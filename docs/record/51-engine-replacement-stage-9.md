# §51 — Engine replacement, stage 9: engine deletion

Plan task 7, stage 9 (`docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
§4.1 row 9, §8). Spec `docs/superpowers/specs/2026-09-24-engine-stage-9-design.md`;
rulings `LR-FC`…`LR-FG` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-9` from `b9a5d7f` (`master`, stage 8 merged), worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-9`.

## 1. Baseline at `b9a5d7f` (2026-09-24, PDT)

`swift build --build-system native --build-tests` → `Build complete!`, 0
`error:`, one `warning:` (SwiftPM's `--build-system native` deprecation notice).
Unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1452 tests in 3 suites passed after 91.885 seconds`**, the log
carrying `FR-J no-argument frame: succeeded=true deprecations=2` (guards ran).

## 2. The entry measurement (design, 2026-09-24)

### 2.1 Runtime census — who reaches the legacy side

**Instrument**: `docs/probes/stage-9-legacy-reach-instrument.patch`, three
`print`s — `S9MARK-ENGINE` in `computeLayout` after its `SA-G` check,
`S9MARK-NEWNODE` at the top of `LayoutTree.newNode`, `S9MARK-LEGACYFRAME` in
`Frame.init` when the authority is `.legacy`. Applied at `b9a5d7f`, built, one
unfiltered run (`Test run with 1452 tests in 3 suites passed after 91.068
seconds`, 163 943 markers), reverted (`git checkout Sources`, `git status
--short` clean but for this design's files). Attribution: the last `Test …
started.` line before a marker (a plain test, or `Test case passing … to NAME(…)
started.` for a parameterised case); `--no-parallel` serializes. Exit-test
children print to their own streams and are not seen.

**Result: 206 tests** (`docs/probes/stage-9-legacy-reach-census.txt`, one line
per test with its file and markers):

- **200** carry all three markers — a `.legacy` frame that registered CSS
  nodes and ran the CSS engine. This is record §49 §2's census A (199) plus
  stage 8's `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities` (N1.2,
  `PresentationLoweringTests` reads 5 where §49 read 4); `ScrollRoutingTests`
  reads 15 where the roll call lists 16 scenarios (one scenario lays nothing
  out under `.legacy` in-process).
- **6** carry `NEWNODE` alone: `LayoutTreeTests`' six plain tests, which mint
  ids with `newNode` and never lay out.

By file: `LoweringItemTests` 27, `ListTests` 21, `ScrollRoutingTests` 15,
`ScrollIndicatorTests` 14, `LoweringStackAndLayerTests` 11,
`LoweringDistributionTests` 9, `LoweringComponentTests` 9,
`LoweringContainerTests` 7, `LoweringBoxModelTests` 7, `PresentationWindowTests`
6, `LoweringScrollTests` 6, `LoweringLeafTests` 6, `LayoutTreeTests` 6,
`AccessibilityDefaultsTests` 6, `PresentationLoweringTests` 5,
`LayoutAuthorityTests` 5, `DeferredTests` 5, `AccessibilityTreeTests` 5,
`ScrollViewTests` 4, `MeasurePerformanceTests` 4, `LoweringPipelineParityTests`
3, `LoweringCorpusTests` 3, `ListLoweringTests` 3, `AXNodeTests` 3,
`HiddenLoweringTests` 2, `FrameSizingTests` 2; one each in `TombstoneTests`,
`TextSystemSeamTests`, `TextFieldTests`, `RootSwitchTests`,
`RootFieldLoweringTests`, `ProposalNodeIDTests`, `ModifierCompositionProofTests`,
`FocusTests`, `EnvironmentTests`, `DecorationPaintTests`, `AbsoluteOverlayTests`.

### 2.2 Static census, and the scratch deletion

**Static census** (`docs/probes/stage-9-legacy-reference-census.tsv`): a script
split every test file into `@Test` blocks (a block runs to the next `@Test`,
comment lines dropped) and listed every block naming a symbol row 9 deletes
(`.legacy`, `LayoutAuthority`, `layoutAuthority`, `lowersToProposal`,
`legacyRootLayoutCounter`, `requestNode(`, `requestLeaf(`, `textMeasure(`,
`computeLayout(`, `newNode(`, `newLeaf(`, `setStyle(`, `tree.style(`,
`AvailableSpace`, `MeasureFunction`, `minContentWidth`, `unbreakableRuns`,
`runCallCounter`, `customElement`, the four `deferred.*` fields,
`AuthorityCoverage`, `LayoutDifferential`, `WindowPair`, `minContentCount`,
`isNativeLayoutNode`, `defaultLayoutAuthority`, `maxContentWidth`,
`expectFullAgreement`, `authorities`) or appearing in §2.1: **371 rows, 71
files** (columns: file, test, `C` if in §2.1, `EXIT` if an exit test, the
symbols hit). Blocks include trailing helpers, so a row can be a false positive
(a helper after the test); lanes read the test, not the row.

**Scratch deletion**, applied and reverted:

1. `git rm` of `FlexEngine.swift`, `ResolveFlexibleLengths.swift`,
   `FlexBaseSize.swift`, `FlexLines.swift`, `Alignment.swift`,
   `LayoutContext.swift`, `Resolve.swift`, and `MeasureFunction.swift` cut after
   `OptionalSizeD` → `swift build --build-system native`: errors in
   **`Sources/MetalUILayout/LayoutTree.swift` alone** (`MeasureFunction` in the
   `measures` row, `newLeaf` and `measure(_:)`).
2. `LayoutTree`'s `styles`/`measures` rows, `newNode`, `newLeaf`, `style`,
   `setStyle`, `measure` removed, `appendNode(style:)` → `appendNode(children:)`,
   `nodeCount` on `childLists` → `MetalUILayout` compiles; `MetalUI` fails in
   `Frame.swift` (7 distinct errors: `newNode`, `newLeaf`, `MeasureFunction`,
   `style`, `setStyle`, `computeLayout`, `AvailableSpaceSize`), `Passes.swift`
   (1) and `Text.swift` (3).
3. Also `LayoutAuthority.legacy`, `Frame.requestNode`/`requestLeaf`/`style`/
   `setStyle`, `LayoutPass.requestNode`/`requestLeaf`/`lowersToProposal`
   removed → the compiler's visible set: `Box` 2, `Component` 1, `Deferred` 1,
   `Frame` 3, `ListRows` 2, `ModifiedElement` 3, `Passes` 2, `ScrollView` 3,
   `Stack` 2, `Text` 5, `TextField` 2 — every one a legacy branch or a
   registrar call.

`resolveLength`/`resolveDimension`/`resolveEdges`/`resolveMargin`/`clamp`/
`ResolvedEdges` have no reference outside the engine files in `Sources`,
`Tests`, `Backends/SDL`, `Tests/PortableTests` or `Experiments` (the hits named
`clamp` elsewhere are `ScrollChrome.clamp` and comments). `OptionalSizeD` and
`AvailableSpace*` are referenced only by `textMeasure`, `computeRootLayout`'s
legacy branch and three retired tests (`LayoutTreeTests`' measure-function
test, `TextMeasureTests`). `minContentWidth` has one production caller,
`Text.swift:94` inside `textMeasure`. No file under `Backends/SDL`,
`Tests/PortableTests/Sources`, `Experiments` or a compiled probe names a
deleted symbol, except `docs/probes/demo-pixels/ZZDemoPixels.swift` (its chrome
pair under both authorities, via `makeFakeWindow(layoutAuthority:)`).
`Tests/PortableTests` calls `PortableText.unbreakableRuns`/`minContentWidth`/
`maxContentWidth`, which `LR-FD` keeps. `Tests/MetalUICrossPlatformTests/Expected.swift`
names `layoutAuthority: .legacy` in a comment only.

### 2.3 The differential tests

94 `@Test` blocks call `LayoutDifferential.compare` or build a `WindowPair`. A
heuristic for a hand-derived literal (`bounds(<digit>`, `Bounds(`,
`LayoutRect(`, `== [`, `.x ==`, `.width ==`, `width: Pixels(<digit>`) finds
none in 15: `DecorationPaintTests.aDeferredPortalInsideAFadedSubtreeIsStillFaded`;
`LayoutAuthorityTests.theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState`;
`ListLoweringTests.aZeroRowHeightLowersWithoutTrappingOrProducingNaN`;
`LoweringComponentTests`' `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
`aComponentsPaddingLowersAsAnOrdinaryOneChildContainer`,
`aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`,
`theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities`,
`chainedComponentAmendsComposeTheSameWayUnderBothAuthorities`,
`anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`,
`aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`,
`aFrameOverSeveralMembersStillPlansEachMembersItemFields`,
`aFrameOverOneMemberIsUnchanged`;
`LoweringLeafTests.aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`;
`LoweringPipelineParityTests.aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`;
`PresentationWindowTests.anAnimatedInsetInterpolatesItsValueUnderBothAuthorities`.
The heuristic misses literals asserted through helpers (the component file's
own helpers among them), so lane 1 reads each; these are the first place a
literal may be owed (`LR-FE` item 2).

The roll call requires **87** scenarios (16 routing, 14 indicator, 4
`ScrollViewTests`, 21 `ListTests`, 3 `AXNodeTests`, 6
`AccessibilityDefaultsTests`, 5 `AccessibilityTreeTests`, 1 `FocusTests`, 1
`TombstoneTests`, 2 `MeasurePerformanceTests`, 5 `DeferredTests`, 1
`AbsoluteOverlayTests`, 6 `PresentationWindowTests`, 1 `DecorationPaintTests`,
1 `EnvironmentTests`) — CLAUDE.md still reads 82 (stage 5's figure).

## 3. The containing block, measured (design, 2026-09-24)

A scratch build with `reportPresentationContainingBlock(root:)`'s call deleted
from `Frame.computeRootLayout` and `Deferred`'s `nested` `noteUnlowerable`
replaced by a no-op, plus a scratch test (`Tests/MetalUITests/ZZScratchS9.swift`,
deleted after) rendering each tree **as the root** of a plain 200×100 `Frame`
under `.proposal` with diagnostics on, printing the report and every hitbox.
The presented content is `PresentationLoweringTests`' `presented()` — a 10×10
`Box` with a background and an `onClick`, `.position(.absolute)`, right and
bottom insets 5 — inside a `Deferred`:

| arm (1.5's name) | report at `b9a5d7f` | report, reports removed | hitbox, reports removed |
|---|---|---|---|
| bordered root | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| root width 100 in 200 | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| auto root (control) | `[]` | `[]` | (185, 85) 10×10 |
| `Deferred` root | `deferred.root` | `[]` | (185, 85) 10×10 |
| inside a top/left-5 presentation | `deferred.nested` | `[]` | (185, 85) 10×10 |
| root `.frame(maxWidth: 100)` | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| root `.frame(minWidth: 300)` | `deferred.containingBlock` | `[]` | (185, 85) 10×10 |
| inside a bordered `inset(0)` presentation | `deferred.nested` | `[]` | (185, 85) 10×10 |

(185, 85) is the window's width and height less the 5-point insets and the
box: the containing block is the window in every arm, as `LR-CL` constructs
it. The outer presentations in the two nested arms carry no `onClick`, so only
the inner box has a hitbox.

**The amended arm.** The same scratch plus `loweredComponentFrame`'s
`deferred.amended` `noteUnlowerable` deleted; `Box { PresentingSolo().width(70) }`
(a `Component` whose one member is a `Deferred` over a top/left-5 10×10
absolute box) and the same tree without `.width(70)`: both report `[]` and put
the hitbox at **(5, 5) 10×10** — the amend is dropped with nothing said. The
legacy amend overwrote the box's own width (divergence 48's mechanism). `LR-FF`
keeps the report and re-owns it to stage 11.

Everything was reverted (`git checkout Sources`, the scratch test removed;
`git status --short` showed only this design's files).
