# Containers — design (plan task 6)

`feat/containers` from `9e439cb`. Rulings `CN-A`…`CN-U` in
`../2026-09-16-containers-decisions.md`; probes
`docs/probes/swiftui-stack-algorithms.swift` (revision 4) and
`docs/probes/swiftui-overlay-presentation.swift` (arm names below are theirs);
record `docs/record/17-containers.md` (written by the lanes). Plan:
`../plans/2026-09-12-swiftui-alignment.md`, task 6, with the items tasks 2, 3,
4 and 5 handed to it.

**Status, 2026-09-16: design only, after critic round 1.** Nothing under
`Sources/` or `Tests/` is committed. The suite at `9e439cb` reads `Test run
with 1303 tests in 1 suite passed` under `--build-system native` after
`swift package clean`, 97 goldens, 66 guards. Every "measured" figure below
comes from a prototype that was applied, run and reverted in this worktree
(`CN-R`); the per-lane figures come from one **staged prototype** whose rulings
switch on per lane, run through the unfiltered suite and the pixel harness at
each stage. The critic's sixteen findings and their dispositions are at the end
of the decisions doc.

## 1. The task, and what it turns out to be

> Replace containers with SwiftUI-style algorithms. Audit Row, Column, Stack,
> Box, Spacer, ScrollView, List, and Deferred against HStack, VStack, ZStack,
> Spacer, ScrollView, List, and overlay/presentation patterns. Port stack,
> overlay and spacer algorithms directly to the new proposal system. Cover
> proposal propagation, explicit versus platform-default spacing, all nine
> Alignment positions, frame alignment, and scroll axes. Preserve the existing
> centred stack defaults only where probes confirm them.

Handed in: `SA-N` item 2 (`Spacer()`'s 8pt minimum), item 8 (single-child
priority pass-through); `MC-L`'s hole 4 and the one-node traps and a two
scroll views in one overlay test; `FR-E`/`FR-O`'s greedy finite and single-axis
infinite maximum and `FR-N`'s oversized child on the legacy frame; `FR-T`'s
`percent:` unit; `OM-`'s legacy overlay; CLAUDE.md's "unprobed kernel behaviour
that fails silently" list.

**What it turns out to be.** The probe shows the proposal kernel's stack is not
SwiftUI's in six independent ways (distribution order, lower-priority
reservation, non-spacer expansion, compression with a spacer, overflow
reporting, measure-versus-place), its spacer in four (default minimum, priority,
cross axis, infinite answer), its default spacing beside a spacer (per edge,
through wrappers), its `ZStack` and root in their placement, its overlay content
when several views share one, and its scroll view on its cross axis. It also
shows that `.aspectRatio` answers its child and treats ∞ as a concrete axis.
Those are ported (lanes 1–4). The legacy containers cannot be lowered onto the
kernel without converting every element beneath them (`SA-G`), so they are
audited, three divergences pinned with task 7 as owner, and the one local legacy
fix a single CSS node can express is taken (lane 5). The migration shape is
`CN-A`.

**Task 6 stays open** after these lanes: no legacy container is replaced.
`CN-T` proposes amended task text and moves the windowed proposal `List` to
task 7, whose closing condition needs it.

**Centred defaults.** Probed and confirmed: `HStack`/`VStack` centre on the
cross axis (A1/A2 `.center` at 10), `ZStack` centres (A3), `.overlay` and
`.background` centre (A6/A9), and an overlay's implicit `ZStack` is centred
whatever the modifier's alignment (K5g, K5h). EP-8's centred `Row`/`Column` and
`Stack`'s `.center` default therefore stay. Not confirmed, and changed: the
stack's 8pt default is not inserted at a spacer's zero-spacing edge (`CN-H`).

## 2. Evidence

- **Probes.** `swiftui-stack-algorithms.swift`, revision 4: about 210 arms in
  fourteen groups (S spacing by view kind, SP/SPB spacer, G/X distribution, Q
  second pass, A alignment/overlay/background, SC/SCG/SCG2 scroll views, R root,
  AR aspect ratio, K the critic round's walks, aspect-ratio branches, overlay
  content and `List`, Z `ZStack` placement). `swiftui-overlay-presentation.swift`:
  overlay clipping and paint order, presentations, background/overlay click
  order (P0–P6, H0–H3). Each header states every reading with the arms behind it
  and holds the whole output.
- **Staged prototype** (`CN-R`): every ruling's kernel and element change in one
  patch, gated per lane; stage 0 reproduces `9e439cb` (1311 = 1303 + 8 scratch
  tests, all green; 0 differing pixels in all twelve images). Earlier
  prototypes P1–P5 and the legacy prototypes are superseded where the staged one
  measured the same thing.
- **Pixel harness** (`CN-R`): twelve images through a real `Window` over
  `FakePlatformWindow`.

### Measured costs

Per lane, cumulative, against `9e439cb` (`CN-S` has bounding boxes and which
images are evidence for which lane):

| after lane | legacy images (9) | `preview-*` (each) | `small560-preview` | red existing tests |
|---|---|---|---|---|
| 1 | 0 | 155 248 (toggle 496×279) | 93 522 | 14 |
| 2 | 0 | 188 (toggle 168×95) | 64 199 | 18 |
| 3 | 0 | 188 | 64 199 | 18 (+1 sentinel artefact) |
| 4 | 0 | 1 109 (+ scroll border 856 → 520) | 65 449 | 30 (+1) |
| 5 | 0 | 1 109 | 65 449 | 32 (+1) |

Work (`CN-B`): the branching tree's 16 calls / 27 hits / 25 misses read
47/51/66 after lane 1, 44/50/63 after lanes 2–3, 46/48/66 after lanes 4–5.
Nested alternating stacks, depth 1–7: at most 8.2 leaf calls per leaf at a
finite root and 11.2 inside a scroll viewport (nil cross proposal), growing by a
bounded amount per level. Shaping: 2 → 4 `ShapingCache` misses per
`ProposalText` on a cold frame.

## 3. The audit

One row per legacy container. "Proposal counterpart" is what exists at
`9e439cb`; "after task 6" is this design.

| legacy | SwiftUI (probe) | legacy today (by reading, or pinned) | proposal counterpart after task 6 | verdict |
|---|---|---|---|---|
| `Row` | `HStack`: flexibility-ordered distribution (G1…G13), 8pt default spacing, none at a spacer's zero-spacing edge (S, SP3, K3), centred cross axis (A1) | CSS flex row: gap 0; centred (EP-8, confirmed); flex-shrink by base size; grows only by `flexGrow`; no spacer | `HStack` ports all of it (lanes 1, 3) | kept; gap-0 pinned (`CN-P` 1, owner task 7); compression and expansion are `FlexEngine`'s (goldens) |
| `Column` | `VStack`: as above on the other axis (G15, A2); text-edge vertical spacing font-derived (S) | as `Row`, column | `VStack` (lanes 1, 3); text-edge spacing not adopted (`CN-H`) | kept, as `Row` |
| `Stack` | `ZStack`: every child measured at the proposal and placed at the `ZStack`'s own size, aligned within the union of those answers (A5, A5n, X12, Q2, Z1–Z4), union size (A4), nine alignments (A3) | display `.stack`: child offered fit-content (ST-H); union size; nine alignments (`StackElementTests`) | `ZStack` (lane 4) | kept; fit-content offer pinned (`CN-P` 2, owner task 7) |
| `Box` | no container counterpart; a `Box` with a child is a CSS flex container that stretches (EP-8) | CSS flex row, stretch | none needed: `ZStack`/`HStack` + frame/padding/background | kept; nothing to port |
| `Spacer` | minimum 8 (SP1, K1), priority −∞ (SP8, X5, K2a), zero on its stack's cross axis through wrappers but not through a `ZStack` (SPB, K2b–K2e, K2a), ∞ at ∞ (contract E) | **no legacy `Spacer` exists** (plan note, `git grep` at `a15ec83`) | `Spacer` (lanes 1, 2; lane 3 for spacing beside it) | nothing to audit on the legacy path |
| `ScrollView` | offers nil on scrolling axes; answers `proposal ?? content` on those, content on the others (SC1/SC2/SC4); two children → centred default `VStack` (SC3); small content leading on one axis, centred on two (SCG2) | CSS viewport: cross axis from its parent (stretch/declared); one child; `List`'s only scroller | `ProposalScrollView` (lane 4); two-axis deferred (task 10) | kept; cross-axis pinned (`CN-P` 3, owner task 7) |
| `List` | **greedy** (K6): answers its proposal on each concrete axis and 0 on a nil axis (100×100 at 100×100, 0×0 at nil, 100×0 at 100×nil, 0×100 at nil×100, ∞×∞ at ∞×∞); in a windowless host no row is laid out (K6f) | windowed `Box`, uniform `rowHeight`, `ScrollContext`; answers by CSS | none | windowed proposal `List` → **task 7** (`CN-T`); SwiftUI `List` semantics → task 10 (`CN-Q`) |
| `Deferred` | **no layout counterpart, measured**: `.overlay` content is clipped by an ancestor clip (P1) and not hoisted above later siblings (P2; `.zIndex` within a `ZStack`, P3); a root's overlay is proposed the root's size (R3, R4); `.sheet`/`.popover` content is outside the presenting view's layout and render tree (P4, P5) | portal: no node, root layer, clip/offset reset | none; `.overlay`/`.background` content completed (lane 4) | deferred, task 7 (`CN-Q`) |
| legacy `.frame` | frame (frame-semantics probe) | `FR-C` lowering; `FR-E`/`FR-N`/`FR-O` divergences | kernel frame (`FR-A`) | single-child overflow fixed (lane 5, `CN-N`); axis-dependent items deferred (`CN-Q`) |
| legacy `.overlay` | overlay (A6–A11, K5) | not offered | `.overlay`/`.background(alignment:content:)` (lane 4) | deferred on the legacy path, task 7 |

**Nine alignments.** `ZStack` A3, `.overlay` A6 and `.background` A9 (three)
are pinned against the probe in lane 4; the frame's nine are `FR-C`'s (legacy,
`aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`) and the kernel's
(`aNativeFramePlacesItsChildAtTheRequestedAlignment`); the linear stacks' three
per axis are lane 3's.

## 4. The migration shape (`CN-A`)

Parity on the proposal path; no legacy container lowered; the root switch is
task 7's. Why, and what that costs: `CN-A`. What a task-7 root switch needs
first: `CN-A`'s prerequisite list and `CN-Q`. Task 6's status and the proposed
plan amendment: `CN-T`.

## 5. Public API

`MetalUILayout`:

```swift
/// SwiftUI's platform-default stack spacing and `Spacer` minimum on macOS
/// (probe S, SP1, K1). Rulings CN-C, CN-H.
public enum ProposalSpacing {
    public static let platformDefault: Double = 8
}

extension LayoutTree {
    // nil = per adjacent pair, 0 at a zero-spacing edge, else platformDefault
    // (CN-H's per-edge walk). The default stays 0 for kernel callers. NaN and
    // ±∞ still trap (SA-J).
    public func newNativeLinearStack(children: [LayoutNodeID], axis: ProposalStackAxis,
                                     spacing: Double? = 0,
                                     alignment: ProposalAlignment = .center) -> LayoutNodeID
    // nil minLength = ProposalSpacing.platformDefault (CN-C). Signature unchanged.
    public func newNativeSpacer(minLength: Double? = nil) -> LayoutNodeID
    // Measures at `proposal`, places the root centred in `container` at its
    // answer, in one run (CN-J).
    @discardableResult
    public func computeNativeLayout(root: LayoutNodeID, proposal: ProposedSize,
                                    centredIn container: LayoutRect) -> LayoutMeasurement
}
```

`LayoutPass.requestNativeLinearStack(children:axis:spacing:alignment:)` takes
`spacing: Double?` with the same default. `reset(generation:)` clears the
spacer marks (`CN-C`) and the parent record (`CN-L`).

`MetalUI`:

```swift
public enum VerticalAlignment: Sendable, Hashable { case top, center, bottom }
public enum HorizontalAlignment: Sendable, Hashable { case leading, center, trailing }

public struct HStack<Content: ProposalElementGroup>: Element {
    public var content: Content
    public var spacing: Pixels?                 // was Pixels
    public var alignment: VerticalAlignment     // was ProposalAlignment
    public init(alignment: VerticalAlignment = .center, spacing: Pixels? = nil,
                @ElementBuilder content: () -> Content)
    @available(*, deprecated, message: "Use init(alignment:spacing:content:) with a VerticalAlignment, in SwiftUI's argument order.")
    public init(spacing: Pixels, alignment: ProposalAlignment, @ElementBuilder content: () -> Content)
}
// VStack: the same with HorizontalAlignment.

/// Prepaints AND paints `background` before `content` (CN-K): the primary's
/// hitbox registers later and ranks above the background's (probe H1).
public struct BackgroundModifier<Content: ProposalElementGroup, Background: ProposalElementGroup>: Element {
    public var content: Content
    public var background: Background
    public var alignment: ProposalAlignment
}
extension BackgroundModifier: ProposalElementGroup {}   // as OverlayModifier
extension ProposalElementGroup {
    public func background<B: ProposalElementGroup>(alignment: ProposalAlignment = .center,
                                                    @ElementBuilder content: () -> B) -> BackgroundModifier<Self, B>
}

extension StyledElement {   // Box.swift, where percent: lives today
    public func width(fraction: Float) -> Self
    public func height(fraction: Float) -> Self
    public func flexBasis(fraction: Float) -> Self
    @available(*, deprecated, renamed: "width(fraction:)")     public func width(percent: Float) -> Self
    @available(*, deprecated, renamed: "height(fraction:)")    public func height(percent: Float) -> Self
    @available(*, deprecated, renamed: "flexBasis(fraction:)") public func flexBasis(percent: Float) -> Self
}
```

Internal: `ModifierLayer.isFrame` (`CN-N`); the kernel's spacer-axis marks
(`CN-C`), zero-spacing-edge walk (`CN-H`) and parent record (`CN-L`). **Two of
those are stored properties on `LayoutTree`, a public class read across a module
boundary: the lane that adds each runs `swift package clean` before its suite**
(`CN-R` reproduced the failure mode on the baseline). `HStack`/`VStack`'s stored
property types change on a public type; clean there too.

## 6. Lanes

Five, in order (`CN-U`). Each lane is written red first, runs the unfiltered
suite (`--build-system native` after `--build-tests`, after `swift package
clean` when a stored property changed), mutates each new test's named mutation
in this worktree after committing, and ends with the pixel comparison of
`CN-S` for its row. Test counts are design estimates; each lane re-takes them.
Every new SwiftUI claim cites a probe arm; no lane adds a probe claim without
extending the probe (with a control) first. Kernel tests are built from fixed,
clamp, half-width and echo leaves that print nothing and log their proposals;
arms whose SwiftUI figures are fractional (K5a 17.5, Z1 2.5) are pinned at the
kernel's rounded rect or rebuilt with integral sizes, and the test says which.

"Red before" is what the tree answers before the lane; the mutation is applied
after the lane commits and must redden the test named. "Existing tests that
change" is the staged prototype's red list for that stage minus the previous
stage's (compared by first recorded issue); the lane updates each to the probe's
number or re-derives it by hand, says which, and treats a red test outside its
list as a finding.

### Lane 1 — distribution

**Rulings:** `CN-B`, `CN-D`, `CN-E`'s second-pass clause, `CN-C`'s −∞
priority (and the proxies' `priority`), `CN-F`'s spacer clause.

**Source.** `Sources/MetalUILayout/LayoutTree.swift`:

- one private `solveLinearStack(_:axis:spacing:proposal:run:) -> (answers,
  proposals, gaps, size)` implementing `CN-B`, called by `measureNative`'s and
  `placeNative`'s `.linearStack` cases (~70 lines in the prototype);
  `stackMainAllocations`, `resolvedStackMainSize`, `spacerProposal`,
  `stackPlacementProposal` and `stackChildProposal` go;
- placement re-solves at `cross = measured cross` when the cross proposal is nil
  (`CN-E`); the cursor advances by the answers and the gaps;
- a private `stackPriority`: spacer −∞; `layoutPriority` its value;
  `overlayAttachment` its primary's; a single-child `linearStack`/`overlay` its
  child's; else 0. `nativeLayoutPriority` (the proxies' reader) returns it;
- `spacerLength` accepts ∞.

`Sources/MetalUILayout/ProposalLayout.swift`: the proxies' `priority` and
`isSpacer` doc comments state the new rule. `Tests/MetalUILayoutTests/ReferenceLinearStack.swift`
is rewritten to `CN-B` through public proxies only.

**New tests** — kernel ones in a new `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`.
Spacer arms that name `Spacer()` use `newNativeSpacer(minLength: 8)` here (the
nil default is lane 2's) and assert the main axis only (the cross mark is lane
2's).

| # | test | arms | red before because | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aStackServesItsLeastFlexibleChildFirst` | G1, G1r, X1, X3, X4 | equal shares: G1 reads a 50 / b 60 (110), not 40/60 | sort by flexibility descending; or no sort |
| 1.2 | `aLowerPriorityGroupKeepsItsMinimumsReserved` | G2, G2c, G14, X5 | G2 reads 80/20 (the ideal fits) | drop the lower-group minimum subtraction |
| 1.3 | `aGreedyChildTakesTheSurplusAheadOfASpacer` | G3, G5, G5b, G25 | a non-spacer never expands: G3's b reads 10 | give a bare spacer priority 0 (G5 moves) |
| 1.4 | `aStackWithASpacerStillCompressesItsOtherChildren` | G6, G6c | a stack with a spacer never compresses: 80 + 8 + 80 | skip distribution when a spacer is present |
| 1.5 | `aStackAnswersTheSumOfItsChildrensAnswers` | G9, G10, G12, G13, X13 | `min(natural, proposal)`: G9 reads 100 | clamp the total to the proposal |
| 1.6 | `aStackAtANilOrInfiniteMainProposalOffersItToEveryChild` | G7, G8, G19 | G7 reads 100 and G8 a finite total | treat nil as 0 in the distribution |
| 1.7 | `aSpacerHasTheLowestPriorityAndAnswersInfinityAtInfinity` | SP8, SP9, SP10, X6, X8 (main axis), contract E and E2 through a proxy | a spacer reads priority 0 and answers its minimum at ∞ | restore `spacerLength`'s `isFinite`; return 0 for a spacer in `stackPriority` |
| 1.8 | `aSingleChildStackPassesItsChildsPriorityThrough` | G11, G11c, K2a (priority half: a single-child `overlay` over a spacer), contract L3 (a custom layout reads 0) | reads 0 | delete the pass-through (G11); pass through at any child count (G11c) |
| 1.9 | `aStackPlacesAfterASecondPassAtItsOwnCrossSize` | Q1, Q1c, X10, X11, G17, G21 | Q1 places a at 10 wide | place with the first-pass answers |
| 1.10 | `aStackMeasuresItsCrossSizeAtItsAllocations` | Q3 | cross size from the nil-main measurement (60) | report cross size from the probe answers |
| 1.11 | `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI` (`Tests/MetalUITests/ContainerIntegrationTests.swift`, new) | G1, G2, G6 (with `Spacer(minLength: 8)`), G15 | as 1.1–1.4 | swap `HStack`'s axis in `NativeElements.swift`. **Measured at `9e439cb`, it reddens 11 tests besides this one**: `aForLoopInsideAProposalContainerPlacesEveryIterationInItsOwnSlot`, `anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`, `aProposalScrollViewForwardsItsHorizontalAxisToTheNativeViewport`, `aPublicHStackFormsAnAllProposalLayoutSubtreeAndPlacesItsSpacer`, `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`, `hStackDividesAConstrainedProposalAmongEqualPriorityFlexibleChildren`, `hStackHonoursHigherLayoutPriorityBeforeCompressingItsSibling`, `hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`, `layoutPriorityPreservesASpacersFlexibleExpansion`, `spacerMinimumLengthSurvivesAConstrainedStackProposal`, `theProposalModifiersAcceptWhatTheKernelAccepts` — the lane confirms this one joins them |
| 1.12 | `nestedStacksUnderAnUnspecifiedCrossProposalDoBoundedWork` (performance) | the `CN-B` nested tree at depth 3 inside a vertical viewport, and at depth 3 at a finite root | green on arrival for "bounded"; the literals are red (today 7 calls) | disable the measurement cache; probe every group, including groups of one |
| 1.13 | `aProposalTextInAStackIsShapedOncePerDistinctWidth` (performance, `MetalUITests`) | three `ProposalText`s in an `HStack`, a fresh `ShapingCache`, one cold frame | literals red (today 6 misses) | key the shaping cache on width rounded to an integer; shape at every probe without the cache |

Tests 1.12 and 1.13 assert literals **derived by hand before the run**; the
staged prototype read 72 calls (depth 3, viewport) / 51 calls (finite) and 12
misses; a derivation that disagrees is a finding (`CN-B`).

**Existing tests that change** (stage 1, 14): `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`
(re-derive by hand; prototype 47/51/66), `aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`
(its wrong-on-purpose 0 flips to 2, and a spacer's priority reads −∞),
`aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` (compares a
**vertical** tree too, closing record §09's "horizontal only"; spacer cross
extents excluded with contract probe E as the reason),
`aDifferentRootProposalReMeasuresAndMovesTheRects`,
`aLinearStackReadsPriorityThroughAnOverlayAttachment`,
`aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`aNativeLinearStackDividesConcreteSurplusBetweenSpacers`,
`aNativeNodeRegisteredTwiceIsNotRejected` (arm a's measure count; lane 4
replaces it), `aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified`,
`anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`,
`aResetTreeMeasuresItsNewRegistrationsFromScratch`,
`aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`, and
`measuringANativeTreeWritesNoRect` (157×38 → 157×91: an unmarked spacer claims
its cross proposal; lane 2 restores 38 — `CN-U`).

**Expected counts:** 1303 + 13 = **1316**; guards 66; goldens 97.
**Demo:** `CN-S` row 1 (preview 155 248 each, small 93 522; legacy 0, not
evidence).

### Lane 2 — spacer cross axis and minimum, infinite answers, aspect ratio

**Rulings:** the rest of `CN-C`, the rest of `CN-F`, `CN-G`.

**Source.** `LayoutTree.swift`: a stored `spacerAxes` record (clean before
testing), `markSpacerAxis` called by `newNativeLinearStack` for each child
(`CN-C`'s walk), `.spacer` measurement answers 0 on its marked cross axis,
`newNativeSpacer(nil)` stores `ProposalSpacing.platformDefault`, `reset` clears
the marks; `framedSize` loses `proposal.isFinite` and its doc comment's third
bullet is rewritten; `resolvedViewportDimension` accepts ∞; `.aspectRatio`
measures and places through an `aspectRatioProposal` that treats ∞ as concrete
and answers the child (`CN-G`), and `aspectRatioSize`'s intrinsic branch goes.
`NativeElements.swift`: `Spacer`'s doc.

**New tests:**

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 2.1 | `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis` | SP1, SP6, SPB1, SPB2, SPB5, SP13, SP14, SP18b, SP21, SP22, K1 (a spacer between two 16pt leaves stands in for the texts); SPB3, SPB4 outside a stack | default 0; the spacer claims the cross proposal (SP13 reads 100×50) | nil → 0; delete the marking |
| 2.2 | `theCrossAxisMarkReachesASpacerThroughEveryWrapperButAStack` | K2b, K2c, K2d, K2e, SP19, SP20, X8 (cross axis); K2a and SP18b as the stops | K2b's stack is 50 tall | stop the walk at `frame`; skip the overlay's content side (K2e moves); walk into an `overlay` node (K2a moves) |
| 2.3 | `anInfiniteProposalIsAnsweredWithInfinity` — replaces `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` | frame D12, viewport SC1 at inf×inf, G4 (`.frame(maxWidth: .infinity)` in a stack takes 180) | `FR-B`: the frame answers its child | restore `isFinite` in each of the two sites, one at a time |
| 2.4 | `aCustomLayoutPlacingAChildAtAnInfiniteProposalTraps` (exit test) | D12's recorded crash, reproduced by K4f's first run | green on arrival if checkpoint 3 already catches it — the lane first greps the `SA-J` trap tests and cites an existing arm instead if one places a custom child at ∞ | remove checkpoint 3's width term |
| 2.5 | `anAspectRatioAnswersItsChildsAnswerToTheRatioProposal` | AR1, AR2, AR3, AR4, K4, K4b, K4c, K4j | answers 500×281.25 for AR1 | answer the ratio size |
| 2.6 | `anAspectRatioTreatsInfinityAsAConcreteAxis` | K4d, K4e, K4f, K4g, K4h | K4d proposes the intrinsic-shaped size, not inf×inf | filter ∞ to nil in `aspectRatioProposal` |
| 2.7 | `aDefaultSpacerAndAGreedyFrameThroughTheElementAPI` (`ContainerIntegrationTests.swift`) | SP1 with `Spacer()`, G4 with `.frame(maxWidth: .infinity)` | SP1 reads 40; G4's b reads 20 | nil → 0 in `newNativeSpacer` |

**Existing tests that change** (stage 2 minus stage 1): newly red —
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` (replaced by 2.3),
`aNegativeAspectRatioIsAcceptedOnEveryProposedBranch` and
`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes` (**their child
becomes a proposal-echoing leaf**, as P8 measured `Color`; the rule is not
changed — `CN-G`'s diagnosis), `aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`; changed
again from lane 1 — `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`
(44/50/63), `aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`,
`aNativeLinearStackDividesConcreteSurplusBetweenSpacers`; green again —
`measuringANativeTreeWritesNoRect` (back to 157×38).

**Expected counts:** 1316 + 7 − 1 = **1322**. **Demo:** `CN-S` row 2 (preview
188 each, small 64 199).

### Lane 3 — platform-default spacing and typed stack alignments

**Rulings:** `CN-H`, `CN-I`.

**Source.** `LayoutTree.swift`: `spacing: Double?` on the stack node;
`zeroSpacingEdges(_:axis:)` and per-pair gaps in `solveLinearStack` (`CN-H`'s
walk). `Passes.swift`, `Frame.swift`: the registrar's signature. New
`Sources/MetalUI/StackAlignment.swift` (the two enums and their internal
`ProposalAlignment` mappings). `NativeElements.swift`: `HStack`/`VStack`
initializers and stored properties, the deprecated initializers.
`ProposalScrollView.swift`: the lowering passes nil. `Sources/MetalUIDemo/main.swift:977, 993`
and `NativeLayoutIntegrationTests.swift:1012`: argument order.

**New tests** (`ContainerIntegrationTests.swift` unless noted):

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 3.1 | `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (kernel and element halves) | SP2, SP3, SP7, G23, S rect\|rect both axes | the default is an explicit 8 applied beside a spacer: SP3 reads 56 | apply 8 beside spacers; default nil → 0 |
| 3.2 | `defaultSpacingBesideASpacerIsDecidedPerEdgeThroughItsWrappers` (kernel, `NativeStackDistributionTests.swift`) | K3 control, K3a–K3q (padding, frame, overlay primary, `layoutPriority`, `fixedSize`, `aspectRatio`, all-spacer and mixed `ZStack`, nested stack, overlay content, non-zero and one-edge padding) | K3a reads 56 | read `isNativeSpacer` instead of the walk (K3a, K3b, K3c, K3e, K3f, K3g move); treat padding as transparent whatever its inset (K3m, K3n move); walk into an overlay's content (K3i moves); OR instead of AND over a `ZStack`'s children (K3j moves) |
| 3.3 | `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer` | S control, SP4 | green on arrival for S control; SP4 reads 80 today too — so the test `#require`s 3.1's SP3 (40) and SP4 (80) to disagree | treat explicit spacing as default beside a spacer |
| 3.4 | `hStackAndVStackPlaceChildrenAtTheirTypedAlignments` | A1 ×3, A2 ×3 | does not compile (new API) | map `.top` to `.center` in `VerticalAlignment`'s mapping |
| 3.5 | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` | S text\|text (0 in SwiftUI) — a pin of MetalUI's rule with the probe's numbers in its doc (`CN-H`) | green on arrival (8 already); `#require`s the gap to differ from a `VStack(spacing: 0)` control | default 0 |

**Guards** (new `Tests/MetalUITests/ContainerCompileGuards.swift`, `typecheckFile`,
plain import — an external module's spellings, `SA-P`):

| # | guard | red before because | mutation (must redden once, in this worktree, after `swift build --build-system native --build-tests`) |
|---|---|---|---|
| G1 | `aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks` — `HStack(alignment: .leading) {…}` and `VStack(alignment: .top) {…}` both fail | both compile today (`ProposalAlignment`) | give `VerticalAlignment` a `leading` case |
| G2 | `theTypedStackInitializersCompileInSwiftUIsArgumentOrder` — `HStack(alignment: .top, spacing: nil)`, `VStack(alignment: .trailing, spacing: Pixels(4))`, `HStack {}` | none compiles today | swap the two parameters' order |
| G3 | `theSpacingFirstStackInitializersAreDeprecated` — `HStack(spacing: Pixels(8), alignment: .center) {}` compiles with exactly 2 deprecation diagnostics for the two stacks | compiles with 0 | remove one `@available` |

**Existing tests that change** (stage 3 minus stage 2): none. The prototype's
extra red `aNaNStackSpacingTraps` is its NaN sentinel for `nil` (`CN-R`); with
`Double?` it must stay green, and the lane checks that it does.

**Demo:** `CN-S` row 3 — measured identical to row 2; lane 3 has no pixel
evidence. **Expected counts:** 1322 + 5 = **1327**; guards **69**. The inert
row "`HStack`/`VStack`'s `alignment:` main-axis half" **stays**, re-worded to
name the deprecated initializer (`CN-I`);
`aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly` stays as the kernel's
pin.

### Lane 4 — root, `ZStack` placement, overlay and background content, duplicate registration, scroll axes

**Rulings:** `CN-J`, `CN-E`'s `ZStack` clause, `CN-K`, `CN-L`, `CN-M`, and
`MC-L`'s two-scroll-views item.

**Source.** `LayoutTree.swift`: `computeNativeLayout(root:proposal:centredIn:)`;
`.overlay` placement by `CN-E` (children at the bounds size, aligned in the
union at the origin); a stored parent record in every native registrar with
children, trapping per `CN-L`, cleared by `reset` — after 4.9's exit test lands
(clean before testing); `.scrollViewport` answers the content's size on the
non-scrolling axis. `Frame.swift`: `computeRootLayout` calls the centred entry
(its doc comment's "runs the flex engine" corrected). `NativeOverlayModifier.swift`:
zero overlay nodes → the primary's node; several → `requestNativeOverlay(children:
alignment: .center)` then the attachment. New `Sources/MetalUI/NativeBackgroundModifier.swift`
(`BackgroundModifier`, the `.background(alignment:content:)` extension; the same
lowering; **prepaints and paints the content before the primary**; content
numbered under `.child(of: id, at: -1)`). `ProposalScrollView.swift`: doc comment
for the lowering (SC3, default spacing).

**New tests** (`ContainerIntegrationTests.swift` unless noted):

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 4.1 | `aNativeRootIsCentredAtItsAnswer` | R1, R2, R control; R3, R4 (a root's overlay/background content proposed the root's size) | the root is stored at the full window, a stack at x 0 | place at the full rect |
| 4.2 | `severalViewsInAnOverlayOrBackgroundAreACentredZStackPositionedByTheAlignment` | A10, K5a (= K5b), K5g `.topLeading`, K5h `.background(.bottomTrailing)`, with a half-width child | traps at `NativeOverlayModifier.swift:73` — measured with `--filter` alone, never in the unfiltered suite (shape 13) | give the implicit `ZStack` the modifier's alignment (K5g moves) |
| 4.3 | `overlayAndBackgroundContentIsPlacedAtThePrimarysSize` | K5 control, K5d (an `HStack` re-solved at the primary's size), K5f, K5e; `.overlay` and `.background` halves, each with a proposal-sensitive (half-width) child | green on arrival for `.overlay` K5; `.background` API missing; `#require`s K5's leaf to differ from a control placed at its own answer | place the content at its own answer (critic finding 2's rule: K5 and K5d move) |
| 4.4 | `aZStackPlacesItsChildrenAtItsOwnSizeWithinTheirUnion` (kernel and element halves) | Z1, Z2, Z3, Z4, Q2, A5, A5n, X12 | Z1 places the half-width leaf at 30×10 | place at the parent's proposal (Z4 moves); centre in the bounds instead of the union (Z1 moves) |
| 4.5 | `anEmptyOverlayOrBackgroundLeavesThePrimaryAlone` | A11, A11b | traps (overlay); API missing (background) | register an attachment with a zero-size leaf in the empty slot, and `#require` no extra node |
| 4.6 | `aClickOverABackgroundAndItsPrimaryReachesThePrimary` (through a real `Window`, `onTap` on both) | overlay-presentation H1 (centre: primary; outside the primary: background), H2 as the control (overlay takes both) | API missing | prepaint the primary before the background |
| 4.7 | `aBackgroundIsProposedThePrimarysSizeAlignedAndPaintedBeneath` | A9 ×3; scene order | API missing | paint the content after the primary |
| 4.8 | `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` | `MC-P`'s mechanism (overlay primary-shape probe) applied to `.background` | API missing | number the background under the primary's cursor |
| 4.9 | `aNativeNodeRegisteredTwiceTraps` (exit test, both of the old pin's arms) — replaces `aNativeNodeRegisteredTwiceIsNotRejected`; plus a `reset` arm that must exit successfully | `MC-G` hole 4 (no SwiftUI spelling) | the process exits successfully today | delete the precondition; do not clear the record in `reset` (the reset arm traps) |
| 4.10 | `everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads` | A3 ×9, A4, A6 ×9 through `.overlay(alignment:)` | green on arrival (the kernel already agrees) — kept as the element-level nine-alignment pin because it is the probe's; `#require`s `.topLeading` and `.bottomTrailing` to disagree | swap `horizontalFactor` for `verticalFactor` in `.overlay` placement |
| 4.11 | `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis` | SC2, SC4, both axes | answers the proposal: SC2 reads 100×100 | answer the proposal on the cross axis |
| 4.12 | `aProposalScrollViewPlacesSmallContentAtTheLeadingEdgeOfItsScrollingAxis` | SCG2 `.vertical`, `.horizontal` | green on arrival; `#require`s the same 50×30 content in a 50×100 **`ZStack`** control to sit at y 35 while the vertical scroll view puts it at y 0 (A5's centring, not the parent's placement, is the disagreement) | centre the content |
| 4.13 | `aProposalScrollViewAnswersItsProposalOnItsScrollingAxis` | SC1 at nil, 100×100, inf×inf, both axes | inf×inf answered the content before lane 2; this lane pins the element path | answer the content at ∞ |
| 4.14 | `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis` — replaces `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing` and `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` | SC3 (b at (10, 38)) | the horizontal arm (stage 4) | lower horizontally for `.horizontal` |
| 4.15 | `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` | `MC-E`'s mechanism, `MC-L` | green on arrival by `MC-E`; a wheel on one must leave the other's offset 0, `#require`d non-zero on the first | key both `ScrollState`s on the modifier's id |

**Existing tests that change** (stage 4 minus stage 3): `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` (replaced by 4.14),
`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`,
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` (its bounds only;
its identity claim must stay), `aProposalLayoutContainerRendersThroughTheFramePipeline`,
`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`,
`spacerMinimumLengthSurvivesAConstrainedStackProposal` (moved by centring);
`fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal` (the root
`ZStack` now re-proposes its child (nil, 10), `CN-J`);
`aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`,
`aNativeOverlayPlacesEveryChildAtTheRequestedAlignment`,
`everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition` (kernel callers
placing a `ZStack` in bounds larger than its answer; rebuilt per `CN-E`'s
kernel-caller note so the nine stay distinct);
`aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal` again (46/48/66);
`aNativeNodeRegisteredTwiceIsNotRejected` (replaced by 4.9). Each is re-read as
"moved by centring", "moved by the `ZStack` rule" or "moved by the scroll cross
axis" before it is edited; a test moved by none is a finding.

**Expected counts:** 1327 + 15 − 3 = **1339**. **Demo:** `CN-S` row 4 (preview
1 109 each, small 65 449) — the lane records each moved rect.

### Lane 5 — the legacy path: single-child frame, `fraction:`, three divergence pins

**Rulings:** `CN-N`, `CN-O`, `CN-P`.

**Source.** `ModifiedElement.swift`: `ModifierLayer.isFrame`; in
`requestLayout`, a frame layer over exactly one child node gets
`display = .stack` and `justifyItems` from its horizontal alignment, before
`animated`. `FrameLayer.swift`: both overloads set `isFrame`; `FrameSpec`'s
table gains the row (the alignment mapping stays one `switch` over the nine
cases, critic finding 15 of task 4). `Box.swift`: `fraction:` methods,
deprecated `percent:`. Every `percent:` call in `Sources/` and `Tests/` (17 hits
today, doc comments included) moves or is re-worded.

**New tests** (`Tests/MetalUITests/FrameSizingTests.swift` for 5.1, 5.2, 5.6,
5.7; `ContainerIntegrationTests.swift` for 5.3–5.5; guard in
`ContainerCompileGuards.swift`):

| # | test | evidence | red before because | mutation |
|---|---|---|---|---|
| 5.1 | `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes` — replaces `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`; with and without `flexShrink(0)` | frame-semantics A5: (−70, −60) 200×160 | reads (0, 20) 60×160 | lower single-child frames as a flex row again |
| 5.2 | `aFractionSizeResolvesAgainstItsContainingBlock` — replaces `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock` | `FR-T`'s arms (150 in a 300pt row; x 75 in a column) | API missing | `fraction:` writes `.percent(fraction * 100)` |
| 5.3 | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` | S rect\|rect; `#require` the two disagree | green on arrival (after lane 3); a pin (`CN-P` 1) | `Row`/`Column` default gap 8 (22 tests redden, this one among them) |
| 5.4 | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | A5 (100×80) against a legacy `Stack` whose sizeless `Box` child reads (50, 40) 0×0 | green on arrival; a pin (`CN-P` 2) | set the legacy `Stack` **container's** `alignItems` and `justifyItems` to `.stretch` in `Stack.init` — measured: the child reads (0, 0) 100×80 and 7 tests redden (`CN-P`); this pin must be the 8th |
| 5.5 | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` | SC2 | green on arrival (after lane 4); a pin (`CN-P` 3) | lane 4's cross-axis line reverted |
| 5.6 | `anAbsolutelyPositionedChildInsideASingleChildLegacyFrameKeepsItsPlacement` | today's answer, taken before the lowering changes (`CN-N`'s open item); no SwiftUI claim | green on arrival by construction; a moved rect after the change is a finding | lower through `display: .stack` without carrying `position`'s containing block |
| 5.7 | `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` | today's answer, as 5.6 | as 5.6 | as 5.6, for the scroll region's bounds |
| G4 | `thePercentSizingModifiersAreDeprecatedRenamesOfFraction` (typecheckFile: exactly 3 deprecations naming `fraction:`) | `CN-O` | compiles with 0 | remove one `@available` |

**Existing tests that change** (stage 5 minus stage 4, measured with the
exactly-one lowering): `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`
(replaced by 5.1) and `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`
(to A5's rect; its clip and border claims stay); from the rename (not in the
prototype): `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`
(replaced by 5.2), `everyPublicModifierWritesItsOwnFieldAndOnlyThatField` and
`ModifierTests`' three percent rows. **Measured green** under the lowering, and
this lane's guard on the "exactly one node" clause:
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes`,
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` — the mutation
"lower every frame layer as a stack" must redden all three (it did, design
round).

**Demo:** `CN-S` row 5 (identical to row 4, measured); lane 5 has no pixel
evidence (`CN-S`). **Expected counts:** 1339 + 7 − 2 = **1344**; guards **70**;
goldens 97 (no file under `Sources/MetalUILayout/` except `LayoutTree.swift`
changes in any lane, and every lane runs the fixtures).

## 7. Order, and what each lane may assume

1 → 2 → 3 → 4 → 5, one agent at a time. Lane 2 assumes lane 1's
`solveLinearStack` and `stackPriority`; lane 3 assumes lane 2's spacer marks and
default; lane 4 assumes lane 1's second pass, lane 2's infinite answers and lane
3's default spacing (SC3's lowering); lane 5 assumes nothing from 1–4 except for
pins 5.3 and 5.5, which read the proposal side lanes 3 and 4 settled. A lane
that finds a probe arm contradicted by its implementation stops, re-runs the
arm, and amends the ruling in the decisions doc before continuing; it never
edits a probe's recorded output.

## 8. Deferrals

`CN-Q`, in full, with `CN-T` for task 6's own status and the `List` move. None
of them is silent: each is a row there with its reason and owner, and the Docs
phase carries each into CLAUDE.md's divergence or inert tables and the plan's
progress notes.

## 9. Divergences this task creates or leaves (numbers assigned at integration)

- `ProposalText` beside text in a `VStack`: 8 where SwiftUI's font-derived gap
  is 0 / 4.74 / 8.15 (`CN-H`, pin 3.5). Owner task 11.
- Legacy `Row`/`Column` gap 0 (`CN-P` 1, pin 5.3); legacy `Stack` fit-content
  offer (`CN-P` 2, pin 5.4); legacy `ScrollView` cross axis (`CN-P` 3, pin 5.5).
  Owner task 7.
- A two-member `Component` under a legacy `.frame` keeps the row lowering where
  SwiftUI frames each member (component-distribution G7; `CN-N`).
- A non-clickable proposal primary does not block a click to its background's
  content, where SwiftUI's does (overlay-presentation H3; `CN-K`). Owner task
  12.
- A `ZStack` placed by a kernel caller in bounds larger than its answer puts its
  union at the origin (`CN-E`); SwiftUI has no such placement.
- Retired by this task: divergence 36 (`FR-N`, the squeezed child) at lane 5;
  CLAUDE.md's four "unprobed kernel behaviour" bullets on spacers, expansion,
  compression and measure-versus-place at lanes 1–2; `SA-N` items 2, 3 and 8.
  **Not retired:** the inert row for stack alignment's main-axis half (`CN-I`).
- Deprecated, not divergent: the spacing-first stack initializers and
  `percent:` (+5 `@available(*, deprecated` hits).

## Appendix — prototype red lists

**Staged prototype** (`CN-R`), unfiltered suite, 1311 tests (1303 + 8 scratch),
clean build. Stage 0: all passed.

**Stage 1** (lane 1), 14 red, 53 issues: `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`,
`aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules`,
`aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects`,
`aDifferentRootProposalReMeasuresAndMovesTheRects`,
`aLinearStackReadsPriorityThroughAnOverlayAttachment`,
`aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`aNativeLinearStackDividesConcreteSurplusBetweenSpacers`,
`aNativeNodeRegisteredTwiceIsNotRejected`,
`aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified`,
`anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`,
`aResetTreeMeasuresItsNewRegistrationsFromScratch`,
`aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`,
`measuringANativeTreeWritesNoRect`.

**Stage 2** (lanes 1–2), 18 red, 53 issues: stage 1's list without
`measuringANativeTreeWritesNoRect`, plus
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity`,
`aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`,
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`.

**Stage 3** (lanes 1–3), 19 red, 55 issues: stage 2's plus
`aNaNStackSpacingTraps` (the NaN sentinel, not a lane change).

**Stage 4** (lanes 1–4), 31 red, 88 issues (the pin skipped as its exit-test
replacement would be): stage 3's without `aNativeNodeRegisteredTwiceIsNotRejected`,
plus `aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`,
`aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`,
`aNativeOverlayPlacesEveryChildAtTheRequestedAlignment`,
`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`,
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`,
`aProposalLayoutContainerRendersThroughTheFramePipeline`,
`everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition`,
`fixedSizeModifierWithholdsOnlyItsSelectedAxisFromTheChildProposal`,
`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`,
`spacerMinimumLengthSurvivesAConstrainedStackProposal`,
`vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`. No other test
tripped `CN-L`'s trap; the scratch `CN-L` exit tests (two traps, one `reset`
success) passed.

**Stage 5** (lanes 1–5), 33 red, 91 issues: stage 4's plus
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`,
`aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`.

**First staged run, `ZStack` clause at stage 1** (superseded, `CN-E`'s coupling
note): stage 1 read 28 red, 89 issues — the 14 above plus
`aNativeOverlayForwardsOneProposalMeasuresTheLargestChildAndCentresEachChild`,
`aNativeOverlayPlacesEveryChildAtTheRequestedAlignment`,
`aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`,
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
`chainedNativeFramesPreserveTheirDeclarationOrder`,
`everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition`,
`hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay`,
`nativeBackgroundWrapsTheResolvedOuterBoundsAndPaintsBeforeItsContent`,
`nativeClipMasksOverflowingContentToItsOuterFrame`,
`nativeOverlayIsMeasuredAgainstItsPrimaryAndDoesNotEnlargeIt`,
`onTapPaintsItsHoverOverlayOnlyWhenThePointerIsOverItsResolvedBounds`,
`onTapRegistersTheResolvedNativeBoundsAsAHittableTarget`,
`proposalLayoutFrameUsesTheTypedProposalWrapper`. At stage 4 (root centred) all
but the three kernel-caller tests were green again, and the two aspect-ratio
tests were red for `CN-G`'s reason instead.

**Mutations at stage 0:** `HStack` axis swapped, 11 red (test 1.11); legacy
`Stack` container stretched, 7 red (pin 5.4, `CN-P`).

**Legacy gap 8** (`CN-P`, design round): 22 red —
`aComponentInsideAComponentFlattensThroughBothLevels`,
`aComponentsContentFlattensIntoItsParent`,
`aComponentsPaddingWrapsEachTopLevelNode`,
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`aHiddenChildTakesNoSpace`, `aLegacyFixedFrameDoesNotShrinkAsAFlexItem`,
`aLegacyFrameClampsToItsMinimumAndMaximumWithoutGrowingIntoTheProposal`,
`aLegacyFrameProposesItsWidthToAMeasuredLeaf`,
`alignItemsAndAlignSelfBothReachTheEngine`,
`aModifierOnAComponentAppliesInTheOrderItIsWritten`,
`aModifierOnAComponentDistributesToEachTopLevelChild`,
`aNestedLayoutMatchesTheEngineRunDirectly`,
`aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds`,
`anExplicitAnyElementIsStillAcceptedAsAChild`,
`aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock`,
`chainedLegacyFramesAgreeWithSwiftUIsOrderingRules`,
`childrenAreRegisteredAndLaidOutInSourceOrder`,
`columnStacksOnTheAxisRowDoesNot`,
`legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`,
`modifierOrderChangesSizeAndPlacementAsSwiftUIDoes`,
`theContentNodeOverflowsTheViewport`,
`theSizingModifiersWriteTheirOwnElementsBoxRatherThanWrappingIt`.

**Legacy frame as a stack, every layer** (`CN-N`, design round): 5 red / 8
issues — `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`,
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`,
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes`.
