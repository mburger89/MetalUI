# Engine replacement, stage 7b — the non-golden CSS-engine tests retired (plan task 7)

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 7b, §8, ruling `LR-U`. Rulings `LR-EC`…`LR-EK` (critic round 1: `LR-EL`) in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Record: `docs/record/49-engine-replacement-stage-7b.md` (its §4 is the 245-row
retirement table this design commits). Instrument:
`docs/probes/stage-7b-css-engine-instrument.patch`; census:
`docs/probes/stage-7b-css-engine-census.txt`. No new SwiftUI probe (`LR-EI`:
five existing probes re-run 2026-09-24, every output line verbatim in its
header). Branch `feat/engine-stage-7b` from `41344e5`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-7b`.

**Status, 2026-09-24 (PDT): lane 1 delivered** (record §49 §6.1, `LR-EM`:
row 71 became N with a new test, so the stage's count is 1445, not 1444; M1j
re-spelled M1j′). The design paragraph below is kept as written.

**What this stage is.** Every test that uses the CSS engine **as its
subject** is retired with a row naming either the native test that asserts
its fact under the proposal engine, the CSS-only concept it dies with, or a
new proposal-authority test written first: the 187 non-golden tests left in
spec §2.6's files after 7a (`StyleTests`' 4 are kept, `LR-EE`), the 50
element tests stages 6a and 6b pinned to `.legacy` with a 7b owner, and the
three `NativeBoundaryTrapTests` that call `computeLayout(` (`LR-EF`).
Divergence 4 retires (`LR-EH`). **It does not pre-empt 8–11**: `FlexEngine`,
`computeLayout`, the legacy authority, `Frame.requestNode`/`requestLeaf`, the
legacy lowering and every test that uses the legacy authority as the *other
arm of a comparison* (199 tests, record §49 §2) stay for stage 9. **No
behaviour line of `Sources/` changes** (`LR-EG`).

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [The retirement, by family](#5-the-retirement-by-family)
6. [Lanes, and every test by name](#6-lanes-and-every-test-by-name)
7. [What must not move; the demo](#7-what-must-not-move-the-demo)
8. [Exit criteria](#8-exit-criteria)
9. [Handed on](#9-handed-on)

## 1. Baseline

At `41344e5`, measured 2026-09-24 in the worktree: `swift build
--build-system native --build-tests` (0 `error:`, one `warning:` — SwiftPM's
deprecation notice), unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1670 tests in 3 suites passed`**, the log
carrying `FR-J no-argument frame: succeeded=true`. 0 goldens, 78 guards, nine
gated tests. `grep -rn "computeLayout(" Tests` (swift files) reads **121**
lines: 117 in the eighteen §2.6 files still present, 3 in
`NativeBoundaryTrapTests`, 1 in `ElementLayoutTests` (record §49 §1).

## 2. The entry measurement

One `print` at `computeLayout`'s entry, one unfiltered run (record §49 §2):
**357 tests reach the CSS engine** — 111 in §2.6's files, 47 in the element
files this stage edits (46 of the 50 pins and `RootSwitchTests` 3.2's
`.legacy` arm), and **199 that are stage 9's**: the `.legacy` arm of every
`AuthorityCoverage` scenario, every differential lowering test, the harness's
own tests, three loops over both authorities, N9 and the deprecated
registrar's legacy half, and `MeasurePerformanceTests`' four (two
both-authority work tests, two tokenizer pins — `LR-EC` item 3 keeps them).
The census file lists all three sets; after this stage the same instrument
must read **exactly** the 199 (§8). *(The design first read 115 / 195 with
those four under C, which would have made §8 item 3 unpassable; corrected by
the critic round, `LR-EL` finding 1.)*

## 3. Decisions

| ruling | decides |
|---|---|
| `LR-EC` | the scope: which tests 7b retires, and that the 199 comparison users and `MeasurePerformanceTests` are not among them (its `LR-U` row is already met by stage 4's native work literal) |
| `LR-ED` | the five verdicts (R, D, N, T, K) and the accounting: before − removed + added = after; T and K are rows, not removals |
| `LR-EE` | `StyleTests` kept (owner stage 10); `ResolveTests` retired (`Resolve.swift` has no caller outside the CSS engine files) |
| `LR-EF` | `NativeBoundaryTrapTests`' three `computeLayout(` calls retired: the exit grep is literal, and each fact they pin is either kept from the native side or dies with `computeLayout` |
| `LR-EG` | `Sources/`: no behaviour line; comment-only edits allowed in non-CSS-only files where a comment names a retired test as a present pin; CSS-only files' comments listed, not edited |
| `LR-EH` | divergence 4 retires: its two CSS-engine pins are D rows, `RootSwitchTests` 3.2 loses its `.legacy` arm (T) |
| `LR-EI` | no new SwiftUI probe; the five cited probes re-run today |
| `LR-EJ` | three lanes by file family, in order; nothing removed before its replacements are confirmed and its N tests are green; mutation sampling per family |
| `LR-EK` | a replacement that is a differential (two-authority) test is stage 9's to re-spell, never to delete with its legacy arm |
| `LR-EL` | critic round 1: census A is 199 (C 111), lane steps remove before mutating, M1i's must-redden column corrected, N3.4's literals derived before the run, `LR-EE`'s `Resolve.swift` reason narrowed; the rejected grep dodge |

## 4. API and files

**No API.** No public, package or internal declaration is added, removed or
changed. `Sources/` may change only by comment lines (`LR-EG`), checked by
`git diff 41344e5 -- Sources | grep -E '^[-+]' | grep -vE '^(\+\+\+|---)' |
grep -vE '^[-+]\s*//'` returning nothing.

**Files deleted whole (lane 1, 17):** `Tests/MetalUILayoutTests/`
`BoxModelTests`, `StackLayoutTests`, `FreezeLoopTests`, `FlexEngineTests`,
`WrappingTests`, `AbsolutePositioningTests`, `AlignmentTests`,
`LayoutContextTests`, `MeasureNodeTests`, `FlexBaseSizeTests`,
`MeasureCacheTests`, `ResolveTests`, `IntrinsicModeTests`,
`FreezeLoopAllocationTests`, `LeafProbeShortcutTests`, `SizingFixtureTests`,
`ScrollLayoutTests` (`.swift`). Any helper another kept file uses is moved,
not copied, into the file that uses it (grep before deleting; a helper with no
remaining caller goes with its consumers, `LR-EB`'s precedent).

**Files edited:** lane 1 `NativeBoundaryTrapTests.swift` (3 tests out),
`LoweringLeafTests.swift` (N1.1 in); lane 2 `FrameSizingTests`,
`ComponentTests`, `ElementLayoutTests`, `ContainerIntegrationTests`,
`ModifiedElementTests`, `ModifierCompositionProofTests`; lane 3
`TextMeasureTests`, `EnvironmentTests`, `StackElementTests`,
`AnimationTests`, `FrameDecorationInteractionTests`,
`OuterModifierMatrixTests`, `RootSwitchTests`. **Nothing under
`Tests/PortableTests`, `Backends/`, `Tests/MetalUICrossPlatformTests` or
`Package.swift` changes** (the deleted files are in an existing target's
directory; SwiftPM picks the change up without a manifest edit).

**Every N test goes in the file whose helpers it needs** — a copied helper is
an unpinned one (CLAUDE.md "Practices"): N2.1 beside `observe` in
`ModifiedElementTests`, N2.2 beside its `observe` in
`ModifierCompositionProofTests`, N3.1/N3.2 beside a new proposal
`textMeasure` helper in `EnvironmentTests`, and so on (§6).

## 5. The retirement, by family

The row-by-row table is record §49 §4; each row names the fact, the verdict,
the family and the replacement. In summary:

- **R (112; 111 after `LR-EM`, row 71 → N)** — the fact has a proposal-engine test today. The largest
  sources: stage 7a's `GoldenReplacementFlexTests` / `GoldenReplacementStackTests`
  arms (fixed packing, gaps, distribution, cross alignment, reversal, padding
  and border, margins, grow with a cap, stacks, absolute boxes), the stage-2–5
  lowering suites (`LoweringItemTests`, `LoweringContainerTests`,
  `LoweringDistributionTests`, `LoweringStackAndLayerTests`,
  `LoweringComponentTests`, `LoweringBoxModelTests`, `PresentationLoweringTests`),
  the kernel's own suites (`NativeLayoutTests`, `NativeStackDistributionTests`,
  `NativeDepthGuardTests`, `NativeInvalidationContractTests`,
  `NativeBoundaryTrapTests`, `NativeLayoutWorkTests`), and 6b's
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`.
- **D (113)** — CSS-only concepts: wrap, percentages, the automatic minimum,
  weighted shrink and length bases, the border-box floor, `display: none`,
  flex base sizes and intrinsic queries, the CSS measure cache,
  `Resolve.swift`, sub-one grow, non-window containing blocks, divergence 4,
  and single concepts (FR-E's clamp, FR-O's both-axes rule, `CN-N`'s one-cell
  stack, divergence 48's legacy answer, …). Each names the native pin of what
  the proposal authority does instead.
- **N (11 rows, 10 new tests; 12 rows and 11 tests after `LR-EM`, N1.2)** — non-CSS facts the retired test observed
  through the legacy engine and nothing pins natively (§6).
- **T (5)** — trimmed or re-spelled, kept assertions byte-identical (§6).
- **K (4)** — `StyleTests` (`LR-EE`).

## 6. Lanes, and every test by name

Three lanes, run **in order** (agents run one at a time in this worktree),
each on disjoint files (`LR-EJ`). Each lane, in this order:

1. **Confirm every R row it owns** by reading the replacement's arm (the name
   exists — checked by script at design time — but "asserts the same fact" is
   read). An R row that does not hold becomes an N row with a finding and a
   new test named for it; the count moves by +1 and the record says so.
2. **Write its N tests** (and T edits), green, committed.
3. **Remove** its R/D/N tests (whole files or named `@Test`s), commit.
4. **Then take the family mutations below**, each on the committed tree with
   the retired tests gone (`LR-EJ`; the design first listed the mutations
   before the removal, contradicting its own table header and `LR-EJ` —
   `LR-EL` finding 2): copy the file to the scratchpad, edit, `swift build
   --build-system native --build-tests`, **full unfiltered** `swift test
   --build-system native --no-parallel`, restore from the copy, `git status
   --short` clean. Name every test each mutant reddens (not a count). **The
   replacement named in the family's row must be among them**, so it is shown
   to redden on its own, with no retired twin to redden for it. The N tests'
   own red-before mutations (M1.1, M2.1–M2.4, M3.1–M3.5) may be taken at step
   2, since nothing retired observes them.
5. Suite, both build systems, guards (`FR-J` in the log), the pixel
   comparison (§7), its record section (§6.1/§6.2/§6.3 of record §49), and its
   rulings from the next unused `LR-` letter.

A **removal check by script** closes each lane: for every row the lane owns,
`R`/`D`/`N` → no `func <name>` left in `<file>` (file **and** name —
`theCacheIsActuallyConsulted` also lives in `ShapingCacheTests`, which stays);
`T`/`K` → the test exists and every kept `#expect`/`#require` line hashes
identically at `41344e5` and HEAD; every surviving `@Test` body in an edited
file other than the T rows equals its `41344e5` text.

### Lane 1 — the engine files (Opus)

**Owns:** the eighteen files of record §49 §1 (seventeen deleted, `StyleTests`
kept untouched), `NativeBoundaryTrapTests.swift`, `LoweringLeafTests.swift`.
**Removes 190, adds 2** (N1.1, and N1.2 for row 71 by `LR-EM`): rows 1–190 of record §49 §4 (rows 191–194 are `StyleTests`'
four K rows; lane 2's are 195–231, lane 3's 232–245): `LayoutContextTests` 10, `StackLayoutTests` 22,
`AlignmentTests` 15, `FlexEngineTests` 19, `BoxModelTests` 26,
`WrappingTests` 18, `FreezeLoopTests` 20, `AbsolutePositioningTests` 17,
`MeasureNodeTests` 10, `SizingFixtureTests` 1, `FlexBaseSizeTests` 8,
`MeasureCacheTests` 6, `ResolveTests` 6, `IntrinsicModeTests` 4,
`FreezeLoopAllocationTests` 2, `LeafProbeShortcutTests` 2,
`ScrollLayoutTests` 1) and `NativeBoundaryTrapTests`'
`computeLayoutRejectsANativeRoot`, `computeLayoutCalledFromANativeMeasureClosureTraps`,
`registeringANodeDuringLegacyLayoutTraps`.

**N1.1 `anEmptyLoweredStackOrContainerAnswersZeroOnItsAutoAxes`**
(`LoweringLeafTests.swift`; replaces `anEmptyStackMeasuresZero` and
`measuringAnEmptyContainerIsZeroNotATrap`). Under `.proposal` with
diagnostics on, each of `Stack { EmptyGroup() }`, `Column { EmptyGroup() }`,
`Row { EmptyGroup() }` and `Box { EmptyGroup() }` beside a 10×10 sibling in a
`Row(gap: 0)` inside `DifferentialRoot`: its `elementBounds` rect is **0×0**,
the sibling at x 0, the report empty; the **positive control** `Stack {
EmptyGroup() }.width(Pixels(30)).height(Pixels(20))` reads 30×20 and moves
the sibling to x 30, `try #require`d to disagree with the empty arm first
(shape 15). Literals derived before the run. **Red-before, M1.1:**
`lowerLegacyLeaf`'s answer on an `auto` axis made 1 instead of 0 → N1.1
reddens (and name everything else it reddens).

**Family mutations** (each must redden the named replacement, after the
removal):

| id | family | mutation | must redden |
|---|---|---|---|
| M1a | F1 | `LayoutTree.beginLayout`'s re-entry precondition removed | `computeNativeLayoutReenteredFromAMeasureClosureTraps` |
| M1b | F1 | `setStyle`'s layout-time precondition reads a flag nothing sets (the one flag split) | `setStyleOnALegacyNodeDuringNativeLayoutTraps` |
| M1c | F1 | the kernel's depth check lets one more level through (a chain of 73 completes) | `layingOutANativeTreeDeeperThanTheLimitTraps` |
| M1d | F2 | the lowered `Stack`'s horizontal alignment factor mirrored (`1 − h`) | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`, `aStackPlacesAFixedChildAtItsAlignment` |
| M1e | F3 | `.spaceAround`'s between-spacers not doubled | `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit`, `justifyContentDistributesADeclaredMainSizesFreeSpace` |
| M1f | F4 | the lowered `Row`/`Column` hands its native stack spacing 0 instead of the declared gap | `fixedItemsPackFromTheMainStartAtTheirOwnSizesAndGap`, `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` |
| M1g | F5 | a margin lowered **inside** the aliased item frame instead of outside it | `marginsOffsetEachItemOutsideItsBorderBox`, `aMarginLowersAsPaddingOutsideTheItem` |
| M1h | F6 | the `flexWrap` diagnostic removed from `legacyContainerDiagnostics` | `everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`, `aWrapReverseContainerIsReportedByNameAsAWrappingOneIs` |
| M1i | F7 | the kernel's measure cache never hits (`measureNative` always misses) | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` (its literal `cacheHits == 51`). **Not** `nativeLayoutWorkIsPerCall`: it compares two calls to each other, both uncached under the mutant, so it stays green (`LR-EL` finding 3) |
| M1j | F7 (D pin) | a positive `flexShrink` lowered as `fixedSize` | `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` — **cannot, measured** (`LR-EM` item 3: its boxes declare their widths, so `fixedSize` around a fixed frame changes nothing); the sample is **M1j′**, a positive shrink other than 1 reported, which reddens it alone |
| M1k | F8 | the presentation lowering ignores the `right`/`bottom` insets | `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape` |
| M1l | F9 | the lowering's rem factor made 10 in place of the frame's root font size | `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` (its rem arm) |

### Lane 2 — frames, components, containers, modifier chains (Opus)

**Owns:** `FrameSizingTests`, `ComponentTests`, `ElementLayoutTests`,
`ContainerIntegrationTests`, `ModifiedElementTests`,
`ModifierCompositionProofTests`. **Removes 36** (record §49 §4 rows of those
files with verdict R, D or N): `FrameSizingTests` 12, `ComponentTests` 13,
`ElementLayoutTests` 6 (the last `computeLayout(` in `Tests/MetalUITests`
goes with `aNestedLayoutMatchesTheEngineRunDirectly`), `ContainerIntegrationTests`
3, `ModifiedElementTests` 1, `ModifierCompositionProofTests` 1. Each file's
`.legacy`-only fixture branch (`Probe`, `Leaf`, `Mark`, `LayerLeaf`,
`CountingLeaf` Dual elements) **stays** while any kept test reaches it; a
branch no kept test reaches is stage 9's with the legacy authority, not this
lane's.

**T — `legacyModifierChainsInferOneConcreteType`**: its last four lines (the
`.legacy` `Frame`, `render`, `nodeCount == 4`) removed; the stored `Row<…>`
typed value may stay as a compile-time assertion. **Red-before:** the kept
`leafChain.style.size.width` line reddens under "a `Self`-returning modifier
written after a wrapper configures the innermost layer" (`MC-C`).

**N2.1 `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`**
(`ModifiedElementTests`, beside `observe`): the retired test's chains and
oracles, `observe(authority: .proposal)`, every disagreeing oracle
(`paddingsSwapped`, `idMoved`, `clickDropped`, …) `try #require`d to disagree
with the flat chain **before** the agreeing comparisons are read. An oracle
that does not lower (a report) is a finding: drop that oracle with a note, not
the test. **Red-before, M2.1:** `_wrap` replacing the outermost layer instead
of appending one.

**N2.2 `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`**
(`ModifierCompositionProofTests`): the same for MC-B's oracle. **M2.2:**
`ModifiedElement`'s inner paint loop run innermost-first (the retired doc's
N8).

**N2.3 `aFramedListBuildsTheRowsTheUnframedListBuildsUnderTheProposalAuthority`**
(`FrameSizingTests`): the retired test's forty 40pt rows in a 600pt viewport,
framed and unframed, under `.proposal`; the built-row counts equal each other
**and** equal a literal derived from `visibleRange` before the run (a warm
frame, `MP-I`: the cold frame builds every row). **M2.3:** the realized range
made `0..<logicalCount` on warm frames (windowing off) → the literal reddens.

**N2.4 `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`**
(`FrameSizingTests`): the retired test's arms through a real `Window` over
`FakePlatformWindow`, 200×200, under the default authority with a
diagnostics pre-flight (`try #require` on an empty report, CLAUDE.md "a window
test in a mode that traps pre-flights in a mode that reports"): the registered
scroll region, the content rect and the offset after one −37 wheel, literals
derived by hand. **M2.4:** `ScrollChrome.clamp(offset:content:viewport:)`
returns 0.

**Family mutations:**

| id | family | mutation | must redden |
|---|---|---|---|
| M2a | F10 | the native frame places its child at the origin whatever its alignment | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` |
| M2b | F10 (D pin) | the lowered flexible frame clamped as the legacy one (greedy maximum dropped) | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` |
| M2c | F11 | `loweredComponentFrame` writes the amend onto the member's style instead of a frame per member | `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` |
| M2d | F11 | a component's `.padding` lowered around the whole body instead of per member | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` |
| M2e | F12 | a lowered `Row` hands its stack `nil` spacing (the platform default) | `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` |
| M2f | F12 | the lowered `alignSelf` wrapper ignored (the container's alignment used) | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` |
| M2g | F13 | M2.1 and M2.2 above | N2.1, N2.2 |

### Lane 3 — text, style readers, decorations, the matrix, divergence 4 (Opus)

**Owns:** `TextMeasureTests`, `EnvironmentTests`, `StackElementTests`,
`AnimationTests`, `FrameDecorationInteractionTests`,
`OuterModifierMatrixTests`, `RootSwitchTests`. **Removes 10**:
`TextMeasureTests` 4, `EnvironmentTests` 2, `AnimationTests` 1,
`FrameDecorationInteractionTests` 2, `OuterModifierMatrixTests` 1. Lane 3
closes the stage: the exit criteria of §8 are its last commit's.

**T — the three `StackElementTests`**: `styleOfRoot` re-spelled to read the
element's own `style` (the `StyledElement` requirement `Stack.init` writes),
no `Frame`, no authority; every `#expect` line unchanged. **Red-before:**
`Stack.init` mapping `.center` to `.stretch` reddens
`stackDefaultsToCentreNotStretch` and `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct`.

**T — `aHuggingLegacyRootIsCentredInAProductionWindow`**: the `.legacy` arm
(`boxRect(.legacy)` and its `#expect`) removed with divergence 4 (`LR-EH`);
its doc's "the two arms disagree, so neither is vacuous" re-worded to what
remains (the production literal is derived from stack-algorithms R1/R2, not
from the other arm). **Red-before:** 6b's M2a (the native root placed
top-leading) still reddens it.

**N3.1 `dynamicTypeSizeChangesNoTextMeasurementUnderTheProposalAuthority`**
and **N3.2 `aLocaleChangesNoTextMeasurementUnderTheProposalAuthority`**
(`EnvironmentTests`, beside a new private `proposalTextMeasure` helper that
renders the `Text` under `.proposal` and reads its `elementBounds` at a nil
width — the ideal — and at a width narrower than its longest word, the
broken answer): the retired tests' texts, environment values and **26pt
positive control**, `try #require(control != bare)` first. **M3.1:** the
lowered `Text`'s measurement scaled by 2 when `environment.dynamicTypeSize !=
.large` → N3.1 reddens; **M3.2:** the same keyed on a non-default `locale` →
N3.2 reddens.

**N3.3 `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority`**
(`FrameDecorationInteractionTests`): the control, after and before arms and
their clicks under `.proposal` (`inFilledRow`), literals derived by hand; the
flexible (FR-E) arm is not carried (its concept is D). **M3.3:**
`Frame.registerHandlers` ignoring the contentShape inset.

**N3.4 `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`**
(`FrameDecorationInteractionTests`): the fade, clip and border scopes reaching
both members under `.proposal`, read from the scene; no node count (CSS
shape). A two-member component's frame lowers to a row of per-member frames
(divergence 56, `LR-BH`), so the lane **derives** where the border and the
clip land from `LR-BH`'s lowering (the per-member frames' rects and which
layer carries the decoration) **before the run**, writes those literals, and
only then runs; a disagreement is a finding to explain, never a number to
copy from the output (the design first said "measures … and pins that", a
snapshot; `LR-EL` finding 4). The difference from the retired legacy arm is
named in the record. **M3.4:** the frame layer's opacity scope pushed around its own fill
only, not its content.

**N3.5 `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`**
(`OuterModifierMatrixTests`): the same matrix rows and kinds, each kind proved
by a witness a different kind cannot satisfy **under the proposal authority**
— `wraps` by `layerCount` / a new outer rect, `selfStorage` by the element's
own `style` and no new layer, `paintOnly` by an unchanged layout with a
changed scene, `distributes` by a per-member effect — derived before the run.
**M3.5:** `.padding(_:)` on a `ModifiedElement` made self-storing (writes
`Style.padding`, adds no layer) → the `wraps` row reddens; the lane adds one
mutation per kind.

**Family mutations:**

| id | family | mutation | must redden |
|---|---|---|---|
| M3a | F14 | the lowered `Text`'s measure ignores its proposal's width (never wraps) | `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` |
| M3b | F14 | `Text.paint` emits no glyph | `aHiddenElementPaintsNothingUnderTheProposalAuthority` (its shown control), `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` |
| M3c | F15 | a lowered `Box` built from its declared, not its animated, style | `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` |
| M3d | F16 | M3.3–M3.5 above | N3.3–N3.5 |
| M3e | F17 | the native root placed top-leading (6b's M2a) | `aHuggingLegacyRootIsCentredInAProductionWindow`, `aNativeRootIsCentredAtItsAnswer` |

**Lane 3's close** (after its removal): the instrument re-applied (§8), the
count, both build systems, pixels, and the census compared.

## 7. What must not move; the demo

- **Production behaviour and pixels: 0 px.** Every lane runs
  `docs/probes/demo-pixels/compare.sh <scratch> 41344e5 HEAD` and reads its
  controls at their recorded values and **`differing=0`, scene identical, in
  all fourteen images**. No `Sources/` behaviour line moves (§4's diff check),
  so any non-zero image is a finding, not a cause to name.
- `DemoFrameDeterminismTests` (`Tests/MetalUICrossPlatformTests`) green and
  **unedited** (`git diff 41344e5 -- Tests/MetalUICrossPlatformTests` empty).
- Identity, hit testing, accessibility, animation: every kept test keeps its
  assertion; the removal check (§6) is byte-level.
- 0 `warning:` on both build systems (`swift build --build-tests` under the
  default one too); 0 `error:`.
- Nothing in `Tests/PortableTests` or `Backends/` changes.
- Guards 78, gated tests nine, `AuthorityCoverage.expected` 82.
- **The portable CI count** (`CLAUDE.md`: MetalUICoreTests + MetalUILayoutTests
  + MetalUICrossPlatformTests, 388 + 22 + 3): lane 1 removes up to 190 tests
  from `MetalUILayoutTests`; it measures how many of them the Linux/Windows
  build compiles (`FreezeLoopAllocationTests` is `#if canImport(Darwin)`; read
  every `#if` in the deleted files) and records the new figure for the Record
  phase, as record §48 §7.1 did.

## 8. Exit criteria

1. **`grep -rn "computeLayout(" Tests --include='*.swift'` (`.build`
   excluded) prints nothing.**
2. **The retirement table accounts for every `@Test` removed:** 1670 − 236 +
   11 = **1445** (`LR-EM`; the design read + 10 = 1444), `Test run with 1445 tests in 3 suites passed`, one summary
   line, `FR-J` in the log; and the removal check by script (§6) green over all
   245 rows.
3. **The census:** `docs/probes/stage-7b-css-engine-instrument.patch`
   applied at the stage's HEAD, one unfiltered run, reverted — the set of
   tests printing a marker equals **section A of the census file exactly**
   (199 names, none of section B or C). A test outside A that prints is a
   missed retirement; an A test that stops printing is a stage-9 comparison
   this stage broke.
4. 0 px in all fourteen images against `41344e5`; 0 `warning:` on both build
   systems; `Sources/` diff comment-only.
5. Every N test has its named mutation's reddened set recorded; every family
   F1–F17 has at least one mutation recorded, with the replacement among the
   reddened tests.

## 9. Handed on

- **To the Record phase:** `CLAUDE.md`/`AGENTS.md` — counts (1444 / 0 / 78),
  the portable figure lane 1 measures, the freeze-loop CI hazard
  (`FREEZE-ALLOC: strict per-pass bound NOT CHECKED`) deleted with its test,
  divergence 4 retired (58 → **57** live; label 4 never reused), the
  "`.minHeight(0)` is the only way to cancel flex's automatic minimum" and
  similar CSS-engine rules re-read (they describe the legacy authority, which
  still exists, but no test pins them any more — say so), the stage-7b
  entries; records §03 (no demo look owed: 0 px), §04 (divergence 4 retired;
  every other live divergence whose pin list contains a retired test re-read,
  and its surviving pin named), §05 (the inert rows `margin: .auto`,
  `AlignItems.baseline` on a stack, `Style.border` on a container: their
  legacy-only pins retire; each row stays or goes by whether the legacy
  authority still stores the field), README; the plan; the parent spec's
  status.
- **To stage 9 (`LR-EK`):** the 199 census-A tests; every R replacement that
  is a differential test (the `Lowering*` suites, `ListLoweringTests`,
  `PresentationLoweringTests`, `HiddenLoweringTests`, the both-authority
  loops) must keep its **proposal** arm when the legacy authority goes — that
  arm is now the only pin of the facts in record §49 §4; the Dual fixtures'
  legacy branches; `LayoutContext`'s `hits`/`misses` counters and the Sources
  comments in CSS-only files that name retired tests (record §49 §6.1 lists
  them); `computeLayout`'s `SA-G` precondition, unpinned since `LR-EF`.
- **To stage 8:** percentages and length bases stay reported by name; no row
  here changes their owners.
