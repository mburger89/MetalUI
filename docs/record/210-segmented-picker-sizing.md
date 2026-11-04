# Record 210: a segmented `Picker` no longer starves its title (round 4 item R4-3a)

Branch `feat/r4-3a-followups` on master 04c37c05. Decisions: `SR-G` in `docs/superpowers/2026-11-03-silent-results-decisions.md`. Human checks: `SR1` Finding A answered, `SR5` new. Divergences: **none added, retired or narrowed** (209 live, next label 217; row 131's text gained the pop-up numbers). Probe: `docs/probes/swiftui-segmented-sizing.swift`, recorded in `swiftui-segmented-sizing-run.txt`.

## 1. What changed

- `Sources/MetalUI/Picker.swift`: `EqualWidthRow.widths(natural:available:)` (pure; nil, infinite or at least `n x widest` is all the widest, else repeatedly fix every segment whose natural width exceeds the current share and share the rest), used by `EqualWidthRow.sizeThatFits` (the sum) and `placeSubviews` (accumulating x); `PickerTitleRow<Content: ElementGroup>` (consumes and plans the title and options records as `OptionRow` does and registers `PickerTitleLayout`; a radio group, menu or `labelsHidden()` picker passes its nodes through unchanged, identity numbering unchanged); `PickerTitleLayout: ProposalLayout` (gap 8, centred vertically, the title offered the proposal's height). All internal, so no inventory row; doc comments updated, the stale "`n·w` where SwiftUI's is `n·w + 1` (divergence 81)" dropped from `Picker`'s.
- Tests: `SegmentedPickerSizingTests.swift` (11 new). Existing tests that changed: section 3.
- Docs: probe and its recording, `SR-G`, `decision-prefixes.md` (next `SR-H`), `layout.md` sentence, row 131, `api-overview.md` (the stale "`.automatic` stays segmented (81)"), human checks `SR1` and `SR5`, `Tasks.md` R4-3a ticked with `(PR #TBD)`, README row.

## 2. Plan items done differently

- **The probe copy gained one arm**: SG3e at 280. The plan quoted "W 280: title 1x96, control 271" but `sg.swift` had no such arm (SG1a's `w280 280x96` plus a subtraction was the source). Read now: label 1x96, control 271. Every other reading in the plan's tables was read again and matched; two runs byte-identical (188 lines). **The layout readings work in `NSHostingView` while locked** (`CGSSessionScreenIsLocked = 1` read before and after).
- **No test literal differed from the prototype's.** All 11 new tests passed first time against the cleaned-up code. Two literals are MetalUI's own and differ from SwiftUI's by the documented rounding: title 19 (SwiftUI 20) at 300, long title 82 (83); both commented in the tests.
- `isSegmented` is set in `requestLayout` from the style, as the prototype did, and initialised `false` (the prototype initialised `true`; the init is not observable).
- Added beyond the plan's table: the pure `widths` test also covers 363 (exactly `n x widest`), an empty row and a single segment below its width.

## 3. Existing tests that changed (before -> after)

`ProposalControlsTests.everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, the `Picker.segmented` row (FL10): zero `(124.85, 24)` -> `(117.98, 24)` and w50 `(124.85, 64)` -> `(117.98, 64)`; the 159.00 columns unchanged. The floor 109.98 plus the gap 8 replaces the rigid 124.85.

Bracket window (retention off first, `theBracketNodeDragRebuildsTheWholeWindow`, frame 10 of 21): `layoutMeasureCalls` 52 -> 57, `layoutCacheHits` 366 -> 365, `layoutCacheMisses` 217 -> 223, `layoutMemoHits` 1258 -> 1259, `layoutSignatureNodes` 844 -> 845. **Unmoved: `builds` 1, `rects` 182, `glyphs` 550, `images` 6, `layoutMemoMisses` 55, `layoutMemoRootHits` 0, every element and content counter, `rasterizedPixels` 78312.** The delta is the top bar's one segmented `Picker` (`BracketFixture.swift`, "Mode") becoming one native node (`PickerTitleLayout`): one more signature node and one more memo hit; the five extra measures and six cache misses are its title and control being asked more than once (the control at the title's ideal, the title at the remainder, the control again) in both `sizeThatFits` and `placeSubviews`. That attribution is by the counts' shape (+1 node, +1 hit), not by tracing the six misses to calls.

Retention on, the same deltas (+5 measures, -1 cache hit, +6 cache misses, +1 memo hit):
- `theBracketNodeDragIsCountedAtFb9a7e42` (and `...AfterPrepaintReplay`, which compares against its table), all three arms: measures 52 -> 57, cacheHits 331 -> 330, cacheMisses 217 -> 223, memoHits 362 -> 363.
- `aDragFrameRestoresTheUnmovedOccurrencesPlacement` (`.value`, `.panels`): memo hits 362 / 1258 -> 363 / 1259, cache hits 331 / 366 -> 330 / 365, measures 52 -> 57, cache misses 217 -> 223.
- `theBracketNodeDragReplaysEveryUnchangedSubtree`, press frame: 52 -> 57 in both counts (the comment's "52 in every arm" updated).
- `theBracketNodeDragIsCountedAfterTheGraft`, `.panels` only: `retainedGraftedNodes` 677 -> 678 (`.value` and `.environment` unchanged).

Unchanged and green: the radio and menu picker pins, `ListSelectionTests`, `AccessibilityAuditTests`, `aSteadyFrameCapturesAndOpensNothing`, `anEquatableOccurrenceWithAnIfStillGrafts`.

## 4. Mutations

Each applied to the committed tree (`Picker.swift` only, restored with `git checkout Sources`, `git status` read clean of `Sources` and `Tests` after each), whole default suite run (`swift test --no-parallel`, head `4469a1c0` code). Spelling in brackets. **Every mutant reddened something; none is green.**

| mutation | reddened |
|---|---|
| MA1 `available` ignored (`widths`' guard gains `natural.count < 0`) | `theSegmentWidthsAreAnEqualShareNeverUnderTheNaturalWidth`, `aSegmentedPickerKeepsItsTitleOnOneLine`, `aStackBesideASegmentedPickerSharesWhatTheTextLeaves`, `aLabelledPickerSqueezesTheTitleBeforeTheSegmentsReachTheirFloor`, `aNarrowerLabelledPickerLeavesTheTitleOneLetterWideAtTheFloor`, `aLabelledPickerBelowItsFloorAnswersTheFloorAndOverflows`, `aLongTitleWrapsAndTheControlKeepsWhatItsIdealLeaves`, `aHiddenTitlePickerTakesTheProposalDownToItsFloor`, `aStackPutsAHiddenSegmentedPickerOnItsFloor`, `pressingTheThirdSegmentOfASqueezedPickerWritesItsTag`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `aDragFrameRestoresTheUnmovedOccurrencesPlacement`, `theBracketNodeDragRebuildsTheWholeWindow`, `...IsCountedAtFb9a7e42`, `...AfterPrepaintReplay` |
| MA2 equal share, no natural floor (`while changed, open > natural.count`) | the same 15 as MA1 |
| MA3 placement at natural widths (`placeSubviews` uses `naturals(subviews)`) | `aSegmentedPickerMakesEverySegmentAsWideAsTheWidest`, `aSegmentedPickerKeepsItsTitleOnOneLine`, `aStackBesideASegmentedPickerSharesWhatTheTextLeaves`, `aLabelledPickerSqueezesTheTitleBeforeTheSegmentsReachTheirFloor`, `aLongTitleWrapsAndTheControlKeepsWhatItsIdealLeaves`, `aShortLabelledPickerKeepsItsIdealInAWiderFrame`, `aHiddenTitlePickerTakesTheProposalDownToItsFloor`, `pressingTheThirdSegmentOfASqueezedPickerWritesItsTag` |
| MA4 `isSegmented` always false (`box.content.isSegmented = false`) | `aLabelledPickerSqueezesTheTitleBeforeTheSegmentsReachTheirFloor`, `aNarrowerLabelledPickerLeavesTheTitleOneLetterWideAtTheFloor`, `aLabelledPickerBelowItsFloorAnswersTheFloorAndOverflows`, `aLongTitleWrapsAndTheControlKeepsWhatItsIdealLeaves`, `aShortLabelledPickerKeepsItsIdealInAWiderFrame`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `aDragFrameRestoresTheUnmovedOccurrencesPlacement` and the five bracket pins incl. `...AfterTheGraft` and `...ReplaysEveryUnchangedSubtree`. **Not** `aSegmentedPickerKeepsItsTitleOnOneLine` (a legacy row also lands 335 at 380) nor the hidden-title tests |
| MA5 no control re-proposal (`let c = first`) | `aLabelledPickerSqueezesTheTitleBeforeTheSegmentsReachTheirFloor`, `aLongTitleWrapsAndTheControlKeepsWhatItsIdealLeaves`, `aDragFrameRestoresTheUnmovedOccurrencesPlacement`, the three bracket pins |
| MA6 gap 0 (`gap = 0.0`) | the labelled tests (not the hidden-title ones), `aSegmentedPickerMakesEverySegmentAsWideAsTheWidest`, `anEmptyTitleStillTakesTheGap`, `aHiddenLabelTakesNoSpace`, `everyControlAnswersInSwiftUIsClassInsideAProposalContainer`, `pressingTheThirdSegmentOfASqueezedPickerWritesItsTag` |
| MA7 title height proposal dropped (both `title(...)` calls pass `height: nil`) | `everyControlAnswersInSwiftUIsClassInsideAProposalContainer` (the w50 row's 64), `aDragFrameRestoresTheUnmovedOccurrencesPlacement`, the three bracket pins. **No new test sees it**; the existing row and the bracket window do |

The comments in `SegmentedPickerSizingTests.swift` name the mutants as measured here (an earlier draft claimed MA4 reddens `aSegmentedPickerKeepsItsTitleOnOneLine`; it does not, and was corrected).

## 5. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests` exit 0, `swift test --build-system native --no-parallel` unfiltered, 2026-11-04: **`Test run with 5146 tests in 14 suites passed after 292.050 seconds`** (5135 + 11); `FR-J no-argument frame: succeeded=true deprecations=2`. `anUnannotatedInsertionAndRemovalFadeByDefault` and `aRedoWithATimelineInTheTreeEqualsAFreshFrame` passed on this fresh build (R4-3d, R4-3e: no failure). `METALUI_VERIFY_RETAINED=1`: **`Test run with 5146 tests in 14 suites passed after 273.825 seconds`**; `METALUI_VERIFY_LAYOUT_MEMO=1`: **`5146 tests in 14 suites passed after 323.034 seconds`** (both native, unfiltered, `--no-parallel`, on the same build). `record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. CLAUDE.md is unchanged, so no `AGENTS.md` copy.

## 6. Not verified

How the picker looks (no capture: the screen was locked; human checks `SR1`, `SR5`); segment edges in pixels (the AX frames are 1 to 2 over the layout figure); how the overflow at the floor reads; Linux, Windows and the asserts compiler (no loop or closure was added to generic content, but `PickerTitleRow` is a new generic `ElementGroup`, no CI ran); `Backends/SDL`; MetalCreator and MetalFlow builds; SwiftUI behaviour with `controlSize(.small)`, a disabled picker or five segments beyond the probe's SG4d, SG4e, SG4f, SG4g readings (not pinned here).
