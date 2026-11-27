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

/// A paint record's move to the position the occurrence stands at now, **checked and not yet made** (`FS-V`): the device pixels the leaves move by and the
/// fold of the clips the record pushed. Prepaint asks whether the record can move (a refusal there asks for a redo) and builds nothing; the paint decision
/// that takes the hit makes the move in place (`applyPaintTranslation`), so an abandoned attempt copies nothing.
struct PaintTranslation {
    /// The device pixels the leaves move by.
    var dx: Float, dy: Float
    var entryDepth: Int
    var fold: MaskFold?
    /// The entry clip's mask before and after, when the entry clip changed (`FS-Y`); `nil` when it is the same.
    var entry: EntryClipChange?
    /// `Frame.unmovedAxisIsFree` when the move was made (`FS-W`): whether a zero shift skips the sixteenth check of its axis.
    var free = false
}

/// The entry clip of a moved record, folded as a leaf's mask where it stood and where it moves to (`FS-Y`): a leaf read at the entry depth
/// carries exactly `was` and takes `now`.
struct EntryClipChange {
    var was: FoldedClip
    var now: FoldedClip
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

/// Whether `value` moved by `shift` is exact (`FS-W`): both are multiples of 1/16, or the shift is exactly zero and `free`, where the moved
/// number is `value` itself (`shifted`) and no addition rounds. The axis that moves keeps both checks. `free` is `Frame.unmovedAxisIsFree`.
@inline(__always) func isExactShift(_ value: Float, by shift: Float, free: Bool) -> Bool {
    (free && shift == 0) || (isExactSixteenth(value) && isExactSixteenth(value + shift))
}

/// Whether a zero shift may skip its axis's check at `scale` (`FS-W`, `Frame.unmovedAxisIsFree`): a scale that is a multiple of 1/16.
func isUnmovedAxisFree(scale: Float) -> Bool { let s = scale * 16; return s == s.rounded() }

/// `value` moved by `shift`: `value` bit for bit when the shift is exactly zero (`FS-W`), else the sum.
@inline(__always) func shifted(_ value: Float, by shift: Float) -> Float { shift == 0 ? value : value + shift }

// MARK: - The key relation

enum RetainedShape {
    /// The shift of the first top node's origin and of where it lands in window points, or `nil` when the shape differs or
    /// nothing moved (`FS-D`; `allowZero` answers a zero shift, for an occurrence whose entry clip changed instead, `FS-Y`): same node count, same relative signature, same sizes, same origins relative to the first.
    static func shift(newRects: [Float], newNodeCount: Int, newShape: Int, newOffset: [Float],
                      oldRects: [Float], oldNodeCount: Int, oldShape: Int, oldOffset: [Float], allowZero: Bool = false) -> LayoutShift? {
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
        guard allowZero || shift.layoutX != 0 || shift.layoutY != 0 || shift.windowX != 0 || shift.windowY != 0 else { return nil }
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
        return ambient.equalsIgnoringOffset(old.ambient) ? shift : nil
    }

    /// How far this (the new) key's occurrence moved from `old`'s, **possibly not at all**, when the entry clip differs and nothing else but the
    /// origin and the scroll offset does (`FS-Y`); `nil` otherwise, so where `shift(from:)` answers this stays silent.
    func clippedShift(from old: ReplayKey) -> LayoutShift? {
        guard ambient.clip != old.ambient.clip, ambient.clip.count == old.ambient.clip.count else { return nil }
        guard let shift = RetainedShape.shift(newRects: rects, newNodeCount: nodeCount, newShape: shapeInterior,
                                              newOffset: ambient.offset, oldRects: old.rects,
                                              oldNodeCount: old.nodeCount, oldShape: old.shapeInterior,
                                              oldOffset: old.ambient.offset, allowZero: true) else { return nil }
        return ambient.equalsIgnoringOffsetAndClip(old.ambient) ? shift : nil
    }

    /// The layout move and the change of the outer render effects found together (`EL-C`). With equal effect scopes this is
    /// `shift(from:)`, so the layout arm cannot move; with scopes that differ only in effect scopes (the shape half is
    /// `RetainedShape.shift`, untouched) `effect` is the relation of the scopes, a named refusal included. `nil` when nothing moved,
    /// or anything but the origin, the scroll offset and effect scopes differs.
    func shiftAndEffects(from old: ReplayKey, relatingClip: Bool = true) -> CombinedShift<EffectRelation>? {
        if let shift = shift(from: old) ?? (relatingClip ? clippedShift(from: old) : nil) { return CombinedShift(shift: shift, effect: nil) }
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
    /// Sets aside the scroller's offsets: index 7, the primary's, and index 10, a two-axis scroller's horizontal one (`XS-L`) -
    /// the two numbers K2 moves (`FS-D`). The one place the indices are named.
    mutating func zeroScrollOffsets() {
        if scroller.count > 7 { scroller[7] = 0 }
        if scroller.count > 10 { scroller[10] = 0 }
    }

    /// These extras but for the scroller's offsets, which K2 moves (`FS-D`).
    func equalIgnoringScrollOffset(_ other: PrepaintExtras) -> Bool {
        guard scroller.count == other.scroller.count else { return false }
        guard scroller.count > 7 else { return self == other }
        var a = self, b = other
        a.zeroScrollOffsets(); b.zeroScrollOffsets()
        return a == b
    }
}

extension PrepaintKey {
    /// How far the occurrence moved from this ledger's key to `new`, or `nil` (`FS-D`).
    func shift(to new: PrepaintKey) -> LayoutShift? {
        guard let shift = RetainedShape.shift(newRects: new.rects, newNodeCount: new.nodeCount, newShape: new.shapeInterior,
                                              newOffset: new.ambient.offset, oldRects: rects, oldNodeCount: nodeCount,
                                              oldShape: shapeInterior, oldOffset: ambient.offset) else { return nil }
        guard new.ambient.equalsIgnoringOffset(ambient), extras.equalIgnoringScrollOffset(new.extras) else { return nil }
        return shift
    }

    /// How far the occurrence moved from this ledger's key to `new`, possibly not at all, when the entry clip differs and nothing else but
    /// the origin and the scroll offset does (`FS-Y`); `nil` otherwise.
    func clippedShift(to new: PrepaintKey) -> LayoutShift? {
        guard new.ambient.clip != ambient.clip, new.ambient.clip.count == ambient.clip.count else { return nil }
        guard let shift = RetainedShape.shift(newRects: new.rects, newNodeCount: new.nodeCount, newShape: new.shapeInterior,
                                              newOffset: new.ambient.offset, oldRects: rects, oldNodeCount: nodeCount,
                                              oldShape: shapeInterior, oldOffset: ambient.offset, allowZero: true) else { return nil }
        guard new.ambient.equalsIgnoringOffsetAndClip(ambient), extras.equalIgnoringScrollOffset(new.extras) else { return nil }
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
        was.zeroScrollOffsets(); now.zeroScrollOffsets()
        guard was.effects != now.effects else { return nil }
        var restWas = was, restNow = now
        restWas.effects = []; restNow.effects = []
        guard restWas == restNow else { return nil }
        return CombinedShift(shift: shift, effect: now.change(from: was))
    }
}

// MARK: - Moving a paint record

/// A clip a record pushed, folded at one position: the mask and the mask's corner radii a leaf read under it carries, in device pixels.
struct FoldedClip {
    var mask: MUIBounds
    var radii: MUICorners
}

/// The clips of a record folded where it stood and where it moves (`FS-V`), and the walk a leaf takes to the clip it read.
struct MaskFold {
    let clips: [InnerClip]
    let old: [FoldedClip]
    let new: [FoldedClip]

    /// The clip at `depth` on the chain of `push` (itself or the clips it was pushed inside), or `nil`.
    func ancestor(of push: Int, at depth: Int) -> Int? {
        var index = push
        while index >= 0 {
            let at = Int(clips[index].depth)
            if at == depth { return index }
            if at < depth { return nil }
            index = Int(clips[index].parent)
        }
        return nil
    }
}

extension Frame {
    /// The clips `clips` pushed, folded again from the clip in force at the entry (`entryClip`, `entryRadii`, `entryOffset`) with the
    /// first top node's layout origin at `origin`: `pushClip`'s own arithmetic (`Frame.pushedClip`), one push after another. Also
    /// whether the cut of a clip that holds leaves is not the one it was recorded with (`crossingChanged`, `FS-V`).
    static func foldedClips(_ clips: [InnerClip], entryClip: Bounds<Pixels>, entryRadii: Corners<Pixels>, entryOffset: Point<Pixels>,
                            origin: (x: Float, y: Float), scale: Float)
        -> (folded: [FoldedClip], crossingChanged: Bool, crossed: Bool) {
        var states: [(clip: Bounds<Pixels>, radii: Corners<Pixels>, offset: Point<Pixels>)] = []
        states.reserveCapacity(clips.count)
        var folded: [FoldedClip] = []
        folded.reserveCapacity(clips.count)
        var changed = false, crossed = false
        for clip in clips {
            let parent: (clip: Bounds<Pixels>, radii: Corners<Pixels>, offset: Point<Pixels>) =
                clip.parent >= 0 ? states[Int(clip.parent)] : (entryClip, entryRadii, entryOffset)
            let bounds = Bounds(origin: Point(x: Pixels(clip.x + origin.x), y: Pixels(clip.y + origin.y)),
                                size: Size(width: Pixels(clip.width), height: Pixels(clip.height)))
            let radii = Corners(topLeft: Pixels(clip.topLeft), topRight: Pixels(clip.topRight),
                                bottomRight: Pixels(clip.bottomRight), bottomLeft: Pixels(clip.bottomLeft))
            let pushed = pushedClip(bounds, offset: Point(x: Pixels(clip.offsetX), y: Pixels(clip.offsetY)), radii: radii,
                                    activeClip: parent.clip, activeRadii: parent.radii, activeOffset: parent.offset,
                                    atFlatteningEntry: clip.atFlatteningEntry)
            if clip.lo < clip.hi {
                if pushed.crosses != clip.crosses { changed = true } else if clip.crosses { crossed = true }
            }
            states.append((pushed.clip, pushed.radii, pushed.offset))
            folded.append(FoldedClip(mask: MUIBounds(pushed.clip.scaled(by: scale)), radii: MUICorners(pushed.radii.scaled(by: scale))))
        }
        return (folded, changed, crossed)
    }

    /// Whether a zero shift skips the sixteenth check of its axis on this frame (`FS-W`): when the scale is a multiple of 1/16 every product of a
    /// whole-point layout number and the scale is exact in `Float`, so the unmoved axis's numbers are the fresh frame's own. At another scale
    /// (1.2) the unmoved axis's check was also the witness that device numbers are exact products, and it stays.
    var unmovedAxisIsFree: Bool { isUnmovedAxisFree(scale: scaleFactor) }

    /// `isExactShift` with this frame's `unmovedAxisIsFree`.
    func exactShift(_ value: Float, by shift: Float) -> Bool { isExactShift(value, by: shift, free: unmovedAxisIsFree) }

    /// `old`'s leaves moved to the position `key` stands at (`FS-D`, `FS-M`), or the name of the gate that refused. `entryDepth` is the
    /// clip depth of the key and its ambient clip the clip in force at the entry: a primitive whose mask was read at the entry depth
    /// carries the entry clip, equal by the key, and is left alone; one read deeper carries a clip derived inside the occurrence, which
    /// is **folded again** from the clips the record pushed (`FS-V`): the cut of a moved mask is not the moved cut, so the mask and
    /// its radii are what a fresh paint computes at the new position, by `pushClip`'s own arithmetic.
    func movedPaintRecord(_ old: RetainedRecord, to key: ReplayKey) -> TranslationOutcome<PaintTranslation> {
        let s = scaleFactor
        guard key.rects.count >= 2, old.key.rects.count >= 2, key.ambient.offset.count == 2,
              old.key.ambient.offset.count == 2 else { return .refused("unkeyedOrigin") }
        // The first top node's device origin, the arithmetic of `fill`: translate by the offset, then scale.
        let newX = (key.rects[0] + key.ambient.offset[0]) * s, newY = (key.rects[1] + key.ambient.offset[1]) * s
        let oldX = (old.key.rects[0] + old.key.ambient.offset[0]) * s, oldY = (old.key.rects[1] + old.key.ambient.offset[1]) * s
        let dx = newX - oldX, dy = newY - oldY
        guard dx == dx.rounded(), dy == dy.rounded() else { return .refused("fractionalTranslation") }
        // An axis that does not move needs no sixteenth: `newX == oldX` bit for bit, and nothing is added (`FS-W`).
        guard exactShift(oldX, by: dx), exactShift(oldY, by: dy), isExactSixteenth(dx), isExactSixteenth(dy),
              shifted(oldX, by: dx) == newX, shifted(oldY, by: dy) == newY
        else { return .refused("inexactTranslation") }
        if old.innerScopes { return .refused("innerScope") }
        guard key.ambient.clip.count >= 4, !key.ambient.depths.isEmpty else { return .refused("unkeyedClip") }
        let entryDepth = key.ambient.depths[0]
        var entry: EntryClipChange?
        if old.key.ambient.clip != key.ambient.clip {
            // The entry clip changed and nothing else did (`FS-Y`): a leaf read at the entry depth is cut by the new clip, one read deeper is folded from it.
            guard old.key.ambient.clip.count == key.ambient.clip.count else { return .refused("unkeyedClip") }
            entry = EntryClipChange(was: Self.entryMask(old.key.ambient.clip, scale: s), now: Self.entryMask(key.ambient.clip, scale: s))
        }
        var fold: MaskFold?
        if let clips = old.innerClips {
            switch foldedRecord(old, clips: clips, to: key, scale: s) {
            case .refused(let reason): return .refused(reason)
            case .moved(let folded): fold = folded
            }
        }
        let translation = PaintTranslation(dx: dx, dy: dy, entryDepth: entryDepth, fold: fold, entry: entry, free: unmovedAxisIsFree)
        if let reason = Self.moveOps(old, mode: .check, translation).reason { return .refused(reason) }
        return .moved(translation)
    }

    /// The move made, **in place**: the record's leaves, key and final stream are what a fresh paint at `key` makes. The record is the only holder of its
    /// scene (the final stream, which shares it, is let go first and taken again after), so the arrays are written through and nothing is copied.
    /// Only after `movedPaintRecord` answered `.moved` for the same record and key.
    func applyPaintTranslation(_ translation: PaintTranslation, to old: RetainedRecord, key: ReplayKey) {
        let shared = old.finalIsScene
        if shared { old.finalScene = nil }
        _ = Self.moveOps(old, mode: .inPlace, translation)
        old.key = key
        // The final stream moved only where this key holds no outer scope: `movedPaintRecord` may have answered a prepaint's key (its ambient never holds the
        // paint scopes), and a stream moved by the delta alone is the final stream of no effect that scales (`EL-L`).
        old.finalScene = shared && key.ambient.scopes.isEmpty ? old.scene : nil
        old.finalIsScene = old.finalScene != nil
    }

    /// The leaves of `old` as moved, in a new array, for verify mode (the record it compares against stays as it is).
    func copiedPaintTranslation(_ translation: PaintTranslation, of old: RetainedRecord) -> [RetainLog.SceneOp] {
        Self.moveOps(old, mode: .copy, translation).ops
    }

    /// The clip in force at the entry as a leaf carries it: `fill`'s own expression, `activeClip.scaled(by: scaleFactor)` and its radii (`FS-Y`).
    private static func entryMask(_ clip: [Float], scale s: Float) -> FoldedClip {
        let (bounds, radii) = entryClipState(clip)
        return FoldedClip(mask: MUIBounds(bounds.scaled(by: s)), radii: MUICorners(radii.scaled(by: s)))
    }

    /// The entry clip a key holds (`ambient.clip`: the rect, then four corner radii when there are eight numbers) as `pushedClip` reads it.
    static func entryClipState(_ c: [Float]) -> (Bounds<Pixels>, Corners<Pixels>) {
        (Bounds(origin: Point(x: Pixels(c[0]), y: Pixels(c[1])), size: Size(width: Pixels(c[2]), height: Pixels(c[3]))),
         c.count >= 8 ? Corners(topLeft: Pixels(c[4]), topRight: Pixels(c[5]), bottomRight: Pixels(c[6]), bottomLeft: Pixels(c[7]))
                      : Corners(all: Pixels(0)))
    }

    /// The fold of the clips `old` pushed, at the position it was made (from the entry clip it was made under) and at `key`'s (from `key`'s), or
    /// the refusal (`FS-V`, `FS-Y`); the layout origins and every recorded bound are multiples of 1/16, so the origin added back is the layout a
    /// fresh frame computes (`FS-D`).
    private func foldedRecord(_ old: RetainedRecord, clips: [InnerClip], to key: ReplayKey, scale s: Float)
        -> TranslationOutcome<MaskFold> {
        guard isExactSixteenth(key.rects[0]), isExactSixteenth(key.rects[1]),
              isExactSixteenth(old.key.rects[0]), isExactSixteenth(old.key.rects[1]) else { return .refused("inexactTranslation") }
        for clip in clips {
            if clip.isRoot { return .refused("rootClip") }
            guard !clip.isInexact, isExactSixteenth(clip.x), isExactSixteenth(clip.y) else { return .refused("inexactTranslation") }
        }
        let (entryClip, entryRadii) = Self.entryClipState(key.ambient.clip)
        let (oldEntryClip, oldEntryRadii) = Self.entryClipState(old.key.ambient.clip)
        let entryOffset = Point(x: Pixels(key.ambient.offset[0]), y: Pixels(key.ambient.offset[1]))
        let oldOffset = Point(x: Pixels(old.key.ambient.offset[0]), y: Pixels(old.key.ambient.offset[1]))
        let was = Self.foldedClips(clips, entryClip: oldEntryClip, entryRadii: oldEntryRadii, entryOffset: oldOffset,
                                   origin: (old.key.rects[0], old.key.rects[1]), scale: s)
        let now = Self.foldedClips(clips, entryClip: entryClip, entryRadii: entryRadii, entryOffset: entryOffset,
                                   origin: (key.rects[0], key.rects[1]), scale: s)
        if now.crossingChanged { return .refused("maskCrossingChanged") }
        if now.crossed { return .refused("maskCrossed") }
        return .moved(MaskFold(clips: clips, old: was.folded, new: now.folded))
    }

    private enum MoveMode { case check, inPlace, copy }

    /// Walks the record's leaves once: `check` only reads (what a refusal needs), `inPlace` writes each moved leaf over its old one, `copy` builds the moved
    /// ops in a new array. The record's arrays are reached by index and never held, so an in-place write meets a unique buffer.
    private static func moveOps(_ old: RetainedRecord, mode: MoveMode, _ move: PaintTranslation) -> (reason: String?, ops: [RetainLog.SceneOp]) {
        let count = old.scene.count
        var copied: [RetainLog.SceneOp] = []
        if mode == .copy { copied.reserveCapacity(count) }
        let fold = move.fold
        // The innermost clip pushed that is open at each op, found by walking the clips' ranges as the ops go by (`FS-V`).
        var current = -1, next = 0
        for index in 0..<count {
            if let fold {
                while current >= 0, Int(fold.clips[current].hi) <= index { current = Int(fold.clips[current].parent) }
                while next < fold.clips.count, Int(fold.clips[next].lo) <= index {
                    if Int(fold.clips[next].hi) > index { current = next }
                    next += 1
                }
            }
            let opDepth = old.scene[index].depth
            let groups = old.scene[index].leaves.count
            var leaves: [([CapturedPrimitive], [Int]?)] = []
            if mode == .copy { leaves.reserveCapacity(groups) }
            for group in 0..<groups {
                let size = old.scene[index].leaves[group].0.count
                var movedGroup: [CapturedPrimitive] = []
                if mode == .copy { movedGroup.reserveCapacity(size) }
                for member in 0..<size {
                    let primitive = old.scene[index].leaves[group].0[member]
                    let emitted = old.scene[index].leaves[group].1?[member] ?? opDepth
                    switch movedLeaf(primitive, dx: move.dx, dy: move.dy, free: move.free, emittedAt: emitted,
                                     entryDepth: move.entryDepth, fold: fold, entry: move.entry, push: current) {
                    case .refused(let reason): return (reason, [])
                    case .moved(let leaf):
                        switch mode {
                        case .check: break
                        case .inPlace: old.scene[index].leaves[group].0[member] = leaf
                        case .copy: movedGroup.append(leaf)
                        }
                    }
                }
                if mode == .copy { leaves.append((movedGroup, old.scene[index].leaves[group].1)) }
            }
            if mode == .copy { copied.append(RetainLog.SceneOp(boundary: old.scene[index].boundary, leaves: leaves, depth: opDepth)) }
        }
        return (nil, copied)
    }

    /// Whether a recorded mask and radii are exactly what the clip was folded to where the record stood.
    private static func same(_ clip: FoldedClip, _ mask: MUIBounds, _ radii: MUICorners) -> Bool {
        clip.mask.origin.x == mask.origin.x && clip.mask.origin.y == mask.origin.y
            && clip.mask.size.width == mask.size.width && clip.mask.size.height == mask.size.height
            && clip.radii.topLeft == radii.topLeft && clip.radii.topRight == radii.topRight
            && clip.radii.bottomRight == radii.bottomRight && clip.radii.bottomLeft == radii.bottomLeft
    }

    /// One leaf moved by (`dx`, `dy`) device pixels, or the gate that refused. The allow-list is a rect, a glyph and an image
    /// (`FS-E`); every other kind refuses by its name.
    private static func movedLeaf(_ primitive: CapturedPrimitive, dx: Float, dy: Float, free: Bool, emittedAt depth: Int,
                                  entryDepth: Int, fold: MaskFold?, entry: EntryClipChange?, push: Int) -> TranslationOutcome<CapturedPrimitive> {
        guard primitive.transform == nil else { return .refused("transformedPrimitive") }
        func exactMove(_ p: MUIPoint) -> MUIPoint? {
            guard isExactShift(p.x, by: dx, free: free), isExactShift(p.y, by: dy, free: free) else { return nil }
            return MUIPoint(x: shifted(p.x, by: dx), y: shifted(p.y, by: dy))
        }
        /// The primitive's mask and its corner radii after the move: unchanged for the entry clip, the clip it was read under folded
        /// again at the new position for one derived inside (`FS-V`), once the fold at the old position gives what was recorded.
        func movedMask(_ mask: MUIBounds, _ radii: MUICorners) -> TranslationOutcome<(MUIBounds, MUICorners)> {
            guard depth > entryDepth else {
                // Read at the entry depth: the entry clip, cut again where it changed (`FS-Y`) once the old one is what was recorded.
                guard let entry else { return .moved((mask, radii)) }
                guard same(entry.was, mask, radii) else { return .refused("maskNotFolded") }
                return .moved((entry.now.mask, entry.now.radii))
            }
            guard let fold, let clip = fold.ancestor(of: push, at: depth) else { return .refused("maskUnmapped") }
            guard same(fold.old[clip], mask, radii) else { return .refused("maskNotFolded") }
            return .moved((fold.new[clip].mask, fold.new[clip].radii))
        }
        var out = primitive
        for k in out.groups.indices where out.groups[k].isMasked {
            // A mask moves like the content, its own clip by the depth it was read at (`CM-A`); a kind the gate does not list
            // (a path mask) refuses by name.
            for m in out.groups[k].mask.indices {
                var unbounded = false
                switch out.groups[k].mask[m].kind {
                case let .rect(r): unbounded = r.contentMask.size.width >= PrimitiveTransform.unboundedThreshold
                case let .glyph(g): unbounded = g.contentMask.size.width >= PrimitiveTransform.unboundedThreshold
                default: break
                }
                switch movedLeaf(out.groups[k].mask[m], dx: dx, dy: dy, free: free,
                                 emittedAt: unbounded ? entryDepth : out.groups[k].maskDepth,
                                 entryDepth: entryDepth, fold: fold, entry: entry, push: push) {
                case .moved(let mask): out.groups[k].mask[m] = mask
                case .refused(let reason): return .refused(reason)
                }
            }
        }
        switch primitive.kind {
        case .rect(var r):
            guard let origin = exactMove(r.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(r.contentMask, r.maskCornerRadii) {
            case .moved(let (mask, radii)): r.contentMask = mask; r.maskCornerRadii = radii
            case .refused(let reason): return .refused(reason)
            }
            r.bounds.origin = origin
            out.kind = .rect(r)
        case .glyph(var g):
            guard let origin = exactMove(g.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(g.contentMask, g.maskCornerRadii) {
            case .moved(let (mask, radii)): g.contentMask = mask; g.maskCornerRadii = radii
            case .refused(let reason): return .refused(reason)
            }
            g.bounds.origin = origin
            out.kind = .glyph(g)
        case .image(var i, let texture):
            guard let origin = exactMove(i.bounds.origin) else { return .refused("inexactTranslation") }
            switch movedMask(i.contentMask, i.maskCornerRadii) {
            case .moved(let (mask, radii)): i.contentMask = mask; i.maskCornerRadii = radii
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
            RetainedTrace.emit("retained paint translation refused \(RetainedTrace.path(phase.build.key.id)): \(reason)"
                + describeFractionalMove(reason, of: old, to: key))
            stateTable.contentMemos.retained.noteTranslationRefused(reason: reason)
            if RetainedTrace.active { phase.paintNote = "paint translation refused: \(reason)" }
        }
        return outcome
    }
}

// MARK: - Moving a prepaint ledger

extension PrepaintLedger {
    /// Constructions of a ledger (`PrepaintLedger.init`) since the process began, and in-place rebases: `package` counters for the
    /// cost pin of a translated hit (`G47`: a translated cell makes no ledger).
    package nonisolated(unsafe) static var madeCount = 0
    package nonisolated(unsafe) static var rebaseCount = 0

    /// This ledger made over at the position `key` stands at, in place (`G47`): what `rebased(to:_:)` copies, minus the allocation.
    /// Only the parts a translation recomputes change; the rest stands as it was.
    func rebase(to newKey: PrepaintKey, _ moved: LedgerTranslation) {
        Self.rebaseCount += 1
        key = newKey
        hitboxes = moved.hitboxes
        if let accessibility = moved.accessibility {
            axEmissions = accessibility.emissions
            axNodes = accessibility.nodes
            if let locals = accessibility.nodeLocals { axNodeLocals = locals }
        }
        elementBounds = moved.elementBounds
        if let notes = moved.geometry { geometry = notes }
    }

    /// This ledger made over at the position `key` stands at, with the moved registrations (`FS-D`): the next frame at that
    /// position replays it as an exact hit instead of moving it again.
    func rebased(to key: PrepaintKey, _ moved: LedgerTranslation) -> PrepaintLedger {
        let copy = PrepaintLedger(key: key)
        copy.hitboxes = moved.hitboxes
        copy.hitboxChains = hitboxChains
        copy.innerClips = innerClips
        copy.axEmissions = moved.accessibility?.emissions ?? axEmissions
        copy.focus = focus
        copy.axNodes = moved.accessibility?.nodes ?? axNodes
        copy.axNodeLocals = moved.accessibility?.nodeLocals ?? axNodeLocals
        copy.pressOnly = pressOnly
        copy.liveValues = liveValues
        copy.inertBlockers = inertBlockers
        copy.contextMenus = contextMenus
        copy.regions = regions
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
    func movedHitbox(_ hitbox: Hitbox, dx: Float, dy: Float, clip c: Bounds<Pixels>, oldClip: Bounds<Pixels>? = nil, entryDepth: Int, index: Int = 0,
                     fold: inout PrepaintClipFold?) -> TranslationOutcome<Hitbox> {
        func inside(_ b: Bounds<Pixels>, _ clip: Bounds<Pixels>) -> Bool { lies(b, strictlyInside: clip) }
        if hitbox.shape != nil { return .refused("hitboxShape") }
        if hitbox.scroll != nil { return .refused("hitboxScrolls") }
        let h = hitbox.handlers
        if h.textInput != nil || h.valueTrack != nil || h.dropDestination != nil || h.contextual != nil {
            return .refused("hitboxHandlers")
        }
        let b = hitbox.bounds
        guard exactShift(hitbox.origin.x.value, by: dx), exactShift(hitbox.origin.y.value, by: dy)
        else { return .refused("inexactTranslation") }
        if hitbox.clipDepth == entryDepth, let u = hitbox.unclipped {
            // Cut by the ambient clip itself: the cut of the moved rect is recomputed, as `insertHitbox` computes it.
            guard exactShift(u.origin.x.value, by: dx), exactShift(u.origin.y.value, by: dy)
            else { return .refused("inexactTranslation") }
            let movedU = Bounds(origin: Point(x: Pixels(u.origin.x.value + dx), y: Pixels(u.origin.y.value + dy)), size: u.size)
            return .moved(hitbox.moved(dx: dx, dy: dy, bounds: Frame.intersect(c, movedU), unclipped: movedU))
        }
        // Cut by a clip derived inside the occurrence (or unknown): it moves with the occurrence only if it did not touch
        // the ambient clip before and does not after.
        let moved = Bounds(origin: Point(x: Pixels(b.origin.x.value + dx), y: Pixels(b.origin.y.value + dy)), size: b.size)
        let movedU = hitbox.unclipped.map {
            Bounds(origin: Point(x: Pixels($0.origin.x.value + dx), y: Pixels($0.origin.y.value + dy)), size: $0.size)
        }
        // The rect before the move is tested against the clip it was made under, the moved rect against the clip now (`FS-Y`).
        guard inside(b, oldClip ?? c), inside(moved, c) else {
            // Cut by the viewport's edge as well as by a clip the occurrence opened: the clips are folded again (`FS-X`).
            guard fold != nil, let u = hitbox.unclipped, let movedU else { return .refused("hitboxClipped") }
            guard exactShift(u.origin.x.value, by: dx), exactShift(u.origin.y.value, by: dy)
            else { return .refused("inexactTranslation") }
            switch fold?.bounds(ofHitbox: index, depth: hitbox.clipDepth, oldUnclipped: u, oldBounds: b, newUnclipped: movedU) {
            case .moved(let cut)?: return .moved(hitbox.moved(dx: dx, dy: dy, bounds: cut, unclipped: movedU))
            case .refused(let reason)?: return .refused(reason)
            case nil: return .refused("hitboxClipped")
            }
        }
        guard exactShift(b.origin.x.value, by: dx), exactShift(b.origin.y.value, by: dy)
        else { return .refused("inexactTranslation") }
        return .moved(hitbox.moved(dx: dx, dy: dy, bounds: moved, unclipped: movedU))
    }

    /// `ledger`'s registrations moved by `shift` (`FS-F`), or the name of the gate that refused: accessibility emissions and
    /// nodes (their frames are computed boxes), press-only actions, context menus and presentation anchors refuse; so does a
    /// hitbox that sits under a render effect, carries a content shape, scrolls, tracks a value, edits text or takes a drop
    /// (their closures or geometry hold positions the move does not reach), and one the ambient clip may have cut.
    func movedPrepaintLedger(_ ledger: PrepaintLedger, shift: LayoutShift, clip: [Float], to key: PrepaintKey? = nil) -> TranslationOutcome<LedgerTranslation> {
        if !ledger.pressOnly.isEmpty { return .refused("pressOnly") }
        if !ledger.inertBlockers.isEmpty { return .refused("inertChromeBlockers") }
        if !ledger.contextMenus.isEmpty { return .refused("contextMenus") }
        if !ledger.anchors.isEmpty { return .refused("presentationAnchor") }
        guard clip.count >= 4 else { return .refused("unkeyedClip") }
        let entryDepth = ledger.key.ambient.depths.first ?? -1
        let dx = shift.windowX, dy = shift.windowY
        guard isExactSixteenth(dx), isExactSixteenth(dy) else { return .refused("inexactTranslation") }
        let c = Bounds(origin: Point(x: Pixels(clip[0]), y: Pixels(clip[1])),
                       size: Size(width: Pixels(clip[2]), height: Pixels(clip[3])))
        // The clip the ledger was made under: it differs from `clip` when the entry clip changed with the move (`FS-Y`).
        let o = ledger.key.ambient.clip
        let oldClip = o.count >= 4 ? Bounds(origin: Point(x: Pixels(o[0]), y: Pixels(o[1])), size: Size(width: Pixels(o[2]), height: Pixels(o[3]))) : c
        // Accessibility records are recomputed (`RL-H`, was `AT-C`'s refusal) and geometry notes made again (`RL-E`, was `RG-C`'s).
        var fold = key.flatMap { PrepaintClipFold(of: ledger, to: $0) }
        var accessibility: AXTranslation?
        if !ledger.axEmissions.isEmpty || !ledger.axNodes.isEmpty {
            switch movedAccessibility(of: ledger, dx: dx, dy: dy, clip: c, oldClip: oldClip, entryDepth: entryDepth, fold: &fold) {
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
        for (index, hitbox) in ledger.hitboxes.enumerated() {
            if hitbox.transform != nil { return .refused("hitboxUnderEffect") }
            switch movedHitbox(hitbox, dx: dx, dy: dy, clip: c, oldClip: oldClip, entryDepth: entryDepth, index: index, fold: &fold) {
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
            guard exactShift(b.origin.x.value, by: ex), exactShift(b.origin.y.value, by: ey)
            else { return .refused("inexactTranslation") }
            elementBounds.append((id, Bounds(origin: Point(x: Pixels(b.origin.x.value + ex), y: Pixels(b.origin.y.value + ey)),
                                             size: b.size)))
        }
        return .moved(LedgerTranslation(hitboxes: hitboxes, elementBounds: elementBounds, accessibility: accessibility,
                                        geometry: geometry))
    }
}
