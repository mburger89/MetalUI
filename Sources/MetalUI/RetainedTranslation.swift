import Foundation
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes

// C14-d lane 2 (`FS-D`, `FS-E`, `FS-F`, `FS-M`, record 126): translated replay for a layout shift and a scroll. An
// `.equatable()` occurrence whose **shape** (its top rects relative to the first one, its subtree's relative signature,
// its node count) is what its record was made with, whose paint-time ambient is equal but for the scroll offset, and
// whose origin or offset moved, replays at the new position: the recorded leaves are moved by one add, **only** when
// that add is exactly what a fresh paint computes (a whole number of device pixels, every number a multiple of 1/16
// below 2^19). Anything else is refused by name and misses as before (`FrameWork.retainedTranslationRefusedReasons`).
// Spec `docs/superpowers/specs/2026-10-20-finer-scopes-design.md` section 2.

/// How far an occurrence moved between the record (or ledger) and now, in points (`FS-D`): K1 is the first top node's
/// layout origin, K2 the scroll offset the occurrence paints under.
struct LayoutShift: Equatable {
    /// The first top node's layout origin moved by this.
    var layoutX: Float, layoutY: Float
    /// Where the first top node lands in window points (layout origin plus the ambient offset) moved by this: what a
    /// hitbox moves by.
    var windowX: Float, windowY: Float
}

/// The result of an attempt to move a record or a ledger: the moved value, or the name of the gate that refused.
enum TranslationOutcome<Value> {
    case moved(Value)
    case refused(String)
}

/// A paint record moved to the position the occurrence stands at now.
struct PaintTranslation {
    /// The device pixels the leaves moved by.
    var dx: Float, dy: Float
    var scene: [RetainLog.SceneOp]
    /// The record's final stream moved too, when no paint scope is open around the occurrence (its leaves are then the
    /// final primitives); `nil` otherwise.
    var finalScene: [RetainLog.SceneOp]?
}

/// A prepaint ledger moved to the position the occurrence stands at now.
struct LedgerTranslation {
    var hitboxes: [Hitbox]
    var elementBounds: [(GlobalElementID, Bounds<Pixels>)]
    /// The accessibility records recomputed at the new position (`RL-H`), `nil` when the ledger holds none.
    var accessibility: AXTranslation?
    /// The geometry notes made again at the new position (`RL-E`), `nil` when the ledger holds none.
    var geometry: [GeometryNoteRecord]?
}

/// What an occurrence memoises between its prepaint and paint decisions: the paint translation of one record at one shift.
struct PaintTranslationMemo {
    let record: RetainedRecord
    let shift: LayoutShift
    let outcome: TranslationOutcome<PaintTranslation>
}

// MARK: - Exactness

/// Whether `value` is a multiple of 1/16 below 2^19 in magnitude (`FS-D`): such a number, and its sum with another,
/// is exact in `Float`.
@inline(__always) func isExactSixteenth(_ value: Float) -> Bool {
    guard value.isFinite, abs(value) < 524_288 else { return false }
    let scaled = value * 16
    return scaled.rounded(.towardZero) == scaled
}

// MARK: - The key relation

enum RetainedShape {
    /// The shift of the first top node's origin and of where it lands in window points, or `nil` when the shape differs or
    /// nothing moved (`FS-D`): same node count, same relative signature, same sizes, same origins relative to the first.
    static func shift(newRects: [Float], newNodeCount: Int, newShape: Int, newOffset: [Float],
                      oldRects: [Float], oldNodeCount: Int, oldShape: Int, oldOffset: [Float]) -> LayoutShift? {
        guard newNodeCount == oldNodeCount, newShape == oldShape, newRects.count == oldRects.count,
              newRects.count >= 4, newRects.count % 4 == 0,
              newOffset.count == 2, oldOffset.count == 2 else { return nil }
        let ox = newRects[0], oy = newRects[1], px = oldRects[0], py = oldRects[1]
        var index = 4
        while index < newRects.count {
            guard newRects[index + 2] == oldRects[index + 2], newRects[index + 3] == oldRects[index + 3],
                  newRects[index] - ox == oldRects[index] - px, newRects[index + 1] - oy == oldRects[index + 1] - py
            else { return nil }
            index += 4
        }
        guard newRects[2] == oldRects[2], newRects[3] == oldRects[3] else { return nil }
        let shift = LayoutShift(layoutX: ox - px, layoutY: oy - py,
                                windowX: (ox + newOffset[0]) - (px + oldOffset[0]),
                                windowY: (oy + newOffset[1]) - (py + oldOffset[1]))
        guard shift.layoutX != 0 || shift.layoutY != 0 || shift.windowX != 0 || shift.windowY != 0 else { return nil }
        return shift
    }
}

/// The layout move and the effect change of one occurrence found together (`EL-C`, FS-O): `effect == nil` is "the effect scopes are
/// equal", today's layout arm (`shift(from:)`/`shift(to:)` answer it, unchanged); otherwise the shape moved **and** the outer render
/// effects differ, the delta to be applied in the occurrence's own space and the live effect scopes to be re-entered second (`EL-B`).
struct CombinedShift<Effect: Equatable>: Equatable {
    var shift: LayoutShift
    var effect: Effect?
}

extension ReplayKey {
    /// How far this (the new) key's occurrence moved from `old`'s, or `nil` when it did not or the two differ in anything
    /// but the origin and the scroll offset (`FS-D`: K1 and K2, independently or together).
    func shift(from old: ReplayKey) -> LayoutShift? {
        guard let shift = RetainedShape.shift(newRects: rects, newNodeCount: nodeCount, newShape: shapeInterior,
                                              newOffset: ambient.offset, oldRects: old.rects,
                                              oldNodeCount: old.nodeCount, oldShape: old.shapeInterior,
                                              oldOffset: old.ambient.offset) else { return nil }
        var normalized = ambient
        normalized.offset = old.ambient.offset
        return normalized == old.ambient ? shift : nil
    }

    /// The layout move and the change of the outer render effects found together (`EL-C`). With equal effect scopes this is
    /// `shift(from:)`, so the layout arm cannot move; with scopes that differ only in effect scopes (the shape half is
    /// `RetainedShape.shift`, untouched) `effect` is the relation of the scopes, a named refusal included. `nil` when nothing moved,
    /// or anything but the origin, the scroll offset and effect scopes differs.
    func shiftAndEffects(from old: ReplayKey) -> CombinedShift<EffectRelation>? {
        if let shift = shift(from: old) { return CombinedShift(shift: shift, effect: nil) }
        guard let shift = RetainedShape.shift(newRects: rects, newNodeCount: nodeCount, newShape: shapeInterior,
                                              newOffset: ambient.offset, oldRects: old.rects,
                                              oldNodeCount: old.nodeCount, oldShape: old.shapeInterior,
                                              oldOffset: old.ambient.offset),
              let diff = ambient.effectScopeDiff(against: old.ambient), diff.moved else { return nil }
        var normalized = diff.normalized
        normalized.offset = old.ambient.offset
        guard normalized == old.ambient else { return nil }
        if let refusal = diff.refusal { return CombinedShift(shift: shift, effect: .refused(refusal)) }
        var base = ambient
        base.offset = old.ambient.offset
        return CombinedShift(shift: shift, effect: base.scopesDifferOnlyByTranslation(from: old.ambient) ? .translation : .affine)
    }
}

extension PrepaintExtras {
    /// These extras but for the scroller's offset (the vector's index 7), which K2 moves (`FS-D`).
    func equalIgnoringScrollOffset(_ other: PrepaintExtras) -> Bool {
        guard scroller.count == other.scroller.count else { return false }
        guard scroller.count > 7 else { return self == other }
        var a = self, b = other
        a.scroller[7] = 0; b.scroller[7] = 0
        return a == b
    }
}

extension PrepaintKey {
    /// How far the occurrence moved from this ledger's key to `new`, or `nil` (`FS-D`).
    func shift(to new: PrepaintKey) -> LayoutShift? {
        guard let shift = RetainedShape.shift(newRects: new.rects, newNodeCount: new.nodeCount, newShape: new.shapeInterior,
                                              newOffset: new.ambient.offset, oldRects: rects, oldNodeCount: nodeCount,
                                              oldShape: shapeInterior, oldOffset: ambient.offset) else { return nil }
        var normalized = new.ambient
        normalized.offset = ambient.offset
        guard normalized == ambient, extras.equalIgnoringScrollOffset(new.extras) else { return nil }
        return shift
    }

    /// The layout move and the change of the render effects around the occurrence found together (`EL-C`): `shift(to:)` when the
    /// effects are equal, else the shape's shift with `extras.change(from:)` classifying the effects (the scroller's offset, which K2
    /// moves, set aside). `nil` when nothing moved or a part other than the effects (and the scroll offset) differs.
    func shiftAndEffects(to new: PrepaintKey) -> CombinedShift<EffectChange>? {
        if let shift = shift(to: new) { return CombinedShift(shift: shift, effect: nil) }
        guard let shift = RetainedShape.shift(newRects: new.rects, newNodeCount: new.nodeCount, newShape: new.shapeInterior,
                                              newOffset: new.ambient.offset, oldRects: rects, oldNodeCount: nodeCount,
                                              oldShape: shapeInterior, oldOffset: ambient.offset) else { return nil }
        var normalized = new.ambient
        normalized.offset = ambient.offset
        guard normalized == ambient, extras.scroller.count == new.extras.scroller.count else { return nil }
        var was = extras, now = new.extras
        if was.scroller.count > 7 { was.scroller[7] = 0; now.scroller[7] = 0 }
        guard was.effects != now.effects else { return nil }
        var restWas = was, restNow = now
        restWas.effects = []; restNow.effects = []
        guard restWas == restNow else { return nil }
        return CombinedShift(shift: shift, effect: now.change(from: was))
    }
}

// MARK: - Moving a paint record

extension Frame {
    /// `old`'s leaves moved to the position `key` stands at (`FS-D`, `FS-M`), or the name of the gate that refused. `entryClip` and
    /// `entryDepth` are the ambient clip (points) and clip depth of the key: a primitive whose mask was read at the entry depth
    /// carries the entry clip, equal by the key, and is left alone; one read deeper carries a clip derived inside the occurrence,
    /// which moves with it only if it lies strictly inside the entry clip before and after (a mask that touches the entry's edge
    /// may have been cut by it, and the cut of a moved mask is not the moved cut: `maskStraddlesEntryClip`).
    func movedPaintRecord(_ old: RetainedRecord, to key: ReplayKey) -> TranslationOutcome<PaintTranslation> {
        let s = scaleFactor
        guard key.rects.count >= 2, old.key.rects.count >= 2, key.ambient.offset.count == 2,
              old.key.ambient.offset.count == 2 else { return .refused("unkeyedOrigin") }
        // The first top node's device origin, the arithmetic of `fill`: translate by the offset, then scale.
        let newX = (key.rects[0] + key.ambient.offset[0]) * s, newY = (key.rects[1] + key.ambient.offset[1]) * s
        let oldX = (old.key.rects[0] + old.key.ambient.offset[0]) * s, oldY = (old.key.rects[1] + old.key.ambient.offset[1]) * s
        let dx = newX - oldX, dy = newY - oldY
        guard dx == dx.rounded(), dy == dy.rounded() else { return .refused("fractionalTranslation") }
        guard isExactSixteenth(newX), isExactSixteenth(newY), isExactSixteenth(oldX), isExactSixteenth(oldY),
              isExactSixteenth(dx), isExactSixteenth(dy), newX == oldX + dx, newY == oldY + dy
        else { return .refused("inexactTranslation") }
        if old.innerScopes { return .refused("innerScope") }
        guard key.ambient.clip.count >= 4, !key.ambient.depths.isEmpty else { return .refused("unkeyedClip") }
        let clip = key.ambient.clip
        let entry = MUIBounds(origin: MUIPoint(x: clip[0] * s, y: clip[1] * s),
                              size: MUISize(width: clip[2] * s, height: clip[3] * s))
        let entryDepth = key.ambient.depths[0]
        switch Self.movedOps(old.scene, dx: dx, dy: dy, entryDepth: entryDepth, entry: entry) {
        case .refused(let reason): return .refused(reason)
        case .moved(let ops):
            var final: [RetainLog.SceneOp]?
            if let stream = old.finalScene, key.ambient.scopes.isEmpty,
               case .moved(let movedStream) = Self.movedOps(stream, dx: dx, dy: dy, entryDepth: entryDepth, entry: entry) {
                final = movedStream
            }
            return .moved(PaintTranslation(dx: dx, dy: dy, scene: ops, finalScene: final))
        }
    }

    private static func movedOps(_ source: [RetainLog.SceneOp], dx: Float, dy: Float, entryDepth: Int,
                                 entry: MUIBounds) -> TranslationOutcome<[RetainLog.SceneOp]> {
        var ops: [RetainLog.SceneOp] = []
        ops.reserveCapacity(source.count)
        for op in source {
            var leaves: [([CapturedPrimitive], [Int]?)] = []
            leaves.reserveCapacity(op.leaves.count)
            for (group, depths) in op.leaves {
                var moved: [CapturedPrimitive] = []
                moved.reserveCapacity(group.count)
                for index in group.indices {
                    switch movedLeaf(group[index], dx: dx, dy: dy, emittedAt: depths?[index] ?? op.depth,
                                     entryDepth: entryDepth, entry: entry) {
                    case .moved(let primitive): moved.append(primitive)
                    case .refused(let reason): return .refused(reason)
                    }
                }
                leaves.append((moved, depths))
            }
            ops.append(RetainLog.SceneOp(boundary: op.boundary, leaves: leaves, depth: op.depth))
        }
        return .moved(ops)
    }

    private static func strictlyInside(_ m: MUIBounds, _ e: MUIBounds) -> Bool {
        m.origin.x > e.origin.x && m.origin.y > e.origin.y
            && m.origin.x + m.size.width < e.origin.x + e.size.width
            && m.origin.y + m.size.height < e.origin.y + e.size.height
    }

    /// One leaf moved by (`dx`, `dy`) device pixels, or the gate that refused. The allow-list is a rect, a glyph and an image
    /// (`FS-E`); every other kind refuses by its name.
    private static func movedLeaf(_ primitive: CapturedPrimitive, dx: Float, dy: Float, emittedAt depth: Int,
                                  entryDepth: Int, entry: MUIBounds) -> TranslationOutcome<CapturedPrimitive> {
        guard primitive.transform == nil else { return .refused("transformedPrimitive") }
        func exactMove(_ p: MUIPoint) -> MUIPoint? {
            let x = p.x + dx, y = p.y + dy
            guard isExactSixteenth(p.x), isExactSixteenth(p.y), isExactSixteenth(x), isExactSixteenth(y) else { return nil }
            return MUIPoint(x: x, y: y)
        }
        /// The primitive's mask after the move: unchanged for the entry clip, moved for one derived inside.
        func movedMask(_ mask: MUIBounds) -> TranslationOutcome<MUIBounds> {
            guard depth > entryDepth else { return .moved(mask) }
            guard strictlyInside(mask, entry) else { return .refused("maskStraddlesEntryClip") }
            guard let origin = exactMove(mask.origin) else { return .refused("inexactTranslation") }
            let moved = MUIBounds(origin: origin, size: mask.size)
            return strictlyInside(moved, entry) ? .moved(moved) : .refused("maskStraddlesEntryClip")
        }
        var out = primitive
        switch primitive.kind {
        case .rect(var r):
            guard let origin = exactMove(r.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(r.contentMask) {
            case .moved(let mask): r.contentMask = mask
            case .refused(let reason): return .refused(reason)
            }
            r.bounds.origin = origin
            out.kind = .rect(r)
        case .glyph(var g):
            guard let origin = exactMove(g.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(g.contentMask) {
            case .moved(let mask): g.contentMask = mask
            case .refused(let reason): return .refused(reason)
            }
            g.bounds.origin = origin
            out.kind = .glyph(g)
        case .image(var i, let texture):
            guard let origin = exactMove(i.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(i.contentMask) {
            case .moved(let mask): i.contentMask = mask
            case .refused(let reason): return .refused(reason)
            }
            i.bounds.origin = origin
            out.kind = .image(i, texture: texture)
        case .surface: return .refused("unlistedKind:surface")
        case .path: return .refused("unlistedKind:path")
        case .shadow: return .refused("unlistedKind:shadow")
        case .gradient: return .refused("unlistedKind:gradient")
        case .blur: return .refused("unlistedKind:blur")
        case .backdrop: return .refused("unlistedKind:backdrop")
        }
        return .moved(out)
    }

    /// The paint translation of `old` at `shift`, computed once per occurrence per frame (prepaint asks first, paint reuses it)
    /// and counted once when it refuses. `key` supplies the new position and the entry clip.
    func paintTranslation(of old: RetainedRecord, shift: LayoutShift, key: ReplayKey, phase: RetainedPhase)
        -> TranslationOutcome<PaintTranslation> {
        if let memo = phase.paintTranslationMemo, memo.record === old, memo.shift == shift { return memo.outcome }
        let outcome = movedPaintRecord(old, to: key)
        phase.paintTranslationMemo = PaintTranslationMemo(record: old, shift: shift, outcome: outcome)
        if case .refused(let reason) = outcome {
            RetainedTrace.emit("retained paint translation refused \(RetainedTrace.path(phase.build.key.id)): \(reason)")
            stateTable.contentMemos.retained.noteTranslationRefused(reason: reason)
        }
        return outcome
    }
}

// MARK: - Moving a prepaint ledger

extension PrepaintLedger {
    /// This ledger made over at the position `key` stands at, with the moved registrations (`FS-D`): the next frame at that
    /// position replays it as an exact hit instead of moving it again.
    func rebased(to key: PrepaintKey, _ moved: LedgerTranslation) -> PrepaintLedger {
        let copy = PrepaintLedger(key: key)
        copy.hitboxes = moved.hitboxes
        copy.hitboxChains = hitboxChains
        copy.axEmissions = moved.accessibility?.emissions ?? axEmissions
        copy.focus = focus
        copy.axNodes = moved.accessibility?.nodes ?? axNodes
        copy.axNodeLocals = moved.accessibility?.nodeLocals ?? axNodeLocals
        copy.pressOnly = pressOnly
        copy.contextMenus = contextMenus
        copy.elementBounds = moved.elementBounds
        copy.anchors = anchors
        copy.geometry = moved.geometry ?? geometry
        copy.modifiers = modifiers
        copy.tallies = tallies
        copy.prepaints = prepaints
        copy.liveStates = liveStates
        copy.reads = reads
        return copy
    }
}

extension Hitbox {
    /// This hitbox with its clipped rect, its uncut rect and its element origin moved by (`dx`, `dy`) window points.
    func moved(dx: Float, dy: Float, bounds newBounds: Bounds<Pixels>, unclipped newUnclipped: Bounds<Pixels>?) -> Hitbox {
        var h = Hitbox(bounds: newBounds, id: id, layer: layer, opaque: opaque, scroll: scroll, handlers: handlers,
                       origin: Point(x: Pixels(origin.x.value + dx), y: Pixels(origin.y.value + dy)), shape: shape,
                       transform: transform)
        h.contextualEnabled = contextualEnabled
        h.unclipped = newUnclipped
        h.clipDepth = clipDepth
        return h
    }
}

extension Frame {
    /// One hitbox moved by (`dx`, `dy`) in its own (pre-effect) space (`FS-F`, shared with the combined move, `EL-B`): the refusals of
    /// the layout arm (content shape, scroll, a handler whose closure holds a position, an inexact number, a clip the move may
    /// change) by name, the cut by the ambient clip itself recomputed. The transform is not looked at.
    func movedHitbox(_ hitbox: Hitbox, dx: Float, dy: Float, clip c: Bounds<Pixels>, entryDepth: Int) -> TranslationOutcome<Hitbox> {
        func inside(_ b: Bounds<Pixels>) -> Bool {
            b.origin.x.value > c.origin.x.value && b.origin.y.value > c.origin.y.value
                && b.origin.x.value + b.size.width.value < c.origin.x.value + c.size.width.value
                && b.origin.y.value + b.size.height.value < c.origin.y.value + c.size.height.value
        }
        if hitbox.shape != nil { return .refused("hitboxShape") }
        if hitbox.scroll != nil { return .refused("hitboxScrolls") }
        let h = hitbox.handlers
        if h.textInput != nil || h.valueTrack != nil || h.dropDestination != nil || h.contextual != nil {
            return .refused("hitboxHandlers")
        }
        let b = hitbox.bounds
        guard isExactSixteenth(hitbox.origin.x.value), isExactSixteenth(hitbox.origin.y.value),
              isExactSixteenth(hitbox.origin.x.value + dx), isExactSixteenth(hitbox.origin.y.value + dy)
        else { return .refused("inexactTranslation") }
        if hitbox.clipDepth == entryDepth, let u = hitbox.unclipped {
            // Cut by the ambient clip itself: the cut of the moved rect is recomputed, as `insertHitbox` computes it.
            guard isExactSixteenth(u.origin.x.value), isExactSixteenth(u.origin.y.value),
                  isExactSixteenth(u.origin.x.value + dx), isExactSixteenth(u.origin.y.value + dy)
            else { return .refused("inexactTranslation") }
            let movedU = Bounds(origin: Point(x: Pixels(u.origin.x.value + dx), y: Pixels(u.origin.y.value + dy)), size: u.size)
            return .moved(hitbox.moved(dx: dx, dy: dy, bounds: Frame.intersect(c, movedU), unclipped: movedU))
        }
        // Cut by a clip derived inside the occurrence (or unknown): it moves with the occurrence only if it did not touch
        // the ambient clip before and does not after.
        let moved = Bounds(origin: Point(x: Pixels(b.origin.x.value + dx), y: Pixels(b.origin.y.value + dy)), size: b.size)
        guard inside(b), inside(moved) else { return .refused("hitboxClipped") }
        guard isExactSixteenth(b.origin.x.value), isExactSixteenth(b.origin.y.value),
              isExactSixteenth(moved.origin.x.value), isExactSixteenth(moved.origin.y.value)
        else { return .refused("inexactTranslation") }
        let movedU = hitbox.unclipped.map {
            Bounds(origin: Point(x: Pixels($0.origin.x.value + dx), y: Pixels($0.origin.y.value + dy)), size: $0.size)
        }
        return .moved(hitbox.moved(dx: dx, dy: dy, bounds: moved, unclipped: movedU))
    }

    /// `ledger`'s registrations moved by `shift` (`FS-F`), or the name of the gate that refused: accessibility emissions and
    /// nodes (their frames are computed boxes), press-only actions, context menus and presentation anchors refuse; so does a
    /// hitbox that sits under a render effect, carries a content shape, scrolls, tracks a value, edits text or takes a drop
    /// (their closures or geometry hold positions the move does not reach), and one the ambient clip may have cut.
    func movedPrepaintLedger(_ ledger: PrepaintLedger, shift: LayoutShift, clip: [Float]) -> TranslationOutcome<LedgerTranslation> {
        if !ledger.pressOnly.isEmpty { return .refused("pressOnly") }
        if !ledger.contextMenus.isEmpty { return .refused("contextMenus") }
        if !ledger.anchors.isEmpty { return .refused("presentationAnchor") }
        guard clip.count >= 4 else { return .refused("unkeyedClip") }
        let entryDepth = ledger.key.ambient.depths.first ?? -1
        let dx = shift.windowX, dy = shift.windowY
        guard isExactSixteenth(dx), isExactSixteenth(dy) else { return .refused("inexactTranslation") }
        let c = Bounds(origin: Point(x: Pixels(clip[0]), y: Pixels(clip[1])),
                       size: Size(width: Pixels(clip[2]), height: Pixels(clip[3])))
        // Accessibility records are recomputed (`RL-H`, was `AT-C`'s refusal) and geometry notes made again (`RL-E`, was `RG-C`'s).
        var accessibility: AXTranslation?
        if !ledger.axEmissions.isEmpty || !ledger.axNodes.isEmpty {
            switch movedAccessibility(of: ledger, dx: dx, dy: dy, clip: c, entryDepth: entryDepth) {
            case .refused(let reason): return .refused(reason)
            case .moved(let translation): accessibility = translation
            }
        }
        var geometry: [GeometryNoteRecord]?
        if !ledger.geometry.isEmpty {
            switch movedGeometryNotes(ledger.geometry, ledger: ledger, shift: shift) {
            case .refused(let reason): return .refused(reason)
            case .moved(let notes): geometry = notes
            }
        }
        var hitboxes: [Hitbox] = []
        hitboxes.reserveCapacity(ledger.hitboxes.count)
        for hitbox in ledger.hitboxes {
            if hitbox.transform != nil { return .refused("hitboxUnderEffect") }
            switch movedHitbox(hitbox, dx: dx, dy: dy, clip: c, entryDepth: entryDepth) {
            case .refused(let reason): return .refused(reason)
            case .moved(let moved): hitboxes.append(moved)
            }
        }
        // Element bounds are layout rects: the layout shift only, not the scroll offset.
        let ex = shift.layoutX, ey = shift.layoutY
        guard isExactSixteenth(ex), isExactSixteenth(ey) else { return .refused("inexactTranslation") }
        var elementBounds: [(GlobalElementID, Bounds<Pixels>)] = []
        elementBounds.reserveCapacity(ledger.elementBounds.count)
        for (id, b) in ledger.elementBounds {
            guard isExactSixteenth(b.origin.x.value), isExactSixteenth(b.origin.y.value),
                  isExactSixteenth(b.origin.x.value + ex), isExactSixteenth(b.origin.y.value + ey)
            else { return .refused("inexactTranslation") }
            elementBounds.append((id, Bounds(origin: Point(x: Pixels(b.origin.x.value + ex), y: Pixels(b.origin.y.value + ey)),
                                             size: b.size)))
        }
        return .moved(LedgerTranslation(hitboxes: hitboxes, elementBounds: elementBounds, accessibility: accessibility,
                                        geometry: geometry))
    }
}
