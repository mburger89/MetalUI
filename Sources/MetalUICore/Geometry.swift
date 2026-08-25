/// A point in a coordinate space parameterised by its unit type.
/// The `Unit` parameter is what prevents mixing logical and device pixels.
public struct Point<Unit> {
    public var x: Unit
    public var y: Unit
    public init(x: Unit, y: Unit) { self.x = x; self.y = y }
}

public struct Size<Unit> {
    public var width: Unit
    public var height: Unit
    public init(width: Unit, height: Unit) { self.width = width; self.height = height }
}

public struct Bounds<Unit> {
    public var origin: Point<Unit>
    public var size: Size<Unit>
    public init(origin: Point<Unit>, size: Size<Unit>) { self.origin = origin; self.size = size }
}

public struct Edges<Unit> {
    public var top: Unit
    public var right: Unit
    public var bottom: Unit
    public var left: Unit
    public init(top: Unit, right: Unit, bottom: Unit, left: Unit) {
        self.top = top; self.right = right; self.bottom = bottom; self.left = left
    }
    public init(all v: Unit) { self.init(top: v, right: v, bottom: v, left: v) }
}

public struct Corners<Unit> {
    public var topLeft: Unit
    public var topRight: Unit
    public var bottomRight: Unit
    public var bottomLeft: Unit
    public init(topLeft: Unit, topRight: Unit, bottomRight: Unit, bottomLeft: Unit) {
        self.topLeft = topLeft; self.topRight = topRight
        self.bottomRight = bottomRight; self.bottomLeft = bottomLeft
    }
    public init(all v: Unit) { self.init(topLeft: v, topRight: v, bottomRight: v, bottomLeft: v) }
}

public struct Axes<T> {
    public var horizontal: T
    public var vertical: T
    public init(horizontal: T, vertical: T) { self.horizontal = horizontal; self.vertical = vertical }
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
    public var minX: Unit { origin.x }
    public var minY: Unit { origin.y }
    public var maxX: Unit { origin.x + size.width }
    public var maxY: Unit { origin.y + size.height }
}

extension Bounds where Unit: AdditiveArithmetic & Comparable {
    /// Half-open on the max edges, so adjacent bounds never both contain a point.
    public func contains(_ p: Point<Unit>) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }
}
