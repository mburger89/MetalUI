# 359 - Surface replay (`TRM-BB`, terminal Phase 3.3)

Branch `perf/surface-replay` from master `7d4d38ff`. Class M, no divergence (labels untouched). Phase 3.3 of `plans/2026-11-16-terminal.md`; renumbering expected (open PRs hold 350, 355-358).

**Problem.** `Frame.drawSurface` tainted retention (`"surface"`), so an `.equatable()` ancestor of a `GPUSurface` was ineligible every frame and its elements were requested again: with a `TerminalView` visible an unrelated editor keystroke frame cost two element requests (the terminal's focus layer and surface leaf).

**What landed.**
- `RetainLog.SurfaceNote` / `RetainLog.surfaces` (and a `surfaces` mark): `drawSurface` notes every call, the guard-skipped ones with `request == nil` (they still hold an occurrence, `MV-M` item 5). `RetainedRecord.surfaces` keeps the slice of its window; `moved(to:)` and `differences(from:)` (verify mode) carry it.
- `Frame.replaySurfaces`, called from `replayPaint` after the lives: counts the occurrence, keeps the id painted, appends the request at the frame's `timestamp` and the trigger, and appends the note to the open recorders (so an outer record holds an inner replay's surfaces).
- `SurfaceRegistry.replays(_:)` joins the hit condition: a record whose surface ids or occurrences the registry no longer holds misses.
- The `"surface"` taint and `LedgerSnapshot.surfaceRequests` are removed. `.continuous` surfaces stay unretained by `noteActiveAnimation`'s `activeAnimation` taint.

**Literals.** `aRetainedCardWith…Surface` (test 15): builds 1, element requests 2 -> 0, hits 0 -> 1, ineligible 1 -> 0, reasons `["surface": 1]` -> `[:]`. `RW-M` test 9: `.surface` arm hits 1 -> 2, paint ineligible 1 -> 0, reasons `["surface": 1]` -> `[:]`; `.continuousSurface` reasons `["surface": 1]` -> `["activeAnimation": 1]` (the taint that was shadowed). Untriggered surface without a card, and an app with no surface: unchanged.

**Tests** (`SurfaceOnlyRedrawTests.swift`, 15-20), mutations each shown red alone: taint restored (15, 16, 18, 19, 20 red); request not re-appended (16, 17, 18, 20); trigger not re-appended (17, 18); `replays` dropped from the hit condition (20). Test 17 compares per-frame headless draw counts of the same script with and without `.equatable()`.

**Not done / notes.** Translation of a record holding a surface still refuses (`movedLeaf` allow-list); an exact hit is the only replay. Surface-only frames are untouched (they never reach the retained paths).
