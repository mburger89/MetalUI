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
/// Two callers apply it, one per engine, and both must keep applying *this*
/// function rather than a second implementation, or the two engines' rounded
/// rects would drift apart:
///
/// - `computeLayout` in `FlexEngine.swift` calls `roundStoredRects`, which
///   applies this to every node's absolute rect, depth-first, as the last step
///   of layout — after positioning, so every rect it rounds is already
///   root-absolute, which is this function's precondition.
/// - `LayoutTree`'s `roundNativeStoredRects` does the same at the end of a
///   native (proposal) run, recording each node's unrounded width first.
///
/// `NativeGridTests` also rounds its probe's recorded rects through this
/// function, so a grid's expected values live in the same rounded space.
///
/// **What detects a missing rounding pass.** Until plan task 7's stage 7a the
/// WebKit goldens did, through their two non-integral fixtures
/// (`flex_row_shrink`'s 1/64 quantum and `flex_row_seven_equal`'s seventh of
/// 100); stage 7a retired the goldens (record §48). Measured after it, in the
/// full suite at 1616 tests:
///
/// - **Deleting `roundStoredRects`' call from `computeLayout`** reddens 28
///   tests, among them `computeLayoutRoundsEveryStoredRect` and
///   `shrinkIsWeightedByBaseSize` on the legacy engine and every lowering
///   differential that compares the legacy engine's rects with the native
///   ones.
/// - **Deleting `roundNativeStoredRects`' call to this function** reddens 57,
///   among them `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`,
///   `flex_row_seven_equal`'s arm of
///   `equalGrowersShareTheLineAndAMaximumCapsItsGrower` (14/15/14/14/14/15/14)
///   and the cross-platform demo pin `theDemoFrameMatchesTheValuesRecordedOnMacOS`.
///
/// Re-measure these claims rather than trusting them; an earlier version of
/// this comment was wrong about the corpus it described.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
