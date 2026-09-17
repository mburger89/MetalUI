# Grids decisions (plan task 7, stage G)

Rulings for [`specs/2026-09-17-grids-design.md`](specs/2026-09-17-grids-design.md),
on `feat/grids` from `cb2e708`. Ids are **lettered**, `GR-A`…`GR-AF`; next
unused is **`GR-AG`**. A bare `GR-3` is a typo, not a citation.

**Status, 2026-09-17: lanes 1 and 2 built** (`GR-W` and `GR-X` record their
as-built amendments);
the design was revised after **two** critic rounds — `GR-Q` records how each of
the first round's fourteen findings was applied, `GR-Y` how each of the second
round's fifteen was, and `GR-Z`…`GR-AF` are that round's new rulings. Baseline measured in this worktree at `cb2e708`: `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` → `Test run with 1409 tests in 1 suite passed after 42.821
seconds`, 0 `error:`, no `warning:` besides SwiftPM's deprecation notice;
`find Tests -name "*.json" | wc -l` 97; guards 71 (73 `canTypecheck` hits, less
the declaration in `Typecheck.swift` and the comment in `UnitSafetyTests`).
After the second critic round's code (`1b6c698`): **1449** tests, 97 goldens,
71 guards.

Probes (arm ids below are theirs):

- `docs/probes/swiftui-grid.swift`, **revision 6** (`ed3471e`, `c1f793d`,
  `01a3462`, `ce84b8b`, `beb4242`, `c0c499b`, `ea591cd`, `1844256`), `/usr/bin/swift`, Apple Swift 6.4,
  macOS 27.0 (26A428). Default run exit 0, twice, byte-identical, recorded in
  its header with the reading; modes `corpus`, `model-arms`, `classify-spans`,
  `divergences` (exit 0, twice each, byte-identical), `span-row`, `huge-columns`
  and `trap-negative-columns` (the last two exit 133 by design, twice each). It
  holds the
  **reference model** (`solve`, `ModelGrid`), the fuzz comparison of that model
  with `Grid` (GZ0–GZ12, with a control GZ0 that must disagree), and the model's
  run over every arm a `Case` can spell (`model-arms`). **Revision 6 is additive**:
  the default run's stdout is byte-identical to revision 5's and the corpus's
  sha256 is unchanged, both re-measured after the edit.
- `docs/probes/swiftui-grid-default-run.txt` — the **default** run's stdout,
  sha256 `5d203038…172f61ba`, 435 lines, committed at revision 6 so the reading
  in the probe's header can be diffed against a re-run rather than checked arm
  by arm (`GR-Y` finding 14).
- `docs/probes/swiftui-grid-corpus.txt` — the `corpus` mode's stdout at revision
  5, 120 grids on which SwiftUI and the model agree, sha256
  `d93bc71a…a886f366` recorded in both files. Revisions 1–4's corpus is
  superseded (`GR-Q` finding 1).
- `docs/probes/swiftui-grid-divergences.txt` — the `divergences` mode's stdout,
  sha256 `36021ffc…8c9bdaf8`: the **65** grids the corpus run discards, each
  with SwiftUI's answer and the model's (`GR-AA`).
- `docs/probes/swiftui-lazy-grid-scope.swift` (`ed3471e`) — LazyVGrid/LazyHGrid
  against Grid, and laziness; exit 0, run twice, byte-identical.

**Call counts.** The containers decisions note that SwiftUI's duplicate
flexibility probes vary by OS release. The grid probe's "measured, in order"
lists are distinct calls only (SwiftUI caches), and the kernel's work literals
are its own count of distinct `(node, proposal)` pairs, which the lists happen
to equal on GP1/GP2 under the model; a later OS changing its list does not
change a ruling.

---

## GR-A — a grid is a kernel `NativeNode` case with registration-time marks, not a `ProposalLayout`

**Ruling.** `LayoutTree` gains one built-in case, `.grid(NativeGridPlan)`, and
three public registrars: `markNativeGridRow(_:alignment:)`,
`markNativeGridCell(_:columns:anchor:columnAlignment:unsizedAxes:)` and
`newNativeGrid(children:alignment:horizontalSpacing:verticalSpacing:)`. Marks
are written by the element layer before the grid registers; the grid resolves
its plan (rows, spans, attributes, priorities, zero-spacing edges, gaps and the
row/column indexes of `GR-U`) **once, at registration**, and stores it in the
case. The solver is a pure function in a new file,
`Sources/MetalUILayout/NativeGrid.swift`, called from the `.grid` arms of
`measureNative`/`placeNative`.

**Why not `ProposalLayout`** (`SA-B`: "the built-ins stay cases"; `SA-D`: the
proxies expose priority, `isSpacer` and a cached `sizeThatFits`, nothing else):

1. A grid needs per-cell facts that live **below** its children: which
   `GridRow` a cell came from, `gridCellColumns`/anchor/column alignment/unsized
   axes written inside a padding or a frame (probe GW), and a Spacer's
   zero-spacing edges seen through wrappers (GS12–GS17, `CN-H`'s walk). The
   public proxy cannot reach any of them without widening `ProposalLayout`'s
   contract for one built-in.
2. A row is not a layout node in SwiftUI (GG1, GG2: outside a Grid a `GridRow`
   is its cells). A `ProposalLayout` over rows would have to nest a layout per
   row, and a row layout cannot place its cells at column widths only the grid
   knows.
3. The kernel's existing walks (`nativeLayoutPriority`, `zeroSpacingEdges`) are
   already the probed rules (GWP, GS12–GS17), so a case reuses them unchanged.
4. A grid seen from a stack needs its own edge rule (`GR-R`), which a
   `ProposalLayout` would get as `.custom`'s "any child" — GE3 refutes that.

**Placement in shared files** (the stage-2 track edits `LayoutTree.swift`,
`Frame.swift` and `Passes.swift` in parallel; critic finding 10):

- `LayoutTree.swift`: the three stored mark dictionaries are declared
  immediately after `nativeParents`; their clearing lines are appended at the
  end of `reset(generation:)`; `case grid(NativeGridPlan)` is the **last** case
  of `NativeNode`; each `.grid` arm is the **last** arm before any `default` in
  `measureNative`, `placeNative`, `markSpacers`, `zeroSpacingEdges` and
  `nativeLayoutPriority`; the registrars and the plan's walk are one extension
  at the end of the file.
- **`Frame.swift` and `Passes.swift` are not edited.** `Frame.tree` and
  `LayoutPass.frame` are internal to `MetalUI`, so the `LayoutPass` registrars
  (`requestNativeGrid`, `markNativeGridRow`, `markNativeGridCell`) are a public
  extension in `Sources/MetalUI/Grid.swift` that calls `frame.tree` directly.

**Merge state, re-checked in the second critic round** (finding 15). `git diff
cb2e708..feat/engine-stage-2 -- Sources/MetalUILayout/LayoutTree.swift` is one
hunk, in `placeNative`'s `.padding` case (`LR-AU`), ~85 lines above this track's
`case .grid:` in the same `switch`: textually mergeable. Neither track touches
`NativeElements.swift`; the other track's `Frame.swift`/`Passes.swift` edits are
files `GR-A` deliberately leaves alone. Three integration items, the third new:

1. both tracks add stored properties to public classes → **`swift package
   clean`** before the merged suite;
2. `case grid(NativeGridPlan)` forces only same-file switches, all of them
   already updated here;
3. **`LR-AU` changes where a padded child is placed, and lanes 3–4 have
   padded-cell arms** (3.10's padding with a non-zero inset, 4.2's
   `.padding(Edges)`). The two rules agree only while a padding's rect equals
   its own answer, which holds inside a grid because cells are placed at their
   answers (spec §4.3) — so the arms should survive, but the integrator
   **re-derives that**, rather than only re-running them green.

**Cost if wrong.** Three stored properties on a public class read across a
module boundary: **`swift package clean` before the lane-1 and lane-3 suites**
(`CN-R`), and **at integration**, since both tracks add stored properties to
public classes. If a later task wants grids as a public `ProposalLayout`, the
solver is already a pure function over a plan and a measure closure.

---

## GR-B — the kernel is the probe's reference model; where the model and SwiftUI disagree, the kernel follows the model and says so

**Ruling.** The grid kernel implements the reference model in
`docs/probes/swiftui-grid.swift` at revision 5 (`solve` and
`ModelGrid.placeSubviews`), whose rules are spec §4. It is not a SwiftUI source
port: it was fitted to the arms and tested against `Grid` on generated grids.
**Precedence** (critic finding 7): the model is normative for everything it
implements **except the gap rule**, where the kernel uses the zero-spacing-edge
walk GS12–GS18 probe (`GR-D`); on a bare Spacer cell, the only Spacer the model
knows, the two agree.

**Evidence** (GZ, fixed seeds, sizes within 0.01 and every leaf rect):

| group | agree |
|---|---|
| GZ0 control, the model with commits ignored | 212 of 300 (must disagree) |
| GZ1 plain grids | **1000 of 1000** |
| GZ2 alignment, anchors, column alignment, unsized axes, explicit spacing | 988 of 1000 |
| GZ3 Spacer cells (bare since revision 5) | 469 of 500 |
| GZ4 layout priority | 441 of 500 |
| GZ5 non-row children | 482 of 500 |
| GZ6 spans | 376 of 500 |
| GZ7 infinite proposals, answers only, everything | 231 of 300 |
| GZ8 everything | 662 of 1000 |
| GZ9 plain grids, infinite proposals (answers) | **300 of 300** |
| GZ10 plain grids, a zero proposal axis | **300 of 300** |
| GZ11 a plain grid beside a leaf in an `HStack` | **300 of 300** |
| GZ12 a plain grid below a leaf in a `VStack` | **300 of 300** |

**The model on the arms** (`model-arms`, new at revision 5): of the 95 arms a
`Case` spells (every one's SwiftUI answer checked against the arm's own line, 0
transcription mismatches), **91 agree**. The four that do not are pinned as
the model's figures, the SwiftUI figures in the pin's doc comment (spec test
2.9): GS4 (a Spacer below a priority-0 cell in one column: SwiftUI 90×40, model
45×40), GS5 (a column holding only a span: SwiftUI 76.67×136, model 164×136),
GX17 and GX18 (the span overflow, `GR-F`). Before revision 5 the spec named GS4,
GS5 and GX9 as agreement arms without the model having run on them; GX9 now
agrees through the model's step 12 (`GR-F`).

**The exit test** is `theGridProbeCorpusAgreesCaseByCase`: the 120 grids of
`docs/probes/swiftui-grid-corpus.txt`, each built from native leaves standing for
the probe's leaf kinds, laid out at its proposal at (0, 0), and compared with
the recorded answer and with `roundLayout` of every recorded rect. Lane 2 runs
the **18** cases with no anchor, column alignment or unsized axis; lane 3 runs
all 120.

**The GZ table is a dated baseline, not a report** (second critic round, finding
3; `GR-AA`). The counts above were taken at probe revision 5 on 2026-09-17 and a
later change to the model or the kernel **must not lower any of them**: a change
that trades agreement in one group for another says so and re-takes the whole
table, as `GR-F` did for step 12.

**Why a corpus of agreeing cases.** It tests SwiftUI's behaviour where the
model reproduces it, which is what the kernel ports. The corpus is therefore
structurally unable to see the divergence — which is why the 65 discarded cases
are committed too, as `docs/probes/swiftui-grid-divergences.txt`, and a handful
of them is pinned wrong on purpose (`GR-AA`, test 3.12). The disagreement is
divergence `GR-O` item 2.

**Cost if wrong.** A rule the model gets right only by coincidence on the
corpus would be ported as fact. The GZ counts bound that: the plain-grid rules
hold on 2200 independent generated grids (GZ1, GZ9–GZ12); the interaction rules
do not, and are named as such.

---

## GR-C — cells, rows, nil proposals and the placement proposal

**Ruling** (reading 1 and 3):

- A column is as wide as its widest single-column cell, a row as tall as its
  tallest cell; a cell is placed in its column-width × row-height slot, centred
  by default; the grid answers the sums plus gaps (GA1 78×58 vs control GA0).
- An empty `Grid`, a `Grid` of empty rows: 0×0 (GA5, GA6). An empty `GridRow` is
  no row (GA7). A grid whose children are all non-row children has one column
  (GA8, GA9).
- At nil×nil every cell is measured once at nil; single-column cells widen
  their columns, then each spanning cell widens its columns (`GR-F`), in
  source order (GP3; GX7 equals GX1 whichever row declares the span).
- **The placement proposal** is the slot size, except that a cell whose slot
  equals its answer is placed at the proposal that answer was measured at (GR1
  at nil, GR2 at 96×200, control GR0). The kernel reproduces this rather than
  proposing the slot: a leaf whose answer at its own size differs (`odd`) is
  observable, and the rule also saves the slot re-measurement (GP3: c is not
  re-measured).

**Cost if wrong.** The placement-proposal rule is invisible to every pure,
idempotent leaf; if it is wrong the only effect is on non-idempotent content,
and the rule is pinned by test 1.5.

---

## GR-D — spacing: the largest pair spacing at each boundary

**Ruling** (reading 2):

- Default 8 on both axes, explicit spacing verbatim (GA1–GA3). **Negative
  spacing is accepted and unclamped** (GS8 60×45), as `SA-J` accepts it on
  stacks. **NaN and ±∞ trap** at registration, the precondition naming
  `horizontalSpacing` or `verticalSpacing`: SwiftUI answers nan and inf (GS9,
  GS10), the rule `SA-J` applies to stacks.
- The gap before column *j* is the **largest** spacing of any pair of adjacent
  cells in one row that meet at *j*, and **0 where no pair meets there** (GS5,
  GS6); the gap before row *r* the largest over pairs of cells covering one
  column in rows *r−1* and *r* (GS4).
- A pair's spacing is the explicit spacing when one is given (GS11: 12 beside a
  Spacer); otherwise 0 when the left (upper) cell's trailing (bottom) edge or
  the right (lower) cell's leading (top) edge is a zero-spacing edge, else 8
  (GS1 190, GS2 48 vs GS3 64). Zero-spacing edges are the kernel's existing
  `zeroSpacingEdges` walk (`CN-H`): through a frame (GS12, GS17 vs GS18), a
  one-child stack or `ZStack` (GS14, GS15), a padding edge whose inset is 0
  (GS13), and not an overlay's content side (GS16). A grid cell's Spacer is
  unmarked — no enclosing stack marks it (`GR-R`, GE29) — so both its edges are
  zero.
- **Not adopted:** SwiftUI's font-derived spacing, 0 between rows of `Text`
  (GS7 36×32; GN2, GN5, GN7 at finite widths). MetalUI gives 8, as `CN-H` does
  for a `VStack` of `ProposalText`. A divergence (`GR-O`), owned by task 11
  (text edges, as `LR-N` already lists), **pinned** by spec test 4.12.

**Cost if wrong.** A boundary rule that differs by view kind in a way GS did not
exercise (for example a `ProposalText` beside a Spacer inside a padding) would
place a column 8pt off; the walk is the one already probed for stacks.

---

## GR-E — finite proposals: flexibility groups, shares and commits; priority and Spacer

**Ruling** (reading 4 and 5; spec §4.2 states it as an algorithm):

1. Every cell is measured at 0×0 and ∞×∞ (GP1).
2. Its **key** is (layout priority, descending; the number of proposal-finite
   axes whose ∞ answer is infinite; the sum over the other proposal-finite axes
   of ∞ answer − 0×0 answer). An axis whose proposal is nil counts for neither
   (GF12 vs GF13). One infinite axis sorts before two (GF10), a finite range of
   150 before one infinite axis (GF11). Equal keys form a group, source order
   within it.
3. At a group's start, per axis: the **share** is (W′ − Σ committed column
   widths) ÷ the number of **open** columns (columns with an unprocessed
   single-column cell of this group's priority), floored nowhere, and **∞ on an
   infinite proposal axis whatever is committed** (GP9–GP11: SwiftUI never
   produces nan there). Each cell is proposed max(share, its column's current
   width) (GF7), nil on a nil axis (GP5, GP6). Rows likewise.
4. After the group, a column with no unprocessed single-column cell of this
   priority **or higher** is committed, permanently (GP2, GF1, GF8). Rows
   likewise over all their cells.
5. The grid answers the sums; it does not fill its proposal with fixed content
   (GP1) and answers ∞ when a cell does (GP4, GP8).

**Priority** is `nativeLayoutPriority` (`CN-D`'s walk), which is what GWP reads
for grids (passes background, overlay primary, one-child stacks; stops at
padding, flexible frame, aspect ratio, overlay content). Higher groups are
served **with no reservation** for lower ones, and the grid can answer wider
than its proposal (GQ2 130 at 100, GQ3 120, GQ4 210×120). This differs from
`CN-B`'s stack, which reserves lower minimums; the grid is its own algorithm.
**A bare Spacer is priority −∞** (GS1: s at 142×42; GQ6–GQ8): SwiftUI's subview
proxy reads −∞ for a bare Spacer, through a background or a `gridCellColumns`,
and the written value for a `.layoutPriority`, **0 included** (GQ10), so
`Spacer().layoutPriority(0)` is an ordinary flexible cell (GQ9: 200×100, s
152×62). The kernel's walk returns exactly that (a `layoutPriority` node's
value, whatever it wraps). A Spacer is flexible on both axes (unmarked,
`CN-C`, `GR-R`).

**Cost if wrong.** GZ4 (441/500) and GZ3 (469/500) are the measured limits of
this rule set with priorities and Spacers; a user layout in the remainder lays
out differently from SwiftUI by a column's share, in either direction (GS4:
SwiftUI 90 wide, the kernel 45). Recorded as a divergence.

---

## GR-F — spans and non-row children; SwiftUI's span overflow is not ported

**Ruling** (reading 6):

- `gridCellColumns(n)` spans *n* columns, **never clamped** (`GR-Z`, second
  critic round finding 1: the grid's column count is the widest row's sum of
  spans, so the columns left in a row are always at least the cell's span).
  GX6's `[a, b] [x span 5]` answers 58 because columns 2–4 are empty and take no
  width, and GX21's `columns(100_000)` genuinely covers columns 0…99_999. A
  column that only a span covers is a column (GX23: its third
  column takes x's whole shortfall). A non-row child is one cell spanning every column and
  ignores `gridCellColumns` (GX3, GX4, GX13; GX13 pinned since the second critic
  round by test 1.2's fourth arm).
- A span's width shortfall (its answer minus its slot) is spread equally over a
  target set of its spanned columns. **At a nil×nil proposal** the targets are
  the spanned columns that hold no single-column cell anywhere in the grid, or
  all of them if every one does (GX1 51/41; GX11 col 1 82, col 2 10). **At any
  other proposal** (model step 12, revision 5) the targets are first the spanned
  columns that still hold an unprocessed single-column cell, then that nil rule
  (GX9: x's shortfall goes to b's open column, and a's committed column stays
  30, where revision 4's model gave a 61 and b 231; GX10: no open column, both
  widen to 151/141).
- At a finite proposal a spanning cell is proposed W′ minus, for each column
  outside it, the share if the column is open or its current width if not,
  plus its inner gaps (GX8 300×46, GX10 300×82, GX12 300×96); it does not keep
  its columns open (GX9: b at 262); its shortfall is applied after its group's
  single-column cells (GX10 151/141).
- **Two `gridCellColumns` on one view add their values above 1** (GX15: 3 and 2
  span 5; GX16: 2 and 1 span 2; GWI1, GWI2 through padding; GG15 through a
  `GridRow`). Ported: odd, but probed in both orders and through two wrappers.
- `gridCellColumns(-1)` **traps** (GT1: exit 133); the kernel traps with the
  parameter named (`SA-J`). Counts above 32 bits: `GR-S`.
- `gridCellColumns(0)` **lays out as 1**. SwiftUI places such a cell in column 0
  without consuming it (GX14: c at x 0, d shares column 0). Accepted (`SA-J`:
  SwiftUI does not reject it) and not reproduced: a divergence (`GR-O`).

**Not ported: SwiftUI's span overflow.** When a span's shortfall is spread while
a spanned column is still open, SwiftUI can propose the open column more than
the grid has: GX17 answers **284×100 at 200×100** (b proposed 218) for content
that fits in 200, and GX18 answers **231.33** where control GX19, which differs
only in the non-row child's width (60 → 40), answers 200. The model answers
**200×100** for both (spec test 2.9 lists its rects). A grid wider than its
proposal for fitting fixed content is a defect, not a design `EP-5` asks
MetalUI to follow. Pinned wrong on purpose; divergence (`GR-O`), no owner.

**What the span residual is** (critic finding 4; `classify-spans`, GZ6's seed,
revision 5). Of the model's **124** disagreements with SwiftUI on 500 grids with
spans:

| symptom | nil×nil | nil width | nil height | finite × finite | total |
|---|---|---|---|---|---|
| SwiftUI wider than a finite proposal, the model within it (the overflow) | — | — | 0 | 3 | **3** |
| the model wider than SwiftUI | 1 | 1 | 12 | 50 | **64** |
| SwiftUI wider than the model, not the overflow | 0 | 0 | 7 | 24 | **31** |
| equal sizes, different rects | 0 | 1 | 8 | 17 | **26** |

By one-rule model variants: 60 of the 124 agree under a variant that keeps a
span's columns open while it is unprocessed (variant 4: 18), counts a column
holding no single-column cell as open for every share and never commits it
(variant 6: 16), or either (26); 1 under spreading every shortfall over all
spanned columns; 63 under none. Neither open-column variant was adopted: the
design round measured spans that block a commit as worse on non-row children
(record §20 step 4), and variant 6 lowered GZ8 from 657 to 646 while raising
GZ6 from 374 to 410 (measured before step 12).

**Cost if wrong** (restated). With spans at a non-nil proposal the kernel can
answer **wider or narrower** than SwiftUI: wider in 64 of GZ6's disagreements
(150×nil: the model 193, SwiftUI 184.5; 60×60: 138 vs 126), narrower in 31
(300×200: the model 66, SwiftUI 126, with no overflow involved), and equal-sized
with different rects in 26. Only 3 of 124 are the overflow ruled out above. A
layout with spans can therefore differ from SwiftUI by up to a column's share;
the overflow is the one case where the kernel is deliberately different.

---

## GR-G — alignment: grid, row, column, anchor

**Ruling** (reading 7):

- `Grid(alignment:)` is the nine-case `ProposalAlignment` (SwiftUI's
  `Alignment`), both axes, and places non-row children (GL1, GL2, GL12).
- `GridRow(alignment:)` is `VerticalAlignment?` (`CN-I`'s type) and overrides
  the grid vertically for its cells (GL3, GL9). Nested rows: `GR-T`.
- `gridColumnAlignment(_:)` takes `HorizontalAlignment` and sets the horizontal
  alignment of the whole column from any row (GL4, GL5). **The first
  declaration in row order, then cell order, wins** (GL6, GL7). A spanning cell
  declares it for its first column and is not itself aligned by it (GL8).
- `gridCellAnchor(_:)` overrides both, on both axes, and applies to a non-row
  child (GL10, GL11, GL13).
- **On one view the inner declaration wins** for anchor and column alignment
  (GL15, GL16; GWI3, GWI4 through padding; GG13, GG14 through a `GridRow`).
- **The anchor is a `ProposalAlignment`, not a `UnitPoint`.** SwiftUI accepts
  any unit point (GL14: (0.25, 1) puts a at (10, 20)). MetalUI has no
  `UnitPoint`, and the kernel's anchors (`PlacementSubview.place`) are nine-case;
  the nine SwiftUI spellings (`.topLeading` …) are source-compatible. A
  divergence (`GR-O`), owned by task 11, **pinned** by guard G4 (spec lane 4:
  `.gridCellAnchor(UnitPoint(x: 0.25, y: 1))` does not compile).
- **The kernel reads one factor of two nine-case parameters**:
  `markNativeGridRow(alignment:)` reads the vertical factor and
  `markNativeGridCell(columnAlignment:)` the horizontal one, as
  `newNativeLinearStack(alignment:)` reads only its cross factor. The element
  API cannot pass the other half (`VerticalAlignment`, `HorizontalAlignment`);
  a kernel caller can, and it is inert (`GR-O`'s inert list).

**Cost if wrong.** A caller needing a fractional anchor cannot spell it; no
nine-point placement differs.

---

## GR-H — `gridCellUnsizedAxes`

**Ruling** (reading 8): on an unsized axis a cell is proposed its current slot
on that axis — the spanned columns' current widths plus inner gaps, or its
row's current height — instead of a share (GU1 30×172 vs GU2; GU6 152×10). Its
answer **still widens** its column or row (GU4, GU5 148; GU6 78×78). Its key and
group are unchanged. A divider-like non-row child stops widening the grid (GU9
58 vs GU10 200); a lone cell unsized on both axes answers 0×0 (GU11).
Declarations on one view form a **union** (GU12, GU13, GWI5; GG16 through a
`GridRow`).

**The ordering variant was measured, not chosen by reading** (record §20): on
400 generated grids with attributes (seed 31), counting an unsized axis in the
key and keeping it in its group agreed 400 of 400; counting it but sorting
unsized cells after sized cells of an equal key agreed 398; excluding the axis
from the key agreed 374, with either grouping.

**The type** is a new kernel `ProposalAxes: OptionSet` with `.horizontal` and
`.vertical`, so `.gridCellUnsizedAxes(.horizontal)` and `[.horizontal,
.vertical]` spell as in SwiftUI. MetalUI has no `Axis.Set`; `ProposalStackAxis`
is a two-case enum and cannot express a set.

**Cost if wrong.** GZ2's 12 disagreements of 1000 all involve an unsized axis;
the rule is the best of three measured variants, not an exact port.

---

## GR-I — which wrappers carry a cell attribute

**Ruling** (reading 9). The plan resolves each grid child's attributes by
walking its **modifier chain**: from the child node through `frame`, `padding`,
`fixedSize`, `aspectRatio`, `layoutPriority` and an overlay attachment's
**primary** (child 0), stopping at anything else (`linearStack`, `overlay`,
`scrollViewport`, `custom`, `leaf`, `spacer`, `grid`). MetalUI's paint-only
proposal modifiers (`background(ColorToken)`, `clip`, `border`, `opacity`,
`allowsHitTesting`, `onTap`) and `EnvironmentScope` register no node, so they
carry attributes by construction.

This is GW's reading: spans, anchors, column alignment and unsized axes pass
through padding, both frames, fixedSize, background/overlay primary, clipped,
border, opacity, allowsHitTesting, aspectRatio, layoutPriority, onTapGesture
and disabled (GWS/GWA/GWC/GWU 1–14) and not through a one-child HStack or ZStack
or the overlay/background content side (15–18). The walk is `markSpacers`'
list without the overlay content side (which K2e reads for spacer marks but GW
rejects for grid attributes).

**Combination along the chain**: row membership from the **outermost** row mark
(`GR-T`); anchor and column alignment from the **innermost** mark; columns the
sum of the marks above 1 (`GR-F`, `GR-S`); unsized axes the union.

**Marks on a node that never sits under a grid are inert** (nothing reads them;
`GR-O`'s inert list), as is a `GridRow`'s alignment and a `GridCellModifier`
outside a grid (GG1, GG2).

**Cost if wrong.** A wrapper MetalUI adds later that registers a node needs an
arm in this walk, or attributes written inside it vanish silently; test 3.10
enumerates the node kinds and must gain an arm with it.

---

## GR-J — the element API; `GridRow` is a group with its own identity

**Ruling.** In `Sources/MetalUI/Grid.swift`:

- `Grid<Content: ProposalElementGroup>: ProposalElement`, `init(alignment:
  ProposalAlignment = .center, horizontalSpacing: Pixels? = nil,
  verticalSpacing: Pixels? = nil, @ElementBuilder content:)` — SwiftUI's
  argument order. Its content numbers from 0 under its id, as `HStack`'s does.
- `GridRow<Content: ProposalElementGroup>: ProposalElementGroup` — **a group,
  not an `Element`**: it contributes its cells' nodes (outside a Grid they are
  the enclosing container's children, GG1, GG2) and marks them as one row. It
  **consumes one cursor index** and numbers its cells from 0 under its own id,
  entered through `GlobalElementID.enteringGroupMember` (`MC-H`), as
  `Component`'s typed default does. Its untyped `requestGroupLayout` forwards to
  the typed entry and maps the ids, so there is no copy to pin (`MC-H`).
- `GridCellModifier<Content: ProposalElementGroup>: ProposalElementGroup` with
  `.gridCellColumns(_: Int)`, `.gridCellAnchor(_: ProposalAlignment)`,
  `.gridColumnAlignment(_: HorizontalAlignment)` and
  `.gridCellUnsizedAxes(_: ProposalAxes)` on `extension ProposalElementGroup`:
  **layout- and identity-transparent** (no node, no cursor index, `parent` and
  `cursor` forwarded), `EnvironmentScope`'s shape, marking **every** node its
  content returns **after** its content registers — so on a `GridRow` it
  applies to each cell, as SwiftUI's does (GG5, GG6), and loses to a cell's own
  attribute (GG13, GG14; `GR-T`).
- The three `LayoutPass` registrars are a public extension in `Grid.swift`
  (`GR-A`).
- **No legacy spelling** (the task text); `Grid`'s content is
  `ProposalElementGroup`, so legacy content does not compile (guard G1).

**Why a row has identity.** Stable ids under the grid: a cell's id is (grid, row
index, cell index), so removing a cell from one row does not renumber another
row's cells and move their `@State` (test 4.9). With a transparent row every
cell would number flat under the grid and a vanishing cell in row 0 would shift
every later row's state. The universal trailing-sibling rule still holds inside
a row and between rows (a vanishing `if` around a row makes the next row adopt
its id). No SwiftUI identity claim is made (not probed); task 8 owns the audit.

**Every proposal modifier on a multi-cell `GridRow` traps** (restated, critic
finding 6). `ModifiedContent.nativeWrapperNode` (`NativeModifiedContent.swift`)
preconditions exactly one node for **every** `LayoutModifier` case, including
the paint-only `.background(ColorToken)`, `.clip`, `.border`, `.opacity` and
`.allowsHitTesting`, which register no node of their own; `OnTapModifier`
preconditions one node too (`NativeTappable.swift:27`), and so do the
`.overlay`/`.background { }` primaries. Only the groups that register nothing —
`GridCellModifier` and `EnvironmentScope` (`.disabled`, `.environment`) — pass
over several cells. SwiftUI applies each modifier to each cell (GG4 padding,
GG7 onTapGesture). On a one-cell row a modifier wraps the cell, and `GR-I`'s
walk keeps the wrapper a row cell. A divergence (`GR-O`), owned by task 8
("`Group` … modifier placement"), pinned by test 4.13's three exit arms
(`.padding`, `.onTap`, `.background(ColorToken)`).

**Cost if wrong.** If task 8 decides rows should be identity-transparent,
changing it resets every grid cell's state once; nothing else moves.

---

## GR-K — the pipeline: hit testing, accessibility, disabled, paint, animation, the bounds log

**Ruling.** A grid and a row paint nothing and register nothing of their own.

- **Hit testing.** An `.onTap` on a cell registers the cell's **frame** (its
  placed rect, not its slot), and on a grid the grid's frame — `OM-I`'s default
  region, already a divergence from SwiftUI's shape-based region; nothing new.
  Content registers after its container's own hitbox, so a cell outranks an
  enclosing grid's `.onTap`.
- **Accessibility.** Nothing on the proposal path publishes (`AB-Q`, `AB-Y`); a
  grid is no exception, and a cell's `.onTap` still presses through the bridge.
  Task 12 owns proposal-path accessibility.
- **Disabled.** `.disabled` on a grid is an `EnvironmentScope` around it; the
  gate in `Frame.registerHandlers` suppresses every cell's hitbox. The gate is
  shared code: its test through a grid (4.19) is a regression pin whose
  discriminating mutation is that gate's, applied and reverted in a shared file.
- **Animation.** Nothing on the proposal path animates (CLAUDE.md); grids snap.
- **Root.** A native grid root is centred at its answer (`CN-J`), with no code
  of its own.
- **The bounds log** (`LR-AA` item 3, critic finding 14). `LR-AA` requires a new
  group entry that hands off to its members to record their bounds. `GridRow`
  and `GridCellModifier` are **exempt: they have no node and no bounds**, and
  they hand off by calling their content's `prepaintGroup`, so every cell —
  each an `Element` or a wrapper over one — records through
  `Element.prepaintGroup` (or `ModifiedElement`'s layer entry) exactly as a
  stack child does. `Grid` itself records through `Element.prepaintGroup`.
  Pinned by test 4.20 (`Frame.elementBounds` holds every cell at its placed rect
  and no entry for a row), whose mutation is the `AnyElement` miss: a
  `GridRow.prepaintGroup` that re-implements the hand-off without
  `recordElementBounds`.

**Cost if wrong.** None beyond the existing rulings cited.

---

## GR-L — lazy grids are not stage G; they are a new stage after stage 4

**Finding** (`swiftui-lazy-grid-scope.swift`): a lazy grid's columns come from
its `GridItem`s, not its cells — a 100pt cell overflows a 96pt flexible column
(LZ1, at x −2) where `Grid` widens the column to 100 (LZ0); fixed and adaptive
items size exactly (LZ2, LZ3); a flexible lazy grid fills the proposed width
(LZ1 200, Grid 128). And it is lazy: 16 of 1000 cell bodies were evaluated in a
200pt scroll view (LZ6) against all 1000 for `Grid` (LZ7).

**Ruling.** `LazyVGrid`, `LazyHGrid` and `GridItem` are a different algorithm
(item-driven) that also needs windowing, which is stage 4's mechanism (the
windowed proposal `List`). They are **deferred to a new stage "G2 — lazy
grids", depending on stage 4**, which this design proposes for the integrator to
add to design §4.1's table and the plan's task 7 note (this track does not edit
either). An eager `LazyVGrid` was rejected: it would be the lazy grid's layout
with `Grid`'s cost, and laziness is observable (LZ6).

**Cost if wrong.** If the integrator reads the task text's "grids" as including
lazy grids, task 7 cannot close until G2 lands.

---

## GR-M — method: lanes, red first, clean builds, mutations, demo

- **Four lanes** (spec §6, rebalanced by `GR-Q` finding 11), in order: 1 the plan
  and the nil proposal, 2 the finite solve, 3 cell attributes, 4 elements,
  identity and the pipeline. Each is written red first; "red before" for a test
  of a new API is its absence.
- Lanes 1 and 3 add stored properties to `LayoutTree` → **`swift package
  clean`** before their suites. Lanes 2 and 4 add none; take one if an
  incremental build misbehaves (CLAUDE.md).
- Every lane: `swift build --build-system native --build-tests`, `swift test
  --build-system native --no-parallel` unfiltered, reading the `Test run with N
  tests` line against spec §7's expected count; 0 `error:`/`warning:` besides
  SwiftPM's notice; 97 goldens unmoved (no lane touches the CSS engine — but
  lanes 1–3 edit `LayoutTree.swift`, whose shared storage can move a golden,
  so the goldens run).
- **Mutations**: commit first, copy the file, apply the named mutation, `git
  status --short`, full suite, name every test it reddens, restore from the
  copy, `git status --short` again. Each new typecheck guard is mutated red
  once. **Before banking a mutation the lane shows the mutant differs** where
  the spec predicts a figure it cannot compute in advance (practices).
- **Depth.** A grid is one native level. `SA-L` says the limit is 0.60 of the
  smallest debug ceiling **over every node kind** on a 1 MB thread; a new node
  kind can lower it. Lane 1
  re-bisects a chain of one-cell grids by `SA-L`'s method (debug, 1 MB `Thread`,
  `--skip-build` per depth) and **stops if the grid's ceiling is below 147**
  (0.60 × 147 = 88.2), reporting rather than lowering `maxDepth`. **The gate on
  the grid alone is not `SA-L`'s rule** — the binding ceiling is the smallest
  over all kinds, and at `cb2e708` that is the one-child vertical stack's 128,
  whose 0.60 is 76, already below `maxDepth` 88 (`GR-W` item 3). The gate,
  the breach and its owner are restated in `GR-AC`; the depth
  tests use **literals** (critic finding 2): a leaf under 88 one-cell grids is
  89 levels and traps; under 87 it is 88 levels and lays out.
- **Demo** (`CN-R`'s harness, as record §16/§17 describe it, rebuilt in the
  lane's scratch; controls non-zero first: light vs dark, default vs modal,
  default vs animation): every lane renders the default demo and the proposal
  preview offscreen through `FakePlatformWindow` for `cb2e708` and its own tree.
  **Expected 0 differing pixels, scene identical, in every image, through lane
  3.** Through lane 3 no demo or preview content names a grid (lanes check with
  `grep -rn "Grid\b" Sources/MetalUIDemoContent Sources/MetalUIDemo`), so the
  images are evidence only that the lane moved nothing else. **Lane 4 puts a
  grid in the preview** (`GR-AE`), so its preview delta is non-zero by design
  and reported as such; the default demo stays 0 px there too. **Real windows**:
  at lane 4's
  end, run `docs/probes/appkit-screen-lock-state.swift` and, if it prints no
  `CGSSessionScreenIsLocked` line and `displayAsleep main: 0`, run
  `docs/probes/window-capture/capture.sh <scratch> cb2e708 <HEAD>` and record
  its table (expected 0 differing pixels in the default window, the grid's own
  region in the preview window).

---

## GR-N — deferrals, each with an owner

| item | owner |
|---|---|
| `LazyVGrid`, `LazyHGrid`, `GridItem` (`.fixed`/`.flexible`/`.adaptive`), laziness | proposed stage **G2**, after stage 4 (`GR-L`; the integrator adds it) |
| `UnitPoint` anchors (`gridCellAnchor(UnitPoint(x:y:))`) | task 11 (`GR-G`) |
| SwiftUI's font-derived 0 between `Text` rows | task 11 (text edges, with `LR-N`'s entry) |
| a modifier distributing over a multi-cell `GridRow` | task 8 (`GR-J`) |
| `.id()` on `Grid`/`GridRow` | task 8 (explicit identity; no built-in proposal element has `.id()`) |
| proposal-path accessibility, grids included | task 12 (`AB-Q`) |
| the model's residual disagreements (GZ2–GZ8; GS4, GS5 among the arms) | **plan task 15, the replacement closeout** (`GR-AA`): re-run the GZ table and the divergence corpus against the baseline in `GR-B`, and decide there whether to close the gap; a count below the baseline is a regression to be fixed, not reported |
| `CN-B`'s stack breaking an infinite-flexibility tie in declaration order (`GR-O` item 8, probe T7, **no grid involved**) | **plan task 6, the stacks task** (`SA-N`'s stack row already belongs to it); the grid stage only measured it |
| the `0.60 × smallest ceiling` margin `SA-L` asks for, breached by the one-child vertical stack at `cb2e708` (128 → 76 < 88) | **`LR-Q`'s stage 6b re-bisection**, dated 2026-09-17 (`GR-AC`); the grid's own chain stays above the gate and lane 4 pins the hard half |
| a grid on screen in front of a human (VoiceOver, hover, input, a mid-flight window) | **plan task 15's closeout look**, on the row lane 4 adds to CLAUDE.md's human-verification table (`GR-AE`) |
| a legacy `Grid` spelling | none: the task text adds none |

(Revision 4's row "a grid's own zero-spacing edges seen from an enclosing stack"
is removed: probed and ruled, `GR-R`.)

---

## GR-O — divergences and inert declarations this stage creates (numbers assigned at integration)

**Divergences**, each with its pin:

1. **SwiftUI's span overflow is not ported** (`GR-F`; GX17, GX18): pinned wrong
   on purpose by test 2.9.
2. **Residual rule interactions** (`GR-B`, `GR-E`, `GR-F`, `GR-H`): with spans,
   priorities, Spacers or unsized axes the kernel is the model, which disagrees
   with `Grid` — in either direction — on GZ2 12/1000, GZ3 31/500, GZ4 59/500,
   GZ5 18/500, GZ6 124/500, GZ7 69/300 (answers), GZ8 338/1000 generated grids,
   and on arms GS4 and GS5: pinned by test 2.9 **and by test 3.12**, which
   holds a representative handful of the 65 committed divergence cases
   (`docs/probes/swiftui-grid-divergences.txt`) wrong on purpose, at the model's
   figures with SwiftUI's in the doc comment. Roughly one generated grid in
   three that uses spans, priorities or Spacers lays out differently from
   SwiftUI; the GZ table is the dated baseline. **Owner: plan task 15's
   closeout** (`GR-AA`, `GR-N`).
3. **`gridCellColumns(0)` lays out as 1** (GX14): pinned by test 3.11.
4. **Anchors are nine-point** (GL14): no `UnitPoint`; pinned by guard G4.
5. **`Text` rows get 8, not 0** (GS7, GN2, GN5, GN7): as `CN-H`'s stacks; pinned
   wrong on purpose by test 4.12.
6. **Every proposal modifier on a multi-cell `GridRow` traps** (GG4, GG7;
   `GR-J`): pinned by test 4.13.
7. **A column count above `Int32.max` traps, naming `columns`**, where SwiftUI
   lays a 40-bit count out as its low 32 bits (GX22: 1 << 40 as `columns(0)`)
   and traps at `Int.max` (GX20) (`GR-S`): pinned by test 3.6.
8. **(Lane 2, not created by this stage and NOT GRID-SPECIFIC; `GR-X`.) A
   linear stack serves two children whose answers at main ∞ are both infinite
   in declaration order**, where SwiftUI served the one larger at main 0 first
   (probe `swiftui-grid-stack-ties.swift` T7, **no grid at all**: `VStack{z
   flexible; b height ≥ 58}` at 200×100 reads z 34, MetalUI z 46 and the stack
   112 tall). It affects every `HStack`/`VStack` in the framework; grid arms
   GE10 and GE19 merely expose it. Pinned wrong on purpose by tests 2.10
   (GE10) and 2.11 (GE19), and — since the second critic round, finding 9 — the
   **no-grid** T7 arm moves out of 2.11 into the stack's own test file (lane 3),
   so a later reader does not take it for grid behaviour. **Owner: plan task 6,
   the stacks task** (`GR-N`), not this stage.

9. **A vanishing `if` inside a grid moves the cells after it** (second critic
   round, finding 13; `GR-AF`): `OptionalGroup` returns no node **without
   advancing the cursor**, so the framework's universal trailing-sibling
   adoption (CLAUDE.md) applies inside a `GridRow` and between rows — a removed
   cell hands its `@State`, its focus and its `onTap` to the next cell in the
   row, and a removed whole `GridRow` hands its row's to the next row. No
   built-in proposal element has `.id()`, so the documented remedy cannot be
   spelled until task 8. Pinned wrong on purpose by lane 4's tests 4.9b (within a
   row) and 4.9c (whole row).

10. **A column count the kernel accepts can still be unrunnable** (`GR-AB`): at
    ~300 bytes per column in SwiftUI and O(ncols) arrays per solve in the
    kernel, a count in the hundreds of millions fails by allocation in both,
    with no message, below the `Int32.max` trap. Measured, not capped; arm in
    test 3.6's doc comment and lane 3's counter arm.

(Revision 4's item 7, "a grid's edges in an enclosing stack take default
spacing", is withdrawn: `GR-R` ports SwiftUI's positional rule.)

**Declared but inert** (for the integrator's inert table):

- `markNativeGridRow(alignment:)`'s horizontal factor and
  `markNativeGridCell(columnAlignment:)`'s vertical factor (`GR-G`);
- grid marks on a node that never sits under a grid, and a `GridRow`'s
  alignment or a `GridCellModifier` outside a `Grid` (`GR-I`);
- `NativeGridSolution`'s bookkeeping counter (`GR-U`): a test observable with no
  production reader.
- `ProposalAxes` (`NativeGrid.swift`), public from lane 1 with no reader or
  writer until lane 3's `unsizedAxes` mark; delete this item when lane 3 lands
  (verifier finding, lane 1).

---

## GR-P — task 7's other text, and what this stage leaves true

Stage G adds a proposal-path container with no legacy twin (design §4.1 row G:
goldens 0 retired, demo 0 px). It does not touch the legacy engine, the layout
authority, the lowering table or the harness of stage 1; nothing in
`LegacyLowering.swift`, `LayoutAuthority.swift`, `Box.swift`,
`ModifiedElement.swift`, `Frame.swift` or `Passes.swift` changes. The
integrator's documentation obligations (CLAUDE.md vocabulary and
unprobed-behaviour lists, the divergence and inert tables, design §4.1 and §8,
the plan's task 7 note, record README, and a `swift package clean` before the
merged suite) are listed in record §20's "For the integrator", written by lane
4.

---

## GR-Q — the critic round: each finding and what was done

The design (`88d0472`…`3981a4e`) was reviewed before any lane ran. Every finding
was applied; none was rejected. Measurements are in record §20, "Critic round".

| # | finding | disposition |
|---|---|---|
| 1 | the corpus and the Spacer fuzz never used a bare Spacer (`CellMods` applied `.layoutPriority(0)`) | **applied.** Probe revision 5 applies each attribute only when written; GQ9/GQ10 record why it matters; the corpus is regenerated (sha256 `d93bc71a…`); GZ3 is 469/500; `GR-B`, `GR-E` restated |
| 2 | depth tests 1.26/1.27 off by one | **applied.** Literals: 88 grids trap (mutant `maxDepth` 89), 87 lay out (mutant 87) (`GR-M`; tests 1.21, 1.22) |
| 3 | a grid inside a container behaved by reading | **applied.** Arms GE1–GE30 and fuzz GZ9–GZ12 (`GR-R`); the three `.grid` arms are now probed rules |
| 4 | `GR-F`'s cost claim contradicted by GZ6 | **applied.** `classify-spans` mode; `GR-F` and `GR-O` item 2 restated |
| 5 | named mutations that cannot redden their tests | **applied**, per test: 1.2 (a mutation on nil-token grouping; GA7 moves to lane 4, where an element mutation exists), 1.9 → 2.4 (the precondition checks each leaf's proposal set, so either `max` spelling fails; moved to the `@testable` file), 1.20 → 1.13 (two tokened nodes: 68×10 vs 30×28), 1.21 → 1.15 (the grid's own check message, so dropping it changes stderr), 1.23 → 1.17 (registration only, stderr names the parameter), 1.24 → 1.18 and 1.19 (both mark registrars), G1 (mutant: a legacy-content overload), 4.4 → 4.19 (the shared gate's mutation, `GR-K`) |
| 6 | `GR-J`/`GR-O` 6 wording: every modifier traps, not only node-registering ones | **applied.** `GR-J` restated; test 4.13 has `.padding`, `.onTap` (GG7) and `.background(ColorToken)` arms |
| 7 | spec precedence contradicted the gap rule; the model never ran on the arms | **applied.** `GR-B`'s precedence; `model-arms` mode (91 of 95 agree); GS4, GS5 move to the pinned disagreements; GX9 fixed by model step 12 |
| 8 | divergences without pins; no text cells | **applied.** GN1–GN10; pins: guard G4 (nine-point), test 4.12 (Text rows), test 4.11 (a form); item 7 withdrawn by `GR-R` |
| 9 | solver bookkeeping unbounded and unpinned | **applied.** `GR-U`: indexed plan, a bookkeeping counter, test 2.14 red first against the scanning solver |
| 10 | merge collisions with stage 2 | **applied.** `GR-A`'s placement: no `Frame.swift`/`Passes.swift` edits; `.grid` last in each switch; marks after `nativeParents`; clean at integration |
| 11 | lane 1 too large | **applied.** Rebalanced as suggested (spec §6, §7) |
| 12 | test 3.9 unspellable | **applied.** Test 4.10 compares ids side by side in one frame and changes the anchor's value, not its presence |
| 13 | unlisted choices and inert APIs | **applied.** Nested rows and row-level attributes probed (GG10–GG16, `GR-T`); inert list in `GR-O`; very large and 40-bit column counts probed and ruled (`GR-S`, GX20–GX23) |
| 14 | `LR-AA`'s bounds-log rule | **applied.** `GR-K`'s exemption and test 4.20 |

---

## GR-R — a grid seen from a stack: positional zero-spacing edges, no priority, no Spacer marks

**Ruling** (reading 12; GE1–GE30, GZ9–GZ12).

- **`zeroSpacingEdges(.grid, axis)`** is positional. Along `.horizontal`: the
  leading edge is zero if **any** cell starting at column 0 has a zero leading
  edge, the trailing edge if any cell ending at the last column has a zero
  trailing edge. Along `.vertical`: top if any cell of row 0 has a zero top
  edge, bottom if any cell of the last row has a zero bottom edge. A cell's
  edge is the existing walk on its node. A non-row child starts at 0 and ends
  at the last column. **A grid with no cells: both edges zero.**
  Evidence: GE1 (a leading Spacer: 0) vs control GE2 (a leaf: 8); GE3 (a
  trailing Spacer: leading 8, trailing 0 — the "any child" rule of `.custom`
  would give 0 on both); GE4 (a Spacer leading one row of two: 0); GE5; GE6 (a
  top-row Spacer: 0) vs GE7; GE23 (row 0 is also the last row: top and bottom
  0); GE24 (a Spacer in the last row only: top 8, bottom 0); GE25 (a non-row
  Spacer: both 0); GE26 (a Spacer starting a short last row: leading 0,
  trailing 8); GE16 (an empty grid: its neighbours touch).
- **`nativeLayoutPriority(.grid)` is 0**, one cell or many: GE8 (a one-cell grid
  of a priority-1 cell) lays out as control GE9, 46/46, where the same HStack
  without the grid gives 0/92 (GE27); a one-cell grid of a Spacer takes an
  equal share (GE11: 50/50) where a bare Spacer gives 92/8 (GE28). Unlike a
  one-child stack (GWP15, GWP16), a grid passes nothing through.
- **`markSpacers` stops at `.grid`**: a stack does not mark a Spacer inside a
  grid. GE29 (`HStack { a; VStack { Grid { [Spacer, b] } }; c }`): a and the
  Spacer touch, so the Spacer's horizontal edges are zero; GE30 (the same
  `VStack` holding the Spacer itself, which marks it vertical): 8. Inside the
  grid the Spacer's gaps are what they are with no stack (GE12 = GE13, GE14 =
  GE15), which the kernel gets for free: the plan is built when the grid
  registers, before any enclosing stack does.
- **A grid's answers at a stack's proposals** follow the model: plain grids at
  infinite proposals 300/300 (GZ9), at a zero axis 300/300 (GZ10), beside a leaf
  in an `HStack` 300/300 (GZ11) and in a `VStack` 300/300 (GZ12); GE17–GE22.

**Cost if wrong.** An edge rule that holds for Spacers but not for another
zero-edge kind (a zero-inset padding over a Spacer, say) would put 8pt between a
grid and its neighbour; the per-cell edge is the walk already probed.

---

## GR-S — column counts are honoured up to `Int32.max` and trap above it

**Finding** (`huge-columns`, GX23, and — since the second critic round —
`span-row`, GX24). `gridCellColumns(100_000)` is **not** clamped (`GR-Z`): GX21's
c genuinely covers columns 0…99_999 and d sits in column
100_000 at x 66, 71×38, the empty columns taking no width without a shortfall;
the grid's column count is the widest row's sum of spans, empty columns included
(GX23). `gridCellColumns(1 << 40)` lays out as `columns(0)` (GX22: SwiftUI keeps
the low 32 bits); `gridCellColumns(Int.max)` traps (GX20, exit 133), and so did
`Int.max / 2` and `Int.max − 1` in scratch.

**A row's SUM is honoured too, and the ceiling is allocation** (second critic
round, finding 8; GX24, `span-row <n>`: one row of **two** cells each marked
`columns(n)`). The answer is 71×38 at n = 3, 100_000, 1_000_000 and 10_000_000
— a sum of 2n columns, all but three empty — and the cost is about **300 bytes
and 1.5 µs per column**: 7.0 s / 1.38 GB at 2 × 10⁶ columns, 31.5 s / 5.95 GB at
2 × 10⁷. A sum of `Int32.max` would be ~640 GB, so **SwiftUI's own ceiling
between 10⁷ and 2^31 is allocation, not a check**, and no arm can probe it: the
run cannot be made. That is measurement, not reading — the earlier "by reading:
no arm sums several large spans in one row" is retired.

**Ruling.** Counts up to `Int32.max` are honoured as SwiftUI honours them, the
column count included, so a grid's column state and bookkeeping are O(its
column count), as SwiftUI's are (GX21 lays out 100_001 columns in both).
`markNativeGridCell` **traps, naming `columns`**, when a single count or a
node's sum of counts exceeds `Int32.max`; `newNativeGrid` traps, naming
`gridCellColumns`, when a row's sum of spans does — GX24 measures that SwiftUI
honours such a sum, so the trap is a deliberate divergence, not a guess.
Negative counts trap as before (`GR-F`, GT1).

**The `SA-J` exception.** `SA-J` rejects a parameter only where SwiftUI rejects
it, and GX22 is a misreading, not a rejection. Honouring a 40-bit count means
either reproducing the truncation (a silent wrong layout) or allocating 2^40
columns (a failure with no message); the kernel traps with the parameter named
instead. A divergence (`GR-O` item 7), pinned by test 3.6.

**Cost if wrong.** A caller passing a count above 2^31 that SwiftUI would
truncate to a usable one gets a trap; a count *below* the trap asks for
O(count) column state in both engines and dies by allocation with no message —
now measured for SwiftUI (above) and a divergence of its own (`GR-AB`,
`GR-O` item 10) rather than an aside.

---

## GR-T — nested rows and row-level cell attributes

**Ruling** (reading 10; GG3, GG10–GG16).

- **A row nested in a row flattens and takes the outermost row's alignment,
  nil included.** GG10 (outer `.top`, inner `.bottom`): a at y 0; GG11 (outer
  `.bottom`, inner `.top`): a at y 20; GG12 (outer unaligned, inner `.bottom`):
  a at y 10, centred by the grid. The kernel's `markNativeGridRow` therefore
  overwrites both the token **and the alignment** of every node it marks,
  writing nil when the enclosing row has none (an enclosing `GridRow`
  registers after an inner one).
- **A cell attribute written on a `GridRow` applies to each cell and loses to
  the cell's own**: anchor (GG13: c keeps its `.topLeading`), column alignment
  (GG14: a keeps `.leading`); columns add (GG15: 2 on the cell and 2 on the row
  span 4); unsized axes form a union (GG16). This is `GR-I`'s combination with
  the row modifier as the outer mark: `GridCellModifier` marks after its content
  has registered, so a cell's own modifier has already marked.

**Cost if wrong.** A form that aligns one row and nests another row inside it
places the inner cells by the outer alignment; that is SwiftUI's reading.

---

## GR-U — the solver's bookkeeping is indexed and counted

**Ruling** (critic finding 9). The model's own shape scans every cell for every
column and group (open counts, commits) and every cell pair for the gaps,
O(groups · ncols · cells) and O(cells²) on every measurement of every frame
(`SA-H`: no cache across calls). The kernel does not port that shape:

- **The plan** (built once at registration) holds each cell's row, first column
  and span; the cells of each row in order; the single-column cells of each
  column; and the gaps, computed in one pass per row (adjacent pairs) and one
  merge of two rows' column intervals per row boundary — O(cells + ncols +
  nrows).
- **The solver** keeps, per priority level, the number of unprocessed
  single-column cells in each column and of cells in each row, and the number
  of open columns and rows; processing a cell decrements them; the commit check
  after a group visits only the columns and rows of that group's cells (and
  every column and row after the first group). A spanning cell's proposal sums
  over the columns outside it, O(ncols) per spanning cell.
- **Bound:** O(cells + ncols + nrows + groups + spanning cells · ncols) per solve.
- **Counter:** `NativeGridSolution` carries an internal `bookkeepingSteps`, +1 per
  cell, column or row record visited by the key sort's comparisons excepted
  (O(cells log cells), not counted), the open-count updates, the commit checks
  and the span sums. Test 2.14 pins a literal on a 200-row × 3-column grid of
  three groups and the linearity `steps(200) − 2 · steps(100)` ≤ a constant, both
  derived by hand; it is written red first against a first solver in the
  model's shape (the lane records that count), then indexed. Measurement work
  stays `lastNativeLayoutWork`'s (`SA-M`).

**Pinned in one dimension only, and the counter is partial** (second critic
round, finding 7). As built, 2.14 varies **rows** on a fixed 3-column,
**span-free** grid, so of the bound's five terms only `cells`, `nrows` and
`groups` are exercised: the `ncols` term (the first group's full commit sweep,
`serve`'s `steps += plan.columnCount` per spanning cell, `spanWidth`'s `steps +=
cell.span`) never varies and `spanning cells · ncols` is not exercised at all.
**Lane 3 adds two arms** to 2.14: one varying `ncols` at a fixed row count, one
with spanning cells, each with a literal derived by hand before the run.
**Uncounted sites, deliberately** (they are O(1) per cell or once per solve and
the counter would only track the same n): `startGroup`'s group-boundary
`sameKey` scan, `init`'s O(ncols + nrows + cells) allocations, `innerGaps`'
`reduce` and `size`'s two `reduce`s. So `GR-U`'s "the red-first run against the
scanning solver is the check that the counter sees the scans" holds for the
sites that solver used, and this list is the rest.

**Cost if wrong.** A counter that misses a scan site proves a bound the code does
not have; the red-first run against the scanning solver is the check that the
counter sees the scans, and the uncounted list above is what that check did not
cover.

---

## GR-V — Text cells

**Finding** (GN1–GN10). A form — labels in column 0, values in column 1 — at
200 × nil answers 196×64: the label column is the widest label (50), the value
column is offered 200 − 50 − 8 = 142 and the long value wraps to 138; the
first row's value (81 wide) does not wrap; rows of `Text` meet with no gap (GN2,
GN5, GN7, as GS7). At 120 × nil both values wrap (GN3). A text-like leaf that
wraps into `ceil(natural / width)` lines agrees with the model in that shape at
200, 120 and 60 wide (GN8–GN10).

**Ruling.** A `ProposalText` cell is an ordinary leaf; the kernel adds nothing
for text. Two element tests hold the form's structure with MetalUI's own text
measurements, claiming no font figure: test 4.11 (the value column is offered
the proposal minus the label column and one gap, and the value cell answers its
own measurement there) and test 4.12 (rows of `ProposalText` are 8 apart:
divergence `GR-O` item 5, pinned wrong on purpose, SwiftUI's 0 in its doc
comment).

**Cost if wrong.** If `ProposalText`'s flexibility at 0 does not order labels
before values, the value column is offered a share instead of the remainder;
test 4.11 fails and the lane records what the text measured.

---

## GR-W — lane 1 as built: stack arms measured, a nil grid's cells measured outside the solver, the plan a class, a row-token counter

**Ruling** (lane 1, 2026-09-17; measurements in record §20, "Lane 1").

1. **Tests 1.10 and 1.11 assert answers, not rects.** The spec placed the GE
   arms in lane 1, but a linear stack places each child at its own measured
   cross size (`CN-E`), so an `HStack` at nil×nil proposes its grid nil×20 —
   probe GE1's own line reads `b … <- nilx20` — and that is the finite branch,
   lane 2's. Lane 1 asserts each stack's answer at nil×nil, where the stack
   measures the grid at nil×nil, and GE29's grid answer (28×20, the VStack's
   width derived from the stack's 76). Every gap the edge rule decides is in
   those answers: mutation (a) reads GE3 68 and GE24 48, (b) GE1 84, and the
   `markSpacers` mutant reads GE29 68×20 with its grid 20×20 (the spec
   predicted "s at x 38", a rect; it also reddens GE25 and GE26, whose Spacer
   an `HStack` then marks). **The GE rects (GE1–GE7, GE16, GE23–GE26,
   GE29, GE30) move to lane 2's test 2.11.**
2. **The depth gate.** Bisected by `SA-L`'s method (debug, 1 MB `Thread`, one
   `swift test --skip-build` per depth, first failing depth completing on
   4 MB): a one-cell grid at nil×nil completes **170** and dies at 171, ≥ 147.
   Two earlier shapes failed the gate and were not kept: the solver measuring
   through its closure with `Array.map` (110) and with a loop (117). So
   `LayoutTree.measureGrid` measures a nil grid's cells itself and hands the
   solver their answers; and `NativeGridPlan` is a `final class` (as a struct
   the grid read 164). **Lane 2's finite solve interleaves measurement with
   state, puts the solver back on the recursion path, and re-bisects against
   the same gate.**
3. **Finding, not this track's to fix:** the same instrument reads the
   one-child vertical stack at **128** at `cb2e708` (127 with lane 1), where
   `NativeLayoutRun.maxDepth`'s table reads 151; `SA-L`'s rule on 127 gives
   72, not 88. Padding reads 197 (194). 88 is unchanged here; the table gains a
   dated re-take and the finding goes to `LR-Q`'s stage 6b re-bisection.
4. **A fourth stored property**: `nextGridRowToken`, so each row mark's token
   is fresh (spec §3 named three dictionaries). Never reset: tokens stay
   unique across generations, and only equality within one plan is read.
5. **The grid's edges are the plan's stored cell edges**, read at
   registration; an enclosing stack cannot change them (`markSpacers` stops at
   a grid, `GR-R`).

**Cost if wrong.** (1) defers rects a lane; (2) binds lane 2 to a frame budget;
(3) is pre-existing and recorded, not hidden.

---

## GR-X — lane 2 as built: the stack's infinite tie, an inverted solver, the counter, two mutations the spec named

**Ruling** (lane 2, 2026-09-17; measurements in record §20, "Lane 2").

1. **GE10 and GE19 are pinned at the kernel's figures, not SwiftUI's.** With the
   finite solve in place, GE10 read a 46 / c 38 / d at 100 (stack 110 wide) and
   GE19 z 46 with the stack 112 tall, against SwiftUI's 36/38/10 and z 34. The
   grid's answers in both are the model's (GE10's grid answers 56 to its 46
   offer, as a 46-wide grid of `[c flexible priority 1, d 10x10]` must; GE19's
   58 to 200×46). The difference is **which child the enclosing stack serves
   first**: both children answer ∞ at main ∞, so `CN-B`'s flexibility (∞ − the
   answer at 0) ties, and MetalUI's stack breaks ties in declaration order.
   A new probe, `docs/probes/swiftui-grid-stack-ties.swift` (run twice,
   byte-identical), shows SwiftUI serving the child larger at 0 first **with no
   grid** (T7: `VStack{z flexible; b height ≥ 58}` at 200×100, z 34), with a
   control (T0) that can contradict declaration order. So this is a stack rule
   the grid exposes, not a grid rule: it is divergence 8 of `GR-O`, pinned wrong
   on purpose (tests 2.10 and 2.11, which gains a kernel T7 arm with no grid),
   and left to the stack's owner. **Not fixed here**: `solveLinearStack` is in a
   shared file on the other track's path, and one arm (T7) does not establish
   SwiftUI's tie rule (the larger minimum first is one reading; T2–T5 and T8
   cannot distinguish it from others). Mutation M2.15 (larger answer at 0 first
   on an infinite tie, applied to the stack and reverted) reddens exactly those
   two tests, at SwiftUI's figures (GE10 a 36; GE19 and T7 z 34).
2. **The finite solver is inverted** (`NativeGridSolver`: `request` /
   `provide`), for the depth guard (`SA-L`, `GR-M`'s gate of 147). A first
   indexed solver that called its measure closure from inside its group loop
   let a chain of one-cell grids at 400×400 complete **65** levels on a 1 MB
   debug thread, below `maxDepth` itself (88), so a chain the guard admits would
   have overflowed the stack. Inverted, with the loop in its own
   `LayoutTree.measureGrid(_:atAProposal:)`, the chain completes **155** at
   400×400 and **167** at nil×nil (170 at lane 1; 159 with the loop inline in
   `measureGrid`); stack 127, padding 194, unchanged (re-taken on the
   committed build). `solveNativeGrid(_:proposal:measure:)`
   remains as a driver over the solver for placement and test 2.14.
3. **The counter** (`GR-U`) counts one per cell visited filling a priority
   level's counts, one per cell decremented after its group, one per column and
   row visited by a commit check (every column and row after the first group,
   a group's own cells' rows and single-column cells' columns after later
   ones), and each column visited by a span sum (the columns outside a span
   when proposing it, the spanned columns when summing its width and choosing
   its targets). It counts nothing at nil×nil. On 2.14's grid: **11n + 3** (2203
   at n = 200). The scanning first branch (`ea0a51b`) read **424331** at n = 200
   and 107181 at n = 100.
4. **Test 2.3 asserts GP5's and GP6's a logs.** Its named mutation (a nil grid
   axis proposed as 0) left 2.3 green: a proposed 152×0 answers 152×0, and its
   152×20 slot re-measures it to the rect the probe reads. The logs are the
   probe's own "measured, in order" entries (`152xnil`, then placed at `152x20`;
   `nilx62`), and with them the mutant reddens 2.3 (and the corpus, 4 issues).
5. **Test 2.12's named mutation does not discriminate** (re-measure every cell
   at its slot): GP1's four slots already differ from their answers, and GP2's
   one equal slot is also its measured proposal. It reddened 1.5, 1.12, 2.1,
   2.9 and 2.13 and left 2.12 green. **Substituted** (spec §7's rule, both
   recorded): the finite solve also measures every cell at nil×nil first, which
   reddens 2.12 at GP1 20 calls / 12 hits / 21 misses and GP2 19 / 13 / 20.
6. **Counts.** Lane 1's verifier added `resetClearsGridCellColumnMarks`, so lane
   2's suite is **1446** (spec §7 read 1445); later lanes' expectations add one.

**Cost if wrong.** (1) If SwiftUI's tie rule is not about the stack, a grid in a
stack beside a flexible sibling lays out differently from SwiftUI by a share
(GE10: 10pt); the pins redden the day the stack changes, which is when this
should be re-read. (2) is a stack-depth budget, re-measured. (3)–(5) are test
strength, measured by mutation.


---

## GR-Y — the second critic round: each finding and what was done

The design and lanes 1–2 as built (`cb2e708`…`cdd9209`) were reviewed a second
time, in the worktree, with the suite re-run (1446) and every probe re-run
twice. **Fifteen findings; all fifteen applied, none rejected** — five in code
now (`1b6c698`), four in the probes and their committed stdout (`1844256`), the
rest as restatements here and as named rows in lanes 3 and 4. Measurements are
in record §20, "Second critic round".

| # | finding | disposition |
|---|---|---|
| 1 | the span clamp is unreachable dead code and §4.1 / `GR-F` document clamping as a probed rule | **applied, in code.** `Swift.min` deleted with the structural proof beside it (`GR-Z`); §4.1, `GR-F`, `GR-S`, `NativeGridCell.span`'s comment and test 1.3's doc comment restated. GX6 and GX21 are empty columns, not clamping |
| 2 | GX13 is normative and pinned by nothing | **applied, in code.** A fourth arm in test 1.2 (71×38, x offered the whole grid), with the mutation that honours a written mark on a non-row child; the non-row **column-alignment** half goes to lane 3 (3.1, 3.3), which is where column alignment exists |
| 3 | the exit test cannot see the divergence it bounds, and `GR-O` item 2 has no owner | **applied.** The 65 discarded cases are committed with both answers (`divergences` mode, `GR-AA`); lane 3's test 3.12 pins a handful wrong on purpose; `GR-B`'s GZ table is a dated baseline a later change may not lower; the owner is plan task 15's closeout (`GR-N`) |
| 4 | no human ever sees a grid, and the design guarantees it | **applied.** Lane 4 puts a small `Grid`/`GridRow` in the **preview** content — its pixel delta becomes non-zero by design and is reported with its region — and adds the open row to CLAUDE.md's human-verification table (`GR-AE`) |
| 5 | the depth gate checks the grid's ceiling, `SA-L`'s is the smallest over kinds | **applied.** `GR-M` restated as `0.60 × min(ceiling over every kind) ≥ maxDepth`; the breach at `cb2e708` (stack 128 → 76 < 88) is dated and owned by `LR-Q`'s stage 6b, and lane 4 pins the hard half as an exit test per kind (`GR-AC`) |
| 6 | placement re-measures through the two frame shapes the bisection rejected, and was never bisected | **applied.** Lane 3's first item, before any new behaviour: re-bisect with a chain whose slot differs from its answer at every level, and if the ceiling falls below 147 route `placeGrid` through `measureGrid(_:atAProposal:)` and hoist `nativeGridCellRects`' measurement out of its `map` (`GR-AC`) |
| 7 | `GR-U`'s bound is pinned in one dimension and the counter has uncounted sites | **applied.** Two more arms on 2.14 in lane 3 (`ncols` at fixed rows; spanning cells), and `GR-U` now lists the four uncounted sites and why |
| 8 | test 3.6 arm (c) traps where SwiftUI is unmeasured, and counts below the trap are unrecoverable | **applied, probed now.** GX24 (`span-row <n>`): SwiftUI honours a two-cell row sum at 2 × 10⁷ columns, ~300 B and ~1.5 µs each, so `Int32.max` would be ~640 GB and cannot be run. Arm (c) ships with that behind it; the allocation ceiling is divergence `GR-O` item 10 (`GR-AB`) with a lane-3 arm |
| 9 | a general `linearStack` defect filed as a grid divergence with a file for an owner | **applied.** `GR-N` gains a row owned by plan task 6; `GR-O` item 8 says it is not grid-specific; lane 3 moves the no-grid T7 arm out of test 2.11 into the stack's own test file |
| 10 | three public registrars exported for two lanes with no caller and a green mutation | **applied, in code now.** `Tests/MetalUITests/GridRegistrarTests.swift`: three tests through a real `Frame`, one per argument the verifier showed could be dropped (V2, V2b, the column count), each mutated red (`GR-AD`) |
| 11 | §4.2's normative bookkeeping paragraph states a rule the code does not implement | **applied.** Restated as "decremented after each group, so a group's open columns are its start-of-group snapshot", matching `NativeGrid.swift`; the difference is load-bearing (GX17's group) |
| 12 | the mark registrars accept a legacy node silently | **applied, in code now.** A `precondition` naming the node in both, with exit-test arms asserting each stderr fragment (`GR-AD`) |
| 13 | identity inside a row carries the worst failure mode with no remedy and no pin | **applied.** Divergence `GR-O` item 9 and lane 4's tests 4.9b (within a row) and 4.9c (whole row), pinned wrong on purpose (`GR-AF`) |
| 14 | the default probe run's stdout is not committed | **applied.** `docs/probes/swiftui-grid-default-run.txt`, sha256 `5d203038…172f61ba`, with the verifying commands in its header |
| 15 | merge collisions with `feat/engine-stage-2`: low, with one caveat | **applied.** `GR-A` gains the third integration item: `LR-AU` changes where a padded child is placed and lanes 3–4 have padded-cell arms, to be **re-derived** at integration, not merely re-run |

---

## GR-Z — a span is never clamped; the column count makes a clamp unreachable

**Ruling** (second critic round, finding 1). `makeNativeGridPlan` computes a row
cell's span as `max(1, Σ its column marks)` and **does not clamp it**. The
`Swift.min(span, columnCount − column)` lane 1 wrote is deleted, and every text
that called clamping a probed rule — spec §4.1, `GR-F`, `GR-S`,
`NativeGridCell.span`'s doc comment, test 1.3's — is restated.

**Why it could never bind.** `columnCount` is the largest sum of spans over the
row groups. Within one group, `column` at a cell is the sum of the previous
cells' spans, so `columnCount − column` ≥ (this row's total) − (the previous
spans) ≥ this cell's span. A proof, not a green mutation: deleting the `min`
leaves the suite green precisely because nothing can reach it.

**Neither engine clamps.** The probe lines read as clamping are three empty
columns: GX6's `[a, b] [x span 5]` has five columns, of which 2–4 hold no cell,
take no width and meet no adjacent pair, so the answer is the same 58; GX21's
`columns(100_000)` genuinely covers columns 0…99_999 with d in column 100_000;
GX23 established that the column count **is** the widest row's sum of spans.

**Cost if wrong.** If some future rule made a row's sum exceed the column count
— a per-row cap, say — spans would silently overflow their row rather than being
cut. Nothing here introduces one, and `GR-S`'s traps are on the sum itself.

---

## GR-AA — the divergence corpus, the GZ baseline, and their owner

**Ruling** (second critic round, finding 3). The replay corpus is, by
construction, the grids on which the model already agrees with SwiftUI, so no
test in this stage can see agreement getting **worse**. Three additions:

1. **The discarded cases are committed.** `divergences` prints, from the same
   generator, seed and budget as `corpus`, the 65 cases that run throws away,
   each with SwiftUI's answer and rects and the model's:
   `docs/probes/swiftui-grid-divergences.txt`, sha256 `36021ffc…8c9bdaf8`, run
   twice, byte-identical.
2. **A handful is pinned wrong on purpose.** Lane 3's test 3.12 transcribes a
   representative set — at least one per symptom of `GR-F`'s
   `classify-spans` table (the model wider, SwiftUI wider, equal sizes and
   different rects) and one that needs no span — and asserts the **model's**
   figures with SwiftUI's in the doc comment, beside test 2.9.
3. **The GZ table is a dated baseline** (`GR-B`), not a report: a later change
   may not lower any group's count, and one that trades groups re-takes the
   whole table.

**Owner: plan task 15, the replacement closeout** (`GR-N`), which re-runs the GZ
table and the divergence corpus, compares them with the baseline and decides
there whether to close the gap. The earlier "reopened by a probe arm that a user
layout hits" was not an owner.

**Cost if wrong.** A pinned handful is a sample: a regression that misses all of
them and lowers a GZ count is caught only at task 15's re-run, not by the suite.
That is the honest bound, and it is why the counts are dated here.

---

## GR-AB — a column count below the trap can still be unrunnable

**Ruling** (second critic round, finding 8). The kernel keeps `GR-S`'s
`Int32.max` traps and adds **no cap below them**, because SwiftUI has none
either: GX24 lays out a two-cell row sum of 2 × 10⁷ columns, at about 300 bytes
and 1.5 µs per column (7.0 s / 1.38 GB at 2 × 10⁶; 31.5 s / 5.95 GB at 2 × 10⁷).
Both engines therefore die by allocation somewhere between 10⁷ and 2^31, with no
message — a **divergence with a measurement** (`GR-O` item 10), not a check.

A cap would have to name a number neither engine names, and `SA-J` forbids
rejecting what SwiftUI accepts; relaxing a trap later is additive, inventing one
is not.

**The kernel's own per-column cost is lane 3's arm**: `newNativeGrid` builds
`columnSingleCells` and `hgap` per column and each solve allocates `widths`,
`levelInColumn`, `unprocessedSingles` and `committedColumn`, with `columnX` at
placement — so lane 3 registers a grid with a large column count and reads
`bookkeepingSteps` (work, never wall clock) to state the kernel's shape beside
SwiftUI's 300 B/column, and records the count it used.

**Cost if wrong.** A caller who writes `.gridCellColumns(1_000_000_000)` gets a
frame that allocates tens of gigabytes and dies without a diagnostic. The
divergence says so; nothing prevents it.

---

## GR-AC — the depth gate is over every node kind, and placement is bisected too

**Ruling** (second critic round, findings 5 and 6).

1. **The gate is `0.60 × min(ceiling over every native node kind) ≥ maxDepth`**,
   `SA-L`'s rule, not "the grid's ceiling ≥ 147". The grid's own chain still has
   to clear 147 for the grid not to be the binding kind; that is necessary, not
   sufficient.
2. **The rule is already breached at `cb2e708`, by the stack, not the grid**
   (`GR-W` item 3): the one-child vertical stack completes 128 levels on a 1 MB
   debug thread (127 with `.grid` present), so 0.60 × 127 = 76 < `maxDepth` 88.
   **Dated obligation, 2026-09-17, owner `LR-Q`'s stage 6b re-bisection**
   (`GR-N`): re-bisect all kinds and either lower `maxDepth` or re-derive the
   margin. The grid track does not lower `maxDepth`: it is shared storage on the
   other track's path and every `SA-L` figure moves with it.
3. **Lane 4 pins the half that can be tested**: one exit test per native node
   kind in `NativeLayoutRun.maxDepth`'s table — padding, a fixed frame, the
   one-child vertical `linearStack`, a custom `ProposalLayout` — **and the
   grid**, each building a chain of
   `maxDepth − 1` nodes on a **1 MB** `Thread` and expecting `.success`. It
   cannot see the 0.60 margin, but it fails the day any kind's ceiling falls
   below `maxDepth` itself — which is the condition the margin exists to keep
   far away. Its mutation is `maxDepth` raised by 40 (every arm's child dies).
4. **The placement path is re-bisected in lane 3, before any new behaviour.**
   Lane 1 and lane 2 rejected two frame shapes for the depth guard — measuring
   from inside an `Array.map` (110 levels) and from inside the solve (65) — and
   `placeGrid` still uses **both**: `solveNativeGrid(_:proposal:measure:)`
   drives the solver from its own loop with a measuring closure, and
   `nativeGridCellRects` measures inside a `map`. That is safe only while every
   placement-time measurement is a cache hit, and `GR-C` deliberately measures
   at a **fresh** proposal whenever the slot differs from the answer. The
   bisection chain (one-cell grids over a leaf answering `min(proposal, 10)`)
   has slot == answer at every level, so the fresh branch was never on the
   measured stack. Lane 3 re-bisects with a chain whose slot differs from its
   answer at every level (a two-cell row, or the `odd` leaf) and, if the ceiling
   falls below the gate, routes `placeGrid` through
   `measureGrid(_:atAProposal:)`'s shape and hoists `nativeGridCellRects`'
   measurement out of its closure, re-bisecting after.

**Cost if wrong.** (2) is pre-existing and disclosed; (4) is the one that could
overflow a stack the guard admits, which is why it is lane 3's first item and
not lane 4's.

---

## GR-AD — the public registrars are pinned, and a grid mark rejects a legacy node

**Ruling** (second critic round, findings 10 and 12), both applied in code at
`1b6c698`.

- **`Sources/MetalUI/Grid.swift`'s three `LayoutPass` registrars are pinned
  now**, not in lane 4: `Tests/MetalUITests/GridRegistrarTests.swift` lays a
  grid out through a real `Frame` and reads its cells' rects relative to the
  grid's own (a native root is centred, `CN-J`). One test per argument the
  lane-1 verifier showed could be dropped with the suite green — `.topLeading`
  vs `.center` for `requestNativeGrid`, a row `.top` for `markNativeGridRow`,
  GX1's span for `markNativeGridCell` — each with a `#require`d control that
  answers differently. Public API with no caller is CLAUDE.md's "an API that
  exists, compiles and does nothing"; two lanes of it was too long.
- **`markNativeGridRow` and `markNativeGridCell` trap on a legacy node**, each
  naming it ("a grid row/cell mark written on a legacy node (SA-G), node *i*"),
  before the parent check. Both previously checked only the generation and the
  parent, so a mark on a legacy node was accepted and the `SA-G` lie surfaced
  either inside `newNativeGrid` with a different message or never at all. Every
  other `SA-G` lie in the tree is a compile error or traps where it is written.

**Cost if wrong.** The three pins fix the registrars' defaults in place: a later
lane that changes an argument's meaning must change them. The two preconditions
reject a mark on a legacy node that could previously have been written and
ignored — no caller in the tree does it, and the arms are exit tests.

---

## GR-AE — a grid reaches the preview, and the human look is a named open row

**Ruling** (second critic round, finding 4). `GR-M`'s "0 differing pixels
everywhere" would close the stage with a grid rendered in no window, and every
earlier proposal container reached the preview. So **lane 4 adds a small
`Grid`/`GridRow` to the `METALUI_NATIVE_LAYOUT_PREVIEW=1` preview content**: a
two-row, two-column grid of `Rectangle`s with one `.onTap` cell, sized to sit
inside the existing preview column.

- The **default demo** stays grid-free and stays at **0 differing pixels**.
- The **preview** delta is **non-zero by design**: lane 4 reports the differing
  pixel count, the bounding box of the difference, and that the scene log's new
  rects are exactly the grid's cells; anything outside that box is a defect.
- CLAUDE.md's human-verification table gains an **open** row —
  "the proposal preview's grid: cells in two rows and two columns, the tap cell
  reacts, nothing else moved" — which is task 15's closeout look (`GR-N`).
  Nobody has looked at a grid on screen, and the row says so rather than the
  record implying a look happened.

**Cost if wrong.** The preview's pixel comparison stops being a pure "moved
nothing else" signal at lane 4; the bounding box is what keeps it evidence. If
the grid's own region is wrong nobody notices until the look.

---

## GR-AF — identity inside a row: a vanishing cell or row is adopted, pinned wrong on purpose

**Ruling** (second critic round, finding 13). Cells mint stable ids under the
grid (`GR-J`: a `GridRow` takes one cursor index and numbers its cells from 0
under its own id), and the framework's **universal** trailing-sibling rule holds
inside a row and between rows: `OptionalGroup.requestProposalGroupLayout`
returns no node **without advancing the cursor**, so

- a vanishing `if` around a **cell** shifts the rest of that row: the next cell
  adopts the vanished cell's id, and with it its `@State`, its focus and its
  `onTap` — CLAUDE.md's "a release can run the wrong `onClick`";
- a vanishing `if` around a whole **`GridRow`** shifts every later row the same
  way.

The documented remedy is naming the trailing sibling with `.id()`, and **no
built-in proposal element has one** (task 8, `GR-N`), so inside a grid it cannot
be spelled today. Lane 4 pins both, wrong on purpose, beside 4.9's good case:
**4.9b** (a cell removed from a row; the next cell reads the removed cell's
counter) and **4.9c** (a whole row removed; the next row does), each naming the
change that would fix it. Divergence `GR-O` item 9, so the integrator's
divergence table carries it rather than one ruling's prose.

**Cost if wrong.** A form that shows a field conditionally hands its state to
the next field. That is the framework's rule everywhere, but a grid is exactly
where conditional cells are natural, so it is recorded as a divergence rather
than left implicit.
