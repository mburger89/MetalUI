# §30 — Engine replacement, stage 6a: custom elements, and tests that are about CSS answers

Plan task 7, stage 6a (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 6a,
rulings `LR-R`, `FR-I`, §8). Design:
`docs/superpowers/specs/2026-09-23-engine-stage-6a-design.md`. Rulings
`LR-CT`…`LR-CZ` (design) in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Probe:
`docs/probes/swift-deprecated-witness-silence.sh` (a compiler probe, no
SwiftUI claim). Branch `feat/engine-stage-6a` from `b3c29b9`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-6a`.

**Status, 2026-09-23 (PDT): designed.** §1–§6 are the design's measurements —
the stage's **entry measurement** is §4. Every one was taken on scratch
commits (`9ccc0d8`…`59b63ad`, listed in §2) that `a1b6edf` reverts to
`b3c29b9`'s tree exactly (`git diff --quiet b3c29b9 a1b6edf` succeeds); they
stay in the history so a later reader can re-run an arm by checking it out.
Critic round 1 is §7; the lanes append from §8.

## 1. Baseline at `b3c29b9`

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`, unfiltered: **`Test run with 1640 tests in
3 suites passed after 78.526 seconds`**; 0 `error:`; the only `warning:` is
SwiftPM's `--build-system native` deprecation notice; the log carries `FR-J
no-argument frame: succeeded=` (the guards ran). Goldens 97
(`find Tests/MetalUILayoutTests -name "*.json" | wc -l`), guards 77 (79
`canTypecheck` hits less `Typecheck.swift`'s declaration and
`UnitSafetyTests`' comment).

**The callers.** `grep -rn 'requestNode(\|requestLeaf(' Sources Tests
--include='*.swift' | grep -v 'requestNative\|func requestNode\|func
requestLeaf'` reads **85 lines**. Of them:

- **10 in `Sources/`**, none a caller of the public pair: `Passes.swift`'s two
  forwarders call `frame.requestNode`/`frame.requestLeaf`, and the eight site
  calls (`Box`, `Stack`, `Text`, `ModifiedElement`, `ScrollView` ×2,
  `ListRows`' spacer, `Component`'s amend) already go through the internal
  `pass.frame.requestNode`/`requestLeaf`. `LR-R`'s sentence "Sources' own sites
  call the public forwarders today; they move … in the same change" was true
  when written and is **not** true at `b3c29b9`: every site checks the authority
  itself and then calls `Frame`'s registrar (`LR-C`'s per-site checks;
  `Frame.requestNode`'s doc comment: "every in-module legacy site calls this
  rather than `LayoutPass`'s public forwarder"). Which commit moved them was not
  looked up; the grep above is the claim. **So the deprecation warns nothing inside `MetalUI`**; every
  warning it can raise is in `Tests/`.
- **5 in doc comments** (`AXNodeTests:640`, `TombstoneTests:156`,
  `ComponentTests:100`, `NativeBoundaryIntegrationTests:91`,
  `MeasurePerformanceTests:861`) and **4 already on `pass.frame.`**
  (`LayoutDifferential:68`, `LoweringStackAndLayerTests:387`,
  `LayoutAuthorityTests:62–63`, the backstop probe).
- **66 test call sites on the public pair, in 35 files.** 8 of them are inside
  typecheck fixture strings (`PhaseSeparationTests` 2, `ErasureCompileGuards` 1,
  `ProposalNodeIDCompileGuards` 3, `FrameSizingCompileGuards` 1,
  `ModifiedElementCompileGuards` 1): a child `swiftc` compiles them against the
  built module, and its output never reaches the build log's `warning:` count
  (`EnvironmentCompileGuards.swift:36–38` says so for the `Binding`
  deprecation). The other 58 compile into the test target and **each would
  print one `warning:`** once the pair is deprecated. The spec's §5 lists every
  one with its disposition. (The task brief's "about 89" is this grep's order of
  magnitude; at `b3c29b9` it reads 85 lines, of which these 66 are callers.)

## 2. The instrument: the default flipped, and five arms

`LR-R` asks for "the suite with the default authority flipped and
diagnostics on". Measured, **the first spelling of that instrument reached
barely half the suite**, and the reason is a finding for 6b.

**Arm A** (`9ccc0d8`): `Frame.init`'s defaults `layoutAuthority: .proposal,
reportsUnlowerableFields: true`; `Window.layoutAuthority`'s default
`.proposal` and `reportsUnlowerableFields: true` passed to every frame it
builds; `Frame.noteUnlowerable` and the backstop print `SIXA-UNLOWERABLE:
<site>.<field>` / `SIXA-BACKSTOP: <registrar>` so each red test's report is in
the log between its `started` and `failed` lines (`--no-parallel`). Result:
`Test run with 1640 tests in 3 suites failed … with 296 issues`, **88** tests
red, no truncation. **But `makeFakeWindow` passes `layoutAuthority: .legacy`
explicitly** (`Fakes.swift:246`, a parameter default, written "only when it
differs" — so a window test at defaults writes `.legacy` over the flipped
`Window` default), **and so do seven file-local render helpers**
(`AXNodeTests:29` and `:673`, `DecorationPaintTests:69`,
`AccessibilityTreeTests:45`, `ScrollIndicatorTests:65`,
`AccessibilityDefaultsTests:51`, `ScrollViewTests:31`,
`MeasurePerformanceTests:43`). Every window test and every test through those
helpers stayed legacy in arm A.

**The flipped default, as 6b will see it** (`2a7cec0` over arm C, then
`0d02538`): those eight helper defaults flipped to `.proposal` too, and — because
`makeFakeWindow`'s windows and `MeasurePerformanceTests`' helper build
production frames that **trap** on an unlowerable field (the first attempt
truncated at `aWarmFrameTokenizesEachDistinctStringAtMostOnce` on
`box.minSize.unconsumed`) — `noteUnlowerable` and the backstop made non-fatal,
printing `SIXA-WOULD-TRAP:` where they would have trapped. Five such lines in
the final arm, all under tests the table below names. Then five arms, each a
full unfiltered run on its own commit:

| arm | commit | custom elements (`LayoutPass.requestNode`/`requestLeaf` under `.proposal`) | native root placed | red |
|---|---|---|---|---|
| **A2** — the flipped default | `95f0630` | reported `customElement.*`, a 0×0 native leaf in their place (production behaviour) | centred at its answer (`CN-J`, production) | **153** |
| B2 | `903fc8c` | **lowered as a `Box`**: `lowerLegacyNode(style, declared: style, children:, site: .customElement)` / `lowerLegacyLeaf` over a native leaf calling the CSS measure function with `known` nil and `available` definite-or-`maxContent` from the proposal | centred | 147 |
| C2 | `0d02538` | lowered as B2 | **at the window rect** (the legacy auto root's `CS-I` fill, divergence 4) | 132 |
| C3 | `c0d8dfd` | reported, as A2 | **top-leading at its own answer** (the legacy sized root) | 153 |
| B3 | `59b63ad` | lowered as B2 | top-leading at its answer | 137 |

B2 and C2/C3/B3 are **separating arms, not proposals**: B2 asks "is this red
only because a custom element reports?", C2/C3/B3 "is it red only because the
root is placed where the legacy root is not?". None of them is a design. The
counts are distinct tests (the log's 154 `failed after` lines in A2 include
`Suite MeasurePerformanceTests failed`).

## 3. The probe: a deprecated witness is silent

Five fixtures exist to be spelled with the public registrars
(`LegacySpelledAXListLeaf`, `LegacySpelledRow`, `LegacySpelledExcursionRow`,
`LegacySpelledStatefulListRow`: stage 4's recorded red-befores, each the
subject of an exit test asserting `customElement.requestNode has no proposal
lowering`; and `LayoutAuthorityTests`' `CustomNodeElement`/`CustomLeafElement`,
the subjects of 1.3 and of `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`),
and the stage's exit test needs a sixth. They cannot move and must not warn.
`docs/probes/swift-deprecated-witness-silence.sh`, run 2026-09-23 with Apple
Swift 6.4: a plain call warns (the positive control, one line); a call inside
a declaration marked deprecated does not; a deprecated method used as a
protocol witness does not warn at the conformance or at a generic call site;
and **a fixture whose `requestLayout` witness is marked
`@available(*, deprecated, message:)`, rendered through a generic `render`,
warns nothing under Swift 5 or 6 mode**. `LR-CV` rests on that.

## 4. The entry measurement — every red test of the flipped default, classified

A2 is the flipped default; the other arms attribute its reds. Classes:

| class | meaning | owner | count |
|---|---|---|---|
| **X** | an exit test of a **production** proposal trap; red only because the instrument made traps non-fatal. Not an entry red: each already passes `.proposal` explicitly and is untouched by the default | — | 13 |
| **D** | asserts the default authority itself | 6b | 2 |
| **N9** | a legacy-authority boundary at the default authority — `SA-G`'s native-under-legacy traps, which `LR-T` lifts under `.proposal`, and `MC-G`'s legacy-registration holes | 9 (deleted with the legacy authority); 6a pins the two callers among them | 5 |
| **RP** | **root placement**: green in C2 or C3 — red only because a native root is centred at its answer (`CN-J`) where the legacy root fills an `auto` axis and sits at (0, 0) | **6b** (divergence 4 vs `CN-J`) | 54 |
| **CE** | custom element only: green in B2 | **6a** (re-spelled here) | 6 |
| **CE+RP** | custom element **and** root placement: red in B2, green in B3 or C2 | 6a pins; **6b** re-spells after ruling the root | 23 |
| **AV** | `hidden()` / `display: none` reported (`box`/`modifierLayer.display.none`) — `LR-AV` defers it to "task 7 before stage 9" with **no stage number**, and `owningStage` names stage 2, which is closed | **unassigned — 6b must assign it** (the five tests are at the default and go red at 6b's flip) | 5 |
| **RT** | a root's item field no parent consumes (`box.minSize.unconsumed` on the root; `WOULD-TRAP` in A2) | 6b (the root) | 1 |
| **CSS-structure** | asserts the legacy tree's shape — `tree.nodeCount`, a node delta, "identical to hand-built nested boxes" | **7b** | 14 |
| **CSS-style** | reads a `Style` or a CSS measure function off a registered node (`tree.style`, `tree.measure`, `pass.style(node)`) | 7b | 7 |
| **CSS-text** | a WebKit text answer (stretch-and-wrap at the column's width, shrink-wrap "like WebKit") | 7b | 3 |
| **CSS-frame** | the legacy `.frame`'s CSS lowering (`FR-C`/`CN-N`: a fixed frame as a flex item, `minSize`/`maxSize` clamps, the one-cell stack's overflow, a percentage size, an absolute child) — red in every arm | 7b | 10 |
| **CSS-d48** | divergence 48: a `Component`'s `.width`/`.height` **overwrites** each member (stage 3 lowered it to one frame per member; the overwrite is the legacy answer) | 7b | 5 |
| **CSS-pin** | a "legacy X where proposal Y" comparison whose legacy arm ran under the default | 7b (6a pins the legacy arm) | 2 |
| **CSS-box** | margin / padding edges on a stretched custom leaf: needs the `Box` lowering's stretch, which a native leaf never gets (record §23 X2: a child with no record is never stretched) | 7b | 2 |
| **RP+CSS-frame** (the design's UNATTRIBUTED) | red in all five arms, no custom element, no report: `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` — attributed by the critic round's measurement (§7.2): three arms are root placement, the fourth is `FR-E`'s legacy flexible frame | 6b (root), 7b (`FR-E`) | 1 |
| | | **total** | **153** |

**What this says to 6b.** Of the 140 non-X reds, **54 + 23 + 1 are root
placement** (78 — more than half the flip), two assert the default, five are
`hidden()` with no owner, one is unattributed. 6b's "root placement ruled
(divergence 4 vs `CN-J`)" is therefore not a demo detail: whichever way it
rules, 78 tests move. **And 6b must flip the eight helper defaults with
`Window`'s** or its own measurement repeats arm A's.

**What this says to 7b.** 43 CSS rows. 31 of them are element tests in the
six files this stage pins to `.legacy` (spec §5, lane 3 — which pins 32: the
31 plus `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`,
green in A2 but a "legacy X where proposal Y" pin whose legacy arm is a CSS
answer by its name). The other 12 call no deprecated registrar and are 6b's to
pin or 7b's to retire: `StackElementTests` ×3 and
`TextMeasureTests.aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot`,
`EnvironmentTests.aLocaleChangesNoTextMeasurement`/`dynamicTypeSizeChangesNoTextMeasurement`,
`AnimationTests.everyRegisteringSiteAnimatesItsStyle` (CSS-style, 7);
`TextMeasureTests` ×3 (CSS-text); `FrameDecorationInteractionTests.aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`
and `OuterModifierMatrixTests.everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`
(CSS-structure; the second also reports `box.display.none`).

The full table, one row per red test, arms as each read (p passed, f failed):

**X** (13)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| AXNodeTests | `aLegacySpelledAXListRowAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| AbsoluteOverlayTests | `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| AccessibilityDefaultsTests | `aHiddenListAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| AccessibilityDefaultsTests | `aRootMinHeightOnTheScrollerFixtureAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| LayoutAuthorityTests | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` | B2 f C2 f C3 f B3 f |
| LayoutAuthorityTests | `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` | B2 f C2 f C3 f B3 f |
| ListTests | `aLegacySpelledListRowAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| LoweringContainerTests | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` | B2 f C2 f C3 f B3 f |
| LoweringLeafTests | `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction` | B2 f C2 f C3 f B3 f |
| MeasurePerformanceTests | `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |
| MeasurePerformanceTests | `aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority` | B2 f C2 f C3 f B3 f |
| PresentationLoweringTests | `aPresentationTrapsAProductionProposalFrameNamingItsField` | B2 f C2 f C3 f B3 f |
| TombstoneTests | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` | B2 f C2 f C3 f B3 f |

**D** (2)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| LayoutAuthorityTests | `aFrameAndAWindowDefaultToTheLegacyAuthority` | B2 f C2 f C3 f B3 f |
| LayoutAuthorityTests | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` | B2 f C2 f C3 f B3 f |

**N9** (5)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| NativeBoundaryIntegrationTests | `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` | B2 f C2 f C3 f B3 f |
| NativeBoundaryIntegrationTests | `aPaddingModifierOnAProposalComponentTraps` | B2 f C2 f C3 f B3 f |
| NativeBoundaryIntegrationTests | `aProposalElementInsideALegacyContainerTrapsAtRegistration` | B2 f C2 f C3 f B3 f |
| NativeBoundaryIntegrationTests | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` | B2 f C2 f C3 f B3 f |
| ProposalNodeIDTests | `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` | B2 f C2 f C3 f B3 f |

**RP** (54)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| AXEmitSiteTests | `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` | B2 f C2 f C3 p B3 p |
| AXEmitSiteTests | `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds` | B2 f C2 f C3 p B3 p |
| AXNodeTests | `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds` | B2 f C2 f C3 p B3 p |
| AccessibilityTreeTests | `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` | B2 f C2 p C3 p B3 p |
| AnimationTests | `hoverAndFocusFadeThroughTheSameEffectiveColourPath` | B2 f C2 p C3 p B3 p |
| BackgroundChainTests | `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour` | B2 f C2 f C3 p B3 p |
| BackgroundChainTests | `everyBackgroundPaintingSiteHonoursHoverAndFocus` | B2 f C2 f C3 p B3 p |
| DecorationPaintTests | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `aBorderIsVisibleOverAChildThatFillsTheBox` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `aChainsOuterLayerScopesContainTheLayersInsideIt` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `aFocusRingOutranksAHoverBorderAndABorder` | B2 f C2 f C3 p B3 p |
| DecorationPaintTests | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `clippedAlsoClipsTheHitboxesInsideIt` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` | B2 f C2 p C3 p B3 p |
| DecorationPaintTests | `everyDecorationScopingSiteContainsItsOwnContent` | B2 f C2 p C3 p B3 p |
| DisabledTests | `aClickNeedsTheTargetEnabledAtPressAndAtRelease` | B2 f C2 p C3 f B3 f |
| DisabledTests | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` | B2 f C2 p C3 f B3 f |
| DisabledTests | `aDisabledScrollViewStillScrollsOnTheWheel` | B2 f C2 p C3 p B3 p |
| DisabledTests | `aDisabledTargetIsNeitherHoveredNorPressed` | B2 f C2 p C3 f B3 f |
| DisabledTests | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` | B2 f C2 p C3 f B3 f |
| DisabledTests | `theGateReadsTheEnvironmentValueNotTheModifier` | B2 f C2 p C3 f B3 f |
| EnvironmentTests | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` | B2 f C2 p C3 f B3 f |
| FrameDecorationInteractionTests | `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes` | B2 f C2 p C3 p B3 p |
| FrameDecorationInteractionTests | `aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick` | B2 f C2 p C3 p B3 p |
| FrameDecorationInteractionTests | `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame` | B2 f C2 p C3 p B3 p |
| FrameDecorationInteractionTests | `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` | B2 f C2 p C3 p B3 p |
| FrameDecorationInteractionTests | `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset` | B2 f C2 p C3 p B3 p |
| FrameLoopTests | `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` | B2 f C2 p C3 f B3 f |
| FrameLoopTests | `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize` | B2 f C2 p C3 f B3 f |
| GlyphEmitterTests | `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox` | B2 f C2 p C3 p B3 p |
| GlyphEmitterTests | `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` | B2 f C2 p C3 p B3 p |
| HitRegionTests | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` | B2 f C2 f C3 p B3 p |
| HitRegionTests | `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` | B2 f C2 f C3 p B3 p |
| HitRegionTests | `aContentShapeWithoutAClickHandlerRegistersNothing` | B2 f C2 f C3 p B3 p |
| HitRegionTests | `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse` | B2 f C2 f C3 p B3 p |
| HitRegionTests | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` | B2 f C2 f C3 p B3 p |
| HitRegionTests | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `aClickInsideTheBoundsRunsTheHandler` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `aClickOutsideTheBoundsDoesNotRunTheHandler` | B2 f C2 f C3 p B3 p |
| InputDispatchTests | `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler` | B2 f C2 f C3 p B3 p |
| InputDispatchTests | `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `aNestedHandlerWinsOverItsContainingStackToo` | B2 f C2 f C3 p B3 p |
| InputDispatchTests | `aPressThatLeavesTheElementAndReturnsStillClicks` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` | B2 f C2 p C3 f B3 f |
| InputDispatchTests | `onClickIsLiveOnEveryConformerThatCanRegisterOne` | B2 f C2 p C3 p B3 p |
| InputDispatchTests | `onlyABoxWithAHandlerRegistersAHitbox` | B2 f C2 f C3 p B3 p |
| LayoutAuthorityTests | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` | B2 f C2 p C3 f B3 f |
| OuterModifierMatrixTests | `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` | B2 f C2 p C3 p B3 p |
| OuterModifierMatrixTests | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | B2 f C2 p C3 p B3 p |
| OuterModifierMatrixTests | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` | B2 f C2 p C3 p B3 p |
| PointerStatePaintTests | `aHoveredBoxPaintsItsHoverBackground` | B2 f C2 p C3 f B3 f |
| PointerStatePaintTests | `focusOutranksHoverWhenAnElementIsBoth` | B2 f C2 p C3 f B3 f |

**CE** (6)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ElementLayoutTests | `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree` | B2 p C2 p C3 f B3 p |
| ModifiedElementTests | `addingALayerAtRunTimeResetsTheWrappedElementsState` | B2 p C2 p C3 f B3 p |
| ModifierCompositionProofTests | `aModifierChainRegistersAndPaintsOuterLayersFirst` | B2 p C2 p C3 f B3 p |
| ModifierCompositionProofTests | `stateSurvivesFramesUnderALegacyModifierChain` | B2 p C2 p C3 f B3 p |
| PipelineTests | `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene` | B2 p C2 p C3 f B3 p |
| PipelineTests | `prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases` | B2 p C2 p C3 f B3 p |

**CE+RP** (23)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ComponentTests | `aComponentInsideAComponentFlattensThroughBothLevels` | B2 f C2 p C3 f B3 f |
| ComponentTests | `aComponentsContentFlattensIntoItsParent` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `aHiddenChildTakesNoSpace` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `aNestedLayoutMatchesTheEngineRunDirectly` | B2 f C2 p C3 f B3 p |
| ElementLayoutTests | `aStackCentresOnTheCrossAxisWhereABoxStretches` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `alignItemsAndAlignSelfBothReachTheEngine` | B2 f C2 p C3 f B3 p |
| ElementLayoutTests | `anExplicitAnyElementIsStillAcceptedAsAChild` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `childrenAreRegisteredAndLaidOutInSourceOrder` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `columnStacksOnTheAxisRowDoesNot` | B2 f C2 p C3 f B3 f |
| ElementLayoutTests | `gapIsPerAxisAndTheRowReadsTheHorizontalOne` | B2 f C2 p C3 f B3 f |
| EnvironmentTests | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` | B2 f C2 p C3 f B3 f |
| FrameSizingTests | `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` | B2 f C2 f C3 f B3 p |
| FrameSizingTests | `aLegacyFrameProposesItsWidthToAMeasuredLeaf` | B2 f C2 p C3 p B3 p |
| FrameSizingTests | `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` | B2 f C2 p C3 f B3 p |
| FrameSizingTests | `hiddenAfterASingleChildLegacyFrameStillHidesTheElement` | B2 f C2 p C3 p B3 p |
| HitboxTests | `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame` | B2 f C2 p C3 f B3 f |
| HitboxTests | `aPressThatLeavesTheHitboxAndReturnsStaysActive` | B2 f C2 p C3 f B3 p |
| HitboxTests | `activeIsSetOnMouseDownAndHeldUntilMouseUp` | B2 f C2 p C3 f B3 p |
| HitboxTests | `activeSurvivesAFrameBoundary` | B2 f C2 p C3 f B3 f |
| HitboxTests | `hoverResolvedThroughARealRenderHasNoLag` | B2 f C2 p C3 f B3 p |
| ModifiedElementTests | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` | B2 f C2 p C3 f B3 p |
| ModifiedElementTests | `changingALayersValueKeepsTheWrappedElementsState` | B2 f C2 p C3 f B3 p |
| ModifierCompositionProofTests | `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` | B2 f C2 p C3 f B3 p |

**AV** (5)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| AccessibilityDefaultsTests | `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` | B2 f C2 f C3 f B3 f |
| AccessibilityTreeTests | `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` | B2 f C2 f C3 f B3 f |
| AccessibilityTreeTests | `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient` | B2 f C2 f C3 f B3 f |
| AccessibilityTreeTests | `aHiddenRootPublishesNothing` | B2 f C2 f C3 f B3 f |
| AccessibilityTreeTests | `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` | B2 f C2 f C3 f B3 f |

**RT** (1)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| MeasurePerformanceTests | `aColdFrameCreatesAtMostOneLineBreakTokenizer` | B2 f C2 f C3 f B3 f |

**CSS-structure** (14)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ComponentTests | `aComponentsPaddingWrapsEachTopLevelNode` | B2 f C2 f C3 f B3 f |
| ComponentTests | `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` | B2 f C2 f C3 f B3 f |
| ComponentTests | `aModifierOnAComponentDistributesToEachTopLevelChild` | B2 f C2 f C3 f B3 f |
| ComponentTests | `aTwoMemberComponentsPaddingIsAppliedToEachMember` | B2 f C2 f C3 f B3 f |
| ComponentTests | `chainedFramesRemainConcreteAndNestTheirLayoutNodes` | B2 f C2 f C3 f B3 f |
| ComponentTests | `chainedPaddingAccumulatesOnAComponentAsItDoesOnAnElement` | B2 f C2 f C3 f B3 f |
| ComponentTests | `chainedPaddingCreatesNestedWrappers` | B2 f C2 f C3 f B3 f |
| ComponentTests | `paddingWrapsAnElementAndExpandsItsOuterFootprint` | B2 f C2 f C3 f B3 f |
| ElementLayoutTests | `theBuilderContributesNoNodesOfItsOwn` | B2 f C2 f C3 f B3 f |
| FrameDecorationInteractionTests | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` | B2 f C2 f C3 f B3 f |
| ModifiedElementTests | `aGenericWrapOverAChainIsIdenticalToTheFlatChain` | B2 f C2 f C3 f B3 f |
| ModifiedElementTests | `legacyModifierChainsInferOneConcreteType` | B2 f C2 f C3 f B3 f |
| ModifierCompositionProofTests | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` | B2 f C2 f C3 f B3 f |
| OuterModifierMatrixTests | `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` | B2 f C2 f C3 f B3 f |

**CSS-style** (7)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| AnimationTests | `everyRegisteringSiteAnimatesItsStyle` | B2 f C2 f C3 f B3 f |
| EnvironmentTests | `aLocaleChangesNoTextMeasurement` | B2 f C2 f C3 f B3 f |
| EnvironmentTests | `dynamicTypeSizeChangesNoTextMeasurement` | B2 f C2 f C3 f B3 f |
| StackElementTests | `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct` | B2 f C2 f C3 f B3 f |
| StackElementTests | `stackDefaultsToCentreNotStretch` | B2 f C2 f C3 f B3 f |
| StackElementTests | `stackWritesDisplayAndBothAlignmentFields` | B2 f C2 f C3 f B3 f |
| TextMeasureTests | `aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot` | B2 f C2 f C3 f B3 f |

**CSS-text** (3)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| TextMeasureTests | `aCentringColumnShrinkWrapsItsTextLikeWebKit` | B2 f C2 f C3 f B3 f |
| TextMeasureTests | `aLongLabelInAStretchedColumnWrapsRatherThanOverflowing` | B2 f C2 f C3 f B3 f |
| TextMeasureTests | `aTextPaintsItsBackgroundAndItsGlyphs` | B2 f C2 f C3 f B3 f |

**CSS-frame** (10)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| FrameSizingTests | `aFractionSizeResolvesAgainstItsContainingBlock` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aLegacyFixedFrameDoesNotShrinkAsAFlexItem` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aLegacyFrameAroundAListStillBuildsEveryRow` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `anInfiniteMaximumFillsOnlyWhenBothAxesAreInfinite` | B2 f C2 f C3 f B3 f |
| FrameSizingTests | `theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt` | B2 f C2 f C3 f B3 f |

**CSS-d48** (5)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ComponentTests | `aComponentsWidthStillOverwritesItsMembersDeclaredWidth` | B2 f C2 f C3 f B3 f |
| ComponentTests | `aModifierOnAComponentAppliesInTheOrderItIsWritten` | B2 f C2 f C3 f B3 f |
| ComponentTests | `heightAloneDistributesToEachTopLevelChild` | B2 f C2 f C3 f B3 f |
| ComponentTests | `widthAloneDistributesToEachTopLevelChild` | B2 f C2 f C3 f B3 f |
| ComponentTests | `widthAndHeightComposeOnAChainedModifier` | B2 f C2 f C3 f B3 f |

**CSS-pin** (2)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ContainerIntegrationTests | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` | B2 f C2 f C3 f B3 f |
| ContainerIntegrationTests | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | B2 p C2 f C3 f B3 f |

**CSS-box** (2)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| ElementLayoutTests | `marginEdgesAreNotTransposed` | B2 f C2 f C3 f B3 f |
| ElementLayoutTests | `paddingEdgesAreNotTransposed` | B2 p C2 p C3 f B3 p |

**RP+CSS-frame** (1; UNATTRIBUTED in the design, attributed in §7.2)

| file | test | arms (A2 is red in every row) |
|---|---|---|
| FrameDecorationInteractionTests | `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` | B2 f C2 f C3 f B3 f |

## 5. The callers' own tests, read through the arms

A caller's test that is **green in A2** ran under the flipped default with its
custom element reported as a 0×0 native leaf and still passed: its assertions
do not depend on that element's geometry, so a `requestNativeLeaf` of the
element's declared size (one node, as the reported leaf is one node) keeps
them. A test **green in B2 but red in A2** needs the element's size, which a
sized native leaf gives — **except** where the element must be stretched by a
legacy parent, which only the `Box` lowering's `LoweredItem` record gets
(`paddingEdgesAreNotTransposed`: its probe is stretched to 376×104 in a padded
`Box`; B2's `lowerLegacyNode` records an item and is stretched, a native leaf
records none and would not be — record §23 X2), so that one is CSS-box, not a
re-spelling. The spec's §5 applies this per test; each re-spelled test the
lanes find red is a finding, recorded with its arm and pinned with its measured
cause rather than re-asserted.

**The windows among them build production frames** (`Window` never sets
`reportsUnlowerableFields`), so under `.proposal` an unlowerable field traps and
truncates the suite. In A2 every caller test green there reported
`customElement.*` and nothing else (the `SIXA-UNLOWERABLE` lines between its
`started` and `passed` lines), which the re-spelling removes: the entry
measurement is the "fixtures already measured to report nothing" that
`makeFakeWindow`'s doc comment accepts in place of a pre-flight.

## 6. Hazards the design leaves for the lanes

- **A native leaf inside a legacy container traps under the legacy
  authority** (`SA-G`; `LR-T` lifts it only under `.proposal`). A re-spelled
  element therefore takes its test to `.proposal` explicitly, unless its whole
  tree is native (a native root is laid out by the kernel under either
  authority — `computeRootLayout` chooses by the root).
- **Each way to undo a re-spelling traps, and each way to undo a pin traps**:
  a re-spelled element put back on `pass.frame.requestNode` under `.proposal`
  hits the backstop (`aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`); a
  re-spelled test put back on `.legacy` hits `SA-G`
  (`aProposalElementInsideALegacyContainerTrapsAtRegistration`); a pinned test
  flipped to `.proposal` hits the backstop. None is silent, and none can be
  taken as an in-process mutation without truncating the run — which is why
  the pins' mutations (spec §7) run over instrument `0d02538`'s non-fatal
  traps. The one silent case is a re-spelled test whose tree is all native: its
  authority does not matter to it, by construction.
- **`makeFakeWindow`'s `.legacy` default** stays `.legacy` in this stage
  (production is legacy until 6b); a pinned window test passes `.legacy`
  explicitly anyway, so 6b's flip of that default cannot reach it.

## 7. Critic round 1 (design) — `LR-DA`

On `feat/engine-stage-6a` at `0d2a5a3`, 2026-09-23. Each check below was run,
not read; every scratch edit was restored and `git status --short` read clean
of source changes after each.

### 7.1 The caller count, with the deprecation in

Both attributes added to `Passes.swift` in a scratch (message `SIXA`), then
`swift build --build-system native --build-tests`: 0 `error:`, and exactly
**58** distinct `warning: '…' is deprecated: SIXA` lines, in **30** compiled
files (`PipelineTests` 7, `StateTests` and `ListTests` 4, `EnvironmentTests` 3,
two in each of `AXNodeTests`, `ComponentTests`, `ElementGroupTrapTests`,
`EnvironmentTrapTests`, `FocusTests`, `FrameClockTests`, `IdentityTests`,
`LayoutAuthorityTests`, `MeasurePerformanceTests`, `ModifiedElementTests`,
`ModifierCompositionProofTests`, `ProposalNodeIDTests`, `ScrollRoutingTests`,
`TombstoneTests`, one in each of the other twelve), none in `Sources/`; the
only other `warning:` was SwiftPM's notice. With the five typecheck-guard files
that is §1's 35 files and 58 compiled sites. **No caller is missed by §1's
grep.** (The task brief's "about 89" is the raw grep including `Sources/`'s 14
lines on `frame.request…` and declarations; 89 − 14 − 5 doc comments − 4 on
`pass.frame.` = 66.) Outside `Sources/`/`Tests/` the only hits are
`docs/probes/modifier-composition-skeletons/*.swift`, standalone files no
target compiles.

### 7.2 The unattributed row, measured

`FrameDecorationInteractionTests`' `render` helper given
`layoutAuthority: .proposal` in a scratch, the test run filtered (a measurement
of one test's values, not a suite claim), restored: the fixture's root is
`Row { subject; 1×1 marker }` in a 200×200 window, which answers 61×40 and is
centred (`CN-J`) at (70, 80) where the legacy root sits at (0, 0). Read:

| arm | expected (legacy) | under `.proposal` | reading |
|---|---|---|---|
| control | `[0 0 60x40]` | `[70 80 60x40]` | offset by the root only |
| after | `[10 10 40x20]` | `[80 90 40x20]` | offset by the root only |
| before | `[25 15 10x10]` | `[95 95 10x10]` | offset by the root only |
| flexible `.frame(minWidth: 80, maxWidth: 100)` | `[5 5 70x10]` | `[55 95 90x10]` | the layer is **100** wide, not `FR-E`'s 80 ("a finite maximum clamps but never grows into the proposal"), and offset |

and the three click counts 0 (the clicks land at legacy coordinates). So the
row is **RP + CSS-frame**: C2/C3 could not turn it green because its fourth arm
is the legacy frame's CSS answer, which no placement arm touches. Owners: 6b for
the root, 7b for the `FR-E` arm. It is not a caller of the deprecated pair and
stage 6a does not pin it.

### 7.3 Instrument I0 did not apply; re-spelled and its control measured

The spec said `git cherry-pick 0d02538`. `git show 0d02538 | git apply --check`
at `0d2a5a3` (tree = `b3c29b9`): **`error: patch failed:
Sources/MetalUI/Frame.swift:1533`** — `0d02538` was written over arm A, whose
`noteUnlowerable` carries a `SIXA-UNLOWERABLE` print that `b3c29b9` does not.
The same two edits re-made against `b3c29b9` are
`docs/probes/stage-6a-instrument-I0.patch` (applies cleanly).

**I0 alone**, applied, built (0 `error:`), full unfiltered suite: **`Test run
with 1640 tests in 3 suites failed after 77.232 seconds with 32 issues`**, the
reddened set exactly the 13 X tests of §4 (`aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`,
`aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`,
`aHiddenListAbortsAProductionProposalFrame`,
`aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`, the four
`aLegacySpelled…AbortsAProductionProposalFrame`,
`anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`,
`aPresentationTrapsAProductionProposalFrameNamingItsField`,
`aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority`,
`aRootMinHeightOnTheScrollerFixtureAbortsAProductionProposalFrame`,
`aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop`). The design's M3g and
2.3 predicted reddened sets that omitted these; every I0 mutation is now read
against this control.

### 7.4 The probe's separating arm

`docs/probes/swift-deprecated-witness-silence.sh` re-run: its three recorded
lines byte for byte. Its silent arm (`use2.swift`) had no arm differing only in
the attribute, so "silent because of the attribute" was unseparated from
"silent because of the shape". Added `use3.swift` = `use2.swift` with the
witness's attribute deleted: **warns once in each language mode**
(`use3.swift:4:46: warning: 'requestNode(style:children:)' is deprecated`). The
header carries both.

### 7.5 What was attacked and stands

- **Production does not move.** The design touches `Sources/` only in two
  attributes, one `owningStage` literal and doc comments; the scratch builds
  above confirm the attribute alone changes nothing but warnings.
- **The R move off the production authority** (66 tests now run `.proposal`, so
  they stop pinning the legacy path). `grep -rln 'lowersToProposal\|layoutAuthority' Sources`
  names only the registration sites (`Box`, `Stack`, `Text`, `ModifiedElement`,
  `ScrollView`, `ListRows`, `Component`, `Deferred`), `LoweringState`,
  `LayoutAuthority`, `Passes`, `Window` (which passes it on) and `Frame` (the
  backstop, the presentation check); the state table, environment, focus,
  frame clock and identity code read no authority. What an R test gives up is
  the legacy **kernel** under its custom element, which the 97 goldens and the
  pinned tests keep. Accepted (`LR-DA` item 7).
- **`typecheckFile` sees warnings**: `TypecheckResult.messages` keeps
  ` warning: ` lines (`Typecheck.swift`), so guard 3.2 can read the
  deprecation.
- **The exit test's trap half** reads a message built from `owningStage`
  (`LayoutAuthority.swift:127`), and no existing test asserts the literal
  `stage 6a` (grep: three doc comments quoting recorded output, one comment in
  `LoweringCorpusTests`), so `LR-CW` reddens only 3.1.
- **`PipelineTests`' native row**: its frames are 400×100, the root's own
  answer, so `CN-J`'s centring places it at (0, 0) and the legacy literals hold;
  `twoCopiesOfOneElementDoNotShareLayoutState` asserts stamps, not positions.
- **The exit tests re-spelled R** (`ElementGroupTrapTests`,
  `EnvironmentTrapTests`) read their abort message off stderr, so a trap for a
  different reason under `.proposal` would redden them rather than pass them.

