import MetalUICore

public enum Display: Sendable, Equatable { case flex, none }
public enum Position: Sendable, Equatable { case relative, absolute }
public enum FlexWrap: Sendable, Equatable { case noWrap, wrap, wrapReverse }
public enum Overflow: Sendable, Equatable { case visible, hidden, scroll }

public enum FlexDirection: Sendable, Equatable {
    case row, rowReverse, column, columnReverse

    /// True when the main axis is horizontal.
    public var isRow: Bool { self == .row || self == .rowReverse }
    /// True when items are placed from the far end of the main axis.
    public var isReverse: Bool { self == .rowReverse || self == .columnReverse }
}

public enum AlignItems: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum AlignSelf: Sendable, Equatable {
    case flexStart, flexEnd, center, baseline, stretch
}

public enum AlignContent: Sendable, Equatable {
    case flexStart, flexEnd, center, stretch, spaceBetween, spaceAround, spaceEvenly
}

public enum JustifyContent: Sendable, Equatable {
    case flexStart, flexEnd, center, spaceBetween, spaceAround, spaceEvenly
}

/// A node's layout inputs.
///
/// Box model is border-box only (spec §5.2): `size`, `minSize` and `maxSize`
/// include padding and border. There is deliberately no `boxSizing` property.
public struct Style: Sendable, Equatable {
    // Box
    public var display: Display = .flex
    public var position: Position = .relative
    public var inset: Edges<Dimension> = Edges(all: .auto)
    public var size: Size<Dimension> = Size(width: .auto, height: .auto)
    public var minSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var maxSize: Size<Dimension> = Size(width: .auto, height: .auto)
    public var aspectRatio: Float? = nil
    public var margin: Edges<Dimension> = Edges(all: .length(.pixels(Pixels(0))))
    public var padding: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var border: Edges<Length> = Edges(all: .pixels(Pixels(0)))
    public var overflow: Axes<Overflow> = Axes(both: .visible)

    // As a flex container
    public var flexDirection: FlexDirection = .row
    public var flexWrap: FlexWrap = .noWrap
    public var gap: Axes<Length> = Axes(both: .pixels(Pixels(0)))
    public var justifyContent: JustifyContent? = nil
    public var alignItems: AlignItems? = nil
    public var alignContent: AlignContent? = nil

    // As a flex item
    public var flexGrow: Float = 0
    public var flexShrink: Float = 1
    public var flexBasis: Dimension = .auto
    public var alignSelf: AlignSelf? = nil

    public init() {}

    public static let `default` = Style()
}
