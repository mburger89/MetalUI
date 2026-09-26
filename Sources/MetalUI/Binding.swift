/// A two-way connection to a value someone else owns — SwiftUI's `Binding`
/// (ruling `DD-D`; probe `docs/probes/swiftui-data-and-scrolling.swift`, arms
/// B1–B6).
///
/// ```swift
/// struct Owner: Component {
///     @State var name = ""
///     var content: some ElementGroup { NameField(name: $name) }
/// }
/// struct NameField: Component {
///     @Binding var name: String
///     var content: some ElementGroup { TextField("Name", text: $name) }
/// }
/// ```
///
/// **A pair of closures, nothing stored.** `$state` (``State/projectedValue``)
/// reads and writes the owner's `StateTable` slot at call time, through any
/// number of `@Binding` hops (B1), so a binding kept after the body that made
/// it has run is live, not a snapshot (B6). `.constant` ignores writes (B2); a
/// key-path binding (`$model.name`) writes one field and leaves the rest (B3);
/// `init(get:set:)` calls its setter once per write (B4 — how often the getter
/// runs is not specified, in SwiftUI or here); the two optional initialisers
/// follow B5.
///
/// **Main-actor isolated — divergence 78** (`DD-D` item 4). SwiftUI's
/// `Binding` is nonisolated and `Sendable`; MetalUI's `State` is `@MainActor`
/// and a binding's whole job is to reach it, and every `Element`, `Component`
/// and handler is main-actor already. Relaxing this later is additive. Pinned
/// by `aBindingIsMainActorIsolated` (`BindingCompileGuards`).
///
/// **A write through `$state` is a `@State` write** (`DD-D` item 7): it dirties
/// the window and fires `onWrite`, so `@State`'s rule carries over unchanged —
/// **write from input, never from a phase**.
///
/// No `transaction`/`animation(_:)`: transaction semantics are plan task 13's.
///
/// **The name was `KeyBinding`'s deprecated alias until this type landed**
/// (`EV-N`); a keymap entry is spelled `KeyBinding(…)`.
@MainActor
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    /// A binding that reads with `get` and writes with `set` — called once per
    /// write (B4).
    public init(get: @escaping @MainActor () -> Value,
                set: @escaping @MainActor (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    /// A binding to an immutable value: every write is dropped (B2).
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }

    /// `$name` on an `@Binding var name`: the binding itself, to pass on.
    public var projectedValue: Binding<Value> { self }

    /// What `@Binding var name: T` in a memberwise initialiser calls with the
    /// `Binding<T>` its caller passed.
    public init(projectedValue: Binding<Value>) {
        self = projectedValue
    }

    /// A binding to one field of this binding's value (B3): the write reads
    /// the current value, changes the one field, and writes the whole value
    /// back — so two derived bindings made together each write over the
    /// other's write (`twoKeyPathBindingsMadeTogetherEachWriteOverTheOthersWrite`).
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let base = self
        return Binding<Subject>(
            get: { base.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var value = base.wrappedValue
                value[keyPath: keyPath] = newValue
                base.wrappedValue = value
            })
    }

    /// Lifts a binding to an optional: a `nil` write is **ignored** (B5).
    public init<V>(_ base: Binding<V>) where Value == V? {
        self.init(get: { base.wrappedValue },
                  set: { newValue in
                      if let newValue { base.wrappedValue = newValue }
                  })
    }

    /// Unwraps a binding to an optional: `nil` while the base is `nil`, and a
    /// binding that writes through otherwise (B5). Once the base goes `nil`
    /// later, it reads the last non-`nil` value it saw (MetalUI's answer,
    /// unprobed in SwiftUI, pinned by `theOptionalBindingInitialisersMatchSwiftUI`;
    /// `DD-D` item 2).
    public init?(_ base: Binding<Value?>) {
        guard let initial = base.wrappedValue else { return nil }
        let last = LastValue(initial)
        self.init(get: {
                      if let current = base.wrappedValue { last.value = current }
                      return last.value
                  },
                  set: { newValue in
                      last.value = newValue
                      base.wrappedValue = newValue
                  })
    }
}

/// The last non-`nil` value an unwrapped binding read — `Binding.init?(_:)`.
@MainActor
private final class LastValue<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// `State.projectedValue` (`$state`) is declared in `State.swift`: a property
// wrapper's projection must be declared in the wrapper's own body.
