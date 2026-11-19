// The uniform-extent window arithmetic `List` has always used, extracted so a second consumer (`Table`'s rows, `TBL-I`) shares
// it with no behaviour change. `List.window(count:rowExtent:offset:viewport:origin:)` forwards here with its own `overscan`.

/// Windowing a run of `count` equal-extent lines against a scroller's offset and viewport.
enum UniformWindow {
    /// The lines intersecting the viewport, widened by `overscan` on each side and clamped into `0..<count`. Needs `extent > 0`
    /// and `viewport > 0` (the callers' guards).
    ///
    /// **The list-local top is clamped into `0...max(0, extent·count − viewport)`** (`DD-F`): the ambient offset is raw and
    /// unclamped (`ScrollContext`'s own doc), and the origin is where line 0 sits down the scroller's content. At origin 0 that
    /// is the pre-`DD-F` window; with an origin it keeps the window a superset of the lines on screen when the run is partly
    /// above or below the viewport, so a run scrolled past never windows to nothing.
    static func lines(count: Int, extent: Double, offset: Double, viewport: Double, origin: Double,
                      overscan: Int) -> Range<Int> {
        let total = extent * Double(count)
        let top = min(max(0, offset - origin), max(0, total - viewport))
        let rawFirst = Int((top / extent).rounded(.down)) - overscan
        let rawLast = Int(((top + viewport) / extent).rounded(.up)) + overscan
        let first = min(max(0, rawFirst), count)
        let last = min(max(first, rawLast), count)
        return first..<last
    }
}
