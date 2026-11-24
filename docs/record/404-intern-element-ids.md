# 404: `GlobalElementID` interning (`HP-L`, G33 (c) revived as G47's first fix)

Class `M` (no public API; `IdentityInterner` is `package`), no divergence (labels unchanged, 240 live, next 244). Branch `perf/g47-intern-element-ids`, base master `361c9944`. **Numbering:** 404 is used out of order: it was left free when record 405 landed (404 had belonged to an in-flight record); master's last was 405.

## History

- 2026-11-12/13: G33 (c) built on `perf/intern-element-ids` (a34145db, never merged): an interner for the build-path ids and a deep-tree fixture where chain-walk steps went 20,628 to 0 a frame. Dropped on 2026-11-13 under the "drop anything that doesn't measurably help" rule, because the deep-tree release frame time did not move (walks cost tens of microseconds, under 1% of a frame).
- 2026-11-24: Alloy's 1M-row `Table` scroll (about 11 ms a frame) was reproduced in the `G47Probe` fixture. With `.equatable()` table cells, retained rows look their state and memo entries up by an earlier frame's id, so the chain walk is on the hot path. The first measurement was -0.8 to -0.95 ms a frame (about -10%) with about 0 elsewhere, so the change is revived.

## Change

The original branch merged with `--no-ff` (no rebase); three conflicts (`FocusState.bind`, `GroupMember.enteringGroupMember`, `State.bind`) were master's new signatures (`owner:`, `counted:`) against the one-word change to `internedChild`, resolved by keeping master's body and swapping the call. Nothing else in the interner changed. Review (correctness): `==` is untouched (`===`, then the component walk), the key compares parent identity plus the exact component, a child holds its parent so a key's parent address cannot be reused, `IdentityInterner` is `@MainActor` like every site that calls it, the sweep keeps any slot something else references (checked with `isKnownUniquelyReferenced` after removal, newest first), and the `#if DEBUG` counter is a `nonisolated(unsafe)` static read only by tests. Build sites added to master since the branch was cut (`ComponentAccessibility`, `TableSelection`, `TableBody` editors) still mint through `child(of:)`; that is equal, only unshared.

Added here: `IdentityInterner.minted` (a `package` count the churn tests read) and the ruling/rule wording moved from an unregistered `II-A` to `HP-L`.

## Table bound

`scrollingAMillionRowTableKeepsTheInternTableBounded` scrolls a 1M-row by 20-column table 300 steps of 100 rows (every step builds rows no earlier step built): 159,600 ids minted, the table sits between 1,628 and 2,692 (peak 2,705, window 1,641). With `sweep()` made a no-op the same run reaches 161,241 (every id kept).

## Measured (release, `G47Probe`, shared Mac, load 11 to 13, median CPU ms per scroll step, master vs branch interleaved)

See the PR body for the table; pooled over the eight N<=150 `scrollcells` pairs the paired median delta is -0.65 ms (7 of 8 negative); `scrollcells nest` -0.1 to -1.0; `scroll` and `chat eq` within noise.

## Tests

| Test | Mutation | Reddens |
|---|---|---|
| `theBuildPathEntryPointsReturnOneInstancePerPath` | `interned(component:parent:)` builds a fresh id | itself |
| `aRebuiltDeepTreeWalksNoIdChains` | same | itself (chain steps > 0) |
| `scrollingAMillionRowTableKeepsTheInternTableBounded` | `sweep()` returns at once; or interning off | itself (both bounds / the minted floor) |
| `aChurningTreeDoesNotGrowTheTableWithoutBound`, `aReferencedIdSurvivesTheSweep...` | `sweep()` returns at once | themselves |

No steady-frame cost pin moved (an interned id changes lookup cost, not requests or paints).
