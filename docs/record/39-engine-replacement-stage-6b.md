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
