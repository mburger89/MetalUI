# 146 - The key-only move miss (C14-k, lane 1; lane 2 appends its section)

Branch `perf/retained-move-miss` from `b1c1269f`. Spec `docs/superpowers/specs/2026-10-22-retained-move-miss-design.md`; rulings `AM-A`...`AM-K` in
`docs/superpowers/2026-10-22-retained-move-miss-decisions.md`. Divergence labels 755-764: none taken. No public API.

## 1 Lane 1 (C14-k): what changed

- `RetainedPhase.prepaintObserved` is `var`; `retainedPrepaintPhase` sets it when the standing record's `rects`/`interior`/`shapeInterior` differ from the
  geometry just read (`AM-A`). `RetainedBuild.closedOnRecord` (`!observed`, set by `EquatableComponent`) and `RetainedPhase.inheritsBuildCoverage` (set in the paint
  decision's miss branch under `valid`, `closedOnRecord`, equal `ambient` and equal `nodeCount`) give `record.coverageBuild = build.observed || inheritsBuildCoverage` (`AM-B`).
- `RetainedTestingHooks.buildWindowsOpened`/`prepaintWindowsOpened` (package, counters) pin that a steady frame opens none.

## 2 Measured

`DoubleMissFixture` `.moved` (nodes 1 and 4 change by a fractional width): change frame h4 m4 before and after; **settle frame h4 m4 before, h8 m0 after**; third frame h8 m0.
Each half alone leaves the settle frame at h4 m4. Red on arrival (commit `37bd7546`): `aMovedOccurrenceCostsOneMissAndTheNextFrameHits` (settle misses, misses over the script),
`theKeyOnlyArmCostsOneMiss` (the flipped `theKeyOnlyArmStillCostsTwoFramesOfMisses`), `aWriteAfterAMovedMissIsStillSeen(afterAHit: false)` (misses != 1, the baseline double miss).

Mutations (filtered to `RetainedMoveMissTests|RetainedSingleMissTests`, source restored after each, `git status` clean):
| mutation | reddened |
|---|---|
| m1 predictor off | `aMovedOccurrenceCostsOneMissAndTheNextFrameHits` (2 lines), `aWriteAfterAMovedMissIsStillSeen(afterAHit: false)`, `theKeyOnlyArmCostsOneMiss` |
| m2 inheritance off | the same four |
| m3 inherit on every miss | `anAmbientMissDoesNotInheritBuildCoverage` (the write-after arm stays green: its read is covered either way) |
| m4 predictor always true | first spelling survived (counter at the run site; a steady prepaint replays); counter moved to the decision site (`AM-K`), then `aSteadyFrameOpensNoMoveWindow` reddens |

Bracket, zoom and fillet fixtures: their pins pass unmoved (a whole-pixel drag translates, `FS-M`, so those frames never take the key-only path); no per-frame number changed.

## 3 Verification (lane 1)

Native unfiltered run 4312 tests in 8 suites passed, `FR-J no-argument frame: succeeded=true`; the same under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`: 4312 passed (597 s).
Build 0 `error:`, only SwiftPM's deprecation `warning:`. Inventory and undocumented scripts print nothing. Fourteen images 0 px against `b1c1269f` (`compare.sh`, all "scene identical").
Linux image (`metalui-portable`): `MetalUITestingTests` 532 (5 suites), Layout 238, Core 141, CrossPlatform 22, all passed. Default-build-system warning re-take and the SDL package were not touched.
