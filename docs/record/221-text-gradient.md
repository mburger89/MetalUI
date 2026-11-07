# Record 221: a gradient `foregroundStyle` on text (R4-5 PR D)

Branch `feat/text-gradient` (master `d0cceec6`). Rulings `TG-A`..`TG-G` in `docs/superpowers/2026-11-07-text-gradient-decisions.md` (new prefix; `TG-F` is the SDL half, `TG-G` the carried items; next `TG-H`). Divergence **975 narrowed, not retired** (209 live and next label 226, unchanged: no row was added, section 8). Probe `docs/probes/swiftui-text-gradient.swift` (commit `65537362`). Plan: the reviewed R4-5 PR D plan; the deviations are in section 4.

Two runs: run 1 built the engine and tests 1-21 (sections 1-5); run 2 the SDL half, parity frame 19, the demo strip, the ledger and the shards (sections 6-8).

## 1. What was measured (probe, compiled `ImageRenderer`, six byte-identical runs, 71 lines)

- `TG0` separates (left B .09, right B .99; control `Color.red` B 0 twice).
- **The span is the ink, not the layout box** (plan expected the layout box): `TG3d` ink .08 vs box .40; `TG2d` vertical ink rows .04-.09 vs line box .31; `TG8x` radial ink .03 vs box .11. A frame (300) and padding are not the span; a container spans each `Text` (`TG4x`).
- **One span per text, not per glyph or line** (`TG1`, `TG2`): wrapped lines share it.
- **Runs (`TG5`)**: the span is the union of the ink of every run carrying the same gradient (`g` beside a red run: its own box; `g,g`: both; `g,green,g`: first and third share one span over all three).
- Decorations follow the gradient and **extend the span** (`TG10`, `TG10v`); an own colour stays. Shadow is the shadow colour (`TG6`); opacity fades once (`TG7`); a level over a gradient parent keeps the gradient at .502 (`TG9`); a bare `Rectangle` takes the gradient (`TG14`). `TG12`, `TG13` not measurable.
- Stop condition P: did **not** fire for per line / per glyph; the rect source *did* change (ink union per equal gradient, not the layout box) as the plan allowed.

## 2. Mutations (a scratch `git worktree` of `94a2ded5`, restored and removed; branch and spelling in the table)

Filter for every row: `TextGradient|RetainedTextGradient|aGradientForegroundStyleOnText|HierarchicalStylePaint|textForegroundColor|ClipMaskTests|GroupMaskTests`, then `swift build --build-tests`; "reddened" lists the tests that failed. **The first pass of this table was invalid and was re-run in full:** the baseline filter run itself crashed (`aShadowOfGradientTextIsTheShadowColour` read a pixel at a negative row, a trap that kills the runner and so hid every test after it), which made six rows read "none" for the wrong reason; the baseline was repaired (59 tests passed) and all rows below are the second pass.

| id | mutation (file, spelling) | reddened |
|---|---|---|
| M1 | `ShapeStyle.swift`, the `Text.foregroundStyle<S>` arm: `.color(style.builderStorage().representativeColor)` | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aDragPreviewOfGradientTextKeepsEveryGlyphMask`, `aFadedGradientTextFadesOnce`, `aGradientTextIsOneMaskedGroupAndAColourTextIsNone`, `aGradientTextPaintsTheGradientAcrossItsInk`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aGradientUnderlineIsPartOfTheInk`, `aRadialGradientTextCentresOnItsInk`, `aRemovedGradientTextFadesItsGhostMasked`, `aShadowOfGradientTextIsTheShadowColour`, `aSteadyGradientTextFrameMakesNoTextureAndRastersNothing`, `aWrappedGradientTextSpansBothLines`, `anOversizeGradientTextDrawsItsInkByName` |
| M1b | `ShapeStyle.swift`, `ElementGroup.foregroundStyle<S>`: `.color(shapeStyleStorage(style, in: $0).representativeColor)` | `aGradientChangeAboveAnEquatableSubtreeMisses`, `aGradientForegroundStyleOnTextIsAMaskedGroupAndItsRepresentativeColourIsTheFirstStop`, `aGradientSpansEachTextNotTheContainer`, `aLevelOverAGradientParentKeepsTheGradient`, `aMovedOccurrenceHoldingGradientTextIsRefusedByNameAndEqualsAFreshFrame`, `aRetainedReplayOfGradientTextEqualsAFreshFrame`, `aShapesDefaultFillTakesAGradientForegroundStyle` |
| M2 | `TextGradient.swift` `drawGradientInk`: `box` grown by 12 x 6 px each side (a layout-box stand-in; the ink box itself is never exactly the layout box, so a real swap is not a mutation of one spelling) | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aGradientTextPaintsTheGradientAcrossItsInk`, `aWrappedGradientTextSpansBothLines` |
| M3 | `BackdropBlurPipeline.swift`, the `destinationIn` arm: destination factors `.one` (CM M24) | `aCrossingPairInsideAnOffsetMovesWithIt`, `aGradientTextCrossingAFlatteningEntryClipIsCutByBothClips`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aGradientTextsCoverageIsTheSolidTexts`, `aLoneFillClippedToAnEllipseIsAnEllipseRect`, `aMaskScalesAllFourChannelsByItsAlpha`, `aMaskedGroupMultipliesItsTargetByTheMasksAlpha`, `aNonAntialiasedClipHasHardEdges`, `aPathClipMasksToItsWinding`, `aShadowOfAnEllipseClipIsElliptical`, `aShadowOfGradientTextIsTheShadowColour`, `anEllipseClipInsideAnOffsetMovesItsMask`, `anEllipseClipMasksItsCorners`, `anEvenOddPathClipLeavesTheHoleClear`, `crossingClipsAcrossAnOffsetIntersectExactly`, `twoCrossingRoundedClipsIntersectExactly` |
| M4 | `Frame.inkGlyph`: the ink colour at alpha .5 | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aFadedGradientTextFadesOnce`, `aGradientSpansEachTextNotTheContainer`, `aGradientTextCrossingAFlatteningEntryClipIsCutByBothClips`, `aGradientTextPaintsTheGradientAcrossItsInk`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aGradientTextsCoverageIsTheSolidTexts`, `aLevelOverAGradientParentKeepsTheGradient`, `aRadialGradientTextCentresOnItsInk`, `aShadowOfGradientTextIsTheShadowColour`, `aWrappedGradientTextSpansBothLines` |
| M5 | `Frame.spriteGlyph` ink branch: `a: color.a * activeOpacity` | `aFadedGradientTextFadesOnce` |
| M6 | `Frame.inkBounds`: `ink.prefix(1)` (first element only) | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aFadedGradientTextFadesOnce`, `aGradientSpansEachTextNotTheContainer`, `aGradientTextPaintsTheGradientAcrossItsInk`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aGradientTextsCoverageIsTheSolidTexts`, `aGradientUnderlineIsPartOfTheInk`, `aLevelOverAGradientParentKeepsTheGradient`, `aRadialGradientTextCentresOnItsInk`, `aShadowOfGradientTextIsTheShadowColour`, `aWrappedGradientTextSpansBothLines`, `anOversizeGradientTextDrawsItsInkByName` |
| M7 | `drawStyledText.addInk`: `firstIndex(where: { $0.fill == fill && $0.ink.count < 2 })` (a group per two-glyph run) | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aGradientUnderlineIsPartOfTheInk` |
| M8a | `resolveForeground`: `switch environment.foregroundStorage ?? own` | `aColorSecondaryStaysGreyUnderAParent`, `aColourBelowAGradientClearsIt`, `aLeadingDotPrimaryAndSecondaryBindTheLevelNotTheColour`, `aLevelIsAFactorOfTheParentAtEverySink`, `aLevelOverAGradientParentKeepsTheGradient` |
| M8b | `Text.foregroundColor` setter: a colour does not replace a gradient | `aColourBelowAGradientClearsIt` |
| M9 | `Frame.needsGPU`: the `!q.groups.isEmpty` line removed | `aShadowOfAnEllipseClipIsElliptical`, `aShadowOfGradientTextIsTheShadowColour` |
| M10 | `drawGradientInk`: `fill.axis(in:)` over a 1.5x rect | `aConcatenatedGradientRunSpansTheRunsThatCarryIt`, `aGradientSpansEachTextNotTheContainer`, `aGradientTextPaintsTheGradientAcrossItsInk`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aRadialGradientTextCentresOnItsInk`, `aWrappedGradientTextSpansBothLines` |
| M11 | `HierarchicalShapeStyle.resolve`: `if false, case let .gradient` | `aLevelOverAGradientParentKeepsTheGradient` |
| M11b | `resolveForeground`: `if false, own != nil, color.readsInheritedStyle, …` | `aLevelOverAGradientParentKeepsTheGradient` |
| M12 | `paintShapeFill`: `if false, declared == nil, …` | `aLevelOverAGradientParentKeepsTheGradient`, `aShapesDefaultFillTakesAGradientForegroundStyle` |
| M13 | `drawGradientGlyphs`: also `frame.draw(glyph, color:)` per glyph | `aFadedGradientTextFadesOnce`, `aGradientForegroundStyleOnTextIsAMaskedGroupAndItsRepresentativeColourIsTheFirstStop`, `aGradientTextIsOneMaskedGroupAndAColourTextIsNone`, `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aGradientTextsCoverageIsTheSolidTexts`, `aLevelOverAGradientParentKeepsTheGradient`, `aRetainedReplayOfGradientTextEqualsAFreshFrame`, `aShadowOfGradientTextIsTheShadowColour`, `anOversizeGradientTextDrawsItsInkByName` |
| M14 | `Renderer.applyMask`: `state.release(scratch)` removed (CM M15) | `aSteadyGradientTextFrameMakesNoTextureAndRastersNothing`, `aSteadyMaskedFrameMakesNoTexture` |
| M15 | `insertMaskedGroup`: `if false, inkMask, children.count == 1, …` | `anOversizeGradientTextDrawsItsInkByName` |
| M16 | `drawGradientInk`: the `retainLog?.noteDirect` line removed | `aGradientChangeAboveAnEquatableSubtreeMisses`, `aMovedOccurrenceHoldingGradientTextIsRefusedByNameAndEqualsAFreshFrame`, `aRetainedReplayOfGradientTextEqualsAFreshFrame` |
| M16b | `RetainedSubtree.replayPaint`: `insertIntoScene` per leaf for `insertLeaves` (CM M20) | `aGradientChangeAboveAnEquatableSubtreeMisses`, `aMaskedClipInsideAnOccurrenceMissesWhenItMovesAndEqualsAFreshFrame`, `aMovedOccurrenceHoldingGradientTextIsRefusedByNameAndEqualsAFreshFrame`, `aRetainedReplayOfAMaskedClipEqualsAFreshFrame`, `aRetainedReplayOfGradientTextEqualsAFreshFrame` |
| M17 | `retainedFingerprint`: `foregroundStorage.map { .color($0.representativeColor) }` | `aGradientChangeAboveAnEquatableSubtreeMisses` |
| M18 | `RenderEffect.apply`: `mask.indices.prefix(1)` | `aGradientTextUnderARotationTurnsEveryGlyphMask`, `aShadowOfGradientTextIsTheShadowColour` |
| M19 | `Frame.cutToEntryClip`: `mask.indices.prefix(1)` |  **none: green, and by construction.** A gradient text's ink elements carry an unbounded content mask, so `cutContentToEntryClip` is a no-op on them; the content gradient is cut by its own clip and the product is the same. Kept as a loop for the day an ink element carries a clip |
| M20 | `DefaultTransition` ghost reader: `drawList.prefix(1)` and `run.start..<run.start + 1` (the old single-primitive read) | `aRemovedGradientTextFadesItsGhostMasked` |
| M21 | `CapturedPrimitive.replayed`: `mask.indices.prefix(1)` | `aDragPreviewOfGradientTextKeepsEveryGlyphMask` |
| M22 | `drawStyledText`: the underline `ink` always `nil` | `aGradientUnderlineIsPartOfTheInk` |
| M23 | `Text.foregroundColor`: `public internal(set)` | `textForegroundColorStaysPubliclyReadableAndWritable` |
| M24 | `RetainedTranslation.movedLeaf`: `mask.indices.prefix(1)` |  **none: unreachable.** A moved occurrence holding a gradient is refused first (`unlistedKind:gradient`, section 4 item 5), so `movedLeaf`'s mark loop never runs; as `CM` M27 |

Read with the plan's test numbers: M1/M1b tests 1, 4, 9, 10, 11; M2/M6/M10 tests 1, 4, 8 (M2 and M10 are layout-box stand-ins: a grown rect and a grown axis, since no one spelling swaps the source); M3, M4, M5 tests 2, 3; M7 test 5; M8a/M8b test 6; M9 test 7; M11/M11b/M12 tests 9, 10; M13 test 11; M14 test 12 (CM M15's spelling); M15 test 13; M16/M16b test 14; M17 test 15; M18 test 16; M20 test 17; M21 test 18; M22 test 19; M23 test 21. Test 12's other mutation (a per-frame value in the gradient raster key) was not applied. Test 16b (a crossing at a flattening entry) is M19's green: pinned for behaviour, not for the loop.

## 3. The mapping audit (plan §7 item 4 did not fire)

`grep` for every reader of `GroupMark.mask`, `isMasked` and `maskDepth` under `Sources/MetalUI` found no site the plan did not list.

| site | handling of a mark's N-element mask |
|---|---|
| `Frame.insertLeaves` | passes `mark.mask` and `mark.inkMask` to `insertMaskedGroup` |
| `Frame.insertMaskedGroup` | `bakingToEllipse` only for a one-element mask; the mask scene is every element; the oversize branch with `inkMask` draws the ink in the first stop (M15) |
| `ClipMask.flagMarkMasks` | each element flagged |
| `RenderEffect.apply` | each element mapped, any unmappable one drops the content (M18) |
| `Frame.cutToEntryClip` | each element cut; green by construction (M19) |
| `CapturedPrimitive.replayed(mask:layer:)` (drag preview) | each element (M21) |
| `Scene.capturedGroup` ghost (`DefaultTransition`) | every primitive of the mask scene read back (M20) |
| `RetainedTranslation.movedLeaf` | each element moved; unreachable (M24, section 4 item 5) |
| `liftSharedMarks`, `needsGPU` | a masked mark stays, so the leaf takes the filtered group (M9) |

## 4. What the code forced (deviations from the plan)

1. **The gradient spans the ink, not the layout box** (probe `TG3`, `TG2d`, `TG8`): `Frame.inkBounds`, the union of the device bounds of the glyph quads and decoration rects of one gradient's ink, mapped back to points. The plan's `Text.glyphBox` rect was refuted. Cost: the raster key holds the ink rect, so a counter that changes digits can re-raster the strip when the ink width changes (a counter of fixed-width digits does not; a steady frame rasters nothing, test 12).
2. **The span is per gradient, not per Text or per run** (probe `TG5`): the rich path groups ink by gradient equality (`drawStyledText.inkGroups`), and a line that names no colour of its own follows the run's gradient (`TextRunPaint.underlineFollowsInk`, `strikethroughFollowsInk`) and **extends the span** (`TG10v`).
3. **The ink carries the representative colour at alpha 1** (`inkGlyph(_:color:)`, `inkRect(_:color:)`), as the plan said, so the oversize fallback can draw it: `GroupMark.inkMask` (new) selects that branch.
4. **A `Color?` map closure in a setter traps off the main thread.** `Text.foregroundColor`, `ProposalText.foregroundColor`, `EnvironmentValues.foregroundStyle` and `TextRunRequest.init` first used `newValue.map { .color($0) }`; the closure carries a main-actor check and `everyProductionTreeBuildsOnAOneMegabyteThread` (which builds trees on a secondary thread) hit `SIGTRAP` in `ProposalText.foregroundColor.setter`. The setters are explicit `if let`. A new setter that runs while a tree is built must not use a closure.
5. **Stop condition 5 fired for retained translation:** a moved `.equatable()` occurrence holding a gradient text is refused by the existing gate with `unlistedKind:gradient` (`FS-E`: the allow-list is rect, glyph, image, and a gradient fill has always been refused), not `innerScope`. It repaints and equals the retention-off frame (`aMovedOccurrenceHoldingGradientTextIsRefusedByNameAndEqualsAFreshFrame`); `movedLeaf`'s N-element loop is kept and unreachable (M24). Listing `.gradient` in the gate (moving `local` and the content mask by the translation) is a candidate for run 2 or later.
6. **`GroupMark.mask` doc, `Scene.insert` precondition message ("rects, glyphs and images (CM-A, TG-D)"), `Scene.groupMasks` doc, `Renderer.applyMask` doc, the SDL header, fixture and flatten comments and the `drawing.md` sentence** say "rects, glyphs and images" (run 2).
7. **`Text` size (stop condition S did not fire):** `MemoryLayout<ShapeStyleStorage?>.size` = `MemoryLayout<Color?>.size` = 24 (`GradientFill` is 41, so `.gradient` is `indirect` as planned); `MemoryLayout<Text>.size` is 1040 and the field is the same size it was, so no growth; `everyProductionTreeBuildsOnAOneMegabyteThread` passes.

## 5. Pins moved (each with its cause)

| pin | was | now | cause |
|---|---|---|---|
| `aGradientParentLowersToItsFirstStopAndATintParentIsTheTint` | P14 first stop at .5 and the tint half | `aTintParentIsTheTint` (the tint half only) | a gradient parent is kept (`TG-B`); the gradient half is `aLevelOverAGradientParentKeepsTheGradient` |
| `aGradientForegroundStylePaintsItsFirstStop` | first-stop glyph colour | `aGradientForegroundStyleOnTextIsAMaskedGroupAndItsRepresentativeColourIsTheFirstStop` | its `allSatisfy` over the root glyphs went vacuous (the glyphs are the mask's); a vacuous-green pin is a broken instrument |
| `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` | row `foregroundStyle` | row `foregroundStorage` | the stored property is `foregroundStorage`; `foregroundStyle` is computed |
| `RetainedAmbientMissTests` field case | `foregroundStyle = Color(...)` | `= .color(Color(...))` | the fingerprint field is the storage |
| `noMaterialSiteBypassesFillMaterial` | — | green after `resolveForeground` reads `ShapeStyleStorage.material(m).representativeColor` | a literal `material.color` in a new file trips the guard |
| allocation pins, `sceneSideTables…`, the bracket glyph counts, `everyFrameChannelIsClassified` | — | did not move (stop condition A did not fire) | the colour path is byte-identical |

## 6. Runs

- [MEASURED] Root on the final head (`swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel`): **`Test run with 5329 tests in 14 suites passed after 316.943 seconds`** (`FR-J no-argument frame: succeeded=true`; 0 `✘` lines). The same with `METALUI_VERIFY_RETAINED=1`: **`Test run with 5329 tests in 14 suites passed after 316.255 seconds`**. Record 220's line was 5305; 24 tests are new (`TextGradientTests` 20, `RetainedTextGradientTests` 3, `TextGradientCompileGuards` 1). Run 1's first full run (head `9a107281`) failed 4 (section 4 item 4, section 5).
- [MEASURED] Stop condition R and stop condition 2 did not fire (`aGradientTextsCoverageIsTheSolidTexts`: alpha within 1/255 of solid text).
- [MEASURED] `Backends/SDL` on macOS (AccessKit flags), filter `SDLTextGradient|ReplayFixture|SDLClipMask|SDLGroup`: **`Test run with 40 tests in 0 suites passed after 0.032 seconds`** and **`Test run with 15 tests in 0 suites passed after 0.443 seconds`** (the two SDL gradient tests and `aGlyphMaskBodyRoundTripsInVersionNine` are in them).
- [MEASURED] Parity, SDL-over-MSL (`swift run -Xcc -I/opt/homebrew/include -Xlinker -L/opt/homebrew/lib Replay --portable --record`): frames 0-19 all `differing pixels=0, max channel delta=0`, frame 19 `720x380: 0 rects, 3 glyphs, 1 images, 0 transforms, 8 groups, 10 runs`; the draw-order control detects (283 px, delta 152).
- [MEASURED] Parity on llvmpipe Vulkan (`metalui-portable`, the same 20 fixtures, `PortableReplay --driver vulkan --expect 20`): PASS over all 20; **frame 19 outside sprites 0 px max D0 (<=1), inside glyph and image quads 16901 px max D3 (<=8)**; frame 18 D1; frames 12 and 13 D3 against 3, unchanged. The tolerance regions needed no extension (`TG-F`).
- [MEASURED] Portable (`metalui-portable`, `git archive` of the final head): **`Test run with 802 tests in 10 suites passed after 101.978 seconds`**, then 9, 16, 73, 68, 49, 286, 154 and 24 tests in the other targets, all passed (0 `✘`).
- [MEASURED] `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- [NOT RUN] Windows D3D12 and real-hardware Vulkan parity (CI), window arms, every human check (group `TG`).

### 6a. SDL mutations (scratch `git worktree` of `4460a475`, reverted)

| id | mutation | reddened |
|---|---|---|
| S1 | `SDLBridge.c` `render_groups`: the mask-run `draw_run` loop removed | `aGradientTextMatchesMetal`, `aRotatedGradientTextMatchesTheRotatedSolidText`, `aMaskedGroupMatchesMetal`, `aHalfTransparentMaskHalvesTheGroup`, `aMaskIsAppliedBeforeTheGroupsFilter` |
| S2 | `SDLGroupFlatten.append`: the glyph transform shift removed | `aRotatedGradientTextMatchesTheRotatedSolidText` (the first spelling of the test was **green**: the root held no transform record, so the shift was 0; a rotated black swatch before the text fixed the instrument) |
| S3 | `ReplayFixture` writer: `mask.glyphs` replaced by an empty word | `aGlyphMaskBodyRoundTripsInVersionNine` |
| S4 | `FlatFrame.append`: the glyph shift removed | `aGlyphMaskBodyRoundTripsInVersionNine` |
| S5 | `SDLGroupFlatten`: the mask `append` removed | both gradient tests, `aGroupsMaskRunsAreShifted`, `aMaskedGroupMatchesMetal`, `aHalfTransparentMaskHalvesTheGroup`, `aMaskIsAppliedBeforeTheGroupsFilter`, `aMaskThatCannotBeMadeDrawsTheGroupUnmaskedByName` |

SDL stop condition F did not fire: the v9 reader and `validate` accept glyph runs in a mask body, so there is no v10. The oracle of the SDL test is the same tree in solid white: no channel exceeds the solid text's coverage, nothing is drawn where it is clear, the ink runs red to blue. A mid-sweep colour has green (the gradient interpolates in a different space), so no channel is pinned.

## 7. Demo, docs, carried

- Demo `LooksTextGradientStrip` (a `Component` over `looksTextGradientStrip()`, three `@inline(never)` columns), covered by `everyProductionTreeBuildsOnAOneMegabyteThread` in the unfiltered run.
- Parity frame 19 `gradientTextFrame`, `--expect 20` on both lines of `sdl-gpu-linux.yml`.
- Carried (`TG-G`): a moved `.equatable()` occurrence holding gradient text is refused by name (`unlistedKind:gradient`), `.gradient` is not on the allow-list; a counter whose digits change width can re-raster the strip.
- Disk: the working disk filled mid-run; regenerable `.build` directories under the session scratchpad were deleted to continue.

## 8. Divergence outcome

**975 narrowed, not retired.** Removed from the row: a gradient `foregroundStyle` on text, a level over a gradient parent (`P14`), a bare shape's default fill. Kept: a material on text, `border` and `tint`, a material stroke, `TextField`/`TextEditor`/`drawText` text, a gradient text over 8192 on a side (ink in the first stop) and an unmasked degrade when the mask scratch cannot be made. The probe found no difference that needs a new row (the moved-occurrence refusal repaints equal to a fresh frame): **209 live and next label 226, unchanged.**
