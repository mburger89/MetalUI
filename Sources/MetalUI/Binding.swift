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
/// **`transaction`, `animation(_:)` and `transaction(_:)`** (plan task 13,
/// ruling `AN-Z`; probe `swiftui-transactions-animation.swift` T11, T11s,
/// T12s): a write through a binding whose source is `@State` — `$state`, and
/// every binding derived from one by dynamic member or the optional
/// initialisers — runs inside `withTransaction(transaction)` when its
/// transaction carries an animation, so `$isOpen.animation().wrappedValue =
/// true` animates what the write changes. **A `Binding(get:set:)` carries its
/// transaction but does not apply it**, as SwiftUI's closure binding over a
/// model snaps (T11): what decides is where the binding came from, a flag the
/// derived bindings inherit, not a wrapper around every setter.
///
/// **The name was `KeyBinding`'s deprecated alias until this type landed**
/// (`EV-N`); a keymap entry is spelled `KeyBinding(…)`.
@MainActor
@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void
    /// Whether a write applies `transaction` — true only for a binding whose
    /// source is `@State` (`AN-Z`).
    private let appliesTransaction: Bool

    /// The transaction a write through this binding happens under — applied
    /// only when the binding's source is `@State` (`AN-Z`). Empty by default.
    public var transaction = Transaction()

    /// A binding that reads with `get` and writes with `set` — called once per
    /// write (B4). **Its transaction is carried and never applied** (T11).
    public init(get: @escaping @MainActor () -> Value,
                set: @escaping @MainActor (Value) -> Void) {
        self.init(get: get, set: set, appliesTransaction: false)
    }

    init(get: @escaping @MainActor () -> Value,
         set: @escaping @MainActor (Value) -> Void,
         appliesTransaction: Bool) {
        self.getValue = get
        self.setValue = set
        self.appliesTransaction = appliesTransaction
    }

    /// `$state`'s binding (`State.projectedValue`): a source that applies its
    /// transaction (`AN-Z`).
    static func stateSource(get: @escaping @MainActor () -> Value,
                            set: @escaping @MainActor (Value) -> Void) -> Binding<Value> {
        Binding(get: get, set: set, appliesTransaction: true)
    }

    /// A copy whose transaction's animation is `animation` — SwiftUI's
    /// `animation(_:)` (T11s).
    public func animation(_ animation: Animation? = .default) -> Binding<Value> {
        var copy = self
        copy.transaction.animation = animation
        return copy
    }

    /// A copy whose transaction is `transaction` — SwiftUI's `transaction(_:)`
    /// (T12s).
    public func transaction(_ transaction: Transaction) -> Binding<Value> {
        var copy = self
        copy.transaction = transaction
        return copy
    }

    /// A binding over the same source and transaction as this one, reading and
    /// writing through `get` and `set` — every derived binding's constructor.
    private func derived<T>(get: @escaping @MainActor () -> T,
                            set: @escaping @MainActor (T) -> Void) -> Binding<T> {
        var binding = Binding<T>(get: get, set: set, appliesTransaction: appliesTransaction)
        binding.transaction = transaction
        return binding
    }

    /// A binding to an immutable value: every write is dropped (B2).
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// The current value: reading calls the getter, writing calls the setter. A
    /// write is a `@State` write when the source is one, so write from input,
    /// never from a phase (`DD-D`).
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set {
            if appliesTransaction, transaction.animation != nil {
                withTransaction(transaction) { setValue(newValue) }
            } else {
                setValue(newValue)
            }
        }
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
    ///
    /// It keeps this binding's source and transaction (`AN-Z`), and writes
    /// through the base's raw setter, so its own transaction is the one that
    /// applies.
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        let base = self
        return derived(
            get: { base.getValue()[keyPath: keyPath] },
            set: { newValue in
                var value = base.getValue()
                value[keyPath: keyPath] = newValue
                base.setValue(value)
            })
    }

    /// Lifts a binding to an optional: a `nil` write is **ignored** (B5). Keeps
    /// the base's source and transaction (`AN-Z`).
    public init<V>(_ base: Binding<V>) where Value == V? {
        self = base.derived(get: { base.getValue() },
                            set: { newValue in
                                if let newValue { base.setValue(newValue) }
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
        self = base.derived(get: {
                                if let current = base.getValue() { last.value = current }
                                return last.value
                            },
                            set: { newValue in
                                last.value = newValue
                                base.setValue(newValue)
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
