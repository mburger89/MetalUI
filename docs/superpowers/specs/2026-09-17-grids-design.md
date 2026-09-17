# Grids — design (plan task 7, stage G)

`feat/grids` from `cb2e708`. Rulings `GR-A`…`GR-P` in
[`../2026-09-17-grids-decisions.md`](../2026-09-17-grids-decisions.md); probes
`docs/probes/swiftui-grid.swift` (revision 4; arm ids below are its),
`docs/probes/swiftui-grid-corpus.txt` (its `corpus` mode) and
`docs/probes/swiftui-lazy-grid-scope.swift`; record
`docs/record/20-grids.md`. Parent design:
[`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row G ("no legacy twin; depends on nothing; exit test is its own probe's
arms; goldens 0; demo 0 px").

**Status, 2026-09-17: design only.** Nothing under `Sources/` or `Tests/`
changed. Baseline at `cb2e708`, measured in this worktree: `Test run with 1409
tests in 1 suite passed` (native, unfiltered), 97 goldens, 71 guards.

## Contents

1. [The task](#1-the-task)
2. [Evidence](#2-evidence)
3. [Shape: a kernel case, marks, and three element types](#3-shape)
4. [The algorithm (normative)](#4-the-algorithm-normative)
5. [API](#5-api)
6. [Lanes](#6-lanes)
7. [Order, counts, and what each lane may assume](#7-order-counts-and-what-each-lane-may-assume)
8. [Deferrals and divergences](#8-deferrals-and-divergences)

## 1. The task

Plan task 7: *"Implement the proposal-system equivalents of … grids …"*.
Engine-replacement design §4.1, row G: *"`Grid`/`GridRow` as probe-backed
`ProposalLayout`s"*. The row's "as `ProposalLayout`s" is **amended by `GR-A`**:
a grid is a kernel case, because what it reads (row membership, cell attributes
behind wrappers, Spacer edges) is not reachable through the public proxy.

What SwiftUI's `Grid` turns out to be (the probe's reading, header items 1–10):
columns sized by their widest cell and rows by their tallest; per-boundary
spacing that goes to 0 beside a Spacer and where no cells meet; at a finite
proposal a **flexibility-ordered, priority-grouped** distribution over cells —
not over columns — with shares recomputed only between groups and columns
committed as their cells finish; layout priority served with no reservation
(so a grid can answer wider than its proposal); spans that widen empty columns
first; per-column alignment from the first declaration; anchors; unsized axes;
attributes that pass through modifiers and stop at containers; and `GridRow` as
a transparent run of cells. `LazyVGrid`/`LazyHGrid` are a different, lazy
algorithm and are **not** this stage (`GR-L`).

## 2. Evidence

- **Arms** (probe groups GA, GP, GF, GR, GS, GX, GQ, GL, GU, GW, GG, GT), each
  group with a control that differs (header, "CONTROLS").
- **The reference model** (`solve`, `ModelGrid` in the probe) — a SwiftUI
  `Layout` over the same leaves — compared with `Grid` on generated grids (GZ):
  plain grids 1000/1000; with attributes 988/1000; Spacers 479/500; priority
  441/500; non-row children 476/500; spans 374/500; infinite proposals 222/300;
  everything 659/1000; the control that ignores commits 212/300 (`GR-B`).
- **The corpus**: 120 generated grids on which `Grid` and the model agree,
  with every leaf rect, as Swift literals.
- **Lazy grids**: LZ0–LZ7 (`GR-L`).

## 3. Shape

| layer | file | what |
|---|---|---|
| kernel | `Sources/MetalUILayout/NativeGrid.swift` (new) | `ProposalAxes`; `NativeGridPlan`, `NativeGridCell`; the pure solver `solveNativeGrid(_:proposal:measure:)` → `NativeGridSolution`; `nativeGridCellRects(_:solution:origin:measure:)` |
| kernel | `Sources/MetalUILayout/LayoutTree.swift` (appended, localized) | three stored mark dictionaries (+ `reset`); `NativeNode.grid(NativeGridPlan)`; a `.grid` arm in `measureNative`, `placeNative`, `markSpacers`, `zeroSpacingEdges`, `nativeLayoutPriority`; an extension at the end holding the registrars and the plan's walk |
| element plumbing | `Sources/MetalUI/Frame.swift`, `Sources/MetalUI/Passes.swift` (appended) | `Frame.requestNativeGrid`/`markNativeGridRow`/`markNativeGridCell` forwards; `LayoutPass` mirrors over `ProposalNodeID` |
| elements | `Sources/MetalUI/Grid.swift` (new) | `Grid`, `GridRow`, `GridCellModifier`, the four cell modifiers |

**Not touched:** `NativeElements.swift`, `Box.swift`, `ModifiedElement.swift`,
`LegacyLowering.swift`, `LayoutAuthority.swift`, the demo and preview content,
CLAUDE.md/AGENTS.md/README/plan/record README (the integrator's).

**The `.grid` arms elsewhere.** `markSpacers`: stop (a grid marks no spacer: its
Spacer cells are flexible on both axes, GQ8). `zeroSpacingEdges`: neither edge
zero (unprobed, `GR-D`). `nativeLayoutPriority`: the `default` 0.

## 4. The algorithm (normative)

The probe's `solve`/`ModelGrid` is the reference; where this text and the model
disagree the model is right and this text is a defect.

### 4.1 Marks and the plan (registration)

- `markNativeGridRow(cells, alignment)` allocates a fresh **row token** and
  stores it for every node in `cells` (overwriting an earlier token: an
  enclosing `GridRow` registers after an inner one, GG3), with the row's
  alignment (vertical factor only).
- `markNativeGridCell(node, columns:, anchor:, columnAlignment:, unsizedAxes:)`
  merges into the node's marks: `columns` — if > 1, **added** to the node's
  column sum (0 and 1 add nothing; negative traps); `anchor` and
  `columnAlignment` (horizontal factor only) — kept if the node has none yet
  (the inner modifier registers first, so the inner wins); `unsizedAxes` —
  unioned.
- Both trap if the node already has a native parent ("a grid mark written after
  its node was parented").
- `newNativeGrid(children, alignment, horizontalSpacing, verticalSpacing)`
  checks every child is native (`nativeNode`), records parents (`CN-L`),
  validates spacing (finite, `SA-J`; negative accepted) and builds the plan:
  - A child's **chain** is the child, then repeatedly `frame`/`padding`/
    `fixedSize`/`aspectRatio`/`layoutPriority`'s child and an overlay
    attachment's child 0, until any other kind (`GR-I`).
  - Its **row token** is the outermost token on its chain. Consecutive children
    with the same non-nil token form one row; a child with no token is a row of
    its own, a **non-row cell**.
  - A row cell's **span** is max(1, the sum over its chain of column sums), its
    **anchor** and **column alignment** the innermost on its chain, its unsized
    axes the union. A non-row cell has the anchor and unsized axes; its column
    marks and column alignment are ignored (GX13).
  - `ncols` is the largest sum of spans in a row, 1 if there is no row. Row
    cells take columns left to right and a span is clamped to the columns left.
    A non-row cell starts at 0 and spans `ncols`.
  - Each cell's **priority** is `nativeLayoutPriority(child)`; its zero-spacing
    edges `zeroSpacingEdges(child, .horizontal)` and `(…, .vertical)`.
  - **Gaps.** For 1 ≤ j < ncols, `hgap[j]` is the largest pair value over pairs
    (L, R) in one row with L ending at j−1 and R starting at j; 0 if none. For
    1 ≤ r < nrows, `vgap[r]` the largest over columns q covered by a cell A in
    row r−1 and a cell B in row r; 0 if none. A pair's value is the explicit
    spacing if given, else 0 if L's trailing (A's bottom) or R's leading (B's
    top) edge is zero, else `ProposalSpacing.platformDefault` (`GR-D`).
  - **Column alignment of column j**: the first row cell, in row then cell
    order, whose column alignment is set and whose first column is j.

### 4.2 Solve at a proposal P = (Pw, Ph)

State: `curW[ncols]`, `curH[nrows]` start at 0. `absorb(c, a)`: `curH[row] =
max(curH[row], a.h)`; if span 1, `curW[col] = max(curW[col], a.w)`.
`absorbSpan(c, a)`: `have` = Σ curW over the span + its inner gaps; if `a.w >
have`, add `(a.w − have) / |T|` to each column in T, where T is the spanned
columns holding **no single-column cell anywhere in the grid**, or all spanned
columns if that is empty (`GR-F`).

**Both axes nil.** Measure every cell at nil, in source order; absorb every
cell; then `absorbSpan` every spanning cell in source order (GP3, GX1, GX7).

**Otherwise.**

1. Measure every cell at 0×0 (`z`) and ∞×∞ (`i`).
2. Key: (−priority; `k` = the number of axes with a non-nil proposal on which
   `i` is infinite; `f` = the sum over the other such axes of `i − z`).
   Stable-sort cells by key; maximal runs of equal keys are **groups**.
3. `W′ = Pw − Σ hgap`, `H′ = Ph − Σ vgap` (nil stays nil). `committedC`,
   `committedR` start empty.
4. For each group, with `level` its priority:
   - `openC` = columns with an unprocessed **span-1** cell of priority `level`;
     `openR` = rows with an unprocessed cell of priority `level`.
   - `shareW = W′` if W′ is infinite, else `(W′ − Σ_{committedC} curW) /
     max(|openC|, 1)`; `shareH` likewise. (Nil if the axis is nil.)
   - For each cell in the group, in order, its proposal:
     - width: nil if Pw is nil; else if unsized horizontally, Σ curW over its
       span + inner gaps; else if span 1, `max(shareW, curW[col])`; else if W′
       is infinite, W′; else `max(W′ − Σ_{j outside the span} (j ∈ openC ?
       shareW : curW[j]) + inner gaps, Σ curW over the span + inner gaps)`;
     - height: nil if Ph is nil; else if unsized vertically, `curH[row]`; else
       `max(shareH, curH[row])`;
     - measure at it, record (proposal, answer), `absorb`.
   - Then `absorbSpan` each spanning cell of the group, in order.
   - Commit every column not yet committed that has no unprocessed span-1 cell
     of priority ≥ `level`; every row likewise over all its cells.
5. The answer is `(Σ curW + Σ hgap, Σ curH + Σ vgap)`.

### 4.3 Place in bounds B at proposal P

Solve at P (every measurement is a cache hit). Column j's x is `B.x + Σ_{k<j}
curW[k] + Σ_{k≤j} hgap[k]`; row r's y likewise. A cell's slot is (Σ curW over
its span + inner gaps, `curH[row]`). Its **placement proposal** is the slot,
unless the slot equals the answer recorded in 4.2 for this cell, in which case
it is the proposal recorded with it (GR1, GR2). Measure at it → `a`. Factors:
`fx = anchor.x ?? (span == 1 ? columnAlignment[col].x : nil) ?? gridAlignment.x`
(a non-row cell spans `ncols`; with one column it is span 1), `fy = anchor.y ??
rowAlignment.y ?? gridAlignment.y`. Place the cell's subtree at
`(colX + (slotW − a.w)·fx, rowY + (slotH − a.h)·fy, a.w, a.h)` with that
proposal. Bounds larger than the answer put the grid at B's origin (as
`ZStack`, `CN-E`); a root is centred by `CN-J` before this runs.

### 4.4 Cost and depth

Per cell: at a nil proposal 1 measurement plus 1 at its slot unless the slot is
its answer; otherwise at most 4 (0×0, ∞×∞, group proposal, slot). GP1's grid is
16 leaf calls and GP2's 15 — the probe's "measured, in order" list lengths. A
grid is **one** native level; the solver runs in functions called from
`measureNative`, so no locals are added to `measureNative`'s own frame
(`GR-M`'s depth gate).

## 5. API

`MetalUILayout`:

```swift
/// A set of layout axes: SwiftUI's `Axis.Set`, for `gridCellUnsizedAxes` (GR-H).
public struct ProposalAxes: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8)
    public static let horizontal: ProposalAxes
    public static let vertical: ProposalAxes
}

extension LayoutTree {
    /// Marks `cells` as one grid row (GR-A, §4.1). Traps on a node that already has a parent.
    public func markNativeGridRow(_ cells: [LayoutNodeID], alignment: ProposalAlignment? = nil)
    /// Merges grid-cell attributes into `node`'s marks (§4.1). `columns` < 0 traps (GT1).
    public func markNativeGridCell(_ node: LayoutNodeID, columns: Int? = nil,
                                   anchor: ProposalAlignment? = nil,
                                   columnAlignment: ProposalAlignment? = nil,
                                   unsizedAxes: ProposalAxes = [])
    /// Registers a grid over native children (§4). nil spacing is the platform
    /// default per boundary (GR-D); a given spacing must be finite (SA-J).
    public func newNativeGrid(children: [LayoutNodeID], alignment: ProposalAlignment = .center,
                              horizontalSpacing: Double? = nil,
                              verticalSpacing: Double? = nil) -> LayoutNodeID
}
```

Lane 1 ships `markNativeGridCell(_:columns:)` only; lane 2 adds the other three
parameters (source-compatible: defaulted).

`MetalUI` (`Grid.swift`):

```swift
public struct Grid<Content: ProposalElementGroup>: ProposalElement {
    public var content: Content
    public var alignment: ProposalAlignment
    public var horizontalSpacing: Pixels?
    public var verticalSpacing: Pixels?
    public init(alignment: ProposalAlignment = .center, horizontalSpacing: Pixels? = nil,
                verticalSpacing: Pixels? = nil, @ElementBuilder content: () -> Content)
}

/// A run of grid cells (GR-J): one cursor index, cells numbered from 0 under
/// its own id, no node; outside a Grid, just its cells.
public struct GridRow<Content: ProposalElementGroup>: ProposalElementGroup {
    public var content: Content
    public var alignment: VerticalAlignment?
    public init(alignment: VerticalAlignment? = nil, @ElementBuilder content: () -> Content)
}

/// A grid-cell attribute over every node of `content`; no node, no index, no id.
public struct GridCellModifier<Content: ProposalElementGroup>: ProposalElementGroup {
    public var content: Content
    public var attribute: GridCellAttribute
}
public enum GridCellAttribute: Sendable, Hashable {
    case columns(Int), anchor(ProposalAlignment), columnAlignment(HorizontalAlignment),
         unsizedAxes(ProposalAxes)
}

extension ProposalElementGroup {
    public func gridCellColumns(_ count: Int) -> GridCellModifier<Self>
    public func gridCellAnchor(_ anchor: ProposalAlignment) -> GridCellModifier<Self>
    public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> GridCellModifier<Self>
    public func gridCellUnsizedAxes(_ axes: ProposalAxes) -> GridCellModifier<Self>
}
```

`LayoutPass` gains `requestNativeGrid(children: [ProposalNodeID], …) ->
ProposalNodeID`, `markNativeGridRow(_: [ProposalNodeID], alignment:)` and
`markNativeGridCell(_: ProposalNodeID, …)`. `GridRow` and `GridCellModifier`'s
untyped `requestGroupLayout` forward to the typed entry and map ids (no copy,
`MC-H`); their `prepaintGroup`/`paintGroup` forward to `content` once each.
Element-level `Grid.requestProposalLayout` numbers content from cursor 0 under
its id and calls `requestNativeGrid`, as `HStack` calls
`requestNativeLinearStack`.

## 6. Lanes

Four, in order (`GR-M`). Each lane: red first; `swift package clean` before the
suite in lanes 1 and 2; `swift build --build-system native --build-tests`, then
`swift test --build-system native --no-parallel` unfiltered, reading the `Test
run with N tests` line against §7; 0 `error:`/`warning:` besides SwiftPM's
notice; `find Tests -name "*.json" | wc -l` = 97; mutations per `GR-M` after
committing, naming every test each reddens; the demo comparison of `GR-M`
(expected **0 differing pixels, scene identical**, every image, every lane).

**Test leaves.** Kernel tests build the probe's leaves as native leaves
(`fx`, `fl`, `hf`, `fw`, `fh`, `cb`, `cw`, `ch`, `odd`) in a file-private `Arm`
helper modelled on `NativeStackDistributionTests.swift`'s, logging distinct
proposals and call counts. A kernel arm is laid out as the probe's `Probe` does:
`measureNativeLayout` at the arm's proposal, then `computeNativeLayout(root:
proposal:in:)` at that proposal in bounds of its own answer at the origin (a
measured-only arm reads the answer alone). A rect is compared with
`roundLayout` of the probe's rect; an answer with the probe's to 1e-9 (or
equal infinity). Element tests read prepaint bounds relative to the `Grid`'s
own bounds (a native root is centred, `CN-J`).

"Red before" is what the tree does before the lane; for a test of a new
registrar or type it is its absence (does not compile). The **mutation** is
applied after the lane commits and must redden the test named (and the lane
records what else it reddens).

### Lane 1 — the kernel algorithm

**Rulings:** `GR-A`, `GR-B`, `GR-C`, `GR-D`, `GR-E`, `GR-F` (except the
column-sum rule and `columns(0)`), `GR-G`'s grid and row alignment.

**Source.** `NativeGrid.swift` (plan, solver, placement rects, `ProposalAxes`);
`LayoutTree.swift` per §3 with `markNativeGridCell(_:columns:)` only and a
chain walk that reads marks **on the child node alone** (lane 2 walks the
chain); `Frame.swift`/`Passes.swift` forwards. `swift package clean` before the
suite.

**New tests.** `Tests/MetalUILayoutTests/NativeGridTests.swift` and
`NativeGridWorkTests.swift` (`@testable import MetalUILayout`, as
`NativeStackDistributionTests.swift`: `measureNativeLayout` and
`lastNativeLayoutWork` are internal), exit tests in `NativeGridTrapTests.swift`
(plain import, as `NativeBoundaryTrapTests.swift`, except 1.9, which measures),
depth tests appended to `NativeDepthGuardTests.swift`.

| # | test | arms | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aGridSizesColumnsFromTheWidestCellAndRowsFromTheTallest` | GA1, GA2, GA3, GA4 | no registrar | take a column's width from its first cell, not the widest (GA1 b moves) |
| 1.2 | `anEmptyGridOrRowIsNothingAndNonRowChildrenMakeOneColumn` | GA5, GA6, GA7, GA8, GA9 (GA5/GA6 as a grid with no children and one of an empty row mark) | no registrar | count a row of zero cells as a row (GA7's c moves) |
| 1.3 | `atANilProposalSpansWidenTheirColumnsAfterEverySingleColumnCell` | GP3, GX1, GX2, GX3, GX4, GX5, GX6, GX7 | no registrar | absorb each cell's span in source order among the single-column cells (GX7's a moves to x 8) |
| 1.4 | `aSpanShortfallGoesFirstToSpannedColumnsWithNoSingleColumnCell` | GX11 | no registrar | spread over every spanned column (col 1 41, col 2 51) |
| 1.5 | `aCellWhoseSlotEqualsItsAnswerIsPlacedAtTheProposalItWasMeasuredAt` | GR1, GR2 with `odd`, and GR0's control (an `odd` leaf in a 20×20 fixed frame reads 15×15), `#require`d first; GP3's c placed at nil | no registrar | always place at the slot size (a reads 15×15 at (2.5, 2.5)) |
| 1.6 | `aFiniteProposalServesGroupsWithSharesAndCommits` | GP1, GP2, GF1–GF9, GF14–GF18 (a greedy `newNativeFrame(maxWidth: .infinity)` cell and a proposal-responsive leaf standing for `Color`): answers, rects, and GF7's d proposed 120 wide (its log) | no registrar | GZ0's control: every group offered W′/ncols, commits ignored (GP2's a at 96) |
| 1.7 | `theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis` | GF10, GF11, GF12, GF13 (`#require` GF12 ≠ GF13) | no registrar | key = the finite sum with ∞ as +∞, one group for equal sums (GF10's b at 96) |
| 1.8 | `oneAxisNilAndInfiniteProposalsAnswerAsTheProbeReads` | GP5, GP6 laid out; GP4 (∞×∞) and GP8 measured only (an infinite answer traps at checkpoint 3 when stored, `SA-J`) | no registrar | propose a nil grid axis as 0 instead of nil (GP5's a answers 152×0) |
| 1.9 | `anInfiniteAxisSharesInfinityAfterAnInfiniteCommittedColumn` — an exit test expecting `.success` (`@testable`), measuring GP9, GP10, GP11 in the child and checking their answers | GP9–GP11 | no registrar | compute `(W′ − committed)` on an infinite axis: inf − inf is nan and checkpoint 1 traps, so the child exits `.failure` |
| 1.10 | `higherPriorityGroupsAreServedFirstWithNoReservation` | GQ1, GQ2, GQ3, GQ4, GQ5 (answers 100×100, 130×10, 120×10, 210×120, 266×118) | no registrar | reserve lower groups' 0×0 widths, as `CN-B`'s stack does (GQ2's a and c read 27) |
| 1.11 | `aSpacerCellIsPriorityMinusInfinityAndFlexibleOnBothAxes` | GS1 (s 142×42), GQ6, GQ7, GQ8 | no registrar | read a cell's priority as 0 (GS1's s reads 152×62) |
| 1.12 | `eachGapIsTheLargestPairSpacingMeetingThere` | GS1, GS2 vs GS3 (`#require` they differ), GS4, GS5, GS6, GS11, GS12–GS18 | no registrar | put `platformDefault` before every column j ≥ 1 regardless of pairs and edges (GS2 reads 64, GS6 76) |
| 1.13 | `explicitGridSpacingIsVerbatimAndNegativeSpacingIsAccepted` | GA2, GA3, GS8 (60×45) | no registrar | clamp a given spacing at 0 (GS8 reads 70×50) |
| 1.14 | `aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndKeepsNoColumnOpen` | GX8, GX9 (b 262), GX10 (a at 60.5, b at 219.5), GX12 (x proposed 300; a 176, b 116 slots) | no registrar | propose a span its columns' shares plus inner gaps instead of W′ minus the outside (GX10's x is proposed 492 and widens both columns) |
| 1.15 | `swiftUIsSpanOverflowIsNotPorted` — pinned wrong on purpose; the probe's figures in its doc comment | GX17: kernel **200×100**, a (14,36 30×10), b (66,0 78×82), c (166,31 20×20), x (25,90 150×10); GX18: **200×100**, a (0,0 104×82), b (112,36 30×10), c (150,36 50×10), x (70,90 60×10); GX19 (control, agreeing with SwiftUI): 200×100, x (80,90 40×10) | no registrar | skip `absorbSpan` at a finite proposal (GX17's cols read 30/134/20: a at 0) |
| 1.16 | `gridAndRowAlignmentPlaceCellsInTheirSlots` | GL1, GL2, GL3, GL9, GL12 | no registrar | ignore the row alignment (GL3's a at y 5) |
| 1.17 | `consecutiveCellsOfOneRowTokenAreOneRowAndAnUnmarkedChildSpansTheGrid` | kernel spellings of GG3 (two marks, the enclosing one overwriting) and GG9 (a linear stack holding marked nodes is a non-row child), and two adjacent rows of equal alignment staying two rows | no registrar | compare rows by alignment instead of token (the adjacent rows merge) |
| 1.18 | `theGridProbeCorpusAgreesCaseByCase` — reads `GridCorpus.swift` (the corpus file's literals, transcribed verbatim into `Tests/MetalUILayoutTests/GridCorpus.swift` with the file's comment header kept), `#require`s 120 cases and, in this lane, filters to those with no anchor, column alignment or unsized axis: `#require` **19** | the corpus | no registrar | GZ0's control (the lane records how many of the 19 redden) |
| 1.19 | `aGridsWorkIsOneLeafCallPerDistinctProposal` (`NativeGridWorkTests.swift`) | GP1 = 16 leaf calls, GP2 = 15, GP3 = 7; cache hits and misses **derived by hand before the run** and recorded in the doc comment | no registrar | re-measure every cell at its slot even when the slot equals its answer (GP3 reads 8) |
| 1.20 | `resetClearsGridMarks` | a node marked as a row in generation 1; after `reset(generation: 2)` a new node at the same index under a grid is a non-row cell | no registrar | do not clear the row-token dictionary in `reset` |
| 1.21 | `aLegacyNodeRegisteredUnderANativeGridTraps` (exit, stderr "contains a legacy node") | — (`SA-G`) | no registrar | drop `nativeNode(child)` in `newNativeGrid` |
| 1.22 | `aNaNGridSpacingTraps` (exit, stderr names the parameter) | GS10 | no registrar | drop the finiteness precondition |
| 1.23 | `anInfiniteGridSpacingTraps` (exit) | GS9 | no registrar | the same |
| 1.24 | `aGridMarkOnANodeThatAlreadyHasAParentTraps` (exit) | — | no registrar | drop the parent precondition in `markNativeGridRow` |
| 1.25 | `aNodeUnderAGridAndASecondParentTraps` (exit, `CN-L`'s message) | — | no registrar | skip `recordParent` in `newNativeGrid` |
| 1.26 | `aChainOfGridsDeeperThanTheLimitTraps` (exit; 89 nested one-cell grids) | — (`SA-L`) | no registrar | `NativeLayoutRun.maxDepth` 89 (the child exits `.success`) |
| 1.27 | `aChainOfGridsAtTheLimitDoesNotTrap` (exit `.success`; 88) | — | no registrar | `NativeLayoutRun.maxDepth` 87 (88 traps) |

**Existing tests that change:** `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`
gains a 13th registrar (`newNativeGrid(children: [leaf(), leaf()])`); its node
count literal 26 → **29**. Nothing else is expected to move; a red existing test
is a finding.

**Depth gate** (`GR-M`): before committing, bisect the debug ceiling of a chain
of one-cell grids on a 1 MB `Thread` by `SA-L`'s method and record it in
`NativeLayoutRun.maxDepth`'s table; below 147, stop and report.

**Expected count:** 1409 + 27 = **1436**; guards 71. **Demo:** 0 px (`GR-M`).

### Lane 2 — cell attributes, the modifier-chain walk, and the exit test

**Rulings:** `GR-F`'s column-sum rule and `columns(0)`, `GR-G` (column
alignment, anchors, inner-wins), `GR-H`, `GR-I`.

**Source.** `markNativeGridCell` gains `anchor:`, `columnAlignment:`,
`unsizedAxes:`; the plan walks each child's chain (§4.1); the solver and
placement honour unsized axes, anchors and column alignment (§4.2, §4.3).
`swift package clean` before the suite (a new stored mark field).

| # | test | arms | red before | mutation |
|---|---|---|---|---|
| 2.1 | `columnAlignmentIsTheFirstDeclarationInRowOrder` | GL4, GL5, GL6, GL7 | no parameter | the last declaration wins (GL6's a at x 20) |
| 2.2 | `aSpanDeclaresColumnAlignmentForItsFirstColumnAndIsNotAlignedByIt` | GL8 | no parameter | align a span by its first column's alignment (c at x 28) |
| 2.3 | `aCellAnchorBeatsColumnAndRowAlignmentAndAppliesToNonRowChildren` | GL10, GL11, GL13 | no parameter | column alignment before the anchor in `fx` (GL10's a at x 30) |
| 2.4 | `onOneNodeTheInnerAnchorAndColumnAlignmentWin` | GL15, GL16, GWI3, GWI4 | no parameter | a later mark overwrites (GL16's c at (40, 98)) |
| 2.5 | `gridCellColumnsDeclaredTwiceAddTheirValuesAboveOne` | GX15 (5 columns), GX16 (2), GWI1, GWI2 | lane 1's mark replaces an earlier one (GX15 spans 2) | take the largest mark instead of the sum (GX15 reads 3) |
| 2.6 | `anUnsizedAxisIsProposedItsCurrentSlotAndItsAnswerStillCounts` | GU1 vs GU2 (`#require` differ), GU3, GU4, GU5, GU6, GU7, GU8, GU11 | no parameter | do not absorb an unsized cell's answer on that axis (GU5 reads 78 wide) |
| 2.7 | `anUnsizedNonRowChildStopsWideningTheGrid` | GU9 vs GU10 | no parameter | ignore unsized axes on non-row cells (GU9 reads 200) |
| 2.8 | `unsizedAxesDeclaredTwiceFormAUnion` | GU12, GU13, GWI5 | no parameter | a later mark replaces the axes (GU12 reads horizontal only) |
| 2.9 | `cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers` — one arm per node kind: fixed and flexible `frame`, `padding` (and a padding with a non-zero inset), `fixedSize`, `aspectRatio`, `layoutPriority`, overlay attachment primary, overlay attachment content side, one-child linear stack, one-child overlay; for each of span, anchor, column alignment, unsized axes and a row token; and GWP's priority arms (padding, flexible frame, aspect ratio stop; overlay primary and one-child stacks pass), which the existing walk already satisfies | GWS/GWA/GWC/GWU/GWP rows 1–4, 6, 11, 12, 15–18 | lane 1 reads marks on the child node only (every wrapped arm reads the unwrapped control's rect) | stop the chain at `padding` (the padding arms redden, and 2.4's and 2.5's GWI arms) |
| 2.10 | `gridCellColumnsZeroLaysOutAsOne` — divergence pin; GX14's SwiftUI figures in the doc comment | GX14: kernel c (10,28 10×10), d (45.5,30.5 5×5), 58×38 (the probe's "GX14as1" computation, record §20) | lane 1 already treats 0 as 1; **green on arrival**, kept as the pin | treat 0 as 2 (c spans two columns, d moves to column 2) |
| 2.11 | `aNegativeGridCellColumnsTraps` (exit, stderr names `columns`) | GT1 | no precondition | drop it |
| — | `theGridProbeCorpusAgreesCaseByCase` (1.18) **loses its filter**: `#require` 120 | the corpus | 101 cases were filtered out | each of: GZ0's control; last-declaration column alignment; unsized answers not absorbed — the lane records how many cases each reddens |

**Expected count:** 1436 + 11 = **1447**; guards 71. **Demo:** 0 px.

### Lane 3 — elements and identity

**Rulings:** `GR-J`, `GR-K`'s layout transparency; `GR-G`/`GR-H`'s element
types.

**Source.** `Sources/MetalUI/Grid.swift` (§5); `Passes.swift`/`Frame.swift`
forwards if lane 1 did not add them. No `swift package clean` needed (new
types only), but take one if an incremental build misbehaves (CLAUDE.md).

`Tests/MetalUITests/GridElementTests.swift`; guards in
`Tests/MetalUITests/GridCompileGuards.swift` (plain `import MetalUI`,
`typecheckFile`, `SA-P`).

| # | test | arms | red before | mutation |
|---|---|---|---|---|
| 3.1 | `gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI` | GA1, GA3, GP2 (at a 200×100 root), GL3 (`GridRow(alignment: .top)`), GX1 (`.gridCellColumns(2)`), GL5 (`.gridColumnAlignment(.trailing)`), GL11 (`.gridCellAnchor(.trailing)`), GU9 (`.gridCellUnsizedAxes(.horizontal)`), GF14 (`.frame(maxWidth: .infinity)`), GF16 (`Color(.accent)`); nil arms under `.fixedSize()` | no types | `Grid` passes `horizontalSpacing` as vertical (GA3 moves) |
| 3.2 | `everyProposalModifierCarriesAGridCellAttributeAsTheProbeReads` | GWS/GWA/GWC/GWU through MetalUI's spellings: `.padding(Edges)`, `.frame(width:height:)`, `.frame(maxWidth:)`, `.fixedSize()`, `.aspectRatio`, `.layoutPriority`, `.background(ColorToken)`, `.clip`, `.border`, `.opacity`, `.allowsHitTesting(false)`, `.onTap {}`, `.disabled(true)`, `.overlay { }` primary and content side, `.background { }` content side, `HStack { one }`, `ZStack { one }` | no types | `GridCellModifier` drops `.columnAlignment` (every GWC arm reddens; the lane records the rest) |
| 3.3 | `aGridRowOutsideAGridIsItsCells` | GG1 (in a `VStack`: a (0,0), b (5,18), 30×38), GG2 | no types | `GridRow` registers an `HStack` of its cells (GG1 reads one child) |
| 3.4 | `aGridRowInsideAGridRowFlattens` | GG3 (71×20) | no types | the kernel keeps the first row token written (GG3 reads two rows) |
| 3.5 | `aGridCellModifierOnAGridRowAppliesToEachCell` | GG5 (anchor), GG6 (columns: 208×38) | no types | mark only the first node (GG6's d spans 1) |
| 3.6 | `rowsReachTheGridThroughIfAndForEachAndAContainerHoldingARowIsNotARow` | GG8 (`if`, `for`), GG9 (`HStack { GridRow { … } }`) | no types | give every `GridRow` the same row token (GG8's two rows merge) |
| 3.7 | `aGridRowTakesOneIndexAndNumbersItsCellsFromZeroUnderItsOwnID` | ids recorded in prepaint: cell (r, c) is `child(child(grid, r), c)` | no types | forward `parent` and `cursor` through `GridRow` (cells number flat under the grid) |
| 3.8 | `removingACellFromOneRowKeepsAnotherRowsState` | `@State` counter in row 1's first cell, clicked to 1; row 0's second cell removed by an `if`; the counter still reads 1 | no types | the same mutation as 3.7 (the counter reads 0) |
| 3.9 | `aGridCellModifierIsLayoutAndIdentityTransparent` | a cell's `@State` survives adding and removing `.gridCellAnchor`; its id is unchanged; no extra node | no types | `GridCellModifier` consumes a cursor index (the id moves, the state resets) |
| G1 | `aGridRejectsLegacyContent` (guard) | `Grid { Box() }` fails; control `Grid { Rectangle() }` compiles | no type (the control fails; the guard is red) | relax `Grid`'s `Content` to `ElementGroup` |
| G2 | `aGridRowAlignmentIsAVerticalAlignment` (guard) | `GridRow(alignment: .leading)` fails; control `.top` compiles | no type | make `alignment` a `ProposalAlignment?` |
| G3 | `aGridColumnAlignmentIsAHorizontalAlignment` (guard) | `.gridColumnAlignment(.top)` fails; control `.trailing` compiles | no type | take a `ProposalAlignment` |

**Existing tests that change:** `everyModifierWrapperDelegatesEachPhaseExactlyOnce`
gains `Grid`, `GridRow` and `GridCellModifier` arms (no new `@Test`).

**Expected count:** 1447 + 12 = **1459**; guards 71 + 3 = **74**, each mutated
red once. **Demo:** 0 px.

### Lane 4 — the pipeline

**Rulings:** `GR-K`, `GR-J`'s multi-cell trap, `GR-M`'s real-window captures.

`Tests/MetalUITests/GridPipelineTests.swift`, through a `Window` over
`FakePlatformWindow` (`makeFakeWindow`). These route through lane 3's elements
and the existing pipeline, so several are **green on arrival**: each `#require`s
a discriminating control first and names a grid-owned mutation.

| # | test | what | red before | mutation |
|---|---|---|---|---|
| 4.1 | `aClickOnAGridCellReachesThatCellsOnTap` | a 2×2 grid of `Rectangle(width:height:)`s with `.onTap` each: a click at each cell's centre counts once on that cell; a click in a slot outside its cell's frame (a 10×10 cell in a 40×40 slot) counts nowhere (`OM-I`) | green on arrival; control: the cell-centre click counts | place cells at their slot size (the slot-corner click counts) |
| 4.2 | `aClickInAGridsGapReachesTheGridsOnTapAndACellOutranksIt` | `Grid { … }.onTap` with tappable cells: a gap click reaches the grid, a cell click the cell only | green on arrival; control: the gap click counts on the grid | `Grid.prepaint` skips its content's prepaint (the cell click reaches the grid) |
| 4.3 | `aGridPublishesNothingAndItsCellsTapStillPresses` | `AB-Y`'s shape with a grid: an active client, nothing published, a press by id counts | green on arrival; control: the window built accessibility | `GridRow.prepaintGroup` skips its content (the hitbox is missing; the press is refused) |
| 4.4 | `aDisabledGridRegistersNoCellHitbox` | `Grid { … }.disabled(true)`: no hitbox; control, enabled: one per tappable cell | green on arrival | `GridRow.prepaintGroup` skips its content (the enabled control's `#require` fails) |
| 4.5 | `aGridRootIsCentredAtItsAnswer` | GA1's grid as a window root in a 200×200 window (GP1's proposal, whose rects equal GA1's): its bounds (61, 71, 78, 58) (`CN-J`); cell a at (61, 76) | green on arrival | place cells from (0, 0) instead of the bounds origin (a at (0, 5)) |
| 4.6 | `aNodeModifierOnAMultiCellGridRowTraps` — divergence pin (exit, the one-node precondition's message) | `Grid { GridRow { a; b }.padding(Edges(all: 5)) }` (GG4's spelling; SwiftUI pads each cell) | green on arrival (the precondition exists); control arm, one cell, exits `.success` | none grid-owned: the pin is of `ModifiedContent`'s precondition; the lane mutates it once (a shared file, reverted) and records the result |
| 4.7 | `aGridPaintsOnlyItsCellsInDeclarationOrder` | scene rects equal the cells' fills in row then cell order; the grid and rows add none | green on arrival | `Grid.paint` paints its content twice (twice as many rects) |

**Real windows:** the lock probe, then `capture.sh <scratch> cb2e708 <HEAD>`
(`GR-M`), its table recorded in record §20 (expected 0 differing pixels in
both windows; if the screen reads locked, say so and do not capture).

**Record §20** gains "For the integrator": CLAUDE.md's vocabulary (proposal
types gain `Grid`, `GridRow`, the four cell modifiers, `ProposalAxes`), the
kernel's registrars count (13 `newNative*` and `requestNative*` each, plus two
mark functions each), the unprobed and divergence lists (`GR-O`), design §4.1
row G's "as `ProposalLayout`s" and the proposed stage G2 (`GR-L`), the plan's
task 7 note, and the suite/guard counts re-taken after `swift package clean`.

**Expected count:** 1459 + 7 = **1466**; guards 74. **Demo:** 0 px; real
windows 0 px.

## 7. Order, counts, and what each lane may assume

| lane | assumes | new `@Test` | suite | guards | clean |
|---|---|---|---|---|---|
| 1 | `cb2e708` | 27 | 1436 | 71 | yes |
| 2 | lane 1 | 11 | 1447 | 71 | yes |
| 3 | lanes 1–2 | 12 | 1459 | 74 | no |
| 4 | lanes 1–3 | 7 | 1466 | 74 | no |

Counts are design estimates: each lane re-takes them and explains a difference.
The stage-2 track may land first at integration; the counts add.

A lane may substitute a grid-owned mutation for one named here only after
showing the named one fails to discriminate, and records both.

## 8. Deferrals and divergences

Deferrals with owners: `GR-N`. Divergences created: `GR-O` (numbers assigned at
integration). Lazy grids: `GR-L` (proposed stage G2, after stage 4).
