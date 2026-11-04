# Record 203: default spacing at a text edge (round 4 item R4-2 PR B)

Branch `feat/r4-2-text-edges`, from master `eb4cc1c2` (PR A, #198, merged). Decisions: `docs/superpowers/2026-11-03-default-spacing-decisions.md` (`DS-E`..`DS-K`). Human checks: group `DS` (`DS1`..`DS3`, not run). Divergences: **65 retired, 51 narrowed to the lazy containers, 213 and 214 added** (208 live: 207 - 1 + 2; next label 215, the first of item 8's reserved range 215-224, so a new row after these needs a deliberate choice). Class `A`, with two MetalUI rulings that are not measurements: the rule on Linux and Windows (`DS-F` item 2) and the three-kind union (`DS-G`).

## 1. What changed

- `TextFontMetrics.capHeight: Double?` (`MetalUITextSystem`; the initialiser's argument is defaulted, so a third-party `TextSystem` conformer compiles); CoreText fills it from `CTFontGetCapHeight`, the portable system from `OS/2.sCapHeight` (`FreeTypeFont.capHeight`, `package`). A new stored property on a public type: `swift package clean`.
- `MetalUILayout`: `TextSpacingMetrics`, `SpacingEdge` (zero, standard, text) and `ProposalSpacing.defaultGap(after:before:axis:)` (`ProposalSpacing.swift`); `LayoutTree.spacingEdges` (was `zeroSpacingEdges`) walks them with the unions of `DS8` and `DS9`; `spacingMarks` is cleared by `reset`, carried by `LayoutSegment` and its graft, shown in `structureDigest`, and mixed into `nodeSignature` for marked nodes only; `NativeGridEdges` holds `SpacingEdge`s and a grid pair's gap is `defaultGap`.
- `MetalUI`: `Text` and `ProposalText` (plain and styled) mark their edge when they register (`TextSpacing.swift`); `Button` (bordered, glass), `Toggle` (every look), `Stepper`, `Picker`, `ColorPicker` and `ProgressView` mark their root node standard (`markControlSpacing`).
- Tests: `DefaultSpacingTests` (pure, 15, runs on Linux and Windows), `DefaultSpacingIntegrationTests` (macOS, 8), `DefaultSpacingRetainedTests` (3), `LayoutMemoTests` (two parameter arms, count 34 -> 36, and the unmarked-signature literal), `PortableCapHeightTests`; the 51 pin renamed `aProposalTextStackTakesItsTextEdgeGaps`, the 65 pin `textRowsMeetWithoutARowGap`.

## 2. Scope changes against the plan

- **The suppression flag is a node mark** (`DS-H` item 1): the same effect on every control, and a text inside a control's own label keeps the text rule's gaps.
- **Stop condition 8 fired in one place and was reported, not improvised** (`DS-G` item 4): `HStack{rect; text}`, `ZStack{rect; text}` and `Pass{rect; text}` read like a standard edge beside a TEXT neighbour (`DS9`: 4.742, 8.151, 9.484, 16.302) where the three-kind union reads text over text (0). Pinned as the ruling reads it (`aMixedCompositeBesideTextIsPinnedAsTheRulingReadsIt`), in row 213.
- **Unmeasured spelling:** a width-only fixed `.frame` is treated as passing the edge (the probe's fixed frame had both dimensions); a fixed-height frame makes a text edge standard.
- `Image(systemName:)` is not offered, so row 213 has no symbol edge. No `Label`-shaped spelling exists. A custom `ButtonStyle` or `ToggleStyle` body is not marked.
- **No quantisation** (plan section 2): gaps are exact; the counters in section 5 did not move.

## 3. Tests that flipped

| test | old | new |
|---|---|---|
| `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` -> `aProposalTextStackTakesItsTextEdgeGaps` | text\|text 8, text\|rect 8 (rounded) | text\|text 0, text\|rect 8.151, rect\|text 4.742 (unrounded), rect\|rect 8 |
| `textRowsTakeTheDefaultRowSpacing` -> `textRowsMeetWithoutARowGap` | two text rows `line + 8 + line` | `line + line`; a rect row above a text row 4.742 |
| `aFormOfTextCellsOffersTheValueColumnTheRemainder` | height `row0 + 8 + long` | `row0 + long` (the column gap's 8 stays) |
| `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt` | form 400x185; rows c, picker, divider, row f at y 80, 104, 136, 145 | 400x182; 77, 101, 133, 142 |
| `theControlsDemosSwiftUISectionLaysOutWithoutReports` | the same figures | the same new figures |
| `theSeamsMetricsAgreeOnBothSystems` | `TextFontMetrics` equality without a cap height | with `CTFontGetCapHeight`, and portable vs CoreText within 1e-3 |

**The form reads FM0's figure:** `theFormMatchesFM0` pins the unrounded height, 182.044 (16 + 24 + 8.151 + 24 + 4.742 + 16 + 8.151 + 24 + 8 + 1 + 8 + 24 + 16); the placed form is 182. The prediction `185 - 40 + 37.04 = 182.04` held. No other test reddened in the first unfiltered run.

## 4. Mutations (applied from the committed tree by `scratchpad/mut/run.py`, restored with `git checkout`; names are the tests that reddened; filter `DefaultSpacing|LayoutMemoTests|` the flipped tests, the seam and cap-height tests, `NativeGridTests|NativeStackDistributionTests|aLazyStack`, default build system)

| mutation (spelling) | reddened |
|---|---|
| M1 `defaultGap` returns the 13 pt figures 4.742 / 8.151 / 0 | `aTextEdgeGapIsTheProbesFigureAtEverySize` (every face but `SF 13`, which stayed green: the separating arm), `unequalFontsTakeTheLowerTextsLeading`, `aRowsTextEdgeWinsOverItsControl`, `aGridsRowGapIsTheLargestPairOverTextCells`, `aFontChangeMovesTheGap`, `aRichTextLeafTakesItsTextEdges`, `aGraftedTextStackKeepsItsGap` |
| M1b the cap term dropped (`- (above.ascent - above.capHeight)` removed) | `aTextEdgeGapIsTheProbesFigureAtEverySize` (all faces with a cap below the ascent; `DIN Condensed 13`, cap = ascent, green), `aPaddedTextHasAStandardEdge`, `aZeroPaddingKeepsTheTextEdge`, `aFixedHeightFrameTurnsATextEdgeStandard`, `aRowsTextEdgeWinsOverItsControl`, `aNestedStackTakesItsFirstAndLastChildsTextEdge`, `aGridsRowGapIsTheLargestPairOverTextCells`, `aPlainTextLeafTakesItsTextEdges`, `aRichTextLeafTakesItsTextEdges`, `aFontChangeMovesTheGap`, `aProposalTextStackTakesItsTextEdgeGaps`, the two form tests, `everyControlKeepsAStandardEdgeBesideText` |
| M2 text\|text always 0 | `aTextEdgeGapIsTheProbesFigureAtEverySize` (the two faces with a leading), `unequalFontsTakeTheLowerTextsLeading` |
| M3 `.zero` not checked first | `aSpacerBesideTextStillTakesNoDefaultSpacing`, `aSpacersNilMinimumIsConstantBesideText`, `anEmptyTextHasNoVerticalEdge`, and 10 existing grid and spacer tests |
| M4 padding passes the text edge at any inset | `aPaddedTextHasAStandardEdge` and the existing `defaultSpacingBesideASpacerIsDecidedPerEdgeThroughItsWrappers`, `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges`, `eachGapIsTheLargestPairSpacingMeetingThere`, `gapsHoldAtFiniteProposals` |
| M5 a standard edge beats a text edge in the union | `aRowsTextEdgeWinsOverItsControl`, `aMixedCompositeBesideTextIsPinnedAsTheRulingReadsIt`, `everyControlKeepsAStandardEdgeBesideText`, both form tests |
| M6 a nested stack's trailing edge is its first child's | `aNestedStackTakesItsFirstAndLastChildsTextEdge`, `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges` |
| M7 the text edge on both axes (`spacingEdges` and the `defaultGap` guard) | `theHorizontalGapIsEightBesideText` (all faces), `textRowsMeetWithoutARowGap`, `aFormOfTextCellsOffersTheValueColumnTheRemainder` |
| M8 explicit spacing consults the edges (`stackGaps` and the measure branch `if let spacing, spacingMarks.isEmpty`) | `anExplicitSpacingIgnoresTextEdges`, `aGraftedTextStackKeepsItsGap`, both form tests. **First spelling green**: with `stackGaps` alone the measure path never reaches it for an explicit spacing (it sums the spacing itself); the test was right, the mutant was not; re-applied at both sites |
| M9 `Spacer()`'s nil minimum read from `defaultGap` | `aSpacersNilMinimumIsConstantBesideText` and 10 existing spacer and grid tests |
| M10 grid `pair` ignores the metrics | `aGridsRowGapIsTheLargestPairOverTextCells`, `textRowsMeetWithoutARowGap`, `aFormOfTextCellsOffersTheValueColumnTheRemainder` |
| M11 the `DS-E` tag line removed from `nodeSignature` | `everyRegistrarParameterIsInItsSignature` (arms `leaf.textSpacing`, `node.controlSpacing` only), `anUnmarkedTreesSignatureIsUnchangedByTheSpacingMark` |
| M12 the tag mixed unconditionally | `anUnmarkedTreesSignatureIsUnchangedByTheSpacingMark` only |
| M13 `Text.swift` plain site not marked | `aPlainTextLeafTakesItsTextEdges` (the `Text` arms; `ProposalText` arms green), `aGraftedTextStackKeepsItsGap`, the form tests |
| M14 `ProposalText.swift` plain site not marked | `aPlainTextLeafTakesItsTextEdges` (the `ProposalText` arms), `aProposalTextStackTakesItsTextEdgeGaps`, `textRowsMeetWithoutARowGap`, `aFormOfTextCells...`, `aFontChangeMovesTheGap` |
| M15 both rich sites not marked | `aRichTextLeafTakesItsTextEdges` only |
| M16 `markControlSpacing` removed, one control at a time (Button, Toggle, Stepper, ColorPicker, ProgressView; Picker's options-style site) | `everyControlKeepsAStandardEdgeBesideText` each (`Toggle` also `aToggleBesideAToggleKeepsEight`). The Picker menu-style site was not mutated separately |
| M17 the mark cached by node index | `aFontChangeMovesTheGap`, `aRichTextLeafTakesItsTextEdges`, `anEmptyTextHasNoVerticalEdge` |
| M18 `LayoutSegment` capture drops the marks | `aGraftedTextStackKeepsItsGap`. Under `METALUI_VERIFY_RETAINED=1` the filter `RetainedVerifyTests\|DefaultSpacingRetainedTests\|RetainedGraft` traps naming the layout tree (`a replayed prepaint differs from a fresh one: layout tree ... ts:`): `aVerifiedGraftThatDiffersTraps` and six more. **`aGraftedTextStackKeepsItsGap` itself stays green in verify mode** (the presented frame is the second, fresh build; the existing verify fixtures carry the trap) |
| M19 `TextLeafKey` drops `font` | **nothing** (3 retained tests green): the spacing mark carries the metrics into the signature, so the key is not the only guard. With M11 added (`M19+M11`): `aFontChangeUnderAnEquatableParentMovesTheGap` |
| M20 the mark mixed with the tree's generation | `aSteadyTextStackHitsTheMemoAndMeasuresNothing` |
| M21 the walk calls a marked leaf's measure closure | `aTextStacksLayoutWorkEqualsARectStacks` (leaf closure calls; the kernel's own counters are blind to a walk that measures, which is why the test counts the closures) |
| M23 a fixed-height frame passes the text edge | `aFixedHeightFrameTurnsATextEdgeStandard` |
| M24 an empty text not marked zero | `anEmptyTextHasNoVerticalEdge` |
| M25 `Toggle` and `Button` marks removed | `theFormMatchesFM0`, `everyControlKeepsAStandardEdgeBesideText`, `aToggleBesideAToggleKeepsEight` |

**Findings:** M19 is green by design (a second guard, not a hole); M8's first spelling was a mutant that reached nothing; the three `lazy` and `portable` mutations of the plan were not run (no lazy change; `PortableCapHeightTests` has no mutation run: `capHeight` read from `sxHeight`, or left `nil`, is stated in its comment and was not applied).

## 5. Memo and translation counters

Unmoved: the pinned bracket literals `aDragFrameRestoresTheUnmovedOccurrencesPlacement` (11 subtree hits, 362 / 1258 memo hits, 331 / 366 cache hits, 52 measure calls, 0 root hits), `RetainedPlacementTests`, `PlacementTranslationTests` and the translation-gate tests are green with their literals in the unfiltered run, so `translatedPlacements`, `fractionalTranslation` and `inexactTranslation` read as before; a steady text stack hits the root memo three times in three frames and measures nothing (`aSteadyTextStackHitsTheMemoAndMeasuresNothing`). The 1/16 quantisation was not needed and not taken. Allocation pins (`PA-`) green.

## 6. For callers (MetalCreator, MetalFlow)

Behaviour: a default-spaced `VStack` or `Grid` next to a `Text` changes (the rule in `DS-E`); `spacing:` given, horizontal gaps, `Spacer()` and non-text pairs do not. Both apps use `.package(path: "../MetalUI")`, so they build whatever MetalUI is checked out. Grep at the merge base (`eb4cc1c2`; apps read 2026-11-03, MetalCreator `da57d91` and MetalFlow `e9d90ef`, both `main`), `Sources/` only, pattern `\b(VStack|Grid)(\(alignment: *[.a-zA-Z]+\))? *\{` plus `\b(VStack|Grid|LazyVStack)\($` for a broken-across-lines call:
- **MetalCreator: 0 default-spaced `VStack`**, 0 MetalUI `Grid` (the one hit, `CoarseSampling.swift:43`, is a private struct; `AnchorGridView.swift:9` is `Grid(horizontalSpacing: 2, verticalSpacing: 2)`, explicit, unchanged), 6 default `HStack`s (horizontal 8, unchanged), every `VStack` gives `spacing:`, no lazy container and no `ProposalScrollView`. Nothing moves.
- **MetalFlow: 0 default-spaced `VStack`, `Grid` or `HStack`**; every `VStack` gives `spacing:`; six lazy containers (`LazyVGrid` x5 with `spacing:`, `LazyVStack(spacing: 0)`) keep 8 / their given spacing (divergence 51 narrowed). Nothing moves.
- Neither app builds in this branch's tests; their own tests were not run.
- To find what moved in another app: the grep above next to a `Text`, or read `frame(ofID:)` / `MetalUITesting` frames before and after.

## 7. Counts and checks

See the end of this section, filled by the final runs.
