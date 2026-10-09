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

