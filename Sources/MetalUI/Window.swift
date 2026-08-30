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
    ///
    /// **Internal rather than private**, for `lastScene`'s reason: a wheel test
    /// has to read back the `ScrollState` `applyScroll` wrote, and there is no
    /// other window through which to see it. `@testable import MetalUI` reaches
    /// it from `Tests/MetalUITests`.
    let stateTable = StateTable()

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
    /// **Nothing evicts from it, and a caller would make things WORSE rather
    /// than better** — which is a mechanism a reader can check, not a milestone
    /// to wait for. `GlyphAtlas.evictUnusedSince` exists, works and is guarded;
    /// calling it here every frame would make the atlas fill *faster*, because
    /// the shelf packer never revisits a closed shelf: an evicted glyph's
    /// pixels stay resident and unreachable, and the next frame that wants it
    /// packs a **second** copy further down. Eviction is a net gain only once
    /// something reclaims the space — a repacker, or a whole-atlas rebuild —
    /// and that is a task, not a call site.
    ///
    /// **Read the consequence with it, because the two are one fact.** The
    /// atlas is therefore **grow-only**, and when it is full `Frame.draw`
    /// **silently drops** the glyphs that will not fit: a window showing an
    /// unbounded stream of *distinct* glyphs loses text with no error
    /// anywhere. CLAUDE.md's inert table carries the same story.
    ///
    /// **Internal rather than private**, for `lastScene`'s reason: a window that
    /// built a *fresh* atlas per frame would produce identical pixels on every
    /// frame the suite renders, so nothing observable from outside distinguishes
    /// it. `currentGeneration` does, and
    /// `aWindowKeepsOneAtlasAcrossFrames` reads it.
    private(set) var glyphAtlas = GlyphAtlas(width: Window.atlasExtent,
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

    /// The scroll regions the most recent frame's prepaint registered, in
    /// registration order, captured alongside `lastScene` for the same reason:
    /// `Frame` dies at the end of `drawFrameIfNeeded`, and a wheel event may
    /// arrive at any point afterward.
    private(set) var lastScrollRegions:
        [(bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis, layer: Int)] = []

    /// The hitboxes the most recent frame's prepaint registered, captured
    /// alongside `lastScrollRegions` for the same reason: `Frame` dies at the
    /// end of `drawFrameIfNeeded` and a mouse event may arrive at any point
    /// afterward — in particular `mouseUp`, which must still resolve against
    /// the hitboxes the button was drawn with, not against whatever the next
    /// frame will register.
    private(set) var lastHitboxes: [Hitbox] = []

    /// The last known mouse position, `nil` before any mouse event has ever
    /// reached the window. Handed into every `Frame` as `mousePosition`, which
    /// is what `resolveHover(at:)` resolves hover against — see
    /// `Frame.mousePosition`'s own doc comment for why this lives here rather
    /// than on `Frame`.
    private var lastMousePosition: Point<Pixels>?

    /// The element holding "active" state — the hitbox that received
    /// `mouseDown` and has not yet seen `mouseUp` (design spec §3.4).
    ///
    /// **Keyed by `GlobalElementID`, not `HitboxID`, and owned here rather than
    /// by `Frame`, for the same reason.** Active must survive the frames
    /// between the two events — including one in which the element holding it
    /// is rebuilt with a fresh, differently-indexed hitbox list — and a `Frame`
    /// is discarded at the end of every `drawFrameIfNeeded`. `internal` rather
    /// than `private`, on `lastScene`'s footing: a test reads it back through
    /// `@testable import MetalUI`.
    private(set) var active: GlobalElementID?

    /// The most recent display-link tick, in seconds — `0` until the first
    /// tick arrives. Carried into every `Frame` as its `timestamp` (spec §8 of
    /// the clipping/scroll design): a borrowed M4 primitive, read once here so
    /// every element in one frame sees the same instant rather than each
    /// sampling a wall clock independently.
    private var lastTick: Double = 0

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

        // §2.6: a `@State` write must reach a window even while its display
        // link is paused (idle, then click). This hook is the ENTIRE
        // production mechanism — `stateTable.isDirty` has no reader anywhere
        // in this file or in `StateTable` itself; see its own doc comment.
        // Captured weakly: `self` owns `stateTable`, so a strong capture here
        // would be a retain cycle.
        stateTable.onWrite = { [weak self] in self?.setNeedsRedraw() }

        platformWindow.onResize = { [weak self] _, _ in self?.setNeedsRedraw() }
        platformWindow.onAppearanceChange = { [weak self] appearance in
            // Assigning drives `theme`'s `didSet`, which is what marks the
            // window dirty — §7.9's "swap the active theme and mark §4.4's
            // dirty flag".
            self?.theme = Theme.forAppearance(appearance)
        }
        platformWindow.onInput = { [weak self] event in
            guard let self else { return false }
            // Hover and active tracking run first and unconditionally, and
            // never claim the event: they are side-channel state a later
            // frame's `paint` reads back (§3.3, §3.4), not a form of dispatch.
            // Click dispatch is a separate, later mechanism (§3.5/design spec
            // §8.2's "cut, deliberately" list) built on top of this state, not
            // part of it.
            self.updatePointerState(event)
            // Scroll routing runs before the window's general `onInput`, and
            // claims the event outright when it hits a region — there is no
            // scroll chaining (see `applyScroll`'s doc comment), so a claimed
            // wheel event does not also reach whoever opened the window.
            if case .scrollWheel(let scroll) = event, self.applyScroll(scroll) {
                self.setNeedsRedraw()
                return true
            }
            let handled = self.onInput?(event) ?? false
            self.setNeedsRedraw()
            return handled
        }
        // Tests pass false so frame counts stay deterministic: a running link
        // could tick between assertions and inflate `framesDrawn`.
        if startsDisplayLink {
            platformWindow.startDisplayLink { [weak self] t in
                self?.lastTick = t
                self?.drawFrameIfNeeded()
            }
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
        // Cleared HERE, before `renderRoot` runs below — not after the frame
        // is built. **This ordering has no production consequence**: a
        // `@State` write made during `renderRoot` fires `onWrite` →
        // `setNeedsRedraw()` regardless of where this call sits, nothing
        // clears `needsRedraw` again before this function returns, so the
        // write is unswallowable either way. What the ordering actually
        // protects is `isDirty` itself, which is otherwise-inert test
        // observability (see `StateTable.isDirty`'s doc): clearing it AFTER
        // `renderRoot` would raise it during the render and immediately
        // clear it again on the next line, so a test reading it back would
        // never see a write made during that frame. Clearing first keeps
        // that observable coherent with the "a write during a frame is not
        // lost" claim it exists to let a test check.
        stateTable.clearDirty()

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
                          theme: theme,
                          timestamp: lastTick,
                          mousePosition: lastMousePosition,
                          activeElement: active)
        renderRoot(frame)
        let scene = frame.finalizedScene()
        lastScene = scene
        lastScrollRegions = frame.scrollRegions
        lastHitboxes = frame.hitboxes
        // An element asked for another frame — an animation in progress. Marking
        // dirty here (rather than leaving the window to go clean) is what keeps
        // the display link running: without it, a fade stops the instant the
        // last input event stops arriving, because `needsRedraw` above already
        // went false for this pass and nothing else would flip it back.
        if frame.wantsAnotherFrame { setNeedsRedraw() }

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
        //
        // **This method commits and never waits, and `upload` is safe anyway —
        // but only because of an invariant `Renderer` maintains, not because of
        // anything here.** There is no semaphore on this path, so frame N-1's
        // draw may still be sampling the atlas texture while this call runs.
        // `Renderer.atlasTextureWasEncoded` is what makes that harmless: a
        // texture is written only while it has never been bound, and a dirty
        // upload after an encode allocates a replacement. **If you add an
        // in-flight semaphore here, that invariant becomes redundant rather than
        // wrong** — do not remove it in the same change, because the atlas is
        // the only persistent CPU-mutated GPU resource in the renderer and it
        // would be the only thing standing between a torn glyph and a frame.
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

    /// Applies a wheel delta to the topmost scroll region under the pointer.
    ///
    /// **Highest layer first, then reverse registration order.** The second
    /// half is the rule §8.1 states for the general hit-test registry this one
    /// is scoped down from: "dispatch walks them in reverse so the topmost
    /// opaque hit wins." `lastScrollRegions` is in prepaint order — outermost
    /// first, since a `ScrollView` registers itself before descending into its
    /// content — so the last match among equals is the most deeply nested
    /// region containing the point, which is the visually topmost one.
    ///
    /// **The layer is what registration order cannot express, and it is the
    /// whole reason `PrepaintPass.deferred` hoists at all.** A `Deferred`
    /// subtree paints above every sibling regardless of where it was declared,
    /// so a scroller inside one can register *before* a scroller it paints on
    /// top of; under registration order alone the covered scroller would take
    /// the wheel while the visible one sat inert. Measured before this was
    /// fixed, on two overlapping full-window scrollers with the deferred one
    /// declared first: the modal painted on top and the background took every
    /// event. Ordering by `(layer, registration index)` puts the two rules in
    /// the order that makes the visible thing win, and leaves ties — every
    /// region within one layer — decided exactly as before, since the index is
    /// unique and no two candidates can compare equal.
    ///
    /// Momentum deltas are applied identically to direct ones — `isMomentum` is
    /// read by nothing here, on purpose. AppKit already ran the physics; a
    /// second simulation on top of an already-physical delta would fight it,
    /// and building our own inertia now means building it twice — once more
    /// for iOS and for programmatic scrolling, which have no momentum phase at
    /// all.
    ///
    /// **Not handled: scroll chaining.** An inner region already at its scroll
    /// limit does not pass the remainder of the delta to an ancestor region —
    /// the way, say, a nested list in a page does in a browser. That is a
    /// dispatch concern belonging with the general hit-test work (§8.1), and
    /// this method claims the topmost match outright rather than falling
    /// through; its absence is a decision recorded here, not an oversight
    /// waiting to be found as a bug.
    ///
    /// **A wheel event arriving before the first frame finds `lastScrollRegions`
    /// empty and returns `false`.** That is correct, not a startup race to
    /// close: there is no layout yet for a region to have been registered
    /// against, so there is nothing to route the event to.
    ///
    /// **The write below is deliberately unbounded, and the thing that bounds
    /// it is `ScrollView.resolvedOffset`, not anything here.** This method has
    /// the region's rect but not its content node's size, and no layout at all
    /// for the frame it is about to cause, so it cannot know where the end is;
    /// the next frame clamps the stored value against the layout it just
    /// resolved and writes the clamped number back. **Do not "simplify" that
    /// write-back into a plain read** — a read-only clamp is what shipped, and
    /// it let a gesture against either end bank an invisible excess that every
    /// reversing event then had to unwind before the view moved, which is the
    /// defect `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind` pins.
    ///
    /// Clamping *here* instead was implemented and reverted: it needs the
    /// ceiling carried on the registration, and it makes a region with **zero**
    /// travel — a `ScrollView` whose content exactly fits — refuse to record an
    /// offset at all, which reddens
    /// `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove`, a routing test
    /// that reads routing off exactly such a region's offset.
    ///
    /// **The delta component is chosen by the region's OWN axis, not fixed to
    /// `y`.** A `.horizontal` `ScrollView` stores its offset along `x`
    /// (`ScrollView.delta(_:)`) and must be driven by `delta.x`; a `.vertical`
    /// one by `delta.y`. This was wrong for one commit — every region read
    /// `delta.y` regardless of axis, so a horizontal `ScrollView` responded to
    /// vertical wheel motion and ignored horizontal motion entirely — fixed by
    /// carrying `axis` on the registration (`Frame.scrollRegions`) rather than
    /// guessing it here.
    ///
    /// **Semantics are narrow on purpose: one axis, no borrowing the other's
    /// delta.** A horizontal region takes `delta.x` only and does not move on
    /// a vertical wheel, and a vertical region the reverse — there is no
    /// fallback that lets a plain vertical wheel drive a horizontal list, the
    /// way some web UIs do. AppKit already remaps components for shift-scroll
    /// on trackpads that report it, so this layer does not need to. Whether a
    /// wheel-only device should be able to drive a horizontal list at all is a
    /// UX decision with real trade-offs, and it is deliberately left to
    /// whoever owns that decision rather than made here by default.
    private func applyScroll(_ event: ScrollEvent) -> Bool {
        let hit = lastScrollRegions.enumerated()
            .filter { contains($0.element.bounds, event.position) }
            .max { ($0.element.layer, $0.offset) < ($1.element.layer, $1.offset) }
        guard let region = hit?.element else { return false }
        let componentDelta = region.axis == .horizontal ? event.delta.x : event.delta.y
        stateTable.withState(region.id, initial: ScrollState()) {
            // Natural scrolling: a positive scrollingDelta means content moves
            // in the positive direction (the user's fingers moved that way),
            // so the offset — how far the content has scrolled away from its
            // start — decreases.
            $0.offset -= Double(componentDelta.value)
            // Stamped from the EVENT's own timestamp, not `lastTick`. The
            // display link pauses while the window is clean (spec §4.4), so
            // after an idle period `lastTick` is however many seconds stale —
            // a wheel event arriving then would be stamped with that stale
            // instant, and the next frame's `age = timestamp - lastScrollTime`
            // would already exceed the fade duration, suppressing the
            // indicator on the very frame meant to show it. `event.timestamp`
            // and `PaintPass.timestamp` (from the display link) share
            // `mach_absolute_time`'s base, so the subtraction stays valid —
            // and the event's own time is also simply more current than
            // `lastTick`, which is the *previous* frame's instant, even when
            // not idle.
            $0.lastScrollTime = event.timestamp
        }
        return true
    }

    /// Updates `lastMousePosition` and `active` from a raw input event —
    /// design spec §3.3 (the position hover resolves against next frame) and
    /// §3.4 (active).
    ///
    /// **Side-effect only: never claims the event.** Unlike `applyScroll`,
    /// which returns whether it routed the wheel delta somewhere, this runs
    /// unconditionally for every event and always lets dispatch continue —
    /// hover and active are state a later `paint` reads back, not a target an
    /// event can be delivered to. Click dispatch is separate (§3.5) and is not
    /// this method's concern.
    ///
    /// **`mouseUp` clears `active` unconditionally**, whatever is under the
    /// pointer at that instant — not only when the release lands back on the
    /// element that was pressed. That is what "held until `mouseUp`" (§3.4)
    /// means: a press that leaves the hitbox and returns stays active for
    /// every mouse-moved event along the way, and is released by the up event
    /// alone, regardless of where the pointer is when it fires.
    ///
    /// `mouseDown` resolves against `lastHitboxes`, **not** against a fresh
    /// `Frame` — there is no frame in flight when an input event arrives, only
    /// the record of the one most recently drawn. See `topmostHitboxOwner(at:)`.
    private func updatePointerState(_ event: InputEvent) {
        switch event {
        case .mouseDown(let mouse):
            lastMousePosition = mouse.position
            active = topmostHitboxOwner(at: mouse.position)
        case .mouseUp(let mouse):
            lastMousePosition = mouse.position
            active = nil
        case .mouseMoved(let mouse):
            lastMousePosition = mouse.position
        default:
            break
        }
    }

    /// The `GlobalElementID` owning the topmost opaque hitbox under `point`,
    /// from the most recently drawn frame's registrations.
    ///
    /// **Deliberately the same ranking as `Frame.topmostHitbox(at:)` and
    /// `applyScroll`'s own walk**: `(layer, registration index)` over the
    /// containing opaque candidates. `Frame.topmostHitbox(at:)` itself cannot
    /// answer this for `mouseDown` — the frame that built `lastHitboxes` is
    /// long gone by the time an input event arrives — so the same closure is
    /// restated here against the window's own copy of the list, exactly as
    /// `applyScroll` restates it against `lastScrollRegions`.
    private func topmostHitboxOwner(at point: Point<Pixels>) -> GlobalElementID? {
        lastHitboxes.enumerated()
            .filter { $0.element.bounds.contains(point) && $0.element.opaque }
            .max { ($0.element.layer, $0.offset) < ($1.element.layer, $1.offset) }
            .map { $0.element.id }
    }

    /// Whether `point` falls within `bounds`, half-open on the max edges. A
    /// small free function rather than reaching for `Bounds.contains(_:)`
    /// inline in `applyScroll` above, purely so that closure reads as
    /// "does this region contain the point" at a glance.
    private func contains(_ bounds: Bounds<Pixels>, _ point: Point<Pixels>) -> Bool {
        bounds.contains(point)
    }
}
