# Containers — design (plan task 6)

`feat/containers` from `9e439cb`. Rulings `CN-A`…`CN-S` in
`../2026-09-16-containers-decisions.md`; probe
`docs/probes/swiftui-stack-algorithms.swift` (arm names below are its); record
`docs/record/17-containers.md` (written by the lanes). Plan:
`../plans/2026-09-12-swiftui-alignment.md`, task 6, with the items tasks 2, 3,
4 and 5 handed to it.

**Status, 2026-09-16: design only.** Nothing under `Sources/` or `Tests/` is
committed. The suite at `9e439cb` reads `Test run with 1303 tests in 1 suite
passed` under `--build-system native`, 97 goldens, 66 guards. Every "measured"
figure below comes from a prototype that was applied, run and reverted in this
worktree (`CN-R`).

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
cross axis, infinite answer), its `ZStack` and root in their placement proposal,
and its scroll view on its cross axis. It also shows that `.aspectRatio` over a
fixed child answers the child, which the ported stack makes visible in the
preview. Those are ported (lanes 1–4). The legacy containers cannot be lowered
onto the kernel without converting every element beneath them (`SA-G`), so they
are audited, three divergences pinned, and the one local legacy fix a single
CSS node can express is taken (lane 5). The migration shape is `CN-A`.

**Centred defaults.** Probed and confirmed: `HStack`/`VStack` centre on the
cross axis (A1/A2 `.center` at 10), `ZStack` centres (A3), `.overlay` and
`.background` centre (A6/A9). EP-8's centred `Row`/`Column` and `Stack`'s
`.center` default therefore stay. Not confirmed, and changed: the stack's 8pt
default is not inserted beside a spacer (`CN-H`).

## 2. Evidence

- **Probe** — `docs/probes/swiftui-stack-algorithms.swift`, about 150 arms in twelve
  groups (S spacing by view kind, SP/SPB spacer, G/X distribution, Q second
  pass, A alignment/overlay/background, SC/SCG/SCG2 scroll views, R root,
  AR aspect ratio). Its header states every reading with the arms behind it and
  holds the whole output.
- **Kernel prototypes** P1–P5 and legacy prototypes (`CN-R`), unfiltered suite
  each.
- **Pixel harness** (`CN-R`): twelve images through a real `Window` over
  `FakePlatformWindow`.

### Measured costs

Prototype P5 (all of `CN-B`–`CN-G`, `CN-J`, `CN-M`'s cross axis) against
`9e439cb`:

| image | differing pixels | what moved |
|---|---|---|
| `default-{light,dark}-{f0,f3}`, `modal-*`, `animation-*`, `small560-default-light` | 0, scene identical | — |
| `preview-light`, `preview-dark` | 1 109 each, bbox (264, 212)–(939, 865) | rect 8, the scroll view's border, 856 → 520 wide (SC2); rects 12–13, `PreviewToggle`, 168×94 → 168×95 at y 846 → 845 (AR1) |
| `small560-preview-light` | 64 945 | 13 of 16 rects: the padded panel 560×594 at (0, −17) → 696×604 at (−68, −22); every child 68pt left; the 520pt rects and 528pt bottom row overflow the 392pt column instead of being squeezed (G9, X13, A4); the toggle 123×69 → 168×95 (AR1, `CN-B` does not compress a rigid child) |

Without `CN-G`, the preview toggle grows to 496×279 (155 248 pixels, P1). Work:
the branching tree's 16 calls / 27 hits / 25 misses read 47 / 52 / 66 under P1;
alternating nested stacks, depth 1–7, 1 → 9 leaf calls per leaf, linear in node
count (`CN-B`).

## 3. The audit

One row per legacy container. "Proposal counterpart" is what exists at
`9e439cb`; "after task 6" is this design.

| legacy | SwiftUI (probe) | legacy today (by reading, or pinned) | proposal counterpart after task 6 | verdict |
|---|---|---|---|---|
| `Row` | `HStack`: flexibility-ordered distribution (G1…G13), 8pt default spacing (S), centred cross axis (A1) | CSS flex row: gap 0; centred (EP-8, confirmed); flex-shrink by base size; grows only by `flexGrow`; no spacer | `HStack` ports all of it (lanes 1, 2) | kept; gap-0 pinned (`CN-P` 1); compression and expansion are `FlexEngine`'s (goldens) |
| `Column` | `VStack`: as above on the other axis (G15, A2); text-edge vertical spacing font-derived (S) | as `Row`, column | `VStack` (lanes 1, 2); text-edge spacing not adopted (`CN-H`) | kept, as `Row` |
| `Stack` | `ZStack`: every child offered the proposal, placed at `proposal ?? own size` (A5, A5n, X12), union size (A4), nine alignments (A3) | display `.stack`: child offered fit-content (ST-H); union size; nine alignments (`StackElementTests`) | `ZStack` (lane 1 placement; lane 3 element pins) | kept; fit-content offer pinned (`CN-P` 2) |
| `Box` | no container counterpart; a `Box` with a child is a CSS flex container that stretches (EP-8) | CSS flex row, stretch | none needed: `ZStack`/`HStack` + frame/padding/background | kept; nothing to port |
| `Spacer` | minimum 8, priority −∞, zero cross size in a stack, ∞ at ∞ (SP, SPB, X6, X8) | **no legacy `Spacer` exists** (plan note, `git grep` at `a15ec83`) | `Spacer` (lane 1; lane 2 for spacing beside it) | nothing to audit on the legacy path |
| `ScrollView` | offers nil on scrolling axes; answers `proposal ?? content` on those, content on the others (SC1/SC2/SC4); two children → centred default `VStack` (SC3); small content leading on one axis, centred on two (SCG2) | CSS viewport: cross axis from its parent (stretch/declared); one child; `List`'s only scroller | `ProposalScrollView` (lane 4); two-axis deferred (task 10) | kept; cross-axis pinned (`CN-P` 3) |
| `List` | AppKit table; outside the layout protocol | windowed `Box`, uniform `rowHeight`, `ScrollContext` | none | deferred, task 10 (`CN-Q`) |
| `Deferred` | no layout counterpart; nearest patterns are `.overlay` on a root and presentations | portal: no node, root layer, clip/offset reset | none; `.overlay`/`.background` content completed (lane 3) | deferred, task 7 (`CN-Q`) |
| legacy `.frame` | frame (frame-semantics probe) | `FR-C` lowering; `FR-E`/`FR-N`/`FR-O` divergences | kernel frame (`FR-A`) | single-child overflow fixed (lane 5, `CN-N`); axis-dependent items deferred (`CN-Q`) |
| legacy `.overlay` | overlay (A6–A11) | not offered | `.overlay`/`.background(alignment:content:)` (lane 3) | deferred on the legacy path, task 7 |

**Nine alignments.** `ZStack` A3, `.overlay` A6 and `.background` A9 (three)
are pinned against the probe in lane 3; the frame's nine are `FR-C`'s (legacy,
`aLegacyFramePlacesItsChildAtEachOfTheNineAlignments`) and the kernel's
(`aNativeFramePlacesItsChildAtTheRequestedAlignment`); the linear stacks' three
per axis are lane 2's.

## 4. The migration shape (`CN-A`)

Parity on the proposal path; no legacy container lowered; the root switch is
task 7's. Why, and what that costs: `CN-A`. What a task-7 root switch needs
first: `CN-A`'s prerequisite list and `CN-Q`.

## 5. Public API

`MetalUILayout`:

```swift
/// SwiftUI's platform-default stack spacing and `Spacer` minimum on macOS
/// (probe S, SP1). Ruling CN-C, CN-H.
public enum ProposalSpacing {
    public static let platformDefault: Double = 8
}

extension LayoutTree {
    // nil = platform default per adjacent pair, 0 beside a spacer (CN-H).
    // The default stays 0 for kernel callers.
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
`spacing: Double?` with the same default.

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
(`CN-C`); the kernel's parent record (`CN-L`). `HStack`/`VStack`'s stored
property types change on a public type across a module boundary only inside
`MetalUI`; run `swift package clean` before testing anyway (CLAUDE.md).

## 6. Lanes

Five, in order. Each lane is written red first, runs the unfiltered suite
(`--build-system native` after `--build-tests`), mutates each new test's named
mutation in this worktree after committing, and ends with the pixel comparison
of `CN-S` for its row. Test counts are design estimates; each lane re-takes
them. Every new SwiftUI claim cites a probe arm; no lane adds a probe claim
without extending the probe (with a control) first.

### Lane 1 — the kernel's stack, spacer, `ZStack` placement, infinite answers and aspect ratio

**Rulings:** `CN-B`, `CN-C` (minus spacing, which is lane 2's), `CN-D`, `CN-E`,
`CN-F`, `CN-G`.

**Source.** `Sources/MetalUILayout/LayoutTree.swift`:

- one private `solveLinearStack(_:axis:spacing:proposal:run:) -> (answers,
  proposals, size)` implementing `CN-B`, called by `measureNative`'s and
  `placeNative`'s `.linearStack` cases (the prototype is ~90 lines);
  `stackMainAllocations`, `resolvedStackMainSize`, `spacerProposal`,
  `stackPlacementProposal` and `stackChildProposal` go;
- placement re-solves at `cross = measured cross` when the cross proposal is nil
  (`CN-E`); the cursor advances by the answers and the spacing;
- `.overlay` placement offers `proposal ?? own size` per axis (`CN-E`);
- `.spacer` answers 0 on its marking stack's cross axis; `newNativeLinearStack`
  marks (`CN-C`); `spacerLength` and `resolvedViewportDimension` accept ∞;
  `newNativeSpacer(nil)` stores `ProposalSpacing.platformDefault`;
- `framedSize` loses `proposal.isFinite` (`CN-F`) and its doc comment's third
  bullet is rewritten;
- `nativeLayoutPriority` gains the single-child `linearStack`/`overlay` case,
  and the stack reads a bare spacer as −∞ (`CN-C`, `CN-D`);
- `.aspectRatio` answers and places at its child's answer (`CN-G`); the lane
  first reproduces `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`'s
  SIGTRAP, names the checkpoint, and fixes the rule so the test stays green;
- `reset(generation:)` clears the spacer marks.

`Sources/MetalUILayout/ProposalLayout.swift`: the proxies' `priority` and
`isSpacer` doc comments state the new rule. `Sources/MetalUI/NativeElements.swift`:
`Spacer`'s doc. `Tests/MetalUILayoutTests/ReferenceLinearStack.swift` is rewritten
to `CN-B` through public proxies only.

**New tests** — kernel ones in a new `Tests/MetalUILayoutTests/NativeStackDistributionTests.swift`,
built from fixed and clamp leaves that print nothing and log their proposals.
"Red before" is what `9e439cb` answers; the mutation is applied after the lane
commits and must redden the test named.

| # | test | arms | red before because | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aStackServesItsLeastFlexibleChildFirst` | G1, G1r, X1, X3, X4 | equal shares: G1 reads a 50 / b 60 (110), not 40/60 | sort by flexibility descending; or no sort |
| 1.2 | `aLowerPriorityGroupKeepsItsMinimumsReserved` | G2, G2c, G14, X5 | G2 reads 80/20 (the ideal fits) | drop the lower-group minimum subtraction |
| 1.3 | `aGreedyChildTakesTheSurplusAheadOfASpacer` | G3, G4, G5, G5b, G25 | a non-spacer never expands: G3's b reads 10 | give a bare spacer priority 0 (G5 moves); restore `FR-B`'s `isFinite` (G4's frame is rigid) |
| 1.4 | `aStackWithASpacerStillCompressesItsOtherChildren` | G6, G6c | a stack with a spacer never compresses: 80 + 8 + 80 | skip distribution when a spacer is present |
| 1.5 | `aStackAnswersTheSumOfItsChildrensAnswers` | G9, G10, G12, G13, X13 | `min(natural, proposal)`: G9 reads 100 | clamp the total to the proposal |
| 1.6 | `aStackAtANilOrInfiniteMainProposalOffersItToEveryChild` | G7, G8, G19 | G7 reads 100 (spacer 0) and G8 a finite total | treat nil as 0 in the distribution |
| 1.7 | `aSpacerDefaultsToEightAndAnswersZeroOnItsStacksCrossAxis` | SP1, SP6, SPB1, SPB2, SPB5, SP13, SP14, SP18b, SP21, SP22; SPB3, SPB4 outside a stack | default 0; the spacer claims the cross proposal (SP13 reads 100×50) | nil → 0; delete the marking; stop the marking walk at `frame` |
| 1.8 | `aSpacersPriorityAndFlexibilityThroughFramePaddingAndOverlay` | SP8, SP9, SP10, SP19, SP20, X6, X8 | SP20's padded spacer is rigid (size 50) | clamp a spacer's answer at ∞ to its minimum (SP20 moves); mark through `padding` as a bare spacer for priority (SP20's b moves) |
| 1.9 | `aSingleChildStackPassesItsChildsPriorityThrough` | G11, G11c; a single-child `overlay`; a single-child custom layout reads 0 (contract L3) | reads 0 | delete the pass-through (G11); pass through at any child count (G11c) |
| 1.10 | `aStackPlacesAfterASecondPassAtItsOwnCrossSize` | Q1, Q1c, X10, X11, G17, G21 | Q1 places a at 10 wide | place with the first-pass answers |
| 1.11 | `aStackMeasuresItsCrossSizeAtItsAllocations` | Q3 | cross size from the nil-main measurement (60) | report cross size from the probe answers |
| 1.12 | `aZStackPlacesItsChildrenAtItsOwnSizeOnAnUnspecifiedAxis` | A5, A5n, X12, Q2 | A5n places a at 10×10 | offer the parent's proposal at placement |
| 1.13 | `anInfiniteProposalIsAnsweredWithInfinity` — replaces `aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity` | frame D12, spacer (contract E), viewport SC1 at inf×inf | `FR-B`: the frame answers its child | restore `isFinite` in each of the three sites, one at a time |
| 1.14 | `aCustomLayoutPlacingAChildAtAnInfiniteProposalTraps` (exit test) | D12's recorded crash | green on arrival if checkpoint 3 already catches it — the lane first greps the `SA-J` trap tests and cites an existing arm instead if one places a custom child at ∞ | remove checkpoint 3's width term |
| 1.15 | `anAspectRatioAnswersItsChildsAnswerToTheRatioProposal` | AR1, AR2, AR3, AR4 | answers 500×281.25 for AR1 | answer the ratio size |
| 1.16 | `hStackAndVStackDistributeAsTheProbeReadsThroughTheElementAPI` (`Tests/MetalUITests/ContainerIntegrationTests.swift`, new) | G1, G2, G4 (`.frame(maxWidth: .infinity)`), G6 with a real `Spacer()`, G15 | as 1.1–1.4 | swap `HStack`'s axis in `NativeElements.swift` (only this test sees the element path) |

**Existing tests that change** (named by prototype P1/P2/P5; the lane that
reddens one updates it to the probe's number or re-derives it by hand, and says
which). Lane 1: `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`
(re-derive the literals by hand before running, `SA-M`),
`aCustomLayoutReadsPriorityAndSpacernessWithTheBuiltInStacksRules` (its
wrong-on-purpose 0 flips to 2, and a spacer's priority reads −∞),
`aCustomLayoutReimplementingTheLinearStackMatchesTheBuiltInRects` (compares a
**vertical** tree too, closing record §09's "horizontal only"; spacer cross
extents are excluded from the comparison with contract probe E as the reason: a
custom layout's spacer is not axis-aware in SwiftUI either),
`aDifferentRootProposalReMeasuresAndMovesTheRects`,
`aResetTreeMeasuresItsNewRegistrationsFromScratch`,
`aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`,
`aLinearStackReadsPriorityThroughAnOverlayAttachment`,
`aNativeHorizontalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`aNativeVerticalStackForwardsItsCrossProposalMeasuresAndPlacesInOrder`,
`aNativeLinearStackDividesConcreteSurplusBetweenSpacers`,
`anIdealFrameWidthBecomesItsOuterWidthWhenTheAxisIsUnspecified`,
`anIdealFrameHeightBecomesItsOuterHeightWhenTheAxisIsUnspecified`,
`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`,
`aNativeNodeRegisteredTwiceIsNotRejected` (arm a's measure count; lane 3
replaces it), and `aNegativeAspectRatioIsAcceptedOnEveryProposedBranch` (must
stay green, see Source). Possibly lane 1 or 4:
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` (red under P5,
not under P2).

**Expected counts:** 1303 + 16 − 1 = **1318**; guards 66; goldens 97.
**Demo:** `CN-S` row 1. The preview's 188 pixels are the harness's own
positive control for a kernel change; the legacy zeros need none beyond it,
because no legacy image contains a native node — the lane states that, and
checks it by grepping `demoContent()` for proposal types.

### Lane 2 — platform-default spacing and typed stack alignments

**Rulings:** `CN-H`, `CN-I`, and `CN-C`'s spacing clause.

**Source.** `LayoutTree.swift`: `spacing: Double?` on the stack node; per-pair
gaps in `solveLinearStack` (nil → 0 beside `isNativeSpacer`, else
`ProposalSpacing.platformDefault`). `Passes.swift`: the registrar's signature.
New `Sources/MetalUI/StackAlignment.swift` (the two enums and their internal
`ProposalAlignment` mappings). `NativeElements.swift`: `HStack`/`VStack`
initializers and stored properties, the deprecated initializers.
`ProposalScrollView.swift`: the lowering passes nil. `Sources/MetalUIDemo/main.swift:977, 993`
and `NativeLayoutIntegrationTests.swift:1012`: argument order.

**New tests** (`ContainerIntegrationTests.swift` unless noted):

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 2.1 | `aStackWithoutSpacingPutsEightBetweenViewsAndNothingBesideASpacer` (kernel and element halves) | SP2, SP3, SP7, G23, S rect\|rect both axes | the default is an explicit 8 applied beside a spacer: SP3 reads 56 | apply 8 beside spacers; default nil → 0 |
| 2.2 | `explicitStackSpacingIsUsedForEveryGapIncludingBesideASpacer` | S control, SP4 | green on arrival for S control; SP4 reads 80 today too — so the test `#require`s 2.1's SP3 (40) and SP4 (80) to disagree | treat explicit spacing as default beside a spacer |
| 2.3 | `hStackAndVStackPlaceChildrenAtTheirTypedAlignments` | A1 ×3, A2 ×3 | does not compile (new API) | map `.top` to `.center` in `VerticalAlignment`'s mapping |
| 2.4 | `aProposalTextStackUsesEightWhereSwiftUIUsesFontSpacing` | S text\|text (0 in SwiftUI) — a pin of MetalUI's rule with the probe's numbers in its doc (`CN-H`) | green on arrival (8 already); `#require`s the gap to differ from a `VStack(spacing: 0)` control | default 0 |

**Guards** (new `Tests/MetalUITests/ContainerCompileGuards.swift`, `typecheckFile`,
plain import — an external module's spellings, `SA-P`):

| # | guard | red before because | mutation (must redden once, in this worktree, after `swift build --build-system native --build-tests`) |
|---|---|---|---|
| G1 | `aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks` — `HStack(alignment: .leading) {…}` and `VStack(alignment: .top) {…}` both fail | both compile today (`ProposalAlignment`) | give `VerticalAlignment` a `leading` case |
| G2 | `theTypedStackInitializersCompileInSwiftUIsArgumentOrder` — `HStack(alignment: .top, spacing: nil)`, `VStack(alignment: .trailing, spacing: Pixels(4))`, `HStack {}` | none compiles today | swap the two parameters' order |
| G3 | `theSpacingFirstStackInitializersAreDeprecated` — `HStack(spacing: Pixels(8), alignment: .center) {}` compiles with exactly 2 deprecation diagnostics for the two stacks | compiles with 0 | remove one `@available` |

**Demo:** `CN-S` row 2 (0 additional; the preview spells `HStack {}` between two
rects and explicit spacing elsewhere). **Expected counts:** 1318 + 4 + 3 =
**1325**; guards **69**. The inert-table row "`HStack`/`VStack`'s `alignment:`
main-axis half" becomes a compile error at the element level (Docs phase);
`aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly` stays as the kernel's pin.

### Lane 3 — root placement, overlay and background content, `ZStack` element pins, duplicate registration

**Rulings:** `CN-J`, `CN-K`, `CN-L`, and the element half of `CN-E`'s `ZStack`.

**Source.** `LayoutTree.swift`: `computeNativeLayout(root:proposal:centredIn:)`;
the native registrars' parent record and trap (`CN-L`) — after 3.6's exit test
lands. `Frame.swift`: `computeRootLayout` calls it (its doc comment's "runs the
flex engine" corrected). `NativeOverlayModifier.swift`: zero overlay nodes → the
primary's node; several → `requestNativeOverlay(children:alignment:)` then the
attachment. New `Sources/MetalUI/NativeBackgroundModifier.swift`
(`BackgroundModifier`, the `.background(alignment:content:)` extension; paints
the secondary before the primary; content numbered under
`.child(of: id, at: -1)`).

**New tests** (`ContainerIntegrationTests.swift` unless noted):

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 3.1 | `aNativeRootIsCentredAtItsAnswer` | R1, R2, R control | the root is stored at the full window, a stack at x 0 | place at the full rect |
| 3.2 | `anOverlayOfSeveralViewsIsAZStackWithTheOverlaysAlignment` | A10 | traps at `NativeOverlayModifier.swift:73` — measured with `--filter` alone, never in the unfiltered suite (shape 13) | lower to a `.center` `ZStack` whatever the alignment |
| 3.3 | `anEmptyOverlayOrBackgroundLeavesThePrimaryAlone` | A11, A11b | traps (overlay); API missing (background) | register an attachment with a zero-size leaf in the empty slot, and `#require` no extra node |
| 3.4 | `aBackgroundWithContentIsProposedThePrimarysSizeAlignedAndPaintedBeneath` | A9 ×3; scene order | API missing | paint the secondary after the primary; offer the parent's proposal |
| 3.5 | `aBackgroundsContentKeepsItsStateWhenThePrimaryChangesShape` | `MC-P`'s mechanism (overlay primary-shape probe) applied to `.background` | API missing | number the background under the primary's cursor |
| 3.6 | `aNativeNodeRegisteredTwiceTraps` (exit test, both of the old pin's arms) — replaces `aNativeNodeRegisteredTwiceIsNotRejected` | `MC-G` hole 4 (no SwiftUI spelling) | the process exits successfully today: the exit test fails on `.failure` expected | delete the precondition |
| 3.7 | `everyZStackAndOverlayAlignmentPlacesAndSizesAsTheProbeReads` | A3 ×9, A4, A6 ×9 through `.overlay(alignment:)` | green on arrival (the kernel already agrees) — kept as the element-level nine-alignment pin because it is the probe's; `#require`s `.topLeading` and `.bottomTrailing` to disagree | swap `horizontalFactor` for `verticalFactor` in `.overlay` placement |

**Existing tests that change** (root, P2): `aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`,
`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`,
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed` (its bounds only;
its identity claim must stay),
`aProposalLayoutContainerRendersThroughTheFramePipeline`,
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`,
`spacerMinimumLengthSurvivesAConstrainedStackProposal`. Each is re-read as
"moved by centring" or "moved by lane 1" before it is edited; a test moved by
neither is a finding.

**Demo:** `CN-S` row 3. **Expected counts:** 1325 + 7 − 1 = **1331**.

### Lane 4 — scroll axes

**Ruling:** `CN-M`, and `MC-L`'s two-scroll-views item.

**Source.** `LayoutTree.swift`: `.scrollViewport` answers the content's size on
the non-scrolling axis. `ProposalScrollView.swift`: doc comment for the lowering
(its "8pt gap" sentence cites SC3, and says default spacing, `CN-H`).

**New tests** (`ContainerIntegrationTests.swift`):

| # | test | arms | red before because | mutation |
|---|---|---|---|---|
| 4.1 | `aProposalScrollViewAnswersItsContentOnItsNonScrollingAxis` | SC2, SC4, both axes | answers the proposal: SC2 reads 100×100 | answer the proposal on the cross axis |
| 4.2 | `aProposalScrollViewAnswersItsProposalOnItsScrollingAxis` | SC1 at nil, 100×100, inf×inf, both axes | inf×inf answers the content (lane 1 changed it; this lane pins the element path) | answer the content at ∞ |
| 4.3 | `aProposalScrollViewPlacesSmallContentAtTheLeadingEdgeOfItsScrollingAxis` | SCG2 `.vertical`, `.horizontal` | green on arrival; `#require`s the vertical and horizontal arms to place differently in a square host | centre the content |
| 4.4 | `aProposalScrollViewsDirectChildrenAreACentredDefaultSpacedVStackOnEitherAxis` — replaces `aProposalScrollViewStacksDirectChildrenWithSwiftUIsDefaultSpacing` and `aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically` | SC3 (b at (10, 38)) | the horizontal arm (P5) | lower horizontally for `.horizontal` |
| 4.5 | `twoProposalScrollViewsInOneOverlayKeepSeparateOffsets` | `MC-E`'s mechanism, `MC-L` | green on arrival by `MC-E`; a wheel on one must leave the other's offset 0, `#require`d non-zero on the first | key both `ScrollState`s on the modifier's id |

**Demo:** `CN-S` row 4: preview 1 109 pixels (the 856 → 520 border) — the lane
records each moved rect. **Expected counts:** 1331 + 5 − 2 = **1334**.

### Lane 5 — the legacy path: single-child frame, `fraction:`, three divergence pins

**Rulings:** `CN-N`, `CN-O`, `CN-P`.

**Source.** `ModifiedElement.swift`: `ModifierLayer.isFrame`; in
`requestLayout`, a frame layer over exactly one child node gets
`display = .stack`, `alignItems`/`justifyItems` from its alignment, before
`animated`. `FrameLayer.swift`: `FrameSpec` keeps the alignment so the stack
mapping is one `switch` over the nine cases (critic finding 15's rule), the
table gains the row. `Box.swift`: `fraction:` methods, deprecated `percent:`.
Every `percent:` call in `Sources/` and `Tests/` (17 hits today, doc comments
included) moves or is re-worded.

**New tests** (`Tests/MetalUITests/FrameSizingTests.swift` for 5.1/5.2,
`ContainerIntegrationTests.swift` for 5.3–5.5, guards in
`ContainerCompileGuards.swift`):

| # | test | evidence | red before because | mutation |
|---|---|---|---|---|
| 5.1 | `aSingleChildLegacyFrameOverflowsAnOversizedChildOnBothAxes` — replaces `aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`; with and without `flexShrink(0)` | frame-semantics A5: (−70, −60) 200×160 | reads (0, 20) 60×160 | lower single-child frames as a flex row again |
| 5.2 | `aFractionSizeResolvesAgainstItsContainingBlock` — replaces `aPercentageSizeTakesAFractionAndResolvesAgainstItsContainingBlock` | `FR-T`'s arms (150 in a 300pt row; x 75 in a column) | API missing | `fraction:` writes `.percent(fraction * 100)` |
| 5.3 | `aLegacyRowAndColumnDefaultToNoSpacingWhereHStackAndVStackDefaultToEight` | S rect\|rect; `#require` the two disagree | green on arrival (after lane 2); a pin (`CN-P` 1) | `Row`/`Column` default gap 8 (22 tests redden, this one among them) |
| 5.4 | `aLegacyStackOffersFitContentWhereAZStackOffersItsProposal` | A5 (100×80) against a legacy `Stack` whose flexible child reads its content size | green on arrival; a pin (`CN-P` 2) | give the legacy `Stack`'s items `alignSelf .stretch` and `justifyItems .stretch` |
| 5.5 | `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents` | SC2 | green on arrival (after lane 4); a pin (`CN-P` 3) | lane 4's cross-axis line reverted |
| G4 | `thePercentSizingModifiersAreDeprecatedRenamesOfFraction` (typecheckFile: exactly 3 deprecations naming `fraction:`) | `CN-O` | compiles with 0 | remove one `@available` |

**Existing tests that change:** `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`
(to A5's rect; its clip and border claims stay), `everyPublicModifierWritesItsOwnFieldAndOnlyThatField`
and `ModifierTests`' three percent rows (to `fraction:`). **Must stay green**,
and are this lane's guard on the "exactly one node" clause:
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes`,
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` — the mutation
"lower every frame layer as a stack" must redden all three (it did, P-legacy).

**Demo:** `CN-S` row 5 (no demo site uses a legacy `.frame` or `percent:`); the
instrument for its zeros is 5.1's mutation applied to a scratch demo site, or
the lane states why the legacy images cannot see this change. **Expected
counts:** 1334 + 5 + 1 − 2 = **1338**; guards **70**; goldens 97 (no file under
`Sources/MetalUILayout/` except `LayoutTree.swift` changes in any lane, and
every lane runs the fixtures).

## 7. Order, and what each lane may assume

1 → 2 → 3 → 4 → 5, one agent at a time. Lane 2 assumes lane 1's
`solveLinearStack` and spacer identity; lane 3 assumes lane 1's `.overlay`
placement; lane 4 assumes lane 1's infinite answer and lane 2's default spacing;
lane 5 assumes nothing from 1–4 except for pins 5.3 and 5.5, which read the
proposal side lanes 2 and 4 settled. A lane that finds a probe arm contradicted
by its implementation stops, re-runs the arm, and amends the ruling in the
decisions doc before continuing; it never edits a probe's recorded output.

## 8. Deferrals

`CN-Q`, in full. None of them is silent: each is a row there with its reason and
owner, and the Docs phase carries each into CLAUDE.md's divergence or inert
tables.

## 9. Divergences this task creates or leaves (numbers assigned at integration)

- `ProposalText` beside text in a `VStack`: 8 where SwiftUI's font-derived gap
  is 0 / 4.74 / 8.15 (`CN-H`, pin 2.4). Owner task 11.
- Legacy `Row`/`Column` gap 0 (`CN-P` 1, pin 5.3); legacy `Stack` fit-content
  offer (`CN-P` 2, pin 5.4); legacy `ScrollView` cross axis (`CN-P` 3, pin 5.5).
- A two-member `Component` under a legacy `.frame` keeps the row lowering where
  SwiftUI frames each member (component-distribution G7; `CN-N`).
- Retired by this task: divergence 36 (`FR-N`, the squeezed child) at lane 5;
  the inert row for stack alignment's main-axis half at lane 2 (element level);
  CLAUDE.md's four "unprobed kernel behaviour" bullets on spacers, expansion,
  compression and measure-versus-place at lane 1; `SA-N` items 2, 3 and 8.
- Deprecated, not divergent: the spacing-first stack initializers and
  `percent:` (+5 `@available(*, deprecated` hits).

## Appendix — prototype red lists

**P1** (kernel `CN-B`, `CN-C` without inf, `CN-D`, `CN-E`): 1303 tests, 50
issues: `aBranchingNativeTreeMeasuresEachLeafOncePerDistinctProposal`,
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
`aSecondComputeNativeLayoutCallReMeasuresEveryLeaf`, and — not reproduced under
P2 or P5 — `aNodeIDDoesNotSilentlyResolveAgainstAnotherFramesTree`,
`everyFrameTakesADistinctTreeGeneration`.

**P2** (+ `CN-G`, `CN-J`): 25 red — P1's 13 plus
`aFlexibleFrameElementGrowsToItsProposalThroughTheElementAPI`,
`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`,
`aNegativeAspectRatioIsAcceptedOnEveryProposedBranch`,
`anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`,
`aProposalLayoutContainerRendersThroughTheFramePipeline`,
`aspectRatioFillCircumscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioFitInscribesTheParentProposalBeforeMeasuringItsChild`,
`aspectRatioUsesSwiftUIsBranchAtZeroAndNegativeProposalAxes`,
`hStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`,
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder`,
`spacerMinimumLengthSurvivesAConstrainedStackProposal`,
`vStackUsesThePlatformDefaultSpacingUnlessTheCallerOverridesIt`.

**P5** (+ `CN-M` cross axis, `CN-F`): 27 red — P2's 25 plus
`aFrameAtAnInfiniteProposalAnswersItsChildRatherThanInfinity`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`.

**Legacy gap 8** (`CN-P`): 22 red —
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

**Legacy frame as a stack, every layer** (`CN-N`): 5 red / 8 issues —
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers`,
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`,
`aFrameWrapsAComponentsBodyWithoutOverwritingItsChildren`,
`aLegacyFrameSqueezesAnOversizedChildWhereSwiftUIOverflows`,
`chainedFramesRemainConcreteAndNestTheirLayoutNodes`.
