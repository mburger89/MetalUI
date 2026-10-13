// C14b (`SB-A`…`SB-R`): retained subtrees. One record per `.equatable()` occurrence, hung off
// its content-memo entry: the hitboxes, focus registrations, accessibility emissions, scene
// operations and cache touches its prepaint and paint produced, replayed instead of run while
// its replay key is equal. Spec `docs/superpowers/specs/2026-10-13-retained-subtrees-design.md`.

/// The work counters of retained subtrees for one build (`SB-`): work, never time.
package struct RetainedCounters: Sendable, Equatable {
    /// Occurrences whose prepaint and paint were replayed from a record.
    package var hits = 0
    /// Occurrences that ran prepaint and paint and left a record (first sight, or a key,
    /// version or observation that no longer matched).
    package var misses = 0
    /// Occurrences that ran and left no record: a channel outside the replayable set moved
    /// (`SB-J`), or a context the key cannot hold was open.
    package var ineligible = 0
    /// Element prepaints and paints a hit stood for (the conservation law of test 1.1).
    package var skippedPrepaints = 0
    package var skippedPaints = 0
    /// Ledger snapshots taken (four per recorded occurrence).
    package var ledgerSnapshots = 0
    /// Recorded operations replayed (hitboxes, registrations, accessibility records, scene
    /// operations).
    package var replayedOps = 0
    package init() {}
}
