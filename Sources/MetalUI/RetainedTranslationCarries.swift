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
    func translatedGeometryNotes(_ notes: [GeometryNoteRecord], ledger: PrepaintLedger) -> TranslationOutcome<[GeometryNoteRecord]> {
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
