import MetalUICore

/// Bridges a `Mirror` child back to `State`'s generic `bind`, without knowing
/// `Value`.
///
/// **`State<Value>` is generic, so a `Mirror` child typed `Any` cannot be cast
/// to `State<Int>` without already knowing `Int`.** Casting to this
/// existential instead lets `StateBinder` call `bind` on any `State<Value>`
/// with no `Value` in sight. `boundID` exposes the same slot id `bind` just
/// computed and stored in the wrapper's box, so `StateBinder` can mark it
/// without recomputing the `"$state\(slot)"` name a second time — the marked
/// id and the id `wrappedValue` reads later are then, structurally, the exact
/// same object rather than two calls that happen to agree.
@MainActor
protocol BindableState {
    func bind(to table: StateTable, id: GlobalElementID, slot: Int)
    var boundID: GlobalElementID? { get }
}

extension State: BindableState {
    var boundID: GlobalElementID? { box.slotID }
}

/// Seeds every `@State` an element declares with this frame's `StateTable`
/// and the element's own identity — the thing that makes `@State` work at
/// all, since the wrapper itself (`State.swift`) only ever reads a box
/// someone else must have filled in.
///
/// **Reflects a TYPE once, not an instance every frame.** `Mirror` over every
/// element every frame would cost more than the whole layout pass; a type's
/// stored properties cannot change at runtime, so the ordinals of its `State`
/// children are computed once, keyed by `ObjectIdentifier`, and reused for
/// every instance of that type forever. The common case — an element with no
/// `@State` at all — is a dictionary hit against an empty array and nothing
/// else: no second `Mirror` is ever built for it.
///
/// `@MainActor` because `StateTable`, `State` and `Element` all are — the
/// cache is main-actor state read and written from main-actor call sites
/// only, so no `nonisolated(unsafe)` is needed anywhere here.
@MainActor
enum StateBinder {
    /// Ordinals of the `State` wrappers a type declares among its `Mirror`
    /// children, computed once per type.
    private static var shapes: [ObjectIdentifier: [Int]] = [:]

    /// Test observability for the per-type cache. Not part of any contract.
    private(set) static var reflectionCount = 0

    static func resetReflectionCount() { reflectionCount = 0 }

    /// Seeds every `@State` `element` declares with `id`, and marks each slot
    /// live for this frame's sweep.
    ///
    /// Marking here rather than leaving it to `wrappedValue`'s own access is
    /// deliberate (see `StateTable.mark`'s doc comment): declaring `@State` is
    /// itself sufficient intent to keep the slot, whether or not this frame
    /// happens to read it.
    static func bind<E>(_ element: E, table: StateTable, id: GlobalElementID) {
        let key = ObjectIdentifier(E.self)
        let ordinals: [Int]
        if let cached = shapes[key] {
            ordinals = cached
        } else {
            ordinals = reflect(element)
            shapes[key] = ordinals
            reflectionCount += 1
        }
        guard !ordinals.isEmpty else { return }

        let children = Array(Mirror(reflecting: element).children)
        for slot in ordinals {
            guard let bindable = children[slot].value as? BindableState else { continue }
            bindable.bind(to: table, id: id, slot: slot)
            if let slotID = bindable.boundID {
                table.mark(slotID)
            }
        }
    }

    /// One `Mirror` pass over `element`'s stored properties, recording the
    /// index of every child that is a `State` wrapper (bridged through
    /// `BindableState`, since `Value` is unknown here).
    private static func reflect<E>(_ element: E) -> [Int] {
        var ordinals: [Int] = []
        for (index, child) in Mirror(reflecting: element).children.enumerated() {
            if child.value is BindableState {
                ordinals.append(index)
            }
        }
        return ordinals
    }
}
