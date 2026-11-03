# Record 198: silent results (round 4 item R4-1 PR A)

Branch `feat/r4-1-silent-results`, from master `1d5d723f`. Decisions: `docs/superpowers/2026-11-03-silent-results-decisions.md` (`SR-A`..`SR-F`). Human checks: group SR. Divergences: **81 and 885 retired, 886 added, 154 narrowed, 295 and 208 reworded** (208 live to 207; next label 210).

## 1. What the probes showed (all macOS 27.2, 2026-11-03, headers hold the output)

| gate | result | consequence |
|---|---|---|
| `E2`-`E8` (`swiftui-surface-text.swift`) | **refuted the plan**: a laid-out `Text("")` is (0, 14), not 0 by 0; `E2` was an `ImageRenderer` artifact (a zero-width view renders no image). In a stack it takes its 14 and both gaps (`E3`, 54), padded 4 it is 8 by 22 (`E5`). Its height is a constant 14 at every font and size 9-40 pt (`E8`) | no `textViewMeasurement` seam; row 295 stays live, reworded (SwiftUI constant 14 against MetalUI's resolved-font line); coordinator ruling: a font-independent constant is not a rule MetalUI's font metrics express |
| `TB-A` (`swiftui-toolbar.swift`) | an automatic toolbar picker hosts the `.menu` view list, not the segmented control | as planned: no `Kind.automatic` |
| `AX1`-`AX8` (`swiftui-control-titles.swift`) | a literal publishes the markup-free `b`, a `String` variable `**b**`, for Button, Toggle, Stepper, Picker, ColorPicker, ProgressView; `Menu("**b**")` publishes `b`; a `TextField` publishes no placeholder; menu items inside a `Menu` not readable | as planned; the fix set is every one of those controls (the plan had said "only where a new arm says bold") |
| `K0`-`K6` (`swiftui-switch-knob.swift`) | the knob slides on a click, an un-animated write and `.linear(1)` alike, ~0.27-0.31 s, 3% overshoot; `withAnimation(nil)` slides; `disablesAnimations` snaps; checkbox snaps. Track 54 by 24, knob 32 by 20 | **refuted the plan's transaction-driven design**; a fixed spring, `disablesAnimations` honoured; 886 records the metrics |

## 2. Rows

- **81** retired (`SR-B`): `.automatic = .menu`; 2 demo sites and 17 test fixtures say `.segmented`; `ToolbarTests` "auto" is `.menu`; `docs/migration.md`. Pin `theAutomaticPickerStaysSegmented` became `theAutomaticPickerIsAPopUpMenu` (+ `anExplicitSegmentedPickerKeepsItsSegments`).
- **154** narrowed (`SR-C`): `LocalizedStringKey` + disfavoured `StringProtocol` initialisers on Button (4), Toggle, Menu, Stepper (6), Picker, ColorPicker, ProgressView (4); `Stepper`/`Picker` store a `Text`. Pin `aControlTitleIsVerbatim` became `aControlTitleLiteralIsParsedAndAStringVariableIsVerbatim`; guard `aControlTitleSpellingsCompile`. Left: `TextField` placeholders, alert titles, native menu-item titles (unmeasured).
- **885** retired, **886** added (`SR-D`): `paintKnob` animates its fraction through `animatedNumbers` on `Toggle.knobSpring` (`.spring(duration: 0.25, bounce: 0.25)`), the transaction not consulted except `disablesAnimations`. **The right-to-left bug was real**: the test was written first and was red (knob offsets [-37, -21] from the track against [18, 2]); `paintKnob` now reflects about the row's bounds like its track. Whether Reduce Motion changes SwiftUI's knob is unmeasured.
- **295** reworded (`SR-A`), **208** reworded (`SR-E`; comments in `PaddingSpellings.swift`, `Font.swift` `TextAlignment`, `LayoutTree.swift` `zeroSpacingEdges`). **Correction of earlier records:** record 99, the surface-text decisions (`GT-C`, `GT-I`; note added), the surface-text spec and `docs/record/14-frame-and-sizing.md` say a SwiftUI `Text("")` view is 0 by 0 (probe `E2`); that is refuted here and those files stay as history.
- **The flake** (`SR-F`): the cause is **unconfirmed** (the failing run's log was overwritten). Read from the code: on Linux the write's invalidation is a hop and `runUntilIdle()` treats a closed window as clean. `HarnessSettleTests` now waits for the hop with bounded `Task.yield()`s before the `needsRedraw` read, in the failing arm and its sibling. Limit: on Linux the documented mutation could pass on a run where the hop lands after `runUntilIdle()` returned.

## 3. Mutations (each applied to the declaration its test is named for, restored; `git status` clean after)

| mutation | reddened |
|---|---|
| `PickerStyle.automatic` restored to `kind: .segmented` | `theAutomaticPickerIsAPopUpMenu`, `theToolbarItemMappingRulesReachThePlatform` |
| `Button`'s `LocalizedStringKey` init draws its title verbatim | `aControlTitleLiteralIsParsedAndAStringVariableIsVerbatim` |
| `Button`'s `StringProtocol` init routed through a key (the variable parses) | `aControlTitleLiteralIsParsedAndAStringVariableIsVerbatim` |
| `Stepper`'s key init made `internal` | `aControlTitleSpellingsCompile` (positive arm fails: `requires that 'LocalizedStringKey' conform to 'StringProtocol'`) |
| knob `transaction: nil` | `aSwitchKnobSlidesOnAnUnanimatedWrite`, `aSwitchKnobSnapsUnderDisablesAnimationsAndSlidesUnderANilAnimation`, `aSwitchsFirstFrameSnapsAndASettledOneInterpolatesNothing` |
| the transaction drives the knob (`pass.transaction ?? pending`) | `aLinearOneSecondWriteHasAlreadyLandedByThreeHundredFiftyMilliseconds`, `aSwitchKnobSlidesOnAnUnanimatedWrite`, `aSwitchKnobSnapsUnderDisablesAnimationsAndSlidesUnderANilAnimation`, `aSwitchsFirstFrameSnapsAndASettledOneInterpolatesNothing` |
| `disablesAnimations` ignored | `aSwitchKnobSnapsUnderDisablesAnimationsAndSlidesUnderANilAnimation` |
| knob not reflected under right-to-left | `aSwitchKnobSitsOnItsTrackUnderRightToLeft` |
| track key rebuilt per frame | `aSwitchKnobSlidesOnAnUnanimatedWrite`, `aSwitchKnobSnapsUnderDisablesAnimationsAndSlidesUnderANilAnimation`, `aSwitchsFirstFrameSnapsAndASettledOneInterpolatesNothing` |
| baseline seeded 0 before the first frame | `aSwitchKnobSitsOnItsTrackUnderRightToLeft`, `aSwitchsFirstFrameSnapsAndASettledOneInterpolatesNothing`, `switchIsACapsuleTrackWithAKnobAtTheOnEnd` |
| range clamp `0...1` (no overshoot) | `aSwitchKnobSlidesOnAnUnanimatedWrite` (first run green: the overshoot was unpinned; the peak assertion was added, then this) |
| `isDirtyAndOpen` without `&& !platformWindow.isClosed` | `runUntilIdleReturnsWhenAnApprovedTerminationClosesTheWindowMidSettle`, `runUntilIdleTreatsAClosedDirtyWindowAsIdle` (with the new `yieldUntil`) |

**Retained subtree (added after review):** `aSwitchInARetainedSubtreeSlidesAfterReplays` asserts (`try #require`) 3 or more real replays of the settled switch, then that a change to `on` slides (mid-travel x) rather than snapping, that x moves between ticks in flight, that it lands at 18, and that the subtree replays again. Mutation: the `retainLog?.touches.append(.touch(id))` line in `AnimationStore.value(at:)` removed reddens it (x = [18, 18, 18, 18, 18, 18]: the track was swept and the change snapped). Removing the `.set` append in `set(_:at:)` reddens nothing (a replay needs only the touch). No bug found. **Not mutated:** the empty-`Text` wording (no behaviour moved; `anEmptyStringMeasuresAsItLaysOut` already pins 0 wide and one line tall).

## 4. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03: **`Test run with 4986 tests in 14 suites passed after 347.739 seconds (second unfiltered run, no clean, after the retained test; the first, after a clean, read 4985 in 283.150 seconds)`**, 0 failures; `FR-J no-argument frame: succeeded=true` (guards ran). The counts line of `CLAUDE.md` is not replaced (the batch's three PRs re-take it once). New tests: 5 in `ToggleStyleTests` (knob), `theAutomaticPickerIsAPopUpMenu` replacing `theAutomaticPickerStaysSegmented` plus `anExplicitSegmentedPickerKeepsItsSegments`, `aControlTitleLiteralIsParsedAndAStringVariableIsVerbatim` replacing `aControlTitleIsVerbatim`, the guard `aControlTitleSpellingsCompile`.
`zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1` each over `ToggleStyleTests`, `RetainedSubtreeInternalTests`, `RetainedPrepaintInternalTests`, `RetainedGraftInternalTests` and `RetainedLifecycleTests`: 37 tests passed under each. Not run: `Backends/SDL` tests (no source there changed), the Windows/Linux CI jobs; human group SR.
