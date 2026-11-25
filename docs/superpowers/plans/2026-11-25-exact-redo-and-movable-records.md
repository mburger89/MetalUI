# Exact redo, scoped redo, movable records — plan (Opus, 2026-11-25)

Context: Alloy's bottom-anchored chat transcript (`ScrollView > LazyVStack > ForEach` of `.equatable()` rows with `BlockChrome` = `.background(tint).cornerRadius(8)`) costs ~423 element requests/delta after #429; ~98 when grafting holds. Record 416 (PR #433) attributes it: a grafted row's paint record cannot follow the scroll move (`maskStraddlesEntryClip` — rounded mask straddling the viewport clip; `inexactTranslation` — fractional device-pixel move) → prepaint miss `recordCannotMove` → `requestRedo` (RK-C) → `noteRedo` suspends replay/grafting window-wide for 9 builds (RK-D), quarantines only the failing entry → descendants cascade. A scoped-redo experiment (162 req/delta) was inexact because the abandoned attempt's writes are not rolled back. Separate master bug: after a whole-frame redo, registered element bounds sit 10 pt off a fresh frame's. Memory note: a scoped backoff was tried in #294 and dropped; `RK-D` item 3 still stands.

## What the code says
1. The redo rolls back very little. `Window.buildAndAdoptFrame` (`Sources/MetalUI/Window.swift:2305-2412`) restores the scroll request queue, the `AnimationStore` checkpoint (entries, transitions, matched geometry, lifecycle, timeline), `surfaceRegistry`, and counters (`noteRedo`). It does NOT restore `StateTable`, any class mutated in place, or the glyph atlas. The checkpoint is taken only when `prepaintReplayAllowed && ledgerEntries > 0` (line 2310). Verify mode uses `stateTable.discardEntries(createdSince:)` (line 2427, `StateTable.swift:803`), which only deletes entries the attempt created.
2. Likely cause of the 10 pt bounds difference (inferred; PR 1.1's first test confirms): the redo's layout reads what the abandoned attempt's prepaint wrote. `ScrollView.requestLayout` reads `ScrollState` (`rawOffset`, `viewportExtent`, `layoutFollowsEnd` over the anchor memory; `ScrollView.swift` ~339-353, `DefaultScrollAnchor.swift:97-105`). `LazyStack.requestLayout` peeks `LazyOrigin` (`LazyStack.swift:199`) and plans from its `RowExtentIndex` (`LazyCore.swift:135-180`). The attempt's prepaint wrote these: `ScrollChrome.swift:225-235` (anchor memory `lastEnd`/`lastContent`, clamp, `viewportExtent`), `LazyCore.swift:239-249` (`LazyOrigin` + `extents.record/rebuild/forgetMeasurements`). `RowExtentIndex` is a class (`ListRowExtents.swift:31`) mutated in place; its estimate is the running mean of measured rows (`:76`). So the redo plans the lazy window from this frame's measured extents. One spacing = 10 pt.
3. Likely cause of `aZoomedNodeIsHitWhereItIsDrawn` going red under a scoped redo: glyph-atlas packing order. The abandoned attempt bumps `currentGeneration` and packs glyphs into the shelf packer (`MetalUIScene/Atlas.swift:302, 525-537`); nothing rewinds it.
4. Refusals: `maskStraddlesEntryClip` = `RetainedTranslation.swift:266-273` (mask moved only if strictly inside the entry clip before and after). Real intersection is non-linear: `Frame.intersectReportingCrossing` (`Frame.swift:1444-1495`); per-corner radii (`CM-J`) or a crossing mask scope (`CM-B`, `ClipMask.swift:113-137`). `inexactTranslation` = exact-sixteenth gate (`:201-204`, `:295-308`). Layout rounds rects to whole points (divergence 77); `spriteGlyph` adds `activeOffset*scale` after the atlas lookup (`Frame.swift:3746-3752`), so rasters never depend on scroll offset; only origin arithmetic can be inexact.

## Piece 1: exact rollback (PRs 1.1, 1.2, 1.3 — before any perf work)

| Channel | Written where | Rolled back today | Plan |
|---|---|---|---|
| `StateTable.storage`: ScrollState, `LazyOrigin`, `ListOrigin`, `$ax`/`$focus`/`$anim`, TableBody/CodeView/TextField prepaint writes, `@State` writes from a getter | `withState` (`StateTable.swift:754`), compared form (`:862`), `write` (`:993`), `touchLive` (`:829`) | no | undo log |
| `marked`, `readJournal`, `markJournal` | same funnels | no (RK-U "idempotent" only if production identical) | snapshot at attempt start, truncate journals |
| `producedSlots`, `namedPositions`, `loopExtents`, `windowedParents`, `departedNames` | build | unions (RK-U) | idempotent once inputs exact; pinned by `BuildChannels` (RK-AA) |
| `RowExtentIndex` inside `LazyOrigin`/`ListOrigin` | layout `plan` and prepaint | no (class) | journal inside the index |
| Glyph atlas: `placed`, `keysBySlot`, shelf cursor, `currentGeneration`, packed area | paint | no | atlas attempt bracket |
| ShapingCache, LayoutMemo, RasterCache | build and paint | no (`endFrame` skipped) | pure caches with exact keys: classify, no rollback; check `ShapingCache.beginFrame` does not age entries twice (if so roll back that epoch) |
| AnimationStore, Lifecycle, Timeline, Transition, Matched, Surface | build | yes (RK-U) | unchanged |
| Scroll request queue (incl. `carry`) | layout, prepaint | yes | unchanged |
| `ScrollPositionRegistry.update` (`ScrollPosition.swift:285`) | prepaint | no | overwritten each attempt; `needsReport` merged not consumed; classify idempotent, pin in differential |
| `pendingPositionKnown`, scroll resolutions, anchor adjustments | frame-local | applied only after accepted paint (`Frame.swift:4652-4679`) | nothing |
| ContentMemoStore (`serial`/`pristine`/`stale`, RK-AF records, ledgers rebased in place, `entry.graft = nil` `EquatableComponent.swift:107`, pending grafts) | build/prepaint/paint | partly | valid at the key they hold; classify, no rollback; a lost graft record costs a rebuild only |
| Focus inside render, frame-capacity hints, `lastDrawBuildCount` | window | n/a | idempotent; hints only from adopted frame |
| Observation registrations from attempt 1 | `withObservationTracking`, memo sessions | no | may cost one spurious frame; idle-convergence assertion pins it |

**Mechanism: undo log on first write (chosen over deferred writes and whole-table snapshot).**
- `StateTable.beginAttempt()` armed under the same condition as today's checkpoint (and always in verify mode).
- On the first write of an id while armed, the prior `Entry?` (value, generation, `isLive`, version) goes into `attemptUndo`.
- `rollbackAttempt()` restores each prior entry (or deletes if absent), restores `marked`, truncates the journals.
- `acceptAttempt()` (after adoption, beside `sweep`) clears the log, keeps capacity, shrinks above 1024 entries.
- `versionCounter` stays monotonic; restored entries keep old versions so standing ledgers still match.
- Verify mode replaces `discardEntries(createdSince:)` with the same rollback (amends `RW-U`; re-check its `$ax` exemption).
- Reference state: protocol `AttemptRestorable { beginAttempt; rollbackAttempt; endAttempt }`. `RowExtentIndex` logs `(index, old height, old id)` per `record`; `rebuild`/`forgetMeasurements` move old arrays into the log (O(n) transient only on data/width change, freed at accept). LazyCore, LazyGrid, List register the index via `pass.frame.stateTable.restorable(_:)`.
- `GlyphAtlas.beginAttempt/rollbackAttempt`: log keys inserted while armed plus packer fields and generation; remove/restore. Atlas growth inside an attempt is not undone; count it (`atlasGrowthsInAbandonedAttempts`) and pin 0 in fixtures.
- Why not deferred writes: every peek/read/withState/entryVersion through an overlay = thousands of extra lookups/frame; can't defer in-place class mutation or atlas. Why not whole-table snapshot: COW first write copies O(entries) every armed frame. Undo log costs only on writes; a quiet frame writes nothing (one branch).

**Tests (first; each mutation removes one rollback arm):**
- `theRedoFrameRegistersTheElementBoundsAFreshFrameDoes`: G49 fixture with a forced redo; compare element bounds, name differing ids. Red on master (10 pt). Mutations: undo log off; index journal off.
- `aRolledBackAttemptLeavesEveryStoreAsItFoundIt` (`@testable`): per-channel digest before attempt == after rollback (entries deep digest excluding versions, `marked`, index contents, atlas map and cursor). Arms: chrome transcript, opacity ancestor (RK-C), zoom, mirrored lazy row, variable-row `List`.
- `aRedoneFrameEqualsAFreshFrameInEveryChannel` (window pair): `RPSnapshot`, state digests, `ScrollPositionRegistry`, scroll queue, animation/lifecycle (incl. delivered-events log), timeline cursors, transitions, atlas slots, frames-until-idle; after the redo frame and three frames after.
- With a new package switch `Window.testingRedoBackoff = false`, these must be green: `aMirroredScrollersGrowing…`, `aZoomedNodeIsHitWhereItIsDrawn`, `BackgroundProminenceTests`. A count pin that moves only because replay now runs where backoff suppressed it gets its literal updated with the reason.
- `everyFrameChannelIsClassified` gains rows; new census `everyReferenceHeldInStateIsClassified` (every class type in entries across demo windows: restorable, cache, or immutable).
- Verify mode (`METALUI_VERIFY_RETAINED=1`) gains channel `rollback` (digest before attempt vs after rollback, trap by entry).
- Steady-frame cost: `aQuietFrameWithAnArmedRollbackLogsNothing` (4 requests, empty log, `aNonAnimatableComponentAllocatesWhatItDid` unchanged), `aStreamingFrameLogsOneEntryPerWrittenState`, `anAbandonedAttemptsGlyphsArePackedOnce`.

PRs: 1.1 StateTable undo log + index journal; 1.2 atlas; 1.3 verify-mode digest, census, suite green with backoff off.
Rulings: `RK-AH`* (rollback contract; amends RK-D, RK-M, RK-U), `RK-AI` (in-place reference state owes `AttemptRestorable`), `GL-K` (atlas attempt bracket). *Check the RK decisions doc's last heading for the real next id — #428 already used `RK-AH`.
Rules-shard line: "A store an attempt writes before `requestRedo` owes an undo entry or a classification; a class mutated in place in a state entry is `AttemptRestorable`."
Effect on Alloy: ~423 unchanged (correctness only). Cost: ~56 B per distinct written id per armed frame; ~24 B per recorded extent; atlas log one key per new glyph; time one hash insert per first write. Report phys_footprint + allocations per PR (release G49Probe method from record 414, 120 words, 3 interleaved runs).

## Piece 2: scoped redo (one PR, after 1.3 green)
- `Frame.redoScopes` = failing occurrences' ids. After rollback, attempt 2 runs with `memos.scopedRedo`: `graftRecord(for:)` and `retainedPrepaintDecisionInner` refuse (`scopedRedo`) for any id that `isOrDescends(from:)` a scope; everything else grafts/replays as in attempt 1.
- Descendants quarantined together: `ContentMemoStore.quarantinedScopes`, at most 64 `(id, until)`, same ancestry test; entry doubling (8·2^k, reset on hit) applies to the scope.
- `noteRedo` no longer sets `prepaintSuspendedUntil`.
- Exact because after exact rollback attempt 2 is a legal build with fewer grafts (RK-Y, SB-W); RK-M (a) can't happen (whole subtree disabled); a failing occurrence's ancestors were all built.
- Window-wide redo + backoff remain only when: (1) attempt 2 itself requests a redo — escalate to a third build with all replay off + 9-build backoff, count `retainedRedoEscalations`, assert 0 across the suite; (2) the attempt wrote a channel declared unrestorable (`frame.noteUnrestorable(name)`); (3) verify mode.
- Tests: permanent `ChromeTranscriptFixture` (rounded tinted rows + nested `.equatable()` paragraph, streaming under `.defaultScrollAnchor(.bottom)`, scale 2); `aScopedRedoRebuildsOnlyTheFailingRowAndItsDescendants`; `aRedoDoesNotCascadeIntoTheRowsDescendants`; `aScopedRedoEqualsAFreshFrameInEveryChannel`; `theWindowBacksOffOnlyOnEscalation`; `aQuietTranscriptFrameCostsOnlyTheScroller` still 4. Mutations: descendants not quarantined; scope check off; rollback off.
- Rulings `RK-AJ`, `RK-AK` (renumber as needed). Effect: ~120-165 req/delta. Rejected: in-place repair mid-frame.

## Piece 3(a): mask cut by the entry clip replays exactly (one PR)
- While a recorder is open, each `pushClip`/`paintClipped` deeper than the entry depth appends to the record's `innerClips`: layout bounds before offset, `offset`, radii, parent push index, leaf index range covered, crossed flag.
- A moved record (where `old.key.ambient.clip == key.ambient.clip`) re-folds each push from the key's entry clip and offset with `pushClip`'s arithmetic and `intersectReportingCrossing`; leaf `contentMask`/`maskCornerRadii` and group-mask primitives come from their push.
- Retire `maskStraddlesEntryClip`; a push whose crossing differs from the recorded one refuses by name `maskCrossingChanged` (only while the viewport edge is inside a corner zone, ~8 pt per row edge).
- Tests: `aRoundedRowAtTheViewportEdgeReplaysTranslated`, `aRowWhoseCornerZoneCrossesTheEdgeRefusesByName`. Mutations: radii not re-folded; old move instead of fold. Ruling `FS-V`. Cost ~40 B per inner push per record.

## Piece 3(b): inexactTranslation
- Step 0 (small PR): the refusal trace names the leaf kind, field, value, and whether the entry offset or the leaf is fractional. Re-run on Alloy and the fixture.
- Probe `docs/probes/swiftui-scroll-offset-pixel-snap.swift` (SA-O header; `/usr/bin/swift` and `xcrun swiftc -O`; run twice). Borderless 300×300 on the 2x display, print `backingScaleFactor`. Instruments: NSScrollView clip `bounds.origin.y` full precision; `onScrollGeometryChange` `contentOffset`/`contentSize`; each row's `frame(in: .scrollView)` and `.global`; a 1 pt black hairline at each row top read back with `cacheDisplay(in:to:)` at backing scale (crisp = snapped). Arms: F0 control 40 pt rows; F1 33.3 pt rows with `.bottom` + append; F2 wrapping text growing word by word; F3 `scrollTo(.bottom)` no anchor; F4 fixed-point 0.3 px wheel delta; F5 `contentMargins` 12.25; F6 `.padding(0.3)`.
- If SwiftUI snaps the drawn position: snap the scroller's painted offset (`activeOffset` term) to `round(offset·scale)/scale`; snap stored/reported offset only if `contentOffset` is snapped too. Class-A fidelity fix, own record, ruling `DSA-J`, divergence row only if a difference remains (next label 250).
- If not: recompute moved leaves (`FS-W`): sparse side table of pre-offset origins only for leaves failing the exact-sixteenth check; recompute `(b + a_new)·s` with `fill`/`spriteGlyph`'s own expressions (AT-A pattern). ~8 B per fractional leaf.
- Tests: `aFractionallyMovedRowReplaysExactly` (mutation: recompute → add-delta), probe arms, quiet-frame cost pin. Effect after 3(a)+3(b): ~98-110 req/delta.

## Order and gates
1.1 → 1.2 → 1.3 → 2 → 3(a); probe + 3(b) step 0 in parallel with piece 2, then 3(b). Every PR: tests first, mutation proof, steady-frame cost test, record entry (next free number — check `docs/record/README.md` and open PRs), a `docs/rules/retained.md` line, rulings with `decision-prefixes.md` next ids moved, CLAUDE.md counts line, `cp CLAUDE.md AGENTS.md`. Alloy re-runs `measureStreamingRows` after 2, 3(a), 3(b).

## Risks
- An unlisted channel (mitigated by verify-mode rollback digests and the reference census).
- User element code storing a class in `withState` and mutating in place (doc contract: stored values are values; verify mode traps on an undigestible class).
- Index journal memory on 100k-row lists (only data-change frames, one frame long).
- 3(a) may expose prepaint-side refusals (`hitboxClipped`, `accessibilityClipped`); `innerClips` can serve them.
- Snapping (if adopted) moves pixel output at fractional offsets; stored offset stays logical.
- `aRedoWithATimelineInTheTreeEqualsAFreshFrame` flake history (RK-AD, RK-AE): keep the clock pin in new differentials.

## Critical files
`Sources/MetalUI/Window.swift` (`buildAndAdoptFrame` 2277-2450), `Sources/MetalUI/StateTable.swift` (write funnels 754-1008, `discardEntries` 803), `Sources/MetalUI/RetainedPrepaint.swift` (decision 287-415, `requestRedo`/`noteRedo` 561-589), `Sources/MetalUI/LazyCore.swift`, `Sources/MetalUI/ListRowExtents.swift`, `Sources/MetalUI/RetainedTranslation.swift` (193-326), `Sources/MetalUIScene/Atlas.swift`, `Sources/MetalUI/ScrollChrome.swift`.
