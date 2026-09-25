import Foundation
import Observation
import MetalUICore
import MetalUIPrimitives
import MetalUIPlatform
#if canImport(MetalUIText)
import MetalUIText
#endif
import MetalUITextSystem

@MainActor
public final class Window {
    private let platformWindow: any PlatformWindow

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
    private let shapingCache: ShapingCache

    /// The text engine this window's `Text`s measure and draw through (ruling
    /// TS-A): the app's choice, made once when the window opens, or the
    /// CoreText system over ``shapingCache``.
    private let textSystem: any TextSystem

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

    /// The root environment every scope in this window starts from (ruling
    /// EV-H): `isEnabled`, `layoutDirection`, `locale`, `dynamicTypeSize` and
    /// custom keys, at `EnvironmentValues()`'s defaults (with the current
    /// locale, below) until set.
    ///
    /// **Every write dirties the window, a no-op included.** Unlike `theme`
    /// above there is no equality guard, and there cannot be one:
    /// `EnvironmentValues` stores custom keys as `Any`. Constraining keys to
    /// `Equatable` would diverge from SwiftUI's unconstrained `Value`. So write
    /// from input, never from a phase — a phase-time write every frame keeps
    /// the display link awake, `@State`'s rule. Pinned as a stated cost by
    /// `theWindowsEnvironmentReachesTheFrameAndASetRepaints`.
    ///
    /// **Three fields are not taken from here** (ruling EV-AB; two before
    /// it). The frame re-stamps `theme` from `theme` above and `displayScale`
    /// from the scale the frame is drawn at (`WindowRenderer.beginFrame()`'s,
    /// ruling EV-AA; `pixelLength` derives from it), and this window stamps
    /// `controlActiveState` from `controlActiveState` below, over this value, at
    /// every draw. So `window.environment.theme = .dark` (which compiles inside
    /// this module), `window.environment.displayScale = 3` and
    /// `window.environment.controlActiveState = .key` (which compile anywhere)
    /// change nothing at the root (`Frame.rootEnvironment`,
    /// `aScopeWriteOfControlActiveStateWinsBelowItAndTheWindowsEnvironmentDoesNot`).
    /// A scope below the root can write all three but `theme`, as in SwiftUI.
    ///
    /// **Starts at `EnvironmentValues()` with `Locale.current` stamped over its
    /// bare locale** (ruling EV-Y): a bare value holds `Locale(identifier: "")`,
    /// as SwiftUI's does, and a window stamps the user's, as a SwiftUI host does.
    public var environment = EnvironmentValues.windowDefault() {
        didSet { setNeedsRedraw() }
    }

    /// The platform window's key state (ruling EV-AB), the root source of
    /// every frame's `controlActiveState`: read from
    /// `PlatformWindow.controlActiveState` at construction and updated through
    /// `PlatformWindow.onControlActiveStateChange`, and stamped over
    /// `environment` at every draw.
    ///
    /// **Guarded, unlike `environment`**: a change repaints and a report of the
    /// state the window already has does not — the platform can report a key
    /// or activation change that leaves this window's state where it was (an
    /// application activation with the window already key), and a window that
    /// repainted for each would wake the display for nothing, `theme`'s reason.
    /// Kept here rather than in `environment` for exactly that: `environment`'s
    /// writes cannot be guarded (EV-H). Pinned by
    /// `theWindowStampsItsPlatformsControlActiveStateAndAChangeRepaints`.
    public private(set) var controlActiveState: ControlActiveState {
        didSet {
            guard controlActiveState != oldValue else { return }
            setNeedsRedraw()
        }
    }

    /// Whether every frame this window builds records its element bounds
    /// (`Frame.recordsElementBounds`), read back through `lastElementBounds`.
    /// **Test observability** for plan task 7's lowering tests through a real
    /// window (`makeLoweredWindow`); no production reader. Off by default, so a
    /// frame pays nothing.
    var recordsElementBounds = false

    /// The most recent frame's `Frame.elementBounds` — empty unless
    /// `recordsElementBounds`. Captured alongside `lastScene`, for its reason.
    private(set) var lastElementBounds: [GlobalElementID: Bounds<Pixels>] = [:]

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

    /// Whether the frame this window last built left an `Animation` still
    /// interpolating — the second half of the binding design spec §4.4 guard,
    /// which M4 spec 1 deliberately left undeclared (ruling `RX-O`: an
    /// always-`false` stored property with no writer is the declared-but-inert
    /// trap, and refusing to declare it was the right call until there was a
    /// writer).
    ///
    /// **It keeps the loop running WITHOUT marking the window dirty**, and that
    /// distinction is the reason this is a second flag rather than a
    /// `setNeedsRedraw()` after the render. `needsRedraw` means "something
    /// changed and has not been drawn"; a window mid-fade has nothing of the
    /// sort — the model is settled, the tree is settled, and only the clock has
    /// moved. Folding the two would make `needsRedraw` permanently true for the
    /// whole of every animation and destroy the only observable that can tell
    /// a dirtying from a redraw.
    ///
    /// **Nothing unpauses the link on this flag's account, and nothing needs
    /// to.** The frame that *starts* an animation is itself drawn because
    /// something dirtied the window (that is what `withAnimation`'s body did),
    /// and `setNeedsRedraw()` unpauses. From there this flag only ever prevents
    /// a pause, which is all a running link requires.
    public private(set) var hasActiveAnimations: Bool = false

    /// Test observability: how many frames actually reached the GPU.
    public private(set) var framesDrawn: Int = 0

    /// How many times the loop has found nothing to do and paused the display
    /// link. Test and debug observability, not API.
    public private(set) var pausesEntered: Int = 0

    /// How many times an `@Observable` change has marked this window dirty,
    /// **excluding** the per-frame sentinel flush.
    ///
    /// This is the only observable that can distinguish "one dirty-marking per
    /// write" from "N of them" — `needsRedraw` is a `Bool` and cannot. It is
    /// what `theObserverSetIsBoundedRegardlessOfFramesDrawn` reads.
    /// **Measured in this tree, not prototyped**: with both `redrawSentinel`
    /// lines commented out, drawing 200 frames and then writing once takes this
    /// delta from 1 to **200** — one dirty-marking per frame drawn since the
    /// last change, exactly the accumulation this property exists to bound.
    ///
    /// Test and debug observability, not API. Delete both counters in the same
    /// change that lands a real profiling story.
    public private(set) var observationDirtyings: Int = 0

    /// The most recent frame's deepest native level
    /// (`LayoutTree.lastNativeLayoutDeepestLevel` — the root's own run, `SA-L`'s
    /// depth), captured alongside `lastScene` because the frame and its tree die
    /// at the end of `drawFrameIfNeeded`. **Test observability** for plan task
    /// 7, stage 6b (`LR-DK` item 2, test 3.3): every production root's depth is
    /// read through a real window.
    private(set) var lastNativeLayoutDeepestLevel = 0

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

    /// The element holding keyboard focus, or `nil` — **window state, because
    /// focus is singular per window** (design spec §4.2).
    ///
    /// Owned here rather than by `Frame` for `active`'s reason and one more:
    /// focus must survive every frame between the two events that move it, and
    /// a `Frame` is discarded at the end of every `drawFrameIfNeeded`. It is
    /// handed into each frame and **read back** afterwards, because the frame
    /// is what discovers that the focused element was not produced.
    ///
    /// **The read-back is guarded, and that is what keeps a concurrent write
    /// from being discarded.** The hand-in and the read-back straddle the whole
    /// of `renderRoot`, so together they are a read-modify-write over a value
    /// `focus(_:)` — public, and called from `MetalUIDemoContent`'s `CounterPanel`
    /// during its own `requestLayout` — can change in between. The frame's
    /// answer is applied only while this property is still what the frame was
    /// handed; see `drawFrameIfNeeded` for why that condition is exactly "the
    /// frame's decision is still about the current focus".
    public private(set) var focusedElement: GlobalElementID?

    /// The focus registry the most recent frame's prepaint built, captured
    /// alongside `lastHitboxes` and for its reason: the frame that built it is
    /// gone by the time a key event arrives, and there is no frame in flight to
    /// ask instead.
    private(set) var lastFocusRegistry = FocusRegistry()

    /// Whether an accessibility client is present, and what this window last
    /// published to it (`WindowAccessibility`, rulings AB-B, AB-M).
    let accessibility = WindowAccessibility()

    /// The focused element and every ancestor of it, **innermost first** —
    /// empty when nothing is focused.
    ///
    /// **Exposed rather than buried inside `dispatchKey`, because Task 10 needs
    /// it and calls no handler.** Design spec §4.3 matches context predicates
    /// innermost-first from the focus chain, which is a different consumer of
    /// the same walk. See `focusChain(from:)`.
    var focusChain: [GlobalElementID] { MetalUI.focusChain(from: focusedElement) }

    /// This window's key bindings (framework spec §8.3).
    ///
    /// **Window-level rather than per-element, because a keymap is a
    /// declaration about the whole window** — a binding predicated on `Editor`
    /// is *scoped* by its context predicate, not by where the keymap was
    /// written. That is what lets a binding fire with nothing focused at all,
    /// which is what the counter demo relies on.
    ///
    /// Assigning **clears any pending two-stroke prefix**: a prefix recorded
    /// against the old bindings means nothing under the new ones.
    public var keymap: Keymap = Keymap() {
        didSet { pendingStroke = nil }
    }

    /// The first stroke of a two-stroke sequence, once one has been seen and
    /// while it is still fresh — framework spec §8.3's pending prefix.
    ///
    /// **Window state rather than keymap state**, because it is a property of
    /// this window's typing history and not of the bindings; a `Keymap` is a
    /// value a caller may share between windows.
    ///
    /// Its age is measured against the *arriving event's* `timestamp`, never
    /// against a clock read here — see `KeyEvent.timestamp` for the bug that
    /// rule exists to avoid.
    private var pendingStroke: PendingStroke?

    /// An action nothing along the focus chain handled.
    ///
    /// **The keyboard's counterpart to `onInput`**, and the reason a keymap
    /// works with nothing focused: the chain is empty, no element handler
    /// exists to run, and the action arrives here. Returning `true` claims the
    /// keystroke; returning `false` (or leaving this `nil`) lets it fall
    /// through to the raw `onKey` bubble and then to `onInput`, so a binding
    /// nobody handles behaves as if it were not bound rather than silently
    /// eating a keypress.
    ///
    /// **What this closure captures is retained by the window, so do not
    /// capture the window** — `StyledElement.onClick(_:)` states the hazard in
    /// full and this is its sharpest form: the closure is stored *on* `Window`,
    /// so `window.onAction = { window.… }` closes the cycle immediately, with
    /// no frame drawn and nothing that ever clears it. Capture `[weak window]`,
    /// or capture the state the handler writes — which is what `@State` is for.
    /// `onInput` above has the identical shape; `MetalUIDemo` writes
    /// `[weak window]` for it.
    public var onAction: ((any Action) -> Bool)?

    /// Moves keyboard focus, or clears it with `nil`.
    ///
    /// **A plain setter with no validation, and the frame is what validates.**
    /// Nothing here checks that `id` names a produced, focusable element —
    /// `Window` has no tree — so focusing something that is not `.focusable()`
    /// this frame is not an error; the next frame's `Frame.resolveFocus()` will
    /// simply clear it. That is the same mechanism that drops focus when a
    /// focused element vanishes, and having one rule rather than two is the
    /// point.
    ///
    /// **Safe to call from inside a frame's own render**, which is what
    /// `MetalUIDemoContent`'s `CounterPanel` does from its `requestLayout` — and the
    /// sentence above is true of an in-frame call as well: the *next* frame
    /// validates it, not this one. That is a property of the guarded read-back
    /// in `drawFrameIfNeeded`, not of this method, and it did not hold until
    /// that guard existed: an unconditional read-back overwrote a concurrent
    /// call with the value the frame had been handed, so an in-frame `focus()`
    /// could never stick at all. See the read-back for the mechanism, and
    /// `focusingFromInsideAFrameSurvivesThatFrame` for the pin.
    ///
    /// **Nothing here focuses anything on its own.** Focus-by-click is a policy
    /// decision this framework has not made: a `mouseDown` on an element with
    /// an `onClick` moves `active` and does *not* move focus. A caller who
    /// wants that behaviour writes it in a handler.
    ///
    /// Marks the window dirty, because focus is visible.
    public func focus(_ id: GlobalElementID?) {
        guard focusedElement != id else { return }
        focusedElement = id
        setNeedsRedraw()
    }

    /// The most recent display-link tick, in seconds — `0` until the first
    /// tick arrives. Carried into every `Frame` as its `timestamp` (spec §8 of
    /// the clipping/scroll design): a borrowed M4 primitive, read once here so
    /// every element in one frame sees the same instant rather than each
    /// sampling a wall clock independently.
    private var lastTick: Double = 0

    /// Written once per frame to flush observation sessions armed by previous
    /// frames. See `RedrawSentinel` for why, with the measurement.
    private let redrawSentinel = RedrawSentinel()

    /// True only for the duration of the sentinel write in
    /// `drawFrameIfNeeded`, so `markDirtyFromObservation` can tell a flush from
    /// a real change.
    ///
    /// **Behaviourally redundant today and kept anyway** — measured: deleting
    /// this guard changes `needsRedraw`, `framesDrawn` and the pause record not
    /// at all, because the `needsRedraw = false` on the line after the flush
    /// already absorbs the spurious dirty. It shows up only in
    /// `observationDirtyings`. **Measured in this tree** (`aFrameThatChangesNoObservedPropertyReportsNoObservationDirtying`,
    /// 200 drawn frames): 0 with the guard, **199** without — one short of 200
    /// because the very first flush has no prior session armed to trip: a
    /// session is armed only by a preceding `withObservationTracking` call
    /// reading `redrawSentinel.tick`, and frame 1 is the first read there ever
    /// is. Frames 2 through 200 each trip the session the frame before armed,
    /// so 199 fire. It is kept because it makes the correctness independent of the
    /// flush happening to run on the main thread, rather than resting on that.
    private var isFlushing = false

    init<Root: Element>(platformWindow: any PlatformWindow,
                        startsDisplayLink: Bool = true,
                        textSystem: (any TextSystem)? = nil,
                        content: @escaping @MainActor () -> Root) {
        let shapingCache = ShapingCache()
        self.shapingCache = shapingCache
        #if canImport(MetalUIText)
        self.textSystem = textSystem ?? CoreTextTextSystem(cache: shapingCache)
        #else
        guard let textSystem else {
            preconditionFailure("a Window needs a TextSystem off Apple platforms: there is no CoreText (ruling XP-B)")
        }
        self.textSystem = textSystem
        #endif
        self.platformWindow = platformWindow
        self.theme = Theme.forAppearance(platformWindow.appearance)
        self.controlActiveState = platformWindow.controlActiveState
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

        // Also the backing-scale path (ruling EV-AA): both platforms report a
        // move between displays through `onResize`, and the next frame's
        // `displayScale` is the drawable's scale that `beginFrame()` returns.
        // Pinned by `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame`.
        platformWindow.onResize = { [weak self] _, _ in self?.setNeedsRedraw() }
        platformWindow.onAccessibilityRequest = { [weak self] request in
            self?.handleAccessibilityRequest(request) ?? false
        }
        platformWindow.onAppearanceChange = { [weak self] appearance in
            // Assigning drives `theme`'s `didSet`, which is what marks the
            // window dirty — §7.9's "swap the active theme and mark §4.4's
            // dirty flag".
            self?.theme = Theme.forAppearance(appearance)
        }
        platformWindow.onControlActiveStateChange = { [weak self] state in
            // Assigning drives `controlActiveState`'s guarded `didSet`, which
            // is what marks the window dirty (ruling EV-AB).
            self?.controlActiveState = state
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
            // Text fields (ruling TI-B): a press on one focuses it and places
            // the caret, a drag from it selects, and committed or marked text
            // goes to the focused one. Ahead of click dispatch — a field has
            // no `onClick` — and of the raw handler.
            if self.dispatchTextInput(event) {
                self.setNeedsRedraw()
                return true
            }
            // After scroll routing and before the raw handler, on the same
            // footing: an element that consumed the point consumed the event.
            if self.dispatchClick(event, pressedBefore: pressed) {
                self.setNeedsRedraw()
                return true
            }
            // The keyboard's turn, on the same footing as the two above: an
            // element that claimed the keystroke consumed the event, and
            // re-offering it to the window's fallback would be half a swallow.
            // It inherits none of the `active` hazard above — a key event falls
            // through `updatePointerState`'s `default: break`.
            //
            // **The keymap goes FIRST, ahead of the raw `onKey` bubble, and
            // the two must not collapse into each other.** A keymap is the
            // declaration of intent and a raw handler is the escape hatch, so a
            // bound keystroke reaches its action and never reaches `onKey`,
            // while an unbound one reaches `onKey` and never troubles the
            // keymap. Swapping these two lines makes every raw handler shadow
            // every binding on the same keystroke; pinned by
            // `aBoundActionRunsBeforeARawOnKeyHandler`.
            if self.dispatchAction(event) {
                self.setNeedsRedraw()
                return true
            }
            // A focused field's editing keys come after the keymap — an app's
            // binding wins, as a menu shortcut does — and before the raw
            // `onKey` bubble (ruling TI-B).
            if self.dispatchTextKey(event) {
                self.setNeedsRedraw()
                return true
            }
            if self.dispatchKey(event) {
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

        // Last, because `register` stores `self` and everything above must
        // have run first. Weak, so this is not a retain and a window nobody
        // else holds still deallocates — see `liveWindows`.
        Window.register(self)
    }

    /// Monotonic count of `setNeedsRedraw()` calls across every window, ever.
    ///
    /// **Not a statistic — it is `withAnimation`'s only way to ask "will there
    /// be a next frame build for this transaction to reach?"** A transaction
    /// is for the frame that results from the mutation inside the body; a body
    /// that dirties nothing produces no such frame, and a transaction parked
    /// for it would otherwise wait indefinitely and apply to whatever happens
    /// to differ on the next frame drawn for any reason at all. See
    /// `withAnimation` for the rule and `Animation.parkedTransaction` for the
    /// measured failure it closes.
    ///
    /// A plain `static var`, not an atomic, for `Frame.nextTreeGeneration`'s
    /// reason: `@MainActor` isolation is what rules out a concurrent
    /// increment, and `UInt64` at one per dirty cannot realistically wrap.
    /// Static rather than per-window because `withAnimation` has no window in
    /// scope — the same constraint that puts the parking slot at module scope.
    static var redrawRequests: UInt64 = 0

    /// Every `Window` still alive, weakly.
    ///
    /// **One caller, one question: `withAnimation` needs to know whether a
    /// frame build is already pending**, and `redrawRequests` above cannot
    /// answer it — see `aFrameBuildIsPending`. Weak, so a window nobody holds
    /// any more drops out on its own; compacted on every read and on every
    /// registration, so the array cannot grow past the number of live windows
    /// plus whatever died since the last look. **Weak references rather than a
    /// maintained count** deliberately: a count needs decrementing when a
    /// dirty window is deallocated, which means an isolated `deinit` touching
    /// main-actor state, and a count that drifts upward once is a
    /// `withAnimation` that parks forever with no diagnostic.
    ///
    /// This is the "window registry" whose absence is `Animation.parkedTransaction`'s
    /// stated reason for living at module scope. It does **not** change that:
    /// this answers "is *any* window about to build", which is a global
    /// question with a global answer, where the parking slot needs "*which*
    /// window did this body mutate", which nothing here can answer.
    private static var liveWindows: [WeakWindowRef] = []

    private struct WeakWindowRef {
        weak var window: Window?
    }

    /// True when some live window will build a frame at its next display-link
    /// tick — **`drawFrameIfNeeded`'s own guard, asked from outside**.
    ///
    /// `withAnimation` needs "will there be a next build for this transaction
    /// to reach", and `redrawRequests` answers only the narrower "did THIS
    /// body dirty a CLEAN window". The two differ on ordinary code, and the
    /// difference was measured rather than reasoned (fix round 2, re-review
    /// finding N-1): `withObservationTracking`'s `onChange` is **one-shot**,
    /// and a session is re-armed only by the next *drawn* frame, so the second
    /// and every later `@Observable` mutation between two frames reaches
    /// `markDirtyFromObservation` never and the counter never moves —
    ///
    /// ```
    /// model.count += 1                                          // counter +1
    /// withAnimation(.linear(duration: 1)) { model.width = 200 } // counter +0
    /// ```
    ///
    /// — even though a frame is certainly coming, because the first write left
    /// the window dirty. Gating on the counter alone silently snapped that
    /// second animation: measured `200.0` where the animation reads `150.0`.
    /// This property is what accepts it.
    ///
    /// **`needsRedraw` alone, NOT `needsRedraw || hasActiveAnimations`, and
    /// that is a deviation from the re-review's suggested predicate with a
    /// measurement and an argument behind it.**
    ///
    /// *It can never be needed.* The only case the pending test exists for is
    /// a counter-silent `@Observable` write, and a write is counter-silent
    /// only when the session is already spent — which means some earlier write
    /// since the last drawn frame *did* fire `onChange` and therefore *did*
    /// run `setNeedsRedraw()`. `needsRedraw = true` is written in exactly one
    /// place and cleared in exactly one other, `drawFrameIfNeeded`, whose
    /// tracked closure re-arms the session in the same breath. So "session
    /// spent" implies "no draw since" implies `needsRedraw == true`. A write
    /// to a model no window reads fires nothing and dirties nothing, but no
    /// frame renders it either, so nothing is dropped.
    ///
    /// *And it is reachable, and harmful when reached.* Measured with a
    /// throwaway probe (not kept): mid-fade, `needsRedraw == false` and
    /// `hasActiveAnimations == true`, an empty
    /// `withAnimation(.linear(duration: 4)) { }` parked `linear(4)` with the
    /// clause and `nil` without it. That parked transaction then applies to
    /// the next bare write — the exact shape of the bug fix round 1 existed to
    /// close, merely bounded by the running animation's lifetime instead of
    /// being unbounded. `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`'s
    /// fourth arm is that case, pinned.
    ///
    /// A measured cost against a structurally zero benefit is what decided it.
    static var aFrameBuildIsPending: Bool {
        liveWindows.removeAll { $0.window == nil }
        return liveWindows.contains { $0.window?.needsRedraw == true }
    }

    private static func register(_ window: Window) {
        liveWindows.removeAll { $0.window == nil }
        liveWindows.append(WeakWindowRef(window: window))
    }

    public func setNeedsRedraw() {
        Window.redrawRequests &+= 1
        needsRedraw = true
        platformWindow.setDisplayLinkPaused(false)
    }

    /// The `withObservationTracking` callback: something a frame read has
    /// changed, so the next frame must be built.
    ///
    /// **`nonisolated` is forced, not chosen.** `withObservationTracking`'s
    /// `onChange` is `@Sendable` and fires on the *mutating* thread, which may
    /// be any thread, so this cannot be `@MainActor` and cannot touch a stored
    /// property directly. Both branches below re-enter the actor before reading
    /// `isFlushing` or writing anything.
    ///
    /// **The two branches differ in latency, not in outcome.** A main-thread
    /// mutation — the demo, every test, any main-actor model — marks the window
    /// dirty *synchronously*, before the write it is reacting to has even
    /// landed. An off-thread mutation costs one main-actor hop first.
    ///
    /// **The synchronous branch is load-bearing for the idle criterion, not an
    /// optimisation.** The per-frame sentinel flush runs on the main thread and
    /// fires this method; under an always-hop implementation that callback
    /// would land *after* `drawFrameIfNeeded`'s `needsRedraw = false`, marking
    /// the window dirty on every single frame forever and destroying the
    /// display-link pause this milestone exists to deliver. The `isFlushing`
    /// guard is what makes that independent of thread affinity rather than
    /// resting on it.
    ///
    /// **KNOWN LIMITATION — a window is UNARMED for the whole frame build, and
    /// a change arriving in that interval is lost (ruling `RX-S`).** This
    /// method fires only for an *armed* session, and `withObservationTracking`
    /// installs its observers **after** the apply closure returns. So the
    /// unarmed interval runs from `drawFrameIfNeeded`'s sentinel flush to the
    /// end of the apply closure — essentially the whole frame build. A write
    /// landing in that interval, *after* the property has been read, fires no
    /// `onChange`: the window renders the pre-write value, clears
    /// `needsRedraw`, and pauses. It self-heals only if some other cause draws
    /// another frame.
    ///
    /// Measured twice rather than reasoned. Standalone: a write inside the
    /// apply closure fires `onChange` **0** times where the identical write
    /// after it returns fires **1**, and a session that missed an in-closure
    /// write still fires for a later one — so the session is armed and simply
    /// did not see the first. In-tree, with a content closure that reads then
    /// writes a model property: `observationDirtyings == 0`, and across 21
    /// subsequent ticks `needsRedraw == false`, **0** frames drawn, 21 pauses
    /// entered, `pauseCalls.last == true`. A post-build write on that same
    /// window then dirties it normally (`observationDirtyings == 1`).
    ///
    /// **Not fixed in code, deliberately.** Closing it means arming a session
    /// across the build, which is exactly what the flush ordering in
    /// `drawFrameIfNeeded` exists to prevent — the flush is what bounds
    /// registrations at one outstanding session, and an always-armed window
    /// re-enters the accumulation `RedrawSentinel` was built to stop. The
    /// off-thread path this reaches (`anOffThreadMutationMarksTheWindowDirtyAfterAHop`)
    /// is supported and tested; what is not guaranteed is a background write
    /// whose arrival lands inside a build. **Probably not a divergence**, by
    /// `RX-P`'s own test: SwiftUI's tracking has the same install-after-body
    /// semantics, so no oracle disagrees — but that claim is **derived from
    /// documented semantics, not measured against SwiftUI**, exactly as
    /// `RX-P`'s own SwiftUI claim is.
    ///
    /// **This limitation is UNPINNED by any test.** The two measurements above
    /// are both throwaway probes, not `#expect`s in the suite. A pin would have
    /// to drive a write from *inside* the tracked closure and assert the window
    /// goes clean and stays clean across subsequent ticks with no further
    /// cause to redraw — nobody has written it, and per this project's
    /// taxonomy shape 4, its absence must be stated rather than left silent.
    nonisolated private func markDirtyFromObservation() {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                guard !self.isFlushing else { return }
                self.observationDirtyings += 1
                self.setNeedsRedraw()
            }
        } else {
            Task { @MainActor [weak self] in
                guard let self, !self.isFlushing else { return }
                self.observationDirtyings += 1
                self.setNeedsRedraw()
            }
        }
    }

    public func drawFrameIfNeeded() {
        // Binding design spec §4.4, and the widening M4 spec 1 could not make.
        // `hasActiveAnimations` is the PREVIOUS frame's answer — an animation
        // left mid-interpolation there needs this frame drawn to advance it —
        // and it goes false on the frame a duration curve lands exactly on its
        // target, so the pause happens on the frame AFTER the last animation
        // ends rather than one frame later or never.
        guard needsRedraw || hasActiveAnimations else {
            // Nothing to do: let the display idle rather than spinning.
            platformWindow.setDisplayLinkPaused(true)
            pausesEntered += 1
            return
        }

        // Flush every observation session armed by an earlier frame, so
        // registrations stay bounded at one outstanding session instead of
        // growing with frames drawn. See `RedrawSentinel` for the measurement.
        //
        // THREE ORDERINGS ARE LOAD-BEARING HERE.
        //
        // 1. The flush is INSIDE the dirty branch, after the guard above. A
        //    clean, paused window must keep its one armed session — that
        //    session is what wakes it. Flushing before the guard disarms an
        //    idle window and it never redraws again.
        // 2. The flush PRECEDES `needsRedraw = false`. Any dirty the flush
        //    produces is absorbed by that clear. Moving the clear above the
        //    flush leaves the window permanently dirty at full frame rate.
        // 3. `redrawSentinel.tick` is READ inside the tracked closure below.
        //    That is what arms the next flush; a frame that does not read it
        //    cannot be flushed and rejoins the accumulating case.
        // Cleared by `defer` rather than by a following statement. `&+=` cannot
        // trap, so nothing here can escape early *today* — the `defer` is what
        // keeps that true for whoever adds a second statement later, at no
        // cost. **The enclosing `do` is load-bearing, not style — but the
        // reasoning below was wrong, and this comment claimed it until
        // 2026-09-03 (ruling `RX-S`).** It said a bare `defer` in this
        // function's own scope would run at the END of `drawFrameIfNeeded`,
        // holding `isFlushing` true across `renderRoot` and suppressing every
        // observation dirty for the whole frame. **That contradicts the KNOWN
        // LIMITATION recorded above, at `markDirtyFromObservation`**:
        // `withObservationTracking` installs its observers only *after* the
        // apply closure returns, and the previous frame's one-shot session was
        // already consumed by the flush two lines above — so nothing is armed
        // during `renderRoot` and nothing could fire there to be suppressed.
        // The off-thread arm cannot help either: its `Task { @MainActor }`
        // cannot run while the main thread is inside `drawFrameIfNeeded`, so
        // under a bare `defer` it would read `isFlushing == false` anyway.
        //
        // **The real hazard is narrower and worse, and it is LATENT rather
        // than live.** The interval that actually differs is the *tail* after
        // `withObservationTracking` returns and before `drawFrameIfNeeded`
        // does — there, a session *is* armed. A suppressed `onChange` in that
        // tail would consume the one-shot session and leave the window clean
        // and unarmed — never waking at all, rather than one frame stale.
        // Today no framework code writes a tracked property in that tail, so
        // a bare `defer` would change no observable behaviour on this branch
        // as it stands: this is a latent hazard the scoping guards against,
        // not a live bug it is presently papering over.
        do {
            isFlushing = true
            defer { isFlushing = false }
            redrawSentinel.tick &+= 1
        }

        needsRedraw = false
        // Cleared HERE, before `renderRoot` runs below — not after the frame
        // is built. **This ordering has no production consequence**: a
        // `@State` write made during `renderRoot` fires `onWrite` →
        // `setNeedsRedraw()` regardless of where this call sits, nothing
        // clears `needsRedraw` again before this function returns, so the
        // write is unswallowable either way.
        //
        // **That argument does NOT extend to an `@Observable` change arriving
        // during the build, and this comment claimed it did until 2026-09-03.**
        // A `@State` write reaches `needsRedraw` through `onWrite`, which fires
        // synchronously at the write; an observation change reaches it only if
        // a session is *armed*, and `withObservationTracking` installs its
        // observers **after** the apply closure returns. A write landing inside
        // the closure fires no `onChange` at all, so there is no dirty for this
        // clear to absorb — the failure is a lost dirty, not a swallowed one.
        // See `markDirtyFromObservation` for the unarmed interval and what it
        // costs. Ruling `RX-S`.
        //
        // What the ordering actually protects is `isDirty` itself, which is
        // otherwise-inert test
        // observability (see `StateTable.isDirty`'s doc): clearing it AFTER
        // `renderRoot` would raise it during the render and immediately
        // clear it again on the next line, so a test reading it back would
        // never see a write made during that frame. Clearing first keeps
        // that observable coherent with the "a write during a frame is not
        // lost" claim it exists to let a test check.
        stateTable.clearDirty()

        // No drawable is an ordinary condition: stay dirty and retry (the
        // window's `WindowRenderer` says so with `nil`, ruling RS-A).
        guard let drawScaleFactor = platformWindow.renderer.beginFrame() else {
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
        // Recorded **before** the frame is built, and read again after
        // `renderRoot` returns, because the read-back below applies the frame's
        // *decision* rather than its value — see there for why a plain copy
        // loses a `focus(_:)` call made from inside the render.
        let focusHandedIn = focusedElement
        // Spec §3's hand-off, and the whole reason production can animate at
        // all. `withAnimation` parked this and returned; the mutation inside
        // its body dirtied the window through `@State`'s `onWrite` or
        // `@Observable`'s tracking; this is the build that results, and it is
        // the FIRST place the transaction has been readable since the closure
        // ended. Taken (not merely read) so it is consumed by exactly one
        // build — spec §3's non-re-entrancy — whether or not this frame
        // contains anything that can use it.
        let transaction = Animation.takeParkedTransaction()
        let frame = Frame(contentSize: platformWindow.contentSize,
                          scaleFactor: drawScaleFactor,
                          stateTable: stateTable,
                          shapingCache: shapingCache,
                          textSystem: textSystem,
                          glyphAtlas: glyphAtlas,
                          theme: theme,
                          timestamp: lastTick,
                          mousePosition: lastMousePosition,
                          activeElement: active,
                          focusedElement: focusHandedIn,
                          transaction: transaction,
                          collectsAccessibility: accessibility.isActive,
                          recordsElementBounds: recordsElementBounds)
        // The window's key state is stamped OVER `environment` (ruling EV-AB):
        // `environment.controlActiveState` is not the root's source, as its
        // `theme` and `displayScale` are not (the frame re-stamps those two).
        var rootEnvironment = environment
        rootEnvironment.controlActiveState = controlActiveState
        frame.rootEnvironment = rootEnvironment
        withObservationTracking {
            // Reading the sentinel arms the next frame's flush; see ordering
            // note 3 above. Everything the element tree reads during all three
            // phases is tracked too, which is what makes an `@Observable`
            // model a dependency with no opt-in.
            _ = redrawSentinel.tick
            renderRoot(frame)
        } onChange: { [weak self] in
            self?.markDirtyFromObservation()
        }
        let scene = frame.finalizedScene()
        lastScene = scene
        lastHitboxes = frame.hitboxes
        lastElementBounds = frame.elementBounds
        lastNativeLayoutDeepestLevel = frame.tree.lastNativeLayoutDeepestLevel
        lastFocusRegistry = frame.focusRegistry
        editedText = [:]
        updateTextInputArea()
        // Read BACK, not merely handed in: `Frame.resolveFocus()` cleared it if
        // this frame did not produce the focused element (design spec §4.2).
        // Assigning the property directly rather than through `focus(_:)`,
        // because this is not a focus *move* — marking the window dirty for a
        // clearing the frame has already painted would wake the display link
        // for nothing.
        //
        // **Guarded, and the guard is what makes this apply the frame's
        // DECISION rather than its value.** The hand-in above and this line
        // straddle the whole of `renderRoot`, so they are a read-modify-write
        // over a value anything in the tree can change in between: `focus(_:)`
        // is public and `MetalUIDemoContent`'s `CounterPanel` calls it from its own
        // `requestLayout`. An unconditional copy would write back the id the
        // frame was *handed*, silently discarding that call — and discarding it
        // on every subsequent frame too, since set-during-render and
        // clobber-at-end alternate forever, so an in-frame `focus()` could
        // never stick at all. `frame.focusedElement` is only ever
        // `focusHandedIn` or `nil` (`resolveFocus()` clears, and nothing else
        // writes it), so "unchanged since the hand-in" is exactly the condition
        // under which the frame's answer is still about the current focus.
        //
        // A concurrent write is left alone rather than validated here, and that
        // is `focus(_:)`'s stated contract rather than a gap: this frame's
        // registry cannot speak for an id set part-way through building it, and
        // the *next* frame's `resolveFocus()` drops it if it was bogus. Pinned
        // from both sides by `focusingFromInsideAFrameSurvivesThatFrame` and
        // `focusingFromInsideAFrameIsStillValidatedByTheNextFrame`.
        if focusedElement == focusHandedIn {
            focusedElement = frame.focusedElement
        }
        // An element asked for another frame — an animation in progress. Marking
        // dirty here (rather than leaving the window to go clean) is what keeps
        // the display link running: without it, a fade stops the instant the
        // last input event stops arriving, because `needsRedraw` above already
        // went false for this pass and nothing else would flip it back.
        if frame.wantsAnotherFrame { setNeedsRedraw() }

        // The animation half of the same idea, and deliberately NOT the same
        // mechanism. `wantsAnotherFrame` marks the window dirty; this records
        // that an `Animation` is still interpolating, which the guard at the
        // top of this function reads on the next tick to keep drawing without
        // claiming anything changed. Assigned rather than or-ed: the frame's
        // answer is the whole answer, and a flag that only ever went true is
        // a window whose display link never pauses again.
        hasActiveAnimations = frame.hasActiveAnimations

        // After the focus read-back, so a published focus is the frame's
        // decision (AB-J). Builds only while a client is active (AB-B). A
        // `List` still waiting for its viewport asks for one more frame, which
        // this honours at most once per run of asking frames (AB-X rule 3).
        if accessibility.frameDidRender(
            emissionCount: frame.axEmissions.count,
            retry: frame.wantsAccessibilityRetry,
            AccessibilityTreeBuilder.build(emissions: frame.axEmissions, focused: focusedElement,
                                           hitboxes: frame.hitboxes,
                                           focusRegistry: frame.focusRegistry),
            to: platformWindow) {
            setNeedsRedraw()
        }

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
        guard platformWindow.renderer.finishFrame(scene: scene, atlas: glyphAtlas) else {
            setNeedsRedraw()
            return
        }
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
    /// it is `ScrollChrome.resolvedOffset`, not anything here.** This method has
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
        // A multi-line text field scrolls its own content (ruling TI-H): the
        // wheel moves its `scrollY` within its content and leaves the caret
        // where it is, so the next frame does not scroll it back.
        if let target = region.handlers.textInput, target.lines != nil {
            stateTable.withState(region.id, initial: TextEditState()) {
                $0.scrollY = min(max($0.scrollY - Double(event.delta.y.value), 0), target.maxScrollY)
                $0.revealsCaret = false
            }
            return true
        }
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
            // and `lastTick` is not a usable stand-in for "now" in either
            // direction: it is the display link's *target* presentation
            // instant (spec §4.4), so while the link is running it sits
            // roughly one frame interval AHEAD of the event's own timestamp,
            // and while paused it is however many seconds behind. The event's
            // own timestamp is the only one of the two that is actually
            // current.
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
        case .mouseMoved(let mouse), .mouseDragged(let mouse):
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
    ///
    /// **Comparing by `GlobalElementID` — structural `==`, not `===` — is what
    /// lets a press survive a rebuild.** Every frame mints new id objects, so a
    /// release after a redraw finds its target only through `==` walking the
    /// chain. Since plan task 8 (`ID-B`) a conditional sibling vanishing between
    /// `mouseDown` and `mouseUp` moves no other element's id: a pressed element
    /// that vanished clicks nothing, even when another element has slid under
    /// the pointer, and a pressed element that survived clicks itself at its new
    /// place. Until `ID-B` the trailing sibling took the vacated `.positional(_:)`
    /// and the release ran ITS `onClick` — identity's behaviour, not this
    /// function's, which is unchanged. Both arms pinned by
    /// `aPressHeldAcrossARebuildClicksItsOwnTargetAndAVanishedTargetClicksNothing`,
    /// whose second arm is what `hit.id === pressed` reddens.
    private func dispatchClick(_ event: InputEvent,
                               pressedBefore pressed: GlobalElementID?) -> Bool {
        guard case .mouseUp(let mouse) = event, let pressed else { return false }
        guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position) else {
            return false
        }
        let hit = lastHitboxes[index]
        guard hit.id == pressed, let handler = hit.handlers.onClick else { return false }
        // The clicked element owns the dispatch, so an aliased `@State` box
        // writes this occurrence (ruling ID-F, `StateDispatch`).
        StateDispatch.dispatching(to: hit.id) { handler() }
        return true
    }

    /// Dispatches a key event from the focused element **outward through its
    /// ancestors**, and reports whether anything claimed it (design spec §4.2).
    ///
    /// **`keyDown` only.** A `KeyEvent` carries no down/up discriminator, so an
    /// `onKey` handed both could not tell them apart and would fire twice per
    /// keystroke with no way to opt out. A `keyUp` falls through to
    /// `Window.onInput` unchanged; widening this means giving the handler the
    /// phase, which is a change to `KeyEvent`'s own surface.
    ///
    /// **With nothing focused the chain is empty and this returns `false`**, so
    /// the event reaches `onInput`. That is not a degenerate case — it is what
    /// lets a window-level keymap work with no focused element at all, which is
    /// the case the counter demo relies on.
    ///
    /// **Against `lastFocusRegistry`, exactly as clicks resolve against
    /// `lastHitboxes`**: there is no frame in flight when an input event
    /// arrives, only the record of the one most recently drawn. So a handler
    /// bound on frame N runs for an event arriving before frame N+1, and it is
    /// that frame's closure rather than an older one.
    ///
    /// **The chain comes from the id itself, not from a registered tree.** See
    /// `focusChain(from:)`: `GlobalElementID` already carries a parent pointer,
    /// so ancestry is derivable with nothing to keep in sync. An ancestor that
    /// bound no key handler is simply skipped.
    private func dispatchKey(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event else { return false }
        return MetalUI.dispatchKey(key, along: focusChain, in: lastFocusRegistry)
    }

    /// Resolves a keystroke against this window's `keymap` and dispatches the
    /// resulting action along the focus chain — the first of the two keyboard
    /// bubbles (design spec §4.1-§4.3).
    ///
    /// **Four steps, and each is a separate mechanism**: the focus chain
    /// supplies the ancestry, the focus registry supplies each level's key
    /// context, `matchKeymap` resolves keystroke plus contexts to an action
    /// (or holds a two-stroke prefix), and `dispatchAction` walks the same
    /// chain looking for a handler registered for that action's type.
    ///
    /// **`keyDown` only, and the guard is load-bearing for TWO reasons, not
    /// one.** A `keyUp` that reached here would dispatch the same binding a
    /// second time — measured: one press-and-release of a bound `cmd-i` fires
    /// the action **twice** without this line — and it would consume
    /// `pendingStroke`, so no two-stroke sequence could survive the release of
    /// its own first stroke. `dispatchKey`'s guard exists for a third,
    /// unrelated reason (a `KeyEvent` carries no down/up discriminator, so an
    /// `onKey` handed both could not tell them apart); the two guards look
    /// identical and are not the same argument. Pinned by
    /// `aKeyUpDispatchesNoActionAndLeavesAPendingPrefixAlone`, which asserts
    /// both halves.
    ///
    /// **Three outcomes, and the middle one is the interesting one.** A
    /// completed binding whose action *someone* handled claims the event. A
    /// pending prefix claims it too, because `ctrl-k` in flight must not also
    /// reach a raw handler. And a binding whose action nobody handled does
    /// **not** claim it: the keystroke falls through to the raw bubble and then
    /// to `onInput`, so a binding to an unhandled action behaves as if unbound
    /// rather than eating the keypress in silence.
    ///
    /// **Against `lastFocusRegistry`**, exactly as `dispatchKey` and
    /// `dispatchClick` resolve against the last frame's records: there is no
    /// frame in flight when an input event arrives.
    private func dispatchAction(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event else { return false }
        let chain = focusChain
        let contexts = chain.map { lastFocusRegistry.context(for: $0) }
        switch matchKeymap(key, in: keymap, contextsByLevel: contexts,
                           pending: &pendingStroke) {
        case .none:
            return false
        case .pending:
            return true
        case .action(let action):
            if MetalUI.dispatchAction(action, along: chain, in: lastFocusRegistry) {
                return true
            }
            return onAction?(action) ?? false
        }
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
    // MARK: Text input (ruling TI-B)

    /// The caret last handed to `setTextInputArea`, so it is called on change.
    private var lastTextInputArea: Bounds<Pixels>?

    /// A field's text as the last edit left it, until the next frame rebuilds
    /// its target: two edits between frames (a paste after a cut, an input
    /// method committing twice) must compose, not both start from the text
    /// the last frame saw. Measured: without it a cut then a paste read
    /// "pastedhello".
    private var editedText: [GlobalElementID: String] = [:]

    private func currentText(_ id: GlobalElementID, _ target: TextInputTarget) -> String {
        editedText[id] ?? target.text
    }

    private func applyEdit(_ id: GlobalElementID, _ target: TextInputTarget, _ text: String) {
        guard text != currentText(id, target) else { return }
        editedText[id] = text
        StateDispatch.dispatching(to: id) { target.onChange(text) }   // ID-F: the edited field
    }

    /// After each frame: text input is on exactly while a field is focused,
    /// with that field's caret as the input method's area.
    private func updateTextInputArea() {
        let area = focusedElement.flatMap { lastFocusRegistry.textTarget(for: $0)?.caretRect }
        guard area != lastTextInputArea else { return }
        lastTextInputArea = area
        platformWindow.setTextInputArea(area)
    }

    private func editState(_ id: GlobalElementID) -> TextEditState {
        var state = TextEditState()
        stateTable.withState(id, initial: TextEditState()) { state = $0 }
        return state
    }

    private func setEditState(_ id: GlobalElementID, _ state: TextEditState) {
        stateTable.withState(id, initial: TextEditState()) { $0 = state }
    }

    /// Pointer and text events for fields; see the call site.
    private func dispatchTextInput(_ event: InputEvent) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position),
                  let target = lastHitboxes[index].handlers.textInput else { return false }
            let id = lastHitboxes[index].id
            focus(id)
            setEditState(id, TextEditing.press(at: target.boundary(atWindowX: Double(mouse.position.x.value),
                                                                   y: Double(mouse.position.y.value)),
                                              clickCount: mouse.clickCount,
                                              extend: mouse.modifiers.contains(.shift),
                                              text: currentText(id, target), state: editState(id)))
            return true
        case .mouseDragged(let mouse):
            guard let id = active,
                  let target = lastHitboxes.first(where: { $0.id == id })?.handlers.textInput else { return false }
            setEditState(id, TextEditing.drag(to: target.boundary(atWindowX: Double(mouse.position.x.value),
                                                                  y: Double(mouse.position.y.value)),
                                             text: currentText(id, target), state: editState(id)))
            return true
        case .textInput(let inserted):
            guard let id = focusedElement, let target = lastFocusRegistry.textTarget(for: id) else { return false }
            let (text, state) = TextEditing.insert(inserted, text: currentText(id, target), state: editState(id),
                                                   multiline: target.lines != nil)
            setEditState(id, state)
            applyEdit(id, target, text)
            return true
        case .textComposition(let composition):
            guard let id = focusedElement, lastFocusRegistry.textTarget(for: id) != nil else { return false }
            setEditState(id, TextEditing.compose(composition, state: editState(id)))
            return true
        default:
            return false
        }
    }

    /// The focused field's editing keys (TI-D's table).
    private func dispatchTextKey(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event, let id = focusedElement,
              let target = lastFocusRegistry.textTarget(for: id) else { return false }
        let outcome = TextEditing.key(key, text: currentText(id, target), state: editState(id),
                                      clipboard: { [platformWindow] in platformWindow.readClipboard() },
                                      lines: target.lines)
        guard outcome.handled else { return false }
        setEditState(id, outcome.state)
        if let copied = outcome.copied { platformWindow.writeClipboard(copied) }
        if let text = outcome.text { applyEdit(id, target, text) }
        if outcome.submitted {
            guard let onSubmit = target.onSubmit else { return false }
            StateDispatch.dispatching(to: id) { onSubmit() }   // ID-F: the submitting field
        }
        return true
    }

    private func topmostHitboxOwner(at point: Point<Pixels>) -> GlobalElementID? {
        topmostOpaqueHitbox(in: lastHitboxes, at: point).map { lastHitboxes[$0].id }
    }
}
