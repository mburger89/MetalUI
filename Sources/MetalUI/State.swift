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
            table.withState(slotID, initial: initialValue) { $0 = newValue }
        }
    }
}

extension State {
    /// Seeds the box. Called by the framework once per frame per element.
    ///
    /// The ordinal goes in the NAME rather than in `at:` — a name replaces a
    /// position rather than joining it, so `at:` is ignored whenever a name is
    /// supplied, and a named slot cannot collide with a positional child.
    func bind(to table: StateTable, id: GlobalElementID, slot: Int) {
        box.table = table
        box.slotID = GlobalElementID.child(of: id, at: slot,
                                           name: ElementID("$state\(slot)"))
    }
}
