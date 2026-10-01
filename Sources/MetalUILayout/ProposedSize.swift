/// A parent's size proposal for one layout measurement.
///
/// A `nil` axis is *unspecified*: the child is free to choose that axis. It is
/// deliberately distinct from zero and infinity, which are concrete proposals
/// used when a layout needs minimum-size or unconstrained measurements. This is
/// MetalUI's renderer-independent counterpart to SwiftUI's
/// `ProposedViewSize`.
public struct ProposedSize: Sendable, Hashable {
    /// The proposed width; `nil` asks for the ideal width.
    public var width: Double?
    /// The proposed height; `nil` asks for the ideal height.
    public var height: Double?

    /// A proposal of `width` by `height`; omitted axes are unspecified.
    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    /// Neither axis is constrained by the parent.
    public static let unspecified = ProposedSize()

    /// The parent asks for the smallest response on both axes.
    public static let zero = ProposedSize(width: 0, height: 0)

    /// The parent asks for an unconstrained response on both axes.
    public static let infinity = ProposedSize(width: .infinity, height: .infinity)

    /// Resolves only unspecified axes from `fallback`.
    ///
    /// This is intentionally not a general clamping operation: a specified
    /// zero or infinity remains that exact proposal. Containers use it after
    /// choosing their own fallback size for an otherwise-unspecified axis.
    public func replacingUnspecifiedDimensions(by fallback: SizeD) -> SizeD {
        SizeD(width: width ?? fallback.width, height: height ?? fallback.height)
    }
}

/// Which text baseline a horizontal stack aligns its children by (ruling
/// TE-K): SwiftUI's `VerticalAlignment.firstTextBaseline` and
/// `.lastTextBaseline`, at the kernel.
public enum ProposalTextBaseline: Hashable, Sendable {
    case first, last
}

/// A layout response, including optional text baselines.
///
/// Baselines are distances from the measured rectangle's top edge. Boxes and
/// shapes leave them `nil`; text leaves will supply them when the native layout
/// path is introduced. Keeping them with the first proposal contract avoids a
/// second incompatible leaf-measurement API when baseline-aligned stacks land.
public struct LayoutMeasurement: Sendable, Equatable {
    /// The measured size.
    public var size: SizeD
    /// The first text baseline's distance from the top, if the leaf has text.
    public var firstBaseline: Double?
    /// The last text baseline's distance from the top, if the leaf has text.
    public var lastBaseline: Double?

    /// A measurement of `size`, with optional baselines (`TE-K`).
    public init(size: SizeD, firstBaseline: Double? = nil, lastBaseline: Double? = nil) {
        self.size = size
        self.firstBaseline = firstBaseline
        self.lastBaseline = lastBaseline
    }
}
