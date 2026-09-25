# 56 — Environment: control state and scale (plan task 9, closing half)

Branch `feat/environment-control-state` from `e732d98`. Spec
`docs/superpowers/specs/2026-09-25-environment-control-state-design.md`;
rulings `EV-AA`…`EV-AF` appended to
`docs/superpowers/2026-09-15-environment-decisions.md`; probe
`docs/probes/swiftui-environment-control-state.swift`. **This file is lane 1's
first draft**, written so its measurements are not lost before the Record
phase; the Record phase owns its final shape (design-phase section, lanes 2
and 3, divergence and inert rows, counts).

## 1. Lane 1 — the values

Commits: `7299051` (red tests), `1f5c221` (implementation).

### 1.1 Baseline

`e732d98`, worktree with its own `.build`: `swift build --build-system native
--build-tests`, then unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1490 tests in 3 suites passed`**; the log
carries `FR-J no-argument frame: succeeded=` (guards ran); the one `warning:`
SwiftPM's deprecation notice.

### 1.2 Red

`7299051` adds T1.1–T1.8 (`Tests/MetalUITests/EnvironmentScaleAndSizeTests.swift`),
extends E13 and G1+/G6, re-premises G3's doc and renames E19. The red reading
is a compile failure of the test target — 32 distinct error sites, of four
kinds: `value of type 'EnvironmentValues' has no member 'displayScale'`
(T1.1–T1.4, E13 ×3, E19′ ×3), `… 'controlActiveState'` (T1.8), `… 'controlSize'`
/ `value of type 'Text'|'TextField'|'ValueRecorder' has no member
'controlSize'` / `cannot find 'ControlSize' in scope` (T1.6, T1.7), and
`cannot convert value of type 'KeyPath<EnvironmentValues, V>' to expected
argument type 'WritableKeyPath<EnvironmentValues, V>'` at every
`.environment(\.displayScale|controlActiveState, _)` (T1.2, T1.4, T1.5, T1.8).
Each test's runtime red is the mutation its row names (§1.4).

### 1.3 The retained test that changed its answer (E19 rename row)

| removed name | new name | assertion that flipped | ruling |
|---|---|---|---|
| `aWholeValueWriteCannotResetTheThemeOrThePixelLength` | `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | both arms' `pixelLength == 0.5` → `displayScale == 1` and `pixelLength == 1` (pixel-length probe X2); theme half unchanged; new: the unscoped control reads `displayScale == 2` | `EV-AA` |

E13 (`theFramesRootEnvironmentCarriesItsThemeAndScale`) keeps every assertion
and gains three (`displayScale` 2 / 1 / 2 on its three arms).

### 1.4 Mutations

Each at `1f5c221`: committed first, the file restored from a copy, the full
unfiltered suite (1498) run, `git status --short` clean after each. Issue
counts are the summary line's.

| # | spelling | reddened | issues |
|---|---|---|---|
| M1.1 | `Frame.displayScale(forScaleFactor:)` returns 1 for a usable scale (the helper both stamps call) | `theRootDisplayScaleIsTheFramesScaleFactorAndThePixelLengthFollows`, `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows`, `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `theFramesRootEnvironmentCarriesItsThemeAndScale`, `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 14 |
| M1.2 | `scopedValues` adds `values.displayScale = environmentTop.displayScale` after a transform | `aScopeCanWriteTheDisplayScaleAndThePixelLengthFollows`, `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 9 |
| M1.3a | `pixelLength` = `1 / displayScale` | `aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale` | 1 |
| M1.3b | `displayScale <= 0 ? 1 : 1 / displayScale` | `aPixelLengthIsSwiftUIsFunctionOfTheDisplayScale` | 1 |
| M1.4 | `Frame.fill`'s `bounds:` scaled by `Float(environmentTop.displayScale)` (mask, radii, borders left on `scaleFactor`) | `aDisplayScaleWriteChangesTheNumberNotTheScaleDrawingUses`, `layoutRoundsToWholePointsWhateverTheDisplayScale` | 2 |
| M1.5 | `roundLayout` rounds all four edges to half points, `(v * 2).rounded() / 2` | 27 tests, §1.5 | 68 |
| M1.6 | `.controlSize(_:)` writes `.regular` | `controlSizeIsScopedByTheNearestWriter` | 2 |
| M1.7 | `Text.requestLayout` resolves its font at `fontSize * 0.7` under `.mini` | `controlSizeReachesNoBuiltInMeasurement` | 2 |
| M1.7b | (added: M1.7 leaves the `TextField` arm unmutated) the same in `TextField.requestLayout` | `controlSizeReachesNoBuiltInMeasurement` | 1 |
| M1.8 | bare `controlActiveState` default `.inactive` | `controlActiveStateIsKeyInABareValueAndAWindowlessFrameAndAScopeCanWriteIt` | 3 |
| M1.9 | the `rootEnvironment` setter stops re-stamping `displayScale` | `theFramesRootEnvironmentCarriesItsThemeAndScale` | 2 |
| M1.10 | `scopedValues` stops re-stamping `theme` | `aWholeValueWriteResetsTheDisplayScaleButNotTheTheme` | 2 |
| MG1 | `var displayScale` (internal) | `environmentValuesAreReadableInEveryPhase`, `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 2 |
| MG3 | `pixelLength` gains `set { displayScale = 1 / newValue }` | `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles` | 2 |
| MG6a | `public internal(set) var displayScale` | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 1 |
| MG6b | `func controlSize(_:)` (internal) | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` | 1 |

MG3 red with G3's `WritableKeyPath` expectation unchanged: the negative half's
message still names `WritableKeyPath` for a computed get-only property, so the
spec's "amend the expectation" branch was not needed. MG6a reddens G6 and not
G1+, so the pair separates read from write.

### 1.5 M1.5's reddened tests, by file

- **AXEmitSiteTests**: `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`
- **ContainerIntegrationTests**: `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`, `overlayAndBackgroundContentIsPlacedAtThePrimarysSize`, `severalViewsInAnOverlayOrBackgroundAreACentredZStackPositionedByTheAlignment`
- **DemoFrameDeterminismTests**: `theDemoFrameMatchesTheValuesRecordedOnMacOS`
- **ElementLayoutTests**: `anExplicitAnyElementIsStillAcceptedAsAChild`, `columnStacksOnTheAxisRowDoesNot`
- **EnvironmentScaleAndSizeTests**: `layoutRoundsToWholePointsWhateverTheDisplayScale`
- **GlyphEmitterTests**: `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox`, `theWindowsPixelsAreExactlyTheGlyphBitmapsItsSpritesStandFor`
- **GoldenReplacementFlexTests**: `equalGrowersShareTheLineAndAMaximumCapsItsGrower`
- **GoldenReplacementStackTests**: `aGrowFactorSumBelowOneStillFillsTheLine`, `aStackHugsItsLargestChildInsideARowAndAroundOne`
- **LoweringContainerTests**: `everyContainerFieldEitherLowersOrIsReportedByName`
- **LoweringDistributionTests**: `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`
- **LoweringLeafTests**: `aLoweredTextLaysOutAndDrawsAtItsNaturalWidth`
- **LoweringScrollTests**: `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`
- **NativeLayoutTests**: `nativeLayoutRoundsStoredRectanglesAfterFractionalPlacement`
- **NativeStackDistributionTests**: `aStackAnswersTheSumOfItsChildrensAnswers`, `aStackMeasuresItsCrossSizeAtItsAllocations`, `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal`, `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`
- **PresentationLoweringTests**: `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes`
- **ProposalLayoutIntegrationTests**: `aProposalLayoutContainerRendersThroughTheFramePipeline`
- **RoundingTests**: `roundingHandlesTheMeasuredWebKitCase`, `roundingRoundsYIndependentlyOfX`, `roundingUsesCumulativeCoordinatesSoWidthsDoNotDrift`

No layout mutation that follows `displayScale` exists without plumbing the
scale into `MetalUILayout`, which this design does not do (`EV-AD`); a
half-point grid is the nearest stand-in and is what divergence 77's pin sees.

### 1.6 `MemoryLayout<EnvironmentValues>`

Before (`e732d98`): size 176, stride 176, alignment 8. After (`1f5c221`):
size 184, stride 184, alignment 8 — `+8`: one stored `Double` (`pixelLength`)
out and one (`displayScale`) in, plus the two one-byte enums, which spill into
one more 8-byte word. Measured with a throwaway filtered test printing the
three numbers, deleted after each reading. The gate is
`everyProductionTreeBuildsOnAOneMegabyteThread` (green on macOS; Windows CI on
push).

### 1.7 Exit

After `swift package clean` (a stored property left a public struct crossing a
module boundary): **`Test run with 1498 tests in 3 suites passed`** (1490 + 8),
guards ran (`FR-J no-argument frame: succeeded=`), 0 `error:`, the one
`warning:` SwiftPM's notice. Guards: 88, none added (G1+ and G6 extended).
`everyProductionTreeBuildsOnAOneMegabyteThread` and
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green in that run.

**Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> e732d98 1f5c221` —
controls at `e732d98` as the script's stage-9 correction records (light vs
dark 1048576, default vs modal 1031003, default vs animation 454895, f0 vs f3
0, preview light vs dark 1048576, chrome pair 0, distinct 544 / 216, prod
default vs modal 491221, distinct prod 529, indicator rects 0); **all fourteen
images `differing=0`, scene identical**.

**Real-window capture: not taken.** Lock probe at lane 1's end:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`. The probe's C arms
(`EV-AB`'s mapping) were not re-run for the same reason.
