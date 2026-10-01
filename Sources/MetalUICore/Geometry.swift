/// A point in a coordinate space parameterised by its unit type.
/// The `Unit` parameter is what prevents mixing logical and device pixels.
public struct Point<Unit> {
    /// The horizontal coordinate, increasing rightwards.
    public var x: Unit
    /// The vertical coordinate, increasing downwards.
    public var y: Unit
    /// The point at `x`, `y`.
    public init(x: Unit, y: Unit) { self.x = x; self.y = y }
}

/// A width and a height in one unit type.
public struct Size<Unit> {
    /// The horizontal extent.
    public var width: Unit
    /// The vertical extent.
    public var height: Unit
    /// A size of `width` by `height`.
    public init(width: Unit, height: Unit) { self.width = width; self.height = height }
}

/// A rectangle: an origin (its top-left corner) and a size.
public struct Bounds<Unit> {
    /// The top-left corner.
    public var origin: Point<Unit>
    /// The width and height.
    public var size: Size<Unit>
    /// The rectangle at `origin` with `size`.
    public init(origin: Point<Unit>, size: Size<Unit>) { self.origin = origin; self.size = size }
}

/// One value per edge of a rectangle, such as insets.
public struct Edges<Unit> {
    /// The top edge's value.
    public var top: Unit
    /// The right edge's value.
    public var right: Unit
    /// The bottom edge's value.
    public var bottom: Unit
    /// The left edge's value.
    public var left: Unit
    /// Edges with a value each.
    public init(top: Unit, right: Unit, bottom: Unit, left: Unit) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
    /// Edges with the same value `v` on all four.
    public init(all v: Unit) { self.init(top: v, right: v, bottom: v, left: v) }
}

/// One value per corner of a rectangle, such as corner radii.
public struct Corners<Unit> {
    /// The top-left corner's value.
    public var topLeft: Unit
    /// The top-right corner's value.
    public var topRight: Unit
    /// The bottom-right corner's value.
    public var bottomRight: Unit
    /// The bottom-left corner's value.
    public var bottomLeft: Unit
    /// Corners with a value each.
    public init(topLeft: Unit, topRight: Unit, bottomRight: Unit, bottomLeft: Unit) {
        self.topLeft = topLeft; self.topRight = topRight
        self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }
    /// Corners with the same value `v` on all four.
    public init(all v: Unit) { self.init(topLeft: v, topRight: v, bottomRight: v, bottomLeft: v) }
}

/// One value per axis.
public struct Axes<T> {
    /// The horizontal axis's value.
    public var horizontal: T
    /// The vertical axis's value.
    public var vertical: T
    /// Axes with a value each.
    public init(horizontal: T, vertical: T) { self.horizontal = horizontal; self.vertical = vertical }
    /// Axes with the same value `v` on both.
    public init(both v: T) { self.init(horizontal: v, vertical: v) }
}

extension Point: Equatable where Unit: Equatable {}
extension Point: Hashable where Unit: Hashable {}
extension Point: Sendable where Unit: Sendable {}
extension Size: Equatable where Unit: Equatable {}
extension Size: Hashable where Unit: Hashable {}
extension Size: Sendable where Unit: Sendable {}
extension Bounds: Equatable where Unit: Equatable {}
extension Bounds: Hashable where Unit: Hashable {}
extension Bounds: Sendable where Unit: Sendable {}
extension Edges: Equatable where Unit: Equatable {}
extension Edges: Hashable where Unit: Hashable {}
extension Edges: Sendable where Unit: Sendable {}
extension Corners: Equatable where Unit: Equatable {}
extension Corners: Hashable where Unit: Hashable {}
extension Corners: Sendable where Unit: Sendable {}
extension Axes: Equatable where T: Equatable {}
extension Axes: Sendable where T: Sendable {}

extension Bounds where Unit: AdditiveArithmetic {
    /// The left edge's x.
    public var minX: Unit { origin.x }
    /// The top edge's y.
    public var minY: Unit { origin.y }
    /// The right edge's x.
    public var maxX: Unit { origin.x + size.width }
    /// The bottom edge's y.
    public var maxY: Unit { origin.y + size.height }
}

extension Bounds where Unit: AdditiveArithmetic & Comparable {
    /// Half-open on the max edges, so adjacent bounds never both contain a point.
    public func contains(_ p: Point<Unit>) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}
