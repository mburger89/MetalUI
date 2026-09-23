# §39 — Engine replacement, stage 6b: the root switch

Plan task 7, stage 6b (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 6b,
rulings `LR-Q`, `LR-S`, §8). Design:
`docs/superpowers/specs/2026-09-23-engine-stage-6b-design.md`. Rulings
`LR-DF`…`LR-DN` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-6b` from `aef88ce`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-6b`.

**Numbering hazard.** This file was written as §39 at design time. Another line
(`feat/demo-cross-platform`, roadmap items 9 and 10) was seen drafting a
CLAUDE.md counts block that cites "record §39" for itself on the same day. If
that line reaches `master` first, this file is renumbered at merge by the
precedent of record §23 §8 and the §25/§27/§29/§38 headers.

**Status, 2026-09-23 (PDT): design measurements (§1–§8).** Every one was taken on
scratch commits — `431d8bd` (arm F), `1c2fd9e` (arm G), `947cdd5` (arm H),
`fd036b9`/`7218cd7` (arm H0), reverted by `b77118e`; `6cdde03` (arm G2),
reverted by `e77375e` — after each revert `git diff --quiet aef88ce HEAD --
Sources Tests` succeeds. They stay in the history so an arm can be re-run by
checking it out. The lanes append from §9.

## 1. Baseline at `aef88ce`

`swift build --build-system native --build-tests`, then unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1688 tests in 3 suites
passed after 92.588 seconds`**; 0 `error:`; the only `warning:` SwiftPM's
deprecation notice; `FR-J no-argument frame: succeeded=true deprecations=2` in
the log (the guards ran).

## 2. The flipped default, three arms

| arm | commit | what is flipped | tests | red | issues |
|---|---|---|---|---|---|
| F | `431d8bd` | record §38's A2 re-taken: `Frame.init` and `Window` `.proposal`, diagnostics **on** (`Window` passes `reportsUnlowerableFields: true`), record §38's helper set (cherry-picked `9ccc0d8` + `2a7cec0`: nine sites in eight files), traps printed `SIXB-WOULD-TRAP:` / backstop non-fatal | 1688 | **90** | 318 |
| G | `1c2fd9e` | as F, diagnostics **off** (production); a deepest-depth counter on `NativeLayoutRun.enter` and a gated root-depth probe test | 1689 | **90** (the same set) | 317 |
| G2 | `6cdde03` | as G without the counter, plus the **four** file-local helpers §38 never flipped: `TextSystemSeamTests.render` (`:32`), `EnvironmentTests.frame` (`:192`) and `.counts` (`:965`), `ContainerIntegrationTests.render` (`:677`) — thirteen helper defaults | 1688 | **92** | 319 |

Arm G2's patch against `aef88ce` is committed as
`docs/probes/stage-6b-flip-instrument.patch` (`git apply --check` clean at
`e77375e`). **G2 is the entry measurement.** Its two reds beyond G are
`EnvironmentTests.aLocaleChangesNoTextMeasurement` and
`dynamicTypeSizeChangesNoTextMeasurement` — record §38's CSS-style rows, green
in F and G only because `EnvironmentTests.frame` still defaulted to `.legacy`.
**Finding: §38's instrument missed four `.legacy` helper defaults** (found by
`grep -rn "LayoutAuthority = \.legacy" Tests`, which read 14 lines at
`aef88ce`: the thirteen defaults and `LayoutDifferential.swift:110`'s
per-pass choice, which is the harness's own).

**Against record §38 §4's 153 rows**: 89 still red in F; the other 64 are every
row stage 6a re-spelled or pinned (CE 6, CE+RP 23, CSS-frame 10, CSS-d48 5,
CSS-pin 2, CSS-box 2, CSS-structure 12, N9 2) and the two CSS-style rows above
(red again in G2). One red is new: stage 6a's exit test
`aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`,
class X (its trap half cannot trap under a non-fatal instrument).

**WOULD-TRAP lines in G2** (tests a real flip would **abort**, truncating the
run): `aColdFrameCreatesAtMostOneLineBreakTokenizer` (`box.minSize.unconsumed`),
the five AV tests (`box`/`modifierLayer.display.none`),
`everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`
(`box.display.none`), and **two tests green in every arm and absent from §38's
table**: `aWarmFrameTokenizesEachDistinctStringAtMostOnce` and
`aWarmFrameReachesTheUncachedFontResolverZeroTimes` (`box.minSize.unconsumed`,
`demoLikeRows`' root). Arm F's diagnostics hid them: a reporting frame does not
abort.

## 3. The 92 reds, one row per test

Arms for the RP rows are record §38 §4's (spec §5.2 carries them).

| class | file | test | disposition |
|---|---|---|---|
| X | AXNodeTests | `aLegacySpelledAXListRowAbortsAProductionProposalFrame` | untouched |
| X | AbsoluteOverlayTests | `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame` | untouched |
| X | AccessibilityDefaultsTests | `aHiddenListAbortsAProductionProposalFrame` | untouched |
| X | AccessibilityDefaultsTests | `aRootMinHeightOnTheScrollerFixtureAbortsAProductionProposalFrame` | untouched |
| X | LayoutAuthorityTests | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` | untouched |
| X | LayoutAuthorityTests | `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` | untouched |
| X | LayoutAuthorityTests | `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` | untouched |
| X | ListTests | `aLegacySpelledListRowAbortsAProductionProposalFrame` | untouched |
| X | LoweringContainerTests | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` | untouched |
| X | LoweringLeafTests | `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction` | untouched |
| X | MeasurePerformanceTests | `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` | untouched |
| X | MeasurePerformanceTests | `aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority` | untouched |
| X | PresentationLoweringTests | `aPresentationTrapsAProductionProposalFrameNamingItsField` | untouched |
| X | TombstoneTests | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` | untouched |
| D | LayoutAuthorityTests | `aFrameAndAWindowDefaultToTheLegacyAuthority` | lane 3 rewrites |
| D | LayoutAuthorityTests | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` | lane 3 rewrites |
| N9 | NativeBoundaryIntegrationTests | `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` | lane 2 pins .legacy (9) |
| N9 | NativeBoundaryIntegrationTests | `aPaddingModifierOnAProposalComponentTraps` | lane 2 pins .legacy (9) |
| N9 | NativeBoundaryIntegrationTests | `aProposalElementInsideALegacyContainerTrapsAtRegistration` | lane 2 pins .legacy (9) |
| RP | AXEmitSiteTests | `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` | lane 2 re-spells |
| RP | AXEmitSiteTests | `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds` | lane 2 re-spells |
| RP | AXNodeTests | `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds` | lane 2 re-spells |
| RP | AccessibilityTreeTests | `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` | lane 2 re-spells |
| RP | AnimationTests | `hoverAndFocusFadeThroughTheSameEffectiveColourPath` | lane 2 re-spells |
| RP | BackgroundChainTests | `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour` | lane 2 re-spells |
| RP | BackgroundChainTests | `everyBackgroundPaintingSiteHonoursHoverAndFocus` | lane 2 re-spells |
| RP | DecorationPaintTests | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` | lane 2 re-spells |
| RP | DecorationPaintTests | `aBorderIsVisibleOverAChildThatFillsTheBox` | lane 2 re-spells |
| RP | DecorationPaintTests | `aChainsOuterLayerScopesContainTheLayersInsideIt` | lane 2 re-spells |
| RP | DecorationPaintTests | `aFocusRingOutranksAHoverBorderAndABorder` | lane 2 re-spells |
| RP | DecorationPaintTests | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` | lane 2 re-spells |
| RP | DecorationPaintTests | `clippedAlsoClipsTheHitboxesInsideIt` | lane 2 re-spells |
| RP | DecorationPaintTests | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` | lane 2 re-spells |
| RP | DecorationPaintTests | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` | lane 2 re-spells |
| RP | DecorationPaintTests | `everyDecorationScopingSiteContainsItsOwnContent` | lane 2 re-spells |
| RP | DisabledTests | `aClickNeedsTheTargetEnabledAtPressAndAtRelease` | lane 2 re-spells |
| RP | DisabledTests | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` | lane 2 re-spells |
| RP | DisabledTests | `aDisabledScrollViewStillScrollsOnTheWheel` | lane 2 re-spells |
| RP | DisabledTests | `aDisabledTargetIsNeitherHoveredNorPressed` | lane 2 re-spells |
| RP | DisabledTests | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` | lane 2 re-spells |
| RP | DisabledTests | `theGateReadsTheEnvironmentValueNotTheModifier` | lane 2 re-spells |
| RP | EnvironmentTests | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` | lane 2 re-spells |
| RP | FrameDecorationInteractionTests | `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes` | lane 2 re-spells |
| RP | FrameDecorationInteractionTests | `aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick` | lane 2 re-spells |
| RP | FrameDecorationInteractionTests | `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame` | lane 2 re-spells |
| RP | FrameDecorationInteractionTests | `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` | lane 2 re-spells |
| RP | FrameDecorationInteractionTests | `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset` | lane 2 re-spells |
| RP | FrameLoopTests | `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` | lane 2 re-spells |
| RP | FrameLoopTests | `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize` | lane 2 re-spells |
| RP | GlyphEmitterTests | `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox` | lane 2 re-spells |
| RP | GlyphEmitterTests | `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` | lane 2 re-spells |
| RP | HitRegionTests | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` | lane 2 re-spells |
| RP | HitRegionTests | `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` | lane 2 re-spells |
| RP | HitRegionTests | `aContentShapeWithoutAClickHandlerRegistersNothing` | lane 2 re-spells |
| RP | HitRegionTests | `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse` | lane 2 re-spells |
| RP | HitRegionTests | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` | lane 2 re-spells |
| RP | HitRegionTests | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` | lane 2 re-spells |
| RP | InputDispatchTests | `aClickInsideTheBoundsRunsTheHandler` | lane 2 re-spells |
| RP | InputDispatchTests | `aClickOutsideTheBoundsDoesNotRunTheHandler` | lane 2 re-spells |
| RP | InputDispatchTests | `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler` | lane 2 re-spells |
| RP | InputDispatchTests | `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne` | lane 2 re-spells |
| RP | InputDispatchTests | `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` | lane 2 re-spells |
| RP | InputDispatchTests | `aNestedHandlerWinsOverItsContainingStackToo` | lane 2 re-spells |
| RP | InputDispatchTests | `aPressThatLeavesTheElementAndReturnsStillClicks` | lane 2 re-spells |
| RP | InputDispatchTests | `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` | lane 2 re-spells |
| RP | InputDispatchTests | `onClickIsLiveOnEveryConformerThatCanRegisterOne` | lane 2 re-spells |
| RP | InputDispatchTests | `onlyABoxWithAHandlerRegistersAHitbox` | lane 2 re-spells |
| RP | LayoutAuthorityTests | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` | lane 2 re-spells |
| RP | OuterModifierMatrixTests | `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` | lane 2 re-spells |
| RP | OuterModifierMatrixTests | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | lane 2 re-spells |
| RP | OuterModifierMatrixTests | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` | lane 2 re-spells |
| RP | PointerStatePaintTests | `aHoveredBoxPaintsItsHoverBackground` | lane 2 re-spells |
| RP | PointerStatePaintTests | `focusOutranksHoverWhenAnElementIsBoth` | lane 2 re-spells |
| AV | AccessibilityDefaultsTests | `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` | lane 1 lowers hidden() |
| AV | AccessibilityTreeTests | `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` | lane 1 lowers hidden() |
| AV | AccessibilityTreeTests | `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient` | lane 1 lowers hidden() |
| AV | AccessibilityTreeTests | `aHiddenRootPublishesNothing` | lane 1 lowers hidden() |
| AV | AccessibilityTreeTests | `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` | lane 1 lowers hidden() |
| RT | MeasurePerformanceTests | `aColdFrameCreatesAtMostOneLineBreakTokenizer` | lane 2 pins .legacy (9) |
| CSS-structure | FrameDecorationInteractionTests | `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` | lane 2 pins .legacy (7b) |
| CSS-structure | OuterModifierMatrixTests | `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` | lane 2 pins .legacy (7b) |
| CSS-style | AnimationTests | `everyRegisteringSiteAnimatesItsStyle` | lane 2 pins .legacy (7b) |
| CSS-style | EnvironmentTests | `aLocaleChangesNoTextMeasurement` | lane 2 pins .legacy (7b) |
| CSS-style | EnvironmentTests | `dynamicTypeSizeChangesNoTextMeasurement` | lane 2 pins .legacy (7b) |
| CSS-style | StackElementTests | `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct` | lane 2 pins .legacy (7b) |
| CSS-style | StackElementTests | `stackDefaultsToCentreNotStretch` | lane 2 pins .legacy (7b) |
| CSS-style | StackElementTests | `stackWritesDisplayAndBothAlignmentFields` | lane 2 pins .legacy (7b) |
| CSS-style | TextMeasureTests | `aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot` | lane 2 pins .legacy (7b) |
| CSS-text | TextMeasureTests | `aCentringColumnShrinkWrapsItsTextLikeWebKit` | lane 2 pins .legacy (7b) |
| CSS-text | TextMeasureTests | `aLongLabelInAStretchedColumnWrapsRatherThanOverflowing` | lane 2 pins .legacy (7b) |
| CSS-text | TextMeasureTests | `aTextPaintsItsBackgroundAndItsGlyphs` | lane 2 pins .legacy (7b) |
| RP+CSS-frame | FrameDecorationInteractionTests | `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` | lane 2 pins .legacy (7b) |

Plus the 23 P-6b rows stage 6a pinned (green here because pinned; spec §5.2
lists them with their arms): 21 re-spelled by lane 2, two kept as CSS answers.

## 4. Pixels, flipped against unflipped

`docs/probes/demo-pixels/compare.sh` run from a copy whose harness captures the
demo and preview at the window's **default** authority (the change now
committed to `ZZDemoPixels.swift`). **The harness change itself, measured at
`aef88ce`**: the new harness against its predecessor (the committed one, run
with the change stashed), 0 differing and the scene dump identical in all
twelve images.

Controls at `aef88ce`, all at their recorded values: light vs dark 1048576;
default vs modal 1030498; default vs animation 210027; f0 vs f3 0; preview
light vs dark 1048576; chrome legacy vs proposal 0; distinct 544 / 216;
indicator rects 0.

| image | `aef88ce` → arm G | `aef88ce` → arm H0 (re-spelling alone, legacy) | arm H0 → arm H (re-spelling + flip) |
|---|---|---|---|
| default-light-f0 / -f3 | 172789, bbox (92,113)–(987,1007) | 0, scene identical | 168380 |
| default-dark-f0 / -f3 | 172786 | 0 | 168380 |
| modal-light | 175970 | 0 | 172126 |
| modal-dark | 175944 | 0 | 172105 |
| animation-light | 356088, bbox (135,113)–(977,1007) | 0 | 341608 |
| animation-dark | 356086 | 0 | 341606 |
| preview-light / -dark | **0, scene identical** | 0 | **0** |
| chrome-legacy / -proposal | **0, scene identical** | 0 | **0** |

(Arm H is arm G plus `.height(Pixels(28))` on the demo list row's inner `Box`;
`aef88ce` → arm H reads the same numbers as H0 → H, since H0 is 0.)

**Every delta, from the `.scene` dumps** (1024², so the legacy sidebar is
shrunk to 96, not the 88 of a 920 window). Rect deltas `(dx, dy, dw, dh)` with
counts, arm G then arm H:

- `default-light-f0`: 518 rects each side, 5 identical (the root, header card,
  avatar, bar, hairline — the root at (0, 0) 1024×1024 in both, so `CN-J` does
  not move the demo). `(+100, 0, 0, 0)` × 507 — every main-pane rect (cluster,
  badge, counter, scroller, the 500 rows); `(0, 0, +100, 0)` × 5 — the sidebar
  card and its four bars; `(+100, 0, −100, 0)` × 1 — the main pane. **Cause 55.**
  Same in arm H.
- Glyphs, 15 711 each side. Arm G: `(+100, −6)` × 15 392 — the 500 row labels,
  55 plus **X9** (the inner `Box` hugs its 16 pt label at the row's top where
  CSS stretched it to 28 and centred it); `(+100, 0)` × 117; the paragraph's
  re-wrap `(+194, 0)`, `(+294, 0)`, `(+295, 0)`, `(−548, +16)`, `(−652, +16)`, …
  **Arm H: `(+100, 0)` × 15 509** — the X9 group is gone and the row labels
  move with 55 alone; the re-wrap groups unchanged; "Count 0"'s six glyphs
  `(+101, 0)` (a one-point centring round in the 140 pt readout); "Library"'s
  seven glyphs identical.
- `modal-light`: the above plus the card `(0, −8, 0, +16)` × 1 and 86 modal
  glyphs `(0, −8)` — **cause C** (the lowered column measures the paragraph at
  the card's 320; the legacy column's height is its items' max-content
  contributions, one line).
- `animation-light`: `(+181, +16, 0, 0)` × 500 — the rows, 55 at the animated
  320 (CSS shrank it to 139) plus the paragraph one line taller in the
  narrower column; `(+181, 0, 0, 0)` × 6; `(0, 0, +181, 0)` × 5;
  `(+181, 0, −181, 0)` × 1; `(+181, +16, 0, −16)` × 1 — the scroller.

## 5. Depth

**Ceilings** — `docs/probes/native-depth-ceiling/bisect.sh <scratch> aef88ce
<release|debug>`; a chain of N one-child nodes of each kind over a leaf, laid
out at 400×400 through `computeNativeLayout` on a 1 MB `Thread`, with
`maxDepth` raised to 1 000 000 in the exported tree; one process per depth;
exponential search then bisection; each boundary re-confirmed. Positive control
in both configurations: `controls ok … padding 10 completes, padding 2000000
dies`.

| kind | debug last / first-dies | release last / first-dies |
|---|---|---|
| padding | 194 / 195 | 1256 / 1257 |
| fixed frame 100×100 | 194 / 195 | 1256 / 1257 |
| flexible frame, 0…∞ both axes | 194 / 195 | 1256 / 1257 |
| one-child vertical stack | **127 / 128** | **653 / 654** |
| one-child horizontal stack | 127 / 128 | 653 / 654 |
| overlay | 169 / 170 | 1256 / 1257 |
| custom `ProposalLayout`, measuring and placing its child | 178 / 179 | 1037 / 1038 |
| scroll viewport (vertical) | 194 / 195 | 1256 / 1257 |
| two-cell grid row (the placement path, `GR-AK`) | 155 / 156 | 1256 / 1257 |

Debug agrees with the grids track's last reading (padding 194 / 195, stack
127 / 128; record §22) and with `NativeLayoutRun.maxDepth`'s doc comment's
grids rows; the 2026-09-14 `SA-L` table (stack 151, custom 156) is superseded.
The first bisect run failed its own harness twice before reading anything —
the kinds list was one zsh word, and `swift build -c release --build-tests`
does not enable testable imports (`ModuleNotTestable`); both fixed in
`3e427f3`, and the numbers above are that script's.

**Production roots** (arm G's counter, through `makeFakeWindow` at 920², two
frames each, the gated `zzRootDepthProbe`): `SIXB-DEPTH demo proposal
deepest=29`, `demo-modal … 29`, `demo-animation … 29`, `preview … 10`,
`preview-legacy legacy … 10` (a native root is laid out by the kernel under
either authority), `list proposal deepest=15` (a `ScrollView { List }` of 200
rows, each `Box { Text }.alignItems(.center).flexGrow(1).padding(12).width(420)`).
CLAUDE.md's "measured at 18" for the demo predates stages 3 and 4 (the scroll
viewport and the windowed `List` add levels). Not yet re-measured after the
demo re-spelling (lane 3).

## 6. SwiftUI probes, re-run

`/usr/bin/swift` (Apple Swift 6.4), macOS 27.0, 2026-09-23, each exit 0, and
**every output line found verbatim among its header's recorded lines**
(`grep -vxFf` of the output against the header's `//   ` lines reads 0 for
each):

| probe | output lines | arms this stage rests on |
|---|---|---|
| `swiftui-stack-algorithms.swift` | 787 | R control, R1–R4 (`CN-J`, `LR-DG`); G9, G4r (55) |
| `swiftui-engine-replacement-stage1.swift` | 79 | H0–H2 (`LR-DH`); T3, T4 (C) |
| `swiftui-engine-replacement-stage2.swift` | 254 | V0–V3 (`LR-DH`); F5 (55); X9 (`LR-DJ`) |

## 7. The screen

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate
&& /tmp/lockstate` at design: `CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1`, `displayActive main: 0`. No real-window capture was attempted.

## 8. Findings the design hands to the lanes

- **Four `.legacy` helper defaults §38's instrument missed** (§2), and with them
  two CSS-style rows that only looked fixed. The committed patch flips all
  thirteen.
- **Two tests abort the real flip that no table listed** (§2): the design
  disposes of them in spec §5.5.
- **The demo's list rows lose their centring under the flip** (X9, §4) — the
  one demo re-spelling.
- **`SA-L`'s table was stale in the direction that matters** (§5): 88 is above
  its own rule; 72 is the rule's answer.
- **`FrameSizingTests`' `render`/`widthInRow`/`nodeCount` and the two `observe`
  helpers take the authority as a required argument** (record §38 §17); the
  thirteen-default flip cannot reach their calls.

## 9. Critic round 1 (`LR-DO`)

On `138746c`. **Re-run byte for byte:** `swiftui-engine-replacement-stage1.swift`
(`/usr/bin/swift`, exit 0, 79 lines, 0 missing from its header; H0 20×60, H1
20×60, H2 20×40 — H2 is the arm that separates) and `swiftui-stack-algorithms.swift`
(exit 0, 787 lines, 0 missing; R control (0, 0) 100×100 against R1/R2 (21, 40)
58×20). `git apply --check docs/probes/stage-6b-flip-instrument.patch`: clean.
`grep -rn "LayoutAuthority = \.legacy" Tests`: the thirteen defaults, no other
spelling (`grep -rnE "LayoutAuthority\??\s*=\s*(LayoutAuthority)?\.legacy"`
reads 13 too).

**Defects found and fixed in the spec (§0) and `LR-DO`:**

1. `LR-DI` item 4 deferred the root's `minSize`/`maxSize` to stage 8 although
   `LR-AQ` names stage 6b as their owner, and left the resulting production
   trap without an exit test. Now: a declared root axis folds its px/rem
   min/max (lane 1, test 1.7); the rest traps, pinned by 1.8.
2. §5.4's "the proposal path has no site-by-site animates-its-style guard" is
   false for five of the guard's sites (seven proposal tests named in spec §0),
   and `ScrollView`'s lowered path has its own two `animated(` calls
   (`ScrollView.swift:393`, `:403`) the legacy-pinned guard never reaches.
   Lane 2 maps and closes it (2.1) instead of handing it to 7b.
3. The pixel accounting was at 1024² and 560² only; `MetalUIDemo` opens
   920×560. Two production-size images added.
4. Depth moved from lane 3 to lane 1 (reads no default; lane 3 was largest).
5. Test 1.6 could stay green under M1g if the legacy path emits nothing for
   the hidden element; its fixture now `#require`s a non-empty legacy emission.
6. M3a's predicted reddened set lacked 3.2's proposal arm and 3.3.

**Rejected, with reason in `LR-DO`:** lowering an auto-axis root min/max as a
flexible frame (no probe records a lone `frame(minHeight:)`/`frame(maxHeight:)`
at a root), and splitting lane 2 (tests only, mechanical, three-lane cap).

## 10. Lane 1 — `hidden()`, the root fold, depth (`LR-DH`, `LR-DO` item 1, `LR-DK`, `LR-DP`)

Commits: `403d6d6` (red first; Sources carry only inert scaffolding —
`Frame.hiddenNodes`, never written, and `LayoutTree.lastNativeLayoutDeepestLevel`),
`ef48a0a` (implementation), `f72ebfd` (root arms of 1.2/1.3), then this record,
the spec note and `LR-DP`. Default authority unchanged (`.legacy`).

### 10.1 Red before (at `403d6d6`)

The proposal arms trap, so each was run filtered; every one aborted with
`MetalUI/Frame.swift:1550: Fatal error: MetalUI: box.display.none has no proposal
lowering (plan task 7, stage 2)` — 1.2, 1.3, 1.5, `aListInsideHiddenContent…`,
`hiddenContentIsNotPublished…`, `aHiddenRootPublishesNothing` — or with
`modifierLayer.display.none` — 1.4, `aHiddenInnerModifierLayerSuppresses…`,
`aHiddenOneNodeFrameLayerPublishes…`. In-process reds: 1.1, 6 issues (report
non-empty; lowered `c.y` 20 not 40; column 40 not 60; `b`; the hidden `Stack`'s
report and rects); 1.7, 3 issues (`box.minSize.unconsumed` ×2,
`box.maxSize.unconsumed`; the heights were already 370/500/300 on both — the
element's own frame folded them, only the report was wrong); 1.8's px control
(`.signal(SIGTRAP)`); the eight depth tests (trap arms exit success, at-limit
arms print `limit=88`); `everyStageOneUnlowerable…` 4, `aLoweredStackPlaces…` 1,
`aHiddenFrameLayerLowersAsIfShown` 5, `everyContainerField…` 1,
`anItemFieldNoLoweredContainer…` 2, `aListsWorkIsTheSameFor160RowsAsFor40` 2,
and the three inverted exit tests (SIGTRAP). 1.6 green on arrival: the legacy
path emits a 0×0 accent rect, glyphs at (0, 2) and (−1, 18) — the doc of
`Box.hidden()` measured the same — and one 0×0 opaque hitbox.

Printed at-limit lines (hand derivation in each fixture's doc):
`LANE5-5.8 nodes=72 deepest=72`, `LANE2-2.14 nodes=106 deepest=72`,
`LANE4-4.8 nodes=100 deepest=72`.

### 10.2 After

`swift build --build-system native --build-tests`: 0 `error:`, only SwiftPM's
deprecation `warning:`. Unfiltered `swift test --build-system native
--no-parallel`: **`Test run with 1696 tests in 3 suites passed`** (1688 + 6 in
`HiddenLoweringTests` + 2 in `RootFieldLoweringTests`), `FR-J no-argument frame:
succeeded=true` in the log; no pre-existing test reddened beyond those
rewritten. Roll call 87. Goldens: `git diff --name-only aef88ce HEAD --
'Tests/**/*.json'` empty. `git apply --check
docs/probes/stage-6b-flip-instrument.patch` clean at `ef48a0a` — not regenerated.

### 10.3 Mutations (each committed first, restored from a copy, full unfiltered suite, `git status --short` clean after)

| id | mutation | reddened (all others green) |
|---|---|---|
| M1a | the three `frame.hiddenNodes.insert(node)` removed | 1.2, 1.3, 1.4, 1.5 and the five AV tests' **proposal** arms only (28 issues) |
| M1b | `lowerLegacyLeaf`'s hidden branch → 0×0 leaf | **only** `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (1 issue) — a broken instrument for 1.1 (`LR-DP` item 5) |
| M1b2 | both hidden branches (`lowerLegacyNode`'s and `lowerLegacyLeaf`'s) → 0×0 leaf | 1.1, 1.4, `everyStageOneUnlowerable…` (7 issues) |
| M1c | `Element.paintGroup`'s skip removed | 1.2 (2 issues) |
| M1d | `Element.prepaintGroup`'s pointer-disable scope removed | 1.3 (2) |
| M1e | `ModifiedElement`'s per-layer skip and scope removed | 1.4 (4) |
| M1f | `AnyElement`'s entry gates removed | 1.5 (3) |
| M1g | `paintGroup`'s skip reads `isHidden` (`display == .none` too) | 1.6, at its `#require` on a non-empty legacy emission (1) |
| M1h | the root fold removed | 1.7, 1.8, `aListsWorkIsTheSameFor160RowsAsFor40` (both arms), `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `aProductionFrameOverDemoLikeRowsCompletesUnderTheProposalAuthority`, `aRootMinHeightOnTheScrollerFixtureNoLongerAbortsAProductionProposalFrame` (10 issues). The font-resolver test is still `.legacy` at lane 1, so it does not appear; lane 2 owns it |
| M1i | `render`'s root paint skip removed | 1.2 (1) |
| M1j | `render`'s root pointer-disable scope removed | 1.3 (1) |
| VH | `lowerLegacyLeaf`'s hidden-branch `frame.hiddenNodes.insert(node)` removed (branch: the leaf's, line 243; the other two inserts kept) | before 1.9: **nothing** (1696 green) — the leaf site's gates were unpinned. After 1.9: **only** `aHiddenTextIsHiddenUnderTheProposalAuthority` (4 issues, 1697) — `LR-DP` item 7 |
| M3e | `maxDepth` back to 88 | the eight: `aChainOf72GridsTraps`, `aChainOf71GridsDoesNotTrap`, `aLoweredChainAtTheNativeDepthLimitLaysOut`, `aLoweredChainOneLevelPastTheNativeDepthLimitTraps`, both 2.14 and both 4.8 arms (12 issues) |
| M3f | `maxDepth` 71 | the same eight (11 issues): the at-limit arms trap, and the trap arms trap with `exceeded 71` where they expect `72` |

M3f reddening the trap arms too is the message literal, not a depth claim.

**Fix round (lane-1 review).** Test 1.9 (`aHiddenTextIsHiddenUnderTheProposalAuthority`)
added for the leaf site VH exposed; suite **1697**. 1.1's assertion on the hidden
`b`'s origin (0, 20) is re-worded as MetalUI's "as if shown" choice: the re-run H1
records the hidden leaf at `(0, 0) 20x20`, so the probe backs the 20×60 and `c` at
y = 40 only (`LR-DP` item 8). `Box.hidden()`'s doc gains a proposal-authority
paragraph citing `LR-DH`; `aHiddenListNoLongerAbortsAProductionProposalFrame`'s
control comment no longer describes an abort.

### 10.4 Depth re-checked at `ef48a0a`

`bisect.sh … ef48a0a debug stack padding grid custom`: controls ok; stack
**127 / 128**, padding 194 / 195, grid 155 / 156, custom 178 / 179 — identical to
§5 at `aef88ce`, so the `deepestLevel` store in `enter` costs no debug level and
72 stands. Release `stack custom`: stack **647 / 648**, custom 1021 / 1022 (§5:
653 / 654, 1037 / 1038) — six and sixteen levels lower, release only; not
governing (72 / 647 = 0.11). The doc table in `NativeLayoutRun.maxDepth` carries
§5's `aef88ce` columns.

### 10.5 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> aef88ce ef48a0a`: every control at
its recorded value (1048576, 1030498, 210027, 0, 1048576, 0, 544, 216, 0), and
**all twelve images `differing=0`, scene identical** — expected: the default
is still `.legacy`, the demo uses no `hidden()`, and the preview's native depth
(10) is far under 72.

### 10.6 Handed on

- Lane 2: the font-resolver test's report is empty (`LR-DP` item 6), and
  `OuterModifierMatrixTests`' `box.display.none` is gone as spec §5.4 said.
- `LR-DP` item 1's limitation (a hidden `Box(style:)` declaring `.stack` lowers
  as flex) — no owner needed until such a tree exists; a `MetalUILayout` field
  would close it.
- The §5 production-root depths (29 / 10 / 15) are lane 3's to re-measure (3.3).

## 11. Lane 2 — every red test made independent of the default (`LR-DG`, `LR-DI`, `LR-DO` items 1–2, `LR-DQ`)

Commit `b2abe17` (tests only: `git diff --quiet eb8ddff b2abe17 -- Sources`
succeeds), then this record, the spec note and `LR-DQ`. Default authority
unchanged (`.legacy`). Every mutation below was taken on a clean tree at
`b2abe17`, restored with `git checkout -- Sources Tests`, `git status --short`
empty after each.

### 11.1 Red before (entry, at `eb8ddff` with the instrument applied)

`git apply docs/probes/stage-6b-flip-instrument.patch` (clean) at lane 1's HEAD,
full unfiltered run: **`Test run with 1697 tests in 3 suites failed after 91.372
seconds with 300 issues`**, **85 tests red**, **0** `SIXB-WOULD-TRAP` lines (lane
1's fold took the two aborting `MeasurePerformanceTests` rows and the RT row's
trap away; the RT row stayed red on its `calls == 40` control). The 85 = 12 X +
2 D + 3 N9 + 54 RP + 2 CSS-structure + 7 CSS-style + 3 CSS-text + 1 RP+CSS-frame
+ 1 RT (`LR-DQ` item 1 for 12 X). Issues per red test (the failure lines are in
the lane's log; each is the literal the re-spelling moved or the pin kept): RP —
`AXEmitSiteTests` 8 + 1; `AXNodeTests` 1; `AccessibilityTreeTests` 3;
`AnimationTests.hoverAndFocusFade…` 3; `BackgroundChainTests` 15 + 5;
`DecorationPaintTests` 3/1/1/1/1/3/1/5/4; `DisabledTests` 1/2/1/4/11/1;
`EnvironmentTests.theSpaceKey…` 1; `FrameDecorationInteractionTests` 4/1/7/1/4;
`FrameLoopTests` 4 + 4; `GlyphEmitterTests` 1 + 40; `HitRegionTests` 7/1/1/1/4/1;
`InputDispatchTests` 1/1/4/2/2/2/1/1/8/1; `LayoutAuthorityTests.theElementBoundsLog…`
1; `OuterModifierMatrixTests` 1/2/3; `PointerStatePaintTests` 1 + 1. CSS/N9 —
`everyRegisteringSiteAnimatesItsStyle` 10, `everyOuterModifier…` 8,
`aComponentsFrameCarries…` 4, `aContentShapeOnAFrameLayerInsets…` 7, the two
`EnvironmentTests` measure rows 1 each, the three N9 exit tests 2 each. The 21
P-6b rows were green (pinned); their red is §38 A2's with the pin removed, and
M2c (below) re-reads it on six of them.

### 11.2 After

- **At the inherited default (`.legacy`)**: `swift build --build-system native
  --build-tests` 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
  unfiltered `swift test --build-system native --no-parallel`: **`Test run with
  1698 tests in 3 suites passed after 88.372 seconds`** (1697 + 2.1),
  `FR-J no-argument frame: succeeded=true` in the log.
- **With the instrument applied**: **`Test run with 1698 tests in 3 suites failed
  after 87.626 seconds with 39 issues`** — red exactly the 12 X
  (`aContainersReportLists…`, `aCustomElementsLegacyRegistrationTraps…`,
  `aDeprecatedRegistrarStillLaysOut…`, `aLeafWithTwoUnlowerableFields…`, the four
  `aLegacySpelled…AbortsAProductionProposalFrame`, `anAbsoluteBoxOutsideADeferred…`,
  `aPresentationTraps…`, `aRootFieldWithNoLoweringTrapsInAProductionWindow`,
  `aSiteThatSkipsItsOwnCheck…`) and the 2 D (`aFrameAndAWindowDefaultToTheLegacyAuthority`,
  `aWindowBuildsEveryFrameUnderItsLayoutAuthority`); **0** `SIXB-WOULD-TRAP`
  lines. Patch reverted; `git apply --check` still clean at `b2abe17` (the lane
  edited files the patch touches, never its hunks).
- `grep -rn "LayoutAuthority = \.legacy" Tests` still reads the thirteen helper
  defaults (lane 3's), no new one. Goldens: `git diff --name-only aef88ce HEAD --
  'Tests/**/*.json'` empty.

### 11.3 The dispositions, by recipe

- **R-centre (28 tests, `.proposal` passed, literals by `(W − w) / 2` with
  `roundLayout`'s half-away rounding where odd):** `InputDispatchTests` 9
  (`aClickInside…`, `aClickOutside…`, `aHandlerRegisteredOnFrameN…`,
  `aNestedHandlerWinsOverItsContainer…`, `…ContainingStackToo`,
  `aPressThatLeavesTheElement…`, `onlyABoxWithAHandler…`, `onClickIsLive…`,
  `aDispatchedClick…`); `HitRegionTests` 6; `DecorationPaintTests` 2
  (`aFocusRingOutranks…`, `everyDecorationPaintingSiteHonours…`);
  `BackgroundChainTests` 2; `AXEmitSiteTests` 2 (300² frame: 41×23 at (130, 139),
  … the inner layer at (130, 139)); `AXNodeTests` 1 ((130, 140)); 
  `AccessibilityTreeTests.aNodeInsideAScrolledScrollView…` (x 90 only);
  `AnimationTests.hoverAndFocusFade…`; `HitboxTests` 3 (the root is the probe);
  `FrameSizingTests.aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` (+ (120, 80)).
- **R-fill (43 tests, green on both authorities):** the rest of the 54 RP and 19
  P-6b, minus item 3's two — including the `inFilledRow` helpers
  (`DecorationPaintTests`, `FrameDecorationInteractionTests`) beside the unchanged
  `inRow`, and three P-6b tests that loop over both authorities
  (`chainedLegacyFrames…`, `aLegacyFrameProposesItsWidth…`,
  `modifierOrderChanges…`; `LR-DQ` item 5). (`b2abe17`'s subject line says "17
  CSS/N9 pins"; the count is 20, as below.) The P-6b custom leaves
  `HitboxTests.HitboxProbe` and `EnvironmentTests.ClickCounter` became Dual
  (`declaredSizeNativeLeaf` under the proposal authority).
- **Greedy frame (2):** the `FrameLoopTests` resize pair (`LR-DQ` item 3).
- **Recipe disagreements** (`LR-DQ` item 4), predicted → used: fill → centre for
  `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` (60×60 root),
  `onClickIsLiveOnEveryConformerThatCanRegisterOne`,
  `everyHandlerRegisteringSiteHonoursAllowsHitTesting`,
  `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`,
  `hoverAndFocusFadeThroughTheSameEffectiveColourPath` (all 40×40 or 56×56 roots),
  `hoverResolvedThroughARealRenderHasNoLag`, `activeIsSetOnMouseDownAndHeldUntilMouseUp`,
  `aPressThatLeavesTheHitboxAndReturnsStaysActive` (a `HitboxProbe` root),
  `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` (a `ScrollView` root);
  centre → fill for `aDisabledScrollViewStillScrollsOnTheWheel` (a `Row` root);
  fill → neither for `alignItemsAndAlignSelfBothReachTheEngine` and
  `hiddenAfterASingleChildLegacyFrameStillHidesTheElement` (`LR-DQ` item 2);
  fill → greedy frame for the two `FrameLoopTests`.
- **Pinned `.legacy` (20 tests, each with an owner in its doc):** §5.4's 16 (7b;
  the three N9 rows 9), the two of `LR-DQ` item 2 (7b), and §5.5's two tokenizer
  tests (9, their own reason). The font-resolver test runs at the helper default
  with `reportsUnlowerableFields: true` and each render's report asserted equal to
  `demoLikeRowsReport(frame.layoutAuthority)` (empty).
- **Test 2.1** `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`
  (`AnimationTests`), its doc carrying the map (`LR-DQ` item 7). Green on arrival
  with its hand-derived numbers; its red-before is its mutations.

### 11.4 Mutations

M2a–M2e over the instrument; M2f–M2h2 at the default (2.1 passes `.proposal`
itself). Each a full unfiltered run.

| id | mutation | reddened |
|---|---|---|
| M2a | `computeRootLayout` places the native root top-leading at its answer (C3: measured, then centred in a container of its own answer's size) | 88 tests, 269 issues: the 14 X/D, **all 28 R-centred tests**, **no R-filled one**, and 46 existing proposal tests that read `CN-J` (`aNativeRootIsCentredAtItsAnswer`, `aGridRootIsCentredAtItsAnswer`, `theTopmostOfTwoOverlappingHandlersRuns`, `aPressOnOneElementReleasedOnAnotherIsNotAClick`, `aPressReleasedOverSomethingCoveringItIsNotAClick`, `hoveringOneClickTargetDoesNotHoverItsSibling`, the `hStack…`/`vStack…`/`nativeOverlay…`/`nativeBackground…`/`onTap…`/`aProposalScrollView…` rows and the rest of the list in the lane log) |
| M2b | the native root placed at the window rect (C2, `computeNativeLayout(… in:)`) | 81 tests, 240 issues: the 14 X/D, **20 of the 28** R-centred tests — not `aClickInsideTheBoundsRunsTheHandler`, `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne`, `aNestedHandlerWinsOverItsContainingStackToo`, `aPressThatLeavesTheElementAndReturnsStillClicks`, `activeIsSetOnMouseDownAndHeldUntilMouseUp`, `aPressThatLeavesTheHitboxAndReturnsStaysActive`, `hoverAndFocusFadeThroughTheSameEffectiveColourPath`, `hoverResolvedThroughARealRenderHasNoLag` (centre readings, `LR-DQ` item 6) — no R-filled one, and 47 existing proposal tests |
| M2c | one R-filled fixture per file with its added sizing (or greedy frame, or `inFilledRow`) removed — 16 files at once | exactly those 16 beyond the X/D: `aVanishingIfBetweenPressAndRelease…`, `aBorderIsPaintedInside…`, `theGateReadsTheEnvironmentValue…`, `aBackgroundBeforeOrAfterALegacyFrame…`, `legacyPaddingAccumulates…`, `aHoveredBoxPaintsItsHoverBackground`, `paintWrapsAtTheWidthLayoutMeasuredAt…`, `theSpaceKeyBindingSwapsTheTheme…`, `theElementBoundsLogRecordsTheRoot…`, `resizingTheWindowDirties…`, `aComponentInsideAComponentFlattens…`, `childrenAreRegisteredAndLaidOutInSourceOrder`, `chainedLegacyFramesAgree…`, `activeSurvivesAFrameBoundary`, `changingALayersValueKeeps…`, `modifierOrderChangesSize…` (76 issues) |
| M2d | every `.legacy` pin the lane owns removed together (the helper-level pins in `observe`, `styleOfRoot`, `textMeasure`; the per-call and per-`Frame` ones) | 19 beyond the X/D, 120 issues: §5.4's 16, `alignItemsAndAlignSelfBothReachTheEngine`, `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`, `aColdFrameCreatesAtMostOneLineBreakTokenizer`. **Not** `aWarmFrameTokenizesEachDistinctStringAtMostOnce` — vacuous at `.proposal` (`0 <= 40`, `LR-DQ` item 9) |
| M2e | the root fold removed (`reportUnconsumedLoweredItems`' `node == root` arm made unreachable) | 4 beyond the X/D, 48 issues: `aWarmFrameReachesTheUncachedFontResolverZeroTimes` (its exact-report assertion, 2 issues — red, not an abort), `aListsWorkIsTheSameFor160RowsAsFor40`, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `aRootsMinimumAndMaximumFoldIntoItsDeclaredSize` |
| M2f | the inner `ModifiedElement` layer lowered from its declared style (`lowerLegacyLayer` handed the pre-`animated` style) | **only** 2.1 (arm (a), both lines: the outer layer's size depends on the inner's padding) |
| M2g | the same for the outermost layer | 2.1, `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries`, `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle`, `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` (9 issues) — the outermost call was pinned already |
| M2h | the lowered `ScrollView`'s content `animated(` call dropped | 2.1 (arm (b)), `aLoweredScrollViewKeepsItsTwoAnimationSlots`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` (13 issues; the others count the `$anim-content` slot) |
| M2h2 | the call kept, `lowerLegacyNode` handed `declaredContent` | **only** 2.1 (1 issue) — the value read was unpinned before 2.1 |

### 11.5 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> aef88ce b2abe17`: every control at
its recorded value (1048576, 1030498, 210027, 0, 1048576, 0, 544, 216, 0), and
**all twelve images `differing=0`, scene identical** — the lane changed no
`Sources/` line and the default is still `.legacy`.

### 11.6 Handed on

- Lane 3: the flip's first-commit reading is still exactly the two D tests (the
  12 X are green again once traps are fatal). `Frame.defaultLayoutAuthority` may
  replace the explicit `.proposal` arguments of the 28 R-centred tests, or leave
  them. The two `LR-DQ` item-2 pins and the 18 other pins carry their owners.
- The Record phase: `LR-DQ` item 1's 12 (not 14) wherever the spec or plan carries
  "14 X".

## 12. Lane 3 — the switch, the exit test, the demo, pixels (`LR-DF`, `LR-DJ`, `LR-DK` item 2, `LR-DL`, `LR-DR`)

Commits: the flip `58e4111`; red-first tests `27c9f52`; implementation `3d4f5d8`;
pixel harness `5f0b4eb`; then this record, the spec note and `LR-DR`. Every
mutation below was applied to a clean tree at `5f0b4eb`, restored with `git
checkout -- Sources Tests`, `git status --short` empty after each; each a full
unfiltered `swift test --build-system native --no-parallel`.

### 12.1 The flip (`58e4111`)

`Frame.defaultLayoutAuthority: LayoutAuthority = .proposal` (internal), read by
`Frame.init`'s default and `Window.layoutAuthority`'s initial value;
`makeFakeWindow`'s `layoutAuthority` is `LayoutAuthority? = nil` (nil leaves the
window's default); the twelve file-local helper defaults read
`Frame.defaultLayoutAuthority`. `grep -rn "LayoutAuthority = \.legacy" Tests Sources`
reads empty afterwards. Full run: **`Test run with 1698 tests in 3 suites failed
after 87.925 seconds with 3 issues`** — exactly the two D tests:

- `aFrameAndAWindowDefaultToTheLegacyAuthority` — `LayoutAuthorityTests.swift:114`
  `frame.layoutAuthority == .legacy`, `:119` `window.layoutAuthority == .legacy`;
- `aWindowBuildsEveryFrameUnderItsLayoutAuthority` — `:141` `log.values == [false, true, false]`.

Rewritten in `27c9f52`: the first renamed `aFrameAndAWindowDefaultToTheProposalAuthority`
(`Frame.defaultLayoutAuthority == .proposal`, a bare `Frame` and a default
`makeFakeWindow` window read it, diagnostics and bounds off); the second writes
`.legacy` then `.proposal` and reads `[true, false, true]`.

### 12.2 Red first (`27c9f52`)

`RootSwitchTests.swift` (3.1–3.3), with `Frame.LegacyRootLayoutCounter` /
`Frame.$legacyRootLayoutCounter` and `Window.lastNativeLayoutDeepestLevel`
declared but never bumped or captured. Filtered `RootSwitchTests|LayoutAuthorityTests`,
15 tests, 22 issues:

- `noProductionFrameReachesTheLegacyEngine` — `RootSwitchTests.swift:143`
  `control.count == frames`, six times (each `.legacy` demo arm read 0);
- `everyProductionRootsDeepestNativeLevelIsMeasured` — `:205` `deepest == expected[root.name]`
  and `:206` `deepest > 0 && deepest < NativeLayoutRun.maxDepth`, on all eight roots;
- `aHuggingLegacyRootIsCentredInAProductionWindow` green on arrival (spec §8:
  its red is M2a, §12.5); the two rewritten D tests green.

### 12.3 Implementation (`3d4f5d8`)

- `computeRootLayout`'s legacy branch bumps `Frame.legacyRootLayoutCounter` (a
  `@TaskLocal`, `nil` in production). No lock: main-actor only (`LR-DR` item 4).
- `Window.lastNativeLayoutDeepestLevel` copies the frame tree's value after each
  frame; `LayoutTree.lastNativeLayoutDeepestLevel` became `package private(set)`
  for it (`LR-DR` item 3). A new stored property on the public `Window`, so the
  gate was taken after `swift package clean` (§12.7).
- **The demo re-spelling (`LR-DJ`)**: the list row's inner `Box` gains
  `.height(Pixels(28))` after `.flexGrow(1)` and before `.padding` (arm H's
  position); the `rowHeight` comment above it, which said declaring the height
  would be a redundant literal, is rewritten to say why it is now declared.
- **3.3 measured**: before the re-spelling the demo read 29 in all six
  roots (1024² and 920×560, modal off/on, animation on); after it, **30** in all
  six. Preview 10. The `List` root (`ScrollView { List(200 rows) }`, the demo's
  row spelling) **16**; with its `.height(Pixels(28))` line removed, 15 (the
  design's 15, whose fixture had no declared height).
- `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` re-derived. Red
  before (the re-spelling alone, full run 1701 tests, 2000 issues, this test only):
  `LoweringCorpusTests.swift:799` `innerGot?.1 == bounds(252, py, 396, 16)` and
  `:811` `textGot.1 == bounds(252, py, …, 16)`, 1 000 issues each (500 rows × two
  modal states). Now the inner `Box` is 396×28 and its `Text` at `py + 6` on the
  lowered side; part 2b's doc says X9 no longer reaches the rows. No other
  `demoContent()` reader reddened: `LoweringItemTests`' paragraph copy and
  `PresentationWindowTests` stayed green.
- Full run: **`Test run with 1701 tests in 3 suites passed after 90.692 seconds`**.

### 12.4 Mutations M3a–M3d

| id | mutation | reddened |
|---|---|---|
| M3a | `Frame.defaultLayoutAuthority` back to `.legacy` | 5 tests, 34 issues: `aFrameAndAWindowDefaultToTheProposalAuthority` (3), `aWindowBuildsEveryFrameUnderItsLayoutAuthority` (1), `noProductionFrameReachesTheLegacyEngine` (15 — the eight production arms' counts and authority), `aHuggingLegacyRootIsCentredInAProductionWindow` (1, the default arm), `everyProductionRootsDeepestNativeLevelIsMeasured` (14 — seven roots read 0; the preview reads 10 under either authority). Nothing else: lane 2 made every other test independent of the default |
| M3b | the counter bump removed | **only** `noProductionFrameReachesTheLegacyEngine` (6 — the six `.legacy` control arms) |
| M3c | `Window.lastNativeLayoutDeepestLevel` not captured | **only** `everyProductionRootsDeepestNativeLevelIsMeasured` (16) |
| M3d | `paddedAndSized` wraps every lowered node in one more zero native padding | 10 tests, 29 issues: `everyProductionRootsDeepestNativeLevelIsMeasured` (7 — the six demo roots and the `List`; the native preview is untouched), `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (3), `aLoweredChainAtTheNativeDepthLimitLaysOut` (2), `aLoweredItemChainWithFourWrappersPerLevelAtTheNativeDepthLimitLaysOut` (2), `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut` (2), `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork` (3), `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex` (1), `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork` (3), `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox` (2), `theCentringDefaultOfRowAndColumnStretchesNothing` (2) |

### 12.5 M2a at the new default (3.2's red)

`computeRootLayout` runs the native root once centred in the window, then again
centred in a container of its own answer's size at the origin (top-leading, C3).
**75 tests, 231 issues**, including `aHuggingLegacyRootIsCentredInAProductionWindow`
(1 — the production arm; its `.legacy` arm never reaches the native branch):
`aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` (1), `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds` (1), `aClickInsideTheBoundsRunsTheHandler` (1), `aClickOutsideTheBoundsDoesNotRunTheHandler` (1), `aClickOverABackgroundAndItsPrimaryReachesThePrimary` (1), `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints` (1), `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` (5), `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` (1), `aContentShapeWithoutAClickHandlerRegistersNothing` (1), `activeIsSetOnMouseDownAndHeldUntilMouseUp` (1), `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` (8), `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI` (6), `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler` (4), `aFocusRingOutranksAHoverBorderAndABorder` (1), `aGridRootIsCentredAtItsAnswer` (2), `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne` (2), `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse` (1), `aHuggingLegacyRootIsCentredInAProductionWindow` (1), `aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent` (1), `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` (9), `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` (1), `aNativeRootIsCentredAtItsAnswer` (7), `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout` (3), `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` (4), `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` (2), `aNestedHandlerWinsOverItsContainingStackToo` (2), `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds` (1), `anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified` (1), `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne` (1), `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified` (1), `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` (3), `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` (1), `aPressOnOneElementReleasedOnAnotherIsNotAClick` (1), `aPressReleasedOverSomethingCoveringItIsNotAClick` (1), `aPressThatLeavesTheElementAndReturnsStillClicks` (1), `aPressThatLeavesTheHitboxAndReturnsStaysActive` (3), `aProposalLayoutContainerRendersThroughTheFramePipeline` (9), `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis` (4), `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis` (4), `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent` (3), `aProposalTextInAStackIsShapedOncePerDistinctWidth` (2), `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer` (1), `aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild` (1), `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild` (1), `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (6), `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState` (1), `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` (4), `chainedNativeFramesPreserveTheirDeclarationOrder` (2), `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour` (15), `everyBackgroundPaintingSiteHonoursHoverAndFocus` (5), `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` (5), `everyHandlerRegisteringSiteHonoursAllowsHitTesting` (1), `everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads` (29), `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer` (4), `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal` (1), `hoverAndFocusFadeThroughTheSameEffectiveColourPath` (3), `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` (2), `hoveringOneClickTargetDoesNotHoverItsSibling` (1), `hoverResolvedThroughARealRenderHasNoLag` (1), `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI` (8), `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` (2), `layoutPriorityPreservesASpacersFlexibleExpansion` (1), `nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent` (4), `nativeClipMasksOverflowingContentToItsOuterFrame` (4), `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder` (1), `nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt` (4), `onClickIsLiveOnEveryConformerThatCanRegisterOne` (8), `onlyABoxWithAHandlerRegistersAHitbox` (1), `onTapPaintsItsHoverOverlayOnlyWhenThePointerIsOverItsResolvedBounds` (3), `onTapRegistersTheResolvedNativeBoundsAsAHittableTarget` (1), `proposalLayoutFrameUsesTheTypedProposalWrapper` (1), `spacerMinimumLengthSurvivesAConstrainedStackProposal` (1), `theProposalModifiersAcceptWhatTheKernelAccepts` (1), `theTopmostOfTwoOverlappingHandlersRuns` (2), `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` (2).

### 12.6 Pixels — `compare.sh <scratch> aef88ce 5f0b4eb`, fourteen images

The harness (`5f0b4eb`) adds `prod-default-light` and `prod-modal-light`, the
demo at 920×560 (`LR-DO` item 3; `LR-DR` item 6 for how). Controls at `aef88ce`,
every one at its recorded value: light vs dark 1048576; default vs modal
1030498; default vs animation 210027; f0 vs f3 0; preview light vs dark
1048576; chrome legacy vs proposal 0; distinct 544 / 216; indicator rects 0; new:
prod default vs modal 491923, distinct `prod-default-light` 529.

| image | differing | bbox | scene |
|---|---|---|---|
| default-light-f0 / -f3, default-dark-f0 / -f3 | 168380 each | (92,113)–(987,1007) | differs |
| modal-light / modal-dark | 172126 / 172105 | (92,113)–(987,1007) | differs |
| animation-light / animation-dark | 341608 / 341606 | (135,113)–(977,1007) | differs |
| preview-light / -dark, chrome-legacy / -proposal | **0** | — | identical |
| prod-default-light | 95649 | (84,113)–(880,543) | differs |
| prod-modal-light | 100745 | (84,113)–(880,543) | differs |

The twelve square images read **exactly** §4's arm H column (arm G plus the
re-spelling), so the X9 row (15 392 row-label glyphs y − 6) is gone. **Every
delta, from the `.scene` dumps** (rects and glyphs paired by index; counts equal
on both sides in every image):

- `default-light-f0` (1024²): rects `(+100, 0, 0, 0)` × 507 (500 rows — their
  clip mask moves with them — and 7 main-pane rects), `(0, 0, +100, 0)` × 5,
  `(+100, 0, −100, 0)` × 1, identical × 5 (root (0, 0) 1024×1024 on both sides).
  Glyphs `(+100, 0)` × 15 509; the paragraph's re-wrap groups `(+194, 0)`,
  `(+294, 0)`, `(+295, 0)`, `(−548, +16)`, `(−652, +16)` and their ±1-width
  sub-pixel variants; "Count 0" `(+101, 0)` × 6; 7 identical. **55, its re-wrap,
  the rounding.**
- `modal-light`: the above plus the card `(0, −8, 0, +16)` and 86 glyphs
  `(0, −8)`. **C.**
- `animation-light`: rects `(+181, +16, 0, 0)` × 500, `(+181, 0, 0, 0)` × 6,
  `(0, 0, +181, 0)` × 5, `(+181, 0, −181, 0)` × 1, `(+181, +16, 0, −16)` × 1 (the
  viewport). Glyphs `(+181, +16)` × 15 392 (row labels), `(+181, 0)` × 102, the
  re-wrap groups (`+338`, `−269`, `−99`, `+517`, `−437`, …) and **`(+180, 0)` × 2**
  — the "−" button's glyph at the animated width, a one-point centring round
  like "Count 0"'s (55's rounding), not listed by name in spec §9.
- `prod-default-light` (920×560): rects `(+108, +16, 0, 0)` × 500 (rows),
  `(+108, 0, 0, 0)` × 6, `(0, 0, +108, 0)` × 5 (sidebar 88 → 196),
  `(+108, 0, −108, 0)` × 1 (main pane), `(+108, +16, 0, −16)` × 1 (viewport
  89 → 73), identical × 5 (root (0, 0) 920×560 on both). Glyphs `(+108, +16)` ×
  15 392, `(+108, 0)` × 104 (including "Count 0" — no rounding group at this
  size), re-wrap groups `(+242, 0)`, `(+351, 0)`, `(−291, +16)`, `(−391, +16)`,
  `(−510, +16)` and ±1-width variants. **55 and its re-wrap; the body is 431
  tall on both sides — no vertical compression.**
- `prod-modal-light`: the above plus the card `(0, −8, 0, +16)` (360×90 →
  360×106 at y 235 → 227) and 86 glyphs `(0, −8)`. **C.**

No region outside 55, its re-wrap, C and the one-point rounds. Looked at: the
920×560 PNGs before and after render the whole demo, the row labels centred in
their rows after the switch.

### 12.7 The gate

`swift package clean`, then `swift build --build-tests` (default build system):
exit 0, 0 `error:`, 0 `warning:`. `swift package clean`, then `swift build
--build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's
deprecation notice; unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1701 tests in 3 suites passed after 92.128 seconds`**, `FR-J
no-argument frame: succeeded=true` in the log. Goldens: `git diff --name-only
aef88ce HEAD -- 'Tests/**/*.json'` empty; 97 in `Tests/MetalUILayoutTests`.
Guards 78, unchanged (no guard added: `LR-DR` item 3).

### 12.8 The 100 000-row test, once, under the new default

`METALUI_RUN_100K_LIST_TEST=1 swift test --build-system native --no-parallel
--filter aListsWorkIsTheSameFor100kRowsAsFor500` (debug; the test is
parameterised over both authorities, so the default does not choose its arms):
passed, 2 cases, 67.411 s; cold frame **39.28 s legacy, 27.36 s proposal**
(CLAUDE.md's 2026-09-23 debug reading: 37.16 / 24.98).

### 12.9 The screen

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at lane close: `CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1`, `displayActive main: 0`. **The real-window capture
(`docs/probes/window-capture/capture.sh <scratch> aef88ce <HEAD>`) was not run
and is owed to the human** (`LR-DM`).

### 12.10 Handed on

- The human: the real-window capture, and the looks §03's re-opened rows name
  (`LR-DM`) — the sidebar at 196, the animation at 320, the modal card, the list
  rows' labels now centred.
- The Record phase: CLAUDE.md's counts (1701 / 97 / 78), the demo's deepest
  level (30, where CLAUDE.md says "measured at 18"), `Frame.defaultLayoutAuthority`
  and the `grep -rn "LayoutAuthority = \.legacy" Tests` check (`LR-DF` item 4),
  the "`LayoutAuthority.proposal` in production" inert row deleted, and the
  fourteen-image harness.

## 13. Stage close

| exit criterion (parent spec §4.1 row 6b) | reading |
|---|---|
| `Window`'s default authority becomes `.proposal` | `Frame.defaultLayoutAuthority` (`LR-DF`); `Frame.init`'s default and `Window.layoutAuthority`'s initial value both read it, one constant |
| every red test of record §38 §4's classification table owned by 6b resolved | the 92-row table (§3) disposed by name in `LR-DI`: 14 X untouched (green once traps are fatal again), 2 D rewritten, 75 RP/P-6b re-spelled to `LR-DG`'s rule, 5 AV closed by lowering `hidden()` (`LR-DH`), the root's px/rem min/max folded (`LR-DI` item 4 amended by `LR-DO` item 1), 12 CSS + 1 RP+CSS-frame + 3 N9 + 1 RT pinned `.legacy` with a named owner (7b or 9) |
| the demo re-spelled for the semantics stage 2 changed, each pixel change probe-backed and named | one re-spelling (`.height(Pixels(28))` on the list row's inner `Box`, `LR-DJ`); every one of the fourteen images' deltas falls in 55, its re-wrap, cause C or a one-point centring round (§4, §12.6) — none outside |
| root placement ruled (divergence 4 vs `CN-J`) | `CN-J` kept, unchanged (`LR-DG`); divergence 4 stays a legacy-authority-only row, retired with the CSS engine by 7b |
| the native depth limit re-bisected in release and re-measured on every production root | `NativeLayoutRun.maxDepth` 88 → 72 (`LR-DK`; debug governs, release headroom 9×); production roots re-measured at the new default: demo 29 → 30 after the re-spelling, preview 10, `ScrollView { List }` 15–16 (§5, §12.3) |
| the human-verification rows that read demo layout re-opened | owed to this Record phase (§18, below); `LR-DM` |
| real-window captures | not taken at any lane — `CGSSessionScreenIsLocked = 1` every time it was checked (§7, §12.9); owed to the human (`LR-DM`) |
| exit test `noProductionFrameReachesTheLegacyEngine` | green at `3d4f5d8`; `demoContent()` and `nativeLayoutPreviewContent()` (`MetalUIDemoContent`, `LR-S`) plus a `List`, all six/eight production roots, `Frame.legacyRootLayoutCounter` reads 0 in every `.legacy`-authority-free run |
| suite count | 1688 → **1701** (+13); goldens 97 unmoved; guards 78 unmoved |

## 14. What landed — the stage

- **The switch is one constant.** `Frame.defaultLayoutAuthority: LayoutAuthority
  = .proposal` (internal, `LR-DF`), read by `Frame.init`'s default and
  `Window.layoutAuthority`'s initial value; no public spelling gained
  (`aPlainImportCannotChooseTheLayoutAuthority` stays green); production frames
  keep trapping on an unlowerable field (`reportsUnlowerableFields` stays
  `false` in `Window`). The thirteen file-local test-helper `.legacy` defaults
  §38's instrument missed (§2) now read `Frame.defaultLayoutAuthority`;
  `grep -rn "LayoutAuthority = \.legacy" Tests Sources` reads empty.
- **`hidden()` lowers under the proposal authority** (`LR-DH`, lane 1): the
  three `frame.hiddenNodes.insert(node)` call sites (leaf, node, modifier
  layer) are read by `Element.paintGroup`/`prepaintGroup`, `ModifiedElement`'s
  per-layer skip/scope and `AnyElement`'s entry gates, closing the five AV
  rows record §38 §4 carried forward. "As if shown" is MetalUI's own choice,
  not SwiftUI's: a hidden leaf's rect is `(0, 0)` at its own size, not the
  position it would have had (`LR-DP` item 8).
- **A declared root axis folds its px/rem `minSize`/`maxSize`** into the
  declared size (`LR-DI` item 4, amended by `LR-DO` item 1); an auto-axis
  min/max, a percentage, a margin or `.absolute` at the root still traps,
  each named and pinned through a production `Window` (tests 1.7, 1.8).
- **Root placement is unchanged**: `computeRootLayout`'s native branch still
  centres the root at its own answer (`CN-J`, `LR-DG`); the M2a (top-leading)
  and M2b (window-rect) mutations each redden dozens of existing proposal
  tests and are rejected. Divergence 4 (the legacy engine's top-left,
  window-filling root) survives as a legacy-authority-only row, retired with
  the CSS engine by 7b.
- **`NativeLayoutRun.maxDepth` moves 88 → 72** (`LR-DK`), the first release
  re-bisection alongside a debug one: debug governs (72/127 = 0.57 of the
  smallest debug ceiling, the one-child stack), release's smallest ceiling
  (653) is 9× headroom. `LayoutTree.lastNativeLayoutDeepestLevel`
  (`package private(set)`, `LR-DR` item 3) and `Window.lastNativeLayoutDeepestLevel`
  copy the run's peak so a production root's depth is measured, not estimated
  (`LR-DK`, `LR-DL`).
- **The demo re-spelling** (`LR-DJ`): the list row's inner `Box` gains
  `.height(Pixels(28))`, closing the one pixel group (X9, the row labels'
  vertical centring) that the switch alone would have moved outside SwiftUI's
  own answer. The demo's deepest native level moves 29 → 30 across all six
  roots after it.
- **The exit test and its counter** (`LR-DL`): `Frame.legacyRootLayoutCounter`,
  a `@TaskLocal` bumped only in `computeRootLayout`'s legacy branch (main-actor
  only, no lock), reads 0 across `demoContent()`, `nativeLayoutPreviewContent()`
  and a `List`, each driven through a real `Window`.
- **Every other red of record §38's 92-row table was made independent of the
  default** (lane 2, `LR-DG`'s fixture rule, `LR-DQ`): 28 tests re-derive their
  literals as `(W − w) / 2` and run `.proposal` (R-centre); 43 pass under
  either authority once given the window's extent explicitly on an `auto` root
  axis (R-fill); 2 keep a greedy frame; 20 are pinned `.legacy` with a named
  owner (16 CSS/7b, 3 N9/9, 1 RT/9) plus 2 more `LR-DQ` item 2 found (fill →
  neither once the root fold changed their reachable path); one new test,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, maps
  every `animated(` call the lowering makes, closing `LR-DO` item 2's hazard
  seven proposal tests exposed.
- **No production `Sources/` line outside the switch, the counter, the depth
  constant and the root fold moves.** The demo re-spelling is the one
  `MetalUIDemoContent` line.

## 15. Tests, red runs and mutations, in one place

**Tests**, 1688 → **1701** (+13, all new files/tests, no existing `@Test`
removed): lane 1 +9 (`HiddenLoweringTests` 6, `RootFieldLoweringTests` 2, and
1.9 added in the fix round), lane 2 +1
(`everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`), lane 3
+3 (`RootSwitchTests` 3.1–3.3). Guards 78 and goldens 97 unmoved by any lane
(`LR-DR` item 3: no new guard).

**Red runs** — none of the three lanes is a red-first suite run in the usual
sense; each lane's own red-before is documented where it happened: the entry
measurement (§2–§3, arm G2, 92 red under the flip+instrument, not a red-first —
it is the stage's baseline); lane 1's red-before at `403d6d6` (§10.1, in-process
and child-process aborts, at-limit prints hand-derived against 72); lane 2's
entry red at `eb8ddff` with the instrument applied (§11.1, 85 tests, 300
issues); lane 3's red-first `RootSwitchTests` at `27c9f52` (§12.2, 15 tests, 22
issues) and the flip commit `58e4111` alone (§12.1, exactly the 2 D tests, 3
issues).

**Mutations**, each committed first, restored from a copy, full unfiltered
suite, `git status --short` clean after — full tables in §10.3 (lane 1: M1a–M1j,
VH, M3e, M3f), §11.4 (lane 2: M2a–M2e over the instrument, M2f–M2h2 at the
default) and §12.4–§12.5 (lane 3: M3a–M3d, M2a re-taken at the new default).
Every one reddens exactly its predicted set, with two findings recorded against
the practice: **M1b** (§10.3) is a broken instrument for 1.1 — its intended
target (the leaf's hidden branch) is masked by `lowerLegacyLeaf`'s own 0×0
answer, so **M1b2** (both hidden branches) is the mutation that actually
separates; **VH** (§10.3, `LR-DP` item 7) reddens nothing until test 1.9 is
added, then reddens exactly it — a leaf-site gate the suite had never pinned.
Lane 3's **M2a**, re-taken at the new default with no instrument (§12.5),
reddens 75 tests including 20 of the 28 R-centred ones (the other 8 read a
centre answer at both defaults and cannot separate, `LR-DQ` item 6) — the same
mutation lane 2 read as 88-red under the instrument (§11.4), the 13-test gap
being the X/D rows the instrument keeps green-but-non-fatal.

## 16. Demo comparisons

Every lane's twelve-image (design, lane 1, lane 2) or fourteen-image (lane 3)
offscreen comparison (`docs/probes/demo-pixels/compare.sh <scratch> aef88ce
<commit>`) reads every control at its recorded value. Design (`947cdd5`, arm
H) and lane 3 (`5f0b4eb`) read the flip's real deltas — eight (then, with the
two production-size images, ten) of the images differ, none outside four named
causes (**55**: the sidebar/animation width SwiftUI answers where CSS shrank
it; **55's re-wrap**: the paragraph breaking narrower; **C**: the modal card
measured at the lowered column's width; **the one-point centring round**: a
half-pixel case in `roundLayout`) — see §4 and §12.6 for the full delta
breakdown, rect by rect and glyph group by glyph group. Lane 1 (`ef48a0a`) and
lane 2 (`b2abe17`) each read **`differing=0`, scene identical in all twelve**:
neither changed a `Sources/` line reachable at the still-`.legacy` default.
The lock probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at
every measurement in the stage (design, both critic-round checks, and all
three lanes' closes) — `docs/probes/window-capture/capture.sh` was never run;
see §18 below for what that leaves open.

## 17. Hazards and deferrals, each with an owner

- **A `.legacy` test-helper default added later is silent** unless the grep is
  re-run: `grep -rn "LayoutAuthority = \.legacy" Tests Sources` is the check
  `LR-DF` item 4 leaves behind, and it is only as good as the next person who
  runs it — §38's own instrument missed four such helpers for a whole stage
  (§2).
- **The proposal-authority `…unconsumed` trap is now a production hazard, not
  only a test one**: every `Frame`/`Window` created without an explicit
  argument now runs `.proposal`, so a lowering site that receives a
  `LoweredItem` nobody consumes traps in production, not only in
  `LayoutAuthorityTests`. Nothing in this stage's `Sources/` changes touches a
  consumption site, but a later stage that adds one inherits a live trap where
  before it was reachable only from a test that opted in.
- **`FrameSizingTests`' `render`/`widthInRow`/`nodeCount` and the two
  `ModifiedElementTests`/`ModifierCompositionProofTests` `observe` helpers
  still take the authority as a required argument** (record §38 §17,
  unchanged): a later default-authority change cannot reach their calls by
  editing a default.
- **The existing CI hazards are untouched by this stage**: `AuthorityCoverage`'s
  cross-file-order dependency, the `AccessibilityDefaultsTests` recording-order
  hazard and the `…unconsumed`-traps-a-`Window`-test hazard (record §38 §17)
  all still apply, and the last one is the more consequential now that
  production runs `.proposal` by default (above).
- **CLAUDE.md's "measured at 18" for the demo's deepest native level predates
  stages 3 and 4** (the scroll viewport and the windowed `List` add levels); the
  Record phase corrects it to 30 (§18).
- **Divergence 4 and the 12 CSS + 1 RP+CSS-frame + 3 N9 + 1 RT pinned rows**
  (33 total, `LR-DI`) are 7b's and 9's to retire, each with the owner named in
  its own doc comment — not this stage's to fix, since the CSS engine they
  read is still production's answer under `.legacy` and no production frame
  ever asks for `.legacy` again.
- **Owed to the human**: the real-window capture, and the demo-layout
  human-verification rows §03 re-opens (§18) — the sidebar now reading 196 (was
  88 at 1024²), the animation panel at 320, the modal card's height, the list
  rows' labels now vertically centred in their 28 pt row. The screen was
  locked at every check this stage took; none of these was seen on a real
  display.

## 18. Record phase (2026-09-23, PDT) — docs pass over `aef88ce..8030eef`

No file under `Sources/` or `Tests/` changed in this pass.

**Suite, re-taken.** `swift package clean`, then `swift build --build-system
native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's
`--build-system native` deprecation notice (40.58s). Unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1701 tests in 3 suites
passed after 90.779 seconds`**, one summary line, `FR-J no-argument frame:
succeeded=true deprecations=2` in the log (guards ran). Default build system,
`swift build --build-tests`: 0 `error:`, 0 `warning:` — the gate holds on both
build systems after a clean build. Goldens: `find Tests/MetalUILayoutTests
-name "*.json" | wc -l` reads **97**; `git diff --name-only aef88ce HEAD --
'Tests/**/*.json'` empty. Guards: `grep -rn "canTypecheck" Tests` reads 80 raw
hits (79 across the fifteen guard files plus `Typecheck.swift`'s declaration);
`UnitSafetyTests`' one hit is a comment, so **78** guards, unchanged, matching
CLAUDE.md's per-file list exactly (`LayoutAuthorityCompileGuards` stays 2, not
touched by this stage).

**Verdict: the stage's exit criteria (§13) all hold**, re-measured
independently of the lanes' own runs. Docs updated in this pass: `CLAUDE.md`
(counts; the `LR-` next-unused note, `LR-DF` → `LR-DS`; a new "SwiftUI
alignment" stage-6b bullet; the "layout authority… `.legacy` in production,
internal until stage 6b" sentence and every other "until stage 6b"/"not yet
ruled" sentence this stage makes false, rewritten to say production now runs
`.proposal`; the depth-guard bullet's 88 → 72 and its stale "measured at 18" →
30; the "no demo look is owed until stage 6b" sentence in the human-verification
reference row, replaced by a pointer at the rows §03 now carries; the
`LayoutAuthority.proposal` in production" declared-but-inert row deleted from
the inert-APIs reference line — verified against source with the greps above,
not copied from the lane verdicts), `AGENTS.md` (copied, `cmp` clean),
`docs/record/04-divergences.md` (divergence 4's row amended: still live, now
legacy-authority-only, owned by 7b) and `docs/record/05-declared-but-inert.md`
(the `LayoutAuthority.proposal` in production row deleted — it is inert no
longer), `docs/record/03-human-verification.md` (the demo-layout rows
re-opened, `LR-DM`), `docs/record/README.md` (the §39 row),
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md` (task 7's stage-6b
progress paragraph, appended after stage 6a's; the task's own checkbox stays
unticked — stages 7a, 7b and 8 remain), this stage's own spec's Status line
(marked delivered, Record phase noted), and `README.md` (the branch/count
line, the record-file list, the engine-replacement spec bullet).

