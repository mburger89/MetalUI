/// A concrete size in layout units.
///
/// (Until stage 9 this file also held the CSS engine's leaf-measurement
/// vocabulary — `MeasureFunction`, `AvailableSpace`, `AvailableSpaceSize` and
/// `OptionalSizeD` — deleted with the engine, `LR-FC`. A kernel leaf measures
/// through `ProposalMeasureFunction`.)
public struct SizeD: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public static let zero = SizeD(width: 0, height: 0)
}
