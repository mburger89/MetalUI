import Observation

/// SwiftUI's `@Bindable`: a property wrapper over an `@Observable` class whose projected value hands out a
/// ``Binding`` to each of the object's properties, so `$model.name` binds a text field to `model.name`
/// (item R3-4, ruling `SP-D`; probe `docs/probes/swiftui-scroll-position.swift` arm B).
///
/// ```swift
/// struct Editor: Component {
///     @Bindable var model: Profile       // a class marked @Observable
///     var content: some ProposalElementGroup {
///         TextField("Name", text: $model.name)
///     }
/// }
/// ```
///
/// **There is no new observation machinery.** A binding's getter reads the property, which registers the
/// read with whatever `withObservationTracking` is open - the frame build, `ContentMemo`'s tracked
/// content, a `Window`'s sentinel (`identity-state.md`, `@Observable`) - and its setter writes it from
/// input, which fires the same `onChange` any other write to an `@Observable` does. `Bindable` itself
/// holds only the reference, so it is also correct as a plain local (`Bindable(model).name`) or beside an
/// `@Environment(Model.self)` object, which is how an environment object is edited (`MD-H` item 6).
///
/// A write through the binding is **not** animated and carries no transaction, as `Binding(get:set:)`
/// (`AN-Z`): only a `@State` source applies its transaction.
@MainActor
@dynamicMemberLookup
@propertyWrapper
public struct Bindable<Value: AnyObject & Observable> {
    /// The observable object the bindings write.
    public var wrappedValue: Value

    /// `$model`: this wrapper, so `$model.property` reaches ``subscript(dynamicMember:)``.
    public var projectedValue: Bindable<Value> { self }

    /// A wrapper over `wrappedValue`, SwiftUI's `Bindable(wrappedValue:)`.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// A wrapper over `wrappedValue`, SwiftUI's `Bindable(_:)`.
    public init(_ wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// The wrapper `$model` projected from another (`@Bindable var model: Model = $other`).
    public init(projectedValue: Bindable<Value>) {
        self = projectedValue
    }

    /// A binding to `keyPath` of the object: reading it reads the property (so the read is observed),
    /// writing it writes the property (so observers fire).
    public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let object = wrappedValue
        return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}
