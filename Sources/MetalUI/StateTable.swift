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

    /// Set by `write` and consulted by `Window`, which is the "observable a
    /// test can read without a window" half of §2.6's invalidation.
    ///
    /// **Deliberately NOT raised by `withState`.** `ScrollView`'s per-frame
    /// offset bookkeeping (`resolvedOffset`, `ScrollView.swift`) goes through
    /// `withState` on every render, scrolled or not — if that raised this
    /// flag, every frame would mark the window dirty and the display link
    /// would never pause, which is milestone 4's exit criterion. `write` is
    /// the only path in, and it exists specifically because `@State`'s setter
    /// needs a distinct one.
    private(set) var isDirty: Bool = false

    /// Fired by `write`, in addition to raising `isDirty` — this is the half
    /// `isDirty` alone cannot cover. `Window.drawFrameIfNeeded` pauses the
    /// display link whenever the window is clean, so a flag only `drawFrame-
    /// IfNeeded` consults is unreachable while the window sits idle — exactly
    /// the state a `@State` write from outside the render loop (a click
    /// handler, a completion callback) needs to escape. `Window.init`
    /// installs this pointing at its own `setNeedsRedraw()`, captured weakly:
    /// `Window` owns this table, so a strong capture here would be a retain
    /// cycle.
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

    /// Write `value` at `id`, marking it live for this frame's sweep exactly
    /// as `withState` does, and — the difference from `withState` — raising
    /// `isDirty` and firing `onWrite`.
    ///
    /// This is `@State`'s `wrappedValue` setter's path and is meant to have
    /// no other caller: anything that reads-then-maybe-writes on its own
    /// schedule (`ScrollView`'s offset, `withState`'s other callers) must not
    /// dirty the window on every frame it happens to run on. A `@State`
    /// write, by contrast, is exactly the SwiftUI-authority signal that
    /// something changed and a redraw is owed (ruling: SwiftUI is the design
    /// authority where it and CSS differ; CSS has no opinion on invalidation
    /// at all).
    func write<S>(_ id: GlobalElementID, _ value: S) {
        marked.insert(id)
        storage[id] = value
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
