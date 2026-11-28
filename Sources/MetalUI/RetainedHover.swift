// What a retained occurrence's paint reads of the pointer, and the rules that key a replay on it (`RK-AR`, record 442).
//
// The pointer is not a reason to refuse. An occurrence's paint records which element ids it asked `isHovered` about (its readers), and which of
// them was hovered when it painted. The paint replays exactly while that answer is the same; the prepaint predicts the paint's answer from where
// the readers' hitboxes stand. Nothing here is public.

/// The hover reads of one occurrence's paint, nested replays included: the element ids it passed to `isHovered`, and the one of them that was hovered.
struct HoverReads: Equatable {
    /// The most readers one record keeps; above it the record falls back to `wholeSubtree`.
    static let readerLimit = 32

    /// The ids asked, de-duplicated, in the order first asked. Empty when `wholeSubtree` or `byHitbox`.
    var readers: [GlobalElementID] = []
    /// The hovered element when it is a reader (or, for `wholeSubtree`, when it is under the occurrence) as the record was painted: `nil` when no reader was hovered.
    var hovered: GlobalElementID?
    /// The paint asked about more than `readerLimit` elements: every hitbox under the occurrence is a reader and the hovered element under it is the answer. Whether
    /// an occurrence reads this way is a function of its own distinct reads, never of what its siblings replayed.
    var wholeSubtree = false
    /// The paint asked `isHovered(HitboxID)`. An index is not a function of the hovered element (one element may register two hitboxes), so the rule is master's:
    /// the record is not stored while the hovered element is under the occurrence, and misses when it is.
    var byHitbox = false

    /// What the paint reads of the hovered element `hovered` now: the one this record's readers can tell apart from every other.
    func answer(hovered: GlobalElementID?, under occurrence: GlobalElementID) -> GlobalElementID? {
        guard let hovered else { return nil }
        if wholeSubtree || byHitbox { return hovered.isOrDescends(from: occurrence) ? hovered : nil }
        return readers.contains(hovered) ? hovered : nil
    }

    /// Whether `hitbox` could make a reader hovered: a reader is hovered only through its own opaque hitbox.
    func reads(_ hitbox: Hitbox) -> Bool { wholeSubtree || byHitbox || readers.contains(hitbox.id) }
}

extension SubtreeRecorder {
    /// Notes a read of hover for `id` in this recorder's paint. Bounded: at most `HoverReads.readerLimit` ids, then `hoverOverflow`; an id outside the occurrence
    /// is `hoverOutside` whatever else was read.
    func noteHover(_ id: GlobalElementID) {
        if let occurrence, !id.isOrDescends(from: occurrence) { hoverOutside = true }
        if hoverOverflow || hoverByHitbox { return }
        if hoverReaders.last == id || hoverReaders.contains(id) { return }
        if hoverReaders.count == HoverReads.readerLimit { hoverOverflow = true; hoverReaders = []; return }
        hoverReaders.append(id)
    }
}

extension Frame {
    /// `PaintPass.isHovered(GlobalElementID)`: one branch while nothing records.
    func noteHoverRead(_ id: GlobalElementID) {
        guard let log = retainLog else { return }
        for recorder in log.recorders { recorder.noteHover(id) }
    }

    /// `PaintPass.isHovered(HitboxID)`: every open recorder reads by hitbox.
    func noteHoverReadByHitbox() {
        guard let log = retainLog else { return }
        for recorder in log.recorders { recorder.hoverByHitbox = true }
    }

    /// A nested occurrence's paint replayed: what its record read, an enclosing recorder read too (the same distinct reads a fresh paint makes, in the same order).
    @inline(never)
    func noteReplayedHoverReads(_ reads: HoverReads?) {
        guard let reads, let log = retainLog else { return }
        for recorder in log.recorders {
            if reads.byHitbox { recorder.hoverByHitbox = true }
            if reads.wholeSubtree { recorder.hoverOverflow = true; recorder.hoverReaders = [] }
            for id in reads.readers { recorder.noteHover(id) }
        }
    }

    /// The reads of the paint `recorder` covered, and whether it asked about an element outside its occurrence. `nil` reads for an occurrence that read
    /// nothing: no allocation.
    func closedHoverReads(_ recorder: SubtreeRecorder, occurrence: GlobalElementID) -> (reads: HoverReads?, outside: Bool) {
        var reads = HoverReads()
        if recorder.hoverByHitbox {
            reads.byHitbox = true
        } else if recorder.hoverOverflow {
            reads.wholeSubtree = true
        } else if !recorder.hoverReaders.isEmpty {
            reads.readers = recorder.hoverReaders
        } else {
            return (nil, recorder.hoverOutside)
        }
        reads.hovered = reads.answer(hovered: hoveredElement, under: occurrence)
        return (reads, recorder.hoverOutside)
    }

    /// Whether the pointer is over a hitbox of `hitboxes` a hover reader of `reads` owns. No reads or no pointer is `false` with no scan.
    func retainedHoverReaderUnderPointer<C: Collection>(_ hitboxes: C, reads: HoverReads?) -> Bool where C.Element == Hitbox {
        guard let reads, let point = mousePosition else { return false }
        for hitbox in hitboxes where reads.reads(hitbox) && hitbox.contains(point) { return true }
        return false
    }

    /// Whether the prepaint of the occurrence must run for hover (`pointerInLedger`): its record was painted with a reader hovered, or the pointer is over a reader's hitbox.
    func retainedHoverNeedsPrepaint(_ reads: HoverReads?, ledger: PrepaintLedger?) -> Bool {
        guard let reads, let ledger else { return false }
        return reads.hovered != nil || retainedHoverReaderUnderPointer(ledger.hitboxes, reads: reads)
    }

    /// Whether the pressed element, or the selected `Text`, is the component or under it (`SB-F` item 4, narrowed by `RK-AR`): identity is structural, so an element
    /// inside the occurrence has its component's id as an ancestor. Hover is not here: a paint that reads it is keyed on it (`HoverReads`), and nothing in a
    /// prepaint reads it.
    func retainedSubtreeHasPressOrSelection(under id: GlobalElementID) -> Bool {
        if let active = activeElement, active.isOrDescends(from: id) { return true }
        // The selected `Text` misses retained replay as a focused element did (`TXS-B`, `TXS-H`): its highlight and its
        // pending press are state a recorded paint knows nothing of.
        if let selected = textSelection?.id, selected.isOrDescends(from: id) { return true }
        return false
    }
}
