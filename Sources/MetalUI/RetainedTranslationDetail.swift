import Foundation
import MetalUIScene

// `RK-AO` (record 425): what the `inexactTranslation` refusal of a paint record looked at. The refusal counter keeps its one name
// (`FrameWork.retainedTranslationRefusedReasons`); the trace line, which is built only when something listens
// (`RetainedTrace.emit`'s autoclosure), also names the leaf kind, the field, its value and whether the entry offset (the scroll
// offset the occurrence paints under, in device pixels) or the leaf's own origin is the number that is not a multiple of 1/16.
// The description re-reads the gates of `movedPaintRecord`/`movedLeaf` in their order and never decides anything.

extension RetainedTrace {
    /// Refusal details built since a test reset it: stays 0 while nothing listens (the description is an autoclosure's, `PA-J`).
    nonisolated(unsafe) package static var detailsBuilt = 0
}

extension Frame {
    /// The refusal `reason` of `movedPaintRecord(old, to: key)` in detail, as a trace fragment (empty for any reason but the two
    /// fractional ones): `fractionalTranslation` names the axis that moved by a part of a device pixel and which of the layout
    /// origin and the scroll offset made it; `inexactTranslation` is `describeInexactTranslation`.
    func describeFractionalMove(_ reason: String, of old: RetainedRecord, to key: ReplayKey) -> String {
        RetainedTrace.detailsBuilt += 1
        switch reason {
        case "inexactTranslation": return " [\(describeInexactTranslation(of: old, to: key))]"
        case "fractionalTranslation": return " [\(describeFractionalTranslation(of: old, to: key))]"
        default: return ""
        }
    }

    /// `fractionalTranslation`: `entry field=<dx|dy> value=<device pixels> fractional=<entryOffset|layoutOrigin|both>
    /// layoutDeltaPx=(x,y) offsetDeltaPx=(x,y)`, the first top node's move split into what its layout origin and the scroll offset
    /// it paints under each contributed.
    func describeFractionalTranslation(of old: RetainedRecord, to key: ReplayKey) -> String {
        let s = scaleFactor
        guard key.rects.count >= 2, old.key.rects.count >= 2, key.ambient.offset.count == 2,
              old.key.ambient.offset.count == 2 else { return "unkeyed" }
        func fmt(_ v: Float) -> String { String(format: "%.6g", Double(v)) }
        let layout = (key.rects[0] * s - old.key.rects[0] * s, key.rects[1] * s - old.key.rects[1] * s)
        let offset = (key.ambient.offset[0] * s - old.key.ambient.offset[0] * s, key.ambient.offset[1] * s - old.key.ambient.offset[1] * s)
        let dx = (key.rects[0] + key.ambient.offset[0]) * s - (old.key.rects[0] + old.key.ambient.offset[0]) * s
        let dy = (key.rects[1] + key.ambient.offset[1]) * s - (old.key.rects[1] + old.key.ambient.offset[1]) * s
        let (field, value, lay, off) = dx != dx.rounded() ? ("dx", dx, layout.0, offset.0) : ("dy", dy, layout.1, offset.1)
        let who = lay != lay.rounded() ? (off != off.rounded() ? "both" : "layoutOrigin") : "entryOffset"
        return "entry field=\(field) value=\(fmt(value)) fractional=\(who) layoutDeltaPx=(\(fmt(layout.0)),\(fmt(layout.1))) "
            + "offsetDeltaPx=(\(fmt(offset.0)),\(fmt(offset.1)))"
    }

    /// The first number `movedPaintRecord(old, to: key)` found inexact, as a trace fragment:
    /// `entry field=<name> value=<v> fractional=<entryOffset|layoutOrigin|sum> ...` for the gate on the first top node's device
    /// origin, or `leaf=<kind> field=<name> value=<v> move=(dx,dy) fractional=<leaf|sum> entryOffsetPx=(x,y)` for a leaf.
    func describeInexactTranslation(of old: RetainedRecord, to key: ReplayKey) -> String {
        let s = scaleFactor
        guard key.rects.count >= 2, old.key.rects.count >= 2, key.ambient.offset.count == 2,
              old.key.ambient.offset.count == 2 else { return "unkeyed" }
        let newOffset = (key.ambient.offset[0] * s, key.ambient.offset[1] * s)
        let newX = (key.rects[0] + key.ambient.offset[0]) * s, newY = (key.rects[1] + key.ambient.offset[1]) * s
        let oldX = (old.key.rects[0] + old.key.ambient.offset[0]) * s, oldY = (old.key.rects[1] + old.key.ambient.offset[1]) * s
        let dx = newX - oldX, dy = newY - oldY
        func fmt(_ v: Float) -> String { String(format: "%.6g", Double(v)) }
        // (name, the number the gate tests, the layout origin and the scroll offset it is made of, in device pixels)
        let gates: [(String, Float, Float, Float)] = [
            ("newX", newX, key.rects[0] * s, key.ambient.offset[0] * s), ("newY", newY, key.rects[1] * s, key.ambient.offset[1] * s),
            ("oldX", oldX, old.key.rects[0] * s, old.key.ambient.offset[0] * s),
            ("oldY", oldY, old.key.rects[1] * s, old.key.ambient.offset[1] * s),
            ("dx", dx, 0, 0), ("dy", dy, 0, 0)
        ]
        // An axis that does not move is not tested (`FS-W`), as `movedPaintRecord` does.
        for (name, value, origin, offsetPx) in gates where !isExactSixteenth(value) && !(unmovedAxisIsFree && name.hasSuffix("X") && dx == 0)
            && !(unmovedAxisIsFree && name.hasSuffix("Y") && dy == 0) {
            let who = !isExactSixteenth(offsetPx) ? "entryOffset" : !isExactSixteenth(origin) ? "layoutOrigin" : "sum"
            return "entry field=\(name) value=\(fmt(value)) fractional=\(who) entryOffsetPx=(\(fmt(newOffset.0)),\(fmt(newOffset.1)))"
        }
        if shifted(oldX, by: dx) != newX || shifted(oldY, by: dy) != newY { return "entry field=sum fractional=sum" }
        guard key.ambient.clip.count >= 4, !key.ambient.depths.isEmpty else { return "unkeyedClip" }
        let tail = "move=(\(fmt(dx)),\(fmt(dy))) entryOffsetPx=(\(fmt(newOffset.0)),\(fmt(newOffset.1)))"
        for op in old.scene {
            for (group, _) in op.leaves {
                for primitive in group {
                    if let found = Self.firstInexact(in: primitive, dx: dx, dy: dy, free: unmovedAxisIsFree, role: "") { return found + " " + tail }
                }
            }
        }
        return "unlocated"
    }

    /// The first inexact origin of `primitive` in `movedLeaf`'s order (group masks, then the leaf's own origin, then its content
    /// mask), or `nil` when every number passes.
    static func firstInexact(in primitive: CapturedPrimitive, dx: Float, dy: Float, free: Bool = false, role: String) -> String? {
        func fmt(_ v: Float) -> String { String(format: "%.9g", Double(v)) }   // enough digits to show a one-ulp error
        func check(_ kind: String, _ field: String, _ p: MUIPoint) -> String? {
            for (axis, v, d) in [("x", p.x, dx), ("y", p.y, dy)] where !isExactShift(v, by: d, free: free) {   // a zero shift passes (`FS-W`)
                let who = isExactSixteenth(v) ? "sum" : "leaf"
                return "leaf=\(role)\(kind) field=\(field).\(axis) value=\(fmt(v)) fractional=\(who)"
            }
            return nil
        }
        for k in primitive.groups.indices where primitive.groups[k].isMasked {
            for m in primitive.groups[k].mask.indices {
                if let found = firstInexact(in: primitive.groups[k].mask[m], dx: dx, dy: dy, free: free, role: "groupMask.") { return found }
            }
        }
        switch primitive.kind {
        case let .rect(r): return check("rect", "bounds.origin", r.bounds.origin) ?? check("rect", "contentMask.origin", r.contentMask.origin)
        case let .glyph(g): return check("glyph", "bounds.origin", g.bounds.origin) ?? check("glyph", "contentMask.origin", g.contentMask.origin)
        case let .image(i, _): return check("image", "bounds.origin", i.bounds.origin) ?? check("image", "contentMask.origin", i.contentMask.origin)
        default: return nil
        }
    }
}
