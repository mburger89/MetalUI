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
/// One caller applies it: `LayoutTree`'s `roundNativeStoredRects`, at the end
/// of a native (proposal) run, to every node's absolute rect, depth-first,
/// recording each node's unrounded width first — after positioning, so every
/// rect it rounds is already root-absolute, which is this function's
/// precondition. (Until stage 9 the CSS engine's `computeLayout` applied it
/// too, through `roundStoredRects`, and both engines had to share *this*
/// function; that engine is deleted, `LR-FC`.)
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
/// - **Deleting `roundStoredRects`' call from `computeLayout`** (the CSS
///   engine's, deleted at stage 9) reddened 28
///   tests, among them `computeLayoutRoundsEveryStoredRect` and
///   `shrinkIsWeightedByBaseSize` on the legacy engine and every lowering
///   differential that compares the legacy engine's rects with the native
///   ones. Stage 7b retired those two with the CSS-engine test files (record
///   §49 rows 54 and 112); re-measured after it, at 1482 tests, the same
///   deletion reddens **26** — the lowering differentials alone, among them
///   `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` and
///   `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` (record §49 §6.1,
///   MR1; renamed at stage 9 `aLoweredPaddingLayerInsetsItsContentByEachEdge` and
///   `aLoweredTextLaysOutAndDrawsAtItsNaturalWidth`, record §51 §5.3).
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
