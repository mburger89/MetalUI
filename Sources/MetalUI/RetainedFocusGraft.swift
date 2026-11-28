// `RK-AS` (record 443): the conjuncts of the graft decision, in a file of their own so `graftRecord` and the lint limits do not grow.

extension Frame {
    /// The first conjunct of the graft decision that fails for this occurrence, named, or `nil` when every one holds (`RK-AS`). Each name is a string literal: no allocation.
    ///
    /// **A focus is a key, not a refusal** (`RK-AS`, amending `RK-AQ` item 3): the graft stands while the focused element under the occurrence now is the one its paint record
    /// and its prepaint ledger were made with (`nil` included). Every focus read the skipped build made is versioned (`TextEditState`, a `@FocusState`'s slot) or a function of
    /// `retainedFocus(under:)` (a table body compares with its own ids), the graft's journal replays the `@FocusState` binding, and the prepaint and the paint of a graft are
    /// replays keyed on the same element (`RK-AQ`). A focus that moves inside the frame makes one of those decisions refuse, which is a redo (`RK-C`), bounded as for `nil` to a focus.
    @inline(never)
    func graftRefusal(entry: ContentMemoStore.Entry, graft: GraftRecord, old: RetainedRecord, ledger: PrepaintLedger,
                      id: GlobalElementID, key: BuildKey) -> String? {
        let memos = stateTable.contentMemos
        // A ledger holding a geometry note a translation cannot recompute would redo the whole frame and back replay off for eight
        // builds (`RG-J`): the refusal stays for such a ledger only (`RL-G`); a recomputable one moves like any other.
        if !geometryNotesRecomputable(ledger) { return "geometryGraft" }
        // `RK-AM`, `RK-AN`: at, under or above the failing occurrences of a scoped redo, or under a scope still quarantined, the build runs.
        if memos.isInRedoScope(id) || memos.isInQuarantinedScope(id) { return "scopedRedo" }
        if entry.quarantineUntil > memos.buildSerial { return "quarantined" }
        if !old.coverageComplete { return "coverage" }
        if old.contentSerial != entry.serial { return "recordSerial" }
        // No `uncomparableCustomCount` conjunct (C14-c4, `FS-H`): an uncomparable custom reading equals nothing, itself
        // included, so `BuildKey.environment` never equals the key a record under it was made with (`graft.key == key`
        // below), and the paint and prepaint refusals leave such an occurrence no record to stand on.
        if graft.key != key { return "buildKey" }
        if let name = prepaintRefusal() { return name }
        if transactionTop.animation != nil { return "animatingTransaction" }
        if !old.versions.allSatisfy({ stateTable.entryVersion($0.0) == $0.1 }) { return "versions" }
        // `RK-AR`: a record painted with a hover reader hovered, or a reader under the pointer where it stands, is not a graft's to stand on; a reader that
        // arrives under a resting pointer is the paint's exact redo (`paintRecord`).
        if retainedSubtreeHasPressOrSelection(under: id) { return "press" }
        if entry.recordHover?.hovered != nil || retainedHoverReaderUnderPointer(ledger.hitboxes, reads: entry.recordHover) { return "hover" }
        // `RK-AS`: the focus under the occurrence at build is the record's and the ledger's.
        let focusNow = retainedFocus(under: id)
        if entry.recordFocus != focusNow || ledger.focusedUnder != focusNow { return "focusMoved" }
        if !graftDependenciesHold(graft) { return "dependencies" }
        return nil
    }
}
