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
/// This is Taffy's `round_layout` strategy.
///
/// Two callers apply it today, and both must keep applying *this* function
/// rather than a second implementation, or the corpus comparison below would
/// validate the wrong thing:
///
/// - `roundBoxes` in `GoldenFile.swift` puts browser output into the same
///   rounded space ours is compared in.
/// - `computeLayout` in `FlexEngine.swift` calls `roundStoredRects`, which
///   applies this to every node's absolute rect, depth-first, as the last step
///   of layout — after positioning, so every rect it rounds is already
///   root-absolute, which is this function's precondition.
///
/// Before the engine called it, the comparison above could not detect a missing
/// rounding pass at all: every fixture in the corpus laid out on integral pixel
/// boundaries, so a fixture's raw and rounded boxes were the same numbers, and
/// pointing the test helper at `golden.raw` instead would have left the whole
/// suite green. `flex-grow` splitting 100 across seven items (100/7 each) is the
/// kind of layout where raw and rounded genuinely diverge — see
/// `computeLayoutRoundsEveryStoredRect` in `FlexEngineTests.swift`.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
