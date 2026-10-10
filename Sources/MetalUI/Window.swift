import Foundation
import Observation
import MetalUICore
import MetalUIPrimitives
import MetalUIPlatform
#if canImport(MetalUIText)
import MetalUIText
#endif
import MetalUITextSystem

/// One window: its element tree, focus, input dispatch and frame loop, drawn
/// through a `PlatformWindow`. Every member is main-actor isolated.
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

    /// The pending `ScrollViewProxy.scrollTo` requests (ruling `DD-G` item 3),
    /// handed to each `Frame` before it renders. An enqueue dirties the window
    /// (below, in `init`), so a request made from a handler while the display
    /// link is paused still draws the frame that resolves it.
    let scrollRequests = ScrollRequestQueue()

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

    /// The platform window's Reduce Motion (plan task 13, ruling `AN-AD`), the
    /// root source of every frame's `accessibilityReduceMotion`: read from
    /// `PlatformWindow.accessibilityReduceMotion` at construction, updated
    /// through `onAccessibilityReduceMotionChange`, and stamped over
    /// `environment` at every draw beside `controlActiveState` — so
    /// `window.environment.accessibilityReduceMotion` (writable inside this
    /// module only) is not the root's source either. **Guarded**, for
    /// `controlActiveState`'s reason: a report of the value the window already
    /// has does not repaint. Pinned by
    /// `theWindowStampsReduceMotionFromItsPlatformWindow`.
    private(set) var accessibilityReduceMotion: Bool {
        didSet {
            guard accessibilityReduceMotion != oldValue else { return }
            setNeedsRedraw()
        }
    }

    // MARK: Colour scheme (rulings `CR-J`, `CR-K`, `CR-L`, `CR-M`)

    /// The colour scheme this window draws in (ruling `CR-J` item 3): the
    /// tree's `.preferredColorScheme`, else ``preferredColorScheme``, else the
    /// platform window's appearance. Stamped over `environment` into the root's
    /// `colorScheme` at every draw, beside `controlActiveState`, so
    /// `@Environment(\.colorScheme)` reads it while building.
    ///
    /// **Guarded, and the guard dirties by itself**: a report of the scheme the
    /// window already has does not repaint (`controlActiveState`'s reason);
    /// a change repaints **even when the theme does not change** — both
    /// variants may be one theme, and dynamic colours still flip (`CR-V` item
    /// 2). A change also re-selects `theme` from the variants. Pinned by
    /// `aReportOfTheCurrentSchemeDoesNotWakeTheDisplay` and
    /// `aSchemeChangeRepaintsEvenWhenBothVariantsAreTheSameTheme`.
    public private(set) var colorScheme: ColorScheme {
        didSet {
            guard colorScheme != oldValue else { return }
            setNeedsRedraw()
            theme = colorScheme == .dark ? darkTheme : lightTheme
        }
    }

    /// The platform window's appearance, as last reported (construction, then
    /// `onAppearanceChange`).
    private var platformAppearance: ColorScheme

    /// The preference the last built frame collected from the tree
    /// (`Frame.collectedColorSchemePreference`).
    private var treeColorSchemePreference: ColorScheme?

    /// The preference last handed to `PlatformWindow.setPreferredColorScheme`
    /// — `nil` until one is requested, so a window nobody asks is never told.
    private var requestedColorScheme: ColorScheme?

    /// A programmatic preference for this window (ruling `CR-L` item 4,
    /// MetalUI-only): used when the tree expresses none, and itself beating
    /// the platform's appearance. `nil` (the default) is no preference.
    /// `App.preferredColorScheme` assigns it on every window.
    public var preferredColorScheme: ColorScheme? {
        didSet {
            guard preferredColorScheme != oldValue else { return }
            updateColorScheme()
        }
    }

    /// The theme this window uses in the light scheme (ruling `CR-K`,
    /// MetalUI-only; default `.light`). While the window is light, assigning
    /// it sets ``theme``; a palette override on it (`lightTheme[Key.self] =`)
    /// is an assignment, so it repaints. `App.lightTheme` assigns it on every
    /// window.
    public var lightTheme: Theme = .light {
        didSet {
            guard lightTheme != oldValue, colorScheme == .light else { return }
            theme = lightTheme
        }
    }

    /// The theme this window uses in the dark scheme (ruling `CR-K`; default
    /// `.dark`). See ``lightTheme``.
    public var darkTheme: Theme = .dark {
        didSet {
            guard darkTheme != oldValue, colorScheme == .dark else { return }
            theme = darkTheme
        }
    }

    /// Recomputes the requested and effective schemes: tells the platform when
    /// the request (tree ?? window) changed, then assigns ``colorScheme``,
    /// whose guarded `didSet` repaints and re-selects the theme. The request
    /// is recorded **before** the platform call, so an `onAppearanceChange`
    /// the call fires synchronously (AppKit's forced appearance) re-enters
    /// here without asking again.
    private func updateColorScheme() {
        let requested = treeColorSchemePreference ?? preferredColorScheme
        if requested != requestedColorScheme {
            requestedColorScheme = requested
            platformWindow.setPreferredColorScheme(requested)
        }
        colorScheme = requested ?? platformAppearance
    }

    /// The window's animation state that is not `StateTable` state (ruling
    /// `AN-AB`): handed to every frame it builds, which drops what it did not
    /// touch.
    let animationStore = AnimationStore()

    /// The window's map from painted app-owned surfaces to their `SurfaceID`s
    /// (MetalView, `MV-E` item 6): minted per window, so two windows never
    /// share — or evict — each other's render targets (`MV-E` item 3).
    let surfaceRegistry = SurfaceRegistry()

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
    /// **Cleared when the pointer leaves the window** (ruling `SV-N` item 7,
    /// amending task 6's "deliberately sticky" decision): `.pointerExited` —
    /// AppKit's tracking-area `mouseExited`, SDL's `SDL_EVENT_WINDOW_MOUSE_LEAVE`
    /// — sets it `nil`, so `PaintPass.isHovered` reads `false` on the next
    /// frame and `onHover` hears `false` at once. Task 6 kept it sticky because
    /// the case would cross the `MetalUIPlatform` → `MetalUI` boundary for one
    /// reader; hover is the feature that gave the case a reason. No other
    /// paint-time query changes, and `topmostOpaqueHitbox` and click dispatch
    /// are untouched. **Migration**: an app that relied on the last in-window
    /// position staying hovered after the pointer left sees it un-hovered.
    private(set) var lastMousePosition: Point<Pixels>?

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

    /// The most recent frame's `Frame.accessibilityPressOnly`: the `onClick`
    /// of each enabled element whose hitbox `allowsHitTesting(false)` withheld,
    /// recorded only while a client is collecting (plan task 12 part 2,
    /// `IX-Z` item 1). An accessibility press runs one when no hitbox answers.
    private(set) var lastAccessibilityPressOnly: [GlobalElementID: @MainActor () -> Void] = [:]

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

    // MARK: - `@FocusState` (plan task 12 part 1, ruling `IX-J`)

    /// Every `@FocusState` the last frame bound, by slot.
    private var lastFocusStates: [GlobalElementID: any FocusStateReconciling] = [:]

    /// Applies each `@FocusState` write input made since the last frame, before
    /// the next frame is built (`IX-J` item 2):
    ///
    /// - `false`/`nil` clears focus **only if** the focused element was bound
    ///   to that state on the last frame;
    /// - any other value moves focus to the element the last frame registered
    ///   with that value — **only if that element was focusable on the last
    ///   frame** (enabled, not hidden, `.focusable()` or a control); otherwise
    ///   focus stays where it is, and the write-back after the frame restores
    ///   the state's value (`IX-S`). Removing this check is mutation M3a.
    ///
    /// A plain assignment, not `focus(_:)`: a frame is already being drawn.
    private func applyPendingFocusStateWrites() {
        guard !lastFocusStates.isEmpty else { return }
        for (slot, state) in lastFocusStates {
            guard let write = state.takePendingWrite(in: stateTable, slot: slot) else { continue }
            if write.clears {
                if let focused = focusedElement, lastFocusRegistry.focusBinding(for: focused)?.slot == slot {
                    focusedElement = nil
                }
            } else if let target = lastFocusRegistry.element(boundTo: slot, value: write.value),
                      lastFocusRegistry.isFocusable(target) {
                focusedElement = target
            }
        }
    }

    /// Writes each `@FocusState` the frame bound to the value the window's
    /// focus implies — the focused element's bound value for its own state,
    /// the default for every other — only where it changed (`IX-J` items 1, 4).
    /// A write dirties the window, so the body reads the new value on the
    /// frame after the move. Writing unconditionally is mutation M3f; skipping
    /// this is M3b.
    private func reconcileFocusStates() {
        guard !lastFocusStates.isEmpty else { return }
        let bound = focusedElement.flatMap { lastFocusRegistry.focusBinding(for: $0) }
        for (slot, state) in lastFocusStates {
            state.reconcile(in: stateTable, slot: slot, focusedValue: bound?.slot == slot ? bound?.value : nil)
        }
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

    /// Whether `drainLifecycle()` is running (ruling `LC-E` item 4).
    private var isDrainingLifecycle = false

    /// How many builds the last `drawFrameIfNeeded` made: 1, or 2 when a
    /// lifecycle action wrote (the settle build, `LC-E` item 2) or the first
    /// frame's scheme changed (`CR-Q`), 3 when both — test observability
    /// (`LC-K`). 0 after a call that drew nothing.
    private(set) var lastDrawBuildCount = 0

    /// Called with each frame `buildAndAdoptFrame` built, after its read-backs
    /// — test observability (the frame's tree and its recorded work, spec test
    /// 2.39). `nil` in production; nothing retains the frame.
    var onFrameAdopted: (@MainActor (Frame) -> Void)?

    // MARK: Window sizing (rulings `SV-L`, `SV-M`)

    /// The smallest content size the user can resize the window to, in window
    /// points; `nil`, the default, sets none (ruling `SV-L`). Combined per axis
    /// with the content's own minimum under `.contentMinSize`/`.contentSize`
    /// (the larger wins). A negative axis counts as 0; NaN traps. Applied at
    /// once: a window smaller than it is resized to it.
    ///
    /// Where MetalUI draws chrome above the root (``drawnChromeHeight``, the
    /// SDL toolbar strip) the minimum is the content's below it — the
    /// platform receives the height plus the chrome — as AppKit's
    /// `contentMinSize` excludes its toolbar (ruling `SG-F` item 2).
    public var minSize: Size<Pixels>? {
        didSet {
            ContentSizeLimits.requireNotNaN(minSize, "minSize")
            reconcileContentSizeLimits()
        }
    }

    /// The largest content size the user can resize the window to, in window
    /// points; `nil`, the default, sets none (ruling `SV-L`). An infinite axis
    /// is no limit on that axis; one below the minimum is raised to it; NaN
    /// traps. Combined with the content's maximum under `.contentSize` (the
    /// smaller wins). Measured below drawn chrome as ``minSize`` is (an
    /// infinite height stays unbounded; `SG-F` item 2).
    public var maxSize: Size<Pixels>? {
        didSet {
            ContentSizeLimits.requireNotNaN(maxSize, "maxSize")
            reconcileContentSizeLimits()
        }
    }

    /// Whether the root's layout limits the window's size (ruling `SV-L`):
    /// `.automatic`, the default, measures nothing (divergence 126);
    /// `.contentMinSize` and `.contentSize` measure the root once per drawn
    /// frame, before its real layout, so the limits follow the content.
    public var windowResizability: WindowResizability = .automatic {
        didSet {
            guard windowResizability != oldValue else { return }
            if windowResizability == .automatic { contentLimits = .none }
            // Only `.contentSize` measures a maximum: leaving it drops the
            // last frame's at once (`SV-AG` item 4).
            if windowResizability != .contentSize { contentLimits.maximum = nil }
            reconcileContentSizeLimits()
            setNeedsRedraw()
        }
    }

    /// Set while `applySizing` assigns several sizing properties, so they
    /// reach the platform as one call.
    private var isApplyingSizing = false

    /// Assigns all three sizing properties and reconciles **once** — `App.openWindow`'s
    /// parameters, so the platform hears one pair before the first frame
    /// (`SV-L` item 4), not one per property.
    func applySizing(minSize: Size<Pixels>?, maxSize: Size<Pixels>?, windowResizability: WindowResizability) {
        isApplyingSizing = true
        self.minSize = minSize
        self.maxSize = maxSize
        self.windowResizability = windowResizability
        isApplyingSizing = false
        reconcileContentSizeLimits()
    }

    /// The last adopted build's toolbar, numbered (`MD-I` item 6): what
    /// `reconcileToolbar` sends and what a `.toolbarAction` runs.
    var assembledToolbar = AssembledToolbar.empty
    /// The toolbar last handed to `setToolbar` — `nil` before any, which a
    /// window with no `.toolbar` never moves from, so it never calls (`MD-J`
    /// item 2).
    var sentToolbar: PlatformToolbar?
    /// Whether the platform declined the current toolbar (`setToolbar`
    /// answered `false`), so the window draws it (`MD-K`): the next build
    /// lays the strip out.
    var toolbarIsDrawn = false
    /// Whether the last adopted build laid the strip out — compared with
    /// `toolbarIsDrawn` after `reconcileToolbar` for the one extra build
    /// (`MD-K` item 5).
    private var lastBuildDrewToolbarStrip = false

    /// The height MetalUI draws above the root in this window, in window
    /// points (ruling `SG-F` item 1): the drawn toolbar strip (`MD-K`, 39 —
    /// on a platform whose `setToolbar` declines, SDL) as the last adopted
    /// frame laid it out; **0** where the platform shows its own toolbar
    /// (AppKit), with no toolbar, and before the first frame. The root is laid
    /// out in the rect below it, and an explicit ``minSize``/``maxSize`` is a
    /// size of that rect. Read-only; MetalUI-only.
    public var drawnChromeHeight: Pixels { Pixels(drawnChromeHeightValue) }
    /// `drawnChromeHeight`'s value, set when a frame is adopted.
    private var drawnChromeHeightValue: Float = 0

    /// Every `onResize` the platform delivered — read by `drawFrameIfNeeded`
    /// so a resize arriving inside its builds (a content limit the platform
    /// resized into, `SV-AG` item 3) still owes the next frame after a
    /// settle build cleared `needsRedraw`.
    private var resizeCount = 0

    /// The content's limits the last built frame measured (`.none` under
    /// `.automatic`).
    private var contentLimits = ContentSizeLimits.none
    /// The limits last sent to the platform — `.none` before any, which a
    /// window with no limits never moves from, so it never calls.
    private var appliedContentSizeLimits = ContentSizeLimits.none

    /// Sends the effective limits to the platform when they differ from the
    /// last pair sent (ruling `SV-L` item 4): from `minSize`/`maxSize`/
    /// `windowResizability`'s setters and after every built frame, so limits
    /// that never change reach the platform once — and none, never.
    private func reconcileContentSizeLimits() {
        guard !isApplyingSizing else { return }
        // An explicit limit is the content's below the drawn chrome (SG-F
        // item 2); the content's own limits already include it
        // (`Frame.computeRootLayout`).
        let effective = ContentSizeLimits.effective(minimum: belowDrawnChrome(minSize),
                                                    maximum: belowDrawnChrome(maxSize),
                                                    contentMinimum: contentLimits.minimum,
                                                    contentMaximum: contentLimits.maximum)
        guard effective != appliedContentSizeLimits else { return }
        appliedContentSizeLimits = effective
        platformWindow.setContentSizeLimits(minimum: effective.minimum, maximum: effective.maximum)
    }

    /// `size` with ``drawnChromeHeight`` added to a finite, non-negative
    /// height (a negative one counts as 0, as `ContentSizeLimits` clamps it);
    /// unchanged with no drawn chrome.
    private func belowDrawnChrome(_ size: Size<Pixels>?) -> Size<Pixels>? {
        guard let size, drawnChromeHeightValue > 0, size.height.value.isFinite else { return size }
        return Size(width: size.width, height: Pixels(max(size.height.value, 0) + drawnChromeHeightValue))
    }

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
        self.platformAppearance = platformWindow.appearance
        self.colorScheme = platformWindow.appearance
        // The variants' defaults are `Theme.forAppearance`'s two themes, so
        // this is the theme the window always started with (`CR-K` item 1).
        self.theme = platformWindow.appearance == .dark ? Theme.dark : Theme.light
        self.controlActiveState = platformWindow.controlActiveState
        self.accessibilityReduceMotion = platformWindow.accessibilityReduceMotion
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
        scrollRequests.onEnqueue = { [weak self] in self?.setNeedsRedraw() }

        // Also the backing-scale path (ruling EV-AA): both platforms report a
        // move between displays through `onResize`, and the next frame's
        // `displayScale` is the drawable's scale that `beginFrame()` returns.
        // Pinned by `aBackingScaleChangeReachesTheDisplayScaleOnTheNextFrame`.
        platformWindow.onResize = { [weak self] _, _ in
            self?.resizeCount &+= 1   // `SV-AG` item 3
            self?.dismissInWindowMenu()   // `MN-F` item 3
            self?.setNeedsRedraw()
        }
        platformWindow.onAccessibilityRequest = { [weak self] request in
            self?.handleAccessibilityRequest(request) ?? false
        }
        platformWindow.onAppearanceChange = { [weak self] appearance in
            // The platform's appearance is one input to the effective scheme
            // (`CR-L` item 4); assigning `colorScheme` drives its guarded
            // `didSet`, which marks the window dirty and swaps the active
            // theme to the scheme's variant — §7.9's "swap the active theme
            // and mark §4.4's dirty flag" (`CR-J`, `CR-K`).
            guard let self else { return }
            self.platformAppearance = appearance
            self.updateColorScheme()
        }
        platformWindow.onControlActiveStateChange = { [weak self] state in
            // Assigning drives `controlActiveState`'s guarded `didSet`, which
            // is what marks the window dirty (ruling EV-AB).
            self?.controlActiveState = state
            if state != .key {
                self?.dismissInWindowMenu()   // `MN-F` item 3
                self?.hideTooltip()   // `MN-P` item 2
            }
        }
        platformWindow.onAccessibilityReduceMotionChange = { [weak self] reduceMotion in
            // Assigning drives the guarded `didSet`, which marks the window
            // dirty (ruling `AN-AD`).
            self?.accessibilityReduceMotion = reduceMotion
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
            // Platform services (`SV-K`, `SV-C`, `SV-I`): a dialog's or an
            // alert's answer is first after the pointer state — no later stage
            // may claim it.
            switch event {
            case .fileDialogResult(let result):
                self.handleFileDialogResult(result)
                self.setNeedsRedraw()
                return true
            case .alertResult(let result):
                self.handleAlertResult(result)
                self.setNeedsRedraw()
                return true
            // A native toolbar control (`MD-J` item 4): first too, under
            // `StateDispatch` for the scope that declared it.
            case .toolbarAction(let action):
                self.handleToolbarAction(action)
                self.setNeedsRedraw()
                return true
            // Hover (`SV-N` item 4): every pointer event and the pointer
            // leaving the window recompute the hovered set from input. Claims
            // nothing.
            // The other buttons and a right drag too (`CI-X` item 1, `CI-Z`
            // item 1: owed by lane 2).
            // The pointer style is recomputed here too (`CI-H` item 7); a
            // release ends a press's hold on it (`CI-H` item 6).
            case .mouseMoved, .mouseDragged, .mouseDown, .rightMouseDown,
                 .rightMouseDragged, .otherMouseDown, .otherMouseDragged:
                self.updateHover(at: self.lastMousePosition, reportsMoves: true)
            case .mouseUp, .rightMouseUp, .otherMouseUp:
                self.updateHover(at: self.lastMousePosition, reportsMoves: true, releasing: true)
            case .pointerExited:
                self.updateHover(at: nil, reportsMoves: true)
            // A pinch at its own position (spec §1.4 item 1, `CI-AL` item 2):
            // the hovered set and the pointer style follow it; an entering
            // region hears `onHover`, but a pinch is not a move, so
            // `onContinuousHover` reports nothing from a member already in.
            case .magnify, .rotate:
                self.updateHover(at: self.lastMousePosition, reportsMoves: false)
            default:
                break
            }
            // The drawn alert is modal (`SV-J` item 3): while it is up it takes
            // every pointer and key event ahead of the drag session, the menu
            // and everything after them; a menu's outcome and the pointer
            // leaving pass.
            if let answer = self.dispatchDrawnAlert(event) {
                self.setNeedsRedraw()
                return answer
            }
            // The tooltip watches every event and claims none (`MN-P` item 2).
            self.trackTooltip(event)
            // Drag and drop (rulings `DN-C`, `DN-H`, `DN-I`): a drop from
            // outside answers for itself — "an accepting destination is under
            // the pointer" or "a destination took it", not "claimed" — and an
            // open in-window session takes its pointer events and Escape
            // FIRST, ahead of scrolling, text input, the arena and the keymap.
            // A press never opens one here: the arena does, on a move.
            if case .drop(let drop) = event {
                let answer = self.dispatchExternalDrop(drop)
                self.setNeedsRedraw()
                return answer
            }
            if self.dispatchDragSession(event) {
                self.setNeedsRedraw()
                return true
            }
            // An open menu takes input next (ruling `MN-F` item 3), then the
            // context-menu stage opens one on a secondary press and takes a
            // native menu's outcome (`MN-C`, `MN-E`). Every later stage
            // ignores the secondary button (`MN-B` item 4, divergence 110).
            // Between them, the popovers' stage (spec §3.8, `MN-N`, `MN-Y`): an
            // outside press dismisses and passes on, an anchor's is consumed,
            // Escape dismisses the topmost — before the keymap.
            if self.dispatchMenuSession(event) || self.dispatchPopovers(event) || self.dispatchContextMenu(event) {
                self.setNeedsRedraw()
                return true
            }
            // Scroll routing runs before the window's general `onInput`: the
            // wheel chain (`CI-I` item 4) offers the event to the elements'
            // wheel handlers and scrollers under the pointer, innermost first —
            // there is no scroll chaining (see `applyScroll`'s doc comment), so
            // a claimed wheel event does not also reach whoever opened the
            // window.
            if case .scrollWheel(let scroll) = event, self.applyScroll(scroll) {
                self.setNeedsRedraw()
                return true
            }
            // A trackpad pinch's arena (`CI-D`) and a secondary or other
            // button's arena (`CI-F`): each formed from the one ranking, each
            // apart from the primary press's arena, each claiming the event
            // when it holds a live arena. The primary-only stages below never
            // see these events (`MN-B`, `CI-E` item 2).
            if self.dispatchPinch(event) || self.dispatchButtonArena(event) {
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
            // A slider's track (ruling `DD-W` item 5): a press writes the value
            // under the pointer and a drag from it writes again. Beside the
            // text fields and on their footing — ahead of click dispatch, and
            // it does not focus.
            if self.dispatchValueTrack(event) {
                self.setNeedsRedraw()
                return true
            }
            // After scroll routing and before the raw handler, on the same
            // footing: an element that consumed the point consumed the event.
            // The gesture arena (plan task 12 part 1, `IX-D`) stands where
            // `dispatchClick` stood and contains it: a press whose target and
            // ancestors carry no gesture forms no arena, and its release is
            // `dispatchClick` exactly.
            if self.dispatchGestures(event, pressedBefore: pressed) {
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
            // Shift-F10 and the Menu key off Apple (ruling `MN-G` item 1):
            // after a caller's raw `onKey`, before shortcuts.
            if self.dispatchContextMenuKey(event) {
                self.setNeedsRedraw()
                return true
            }
            // A `Button`'s keyboard shortcut (plan task 12 part 1, `IX-F` item
            // 4): after the keymap, a focused field's editing keys and the raw
            // `onKey` bubble, so each claims a key first (`B4i`, `X2`); before
            // Tab traversal. Needs no focus (`B4e`).
            if self.dispatchShortcut(event) {
                self.setNeedsRedraw()
                return true
            }
            // The app's commands (ruling `MN-J`): directly after a `Button`'s
            // shortcut, so a keystroke both claim fires the button alone, and
            // before Tab traversal. **Migration**: a key a command binds no
            // longer reaches Tab traversal or the window's own `onInput`.
            if self.dispatchCommandShortcut(event) {
                self.setNeedsRedraw()
                return true
            }
            // Tab and shift-Tab move focus (ruling TI-J) — last of the key
            // stages, so a keymap binding, a field and a raw `onKey` all see
            // the key first.
            if self.dispatchFocusTraversal(event) {
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
                // Ahead of the frame build (plan task 12 part 1, `IX-C` item 4):
                // a long press or a deferred tap that matures at this tick runs
                // its callback from input's footing, so a `@State` write lands
                // in the frame drawn below and is not a phase write.
                self?.advanceGestures(to: t)
                self?.advanceTooltip(to: t)   // the tooltip's timer, on the same footing (MN-P item 2)
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
    /// any more drops out on its own; compacted on every registration (and,
    /// until plan task 13, on every read — `aFrameBuildIsPending`'s note), so
    /// the array cannot grow past the number of live windows plus whatever
    /// died since the last registration. **Weak references rather than a
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
    ///
    /// **A pure read since plan task 13** (`AN-AF` item 8, the animation
    /// milestone's follow-up): it no longer compacts the registry as it reads
    /// — a dead entry answers `false` all the same — and `register` does the
    /// compacting, so the array still cannot grow past the live windows plus
    /// whatever died since the last registration. Pinned by
    /// `aFrameBuildIsPendingDoesNotPruneTheRegistry`.
    static var aFrameBuildIsPending: Bool {
        liveWindows.contains { $0.window?.needsRedraw == true }
    }

    /// Entries in the registry, dead ones included — test observability for
    /// the prune split (1.19).
    static var registeredWindowCount: Int { liveWindows.count }

    private static func register(_ window: Window) {
        liveWindows.removeAll { $0.window == nil }
        liveWindows.append(WeakWindowRef(window: window))
    }

    /// Marks the window dirty and wakes its display link, so the next tick
    /// builds a frame.
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

    /// Builds and draws one frame if the window is dirty or an animation is
    /// running; otherwise pauses the display link.
    public func drawFrameIfNeeded() {
        lastDrawBuildCount = 0
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
        let resizesBeforeBuild = resizeCount

        // The build-and-adopt half (ruling `CR-Q`): an ordinary frame, every
        // window-owned store updated from it.
        var (frame, scene) = buildAndAdoptFrame(scaleFactor: drawScaleFactor)

        // The tree's colour-scheme preference (rulings `CR-L`, `CR-Q`). After
        // the first frame a change applies on the next one: `updateColorScheme`
        // dirties through `colorScheme`'s guard. On the FIRST frame a change
        // of the effective scheme is applied now and the half runs once more
        // inside this `beginFrame()`, so no light flash is presented. The
        // first build is adopted in full — nothing is discarded or rolled back
        // (`StateTable`, `AnimationStore`, focus, scroll requests and surfaces
        // saw an ordinary frame); only the second is published and encoded.
        // The second build snaps every change (`Frame.snapsEveryChange`,
        // `CR-Q` item 3): a value animated on the scheme, or a transition on a
        // scheme-dependent conditional, does not start from the first build,
        // so the presented frame equals one build in the target scheme
        // (test 2.11b).
        let schemeBefore = colorScheme
        if applyTreeColorSchemePreference(of: frame), framesDrawn == 0, colorScheme != schemeBefore {
            // The second build re-derives every "another frame" request the
            // first made; the scheme change that dirtied is consumed by it.
            needsRedraw = false
            (frame, scene) = buildAndAdoptFrame(scaleFactor: drawScaleFactor, snapsEveryChange: true)
            _ = applyTreeColorSchemePreference(of: frame)
        }

        // The lifecycle's actions (ruling `LC-E`): after the build — outside
        // every phase, outside `Frame.render` and outside
        // `withObservationTracking`'s apply closure, so an `@Observable` write
        // reaches the armed session — and before accessibility and
        // `finishFrame`. When they wrote, the window builds ONCE more inside
        // this `beginFrame()` (`CR-Q`'s precedent) and presents that build, so
        // an `onAppear`'s write is in the first frame (`F1`); that build's own
        // actions run too, and their writes schedule the next frame (one level
        // per presented frame, divergence 121). An action that writes nothing
        // costs no second build.
        if drainLifecycle() {
            needsRedraw = false
            (frame, scene) = buildAndAdoptFrame(scaleFactor: drawScaleFactor)
            _ = applyTreeColorSchemePreference(of: frame)
            drainLifecycle()
        }

        // The toolbar (`MD-J` item 2): the last build's, sent when it changed.
        // When the platform's answer changes whether the window draws a strip
        // (`MD-K` item 5) — it appeared, or the drawn one left — the root's
        // rect changes, so the window builds ONCE more inside this
        // `beginFrame()` (`CR-Q`'s precedent) and presents that build: the
        // strip is in the first presented frame. A changed strip, or a window
        // with no toolbar, costs no extra build.
        reconcileToolbar()
        if lastBuildDrewToolbarStrip != toolbarIsDrawn {
            needsRedraw = false
            (frame, scene) = buildAndAdoptFrame(scaleFactor: drawScaleFactor)
            _ = applyTreeColorSchemePreference(of: frame)
            drainLifecycle()
            reconcileToolbar()
        }

        // A resize that arrived during the builds above (the platform resizing
        // into a content limit, `SV-AG` item 3) was encoded into a drawable
        // taken before it; the settle builds' `needsRedraw = false` may have
        // cleared its dirt, so it is raised again here.
        if resizeCount != resizesBeforeBuild { setNeedsRedraw() }

        // Platform services, after the frame (`SV-K` item 3, `SV-N` item 4;
        // `LC-E`'s place — outside every phase): present what turned `true`,
        // dismiss what turned `false` or left, then recompute hover against
        // this frame's hitboxes (content moved, appeared or left under a still
        // pointer; a presented drawn alert empties it). Writes their callbacks
        // make schedule the next frame.
        reconcilePresentations()
        updateHover(at: lastMousePosition, reportsMoves: false)

        // After the focus read-back, so a published focus is the frame's
        // decision (AB-J). Builds only while a client is active (AB-B). A
        // `List` still waiting for its viewport asks for one more frame, which
        // this honours at most once per run of asking frames (AB-X rule 3).
        if accessibility.frameDidRender(
            emissionCount: frame.axEmissions.count,
            retry: frame.wantsAccessibilityRetry,
            { () -> AccessibilityBuild in
                var build = AccessibilityTreeBuilder.buildResult(
                    emissions: frame.axEmissions, focused: focusedElement, hitboxes: frame.hitboxes,
                    pressOnly: frame.accessibilityPressOnly, focusRegistry: frame.focusRegistry,
                    menus: Set(frame.contextMenuRecords.keys))
                // The in-window menu: a root after the content's, published
                // even under modal isolation (`MN-F` item 4, `MN-AB`).
                appendMenuPanel(to: &build)
                appendAlertPanel(to: &build)   // the drawn alert, last (SV-J item 4)
                return build
            }(),
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
        //
        // The frame's app-owned surfaces' requests ride along (MetalView,
        // `MV-F`): the renderer runs them into this frame's command buffer
        // after its atlas upload and before it encodes `scene`.
        guard platformWindow.renderer.finishFrame(scene: scene, atlas: glyphAtlas,
                                                  surfaces: frame.surfaceRequests) else {
            setNeedsRedraw()
            return
        }
        framesDrawn += 1
    }

    /// Runs every lifecycle event the builds so far produced (ruling `LC-E`),
    /// each under `StateDispatch` for its element and, for a disappearance,
    /// reading through its departed state (`LC-I`). Answers whether they
    /// dirtied the window; `needsRedraw` ends as it was or-ed with that.
    ///
    /// **Not re-entrant** (`LC-E` item 4): an action that draws a frame
    /// synchronously builds normally, and that build's events wait for this
    /// drain's next pass — it loops until no events are left, and each pass's
    /// events come from a build that already happened, so the loop is bounded
    /// by the builds the actions themselves drew.
    @discardableResult
    private func drainLifecycle() -> Bool {
        guard !isDrainingLifecycle else { return false }
        isDrainingLifecycle = true
        defer { isDrainingLifecycle = false }
        let wasDirty = needsRedraw
        needsRedraw = false
        var events = animationStore.lifecycle.takeEvents()
        while !events.isEmpty {
            for event in events {
                stateTable.withDepartedOverlay(event.departed) {
                    StateDispatch.dispatching(to: event.owner) { event.action() }
                }
            }
            events = animationStore.lifecycle.takeEvents()
        }
        let dirtied = needsRedraw
        needsRedraw = wasDirty || dirtied
        return dirtied
    }

    /// Closing the window (ruling `LC-J`): every present element's
    /// `onDisappear`, then every parked one, each once, under `StateDispatch`
    /// — called by `App`'s `onClose`. A second call finds nothing. A write
    /// such an action makes dirties a window that will not draw again
    /// (`LC-P` item 6).
    func runDisappearancesForClose() {
        for event in animationStore.lifecycle.closeAll() {
            StateDispatch.dispatching(to: event.owner) { event.action() }
        }
    }

    /// Records the preference `frame` collected and, when it changed,
    /// recomputes the scheme (ruling `CR-L`). Answers whether it changed.
    private func applyTreeColorSchemePreference(of frame: Frame) -> Bool {
        let collected = frame.collectedColorSchemePreference
        guard collected != treeColorSchemePreference else { return false }
        treeColorSchemePreference = collected
        updateColorScheme()
        return true
    }

    /// The build-and-adopt half of `drawFrameIfNeeded` (ruling `CR-Q`): builds
    /// one frame at `scaleFactor` — taking the parked root transaction, so a
    /// second call in one `beginFrame()` gets none — and adopts it: the read-
    /// backs (`lastScene`, hitboxes, focus, menus, popovers, drag), the
    /// focus decision, `@FocusState` reconciliation and the "another frame"
    /// answers. Accessibility publication and `finishFrame` stay with the
    /// caller, which runs them once, for the build it presents.
    private func buildAndAdoptFrame(scaleFactor drawScaleFactor: Float,
                                    snapsEveryChange: Bool = false) -> (Frame, Scene) {
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
        // A `@FocusState` write made from input since the last frame moves focus
        // now, before the frame that validates it is built (ruling `IX-J`).
        applyPendingFocusStateWrites()
        let focusHandedIn = focusedElement
        // Spec §3's hand-off, and the whole reason production can animate at
        // all. `withAnimation` parked this and returned; the mutation inside
        // its body dirtied the window through `@State`'s `onWrite` or
        // `@Observable`'s tracking; this is the build that results, and it is
        // the FIRST place the transaction has been readable since the closure
        // ended. Taken (not merely read) so it is consumed by exactly one
        // build — spec §3's non-re-entrancy — whether or not this frame
        // contains anything that can use it.
        lastDrawBuildCount += 1
        let transaction = Animation.takeParkedRootTransaction()
        let frame = Frame(contentSize: platformWindow.contentSize,
                          scaleFactor: drawScaleFactor,
                          stateTable: stateTable,
                          shapingCache: shapingCache,
                          textSystem: textSystem,
                          glyphAtlas: glyphAtlas,
                          theme: theme,
                          lightTheme: lightTheme,
                          darkTheme: darkTheme,
                          timestamp: lastTick,
                          mousePosition: lastMousePosition,
                          activeElement: active,
                          focusedElement: focusHandedIn,
                          transaction: transaction.animation,
                          disablesAnimations: transaction.disablesAnimations,
                          snapsEveryChange: snapsEveryChange,
                          animationStore: animationStore,
                          surfaceRegistry: surfaceRegistry,
                          collectsAccessibility: accessibility.isActive,
                          recordsElementBounds: recordsElementBounds)
        // The window's key state is stamped OVER `environment` (ruling EV-AB):
        // `environment.controlActiveState` is not the root's source, as its
        // `theme` and `displayScale` are not (the frame re-stamps those two).
        var rootEnvironment = environment
        rootEnvironment.controlActiveState = controlActiveState
        rootEnvironment.accessibilityReduceMotion = accessibilityReduceMotion  // AN-AD, the same stamp
        rootEnvironment.colorScheme = colorScheme  // CR-J, the same stamp
        rootEnvironment.fileDialogs = fileDialogs  // SV-D item 4, the same stamp (holds self weakly)
        frame.rootEnvironment = rootEnvironment
        frame.scrollRequestQueue = scrollRequests
        frame.menuPresenter = menuPresenter   // a pull-down's handle (spec §3.4)
        frame.contentSizeLimitsMode = windowResizability   // what the root is measured for (SV-L item 2)
        frame.previousPresentationAnchors = lastPresentationAnchors   // popovers' anchors (MN-M item 2)
        frame.tooltip = tooltipTracker.visible   // the tooltip (MN-P item 2)
        if let session = dragSession {   // the drag preview (DN-J)
            frame.dragSourceID = session.sourceID
            frame.dragPreviewTranslation = session.translation
            frame.dragPreviewOrigin = session.previewOrigin
            frame.previousDragSnapshot = session.snapshot
        }
        if let session = menuSession, !session.isNative {   // the in-window menu (MN-F item 2)
            frame.menuPanelLevels = session.levels
        }
        frame.alertPanel = drawnAlertPanel   // the drawn alert (SV-J item 2)
        frame.pickerTitleWidths = pickerTitleWidths   // menu pickers' widths (SV-AA)
        frame.drawsToolbarStrip = toolbarIsDrawn   // the drawn toolbar strip (MD-K)
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
        lastHoverRegionCount = frame.hoverRegionCount   // SV-U
        lastPointerStyleRegionCount = frame.pointerStyleRegionCount   // CI-H item 7
        lastMenuRowsPainted = frame.menuRowsPainted   // SV-Q
        pickerTitleWidths.sweep()   // only the pickers this build laid out keep an entry (SV-AA)
        presentations.records = frame.presentationRecords   // SV-K item 2
        assembledToolbar = AssembledToolbar(records: frame.toolbarRecords)   // MD-I item 5, MD-J item 4
        lastBuildDrewToolbarStrip = frame.drewToolbarStrip   // MD-K item 5
        drawnChromeHeightValue = frame.drewToolbarStrip ? ToolbarStrip.height : 0   // SG-F item 1
        lastElementBounds = frame.elementBounds
        lastNativeLayoutDeepestLevel = frame.tree.lastNativeLayoutDeepestLevel
        lastFocusRegistry = frame.focusRegistry
        lastAccessibilityPressOnly = frame.accessibilityPressOnly
        lastContextMenus = frame.contextMenuRecords
        lastPresentationAnchors = frame.presentationAnchors
        lastOpenPopovers = frame.openPopovers
        lastDragCapturedPrimitives = frame.dragCapturedPrimitives
        lastEffectScopesPushed = frame.effectScopesPushed
        if let captured = frame.dragSnapshot, dragSession != nil {
            dragSession?.snapshot = captured   // kept when the source stops painting (DN-H item 4)
        }
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
        // Every `@FocusState` the frame bound follows the focus it settled on —
        // between frames, never in a phase, and writing only a changed value
        // (ruling `IX-J` item 4).
        lastFocusStates = stateTable.takeFocusStates()
        reconcileFocusStates()
        // An element asked for another frame — an animation in progress. Marking
        // dirty here (rather than leaving the window to go clean) is what keeps
        // the display link running: without it, a fade stops the instant the
        // last input event stops arriving, because `needsRedraw` above already
        // went false for this pass and nothing else would flip it back.
        if frame.wantsAnotherFrame { setNeedsRedraw() }
        // A pending long press or tap sequence needs the next tick to reach
        // `advanceGestures` (plan task 12 part 1, `IX-C` item 4) — only while
        // one is pending, so a held press that has already ended, or failed,
        // lets the link pause (pinned by
        // `aPendingGestureKeepsFramesComingOnlyWhilePending`).
        if gestureArena?.needsTicks == true { setNeedsRedraw() }
        // A pending tooltip's timer needs the next tick to reach
        // `advanceTooltip` — only while pending (`MN-P` item 2, `IX-C` item
        // 4's footing; pinned by `thePendingTooltipKeepsTheLinkAwakeOnlyWhilePending`).
        if tooltipTracker.isPending { setNeedsRedraw() }

        // The animation half of the same idea, and deliberately NOT the same
        // mechanism. `wantsAnotherFrame` marks the window dirty; this records
        // that an `Animation` is still interpolating, which the guard at the
        // top of this function reads on the next tick to keep drawing without
        // claiming anything changed. Assigned rather than or-ed: the frame's
        // answer is the whole answer, and a flag that only ever went true is
        // a window whose display link never pauses again.
        hasActiveAnimations = frame.hasActiveAnimations

        // The content's limits follow the frame just built (ruling `SV-L`
        // items 2 and 4): sent to the platform only when the effective pair
        // changed. A resize the platform makes into them arrives through
        // `onResize` and dirties the window for the next frame.
        if windowResizability != .automatic {
            contentLimits = ContentSizeLimits(minimum: frame.contentMinimum, maximum: frame.contentMaximum)
        }
        // Also when only the drawn chrome changed (SG-F item 3); a pair equal
        // to the last one sent sends nothing.
        reconcileContentSizeLimits()
        onFrameAdopted?(frame)
        return (frame, scene)
    }

    /// Applies a wheel delta to the topmost **opaque hitbox** under the
    /// pointer if that hitbox is a scroller, and otherwise to that hitbox's
    /// nearest enclosing scroller on the same layer (ruling `DD-Y`).
    ///
    /// **One list, one ranking** (design spec §3.1). This used to walk a
    /// separate `lastScrollRegions` with its own copy of the ranking closure;
    /// it now calls `topmostOpaqueHitbox(in:at:)` — the single copy — against
    /// the same list `mouseDown` resolves against. `lastHitboxes` is in
    /// prepaint order, outermost first, so the last match among equal layers is
    /// the most deeply nested hitbox containing the point, which is the
    /// visually topmost one.
    ///
    /// **An opaque hitbox that is NOT a scroller stops the walk**, which is the
    /// entire point of the fold and the limitation three milestones recorded:
    /// before it, a non-scrolling `Deferred` scrim registered nothing a wheel
    /// event could see, so the list underneath a modal scrolled through it. The
    /// walk does not keep descending through what the hitbox covers.
    ///
    /// **But the wheel passes a non-scrolling hitbox to its nearest enclosing
    /// scroller** (ruling `DD-Y`, plan task 10 part 2 — **divergence 16
    /// retired**): the nearest ancestor of its id that registered a scroll
    /// region containing the point **on the same layer**
    /// (the wheel chain, `CI-I` item 4). Until then a click target inside a
    /// `ScrollView` swallowed that scroller's wheel over its own rect, where a
    /// browser scrolls (a wheel event bubbles up the DOM to the first
    /// scrollable ancestor) — pinned as today's behaviour by
    /// `aClickTargetInsideAScrollViewSwallowsTheWheel`, whose doc asked whoever
    /// fixed it to invert it; it is now
    /// `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`. A selectable
    /// `List` — rows of click targets edge to edge — is what made it due. The
    /// fix this doc once named (prefer the topmost scroller whenever its layer
    /// is not lower, "no ancestor walk") is **narrowed by an ancestry test**:
    /// by layer alone a click target merely *overlaid* on a scroller (a `Stack`
    /// sibling) would pass the wheel to what it covers. **The two clauses** are
    /// pinned apart: ancestry by
    /// `aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel`,
    /// the layer — a `Deferred` scrim hoisted to layer 1 while the scroller
    /// that declared it paints on 0 — by
    /// `aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel`. **A
    /// single-line `TextField` is such a click target** (a pointer target
    /// through `Handlers.textInput`), so its wheel reaches its scroller too — a
    /// changed `TextField` answer (`DD-AC` item 3), pinned by
    /// `aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller`. The
    /// multi-line editor's own branch stays first. SwiftUI's and AppKit's
    /// answers are unmeasured (the probe's wheel control WH0 failed); a human
    /// look is owed.
    ///
    /// **It is CLAIMED rather than merely dropped**, whether or not anything
    /// scrolled. Returning `false` here would leave an event that landed on an
    /// element which consumed the point being re-offered to the window's own
    /// fallback handler as though nothing had taken it — half a swallow, the
    /// shape ruling AP-I warns about for the portal's two halves. Opaque was not
    /// optional for a click target: a non-opaque one would stop a `Deferred`
    /// scrim swallowing clicks aimed at what it covers.
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
    ///
    /// **The wheel chain** (input APIs, ruling `CI-I` item 4, in place of the
    /// lookup that stood here; `DD-Y` preserved). The cover is the one
    /// ranking's topmost hitbox under the pointer that is opaque or carries an
    /// `.onScrollWheel` handler. The chain is the cover's id and its ancestors
    /// (by `GlobalElementID.parent`); at each id, among the regions **on the
    /// cover's layer** containing the point with that id: its wheel handlers,
    /// innermost (registered last) first, each under `StateDispatch` with
    /// `location` made local to its region — claimed when one returns `true`;
    /// at the cover only, a multi-line text editor (`TI-H`, claimed); then that
    /// id's scroll region (scrolls, claimed). Unclaimed after the chain: claimed
    /// when the cover is opaque (a click target with no scroller above it
    /// stops the wheel, `DD-Y`), else not (the window's `onInput` sees it).
    ///
    /// **Ancestry** keeps a click target merely *overlaid* on a scroller (a
    /// `Stack` sibling) stopping its wheel; **the layer** keeps a `Deferred`
    /// scrim — hoisted to layer 1 while the scroller that declared it paints on
    /// 0 — and a popover over a canvas stopping it too. Pinned by
    /// `aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel`,
    /// `aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel`,
    /// `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`,
    /// `aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller` and
    /// the input-API tests 3.3–3.13 (`InputAPIWindowTests`). **The element is
    /// the cover, not its handler's region** (`CI-AL` item 1): a legacy
    /// `.onScrollWheel` registers its non-opaque region under the element's
    /// own id, ranking above the element's opaque hitbox, so when the top
    /// match is non-opaque and that id's opaque hitbox on its layer is under
    /// the point, that hitbox is the cover — a declining handler on a click
    /// target still stops the wheel, and one on a `TextEditor` leaves it
    /// scrolling itself, inside a `ScrollView` too
    /// (`aDecliningWheelHandlerOnAClickTargetStillSwallowsTheWheel`,
    /// `aDecliningWheelHandlerOnATextEditorLeavesItScrollingItself`). No
    /// built-in scroller shares an id with a handler, so a handler on or around
    /// a `ScrollView` sees nothing over it (`CI-AH` item 1, narrowed by `CI-AL`
    /// item 3: a custom `StyledElement` that calls the public
    /// `registerScrollRegion` under its own id and takes `.onScrollWheel` does
    /// share it, and its handler runs first — unpinned). Each event is
    /// dispatched at its own position — no latching (`CI-AD`).
    private func applyScroll(_ event: ScrollEvent) -> Bool {
        let point = event.position
        guard let topIndex = topmostHitbox(in: lastHitboxes, at: point, where: {
            $0.opaque || $0.handlers.pointer?.scrollWheel != nil
        }) else { return false }
        var cover = lastHitboxes[topIndex]
        // A legacy `.onScrollWheel` registers its non-opaque wheel region under
        // the element's own id after the element's opaque hitbox, so it ranks
        // above it. The element is still the cover (`CI-AL` item 1): when that
        // element's opaque hitbox on the same layer is under the point too —
        // the one ranking again, never a second lookup — the cover is it, so a
        // declining handler falls through to the element's own `TI-H` scroll
        // and opacity rather than the handler-only region's.
        if !cover.opaque, let own = topmostHitbox(in: lastHitboxes, at: point, where: { [cover] in
            $0.opaque && $0.id == cover.id && $0.layer == cover.layer
        }) {
            cover = lastHitboxes[own]
        }
        let candidates = lastHitboxes.indices.filter {
            let region = lastHitboxes[$0]
            return (region.scroll != nil || region.handlers.pointer?.scrollWheel != nil)
                && region.layer == cover.layer && region.contains(point)
        }
        var cursor: GlobalElementID? = cover.id
        while let id = cursor {
            let here = candidates.filter { lastHitboxes[$0].id == id }
            for index in here.reversed() {
                let region = lastHitboxes[index]
                guard let handler = region.handlers.pointer?.scrollWheel else { continue }
                var local = event
                let p = region.localPoint(point)
                local.location = Point(x: Pixels(p.x.value - region.origin.x.value),
                                       y: Pixels(p.y.value - region.origin.y.value))
                if StateDispatch.dispatching(to: region.id, { handler(local) }) { return true }
            }
            // A multi-line text field scrolls its own content (ruling TI-H): the
            // wheel moves its `scrollY` within its content and leaves the caret
            // where it is, so the next frame does not scroll it back.
            if id == cover.id, let target = cover.handlers.textInput, target.lines != nil {
                stateTable.withState(cover.id, initial: TextEditState()) {
                    $0.scrollY = min(max($0.scrollY - Double(event.delta.y.value), 0), target.maxScrollY)
                    $0.revealsCaret = false
                }
                return true
            }
            if let scroller = here.last(where: { lastHitboxes[$0].scroll != nil }) {
                scroll(lastHitboxes[scroller], by: event)
                return true
            }
            cursor = id.parent
        }
        return cover.opaque
    }

    /// Moves `region`'s stored offset by the wheel's component on its axis.
    /// See `applyScroll` for why the write is unbounded.
    private func scroll(_ region: Hitbox, by event: ScrollEvent) {
        guard let axis = region.scroll else { return }
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
        case .rightMouseDown(let mouse), .rightMouseUp(let mouse), .rightMouseDragged(let mouse),
             .otherMouseDown(let mouse), .otherMouseDragged(let mouse), .otherMouseUp(let mouse):
            // A secondary or other press, and its drag, move the pointer,
            // never `active` (`MN-B` item 4, `CI-E` item 2).
            lastMousePosition = mouse.position
        case .magnify(let pinch):
            // A pinch is at the pointer (AppKit's event location, SDL's last
            // pointer position): it moves `lastMousePosition`, never `active`
            // (`CI-AL` item 2).
            lastMousePosition = pinch.position
        case .rotate(let pinch):
            lastMousePosition = pinch.position
        case .pointerExited:
            // The pointer left the window (`SV-N` item 7): nothing is under it.
            lastMousePosition = nil
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
        runClick(handler, on: hit.id, modifiers: mouse.modifiers)
        return true
    }

    // MARK: Menus (menus, popovers and tooltips, lane 1 — `MN-C`, `MN-F`)

    /// The open menu — native or in-window — or `nil` (`MN-C`, `MN-F`). On
    /// `Window`, never in `StateTable`, so no id path or reserved slot moves.
    var menuSession: MenuSession?

    // MARK: Presentations and hover (platform services, `SV-K`, `SV-N`)

    /// The window's presentations: the last build's records and the one
    /// dialog or alert in flight (`SV-K`). Never a `StateTable` entry.
    let presentations = PresentationRegistry()

    /// The alert the platform declined to show (`SV-J` item 2) — the window's
    /// to draw (lane 3's panel) and answer through `chooseAlertButton(_:)`.
    var drawnAlert: DrawnAlert?

    /// The hovered regions, in the last frame's registration order — outer
    /// first (`SV-N` item 5).
    var hoveredRegions: [HoveredRegion] = []

    /// How many hover regions the last adopted frame registered (`SV-U`): with
    /// none and nothing hovered, a pointer event or frame does no hover work.
    var lastHoverRegionCount = 0

    /// How many in-window menu rows the last adopted frame painted (`SV-Q`):
    /// at most the visible band's rows plus one per level.
    var lastMenuRowsPainted = 0

    /// Each menu picker's widest option title, across builds (`SV-AA`).
    let pickerTitleWidths = PickerTitleWidths()

    /// Hitboxes the hover recomputes visited, ever — test observability for
    /// `SV-U`'s counted work (one per hitbox per recompute, after the ranking).
    var hoverVisits = 0

    /// The pointer style last sent to the platform, or `nil` when unknown —
    /// before the first pointer event, and after the pointer left the window
    /// (`CI-S`), so the next pointer event sends unconditionally (`CI-H` item 7).
    var resolvedPointerStyle: PointerStyle?

    /// How many pointer-style regions the last adopted frame registered: with
    /// none, a recompute visits no hitbox (`CI-H` item 7, `SV-U`'s shape).
    var lastPointerStyleRegionCount = 0

    /// Hitboxes the pointer-style recomputes visited, ever — test observability
    /// for the counted work (test 3.25).
    var pointerStyleVisits = 0

    /// The app's enabled command shortcuts, in menu order (ruling `MN-J`):
    /// set by `App.openWindow`, re-evaluated at each keystroke reaching the
    /// command stage. `nil` for a window built without an `App`.
    var commandShortcuts: (@MainActor () -> [(KeyboardShortcut, @MainActor () -> Void)])?

    /// Runs the first enabled command shortcut, in menu order, that `event`
    /// matches (`MN-J` item 1), from input — exact modifiers, as a `Button`'s
    /// (`IX-F` item 2). `false` for a window with no app or no match.
    func dispatchCommandShortcut(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event, let shortcuts = commandShortcuts?(),
              let match = shortcuts.first(where: { $0.0.matches(key) }) else { return false }
        match.1()
        return true
    }

    /// The anchors the last frame recorded, by element, in window points (spec
    /// §3.4, `MN-AD`): a `Menu`'s bounds and a popover's anchor (lane 3,
    /// `MN-M` item 2), handed to the next frame for its popovers' placement.
    /// The window-owned anchor map; frame-scoped, never `StateTable`.
    var lastPresentationAnchors: [GlobalElementID: Bounds<Pixels>] = [:]

    /// The popovers the last frame presented, topmost last (spec §3.8): the
    /// dismissal stage's table. A dismissed one leaves it at once, so a second
    /// event before the next frame does not dismiss it again.
    var lastOpenPopovers: [OpenPopover] = []

    /// The release a popover's consumed anchor press owes a claim (`MN-Y`
    /// item 2): `true` for the secondary button, `false` for the primary.
    var popoverClaimsRelease: Bool?

    /// The tooltip's state (`MN-P` item 2) — on `Window`, never `StateTable`.
    var tooltipTracker = TooltipTracker()

    /// The handle every frame hands its pull-down menus (spec §3.4).
    var menuPresenter: MenuPresenter {
        if let existing = menuPresenterStorage { return existing }
        let made = MenuPresenter(window: self)
        menuPresenterStorage = made
        return made
    }
    private var menuPresenterStorage: MenuPresenter?

    /// The last menu token handed out; each presentation takes the next.
    var lastMenuToken = 0

    /// The context menus the last frame recorded, by element (spec §3.1): the
    /// keyboard and accessibility openers' table (`MN-G`).
    var lastContextMenus: [GlobalElementID: ContextMenuRecord] = [:]

    /// The platform convention the keyboard context-menu opener reads (`MN-G`
    /// item 1): `TextEditing.platform` always, in production. A test sets it to
    /// `.other` so the Shift-F10/Menu-key path, compiled for Linux and Windows,
    /// is exercised on macOS too.
    var contextMenuKeyPlatform: TextEditing.Platform = TextEditing.platform

    /// The text system an in-window menu measures and draws through (`TS-A`).
    var menuTextSystem: any TextSystem { textSystem }

    /// The in-window menu's font: the default control font (`MN-F` item 2).
    var menuFont: FontKey { textSystem.resolveFont(MenuPanel.fontDescriptor) }

    /// The release a menu stage owes a claim: the up of a press it claimed
    /// (`MN-F` item 3's consumed outside press, a right press that opened a
    /// native menu). `true` for the secondary button, `false` for the primary.
    var menuClaimsRelease: Bool?

    /// An other button's press the open in-window menu took owes its release
    /// a claim (spec §1.4 item 3).
    var menuClaimsOtherRelease = false

    /// A context menu deferred to its secondary press's release (`CI-F` item
    /// 4), or `nil`.
    var pendingContextMenu: PendingContextMenu?

    /// Asks the platform to show `menu` itself (`MN-C`).
    func presentMenuOnPlatform(_ menu: PlatformMenu, at position: Point<Pixels>) -> Bool {
        platformWindow.presentMenu(menu, at: position)
    }

    /// The platform's file dialog, alert and dismissal (`SV-B`), for
    /// `Presentations.swift` and `FileDialogs.swift` — `platformWindow` stays
    /// private, as `presentMenuOnPlatform` keeps it.
    func presentFileDialogOnPlatform(_ dialog: PlatformFileDialog) -> Bool {
        platformWindow.presentFileDialog(dialog)
    }
    func presentAlertOnPlatform(_ alert: PlatformAlert) -> Bool {
        platformWindow.presentAlert(alert)
    }
    func dismissPresentationOnPlatform(token: Int) {
        platformWindow.dismissPresentation(token: token)
    }

    /// The platform's toolbar (`MD-J` item 2), for `Toolbar.swift`.
    func setToolbarOnPlatform(_ toolbar: PlatformToolbar?) -> Bool {
        platformWindow.setToolbar(toolbar)
    }

    /// Clears `active` for a press the open menu consumed, so the press never
    /// draws pressed and its release completes no click beneath (`MN-F` item 3).
    func releasePressForMenu() {
        active = nil
    }

    /// The current press's gesture arena (plan task 12 part 1, `IX-D`), or
    /// `nil` when no press with a gesture in its arena is undecided. Formed at
    /// a `mouseDown`, kept past the release only while a tap sequence waits for
    /// its next press.
    private var gestureArena: GestureArena?

    /// The open in-window drag (ruling `DN-H`), or `nil`. On `Window`, never
    /// in `StateTable` (`DN-H` item 6), so no id path or reserved slot moves.
    var dragSession: DragSession?

    /// How many primitives the last frame captured for a drag preview
    /// (ruling `DN-J`; test 2.14) — 0 in every frame without a session.
    private(set) var lastDragCapturedPrimitives = 0

    /// The last frame's `Frame.effectScopesPushed` (ruling `GX-G`, test 2.21).
    private(set) var lastEffectScopesPushed = 0

    /// The destination currently targeted — by the in-window session or by a
    /// drag from outside — whose `isTargeted(true)` has run and whose `false`
    /// is owed (`DN-H` item 1).
    var dropTarget: DropTargetState?

    /// A drag from outside the window in progress (ruling `DN-C`): the items
    /// it offered on entering — `.some(nil)` when the platform cannot know
    /// them until the drop (SDL, `DN-M`) — or `nil` when none is in progress.
    var externalDropItems: [DropItem]??

    /// Feeds a pointer event to the gesture arena and runs what it decided;
    /// returns whether a `mouseUp` ran a callback (`IX-D` item 6 — a press or a
    /// drag is never claimed, so `Window.onInput` still sees them as before).
    ///
    /// **The arena is formed from the one ranking**: its target is
    /// `topmostOpaqueHitbox(in:at:)`'s answer — the same hitbox `mouseDown`
    /// made `active` — and its other members are the gesture-carrying hitboxes
    /// of that id's proper ancestors, in its own hit layer (`IX-Q`), that
    /// contain the point (`Hitbox.contains`),
    /// found through the id itself, as `focusChain(from:)` finds its chain —
    /// no parent link on a `Hitbox`, no second list, no second ranking (`IX-D`
    /// item 1). **An ancestor's `onClick` never joins** (`IX-D` item 2): with
    /// no gesture anywhere in the arena there is no arena, and the release is
    /// `dispatchClick`'s, unchanged.
    private func dispatchGestures(_ event: InputEvent, pressedBefore pressed: GlobalElementID?) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            var callbacks: [GestureCallback] = []
            let key = gestureArenaKey(at: mouse.position)
            if var arena = gestureArena, arena.isAlive {
                // The no-target arena keys on its draggable region (`DN-U`
                // item 5), so a continuing press compares against the same.
                if let key, lastHitboxes[key.target].id == arena.targetID {
                    callbacks = arena.press(at: mouse.position, clickCount: mouse.clickCount, continuing: true,
                                            modifiers: mouse.modifiers)
                    gestureArena = arena
                    runGestureCallbacks(callbacks)
                    return false
                }
                callbacks = arena.abandon()
            }
            gestureArena = nil
            if let key, var arena = makeGestureArena(key, at: mouse.position) {
                callbacks += arena.press(at: mouse.position, clickCount: mouse.clickCount, continuing: false,
                                         modifiers: mouse.modifiers)
                gestureArena = arena
            }
            runGestureCallbacks(callbacks)
            return false
        case .mouseDragged(let mouse):
            guard var arena = gestureArena else { return false }
            let callbacks = arena.move(to: mouse.position, modifiers: mouse.modifiers)
            gestureArena = arena
            runGestureCallbacks(callbacks)
            return false
        case .mouseUp(let mouse):
            guard var arena = gestureArena, arena.isPressing else {
                return dispatchClick(event, pressedBefore: pressed)
            }
            let callbacks = arena.release(at: mouse.position, clickCount: mouse.clickCount,
                                          modifiers: mouse.modifiers,
                                          click: completedClick(mouse, pressedBefore: pressed))
            gestureArena = arena.isAlive ? arena : nil
            runGestureCallbacks(callbacks)
            return !callbacks.isEmpty
        default:
            return false
        }
    }

    /// Ends the press's pointer bookkeeping when a drag begins or is handed
    /// to the platform (ruling `DN-D` item 7, `DN-K` item 1): the arena is
    /// dropped (every member already failed or ended) and `active` cleared, so
    /// nothing draws pressed and the release is not a click. Here, beside the
    /// two `private` stores it clears, rather than widening their access for
    /// `DragSession.swift`.
    func endPressForDrag() {
        gestureArena = nil
        active = nil
    }

    /// The window's content size, for "the drag left the window" (`DN-K`).
    var contentSizeForDrag: Size<Pixels> { platformWindow.contentSize }

    /// Offers a drag leaving the window to the platform (`DN-K` item 1).
    func offerExternalDrag(_ representations: [DragRepresentation], at position: Point<Pixels>) -> Bool {
        platformWindow.beginExternalDrag(representations, at: position)
    }

    /// The arena for a press on `lastHitboxes[target]`, or `nil` when neither
    /// it nor a containing ancestor carries a gesture.
    ///
    /// **An ancestor joins only from the target's own hit layer** (`IX-Q`): a
    /// `Deferred` presentation's content is hoisted to a higher layer while its
    /// id stays under its declarer's, and SwiftUI keeps a presentation's press
    /// out of its presenter's arena (probe `swiftui-gesture-presentation-arena.swift`
    /// S1/S2, V1/V2) — so a declarer's high-priority gesture cannot take a
    /// modal's click, nor its simultaneous one run beside it. Pinned by
    /// `aDeferredPresentationsPressDoesNotJoinItsDeclarersArena`.
    private func makeGestureArena(_ key: (target: Int, draggableAbove: Int?),
                                  at point: Point<Pixels>, mode: ArenaMode = .press) -> GestureArena? {
        let hit = lastHitboxes[key.target]
        var ancestors: [(hitbox: Hitbox, depth: Int)] = []
        var depth = 1
        var cursor = hit.id.parent
        while let id = cursor {
            if let box = lastHitboxes.last(where: { $0.id == id && $0.layer == hit.layer
                                                        && !$0.handlers.gestures.isEmpty
                                                        && $0.contains(point) }) {
                ancestors.append((box, depth))
            }
            depth += 1
            cursor = id.parent
        }
        return GestureArena(target: hit, ancestors: ancestors,
                            draggableAbove: key.draggableAbove.map { lastHitboxes[$0] }, mode: mode)
    }

    // MARK: The pinch and button arenas (input APIs, `CI-D`, `CI-F`)

    /// The trackpad pinch's arena (`CI-D`), or `nil`: formed at a pinch's
    /// first event, alive while a begun magnify or rotate has not ended.
    private var pinchArena: GestureArena?

    /// The secondary or other button's arena (`CI-F` item 3) and its button
    /// number, or `nil`: formed at that button's press, ended by its release.
    /// Apart from `gestureArena`, so a middle drag during a pending primary
    /// tap sequence disturbs neither.
    private var buttonArena: GestureArena?
    private var buttonArenaButton = 0

    /// Hands `style` to the platform window (`CI-H` item 8) — the one call
    /// site, `updatePointerStyle(at:releasing:)`, sends only on a change.
    func sendPointerStyle(_ style: PlatformPointerStyle) {
        platformWindow.setPointerStyle(style)
    }

    /// The pressed target the pointer style holds to (`CI-H` item 6): a live
    /// secondary or other button's arena, else the primary arena while it is
    /// pressing — its owner and the layer of its opaque hitbox in the last
    /// frame. `nil` with no press, or when the target left the frame.
    var pointerStylePressTarget: (id: GlobalElementID, layer: Int)? {
        let id: GlobalElementID
        if let arena = buttonArena {
            id = arena.targetID
        } else if let arena = gestureArena, arena.isPressing {
            id = arena.targetID
        } else {
            return nil
        }
        guard let hit = lastHitboxes.last(where: { $0.opaque && $0.id == id }) else { return nil }
        return (id, hit.layer)
    }

    /// The arena of `mode` for an event at `point`, from the one ranking:
    /// `topmostOpaqueHitbox`'s target and its gesture-carrying ancestors in
    /// its hit layer (`makeGestureArena`), no draggable region.
    private func makeArena(at point: Point<Pixels>, mode: ArenaMode) -> GestureArena? {
        guard let target = topmostOpaqueHitbox(in: lastHitboxes, at: point) else { return nil }
        return makeGestureArena((target, nil), at: point, mode: mode)
    }

    /// Whether a secondary press at `point` would form a button arena with a
    /// live leaf — the context-menu stage's reason to defer (`CI-F` item 4).
    func secondaryDragIsDeclared(at point: Point<Pixels>) -> Bool {
        makeArena(at: point, mode: .button(MouseButton.secondary.buttonNumber)) != nil
    }

    /// Feeds a `.magnify` or `.rotate` to the pinch arena (`CI-D`): the first
    /// event of a pinch forms it at the EVENT's position — an end or cancel
    /// with no arena is dropped (`CI-V` item 4) — and the callbacks run under
    /// their owners. Claims the event while an arena holds it.
    private func dispatchPinch(_ event: InputEvent) -> Bool {
        let position: Point<Pixels>, phase: InputPhase
        switch event {
        case .magnify(let pinch): (position, phase) = (pinch.position, pinch.phase)
        case .rotate(let pinch): (position, phase) = (pinch.position, pinch.phase)
        default: return false
        }
        // A `.began` of a kind the arena already holds active means that
        // kind's end was lost: the stale arena is dropped silently and the
        // event forms a new one at its own position (ruling `CI-AB` item 2).
        if phase == .began, let arena = pinchArena, arena.holdsActivePinch(of: event) { pinchArena = nil }
        if pinchArena == nil {
            guard phase != .ended, phase != .cancelled,
                  let arena = makeArena(at: position, mode: .pinch) else { return false }
            pinchArena = arena
        }
        guard var arena = pinchArena else { return false }
        let callbacks: [GestureCallback]
        switch event {
        case .magnify(let pinch): callbacks = arena.magnify(pinch)
        case .rotate(let pinch): callbacks = arena.rotate(pinch)
        default: callbacks = []
        }
        pinchArena = arena.isAlive ? arena : nil
        runGestureCallbacks(callbacks)
        return true
    }

    /// Feeds a secondary or other button's press, drag and release to its
    /// arena (`CI-F` item 3): only drags declared with that button run; with
    /// none on the chain there is no arena and the event passes on. A second
    /// button pressed while one's arena is alive is ignored; a press of the
    /// arena's own button replaces it (`CI-AB`). The secondary
    /// release opens a context menu the press deferred, unless a drag reached
    /// its minimum (`CI-F` item 4).
    private func dispatchButtonArena(_ event: InputEvent) -> Bool {
        switch event {
        case .rightMouseDown(let mouse): return buttonPress(mouse, button: MouseButton.secondary.buttonNumber)
        case .otherMouseDown(let mouse): return buttonPress(mouse, button: mouse.buttonNumber)
        case .rightMouseDragged(let mouse): return buttonMove(mouse, button: MouseButton.secondary.buttonNumber)
        case .otherMouseDragged(let mouse): return buttonMove(mouse, button: mouse.buttonNumber)
        case .rightMouseUp(let mouse): return buttonRelease(mouse, button: MouseButton.secondary.buttonNumber)
        case .otherMouseUp(let mouse): return buttonRelease(mouse, button: mouse.buttonNumber)
        default: return false
        }
    }

    private func buttonPress(_ mouse: MouseEvent, button: Int) -> Bool {
        // A press of the live arena's own button means its release was lost:
        // the stale arena is dropped silently, as a primary press's
        // re-formation drops one (ruling `CI-AB` item 1). Another button's
        // press while an arena is alive is ignored (`CI-AA` item 4).
        if buttonArena != nil, buttonArenaButton == button { buttonArena = nil }
        guard buttonArena == nil, var arena = makeArena(at: mouse.position, mode: .button(button)) else {
            return false
        }
        let callbacks = arena.press(at: mouse.position, clickCount: mouse.clickCount, continuing: false,
                                    modifiers: mouse.modifiers)
        buttonArena = arena
        buttonArenaButton = button
        if arena.activatedAnyDrag { pendingContextMenu = nil }
        runGestureCallbacks(callbacks)
        return true
    }

    private func buttonMove(_ mouse: MouseEvent, button: Int) -> Bool {
        guard var arena = buttonArena, buttonArenaButton == button else { return false }
        let callbacks = arena.move(to: mouse.position, modifiers: mouse.modifiers)
        buttonArena = arena
        if arena.activatedAnyDrag { pendingContextMenu = nil }
        runGestureCallbacks(callbacks)
        return true
    }

    private func buttonRelease(_ mouse: MouseEvent, button: Int) -> Bool {
        let pending = button == MouseButton.secondary.buttonNumber ? pendingContextMenu : nil
        if pending != nil { pendingContextMenu = nil }
        guard var arena = buttonArena, buttonArenaButton == button else { return false }
        let callbacks = arena.release(at: mouse.position, clickCount: mouse.clickCount,
                                      modifiers: mouse.modifiers, click: nil)
        buttonArena = nil
        runGestureCallbacks(callbacks)
        if let pending, !arena.activatedAnyDrag { openPendingContextMenu(pending) }
        return true
    }

    /// Who forms the arena for a press at `point` (drag and drop, ruling
    /// `DN-E` item 2), from the one ranking: the target is still
    /// `topmostOpaqueHitbox`'s answer, and the topmost NON-opaque draggable
    /// region ranking above it — a later `(layer, index)` — joins as the
    /// innermost member. With no opaque hitbox at the point, the topmost
    /// draggable region is the target itself, and the arena keys on it
    /// (`DN-U` item 5). `nil` when neither exists.
    private func gestureArenaKey(at point: Point<Pixels>) -> (target: Int, draggableAbove: Int?)? {
        let draggable = topmostHitbox(in: lastHitboxes, at: point,
                                      where: { !$0.opaque && $0.handlers.hasDraggable })
        guard let target = topmostOpaqueHitbox(in: lastHitboxes, at: point) else {
            return draggable.map { ($0, nil) }
        }
        let above = draggable.flatMap { region -> Int? in
            (lastHitboxes[region].layer, region) > (lastHitboxes[target].layer, target) ? region : nil
        }
        return (target, above)
    }

    /// Advances the arena's timers to a display-link tick and runs what
    /// matured (`IX-C` item 4). Called from the display link, before the frame.
    func advanceGestures(to time: Double) {
        guard var arena = gestureArena else { return }
        let callbacks = arena.tick(time)
        gestureArena = arena.isAlive ? arena : nil
        runGestureCallbacks(callbacks)
        if !callbacks.isEmpty { setNeedsRedraw() }
    }

    /// Runs the arena's callbacks in order, each under its owner (`ID-F`); a
    /// click through `runClick`, as `dispatchClick` runs one.
    private func runGestureCallbacks(_ callbacks: [GestureCallback]) {
        for callback in callbacks {
            switch callback {
            case .click(let owner, let handler, let modifiers):
                runClick(handler, on: owner, modifiers: modifiers)
            case .gesture(let owner, let run):
                StateDispatch.dispatching(to: owner) { run() }
            case .beginDrag(let owner, let source, let point):
                beginDragSession(from: owner, source: source, pressedAt: point)
            }
        }
    }

    /// `dispatchClick`'s test, asked by the arena: the target's `onClick` and
    /// the release's modifiers when the release lands on the pressed element,
    /// `nil` otherwise.
    private func completedClick(_ mouse: MouseEvent, pressedBefore pressed: GlobalElementID?)
        -> (handler: @MainActor () -> Void, modifiers: Modifiers)? {
        guard let pressed, let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position) else {
            return nil
        }
        let hit = lastHitboxes[index]
        guard hit.id == pressed, let handler = hit.handlers.onClick else { return nil }
        return (handler, mouse.modifiers)
    }

    /// Runs a click handler — a mouse click's or an accessibility `.press`'s —
    /// with `ClickDispatch` set for it, then honours the focus request it left
    /// (ruling `DD-Z` item 9). The one place both click paths run a handler, so
    /// the two cannot drift.
    func runClick(_ handler: @MainActor () -> Void, on id: GlobalElementID, modifiers: Modifiers) {
        let request = ClickDispatch.running(modifiers: modifiers) {
            // The clicked element owns the dispatch, so an aliased `@State` box
            // writes this occurrence (ruling ID-F, `StateDispatch`).
            StateDispatch.dispatching(to: id) { handler() }
        }
        if let request { focus(request) }
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

    /// A slider's pointer events (ruling `DD-W` item 5); see the call site.
    /// The press resolves against `lastHitboxes` exactly as `mouseDown` does,
    /// and the drag follows the id `active` holds — the one the press made
    /// active — wherever the pointer goes, as a field's drag does.
    private func dispatchValueTrack(_ event: InputEvent) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position),
                  let track = lastHitboxes[index].handlers.valueTrack else { return false }
            // The slider's own local point under a render effect (`GX-P` item 3).
            let local = lastHitboxes[index].localPoint(mouse.position)
            StateDispatch.dispatching(to: lastHitboxes[index].id) {   // ID-F: the pressed slider
                track.track(toWindowX: Double(local.x.value))
            }
            return true
        case .mouseDragged(let mouse):
            guard let id = active,
                  let region = lastHitboxes.last(where: { $0.id == id && $0.handlers.valueTrack != nil }),
                  let track = region.handlers.valueTrack else { return false }
            let local = region.localPoint(mouse.position)
            StateDispatch.dispatching(to: id) { track.track(toWindowX: Double(local.x.value)) }
            return true
        default:
            return false
        }
    }

    /// Pointer and text events for fields; see the call site.
    private func dispatchTextInput(_ event: InputEvent) -> Bool {
        switch event {
        case .mouseDown(let mouse):
            guard let index = topmostOpaqueHitbox(in: lastHitboxes, at: mouse.position),
                  let target = lastHitboxes[index].handlers.textInput else { return false }
            let id = lastHitboxes[index].id
            let local = lastHitboxes[index].localPoint(mouse.position)   // `GX-P` item 3
            focus(id)
            setEditState(id, TextEditing.press(at: target.boundary(atWindowX: Double(local.x.value),
                                                                   y: Double(local.y.value)),
                                              clickCount: mouse.clickCount,
                                              extend: mouse.modifiers.contains(.shift),
                                              text: currentText(id, target), state: editState(id)))
            return true
        case .mouseDragged(let mouse):
            guard let id = active, let region = lastHitboxes.first(where: { $0.id == id }),
                  let target = region.handlers.textInput else { return false }
            let local = region.localPoint(mouse.position)   // `GX-P` item 3
            setEditState(id, TextEditing.drag(to: target.boundary(atWindowX: Double(local.x.value),
                                                                  y: Double(local.y.value)),
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

    /// Tab to the next focusable element in tree order, shift-Tab (or AppKit's
    /// backtab character) to the previous, wrapping; with nothing focused,
    /// the first or the last (ruling TI-J). Tabbing into a text field selects
    /// its text, as AppKit's fields do. A Tab with command, control or option
    /// is not traversal and falls through.
    private func dispatchFocusTraversal(_ event: InputEvent) -> Bool {
        guard case .keyDown(let key) = event,
              key.modifiers.isDisjoint(with: [.command, .control, .option]) else { return false }
        let backward: Bool
        switch key.charactersIgnoringModifiers {
        case "\t": backward = key.modifiers.contains(.shift)
        case "\u{19}": backward = true
        default: return false
        }
        let order = lastFocusRegistry.tabOrder
        guard let first = order.first, let last = order.last else { return false }
        let next: GlobalElementID
        if let current = focusedElement, let index = order.firstIndex(of: current) {
            next = order[(index + (backward ? order.count - 1 : 1)) % order.count]
        } else {
            next = backward ? last : first
        }
        focus(next)
        if let target = lastFocusRegistry.textTarget(for: next) {
            var state = editState(next)
            state.anchor = 0
            state.head = currentText(next, target).count
            state.composition = .none
            state.revealsCaret = true
            state.history.openGroup = nil
            setEditState(next, state)
        }
        return true
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
