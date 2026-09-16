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
Not added here.

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
