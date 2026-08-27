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
/// **The corpus now detects a missing rounding pass, and it did not always.**
/// An earlier version of this comment said every fixture was integral, that
/// pointing the comparison helpers at `golden.raw` would leave the suite green,
/// and that `computeLayoutRoundsEveryStoredRect` was the only test that could
/// catch a missing pass. All three were measured false during the whole-branch
/// review. What is true, measured at 115 tests and 16 fixtures unless a bullet
/// says otherwise:
///
/// - **Two fixtures are non-integral**: `flex_row_shrink` (WebKit's 1/64
///   quantum puts `a` at 133.328125 and `b` at 66.671875) and
///   `flex_row_seven_equal` (100 split seven ways, 14.28125 each). The other
///   fourteen still have `raw == rounded`.
/// - **Deleting `roundStoredRects`' call from `computeLayout` reddens three
///   tests**: `computeLayoutRoundsEveryStoredRect`, `shrinkIsWeightedByBaseSize`
///   and `shrinkMatchesWebKit`.
/// - **Pointing both golden-comparison helpers at `golden.raw` reddens two** —
///   `shrinkMatchesWebKit` and `sevenEqualChildrenMatchWebKit`, 16 issues,
///   re-measured `--no-parallel` at 342 tests and 61 fixtures. It was **one**
///   until the content-sizing branch's final fix round, and the second is the
///   point: `flex_row_seven_equal` had a golden and no engine comparison at all,
///   so its only reader was `generatorRoundsWhenTheBrowserQuantizes`, which
///   measures the browser and never runs the engine — taxonomy shape 3, and the
///   asymmetry the paragraph below used to describe as live.
///
/// **That hazard is now half-closed rather than open.** The raw/rounded
/// distinction rested on *one* fixture reaching *one* comparison; it rests on
/// two, and the two fail differently (a 1/64 quantum against a seventh of 100).
/// Deleting either alone no longer restores the blind spot, but deleting both —
/// or giving them geometry that divides evenly — still does, and nothing would
/// say so. Re-measure these claims rather than trusting them; they have been
/// wrong once already.
public func roundLayout(_ rects: [LayoutRect]) -> [LayoutRect] {
    rects.map { r in
        let x0 = r.x.rounded()
        let x1 = (r.x + r.width).rounded()
        let y0 = r.y.rounded()
        let y1 = (r.y + r.height).rounded()
        return LayoutRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
