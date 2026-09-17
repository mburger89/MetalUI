# 17 — Containers (plan task 6)

`feat/containers`, from `9e439cb`. Design: `docs/superpowers/specs/2026-09-16-containers-design.md`;
rulings `CN-A`… in `docs/superpowers/2026-09-16-containers-decisions.md`;
probes `docs/probes/swiftui-stack-algorithms.swift` (revision 4 at design,
revision 8 at the end), `docs/probes/swiftui-overlay-presentation.swift`.
Written by the lanes, one section each, in order; lane 1's and lane 3's
verifier rounds and everything from "What landed, in one place" onward were
written by the record pass at `6d59cf0`.

**Summary.** The proposal path's `HStack`, `VStack`, `ZStack`, `Spacer`,
overlay/background content, native root and `ProposalScrollView` now follow
SwiftUI's probed algorithms (lanes 1–4); on the legacy path a frame over one
node overflows both axes and `percent:` is renamed `fraction:` (lane 5). No
legacy container is lowered or replaced (`CN-A`), so task 6 stays open
(`CN-T`). 1303 → **1355** tests, 66 → **70** guards, 97 goldens unmoved.
**Lanes 1, 2, 4 and 5 verified `ok`; lane 3 `ok: false`** (its re-verification
was cut short; the record pass's own run of the missing mutations found one
unpinned, unprobed clause). "For the integrator", the last section, says what
CLAUDE.md, the plan, README and the two tables should say.

## Lane 1 — distribution (`CN-B`, `CN-D`, `CN-E`'s second pass, `CN-C`'s −∞, `CN-F`'s spacer)

2026-09-16. Commits: `f657598` (tests, red), `31fd2ba` (implementation and the
fourteen re-derived tests), then this record with `CN-B`'s "Lane 1, as built"
addendum.

### Red first

Thirteen new tests — `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`
(1.1–1.10, 1.12) and `Tests/MetalUITests/ContainerIntegrationTests.swift`
(1.11, 1.13) — built against `9e439cb`'s kernel and run filtered:
`Test run with 13 tests in 0 suites failed … with 81 issues`, every test red.
Each test's first failure:

| # | test | first failure |
|---|---|---|
| 1.1 | `aStackServesItsLeastFlexibleChildFirst` | `:163` `arm["a"] == rect(0, 0, 40, 20)` (G1) |
| 1.2 | `aLowerPriorityGroupKeepsItsMinimumsReserved` | `:217` `arm["a"] == rect(0, 0, 70, 20)` (G2) |
| 1.3 | `aGreedyChildTakesTheSurplusAheadOfASpacer` | `:266` `arm.run(root, 200, 50) == size(200, 20)` (G3) |
| 1.4 | `aStackWithASpacerStillCompressesItsOtherChildren` | `:310` `arm.run(root, 100, 50).width == 100` (G6) |
| 1.5 | `aStackAnswersTheSumOfItsChildrensAnswers` | `:345` `arm.run(root, 100, 50) == size(160, 20)` (G9) |
| 1.6 | `aStackAtANilOrInfiniteMainProposalOffersItToEveryChild` | `:403` `arm.proposals("a") == [p(nil, nil), p(nil, 20)]` (G7) |
| 1.7 | `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity` | `:466` `arm.proposals("a").last == p(96, 50)` (SP8) |
| 1.8 | `aSingleChildStackPassesItsChildsPriorityThrough` | `:542` `arm["a"] == rect(0, 0, 80, 20)` (G11) |
| 1.9 | `aStackPlacesAfterASecondPassAtItsOwnCrossSize` | `:605` `arm["a"] == rect(0, 0, 30, 20)` (Q1) |
| 1.10 | `aStackMeasuresItsCrossSizeAtItsAllocations` | `:660` `arm.run(root, 100, 50) == size(100, 30)` (Q3) |
| 1.11 | `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI` | `ContainerIntegrationTests.swift:84` `log.bounds["a"] == rect(0, 15, 40, 20)` (G1) |
| 1.12 | `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` | `:734` `finite.lastNativeLayoutWork.measureCalls == 51` |
| 1.13 | `aProposalTextInAStackIsShapedOncePerDistinctWidth` | `ContainerIntegrationTests.swift:157` `cache.misses == 12` |

The two performance literals (51 / 72 calls; 12 misses with 12 / 21 lookups)
were derived by hand before this red run; the derivations are the tests' doc
comments. Both equal the staged prototype's figures.

### What changed

`Sources/MetalUILayout/LayoutTree.swift`: one private `solveLinearStack`
(priority groups highest first; a group offered what remains minus every
lower-priority child's answer at main 0; least flexible first by answer at ∞
minus answer at 0, ties in declaration order; each offered `max(0, remaining /
left)`; the sum of the answers; the cross size of the answers at their
proposals) called by `measureNative` and `placeNative`. Placement re-solves at
the stack's measured cross size when its cross proposal is nil and advances
by the answers. `stackChildProposal`, `resolvedStackMainSize`, `stackMainSize`,
`spacerProposal`, `stackPlacementProposal`, `stackMainAllocations` and
`stackMain` are gone. `nativeLayoutPriority` reads a spacer as −∞ and passes a
single child's priority through a linear stack or overlay; `spacerLength`
answers ∞ at ∞. Doc comments: `newNativeSpacer`, `isNativeSpacer`,
`ProposalLayout.swift`'s `priority`/`isSpacer`, `HStack`/`VStack`.

`Tests/MetalUILayoutTests/ReferenceLinearStack.swift` rewritten to the same
rules through public proxies only; it no longer reads `isSpacer`. Its
`SpacerBlindLinearStack` control became `OrderBlindLinearStack` (no
flexibility sort): after `CN-B` a spacer is distinguished by priority alone, so
a spacer-blind reference is the reference.

### The fourteen existing tests

Exactly the spec's list went red (53 issues, the staged prototype's count), and
each was re-derived by hand, not copied from the run:

| test | change |
|---|---|
| `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` | 16/27/25 → **65/54/90**, re-derived; (4)'s a3 rect unchanged. Differs from the prototype's 47/51/66 — see `CN-B`'s "Lane 1, as built" |
| `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules` | single-child stack 0 → 2 (L3); overlay over a spacer −∞ (X8); a bare spacer arm added, −∞ (E) |
| `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` | literals re-derived (157×91; (96, 19, 48, 11); (88, 37, 66, 71); (159, 69, 11, 8)); compares a transposed (vertical) tree too, closing record §09's "horizontal only"; priority- and order-blind controls must disagree on both. **Spacer cross extents are not excluded yet**: in lane 1 the built-in marks nothing, so the two agree everywhere; lane 2's marks will need the exclusion |
| `aDifferentRootProposalReMeasuresAndMovesTheRects` | proposal lists gain the (∞, 80) and (0, 80) probes; rects unchanged |
| `aLinearStackReadsPriorityThroughAnOverlayAttachment` | the prioritized leaf is offered 100 (G2c's rule), not 80; rects unchanged |
| `aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder` | asserts every proposal's cross and the offers 56.5 / 83; rects unchanged |
| `aNativeLinearStackDividesConcreteSurplusBetweenSpacers` | offers 40 / 50, the spacer served last; rects unchanged |
| `aNativeNodeRegisteredTwiceIsNotRejected` | arm a's measure calls 1 → 4; lane 4 replaces the test |
| `aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder` | offers 37.5 / 65; rects unchanged |
| `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `…Height…` | the stack now sits under `.fixedSize` on its main axis, keeping the axis unspecified (the question the tests ask); trailing leaf (80, 0) / (0, 80) — y/x 0 because `.fixedSize` places the stack at its answer |
| `aResetTreeMeasuresItsNewRegistrationsFromScratch`, `aSecondComputeNativeLayoutCallReMeasuresEveryLeaf` | calls per leaf per call 1 → 3 (two probes and an offer) |
| `measuringANativeTreeWritesNoRect` | 157×38 → **157×91**: B's unmarked spacers claim the 71pt cross offer; lane 2 expected to restore 38 |

### Suite

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`: **`Test run with 1316 tests in 1 suite
passed`** (1303 + 13), 0 `error:`, no `warning:` besides SwiftPM's deprecation
notice. Under the default build system (`swift build --build-tests`, `swift
test --no-parallel`) the run prints six summary lines, 65 + 717 + 55 + 28 + 429
+ 22 = **1316, all passed**, 0 `error:`. Goldens: `find Tests -name "*.json" | wc -l` = 97, none modified. No
guard added (66). No stored property changed on a public type, so no
`swift package clean` was owed.

### Mutations

Run after `31fd2ba` in this worktree, each applied, built, the unfiltered suite
run, the file restored with `git checkout`, `git status --short` empty after
every one:

| mutation | red tests (the named test in bold) |
|---|---|
| M1 sort by flexibility descending | **1.1**, 1.3, 1.4, 1.5, 1.10, 1.11, reference equivalence, `measuringANativeTreeWritesNoRect` (71 issues) |
| M2 no flexibility sort (and no probes) | **1.1**, 1.3, 1.5, 1.10, 1.11, 1.12, 1.13, branching tree, reference equivalence, four invalidation/registration tests (50) |
| M3 drop the lower groups' reservation | **1.2**, 1.3, 1.4, 1.7, 1.8, 1.11, reference equivalence, surplus test, `layoutPriorityPreservesASpacersFlexibleExpansion`, `measuringANativeTreeWritesNoRect` (50) |
| M4 a spacer's priority 0 | **1.3**, **1.7**, 1.2, 1.4, 1.8, 1.11, proxy-surface test, surplus test (22) |
| M5 skip distribution when a spacer is present | **1.4**, 1.2, 1.3, 1.7, 1.11, 1.12, reference equivalence, five more (66) |
| M6 clamp the total to the proposal | **1.5** only (2) |
| M7 nil main proposal read as 0 | **1.6**, 1.12, both ideal-frame tests, two scroll-view tests, `aNegativeSpacerMinimumIsAccepted` (13) |
| M8 restore `spacerLength`'s `isFinite` | **1.7** only (1) |
| M9 delete the single-child pass-through | **1.8**, proxy-surface test (5) |
| M10 pass through at any child count | **1.8**, branching tree (7) |
| M11 place with the first-pass proposal | **1.9**, 1.6, 1.12, 1.13 (9) |
| M12 report the cross size from the main-0 probes | **1.10**, 1.2, 1.6, 1.7, branching tree, overlay-attachment test, registered-twice test (18) |
| M13 `HStack`'s axis swapped | **1.11**, 1.13, and ten of the eleven the spec measured at `9e439cb` (not `aProposalScrollViewForwardsItsHorizontalAxisToTheNativeViewport`, green now), 12 tests / 23 issues |
| M14 disable the measurement cache | **1.12**, 1.13, branching tree, nine more (32) |
| M15 probe groups of one | **1.12** is NOT among them; branching tree, 1.2, 1.7, registered-twice test (9) |
| M16 key the shaping cache on width rounded to an integer | **nothing red** |
| M17 shape without the shaping cache | **1.13**, five `ShapingCache` tests (12) |

Two named mutations did not redden their named test:

- **M15 vs 1.12.** Probing a group of one adds a probe per single-member group.
  The nested tree has no such group at a finite main proposal (every level's
  priority-0 group has three members; the spacer's −∞ group is one member but
  is offered, not probed, and a spacer is not a call). So 1.12 cannot see it;
  1.2 (G2's `a` asked only at 70), 1.7 (SP9/SP10/X8's `a` asked once) and the
  branching tree do. The mutation is covered, by other tests than the spec
  named.
- **M16 vs 1.13, a finding.** Rounding widths before keying changes no key
  collision on this fixture: per text the four widths (∞, 0.5 → 1, an offer
  near 200, a one-line answer near 30–130) stay distinct after rounding, so the
  misses stay 12. The mutant does not behave differently on this tree, so it is
  not a coverage gap of 1.13 but an equivalent mutation here; no test in the
  suite reddens either. Not banked as covered.

### Demo comparison (`CN-S` row 1)

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>`: no real windows
captured, no demo launched. Stand-in: the `CN-R` harness (`main.swift` up to
`runDemo()`, `SI`-prefixed, a real `Window` over `FakePlatformWindow`, scale 1,
`fakeSurface.readPixels()` and the scene dump), twelve images, on
`git archive 9e439cb` and `git archive 31fd2ba`, debug builds.
`demoContent()` names no proposal type (grep over lines 384–917 of `main.swift`),
so the legacy images are not evidence for this lane.

| comparison | differing pixels |
|---|---|
| control: base light vs dark | 1 048 576 |
| control: base default vs modal | 1 030 498 |
| control: base default vs animation | 210 027 |
| control: base preview light vs dark | 1 048 576 |
| base f0 vs f3 | 0 |
| eight legacy images + `small560-default-light` | **0**, scenes identical |
| `preview-light`, `preview-dark` | **155 248** each, bbox (84, 661)–(939, 939) |
| `small560-preview-light` | **93 522**, bbox (0, 0)–(559, 559) |

Exactly `CN-S` row 1. The moved rects, from the scene dumps:

- **1024 preview:** `PreviewToggle`'s rectangle, `Rectangle(168×95)
  .aspectRatio(16/9)` in the bottom `HStack(spacing: 12)` beside two fixed
  168×64 panels, goes 168×94 at (264, 846) → **496×279 at (264, 661)**; the
  right panel moves x 412 → 740 and the row's other rects re-centre vertically
  in the taller row (y 861 → 769). The kernel's aspect ratio still answers the
  ratio size, not its child (`CN-G`, lane 2), so its flexibility is large, it is
  served after the two fixed panels (G1/X1's order) and offered 856 − 24 − 336
  = 496. SwiftUI's AR4 keeps it 168×95; lane 2 is expected to (`CN-S` row 2).
- **560 preview:** the toggle is served last with little left, 123×69 → 32×18,
  and the content's root answer grows past the window, 560×594 at (0, −17) →
  668×564 at (−54, −2), centred by the root `ZStack`: a stack answers the sum of
  its children's answers, overflow included (G9, X13), where it clamped to its
  proposal before. Every other moved rect in that image is the same
  translation.

### Not done here, and why

- The spacer's 8pt default, its cross-axis zero, the infinite answers of a
  frame and a viewport, and `aspectRatio` answering its child: lane 2 (`CN-C`,
  `CN-F`, `CN-G`).
- `CLAUDE.md`, `AGENTS.md`, the plan and the record index are untouched until
  the Docs phase. Of `CLAUDE.md`'s "unprobed kernel behaviour" bullets, a
  spacer as the only surplus-taker, a stack with a spacer never compressing,
  and measure-at-nil-versus-place-at-allocations are superseded by this lane;
  whether `.frame(maxWidth: .infinity)` in a stack now matches G4 was not
  measured here (test 2.7 is lane 2's). `SA-N` item 8 is closed (1.8).

### Verifier round (lane 1)

**Verdict `ok: true`, three minor issues, no fix round.** Quoted from the
verifier (at `65822a8`): `swift build --build-system native --build-tests`,
then `swift test --build-system native --no-parallel` → `Test run with 1316
tests in 1 suite passed`, 0 `error:`, the only `warning:` SwiftPM's deprecation
notice, only the two gated tests skipped; 97 goldens, `git diff 9e439cb HEAD --
'*.json'` empty; re-run after its mutations, 1316 again and `git status
--short` empty.

- **Red first, re-taken independently.** `31fd2ba` touches neither new test
  file, and nothing under `Sources/` or `Tests/` moved between `9e439cb` and
  `f657598^`. The two test files from `f657598`, on a `git archive 9e439cb`
  tree, filtered: 13 tests failed with 81 issues (2 with 9, 11 with 72), as
  above.
- **Probe re-run.** `/usr/bin/swift docs/probes/swiftui-stack-algorithms.swift`
  exit 0, 608 lines, all identical to the header's record. G1, G2, G5b, G6,
  G13, G21, G24, SP9, SP10 and AR4's offers were checked against
  `solveLinearStack` by hand; each matches.
- **Demo comparison, re-taken** on fresh `git archive` trees of `9e439cb` and
  HEAD with the implementer's harness (diffed against `main.swift`): every
  control and every figure in "Demo comparison (`CN-S` row 1)" above,
  identical.

The verifier's mutations, each unfiltered ("new" = not in the lane's table):

| mutation | red |
|---|---|
| V1 flexibility sort descending (lane M1) | `aStackServesItsLeastFlexibleChildFirst`, `aGreedyChildTakesTheSurplusAheadOfASpacer`, `aStackWithASpacerStillCompressesItsOtherChildren`, `aStackAnswersTheSumOfItsChildrensAnswers`, `aStackMeasuresItsCrossSizeAtItsAllocations`, `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI`, `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`, `measuringANativeTreeWritesNoRect` |
| V2 (new) tie-break reversed, later declaration first | `aStackServesItsLeastFlexibleChildFirst`, `aStackAnswersTheSumOfItsChildrensAnswers`, `aSingleChildStackPassesItsChildsPriorityThrough`, `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity`, `aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`, `aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`, `aNativeLinearStackDividesConcreteSurplusBetweenSpacers` |
| V3 lower groups' minimums not reserved (lane M3) | `aLowerPriorityGroupKeepsItsMinimumsReserved` and ten more (1.3, 1.4, 1.7, 1.8, 1.11, reference equivalence, surplus spacers, `layoutPriorityPreservesASpacersFlexibleExpansion`, measuring-writes-no-rect, branching tree) |
| V4 (new) `remaining` not reduced across priority groups | `aLowerPriorityGroupKeepsItsMinimumsReserved` and sixteen more, including `hStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling`, `vStack…`, `infiniteLayoutPrioritiesAreAcceptedAndOrderLikeFinitePriorities`, `aLinearStackReadsPriorityThroughAnOverlayAttachment`, `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer`, `nativeCompositionUsesColumnFrameAndPaddingProposals`, `theProposalModifiersAcceptWhatTheKernelAccepts` |
| V5 (new) spacing not subtracted before distribution | `aStackAnswersTheSumOfItsChildrensAnswers`, both native stack forwarding tests, surplus spacers, `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer`, `layoutPriorityPreservesASpacersFlexibleExpansion`, reference equivalence, branching tree, measuring-writes-no-rect, `nativeCompositionUsesColumnFrameAndPaddingProposals` |
| V6 (new) the `max(0, …)` floor on an offer removed | `aStackAnswersTheSumOfItsChildrensAnswers`, `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` |
| V7 spacer priority 0 (lane M4) | `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity` and seven more, including `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules` |
| V8 `spacerLength`'s `isFinite` restored (lane M8) | `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity` only |
| V9 (new) the `ZStack` single-child pass-through removed, the linear stack's kept | `aSingleChildStackPassesItsChildsPriorityThrough` only |
| V10 (new) vertical second pass disabled | `aStackPlacesAfterASecondPassAtItsOwnCrossSize` only |
| V11 (new) horizontal second pass disabled | `aStackPlacesAfterASecondPassAtItsOwnCrossSize`, `aStackAtANilOrInfiniteMainProposalOffersItToEveryChild`, `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork`, `aProposalTextInAStackIsShapedOncePerDistinctWidth` |
| V12 (new) distribute at an infinite main proposal | `aStackAtANilOrInfiniteMainProposalOffersItToEveryChild` only |
| V13 (new) cross size from the minimum, not the maximum | `aStackMeasuresItsCrossSizeAtItsAllocations` and twelve more, including `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` and `aNativeNodeRegisteredTwiceIsNotRejected` |
| V14 total clamped to the main proposal (lane M6) | `aStackAnswersTheSumOfItsChildrensAnswers` only |
| V15 (new) a group's `remaining` shrinks by what was offered, not answered | `aStackServesItsLeastFlexibleChildFirst` and eleven more |

Every mutation reddened its named test. The three minor issues, as dispositioned:

1. **The preview is visibly worse at this commit** (toggle 496×279 at 1024,
   32×18 with content overflowing at 560): expected, `CN-S` row 1, handed to
   lane 2, which restored 168×95 (row 2).
2. **Two tests pinned intermediate answers** (`measuringANativeTreeWritesNoRect`
   157×91; `aNativeNodeRegisteredTwiceIsNotRejected` 4 calls): lane 2 restored
   157×38; lane 4 replaced the registered-twice pin with an exit test.
3. **A NaN flexibility orders a group inconsistently.** A child whose answer
   is ∞ both at main 0 and at main ∞ has flexibility ∞ − ∞ = NaN; the
   comparator `l != r ? l < r : lhs < rhs` then answers false both ways. No
   built-in node reaches it; a custom `ProposalLayout` that always answers ∞
   can. **Not fixed, not probed, not pinned** at `6d59cf0`
   (`LayoutTree.swift:1239`, unchanged). Hazard 6 below.

## Lane 2 — spacer cross axis and minimum, infinite answers, aspect ratio (the rest of `CN-C`, the rest of `CN-F`, `CN-G`)

2026-09-16. Commits: `32f57fb` (probe revision 5), `476a894` (tests, red),
`63387f6` (implementation and the nine re-derived tests), then this record
with the as-built addenda to `CN-B`, `CN-C`, `CN-F` and the 2.4 doc comment.

### Probe revision 5, first

Test 2.7's spec arm G4 (`HStack(0){a 20; b 20 .frame(maxWidth: .infinity)}`)
is **green on arrival since lane 1**: under `FR-B` the frame answers its child
at ∞, so a and the frame both have flexibility 0 and are served in declaration
order, a at 100 → 20, the frame at 180 → 180 — SwiftUI's allocation by
accident. G4 cannot see `CN-F`. Rather than state an unprobed order, the lane
extended `docs/probes/swiftui-stack-algorithms.swift` (additive, after R4; run
twice under `/usr/bin/swift`, Apple Swift 6.4, macOS 27.0 26A428, exit 0,
byte-identical; the 607 revision-4 output lines unchanged, `diff` empty):

- **G4r** — the same frame declared first: frame 180, b at (80, 0), a at 180.
- **G4f** — the frame beside a bounded `a 0..80`: a served first at 100 → 80
  at x 120, the frame 120, b at (50, 0).

G4 is their control. Both are red before this lane (G4r's frame is served
first at 100) and are arms of tests 2.3 (kernel) and 2.7 (G4r, element API).

### Red first

Seven new tests: 2.1, 2.2, 2.3, 2.5, 2.6 appended to
`Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`, 2.4 in
`NativeValidationTrapTests.swift` (beside `anInfiniteStoredRectTraps`), 2.7 in
`Tests/MetalUITests/ContainerIntegrationTests.swift`. Run filtered against
`32f57fb`: `Test run with 7 tests in 0 suites failed … with 75 issues`, every
test red. First failure each:

| # | test | first failure |
|---|---|---|
| 2.1 | `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis` (20 issues) | `:818` `arm.run(root, nil, nil) == size(48, 20)` (SP1) |
| 2.2 | `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` (18) | `:916` `arm.run(root, 200, 50) == size(90, 20)` (K2b) |
| 2.3 | `anInfiniteProposalIsAnsweredWithInfinity` (9) | `:1010` `arm.measure(root, .infinity, .infinity) == size(.infinity, 20)` (D12) |
| 2.4 | `aCustomLayoutPlacingAChildAtAnInfiniteProposalTraps` (2) | `NativeValidationTrapTests.swift:497` `expected exit status ".failure", but ".exitCode(EXIT_SUCCESS)"` |
| 2.5 | `anAspectRatioAnswersItsChildsAnswerToTheRatioProposal` (16) | `:1069` `arm.run(root, 500, 300) == size(168, 95)` (AR1) |
| 2.6 | `anAspectRatioTreatsInfinityAsAConcreteAxis` (7) | `:1138` `arm.measure(root, .infinity, .infinity) == size(168, 95)` (K4d) |
| 2.7 | `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI` (3) | `ContainerIntegrationTests.swift:202` `log.bounds["b"] == rect(28, 0, 20, 20)` (SP1) |

Green on arrival inside red tests: 2.3's G4 arm (above), 2.6's K4f (the old
intrinsic branch also answered ∞×∞ there), 2.7's G4 arm.

**2.4 differs from the spec's wording.** The spec said to cite an existing
`SA-J` trap test if one places a custom child at ∞. `anInfiniteStoredRectTraps`
does, with a proposal-echoing leaf, which answered ∞ before this lane too; the
lane wrote the frame form instead, because it is the path `CN-F` newly opens
and it was red before (the frame answered 20 and nothing trapped).

### What changed

`Sources/MetalUILayout/LayoutTree.swift`:

- `spacerAxes: [Int: ProposalStackAxis]`, a stored property on the public
  `LayoutTree` — **`swift package clean` before the suite**, as `CN-R`
  requires; `reset(generation:)` clears it.
- `markSpacers(_:axis:)`, called by `newNativeLinearStack` for each child: a
  spacer keeps its first mark (its nearest stack's, which registers first);
  the walk passes `layoutPriority`, `padding`, `frame`, `fixedSize`,
  `aspectRatio` and both children of `overlayAttachment`, and returns at
  `leaf`, `overlay`, `linearStack`, `scrollViewport`, `custom` (an exhaustive
  switch, so a new node kind must choose).
- `.spacer` measurement answers 0 on the marked stack's cross axis;
  `newNativeSpacer(nil)` stores `ProposalSpacing.platformDefault` (new public
  `enum` in `Sources/MetalUILayout/ProposalSpacing.swift`, 8).
- `framedSize`'s greedy gate and `resolvedViewportDimension` lose
  `isFinite`.
- `.aspectRatio` measures and places through `aspectRatioProposal` (∞
  concrete, nil×nil passed through) and answers / places the child at the
  child's answer; `aspectRatioSize` and its intrinsic branch are gone.

Doc comments rewritten: `newNativeFrame` (the `FR-B` paragraph), `framedSize`
(third bullet), `newNativeAspectRatio` (and its negative-ratio line: −2 at
100×80 now *proposes* 100×−50), `newNativeSpacer`, `newNativeLinearStack`,
`newNativeScrollViewport`, `ProposalLayout.swift`'s `isSpacer`,
`NativeModifiedContent.swift`'s `.aspectRatio`, `NativeElements.swift`'s
`Spacer`.

### The nine existing tests

Exactly the spec's list went red (9 tests, 34 issues), plus nothing else:

| test | change |
|---|---|
| `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` | deleted, replaced by 2.3 (a pointer comment stays in `NativeLayoutTests.swift`); 1316 + 7 − 1 = 1322 |
| `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`, `aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes` | child becomes a proposal-echoing leaf (P8's `Color`), numbers unchanged — `CN-G`'s diagnosis held |
| `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`, `…Fill…` | the fixed 20×10 child now stays 20×10 at (40, 35) in both (AR1); the proposals (100×50 vs 160×80) still tell the modes apart |
| `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` | 65/54/90 → **62 calls / 53 hits / 87 misses**, re-derived by hand before the run from `31fd2ba`'s tree: only branch B's aspect ratio changes (no spacer in the tree), B's three evaluations 17/1/11 → 14/1/8 and its placement 5 → 4 hits. The prototype moved by the same −3/−1/−3 (66/51/47 → 63/50/44) |
| `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` | literals re-derived: **157×38**, second spacer (88, 46, 66, 0), last leaf (159, 42, 11, 8). The reference stack now reads `isSpacer` and leaves spacers out of its cross size (a `ProposalLayout` cannot mark a node — SwiftUI's custom layouts cannot either, contract probe E); for the three spacer nodes only the main extent is compared (and no measured width transposed). Both controls still disagree |
| `aNativeLinearStackDividesConcreteSurplusBetweenSpacers` | stack 100×40 → **100×10**; spacer (35, 0, 40, 40) → (35, 20, 40, 0) |
| `measuringANativeTreeWritesNoRect` | 157×91 → **157×38**, as lane 1 expected |

Unchanged, and so confirmed: 1.12 (51 / 72 calls) and 1.13 (12 misses) — the
nested tree's spacers now answer 0 on their cross axis without moving a call.

### Suite

After `swift package clean`: `swift build --build-system native --build-tests`,
`swift test --build-system native --no-parallel` → **`Test run with 1322 tests
in 1 suite passed`**, 0 `error:`, no `warning:` besides SwiftPM's deprecation
notice (re-run after the doc-only edits: the same). Default build system:
65 + 718 + 55 + 28 + 434 + 22 = **1322, all passed**, 0 `error:`. Goldens:
97, `git diff 9e439cb -- '*.json'` empty. No guard added (66).

### Mutations

After `63387f6`, in this worktree, one at a time: applied, built (native),
unfiltered suite, `git checkout`, `git status --short` empty after each.

| mutation | red tests (the named test in bold) |
|---|---|
| L1 nil → 0 in `newNativeSpacer` | **2.1**, **2.7**, 2.2 (16 issues) |
| L2 delete the marking | **2.1**, 2.2, reference equivalence, surplus spacers, measuring-writes-no-rect (43) |
| L3 the walk stops at `frame` | **2.2** only (4: K2d, SP19) |
| L4 skip an overlay attachment's content side | **2.2** only (1: K2e's spacer) |
| L5 walk into an `overlay` node | **2.2** only (3: K2a) |
| L6 restore `isFinite` in `framedSize` | **2.3**, 2.4, 2.7 (11) |
| L7 restore `isFinite` in `resolvedViewportDimension` | **2.3** only (2: SC1 both axes) |
| L8 remove checkpoint 3's width term | **nothing red** — see below |
| L8b remove checkpoint 3's x and width terms | **2.4**, `anInfiniteStoredRectTraps`, `aNonFinitePlacementPositionTraps` (6) |
| L9 answer the ratio size | **2.5**, 2.6, 2.2 (K2b), both integration fit/fill tests (15) |
| L10 filter ∞ to nil in `aspectRatioProposal` | **2.6** only (4) |

**L8, a finding, not a coverage gap of 2.4 alone.** An ∞-wide rect never
reaches checkpoint 3 with a finite x on these paths: the frame centres its
child at x = (∞ − 20) × 0.5 = ∞, and a custom record at a top-leading anchor
stores x − 0 × ∞ = NaN, so the x term traps one node later with the same
"non-finite rect" message. L8b proves the test sees checkpoint 3. The width
term alone was already unpinned before this lane (`anInfiniteStoredRectTraps`
has the same shape); a root-bounds arm with an infinite width would pin it.
Not added here; added in the verifier round below.

### Verifier round (lane 2)

The verifier's mutations M3d (the walk stops at `fixedSize`), M10 (checkpoint
3's width term), M11 (`reset` keeps the marks) and M12 (`.aspectRatio` places
its child in the node's bounds) left the suite green.

- **M3d, the major.** The only evidence for the mark reaching through
  `fixedSize` was K2c, whose 20pt siblings set the stack's height whether the
  spacer is marked or not. Probe revision 6 adds K2f–K2j, which discriminate:
  `HStack(0){Spacer().fixedSize()}` at nil is **8×0** against its `ZStack`
  control's 8×8 (K2g/K2f), and `{a20; Spacer(minLength: 30).fixedSize(); b20}`
  is **70×20** against the `ZStack`-wrapped control's 70×30 (K2i/K2j). SwiftUI
  does mark through `fixedSize`; `CN-C` stands, its citation corrected (probe
  reading, decisions doc, `markSpacers`' doc). The K2g and K2i arms join
  test 2.2.
- **M11.** `aResetTreeMeasuresItsNewRegistrationsFromScratch` gains a spacer
  arm: a spacer marked by an `HStack`, a reset, and a bare spacer at the same
  index measured at 100×50 answers 100×50 (SPB3), not 100×0.
- **M10.** New exit test `anInfinitelyWideRootBoundsTraps`: a leaf root in
  bounds (0, 0, ∞, 10) keeps a finite x, so only the width term traps.
- **M12, recorded as unpinned, not pinned.** `.aspectRatio` places its child
  at the child's measured answer; every arm places the node in bounds equal
  to that answer, so placing the child in the bounds is indistinguishable.
  The clause is observable only where bounds exceed the answer — a window-root
  aspect ratio — and which SwiftUI placement applies there is unprobed. Owner:
  lane 4's root placement (`CN-J`).
- `ProposalSpacing`'s doc no longer says default stack spacing uses the
  constant: no stack reads it until lane 3 (`CN-H`).

Measured after `103bce0`, one at a time, unfiltered native suite, source
restored and `git status --short` empty after each: M3d reddens
`theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` only (3 issues:
K2g size, K2i size, K2i b rect); M11 reddens
`aResetTreeMeasuresItsNewRegistrationsFromScratch` only (1); M10 reddens
`anInfinitelyWideRootBoundsTraps` only (2). Unmutated: **`Test run with 1323
tests in 1 suite passed`** (+2 arms in existing tests, +1 test), 0 `error:`,
no `warning:` besides the deprecation notice; goldens 97, unchanged against
`9e439cb`. Probe revision 6: exit 0, run twice byte-identical, 626 output
lines, the first 613 byte-identical to revision 5's record.

### Demo comparison (`CN-S` row 2)

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>`: no real window
captures. Stand-in: lane 1's harness (`scratchpad/harness/gen.py`, twelve
images through a real `Window` over `FakePlatformWindow`) on `git archive
63387f6`, against lane 1's `9e439cb` images. `demoContent()` still names no
proposal type, so the legacy images are not evidence.

| comparison | differing pixels |
|---|---|
| controls, base and head alike: light vs dark / default vs modal / default vs animation / f0 vs f3 / preview light vs dark | 1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576 |
| eight legacy images + `small560-default-light` | **0**, scenes identical |
| `preview-light`, `preview-dark` | **188** each, bbox (264, 845)–(431, 865) |
| `small560-preview-light` | **64 199**, bbox (0, 0)–(559, 559) |

Exactly `CN-S` row 2. Moved rects, from the scene dumps:

- **1024 preview:** two rects. `PreviewToggle`'s `Rectangle(168×95)
  .aspectRatio(16/9)` 168×94 at (264, 846) → **168×95 at (264, 845)**, and its
  `.topTrailing` 20×20 badge (412, 846) → (412, 845). Base: the ratio size
  168×94.5, rounded; now the child's own answer (AR1, AR4), vertically centred
  in the row one point higher.
- **560 preview:** every rect is translated except inside the bottom row. The
  toggle 32×18 (lane 1) → **168×95** (AR4); the bottom row is now the widest,
  168 + 12 + 168 + 12 + 168 = 528, plus 2 × (36 + 48) = **696**, so the root's
  answer 668×564 → 696×603 (G9/X13 overflow), stored rounded at (−68, −22)
  696×604 from −21.5, centred by the root `ZStack`. Height +39 = the row 64 →
  95 (+31) and the `Spacer()` between the panels and that row now at its 8pt
  minimum where it was 0 (CN-C, SP1/K1: the row starts 48 = 20 + 8 + 20 below
  the priority panels, 40 before).

### Not done here, and why

- `CLAUDE.md`, `AGENTS.md`, the plan and the record index: the Docs phase.
  Candidates it should carry: `CLAUDE.md`'s "unprobed kernel behaviour"
  bullets on `.frame(maxWidth: .infinity)` in a stack (now expands, G4r/G4f)
  and "a `Spacer` also claims the proposed cross axis" (now 0 inside a stack);
  `SA-N` items 2 (`Spacer()`'s 8) and 3 (`aspectRatio` at nil×nil) closed;
  `FR-B` reversed; the inert/limit note that checkpoint 3's width term alone
  is unpinned.
- Default spacing beside a spacer is lane 3's (`CN-H`); nothing here inserts
  it.

## Lane 3 — platform-default spacing and typed stack alignments (`CN-H`, `CN-I`)

2026-09-16. Commits: `6adf624` (tests and guards, red), `f916d1c`
(implementation), `91ea9af` (probe revision 7, SC5c/SC5), `ef431b0` (the SC5
arm in test 3.1), then this record with the as-built addenda to `CN-H` and
`CN-I` and the spec's count note.

### Red first

Five tests — 3.2 appended to `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`,
3.1, 3.3, 3.4, 3.5 to `Tests/MetalUITests/ContainerIntegrationTests.swift` —
and three guards in a new `Tests/MetalUITests/ContainerCompileGuards.swift`.

**Against `4830b22` the test targets do not compile**: `'nil' is not
compatible with expected argument type 'Double'` at every `spacing: nil`
(`NativeStackDistributionTests.swift:1196`, `:1200`;
`ContainerIntegrationTests.swift:269`, `:276`, `:284`, `:292`, `:300`), and for
3.4 `cannot find type 'VerticalAlignment' in scope` (`:397`), `cannot find type
'HorizontalAlignment' in scope` (`:409`), `argument 'spacing' must precede
argument 'alignment'` (`:401`, `:413`, `:447`).

To see runtime red lines, a **temporary, uncommitted shim** gave the kernel
registrar (and the two `MetalUI` forwards) `spacing: Double?` mapping nil to
the pre-lane explicit 8, and 3.4 was removed from the build (3.5's two
new-order calls respelled in the old order). Native build, filtered:
`Test run with 7 tests in 0 suites failed … with 40 issues`. The shim was
reverted with `git checkout` on the three `Sources` files (clean before it);
`git status --short` showed only the new tests.

| # | test | first failure |
|---|---|---|
| 3.1 | `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (9) | `:285` `kernelRun(tree, root) == SizeD(width: 48, height: 20)` (kernel SP2; also SP3, SP7 and the element SP2/SP3/SP7) |
| 3.2 | `defaultSpacingBesideASpacerIsDecidedPerEdgeThroughItsWrappers` (24) | `:1268` `answer == size(40, 20)` (K3a, first of the zero-spacing loop; also K3c, K3f, K3q, K3n, K3p) |
| 3.3 | `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer` | green on arrival, its `#require` (SP3 ≠ SP4) holding |
| 3.4 | `hStackAndVStackPlaceChildrenAtTheirTypedAlignments` | does not compile (above) |
| 3.5 | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` | green on arrival, its `#require`s holding |
| G1 | `aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks` (4) | `ContainerCompileGuards.swift:59` `!hStack.succeeded` (both negatives compiled) |
| G2 | `theTypedStackInitializersCompileInSwiftUIsArgumentOrder` (1) | `:90` `result.succeeded` — `argument 'spacing' must precede argument 'alignment'`, `'nil' is not compatible with expected argument type 'Pixels'` |
| G3 | `theSpacingFirstStackInitializersAreDeprecated` (2) | `:108` `deprecations(result) == 2` (0) |

Green on arrival inside 3.2 under the shim: the default-8 arms (K3 control,
K3h, K3i, K3j, K3k, K3m), which an explicit 8 also produces.

### What changed

`Sources/MetalUILayout/LayoutTree.swift`: `newNativeLinearStack(spacing:
Double? = 0)` — a given spacing still traps unless finite; the private
`NativeNode.linearStack` stores `Double?`. `stackGaps(_:axis:spacing:)` returns
one gap per adjacent pair (the given spacing, or per pair 0 at a zero-spacing
edge, else `ProposalSpacing.platformDefault`); `solveLinearStack`'s total and
`placeNative`'s cursor read it. `zeroSpacingEdges(_:axis:)`: a spacer both;
`layoutPriority`, `frame`, `fixedSize`, `aspectRatio` and an overlay
attachment's primary the child's; `padding` the child's AND a zero inset on
that edge; a non-empty `overlay` the AND over its children; anything else
neither. No stored property changed on `LayoutTree`; `HStack`/`VStack`'s stored
property types did, so the suite ran after `swift package clean`.
`Frame.requestNativeLinearStack` and `LayoutPass.requestNativeLinearStack`
take `Double?` (default 0).

`Sources/MetalUI/StackAlignment.swift` (new): `VerticalAlignment { top,
center, bottom }`, `HorizontalAlignment { leading, center, trailing }`, internal
`proposalAlignment` mappings and factor-reading initializers.
`NativeElements.swift`: `HStack`/`VStack` store `spacing: Pixels?` and the
typed alignment; `init(alignment:spacing:content:)` with `.center`/`nil`
defaults; the spacing-first `ProposalAlignment` initializer is kept,
deprecated, without defaults, forwarding the cross factor. `ProposalScrollView`'s
several-children lowering passes `nil`. `main.swift`'s two `VStack(spacing:
…, alignment: .leading)` and `NativeLayoutIntegrationTests.swift`'s one moved
to the new order. Doc comments: `newNativeLinearStack`, `HStack`, `VStack`,
`Spacer`, `LayoutPass.requestNativeLinearStack`, `ProposalSpacing` (no longer
"no stack reads this constant yet"), `ProposalScrollView`'s lowering comment.

**Existing tests that changed: none** (the spec's stage-3 list). Only the one
call site's argument order moved. `aNaNStackSpacingTraps` is green.

### Suite

After `swift package clean`, `swift build --build-system native
--build-tests`, unfiltered: **`Test run with 1331 tests in 1 suite passed`**,
0 `error:`, no `warning:` besides SwiftPM's deprecation notice. Default build
system (`swift build`, `swift test --no-parallel`): six summary lines, 65 + 725
+ 55 + 28 + 436 + 22 = **1331**, all passed, 0 `error:`, 0 `warning:`. Guards
(`grep -c canTypecheck`): 66 + 3 = **69**; the three printed their
diagnostics in the native run, so they ran. Goldens: 97, unchanged against
`9e439cb` (`git diff --quiet`).

The spec expected 1327: it did not count the three guards, which are `@Test`s,
and predates lane 2's verifier round (+1). 1323 + 5 + 3 = 1331.

### Mutations

`f916d1c` (and `ef431b0` for M9), each applied in this worktree, built
`--build-system native --build-tests`, the unfiltered suite run, `git checkout
-q Sources` (committed tree), `git status --short` empty after each.

| mutation | red (named test in bold) |
|---|---|
| M1 nil → 8 at every pair ("apply 8 beside spacers") | **3.2** (24 issues), **3.1** (9) |
| M2 nil → 0 at every pair ("default nil → 0") | **3.1** (7), **3.5** (its `#require` `textText != control`), 3.2 (17), `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing`, `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`, `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`, `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` |
| M3 `zeroSpacingEdges` reads `isNativeSpacer` | **3.2** only (22): K3a, K3b, K3c, K3e, K3f, K3g as the spec named, and K3l, K3o, K3q, K3n, K3p |
| M4 padding transparent whatever its inset | **3.2** only (6): K3m, K3n, K3p |
| M5 an overlay attachment's zero edges from either child (walks into the content) | **3.2** only (3): K3i |
| M6 OR instead of AND over a `ZStack`'s children | **3.2** only (4): K3j, K3k |
| M7 an explicit spacing becomes 0 at a zero-spacing edge | **3.3** (SP4), `aNativeLinearStackDividesConcreteSurplusBetweenSpacers` (3), `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` (11) |
| M8 `VerticalAlignment.top` maps to `.center` | **3.4** only (1: A1 `.top` a) |
| M9 `ProposalScrollView` lowers with an explicit 8 | **nothing red at `f916d1c`** — a finding, see below; after `ef431b0`, **3.1**'s SC5 arm (`:359`, filtered run) |
| G1 `VerticalAlignment` gains `leading` | **G1** only (2: `:59`, `:60`) |
| G2 the new `HStack` initializer's parameters swapped | first attempt: `MetalUI` itself failed to build (its deprecated initializer forwards in the new order) and the run is discarded; re-run with that forward and test 3.4's call site moved to the mutant order: **G2** only (1: `:90`, `argument 'spacing' must precede argument 'alignment'`) |
| G3 `HStack`'s `@available(deprecated)` removed | **G3** only (1: `:108`, 1 deprecation) |

**M9, a finding.** At `f916d1c` nothing pinned the `nil` in
`ProposalScrollView`'s lowering beside a spacer: M2 shows the non-spacer gap is
pinned by two existing tests, but nil and an explicit 8 differ only at a
spacer's edge, and the mutant was proven to differ (SC5 reads b 28 below a under
it, 20 without it). Nor was it probed: SC3 shows the lowering is a default
stack, not how a spacer inside it is spaced. Probe revision 7 (`91ea9af`,
additive after K2j, run twice under `/usr/bin/swift`, Apple Swift 6.4, macOS
27.0 26A428, exit 0, byte-identical, 639 lines, the first 626 identical to
revision 6's record) measured it: vertically SC5c 28, SC5 20, so SwiftUI's
lowering does take no spacing beside the spacer; horizontally both read b at
(0, 180) and cannot discriminate. `ef431b0` adds the vertical arm to 3.1.

Not measured: whether the new spacing walk changes any work count — it calls no
measurement, and `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` and
the branching-tree test stayed green unmutated.

### Demo comparison (`CN-S` row 3)

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>`: no real window
captures. Stand-in: lane 1's harness (`scratchpad/harness/gen.py`, twelve images
through a real `Window` over `FakePlatformWindow`) on `git archive f916d1c`,
against lane 2's `63387f6` images (lane 2's later commits changed only comments
under `Sources/`) and lane 1's `9e439cb` images. **Lane 3 has no pixel
evidence** (`CN-S`): every preview stack gap names a spacing or sits between
two views, and `demoContent()` names no proposal type.

| comparison | differing pixels |
|---|---|
| controls, head: light vs dark / default vs modal / default vs animation / f0 vs f3 / preview light vs dark | 1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576 |
| all twelve images vs lane 2 | **0**, scenes identical |
| eight legacy images + `small560-default-light` vs `9e439cb` | **0**, scenes identical |
| `preview-light`, `preview-dark` vs `9e439cb` | **188** each, bbox (264, 845)–(431, 865) |
| `small560-preview-light` vs `9e439cb` | **64 199**, bbox (0, 0)–(559, 559) |

Exactly `CN-S` row 3 (= row 2); the moved rects are lane 2's.

### Not done here, and why

- `CLAUDE.md`, `AGENTS.md`, the plan and the record index: the Docs phase.
  Candidates: the inert row "`HStack`/`VStack`'s `alignment:` main-axis half"
  stays, re-worded to name the deprecated `init(spacing:alignment:content:)`
  (`CN-I`); the vocabulary line `HStack`/`VStack(spacing: 8, alignment:
  .center)` becomes `(alignment:spacing:)` with typed alignments and a nil
  default; `ProposalScrollView`'s "direct children 8pt vertical" probe bullet
  gains "none beside a spacer (SC5)"; a new divergence for `ProposalText`'s
  8pt vertical text-edge spacing (SwiftUI 0 / 4.74 / 8.15, `CN-H`, pin 3.5,
  owner task 11).
- K3f's placement (SwiftUI places b at 40 while reporting 40 wide) is not
  pinned; only its size is, as the spec says.
- The horizontal `ProposalScrollView` beside-spacer case is unprobed in a
  discriminating form (SC5 horizontal cannot tell).

### Verifier round (lane 3)

Written by the record pass; the lane's fixer was interrupted before writing it.

**First verifier (at `05bf236`), as the fixer's commits answer it.** It found
`CN-H`'s "none for anything else" clause unprobed: its only evidence was K3h,
a CROSS-axis `VStack{Spacer}`. The kernel read 56 for V1, V1b, V3, V3d and V4
and 20×56 for V1e, where SwiftUI reads 40 (and 20×40). The fix round:

- **`632b327`, probe revision 8.** The `Pass` layout (a custom layout that
  overrides only the two required methods), the `flexible` helper and the V
  group V1–V8, additive after SC5; run twice under `/usr/bin/swift`, exit 0,
  byte-identical; the 638 output lines before them identical to revision 7's
  record. Controls K3 48, SP3 40 and the non-spacer arms V1j, V3c, V3g, V4c 56.
  The readings are `CN-H`'s "Amended, lane 3's verifier round" bullets.
- **`dcd509d`, red.** Test 3.6
  `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges`
  (`NativeStackDistributionTests.swift`) carries every V arm: **red with 46
  issues**. Test 3.2 gains V6/V6c (a padded spacer sits after the gap its padded
  edge keeps: x 28 and x 20). New
  `theDeprecatedSpacingFirstStackInitializersForwardSpacingAndTheCrossFactor`
  (`ContainerIntegrationTests.swift`) calls the deprecated initializers through
  a protocol whose witness is deprecated (not diagnosed, so the 0-warning gate
  holds), with controls that must disagree.
- **`8a4a491`, the amended walk** (`zeroSpacingEdges`): a spacer is zero on both
  edges when unmarked or marked along the query axis; a same-axis stack takes
  its first child's leading and last child's trailing edge; a cross-axis stack
  or custom layout, ANY child; a `ZStack`, EVERY child; an empty container of
  any of the three, both; a leaf or scroll viewport, neither. 3.6 green.
  **1333 tests** (1331 + 3.6 + the forwarding test).
- **`6133316`**: the fixer's uncommitted `CN-H` amendment, committed unchanged
  by the second verifier, which also found and reverted an un-reverted mutation
  in `LayoutTree.swift` (same-axis stack → `(false, false)`).

**Second verifier (at `6133316`): `ok: false`**, quoted: `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` → `Test run with 1333 tests in 1 suite passed after 40.273
seconds`; 0 `error:`; the only `warning:` SwiftPM's deprecation notice; the
container guards printed their diagnostics; 97 goldens unchanged against
`9e439cb`. The probe re-run (`/usr/bin/swift`, exit 0) printed 779 lines,
byte-identical to revision 8's header, every V arm and control among them.

| mutation (second verifier) | red |
|---|---|
| A: an empty `ZStack` has no zero-spacing edge | `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges` |
| B: an empty cross-axis stack or custom layout has no zero-spacing edge | `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges` |

Its three issues:

1. **major — re-verification incomplete.** Told to return while its batch ran,
   it stopped after A and B. Not run: C–K below, and the twelve-image demo
   comparison for `8a4a491`.
2. **minor — this record had no lane 3 verifier-round section**, though
   `CN-H`'s amendment says "the mutations are in record §17". This section is
   the fix.
3. **minor — probe labels.** V7f's `run(...)` label reads
   `VStack{sp.padding(.leading, 4); HStack{sp}}` but the arm runs
   `VStack{ZStack{sp}.padding(.leading, 4); HStack{sp}}` (test 3.6's tree), so
   the recorded output line carries the wrong label; V7k's label is garbled
   (`swiftui-stack-algorithms.swift:2017`, `:2032`). **Still unfixed at
   `6d59cf0`**: re-labelling means re-recording the header, which is probe
   work this record pass did not take.

**The demo comparison for `8a4a491`** was never taken as its own run. It is
covered transitively: lane 4 compared `1ae17cc` with lane 3's `f916d1c` and
found, in the 1024 preview's scene, only the scroll view's 48 widths (856 →
520, `CN-M`); `8a4a491` lies between the two, so it moved no rect a scene dump
records. No preview gap sits beside a nested container holding a spacer.

### Lane 3 — the record pass's mutations

The second verifier's unrun mutations, run by the record pass on `6d59cf0`'s
tree (lane 3's code, with lanes 4 and 5 on top; `zeroSpacingEdges`,
`StackAlignment.swift` and the deprecated initializers are unchanged since
`8a4a491`). **This is the record writer's measurement, not an independent
verification; lane 3's verdict stays `ok: false`.** Script
`scratchpad/rec17/mut.py`: each mutation an exact string replacement asserted
unique, `swift build --build-system native --build-tests`, the unfiltered
`swift test --build-system native --no-parallel`, the file restored from its
in-memory original, `git status --short` printed after each (only this
record's own uncommitted edits), and a final unmutated rebuild.

| mutation | red (issues) |
|---|---|
| C a same-axis nested stack has no zero edge | **3.6** only (24) |
| D a cross-axis stack or custom layout combines with AND | **3.6** only (14) |
| E a spacer's edges ignore its orientation (always zero) | **3.6** (8), 3.2 `defaultSpacingBesideASpacerIsDecidedPerEdgeThroughItsWrappers` (2) |
| E2 an unmarked spacer has no zero edge | **3.6** (18), 3.2 (4) |
| F a same-axis stack's trailing edge read from its last child's LEADING edge | **nothing red** — the finding below |
| G padding's left/right insets swapped (M4b) | **3.2** only (2: V6/V6c) |
| H `VerticalAlignment(verticalFactorOf:)` maps 1 to `.center` (M12) | **the forwarding test** only (4) |
| H2 `HorizontalAlignment(horizontalFactorOf:)` maps 1 to `.center` | **the forwarding test** only (4) |
| I the deprecated `HStack` initializer forwards `spacing: nil` (M13) | **the forwarding test** only (11) |
| I2 the deprecated `VStack` initializer forwards `spacing: nil` | **the forwarding test** only (11) |
| J a custom layout treated as a leaf (no zero edge) | **3.6** only (12) |
| K a cross-axis stack treated as a same-axis one | **3.6** only (6) |

Every run printed `Test run with 1355 tests in 1 suite …`, so none truncated.

**F, a finding: the same-axis stack's trailing clause is unpinned and
unprobed.** 3.6's doc comment says this mutation reddens V1b and V1c; it
cannot, because in every probed same-axis arm the last child's leading and
trailing edges agree (V1b's last child is a leaf, V1c's a bare spacer). The
mutant was proven to differ before this was banked: a scratch test (deleted,
`git status --short` clean afterwards) measured `HStack{a 20; HStack{c 0;
Spacer(minLength: 0).padding(.leading, 4)}; b 20}` at nil×nil, **60 wide
unmutated and 68 under F** (the inner stack's trailing edge is the padded
spacer's trailing edge, zero, against its leading edge, 8). No probe arm
builds that tree (V1k is its mirror, a padded FIRST child, and pins the leading
clause), so SwiftUI's answer is unmeasured: the ruled rule is the symmetric
reading of V1b/V1c/V1k, not a measurement. Owner: the next probe revision
(arm: V1k mirrored), with an arm added to 3.6; 3.6's doc comment should stop
naming V1b/V1c for this mutation.

After the batch and the scratch instrument, the record pass rebuilt the
unmutated tree and ran the unfiltered suite: `Test run with 1355 tests in 1 suite passed after 41.117 seconds`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; 97 goldens, unchanged against `9e439cb`.

## Lane 4 — root, `ZStack` placement, overlay and background content, duplicate registration, scroll axes (`CN-J`, `CN-E`'s `ZStack` clause, `CN-K`, `CN-L`, `CN-M`, `MC-L`'s item)

2026-09-16. Commits: `400e844` (tests, red), `1ae17cc` (implementation and
the existing tests it moved), then this record with the as-built addenda.
Baseline: `6133316`, `Test run with 1333 tests in 1 suite passed` (native,
unfiltered).

### Red first

Fifteen spec tests, sixteen `@Test`s: 4.4 has a kernel half
(`aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`,
`NativeStackDistributionTests.swift`) and an element half
(`aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`,
`ContainerIntegrationTests.swift`), because the two halves live in different
test targets. 4.9 replaces the pin in `ProposalNodeIDTests.swift`, whose
private leaf types its arms reuse. The rest are in `ContainerIntegrationTests.swift`.
Removed: `aNativeNodeRegisteredTwiceIsNotRejected`,
`aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`.

**Against `6133316` the test targets do not compile**: `incorrect argument
label in call (have 'root:proposal:centredIn:', expected 'root:proposal:in:')`
(`ContainerIntegrationTests.swift:720`, `:724`), `trailing closure passed to
parameter of type 'ColorToken' that does not accept a closure` at every
`.background { … }` (`:712`, `:830`, `:837`, `:843`, `:902`, `:953`, `:994`,
`:1076`), and `type 'ColorToken' has no member 'bottomTrailing'` /
`cannot convert value of type 'ProposalAlignment' to expected argument type
'ColorToken'` at `.background(alignment:)` (`:778`, `:985`).

A **temporary, uncommitted shim** (`Sources/MetalUI/ZZShim.swift`:
`.background(alignment:content:)` returning an `OverlayModifier`, and
`computeNativeLayout(root:proposal:centredIn:)` forwarding to `in:` the full
container) let the targets build; each test was run **filtered on its own**
(several trap: shape 13), then the shim was deleted and `git status --short`
showed only the tests.

| # | test | first failure |
|---|---|---|
| 4.1 | `aNativeRootIsCentredAtItsAnswer` (6) | `:695` R1 `log.bounds["a"] == rect(21, 40, 58, 20)` (also R2, R3, R4 and both kernel arms) |
| 4.2 | `severalViewsInAnOverlayOrBackgroundAreACentredZStackPositionedByTheAlignment` | **process trapped**: `NativeOverlayModifier.swift:73: Precondition failed: a native overlay modifier requires one primary and one overlay node` |
| 4.3 | `overlayAndBackgroundContentIsPlacedAtThePrimarysSize` | trapped at the same line (its K5e arm) |
| 4.4 kernel | `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` (15) | `NativeStackDistributionTests.swift:1549` Z1 `arm.proposals("h") == [p(60, 40), p(30, 20)]`; `:1550` Z1 h `rect(3, 5, 15, 10)` |
| 4.4 element | `aZStackRootPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` (5) | `:869` Z1 proposals; `:870` Z1 h `rect(18, 15, 15, 10)` |
| 4.5 | `anEmptyOverlayOrBackgroundLeavesThePrimaryAlone` | trapped at `NativeOverlayModifier.swift:73` |
| 4.6 | `aClickOverABackgroundAndItsPrimaryReachesThePrimary` (1) | `:961` `#require(overlayCentre != backgroundCentre)` (the shim's background is an overlay) |
| 4.7 | `aBackgroundIsProposedThePrimarysSizeAlignedAndPaintedBeneath` (1) | `:995` `#require(overlay != background)` |
| 4.8 | `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` (1) | `:1079` `#require(log.bounds["p"] == rect(20, 20, 60, 60))` (the root filled the window) |
| 4.9 | `aNativeNodeRegisteredTwiceTraps` (4) | `ProposalNodeIDTests.swift:263` `expected exit status ".failure", but ".exitCode(EXIT_SUCCESS)"` (arm a; arm b at `:273`) |
| 4.10 | `everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads` (26) | `:1144` A3 big `rect(20, 30, 60, 40)` — red for the root's offset alone: the relative placements already agreed, as the spec said |
| 4.11 | `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis` (6) | `:1182` SC2 vertical c `rect(25, 0, 50, 30)` |
| 4.12 | `aProposalScrollViewPlacesSmallContentAtTheLeadingEdgeOfItsScrollingAxis` | green on arrival, its `#require` holding |
| 4.13 | `aProposalScrollViewAnswersItsProposalOnItsScrollingAxis` | green on arrival (the kernel agrees since lane 2) |
| 4.14 | `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis` (4) | `:1291` SC3 vertical a `rect(75, 0, 50, 30)` (and the horizontal arm, `:1297`) |
| 4.15 | `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` | trapped at `NativeOverlayModifier.swift:73` |

### What changed

`Sources/MetalUILayout/LayoutTree.swift`:
- `computeNativeLayout(root:proposal:centredIn:)` (public): one run, measure
  at the proposal, place at `((w − answer.w)/2, (h − answer.h)/2)` in the
  container at the answer (`CN-J`).
- `.overlay` placement (`CN-E`): B = the stored bounds' size; each child is
  measured at B and placed at its answer aligned within the union U of those
  answers, U at the bounds' origin, with B as its placement proposal.
- `.scrollViewport` measurement answers the content's size on the
  non-scrolling axis (`scrollViewportSize(axis:proposal:content:)`, `CN-M`).
- A stored `nativeParents: [Int: Int]` and `recordParent(_:of:)`, called after
  `appendNode` by all ten native registrars with children; it traps with
  `… registered under a second parent … (MC-G hole 4, ruling CN-L)`.
  `reset(generation:)` clears it. **A stored property on a public class read
  across a module boundary: the suite ran after `swift package clean`.**
- Doc comments: `newNativeOverlay`, `newNativeScrollViewport`.

`Sources/MetalUI/`:
- `Frame.computeRootLayout` calls the centred entry; its doc comment no longer
  says it "runs the flex engine" for both roots.
- `NativeOverlayModifier.swift`: the one-node precondition on the overlay side
  is gone; `OverlayModifier` lowers through
  `LayoutPass.requestSecondaryContentAttachment(primary:secondary:alignment:modifier:)`
  (internal, in `NativeBackgroundModifier.swift`): the primary must be exactly
  one node; zero secondary nodes return the primary's node; one is the
  attachment's content; several are one kernel `overlay` at `.center`, which
  the attachment positions with the modifier's alignment (`CN-K`).
- `NativeBackgroundModifier.swift` (new): `BackgroundModifier` and
  `.background(alignment:content:)`; the same lowering; content numbered from
  0 under `.child(of: id, at: -1)`; **prepaint and paint run the background
  before the primary**. `ProposalElementGroup.swift` gains
  `extension BackgroundModifier: ProposalElement {}`.
- `ProposalNodeID.swift`'s header: hole 4 closed at run time.
- Doc comments: `ZStack`, `ProposalScrollView`'s lowering (SC3, `CN-M`).

The demo (`main.swift`) needed no change.

### The nineteen existing tests

Measured red at `1ae17cc`'s implementation before the edits, then each re-read
and re-derived by hand. **The spec's stage-4 list** (13 besides the two
removed and the replaced pin) — all red, each for the reason named:

| test | moved by | now |
|---|---|---|
| `aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild` | the `ZStack` rule (bounds larger than the answer) | rebuilt at bounds = answer (40×50), second child 20×50 so both offsets are integral; each leaf asked (120, 80) then (40, 50), 2 calls each |
| `aNativeOverlayPlacesEveryChildAtTheRequestedAlignment` | the `ZStack` rule | bounds = the 50×40 answer; first at (33, 47) |
| `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition` | the `ZStack` rule (a lone child is its own union) | a 100×80 sibling makes the union; the nine expected rects are unchanged |
| `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` | the `ZStack` rule (B placed at 100×50 proposes its children 100×50) | re-derived by hand: 64 calls / 51 hits / 90 misses (lanes 2–3: 62 / 53 / 87; place B now 3 misses, 2 hits, 2 calls where it was 4 hits). The prototype's 46/48/66 is not comparable (`CN-B`'s lane 1 note) |
| `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout` | centring and the `ZStack` rule | proposals [140×90, 40×20], 2 calls, bounds (50, 35) 40×20 |
| `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` | centring (bounds only) | overlay at (20, 20), clicks at (25, 25); the identity claims unchanged |
| `aProposalLayoutContainerRendersThroughTheFramePipeline` | centring | the 82×41 padding root at (29, 24.5): (36, 36), (56, 46), (86, 61), rounded |
| `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` | centring | 49 and 45 (58×10 at x 21; 50×10 at x 25) |
| `vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt` | centring | 34 and 30 |
| `nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder` | centring (the padding root no longer fills the window, so the padding's stored-bounds-minus-insets divergence does not show) | (50, 45) |
| `spacerMinimumLengthSurvivesAConstrainedStackProposal` | centring (a 50pt root in a 20pt window at x −15) | (25, 15) |
| `fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal` | centring and the `ZStack` rule | proposals [(nil, 80), (nil, 10)], `NativeProposalProbe` gains an `expectedProposals:` initializer |
| `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI` | centring | **a finding**: centring alone would put an 80pt and a 40pt frame's leaf at the same x (90). A 200×10 sibling keeps the stack as wide as the window; the leaf reads x 30. Instrument check: with the frame's `maxWidth` removed (a 40pt, non-greedy frame) the test reads x 10 and is red (filtered, `:1047`) |

**Outside the stage-4 list** (six, all moved by centring; none moved by
anything else):
- `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified` and
  `…Height…`: lane 1 wrapped each stack in `.fixedSize`, so the root answers
  less than the window on the cross axis and centring now shows: (80, 15) and
  (15, 80). The prototype predates that wrapping.
- `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI` (SP1),
  `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (element
  half), `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer`: written
  in lanes 2–3 after the prototype, with `.fixedSize()` roots in a larger
  window. Expectations carry the centring offset, derived in each doc comment.
- `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing`: its three roots
  differ in height, so centring moved each marker differently; each root now
  sits in a 300×300 top-leading frame, keeping its arithmetic.

### Suite

After `swift package clean`, `swift build --build-system native
--build-tests` (0 `error:`, no `warning:` besides SwiftPM's deprecation
notice), unfiltered: **`Test run with 1346 tests in 1 suite passed`**, 0
`error:`. 1333 + 16 − 3 = 1346. The spec's 1339 was written before lane 3's
guards were counted as tests and before lane 3's verifier round (1333 at this
lane's start), and it counted 4.4 as one test. Default build system (`swift
build`, `swift test --no-parallel`): six summary lines, 65 + 738 + 55 + 28 +
438 + 22 = **1346**, all passed, 0 `error:`, 0 `warning:`. No test besides 4.9's arms
tripped `CN-L`'s trap. Goldens: 97, unchanged against `9e439cb`
(`git diff --quiet`). No guard added.

### Mutations

`1ae17cc`, each applied in this worktree, built `--build-system native
--build-tests`, the unfiltered suite run, `git checkout -q Sources`, `git
status --short` empty after each.

| mutation | red (named test in bold) |
|---|---|
| M1 place the root at the full container (`centredIn:` ignores the answer) | **4.1** (6), 4.4 element (6), 4.6, 4.8, 4.10 (28), 4.11 (4), 4.14 (4), and 24 existing root-placement tests — 108 issues, 31 tests |
| M2 the implicit `ZStack` takes the modifier's alignment | **4.2** only (2: K5g's h and K5h's h) |
| M3 the attachment places its content at the content's own answer | **4.3** only (5: K5d's two rects, the background K5d's two, K5f's proposal) |
| M4a a `ZStack` places at its parent's proposal | **4.4** kernel (15) and element (5), 4.2 (8), 4.3 (3), `aNativeOverlayForwardsOne…`, the branching-tree counts, `aNativeRootRunsThrough…`, `fixedSizeModifier…` |
| M4b centre in the bounds instead of the union | **4.4** kernel (4) and element (2), 4.2 (6), 4.3 (2) |
| M5 an empty slot registers an attachment over a zero-size leaf | **4.5** only (2: both node counts) |
| M6 prepaint the primary before the background | **4.6** only (1: H1 centre) |
| M7 paint the background after the primary | **4.7** only (1: background order) |
| M8 number the background under the primary's cursor | **4.8** only (3: first/second/third readings) |
| M9a delete `recordParent`'s precondition | **4.9** only (4: both arms' exit status and message) |
| M9b do not clear `nativeParents` in `reset` | **the unfiltered suite truncates**: `aResetTreeMeasuresItsNewRegistrationsFromScratch` traps in-process at the parent record, no summary line (shape 13). Filtered, **4.9**'s reset arm reads `expected exit status ".success", but ".signal(SIGTRAP)"` (`:283`). So an existing in-process test already pins the clear, and truncates the suite if it is lost |
| M10 swap `horizontalFactor`/`verticalFactor` in `.overlay` placement | **4.10** (6), `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition` (6) |
| M11 answer the proposal on the cross axis | **4.11** (6), 4.14 (4), 4.15 (1: narrow covers wide, so the first wheel's `#require` fails) |
| M12 centre the content in the viewport | **4.12** (1), 4.11 (4), 4.14 (4), four existing scroll-viewport tests |
| M13 answer the content at ∞ on the scrolling axis | **4.13** (2), `anInfiniteProposalIsAnsweredWithInfinity` (2) |
| M14 lower several children horizontally for `.horizontal` | **4.14** only (2: the horizontal a and b) |
| M15 key `ProposalScrollView`'s state and region on the parent id | **4.15** only (1: narrow moved with wide) |

### Demo comparison (`CN-S` row 4)

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>`: no real window
captures. Stand-in: the harness (`scratchpad/harness/gen.py`, twelve images
through a real `Window` over `FakePlatformWindow`) on `git archive 1ae17cc`.

| comparison | differing pixels |
|---|---|
| controls, head: light vs dark / default vs modal / default vs animation / f0 vs f3 / preview light vs dark | 1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576 |
| eight legacy images + `small560-default-light` vs `9e439cb` | **0**, scenes identical |
| `preview-light`, `preview-dark` vs `9e439cb` | **1 109** each, bbox (264, 212)–(939, 865) |
| `small560-preview-light` vs `9e439cb` | **65 449**, bbox (0, 0)–(559, 559) |
| `preview-*` vs lane 3 (`f916d1c`) | 921 each, bbox (596, 212)–(939, 307) |
| `small560-preview-light` vs lane 3 | 14 998, bbox (388, 191)–(543, 354) |

Exactly `CN-S` row 4. **The moved rect, traced:** against lane 3 the 1024
preview's scene differs only in 48 `MUISize(width: 856.0` → `520.0` fields —
the `ProposalScrollView`'s border, clip and mask rects — so its viewport now
answers its content's width (SC2, `CN-M`); no origin moved, so the preview's
greedy root did not move under `CN-J`. The 560 preview's scroll view narrows
the same way inside a compressed layout. `demoContent()` names no proposal
type, so the legacy zeros are not evidence for this lane (`CN-S`).

### Verifier round (`cdd3c74`)

The verifier (at `b1a4c42`) found four gaps, each a mutation that left the
unfiltered suite green. Fixed:

- **Two copies of the run bracket (major).** `computeNativeLayout(root:proposal:centredIn:)`
  was a line-for-line copy of the `in:` entry's bracket (`beginLayout`/`endLayout`,
  `activeNativeRun`, `run.isActive = false`, `lastNativeLayoutWork`), and the
  Frame path uses only the copy. Both entries now call one private
  `runNativeLayout(root:proposal:placement:)`, which differs per entry only in
  the bounds closure. No test changed. `measureNativeLayout` keeps its own
  bracket, as before (record §09's unpinned sub-clause).
- **CN-E's placement proposal (major).** A kernel leaf never sees the proposal
  it is placed at, so nothing pinned "B as the child's placement proposal".
  New `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal`
  (`NativeStackDistributionTests.swift`): the half-width child is a childless
  custom layout that records `placeSubviews`' proposal, [30×20] in Z1 and
  [60×40] in Z4. Those are the last placements in the probe's logs.
- **CN-L at eight unpinned registrars (minor).** New
  `aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent`
  (`NativeBoundaryTrapTests.swift`) has ten exit-test arms, one per registrar
  with children. Each registers a leaf under a frame, then under a registrar of
  that kind, and checks for "MC-G hole 4" on stderr. As a positive control,
  each registrar lays out over a fresh leaf in process.
- **R1's root placement proposal (minor).** `aNativeRootIsCentredAtItsAnswer`
  gains an arm with a `ProposalLayoutContainer` root that answers 58×20 in a
  100×100 window and records `placeSubviews`' proposal, [100×100].

These new tests went green on arrival because they pin behaviour that already
existed. Each was shown to catch its mutation instead. The worktree was
committed at `cdd3c74` and `LayoutTree.swift` was restored from a copy after
each mutation. Each mutant was built with `--build-system native --build-tests`
and the unfiltered suite was run; `git status --short` was empty after every
one.

| mutation | red |
|---|---|
| V3 `.overlay` places each child at the parent's proposal, not B | **`aZStackPlacesEachChildWithItsOwnSizeAsTheProposal`** only (2) |
| V2 place the root at proposal = its answer (now in the shared run, so both entries) | **`aNativeRootIsCentredAtItsAnswer`** (1: the new R1 arm) and 20 other kernel tests placed at bounds smaller than their proposal — 52 issues |
| V8 drop `lastNativeLayoutWork = run.work` | `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`, `nativeLayoutWorkIsPerCall`, `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` (6) |
| V9 drop `run.isActive = false` | `aSubviewUsedAfterItsLayoutRunTraps` (2) |
| V10 drop `beginLayout()`/`defer { endLayout() }` | `computeLayoutCalledFromANativeMeasureClosureTraps`, `computeNativeLayoutReenteredFromAMeasureClosureTraps`, `nativeLayoutHoldsTheLayingOutFlagOnlyWhileItRuns`, `registeringALegacyLeafDuringNativeLayoutTraps`, `registeringANativeNodeDuringNativeLayoutTraps`, `resettingATreeDuringLayoutTraps`, `setStyleOnALegacyNodeDuringNativeLayoutTraps` (10) |
| V7 delete `recordParent` from the eight registrars other than stack and frame | **`aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent`** only (16: eight arms, each with exit status and message) |

Since the entries share one run, V8–V10 now redden the `in:` entry's existing
bracket tests, and those tests also cover the Frame path. Suite: `swift build
--build-system native --build-tests`, then the unfiltered run gives
**`Test run with 1348 tests in 1 suite passed`** (1346 + 2), with 0 `error:`
and no `warning:` apart from SwiftPM's deprecation notice. Goldens: 97,
unchanged against `9e439cb`. No guard was added. The change touches no
stored property and no paint path; the eight legacy demo images are
unaffected by construction (`computeNativeLayout` does not run for a legacy
root).

### Not done here, and why

- `CLAUDE.md`, `AGENTS.md`, the plan and the record index: the Docs phase.
  Candidates: the SwiftUI-alignment section's root paragraph ("stored at the
  full window … a root stack packs from the leading edge", with
  `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`'s x = 28,
  now 49); the "Single-child proposal wrappers" sentence (both `.overlay` slots
  no longer precondition one node — only the primary does); `MC-G`'s holes
  ("one id used twice does not trap" now traps; "A precondition closing the
  orphan or duplicate hole truncates the suite" is half-done); the vocabulary
  gains `.background(alignment:content:)`; `ProposalScrollView` answers its
  content on the cross axis; the `Deferred`/overlay divergence for H3 (a
  non-clickable proposal primary does not block its background's click); the
  kernel-caller `ZStack` placement note (`CN-E`); padding's
  bounds-minus-insets pin (`SA-N`, task 5) no longer shows at a centred root.
- Two-axis scrolling (SCG2 `.both` centring): task 10 (`CN-M`).
- H3 is a recorded difference, not adopted (`CN-K`).

## Lane 5 — the legacy path: single-child frame, `fraction:`, three divergence pins (`CN-N`, `CN-O`, `CN-P`)

2026-09-16. Commits: `1f56652` (tests and guard, red), `c73706f`
(implementation and the moved tests), `f21d626` (5.1's inner-layer arms after
mutation M12, and each test's measured mutation lines), then this record with
the as-built addenda to `CN-N`, `CN-O`, `CN-P` and the spec's count note.

### Probes, re-run first

`/usr/bin/swift docs/probes/swiftui-frame-semantics.swift` and
`…/swiftui-stack-algorithms.swift`, macOS 27.0 (26A428), both exit 0. The arms
this lane cites read as recorded in the headers: `A5` `child at (-70.0, -60.0)
size 200.0x160.0`, `B9` `child at (0.0, 0.0) size 200.0x160.0`; `S rect|rect:
hstack 8  vstack 8` with its control `hstack(0) 0 hstack(20) 20 vstack(20) 20`;
`A5` `leaf a: proposed [100x80] at (0, 0) 100x80`; `SC2` vertical `size 50x100`.
The frame-semantics run printed fewer duplicate `child proposed` lines in its G
group than its macOS 26 header, the call-count difference the decisions doc's
preamble already records; no placement differed.

### Today's answers, before any source change

`CN-N` left an absolutely positioned child and a `ScrollView` inside a
one-child legacy frame open. At `8e1dfa7`, exploratory scratch tests (never
committed) printed the arms that became 5.6 and 5.7; the values are in those
tests' doc comments. They were taken before `ModifiedElement.swift` changed and
read identically after it (the suite below), so the open item closes with no
difference.

### Red first

Eight `@Test`s: 5.1, 5.2, 5.6, 5.7 in `Tests/MetalUITests/FrameSizingTests.swift`
(5.1 replaces `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`, 5.2
replaces `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`),
5.3–5.5 in `ContainerIntegrationTests.swift`, G4 in `ContainerCompileGuards.swift`.

**Against `8e1dfa7` the test target does not compile**: `extraneous argument
label 'fraction:' in call` at `FrameSizingTests.swift:682`, `:685`, `:690`,
`:693`, `:696`, `:699` (every `fraction:` call in 5.2).

A **temporary, uncommitted shim** (`Sources/MetalUI/ZZShim.swift`: the three
`fraction:` methods forwarding to `percent:`) let the targets build; the eight
tests ran filtered (`Test run with 8 tests in 0 suites failed … with 8 issues`),
then the shim was deleted and `git status --short` showed only the tests.

| # | test | first failure |
|---|---|---|
| 5.1 | `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes` (4) | `:514` `single == Rect(-70, 20, 200, 160)` — reads (0, 20) 60×160 (`FR-N`); also the pinned and top-leading arms, and the two-node control's expected width (written 60, measured 57, corrected before the commit: CSS shrinks by base size) |
| 5.2 | `aFractionSizeResolvesAgainstItsContainingBlock` | does not compile (above); green under the shim, as a rename must be |
| 5.3 | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` | green on arrival, its `#require` holding (a pin) |
| 5.4 | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | green on arrival (a pin) |
| 5.5 | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` | green on arrival (a pin) |
| 5.6 | `anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement` | green on arrival by construction |
| 5.7 | `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` | green on arrival by construction |
| G4 | `thePercentSizingModifiersAreDeprecatedRenamesOfFraction` (4) | `ContainerCompileGuards.swift:142` `deprecations(result) == 3` (0), and `:144` for each of the three names |

### What changed

`Sources/MetalUI/ModifiedElement.swift`: `ModifierLayer.isFrame` (internal
stored property, default `false`) and `lowered(_:childCount:)`, which returns
the style with `display = .stack` for a frame layer over exactly one node.
`requestLayout` applies it to each inner layer and to the outermost, before
`animated`. The fixed `frame(width:height:alignment:)` passes `isFrame: true`.
`Sources/MetalUI/FrameLayer.swift`: the flexible overload passes `isFrame:
true`; `FrameSpec.style()`'s nine-case `switch` also writes `justifyItems`
(`.start`/`.center`/`.end`); the lowering table gains the one-node row; the
overload's doc no longer lists the squeeze as a live divergence.
`Sources/MetalUI/Box.swift`: `width(fraction:)`, `height(fraction:)`,
`flexBasis(fraction:)`; the three `percent:` methods are
`@available(*, deprecated, renamed: …)` and forward. Doc comments:
`Units.swift`'s `Length.percent`, `NativeModifiedContent.swift`'s fixed
`frame`.

`ModifierLayer` is a public struct whose stored properties changed, so the
suite ran after `swift package clean`.

**Existing tests that changed** (the spec's list, and no other):
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` (child now at
A5's (−70, −60) 200×160; its clip and border claims unchanged);
`everyPublicModifierWritesItsOwnFieldAndOnlyThatField`'s three rows renamed
`…(fraction:)`; the two replaced tests. The hand-spelled `frameStyle`
oracles in `ModifiedElementTests.swift` and
`ModifierCompositionProofTests.swift` gained `justifyItems = .center` and
`display = .stack`, per their drift obligation (they were green either way).
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes` and
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` stayed green,
as the spec measured.

### Suite

After `swift package clean`, `swift build --build-system native --build-tests`
(no `error:`, no `warning:` besides SwiftPM's deprecation notice), unfiltered at
`c73706f`: **`Test run with 1354 tests in 1 suite passed`**, 0 `error:`.
Default build system (`swift build`, `swift test --no-parallel`): six summary
lines, 65 + 744 + 55 + 28 + 440 + 22 = **1354**, all passed, 0 `error:`, 0
`warning:`. Again at `f21d626`, native: 1354 passed, 0 `error:`. 1348 + 8 − 2 =
1354; the spec's 1344 predates lane 4's count (1346, then 1348 after its
verifier round) and did not count G4 as a test. Guards (`grep -c
canTypecheck`, `Typecheck.swift` excluded, one `UnitSafetyTests` hit a comment):
**70**. G4 printed its three diagnostics, so it ran. Goldens: 97, unchanged
against `9e439cb` (`git diff --quiet`).

### Mutations

Each was applied in this worktree at `c73706f` (M12 again at `f21d626`),
built with `--build-system native --build-tests`, and run through the
unfiltered suite. Afterwards `git checkout -q Sources Tests` restored the tree,
and `git status --short` was empty every time. The script is
`scratchpad/lane5/mutate.py`.

| mutation | red (issues) |
|---|---|
| M1 a single-child frame lowers as a flex row again | **5.1** (3), `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` (1) |
| M2 every frame layer lowers as a stack | **5.1** (1: the two-node control's `#require`), `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` (1), `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` (2), `chainedFramesRemainConcreteAndNestTheirLayoutNodes` (2) |
| M3 `fraction:` writes `.percent(fraction * 100)` | **5.2** (1), `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` (3) |
| M4 the legacy `Stack` container stretches (`alignItems`/`justifyItems` `.stretch` in `Stack.init`) | **5.4** (1) and the design's seven: `allNineAlignmentsMapToTheirPairAndTheNineAreDistinct` (19), `aNestedHandlerWinsOverItsContainingStackToo` (2), `aPressReleasedOverSomethingCoveringItIsNotAClick`, `clippedAlsoClipsTheHitboxesInsideIt`, `stackDefaultsToCentreNotStretch` (2), `stackWritesDisplayAndBothAlignmentFields` (2), `theTopmostOfTwoOverlappingHandlersRuns` (2) — 8 tests, 30 issues |
| M5 `Row`/`Column` default gap 8 | **5.3** (1), and 24 others — 25 tests, 59 issues: the design's 22 minus the replaced percentage test, plus 5.2 (3), 5.6 (7), 5.7 (4), which build legacy rows |
| M6 the proposal scroll viewport answers its proposal on the cross axis (lane 4's line reverted) | **5.5** (1), `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis` (6), `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis` (4), `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` (1) |
| M7 remove `height(percent:)`'s `@available` | **G4** only (2) |
| M8 the lowered frame layer is made `.static` | **5.6** only (1: its `#require`, A reading B's (15, 10)) |
| M9 the lowered stack stretches its one child | **5.7** (1: its `#require`, A's viewport stretched to 100 and scrolling 37), 5.1 (2), and 16 other frame tests — 18 tests, 42 issues |
| M10 `FrameSpec.style()` writes no `justifyItems` (a stack then stretches) | **5.7** (3), 5.1 (2), `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` (6), and 13 others — 16 tests, 43 issues |
| M11 lower the outermost layer **after** `animated` | **none** — an equivalent mutant (see below) |
| M12 inner layers not lowered | **none** at `c73706f` — the finding; at `f21d626` **5.1** only (2: the padded and doubly framed arms) |

**M11, proved equivalent rather than banked.** `animated` never assigns
`display`. The snapping fields pass through from the style it is given, and
the `$anim` baseline's snapping fields are never read back
(`AnimatedStyle.swift`, "wasted work, not a wrong value"). So the registered
style is the same in either order. The only difference is one
`StateTable.writeCount` write when a frame's node count changes. `CN-N`'s
addendum records the clause as a convention, not a pinned behaviour.

**M12, the finding.** The ruling lowers "per layer", but every 5.1 arm had the
frame as the outermost layer. A frame under a `.padding(4)` and a frame under
a second frame were added to 5.1: the child reads (−66, 20) and (−60, 20),
where the row lowering squeezes it.

### Demo comparison (`CN-S` row 5)

`ioreg -n Root -d1 -a` read `IOConsoleLocked` `<true/>`, so no real windows were
captured. As a stand-in, the harness (`scratchpad/harness/gen.py`) rendered
twelve images through a real `Window` over `FakePlatformWindow`, in fresh
`git archive` trees of `9e439cb` and `c73706f`. It was built with the default
build system.

| comparison | differing pixels |
|---|---|
| controls, base and head alike: light vs dark / default vs modal / default vs animation / f0 vs f3 / preview light vs dark | 1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576 |
| eight legacy images + `small560-default-light` vs `9e439cb` | **0**, scenes identical |
| `preview-light`, `preview-dark` vs `9e439cb` | **1 109** each, bbox (264, 212)–(939, 865) |
| `small560-preview-light` vs `9e439cb` | **65 449**, bbox (0, 0)–(559, 559) |
| all twelve vs lane 4's images (`1ae17cc`) | **0**, scenes identical |

The table is exactly `CN-S` row 5. The two `.frame` calls in `main.swift`
(`:1003`, `:1032`) are on proposal elements, and the demo has no `percent:`,
so no image reaches this lane's code. As `CN-S` says, these zeros show only
that nothing else moved; they are not evidence for the lane.

### Not done here, and why

- `CLAUDE.md`, `AGENTS.md`, the plan and the record index are left for the Docs
  phase. Candidates:
  - the "Containers" paragraph's `.frame(width:height:)` sentences, which
    say the frame "does not stretch or impose" and that a long child is
    "bounded by the frame's width (flex-shrink …)". Over exactly one node the
    child now keeps its size and overflows, and over several it still shrinks;
  - divergence 36 (`FR-N`) retired;
  - the inert table and vocabulary gain `fraction:`, and `percent:` is
    deprecated;
  - the deprecation count (`@available(*, deprecated` hits) rises by three;
  - the three `CN-P` divergences, owner task 7;
  - (fix round) an inert-table row, "`.flexGrow`/`.alignSelf` on the only
    child of a legacy `.frame`": a stack reads neither, so both compile and do
    nothing, the fill idiom `.flexGrow(1).frame(maxWidth: .infinity,
    maxHeight: .infinity)` included; workaround `width(fraction: 1)` /
    `height(fraction: 1)`; pinned by
    `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`. The
    "Containers" paragraph's `.frame` sentences should say the same.
- `CN-Q`'s legacy frame items (greedy finite maximum, single-axis infinite
  maximum, nil-axis frame under a stretching `Box`), legacy `.overlay`, and
  lowering the legacy containers go to **task 7**, unchanged. None was
  attempted.
- A frame over a multi-member `Component` still lays its members out as a
  row. SwiftUI frames each member (`G7`), and neither lowering gives that
  answer (`CN-N`).

### Verifier round (fix round)

The verifier (at `017c813`) returned two majors and a minor, each a mutation
that left the unfiltered suite green. All three are tests only; no source
changed. Commit `5add712` (tests), then this record.

**Probe re-run.** `/usr/bin/swift docs/probes/swiftui-frame-semantics.swift`
(exit 0) printed, as its header records, `D13 frame(minWidth: 40, maxWidth: 80)
with a 200x160 child, proposal 100x100: size 80.0x160.0` / `child at (-60.0,
0.0) size 200.0x160.0` and `D14 frame(maxWidth: 80) with a 200x160 child,
proposal nil: size 80.0x160.0` / `child at (-60.0, 0.0) size 200.0x160.0`; the
positive control `D` (a 20×20 child) at `(30.0, 0.0)`.

1. **The flexible overload's lowering was unpinned (V1).** 5.1 gained
   `.frame(minWidth: 40, maxWidth: 80)` and `.frame(maxWidth: 80)` arms around
   the 200×160 mark in a `Row`: the frame at (0, 20), the child at (−60, 20)
   200×160, `D13`/`D14` translated.
2. **A single-child frame's child loses `.flexGrow`/`.alignSelf`, unpinned.**
   New test 5.8, `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`
   (pinned as it stands, no SwiftUI claim): in a 300×200 `Frame`,
   `Row { mark(h 20).flexGrow(1).frame(width: 100, height: 40) }` reads
   (50, 90) 0×20; the root fill idiom (150, 90) 0×20;
   `mark(w 20).alignSelf(.stretch).frame(width: 100, height: 40)` in a `Row`
   (40, 100) 20×0. Controls, `#require`d to disagree: the same marks beside a
   10×10 mark in one framed component (two nodes, the row) grow to 90 and
   stretch to 40. Workaround arms: `width(fraction: 1)` reads (0, 90) 100×20
   and, at the root, (0, 90) 300×20. The verifier's before/after values used
   another container height; the ratios agree.
3. **`percent:`'s forwarding was unpinned (V8).** 5.2 gained arm F: the three
   deprecated spellings at 0.5 must equal their `fraction:` answers. They are
   called through a `@MainActor` protocol whose `Mark` witnesses are
   `@available(*, deprecated)` and a generic caller, which the compiler does
   not diagnose (checked first on a scratch file with `xcrun swiftc
   -swift-version 6`: no warning), so the 0-warning gate holds.

**Red.** The three additions describe the lane's built behaviour, so they were
green on arrival; their proof is the mutations. Each ran against `5add712` in
this worktree, built with `--build-system native --build-tests`, filtered to
`FrameSizingTests`, the file restored from a copy and `git status --short`
checked afterwards (the verifier's unfiltered runs had already shown V1 and V8
redden nothing else):

| mutation | red (issues) |
|---|---|
| V1 flexible overload `isFrame: false` (`FrameLayer.swift:179`) | **5.1** (2: the `D13`, `D14` arms), **5.8** (1: the fill pin; its workaround stays green, a row fills a `width(fraction: 1)` child too) |
| V2 fixed overload `isFrame: false` (`ModifiedElement.swift:339`) | **5.1** (5), **5.8** (1: the stretch control's `#require`, since the restored row stretches both, stopping the test) |
| V8 `width(percent:)` forwards `fraction: percent * 100` | **5.2** (1: arm F's width) |

**Suite.** Unfiltered at `5add712` plus the doc-comment edit: native
`Test run with 1355 tests in 1 suite passed`, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice; default build system six lines summing to
**1355**, 0 `error:`, 0 `warning:` in build and test output. 1354 + 1 (5.8).
Goldens: 97, `git diff 9e439cb..HEAD` over them empty. No source changed, so
the demo images are the verifier's.

## What landed, in one place

Written by the record pass at `6d59cf0` (2026-09-16). Every figure in this and
the following sections is quoted from a lane or verifier section above, or
re-taken by the record pass where it says so.

Forty commits on `feat/containers` from `9e439cb`, in order. `Sources/` moved
in eight of them (`31fd2ba`, `63387f6`, `103bce0`, `f916d1c`, `8a4a491`,
`1ae17cc`, `cdd3c74`, `c73706f`):

| commit | phase | what |
|---|---|---|
| `75b5f69`, `fbfc1d6`, `b75bc50` | design | stack-algorithms probe revisions 1–3 (stacks, spacers, alignment, overlay, scroll views; aspect ratio over a fixed child; an empty overlay or background) |
| `589cc87` | design | spec and decisions doc (`CN-A`…`CN-S`) |
| `cef0acd`, `a163bb9`, `f10e779` | critic round | probe revision 4 (spacing and marking walks, aspect ratio at ∞, `ZStack` placement, `List`, K5g/K5h); the overlay/presentation probe and its reading |
| `f25cbed` | critic round | the staged prototype, amended `CN-C/E/G/H/I/K/L/N/P/Q`, new `CN-T`/`CN-U`, five re-cut lanes |
| `f657598`, `31fd2ba`, `65822a8` | lane 1 | red; `solveLinearStack`, single-child pass-through, second pass, spacer −∞/∞; record |
| `32f57fb`, `476a894`, `63387f6`, `5980ed5` | lane 2 | probe revision 5 (G4r/G4f); red; spacer default 8 and cross-axis mark, infinite answers, `aspectRatio` answers its child; record |
| `103bce0`, `4830b22` | lane 2 verifier round | probe revision 6 (K2f–K2j); `fixedSize` marking, `reset` clearing marks and checkpoint 3's width term pinned; record |
| `6adf624`, `f916d1c`, `91ea9af`, `ef431b0`, `05bf236` | lane 3 | red and guards G1–G3; per-edge default spacing and typed stack alignments; probe revision 7 (SC5); the SC5 arm; record |
| `632b327`, `dcd509d`, `8a4a491`, `6133316` | lane 3 verifier round | probe revision 8 (V1–V8); test 3.6, V6/V6c, the deprecated-forwarding test; `CN-H` amended walk; the interrupted fixer's `CN-H` text committed unchanged |
| `400e844`, `1ae17cc`, `b1a4c42` | lane 4 | red; centred root, `ZStack` placement, overlay/background content, `.background(alignment:content:)`, duplicate-parent trap, scroll viewport cross axis; record |
| `cdd3c74`, `8e1dfa7` | lane 4 verifier round | one shared `runNativeLayout`; pins for the `ZStack` and root placement proposals and `CN-L` at all ten registrars; record |
| `1f56652`, `c73706f`, `f21d626`, `017c813` | lane 5 | red and guard G4; single-child legacy frame as a one-cell stack, `fraction:` with deprecated `percent:`; inner-layer arms; record |
| `5add712`, `6d59cf0` | lane 5 fix round | D13/D14 arms, test 5.8, arm F; record |
| this commit | record | lane 1's and lane 3's verifier rounds, the record pass's lane 3 mutations, these summary sections, the spec's Status |

**Source files, `git diff --stat 9e439cb 6d59cf0 -- Sources`:**

| file | lines | what changed |
|---|---|---|
| `Sources/MetalUILayout/LayoutTree.swift` | 634 | `solveLinearStack`, `stackGaps`, `zeroSpacingEdges`, `markSpacers` and `spacerAxes`, `nativeParents` and `recordParent`, the `.overlay` placement, `aspectRatioProposal`, `scrollViewportSize`, `computeNativeLayout(root:proposal:centredIn:)` and the shared `runNativeLayout`, `nativeLayoutPriority`, `spacerLength`, `framedSize`'s greedy gate; doc comments |
| `Sources/MetalUILayout/ProposalSpacing.swift` | +12, new | `public enum ProposalSpacing { static let platformDefault: Double = 8 }` |
| `Sources/MetalUILayout/ProposalLayout.swift` | 24 | doc comments: `priority`, `isSpacer` |
| `Sources/MetalUI/NativeBackgroundModifier.swift` | +100, new | `BackgroundModifier`, `.background(alignment:content:)`, the shared secondary-content lowering |
| `Sources/MetalUI/StackAlignment.swift` | +61, new | `VerticalAlignment`, `HorizontalAlignment` |
| `Sources/MetalUI/NativeElements.swift` | 76 | `HStack`/`VStack` `init(alignment:spacing:content:)`, the deprecated spacing-first initializers, `Spacer`'s docs |
| `Sources/MetalUI/NativeOverlayModifier.swift` | 16 | the overlay side's one-node precondition removed |
| `Sources/MetalUI/ProposalScrollView.swift` | 15 | several children lower with `spacing: nil`; docs |
| `Sources/MetalUI/Frame.swift`, `Passes.swift` | 16, 6 | `computeRootLayout` calls the centred entry; `requestNativeLinearStack` takes `Double?` |
| `Sources/MetalUI/ProposalElementGroup.swift`, `ProposalNodeID.swift` | 1, 8 | `BackgroundModifier: ProposalElement`; hole 4 closed at run time |
| `Sources/MetalUI/ModifiedElement.swift`, `FrameLayer.swift` | 38, 39 | `ModifierLayer.isFrame`, `lowered(_:childCount:)`; `justifyItems` in `FrameSpec.style()`; both overloads set `isFrame` |
| `Sources/MetalUI/Box.swift`, `Sources/MetalUICore/Units.swift` | 73, 12 | `width/height/flexBasis(fraction:)`; `percent:` deprecated, forwarding; docs |
| `Sources/MetalUI/NativeModifiedContent.swift` | 17 | doc comments (`.aspectRatio`, the fixed `frame`) |
| `Sources/MetalUIDemo/main.swift` | 4 | the two `VStack(spacing:alignment:)` calls moved to SwiftUI's argument order |

**Stored properties changed on public types** (each lane ran `swift package
clean` before its suite): `LayoutTree.spacerAxes` (lane 2),
`LayoutTree.nativeParents` (lane 4), `HStack`/`VStack`'s `spacing`/`alignment`
types (lane 3), `ModifierLayer.isFrame` (lane 5). **The integrator cleans after
the merge.**

**Counts at `6d59cf0`** (lane 5's verifier, native, after `swift build
--build-system native --build-tests`): `Test run with 1355 tests in 1 suite
passed`; 0 `error:`; the only `warning:` SwiftPM's deprecation notice; only
the two gated tests skipped. Goldens **97**, `git diff 9e439cb..HEAD` over them
empty at every lane. Guards **70** (`git grep -c canTypecheck` per file, less
`Typecheck.swift` and the `UnitSafetyTests` comment). `@available(*,
deprecated` hits in `Sources/` **34** (29 at `9e439cb`). The record pass
re-took the suite at `6d59cf0` after its own mutation batch: see "Lane 3 —
the record pass's mutations".

## Tests and guards, per file

**1303 → 1355, +52** (lane 1 +13; lane 2 +7 − 1, verifier +1; lane 3 +8,
verifier +2; lane 4 +16 − 3, verifier +2; lane 5 +8 − 2, fix round +1). `@Test`
lines per file, `9e439cb` → `6d59cf0`:

| file | tests | what |
|---|---|---|
| `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift` (new) | 0 → 20 | 1.1–1.10, 1.12; 2.1, 2.2, 2.3, 2.5, 2.6; 3.2, 3.6; 4.4 kernel; `aZStackPlacesEachChildWithItsOwnSizeAsTheProposal` |
| `Tests/MetalUITests/ContainerIntegrationTests.swift` (new) | 0 → 25 | 1.11, 1.13; 2.7; 3.1, 3.3, 3.4, 3.5, `theDeprecatedSpacingFirstStackInitializersForwardSpacingAndTheCrossFactor`; 4.1–4.3, 4.4 element, 4.5–4.8, 4.10–4.15; 5.3, 5.4, 5.5 |
| `Tests/MetalUITests/ContainerCompileGuards.swift` (new) | 0 → 4 | **four guards**, all `typecheckFile` (whole file, Swift 6): G1 `aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks`, G2 `theTypedStackInitializersCompileInSwiftUIsArgumentOrder`, G3 `theSpacingFirstStackInitializersAreDeprecated`, G4 `thePercentSizingModifiersAreDeprecatedRenamesOfFraction`. Each printed its diagnostics in a native run; each was mutated red (lane 3 G1–G3, lane 5 M7) |
| `Tests/MetalUITests/FrameSizingTests.swift` | 12 → 15 | 5.1 replaces `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`; 5.2 replaces `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`; 5.6, 5.7, 5.8 new |
| `Tests/MetalUILayoutTests/NativeValidationTrapTests.swift` | 35 → 37 | 2.4 `aCustomLayoutPlacingAChildAtAnInfiniteProposalTraps`, `anInfinitelyWideRootBoundsTraps` (exit tests) |
| `Tests/MetalUILayoutTests/NativeBoundaryTrapTests.swift` | 14 → 15 | `aNativeRegistrarWithChildrenRejectsANodeThatAlreadyHasAParent` (ten exit arms) |
| `Tests/MetalUILayoutTests/NativeLayoutTests.swift` | 25 → 24 | `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` deleted (replaced by 2.3); fit/fill and negative-ratio fixtures changed |
| `Tests/MetalUITests/NativeLayoutIntegrationTests.swift` | 42 → 40 | the two `ProposalScrollView` spacing tests removed (replaced by 4.14); root-placement expectations moved |
| `Tests/MetalUITests/ProposalNodeIDTests.swift` | 3 → 3 | the registered-twice pin replaced by the exit test 4.9 `aNativeNodeRegisteredTwiceTraps` |
| `Tests/MetalUILayoutTests/ReferenceLinearStack.swift` | helper | rewritten to `CN-B` through public proxies; `OrderBlindLinearStack` control; vertical comparison |
| `NativeInvalidationContractTests`, `NativeLayoutWorkTests`, `NativeValidationAcceptanceTests`, `ProposalLayoutTests`, `FrameDecorationInteractionTests`, `ModifiedElementTests`, `ModifierCompositionProofTests`, `ModifierTests`, `ProposalLayoutIntegrationTests` | unchanged counts | literals re-derived by hand (branching tree 16/27/25 → **64 / 51 / 90**), fixtures moved by centring, `frameStyle` oracles gained `justifyItems`/`display: .stack`, three `ModifierCase` rows renamed `…(fraction:)` |

Guards **66 → 70**, per file: `PhaseSeparationTests` 19,
`ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
`ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
`ElementGroupTrapTests` 5, **`ContainerCompileGuards` 4**, `AXNodeTests` 3,
`DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits, one a comment),
`ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2.
`typecheckFile` guards 26 → **30**.

## Probes

| probe | arms | what it settled | positive controls |
|---|---|---|---|
| `docs/probes/swiftui-stack-algorithms.swift`, revision 8 | 220 `run`/`runMeasured` arms in groups S, SP/SPB, G/X, Q, A, SC/SCG/SCG2, R, AR, K, Z, V; 779 output lines | `CN-B` distribution, `CN-C` spacer, `CN-D` pass-through, `CN-E` second pass and `ZStack` placement, `CN-F` infinite answers, `CN-G` aspect ratio, `CN-H` spacing walk, `CN-I` alignments, `CN-J` root, `CN-K` overlay content, `CN-M` scroll axes; `List` greedy (K6) | every group has a control whose answer differs (K3 48, SP3 40, K2f/K2j for the `fixedSize` mark, SC5c for SC5, G4 for G4r/G4f, V1j/V3c/V3g/V4c 56 for V). `/usr/bin/swift`, Apple Swift 6.4, macOS 27.0 (26A428); each revision run twice byte-identical and additive over the previous revision's output. Re-run by lane 1's verifier (608 lines, revision 4), lane 2's (627, revision 6), lane 3's (779, revision 8), each identical to the header |
| `docs/probes/swiftui-overlay-presentation.swift` | P0–P6, H0–H3 | an `.overlay` is clipped by an ancestor clip and not hoisted (P1, P2; `.zIndex` within a `ZStack`, P3); a presented sheet/popover is outside the layout and render tree (P4, P5), so `Deferred` has no layout counterpart (`CN-Q`); a click over a view and its `.background` reaches the view (H1), an overlay takes both (H2), a non-clickable view still blocks its background's gesture (H3) | P0 renderer readback, P1c/P2c, H0; H1/H2 click two points that must disagree. **Compiled form only** (`xcrun swiftc`; the script form fails to JIT) |
| cited, re-run by lane 5: `docs/probes/swiftui-frame-semantics.swift` | A5, B9, D13, D14 | a child larger than its frame overflows both axes (`CN-N`) | its `D` control at (30, 0) |

**Probe defects left open:** the V7f and V7k labels (lane 3's verifier, minor).
`swiftui-stack-algorithms.swift:2017` labels V7f `VStack{sp.padding(.leading,
4); HStack{sp}}` but runs `VStack{ZStack{sp}.padding(.leading, 4); HStack{sp}}`
(test 3.6's tree), and `:2032`'s V7k label is garbled; the recorded output
lines carry the wrong labels. Unfixed at `6d59cf0` (`grep -n V7f`). No ruling
number depends on the label; `CN-H`'s addendum cites V7f in a list only.

## Red runs, in one place

| lane | red | green |
|---|---|---|
| 1 | 13 new tests on `9e439cb`'s kernel, filtered: `13 tests … failed … with 81 issues`; re-taken by the verifier on a `git archive` tree, identical | `31fd2ba`: 1316 passed |
| 2 | 7 new tests against `32f57fb`, filtered: `7 tests … failed … with 75 issues` (2.3's G4, 2.6's K4f and 2.7's G4 arms green inside red tests) | `63387f6`: 1322; verifier round `103bce0`: 1323 (its three additions pin existing behaviour, proved by M3d, M11, M10) |
| 3 | the targets do not compile against `4830b22` (`spacing: nil`, the typed alignments, argument order); under a temporary shim, `7 tests … failed … with 40 issues`, 3.3 and 3.5 green on arrival as pins | `f916d1c`: 1331 |
| 3 verifier round | 3.6 red with **46 issues** at `dcd509d` (decisions doc `CN-H`); V6/V6c and the deprecated-forwarding test describe existing behaviour | `8a4a491`: **1333**, re-verified at `6133316` |
| 4 | the targets do not compile against `6133316` (`centredIn:`, `.background { … }`); under a shim, each test filtered: four trapped at `NativeOverlayModifier.swift:73`, 4.9 exited successfully where failure was expected, 4.12 and 4.13 green on arrival | `1ae17cc`: 1346; verifier round `cdd3c74`: 1348 (its two tests green on arrival, proved by V3 and V7) |
| 5 | the target does not compile against `8e1dfa7` (`fraction:`); under a shim, `8 tests … failed … with 8 issues`, five green on arrival as pins or by construction | `c73706f`: 1354; fix round `5add712`: 1355 (additions green on arrival, proved by V1, V2, V8) |

## Verifier verdicts, in one place

| lane | verdict | suite the verifier read | fix round |
|---|---|---|---|
| 1 | **`ok: true`**, three minor | 1316 at `65822a8` | none; issues dispositioned in "Verifier round (lane 1)" |
| 2 | **`ok: true`**, no issues (after its fix round) | 1323 at `4830b22` | `103bce0` (M3d, M11, M10, M12 recorded unpinned) |
| 3 | **`ok: false`**: one major (re-verification incomplete), two minor | 1333 at `6133316` | `632b327`…`6133316` were the fix round; its re-verification was cut short, see "Verifier round (lane 3)" |
| 4 | **`ok: true`**, no issues (second look at `8e1dfa7`) | 1348 | `cdd3c74` |
| 5 | **`ok: true`**, no issues (second look at `6d59cf0`) | 1355 | `5add712` |

**Not all five lanes verified `ok`.** Lane 3's second verifier ran two of its
fifteen mutations (A and B, both red) before it was told to return; it did not
re-take the demo comparison for `8a4a491`. What the record pass did about it,
and what it could not do, is in "Verifier round (lane 3)" and "Lane 3 — the
record pass's mutations".

## Mutations that stayed green, and what has no mutation

Each is a coverage statement, named rather than hidden in a count.

- **Lane 1 M15 vs 1.12** (probe groups of one): covered by 1.2, 1.7 and the
  branching tree, not by the test the spec named.
- **Lane 1 M16** (key the shaping cache on an integer width): **equivalent on
  every fixture**; nothing reddens. Not banked as covered.
- **Lane 2 L8** (checkpoint 3's width term alone): green in the lane; pinned in
  its verifier round by `anInfinitelyWideRootBoundsTraps` (M10).
- **Lane 2 verifier M3d, M11**: green before `103bce0`, red after.
- **Lane 2 verifier M12** (`.aspectRatio` places its child in its bounds rather
  than at its answer): **recorded unpinned** — every arm places the node at its
  answer; only a window-root aspect ratio could tell, and SwiftUI's placement
  there is unprobed.
- **Lane 3 M9** (`ProposalScrollView` lowers with an explicit 8): green at
  `f916d1c`; probe revision 7 (SC5) and `ef431b0` pin it vertically. **The
  horizontal case stays unprobed in a discriminating form** (SC5 horizontal
  reads b at 180 either way).
- **Lane 3, the record pass's F** (a same-axis stack's trailing edge read from
  its last child's leading edge): **nothing red**, and the mutant differs (60
  vs 68 on `HStack{a; HStack{c; sp.padding(.leading, 4)}; b}`). Unpinned and
  unprobed; 3.6's doc comment wrongly names V1b/V1c for it.
- **Lane 4 verifier V3, V7–V10**: green at `b1a4c42`, red after `cdd3c74`.
- **Lane 4 M9b** (do not clear `nativeParents` in `reset`): the unfiltered
  suite **truncates** in-process at
  `aResetTreeMeasuresItsNewRegistrationsFromScratch` (shape 13); only a filtered
  run shows 4.9's reset arm red.
- **Lane 5 M11** (lower the outermost layer after `animated`): **equivalent**
  by reading (`animated` never writes `display`); a convention, not a pinned
  behaviour.
- **Lane 5 M12** (inner layers not lowered): green at `c73706f`, red after
  `f21d626`.
- **Lane 5 verifier V1, V2, V8**: green at `017c813`, red after `5add712`.

**Unpinned or unprobed, by reading:**

- `K3f`'s placement (SwiftUI places b at 40 while reporting 40 wide); only the
  size is pinned.
- A NaN flexibility (∞ − ∞) in `solveLinearStack`'s comparator
  (`LayoutTree.swift:1239`): unprobed, unpinned, no built-in reaches it.
- A custom layout's own spacing preference: `ProposalLayout` has no `spacing`
  requirement, so every custom layout spaces as SwiftUI's default
  `Layout.spacing` (V3). No probe of a custom layout overriding `spacing`.
- H3 (a non-clickable primary blocks a click on its background's content in
  SwiftUI): recorded, not adopted, and **no test** pins MetalUI's answer.
- `measureNativeLayout`'s own bracket (record §09's item) is still separate
  from the shared `runNativeLayout`.
- The single-axis `.frame(maxWidth: .infinity)` legacy inert row, the greedy
  finite maximum and the nil-axis frame under a stretching `Box`: untouched,
  owner task 7.
- Two-axis `ProposalScrollView` centring (SCG2 both): not built.

## Demo comparisons, in one place

Stand-in every lane: `CN-R`'s harness (`scratchpad/harness/gen.py`, twelve
images through a real `Window` over `FakePlatformWindow`, scale 1, pixels and
scene dumps) on `git archive` trees. **`IOConsoleLocked` read `<true/>` at
every lane's end and again at the record pass (`ioreg -n Root -d1 -a`,
2026-09-16 16:4x PDT); no real window was captured.** `FR-V` records that
`IOConsoleLocked` is not a reliable lock check; the CGS probe
(`docs/probes/appkit-screen-lock-state.swift`) was not run by any lane.

Controls, identical at base and at every head: light vs dark 1 048 576;
default vs modal 1 030 498; default vs animation 210 027; f0 vs f3 0; preview
light vs dark 1 048 576.

| after | 8 legacy images + `small560-default` vs `9e439cb` | `preview-light`/`-dark` (1024) vs `9e439cb`, each | `small560-preview-light` vs `9e439cb` | matches `CN-S` |
|---|---|---|---|---|
| lane 1 (`31fd2ba`; re-taken by its verifier) | 0, scenes identical | 155 248, bbox (84, 661)–(939, 939): the toggle 496×279 | 93 522 | row 1 |
| lane 2 (`63387f6`) | 0 | 188, bbox (264, 845)–(431, 865): the toggle 168×95 (AR1, AR4) | 64 199: root answer 696×604 at (−68, −22) | row 2 |
| lane 3 (`f916d1c`) | 0 | 188 (0 vs lane 2) | 64 199 | row 3 |
| lane 3 verifier round (`8a4a491`) | **not taken as its own comparison**; covered transitively, below | | | |
| lane 4 (`1ae17cc`) | 0 | 1 109, bbox (264, 212)–(939, 865): lane 2's rect plus the scroll view's 48 widths 856 → 520 (SC2) | 65 449 | row 4 |
| lane 5 (`c73706f` = `6d59cf0`'s `Sources/`) | 0, and 0 in all twelve vs lane 4 | 1 109 | 65 449 | row 5 |

**`8a4a491` is covered by lane 4's comparison.** Lane 4 compared its images
with lane 3's `f916d1c` and found only the scroll view's 48 widths changed in
the 1024 preview's scene, all traced to `CN-M`; `8a4a491` sits between those
two commits, so it moved no preview rect a scene dump records. `git diff
c73706f 6d59cf0 -- Sources` is empty, so lane 5's images are HEAD's.

**What the legacy zeros prove:** only that nothing else moved. No legacy image
contains a native node, the demo has no legacy `.frame` and no `percent:`, so
lanes 1–5 have no legacy pixel evidence (`CN-S`). The preview images are the
evidence for lanes 1, 2 and 4; lanes 3 and 5 have none.

## Hazards this track introduced or exposed

1. **Two stored properties on `LayoutTree`** (`spacerAxes`, `nativeParents`),
   a public class read across the `MetalUILayout` → `MetalUI` boundary, plus
   `ModifierLayer.isFrame` and `HStack`/`VStack`'s stored types. An incremental
   build over a pre-merge build reproduces the `CN-R` failure (every `Frame`'s
   generation read as 0). **`swift package clean` after merging.**
2. **`reset(generation:)` must clear `nativeParents` and `spacerAxes`.**
   Losing the first truncates the unfiltered suite at
   `aResetTreeMeasuresItsNewRegistrationsFromScratch` with no summary line
   (M9b); losing the second reddens only that test's spacer arm (M11).
3. **A native node reused under a second parent now traps** (`CN-L`, "MC-G
   hole 4"), at every registrar with children. No `Sources/` tree does it.
4. **Work rose.** The branching tree reads 64 calls / 51 hits / 90 misses
   (16 / 27 / 25 before); nested alternating stacks up to 8.2 leaf calls per
   leaf at a finite root and 11.2 in a scroll viewport; each `ProposalText` is
   shaped at 4 widths per cold frame, not 2. The cache is still per call
   (`SA-H`), so a warm frame pays it again. No timing was taken.
5. **An infinite proposal is answered with infinity** by a frame with an
   infinite maximum, a spacer and a scroll viewport's scrolling axis
   (`CN-F`, reversing `FR-B`). A custom layout that places a child at ∞ traps at
   checkpoint 3 (2.4), as SwiftUI crashes (D12).
6. **A NaN flexibility.** A custom `ProposalLayout` answering ∞ at both main 0
   and main ∞, in a priority group of two or more, gets flexibility NaN, and the
   comparator orders the group inconsistently (lane 1 verifier, minor 3). No
   trap, no diagnostic, unpinned.
7. **A legacy frame's lowering depends on its content's node count.** Over
   exactly one node it is a one-cell `display: .stack` (the child keeps its
   size and overflows, SwiftUI's A5); over zero or several (a multi-member
   `Component`) it is `FR-C`'s flex row, which shrinks them. A conditional that
   changes the count between 1 and 2 switches the lowering at run time.
   **On the single child, `.flexGrow` and `.alignSelf` compile and do nothing**
   (5.8), the fill idiom `.flexGrow(1).frame(maxWidth: .infinity, maxHeight:
   .infinity)` included; `width(fraction: 1)` is the workaround.
8. **The deprecated spellings.** `HStack(spacing:alignment:content:)` and
   `VStack(…)` (nine-case alignment, no defaults, cross factor only) and
   `width/height/flexBasis(percent:)` warn; the 0-`warning:` gate makes every
   call site move. 5.2's arm F and the deprecated-forwarding test call them
   through a protocol whose witness is deprecated, which the compiler does not
   diagnose — a way to hide a deprecation the suite now uses on purpose.
9. **`HStack(alignment: .leading)` no longer compiles** (typed alignments,
   SwiftUI's own error; G1). A caller of the old argument order gets a
   warning, not an error.
10. **Default spacing is a walk, recomputed per solve.** `zeroSpacingEdges` is
    an exhaustive `switch`: a new `NativeNode` case must choose its edges, and
    one that chooses "neither" silently adds 8pt beside a spacer.
11. **Kernel callers:** `computeNativeLayout(root:proposal:in:)` still places
    the root at the caller's bounds, and a `ZStack` root placed in bounds larger
    than its answer puts its union at the bounds' origin (`CN-E`), a placement
    SwiftUI has no spelling for. Only `Frame.computeRootLayout` centres.
12. **The preview now looks different**, deliberately: the bottom row's toggle
    is 168×95, the `ProposalScrollView` is as wide as its content (520 at
    1024), and at 560×560 the content answers 696×604 and overflows the window,
    centred. Its first human look is still owed.
13. **Probe labels V7f/V7k are wrong in the recorded output** (above).
14. **A same-axis nested stack's trailing zero edge is inferred by symmetry,
    not measured** (record pass mutation F): a last child with asymmetric
    edges (a one-side-padded spacer) is the only shape that tells, and no probe
    arm or test builds it.
15. **The four new guards skip in a worktree never built natively**; each
    prints its diagnostics, so grep a log for `is deprecated` / the G1 output
    to know they ran.

## Deferred, each with an owner

| deferral | why | owner |
|---|---|---|
| lowering `Row`/`Column`/`Stack`/`Box`/`ScrollView`/`Deferred` onto the kernel; switching the default demo root; the legacy divergences (gap 0, `Stack` fit-content, `ScrollView` cross axis, flex-shrink compression) | `SA-G` makes it a whole-tree conversion (`CN-A`) | task 7 |
| a windowed proposal `List` (layout, windowing, `ScrollContext`, row identity, `AXTable` records) | the `MP-`/`TB-`/`AB-L` rulings; K6 fixes its layout answer | task 7 (moved from task 10, `CN-T`) |
| a proposal portal for `Deferred` | no layout-protocol counterpart (P1–P5) | task 7 |
| SwiftUI `List` semantics beyond layout | data-driven controls | task 10 |
| a greedy finite and a single-axis infinite maximum on the legacy frame; a nil-axis frame under a stretching `Box` | needs the parent's flex axis at registration (`CN-Q`) | task 7 (was task 6) |
| legacy `.overlay` | the `ModifiedContent` unification | task 7 |
| two-axis scrolling | one offset, one axis, one track (`CN-M`) | task 10 |
| text-edge vertical default spacing; baseline stack alignment | needs font metrics (`CN-H`) | task 11 |
| builder wrappers with zero or several nodes | `Group` semantics | task 8 |
| `SA-N` item 4, padding places its child at the child's size | not a container | task 7 |
| H3, a non-clickable primary blocking its background's click | MetalUI's hit model | task 12 |
| a frame over a multi-member `Component` framing each member (G7) | neither lowering gives it (`CN-N`) | task 7 (with `FR-F`'s component work) |
| the NaN flexibility guard | found by the lane 1 verifier, not ruled | unowned; the next change to `solveLinearStack` |
| the V7f/V7k probe labels | found by the lane 3 verifier | the next probe revision |
| probing and pinning a same-axis stack whose last child has asymmetric edges (V1k mirrored) | record pass mutation F | the next probe revision, then an arm in 3.6 |
| the lane 3 verifier-round re-verification by an independent verifier, and its `8a4a491` demo comparison | the verifier was stopped (above) | the integrator's verification pass |
| the release-window captures | locked display at every lane | carried (`MC-J`, `FR-V`) |
| the preview's first human look | none recorded | CLAUDE.md's human-verification table |

## For the integrator

**Verdict: NOT all five lanes verified `ok`.** Lanes 1, 2, 4 and 5 verified
`ok: true` (lane 1 with three minor issues, dispositioned above; lanes 2, 4
and 5 clean after their fix rounds). **Lane 3 verified `ok: false`**: its
second verifier was stopped after two of fifteen mutations, and did not
re-take the demo comparison for `8a4a491`. The record pass then ran the twelve
outstanding mutations on `6d59cf0`'s tree (eleven of twelve reddened their
named tests; **F**, a same-axis stack's trailing edge read from its last
child's leading edge, left the suite green and was proven to differ (60 vs 68
wide) on a tree no probe arm builds). That is the record writer's measurement,
not an independent verifier's, and lane 3's verdict stands as `ok: false`
until one re-runs them. The two minor issues are this record's lane 3
verifier-round section (now written) and the V7f/V7k probe labels (still
wrong). **Before merging:** have a verifier re-run lane 3's mutations C–K
(each a one-line edit to `zeroSpacingEdges`, `StackAlignment.swift` or the
deprecated `HStack`/`VStack` initializers, as tabled in "Lane 3 — the record
pass's mutations") and decide F: probe V1k mirrored (`HStack{a; HStack{c;
Spacer(minLength: 0).padding(.leading, 4)}; b}` at nil×nil; the kernel answers
60) and add the arm to 3.6.

This branch's figures: **1355 tests, 97 goldens, 70 guards, 0 `error:` / 0
`warning:`** (the lone `warning:` in a native log is SwiftPM's deprecation
notice); 34 `@available(*, deprecated` hits. Re-take every count after the
merge, after `swift package clean` (hazard 1).

**`CLAUDE.md` (rules only; then `cp CLAUDE.md AGENTS.md` and `cmp`):**

1. **Ruling table.** Add `` | `CN-` | containers, plan task 6 (`CN-A`…`CN-U`,
   next is `CN-V`) | lettered | ``; add `CN-3` to the bare-typo sentence. Add to
   "Where things are": `` - containers (task 6, `CN-`):
   `specs/2026-09-16-containers-design.md`,
   `2026-09-16-containers-decisions.md`, record §17; probes
   `docs/probes/swiftui-stack-algorithms.swift` (revision 8, 220 arms) and
   `swiftui-overlay-presentation.swift` (compiled form only). ``
2. **Counts.** 1303 / 97 / 66 → **1355 / 97 / 70** on `feat/containers`
   (+52 tests: lane 1 +13, lane 2 +7, lane 3 +10, lane 4 +15, lane 5 +7;
   +4 guards, all in `ContainerCompileGuards`), then re-take after the merge.
   Add `ContainerCompileGuards` 4 to the per-file list and to the "count with
   per-file `grep -c canTypecheck` across …" sentence. "the other 26 — …" →
   "the other 30 — … `ContainerCompileGuards`' four …". In "CI — what lapses
   silently", "all 66 guards skip" → 70. In "Vocabulary", "26 of the 29
   `@available(*, deprecated` hits (the others are task 9's `Binding` alias …
   and task 4's `frame()` on each protocol)" → "26 of the 34 (… task 4's
   `frame()` on each protocol, task 6's two spacing-first stack initializers
   and three `percent:` sizing modifiers)".
3. **Containers (legacy).** In the frame sentence run, replace "**Three legacy
   divergences are pinned wrong on purpose:** a finite maximum clamps but never
   grows into the proposal (35); an oversized child is squeezed on the layer's
   main axis and overflows the cross axis (36); a single-axis infinite maximum
   is inert (inert table)." with:
   > "**A legacy frame over exactly ONE node lowers to a one-cell `display:
   > .stack`** (`CN-N`): the child keeps its own size and overflows both axes,
   > SwiftUI's A5 (`aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`,
   > inner layers included). Over zero or several nodes — a multi-member
   > `Component` — it stays `FR-C`'s flex row and shrinks them, where SwiftUI
   > frames each member (G7). **A stack reads neither `.flexGrow` nor
   > `.alignSelf`, so on the only child of a legacy frame both compile and do
   > nothing** (inert table; `width(fraction: 1)` fills). **Two legacy
   > divergences stay pinned wrong on purpose**, owner now task 7: a finite
   > maximum clamps but never grows (35); a single-axis infinite maximum is
   > inert (inert table)."

   After "There is no `display: contents`." add:
   > "**The legacy containers keep their CSS algorithms** (`CN-A`, `CN-P`):
   > `Row`/`Column` default to gap 0 where `HStack`/`VStack` default to 8; a
   > `Stack` offers a child fit-content where a `ZStack` offers its proposal;
   > a legacy `ScrollView` takes its cross axis from its parent where a
   > `ProposalScrollView` takes its content's; compression is flex-shrink by
   > base size, not flexibility order. Each is pinned side by side with its
   > proposal counterpart (divergences, task 7). Porting a `Row {}` to an
   > `HStack {}` changes all four silently."
4. **Sizing modifiers.** Replace the `percent:` sentences with: "**Fractions
   are spelled `width(fraction:)`, `height(fraction:)`, `flexBasis(fraction:)`**
   (`CN-O`): `fraction: 0.5` is half. The `percent:` spellings are deprecated
   renames that forward unchanged (they always took a fraction; guard
   `thePercentSizingModifiersAreDeprecatedRenamesOfFraction`)." Change the list
   "`width(percent:)` and `height(percent:)` write THIS element's own CSS box"
   to name `fraction:`.
5. **SwiftUI alignment — root.** Replace "A native root runs
   `LayoutTree.computeNativeLayout(root:proposal:in:)` … puts its trailing item
   at x = 28)." with:
   > "A native root is measured at the window proposal and **placed centred at
   > its own answer** (`CN-J`, probe R1/R2) by
   > `computeNativeLayout(root:proposal:centredIn:)`
   > (`aNativeRootIsCentredAtItsAnswer`); a greedy root still fills.
   > `computeNativeLayout(root:proposal:in:)` still places at the caller's
   > bounds, and a `ZStack` placed in bounds larger than its answer puts its
   > union at their origin (`CN-E`). Both entries share one private
   > `runNativeLayout`; `measureNativeLayout` keeps its own bracket."
   Delete "(its doc comment still says "runs the flex engine")": lane 4 fixed it.
6. **SwiftUI alignment — the stack rules, a new paragraph** after "`ProposalLayout`
   is the public algorithm protocol":
   > "**The kernel's stacks are SwiftUI's** (`CN-B`…`CN-I`,
   > `swiftui-stack-algorithms.swift`). A linear stack at a finite main
   > proposal takes spacing off, groups children by priority highest first,
   > offers each group what remains **minus every lower-priority child's
   > answer at main 0**, serves each group **least flexible first** (answer at
   > main ∞ minus answer at main 0; ties in declaration order) at `max(0,
   > remaining / left)`, and **answers the sum of the answers, overflow
   > included**; at a nil or ∞ main proposal every child gets that value. One
   > function (`solveLinearStack`) serves measurement and placement. At a nil
   > cross proposal it places after a second pass at its own cross size. A
   > `Spacer` has priority −∞, a nil `minLength` of **8**
   > (`ProposalSpacing.platformDefault`), answers ∞ at ∞, and answers **0 on
   > the cross axis of the stack that marks it** — the mark passes
   > `layoutPriority`, `padding`, `frame`, `fixedSize`, `aspectRatio` and both
   > sides of an overlay attachment, and stops at a `ZStack`, a nested stack, a
   > scroll viewport and a custom layout. **A single-child `HStack`/`VStack`/
   > `ZStack` passes its child's priority through**; a custom layout reads 0.
   > **Default spacing (`spacing: nil`) is decided per adjacent pair**: 0 if
   > either facing edge is a zero-spacing edge, else 8 (`zeroSpacingEdges`, an
   > exhaustive switch: a spacer along its marking axis; wrappers pass through;
   > padding only on a 0 inset; a same-axis stack its first and last child's; a
   > cross-axis stack or custom layout if ANY child is; a `ZStack` if EVERY
   > child is; an empty container both); an explicit spacing is used verbatim,
   > beside a spacer too. A `ZStack` measures children at its proposal, places
   > each at **its own size** as the proposal, aligned within the union of
   > those answers. `.aspectRatio` answers **its child's** answer to the
   > ratio-shaped proposal, ∞ a concrete axis. A frame with an infinite
   > maximum, a spacer and a scroll viewport's scrolling axis **answer ∞ at ∞**
   > (`CN-F`, reversing `FR-B`); a custom layout placing a child there traps at
   > checkpoint 3. Every one is pinned against a probe arm in
   > `NativeStackDistributionTests` and `ContainerIntegrationTests`."
7. **SwiftUI alignment — edits elsewhere in the section.**
   - "**Proxies expose `priority`, `isSpacer` …, each by the built-in stack's
     own rule**" → "`priority` by the built-in stack's rule (a spacer −∞, a
     single-child stack its child's); `isSpacer` is read by no built-in".
   - "**Sufficiency.** … It proves the **horizontal** path only (verifier
     mutation F1)" → "It compares a transposed vertical tree too, and spacers'
     main extents only (a `ProposalLayout` cannot mark a spacer)".
   - "**Seven holes stay**" → "**Six holes stay**"; delete "one id used twice
     does not trap"; add after the list: "A native node registered under a
     second parent **traps** at every registrar with children (`CN-L`, exit
     tests); `reset` clears the record, and losing that clear truncates the
     unfiltered suite at `aResetTreeMeasuresItsNewRegistrationsFromScratch`."
     Change "A precondition closing the orphan or duplicate hole truncates the
     suite" to "A precondition closing the orphan hole truncates the suite".
   - "Single-child proposal wrappers (… both `.overlay` slots …) precondition
     exactly one node" → drop "both `.overlay` slots", add: "`.overlay` and
     `.background(alignment:content:)` precondition one PRIMARY node; their
     content may be zero nodes (no attachment, the primary alone), one, or
     several (a `.center` kernel `ZStack` positioned by the modifier's
     alignment) (`CN-K`). A background's content prepaints and paints before
     its primary, so a click over both reaches the primary."
   - **Vocabulary:** "`HStack`/`VStack(spacing: 8, alignment: .center)`" →
     "`HStack(alignment: VerticalAlignment = .center, spacing: Pixels? = nil)`,
     `VStack(alignment: HorizontalAlignment = .center, spacing:)` (`CN-I`;
     the nine-case spacing-first initializer is deprecated)"; "`Spacer(minLength:)`"
     → "`Spacer(minLength:)` (nil = 8)"; add `.background(alignment:content:)`
     to the modifier list; add `ProposalSpacing` and
     `computeNativeLayout(root:proposal:centredIn:)` to the kernel types.
   - **`ProposalScrollView` vs `ScrollView`:** "reports each finite proposal
     axis" → "answers `proposal ?? content` on its scrolling axis (∞ at ∞) and
     **its content's answer on the other** (`CN-M`, SC2); small content sits at
     the leading edge of the scrolling axis"; "multiple direct children lower
     to a **vertical** stack at spacing 8 on either axis" → "… to a centred
     **vertical** stack at default spacing (8, none beside a spacer: SC3, SC5)
     on either axis; two-axis scrolling does not exist (task 10)".
   - **Probe-backed values:** add at the top: "The stack, spacer, spacing,
     alignment, `ZStack`, overlay-content, root and scroll-axis rules have a
     saved probe with controls, `swiftui-stack-algorithms.swift`." Delete the
     `HStack`/`VStack` default-spacing bullet (superseded by paragraph 6) and
     the **Priority** bullet ("descending groups take their natural sum if it
     fits, else equal shares …"): **refuted by `CN-B`**. Keep the `Spacer`
     floor bullet. The `.aspectRatio` bullet: "fit/fill at 100×80 on 2:1
     proposes 100×50 / 160×80 and answers the child (AR1)".
   - **Probed, and the kernel disagrees (`SA-N`):** delete the `Spacer()` 8pt
     item (`CN-C`), the `aspectRatio` nil×nil item (`CN-G`) and the
     single-child priority item (`CN-D`). The padding item stays; add "it no
     longer shows at a centred root (`CN-J`)".
   - **The kernel's flexible frame is greedy:** "An infinite proposal answers
     the child (divergence 37)" → "An infinite maximum answers ∞ at an infinite
     proposal (`CN-F`)".
   - **Unprobed kernel behaviour that fails silently:** delete the first two
     bullets (only a `Spacer` takes surplus …; measures at nil, places at
     allocations) — both refuted and replaced by paragraph 6. Add: "a custom
     `ProposalLayout` that answers ∞ at both main 0 and main ∞ gets a NaN
     flexibility and an inconsistent order within its priority group
     (`LayoutTree.swift` `solveLinearStack`; unprobed, unpinned)"; and "a custom
     layout has no spacing preference: it spaces as SwiftUI's default
     `Layout.spacing` (V3)"; and "a same-axis nested stack's trailing
     zero-spacing edge comes from its last child's trailing edge by symmetry
     with V1k; no probe arm has a last child whose two edges differ (record
     §17, mutation F)".
8. **Performance.** "on the branching tree in `NativeLayoutWorkTests.swift` one
   call is 16 measure calls, 27 hits, 25 misses" → "64 measure calls, 51 hits,
   90 misses (`CN-B`: stacks probe children at main 0 and ∞); nested
   alternating stacks cost up to ~11 leaf calls per leaf, and a `ProposalText`
   in a stack is shaped at 4 widths per cold frame, not 2". Still no timing.
9. **Practices.** Add: "**A rule read from one arm is unprobed for every node
   kind that arm does not contain.** `CN-H`'s 'none for anything else' rested
   on K3h, a cross-axis stack; probe revision 8's V group refuted it for
   same-axis stacks, custom layouts and empty containers." And: "**An arm
   green on arrival cannot see the ruling it is named for; write the
   separating arm** (G4 → G4r/G4f; K2c → K2f–K2j)."
10. **Human verification.** In the proposal-preview row add: "since task 6 the
    bottom row's toggle is 168×95, the scroll view is as wide as its content
    (520 at 1024), and at 560×560 the content answers 696×604 and overflows,
    centred (record §17)". Add a row: "containers (plan task 6): release-window
    capture of the default demo and the preview against `9e439cb` | **open**:
    `IOConsoleLocked` read `true` at every lane; stand-in offscreen, legacy 0 in
    all nine, preview 1 109 per 1024 image and 65 449 at 560, every rect traced
    to `CN-G`/`CN-M` (record §17); the lock check itself should be the CGS
    probe (`FR-V`)".

**Divergence table** (`CLAUDE.md`; record §04's 35–50 index gains the rest):

- **Retire 36** (`FR-N`): fixed by `CN-N` for a frame over one node; its pin
  was replaced by `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes`.
- **Retire 37** (`FR-B`): reversed by `CN-F`; its pin was deleted and replaced
  by `anInfiniteProposalIsAnsweredWithInfinity`.
- **Retire 40** (`FR-T`): the unit was always a fraction and is now spelled
  `fraction:`; `percent:` is deprecated (`CN-O`). Update README's "Two are
  unfixed defects" sentence to one (19).
- **35** stays; its owner changes from task 6 to **task 7** (`CN-Q`).
- **Add**, numbers 51 onward, `vs SwiftUI` unless stated:

> "51 | `ProposalText` beside `ProposalText` in a `VStack` is 8pt apart; SwiftUI's
> text edges are font-derived (text|text 0, rect|text 4.74, text|rect 8.15;
> probe S, `CN-H`). Pinned by `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing`;
> task 11."

> "52 | Legacy `Row`/`Column` default to gap 0; `HStack`/`VStack` 8 (probe S,
> `CN-P` 1). Pinned by
> `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight`;
> task 7."

> "53 | A legacy `Stack` offers a child fit-content; `ZStack` offers its
> proposal (A5: a greedy child fills 100×80; a childless `Box` is 0×0)
> (`CN-P` 2). Pinned by `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal`;
> task 7."

> "54 | A legacy `ScrollView` takes its cross axis from its parent; SwiftUI's
> takes its content's (SC2, `CN-P` 3). Pinned by
> `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`;
> task 7."

> "55 | Legacy `Row`/`Column` compress by flex-shrink in proportion to base
> size and expand only by `flexGrow`, with no `Spacer`; a SwiftUI stack serves
> least flexible first (G1, `CN-P` 4). Covered by the CSS goldens; task 7."

> "56 | A legacy `.frame` over a multi-member `Component` lays the members
> out as a flex row; SwiftUI frames each member (G7, `CN-N`). Pinned as it
> stands by `aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren` and
> `chainedFramesRemainConcreteAndNestTheirLayoutNodes`; task 7."

> "57 | A non-clickable proposal primary does not block a click to its
> `.background` content; SwiftUI's does (overlay-presentation H3, `CN-K`).
> Unpinned; task 12."

> "58 | design | A `ZStack` placed by a kernel caller in bounds larger than its
> answer puts the union of its children at the bounds' origin (`CN-E`);
> SwiftUI has no such placement. Pinned by
> `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion`."

  README's "Forty-two measured divergences" → forty-seven (42 − 3 + 8), if
  all eight are assigned.

**Declared-but-inert table:**

- **Reword** "`HStack`/`VStack`'s `alignment:` main-axis half" →
  "`HStack(spacing:alignment:content:)` / `VStack(…)`, the deprecated
  spacing-first initializers | take a nine-case `ProposalAlignment` and read
  only its cross-axis factor: `.leading` on an `HStack` places as `.center`.
  The current `init(alignment:spacing:)` takes `VerticalAlignment` /
  `HorizontalAlignment` and rejects the other axis at compile time (`CN-I`,
  guards G1–G3); delete this row with the deprecated initializers".
- **Add** "`.flexGrow` / `.alignSelf` on the only child of a legacy `.frame` |
  the one-node frame is a `display: .stack`, which reads neither; both compile
  and do nothing, the fill idiom `.flexGrow(1).frame(maxWidth: .infinity,
  maxHeight: .infinity)` included; `width(fraction: 1)`/`height(fraction: 1)`
  fill (`CN-N`, `aSingleChildLegacyFrameIgnoresItsChildsFlexGrowAndAlignSelf`)".
- **Edit** the single-axis `.frame(maxWidth: .infinity)` row: owner "task 6" →
  "task 7 (`CN-Q`)".
- **Edit** "`ProposedSize.zero` / `.infinity` | no container ever proposes
  them; nothing asks a child for its minimum or maximum" → "no container
  proposes them on both axes; linear stacks now ask each child for its
  main-axis minimum and maximum (main 0 and main ∞, cross proposal kept,
  `CN-B`)".
- **Add** to the test-observables row: "`MeasurementSubview.isSpacer` /
  `PlacementSubview.isSpacer` (read by no built-in since `CN-B`)".
- **Add** "`width(percent:)`, `height(percent:)`, `flexBasis(percent:)` |
  deprecated renames of `…(fraction:)`, forwarding unchanged (`CN-O`)" — or
  list them with the other deprecations in Vocabulary; they are not inert.

**The plan's task 6 entry: do NOT tick it.** The task's own text:

- *"Audit Row, Column, Stack, Box, Spacer, ScrollView, List, and Deferred
  against HStack, VStack, ZStack, Spacer, ScrollView, List, and
  overlay/presentation patterns"* — **done** (spec §3's table, probes K6 for
  `List`, P0–P6/H0–H3 for presentation; `Spacer` has no legacy counterpart).
- *"Port stack, overlay and spacer algorithms directly to the new proposal
  system"* — **done** (`CN-B`…`CN-K`, lanes 1–4).
- *"Cover proposal propagation, explicit versus platform-default spacing, all
  nine Alignment positions, frame alignment, and scroll axes"* — **done except
  two-axis scrolling** (task 10, `CN-M`); the nine positions are pinned for
  `ZStack`, `.overlay`, `.background` and both frames, three per axis for the
  linear stacks.
- *"Preserve the existing centred stack defaults only where probes confirm
  them"* — **done** (A1–A3, A6, A9, K5g/K5h confirm centring).
- *"Replace containers with SwiftUI-style algorithms"* (the title) — **not
  met**: no legacy container is replaced or lowered (`CN-A`), by ruling.

Proposed text under the unchanged body, replacing the 2026-09-14 progress note:

> *Progress 2026-09-16 on `feat/containers` (`75b5f69..`record commit), still
> open.* Spec `specs/2026-09-16-containers-design.md`; rulings `CN-A`…`CN-U` in
> `../2026-09-16-containers-decisions.md`; probes
> `docs/probes/swiftui-stack-algorithms.swift` (revision 8) and
> `swiftui-overlay-presentation.swift`; record §17. Five lanes, each red first;
> lanes 1, 2, 4, 5 verified `ok`, lane 3 `ok: false` (re-verification cut
> short; record §17). Suite 1355 (1303 + 52), 97 goldens unmoved, 70 guards.
> - **Proposal containers — SwiftUI's** (lanes 1–4): stack distribution,
>   spacer, per-edge default spacing, typed stack alignments, `ZStack`
>   placement, centred root, overlay/background content with
>   `.background(alignment:content:)`, duplicate-parent trap, scroll-view cross
>   axis. `SA-N` items 2, 3 and 8 closed; `FR-B` reversed.
> - **Legacy path** (lane 5): a one-node legacy frame overflows both axes
>   (`FR-N` closed); `fraction:` sizing, `percent:` deprecated (`FR-T`
>   resolved); gap 0, `Stack` fit-content and `ScrollView` cross axis pinned
>   as divergences.
>
> **Not done, by ruling (`CN-A`, `CN-Q`):** no legacy container is lowered or
> replaced; the root switch, a windowed proposal `List`, a `Deferred` portal,
> legacy `.overlay` and the legacy frame's greedy/single-axis maxima go to task
> 7; two-axis scrolling to task 10; text-edge spacing to task 11.
> **Proposed amendment (`CN-T`), for the user to accept or not:** retitle task
> 6 "Port SwiftUI's container algorithms to the proposal path and audit the
> legacy containers" with `CN-T`'s body, and append "including a windowed
> proposal `List` and a proposal portal for `Deferred`" to task 7's "Migrate
> the remaining elements off `FlexEngine`". If accepted, tick task 6.

Task 7's progress note: "expansion of non-spacer children are still absent" is
history (`CN-B`: a greedy frame takes surplus, G4r/G4f).

**README:**

- The count sentence (1303 / 97 / 66 on `integrate/tasks-4-5`): this branch
  reads 1355 / 97 / 70; re-take after the merge.
- "Forty-two measured divergences … Two are unfixed defects (19 …; 40,
  `width(percent:)` takes a fraction)" → re-count after assigning the rows
  above (47), and one unfixed defect (19).
- Under "SwiftUI alignment", add the containers spec and record §17.
- Where a sample writes `width(percent:)`, write `width(fraction:)`
  (`git grep -n 'percent:' README.md` first).

**Other owned documents:**

- `docs/record/README.md`: add `` | `17-containers.md` | plan task 6 on
  `feat/containers`: SwiftUI's stack distribution, spacer, per-edge default
  spacing, typed alignments, `ZStack` and root placement, overlay/background
  content, the duplicate-parent trap and scroll axes on the proposal path;
  the one-node legacy frame and `fraction:`; the legacy audit and its pins;
  five lanes, their red runs, verifier verdicts (lane 3 `ok: false`) and
  mutation tables; the offscreen pixel stand-in; counts 1355 / 97 / 70 | ``.
- `docs/record/04-divergences.md`: retire 36, 37, 40 and index 51–58.
- SA decisions doc, `SA-N` items 2, 3, 8: "**Closed 2026-09-16 by `CN-C`**",
  "`CN-G`", "`CN-D`" (`feat/containers`).
- FR decisions doc: `FR-B` "**Reversed by `CN-F`**"; `FR-N` "**Closed by
  `CN-N`** for a frame over one node"; `FR-T` "**Resolved by `CN-O`**"; `FR-E`,
  `FR-O` and `MC-Q` finding 7's nil axis: owner task 6 → task 7.
- MC decisions doc, `MC-G`: hole 4 closed at run time (`CN-L`); `MC-L`'s
  one-node overlay trap and two-scroll-views items delivered (`CN-K`, 4.15).
- Record §09: "It proves the horizontal path only (verifier mutation F1)" is
  closed (lane 1 compares a transposed tree).
- `docs/probes/swiftui-stack-algorithms.swift`: fix the V7f/V7k labels and
  re-record (run twice, byte-identical apart from those two lines).

## Docs phase (integrator)

2026-09-16, on `feat/containers` from `5224dfa`. Documents only, plus one probe
re-record and one mutation; no `Sources/` or test change.

**Counts, re-taken.** `swift package clean`, `swift build --build-system native
--build-tests`, then unfiltered `swift test --build-system native
--no-parallel`: `Test run with 1355 tests in 1 suite passed after 41.342
seconds`; 0 `error:` in the build and test logs; the one `warning:` in each is
SwiftPM's `--build-system native` deprecation notice; only
`regenerateAllGoldens` and `aListsWorkIsTheSameFor100kRowsAsFor500` skipped.
The four `ContainerCompileGuards` ran (`CONTAINER GUARD G1 …`/`G4 …` lines in
the log; 0.2–0.5 s each). Goldens 97, `git diff --stat 9e439cb` over them
empty. Guards 70, per file by `grep -c canTypecheck`: `PhaseSeparationTests`
19, `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
`ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
`ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `AXNodeTests` 3,
`DecorationCompileGuards` 3, `UnitSafetyTests` 2 (3 hits, one a comment),
`ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2.
`@available(*, deprecated` hits in `Sources/`: 34.

**Probe revision 9.** The V7f and V7k labels in
`docs/probes/swiftui-stack-algorithms.swift` now name the trees they run; run
twice (`/usr/bin/swift`, exit 0, byte-identical), 779 lines, and against
revision 8's recorded output `diff` shows exactly those two lines with the
figures unchanged (44x20, 52x20). The header records it. Hazard 13 and the
"Probe defects left open" paragraph above are closed by this.

**Record §09 mutation F1, re-run** at `7b47c6a`:
`ReferenceLinearStack.swift:89`'s `* alignment.horizontalFactor` → `* 0`,
filtered run of `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`:
red, 7 issues at `ProposalLayoutTests.swift:212` (`c == b`). Restored from a
copy; `git status --short` clean. Lane 1's transposed tree closes it.

**Not done here:** lane 3's mutations C–K by an independent verifier and a
decision on F (probe V1k mirrored, an arm in 3.6). Lane 3 stays `ok: false`;
the plan's task 6 note says so.

**Documents changed:** `CLAUDE.md`/`AGENTS.md` (ruling table, Where things
are, counts and guard sentences, legacy frame and containers rules, `fraction:`,
the native root, the stack rules paragraph, proxies, sufficiency, the holes,
wrapper preconditions, Vocabulary, `ProposalScrollView`, probe-backed values,
`SA-N`, the greedy frame, unprobed behaviour, performance, practices, human
verification, divergences 36/37/40 retired and 51–58 added, inert rows);
`README.md`; `docs/record/README.md`; `docs/record/04-divergences.md`;
`docs/record/09-swiftui-alignment.md` (F1); the plan (task 6 progress note,
not ticked; notes on tasks 2, 3, 4, 5 and 7; dated history in "Current
starting point"); the `SA-`, `FR-` and `MC-` decisions docs.

## Branch checker (adversarial, `9e439cb..14f8abe`)

2026-09-16, in this worktree at `14f8abe`. Documents only; no `Sources/` or
test change.

**Suite, re-taken.** `swift build --build-system native --build-tests`, then
unfiltered `swift test --build-system native --no-parallel`: `Test run with
1355 tests in 1 suite passed after 41.312 seconds`; 0 `error:`; the only
`warning:` SwiftPM's deprecation notice; only `regenerateAllGoldens` and
`aListsWorkIsTheSameFor100kRowsAsFor500` skipped; `CONTAINER GUARD G1`…`G4`
lines printed. Under the default build system (`swift build --build-tests`,
`swift test --no-parallel`): six summary lines, 65 + 745 + 55 + 28 + 440 + 22
= **1355**, all passed, 0 `error:`, 0 `warning:`. Goldens 97, `git diff
9e439cb..HEAD` over them empty. Guards 70 by per-file `grep -c canTypecheck`
(the Docs phase's table, identical). `cmp CLAUDE.md AGENTS.md` identical.
`@available(*, deprecated` hits in `Sources/` 34, broken down as CLAUDE.md
says (17 + `Binding` typealiases, 9 `native…` methods, 2 `frame()`, 2 stack
initializers, 3 `percent:`). Every long backticked test name in `CLAUDE.md`
and `README.md` exists as a declaration; the six in added doc lines that do
not are each cited as deleted or replaced.

**Mutations** (`LayoutTree.swift`, exact unique replacement, native build,
unfiltered suite, restored from a copy, `git status --short` clean after each;
every run printed its 1355-test summary line):

| mutation | red |
|---|---|
| M1 `solveLinearStack` serves MOST flexible first (`l > r`) | 11 tests, 70 issues: `aStackServesItsLeastFlexibleChildFirst`, `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`, `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI`, `aGreedyChildTakesTheSurplusAheadOfASpacer`, `aStackAnswersTheSumOfItsChildrensAnswers`, `aStackMeasuresItsCrossSizeAtItsAllocations`, `aStackWithASpacerStillCompressesItsOtherChildren`, `anInfiniteProposalIsAnsweredWithInfinity`, `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI`, `overlayAndBackgroundContentIsPlacedAtThePrimarysSize`, `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` |
| M2 = lane 3's C: a same-axis nested stack has no zero edge | `defaultSpacingBesideANestedContainerFollowsItsChildrensEdges` only, 24 issues — the record pass's figure exactly |
| M3 = lane 3's F: trailing edge read from the last child's leading edge | **nothing red** — the record pass's finding confirmed |
| M4 `CN-D`: a single-child stack reads priority 0 | 4 tests, 8 issues: `aSingleChildStackPassesItsChildsPriorityThrough`, `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`, `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis`, `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` |

Lane 3's D–K were not re-run here, so its independent re-verification stays
incomplete.

**Demo comparison, re-taken** (`CN-R`'s harness, `git archive` of `9e439cb` and
`14f8abe`, default build system, `DEMO_PIXELS_SMALL=1`). Base controls: light
vs dark 1 048 576, default vs modal 1 030 498, default vs animation 210 027,
f0 vs f3 0, preview light vs dark 1 048 576. Head vs base: the eight legacy
images and `small560-default-light` 0 with identical scenes;
`preview-light`/`-dark` 1 109 each, bbox (264, 212)–(939, 865);
`small560-preview-light` 65 449 — every figure the record's. The 1024
preview's scene differs in three rects only: the scroll view's border
856 → 520 wide (`CN-M`), the toggle 168×94 at y 846 → 168×95 at y 845 and its
20×20 child y 846 → 845 (`CN-G`). The 560 preview moves all sixteen rects:
the root 696×604 at (−68, −22) (`CN-J` centring an overflowing `CN-B`
answer), a 380-wide row member → 480 and its 0-wide neighbour → 36 (`CN-B`),
the toggle 123×69 → 168×95 (`CN-B`/`CN-G`). `IOConsoleLocked` read `<true/>`;
no real window was captured.

**List and identity.** `git diff 9e439cb..HEAD` touches no line of
`List.swift`, `ScrollView.swift`, `Deferred.swift`, `Stack.swift`,
`Flex.swift`, `MetalUIPlatform` or any id, `StateTable` or hit-testing source;
`ModifiedElement.swift` changes only the style a layer registers with, not its
id; no test asserting an id, `$state`/`$focus`/`$anim` path or `List` row name
changed. The legacy demo images read 0.

**Code defect found (not fixed): `.hidden()` after a one-node legacy frame is
undone by `CN-N`.** `ModifierLayer.lowered(_:childCount:)` sets
`style.display = .stack` unconditionally for a frame layer over one node, so a
`display: .none` written onto that layer by `hidden()` (a `Self`-returning
`StyledElement` modifier, which configures the outermost layer) is
overwritten. Scratch test in both `git archive` trees (not committed): a
20×20 mark in a `Row` with a 5×5 sibling, reading the sibling's x —

| chain | `9e439cb` | `14f8abe` |
|---|---|---|
| `mark.hidden()` (control) | 0 | 0 |
| `mark.frame(width: 40, height: 40)` (control) | 40 | 40 |
| `mark.frame(width: 40, height: 40).hidden()` | **0** | **40** |
| `mark.frame(width: 40, height: 40).padding(4).hidden()` | 0 | 0 |
| `mark.frame(minWidth: 40, maxWidth: 80).hidden()` | **0** | **40** |

By reading, the same overwrite defeats `AB-O`'s accessibility suppression for
that layer (`suppressingAccessibilityIfHidden` reads the registered node's
display). No test pins it. The fix is to keep `.none` in `lowered`; its pin is
the table above.

**Doc defects fixed** (this commit): the plan's task 6 note said the nine
alignment positions are pinned for `.background` (A9 pins three); `CLAUDE.md`
said every stack rule is pinned (mutation F is not) and traced every changed
560 rect to `CN-G`/`CN-M` (`CN-B` and `CN-J` move them too); the legacy frame
paragraph and the `hidden()` inert row gained the defect above; `CN-N`'s
decisions entry gained an addendum.

**Doc defect reported, not fixed (a test file):** test 3.6's doc comment
(`NativeStackDistributionTests.swift`, above
`defaultSpacingBesideANestedContainerFollowsItsChildrensEdges`) still says the
trailing-edge mutation reddens V1b and V1c; M3 shows it reddens nothing.
