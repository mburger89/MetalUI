# Grids decisions (plan task 7, stage G)

Rulings for [`specs/2026-09-17-grids-design.md`](specs/2026-09-17-grids-design.md),
on `feat/grids` from `cb2e708`. Ids are **lettered**, `GR-A`…`GR-P`; next unused
is **`GR-Q`**. A bare `GR-3` is a typo, not a citation.

**Status, 2026-09-17, design only.** No file under `Sources/` or `Tests/`
changed. Baseline measured in this worktree at `cb2e708`: `swift build
--build-system native --build-tests`, then `swift test --build-system native
--no-parallel` → `Test run with 1409 tests in 1 suite passed after 42.821
seconds`, 0 `error:`, no `warning:` besides SwiftPM's deprecation notice;
`find Tests -name "*.json" | wc -l` 97; guards 71 (73 `canTypecheck` hits, less
the declaration in `Typecheck.swift` and the comment in `UnitSafetyTests`).

Probes (arm ids below are theirs):

- `docs/probes/swiftui-grid.swift`, revision 4 (`ed3471e`, `c1f793d`,
  `01a3462`, and the revision-4 commit), `/usr/bin/swift`, Apple Swift 6.4, macOS 27.0 (26A428); exit 0,
  each revision run twice with byte-identical output, recorded in its header
  with the reading. It holds the **reference model** (`solve`, `ModelGrid`),
  the fuzz comparison of that model with `Grid` (group GZ, with a control GZ0
  that must disagree) and the `corpus` mode.
- `docs/probes/swiftui-grid-corpus.txt` — the `corpus` mode's stdout, 120 grids
  on which SwiftUI and the model agree, sha256 recorded in both files.
- `docs/probes/swiftui-lazy-grid-scope.swift` (`ed3471e`) — LazyVGrid/LazyHGrid
  against Grid, and laziness; exit 0, run twice, byte-identical.

**Call counts.** The containers decisions note that SwiftUI's duplicate
flexibility probes vary by OS release. The grid probe's "measured, in order"
lists are distinct calls only (SwiftUI caches), and `GR-B`'s work literal is
the kernel's own count of distinct `(node, proposal)` pairs, which the lists
happen to equal on GP1/GP2 under the model; a later OS changing its list does
not change the ruling.

---

## GR-A — a grid is a kernel `NativeNode` case with registration-time marks, not a `ProposalLayout`

**Ruling.** `LayoutTree` gains one built-in case, `.grid(NativeGridPlan)`, and
three public registrars: `markNativeGridRow(_:alignment:)`,
`markNativeGridCell(_:columns:anchor:columnAlignment:unsizedAxes:)` and
`newNativeGrid(children:alignment:horizontalSpacing:verticalSpacing:)`. Marks
are written by the element layer before the grid registers; the grid resolves
its plan (rows, spans, attributes, priorities, zero-spacing edges) **once, at
registration**, and stores it in the case. The solver is a pure function in a
new file, `Sources/MetalUILayout/NativeGrid.swift`, called from the `.grid` arms
of `measureNative`/`placeNative`.

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

**Cost if wrong.** `LayoutTree.swift` is shared with the stage-2 track: the
edits are appended (three stored mark dictionaries, `reset` lines, one enum
case, one arm in each exhaustive switch, registrars in an extension at the end)
and the algorithm is in its own file. Three stored properties on a public class
read across a module boundary: **`swift package clean` before the lane-1 and
lane-2 suites** (`CN-R`). If a later task wants grids as a public
`ProposalLayout`, the solver is already a pure function over a plan and a
measure closure.

---

## GR-B — the kernel is the probe's reference model; the stage's exit test replays its corpus

**Ruling.** The grid kernel implements the reference model in
`docs/probes/swiftui-grid.swift` (`solve` and `ModelGrid.placeSubviews`), whose
rules are spec §4. It is not a SwiftUI source port: it was fitted to the arms
and then tested against `Grid` on generated grids.

**Evidence** (GZ, fixed seeds, sizes within 0.01 and every leaf rect):

| group | agree |
|---|---|
| GZ0 control, the model with commits ignored | 212 of 300 (must disagree) |
| GZ1 plain grids | **1000 of 1000** |
| GZ2 alignment, anchors, column alignment, unsized axes, explicit spacing | 988 of 1000 |
| GZ3 Spacer cells | 479 of 500 |
| GZ4 layout priority | 441 of 500 |
| GZ5 non-row children | 476 of 500 |
| GZ6 spans | 374 of 500 |
| GZ7 infinite proposals, answers only, everything | 222 of 300 |
| GZ8 everything | 659 of 1000 |

Every disagreement printed involves a span or non-row child, a priority, a
Spacer or an unsized axis; none is a plain grid. The model was refined during
the design round against these groups, one rule at a time, with the counts
recorded in record §20 (the unsized-axis variant choice is one of them).

**The exit test** is `theGridProbeCorpusAgreesCaseByCase` (spec test 1.18,
unfiltered by lane 2): the 120 grids of `docs/probes/swiftui-grid-corpus.txt`, each built from
native leaves standing for the probe's leaf kinds, laid out at its proposal at
(0, 0), and compared with the recorded answer and with `roundLayout` of every
recorded rect. Lane 1 runs the 19 cases that use no anchor, column alignment or
unsized axis.

**Why a corpus of agreeing cases.** It tests SwiftUI's behaviour where the
model reproduces it, which is what the kernel ports; the disagreeing cases are
the divergence `GR-O` names, and three of them are pinned by name (`GR-F`).

**Cost if wrong.** A rule the model gets right only by coincidence on the
corpus would be ported as fact. The GZ counts bound that: the plain-grid rules
are 1000 of 1000 on independent seeds; the interaction rules are not, and are
named as such.

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
  stacks. **NaN and ±∞ trap** at registration: SwiftUI answers nan and inf
  (GS9, GS10), the rule `SA-J` applies to stacks.
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
  unmarked (no stack marks it), so both its edges are zero.
- **Not adopted:** SwiftUI's font-derived spacing, 0 between rows of `Text`
  (GS7 36×32). MetalUI gives 8, as `CN-H` does for a `VStack` of `ProposalText`.
  A divergence (`GR-O`), owned by task 11 (text edges, as `LR-N` already lists).

**A grid's own edges, seen from a stack it sits in, are unprobed.** The kernel
treats `.grid` in `zeroSpacingEdges` as a leaf (neither edge zero), by reading;
recorded in `GR-O`.

**Cost if wrong.** A boundary rule that differs by view kind in a way GS did not
exercise (for example a `ProposalText` beside a Spacer inside a padding) would
place a column 8pt off; the walk is the one already probed for stacks.

---

## GR-E — finite proposals: flexibility groups, shares and commits; priority and Spacer

**Ruling** (reading 4 and 5; spec §4.3 states it as an algorithm):

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
**A Spacer is priority −∞** (GS1: s at 142×42; GQ6–GQ8), which the walk already
returns, and is flexible on both axes (unmarked, `CN-C`).

**Cost if wrong.** GZ4 (441/500) and GZ3 (479/500) are the measured limits of
this rule set with priorities and Spacers; a user layout in the remainder lays
out differently from SwiftUI by a column's share. Recorded as a divergence.

---

## GR-F — spans and non-row children; SwiftUI's span overflow is not ported

**Ruling** (reading 6):

- `gridCellColumns(n)` spans *n* columns, clamped to the columns left in the row
  (GX6). A non-row child is one cell spanning every column and ignores
  `gridCellColumns` (GX3, GX4, GX13).
- A span's width shortfall (its answer minus its slot) is spread equally over
  its spanned columns **that hold no single-column cell anywhere in the grid**,
  or over all of them if every one does (GX1 51/41; GX11 col 1 82, col 2 10).
- At a finite proposal a spanning cell is proposed W′ minus, for each column
  outside it, the share if the column is open or its current width if not,
  plus its inner gaps (GX8 300×46, GX10 300×82, GX12 300×96); it does not keep
  its columns open (GX9: b at 262); its shortfall is applied after its group's
  single-column cells (GX10 151/141).
- **Two `gridCellColumns` on one view add their values above 1** (GX15: 3 and 2
  span 5; GX16: 2 and 1 span 2; GWI1, GWI2 through padding). Ported: odd, but
  probed in both orders and through a wrapper.
- `gridCellColumns(-1)` **traps** (GT1: exit 133); the kernel traps with the
  parameter named (`SA-J`).
- `gridCellColumns(0)` **lays out as 1**. SwiftUI places such a cell in column 0
  without consuming it (GX14: c at x 0, d shares column 0). Accepted (`SA-J`:
  SwiftUI does not reject it) and not reproduced: a divergence (`GR-O`).

**Not ported: SwiftUI's span overflow.** When a span's shortfall is spread while
a spanned column is still open, SwiftUI proposes the open column more than the
grid has: GX17 answers **284×100 at 200×100** (b proposed 218) for content that
fits in 200, and GX18 answers **231.33** where control GX19, which differs only
in the non-row child's width (60 → 40), answers 200. The model answers
**200×100** for both (spec 1.15 lists its rects). A grid wider than its proposal
for fitting fixed content is a defect, not a design `EP-5` asks MetalUI to
follow; it is the largest share of GZ6's 126 disagreements. Pinned wrong on
purpose by test 1.15; divergence (`GR-O`), no owner.

**Cost if wrong.** A layout that relies on SwiftUI's overflow (unlikely: it
clips or overlaps) differs; the model's answer is at most the proposal where
SwiftUI's exceeds it.

---

## GR-G — alignment: grid, row, column, anchor

**Ruling** (reading 7):

- `Grid(alignment:)` is the nine-case `ProposalAlignment` (SwiftUI's
  `Alignment`), both axes, and places non-row children (GL1, GL2, GL12).
- `GridRow(alignment:)` is `VerticalAlignment?` (`CN-I`'s type) and overrides
  the grid vertically for its cells (GL3, GL9).
- `gridColumnAlignment(_:)` takes `HorizontalAlignment` and sets the horizontal
  alignment of the whole column from any row (GL4, GL5). **The first
  declaration in row order, then cell order, wins** (GL6, GL7). A spanning cell
  declares it for its first column and is not itself aligned by it (GL8).
- `gridCellAnchor(_:)` overrides both, on both axes, and applies to a non-row
  child (GL10, GL11, GL13).
- **On one view the inner declaration wins** for anchor and column alignment
  (GL15, GL16; GWI3, GWI4 through padding).
- **The anchor is a `ProposalAlignment`, not a `UnitPoint`.** SwiftUI accepts
  any unit point (GL14: (0.25, 1) puts a at (10, 20)). MetalUI has no
  `UnitPoint`, and the kernel's anchors (`PlacementSubview.place`) are nine-case;
  the nine SwiftUI spellings (`.topLeading` …) are source-compatible. A
  divergence (`GR-O`), owned by task 11 (which owns shapes and overlays, where
  a `UnitPoint` would also serve).

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
Declarations on one view form a **union** (GU12, GU13, GWI5).

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
(a `GridRow` marks the nodes it receives, and an enclosing `GridRow` registers
later: GG3 flattens); anchor and column alignment from the **innermost** mark;
columns the sum of the marks above 1 (`GR-F`); unsized axes the union.

**Cost if wrong.** A wrapper MetalUI adds later that registers a node needs an
arm in this walk, or attributes written inside it vanish silently; test 2.9
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
  content returns — so on a `GridRow` it applies to each cell, as SwiftUI's
  does (GG5, GG6).
- **No legacy spelling** (the task text); `Grid`'s content is
  `ProposalElementGroup`, so legacy content does not compile (guard).

**Why a row has identity.** Stable ids under the grid: a cell's id is (grid, row
index, cell index), so removing a cell from one row does not renumber another
row's cells and move their `@State` (test 3.8). With a transparent row every
cell would number flat under the grid and a vanishing cell in row 0 would shift
every later row's state. The universal trailing-sibling rule still holds inside
a row and between rows (a vanishing `if` around a row makes the next row adopt
its id). No SwiftUI identity claim is made (not probed); task 8 owns the audit.

**A modifier that registers a node on a multi-cell `GridRow` traps** (the
existing one-node preconditions of `ModifiedContent`, `OnTapModifier`,
`OverlayModifier`/`BackgroundModifier`'s primary), where SwiftUI applies it to
each cell (GG4, GG7). On a one-cell row it wraps the cell, and `GR-I`'s walk
keeps the wrapper a row cell, which lays out as SwiftUI's distribution does. A
divergence (`GR-O`), owned by task 8 ("`Group` … modifier placement"), pinned
by an exit test.

**Cost if wrong.** If task 8 decides rows should be identity-transparent,
changing it resets every grid cell's state once; nothing else moves.

---

## GR-K — the pipeline: hit testing, accessibility, disabled, paint, animation

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
  gate in `Frame.registerHandlers` suppresses every cell's hitbox.
- **Animation.** Nothing on the proposal path animates (CLAUDE.md); grids snap.
- **Root.** A native grid root is centred at its answer (`CN-J`), with no code
  of its own.

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

- **Four lanes** (spec §6), in order: 1 kernel algorithm, 2 kernel cell
  attributes and the exit test, 3 elements and identity, 4 pipeline. Each is
  written red first; "red before" for a test of a new API is its absence.
- Lanes 1 and 2 add stored properties to `LayoutTree` → **`swift package
  clean`** before their suites. Lane 3 adds public types only.
- Every lane: `swift build --build-system native --build-tests`, `swift test
  --build-system native --no-parallel` unfiltered, reading the `Test run with N
  tests` line against spec §7's expected count; 0 `error:`/`warning:` besides
  SwiftPM's notice; 97 goldens unmoved (no lane touches the CSS engine — but
  lanes 1 and 2 edit `LayoutTree.swift`, whose shared storage can move a golden,
  so the goldens run).
- **Mutations**: commit first, copy the file, apply the named mutation, `git
  status --short`, full suite, name every test it reddens, restore from the
  copy, `git status --short` again. Each new typecheck guard is mutated red once.
- **Depth.** A grid is one native level. `SA-L` says the limit is 0.60 of the
  smallest debug ceiling on a 1 MB thread; a new node kind can lower it. Lane 1
  re-bisects a chain of one-cell grids by `SA-L`'s method (debug, 1 MB `Thread`,
  `--skip-build` per depth) and **stops if the ceiling is below 147**
  (0.60 × 147 = 88.2), reporting rather than lowering `maxDepth`.
- **Demo** (`CN-R`'s harness, as record §16/§17 describe it, rebuilt in the
  lane's scratch; controls non-zero first: light vs dark, default vs modal,
  default vs animation): every lane renders the default demo and the proposal
  preview offscreen through `FakePlatformWindow` for `cb2e708` and its own tree.
  **Expected 0 differing pixels, scene identical, in every image, at every
  lane.** No demo or preview content names a grid (lanes check with `grep -rn
  "Grid\b" Sources/MetalUIDemoContent Sources/MetalUIDemo`), so the images are
  evidence only that the lane moved nothing else. **Real windows**: at lane 4's
  end, run `docs/probes/appkit-screen-lock-state.swift` and, if it prints no
  `CGSSessionScreenIsLocked` line and `displayAsleep main: 0`, run
  `docs/probes/window-capture/capture.sh <scratch> cb2e708 <HEAD>` and record
  its table (expected 0 differing pixels in both windows).

---

## GR-N — deferrals, each with an owner

| item | owner |
|---|---|
| `LazyVGrid`, `LazyHGrid`, `GridItem` (`.fixed`/`.flexible`/`.adaptive`), laziness | proposed stage **G2**, after stage 4 (`GR-L`; the integrator adds it) |
| `UnitPoint` anchors (`gridCellAnchor(UnitPoint(x:y:))`) | task 11 (`GR-G`) |
| SwiftUI's font-derived 0 between `Text` rows | task 11 (text edges, with `LR-N`'s entry) |
| a node-registering modifier distributing over a multi-cell `GridRow` | task 8 (`GR-J`) |
| `.id()` on `Grid`/`GridRow` | task 8 (explicit identity; no built-in proposal element has `.id()`) |
| proposal-path accessibility, grids included | task 12 (`AB-Q`) |
| a grid's own zero-spacing edges seen from an enclosing stack (unprobed) | stage G follow-up, before stage 6b's root switch puts a grid in a stack in production |
| the model's residual disagreements (GZ2–GZ8) | recorded divergence; reopened by a probe arm that a user layout hits (task 15's closeout audit) |
| a legacy `Grid` spelling | none: the task text adds none |

---

## GR-O — divergences this stage creates (numbers assigned at integration)

1. **SwiftUI's span overflow is not ported** (`GR-F`; GX17, GX18): pinned wrong
   on purpose by test 1.15.
2. **Residual rule interactions** (`GR-B`, `GR-E`, `GR-H`): with spans,
   priorities, Spacers or unsized axes the kernel is the model, which disagrees
   with `Grid` on GZ2 12/1000, GZ3 21/500, GZ4 59/500, GZ5 24/500, GZ6 126/500,
   GZ7 78/300, GZ8 341/1000 generated grids.
3. **`gridCellColumns(0)` lays out as 1** (GX14): pinned by test 2.10.
4. **Anchors are nine-point** (GL14): no `UnitPoint`.
5. **`Text` rows get 8, not 0** (GS7): as `CN-H`'s stacks.
6. **A node-registering modifier on a multi-cell `GridRow` traps** (GG4, GG7):
   pinned by test 4.6.
7. **A grid's edges in an enclosing stack take default spacing**, by reading,
   unprobed (`GR-D`).

---

## GR-P — task 7's other text, and what this stage leaves true

Stage G adds a proposal-path container with no legacy twin (design §4.1 row G:
goldens 0 retired, demo 0 px). It does not touch the legacy engine, the layout
authority, the lowering table or the harness of stage 1; nothing in
`LegacyLowering.swift`, `LayoutAuthority.swift`, `Box.swift` or
`ModifiedElement.swift` changes. The integrator's documentation obligations
(CLAUDE.md vocabulary and unprobed-behaviour lists, the divergence and inert
tables, design §4.1 and §8, the plan's task 7 note, record README) are listed
in record §20's "For the integrator", written by lane 4.
