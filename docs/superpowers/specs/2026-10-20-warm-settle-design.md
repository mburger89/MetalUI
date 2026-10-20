# Warm settle (C14-e) — design

Item C14-e (user request 2026-10-02's list; MetalCreator's counter bisect, 2026-10-20). Branch `perf/warm-settle` from `679f5d7d`.
Rulings: [`../2026-10-20-warm-settle-decisions.md`](../2026-10-20-warm-settle-decisions.md) (`CF-A`…`CF-G`). Part (c) of the original item
(`onGeometryChange` replay inside a retained subtree, `RK-E`) is **excluded** and runs after C14-d.

## 1. What changes, in one paragraph each

**(a)** `@Environment(\.textMeasurer)` becomes a comparable `EnvironmentReading` (`CF-A`): text-system instance identity plus the two
resolved default text styles of the measurer's environment. A component reading it is skipped while both are unchanged. No public API,
no new divergence label: divergence 346's text is narrowed again at the Record phase (the uncomparable list loses `\.textMeasurer`).

**(d)** A redo frame (`RK-D`) reports the redo's counters with the abandoned attempt's content evaluations carried (`CF-C`, `CF-D`).
No public API.

**(e)** Reproduce, then fix or rule (`CF-E`). **Not reproduced by the item's described shape at the designer step.**

**(b)** Dated cold-frame profile; a fix only outside C14-d's files (`CF-F`).

## 2. Files and the C14-d merge plan

C14-d (`perf/finer-scopes`) edits `RetainedSubtree.swift`, `List`/`ForEach` retention and the prepaint ledger. This item touches **none**
of them. Shared-risk files, each with at most a few lines: `ContentMemo.swift` (lane 1: a carried-evaluations field read in `endFrame`;
C14-d may also edit it for per-row scopes — merge by hand, the hunk is disjoint), `RetainedPrepaint.swift` (`noteRedo`, ~3 lines),
`Window.swift` (not edited unless the redo hunk needs a line). If (b)'s fix lands it is in C14-d's files and is **not** applied here
(`CF-F`); the record carries it for after C14-d.

| Lane | Owns | Files (disjoint) |
|---|---|---|
| 1 | (a) and (d) | `Sources/MetalUI/EnvironmentReading.swift`, `TextMeasurer.swift` (an internal `reading` property), `ContentMemo.swift`, `RetainedPrepaint.swift`; tests `Tests/MetalUITests/TextMeasurerReadingTests.swift`, `Tests/MetalUITestingTests/TextMeasurerEpochTests.swift`, `RedoCounterTests.swift` |
| 2 | (e) and (b) | `Sources/MetalUILayout/LayoutMemo.swift` / `LayoutTree.swift` only if (e)'s cause is there; tests `Tests/MetalUITestingTests/WarmSettleTests.swift`; probes/notes under `docs/probes/warm-settle/`; (b) is measurement only |

Lane 2 never edits `ContentMemo.swift`, `RetainedPrepaint.swift` or `Window.swift`: a cause found there is handed to the orchestrator and applied
after lane 1 lands (sequential), so the lanes cannot conflict. Both lanes end with the verification list in §6; lane 1 owns the
`swift package clean` run (no stored property on a public type changes, so none is owed otherwise).

## 3. Lane 1 — (a) the comparable measurer

`TextMeasurer` gains `var reading: TextMeasurerReading` (internal) built from `box?.system` (`ObjectIdentifier`, `nil` for no box) and
`[resolveTextStyle(TextStyleRequest(), in: environment), resolveTextStyle(TextStyleRequest(font: .defaultFont), in: environment)]`.
`TextMeasurerReading: Equatable` is internal. `EnvironmentReading.of<T>` tests `value as? TextMeasurer` **first** (a single
dynamic cast per probe; the cast happens only for a keypath whose `Value` is that type — place it in `Environment.init(_ keyPath:)`
as `Value.self == TextMeasurer.self` check so no other reading pays). The doc comments on `EnvironmentReading` (line 12) and
`EquatableComponent.equatable()` (line 197) drop `\.textMeasurer` from the uncomparable list.

Tests (each red at `679f5d7d`):

| # | Test | Red before | Mutation that must redden it |
|---|---|---|---|
| T1 | `aMeasurerReaderIsSkippedWhileTheSystemIsUnchanged` (TestingTests): an `.equatable()` component sizing a label by `measurer.resolve(Text(...)).measure(in:)`; 3 warm redraws | `contentRefusals == 1`, `contentSkips == 0` per frame | `Environment.init` bypasses the new arm (`.uncomparable` again): refusals return; separately, the arm keys on the box (`ObjectIdentifier(box)`): evaluations every frame (box is per frame) |
| T2 | `aFontChangeAboveAMeasurerReaderReevaluatesIt`: a model toggles `.font(.system(size: 20))` on a parent | stale: n/a (it is refused, always fresh) so assert evaluation count 1 **and** the shown size equals a fresh `Text` layout's | drop the style half of `TextMeasurerReading`: size stays stale, test red |
| T3 | `aMeasurerReadingChangesWithEachTextStyleField` (arguments: font, fontWeight, italic, controlSize, lineLimit, truncationMode, multilineTextAlignment, foregroundStyle, controlSize with `font(nil)` text): `@testable` unit over two `EnvironmentValues` differing in one field | `.uncomparable` equals nothing, so "equal when same" arm red | per argument: remove that field from the environment writer used to build the reading's styles — the named argument's arm only reddens |
| T4 | `theReadingIsTheSystemInstanceNotTheBox` (unit): two boxes over one system equal, over two systems unequal, a nil box equal to itself and unequal to a boxed one | arms 1,3 red (uncomparable) | key on `ObjectIdentifier(box)`: arm 1 red |
| T5 | `aMeasurerReaderReplaysItsPaint`: the same component, retained: `retainedHits` 1 and the scene equals retention-off (`testingRetainedSubtrees = false`), then a font change repaints | `retainedIneligible`/refusal (`uncomparable` custom reading) | skip-arm of the fingerprint removed |
| T6 | dropped (`CF-H`): it had no mutation that reddens it; T4 is the separating arm | | |

Run under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` too (T5 must hold; the existing
`aReaderOfAFunctionKeyIsRefusedAndStillEvaluates` stays red-for-the-right-reason: the refused arm is the function key).

## 4. Lane 1 — (d) the redo counters

`ContentMemoStore.noteRedo` saves `evaluations` before `resetBuildCounters()` and the redo's `endFrame` adds it back (`carriedEvaluations`,
cleared there). Verify mode (`RK-N`) keeps `reportLast`. Tests in `RedoCounterTests.swift` reuse `RetainedPrepaintTests`' redo fixture (a paint-time
ambient that differs for a replayed prepaint, `RK-D`):

| # | Test | Red before | Mutation |
|---|---|---|---|
| R1 | `aRedoFrameReportsTheContentGetterTheAbandonedAttemptEvaluated`: one component's value changes in the same frame the redo fires: `retainedRedos == 1` and `contentEvaluations == 1` | `contentEvaluations == 0` | delete the carry in `endFrame` |
| R2 | `aRedoFrameDoesNotCountAnEvaluationTwice`: a changed component plus a refused one: evaluations 1, refusals 1 | n/a (guards the carry against double count) | carry added also to `refusals`: red |
| R3 | `aRedoFrameKeepsTheRedosOtherCounters`: layout, element and retained counters of a redo frame equal the same tree's redo-off frame minus `retainedRedos` (the redo is a full rebuild) | none (pins the "redo only" half of `CF-C`) | carry everything: red |
| R4 | the frame after a redo (backoff, `retainedBackoffFrames == 1`) reports no carried count | none | carry not cleared: red |

## 5. Lane 2 — (e) and (b)

**(e).** Step 0 of `CF-E` (scratch copy of MetalCreator, instrument, cut down). Then `WarmSettleTests.swift`:
`aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst` (builds the reproduced fixture, `resetFrameWork()`, seven `redraw`s, `#expect(work == warm[0])`
for all, and no raster/atlas/texture work) and `theMemoKeepsWhatAGraftedSubtreeStandsFor` (if the cause is (1): `LayoutMemo.entryCount`
after N warm frames equals after 2). **Red before:** the first needs the fixture to show the spike at `679f5d7d`; if it cannot, the pin
starts at the first stable frame and the item stays open (`CF-E`'s cost clause). Mutation: the `touch` removed (or, for the inherent
ruling, none — a pin on stability only).

**(b).** `docs/probes/warm-settle/cold-profile.md` (measurement notes, not a record file) and §127: release harness (`perf-baselines.sh`),
`xctrace record --template 'Time Profiler'` on the bracket fixture first frame and an orbit-shaped tree at `679f5d7d` and at `6273e3a4`
(before C14b-2), three repeats, medians, beside `layoutMemoMisses`, `retainedLedgerSnapshots`, `rasterizedPixels`. The attribution splits
cold time into ledger snapshots, memo-miss handling, overscan raster (P3 `PN-`, P4 `OS-`), build/paint. Decision per `CF-F`.

## 6. Verification (both lanes; the orchestrator re-takes the totals)

`swift package clean`; `swift build --build-system native --build-tests` 0 `error:`; `swift test --build-system native --no-parallel`
unfiltered, one summary line (4015 at `679f5d7d` + the new tests) and `FR-J no-argument frame: succeeded=`; the run again under
`METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`; `swift build --build-tests` (default) 0 `warning:`; inventory and undocumented
scripts print nothing (no public declaration expected); the fourteen images 0 px (`docs/probes/demo-pixels/compare.sh <scratch> 679f5d7d
HEAD`); Linux image `metalui-portable` for `MetalUITestingTests` and the portable tests (the warm pin must hold off Darwin; T1–T5 use
`setNeedsRedraw()`+`tick()`, no observation hop). Every mutation: commit first, restore from a copy, full unfiltered suite, `git status
--short` after, reddened tests named. `Backends/SDL` is untouched. No new typecheck guard.

## 7. Demo expectation and human checks

No demo section; no look changes (value-identical). Human checks: none new (agent-verifiable; pixels via the fourteen images). The one
real-window item is MetalCreator's own: re-run its `WarmFrameTests` (`unchangedFramesAfterSettlingDoExactlyTheSameWork`) with the
comparison moved back to frame 0 once `CF-E` lands — recorded as a hand-off, not a check group.

## 8. Deferred, with owner

- `onGeometryChange` replay in a retained subtree (`RK-E`, `GeometryChange.swift:104`): after C14-d, owner C14-f.
- (b)'s ledger-snapshot fix, if the profile supports it: in C14-d's `RetainedSubtree.swift`; applied after C14-d merges, owner C14-d's merge.
- `@FocusState` readings (C14-c2) and the remaining uncomparable readings (closures, `\.self`): unchanged, divergence 346's residue.
- A reported abandoned-attempt work counter (`CF-D`): not built.

## 9. Record phase

`docs/record/127-warm-settle.md`; divergence 346 text narrowed (`\.textMeasurer` out of the refused list; pin names `aMeasurerReaderIsSkipped…`);
CLAUDE.md gets the `CF-` prefix (next id from the decisions doc), a one-paragraph rule, and the counts; `docs/record/README.md` row;
`cmp CLAUDE.md AGENTS.md`.
