# §38 — Engine replacement, stage 6a: custom elements, and tests that are about CSS answers

**Renumbered from §30 to §38 at merge with `master` (2026-09-23):** PRs
#11–#20 (`64c5271` — portable line breaking, lines emission, content sizes,
font resolver, portable core/layout, text seam, render seam, SDL platform)
were pushed first and keep §30–§37, so every `§30` this track wrote was
repointed to `§38` and the file renamed
(`docs/record/30-engine-replacement-stage-6a.md` →
`38-engine-replacement-stage-6a.md`); the precedent is record §23 §8 and the
§25, §27 and §29 headers. Master's own `§30` citations (line breaking) were
left alone, and so was one historical mention below — the Docs-pass list's
"(the §30 row)", which describes this file as it stood before the merge.
Counts re-taken on the merged tree: **1688 / 97 / 78, `Test run with 1688 tests in 3 suites passed` (1686 + 2)** (`CLAUDE.md` "Build and
test").

Plan task 7, stage 6a (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 6a,
rulings `LR-R`, `FR-I`, §8). Design:
`docs/superpowers/specs/2026-09-23-engine-stage-6a-design.md`. Rulings
`LR-CT`…`LR-CZ` (design) in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md`. Probe:
`docs/probes/swift-deprecated-witness-silence.sh` (a compiler probe, no
SwiftUI claim). Branch `feat/engine-stage-6a` from `b3c29b9`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-6a`.

**Status, 2026-09-23 (PDT): lanes 1–3 landed; stage closed at `e531260` (§11); Record phase complete (§20); branch checker `ok` (§21).** §1–§6 are the design's measurements —
the stage's **entry measurement** is §4. Every one was taken on scratch
commits (`9ccc0d8`…`59b63ad`, listed in §2) that `a1b6edf` reverts to
`b3c29b9`'s tree exactly (`git diff --quiet b3c29b9 a1b6edf` succeeds); they
stay in the history so a later reader can re-run an arm by checking it out.
Critic round 1 is §7; the lanes append from §8. **Lane 1 (L, Dep, G) ran:
§8, `LR-DB`** — it corrected §1's census from 66 sites (8 in fixture strings)
to **67 (9)**. **Lane 2 (R, the P-only files) ran: §9, `LR-DC`** — no
re-spelled test was red; the one Dual element was not dual. **Lane 3 (the
Dual files, the deprecation, the exit test) ran: §10, `LR-DD`** — the gate
closed at `e531260` with 1642 tests and 0 `warning:`; M3g reddened exactly the
46 predicted pins. **Lane 3's verification moved one R test to P (§10.7,
`LR-DE`)**: FR-P's test 2.10, which under `.proposal` could not see its own
mutation — lane 3 is 11 R and 47 P (30 CSS). **The stage's exit criteria are
read in §11.**

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
| **AV** | `hidden()` / `display: none` reported (`box`/`modifierLayer.display.none`) — `LR-AV` defers it to "task 7 before stage 9" with **no stage number**, and `owningStage` names stage 2, which is closed | **6b**, a prerequisite of its flip (`LR-DA` item 5; the design read "unassigned — 6b must assign it", which critic round 1 ruled a deferral with no owner) | 5 |
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
`hidden()` (no owner at design time; **6b's** since `LR-DA` item 5), one is unattributed (RP + CSS-frame since §7.2). 6b's "root placement ruled
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


## 9. Lane 2 — authority-independent tests (R) and the P-only files — `LR-DC`

On `feat/engine-stage-6a`, 2026-09-23. The change is `e683975` (tests only; no
`Sources/` line), on top of lane 1's `0f79da6`. Every mutation below was taken
on top of it: the files copied to the scratchpad, edited,
`swift build --build-system native --build-tests`, **full unfiltered**
`swift test --build-system native --no-parallel`, the copies restored (and I0
reverted with `git apply -R`), `git status --short` read empty. Every run
printed `FR-J no-argument frame: succeeded=`.

### 9.1 What moved

| disp. | element (file) | spelling | tests that lay it out, and their authority |
|---|---|---|---|
| R | `leafNode` for `CounterElement`, `ConditionalReadElement`, `ReflectOnceElement`, `TwoOrdinalElement` (`StateTests`) | `requestNativeLeaf` 10×10 | 6: `stateSurvivesAcrossFramesForTheSameElement`, `reflectionRunsOncePerTypeNotOncePerElement` (`.proposal`, a `Box` root); `aRootElementsStateIsSeededAndSurvives`, `aStateThatIsNeverReadInAFrameIsStillNotSwept`, `stateOrdinalsAreTheMirrorIndexNotThePositionAmongStateChildren`, `aStateWriteDuringTheFramesOwnRenderIsNotSwallowedByClearingAfterward` (all native: the element is the root) |
| R | `CountingElement` (`StateTableTests`, shared with `IdentityTests`) | 10×10 | `aSharedTableCarriesStateAcrossFramesWhileAPerFrameTableWouldNot`, `anElementThatStopsBeingProducedLosesLivenessButKeepsItsValue`, `anAnonymousElementHoldsStateAcrossFrames` (native roots); **and eleven `IdentityTests` over `Row { CountingElement… }`, each now `.proposal`** (§9.3) |
| R | `StampedStateProbe`, `ClickableStateProbe` (`IdentityTests`) | 0×0 (`Style()`) | `oneElementValuePlacedTwiceDoesNotShareItsState`, `aHandlerWritesTheStateOfTheOccurrenceThatRegisteredIt` (`.proposal`) |
| R | `EnvRecorder` 10×10, `PropertyRecorder` 1×1 (`EnvironmentTests`) | the file's `frame` helper gains `authority:` (default `.legacy`), as does `counts` | 13, each `.proposal`: the twelve that render them (two through `makeFakeWindow(layoutAuthority: .proposal)`) and `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants`' reader case only (its writer-only cases stay legacy) |
| R | `RootWriter`, `ScopedReader` (`EnvironmentTrapTests`) | 0×0 | the two exit tests' helpers `.proposal` |
| R | `EnabledRecorder` (`DisabledTests`) | 10×10 | `disabledComposesAsAnAndAndARawWriteOverridesIt` `.proposal` |
| R | `FocusReader`, `SelfFocuser` (`FocusTests`) | 20×20 | the three windows `.proposal` |
| R | `RequestingBox`, `TimestampRecorder` (`FrameClockTests`); `FrameCounter` (`FrameLoopTests`) | 0×0 (their `style` is never set) | `everyElementInOneFrameSeesTheSameTimestamp` `.proposal` (a `Row`); the other two native roots |
| R | `Probe` (`GlyphEmitterTests`) | 0×0 | native root |
| R | `ContentSwapper` (`ElementGroupTrapTests`) | `pass.frame.requestNativeOverlay(children:)` | the six `renderSwapper` exit tests: the helper `.proposal` |
| R | `StateProbe` (`ElementGroupTrapTests`) | a leaf of the size its `style` declares (`declaredSize`, 10×10 from `.width`/`.height`) | the two duplicate-id tests `.proposal` |
| R | `ProbeRow` (`PipelineTests`) | **one `ProposalLayout` (`ProbeRowLayout`) over two sized leaves** — §9.4 | 4, all native |
| R | `StampedProbe`, `MutatingProbe`, `IdentifiedProbe` 30×10; the hand-built root | leaves; the root `pass.frame.requestNativeLinearStack(…, axis: .horizontal, spacing: 0)` | `twoCopiesOfOneElementDoNotShareLayoutState`, `theBoxCarriesEveryPhasesMutationForwardToTheNextPhase`, `paintWritesItsStatesBackSoASecondPaintSeesTheFirst`, all native |
| **P-6b** | `ClickCounter` (`EnvironmentTests`) | `pass.frame.requestNode` | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`, both windows `.legacy` — **not a Dual** (§9.3) |
| P-CSS | `LegacyMark` (`ContainerIntegrationTests`) | `pass.frame.requestNode`; the file's `render` gains `authority:` | the legacy arm of the three CN-P pins `.legacy` |
| P-6b | `HitboxProbe` (`HitboxTests`) | `pass.frame.requestNode` | the five tests `.legacy` |
| P-9 | `OrphanLegacyNode`, `StatefulLegacyLeaf` (`ProposalNodeIDTests`); `LegacyNodeUnderAProposalMarker` (`NativeBoundaryIntegrationTests`) | `pass.frame.requestNode` | the two tests `.legacy` (three frames and one) |

**59 tests lay out a lane-2 R element** — 42 under an explicit `.proposal`,
17 over an all-native tree that names no authority — and **11 are pinned**
(3 P-CSS, 6 P-6b, 2 P-9: the spec's count). Each pinned test's doc comment
carries `Pinned to the legacy authority by stage 6a (<class>, record §38 §4).`
and each re-spelled element's a line saying so. No `#expect`/`#require` line
changed (`git diff 0f79da6 e683975 -- Tests | grep -E '^[-+].*#(expect|require)'`
is empty). After the change §8.3's census grep returns **15** lines: the 5 Dep
lines and lane 3's 10.

**Red-first does not apply**: the lane adds no test. The spec's rule for a
re-spelled test found red (record it, pin it P with its cause) had nothing to
act on — **no R test was red** on the first full run.

### 9.2 Suite, build, pixels

- `e683975`: **`Test run with 1640 tests in 3 suites passed after 81.133 seconds`**,
  one summary line; 0 `error:`; the only `warning:` SwiftPM's notice under
  `--build-system native`; `swift build --build-tests` (default build system):
  `Build complete!`, 0 `error:`, 0 `warning:`.
- Goldens: `git diff --name-only b3c29b9 e683975 -- 'Tests/**/*.json'` empty.
- **Twelve-image offscreen comparison** (`docs/probes/demo-pixels/compare.sh
  <scratch> b3c29b9 e683975`): controls at their recorded values (1048576,
  1030498, 210027, 0, 1048576, chrome pair 0, distinct 544 / 216, indicator
  rects 0), and **`differing=0` / `scene identical` in all twelve**.
- Lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — no
  window capture.

### 9.3 Findings against the spec's §5 lane-2 rows

1. **`ClickCounter` is not a Dual.** The spec gave it an R test,
   `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex`; that test
   renders `EnvRecorder` (it is in the `EnvRecorder` row too), and
   `ClickCounter` is laid out by exactly one test, the P-6b one. So it is
   P-6b alone, `pass.frame.requestNode`, with no `lowersToProposal` branch —
   and lane 2 has **no** Dual element. `LR-DA` item 3's rule (a Dual's R test
   passes `.proposal`) has nothing to apply to here.
2. **`CountingElement` has eleven consumers the spec did not list.** It is
   defined in `StateTableTests` and shared with `IdentityTests` (its doc says
   so), where ten tests put it under a legacy `Row` and one
   (`twoErasedSiblingsDoNotShareOneStateEntry`, listed under the probes' row)
   under `Row { AnyElement(…) }`. A native leaf under a legacy `Row` traps
   under the legacy authority (`SA-G`, §6), so each of those tests' `Frame`
   passes `.proposal` — none was red in A2 (§4 lists no `IdentityTests` row),
   and none was red here. `anAnonymousElementHoldsStateAcrossFrames` renders it
   as the root and names no authority.
3. **Four listed tests lay out no lane-2 element**:
   `aStateWriteWakesAPausedDisplayLinkThroughTheOnWriteHook` (renders `Box()`),
   `childrenOfDistinctUnnamedParentsDoNotCollide` (no render),
   `theErasureForwardsTheElementsIdentity` (constructs two `AnyElement`s, lays
   out neither), and the Dual's R row above. They are untouched.
4. **`ProbeRow` cannot be a native frame over a stack.**
   `eachFrameOwnsItsOwnStateSoNothingLeaksBetweenFrames` asserts
   `first.tree.nodeCount == 3` ("two children plus the root"); frame + stack +
   two leaves is 4. §9.4.
5. **The spec's CE prediction for `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene`
   reads the container, not the leaves.** In A2 the whole custom row — its
   root included — was reported as one 0×0 leaf, so the root's 400×100 was
   lost; the re-spelling's container answers 400×100 by itself. The test reads
   the root's size and `rects.count == 2` (a 0×0 `fill` still emits a rect),
   so it depends on the container's answer, not the leaves' sizes (M2a / M2a′
   below).

### 9.4 `ProbeRow`'s native spelling

`ProbeRowLayout: ProposalLayout` answers a fixed 400×100 and places each
subview at its own `.unspecified` answer, left to right from `bounds.x`, at
`bounds.y` — the legacy fixed-size flex row's answer (children at (0, 0)
100×40 and (100, 0) 60×20, both at the top — the test's own literals), in one
container node. The root is 400×100 in a 400×100 frame, so `CN-J`'s centring
places it at (0, 0) and the absolute literals hold. The tree is all native.

### 9.5 Mutations

| id | mutation (file, spelling as applied) | full-suite line | reddened — every test |
|---|---|---|---|
| **M2a** | the 13 lane-2 native-leaf sites with a non-zero size (`DisabledTests` 1, `EnvironmentTests` 2 — the two recorders only, not the pre-existing `NativeEnvRecorder` — `FocusTests` 2, `PipelineTests` 5, `StateTableTests` 1, `StateTests` 1, and `ElementGroupTrapTests.declaredSize` returning 0×0) answer 0×0; the sites already 0×0 unchanged | `1640 … failed after 81.133 seconds with 5 issues` | **`prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases` alone** (`PipelineTests.swift:134`, `:135` first child's size; `:139` second's x; `:141`, `:142` its size). The spec predicted it **and** `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene`; the second reads the container's answer (§9.3 item 5). No non-CE test reads a lane-2 element's size |
| **M2a′** | `ProbeRowLayout.sizeThatFits` answers 0×0 (the half of A2's loss M2a cannot reach) | `1640 … failed after 80.248 seconds with 6 issues` | `prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases` (`:132`, `:133`, `:139`, `:140` — the 0×0 root is centred at (200, 50), so the children's origins move), `paintReceivesTheRootBoundsAndEmitsIntoTheFramesScene` (`:154`, `:155`, the root's size) — **the two CE rows, together** |
| **M2b** | `ProbeRowLayout` places each child centred on the cross axis (`y: bounds.y + (bounds.height - size.height) / 2`), the spec's "alignment `.center`" in this spelling | `1640 … failed after 91.202 seconds with 2 issues` | `prepaintSeesBoundsTheEngineResolvedBetweenTheFirstTwoPhases` alone (`:133` first.origin.y, `:140` second.origin.y). The spec predicted both CE rows; `paintReceives…` reads no child position, in either spelling |
| **I0 control** | `git apply docs/probes/stage-6a-instrument-I0.patch` on `e683975`, nothing else | `1640 … failed after 81.086 seconds with 32 issues` | exactly the 13 X tests of §7.3, no difference |
| **M2c** | over I0, every `.legacy` lane 2 wrote flipped to `.proposal`: **15** sites (`EnvironmentTests` 2 windows, `ContainerIntegrationTests` 4 `render` calls, `HitboxTests` 1 `Frame` + 4 windows, `ProposalNodeIDTests` 3 frames, `NativeBoundaryIntegrationTests` 1) | `1640 … failed after 77.714 seconds with 45 issues` | against the control, **exactly the predicted 10**: `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` (`EnvironmentTests.swift:368`, the first arm's `try #require(log.readings.last == 2)` — its two clicks at legacy coordinates miss the centred root), `hoverResolvedThroughARealRenderHasNoLag` (`HitboxTests.swift:331`), `activeIsSetOnMouseDownAndHeldUntilMouseUp` (`:443`), `aPressThatLeavesTheHitboxAndReturnsStaysActive` (`:464`, 3 issues), `activeSurvivesAFrameBoundary` (`:536`, 2), `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame` (`:597`), `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (`ProposalNodeIDTests.swift:197`, arm b's `nodeCount == 6`: the backstop's 0×0 native leaf replaced the orphan subtree), `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (`NativeBoundaryIntegrationTests.swift:166`, the abort is no longer "contains a legacy node"), `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` (`ContainerIntegrationTests.swift:1498`), `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` (`:1523`); **`aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` green**, as A2 read it; the 13 control reds all still red. 21 `SIXA-WOULD-TRAP:` lines in the log. The P-9 "may stay green" caveat did not bite: both P-9 tests reddened |

**No mutation of an R test's authority** (spec §7, record §6): each way back
traps, loudly, at a pinned site.

### 9.6 Handed on

- Lane 3 owns the census grep's 10 remaining lines, the deprecation, 3.1/3.2.
- `IdentityTests` now runs under the proposal authority with no legacy twin.
  What it gives up is the legacy kernel under `CountingElement`; identity is
  assigned by the element groups, which read no authority (§7.5's grep), and
  the legacy `Row` still lowers through stage 2's container lowering. Stage 6b
  flips the default; nothing here changes when it does.


## 10. Lane 3 — layout-answer tests (Dual, P, R), the deprecation, the exit test — `LR-DD`

On `feat/engine-stage-6a`, 2026-09-23, on top of lane 2's `d306d97`. Three
commits, in the order spec §7 fixes: **`5822f60`** the callers moved (tests
only, green, 0 `warning:`); **`ab7d76f`** tests 3.1 and 3.2 red-first;
**`e531260`** the two attributes and `owningStage` — the commit that closes the
gate. Every mutation below was taken on top of `e531260`: the file copied to the
scratchpad, edited, `swift build --build-system native --build-tests`, **full
unfiltered** `swift test --build-system native --no-parallel`, the copy
restored (I0 reverted with `git apply -R`), `git status --short` read empty.
Every run printed `FR-J no-argument frame: succeeded=`.

### 10.1 What moved

| disp. | element (file) | spelling | tests, and their authority |
|---|---|---|---|
| **Dual** | `Probe` (`ElementLayoutTests`) | `pass.lowersToProposal ? declaredSizeNativeLeaf(style, pass) : pass.frame.requestNode(style:children:)` | R `.proposal`: 3 (4 frames). P `.legacy`: 8 CE+RP, 1 CSS-structure, 2 CSS-box (14 frames) |
| **Dual** | `Leaf` (`ComponentTests`) | as `Probe` | R `.proposal`: `aComponentContributesNoLayoutNodeOfItsOwn`, `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`. P `.legacy`: 2 CE+RP, 8 CSS-structure, 5 CSS-d48 (21 frames) |
| R | `CounterLeaf` (`ComponentTests`) | `requestNativeLeaf` 10×10 | `stateInsideAComponentsContentIsAlsoSeeded`, `aNamedComponentsContentKeepsItsStateWhenASiblingIsInsertedBeforeIt`, `.proposal` |
| **Dual** | `Mark` (`FrameSizingTests`) | as `Probe` | ~~R `.proposal`: `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`~~ — P `.legacy` (CSS-frame) since `b504e9f`, §10.7. P `.legacy`: 4 CE+RP, 10 CSS-frame (57 helper calls, 4 frames/windows), and 2.10's 3 `widthInRow` calls |
| **Dual** | `LayerLeaf` (`ModifiedElementTests`) | as `Probe` | R `.proposal`: `anIDAfterAChainsLastWrapperNamesTheOutermostLayer` (3 `observe`), `addingALayerAtRunTimeResetsTheWrappedElementsState` (window). P `.legacy`: 2 CE+RP (windows), `aGenericWrapOverAChainIsIdenticalToTheFlatChain` (8 `observe`) |
| P-CSS | `ChainLeaf` (`ModifiedElementTests`) | `pass.frame.requestNode` | `legacyModifierChainsInferOneConcreteType` `.legacy` |
| **Dual** | `CountingLeaf` (`ModifierCompositionProofTests`) | as `Probe` | R `.proposal`: `everyModifierWrapperDelegatesEachPhaseExactlyOnce` (its `counts` frame, every arm), `stateSurvivesFramesUnderALegacyModifierChain`, `aModifierChainRegistersAndPaintsOuterLayersFirst` (windows). P `.legacy`: `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` (2 frames), `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (8 `observe`) |
| P-CSS | `BoxWithoutAnimated` (`ModifierCompositionProofTests`) | `pass.frame.requestNode` | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` `.legacy` |
| **Dep** | `CustomNodeElement`, `CustomLeafElement` (`LayoutAuthorityTests`) | body byte-identical; `requestLayout` `@available(*, deprecated, message: "…(stage 6a, LR-CV)")` | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| **Dep** (new) | `DeprecatedRegistrarRow`, and its oracle `InternalRegistrarRow` (`LayoutAuthorityTests`) | spec §8 | 3.1 |

`declaredSizeNativeLeaf(_:_:)` is one internal helper in `ElementLayoutTests`,
shared by the five Dual elements: a native leaf answering the pixel size its
`Style` declares, 0 on an `auto` axis, and a **precondition** on any other
dimension (a fraction or percentage), so an R test cannot silently get a wrong
size (§10.5, M3g). **The five files' shared helpers take the authority as a
required argument** — `FrameSizingTests`' `render`, `widthInRow` and
`nodeCount`, and both `observe` helpers — not as a defaulted one as lane 2's
`render`/`frame` helpers do: stage 6b flips "the eight test helpers' `.legacy`
parameter defaults" (spec §10), and a required argument is one no sweep of
defaults can reach.

**46 P tests** (17 CE+RP owned by 6b, 29 CSS owned by 7b — exactly spec §5's
lane-3 count; **47, 30 CSS, since §10.7**), each with the doc line `Pinned to the legacy authority by stage
6a (<class>, record §38 §4).`, the class read off §4 (`CE+RP`, `CSS-structure`,
`CSS-box`, `CSS-frame`, `CSS-d48`). **12 R tests** run under an explicit
`.proposal` (**11 since §10.7**). No `#expect`/`#require` line changed (`git diff d306d97 e531260 --
Tests | grep -E '^[-+].*#(expect|require)'` returns only 3.1's and 3.2's new
lines).

**After the change** the gate grep (spec §7 3.5, `grep -rn
'pass\.requestNode(\|pass\.requestLeaf(\|layoutPass\.requestNode(' Tests`,
doc lines dropped) returns 14 lines: the seven Dep fixtures' (`AXNodeTests`,
`TombstoneTests`, `ListTests` ×2, `MeasurePerformanceTests`,
`LayoutAuthorityTests` ×2 for `CustomNodeElement`/`CustomLeafElement`, ×5 for
`DeprecatedRegistrarRow`) and **two lines of guard 3.2's fixture string**, which
the spec's "returns only Dep fixtures' lines" did not foresee: the guard's
subject is a caller of the pair, spelled in a string the suite never compiles.

Outside lane 3's files, doc comments only: the three recorded trap quotes in
`AXNodeTests`, `TombstoneTests` and `MeasurePerformanceTests` (each quotes a
2026-09 stderr ending `(plan task 7, stage 6a)`) gain a sentence that the
message names stage 9 since `LR-CW` — their assertions read the part before the
stage, so they did not redden — and `LoweringCorpusTests`' "`CountingLeaf` …
reports `customElement.requestLeaf` until stage 6a" is corrected to
`requestNode` (it never called `requestLeaf`).

### 10.2 Red-first (`ab7d76f`)

`Test run with 1642 tests in 3 suites failed after 79.564 seconds with 3
issues`, exactly:

- `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes`
  (`LayoutAuthorityCompileGuards.swift:93`, the `#require` that the legacy
  caller and the control disagree on `is deprecated`: both fixtures compiled,
  `succeeded=true`, with empty messages);
- `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`
  at `LayoutAuthorityTests.swift:317` and `:328` — the child aborted with
  `MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestLeaf
  has no proposal lowering (plan task 7, stage 6a); …` (and `requestNode`),
  where the test reads `(plan task 7, stage 9)`.

**The legacy half passed**, as its doc comment says it must, and the run
confirmed the hand-derived literals before they were relied on: the leaf at
(0, 0) 30×20 and the node at (30, 0) 40×10, equal to the internal-registrar
oracle's.

### 10.3 Suite, build, pixels

- `e531260`, after `swift package clean`: `swift build --build-system native
  --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
  **`Test run with 1642 tests in 3 suites passed after 80.846 seconds`**, one
  summary line, the only `warning:` in the log SwiftPM's notice. `swift build
  --build-tests` (default build system): `Build complete!`, 0 `error:`, **0
  `warning:`**. **The gate holds with the deprecation in** — spec §6.1's last
  row.
- **The gate's red** (spec §7 3.5), a scratch over `e531260`: `ChainLeaf`'s
  `pass.frame.requestNode(` put back to `pass.requestNode(` → exactly one
  diagnostic, `ModifiedElementTests.swift:129:15: warning:
  'requestNode(style:children:)' is deprecated: a custom element registers
  through requestNativeLeaf(measure:) or a ProposalLayout; …`. Restored.
- Guard 3.2's print on the green run: `legacy: succeeded=true` with both
  `'requestLeaf(style:measure:)' is deprecated: …` and
  `'requestNode(style:children:)' is deprecated: …`; `control: succeeded=true`,
  no message. It ran in 0.45 s, a real `swiftc` (CLAUDE.md's tell).
- Counts: **1642 tests** (1640 + 3.1 + 3.2), **97 goldens** (`git diff
  --name-only b3c29b9 e531260 -- 'Tests/**/*.json'` empty), **78 guards**
  (`LayoutAuthorityCompileGuards` 1 → 2; the per-file sum of CLAUDE.md's list is
  76 in `Tests/MetalUITests` plus `UnitSafetyTests`' 2 in `Tests/MetalUICoreTests`).
- **Twelve-image offscreen comparison** (`docs/probes/demo-pixels/compare.sh
  <scratch> b3c29b9 e531260`): the controls at their recorded values (1048576,
  1030498, 210027, 0, 1048576, chrome pair 0, distinct 544 / 216, indicator
  rects 0), and **`differing=0` / `scene identical` in all twelve**.
- Lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — **no
  window capture** (spec §9 owes it only unlocked).

### 10.4 Findings against the spec's §5 lane-3 rows

1. **Two listed R tests lay out no lane-3 element**, as lane 2's §9.3 item 3
   found for its rows: `anEmptyComponentContributesNoNodes` (listed under
   `CounterLeaf`; renders `Row { Nothing() }` and `Row { EmptyGroup() }`) and
   `contentIsMaterializedExactlyOncePerFrame` (listed under `Leaf`; renders a
   `Box` over an empty component). Both untouched. Lane 3's R count is **12** (**11** after §10.7),
   not the spec's 14.
2. **M3e reddens one test the spec did not name**:
   `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, whose custom-element
   arms read the `customElement.requestNode` report under diagnostics. And it
   reddens only 3.1's **node-first** arm: M3e (as the spec spells it) skips
   `requestNode`'s report alone, so the leaf-first child still aborts at
   `requestLeaf`'s.
3. **M3g truncated as first taken, at a harness decision of this lane**:
   `declaredSizeNativeLeaf`'s precondition fired at
   `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`, a
   `Mark(…).width(fraction: 1)` flipped to `.proposal` (`Precondition failed: a
   stage 6a Dual fixture's proposal branch answers only pixel sizes; got
   length(MetalUICore.Length.percent(1.0))`, 988 tests reported). Retaken with
   the precondition softened to answer 0 in the scratch (§10.5); the truncation
   is itself the measurement that the precondition is live. Practice: *a harness
   decision is a mutation site*.
4. **The file helpers' authority is required, not defaulted** (§10.1) — a
   spelling the spec left open.

### 10.5 Mutations

| id | mutation (file, spelling as applied) | full-suite line | reddened — every test |
|---|---|---|---|
| **M3a** | `Passes.swift`, the `@available(*, deprecated, …)` line above `requestNode(style:children:)` deleted | `1642 … failed after 93.874 seconds with 1 issue`; build: 0 deprecation warnings | `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes` (`LayoutAuthorityCompileGuards.swift:97`, `'requestNode(style:children:)' is deprecated`) |
| **M3b** | the same above `requestLeaf(style:measure:)` | `1642 … failed after 79.821 seconds with 1 issue` | `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes` (`:99`, `'requestLeaf(style:measure:)' is deprecated`) |
| **M3c** | `Passes.swift`, the legacy `requestNode` forwarder `frame.requestNode(style: Style(), children: children)` | `1642 … failed after 78.456 seconds with 2 issues` | 3.1's legacy half alone (`LayoutAuthorityTests.swift:302`: leaf 30×**100**, stretched by a root that lost `alignItems`; `:304`: node (30, 0) **0×100**) |
| **M3d** | the legacy `requestLeaf` forwarder `frame.requestLeaf(style: style) { _, _ in SizeD(width: 0, height: 0) }` | `1642 … failed after 84.010 seconds with 2 issues` | 3.1's legacy half alone (`:302`: leaf 0×0; `:304`: node at x **0**) |
| **M3e** | the proposal branch of `requestNode` returns `frame.requestNode(style: style, children: children)` in place of `frame.unlowerable(…)` (the backstop then aborts with its site-less message) | `1642 … failed after 90.210 seconds with 7 issues` | 3.1's node-first arm (`:328`), `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` (`:160`), the four `aLegacySpelled…AbortsAProductionProposalFrame` (`AXNodeTests.swift:666`, `TombstoneTests.swift:189`, `ListTests.swift:954`, `MeasurePerformanceTests.swift:888`), and `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (`:517`) — §10.4 item 2 |
| **M3f** | `LayoutAuthority.swift`, `.customElement` → `"6a"` | `1642 … failed after 80.246 seconds with 2 issues` | 3.1's trap half alone (`:317`, `:328`) |
| **M3h** | `declaredSizeNativeLeaf` answers 0×0, and `ComponentTests.CounterLeaf` 0×0 | `1642 … failed after 78.561 seconds with 5 issues` | **exactly the four CE rows**: `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree` (`ElementLayoutTests.swift:919`, the `!=` of the two frames' rects: both 0×0), `addingALayerAtRunTimeResetsTheWrappedElementsState` (`ModifiedElementTests.swift:567`, the three clicks miss a 0×0 leaf), `stateSurvivesFramesUnderALegacyModifierChain` (`ModifierCompositionProofTests.swift:749`, `taps` read 0), `aModifierChainRegistersAndPaintsOuterLayersFirst` (`:980` the padding-ring click ran nothing, `:983` the leaf click ran `outer`) |
| **I0 control** | `git apply docs/probes/stage-6a-instrument-I0.patch` on `e531260`, nothing else | `1642 … failed after 79.216 seconds with 36 issues` | the 13 X tests of §7.3 **and 3.1** (its two trap arms, `:309`/`:317`, `:320`/`:328`) — spec §7's predicted control from lane 3's red-first commit on |
| **M3g** | over I0, every `.legacy` lane 3 wrote in `5822f60` flipped to `.proposal` — **117** sites (`ElementLayoutTests` 14, `ComponentTests` 21, `FrameSizingTests` 61, `ModifiedElementTests` 11, `ModifierCompositionProofTests` 10), **plus** `declaredSizeNativeLeaf`'s precondition softened to answer 0 (§10.4 item 3; without it the run truncates) | `1642 … failed after 78.797 seconds with 168 issues` | against the control, **exactly the predicted 46** — the 17 CE+RP and 29 CSS P tests of §10.1, no more and no fewer; the 14 control reds all still red. 14 `SIXA-WOULD-TRAP:` lines (7 `modifierLayer.style`, 5 `modifierLayer.display.none`, 2 the backstop) |

**No mutation of an R test's authority** (spec §7, §6): each way back traps,
loudly, at a pinned site.

**`declaredSizeNativeLeaf`'s answer is pinned only at 0×0.** The R tests assert
identity, phase counts, state and hit targets, never the Dual leaf's geometry:
the verifier's **VC** (`declaredSizeNativeLeaf` answering its declared width
**+ 7**, run in one suite with M3a and M3d) reddened only the tests M3a and M3d
target (3.2, and 3.1's legacy half) — no R test. So a wrong but nonzero native
answer is invisible to lane 3's R tests; only M3h's 0×0, which makes the CE
rows' clicks miss and C-3's two rects compare equal, is seen. The precondition
above stops a **fraction** reaching the proposal branch; it does not make an R
test see a wrong pixel size, and §10.1's "so an R test cannot silently get a
wrong size" is to be read as *a wrong size from a non-pixel dimension*.

### 10.6 Handed on

- **To the Record phase**: CLAUDE.md's counts (1642 / 97 / 78;
  `LayoutAuthorityCompileGuards` 2; `typecheckFile` helpers 37 → 38, one
  `LayoutAuthority`→ two), and the sentence that the public
  `requestNode`/`requestLeaf` are deprecated and trap naming stage 9; records
  §03/§04/§05/README; the plan's 6a row; the parent spec's status.
- **To 6b**: the 17 CE+RP pins of this lane (23 with lane 2's six), and the
  eleven R tests now under `.proposal` (twelve until §10.7) — nothing moves for
  them when the default flips.
- **To 7b**: the 30 CSS pins of this lane (33 with lane 2's three; 29 and 32
  until §10.7). One of them, FR-P's test 2.10, is **green** under the flipped
  default: 7b retires it with `FrameSpec.style()`, not because a flip reddened
  it.
- **To 9**: the five Dual elements' legacy branches, `ChainLeaf`,
  `BoxWithoutAnimated`, the seven Dep fixtures and 3.1's legacy half, with the
  pair.

### 10.7 Verification fix: FR-P's test 2.10 is a CSS pin, not an R test — `LR-DE`

The lane-3 verifier found that `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`
(`FrameSizingTests`, test 2.10, ruling `FR-P`), which lane 3 moved to
`.proposal` as an R test because it lays out a `Text` and no `Mark` of its own
(the `Mark` in it is `widthInRow`'s sibling), **cannot see the mutation it is
named for** under the proposal authority. `FR-P` is the legacy
`FrameSpec.style()`'s choice of an axis-named `minSize` over `flexShrink = 0` —
a CSS answer the proposal lowering never reads. The verifier's **VA** (both
fixed axes' `minSize` writes in `FrameLayer.swift` replaced by `flexShrink = 0`)
over `92914cb` read `Test run with 1642 tests in 3 suites passed`: after lane
3's re-spelling nothing in the suite pinned `FR-P`, and the test's doc comment
("This test reddens where 2.2 does not") was false. Its **VA2** (the same with
the test's three `widthInRow` calls set back to `.legacy`) failed it alone.

**Fix, `b504e9f`**: the three calls pass `.legacy`, and the doc comment gains
the §5 line `Pinned to the legacy authority by stage 6a (CSS-frame, record §38
§4).` with the reason. No assertion changed. Class **P-CSS-frame**, owned by
7b. Suite on `b504e9f`: `Test run with 1642 tests in 3 suites passed after
78.591 seconds`, 0 `error:`, the only `warning:` SwiftPM's notice, `FR-J
no-argument frame: succeeded=` printed.

**VA re-run on `b504e9f`** (`FrameLayer.swift` copied to the scratchpad; in
`FrameSpec.style()` the two lines `style.minSize.width = .length(.pixels(width))`
and `style.minSize.height = .length(.pixels(height))` each replaced by
`style.flexShrink = 0`; full unfiltered suite; the copy restored, `git status
--short` empty): **`Test run with 1642 tests in 3 suites failed after 78.953
seconds with 1 issue`** — `aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`
alone, at `FrameSizingTests.swift:942`, its `try #require(framed <
unconstrained)`: under `flexShrink = 0` the framed text reads its full
unwrapped width, as wide as the unconstrained arm, so the precondition that
the row is over-constrained fails before the `#expect`. `FR-P` is pinned again,
by this test alone.

**It is the one lane-3 P test M3g cannot see.** It was green under §4's flipped
default (so §4 never listed it) and is green under `.proposal` now, so M3g's
"exactly the 46" stands as taken, and the 47th P test is pinned by VA instead.
Lane 3's counts become **11 R** (12 − 1) and **47 P: 17 CE+RP, 30 CSS** (29 +
1); lanes 2 and 3 together hand 7b **33** CSS pins.

**The same shape elsewhere, checked by reading, not by running a mutation.**
Lane 1 moved no R test (L, Dep, G only). Lane 2's R tests (§9.1), by subject:
`@State` seeding and retention, environment reads and their work counts, the
disabled gate, focus, the frame clock, glyph emission, the element-group traps
and the pipeline's phase write-back — none is about a `Style` a legacy site
lowers. Lane 3's other ten R tests' doc comments name mutations in
`GlobalElementID` (`Element.requestGroupLayout`'s parent), `ModifiedElement`'s
content cursor, content id, `animated` calls and per-phase delegation, handler
registration and fill order, and `ModifiedElement.elementID` — code read under
either authority. 2.10 was the only R test whose named mutation is in a legacy
lowering.

## 11. Stage close

| exit criterion (parent spec §4.1 row 6a) | reading |
|---|---|
| the public `LayoutPass.requestNode`/`requestLeaf` deprecated | `e531260`; guard 3.2 sees both attributes from a plain import |
| every in-repo caller moved in the same change | 0 in `Sources/` at `b3c29b9`; the 67 test sites moved by lanes 1–3 (L 10, G 9, R, P, Dual), the rest Dep; §10.1's gate grep |
| **0 `warning:`** with the deprecation in place | both build systems, after `swift package clean` (§10.3); one caller left behind → exactly one warning |
| `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` | green; red-before (trap half) §10.2; M3c–M3f each redden it |
| the flipped-default classification table recorded as the entry measurement | §4 (153 reds), attributed in §7.2 |
| production behaviour unmoved | twelve `CN-R` images 0 differing at every lane; `Sources/` diff is two attributes, one `owningStage` literal, doc comments |
| suite count | 1640 → **1642**, the two added tests; goldens 97 unmoved; guards 77 → 78 |
| lane 3's classification after verification | 11 R, 47 P (17 CE+RP, 30 CSS): FR-P's test 2.10 moved R → P-CSS-frame at `b504e9f`, its mutation VA red again (§10.7) |

## 12. What landed — the stage

- **Two attributes and one literal, in `Sources/`, nothing else.**
  `Passes.swift`'s public `LayoutPass.requestNode(style:children:)` and
  `requestLeaf(style:measure:)` are each marked
  `@available(*, deprecated, message: …)`, bodies byte-identical; a custom
  element that still calls them under the proposal authority now traps
  naming **stage 9**, not stage 6a (`LayoutAuthority.swift`'s
  `owningStage` for `.customElement`, `"6a"` → `"9"`, `LR-CW`). `Frame`'s
  internal `requestNode`/`requestLeaf` stay undeprecated — every
  production site already called them, not the public pair (`LR-R`'s
  premise was stale at `b3c29b9`, §1).
- **Every in-repo test caller of the public pair moved**: 67 sites in 35
  files (58 that would each print one build warning, 9 inside typecheck
  fixture strings a child `swiftc` compiles). Six dispositions (`LR-CU`):
  **R** re-spelled onto `requestNativeLeaf`/a `ProposalLayout`, its test run
  under `.proposal` (lane 2: 59 tests over R elements; lane 3: 11 after
  `LR-DE`); **P-CSS** (32, one moved from R at `b504e9f`) / **P-6b** (23) /
  **P-9** (2) pinned to `.legacy` through the internal, undeprecated
  `Frame.requestNode`/`requestLeaf`, each test's doc comment gaining the §5
  line; **Dual** elements (6, one — `ClickCounter` — found not actually
  dual, `LR-DC`) branching on `pass.lowersToProposal`; **L** (10 sites in 9
  pre-existing dual-branch fixtures) whose legacy branch is now spelled
  through `pass.frame.` — identical by construction under `.legacy`
  (`LR-X`); **Dep** (6, plus the new exit fixture) kept on the deprecated
  pair on purpose, `requestLayout` itself marked deprecated, measured
  silent under both Swift 5 and 6 mode (`docs/probes/swift-deprecated-witness-silence.sh`,
  `LR-CV`); **G** (9 typecheck-guard fixture strings) re-spelled onto
  `requestNativeLeaf`/`requestNativeSpacer`.
- **The exit test and its guard, new**:
  `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`
  (`LayoutAuthorityTests`) renders a fixture through both the deprecated
  public pair and the internal oracle under `.legacy` (equal, non-zero,
  distinct rects) and through the public pair alone under production
  `.proposal` (traps, naming `customElement.requestLeaf`/`requestNode`,
  "stage 9"); `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes`
  (`LayoutAuthorityCompileGuards`, `typecheckFile`) confirms a plain-import
  caller of the deprecated pair still compiles and is warned, where a
  control calling only `requestNativeLeaf` is not.
- **The entry measurement** (`LR-CT`): the default authority and the eight
  test-helper `.legacy` parameter defaults flipped together, diagnostics on,
  read through five arms (§2). All **153** reds of that flip are classified
  (§4) and handed on as this stage's own record of what stage 6b and stage
  7b inherit — not a demo detail, since more than half the flip (RP 54 +
  CE+RP 23 + RP+CSS-frame's root arm) is root placement alone.
- **The gate**: 0 `warning:` on both build systems with the deprecation in
  place, the deprecation landing last, in the commit that moves the last
  caller (`e531260`); one caller left behind prints exactly one
  `warning: '…' is deprecated` (measured, §10.3).
- **Verification found one more move**: `FR-P`'s test 2.10
  (`aSingleAxisFixedFrameDoesNotPinTheAxisItDidNotDeclare`) was re-spelled R
  by lane 3 but cannot see its own named mutation (a legacy `FrameSpec.style()`
  choice) once run under `.proposal`; reclassified **P-CSS-frame**, owned by
  7b (`LR-DE`, `b504e9f`). Lane 3's final split is **11 R, 47 P** (17
  CE+RP, 30 CSS).

## 13. Tests per file

1640 at `b3c29b9` → **1642** (+2). Guards 77 → **78**, goldens 97, both
otherwise unchanged.

| file | change | count |
|---|---|---|
| `LayoutAuthorityTests.swift` | `CustomNodeElement`/`CustomLeafElement` → Dep; new `DeprecatedRegistrarRow`/`InternalRegistrarRow` fixtures and exit test 3.1 | +1 |
| `LayoutAuthorityCompileGuards.swift` | new guard 3.2, `typecheckFile` | +1 |
| `Passes.swift`, `LayoutAuthority.swift` | two `@available` attributes, one `owningStage` literal, doc comments (`Sources/`) | 0 |
| the other **33** files of spec §5 | a caller's disposition changes (L/Dep/G/R/P/Dual); no `@Test` added or removed, no `#expect`/`#require` line touched except `PhaseSeparationTests`' one negative-message literal (`LR-CU` item 6) and the new authority arguments | 0 |

`typecheckFile`'s helper count moves with guard 3.2: 37 → **38**
(`LayoutAuthority`'s share 1 → 2; CLAUDE.md's "40 and 37" becomes "40 and
38").

## 14. Red runs, in one place

- **The entry measurement is not a red-first**: it is the stage's baseline
  table, arm A2, 153 reds classified (§2, §4), attributed by the
  separating arms B2/C2/C3/B3 and by the critic round's measurement of the
  unattributed row (§7.2).
- **Lane 1**: red-first does not apply (no test added, §8.1); each
  re-spelled guard's own mutation is its red (§8.4).
- **Lane 2**: red-first does not apply (no test added); **no re-spelled (R)
  test was found red** on the first full run (§9.1) — the practice's
  "record it, pin it P" rule had nothing to act on.
- **Lane 3**: 3.1 and 3.2 written red-first (`ab7d76f`): **3 issues** — the
  guard's `#require` that the two fixtures disagree on `is deprecated`
  (both silent pre-deprecation), and 3.1's two trap arms (the child aborted
  naming "stage 6a", where the test reads "stage 9") — while 3.1's legacy
  half passed on arrival, confirming the hand-derived literals before they
  were relied on (§10.2).
- **Instrument I0's own control** (a re-derivation of the design's
  `0d02538`, which did not apply at `b3c29b9`, §7.3) reads **exactly the 13
  X tests** at every lane it was taken (plus 3.1's trap half from lane 3's
  red-first commit on) — every I0-based mutation below is read as the
  difference against this control, not against a green suite.

## 15. Mutations, in one place

Lane 1: M1a–M1i (§8.4, including the re-spelled M1g-A/B and M1h/M1h′ from
records §14 and lane 2's original design); one check, 1.1, has **no possible
mutation** — an L fixture's legacy branch put back on `pass.requestNode(` is,
under `.legacy`, exactly the call the forwarder makes, and unreachable under
`.proposal` (`LR-X`, recorded as such rather than chased).

Lane 2: M2a (13 sites), M2a′ (the container half M2a could not reach), M2b
(§9.5); I0 control; M2c (15 `.legacy` sites flipped, exactly the predicted
10 reddened, `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`
green as A2 read it).

Lane 3: M3a/M3b (the two attributes, each alone), M3c/M3d (the legacy
forwarders' arguments), M3e (the proposal forwarder's report skipped —
reddened one test the spec did not name, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`,
and only 3.1's node-first arm), M3f (`owningStage` reverted), M3h (the five
Dual leaves' shared helper and `CounterLeaf` answer 0×0 — exactly the four
CE rows); I0 control; M3g (117 `.legacy` sites flipped, **exactly the
predicted 46**, with `declaredSizeNativeLeaf`'s precondition softened in the
scratch to avoid truncating at the first fraction-sized `Mark`, §10.4 item
3 — a harness decision that is itself a mutation site, per practice).

**Verification's own mutations** (§10.7): **VA** (both fixed axes'
`minSize` writes in `FrameLayer.swift` replaced by `flexShrink = 0`) over
the landed tree read **green** — the tell that nothing in the suite still
pinned `FR-P` after lane 3's re-spelling; **VA2** (the same, with 2.10's
three calls set back to `.legacy` in the same scratch) read red **alone**,
proving 2.10 the missing pin; the fix restores it, and **VA re-run on the
fixed tree** reddens 2.10 alone again. **VC** (`declaredSizeNativeLeaf` + 7
on the width, run together with M3a/M3d and separately) reddens no R test
either time — the practice's "a wrong nonzero answer is invisible" finding,
narrowing §10.1's "cannot silently get a wrong size" to sizes from a
non-pixel dimension (§10.5).

**Green mutations, each explained**: lane 1's 1.1 (`LR-X`, above). Lane 3's
2.10 was found **green** under M3g's full flip (§10.4 item 1 → §10.7): the
correct reading was not "this R test's mutation must redden it" but "this
test was never an R test" — the classification error, not the mutation,
was the finding.

## 16. Demo comparisons

Every lane's twelve-image offscreen comparison
(`docs/probes/demo-pixels/compare.sh <scratch> b3c29b9 <lane commit>`) reads
every control at its recorded value (1048576, 1030498, 210027, 0, 1048576,
chrome pair 0, distinct 544 / 216, indicator rects 0) and **`differing=0` /
scene identical in all twelve**, at the design/critic round, lane 1
(`c95dc0d`), lane 2 (`e683975`) and lane 3 (`e531260`). The lock probe read
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at every one of
those measurements, so `docs/probes/window-capture/capture.sh` was never
run and no real-window capture exists for this stage — not owed for
acceptance, since no legacy path changed and the offscreen twelve already
read 0 (spec §9).

## 17. Hazards

- **`declaredSizeNativeLeaf`'s answer is pinned only at 0×0** (§10.5, `VC`):
  lane 3's R tests assert identity, phase counts, state and hit targets,
  never a Dual leaf's geometry, so a wrong but nonzero pixel answer is
  invisible to them. Its precondition against a non-pixel (fraction/
  percentage) dimension is a live, load-bearing trap (§10.4 item 3), not
  redundant with that gap.
- **Five files' shared test helpers take the layout authority as a
  required argument, not a defaulted one** (`FrameSizingTests`' `render`,
  `widthInRow`, `nodeCount`; both `ModifiedElementTests`/
  `ModifierCompositionProofTests` `observe` helpers): stage 6b's "flip the
  eight helper defaults with `Window`'s" cannot reach these — a required
  argument names its authority at every call site, so 6b edits calls, not
  defaults, wherever these five files are touched.
- **A naive caller census can miss a real call site sharing a line with a
  `requestNative` one**: `ProposalNodeIDCompileGuards.swift:155`'s fixture
  string was dropped by `grep -v requestNative`; the corrected grep is
  `grep -rnE '[A-Za-z_]+\.request(Node|Leaf)\(' Tests | grep -vE 'frame\.request(Node|Leaf)\(' | grep -v '///'`
  (§8.3). The gate's own grep (spec §7 3.5) has no such `-v` and already
  keeps such a line, so only a *count* of callers was at risk, not the
  gate.
- **A regression in the proposal forwarder's report can widen past its own
  exit test**: M3e (skip `requestNode`'s report, call `frame.requestNode`
  directly) reddened `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`
  in addition to every test the spec named, because that guard reads the
  same per-site report under diagnostics (§10.4 item 2).
- **The design's instrument commit did not apply outside its own arm**:
  `git cherry-pick 0d02538`/`git apply` of it fails at `b3c29b9`, because
  `0d02538` was authored over arm A's non-fatal-trap variant of
  `noteUnlowerable`, which `b3c29b9` does not have. The re-derived patch is
  committed at `docs/probes/stage-6a-instrument-I0.patch` (§7.3) —
  re-applying `0d02538` itself against a clean tree will fail the same way.
- **The existing CI hazards are untouched**: `AuthorityCoverage.expected`
  stays 82 across fifteen files (3.1/3.2 are not parameterised scenarios
  and record no coverage); the roll call's cross-file-order dependency, the
  `AccessibilityDefaultsTests` recording-order hazard and the
  `…unconsumed`-traps-a-`Window`-test hazard are all unchanged by this
  stage.

## 18. Deferred, each with an owner

| item | owner |
|---|---|
| root placement (divergence 4 vs `CN-J`): 78 of the flip's reds (RP 54, CE+RP 23, RP+CSS-frame's root arm 1), including the 23 P-6b tests this stage pins (17 lane 3 + 6 lane 2) | 6b |
| the eight test-helper `.legacy` parameter defaults, flipped with `Window`'s | 6b |
| `hidden()` / `display: none` under `.proposal` (5 AV rows, no stage named by `LR-AV`) | 6b, as a prerequisite of its own flip |
| the two D tests and three N9 exit tests read at the default authority | 6b pins or rewrites |
| `FR-E`'s legacy flexible-frame arm of the RP+CSS-frame row (`aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox`) | 7b, after 6b rules the root |
| 33 CSS pins (32 element tests plus `FR-P`'s 2.10) and 12 non-caller CSS rows named in §4 | 7b |
| the two P-9 tests, the seven Dep fixtures (plus 3.1's), the L fixtures' legacy branches, the six Dual elements' legacy branches, `LoweringSite.customElement`, and the internal `Frame.requestNode`/`requestLeaf` pair itself | 9 (deletes the legacy authority) |
| the real-window capture | owed whenever the screen is next unlocked against this branch; not owed for acceptance (no legacy path changed, offscreen twelve read 0) |
| CLAUDE.md, AGENTS.md, records §03/§04/§05/README, the plan's 6a row, the parent spec's status | the Record phase (§20, below) |

## 19. For the integrator

- **Decisions doc**: next unused `LR-DF` (`LR-CT`…`LR-DE` used: design
  `LR-CT`…`LR-CZ`, critic round 1 `LR-DA`, lane 1 `LR-DB`, lane 2 `LR-DC`,
  lane 3 `LR-DD`, verification `LR-DE`).
- **Counts**: 1642 tests (1640 + 2), 97 goldens, 78 guards
  (`LayoutAuthorityCompileGuards` 1 → 2), `typecheckFile` 37 → 38, all
  measured fresh at §11/`21f2369` and re-measured in the Record phase (§20).
- **No golden moved and none may** (`Sources/MetalUILayout/` untouched);
  **no divergence or declared-but-inert row changed** — `LayoutAuthority.proposal`
  in production stays the one inert row this stage's territory touches, and
  it is unchanged (still inert until stage 6b).
- **CLAUDE.md**: the counts block gains this stage's layer on top of
  `b3c29b9`'s; the `LR-` next-unused note (`LR-CT` → `LR-DF`); the plan
  task 7 stage list gains stage 6a's citation; the "SwiftUI alignment"
  section gains a stage 6a bullet (the public pair deprecated, no
  production move, the entry measurement handed to 6b/7b); the guards
  per-file list and the CI-hazards "all 77 guards" sentence move to 78;
  the `typecheckFile` helper split moves to 40/38. `AGENTS.md` copied
  after, `cmp` checked.

## 20. Record phase (2026-09-23, PDT) — docs pass over `b3c29b9..21f2369`

No file under `Sources/` changed in this pass (the record file and,
separately, CLAUDE.md/AGENTS.md/records/plan/README).

**Suite, re-taken.** `swift package clean`, then `swift build --build-system
native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's
`--build-system native` deprecation notice. Unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1642 tests in 3
suites passed after 85.307 seconds`**, one summary line, `FR-J no-argument
frame: succeeded=true deprecations=2` in the log (guards ran). Default
build system, `swift build --build-tests`: **`Build complete!`**, 0
`error:`, 0 `warning:` — the gate holds on both build systems after a clean
build, not only at the lane's own measurement. Goldens: `find
Tests/MetalUILayoutTests -name "*.json" | wc -l` reads **97**;
`git diff --name-only b3c29b9 HEAD -- 'Tests/**/*.json'` empty. Guards:
`grep -c canTypecheck` per file, re-counted fresh, matches CLAUDE.md's
per-file list exactly with `LayoutAuthorityCompileGuards` now **2** — total
**78** (80 `canTypecheck` hits less `Typecheck.swift`'s declaration and
`UnitSafetyTests`' one comment). *Erratum (branch checker, §21): CLAUDE.md's
per-file list is the stage-5 paragraph's and still read 1; the stage-6a
bullet now says so.*

**Verdict: the stage's exit criteria (§11) all hold**, re-measured
independently of the lanes' own runs. Docs updated in this pass: `CLAUDE.md`
(counts, `LR-` next-unused, the plan-task-7 stage list, a new "SwiftUI
alignment" bullet, the guard-count and `typecheckFile`-split updates —
verified against source, not copied from the lane verdicts), `AGENTS.md`
(copied, `cmp` clean), `docs/record/04-divergences.md` and
`docs/record/05-declared-but-inert.md` (each gains a 2026-09-23 dated
section recording that this stage changes no row — no divergence and no
inert API moves, since production is untouched beyond the two attributes
and one literal), `docs/record/README.md` (the §30 row),
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md` (task 7's stage-6a
progress paragraph, appended after stage 5's; the task's own checkbox stays
unticked — this is stage 6a of 14, and 6b onward remain; the original "14 stages remain" was a slip), `docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
("Where the task actually stands" gains a stage-6a sentence), this stage's
own spec's Status line (marked delivered, Record phase noted), and
`README.md` (the branch/count line, the record-file list, the engine-replacement
spec bullet).

## 21. Branch checker (2026-09-23, PDT) — adversarial pass over `b3c29b9..af1af6f`

Every check below was run on this worktree; each scratch edit was restored
from a copy and `git status --short` read clean after it.

**Suite.** `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`; one `warning:`, SwiftPM's `--build-system native`
notice), then unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1642 tests in 3 suites passed after 80.513 seconds`**, `FR-J
no-argument frame: succeeded=true deprecations=2` in the log. The test log's
only `warning:` is the same notice. Default build system, `swift build
--build-tests`: `Build complete!`, 0 `error:`, 0 `warning:`. Goldens 97,
`git diff --name-only b3c29b9 HEAD -- 'Tests/**/*.json'` empty. Guards 78 (80
hits less the declaration and the comment). `cmp CLAUDE.md AGENTS.md` clean.

**Callers.** `grep -rn 'requestNode(\|requestLeaf(' Sources Tests | grep -v
requestNative` leaves no call on the public pair outside a declaration marked
`@available(*, deprecated)`: the six `Dep` fixtures (`CustomNodeElement`,
`CustomLeafElement`, the four `LegacySpelled…` rows), `DeprecatedRegistrarRow`
and the fixture string of guard 3.2. Every other hit is `pass.frame.` or a
doc comment. The one existing assertion whose text changed is
`registeringALayoutNodeDuringPaintDoesNotCompile`'s reason string
(`"requestNode"` → `"requestNativeLeaf"`), which follows its fixture's
re-spelling; no other `#expect`/`#require` line was removed or edited.

**The classification table (§4).** 153 rows, 153 distinct `file test` pairs,
every one resolving to a `func` in the named file; per-class counts sum to 153.
Every row has an owner once `LR-DA` item 5 is applied — the AV cell still read
"unassigned" and is amended in place (below). Every backticked test name (238)
and `File.test` citation in the branch's changed docs resolves; every ruling
id resolves except the "next unused" markers and the quoted typo `LR-3`.

**Pixels.** Lock probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main:
1` — no real-window capture. `docs/probes/demo-pixels/compare.sh <scratch>
b3c29b9 af1af6f`: every control at its recorded value (1048576, 1030498,
210027, 0, 1048576, chrome pair 0, distinct 544 / 216, indicator rects 0) and
all twelve `differing=0`, scene identical.

**MX1 — the gate can fail.** `@available(*, deprecated)` removed from
`TombstoneTests.LegacySpelledExcursionRow.requestLayout` alone. The native
build prints exactly **one** new `warning:`, `TombstoneTests.swift:143:15:
'requestNode(style:children:)' is deprecated: …`; the suite stays green (1642
passed) — nothing but the build log's count sees the gate, which is what
`LR-CX` says. Restored.

**MX2 — identity under the production authority after the R move.** `LR-DA`
item 7 accepted that the R tests stop pinning the legacy authority, "on the
grep". The mutation puts a branch there that the grep cannot find: `Box`'s
child cursor starts at `pass.lowersToProposal ? 0 : 1` (legacy-only identity
shift). At HEAD: **86 tests red, 216 issues** — none in `IdentityTests`. The
same mutation over `b3c29b9` (a `git archive` in scratch): **96 red, 230
issues**. The difference is exactly ten tests, red at `b3c29b9` and green at
HEAD, and exactly the R-moved identity pins: `IdentityTests`
`aBranchReservesBothIndicesSoASiblingCannotLandOnTheUntakenOne`,
`anElementAfterAVanishingIfAdoptsTheVanishedElementsState`,
`flippingAnEitherBranchResetsTheBranchesState`,
`namingTheLaterSiblingIsWhatSurvivesAVanishingIf`,
`reorderingAnUnnamedListKeepsStateWithThePositionNotTheItem`,
`theIndexSpaceIsFlatRatherThanNested`,
`twoErasedSiblingsDoNotShareOneStateEntry`;
`ElementLayoutTests.anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition`;
`ModifiedElementTests.anIDAfterAChainsLastWrapperNamesTheOutermostLayer`;
`ModifierCompositionProofTests.stateSurvivesFramesUnderALegacyModifierChain`.
No test is red at HEAD that was green at `b3c29b9`. The 86 at HEAD are the
differential and lowering files (`LoweringItemTests` 26,
`LoweringDistributionTests` 9, `LoweringComponentTests` 9,
`LoweringContainerTests` 7, `LoweringBoxModelTests` 7, `LoweringScrollTests` 5,
`PresentationLoweringTests` 4, `LoweringPipelineParityTests` 3,
`LoweringCorpusTests` 3, `ListLoweringTests` 3, `ModifiedElementTests` 2,
`LoweringStackAndLayerTests` 2, `AccessibilityTreeTests` 2,
`ProposalNodeIDTests` 1, `ModifierCompositionProofTests` 1,
`FrameDecorationInteractionTests` 1, `DisabledTests` 1; the full name list is
in the checker's scratch log, and includes
`aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`,
`aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`,
`aLoweredWindowPublishesTheSameAccessibilityTree`,
`aLoweredListsRowIdentitiesAreTheLegacyOnes` and
`reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder`).
**Reading:** item 7's cost, measured — the ten identity pins moved to the
proposal authority, and a legacy-only identity regression is still caught, by
86 tests, mostly the differential harness comparing the two authorities.
**MX2′** (the control, `pass.lowersToProposal ? 1 : 0`) reddens 99 tests with
285 issues, among them seven `IdentityTests` (the seven above),
`anIdentifiedChildOfAnUnnamedContainerHasAnIdentityThroughItsPosition`,
`anIDAfterAChainsLastWrapperNamesTheOutermostLayer` and
`stateSurvivesFramesUnderALegacyModifierChain`: the moved tests still see
identity, now under `.proposal`. Restored after each.

**Identity, hit testing, accessibility, animation.** Not moved by any
`Sources/` change (the two attributes, one `owningStage` literal, doc
comments). The pins a legacy-only regression in each still reaches at HEAD are
in MX2's list: identity and state (`aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`,
`aLoweredListsRowIdentitiesAreTheLegacyOnes`), hit testing and focus
(`aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`,
`aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick`),
accessibility (`aLoweredWindowPublishesTheSameAccessibilityTree`,
`hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`,
`eachLiveHandlerAloneMakesAnUndeclaredElementRecord`), animation
(`aLoweredMarginRegistersItsAnimatedValue`,
`anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues`); the P-6b
hit-testing pins (`HitboxTests`' five) stay on `.legacy` explicitly.

**Doc defects fixed (this commit).** (1) Record §4's AV owner cell read
"unassigned — 6b must assign it" and its summary "with no owner", after
`LR-DA` item 5 made 6b the owner; amended in place with the design's wording
quoted. (2) The plan's stage-6a paragraph repeated "has no owning stage … 6b
must assign it" — the wording `LR-DA` item 5 rejected; now "owned by 6b as a
prerequisite of its flip". (3) CLAUDE.md's stage-6a count bullet said
`LayoutAuthorityCompileGuards` 1 → 2 was "in the per-file list above", which
still reads 1 (it is stage 5's paragraph); the bullet now says so. (4) §20's
guard arithmetic ("79 hits less the comment") and "14 stages remain"
corrected, each keeping the old wording as an erratum. (5) The parent spec's
status sentence said stage 6a "has landed" and attributed itself to the
branch checker before one ran; now "complete on its branch, not yet merged".

**No code defect found. Merge verdict: `ok`.** Task 7 stays unticked; the
plan's note and the parent spec's §4.1 rows 6a/6b/7b/9 agree (custom
elements are removed at 9 per `LR-CW`, 6b owns root placement and `hidden()`,
7b the 43 CSS rows).
