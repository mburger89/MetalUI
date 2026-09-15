import Foundation
import MetalUICore

/// A key for a custom environment value — SwiftUI's `EnvironmentKey`
/// (ruling EV-C).
///
/// `static let defaultValue = 0` satisfies the requirement. The value is read
/// wherever no writer above the reader set one.
public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

/// The values an element's position in the tree hands it: SwiftUI's
/// `EnvironmentValues`, scoped by nearest writer (ruling EV-A).
///
/// **Not a cascade.** A value is produced only at a writer —
/// `.environment(_:_:)`, `.transformEnvironment(_:transform:)`,
/// `.dynamicTypeSize(_:)`, `.theme(_:)` or `Window.environment` — and handed
/// out only to a reader: `pass.environment`, or an element whose type
/// declares an `@Environment`. Nothing is written into every node.
///
/// **Not `@MainActor`**: a plain value with nothing isolated in it. **Not
/// `Sendable`**: custom keys are stored as `[ObjectIdentifier: Any]`, and
/// SwiftUI's `EnvironmentKey.Value` is unconstrained, so this cannot promise
/// what its contents are. That same storage is why `Window.environment`
/// cannot compare an old and a new value, and every write to it dirties the
/// window (ruling EV-H).
///
/// **Two fields are not the caller's to write, and access control alone does
/// not stop it** (ruling EV-U). `pixelLength` is `public internal(set)` and
/// `theme` is `internal`, so neither has a writable key path outside the
/// module — but `\.self` does, and `.environment(\.self, EnvironmentValues())`
/// would reset both. `Frame.scopedValues(applying:)` and
/// `Frame.rootEnvironment` re-stamp them after every write instead.
public struct EnvironmentValues {
    /// Every field at its default: enabled, left-to-right, `Locale.current`,
    /// `.large`, a `pixelLength` of 1, the light theme, and every custom key at
    /// its `defaultValue`. The defaults match probe C (ruling EV-H); a `Frame`
    /// stamps the real `pixelLength` and theme over the last two.
    public init() {
        locale = Locale.current
    }

    /// Whether controls below accept interaction. `true` by default.
    public var isEnabled: Bool = true

    /// Carried and readable; nothing mirrors under `.rightToLeft` yet (ruling
    /// EV-K).
    public var layoutDirection: LayoutDirection = .leftToRight

    /// `Locale.current`, read in `init()`. **No built-in consumer**: `Text`'s
    /// tokenizer and typesetter never receive it (ruling EV-H, pinned by
    /// `aLocaleChangesNoTextMeasurement`).
    public var locale: Locale

    /// Carried; changes no built-in text size, as in SwiftUI on macOS (ruling
    /// EV-I, probe G, pinned by `dynamicTypeSizeChangesNoTextMeasurement`).
    public var dynamicTypeSize: DynamicTypeSize = .large

    /// One device pixel, in points: `1 / scaleFactor` of the frame's surface.
    ///
    /// **Read-only from outside the module**, as SwiftUI's is (ruling EV-J),
    /// and re-stamped after every write so `\.self` cannot reset it (EV-U).
    /// There is deliberately no `displayScale`: `PaintPass.fill` takes points
    /// and scales once, and a value in this unit draws a hairline correctly as
    /// written. **No internal reader**; it exists for element authors.
    public internal(set) var pixelLength: Double = 1

    /// The theme tokens resolve against. **Internal, and paint-only**: the only
    /// public reader is `PaintPass.theme`, and the only public writer is
    /// `.theme(_:)` (ruling EV-G).
    var theme: Theme = .light

    private var custom: [ObjectIdentifier: Any] = [:]

    /// A custom key's value, or its `defaultValue` when no writer set it.
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value {
        get {
            guard let stored = custom[ObjectIdentifier(key)] else { return K.defaultValue }
            // Only this setter writes the slot, typed by the same key.
            return stored as! K.Value
        }
        set { custom[ObjectIdentifier(key)] = newValue }
    }
}

/// SwiftUI's twelve dynamic type sizes (ruling EV-I).
///
/// `Comparable` in declaration order, so `size >= .accessibility1` reads as it
/// does in SwiftUI.
public enum DynamicTypeSize: Sendable, Hashable, CaseIterable, Comparable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5

    /// Whether this is one of the five accessibility sizes.
    public var isAccessibilitySize: Bool { self >= .accessibility1 }
}
