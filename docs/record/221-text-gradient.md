# Record 221: a gradient `foregroundStyle` on text (R4-5 PR D) — DRAFT (run 1)

Branch `feat/text-gradient` (master `d0cceec6`). Rulings `TG-A`..`TG-E` (new prefix; decisions doc `docs/superpowers/2026-11-0X-text-gradient-decisions.md` is run 2's). Divergence **975 narrowed, not retired**. Probe `docs/probes/swiftui-text-gradient.swift` (commit `65537362`). Plan: the reviewed R4-5 PR D plan; the deviations are in section 4.

TODO(run 2): decisions doc, ledger (975 text, `docs/divergences.md`, record 04 section), shards, `decision-prefixes.md`, human-checks group `TG`, SDL tests 22-23, parity frame 19, demo strip, `api-overview.md`, `migration.md` (`Text.foregroundColor` computed; `swift package clean`), README row, `Tasks.md`, `CLAUDE.md`/`AGENTS.md` counts.

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
6. **`GroupMark.mask` doc, `Scene.insert` precondition message and the `drawing.md` sentence** say "rects, glyphs and images" (TODO(run 2): the shard and the `Scene` doc comment; the `Scene` precondition text is not yet amended).
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

- [MEASURED] Root on the final head `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel`: **`Test run with 5329 tests in 14 suites passed after 409.049 seconds`** (`FR-J no-argument frame: succeeded=true`; 0 `✘` lines). Record 220's line was 5305: 24 tests are new (`TextGradientTests` 20 including the two wrapped/shadow arms, `RetainedTextGradientTests` 3, `TextGradientCompileGuards` 1, minus the replaced pins, which keep their count). The same with `METALUI_VERIFY_RETAINED=1`: **`Test run with 5329 tests in 14 suites passed after 410.506 seconds`**. The first full run (head `9a107281`) failed 4: `everyProductionTreeBuildsOnAOneMegabyteThread` (section 4 item 4), the P14 pin, `noMaterialSiteBypassesFillMaterial`, `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant` (section 5).
- [MEASURED] Stop condition R (a glyph-mask scratch renders empty or wrong on Metal) did not fire: `aGradientTextsCoverageIsTheSolidTexts` reads alpha within 1/255 of the solid text at every pixel, and the gradient equals a rectangle's within 1/255 (test 1). Stop condition 2 did not fire.
- [MEASURED] `Backends/SDL` on macOS (AccessKit flags), by filter `SDLGroup|SDLClipMask|ReplayFixture`: builds, **39 and 13 tests passed**.
- [MEASURED] Portable (`metalui-portable:latest`, `git archive` of the head): `swift build --build-tests` then `swift test --skip-build --no-parallel`: **802 tests in 10 suites** passed, plus 9, 16, 73, 68, 49, 286, 154 and 24 in the other targets. `RetainedTextGradientTests` run there with `harnessTextSystem`; the Metal pixel tests are Apple-only.
- [MEASURED] `zsh docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- [NOT RUN] Parity (`Replay --portable`) frames 0-19, Linux Vulkan, Windows D3D12: run 2 / CI.

## 7. Not done (run 2)
SDL tests 22-23 (`SDLTextGradientTests`, `ReplayFixtureTests.aGlyphMaskBodyRoundTripsInVersionNine`), parity frame 19 (`--expect 20`), the demo strip, the decisions doc, the ledger and shards, human checks `TG`. [NOT RUN] Linux Vulkan and Windows D3D12, window arms, any human check.
