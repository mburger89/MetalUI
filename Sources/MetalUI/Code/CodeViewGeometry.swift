import MetalUICodeBuffer
import MetalUICore
import MetalUILayout

/// What is under a point of a ``CodeView``, from ``CodeViewGeometry/hit(at:)`` (`CV-AK`).
public struct CodeHit: Equatable, Sendable {
    /// Where a point is, in a ``CodeView``'s terms.
    public enum Region: Equatable, Sendable {
        /// On the text of a buffer row.
        case text
        /// On a buffer row, right of its last character (or on an empty line).
        case pastLineEnd
        /// On a virtual row (``CodeVirtualRow``): not text of the buffer.
        case virtualRow
        /// In the line-number gutter, on any row.
        case gutter
    }

    /// The nearest caret boundary, UTF-8 bytes: exactly what a primary press at the point places the caret at (a virtual
    /// row resolves to the start of the buffer row it sits before).
    public var offset: Int
    /// The grapheme under the point, UTF-8 bytes; `nil` unless the region is ``Region/text`` and the point is on a
    /// character (not left of the shaped text, not on the input method's marked text).
    public var character: Range<Int>?
    /// The buffer row; `nil` on a virtual row.
    public var row: Int?
    /// Where the point is.
    public var region: Region
}

/// Answers "what is at this point" and "where is this range" for a ``CodeView`` (`CV-AJ`, Alloy's LSP hover,
/// diagnostics and completion popups). MetalUI-only (class `M`, no divergence).
///
/// Share one with a view through ``CodeView/geometry(_:)``. The answers are those of **the last frame the view
/// drew**, in that frame's buffer ``version``: between an edit and the next frame they are stale, so map an offset
/// from an older version with ``CodeBuffer/map(_:from:bias:)`` first. Points and rectangles are **view-local with
/// the view's render effects undone** (origin at the view's top-leading corner): the space of
/// ``View/onContinuousHover(coordinateSpace:perform:)`` with `.local` and of ``PopoverAttachmentAnchor/rect(_:)``, so
/// a value passes between them unchanged. Reading it costs nothing and observes nothing; a view with no geometry pays one
/// optional check per frame.
@MainActor
public final class CodeViewGeometry {
    var plan: CodeViewPlan?
    var origin = Point(x: Pixels(0), y: Pixels(0))

    /// An empty geometry, answering nothing until a view has drawn a frame.
    public init() {}

    /// The buffer version of the text the last drawn frame showed (the offsets here are in it); `nil` before a frame.
    public var version: UInt64? { plan?.snapshot.version }

    /// What is under `point` (view-local): the nearest caret boundary, the character, the row and the region. `nil`
    /// before the view has drawn.
    public func hit(at point: Point<Pixels>) -> CodeHit? {
        plan?.hit(at: Point(x: point.x + origin.x, y: point.y + origin.y))
    }

    /// The rectangles of `range` (UTF-8 bytes of ``version``): one per shown row segment, view-local, the height of a
    /// row, not covering the line break. A range outside the shown rows gives none; an empty range gives a zero-width
    /// rectangle at its position when that is shown.
    public func rects(for range: Range<Int>) -> [Bounds<Pixels>] {
        guard let plan else { return [] }
        return plan.rects(forBounds: range).map {
            Bounds(origin: Point(x: $0.origin.x - origin.x, y: $0.origin.y - origin.y), size: $0.size)
        }
    }

    /// The caret's rectangle (the primary selection's head, a point wide as it is painted), view-local, whether or not
    /// the caret is drawn at the moment; `nil` when the head is not on a shown row.
    public func caretRect() -> Bounds<Pixels>? {
        guard let plan, let caret = plan.caretPosition(), caret.top + plan.pitchPx > plan.originY,
              caret.top < plan.originY + plan.heightPx else { return nil }
        let scale = plan.scale
        let width = max(1, Int(Double(scale).rounded()))
        return Bounds(origin: Point(x: Pixels(Float(caret.x) / scale) - origin.x, y: Pixels(Float(caret.top) / scale) - origin.y),
                      size: Size(width: Pixels(Float(width) / scale), height: Pixels(Float(plan.pitchPx) / scale)))
    }

    /// The buffer rows that intersect the view, partially visible ones included; `nil` before a frame or when only
    /// virtual rows are shown.
    public var visibleRows: Range<Int>? {
        guard let plan else { return nil }
        var low: Int?, high = 0
        var i = plan.shownFrom
        while i < plan.shownTo {
            let row = plan.rows[i]
            i += 1
            guard !row.isVirtual else { continue }
            if low == nil { low = row.buffer }
            high = row.buffer + 1
        }
        return low.map { $0..<high }
    }
}

extension CodeView {
    /// Fills `geometry` with this view's last frame (see ``CodeViewGeometry``).
    public func geometry(_ g: CodeViewGeometry) -> CodeView {
        var copy = self
        copy.geometryObject = g
        return copy
    }
}
