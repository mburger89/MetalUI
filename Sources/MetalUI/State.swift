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
/// - **Handlers were wrong, and re-binding could not fix them.** A closure
///   registered by one occurrence captures this box by reference; one box
///   holds one `slotID`; by the time a click arrives it holds whatever the last
///   phase bound. Measured: occurrence 0 clicked once read **1** while
///   occurrence 1, never clicked, read **102** — correct is 101 and 2.
///
/// **Fixed for input dispatch by plan task 8 (ruling ID-F)** without a per-copy
/// slot (`Mirror` still cannot write a stored struct field): the box remembers
/// every slot it was bound to in one generation (`Box.occurrences`), and each
/// input dispatch site names the element it is dispatching to
/// (`StateDispatch.owner`), so a dispatched handler reads and writes the
/// occurrence whose element is the owner or an ancestor of it — SwiftUI's
/// answer (probe `swiftui-composition-identity.swift` S1, S4). Pinned by
/// `OccurrenceIdentityTests` (one arm per dispatch site).
///
/// **Outside dispatch it is still the last-bound slot — divergence 71.** A
/// closure called directly, from a timer or a task, has no owner; SwiftUI
/// writes each occurrence's own storage there too (probe S5). Pinned by
/// `IdentityTests`' `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt`
/// (occurrence 0's handler called directly reads 1 / 102), and still counted by
/// `StateTable.aliasedStateBoxes`. **So a value placed twice is safe for
/// input handlers; for anything else, build two values.**
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
        /// Every slot this box was bound to in `boundGeneration`, once a
        /// SECOND, different slot is bound in one generation — one element
        /// value placed twice (ruling ID-F). `nil` in the common case, so an
        /// unaliased box allocates nothing; cleared by the first bind of a
        /// later generation.
        var occurrences: [GlobalElementID]?

        /// The slot `wrappedValue` reads and writes: while input dispatch runs
        /// a handler (`StateDispatch.owner`), an aliased box serves the
        /// occurrence whose element is the owner or its nearest ancestor;
        /// otherwise — and outside dispatch, divergence 71 — the last-bound
        /// `slotID`.
        @MainActor var resolvedSlot: GlobalElementID? {
            guard let occurrences, StateDispatch.owner != nil else { return slotID }
            // A slot's parent is its element (`bind`'s `child(of: id, …)`).
            guard let index = StateDispatch.resolve(among: occurrences.map { $0.parent! }) else {
                return slotID
            }
            return occurrences[index]
        }
    }

    let box = Box()
    let initialValue: Value

    public init(wrappedValue: Value) { self.initialValue = wrappedValue }

    public var wrappedValue: Value {
        get {
            guard let table = box.table, let slotID = box.resolvedSlot else {
                return initialValue
            }
            return table.peek(slotID, as: Value.self) ?? initialValue
        }
        nonmutating set {
            guard let table = box.table, let slotID = box.resolvedSlot else { return }
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
        //
        // **Since ID-F the box remembers each occurrence's slot**, and input
        // dispatch resolves a handler's write to its own occurrence
        // (`resolvedSlot`, `StateDispatch`). The count stays: the shape is
        // resolved for dispatched handlers, not removed.
        if box.boundGeneration != table.generation {
            box.occurrences = nil
        } else if let previous = box.slotID, previous != slotID {
            table.noteAliasedStateBox()
            if box.occurrences == nil { box.occurrences = [previous] }
            if !box.occurrences!.contains(slotID) { box.occurrences!.append(slotID) }
        }
        box.slotID = slotID
        box.boundGeneration = table.generation
        table.mark(slotID)
    }
}
