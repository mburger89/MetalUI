// SwiftUI probe: what the flex-item fields of a LOWERED legacy element must
// answer on the proposal path — plan task 7, stage 2 (engine replacement).
// Evidence for rulings LR-AB… in
// docs/superpowers/2026-09-17-engine-replacement-decisions.md and for
// docs/superpowers/specs/2026-09-17-engine-stage-2-design.md.
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-engine-replacement-stage2.swift 2>&1 \
//     | grep -v 'Connection\]\|warning:\|deprecated\|note:'
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols. It opens small windows for group V (hit testing) and
// orders them out.
//
// METHOD. As `swiftui-engine-replacement-stage1.swift`: `size` is
// `LayoutSubview.sizeThatFits` of the whole view at the stated proposal, taken
// by the `Probe` layout, which places it at (0, 0); a `leaf` line is `Leaf`, a
// custom `Layout` answering `clamp(proposal ?? ideal, min, max)` per axis and
// recording its last placed rect; a `geometry` line is `onGeometryChange` in
// the probe's coordinate space. Every group opens with a control that must
// DIFFER from at least one of its arms (practices shape 15).
//
// Groups (each is the SwiftUI spelling a CSS item field would lower to):
//   F  — main-axis growth: `.frame(maxWidth: .infinity)` for `flexGrow`, two
//        greedy siblings over unequal content (CSS `flex-basis: auto`
//        answers base + share), a minimum's presence (`min-width: 0`), a
//        rigid sibling served first, `.fixedSize()` for `flex-shrink: 0`.
//   X  — cross-axis fill: `.frame(maxHeight: .infinity)` for `stretch` at an
//        unspecified and a concrete cross proposal, a greedy view inside a
//        hugging container, a per-child alignment spelled as a greedy frame,
//        a nil-axis frame (MC-Q finding 7), a clamped greedy frame.
//   P  — padding family: a padding larger than a fixed frame (BM-4's floor),
//        padding outside a background (margin), negative padding, padding on
//        a Text.
//   J  — justify distribution spelled with `Spacer(minLength:)`.
//   R  — reverse direction spelled as reversed children in a trailing frame.
//   C  — `containerRelativeFrame` is relative to the nearest container, not
//        the parent (percentages).
//   V  — `.hidden()` paints nothing and takes no tap (layout is stage-1 H1,
//        accessibility is accessibility-bridge-rules R9).
//   Revision 2 (critic round 1, appended; every revision-1 line is unchanged
//   and in place, C2 sits after C1):
//   C2 — a parent-relative fraction spelled with GeometryReader.
//   X11–X18 — a greedy item inside a one-child padding (grow, alignment), a
//        greedy child in a hugging ZStack, a greedy item on a hugging stack's
//        main axis.
//   F9, F10 — a greedy frame over a Text, and over a rigid stack, wider than
//        its share (a zero basis with no minimum).
//   P7–P9 — BM-4's overflow under a leading, top and centre frame alignment.
//   Y  — breaking inside a word, against CoreText's own line breaks.
//
// RECORDED 2026-09-17 07:20 PDT by the stage-2 design session, macOS 27.0
// (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit
// 0; run twice, stdout byte-identical (`diff` empty), 157 lines. stderr
// carries only the toolchain's Connection/warning noise the HOW TO RUN grep
// removes. The screen read locked (`appkit-screen-lock-state`:
// CGSSessionScreenIsLocked = 1, displayAsleep main: 1); group V sends events
// to its own windows with `NSWindow.sendEvent`, and its controls V0/V2 move,
// so the lock did not blind it.
//
// REVISION 2 RECORDED 2026-09-17 07:55 PDT by the same session (critic round
// 1), same OS and toolchain, after renaming its word-break group to Y (the
// stage-1 probe already has a B group): exit 0; run twice, stdout
// byte-identical, 235 lines, the header's OUTPUT line for line; filtered stderr
// empty. Screen locked and asleep
// (CGSSessionScreenIsLocked = 1, displayAsleep main: 1 at 07:49). The 157
// revision-1 lines appear unchanged and in order, with C2's three lines after
// C1.
//
// READING (each arm against its control; "CSS" is the legacy engine's answer
// for the legacy spelling the arm stands in for, from the engine's rules, not
// from this probe).
// - F: a greedy frame takes the rigid sibling's leftover (F1 260; F0 control
//   0 with the pair centred). Two greedy siblings share the surplus EQUALLY
//   whatever their content (F2: 150/150 over 100 and 20; CSS `flex-basis:
//   auto` answers base + share, 190/110), and a greedy frame without a
//   minimum never answers less than its child (F3: 200/100). A declared
//   minimum's PRESENCE lets it go below its child (F4: 150, the 200 child
//   overflowing centred at -25; F8 both 150). A rigid 196 sibling is served
//   first and keeps its width (F5: text frame 204). `.fixedSize()` keeps a
//   Text on one line and overflows (F7 302 wide against F6's wrapped 95).
// - X: a greedy cross frame takes the stack's own cross size at an
//   unspecified proposal (X1: 40, the tallest sibling) and the concrete one
//   when framed (X2: 100); the child inside keeps its size, centred. A greedy
//   view inside a HUGGING container fills that container's proposal (X4: the
//   VStack is 200 wide against X3's 30; CSS's fit-content column would be
//   30). A per-child alignment spelled `.frame(maxWidth: .infinity,
//   alignment: .leading)` is exact in a definite column (X5: b at 0, a
//   centred at 100) and makes an indefinite column fill its proposal (X7: 300
//   against X6's 100). A nil-axis `.frame(width: 30)` is NOT stretched by its
//   stack (X8: 30x10 at y 15); an outer greedy frame stretches it and its
//   content stays centred (X9: outer 30x40, inner frame 30x10 at y 15).
//   `.frame(maxHeight: 25)` in a 100-tall stack is 25, centred (X10).
// - P: a padding larger than a fixed frame overflows it; the frame keeps its
//   size (P1: 10x10, child at (12, 12), padding 34x34; control P0 10x10 child
//   at 0; CSS's border box floors at 34x34, BM-4). Padding outside a
//   background moves the background with the child and spaces the sibling
//   (P3: background at (8, 8), b at 36; control P2 b at 20). Negative padding
//   overlaps and its response clamps at 0 per axis (P4: a at -8, b at 4,
//   size 24x20). Padding on a Text pads it (P6: 53x36, text at (10, 10);
//   control P5 33x16).
// - J: `Spacer(minLength: 0)` between children is CSS `space-between` (J1: 0,
//   90, 180; control J0 centred at 70); `Spacer(minLength: 10)` agrees while
//   it fits (J2) and packs from the start at the minimum when it does not
//   (J3: 0, 30, 60, 80 wide at 50 — CSS `space-between` falls back to
//   `flex-start`, the same). Spacers at both ends and between are
//   `space-evenly` at gap 0 (J4: 35, 90, 145); a `Spacer(minLength: 10)`
//   between them is NOT `space-evenly` with a 10 gap (J5: 53.33, 126.67; CSS
//   50, 130), but a rigid 10-wide leaf beside a `Spacer(minLength: 0)` is
//   (J8: 50, 130). Two spacers between and one at each end are
//   `space-around` (J7: 23.33, 90, 156.67). Overflowing, spacers pack from
//   the start (J9: 0, 20, 30 at 40; CSS `space-evenly` and `space-around`
//   fall back to `center`, which would start at -5). A greedy frame beside a
//   spacer takes everything and the spacer 0 (J6: frame 180, b at 180).
// - R: reversed children in a trailing frame are CSS `row-reverse` (R1: a at
//   180, b at 150; control R0 a at 0), overflow included (R2: a at 20, b at
//   -60).
// - C: `containerRelativeFrame(.horizontal) { $0 * 0.5 }` inside a 200-wide
//   VStack is 500 wide (C1) — half of the 1000-wide host, not of the 200
//   parent (control C0: 100 at 50). SwiftUI has no parent-relative
//   percentage spelling.
// - V: `.hidden()` paints nothing (V1 white; control V0 not white) and takes
//   no tap — the tap reaches the view under it (V3: top 0, under 1; control
//   V2 top 1, under 0).
// - C2: `GeometryReader` takes the whole 200 proposal and a child sized
//   `g.size.width * 0.5` is 100 — half of the PARENT's proposal. A
//   parent-relative fraction IS spellable in SwiftUI, through a view that is
//   itself greedy; `containerRelativeFrame` (C1) is not it.
// - X11/X12: a greedy frame inside `.padding(8)` makes the padding fill its
//   stack's leftover (160 against the control's 46; a hugging CSS padding
//   layer keeps 46). X13/X14: a trailing alignment frame inside a padding
//   makes an indefinite VStack fill (300 against 100) with b at the trailing
//   edge (272). X15/X16: a greedy child makes a hugging ZStack fill (200
//   against 30). X17/X18: a greedy item on a VStack's MAIN axis makes it
//   fill a concrete proposal (200 tall against 30).
// - F9: a greedy frame over a Text wider than its 50 share is 50, the Text
//   breaking inside its word (48x48, three lines); CSS's zero-basis automatic
//   minimum keeps the word's width. F10: over a rigid 200 stack the frame is
//   200 and the row overflows (220), as CSS's automatic minimum does.
// - P7/P8/P9: the 34x34 padding overflows a 10x10 frame by the frame's
//   alignment: `.leading` centres it vertically (child at (12, 0)), `.top`
//   horizontally (child at (0, 12)), the default both (child at (0, 0)); P1's
//   `.topLeading` put the child at (12, 12).
// - Y: at every width SwiftUI's line count equals CoreText's
//   `CTTypesetterSuggestLineBreak` loop (which breaks inside a word that does
//   not fit), and its width is min(proposal, ceil(widest line WITH its
//   trailing space)): Y2/Y3 19 (18.17), Y4 11 (10.31), Y6/Y7 18 (17.25), Y9 45
//   (44.02; 40.44 without the space), and the proposal where that is wider
//   (Y5 5 against 7.86, Y8 30 against 33.31). Control Y0 (nil): one line.
//
// OUTPUT:
//
//   F0 control HStack(0){a40x10; b0x10}.frame(width:300) @nilxnil: size 300x10
//       leaf a: at (130, 0) 40x10
//       leaf b: at (170, 0) 0x10
//   F1 HStack(0){a40x10; b0x10.frame(maxWidth:.inf)}.frame(width:300) @nilxnil: size 300x10
//       leaf a: at (0, 0) 40x10
//       leaf b: at (170, 0) 0x10
//       geometry bframe: (40, 0) 260x10
//   F2 HStack(0){a100x10.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300 @300xnil: size 300x10
//       leaf a: at (25, 0) 100x10
//       leaf b: at (215, 0) 20x10
//       geometry aframe: (0, 0) 150x10
//       geometry bframe: (150, 0) 150x10
//   F3 HStack(0){a200x10.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300 @300xnil: size 300x10
//       leaf a: at (0, 0) 200x10
//       leaf b: at (240, 0) 20x10
//       geometry aframe: (0, 0) 200x10
//       geometry bframe: (200, 0) 100x10
//   F4 HStack(0){a200x10.frame(minWidth:0,maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300 @300xnil: size 300x10
//       leaf a: at (-25, 0) 200x10
//       leaf b: at (215, 0) 20x10
//       geometry aframe: (0, 0) 150x10
//       geometry bframe: (150, 0) 150x10
//   F5 HStack(0){a196x10; Text(long).frame(maxWidth:.inf)} at 400 @400xnil: size 400x32
//       leaf a: at (0, 11) 196x10
//       geometry textframe: (196, 0) 204x32
//   F6 control HStack(0){Text(long); b50x10} at 100 @100xnil: size 95x112
//       leaf b: at (45, 51) 50x10
//       geometry text: (0, 0) 45x112
//   F7 HStack(0){Text(long).fixedSize(); b50x10} at 100 @100xnil: size 302x16
//       leaf b: at (252, 3) 50x10
//       geometry text: (0, 0) 252x16
//   F8 HStack(0){a100x10.frame(minWidth:0,maxWidth:.inf); b20x10.frame(minWidth:0,maxWidth:.inf)} at 300 @300xnil: size 300x10
//       leaf a: at (25, 0) 100x10
//       leaf b: at (215, 0) 20x10
//       geometry aframe: (0, 0) 150x10
//       geometry bframe: (150, 0) 150x10
//   X0 control HStack(0){a20x40; b20x10} @nilxnil: size 40x40
//       leaf a: at (0, 0) 20x40
//       leaf b: at (20, 15) 20x10
//   X1 HStack(0){a20x40; b20x10.frame(maxHeight:.inf)} @nilxnil: size 40x40
//       leaf a: at (0, 0) 20x40
//       leaf b: at (20, 15) 20x10
//       geometry bframe: (20, 0) 20x40
//   X2 HStack(0){a20x40; b20x10.frame(maxHeight:.inf)}.frame(height:100) @nilxnil: size 40x100
//       leaf a: at (0, 30) 20x40
//       leaf b: at (20, 45) 20x10
//       geometry bframe: (20, 0) 20x100
//   X3 control HStack(0){VStack(0){a30x10; b0x10}} at 200 @200xnil: size 30x20
//       leaf a: at (0, 0) 30x10
//       leaf b: at (15, 10) 0x10
//       geometry vstack: (0, 0) 30x20
//   X4 HStack(0){VStack(0){a30x10; b0x10.frame(maxWidth:.inf)}} at 200 @200xnil: size 200x20
//       leaf a: at (85, 0) 30x10
//       leaf b: at (100, 10) 0x10
//       geometry vstack: (0, 0) 200x20
//   X5 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.leading)}.frame(width:300) @nilxnil: size 300x20
//       leaf a: at (100, 0) 100x10
//       leaf b: at (0, 10) 20x10
//       geometry bframe: (0, 10) 300x10
//   X6 control VStack(0){a100x10; b20x10} at 300 @300xnil: size 100x20
//       leaf a: at (0, 0) 100x10
//       leaf b: at (40, 10) 20x10
//       geometry vstack: (0, 0) 100x20
//   X7 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.leading)} at 300 @300xnil: size 300x20
//       leaf a: at (100, 0) 100x10
//       leaf b: at (0, 10) 20x10
//       geometry vstack: (0, 0) 300x20
//   X8 HStack(0){a20x40; c10x10.frame(width:30)} @nilxnil: size 50x40
//       leaf a: at (0, 0) 20x40
//       leaf c: at (30, 15) 10x10
//       geometry cframe: (20, 15) 30x10
//   X9 HStack(0){a20x40; c10x10.frame(width:30).frame(maxHeight:.inf)} @nilxnil: size 50x40
//       leaf a: at (0, 0) 20x40
//       leaf c: at (30, 15) 10x10
//       geometry cframe: (20, 15) 30x10
//       geometry outer: (20, 0) 30x40
//   X10 HStack(0){a20x40; b20x10.frame(maxHeight:25)}.frame(height:100) @nilxnil: size 40x100
//       leaf a: at (0, 30) 20x40
//       leaf b: at (20, 45) 20x10
//       geometry bframe: (20, 37.50) 20x25
//   P0 control c10x10.frame(width:10,height:10,.topLeading) @nilxnil: size 10x10
//       leaf c: at (0, 0) 10x10
//   P1 c10x10.padding(12).frame(width:10,height:10,.topLeading) @nilxnil: size 10x10
//       leaf c: at (12, 12) 10x10
//       geometry padding: (0, 0) 34x34
//   P2 control HStack(0){a20x20.background; b20x20} @nilxnil: size 40x20
//       leaf a: at (0, 0) 20x20
//       leaf b: at (20, 0) 20x20
//       geometry abg: (0, 0) 20x20
//   P3 HStack(0){a20x20.background.padding(8); b20x20} @nilxnil: size 56x36
//       leaf a: at (8, 8) 20x20
//       leaf b: at (36, 8) 20x20
//       geometry abg: (8, 8) 20x20
//   P4 HStack(0){a20x20.background.padding(-8); b20x20} @nilxnil: size 24x20
//       leaf a: at (-8, 0) 20x20
//       leaf b: at (4, 0) 20x20
//       geometry abg: (-8, 0) 20x20
//   P5 control Text("alpha") @nilxnil: size 33x16
//   P6 Text("alpha").padding(10) @nilxnil: size 53x36
//       geometry text: (10, 10) 33x16
//   J0 control HStack(0){a20; b20; c20}.frame(width:200) @nilxnil: size 200x10
//       leaf a: at (70, 0) 20x10
//       leaf b: at (90, 0) 20x10
//       leaf c: at (110, 0) 20x10
//   J1 HStack(0){a; Spacer(0); b; Spacer(0); c} at 200 (space-between) @200xnil: size 200x10
//       leaf a: at (0, 0) 20x10
//       leaf b: at (90, 0) 20x10
//       leaf c: at (180, 0) 20x10
//   J2 HStack(0){a; Spacer(10); b; Spacer(10); c} at 200 (space-between, gap 10) @200xnil: size 200x10
//       leaf a: at (0, 0) 20x10
//       leaf b: at (90, 0) 20x10
//       leaf c: at (180, 0) 20x10
//   J3 HStack(0){a; Spacer(10); b; Spacer(10); c} at 50 (overflow, gap 10) @50xnil: size 80x10
//       leaf a: at (0, 0) 20x10
//       leaf b: at (30, 0) 20x10
//       leaf c: at (60, 0) 20x10
//   J4 HStack(0){Spacer(0); a; Spacer(0); b; Spacer(0); c; Spacer(0)} at 200 (space-evenly) @200xnil: size 200x10
//       leaf a: at (35, 0) 20x10
//       leaf b: at (90, 0) 20x10
//       leaf c: at (145, 0) 20x10
//   J5 HStack(0){Spacer(0); a; Spacer(10); b; Spacer(0)} at 200 (space-evenly, gap 10) @200xnil: size 200x10
//       leaf a: at (53.33, 0) 20x10
//       leaf b: at (126.67, 0) 20x10
//   J7 HStack(0){S; a; S; S; b; S; S; c; S} at 200 (space-around, spacers minLength 0) @200xnil: size 200.00x10
//       leaf a: at (23.33, 0) 20x10
//       leaf b: at (90, 0) 20x10
//       leaf c: at (156.67, 0) 20x10
//   J8 HStack(0){S; a; S; g10; b; S} at 200 (space-evenly, gap as a rigid 10 leaf) @200xnil: size 200x10
//       leaf a: at (50, 0) 20x10
//       leaf g: at (120, 5) 10x0
//       leaf b: at (130, 0) 20x10
//   J9 HStack(0){S; a; S; g10; b; S} at 40 (space-evenly overflow) @40xnil: size 50x10
//       leaf a: at (0, 0) 20x10
//       leaf g: at (20, 5) 10x0
//       leaf b: at (30, 0) 20x10
//   J6 HStack(0){a.frame(maxWidth:.inf); Spacer(0); b} at 200 (greedy beside a spacer) @200xnil: size 200x10
//       leaf a: at (80, 0) 20x10
//       leaf b: at (180, 0) 20x10
//       geometry aframe: (0, 0) 180x10
//   R0 control HStack(0){a20; b30}.frame(width:200,.leading) @nilxnil: size 200x10
//       leaf a: at (0, 0) 20x10
//       leaf b: at (20, 0) 30x10
//   R1 HStack(0){b30; a20}.frame(width:200,.trailing) @nilxnil: size 200x10
//       leaf b: at (150, 0) 30x10
//       leaf a: at (180, 0) 20x10
//   R2 HStack(0){b80; a80}.frame(width:100,.trailing) @nilxnil: size 100x10
//       leaf b: at (-60, 0) 80x10
//       leaf a: at (20, 0) 80x10
//   C0 control VStack(0){Color.frame(width:100,height:10)}.frame(width:200) @nilxnil: size 200x10
//       geometry color: (50, 0) 100x10
//   C1 VStack(0){Color.containerRelativeFrame(.horizontal){w*0.5}.frame(height:10)}.frame(width:200) @nilxnil: size 200x10
//       geometry color: (-150, 0) 500x10
//   C2 VStack(0){GeometryReader{Color.frame(width:g.w*0.5,height:10)}.frame(height:10)}.frame(width:200) @nilxnil: size 200x10
//       geometry color: (0, 0) 100x10
//       geometry reader: (0, 0) 200x10
//   V0 control Color.red.frame(20x20): centre pixel not white [255, 66, 69]
//   V1 Color.red.frame(20x20).hidden(): centre pixel white (255,255,255)
//   V2 control ZStack{blue.onTap(under); red.onTap(top)}: top 1, under 0
//   V3 ZStack{blue.onTap(under); red.onTap(top).hidden()}: top 0, under 1
//   X11 control HStack(0){a40x10; b30x10.padding(8)} at 200 @200xnil: size 86x26
//       leaf a: at (0, 8) 40x10
//       leaf b: at (48, 8) 30x10
//       geometry pad: (40, 0) 46x26
//   X12 HStack(0){a40x10; b30x10.frame(maxWidth:.inf).padding(8)} at 200 @200xnil: size 200x26
//       leaf a: at (0, 8) 40x10
//       leaf b: at (105, 8) 30x10
//       geometry pad: (40, 0) 160x26
//   X13 control VStack(0){a100x10; b20x10.padding(8)} at 300 @300xnil: size 100x36
//       leaf a: at (0, 0) 100x10
//       leaf b: at (40, 18) 20x10
//       geometry pad: (32, 10) 36x26
//       geometry vstack: (0, 0) 100x36
//   X14 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.trailing).padding(8)} at 300 @300xnil: size 300x36
//       leaf a: at (100, 0) 100x10
//       leaf b: at (272, 18) 20x10
//       geometry pad: (0, 10) 300x26
//       geometry vstack: (0, 0) 300x36
//   X15 control HStack(0){ZStack{a30x10; b0x10}} at 200 @200xnil: size 30x10
//       leaf a: at (0, 0) 30x10
//       leaf b: at (15, 0) 0x10
//       geometry zstack: (0, 0) 30x10
//   X16 HStack(0){ZStack{a30x10; b0x10.frame(maxWidth:.inf)}} at 200 @200xnil: size 200x10
//       leaf a: at (85, 0) 30x10
//       leaf b: at (100, 0) 0x10
//       geometry zstack: (0, 0) 200x10
//   X17 control VStack(0){a30x20; b30x10} at 200x200 @200x200: size 30x30
//       leaf a: at (0, 0) 30x20
//       leaf b: at (0, 20) 30x10
//       geometry vstack: (0, 0) 30x30
//   X18 VStack(0){a30x20; b30x10.frame(maxHeight:.inf)} at 200x200 @200x200: size 30x200
//       leaf a: at (0, 0) 30x20
//       leaf b: at (0, 105) 30x10
//       geometry bframe: (0, 20) 30x180
//       geometry vstack: (0, 0) 30x200
//   F9 HStack(0){Text(alphabravocharlie).frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 100 @100xnil: size 100x48
//       leaf b: at (65, 19) 20x10
//       geometry bframe: (50, 19) 50x10
//       geometry text: (1, 0) 48x48
//       geometry textframe: (0, 0) 50x48
//   F10 HStack(0){HStack(0){a100;c100}.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 150 @150xnil: size 220x10
//       leaf a: at (0, 0) 100x10
//       leaf c: at (100, 0) 100x10
//       leaf b: at (200, 0) 20x10
//       geometry bframe: (200, 0) 20x10
//       geometry innerframe: (0, 0) 200x10
//   P7 c10x10.padding(12).frame(width:10,height:10,.leading) @nilxnil: size 10x10
//       leaf c: at (12, 0) 10x10
//       geometry padding: (0, -12) 34x34
//   P8 c10x10.padding(12).frame(width:10,height:10,.top) @nilxnil: size 10x10
//       leaf c: at (0, 12) 10x10
//       geometry padding: (-12, 0) 34x34
//   P9 c10x10.padding(12).frame(width:10,height:10) @nilxnil: size 10x10
//       leaf c: at (0, 0) 10x10
//       geometry padding: (-12, -12) 34x34
//   Y0 control Text(alpha) at nil @nilxnil: size 33x16
//       ct n/a (nil proposal)
//   Y1 Text(alpha) at 33 @33xnil: size 33x16
//       ct lines 1 widest 32.84 with trailing space 32.84
//   Y2 Text(alpha) at 25 @25xnil: size 19x32
//       ct lines 2 widest 18.17 with trailing space 18.17
//   Y3 Text(alpha) at 20 @20xnil: size 19x32
//       ct lines 2 widest 18.17 with trailing space 18.17
//   Y4 Text(alpha) at 12 @12xnil: size 11x64
//       ct lines 4 widest 10.31 with trailing space 10.31
//   Y5 Text(alpha) at 5 @5xnil: size 5x80
//       ct lines 5 widest 7.86 with trailing space 7.86
//   Y6 Text(Short) at 21 @21xnil: size 18x32
//       ct lines 2 widest 17.25 with trailing space 17.25
//   Y7 Text(Short) at 18 @18xnil: size 18x32
//       ct lines 2 widest 17.25 with trailing space 17.25
//   Y8 Text(long) at 30 @30xnil: size 30x192
//       ct lines 12 widest 29.95 with trailing space 33.31
//   Y9 Text(long) at 45 @45xnil: size 45x112
//       ct lines 7 widest 40.44 with trailing space 44.02
//   DONE

import AppKit
import SwiftUI
import CoreText

func d(_ v: CGFloat?) -> String {
    guard let v else { return "nil" }
    if v == .infinity { return "inf" }
    return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
}
func fmt(_ s: CGSize) -> String { "\(d(s.width))x\(d(s.height))" }
func fmt(_ p: ProposedViewSize) -> String { "\(d(p.width))x\(d(p.height))" }

nonisolated(unsafe) var placed: [String: CGRect] = [:]
nonisolated(unsafe) var order: [String] = []
nonisolated(unsafe) var lastSize: CGSize = .zero
nonisolated(unsafe) var geometry: [String: CGRect] = [:]

struct Probe: Layout {
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        lastSize = size
        return size
    }
    func placeSubviews(in _: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        lastSize = subviews[0].sizeThatFits(proposal)
        subviews[0].place(at: .zero, anchor: .topLeading, proposal: proposal)
    }
}

struct Leaf: Layout {
    let name: String
    var minW: CGFloat = 0, idealW: CGFloat, maxW: CGFloat
    var minH: CGFloat = 0, idealH: CGFloat, maxH: CGFloat
    func sizeThatFits(proposal p: ProposedViewSize, subviews _: Subviews, cache: inout ()) -> CGSize {
        if placed[name] == nil, !order.contains(name) { order.append(name) }
        return CGSize(width: min(max(p.width ?? idealW, minW), maxW),
                      height: min(max(p.height ?? idealH, minH), maxH))
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if !order.contains(name) { order.append(name) }
        placed[name] = bounds
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

func fixed(_ n: String, _ w: CGFloat, _ h: CGFloat) -> some View {
    Leaf(name: n, minW: w, idealW: w, maxW: w, minH: h, idealH: h, maxH: h) { SwiftUI.Color.clear }
}

extension View {
    func geo(_ n: String) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named("probe")) } action: { geometry[n] = $0 }
    }
}

@MainActor func run<V: View>(_ label: String, _ proposal: ProposedViewSize, @ViewBuilder _ view: () -> V) {
    placed = [:]; order = []; geometry = [:]
    lastSize = CGSize(width: -1, height: -1)
    let host = NSHostingView(rootView: Probe(proposal: proposal) { view().coordinateSpace(.named("probe")) })
    host.frame = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    host.layoutSubtreeIfNeeded()
    print("\(label) @\(fmt(proposal)): size \(fmt(lastSize))")
    for n in order {
        let at = placed[n].map { "at (\(d($0.minX)), \(d($0.minY))) \(d($0.width))x\(d($0.height))" } ?? "not placed"
        print("    leaf \(n): \(at)")
    }
    for (n, r) in geometry.sorted(by: { $0.key < $1.key }) {
        print("    geometry \(n): (\(d(r.minX)), \(d(r.minY))) \(d(r.width))x\(d(r.height))")
    }
    fflush(stdout)
}

let long = "alpha bravo charlie delta echo foxtrot golf"
let none = ProposedViewSize(width: nil, height: nil)
func w(_ x: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: x, height: nil) }
func p(_ x: CGFloat?, _ y: CGFloat?) -> ProposedViewSize { ProposedViewSize(width: x, height: y) }

@MainActor func layoutProbes() {
    // F — main axis. Control F0: nothing greedy; the pair is centred in 300.
    run("F0 control HStack(0){a40x10; b0x10}.frame(width:300)", none) {
        HStack(spacing: 0) { fixed("a", 40, 10); fixed("b", 0, 10) }.frame(width: 300)
    }
    run("F1 HStack(0){a40x10; b0x10.frame(maxWidth:.inf)}.frame(width:300)", none) {
        HStack(spacing: 0) { fixed("a", 40, 10); fixed("b", 0, 10).frame(maxWidth: .infinity).geo("bframe") }.frame(width: 300)
    }
    run("F2 HStack(0){a100x10.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300", w(300)) {
        HStack(spacing: 0) {
            fixed("a", 100, 10).frame(maxWidth: .infinity).geo("aframe")
            fixed("b", 20, 10).frame(maxWidth: .infinity).geo("bframe")
        }
    }
    run("F3 HStack(0){a200x10.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300", w(300)) {
        HStack(spacing: 0) {
            fixed("a", 200, 10).frame(maxWidth: .infinity).geo("aframe")
            fixed("b", 20, 10).frame(maxWidth: .infinity).geo("bframe")
        }
    }
    run("F4 HStack(0){a200x10.frame(minWidth:0,maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 300", w(300)) {
        HStack(spacing: 0) {
            fixed("a", 200, 10).frame(minWidth: 0, maxWidth: .infinity).geo("aframe")
            fixed("b", 20, 10).frame(maxWidth: .infinity).geo("bframe")
        }
    }
    run("F5 HStack(0){a196x10; Text(long).frame(maxWidth:.inf)} at 400", w(400)) {
        HStack(spacing: 0) { fixed("a", 196, 10); Text(long).frame(maxWidth: .infinity).geo("textframe") }
    }
    run("F6 control HStack(0){Text(long); b50x10} at 100", w(100)) {
        HStack(spacing: 0) { Text(long).geo("text"); fixed("b", 50, 10) }
    }
    run("F7 HStack(0){Text(long).fixedSize(); b50x10} at 100", w(100)) {
        HStack(spacing: 0) { Text(long).fixedSize().geo("text"); fixed("b", 50, 10) }
    }
    run("F8 HStack(0){a100x10.frame(minWidth:0,maxWidth:.inf); b20x10.frame(minWidth:0,maxWidth:.inf)} at 300", w(300)) {
        HStack(spacing: 0) {
            fixed("a", 100, 10).frame(minWidth: 0, maxWidth: .infinity).geo("aframe")
            fixed("b", 20, 10).frame(minWidth: 0, maxWidth: .infinity).geo("bframe")
        }
    }

    // X — cross axis. Control X0: b centred, 10 tall.
    run("X0 control HStack(0){a20x40; b20x10}", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("b", 20, 10) }
    }
    run("X1 HStack(0){a20x40; b20x10.frame(maxHeight:.inf)}", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("b", 20, 10).frame(maxHeight: .infinity).geo("bframe") }
    }
    run("X2 HStack(0){a20x40; b20x10.frame(maxHeight:.inf)}.frame(height:100)", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("b", 20, 10).frame(maxHeight: .infinity).geo("bframe") }.frame(height: 100)
    }
    run("X3 control HStack(0){VStack(0){a30x10; b0x10}} at 200", w(200)) {
        HStack(spacing: 0) { VStack(spacing: 0) { fixed("a", 30, 10); fixed("b", 0, 10) }.geo("vstack") }
    }
    run("X4 HStack(0){VStack(0){a30x10; b0x10.frame(maxWidth:.inf)}} at 200", w(200)) {
        HStack(spacing: 0) { VStack(spacing: 0) { fixed("a", 30, 10); fixed("b", 0, 10).frame(maxWidth: .infinity) }.geo("vstack") }
    }
    run("X5 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.leading)}.frame(width:300)", none) {
        VStack(spacing: 0) { fixed("a", 100, 10); fixed("b", 20, 10).frame(maxWidth: .infinity, alignment: .leading).geo("bframe") }.frame(width: 300)
    }
    run("X6 control VStack(0){a100x10; b20x10} at 300", w(300)) {
        VStack(spacing: 0) { fixed("a", 100, 10); fixed("b", 20, 10) }.geo("vstack")
    }
    run("X7 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.leading)} at 300", w(300)) {
        VStack(spacing: 0) { fixed("a", 100, 10); fixed("b", 20, 10).frame(maxWidth: .infinity, alignment: .leading) }.geo("vstack")
    }
    run("X8 HStack(0){a20x40; c10x10.frame(width:30)}", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("c", 10, 10).frame(width: 30).geo("cframe") }
    }
    run("X9 HStack(0){a20x40; c10x10.frame(width:30).frame(maxHeight:.inf)}", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("c", 10, 10).frame(width: 30).geo("cframe").frame(maxHeight: .infinity).geo("outer") }
    }
    run("X10 HStack(0){a20x40; b20x10.frame(maxHeight:25)}.frame(height:100)", none) {
        HStack(spacing: 0) { fixed("a", 20, 40); fixed("b", 20, 10).frame(maxHeight: 25).geo("bframe") }.frame(height: 100)
    }

    // P — padding family. Control P0: the fixed frame alone.
    run("P0 control c10x10.frame(width:10,height:10,.topLeading)", none) {
        fixed("c", 10, 10).frame(width: 10, height: 10, alignment: .topLeading)
    }
    run("P1 c10x10.padding(12).frame(width:10,height:10,.topLeading)", none) {
        fixed("c", 10, 10).padding(12).geo("padding").frame(width: 10, height: 10, alignment: .topLeading)
    }
    run("P2 control HStack(0){a20x20.background; b20x20}", none) {
        HStack(spacing: 0) { fixed("a", 20, 20).background(SwiftUI.Color.red).geo("abg"); fixed("b", 20, 20) }
    }
    run("P3 HStack(0){a20x20.background.padding(8); b20x20}", none) {
        HStack(spacing: 0) { fixed("a", 20, 20).background(SwiftUI.Color.red).geo("abg").padding(8); fixed("b", 20, 20) }
    }
    run("P4 HStack(0){a20x20.background.padding(-8); b20x20}", none) {
        HStack(spacing: 0) { fixed("a", 20, 20).background(SwiftUI.Color.red).geo("abg").padding(-8); fixed("b", 20, 20) }
    }
    run("P5 control Text(\"alpha\")", none) { Text("alpha") }
    run("P6 Text(\"alpha\").padding(10)", none) { Text("alpha").geo("text").padding(10) }

    // J — justify distribution. Control J0: centred, no spacers.
    run("J0 control HStack(0){a20; b20; c20}.frame(width:200)", none) {
        HStack(spacing: 0) { fixed("a", 20, 10); fixed("b", 20, 10); fixed("c", 20, 10) }.frame(width: 200)
    }
    run("J1 HStack(0){a; Spacer(0); b; Spacer(0); c} at 200 (space-between)", w(200)) {
        HStack(spacing: 0) { fixed("a", 20, 10); Spacer(minLength: 0); fixed("b", 20, 10); Spacer(minLength: 0); fixed("c", 20, 10) }
    }
    run("J2 HStack(0){a; Spacer(10); b; Spacer(10); c} at 200 (space-between, gap 10)", w(200)) {
        HStack(spacing: 0) { fixed("a", 20, 10); Spacer(minLength: 10); fixed("b", 20, 10); Spacer(minLength: 10); fixed("c", 20, 10) }
    }
    run("J3 HStack(0){a; Spacer(10); b; Spacer(10); c} at 50 (overflow, gap 10)", w(50)) {
        HStack(spacing: 0) { fixed("a", 20, 10); Spacer(minLength: 10); fixed("b", 20, 10); Spacer(minLength: 10); fixed("c", 20, 10) }
    }
    run("J4 HStack(0){Spacer(0); a; Spacer(0); b; Spacer(0); c; Spacer(0)} at 200 (space-evenly)", w(200)) {
        HStack(spacing: 0) {
            Spacer(minLength: 0); fixed("a", 20, 10); Spacer(minLength: 0); fixed("b", 20, 10)
            Spacer(minLength: 0); fixed("c", 20, 10); Spacer(minLength: 0)
        }
    }
    run("J5 HStack(0){Spacer(0); a; Spacer(10); b; Spacer(0)} at 200 (space-evenly, gap 10)", w(200)) {
        HStack(spacing: 0) { Spacer(minLength: 0); fixed("a", 20, 10); Spacer(minLength: 10); fixed("b", 20, 10); Spacer(minLength: 0) }
    }
    run("J7 HStack(0){S; a; S; S; b; S; S; c; S} at 200 (space-around, spacers minLength 0)", w(200)) {
        HStack(spacing: 0) {
            Spacer(minLength: 0); fixed("a", 20, 10); Spacer(minLength: 0); Spacer(minLength: 0); fixed("b", 20, 10)
            Spacer(minLength: 0); Spacer(minLength: 0); fixed("c", 20, 10); Spacer(minLength: 0)
        }
    }
    run("J8 HStack(0){S; a; S; g10; b; S} at 200 (space-evenly, gap as a rigid 10 leaf)", w(200)) {
        HStack(spacing: 0) { Spacer(minLength: 0); fixed("a", 20, 10); Spacer(minLength: 0); fixed("g", 10, 0); fixed("b", 20, 10); Spacer(minLength: 0) }
    }
    run("J9 HStack(0){S; a; S; g10; b; S} at 40 (space-evenly overflow)", w(40)) {
        HStack(spacing: 0) { Spacer(minLength: 0); fixed("a", 20, 10); Spacer(minLength: 0); fixed("g", 10, 0); fixed("b", 20, 10); Spacer(minLength: 0) }
    }
    run("J6 HStack(0){a.frame(maxWidth:.inf); Spacer(0); b} at 200 (greedy beside a spacer)", w(200)) {
        HStack(spacing: 0) { fixed("a", 20, 10).frame(maxWidth: .infinity).geo("aframe"); Spacer(minLength: 0); fixed("b", 20, 10) }
    }

    // R — reverse. Control R0: declaration order at the leading edge.
    run("R0 control HStack(0){a20; b30}.frame(width:200,.leading)", none) {
        HStack(spacing: 0) { fixed("a", 20, 10); fixed("b", 30, 10) }.frame(width: 200, alignment: .leading)
    }
    run("R1 HStack(0){b30; a20}.frame(width:200,.trailing)", none) {
        HStack(spacing: 0) { fixed("b", 30, 10); fixed("a", 20, 10) }.frame(width: 200, alignment: .trailing)
    }
    run("R2 HStack(0){b80; a80}.frame(width:100,.trailing)", none) {
        HStack(spacing: 0) { fixed("b", 80, 10); fixed("a", 80, 10) }.frame(width: 100, alignment: .trailing)
    }

    // C — percentages. Control C0: an absolute half of the 200 parent.
    run("C0 control VStack(0){Color.frame(width:100,height:10)}.frame(width:200)", none) {
        VStack(spacing: 0) { SwiftUI.Color.red.frame(width: 100, height: 10).geo("color") }.frame(width: 200)
    }
    run("C1 VStack(0){Color.containerRelativeFrame(.horizontal){w*0.5}.frame(height:10)}.frame(width:200)", none) {
        VStack(spacing: 0) {
            SwiftUI.Color.red.containerRelativeFrame(.horizontal) { length, _ in length * 0.5 }.frame(height: 10).geo("color")
        }.frame(width: 200)
    }
    // C2 (critic round 1, finding 15): a parent-relative fraction IS spellable
    // with GeometryReader, which itself takes the whole proposal.
    run("C2 VStack(0){GeometryReader{Color.frame(width:g.w*0.5,height:10)}.frame(height:10)}.frame(width:200)", none) {
        VStack(spacing: 0) {
            GeometryReader { g in
                SwiftUI.Color.red.frame(width: g.size.width * 0.5, height: 10).geo("color")
            }.frame(height: 10).geo("reader")
        }.frame(width: 200)
    }
}

// Revision 2 (critic round 1): arms appended after C2 so the earlier output
// lines are unchanged.
@MainActor func revisionTwoProbes() {
    // X11-X16 — a greedy item inside a HUGGING one-child wrapper (finding 2),
    // inside a hugging ZStack (finding 13), and on a hugging stack's main axis
    // (cause R, finding 13). Each arm follows its control.
    run("X11 control HStack(0){a40x10; b30x10.padding(8)} at 200", w(200)) {
        HStack(spacing: 0) { fixed("a", 40, 10); fixed("b", 30, 10).padding(8).geo("pad") }
    }
    run("X12 HStack(0){a40x10; b30x10.frame(maxWidth:.inf).padding(8)} at 200", w(200)) {
        HStack(spacing: 0) { fixed("a", 40, 10); fixed("b", 30, 10).frame(maxWidth: .infinity).padding(8).geo("pad") }
    }
    run("X13 control VStack(0){a100x10; b20x10.padding(8)} at 300", w(300)) {
        VStack(spacing: 0) { fixed("a", 100, 10); fixed("b", 20, 10).padding(8).geo("pad") }.geo("vstack")
    }
    run("X14 VStack(0){a100x10; b20x10.frame(maxWidth:.inf,alignment:.trailing).padding(8)} at 300", w(300)) {
        VStack(spacing: 0) { fixed("a", 100, 10); fixed("b", 20, 10).frame(maxWidth: .infinity, alignment: .trailing).padding(8).geo("pad") }.geo("vstack")
    }
    run("X15 control HStack(0){ZStack{a30x10; b0x10}} at 200", w(200)) {
        HStack(spacing: 0) { ZStack { fixed("a", 30, 10); fixed("b", 0, 10) }.geo("zstack") }
    }
    run("X16 HStack(0){ZStack{a30x10; b0x10.frame(maxWidth:.inf)}} at 200", w(200)) {
        HStack(spacing: 0) { ZStack { fixed("a", 30, 10); fixed("b", 0, 10).frame(maxWidth: .infinity) }.geo("zstack") }
    }
    run("X17 control VStack(0){a30x20; b30x10} at 200x200", p(200, 200)) {
        VStack(spacing: 0) { fixed("a", 30, 20); fixed("b", 30, 10) }.geo("vstack")
    }
    run("X18 VStack(0){a30x20; b30x10.frame(maxHeight:.inf)} at 200x200", p(200, 200)) {
        VStack(spacing: 0) { fixed("a", 30, 20); fixed("b", 30, 10).frame(maxHeight: .infinity).geo("bframe") }.geo("vstack")
    }

    // F9-F10 — a zero-basis grower with no minimum (finding 3): a Text whose
    // word is wider than its share, and a rigid container wider than its share.
    run("F9 HStack(0){Text(alphabravocharlie).frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 100", w(100)) {
        HStack(spacing: 0) {
            Text("alphabravocharlie").geo("text").frame(maxWidth: .infinity).geo("textframe")
            fixed("b", 20, 10).frame(maxWidth: .infinity).geo("bframe")
        }
    }
    run("F10 HStack(0){HStack(0){a100;c100}.frame(maxWidth:.inf); b20x10.frame(maxWidth:.inf)} at 150", w(150)) {
        HStack(spacing: 0) {
            HStack(spacing: 0) { fixed("a", 100, 10); fixed("c", 100, 10) }.frame(maxWidth: .infinity).geo("innerframe")
            fixed("b", 20, 10).frame(maxWidth: .infinity).geo("bframe")
        }
    }

    // P7-P9 — BM-4's floor under the alignments a lowered Row (.leading: main
    // flex-start, cross centre), Column (.top) and centred frame use (finding 13).
    run("P7 c10x10.padding(12).frame(width:10,height:10,.leading)", none) {
        fixed("c", 10, 10).padding(12).geo("padding").frame(width: 10, height: 10, alignment: .leading)
    }
    run("P8 c10x10.padding(12).frame(width:10,height:10,.top)", none) {
        fixed("c", 10, 10).padding(12).geo("padding").frame(width: 10, height: 10, alignment: .top)
    }
    run("P9 c10x10.padding(12).frame(width:10,height:10)", none) {
        fixed("c", 10, 10).padding(12).geo("padding").frame(width: 10, height: 10)
    }
}

// Y — breaking inside a word (critic round 1, finding 14). Each arm prints
// SwiftUI's answer and CoreText's `CTTypesetterSuggestLineBreak` loop at the
// same width in the 13pt system font (`ct lines N widest W with trailing space
// H`: the widest line without, and with, its trailing whitespace), so an agreement is a reading, not a guess.
@MainActor func coreTextLines(_ string: String, _ width: CGFloat) -> String {
    let font = NSFont.systemFont(ofSize: 13)
    let attributed = NSAttributedString(string: string, attributes: [.font: font])
    let typesetter = CTTypesetterCreateWithAttributedString(attributed)
    var start = 0, lines = 0
    var widest: CGFloat = 0, widestHung: CGFloat = 0
    while start < attributed.length {
        let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
        let full = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        widest = max(widest, full - CGFloat(CTLineGetTrailingWhitespaceWidth(line)))
        widestHung = max(widestHung, full)
        lines += 1
        start += max(count, 1)
    }
    return "ct lines \(lines) widest \(String(format: "%.2f", widest)) with trailing space \(String(format: "%.2f", widestHung))"
}

@MainActor func breakProbes() {
    let arms: [(String, String, CGFloat?)] = [
        ("Y0 control Text(alpha) at nil", "alpha", nil),
        ("Y1 Text(alpha) at 33", "alpha", 33),
        ("Y2 Text(alpha) at 25", "alpha", 25),
        ("Y3 Text(alpha) at 20", "alpha", 20),
        ("Y4 Text(alpha) at 12", "alpha", 12),
        ("Y5 Text(alpha) at 5", "alpha", 5),
        ("Y6 Text(Short) at 21", "Short", 21),
        ("Y7 Text(Short) at 18", "Short", 18),
        ("Y8 Text(long) at 30", long, 30),
        ("Y9 Text(long) at 45", long, 45),
    ]
    for (label, string, width) in arms {
        run(label, w(width)) { Text(string) }
        print("    \(width.map { coreTextLines(string, $0) } ?? "ct n/a (nil proposal)")")
        fflush(stdout)
    }
}

// V — hidden: paint and hit testing.

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Count {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static func bump(_ k: String) { hits[k, default: 0] += 1 }
    static func take(_ k: String) -> Int { let v = hits[k, default: 0]; hits[k] = 0; return v }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func click<V: View>(_ label: String, _ view: V) {
    _ = Count.take("top"); _ = Count.take("under")
    let win = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                       styleMask: [.titled], backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = FirstMouseHost(rootView: view)
    win.makeKeyAndOrderFront(nil)
    spin()
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: CGPoint(x: 100, y: 100), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: win.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    win.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    win.sendEvent(ev(.leftMouseUp))
    spin()
    print("\(label): top \(Count.take("top")), under \(Count.take("under"))")
    win.orderOut(nil)
    fflush(stdout)
}

@MainActor func centrePixel<V: View>(_ label: String, _ view: V) {
    let root = ZStack { SwiftUI.Color.white; view }.frame(width: 40, height: 40)
    let host = NSHostingView(rootView: root)
    host.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB)
    let name: String
    if let c {
        let rgb = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        name = rgb == [255, 255, 255] ? "white (255,255,255)" : "not white \(rgb)"
    } else { name = "?" }
    print("\(label): centre pixel \(name)")
    fflush(stdout)
}

@MainActor func hiddenProbes() {
    centrePixel("V0 control Color.red.frame(20x20)", SwiftUI.Color.red.frame(width: 20, height: 20))
    centrePixel("V1 Color.red.frame(20x20).hidden()", SwiftUI.Color.red.frame(width: 20, height: 20).hidden())
    click("V2 control ZStack{blue.onTap(under); red.onTap(top)}", ZStack {
        SwiftUI.Color.blue.onTapGesture { Count.bump("under") }
        SwiftUI.Color.red.onTapGesture { Count.bump("top") }
    })
    click("V3 ZStack{blue.onTap(under); red.onTap(top).hidden()}", ZStack {
        SwiftUI.Color.blue.onTapGesture { Count.bump("under") }
        SwiftUI.Color.red.onTapGesture { Count.bump("top") }.hidden()
    })
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    layoutProbes()
    hiddenProbes()
    revisionTwoProbes()
    breakProbes()
}
print("DONE")
