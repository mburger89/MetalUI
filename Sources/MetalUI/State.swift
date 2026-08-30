/// A value that survives the fresh tree each frame, keyed by its element's
/// identity.
///
/// **Nothing durable is stored in the element struct.** The value lives in the
/// window's ``StateTable`` under a slot id derived from the element's own
/// ``GlobalElementID``; the wrapper holds only a box the framework seeds with
/// that location each frame. That indirection is what makes the wrapper
/// possible in public Swift at all: `Mirror` hands back *copies* of a struct's
/// stored properties, so it cannot write into them — but a copy shares the
/// same box.
///
/// **`@MainActor`, because `StateTable` is.** `Element` is itself `@MainActor`
/// (`Element.swift`), so every real use site is already isolated; this only
/// makes the wrapper's own `wrappedValue` accessors — which call straight into
/// `StateTable.peek`/`withState` — legal to write. Without it, `wrappedValue`
/// cannot call a main-actor-isolated method from a synchronous nonisolated
/// context (measured: `swift build` rejects the brief's un-annotated version
/// with exactly that diagnostic).
///
/// **Open question: what happens when one element VALUE is placed twice in a
/// tree — `let c = Counter(); Box { c; c }` — rather than two separate
/// values of the same type?** Both occurrences share one `Box` instance
/// (`let box = Box()` is copied by reference, not reconstructed), so the
/// second `bind` call overwrites the first `box.table`/`box.slotID` with its
/// own slot id. A probe reading both counters after a few frames of
/// `Row { c; c }.render` back-to-back three times read `[1, 1, 2, 2, 3, 3]`
/// — correct-LOOKING, but not conclusive: both copies advance in lockstep in
/// that probe (each `requestLayout` increments its own counter by the same
/// amount), so a wrong slot assignment would still read the right NUMBER.
/// Telling "both counters correctly share one entry because they are one
/// value" from "the second bind silently clobbered the first, and they only
/// look right because they happen to move together" needs a differential
/// probe — e.g. two occurrences that increment by different amounts, or that
/// are rendered on frames where only one of them runs its `requestLayout` —
/// and none has been written. Recording this rather than guessing which way
/// it resolves: reusing one element value is a shape the box design does not
/// obviously handle either way, and naming the gap is worth more here than a
/// claim that has not been checked.
@propertyWrapper
@MainActor
public struct State<Value> {
    final class Box {
        var table: StateTable?
        var slotID: GlobalElementID?
    }

    let box = Box()
    let initialValue: Value

    public init(wrappedValue: Value) { self.initialValue = wrappedValue }

    public var wrappedValue: Value {
        get {
            guard let table = box.table, let slotID = box.slotID else {
                return initialValue
            }
            return table.peek(slotID, as: Value.self) ?? initialValue
        }
        nonmutating set {
            guard let table = box.table, let slotID = box.slotID else { return }
            // `write`, not `withState` — §2.6: a `@State` write must mark the
            // window dirty, and `withState` is also `ScrollView`'s per-frame
            // offset path, which must NOT (see `StateTable.write`'s doc).
            table.write(slotID, newValue)
        }
    }
}

extension State {
    /// Seeds the box, and marks the slot live for this frame's sweep. Called
    /// by the framework once per frame per element (`StateBinder.bind`).
    ///
    /// The ordinal goes in the NAME rather than in `at:` — a name replaces a
    /// position rather than joining it, so `at:` is ignored whenever a name is
    /// supplied, and a named slot cannot collide with a positional child.
    ///
    /// **Marks unconditionally, in the same call that computes the id.**
    /// `StateTable.mark`'s own doc comment explains why marking has to happen
    /// here rather than waiting for `wrappedValue`'s own access: a value read
    /// only inside an `if` would go unmarked on frames where the branch is
    /// not taken, and the next `sweep()` would discard it. Marking from the
    /// same call that sets `box.slotID`, rather than from a caller re-reading
    /// it back out through a second existential dispatch, means there is no
    /// path where the id gets bound but the mark does not follow it.
    func bind(to table: StateTable, id: GlobalElementID, slot: Int) {
        box.table = table
        let slotID = GlobalElementID.child(of: id, at: slot,
                                           name: ElementID("$state\(slot)"))
        box.slotID = slotID
        table.mark(slotID)
    }
}
