# Grids — design (plan task 7, stage G)

`feat/grids` from `cb2e708`. Rulings `GR-A`…`GR-W` in
[`../2026-09-17-grids-decisions.md`](../2026-09-17-grids-decisions.md); probes
`docs/probes/swiftui-grid.swift` (**revision 5**; arm ids below are its),
`docs/probes/swiftui-grid-corpus.txt` (its `corpus` mode at revision 5) and
`docs/probes/swiftui-lazy-grid-scope.swift`; record `docs/record/20-grids.md`.
Parent design:
[`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row G ("no legacy twin; depends on nothing; exit test is its own probe's
arms; goldens 0; demo 0 px").

**Status, 2026-09-17: lane 1 built** (`432cb3d` red, `82a63fe`; as-built
amendments in `GR-W`, record §20 "Lane 1"). Lanes 2–4 not started. The design
was revised after one critic round (`GR-Q`). Baseline at `cb2e708`, measured in
this worktree: `Test run with 1409 tests in 1 suite passed` (native,
unfiltered), 97 goldens, 71 guards.

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

What SwiftUI's `Grid` turns out to be (the probe's reading, header items 1–14):
columns sized by their widest cell and rows by their tallest; per-boundary
spacing that goes to 0 beside a Spacer and where no cells meet; at a finite
proposal a **flexibility-ordered, priority-grouped** distribution over cells —
not over columns — with shares recomputed only between groups and columns
committed as their cells finish; layout priority served with no reservation
(so a grid can answer wider than its proposal); spans that widen open or empty
columns first; per-column alignment from the first declaration; anchors; unsized
axes; attributes that pass through modifiers and stop at containers; `GridRow`
as a transparent run of cells whose outermost declaration wins; and, seen from
an enclosing stack, positional zero-spacing edges and no priority.
`LazyVGrid`/`LazyHGrid` are a different, lazy algorithm and are **not** this
stage (`GR-L`).

## 2. Evidence

- **Arms** (probe groups GA, GP, GF, GR, GS, GX, GQ, GL, GU, GW, GG, GE, GN), each
  group with a control that differs (header, "CONTROLS").
- **The reference model** (`solve`, `ModelGrid` in the probe) — a SwiftUI
  `Layout` over the same leaves — compared with `Grid` on generated grids (GZ):
  plain grids 1000/1000, and 300/300 each at infinite proposals, at a zero axis,
  beside a leaf in an `HStack` and in a `VStack`; with attributes 988/1000;
  Spacers 469/500; priority 441/500; non-row children 482/500; spans 376/500;
  infinite proposals with everything 231/300; everything 662/1000; the control
  that ignores commits 212/300 (`GR-B`).
- **The model on the arms** (`model-arms`): 91 of the 95 arms a `Case` spells
  agree; GS4, GS5, GX17 and GX18 do not, and are pinned (test 2.9).
- **The corpus**: 120 generated grids on which `Grid` and the model agree, with
  every leaf rect, as Swift literals (sha256 `d93bc71a…`).
- **Lazy grids**: LZ0–LZ7 (`GR-L`).

## 3. Shape

| layer | file | what |
|---|---|---|
| kernel | `Sources/MetalUILayout/NativeGrid.swift` (new) | `ProposalAxes`; `NativeGridPlan` (cells, row and column indexes, gaps, edges), `NativeGridCell`; the pure solver `solveNativeGrid(_:proposal:measure:)` → `NativeGridSolution` (with its internal bookkeeping counter, `GR-U`); `nativeGridCellRects(_:solution:origin:measure:)`; `nativeGridZeroSpacingEdges(_:axis:)` |
| kernel | `Sources/MetalUILayout/LayoutTree.swift` (localized, `GR-A`) | three stored mark dictionaries and a row-token counter (`GR-W`) declared right after `nativeParents`, cleared by lines appended at the end of `reset`; `NativeNode.grid(NativeGridPlan)` as the last case; a `.grid` arm, last, in `measureNative`, `placeNative`, `markSpacers`, `zeroSpacingEdges`, `nativeLayoutPriority`; one extension at the end of the file holding the registrars and the plan's walk |
| elements | `Sources/MetalUI/Grid.swift` (new) | `Grid`, `GridRow`, `GridCellModifier`, the four cell modifiers, and the public `LayoutPass` registrars (`LayoutPass.frame` and `Frame.tree` are internal to `MetalUI`) |

**Not touched:** `Frame.swift`, `Passes.swift`, `NativeElements.swift`,
`Box.swift`, `ModifiedElement.swift`, `LegacyLowering.swift`,
`LayoutAuthority.swift`, the demo and preview content,
CLAUDE.md/AGENTS.md/README/plan/record README (the integrator's).

**The `.grid` arms elsewhere** (`GR-R`, all probed):

- `markSpacers`: **stop** — a stack does not mark a Spacer inside a grid (GE29 vs
  GE30).
- `zeroSpacingEdges`: **positional** (§4.4) — GE1–GE7, GE16, GE23–GE26.
- `nativeLayoutPriority`: **0**, however many cells (GE8 = GE9 vs GE27; GE11 vs
  GE28), spelled as an explicit `.grid` arm returning 0 before `default`, so
  test 2.10 has a line to mutate.

**Integration** (`GR-A`): both tracks add stored properties to public classes;
the integrator takes a `swift package clean` before the merged suite.

## 4. The algorithm (normative)

**Precedence** (`GR-B`). The probe's `solve`/`ModelGrid` at revision 5 is the
reference for everything it implements, and where this text and the model
disagree on such a rule the model is right and this text is a defect. **The gap
rule is the exception**: the model decides a pair's spacing by the leaf kind
(`isSpacer`), the kernel by the zero-spacing-edge walk that GS12–GS18 probe
(§4.1); the two agree on a bare Spacer cell. Where the model disagrees with
SwiftUI (`model-arms`: GS4, GS5, GX17, GX18), the kernel follows the model and
test 2.9 pins the model's figures.

### 4.1 Marks and the plan (registration)

- `markNativeGridRow(cells, alignment)` allocates a fresh **row token** and
  stores, for every node in `cells`, that token **and** the row's alignment
  (vertical factor only; nil stored as nil), overwriting any earlier token and
  alignment: an enclosing `GridRow` registers after an inner one and its
  declaration wins, nil included (GG3, GG10–GG12, `GR-T`). `cells` may be
  empty (no node is marked).
- `markNativeGridCell(node, columns:, anchor:, columnAlignment:, unsizedAxes:)`
  merges into the node's marks: `columns` — negative traps naming `columns`
  (GT1); if > 1, added to the node's column sum (0 and 1 add nothing); a count
  or a sum above `Int32.max` traps naming `columns` (`GR-S`); `anchor` and `columnAlignment` (horizontal
  factor only) — kept if the node has none yet (the inner modifier registers
  first, so the inner wins); `unsizedAxes` — unioned.
- Both mark registrars trap if the node already has a native parent, each with
  its own message ("a grid row mark written after its node was parented", "a
  grid cell mark written after its node was parented").
- `newNativeGrid(children, alignment, horizontalSpacing, verticalSpacing)`:
  - **first** checks every child with its own precondition, "grid child *i* is a
    legacy node (SA-G)", before any other read of the child;
  - validates spacing — each finite (`SA-J`), the precondition naming
    `horizontalSpacing` or `verticalSpacing`; negative accepted;
  - records parents (`CN-L`);
  - builds the plan:
    - A child's **chain** is the child, then repeatedly `frame`/`padding`/
      `fixedSize`/`aspectRatio`/`layoutPriority`'s child and an overlay
      attachment's child 0, until any other kind (`GR-I`).
    - Its **row token** is the outermost token on its chain. Consecutive
      children with the same **non-nil** token form one row; a child with no
      token is a row of its own, a **non-row cell**. A row's alignment is the
      alignment stored with that outermost token.
    - A row cell's **span** is max(1, the sum over its chain of column sums), its **anchor** and **column alignment** the innermost on its
      chain, its unsized axes the union. A non-row cell has the anchor and
      unsized axes; its column marks and column alignment are ignored (GX13).
    - `ncols` is the largest sum of spans in a row, 1 if there is no row; a
      chain sum or a row sum above `Int32.max` traps naming `gridCellColumns`
      (`GR-S`, by reading). Columns that only a span covers are columns (GX23). Row cells take columns left to right and a span is clamped to the
      columns left. A non-row cell starts at 0 and spans `ncols`.
    - Each cell's **priority** is `nativeLayoutPriority(child)`; its zero-spacing
      edges `zeroSpacingEdges(child, .horizontal)` and `(…, .vertical)`.
    - **Indexes** (`GR-U`): each cell's row, first column and span; the cells of
      each row in order; the single-column cells of each column.
    - **Gaps.** For 1 ≤ j < ncols, `hgap[j]` is the largest pair value over
      pairs (L, R) of adjacent cells in one row with L ending at j−1 and R
      starting at j; 0 if none (one pass per row). For 1 ≤ r < nrows, `vgap[r]`
      is the largest over columns q covered by a cell A in row r−1 and a cell B
      in row r; 0 if none (one merge of the two rows' column intervals). A
      pair's value is the explicit spacing if given, else 0 if L's trailing (A's
      bottom) or R's leading (B's top) edge is zero, else
      `ProposalSpacing.platformDefault` (`GR-D`).
    - **Column alignment of column j**: the first row cell, in row then cell
      order, whose column alignment is set and whose first column is j.

### 4.2 Solve at a proposal P = (Pw, Ph)

State: `curW[ncols]`, `curH[nrows]` start at 0. `absorb(c, a)`: `curH[row] =
max(curH[row], a.h)`; if span 1, `curW[col] = max(curW[col], a.w)`.
`absorbSpan(c, a)`: `have` = Σ curW over the span + its inner gaps; if `a.w >
have`, add `(a.w − have) / |T|` to each column in T, where T is:

- at a proposal that is not nil×nil, the spanned columns that still hold an
  unprocessed single-column cell, if there are any (step 12, GX9);
- otherwise the spanned columns holding **no single-column cell anywhere in the
  grid**, or all spanned columns if that is empty (`GR-F`).

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
     - measure at it, record (proposal, answer), `absorb`, mark it processed.
   - Then `absorbSpan` each spanning cell of the group, in order.
   - Commit every column not yet committed that has no unprocessed span-1 cell
     of priority ≥ `level`; every row likewise over all its cells.
5. The answer is `(Σ curW + Σ hgap, Σ curH + Σ vgap)`.

**Bookkeeping** (`GR-U`): open counts are kept per level and per column and row,
decremented as cells are processed; after the first group the commit check
visits only the columns and rows of the group's cells. The observable result is
the text above.

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

### 4.4 Seen from outside

- **Zero-spacing edges** of a `.grid` node along `.horizontal`: leading ⇔ some
  cell starting at column 0 has a zero leading edge; trailing ⇔ some cell
  ending at column ncols − 1 has a zero trailing edge. Along `.vertical`: top ⇔
  some cell of row 0 has a zero top edge; bottom ⇔ some cell of row nrows − 1
  has a zero bottom edge. A cell's edges are the plan's (`zeroSpacingEdges` on
  the child). No cell: both zero (GE16).
- **Priority**: 0. **Spacer marks**: an enclosing stack's `markSpacers` does not
  enter a grid.

### 4.5 Cost and depth

Per cell: at a nil proposal 1 measurement plus 1 at its slot unless the slot is
its answer; otherwise at most 4 (0×0, ∞×∞, group proposal, slot). GP1's grid is
16 leaf calls and GP2's 15 — the probe's "measured, in order" list lengths.
Bookkeeping is O(cells + ncols + nrows + groups + spanning cells · ncols) per
solve, plus the key sort (`GR-U`). A grid is **one** native level; the solver
runs in functions called from `measureNative`, so no locals are added to
`measureNative`'s own frame (`GR-M`'s depth gate).

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
    /// Marks `cells` as one grid row, overwriting an earlier row mark and its
    /// alignment (GR-A, GR-T, §4.1). Reads `alignment`'s vertical factor only.
    /// Traps on a node that already has a parent.
    public func markNativeGridRow(_ cells: [LayoutNodeID], alignment: ProposalAlignment? = nil)
    /// Merges grid-cell attributes into `node`'s marks (§4.1). `columns` < 0 traps
    /// (GT1), and so does a count or sum above `Int32.max` (GR-S). Reads
    /// `columnAlignment`'s horizontal factor only.
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

Lane 1 ships `markNativeGridCell(_:columns:)` only, with `columns` replacing an
earlier mark; lane 3 adds the other three parameters (source-compatible:
defaulted), the sum and its `Int32.max` checks.

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

/// A grid-cell attribute over every node of `content`, marked after `content`
/// registers; no node, no index, no id.
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

extension LayoutPass {   // in Grid.swift, calling frame.tree (GR-A)
    public func requestNativeGrid(children: [ProposalNodeID], alignment: ProposalAlignment = .center,
                                  horizontalSpacing: Double? = nil,
                                  verticalSpacing: Double? = nil) -> ProposalNodeID
    public func markNativeGridRow(_ cells: [ProposalNodeID], alignment: ProposalAlignment? = nil)
    public func markNativeGridCell(_ node: ProposalNodeID, columns: Int? = nil,
                                   anchor: ProposalAlignment? = nil,
                                   columnAlignment: ProposalAlignment? = nil,
                                   unsizedAxes: ProposalAxes = [])
}
```

`GridRow` and `GridCellModifier`'s untyped `requestGroupLayout` forward to the
typed entry and map ids (no copy, `MC-H`); their `prepaintGroup`/`paintGroup`
forward to `content` once each (no bounds of their own, `GR-K`). Element-level
`Grid.requestProposalLayout` numbers content from cursor 0 under its id and
calls `requestNativeGrid`, as `HStack` calls `requestNativeLinearStack`. Lane 1
ships the `LayoutPass` registrars with `columns` only on the cell mark; lane 3
widens it.

## 6. Lanes

Four, in order (`GR-M`, rebalanced by `GR-Q` finding 11). Each lane: red first;
`swift package clean` before the suite in lanes 1 and 3; `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` unfiltered, reading the `Test run with N tests` line against §7;
0 `error:`/`warning:` besides SwiftPM's notice; `find Tests -name "*.json" | wc
-l` = 97; mutations per `GR-M` after committing, naming every test each
reddens; the demo comparison of `GR-M` (expected **0 differing pixels, scene
identical**, every image, every lane).

**Test leaves.** Kernel tests build the probe's leaves as native leaves
(`fx`, `fl`, `hf`, `fw`, `fh`, `cb`, `cw`, `ch`, `odd`) in a file-private `Arm`
helper modelled on `NativeStackDistributionTests.swift`'s, logging distinct
proposals and call counts. A probe `Spacer()` is `newNativeSpacer()` (its
default 8pt minimum, `CN-F`); `Spacer(minLength: 0)` is
`newNativeSpacer(minLength: 0)`; a written `.layoutPriority(p)` is a
`newNativeLayoutPriority` node. A kernel arm is laid out as the probe's `Probe`
does: `measureNativeLayout` at the arm's proposal, then
`computeNativeLayout(root:proposal:in:)` at that proposal in bounds of its own
answer at the origin (a measured-only arm reads the answer alone). A stack arm
(GE) wraps the grid in `newNativeLinearStack` with the probe's siblings. A rect
is compared with `roundLayout` of the probe's rect; an answer with the probe's
to 1e-9 (or equal infinity). Element tests read prepaint bounds relative to the
`Grid`'s own bounds (a native root is centred, `CN-J`).

"Red before" is what the tree does before the lane; for a test of a new
registrar, type or branch it is its absence ("not in the tree": it does not
compile, or the branch is lane 1's `preconditionFailure`). The **mutation** is
applied after the lane commits and must redden the test named (and the lane
records what else it reddens). Where a row predicts a figure under the mutant
that the lane cannot derive by hand, the lane runs the mutant and records the
figure; a mutant that reddens nothing is reported, not banked.

### Lane 1 — the plan and the nil proposal

**Rulings:** `GR-A`, `GR-C`, `GR-D`, `GR-F` at nil (without the column sum),
`GR-G`'s grid and row alignment, `GR-R`'s edges and Spacer marks, `GR-T`'s row
marks, `GR-S`'s negative trap.

**Source.** `NativeGrid.swift` (plan, indexes, gaps, edges, the solver's nil
branch and a finite branch that is `preconditionFailure("grids lane 2")`, which
no lane-1 test reaches; placement rects; `ProposalAxes`); `LayoutTree.swift` per
§3 with `markNativeGridCell(_:columns:)` only and a chain walk that reads marks
**on the child node alone** (lane 3 walks the chain); `Grid.swift` holding only
the `LayoutPass` registrars. `swift package clean` before the suite.

**New tests.** `Tests/MetalUILayoutTests/NativeGridTests.swift` and
`NativeGridWorkTests.swift` (`@testable import MetalUILayout`, as
`NativeStackDistributionTests.swift`: `measureNativeLayout`,
`lastNativeLayoutWork` and the plan are internal); exit tests in
`NativeGridTrapTests.swift` (plain import, as `NativeBoundaryTrapTests.swift`,
each asserting its stderr fragment); depth tests appended to
`NativeDepthGuardTests.swift`.

| # | test | arms | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aGridSizesColumnsFromTheWidestCellAndRowsFromTheTallest` | GA1, GA4, GP3 (nil) | no registrar | take a column's width from its first cell, not the widest (GA1's b moves) |
| 1.2 | `anEmptyGridOrRowIsNothingAndNonRowChildrenMakeOneColumn` | GA5 (a grid with no children), GA6 (`markNativeGridRow([])`, then a grid with no children), GA8 | no registrar | group consecutive children by token equality **including nil** (GA8's x and y become one row; the lane records the figures) |
| 1.3 | `atANilProposalSpansWidenTheirColumnsAfterEverySingleColumnCell` | GX1–GX7 | no registrar | absorb each span in source order among the single-column cells (GX7's a moves to x 8) |
| 1.4 | `aSpanShortfallAtNilGoesFirstToSpannedColumnsWithNoSingleColumnCell` | GX11 | no registrar | spread over every spanned column (col 1 41, col 2 51) |
| 1.5 | `aCellWhoseSlotEqualsItsAnswerIsPlacedAtTheProposalItWasMeasuredAt` | GR0's control (an `odd` leaf in a 20×20 fixed frame reads 15×15), `#require`d first; GR1; GP3's c placed at nil | no registrar | always place at the slot size (GR1's a reads 15×15 at (2.5, 2.5)) |
| 1.6 | `eachGapIsTheLargestPairSpacingMeetingThere` | the plan's `hgap`/`vgap` for GS1, GS2 vs GS3 (`#require` they differ), GS4, GS5, GS11, GS12–GS18; GS6 and GQ6 laid out at nil | no registrar | put `platformDefault` before every column j ≥ 1 regardless of pairs and edges (GS2's plan reads 8, 8; GS6 reads 76) |
| 1.7 | `explicitGridSpacingIsVerbatimAndNegativeSpacingIsAccepted` | GA2, GA3, GS8 (60×45) | no registrar | clamp a given spacing at 0 (GS8 reads 70×50) |
| 1.8 | `gridAndRowAlignmentPlaceCellsInTheirSlots` | GL1, GL2, GL3, GL9, GL12 | no registrar | ignore the row alignment (GL3's a at y 5) |
| 1.9 | `consecutiveCellsOfOneRowTokenAreOneRowAndTheOutermostRowMarkWins` | kernel spellings of GG3 (two marks, the enclosing one overwriting), GG10, GG11, GG12 (the enclosing mark's alignment replaces the inner's, nil included), GG9 (a linear stack holding marked nodes is a non-row child), and two adjacent rows of equal alignment staying two rows | no registrar | (a) compare rows by alignment instead of token (the adjacent rows merge); (b) keep the inner alignment when the enclosing mark's is nil (GG12's a at y 20) |
| 1.10 | `aGridSeenFromAStackHasPositionalZeroSpacingEdges` | kernel spellings at nil of GE1–GE7, GE16, GE23–GE26: **the stacks' answers, measured only** (`GR-W`: placing would propose the grid a concrete cross axis, lane 2's branch) | no registrar | (a) answer "any cell", as `.custom` does (GE3 reads 68×20, GE24 30×48); (b) answer neither edge (GE1 reads 84×20) |
| 1.11 | `aStackDoesNotMarkASpacerInsideAGrid` | GE29 vs GE30 at nil (`#require` they differ), measured only, and GE29's grid answer 28×20 | no registrar | walk `markSpacers` into a grid's children (GE29 reads 68×20, its grid 20×20) |
| 1.12 | `aGridsWorkAtNilIsOneLeafCallPerDistinctProposal` (`NativeGridWorkTests.swift`) | GP3 = 7 leaf calls; cache hits and misses **derived by hand before the run** and recorded in the doc comment | no registrar | re-measure every cell at its slot even when the slot equals its answer (GP3 reads 8) |
| 1.13 | `resetClearsGridRowMarks` | two nodes marked as one row in generation 1; after `reset(generation: 2)`, two 30×10 leaves at the same indexes under a grid are two non-row cells: **30×28**, not one row's 68×10 | no registrar | do not clear the row-token dictionary in `reset` (68×10) |
| 1.14 | `aNegativeGridCellColumnsTraps` (exit, stderr names `columns`) | GT1 | no precondition | drop it |
| 1.15 | `aLegacyNodeRegisteredUnderANativeGridTraps` (exit, stderr "is a legacy node (SA-G)", the grid's own message) | — (`SA-G`) | no registrar | drop the grid's explicit child check (a later `nativeNode` read still traps, with the generic "contains a legacy node": the stderr check fails) |
| 1.16 | `aNaNGridSpacingTraps` (exit; registration only, no layout; stderr names `horizontalSpacing`) | GS10 | no registrar | drop the finiteness precondition (the child exits `.success`) |
| 1.17 | `anInfiniteGridSpacingTraps` (exit; registration only; `verticalSpacing: .infinity`; stderr names `verticalSpacing`) | GS9 | no registrar | the same |
| 1.18 | `aGridRowMarkOnANodeThatAlreadyHasAParentTraps` (exit, stderr "grid row mark") | — | no registrar | drop the parent precondition in `markNativeGridRow` |
| 1.19 | `aGridCellMarkOnANodeThatAlreadyHasAParentTraps` (exit, stderr "grid cell mark") | — | no registrar | drop the parent precondition in `markNativeGridCell` |
| 1.20 | `aNodeUnderAGridAndASecondParentTraps` (exit, `CN-L`'s message) | — | no registrar | skip `recordParent` in `newNativeGrid` |
| 1.21 | `aChainOf88GridsTraps` (exit; a leaf under **88** nested one-cell grids, 89 levels; the literal, not `maxDepth`) | — (`SA-L`) | no registrar | `NativeLayoutRun.maxDepth` 89 (the child exits `.success`) |
| 1.22 | `aChainOf87GridsDoesNotTrap` (exit `.success`; **87** grids, 88 levels) | — | no registrar | `NativeLayoutRun.maxDepth` 87 (the child traps) |

**Existing tests that change:** `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping`
gains a 13th registrar (`newNativeGrid(children: [leaf(), leaf()])`); its node
count literal 26 → **29**. Nothing else is expected to move; a red existing test
is a finding.

**Depth gate** (`GR-M`): before committing, bisect the debug ceiling of a chain
of one-cell grids on a 1 MB `Thread` by `SA-L`'s method and record it in
`NativeLayoutRun.maxDepth`'s table; below 147, stop and report. **As built: 170**
(`GR-W`); lane 2 re-bisects with its finite solve on the recursion path.

**Expected count:** 1409 + 22 = **1431**; guards 71. **Demo:** 0 px (`GR-M`).

### Lane 2 — the finite solve

**Rulings:** `GR-B`, `GR-E`, `GR-F` at proposals other than nil×nil (step 12,
the overflow), `GR-R`'s priority and answers in stacks, `GR-U`.

**Source.** `NativeGrid.swift`'s finite branch (§4.2, with `GR-U`'s bookkeeping
and counter); the explicit `.grid` arm in `nativeLayoutPriority`. No stored
property changes.

**New tests** in the lane-1 files, plus
`Tests/MetalUILayoutTests/GridCorpus.swift` (the corpus file's literals,
transcribed verbatim with its comment header kept).

| # | test | arms | red before | mutation |
|---|---|---|---|---|
| 2.1 | `aFiniteProposalServesGroupsWithSharesAndCommits` | GP1, GP2, GP7, GA9, GF1–GF9, GF14–GF18 (a greedy `newNativeFrame(maxWidth: .infinity)` cell; a proposal-responsive leaf standing for `Color`), GR2 (placed at 96×200): answers, rects, and GF7's d proposed 120 wide (its log) | not in the tree | GZ0's control: every group offered W′/ncols, commits ignored (GP2's a at 96) |
| 2.2 | `theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis` | GF10, GF11, GF12, GF13 (`#require` GF12 ≠ GF13) | not in the tree | key = the finite sum with ∞ as +∞, one group for equal sums (GF10's b at 96) |
| 2.3 | `oneAxisNilAndInfiniteProposalsAnswerAsTheProbeReads` | GP5, GP6 laid out; GP4 (∞×∞) and GP8 measured only (an infinite answer traps at checkpoint 3 when stored, `SA-J`) | not in the tree | propose a nil grid axis as 0 instead of nil (GP5's a answers 152×0) |
| 2.4 | `anInfiniteAxisSharesInfinityAfterAnInfiniteCommittedColumn` — in `NativeGridTests.swift` (`@testable`), an exit test expecting `.success` whose body measures GP9, GP10, GP11 and `precondition`s each answer and **each leaf's set of distinct proposals**, derived by hand from §4.2 before the run (for example GP11's b: {0×0, ∞×∞, ∞×100}) | GP9–GP11 | not in the tree | compute `(W′ − committed) / open` on an infinite axis: inf − inf is nan, and whether `max` then returns nan (a trap at checkpoint 1) or the column's width (a finite proposal in the set), the child exits `.failure` |
| 2.5 | `higherPriorityGroupsAreServedFirstWithNoReservation` | GQ1, GQ2, GQ3, GQ4, GQ5 (answers 100×100, 130×10, 120×10, 210×120, 266×118) | not in the tree | reserve lower groups' 0×0 widths, as `CN-B`'s stack does (GQ2's a and c read 27) |
| 2.6 | `aBareSpacerCellIsPriorityMinusInfinityAndFlexibleOnBothAxes` | GS1 (s 142×42), GQ7 (`minLength: 0`), GQ8, and GQ9 (a `layoutPriority(0)` node over the Spacer: 200×100, s 152×62), `#require` GQ9 ≠ GS1 | not in the tree | read a cell's priority as 0 (GS1 reads GQ9's figures) |
| 2.7 | `gapsHoldAtFiniteProposals` | GS1, GS2, GS3, GS11, GS12–GS18 laid out at their proposals | not in the tree | subtract no gaps from W′ and H′ (GS1 moves; the lane records it) |
| 2.8 | `aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndWidensItsOpenColumnsFirst` | GX8, GX9 (a 30 wide in its column, b 262), GX10 (a at 60.5, b at 219.5), GX12 (x proposed 300; a 176, b 116 slots) | not in the tree | (a) propose a span the sum of its columns' shares plus inner gaps (probe variant 2; GX10's x moves); (b) drop step 12 (GX9's b reads 231, a's column 61) |
| 2.9 | `theModelsDisagreementsWithSwiftUIArePinned` — pinned wrong on purpose; SwiftUI's figures in its doc comment | the model's figures: **GX17** 200×100, a (0,36 30×10), b (38,0 134×82), c (180,31 20×20), x (25,90 150×10); **GX18** 200×100, a (0,0 104×82), b (112,36 30×10), c (150,36 50×10), x (70,90 60×10); **GS4** 45×40, a (0,0 15×10), c (15,15 30×20), s (0,10 15×30); **GS5** 164×136, a (48,0 40×40), b (34,63 68×10), c (144,48 20×40), d (53,96 30×40); GX19 (control, agreeing with SwiftUI) 200×100, x (80,90 40×10) | not in the tree | skip `absorbSpan` at proposals other than nil×nil (GX17 and GS5 move; the lane records the figures) |
| 2.10 | `aGridPassesNoPriorityToAnEnclosingStack` | kernel spellings of GE8 (46/46), GE10 (36/38/10), GE11 (50/50), with GE27 (0/92) and GE28 (92/8) as controls, `#require` GE8 ≠ GE27 and GE11 ≠ GE28 | not in the tree | `.grid` in `nativeLayoutPriority` passes a one-cell grid's child priority, as a one-child stack does (GE8 reads 0/92, GE11 reads 92/8) |
| 2.11 | `aGridInAStackLaysOutAsTheModelInAStack` | kernel spellings of GE17–GE22, and the rects of GE1–GE7, GE16, GE23–GE26, GE29, GE30 laid out (moved from 1.10/1.11 by `GR-W`) | not in the tree | GZ0's control (GE17 moves; the lane records it) |
| 2.12 | `aGridsWorkAtFiniteProposalsIsOneLeafCallPerDistinctProposal` (`NativeGridWorkTests.swift`) | GP1 = 16 leaf calls, GP2 = 15; hits and misses derived by hand before the run | not in the tree | re-measure every cell at its slot (GP1 reads more; the lane records it) |
| 2.13 | `theGridProbeCorpusAgreesCaseByCase` — reads `GridCorpus.swift`, `#require`s 120 cases and, in this lane, filters to those with no anchor, column alignment or unsized axis: `#require` **18** | the corpus | not in the tree | GZ0's control (the lane records how many of the 18 redden) |
| 2.14 | `theSolversBookkeepingIsLinearInTheCells` (`NativeGridWorkTests.swift`) — `solveNativeGrid` directly on a grid of *n* rows `[fixed 20×10, clampW(0, 50, 10), flexW(10)]` at 300 × nil (three groups): `bookkeepingSteps` at *n* = 200 equals a literal, and `steps(200) − 2 · steps(100)` is at most a constant, both derived by hand from the indexed solver before the run | — (`GR-U`) | **red first** against a first finite branch in the model's shape (a scan of every cell per column and per group, the gaps by cell pairs); the lane records that count, then indexes | replace the column index in the commit check with a scan of every cell |

**Expected count:** 1431 + 14 = **1445**; guards 71. **Demo:** 0 px.

### Lane 3 — cell attributes and the modifier-chain walk

**Rulings:** `GR-F`'s column-sum rule and `columns(0)`, `GR-G` (column
alignment, anchors, inner-wins), `GR-H`, `GR-I`, `GR-S`.

**Source.** `markNativeGridCell` gains `anchor:`, `columnAlignment:`,
`unsizedAxes:`, the column sum and its `Int32.max` checks; the plan walks each child's chain
(§4.1); the solver and placement honour unsized axes, anchors and column
alignment (§4.2, §4.3). `swift package clean` before the suite (new stored mark
fields).

| # | test | arms | red before | mutation |
|---|---|---|---|---|
| 3.1 | `columnAlignmentIsTheFirstDeclarationInRowOrder` | GL4, GL5, GL6, GL7 | no parameter | the last declaration wins (GL6's a at x 20) |
| 3.2 | `aSpanDeclaresColumnAlignmentForItsFirstColumnAndIsNotAlignedByIt` | GL8 | no parameter | align a span by its first column's alignment (c at x 28) |
| 3.3 | `aCellAnchorBeatsColumnAndRowAlignmentAndAppliesToNonRowChildren` | GL10, GL11, GL13 | no parameter | column alignment before the anchor in `fx` (GL10's a at x 30) |
| 3.4 | `onOneNodeTheInnerAnchorAndColumnAlignmentWin` | GL15, GL16, GWI3, GWI4 | no parameter | a later mark overwrites (GL16's c at (40, 98)) |
| 3.5 | `gridCellColumnsDeclaredTwiceAddTheirValuesAboveOne` | GX15 (5 columns), GX16 (2), GWI1, GWI2, GX21 (100_000: 100_001 columns, 71×38), GX23 | lane 1's mark replaces an earlier one (GX15 spans 2) | take the largest mark instead of the sum (GX15 reads 3) |
| 3.6 | `aColumnCountAboveInt32MaxTraps` — divergence pin (`GR-O` 7; GX20's trap and GX22's 32-bit reading in the doc comment): three exit arms expecting `.failure`, registration only, each asserting its stderr names the parameter: (a) one mark of `Int(Int32.max) + 1`; (b) two marks of 2^30 on one node; (c) one row of two cells each marked `Int32.max` under `newNativeGrid` (`gridCellColumns`) | GX20, GX22 | no check (lane 1's replace accepts (a) and (b) and allocates; the arms are not in the tree) | (a) drop the single-count check; (b) drop the sum check; (c) drop the row-sum check — each arm's child then exits otherwise than by the named trap |
| 3.7 | `anUnsizedAxisIsProposedItsCurrentSlotAndItsAnswerStillCounts` | GU1 vs GU2 (`#require` differ), GU3, GU4, GU5, GU6, GU7, GU8, GU11 | no parameter | do not absorb an unsized cell's answer on that axis (GU5 reads 78 wide) |
| 3.8 | `anUnsizedNonRowChildStopsWideningTheGrid` | GU9 vs GU10 | no parameter | ignore unsized axes on non-row cells (GU9 reads 200) |
| 3.9 | `unsizedAxesDeclaredTwiceFormAUnion` | GU12, GU13, GWI5 | no parameter | a later mark replaces the axes (GU12 reads horizontal only) |
| 3.10 | `cellAttributesAndRowTokensAreReadThroughModifierNodesAndNotContainers` — one arm per node kind: fixed and flexible `frame`, `padding` (and a padding with a non-zero inset), `fixedSize`, `aspectRatio`, `layoutPriority`, overlay attachment primary, overlay attachment content side, one-child linear stack, one-child overlay; for each of span, anchor, column alignment, unsized axes and a row token; and GWP's priority arms (padding, flexible frame, aspect ratio stop; overlay primary and one-child stacks pass), which the existing walk already satisfies | GWS/GWA/GWC/GWU/GWP rows 1–4, 6, 11, 12, 15–18 | lane 1 reads marks on the child node only (every wrapped arm reads the unwrapped control's rect) | stop the chain at `padding` (the padding arms redden, and 3.4's and 3.5's GWI arms) |
| 3.11 | `gridCellColumnsZeroLaysOutAsOne` — divergence pin; GX14's SwiftUI figures in the doc comment | GX14: kernel c (10,28 10×10), d (45.5,30.5 5×5), 58×38 (record §20's "GX14as1") | lane 1 already treats 0 as 1; **green on arrival**, kept as the pin | treat 0 as 2 (c spans two columns, d moves to column 2) |
| — | `theGridProbeCorpusAgreesCaseByCase` (2.13) **loses its filter**: `#require` 120 | the corpus | 102 cases were filtered out | each of: GZ0's control; last-declaration column alignment; unsized answers not absorbed — the lane records how many cases each reddens |

**Expected count:** 1445 + 11 = **1456**; guards 71. **Demo:** 0 px.

### Lane 4 — elements, identity and the pipeline

**Rulings:** `GR-J`, `GR-K`, `GR-T`, `GR-V`; `GR-G`/`GR-H`'s element types;
`GR-M`'s real-window captures.

**Source.** `Sources/MetalUI/Grid.swift` (§5). No `swift package clean` needed
(new types only), but take one if an incremental build misbehaves (CLAUDE.md).

`Tests/MetalUITests/GridElementTests.swift` (4.1–4.12);
`Tests/MetalUITests/GridTrapTests.swift` (4.13, plain `import MetalUI`);
`Tests/MetalUITests/GridPipelineTests.swift` (4.14–4.20, through a `Window` over
`FakePlatformWindow`, `makeFakeWindow`); guards in
`Tests/MetalUITests/GridCompileGuards.swift` (plain `import MetalUI`,
`typecheckFile`, `SA-P`). The pipeline tests route through the existing
pipeline, so several are **green on arrival**: each `#require`s a
discriminating control first and names the mutation that reddens its own
assertion, not its control's.

| # | test | arms | red before | mutation |
|---|---|---|---|---|
| 4.1 | `gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI` | GA1, GA3, GP2 (at a 200×100 root), GL3 (`GridRow(alignment: .top)`), GX1 (`.gridCellColumns(2)`), GL5 (`.gridColumnAlignment(.trailing)`), GL11 (`.gridCellAnchor(.trailing)`), GU9 (`.gridCellUnsizedAxes(.horizontal)`), GF14 (`.frame(maxWidth: .infinity)`), GF16 (`Color(.accent)`); nil arms under `.fixedSize()` | no types | `Grid` passes `horizontalSpacing` as vertical (GA3 moves) |
| 4.2 | `everyProposalModifierCarriesAGridCellAttributeAsTheProbeReads` | GWS/GWA/GWC/GWU through MetalUI's spellings: `.padding(Edges)`, `.frame(width:height:)`, `.frame(maxWidth:)`, `.fixedSize()`, `.aspectRatio`, `.layoutPriority`, `.background(ColorToken)`, `.clip`, `.border`, `.opacity`, `.allowsHitTesting(false)`, `.onTap {}`, `.disabled(true)`, `.overlay { }` primary and content side, `.background { }` content side, `HStack { one }`, `ZStack { one }` | no types | `GridCellModifier` drops `.columnAlignment` (every GWC arm reddens; the lane records the rest) |
| 4.3 | `aGridRowOutsideAGridIsItsCells` | GG1 (in a `VStack`: a (0,0), b (5,18), 30×38), GG2 | no types | `GridRow` registers an `HStack` of its cells (GG1 reads one child) |
| 4.4 | `aGridRowInsideAGridRowFlattensWithTheOutermostAlignment` | GG3 (71×20), GG10 (a at y 0), GG11 (a at y 20), GG12 (a at y 10) | no types | the inner `GridRow` marks after the outer one (GG11's a at y 0) |
| 4.5 | `aGridCellModifierOnAGridRowAppliesToEachCellAndLosesToTheCellsOwn` | GG5 (anchor), GG6 (columns: 208×38), GG13 (c keeps `.topLeading`), GG14 (a keeps `.leading`), GG15 (2 + 2 span 4), GG16 (union) | no types | (a) mark only the first node (GG6's d spans 1); (b) mark before the content registers (GG13's c at (40, 98)) |
| 4.6 | `rowsReachTheGridThroughIfAndForEachAndAContainerHoldingARowIsNotARow` | GG8 (`if`, `for`), GG9 (`HStack { GridRow { … } }`) | no types | give every `GridRow` the same row token (GG8's two rows merge) |
| 4.7 | `anEmptyGridRowIsNoRow` | GA7 (`GridRow {}` between two rows: 30×48) | no types | a `GridRow` with no cells registers an empty `ZStack` as its cell (the extra row adds a gap; the lane records the figure) |
| 4.8 | `aGridRowTakesOneIndexAndNumbersItsCellsFromZeroUnderItsOwnID` | ids recorded in prepaint: cell (r, c) is `child(child(grid, r), c)` | no types | forward `parent` and `cursor` through `GridRow` (cells number flat under the grid) |
| 4.9 | `removingACellFromOneRowKeepsAnotherRowsState` | `@State` counter in row 1's first cell, clicked to 1; row 0's second cell removed by an `if`; the counter still reads 1 | no types | the same mutation as 4.8 (the counter reads 0) |
| 4.10 | `aGridCellModifierIsLayoutAndIdentityTransparent` | in **one frame**, `Grid { GridRow { A(); B().gridCellAnchor(.top) } }`, and a control frame without the modifier: B's id is `child(child(grid, 0), 1)` in both, and the native node counts are equal; and a `@State` in B survives the anchor's **value** changing from `.top` to `.bottom` between two frames (a window-level value read in the content) | no types | `GridCellModifier` consumes a cursor index (B's id moves; the state resets) |
| 4.11 | `aFormOfTextCellsOffersTheValueColumnTheRemainder` | GN2's structure with `ProposalText`: labels "Name", "Address", values "Ada Lovelace" and GN's long address, at 200 × nil. Asserted with MetalUI's own measurements (each `ProposalText` measured alone at nil and at the offered width): the label column is the wider label's nil width; the long value's slot width is its answer at 200 − labelColumn − 8; its height exceeds one line; the grid's width is labelColumn + 8 + the value column; row 1's height is the long value's | no types | GZ0's control (the value is offered W′/2; the lane records it) |
| 4.12 | `textRowsTakeTheDefaultRowSpacing` — pinned wrong on purpose; GS7's, GN2's and GN7's SwiftUI 0 in the doc comment (divergence `GR-O` 5) | `Grid { GridRow { ProposalText("A"); ProposalText("B") }; GridRow { ProposalText("C"); ProposalText("D") } }` at nil: row 1's y is row 0's height + 8 | no types | a gap of 0 between two rows whose cells are all leaves (row 1 at row 0's height) |
| 4.13 | `aModifierOnAMultiCellGridRowTraps` — three exit arms expecting `.failure`, each asserting the precondition's stderr fragment: `GridRow { a; b }.padding(Edges(all: 5))` (GG4), `GridRow { a; b }.onTap {}` (GG7), `GridRow { a; b }.background(.accent)`; and a control arm, one cell with the same three modifiers, expecting `.success` | GG4, GG7 | green on arrival (the preconditions exist) | none grid-owned: the pin is of `ModifiedContent.nativeWrapperNode`'s and `OnTapModifier`'s preconditions; the lane mutates each once (shared files, reverted) and records the arms each reddens |
| 4.14 | `aClickOnAGridCellReachesThatCellsOnTap` | a 2×2 grid of `Rectangle(width:height:)`s with `.onTap` each: a click at each cell's centre counts once on that cell; a click in a slot outside its cell's frame (a 10×10 cell in a 40×40 slot) counts nowhere (`OM-I`) | green on arrival; control: the cell-centre click counts | place cells at their slot size (the slot-corner click counts) |
| 4.15 | `aClickInAGridsGapReachesTheGridsOnTapAndACellOutranksIt` | `Grid { … }.onTap` with tappable cells: a gap click reaches the grid, a cell click the cell only | green on arrival; control: the gap click counts on the grid | `Grid.prepaint` skips its content's prepaint (the cell click reaches the grid) |
| 4.16 | `aGridPublishesNothingAndItsCellsTapStillPresses` | `AB-Y`'s shape with a grid: an active client, nothing published, a press by id counts | green on arrival; control: the window built accessibility | `GridRow.prepaintGroup` skips its content (the hitbox is missing; the press is refused) |
| 4.17 | `aGridRootIsCentredAtItsAnswer` | GA1's grid as a window root in a 200×200 window (GP1's proposal, whose rects equal GA1's): its bounds (61, 71, 78, 58) (`CN-J`); cell a at (61, 76) | green on arrival | place cells from (0, 0) instead of the bounds origin (a at (0, 5)) |
| 4.18 | `aGridPaintsOnlyItsCellsInDeclarationOrder` | scene rects equal the cells' fills in row then cell order; the grid and rows add none | green on arrival | `Grid.paint` paints its content twice (twice as many rects) |
| 4.19 | `aDisabledGridRegistersNoCellHitbox` | `Grid { … }.disabled(true)`: no hitbox; control, enabled: one per tappable cell (`#require`) | green on arrival | not grid-owned (`GR-K`): drop the disabled gate in `Frame.registerHandlers` once (shared file, reverted); the disabled arm reddens. `GridRow.prepaintGroup` skipping its content reddens only the control's `#require` and does not count |
| 4.20 | `gridCellsRecordTheirBoundsThroughTheElementGroupEntry` | a `Frame` with `recordsElementBounds`: `elementBounds` holds every cell's id at its placed rect and the grid's at its bounds, and nothing under a `GridRow`'s own id (`GR-K`, `LR-AA`) | green on arrival | `GridRow.prepaintGroup` hands off to each member through a copy of `Element.prepaintGroup` without `recordElementBounds` (the `AnyElement` miss; the cells' entries vanish) |
| G1 | `aGridRejectsLegacyContent` (guard) | `Grid { Box() }` fails; control `Grid { Rectangle() }` compiles | no type (the control fails; the guard is red) | add an overload `init<L: ElementGroup>(alignment:horizontalSpacing:verticalSpacing:content: () -> L) where Content == Rectangle` whose body is `fatalError()` (`Grid { Box() }` compiles) |
| G2 | `aGridRowAlignmentIsAVerticalAlignment` (guard) | `GridRow(alignment: .leading)` fails; control `.top` compiles | no type | make `alignment` a `ProposalAlignment?` |
| G3 | `aGridColumnAlignmentIsAHorizontalAlignment` (guard) | `.gridColumnAlignment(.top)` fails; control `.trailing` compiles | no type | take a `ProposalAlignment` |
| G4 | `aGridCellAnchorIsNinePoint` (guard; divergence `GR-O` 4) | `.gridCellAnchor(UnitPoint(x: 0.25, y: 1))` fails; control `.gridCellAnchor(.topLeading)` compiles | no type | add a public `UnitPoint` and a `gridCellAnchor(_: UnitPoint)` overload |

**Existing tests that change:** `everyModifierWrapperDelegatesEachPhaseExactlyOnce`
gains `Grid`, `GridRow` and `GridCellModifier` arms (no new `@Test`).

**Real windows:** the lock probe, then `capture.sh <scratch> cb2e708 <HEAD>`
(`GR-M`), its table recorded in record §20 (expected 0 differing pixels in
both windows; if the screen reads locked, say so and do not capture).

**Record §20** gains "For the integrator": CLAUDE.md's vocabulary (proposal
types gain `Grid`, `GridRow`, the four cell modifiers, `ProposalAxes`), the
kernel's registrars count (13 `newNative*` and `requestNative*` each, plus two
mark functions each), the divergence and inert lists (`GR-O`), design §4.1 row
G's "as `ProposalLayout`s" and the proposed stage G2 (`GR-L`), the plan's task 7
note, a `swift package clean` before the merged suite, and the suite/guard
counts re-taken after `swift package clean`.

**Expected count:** 1456 + 24 = **1480**; guards 71 + 4 = **75**, each mutated
red once. **Demo:** 0 px; real windows 0 px.

## 7. Order, counts, and what each lane may assume

| lane | assumes | new `@Test` | suite | guards | clean |
|---|---|---|---|---|---|
| 1 | `cb2e708` | 22 | 1431 | 71 | yes |
| 2 | lane 1 | 14 | 1445 | 71 | no |
| 3 | lanes 1–2 | 11 | 1456 | 71 | yes |
| 4 | lanes 1–3 | 24 (4 of them guards) | 1480 | 75 | no |

Counts are design estimates: each lane re-takes them and explains a difference.
The stage-2 track may land first at integration; the counts add.

A lane may substitute a grid-owned mutation for one named here only after
showing the named one fails to discriminate, and records both.

## 8. Deferrals and divergences

Deferrals with owners: `GR-N`. Divergences and inert declarations created:
`GR-O` (numbers assigned at integration). Lazy grids: `GR-L` (proposed stage G2,
after stage 4). The critic round's dispositions: `GR-Q`.
