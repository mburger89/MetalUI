import MetalUICore

/// Cross-frame state, keyed by `GlobalElementID`, marked on access and swept
/// after each frame (spec §4.3).
///
/// ## Read this first: the table is keyed by SLOT, not by element
///
/// **Three separate implementers on the tombstones milestone independently
/// re-derived this fact from the source, and the design spec's own §5 was
/// written against the wrong version of it — so it is stated here rather than
/// left to be rediscovered a fourth time.** The key type is
/// `GlobalElementID`, which reads as "an element's id"; what is actually
/// stored under it is a **slot**, and every slot this framework mints is a
/// *child* of the owning element's id:
///
/// - `@State` slot *n* → `.child(of: elementID, at: n, name: "$state\(n)")`
///   (`State.swift`, `StateBinder.bind`)
/// - focus retention → `.child(of: elementID, at: 0, name: "$focus")`
///   (`Frame.focusRetentionSlot(for:)`)
/// - AX retention → `.child(of: elementID, at: 0, name: "$ax")`
///   (`Frame.axRetentionSlot(for:)`)
///
/// **The consequence that keeps catching people: an element with no `@State`
/// and no retention slot has NOTHING in this table at all.** So "look up the
/// element's own id and see whether it is still retained" — which is what
/// design spec §5 told `resolveFocus()` to do — is unanswerable for most of
/// the elements the rule is about, and cannot be fixed by trying harder at
/// the lookup. It is fixed by *writing a slot*, which is what `$focus` and
/// `$ax` are.
///
/// **The one exception, and it is the reason the two retention slots are
/// children rather than the id itself.** `ScrollView` really does key on the
/// element's own bare id — `pass.withState(id, initial: ScrollState())`, four
/// sites in `ScrollView.swift`, plus `Window.applyScroll`. A retention slot
/// written at `id` would land on that entry and, being a different type,
/// silently clobber it (see `write`'s own doc on mismatched types). A child
/// id can never equal its parent: `GlobalElementID.==` walks both parent
/// chains to `nil` and a child has one more component, so the walk cannot
/// terminate equal. That is structural, not a convention.
///
/// **All three slot names are reserved, none is guarded, and they are
/// recorded together on purpose.** A hand-written `.id("$state0")`,
/// `.id("$focus")` or `.id("$ax")` on the right child collides with the
/// corresponding slot, silently and with no diagnostic — design spec §8 risk
/// 1, which named only the first of the three. Guarding one alone would leave
/// one namespace defended and two open, which reads as though the other two
/// were safe.
///
/// **And as of this milestone the risk is no longer only an AUTHOR typing one
/// — a `List`'s DATA can supply it, which is a different threat model.** A
/// row's wrapping `Box` is `.child(of: listID, at: 0, name:
/// String(describing: datum.id))` and the `List`'s own AX retention slot is
/// `.child(of: listID, at: 0, name: "$ax")`, so a datum whose id describes to
/// `"$ax"` mints the identical `GlobalElementID`. `List`'s own doc already
/// records `String(describing:)` non-injectivity as a real unguarded gap; what
/// widens here is that the colliding string now comes from a caller's data
/// rather than from a literal in their source, where nobody is looking for it.
/// **No live clobber today** — nothing stores state under a bare row-`Box` id,
/// and the row's own `$focus`/`$state0` slots are children of it and so remain
/// distinct — which is why this is recorded rather than guarded, on the same
/// footing as the three names above.
///
/// What *is* pinned is that the three cannot collide with each
/// other: `theSevenRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift`,
/// named `theThreeRetentionSlotsAreMutuallyDistinct` until the animation
/// milestone's Task 3 extended it to a fourth slot (`$anim`), Task 4's
/// own fix round extended it again to a sixth (`$anim-content`,
/// `$anim-viewport` — `ScrollView`'s own two extra reserved names), and
/// Task 4b to a seventh (`$anim-color`, `AnimatedColor.swift`)),
/// written because renaming `"$ax"` to `"$focus"` reddened **0 of 777 tests**
/// — measured at that suite size, before the pin itself was added, so the
/// number dates the claim rather than decorating it — while silently
/// dropping focus. (Dated on review: a bare "reddened nothing" reads as
/// timeless, which is ruling `TB-AA` applied to a line written by the task
/// that carried `TB-AA` into the practices doc. What the mutation costs, and
/// why it is invisible: the `AXNode` clobbers the `Bool` at the shared slot,
/// `resolveFocus`'s `peek(…, as: Bool.self)` returns `nil`, and focus is
/// dropped with nothing able to see it.)
///
/// **This dictionary plus mark-sweep IS the entire reconciliation story.** There
/// is no diffing anywhere in this framework and there is not meant to be: §4.1
/// rejects the retained-tree model outright, on the grounds that a reconciler —
/// identity, keys, state migration — is where the nastiest framework bugs live.
/// If a future change starts comparing trees, it is departing from §4.1, not
/// optimising it.
///
/// What lives here is state that must survive a rebuild and cannot be recomputed
/// from the element values: scroll offset, hover, animation progress, text
/// selection, an in-progress drag, `MetalView` render targets (§7.7). What does
/// *not* live here is anything `Frame` owns — that is per-frame and dies with it.
/// The two are deliberately different objects so the distinction stays visible.
///
/// ## Two consequences the sweep forces
///
/// Both are load-bearing elsewhere in the spec, so they are recorded here, at
/// the sweep, rather than in the section that will eventually depend on them.
///
/// **Accessibility identity rides this table (§9).** AX clients retain element
/// references *across* frames, so `GlobalElementID` is the only structure that
/// can back stable AX identity. A node an AX client still holds must therefore
/// survive the sweep as a **tombstone that reports itself invalid**, rather than
/// vanishing.
///
/// **Both halves of that mechanism are here now.** `sweep()` no longer removes
/// unmarked entries on the spot — every `Entry` retains its `value` past the
/// frame that stopped producing it, and `isLive` reports whether the element
/// that owns it was produced by the most recent frame. `isLive(_:)` is the
/// validity flag AX will read. What bounds the tombstone's lifetime is
/// **reaping**: once `storage.count` exceeds `sweepThreshold`, `sweep()` also
/// drops entries that are both unmarked and more than `staleAfterGenerations`
/// behind — see `staleAfterGenerations` and `sweepThreshold` for why those two
/// numbers are sized against the cold frame (ruling MP-I) rather than the
/// steady state a windowed `List` leaves behind.
///
/// **CLAUDE.md's divergences 12 and 17 are retired on the strength of this,
/// and they are retired as BOUNDED closures — the wording is part of the
/// claim** (ruling `TB-AH`, design spec §3 and §8 risk 2). A windowed `List`
/// row scrolled out and back within `staleAfterGenerations` (**2**)
/// generations keeps its `@State` (was 12) and keeps its focus (was 17); an
/// excursion of three generations keeps neither, and the reap that takes them
/// engages only once `storage.count` exceeds `sweepThreshold` (**256**), so
/// below that a tombstone is retained indefinitely. "Fixed" and "fixed for N
/// generations" are different claims and the second is the true one; anywhere
/// this closure is cited it is cited with the bound attached.
///
/// **Exit transitions are now POSSIBLE and UNBUILT, which is a different claim
/// from the "impossible until that mechanism exists" this doc used to carry**
/// (spec §4.3). The blocking mechanism — state that outlives the frame that
/// stopped producing its element — is here. What is missing is a *distinction*
/// nothing yet draws: "gone, keep animating out" against "gone, ordinary
/// tombstone". That is a future task's design decision, not a prerequisite
/// this type is waiting on. An element that stops being produced no longer
/// loses its state on that very frame; nothing here uses that survival for
/// anything yet.
@MainActor
final class StateTable {
    /// One entry's storage. `isLive` and `lastSeenGeneration` are what let an
    /// entry outlive the frame that produced it: `value` is never dropped by
    /// `sweep()`, only re-marked. See `StateTable`'s own doc for what that
    /// buys and what it still does not.
    private struct Entry {
        var value: Any
        var lastSeenGeneration: UInt64
        var isLive: Bool
    }

    private var storage: [GlobalElementID: Entry] = [:]
    private var marked: Set<GlobalElementID> = []

    /// Advanced by `sweep()`, once per frame. An entry's `lastSeenGeneration`
    /// is compared against this to decide staleness.
    private(set) var generation: UInt64 = 0

    /// How many times one `State.Box` was bound to two different slots inside
    /// one generation — i.e. how many times one element VALUE was placed more
    /// than once in a tree. A test observable; nothing in production reads it.
    /// See `State.bind(to:id:slot:)` for why this is counted and not trapped.
    private(set) var aliasedStateBoxes = 0

    func noteAliasedStateBox() { aliasedStateBoxes += 1 }

    // MARK: Evaluated removal (plan task 8, ruling `ID-C`)

    /// Every conditional slot noted produced by the frame being built: an
    /// `OptionalGroup`'s own slot while it has content, an `EitherGroup`'s taken
    /// branch id. Swapped into `previouslyProducedSlots` by `sweep()`.
    private var producedSlots: Set<GlobalElementID> = []

    /// `producedSlots` as the last COMPLETED frame (`Frame.render`'s sweep) left
    /// it. `noteAbsent` resets a slot only when it is here — the transition from
    /// produced to evaluated-and-absent, never the steady absent state.
    private var previouslyProducedSlots: Set<GlobalElementID> = []

    /// How many times `noteAbsent` scanned the table: once per produced → absent
    /// transition, never per absent frame. A work counter (spec C2.9); nothing in
    /// production reads it.
    private(set) var subtreeResetScans = 0

    /// A conditional slot produced its content this frame.
    func noteProduced(_ slot: GlobalElementID) {
        producedSlots.insert(slot)
    }

    /// A conditional slot was EVALUATED and produced nothing this frame — an
    /// `if` whose condition is false, the branch of an `if`/`else` not taken.
    ///
    /// **Resets only on the transition**: when the last completed frame produced
    /// `slot`, every entry whose id has `slot` as a proper ancestor is deleted,
    /// so content that returns starts fresh (SwiftUI's lifetime rule, probe
    /// V5/V9; ruling `ID-C`). **Two retention slots are exempt** — an entry whose
    /// own component is `.named("$focus")` or `.named("$ax")` — because their
    /// lifetime is the window's (focus retention, the accessibility node's
    /// republish; `TB-J`, `AB-U`), not the element's. **Only an evaluated
    /// conditional calls this**: a subtree nothing evaluates (a `List` row out of
    /// the window) keeps `TB-AH`'s retention, and `sweep()` never resets a
    /// conditional slot (it resets only a departed NAME, `noteNamed`).
    func noteAbsent(_ slot: GlobalElementID) {
        // `remove`, not `contains`: a second note in the same frame (a slot
        // evaluated twice before a sweep) finds nothing and scans nothing.
        guard previouslyProducedSlots.remove(slot) != nil else { return }
        subtreeResetScans += 1
        resetEntries(under: slot, includingRoot: false)
    }

    // MARK: A name that returns (the closeout, ruling `ID-R`)

    /// One structural position a name can sit at: the parent's id and the
    /// cursor index the named element consumed there (the index a name
    /// replaces, `GlobalElementID.child(of:at:name:)`). A plain value, so
    /// keying on it allocates nothing once the tables are warm.
    struct NamedPosition: Hashable {
        let parent: GlobalElementID?
        let index: Int
    }

    /// Which name each position held in the frame being built, and in the last
    /// COMPLETED frame (swapped by `sweep()`, as `producedSlots` is).
    private var namedPositions: [NamedPosition: GlobalElementID] = [:]
    private var previousNamedPositions: [NamedPosition: GlobalElementID] = [:]

    /// Every named id the frame being built produced, anywhere.
    private var producedNames: Set<GlobalElementID> = []

    /// Names an evaluated position held last frame and replaced this frame —
    /// the candidates `sweep()` resets unless they were produced elsewhere.
    private var departedNames: [GlobalElementID] = []

    /// Parents whose named children are a WINDOW over their data, not the
    /// data (a `List`'s rows, `ListRows`): a row's name leaving a position
    /// because the window moved is not the row going away (`TB-AH`).
    private var windowedParents: Set<GlobalElementID> = []

    /// How many names `sweep()` reset (a test observable; nothing in production
    /// reads it).
    private(set) var departedNameResets = 0

    /// `id` was just minted at cursor `index` under its parent. A no-op unless
    /// its component is `.named` — an unnamed id IS its position, so it cannot
    /// be replaced by a different one there.
    ///
    /// **When the position held a DIFFERENT name in the last completed frame,
    /// that name departs**, and `sweep()` resets it (every entry at it or
    /// under it, except `$focus`/`$ax`) **unless the frame produced it
    /// somewhere else** — a name that moved to a sibling's position (a swap, a
    /// loop reorder) keeps its state. So `.id(n)` over a, b, a starts the
    /// returning a fresh, as SwiftUI's does (probe X9–X11; ruling `ID-R`).
    /// Only an EVALUATED position replaces a name: a position nothing
    /// evaluates (an `if` that went false — its own `noteAbsent` resets it; a
    /// loop that shrank, divergence 74; anything under an element no longer
    /// produced) departs nothing here, and a `List`'s rows are exempt
    /// (`noteWindowedParent`).
    func noteNamed(_ id: GlobalElementID, at index: Int) {
        guard case .named = id.component else { return }
        if let parent = id.parent, windowedParents.contains(parent) { return }
        producedNames.insert(id)
        let position = NamedPosition(parent: id.parent, index: index)
        if let previous = previousNamedPositions[position], previous != id {
            departedNames.append(previous)
        }
        namedPositions[position] = id
    }

    /// `parent`'s named children this frame are a window over its data (a
    /// `List`'s rows): `noteNamed` ignores them, so a row scrolled out keeps
    /// `TB-AH`'s bounded retention.
    func noteWindowedParent(_ parent: GlobalElementID) {
        windowedParents.insert(parent)
    }

    /// Deletes every entry under `root` — and at `root` itself when
    /// `includingRoot` — except the window-owned retention slots. The one
    /// deletion both resets share: `noteAbsent` passes `false` (a conditional
    /// slot holds no entry of its own), a departed name `true` (a renamed
    /// element's own id carries entries too: `ScrollView`'s offset, an
    /// element's `withState(id, …)`).
    private func resetEntries(under root: GlobalElementID, includingRoot: Bool) {
        for id in storage.keys
        where ((includingRoot && id == root) || Self.descends(id, from: root)) && !Self.isWindowRetained(id) {
            storage.removeValue(forKey: id)
            marked.remove(id)
        }
    }

    /// Whether `slot` is a PROPER ancestor of `id`.
    private static func descends(_ id: GlobalElementID, from slot: GlobalElementID) -> Bool {
        var cursor = id.parent
        while let ancestor = cursor {
            if ancestor == slot { return true }
            cursor = ancestor.parent
        }
        return false
    }

    private static let focusRetentionName = PathComponent.named(ElementID("$focus"))
    private static let axRetentionName = PathComponent.named(ElementID("$ax"))

    /// `$focus` and `$ax`: the window-owned retention slots `noteAbsent` keeps.
    private static func isWindowRetained(_ id: GlobalElementID) -> Bool {
        id.component == focusRetentionName || id.component == axRetentionName
    }

    /// An entry survives being unmarked for this many generations before
    /// `sweep()` will reap it — same shape and same value as
    /// `ShapingCache.staleAfterGenerations` (`Sources/MetalUIText/ShapingCache.swift:141`),
    /// kept rather than widened: that value's own story is a grace period for
    /// a caller that touches a key on a slightly different frame than the one
    /// right before it (a windowed `List` re-touching a row it dropped one
    /// frame and picked back up the next), and a `List` row is exactly that
    /// caller here too — divergence 12/17 in CLAUDE.md are the state and
    /// focus versions of the same re-touch pattern `ShapingCache` was tuned
    /// for. There is no measurement here that argues for a different number,
    /// so this copies the constant rather than inventing one.
    static let staleAfterGenerations: UInt64 = 2

    /// The entry-count `sweep()`'s reap triggers on — a trigger, not a
    /// ceiling, on `ShapingCache.sweepThreshold`'s exact footing
    /// (`Sources/MetalUIText/ShapingCache.swift:188`): once over this, reap
    /// removes only entries that are both unmarked *and* stale, so a working
    /// set that itself exceeds this number settles above it rather than
    /// being forced under it.
    ///
    /// **Not copied from `ShapingCache` — chosen against this table's own two
    /// numbers, per the brief.** The steady state a windowed `List` leaves
    /// behind is **20** entries — **19 (the ORIGINAL measurement, on a
    /// scrolling 500-row and a scrolling 100,000-row list alike — steady
    /// state flat regardless of list size; that harness is not preserved as
    /// a runnable test and was NOT re-run this round) plus 1 (this
    /// milestone's Task 7, DIRECTLY re-measured in its fix round — see
    /// below).** Read 20 as a derivation, not a fresh measurement of the sum:
    /// the base is inherited and unverified this round, the +1 is not. The
    /// cold frame — frame 0, before a `ScrollView`'s own `prepaint` has run
    /// once (ruling MP-I) — builds every row: **100,002** on a 100k-row list,
    /// the identical derivation (100,001 inherited + 1 re-measured). **Task 7
    /// made a `List` unconditionally emit its own `AXNode`** — a permanent,
    /// every-frame-re-marked `$ax` retention slot that never goes stale, so
    /// it adds one resident entry to any windowed `List`'s steady state and
    /// one to its cold-frame peak alike. **The +1 is what Task 7's fix round
    /// actually measured**, twice, on two different harnesses: reverting the
    /// `AXNode` emission in the large-jump 10k-row suite test
    /// (`MeasurePerformanceTests.swift`) drops every figure by exactly one
    /// (10002→10001, and each of 77/127/99→76/126/98), and a separate
    /// differential steady-scroll probe (throwaway, not committed) showed the
    /// identical flat +1 under different scroll parameters — independent of
    /// scroll parameters, but not a re-derivation of 19 or 100,001
    /// themselves. `ShapingCache`'s 256 sits close to *its* measured resident
    /// set (207, ~81% of 256) on purpose, because its cost model is "an
    /// eviction that turns out to still be live re-shapes every frame
    /// forever" — thrashing near the threshold is expensive there. Nothing
    /// here re-computes a value once reaped; a reaped `@State` slot that
    /// comes back is just a fresh `initial()`, which is cheap and correct
    /// (it is what a never-produced-before element gets too). So this table
    /// has no reason to sit close to its steady state the way the cache
    /// does, and every reason not to: 20 is two orders of magnitude below
    /// 100,002, so a threshold anywhere in, say, the low thousands still
    /// reaps the cold-frame spike down to near-nothing while leaving the
    /// steady state (20) nowhere close to firing the reap on any ordinary
    /// frame. **256** would work for that alone, but this table's growth is
    /// unbounded on the number of distinct elements a session ever produces
    /// — not on a fixed viewport-driven working set the way glyph runs are —
    /// so a threshold sized only to clear 20 leaves no margin for a second,
    /// smaller list or a handful of ordinary (non-list) stateful elements
    /// coexisting with it before the sweep starts firing every frame. 256
    /// itself is kept: it is comfortably above any plausible non-list steady
    /// state this framework's own demo produces, and the cold-frame test
    /// below requires only that reaping actually runs when the table is
    /// three orders of magnitude over it — it does not require sitting close
    /// to it the way `ShapingCache` does.
    static let sweepThreshold = 256

    /// Set by `write`. **A pure test observable with no production reader —
    /// `grep -rn "isDirty" Sources/` finds the declaration, the set in
    /// `write`, the clear in `clearDirty`, and doc comments; there is no
    /// `if stateTable.isDirty` anywhere.** `Window`'s entire production
    /// mechanism is `onWrite` below, which fires unconditionally on every
    /// write and cannot be reached through this flag: `onWrite` already
    /// calls `setNeedsRedraw()` whenever `isDirty` goes true, so a
    /// hypothetical `if stateTable.isDirty { setNeedsRedraw() }` in `Window`
    /// would be unreachable dead code, not a fix. Kept anyway — this is what
    /// this task's own tests read, two of which construct no `Window` at
    /// all — and listed in CLAUDE.md's declared-but-inert table under the
    /// shape `Style.overflow` had until stage 10 deleted it (`LR-FM` item 1):
    /// a production write with no production read.
    ///
    /// **Deliberately NOT raised by `withState`.** `ScrollView`'s per-frame
    /// offset bookkeeping (`ScrollChrome.resolvedOffset`) goes through
    /// `withState` on every render, scrolled or not — if that raised this
    /// flag, every frame would mark it dirty, which would defeat the point
    /// of an observable meant to distinguish a `@State` write from routine
    /// per-frame bookkeeping. `write` is the only path in, and it exists
    /// specifically because `@State`'s setter needs a distinct one.
    private(set) var isDirty: Bool = false

    /// Fired by `write`. This is the ENTIRE production mechanism — see
    /// `isDirty`'s doc above for why a flag alone cannot be one:
    /// `Window.drawFrameIfNeeded` pauses the display link whenever the
    /// window is clean and has no reason to poll anything while paused, so a
    /// flag it merely *could* consult would stay unread for as long as the
    /// window sits idle — exactly the state a `@State` write from outside
    /// the render loop (a click handler, a completion callback) needs to
    /// escape. `Window.init` installs this pointing at its own
    /// `setNeedsRedraw()`, captured weakly: `Window` owns this table, so a
    /// strong capture here would be a retain cycle.
    var onWrite: (@MainActor () -> Void)?

    init() {}

    /// How many entries survive. Test observability; not part of the contract.
    ///
    /// `internal`, like `peek`: `StateTable` is unreachable from outside the
    /// module anyway (`Frame.stateTable` and the passes' `frame` are internal),
    /// so `public` here bought nothing and implied a supported API.
    var count: Int { storage.count }

    /// Every id holding an entry. A test observable with no production reader,
    /// on `count`'s footing: the differential harness compares two tables' ids
    /// (plan task 7, ruling LR-D).
    var ids: Set<GlobalElementID> { Set(storage.keys) }

    /// How many times `withState` has actually run its `body` and written an
    /// entry, cumulative since this table was created. Test observability, on
    /// `isDirty`'s exact footing — no production reader, `internal` for the
    /// same reason `count` is.
    ///
    /// **Added for the animation milestone's Task 3 fix round, ruling C2.**
    /// Neither `count` nor `isDirty` can see write *frequency*: `withState`
    /// overwriting an EXISTING key changes neither the dictionary's size nor
    /// `isDirty` (`withState` never sets it — see that flag's own doc for
    /// why). A caller that re-writes a settled, unchanging entry every frame
    /// — precisely what `$anim`'s Ruling I forbids — is invisible to both.
    /// This counter is what makes that frequency assertable at all.
    private(set) var writeCount: Int = 0

    /// Read-modify-write the state at `id`, creating it from `initial` on first
    /// access, and **mark it as still live**.
    ///
    /// Marking happens on access rather than on production because an element
    /// that is produced but never touches its state has nothing worth keeping —
    /// and because `Element`'s phases have no "I exist" callback separate from
    /// the work they do.
    ///
    /// **There is no longer an unidentified caller.** This took a
    /// `GlobalElementID?` and gave an anonymous element a scratch value that was
    /// discarded on return; structural identity removed the `nil` from the type,
    /// so every element that calls this has a real key and a real entry. The
    /// scratch branch is gone rather than unreachable — the mechanism is
    /// `GlobalElementID.child(of:at:name:)`'s non-optional return, which the
    /// compiler checks, not a convention a reader has to remember.
    ///
    /// **`marked` — not `write` — is what `sweep()` reads to decide who was
    /// actually produced.** `withState` and `mark` insert into it; `write`
    /// deliberately does not (see `write`'s own doc for why). **Correction to
    /// an earlier draft of this comment, caught by a review rather than by
    /// a test:** it claimed `withState` "runs only from inside a frame's own
    /// construction," which is false — `Window.applyScroll`
    /// (`Window.swift:711`) calls `stateTable.withState` directly, from raw
    /// scroll-wheel handling, entirely outside `Frame.render`. `mark`'s only
    /// path in (`StateBinder.bind`, `ElementGroup.swift:112` and
    /// `Frame.swift:896`) really is exclusively frame construction — checked
    /// by grepping every call site of `StateBinder.bind`, not assumed — but
    /// `withState` is not, so "both run only from inside a frame's own
    /// construction" overstated it for one of the two. What actually
    /// distinguishes `withState` from `write` is narrower: `withState`'s
    /// callers are a small, framework-owned set (`LayoutPass`/`PrepaintPass`/
    /// `PaintPass`'s wrappers, `ScrollView`'s own bookkeeping, and
    /// `Window.applyScroll`'s scroll-offset write) that are all tied to a
    /// scroll region's continued existence — a wheel event that reaches
    /// `applyScroll` always calls `setNeedsRedraw()` right after, so the
    /// region is about to be produced again regardless. `write` has exactly
    /// one caller (`@State`'s `wrappedValue` setter, `State.swift:64`) and
    /// says nothing at all about whether its element still exists. The
    /// single field every one of the three flips is still `Entry.isLive`,
    /// and `marked` membership is still the one thing allowed to differ
    /// between them — that part of the "one path" claim holds; only the
    /// reason given for `withState`'s half did not.
    func withState<S>(_ id: GlobalElementID,
                      initial: @autoclosure () -> S,
                      _ body: (inout S) -> Void) {
        marked.insert(id)
        var value = (storage[id]?.value as? S) ?? initial()
        body(&value)
        storage[id] = Entry(value: value, lastSeenGeneration: generation, isLive: true)
        writeCount += 1
    }

    /// Mark `id` live for this frame's sweep, without reading or creating an
    /// entry for it.
    ///
    /// `withState` marks on access because an element that never touches its
    /// state has nothing worth keeping. That rule is wrong for `@State`: a
    /// value read only inside an `if` would go unmarked on frames where the
    /// branch is not taken, and the next `sweep()` would discard it — a
    /// counter that silently resets. Declaring `@State` is sufficient intent
    /// to keep it, so `StateBinder` calls this for every slot, every frame,
    /// independent of whether that frame ever reads `wrappedValue`.
    ///
    /// **Resurrects a tombstoned entry immediately.** A tombstone's `isLive`
    /// would otherwise stay `false` until the next `sweep()` ran, and a
    /// caller that marks an entry and then reads `isLive(_:)` in the same
    /// frame — before any `sweep()` — must see it as live right away. This is
    /// the same field `withState`/`write` set via a freshly-built `Entry`;
    /// there being no existing entry to resurrect here is a no-op, not an
    /// error — `mark` is called for slots that may not have been written to
    /// yet.
    func mark(_ id: GlobalElementID) {
        marked.insert(id)
        storage[id]?.isLive = true
    }

    /// Write `value` at `id`, setting the entry live immediately, and —
    /// unlike `withState`/`mark` — raising `isDirty` and firing `onWrite`.
    ///
    /// **Deliberately does NOT join `marked`, and this is a decision this
    /// task made rather than one the brief specified — see the report.**
    /// `mark`'s only call path (`StateBinder.bind`) runs exclusively from
    /// inside a frame's own construction, so its `marked.insert` is a true
    /// "this element was produced this frame" signal. `withState` is looser
    /// — it is also called from `Window.applyScroll` in direct response to a
    /// raw scroll-wheel event, outside any frame — but every one of its
    /// callers is a small, framework-owned set tied to a scroll region's
    /// continued existence, and a wheel event that reaches `applyScroll`
    /// always triggers `setNeedsRedraw()`, so the region is about to be
    /// produced again regardless of exactly which call marked it (see
    /// `withState`'s own doc for the correction to an earlier, overstated
    /// version of this claim). `write` is different in kind, not degree: it
    /// is `@State`'s `wrappedValue` setter, has exactly one call site
    /// (`State.swift:64`), and can run from *anywhere* — most often a click
    /// handler firing between frames — with no relationship at all to
    /// whether its element still exists. Treating a write as equivalent to
    /// production would let an element that was never rendered this frame
    /// masquerade as live for exactly one sweep, which is wrong for what
    /// `isLive` promises AX (spec §9): produced, not merely poked. If the
    /// owning element genuinely is being produced this frame, its own
    /// `mark`/`withState` call already keeps the entry live; this only
    /// changes what happens to a write whose element is NOT being produced —
    /// its value still survives the next `sweep()` (tombstones keep every
    /// value, unconditionally), it just is not reported live until something
    /// marks it again. Pinned by `anUnmarkedEntryIsRetainedAsATombstoneWithItsValue`
    /// (`TombstoneTests.swift`): `write` then an immediate `sweep()`, with
    /// nothing else touching the id, ends with `isLive == false` and
    /// `peek == 42`.
    ///
    /// This is `@State`'s `wrappedValue` setter's path and is meant to have
    /// no other caller: anything that reads-then-maybe-writes on its own
    /// schedule (`ScrollView`'s offset, `withState`'s other callers) must not
    /// dirty the window on every frame it happens to run on. A `@State`
    /// write, by contrast, is exactly the SwiftUI-authority signal that
    /// something changed and a redraw is owed (ruling: SwiftUI is the design
    /// authority where it and CSS differ; CSS has no opinion on invalidation
    /// at all). **"Meant to" is a comment, not an enforced constraint**:
    /// `S` is unconstrained and unconnected to any prior value at `id`, so
    /// nothing here stops a second, differently-typed caller from reaching
    /// this method at all.
    ///
    /// **Measured, unconstrained-type behaviour, not a regression:** writing
    /// to a slot that does not yet exist creates it — an ordinary first
    /// write. Writing a value of a DIFFERENT type than what is already
    /// stored at `id` silently clobbers it: `storage[id]` becomes the new
    /// value under the new type, `peek(id, as: OldType.self)` then returns
    /// `nil`, and a `State<OldType>` bound to that slot reads back its own
    /// `initialValue` with no trap and no diagnostic. This is identical to
    /// `withState(id, initial:)`'s own long-standing clobber semantics — `S`
    /// was never anchored to the slot's stored type there either — so this
    /// is not a new hazard `write` introduces, only one it inherits.
    func write<S>(_ id: GlobalElementID, _ value: S) {
        storage[id] = Entry(value: value, lastSeenGeneration: generation, isLive: true)
        isDirty = true
        onWrite?()
    }

    /// Clear `isDirty`. `Window.drawFrameIfNeeded` calls this at the same
    /// point it sets `needsRedraw = false` — BEFORE `renderRoot` runs, not
    /// after. Clearing after would swallow a write made during the frame
    /// itself: the flag would go true during `renderRoot` and then false
    /// again on the very next line, with nothing left to observe it. Clearing
    /// before means a write during the frame re-raises the flag, and the next
    /// `drawFrameIfNeeded` sees it — the same shape `frame.wantsAnotherFrame`
    /// already uses for exactly this reason.
    func clearDirty() { isDirty = false }

    /// Read the state at `id` without marking it. Test observability: a reader
    /// that marked would make liveness assertions pass by the act of checking
    /// them.
    ///
    /// **Returns a tombstone's value too.** Since this task, `sweep()` no
    /// longer deletes an unmarked entry, so `peek` after a sweep can return a
    /// value for an element that was not produced this frame — that is the
    /// whole point of a tombstone. Use `isLive(_:)` to ask whether the owning
    /// element was actually produced.
    func peek<S>(_ id: GlobalElementID, as type: S.Type = S.self) -> S? {
        storage[id]?.value as? S
    }

    /// Whether `id`'s element was produced by the frame now being built (more
    /// precisely: whether it was marked since the last `sweep()`).
    ///
    /// **`false` does NOT mean "gone."** A tombstoned entry keeps its value —
    /// `peek(_:as:)` still returns it — and is resurrected by the next `mark`,
    /// `withState` or `write` naming it. This reports only whether the
    /// element was produced, which is what an AX handle will read as invalid
    /// (spec §9) once that layer exists.
    func isLive(_ id: GlobalElementID) -> Bool { storage[id]?.isLive ?? false }

    /// Re-mark every entry's liveness for the frame just finished, retain
    /// every entry regardless of the answer, and — only once the table has
    /// grown past `sweepThreshold` — reap the ones that are both unmarked and
    /// stale.
    ///
    /// Called once per frame, **after** the frame is built.
    ///
    /// **The liveness pass no longer deletes anything — that was this
    /// milestone's Task 1.** Before it, this was `storage = storage.filter {
    /// marked.contains($0.key) }`: an unmarked entry vanished, value and all,
    /// on the very sweep after its element stopped being produced. Now every
    /// entry survives that pass; only its `isLive` flag (and, for the marked
    /// ones, `lastSeenGeneration`) moves.
    ///
    /// **Clearing `marked` here is what makes the ordering matter, and it is
    /// subtler than it looks.** Because marks are cleared only inside this
    /// function, sweeping at the *start* of a frame still sees the previous
    /// frame's marks — so the wrong ordering does not lose everything, it
    /// introduces a **one-frame liveness lag** (before this task, when
    /// `sweep()` still deleted, the same ordering mistake was a one-frame
    /// *eviction* lag — the whole value stayed an extra frame rather than
    /// just the `isLive` flag). An earlier version of this
    /// comment claimed the stronger, false thing and named
    /// `stateSurvivesARebuildWhenTheElementIsProducedAgain` as the witness; that
    /// test stays green under the ordering mutation. The test that actually
    /// reddens is `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`
    /// (formerly `anElementThatStopsBeingProducedIsSweptByTheNextFrame`, before
    /// this task inverted it — see that test's own comment).
    ///
    /// **The reap runs second, guarded on `storage.count > sweepThreshold`, so
    /// the steady state pays nothing at all** — a table sitting at 20 entries
    /// (this type's own doc above, `sweepThreshold`'s own comment) never even
    /// evaluates a single entry's staleness. `entry.lastSeenGeneration
    /// + staleAfterGenerations < generation` — addition against the just-
    /// advanced `generation`, not subtraction from it — is deliberate:
    /// `generation` is a `UInt64` starting at 0, and a subtracting form
    /// (`generation - staleAfterGenerations`) underflows and traps on any of
    /// the first `staleAfterGenerations` sweeps of this table's life. The
    /// addition form asks the identical question and cannot underflow.
    /// **`isLive` is checked too, and today that check is REDUNDANT BY
    /// CONSTRUCTION — not the line the "never reap a live entry" promise
    /// rests on.** The liveness loop directly above this one is what the
    /// promise actually rests on: for every key, unconditionally, it sets
    /// `isLive := isMarked` and, exactly when marked, stamps
    /// `lastSeenGeneration := generation` — the value just incremented at
    /// the top of this same call. So by the time this loop runs,
    /// `isLive == true ⟺ lastSeenGeneration == generation` is a structural
    /// invariant of the pass above, not a probabilistic fact about who
    /// happens to be current. Substitute that equality into the staleness
    /// test and a live entry's `lastSeenGeneration + staleAfterGenerations
    /// < generation` becomes `generation + staleAfterGenerations <
    /// generation` — false for any `staleAfterGenerations >= 1` — so no
    /// live entry can ever be stale here, with or without `!entry.isLive`.
    /// Proved both ways: read the two loops together, and empirically —
    /// deleting the `!entry.isLive` conjunct produces a byte-identical
    /// **782/782** test run (re-run 2026-09-02 at the whole-branch fix wave;
    /// it read 758/758 when first measured, which was that task's own suite
    /// size — the claim is "byte-identical", and the count only dates it).
    ///
    /// **Kept anyway, on purpose, as an honest label rather than dead
    /// code.** The redundancy is an accident of *this* ordering, not a law:
    /// it breaks the moment either (1) the liveness loop stops stamping
    /// `lastSeenGeneration` together with `isLive` in the same pass — e.g.
    /// a future caller resurrects an entry (`mark`) without the stamp
    /// happening until some later sweep — or (2) the reap runs *before*
    /// the liveness loop instead of after it. Either change makes this
    /// conjunct the only thing standing between a live entry and getting
    /// reaped. Delete it today and nothing reddens; delete it and make
    /// either of those changes later and something will, silently, unless
    /// this line is still here to catch it.
    func sweep() {
        // `ID-R`: a name an evaluated position replaced, and that this frame
        // produced nowhere, is reset before the next frame can return to it.
        for name in departedNames where !producedNames.contains(name) {
            departedNameResets += 1
            resetEntries(under: name, includingRoot: true)
        }
        departedNames.removeAll(keepingCapacity: true)
        swap(&namedPositions, &previousNamedPositions)
        namedPositions.removeAll(keepingCapacity: true)
        producedNames.removeAll(keepingCapacity: true)
        windowedParents.removeAll(keepingCapacity: true)

        generation += 1
        for id in storage.keys {
            let isMarked = marked.contains(id)
            storage[id]!.isLive = isMarked
            if isMarked {
                storage[id]!.lastSeenGeneration = generation
            }
        }
        marked.removeAll(keepingCapacity: true)
        // `ID-C`: this frame's produced conditional slots become the set the next
        // frame's `noteAbsent` compares against. A swap, so no allocation once warm.
        swap(&producedSlots, &previouslyProducedSlots)
        producedSlots.removeAll(keepingCapacity: true)

        if storage.count > Self.sweepThreshold {
            for (id, entry) in storage
            where !entry.isLive && entry.lastSeenGeneration + Self.staleAfterGenerations < generation {
                storage.removeValue(forKey: id)
            }
        }
    }
}
