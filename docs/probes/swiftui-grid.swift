// SwiftUI probe: Grid and GridRow — column widths, row heights, spacing,
// proposals, flexibility, layout priority, Spacer cells, spans and non-row
// children, alignment, gridCellAnchor, gridColumnAlignment,
// gridCellUnsizedAxes, which wrappers carry a cell attribute, and GridRow
// outside a Grid. Evidence for rulings GR-… in
// docs/superpowers/2026-09-17-grids-decisions.md (plan task 7, stage G).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-grid.swift                          # arms + fuzz (the output below)
//   /usr/bin/swift docs/probes/swiftui-grid.swift corpus                   # the replay corpus (docs/probes/swiftui-grid-corpus.txt)
//   /usr/bin/swift docs/probes/swiftui-grid.swift trap-negative-columns    # arm GT1: exits by trap
//   /usr/bin/swift docs/probes/swiftui-grid.swift huge-columns             # arms GX21, GX22, then GX20: exits by trap (revision 5)
//   /usr/bin/swift docs/probes/swiftui-grid.swift model-arms               # the reference model on every arm a Case spells (revision 5)
//   /usr/bin/swift docs/probes/swiftui-grid.swift classify-spans           # GZ6's disagreements by symptom and model variant (revision 5)
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols. The default run takes about twenty seconds.
//
// METHOD. Every figure is read from SwiftUI through an `NSHostingView` whose
// root is the `Probe` layout: it asks the grid for its answer at the stated
// proposal and places it at (0, 0) at that proposal, the containers probe's
// instrument (`swiftui-stack-algorithms.swift`). A cell is an `L` leaf, a custom
// `Layout` that answers a pure function of its proposal (`fx` fixed, `fl`
// proposal ?? 10, `hf` half the width, `fw`/`fh` flexible on one axis, `cb`/`cw`/
// `ch` clamps, `odd` answers 15x15 only at exactly 20x20), logs every
// measurement in order and records its last placed rect and the proposal it was
// placed with. An arm line reads `name (x,y wxh) <- placement proposal`. SwiftUI
// caches measurements, so a "measured, in order" list shows distinct calls only.
// A Spacer or Text cell is read through a flexible `.background` leaf, which is
// placed at the view's own rect. "measured only" arms (`MeasureOnly`) read the
// answer without placing it: SwiftUI traps placing an infinite answer.
//
// CONTROLS (practices shape 15). GA0 (the same leaves in stacks) differs from
// GA1; GR0 shows `odd` answering 15 at 20x20 where GR1/GR2 read 20; GS3 (an 8x8
// leaf) differs from GS2 (a Spacer); GF13 differs from GF12 (only the height
// proposal changes); GU2 and GU10 differ from GU1 and GU9 (unsized removed);
// GX19 differs from GX18 (only the non-row child's width changes); in every GW
// table the `none` row differs from the `HStack{one}` row. GZ0 runs the
// reference model with commits ignored and must disagree: 212 of 300 agree
// against GZ1's 1000 of 1000. Revision 5: GE2, GE7 (an 8x8 leaf where GE1, GE6
// have a Spacer) differ from GE1, GE6; GE24 (the Spacer in the last row)
// differs from GE23 (in the top row); GE8 equals GE9 (no priority), which is
// the finding, and GE27 (the same HStack with no grid: 0/92) shows the priority
// acting; GE11 (50/50) likewise against GE28 (92 and the Spacer at its 8pt
// minimum); GE13 and GE15 (no stack) are the controls
// GE12 and GE14 equal; GG12 (outer row unaligned) differs from GG10 and GG11;
// GN6 is the long Text alone; GX21 (100_000 columns) differs from GX22
// (1 << 40); `model-arms` checks every transcribed arm's SwiftUI answer against
// the arm's own line (0 mismatches) and reports 4 disagreements, so it can
// disagree.
//
// THE REFERENCE MODEL (`solve` and `ModelGrid`, below) is the algorithm the
// grids design ports (spec §4, rulings GR-B…GR-H). It is a SwiftUI `Layout`
// over the SAME leaves, so GZ compares it with `Grid` rect for rect on
// generated grids with fixed seeds (`fuzz`: sizes within 0.01, every leaf's
// rect, and for GZ7 the answer only). It reads layout priority from the
// subview proxy (a bare Spacer's is -inf there) and treats a `.spacer` cell as
// a Spacer for the gap rule only; the kernel's gap rule is the zero-spacing-edge
// walk that GS12-GS18 probe, which agrees with this on a bare Spacer.
//
// RECORDED 2026-09-17 07:38 PDT by the grids design session (plan task 7, stage
// G), macOS 27.0 (26A428), `/usr/bin/swift` = Apple Swift 6.4
// (swiftlang-6.4.0.33.1). Default run: exit 0, run twice, byte-identical stdout
// (`diff` empty). `corpus` run: exit 0, run twice, byte-identical; its stdout is
// committed verbatim as docs/probes/swiftui-grid-corpus.txt (after that file's
// own comment header), sha256 of the stdout
// 88e4e1ec9a545ce071418ac4381181f1e55f34d9831895bc23d746e1ca42ae78, last line
// "// END CORPUS: 120 kept of 193 generated; 73 skipped because SwiftUI and the
// model differ, 0 because an answer was infinite". `trap-negative-columns`: exit
// 133 (SIGTRAP) after printing its first line, run twice.
//
// RE-RECORDED 2026-09-17 (revision 2, the same design session), same machine
// and toolchain, exit 0, run twice with byte-identical output. Additive only:
// arms GS12-GS18 (`armsS2`), printed after GG9; every other line is
// byte-identical to revision 1's output (`diff` of the rest empty). The corpus
// run is unchanged (it does not call the arms).
//
// RE-RECORDED 2026-09-17 (revision 3, the same design session), same machine
// and toolchain, exit 0, run twice with byte-identical output. Additive arms
// GP9-GP11 (`armsP2`), printed after GS18, and one change to the reference
// model: on an infinite proposal axis the share is infinity whatever is
// committed (`w.isInfinite ? w : ...`), where revision 2 computed inf - inf =
// nan. Every revision-2 output line is byte-identical (the GZ counts included:
// no generated grid reached that path); the corpus stdout's sha256 is
// unchanged.
//
// RE-RECORDED 2026-09-17 (revision 4, the same design session), same machine
// and toolchain, exit 0, run twice with byte-identical output. Additive only:
// arms GF14-GF18 (`armsF2`: a greedy frame and a Color as cells), printed after
// GP11; every revision-3 line is byte-identical.
//
// RE-RECORDED 2026-09-17 08:32 PDT (revision 5, the grids design's critic
// round), same machine and toolchain. Default run exit 0, run twice,
// byte-identical; every arm line up to GF18 is byte-identical to revision 4.
// Changes, each measured (record §20, "Critic round"):
// - The generated cells apply `.layoutPriority`, `.gridCellColumns` and
//   `.gridCellUnsizedAxes` only when written (`WrittenAttributes`). Revisions
//   1-4 applied `.layoutPriority(0)` to every cell, which replaces a Spacer's
//   -inf priority with 0, so no generated Spacer was bare. GZ3 moved 479 -> 469.
// - Model step 12: at a non-nil proposal a span's shortfall goes first to the
//   spanned columns that still hold an unprocessed single-column cell (GX9).
//   GZ5 476 -> 482, GZ6 374 -> 376, GZ7 222 -> 231, GZ8 659 -> 662 (with the
//   bare Spacers); GZ0, GZ1, GZ2, GZ4 unchanged.
// - Arms GE1-GE28 (a Grid in a stack), GN1-GN10 (Text and text-like cells),
//   GG10-GG16 (nested rows, row-level cell attributes), GQ9-GQ10 (a Spacer's
//   priority), fuzz GZ9-GZ12, printed
//   after GZ8; modes `model-arms`, `classify-spans`, `huge-columns`; a
//   `.wrap` leaf kind the generator never produces.
// The `corpus` run: exit 0, twice, byte-identical, sha256
// d93bc71acd09a1c745691e65460401d214f6c701bf70c7d0b2e52e2da886f366, last line
// "// END CORPUS: 120 kept of 185 generated; 65 skipped because SwiftUI and the
// model differ, 0 because an answer was infinite". `model-arms`,
// `classify-spans`: exit 0, twice each, byte-identical (stdout below).
// `huge-columns`: exit 133 after printing GX21, GX22 and GX20's first line,
// twice, byte-identical. `trap-negative-columns`: exit 133, twice.
//
// THE READING (arm ids in brackets; "share" and "commit" are defined in 4).
//
// 1. Cells. A column is as wide as its widest single-column cell, a row as tall
//    as its tallest cell, and each cell is placed in its column-width x
//    row-height slot, centred by default [GA1 vs GA0: b at 48, not 38]. The
//    answer is the sum of widths and gaps [GA1 78x58]. An empty Grid and a Grid
//    of an empty GridRow answer 0x0 [GA5, GA6]; an empty GridRow is no row
//    [GA7 30x48: one gap]. Only non-row children make one column [GA8, GA9].
//    Unequal rows leave the short row's missing cells empty [GA4].
// 2. Spacing. Default 8 on both axes [GA1], explicit spacing verbatim [GA2,
//    GA3], negative accepted and unclamped [GS8 60x45], +inf and nan answered as
//    inf and nan [GS9, GS10]. The gap before column j is the LARGEST spacing of
//    any pair of adjacent cells in one row that meet at j, and 0 where no pair
//    meets there [GS5/GS6: col 2 has no cell starting, 76.67 and 68]; the gap
//    before row r likewise over pairs covering one column in rows r-1 and r
//    [GS4: 0 above a Spacer]. A pair's spacing is the explicit spacing if one
//    is given [GS11: 12 beside a Spacer], else 0 if either cell is a Spacer
//    [GS2 48 vs control GS3 64] and 8 otherwise — so one non-spacer pair at a
//    boundary gives 8 [GS1 190 = 142 + 8 + 40]. A Spacer is seen through a
//    frame [GS12, GS17 vs control GS18], a one-child HStack or ZStack [GS14,
//    GS15] and a padding edge whose inset is 0 [GS13: 8 before the padded
//    leading edge, 0 after], and not on an overlay's content side [GS16]: the
//    stacks' zero-spacing-edge rule, ruling CN-H. Text cells get 0 vertically
//    [GS7 36x32], font-derived; not adopted (GR-D).
// 3. Nil proposal. Every cell is measured once at nil [GP3], single-column
//    cells widen their columns, then spanning cells widen theirs [GX7 = GX1:
//    51/41 whichever row declares the span]. A cell is PLACED at its slot size,
//    except that when the slot equals the cell's own answer it is placed at
//    the proposal that answer was measured at [GR1 nil, GR2 96x200; control
//    GR0: 15 at 20x20]. GP3's c and GA4's b show the same (`<- nilxnil`).
// 4. Finite proposals. Every cell is first measured at 0x0 and inf x inf [GP1].
//    Cells are processed in groups ordered by layout priority (higher first),
//    then by the number of axes on which the inf answer is infinite, then by
//    the sum of (inf answer - 0x0 answer) over the other axes; an axis whose
//    proposal is nil counts for neither [GF10: half (one infinite axis) before
//    flexible (two); GF11: width 10...160 (150) before height-flexible (one
//    infinite axis); GF12 vs GF13]. Equal keys form a group, in source order.
//    At a group's start: W' = W - column gaps; SHARE = (W' - the widths of the
//    committed columns) / the number of OPEN columns, an open column being one
//    with an unprocessed single-column cell of this group's priority. Each cell
//    of the group is proposed max(share, its column's current width) [GF7: d at
//    120, b's] and the grid proposal's nil axis stays nil [GP5, GP6]. After the
//    group every column with no unprocessed single-column cell of this
//    priority or higher is COMMITTED, and stays so [GP2: a at 152 = 192 - 40;
//    GF1: both halves at 96, same group; GF8: a at 61.33, then 82 each]. Rows
//    the same on the other axis. The grid does not fill its proposal with
//    fixed content [GP1 78x58 at 200x200] and answers inf when a cell does [GP4
//    infxinf; GP8 78x58]. Flexible content behaves as its answers say: a
//    cell in .frame(maxWidth: .infinity) takes its column's remainder and
//    keeps its row at its child's height [GF14 200x58, a centred in 152; GF15
//    at nil 78x58], a Color takes both [GF16 152x62; GF17 10x20 at nil], a
//    frame greedy on both axes both [GF18 200x100]. On an infinite proposal
//    axis every share is inf,
//    even after a column of infinite width is committed [GP9: b's share
//    measurement is the inf x inf cache hit, then its slot 50 x inf; GP10;
//    GP11 at inf x 100: width inf, height 100].
// 5. Layout priority. Groups of higher priority are served first with no
//    reservation for lower ones [GQ1 92/0; GQ3 84 then 0 and 0, answer 120 at
//    100]; lower-priority columns are not open for a higher group and count as
//    committed at their current width afterwards [GQ2 42 and 42 at 100 then 30:
//    130; GQ4 d at 192x92, then b 192x0 and c 0x92: 210x120; GQ5]. The grid
//    can answer wider than its proposal. A Spacer is priority -inf [GS1: s at
//    142x42 = 192 - 40 - 10 by 92 - 30 - 20; GQ7 with minLength 0; GQ6 at nil;
//    GQ8 alone fills]. (Revision 5.) The subview proxy reads -inf for a bare
//    Spacer, through a background or a gridCellColumns, and the written value
//    for a `.layoutPriority`, 0 included [GQ10]; so `.layoutPriority(0)` makes
//    GS1's Spacer an ordinary flexible cell [GQ9: 200x100, s 152x62].
// 6. Spans. A span's width shortfall is spread equally over its spanned columns
//    that hold no single-column cell, else over all of them [GX1 51/41; GX11:
//    col 1 grows to 82 and col 2 stays 10]. A span is clamped to the columns
//    left [GX6]. A non-row child spans every column and ignores
//    gridCellColumns [GX3, GX4, GX13]. At a finite proposal a spanning cell is
//    proposed W' minus the other columns' shares or committed widths plus its
//    inner gaps [GX8 300x46, GX10 300x82, GX12 300x96], does not keep its
//    columns open [GX9: b at 262], and widens its columns after its group
//    [GX10 151/141]. SwiftUI OVERFLOWS when a span's shortfall is spread while
//    a spanned column is still open: GX17 answers 284 at 200 (b proposed 218),
//    GX18 231.33 at 200 where control GX19 reads 200 (GR-F: not ported).
//    (Revision 5.) At a non-nil proposal the shortfall goes first to the
//    spanned columns still holding an unprocessed single-column cell [GX9: b's
//    column absorbs x's shortfall, a's committed column stays 30]. The model
//    still misreads GS5 (SwiftUI shares 292 over all 3 columns where the model
//    opens only the column with single-column cells: 76.67 vs 164). A column
//    count of 100_000 is clamped [GX21]; 1 << 40 lays out as columns(0)
//    [GX22]; Int.max and Int.max / 2 trap [GX20; Int.max / 2 and Int.max - 1
//    in scratch, record §20].
//    gridCellColumns(0) lays out as neither 0 nor 1 [GX14: c at x 0, d shares
//    column 0]; gridCellColumns(-1) traps [GT1]. Two gridCellColumns on one
//    view add the values above 1 [GX15: 3 and 2 span 5; GX16: 2 and 1 span 2;
//    GWI1, GWI2 through padding].
// 7. Alignment. Grid(alignment:) places on both axes [GL1, GL2] and places
//    non-row children [GL12]; GridRow(alignment:) overrides it vertically
//    [GL3, GL9]. gridColumnAlignment sets the horizontal alignment of the whole
//    column, from any row [GL4, GL5]; the first declaration in row order wins
//    [GL6, GL7]; a span declares it for its first column and is not itself
//    aligned by it [GL8: a trailing, c centred]. gridCellAnchor overrides both
//    [GL10, GL13] and applies to a non-row child [GL11]; it takes any UnitPoint
//    [GL14: (0.25, 1) puts a at (10, 20)]. On one view the inner declaration
//    wins for both [GL15, GL16, GWI3, GWI4].
// 8. gridCellUnsizedAxes. An unsized axis is proposed the cell's current
//    column (or spanned) width / row height instead of a share [GU1 30x172 vs
//    control GU2 152x172; GU6 152x10]; the answer still widens the column [GU4,
//    GU5 148; GU6 78x78]; the processing order is unchanged (GZ2 agrees only
//    with that variant, record §20). A divider-like non-row child stops
//    widening the grid [GU9 58 vs control GU10 200]. A lone cell unsized on
//    both axes answers 0x0 [GU11]. Declarations on one view form a union
//    [GU12, GU13, GWI5].
// 9. Which wrappers carry a cell attribute (GW; each attribute written INSIDE
//    the wrapper). gridCellColumns, gridCellAnchor, gridColumnAlignment and
//    gridCellUnsizedAxes pass through padding, both frames, fixedSize,
//    background/overlay on their primary side, clipped, border, opacity,
//    allowsHitTesting, aspectRatio, layoutPriority, onTapGesture and disabled
//    [GWS/GWA/GWC/GWU 1-14], and not through a one-child HStack or ZStack or
//    the content side of overlay/background [15-18]. (GWS2's fixed frame, GWU2
//    and GWU4 cannot show it; GWA2, GWA4, GWC4 can.) layoutPriority passes
//    through background, overlay's primary side, clipped, border, opacity,
//    allowsHitTesting, layoutPriority, onTapGesture, disabled and a one-child
//    HStack/ZStack, and not through padding, frame(maxWidth:), aspectRatio or
//    overlay content [GWP1, GWP3, GWP11, GWP17]; GWP2 and GWP4 cannot show it.
//    This is the kernel's existing priority walk (ruling CN-D).
// 10. GridRow. Outside a Grid it is its cells [GG1 in a VStack, GG2 in an
//    HStack]; nested in a GridRow it flattens [GG3]; a modifier on it applies
//    to each cell [GG4 padding, GG5 anchor, GG6 columns, GG7 onTapGesture keeps
//    the row]; rows reach the Grid through if and ForEach [GG8]; a container
//    holding a GridRow is a non-row child [GG9]. (Revision 5.) Flattened rows
//    take the OUTERMOST row's alignment, nil included [GG10 a at y 0, GG11 a
//    at y 20, control GG12 a at y 10: the inner .bottom is ignored]; a cell
//    attribute written on a GridRow loses to the cell's own [GG13 anchor, GG14
//    column alignment], columns add [GG15: 2 + 2 spans 4] and unsized axes
//    form a union [GG16].
// 11. The model against SwiftUI (GZ, seeds fixed): 1000/1000 plain; 988/1000
//    with alignment, anchors, column alignment, unsized axes and explicit
//    spacing; 479/500 with Spacer cells; 441/500 with layout priority; 476/500
//    with non-row children; 374/500 with spans; 222/300 answers at infinite
//    proposals with everything; 659/1000 with everything. The first
//    disagreements per group are printed. Every disagreement read involves a
//    span or non-row child, a priority, a Spacer or an unsized axis;
//    none is a plain grid. REVISION 5 COUNTS: GZ3 469/500 (bare Spacers), GZ5
//    482/500, GZ6 376/500, GZ7 231/300, GZ8 662/1000; the others unchanged;
//    plain grids at infinite proposals 300/300 [GZ9], at a zero axis 300/300
//    [GZ10], beside a leaf in an HStack 300/300 [GZ11] and in a VStack 300/300
//    [GZ12]. `classify-spans`: of GZ6's 124 disagreements, 3 are SwiftUI
//    answering wider than a finite proposal where the model fits (the
//    overflow), 64 the model answering wider than SwiftUI, 31 SwiftUI wider
//    without the overflow, 26 equal sizes with different rects; 60 agree under
//    a variant that keeps a span's columns open (4, 6 or both), 1 under
//    variant 1, 63 under none.
// 12. A Grid in a stack (revision 5). Its zero-spacing edges are positional:
//    leading if a cell starting at column 0 has a zero leading edge [GE1, GE4
//    one row of two, GE5, GE26], trailing if a cell ending at the last column
//    has a zero trailing edge [GE3; GE26: a short last row does not], top if a
//    cell of row 0 has a zero top edge [GE6, GE23], bottom if a cell of the
//    last row has [GE23, GE24; GE24's top is 8]; a non-row Spacer gives both
//    [GE25]; an empty Grid gives both [GE16: a and c touch]. A Grid passes NO
//    priority through, a one-cell grid of a priority-1 cell [GE8 = GE9; no
//    grid, GE27: 0/92] or of a Spacer [GE11: 50/50; no grid, GE28: 92/8]
//    included. An enclosing stack does not change
//    a Spacer cell's gaps inside the grid [GE12 = GE13, GE14 = GE15]. The model
//    in a stack agrees with Grid in a stack [GE17-GE22, GZ11, GZ12].
// 13. Text cells (revision 5). A form at 200 x nil answers 196x64: the label
//    column is its widest label (50), the value column 138 = 200 - 50 - 8 - 4
//    (the long value wraps narrower than offered), and rows of Text meet with
//    no gap [GN2, GN5, GN7: 0, as GS7]; at 120 x nil both values wrap [GN3].
//    Text-like `.wrap` leaves in the same shape agree with the model at 200,
//    120 and 60 wide [GN8-GN10].
// 14. The model on the arms (revision 5, `model-arms`): 91 of the 95 arms a
//    `Case` spells agree; GS4 (a Spacer below a priority-0 cell in one column,
//    at 60x60: SwiftUI 90x40, model 45x40), GS5 (a column holding only a span:
//    76.67x136 vs 164x136) and GX17, GX18 (the overflow) do not.
//
// WHOLE STDOUT OF THE DEFAULT RUN (revision 5):
//
//   === GA: column widths, row heights, default and explicit spacing, empty content (nil proposal)
//   GA0 control: VStack{HStack{a 30x10; b 20x20}; HStack{c 10x30; d 40x10}} @nilxnil: size 58x58 | a (0,5 30x10) <- 25x20 | b (38,0 20x20) <- 20x20 | c (0,28 10x30) <- 25x30 | d (18,38 40x10) <- 40x30
//   GA1 Grid{[a 30x10, b 20x20] [c 10x30, d 40x10]} @nilxnil: size 78x58 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GA2 GA1 at spacing 0/0 @nilxnil: size 70x50 | a (0,5 30x10) <- 30x20 | b (40,0 20x20) <- 40x20 | c (10,20 10x30) <- 30x30 | d (30,30 40x10) <- 40x30
//   GA3 GA1 at spacing 3/5 @nilxnil: size 73x55 | a (0,5 30x10) <- 30x20 | b (43,0 20x20) <- 40x20 | c (10,25 10x30) <- 30x30 | d (33,35 40x10) <- 40x30
//   GA4 unequal rows [a 30x10, b 20x20, e 5x5] [c 10x30] @nilxnil: size 71x58 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | e (66,7.50 5x5) <- 5x20 | c (10,28 10x30) <- 30x30
//   GA5 empty Grid{}, read through a background leaf g @nilxnil: size 0x0 | g (0,0 0x0) <- 0x0
//   GA6 Grid{GridRow{}}, read through a background leaf g @nilxnil: size 0x0 | g (0,0 0x0) <- 0x0
//   GA7 an empty GridRow between two rows @nilxnil: size 30x48 | a (0,0 30x10) <- nilxnil | c (10,18 10x30) <- 30x30
//   GA8 only non-row children {x 30x10; y 10x20} @nilxnil: size 30x38 | x (0,0 30x10) <- nilxnil | y (10,18 10x20) <- 30x20
//   GA9 only non-row children {x 30x10; y flexible} at 200x100 @200x100: size 200x100 | x (85,0 30x10) <- 200x10 | y (0,18 200x82) <- 200x82
//   === GP: the grid's answer at nil, finite, one-axis and infinite proposals
//   GP1 GA1 at 200x200 (fixed content answers its nil size) @200x200: size 78x58 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; a 96x96->30x10; b 96x96->20x20; c 96x96->10x30; d 96x96->40x10; a 30x20->30x10; b 40x20->20x20; c 30x30->10x30; d 40x30->40x10
//   GP2 [a flexible, b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 200x100 | a (0,0 152x62) <- 152x62 | b (170,21 20x20) <- 40x62 | c (71,70 10x30) <- 152x30 | d (160,80 40x10) <- 40x30
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->152x62; b 40x62->20x20; c 152x30->10x30; d 40x30->40x10
//   GP3 GP2 at nil @nilxnil: size 58x58 | a (0,0 10x20) <- 10x20 | b (28,0 20x20) <- 40x20 | c (0,28 10x30) <- nilxnil | d (18,38 40x10) <- 40x30
//       measured, in order: a nilxnil->10x10; b nilxnil->20x20; c nilxnil->10x30; d nilxnil->40x10; a 10x20->10x20; b 40x20->20x20; d 40x30->40x10
//   GP4 GP2 at inf x inf @infxinf (measured only): size infxinf
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 40xinf->20x20; c infx30->10x30; d 40x30->40x10; d 20x30->40x10; a 10x20->10x20; b 40x20->20x20
//   GP5 GP2 at 200 x nil @200xnil: size 200x58 | a (0,0 152x20) <- 152x20 | b (170,0 20x20) <- 40x20 | c (71,28 10x30) <- 152x30 | d (160,38 40x10) <- 40x30
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96xnil->20x20; c 96xnil->10x30; d 96xnil->40x10; a 152xnil->152x10; a 152x20->152x20; b 40x20->20x20; c 152x30->10x30; d 40x30->40x10
//   GP6 GP2 at nil x 100 @nilx100: size 58x100 | a (0,0 10x62) <- nilx62 | b (28,21 20x20) <- 40x62 | c (0,70 10x30) <- nilx46 | d (18,80 40x10) <- 40x30
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b nilx46->20x20; c nilx46->10x30; d nilx46->40x10; a nilx62->10x62; b 40x62->20x20; d 40x30->40x10
//   GP7 a single flexible cell at 100x100 @100x100: size 100x100 | a (0,0 100x100) <- 100x100
//   GP8 GA1 at inf x inf (fixed content) @infxinf (measured only): size 78x58
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; a 30x20->30x10; b 40x20->20x20; c 30x30->10x30; d 40x30->40x10; b 0x10->20x20; c 30x0->10x30; d 20x30->40x10
//   === GF: flexibility order, shares and commits at finite proposals
//   GF1 [a half, b 20x20] [c 10x30, d half] at 200x200 @200x200: size 104x58 | a (12,5 24x10) <- 48x20 | b (70,0 20x20) <- 48x20 | c (19,28 10x30) <- 48x30 | d (68,38 24x10) <- 48x30
//       measured, in order: a 0x0->0x10; a infxinf->infx10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->0x10; d infxinf->infx10; b 96x96->20x20; c 96x96->10x30; a 96x96->48x10; d 96x96->48x10; a 48x20->24x10; b 48x20->20x20; c 48x30->10x30; d 48x30->24x10
//   GF2 [a width-flexible h20, b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 200x58 | a (0,0 152x20) <- 152x62 | b (170,0 20x20) <- 40x20 | c (71,28 10x30) <- 152x30 | d (160,38 40x10) <- 40x30
//       measured, in order: a 0x0->0x20; a infxinf->infx20; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->152x20; b 40x20->20x20; c 152x30->10x30; d 40x30->40x10
//   GF3 [a height-flexible w20, b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 68x100 | a (0,0 20x62) <- 152x62 | b (38,21 20x20) <- 40x62 | c (5,70 10x30) <- 20x30 | d (28,80 40x10) <- 40x30
//       measured, in order: a 0x0->20x0; a infxinf->20xinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->20x62; b 40x62->20x20; c 20x30->10x30; d 40x30->40x10
//   GF4 [a clamp 0...150, b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 198x100 | a (0,0 150x62) <- 152x62 | b (168,21 20x20) <- 40x62 | c (70,70 10x30) <- 150x30 | d (158,80 40x10) <- 40x30
//       measured, in order: a 0x0->0x0; a infxinf->150x150; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->150x62; b 40x62->20x20; c 150x30->10x30; d 40x30->40x10
//   GF5 [a clamp 0...50, b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 98x88 | a (0,0 50x50) <- 152x62 | b (68,15 20x20) <- 40x50 | c (20,58 10x30) <- 50x30 | d (58,68 40x10) <- 40x30
//       measured, in order: a 0x0->0x0; a infxinf->50x50; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->50x50; b 40x50->20x20; c 50x30->10x30; d 40x30->40x10
//   GF6 [a flexible, b 20x20] [c 10x30, d flexible] at 200x100 @200x100: size 200x100 | a (0,0 96x46) <- 96x46 | b (142,13 20x20) <- 96x46 | c (43,62 10x30) <- 96x46 | d (104,54 96x46) <- 96x46
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->0x0; d infxinf->infxinf; b 96x46->20x20; c 96x46->10x30; a 96x46->96x46; d 96x46->96x46
//   GF7 overflow [a flexible, b 120x20] [c 10x30, d 40x10] at 100x100 @100x100: size 138x100 | a (0,0 10x62) <- 10x62 | b (18,21 120x20) <- 120x62 | c (0,70 10x30) <- 46x46 | d (58,80 40x10) <- 120x30
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->120x20; b infxinf->120x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 46x46->120x20; c 46x46->10x30; d 120x46->40x10; a 10x62->10x62; b 120x62->120x20; d 120x30->40x10
//   GF8 [a 20x20, b flexible, c flexible] at 200x100 @200x100: size 200x100 | a (0,40 20x20) <- 20x100 | b (28,0 82x100) <- 82x100 | c (118,0 82x100) <- 82x100
//       measured, in order: a 0x0->20x20; a infxinf->20x20; b 0x0->0x0; b infxinf->infxinf; c 0x0->0x0; c infxinf->infxinf; a 61.33x100->20x20; b 82x100->82x100; c 82x100->82x100; a 20x100->20x20
//   GF9 [a width 0...30, b width 0...55] at 100x100 @100x100: size 93x10 | a (0,0 30x10) <- 46x100 | b (38,0 55x10) <- 62x100
//       measured, in order: a 0x0->0x10; a infxinf->30x10; b 0x0->0x10; b infxinf->55x10; a 46x100->30x10; b 62x100->55x10
//   GF10 [a half, b flexible] at 200x100 (one infinite axis before two) @200x100: size 200x100 | a (12,45 24x10) <- 48x100 | b (56,0 144x100) <- 144x100
//       measured, in order: a 0x0->0x10; a infxinf->infx10; b 0x0->0x0; b infxinf->infxinf; a 96x100->48x10; b 144x100->144x100; a 48x100->24x10
//   GF11 [a width 10...20, b height-flexible w20, c width 10...160 h30] at 200x100 (finite 150 before one infinite axis) @200x100: size 138x100 | a (0,45 20x10) <- 20x100 | b (28,0 20x100) <- 82x100 | c (56,35 82x30) <- 82x100
//       measured, in order: a 0x0->10x10; a infxinf->20x10; b 0x0->20x0; b infxinf->20xinf; c 0x0->10x30; c infxinf->160x30; a 61.33x100->20x10; c 82x100->82x30; b 82x100->20x100; a 20x100->20x10
//   GF12 [a clamp 10...50, b height-flexible w30, c flexible] at 150 x nil (a nil axis adds no flexibility) @150xnil: size 150x10 | a (0,0 50x10) <- 52xnil | b (58,0 30x10) <- 44.67xnil | c (96,0 54x10) <- 54xnil
//       measured, in order: a 0x0->10x10; a infxinf->50x50; b 0x0->30x0; b infxinf->30xinf; c 0x0->0x0; c infxinf->infxinf; b 44.67xnil->30x10; a 52xnil->50x10; c 54xnil->54x10
//   GF13 control for GF12: the same at 150x100 @150x100: size 150x100 | a (0,25 44.67x50) <- 44.67x100 | b (52.67,0 30x100) <- 44.67x100 | c (90.67,0 59.33x100) <- 59.33x100
//       measured, in order: a 0x0->10x10; a infxinf->50x50; b 0x0->30x0; b infxinf->30xinf; c 0x0->0x0; c infxinf->infxinf; a 44.67x100->44.67x50; b 44.67x100->30x100; c 59.33x100->59.33x100
//   === GR: the placement proposal is the measured one when the cell equals that answer
//   GR0 control: odd leaf in .frame(width: 20, height: 20) @nilxnil: size 20x20 | a (2.50,2.50 15x15) <- 20x20
//   GR1 [a odd, b 20x20] at nil @nilxnil: size 48x20 | a (0,0 20x20) <- nilxnil | b (28,0 20x20) <- nilxnil
//       measured, in order: a nilxnil->20x20; b nilxnil->20x20
//   GR2 [a odd, b 20x20] at 200x200 @200x200: size 48x20 | a (0,0 20x20) <- 96x200 | b (28,0 20x20) <- 96x200
//       measured, in order: a 0x0->20x20; a infxinf->20x20; b 0x0->20x20; b infxinf->20x20; a 96x200->20x20; b 96x200->20x20
//   === GS: spacing
//   GS1 [Spacer (bg leaf s), b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 190x80 | b (160,11 20x20) <- 40x42 | c (66,50 10x30) <- 142x30 | d (150,60 40x10) <- 40x30 | s (0,0 142x42) <- 142x42
//       measured, in order: b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; b 40x42->20x20; c 142x30->10x30; d 40x30->40x10; s 142x42->142x42
//   GS2 [a 30x10, Spacer (bg s), c height-flexible w10] at nil x 80 @nilx80: size 48x80 | a (0,35 30x10) <- 30x80 | c (38,0 10x80) <- nilx80 | s (30,0 8x80) <- 8x80
//   GS3 control for GS2: Spacer replaced by an 8x8 leaf @nilx80: size 64x80 | a (0,35 30x10) <- 30x80 | s (38,36 8x8) <- 8x80 | c (54,0 10x80) <- nilx80
//   GS4 [a half] [Spacer (bg s), c width 30...180 h20] at 60x60 (no vertical gap above a spacer) @60x60: size 90x40 | a (0,0 30x10) <- 60x100 | c (30,15 60x20) <- 60x30 | s (0,10 30x30) <- 30x30
//   GS5 [a 40x40] [b half, c 20x40 span 2] [d width 0...30 h40] at 300x200 (no gap before a column no cell starts) @300x200: size 76.67x136 | a (4.33,0 40x40) <- 48.67x40 | b (12.17,63 24.33x10) <- 48.67x40 | c (56.67,48 20x40) <- 194.67x61.33 | d (9.33,96 30x40) <- 48.67x40
//       measured, in order: a 0x0->40x40; a infxinf->40x40; b 0x0->0x10; b infxinf->infx10; c 0x0->20x40; c infxinf->20x40; d 0x0->0x40; d infxinf->30x40; a 97.33x61.33->40x40; c 194.67x61.33->20x40; d 97.33x72->30x40; b 97.33x104->48.67x10; a 48.67x40->40x40; b 48.67x40->24.33x10; d 48.67x40->30x40
//   GS6 GS5 at nil @nilxnil: size 68x136 | a (0,0 40x40) <- nilxnil | b (10,63 20x10) <- 40x40 | c (48,48 20x40) <- nilxnil | d (5,96 30x40) <- 40x40
//   GS7 Texts [Hi, Yo] [A, B] (bg leaves) @nilxnil: size 36x32 | t4 (24,16 9x16) <- 9x16 | t3 (2,16 9x16) <- 9x16 | t2 (21,0 15x16) <- 15x16 | t1 (0,0 13x16) <- 13x16
//   GS8 GA1 at spacing -10/-5 @nilxnil: size 60x45 | a (0,5 30x10) <- 30x20 | b (30,0 20x20) <- 40x20 | c (10,15 10x30) <- 30x30 | d (20,25 40x10) <- 40x30
//   GS9 [a, b] at horizontal spacing +inf @nilxnil (measured only): size infx20
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; a 30x20->30x10; a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; b 0x10->20x20
//   GS10 [a, b] at horizontal spacing nan @nilxnil (measured only): size nanx20
//       measured, in order: a nilxnil->30x10; b nilxnil->20x20; a 30x20->30x10; a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; b 0x10->20x20
//   GS11 explicit spacing 12 beside a Spacer: [a 30x10, Spacer, c 10x10] at nil x 80 @nilx80: size 72x70 | a (0,30 30x10) <- 30x70 | c (62,30 10x10) <- 10x70 | s (42,0 8x70) <- 8x70
//   === GX: spans and non-row children
//   GX1 [a 30x10, b 20x20] [c 100x10 span 2] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GX2 [a 30x10, b 20x20] [c 10x10 span 2] @nilxnil: size 58x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (24,28 10x10) <- 58x10
//   GX3 [a 30x10, b 20x20] x 100x10 (non-row) [c 10x30, d 40x10] @nilxnil: size 100x76 | a (5.50,5 30x10) <- 41x20 | b (64.50,0 20x20) <- 51x20 | x (0,28 100x10) <- nilxnil | c (15.50,46 10x30) <- 41x30 | d (54.50,56 40x10) <- 51x30
//   GX4 [a 30x10, b 20x20] x half (non-row) @nilxnil: size 58x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | x (14.50,28 29x10) <- 58x10
//   GX5 [a, b, c 5x5] [x 100x10 span 2, y 1x1] @nilxnil: size 113x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (108,7.50 5x5) <- 5x20 | x (0,28 100x10) <- nilxnil | y (110,32.50 1x1) <- 5x10
//   GX6 [a, b] [x 10x10 span 5] (clamped to the grid) @nilxnil: size 58x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | x (24,28 10x10) <- 58x10
//   GX7 [x 100x10 span 2] [a 30x10, b 20x20] (span declared first) @nilxnil: size 100x38 | x (0,0 100x10) <- nilxnil | a (10.50,23 30x10) <- 51x20 | b (69.50,18 20x20) <- 41x20
//   GX8 GX7 at 300x100 @300x100: size 100x38 | x (0,0 100x10) <- 300x46 | a (10.50,23 30x10) <- 51x20 | b (69.50,18 20x20) <- 41x20
//       measured, in order: x 0x0->100x10; x infxinf->100x10; a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; x 300x46->100x10; a 146x46->30x10; b 146x46->20x20; a 51x20->30x10; b 41x20->20x20
//   GX9 [a 30x10, b flexible] [x 100x10 span 2] at 300x100 @300x100: size 300x100 | a (0,36 30x10) <- 30x82 | b (38,0 262x82) <- 262x82 | x (100,90 100x10) <- 300x10
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->0x0; b infxinf->infxinf; x 0x0->100x10; x infxinf->100x10; a 146x46->30x10; x 300x46->100x10; b 262x82->262x82; a 30x82->30x10; x 300x10->100x10
//   GX10 [a 30x10, b 20x10] [x flexible span 2] at 300x100 @300x100: size 300x100 | a (60.50,0 30x10) <- 151x10 | b (219.50,0 20x10) <- 141x10 | x (0,18 300x82) <- 300x82
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x10; b infxinf->20x10; x 0x0->0x0; x infxinf->infxinf; a 146x46->30x10; b 146x46->20x10; x 300x82->300x82; a 151x10->30x10; b 141x10->20x10
//   GX11 excess goes to a spanned column with no single-column cell: [a 0...100, b 100x40 span 2, c width 30...40 h40 span 2] [d height-flexible w10 span 2, e height-flexible w10, f width 30...180 h10] @nilxnil: size 156x58 | a (0,0 10x40) <- 10x40 | b (18,0 100x40) <- nilxnil | c (126,0 30x40) <- nilxnil | d (45,48 10x10) <- 100x10 | e (108,48 10x10) <- nilxnil | f (126,48 30x10) <- nilxnil
//   GX12 a flexible non-row child is proposed the whole width: [a clamp 20...120, b width 0...60 h30] x width-flexible h10 at 300x200 @300x200: size 300x114 | a (28,0 120x96) <- 176x96 | b (212,33 60x30) <- 116x96 | x (0,104 300x10) <- 300x96
//       measured, in order: a 0x0->20x20; a infxinf->120x120; b 0x0->0x30; b infxinf->60x30; x 0x0->0x10; x infxinf->infx10; b 146x96->60x30; a 232x96->120x96; x 300x96->300x10; a 176x96->120x96; b 116x96->60x30
//   GX13 gridCellColumns on a non-row child is ignored: [a, b, e 5x5] x 10x10 columns(1) @nilxnil: size 71x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | e (66,7.50 5x5) <- 5x20 | x (30.50,28 10x10) <- 71x10
//   GX14 gridCellColumns(0): [a, b] [c 10x10 columns(0), d 5x5] @nilxnil: size 58x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (0,28 10x10) <- 30x10 | d (12.50,30.50 5x5) <- 30x10
//   GX15 stacked columns: [a,b,e 5x5,f 5x5] [c 100x10 columns(3).columns(2), d 1x1] @nilxnil: size 109x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | e (66,7.50 5x5) <- 5x20 | f (79,7.50 5x5) <- 5x20 | c (0,28 100x10) <- nilxnil | d (108,32.50 1x1) <- 1x10
//   GX16 stacked columns: the same with columns(2).columns(1) @nilxnil: size 126x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | e (108,7.50 5x5) <- 5x20 | f (121,7.50 5x5) <- 5x20 | c (0,28 100x10) <- nilxnil | d (110,32.50 1x1) <- 5x10
//   GX17 SwiftUI overflow: [a 30x10, b flexible, c 20x20] [x 150x10 span 3] at 200x100 @200x100: size 284x100 | a (0,36 30x10) <- 30x82 | b (38,0 218.00x82) <- 218.00x82 | c (264,31 20x20) <- 20x82 | x (67,90 150x10) <- 284x10
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->0x0; b infxinf->infxinf; c 0x0->20x20; c infxinf->20x20; x 0x0->150x10; x infxinf->150x10; a 61.33x46->30x10; c 61.33x46->20x20; x 200.00x46->150x10; b 218.00x82->218.00x82; a 30x82->30x10; c 20x82->20x20; x 284x10->150x10
//   GX18 SwiftUI overflow: [a flexible, b width 10...30, c width 20...50] x 60x10 at 200x100 @200x100: size 231.33x100 | a (0,0 135.33x82) <- 135.33x82 | b (143.33,36 30x10) <- 30x82 | c (181.33,36 50x10) <- 50x82 | x (85.67,90 60x10) <- 231.33x10
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->10x10; b infxinf->30x10; c 0x0->20x10; c infxinf->50x10; x 0x0->60x10; x infxinf->60x10; x 200.00x46->60x10; b 61.33x82->30x10; c 92.67x82->50x10; a 135.33x82->135.33x82; b 30x82->30x10; c 50x82->50x10; x 231.33x10->60x10
//   GX19 control for GX18: x 40x10 @200x100: size 200x100 | a (0,0 104x82) <- 104x82 | b (112,36 30x10) <- 30x82 | c (150,36 50x10) <- 50x82 | x (80,90 40x10) <- 200x10
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->10x10; b infxinf->30x10; c 0x0->20x10; c infxinf->50x10; x 0x0->40x10; x infxinf->40x10; x 200.00x46->40x10; b 61.33x82->30x10; c 77x82->50x10; a 104x82->104x82; b 30x82->30x10; c 50x82->50x10; x 200x10->40x10
//   === GQ: layout priority and Spacer
//   GQ1 [a flexible, b flexible priority 1] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | b (8,0 92x100) <- 92x100
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->0x0; b infxinf->infxinf; b 92x100->92x100; a 0x100->0x100
//   GQ2 [a width 0...200, b width 30...200 priority -1, c width 20...200] at 100x100 @100x100: size 130x10 | a (0,0 42x10) <- 42x100 | b (50,0 30x10) <- 0x90 | c (88,0 42x10) <- 42x100
//       measured, in order: a 0x0->0x10; a infxinf->200x10; b 0x0->30x10; b infxinf->200x10; c 0x0->20x10; c infxinf->200x10; c 42x100->42x10; a 42x100->42x10; b 0x90->30x10
//   GQ3 [a width 0...200, b width 30...200 priority 1, c width 20...200] at 100x100 @100x100: size 120x10 | a (0,0 0x10) <- 0x90 | b (8,0 84x10) <- 84x100 | c (100,0 20x10) <- 0x90
//       measured, in order: a 0x0->0x10; a infxinf->200x10; b 0x0->30x10; b infxinf->200x10; c 0x0->20x10; c infxinf->200x10; b 84x100->84x10; c 0x90->20x10; a 0x90->0x10
//   GQ4 [a flexible, b 20x20] [c 10x30, d flexible priority 1] at 200x100 @200x100: size 210x120 | a (0,0 10x20) <- 10x20 | b (104,0 20x20) <- 192x20 | c (0,59 10x30) <- 10x92 | d (18,28 192x92) <- 192x92
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->0x0; d infxinf->infxinf; d 192x92->192x92; b 192x0->20x20; c 0x92->10x30; a 10x20->10x20; b 192x20->20x20; c 10x92->10x30
//   GQ5 [a clamp 10...70 priority 1] [b 20x10 priority 1, c 150x30, d width 30...180 h40] at 100x100 @100x100: size 266x118 | a (0,0 70x70) <- 84x82 | b (25,93 20x10) <- 70x40 | c (78,83 150x30) <- 150x40 | d (236,78 30x40) <- 0x30
//       measured, in order: a 0x0->10x10; a infxinf->70x70; b 0x0->20x10; b infxinf->20x10; c 0x0->150x30; c infxinf->150x30; d 0x0->30x40; d infxinf->180x40; b 84x46->20x10; a 84x82->70x70; c 7x12->150x30; d 0x30->30x40; b 70x40->20x10; c 150x40->150x30
//   GQ6 GS1 at nil @nilxnil: size 58x58 | b (28,0 20x20) <- 40x20 | c (0,28 10x30) <- nilxnil | d (18,38 40x10) <- 40x30 | s (0,0 10x20) <- 10x20
//       measured, in order: b nilxnil->20x20; c nilxnil->10x30; d nilxnil->40x10; b 40x20->20x20; d 40x30->40x10; s 10x20->10x20
//   GQ7 GS1 with Spacer(minLength: 0) @200x100: size 190x80 | b (160,11 20x20) <- 40x42 | c (66,50 10x30) <- 142x30 | d (150,60 40x10) <- 40x30 | s (0,0 142x42) <- 142x42
//   GQ8 a lone Spacer at 100x100 @100x100: size 100x100 | s (0,0 100x100) <- 100x100
//   === GL: alignment, anchors, column alignment
//   GL1 GA1 alignment .topLeading @nilxnil: size 78x58 | a (0,0 30x10) <- 30x20 | b (38,0 20x20) <- 40x20 | c (0,28 10x30) <- 30x30 | d (38,28 40x10) <- 40x30
//   GL2 GA1 alignment .bottomTrailing @nilxnil: size 78x58 | a (0,10 30x10) <- 30x20 | b (58,0 20x20) <- 40x20 | c (20,28 10x30) <- 30x30 | d (38,48 40x10) <- 40x30
//   GL3 GA1 with GridRow(alignment: .top) on row 0 @nilxnil: size 78x58 | a (0,0 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GL4 GA1 with b.gridColumnAlignment(.trailing) @nilxnil: size 78x58 | a (0,5 30x10) <- 30x20 | b (58,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GL5 [a 10x10, b 20x20] [c 30x30 columnAlignment trailing, d 40x10] (declared in a later row) @nilxnil: size 78x58 | a (20,5 10x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x30) <- nilxnil | d (38,38 40x10) <- 40x30
//   GL6 [a 10x10 leading] [b 10x10] [c 30x10 trailing]: the first declaration wins @nilxnil: size 30x46 | a (0,0 10x10) <- 30x10 | b (0,18 10x10) <- 30x10 | c (0,36 30x10) <- nilxnil
//   GL7 GL6 reversed: [a trailing] [b] [c leading] @nilxnil: size 30x46 | a (20,0 10x10) <- 30x10 | b (20,18 10x10) <- 30x10 | c (0,36 30x10) <- nilxnil
//   GL8 [a 10x10, b 10x10] [c 30x10 span 2 trailing] [d 40x10]: a span declares for its first column and is not itself aligned by it @nilxnil: size 58x46 | a (30,0 10x10) <- 40x10 | b (48,0 10x10) <- nilxnil | c (14,18 30x10) <- 58x10 | d (0,36 40x10) <- nilxnil
//   GL9 Grid(.bottom) {[row .top: a 10x10, b 10x30] [c 10x10, d 10x30]} @nilxnil: size 28x68 | a (0,0 10x10) <- 10x30 | b (18,0 10x30) <- nilxnil | c (0,58 10x10) <- 10x30 | d (18,38 10x30) <- nilxnil
//   GL10 [a 10x10 anchor topLeading + column trailing, b 10x30] [c 40x10]: the anchor wins @nilxnil: size 58x48 | a (0,0 10x10) <- 40x30 | b (48,0 10x30) <- nilxnil | c (0,38 40x10) <- nilxnil
//   GL11 [a 40x10, b 10x30] x 10x10 anchor .trailing (non-row) @nilxnil: size 58x48 | a (0,10 40x10) <- 40x30 | b (48,0 10x30) <- nilxnil | x (48,38 10x10) <- 58x10
//   GL12 Grid(.leading) {[a 40x10, b 10x30] x 10x10 (non-row)} @nilxnil: size 58x48 | a (0,10 40x10) <- 40x30 | b (48,0 10x30) <- nilxnil | x (0,38 10x10) <- 58x10
//   GL13 Grid(.topLeading) {[row .bottom: a 10x10 column trailing, b 20x40, e 10x10 anchor center] [c 30x30, d 40x10, f 30x30]} @nilxnil: size 116x78 | a (20,30 10x10) <- 30x40 | b (38,0 20x40) <- 40x40 | e (96,15 10x10) <- 30x40 | c (0,48 30x30) <- nilxnil | d (38,48 40x10) <- 40x30 | f (86,48 30x30) <- nilxnil
//   GL14 anchor UnitPoint(x: 0.25, y: 1): [a 10x10, b 10x30] [c 50x10] @nilxnil: size 68x48 | a (10,20 10x10) <- 50x30 | b (58,0 10x30) <- nilxnil | c (0,38 50x10) <- nilxnil
//   GL15 [a 10x10 columnAlignment(.leading).columnAlignment(.trailing)] [e 50x10]: the inner declaration wins @nilxnil: size 50x28 | a (0,0 10x10) <- 50x10 | e (0,18 50x10) <- nilxnil
//   GL16 [a 50x10, b 20x50] [c 10x10 anchor(.topLeading).anchor(.bottomTrailing), d 20x50]: the inner anchor wins @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   === GU: gridCellUnsizedAxes
//   GU1 [a 30x10, b 20x20] [c flexible unsized h, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->0x0; c infxinf->infxinf; d 0x0->40x10; d infxinf->40x10; a 96x96->30x10; b 96x96->20x20; d 96x96->40x10; c 30x172->30x172; a 30x20->30x10; b 40x20->20x20; d 40x172->40x10
//   GU2 control for GU1: c not unsized @200x200: size 200x200 | a (61,5 30x10) <- 152x20 | b (170,0 20x20) <- 40x20 | c (0,28 152x172) <- 152x172 | d (160,109 40x10) <- 40x172
//   GU3 [a, b] [c flexible unsized both, span 2] at 200x200 @200x200: size 58x28 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- 96x96 | c (0,28 58x0) <- 58x0
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->0x0; c infxinf->infxinf; a 96x96->30x10; b 96x96->20x20; c 58x0->58x0; a 30x20->30x10
//   GU4 [a, b] [c 100x30 unsized h, d 40x10] at nil (the answer still counts) @nilxnil: size 148x58 | a (35,5 30x10) <- 100x20 | b (118,0 20x20) <- 40x20 | c (0,28 100x30) <- nilxnil | d (108,38 40x10) <- 40x30
//   GU5 GU4 at 200x200 (the answer still counts) @200x200: size 148x58 | a (35,5 30x10) <- 100x20 | b (118,0 20x20) <- 40x20 | c (0,28 100x30) <- 30x172 | d (108,38 40x10) <- 40x30
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->100x30; c infxinf->100x30; d 0x0->40x10; d infxinf->40x10; a 96x96->30x10; b 96x96->20x20; d 96x96->40x10; c 30x172->100x30; a 100x20->30x10; b 40x20->20x20; d 40x30->40x10
//   GU6 [a, b] [c 10x50 unsized v, d 40x10] at 200x200 @200x200: size 78x78 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x50) <- 30x50 | d (38,48 40x10) <- 40x50
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x50; c infxinf->10x50; d 0x0->40x10; d infxinf->40x10; a 96x96->30x10; b 96x96->20x20; d 96x96->40x10; c 152x10->10x50; a 30x20->30x10; b 40x20->20x20; c 30x50->10x50; d 40x50->40x10
//   GU7 [a flexible unsized h, b flexible] [c 30x30, d 40x10] at 200x100 @200x100: size 134x100 | a (0,0 30x62) <- 30x62 | b (38,0 96x62) <- 96x62 | c (0,70 30x30) <- 96x46 | d (66,80 40x10) <- 96x30
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->0x0; b infxinf->infxinf; c 0x0->30x30; c infxinf->30x30; d 0x0->40x10; d infxinf->40x10; c 96x46->30x30; d 96x46->40x10; b 96x62->96x62; a 30x62->30x62; d 96x30->40x10
//   GU8 [a width 0...50 unsized h, b flexible] [c 30x30, d 40x10] at 200x100 @200x100: size 200x100 | a (0,26 30x10) <- 30x62 | b (38,0 162x62) <- 162x62 | c (0,70 30x30) <- 96x46 | d (99,80 40x10) <- 162x30
//       measured, in order: a 0x0->0x10; a infxinf->50x10; b 0x0->0x0; b infxinf->infxinf; c 0x0->30x30; c infxinf->30x30; d 0x0->40x10; d infxinf->40x10; c 96x46->30x30; d 96x46->40x10; a 30x62->30x10; b 162x62->162x62; d 162x30->40x10
//   GU9 divider-like: [a, b] x flexible unsized h (non-row) at 200x100 @200x100: size 58x100 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- 96x46 | x (0,28 58x72) <- 58x72
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; x 0x0->0x0; x infxinf->infxinf; a 96x46->30x10; b 96x46->20x20; x 58x72->58x72; a 30x20->30x10
//   GU10 control for GU9: x not unsized @200x100: size 200x100 | a (35.50,5 30x10) <- 101x20 | b (144.50,0 20x20) <- 91x20 | x (0,28 200x72) <- 200x72
//   GU11 a lone flexible cell unsized on both axes at 200x100 @200x100: size 0x0 | a (0,0 0x0) <- 0x0
//   GU12 union: c unsized(.vertical).unsized(.horizontal) at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x10) <- 30x10 | d (38,28 40x10) <- 96x96
//   GU13 union: c unsized(.horizontal).unsized([]) at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   === GW: which wrappers a cell attribute passes through (each attribute written INSIDE the wrapper)
//   GWS0 span 2 inside none: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS1 span 2 inside padding(1): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 102x40 | a (11,5 30x10) <- 52x20 | b (71,0 20x20) <- 42x20 | c (1,29 100x10) <- nilxnil
//   GWS2 span 2 inside frame(width:12,height:12): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 58x40 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (-21,29 100x10) <- 12x12
//   GWS3 span 2 inside frame(maxWidth:.infinity): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS4 span 2 inside fixedSize(): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS5 span 2 inside background(Color): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS6 span 2 inside overlay(Color) primary: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS7 span 2 inside clipped(): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS8 span 2 inside border(Color): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS9 span 2 inside opacity(0.5): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS10 span 2 inside allowsHitTesting(false): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS11 span 2 inside aspectRatio(1,.fit): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS12 span 2 inside layoutPriority(1): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS13 span 2 inside onTapGesture: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS14 span 2 inside disabled(true): [a 30x10, b 20x20] [c 100x10] @nilxnil: size 100x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | c (0,28 100x10) <- nilxnil
//   GWS15 span 2 inside HStack{one}: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 128x38 | a (35,5 30x10) <- 100x20 | b (108,0 20x20) <- nilxnil | c (0,28 100x10) <- nilx10
//   GWS16 span 2 inside ZStack{one}: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 128x38 | a (35,5 30x10) <- 100x20 | b (108,0 20x20) <- nilxnil | c (0,28 100x10) <- 100x10
//   GWS17 span 2 inside overlay content side: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 58x29 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (-35,23.50 100x10) <- 1x1
//   GWS18 span 2 inside background content side: [a 30x10, b 20x20] [c 100x10] @nilxnil: size 58x29 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (-35,23.50 100x10) <- 1x1
//   GWA0 anchor topLeading inside none: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA1 anchor topLeading inside padding(1): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (1,59 10x10) <- 48x48 | d (58,58 20x50) <- nilxnil
//   GWA2 anchor topLeading inside frame(width:12,height:12): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | d (58,58 20x50) <- nilxnil | c (1,59 10x10) <- 12x12
//   GWA3 anchor topLeading inside frame(maxWidth:.infinity): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (20,58 10x10) <- 50x10 | d (58,58 20x50) <- nilxnil
//   GWA4 anchor topLeading inside fixedSize(): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- nilxnil | d (58,58 20x50) <- nilxnil
//   GWA5 anchor topLeading inside background(Color): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA6 anchor topLeading inside overlay(Color) primary: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA7 anchor topLeading inside clipped(): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA8 anchor topLeading inside border(Color): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA9 anchor topLeading inside opacity(0.5): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA10 anchor topLeading inside allowsHitTesting(false): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA11 anchor topLeading inside aspectRatio(1,.fit): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA12 anchor topLeading inside layoutPriority(1): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA13 anchor topLeading inside onTapGesture: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA14 anchor topLeading inside disabled(true): [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA15 anchor topLeading inside HStack{one}: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (20,78 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GWA16 anchor topLeading inside ZStack{one}: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (20,78 10x10) <- 10x10 | d (58,58 20x50) <- nilxnil
//   GWA17 anchor topLeading inside overlay content side: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | d (58,58 20x50) <- nilxnil | c (20,78 10x10) <- 1x1
//   GWA18 anchor topLeading inside background content side: [a 50x10, b 20x50] [c 10x10, d 20x50] @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | d (58,58 20x50) <- nilxnil | c (20,78 10x10) <- 1x1
//   GWC0 columnAlignment trailing inside none: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC1 columnAlignment trailing inside padding(1): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (39,33 10x10) <- 48x18 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC2 columnAlignment trailing inside frame(width:12,height:12): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil | c (39,33 10x10) <- 12x12
//   GWC3 columnAlignment trailing inside frame(maxWidth:.infinity): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (20,33 10x10) <- 50x10 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC4 columnAlignment trailing inside fixedSize(): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- nilxnil | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC5 columnAlignment trailing inside background(Color): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC6 columnAlignment trailing inside overlay(Color) primary: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC7 columnAlignment trailing inside clipped(): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC8 columnAlignment trailing inside border(Color): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC9 columnAlignment trailing inside opacity(0.5): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC10 columnAlignment trailing inside allowsHitTesting(false): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC11 columnAlignment trailing inside aspectRatio(1,.fit): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 20x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC12 columnAlignment trailing inside layoutPriority(1): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC13 columnAlignment trailing inside onTapGesture: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC14 columnAlignment trailing inside disabled(true): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (40,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (40,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC15 columnAlignment trailing inside HStack{one}: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (20,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (20,33 10x10) <- 50x20 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC16 columnAlignment trailing inside ZStack{one}: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (20,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | c (20,33 10x10) <- 10x10 | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil
//   GWC17 columnAlignment trailing inside overlay content side: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (20,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil | c (20,33 10x10) <- 1x1
//   GWC18 columnAlignment trailing inside background content side: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10] @nilxnil: size 78x66 | a (20,5 10x10) <- 50x20 | b (58,0 20x20) <- nilxnil | d (58,28 20x20) <- nilxnil | e (0,56 50x10) <- nilxnil | c (20,33 10x10) <- 1x1
//   GWU0 unsized h inside none: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU1 unsized h inside padding(1): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (1,29 28x170) <- 28x170 | d (38,109 40x10) <- 40x172
//   GWU2 unsized h inside frame(width:12,height:12): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x40 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | d (38,29 40x10) <- 40x12 | c (9,28 12x12) <- 12x12
//   GWU3 unsized h inside frame(maxWidth:.infinity): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU4 unsized h inside fixedSize(): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x10) <- nilxnil | d (38,28 40x10) <- 96x96
//   GWU5 unsized h inside background(Color): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU6 unsized h inside overlay(Color) primary: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU7 unsized h inside clipped(): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU8 unsized h inside border(Color): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU9 unsized h inside opacity(0.5): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU10 unsized h inside allowsHitTesting(false): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU11 unsized h inside aspectRatio(1,.fit): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x58 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GWU12 unsized h inside layoutPriority(1): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x220 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x192) <- 30x192 | d (38,119 40x10) <- 40x192
//   GWU13 unsized h inside onTapGesture: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU14 unsized h inside disabled(true): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x200 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x172) <- 30x172 | d (38,109 40x10) <- 40x172
//   GWU15 unsized h inside HStack{one}: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 200x200 | a (61,5 30x10) <- 152x20 | b (170,0 20x20) <- 40x20 | c (0,28 152x172) <- 152x172 | d (160,109 40x10) <- 40x172
//   GWU16 unsized h inside ZStack{one}: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 200x200 | a (61,5 30x10) <- 152x20 | b (170,0 20x20) <- 40x20 | c (0,28 152x172) <- 152x172 | d (160,109 40x10) <- 40x172
//   GWU17 unsized h inside overlay content side: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | d (38,28 40x10) <- 96x96 | c (14.50,32.50 1x1) <- 1x1
//   GWU18 unsized h inside background content side: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | d (38,28 40x10) <- 96x96 | c (14.50,32.50 1x1) <- 1x1
//   GWP0 priority 1 inside none: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP1 priority 1 inside padding(1): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (55,1 44x98) <- 44x98
//   GWP2 priority 1 inside frame(width:12,height:12): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 80x100) <- 80x100 | c (88,44 12x12) <- 12x12
//   GWP3 priority 1 inside frame(maxWidth:.infinity): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (54,0 46x100) <- 46x100
//   GWP4 priority 1 inside fixedSize(): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 82x100) <- 82x100 | c (90,45 10x10) <- nilxnil
//   GWP5 priority 1 inside background(Color): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP6 priority 1 inside overlay(Color) primary: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP7 priority 1 inside clipped(): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP8 priority 1 inside border(Color): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP9 priority 1 inside opacity(0.5): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP10 priority 1 inside allowsHitTesting(false): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP11 priority 1 inside aspectRatio(1,.fit): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (54,27 46x46) <- 46x46
//   GWP12 priority 1 inside layoutPriority(1): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP13 priority 1 inside onTapGesture: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP14 priority 1 inside disabled(true): [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP15 priority 1 inside HStack{one}: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP16 priority 1 inside ZStack{one}: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GWP17 priority 1 inside overlay content side: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 91x100) <- 91x100 | c (99,49.50 1x1) <- 1x1
//   GWP18 priority 1 inside background content side: [a flexible, c flexible] at 100x100 @100x100: size 100x100 | a (0,0 91x100) <- 91x100 | c (99,49.50 1x1) <- 1x1
//   GWI1 inner span 2, padding, outer span 1: [a 30x10, b 20x20, e 5x5] [c 100x10, d 5x5] @nilxnil: size 115x40 | a (11,5 30x10) <- 52x20 | b (71,0 20x20) <- 42x20 | e (110,7.50 5x5) <- 5x20 | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//   GWI2 inner span 1, padding, outer span 2 @nilxnil: size 115x40 | a (11,5 30x10) <- 52x20 | b (71,0 20x20) <- 42x20 | e (110,7.50 5x5) <- 5x20 | c (1,29 100x10) <- nilxnil | d (110,31.50 5x5) <- 5x12
//   GWI3 inner anchor topLeading, padding, outer bottomTrailing @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (1,59 10x10) <- 48x48 | d (58,58 20x50) <- nilxnil
//   GWI4 inner column leading, padding, outer trailing: [a 10x10] [e 50x10] @nilxnil: size 50x30 | a (1,1 10x10) <- 48x10 | e (0,20 50x10) <- nilxnil
//   GWI5 unsized v, padding, unsized h (union) at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (1,29 28x8) <- 28x8 | d (38,28 40x10) <- 96x96
//   === GG: GridRow outside and inside a Grid; modifiers on a GridRow
//   GG1 GridRow{a 30x10; b 20x20} inside a VStack @nilxnil: size 30x38 | a (0,0 30x10) <- 30xnil | b (5,18 20x20) <- 30xnil
//   GG2 GridRow{a; b} inside an HStack @nilxnil: size 58x20 | a (0,5 30x10) <- nilx20 | b (38,0 20x20) <- nilx20
//   GG3 a GridRow nested in a GridRow: [[a, b], c 5x5] @nilxnil: size 71x20 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (66,7.50 5x5) <- 5x20
//   GG4 GridRow{a; b}.padding(5) in GA1 @nilxnil: size 88x68 | a (5,10 30x10) <- 30x20 | b (58,5 20x20) <- 30x20 | c (15,38 10x30) <- 40x30 | d (48,48 40x10) <- 40x30
//   GG5 GridRow{c 10x10; d 10x10}.gridCellAnchor(.topLeading) under [a 50x10, b 20x50] @nilxnil: size 78x68 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x10 | d (58,58 10x10) <- 20x10
//   GG6 GridRow{c 100x10; d 100x10}.gridCellColumns(2) under [a, b, e, f] @nilxnil: size 208x38 | a (10.50,5 30x10) <- 51x20 | b (69.50,0 20x20) <- 41x20 | e (128.50,7.50 5x5) <- 46x20 | f (182.50,7.50 5x5) <- 46x20 | c (0,28 100x10) <- nilxnil | d (108,28 100x10) <- nilxnil
//   GG7 GridRow{a; b}.onTapGesture{} in GA1 (still a row) @nilxnil: size 78x58 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GG8 rows through if and ForEach @nilxnil: size 78x58 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GG9 an HStack containing a GridRow is a non-row child: [a, b] HStack{GridRow{c 10x30; d 40x10}} @nilxnil: size 58x58 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (0,28 10x30) <- nilx30 | d (18,38 40x10) <- nilx30
//   === GS (revision 2): a Spacer seen through wrappers and containers, for the gap
//   GS12 [a 30x10, Spacer.frame(width: 8), c 10x10] at nil x 80 @nilx80: size 48x80 | a (0,35 30x10) <- 30x80 | c (38,35 10x10) <- 10x80 | s (30,0 8x80) <- 8x80
//   GS13 [a 30x10, Spacer.padding(.leading, 4), c 10x10] at nil x 80 @nilx80: size 60x80 | a (0,35 30x10) <- 30x80 | c (50,35 10x10) <- 10x80 | s (42,0 8x80) <- 8x80
//   GS14 [a 30x10, HStack(spacing: 0){Spacer}, c 10x10] at nil x 80 @nilx80: size 48x10 | a (0,0 30x10) <- nilx80 | c (38,0 10x10) <- nilx80 | s (30,5 8x0) <- 8x0
//   GS15 [a 30x10, ZStack{Spacer}, c 10x10] at nil x 80 @nilx80: size 48x70 | a (0,30 30x10) <- 30x70 | c (38,30 10x10) <- 10x70 | s (30,0 8x70) <- 8x70
//   GS16 [a 30x10, 8x8 leaf with a Spacer overlay, c 10x10] at nil x 80 @nilx80: size 64x10 | a (0,0 30x10) <- nilx80 | s (38,1 8x8) <- 8x10 | c (54,0 10x10) <- nilx80
//   GS17 [a 30x10] [Spacer.frame(height: 8)] [c 10x10] at 80 x nil @80xnil: size 80x28 | a (25,0 30x10) <- 80x10 | c (35,18 10x10) <- 80x10 | s (0,10 80x8) <- 80x8
//   GS18 control for GS17: [a] [8x8 leaf] [c] at 80 x nil @80xnil: size 30x44 | a (0,0 30x10) <- 80xnil | s (11,18 8x8) <- 30x8 | c (10,34 10x10) <- 30x10
//   === GP (revision 3): a later group after an infinite committed column, at inf
//   GP9 [a flexible, b width 0...50 h10 priority -1] at inf x inf @infxinf (measured only): size infxinf
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->0x10; b infxinf->50x10; b 50xinf->50x10; a 0x10->0x10
//   GP10 [a flexible] [b flexible, c 10x10 priority -1] at inf x inf @infxinf (measured only): size infxinf
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->0x0; b infxinf->infxinf; c 0x0->10x10; c infxinf->10x10; c 10xinf->10x10; b 0x10->0x10
//   GP11 [a flexible, b height-flexible w10 priority -1] at inf x 100 @infx100 (measured only): size infx100
//       measured, in order: a 0x0->0x0; a infxinf->infxinf; b 0x0->10x0; b infxinf->10xinf; a infx100->infx100; b infx100->10x100
//   === GF (revision 4): a greedy frame and a Color as cells
//   GF14 [a 30x10 in .frame(maxWidth: .infinity), b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 200x58 | a (61,5 30x10) <- 152x10 | b (170,0 20x20) <- 40x20 | c (71,28 10x30) <- 152x30 | d (160,38 40x10) <- 40x30
//       measured, in order: a 0x0->30x10; a infxinf->30x10; b 0x0->20x20; b infxinf->20x20; c 0x0->10x30; c infxinf->10x30; d 0x0->40x10; d infxinf->40x10; b 96x46->20x20; c 96x46->10x30; d 96x46->40x10; a 152x62->30x10; a 152x20->30x10; b 40x20->20x20; c 152x30->10x30; d 40x30->40x10; a 152x10->30x10
//   GF15 GF14 at nil @nilxnil: size 78x58 | a (0,5 30x10) <- 30x10 | b (48,0 20x20) <- 40x20 | c (10,28 10x30) <- 30x30 | d (38,38 40x10) <- 40x30
//   GF16 [a Color (bg leaf k), b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 200x100 | b (170,21 20x20) <- 40x62 | c (71,70 10x30) <- 152x30 | d (160,80 40x10) <- 40x30 | k (0,0 152x62) <- 152x62
//   GF17 GF16 at nil @nilxnil: size 58x58 | b (28,0 20x20) <- 40x20 | c (0,28 10x30) <- nilxnil | d (18,38 40x10) <- 40x30 | k (0,0 10x20) <- 10x20
//   GF18 [a 30x10 in .frame(maxWidth: .infinity, maxHeight: .infinity), b 20x20] [c 10x30, d 40x10] at 200x100 @200x100: size 200x100 | a (61,26 30x10) <- 152x62 | b (170,21 20x20) <- 40x62 | c (71,70 10x30) <- 152x30 | d (160,80 40x10) <- 40x30
//   === GZ: the reference model (solve/ModelGrid above) against SwiftUI's Grid on generated grids
//     DIFFERS Grid(center, h nil, v nil) [c1:fixed(150, 20), c2:clampW(10, 40, 40)] @150xnil
//       SwiftUI 168x40 c1(0,10 150x20) c2(158,0 10x40)
//       model   198x40 c1(0,10 150x20) c2(158,0 40x40)
//   FUZZ GZ0 control: the model with commits ignored (must disagree) seed 101: 212 of 300 agree
//   FUZZ GZ1 plain seed 101: 1000 of 1000 agree
//     DIFFERS Grid(trailing, h 12, v 12) [c1:fixed(30, 60) anchor.bottomLeading] [c2:flex, c3:flex unsizedV, c4:flex] @60x60
//       SwiftUI 66x72 c1(0,0 30x60) c2(0,72 30x0) c3(42,72 0x0) c4(54,72 12x0)
//       model   78x72 c1(0,0 30x60) c2(0,72 30x0) c3(42,72 12x0) c4(66,72 12x0)
//     DIFFERS Grid(bottomTrailing, h 3, v nil) [row.center c1:flex col.leading, c2:fixed(30, 10)] [c3:fixed(60, 60) anchor.bottom, c4:fixed(10, 20) col.center] [c5:flexW(10) col.leading, c6:flexH(10) anchor.topLeading, c7:half anchor.topLeading unsizedV] @200x100
//       SwiftUI 200x100 c1(0,0 123x12) c2(126,1 30x10) c3(31.50,20 60x60) c4(136,60 10x20) c5(0,90 123x10) c6(126,88 10x12) c7(159,88 20.50x10)
//       model   200x100 c1(0,0 131.67x12) c2(134.67,1 30x10) c3(35.83,20 60x60) c4(144.67,60 10x20) c5(0,90 131.67x10) c6(134.67,88 10x12) c7(167.67,88 16.17x10)
//     DIFFERS Grid(center, h 0, v nil) [row.top c1:fixed(100, 10) unsizedH] [c2:fixed(150, 30), c3:flexH(20) anchor.topLeading unsizedH] [row.center c4:fixed(20, 60), c5:flexW(20), c6:half] @200x100
//       SwiftUI 187.50x116 c1(25,0 100x10) c2(0,18 150x30) c3(150,18 20x30) c4(65,56 20x60) c5(150,76 25.00x20) c6(178.12,81 6.25x10)
//       model   187.50x123 c1(25,0 100x10) c2(0,21.50 150x30) c3(150,18 20x37) c4(65,63 20x60) c5(150,83 25x20) c6(178.12,88 6.25x10)
//   FUZZ GZ2 alignment, anchors, column alignment, unsized axes, explicit spacing seed 102: 988 of 1000 agree
//     DIFFERS Grid(bottomLeading, h nil, v nil) [c1:half] [row.bottom c2:spacer col.center unsizedV, c3:clampW(30, 180, 20) anchor.center unsizedH] @60x60
//       SwiftUI 75x30 c1(0,0 45x10) c2(0,10 45x20) c3(45,10 30x20)
//       model   45x30 c1(0,0 15x10) c2(0,10 15x20) c3(15,10 30x20)
//     DIFFERS Grid(top, h nil, v nil) [c1:clampW(30, 90, 10)] [c2:spacer, c3:flexW(10)] [c4:flexH(40)] @60x60
//       SwiftUI 120x60 c1(0,0 60x10) c2(0,10 60x10) c3(60,10 60x10) c4(10,20 40x40)
//       model   70x50 c1(0,0 40x10) c2(0,10 40x15) c3(40,10 30x10) c4(0,25 40x25)
//     DIFFERS Grid(bottomTrailing, h nil, v nil) [c1:flex col.trailing, c2:clampW(10, 160, 10)] [c3:spacer anchor.trailing col.trailing, c4:flexH(10) anchor.bottom] [c5:fixed(10, 10), c6:spacer, c7:fixed(100, 10)] @300x200
//       SwiftUI 446x296 c1(0,0 178x139) c2(186,129 160x10) c3(0,147 178x139) c4(261,147 10x139) c5(168,286 10x10) c6(186,286 160x10) c7(346,286 100x10)
//       model   300x200 c1(0,0 96x91) c2(104,81 96x10) c3(0,99 96x91) c4(147,99 10x91) c5(86,190 10x10) c6(104,190 96x10) c7(200,190 100x10)
//   FUZZ GZ3 Spacer cells seed 103: 469 of 500 agree
//     DIFFERS Grid(center, h nil, v nil) [c1:clampW(30, 40, 30), c2:clampBoth(10, 20), c3:fixed(40, 40)] [c4:flexH(30) prio-1] [c5:fixed(40, 30) prio1, c6:clampBoth(20, 170) prio-1] @200x100
//       SwiftUI 180x86 c1(0,5 40x30) c2(80,10 20x20) c3(140,0 40x40) c4(5,48 30x0) c5(0,56 40x30) c6(48,56 84x30)
//       model   138x100 c1(0,5 40x30) c2(59,10 20x20) c3(98,0 40x40) c4(5,48 30x14) c5(0,70 40x30) c6(48,70 42x30)
//     DIFFERS Grid(center, h nil, v nil) [c1:flex, c2:clampW(0, 150, 30)] [c3:half prio1, c4:flexH(10)] [c5:clampW(10, 50, 30), c6:fixed(100, 30)] @100x100
//       SwiftUI 154x98 c1(0,0 46x30) c2(54,0 100x30) c3(11.50,44 23x10) c4(99,38 10x22) c5(0,68 46x30) c6(54,68 100x30)
//       model   154x86 c1(0,0 46x30) c2(54,0 100x30) c3(0,38 46x10) c4(99,38 10x10) c5(0,56 46x30) c6(54,56 100x30)
//     DIFFERS Grid(center, h nil, v nil) [c1:clampW(10, 50, 10), c2:clampW(30, 70, 20) prio1, c3:clampW(30, 130, 20)] [c4:flexH(20), c5:flexH(30)] [c6:fixed(20, 40)] @100x100
//       SwiftUI 136x80 c1(0,5 20x10) c2(28,0 70x20) c3(106,0 30x20) c4(0,28 20x4.00) c5(48,28 30x4.00) c6(0,40 20x40)
//       model   136x100 c1(0,5 20x10) c2(28,0 70x20) c3(106,0 30x20) c4(0,28 20x24) c5(48,28 30x24) c6(0,60 20x40)
//   FUZZ GZ4 layout priority seed 104: 441 of 500 agree
//     DIFFERS Grid(topTrailing, h nil, v nil) FULL c1:fixed(40, 40) col.leading [c2:clampBoth(20, 60), c3:fixed(10, 10) anchor.bottomLeading col.center] [row.top c4:clampBoth(0, 10), c5:flexH(30), c6:fixed(60, 40) col.trailing] @nilxnil
//       SwiftUI 126x116 c1(86,0 40x40) c2(0,48 20x20) c3(28,58 10x10) c4(0,76 10x10) c5(28,76 30x40) c6(66,76 60x40)
//       model   126x116 c1(86,0 40x40) c2(0,48 20x20) c3(28,58 10x10) c4(10,76 10x10) c5(28,76 30x40) c6(66,76 60x40)
//     DIFFERS Grid(topTrailing, h nil, v nil) [c1:flex anchor.trailing col.center unsizedV] [c2:half anchor.topTrailing] FULL c3:clampW(0, 100, 20) col.leading @200x100
//       SwiftUI 200x46 c1(0,0 200x0) c2(100,8 100x10) c3(100,26 100x20)
//       model   200x46 c1(0,0 200x0) c2(100,8 100x10) c3(50,26 100x20)
//     DIFFERS Grid(leading, h nil, v nil) FULL c1:fixed(100, 10) col.center [c2:fixed(40, 40) unsizedH, c3:fixed(60, 20) anchor.top, c4:clampBoth(0, 10) anchor.center] [row.center c5:fixed(150, 40) unsizedH, c6:flex] @60x60
//       SwiftUI 226x106 c1(0,0 100x10) c2(55,18 40x40) c3(158,18 60x20) c4(226,33 0x10) c5(0,66 150x40) c6(158,66 60x40)
//       model   226x106 c1(0,0 100x10) c2(0,18 40x40) c3(158,18 60x20) c4(226,33 0x10) c5(0,66 150x40) c6(158,66 60x40)
//   FUZZ GZ5 non-row children seed 105: 482 of 500 agree
//     DIFFERS Grid(center, h nil, v nil) [c1:clampBoth(10, 160), c2:clampW(0, 30, 30), c3:flexW(20) span3] [c4:fixed(100, 10), c5:clampW(10, 30, 20)] @60x60
//       SwiftUI 126x60 c1(0,0 100x32) c2(108,1 10x30) c3(126,6 0x20) c4(0,45 100x10) c5(108,40 10x20)
//       model   138x60 c1(0,0 100x32) c2(108,1 22x30) c3(138,6 0x20) c4(0,45 100x10) c5(108,40 22x20)
//     DIFFERS Grid(center, h nil, v nil) [c1:clampW(10, 70, 10) span2, c2:flexH(30), c3:flexH(10)] @300x200
//       SwiftUI 126x200 c1(0,95 70x10) c2(78,0 30x200) c3(116,0 10x200)
//       model   66x200 c1(0,95 10x10) c2(18,0 30x200) c3(56,0 10x200)
//     DIFFERS Grid(center, h nil, v nil) [c1:fixed(60, 10)] [c2:clampBoth(0, 60), c3:clampBoth(0, 60), c4:fixed(100, 10) span3] @150xnil
//       SwiftUI 184.50x28 c1(0,0 60x10) c2(0,18 60x10) c3(68,18 8.50x10) c4(84.50,18 100x10)
//       model   193.00x28 c1(0,0 60x10) c2(0,18 60x10) c3(68,18 17x10) c4(93,18 100x10)
//   FUZZ GZ6 spans seed 106: 376 of 500 agree
//     DIFFERS Grid(bottomTrailing, h nil, v nil) [c1:clampW(0, 60, 20) anchor.center unsizedV] [row.center c2:flex span3 col.center unsizedV, c3:clampW(0, 20, 40) span3 anchor.trailing col.center] @infxinf
//       SwiftUI infxinf
//       model   infx68
//     DIFFERS Grid(topLeading, h nil, v nil) [c1:clampW(0, 150, 40) anchor.trailing, c2:clampBoth(0, 10)] [c3:flexH(20) span2] [c4:clampW(10, 160, 40) anchor.topTrailing unsizedH, c5:flexH(10)] @infx100
//       SwiftUI 178x118
//       model   168x118
//     DIFFERS Grid(center, h nil, v nil) FULL c1:clampBoth(10, 70) span2 [row.bottom c2:clampW(30, 40, 10) col.center, c3:flex span3 anchor.trailing col.trailing unsizedH unsizedV] @infx100
//       SwiftUI infx64
//       model   70x64
//   FUZZ GZ7 infinite proposals (sizes only) seed 108: 231 of 300 agree
//     DIFFERS Grid(topTrailing, h nil, v nil) [c1:clampBoth(0, 30) prio1 unsizedH, c2:half prio1] [c3:flexW(40) prio1 anchor.leading col.leading, c4:clampW(30, 40, 10) anchor.topLeading col.trailing, c5:clampW(10, 40, 10) prio1 col.center unsizedH] FULL c6:half unsizedV @300x200
//       SwiftUI 338x96 c1(0,0 30x30) c2(268,0 52x10) c3(0,38 208x40) c4(216,38 40x10) c5(328,38 10x10) c6(169,86 169x10)
//       model   231.50x96 c1(0,0 30x30) c2(179.25,0 34.25x10) c3(0,38 137x40) c4(145,38 40x10) c5(221.50,38 10x10) c6(115.75,86 115.75x10)
//     DIFFERS Grid(bottom, h 3, v nil) [c1:spacer, c2:spacer unsizedV, c3:spacer prio1 unsizedV] [c4:flex prio1 anchor.leading, c5:fixed(20, 20) prio-1 unsizedH] [c6:half span2] @150xnil
//       SwiftUI 314x46 c1(0,0 144x8) c2(147,0 20x8) c3(170,0 144x8) c4(0,8 144x20) c5(147,8 20x20) c6(41.75,36 83.50x10)
//       model   170x46 c1(0,0 72x8) c2(75,0 20x8) c3(98,0 72x8) c4(0,8 72x20) c5(75,8 20x20) c6(23.75,36 47.50x10)
//     DIFFERS Grid(trailing, h nil, v nil) [row.bottom c1:half prio-1, c2:fixed(10, 20) col.center, c3:clampBoth(0, 30)] [c4:clampW(0, 150, 30)] [c5:clampBoth(10, 40) anchor.center col.leading, c6:clampW(10, 30, 10) prio1, c7:clampW(0, 100, 20) anchor.trailing col.leading unsizedH] @nilx80
//       SwiftUI 56x97 c1(0,15.50 10x10) c2(28,5.50 10x20) c3(46,0 10x25.50) c4(0,33.50 20x30) c5(0,71.50 20x25.50) c6(28,79.25 10x10) c7(46,74.25 10x20)
//       model   56x86 c1(0,10 10x10) c2(28,0 10x20) c3(46,0 10x20) c4(0,28 20x30) c5(0,66 20x20) c6(28,71 10x10) c7(46,66 10x20)
//   FUZZ GZ8 everything seed 109: 662 of 1000 agree
//   === GE (revision 5): a Grid inside a stack — its edges, its priority, a Spacer cell, its answers at a stack's proposals
//   GE1 HStack{a 30x10; Grid{[Spacer (bg s), b 20x20]}; c 10x10}: the grid's leading edge @nilxnil: size 76x20 | a (0,5 30x10) <- nilx20 | b (38,0 20x20) <- nilx20 | c (66,5 10x10) <- nilx20 | s (30,0 8x20) <- 8x20
//   GE2 control for GE1: the Spacer replaced by an 8x8 leaf s @nilxnil: size 92x20 | a (0,5 30x10) <- nilx20 | s (38,6 8x8) <- 8x20 | b (54,0 20x20) <- nilx20 | c (82,5 10x10) <- nilx20
//   GE3 HStack{a; Grid{[b 20x20, Spacer (bg s)]}; c}: the trailing edge @nilxnil: size 76x20 | a (0,5 30x10) <- nilx20 | b (38,0 20x20) <- nilx20 | c (66,5 10x10) <- nilx20 | s (58,0 8x20) <- 8x20
//   GE4 HStack{a; Grid{[Spacer (bg s), b 20x20] [d 20x20, e 20x20]}; c}: a Spacer leading one row of two @nilxnil: size 96x48 | a (0,19 30x10) <- nilx48 | b (58,0 20x20) <- nilx20 | d (30,28 20x20) <- nilx20 | e (58,28 20x20) <- nilx20 | c (86,19 10x10) <- nilx48 | s (30,0 20x20) <- 20x20
//   GE5 HStack{a; Grid{[Spacer (bg s), b 20x20] [Spacer (bg t), e 20x20]}; c}: a Spacer leading every row @nilxnil: size 76x48 | a (0,19 30x10) <- nilx48 | b (38,0 20x20) <- nilx20 | e (38,28 20x20) <- nilx20 | c (66,19 10x10) <- nilx48 | t (30,28 8x20) <- 8x20 | s (30,0 8x20) <- 8x20
//   GE6 VStack{a 30x10; Grid{[Spacer (bg s)] [b 20x20]}; c 10x10}: the grid's top edge @nilxnil: size 30x56 | a (0,0 30x10) <- 30xnil | b (5,18 20x20) <- 30xnil | c (10,46 10x10) <- 30xnil | s (5,10 20x8) <- 20x8
//   GE7 control for GE6: the Spacer replaced by an 8x8 leaf s @nilxnil: size 30x72 | a (0,0 30x10) <- 30xnil | s (11,18 8x8) <- 20x8 | b (5,34 20x20) <- 30xnil | c (10,62 10x10) <- 30xnil
//   GE8 HStack{a flexible; Grid{[c flexible priority 1]}} at 100x100: a one-cell grid's priority @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (54,0 46x100) <- 46x100
//   GE9 control for GE8: no priority @100x100: size 100x100 | a (0,0 46x100) <- 46x100 | c (54,0 46x100) <- 46x100
//   GE10 HStack{a flexible; Grid{[c flexible priority 1, d 10x10]}} at 100x100: two cells @100x100: size 100x100 | a (0,0 36x100) <- 36x100 | c (44,0 38x100) <- 38x100 | d (90,45 10x10) <- 10x100
//   GE11 HStack{a flexible; Grid{[Spacer (bg s)]}} at 100x100: a one-cell grid of a Spacer @100x100: size 100x100 | a (0,0 50x100) <- 50x100 | s (50,0 50x100) <- 50x100
//   GE12 HStack(spacing: 0){Grid{[a 30x10] [Spacer (bg s)] [c 10x10]}} at nil x 80: row gaps beside a Spacer under an enclosing HStack @nilx80: size 30x80 | a (0,0 30x10) <- nilx40 | c (10,70 10x10) <- 30x10 | s (0,10 30x60) <- 30x60
//   GE13 control for GE12: the grid with no stack @nilx80: size 30x80 | a (0,0 30x10) <- nilx40 | c (10,70 10x10) <- 30x10 | s (0,10 30x60) <- 30x60
//   GE14 VStack(spacing: 0){Grid{[a 30x10, Spacer (bg s), c 10x10]}} at 80 x nil: column gaps beside a Spacer under an enclosing VStack @80xnil: size 80x10 | a (0,0 30x10) <- 40xnil | c (70,0 10x10) <- 40xnil | s (30,0 40x10) <- 40x10
//   GE15 control for GE14: the grid with no stack @80xnil: size 80x10 | a (0,0 30x10) <- 40xnil | c (70,0 10x10) <- 40xnil | s (30,0 40x10) <- 40x10
//   GE16 HStack{a 30x10; Grid{} ; c 10x10}: an empty grid's edges @nilxnil: size 40x10 | a (0,0 30x10) <- nilx10 | c (30,0 10x10) <- nilx10
//   GE17 HStack{z:flex; Grid(center, h nil, v nil) [a:flex, b:fixed(20, 20)] [c:fixed(10, 30), d:fixed(40, 10)] @200x100} agrees
//       SwiftUI 200x100 a(104,0 48x62) b(170,21 20x20) c(123,70 10x30) d(160,80 40x10) z(0,0 96x100)
//   GE18 HStack{z:flexW(20); Grid(center, h nil, v nil) [a:fixed(30, 10), b:fixed(20, 20)] [c:fixed(10, 30), d:fixed(40, 10)] @200x100} agrees
//       SwiftUI 200x58 a(122,5 30x10) b(170,0 20x20) c(132,28 10x30) d(160,38 40x10) z(0,19 114x20)
//   GE19 VStack{z:flex; Grid(center, h nil, v nil) [a:flex, b:fixed(20, 20)] [c:fixed(10, 30), d:fixed(40, 10)] @200x100} agrees
//       SwiftUI 200x100 a(0,42 152x20) b(170,42 20x20) c(71,70 10x30) d(160,80 40x10) z(0,0 200x34)
//   GE20 HStack{z:clampW(0, 100, 10); Grid(center, h nil, v nil) [b:half, x:flex] [e:fixed(10, 30)] @150x80} agrees
//       SwiftUI 150x80 b(82.94,16 7.88x10) e(81.88,50 10x30) x(102.75,0 47.25x42) z(0,35 71x10)
//   GE21 HStack{z:fixed(30, 10); Grid(center, h nil, v nil) [a:flex, b:fixed(20, 20)] [c:fixed(10, 30), d:fixed(40, 10)] @nilx80} agrees
//       SwiftUI 96x80 a(38,0 10x42) b(66,11 20x20) c(38,50 10x30) d(56,60 40x10) z(0,35 30x10)
//   GE22 VStack{z:half; Grid(center, h nil, v nil) [a:clampW(0, 60, 10), b:flexH(10)] [c:fixed(10, 30), d:fixed(40, 10)] @120xnil} agrees
//       SwiftUI 108x66 a(0,18 60x10) b(83,18 10x10) c(25,36 10x30) d(68,46 40x10) z(24,0 60x10)
//   GE23 VStack{a 30x10; Grid{[Spacer (bg s), b 20x20]}; c 10x10}: a Spacer in the top row beside a leaf @nilxnil: size 30x40 | a (0,0 30x10) <- 30xnil | b (10,10 20x20) <- 30xnil | c (10,30 10x10) <- 30xnil | s (0,10 10x20) <- 10x20
//   GE24 VStack{a 30x10; Grid{[b 20x20] [Spacer (bg s)]}; c 10x10}: a Spacer in the last row only @nilxnil: size 30x56 | a (0,0 30x10) <- 30xnil | b (5,18 20x20) <- 30xnil | c (10,46 10x10) <- 30xnil | s (5,38 20x8) <- 20x8
//   GE25 HStack{a 30x10; Grid{[b 20x20] Spacer (bg s, non-row)}; c 10x10}: a non-row Spacer @nilxnil: size 60x28 | a (0,9 30x10) <- nilx28 | b (30,0 20x20) <- nilx28 | c (50,9 10x10) <- nilx28 | s (30,20 20x8) <- 20x8
//   GE26 HStack{a 30x10; Grid{[b 20x20, e 20x20] [Spacer (bg s)]}; c 10x10}: a Spacer starting a short last row @nilxnil: size 96x28 | a (0,9 30x10) <- nilx28 | b (30,0 20x20) <- nilx28 | e (58,0 20x20) <- nilx28 | c (86,9 10x10) <- nilx28 | s (30,20 20x8) <- 20x8
//   GE27 positive control for GE8: HStack{a flexible; c flexible priority 1} at 100x100, no grid @100x100: size 100x100 | a (0,0 0x100) <- 0x100 | c (8,0 92x100) <- 92x100
//   GE28 positive control for GE11: HStack{a flexible; Spacer (bg s)} at 100x100, no grid @100x100: size 100x100 | a (0,0 92x100) <- 92x100 | s (92,50 8x0) <- 8x0
//   === GN (revision 5): Text cells — a form of labels and wrapping values (Texts read through background leaves)
//   GN1 form [Name, Ada Lovelace] [Address, long] at nil @nilxnil: size 363x32 | t4 (58,16 305x16) <- 305x16 | t3 (0,16 50x16) <- 50x16 | t2 (170,0 81x16) <- 81x16 | t1 (7,0 36x16) <- 36x16
//   GN2 the form at 200 x nil @200xnil: size 196x64 | t4 (58,16 138x48) <- 138x48 | t3 (0,32 50x16) <- 50x16 | t2 (86.50,0 81x16) <- 81x16 | t1 (7,0 36x16) <- 36x16
//   GN3 the form at 120 x nil @120xnil: size 112x144 | t4 (58,32 54x112) <- 54x112 | t3 (0,80 50x16) <- 50x16 | t2 (58,0 54x32) <- 54x32 | t1 (7,8 36x16) <- 36x16
//   GN4 the form, Grid(alignment: .leading), at 200 x nil @200xnil: size 196x64 | t4 (58,16 138x48) <- 138x48 | t3 (0,32 50x16) <- 50x16 | t2 (58,0 81x16) <- 81x16 | t1 (0,0 36x16) <- 36x16
//   GN5 the form at 200 x 100 @200x100: size 196x64 | t4 (58,16 138x48) <- 138x48 | t3 (0,32 50x16) <- 50x16 | t2 (86.50,0 81x16) <- 81x16 | t1 (7,0 36x16) <- 36x16
//   GN6 control: the long Text alone at 128 x nil @128xnil: size 119x48 | t4 (0,0 119x48) <- 119x48
//   GN7 [Text A, Text B] [Text C, Text D] at 80 x nil: row gap between Text rows at a finite width @80xnil: size 28x32 | t4 (18,16 10x16) <- 10x16 | t3 (0,16 10x16) <- 10x16 | t2 (18.50,0 9x16) <- 9x16 | t1 (0.50,0 9x16) <- 9x16
//   GN8 text-like wrap leaves Grid(center, h nil, v nil) [l1:wrap(40, 16), v1:wrap(84, 16)] [l2:wrap(56, 16), v2:wrap(290, 16)] @200xnil agrees
//       SwiftUI 200x72 l1(8,0 40x16) l2(0,40 56x16) v1(90,0 84x16) v2(64,24 136x48)
//   GN9 text-like wrap leaves Grid(center, h nil, v nil) [l1:wrap(40, 16), v1:wrap(84, 16)] [l2:wrap(56, 16), v2:wrap(290, 16)] @120xnil agrees
//       SwiftUI 120x136 l1(8,8 40x16) l2(0,80 56x16) v1(64,0 56x32) v2(64,40 56x96)
//   GN10 text-like wrap leaves Grid(center, h nil, v nil) [l1:wrap(40, 16), v1:wrap(84, 16)] [l2:wrap(56, 16), v2:wrap(290, 16)] @60xnil agrees
//       SwiftUI 60x264 l1(0,16 26x32) l2(0,144 26x48) v1(34,0 26x64) v2(34,72 26x192)
//   === GG (revision 5): nested GridRow alignment; a cell attribute on a GridRow against the cell's own
//   GG10 Grid{GridRow(.top){GridRow(.bottom){a 10x10; b 10x30}; c 10x20}} @nilxnil: size 46x30 | a (0,0 10x10) <- 10x30 | b (18,0 10x30) <- nilxnil | c (36,0 10x20) <- 10x30
//   GG11 the reverse: Grid{GridRow(.bottom){GridRow(.top){a 10x10; b 10x30}; c 10x20}} @nilxnil: size 46x30 | a (0,20 10x10) <- 10x30 | b (18,0 10x30) <- nilxnil | c (36,10 10x20) <- 10x30
//   GG12 control: Grid{GridRow{GridRow(.bottom){a; b}; c}} (outer row unaligned) @nilxnil: size 46x30 | a (0,10 10x10) <- 10x30 | b (18,0 10x30) <- nilxnil | c (36,5 10x20) <- 10x30
//   GG13 [a 50x10, b 20x50] GridRow{c 10x10 anchor(.topLeading); d 20x50}.gridCellAnchor(.bottomTrailing) @nilxnil: size 78x108 | a (0,20 50x10) <- 50x50 | b (58,0 20x50) <- nilxnil | c (0,58 10x10) <- 50x50 | d (58,58 20x50) <- nilxnil
//   GG14 [a 10x10] [e 50x10] with GridRow{a column(.leading)}.gridColumnAlignment(.trailing) @nilxnil: size 50x28 | a (0,0 10x10) <- 50x10 | e (0,18 50x10) <- nilxnil
//   GG15 [a,b,e 5x5,f 5x5,g 5x5] GridRow{c 100x10 columns(2); d 1x1}.gridCellColumns(2) @nilxnil: size 113x38 | a (2,5 30x10) <- 34x20 | b (44,0 20x20) <- 24x20 | e (76,7.50 5x5) <- 9x20 | f (93,7.50 5x5) <- 9x20 | g (108,7.50 5x5) <- 5x20 | c (0,28 100x10) <- nilxnil | d (110,32.50 1x1) <- 5x10
//   GG16 [a 30x10, b 20x20] [c flexible unsized(.vertical)] row .gridCellUnsizedAxes(.horizontal) at 200x200 @200x200: size 78x38 | a (0,5 30x10) <- 30x20 | b (48,0 20x20) <- 40x20 | c (0,28 30x10) <- 30x10 | d (38,28 40x10) <- 20x172
//   === GQ (revision 5): a Spacer with .layoutPriority(0) is not a bare Spacer
//   GQ9 GS1 with Spacer().layoutPriority(0) @200x100: size 200x100 | b (170,21 20x20) <- 40x62 | c (71,70 10x30) <- 152x30 | d (160,80 40x10) <- 40x30 | s (0,0 152x62) <- 152x62
//   GQ10 subview-proxy priority of [Spacer(), Spacer().layoutPriority(0), Spacer().layoutPriority(1), Spacer().background(Color), Spacer().gridCellColumns(1), Color]: -inf, 0.0, 1.0, -inf, -inf, 0.0
//   === GZ (revision 5): plain grids at a stack's probe proposals, and beside a sibling in a stack
//   FUZZ GZ9 plain, infinite proposals (sizes only) seed 110: 300 of 300 agree
//   FUZZ GZ10 plain, a zero axis seed 111: 300 of 300 agree
//   FUZZ GZ11 plain grid beside a leaf in an HStack seed 112: 300 of 300 agree
//   FUZZ GZ12 plain grid below a leaf in a VStack seed 113: 300 of 300 agree
//   DONE
//
// STDOUT OF `model-arms` (revision 5):
//
//   === MODEL-ARMS (revision 5): the reference model on every arm a Case can spell
//   GA1 agrees: 78x58
//   GA2 agrees: 70x50
//   GA3 agrees: 73x55
//   GA4 agrees: 71x58
//   GA7 agrees: 30x48
//   GA8 agrees: 30x38
//   GA9 agrees: 200x100
//   GP1 agrees: 78x58
//   GP2 agrees: 200x100
//   GP3 agrees: 58x58
//   GP4 agrees: infxinf
//   GP5 agrees: 200x58
//   GP6 agrees: 58x100
//   GP7 agrees: 100x100
//   GP8 agrees: 78x58
//   GP9 agrees: infxinf
//   GP10 agrees: infxinf
//   GP11 agrees: infx100
//   GF1 agrees: 104x58
//   GF2 agrees: 200x58
//   GF3 agrees: 68x100
//   GF4 agrees: 198x100
//   GF5 agrees: 98x88
//   GF6 agrees: 200x100
//   GF7 agrees: 138x100
//   GF8 agrees: 200x100
//   GF9 agrees: 93x10
//   GF10 agrees: 200x100
//   GF11 agrees: 138x100
//   GF12 agrees: 150x10
//   GF13 agrees: 150x100
//   GS1 agrees: 190x80
//   GS2 agrees: 48x80
//   GS3 agrees: 64x80
//   GS4 DIFFERS
//       SwiftUI 90x40 a(0,0 30x10) c(30,15 60x20) s(0,10 30x30)
//       model   45x40 a(0,0 15x10) c(15,15 30x20) s(0,10 15x30)
//   GS5 DIFFERS
//       SwiftUI 76.67x136 a(4.33,0 40x40) b(12.17,63 24.33x10) c(56.67,48 20x40) d(9.33,96 30x40)
//       model   164x136 a(48,0 40x40) b(34,63 68x10) c(144,48 20x40) d(53,96 30x40)
//   GS6 agrees: 68x136
//   GS8 agrees: 60x45
//   GS11 agrees: 72x70
//   GX1 agrees: 100x38
//   GX2 agrees: 58x38
//   GX3 agrees: 100x76
//   GX4 agrees: 58x38
//   GX5 agrees: 113x38
//   GX6 agrees: 58x38
//   GX7 agrees: 100x38
//   GX8 agrees: 100x38
//   GX9 agrees: 300x100
//   GX10 agrees: 300x100
//   GX11 agrees: 156x58
//   GX12 agrees: 300x114
//   GX13 agrees: 71x38
//   GX15 (columns 3 + 2 spelled as 5) agrees: 109x38
//   GX16 (columns 2 + 1 spelled as 2) agrees: 126x38
//   GX17 DIFFERS
//       SwiftUI 284x100 a(0,36 30x10) b(38,0 218.00x82) c(264,31 20x20) x(67,90 150x10)
//       model   200x100 a(0,36 30x10) b(38,0 134x82) c(180,31 20x20) x(25,90 150x10)
//   GX18 DIFFERS
//       SwiftUI 231.33x100 a(0,0 135.33x82) b(143.33,36 30x10) c(181.33,36 50x10) x(85.67,90 60x10)
//       model   200x100 a(0,0 104x82) b(112,36 30x10) c(150,36 50x10) x(70,90 60x10)
//   GX19 agrees: 200x100
//   GQ1 agrees: 100x100
//   GQ2 agrees: 130x10
//   GQ3 agrees: 120x10
//   GQ4 agrees: 210x120
//   GQ5 agrees: 266x118
//   GQ6 agrees: 58x58
//   GQ8 agrees: 100x100
//   GL1 agrees: 78x58
//   GL2 agrees: 78x58
//   GL3 agrees: 78x58
//   GL4 agrees: 78x58
//   GL5 agrees: 78x58
//   GL6 agrees: 30x46
//   GL7 agrees: 30x46
//   GL8 agrees: 58x46
//   GL9 agrees: 28x68
//   GL10 agrees: 58x48
//   GL11 agrees: 58x48
//   GL12 agrees: 58x48
//   GL13 agrees: 116x78
//   GL15 (inner leading) agrees: 50x28
//   GL16 (inner topLeading) agrees: 78x108
//   GU1 agrees: 78x200
//   GU2 agrees: 200x200
//   GU3 agrees: 58x28
//   GU4 agrees: 148x58
//   GU5 agrees: 148x58
//   GU6 agrees: 78x78
//   GU7 agrees: 134x100
//   GU8 agrees: 200x100
//   GU9 agrees: 58x100
//   GU10 agrees: 200x100
//   GU11 agrees: 0x0
//   GU12 agrees: 78x38
//   GU13 agrees: 78x200
//   GG3 (flattened) agrees: 71x20
//   GG5 (per cell) agrees: 78x68
//   GG6 (per cell) agrees: 208x38
//   MODEL-ARMS: 91 agree, 4 differ, 0 transcription mismatches, of 95
//
// STDOUT OF `classify-spans` (revision 5):
//
//   CLASSIFY GZ6 (seed 106, 500 grids with spans): 124 disagreements
//     symptom SwiftUI wider than the model, not the overflow above | finite width, nil height: 7
//     symptom SwiftUI wider than the model, not the overflow above | finite x finite: 24
//     symptom SwiftUI wider than the proposal, the model within it | finite x finite: 3
//     symptom equal sizes, rects differ | finite width, nil height: 8
//     symptom equal sizes, rects differ | finite x finite: 17
//     symptom equal sizes, rects differ | nil width, finite height: 1
//     symptom the model wider than SwiftUI | finite width, nil height: 12
//     symptom the model wider than SwiftUI | finite x finite: 50
//     symptom the model wider than SwiftUI | nil width, finite height: 1
//     symptom the model wider than SwiftUI | nil x nil: 1
//     agrees under no single variant: 63
//     agrees under variant 1: 1
//     agrees under variant 4: 18
//     agrees under variant 4+6: 26
//     agrees under variant 6: 16
//
// STDOUT OF `huge-columns` (revision 5; the process ends by trap after the last line):
//
//   GX21 [a 30x10, b 20x20] [c 10x10 columns(100_000), d 5x5]: clamped @nilxnil: size 71x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (24,28 10x10) <- 58x10 | d (66,30.50 5x5) <- 5x10
//   GX22 [a 30x10, b 20x20] [c 10x10 columns(1 << 40), d 5x5] @nilxnil: size 58x38 | a (0,5 30x10) <- 30x20 | b (38,0 20x20) <- nilxnil | c (0,28 10x10) <- 30x10 | d (12.50,30.50 5x5) <- 30x10
//   GX20 gridCellColumns(Int.max): laying out; a trap ends the process here
//

import AppKit
import SwiftUI

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    if v.isNaN { return "nan" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ p: ProposedViewSize) -> String { "\(d(p.width))x\(d(p.height))" }
func fmt(_ r: CGRect) -> String { "(\(d(r.minX)),\(d(r.minY)) \(d(r.width))x\(d(r.height)))" }

// ---------- leaves ----------
enum LK: Sendable {
    case fixed(CGFloat, CGFloat), flex, clampBoth(CGFloat, CGFloat), flexW(CGFloat), flexH(CGFloat), half, clampW(CGFloat, CGFloat, CGFloat), spacer
    /// Revision 5: a text-like leaf, `natural` wide on one line of `line`
    /// height; at a narrower width it wraps into ceil(natural / width) lines
    /// (a width below 1 counts as 1). Never produced by the generator.
    case wrap(CGFloat, CGFloat)
    func answer(_ p: ProposedViewSize) -> CGSize {
        switch self {
        case let .wrap(natural, line):
            let w = min(max(p.width ?? natural, 0), natural)
            return CGSize(width: w, height: line * (natural / max(w, 1)).rounded(.up))
        case let .fixed(w, h): return CGSize(width: w, height: h)
        case .flex: return CGSize(width: p.width ?? 10, height: p.height ?? 10)
        case let .clampBoth(lo, hi): return CGSize(width: min(max(p.width ?? 10, lo), hi), height: min(max(p.height ?? 10, lo), hi))
        case let .flexW(h): return CGSize(width: p.width ?? 10, height: h)
        case let .flexH(w): return CGSize(width: w, height: p.height ?? 10)
        case .half: return CGSize(width: (p.width ?? 40) / 2, height: 10)
        case let .clampW(lo, hi, h): return CGSize(width: min(max(p.width ?? 10, lo), hi), height: h)
        case .spacer: return .zero // never used: a real Spacer stands in
        }
    }
    var text: String {
        switch self {
        case let .fixed(w, h): return "fixed(\(d(w)), \(d(h)))"
        case .flex: return "flex"
        case let .clampBoth(lo, hi): return "clampBoth(\(d(lo)), \(d(hi)))"
        case let .flexW(h): return "flexW(\(d(h)))"
        case let .flexH(w): return "flexH(\(d(w)))"
        case .half: return "half"
        case let .clampW(lo, hi, h): return "clampW(\(d(lo)), \(d(hi)), \(d(h)))"
        case .spacer: return "spacer"
        case let .wrap(n, l): return "wrap(\(d(n)), \(d(l)))"
        }
    }
}

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var lastSize: CGSize = .zero

struct RLeaf: Layout {
    let name: String
    let kind: LK
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize { kind.answer(proposal) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

enum A9: Int, CaseIterable, Sendable { case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing
    var x: CGFloat { [0, 0.5, 1, 0, 0.5, 1, 0, 0.5, 1][rawValue] }
    var y: CGFloat { [0, 0, 0, 0.5, 0.5, 0.5, 1, 1, 1][rawValue] }
    var swiftUI: Alignment { [.topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom, .bottomTrailing][rawValue] }
    var unit: UnitPoint { [.topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom, .bottomTrailing][rawValue] }
    var text: String { "\(self)" }
}
enum H3: Int, Sendable { case leading, center, trailing
    var x: CGFloat { [0, 0.5, 1][rawValue] }
    var swiftUI: HorizontalAlignment { [.leading, .center, .trailing][rawValue] }
}
enum V3: Int, Sendable { case top, center, bottom
    var y: CGFloat { [0, 0.5, 1][rawValue] }
    var swiftUI: VerticalAlignment { [.top, .center, .bottom][rawValue] }
}

struct CellSpec: Sendable {
    var name: String; var kind: LK; var span: Int = 1; var prio: Double = 0
    var anchor: A9? = nil; var colAlign: H3? = nil; var unsizedH = false; var unsizedV = false
}
enum ChildSpec: Sendable { case row(V3?, [CellSpec]), full(CellSpec) }
struct Case: Sendable {
    var children: [ChildSpec]; var proposal: ProposedViewSize
    var alignment: A9 = .center; var hs: CGFloat? = nil; var vs: CGFloat? = nil
}
/// Revision 5: each attribute is applied only when it was written (a priority
/// other than 0, a span other than 1, a non-empty axis set). Revisions 1-4
/// applied `.layoutPriority(c.prio)` to every cell, and a `.layoutPriority(0)`
/// on a Spacer replaces its -inf priority with 0 (GS1 bare: 190x80; with
/// `.layoutPriority(0)`: 200x100), so their Spacer cells were not bare.
struct WrittenAttributes: ViewModifier {
    let c: CellSpec
    @ViewBuilder func body(content: Content) -> some View {
        let axes: Axis.Set = c.unsizedH ? (c.unsizedV ? [.horizontal, .vertical] : .horizontal) : (c.unsizedV ? .vertical : [])
        switch (c.prio != 0, c.span != 1, !axes.isEmpty) {
        case (false, false, false): content
        case (true, false, false): content.layoutPriority(c.prio)
        case (false, true, false): content.gridCellColumns(c.span)
        case (false, false, true): content.gridCellUnsizedAxes(axes)
        case (true, true, false): content.layoutPriority(c.prio).gridCellColumns(c.span)
        case (true, false, true): content.layoutPriority(c.prio).gridCellUnsizedAxes(axes)
        case (false, true, true): content.gridCellColumns(c.span).gridCellUnsizedAxes(axes)
        case (true, true, true): content.layoutPriority(c.prio).gridCellColumns(c.span).gridCellUnsizedAxes(axes)
        }
    }
}
struct CellMods: ViewModifier {
    let c: CellSpec
    @ViewBuilder func body(content: Content) -> some View {
        let base = content.modifier(WrittenAttributes(c: c))
        if let a = c.anchor, let h = c.colAlign {
            base.gridCellAnchor(a.unit).gridColumnAlignment(h.swiftUI)
        } else if let a = c.anchor {
            base.gridCellAnchor(a.unit)
        } else if let h = c.colAlign {
            base.gridColumnAlignment(h.swiftUI)
        } else {
            base
        }
    }
}

@MainActor @ViewBuilder func leafView(_ c: CellSpec) -> some View {
    if case .spacer = c.kind {
        Spacer().background(RLeaf(name: c.name, kind: .flex) { SwiftUI.Color.clear }).modifier(CellMods(c: c))
    } else {
        RLeaf(name: c.name, kind: c.kind) { SwiftUI.Color.clear }.modifier(CellMods(c: c))
    }
}

@MainActor @ViewBuilder func realGrid(_ k: Case) -> some View {
    Grid(alignment: k.alignment.swiftUI, horizontalSpacing: k.hs, verticalSpacing: k.vs) {
        ForEach(Array(k.children.enumerated()), id: \.offset) { _, child in
            if case let .row(al, cells) = child {
                GridRow(alignment: al?.swiftUI) { ForEach(Array(cells.enumerated()), id: \.offset) { _, c in leafView(c) } }
            }
            if case let .full(c) = child { leafView(c) }
        }
    }
}

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal); lastSize = size; return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}
struct MeasureOnly: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lastSize = subviews[0].sizeThatFits(proposal); return .zero
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: .zero)
    }
}

@MainActor func host<V: View>(_ proposal: ProposedViewSize, measureOnly: Bool = false, @ViewBuilder _ view: () -> V) -> (CGSize, [String: CGRect]) {
    placed = [:]; lastSize = CGSize(width: -1, height: -1)
    let host: NSView = measureOnly ? NSHostingView(rootView: MeasureOnly(proposal: proposal) { view() })
                                   : NSHostingView(rootView: Probe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    return (lastSize, placed)
}
// ---------------- the reference model ----------------

/// Positive control for the fuzz (GZ0): when true, every group is offered the
/// initial equal share, ignoring commits.
nonisolated(unsafe) var controlIgnoresCommits = false
/// Revision 5, `classify-spans` only: a model variant, 0 = the reference model.
/// 1 spreads a span's shortfall over all its columns; 2 proposes a span the
/// sum over its columns of the share (open) or current width, plus inner gaps;
/// 3 absorbs a span's shortfall as soon as it is measured, not after its group;
/// 4 keeps a span's columns open while it is unprocessed; 5 drops step 12 (the
/// shortfall's preference for still-open columns); 6 counts a column holding no
/// single-column cell as open for every share and never commits it (GS5).
nonisolated(unsafe) var modelVariant = 0

struct MCell { var row: Int; var col: Int; var span: Int; var prio: Double; var index: Int; var spec: CellSpec; var isFull: Bool }
struct Structure { var cells: [MCell]; var ncols: Int; var nrows: Int; var rowAlign: [V3?] }

func structure(_ k: Case, prios: [Double]) -> Structure {
    var ncols = 0
    for c in k.children { if case let .row(_, cells) = c { ncols = max(ncols, cells.reduce(0) { $0 + max($1.span, 1) }) } }
    if ncols == 0 { ncols = 1 }
    var out: [MCell] = []; var r = 0; var idx = 0; var rowAlign: [V3?] = []
    for c in k.children {
        switch c {
        case let .row(al, cells):
            if cells.isEmpty { continue }
            var col = 0
            for cell in cells {
                let span = max(min(max(cell.span, 1), ncols - col), 1)
                out.append(MCell(row: r, col: col, span: span, prio: prios[idx], index: idx, spec: cell, isFull: false)); idx += 1; col += span
            }
            rowAlign.append(al); r += 1
        case let .full(cell):
            out.append(MCell(row: r, col: 0, span: ncols, prio: prios[idx], index: idx, spec: cell, isFull: true)); idx += 1
            rowAlign.append(nil); r += 1
        }
    }
    return Structure(cells: out, ncols: ncols, nrows: r, rowAlign: rowAlign)
}

struct Solved { var colW: [CGFloat]; var gap: [CGFloat]; var rowH: [CGFloat]; var vgap: [CGFloat]; var prop: [ProposedViewSize]; var size: [CGSize] }

func solve(_ st: Structure, _ P: ProposedViewSize, hs: CGFloat?, vs: CGFloat?, measure: (Int, ProposedViewSize) -> CGSize) -> Solved {
    let cells = st.cells, ncols = st.ncols, nrows = st.nrows
    var curW = Array(repeating: CGFloat(0), count: ncols)
    var curH = Array(repeating: CGFloat(0), count: nrows)
    var prop = Array(repeating: ProposedViewSize(width: nil, height: nil), count: cells.count)
    var size = Array(repeating: CGSize.zero, count: cells.count)
    // Spacing (rule GS): the gap before column j is the largest spacing of any
    // adjacent pair of cells in one row meeting at j; the gap before row r the
    // largest of any pair of cells covering one column in rows r-1 and r. A
    // pair's spacing is the explicit spacing, or 8 unless either is a Spacer.
    func isSpacer(_ c: MCell) -> Bool { if case .spacer = c.spec.kind { return true }; return false }
    func pair(_ a: MCell, _ b: MCell, _ explicit: CGFloat?) -> CGFloat { explicit ?? (isSpacer(a) || isSpacer(b) ? 0 : 8) }
    var gapOpt = Array(repeating: CGFloat?.none, count: ncols)
    for c in cells where c.col > 0 {
        if let left = cells.first(where: { $0.row == c.row && $0.col + $0.span == c.col }) {
            let v = pair(left, c, hs); gapOpt[c.col] = max(gapOpt[c.col] ?? v, v)
        }
    }
    let gap = gapOpt.map { $0 ?? 0 }
    var vgapOpt = Array(repeating: CGFloat?.none, count: nrows)
    for r in 1..<max(nrows, 1) where r < nrows {
        for q in 0..<ncols {
            if let above = cells.first(where: { $0.row == r - 1 && $0.col <= q && q < $0.col + $0.span }),
               let below = cells.first(where: { $0.row == r && $0.col <= q && q < $0.col + $0.span }) {
                let v = pair(above, below, vs); vgapOpt[r] = max(vgapOpt[r] ?? v, v)
            }
        }
    }
    let vgap = vgapOpt.map { $0 ?? 0 }
    let singleCols = Set(cells.filter { $0.span == 1 }.map { $0.col })
    func inner(_ c: MCell) -> CGFloat { (c.col + 1 ..< c.col + c.span).reduce(0) { $0 + gap[$1] } }
    func spanW(_ c: MCell) -> CGFloat { (c.col..<c.col + c.span).reduce(0) { $0 + curW[$1] } + inner(c) }
    func absorbSingle(_ c: MCell, _ s: CGSize) {
        curH[c.row] = max(curH[c.row], s.height)
        if c.span == 1 { curW[c.col] = max(curW[c.col], s.width) }
    }
    var done = Set<Int>()
    func absorbSpan(_ c: MCell, _ s: CGSize) {
        let have = spanW(c)
        if s.width > have {
            var targets = (c.col..<c.col + c.span).filter { !singleCols.contains($0) }
            // Revision 5 (record §20 step 12): at a non-nil proposal the shortfall
            // goes first to the spanned columns that still hold an unprocessed
            // single-column cell (GX9: b's column, not a's committed one).
            if modelVariant != 5, P.width != nil || P.height != nil {
                let open = (c.col..<c.col + c.span).filter { q in cells.contains { $0.span == 1 && $0.col == q && !done.contains($0.index) } }
                if !open.isEmpty { targets = open }
            }
            if targets.isEmpty || modelVariant == 1 { targets = Array(c.col..<c.col + c.span) }
            let e = (s.width - have) / CGFloat(targets.count)
            for j in targets { curW[j] += e }
        }
    }
    if P.width == nil && P.height == nil {
        for c in cells { prop[c.index] = P; size[c.index] = measure(c.index, P) }
        for c in cells { absorbSingle(c, size[c.index]) }
        for c in cells where c.span > 1 { absorbSpan(c, size[c.index]) }
    } else {
        let zero = ProposedViewSize(width: 0, height: 0), inf = ProposedViewSize(width: .infinity, height: .infinity)
        var infs = Array(repeating: 0, count: cells.count), fins = Array(repeating: CGFloat(0), count: cells.count)
        for c in cells {
            let a = measure(c.index, zero), b = measure(c.index, inf)
            if P.width != nil { if b.width.isInfinite { infs[c.index] += 1 } else { fins[c.index] += b.width - a.width } }
            if P.height != nil { if b.height.isInfinite { infs[c.index] += 1 } else { fins[c.index] += b.height - a.height } }
        }
        func key(_ c: MCell) -> (Double, Int, CGFloat) { (-c.prio, infs[c.index], fins[c.index]) }
        let order = cells.sorted { x, y in
            let kx = key(x), ky = key(y)
            if kx.0 != ky.0 { return kx.0 < ky.0 }
            if kx.1 != ky.1 { return kx.1 < ky.1 }
            if kx.2 != ky.2 { return kx.2 < ky.2 }
            return x.index < y.index
        }
        var committedC = Set<Int>(), committedR = Set<Int>()
        let Wp = P.width.map { $0 - gap.reduce(0, +) }
        let Hp = P.height.map { $0 - vgap.reduce(0, +) }
        var i = 0
        while i < order.count {
            var j = i
            while j < order.count && key(order[j]) == key(order[i]) { j += 1 }
            let group = Array(order[i..<j])
            let level = order[i].prio
            let openCols = Set((0..<ncols).filter { col in cells.contains { ($0.span == 1 ? $0.col == col : (modelVariant == 4 && $0.col <= col && col < $0.col + $0.span)) && $0.prio == level && !done.contains($0.index) } || (modelVariant == 6 && !singleCols.contains(col)) })
            let openR = (0..<nrows).filter { r in cells.contains { $0.row == r && $0.prio == level && !done.contains($0.index) } }.count
            // An infinite proposal axis shares infinity, whatever is committed (GP9-GP11).
            let shareW = controlIgnoresCommits ? Wp.map { $0 / CGFloat(ncols) } : Wp.map { w in w.isInfinite ? w : (w - committedC.reduce(0) { $0 + curW[$1] }) / CGFloat(max(openCols.count, 1)) }
            let shareH = Hp.map { h in h.isInfinite ? h : (h - committedR.reduce(0) { $0 + curH[$1] }) / CGFloat(max(openR, 1)) }
            var spans: [MCell] = []
            for c in group {
                var w: CGFloat? = nil
                if let Wp, let shareW {
                    if c.spec.unsizedH { w = spanW(c) }
                    else if c.span == 1 { w = max(shareW, curW[c.col]) }
                    else {
                        var outside: CGFloat = 0
                        for q in 0..<ncols where !(c.col <= q && q < c.col + c.span) { outside += openCols.contains(q) ? shareW : curW[q] }
                        w = Wp.isInfinite ? Wp : max(Wp - outside + inner(c), spanW(c))
                        if modelVariant == 2 && !Wp.isInfinite { w = max((c.col..<c.col + c.span).reduce(0) { $0 + (openCols.contains($1) ? shareW : curW[$1]) } + inner(c), spanW(c)) }
                    }
                }
                var h: CGFloat? = nil
                if let shareH { h = c.spec.unsizedV ? curH[c.row] : max(shareH, curH[c.row]) }
                let p = ProposedViewSize(width: w, height: h)
                prop[c.index] = p; size[c.index] = measure(c.index, p)
                absorbSingle(c, size[c.index])
                if c.span > 1 { if modelVariant == 3 { absorbSpan(c, size[c.index]) } else { spans.append(c) } }
                done.insert(c.index)
            }
            for c in spans { absorbSpan(c, size[c.index]) }
            for col in 0..<ncols where !committedC.contains(col) && !(modelVariant == 6 && !singleCols.contains(col)) {
                if cells.allSatisfy({ ($0.span > 1 ? !(modelVariant == 4 && $0.col <= col && col < $0.col + $0.span) : $0.col != col) || done.contains($0.index) || $0.prio < level }) { committedC.insert(col) }
            }
            for r in 0..<nrows where !committedR.contains(r) {
                if cells.allSatisfy({ $0.row != r || done.contains($0.index) || $0.prio < level }) { committedR.insert(r) }
            }
            i = j
        }
    }
    return Solved(colW: curW, gap: gap, rowH: curH, vgap: vgap, prop: prop, size: size)
}

struct ModelGrid: Layout {
    let k: Case
    var hs: CGFloat? { k.hs }
    var vs: CGFloat? { k.vs }
    func st(_ subviews: Subviews) -> Structure { structure(k, prios: subviews.map { Double($0.priority) }) }
    func total(_ s: Solved) -> CGSize {
        CGSize(width: s.colW.reduce(0, +) + s.gap.reduce(0, +), height: s.rowH.reduce(0, +) + s.vgap.reduce(0, +))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        total(solve(st(subviews), proposal, hs: hs, vs: vs) { subviews[$0].sizeThatFits($1) })
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let structure = st(subviews)
        let s = solve(structure, proposal, hs: hs, vs: vs) { subviews[$0].sizeThatFits($1) }
        var xs: [CGFloat] = []; var x = bounds.minX
        for (j, w) in s.colW.enumerated() { x += s.gap[j]; xs.append(x); x += w }
        var ys: [CGFloat] = []; var y = bounds.minY
        for (r, h) in s.rowH.enumerated() { y += s.vgap[r]; ys.append(y); y += h }
        var colAlign = Array(repeating: H3?.none, count: structure.ncols)
        for c in structure.cells where !c.isFull { if colAlign[c.col] == nil, let a = c.spec.colAlign { colAlign[c.col] = a } }
        for c in structure.cells {
            let cw = (c.col..<c.col + c.span).reduce(0) { $0 + s.colW[$1] } + (c.col + 1 ..< c.col + c.span).reduce(0) { $0 + s.gap[$1] }
            let ch = s.rowH[c.row]
            var p = ProposedViewSize(width: cw, height: ch)
            if s.size[c.index] == CGSize(width: cw, height: ch) { p = s.prop[c.index] }
            let a = subviews[c.index].sizeThatFits(p)
            let fx = c.spec.anchor?.x ?? (c.span == 1 ? colAlign[c.col]?.x : nil) ?? k.alignment.x
            let fy = c.spec.anchor?.y ?? structure.rowAlign[c.row]?.y ?? k.alignment.y
            subviews[c.index].place(at: CGPoint(x: xs[c.col] + (cw - a.width) * fx, y: ys[c.row] + (ch - a.height) * fy), anchor: .topLeading, proposal: p)
        }
    }
}

@MainActor @ViewBuilder func modelGrid(_ k: Case) -> some View {
    ModelGrid(k: k) {
        ForEach(Array(k.children.enumerated()), id: \.offset) { _, child in
            if case let .row(_, cells) = child { ForEach(Array(cells.enumerated()), id: \.offset) { _, c in leafView(c) } }
            if case let .full(c) = child { leafView(c) }
        }
    }
}
struct LCG { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }
struct Features: OptionSet { let rawValue: Int
    static let spans = Features(rawValue: 1), prios = Features(rawValue: 2), fulls = Features(rawValue: 4), attrs = Features(rawValue: 8), spacers = Features(rawValue: 16), spacing = Features(rawValue: 32), inf = Features(rawValue: 64)
    /// Revision 5: proposals with a zero axis (what an enclosing stack's minimum probe sends).
    static let zero = Features(rawValue: 128)
}
func randomKind(_ g: inout LCG, spacers: Bool) -> LK {
    let sizes: [CGFloat] = [10, 20, 30, 40, 60, 100, 150]
    if spacers && g.next(8) == 0 { return .spacer }
    switch g.next(10) {
    case 0, 1, 2: return .fixed(sizes[g.next(7)], sizes[g.next(5)])
    case 3: return .flex
    case 4: let lo = [0, 10, 20][g.next(3)]; return .clampBoth(CGFloat(lo), CGFloat(lo) + sizes[g.next(7)])
    case 5: return .flexW(sizes[g.next(4)])
    case 6: return .flexH(sizes[g.next(4)])
    case 7: return .half
    default: let lo = [0, 10, 30][g.next(3)]; return .clampW(CGFloat(lo), CGFloat(lo) + sizes[g.next(7)], sizes[g.next(4)])
    }
}
func randomCell(_ g: inout LCG, _ n: Int, _ f: Features) -> CellSpec {
    var c = CellSpec(name: "c\(n)", kind: randomKind(&g, spacers: f.contains(.spacers)))
    if f.contains(.spans) && g.next(5) == 0 { c.span = 2 + g.next(2) }
    if f.contains(.prios) && g.next(6) == 0 { c.prio = [1, -1][g.next(2)] }
    if f.contains(.attrs) {
        if g.next(4) == 0 { c.anchor = A9(rawValue: g.next(9)) }
        if g.next(4) == 0 { c.colAlign = H3(rawValue: g.next(3)) }
        if g.next(6) == 0 { c.unsizedH = true }
        if g.next(6) == 0 { c.unsizedV = true }
    }
    return c
}
func randomCase(_ g: inout LCG, _ f: Features) -> Case {
    var n = 0
    var children: [ChildSpec] = []
    for _ in 0..<(1 + g.next(3)) {
        if f.contains(.fulls) && g.next(6) == 0 {
            n += 1; children.append(.full(randomCell(&g, n, f)))
        } else {
            var cells: [CellSpec] = []
            for _ in 0..<(1 + g.next(3)) { n += 1; cells.append(randomCell(&g, n, f)) }
            let al: V3? = f.contains(.attrs) && g.next(3) == 0 ? V3(rawValue: g.next(3)) : nil
            children.append(.row(al, cells))
        }
    }
    var props: [ProposedViewSize] = [.init(width: nil, height: nil), .init(width: 200, height: 100), .init(width: 100, height: 100), .init(width: 60, height: 60), .init(width: 300, height: 200), .init(width: 150, height: nil), .init(width: nil, height: 80)]
    if f.contains(.inf) { props = [.init(width: .infinity, height: .infinity), .init(width: .infinity, height: 100), .init(width: 150, height: .infinity), .init(width: nil, height: .infinity)] }
    if f.contains(.zero) { props = [.init(width: 0, height: 0), .init(width: 0, height: nil), .init(width: nil, height: 0), .init(width: 0, height: 100), .init(width: 200, height: 0)] }
    var k = Case(children: children, proposal: props[g.next(props.count)])
    if f.contains(.attrs) { k.alignment = A9(rawValue: g.next(9))! }
    if f.contains(.spacing) { if g.next(2) == 0 { k.hs = [0, 3, 12][g.next(3)] }; if g.next(2) == 0 { k.vs = [0, 5, 12][g.next(3)] } }
    return k
}
func caseText(_ k: Case) -> String {
    func cell(_ c: CellSpec) -> String {
        var s = "\(c.name):\(c.kind.text)"
        if c.span != 1 { s += " span\(c.span)" }
        if c.prio != 0 { s += " prio\(d(c.prio))" }
        if let a = c.anchor { s += " anchor.\(a.text)" }
        if let h = c.colAlign { s += " col.\(h)" }
        if c.unsizedH { s += " unsizedH" }
        if c.unsizedV { s += " unsizedV" }
        return s
    }
    var t = "Grid(\(k.alignment.text), h \(d(k.hs)), v \(d(k.vs))) "
    t += k.children.map { ch -> String in
        switch ch {
        case let .row(al, cells): return "[" + (al.map { "row.\($0) " } ?? "") + cells.map(cell).joined(separator: ", ") + "]"
        case let .full(c): return "FULL " + cell(c)
        }
    }.joined(separator: " ")
    return t + " @" + fmt(k.proposal)
}
func close(_ a: CGFloat, _ b: CGFloat) -> Bool { a == b || abs(a - b) < 0.01 || (a.isInfinite && b.isInfinite && a.sign == b.sign) }
func closeR(_ a: CGRect?, _ b: CGRect?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return close(a.minX, b.minX) && close(a.minY, b.minY) && close(a.width, b.width) && close(a.height, b.height)
}
func rects(_ m: [String: CGRect]) -> String {
    m.sorted { Int($0.key.dropFirst())! < Int($1.key.dropFirst())! }.map { "\($0.key)\(fmt($0.value))" }.joined(separator: " ")
}
@MainActor func fuzz(_ label: String, seed: UInt64, count: Int, _ f: Features, show: Int) -> Int {
    var g = LCG(s: seed); var bad = 0
    let mo = f.contains(.inf)
    for _ in 0..<count {
        let k = randomCase(&g, f)
        let (rs, rp) = host(k.proposal, measureOnly: mo) { realGrid(k) }
        let (ms, mp) = host(k.proposal, measureOnly: mo) { modelGrid(k) }
        var ok = close(rs.width, ms.width) && close(rs.height, ms.height)
        if !mo { for (name, r) in rp where !closeR(r, mp[name]) { ok = false }; if rp.count != mp.count { ok = false } }
        if !ok {
            bad += 1
            if bad <= show {
                print("  DIFFERS \(caseText(k))")
                print("    SwiftUI \(fmt(rs)) \(mo ? "" : rects(rp))")
                print("    model   \(fmt(ms)) \(mo ? "" : rects(mp))")
            }
        }
    }
    print("FUZZ \(label) seed \(seed): \(count - bad) of \(count) agree")
    fflush(stdout)
    return bad
}
// ---------------- arm harness ----------------
nonisolated(unsafe) var placedProposal: [String: ProposedViewSize] = [:]
nonisolated(unsafe) var seqLog: [String] = []
nonisolated(unsafe) var order: [String] = []

/// A leaf standing for one cell: answers `f(proposal)`, logs every measurement
/// in order (SwiftUI's own cache hides repeats), and records its last placed
/// rect and the proposal it was placed with.
struct L: Layout {
    let name: String
    let f: @Sendable (ProposedViewSize) -> CGSize
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if !order.contains(name) { order.append(name) }
        let s = f(proposal); seqLog.append("\(name) \(fmt(proposal))->\(fmt(s))"); return s
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !order.contains(name) { order.append(name) }
        placed[name] = bounds; placedProposal[name] = proposal
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
func leaf(_ n: String, _ f: @escaping @Sendable (ProposedViewSize) -> CGSize) -> some View { L(name: n, f: f) { SwiftUI.Color.clear } }
/// fixed w x h
func fx(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View { leaf(n) { _ in CGSize(width: w, height: h) } }
/// proposal ?? 10 on both axes
func fl(_ n: String) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: p.height ?? 10) } }
/// half the proposed width (40 at nil), height 10
func hf(_ n: String) -> some View { leaf(n) { p in CGSize(width: (p.width ?? 40) / 2, height: 10) } }
/// width proposal ?? 10, fixed height h
func fw(_ n: String, _ h: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: p.width ?? 10, height: h) } }
/// fixed width w, height proposal ?? 10
func fh(_ n: String, _ w: CGFloat = 20) -> some View { leaf(n) { p in CGSize(width: w, height: p.height ?? 10) } }
/// clamp(proposal ?? 10, lo, hi) on both axes
func cb(_ n: String, _ lo: CGFloat, _ hi: CGFloat) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: min(max(p.height ?? 10, lo), hi)) } }
/// width clamp(proposal ?? 10, lo, hi), fixed height h
func cw(_ n: String, _ lo: CGFloat, _ hi: CGFloat, _ h: CGFloat = 10) -> some View { leaf(n) { p in CGSize(width: min(max(p.width ?? 10, lo), hi), height: h) } }
/// height clamp(proposal ?? 10, lo, hi), fixed width w
func ch(_ n: String, _ lo: CGFloat, _ hi: CGFloat, _ w: CGFloat = 10) -> some View { leaf(n) { p in CGSize(width: w, height: min(max(p.height ?? 10, lo), hi)) } }
/// answers 20x20, except exactly 15x15 when proposed exactly 20x20
func odd(_ n: String) -> some View { leaf(n) { p in (p.width == 20 && p.height == 20) ? CGSize(width: 15, height: 15) : CGSize(width: 20, height: 20) } }

let none = ProposedViewSize(width: nil, height: nil)
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

@MainActor func arm<V: View>(_ label: String, _ proposal: ProposedViewSize, seq: Bool = false, measureOnly: Bool = false, @ViewBuilder _ view: () -> V) {
    seqLog = []; order = []; placedProposal = [:]
    let (size, rects) = host(proposal, measureOnly: measureOnly, view)
    var line = "\(label) @\(fmt(proposal))\(measureOnly ? " (measured only)" : ""): size \(fmt(size))"
    if !measureOnly {
        for n in order { line += " | \(n) " + (rects[n].map { fmt($0) } ?? "not placed") + (placedProposal[n].map { " <- \(fmt($0))" } ?? "") }
    }
    print(line)
    if seq || measureOnly { print("    measured, in order: " + seqLog.joined(separator: "; ")) }
    fflush(stdout)
}
@MainActor func armsA() {
    print("=== GA: column widths, row heights, default and explicit spacing, empty content (nil proposal)")
    arm("GA0 control: VStack{HStack{a 30x10; b 20x20}; HStack{c 10x30; d 40x10}}", none) { VStack { HStack { fx("a",30,10); fx("b",20,20) }; HStack { fx("c",10,30); fx("d",40,10) } } }
    arm("GA1 Grid{[a 30x10, b 20x20] [c 10x30, d 40x10]}", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GA2 GA1 at spacing 0/0", none) { Grid(horizontalSpacing: 0, verticalSpacing: 0) { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GA3 GA1 at spacing 3/5", none) { Grid(horizontalSpacing: 3, verticalSpacing: 5) { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GA4 unequal rows [a 30x10, b 20x20, e 5x5] [c 10x30]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5) }; GridRow { fx("c",10,30) } } }
    arm("GA5 empty Grid{}, read through a background leaf g", none) { Grid { }.background(fl("g")) }
    arm("GA6 Grid{GridRow{}}, read through a background leaf g", none) { Grid { GridRow { } }.background(fl("g")) }
    arm("GA7 an empty GridRow between two rows", none) { Grid { GridRow { fx("a",30,10) }; GridRow { }; GridRow { fx("c",10,30) } } }
    arm("GA8 only non-row children {x 30x10; y 10x20}", none) { Grid { fx("x",30,10); fx("y",10,20) } }
    arm("GA9 only non-row children {x 30x10; y flexible} at 200x100", p(200,100)) { Grid { fx("x",30,10); fl("y") } }
}

@MainActor func armsP() {
    print("=== GP: the grid's answer at nil, finite, one-axis and infinite proposals")
    arm("GP1 GA1 at 200x200 (fixed content answers its nil size)", p(200,200), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP2 [a flexible, b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP3 GP2 at nil", none, seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP4 GP2 at inf x inf", p(.infinity,.infinity), measureOnly: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP5 GP2 at 200 x nil", p(200,nil), seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP6 GP2 at nil x 100", p(nil,100), seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GP7 a single flexible cell at 100x100", p(100,100)) { Grid { GridRow { fl("a") } } }
    arm("GP8 GA1 at inf x inf (fixed content)", p(.infinity,.infinity), measureOnly: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
}

@MainActor func armsF() {
    print("=== GF: flexibility order, shares and commits at finite proposals")
    arm("GF1 [a half, b 20x20] [c 10x30, d half] at 200x200", p(200,200), seq: true) { Grid { GridRow { hf("a"); fx("b",20,20) }; GridRow { fx("c",10,30); hf("d") } } }
    arm("GF2 [a width-flexible h20, b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { fw("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF3 [a height-flexible w20, b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { fh("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF4 [a clamp 0...150, b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { cb("a",0,150); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF5 [a clamp 0...50, b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { cb("a",0,50); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF6 [a flexible, b 20x20] [c 10x30, d flexible] at 200x100", p(200,100), seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fl("d") } } }
    arm("GF7 overflow [a flexible, b 120x20] [c 10x30, d 40x10] at 100x100", p(100,100), seq: true) { Grid { GridRow { fl("a"); fx("b",120,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF8 [a 20x20, b flexible, c flexible] at 200x100", p(200,100), seq: true) { Grid { GridRow { fx("a",20,20); fl("b"); fl("c") } } }
    arm("GF9 [a width 0...30, b width 0...55] at 100x100", p(100,100), seq: true) { Grid { GridRow { cw("a",0,30); cw("b",0,55) } } }
    arm("GF10 [a half, b flexible] at 200x100 (one infinite axis before two)", p(200,100), seq: true) { Grid { GridRow { hf("a"); fl("b") } } }
    arm("GF11 [a width 10...20, b height-flexible w20, c width 10...160 h30] at 200x100 (finite 150 before one infinite axis)", p(200,100), seq: true) { Grid { GridRow { cw("a",10,20,10); fh("b"); cw("c",10,160,30) } } }
    arm("GF12 [a clamp 10...50, b height-flexible w30, c flexible] at 150 x nil (a nil axis adds no flexibility)", p(150,nil), seq: true) { Grid { GridRow { cb("a",10,50); fh("b",30); fl("c") } } }
    arm("GF13 control for GF12: the same at 150x100", p(150,100), seq: true) { Grid { GridRow { cb("a",10,50); fh("b",30); fl("c") } } }
}

@MainActor func armsR() {
    print("=== GR: the placement proposal is the measured one when the cell equals that answer")
    arm("GR0 control: odd leaf in .frame(width: 20, height: 20)", none) { odd("a").frame(width: 20, height: 20) }
    arm("GR1 [a odd, b 20x20] at nil", none, seq: true) { Grid { GridRow { odd("a"); fx("b",20,20) } } }
    arm("GR2 [a odd, b 20x20] at 200x200", p(200,200), seq: true) { Grid { GridRow { odd("a"); fx("b",20,20) } } }
}

@MainActor func armsS() {
    print("=== GS: spacing")
    arm("GS1 [Spacer (bg leaf s), b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GS2 [a 30x10, Spacer (bg s), c height-flexible w10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); Spacer().background(fl("s")); fh("c",10) } } }
    arm("GS3 control for GS2: Spacer replaced by an 8x8 leaf", p(nil,80)) { Grid { GridRow { fx("a",30,10); fx("s",8,8); fh("c",10) } } }
    arm("GS4 [a half] [Spacer (bg s), c width 30...180 h20] at 60x60 (no vertical gap above a spacer)", p(60,60)) { Grid { GridRow { hf("a") }; GridRow { Spacer().background(fl("s")); cw("c",30,180,20) } } }
    arm("GS5 [a 40x40] [b half, c 20x40 span 2] [d width 0...30 h40] at 300x200 (no gap before a column no cell starts)", p(300,200), seq: true) { Grid { GridRow { fx("a",40,40) }; GridRow { hf("b"); fx("c",20,40).gridCellColumns(2) }; GridRow { cw("d",0,30,40) } } }
    arm("GS6 GS5 at nil", none) { Grid { GridRow { fx("a",40,40) }; GridRow { hf("b"); fx("c",20,40).gridCellColumns(2) }; GridRow { cw("d",0,30,40) } } }
    arm("GS7 Texts [Hi, Yo] [A, B] (bg leaves)", none) { Grid { GridRow { Text("Hi").background(fl("t1")); Text("Yo").background(fl("t2")) }; GridRow { Text("A").background(fl("t3")); Text("B").background(fl("t4")) } } }
    arm("GS8 GA1 at spacing -10/-5", none) { Grid(horizontalSpacing: -10, verticalSpacing: -5) { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GS9 [a, b] at horizontal spacing +inf", none, measureOnly: true) { Grid(horizontalSpacing: .infinity) { GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GS10 [a, b] at horizontal spacing nan", none, measureOnly: true) { Grid(horizontalSpacing: .nan) { GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GS11 explicit spacing 12 beside a Spacer: [a 30x10, Spacer, c 10x10] at nil x 80", p(nil,80)) { Grid(horizontalSpacing: 12) { GridRow { fx("a",30,10); Spacer().background(fl("s")); fx("c",10,10) } } }
}

@MainActor func armsX() {
    print("=== GX: spans and non-row children")
    arm("GX1 [a 30x10, b 20x20] [c 100x10 span 2]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2) } } }
    arm("GX2 [a 30x10, b 20x20] [c 10x10 span 2]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(2) } } }
    arm("GX3 [a 30x10, b 20x20] x 100x10 (non-row) [c 10x30, d 40x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; fx("x",100,10); GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GX4 [a 30x10, b 20x20] x half (non-row)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; hf("x") } }
    arm("GX5 [a, b, c 5x5] [x 100x10 span 2, y 1x1]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("c",5,5) }; GridRow { fx("x",100,10).gridCellColumns(2); fx("y",1,1) } } }
    arm("GX6 [a, b] [x 10x10 span 5] (clamped to the grid)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("x",10,10).gridCellColumns(5) } } }
    arm("GX7 [x 100x10 span 2] [a 30x10, b 20x20] (span declared first)", none) { Grid { GridRow { fx("x",100,10).gridCellColumns(2) }; GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GX8 GX7 at 300x100", p(300,100), seq: true) { Grid { GridRow { fx("x",100,10).gridCellColumns(2) }; GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GX9 [a 30x10, b flexible] [x 100x10 span 2] at 300x100", p(300,100), seq: true) { Grid { GridRow { fx("a",30,10); fl("b") }; GridRow { fx("x",100,10).gridCellColumns(2) } } }
    arm("GX10 [a 30x10, b 20x10] [x flexible span 2] at 300x100", p(300,100), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,10) }; GridRow { fl("x").gridCellColumns(2) } } }
    arm("GX11 excess goes to a spanned column with no single-column cell: [a 0...100, b 100x40 span 2, c width 30...40 h40 span 2] [d height-flexible w10 span 2, e height-flexible w10, f width 30...180 h10]", none) { Grid { GridRow { cb("a",0,100); fx("b",100,40).gridCellColumns(2); cw("c",30,40,40).gridCellColumns(2) }; GridRow { fh("d",10).gridCellColumns(2); fh("e",10); cw("f",30,180,10) } } }
    arm("GX12 a flexible non-row child is proposed the whole width: [a clamp 20...120, b width 0...60 h30] x width-flexible h10 at 300x200", p(300,200), seq: true) { Grid { GridRow { cb("a",20,120); cw("b",0,60,30) }; fw("x",10) } }
    arm("GX13 gridCellColumns on a non-row child is ignored: [a, b, e 5x5] x 10x10 columns(1)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5) }; fx("x",10,10).gridCellColumns(1) } }
    arm("GX14 gridCellColumns(0): [a, b] [c 10x10 columns(0), d 5x5]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(0); fx("d",5,5) } } }
    arm("GX15 stacked columns: [a,b,e 5x5,f 5x5] [c 100x10 columns(3).columns(2), d 1x1]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5); fx("f",5,5) }; GridRow { fx("c",100,10).gridCellColumns(3).gridCellColumns(2); fx("d",1,1) } } }
    arm("GX16 stacked columns: the same with columns(2).columns(1)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5); fx("f",5,5) }; GridRow { fx("c",100,10).gridCellColumns(2).gridCellColumns(1); fx("d",1,1) } } }
    arm("GX17 SwiftUI overflow: [a 30x10, b flexible, c 20x20] [x 150x10 span 3] at 200x100", p(200,100), seq: true) { Grid { GridRow { fx("a",30,10); fl("b"); fx("c",20,20) }; GridRow { fx("x",150,10).gridCellColumns(3) } } }
    arm("GX18 SwiftUI overflow: [a flexible, b width 10...30, c width 20...50] x 60x10 at 200x100", p(200,100), seq: true) { Grid { GridRow { fl("a"); cw("b",10,30); cw("c",20,50) }; fx("x",60,10) } }
    arm("GX19 control for GX18: x 40x10", p(200,100), seq: true) { Grid { GridRow { fl("a"); cw("b",10,30); cw("c",20,50) }; fx("x",40,10) } }
}

@MainActor func armsQ() {
    print("=== GQ: layout priority and Spacer")
    arm("GQ1 [a flexible, b flexible priority 1] at 100x100", p(100,100), seq: true) { Grid { GridRow { fl("a"); fl("b").layoutPriority(1) } } }
    arm("GQ2 [a width 0...200, b width 30...200 priority -1, c width 20...200] at 100x100", p(100,100), seq: true) { Grid { GridRow { cw("a",0,200); cw("b",30,200).layoutPriority(-1); cw("c",20,200) } } }
    arm("GQ3 [a width 0...200, b width 30...200 priority 1, c width 20...200] at 100x100", p(100,100), seq: true) { Grid { GridRow { cw("a",0,200); cw("b",30,200).layoutPriority(1); cw("c",20,200) } } }
    arm("GQ4 [a flexible, b 20x20] [c 10x30, d flexible priority 1] at 200x100", p(200,100), seq: true) { Grid { GridRow { fl("a"); fx("b",20,20) }; GridRow { fx("c",10,30); fl("d").layoutPriority(1) } } }
    arm("GQ5 [a clamp 10...70 priority 1] [b 20x10 priority 1, c 150x30, d width 30...180 h40] at 100x100", p(100,100), seq: true) { Grid { GridRow { cb("a",10,70).layoutPriority(1) }; GridRow { fx("b",20,10).layoutPriority(1); fx("c",150,30); cw("d",30,180,40) } } }
    arm("GQ6 GS1 at nil", none, seq: true) { Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GQ7 GS1 with Spacer(minLength: 0)", p(200,100)) { Grid { GridRow { Spacer(minLength: 0).background(fl("s")); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GQ8 a lone Spacer at 100x100", p(100,100)) { Grid { GridRow { Spacer().background(fl("s")) } } }
}

@MainActor func armsL() {
    print("=== GL: alignment, anchors, column alignment")
    arm("GL1 GA1 alignment .topLeading", none) { Grid(alignment: .topLeading) { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GL2 GA1 alignment .bottomTrailing", none) { Grid(alignment: .bottomTrailing) { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GL3 GA1 with GridRow(alignment: .top) on row 0", none) { Grid { GridRow(alignment: .top) { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GL4 GA1 with b.gridColumnAlignment(.trailing)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20).gridColumnAlignment(.trailing) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GL5 [a 10x10, b 20x20] [c 30x30 columnAlignment trailing, d 40x10] (declared in a later row)", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",30,30).gridColumnAlignment(.trailing); fx("d",40,10) } } }
    arm("GL6 [a 10x10 leading] [b 10x10] [c 30x10 trailing]: the first declaration wins", none) { Grid { GridRow { fx("a",10,10).gridColumnAlignment(.leading) }; GridRow { fx("b",10,10) }; GridRow { fx("c",30,10).gridColumnAlignment(.trailing) } } }
    arm("GL7 GL6 reversed: [a trailing] [b] [c leading]", none) { Grid { GridRow { fx("a",10,10).gridColumnAlignment(.trailing) }; GridRow { fx("b",10,10) }; GridRow { fx("c",30,10).gridColumnAlignment(.leading) } } }
    arm("GL8 [a 10x10, b 10x10] [c 30x10 span 2 trailing] [d 40x10]: a span declares for its first column and is not itself aligned by it", none) { Grid { GridRow { fx("a",10,10); fx("b",10,10) }; GridRow { fx("c",30,10).gridCellColumns(2).gridColumnAlignment(.trailing) }; GridRow { fx("d",40,10) } } }
    arm("GL9 Grid(.bottom) {[row .top: a 10x10, b 10x30] [c 10x10, d 10x30]}", none) { Grid(alignment: .bottom) { GridRow(alignment: .top) { fx("a",10,10); fx("b",10,30) }; GridRow { fx("c",10,10); fx("d",10,30) } } }
    arm("GL10 [a 10x10 anchor topLeading + column trailing, b 10x30] [c 40x10]: the anchor wins", none) { Grid { GridRow { fx("a",10,10).gridCellAnchor(.topLeading).gridColumnAlignment(.trailing); fx("b",10,30) }; GridRow { fx("c",40,10) } } }
    arm("GL11 [a 40x10, b 10x30] x 10x10 anchor .trailing (non-row)", none) { Grid { GridRow { fx("a",40,10); fx("b",10,30) }; fx("x",10,10).gridCellAnchor(.trailing) } }
    arm("GL12 Grid(.leading) {[a 40x10, b 10x30] x 10x10 (non-row)}", none) { Grid(alignment: .leading) { GridRow { fx("a",40,10); fx("b",10,30) }; fx("x",10,10) } }
    arm("GL13 Grid(.topLeading) {[row .bottom: a 10x10 column trailing, b 20x40, e 10x10 anchor center] [c 30x30, d 40x10, f 30x30]}", none) { Grid(alignment: .topLeading) { GridRow(alignment: .bottom) { fx("a",10,10).gridColumnAlignment(.trailing); fx("b",20,40); fx("e",10,10).gridCellAnchor(.center) }; GridRow { fx("c",30,30); fx("d",40,10); fx("f",30,30) } } }
    arm("GL14 anchor UnitPoint(x: 0.25, y: 1): [a 10x10, b 10x30] [c 50x10]", none) { Grid { GridRow { fx("a",10,10).gridCellAnchor(UnitPoint(x: 0.25, y: 1)); fx("b",10,30) }; GridRow { fx("c",50,10) } } }
    arm("GL15 [a 10x10 columnAlignment(.leading).columnAlignment(.trailing)] [e 50x10]: the inner declaration wins", none) { Grid { GridRow { fx("a",10,10).gridColumnAlignment(.leading).gridColumnAlignment(.trailing) }; GridRow { fx("e",50,10) } } }
    arm("GL16 [a 50x10, b 20x50] [c 10x10 anchor(.topLeading).anchor(.bottomTrailing), d 20x50]: the inner anchor wins", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).gridCellAnchor(.bottomTrailing); fx("d",20,50) } } }
}

@MainActor func armsU() {
    print("=== GU: gridCellUnsizedAxes")
    arm("GU1 [a 30x10, b 20x20] [c flexible unsized h, d 40x10] at 200x200", p(200,200), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
    arm("GU2 control for GU1: c not unsized", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c"); fx("d",40,10) } } }
    arm("GU3 [a, b] [c flexible unsized both, span 2] at 200x200", p(200,200), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes([.horizontal, .vertical]).gridCellColumns(2) } } }
    arm("GU4 [a, b] [c 100x30 unsized h, d 40x10] at nil (the answer still counts)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,30).gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
    arm("GU5 GU4 at 200x200 (the answer still counts)", p(200,200), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,30).gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
    arm("GU6 [a, b] [c 10x50 unsized v, d 40x10] at 200x200", p(200,200), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,50).gridCellUnsizedAxes(.vertical); fx("d",40,10) } } }
    arm("GU7 [a flexible unsized h, b flexible] [c 30x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { fl("a").gridCellUnsizedAxes(.horizontal); fl("b") }; GridRow { fx("c",30,30); fx("d",40,10) } } }
    arm("GU8 [a width 0...50 unsized h, b flexible] [c 30x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { cw("a",0,50).gridCellUnsizedAxes(.horizontal); fl("b") }; GridRow { fx("c",30,30); fx("d",40,10) } } }
    arm("GU9 divider-like: [a, b] x flexible unsized h (non-row) at 200x100", p(200,100), seq: true) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; fl("x").gridCellUnsizedAxes(.horizontal) } }
    arm("GU10 control for GU9: x not unsized", p(200,100)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; fl("x") } }
    arm("GU11 a lone flexible cell unsized on both axes at 200x100", p(200,100)) { Grid { GridRow { fl("a").gridCellUnsizedAxes([.horizontal, .vertical]) } } }
    arm("GU12 union: c unsized(.vertical).unsized(.horizontal) at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.vertical).gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
    arm("GU13 union: c unsized(.horizontal).unsized([]) at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).gridCellUnsizedAxes([]); fx("d",40,10) } } }
}
@MainActor func armsW() {
    print("=== GW: which wrappers a cell attribute passes through (each attribute written INSIDE the wrapper)")
    arm("GWS0 span 2 inside none: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2) } } }
    arm("GWS1 span 2 inside padding(1): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).padding(1) } } }
    arm("GWS2 span 2 inside frame(width:12,height:12): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).frame(width: 12, height: 12) } } }
    arm("GWS3 span 2 inside frame(maxWidth:.infinity): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).frame(maxWidth: .infinity) } } }
    arm("GWS4 span 2 inside fixedSize(): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).fixedSize() } } }
    arm("GWS5 span 2 inside background(Color): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).background(SwiftUI.Color.red) } } }
    arm("GWS6 span 2 inside overlay(Color) primary: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).overlay(SwiftUI.Color.red) } } }
    arm("GWS7 span 2 inside clipped(): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).clipped() } } }
    arm("GWS8 span 2 inside border(Color): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).border(SwiftUI.Color.red) } } }
    arm("GWS9 span 2 inside opacity(0.5): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).opacity(0.5) } } }
    arm("GWS10 span 2 inside allowsHitTesting(false): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).allowsHitTesting(false) } } }
    arm("GWS11 span 2 inside aspectRatio(1,.fit): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).aspectRatio(1, contentMode: .fit) } } }
    arm("GWS12 span 2 inside layoutPriority(1): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).layoutPriority(1) } } }
    arm("GWS13 span 2 inside onTapGesture: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).onTapGesture {} } } }
    arm("GWS14 span 2 inside disabled(true): [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",100,10).gridCellColumns(2).disabled(true) } } }
    arm("GWS15 span 2 inside HStack{one}: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { HStack { fx("c",100,10).gridCellColumns(2) } } } }
    arm("GWS16 span 2 inside ZStack{one}: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { ZStack { fx("c",100,10).gridCellColumns(2) } } } }
    arm("GWS17 span 2 inside overlay content side: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).overlay(fx("c",100,10).gridCellColumns(2)) } } }
    arm("GWS18 span 2 inside background content side: [a 30x10, b 20x20] [c 100x10]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).background(fx("c",100,10).gridCellColumns(2)) } } }
    arm("GWA0 anchor topLeading inside none: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading); fx("d",20,50) } } }
    arm("GWA1 anchor topLeading inside padding(1): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).padding(1); fx("d",20,50) } } }
    arm("GWA2 anchor topLeading inside frame(width:12,height:12): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).frame(width: 12, height: 12); fx("d",20,50) } } }
    arm("GWA3 anchor topLeading inside frame(maxWidth:.infinity): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).frame(maxWidth: .infinity); fx("d",20,50) } } }
    arm("GWA4 anchor topLeading inside fixedSize(): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).fixedSize(); fx("d",20,50) } } }
    arm("GWA5 anchor topLeading inside background(Color): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).background(SwiftUI.Color.red); fx("d",20,50) } } }
    arm("GWA6 anchor topLeading inside overlay(Color) primary: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).overlay(SwiftUI.Color.red); fx("d",20,50) } } }
    arm("GWA7 anchor topLeading inside clipped(): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).clipped(); fx("d",20,50) } } }
    arm("GWA8 anchor topLeading inside border(Color): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).border(SwiftUI.Color.red); fx("d",20,50) } } }
    arm("GWA9 anchor topLeading inside opacity(0.5): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).opacity(0.5); fx("d",20,50) } } }
    arm("GWA10 anchor topLeading inside allowsHitTesting(false): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).allowsHitTesting(false); fx("d",20,50) } } }
    arm("GWA11 anchor topLeading inside aspectRatio(1,.fit): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).aspectRatio(1, contentMode: .fit); fx("d",20,50) } } }
    arm("GWA12 anchor topLeading inside layoutPriority(1): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).layoutPriority(1); fx("d",20,50) } } }
    arm("GWA13 anchor topLeading inside onTapGesture: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).onTapGesture {}; fx("d",20,50) } } }
    arm("GWA14 anchor topLeading inside disabled(true): [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).disabled(true); fx("d",20,50) } } }
    arm("GWA15 anchor topLeading inside HStack{one}: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { HStack { fx("c",10,10).gridCellAnchor(.topLeading) }; fx("d",20,50) } } }
    arm("GWA16 anchor topLeading inside ZStack{one}: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { ZStack { fx("c",10,10).gridCellAnchor(.topLeading) }; fx("d",20,50) } } }
    arm("GWA17 anchor topLeading inside overlay content side: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).overlay(fx("c",10,10).gridCellAnchor(.topLeading)); fx("d",20,50) } } }
    arm("GWA18 anchor topLeading inside background content side: [a 50x10, b 20x50] [c 10x10, d 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).background(fx("c",10,10).gridCellAnchor(.topLeading)); fx("d",20,50) } } }
    arm("GWC0 columnAlignment trailing inside none: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC1 columnAlignment trailing inside padding(1): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).padding(1); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC2 columnAlignment trailing inside frame(width:12,height:12): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).frame(width: 12, height: 12); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC3 columnAlignment trailing inside frame(maxWidth:.infinity): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).frame(maxWidth: .infinity); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC4 columnAlignment trailing inside fixedSize(): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).fixedSize(); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC5 columnAlignment trailing inside background(Color): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).background(SwiftUI.Color.red); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC6 columnAlignment trailing inside overlay(Color) primary: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).overlay(SwiftUI.Color.red); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC7 columnAlignment trailing inside clipped(): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).clipped(); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC8 columnAlignment trailing inside border(Color): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).border(SwiftUI.Color.red); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC9 columnAlignment trailing inside opacity(0.5): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).opacity(0.5); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC10 columnAlignment trailing inside allowsHitTesting(false): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).allowsHitTesting(false); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC11 columnAlignment trailing inside aspectRatio(1,.fit): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).aspectRatio(1, contentMode: .fit); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC12 columnAlignment trailing inside layoutPriority(1): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).layoutPriority(1); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC13 columnAlignment trailing inside onTapGesture: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).onTapGesture {}; fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC14 columnAlignment trailing inside disabled(true): [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridColumnAlignment(.trailing).disabled(true); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC15 columnAlignment trailing inside HStack{one}: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { HStack { fx("c",10,10).gridColumnAlignment(.trailing) }; fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC16 columnAlignment trailing inside ZStack{one}: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { ZStack { fx("c",10,10).gridColumnAlignment(.trailing) }; fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC17 columnAlignment trailing inside overlay content side: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).overlay(fx("c",10,10).gridColumnAlignment(.trailing)); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWC18 columnAlignment trailing inside background content side: [a 10x10, b 20x20] [c 10x10, d 20x20] [e 50x10]", none) { Grid { GridRow { fx("a",10,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).background(fx("c",10,10).gridColumnAlignment(.trailing)); fx("d",20,20) }; GridRow { fx("e",50,10) } } }
    arm("GWU0 unsized h inside none: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
    arm("GWU1 unsized h inside padding(1): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).padding(1); fx("d",40,10) } } }
    arm("GWU2 unsized h inside frame(width:12,height:12): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).frame(width: 12, height: 12); fx("d",40,10) } } }
    arm("GWU3 unsized h inside frame(maxWidth:.infinity): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).frame(maxWidth: .infinity); fx("d",40,10) } } }
    arm("GWU4 unsized h inside fixedSize(): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).fixedSize(); fx("d",40,10) } } }
    arm("GWU5 unsized h inside background(Color): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).background(SwiftUI.Color.red); fx("d",40,10) } } }
    arm("GWU6 unsized h inside overlay(Color) primary: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).overlay(SwiftUI.Color.red); fx("d",40,10) } } }
    arm("GWU7 unsized h inside clipped(): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).clipped(); fx("d",40,10) } } }
    arm("GWU8 unsized h inside border(Color): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).border(SwiftUI.Color.red); fx("d",40,10) } } }
    arm("GWU9 unsized h inside opacity(0.5): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).opacity(0.5); fx("d",40,10) } } }
    arm("GWU10 unsized h inside allowsHitTesting(false): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).allowsHitTesting(false); fx("d",40,10) } } }
    arm("GWU11 unsized h inside aspectRatio(1,.fit): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).aspectRatio(1, contentMode: .fit); fx("d",40,10) } } }
    arm("GWU12 unsized h inside layoutPriority(1): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).layoutPriority(1); fx("d",40,10) } } }
    arm("GWU13 unsized h inside onTapGesture: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).onTapGesture {}; fx("d",40,10) } } }
    arm("GWU14 unsized h inside disabled(true): [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.horizontal).disabled(true); fx("d",40,10) } } }
    arm("GWU15 unsized h inside HStack{one}: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { HStack { fl("c").gridCellUnsizedAxes(.horizontal) }; fx("d",40,10) } } }
    arm("GWU16 unsized h inside ZStack{one}: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { ZStack { fl("c").gridCellUnsizedAxes(.horizontal) }; fx("d",40,10) } } }
    arm("GWU17 unsized h inside overlay content side: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).overlay(fl("c").gridCellUnsizedAxes(.horizontal)); fx("d",40,10) } } }
    arm("GWU18 unsized h inside background content side: [a 30x10, b 20x20] [c flexible, d 40x10] at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { SwiftUI.Color.clear.frame(width: 1, height: 1).background(fl("c").gridCellUnsizedAxes(.horizontal)); fx("d",40,10) } } }
    arm("GWP0 priority 1 inside none: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1) } } }
    arm("GWP1 priority 1 inside padding(1): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).padding(1) } } }
    arm("GWP2 priority 1 inside frame(width:12,height:12): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).frame(width: 12, height: 12) } } }
    arm("GWP3 priority 1 inside frame(maxWidth:.infinity): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).frame(maxWidth: .infinity) } } }
    arm("GWP4 priority 1 inside fixedSize(): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).fixedSize() } } }
    arm("GWP5 priority 1 inside background(Color): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).background(SwiftUI.Color.red) } } }
    arm("GWP6 priority 1 inside overlay(Color) primary: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).overlay(SwiftUI.Color.red) } } }
    arm("GWP7 priority 1 inside clipped(): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).clipped() } } }
    arm("GWP8 priority 1 inside border(Color): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).border(SwiftUI.Color.red) } } }
    arm("GWP9 priority 1 inside opacity(0.5): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).opacity(0.5) } } }
    arm("GWP10 priority 1 inside allowsHitTesting(false): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).allowsHitTesting(false) } } }
    arm("GWP11 priority 1 inside aspectRatio(1,.fit): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).aspectRatio(1, contentMode: .fit) } } }
    arm("GWP12 priority 1 inside layoutPriority(1): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).layoutPriority(1) } } }
    arm("GWP13 priority 1 inside onTapGesture: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).onTapGesture {} } } }
    arm("GWP14 priority 1 inside disabled(true): [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); fl("c").layoutPriority(1).disabled(true) } } }
    arm("GWP15 priority 1 inside HStack{one}: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); HStack { fl("c").layoutPriority(1) } } } }
    arm("GWP16 priority 1 inside ZStack{one}: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); ZStack { fl("c").layoutPriority(1) } } } }
    arm("GWP17 priority 1 inside overlay content side: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); SwiftUI.Color.clear.frame(width: 1, height: 1).overlay(fl("c").layoutPriority(1)) } } }
    arm("GWP18 priority 1 inside background content side: [a flexible, c flexible] at 100x100", p(100,100)) { Grid { GridRow { fl("a"); SwiftUI.Color.clear.frame(width: 1, height: 1).background(fl("c").layoutPriority(1)) } } }
    arm("GWI1 inner span 2, padding, outer span 1: [a 30x10, b 20x20, e 5x5] [c 100x10, d 5x5]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5) }; GridRow { fx("c",100,10).gridCellColumns(2).padding(1).gridCellColumns(1); fx("d",5,5) } } }
    arm("GWI2 inner span 1, padding, outer span 2", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5) }; GridRow { fx("c",100,10).gridCellColumns(1).padding(1).gridCellColumns(2); fx("d",5,5) } } }
    arm("GWI3 inner anchor topLeading, padding, outer bottomTrailing", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading).padding(1).gridCellAnchor(.bottomTrailing); fx("d",20,50) } } }
    arm("GWI4 inner column leading, padding, outer trailing: [a 10x10] [e 50x10]", none) { Grid { GridRow { fx("a",10,10).gridColumnAlignment(.leading).padding(1).gridColumnAlignment(.trailing) }; GridRow { fx("e",50,10) } } }
    arm("GWI5 unsized v, padding, unsized h (union) at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.vertical).padding(1).gridCellUnsizedAxes(.horizontal); fx("d",40,10) } } }
}

@MainActor func armsG() {
    print("=== GG: GridRow outside and inside a Grid; modifiers on a GridRow")
    arm("GG1 GridRow{a 30x10; b 20x20} inside a VStack", none) { VStack { GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GG2 GridRow{a; b} inside an HStack", none) { HStack { GridRow { fx("a",30,10); fx("b",20,20) } } }
    arm("GG3 a GridRow nested in a GridRow: [[a, b], c 5x5]", none) { Grid { GridRow { GridRow { fx("a",30,10); fx("b",20,20) }; fx("c",5,5) } } }
    arm("GG4 GridRow{a; b}.padding(5) in GA1", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }.padding(5); GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GG5 GridRow{c 10x10; d 10x10}.gridCellAnchor(.topLeading) under [a 50x10, b 20x50]", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10); fx("d",10,10) }.gridCellAnchor(.topLeading) } }
    arm("GG6 GridRow{c 100x10; d 100x10}.gridCellColumns(2) under [a, b, e, f]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5); fx("f",5,5) }; GridRow { fx("c",100,10); fx("d",100,10) }.gridCellColumns(2) } }
    arm("GG7 GridRow{a; b}.onTapGesture{} in GA1 (still a row)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }.onTapGesture {}; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GG8 rows through if and ForEach", none) { Grid { if true { GridRow { fx("a",30,10); fx("b",20,20) } }; ForEach(0..<1) { _ in GridRow { fx("c",10,30); fx("d",40,10) } } } }
    arm("GG9 an HStack containing a GridRow is a non-row child: [a, b] HStack{GridRow{c 10x30; d 40x10}}", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; HStack { GridRow { fx("c",10,30); fx("d",40,10) } } } }
}

@MainActor func armsS2() {
    print("=== GS (revision 2): a Spacer seen through wrappers and containers, for the gap")
    arm("GS12 [a 30x10, Spacer.frame(width: 8), c 10x10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); Spacer().background(fl("s")).frame(width: 8); fx("c",10,10) } } }
    arm("GS13 [a 30x10, Spacer.padding(.leading, 4), c 10x10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); Spacer().background(fl("s")).padding(.leading, 4); fx("c",10,10) } } }
    arm("GS14 [a 30x10, HStack(spacing: 0){Spacer}, c 10x10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); HStack(spacing: 0) { Spacer().background(fl("s")) }; fx("c",10,10) } } }
    arm("GS15 [a 30x10, ZStack{Spacer}, c 10x10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); ZStack { Spacer().background(fl("s")) }; fx("c",10,10) } } }
    arm("GS16 [a 30x10, 8x8 leaf with a Spacer overlay, c 10x10] at nil x 80", p(nil,80)) { Grid { GridRow { fx("a",30,10); fx("s",8,8).overlay(Spacer()); fx("c",10,10) } } }
    arm("GS17 [a 30x10] [Spacer.frame(height: 8)] [c 10x10] at 80 x nil", p(80,nil)) { Grid { GridRow { fx("a",30,10) }; GridRow { Spacer().background(fl("s")).frame(height: 8) }; GridRow { fx("c",10,10) } } }
    arm("GS18 control for GS17: [a] [8x8 leaf] [c] at 80 x nil", p(80,nil)) { Grid { GridRow { fx("a",30,10) }; GridRow { fx("s",8,8) }; GridRow { fx("c",10,10) } } }
}
@MainActor func armsP2() {
    print("=== GP (revision 3): a later group after an infinite committed column, at inf")
    arm("GP9 [a flexible, b width 0...50 h10 priority -1] at inf x inf", p(.infinity,.infinity), measureOnly: true) { Grid { GridRow { fl("a"); cw("b",0,50).layoutPriority(-1) } } }
    arm("GP10 [a flexible] [b flexible, c 10x10 priority -1] at inf x inf", p(.infinity,.infinity), measureOnly: true) { Grid { GridRow { fl("a") }; GridRow { fl("b"); fx("c",10,10).layoutPriority(-1) } } }
    arm("GP11 [a flexible, b height-flexible w10 priority -1] at inf x 100", p(.infinity,100), measureOnly: true) { Grid { GridRow { fl("a"); fh("b",10).layoutPriority(-1) } } }
}
@MainActor func armsF2() {
    print("=== GF (revision 4): a greedy frame and a Color as cells")
    arm("GF14 [a 30x10 in .frame(maxWidth: .infinity), b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100), seq: true) { Grid { GridRow { fx("a",30,10).frame(maxWidth: .infinity); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF15 GF14 at nil", none) { Grid { GridRow { fx("a",30,10).frame(maxWidth: .infinity); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF16 [a Color (bg leaf k), b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100)) { Grid { GridRow { SwiftUI.Color.red.background(fl("k")); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF17 GF16 at nil", none) { Grid { GridRow { SwiftUI.Color.red.background(fl("k")); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    arm("GF18 [a 30x10 in .frame(maxWidth: .infinity, maxHeight: .infinity), b 20x20] [c 10x30, d 40x10] at 200x100", p(200,100)) { Grid { GridRow { fx("a",30,10).frame(maxWidth: .infinity, maxHeight: .infinity); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
}
// ---------------- revision 5 ----------------
func C(_ n: String, _ k: LK) -> CellSpec { CellSpec(name: n, kind: k) }
extension CellSpec {
    func span(_ v: Int) -> CellSpec { var c = self; c.span = v; return c }
    func prio(_ v: Double) -> CellSpec { var c = self; c.prio = v; return c }
    func anchor(_ v: A9) -> CellSpec { var c = self; c.anchor = v; return c }
    func col(_ v: H3) -> CellSpec { var c = self; c.colAlign = v; return c }
    func uH() -> CellSpec { var c = self; c.unsizedH = true; return c }
    func uV() -> CellSpec { var c = self; c.unsizedV = true; return c }
}
func R(_ cells: CellSpec..., al: V3? = nil) -> ChildSpec { .row(al, cells) }
func F(_ c: CellSpec) -> ChildSpec { .full(c) }
func K(_ children: [ChildSpec], _ p: ProposedViewSize, al: A9 = .center, hs: CGFloat? = nil, vs: CGFloat? = nil) -> Case {
    Case(children: children, proposal: p, alignment: al, hs: hs, vs: vs)
}
func byName(_ m: [String: CGRect]) -> String { m.sorted { $0.key < $1.key }.map { "\($0.key)\(fmt($0.value))" }.joined(separator: " ") }
func agrees(_ rs: CGSize, _ rp: [String: CGRect], _ ms: CGSize, _ mp: [String: CGRect], sizesOnly: Bool) -> Bool {
    var ok = close(rs.width, ms.width) && close(rs.height, ms.height)
    if !sizesOnly { ok = ok && rp.count == mp.count; for (n, r) in rp where !closeR(r, mp[n]) { ok = false } }
    return ok
}

/// The arms a `Case` can spell, with the answer their own line above records
/// (a transcription check), for `model-arms`.
let modelArmCases: [(String, String, Case, Bool)] = {
    let a = C("a", .fixed(30, 10)), b = C("b", .fixed(20, 20)), c = C("c", .fixed(10, 30)), d = C("d", .fixed(40, 10))
    let ga1 = [R(a, b), R(c, d)]
    let gp2 = [R(C("a", .flex), b), R(c, d)]
    let n = none, pp = { (w: CGFloat?, h: CGFloat?) in ProposedViewSize(width: w, height: h) }
    let inf = CGFloat.infinity
    let s = C("s", .spacer)
    return [
        ("GA1", "78x58", K(ga1, n), false),
        ("GA2", "70x50", K(ga1, n, hs: 0, vs: 0), false),
        ("GA3", "73x55", K(ga1, n, hs: 3, vs: 5), false),
        ("GA4", "71x58", K([R(a, b, C("e", .fixed(5, 5))), R(c)], n), false),
        ("GA7", "30x48", K([R(a), .row(nil, []), R(c)], n), false),
        ("GA8", "30x38", K([F(C("x", .fixed(30, 10))), F(C("y", .fixed(10, 20)))], n), false),
        ("GA9", "200x100", K([F(C("x", .fixed(30, 10))), F(C("y", .flex))], pp(200, 100)), false),
        ("GP1", "78x58", K(ga1, pp(200, 200)), false),
        ("GP2", "200x100", K(gp2, pp(200, 100)), false),
        ("GP3", "58x58", K(gp2, n), false),
        ("GP4", "infxinf", K(gp2, pp(inf, inf)), true),
        ("GP5", "200x58", K(gp2, pp(200, nil)), false),
        ("GP6", "58x100", K(gp2, pp(nil, 100)), false),
        ("GP7", "100x100", K([R(C("a", .flex))], pp(100, 100)), false),
        ("GP8", "78x58", K(ga1, pp(inf, inf)), true),
        ("GP9", "infxinf", K([R(C("a", .flex), C("b", .clampW(0, 50, 10)).prio(-1))], pp(inf, inf)), true),
        ("GP10", "infxinf", K([R(C("a", .flex)), R(C("b", .flex), C("c", .fixed(10, 10)).prio(-1))], pp(inf, inf)), true),
        ("GP11", "infx100", K([R(C("a", .flex), C("b", .flexH(10)).prio(-1))], pp(inf, 100)), true),
        ("GF1", "104x58", K([R(C("a", .half), b), R(c, C("d", .half))], pp(200, 200)), false),
        ("GF2", "200x58", K([R(C("a", .flexW(20)), b), R(c, d)], pp(200, 100)), false),
        ("GF3", "68x100", K([R(C("a", .flexH(20)), b), R(c, d)], pp(200, 100)), false),
        ("GF4", "198x100", K([R(C("a", .clampBoth(0, 150)), b), R(c, d)], pp(200, 100)), false),
        ("GF5", "98x88", K([R(C("a", .clampBoth(0, 50)), b), R(c, d)], pp(200, 100)), false),
        ("GF6", "200x100", K([R(C("a", .flex), b), R(c, C("d", .flex))], pp(200, 100)), false),
        ("GF7", "138x100", K([R(C("a", .flex), C("b", .fixed(120, 20))), R(c, d)], pp(100, 100)), false),
        ("GF8", "200x100", K([R(C("a", .fixed(20, 20)), C("b", .flex), C("c", .flex))], pp(200, 100)), false),
        ("GF9", "93x10", K([R(C("a", .clampW(0, 30, 10)), C("b", .clampW(0, 55, 10)))], pp(100, 100)), false),
        ("GF10", "200x100", K([R(C("a", .half), C("b", .flex))], pp(200, 100)), false),
        ("GF11", "138x100", K([R(C("a", .clampW(10, 20, 10)), C("b", .flexH(20)), C("c", .clampW(10, 160, 30)))], pp(200, 100)), false),
        ("GF12", "150x10", K([R(C("a", .clampBoth(10, 50)), C("b", .flexH(30)), C("c", .flex))], pp(150, nil)), false),
        ("GF13", "150x100", K([R(C("a", .clampBoth(10, 50)), C("b", .flexH(30)), C("c", .flex))], pp(150, 100)), false),
        ("GS1", "190x80", K([R(s, b), R(c, d)], pp(200, 100)), false),
        ("GS2", "48x80", K([R(a, s, C("c", .flexH(10)))], pp(nil, 80)), false),
        ("GS3", "64x80", K([R(a, C("s", .fixed(8, 8)), C("c", .flexH(10)))], pp(nil, 80)), false),
        ("GS4", "90x40", K([R(C("a", .half)), R(s, C("c", .clampW(30, 180, 20)))], pp(60, 60)), false),
        ("GS5", "76.67x136", K([R(C("a", .fixed(40, 40))), R(C("b", .half), C("c", .fixed(20, 40)).span(2)), R(C("d", .clampW(0, 30, 40)))], pp(300, 200)), false),
        ("GS6", "68x136", K([R(C("a", .fixed(40, 40))), R(C("b", .half), C("c", .fixed(20, 40)).span(2)), R(C("d", .clampW(0, 30, 40)))], n), false),
        ("GS8", "60x45", K(ga1, n, hs: -10, vs: -5), false),
        ("GS11", "72x70", K([R(a, s, C("c", .fixed(10, 10)))], pp(nil, 80), hs: 12), false),
        ("GX1", "100x38", K([R(a, b), R(C("c", .fixed(100, 10)).span(2))], n), false),
        ("GX2", "58x38", K([R(a, b), R(C("c", .fixed(10, 10)).span(2))], n), false),
        ("GX3", "100x76", K([R(a, b), F(C("x", .fixed(100, 10))), R(c, d)], n), false),
        ("GX4", "58x38", K([R(a, b), F(C("x", .half))], n), false),
        ("GX5", "113x38", K([R(a, b, C("c", .fixed(5, 5))), R(C("x", .fixed(100, 10)).span(2), C("y", .fixed(1, 1)))], n), false),
        ("GX6", "58x38", K([R(a, b), R(C("x", .fixed(10, 10)).span(5))], n), false),
        ("GX7", "100x38", K([R(C("x", .fixed(100, 10)).span(2)), R(a, b)], n), false),
        ("GX8", "100x38", K([R(C("x", .fixed(100, 10)).span(2)), R(a, b)], pp(300, 100)), false),
        ("GX9", "300x100", K([R(a, C("b", .flex)), R(C("x", .fixed(100, 10)).span(2))], pp(300, 100)), false),
        ("GX10", "300x100", K([R(a, C("b", .fixed(20, 10))), R(C("x", .flex).span(2))], pp(300, 100)), false),
        ("GX11", "156x58", K([R(C("a", .clampBoth(0, 100)), C("b", .fixed(100, 40)).span(2), C("c", .clampW(30, 40, 40)).span(2)), R(C("d", .flexH(10)).span(2), C("e", .flexH(10)), C("f", .clampW(30, 180, 10)))], n), false),
        ("GX12", "300x114", K([R(C("a", .clampBoth(20, 120)), C("b", .clampW(0, 60, 30))), F(C("x", .flexW(10)))], pp(300, 200)), false),
        ("GX13", "71x38", K([R(a, b, C("e", .fixed(5, 5))), F(C("x", .fixed(10, 10)))], n), false),
        ("GX15 (columns 3 + 2 spelled as 5)", "109x38", K([R(a, b, C("e", .fixed(5, 5)), C("f", .fixed(5, 5))), R(C("c", .fixed(100, 10)).span(5), C("d", .fixed(1, 1)))], n), false),
        ("GX16 (columns 2 + 1 spelled as 2)", "126x38", K([R(a, b, C("e", .fixed(5, 5)), C("f", .fixed(5, 5))), R(C("c", .fixed(100, 10)).span(2), C("d", .fixed(1, 1)))], n), false),
        ("GX17", "284x100", K([R(a, C("b", .flex), C("c", .fixed(20, 20))), R(C("x", .fixed(150, 10)).span(3))], pp(200, 100)), false),
        ("GX18", "231.33x100", K([R(C("a", .flex), C("b", .clampW(10, 30, 10)), C("c", .clampW(20, 50, 10))), F(C("x", .fixed(60, 10)))], pp(200, 100)), false),
        ("GX19", "200x100", K([R(C("a", .flex), C("b", .clampW(10, 30, 10)), C("c", .clampW(20, 50, 10))), F(C("x", .fixed(40, 10)))], pp(200, 100)), false),
        ("GQ1", "100x100", K([R(C("a", .flex), C("b", .flex).prio(1))], pp(100, 100)), false),
        ("GQ2", "130x10", K([R(C("a", .clampW(0, 200, 10)), C("b", .clampW(30, 200, 10)).prio(-1), C("c", .clampW(20, 200, 10)))], pp(100, 100)), false),
        ("GQ3", "120x10", K([R(C("a", .clampW(0, 200, 10)), C("b", .clampW(30, 200, 10)).prio(1), C("c", .clampW(20, 200, 10)))], pp(100, 100)), false),
        ("GQ4", "210x120", K([R(C("a", .flex), b), R(c, C("d", .flex).prio(1))], pp(200, 100)), false),
        ("GQ5", "266x118", K([R(C("a", .clampBoth(10, 70)).prio(1)), R(C("b", .fixed(20, 10)).prio(1), C("c", .fixed(150, 30)), C("d", .clampW(30, 180, 40)))], pp(100, 100)), false),
        ("GQ6", "58x58", K([R(s, b), R(c, d)], n), false),
        ("GQ8", "100x100", K([R(s)], pp(100, 100)), false),
        ("GL1", "78x58", K(ga1, n, al: .topLeading), false),
        ("GL2", "78x58", K(ga1, n, al: .bottomTrailing), false),
        ("GL3", "78x58", K([R(a, b, al: .top), R(c, d)], n), false),
        ("GL4", "78x58", K([R(a, b.col(.trailing)), R(c, d)], n), false),
        ("GL5", "78x58", K([R(C("a", .fixed(10, 10)), b), R(C("c", .fixed(30, 30)).col(.trailing), d)], n), false),
        ("GL6", "30x46", K([R(C("a", .fixed(10, 10)).col(.leading)), R(C("b", .fixed(10, 10))), R(C("c", .fixed(30, 10)).col(.trailing))], n), false),
        ("GL7", "30x46", K([R(C("a", .fixed(10, 10)).col(.trailing)), R(C("b", .fixed(10, 10))), R(C("c", .fixed(30, 10)).col(.leading))], n), false),
        ("GL8", "58x46", K([R(C("a", .fixed(10, 10)), C("b", .fixed(10, 10))), R(C("c", .fixed(30, 10)).span(2).col(.trailing)), R(C("d", .fixed(40, 10)))], n), false),
        ("GL9", "28x68", K([R(C("a", .fixed(10, 10)), C("b", .fixed(10, 30)), al: .top), R(C("c", .fixed(10, 10)), C("d", .fixed(10, 30)))], n, al: .bottom), false),
        ("GL10", "58x48", K([R(C("a", .fixed(10, 10)).anchor(.topLeading).col(.trailing), C("b", .fixed(10, 30))), R(C("c", .fixed(40, 10)))], n), false),
        ("GL11", "58x48", K([R(C("a", .fixed(40, 10)), C("b", .fixed(10, 30))), F(C("x", .fixed(10, 10)).anchor(.trailing))], n), false),
        ("GL12", "58x48", K([R(C("a", .fixed(40, 10)), C("b", .fixed(10, 30))), F(C("x", .fixed(10, 10)))], n, al: .leading), false),
        ("GL13", "116x78", K([R(C("a", .fixed(10, 10)).col(.trailing), C("b", .fixed(20, 40)), C("e", .fixed(10, 10)).anchor(.center), al: .bottom), R(C("c", .fixed(30, 30)), d, C("f", .fixed(30, 30)))], n, al: .topLeading), false),
        ("GL15 (inner leading)", "50x28", K([R(C("a", .fixed(10, 10)).col(.leading)), R(C("e", .fixed(50, 10)))], n), false),
        ("GL16 (inner topLeading)", "78x108", K([R(C("a", .fixed(50, 10)), C("b", .fixed(20, 50))), R(C("c", .fixed(10, 10)).anchor(.topLeading), C("d", .fixed(20, 50)))], n), false),
        ("GU1", "78x200", K([R(a, b), R(C("c", .flex).uH(), d)], pp(200, 200)), false),
        ("GU2", "200x200", K([R(a, b), R(C("c", .flex), d)], pp(200, 200)), false),
        ("GU3", "58x28", K([R(a, b), R(C("c", .flex).uH().uV().span(2))], pp(200, 200)), false),
        ("GU4", "148x58", K([R(a, b), R(C("c", .fixed(100, 30)).uH(), d)], n), false),
        ("GU5", "148x58", K([R(a, b), R(C("c", .fixed(100, 30)).uH(), d)], pp(200, 200)), false),
        ("GU6", "78x78", K([R(a, b), R(C("c", .fixed(10, 50)).uV(), d)], pp(200, 200)), false),
        ("GU7", "134x100", K([R(C("a", .flex).uH(), C("b", .flex)), R(C("c", .fixed(30, 30)), d)], pp(200, 100)), false),
        ("GU8", "200x100", K([R(C("a", .clampW(0, 50, 10)).uH(), C("b", .flex)), R(C("c", .fixed(30, 30)), d)], pp(200, 100)), false),
        ("GU9", "58x100", K([R(a, b), F(C("x", .flex).uH())], pp(200, 100)), false),
        ("GU10", "200x100", K([R(a, b), F(C("x", .flex))], pp(200, 100)), false),
        ("GU11", "0x0", K([R(C("a", .flex).uH().uV())], pp(200, 100)), false),
        ("GU12", "78x38", K([R(a, b), R(C("c", .flex).uH().uV(), d)], pp(200, 200)), false),
        ("GU13", "78x200", K([R(a, b), R(C("c", .flex).uH(), d)], pp(200, 200)), false),
        ("GG3 (flattened)", "71x20", K([R(a, b, C("c", .fixed(5, 5)))], n), false),
        ("GG5 (per cell)", "78x68", K([R(C("a", .fixed(50, 10)), C("b", .fixed(20, 50))), R(C("c", .fixed(10, 10)).anchor(.topLeading), C("d", .fixed(10, 10)).anchor(.topLeading))], n), false),
        ("GG6 (per cell)", "208x38", K([R(a, b, C("e", .fixed(5, 5)), C("f", .fixed(5, 5))), R(C("c", .fixed(100, 10)).span(2), C("d", .fixed(100, 10)).span(2))], n), false),
    ]
}()

@MainActor func modelArms() {
    print("=== MODEL-ARMS (revision 5): the reference model on every arm a Case can spell")
    var agree = 0, differ = 0, transcription = 0
    for (id, expected, k, mo) in modelArmCases {
        let (rs, rp) = host(k.proposal, measureOnly: mo) { realGrid(k) }
        let (ms, mp) = host(k.proposal, measureOnly: mo) { modelGrid(k) }
        let tag = fmt(rs) == expected ? "" : " TRANSCRIPTION: the arm reads \(expected)"
        if !tag.isEmpty { transcription += 1 }
        if agrees(rs, rp, ms, mp, sizesOnly: mo) {
            agree += 1; print("\(id) agrees: \(fmt(rs))\(tag)")
        } else {
            differ += 1
            print("\(id) DIFFERS\(tag)")
            print("    SwiftUI \(fmt(rs)) \(mo ? "" : byName(rp))")
            print("    model   \(fmt(ms)) \(mo ? "" : byName(mp))")
        }
    }
    print("MODEL-ARMS: \(agree) agree, \(differ) differ, \(transcription) transcription mismatches, of \(modelArmCases.count)")
    fflush(stdout)
}

enum StackKind { case h, v }
@MainActor func embeddedCompare(_ label: String, _ axis: StackKind, _ sibling: CellSpec, _ k: Case) -> Bool {
    let (rs, rp) = host(k.proposal) {
        if axis == .h { HStack { leafView(sibling); realGrid(k) } } else { VStack { leafView(sibling); realGrid(k) } }
    }
    let (ms, mp) = host(k.proposal) {
        if axis == .h { HStack { leafView(sibling); modelGrid(k) } } else { VStack { leafView(sibling); modelGrid(k) } }
    }
    let ok = agrees(rs, rp, ms, mp, sizesOnly: false)
    if !label.isEmpty {
        print("\(label) \(axis == .h ? "HStack" : "VStack"){\(sibling.name):\(sibling.kind.text); \(caseText(k))} \(ok ? "agrees" : "DIFFERS")")
        print("    SwiftUI \(fmt(rs)) \(byName(rp))")
        if !ok { print("    model   \(fmt(ms)) \(byName(mp))") }
    }
    return ok
}

@MainActor func armsE() {
    print("=== GE (revision 5): a Grid inside a stack — its edges, its priority, a Spacer cell, its answers at a stack's proposals")
    arm("GE1 HStack{a 30x10; Grid{[Spacer (bg s), b 20x20]}; c 10x10}: the grid's leading edge", none) { HStack { fx("a",30,10); Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) } }; fx("c",10,10) } }
    arm("GE2 control for GE1: the Spacer replaced by an 8x8 leaf s", none) { HStack { fx("a",30,10); Grid { GridRow { fx("s",8,8); fx("b",20,20) } }; fx("c",10,10) } }
    arm("GE3 HStack{a; Grid{[b 20x20, Spacer (bg s)]}; c}: the trailing edge", none) { HStack { fx("a",30,10); Grid { GridRow { fx("b",20,20); Spacer().background(fl("s")) } }; fx("c",10,10) } }
    arm("GE4 HStack{a; Grid{[Spacer (bg s), b 20x20] [d 20x20, e 20x20]}; c}: a Spacer leading one row of two", none) { HStack { fx("a",30,10); Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) }; GridRow { fx("d",20,20); fx("e",20,20) } }; fx("c",10,10) } }
    arm("GE5 HStack{a; Grid{[Spacer (bg s), b 20x20] [Spacer (bg t), e 20x20]}; c}: a Spacer leading every row", none) { HStack { fx("a",30,10); Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) }; GridRow { Spacer().background(fl("t")); fx("e",20,20) } }; fx("c",10,10) } }
    arm("GE6 VStack{a 30x10; Grid{[Spacer (bg s)] [b 20x20]}; c 10x10}: the grid's top edge", none) { VStack { fx("a",30,10); Grid { GridRow { Spacer().background(fl("s")) }; GridRow { fx("b",20,20) } }; fx("c",10,10) } }
    arm("GE7 control for GE6: the Spacer replaced by an 8x8 leaf s", none) { VStack { fx("a",30,10); Grid { GridRow { fx("s",8,8) }; GridRow { fx("b",20,20) } }; fx("c",10,10) } }
    arm("GE8 HStack{a flexible; Grid{[c flexible priority 1]}} at 100x100: a one-cell grid's priority", p(100,100)) { HStack { fl("a"); Grid { GridRow { fl("c").layoutPriority(1) } } } }
    arm("GE9 control for GE8: no priority", p(100,100)) { HStack { fl("a"); Grid { GridRow { fl("c") } } } }
    arm("GE10 HStack{a flexible; Grid{[c flexible priority 1, d 10x10]}} at 100x100: two cells", p(100,100)) { HStack { fl("a"); Grid { GridRow { fl("c").layoutPriority(1); fx("d",10,10) } } } }
    arm("GE11 HStack{a flexible; Grid{[Spacer (bg s)]}} at 100x100: a one-cell grid of a Spacer", p(100,100)) { HStack { fl("a"); Grid { GridRow { Spacer().background(fl("s")) } } } }
    arm("GE12 HStack(spacing: 0){Grid{[a 30x10] [Spacer (bg s)] [c 10x10]}} at nil x 80: row gaps beside a Spacer under an enclosing HStack", p(nil,80)) { HStack(spacing: 0) { Grid { GridRow { fx("a",30,10) }; GridRow { Spacer().background(fl("s")) }; GridRow { fx("c",10,10) } } } }
    arm("GE13 control for GE12: the grid with no stack", p(nil,80)) { Grid { GridRow { fx("a",30,10) }; GridRow { Spacer().background(fl("s")) }; GridRow { fx("c",10,10) } } }
    arm("GE14 VStack(spacing: 0){Grid{[a 30x10, Spacer (bg s), c 10x10]}} at 80 x nil: column gaps beside a Spacer under an enclosing VStack", p(80,nil)) { VStack(spacing: 0) { Grid { GridRow { fx("a",30,10); Spacer().background(fl("s")); fx("c",10,10) } } } }
    arm("GE15 control for GE14: the grid with no stack", p(80,nil)) { Grid { GridRow { fx("a",30,10); Spacer().background(fl("s")); fx("c",10,10) } } }
    arm("GE16 HStack{a 30x10; Grid{} ; c 10x10}: an empty grid's edges", none) { HStack { fx("a",30,10); Grid { }; fx("c",10,10) } }
    let a = C("a", .fixed(30, 10)), b = C("b", .fixed(20, 20)), c = C("c", .fixed(10, 30)), d = C("d", .fixed(40, 10))
    _ = embeddedCompare("GE17", .h, C("z", .flex), K([R(C("a", .flex), b), R(c, d)], p(200, 100)))
    _ = embeddedCompare("GE18", .h, C("z", .flexW(20)), K([R(a, b), R(c, d)], p(200, 100)))
    _ = embeddedCompare("GE19", .v, C("z", .flex), K([R(C("a", .flex), b), R(c, d)], p(200, 100)))
    _ = embeddedCompare("GE20", .h, C("z", .clampW(0, 100, 10)), K([R(C("b", .half), C("x", .flex)), R(C("e", .fixed(10, 30)))], p(150, 80)))
    _ = embeddedCompare("GE21", .h, C("z", .fixed(30, 10)), K([R(C("a", .flex), b), R(c, d)], p(nil, 80)))
    _ = embeddedCompare("GE22", .v, C("z", .half), K([R(C("a", .clampW(0, 60, 10)), C("b", .flexH(10))), R(c, d)], p(120, nil)))
    arm("GE23 VStack{a 30x10; Grid{[Spacer (bg s), b 20x20]}; c 10x10}: a Spacer in the top row beside a leaf", none) { VStack { fx("a",30,10); Grid { GridRow { Spacer().background(fl("s")); fx("b",20,20) } }; fx("c",10,10) } }
    arm("GE24 VStack{a 30x10; Grid{[b 20x20] [Spacer (bg s)]}; c 10x10}: a Spacer in the last row only", none) { VStack { fx("a",30,10); Grid { GridRow { fx("b",20,20) }; GridRow { Spacer().background(fl("s")) } }; fx("c",10,10) } }
    arm("GE25 HStack{a 30x10; Grid{[b 20x20] Spacer (bg s, non-row)}; c 10x10}: a non-row Spacer", none) { HStack { fx("a",30,10); Grid { GridRow { fx("b",20,20) }; Spacer().background(fl("s")) }; fx("c",10,10) } }
    arm("GE26 HStack{a 30x10; Grid{[b 20x20, e 20x20] [Spacer (bg s)]}; c 10x10}: a Spacer starting a short last row", none) { HStack { fx("a",30,10); Grid { GridRow { fx("b",20,20); fx("e",20,20) }; GridRow { Spacer().background(fl("s")) } }; fx("c",10,10) } }
    arm("GE27 positive control for GE8: HStack{a flexible; c flexible priority 1} at 100x100, no grid", p(100,100)) { HStack { fl("a"); fl("c").layoutPriority(1) } }
    arm("GE28 positive control for GE11: HStack{a flexible; Spacer (bg s)} at 100x100, no grid", p(100,100)) { HStack { fl("a"); Spacer().background(fl("s")) } }
}

@MainActor func armsN() {
    print("=== GN (revision 5): Text cells — a form of labels and wrapping values (Texts read through background leaves)")
    let long = "12 St James's Square, London SW1Y 4LB, England"
    func form(_ al: Alignment) -> some View {
        Grid(alignment: al) {
            GridRow { Text("Name").background(fl("t1")); Text("Ada Lovelace").background(fl("t2")) }
            GridRow { Text("Address").background(fl("t3")); Text(long).background(fl("t4")) }
        }
    }
    arm("GN1 form [Name, Ada Lovelace] [Address, long] at nil", none) { form(.center) }
    arm("GN2 the form at 200 x nil", p(200,nil)) { form(.center) }
    arm("GN3 the form at 120 x nil", p(120,nil)) { form(.center) }
    arm("GN4 the form, Grid(alignment: .leading), at 200 x nil", p(200,nil)) { form(.leading) }
    arm("GN5 the form at 200 x 100", p(200,100)) { form(.center) }
    arm("GN6 control: the long Text alone at 128 x nil", p(128,nil)) { Text(long).background(fl("t4")) }
    arm("GN7 [Text A, Text B] [Text C, Text D] at 80 x nil: row gap between Text rows at a finite width", p(80,nil)) { Grid { GridRow { Text("A").background(fl("t1")); Text("B").background(fl("t2")) }; GridRow { Text("C").background(fl("t3")); Text("D").background(fl("t4")) } } }
    let form = { (w: CGFloat?) in K([R(C("l1", .wrap(40, 16)), C("v1", .wrap(84, 16))), R(C("l2", .wrap(56, 16)), C("v2", .wrap(290, 16)))], p(w, nil)) }
    for (id, w) in [("GN8", CGFloat(200)), ("GN9", 120), ("GN10", 60)] {
        let k = form(w)
        let (rs, rp) = host(k.proposal) { realGrid(k) }
        let (ms, mp) = host(k.proposal) { modelGrid(k) }
        let ok = agrees(rs, rp, ms, mp, sizesOnly: false)
        print("\(id) text-like wrap leaves \(caseText(k)) \(ok ? "agrees" : "DIFFERS")")
        print("    SwiftUI \(fmt(rs)) \(byName(rp))")
        if !ok { print("    model   \(fmt(ms)) \(byName(mp))") }
    }
}

@MainActor func armsG2() {
    print("=== GG (revision 5): nested GridRow alignment; a cell attribute on a GridRow against the cell's own")
    arm("GG10 Grid{GridRow(.top){GridRow(.bottom){a 10x10; b 10x30}; c 10x20}}", none) { Grid { GridRow(alignment: .top) { GridRow(alignment: .bottom) { fx("a",10,10); fx("b",10,30) }; fx("c",10,20) } } }
    arm("GG11 the reverse: Grid{GridRow(.bottom){GridRow(.top){a 10x10; b 10x30}; c 10x20}}", none) { Grid { GridRow(alignment: .bottom) { GridRow(alignment: .top) { fx("a",10,10); fx("b",10,30) }; fx("c",10,20) } } }
    arm("GG12 control: Grid{GridRow{GridRow(.bottom){a; b}; c}} (outer row unaligned)", none) { Grid { GridRow { GridRow(alignment: .bottom) { fx("a",10,10); fx("b",10,30) }; fx("c",10,20) } } }
    arm("GG13 [a 50x10, b 20x50] GridRow{c 10x10 anchor(.topLeading); d 20x50}.gridCellAnchor(.bottomTrailing)", none) { Grid { GridRow { fx("a",50,10); fx("b",20,50) }; GridRow { fx("c",10,10).gridCellAnchor(.topLeading); fx("d",20,50) }.gridCellAnchor(.bottomTrailing) } }
    arm("GG14 [a 10x10] [e 50x10] with GridRow{a column(.leading)}.gridColumnAlignment(.trailing)", none) { Grid { GridRow { fx("a",10,10).gridColumnAlignment(.leading) }.gridColumnAlignment(.trailing); GridRow { fx("e",50,10) } } }
    arm("GG15 [a,b,e 5x5,f 5x5,g 5x5] GridRow{c 100x10 columns(2); d 1x1}.gridCellColumns(2)", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20); fx("e",5,5); fx("f",5,5); fx("g",5,5) }; GridRow { fx("c",100,10).gridCellColumns(2); fx("d",1,1) }.gridCellColumns(2) } }
    arm("GG16 [a 30x10, b 20x20] [c flexible unsized(.vertical)] row .gridCellUnsizedAxes(.horizontal) at 200x200", p(200,200)) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fl("c").gridCellUnsizedAxes(.vertical); fx("d",40,10) }.gridCellUnsizedAxes(.horizontal) } }
    print("=== GQ (revision 5): a Spacer with .layoutPriority(0) is not a bare Spacer")
    arm("GQ9 GS1 with Spacer().layoutPriority(0)", p(200,100)) { Grid { GridRow { Spacer().background(fl("s")).layoutPriority(0); fx("b",20,20) }; GridRow { fx("c",10,30); fx("d",40,10) } } }
    let (_, _) = host(none) { PriorityReader { Spacer(); Spacer().layoutPriority(0); Spacer().layoutPriority(1); Spacer().background(SwiftUI.Color.red); Spacer().gridCellColumns(1); SwiftUI.Color.red } }
    print("GQ10 subview-proxy priority of [Spacer(), Spacer().layoutPriority(0), Spacer().layoutPriority(1), Spacer().background(Color), Spacer().gridCellColumns(1), Color]: " + readPriorities.map { "\($0)" }.joined(separator: ", "))
}
nonisolated(unsafe) var readPriorities: [Double] = []
/// Reads its subviews' `priority` (GQ10).
struct PriorityReader: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        readPriorities = subviews.map { Double($0.priority) }; lastSize = CGSize(width: 10, height: 10); return lastSize
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
}

/// Revision 5: plain grids beside a sibling leaf in an HStack or VStack,
/// SwiftUI's Grid against the model, every rect.
@MainActor func fuzzEmbedded(_ label: String, seed: UInt64, count: Int, _ axis: StackKind, show: Int) {
    var g = LCG(s: seed); var bad = 0
    for _ in 0..<count {
        let k = randomCase(&g, [])
        let sibling = CellSpec(name: "z", kind: randomKind(&g, spacers: false))
        if !embeddedCompare("", axis, sibling, k) {
            bad += 1
            if bad <= show { _ = embeddedCompare("  DIFFERS", axis, sibling, k) }
        }
    }
    print("FUZZ \(label) seed \(seed): \(count - bad) of \(count) agree")
    fflush(stdout)
}

/// Revision 5: GZ6's disagreements, by symptom and by which one-rule variant
/// of the model agrees with SwiftUI instead (`modelVariant`).
@MainActor func classifySpans() {
    var g = LCG(s: 106)
    var symptoms: [String: Int] = [:], fixes: [String: Int] = [:], total = 0
    for _ in 0..<500 {
        let k = randomCase(&g, [.spans])
        modelVariant = 0
        let (rs, rp) = host(k.proposal) { realGrid(k) }
        let (ms, mp) = host(k.proposal) { modelGrid(k) }
        if agrees(rs, rp, ms, mp, sizesOnly: false) { continue }
        total += 1
        let pw = k.proposal.width
        let kind = pw == nil ? (k.proposal.height == nil ? "nil x nil" : "nil width, finite height") : (k.proposal.height == nil ? "finite width, nil height" : "finite x finite")
        var symptom: String
        if let pw, rs.width > pw + 0.01, ms.width <= pw + 0.01 { symptom = "SwiftUI wider than the proposal, the model within it" }
        else if ms.width > rs.width + 0.01 { symptom = "the model wider than SwiftUI" }
        else if rs.width > ms.width + 0.01 { symptom = "SwiftUI wider than the model, not the overflow above" }
        else if !close(rs.height, ms.height) { symptom = "equal widths, heights differ" }
        else { symptom = "equal sizes, rects differ" }
        symptoms["\(symptom) | \(kind)", default: 0] += 1
        var fixedBy: [Int] = []
        for v in 1...6 {
            modelVariant = v
            let (vs, vp) = host(k.proposal) { modelGrid(k) }
            if agrees(rs, rp, vs, vp, sizesOnly: false) { fixedBy.append(v) }
        }
        modelVariant = 0
        fixes[fixedBy.isEmpty ? "no single variant" : "variant " + fixedBy.map(String.init).joined(separator: "+"), default: 0] += 1
    }
    print("CLASSIFY GZ6 (seed 106, 500 grids with spans): \(total) disagreements")
    for (key, n) in symptoms.sorted(by: { $0.key < $1.key }) { print("  symptom \(key): \(n)") }
    for (key, n) in fixes.sorted(by: { $0.key < $1.key }) { print("  agrees under \(key): \(n)") }
    fflush(stdout)
}
// ---------------- corpus ----------------
func lit(_ v: CGFloat?) -> String { v.map { "\(Double($0))" } ?? "nil" }
func kindLit(_ k: LK) -> String {
    switch k {
    case let .fixed(w, h): return ".fixed(\(lit(w)), \(lit(h)))"
    case .flex: return ".flex"
    case let .clampBoth(lo, hi): return ".clampBoth(\(lit(lo)), \(lit(hi)))"
    case let .flexW(h): return ".flexW(\(lit(h)))"
    case let .flexH(w): return ".flexH(\(lit(w)))"
    case .half: return ".half"
    case let .clampW(lo, hi, h): return ".clampW(\(lit(lo)), \(lit(hi)), \(lit(h)))"
    case .spacer: return ".spacer"
    case let .wrap(n, l): return ".wrap(\(lit(n)), \(lit(l)))"
    }
}
func cellLit(_ c: CellSpec) -> String {
    var s = ".init(\(kindLit(c.kind))"
    if c.span != 1 { s += ", span: \(c.span)" }
    if c.prio != 0 { s += ", priority: \(Double(c.prio))" }
    if let a = c.anchor { s += ", anchor: .\(a)" }
    if let h = c.colAlign { s += ", columnAlignment: .\(h)" }
    if c.unsizedH { s += ", unsizedHorizontal: true" }
    if c.unsizedV { s += ", unsizedVertical: true" }
    return s + ")"
}
@MainActor func corpus(seed: UInt64, want: Int) {
    var g = LCG(s: seed); var kept = 0; var tried = 0; var skippedDiffer = 0; var skippedInfinite = 0
    print("// BEGIN CORPUS (seed \(seed))")
    while kept < want {
        tried += 1
        let k = randomCase(&g, [.spans, .prios, .fulls, .attrs, .spacers, .spacing])
        let (rs, rp) = host(k.proposal) { realGrid(k) }
        let (ms, mp) = host(k.proposal) { modelGrid(k) }
        var ok = close(rs.width, ms.width) && close(rs.height, ms.height) && rp.count == mp.count
        for (name, r) in rp where !closeR(r, mp[name]) { ok = false }
        if !ok { skippedDiffer += 1; continue }
        let finite = rs.width.isFinite && rs.height.isFinite && rp.values.allSatisfy { $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite }
        if !finite { skippedInfinite += 1; continue }
        kept += 1
        let children = k.children.map { ch -> String in
            switch ch {
            case let .row(al, cells): return ".row(\(al.map { ".\($0)" } ?? "nil"), [" + cells.map(cellLit).joined(separator: ", ") + "])"
            case let .full(c): return ".spanning(\(cellLit(c)))"
            }
        }.joined(separator: ", ")
        let names = rp.keys.sorted { Int($0.dropFirst())! < Int($1.dropFirst())! }
        let rects = names.map { n -> String in let r = rp[n]!; return "(\(lit(r.minX)), \(lit(r.minY)), \(lit(r.width)), \(lit(r.height)))" }.joined(separator: ", ")
        print("GridCorpusCase(id: \(kept), proposal: (\(lit(k.proposal.width)), \(lit(k.proposal.height))), alignment: .\(k.alignment), horizontalSpacing: \(lit(k.hs)), verticalSpacing: \(lit(k.vs)),")
        print("    children: [\(children)],")
        print("    size: (\(lit(rs.width)), \(lit(rs.height))), rects: [\(rects)]),")
    }
    print("// END CORPUS: \(kept) kept of \(tried) generated; \(skippedDiffer) skipped because SwiftUI and the model differ, \(skippedInfinite) because an answer was infinite")
    fflush(stdout)
}
// ---------------- main ----------------
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
if CommandLine.arguments.contains("trap-negative-columns") {
    MainActor.assumeIsolated {
        print("GT1 gridCellColumns(-1): laying out; a trap ends the process here")
        fflush(stdout)
        arm("GT1", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(-1); fx("d",5,5) } } }
        print("GT1 survived")
    }
    exit(0)
}
if CommandLine.arguments.contains("huge-columns") {
    MainActor.assumeIsolated {
        arm("GX21 [a 30x10, b 20x20] [c 10x10 columns(100_000), d 5x5]: clamped", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(100_000); fx("d",5,5) } } }
        arm("GX22 [a 30x10, b 20x20] [c 10x10 columns(1 << 40), d 5x5]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(1 << 40); fx("d",5,5) } } }
        print("GX20 gridCellColumns(Int.max): laying out; a trap ends the process here")
        fflush(stdout)
        arm("GX20 [a 30x10, b 20x20] [c 10x10 columns(Int.max), d 5x5]", none) { Grid { GridRow { fx("a",30,10); fx("b",20,20) }; GridRow { fx("c",10,10).gridCellColumns(Int.max); fx("d",5,5) } } }
        print("GX20 survived")
    }
    exit(0)
}
if CommandLine.arguments.contains("model-arms") {
    MainActor.assumeIsolated { modelArms() }
    exit(0)
}
if CommandLine.arguments.contains("classify-spans") {
    MainActor.assumeIsolated { classifySpans() }
    exit(0)
}
if CommandLine.arguments.contains("corpus") {
    MainActor.assumeIsolated { corpus(seed: 4242, want: 120) }
    exit(0)
}
MainActor.assumeIsolated {
    armsA(); armsP(); armsF(); armsR(); armsS(); armsX(); armsQ(); armsL(); armsU(); armsW(); armsG(); armsS2(); armsP2(); armsF2()
    print("=== GZ: the reference model (solve/ModelGrid above) against SwiftUI's Grid on generated grids")
    controlIgnoresCommits = true
    _ = fuzz("GZ0 control: the model with commits ignored (must disagree)", seed: 101, count: 300, [], show: 1)
    controlIgnoresCommits = false
    _ = fuzz("GZ1 plain", seed: 101, count: 1000, [], show: 1)
    _ = fuzz("GZ2 alignment, anchors, column alignment, unsized axes, explicit spacing", seed: 102, count: 1000, [.attrs, .spacing], show: 3)
    _ = fuzz("GZ3 Spacer cells", seed: 103, count: 500, [.spacers, .attrs], show: 3)
    _ = fuzz("GZ4 layout priority", seed: 104, count: 500, [.prios], show: 3)
    _ = fuzz("GZ5 non-row children", seed: 105, count: 500, [.fulls, .attrs], show: 3)
    _ = fuzz("GZ6 spans", seed: 106, count: 500, [.spans], show: 3)
    _ = fuzz("GZ7 infinite proposals (sizes only)", seed: 108, count: 300, [.inf, .attrs, .spans, .fulls, .prios], show: 3)
    _ = fuzz("GZ8 everything", seed: 109, count: 1000, [.spans, .prios, .fulls, .attrs, .spacers, .spacing], show: 3)
    armsE(); armsN(); armsG2()
    print("=== GZ (revision 5): plain grids at a stack's probe proposals, and beside a sibling in a stack")
    _ = fuzz("GZ9 plain, infinite proposals (sizes only)", seed: 110, count: 300, [.inf], show: 3)
    _ = fuzz("GZ10 plain, a zero axis", seed: 111, count: 300, [.zero], show: 3)
    fuzzEmbedded("GZ11 plain grid beside a leaf in an HStack", seed: 112, count: 300, .h, show: 3)
    fuzzEmbedded("GZ12 plain grid below a leaf in a VStack", seed: 113, count: 300, .v, show: 3)
}
print("DONE")
