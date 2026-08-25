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
/// **Today only the golden generator calls it** — `roundBoxes` in
/// `GoldenFile.swift`, which puts browser output into the same space ours is
/// compared in. `computeLayout` does **not** call it: the engine writes raw,
/// unrounded rects, and the test helper compares those raw rects against
/// `golden.rounded`.
///
/// That comparison currently cannot detect the difference. Every fixture in the
/// corpus lays out on integral pixel boundaries, so a fixture's raw and rounded
/// boxes are the same numbers — pointing the helper at `golden.raw` instead
/// leaves the whole suite green. It stops being green the moment a non-integral
/// layout exists: `flex-grow` splitting 100 across seven items gives 100/7, and
/// then raw and rounded genuinely diverge.
///
/// So once such layouts exist, both sides must apply an identical rounding pass,
/// and it must be *this* function on both sides — a second implementation would
/// drift and the corpus would then validate the wrong thing. Where in the
/// pipeline the engine applies it is a design decision left to the grow/shrink
/// task, which is why it is not wired in here yet.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
