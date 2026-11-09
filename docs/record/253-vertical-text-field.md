# 253. The vertical `TextField` (Alloy gap G18, `VT-A`..`VT-H`)

Branch `feat/vertical-text-field` (master `12ca12d4`), two commits: layout, paint, scroll and the wheel; then the keys and the docs. Decisions `docs/superpowers/2026-11-09-vertical-text-field-decisions.md`; probe `docs/probes/swiftui-vertical-text-field.swift` (arms S E F R W K P, recorded 2026-11-09 on macOS 27.2 / Swift 6.4.2, compiled, run twice byte-identical, md5 `b3e9f1c21b1f74447fa7b7940d00575e`). Class `A`; divergences 232-234 and 237-240 (213 live becomes 220, next label 241; 235 and 236 are older rows).

- **Probe versus plan.** Every number of the plan reproduced (heights 24/24/56/136/136 and 328, plain 16/48/128, exact 100/80/70, floors 24/40/56/10/0, reservesSpace 56/56/136, `lineLimit(0)` 24, `"a\n"` 40, two-line placeholder 40, font 20 -> 80, small -> 50, nil ideals 43 and 67, horizontal 24; E: `TextEditor` ignores `lineLimit` (120 both); R: the clip is a `_NSKeyboardFocusClipView` 128 tall holding a 320-tall field editor, bounds.y 4 -> 196 -> 4, no scroller, 132 tall at y 2 when focused and overflowing; W: a wheel step moves a focused field; K: the key table; P: the placeholder is `secondaryLabelColor` and only a `prompt:` colour reaches it). Differences are in the probe's instruments only: a 24-line paragraph is 120 words at width 200 (60 words wrap to 12); the recipe in F is read at 1/8/20 lines (16/96/128; 6 lines is 72), the `TextEditor` having 12-point lines.
- **Built** as `VT-A`..`VT-H` say. `MultilineText` is `TextEditor`'s geometry and line loop moved unchanged: its scene was dumped for three texts in eleven states before and after and is byte-identical (md5 `a18b8c05e0402643028881fa3d4db995`); the throwaway test is not kept, `aTextEditorDrawsItsLinesAndCaretWhereItAlwaysDid` pins the geometry. The `Handlers` pin (480) moved when the vertical marker was a `Bool` on `TextLineModel`, so it lives in `TextTargetHooks`.
- **Deviations from the plan.** The marker is in `TextTargetHooks`, not `TextLineModel` (the plan's own fallback). The scroll write-back is gated on focus (an unfocused field writes nothing). `.controlSize(.small)` differs (46 against 50) and is divergence 239, finding K got 240 and the unmeasured behaviours 238; the plan's eight items became seven rows (Alt+Enter is class M, not a divergence). The probe source did not exist next to the plan and was written here.
- **Found, not fixed.** The one-line `TextField` submits on Option-Return and Command-Return (234). Finding K (240, `SA-N` item 10): `TextEditor.frame(minHeight: 16, maxHeight: 128).fixedSize(vertical:)` is 320 at 20 lines here, 128 in SwiftUI.
- **Tests** (`VerticalTextFieldTests`, `VerticalTextFieldKeyTests`, `VerticalTextFieldCompileGuards`, `VerticalFieldRetainedTests`; `everyStateWriteSiteIsClassified` rows `TextField.swift` (1, 2, 3, 0) and `Window.swift` 6).
- **Mutations** (each applied alone and restored; filter `VerticalTextField|VerticalFieldRetained|TextEditorTests|TextFieldTests|TextEditingTests|handlersGainsOneReferenceMember`; reddened tests named):

| mutation | reddened |
|---|---|
| M1 upper bound not applied | `aVerticalFieldIsAsTallAsItsLinesBetweenTheBoundsOfLineLimit`, `withoutALimitAVerticalFieldGrowsWithItsText`, `aWrappedParagraphIsCappedLikeHardLines`, `aPlainVerticalFieldHasNoChromeInsets`, `aLineLimitOfZeroActsAsOne`, `reservingSpaceMakesTheFieldAlwaysThatTall`, `theFloorIsTheLowerBoundsHeightAndNothingWithoutOne`, `aContainersLineLimitReachesTheFieldAndTheFieldsOwnWins` and the scroll tests |
| M2 missing upper bound defaults to 8 | `withoutALimitAVerticalFieldGrowsWithItsText`, `aWrappedParagraphIsCappedLikeHardLines` |
| M3 floor reads `?? 1` | `theFloorIsTheLowerBoundsHeightAndNothingWithoutOne` |
| M4 proposal snapped to whole lines | `aProposalBetweenTheFloorAndTheContentIsAnsweredExactly`, `theFloorIsTheLowerBoundsHeightAndNothingWithoutOne` |
| M5 lower bound ignored in the content | `reservingSpaceMakesTheFieldAlwaysThatTall` (only at a nil height proposal: a finite one is rescued by the floor, so the height helper uses `fixedSize`) |
| M6 bound clamp to 1 removed | `aLineLimitOfZeroActsAsOne` |
| M7a trailing-newline `+1` dropped / M7b placeholder branch dropped | `aTrailingNewlineAndAPlaceholderCountAsLines` (both) |
| M8 hard lines only | `aWrappedParagraphIsCappedLikeHardLines`, `aTrailingNewlineAndAPlaceholderCountAsLines` |
| M9 bordered inset always added | `aPlainVerticalFieldHasNoChromeInsets` |
| M10 limit read on the horizontal axis too (`guard vertical` always passes) | `aHorizontalFieldIgnoresLineLimit` (the first sweep wrote `guard false`, which sends every field the horizontal way; rerun with `guard true`) |
| M11a only the field's own limit / M11b only the environment's | `aContainersLineLimitReachesTheFieldAndTheFieldsOwnWins` (a); (b) the same plus ten tests that use the field's own limit |
| M12 reveal write-back skipped | `typingPastTheCapRevealsTheCaretAndStoresTheScroll`, `anUnfocusedFieldDrawsFromTheTopAndKeepsItsScroll`, `aFocusedWheelWithRoomScrollsTheFieldAndOtherwiseTheOuterScrollView` |
| M13 geometry in the bounds, not the content rect | `commandDownGoesToTheEndAndCommandUpBackToTheTop`, `typingPastTheCapRevealsTheCaretAndStoresTheScroll`, `anUnfocusedFieldDrawsFromTheTopAndKeepsItsScroll`, `aFocusedWheelWithRoomScrollsTheFieldAndOtherwiseTheOuterScrollView` |
| M14a room test dropped / M14b focus test dropped | `aFocusedWheelWithRoomScrollsTheFieldAndOtherwiseTheOuterScrollView` (both) |
| M15 field rule on `TextEditor` | `aTextEditorStillSwallowsTheWheel`, `returnStartsANewLineAndTheCaretMovesDownALine` |
| M16a unfocused paints with the stored scroll / M16b write-back not focus-gated | `anUnfocusedFieldDrawsFromTheTopAndKeepsItsScroll` (both) |
| M17a Return inserts | `returnSubmitsAndTheNewlineModifiersInsertInAVerticalField`, `returnInAWindowSubmitsOnceAndInsertsNothing` |
| M17b shift is a newline modifier | the same two |
| M17c option not a newline modifier | the same two and `typingPastTheCapRevealsTheCaretAndStoresTheScroll` |
| M17d control not a newline modifier (Mac) | `returnSubmitsAndTheNewlineModifiersInsertInAVerticalField` |
| M17e shortcut-modifier Return case disabled | the same two, and (separate run) `aDeclinedCommandReturnInATextEditorReachesTheWindowsOnInput` |
| M17f Alt not the newline modifier elsewhere | `returnSubmitsAndTheNewlineModifiersInsertInAVerticalField` |
| M17g `Window` passes `.editor` | `returnInAWindowSubmitsOnceAndInsertsNothing` |
| M18 `Window` passes `.singleLine` | `aPasteKeepsItsNewlinesInAVerticalField`, `returnInAWindowSubmitsOnceAndInsertsNothing` |
| M19 every line's y shifted by 1 | `aTextEditorDrawsItsLinesAndCaretWhereItAlwaysDid` |
| M20 paint reads the state with a plain `withState` (a write) | `anUnfocusedVerticalFieldReplaysAndAFocusedOneEqualsARetentionOffWindow` |
| M21 the five `lineLimit` overloads on the field disabled | the test target does not build (`EnvironmentScope<TextField>` has no `onSubmit`); the typecheck guard reads the same |
| M22 the marker as a `Bool` on `TextLineModel` (the first design) | `handlersGainsOneReferenceMember` (Handlers 480 moved) |

- **Counts** (2026-11-09, after the last code change, `swift test --no-parallel`, default build system; groups summed): 5195 tests passed, 0 failures. Under `METALUI_VERIFY_RETAINED=1` the same run crashes in `indicesAreStableWhileTheDocumentGrows` (`Fatal error ... replay differs from a fresh run ... scene.count 6 vs 16`, Markdown copy button, **also on master 12ca12d4**); skipping `MarkdownCopyButtonTests`' functions (6 tests, and by regex anything containing `look` or `buttons`) all 5189 pass. Under `METALUI_VERIFY_LAYOUT_MEMO=1` (the variable exists, `AnimationStore.swift`) three Markdown tests fail with 6 issues (`theCopyButtonIsAnOverlayAndPressingItDoesNotReshapeTheFence`, `aTokenCostsTheLastBlockWhateverTheTranscriptHolds`, `appendingToAnOpenFenceShapesOneChunk`), **identical on master 12ca12d4**; everything else passes. `swift build --build-system native --build-tests` then `swift test --build-system native --no-parallel`: `Test run with 5779 tests in 26 suites passed after 350.674 seconds`, `FR-J no-argument frame: succeeded=true deprecations=2`, `VERTICAL FIELD GUARD 21 positive: succeeded=true`, `control: succeeded=false`. The closeout probes print nothing. Portable image not run.
