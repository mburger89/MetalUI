import MetalUICore
import MetalUILayout
import MetalUIPlatform

// C14-h lane 2 (`RL-E`...`RL-I`, record 131): what a translated replay used to refuse and now carries. Geometry notes are recomputed
// (the proxy is rebuilt from the recorded operands against the translated position and the user's transform runs again, as a fresh
// prepaint would run it), accessibility records of a layout or scroll shift are recomputed from the recorded post-offset rects, and
// the hitbox step walk is shared with `translatedAccessibility` (`Frame.walkEffectSteps`, in `Frame.swift`). Every number is moved
// only when the move is exactly what a fresh prepaint computes (`isExactSixteenth`); anything else is refused by name.

extension Affine2D {
    /// Whether the linear part is made of multiples of 1/16 below 2^19, so a product with an exact-sixteenth translation and the sum
    /// of such products are exact in `Double` whatever the order they are added in (`RL-E`: a named space's map moved by a delta is
    /// bit-equal to the one a fresh prepaint computes).
    fileprivate var hasDyadicLinearPart: Bool {
        isExactSixteenth(Float(a)) && isExactSixteenth(Float(b)) && isExactSixteenth(Float(c)) && isExactSixteenth(Float(d))
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
            guard isExactSixteenth(o.x.value), isExactSixteenth(o.y.value),
                  isExactSixteenth(o.x.value + dx), isExactSixteenth(o.y.value + dy) else { return .refused("inexactTranslation") }
            let moved = Bounds(origin: Point(x: Pixels(o.x.value + dx), y: Pixels(o.y.value + dy)), size: note.moved.size)
            var spaces = note.namedSpaces
            for index in spaces.indices {
                let t = spaces[index].toWindow
                guard t.hasDyadicLinearPart, isExactSixteenth(Float(t.tx)), isExactSixteenth(Float(t.ty)) else {
                    return .refused("geometryNamedSpace")
                }
                let toWindow = Affine2D(a: t.a, b: t.b, c: t.c, d: t.d,
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
                let toWindow = Affine2D(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx + ex, ty: t.ty + ey)
                spaces[index] = NamedSpace(name: spaces[index].name, toSpace: toWindow.inverted, toWindow: toWindow)
            }
            out.append(remade(note, moved: note.moved, composed: effect.composed, namedSpaces: spaces))
        }
        return .moved(out)
    }

    /// `note` with its proxy rebuilt from the given operands and the user's transform run again: the arithmetic of `noteGeometry`.
    private func remade(_ note: GeometryNoteRecord, moved: Bounds<Pixels>, composed: Affine2D?, namedSpaces: [NamedSpace])
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
    func movedAccessibility(of ledger: PrepaintLedger, dx: Float, dy: Float, clip c: Bounds<Pixels>, entryDepth: Int)
        -> TranslationOutcome<AXTranslation> {
        func inside(_ b: Bounds<Pixels>) -> Bool {
            b.origin.x.value > c.origin.x.value && b.origin.y.value > c.origin.y.value
                && b.origin.x.value + b.size.width.value < c.origin.x.value + c.size.width.value
                && b.origin.y.value + b.size.height.value < c.origin.y.value + c.size.height.value
        }
        func exactly(_ b: Bounds<Pixels>) -> Bounds<Pixels>? {
            let x = b.origin.x.value, y = b.origin.y.value
            guard isExactSixteenth(x), isExactSixteenth(y), isExactSixteenth(x + dx), isExactSixteenth(y + dy) else { return nil }
            return Bounds(origin: Point(x: Pixels(x + dx), y: Pixels(y + dy)), size: b.size)
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
                guard inside(old), let moved = exactly(old), inside(moved) else { return .refused("accessibilityClipped") }
                visible = moved
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
    func movedCombinedLedger(_ ledger: PrepaintLedger, shift: LayoutShift, clip: [Float]) -> TranslationOutcome<LedgerTranslation> {
        if !ledger.pressOnly.isEmpty { return .refused("pressOnly") }
        if !ledger.contextMenus.isEmpty { return .refused("contextMenus") }
        if !ledger.anchors.isEmpty { return .refused("presentationAnchor") }
        guard clip.count >= 4 else { return .refused("unkeyedClip") }
        let entryDepth = ledger.key.ambient.depths.first ?? -1
        let dx = shift.windowX, dy = shift.windowY
        guard isExactSixteenth(dx), isExactSixteenth(dy) else { return .refused("inexactTranslation") }
        let c = Bounds(origin: Point(x: Pixels(clip[0]), y: Pixels(clip[1])),
                       size: Size(width: Pixels(clip[2]), height: Pixels(clip[3])))
        var accessibility: AXTranslation?
        if !ledger.axEmissions.isEmpty || !ledger.axNodes.isEmpty {
            switch shiftedLocals(of: ledger, dx: dx, dy: dy, clip: c, entryDepth: entryDepth) {
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
            switch movedHitbox(hitbox, dx: dx, dy: dy, clip: c, entryDepth: entryDepth) {
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
            guard isExactSixteenth(b.origin.x.value), isExactSixteenth(b.origin.y.value),
                  isExactSixteenth(b.origin.x.value + ex), isExactSixteenth(b.origin.y.value + ey)
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
    func shiftedLocals(of ledger: PrepaintLedger, dx: Float, dy: Float, clip c: Bounds<Pixels>, entryDepth: Int)
        -> TranslationOutcome<PrepaintLedger> {
        let base = ledger.key.extras.effects.count
        func exactly(_ b: Bounds<Pixels>) -> Bounds<Pixels>? {
            let x = b.origin.x.value, y = b.origin.y.value
            guard isExactSixteenth(x), isExactSixteenth(y), isExactSixteenth(x + dx), isExactSixteenth(y + dy) else { return nil }
            return Bounds(origin: Point(x: Pixels(x + dx), y: Pixels(y + dy)), size: b.size)
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
                guard lies(local.clipped, strictlyInside: c), let clipped = exactly(local.clipped),
                      lies(clipped, strictlyInside: c) else { return .refused("accessibilityClipped") }
                local.clipped = clipped
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
            guard isExactSixteenth(o.x.value), isExactSixteenth(o.y.value),
                  isExactSixteenth(o.x.value + dx), isExactSixteenth(o.y.value + dy) else { return .refused("inexactTranslation") }
            let moved = Bounds(origin: Point(x: Pixels(o.x.value + dx), y: Pixels(o.y.value + dy)), size: note.moved.size)
            out.append(remade(note, moved: moved, composed: ambient.composed, namedSpaces: []))
        }
        return .moved(out)
    }
}
