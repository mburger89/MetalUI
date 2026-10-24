// SwiftUI's `@Namespace` (ruling `LG-K`): a stable, per-declaration identity that
// `glassEffectID(_:in:)` and `glassEffectUnion(id:namespace:)` scope their ids by. MetalUI had
// none before Liquid Glass.

/// SwiftUI's `Namespace`: `@Namespace var ns` declares one identity for the element, stable
/// across frames and distinct per declaration; `ns` reads as a ``Namespace/ID``.
///
/// It rides `@State`'s own slot (a `$state<n>` sibling, **no eighth reserved name**, ruling
/// `LG-K`): the wrapper holds a `State` it never writes, and its id is the slot's identity.
/// Outside an element (never bound) it reads an id equal to no bound one.
@propertyWrapper
@MainActor
public struct Namespace {
    private let slot = State<Bool>(wrappedValue: false)

    /// A namespace; declare it as `@Namespace var name`.
    public init() {}

    /// The identity this declaration carries.
    public var wrappedValue: Namespace.ID {
        guard let slotID = slot.box.slotID else { return ID(owner: nil) }
        return ID(owner: slotID)
    }

    /// SwiftUI's `Namespace.ID`: `Hashable` and `Sendable`, compared by the declaring slot.
    public struct ID: Hashable, Sendable {
        let owner: GlobalElementID?
    }
}

extension Namespace: BindableState {
    func bind(to table: StateTable, id: GlobalElementID, slot index: Int) {
        slot.bind(to: table, id: id, slot: index)
    }
}
