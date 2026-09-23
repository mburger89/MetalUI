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
Critic round 1 is §7; the lanes append from §8. **Lane 1 (L, Dep, G) ran:
§8, `LR-DB`** — it corrected §1's census from 66 sites (8 in fixture strings)
to **67 (9)**.

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
  **Corrected by lane 1 (§8.3, `LR-DB`): 67 sites, 9 in fixture strings** —
  `ProposalNodeIDCompileGuards:155`, guard 4's negative
  (`pass.requestNativeFrame(child: pass.requestNode(…))`), shares its line with
  a `requestNative` call, which this census's `grep -v requestNative` dropped.
  The 58 compiled sites stand (§7.1 counted them by warning, not by grep).

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
grep.** *(True of the 58 compiled sites, which is what this check measured;
the fixture-string count was one short — §8.3.)* (The task brief's "about 89" is the raw grep including `Sources/`'s 14
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


## 8. Lane 1 — mechanical fixtures (L, Dep, G) — `LR-DB`

On `feat/engine-stage-6a`, 2026-09-23. The change is `c95dc0d` (tests only; no
`Sources/` line). Every mutation below was taken on top of it: the file copied
to the scratchpad, edited, `swift build --build-system native --build-tests`,
**full unfiltered** `swift test --build-system native --no-parallel`, the copy
restored, `git status --short` read empty. Every run printed `FR-J no-argument
frame: succeeded=`, so the guards ran.

### 8.1 What moved

| disp. | sites | what |
|---|---|---|
| **L** | 10 call sites in 9 fixtures | `AXListLeaf`, `ListTests.Row` (its node and its leaf), `ExcursionRow`, `StatefulListRow`, `LoweredProbeLeaf`, `ContextProbe`, `ScrollContextRecorder`, `ScrollRoutingTests.HitboxProbe`, `LayoutDifferential.ProbeLeaf`: the legacy branch's `pass.requestNode(`/`pass.requestLeaf(` → `pass.frame.requestNode(`/`pass.frame.requestLeaf(`. (The spec's "L 10 fixtures" counts sites.) |
| **Dep** | 4 | `LegacySpelledAXListLeaf`, `LegacySpelledRow`, `LegacySpelledExcursionRow`, `LegacySpelledStatefulListRow`: `requestLayout` marked `@available(*, deprecated, message: "spelled with the deprecated legacy registrar on purpose: it is the subject of <its exit test>, which reads the customElement trap (stage 6a, LR-CV)")`; bodies byte-identical |
| **G** | **9** fixture strings | `PhaseSeparationTests` 2 (the negative's literal → `"requestNativeLeaf"`, `LR-CU` item 6), `ErasureCompileGuards` 1, `ProposalNodeIDCompileGuards` **4** (guards 1, 2, 4, 6), `FrameSizingCompileGuards` 1, `ModifiedElementCompileGuards` 1 |

No `#expect`/`#require` line changed except PhaseSeparation's literal
(`git diff b3c29b9 c95dc0d -- Tests | grep -E '^[-+].*#(expect|require)'` returns
that one pair). One `#expect` message string is now loosely worded and was left
alone because it is on an assertion line: guard 1's `"a marker conformer
registering a legacy node must not compile"` — the fixture now registers a
native leaf's untyped id; the doc above the guard says so.

**Red-first does not apply to this lane**: it adds no test. Each re-spelled
guard's red is its mutation (§8.4), taken on the re-spelled fixture.

### 8.2 Suite, build, pixels

- `c95dc0d`: **`Test run with 1640 tests in 3 suites passed after 77.177 seconds`**,
  one summary line; 0 `error:`; the only `warning:` SwiftPM's notice under
  `--build-system native`; `swift build --build-tests` (default build system):
  `Build complete!`, 0 `error:`, 0 `warning:`.
- Guard prints on the green run: `MC-A solver budget 1000: positive
  succeeded=true`, negative `succeeded=false` with "unable to type-check this
  expression in reasonable time" — **the solver-budget guard's positive still
  passes at 1000 and its negative still fails** with the re-spelled `Leaf`;
  `FR-J no-argument frame: succeeded=true deprecations=2`; the six
  `PROPOSAL-NODE-ID GUARD` pairs read as before (1 liar false; 2 mint false /
  read true; 4 legacy false / native true; 6 liar true / without false).
- Goldens: `git diff --name-only b3c29b9 c95dc0d -- 'Tests/**/*.json'` empty.
- **Twelve-image offscreen comparison** (`docs/probes/demo-pixels/compare.sh
  <scratch> b3c29b9 c95dc0d`): the controls at their recorded values (1048576,
  1030498, 210027, 0, 1048576, chrome pair 0, distinct 544 / 216, indicator
  rects 0), and **`differing=0` / `scene identical` in all twelve**.
- Lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — no
  window capture (owed by lane 3 only when unlocked, spec §9).

### 8.3 Finding: a ninth fixture-string caller

`ProposalNodeIDCompileGuards.swift:155`, `aNativeRegistrarRejectsALegacyChild`'s
negative fixture, `_ = pass.requestNativeFrame(child: pass.requestNode(style:
Style(), children: []))`. §1's census grep excluded lines matching
`requestNative`, and this call shares its line with one. It is a fixture string
(no build warning, so §7.1's warning count could not see it), but it matters
twice: the guard's `show` prints the child `swiftc`'s messages into the test
log, so after the deprecation the log would carry a `warning: … is deprecated`
line; and at stage 9's deletion the negative would still fail — for "no member
`requestNode`", not for the typed child parameter, so its `messages.contains`
reddens for the wrong reason. Re-spelled G:
`pass.requestNativeFrame(child: pass.requestNativeSpacer().layoutNodeID)` — the
untyped `LayoutNodeID` the guard is about, from the registrar that survives.
Mutated as **M1i** below. A grep that does not drop such lines:
`grep -rnE '[A-Za-z_]+\.request(Node|Leaf)\(' Tests | grep -vE 'frame\.request(Node|Leaf)\(' | grep -v '///'`
— after `c95dc0d` it returns 48 lines: the 5 Dep lines of this lane and the 43
lanes 2 and 3 own.

### 8.4 Mutations

| id | mutation (file, spelling as applied) | full-suite line | reddened — every test |
|---|---|---|---|
| 1.1 | **none possible** (`LR-X`): an L fixture's legacy branch back on `pass.requestNode(` is, under the legacy authority, exactly the call `Passes.swift:43–48`/`66–72` forward to, and that branch is unreachable under the proposal one | — | — |
| **M1a** | `Passes.swift`, `PaintPass` gains `public func requestNativeLeaf(measure: @escaping ProposalMeasureFunction) -> ProposalNodeID { ProposalNodeID(frame.requestNativeLeaf(measure: measure)) }` | `1640 … failed after 77.718 seconds with 2 issues` | `registeringALayoutNodeDuringPaintDoesNotCompile` (`PhaseSeparationTests.swift:93` `!result.succeeded`, `:95` `messages.contains("requestNativeLeaf")`) |
| **M1b** | `Passes.swift:94`, `LayoutPass.requestNativeLeaf` `public` → **`package`**. The spec's `internal` does not build: `DemoContent.swift:983: error: 'requestNativeLeaf' is inaccessible due to 'internal' protection level` (`MetalUIDemoContent` is another module). `package` keeps the package building and hides the member from a fixture compiled without `-package-name` | `1640 … failed after 78.428 seconds with 9 issues` | `registeringALayoutNodeDuringLayoutCompiles` (`PhaseSeparationTests.swift:106`), `aStructCanConformToElementObject` (`ErasureCompileGuards.swift:169`), `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` (`FrameSizingCompileGuards.swift:106`), `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (`:175`), `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`ModifiedElementCompileGuards.swift:123`), `aNestedModifiedElementCannotBeSpelled` (`:166`), `aProposalGroupWhoseEntryPointsDisagreeStillCompiles` (`ProposalNodeIDCompileGuards.swift:284`), and two guards that already spelled `requestNativeLeaf` at `b3c29b9`: `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` (`ProposalLayoutCompileGuards.swift:159`), `aFixedAndAFlexibleFrameDimensionCannotBeCombined` (`:292`). Not reddened: guard 1 (`aMarkerConformer…`) — its fixture is rejected either way and still names the typed requirement |
| **M1c** | `AnyElement.swift`: `ElementObject: AnyObject`. **As spelled it does not build** (`AnyElementBox` is a struct conformer), so the mutant also makes `AnyElementBox` a `final class` and drops `mutating` from the three requirements and the box's three methods — the smallest edit that builds with a class-bound protocol | `1640 … failed after 78.288 seconds with 3 issues` | `aStructCanConformToElementObject` (`ErasureCompileGuards.swift:169` `result.succeeded`), `twoCopiesOfOneElementDoNotShareLayoutState` (`PipelineTests.swift:309` `inPrepaint.values == [1, 2]`, `:310` `inPaint.values == [1, 2]` — the class box shares one `LayoutState`, fact 2) |
| **M1d** | `ProposalElementGroup.swift`: a trapping default `requestProposalGroupLayout` on **`extension ProposalElementGroup where Self: Element`** (record §10's V-G1b spelling). The unconstrained extension the spec names does not build: `DemoContent.swift:966: error: type 'GridPreviewCell' does not conform to protocol 'ProposalElementGroup'` (ambiguous with the existing defaults) | `1640 … failed after 78.319 seconds with 2 issues` | `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` (`ProposalNodeIDCompileGuards.swift:69` `!result.succeeded`, `:71` the typed-requirement message) |
| **M1e** | `ProposalNodeID.swift:61`, `init(_:)` → `public init(_:)` | `1640 … failed after 78.574 seconds with 1 issue` | `aProposalNodeIDCannotBeMintedOutsideMetalUI` (`ProposalNodeIDCompileGuards.swift:96`, the `#require` that mint and read disagree) |
| **M1f** | `ProposalNodeIDCompileGuards.swift`, `disagreeingGroupSource`: `let typedEntry = false && withTypedEntry ? …` (the positive fixture loses its typed entry — guard 6's doc) | `1640 … failed after 79.054 seconds with 1 issue` | `aProposalGroupWhoseEntryPointsDisagreeStillCompiles` (`:284`, the `#require`) |
| **M1i** | `Passes.swift`: `LayoutPass` gains `public func requestNativeFrame(child: LayoutNodeID, width: Double? = nil) -> ProposalNodeID` (guard 4's doc) | `1640 … failed after 90.800 seconds with 1 issue` | `aNativeRegistrarRejectsALegacyChild` (`ProposalNodeIDCompileGuards.swift:169`, the `#require`) |
| **M1g-A** | `FrameLayer.swift:225–226`, `ElementGroup`'s deprecated `frame()` deleted (record §14's mutation A) | `1640 … failed after 79.393 seconds with 2 issues` | `theNoArgumentFrameIsADeprecatedNoOpOnBothPaths` (`FrameSizingCompileGuards.swift:106` `result.succeeded`, `:108` `deprecations == 2`; print `succeeded=false deprecations=1`, as record §14 read) |
| **M1g-B** | `NativeModifiedContent.swift:300`, the proposal flexible `frame`'s `idealWidth:` label → `idealWidthM1gB` (record §14's mutation B) | `1640 … failed after 90.388 seconds with 2 issues` | `everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload` (`FrameSizingCompileGuards.swift:175`), `anIdealDimensionOnTheLegacyFrameTraps` (`FrameSizingTests.swift:293`, `.success` → `.signal(SIGTRAP)`) — record §14's pair |
| **M1h** | `ModifiedElement.swift`: the first `MC-A` design's three concrete overloads (`padding(_: Pixels)`, `padding(_: Edges<Length>)`, `frame(width:height:)`, each `-> ModifiedElement<Content>`, working bodies) in an `extension ModifiedElement` | `1640 … failed after 78.653 seconds with 1 issue` | `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`ModifiedElementCompileGuards.swift:123`, the `#require`; print `positive succeeded=false … unable to type-check this expression in reasonable time`). `aNestedModifiedElementCannotBeSpelled` stays green: its doc names a different mutation, taken next |
| **M1h′** | `ModifiedElement.swift`: a single concrete **nesting** `padding(_: Pixels) -> ModifiedElement<Self>` (lane 2 test 1's mutation, named in `aNestedModifiedElementCannotBeSpelled`'s doc) | `1640 … failed after 78.005 seconds with 5 issues` | `aNestedModifiedElementCannotBeSpelled` (`:166`, the `#require`), `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` (`:123`), `legacyModifierChainsInferOneConcreteType` (`ModifiedElementTests.swift:289`, `:294`), `decorationSubstitutionReachesTheElementOnBoxAndStack` (`AnimationTests.swift:1216` `baseline.layers == 2`) |

Every re-spelled guard reddened under its own named mutation, on the re-spelled
fixture. **Three of the spec's spellings could not be applied as written**
(M1b `internal`, M1c alone, M1d unconstrained — each a build error, quoted
above); each was taken in the nearest spelling that builds, recorded as
applied (`LR-DB`).

### 8.5 Handed on

- Lanes 2 and 3 own the 43 remaining non-Dep lines of §8.3's grep. Lane 3's gate
  grep (spec §7 3.5, `grep -rn 'pass\.requestNode(\|pass\.requestLeaf(\|layoutPass\.requestNode(' Tests`)
  has no `-v requestNative` and so already keeps a line like guard 4's; only a
  census that excludes `requestNative` lines misses it.
- M1b's reddened set shows the G fixtures now depend on `requestNativeLeaf`
  being public, as seven other guards already did — the dependency stage 9
  leaves standing.
