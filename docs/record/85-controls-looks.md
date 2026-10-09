# 85 — Controls and looks (C10)

Branch `feat/controls-looks` from `cd84b0c`. User request 2026-10-02, item
C10 of the gpui-gap priority list (not a plan task). Spec
`docs/superpowers/specs/2026-10-08-controls-looks-design.md`; rulings
`docs/superpowers/2026-10-08-controls-looks-decisions.md` (`LK-`). Divergence
labels reserved for this branch: 165–174.

## §0 Baseline (lane 1, before its first change)

Taken at `ba672be` (= `cd84b0c` plus the design commits, docs only):

- `swift build --build-system native --build-tests`, then
  `swift test --build-system native --no-parallel` unfiltered: **2723 tests in
  3 suites passed**; `FR-J no-argument frame: succeeded=true` present; 0
  `error:`; the only `warning:` SwiftPM's `--build-system native` notice.
- `swift build --build-tests` (default build system): 0 warnings.
- `Backends/SDL` on macOS (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)`): **24 + 84**.
- `Backends/SDL` in the Linux image (`metalui-portable`, volume
  `metalui-sdl-build-controls-looks`): **24 + 81**.

## §1 Lane 1 — controls (Slider editing, ColorPicker, three roles)

Commits: `b453b9a` (red: tests and API stubs), `ec0f58a` (implementation,
ruling `LK-U`, divergence 165, census), `dce0364` (two instruments repaired),
the record commit (this section).

### §1.1 Red

44 root tests and one `Backends/SDL` test, written against stubs carrying the
public surface with every answer wrong (`b453b9a`). On the stub, 40 of 44
failed at run time; the 4 that passed were the two guards
(`theSliderInitialisersKeepTheirSwiftUISpellings`,
`aColorPickerTakesABackgroundAndPadding`) and the two negative slider tests
(`aDisabledSliderPressCallsNothing`, `anOutsideBindingWriteCallsNothing`) — all
four are absent API at `cd84b0c`, so none compiled there. First failure line
per test (abridged; each `Expectation failed:`):

| test | first red line |
|---|---|
| `hsbRoundTripsEveryByteTriple` | `ColorMathTests.swift:28` `failures.isEmpty` |
| `hsbOfThePrimariesAndGreys` | `:40` `hsb(1, 0, 0) == [0, 1, 1]` |
| `parseHexAcceptsTheFourFormsAndNothingElse` | `:53` `parseHex("#FF8000") == orange` |
| `hexStringIsUppercaseRoundedAndCarriesAlphaOnlyWhenAsked` | `:71` `… == "#FF8000"` |
| `axComponentsPrintLikeAppKit` | `:82` `… == "rgb 1 0 0 1"` |
| the 16 panel tests, `pressingTheWellOpensThePanelAndDoesNotFocus`, `spaceOnAFocusedWellOpensThePanel` | `ColorPickerTests.swift:41` `wells.count == 1` (no well) |
| `aColorPickerIsItsLabelEightPointsAndAFortyEightByTwentyFourWell` | `:85` `width == text.width + 56 && height == 24` |
| `aColorPickerWithAnEmptyTitleIsTheWellAlone` | `:95` `48 × 24` |
| `aColorPickerInAVStack…`, `…InAnHStack…` | `:103` no 48×24 well |
| `theWellPublishesAColorWellWithAppKitsValueFormat` | `:169` `wells.count == 1` |
| `anAccessibilityPressOnTheWellOpensThePanel` | `:184` no `.colorWell` node |
| `theThreeNewRolesHaveRowsOnTheAppKitBridge` | `ControlsLooksAccessibilityTests.swift:50` role `.progressIndicator` |
| `aSliderPressCallsEditingTrueBeforeItsFirstWrite` | `SliderEditingTests.swift:83` `log == ["editing true", "set 5"]` |
| the other eleven slider runtime tests | their `model.log == […]` line (`:95`, `:105`, `:141`, `:155`, `:171`, `:183`, `:195`, `:221`, `:232`, `:252`, `:291`) |
| `theThreeNewRolesHaveRowsOnAccessKit` (`Backends/SDL`) | `AccessKitControlsLooksTests.swift:35` `progress.role == .progressIndicator` |

### §1.2 Landing

- **Suite**: after `swift package clean` (new `AccessibilityRole` cases, a new
  `AXNode` stored property), native build, unfiltered `--no-parallel`:
  **2768 tests in 3 suites passed** (2723 + 45: the 44 red tests plus
  `aDisabledColorPickerOpensNothing`), `FR-J no-argument frame: succeeded=true`, 0 `error:`,
  only SwiftPM's deprecation `warning:`. `swift build --build-tests` 0 warnings.
- **The first green suite was not green** (three issues, all fixed before the
  implementation commit): `theNewDeclarationsCostHandlersAtMostOnePointer` and
  `handlersGainsOneReferenceMember` (a second closure on `ValueTrackTarget`
  grew `Handlers` by 16 bytes — `LK-U` item 2) and
  `theVoiceOverScriptQuotesThePublishedTree` (the demo's slider published
  `0.5`, a value the script's step C6 reads — `LK-U` item 8).
- **`Backends/SDL`**: macOS **24 + 85**, Linux image **24 + 82** (one new test
  each).
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> cd84b0c HEAD`
  (HEAD `ec0f58a`): **all fourteen images 0 differing pixels, every scene
  identical**. Its controls at `cd84b0c` read light-vs-dark 1048576, f0-vs-f3
  0, chrome legacy-vs-proposal 0, distinct 544/216, prod default-vs-modal
  491221; two controls read other than the script header's quoted numbers
  (default-vs-modal 1031003 for 1030498, default-vs-animation 454895 for
  210027) — at `cd84b0c` itself, so not this lane's; reported, not corrected
  here.
- **Inventory**: `closeout-inventory-check.sh` and `closeout-undocumented.sh`
  print nothing; census re-recorded, **2540 → 2552** (`ColorPicker` and its
  members). A first map row for the three roles was `UNUSED` — enum cases are
  not census rows — and was removed.
- **Divergence 165** added (`docs/divergences.md`), pinned by
  `pressingTheWellOpensThePanelAndDoesNotFocus`; the header's count and
  next-label line are left to the merge (`LK-N`).

- **After the instrument repair** (`dce0364`), unmutated, native, unfiltered:
  **2768 tests in 3 suites passed**, `FR-J` line present, 0 `error:`.

### §1.3 Mutations

Each applied to the committed tree from a copy, native build, **full
unfiltered suite**, restored, `git status --short` clean after each (the
driver's own crash on M7 left `Slider.swift` mutated; restored with `git
checkout`, then clean). Spelling: the exact replacement in
`/private/tmp/…/mut/mutations.py`, summarised.

| # | mutation | reddened (full unfiltered suite) |
|---|---|---|
| M1 | `Window.dispatchValueTrack`: `.begin` after the press's write | `aPressWithNoDragIsTrueWriteFalse`, `aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit`, `aReleaseAfterTheSliderWasDisabledStillEndsTheEdit`, `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit`, `aSecondPressWithoutAReleaseEndsTheFirstEdit`, `aSliderPressCallsEditingTrueBeforeItsFirstWrite`, `aSliderReleaseCallsEditingFalseAfterTheLastWrite`, `closingTheWindowMidDragEndsTheEdit` |
| M2 | top-of-hook end for `.mouseDown` only (no release end) | `aPressWithNoDragIsTrueWriteFalse`, `aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit`, `aReleaseAfterTheSliderWasDisabledStillEndsTheEdit`, `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit`, `aSliderReleaseCallsEditingFalseAfterTheLastWrite`, `theEditingCallbacksRunUnderTheSlidersDispatch`, `theReleaseIsNotClaimedByTheSlider` |
| M3 | the end moved into `dispatchValueTrack`'s `.mouseUp` case (the first design's spelling) | `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit` |
| M4 | top-of-hook end for `.mouseUp` only (a press overwrites an open edit) | `aSecondPressWithoutAReleaseEndsTheFirstEdit` |
| M5 | the end returns `true` (claims the event) | `aSecondPressWithoutAReleaseEndsTheFirstEdit`, `theReleaseIsNotClaimedByTheSlider` |
| M6 | `endSliderEdit` calls the end outside `StateDispatch` | `theEditingCallbacksRunUnderTheSlidersDispatch` |
| M7 | `Slider.prepaint`'s adjust closure without the `true`/`false` pair | `anAccessibilityIncrementIsAWholeEdit`, `anArrowKeyIsAWholeEdit` |
| M8 | `runDisappearancesForClose` without `endSliderEdit()` | `closingTheWindowMidDragEndsTheEdit` |
| M9 | `endSliderEdit` ends only if the id still has a track in `lastHitboxes` | `aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit`, `aReleaseAfterTheSliderWasDisabledStillEndsTheEdit` |
| M10 | the `onEditingChanged` public init made internal | build failed: the demo module calls the init (`ControlsDemo.swift:169`, `:377`); replaced by M10b |
| M11 | `ColorPicker` without `StyledElement` | `aColorPickerTakesABackgroundAndPadding` |
| M12 | `ColorWell.gap` 6 | `aColorPickerInAVStackKeepsItsLabelBesideTheWell`, `aColorPickerInAnHStackKeepsItsOwnEightPointGap`, `aColorPickerIsItsLabelEightPointsAndAFortyEightByTwentyFourWell` |
| M13 | the gap kept with an empty title | **none (green)** |
| M14 | the picker's box a column (stand-in for "a `Component` of two top-level nodes") | `aColorPickerInAVStackKeepsItsLabelBesideTheWell`, `aColorPickerInAnHStackKeepsItsOwnEightPointGap`, `aColorPickerIsItsLabelEightPointsAndAFortyEightByTwentyFourWell` |
| M15 | the well's press also requests focus (`ClickDispatch.focusRequest`) | `pressingTheWellOpensThePanelAndDoesNotFocus` |
| M16 | the well takes Return only | `spaceOnAFocusedWellOpensThePanel` |
| M17 | the square's drag swaps saturation and brightness | `anOutsideWriteWhileOpenReSeedsThePanel`, `theHueSurvivesSaturationZeroWhileDragging` |
| M18 | a hue drag resets saturation and brightness to 1 | `aDragOnTheHueBarWritesTheHueKeepingSaturationAndBrightness` |
| M19 | the opacity bar shown regardless | `theOpacityBarIsAbsentWithoutSupportsOpacity` |
| M20 | `apply` passes the panel's alpha without `supportsOpacity` | `everyWriteHasOpacityOneWithoutSupportsOpacity` |
| M21 | `current` ignores the panel's edit (re-seeds every frame) | **none (green)** |
| M22 | `current` uses the edit whatever the binding holds | `anOutsideWriteWhileOpenReSeedsThePanel` |
| M23 | the seed resolved in a light scheme and theme | `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral` |
| M24 | `parseHex` accepts five digits | `anInvalidHexRevertsAndWritesNothing`, `parseHexAcceptsTheFourFormsAndNothingElse` |
| M25 | an invalid submit writes black | `alphaHexIsRefusedWithoutSupportsOpacity`, `anInvalidHexRevertsAndWritesNothing` |
| M26 | the field accepts `#RRGGBBAA` without `supportsOpacity` | `alphaHexIsRefusedWithoutSupportsOpacity` |
| M27 | the field always shows eight digits | `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral`, `anInvalidHexRevertsAndWritesNothing`, `theHexFieldShowsUppercaseWithAlphaOnlyBelowOne` |
| M28 | every key step ×10 unshifted | `squareAndBarKeysStepByOneHundredthAndShiftByATenth` |
| M29 | the well's popover binding ignores `false` | `escapeClosesThePanel` |
| M30 | the hue bar publishes no value | `thePanelsSlidersPublishTheirValues` |
| M31 | `ColorMath.byte` truncates | `hexStringIsUppercaseRoundedAndCarriesAlphaOnlyWhenAsked`, `hsbRoundTripsEveryByteTriple`, `theHexFieldShowsUppercaseWithAlphaOnlyBelowOne` |
| M32 | `axNumber` prints `%.3f` | `axComponentsPrintLikeAppKit`, `theWellPublishesAColorWellWithAppKitsValueFormat` |
| M33 | AppKit maps `.colorWell` to `.group` | `theThreeNewRolesHaveRowsOnTheAppKitBridge` |
| M34 | the well registers under an environment forced enabled (outside the gate) | `aDisabledColorPickerOpensNothing` |
| M35 | `hsb(from:)` brightness from the minimum component | `aDragOnTheHueBarWritesTheHueKeepingSaturationAndBrightness`, `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral`, `anInvalidHexRevertsAndWritesNothing`, `hsbOfThePrimariesAndGreys`, `hsbRoundTripsEveryByteTriple`, `squareAndBarKeysStepByOneHundredthAndShiftByATenth`, `theHexFieldAcceptsTheFourForms`, `theHexFieldShowsUppercaseWithAlphaOnlyBelowOne`, `thePanelsSlidersPublishTheirValues` |
| M36 | `hexString` lowercase | `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral`, `anInvalidHexRevertsAndWritesNothing`, `hexStringIsUppercaseRoundedAndCarriesAlphaOnlyWhenAsked`, `theHexFieldShowsUppercaseWithAlphaOnlyBelowOne` |
| M17 | the same, on the repaired test (press at (¼, ½)) | `aDragOnTheSquareWritesSaturationAndBrightness`, `anOutsideWriteWhileOpenReSeedsThePanel`, `theHueSurvivesSaturationZeroWhileDragging` |
| M21 | the same, on the repaired test (a key step on the latest frame) | `theHueSurvivesSaturationZeroWhileDragging` |
| M13b | an empty title keeps a `Text("")` label | `aColorPickerWithAnEmptyTitleIsTheWellAlone` |
| M10b | the public inits' external label renamed `onEditingChange` (callers in the demo and `SliderEditingTests` renamed with it) | `theSliderInitialisersKeepTheirSwiftUISpellings` |
| M37 | the demo section inlined into `controlsDemoContent()` | **none (green)** |
| M38 | the slider registers under an environment forced enabled | `aDisabledSliderNeitherTracksNorAdjustsAndPublishesDisabled`, `aDisabledSliderPressCallsNothing`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` |
| M39 | `Slider.paint` calls `onEditingChanged(false)` | `aDisabledSliderPressCallsNothing`, `aPressWithNoDragIsTrueWriteFalse`, `aReleaseAfterTheSliderLeftTheTreeStillEndsTheEdit`, `aReleaseAfterTheSliderWasDisabledStillEndsTheEdit`, `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit`, `aSecondPressWithoutAReleaseEndsTheFirstEdit`, `aSliderPressCallsEditingTrueBeforeItsFirstWrite`, `aSliderReleaseCallsEditingFalseAfterTheLastWrite`, `anAccessibilityIncrementIsAWholeEdit`, `anArrowKeyIsAWholeEdit`, `anOutsideBindingWriteCallsNothing`, `closingTheWindowMidDragEndsTheEdit`, `theEditingCallbacksRunUnderTheSlidersDispatch` |
| M40 | `Backends/SDL` `numericValue` sends a busy indicator's value | **none (green)**: a busy node has no value to send, so this spelling is correct (`LR-X`) |
| M40b | `Backends/SDL` `numericRange` set for a busy indicator | `theThreeNewRolesHaveRowsOnAccessKit` (SDL suite, macOS) |

Findings from the mutations: **M13** is the correct spelling (a box's gap
applies only between children, and the empty title produces none) — M13b is
the separating one. **M17** and **M21** were green on the first spellings of
`aDragOnTheSquareWritesSaturationAndBrightness` (a press at (¼, ¼), where
swapping the axes writes the same colour) and
`theHueSurvivesSaturationZeroWhileDragging` (a drag runs on the callbacks its
press captured, whose `seed` is still the press frame's — so it cannot tell a
re-seed from white): both tests repaired (commit `dce0364`), both mutations
re-run red. **M37** is green: the section is small enough that inlining it
into `controlsDemoContent()` does not overflow the 1 MB thread, so
`everyProductionTreeBuildsOnAOneMegabyteThread` does not separate it (the
spec's expectation that it would was unmeasured); the section stays in its own
function by the rule. Every other mutation reddened the tests named for it.

### §1.4 Deferred and owed

- The native `NSColorPanel` route (`LK-C` item 6, C10-b), unchanged.
- Human checks owed (spec §7 items 1, 2, 10): the well's look beside an
  `NSColorWell`, the panel's drag and keys, one undo step per drag in
  MetalCreator, VoiceOver on the well and the panel's sliders.
- A real-window look was not taken (the lock probe was not run by this lane).

## §2 Lane 2 — progress view and keyframes

Commits: `2afcabd` (red: tests and API stubs), `a31d446` (implementation,
ruling `LK-V`, divergences 168, 169, 171, census, two demo sections), the
record commit (this section).

### §2.1 Red

45 root tests (18 `ProgressViewTests`, 1 `ProgressViewCompileGuards`, 15
`KeyframeTimelineTests`, 8 `KeyframeAnimatorTests`, 3
`KeyframeCompileGuards`) written against stubs carrying the public surface with
every answer wrong (`2afcabd`). Filtered run on the stub: **39 of 45 failed**.
The 6 that passed were the four guards
(`progressViewSpellingsTypecheckFromAnExternalModule`,
`keyframeAnimatorTypechecksWithSwiftUIsCallShape`,
`userConformancesToKeyframesDoNotCompile`,
`springKeyframeWithoutDurationDoesNotCompile`),
`theAnimatorShowsTheInitialValueAndCallsNoKeyframesOnAppearK10` (the stub's
"show the initial value, run nothing" is K10's answer) and
`theKeyframeScopeTakesNoIdentityLevel` (the stub took no level either) — all
six are absent API at `cd84b0c`, so none compiled there; each is reddened by a
mutation in §2.3. First failure line per test (abridged; each `Expectation
failed:`):

| test | first red line |
|---|---|
| `linearKeyframesMatchK1` | `KeyframeTimelineTests.swift:43` `abs(timeline.duration - 0.6) < 1e-12` |
| `easeInOutMatchesK2`, `aLoneCubicIsSmoothstepK3b`, `cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g`, `aCubicTakesALinearNeighboursVelocityK3dK3h`, `anExplicitStartVelocityWinsK3e`, `aSpringKeyframeHoldsWhereItsDurationEndsK4`, `aSpringCarriesTheIncomingVelocityK4e`, `theNextKeyframeStartsFromTheSpringsValueK4c`, `aMoveKeyframeJumpsK5` | `:53`, `:60`, `:76`, `:103`, `:120`, `:130`, `:143`, `:156`, `:189` `misses.isEmpty` |
| `springValuesMatchK4dAtPointOne` | `:173` `abs(value - arm.value) <= 0.005` |
| `tracksRunInParallelAndHoldK6` | `:206` `abs(timeline.duration - 0.6) < 1e-12` |
| `anUntrackedFieldKeepsItsInitialValueK7` | `:227` `abs(value.x - x) <= 0.001 && value.s == s` |
| `aZeroDurationKeyframeReadsItsTarget` | `:243` `value == 10` |
| `valueProgressClampsK9` | `:261` `zip(values, [0.0, 5, 10, 10]).allSatisfy …` |
| `aTriggerFromRestRestartsFromTheInitialValueK11K12` | `KeyframeAnimatorTests.swift:79` `log.starts == [0]` |
| `aTriggerMidRunStartsFromTheCurrentValueK13` | `:98` `log.starts.count == 2 && …` |
| `theAnimatorHoldsItsEndValueAtRest` | `:111` `log.values.suffix(4).allSatisfy { near($0, 20) }` |
| `repeatingLoopsAndCallsKeyframesOnceK14` | `:134` `log.starts == [0]` |
| `theAnimatorNotesAnimationOnlyWhileRunning` | `:151` `started.hasActiveAnimations && midway.hasActiveAnimations` |
| `keyframeAnimatorKeepsProposalContentProposal` | `:196` `width(…) == 20` |
| `theSpinnerIsThirtyTwoSixteenAndTenByControlSize` | `ProgressViewTests.swift:121` `answer == SizeD(width: side, height: side)` |
| `theBarIsGreedyTwentyTallAndZeroWideAtNil` | `:137` `measured["ideal"] == SizeD(width: 0, height: 20)` |
| `aSmallBarIsTwelveTall` | `:148` `measured["w200"] == …` |
| `aTitledBarStacksTheTitleAboveWithNoGap` | `:158` `measured["ideal"] == …` |
| `aCurrentValueLabelSitsBelowInTheCaptionFont` | `:176` `measured["w300"] == …` |
| `aTitledSpinnerStacksTheTitleBelowFourPointsApart` | `:185` `measured["ideal"] == …` |
| `aTitledProgressViewInAnHStackStacksItsTitleAbove` | `:202` no 100 × 20 bar |
| `aValueAboveTheTotalDrawsFull` | `:238` `bars.count == 2` |
| `progressViewStyleCircularDrawsARingAndLinearAnIndeterminateBar` | `:268` `ring["w300"] == SizeD(width: 32, height: 32)` |
| `theInnermostProgressViewStyleWins` | `:283` `own["w300"] == SizeD(width: 300, height: 20)` |
| `theSpinnerAdvancesTwentyFourStepsPerPointEightSeconds`, `reduceMotionDoesNotStopTheSpinner` | `:88` `leaves.count == 1` |
| `anIndeterminateViewKeepsTheWindowAnimatingAndADeterminateOneDoesNot` | `:309` `spinner.hasActiveAnimations` |
| `aHiddenOrZeroSizeSpinnerRequestsNoFrames` | `:337` `visible.hasActiveAnimations` |
| `aNegativeValueOrAZeroTotalIsIndeterminate`, `aNonFiniteValueIsIndeterminateAndNothingNonFiniteIsStored`, `aDeterminateViewPublishesAProgressIndicatorWithTheFraction`, `anIndeterminateViewPublishesABusyIndicatorWithNoValue` | `ButtonTests.swift:107` (the shared AX helper) `platform.publishedAccessibilityTrees.last` |

### §2.2 Landing

- **Suite** (HEAD `a31d446`), native build, unfiltered `--no-parallel`:
  **2813 tests in 3 suites passed** (2768 + 45), `FR-J no-argument frame:
  succeeded=true`, 0 `error:`, only SwiftPM's deprecation `warning:`.
  `swift build --build-tests` (default build system) 0 warnings.
- **The first green suites were not green**, both fixed before the
  implementation commit: run 1 (6 issues) — `everyProductionTreeBuildsOnAOneMegabyteThread`
  (`SIGBUS`: the looks tree with three temporaries), `theLooksDemoDrawsEverySurfaceItsHumanChecksName`
  and `theLooksColourSectionPaintsLiteralDynamicAndPaletteColours` (a `Button`
  as the shake trigger moved the click-target count and the bottom-most press)
  — `LK-V` item 9; run 2 (1 issue) — `aCurrentValueLabelSitsBelowInTheCaptionFont`,
  an instrument: the titled sizes compared an unrounded answer with rounded
  text bounds, and `captionSize` read an arbitrary recorded rect; repaired in
  the test file.
- **`Backends/SDL`** (no file of it touched): macOS **24 + 85**, Linux image
  **24 + 82**, unchanged from lane 1.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> cd84b0c HEAD`
  (HEAD `a31d446`): **all fourteen images 0 differing pixels, every scene
  identical**.
- **Inventory**: `closeout-inventory-check.sh` and `closeout-undocumented.sh`
  print nothing; census re-recorded, **2552 → 2647** (`ProgressView`,
  `ProgressViewStyle`, the keyframe types and builders, `VectorArithmetic`,
  `UnitCurve`, `Spring`, the animator).
- **Divergences 168, 169, 171** added, pinned by
  `springKeyframeWithoutDurationDoesNotCompile`,
  `keyframeAnimatorTypechecksWithSwiftUIsCallShape` and
  `aZeroDurationKeyframeReadsItsTarget`; the header's lines are left to the
  merge (`LK-N`).

### §2.3 Mutations

Each applied to the committed tree (`a31d446`) from a copy, native build,
**full unfiltered suite**, restored, `git status --short` empty after each.
Spellings: the exact replacements in `/private/tmp/…/lk2mut/mutate.py`,
summarised. Driven in two sittings (the first interrupted after `STEPS`; the
second ran `ALWAYS` onward and the two guard mutations `GPVa`/`GPVn` added
when `GPV` failed to build).

| id | mutation | reddened (full unfiltered suite, 2813 tests) |
|---|---|---|
| K1 | `KeyframeSegments`: `time += segment.duration` deleted (every segment starts at 0) | `aCubicTakesALinearNeighboursVelocityK3dK3h`, `aMoveKeyframeJumpsK5`, `aSpringCarriesTheIncomingVelocityK4e`, `aTriggerFromRestRestartsFromTheInitialValueK11K12`, `aTriggerMidRunStartsFromTheCurrentValueK13`, `cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g`, `linearKeyframesMatchK1`, `repeatingLoopsAndCallsKeyframesOnceK14`, `theAnimatorHoldsItsEndValueAtRest`, `theAnimatorNotesAnimationOnlyWhileRunning`, `theNextKeyframeStartsFromTheSpringsValueK4c`, `tracksRunInParallelAndHoldK6`, `valueProgressClampsK9` |
| K2 | a cubic/linear segment ignores its `UnitCurve` (progress `u`) | `easeInOutMatchesK2` |
| K3b | the first cubic's start velocity is the chord slope, not 0 | `aLoneCubicIsSmoothstepK3b`, `cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g` |
| K3g | the Catmull-Rom tangent divides by `2 × duration`, not the span | `cubicTangentsAreCatmullRomBetweenCubicsK3K3fK3g` |
| K3d | a cubic before a linear keyframe takes no velocity from it | `aCubicTakesALinearNeighboursVelocityK3dK3h` |
| K3e | an explicit `startVelocity:` ignored | `anExplicitStartVelocityWinsK3e` |
| K4 | a spring segment's end is its target, not where its duration ends | `aSpringKeyframeHoldsWhereItsDurationEndsK4`, `theNextKeyframeStartsFromTheSpringsValueK4c` |
| K4e | a spring starts at velocity 0, not the incoming one | `aSpringCarriesTheIncomingVelocityK4e` |
| K4c | the next keyframe starts from the spring's target | `theNextKeyframeStartsFromTheSpringsValueK4c` |
| K4d | `Spring`'s damping ratio `1 - bounce` for a negative bounce too (`Animation.swift`) | `springValuesMatchK4dAtPointOne` |
| K5 | segment search `endTime > time` (a move keyframe at its own time reads the old value) | `aMoveKeyframeJumpsK5` |
| K6 | timeline duration the sum of the tracks, not the maximum | `tracksRunInParallelAndHoldK6`, `valueProgressClampsK9` |
| K7 | a track starts from `.zero`, not the initial value's field | `aTriggerMidRunStartsFromTheCurrentValueK13`, `anUntrackedFieldKeepsItsInitialValueK7`, `tracksRunInParallelAndHoldK6`, `valueProgressClampsK9` |
| K8 | a zero-duration segment's guard deleted (divides by 0) | `aZeroDurationKeyframeReadsItsTarget` |
| K9 | `value(progress:)` scales by the first track's duration | `valueProgressClampsK9` |
| K10 | the animator runs its keyframes on appear | `aTriggerFromRestRestartsFromTheInitialValueK11K12`, `aTriggerMidRunStartsFromTheCurrentValueK13`, `keyframeAnimatorKeepsProposalContentProposal`, `theAnimatorHoldsItsEndValueAtRest`, `theAnimatorNotesAnimationOnlyWhileRunning`, `theAnimatorShowsTheInitialValueAndCallsNoKeyframesOnAppearK10` |
| K11 | a trigger from rest starts from the resting value, not the initial value | `aTriggerFromRestRestartsFromTheInitialValueK11K12` |
| K13 | a trigger mid-run starts from the initial value | `aTriggerMidRunStartsFromTheCurrentValueK13` |
| HOLD | the resting value is the initial value, not the timeline's end | `aTriggerFromRestRestartsFromTheInitialValueK11K12`, `aTriggerMidRunStartsFromTheCurrentValueK13`, `theAnimatorHoldsItsEndValueAtRest` |
| K14 | the timeline rebuilt every frame (`if true`) | `repeatingLoopsAndCallsKeyframesOnceK14` |
| NOTE | `noteActiveAnimation()` every frame, running or not | `theAnimatorNotesAnimationOnlyWhileRunning` |
| IDENT | the scope's content laid out under `.child(of: parent, at: 99)` | `theKeyframeScopeTakesNoIdentityLevel` |
| PROP | the proposal content built from `initialValue`, not the current value | `keyframeAnimatorKeepsProposalContentProposal` |
| G1 | the call-shape guard's negative arm without `.onClick {}` | `keyframeAnimatorTypechecksWithSwiftUIsCallShape` |
| G2 | the carriers' initialisers and storage types made public | `userConformancesToKeyframesDoNotCompile` |
| G3 | `SpringKeyframe`'s `duration:` defaulted to 1 | `springKeyframeWithoutDurationDoesNotCompile` |
| GPV | `ProgressView` without `StyledElement` | **build failed**: `ProgressViewTests.swift:330`–`:331` call `.hidden()`/`.opacity` on the view; not a mutation of the guard — replaced by `GPVa`, `GPVn` |
| V0 | `.mini` spinner 12 | `theSpinnerIsThirtyTwoSixteenAndTenByControlSize` |
| V3 | the bar's nil-width answer 30 | `theBarIsGreedyTwentyTallAndZeroWideAtNil` |
| V3s | a small bar 20 tall | `aSmallBarIsTwelveTall` |
| V4gap | a bar's title gap 4 | `aCurrentValueLabelSitsBelowInTheCaptionFont`, `aTitledBarStacksTheTitleAboveWithNoGap`, `aTitledProgressViewInAnHStackStacksItsTitleAbove` |
| V4cap | the current-value label in `.body` | `aCurrentValueLabelSitsBelowInTheCaptionFont` |
| V1 | the spinner's title above, like a bar's | `aTitledSpinnerStacksTheTitleBelowFourPointsApart` |
| LKP | the box a row | `aCurrentValueLabelSitsBelowInTheCaptionFont`, `aTitledBarStacksTheTitleAboveWithNoGap`, `aTitledProgressViewInAnHStackStacksItsTitleAbove`, `aTitledSpinnerStacksTheTitleBelowFourPointsApart` |
| V8neg | a negative value accepted (clamped to 0) | `aNegativeValueOrAZeroTotalIsIndeterminate` |
| V8full | a value above the total not clamped | `aValueAboveTheTotalDrawsFull` |
| NAN | no finiteness checks on value, total or fraction | `aNegativeValueOrAZeroTotalIsIndeterminate`, `aNonFiniteValueIsIndeterminateAndNothingNonFiniteIsStored` |
| STYLE | `.circular` with a value draws a bar, not the ring | `progressViewStyleCircularDrawsARingAndLinearAnIndeterminateBar`, `theInnermostProgressViewStyleWins` |
| INNER | the environment's style before the view's own | `theInnermostProgressViewStyleWins` |
| STEPS | 12 steps per period, not 24 | `reduceMotionDoesNotStopTheSpinner`, `theSpinnerAdvancesTwentyFourStepsPerPointEightSeconds` |
| ALWAYS | `noteActiveAnimation()` whatever the kind or visibility (`if true`) | `aHiddenOrZeroSizeSpinnerRequestsNoFrames`, `anIndeterminateViewKeepsTheWindowAnimatingAndADeterminateOneDoesNot` |
| VIS | the visibility test dropped (spinner/indeterminate bar only) | `aHiddenOrZeroSizeSpinnerRequestsNoFrames` |
| RM | Reduce Motion freezes the spinner (time 0) | `reduceMotionDoesNotStopTheSpinner` |
| RAW | the published value ×10 | `aDeterminateViewPublishesAProgressIndicatorWithTheFraction`, `progressViewStyleCircularDrawsARingAndLinearAnIndeterminateBar` |
| BUSY0 | a busy indicator publishes value `0` | `aNegativeValueOrAZeroTotalIsIndeterminate`, `anIndeterminateViewPublishesABusyIndicatorWithNoValue` |
| ROLE | `AccessibilityTreeBuilder` maps both hints to `.progressIndicator` | `aNegativeValueOrAZeroTotalIsIndeterminate`, `aNonFiniteValueIsIndeterminateAndNothingNonFiniteIsStored`, `anIndeterminateViewPublishesABusyIndicatorWithNoValue` |
| GPVa | the view's own `progressViewStyle(_:) -> ProgressView` made internal | `progressViewSpellingsTypecheckFromAnExternalModule` |
| GPVn | a public `progressViewStyle(_: String) -> Self` on `ElementGroup` | `progressViewSpellingsTypecheckFromAnExternalModule` |

Every mutation reddened the tests named for it; none stayed green and none
hung. Findings: `GPV` breaks the test target, so the guard's doc comment named
an unobservable mutation — rewritten to name `GPVa` and `GPVn` (the record
commit). `K10` and `IDENT` redden the two tests that passed on the stub, and
`G1`–`G3`, `GPVa`, `GPVn` redden the four guards that did.

### §2.4 Deferred and owed

- `phaseAnimator`/`PhaseAnimator` are not built (`LK-H`: it needs an
  unmeasured logical-completion rule for springs and new transaction plumbing;
  additive later).
- Human checks owed (spec §7 items 3, 4, 9, 10): the spinner at 32/16/10
  against `NSProgressIndicator` and its step rate, the indeterminate bar's
  motion, the determinate bar's colours in both schemes and key/inactive
  windows, the shake at 60 and 120 Hz, VoiceOver on a determinate and a busy
  indicator.
- A real-window look was not taken (the lock probe was not run by this lane).


### §2.5 Review fixes (lane 2)

The lane-2 review's two majors and five minors, each red-first, committed as
`1fbf9cf`. Native build, full unfiltered suite: **2820 tests in 3 suites passed**
(2813 + 7), `FR-J no-argument frame: succeeded=true`.

- **Sibling records (major).** `siblingKeyframeAnimatorsKeepTheirOwnRecordsV4`:
  two trigger animators in one `Row` (only one trigger changes), and a trigger
  animator beside a repeating one.
- **Handler-carried modifiers (major).** `aProgressViewTakesHandlerCarriedModifiersV5`:
  a click on a spinner with `.onClick` runs, and `.accessibilityLabel` labels the
  one busy indicator. These are **two windows**. One window carrying both
  modifiers publishes no progress node: a clickable element synthesizes a
  `.button`, and `publishedRole` maps the progress hint only from `.group`,
  so a clickable `ProgressView` publishes as a button. This is measured here,
  not ruled. Owed: a ruling, and a SwiftUI probe of `ProgressView().onTapGesture`'s
  role. It is accessibility, which this fix does not move.
- **K12 after an unseen end (minor, a fix).** `KeyframeAnimator.resolve`'s
  trigger branch now treats `running && now - start >= duration` as rest,
  storing the end value as `resting` before the restart. Frames 0, 1, 1.19,
  1.21 give starts `[0, 0]` (were `[0, 20]`):
  `aTriggerJustAfterAnUnseenEndRestartsFromTheInitialValue`, red before the
  fix.
- **Stacked animators (minor).** `stackedKeyframeAnimatorsKeepTwoRecordsV1b`.
- **The progress-hint strip (minor).** `anUntitledProgressViewWritesNoAXSlotAndNoDeclaredNodeV3`:
  no `axNodes` entry, no `$ax` slot, and the client record carries `.busy`.
- **Trap exit tests (minor).** `theKeyframeAndSpringPreconditionsTrap`:
  `LinearKeyframe(1.0, duration: .nan)`, `Spring(duration: .infinity)` and
  `Spring(bounce: 1)` each abort, with their message.
- **The moving sweep (minor).** `theIndeterminateBarSegmentMovesWithTheClockV6`:
  segment offset 0 at t = 0 and 35 at 0.4 s in a 100-wide track.

Each mutation was applied to `1fbf9cf` and restored from the committed source,
then a native build and a **full unfiltered suite** (2820 tests) ran.
`git status --short` was empty after each.

| id | mutation | reddened |
|---|---|---|
| V4 | `currentValue`'s owner `child(of: parent, at: cursor, …)` → `at: 0` | `siblingKeyframeAnimatorsKeepTheirOwnRecordsV4` |
| V1b | `withKeyframeScope`'s increment and deferred decrement deleted | `stackedKeyframeAnimatorsKeepTwoRecordsV1b` |
| K12 | the new end-of-run check disabled (`if false, …`) | `aTriggerJustAfterAnUnseenEndRestartsFromTheInitialValue` |
| V9 | `keyframeDuration`'s precondition deleted | `theKeyframeAndSpringPreconditionsTrap` |
| V5 | `ProgressView.prepaint`'s `layout.body.handlers = handlers` deleted | `aProgressViewTakesHandlerCarriedModifiersV5`, plus `aWheelMouseEventReachesOnInputInPointsAndATrackpadEventIsUnchanged` (`PlatformTests`, real `NSEvent` wheel deltas): unrelated to the mutation, green in the unmutated run and in the six other mutated runs, so environmental |
| V3 | `registerHandlers`' `declaration.progressHint = nil` deleted | `anUntitledProgressViewWritesNoAXSlotAndNoDeclaredNodeV3` |
| V6 | `paintSweep`'s `travel` → `0.0` | `theIndeterminateBarSegmentMovesWithTheClockV6` |

## §3 Lane 3 — looks (gradients, blur, materials)

Commits: `87b82ce` (red: tests and API stubs), `5927784` (implementation,
ruling `LK-W`, divergences 166, 167, census, demo section, replay frame 8 and
CI `--expect 9`), the record commit (this section). Baseline: lane 2's review
head `2e99439`, **2820 tests** (§2.5).

### §3.1 Red

30 root tests (10 `GradientTests`, 6 `GradientRasterTests`, 11 `BlurTests`, 2
`MaterialTests`, 1 `LooksCompileGuards`) written against stubs carrying the
public surface with every answer wrong (`87b82ce`: a gradient view of ideal 0
painting nothing, a gradient fill painting nothing, a table of zeros, a blur
returning its content, materials `.clear`). Filtered run on the stub: **27 of
30 failed** (the commit message's "29 of 32" miscounted the files; the run's
own lines are these). The 3 that passed: `aBlurOfRadiusZeroDrawsTheLeafUnchanged`
(the stub's "no blur" is radius 0's answer), `theLayoutModifierBlurCaseIsOneIdentityLevel`
(the stub already wrapped one layer) and `materialSpellingsResolveWithoutAmbiguity`
(the overloads were the stub) — all absent API at `cd84b0c`, each reddened by
a mutation in §3.3. First failure line per test (each `Expectation failed:`):

| test | first red line |
|---|---|
| `theOklabTableMatchesG11G2G5` | `GradientTests.swift:95` `lkNear(g11, [140, 83, 162], 1)` |
| `aVerticalGradientSamplesAtPixelCentresG1` | `:112` `lkNear(got, want, 1)` |
| `aDiagonalGradientsIsolinesArePerpendicularInPointsG3` | `:129` `lkNear(a, [73, 73, 72], 2)` |
| `stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7` | `:150` `lkNear(at(g4, x), want, 2)` |
| `aDegenerateGradientDrawsTheLastColourG6` | `:176` `lkNear(got, [0, 0, 255], 1)` |
| `aRadialGradientIsCircularInPointsR1R2` | `:192` `abs(got[0] - want) <= 2` |
| `aGradientFilledCircleIsCutByTheCircleG8` | `:211` `lkNear(at(20, 1), [0, 1, 0], 3)` |
| `aLinearGradientViewIsGreedyWithAnIdealOfTenG10` | `:228` `images.count == 1` |
| `legacyAndProposalBackgroundGradientsFillTheFrameG9` | `:251` `abs(got[0] - want) <= 2` |
| `aGradientChangeSnaps` | `:279` `lkNear(got, [0, 255, 0], 3)` |
| `anAxisAlignedRectGradientDrawsAOnePixelStrip` | `GradientRasterTests.swift:32` `tallImages.count == 1` |
| `aDiagonalOrClippedGradientRastersInFull` | `:69` `images.count == 1` |
| `anUnchangedGradientKeepsItsTextureIdentity` | `:99` `first.count == 1 && again.count == 1` |
| `aChangedStopMakesANewTexture` | `:117` `gxImages(red).count == 1 && …` |
| `aGradientUnderARotationFollowsTheTransform` | `:133` `gxImages(scene).count == 1` |
| `aShadowSeesAGradientLeafsAlpha` | `:150` `images.count == 2` |
| `blurIsPerLeafB2` | `BlurTests.swift:34` `gxImages(scene).count == 2` |
| `blurSigmaIsTheRadiusB1` | `:48` `gxImages(scene).count == 1` |
| `aBlurChangesNoLayoutHitOrAccessibilityB4` | `:96` `gxImages(window.lastScene).count == 2` |
| `aClipOutsideTheBlurCutsItB5` | `:109` `images.count == 1` |
| `aTextRunBlursAsOneLeaf` | `:124` `gxImages(scene).count == 1` |
| `aSurfaceLeafUnderBlurIsDrawnUnblurred` | `:139` `gxImages(scene).count == 1` |
| `theBlurRadiusAnimates` | `:157` `midway.count == 1 && four.count == 1` |
| `aNonFiniteBlurRadiusTraps` | `:178` expected exit status `.failure`, but `.exitCode(EXIT_SUCCESS)` |
| `theLegacyBlurJoinsRenderEffectsInWrittenOrder` | `:199` `scaledBlur.count == 1 && blurredScale.count == 1` |
| `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` | `MaterialTests.swift:48` `abs(white - want.white) <= 1 && …` |
| `aMaterialFollowsTheColourScheme` | `:82` `light.count == 3 && dark.count == 3` |

Three test edits after the red commit, each in `LK-W`: G1's y 0 takes ±3
(item 2), the sampler `lkSample` honours an image's mask radii as the shader
does (the circle's strip-path quad is cut there — the first green run read the
G8 corner black because the helper ignored the radii), and `aGradientChangeSnaps`
compares with a fresh window (item 7).

### §3.2 Landing

- **Suite** (HEAD `5927784`), `swift package clean`, native build, unfiltered
  `--no-parallel`: **2850 tests in 3 suites passed** (2820 + 30),
  `FR-J no-argument frame: succeeded=true`, 0 `error:`, only SwiftPM's
  deprecation `warning:`; guard 3.T1 ran (`CONTROLS LOOKS GUARD 3.T1 positive:
  succeeded=true`). `swift build --build-tests` (default build system) 0
  warnings.
- **The first green suites were not green**, both fixed before the
  implementation commit: run 1 and run 2 (2850, one issue each) —
  `everyProductionTreeBuildsOnAOneMegabyteThread` (`.signal(SIGBUS)`), from
  `Decoration` growing by the inline `backgroundGradient` (272 bytes; it failed
  with the new demo section removed too) and from the section composed inline
  — `LK-W` item 10: `clipShape` and `backgroundGradient` boxed (224 bytes), the
  section a `Component`. Before them the lane's own filtered run found
  `blurIsPerLeafB2` reading the red leaf's texture for the blue one (the
  shadow's alpha-only leaf key, `LK-W` item 4) and an `AlphaMask` precondition
  (a quad built from an empty mask; `RasterPlacement.quad(over: RasterRect)`).
- **`Backends/SDL`**: no file of it touched (the `LK-S` mutation was applied
  and restored in place, §3.3); not re-run.
- **Replay** (`LK-S`): `Experiments/SDLGPU` `Replay --portable --record
  fixtures` (SDL GPU over Metal, SPIR-V → MSL): frames 0–8 **0 differing
  pixels**, frame 8 "(gradients and blur) 640x380: 0 rects, 0 glyphs, 5 images,
  5 runs"; draw-order control detected (283 px, Δ152). `Backends/SDL`
  `PortableReplay … --driver metal --expect 9`: **9 fixtures, every frame 0 px,
  PASS**. CI's two `--expect 8` are `--expect 9`; Linux llvmpipe and Windows
  D3D12 confirm on push.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> cd84b0c HEAD`
  (HEAD `5927784`): controls as recorded, **all fourteen images 0 differing
  pixels, every scene identical**.
- **Inventory**: `closeout-inventory-check.sh` and `closeout-undocumented.sh`
  print nothing; families `gradients` (A), `blur` (D 167), `materials`
  (D 166); census re-recorded, **2647 → 2711**.
- **Divergences 166, 167** added, pinned by
  `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` and
  `aSurfaceLeafUnderBlurIsDrawnUnblurred`; the header's lines are left to the
  merge (`LK-N`).
- **A real window**: the lock probe allowed it (no `CGSSessionScreenIsLocked`
  line, `displayAsleep main: 0`) during the replay; no window capture was taken
  of the demo (human checks 5–8 stay owed).

### §3.3 Mutations

Each applied to the committed tree (`5927784`) from a copy, native build,
**full unfiltered suite** (2850 tests), restored, `git status --short` empty
after each (`runner.log` in the session scratchpad's `lk3mut/`). No hang.

| id | mutation (spelling, file) | reddened |
|---|---|---|
| L1 | `GradientTable.make`: `toOklab`/`fromOklab` replaced by the identity (premultiplied gamma sRGB) | `aDiagonalGradientsIsolinesArePerpendicularInPointsG3`, `aGradientFilledCircleIsCutByTheCircleG8`, `aRadialGradientIsCircularInPointsR1R2`, `aVerticalGradientSamplesAtPixelCentresG1`, `legacyAndProposalBackgroundGradientsFillTheFrameG9`, `stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7`, `theOklabTableMatchesG11G2G5` |
| L2 | both sample sites drop the half pixel: the strip's texel centre `origin + i·length/count`, the full raster's `inverse.apply(x, y)` | `aGradientFilledCircleIsCutByTheCircleG8`, `aRadialGradientIsCircularInPointsR1R2`, `aVerticalGradientSamplesAtPixelCentresG1`, `legacyAndProposalBackgroundGradientsFillTheFrameG9`, `stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7`, `theOklabTableMatchesG11G2G5` |
| L3 | `GradientAxis.parameter` (linear): `((x − sx)/dx + (y − sy)/dy)/2` when both deltas are non-zero — unit space for a corner-to-corner axis | `aDiagonalGradientsIsolinesArePerpendicularInPointsG3` |
| L4 | `GradientStops`' sort compares indices (`$0 < $1`): written order | `stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7` |
| L5 | start == end answers `t = 0` (the first colour) | `aDegenerateGradientDrawsTheLastColourG6` |
| L6 | radial distance with `dx²/4` (elliptical) | `aRadialGradientIsCircularInPointsR1R2` |
| L7 | `paintGradientFill`: `Path(geometry.rect)` for a built-in geometry | **none (green)** — see below |
| L7r | the strip quad's `maskCornerRadii` zero (a circle drawn as its bounding square) | `aGradientFilledCircleIsCutByTheCircleG8`, `anAxisAlignedRectGradientDrawsAOnePixelStrip` |
| L8 | the gradient view's nil axis `?? 0` | `aLinearGradientViewIsGreedyWithAnIdealOfTenG10` |
| L9a | `paintDecorationBody`: `if let gradient, false` | `legacyAndProposalBackgroundGradientsFillTheFrameG9` |
| L9b | `ProposalElementGroup.background(_: LinearGradient)`: `alignment: .topLeading` | **none (green)** — see below |
| L9c | the gradient view answers 10 × 10 whatever the proposal | `aLinearGradientViewIsGreedyWithAnIdealOfTenG10`, `legacyAndProposalBackgroundGradientsFillTheFrameG9` |
| L10 | `gradientImage`: `if transform == nil, false, let strip` | `anAxisAlignedRectGradientDrawsAOnePixelStrip` |
| L11 | `stripImage`'s axis test `|| true` (a diagonal takes the strip) | `aDiagonalGradientsIsolinesArePerpendicularInPointsG3`, `aDiagonalOrClippedGradientRastersInFull` |
| L12 | `key.words += paint.stops.keyWords` deleted from the strip's and the full raster's keys | `aChangedStopMakesANewTexture`, `aGradientChangeSnaps` |
| L13 | `RasterCache.image`: `if false, let hit` | `anUnchangedGradientKeepsItsTextureIdentity` |
| L14 | `gradientPixels`: the device pixel centre used as the outline point (no inverse map) | `aGradientUnderARotationFollowsTheTransform` |
| L16 | the shadow silhouette of a gradient: its bounding rect filled | `aShadowSeesAGradientLeafsAlpha` |
| B2 | composite first: the blur scope collects every leaf (`scope.captures`) and `paintWithBlur` inserts ONE blur item at its exit | `blurIsPerLeafB2`, `theLegacyBlurJoinsRenderEffectsInWrittenOrder` |
| B1 | `blurLayer`: `sigma = radius × linearScale / 2` | `aClipOutsideTheBlurCutsItB5`, `blurIsPerLeafB2`, `blurSigmaIsTheRadiusB1`, `theLegacyBlurJoinsRenderEffectsInWrittenOrder` |
| B4 | `LayoutModifier.blur`'s wrapper a padding of 3 × radius | `aBlurChangesNoLayoutHitOrAccessibilityB4`, `aClipOutsideTheBlurCutsItB5` |
| B5 | `paintWithBlur`'s entry mask unbounded (±100000) | `aClipOutsideTheBlurCutsItB5` |
| B6 | the blur branch makes one blur item per primitive of the leaf | `aTextRunBlursAsOneLeaf` |
| B7 | the blur branch drops an all-surface leaf | `aSurfaceLeafUnderBlurIsDrawnUnblurred` |
| B8 | `LayoutModifier.animate`: `.blur` keeps its declared radius (no track) | `theBlurRadiusAnimates` |
| B9 | `paintWithBlur`: `guard r >= 0` | `aBlurOfRadiusZeroDrawsTheLeafUnchanged` |
| B10 | both `precondition(radius.value.isFinite, …)` deleted | `aNonFiniteBlurRadiusTraps` |
| B11 | the legacy `blur(radius:)` inserts its effect at index 0 | `theLegacyBlurJoinsRenderEffectsInWrittenOrder` |
| B12 | the proposal `blur(radius:)` wraps a second `.padding(0)` layer | `theLayoutModifierBlurCaseIsOneIdentityLevel` |
| M1 | `Material.fill`: light thin and thick rows swapped | `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` |
| M2 | `Material.fill`: `switch (kind, false)` (light in dark) | `aMaterialFollowsTheColourScheme`, `everyMaterialMatchesSwiftUIOverWhiteAndBlackM5` |
| G1 | `Material` gains `public static let surface` | **the module fails to build**: `ToolbarStrip.swift:78:26: error: ambiguous use of 'surface'` (MetalUI's own `.background(.surface)`) — the hazard the guard names, reddened before the guard can run |
| G2 | `ElementGroup.background(_: Material, in:)` moved to `ProposalElementGroup` | `materialSpellingsResolveWithoutAmbiguity` |

- **L7 green, explained**: a `Circle` is a built-in rounded rectangle (radius
  = half the side), so it takes the strip, whose mask radii cut it — the path
  `paintGradientFill` builds is not on its route. Respelled at the strip's
  radii (L7r), red.
- **L9b green, the correct spelling** (`LR-X`): a greedy attachment fills the
  primary whatever its alignment. The proposal arm's separating mutation is
  L9c (the view not greedy), red.
- **`aGradientChangeSnaps` (`LK-J` item 7)** pins a rule with no animating code
  to break; L12 (stale stops) reddens it as a stale raster would.
- **The replay (`LK-S` item 3)**: `SDLBridge.c` line 158, the one image
  sampler's `address_mode_v` → `SDL_GPU_SAMPLERADDRESSMODE_REPEAT`, applied in
  place and restored from a copy (never committed; `git status` empty after),
  `PortableReplay … --driver metal --expect 9`: **frame 6 fails first**
  (`inside glyph and image quads: 12223 px, max Δ99 (≤8)`; the replay stops
  there), frames 0–5 pass. Frame 8 alone (a directory holding only
  `frame-8.muireplay`, `--expect 1`): **fails, 101 px, max Δ40** under the
  mutant and passes unmutated (0 px). So frame 8 separates the sampler's edge
  mode on its own, but frame 6's stretched images already did: the fixture is
  not the first witness (`LK-W` item 12).
- **The 1 MB thread**: `LK-W` item 10's two measurements (inline
  `backgroundGradient`; the section inline) are this lane's reddening of
  `everyProductionTreeBuildsOnAOneMegabyteThread`.

### §3.4 Deferred and owed

- `AngularGradient`, `EllipticalGradient`, `Gradient.colorSpace(_:)`,
  `.foregroundStyle(gradient)`, gradient animation, `.blur(radius:opaque:)`
  — `LK-A`, unchanged. Backdrop blur for materials — C10-c (`LK-L` item 4).
- The Record phase owes: `docs/migration.md`'s `LayoutModifier.blur` note
  (`LK-W` item 11), divergences 166/167 in record §04, human checks 5–8 (spec
  §7), the `LK-W` spellings in CLAUDE.md's one-line rule.
- `ShapeView`'s chained `stroke(_:)` with a gradient is not offered (spec §1
  named `fill` only); `Shape.stroke(gradient…)` is.

### §3.5 Review fixes (lane 3)

The lane-3 review's three majors and one minor, each a missing pin on existing
code (no source change), committed as `2456d60`; the fifth item (the
verifier's shared-scratchpad note) asks nothing of the lane — this run used its
own `lk3fix-c10/`. Native build, full unfiltered suite: **2857 tests in 3
suites passed** (2850 + 7), `FR-J no-argument frame: succeeded=true`, 0
`error:`.

- **Gradient opacity (major).** `anOpacityScalesAGradient` (3.30: `.opacity(0.5)`
  over the strip and the full raster gives image opacity 0.5, and a legacy
  gradient background inside a legacy `.opacity`), `aFadingTransitionScalesAGradientsAlpha`
  (3.31: half-way through a `.transition(.opacity)` insertion the image's
  opacity is 0.5 on the flattening route and, under `.rotationEffect(30°)`, on
  the non-flattening one), `aGradientWrittenAfterOpacityEscapesIt` (3.32:
  `Box().frame(…).opacity(0.5).background(gradient)` draws at opacity 1).
- **The strip's rounded-clip guard (major).** `aRoundedClipCutsAStripCandidate`
  (3.33): a leading→trailing 100 × 40 rect under `.clipShape(RoundedRectangle(cornerRadius: 10))`
  reads white at its corner pixel (50.5, 80.5) and red inside.
- **`Deferred` and fades under a blur (major).** `aDeferredStopsAnEnclosingBlur`
  (3.35, the blur arm of `aDeferredStopsAnEnclosingShadow`: the presentation's
  50 × 30 is a rect, the bar the one blur image) and `aFadingTransitionScalesABlursAlpha`
  (3.36, both routes as in 3.31).
- **Last write wins (minor).** `legacyFillsAreLastWriteWinsBothWays` (3.34): a
  translucent colour after a gradient draws no gradient image; a gradient after
  it draws no colour rect.

Each mutation was applied to `2456d60` from a copy, native build, **full
unfiltered suite** (2857 tests), restored, `git status --short` empty after
each (`results.txt` in the session scratchpad's `lk3fix-c10/`). No hang. Each
reddened only the test named.

| id | mutation (spelling, file) | reddened |
|---|---|---|
| V9 | `Frame.drawGradient`: `opacity: 1` for `opacity: activeOpacity` (`GradientRaster.swift`) | `anOpacityScalesAGradient` |
| V6 | the `.gradient` arm of `RenderEffect.apply`'s flattening switch: `gradient.opacity *= alpha` deleted (`Transition.swift`) | `aFadingTransitionScalesAGradientsAlpha` |
| V5 | the `.gradient` arm of `CapturedPrimitive.multiplyAlpha`: the same line deleted | `aFadingTransitionScalesAGradientsAlpha` |
| V3 | `paintDecoration`: `let gradientEscapes = … && false` (`AnimatedColor.swift`) | `aGradientWrittenAfterOpacityEscapesIt` |
| V7 | `stripImage`: `let inset = 0 * Double(max(…))` (`GradientRaster.swift`) | `aRoundedClipCutsAStripCandidate` |
| V4 | `Frame.insertThroughScopes`: `, .blur where pastBarrier` removed (`Frame.swift`) | `aDeferredStopsAnEnclosingBlur` |
| V8 | the `.blur` arm of `multiplyAlpha`: `blur.alpha *= alpha` deleted | `aFadingTransitionScalesABlursAlpha` |
| V8f | the `.blur` arm of `RenderEffect.apply`'s flattening switch: the same line deleted | `aFadingTransitionScalesABlursAlpha` |
| V2 | `StyledElement.background(_ color:)`: `$0.backgroundGradient = nil` deleted (`Box.swift`) | `legacyFillsAreLastWriteWinsBothWays` |
