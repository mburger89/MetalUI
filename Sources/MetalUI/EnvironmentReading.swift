/// STUB (red-first): every reading is uncomparable until the implementation lands.
enum EnvironmentReading: Equatable {
    case value(any Equatable)
    case object(ObjectIdentifier?)
    case uncomparable

    static func == (l: EnvironmentReading, r: EnvironmentReading) -> Bool { false }

    var isUncomparable: Bool { true }

    static func of<T>(_ value: T) -> EnvironmentReading { .uncomparable }
}
