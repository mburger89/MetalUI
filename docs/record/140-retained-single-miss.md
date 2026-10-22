# 140 - One miss per changed occurrence, and a trace that names every failing conjunct (C14-j)

Branch `perf/retained-single-miss` from `195ff2c8`. Not a plan task: item C14-j of the gpui-gap list (MetalCreator's fillet-drag trace, 2026-10-21).
Spec `docs/superpowers/specs/2026-10-21-retained-single-miss-design.md`; rulings `DM-A`...`DM-O` in `docs/superpowers/2026-10-21-retained-single-miss-decisions.md` (next `DM-P`).
Divergence labels 695-704: **none taken** (value-identical, no public API, class `M` trace is `package`). Two lanes: lane 1 the trace (`RetainedTrace.swift`), lane 2 the fix.

## 1 What landed

- **Trace (lane 1).** `METALUI_TRACE_RETAINED=1` (or a `RetainedTrace.sink`, package) prints one `retained <paint|prepaint> <kind> <path tail> reasons=[...]` line per failing decision. Reasons are every failing
  conjunct (`PaintInvalidation`/`PrepaintInvalidation`, pure over primitive inputs, the decision reads the same struct): `observed`, `serial`, `coverage.build`, `coverage.prepaint`, ledger identity, `RW-S` ledger gain, versions,
  pointer, then each differing `key.<field>`/`ledgerKey.<field>` (nodeCount, shapeInterior, every ambient member) and a prepaint's own exit (`recordCannotMove`, `translationRefused: ...`). An empty list prints `unclassified`
  and counts (a test asserts zero). Path suffix default 120 characters (`METALUI_TRACE_RETAINED_PATH=<n>`). The writer behind an `observed` fire is recorded where `fireRetained` runs (`MemoFlags.lastFireCause`), only while
  active; a key path is not available from `withObservationTracking`, so the cause is the setter's symbol (debug) or `?` (release, inlined; `DM-E`, probe `docs/probes/observation-fire-cause.swift`). Off costs nothing
  (autoclosure behind one switch; `linesBuilt`/`pathsBuilt` pins and a Darwin allocation differential, `DM-K`).
- **Single miss (lane 2).** The hypothesis held and was measured first (`DM-B`, `DM-K`): the second miss was never `RW-S` alone. A changed occurrence's change frame ran its build and prepaint with the observation
  windows **closed** (`needsObservation` read a clean standing record), so the record its miss made had `coverageBuild == false`/`coveragePrepaint == false` and the next, unchanged frame missed naming exactly
  `coverage.build, coverage.prepaint`. Fix: `needsObservation` is also true for a certain miss (`record.contentSerial != serial || observedChange`, `DM-C`, ordering `DM-J`); `EquatableComponent.buildGroup` hands the
  window `observed || descendantRan` (`DM-L`: a nested `.equatable()` whose own getter ran keeps the outer record's build half). The two coverage halves are recorded separately (`DM-F`); the prepaint half differs only under
  the test seam `RetainedTestingHooks.closesPrepaintWindow` (`DM-M`). The `DM-G` adoption was **not needed** and is not built: `RW-S`'s ledger-gain rule is untouched in code, its amendment is about when it is reached.
- **Amendment of `RW-S`** (record §121): "a record made then gains its ledger one counted miss later" no longer holds for an `.equatable()` occurrence that changes (the `.ledgerGain` arm: change frame h6 m2, settle frame h8 m0). It still
  holds for a key-only miss.

## 2 Before and after (counts, `FrameWork`)

"Before" is the lane-2 behaviour with the two source terms reverted (`needsObservation` without the certain-miss terms, `observed` without `descendantRan`), measured on the same tree with the same temporary measurement test; "after" is HEAD.
`DoubleMissFixture` (eight `.equatable()` `DMNode`s in a `ForEach` under one parent; two nodes changed; change frame / settle frame):

| arm | before | after |
|---|---|---|
| `.value` | h6 m2 / h6 m2 | h6 m2 / **h8 m0** |
| `.observed` | h6 m2 / h6 m2 | h6 m2 / **h8 m0** |
| `.ledgerGain` (a `TextField` per node) | h6 m2 / h6 m2 | h6 m2 / **h8 m0** |
| `.nested` (inner and ancestor miss once, `SB-AC`) | h6 m4 / h6 m4 | h6 m4 / **h8 m0** |
| `.plain` (a plain child's read, the soundness arm) | h6 m2 / h6 m2 | h6 m2 / **h8 m0** |
| `.moved` (key-only: fractional width moves later nodes) | h2 m6 / h4 m4 | h4 m4 / h4 m4 (**carried**, `DM-D`) |

Over a change plus settle pair, misses equal changed occurrences (1 each) and hits are up by the same count. Other fixtures (6 orbit frames, 4 zoom steps, 9 drag steps), identical before and after because none of them re-draws an
unchanged-after-change occurrence: bracket `.value` 192 hits 0 misses 936 requests, `.panels` 18 / 0 / 36; zoom 40 / 0 / 20; `FilletDragFixture` `sliderOutside` 46 h / 8 m / 359 requests, `sliderInside` 45 / 9 / 396,
`sliderEverywhere` 5 / 49 / 1956, `sliderEverywhereObjects` 45 / 9 / 396, `observedRead` 46 / 8 / 359. **Not reproduced:** MetalCreator's 32 misses a frame in two groups. The fillet fixture changes one occurrence every frame, so
its second miss is never visible; the end-to-end figure needs MetalCreator re-run with `METALUI_TRACE_RETAINED=1` against this branch (not edited from here).

## 3 Pins and their mutations

`RetainedSingleMissTests` (filtered runs of `RetainedSingleMissTests|RetainedSubtreeSemanticsTests|RetainedTraceTests|retained prepaint/graft`, 66 tests; the full suite unmutated after): reddened tests by mutation, every one restored (`git status --short` clean after each).

| mutation | reddened |
|---|---|
| m1 `needsObservation` restored to `!record.coverageComplete` | `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` (all six arm/count cases), `aChangeNamesItsConjuncts`, `theCoverageHalvesAreRecordedSeparately`, `theKeyOnlyArmStillCostsTwoFramesOfMisses`, `aFrameRightAfterAMissObservesAgainSoASecondWriteIsSeen` |
| m2 `coveragePrepaint = phase.build.observed` | `theCoverageHalvesAreRecordedSeparately` |
| m3 `coverageBuild = phase.prepaintObserved` | `theCoverageHalvesAreRecordedSeparately` |
| m4 both halves `= true` at the record (windows still open) | `theCoverageHalvesAreRecordedSeparately`, `theKeyOnlyArmStillCostsTwoFramesOfMisses` (**not the soundness pin**: see below) |
| m5 `observed: observed` (no `descendantRan`) | `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` (`.nested`, both counts) |
| m6 drop `record.contentSerial != serial` | `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` (`.value`), `aChangeNamesItsConjuncts`, `theCoverageHalvesAreRecordedSeparately`, `theKeyOnlyArmStillCostsTwoFramesOfMisses` |
| m7 drop `|| observedChange` | `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` (`.observed`, `.nested`), `aFrameRightAfterAMissObservesAgainSoASecondWriteIsSeen` |
| m8 m1 + m4 (windows closed, coverage declared) | `aStaleSessionStillFiresAfterTheSameFrameRecord` (both variants), `aChildGetterReadInvalidatesItsEquatableParentsRecord`, `aRetainedFrameEqualsAFreshFrameOverAScript`, `aFrameRightAfterAMissObservesAgainSoASecondWriteIsSeen`, `theCoverageHalvesAreRecordedSeparately`, `theKeyOnlyArmStillCostsTwoFramesOfMisses` |
| m9 `observed: true` | **nothing** (equivalent on every fixture; `DM-O`) |

**Verify finding fixed (`DM-O`).** m4 and the first m8 run left the soundness pin green: on `.observed` the read is the getter's, covered by the memo session whatever the retained windows did. The fixture gained a `.plain` arm (a plain
child whose body reads the radius; only the occurrence's retained build window sees the write) and the pin writes after the change frame and after the hit that replayed it; m8 now reddens it. `theSingleMissFrameEqualsRetentionOff`
(the retention-off twin on every arm, four steps each) reddened under no coverage mutation alone: it is the oracle, not the instrument (its doc says so). The negative control is `.moved` (a key difference with an equal value still misses
twice; pinned at h4 m4 / h4 m4 until C14-k) and `theKeyOnlyArmStillCostsTwoFramesOfMisses` reddens when it lands.

## 4 Verification

- Native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; native unfiltered run on a **locked screen** at the final commit: **4261 tests in 7 suites** (4247 at `195ff2c8` + 14 test functions;
  parameterised cases are not counted), the five `AppKitPresentationTests` sheet issues of `CI-AF` and nothing else, `FR-J no-argument frame: succeeded=true`. `swift build --build-tests` on the default build system 0 `warning:`.
- `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, `AppKitPresentationTests` skipped: **4252 passed, no trap**.
- Inventory and undocumented scripts print nothing (no public declaration; `RetainedTrace` is `package`).
- The fourteen offscreen images: **0 px** against `195ff2c8` (`docs/probes/demo-pixels/compare.sh`, every row `scene identical`).
- Linux image (`metalui-portable`, root package, `--no-parallel`): `MetalUITestingTests` 500 tests in 4 suites, `MetalUILayoutTests` 238 and `MetalUICoreTests` 22 passed; `Backends/SDL` untouched.
- Scene, hitboxes, accessibility, tallies and bounds equal a retention-off twin on every arm every step (`theSingleMissFrameEqualsRetentionOff`).

## 5 Carried

- **C14-k: key-only `.moved` misses.** A key difference with an equal value still records with an unobserved prepaint (and build). The m9 result is the lead: claiming the build half from the standing record is sound on every fixture;
  the prepaint half needs its own window on the key-only path. `DM-D2`.
- The fillet drag's end-to-end number (MetalCreator's trace re-run); a release `?` for the fire cause (inlined setter).

## 6 Merge re-take

Merged with master `d062168c`-line (record 141 `drawText`, 139); 140 was free, no renumbering. On the merged tree after `swift package clean`: native build 0 `error:`, only SwiftPM's deprecation warning; native unfiltered run on a locked screen **4278 tests in 7 suites** (4264 + 14), exactly the five `AppKitPresentationTests` sheet issues, `FR-J no-argument frame: succeeded=true`; inventory and undocumented scripts print nothing. The verify-switch run, fourteen images, Linux image and default-build warning count are not re-taken on the merged tree (owed at merge).
