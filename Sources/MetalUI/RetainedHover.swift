// What a retained occurrence's paint reads of the pointer, and the rules that key a replay on it (`RK-AR`, record 442).
//
// The pointer is not a reason to refuse. An occurrence's paint records which element ids it asked `isHovered` about (its readers), and which of
// them was hovered when it painted. The paint replays exactly while that answer is the same; the prepaint predicts the paint's answer from where
// the readers' hitboxes stand. Nothing here is public.

/// The hover reads of one occurrence's paint, nested replays included: the element ids it passed to `isHovered`, and the one of them that was hovered.
struct HoverReads: Equatable {
    /// The most readers one record keeps; above it the record falls back to `wholeSubtree`, the rule before `RK-AR`.
    static let readerLimit = 32
    /// The most reads one frame's log keeps, duplicates included; a frame that reads more falls back to `wholeSubtree` for every recorder it opens or has open.
    static let logLimit = 256

    /// The ids asked, de-duplicated, in the order first asked. Empty when `wholeSubtree`.
    var readers: [GlobalElementID] = []
    /// The hovered element when it is a reader (or, for `wholeSubtree`, when it is under the occurrence) as the record was painted: `nil` when no reader was hovered.
    var hovered: GlobalElementID?
    /// The occurrence read hover in a way an id cannot name (a `HitboxID` query: an index, not a function of the hovered element), or read it
    /// of more elements than `readerLimit`: every hitbox under it is a reader and the hovered element under it is the answer.
    var wholeSubtree = false

    /// What the paint reads of the hovered element `hovered` now: the one this record's readers can tell apart from every other.
    func answer(hovered: GlobalElementID?, under occurrence: GlobalElementID) -> GlobalElementID? {
        guard let hovered else { return nil }
        if wholeSubtree { return hovered.isOrDescends(from: occurrence) ? hovered : nil }
        return readers.contains(hovered) ? hovered : nil
    }

    /// Whether `hitbox` could make a reader hovered: a reader is hovered only through its own opaque hitbox.
    func reads(_ hitbox: Hitbox) -> Bool { wholeSubtree || readers.contains(hitbox.id) }
}

extension RetainLog {
    /// Notes a read of hover for `id` while the recorders are open. Bounded by `HoverReads.logLimit`: past it every open recorder, and every
    /// recorder opened later in the frame, is `wholeSubtree`.
    func noteHover(_ id: GlobalElementID) {
        if hoverSaturated || hoverReads.last == id { return }
        if hoverReads.count >= HoverReads.logLimit { saturateHover(); return }
        hoverReads.append(id)
    }

    /// Every open recorder reads hover by hitbox from here on (an index-keyed query, or a log past its limit).
    func saturateHover() {
        hoverSaturated = true
        for recorder in recorders { recorder.hoverByHitbox = true }
    }
}

extension Frame {
    /// `PaintPass.isHovered(GlobalElementID)`: one branch while nothing records.
    func noteHoverRead(_ id: GlobalElementID) {
        guard let log = retainLog else { return }
        log.noteHover(id)
    }

    /// `PaintPass.isHovered(HitboxID)`: an index into this frame's hitboxes is not a function of the hovered element, so every open recorder reads the whole subtree.
    func noteHoverReadByHitbox() {
        guard let log = retainLog else { return }
        for recorder in log.recorders { recorder.hoverByHitbox = true }
    }

    /// A nested occurrence's paint replayed: what its record read, an enclosing recorder read too.
    @inline(never)
    func noteReplayedHoverReads(_ reads: HoverReads?) {
        guard let reads, let log = retainLog else { return }
        if reads.wholeSubtree { noteHoverReadByHitbox(); return }
        for id in reads.readers { log.noteHover(id) }
    }

    /// The reads of the paint `recorder` covered, and whether it asked about an element outside `occurrence`. `nil` reads for an occurrence that read
    /// nothing: no allocation.
    func closedHoverReads(_ recorder: SubtreeRecorder, occurrence: GlobalElementID) -> (reads: HoverReads?, outside: Bool) {
        guard let log = retainLog else { return (nil, false) }
        var reads = HoverReads()
        var outside = false
        if recorder.hoverByHitbox {
            reads.wholeSubtree = true
        } else if recorder.hoverFrom < log.hoverReads.count {
            for index in recorder.hoverFrom..<log.hoverReads.count {
                let id = log.hoverReads[index]
                if !id.isOrDescends(from: occurrence) { outside = true; continue }
                if reads.readers.contains(id) { continue }
                if reads.readers.count == HoverReads.readerLimit { reads.wholeSubtree = true; reads.readers = []; break }
                reads.readers.append(id)
            }
        }
        guard reads.wholeSubtree || !reads.readers.isEmpty else { return (nil, outside) }
        reads.hovered = reads.answer(hovered: hoveredElement, under: occurrence)
        return (reads, outside)
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
