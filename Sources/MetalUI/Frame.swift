import MetalUICore
import MetalUILayout
import MetalUIPrimitives
#if canImport(MetalUIText)
import MetalUIText
#else
/// Off Apple platforms there is no CoreText shaping cache. This empty type
/// keeps `Frame`'s and `Window`'s initialisers to one spelling on every
/// platform; nothing reads it there (ruling XP-B).
struct ShapingCache { init() {} }
#endif
import MetalUITextSystem
import MetalUIPlatform

/// The single owner of one frame's mutable state (spec §4.1).
///
/// `LayoutPass`, `PrepaintPass` and `PaintPass` are thin structs over this
/// class; the state lives here exactly once, and each pass exposes the slice of
/// it that its phase may touch. Making the *passes* own state instead would
/// force it to be copied or shared between phases, which is the bug the split
/// exists to prevent.
///
/// **`init` and every phase operation are `internal` on purpose.** The
/// compile-time guarantee that an element cannot paint during layout rests
/// entirely on an element being unable to obtain a pass it was not handed: from
/// outside `MetalUI` there is no way to construct a `Frame` and no way to
/// construct a `PaintPass`. Inside the module the compiler does not stop you —
/// that half is a convention, and `codeOutsideTheFrameworkCannotFabricateAPaintPass`
/// pins the half that is enforced.
@MainActor
public final class Frame {
    /// The space offered to the root element, in logical points.
    public let contentSize: Size<Pixels>

    /// Logical points to device pixels for this frame's target. Applied once,
    /// in `fill`, so element code never has to think about it.
    public let scaleFactor: Float

    /// This frame's display-link timestamp, in seconds — identical for every
    /// element in this frame, because it is read once here rather than by each
    /// element calling a wall clock.
    ///
    /// **A borrowed M4 primitive** (spec §8 of the clipping/scroll design): the
    /// input to a time-based animation, not an animation system. Defaulted to
    /// `0` so every existing `Frame(...)` call site in the corpus and the test
    /// suite keeps compiling unchanged; `Window` is the only production caller
    /// that passes a real one.
    public let timestamp: Double

    /// The last known mouse position, or `nil` before any mouse event has ever
    /// reached the window. `Window` is the only owner of "last known" — it
    /// survives across frames the way `timestamp`'s underlying clock does not —
    /// and hands the current value in here on construction, the same way it
    /// hands in `theme` and `timestamp`.
    ///
    /// This is the input `resolveHover(at:)` reads at the prepaint/paint
    /// boundary (design spec §3.3). Defaulted to `nil` for the same reason
    /// `timestamp` defaults to `0`: every existing `Frame(...)` call site keeps
    /// compiling, and a frame built with no position registers no hover at all
    /// — there is nothing to resolve against.
    let mousePosition: Point<Pixels>?

    /// The element holding "active" state this frame — the hitbox that
    /// received `mouseDown` and has not yet seen `mouseUp` (design spec §3.4).
    ///
    /// **Handed in from `Window`, not computed here**, because active state
    /// must survive the frames between `mouseDown` and `mouseUp` and a `Frame`
    /// does not: it is discarded at the end of `drawFrameIfNeeded`
    /// (`Window.swift`). Keyed by `GlobalElementID` rather than `HitboxID` for
    /// `HitboxID`'s own reason — a per-frame index cannot key anything that
    /// outlives the frame that issued it.
    let activeElement: GlobalElementID?

    /// Set by an element that needs another frame — an in-progress animation.
    ///
    /// **A borrowed M4 primitive** (spec §8 of the clipping/scroll design): the
    /// input to animation, not an animation system. `Window` reads it after
    /// render and marks itself dirty, which unpauses the display link.
    private(set) var wantsAnotherFrame = false

    /// Ask for another frame after this one — for an animation in progress.
    func requestAnotherFrame() { wantsAnotherFrame = true }

    /// Where a ``ScrollViewProxy`` built in this frame enqueues its
    /// `scrollTo` requests (ruling `DD-G` item 3). `Window` replaces this with
    /// its own queue before rendering, so a request outlives the frame whose
    /// proxy made it; a bare `Frame`'s own queue dies with it.
    var scrollRequestQueue = ScrollRequestQueue()

    // MARK: - `scrollTo` resolution (plan task 10, part 1, rulings `DD-G`, `DD-K`)

    /// The requests this frame resolves, taken from `scrollRequestQueue` when
    /// the frame starts rendering. Anything still unresolved after prepaint is
    /// dropped (T8): a request never outlives the frame that looked for it.
    private var scrollRequests: [ScrollRequest] = []
    private var scrollRequestResolved: [Bool] = []
    private var unresolvedScrollRequestCount = 0

    /// Whether any request is still looking for its target — the one flag
    /// `recordElementBounds` and `List.prepaint` read before doing any work.
    var hasUnresolvedScrollRequests: Bool { unresolvedScrollRequestCount > 0 }

    /// Whether this frame notes typed keys (`DD-K`): true only while a request
    /// is pending, so a steady frame pays one flag read per `ForEach` and per
    /// `List` and notes nothing (`scrollKeyCount` reads 0).
    private(set) var notesScrollKeys = false

    /// The typed keys noted this frame (`DD-K`): each `ForEach` element scope's
    /// key and each realised `List` row's `datum.id`, by the scope's or row's
    /// id. `recordElementBounds`' match reads an id's key here first and falls
    /// back to its `String` name, so `scrollTo(10)` does not reach a `ForEach`
    /// element keyed `"10"` or an `.id("10")`.
    private(set) var scrollKeys: [GlobalElementID: AnyHashable] = [:]

    /// How many typed keys this frame noted — a work counter.
    var scrollKeyCount: Int { scrollKeys.count }

    /// Each resolved request's scroller and the offset it moves to, in
    /// resolution order — applied after paint (`applyScrollResolutions`).
    private var scrollResolutions: [(scroller: GlobalElementID, offset: Double)] = []

    /// Notes `id`'s typed key. Callers check `notesScrollKeys` first.
    func noteScrollKey(_ id: GlobalElementID, _ key: AnyHashable) {
        scrollKeys[id] = key
    }

    /// Takes the window's pending requests at the start of a render.
    private func beginScrollRequests() {
        scrollRequests = scrollRequestQueue.take()
        scrollRequestResolved = Array(repeating: false, count: scrollRequests.count)
        unresolvedScrollRequestCount = scrollRequests.count
        notesScrollKeys = !scrollRequests.isEmpty
    }

    /// The unresolved requests whose reader encloses `id`, as (index, key) —
    /// `unresolvedScrollRequestsWithScope(enclosing:)`, narrowed (`VL-T`).
    func unresolvedScrollRequests(enclosing id: GlobalElementID) -> [(index: Int, key: AnyHashable)] {
        unresolvedScrollRequestsWithScope(enclosing: id).map { ($0.index, $0.key) }
    }

    /// The unresolved requests whose reader encloses `id`, each with its
    /// reader's scope and its anchor (ruling `VL-P`): what a variable-height
    /// `List` needs to carry a refinement of a request onto the next frame
    /// with the request's own scope and anchor. The two-member
    /// `unresolvedScrollRequests(enclosing:)` above is this, narrowed (`VL-T`).
    func unresolvedScrollRequestsWithScope(enclosing id: GlobalElementID)
        -> [(index: Int, key: AnyHashable, scope: GlobalElementID, anchor: UnitPoint?)] {
        guard hasUnresolvedScrollRequests else { return [] }
        return scrollRequests.indices.compactMap { index in
            let request = scrollRequests[index]
            guard !scrollRequestResolved[index],
                  Self.isStrictDescendant(id, of: request.scope) else { return nil }
            return (index, request.key, request.scope, request.anchor)
        }
    }

    /// Each anchor adjustment noted this frame, by scroller (ruling `VL-G`
    /// item 2) — applied after paint, after the absolute resolutions.
    private var scrollAnchorAdjustments: [(scroller: GlobalElementID, delta: Double)] = []

    /// Notes that `scroller`'s stored offset must move by `delta` after this
    /// frame so that what is on screen stays put (ruling `VL-G` item 2): a
    /// variable-height `List` calls it from `prepaint` when re-measured rows
    /// above its anchor row moved that row by `delta` in content coordinates.
    ///
    /// Adjustments for one scroller are summed, and **added after** that
    /// scroller's `scrollTo` resolution in `applyScrollResolutions` (or to the
    /// stored offset when there is none) — so a resolution computed in this
    /// frame's coordinates lands in the next frame's. A zero or non-finite
    /// delta is never recorded, so a steady list asks for no frame.
    func noteScrollAnchorAdjustment(scroller: GlobalElementID, delta: Double) {
        guard delta != 0, delta.isFinite else { return }
        scrollAnchorAdjustments.append((scroller, delta))
    }

    /// Whether request `index` has already found its target (first match wins).
    func isScrollRequestResolved(_ index: Int) -> Bool { scrollRequestResolved[index] }

    /// Resolves request `index` against `target` (layout space) and the
    /// innermost scroller frame in effect — the target's nearest scroller
    /// (T14). A target in no scroller resolves to nothing, and the request is
    /// spent either way.
    func resolveScrollRequest(_ index: Int, target: Bounds<Pixels>) {
        guard !scrollRequestResolved[index] else { return }
        scrollRequestResolved[index] = true
        unresolvedScrollRequestCount -= 1
        guard let scroller = activeScrollerFrame else { return }
        let offset = Self.scrollOffset(bringing: target, into: scroller,
                                       anchor: scrollRequests[index].anchor)
        scrollResolutions.append((scroller.scrollerID, offset))
    }

    /// Matches every unresolved request against `id` and its ancestors — the
    /// first element recorded at or under a key equal to the request's, inside
    /// the request's reader (`DD-G` item 2, `DD-K`). Called by
    /// `recordElementBounds`, which the four element-bounds sites already call
    /// in document order, so the first match is the first such element.
    private func matchScrollRequests(_ id: GlobalElementID, _ bounds: Bounds<Pixels>) {
        var ancestor: GlobalElementID? = id
        while let candidate = ancestor, hasUnresolvedScrollRequests {
            if let key = scrollKey(of: candidate) {
                for index in scrollRequests.indices
                where !scrollRequestResolved[index] && scrollRequests[index].key == key
                    && Self.isStrictDescendant(candidate, of: scrollRequests[index].scope) {
                    resolveScrollRequest(index, target: bounds)
                }
            }
            ancestor = candidate.parent
        }
    }

    /// `id`'s key: its typed key when one was noted, else its `String` name
    /// (an `.id(_:)`, `ID-G`), else none.
    private func scrollKey(of id: GlobalElementID) -> AnyHashable? {
        if let typed = scrollKeys[id] { return typed }
        if case .named(let name) = id.component { return AnyHashable(name.name) }
        return nil
    }

    /// Whether `scope` is a proper ancestor of `id` — a proxy's reach (S0–S2).
    private static func isStrictDescendant(_ id: GlobalElementID, of scope: GlobalElementID) -> Bool {
        var ancestor = id.parent
        while let candidate = ancestor {
            if candidate == scope { return true }
            ancestor = candidate.parent
        }
        return false
    }

    /// The offset that brings `target` into `scroller` (`DD-G` item 2):
    /// with an anchor, `minY − anchor.y × (viewport − height)` (T1–T3, T9;
    /// `x`/`width` horizontally, T11); with none, the least distance — above
    /// → top-aligned, below → bottom-aligned, visible → unmoved (T4–T6).
    /// Clamped to the content (T7).
    static func scrollOffset(bringing target: Bounds<Pixels>, into scroller: ScrollerFrame,
                             anchor: UnitPoint?) -> Double {
        let vertical = scroller.axis == .vertical
        let start = Double(vertical ? target.origin.y.value - scroller.contentOrigin.y.value
                                    : target.origin.x.value - scroller.contentOrigin.x.value)
        let length = Double(vertical ? target.size.height.value : target.size.width.value)
        let viewport = scroller.viewportExtent
        let offset: Double
        if let anchor {
            offset = start - (vertical ? anchor.y : anchor.x) * (viewport - length)
        } else if start < scroller.offset {
            offset = start
        } else if start + length > scroller.offset + viewport {
            offset = start + length - viewport
        } else {
            offset = scroller.offset
        }
        return ScrollChrome.clamp(offset: offset, content: scroller.contentExtent, viewport: viewport)
    }

    /// Writes each resolved scroller's offset, then adds each anchor
    /// adjustment (`VL-G` item 2) — after paint, so the frame that
    /// resolved a request paints the old offset consistently with its
    /// hitboxes, and the next frame shows the new one — through `withState`
    /// (as `ScrollChrome.resolvedOffset`'s write-back does: no `onWrite`), and
    /// asks for that next frame. Then drops every request, resolved or not.
    private func applyScrollResolutions() {
        for resolution in scrollResolutions {
            stateTable.withState(resolution.scroller, initial: ScrollState()) {
                $0.offset = resolution.offset
            }
        }
        // `VL-G` item 2: after the absolute writes, so a resolution and an
        // adjustment for one scroller compose additively; several adjustments
        // for one scroller sum.
        for adjustment in scrollAnchorAdjustments {
            stateTable.withState(adjustment.scroller, initial: ScrollState()) {
                $0.offset += adjustment.delta
            }
        }
        if !scrollResolutions.isEmpty || !scrollAnchorAdjustments.isEmpty { requestAnotherFrame() }
        scrollResolutions = []
        scrollAnchorAdjustments = []
        scrollRequests = []
        scrollRequestResolved = []
        unresolvedScrollRequestCount = 0
    }

    /// True once anything in this frame has reported an `Animation` that is
    /// still interpolating **after this frame's own update** — the property
    /// M4 spec 1 refused to declare without a writer (ruling `RX-O`), and the
    /// one the binding design spec §4.4's idle guard is written in terms of.
    ///
    /// **It must see BOTH animation subsystems, and computing it from layout
    /// alone is the way to get this wrong.** `animated(_:_:for:pass:)`
    /// (`AnimatedStyle.swift`) animates `Style`/`Decoration` from `LayoutPass`
    /// through the `$anim` slot; `animatedColor(_:for:pass:)`
    /// (`AnimatedColor.swift`) animates the resolved background colour from
    /// `PaintPass` through `$anim-color`, because only `PaintPass` carries a
    /// theme. A colour fade on an element whose `Style` never changes raises
    /// nothing during layout, so a layout-only criterion would be a fade that
    /// stops the instant input stops arriving. Both helpers call
    /// `noteActiveAnimation()`; `Window` reads this AFTER the whole of
    /// `render` — layout, prepaint and paint — so the paint-phase contribution
    /// arrives in time with no ordering change.
    ///
    /// **A per-frame answer, not a latch.** It is `false` on the frame a
    /// duration curve lands on its target (termination is exact, so nothing is
    /// left in flight), which is precisely what lets the display link pause on
    /// the frame *after* the last animation ends rather than one frame later.
    ///
    /// **Distinct from `wantsAnotherFrame` above, and after this task nothing
    /// raises both.** `wantsAnotherFrame` means "mark the window DIRTY next
    /// frame" and its callers are `ScrollView`'s scroll-indicator fade, which
    /// predates the `Animation` type and drives itself by dirtying, and — since
    /// plan task 10's `DD-F` — a `List` whose window went stale, once; neither
    /// raises `noteActiveAnimation()`. This means
    /// "an `Animation` is interpolating", and it keeps the loop running
    /// *without* dirtying the window — so a window mid-fade reports
    /// `needsRedraw == false`, which is true: nobody changed anything.
    private(set) var hasActiveAnimations = false

    /// Report that an `Animation` in this frame is still interpolating.
    func noteActiveAnimation() { hasActiveAnimations = true }

    /// The transaction this build inherited from a `withAnimation` that ran
    /// since the last one — spec §3's "the **next frame build** carries that
    /// animation as ambient context on the passes, the way
    /// `LayoutPass.scrollContext` already is".
    ///
    /// A `let`, for `theme`'s reason: the two halves of one frame must not
    /// resolve the same transition under different animations. `Window` takes
    /// it from `Animation.parkedTransaction` once per drawn frame and hands it
    /// in here; a `Frame` built by a test defaults to `nil` and its callers
    /// fall back to the lexical `Animation.pendingTransaction`.
    let transaction: Animation?

    // MARK: - The transaction stack (plan task 13, ruling `AN-Y`)

    /// The transaction in effect at the element being visited: the root —
    /// `transaction` above, with the parked `disablesAnimations` — until a
    /// `TransactionScope` (`.animation(_:value:)`, `.transaction(_:)`) pushes
    /// its own around its content, in layout and paint (`withTransactionScope`).
    /// `LayoutPass.transaction` and `PaintPass.transaction` read its
    /// `animation`. The call stack is the stack, as for `environmentTop`.
    private(set) var transactionTop: Transaction

    /// Whether every change in this build snaps (ruling `CR-Q` item 3): the
    /// root transaction and every scope's carry no animation, whatever a
    /// `withAnimation`, `.animation(_:value:)` or `.transaction(_:)` says.
    /// Set only on the first frame's second build, which re-runs the tree in
    /// the scheme its preference chose: diffing it against the adopted first
    /// build is not a change anyone made, so nothing may animate or
    /// transition from it — the presented frame equals one build in the
    /// target scheme.
    let snapsEveryChange: Bool

    /// How many `TransactionScope`s are open around the element being
    /// visited — part of `.animation(_:value:)`'s store key, so two scopes
    /// nested at one position keep separate values (spec test 1.11).
    private(set) var transactionDepth = 0

    /// Runs `body` with `transaction` as the top, restoring the previous top
    /// when it returns.
    func withTransactionScope<R>(_ transaction: Transaction, _ body: () -> R) -> R {
        let saved = transactionTop
        transactionTop = transaction
        if snapsEveryChange { transactionTop.animation = nil }
        transactionDepth += 1
        defer {
            transactionTop = saved
            transactionDepth -= 1
        }
        return body()
    }

    /// How many `LifecycleScope`s are open around the element being visited —
    /// part of a lifecycle entry's store key, so two lifecycle modifiers
    /// stacked at one position keep two entries (ruling `LC-C` item 2).
    private(set) var lifecycleDepth = 0

    /// The hover regions this frame registered (ruling `SV-N` item 2) — read
    /// by `Window`, which skips every hover recompute for a frame with none
    /// (`SV-U`).
    private(set) var hoverRegionCount = 0

    /// The pointer-style regions this frame registered (ruling `CI-H` item 7)
    /// — read by `Window`, which does no per-hitbox style work for a frame
    /// with none (`SV-U`'s shape).
    private(set) var pointerStyleRegionCount = 0

    /// The presentation scopes enclosing the one being laid out — the depth in
    /// its registry key (`SV-K` item 2, `LC-U`'s reason).
    private(set) var presentationDepth = 0

    /// The presentation records this build noted, in registration order
    /// (`SV-K` item 2), adopted by `Window` after the build.
    var presentationRecords: [PresentationRecord] = []
    /// Records noted per key this build — the occurrence rule (`MV-M` item 5).
    var presentationOccurrences: [GlobalElementID: Int] = [:]

    /// The toolbar scopes this build noted, in build pre-order (ruling `MD-I`
    /// item 5) — the main tree's only: a presentation root's are dropped when
    /// it closes (`endPresentationPreferences`). Adopted by `Window` after the
    /// build.
    var toolbarRecords: [ToolbarRecord] = []

    /// Whether this build draws the window's toolbar as a strip (`MD-K`): the
    /// window's last `setToolbar` answered `false`. Set by `Window` before
    /// the build; `false` — today's path — everywhere else.
    var drawsToolbarStrip = false
    /// Whether this build laid a strip out (`drawsToolbarStrip` and at least
    /// one item) — read back by `Window`, whose one extra build runs when the
    /// strip's presence must change (`MD-K` item 5).
    private(set) var drewToolbarStrip = false

    func withPresentationScope<R>(_ body: () -> R) -> R {
        presentationDepth += 1
        defer { presentationDepth -= 1 }
        return body()
    }

    /// Runs `body` one lifecycle scope deeper.
    func withLifecycleScope<R>(_ body: () -> R) -> R {
        lifecycleDepth += 1
        defer { lifecycleDepth -= 1 }
        return body()
    }

    /// The window's `AnimationStore` (ruling `AN-AB`): animation state kept
    /// out of `StateTable`. A `Frame` built without a window gets a fresh one.
    let animationStore: AnimationStore

    /// CSS's `rem` basis for `Length.rem`. One value per frame.
    ///
    /// **M2 came and went without making this settable, and that was a
    /// decision rather than an oversight.** This comment used to predict that
    /// "the text system may make it settable in M2". It did not: `Text` carries
    /// its own `fontSize` in points and never consults this value, and `Frame`
    /// is only ever constructed with the 16 default from `Window` — so a `rem`
    /// still resolves against 16 whatever font a `Text` is using. The two are
    /// unrelated quantities that share a word: this one is the *document* root
    /// font size CSS resolves `rem` against, and M2 supplies a *per-element*
    /// size. Wiring one to the other needs a root-level text style, which no
    /// element has. Measured rather than assumed: `grep -rn "rootFontSize:"
    /// Sources/ Tests/` finds no caller that passes it to a `Frame` at all, so
    /// the default below is the only value the engine has ever seen.
    let rootFontSize: Double

    /// The theme in effect at the element being visited (spec §7.9): the
    /// nearest `.theme(_:)` scope's, else the root's (ruling EV-G).
    ///
    /// **Scoped now, and still fixed per scope for the whole frame.** It used
    /// to be a `let`, so the two halves of one frame could not resolve the same
    /// token differently. That property survives scoping: the root theme is a
    /// `let` (`rootTheme`), and a scope computes its values once, in layout,
    /// and re-pushes the stored result in prepaint and paint (ruling EV-V), so
    /// one element reads one theme in every phase. `Window` still swaps the
    /// root theme *between* frames and marks §4.4's dirty flag.
    ///
    /// Read **in place** from `environmentTop`, not through
    /// `environmentSnapshot()`, so it costs no copy and is not counted
    /// (ruling EV-O).
    ///
    /// Reachable from `PaintPass` only. Nothing in layout or prepaint consumes a
    /// colour — `LayoutPass` contributes `Style`, which has no colour field at
    /// all, and `PrepaintPass` reads resolved rects — so exposing it there would
    /// be an API with no reader. `EnvironmentValues.theme` is internal for the
    /// same reason.
    var theme: Theme { environmentTop.theme }

    /// The theme this frame was built with — `Window.theme`, handed in through
    /// `init`. The root environment's `theme` is stamped from this and from
    /// nothing else (ruling EV-H), so an in-module write to
    /// `rootEnvironment.theme` is silently re-stamped.
    private let rootTheme: Theme

    // MARK: - Environment (rulings EV-A, EV-H, EV-O, EV-U, EV-V)

    /// The environment in effect at the element being visited.
    ///
    /// Starts as `rootEnvironment` and is replaced only inside
    /// `withEnvironment`, which restores it when its body returns — so the
    /// call stack is the stack, and an unbalanced push is not expressible
    /// (the discipline `clipStack` and `scrollContextStack` use). Read in place
    /// by `theme`; handed out as a copy only by `environmentSnapshot()`.
    private(set) var environmentTop: EnvironmentValues

    private var storedRootEnvironment: EnvironmentValues

    /// True from `render`'s first line to its last, and nowhere else (ruling
    /// EV-Z). Not cleared in a `defer`, for the reason `render`'s atlas bracket
    /// gives: the only way out of `render` early is a trap, which aborts.
    ///
    /// `private(set)`, not `private`: a lifecycle test reads it from inside an
    /// action to prove the action runs outside the build (ruling `LC-E`).
    private(set) var isRendering = false

    /// The values every scope starts from: `Window.environment`, set by
    /// `Window.drawFrameIfNeeded` on the line after it builds this frame. A
    /// `Frame` built without a window (every test) keeps `EnvironmentValues()`,
    /// whose locale is the root locale `Locale(identifier: "")` (ruling EV-Y).
    ///
    /// **The setter re-stamps two fields** (rulings EV-H, EV-U, EV-AA):
    /// `theme` from the `theme:` this frame was built with, and `displayScale`
    /// from its scale factor. `Window.theme` stays the root theme's only
    /// source, and the root's scale is the drawable's, so
    /// `window.environment.theme = .dark` and
    /// `window.environment.displayScale = 3` — which compile — change nothing
    /// at the root. A scope below the root may write `displayScale` (EV-AA).
    ///
    /// **It also resets the top, so it traps while `render` runs** (ruling
    /// EV-Z). From inside a phase it would replace every open scope's values
    /// for the rest of that scope's content, and a scope's restoring `defer`
    /// would then put the enclosing values back — silently. Set it before a
    /// render or between two renders. Pinned by
    /// `aRootEnvironmentWriteDuringARenderTraps` (one arm per phase) and
    /// `aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap`.
    var rootEnvironment: EnvironmentValues {
        get { storedRootEnvironment }
        set {
            precondition(!isRendering,
                         "Frame.rootEnvironment set during render: it would replace every open scope's values (ruling EV-Z)")
            var values = newValue
            values.theme = rootTheme
            values.displayScale = Self.displayScale(forScaleFactor: scaleFactor)
            storedRootEnvironment = values
            environmentTop = values
        }
    }

    /// The root's `displayScale`: the surface's scale factor, or 1 when it has
    /// not reported a usable one — a 0 or NaN from a backend still configuring
    /// itself would otherwise hand every reader a nonsense scale (ruling EV-AA;
    /// the guard that protected `pixelLength` before it was derived).
    private static func displayScale(forScaleFactor scale: Float) -> Double {
        guard scale.isFinite, scale > 0 else { return 1 }
        return Double(scale)
    }

    /// A writer's values: `write` applied to a copy of the **current top**, so
    /// a transform composes with what it inherits and a nearer writer wins
    /// (ruling EV-A). Called once per scope per frame, by
    /// `EnvironmentScope.requestGroupLayout` only (ruling EV-V).
    ///
    /// **A `.transform` cannot change `theme`**: it is put back from the top
    /// it copied, after the transform runs, because
    /// `.environment(\.self, EnvironmentValues())` compiles outside the module
    /// and would otherwise reset it (ruling EV-U). `.theme` is the one write
    /// that sets a theme. **`displayScale` is not re-stamped** (ruling EV-AA,
    /// which withdrew `EV-U`'s `pixelLength` half): a scope may write it, and a
    /// `\.self` reset reads 1, as in SwiftUI.
    func scopedValues(applying write: EnvironmentWrite) -> EnvironmentValues {
        environmentTransformCount += 1
        var values = environmentTop
        switch write {
        case .transform(let transform):
            transform(&values)
            values.theme = environmentTop.theme
            // A scope that changes the scheme gets the window's variant for
            // it (rulings `CR-K` item 2, `CR-S`): SwiftUI's subtree flips with
            // the write (probe `V1`), so the tokens flip too. Pinned by
            // `aColorSchemeScopeSelectsTheWindowsVariantForItsSubtree` and
            // `aSelfResetBelowADarkScopeReadsLightAndTheLightVariant`.
            if values.colorScheme != environmentTop.colorScheme {
                values.theme = values.colorScheme == .dark ? darkTheme : lightTheme
            }
        case .theme(let theme):
            values.theme = theme   // tokens only; `colorScheme` untouched (`CR-K` item 3)
        case .preferredColorScheme:
            break   // values unchanged: a preference is reported, not written (`CR-L` item 1)
        }
        return values
    }

    // MARK: - Colour scheme preference (rulings `CR-L`, `CR-T`)

    /// The window's light and dark themes (rulings `CR-K`, `CR-S`):
    /// `Window.lightTheme`/`darkTheme`, handed in through `init`. A scope that
    /// changes `colorScheme` sets its subtree's theme to the new scheme's
    /// variant. Frame fields, not environment fields — no scope writes them.
    let lightTheme: Theme
    let darkTheme: Theme

    /// How many `.preferredColorScheme` scopes enclose the element being
    /// built. Only a scope at depth 0 reports (`CR-L` item 3): an outer
    /// modifier replaces its content's value, `nil` included (probes `P5`,
    /// `P6`).
    private var colorSchemePreferenceDepth = 0
    /// The first non-nil top-level preference in the main tree, in build
    /// order (probes `P3`, `P4`, `P7`).
    private(set) var mainColorSchemePreference: ColorScheme?
    /// The first non-nil top-level preference inside a presentation root —
    /// a popover's chrome or an absolute `Deferred` — counted only when the
    /// main tree has none (`CR-T`).
    private(set) var presentationColorSchemePreference: ColorScheme?

    /// This frame's preference, read by `Window` after the build: the main
    /// tree's, else a presentation root's (`CR-T`).
    var collectedColorSchemePreference: ColorScheme? {
        mainColorSchemePreference ?? presentationColorSchemePreference
    }

    // MARK: Content size limits (ruling `SV-L` item 2)

    /// Which of the root's limits `computeRootLayout` measures — the window's
    /// `windowResizability`, set by `Window` before the build. `.automatic`,
    /// the default, measures nothing.
    var contentSizeLimitsMode: WindowResizability = .automatic
    /// The root's answer at a zero proposal, under `.contentMinSize` or
    /// `.contentSize`; `nil` otherwise. Read by `Window` after the build.
    private(set) var contentMinimum: Size<Pixels>?
    /// The root's answer at an infinite proposal, under `.contentSize`; `nil`
    /// otherwise. An axis may be infinite (a greedy root): no maximum there.
    private(set) var contentMaximum: Size<Pixels>?

    private static func size(of measurement: LayoutMeasurement, plus top: Double = 0) -> Size<Pixels> {
        Size(width: Pixels(Float(measurement.size.width)), height: Pixels(Float(measurement.size.height + top)))
    }

    /// Runs `body` — a `.preferredColorScheme(value)` scope's content — after
    /// recording `value` if this scope is top-level and no earlier top-level
    /// scope decided (`CR-L` item 3). Called from both of `EnvironmentScope`'s
    /// layout entries (`OM-AI`'s two halves).
    func withColorSchemePreference<R>(_ value: ColorScheme?, _ body: () -> R) -> R {
        if colorSchemePreferenceDepth == 0 && mainColorSchemePreference == nil {
            mainColorSchemePreference = value
        }
        colorSchemePreferenceDepth += 1
        defer { colorSchemePreferenceDepth -= 1 }
        return body()
    }

    /// Opens a presentation candidate's content build (`CR-T`): preferences
    /// recorded inside it are kept apart from the main tree's, and its toolbar
    /// records can be dropped (`MD-I` item 5). Returns the main tree's value
    /// so far and the toolbar record count, for `endPresentationPreferences`.
    func beginPresentationPreferences() -> PresentationCollectionMark {
        let saved = mainColorSchemePreference
        mainColorSchemePreference = nil
        return PresentationCollectionMark(colorScheme: saved, toolbarCount: toolbarRecords.count)
    }

    /// What `beginPresentationPreferences` saved: the main tree's colour-scheme
    /// preference so far (`CR-T`) and how many toolbar records preceded the
    /// candidate's content (`MD-I` item 5).
    struct PresentationCollectionMark {
        let colorScheme: ColorScheme?
        let toolbarCount: Int
    }

    /// Closes what `beginPresentationPreferences` opened. A presentation
    /// root's first preference goes to the presentation slot; content that
    /// turned out not to be one (an in-flow `Deferred`) is the main tree, in
    /// build order.
    func endPresentationPreferences(saved mark: PresentationCollectionMark, isPresentation: Bool) {
        let saved = mark.colorScheme
        let inner = mainColorSchemePreference
        // A presentation root's toolbars are ignored (`MD-I` item 5, probe
        // `PO`): only the records its content appended are dropped.
        if isPresentation, toolbarRecords.count > mark.toolbarCount {
            toolbarRecords.removeSubrange(mark.toolbarCount...)
        }
        if isPresentation {
            if presentationColorSchemePreference == nil { presentationColorSchemePreference = inner }
            mainColorSchemePreference = saved
        } else {
            mainColorSchemePreference = saved ?? inner
        }
    }

    /// Runs `body` with `values` as the top, restoring the previous top when it
    /// returns. The saved top lives in this call's own local, so nesting is the
    /// call stack.
    func withEnvironment<R>(_ values: EnvironmentValues, _ body: () -> R) -> R {
        environmentPushCount += 1
        let saved = environmentTop
        environmentTop = values
        defer { environmentTop = saved }
        return body()
    }

    /// A copy of the top, for a public reader: `pass.environment`, or a bind of
    /// a type that declares an `@Environment`. The framework's own reads
    /// (`theme`) read the top in place and do not come through here.
    func environmentSnapshot() -> EnvironmentValues {
        environmentSnapshotCount += 1
        return environmentTop
    }

    /// Test observables for ruling EV-O. A tree with no writer pushes 0 and
    /// transforms 0; W writers push 3W and transform W per frame; a tree with
    /// no reader snapshots 0, however large. No production reader.
    private(set) var environmentPushCount = 0
    private(set) var environmentSnapshotCount = 0
    private(set) var environmentTransformCount = 0

    /// Layout nodes for this frame.
    ///
    /// **A `LayoutNodeID` *can* outlive the frame that minted it, which is why
    /// the tree is stamped.** It was tempting to argue the opposite — a `Frame`
    /// is built per frame, its tree is never `reset`, so id and storage die
    /// together — but that is a claim about the tree, not about the id, and the
    /// id is a `Sendable` value an element may copy anywhere. The carrier that
    /// makes m1a's ruling C-3 reachable here is `pass.withState`: its `S` is
    /// unconstrained, so an element may stash a `LayoutNodeID` in the
    /// cross-frame state table and read it back next frame, against a tree that
    /// no longer knows it. Nothing in the type system prevents that, and a
    /// stored property on a reused element value is a second, narrower route.
    ///
    /// So the hazard is closed rather than argued away: every `Frame` draws a
    /// fresh generation from `nextTreeGeneration`, and `LayoutTree` rejects an
    /// id from any other. A stale id now traps at the accessor instead of
    /// silently returning whatever node shares its index.
    let tree: LayoutTree

    /// Source of `LayoutTree` generations, one per `Frame`, never reused.
    ///
    /// A plain `static var` and not an atomic: it is isolated to the main actor
    /// by `Frame`'s own `@MainActor`, so the compiler — not a comment — is what
    /// rules out a concurrent increment. `UInt64` at one per frame overflows
    /// after about 10^11 years at 120 Hz.
    private static var nextTreeGeneration: UInt64 = 1

    /// Primitives emitted during paint. Written only through `fill`.
    private(set) var scene = Scene()

    /// Clip and translation, innermost last. Both are in **logical points**;
    /// `fill` and `draw` scale on the way to the scene as they already do.
    ///
    /// **This is emission state, not geometry.** `bounds(of:)` keeps returning
    /// what the engine computed, untranslated — a child that fills its own
    /// resolved bounds is translated automatically and needs to know nothing
    /// about scrolling. It is the same division `fill` already makes for the
    /// scale factor, and for the same reason: a caller who could see the value
    /// would apply it a second time.
    private var clipStack: [(clip: Bounds<Pixels>, offset: Point<Pixels>, radii: Corners<Pixels>)] = []

    /// The clip currently in effect, in logical points. The whole surface when
    /// no `clipped(to:offsetBy:)` block is active — the same "no clip" answer
    /// `fill`/`draw` always passed before this stack existed.
    var activeClip: Bounds<Pixels> {
        guard clipBase > 0 else {
            return clipStack.last?.clip ?? Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                                  size: contentSize)
        }
        return clipStack.count > clipBase ? clipStack[clipStack.count - 1].clip : Self.unboundedLocalClip
    }

    /// The first `clipStack` entry `activeClip` reads (ruling `GX-G`): 0 —
    /// every entry — outside every render effect. A non-flattening effect scope
    /// (always, in prepaint) sets it to the stack's depth at its entry, so the
    /// clips pushed inside it intersect among themselves in its LOCAL space and
    /// the clip outside becomes the scope's outer mask; a `Deferred` sets it
    /// below its root clip. `activeOffset` ignores it: the scroll translation
    /// stays in force inside an effect. Restored by whoever moved it.
    var clipBase = 0

    /// The clip depth at the entry of the innermost open **flattening** paint
    /// effect (ruling `GX-X`, the LF-a fix), `nil` outside every one (`GX-Y`:
    /// an `Int` with 0 for "none" could not tell a scope opened at depth 0, the
    /// window root, from no scope). A `Deferred` needs no reset: it raises
    /// `clipBase` to its entry depth and pushes its root clip at once, so
    /// `atFlatteningEntry` is false inside it. The first clip pushed inside such a scope
    /// (`clipStack.count` equal to it, with no non-flattening split above it)
    /// does **not** intersect the clip in force at the scope's entry — that
    /// clip is in the space the effect maps INTO, the pushed one in the
    /// content's — so clips pushed inside intersect among themselves in local
    /// space, are mapped by the scope, and only then are cut by the entry clip
    /// (`insertThroughScopes`). Unlike `clipBase` it leaves `activeClip` alone:
    /// a primitive with no clip pushed inside still reads the entry clip, as
    /// before. Restored by whoever moved it.
    var flatteningClipBase: Int? = nil

    /// Whether the clip in force now was read at or outside the entry of the
    /// innermost open flattening effect, with no non-flattening split nearer
    /// (`GX-Y`): no clip has been pushed since that scope opened, so
    /// `activeClip` is its entry clip, in the space it maps INTO — not the
    /// content's. A clip pushed now intersects nothing (`pushClip`), and a
    /// flattening scope opened now has no entry clip of its own to cut by: the
    /// enclosing one's cut, after its map, covers it.
    var atFlatteningEntry: Bool {
        guard let base = flatteningClipBase else { return false }
        return base >= clipBase && clipStack.count == base
    }

    /// The clip a render effect's content sees before any clip is pushed inside
    /// it: unbounded, in local points (`GX-G`).
    static let unboundedLocalClip = Bounds(origin: Point(x: Pixels(-1_000_000), y: Pixels(-1_000_000)),
                                           size: Size(width: Pixels(2_000_000), height: Pixels(2_000_000)))

    /// The corner radii of the clip currently in effect, in logical points.
    /// All zero — a square clip — when no `clipped(to:offsetBy:)` block is
    /// active, or when one is active but was pushed with no radii (every call
    /// site written before this existed).
    var activeClipRadii: Corners<Pixels> {
        guard clipBase > 0 else { return clipStack.last?.radii ?? Corners(all: Pixels(0)) }
        return clipStack.count > clipBase ? clipStack[clipStack.count - 1].radii : Corners(all: Pixels(0))
    }

    /// The translation currently in effect, in logical points. Zero when no
    /// `clipped(to:offsetBy:)` block is active.
    var activeOffset: Point<Pixels> {
        clipStack.last?.offset ?? Point(x: Pixels(0), y: Pixels(0))
    }

    /// Layers, shaped exactly like `clipStack` above and for the same reason:
    /// `deferred` pushes one, `fill`/`draw` stamp whichever is active, and the
    /// closure form that pushes it keeps the stack balanced.
    private var layerStack: [Int] = []

    /// Multiplicative opacity scopes used by native paint modifiers.
    private var opacityStack: [Float] = []
    var activeOpacity: Float { opacityStack.reduce(1, *) }
    func pushOpacity(_ opacity: Float) { opacityStack.append(opacity) }
    func popOpacity() { opacityStack.removeLast() }

    /// The layer currently in effect. `0` — ordinary paint order — when no
    /// `deferred` block is active, the same "nothing special" answer
    /// `activeClip` gives an empty `clipStack`.
    var activeLayer: Int { layerStack.last ?? 0 }

    /// `deferred`'s hoist target. One constant, not a counter: design spec §1
    /// rules out an arbitrary stacking-context system, so `Deferred` is a
    /// single hoist and every instance — nested or not — lands on the same
    /// layer.
    static let rootLayer = 1

    /// Pushes the root layer. Balanced by `popLayer`, reached only through
    /// `deferred`'s `defer`.
    ///
    /// **While collecting accessibility it also opens a portal** (ruling AB-V):
    /// each `Deferred` scope gets a fresh per-frame ordinal, nested ones
    /// included, and every record made inside carries the innermost. The layer
    /// itself cannot serve: every portal shares `rootLayer`, so a portal nested
    /// in a portal would look like its parent's content.
    func pushLayer() {
        layerStack.append(Self.rootLayer)
        if collectsAccessibility {
            portalCount += 1
            portalStack.append(portalCount)
        }
    }

    /// Pops one level pushed by `pushLayer`.
    func popLayer() {
        layerStack.removeLast()
        if collectsAccessibility { portalStack.removeLast() }
    }

    /// Portal ordinals issued this frame, and the ones open now, innermost last
    /// (AB-V). Untouched while not collecting.
    private var portalCount = 0
    private var portalStack: [Int] = []

    /// Pushes an **intersected** clip (radii included, see `intersect(_:radii:_:radii:)`)
    /// and an **accumulated** offset.
    ///
    /// Intersection rather than replacement is what makes nesting correct: an
    /// inner clip wider than its outer must not widen it, or a nested scroller
    /// paints over its parent's chrome. Pinned by
    /// `nestedClipsIntersectRatherThanReplace`.
    ///
    /// **`bounds` is translated by `activeOffset` before the intersection, and
    /// it was not until plan task 5** (ruling `OM-U`; CLAUDE.md's divergence 15,
    /// now retired). `activeClip` is in surface space — `fill` and
    /// `insertHitbox` both translate on the way in — so intersecting an
    /// untranslated rect into it compared two different coordinate spaces.
    /// Inside a scrolled ancestor the inner clip came out at the engine's stored
    /// y rather than the painted one, and once the ancestor had scrolled far
    /// enough the intersection was **empty**: the subtree laid out correctly,
    /// routed wheel events correctly, and drew nothing.
    ///
    /// It was deferred while `ScrollView` was the only caller. Lane 2 of that
    /// task put `pass.clipped(to: bounds, …)` behind a public `.clipped()` on
    /// every `Box`/`Stack`/`Text`/`ModifierLayer`, which changes the defect's
    /// reach from "a `ScrollView` inside a scrolled `ScrollView`" to "any
    /// element inside one" — a `.clipped()` row in the demo's 500-row list would
    /// blank itself on the first scroll. The added term is a **no-op wherever
    /// `activeOffset == 0`**, which is every non-nested scroller in existence,
    /// so it moves no existing pixel. Pinned by
    /// `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` (inverted in
    /// the same commit) and
    /// `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`.
    func pushClip(_ bounds: Bounds<Pixels>, offset: Point<Pixels>,
                 radii: Corners<Pixels> = Corners(all: Pixels(0))) {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        // The first push inside a flattening effect intersects nothing outside
        // it (`GX-X`): `activeClip` there is the entry clip, in another space.
        let (clip, clipRadii) = atFlatteningEntry
            ? (translated, radii)
            : Self.intersect(activeClip, radii: activeClipRadii, translated, radii: radii)
        let composed = Point(x: Pixels(activeOffset.x.value + offset.x.value),
                             y: Pixels(activeOffset.y.value + offset.y.value))
        clipStack.append((clip, composed, clipRadii))
    }

    /// Pops one level pushed by `pushClip` (or `pushRootClip` below —
    /// `clipStack` does not distinguish how a level was pushed, only how it is
    /// popped). Callers reach this only through `clipped(to:offsetBy:)`'s or
    /// `deferred`'s `defer`, which is what keeps the stack balanced — see
    /// those methods' doc comments.
    func popClip() { clipStack.removeLast() }

    /// Pushes a clip covering the whole surface with **no accumulated
    /// offset** — `Deferred`'s escape, as opposed to `pushClip`'s intersect-
    /// and-accumulate. `Deferred` is a portal (spec §4.2): a modal painted
    /// from inside a scrolled `ScrollView` must not inherit that scroll's
    /// translation any more than it inherits the viewport's clip, or it would
    /// slide with the content it is meant to cover. Popped exactly like an
    /// ordinary level, by `popClip`.
    func pushRootClip() {
        clipStack.append((Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: contentSize),
                          Point(x: Pixels(0), y: Pixels(0)),
                          Corners(all: Pixels(0))))
    }

    /// The innermost active `ScrollView`'s ambient context.
    ///
    /// **What it shares with `clipStack` above is the nesting discipline, and
    /// nothing else.** Both are pushed before descending into a subtree and
    /// popped after via `defer` — through `LayoutPass.withScrollContext` here,
    /// `PrepaintPass`/`PaintPass.clipped(to:offsetBy:)` there — so nesting and
    /// an unbalanced push behave the same way in both. They do **not** share a
    /// phase, a payload or an escape rule: this one exists only during
    /// `requestLayout`, carries a scroll offset rather than a rectangle, and
    /// `Deferred`'s portal reaches it by `pushAbsentScrollContext` below rather
    /// than by `pushRootClip`. An earlier version of this comment said the two
    /// were shaped "exactly alike and for the same reason", which read as
    /// "`Deferred` resets this too" at a time when nothing reset it at all.
    ///
    /// **The element is `ScrollContext?`, not `ScrollContext`, because
    /// `Deferred` must be able to push the ABSENCE of one.** A subtree that has
    /// escaped a scroller's clip and translation has escaped its windowing too,
    /// so it needs the answer a subtree outside every `ScrollView` gets — and
    /// popping the enclosing entry instead would expose the *next* scroller
    /// out, which is a different wrong answer.
    private var scrollContextStack: [ScrollContext?] = []

    /// The scroll context currently in effect, or `nil` outside every
    /// `ScrollView`'s subtree — the same "nothing special" answer `activeClip`
    /// gives an empty `clipStack`. A `nil` pushed by
    /// `pushAbsentScrollContext` reads back identically, by design.
    var activeScrollContext: ScrollContext? {
        scrollContextStack.last ?? nil
    }

    /// Pushes a scroll context. Balanced by `popScrollContext`, reached only
    /// through `LayoutPass.withScrollContext`'s `defer`.
    func pushScrollContext(_ context: ScrollContext) {
        scrollContextStack.append(context)
    }

    /// Pushes the ABSENCE of a scroll context — `Deferred`'s layout-phase
    /// escape, the counterpart to `pushRootClip` on the clip stack.
    ///
    /// A `Deferred` subtree paints against the whole surface at zero offset
    /// (ruling AP-I: escaping the clip without the offset is half a portal),
    /// so a `List` inside one is not being scrolled by the `ScrollView` it was
    /// declared in and must not window against that scroller's offset. Popped
    /// exactly like an ordinary level, by `popScrollContext`.
    func pushAbsentScrollContext() {
        scrollContextStack.append(nil)
    }

    /// Pops one level pushed by `pushScrollContext` or
    /// `pushAbsentScrollContext`.
    func popScrollContext() {
        scrollContextStack.removeLast()
    }

    /// The innermost scroller whose content is being prepainted — ruling
    /// `DD-F` item 2's prepaint frame. `ScrollView` and `ProposalScrollView`
    /// push one around their content's prepaint (`PrepaintPass.inScroller`);
    /// `List` reads it to measure its own origin within the scroller's content
    /// and to see whether the window it built is stale.
    ///
    /// **`ScrollerFrame?`, for `scrollContextStack`'s reason**: `Deferred`
    /// pushes the ABSENCE of one (`PrepaintPass.deferred`), since a portal has
    /// escaped its scroller — popping the entry instead would expose the next
    /// scroller out, a different wrong answer. Prepaint-only; empty between
    /// phases.
    private var scrollerFrameStack: [ScrollerFrame?] = []

    /// The scroller frame in effect, or `nil` outside every scroller (or
    /// inside a `Deferred`).
    var activeScrollerFrame: ScrollerFrame? { scrollerFrameStack.last ?? nil }

    /// Balanced by `popScrollerFrame`, reached only through a `defer`.
    func pushScrollerFrame(_ frame: ScrollerFrame?) { scrollerFrameStack.append(frame) }

    func popScrollerFrame() { scrollerFrameStack.removeLast() }

    /// The axis-aligned intersection of two bounds. Either dimension can go to
    /// zero (or below, clamped to zero) when the two do not overlap; it never
    /// goes negative.
    static func intersect(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Bounds<Pixels> {
        let x0 = max(a.origin.x.value, b.origin.x.value)
        let y0 = max(a.origin.y.value, b.origin.y.value)
        let x1 = min(a.origin.x.value + a.size.width.value,
                     b.origin.x.value + b.size.width.value)
        let y1 = min(a.origin.y.value + a.size.height.value,
                     b.origin.y.value + b.size.height.value)
        return Bounds(origin: Point(x: Pixels(x0), y: Pixels(y0)),
                      size: Size(width: Pixels(max(0, x1 - x0)),
                                 height: Pixels(max(0, y1 - y0))))
    }

    /// The axis-aligned intersection of two clips, **carrying radii** — the
    /// half of ruling CL-A's follow-on this milestone closes.
    ///
    /// **Two rounded rects do not intersect into a rounded rect in general**:
    /// the true shape can need a distinct curve at each corner where the two
    /// rounded regions overlap. This function does not attempt that shape. It
    /// uses two cases where a rounded intersection collapses exactly, and
    /// falls back to a square-cornered box otherwise:
    ///
    /// 1. **`outer` has NO rounding at all**, and `inner`'s bounding box sits
    ///    inside `outer`'s (touching an edge is fine — a straight edge has no
    ///    curve to interact with). `outer` then contributes nothing to the
    ///    shape at all, so the intersection is exactly `inner`, radii and all.
    ///    This is the common case: a single top-level `ScrollView` pushes its
    ///    first clip against the frame's whole-surface (zero-radius) default,
    ///    and its own bounds are routinely FLUSH with that default — a
    ///    full-bleed list has no padding to keep it "strictly" inside.
    /// 2. **`inner`'s bounding box sits STRICTLY inside `outer`'s** — not
    ///    touching or crossing any of its four edges — regardless of
    ///    `outer`'s own rounding. The intersection of the two REGIONS still
    ///    reduces to `inner` alone here: `outer`'s curve only removes area
    ///    outside its own bounding box, which `inner` never reaches. This is
    ///    what a NESTED `ScrollView` gets — one rounded clip strictly inside
    ///    another — once ordinary padding is in play.
    ///
    /// **What this gets wrong, on purpose, and why nothing in this corpus
    /// notices.** Case 2's containment check is against `outer`'s bounding
    /// BOX, not its rounded shape: an `inner` clip that sits inside `outer`'s
    /// box but reaches into the disk `outer`'s OWN corner rounds away — a
    /// small `inner` clip tucked into `outer`'s corner — is still accepted as
    /// "strictly inside" and keeps `inner`'s radii un-clipped by `outer`'s
    /// curve there, so a corner of `inner` can paint past where the true
    /// intersection would stop. Not reachable today: `ScrollView` is the only
    /// production caller and nests at most one clip inside another, so no
    /// fixture or test in this corpus nests two DIFFERENTLY-rounded clips
    /// close enough to a shared corner to see it. Whenever neither case
    /// applies — `outer` is itself rounded AND `inner` merely touches or
    /// crosses its bounding box, or is larger than it — this falls back to
    /// the plain intersected box (`intersect(_:_:)` above) with SQUARE
    /// corners: the tighter box, rounding dropped rather than guessed at —
    /// **unless** (since plan task 11 part 2, `TE-AJ` item 5) one rounded
    /// rect lies exactly inside the other (case 3 below), when the contained
    /// one's radii are the exact answer. Two that cross still get the square
    /// box: divergence 92, pinned by `twoCrossingRoundedClipsIntersectAsTheSquareBox`.
    static func intersect(_ outer: Bounds<Pixels>, radii outerRadii: Corners<Pixels>,
                          _ inner: Bounds<Pixels>, radii innerRadii: Corners<Pixels>)
        -> (bounds: Bounds<Pixels>, radii: Corners<Pixels>) {
        let bounds = intersect(outer, inner)

        let containedNonStrict =
            inner.origin.x.value >= outer.origin.x.value &&
            inner.origin.y.value >= outer.origin.y.value &&
            inner.origin.x.value + inner.size.width.value
                <= outer.origin.x.value + outer.size.width.value &&
            inner.origin.y.value + inner.size.height.value
                <= outer.origin.y.value + outer.size.height.value
        let outerIsSquare = outerRadii.topLeft == Pixels(0) && outerRadii.topRight == Pixels(0) &&
            outerRadii.bottomRight == Pixels(0) && outerRadii.bottomLeft == Pixels(0)
        if outerIsSquare && containedNonStrict {
            return (bounds, innerRadii)
        }

        let strictlyInside =
            inner.origin.x.value > outer.origin.x.value &&
            inner.origin.y.value > outer.origin.y.value &&
            inner.origin.x.value + inner.size.width.value
                < outer.origin.x.value + outer.size.width.value &&
            inner.origin.y.value + inner.size.height.value
                < outer.origin.y.value + outer.size.height.value
        if strictlyInside { return (bounds, innerRadii) }

        // 3. (plan task 11 part 2, `TE-AJ` item 5, run AFTER the two cases
        //    above so every answer they gave stands — `TE-AQ` item 12) An
        //    inner rounded rect CONTAINED in the outer rounded rect keeps its
        //    radii, and the mirror keeps the outer's. Exact: a rounded rect
        //    with circular corners is the convex hull of its four corner discs,
        //    so it lies inside a convex shape iff each disc does —
        //    `sdf(other, cᵢ) ≤ −rᵢ` at each corner centre. Probe C6 (a capsule
        //    clip then a circle clip equals the circle alone) is the case the
        //    square fallback drew wrong.
        if Self.roundedRect(inner, radii: innerRadii, liesInside: outer, radii: outerRadii) {
            return (bounds, innerRadii)
        }
        if Self.roundedRect(outer, radii: outerRadii, liesInside: inner, radii: innerRadii) {
            return (bounds, outerRadii)
        }
        // Two rounded clips that CROSS: the square box (divergence 92).
        return (bounds, Corners(all: Pixels(0)))
    }

    /// Whether `rect`'s rounded region lies inside `container`'s: each of
    /// `rect`'s four corner discs (radius clamped to half its shorter side, as
    /// the shader clamps) has its centre at least its radius inside
    /// `container`'s signed distance field — the rounded-rect SDF the shaders
    /// evaluate, radius chosen by quadrant. The 1e-4 pt tolerance is
    /// **defensive and unpinned** (`TE-AT` item 2): C6's tangency — the circle
    /// touching the capsule — is exact in integers, and removing the tolerance
    /// reddens nothing (mutation X2); it is kept against a non-integer
    /// tangency rounding a hair outside, a sub-pixel cost if it is too loose.
    static func roundedRect(_ rect: Bounds<Pixels>, radii: Corners<Pixels>,
                            liesInside container: Bounds<Pixels>,
                            radii containerRadii: Corners<Pixels>) -> Bool {
        func clamp(_ r: Pixels, _ b: Bounds<Pixels>) -> Float {
            min(max(r.value, 0), max(0, min(b.size.width.value, b.size.height.value) / 2))
        }
        let x0 = rect.origin.x.value, y0 = rect.origin.y.value
        let x1 = x0 + rect.size.width.value, y1 = y0 + rect.size.height.value
        let tl = clamp(radii.topLeft, rect), tr = clamp(radii.topRight, rect)
        let br = clamp(radii.bottomRight, rect), bl = clamp(radii.bottomLeft, rect)
        let discs: [(x: Float, y: Float, r: Float)] = [
            (x0 + tl, y0 + tl, tl), (x1 - tr, y0 + tr, tr),
            (x1 - br, y1 - br, br), (x0 + bl, y1 - bl, bl),
        ]
        let halfW = container.size.width.value / 2, halfH = container.size.height.value / 2
        let cx = container.origin.x.value + halfW, cy = container.origin.y.value + halfH
        for disc in discs {
            let px = disc.x - cx, py = disc.y - cy
            let corner = px >= 0 ? (py >= 0 ? containerRadii.bottomRight : containerRadii.topRight)
                                 : (py >= 0 ? containerRadii.bottomLeft : containerRadii.topLeft)
            let r = clamp(corner, container)
            let qx = abs(px) - halfW + r, qy = abs(py) - halfH + r
            let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
            let distance = outside + min(max(qx, qy), 0) - r
            if distance > -disc.r + 1e-4 { return false }
        }
        return true
    }

    /// Scroll regions registered this frame, in prepaint order — a **derived
    /// view** of `hitboxes` below, not a list of its own.
    ///
    /// **This used to be a second registry and is not one any more** (design
    /// spec §3.1). It was a hitbox list in miniature — bounds intersected with
    /// the active clip, carrying a layer, registered in prepaint, picked by
    /// `(layer, registration order)` — and it differed from the general list in
    /// exactly two ways, both of which were defects rather than features: it
    /// tracked no opacity, so nothing could swallow a wheel event, and it
    /// recorded its bounds **untranslated** while `insertHitbox` translated
    /// them, so a `ScrollView` nested inside an already-scrolled `ScrollView`
    /// registered in the wrong space and lost **part of its hit area** — the
    /// part the untranslated rect misses — to whatever is underneath (ruling
    /// IN-F, pinned by
    /// `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`).
    /// **Not all of it**, and the difference matters to anyone diagnosing this:
    /// measured on that test's own fixture with the fix reverted, a wheel at
    /// `(100, 120)` went to the OUTER scroller while one at `(100, 170)` still
    /// reached the inner one. "No events at all" was true only of Task 5's
    /// degenerate probe, whose ancestor clip happened to cut the misplaced rect
    /// to zero height; generalising from it would send someone who tests the
    /// lower half of a nested scroller away satisfied.
    ///
    /// Kept as an accessor because a scroller is the one kind of hitbox with a
    /// payload, and "the scrolling ones" is a question several tests ask. The
    /// tuple shape is preserved so every assertion written against the old
    /// registry keeps reading the same fields.
    ///
    /// **Test observability, and it has ZERO production readers** — the same
    /// status `Window.lastScrollRegions` states in its own first line, and the
    /// reason this sentence exists is that the two used to disagree about
    /// saying so. `Window.applyScroll` ranks against `lastHitboxes` directly,
    /// `Window.lastScrollRegions` derives its own view from that same array
    /// rather than calling this one, and every other consumer went with them
    /// when the two lists folded into one.
    ///
    /// **Check with `grep -rn "scrollRegions" Sources/`, which returns five
    /// lines and no call site at all**: this declaration; the line you are
    /// reading and one in `Window.swift`, both doc comments; and two references
    /// in `Hitbox.swift`'s prose. **The pattern is case-sensitive, so it does
    /// NOT match `Window.lastScrollRegions`' own declaration** — it finds one
    /// declaration, not two, and a case-INSENSITIVE sweep
    /// (`grep -rni "scrollregions" Sources/`) is what sees both. No count is
    /// quoted for that one on purpose: it also matches every prose mention,
    /// including this paragraph, so it moves whenever the comments move — the
    /// trap the `evictUnusedSince` row in CLAUDE.md has now been caught by
    /// twice. The load-bearing half is "no call site", which
    /// holds under either pattern; the counting half did not survive being run,
    /// and this paragraph is its second draft. It reads
    /// like a live API and is not one — `LayoutTree.reset(generation:)`'s exact
    /// shape, and CLAUDE.md's declared-but-inert table carries the row.
    ///
    /// **`axis` rides along because routing, not `ScrollState`, is what needs
    /// it.** A `ScrollView` already knows its own axis and maps the stored
    /// scalar offset through it (`ScrollView.delta(_:)`), so `ScrollState`
    /// stays a bare `Double`. `Window.applyScroll` is the reader: it has no
    /// other way to know whether a region wants `delta.x` or `delta.y`.
    ///
    /// **`layer` rides along for the same reason `axis` does: routing is what
    /// needs it, and nothing else can recover it.** A `Deferred` subtree paints
    /// above everything through `Frame.pushLayer`, and a scroller inside one
    /// has to *receive* wheel events above everything too — a tooltip that
    /// paints over its siblings while they take its events is worse than one
    /// that does neither (`PrepaintPass.deferred`). Registration order alone
    /// cannot express that: a hoisted subtree is emitted wherever it was
    /// declared, so it can register before a sibling it paints on top of.
    var scrollRegions:
        [(bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis, layer: Int)] {
        hitboxes.compactMap { box in
            box.scroll.map { (box.bounds, box.id, $0, box.layer) }
        }
    }

    /// Records a scroll region — an **opaque hitbox carrying a scroll axis**.
    ///
    /// `opaque: true` because a scroller consumes the point it is under: a
    /// non-opaque record is skipped by `topmostOpaqueHitbox(in:at:)` and could
    /// never receive a wheel event at all.
    ///
    /// Everything about *where* the record lands is `insertHitbox`'s, and that
    /// is the whole point of routing through it — the translating convention
    /// used to be `insertHitbox`'s alone and this function's omission of it was
    /// a live routing defect. See `insertHitbox`.
    func registerScrollRegion(_ bounds: Bounds<Pixels>, id: GlobalElementID, axis: ScrollAxis) {
        _ = insertHitbox(bounds, id: id, opaque: true, scroll: axis)
    }

    /// Hitboxes registered this frame, in prepaint order — **the one list**.
    ///
    /// Rebuilt from scratch every frame, exactly like the `LayoutTree` — which
    /// is why a `HitboxID` is a per-frame handle and every record carries a
    /// `GlobalElementID` for anything that must outlive one.
    private(set) var hitboxes: [Hitbox] = []

    /// Pointer-disable scopes are inherited by descendants during prepaint.
    /// Keyboard registration stays outside this gate: disabling hit testing is
    /// a pointer decision, not an instruction to discard a focused control's
    /// key handler.
    private var hitTestingDisabledDepth = 0

    func withHitTestingDisabled<R>(_ body: () -> R) -> R {
        hitTestingDisabledDepth += 1
        defer { hitTestingDisabledDepth -= 1 }
        return body()
    }

    /// Runs `body` — a prepaint — under the pointer-disable scope when `node` is in
    /// `hiddenNodes`, and plainly otherwise (plan task 7, stage 6b, ruling `LR-DH`
    /// item 2): a lowered `hidden()` registers no pointer hitbox, and neither does
    /// anything inside it (stage-2 probe V3: a hidden view passes the tap to the view
    /// under it). Focus, keys and scroll regions are
    /// outside this gate, as they are outside `allowsHitTesting(false)`'s (`OM-AK`).
    ///
    /// **It is also the hidden scope for the keyboard's focus half** (plan task
    /// 12 part 1, ruling `IX-K` item 3; probe arm F9): inside it
    /// `registerHandlers` registers no focusability, `onKey`, actions or key
    /// context — the same gate as `isEnabled`, keyboard half only — so a focused
    /// element that becomes hidden loses focus at the next boundary. **A
    /// keyboard shortcut is NOT gated by it** (arm X1: a hidden button's
    /// shortcut fires), and scroll regions stay outside every gate. One helper,
    /// so each of its callers — `Element.prepaintGroup`,
    /// `ModifiedContent.prepaintLayer` (each inner layer, `MC-B`) and
    /// `Frame.render`'s root — carries both scopes; `AnyElement`'s entry reaches
    /// the first through its box's group default.
    func disablingHitTestingIfHidden<R>(_ node: LayoutNodeID, _ body: () -> R) -> R {
        guard hiddenNodes.contains(node) else { return body() }
        keyboardHiddenDepth += 1
        defer { keyboardHiddenDepth -= 1 }
        return withHitTestingDisabled(body)
    }

    /// Inside a hidden node's prepaint (`disablingHitTestingIfHidden`) — the
    /// keyboard focus half's hidden condition (`IX-K` item 3).
    private var keyboardHiddenDepth = 0

    /// Records a hitbox at the rect it actually **paints** at: translated by
    /// the active offset, then intersected with the active clip, carrying the
    /// active layer.
    ///
    /// **The translation is what makes a hit land on the pixels the user is
    /// pointing at.** `PaintPass.fill` adds `activeOffset` before emitting, so
    /// a row inside a `ScrollView` scrolled by 30 draws thirty points above
    /// where `bounds(of:)` reports it; a hitbox recorded at the untranslated
    /// rect would sit thirty points below what is on screen, and the error
    /// would grow with the scroll.
    ///
    /// **`registerScrollRegion` used to omit it, and that was a live routing
    /// defect** — ruling IN-F, fixed by folding it through here. `ScrollView.prepaint`
    /// registers *outside* its OWN `clipped(to:offsetBy:)` block, which zeroes
    /// only its own contribution; an **ancestor** scroller's is still in
    /// effect, because the inner element's whole `prepaint` runs inside the
    /// outer's block. Measured through a real `Frame.render` with the outer
    /// scrolled by 50: the inner scroller registered `(0, 150) 200x50` — 50pt
    /// low and cut in half by the ancestor clip — while painting at
    /// `(0, 100) 200x100`, so a wheel over its visible top half went to the
    /// OUTER scroller instead.
    ///
    /// The **clipped** bounds, not the raw ones: a nested scroller positioned
    /// outside its ancestor's viewport window must not receive events for the
    /// area it cannot actually show. Storing the raw, un-intersected bounds
    /// instead would let an event land on a region the user cannot see.
    ///
    /// `id` is a parameter rather than something derived here because the
    /// returned `HitboxID` is a per-frame index and cannot key anything that
    /// survives a frame — hover, active state and a scroller's offset all need
    /// the element's own id. Every prepaint site has one in hand already.
    ///
    /// `scroll` and `handlers` both default to empty — an ordinary hitbox is
    /// neither a scroller nor a click target — so the public
    /// `PrepaintPass.insertHitbox` needs no payload parameter, and
    /// `registerScrollRegion` and `registerHandlers` stay the two spellings
    /// that supply one each.
    ///
    /// `origin` is the owning element's own origin when the region differs from
    /// its box (a content shape's inset); it is translated like `bounds` and
    /// never clipped, so a gesture's values are local to the element (plan task
    /// 12 part 1, `IX-C` item 5). It defaults to `bounds`' origin.
    func insertHitbox(_ bounds: Bounds<Pixels>, id: GlobalElementID,
                      opaque: Bool, scroll: ScrollAxis? = nil,
                      handlers: Handlers = Handlers(),
                      origin: Point<Pixels>? = nil,
                      shape: ShapeGeometry? = nil) -> HitboxID {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        let elementOrigin = origin ?? bounds.origin
        hitboxes.append(Hitbox(bounds: Self.intersect(activeClip, translated),
                               id: id, layer: activeLayer, opaque: opaque, scroll: scroll,
                               handlers: handlers,
                               origin: Point(x: Pixels(elementOrigin.x.value + activeOffset.x.value),
                                             y: Pixels(elementOrigin.y.value + activeOffset.y.value)),
                               shape: shape?.offsetBy(dx: activeOffset.x.value, dy: activeOffset.y.value),
                               // Inside render effects: the local rect above, the inverse
                               // composed map and the outer clip (`GX-I`).
                               transform: prepaintEffects.last.map {
                                   HitboxTransform(inverse: $0.inverse, outerClip: $0.outerClip)
                               }))
        // A proposal wrapper's own registration, noted for an effect at the same
        // rect to transform (`GX-P` item 1).
        if !shareCollecting.isEmpty {
            shareCollecting[shareCollecting.count - 1].hitboxes.append(
                (index: hitboxes.count - 1, raw: translated, clip: activeClip))
        }
        return HitboxID(index: hitboxes.count - 1)
    }

    /// Records a click target — an **opaque hitbox carrying a handler set** —
    /// and does nothing at all when `handlers` is empty.
    ///
    /// **The empty case is the interesting one**, and it is why this exists
    /// rather than every element calling `insertHitbox` behind its own `guard`.
    /// A hitbox registered for an element that asked for nothing would be
    /// opaque, would shadow whatever it covers, and — since Task 7 folded
    /// scroll regions into this list — would swallow the wheel of any
    /// `ScrollView` it sits inside. Every `Box` in this framework is a
    /// potential caller, so that gate has to be in one place and not in six.
    ///
    /// `opaque: true` for the same reason a scroller is: a click target
    /// consumes the point. Non-opaque would mean a modal scrim could not
    /// swallow clicks aimed at what it covers, which is the sibling property of
    /// the wheel swallow this milestone's exit criterion 4 is about.
    ///
    /// **The disabled gate is here too, and only here** (rulings EV-E, EV-F,
    /// EV-T). `environmentTop.isEnabled` is read once, in place, and when it is
    /// false:
    ///
    /// - **no hitbox is registered**, whatever `handlers` holds. A click over
    ///   the disabled target therefore reaches whatever enabled hitbox lies
    ///   under it — an enabled ancestor with an `onClick` (aligned with SwiftUI,
    ///   probe `swiftui-disabled-ancestor-and-order.swift` N1/N2) or an enabled
    ///   sibling drawn under it (a divergence, SwiftUI's shape blocks, P2f; the
    ///   same difference every non-clickable MetalUI overlay already has). With
    ///   no hitbox the target is neither hovered nor `isActive`, and a press or
    ///   a release made while it was disabled fails `Window.dispatchClick`'s
    ///   `hit.id == pressed` (probe R), with no `Window` edit.
    /// - **no focus registration**: not `isFocusable`, `actions`, `onKey` or
    ///   `keyContext`. A focus request on it is cleared at the prepaint/paint
    ///   boundary, a focused element that becomes disabled loses focus, and a
    ///   disabled ancestor's raw `onKey` does not see a key (the last two are
    ///   divergences from probe K2/K6, ruling EV-F).
    /// - **no `$focus` retention write** — while `focusedElementProducedThisFrame`
    ///   stays ungated (see that write's own paragraph below).
    /// - **the declared AX node gains `.disabled`**.
    ///
    /// Every caller reaches it: `Box` (and so `Column`/`Row`), `Stack`, `Text`
    /// and `ModifiedElement` (each layer) through `PrepaintPass.registerAndScope`
    /// (`DecorationScope.swift`, since plan task 5's lane 2 — one call site for
    /// the four), `OnTapModifier` through `PrepaintPass`'s internal overload
    /// directly, `List` rows through their elements and `Component` through
    /// its members.
    /// A raw `PrepaintPass.insertHitbox` is NOT gated: an element using the
    /// primitive reads `pass.environment.isEnabled` itself.
    func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>,
                          id: GlobalElementID) {
        registerHandlers(handlers, at: bounds, id: id, accessibleText: nil,
                         synthesizesAccessibility: true)
    }

    /// The implementation, and **the one place the disabled gate lives**
    /// (ruling EV-W item 4): the 3-argument overload above is a bare forward,
    /// because `Text` and `OnTapModifier` reach this method directly through
    /// `PrepaintPass`'s internal overload, so a gate in the 3-argument method
    /// would leave them ungated (measured: D2's "text" and "proposal" arms and
    /// D3 redden).
    func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>,
                          id: GlobalElementID, accessibleText: String?,
                          synthesizesAccessibility: Bool) {
        // Read in place, not through `environmentSnapshot()`, so the gate costs
        // no counted snapshot (ruling EV-O).
        let enabled = environmentTop.isEnabled
        // A hidden element is out of the keyboard's focus half (plan task 12
        // part 1, ruling `IX-K` item 3): the second condition of this one gate.
        let keyboardVisible = keyboardHiddenDepth == 0
        // A `.focused` binding is recorded whatever the gates say (`IX-J`): it
        // is not a keyboard ask, and a `@FocusState` write naming it is refused
        // by the focusability it would need (`Window.applyPendingFocusStateWrites`).
        if let binding = handlers.focusBinding {
            focusRegistry.registerFocusBinding(binding, id: id)
        }
        // The keyboard side first: focus registration is not gated on the
        // pointer gate below, and an element can ask for one without the
        // other. `register` gates itself on `isKeyTarget`; a disabled element
        // does not reach it at all (ruling EV-F), and a hidden one registers
        // its keyboard shortcut alone (`IX-K` item 3, arm X1 — the shortcut
        // table is gated by `isEnabled` only).
        if enabled {
            if keyboardVisible {
                focusRegistry.register(handlers, id: id)
            } else {
                focusRegistry.registerShortcut(handlers, id: id)
            }
        }
        // **Independent of `isKeyTarget`/`isFocusable` — this is "was the
        // currently-focused id produced this frame at all", not "did it ask
        // to stay focused".** `Box.prepaint`, `Stack.prepaint` and
        // `Text.prepaint` call this unconditionally for every produced element
        // of their type (see this method's own doc), so it is the one
        // per-frame signal that fires for `focusedElement` whether or not
        // `handlers` asks for anything. `resolveFocus()` needs exactly that
        // to tell "still produced, gave up `.focusable()`" (clear at once)
        // apart from "not produced this frame" (fall back to the state
        // table's retention window) — `focusRegistry.isFocusable(_:)` alone
        // cannot make that distinction, since a produced-but-uninterested
        // element and an unproduced one both read `false` there.
        if let focused = focusedElement, id == focused {
            focusedElementProducedThisFrame = true
            // Rides `StateTable`'s own tombstone mechanism rather than a
            // focus-specific grace period (design spec §5) — a distinct
            // slot, `$focus`, so this can never collide with a `@State`
            // slot (always a CHILD of the element's own id, named
            // `"$state\(n)"`) or with a `ScrollView`'s own
            // `withState(id, ...)` entry (keyed directly on its own id,
            // typed `ScrollState` — writing `Bool` there would silently
            // clobber it, per `StateTable.write`'s own doc on mismatched
            // types). `resolveFocus()` reads this back with `peek`, which
            // returns non-nil for a live OR a tombstoned entry and nil only
            // once it is actually reaped.
            //
            // **KNOWN, and ruled "record, do not fix" at the whole-branch
            // review: this write is not gated on `handlers.isKeyTarget`, so a
            // `$focus` slot can be written for an element that was never
            // legitimately focusable.** `Window.focus(x)` on a produced but
            // non-focusable `x` reaches here and writes the slot *before*
            // `resolveFocus()` clears the focus later in the same frame. Below
            // `StateTable.sweepThreshold` that slot is never reaped, so a later
            // `Window.focus(x)` made while `x` is NOT produced then **sticks**:
            // `resolveFocus`'s fallback tests only `peek(...) != nil` and never
            // asks whether the slot was written by a frame that also found `x`
            // focusable. The consequence is a wrongly-sticky focus on an
            // element that has never been a key target — not a clobber, not a
            // crash, and not reachable without an explicit `Window.focus` call
            // on an ENABLED, produced, non-focusable element.
            //
            // **Since plan task 12 part 1 (`IX-I`) only an UNEVALUATED subtree
            // reaches it.** `$focus` is no longer exempt from the evaluated
            // resets (`ID-C`'s removed conditional, `DD-C`'s dropped loop tail,
            // `ID-R`'s departed name), so an `x` removed by an `if` loses the
            // stray slot with the rest of its entries in that frame's `sweep()`
            // and the second request is cleared. What still keeps the slot is
            // a subtree nothing evaluates — a `List` row out of its window
            // (`TB-AH`) — so the hazard survives on exactly that route (`IX-T`).
            //
            // **`.disabled` does not reach it** (ruling EV-F, critic finding 7):
            // every `.focusable()` element under `.disabled` is non-focusable,
            // so without the `if enabled` below a focus request on one would
            // write the slot, and windowing the row out and focusing its id
            // again would stick. The write is gated on `enabled` alone — not on
            // `isKeyTarget`, which is the general fix below and a focus-contract
            // change — and `focusedElementProducedThisFrame` above stays
            // ungated, so the pre-existing hazard is exactly as reachable as it
            // was. Pinned both ways by
            // `aFocusRequestWhileDisabledLeavesNoRetentionSlot`, over a `List`
            // row windowed out of its scroller (re-derived at `IX-T` from the
            // `if` route `IX-I` closed): its disabled arm leaves no slot, its
            // instrument arm (enabled, not focusable) sticks.
            //
            // **Deliberately not fixed, and the reason is the SHAPE of the fix
            // rather than its size.** The obvious patch — gate this write on
            // `isKeyTarget` — cannot be applied on its own, because the
            // *produced* signal set immediately above must stay ungated: it is
            // the only per-frame evidence distinguishing "gave up
            // `.focusable()`" (clear at once) from "not produced" (fall back to
            // retention), and `anElementThatStopsBeingFocusableLosesFocus`
            // depends on exactly that. A correct fix must therefore SEPARATE
            // two things that today share one conditional — keep
            // `focusedElementProducedThisFrame` ungated, gate the slot write on
            // `isKeyTarget`, and clear the slot in `resolveFocus`'s
            // produced-but-not-focusable branch so a stale one cannot outlive
            // the frame that invalidated it. That is a change to the focus
            // contract rather than a patch, and it does not go in unreviewed in
            // the last commit before a merge — the same judgement
            // `Window.applyScroll` was given during the input milestone.
            if enabled && keyboardVisible {
                stateTable.withState(Self.focusRetentionSlot(for: focused),
                                     initial: true) { _ in }
            }
        }
        // Disabled: NO hitbox — not a blocker with empty handlers, and no
        // derived id (ruling EV-E, third pass). A blocker would eat an enabled
        // ancestor's click (against probe N1/N2), and one under this id would
        // let a press made while disabled click on a release after
        // re-enabling (against probe R, ruling EV-T).
        //
        // **The content shape is applied HERE and nowhere else** (ruling OM-J,
        // plan task 5's lane 3): to the bounds handed to `insertHitbox`, below
        // the focus registration, the `$focus` write and the
        // `focusedElementProducedThisFrame` signal above, and above the declared
        // `AXNode` and the accessibility record below — all five of which keep
        // the element's own `bounds`. One site rather than four, for this
        // method's own reason: a conformer insetting its own bounds before
        // calling here would have to get it right in `Box`, `Stack`, `Text` and
        // `ModifiedElement`, and a conformer that forgot would be silently
        // wrong.
        // The press the gate below withholds from the pointer, kept for an
        // accessibility client only (`IX-Z` item 1): enabled, and only while
        // collecting, so a window with no client pays one `Bool` read. A
        // suppressed subtree records no node, so it advertises no press.
        if collectsAccessibility, enabled, hitTestingDisabledDepth > 0, let onClick = handlers.onClick,
           !isAccessibilitySuppressed(for: id) {
            accessibilityPressOnly[id] = onClick
        }
        // The pointer target's and the draggable region's handlers carry no
        // hover attachment: the hover region below is the one hitbox that
        // does, so the hovered set counts each element once (`SV-N` item 2).
        var pointerHandlers = handlers
        pointerHandlers.hover = nil
        // Nor the wheel handler and pointer style (`CI-I` item 3, `CI-H` item
        // 3): the pointer region below carries them, once per element.
        pointerHandlers.pointer = nil
        if enabled, hitTestingDisabledDepth == 0, handlers.isPointerTarget {
            // A declared `.contentShape(_:)` (plan task 12 part 1, `IX-L`) is
            // the shape's geometry in the same (inset) region, here and nowhere
            // else, for the inset's reason above.
            let region = Self.hitRegion(bounds, inset: handlers.contentShapeInset)
            _ = insertHitbox(region, id: id, opaque: true, handlers: pointerHandlers, origin: bounds.origin,
                             shape: handlers.contentShape?.geometry(in: region))
        }
        // Drag and drop (rulings `DN-E`, `DN-F`, `DN-G`): two NON-opaque
        // regions, each inside the one disabled gate. A draggable on a pointer
        // target already rides the opaque hitbox above; one whose element asks
        // for nothing else gets its own region, carrying its handlers so the
        // arena finds it by identity — gated by `allowsHitTesting(false)` like
        // any pointer ask (`DN-E` item 3). A destination's region carries only
        // the drop handler, at the element's own bounds (no content shape), and
        // sits OUTSIDE the `allowsHitTesting` gate, as a scroll region does
        // (`DN-F` item 3, `P15e`) — but not outside `hidden()`
        // (`keyboardHiddenDepth`, `R5d`). Neither is registered by a frame with
        // no draggable or destination, so every other tree's hitbox list is
        // unchanged (pinned by `aFrameWithoutADragOrDestinationAddsNoHitbox`).
        if enabled, hitTestingDisabledDepth == 0, !handlers.isPointerTarget, handlers.hasDraggable {
            let region = Self.hitRegion(bounds, inset: handlers.contentShapeInset)
            _ = insertHitbox(region, id: id, opaque: false, handlers: pointerHandlers, origin: bounds.origin,
                             shape: handlers.contentShape?.geometry(in: region))
        }
        if enabled, keyboardHiddenDepth == 0, let destination = handlers.dropDestination {
            var only = Handlers()
            only.dropDestination = destination
            _ = insertHitbox(bounds, id: id, opaque: false, handlers: only, origin: bounds.origin)
        }
        // A context menu and help (menus, rulings `MN-Q`, `MN-U`, `MN-V`): a
        // NON-opaque contextual region at the element's own bounds (clipped as
        // every hitbox is), carrying only the attachment and whether the element
        // is enabled. **Inside the `allowsHitTesting` gate** (C13: a right press
        // under `.allowsHitTesting(false)` opens no menu) — unlike a drop
        // destination's — and **before the disabled gate** (C9: a disabled
        // element's menu opens, every item disabled). `hidden()` withholds it
        // through the same gate. Registered after the element's own opaque
        // hitbox, so the region ranks above it, and before its content's.
        if let contextual = handlers.contextual {
            if hitTestingDisabledDepth == 0 {
                var only = Handlers()
                only.contextual = contextual
                let index = insertHitbox(bounds, id: id, opaque: false, handlers: only, origin: bounds.origin).index
                hitboxes[index].contextualEnabled = enabled
            }
            // The keyboard and accessibility openers' record (`MN-G`): not a
            // hitbox query, so outside the `allowsHitTesting` gate (`MN-U`), but
            // not inside a hidden subtree.
            if contextual.menu != nil, keyboardHiddenDepth == 0 {
                contextMenuRecords[id] = ContextMenuRecord(
                    attachment: contextual, isEnabled: enabled,
                    bounds: Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                                                 y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
                                   size: bounds.size))
            }
        }
        // Hover (ruling `SV-N` item 2): a NON-opaque region carrying only the
        // attachment, at the element's hit region (its content shape, as a
        // draggable region's), registered after the element's own opaque
        // hitbox so it ranks above it — inside the disabled gate, the
        // `allowsHitTesting` gate and `hidden()`. A frame with no hover
        // attachment registers nothing here, so every other tree's hitbox list
        // is unchanged (spec test 2.55). The `keyboardHiddenDepth` clause is
        // belt-and-braces: `disablingHitTestingIfHidden` also opens a
        // hit-testing-disabled scope, so the `hitTestingDisabledDepth` clause
        // already withdraws a hidden region (mutation `V1`, equivalent).
        if let hover = handlers.hover, enabled, hitTestingDisabledDepth == 0, keyboardHiddenDepth == 0 {
            var only = Handlers()
            only.hover = hover
            let region = Self.hitRegion(bounds, inset: handlers.contentShapeInset)
            _ = insertHitbox(region, id: id, opaque: false, handlers: only, origin: bounds.origin,
                             shape: handlers.contentShape?.geometry(in: region))
            hoverRegionCount += 1
        }
        // The wheel handler and the pointer style (rulings `CI-I` item 3,
        // `CI-H` item 3): ONE non-opaque region carrying only the attachment,
        // at the element's hit region, inside the disabled, `allowsHitTesting`
        // and `hidden()` gates exactly as the hover region — unlike a scroll
        // region, which stays outside them. A frame with neither registers
        // nothing here (test 3.14).
        if let pointer = handlers.pointer, enabled, hitTestingDisabledDepth == 0, keyboardHiddenDepth == 0 {
            var only = Handlers()
            only.pointer = pointer
            let region = Self.hitRegion(bounds, inset: handlers.contentShapeInset)
            _ = insertHitbox(region, id: id, opaque: false, handlers: only, origin: bounds.origin,
                             shape: handlers.contentShape?.geometry(in: region))
            if pointer.style != nil { pointerStyleRegionCount += 1 }
        }
        // **Accessibility rides here too, and it was not always here.** The
        // gate used to live in `Box.prepaint` alone, so `Stack.prepaint` and
        // `Text.prepaint` — which call this and nothing else — dropped a
        // declared `handlers.axNode` silently.
        // `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
        // (`AXEmitSiteTests.swift`) is the per-conformer pin. No-op unless
        // something set `handlers.axNode` to something other than `AXNode()`
        // — `AXNode.isEmpty`'s own doc names this as `Handlers`' "empty means
        // not a hit target" rule, one type over.
        //
        // **Kept AFTER the `$focus` write above** (and before only the
        // accessibility record below, which writes no slot), so the `$ax` write
        // follows the `$focus` write — `Box.prepaint`'s order before this moved, and
        // the order `theSevenRetentionSlotsAreMutuallyDistinct`
        // (`AXNodeTests.swift`) calls the two in by hand. **That test does not
        // pin this ordering, and it is not what keeps it red:** it calls
        // `registerHandlers` with an empty `axNode` and then `emitAXNode`
        // itself. Measured when this moved: its `"$ax"` → `"$focus"` collision
        // mutation reddens it (its `$focus` assertion) with this call last,
        // and ALSO with this call moved above `focusRegistry.register`.
        //
        // **`children` is always `[]` from here**: a generic
        // `Content: ElementGroup` hands `requestGroupLayout` a flat
        // `[LayoutNodeID]`, not a `GlobalElementID` per child
        // (`ElementGroup.swift`), so no container can name its own children's
        // ids without a change to that protocol's associated types (ruling
        // `TB-M`). **The accessibility bridge assembles its tree elsewhere and
        // leaves this `[]`** (ruling AB-C): `AccessibilityTreeBuilder` walks
        // `GlobalElementID.parent` over this frame's `axEmissions`, whose
        // record order — which `axNodes`' keys cannot carry — is declaration
        // order.
        //
        // **A row hint is not a declaration** (ruling AB-L): `logicalIndex` is
        // stripped before the test, so a `List` row that carries only its index
        // emits nothing here and writes no `$ax` slot (AB-U). **A selection
        // hint is stripped the same way** (ruling `DD-U` item 4): a selected
        // `List(selection:)` row records `isSelected` for a client and writes
        // neither `axNodes` nor a `$ax` slot, so retention does not move.
        //
        // **A disabled element's declared node gains `.disabled`** (ruling
        // EV-E). Presence and role still come from the ungated `handlers`: a
        // disabled button is still a button. The client's record below carries
        // `isEnabled: enabled` (ruling EV-W item 4).
        var declaration = handlers.axNode
        declaration.logicalIndex = nil
        declaration.selectionHint = false
        declaration.menuButtonHint = false   // MN-H item 2, stripped as the selection hint is
        declaration.popUpButtonHint = false  // SV-S, the same
        declaration.popoverHint = false      // MN-O, the same
        if !declaration.isEmpty {
            var node = handlers.axNode
            if !enabled { node.traits.insert(.disabled) }
            emitAXNode(node, at: bounds, id: id, children: [])
        }
        // **A client's record, separate from the emission above and never a
        // substitute for it** (ruling AB-U). With no client this is one `Bool`
        // read. While collecting, anything with something to say appends a
        // record — a declared node, and (when this conformer synthesizes) a
        // click target, a focusable or adjustable element, or a text leaf —
        // and nothing here writes `axNodes` or `StateTable`, so a synthesized
        // node cannot change retention and `noConformerEmitsAnAXNodeItDidNotDeclare`
        // stays true whether or not a client is active.
        if collectsAccessibility, !isAccessibilitySuppressed(for: id) {
            let adjustable = handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] != nil
            let declaresAction = handlers.actions[ObjectIdentifier(AccessibilityDefaultAction.self)] != nil
            // A declared action is a declaration, not a synthesis (plan task 12
            // part 2, `IX-AF` item 3): recorded OUTSIDE the synthesize gate, so
            // a non-synthesizing conformer (a proposal wrapper, G6's action over
            // a gesture) still publishes it.
            let declaresNamedAction = handlers.actions[ObjectIdentifier(AccessibilityNamedAction.self)] != nil
            // A context menu is a declaration too (`MN-G` item 2): its node
            // carries the show-menu action, so a client can open it.
            let hasSomethingToSay = !declaration.isEmpty || handlers.axNode.logicalIndex != nil
                || handlers.axNode.selectionHint || handlers.axNode.popoverHint
                || declaresAction || declaresNamedAction
                || handlers.contextual?.menu != nil
                || (synthesizesAccessibility
                    && (handlers.onClick != nil || handlers.isFocusable || adjustable
                        || accessibleText != nil))
            if hasSomethingToSay {
                axEmissions.append(AXEmission(id: id, declared: handlers.axNode,
                                              text: accessibleText,
                                              isClickable: handlers.onClick != nil,
                                              isEnabled: enabled,
                                              synthesizes: synthesizesAccessibility,
                                              portal: portalStack.last ?? 0,
                                              geometry: accessibilityGeometry(for: bounds),
                                              declaresAction: declaresAction))
            }
        }
    }

    /// A record for an element that registers nothing else — a `ProposalText`'s
    /// string, a labelled `Image` (plan task 12 part 2, `IX-AB` items 1 and 3).
    /// **Gated on `collectsAccessibility` alone**: no hitbox, no focus entry, no
    /// `StateTable` slot (so no `$ax` write, AB-U), reading `isEnabled` and the
    /// suppression exactly as `registerHandlers`' record does.
    func recordAccessibility(text: String?, declared: AXNode, at bounds: Bounds<Pixels>,
                             id: GlobalElementID) {
        guard collectsAccessibility, !isAccessibilitySuppressed(for: id) else { return }
        axEmissions.append(AXEmission(id: id, declared: declared, text: text, isClickable: false,
                                      isEnabled: environmentTop.isEnabled, synthesizes: true,
                                      portal: portalStack.last ?? 0,
                                      geometry: accessibilityGeometry(for: bounds)))
    }

    /// `bounds` inset by a declared content shape, or `bounds` itself — the
    /// whole of `Handlers.contentShapeInset`'s effect (ruling OM-J).
    ///
    /// **A negative inset GROWS the region and is not clamped**, which SwiftUI
    /// does too (probe `swiftui-content-shape-hit-region`, arm H5: a point 40pt
    /// outside an 80x80 leaf hits it at `inset(by: -60)`). What bounds the grown
    /// region is the active clip, applied by `insertHitbox` to every hitbox
    /// alike — where SwiftUI's `.clipped()` bounds nothing (H6, ruling OM-AJ).
    ///
    /// **An inset larger than the box is left inside-out here and is empty by
    /// the time it lands.** `insertHitbox` intersects with the active clip and
    /// `Self.intersect` clamps a negative extent to zero, so an over-inset
    /// region is stored with a zero extent and `Bounds.contains`, being
    /// half-open on the max edges, can never answer true for it. Clamping here
    /// as well would say the same thing twice and hide which of the two rules
    /// is load-bearing.
    static func hitRegion(_ bounds: Bounds<Pixels>, inset: Edges<Pixels>?) -> Bounds<Pixels> {
        guard let inset else { return bounds }
        return Bounds(origin: Point(x: Pixels(bounds.origin.x.value + inset.left.value),
                                    y: Pixels(bounds.origin.y.value + inset.top.value)),
                      size: Size(width: Pixels(bounds.size.width.value
                                                   - inset.left.value - inset.right.value),
                                 height: Pixels(bounds.size.height.value
                                                    - inset.top.value - inset.bottom.value)))
    }

    /// The state-table key that backs a focused id's retention window — see
    /// `registerHandlers`'s own doc for why it must be a distinct slot rather
    /// than `id` itself. `at: 0` is inert: `GlobalElementID.child(of:at:name:)`
    /// always prefers `name` when one is supplied.
    private static func focusRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
        .child(of: id, at: 0, name: ElementID("$focus"))
    }

    // MARK: - Accessibility (design spec §9)

    /// Every accessibility node emitted this frame, keyed by the element that
    /// emitted it.
    ///
    /// **A dictionary rather than a list**, unlike `hitboxes` — nothing here
    /// ranks records against each other (there is no "topmost" question for an
    /// AX node), so the only operation any caller performs is "look up `id`",
    /// which `hitboxes` would need a linear scan for. `Hitbox`'s per-frame
    /// `HitboxID` handle exists to keep a dense array cheap to index; an
    /// `AXNode` has no equivalent because nothing needs one.
    ///
    /// **Rebuilt from scratch every frame**, on `hitboxes` and `focusRegistry`'s
    /// own footing: an element not produced this frame emits nothing here, so
    /// this dictionary alone answers only "was `id` produced THIS frame", not
    /// "does `id` still exist". **That is deliberately not this property's
    /// job any more** — `axNode(for:)` below is the durable, tombstone-aware
    /// query (design spec §9); this one stays exactly what Task 5 shipped, a
    /// per-frame view, because Task 7 and any future tree walk still want
    /// "what was produced this frame" as a distinct question from "is this id
    /// still valid".
    private(set) var axNodes: [GlobalElementID: AXNode] = [:]

    /// Whether an accessibility client is active for this frame's window
    /// (ruling AB-B). `Window` passes `WindowAccessibility.isActive`; a `Frame`
    /// built anywhere else defaults to `false`.
    ///
    /// **A `let`, for `theme`'s reason**: half a frame collecting would publish
    /// half a tree. **What it turns on is records, not emissions**: `axNodes`,
    /// the `$ax` slot and everything else this frame does are identical either
    /// way (AB-U), which is what keeps a screen reader from changing app state.
    let collectsAccessibility: Bool

    /// This frame's accessibility records, in prepaint order — **empty unless
    /// `collectsAccessibility`**. Read by `AccessibilityTreeBuilder` once per
    /// frame. See `AXEmission`.
    private(set) var axEmissions: [AXEmission] = []

    /// The `onClick` of each **enabled** element whose hitbox the
    /// `allowsHitTesting(false)` gate withheld — **empty unless
    /// `collectsAccessibility`** (plan task 12 part 2, ruling `IX-Z` item 1).
    /// SwiftUI still presses a `Button` under `allowsHitTesting(false)` (arm
    /// B6): an accessibility press is not a pointer query. The builder
    /// advertises `.press` for these ids and `Window` runs the handler when no
    /// hitbox answers; a mouse click still finds nothing. Last registration
    /// wins, as click dispatch ranks a later hitbox above an earlier one.
    private(set) var accessibilityPressOnly: [GlobalElementID: @MainActor () -> Void] = [:]

    /// The context menus this frame's elements declared, by element (menus,
    /// spec §3.1): `Window`'s keyboard and accessibility openers' table
    /// (`MN-G`). Frame-scoped, never `StateTable`.
    private(set) var contextMenuRecords: [GlobalElementID: ContextMenuRecord] = [:]

    /// The presentation anchors this frame's elements recorded, by element, in
    /// window points (spec §3.4): `Window.lastPresentationAnchors` after the
    /// frame. Frame-scoped, never `StateTable`.
    private(set) var presentationAnchors: [GlobalElementID: Bounds<Pixels>] = [:]

    /// The anchors the LAST frame recorded, handed in by `Window` (spec §3.7,
    /// `MN-M` item 2): a popover is placed against its anchor's last completed
    /// bounds, since presentations are laid out before the root. Empty for a
    /// frame rendered without a window.
    var previousPresentationAnchors: [GlobalElementID: Bounds<Pixels>] = [:]

    /// The popovers this frame presented, in registration order — so the
    /// topmost last (spec §3.7): `Window.lastOpenPopovers` after the frame.
    /// Frame-scoped, never `StateTable`.
    private(set) var openPopovers: [OpenPopover] = []

    /// Registers an open popover (`AnchoredPresentation.prepaint`).
    func registerOpenPopover(_ popover: OpenPopover) {
        openPopovers.append(popover)
    }

    /// The tooltip on screen, handed in by `Window` before it renders
    /// (`MN-P` item 2); `nil` with none, so a frame without one paints
    /// nothing more.
    var tooltip: VisibleTooltip?

    /// The window's handle a pull-down presents through (spec §3.4); `nil` for
    /// a frame rendered without a window.
    var menuPresenter: MenuPresenter?

    /// Records `bounds` (this element's, in the current offset) as `id`'s
    /// presentation anchor, in window points.
    func recordPresentationAnchor(_ id: GlobalElementID, bounds: Bounds<Pixels>) {
        presentationAnchors[id] = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                                                       y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
                                         size: bounds.size)
    }

    /// Set by a collecting `List` whose window is unbounded only because its
    /// scroller has not measured a viewport yet (ruling AB-X rule 3). `Window`
    /// hands it to `WindowAccessibility.frameDidRender`, which dirties the window
    /// only when the previous drawn frame did not ask too.
    private(set) var wantsAccessibilityRetry = false

    /// Ask for one more frame so an accessibility client sees what this frame
    /// could not publish. A no-op unless collecting.
    ///
    /// **Not `requestAnotherFrame()`**: `wantsAnotherFrame` is honoured on every
    /// frame, so a scroller that never measures a viewport (zero height) would
    /// keep the display link awake forever. This one is capped by its reader.
    func requestAccessibilityRetry() {
        guard collectsAccessibility else { return }
        wantsAccessibilityRetry = true
    }

    /// The exceptions of the open suppression scopes, outermost first.
    private var accessibilitySuppressionExceptions: [GlobalElementID?] = []

    /// Runs `body` with accessibility records suppressed for everything except
    /// `exception` — for a subtree a client must not see even though it runs
    /// `prepaint` (`display: none`, ruling AB-O; a `List`'s unbounded window,
    /// which excepts the list's own node, AB-X). Closure form for `clipped(to:offsetBy:)`'s
    /// reason: an unbalanced scope is not expressible. A no-op while not
    /// collecting.
    func withAccessibilitySuppressed<R>(except exception: GlobalElementID?, _ body: () -> R) -> R {
        guard collectsAccessibility else { return body() }
        accessibilitySuppressionExceptions.append(exception)
        defer { accessibilitySuppressionExceptions.removeLast() }
        return body()
    }

    /// Runs `body` inside an accessibility suppression scope when `node` is
    /// hidden (`isHidden`), and plainly otherwise — the one hidden check (ruling
    /// AB-O), shared by `Element.prepaintGroup` (a whole element) and
    /// `ModifiedElement`'s per-layer prepaint (each inner layer, which receives
    /// no group default of its own — ruling MC-B's "any hook in those defaults
    /// is mirrored per layer"). Read only while collecting. Pinned per layer by
    /// `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`.
    ///
    /// **Reads `isHidden` since stage 6b** (`LR-DH` item 3), which reads
    /// `hiddenNodes` alone since stage 9 (`LR-FC`).
    func suppressingAccessibilityIfHidden<R>(_ node: LayoutNodeID, _ body: () -> R) -> R {
        guard collectsAccessibility, isHidden(node) else { return body() }
        return withAccessibilitySuppressed(except: nil, body)
    }

    /// True inside a suppression scope, unless `id` is the **outermost** scope's
    /// exception: a `List` suppressing its rows keeps its own node, and a
    /// hidden ancestor (`except: nil`, outermost) still silences that `List`.
    func isAccessibilitySuppressed(for id: GlobalElementID) -> Bool {
        guard let outermost = accessibilitySuppressionExceptions.first else { return false }
        return outermost != id
    }

    /// A record's geometry: `bounds` translated exactly as `insertHitbox`
    /// translates it, that rect intersected with the active clip — the rect a
    /// hitbox would register at — and the hitbox's layer (AB-E, AB-W). The
    /// record's `order` is not known here: `AccessibilityTreeBuilder` fills it
    /// from the record's first position.
    private func accessibilityGeometry(for bounds: Bounds<Pixels>) -> AccessibilityGeometry {
        let translated = translatedByActiveOffset(bounds)
        guard let effect = prepaintEffects.last else {
            return AccessibilityGeometry(frame: translated,
                                         visibleFrame: Self.intersect(activeClip, translated),
                                         layer: activeLayer)
        }
        // Inside render effects: the transformed frame's bounding box, its
        // visible part cut by the outer clip (`GX-I`; X1, X2, X4, X5).
        return AccessibilityGeometry(
            frame: effect.composed.boundingBox(of: translated),
            visibleFrame: Self.intersect(effect.outerClip,
                                         effect.composed.boundingBox(of: Self.intersect(activeClip, translated))),
            layer: activeLayer)
    }

    /// `bounds` moved by the active scroll translation — what `insertHitbox`,
    /// `fill` and `emitAXNode` each apply before storing or emitting.
    private func translatedByActiveOffset(_ bounds: Bounds<Pixels>) -> Bounds<Pixels> {
        Bounds(origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                             y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
               size: bounds.size)
    }

    /// Records `node` as `id`'s accessibility node, resolving its `frame` and
    /// `children` from the parameters rather than from whatever `node` itself
    /// carried — see `AXNode`'s own doc on why a declared value's `frame` and
    /// `children` are not meaningful on the way in.
    ///
    /// **Also persists a durable copy, under a dedicated retention slot —
    /// this is what makes `axNode(for:)` below possible at all.** `axNodes`
    /// itself is rebuilt from scratch every frame (see its own doc), so an id
    /// not produced THIS frame is simply absent from it — a dictionary miss a
    /// caller cannot tell apart from "never existed". Design spec §9 needs
    /// more than that: a handle an AX client still holds must survive and
    /// report itself invalid, not vanish. `StateTable` already has exactly
    /// that mechanism (Tasks 1-2 of this milestone: an entry's `value`
    /// outlives the frame that stopped producing it, and `isLive` says
    /// whether it was actually produced). Riding it here is Task 4's rule
    /// applied a second time — "validity is `StateTable.isLive`, not a second
    /// liveness notion" — so this writes to a distinct child slot of `id`,
    /// never `id` itself, on `focusRetentionSlot`'s exact footing: `id` is
    /// already `ScrollView`'s own `withState(id, …)` key, typed `ScrollState`,
    /// and writing an `AXNode` there would silently clobber it (mismatched
    /// types are `StateTable.write`'s own documented clobber hazard).
    @discardableResult
    func emitAXNode(_ node: AXNode, at bounds: Bounds<Pixels>, id: GlobalElementID,
                    children: [GlobalElementID]) -> AXNode {
        var resolved = node
        // Translated by the active scroll offset, exactly as `insertHitbox`
        // translates a hitbox (ruling AB-E). **It was not, until the
        // accessibility bridge's lane 1**: a node inside a `ScrollView`
        // scrolled by 40 reported its content-space y of 100 where it was on
        // screen at 60, measured by
        // `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` before the
        // fix. Unclipped, unlike the hitbox: a frame is where the node IS, and a
        // client reads what is scrolled out of view too (arm R17).
        resolved.frame = translatedByActiveOffset(bounds)
        if let effect = prepaintEffects.last { resolved.frame = effect.composed.boundingBox(of: resolved.frame) }
        resolved.children = children
        resolved.isValid = true
        axNodes[id] = resolved
        stateTable.withState(Self.axRetentionSlot(for: id), initial: resolved) { $0 = resolved }
        return resolved
    }

    /// The state-table key that backs an AX handle's retention window — see
    /// `emitAXNode`'s own doc for why it must be a distinct slot rather than
    /// `id` itself. `at: 0` is inert, on `focusRetentionSlot`'s footing:
    /// `GlobalElementID.child(of:at:name:)` always prefers `name` when one is
    /// supplied.
    private static func axRetentionSlot(for id: GlobalElementID) -> GlobalElementID {
        .child(of: id, at: 0, name: ElementID("$ax"))
    }

    /// The durable accessibility record for `id` — design spec §9's actual
    /// requirement, and the reason `emitAXNode` above writes a second copy.
    /// `Frame.axNodes[id]` only ever answers "was this produced THIS frame";
    /// this answers "was `id` produced by the last COMPLETED frame" — exactly
    /// the query an AX client holding `id` across frames needs, and see the
    /// next paragraph for why that is not quite "is it current right now".
    ///
    /// **`.isValid` is `StateTable.isLive` at the retention slot, read fresh
    /// on every call — not a value snapshotted at emission.** A node stored
    /// while its element was being produced would read `isValid == true`
    /// forever if that flag were captured once; deriving it here, from the
    /// same table Task 4's focus retention and every `@State` slot already
    /// use, is what keeps this one liveness notion rather than a second one
    /// that could disagree with it.
    ///
    /// **That derivation has a one-frame read lag, and it is documented here
    /// rather than closed.** `StateTable.isLive` reflects the sweep at the
    /// END of the last COMPLETED frame (`Frame.render`'s `stateTable.sweep()`
    /// call); an element that stops being produced mid-frame is not noticed
    /// until that frame's own sweep runs, so a query made DURING the frame it
    /// vanished in still reads `isValid == true` — even though
    /// `Frame.axNodes[id]` for that very frame is already `nil`. Measured on
    /// this exact shape: emit, sweep (confirms — still `true`), construct the
    /// next frame with nothing re-emitting — `axNode(for:).isValid` is still
    /// `true` while `axNodes[id]` is already `nil` — sweep that frame, and
    /// only then does `isValid` become `false`. **The lag is one-directional
    /// and self-correcting**: it can only report valid one frame too long,
    /// never invalid too early, and it always resolves by the next sweep. A
    /// lag-free answer needs a per-frame production signal alongside
    /// `StateTable.isLive` — the shape `Frame.focusedElementProducedThisFrame`
    /// gives focus — which is a second signal on top of the one liveness
    /// notion this task's brief forbids adding; not built here for that
    /// reason.
    ///
    /// `nil` only once the slot is actually reaped by `sweep()`'s existing
    /// bound (`StateTable.staleAfterGenerations`/`sweepThreshold`) — the same
    /// bound divergence 12 and 17 already ride, not a new one invented here.
    /// Until then, an id that was never emitted at all is indistinguishable
    /// from one reaped long ago (`nil` either way); an id whose element
    /// merely stopped being produced is not — it comes back with
    /// `.isValid == false`, the tombstone spec §9 asks for, rather than
    /// vanishing or dangling. **This reaped→`nil` transition is unpinned by
    /// any test** — the obvious fixture (a fixed set of filler keys) falls
    /// back under `sweepThreshold` before reaching it and the slot then
    /// survives forever reporting `isValid == false`, never `nil`; reaching
    /// the reap needs fresh keys every frame holding the table above
    /// `sweepThreshold`, which no test here does. Left unmeasured rather than
    /// given a test that cannot express the defect (MP-J's shape) — see this
    /// task's fix-round report.
    func axNode(for id: GlobalElementID) -> AXNode? {
        let slot = Self.axRetentionSlot(for: id)
        guard var node = stateTable.peek(slot, as: AXNode.self) else { return nil }
        node.isValid = stateTable.isLive(slot)
        return node
    }

    // MARK: - Focus (design spec §4.2)

    /// What each element asked for on the keyboard side this frame, built
    /// during `prepaint` by `registerHandlers` above.
    ///
    /// **Registered in prepaint, alongside hitboxes and for the same reason**
    /// (§4.2, and §8.1 before it): it is the one phase where positions have
    /// resolved and nothing has been emitted yet. Focus itself needs no
    /// geometry — nothing here reads `bounds` — but the registration rides on
    /// the call that does, so a conformer that registers its click target
    /// registers its focusability in the same line and cannot forget one.
    ///
    /// `Window` captures this after the frame the way it captures `hitboxes`,
    /// because the frame is gone by the time a key event arrives.
    private(set) var focusRegistry = FocusRegistry()

    /// The focused element for this frame — handed in from `Window`, then
    /// possibly **cleared here** by `resolveFocus()` — see that method's own
    /// doc for the actual rule, which is no longer just "if this frame did
    /// not produce it": an id the state table still retains, live or
    /// tombstoned, survives a frame that did not produce it (divergence 17).
    ///
    /// A `var` rather than a `let`, unlike `activeElement`, and that difference
    /// is the whole of §4.2's dangling rule: `Window` reads this back after
    /// `render` returns, so the clearing decision is made against the registry
    /// the frame actually built rather than against the previous frame's.
    private(set) var focusedElement: GlobalElementID?

    /// Whether `registerHandlers` saw `focusedElement` produced this frame —
    /// **independent of what it asked for**, unlike `focusRegistry.isFocusable`.
    /// See `registerHandlers`'s own doc. Defaults `false`; nothing has to reset
    /// it between frames because `Frame` itself is rebuilt fresh every frame
    /// (`Window.drawFrameIfNeeded`).
    private var focusedElementProducedThisFrame = false

    /// Drops focus when the focused element was not produced this frame AND
    /// is no longer retained by the state table (design spec §4.2, closing
    /// CLAUDE.md's divergence 17).
    ///
    /// **Called once per frame, from `render`, at the prepaint/paint boundary
    /// — beside `resolveHover(at:)` and for its reason.** "Was it produced" is
    /// not knowable until every element's `prepaint` has run, so asking earlier
    /// would answer from a half-built registry; asking later, after `paint`,
    /// would let this frame paint a focus ring for an element it has already
    /// decided is not focused.
    ///
    /// **Two separate questions, and conflating them is the trap.** "Is
    /// `focused` still `.focusable()` right now" is `focusRegistry.isFocusable`;
    /// an element that answers no to that but WAS produced this frame (it
    /// simply stopped asking to be focusable) loses focus on the spot — the
    /// existing contract, pinned by `anElementThatStopsBeingFocusableLosesFocus`,
    /// and nothing here weakens it. "Was `focused` produced at all this frame"
    /// is `focusedElementProducedThisFrame`, and only when that is ALSO false —
    /// nothing at `focused`'s position in the tree ran `prepaint` — does this
    /// fall back to the state table. **One notion of "still exists", not two**
    /// (design spec §5): rather than a focus-specific grace period, an id that
    /// stops being produced keeps focus for exactly as long as
    /// `StateTable` retains its `$focus` slot — live or tombstoned, the same
    /// `staleAfterGenerations` bound divergence 12's `@State` entries get,
    /// because it rides the identical `sweep()`/reap. Once that slot is
    /// actually reaped, `peek` returns `nil` and focus clears here, one frame
    /// after the reap happened.
    ///
    /// **"The same `staleAfterGenerations` bound" above is the CEILING, not the
    /// behaviour an ordinary tree gets — and three consequences follow that
    /// nobody designed in.** The reap runs only on a sweep where
    /// `storage.count` exceeds `StateTable.sweepThreshold` (**256**), so below
    /// that a retained `$focus` slot is never reaped. All three were measured
    /// through a real `Window` on 2026-09-02, when an `if` was the route; **since
    /// plan task 12 part 1 (`IX-I`) they hold only for a subtree nothing
    /// evaluates** — a `List` row out of its window (`TB-AH`). An element an
    /// evaluated reset removes (an `if`, a loop's dropped tail, a departed
    /// `.id`) loses its `$focus` slot in that frame's `sweep()` — `$focus` is
    /// no longer exempt — and `render` clears focus in the same frame, right
    /// after the sweep (`StateTable.resetFocusSlots`; probe arm F2: SwiftUI
    /// drops focus and does not restore it). Pinned by
    /// `focusDropsWhenAnIfRemovesItsElement` (renamed from
    /// `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`).
    ///
    /// 1. **Retained indefinitely, while unevaluated.** A focused `List` row
    ///    windowed out keeps focus for as long as its slot survives — below
    ///    the threshold, indefinitely.
    /// 2. **The unevaluated subtree's still-produced ANCESTORS keep claiming
    ///    its keystrokes.** `focusChain(from:)` walks the retained id's parent
    ///    chain; those ancestors are produced and registered, so an ancestor's
    ///    `onKey` and `keyContext` stay live while the row is out of its
    ///    window. (Through an `if` this no longer happens: focus is `nil` by
    ///    the end of the frame that removed the element, so a keystroke
    ///    reaches `Window.onInput`.)
    /// 3. **Focus is RESTORED on return** from the window —
    ///    `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`. Through
    ///    an `if` it is not (`IX-I`).
    ///
    /// **All three require a CONFIRMING FRAME, which is easy to trip over.**
    /// `registerHandlers` writes the `$focus` slot only while the focused id is
    /// actually being produced, so `Window.focus(x)` followed by removal with
    /// no frame rendered in between retains nothing — measured by getting it
    /// wrong first, in a probe that skipped the frame and looked like a
    /// refutation of all three. `focusSetWithNoConfirmingFrameHasNothingToRetain`
    /// is that boundary's pin.
    ///
    /// A free method rather than a step inlined into `render`, so a test can
    /// drive `PrepaintPass` directly and resolve focus explicitly, exactly as
    /// `resolveHover(at:)` allows.
    func resolveFocus() {
        guard let focused = focusedElement else { return }
        if focusRegistry.isFocusable(focused) { return }
        if focusedElementProducedThisFrame {
            focusedElement = nil
            return
        }
        if stateTable.peek(Self.focusRetentionSlot(for: focused), as: Bool.self) == nil {
            focusedElement = nil
        }
    }

    /// The topmost **opaque** hitbox containing `point`, or `nil` when nothing
    /// opaque is under it.
    ///
    /// A thin wrapper over `topmostOpaqueHitbox(in:at:)`, which is the single
    /// copy of the ranking and carries its reasoning. `Window` calls the same
    /// function against its own captured copy of the last frame's list, because
    /// the frame that built it is gone by the time an input event arrives.
    func topmostHitbox(at point: Point<Pixels>) -> HitboxID? {
        topmostOpaqueHitbox(in: hitboxes, at: point).map { HitboxID(index: $0) }
    }

    /// This frame's answer to "what is the pointer over", written once by
    /// `resolveHover(at:)` and read by `PaintPass.isHovered(_:)`. `nil` until
    /// `resolveHover` runs, and `nil` again if it runs with nothing under the
    /// pointer.
    private(set) var hoveredHitbox: HitboxID?

    /// The topmost hitbox under the pointer, resolved **once**, against every
    /// hitbox registered so far — design spec §3.3.
    ///
    /// **Called exactly once per frame, from `render`, at the prepaint/paint
    /// boundary — after `prepaint` has returned and before `glyphAtlas.beginFrame()`.**
    /// "Topmost wins" is not knowable until every hitbox has registered, so
    /// resolving during registration (or before it) would give an answer that
    /// depends on declaration order rather than on the finished list. Resolving
    /// here, rather than lazily on first query during `paint`, is what makes
    /// `PaintPass.isHovered(_:)` a plain equality check with no one-frame lag:
    /// every element's `paint` sees the same answer regardless of which of them
    /// asks first.
    ///
    /// A free function rather than folded into `render` itself so a test can
    /// drive `PrepaintPass` directly — the idiom the rest of `HitboxTests.swift`
    /// already uses — and resolve hover explicitly, with no element and no
    /// `Frame.render` call in the way.
    func resolveHover(at point: Point<Pixels>?) {
        hoveredHitbox = point.flatMap { topmostHitbox(at: $0) }
    }

    /// Which **element** owns `hoveredHitbox`, or `nil` when nothing is
    /// hovered.
    ///
    /// **A derived view of `hoveredHitbox`, not a second piece of state** —
    /// there is one resolution per frame and this reads its answer, so the two
    /// cannot disagree. It exists because an element in `paint` has its own
    /// `GlobalElementID` and *not* its `HitboxID`:
    /// `PrepaintPass.registerHandlers(_:at:id:)` returns nothing, so a
    /// conformer has nowhere to keep the index even if it wanted one. See
    /// `PaintPass.isHovered(_ id: GlobalElementID)`.
    ///
    /// **The two keys coincide today and the reason is worth stating**, since
    /// it is what makes this lookup exact rather than approximate: an element
    /// registers at most one hitbox — `registerHandlers` is the only production
    /// path into the list for a handler set and it is called once per element
    /// per frame — so "this element's hitbox is hovered" and "the hovered
    /// hitbox belongs to this element" are the same question. An element that
    /// registered two would make this answer `true` for both, where the
    /// `HitboxID`-keyed query would still separate them.
    var hoveredElement: GlobalElementID? {
        hoveredHitbox.map { hitboxes[$0.index].id }
    }

    /// The cross-frame state table (§4.3).
    ///
    /// **Not owned here — `Frame` is per-frame and this outlives it.** The
    /// window owns it and hands the same instance to every frame; that is the
    /// whole point, and a `Frame` that constructed its own would give every
    /// element fresh state each frame while every test still passed.
    let stateTable: StateTable

    /// The shaping cache (spec §3.2), owned **by the window** exactly as
    /// `stateTable` is, and handed to every frame.
    ///
    /// **A per-frame cache would be a cache that never hits.** It would re-shape
    /// every string on every frame — through CoreText, three times per text item
    /// per layout, since §4.5's automatic minimum probes every item — while
    /// leaving the entire suite green, because a single-frame test cannot tell
    /// a warm cache from a cold one. That is the `StateTable` hazard in a second
    /// place, and `twoFramesShareOneShapingCacheRatherThanReShapingEachFrame`
    /// is the test that can see it: it renders two frames and asserts the miss
    /// count did not double.
    ///
    /// It is keyed on content — `(string, FontKey, width)` — not on element
    /// identity, so two `Text`s showing the same string share one entry and a
    /// `Text` that moves keeps its shape.
    let shapingCache: ShapingCache

    /// The text engine every `Text` and `ProposalText` measures and draws
    /// through (ruling TS-A) — the window's, chosen once per app. By default
    /// the CoreText system over ``shapingCache``, so a test that builds a
    /// frame with its own cache and inspects it sees exactly the entries it
    /// did before the seam.
    let textSystem: any TextSystem

    /// The glyph atlas (spec §3.5), owned **by the window** for exactly the
    /// reasons `stateTable` and `shapingCache` are, and with a sharper
    /// consequence than either.
    ///
    /// **A per-frame atlas would re-rasterize every glyph on every frame** —
    /// `CTFontDrawGlyphs` per glyph per variant, the single most expensive step
    /// in drawing text — *and* would upload a whole fresh texture to the GPU
    /// each time, while every test in the repo stayed green: a single-frame
    /// test cannot tell a warm atlas from a cold one, and the pixels are
    /// identical either way. `theAtlasSurvivesTheFrameThatFilledIt` is what can
    /// see it.
    ///
    /// It is keyed on ``MetalUIText/GlyphKey`` — face, glyph id, size, subpixel
    /// variant and scale factor — so two `Text`s in one font share every glyph
    /// they have in common, and a window dragged onto a display with a
    /// different backing scale re-rasterizes rather than serving a 1x bitmap
    /// into a 2x frame.
    let glyphAtlas: GlyphAtlas

    init(contentSize: Size<Pixels>, scaleFactor: Float, rootFontSize: Double = 16,
         stateTable: StateTable = StateTable(),
         shapingCache: ShapingCache = ShapingCache(),
         textSystem: (any TextSystem)? = nil,
         glyphAtlas: GlyphAtlas = GlyphAtlas(width: Window.atlasExtent,
                                             height: Window.atlasExtent),
         theme: Theme = .light,
         lightTheme: Theme = .light,
         darkTheme: Theme = .dark,
         timestamp: Double = 0,
         mousePosition: Point<Pixels>? = nil,
         activeElement: GlobalElementID? = nil,
         focusedElement: GlobalElementID? = nil,
         transaction: Animation? = nil,
         disablesAnimations: Bool = false,
         snapsEveryChange: Bool = false,
         animationStore: AnimationStore = AnimationStore(),
         surfaceRegistry: SurfaceRegistry = SurfaceRegistry(),
         collectsAccessibility: Bool = false,
         reportsUnlowerableFields: Bool = false,
         recordsElementBounds: Bool = false) {
        self.tree = LayoutTree(generation: Frame.nextTreeGeneration)
        Frame.nextTreeGeneration += 1
        self.contentSize = contentSize
        self.scaleFactor = scaleFactor
        self.rootFontSize = rootFontSize
        self.stateTable = stateTable
        self.shapingCache = shapingCache
        #if canImport(MetalUIText)
        self.textSystem = textSystem ?? CoreTextTextSystem(cache: shapingCache)
        #else
        guard let textSystem else {
            preconditionFailure("a Frame needs a TextSystem off Apple platforms: there is no CoreText (ruling XP-B)")
        }
        self.textSystem = textSystem
        #endif
        self.glyphAtlas = glyphAtlas
        self.rootTheme = theme
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        var root = EnvironmentValues()
        root.theme = theme
        root.displayScale = Self.displayScale(forScaleFactor: scaleFactor)
        self.storedRootEnvironment = root
        self.environmentTop = root
        self.timestamp = timestamp
        self.mousePosition = mousePosition
        self.activeElement = activeElement
        self.focusedElement = focusedElement
        self.transaction = transaction
        var rootTransaction = Transaction(animation: snapsEveryChange ? nil : transaction)
        rootTransaction.disablesAnimations = disablesAnimations || snapsEveryChange
        self.snapsEveryChange = snapsEveryChange
        self.transactionTop = rootTransaction
        self.animationStore = animationStore
        self.surfaceRegistry = surfaceRegistry
        self.collectsAccessibility = collectsAccessibility
        self.reportsUnlowerableFields = reportsUnlowerableFields
        self.recordsElementBounds = recordsElementBounds
    }

    // MARK: - Lowering diagnostics (plan task 7, rulings LR-C, LR-D)
    //
    // Stage 9 (`LR-FC`) deleted the layout authority — `layoutAuthority`, its
    // `init` parameter and `defaultLayoutAuthority` — with the legacy engine:
    // every frame lowers its legacy elements onto the proposal kernel.

    /// Whether a site with no proposal lowering records an `UnlowerableField` and
    /// carries on instead of trapping. **Set only by tests** (the differential
    /// harness): a diagnostic is what lets a lowering test read red without
    /// truncating the suite (ruling LR-C). Production frames never set it, and the
    /// exit tests that pin each trap run with it off.
    let reportsUnlowerableFields: Bool

    /// What the sites reported, in registration order — **empty unless
    /// `reportsUnlowerableFields`**.
    private(set) var unlowerableFields: [UnlowerableField] = []

    /// The proposal lowering's item records and bounds aliases (plan task 7, stage
    /// 2; rulings LR-AB, LR-AT).
    var lowering = LoweringState()

    /// The element nodes a lowered `hidden()` produced this frame (plan task 7,
    /// stage 6b, ruling `LR-DH`): a `display: .none` node is laid out as if shown
    /// and its element node is inserted here by `LegacyLowering.swift`, and the
    /// three gates read it — paint skipped (`Element.paintGroup`), hitboxes under
    /// the pointer-disable scope (`disablingHitTestingIfHidden`), accessibility
    /// suppressed (`isHidden`) — per inner `ModifiedElement` layer, in
    /// `AnyElement`'s group entry and at the root. The one source of "hidden"
    /// since stage 9 (`LR-FC`).
    var hiddenNodes: Set<LayoutNodeID> = []

    /// Whether `node` is hidden for accessibility: a lowered `hidden()` put it in
    /// `hiddenNodes` (`LR-DH` item 3). Until stage 9 it also read the node's
    /// registered style for the legacy path's `display: .none` (ruling AB-O); no
    /// node carries a style since (`LR-FC`).
    func isHidden(_ node: LayoutNodeID) -> Bool {
        hiddenNodes.contains(node)
    }

    /// Whether `elementBounds` is filled. Set only by tests (the differential
    /// harness, ruling LR-D).
    let recordsElementBounds: Bool

    /// Each element's resolved bounds this frame, by id — **empty unless
    /// `recordsElementBounds`**. Written at the four places an element's bounds
    /// are handed to its `prepaint`: the root (`render`), every group member
    /// (`Element.prepaintGroup`, and `AnyElement`'s own group entry, a copy of it —
    /// lane 5), and every inner `ModifiedElement` layer (`prepaintLayer`). An id
    /// placed twice keeps its last rect.
    private(set) var elementBounds: [GlobalElementID: Bounds<Pixels>] = [:]

    /// Records `bounds` for `id` when this frame records element bounds.
    ///
    /// **Also where a pending `scrollTo` finds its target** (ruling `DD-G`
    /// item 3), whether or not the frame records bounds: one flag read per
    /// element while no request is pending.
    func recordElementBounds(_ id: GlobalElementID, _ bounds: Bounds<Pixels>) {
        if hasUnresolvedScrollRequests { matchScrollRequests(id, bounds) }
        guard recordsElementBounds else { return }
        elementBounds[id] = bounds
    }

    /// A legacy site met a field (or is a site) with no proposal lowering.
    /// **Traps** with `field.trapMessage` unless this frame reports; reporting,
    /// records the entry and returns. The site is always the caller's own
    /// argument (ruling LR-C). For a site that registers nothing in place of the
    /// field — `StyledComponent`'s amend — this is the whole check.
    func noteUnlowerable(_ field: UnlowerableField) {
        guard reportsUnlowerableFields else { preconditionFailure(field.trapMessage) }
        unlowerableFields.append(field)
    }

    /// `noteUnlowerable(_:)`, then — reporting — a 0×0 native leaf in place of
    /// the node the site would have registered, so the frame completes. Whatever
    /// the site had already registered below it is orphaned: its rects are unset
    /// and the harness reports them, which is noise, not silence (ruling LR-C's
    /// cost).
    func unlowerable(_ field: UnlowerableField) -> LayoutNodeID {
        noteUnlowerable(field)
        return requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 0, height: 0)) }
    }

    // MARK: - The stack-axis stack (platform services, `SV-O` item 2)

    /// The axes of the linear stacks enclosing the element being laid out,
    /// innermost last: `HStack`/`Row` push `.horizontal`, `VStack`/`Column`
    /// `.vertical`, and `ZStack`/`Grid` `nil` ("no stack"). A `Divider` reads
    /// the top at its layout request. Every other container pushes nothing, so
    /// it is transparent. Layout-only: the phases after layout never read it.
    private var stackAxes: [ProposalStackAxis?] = []

    /// The innermost enclosing stack's axis, or `nil` outside any stack or
    /// inside a `ZStack` or `Grid` (`SV-O` item 2, `V3`, `V4`).
    var stackAxis: ProposalStackAxis? { stackAxes.last ?? nil }

    /// Runs `body` — a container's request of its children's layout — with
    /// `axis` on top of the stack-axis stack, popped by `defer` on every exit,
    /// so the axis never reaches a later sibling (`SV-O` item 2).
    func withStackAxis<T>(_ axis: ProposalStackAxis?, _ body: () -> T) -> T {
        stackAxes.append(axis)
        defer { stackAxes.removeLast() }
        return body()
    }

    // MARK: - Layout phase

    // Stage 9 (`LR-FC`): the legacy registrars `requestNode(style:children:)`
    // and `requestLeaf(style:measure:)`, and their proposal-authority backstop
    // (`LR-C`), went with the legacy engine. Every registrar below is native.

    func requestNativeLeaf(measure: @escaping ProposalMeasureFunction) -> LayoutNodeID {
        StackMeter.sample()   // a tree's deepest layout point (`PE-L` item 2)
        return tree.newNativeLeaf(measure: measure)
    }

    func requestNativeOverlay(children: [LayoutNodeID],
                              alignment: ProposalAlignment = .center) -> LayoutNodeID {
        tree.newNativeOverlay(children: children, alignment: alignment)
    }

    func requestNativeOverlayAttachment(child: LayoutNodeID, overlay: LayoutNodeID,
                                        alignment: ProposalAlignment = .center) -> LayoutNodeID {
        tree.newNativeOverlayAttachment(child: child, overlay: overlay, alignment: alignment)
    }

    func requestNativeFrame(child: LayoutNodeID, width: Double? = nil,
                            height: Double? = nil,
                            minWidth: Double? = nil, idealWidth: Double? = nil,
                            maxWidth: Double? = nil,
                            minHeight: Double? = nil, idealHeight: Double? = nil,
                            maxHeight: Double? = nil,
                            alignment: ProposalAlignment = .center) -> LayoutNodeID {
        tree.newNativeFrame(child: child, width: width, height: height,
                            minWidth: minWidth, idealWidth: idealWidth,
                            maxWidth: maxWidth,
                            minHeight: minHeight, idealHeight: idealHeight,
                            maxHeight: maxHeight,
                            alignment: alignment)
    }

    func requestNativePadding(child: LayoutNodeID,
                              insets: Edges<Double>) -> LayoutNodeID {
        tree.newNativePadding(child: child, insets: insets)
    }

    func requestNativeFixedSize(child: LayoutNodeID,
                                horizontal: Bool = true,
                                vertical: Bool = true) -> LayoutNodeID {
        tree.newNativeFixedSize(child: child, horizontal: horizontal, vertical: vertical)
    }

    func requestNativeAspectRatio(child: LayoutNodeID, ratio: Double?,
                                  contentMode: AspectRatioContentMode = .fit) -> LayoutNodeID {
        tree.newNativeAspectRatio(child: child, ratio: ratio, contentMode: contentMode)
    }

    func requestNativeLayoutPriority(child: LayoutNodeID, priority: Double) -> LayoutNodeID {
        tree.newNativeLayoutPriority(child: child, priority: priority)
    }

    func requestNativeSpacer(minLength: Double? = nil) -> LayoutNodeID {
        tree.newNativeSpacer(minLength: minLength)
    }

    func requestNativeScrollViewport(child: LayoutNodeID,
                                     axis: ProposalStackAxis) -> LayoutNodeID {
        tree.newNativeScrollViewport(child: child, axis: axis)
    }

    func requestNativeLinearStack(children: [LayoutNodeID], axis: ProposalStackAxis,
                                  spacing: Double? = 0,
                                  alignment: ProposalAlignment = .center,
                                  baseline: ProposalTextBaseline? = nil) -> LayoutNodeID {
        tree.newNativeLinearStack(children: children, axis: axis, spacing: spacing,
                                  alignment: alignment, baseline: baseline)
    }

    func requestNativeLayout(_ layout: some ProposalLayout,
                             children: [LayoutNodeID]) -> LayoutNodeID {
        tree.newNativeLayout(layout, children: children)
    }

    /// Lays the finished tree out, between `requestLayout` and `prepaint`. Not
    /// reachable from any pass: elements contribute nodes, the frame runs the
    /// engine on the finished root.
    ///
    /// **One engine since stage 9** (`LR-FC`). The root is measured at the
    /// content size and placed CENTRED at its own answer
    /// (`computeNativeLayout(root:proposal:centredIn:)`, ruling CN-J, probe
    /// R1/R2); a root that takes the whole offer fills the window. Until stage 9
    /// a legacy root ran the CSS flex engine here instead.
    ///
    /// **Presentations first** (plan task 7, stage 5, ruling `LR-CM`). With any
    /// presentation registered: each presentation root in registration order in
    /// its own native run, with the window as proposal and bounds, then the root
    /// exactly as before.
    /// **Before** the root, so `LayoutTree.lastNativeLayoutWork` still reads the
    /// root's own run (`SA-M`); separate runs, so a presentation's depth counts
    /// from its own root (`SA-L`) and the root's placement (`CN-J`) is untouched.
    ///
    /// **Content size limits first** (ruling `SV-L` item 2): under
    /// `.contentMinSize` the root is measured at a zero proposal, under
    /// `.contentSize` also at an infinite one — measure-only runs, before every
    /// real run, so `lastNativeLayoutWork` still reads the root's own. Under
    /// `.automatic` nothing is measured.
    func computeRootLayout(root: LayoutNodeID, toolbarStrip strip: LayoutNodeID? = nil) {
        let width = Double(contentSize.width.value), height = Double(contentSize.height.value)
        // A drawn toolbar strip takes the window's top (`MD-K` item 2): the
        // root is offered, and centred in, the rect below it, and the window's
        // content limits include it. Without one, `top` is 0 — today's values.
        let top = strip == nil ? 0 : Double(ToolbarStrip.height)
        let rootHeight = max(0, height - top)
        if contentSizeLimitsMode != .automatic {
            contentMinimum = Self.size(of: tree.measureNativeLayout(root: root, proposal: .zero), plus: top)
            if contentSizeLimitsMode == .contentSize {
                contentMaximum = Self.size(of: tree.measureNativeLayout(root: root, proposal: .infinity), plus: top)
            }
        }
        for presentation in lowering.presentations {
            tree.computeNativeLayout(root: presentation.root,
                                     proposal: ProposedSize(width: width, height: height),
                                     in: LayoutRect(x: 0, y: 0, width: width, height: height))
        }
        // The strip's own run (`MD-K` item 4), before the root's so the
        // root's run stays the tree's last (`lastNativeLayoutWork`, the
        // deepest level) — the runs are independent (`MD-Z` item 2).
        if let strip {
            _ = tree.computeNativeLayout(root: strip,
                                         proposal: ProposedSize(width: width, height: top),
                                         centredIn: LayoutRect(x: 0, y: 0, width: width, height: top))
        }
        _ = tree.computeNativeLayout(root: root,
                                     proposal: ProposedSize(width: width, height: rootHeight),
                                     centredIn: LayoutRect(x: 0, y: top, width: width, height: rootHeight))
    }

    // MARK: - Post-layout phases

    /// A node's resolved bounds, **absolute to the root** — the engine stores
    /// absolute rects, so no parent offset is added here.
    ///
    /// **Through the lowering's bounds alias** (plan task 7, stage 2, ruling LR-AB):
    /// an element its parent grew or stretched is the
    /// item frame the parent registered around it, so every reader of an element's
    /// rect — decoration, hitbox, accessibility, glyph origin — sees the CSS box. A
    /// reader of `tree.layout` for an element would bypass it.
    func bounds(of node: LayoutNodeID) -> Bounds<Pixels> {
        let rect = tree.layout(lowering.alias(node))
        return Bounds(
            origin: Point(x: Pixels(Float(rect.x)), y: Pixels(Float(rect.y))),
            size: Size(width: Pixels(Float(rect.width)), height: Pixels(Float(rect.height))))
    }

    // MARK: - Paint phase

    /// Emits one filled rect, optionally with rounded corners.
    ///
    /// Explicit z-order is still ahead (§7.3): every rect here is
    /// emitted at `order: 0`, and `Scene.finalize()` sorts stably, so equal
    /// orders keep emission sequence — which is why a container's own
    /// background paints under its children provided it emits first.
    /// `bounds` is translated by `activeOffset` and `contentMask` is
    /// `activeClip`, both scaled to match — the whole surface and zero offset
    /// when no `clipped(to:offsetBy:)` block is active, which is why no
    /// existing call site's output moves.
    ///
    /// **`borderColor` and `borderWidths` are parameters, and both paths reach
    /// them.** This doc said "`borderColor` is `.transparent` and there is no
    /// way to set it": that was true of a width derived from `Style.border`, an
    /// `Edges<Length>` whose percentage case resolves against the **containing
    /// block's width**, which the engine computes inside `contentBox` and
    /// discards rather than storing on the node. Re-resolving one here against
    /// the box's own width is the exact mistake CLAUDE.md's percentage-inset
    /// constraint records, and storing the resolved edges on `LayoutTree` is
    /// still what would unblock *that*.
    ///
    /// What unblocked a border was declaring one that needs no resolution.
    /// `NativeModifiedContent`'s `.border` (proposal path) and
    /// `Decoration.border`/`hoverBorder`/`focusBorder` (legacy path, rulings
    /// `OM-B`/`OM-L`) both carry `Pixels`, which paint can pair with a colour
    /// directly. `Style.border` was deleted by stage 10 (`LR-FM` item 1).
    func fill(_ bounds: Bounds<Pixels>, color: Hsla,
              cornerRadii: Corners<Pixels> = Corners(all: Pixels(0)),
              borderColor: Hsla = .transparent,
              borderWidths: Edges<Pixels> = Edges(all: Pixels(0)),
              shape: PrimitiveShape = .roundedRectangle) {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        let rect = MUIRect(
            bounds: translated.scaled(by: scaleFactor),
            contentMask: activeClip.scaled(by: scaleFactor),
            maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
            background: Hsla(h: color.h, s: color.s, l: color.l, a: color.a * activeOpacity),
            borderColor: Hsla(h: borderColor.h, s: borderColor.s, l: borderColor.l,
                              a: borderColor.a * activeOpacity),
            cornerRadii: cornerRadii.scaled(by: scaleFactor),
            borderWidths: Edges(top: borderWidths.top.scaled(by: scaleFactor),
                                right: borderWidths.right.scaled(by: scaleFactor),
                                bottom: borderWidths.bottom.scaled(by: scaleFactor),
                                left: borderWidths.left.scaled(by: scaleFactor)),
            order: 0, shape: shape)
        if paintScopes.isEmpty {
            scene.insert(rect, layer: activeLayer)
        } else {
            insertThroughScopes(.rect(rect, layer: activeLayer, innerMask: false))
        }
    }

    /// Emits one image quad sampling the whole of `texture` over `bounds`
    /// (ruling TE-AF) — `fill`'s arithmetic exactly: `bounds` in points,
    /// translated by `activeOffset` then scaled, the mask `activeClip` with
    /// its radii, scaled, the opacity `activeOpacity`, on `activeLayer`. The
    /// scene carries `texture` once however often it is drawn.
    func drawImage(_ texture: ImageTexture, in bounds: Bounds<Pixels>, filter: ImageFilter) {
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        let image = MUIImage(bounds: translated.scaled(by: scaleFactor),
                             contentMask: activeClip.scaled(by: scaleFactor),
                             maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
                             opacity: activeOpacity, filter: filter, order: 0)
        if paintScopes.isEmpty {
            scene.insert(image, texture: texture, layer: activeLayer)
        } else {
            insertThroughScopes(.image(image, texture: texture, layer: activeLayer, innerMask: false))
        }
    }

    /// The largest side of a surface's render target, in device pixels
    /// (MetalView, `MV-E` item 2): the SDL bridge's texture limit
    /// (`mui_renderer_create_texture`); Metal's is 16384 — one limit for both.
    /// A larger element samples its target stretched.
    static let maxSurfaceTargetSide = 8192

    /// The window's map from an element to its surface's `SurfaceID`
    /// (MetalView, `MV-E` item 6) — **not** a `StateTable` entry. A `Frame`
    /// built without a window gets a fresh one.
    let surfaceRegistry: SurfaceRegistry

    /// This frame's app-owned surfaces' draw requests, in paint order —
    /// handed by `Window` to `WindowRenderer.finishFrame(scene:atlas:surfaces:)`
    /// (`MV-F`). A headless `renderFrame` drops them.
    private(set) var surfaceRequests: [SurfaceDrawRequest] = []

    /// Emits one app-owned surface's quad and its draw request (MetalView,
    /// rulings `MV-D`, `MV-E` item 2, `MV-G`) — ``drawImage(_:in:filter:)``'s
    /// arithmetic line for line: `bounds` in points, translated by
    /// `activeOffset` then scaled, the mask `activeClip` with its radii,
    /// scaled, the opacity `activeOpacity`, on `activeLayer`, linear-filtered,
    /// through `insertThroughScopes` so a transition's ghost and a drag
    /// preview replay it as they replay an image.
    ///
    /// The target is `Int((pt × scale).rounded())` device pixels per axis,
    /// computed from the **laid-out** bounds (a transition never reallocates),
    /// clamped to ``maxSurfaceTargetSide``. **Nothing is emitted** — no quad, no
    /// request, so a renderer releases the target and does no GPU work — when a
    /// side rounds to 0, the translated bounds do not intersect `activeClip`,
    /// or `activeOpacity` is 0 (`MV-G` item 4). A `.continuous` surface notes an
    /// active animation, keeping the display link awake — never
    /// `requestAnotherFrame()` (CLAUDE.md "Animation": never raise both).
    func drawSurface(id: GlobalElementID, bounds: Bounds<Pixels>, policy: RedrawPolicy,
                     value: AnyHashable?, draw: @escaping @MainActor (any GPUSurfaceContext) -> Void) {
        // Counted before the guards, so a skipped sibling sharing one `.id`
        // keeps its place (`MV-M` item 5).
        let occurrence = surfaceRegistry.occurrence(for: id)
        let width = min(Self.maxSurfaceTargetSide, Int((bounds.size.width.value * scaleFactor).rounded()))
        let height = min(Self.maxSurfaceTargetSide, Int((bounds.size.height.value * scaleFactor).rounded()))
        guard width > 0, height > 0 else { return }
        guard activeOpacity > 0 else { return }
        let translated = Bounds(
            origin: Point(x: Pixels(bounds.origin.x.value + activeOffset.x.value),
                          y: Pixels(bounds.origin.y.value + activeOffset.y.value)),
            size: bounds.size)
        let clip = activeClip
        let overlapWidth = min(translated.origin.x.value + translated.size.width.value,
                               clip.origin.x.value + clip.size.width.value)
            - max(translated.origin.x.value, clip.origin.x.value)
        let overlapHeight = min(translated.origin.y.value + translated.size.height.value,
                                clip.origin.y.value + clip.size.height.value)
            - max(translated.origin.y.value, clip.origin.y.value)
        guard overlapWidth > 0, overlapHeight > 0 else { return }

        let target = SurfaceTarget(id: surfaceRegistry.id(for: id, occurrence: occurrence), width: width, height: height)
        let quad = MUIImage(bounds: translated.scaled(by: scaleFactor),
                            contentMask: clip.scaled(by: scaleFactor),
                            maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
                            opacity: activeOpacity, filter: .linear, order: 0)
        insertThroughScopes(.surface(quad, target: target, layer: activeLayer, innerMask: false))
        surfaceRequests.append(SurfaceDrawRequest(target: target, scaleFactor: scaleFactor, time: timestamp,
                                                  policy: policy, value: value, draw: draw))
        if policy == .continuous { noteActiveAnimation() }
    }

    /// Emits one glyph sprite, taking its bitmap from the atlas and rasterizing
    /// it there on first sight.
    ///
    /// **Everything here is already in device pixels and nothing is scaled**,
    /// which is the opposite of `fill` above and is deliberate. A glyph bitmap
    /// is rasterized *on* the device grid — `GlyphKey` carries the scale factor
    /// and `GlyphImage`'s bearings are in device pixels — so the conversion has
    /// already happened, in `ShapedText.placedGlyphs`, once. Scaling again here
    /// would double-scale exactly the way `PaintPass.fill`'s doc warns about.
    ///
    /// **The bearings come from the atlas, not from a second look at the
    /// font.** `PackedGlyph.left`/`.top` are the values the rasterizer computed
    /// with the same `floor`/`ceil` that produced the bitmap's width and height;
    /// re-deriving them from `CTFontGetBoundingRectsForGlyphs` here is the
    /// percentage-inset mistake CLAUDE.md records — one quantity resolved twice,
    /// free to disagree with itself by a pixel.
    ///
    /// Two returns without an error, and they are different situations:
    ///
    /// - **The atlas is full** (`nil`). Nothing this frame can do about it: the
    ///   packer never revisits a closed shelf, so there is no smaller correct
    ///   answer than dropping the glyph. It is silent because a `throw` here
    ///   would take down a frame that is otherwise entirely drawable.
    /// - **The glyph has no ink** (a zero-area slot — a space, and the
    ///   commonest glyph in a paragraph). Emitting it would add an instance
    ///   whose quad is degenerate and whose sampler reads nothing; the atlas
    ///   still records it so `rasterize` is not re-run for every space.
    ///
    /// `contentMask` is `activeClip`, scaled exactly as `fill` above scales
    /// it. **The offset is scaled here too, and that is the one place this
    /// method is not the mirror of `fill`.** `fill` receives points and scales
    /// the whole translated rect at the end; `draw`'s `bounds` are already in
    /// device pixels, so `activeOffset` — still in points, the space the clip
    /// stack is pushed in — has to be multiplied by `scaleFactor` before it is
    /// added, not after. Adding it unscaled would shift glyphs by the scale
    /// factor's worth of points on a Retina display and by nothing at 1x,
    /// which is exactly the kind of bug a 1x-only test cannot see.
    #if canImport(MetalUIText)
    func draw(_ placed: PlacedGlyph, color: Hsla) {
        drawSprite(key: placed.key, pixelX: placed.pixelX, baselineY: placed.baselineY, color: color) {
            GlyphRaster.rasterize(glyph: placed.key.glyph, font: placed.font,
                                  subpixelVariant: placed.key.subpixelVariant,
                                  scaleFactor: placed.key.scaleFactor)
        }
    }
    #endif

    /// Emits one glyph the frame's ``textSystem`` placed, rasterized by that
    /// system on an atlas miss (ruling TS-A).
    func draw(_ glyph: TextGlyph, color: Hsla) {
        drawSprite(key: glyph.key, pixelX: glyph.pixelX, baselineY: glyph.baselineY, color: color) {
            textSystem.rasterize(glyph.key)
        }
    }

    /// The sprite arithmetic both `draw`s share: atlas lookup, then the
    /// bitmap's bearings, the active offset (scaled), clip, radii, opacity and
    /// layer. One copy, so the two engines' glyphs cannot drift apart here.
    private func drawSprite(key: GlyphKey, pixelX: Int, baselineY: Int, color: Hsla,
                            rasterize: () -> GlyphImage) {
        guard let packed = glyphAtlas.packed(for: key, rasterize: rasterize) else { return }
        guard packed.slot.width > 0, packed.slot.height > 0 else { return }

        let bounds = Bounds(
            origin: Point(x: ScaledPixels(Float(pixelX + packed.left)),
                          y: ScaledPixels(Float(baselineY - packed.top))),
            size: Size(width: ScaledPixels(Float(packed.slot.width)),
                       height: ScaledPixels(Float(packed.slot.height))))
        let dx = activeOffset.x.value * scaleFactor
        let dy = activeOffset.y.value * scaleFactor
        let placedBounds = Bounds(
            origin: Point(x: ScaledPixels(bounds.origin.x.value + dx),
                          y: ScaledPixels(bounds.origin.y.value + dy)),
            size: bounds.size)
        let glyph = MUIGlyph(bounds: placedBounds, slot: packed.slot,
                             contentMask: activeClip.scaled(by: scaleFactor),
                             maskCornerRadii: activeClipRadii.scaled(by: scaleFactor),
                             color: Hsla(h: color.h, s: color.s, l: color.l,
                                         a: color.a * activeOpacity), order: 0)
        if paintScopes.isEmpty {
            scene.insert(glyph, layer: activeLayer)
        } else {
            insertThroughScopes(.glyph(glyph, layer: activeLayer, innerMask: false))
        }
    }

    // MARK: - Transitions (plan task 13, lane 3, ruling `AN-AE`/`AN-AK`)

    /// The paint scopes open now, innermost last (ruling `GX-G`, generalizing
    /// plan task 13's transition stack): a CLAIMED `TransitionGroup`'s, a
    /// render effect's, a drag source's capture, a `Deferred`'s barrier.
    /// **Empty in every frame of a tree without `.transition`, an effect or an
    /// open drag**, and the emitters above then insert exactly as they always
    /// did: nothing they compute passes through here.
    var paintScopes: [PaintScope] = []

    // MARK: - The drag preview (drag and drop, lane 2, ruling `DN-J`)

    /// The open drag session's source, set by `Window` before `render` —
    /// `nil` in every frame without a session, so nothing below runs.
    var dragSourceID: GlobalElementID?

    /// The open in-window menu's levels, root first, handed in by `Window`
    /// before it renders (menus, `MN-F` item 2); empty with none open, so a
    /// frame without a menu paints nothing more.
    var menuPanelLevels: [MenuSession.Level] = []

    /// How many menu rows this frame painted — O(visible) per level (`SV-Q`),
    /// read back through `Window.lastMenuRowsPainted`.
    var menuRowsPainted = 0

    /// Each menu picker's widest option title (`SV-AA`): the window's
    /// long-lived cache, handed in before the build; a fresh one otherwise.
    var pickerTitleWidths = PickerTitleWidths()

    /// The drawn alert, handed in by `Window` before it renders (platform
    /// services, `SV-J` item 2); `nil` with none up, so a frame without one
    /// paints nothing more.
    var alertPanel: DrawnAlertPanel?

    /// Runs `body` with `layer` as the active paint layer — the in-window
    /// menu's, above every layer the frame used (`MN-F` item 2). Opens no
    /// accessibility portal: the menu publishes through `Window`, not records.
    func withPaintLayer(_ layer: Int, _ body: () -> Void) {
        layerStack.append(layer)
        defer { layerStack.removeLast() }
        body()
    }

    /// `pointer − press point`, in points: how far the snapshot is replayed
    /// from where the source painted it (`DN-J` item 1).
    var dragPreviewTranslation = Point(x: Pixels(0), y: Pixels(0))

    /// Where a `draggable(_:preview:)` preview's top-left goes, in window
    /// points: the pointer less the press point's offset into the source.
    var dragPreviewOrigin = Point(x: Pixels(0), y: Pixels(0))

    /// The session's last snapshot, handed in by `Window`: replayed when the
    /// source paints nothing this frame (`DN-H` item 4).
    var previousDragSnapshot: [CapturedPrimitive] = []

    /// What the source painted this frame, captured — `nil` when it did not
    /// paint. `Window` keeps it on the session.
    var dragSnapshot: [CapturedPrimitive]?

    /// How many primitives this frame captured for a drag preview (2.14).
    var dragCapturedPrimitives = 0

    /// Render-effect scopes pushed this frame, prepaint and paint together — a
    /// work counter (ruling `GX-G`, test 2.21): 0 for a tree with no
    /// `rotationEffect`, `scaleEffect` or `offset`.
    var effectScopesPushed = 0

    /// `GX-P` item 1: every enclosing wrapper registered at exactly `rect` —
    /// innermost first, stopping at the first that is not — gets the
    /// innermost open effect's map: its hitboxes the inverse and their own
    /// clip as the outer clip, its accessibility records the bounding box.
    ///
    /// Only candidates at or above `floor` are reachable (`GX-U`): the share
    /// floor the effect's own element (the modifier chain carrying the effect
    /// layer, or the legacy element) entered at, so a candidate outside any
    /// element that is not a sharing wrapper — a `ZStack`, an overlay or
    /// background attachment, a stack, a grid, another chain's content — is
    /// not patched, whatever its rect.
    func shareWithEnclosingWrappers(at rect: Bounds<Pixels>, floor: Int) {
        guard let effect = prepaintEffects.last else { return }
        for k in shareCandidates.indices.reversed() {
            guard k >= floor else { break }
            let candidate = shareCandidates[k]
            guard candidate.rect == rect else { break }
            for entry in candidate.hitboxes {
                var hitbox = hitboxes[entry.index]
                let outerClip = hitbox.transform?.outerClip ?? entry.clip
                hitbox.bounds = entry.raw
                hitbox.transform = HitboxTransform(inverse: effect.inverse, outerClip: outerClip)
                hitboxes[entry.index] = hitbox
            }
            for index in candidate.accessibility where index < axEmissions.count {
                var geometry = axEmissions[index].geometry
                // As `accessibilityGeometry` computes it inside an effect: the
                // bounding box of the pre-effect visible rect (the rect cut by
                // the clip in force at the wrapper's registration), cut by the
                // effect's outer clip (`GX-U` item 2).
                geometry.frame = effect.composed.boundingBox(of: candidate.rect)
                geometry.visibleFrame = Self.intersect(
                    effect.outerClip,
                    effect.composed.boundingBox(of: Self.intersect(candidate.clip, candidate.rect)))
                axEmissions[index].geometry = geometry
            }
        }
    }


    /// The render effects open in prepaint, innermost last (`GX-I`).
    var prepaintEffects: [PrepaintEffect] = []

    /// Proposal wrappers whose registrations an effect at their rect may still
    /// transform, innermost last (`GX-P` item 1), and the one collecting now.
    var shareCandidates: [ShareCandidate] = []
    var shareCollecting: [ShareCandidate] = []

    /// The lowest index of `shareCandidates` an effect may still patch
    /// (`GX-U`). Every element entry raises it to the stack's count for the
    /// element's prepaint (`enteringShareBarrier`); a sharing wrapper lowers it
    /// back to `shareFloorAtEntry` for its content.
    var shareFloor = 0

    /// `shareFloor` as it stood just before the element whose prepaint is
    /// running was entered — what a transparent element passes through.
    var shareFloorAtEntry = 0

    /// `body` — one element's prepaint — behind a share barrier (`GX-U`): no
    /// candidate open outside it is reachable unless the element passes the
    /// floor through (`passingShareFloorThrough`). Pure bookkeeping: two
    /// integers saved and restored, nothing registered.
    func enteringShareBarrier<R>(_ body: () -> R) -> R {
        let saved = shareFloor
        let savedAtEntry = shareFloorAtEntry
        shareFloorAtEntry = saved
        shareFloor = shareCandidates.count
        defer {
            shareFloor = saved
            shareFloorAtEntry = savedAtEntry
        }
        return body()
    }

    /// `body` with the floor the current element entered at (`GX-U`): what a
    /// sharing wrapper (`GX-P` item 1's list) does for its content, so a
    /// candidate outside it stays reachable through it.
    func passingShareFloorThrough<R>(_ body: () -> R) -> R {
        let saved = shareFloor
        shareFloor = shareFloorAtEntry
        defer { shareFloor = saved }
        return body()
    }

    /// How many clips are pushed — a transitioning group's entry depth, so a
    /// primitive can tell a clip set inside the group (which moves and scales
    /// with it) from the one in effect where the group starts (which stays).
    var clipDepth: Int { clipStack.count }

    /// One emitted primitive through every open transitioning group, innermost
    /// first: each captures it as it arrives (for a ghost), then applies its
    /// effect, and the result reaches the scene.
    private func insertThroughScopes(_ primitive: CapturedPrimitive) {
        // Inside a text draw (`beginLeafGroup`), the glyphs wait for the
        // group's end, so a shadow scope sees the whole text as one leaf.
        if leafGroup != nil {
            leafGroup!.append(primitive)
            return
        }
        insertThroughScopes(leaf: [primitive])
    }

    /// One leaf — a primitive, or one text draw's glyphs — through every open
    /// paint scope, innermost first: each captures what arrives (for a ghost or
    /// a drag preview) and applies its map; a shadow scope puts the leaf's
    /// shadow before it, itself a leaf to every scope further out (`GX-J`;
    /// SH5, SH11). What survives reaches the scene in order.
    private func insertThroughScopes(leaf: [CapturedPrimitive]) {
        var leaves: [[CapturedPrimitive]] = [leaf]
        let depth = clipStack.count
        var pastBarrier = false
        for scope in paintScopes.reversed() {
            switch scope.kind {
            case .barrier:
                pastBarrier = true
                continue
            case .effect where pastBarrier, .shadow where pastBarrier:
                continue   // a `Deferred`'s content is not transformed or shadowed (`GX-G`)
            default:
                break
            }
            var next: [[CapturedPrimitive]] = []
            for var group in leaves {
                for i in group.indices {
                    group[i].innerMask = group[i].maskDepth(emittedAt: depth) > scope.entryClipDepth
                    group[i].outerMaskInner = group[i].transform.map { $0.outerDepth > scope.entryClipDepth } ?? false
                }
                if scope.capturing { scope.captures.append(contentsOf: group) }
                if let shadow = scope.shadow {
                    next.append([shadowItem(of: group, shadow, entryDepth: scope.entryClipDepth)])
                    next.append(group)
                    continue
                }
                if !scope.effect.isIdentity {
                    group = group.compactMap {
                        scope.effect.apply(to: $0, flattens: scope.flattens, outer: scope.outer)
                    }
                    if group.isEmpty { continue }
                }
                if scope.kind == .effect, scope.flattens, let entry = scope.outer {
                    for i in group.indices { group[i] = Self.cutToEntryClip(group[i], entry) }
                }
                next.append(group)
            }
            leaves = next
        }
        for group in leaves {
            for primitive in group { insertIntoScene(primitive) }
        }
    }

    /// `primitive` after a flattening effect mapped it (`GX-X`, the LF-a fix):
    /// a mask pushed inside the scope — its own (`innerMask`), or its
    /// transform's outer mask (`outerMaskInner`) — cut by `entry`, the clip in
    /// force at the scope's entry, in the space the scope maps into. Any other
    /// mask was read at or outside the entry and already is that clip.
    private static func cutToEntryClip(_ primitive: CapturedPrimitive, _ entry: OuterMask) -> CapturedPrimitive {
        func cut(_ mask: MUIBounds, _ radii: MUICorners) -> (MUIBounds, MUICorners) {
            func bounds(_ b: MUIBounds) -> Bounds<Pixels> {
                Bounds(origin: Point(x: Pixels(b.origin.x), y: Pixels(b.origin.y)),
                       size: Size(width: Pixels(b.size.width), height: Pixels(b.size.height)))
            }
            func corners(_ c: MUICorners) -> Corners<Pixels> {
                Corners(topLeft: Pixels(c.topLeft), topRight: Pixels(c.topRight),
                        bottomRight: Pixels(c.bottomRight), bottomLeft: Pixels(c.bottomLeft))
            }
            let (b, r) = intersect(bounds(entry.bounds), radii: corners(entry.radii), bounds(mask), radii: corners(radii))
            return (MUIBounds(origin: MUIPoint(x: b.origin.x.value, y: b.origin.y.value),
                              size: MUISize(width: b.size.width.value, height: b.size.height.value)),
                    MUICorners(topLeft: r.topLeft.value, topRight: r.topRight.value,
                               bottomRight: r.bottomRight.value, bottomLeft: r.bottomLeft.value))
        }
        var p = primitive
        if var t = p.transform {
            guard p.outerMaskInner else { return p }
            (t.outerMask, t.outerMaskRadii) = cut(t.outerMask, t.outerMaskRadii)
            p.transform = t
            return p
        }
        guard p.innerMask else { return p }
        switch p.kind {
        case .rect(var r):
            (r.contentMask, r.maskCornerRadii) = cut(r.contentMask, r.maskCornerRadii)
            p.kind = .rect(r)
        case .glyph(var g):
            (g.contentMask, g.maskCornerRadii) = cut(g.contentMask, g.maskCornerRadii)
            p.kind = .glyph(g)
        case .image(var i, let texture):
            (i.contentMask, i.maskCornerRadii) = cut(i.contentMask, i.maskCornerRadii)
            p.kind = .image(i, texture: texture)
        case .surface(var q, let target):
            (q.contentMask, q.maskCornerRadii) = cut(q.contentMask, q.maskCornerRadii)
            p.kind = .surface(q, target: target)
        case .path(var path):
            (path.contentMask, path.maskCornerRadii) = cut(path.contentMask, path.maskCornerRadii)
            p.kind = .path(path)
        case .shadow(var shadow):
            (shadow.contentMask, shadow.maskCornerRadii) = cut(shadow.contentMask, shadow.maskCornerRadii)
            p.kind = .shadow(shadow)
        }
        return p
    }

    /// The shadow of `leaf` under a shadow scope (`GX-J`), in the space the
    /// leaf reached it in.
    private func shadowItem(of leaf: [CapturedPrimitive], _ shadow: PaintScope.Shadow,
                            entryDepth: Int) -> CapturedPrimitive {
        let paint = ShadowPaint(leaf: leaf, color: shadow.color, radius: shadow.radius, dx: shadow.dx,
                                dy: shadow.dy, local: .identity, contentMask: shadow.mask,
                                maskCornerRadii: shadow.radii, entryDepth: entryDepth)
        return CapturedPrimitive(kind: .shadow(paint), layer: leaf.first?.layer ?? activeLayer, innerMask: false)
    }

    /// Inserts a processed primitive, with its transform record when it has
    /// one (`GX-F`); `nil` writes index 0. A path or a shadow is rasterized
    /// here, in device pixels, into one untransformed image (`GX-B`, `GX-J`).
    func insertIntoScene(_ primitive: CapturedPrimitive) {
        let transform = primitive.transform?.record
        switch primitive.kind {
        case .rect(let rect): scene.insert(rect, layer: primitive.layer, transform: transform)
        case .glyph(let glyph): scene.insert(glyph, layer: primitive.layer, transform: transform)
        case .image(let image, let texture):
            scene.insert(image, texture: texture, layer: primitive.layer, transform: transform)
        case .surface(let quad, let target):
            scene.insert(quad, surface: target, layer: primitive.layer, transform: transform)
        case .path(let paint):
            guard let (quad, texture) = pathImage(paint, transform: primitive.transform) else { return }
            scene.insert(quad, texture: texture, layer: primitive.layer)
        case .shadow(let paint):
            guard let (quad, texture) = shadowImage(paint, transform: primitive.transform) else { return }
            scene.insert(quad, texture: texture, layer: primitive.layer)
        }
    }

    /// The glyphs of the text draw in progress, while a paint scope is open —
    /// `nil` otherwise (`GX-J`: a text draw is one leaf, SH4/SH5e).
    var leafGroup: [CapturedPrimitive]?

    /// Opens a text draw's leaf group; nothing when no paint scope is open
    /// (the emitters then insert directly, as they always did).
    func beginLeafGroup() {
        leafGroup = paintScopes.isEmpty ? nil : []
    }

    /// Sends the group's glyphs through the scopes as one leaf.
    func endLeafGroup() {
        guard let group = leafGroup else { return }
        leafGroup = nil
        if !group.isEmpty { insertThroughScopes(leaf: group) }
    }

    /// Emits a path (`GX-B`): `path`'s points (window points, before the scroll
    /// translation) filled or stroked in `color`, under the active offset,
    /// clip, opacity and layer, as `fill` places a rect. It stays a vector
    /// through the paint scopes and is rasterized in the scene's device pixels
    /// at `insertIntoScene`.
    func drawPath(_ path: Path, mode: PathPaint.Mode, color: Hsla) {
        guard !path.isEmpty, color.a > 0 else { return }
        let s = Double(scaleFactor)
        let local = Affine2D(a: s, d: s, tx: Double(activeOffset.x.value) * s, ty: Double(activeOffset.y.value) * s)
        let paint = PathPaint(geometry: path.storage, mode: mode, local: local,
                              color: Hsla(h: color.h, s: color.s, l: color.l, a: color.a * activeOpacity),
                              contentMask: MUIBounds(activeClip.scaled(by: scaleFactor)),
                              maskCornerRadii: MUICorners(activeClipRadii.scaled(by: scaleFactor)))
        let primitive = CapturedPrimitive(kind: .path(paint), layer: activeLayer, innerMask: false)
        if paintScopes.isEmpty {
            insertIntoScene(primitive)
        } else {
            insertThroughScopes(primitive)
        }
    }

    /// Paint inside a shadow scope (`GX-J`): every leaf emitted in `body` gets
    /// its own shadow just before it. `radius`, `x` and `y` in points; the clip
    /// in force cuts the shadow, clips pushed inside shape the silhouette.
    func paintWithShadow(color: Hsla, radius: Pixels, x: Pixels, y: Pixels, _ body: () -> Void) {
        let s = Double(scaleFactor)
        let shadow = PaintScope.Shadow(color: color, radius: max(0, Double(radius.value)) * s,
                                       dx: Double(x.value) * s, dy: Double(y.value) * s,
                                       mask: MUIBounds(activeClip.scaled(by: scaleFactor)),
                                       radii: MUICorners(activeClipRadii.scaled(by: scaleFactor)))
        paintScopes.append(PaintScope(kind: .shadow, effect: .identity, entryClipDepth: clipDepth, shadow: shadow))
        body()
        paintScopes.removeLast()
    }

    func finalizedScene() -> Scene {
        var finalized = scene
        finalized.finalize()
        return finalized
    }

    // MARK: - Driving the three phases

    /// Walks `element` through layout, prepaint and paint, running the flex
    /// engine in between.
    ///
    /// Builds the root's `GlobalElementID` from the element's own `elementID`
    /// and hands it down, then **sweeps after the frame** (§4.3).
    ///
    /// Only the root's path is built here. Every deeper path comes from a
    /// container calling `GlobalElementID.child(of:at:name:)` through
    /// `ElementGroup`'s conformances, so a deep tree is identified all the way
    /// down **whether or not any container on the path is named** — an unnamed
    /// one contributes its own positional component instead of stopping the
    /// path. See `ElementGroup.swift` for the cursor that supplies the index.
    func render<E: Element>(_ element: inout E) {
        // A build reads each phase's own bind, never a dispatching owner's
        // occurrence (ID-O item 2, `StateDispatch.outsideDispatch`).
        StateDispatch.outsideDispatch { renderOutsideDispatch(&element) }
    }

    private func renderOutsideDispatch<E: Element>(_ element: inout E) {
        isRendering = true
        beginScrollRequests()  // `DD-G` item 3: before layout, where `ForEach` and `List` note keys
        // The root is the only id with no parent, and the only one this file
        // builds. `at: 0` is not inert: an unnamed root element takes
        // `.positional(0)`, which is what gives a `Row { … }` rendered straight
        // into a frame an identity for its children to hang from. A named root
        // takes `.named` instead — the constructor decides, here as everywhere.
        let rootID = GlobalElementID.child(of: nil, at: 0, name: element.elementID)
        stateTable.noteNamed(rootID, at: 0)  // `ID-R`: a renamed root departs its old name

        // `Frame.render` calls the root's `requestLayout` directly rather than
        // through `ElementGroup`'s default `requestGroupLayout` — that method
        // never runs for the root at all — so this is a second, independent
        // seeding site. A root element with `@State` would otherwise never be
        // bound to a table or an id.
        StateBinder.bind(element, in: self, id: rootID)

        // Unlike the atlas's bracket below, this one wraps layout as well as
        // paint: a `Text`'s measurement shapes during layout
        // and `Text.paint` shapes again at the box's final rounded width, and
        // `ShapingCache.endFrame()`'s sweep must see both touches as this
        // frame's before it can tell them from stale ones. See
        // `ShapingCache.beginFrame()`'s own doc comment.
        textSystem.beginFrame()
        animationStore.beginFrame()
        animationStore.rasters.beginFrame()

        var layoutPass = LayoutPass(frame: self)
        let (root, layoutState) = element.requestLayout(rootID, pass: &layoutPass)
        var state = layoutState
        reportUnconsumedLoweredItems(root: root)
        // The drawn toolbar strip (`MD-K`): requested after the root, whose
        // layout collected the toolbar; `nil` — no node — without one.
        var strip = requestToolbarStrip(pass: &layoutPass)
        if let strip { reportUnconsumedLoweredItems(root: strip.node) }
        drewToolbarStrip = strip != nil

        computeRootLayout(root: root, toolbarStrip: strip?.node)
        animationStore.transitions.afterLayout(self)  // plan task 13's transition seam (AN-AE)
        let rootBounds = bounds(of: root)
        recordElementBounds(rootID, rootBounds)
        let stripBounds = strip.map { bounds(of: $0.node) }
        if let stripBounds { recordElementBounds(ToolbarStrip.rootID, stripBounds) }

        var prepaintPass = PrepaintPass(frame: self)
        // The root's `prepaint` is called here, not through `prepaintGroup`, so
        // `Element.prepaintGroup`'s `display: none` check cannot reach it: a
        // hidden root still prepaints (`hidden()` filters layout only), and
        // without this every record inside it would publish (ruling AB-AD,
        // `aHiddenRootPublishesNothing`). Accessibility only, as there.
        //
        // Since stage 6b (`LR-DH`) the check reads `isHidden` — a lowered hidden
        // root is native and carries no style — and a root in `hiddenNodes` also
        // prepaints under the pointer-disable scope and skips its paint below, the
        // two gates `Element`'s group defaults apply to every other element.
        var prepaintState = disablingHitTestingIfHidden(root) {
            collectsAccessibility && isHidden(root)
                ? withAccessibilitySuppressed(except: nil) {
                    element.prepaint(rootID, bounds: rootBounds, layout: &state, pass: &prepaintPass)
                }
                : element.prepaint(rootID, bounds: rootBounds, layout: &state, pass: &prepaintPass)
        }
        // The strip after the root (`MD-K` item 4): its hitboxes rank above
        // the root's on the base layer (presentation roots are hoisted above
        // both), its focus stops follow the root's, its records come after.
        if let stripBounds {
            strip?.element.prepaint(ToolbarStrip.rootID, bounds: stripBounds, pass: &prepaintPass)
        }

        // Hover resolves HERE — after `prepaint` has returned, so every
        // hitbox the frame will ever have is already registered, and before
        // `paint` runs, so `PaintPass.isHovered(_:)` has no one-frame lag
        // (design spec §3.3). See `resolveHover(at:)`'s own doc for why this
        // must not move to either side of this call.
        resolveHover(at: mousePosition)

        // Focus resolves HERE too, and for the same reason one phase later
        // would be wrong: `paint` must not draw a focus ring for an element
        // this frame has already decided is not focused. See `resolveFocus()`.
        resolveFocus()

        // The atlas's frame brackets go around the paint phase and nothing
        // else, because scene construction is the whole of what they protect:
        // `GlyphAtlas.evictUnusedSince` traps while a frame is being built, so
        // that a glyph this scene still holds an `AtlasSlot` for cannot be
        // dropped underneath it (spec §3.5). They also stamp every slot handed
        // out here with this frame's generation, which is what eviction reads.
        //
        // **Not a `defer`, and the reason is a mechanism rather than taste.**
        // The only way `paint` fails to reach `endFrame` is a Swift trap, and a
        // trap aborts the process — there is no later frame to be left with
        // `isBuildingFrame` still true. A `defer` here would be insurance
        // against a case that cannot occur, and would additionally hold the
        // bracket open across `stateTable.sweep()` below, which is not scene
        // construction.
        glyphAtlas.beginFrame()
        var paintPass = PaintPass(frame: self)
        if !hiddenNodes.contains(root) {
            element.paint(rootID, bounds: rootBounds,
                          layout: &state, prepaint: &prepaintState, pass: &paintPass)
        }
        animationStore.transitions.paintGhosts(&paintPass)
        if let stripBounds {   // above the root's content and its ghosts, below presentations (`MD-K` item 4)
            strip?.element.paint(ToolbarStrip.rootID, bounds: stripBounds, pass: &paintPass)
        }
        paintDragPreview()  // drag and drop's preview, above everything (DN-J)
        paintMenuPanel()  // an open in-window menu, above the preview (MN-F item 2)
        paintTooltip()  // a tooltip, above everything (MN-P item 2)
        paintAlertPanel()  // the drawn alert, above the menu and the tooltip (SV-J item 2)
        glyphAtlas.endFrame()
        textSystem.endFrame()
        applyScrollResolutions()
        animationStore.transitions.endFrame()
        animationStore.endFrame()  // drops every entry this frame did not touch (AN-AB)
        animationStore.rasters.endFrame()  // drops every raster this frame did not draw (GX-K)
        surfaceRegistry.endFrame()  // drops every surface this frame did not paint (MV-E)

        // After the frame, not before — but **not for the reason it is tempting
        // to write down.** Sweeping first does *not* discard everything the
        // previous frame established: `marked` is cleared only inside `sweep()`,
        // so a sweep at frame start still sees the previous frame's marks. The
        // real cost of that ordering is a **one-frame LIVENESS lag** — an
        // element that stops being produced reports `isLive == true` for one
        // extra frame. (Before the tombstones milestone this was a one-frame
        // *eviction* lag — the entry's whole value stayed an extra frame — but
        // `sweep()` no longer evicts anything, so the wrong ordering now only
        // delays the `isLive` flag, not the value.) Witnessed by
        // `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`
        // (`StateTableTests.swift`, formerly `…IsSweptByTheNextFrame`), which
        // is this ordering's own dedicated pin, through its `isLive`
        // assertions — `peek`/`count` no longer discriminate the mutation at
        // all, because nothing `sweep()` does is deletion any more.
        //
        // **Not the only test that reddens, and this was measured rather than
        // assumed after a review caught the stale claim.** Moving this call
        // to right after `StateBinder.bind` above reddens 3, not 1:
        // the pin above, plus `flippingAnEitherBranchResetsTheBranchesState`
        // and `anElementAfterAVanishingIfAdoptsTheVanishedElementsState` (renamed
        // `anElementAfterAVanishingIfKeepsItsOwnState` by plan task 8, whose
        // `ID-C` deletes the entries these `isLive` lines read — re-measure
        // before relying on this count)
        // (`IdentityTests.swift`). Both are two-frame `IdentityTests` cases
        // whose tombstones-milestone inversion added an `isLive` assertion on
        // an abandoned branch's entry — the same one-frame liveness lag this
        // ordering pin exists for, reached incidentally rather than by design.
        // They are not a second ordering guard: nothing about their own
        // purpose (branch state resets rather than carries; a vacated slot is
        // not "reserved") depends on sweep ordering, and a future edit should
        // not preserve their `isLive` lines *for* this reason.
        // The sweep keeps what it resets only when the last build held an
        // `onDisappear` that may read it (ruling `LC-I` item 1).
        stateTable.retainsDepartedValues = animationStore.lifecycle.hasDisappearActions
        stateTable.sweep()
        // **Focus leaves with its identity** (plan task 12 part 1, ruling
        // `IX-I`; probe arms F1, F2): when this frame's sweep reset the focused
        // element's `$focus` slot — an `if` removed it, a `.id` departed, a loop
        // dropped it — focus clears in THIS frame, so `Window`'s read-back never
        // hands the next input event a dead id and the next frame's
        // `resolveFocus` finds nothing to retain. Not a reap (`resetFocusSlots`'s
        // own doc): a `List` row out of its window keeps `TB-J`'s retention.
        if let focused = focusedElement,
           stateTable.resetFocusSlots.contains(Self.focusRetentionSlot(for: focused)) {
            focusedElement = nil
        }
        // The lifecycle's build closes AFTER the sweep (ruling `LC-E` item 1):
        // its disappearances read the values the sweep reset (`LC-I`), and its
        // parked ones the ghosts `paintGhosts` left alive (`LC-H`). Nothing
        // runs here — the window runs the events after the build.
        animationStore.lifecycle.endFrame(liveGhosts: animationStore.transitions.liveGhosts,
                                          departed: stateTable.takeDepartedState())
        isRendering = false
    }
}

extension Size where Unit == Pixels {
    func scaled(by factor: Float) -> Size<ScaledPixels> {
        Size<ScaledPixels>(width: width.scaled(by: factor), height: height.scaled(by: factor))
    }
}

extension Corners where Unit == Pixels {
    func scaled(by factor: Float) -> Corners<ScaledPixels> {
        Corners<ScaledPixels>(
            topLeft: topLeft.scaled(by: factor), topRight: topRight.scaled(by: factor),
            bottomRight: bottomRight.scaled(by: factor), bottomLeft: bottomLeft.scaled(by: factor))
    }
}

extension Bounds where Unit == Pixels {
    /// Logical points to the render target's space. Every component is scaled,
    /// including the origin — scaling the size alone leaves everything but the
    /// top-left element in the wrong place on a Retina display.
    func scaled(by factor: Float) -> Bounds<ScaledPixels> {
        Bounds<ScaledPixels>(
            origin: Point(x: origin.x.scaled(by: factor), y: origin.y.scaled(by: factor)),
            size: size.scaled(by: factor))
    }
}
