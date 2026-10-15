/// What one declared `@Environment` read at a position (internal; `EE-A`, `EE-B`, record §120).
///
/// A memoized component (`Component.equatable()`) skips its `content` getter only while the readings of its
/// declared `@Environment` properties equal the readings of the evaluation it would replay. There is no epoch
/// counter: the values are compared, per declared property.
///
/// - `.value`: an `Equatable` value, compared by `==` after an opened-existential type match (a type mismatch is
///   unequal). An `Optional` compares as its wrapped value. The `Equatable` cast is dynamic (`EE-C`): measured at
///   lane 1 step 0, a `@MainActor`-isolated conformance casts on the main actor and fails off it.
/// - `.object`: a reference-type value that is not `Equatable` (compared by identity), or the instance an
///   `@Observable` object read provided; `nil` is "none provided".
/// - `.uncomparable`: a function, a struct holding one, an `EnvironmentValues`, `\.textMeasurer`: it equals
///   nothing, **itself included**, so a component holding one is refused (divergence 346's remainder).
enum EnvironmentReading: Equatable {
    case value(any Equatable)
    case object(ObjectIdentifier?)
    case uncomparable

    static func == (l: EnvironmentReading, r: EnvironmentReading) -> Bool {
        switch (l, r) {
        case let (.value(a), .value(b)): return openedEqual(a, b)
        case let (.object(a), .object(b)): return a == b
        default: return false
        }
    }

    var isUncomparable: Bool {
        if case .uncomparable = self { return true }
        return false
    }

    /// The reading of `value`: `Equatable` by `==`, a class (or an optional class) by identity, else uncomparable.
    static func of<T>(_ value: T) -> EnvironmentReading {
        if let equatable = value as? any Equatable { return .value(equatable) }
        if T.self is AnyObject.Type { return .object(ObjectIdentifier(value as AnyObject)) }
        if let optional = value as? any OptionalReadingClass { return .object(optional.readingIdentity) }
        return .uncomparable
    }
}

/// `==` of two existentials: opens `a`, then casts `b` to its type (a mismatch is unequal, never a trap).
private func openedEqual(_ a: any Equatable, _ b: any Equatable) -> Bool {
    func open<A: Equatable>(_ a: A) -> Bool {
        guard let b = b as? A else { return false }
        return a == b
    }
    return open(a)
}

/// `Optional<Class>` for `EnvironmentReading.of`: the identity of the wrapped instance, `nil` when none.
private protocol OptionalReadingClass {
    var readingIdentity: ObjectIdentifier? { get }
}

extension Optional: OptionalReadingClass where Wrapped: AnyObject {
    fileprivate var readingIdentity: ObjectIdentifier? { map { ObjectIdentifier($0) } }
}
