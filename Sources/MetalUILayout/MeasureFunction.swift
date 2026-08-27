/// A concrete size in layout units.
public struct SizeD: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let zero = SizeD(width: 0, height: 0)
}

/// A size where either axis may be unknown.
public struct OptionalSizeD: Sendable, Equatable {
    public var width: Double?
    public var height: Double?
    public init(width: Double?, height: Double?) { self.width = width; self.height = height }
    /// Named `unspecified`, not `none`: a static `.none` on a non-Optional type
    /// shadows `Optional.none` at call sites and reads as "no size" rather than
    /// "both axes unknown".
    public static let unspecified = OptionalSizeD(width: nil, height: nil)
}

/// How much room a leaf may use in one axis.
public enum AvailableSpace: Sendable, Hashable {
    case definite(Double)
    /// Size to the smallest width that avoids overflow — the longest
    /// unbreakable run, for text.
    case minContent
    /// Size as if infinitely wide — a single line, for text.
    case maxContent
}

public struct AvailableSpaceSize: Sendable, Equatable {
    public var width: AvailableSpace
    public var height: AvailableSpace
    public init(width: AvailableSpace, height: AvailableSpace) {
        self.width = width; self.height = height
    }
}

/// How layout asks a leaf how big it wants to be (spec §5.5).
///
/// The two parameters cannot collapse into one. A *known* width of 100 obliges
/// the leaf to return 100. An *available* width of 100 obliges it to wrap at 100
/// and report its natural width, which may be less. Grid additionally needs
/// "known in this axis, max-content in the other".
public typealias MeasureFunction = @Sendable (
    _ known: OptionalSizeD,
    _ available: AvailableSpaceSize
) -> SizeD
