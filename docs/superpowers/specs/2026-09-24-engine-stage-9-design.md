# Engine replacement, stage 9 — engine deletion (plan task 7)

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 9, §8. Rulings `LR-FC`…`LR-FH` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
(next unused `LR-FI`; `LR-FH` is the critic round's).
Record: `docs/record/51-engine-replacement-stage-9.md` (§1 baseline, §2 the
entry measurement, §3 the containing-block measurement).
Instruments: `docs/probes/stage-9-legacy-reach-instrument.patch` (the runtime
census), `docs/probes/stage-9-legacy-reach-census.txt` (its 206 tests, by file),
`docs/probes/stage-9-legacy-reference-census.tsv` (the static census: every
`@Test` block naming a symbol this stage deletes, 371 rows).
**No SwiftUI probe**: the stage makes no SwiftUI claim. The one behaviour that
changes — a presentation whose surroundings the legacy containing block
followed now lays out against the window — is `LR-CL`'s own construction, not a
new SwiftUI claim (record §51 §3).
Branch `feat/engine-stage-9` from `b9a5d7f`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-9`.

**Status, 2026-09-24 (PDT): design, critic round 1 applied (`LR-FH`).** No `Sources/` or `Tests/` file changed
in a commit; every scratch patch was applied, built, run and restored with
`git checkout`, `git status --short` showing only this design's files after.

**What this stage is.** The CSS flex engine, the legacy registrars and the
legacy layout authority are **deleted**. Production has run the proposal
engine since stage 6b, so nothing a user sees moves: the fourteen offscreen
images read 0 against `b9a5d7f`. The legacy **elements** — `Box`, `Row`,
`Column`, `Stack`, `ScrollView`, `List`, legacy `.frame`, `Text`, `TextField`,
`Component`'s modifiers, `Deferred` — keep working through the lowering, which
becomes their only path. Every test that used the legacy authority as the
other arm of a comparison collapses to a single-authority assertion of the
same fact or retires with a row. **It does not pre-empt stages 10–11**:
`Style`'s CSS fields, `StyledElement.style`, the `Style`-field reports,
`CSSSizing.swift`, and the separate `ModifiedElement`/`ModifiedContent` all
stay.

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [Every stage-9-owned item](#5-every-stage-9-owned-item)
6. [Lanes, and every test by name](#6-lanes-and-every-test-by-name)
7. [What must not move; the demo](#7-what-must-not-move-the-demo)
8. [Exit criteria](#8-exit-criteria)
9. [Handed on](#9-handed-on)

## 1. Baseline

At `b9a5d7f`, 2026-09-24, in the worktree: `swift build --build-system native
--build-tests` (0 `error:`, one `warning:`, SwiftPM's deprecation notice), then
unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1452 tests in 3 suites passed`**, the log carrying `FR-J
no-argument frame: succeeded=true`. 0 goldens, 79 guards, eleven gated tests.

## 2. The entry measurement

Record §51 §2 has the method and the figures.

- **Runtime census** (the instrument patch: a marker in `computeLayout`, in
  `LayoutTree.newNode` and in `Frame.init` for a `.legacy` frame; one
  unfiltered run, 1452 passed, reverted): **206 tests** reach the legacy side
  in-process — **200** build a `.legacy` frame and run the CSS engine (record
  §49 §2's census A, 199, plus stage 8's N1.2), **6** only mint
  `LayoutTree.newNode` ids (`LayoutTreeTests`). By file: `LoweringItemTests`
  27, `ListTests` 21, `ScrollRoutingTests` 15, `ScrollIndicatorTests` 14,
  `LoweringStackAndLayerTests` 11, `LoweringDistributionTests` 9,
  `LoweringComponentTests` 9, `LoweringContainerTests` 7,
  `LoweringBoxModelTests` 7, `PresentationWindowTests` 6, `LoweringScrollTests`
  6, `LoweringLeafTests` 6, `LayoutTreeTests` 6, `AccessibilityDefaultsTests` 6,
  `PresentationLoweringTests` 5, `LayoutAuthorityTests` 5, `DeferredTests` 5,
  `AccessibilityTreeTests` 5, `ScrollViewTests` 4, `MeasurePerformanceTests` 4,
  `LoweringPipelineParityTests` 3, `LoweringCorpusTests` 3, `ListLoweringTests`
  3, `AXNodeTests` 3, `HiddenLoweringTests` 2, `FrameSizingTests` 2, and one
  each in `TombstoneTests`, `TextSystemSeamTests`, `TextFieldTests`,
  `RootSwitchTests`, `RootFieldLoweringTests`, `ProposalNodeIDTests`,
  `ModifierCompositionProofTests`, `FocusTests`, `EnvironmentTests`,
  `DecorationPaintTests`, `AbsoluteOverlayTests`. Exit-test children are not
  seen.
- **Static census** (every `@Test` block naming a symbol this stage deletes):
  **371 tests in 71 files** across `MetalUITests`, `MetalUILayoutTests`,
  `MetalUITextTests` and `MetalUIPortableTextTests`. Most of the difference
  from 206 is an explicit `layoutAuthority: .proposal` argument (the default,
  so its removal moves nothing) and exit tests.
- **Scratch deletion** (record §51 §2.2): the seven engine files and
  `MeasureFunction.swift`'s legacy half deleted → `MetalUILayout` errors in
  `LayoutTree.swift` only; those rows stripped → `MetalUI` fails in eleven
  files (`Box`, `Component`, `Deferred`, `Frame`, `ListRows`,
  `ModifiedElement`, `Passes`, `ScrollView`, `Stack`, `Text`, `TextField`),
  every one a legacy branch or a registrar. Nothing in `Backends/SDL`,
  `Tests/PortableTests`, `Experiments` or `MetalUICrossPlatformTests`' code
  names a deleted symbol (`Expected.swift` in a comment only, left unedited);
  `docs/probes/demo-pixels/ZZDemoPixels.swift` renders its chrome pair under
  both authorities and needs a stage-9 copy (§7).
- **The containing block** (record §51 §3): with the `deferred.containingBlock`,
  `.nested` and `.root` reports removed, all seven reporting arms of
  `PresentationLoweringTests` 1.5 put the presented box at the window rect
  (185, 85) 10×10 with nothing reported; with `deferred.amended` removed, the
  amend is dropped silently.
- **Differential tests**: 94 call `LayoutDifferential.compare` or build a
  `WindowPair`; 79 already assert the proposal side's rects by literal.

## 3. Decisions

| ruling | decides |
|---|---|
| `LR-FC` | scope: the files, types, functions and stored properties deleted, and what is kept; three departures from row 9's wording — `Resolve.swift` and `Alignment.swift` deleted whole (no other half has a caller), the whole `LayoutAuthority` enum and its properties deleted (not only `.legacy`), the kernel's four unreachable legacy-node preconditions (three deleted, one reworded) |
| `LR-FD` | tokenizer min-content deleted from production (`TextSystem.minContentWidth`, `UnbreakableRuns.swift`, `ShapingCache`'s min-content memo); `PortableText`'s content sizes kept as library API, re-owned out of task 7; the oracle's Apple arm becomes a verbatim test-local copy of the tokenizer |
| `LR-FE` | one authority: the 87 parameterised scenarios collapse; a differential test keeps its literals and loses its agreement assertions, with a literal added where only the agreement carried a named observation and a base-vs-head mutation check; frozen legacy snapshots rejected; the harness single-authority; renames of names that state a legacy answer |
| `LR-FF` | every stage-9-owned item disposed by name (§5) |
| `LR-FG` | three lanes, their order, the accounting (1452 − 43 + 1 = 1410), the guards (79, three re-spelled to read absence), the demo harness revision |
| `LR-FH` | critic round 1: the lanes re-cut by harness (lane 1 the differential harness and its users, lane 2 the scenario registry's other contributors plus every other test), the site-coverage check re-run at every lane's head, the R/D labels corrected, M3a's arm count, one unprobed SwiftUI sentence struck; the containing-block and `deferred.amended` dispositions and the plan's deferred status fix upheld |

## 4. API and files

**Public API removed** (lane 3): `LayoutPass.requestNode(style:children:)` and
`requestLeaf(style:measure:)` (deprecated since 6a); `MetalUILayout`'s
`computeLayout`, `MeasureFunction`, `AvailableSpace`, `AvailableSpaceSize`,
`OptionalSizeD`, `resolveLength`, `resolveDimension`, `resolveEdges`,
`resolveMargin`, `clamp`, `ResolvedEdges`, `LayoutTree.newNode`, `newLeaf`,
`style`, `setStyle`, `measure`, `isNativeLayoutNode`; `MetalUITextSystem`'s
`TextSystem.minContentWidth` requirement; `MetalUIText`'s
`Shaper.unbreakableRuns`, `ShapingCache.minContentWidth`, and the two
conformers' witnesses. **Public API kept**: every native registrar,
`LayoutTree`'s native API, `SizeD`, `LayoutRect`, `roundLayout`,
`measuredWidth`, `Style`, `PortableText.unbreakableRuns`/`minContentWidth`/
`maxContentWidth`.

**Internal removed** (lane 3): `LayoutAuthority`, `Frame.layoutAuthority`,
`Frame.init(layoutAuthority:)`, `Frame.defaultLayoutAuthority`,
`Window.layoutAuthority`, `LayoutPass.lowersToProposal`,
`Frame.requestNode`/`requestLeaf`/`unguardedLegacyRegistration`,
`Frame.style`/`setStyle`, `LayoutPass.style`/`setStyle`,
`Frame.legacyRootLayoutCounter`/`LegacyRootLayoutCounter`, `textMeasure` (three
overloads), `LoweringSite.customElement`, `ListRows.GroupLayout.spacer`,
`ShapingCache.minContentCount`, `Shaper.RunCallCounter`/`runCallCounter`/
`unbreakableRunsReusingTokenizer`.

**Behaviour** (lane 3, `LR-FF`): `deferred.containingBlock`, `.nested`, `.root`
no longer report — a presentation's containing block is the window whatever
surrounds it (a production trap becomes an answer; the demo takes no such
path). `deferred.amended` still reports, owner **11**. Everything else is
byte-identical in production.

**Stored properties on a public type crossing a module boundary change**
(`LayoutTree`'s `styles`/`measures`, `ShapingCache`'s `minContent`): lane 3
runs `swift package clean` before its counts.

**Files deleted** (lane 3, last): `Sources/MetalUILayout/FlexEngine.swift`,
`ResolveFlexibleLengths.swift`, `FlexBaseSize.swift`, `FlexLines.swift`,
`Alignment.swift`, `LayoutContext.swift`, `Resolve.swift`;
`Sources/MetalUI/LayoutAuthority.swift` keeps `LoweringSite` and
`UnlowerableField` (the enum `LayoutAuthority` goes; the file may be renamed
`Lowering…` only if every citation moves with it — default: kept under its
name); `Sources/MetalUIText/UnbreakableRuns.swift`. Test-support files are
deleted by the lane that removes their last caller: `AuthorityCoverage.swift`,
`ZZAuthorityRollCall.swift` (lane 1), `UnbreakableRunsTests.swift`,
`TokenizerReuseTests.swift` (lane 2, whole files retired).

**Files per lane** — disjoint:

- **Lane 1** (`LR-FH` item 1): `Tests/MetalUITests/` `LayoutDifferential.swift`
  and every file that calls `LayoutDifferential.compare`/`render(authority:)`
  or builds a `WindowPair` — `LayoutAuthorityTests`, `LoweringItemTests`,
  `LoweringStackAndLayerTests`, `LoweringDistributionTests`,
  `LoweringComponentTests`, `LoweringContainerTests`, `LoweringBoxModelTests`,
  `LoweringLeafTests`, `LoweringScrollTests`, `LoweringPipelineParityTests`,
  `LoweringCorpusTests`, `PresentationLoweringTests`, `ListLoweringTests`,
  `HiddenLoweringTests`, `RootFieldLoweringTests`,
  `GridLoweringInteractionTests`, `GoldenReplacementStackTests`,
  `GoldenReplacementSupport`, `FrameSizingTests`, and the five that also
  contribute scenarios to the registry — `ScrollRoutingTests`, `ListTests`,
  `DeferredTests`, `PresentationWindowTests`, `DecorationPaintTests` (their
  49 scenarios collapse here too) — plus the registry's two literals only:
  `AuthorityCoverage.expected` loses those 49 names and
  `ZZAuthorityRollCall`'s count `#require` moves **87 → 38** with its
  hand-derived sum re-written (both files still compile and the roll call
  stays green for the 38 lane 2 owns) — **25 files** plus the two literal
  edits, ~17k lines (the old lane 1 was 38 files, 25k lines, 617 edit sites).
  `AnimationTests` uses only `DifferentialRoot`, which lane 1 keeps.
- **Lane 2**: the ten remaining registry contributors — `ScrollIndicatorTests`,
  `ScrollViewTests`, `AXNodeTests`, `AccessibilityDefaultsTests`,
  `AccessibilityTreeTests`, `FocusTests`, `TombstoneTests`,
  `MeasurePerformanceTests`, `AbsoluteOverlayTests`, `EnvironmentTests` (38
  scenarios) — then `AuthorityCoverage.swift` and `ZZAuthorityRollCall.swift`
  deleted; and `Tests/MetalUITests/` `NativeBoundaryIntegrationTests`,
  `RootSwitchTests`, `ProposalNodeIDTests`, `TextSystemSeamTests`,
  `TextFieldTests`, `TextMeasureTests`, `TextHardLineBreakTests`,
  `IdentityTests`, `InputDispatchTests`, `HitRegionTests`, `HitboxTests`,
  `ComponentTests`, `ElementGroupTrapTests`, `ElementLayoutTests`, `StateTests`,
  `ModifiedElementTests`, `ModifierCompositionProofTests`, `FrameClockTests`,
  `DisabledTests`, `BackgroundChainTests`, `ContainerIntegrationTests`,
  `EnvironmentTrapTests`, `FrameDecorationInteractionTests`, `AnimationTests`,
  `StackElementTests`, `OuterModifierMatrixTests`, `AXEmitSiteTests`;
  `Tests/MetalUILayoutTests/` `LayoutTreeTests`, `NativeBoundaryTrapTests`,
  `NativeGridTrapTests`, `NativeInvalidationContractTests`;
  `Tests/MetalUITextTests/` `ShapingCacheTests`, `TokenizerReuseTests`,
  `UnbreakableRunsTests`; `Tests/MetalUIPortableTextTests/ContentSizeOracleTests`;
  and any other test file the static census names that lane 1 does not own
  (the lane re-runs the census grep at its base and lists additions in its
  record). The critic's grep at `caa331a` found none outside the two lists.
- **Lane 3**: every `Sources/` file; `Tests/MetalUITests/Fakes.swift`;
  `LayoutAuthorityCompileGuards.swift`, `ErasureCompileGuards.swift`;
  `Tests/MetalUITests/PresentationContainingBlockTests.swift` (new);
  `docs/probes/demo-pixels/` (`ZZDemoPixels-stage9.swift` new, `compare.sh`).
  **Nothing under `Backends/`, `Tests/PortableTests`,
  `Tests/MetalUICrossPlatformTests` (in particular `Expected.swift` and
  `DemoFrameDeterminismTests`) or `Package.swift` changes** (no target is added
  or removed: every deleted file is inside a target that stays).

## 5. Every stage-9-owned item

`LR-FF` is the table; in short:

| item | disposition |
|---|---|
| 3 N9 pins + 6a's N9 (`NativeBoundaryIntegrationTests`), `ProposalNodeIDTests`' N9 | D (no legacy node can be minted) — lane 2 |
| 2 tokenizer pins (`MeasurePerformanceTests`) | D (`LR-FD`) — lane 2 |
| `deferred.containingBlock`/`.nested`/`.root` | deleted; N3.1 pins the window answer; 1.6 R — lanes 1 and 3 |
| `deferred.amended` | kept, owner 11 — lane 3 |
| custom elements | registrars and site deleted; six trap tests R (three lane 1, three lane 2); one diagnostics arm pair T; one guard re-spelled — lanes 1, 2 and 3 |
| divergence 11 | retires; its test R (lane 2), its proposal fact an arm of 1.5 (lane 1) |
| §05's legacy-authority-only rows, the spacer row, the `FlexBaseSize` figures | deleted/gone (Record phase) |
| `FlexEngine.swift:107`, `computeLayout`'s bracket (`LR-EQ`) | gone with the file |
| `LR-H`'s legacy ideal trap, `Frame`'s backstop, 6b's exit test, the default-authority tests, the legacy hidden path | D each (§6; no replacement test exists) |
| every "under both authorities" test | `LR-FE` |

## 6. Lanes, and every test by name

Three lanes, in order 1 → 2 → 3, on one branch; each commits green
(unfiltered suite, 0 `error:`, only SwiftPM's notice as `warning:`). Lanes 1
and 2 change no `Sources/` line; lane 3 changes no test outside its list.
Every mutation: commit first, restore from a copy, full unfiltered suite,
`git status --short` after, name every test reddened. Every removed `@Test` is
a row (R: replaced by a named test; D: a deleted concept named; T: kept and
changed — collapsed, renamed, re-spelled) in the lane's record section;
before − removed + added = after is read off the summary line.

### Lane 1 — the differential harness and its users (`LR-FE`, `LR-FH` item 1)

Steps: (1) **before any edit**, run the site-coverage mutations Ma–Me at the
lane's base (`b9a5d7f`) and record every reddened test name (with issue
counts) — this base set is the stage's, read again by lanes 2 and 3; (2)
collapse the 49 parameterised scenarios of the five registry contributors
this lane owns (drop `arguments:`, the authority parameter, `.legacy`
branches, `AuthorityCoverage.record`), and remove those 49 names from
`AuthorityCoverage.expected` and move the roll call's count `#require` to 38
(literal and sum re-written); (3) collapse each
differential test by `LR-FE` item 2 — literals kept verbatim, agreement
assertions deleted, a literal added **derived by hand before the run** where
the test's name or doc names an observation only the agreement carried, each
added literal read in a scratch run at the lane's base against the legacy arm
and recorded; (4) `WindowPair`s to one window; (5) the retirements below; (6)
move every test element off `site: .customElement` (onto `.box`; a test that
reads a `customElement.*` report is one of the retired trap tests) and off
`pass.frame.requestNode`/`requestLeaf`/`pass.lowersToProposal`/
`layoutAuthority:`; (7) rewrite `LayoutDifferential.swift` single-authority
(`LR-FE` item 5); (8) renames by `LR-FE` item 6, each a T row
old → new; (9) re-run Ma–Me at the head: **every test reddened at base still
reddens at head, or is a row of this lane or a test lane 2 still owns
unchanged** — a dropout gets a literal and the mutation is re-run. Lanes 2
and 3 repeat step (9) at their heads against the same base set (`LR-FH`
item 2): lane 2 collapses scenarios Md and Me reach, and lane 3 edits the
file every mutation is applied to.

**Site-coverage mutations** (each on `Sources/MetalUI/LegacyLowering.swift`
unless named; the base run is what makes them instruments):

- **Ma**: the container lowering's `gap` resolved as 0 (`let gap = 0` at
  `arrangeLegacyMainAxis`'s `resolvedLength(… gap …)`).
- **Mb**: a stretched item's frame no longer aliased as the element's rect
  (drop the `lowering.alias` call for stretch).
- **Mc**: a lowered container's padding insets with `left`/`right` swapped.
- **Md**: `WindowedRowsLayout` places row `i` at `i × rowHeight` instead of
  `(firstIndex + i) × rowHeight` (`ListRows.swift`).
- **Me**: `lowerPresentation` drops the inset padding (the content sits at the
  window's corner).

**Retirements** (11 rows; the design's rows 1, 9, 11–15 moved to lane 2 with
their files, `LR-FH` item 1 — numbers kept so citations still resolve):

| # | test (file) | row | replacement / concept |
|---|---|---|---|
| 2 | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement` (`LayoutAuthorityTests`) | D | the two-engine comparison |
| 3 | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` (`LayoutAuthorityTests`) | D | the two-engine comparison |
| 4 | `aFrameAndAWindowDefaultToTheProposalAuthority` (`LayoutAuthorityTests`) | D | an authority default |
| 5 | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` (`LayoutAuthorityTests`) | D | a window's authority |
| 6 | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` (`LayoutAuthorityTests`) | R | lane 3's re-spelled guard G6a (the registrars are absent) |
| 7 | `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne` (`LayoutAuthorityTests`) | R | G6a |
| 8 | `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` (`LayoutAuthorityTests`) | D | `Frame`'s legacy backstop |
| 10 | `aLegacySpelledListRowAbortsAProductionProposalFrame` (`ListTests`) | R | G6a |
| 16 | `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore` (`HiddenLoweringTests`) | D | the legacy hidden path |
| 17 | `aPresentationTrapsAProductionProposalFrameNamingItsField` (`PresentationLoweringTests`) | R | N3.1 |
| 18 | `anIdealDimensionOnTheLegacyFrameTraps` (`FrameSizingTests`) | D | `LR-H`'s legacy ideal trap |

**T rows the design names** (the lane adds the rest): 1.5
`aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` loses its
seven `deferred.containingBlock`/`.nested`/`.root` arms (their reports die in
lane 3 — `LR-FG` item 4) and gains the `ScrollView` arm (the fact of lane 2's
row 15, added here **before** lane 2 retires that test); its arm-count
`#require` moves 18 → 12; the `deferred.amended` arm stays.
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` loses its two
`customElement` arms. `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`
(and `LoweringCorpusTests`' other two) keep "lowers with no diagnostic" and
their element counts; element-by-element agreement is the deleted concept.
Renames the design expects (`LR-FE` item 6), among them:
`aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren`,
`aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren`,
`aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth`,
`aLoweredPaddingLayerAgreesWithTheLegacyWrapper`,
`aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild`,
`aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation`,
`aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`,
`aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`,
`aLoweredListsRowIdentitiesAreTheLegacyOnes`,
`anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne`,
`aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne`,
`theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities`
and every `…UnderBothAuthorities` scenario. A name whose legacy clause is still
a true statement of the proposal answer's difference from CSS (for example
`aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`) is renamed
only if the collapsed test no longer asserts the legacy half; the record says
which.

**Lane 1's count: 1452 − 11 = 1441.**

### Lane 2 — the registry's other contributors, and every other test that names a deleted symbol

Steps: (0) collapse the ten remaining registry contributors' 38 scenarios
as lane 1's step (2) does (`aListsWorkIsTheSameFor100kRowsAsFor500`, gated,
collapses like its 160/40 twin), then delete `AuthorityCoverage.swift` and
`ZZAuthorityRollCall.swift`; retire lane 1's old rows 1, 9, 11–15 (below);
move every test element in these files off `site: .customElement`; (1)
re-run the static census grep at the lane's base; every hit
outside lane 1's and lane 3's files is this lane's; (2) delete every
`layoutAuthority:` argument (all `.proposal` or defaulted — a `.legacy` one is
a row) and every test element's legacy branch (`lowersToProposal`,
`pass.frame.requestNode`/`requestLeaf`); a test that looped over both
authorities keeps its proposal iteration (T); (3) `ContentSizeOracleTests`:
copy the `CFStringTokenizer` walk **verbatim** from
`Sources/MetalUIText/UnbreakableRuns.swift` into the oracle file as a
`private` reference and point every Apple-arm call at it (`LR-FD` item 3) —
the oracle must read the same agreement before and after (record its
`measureContentSizeDifferences` output with `METALUI_CONTENT_MEASURE=1` at
base and head: identical); (4) `MetalUILayoutTests`: mint ids with
`newNativeLeaf` where the test's fact is about ids, generations, reset or
adoption (T), and retire the legacy-node tests; (5) the retirements below;
(6) `TextSystemSeamTests.aPortableFrameNeverShapesThroughCoreText` and
`TextFieldTests.aFieldLaysOutAndEditsUnderBothAuthorities` lose their
`.legacy` arm — if that arm was the test's **positive control** (the one that
proves the instrument counts), the lane writes a proposal-side control that
separates, runs it red once, and records it.

**Retirements** (32 rows: the design's 25 plus lane 1's old rows 1, 9, 11–15):

| # | test (file) | row | replacement / concept |
|---|---|---|---|
| 1–4 | `aProposalElementInsideALegacyContainerTrapsAtRegistration`, `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`, `aPaddingModifierOnAProposalComponentTraps`, `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (`NativeBoundaryIntegrationTests`) | D | `SA-G`'s mixed tree (no legacy node can exist) |
| 5 | `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (`ProposalNodeIDTests`) | D | a legacy registration |
| 6 | `noProductionFrameReachesTheLegacyEngine` (`RootSwitchTests`) | D | the legacy root-layout counter and the branch it counted (`LR-FH` item 3: stage 10's `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`, row 9's own wording, does not exist yet, so it is handed on, not cited as a replacement) |
| 7–10 | `theThreeSizingModesAnswerWithCoreTextsOwnNumbers`, `minContentIsTheLongestRunNotTheWidestCharacter`, `anExplicitKnownSizeWinsOverTheMeasuredOne`, `aZeroAvailableExtentMeasuresRatherThanTraps` (`TextMeasureTests`) | D | `textMeasure` and the CSS known/available pair |
| 11–12 | `unbreakableRunsAreLineBreakOpportunitiesNotWordBoundaries`, `runsAreTrimmedOfTrailingWhitespaceAndBlankOnesAreDropped` (`UnbreakableRunsTests`, file deleted) | R | `ContentSizeOracleTests`' `everyClassPairBreaksAsCoreTextDoes` and `maxContentIsTheWidestHardLineAndRunsCarryNoTrailingSpace` (the portable side, measured against the moved reference) |
| 13–14 | `aMinContentMissReusesOneTokenizerRatherThanCreatingOnePerString`, `theReusedTokenizerAnswersExactlyAsAFreshOneDoes` (`TokenizerReuseTests`, file deleted) | D | tokenizer min-content |
| 15–17 | `aSecondMinContentQueryTokenizesNothing`, `theMemoizedWidthEqualsTheMaxOverIndependentlyShapedRuns`, `aCounterOnlyCountsCallsWithinItsOwnBinding` (`ShapingCacheTests`) | D | the min-content memo and its counter |
| 18 | `leavesCarryAMeasureFunctionAndBranchesDoNot` (`LayoutTreeTests`) | D | the CSS `MeasureFunction` |
| 19–24 | `aNativeNodeRegisteredUnderALegacyNodeTraps`, `aLegacyNodeRegisteredUnderANativeStackTraps`, `aLegacyNodeRegisteredUnderACustomLayoutTraps`, `aStyleWrittenOntoANativeNodeTraps`, `setStyleOnALegacyNodeDuringNativeLayoutTraps`, `registeringALegacyLeafDuringNativeLayoutTraps` (`NativeBoundaryTrapTests`) | D | `SA-G`'s legacy half, `setStyle`, `newLeaf`; the native halves stay pinned by `registeringANativeNodeDuringNativeLayoutTraps` and `computeNativeLayoutReenteredFromAMeasureClosureTraps` |
| 25 | `aLegacyNodeUnderAGridOrCarryingAGridMarkTraps` (`NativeGridTrapTests`) | D | a legacy node under a grid (all three arms) |
| L1-1 | `everyParameterisedScenarioRanUnderBothLayoutAuthorities` (`ZZAuthorityRollCall`, file deleted) | D | "both authorities ran" |
| L1-9 | `aLegacySpelledAXListRowAbortsAProductionProposalFrame` (`AXNodeTests`) | R | G6a |
| L1-11 | `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` (`MeasurePerformanceTests`) | R | G6a |
| L1-12 | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame` (`TombstoneTests`) | R | G6a |
| L1-13 | `aColdFrameCreatesAtMostOneLineBreakTokenizer` (`MeasurePerformanceTests`) | D | tokenizer min-content (`LR-FD`) |
| L1-14 | `aWarmFrameTokenizesEachDistinctStringAtMostOnce` (`MeasurePerformanceTests`) | D | tokenizer min-content |
| L1-15 | `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` (`AbsoluteOverlayTests`) | R | 1.5's arm "absolute in a `ScrollView`, no `Deferred`", added by lane 1 (divergence 11 retires) |

**T rows the design names**: `ShapingCacheTests`' `aMinContentHitReStampsSoItSurvivesASweepingLoad`
and `anEntrySurvivesExactlyTwoUntouchedSweptFrames` re-spelled onto the
`shaped(_:font:wrappingAt:)` storage and `storageCount` (the sweep they pin is
shared by both memos); if no observable separates on the storage side, each
becomes R with `anEntryUntouchedForAFrameIsDropped`/`aSweepNeverDropsAnEntryTheCurrentFrameTouched`
as its replacement and the lane's count moves by one each, recorded.
`treeStoresStyleAndChildren` → `treeStoresChildren` (native nodes; the style
half is the deleted placeholder rows). `LayoutTreeTests`' six id/reset/adoption
exit tests and three plain tests, `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`
(its `isNativeLayoutNode`/`style == .default` preconditions dropped) and
`nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` (the flag probed by a
native registration's `SA-I` trap instead of `setStyle`'s) re-spelled native.
`TextHardLineBreakTests.aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent`
re-spelled onto `TextSystem.measure(_:font:wrappingAt: nil)`.
`RootSwitchTests.aHuggingLegacyRootIsCentredInAProductionWindow` keeps its
production arm (T). `ContentSizeOracleTests`' seven tests (T: reference moved).

**Mutations**: **M2a** `LayoutTree.slot(_:)`'s generation check deleted → the
re-spelled `LayoutTreeTests` id/reset/adoption tests redden (name them; at base
the same mutation reddens the same names — run both); **M2b** the oracle's
moved reference drops its trailing-whitespace trim → `ContentSizeOracleTests`'
run-comparison tests redden; **M2c** `appendNode`'s `SA-I` precondition
deleted → `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns` reddens.

**Lane 2's count: 1441 − 32 = 1409.**

### Lane 3 — the deletion (`LR-FC`, `LR-FD`, `LR-FF`)

Steps, each building before the next: (1) N3.1, red first (commit the red);
(2) the `deferred.*` change — `reportPresentationContainingBlock` and its call
deleted, `Deferred`'s `nested` report and `presentationsBefore` bookkeeping
deleted, `presentationCoversWindow` deleted if no caller remains, `.deferred`'s
`owningStage` → "11" with its comment; (3) every site's legacy branch, the
registrars, `LoweringSite.customElement`, `Frame`/`LayoutPass` `style`/`setStyle`,
`isHidden`'s style clause, `ListRows`' spacer, `LoweringState`'s guard,
`Deferred`'s authority guard; (4) the authority: `LayoutAuthority`,
`Frame.layoutAuthority` and its init parameter, `defaultLayoutAuthority`,
`Window.layoutAuthority`, `lowersToProposal`, the counter, `computeRootLayout`'s
legacy branch; `Fakes.swift`'s `layoutAuthority:` parameter; (5) text:
`textMeasure`, `TextSystem.minContentWidth` and its witnesses, `ShapingCache`'s
min-content memo, `UnbreakableRuns.swift`; (6) `LayoutTree`'s legacy API and
rows, the kernel's three unreachable checks deleted and `nativeNode(_:)`'s
message reworded (`LR-FC` item 3), `beginLayout`'s message; (7) **last**, the
seven engine files and `MeasureFunction.swift`'s legacy half; (8) doc comments
that would lie (every `Sources/` comment naming the legacy authority, the CSS
engine, `computeLayout`, `requestNode`, a deleted test or "until stage 9" —
grep, and list the survivors with reasons in the record); (9) the three guards
re-spelled; (10) `swift package clean`, both build systems, the suite;
(11) `ZZDemoPixels-stage9.swift` and `compare.sh`'s switch, then the
fourteen-image comparison; (12) `Backends/SDL` and a Linux container build (§7);
(13) the site-coverage re-run.

| test (file) | asserts | red before | mutation that must redden it |
|---|---|---|---|
| **N3.1** `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt` (`PresentationContainingBlockTests`, new) | the seven arms of record §51 §3 (bordered root; root width 100 in 200; a `Deferred` root; inside a top/left-5 presentation; root `.frame(maxWidth: 100)`; root `.frame(minWidth: 300)`; inside a bordered `inset(0)` presentation), each a plain `Frame` 200×100 with diagnostics, the tree as root: the presented box's hitbox is **(185, 85) 10×10** and the report is **empty**; arm count `#require`d == 7; plus the amended arm: `Box { PresentingSolo().width(70) }` reports exactly `["deferred.amended"]` and that field's `owningStage == "11"` | each of the seven reports its `deferred.*` field; the amended owner reads "9" | **M3a**: restore the `reportPresentationContainingBlock(root:)` call → the five root arms red (four `deferred.containingBlock`, one `deferred.root` — the function raises both, `LR-FH` item 5); **M3b**: restore the `nested` report → the two nested arms red; **M3c**: `.deferred`'s `owningStage` back to "9" → the amended arm red |
| **G1** `aPlainImportCannotChooseTheLayoutAuthority` (`LayoutAuthorityCompileGuards`) — **T** | the `window.layoutAuthority = .proposal` fixture fails with `has no member 'layoutAuthority'`; the control compiles; `#require` they disagree | the message reads `inaccessible due to 'internal' protection level` | **M3d**: an internal `var layoutAuthority = 0` on `Window` → the message is the access one, G1 red |
| **G6a** `aPlainImportCallerOfTheLegacyRegistrarsIsWarnedTowardTheNativeOnes` (`LayoutAuthorityCompileGuards`) — **T**, renamed `aPlainImportCallerOfTheLegacyRegistrarsNoLongerCompiles` | the legacy fixture fails, naming `requestLeaf` and `requestNode` as members `LayoutPass` does not have; the native control compiles with no deprecation | the fixture compiles with two deprecations | **M3e**: restore the public deprecated `requestNode` (body `fatalError()`) → the fixture's `requestNode` error vanishes, G6a red |
| **G5** `layoutPassStyleAccessorsAreNotPublic` (`ErasureCompileGuards`) — **T** | the fixture fails with `has no member 'style'` (tightened from `contains("style")`, which a deleted accessor would pass for nothing) | the message is the access one | **M3f**: an internal `func style(_:)` restored on `LayoutPass` → red |

Step (13), after (12): re-run Ma–Me at the head against lane 1's base set (`LR-FH` item 2).

Also mutated once each (no new test; the named existing tests must redden):
**M3g** `Frame.isHidden` returns `false` → the accessibility-suppression tests
of `HiddenLoweringTests` and `AXNodeTests` redden (name them) — the single
source of hidden now carries every one; **M3h** `computeRootLayout` skips the
presentations loop → `PresentationWindowTests`/`DeferredTests` redden (name
them).

**Lane 3's count: 1409 + 1 = 1410**; guards **79** (three re-spelled, none
added or removed; `typecheckFile`'s helper count unchanged).

## 7. What must not move; the demo

- **Production behaviour and pixels**: `compare.sh <scratch> b9a5d7f <lane
  head>` reads **0 differing, scene identical, in all fourteen images** at
  every lane (lanes 1–2 change no `Sources/`; lane 3 with the stage-9 harness
  copy). Controls as recorded in `compare.sh`; the chrome pair's `[0]` holds at
  the head with both images rendered under the one authority, and
  `b9a5d7f`'s `chrome-legacy` against the head's reads 0.
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` green with `Expected.swift`
  unedited. The one intended behaviour change (`LR-FF`'s containing block) is
  on no production tree: the demo's root is auto on both axes and unbordered,
  and its modal is not nested.
- **Identity, hit testing, accessibility, animation, focus, scrim, `List`
  windowing, `Deferred` presentations**: the lowering is untouched except for
  the deleted guards and reports; every test of these facts runs, collapsed,
  under the one authority. The site-coverage rule (lane 1) is what shows a
  collapse kept its pin.
- **`MetalUILayout` imports only `MetalUICore`** (`grep -h '^import'
  Sources/MetalUILayout/*.swift | sort -u` reads one line).
- **0 `warning:`** besides SwiftPM's notice on both build systems.
- **Linux and Windows CI**: lane 3 builds `Backends/SDL` (`python3
  Backends/SDL/scripts/fetch-accesskit.py` once, then
  `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests` and `swift test`
  there — `PortableReplay` and `DemoCapture` green unedited), `Tests/PortableTests`
  (`swift build --build-tests` there; it depends on `MetalUIPortableText`, whose
  `TextSystem` conformance loses a witness), and, with Docker (OrbStack is
  installed), a `swift:6.4-noble` container: `swift build --build-tests` of the
  root package and `swift test --filter 'MetalUICoreTests|MetalUILayoutTests|MetalUICrossPlatformTests'`,
  recording the three counts (the portable CI figure moves by the eight
  `MetalUILayoutTests` retirements).
- **Depth**: `NativeLayoutRun.maxDepth` 72, `SA-L` and the depth tests
  unchanged; `everyProductionRootsDeepestNativeLevelIsMeasured` green unedited
  apart from lane 2's argument removal.
- **Every test not retired keeps its assertion's answer** (T rows change a
  test's arms, spelling or name, never an expected value — the containing-block
  arms are removed from 1.5, not re-valued; N3.1 carries the new values).

## 8. Exit criteria

1. The seven engine files, `UnbreakableRuns.swift` and the deleted symbols are
   gone: `git ls-files Sources/MetalUILayout` lists none of the seven, and
   `grep -rnE 'LayoutAuthority|layoutAuthority|lowersToProposal|computeLayout\(|requestNode\(|requestLeaf\(|textMeasure|legacyRootLayoutCounter|unbreakableRuns|minContentWidth|AvailableSpace|MeasureFunction\b|customElement' Sources Tests/MetalUITests Tests/MetalUILayoutTests Tests/MetalUITextTests`
   prints only lines the record lists with a reason (expected: comments in the
   record-citing doc text of `LegacyLowering.swift`, if any survive step 8; the
   oracle's reference in `MetalUIPortableTextTests` is outside the grep).
2. Unfiltered `swift test --build-system native --no-parallel` → **`Test run
   with 1410 tests in 3 suites passed`** (or the lanes' re-derived figure, with
   its equation), the log carrying `FR-J no-argument frame: succeeded=`;
   **79 guards**; 0 goldens; **eleven** gated tests, unchanged (neither
   retired tokenizer pin was gated; `aListsWorkIsTheSameFor100kRowsAsFor500` and
   `measureContentSizeDifferences` collapse and stay gated).
3. 0 `error:`, 0 `warning:` besides SwiftPM's notice, on `swift build
   --build-system native --build-tests` **and** `swift build --build-tests`.
4. The fourteen-image comparison against `b9a5d7f`: 0 differing, scene
   identical; `DemoFrameDeterminismTests` green unedited; `Backends/SDL`'s
   `PortableReplay` and `DemoCapture` green unedited; `Tests/PortableTests`
   builds; the Linux container's three test targets pass.
5. N3.1, G1, G6a, G5 green; every named mutation reddened what §6 names; lane
   1's site-coverage base set held at every lane's head (head ⊇ base − retired, `LR-FH` item 2).
6. Every removed `@Test` has a row; 1452 − 43 + 1 = 1410 (or the re-derived
   equation).

## 9. Handed on

- **To stage 10**: `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  (replaces `noProductionFrameReachesTheLegacyEngine`); `Style`'s CSS fields,
  every `Style`-field report, `CSSSizing.swift`, and the `LegacyLowering`
  name if stage 10 wants it gone.
- **To stage 11**: `deferred.amended` (`LR-FF`), with `Component.width` over a
  presentation member.
- **To the Record phase** (not before): CLAUDE.md/AGENTS.md — the "Two engines,
  chosen by the window root alone", "Layout authority", "One authority per
  root, no adapter (`SA-G`)" and "one `isLayingOut` flag guards both engines"
  bullets; the `Text` paragraph's min-content rule (`TX-F`, `runCallCounter`);
  the `List`/`Deferred` paragraphs' "under both authorities" sentences; the CI
  hazards of the roll call; the counts (suite, portable CI), `LR-` next
  unused, a stage-9 alignment bullet; record §04 (divergence 11 retires; the
  live rows whose pins ran "under both authorities" — 9, 10, 13, 14, 18, 48,
  54, 55, 56 among them — re-read, each keeping its fact on the one authority
  or retiring by the rule divergences 4 and 11 set), record §05 (`LR-FF`'s
  deleted rows), record README; the parent spec's §4.1 row 9 status; **the
  plan's stale "Progress 2026-09-24 on `feat/engine-stage-8`" note** (stage 8
  merged at `b9a5d7f`; this design fixed the parent spec's equivalent sentence
  and may not edit the plan before the Record phase).
