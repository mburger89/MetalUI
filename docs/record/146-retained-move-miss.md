# 146 - The key-only move miss (C14-k, lane 1) and the drag ambient miss (C14-l, lane 2)

Branch `perf/retained-move-miss` from `b1c1269f`. Spec `docs/superpowers/specs/2026-10-22-retained-move-miss-design.md`; rulings `AM-A`...`AM-O` in
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

## 4 Lane 2 (C14-l): what changed and what was measured

- **`DragAmbientFixture`** (`DragAmbientFixture.swift`): eight `.equatable()` `DMNode` panels (`.observed` arm) under a parent holding `@GestureState` and a strip with `DragGesture(minimumDistance: 0).updating($dragging) { _, s, t in s = true; t.disablesAnimations = true }.onChanged { write params[2].radius }`. The gesture's transaction is parked for one build (`AN-Y`): the drag frames' root transaction differs from the settle frames'.
- **Before** (measured at `bc0b60b8`, `RetainedAmbientMissTests.measure`, trace on), per frame, six drag moves, the release, two settles: `h0 m8, h0 m8, h7 m1, h7 m1, h7 m1, h7 m1, h0 m8, h0 m8, h8 m0`. The reasons: the first drag frame all eight panels `key.ambient.disablesAnimations` (paint) and `ledgerKey.ambient.disablesAnimations` (prepaint), the next `coverage.build, coverage.prepaint` (both halves: the second frame of an ambient miss, `AM-C`), panel 2 `serial` throughout; the release frame the same flip back and the same second frame. **`key.ambient.environment` did not flip** in the fixture (`AM-M`).
- **After**: `h7 m1` on each of the six drag frames, `h8 m0` on the release and both settle frames. No `disablesAnimations`, `snappingTransaction` or `coverage` in any line. The `[coverage.build, coverage.prepaint]` lines MetalCreator's log shows after a change were the second frame of this ambient miss and are gone with it (`AM-J`); no residue on the fixture.
- **The rule** (`AM-D`, amended by `AM-L`): `snappingTransaction` and `disablesAnimations` are not part of a retained key. The first build kept them for a record with no animation touches; it left the drag unchanged because every filled panel touches an animation track, so the guard was retired (`AM-L`). `RetainedTransactionKey.swift`: `transactionNormalised` on `AmbientKey`, `ReplayKey`, `PrepaintKey`, applied at the decisions in `retainedPaintDecision` and `retainedPrepaintDecisionInner` (every stored key is normalised since every computed one is).
- **The graft's `BuildKey`** still keys `snapping`/`disablesAnimations`; a flip frame refuses the graft by key and builds, which is not a miss and not a repaint (`retainedGraftIneligible`). Not changed (`AM-L`, carried).
- **The trace**: `key.ambient.environment.<field>` for all 26 fields of `EnvironmentFingerprint` (`differences(from:)`, `Mirror` guard); `tail(of:length:)` cuts at a `/` with a `…/` prefix (the log's tails began `ional(0)/positional(1)`); the fire cause is `writerCause(from:)`, the setter frame in debug, `via <function>` in release (the first frame after the observation machinery), `release-inlined` when nothing is above it, `?` only when no frame is symbolicated (Windows).
- **Release probe** `docs/probes/observation-fire-cause-release.swift`, recorded 2026-10-22 (macOS arm64, swift 6.4). `-Onone`: both arms have a `.setter` frame (`main.Model.radius.setter`) between `main.Model.withMutation` and the writer. `-O`: no `.setter` frame in either arm; the writer behind `@inline(never)` is `main.theWriter(main.Model) -> ()`, directly after `Observation.ObservationRegistrar.withMutation`; a writer inlined into its caller leaves `function signature specialization <...> of main.arm(...)`. Reading: the nearest frame after the machinery is the writer or its inlined-into caller; both rules named in `AM-N` hold, and nothing in `onChange` carries a key path (probe `observation-fire-cause.swift` B).
- **Not reproduced, carried as C14-m**: the `key.ambient.environment` half of MetalCreator's `[key.ambient.environment, key.ambient.disablesAnimations]` lines (`AM-M`), `[noRecord]`/`first-or-dropped` (spec section 7), the graft key's two members.

## 5 Red on arrival and mutations (lane 2)

Red on arrival: the unnormalised tree read the `before` frames above (`measure` printed them); `aSteadyDragCostsExactlyTheChangedPanelsMisses` is red on exactly that by mutation m1+m2 below (36 + 16 issues); the other new tests do not compile before the change (`EnvironmentFingerprint.differences`, `RetainedTrace.writerCause(from:)`) or read the old text (`tail`, `key.ambient.environment`).

Mutations (filtered to the lane's tests and the trace suites, source restored from a copy, `git status` clean after each):
| mutation | reddened |
|---|---|
| m1 `retainedKey(phase)` not normalised | `aSteadyDragCostsExactlyTheChangedPanelsMisses` (36 issues: the paint half names `key.ambient.disablesAnimations`) |
| m2 `retainedPrepaintKey(phase)` not normalised | `aSteadyDragCostsExactlyTheChangedPanelsMisses` (16 issues: `ledgerKey.ambient.disablesAnimations`) |
| m7 only `snappingTransaction` zeroed | `aSteadyDragCostsExactlyTheChangedPanelsMisses` (66 issues) |
| m3 bare `environment` in `AmbientKey.differences` | `theTraceNamesTheDifferingEnvironmentField`, `everyReplayKeyFieldIsNamedWhenItDiffersAlone` |
| m6 the `colorScheme` row dropped | `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` |
| m4 `tail` back to `suffix(length)` | `aTraceSuffixIsCutAtASlash` (6 issues) |
| m5 `writerCause(from:)` returns `?` | `aFireCauseNamesTheWriterFrameOrSaysReleaseInlined` (8 issues), `aChangeNamesItsConjuncts`, `theFireCauseNamesTheWritingProperty` |

Survivors and unmeasured: `theDragFrameEqualsRetentionOff` and `anAnimationStartedInsideAPanelStillRuns` stay green under m1-m7 (oracles: the twin agrees with or without the key, `AM-O`); `aDragWithoutATransactionCostsTheSame` is the control; the `differences`-outside-the-autoclosure mutation of `theTraceCostsNothingWhenOff` was not run (`AM-O` 3).

## 6 Verification (lane 2)

`swift package clean`, native build 0 `error:`, only SwiftPM's deprecation `warning:`; native unfiltered run **4321 tests in 9 suites passed** (4312 + this lane's 9 test cases), `FR-J no-argument frame: succeeded=true`. Inventory and undocumented scripts print nothing (no public declaration: `package` and internal only).
