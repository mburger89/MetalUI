// SwiftUI probe: the container algorithms plan task 6 ports — HStack/VStack
// distribution and compression, Spacer, default versus explicit spacing,
// stack/ZStack/overlay/background alignment, and ScrollView axes.
// Evidence for rulings CN-… in docs/superpowers/2026-09-16-containers-decisions.md.
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-stack-algorithms.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. Every figure is read from SwiftUI:
// - `size` is `LayoutSubview.sizeThatFits` of the whole view under test at the
//   stated proposal, taken by the `Probe` layout, which places it at (0, 0);
// - a `leaf` line comes from `Leaf`, a custom `Layout` standing in for a child.
//   It answers `clamp(proposal ?? ideal, min, max)` per axis, prints every
//   DISTINCT proposal it received in order, and its LAST placed rect (SwiftUI
//   places twice per host layout; the dedupe keeps the output readable);
// - an `S` spacing line is size(stack{a; b}) - size(a) - size(b) on the main
//   axis, so no wrapper changes the view kinds whose spacing is measured.
// Every group opens with a control that must DIFFER from the arms under test
// (practices shape 15).
//
// RECORDED 2026-09-16 by the containers design session (plan task 6), macOS
// 27.0 (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1).
// Exit 0. Run twice; the two outputs are byte-identical (`diff` empty). The
// whole stdout follows the reading.
//
// RE-RECORDED 2026-09-16 (revision 4, the design's critic round), same machine
// and toolchain, exit 0, run twice with byte-identical output. Additive: the K,
// Z and R3/R4 arms after A11b, the `Logged` leaf (placement proposals, in
// order) and `runMeasured` (for arms whose answer may be infinite; SwiftUI
// traps placing one). One label changed: X9 said "at 100x50" but has always
// run at nil; its figures are unchanged. Every other line before K0 is byte-
// identical to revision 3. Two revision-3 readings below were WRONG and are
// corrected in place, marked "(corrected, revision 4)": the ZStack placement
// rule and "framing a spacer hides its flexibility".
//
// READING (each claim names its arms):
// - Default spacing is 8 horizontally between every pair measured (S), and 8
//   vertically between non-text views; vertically a Text edge is font-derived
//   (text|text 0, rect|text 4.74, text|rect 8.15, image|image 0, toggle 6).
//   Explicit spacing is used verbatim (S control). An empty conditional adds
//   no spacing (G23). A nested stack's spacing is its content's (hstack|text).
// - Spacer(): minLength nil means 8 (SP1 48, SP6), a constant and not the
//   gap its neighbours would get: VStack{text; Spacer(); text} is 40 at default
//   and at 0 spacing (K1, K1c) where text|text is 0 (K0, K1b). NO default
//   spacing is inserted next to a spacer (SP2 48 = SP1, SP3 40), but EXPLICIT
//   spacing is (SP4 80). A spacer answers 0 on its stack's cross axis (SPB1
//   100x0, SPB2 8x0, SPB5 0x50, X8's overlay proposed 180x0) and both axes
//   outside a linear stack (SPB3 100x50, SPB4 8x8, SPB6).
// - Default spacing beside a spacer is decided PER EDGE, through wrappers
//   (K3 control 48): the spacer's zero spacing survives `.padding(0)` (K3a 40),
//   a frame (K3b 40, K3q 50 = 20+10+20), the overlay primary (K3c 40),
//   `layoutPriority` (K3d 40), `fixedSize` (K3e 40), `aspectRatio` (K3f: 40
//   reported) and a ZStack whose children are ALL spacers (K3g 40, K3l 40). A
//   non-zero padding inset gives THAT edge default spacing again (K3m 64 =
//   20+8+8+8+20; K3n 52 = 20+8+4+0+20 with only the leading edge padded; K3o
//   40, a cross-axis edge; K3p 52 vertically). A ZStack with a non-spacer child
//   (K3j, K3k 56), a nested stack (K3h 56) and a spacer on the OVERLAY side of
//   `.overlay` (K3i 56) get default spacing.
// - The stack's cross-axis mark on a spacer is a DIFFERENT walk: it reaches
//   through `aspectRatio` (K2b, height 20), `fixedSize` (K2c, height 20), a
//   flexible frame (K2d) and the OVERLAY side of `.overlay` (K2e: the overlay
//   spacer answers 10x0 on a 10x10 primary), and NOT through a ZStack (K2a: a
//   ZStack{Spacer()} claims the 50pt cross proposal) or a nested stack (SP18b).
// - Distribution (G, X): at a concrete main proposal, spacing comes off first
//   (G12); children are grouped by layout priority, highest first; each group
//   is offered the remaining length minus the MINIMUM (the answer at main 0)
//   of every lower-priority child (G2 70, G14, X5 92); inside a group,
//   children are served least flexible first (flexibility = answer at main
//   inf minus answer at main 0; stable on ties: G1, G1r, X1, X3, X4), each
//   proposed max(0, remaining / children left) (G13's b gets 0), and the
//   remaining shrinks by what each ANSWERED. The stack reports the sum of the
//   answers plus spacing, overflow included (G9 160, G13 75, X13 160) and
//   shrink-wrap included (G10 40).
// - A Spacer has priority -infinity unless given one (SP8's 96 = (200-8)/2,
//   X5, X6 takes all 100 at priority 1). Framing a spacer hides both its
//   priority and its flexibility (SP19 size 50) — (corrected, revision 4) SP19's
//   frame is FIXED (width 10), so it shows only that a fixed frame is rigid;
//   a FLEXIBLE frame keeps the spacer greedy and hides only its priority (K2d:
//   a is offered 200/3, the stack answers 200). `aspectRatio` and `fixedSize`
//   hide the priority too (K2b, K2c: 200/3). A single-child ZStack passes
//   the -inf priority through (K2a: a is offered (200-8)/2 = 96). Padding
//   hides only the priority (SP20: still flexible, served last among priority
//   0); an overlay hides neither (X8). A greedy non-spacer child takes surplus (G3 180, G4
//   `.frame(maxWidth: .infinity)` 180) and beats a spacer to it (G5, G5b: the
//   spacer keeps 8); two greedy children share (G25 96/96); a stack WITH a
//   spacer compresses its other children (G6 80/8/12 at 100).
// - A single-child HStack/VStack passes its child's priority through (G11 80
//   vs G11c 50).
// - Cross axis: each child is proposed the stack's cross proposal (G16, G20).
//   When that is nil, the stack reports pass-1 answers but PLACES after a
//   second pass at its own cross size (Q1 reports 30x80 and places a at
//   30x20; X10, X11, G7, G17). The main axis is measured at the allocations
//   (Q3 height 30 from a at 80 wide). Nil main proposal: every child at nil
//   (G7 108 = 80 + 8 + 20). Infinite main proposal: every child at inf (G8).
// - Alignment: HStack top/center/bottom place 0/10/20 (A1), VStack
//   leading/center/trailing 0/10/20 (A2). ZStack's nine alignments place the
//   20pt child of a 60x40 stack at each of (0|20|40, 0|10|20) (A3); its size
//   is the union (A4 60x40). ZStack measures every child at its proposal.
//   (corrected, revision 4 — revision 3 read "places at proposal ?? its own
//   size", which A5/A5n/X12/Q2 cannot tell apart from the rule below, and Z1
//   refutes.) ZStack PLACES every child at a proposal equal to its own size
//   B (the size it answered, which its parent placed it at), re-measures each
//   child there, and aligns each within the UNION U of those answers, U's
//   origin at the ZStack's origin: Z1 at 60x40 answers 30x20 and places h
//   (half of its width) at proposal 30x20 -> 15x10 at (2.5, 5) inside the 20x20
//   union, not (7.5, 5) inside 30x20; Z4 places at 60x40, not 100x100; Q2's
//   children at 30x60 answer 30x20 and sit at y 0, not y 20; Z3 at nil.
//   (Each Logged leaf also records earlier placements at (0, 0) on SwiftUI's
//   first passes; the LAST is the displayed geometry, as for every other arm.)
//   overlay/background: the secondary is proposed the primary's size AND
//   PLACED AT THAT PROPOSAL, positioned by its answer and the nine alignments,
//   and may overflow (A6-A9; K5: a half-width leaf's placement proposal is
//   60x40; K5d: an HStack in an overlay is placed at 60x40 and re-solved there,
//   h at 40x40). Several views in one overlay or background are a ZStack with
//   the modifier's alignment POSITIONING a CENTRED ZStack (A10, K5a = K5b,
//   K5e): the implicit ZStack's own alignment is .center whatever the
//   modifier's (K5g .topLeading: h at (2.5, 5) inside the union at (0, 0), not
//   (0, 0); K5h .bottomTrailing: union at (30, 20), h at (32.5, 25); K5c the
//   same with an explicit ZStack). That ZStack then applies the ZStack rule
//   above (K5a: h at (17.5, 15) 15x10, o at (15, 10)). An empty overlay or
//   background leaves the primary alone (A11, A11b). A root's overlay and
//   background content is proposed the ROOT's size, not the host's (R3, R4).
// - ScrollView (SC, SCG2): the content is proposed nil on each scrolling axis
//   and the proposal on the other. The view answers the proposal on each
//   scrolling axis (nil -> the content's answer, inf -> inf) and the CONTENT's
//   answer on a non-scrolling axis (SC2 .vertical 50x100, SC4 500x100). Content
//   smaller than a two-axis viewport is centred (SCG2 both (25, 35); control
//   500x500 at (0, 0)); on a single axis it sits at the leading edge of the
//   scrolling axis (SCG2 vertical (0, 0) in a 50x100 view). Two direct
//   children form a VStack at default spacing, centred, whatever the axes
//   (SC3: b at (10, 38)).
// - The root (R): a hosting view proposes its bounds and CENTRES the root's
//   answer (R1, R2 at (21, 40) in 100x100); a greedy root fills (R control).
// - aspectRatio ANSWERS ITS CHILD'S ANSWER to the ratio-shaped proposal: a
//   fixed 168x95 child reads 168x95 at 500x300 (AR1, proposed 500x281.25) and
//   at nil (AR2); a child that takes the offer reads the ratio size (AR3). In a
//   stack it stays 168x95 (AR4). Single axis: 500 x nil proposes 500x281.25
//   (K4, K4c), nil x 300 proposes 533.33x300 (K4b). INFINITY IS A CONCRETE
//   AXIS, not nil: inf x inf proposes inf x inf (K4d fit, K4h fill at 500 x inf
//   also inf x inf) and 500 x inf proposes 500x281.25 (K4e, K4g) — the
//   two-axis fit/fill comparison with inf in it. A flexible child at inf x inf
//   answers inf x inf (K4f). A negative ratio at 100x100 proposes 100 x -100
//   (K4i: a clamping leaf answers 100x0; K4j a fixed one 30x30).
// - List (K6) is GREEDY and outside nothing: it answers its proposal on each
//   concrete axis and 0 on a nil axis (K6a 100x100, K6b 0x0, K6c 100x0, K6d
//   0x100, K6e inf x inf), against a fixed leaf's 30x30 (K6 control). In a
//   windowless host no row is laid out (K6f prints no leaf line).
// - Not a result: the sparse probe lists (G3's b has one call) are SwiftUI
//   evaluating flexibility lazily and stopping at a flexibility of 0; every
//   allocation above equals a stable sort by flexibility.
//
//   S control explicit: hstack(0) 0 hstack(20) 20 vstack(20) 20
//   S rect|rect: hstack 8  vstack 8
//   S color|color: hstack 8  vstack 8
//   S leaf|leaf: hstack 8  vstack 8
//   S text|text: hstack 8  vstack 0
//   S rect|text: hstack 8  vstack 4.74
//   S text|rect: hstack 8  vstack 8.15
//   S leaf|text: hstack 8  vstack 4.74
//   S image|image: hstack 8  vstack 0
//   S image|text: hstack 8  vstack 0
//   S hstack|rect: hstack 8  vstack 8
//   S hstack|text: hstack 8  vstack 4.74
//   S button|button: hstack 8  vstack 8
//   S text|button: hstack 8  vstack 8.15
//   S paddedText|paddedText: hstack 8  vstack 8
//   S paddedText|rect: hstack 8  vstack 8
//   S toggle|toggle: hstack 8  vstack 6
//   S text|toggle: hstack 8  vstack 8.15
//   S zstack(text)|text: hstack 8 vstack 0 (r 20x20)
//   SP control HStack(0){a20; Spacer(min 30); b20} @nilxnil: size 70x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (50, 0) 20x20 calls 2
//   SP1 HStack(0){a20; Spacer(); b20} @nilxnil: size 48x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (28, 0) 20x20 calls 2
//   SP2 HStack{a20; Spacer(); b20} (default spacing) @nilxnil: size 48x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (28, 0) 20x20 calls 2
//   SP3 HStack{a20; Spacer(minLength: 0); b20} (default spacing) @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   SP4 HStack(spacing: 20){a20; Spacer(minLength: 0); b20} @nilxnil: size 80x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (60, 0) 20x20 calls 2
//   SP5 HStack{text; Spacer(); text} (default spacing) @nilxnil: size 34x16
//   SP5c HStack{text; text} (default spacing, control for SP5) @nilxnil: size 34x16
//   SP6 VStack(0){a20; Spacer(); b20} @nilxnil: size 20x48
//       leaf a: proposed [nilxnil, 20xnil] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, 20xnil] at (0, 28) 20x20 calls 2
//   SP7 VStack{a20; Spacer(minLength: 0); b20} (default spacing) @nilxnil: size 20x40
//       leaf a: proposed [nilxnil, 20xnil] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, 20xnil] at (0, 20) 20x20 calls 2
//   SP8 HStack(0){a20; Spacer(); b20} at 200x50 @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 96x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [172x50] at (180, 0) 20x20 calls 1
//   SP9 HStack(0){Spacer(); a20; Spacer(); Spacer()} at 200x50 (surplus sharing) @200x50: size 200x20
//       leaf a: proposed [176x50] at (60, 0) 20x20 calls 1
//   SP10 HStack(0){Spacer(min 50); a20; Spacer()} at 200x50 (unequal minimums) @200x50: size 200x20
//       leaf a: proposed [142x50] at (90, 0) 20x20 calls 1
//   SP11 HStack(0){Spacer()} at nil @nilxnil: size -1x-1
//   SP12 HStack(0){Spacer()} at 100x50 @100x50: size -1x-1
//   SP13 HStack(0){Spacer(); a20x20} at 100x50 @100x50: size 100x20
//       leaf a: proposed [92x50] at (80, 0) 20x20 calls 1
//   SP14 VStack(0){Spacer(); a20x20} at 100x50 @100x50: size 20x50
//       leaf a: proposed [100x42] at (0, 30) 20x20 calls 1
//   SP15 Spacer() alone (in the Probe layout) at 100x50 @100x50: size -1x-1
//   SP16 Spacer() alone at nil @nilxnil: size -1x-1
//   SP17 ZStack{Spacer()} at 100x50 @100x50: size -1x-1
//   SP18 HStack(0){VStack{Spacer()}; a20} at 100x50 @100x50: size 20x50
//       leaf a: proposed [100x50] at (0, 15) 20x20 calls 1
//   SP19 HStack(0){a20; Spacer().frame(width: 10); b20} at 200x50 (framed spacer) @200x50: size 50x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [170x50] at (30, 0) 20x20 calls 1
//   SP20 HStack(0){a20; Spacer().padding(5); b20} at 200x50 (padded spacer) @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [infx50, 90x50] at (180, 0) 20x20 calls 2
//   G control HStack(0){a 0..80; b 0..80} at 100x50 @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 50x50] at (0, 0) 50x20 calls 3
//       leaf b: proposed [infx50, 0x50, 50x50] at (50, 0) 50x20 calls 3
//   G1 HStack(0){a 20..100; b 60..100} at 100x50 (b less flexible) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 40x50] at (0, 0) 40x20 calls 3
//       leaf b: proposed [infx50, 0x50, 50x50] at (40, 0) 60x20 calls 3
//   G1r HStack(0){b 60..100; a 20..100} at 100x50 (order swapped) @100x50: size 100x20
//       leaf b: proposed [infx50, 0x50, 50x50] at (0, 0) 60x20 calls 3
//       leaf a: proposed [infx50, 0x50, 40x50] at (60, 0) 40x20 calls 3
//   G2 HStack(0){a 0..80 prio 1; b 30..80} at 100x50 (lower group's minimum reserved?) @100x50: size 100x20
//       leaf b: proposed [0x50, 30x50] at (70, 0) 30x20 calls 2
//       leaf a: proposed [70x50] at (0, 0) 70x20 calls 1
//   G2c HStack(0){a 0..80 prio 1; b 0..80} at 100x50 (control for G2) @100x50: size 100x20
//       leaf b: proposed [0x50, 20x50] at (80, 0) 20x20 calls 2
//       leaf a: proposed [100x50] at (0, 0) 80x20 calls 1
//   G3 HStack(0){a fixed 20; b 0..inf ideal 10} at 200x50 (non-spacer expansion) @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 100x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [180x50] at (20, 0) 180x20 calls 1
//   G4 HStack(0){a fixed 20; b fixed 20 .frame(maxWidth: .infinity)} at 200x50 @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 100x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [180x50, 180x20] at (100, 0) 20x20 calls 2
//   G5 HStack(0){a 20; Spacer(); b 0..inf ideal 10} at 200x50 (spacer vs greedy child) @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 96x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [172x50] at (28, 0) 172x20 calls 1
//   G5b HStack(0){b 0..inf ideal 10; Spacer(); a 20} at 200x50 (order swapped) @200x50: size 200x20
//       leaf b: proposed [infx50, 172x50] at (0, 0) 172x20 calls 2
//       leaf a: proposed [infx50, 96x50] at (180, 0) 20x20 calls 2
//   G6 HStack(0){a fixed 80; Spacer(); b 0..80} at 100x50 (overflow WITH a spacer) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 46x50] at (0, 0) 80x20 calls 3
//       leaf b: proposed [12x50] at (88, 0) 12x20 calls 1
//   G6c HStack(0){a fixed 80; b 0..80} at 100x50 (control: no spacer) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 50x50] at (0, 0) 80x20 calls 3
//       leaf b: proposed [20x50] at (80, 0) 20x20 calls 1
//   G7 HStack(0){a 0..80; Spacer(); b 20} at nil @nilxnil: size 108x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 80x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (88, 0) 20x20 calls 2
//   G8 HStack(0){a 0..inf ideal 10; b 20} at inf x inf @infxinf: size infx20
//       leaf a: proposed [infxinf] at (0, 0) infx20 calls 1
//       leaf b: proposed [infxinf] at (inf, 0) 20x20 calls 1
//   G9 HStack(0){a fixed 80; b fixed 80} at 100x50 (overflow, nothing flexible) @100x50: size 160x20
//       leaf a: proposed [infx50, 0x50, 50x50] at (0, 0) 80x20 calls 3
//       leaf b: proposed [20x50] at (80, 0) 80x20 calls 1
//   G10 HStack(0){a 20; b 20} at 300x50 (stack smaller than proposal) @300x50: size 40x20
//       leaf a: proposed [infx50, 0x50, 150x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [280x50] at (20, 0) 20x20 calls 1
//   G11 HStack(0){HStack{a 0..80 prio 1}; b 0..80} at 100x50 (single-child pass-through) @100x50: size 100x20
//       leaf b: proposed [0x50, 20x50] at (80, 0) 20x20 calls 2
//       leaf a: proposed [100x50] at (0, 0) 80x20 calls 1
//   G11c HStack(0){HStack{a 0..80 prio 1; c fixed 0}; b 0..80} at 100x50 (two children: control) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 50x50] at (0, 0) 50x20 calls 3
//       leaf c: proposed [infx50, 0x50] at (50, 10) 0x0 calls 2
//       leaf b: proposed [infx50, 0x50, 50x50] at (50, 0) 50x20 calls 3
//   G12 HStack(10){a 0..80; b 0..80; c 0..80} at 100x50 (spacing comes off first) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 26.67x50] at (0, 0) 26.67x20 calls 3
//       leaf b: proposed [infx50, 0x50, 26.67x50] at (36.67, 0) 26.67x20 calls 3
//       leaf c: proposed [infx50, 0x50, 26.67x50] at (73.33, 0) 26.67x20 calls 3
//   G13 HStack(0){a 30..40; b 0..100 ideal 50; c 45..45} at 60x50 (three flexibilities) @60x50: size 75x20
//       leaf a: proposed [infx50, 0x50, 7.50x50] at (0, 0) 30x20 calls 3
//       leaf b: proposed [infx50, 0x50] at (30, 0) 0x20 calls 2
//       leaf c: proposed [infx50, 0x50, 20x50] at (30, 0) 45x20 calls 3
//   G14 HStack(0){a 0..80 prio -1; b 0..80; c 0..80 prio 1} at 100x50 (three groups) @100x50: size 100x20
//       leaf a: proposed [0x50] at (0, 0) 0x20 calls 1
//       leaf b: proposed [0x50, 20x50] at (0, 0) 20x20 calls 2
//       leaf c: proposed [100x50] at (20, 0) 80x20 calls 1
//   G15 VStack(0){a 0..80; b 20..80} at 50x100 (vertical distribution) @50x100: size 20x100
//       leaf a: proposed [50xinf, 50x0, 50x50] at (0, 0) 20x50 calls 3
//       leaf b: proposed [50xinf, 50x0, 50x50] at (0, 50) 20x50 calls 3
//   G16 VStack(0){a width 0..inf ideal 10; b fixed 30} at 100x100 (cross proposal) @100x100: size 100x40
//       leaf a: proposed [100xinf, 100x0, 100x50] at (0, 0) 100x20 calls 3
//       leaf b: proposed [100x80] at (35, 20) 30x20 calls 1
//   G17 VStack(0){a width 0..inf ideal 10; b fixed 30} at nil @nilxnil: size 30x40
//       leaf a: proposed [nilxnil, 30xnil] at (0, 0) 30x20 calls 2
//       leaf b: proposed [nilxnil, 30xnil] at (0, 20) 30x20 calls 2
//   G18 HStack(0){Text long; Text short} at 80xnil (text compression) @80xnil: size 80x48
//   G19 HStack(0){a 20; Spacer(); b 20} at nil x 50 @nilx50: size 48x20
//       leaf a: proposed [nilx50] at (0, 0) 20x20 calls 1
//       leaf b: proposed [nilx50] at (28, 0) 20x20 calls 1
//   G20 HStack(0){a height 0..inf ideal 10; b 20x30} at 100x80 (cross axis) @100x80: size 40x80
//       leaf a: proposed [infx80, 0x80, 50x80] at (0, 0) 20x80 calls 3
//       leaf b: proposed [80x80] at (20, 25) 20x30 calls 1
//   G21 HStack(0){a height 0..inf ideal 10; b 20x30} at 100 x nil @100xnil: size 40x30
//       leaf a: proposed [infxnil, 0xnil, 50xnil, infx30, 0x30, 50x30] at (0, 0) 20x30 calls 6
//       leaf b: proposed [80xnil, 80x30] at (20, 0) 20x30 calls 2
//   G22 HStack(0){} empty at 100x50 @100x50: size -1x-1
//   G23 HStack{a20; if false; b20} (default spacing; empty conditional) @nilxnil: size 48x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (28, 0) 20x20 calls 2
//   G24 HStack(0){a 0..inf ideal 10; b 0..inf ideal 10 prio 1} at 200x50 @200x50: size 200x20
//       leaf a: proposed [0x50] at (0, 0) 0x20 calls 1
//       leaf b: proposed [200x50] at (0, 0) 200x20 calls 1
//   G25 HStack(0){a 0..inf ideal 10; Spacer(); b 0..inf ideal 10} at 200x50 (two greedy + spacer) @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 96x50] at (0, 0) 96x20 calls 3
//       leaf b: proposed [infx50, 0x50, 96x50] at (104, 0) 96x20 calls 3
//   A1 HStack(0, alignment: .top){a 20x10; b 20x30} @nilxnil: size 40x30
//       leaf a: proposed [nilxnil, nilx30] at (0, 0) 20x10 calls 2
//       leaf b: proposed [nilxnil, nilx30] at (20, 0) 20x30 calls 2
//   A1 HStack(0, alignment: .center){a 20x10; b 20x30} @nilxnil: size 40x30
//       leaf a: proposed [nilxnil, nilx30] at (0, 10) 20x10 calls 2
//       leaf b: proposed [nilxnil, nilx30] at (20, 0) 20x30 calls 2
//   A1 HStack(0, alignment: .bottom){a 20x10; b 20x30} @nilxnil: size 40x30
//       leaf a: proposed [nilxnil, nilx30] at (0, 20) 20x10 calls 2
//       leaf b: proposed [nilxnil, nilx30] at (20, 0) 20x30 calls 2
//   A2 VStack(0, alignment: .leading){a 10x20; b 30x20} @nilxnil: size 30x40
//       leaf a: proposed [nilxnil, 30xnil] at (0, 0) 10x20 calls 2
//       leaf b: proposed [nilxnil, 30xnil] at (0, 20) 30x20 calls 2
//   A2 VStack(0, alignment: .center){a 10x20; b 30x20} @nilxnil: size 30x40
//       leaf a: proposed [nilxnil, 30xnil] at (10, 0) 10x20 calls 2
//       leaf b: proposed [nilxnil, 30xnil] at (0, 20) 30x20 calls 2
//   A2 VStack(0, alignment: .trailing){a 10x20; b 30x20} @nilxnil: size 30x40
//       leaf a: proposed [nilxnil, 30xnil] at (20, 0) 10x20 calls 2
//       leaf b: proposed [nilxnil, 30xnil] at (0, 20) 30x20 calls 2
//   A3 ZStack(.topLeading){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (0, 0) 20x20 calls 2
//   A3 ZStack(.top){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (20, 0) 20x20 calls 2
//   A3 ZStack(.topTrailing){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (40, 0) 20x20 calls 2
//   A3 ZStack(.leading){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (0, 10) 20x20 calls 2
//   A3 ZStack(.center){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (20, 10) 20x20 calls 2
//   A3 ZStack(.trailing){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (40, 10) 20x20 calls 2
//   A3 ZStack(.bottomLeading){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (0, 20) 20x20 calls 2
//   A3 ZStack(.bottom){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (20, 20) 20x20 calls 2
//   A3 ZStack(.bottomTrailing){big 60x40; small 20x20} at nil @nilxnil: size 60x40
//       leaf big: proposed [nilxnil, 60x40] at (0, 0) 60x40 calls 2
//       leaf small: proposed [nilxnil, 60x40] at (40, 20) 20x20 calls 2
//   A4 ZStack(.topLeading){a 60x20; b 20x40} at nil (size is the union) @nilxnil: size 60x40
//       leaf a: proposed [nilxnil, 60x40] at (0, 0) 60x20 calls 2
//       leaf b: proposed [nilxnil, 60x40] at (0, 0) 20x40 calls 2
//   A5 ZStack{a 0..inf ideal 10 (w and h); b 20x20} at 100x80 @100x80: size 100x80
//       leaf a: proposed [100x80] at (0, 0) 100x80 calls 1
//       leaf b: proposed [100x80] at (40, 30) 20x20 calls 1
//   A5n same ZStack at nil @nilxnil: size 20x20
//       leaf a: proposed [nilxnil, 20x20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, 20x20] at (0, 0) 20x20 calls 2
//   A6 primary 60x40 .overlay(alignment: .topLeading){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (0, 0) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .top){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (20, 0) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .topTrailing){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (40, 0) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .leading){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (0, 10) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .center){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (20, 10) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .trailing){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (40, 10) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .bottomLeading){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (0, 20) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .bottom){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (20, 20) 20x20 calls 1
//   A6 primary 60x40 .overlay(alignment: .bottomTrailing){o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (40, 20) 20x20 calls 1
//   A7 primary 60x40 .overlay(.center){o 0..inf ideal 10} (overlay proposal) @300x300: size 60x40
//       leaf primary: proposed [300x300] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (0, 0) 60x40 calls 1
//   A8 primary 60x40 .overlay(.topLeading){o 100x100} (bigger overlay) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o: proposed [60x40] at (0, 0) 100x100 calls 1
//   A9 primary 60x40 .background(alignment: .topLeading){bg 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf bg: proposed [60x40] at (0, 0) 20x20 calls 1
//   A9 primary 60x40 .background(alignment: .center){bg 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf bg: proposed [60x40] at (20, 10) 20x20 calls 1
//   A9 primary 60x40 .background(alignment: .bottomTrailing){bg 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf bg: proposed [60x40] at (40, 20) 20x20 calls 1
//   A10 primary 60x40 .overlay{ o1 20x20; o2 30x10 } (multi-view overlay) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf o1: proposed [60x40, 30x20] at (20, 10) 20x20 calls 2
//       leaf o2: proposed [60x40, 30x20] at (15, 15) 30x10 calls 2
//   SC control content 0..inf ideal 50 x 0..inf ideal 300 alone at 100x100 @100x100: size 100x100
//       leaf c: proposed [100x100] at (0, 0) 100x100 calls 1
//   SC1 ScrollView(.vertical){c flexible ideal 50x300} @nilxnil: size 50x300
//       leaf c: proposed [nilxnil, 50xnil] at (0, 0) 50x300 calls 2
//   SC1 ScrollView(.vertical){c flexible ideal 50x300} @100x100: size 100x100
//       leaf c: proposed [100xnil] at (0, 0) 100x300 calls 1
//   SC1 ScrollView(.vertical){c flexible ideal 50x300} @infxinf: size infxinf
//       leaf c: proposed [infxnil] at (0, 0) infx300 calls 1
//   SC2 ScrollView(.vertical){c fixed 50x30} at 100x100 (content smaller than viewport) @100x100: size 50x100
//       leaf c: proposed [100xnil, 50xnil] at (0, 0) 50x30 calls 2
//   SC3 ScrollView(.vertical){a 50x30; b 30x20} at 200x200 (two direct children) @200x200: size 50x200
//       leaf a: proposed [200xnil, 50xnil] at (0, 0) 50x30 calls 2
//       leaf b: proposed [200xnil, 50xnil] at (10, 38) 30x20 calls 2
//   SC4 ScrollView(.vertical){c fixed 500x500} at 100x100 (content larger) @100x100: size 500x100
//       leaf c: proposed [100xnil, 500xnil] at (0, 0) 500x500 calls 2
//   SC1 ScrollView(.horizontal){c flexible ideal 50x300} @nilxnil: size 50x300
//       leaf c: proposed [nilxnil, nilx300] at (0, 0) 50x300 calls 2
//   SC1 ScrollView(.horizontal){c flexible ideal 50x300} @100x100: size 100x100
//       leaf c: proposed [nilx100] at (0, 0) 50x100 calls 1
//   SC1 ScrollView(.horizontal){c flexible ideal 50x300} @infxinf: size infxinf
//       leaf c: proposed [nilxinf] at (0, 0) 50xinf calls 1
//   SC2 ScrollView(.horizontal){c fixed 50x30} at 100x100 (content smaller than viewport) @100x100: size 100x30
//       leaf c: proposed [nilx100, nilx30] at (0, 0) 50x30 calls 2
//   SC3 ScrollView(.horizontal){a 50x30; b 30x20} at 200x200 (two direct children) @200x200: size 200x58
//       leaf a: proposed [nilxinf, nilx0, nilx96, nilx25, 50xinf, 50x0, 50x25] at (0, 0) 50x30 calls 7
//       leaf b: proposed [nilx162, nilx20, 50x20] at (10, 38) 30x20 calls 3
//   SC4 ScrollView(.horizontal){c fixed 500x500} at 100x100 (content larger) @100x100: size 100x500
//       leaf c: proposed [nilx100, nilx500] at (0, 0) 500x500 calls 2
//   SC1 ScrollView(.both){c flexible ideal 50x300} @nilxnil: size 50x300
//       leaf c: proposed [nilxnil] at (0, 0) 50x300 calls 1
//   SC1 ScrollView(.both){c flexible ideal 50x300} @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 50x300 calls 1
//   SC1 ScrollView(.both){c flexible ideal 50x300} @infxinf: size infxinf
//       leaf c: proposed [nilxnil] at (0, 0) 50x300 calls 1
//   SC2 ScrollView(.both){c fixed 50x30} at 100x100 (content smaller than viewport) @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 50x30 calls 1
//   SC3 ScrollView(.both){a 50x30; b 30x20} at 200x200 (two direct children) @200x200: size 200x200
//       leaf a: proposed [nilxnil, 50xnil] at (0, 0) 50x30 calls 2
//       leaf b: proposed [nilxnil, 50xnil] at (10, 38) 30x20 calls 2
//   SC4 ScrollView(.both){c fixed 500x500} at 100x100 (content larger) @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 500x500 calls 1
//   X1 HStack(0){a 0..80; b fixed 80} at 100x50 @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 20x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [infx50, 0x50, 50x50] at (20, 0) 80x20 calls 3
//   X2 HStack(0){a 0..inf ideal 10; b fixed 20} at 200x50 @200x50: size 200x20
//       leaf a: proposed [infx50, 180x50] at (0, 0) 180x20 calls 2
//       leaf b: proposed [infx50, 100x50] at (180, 0) 20x20 calls 2
//   X3 HStack(0){a 0..80; b fixed 30; c fixed 30} at 100x50 @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50, 40x50] at (0, 0) 40x20 calls 3
//       leaf b: proposed [infx50, 0x50, 33.33x50] at (40, 0) 30x20 calls 3
//       leaf c: proposed [infx50, 0x50, 35x50] at (70, 0) 30x20 calls 3
//   X4 HStack(0){a 0..100 ideal 50; b 40..60 ideal 50} at 70x50 @70x50: size 70x20
//       leaf a: proposed [infx50, 0x50, 30x50] at (0, 0) 30x20 calls 3
//       leaf b: proposed [infx50, 0x50, 35x50] at (30, 0) 40x20 calls 3
//   X5 HStack(0){a 0..80 prio 1; Spacer(); b 0..80} at 100x50 (spacer below priority 0) @100x50: size 100x20
//       leaf b: proposed [0x50, 12x50] at (88, 0) 12x20 calls 2
//       leaf a: proposed [92x50] at (0, 0) 80x20 calls 1
//   X6 HStack(0){a 0..80; Spacer().layoutPriority(1); b 0..80} at 100x50 (spacer given priority 1) @100x50: size 100x20
//       leaf a: proposed [infx50, 0x50] at (0, 0) 0x20 calls 2
//       leaf b: proposed [infx50, 0x50] at (100, 0) 0x20 calls 2
//   X7 HStack(0){a 0..inf ideal 10; b 0..inf ideal 10 .layoutPriority(-1)} at 200x50 @200x50: size 200x20
//       leaf b: proposed [0x50] at (200, 0) 0x20 calls 1
//       leaf a: proposed [200x50] at (0, 0) 200x20 calls 1
//   X8 HStack(0){Spacer().overlay{o 20x20}; a 20} at 200x50 (overlaid spacer) @200x50: size 200x20
//       leaf a: proposed [192x50] at (180, 0) 20x20 calls 1
//       leaf o: proposed [180x0] at (80, 0) 20x20 calls 1
//   X9 HStack(0){a 20; Spacer()} at nil (label corrected 2026-09-16: it never ran at 100x50) @nilxnil: size 28x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//   X10 HStack(0){a height 0..inf ideal 10; b 20x30} at nil (cross re-proposal) @nilxnil: size 40x30
//       leaf a: proposed [nilxnil, nilx30] at (0, 0) 20x30 calls 2
//       leaf b: proposed [nilxnil, nilx30] at (20, 0) 20x30 calls 2
//   X11 VStack(0){a 0..inf ideal 10 wide; b 30} at nil x 100 @nilx100: size 30x40
//       leaf a: proposed [nilxinf, nilx0, nilx50, 30xinf, 30x0, 30x50] at (0, 0) 30x20 calls 6
//       leaf b: proposed [nilx80, 30x80] at (0, 20) 30x20 calls 2
//   X12 ZStack{a 0..inf ideal 10; b 20x20} at 100 x nil @100xnil: size 100x20
//       leaf a: proposed [100xnil, 100x20] at (0, 0) 100x20 calls 2
//       leaf b: proposed [100xnil, 100x20] at (40, 0) 20x20 calls 2
//   X13 HStack(0){a fixed 80; b fixed 80} at nil x 50 (overflow check at nil) @nilx50: size 160x20
//       leaf a: proposed [nilx50] at (0, 0) 80x20 calls 1
//       leaf b: proposed [nilx50] at (80, 0) 80x20 calls 1
//   SP11b HStack(0){Spacer()} at nil @nilxnil: size -1x-1
//   SP12b HStack(0){Spacer()} at 100x50 @100x50: size -1x-1
//   SP15b Spacer() alone at 100x50 @100x50: size -1x-1
//   SP16b Spacer() alone at nil @nilxnil: size -1x-1
//   SP16c Spacer(minLength: 12) alone at nil @nilxnil: size -1x-1
//   SP17b ZStack{Spacer()} at 100x50 @100x50: size -1x-1
//   SP18b HStack(0){VStack{Spacer()}; a20} at 100x50 @100x50: size 20x50
//       leaf a: proposed [100x50] at (0, 15) 20x20 calls 1
//   SP21 VStack(0){HStack(0){Spacer()}; a20} at 100x50 @100x50: size 100x20
//       leaf a: proposed [100x50] at (40, 0) 20x20 calls 1
//   SP22 HStack(0){a20; Spacer()} at 100 x nil (spacer cross at nil) @100xnil: size 100x20
//       leaf a: proposed [92xnil, 92x20] at (0, 0) 20x20 calls 2
//   G22b HStack(0){} empty at 100x50 @100x50: size -1x-1
//   G22c HStack{} empty at nil @nilxnil: size -1x-1
//   SCG ScrollView(.vertical){c 50x30}.frame(100x100) content frame in the scroll view @100x100: size 100x100
//       leaf c: proposed [100xnil, 50xnil] at (0, 0) 50x30 calls 2
//       geometry c: (25, 0) 50x30
//   SCG ScrollView(.horizontal){c 50x30}.frame(100x100) content frame in the scroll view @100x100: size 100x100
//       leaf c: proposed [nilx100, nilx30] at (0, 0) 50x30 calls 2
//       geometry c: (0, 35) 50x30
//   SCG ScrollView(.both){c 50x30}.frame(100x100) content frame in the scroll view @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 50x30 calls 1
//       geometry c: (25, 35) 50x30
//   SCG2 ScrollView(.vertical){c 50x30} coordinate space on the scroll view, at 100x100 @100x100: size 50x100
//       leaf c: proposed [100xnil, 50xnil] at (0, 0) 50x30 calls 2
//       geometry c: (0, 0) 50x30
//       geometry sv: (0, 0) 50x100
//   SCG2 ScrollView(.horizontal){c 50x30} coordinate space on the scroll view, at 100x100 @100x100: size 100x30
//       leaf c: proposed [nilx100, nilx30] at (0, 0) 50x30 calls 2
//       geometry c: (0, 0) 50x30
//       geometry sv: (0, 0) 100x30
//   SCG2 ScrollView(.both){c 50x30} coordinate space on the scroll view, at 100x100 @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 50x30 calls 1
//       geometry c: (25, 35) 50x30
//       geometry sv: (0, 0) 100x100
//   SCG2 control ScrollView(.both){c 500x500} at 100x100 @100x100: size 100x100
//       leaf c: proposed [nilxnil] at (0, 0) 500x500 calls 1
//       geometry c: (0, 0) 500x500
//   SPB control fixed 30x10 .background{bg} @100x50: size 30x10
//       leaf a: proposed [100x50] at (0, 0) 30x10 calls 1
//       leaf bg: proposed [30x10] at (15, 5) 0x0 calls 1
//   SPB1 HStack(0){Spacer()} .background{bg} at 100x50 @100x50: size 100x0
//       leaf bg: proposed [100x0] at (50, 0) 0x0 calls 1
//   SPB2 HStack(0){Spacer()} .background{bg} at nil @nilxnil: size 8x0
//       leaf bg: proposed [8x0] at (4, 0) 0x0 calls 1
//   SPB3 Spacer() .background{bg} at 100x50 (outside a stack) @100x50: size 100x50
//       leaf bg: proposed [100x50] at (50, 25) 0x0 calls 1
//   SPB4 Spacer() .background{bg} at nil @nilxnil: size 8x8
//       leaf bg: proposed [8x8] at (4, 4) 0x0 calls 1
//   SPB5 VStack(0){Spacer()} .background{bg} at 100x50 @100x50: size 0x50
//       leaf bg: proposed [0x50] at (0, 25) 0x0 calls 1
//   SPB6 ZStack{Spacer()} .background{bg} at 100x50 @100x50: size 100x50
//       leaf bg: proposed [100x50] at (50, 25) 0x0 calls 1
//   SPB7 HStack(0){} .background{bg} at 100x50 (empty stack) @100x50: size 0x0
//       leaf bg: proposed [0x0] at (0, 0) 0x0 calls 1
//   R control greedy Leaf 0..inf root in a 100x100 host: a proposed [100x100] at (0, 0) 100x100
//   R1 HStack(0){a 58x20} root in a 100x100 host: a proposed [100x100] at (21, 40) 58x20
//   R2 fixed a 58x20 root in a 100x100 host: a proposed [100x100] at (21, 40) 58x20
//   Q1 VStack(0){a area 600 ideal 10; b 30x20} at nil @nilxnil: size 30x80
//       leaf a: proposed [nilxnil, 30xnil] at (0, 0) 30x20 calls 2
//       leaf b: proposed [nilxnil, 30xnil] at (0, 20) 30x20 calls 2
//   Q1c VStack(0){a area 600 ideal 10; b 30x20} at 30 x nil (control: width given) @30xnil: size 30x40
//       leaf a: proposed [30xnil] at (0, 0) 30x20 calls 1
//       leaf b: proposed [30xnil] at (0, 20) 30x20 calls 1
//   Q2 ZStack{a area 600 ideal 10; b 30x20} at nil @nilxnil: size 30x60
//       leaf a: proposed [nilxnil, 30x60] at (0, 0) 30x20 calls 2
//       leaf b: proposed [nilxnil, 30x60] at (0, 0) 30x20 calls 2
//   Q3 HStack(0){a area 600 ideal 10; b 20x30} at 100x50 (measured at allocations?) @100x50: size 100x30
//       leaf a: proposed [infx50, 0x50, 80x50] at (0, 11.25) 80x7.50 calls 3
//       leaf b: proposed [infx50, 0x50, 50x50] at (80, 0) 20x30 calls 3
//   AR control fixed 168x95 alone at 500x300 @500x300: size 168x95
//       leaf c: proposed [500x300] at (0, 0) 168x95 calls 1
//   AR1 fixed 168x95 .aspectRatio(16/9, .fit) at 500x300 @500x300: size 168x95
//       leaf c: proposed [500x281.25] at (0, 0) 168x95 calls 1
//   AR2 fixed 168x95 .aspectRatio(16/9, .fit) at nil @nilxnil: size 168x95
//       leaf c: proposed [nilxnil] at (0, 0) 168x95 calls 1
//   AR3 flexible c .aspectRatio(16/9, .fit) at 500x300 (a child that takes the offer) @500x300: size 500x281.25
//       leaf c: proposed [500x281.25] at (0, 0) 500x281.25 calls 1
//   AR4 HStack(12){a 168x64; fixed 168x95 .aspectRatio(16/9); b 168x64} at 856x300 @856x300: size 528x95
//       leaf a: proposed [infx300, 0x300, 277.33x300] at (0, 15.50) 168x64 calls 3
//       leaf c: proposed [533.33x300, 0x0, 332x186.75] at (180, 0) 168x95 calls 3
//       leaf b: proposed [496x300] at (360, 15.50) 168x64 calls 1
//   A11 primary 60x40 .overlay{ if false { o 20x20 } } (empty overlay) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//   A11b primary 60x40 .background{ if false { bg 20x20 } } (empty background) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//   K0 control VStack(0){text; text} @nilxnil: size 13x32
//   K1b VStack{text; text} (default spacing) @nilxnil: size 13x32
//   K1 VStack{text; Spacer(); text} (default spacing) @nilxnil: size 13x40
//   K1c VStack(0){text; Spacer(); text} @nilxnil: size 13x40
//   K2 control HStack(0){a20; Spacer(); b20} at 200x50 @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 96x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [172x50] at (180, 0) 20x20 calls 1
//   K2a HStack(0){a20; ZStack{Spacer()}; b20} at 200x50 @200x50: size 200x50
//       leaf a: proposed [infx50, 0x50, 96x50] at (0, 15) 20x20 calls 3
//       leaf b: proposed [172x50] at (180, 15) 20x20 calls 1
//   K2b HStack(0){a20; Spacer().aspectRatio(1, .fit); b20} at 200x50 @200x50: size 90x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [infx50, 0x50, 90x50] at (70, 0) 20x20 calls 3
//   K2c HStack(0){a20; Spacer().fixedSize(); b20} at 200x50 @200x50: size 48x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [172x50] at (28, 0) 20x20 calls 1
//   K2d HStack(0){a20; Spacer().frame(maxWidth: .infinity); b20} at 200x50 @200x50: size 200x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf b: proposed [infx50, 90x50] at (180, 0) 20x20 calls 2
//   K2e HStack(0){a20; p 10x10 .overlay{Spacer() .background{bg}}; b20} at 200x50 (overlay-side spacer) @200x50: size 50x20
//       leaf a: proposed [infx50, 0x50, 66.67x50] at (0, 0) 20x20 calls 3
//       leaf p: proposed [infx50, 0x50, 90x50] at (20, 5) 10x10 calls 3
//       leaf b: proposed [170x50] at (30, 0) 20x20 calls 1
//       leaf bg: proposed [10x0] at (25, 10) 0x0 calls 1
//   K3 control HStack{a20; b20} (default spacing) @nilxnil: size 48x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (28, 0) 20x20 calls 2
//   K3a HStack{a20; Spacer(minLength: 0).padding(0); b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3b HStack{a20; Spacer(minLength: 0).frame(width: 0); b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3c HStack{a20; Spacer(minLength: 0).overlay{c 0x0}; b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//       leaf c: proposed [0x0] at (20, 10) 0x0 calls 1
//   K3d HStack{a20; Spacer(minLength: 0).layoutPriority(1); b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3e HStack{a20; Spacer(minLength: 0).fixedSize(); b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3f HStack{a20; Spacer(minLength: 0).aspectRatio(1, .fit); b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (40, 0) 20x20 calls 2
//   K3g HStack{a20; ZStack{Spacer(minLength: 0)}; b20} @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3h HStack{a20; VStack{Spacer(minLength: 0)}; b20} @nilxnil: size 56x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (36, 0) 20x20 calls 2
//   K3i HStack{a20; c 0x0 .overlay{Spacer(minLength: 0)}; b20} (overlay-side spacer) @nilxnil: size 56x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf c: proposed [nilxnil, nilx20] at (28, 10) 0x0 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (36, 0) 20x20 calls 2
//   K3j HStack{a20; ZStack{Spacer(minLength: 0); c 0x0}; b20} (two-child ZStack, spacer first) @nilxnil: size 56x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf c: proposed [nilxnil, 0x0, nilx20] at (28, 10) 0x0 calls 3
//       leaf b: proposed [nilxnil, nilx20] at (36, 0) 20x20 calls 2
//   K3k HStack{a20; ZStack{c 0x0; Spacer(minLength: 0)}; b20} (two-child ZStack, spacer last) @nilxnil: size 56x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf c: proposed [nilxnil, 0x0, nilx20] at (28, 10) 0x0 calls 3
//       leaf b: proposed [nilxnil, nilx20] at (36, 0) 20x20 calls 2
//   K3l HStack{a20; ZStack{Spacer(minLength: 0); Spacer(minLength: 0)}; b20} (two spacers) @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3m HStack{a20; Spacer(minLength: 0).padding(4); b20} (non-zero padding) @nilxnil: size 64x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (44, 0) 20x20 calls 2
//   K3n HStack{a20; Spacer(minLength: 0).padding(.leading, 4); b20} (one edge padded) @nilxnil: size 52x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (32, 0) 20x20 calls 2
//   K3o HStack{a20; Spacer(minLength: 0).padding(.top, 4); b20} (a cross-axis edge padded) @nilxnil: size 40x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (20, 0) 20x20 calls 2
//   K3p VStack{a20; Spacer(minLength: 0).padding(.top, 4); b20} (one edge padded, vertical) @nilxnil: size 20x52
//       leaf a: proposed [nilxnil, 20xnil] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, 20xnil] at (0, 32) 20x20 calls 2
//   K3q HStack{a20; Spacer(minLength: 0).frame(width: 10).padding(0); b20} (frame then zero padding) @nilxnil: size 50x20
//       leaf a: proposed [nilxnil, nilx20] at (0, 0) 20x20 calls 2
//       leaf b: proposed [nilxnil, nilx20] at (30, 0) 20x20 calls 2
//   K4 fixed 168x95 .aspectRatio(16/9, .fit) at 500 x nil @500xnil: size 168x95
//       leaf c: proposed [500x281.25] at (0, 0) 168x95 calls 1
//   K4b fixed 168x95 .aspectRatio(16/9, .fit) at nil x 300 @nilx300: size 168x95
//       leaf c: proposed [533.33x300] at (0, 0) 168x95 calls 1
//   K4c flexible c .aspectRatio(16/9, .fit) at 500 x nil @500xnil: size 500x281.25
//       leaf c: proposed [500x281.25] at (0, 0) 500x281.25 calls 1
//   K4d fixed 168x95 .aspectRatio(16/9, .fit) at inf x inf @infxinf (measured only): size 168x95
//       leaf c: proposed [infxinf, 0x0]
//   K4e fixed 168x95 .aspectRatio(16/9, .fit) at 500 x inf @500xinf (measured only): size 168x95
//       leaf c: proposed [500x281.25, 0x0]
//   K4f flexible c .aspectRatio(16/9, .fit) at inf x inf @infxinf (measured only): size infxinf
//       leaf c: proposed [infxinf, 0x0]
//   K4g flexible c .aspectRatio(16/9, .fit) at 500 x inf @500xinf (measured only): size 500x281.25
//       leaf c: proposed [500x281.25, 0x0]
//   K4h fixed 168x95 .aspectRatio(16/9, .fill) at 500 x inf @500xinf (measured only): size 168x95
//       leaf c: proposed [infxinf, 0x0]
//   K4i flexible c .aspectRatio(-1, .fit) at 100x100 (negative ratio) @100x100: size 100x0
//       leaf c: proposed [100x-100] at (0, 0) 100x0 calls 1
//   K4j fixed 30x30 .aspectRatio(-1, .fit) at 100x100 (negative ratio) @100x100: size 30x30
//       leaf c: proposed [100x-100] at (0, 0) 30x30 calls 1
//   K5 control primary 60x40 .overlay{half h} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40] at (15, 15) 30x10 calls 1
//           placements, in order: [60x40 -> (0, 0) 30x10; 60x40 -> (15, 15) 30x10]
//   K5a primary 60x40 .overlay{half h; o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (17.50, 15) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (17.50, 15) 15x10]
//       leaf o: proposed [60x40, 30x20] at (15, 10) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20; 30x20 -> (15, 10) 20x20]
//   K5b primary 60x40 .overlay{ZStack{half h; o 20x20}} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (17.50, 15) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (17.50, 15) 15x10]
//       leaf o: proposed [60x40, 30x20] at (15, 10) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20; 30x20 -> (15, 10) 20x20]
//   K5c primary 60x40 .overlay(alignment: .topLeading){ZStack{half h; o 20x20}} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (2.50, 5) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (2.50, 5) 15x10]
//       leaf o: proposed [60x40, 30x20] at (0, 0) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20]
//   K5d primary 60x40 .overlay{HStack(0){half h; o 20x20}} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [infx40, 40x40] at (10, 15) 20x10 calls 2
//           placements, in order: [40x40 -> (0, 0) 20x10; 40x40 -> (10, 15) 20x10]
//       leaf o: proposed [infx40, 30x40] at (30, 10) 20x20 calls 2
//           placements, in order: [30x40 -> (0, 0) 20x20; 30x40 -> (30, 10) 20x20]
//   K5e primary 60x40 .background{half h; o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (17.50, 15) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (17.50, 15) 15x10]
//       leaf o: proposed [60x40, 30x20] at (15, 10) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20; 30x20 -> (15, 10) 20x20]
//   K5f primary 60x40 .overlay{half h .frame(width: 30)} (content answer = its proposal width) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [30x40] at (22.50, 15) 15x10 calls 1
//           placements, in order: [30x40 -> (0, 0) 15x10; 30x40 -> (22.50, 15) 15x10]
//   K5g primary 60x40 .overlay(alignment: .topLeading){half h; o 20x20} (implicit ZStack's own alignment?) @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (2.50, 5) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (2.50, 5) 15x10]
//       leaf o: proposed [60x40, 30x20] at (0, 0) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20]
//   K5h primary 60x40 .background(alignment: .bottomTrailing){half h; o 20x20} @nilxnil: size 60x40
//       leaf primary: proposed [nilxnil] at (0, 0) 60x40 calls 1
//       leaf h: proposed [60x40, 30x20] at (32.50, 25) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (32.50, 25) 15x10]
//       leaf o: proposed [60x40, 30x20] at (30, 20) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20; 30x20 -> (30, 20) 20x20]
//   Z1 ZStack{half h; o 20x20} at 60x40 (no overlay) @60x40: size 30x20
//       leaf h: proposed [60x40, 30x20] at (2.50, 5) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10; 30x20 -> (2.50, 5) 15x10]
//       leaf o: proposed [60x40, 30x20] at (0, 0) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20]
//   Z2 ZStack(.topLeading){half h; o 20x20} at 60x40 @60x40: size 30x20
//       leaf h: proposed [60x40, 30x20] at (0, 0) 15x10 calls 2
//           placements, in order: [60x40 -> (0, 0) 30x10; 30x20 -> (0, 0) 15x10]
//       leaf o: proposed [60x40, 30x20] at (0, 0) 20x20 calls 2
//           placements, in order: [60x40 -> (0, 0) 20x20; 30x20 -> (0, 0) 20x20]
//   Z3 ZStack{half h; o 20x20} at nil @nilxnil: size 20x20
//       leaf h: proposed [nilxnil, 20x20] at (5, 5) 10x10 calls 2
//           placements, in order: [nilxnil -> (0, 0) 20x10; 20x20 -> (0, 0) 10x10; 20x20 -> (5, 5) 10x10]
//       leaf o: proposed [nilxnil, 20x20] at (0, 0) 20x20 calls 2
//           placements, in order: [nilxnil -> (0, 0) 20x20; 20x20 -> (0, 0) 20x20]
//   Z4 ZStack{half h; o 60x40} at 100x100 (a child as big as the ZStack) @100x100: size 60x40
//       leaf h: proposed [100x100, 60x40] at (15, 15) 30x10 calls 2
//           placements, in order: [100x100 -> (0, 0) 50x10; 60x40 -> (0, 0) 30x10; 60x40 -> (15, 15) 30x10]
//       leaf o: proposed [100x100, 60x40] at (0, 0) 60x40 calls 2
//           placements, in order: [100x100 -> (0, 0) 60x40; 60x40 -> (0, 0) 60x40]
//   K6 control fixed 30x30 at 100x100 @100x100: size 30x30
//       leaf c: proposed [100x100] at (0, 0) 30x30 calls 1
//   K6a List{Text} at 100x100 @100x100: size 100x100
//   K6b List{Text} at nil @nilxnil: size 0x0
//   K6c List{Text} at 100 x nil @100xnil: size 100x0
//   K6d List{Text} at nil x 100 @nilx100: size 0x100
//   K6e List{Text} at inf x inf @infxinf (measured only): size infxinf
//   K6f List{leaf l 30x30} at 100x100 (is a row laid out?) @100x100: size 100x100
//   R3 fixed r 58x20 .overlay{greedy a} root in a 100x100 host: r at (21, 40) 58x20; a proposed [58x20] at (21, 40) 58x20
//   R4 fixed r 58x20 .background{greedy a} root in a 100x100 host: r at (21, 40) 58x20; a proposed [58x20] at (21, 40) 58x20
//   DONE

import AppKit
import SwiftUI

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ p: ProposedViewSize) -> String { "\(d(p.width))x\(d(p.height))" }

nonisolated(unsafe) var proposalsSeen: [String: [String]] = [:]
nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero

struct Probe: Layout {
    let label: String
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        lastSize = size
        return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Re-read here too: SwiftUI does not always call this layout's own
        // sizeThatFits (an earlier build printed the previous arm's size).
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

nonisolated(unsafe) var calls: [String: Int] = [:]
nonisolated(unsafe) var geometry: [String: CGRect] = [:]

struct Leaf: Layout {
    let name: String
    var minW: CGFloat = 0, idealW: CGFloat, maxW: CGFloat
    var minH: CGFloat = 0, idealH: CGFloat, maxH: CGFloat
    func answer(_ p: ProposedViewSize) -> CGSize {
        CGSize(width: min(max(p.width ?? idealW, minW), maxW),
               height: min(max(p.height ?? idealH, minH), maxH))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if proposalsSeen[name] == nil { order.append(name) }
        calls[name, default: 0] += 1
        let s = fmt(proposal)
        if !(proposalsSeen[name] ?? []).contains(s) { proposalsSeen[name, default: []].append(s) }
        return answer(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if proposalsSeen[name] == nil { order.append(name); proposalsSeen[name] = [] }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// A leaf of constant AREA: width is flexible (ideal `ideal`), height = area / width.
struct AreaLeaf: Layout {
    let name: String
    let area: CGFloat
    let ideal: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if proposalsSeen[name] == nil { order.append(name) }
        calls[name, default: 0] += 1
        let s = fmt(proposal)
        if !(proposalsSeen[name] ?? []).contains(s) { proposalsSeen[name, default: []].append(s) }
        let w = max(1, min(proposal.width ?? ideal, 1000))
        return CGSize(width: w, height: area / w)
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// A fixed w x h leaf.
func fixed(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View {
    Leaf(name: n, minW: w, idealW: w, maxW: w, minH: h, idealH: h, maxH: h) { SwiftUI.Color.clear }
}
/// Flexible on width (min...max, ideal), fixed height h.
func flexW(_ n: String, _ minW: CGFloat, _ ideal: CGFloat, _ maxW: CGFloat, _ h: CGFloat = 20) -> some View {
    Leaf(name: n, minW: minW, idealW: ideal, maxW: maxW, minH: h, idealH: h, maxH: h) { SwiftUI.Color.clear }
}
/// Flexible on height, fixed width w.
func flexH(_ n: String, _ minH: CGFloat, _ ideal: CGFloat, _ maxH: CGFloat, _ w: CGFloat = 20) -> some View {
    Leaf(name: n, minW: w, idealW: w, maxW: w, minH: minH, idealH: ideal, maxH: maxH) { SwiftUI.Color.clear }
}

@MainActor func measure<V: View>(_ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) -> CGSize {
    proposalsSeen = [:]; placed = [:]; order = []; calls = [:]; geometry = [:]; placedWith = [:]
    lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: Probe(label: "", proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    return lastSize
}

@MainActor func run<V: View>(_ label: String, _ proposal: ProposedViewSize,
                             @ViewBuilder _ view: () -> V) {
    let size = measure(proposal, view)
    print("\(label) @\(fmt(proposal)): size \(fmt(size))")
    for n in order {
        let r = placed[n]
        let at = r.map { "at (\(d($0.minX)), \(d($0.minY))) \(d($0.width))x\(d($0.height))" } ?? "not placed"
        print("    leaf \(n): proposed [\((proposalsSeen[n] ?? []).joined(separator: ", "))] \(at) calls \(calls[n] ?? 0)")
        if let w = placedWith[n] { print("        placements, in order: [\(w.joined(separator: "; "))]") }
    }
    for (n, r) in geometry.sorted(by: { $0.key < $1.key }) {
        print("    geometry \(n): (\(d(r.minX)), \(d(r.minY))) \(d(r.width))x\(d(r.height))")
    }
    fflush(stdout)
}

/// Revision 4 (critic round): every PLACEMENT a leaf receives in
/// `placeSubviews` — its proposal, which `Leaf` ignores, and its rect — in
/// order. Only `Logged` writes it, so every earlier arm's output is unchanged.
nonisolated(unsafe) var placedWith: [String: [String]] = [:]

/// A leaf that answers `half` of its proposed width (40 at nil) and height 10,
/// or a fixed w x h, and logs both its measurement and its placement proposals.
struct Logged: Layout {
    let name: String
    var fixedSize: CGSize? = nil
    func answer(_ p: ProposedViewSize) -> CGSize {
        fixedSize ?? CGSize(width: (p.width ?? 40) / 2, height: 10)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if proposalsSeen[name] == nil { order.append(name) }
        calls[name, default: 0] += 1
        let s = fmt(proposal)
        if !(proposalsSeen[name] ?? []).contains(s) { proposalsSeen[name, default: []].append(s) }
        return answer(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if proposalsSeen[name] == nil { order.append(name); proposalsSeen[name] = [] }
        placed[name] = bounds
        // Every placement, in order, NOT deduplicated: proposal -> rect.
        placedWith[name, default: []].append(
            "\(fmt(proposal)) -> (\(d(bounds.minX)), \(d(bounds.minY))) \(d(bounds.width))x\(d(bounds.height))")
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}
func half(_ n: String) -> some View { Logged(name: n) { SwiftUI.Color.clear } }
func logged(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View {
    Logged(name: n, fixedSize: CGSize(width: w, height: h)) { SwiftUI.Color.clear }
}

/// Like `Probe`, but PLACES its child at a 0x0 proposal after measuring it at
/// the arm's: SwiftUI traps placing an infinite answer ("view origin is
/// invalid", as D12 in swiftui-frame-semantics.swift records), so an arm whose
/// answer may be infinite reads only its size. The 0x0 placement adds a
/// `0x0` entry to the proposal list; ignore it.
struct MeasureOnlyProbe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        lastSize = subviews[0].sizeThatFits(proposal); return .zero
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: .zero)
    }
}

@MainActor func runMeasured<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    proposalsSeen = [:]; placed = [:]; order = []; calls = [:]; geometry = [:]; placedWith = [:]
    lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: MeasureOnlyProbe(proposal: proposal) { view() })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    print("\(label) @\(fmt(proposal)) (measured only): size \(fmt(lastSize))")
    for n in order {
        print("    leaf \(n): proposed [\((proposalsSeen[n] ?? []).joined(separator: ", "))]")
    }
    fflush(stdout)
}

let none = ProposedViewSize(width: nil, height: nil)
func p(_ w: CGFloat?, _ h: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: w, height: h) }

enum Kind: String, CaseIterable { case rect, color, text, leaf, image, hstack, button, paddedText, toggle }

@MainActor @ViewBuilder func view(_ k: Kind) -> some View {
    switch k {
    case .rect: Rectangle().frame(width: 20, height: 20)
    case .color: SwiftUI.Color.red.frame(width: 20, height: 20)
    case .text: Text("Hi")
    case .leaf: fixed("L", 20, 20)
    case .image: Image(systemName: "star")
    case .hstack: HStack { Rectangle().frame(width: 20, height: 20) }
    case .button: Button("B") {}
    case .paddedText: Text("Hi").padding(4)
    case .toggle: Toggle("T", isOn: .constant(true))
    }
}

@MainActor func spacing(_ a: Kind, _ b: Kind) {
    let sa = measure(none) { view(a) }, sb = measure(none) { view(b) }
    let h = measure(none) { HStack { view(a); view(b) } }
    let v = measure(none) { VStack { view(a); view(b) } }
    print("S \(a.rawValue)|\(b.rawValue): hstack \(d(h.width - sa.width - sb.width))  vstack \(d(v.height - sa.height - sb.height))")
    fflush(stdout)
}

@MainActor func probes() {
    // ================= S: default spacing by view kind =================
    // Control: explicit spacing 0 and 20 between two rects must read 0 and 20.
    do {
        let r = measure(none) { view(.rect) }
        let h0 = measure(none) { HStack(spacing: 0) { view(.rect); view(.rect) } }
        let h20 = measure(none) { HStack(spacing: 20) { view(.rect); view(.rect) } }
        let v20 = measure(none) { VStack(spacing: 20) { view(.rect); view(.rect) } }
        print("S control explicit: hstack(0) \(d(h0.width - 2 * r.width)) hstack(20) \(d(h20.width - 2 * r.width)) vstack(20) \(d(v20.height - 2 * r.height))")
    }
    for (a, b) in [(Kind.rect, Kind.rect), (.color, .color), (.leaf, .leaf), (.text, .text), (.rect, .text),
                   (.text, .rect), (.leaf, .text), (.image, .image), (.image, .text), (.hstack, .rect),
                   (.hstack, .text), (.button, .button), (.text, .button), (.paddedText, .paddedText),
                   (.paddedText, .rect), (.toggle, .toggle), (.text, .toggle)] {
        spacing(a, b)
    }
    // ZStack of two kinds as a stack child: is its spacing the union?
    do {
        let r = measure(none) { view(.rect) }, t = measure(none) { view(.text) }
        let z = measure(none) { ZStack { view(.text) } }
        let h = measure(none) { HStack { ZStack { view(.text) }; view(.text) } }
        let v = measure(none) { VStack { ZStack { view(.text) }; view(.text) } }
        print("S zstack(text)|text: hstack \(d(h.width - z.width - t.width)) vstack \(d(v.height - z.height - t.height)) (r \(fmt(r)))")
    }

    // ================= SP: Spacer =================
    // Control: HStack(spacing: 0){20; Spacer(minLength: 30); 20} = 70 (P5).
    run("SP control HStack(0){a20; Spacer(min 30); b20}", none) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(minLength: 30); fixed("b", 20, 20) }
    }
    run("SP1 HStack(0){a20; Spacer(); b20}", none) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("SP2 HStack{a20; Spacer(); b20} (default spacing)", none) {
        HStack { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("SP3 HStack{a20; Spacer(minLength: 0); b20} (default spacing)", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0); fixed("b", 20, 20) }
    }
    run("SP4 HStack(spacing: 20){a20; Spacer(minLength: 0); b20}", none) {
        HStack(spacing: 20) { fixed("a", 20, 20); Spacer(minLength: 0); fixed("b", 20, 20) }
    }
    run("SP5 HStack{text; Spacer(); text} (default spacing)", none) {
        HStack { Text("Hi"); Spacer(); Text("Hi") }
    }
    run("SP5c HStack{text; text} (default spacing, control for SP5)", none) {
        HStack { Text("Hi"); Text("Hi") }
    }
    run("SP6 VStack(0){a20; Spacer(); b20}", none) {
        VStack(spacing: 0) { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("SP7 VStack{a20; Spacer(minLength: 0); b20} (default spacing)", none) {
        VStack { fixed("a", 20, 20); Spacer(minLength: 0); fixed("b", 20, 20) }
    }
    run("SP8 HStack(0){a20; Spacer(); b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("SP9 HStack(0){Spacer(); a20; Spacer(); Spacer()} at 200x50 (surplus sharing)", p(200, 50)) {
        HStack(spacing: 0) { Spacer(); fixed("a", 20, 20); Spacer(); Spacer() }
    }
    run("SP10 HStack(0){Spacer(min 50); a20; Spacer()} at 200x50 (unequal minimums)", p(200, 50)) {
        HStack(spacing: 0) { Spacer(minLength: 50); fixed("a", 20, 20); Spacer() }
    }
    // Cross axis: what a Spacer claims.
    run("SP11 HStack(0){Spacer()} at nil", none) { HStack(spacing: 0) { Spacer() } }
    run("SP12 HStack(0){Spacer()} at 100x50", p(100, 50)) { HStack(spacing: 0) { Spacer() } }
    run("SP13 HStack(0){Spacer(); a20x20} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { Spacer(); fixed("a", 20, 20) }
    }
    run("SP14 VStack(0){Spacer(); a20x20} at 100x50", p(100, 50)) {
        VStack(spacing: 0) { Spacer(); fixed("a", 20, 20) }
    }
    run("SP15 Spacer() alone (in the Probe layout) at 100x50", p(100, 50)) { Spacer() }
    run("SP16 Spacer() alone at nil", none) { Spacer() }
    run("SP17 ZStack{Spacer()} at 100x50", p(100, 50)) { ZStack { Spacer() } }
    run("SP18 HStack(0){VStack{Spacer()}; a20} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { VStack { Spacer() }; fixed("a", 20, 20) }
    }
    run("SP19 HStack(0){a20; Spacer().frame(width: 10); b20} at 200x50 (framed spacer)", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer().frame(width: 10); fixed("b", 20, 20) }
    }
    run("SP20 HStack(0){a20; Spacer().padding(5); b20} at 200x50 (padded spacer)", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer().padding(5); fixed("b", 20, 20) }
    }

    // ================= G: distribution and compression =================
    // Control: two equally flexible children (0...80, ideal 80) at 100 get 50/50 (record §09).
    run("G control HStack(0){a 0..80; b 0..80} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80); flexW("b", 0, 80, 80) }
    }
    run("G1 HStack(0){a 20..100; b 60..100} at 100x50 (b less flexible)", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 20, 100, 100); flexW("b", 60, 100, 100) }
    }
    run("G1r HStack(0){b 60..100; a 20..100} at 100x50 (order swapped)", p(100, 50)) {
        HStack(spacing: 0) { flexW("b", 60, 100, 100); flexW("a", 20, 100, 100) }
    }
    run("G2 HStack(0){a 0..80 prio 1; b 30..80} at 100x50 (lower group's minimum reserved?)", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80).layoutPriority(1); flexW("b", 30, 80, 80) }
    }
    run("G2c HStack(0){a 0..80 prio 1; b 0..80} at 100x50 (control for G2)", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80).layoutPriority(1); flexW("b", 0, 80, 80) }
    }
    run("G3 HStack(0){a fixed 20; b 0..inf ideal 10} at 200x50 (non-spacer expansion)", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); flexW("b", 0, 10, .infinity) }
    }
    run("G4 HStack(0){a fixed 20; b fixed 20 .frame(maxWidth: .infinity)} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); fixed("b", 20, 20).frame(maxWidth: .infinity) }
    }
    run("G5 HStack(0){a 20; Spacer(); b 0..inf ideal 10} at 200x50 (spacer vs greedy child)", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(); flexW("b", 0, 10, .infinity) }
    }
    run("G5b HStack(0){b 0..inf ideal 10; Spacer(); a 20} at 200x50 (order swapped)", p(200, 50)) {
        HStack(spacing: 0) { flexW("b", 0, 10, .infinity); Spacer(); fixed("a", 20, 20) }
    }
    run("G6 HStack(0){a fixed 80; Spacer(); b 0..80} at 100x50 (overflow WITH a spacer)", p(100, 50)) {
        HStack(spacing: 0) { fixed("a", 80, 20); Spacer(); flexW("b", 0, 80, 80) }
    }
    run("G6c HStack(0){a fixed 80; b 0..80} at 100x50 (control: no spacer)", p(100, 50)) {
        HStack(spacing: 0) { fixed("a", 80, 20); flexW("b", 0, 80, 80) }
    }
    run("G7 HStack(0){a 0..80; Spacer(); b 20} at nil", none) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80); Spacer(); fixed("b", 20, 20) }
    }
    run("G8 HStack(0){a 0..inf ideal 10; b 20} at inf x inf", p(.infinity, .infinity)) {
        HStack(spacing: 0) { flexW("a", 0, 10, .infinity); fixed("b", 20, 20) }
    }
    run("G9 HStack(0){a fixed 80; b fixed 80} at 100x50 (overflow, nothing flexible)", p(100, 50)) {
        HStack(spacing: 0) { fixed("a", 80, 20); fixed("b", 80, 20) }
    }
    run("G10 HStack(0){a 20; b 20} at 300x50 (stack smaller than proposal)", p(300, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); fixed("b", 20, 20) }
    }
    run("G11 HStack(0){HStack{a 0..80 prio 1}; b 0..80} at 100x50 (single-child pass-through)", p(100, 50)) {
        HStack(spacing: 0) { HStack { flexW("a", 0, 80, 80).layoutPriority(1) }; flexW("b", 0, 80, 80) }
    }
    run("G11c HStack(0){HStack{a 0..80 prio 1; c fixed 0}; b 0..80} at 100x50 (two children: control)", p(100, 50)) {
        HStack(spacing: 0) {
            HStack(spacing: 0) { flexW("a", 0, 80, 80).layoutPriority(1); fixed("c", 0, 0) }
            flexW("b", 0, 80, 80)
        }
    }
    run("G12 HStack(10){a 0..80; b 0..80; c 0..80} at 100x50 (spacing comes off first)", p(100, 50)) {
        HStack(spacing: 10) { flexW("a", 0, 80, 80); flexW("b", 0, 80, 80); flexW("c", 0, 80, 80) }
    }
    run("G13 HStack(0){a 30..40; b 0..100 ideal 50; c 45..45} at 60x50 (three flexibilities)", p(60, 50)) {
        HStack(spacing: 0) { flexW("a", 30, 40, 40); flexW("b", 0, 50, 100); fixed("c", 45, 20) }
    }
    run("G14 HStack(0){a 0..80 prio -1; b 0..80; c 0..80 prio 1} at 100x50 (three groups)", p(100, 50)) {
        HStack(spacing: 0) {
            flexW("a", 0, 80, 80).layoutPriority(-1); flexW("b", 0, 80, 80); flexW("c", 0, 80, 80).layoutPriority(1)
        }
    }
    run("G15 VStack(0){a 0..80; b 20..80} at 50x100 (vertical distribution)", p(50, 100)) {
        VStack(spacing: 0) { flexH("a", 0, 80, 80); flexH("b", 20, 80, 80) }
    }
    run("G16 VStack(0){a width 0..inf ideal 10; b fixed 30} at 100x100 (cross proposal)", p(100, 100)) {
        VStack(spacing: 0) { flexW("a", 0, 10, .infinity); fixed("b", 30, 20) }
    }
    run("G17 VStack(0){a width 0..inf ideal 10; b fixed 30} at nil", none) {
        VStack(spacing: 0) { flexW("a", 0, 10, .infinity); fixed("b", 30, 20) }
    }
    run("G18 HStack(0){Text long; Text short} at 80xnil (text compression)", p(80, nil)) {
        HStack(spacing: 0) { Text("A fairly long label"); Text("Short") }
    }
    run("G19 HStack(0){a 20; Spacer(); b 20} at nil x 50", p(nil, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("G20 HStack(0){a height 0..inf ideal 10; b 20x30} at 100x80 (cross axis)", p(100, 80)) {
        HStack(spacing: 0) { flexH("a", 0, 10, .infinity); fixed("b", 20, 30) }
    }
    run("G21 HStack(0){a height 0..inf ideal 10; b 20x30} at 100 x nil", p(100, nil)) {
        HStack(spacing: 0) { flexH("a", 0, 10, .infinity); fixed("b", 20, 30) }
    }
    run("G22 HStack(0){} empty at 100x50", p(100, 50)) { HStack(spacing: 0) {} }
    run("G23 HStack{a20; if false; b20} (default spacing; empty conditional)", none) {
        HStack { fixed("a", 20, 20); if Bool.random() && false { fixed("x", 20, 20) }; fixed("b", 20, 20) }
    }
    run("G24 HStack(0){a 0..inf ideal 10; b 0..inf ideal 10 prio 1} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 10, .infinity); flexW("b", 0, 10, .infinity).layoutPriority(1) }
    }
    run("G25 HStack(0){a 0..inf ideal 10; Spacer(); b 0..inf ideal 10} at 200x50 (two greedy + spacer)", p(200, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 10, .infinity); Spacer(); flexW("b", 0, 10, .infinity) }
    }

    // ================= A: alignment =================
    // Controls are the .center arms, whose offsets must differ from the edge arms.
    for (name, al) in [("top", VerticalAlignment.top), ("center", .center), ("bottom", .bottom)] {
        run("A1 HStack(0, alignment: .\(name)){a 20x10; b 20x30}", none) {
            HStack(alignment: al, spacing: 0) { fixed("a", 20, 10); fixed("b", 20, 30) }
        }
    }
    for (name, al) in [("leading", HorizontalAlignment.leading), ("center", .center), ("trailing", .trailing)] {
        run("A2 VStack(0, alignment: .\(name)){a 10x20; b 30x20}", none) {
            VStack(alignment: al, spacing: 0) { fixed("a", 10, 20); fixed("b", 30, 20) }
        }
    }
    let nine: [(String, SwiftUI.Alignment)] = [
        ("topLeading", .topLeading), ("top", .top), ("topTrailing", .topTrailing),
        ("leading", .leading), ("center", .center), ("trailing", .trailing),
        ("bottomLeading", .bottomLeading), ("bottom", .bottom), ("bottomTrailing", .bottomTrailing),
    ]
    for (name, al) in nine {
        run("A3 ZStack(.\(name)){big 60x40; small 20x20} at nil", none) {
            ZStack(alignment: al) { fixed("big", 60, 40); fixed("small", 20, 20) }
        }
    }
    run("A4 ZStack(.topLeading){a 60x20; b 20x40} at nil (size is the union)", none) {
        ZStack(alignment: .topLeading) { fixed("a", 60, 20); fixed("b", 20, 40) }
    }
    run("A5 ZStack{a 0..inf ideal 10 (w and h); b 20x20} at 100x80", p(100, 80)) {
        ZStack {
            Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            fixed("b", 20, 20)
        }
    }
    run("A5n same ZStack at nil", none) {
        ZStack {
            Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            fixed("b", 20, 20)
        }
    }
    for (name, al) in nine {
        run("A6 primary 60x40 .overlay(alignment: .\(name)){o 20x20}", none) {
            fixed("primary", 60, 40).overlay(alignment: al) { fixed("o", 20, 20) }
        }
    }
    run("A7 primary 60x40 .overlay(.center){o 0..inf ideal 10} (overlay proposal)", p(300, 300)) {
        fixed("primary", 60, 40).overlay {
            Leaf(name: "o", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
        }
    }
    run("A8 primary 60x40 .overlay(.topLeading){o 100x100} (bigger overlay)", none) {
        fixed("primary", 60, 40).overlay(alignment: .topLeading) { fixed("o", 100, 100) }
    }
    for (name, al) in [("topLeading", SwiftUI.Alignment.topLeading), ("center", .center), ("bottomTrailing", .bottomTrailing)] {
        run("A9 primary 60x40 .background(alignment: .\(name)){bg 20x20}", none) {
            fixed("primary", 60, 40).background(alignment: al) { fixed("bg", 20, 20) }
        }
    }
    run("A10 primary 60x40 .overlay{ o1 20x20; o2 30x10 } (multi-view overlay)", none) {
        fixed("primary", 60, 40).overlay { fixed("o1", 20, 20); fixed("o2", 30, 10) }
    }

    // ================= SC: ScrollView axes =================
    // Control: the content alone at the same proposal.
    run("SC control content 0..inf ideal 50 x 0..inf ideal 300 alone at 100x100", p(100, 100)) {
        Leaf(name: "c", minW: 0, idealW: 50, maxW: .infinity, minH: 0, idealH: 300, maxH: .infinity) { SwiftUI.Color.clear }
    }
    for (name, axes) in [("vertical", Axis.Set.vertical), ("horizontal", .horizontal), ("both", [.horizontal, .vertical] as Axis.Set)] {
        for prop in [none, p(100, 100), p(.infinity, .infinity)] {
            run("SC1 ScrollView(.\(name)){c flexible ideal 50x300}", prop) {
                ScrollView(axes) {
                    Leaf(name: "c", minW: 0, idealW: 50, maxW: .infinity, minH: 0, idealH: 300, maxH: .infinity) { SwiftUI.Color.clear }
                }
            }
        }
        run("SC2 ScrollView(.\(name)){c fixed 50x30} at 100x100 (content smaller than viewport)", p(100, 100)) {
            ScrollView(axes) { fixed("c", 50, 30) }
        }
        run("SC3 ScrollView(.\(name)){a 50x30; b 30x20} at 200x200 (two direct children)", p(200, 200)) {
            ScrollView(axes) { fixed("a", 50, 30); fixed("b", 30, 20) }
        }
        run("SC4 ScrollView(.\(name)){c fixed 500x500} at 100x100 (content larger)", p(100, 100)) {
            ScrollView(axes) { fixed("c", 500, 500) }
        }
    }

    // ================= X: does the stack sort by flexibility when the FIRST
    // child is the more flexible one? (G3/G9/G10 printed no 0/inf probe for
    // their second child; these arms decide whether that matters.)
    run("X1 HStack(0){a 0..80; b fixed 80} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80); fixed("b", 80, 20) }
    }
    run("X2 HStack(0){a 0..inf ideal 10; b fixed 20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 10, .infinity); fixed("b", 20, 20) }
    }
    run("X3 HStack(0){a 0..80; b fixed 30; c fixed 30} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80); fixed("b", 30, 20); fixed("c", 30, 20) }
    }
    run("X4 HStack(0){a 0..100 ideal 50; b 40..60 ideal 50} at 70x50", p(70, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 50, 100); flexW("b", 40, 50, 60) }
    }
    run("X5 HStack(0){a 0..80 prio 1; Spacer(); b 0..80} at 100x50 (spacer below priority 0)", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80).layoutPriority(1); Spacer(); flexW("b", 0, 80, 80) }
    }
    run("X6 HStack(0){a 0..80; Spacer().layoutPriority(1); b 0..80} at 100x50 (spacer given priority 1)", p(100, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 80, 80); Spacer().layoutPriority(1); flexW("b", 0, 80, 80) }
    }
    run("X7 HStack(0){a 0..inf ideal 10; b 0..inf ideal 10 .layoutPriority(-1)} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { flexW("a", 0, 10, .infinity); flexW("b", 0, 10, .infinity).layoutPriority(-1) }
    }
    run("X8 HStack(0){Spacer().overlay{o 20x20}; a 20} at 200x50 (overlaid spacer)", p(200, 50)) {
        HStack(spacing: 0) { Spacer().overlay { fixed("o", 20, 20) }; fixed("a", 20, 20) }
    }
    run("X9 HStack(0){a 20; Spacer()} at nil (label corrected 2026-09-16: it never ran at 100x50)", none) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer() }
    }
    run("X10 HStack(0){a height 0..inf ideal 10; b 20x30} at nil (cross re-proposal)", none) {
        HStack(spacing: 0) { flexH("a", 0, 10, .infinity); fixed("b", 20, 30) }
    }
    run("X11 VStack(0){a 0..inf ideal 10 wide; b 30} at nil x 100", p(nil, 100)) {
        VStack(spacing: 0) { flexW("a", 0, 10, .infinity); fixed("b", 30, 20) }
    }
    run("X12 ZStack{a 0..inf ideal 10; b 20x20} at 100 x nil", p(100, nil)) {
        ZStack {
            Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            fixed("b", 20, 20)
        }
    }
    run("X13 HStack(0){a fixed 80; b fixed 80} at nil x 50 (overflow check at nil)", p(nil, 50)) {
        HStack(spacing: 0) { fixed("a", 80, 20); fixed("b", 80, 20) }
    }

    // ================= SP again: spacer alone / cross axis (sentinel harness)
    run("SP11b HStack(0){Spacer()} at nil", none) { HStack(spacing: 0) { Spacer() } }
    run("SP12b HStack(0){Spacer()} at 100x50", p(100, 50)) { HStack(spacing: 0) { Spacer() } }
    run("SP15b Spacer() alone at 100x50", p(100, 50)) { Spacer() }
    run("SP16b Spacer() alone at nil", none) { Spacer() }
    run("SP16c Spacer(minLength: 12) alone at nil", none) { Spacer(minLength: 12) }
    run("SP17b ZStack{Spacer()} at 100x50", p(100, 50)) { ZStack { Spacer() } }
    run("SP18b HStack(0){VStack{Spacer()}; a20} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { VStack { Spacer() }; fixed("a", 20, 20) }
    }
    run("SP21 VStack(0){HStack(0){Spacer()}; a20} at 100x50", p(100, 50)) {
        VStack(spacing: 0) { HStack(spacing: 0) { Spacer() }; fixed("a", 20, 20) }
    }
    run("SP22 HStack(0){a20; Spacer()} at 100 x nil (spacer cross at nil)", p(100, nil)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer() }
    }
    run("G22b HStack(0){} empty at 100x50", p(100, 50)) { HStack(spacing: 0) {} }
    run("G22c HStack{} empty at nil", none) { HStack {} }

    // ================= SCG: where scroll content sits inside its viewport
    for (name, axes) in [("vertical", Axis.Set.vertical), ("horizontal", .horizontal), ("both", [.horizontal, .vertical] as Axis.Set)] {
        run("SCG ScrollView(.\(name)){c 50x30}.frame(100x100) content frame in the scroll view", p(100, 100)) {
            ScrollView(axes) {
                fixed("c", 50, 30)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("sv")) } action: { geometry["c"] = $0 }
            }
            .frame(width: 100, height: 100)
            .coordinateSpace(.named("sv"))
        }
    }

    // ================= SCG2: the same, coordinate space ON the scroll view
    for (name, axes) in [("vertical", Axis.Set.vertical), ("horizontal", .horizontal), ("both", [.horizontal, .vertical] as Axis.Set)] {
        run("SCG2 ScrollView(.\(name)){c 50x30} coordinate space on the scroll view, at 100x100", p(100, 100)) {
            ScrollView(axes) {
                fixed("c", 50, 30)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("sv")) } action: { geometry["c"] = $0 }
            }
            .coordinateSpace(.named("sv"))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { geometry["sv"] = $0 }
        }
    }
    // The control for SCG2: content LARGER than the viewport sits at (0, 0).
    run("SCG2 control ScrollView(.both){c 500x500} at 100x100", p(100, 100)) {
        ScrollView([.horizontal, .vertical]) {
            fixed("c", 500, 500)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("sv")) } action: { geometry["c"] = $0 }
        }
        .coordinateSpace(.named("sv"))
    }

    // ================= SPB: views SwiftUI does not lay out alone, read through
    // a background leaf, which is proposed its primary's size (A9).
    run("SPB control fixed 30x10 .background{bg}", p(100, 50)) {
        fixed("a", 30, 10).background { fixed("bg", 0, 0) }
    }
    run("SPB1 HStack(0){Spacer()} .background{bg} at 100x50", p(100, 50)) {
        HStack(spacing: 0) { Spacer() }.background { fixed("bg", 0, 0) }
    }
    run("SPB2 HStack(0){Spacer()} .background{bg} at nil", none) {
        HStack(spacing: 0) { Spacer() }.background { fixed("bg", 0, 0) }
    }
    run("SPB3 Spacer() .background{bg} at 100x50 (outside a stack)", p(100, 50)) {
        Spacer().background { fixed("bg", 0, 0) }
    }
    run("SPB4 Spacer() .background{bg} at nil", none) {
        Spacer().background { fixed("bg", 0, 0) }
    }
    run("SPB5 VStack(0){Spacer()} .background{bg} at 100x50", p(100, 50)) {
        VStack(spacing: 0) { Spacer() }.background { fixed("bg", 0, 0) }
    }
    run("SPB6 ZStack{Spacer()} .background{bg} at 100x50", p(100, 50)) {
        ZStack { Spacer() }.background { fixed("bg", 0, 0) }
    }
    run("SPB7 HStack(0){} .background{bg} at 100x50 (empty stack)", p(100, 50)) {
        HStack(spacing: 0) {}.background { fixed("bg", 0, 0) }
    }


    // ================= R: the ROOT. A hosting view proposes its bounds and
    // places the root's answer; where? Control: a greedy root fills.
    for (label, anyView) in [
        ("R control greedy Leaf 0..inf root in a 100x100 host",
         AnyView(Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear })),
        ("R1 HStack(0){a 58x20} root in a 100x100 host", AnyView(HStack(spacing: 0) { fixed("a", 58, 20) })),
        ("R2 fixed a 58x20 root in a 100x100 host", AnyView(fixed("a", 58, 20))),
    ] {
        proposalsSeen = [:]; placed = [:]; order = []; calls = [:]
        let host = NSHostingView(rootView: anyView)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        let r = placed["a"]!
        print("\(label): a proposed [\((proposalsSeen["a"] ?? []).joined(separator: ", "))] at (\(d(r.minX)), \(d(r.minY))) \(d(r.width))x\(d(r.height))")
    }


    // ================= Q: is the second, cross-axis pass part of the REPORTED size?
    // a: width ideal 10, height 600 / width. Pass 1 (width nil) -> 10x60; pass 2
    // (width 30, the widest sibling) -> 30x20. Stack height 80 = pass 1, 40 = pass 2.
    run("Q1 VStack(0){a area 600 ideal 10; b 30x20} at nil", none) {
        VStack(spacing: 0) { AreaLeaf(name: "a", area: 600, ideal: 10) { SwiftUI.Color.clear }; fixed("b", 30, 20) }
    }
    run("Q1c VStack(0){a area 600 ideal 10; b 30x20} at 30 x nil (control: width given)", p(30, nil)) {
        VStack(spacing: 0) { AreaLeaf(name: "a", area: 600, ideal: 10) { SwiftUI.Color.clear }; fixed("b", 30, 20) }
    }
    run("Q2 ZStack{a area 600 ideal 10; b 30x20} at nil", none) {
        ZStack { AreaLeaf(name: "a", area: 600, ideal: 10) { SwiftUI.Color.clear }; fixed("b", 30, 20) }
    }
    run("Q3 HStack(0){a area 600 ideal 10; b 20x30} at 100x50 (measured at allocations?)", p(100, 50)) {
        HStack(spacing: 0) { AreaLeaf(name: "a", area: 600, ideal: 10) { SwiftUI.Color.clear }; fixed("b", 20, 30) }
    }


    // ================= AR: aspectRatio over a FIXED child (the preview's
    // PreviewToggle). Control: the child alone answers 168x95 at 500x300.
    run("AR control fixed 168x95 alone at 500x300", p(500, 300)) { fixed("c", 168, 95) }
    run("AR1 fixed 168x95 .aspectRatio(16/9, .fit) at 500x300", p(500, 300)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    run("AR2 fixed 168x95 .aspectRatio(16/9, .fit) at nil", none) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    run("AR3 flexible c .aspectRatio(16/9, .fit) at 500x300 (a child that takes the offer)", p(500, 300)) {
        Leaf(name: "c", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    run("AR4 HStack(12){a 168x64; fixed 168x95 .aspectRatio(16/9); b 168x64} at 856x300", p(856, 300)) {
        HStack(spacing: 12) {
            fixed("a", 168, 64); fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit); fixed("b", 168, 64)
        }
    }


    // ================= A11: an overlay whose content is an empty conditional.
    // Control: A6's .center arm places o at (20, 10); here o must not exist.
    run("A11 primary 60x40 .overlay{ if false { o 20x20 } } (empty overlay)", none) {
        fixed("primary", 60, 40).overlay { if Bool.random() && false { fixed("o", 20, 20) } }
    }
    run("A11b primary 60x40 .background{ if false { bg 20x20 } } (empty background)", none) {
        fixed("primary", 60, 40).background { if Bool.random() && false { fixed("bg", 20, 20) } }
    }


    // ================= Revision 4, critic round (2026-09-16). K: the spacing
    // walk, the spacer marking walk, aspectRatio's single-axis and infinite
    // branches, overlay CONTENT placement, List, and the root overlay.

    // K1: is a nil minLength a constant 8, or the text-to-text gap? Control K0/K1b:
    // text|text is 0 vertically.
    run("K0 control VStack(0){text; text}", none) { VStack(spacing: 0) { Text("Hi"); Text("Hi") } }
    run("K1b VStack{text; text} (default spacing)", none) { VStack { Text("Hi"); Text("Hi") } }
    run("K1 VStack{text; Spacer(); text} (default spacing)", none) { VStack { Text("Hi"); Spacer(); Text("Hi") } }
    run("K1c VStack(0){text; Spacer(); text}", none) { VStack(spacing: 0) { Text("Hi"); Spacer(); Text("Hi") } }

    // K2: does the stack's axis (and the spacer's -inf priority) reach a spacer
    // through a ZStack, aspectRatio, fixedSize, a flexible frame, and the
    // OVERLAY side of .overlay? Control K2: a bare spacer, 200x20.
    run("K2 control HStack(0){a20; Spacer(); b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer(); fixed("b", 20, 20) }
    }
    run("K2a HStack(0){a20; ZStack{Spacer()}; b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); ZStack { Spacer() }; fixed("b", 20, 20) }
    }
    run("K2b HStack(0){a20; Spacer().aspectRatio(1, .fit); b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer().aspectRatio(1, contentMode: .fit); fixed("b", 20, 20) }
    }
    run("K2c HStack(0){a20; Spacer().fixedSize(); b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer().fixedSize(); fixed("b", 20, 20) }
    }
    run("K2d HStack(0){a20; Spacer().frame(maxWidth: .infinity); b20} at 200x50", p(200, 50)) {
        HStack(spacing: 0) { fixed("a", 20, 20); Spacer().frame(maxWidth: .infinity); fixed("b", 20, 20) }
    }
    run("K2e HStack(0){a20; p 10x10 .overlay{Spacer() .background{bg}}; b20} at 200x50 (overlay-side spacer)", p(200, 50)) {
        HStack(spacing: 0) {
            fixed("a", 20, 20)
            fixed("p", 10, 10).overlay { Spacer().background { fixed("bg", 0, 0) } }
            fixed("b", 20, 20)
        }
    }

    // K3: default spacing beside a spacer seen through a wrapper. Control K3:
    // two views get 8 (48); a bare Spacer(minLength: 0) between them gets none
    // (SP3, 40).
    run("K3 control HStack{a20; b20} (default spacing)", none) { HStack { fixed("a", 20, 20); fixed("b", 20, 20) } }
    run("K3a HStack{a20; Spacer(minLength: 0).padding(0); b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).padding(0); fixed("b", 20, 20) }
    }
    run("K3b HStack{a20; Spacer(minLength: 0).frame(width: 0); b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).frame(width: 0); fixed("b", 20, 20) }
    }
    run("K3c HStack{a20; Spacer(minLength: 0).overlay{c 0x0}; b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).overlay { fixed("c", 0, 0) }; fixed("b", 20, 20) }
    }
    run("K3d HStack{a20; Spacer(minLength: 0).layoutPriority(1); b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).layoutPriority(1); fixed("b", 20, 20) }
    }
    run("K3e HStack{a20; Spacer(minLength: 0).fixedSize(); b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).fixedSize(); fixed("b", 20, 20) }
    }
    run("K3f HStack{a20; Spacer(minLength: 0).aspectRatio(1, .fit); b20}", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).aspectRatio(1, contentMode: .fit); fixed("b", 20, 20) }
    }
    run("K3g HStack{a20; ZStack{Spacer(minLength: 0)}; b20}", none) {
        HStack { fixed("a", 20, 20); ZStack { Spacer(minLength: 0) }; fixed("b", 20, 20) }
    }
    run("K3h HStack{a20; VStack{Spacer(minLength: 0)}; b20}", none) {
        HStack { fixed("a", 20, 20); VStack { Spacer(minLength: 0) }; fixed("b", 20, 20) }
    }
    run("K3i HStack{a20; c 0x0 .overlay{Spacer(minLength: 0)}; b20} (overlay-side spacer)", none) {
        HStack { fixed("a", 20, 20); fixed("c", 0, 0).overlay { Spacer(minLength: 0) }; fixed("b", 20, 20) }
    }
    run("K3j HStack{a20; ZStack{Spacer(minLength: 0); c 0x0}; b20} (two-child ZStack, spacer first)", none) {
        HStack { fixed("a", 20, 20); ZStack { Spacer(minLength: 0); fixed("c", 0, 0) }; fixed("b", 20, 20) }
    }
    run("K3k HStack{a20; ZStack{c 0x0; Spacer(minLength: 0)}; b20} (two-child ZStack, spacer last)", none) {
        HStack { fixed("a", 20, 20); ZStack { fixed("c", 0, 0); Spacer(minLength: 0) }; fixed("b", 20, 20) }
    }
    run("K3l HStack{a20; ZStack{Spacer(minLength: 0); Spacer(minLength: 0)}; b20} (two spacers)", none) {
        HStack { fixed("a", 20, 20); ZStack { Spacer(minLength: 0); Spacer(minLength: 0) }; fixed("b", 20, 20) }
    }
    run("K3m HStack{a20; Spacer(minLength: 0).padding(4); b20} (non-zero padding)", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).padding(4); fixed("b", 20, 20) }
    }
    run("K3n HStack{a20; Spacer(minLength: 0).padding(.leading, 4); b20} (one edge padded)", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).padding(.leading, 4); fixed("b", 20, 20) }
    }
    run("K3o HStack{a20; Spacer(minLength: 0).padding(.top, 4); b20} (a cross-axis edge padded)", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).padding(.top, 4); fixed("b", 20, 20) }
    }
    run("K3p VStack{a20; Spacer(minLength: 0).padding(.top, 4); b20} (one edge padded, vertical)", none) {
        VStack { fixed("a", 20, 20); Spacer(minLength: 0).padding(.top, 4); fixed("b", 20, 20) }
    }
    run("K3q HStack{a20; Spacer(minLength: 0).frame(width: 10).padding(0); b20} (frame then zero padding)", none) {
        HStack { fixed("a", 20, 20); Spacer(minLength: 0).frame(width: 10).padding(0); fixed("b", 20, 20) }
    }

    // K4: aspectRatio's single-axis and infinite branches. Control: AR1 (500x300).
    run("K4 fixed 168x95 .aspectRatio(16/9, .fit) at 500 x nil", p(500, nil)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    run("K4b fixed 168x95 .aspectRatio(16/9, .fit) at nil x 300", p(nil, 300)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    run("K4c flexible c .aspectRatio(16/9, .fit) at 500 x nil", p(500, nil)) {
        Leaf(name: "c", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    runMeasured("K4d fixed 168x95 .aspectRatio(16/9, .fit) at inf x inf", p(.infinity, .infinity)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    runMeasured("K4e fixed 168x95 .aspectRatio(16/9, .fit) at 500 x inf", p(500, .infinity)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    runMeasured("K4f flexible c .aspectRatio(16/9, .fit) at inf x inf", p(.infinity, .infinity)) {
        Leaf(name: "c", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    runMeasured("K4g flexible c .aspectRatio(16/9, .fit) at 500 x inf", p(500, .infinity)) {
        Leaf(name: "c", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
    }
    runMeasured("K4h fixed 168x95 .aspectRatio(16/9, .fill) at 500 x inf", p(500, .infinity)) {
        fixed("c", 168, 95).aspectRatio(16.0 / 9.0, contentMode: .fill)
    }
    run("K4i flexible c .aspectRatio(-1, .fit) at 100x100 (negative ratio)", p(100, 100)) {
        Leaf(name: "c", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
            .aspectRatio(-1, contentMode: .fit)
    }
    run("K4j fixed 30x30 .aspectRatio(-1, .fit) at 100x100 (negative ratio)", p(100, 100)) {
        fixed("c", 30, 30).aspectRatio(-1, contentMode: .fit)
    }

    // K5 / Z: where and at what proposal is overlay/background CONTENT placed?
    // `half` answers half its proposed width x 10 and logs its placement
    // proposal. Control K5: one half alone in the overlay.
    run("K5 control primary 60x40 .overlay{half h}", none) { fixed("primary", 60, 40).overlay { half("h") } }
    run("K5a primary 60x40 .overlay{half h; o 20x20}", none) {
        fixed("primary", 60, 40).overlay { half("h"); logged("o", 20, 20) }
    }
    run("K5b primary 60x40 .overlay{ZStack{half h; o 20x20}}", none) {
        fixed("primary", 60, 40).overlay { ZStack { half("h"); logged("o", 20, 20) } }
    }
    run("K5c primary 60x40 .overlay(alignment: .topLeading){ZStack{half h; o 20x20}}", none) {
        fixed("primary", 60, 40).overlay(alignment: .topLeading) { ZStack { half("h"); logged("o", 20, 20) } }
    }
    run("K5d primary 60x40 .overlay{HStack(0){half h; o 20x20}}", none) {
        fixed("primary", 60, 40).overlay { HStack(spacing: 0) { half("h"); logged("o", 20, 20) } }
    }
    run("K5e primary 60x40 .background{half h; o 20x20}", none) {
        fixed("primary", 60, 40).background { half("h"); logged("o", 20, 20) }
    }
    run("K5f primary 60x40 .overlay{half h .frame(width: 30)} (content answer = its proposal width)", none) {
        fixed("primary", 60, 40).overlay { half("h").frame(width: 30) }
    }
    run("K5g primary 60x40 .overlay(alignment: .topLeading){half h; o 20x20} (implicit ZStack's own alignment?)", none) {
        fixed("primary", 60, 40).overlay(alignment: .topLeading) { half("h"); logged("o", 20, 20) }
    }
    run("K5h primary 60x40 .background(alignment: .bottomTrailing){half h; o 20x20}", none) {
        fixed("primary", 60, 40).background(alignment: .bottomTrailing) { half("h"); logged("o", 20, 20) }
    }
    run("Z1 ZStack{half h; o 20x20} at 60x40 (no overlay)", p(60, 40)) { ZStack { half("h"); logged("o", 20, 20) } }
    run("Z2 ZStack(.topLeading){half h; o 20x20} at 60x40", p(60, 40)) {
        ZStack(alignment: .topLeading) { half("h"); logged("o", 20, 20) }
    }
    run("Z3 ZStack{half h; o 20x20} at nil", none) { ZStack { half("h"); logged("o", 20, 20) } }
    run("Z4 ZStack{half h; o 60x40} at 100x100 (a child as big as the ZStack)", p(100, 100)) {
        ZStack { half("h"); logged("o", 60, 40) }
    }

    // K6: List. Control: a fixed 30x30 leaf answers 30x30 at 100x100.
    run("K6 control fixed 30x30 at 100x100", p(100, 100)) { fixed("c", 30, 30) }
    run("K6a List{Text} at 100x100", p(100, 100)) { List { Text("row") } }
    run("K6b List{Text} at nil", none) { List { Text("row") } }
    run("K6c List{Text} at 100 x nil", p(100, nil)) { List { Text("row") } }
    run("K6d List{Text} at nil x 100", p(nil, 100)) { List { Text("row") } }
    runMeasured("K6e List{Text} at inf x inf", p(.infinity, .infinity)) { List { Text("row") } }
    run("K6f List{leaf l 30x30} at 100x100 (is a row laid out?)", p(100, 100)) { List { logged("l", 30, 30) } }

    // R3: a root .overlay — the only overlay/presentation pattern a hosting
    // view lays out. Control R2: the root alone is centred at (21, 40).
    for (label, anyView) in [
        ("R3 fixed r 58x20 .overlay{greedy a} root in a 100x100 host",
         AnyView(fixed("r", 58, 20).overlay {
             Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
         })),
        ("R4 fixed r 58x20 .background{greedy a} root in a 100x100 host",
         AnyView(fixed("r", 58, 20).background {
             Leaf(name: "a", minW: 0, idealW: 10, maxW: .infinity, minH: 0, idealH: 10, maxH: .infinity) { SwiftUI.Color.clear }
         })),
    ] {
        proposalsSeen = [:]; placed = [:]; order = []; calls = [:]
        let host = NSHostingView(rootView: anyView)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        let r = placed["r"]!, a = placed["a"]!
        print("\(label): r at (\(d(r.minX)), \(d(r.minY))) \(d(r.width))x\(d(r.height)); a proposed [\((proposalsSeen["a"] ?? []).joined(separator: ", "))] at (\(d(a.minX)), \(d(a.minY))) \(d(a.width))x\(d(a.height))")
    }

}

let app = NSApplication.shared

app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated { probes() }
print("DONE")
