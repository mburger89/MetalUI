# 17 — Containers (plan task 6)

`feat/containers`, from `9e439cb`. Design: `docs/superpowers/specs/2026-09-16-containers-design.md`;
rulings `CN-A`… in `docs/superpowers/2026-09-16-containers-decisions.md`;
probes `docs/probes/swiftui-stack-algorithms.swift` (revision 4),
`docs/probes/swiftui-overlay-presentation.swift`. Written by the lanes, one
section each, in order.

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
  - the three `CN-P` divergences, owner task 7.
- `CN-Q`'s legacy frame items (greedy finite maximum, single-axis infinite
  maximum, nil-axis frame under a stretching `Box`), legacy `.overlay`, and
  lowering the legacy containers go to **task 7**, unchanged. None was
  attempted.
- A frame over a multi-member `Component` still lays its members out as a
  row. SwiftUI frames each member (`G7`), and neither lowering gives that
  answer (`CN-N`).
