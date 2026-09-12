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
/// **Answered 2026-09-10: one element VALUE placed twice shares one box, and
/// it was corrupting both reads and clicks.** The note that stood here called
/// it an open question and asked for a differential probe — "two occurrences
/// that increment by different amounts" — because a lockstep probe reading
/// `[1, 1, 2, 2, 3, 3]` cannot tell a correct shared entry from a clobbered
/// one. That probe is now written
/// (`oneElementValuePlacedTwiceDoesNotShareItsState`) and it resolved both
/// ways at once:
///
/// - **Reads were wrong and are now fixed.** `bind` ran only inside layout, so
///   after the second occurrence bound, the first read the second's value in
///   every later phase — measured `[2, 2]` where `[1, 2]` is correct.
///   `ElementGroup.prepaintGroup`/`paintGroup` now re-bind to `layout.id`,
///   which is each occurrence's own id.
///
/// - **Handlers are still wrong, and re-binding cannot fix them.** A closure
///   registered by one occurrence captures this box by reference; one box
///   holds one `slotID`; by the time a click arrives it holds whatever the last
///   phase bound. Measured: occurrence 0 clicked once reads **1** while
///   occurrence 1, never clicked, reads **102** — correct is 101 and 2. Pinned
///   wrong on purpose by `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt`
///   and counted by `StateTable.aliasedStateBoxes`.
///
/// The real fix is a per-copy slot rather than a shared box, which the
/// reflection-driven binding currently forbids: `StateBinder.bind` walks a
/// `Mirror`, and `Mirror` cannot write a stored struct field. **Until then, do
/// not place one element value twice — build two.**
///
@propertyWrapper
@MainActor
public struct State<Value> {
    final class Box {
        var table: StateTable?
        var slotID: GlobalElementID?
        /// The `StateTable.generation` the current `slotID` was bound in, so a
        /// SECOND binding to a DIFFERENT slot within one generation can be
        /// told from the ordinary re-binding that happens once per phase.
        var boundGeneration: UInt64?
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
        // **One element VALUE placed twice aliases one box.** `Box` is a class,
        // so `Row { sep; sep }` gives two occurrences that share it; the second
        // `bind` overwrites the first's slot. Re-binding per phase
        // (`ElementGroup.prepaintGroup`/`paintGroup`) repairs the reads, but a
        // handler registered by the first occurrence captured this same box and
        // will still write the second's slot when it fires after the frame —
        // measured: occurrence 0 clicked once, occurrence 1's slot moved.
        // Counted rather than trapped: a trap here aborts the process, and the
        // shape is silent corruption rather than a crash today.
        if let previous = box.slotID, previous != slotID,
           box.boundGeneration == table.generation {
            table.noteAliasedStateBox()
        }
        box.slotID = slotID
        box.boundGeneration = table.generation
        table.mark(slotID)
    }
}
