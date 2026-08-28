import Metal
import MetalUICore
import MetalUIRender
import MetalUIPlatform
import MetalUIText

@MainActor
public final class Window {
    private let platformWindow: any PlatformWindow
    private let renderer: Renderer

    /// Builds and walks the root element for one frame.
    ///
    /// **The element type is erased here and nowhere else, and this is not
    /// §4.6's boxing.** `Frame.render` is generic over the root, so the window
    /// would otherwise have to be `Window<Root>` — and `App.windows` would then
    /// be a heterogeneous array it could not hold. Closing over the builder
    /// keeps one existential per *window* instead of one per element: inside the
    /// closure `content()` still returns its concrete type and `frame.render`
    /// still specializes on it, so `Column { Box(); Box() }` reaches the engine
    /// as `Column<Pair<Box<EmptyGroup>, Box<EmptyGroup>>>` with nothing boxed.
    ///
    /// It rebuilds the root **every frame**, which is §4.1's contract — "the
    /// tree is rebuilt from scratch each frame; there is no diffing and no
    /// persistent node graph". State that must survive lives in `stateTable`.
    private let renderRoot: @MainActor (Frame) -> Void

    /// The cross-frame state table (§4.3), owned **here** rather than by
    /// `Frame`.
    ///
    /// A `Frame` lives for one frame and this must outlive it. A window that let
    /// each frame construct its own would hand every element fresh state on
    /// every frame — a running app that silently forgets, with the whole suite
    /// still green, because a single-frame test cannot tell the two apart.
    private let stateTable = StateTable()

    /// The shaping cache (spec §3.2), owned here for the same reason
    /// `stateTable` is: a `Frame` lives for one frame and a cache that died with
    /// it would re-shape every string through CoreText on every frame, with the
    /// whole suite green. See `Frame.shapingCache`.
    ///
    /// It is not swept the way `stateTable` is. Its key is *content*, not
    /// element identity, so an entry is valid for as long as the string, font
    /// and width recur — and nothing yet evicts. A window showing an unbounded
    /// stream of distinct strings therefore grows unboundedly; eviction is the
    /// atlas's problem first (spec §3.5) and this cache's next, and neither is
    /// M2's.
    private let shapingCache = ShapingCache()

    /// The glyph atlas (spec §3.5), owned here for the same reason
    /// `shapingCache` is — a `Frame` lives for one frame and an atlas that died
    /// with it would re-rasterize every glyph through `CTFontDrawGlyphs` and
    /// re-upload a whole texture on every frame, with the whole suite green.
    /// See `Frame.glyphAtlas`.
    ///
    /// **Nothing evicts from it, and that is a deliberate omission rather than
    /// an oversight.** `GlyphAtlas.evictUnusedSince` exists and works, and
    /// calling it here every frame would make text *worse*: the shelf packer
    /// never revisits a closed shelf, so an evicted glyph's pixels stay
    /// resident and unreachable, and the next frame that wants it packs a
    /// second copy further down the atlas. Eviction is only a net gain once
    /// something can reclaim the space — a repacker, or a whole-atlas rebuild —
    /// and neither is M2's. Until then the atlas is a grow-only cache, and a
    /// window showing an unbounded stream of *distinct* glyphs fills it, after
    /// which `Frame.draw` silently drops the ones that will not fit. That is
    /// recorded in CLAUDE.md's inert table with this mechanism named.
    private let glyphAtlas = GlyphAtlas(width: Window.atlasExtent,
                                        height: Window.atlasExtent)

    /// The atlas is square and this is its side, in **device pixels**.
    ///
    /// 1024 holds on the order of two thousand 13pt glyphs at 2x — every
    /// distinct character of a UI's chrome across four subpixel variants, with
    /// room to spare — for one megabyte of R8 on the CPU and the same on the
    /// GPU. It is `internal` rather than private because `Frame`'s default
    /// argument uses it: a `Frame` built without a window (every layout test)
    /// gets an atlas of exactly the production size, so a test cannot pass
    /// against a packer that only fits in a larger one.
    static let atlasExtent = 1024

    /// The active theme (spec §7.9).
    ///
    /// Setting it marks §4.4's dirty flag, so a theme swap repaints. The
    /// equality guard is not an optimisation detail — `onAppearanceChange` can
    /// fire for a change that does not cross the light/dark line (a tint or
    /// contrast change AppKit reports through the same hook), and a window that
    /// repainted for each of those would wake the display for nothing.
    public var theme: Theme {
        didSet {
            guard theme != oldValue else { return }
            setNeedsRedraw()
        }
    }

    /// Raw input, before any dispatch.
    ///
    /// **Not M3's hit-testing.** `Frame` holds no hitbox registry and
    /// `PrepaintPass` exposes no way to add one, so nothing routes an event to
    /// an element; this hands the whole event to whoever opened the window.
    /// Returning `true` means handled. The window marks itself dirty either
    /// way, because it cannot know whether the handler changed anything.
    public var onInput: ((InputEvent) -> Bool)?

    /// Set by input, resize, appearance or content invalidation. A frame is
    /// built only when this (or an active animation) says so — an idle window
    /// costs nothing (spec 4.4).
    public private(set) var needsRedraw: Bool = true

    /// Test observability: how many frames actually reached the GPU.
    public private(set) var framesDrawn: Int = 0

    /// The primitives the most recent frame handed to the renderer.
    ///
    /// Test observability, and internal rather than public: what the GPU
    /// received cannot be read back from an on-screen drawable, so without this
    /// the only assertions available about a real window's output are "a frame
    /// happened". `@testable import MetalUI` reaches it.
    private(set) var lastScene = Scene()

    init<Root: Element>(platformWindow: any PlatformWindow,
                        renderer: Renderer,
                        startsDisplayLink: Bool = true,
                        content: @escaping @MainActor () -> Root) {
        self.platformWindow = platformWindow
        self.renderer = renderer
        self.theme = Theme.forAppearance(platformWindow.appearance)
        self.renderRoot = { frame in
            var root = content()
            frame.render(&root)
        }

        platformWindow.onResize = { [weak self] _, _ in self?.setNeedsRedraw() }
        platformWindow.onAppearanceChange = { [weak self] appearance in
            // Assigning drives `theme`'s `didSet`, which is what marks the
            // window dirty — §7.9's "swap the active theme and mark §4.4's
            // dirty flag".
            self?.theme = Theme.forAppearance(appearance)
        }
        platformWindow.onInput = { [weak self] event in
            guard let self else { return false }
            let handled = self.onInput?(event) ?? false
            self.setNeedsRedraw()
            return handled
        }
        // Tests pass false so frame counts stay deterministic: a running link
        // could tick between assertions and inflate `framesDrawn`.
        if startsDisplayLink {
            platformWindow.startDisplayLink { [weak self] in self?.drawFrameIfNeeded() }
        }
    }

    public func setNeedsRedraw() {
        needsRedraw = true
        platformWindow.setDisplayLinkPaused(false)
    }

    public func drawFrameIfNeeded() {
        guard needsRedraw else {
            // Nothing to do: let the display idle rather than spinning.
            platformWindow.setDisplayLinkPaused(true)
            return
        }
        needsRedraw = false

        let surfaceFrame: SurfaceFrame
        do {
            surfaceFrame = try platformWindow.surface.nextFrame()
        } catch {
            // No drawable is an ordinary condition. Stay dirty and retry.
            setNeedsRedraw()
            return
        }

        guard let view = surfaceFrame.views.first,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else {
            setNeedsRedraw()
            return
        }

        // Layout is offered the window's **logical** size, taken from the
        // platform window rather than divided out of `view.viewport`. The
        // viewport is in device pixels, so recovering points from it means
        // dividing by the scale factor — and a scale factor of 0 from a backend
        // that has not finished configuring itself would turn every layout
        // extent into an infinity, which the flex engine propagates silently
        // rather than trapping. `contentSize` is the number the windowing system
        // already reports in the unit layout wants.
        let frame = Frame(contentSize: platformWindow.contentSize,
                          scaleFactor: surfaceFrame.scaleFactor,
                          stateTable: stateTable,
                          shapingCache: shapingCache,
                          glyphAtlas: glyphAtlas,
                          theme: theme)
        renderRoot(frame)
        let scene = frame.finalizedScene()
        lastScene = scene

        // **Before `encode`, and the ordering is the whole point.** Paint has
        // just packed whatever glyphs this frame needed and the scene holds
        // `AtlasSlot`s pointing at them; `encode` draws against whatever
        // texture the renderer has. Uploading afterwards would leave the *first*
        // frame of any new glyph sampling a texture that does not contain it —
        // blank text that fixes itself on the next redraw, which is the
        // intermittent failure spec §4.2 names and which no amount of staring
        // at a second frame reveals.
        //
        // Unconditional rather than guarded on `scene.glyphs.isEmpty`: only the
        // atlas knows which pixels changed, it already answers "nothing" with a
        // `nil` dirty rect, and a guard here would couple the upload to a
        // property of the scene that can drift from it.
        renderer.upload(glyphAtlas)

        do {
            try renderer.encode(scene, view: view, in: commandBuffer)
        } catch {
            setNeedsRedraw()
            return
        }

        platformWindow.surface.present(surfaceFrame, in: commandBuffer)
        commandBuffer.commit()
        framesDrawn += 1
    }
}
