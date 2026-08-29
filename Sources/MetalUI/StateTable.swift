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
/// vanishing. The mechanism that would provide it does not exist here: `sweep()`
/// removes unmarked entries outright, and there is no tombstone state, no
/// validity flag, and no deferred-removal queue — check by grepping this file
/// for `tombstone`, which finds only this paragraph.
///
/// **Exit transitions are impossible until that mechanism exists**, and this is
/// *why* v1 does not have them (§14) rather than an oversight. An element that
/// stops being produced has its animation state removed on that very frame, so
/// there is nothing left to animate out of. Adding exit transitions later is a
/// change to §4.3's sweep, not a feature bolted onto the animation system.
@MainActor
final class StateTable {
    private var storage: [GlobalElementID: Any] = [:]
    private var marked: Set<GlobalElementID> = []

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
    func withState<S>(_ id: GlobalElementID,
                      initial: @autoclosure () -> S,
                      _ body: (inout S) -> Void) {
        marked.insert(id)
        var value = (storage[id] as? S) ?? initial()
        body(&value)
        storage[id] = value
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
    func mark(_ id: GlobalElementID) { marked.insert(id) }

    /// Read the state at `id` without marking it. Test observability: a reader
    /// that marked would make `stateIsSweptWhenTheElementStopsBeingProduced`
    /// pass by the act of checking it.
    func peek<S>(_ id: GlobalElementID, as type: S.Type = S.self) -> S? {
        storage[id] as? S
    }

    /// Drop every entry not marked since the last sweep.
    ///
    /// Called once per frame, **after** the frame is built.
    ///
    /// **Clearing `marked` here is what makes the ordering matter, and it is
    /// subtler than it looks.** Because marks are cleared only inside this
    /// function, sweeping at the *start* of a frame still sees the previous
    /// frame's marks — so the wrong ordering does not lose everything, it
    /// introduces a **one-frame eviction lag**. An earlier version of this
    /// comment claimed the stronger, false thing and named
    /// `stateSurvivesARebuildWhenTheElementIsProducedAgain` as the witness; that
    /// test stays green under the ordering mutation. The test that actually
    /// reddens is `anElementThatStopsBeingProducedIsSweptByTheNextFrame`.
    func sweep() {
        storage = storage.filter { marked.contains($0.key) }
        marked.removeAll(keepingCapacity: true)
    }
}
