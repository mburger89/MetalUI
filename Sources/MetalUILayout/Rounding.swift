/// An absolutely-positioned box in layout coordinates.
public struct LayoutRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// Round a layout to whole pixels without accumulating error.
///
/// Rounding each width independently loses up to half a pixel per box, and the
/// loss compounds across siblings — three 33.333 children in a 100 row become
/// 99. Rounding the *cumulative* edges instead and taking the difference keeps
/// every boundary exact, so a row always closes on its parent.
///
/// This is Taffy's `round_layout` strategy. The engine and the golden generator
/// must both call this function — a second implementation would drift and the
/// corpus would then validate the wrong thing.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
