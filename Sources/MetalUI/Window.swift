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

    /// Raw input, for whatever no element claimed.
    ///
    /// **The window's fallback, not its first look — and that sentence is the
    /// correction.** This read "raw input, before any dispatch" and went on to
    /// say `Frame` held no hitbox registry, which was true when it was written
    /// and has not been since scroll regions, hover, active and now `onClick`
    /// landed. Two mechanisms run ahead of it and **claim** the events they
    /// consume: `applyScroll` takes a wheel event that lands on a scroller, and
    /// `dispatchClick` takes a `mouseUp` that completes a click on an element
    /// with a handler. Neither reaches here. Everything else still does —
    /// every key event, every `mouseMoved`, and every press or release that
    /// landed on nothing interactive.
    ///
    /// `updatePointerState` runs ahead of both and claims nothing: hover and
    /// active are side-channel state a later frame reads back, not a delivery.
    ///
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

    /// The hitboxes the most recent frame's prepaint registered, captured
    /// alongside `lastScene` for the same reason: `Frame` dies at the end of
    /// `drawFrameIfNeeded` and an input event may arrive at any point
    /// afterward — a wheel event with no frame in flight to route it, or a
    /// `mouseUp` that must still resolve against the hitboxes the button was
    /// drawn with rather than against whatever the next frame will register.
    ///
    /// **It retains the last frame's `onClick` closures, and nothing clears
    /// it** — a record carries its `Handlers` (see `Hitbox.handlers`), so
    /// whatever a caller's handler captured stays alive for as long as this
    /// window does. That is not a cycle by itself: this is an array of structs
    /// and holds no `Frame`. It becomes one if a *caller* closes over the
    /// window, which is the hazard named at `StyledElement.onClick(_:)`.
    private(set) var lastHitboxes: [Hitbox] = []

    /// The scrolling subset of `lastHitboxes`, in registration order — test
    /// observability, and a **derived view** rather than a second capture.
    ///
    /// There were two lists and two captures; there is now one of each (design
    /// spec §3.1). This accessor exists because "the scrolling ones" is a
    /// question several routing tests ask, and because keeping the tuple shape
    /// lets every assertion written against the old registry keep reading the
    /// same fields. See `Frame.scrollRegions`.
    var lastScrollRegions:
        [(bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis, layer: Int)] {
        lastHitboxes.compactMap { box in
            box.scroll.map { (box.bounds, box.id, $0, box.layer) }
        }
    }

    /// The last known mouse position, `nil` before any mouse event has ever
    /// reached the window. Handed into every `Frame` as `mousePosition`, which
    /// is what `resolveHover(at:)` resolves hover against — see
    /// `Frame.mousePosition`'s own doc comment for why this lives here rather
    /// than on `Frame`.
    ///
    /// **Deliberately STICKY: nothing clears it when the pointer leaves the
    /// window.** `InputEvent` has no `mouseExited` case — only
    /// `.mouseDown`/`.mouseUp`/`.mouseMoved` update this — so an element under
    /// the cursor's last in-window position stays hovered after the cursor
    /// leaves the window entirely, until the next event arrives from inside it.
    ///
    /// **A decision, not an oversight, and the reasoning is the cost of the
    /// alternative.** Closing it means a new `InputEvent.mouseExited` case,
    /// which crosses the `MetalUIPlatform` → `MetalUI` module boundary — the
    /// exact shape that has produced a SIGSEGV or a truncated run with no
    /// summary line four times on this project (CLAUDE.md's "Adding a case to
    /// a public enum … crossing module boundaries" section) — for a case whose
    /// only production reader would be one line clearing this property. Task 6
    /// (hover/active infrastructure) is not the task that should widen
    /// `InputEvent`'s surface for a single caller; a future task adding a real
    /// `mouseExited`-driven feature (a tooltip dismissal, say) can add the case
    /// and wire this in the same change, with a reason beyond "tidiness" to
    /// justify the risk.
    ///
    /// **What this costs, stated plainly**: `Task-11`'s human verification of
    /// hover should report on this specifically — move the pointer over an
    /// interactive element, then off the window entirely, and check whether
    /// the element still reads as hovered. Expected today: yes, until the next
    /// in-window mouse event.
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
            // Click dispatch, below, is a separate mechanism built *on top of*
            // that state rather than part of it — which is exactly why the
            // next line exists.
            //
            // **`active` is read HERE, before `updatePointerState`, and this
            // one line is the difference between clicks working and clicks
            // silently never firing.** That method's `.mouseUp` case clears
            // `active` unconditionally, and it runs first and unconditionally
            // — so a dispatcher that asked `self.active` at release time would
            // read `nil` every time, with every hitbox correct, every handler
            // registered and nothing anywhere to indicate a fault. Measured on
            // exactly that spelling before this line existed: all eight click
            // tests in `InputDispatchTests` at the time stayed red, while
            // `onlyABoxWithAHandlerRegistersAHitbox` — the one that checks
            // registration rather than dispatch — stayed green.
            //
            // Handing the pressed id forward, rather than moving dispatch
            // above `updatePointerState`, is deliberate: the handler then runs
            // in the world the release has already produced — `active` is
            // `nil`, `lastMousePosition` is the release point — which is what
            // a handler that reads either would expect.
            let pressed = self.active
            self.updatePointerState(event)
            // Scroll routing runs before the window's general `onInput`, and
            // claims the event outright when it hits a region — there is no
            // scroll chaining (see `applyScroll`'s doc comment), so a claimed
            // wheel event does not also reach whoever opened the window.
            if case .scrollWheel(let scroll) = event, self.applyScroll(scroll) {
                self.setNeedsRedraw()
                return true
            }
            // After scroll routing and before the raw handler, on the same
            // footing: an element that consumed the point consumed the event.
            if self.dispatchClick(event, pressedBefore: pressed) {
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

    /// Applies a wheel delta to the topmost **opaque hitbox** under the
    /// pointer, if that hitbox is a scroller.
    ///
    /// **One list, one ranking** (design spec §3.1). This used to walk a
    /// separate `lastScrollRegions` with its own copy of the ranking closure;
    /// it now calls `topmostOpaqueHitbox(in:at:)` — the single copy — against
    /// the same list `mouseDown` resolves against. `lastHitboxes` is in
    /// prepaint order, outermost first, so the last match among equal layers is
    /// the most deeply nested hitbox containing the point, which is the
    /// visually topmost one.
    ///
    /// **An opaque hitbox that is NOT a scroller swallows the event**, which is
    /// the entire point of the fold and the limitation three milestones
    /// recorded: before it, a non-scrolling `Deferred` scrim registered nothing
    /// a wheel event could see, so the list underneath a modal scrolled through
    /// it. The walk stops at the topmost opaque record whatever that record is;
    /// it does not keep descending looking for something scrollable.
    ///
    /// **It is CLAIMED rather than merely dropped**, and the two are different.
    /// Returning `false` here would leave an event that landed on an element
    /// which consumed the point being re-offered to the window's own fallback
    /// handler as though nothing had taken it — half a swallow, the shape
    /// ruling AP-I warns about for the portal's two halves. So the answer is
    /// "this was consumed", and nothing scrolled.
    ///
    /// **What it costs, and something in production pays it now.** That
    /// sentence read "nothing in production pays it yet" until `onClick`
    /// landed: `StyledElement.onClick(_:)` registers this framework's first
    /// non-scrolling production hitbox, opaque, so **a click target inside a
    /// `ScrollView` swallows that scroller's wheel over its own rect** where a
    /// browser would scroll (a wheel event bubbles up the DOM to the first
    /// scrollable ancestor). Accepted, not fixed here, and pinned by
    /// `aClickTargetInsideAScrollViewSwallowsTheWheel` so the cost is a
    /// decision a reader can find. Opaque was not optional: a non-opaque click
    /// target would stop a `Deferred` scrim swallowing clicks aimed at what it
    /// covers, which is the sibling property of the wheel swallow this
    /// milestone's exit criterion 4 is about.
    ///
    /// **The named fix, so whoever needs it is not starting from a mystery.**
    /// A wheel should stop at an opaque hitbox only when that hitbox is on a
    /// **higher layer** than the topmost *scroller* under the same point. That
    /// distinguishes the two cases with no ancestor walk and no new field:
    /// `Deferred` hoists a scrim to the root layer, so it outranks the scroller
    /// it covers and rightly swallows; a button inside a `ScrollView` shares
    /// its scroller's layer, so it would not. Concretely: find the topmost
    /// opaque record as now, and — when it is not itself a scroller — look for
    /// the topmost scroller under the same point and prefer it whenever its
    /// layer is not lower. It is deliberately NOT implemented here, because
    /// this method is the site of two shipped intermittent defects that only a
    /// human found, and it does not get an unreviewed refinement bolted on in a
    /// task about click handlers. Whoever makes the change inverts that test.
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
    /// record within one layer — decided exactly as before, since the index is
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
    /// **A wheel event arriving before the first frame finds `lastHitboxes`
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
    /// carrying `axis` on the registration (`Hitbox.scroll`) rather than
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
        guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: event.position) else {
            return false
        }
        let region = lastHitboxes[index]
        // Opaque, and not a scroller: it consumed the point, so the event stops
        // here rather than falling through to whatever it covers.
        guard let axis = region.scroll else { return true }
        let componentDelta = axis == .horizontal ? event.delta.x : event.delta.y
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
    /// **But the clear below is click dispatch's whole hazard**, so read this
    /// before reordering anything at the call site: `dispatchClick` needs the
    /// id `active` held *before* this method ran, and gets it as a parameter
    /// captured at the `onInput` hook. Moving that capture after this call, or
    /// making `dispatchClick` read `self.active` itself, makes every click
    /// silently do nothing.
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

    /// Runs the `onClick` of the element that was **pressed and released on**,
    /// and reports whether it did (design spec §3.5, framework spec §8.2).
    ///
    /// **A click is press-in-then-release-on-the-same-element, not "a `mouseUp`
    /// landed somewhere".** So this resolves the hitbox under the release point
    /// and requires it to own the same `GlobalElementID` that `mouseDown` made
    /// active. A press that leaves the element and returns still fires, which
    /// is §3.4's stated reason for keying `active` by `GlobalElementID` rather
    /// than by a per-frame index: nothing about the excursion is recorded, so
    /// there is nothing for the return to undo.
    ///
    /// **`pressed` is a parameter and not `self.active`, and that is the one
    /// thing to get right here** — see the capture at the `onInput` hook, where
    /// the ordering that makes it necessary lives.
    ///
    /// **Against `lastHitboxes`, exactly as `mouseDown` resolves** — there is
    /// no frame in flight when an input event arrives, only the record of the
    /// one most recently drawn, and the handler set rides on that same record
    /// (`Hitbox.handlers`) rather than in a second list captured beside it. So
    /// a handler registered on frame N runs for an event arriving before frame
    /// N+1, and it is that frame's closure rather than an older one.
    ///
    /// **One handler, no chaining.** Dispatch stops at the topmost opaque
    /// hitbox: a container's `onClick` never sees a click that landed on a
    /// child with its own, because a `Hitbox` carries no parent link to bubble
    /// through. Design spec §3.5 cuts the *capture* phase and says why; the
    /// absence of bubbling past the first hit is the same shape as
    /// `applyScroll`'s absent scroll chaining, and closing it means putting
    /// ancestry on the registration rather than changing this function.
    ///
    /// **It CLAIMS the event**, for `applyScroll`'s reason: re-offering a
    /// release that an element consumed to the window's own fallback handler
    /// would be half a swallow. A release that ran no handler is not claimed
    /// and falls through unchanged, which is every event in every window that
    /// has no `onClick` in it.
    private func dispatchClick(_ event: InputEvent,
                               pressedBefore pressed: GlobalElementID?) -> Bool {
        guard case .mouseUp(let mouse) = event, let pressed else { return false }
        guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position) else {
            return false
        }
        let hit = lastHitboxes[index]
        guard hit.id == pressed, let handler = hit.handlers.onClick else { return false }
        handler()
        return true
    }

    /// The `GlobalElementID` owning the topmost opaque hitbox under `point`,
    /// from the most recently drawn frame's registrations.
    ///
    /// **`topmostOpaqueHitbox(in:at:)`, the one ranking, against the window's
    /// own copy of the list.** `Frame.topmostHitbox(at:)` cannot answer this
    /// for `mouseDown` — the frame that built `lastHitboxes` is long gone by
    /// the time an input event arrives — so the list, not the closure, is what
    /// differs between the two call sites. There were three copies of that
    /// closure before this task and there is one now.
    private func topmostHitboxOwner(at point: Point<Pixels>) -> GlobalElementID? {
        topmostOpaqueHitbox(in: lastHitboxes, at: point).map { lastHitboxes[$0].id }
    }
}
