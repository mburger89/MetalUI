import MetalUICore
import MetalUILayout
import MetalUIPlatform

// C14-h lane 2 (`RL-E`...`RL-I`, record 131): what a translated replay used to refuse and now carries. Geometry notes are recomputed
// (the proxy is rebuilt from the recorded operands against the translated position and the user's transform runs again, as a fresh
// prepaint would run it), accessibility records of a layout or scroll shift are recomputed from the recorded post-offset rects, and
// the hitbox step walk is shared with `translatedAccessibility` (`Frame.walkEffectSteps`, in `Frame.swift`). Every number is moved
// only when the move is exactly what a fresh prepaint computes (`isExactSixteenth`); anything else is refused by name.

extension Homography2D {
    /// Whether the map is affine and its linear part is made of multiples of 1/16 below 2^19, so a product with an exact-sixteenth translation and the sum
    /// of such products are exact in `Double` whatever the order they are added in (`RL-E`: a named space's map moved by a delta is
    /// bit-equal to the one a fresh prepaint computes).
    fileprivate var hasDyadicLinearPart: Bool {
        isAffine && isExactSixteenth(Float(a)) && isExactSixteenth(Float(b)) && isExactSixteenth(Float(c)) && isExactSixteenth(Float(d))
            && Double(Float(a)) == a && Double(Float(b)) == b && Double(Float(c)) == c && Double(Float(d)) == d
    }
}

extension Frame {
    /// Whether every geometry note of `ledger` can be recomputed by a translated replay, so a graft counting on one cannot cost a
    /// redo for the note's sake (`RL-G`, `RG-J`): no effect opened inside the occurrence (a layout shift moves such an effect's map,
    /// which the recorded steps do not re-derive) and every named space's linear part dyadic.
    func geometryNotesRecomputable(_ ledger: PrepaintLedger) -> Bool {
        let base = ledger.key.extras.effects.count
        for note in ledger.geometry {
            if note.chain.steps.count != base { return false }
            for space in note.namedSpaces where !space.toWindow.hasDyadicLinearPart { return false }
        }
        return true
    }

    /// `notes` made again at the position a layout or scroll shift moved the occurrence to (`RL-E`): `moved` shifts by the window
    /// delta, the effect map in force is unchanged (the ambient is equal by the shift's own key), the proxy is rebuilt and the
    /// transform runs. A note made under an effect the occurrence opened refuses (`geometryUnderEffect`), as does a named space whose
    /// map cannot be moved exactly (`geometryNamedSpace`).
    func movedGeometryNotes(_ notes: [GeometryNoteRecord], ledger: PrepaintLedger, shift: LayoutShift)
        -> TranslationOutcome<[GeometryNoteRecord]> {
        let dx = shift.windowX, dy = shift.windowY
        guard isExactSixteenth(dx), isExactSixteenth(dy) else { return .refused("inexactTranslation") }
        let base = ledger.key.extras.effects.count
        let composed = prepaintEffects.last?.composed
        var out: [GeometryNoteRecord] = []
        out.reserveCapacity(notes.count)
        for note in notes {
            guard note.chain.steps.count == base else { return .refused("geometryUnderEffect") }
            let o = note.moved.origin
            guard exactShift(o.x.value, by: dx), exactShift(o.y.value, by: dy) else { return .refused("inexactTranslation") }
            let moved = Bounds(origin: Point(x: Pixels(o.x.value + dx), y: Pixels(o.y.value + dy)), size: note.moved.size)
            var spaces = note.namedSpaces
            for index in spaces.indices {
                let t = spaces[index].toWindow
                guard t.hasDyadicLinearPart, isExactSixteenth(Float(t.tx)), isExactSixteenth(Float(t.ty)) else {
                    return .refused("geometryNamedSpace")
                }
                let toWindow = Homography2D(a: t.a, b: t.b, c: t.c, d: t.d,
                                        tx: t.tx + t.a * Double(dx) + t.c * Double(dy),
                                        ty: t.ty + t.b * Double(dx) + t.d * Double(dy))
                spaces[index] = NamedSpace(name: spaces[index].name, toSpace: toWindow.inverted, toWindow: toWindow)
            }
            out.append(remade(note, moved: moved, composed: composed, namedSpaces: spaces))
        }
        return .moved(out)
    }

    /// `notes` made again under the render effects now in force, which moved by a translation against the ledger's (`RL-E`, `RK-G`):
    /// `moved` is unchanged, the composed map is the current ambient's (followed through the recorded steps of an effect the
    /// occurrence opened, the walk the accessibility records share), the proxy is rebuilt and the transform runs. A named space
    /// moves with the ambient effect's translation when its linear part is dyadic, else it refuses (`geometryNamedSpace`).
    func translatedGeometryNotes(_ notes: [GeometryNoteRecord], ledger: PrepaintLedger, affine: Bool = false)
        -> TranslationOutcome<[GeometryNoteRecord]> {
        // A named space moves by a translation only, so under a changed linear part a note holding one refuses (`RZ-E`).
        if affine, notes.contains(where: { !$0.namedSpaces.isEmpty }) { return .refused("geometryNamedSpace") }
        guard let ambient = prepaintEffects.last, let recorded = ledger.key.extras.effects.last, recorded.count > PrepaintExtras.effectTy
        else { return .refused("geometryUnrecorded") }
        let base = prepaintEffects.count
        let ex = ambient.composed.tx - recorded[PrepaintExtras.effectTx]
        let ey = ambient.composed.ty - recorded[PrepaintExtras.effectTy]
        var out: [GeometryNoteRecord] = []
        out.reserveCapacity(notes.count)
        for note in notes {
            guard let effect = note.chain.steps.count == base ? ambient
                    : Self.walkEffectSteps(from: ambient, chain: note.chain, base: base) else { return .refused("geometryUnrecorded") }
            var spaces = note.namedSpaces
            for index in spaces.indices {
                let t = spaces[index].toWindow
                guard t.hasDyadicLinearPart, (t.tx + ex) - ex == t.tx, (t.ty + ey) - ey == t.ty else {
                    return .refused("geometryNamedSpace")
                }
                let toWindow = Homography2D(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx + ex, ty: t.ty + ey)
                spaces[index] = NamedSpace(name: spaces[index].name, toSpace: toWindow.inverted, toWindow: toWindow)
            }
            out.append(remade(note, moved: note.moved, composed: effect.composed, namedSpaces: spaces))
        }
        return .moved(out)
    }

    /// `note` with its proxy rebuilt from the given operands and the user's transform run again: the arithmetic of `noteGeometry`.
    private func remade(_ note: GeometryNoteRecord, moved: Bounds<Pixels>, composed: Homography2D?, namedSpaces: [NamedSpace])
        -> GeometryNoteRecord {
        let global = composed.map { $0.boundingBox(of: moved) } ?? moved
        let value = note.watch.transform(GeometryProxy(size: note.size, globalFrame: global, scrolledFrame: moved,
                                                       composed: composed, namedSpaces: namedSpaces))
        return GeometryNoteRecord(watch: note.watch, key: note.key, owner: note.owner, value: value, global: global,
                                  size: note.size, moved: moved, composed: composed, chain: note.chain, namedSpaces: namedSpaces)
    }

    /// `ledger`'s accessibility emissions and nodes moved by a layout or scroll shift (`RL-H`, amending `AT-C`): a frame is the rect
    /// after the active offset, so it moves by the window delta; a visible frame is cut by the clip in force, so a record cut by the
    /// ambient clip itself is cut again against it and one cut by a clip derived inside the occurrence moves only if it stays
    /// strictly inside the ambient clip before and after (the hitbox rule of `movedPrepaintLedger`). A record made under an effect
    /// refuses by name (`accessibilityUnderEffect`): the effect translation owns it (`AT-A`).
    func movedAccessibility(of ledger: PrepaintLedger, dx: Float, dy: Float, clip c: Bounds<Pixels>, entryDepth: Int,
                            fold: inout PrepaintClipFold?) -> TranslationOutcome<AXTranslation> {
        func inside(_ b: Bounds<Pixels>) -> Bool {
            b.origin.x.value > c.origin.x.value && b.origin.y.value > c.origin.y.value
                && b.origin.x.value + b.size.width.value < c.origin.x.value + c.size.width.value
                && b.origin.y.value + b.size.height.value < c.origin.y.value + c.size.height.value
        }
        func exactly(_ b: Bounds<Pixels>) -> Bounds<Pixels>? {
            let x = b.origin.x.value, y = b.origin.y.value
            guard exactShift(x, by: dx), exactShift(y, by: dy) else { return nil }
            return Bounds(origin: Point(x: Pixels(shifted(x, by: dx)), y: Pixels(shifted(y, by: dy))), size: b.size)
        }
        var result = AXTranslation(emissions: ledger.axEmissions, nodes: ledger.axNodes)
        for index in result.emissions.indices {
            let emission = result.emissions[index]
            if emission.local != nil { return .refused("accessibilityUnderEffect") }
            guard let frame = exactly(emission.geometry.frame) else { return .refused("inexactTranslation") }
            let visible: Bounds<Pixels>
            if emission.clipDepth == entryDepth {
                visible = Self.intersect(c, frame)
            } else {
                let old = emission.geometry.visibleFrame
                if inside(old), let moved = exactly(old), inside(moved) {
                    visible = moved
                } else if fold != nil {
                    // Cut by the viewport's edge as well as by a clip the occurrence opened: the clips are folded again (`FS-X`).
                    switch fold?.visibleFrame(ofEmission: index, depth: emission.clipDepth, oldFrame: emission.geometry.frame,
                                              oldVisible: old, newFrame: frame) {
                    case .moved(let now)?: visible = now
                    case .refused(let reason)?: return .refused(reason)
                    case nil: return .refused("accessibilityClipped")
                    }
                } else {
                    return .refused("accessibilityClipped")
                }
            }
            result.emissions[index].geometry.frame = frame
            result.emissions[index].geometry.visibleFrame = visible
        }
        guard ledger.axNodeLocals.count == ledger.axNodes.count else { return .refused("accessibilityUnrecorded") }
        for index in result.nodes.indices {
            if ledger.axNodeLocals[index] != nil { return .refused("accessibilityUnderEffect") }
            guard let frame = exactly(result.nodes[index].1.frame) else { return .refused("inexactTranslation") }
            result.nodes[index].1.frame = frame
        }
        return .moved(result)
    }
}

// MARK: - A layout move under a changed effect (`EL-B`..`EL-G`, FS-O)

/// Whether `b` lies strictly inside `c` (the rule every moved clipped rect obeys: a rect touching the clip's edge may have been cut).
private func lies(_ b: Bounds<Pixels>, strictlyInside c: Bounds<Pixels>) -> Bool {
    b.origin.x.value > c.origin.x.value && b.origin.y.value > c.origin.y.value
        && b.origin.x.value + b.size.width.value < c.origin.x.value + c.size.width.value
        && b.origin.y.value + b.size.height.value < c.origin.y.value + c.size.height.value
}

extension Frame {
    /// `ledger` made over for an occurrence whose layout origin moved by `shift` **and** whose outer render effects changed
    /// (`EL-B`): every recorded rect is in the occurrence's own pre-effect space, so the whole-device-pixel delta is added there
    /// first (hitbox `bounds`/`origin`/`unclipped`, the accessibility locals, a geometry note's `moved`, the element bounds) and the
    /// effect now in force is applied second (the current inverse for a hitbox, the recomputed accessibility frames and geometry
    /// proxies); a fresh frame computes `effect_now(local + delta)`. Presentation anchors, context-menu records and press-only
    /// actions refuse by name (`EL-F`), and so does anything registered inside an effect the occurrence opened
    /// (`effectAndLayoutInner`, `EL-D`: such an effect's map is anchored at the occurrence's own position). The effect change itself
    /// (`.refused`) is the caller's to name.
    func movedCombinedLedger(_ ledger: PrepaintLedger, shift: LayoutShift, clip: [Float], to key: PrepaintKey? = nil) -> TranslationOutcome<LedgerTranslation> {
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
        var fold = key.flatMap { PrepaintClipFold(of: ledger, to: $0) }
        var accessibility: AXTranslation?
        if !ledger.axEmissions.isEmpty || !ledger.axNodes.isEmpty {
            switch shiftedLocals(of: ledger, dx: dx, dy: dy, clip: c, entryDepth: entryDepth, fold: &fold) {
            case .refused(let reason): return .refused(reason)
            case .moved(let shifted):
                switch translatedAccessibility(of: shifted) {
                case .failure(let refusal): return .refused(refusal.reason)
                case .success(var translation):
                    translation.nodeLocals = shifted.axNodeLocals
                    accessibility = translation
                }
            }
        }
        var geometry: [GeometryNoteRecord]?
        if !ledger.geometry.isEmpty {
            switch movedCombinedGeometryNotes(ledger.geometry, ledger: ledger, dx: dx, dy: dy) {
            case .refused(let reason): return .refused(reason)
            case .moved(let notes): geometry = notes
            }
        }
        guard let rederivation = hitboxRederivation(of: ledger) else { return .refused("hitboxes") }
        var hitboxes: [Hitbox] = []
        hitboxes.reserveCapacity(ledger.hitboxes.count)
        for (index, hitbox) in ledger.hitboxes.enumerated() {
            guard let transform = hitbox.transform else { return .refused("hitboxes") }
            // Registered inside an effect the occurrence opened: a chain beyond the ambient, or an inverse that is not the ambient's
            // (no chain recorded) is anchored at the occurrence's position.
            if index < ledger.hitboxChains.count, let chain = ledger.hitboxChains[index], chain.steps.count > rederivation.base {
                return .refused("effectAndLayoutInner")
            }
            if let inverse = transform.inverse, inverse != rederivation.recorded { return .refused("effectAndLayoutInner") }
            let local: Hitbox
            switch movedHitbox(hitbox, dx: dx, dy: dy, clip: c, entryDepth: entryDepth, index: index, fold: &fold) {
            case .refused(let reason): return .refused(reason)
            case .moved(let moved): local = moved
            }
            guard let rederived = rederived(local, at: index, of: ledger, by: nil, using: rederivation) else { return .refused("hitboxes") }
            hitboxes.append(rederived)
        }
        // Element bounds are layout rects: the layout shift only, not the scroll offset (`FS-P`).
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

    /// A copy of `ledger` whose accessibility records' recorded pre-effect rects (`AXLocalRects`) are moved by (`dx`, `dy`) (`EL-G`),
    /// ready for `translatedAccessibility` to recompute the frames against the effect now in force. A frame the clip in force cut
    /// follows the hitbox rule: cut by the ambient clip itself, it is cut again against it; cut by a clip derived inside the
    /// occurrence, it moves only while strictly inside the ambient clip before and after. A record with no recorded rects refuses
    /// `accessibilityUnrecorded`, one made inside an effect the occurrence opened `effectAndLayoutInner`.
    func shiftedLocals(of ledger: PrepaintLedger, dx: Float, dy: Float, clip c: Bounds<Pixels>, entryDepth: Int,
                       fold: inout PrepaintClipFold?) -> TranslationOutcome<PrepaintLedger> {
        let base = ledger.key.extras.effects.count
        func exactly(_ b: Bounds<Pixels>) -> Bounds<Pixels>? {
            let x = b.origin.x.value, y = b.origin.y.value
            guard exactShift(x, by: dx), exactShift(y, by: dy) else { return nil }
            return Bounds(origin: Point(x: Pixels(shifted(x, by: dx)), y: Pixels(shifted(y, by: dy))), size: b.size)
        }
        let copy = ledger.rebased(to: ledger.key, LedgerTranslation(hitboxes: ledger.hitboxes, elementBounds: ledger.elementBounds,
                                                                      accessibility: nil, geometry: nil))
        for index in copy.axEmissions.indices {
            guard var local = copy.axEmissions[index].local else { return .refused("accessibilityUnrecorded") }
            if local.chain.steps.count > base { return .refused("effectAndLayoutInner") }
            guard let frame = exactly(local.frame) else { return .refused("inexactTranslation") }
            if copy.axEmissions[index].clipDepth == entryDepth {
                local.clipped = Self.intersect(c, frame)
            } else {
                if lies(local.clipped, strictlyInside: c), let clipped = exactly(local.clipped), lies(clipped, strictlyInside: c) {
                    local.clipped = clipped
                } else if fold != nil {
                    switch fold?.visibleFrame(ofEmission: index, depth: copy.axEmissions[index].clipDepth, oldFrame: local.frame,
                                              oldVisible: local.clipped, newFrame: frame) {
                    case .moved(let now)?: local.clipped = now
                    case .refused(let reason)?: return .refused(reason)
                    case nil: return .refused("accessibilityClipped")
                    }
                } else {
                    return .refused("accessibilityClipped")
                }
            }
            local.frame = frame
            copy.axEmissions[index].local = local
        }
        guard copy.axNodeLocals.count == copy.axNodes.count else { return .refused("accessibilityUnrecorded") }
        for index in copy.axNodeLocals.indices {
            guard var local = copy.axNodeLocals[index] else { return .refused("accessibilityUnrecorded") }
            if local.chain.steps.count > base { return .refused("effectAndLayoutInner") }
            // A node's rect is read from `frame` alone; `clipped` follows it so a rebased ledger holds one consistent pair.
            guard let frame = exactly(local.frame), let clipped = exactly(local.clipped) else { return .refused("inexactTranslation") }
            local.frame = frame; local.clipped = clipped
            copy.axNodeLocals[index] = local
        }
        return .moved(copy)
    }

    /// `notes` made again for an occurrence moved by (`dx`, `dy`) under an effect that changed (`EL-E`): `moved` shifts by the
    /// delta in the occurrence's own space, then the proxy is rebuilt against the composed effect in force and the transform runs
    /// (`translatedGeometryNotes`' arithmetic). A note that holds a named space refuses `geometryNamedSpace` (it would need the
    /// linear part times the delta plus the effect's own shift), one made inside an effect the occurrence opened
    /// `effectAndLayoutInner`.
    func movedCombinedGeometryNotes(_ notes: [GeometryNoteRecord], ledger: PrepaintLedger, dx: Float, dy: Float)
        -> TranslationOutcome<[GeometryNoteRecord]> {
        guard isExactSixteenth(dx), isExactSixteenth(dy) else { return .refused("inexactTranslation") }
        guard let ambient = prepaintEffects.last else { return .refused("geometryUnrecorded") }
        let base = ledger.key.extras.effects.count
        var out: [GeometryNoteRecord] = []
        out.reserveCapacity(notes.count)
        for note in notes {
            guard note.chain.steps.count == base else { return .refused("effectAndLayoutInner") }
            guard note.namedSpaces.isEmpty else { return .refused("geometryNamedSpace") }
            let o = note.moved.origin
            guard exactShift(o.x.value, by: dx), exactShift(o.y.value, by: dy) else { return .refused("inexactTranslation") }
            let moved = Bounds(origin: Point(x: Pixels(o.x.value + dx), y: Pixels(o.y.value + dy)), size: note.moved.size)
            out.append(remade(note, moved: moved, composed: ambient.composed, namedSpaces: []))
        }
        return .moved(out)
    }
}

// MARK: - A registration cut by a clip its occurrence pushed (`FS-X`)

/// The clips a prepaint ledger recorded (`PrepaintLedger.innerClips`), folded again at the position it was made and at the one it moves to, so a
/// hitbox or accessibility rect cut by a clip the occurrence itself opened moves **exactly** where the viewport edge now cuts it (`FS-V`'s fold,
/// for registrations). Asked only where the strictly-inside rule refuses; holds the array and numbers, allocates nothing.
@MainActor
struct PrepaintClipFold {
    private let clips: [PrepaintClip]
    private let entryClip: Bounds<Pixels>
    private let entryRadii: Corners<Pixels>
    private let oldOffset: Point<Pixels>, newOffset: Point<Pixels>
    private let oldOrigin: (x: Float, y: Float), newOrigin: (x: Float, y: Float)
    /// Whether an origin or a recorded bound is not a multiple of 1/16 (`FS-V`'s guard): the fold then refuses `inexactTranslation`.
    private let inexact: Bool
    private var hitboxCursor = Cursor(), emissionCursor = Cursor()

    /// The innermost open clip at an index, found as the registrations go by in order (`moveOps`' walk).
    private struct Cursor {
        var current = -1, next = 0

        mutating func innermost(at index: Int, in clips: [PrepaintClip], emissions: Bool) -> Int {
            func lo(_ clip: Int) -> Int { Int(emissions ? clips[clip].axLo : clips[clip].clip.lo) }
            func hi(_ clip: Int) -> Int { Int(emissions ? clips[clip].axHi : clips[clip].clip.hi) }
            while current >= 0, hi(current) <= index { current = Int(clips[current].clip.parent) }
            while next < clips.count, lo(next) <= index {
                if hi(next) > index { current = next }
                next += 1
            }
            return current
        }
    }

    /// The fold of `ledger`'s clips between its key and `key`, or `nil` when it holds none or a key is unkeyed.
    init?(of ledger: PrepaintLedger, to key: PrepaintKey) {
        guard let clips = ledger.innerClips, key.rects.count >= 2, ledger.key.rects.count >= 2, key.ambient.clip.count >= 4,
              key.ambient.offset.count == 2, ledger.key.ambient.offset.count == 2 else { return nil }
        self.clips = clips
        let c = key.ambient.clip
        entryClip = Bounds(origin: Point(x: Pixels(c[0]), y: Pixels(c[1])), size: Size(width: Pixels(c[2]), height: Pixels(c[3])))
        entryRadii = c.count >= 8
            ? Corners(topLeft: Pixels(c[4]), topRight: Pixels(c[5]), bottomRight: Pixels(c[6]), bottomLeft: Pixels(c[7]))
            : Corners(all: Pixels(0))
        oldOffset = Point(x: Pixels(ledger.key.ambient.offset[0]), y: Pixels(ledger.key.ambient.offset[1]))
        newOffset = Point(x: Pixels(key.ambient.offset[0]), y: Pixels(key.ambient.offset[1]))
        oldOrigin = (ledger.key.rects[0], ledger.key.rects[1])
        newOrigin = (key.rects[0], key.rects[1])
        var bad = !(isExactSixteenth(oldOrigin.x) && isExactSixteenth(oldOrigin.y) && isExactSixteenth(newOrigin.x)
                    && isExactSixteenth(newOrigin.y))
        for stored in clips where stored.clip.isInexact || !isExactSixteenth(stored.clip.x) || !isExactSixteenth(stored.clip.y) { bad = true }
        inexact = bad
    }

    /// The clip `index` (of the clips) folded from the entry clip, root first, with the arithmetic of `pushClip` (`Frame.pushedClip`): the rect
    /// it cuts to. `nil` for a root clip or one pushed at a flattening entry, whose parent is in another space.
    static func foldedClipRect(_ clips: [PrepaintClip], at index: Int, entryClip: Bounds<Pixels>, entryRadii: Corners<Pixels>,
                               entryOffset: Point<Pixels>, origin: (x: Float, y: Float)) -> Bounds<Pixels>? {
        state(clips, at: index, entryClip: entryClip, entryRadii: entryRadii, entryOffset: entryOffset, origin: origin)?.clip
    }

    private static func state(_ clips: [PrepaintClip], at index: Int, entryClip: Bounds<Pixels>, entryRadii: Corners<Pixels>,
                              entryOffset: Point<Pixels>, origin: (x: Float, y: Float))
        -> (clip: Bounds<Pixels>, radii: Corners<Pixels>, offset: Point<Pixels>)? {
        let c = clips[index].clip
        if c.isRoot || c.atFlatteningEntry { return nil }
        let parent: (clip: Bounds<Pixels>, radii: Corners<Pixels>, offset: Point<Pixels>)
        if c.parent >= 0 {
            guard Int(c.parent) < index, let up = state(clips, at: Int(c.parent), entryClip: entryClip, entryRadii: entryRadii,
                                                        entryOffset: entryOffset, origin: origin) else { return nil }
            parent = up
        } else {
            parent = (entryClip, entryRadii, entryOffset)
        }
        let bounds = Bounds(origin: Point(x: Pixels(c.x + origin.x), y: Pixels(c.y + origin.y)),
                            size: Size(width: Pixels(c.width), height: Pixels(c.height)))
        let radii = Corners(topLeft: Pixels(c.topLeft), topRight: Pixels(c.topRight),
                            bottomRight: Pixels(c.bottomRight), bottomLeft: Pixels(c.bottomLeft))
        let pushed = Frame.pushedClip(bounds, offset: Point(x: Pixels(c.offsetX), y: Pixels(c.offsetY)), radii: radii,
                                      activeClip: parent.clip, activeRadii: parent.radii, activeOffset: parent.offset,
                                      atFlatteningEntry: false)
        return (pushed.clip, pushed.radii, pushed.offset)
    }

    private static func same(_ a: Bounds<Pixels>, _ b: Bounds<Pixels>) -> Bool {
        a.origin.x.value == b.origin.x.value && a.origin.y.value == b.origin.y.value
            && a.size.width.value == b.size.width.value && a.size.height.value == b.size.height.value
    }

    /// The clip cutting the registration at `index` (of `emissions` or of the hitboxes), folded where it was made and where it moves to.
    /// The fold at the old position must give the rect that was recorded (`recorded`, cut from `uncut`), else the registration refuses
    /// `notFolded`; one whose innermost clip is not at its own depth, or is none, refuses `unmapped`.
    private mutating func folded(at index: Int, depth: Int, emissions: Bool, uncut: Bounds<Pixels>, recorded: Bounds<Pixels>,
                                 unmapped: String, notFolded: String) -> TranslationOutcome<Bounds<Pixels>> {
        if inexact { return .refused("inexactTranslation") }
        let found = emissions ? emissionCursor.innermost(at: index, in: clips, emissions: true)
                              : hitboxCursor.innermost(at: index, in: clips, emissions: false)
        guard found >= 0, Int(clips[found].clip.depth) == depth else { return .refused(unmapped) }
        guard let was = Self.foldedClipRect(clips, at: found, entryClip: entryClip, entryRadii: entryRadii, entryOffset: oldOffset,
                                            origin: oldOrigin),
              let now = Self.foldedClipRect(clips, at: found, entryClip: entryClip, entryRadii: entryRadii, entryOffset: newOffset,
                                            origin: newOrigin)
        else { return .refused("rootClip") }
        guard Self.same(Frame.intersect(was, uncut), recorded) else { return .refused(notFolded) }
        return .moved(now)
    }

    /// The visible frame of the emission at `index` after the move: `frame` (the moved frame) cut by the clip folded at the new position.
    mutating func visibleFrame(ofEmission index: Int, depth: Int, oldFrame: Bounds<Pixels>, oldVisible: Bounds<Pixels>,
                               newFrame: Bounds<Pixels>) -> TranslationOutcome<Bounds<Pixels>> {
        switch folded(at: index, depth: depth, emissions: true, uncut: oldFrame, recorded: oldVisible,
                      unmapped: "accessibilityUnmapped", notFolded: "accessibilityNotFolded") {
        case .refused(let reason): return .refused(reason)
        case .moved(let now): return .moved(Frame.intersect(now, newFrame))
        }
    }

    /// The clipped rect of the hitbox at `index` after the move: its moved uncut rect cut by the clip folded at the new position.
    mutating func bounds(ofHitbox index: Int, depth: Int, oldUnclipped: Bounds<Pixels>, oldBounds: Bounds<Pixels>,
                         newUnclipped: Bounds<Pixels>) -> TranslationOutcome<Bounds<Pixels>> {
        switch folded(at: index, depth: depth, emissions: false, uncut: oldUnclipped, recorded: oldBounds,
                      unmapped: "hitboxUnmapped", notFolded: "hitboxNotFolded") {
        case .refused(let reason): return .refused(reason)
        case .moved(let now): return .moved(Frame.intersect(now, newUnclipped))
        }
    }
}
