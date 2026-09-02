import MetalUICore

/// Cross-frame state, keyed by `GlobalElementID`, marked on access and swept
/// after each frame (spec §4.3).
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
/// **Half of that mechanism is here; half is not.** `sweep()` no longer removes
/// unmarked entries — every `Entry` retains its `value` forever, and `isLive`
/// reports whether the element that owns it was produced by the most recent
/// frame. `isLive(_:)` is the validity flag AX will read. What is still missing
/// is **reaping**: nothing bounds how long a tombstone survives, so this table
/// grows without limit as elements come and go — deliberately out of scope here
/// (a later task's own central assertion needs that growth to be red on
/// arrival) and tracked by `lastSeenGeneration`, which is written but not yet
/// read by anything that reaps.
///
/// **Exit transitions are still impossible today**, but for a narrower reason
/// than before: the *state* now survives an element's last frame, but nothing
/// yet distinguishes "gone, keep animating out" from "gone, ordinary
/// tombstone" — that distinction is a future task's, not this one's. An element
/// that stops being produced no longer loses its state on that very frame, but
/// nothing here uses that survival for anything yet.
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
    /// is compared against this to decide staleness — the reaping this task
    /// deliberately does not implement; see the class doc.
    private(set) var generation: UInt64 = 0

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
    /// `Style.overflow` shape: a production write with no production read.
    ///
    /// **Deliberately NOT raised by `withState`.** `ScrollView`'s per-frame
    /// offset bookkeeping (`resolvedOffset`, `ScrollView.swift`) goes through
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
    /// actually produced.** `withState` and `mark` insert into it because
    /// both run only from inside a frame's own construction (`requestLayout`
    /// / `prepaint`), which is genuinely "this element was here this frame."
    /// `write` deliberately does NOT (see `write`'s own doc for why) — so the
    /// single field every one of the three flips is `Entry.isLive`, and
    /// `marked` membership is the one thing that is allowed to differ between
    /// them. That split is itself the "one path" the class doc's tombstone
    /// section promises: there is exactly one flag (`Entry.isLive`) and
    /// exactly one function (`sweep()`) that ever recomputes it from
    /// `marked`; nothing keeps a second, shadow notion of liveness.
    func withState<S>(_ id: GlobalElementID,
                      initial: @autoclosure () -> S,
                      _ body: (inout S) -> Void) {
        marked.insert(id)
        var value = (storage[id]?.value as? S) ?? initial()
        body(&value)
        storage[id] = Entry(value: value, lastSeenGeneration: generation, isLive: true)
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
    /// `withState` and `mark` both run only from inside a frame's own
    /// construction, so their `marked.insert` is a true "this element was
    /// produced this frame" signal that `sweep()` may act on. `write` is
    /// `@State`'s `wrappedValue` setter and can run from anywhere — most
    /// often a click handler firing *between* frames — so treating a write as
    /// equivalent to production would let an element that was never rendered
    /// this frame masquerade as live for exactly one sweep, which is wrong
    /// for what `isLive` promises AX (spec §9): produced, not merely poked.
    /// If the owning element genuinely is being produced this frame, its own
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

    /// Re-mark every entry's liveness for the frame just finished, and retain
    /// every entry regardless of the answer.
    ///
    /// Called once per frame, **after** the frame is built.
    ///
    /// **This no longer deletes anything — that is this task's whole change.**
    /// Before it, this was `storage = storage.filter { marked.contains($0.key)
    /// }`: an unmarked entry vanished, value and all, on the very sweep after
    /// its element stopped being produced. Now every entry survives; only its
    /// `isLive` flag (and, for the marked ones, `lastSeenGeneration`) moves.
    /// Deletion — reaping a tombstone once it has been dead long enough — is
    /// deliberately not implemented here; see the class doc and the milestone
    /// this task is the first step of.
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
    func sweep() {
        generation += 1
        for id in storage.keys {
            let isMarked = marked.contains(id)
            storage[id]!.isLive = isMarked
            if isMarked {
                storage[id]!.lastSeenGeneration = generation
            }
        }
        marked.removeAll(keepingCapacity: true)
    }
}
