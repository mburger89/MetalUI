// SwiftUI probe: Liquid Glass (`glassEffect`), item LG; rulings LG-* in
// docs/superpowers/2026-10-23-liquid-glass-decisions.md, spec
// docs/superpowers/specs/2026-10-23-liquid-glass-design.md.
//
// HOW TO RUN (unlocked screen for groups W; check first:
//   xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate
//   prints no CGSSessionScreenIsLocked line and `displayAsleep main: 0`):
//
//   xcrun swiftc docs/probes/swiftui-liquid-glass.swift -o /tmp/lg-probe && /tmp/lg-probe 2>&1 | grep -v 'Connection\]'
//   (`--no-window` skips W; screencapture needs the screen-recording grant)
//
// GROUPS.
//   A  API surface by `swiftc -typecheck` of one-line snippets, positive control + separating arm.
//   P  DefaultGlassEffectShape.path(in:), read by Path.contains on a grid: is it a capsule?
//   R  ImageRenderer: does a glass effect render at all (the headless route)?
//   W  A real window (NSHostingView, screencapture -l), pixels at 2x. W1 identity is the control
//      (must equal no effect); W2 regular/clear/tint centre colour over white and black, light and dark;
//      W3 a row profile across a rounded rect's left edge over a horizontal ramp (lensing, rim);
//      W4 a vertical-stripe backdrop (blur inside); W5 two circles in a GlassEffectContainer
//      with spacing 40 vs 4 vs no container (the gap pixel: does it merge?).
//
// RECORDED OUTPUT (2026-10-23, macOS 27.0.1, Xcode SDK MacOSX27, Apple Swift 6.4.2, screen unlocked; two runs differ by nothing in A/P/R/W2-W15 pixel values):
//   --- A: API surface (swiftc -typecheck)
//     A0 positive: glassEffect(): compiles
//     A1 glassEffect(.clear, in: RoundedRectangle): compiles
//     A2 Glass.regular.tint(.red).interactive(): compiles
//     A3 interactive(false): compiles
//     A4 separating: glassEffect(isEnabled:): ERROR extra argument 'isEnabled' in call
//     A5 separating: glassEffect(in: .capsule, isEnabled:): ERROR extra argument 'isEnabled' in call
//     A6 Glass.identity: compiles
//     A7 tint(nil): compiles
//     A8 GlassEffectContainer(spacing:): compiles
//     A9 GlassEffectContainer() no spacing: compiles
//     A10 glassEffectID(_:in:): compiles
//     A11 glassEffectUnion(id:namespace:): compiles
//     A12 glassEffectTransition(.materialize/.matchedGeometry/.identity): compiles
//     A13 buttonStyle(.glass) / (.glassProminent): compiles
//     A14 Glass is Equatable: compiles
//     A15 separating: Glass is Hashable: ERROR type 'Glass' does not conform to protocol 'Hashable'
//     A16 separating: Glass.tinted(.red): ERROR type 'Glass' has no member 'tinted'
//     A17 separating: Glass(shape): ERROR 'Glass' cannot be constructed because it has no accessible initializers
//     A18 separating: glassEffect(_:in:) where shape is Path-based Shape: compiles
//     A19 separating: glassEffectID with nil id: compiles
//     A20 separating: glassEffectID(non-Sendable id): compiles
//     A21 positive: GlassEffectContainer is a View over a stack of two: compiles
//     A22 DefaultGlassEffectShape is public: compiles
//   --- P: DefaultGlassEffectShape (Path.contains on a 1-pt grid)
//     P 100x40: bounding (0.0, 0.0, 100.0, 40.0), capsule agreement 3972/4000, top-left corner pixel outside=1
//     P 100x100: bounding (0.0, 0.0, 100.0, 100.0), capsule agreement 9928/10000, top-left corner pixel outside=1
//     P 40x100: bounding (0.0, 0.0, 40.0, 100.0), capsule agreement 3972/4000, top-left corner pixel outside=1
//   --- R: ImageRenderer (light, 80x40, red channel)
//     R0 backdrop alone (centre, left edge, top edge): [142, 142, 142]
//     R1 glass over it: [142, 142, 142]
//   --- W: real window (2x pixels; centre of a 100x50 capsule/rounded rect on a 160x100 backdrop)
//     W2 light none: over white (255,255,255), over black (0,0,0), over gray (142,142,147)
//     W2 light identity: over white (255,255,255), over black (0,0,0), over gray (142,142,147)
//     W2 light regular: over white (241,241,241), over black (139,139,139), over gray (197,197,201)
//     W2 light clear: over white (244,244,244), over black (71,71,71), over gray (167,167,172)
//     W2 light regular.tint(red): over white (216,216,216), over black (113,113,113), over gray (172,172,174)
//     W2 light clear.tint(red): over white (255,0,42), over black (233,0,0), over gray (255,0,6)
//     W2 dark  none: over white (255,255,255), over black (0,0,0), over gray (152,152,157)
//     W2 dark  identity: over white (255,255,255), over black (0,0,0), over gray (152,152,157)
//     W2 dark  regular: over white (169,169,169), over black (19,19,19), over gray (132,132,138)
//     W2 dark  clear: over white (207,207,207), over black (25,25,25), over gray (133,133,138)
//     W2 dark  regular.tint(red): over white (194,194,194), over black (44,44,45), over gray (158,158,161)
//     W2 dark  clear.tint(red): over white (255,0,39), over black (229,0,0), over gray (252,0,0)
//     W3 light ramp, luminance at x offsets from the left edge (px): none -6:28 -2:30 0:32 2:34 4:35 6:36 8:37 12:40 20:46 40:59 100:99
//     W3 light ramp regular: -6:28 -2:30 0:162 2:160 4:160 6:160 8:160 12:160 20:161 40:165 100:182
//     W3 light ramp clear: -6:28 -2:30 0:117 2:112 4:110 6:109 8:108 12:107 20:107 40:112 100:140
//     W3 dark  ramp, luminance at x offsets from the left edge (px): none -6:28 -2:30 0:32 2:34 4:35 6:36 8:37 12:40 20:46 40:59 100:99
//     W3 dark  ramp regular: -6:28 -2:30 0:65 2:65 4:65 6:64 8:64 12:64 20:65 40:74 100:103
//     W3 dark  ramp clear: -6:28 -2:30 0:73 2:68 4:66 6:64 8:63 12:62 20:62 40:68 100:98
//     W4 stripes none: inside min/max 0/255; outside (backdrop) 0/255
//     W4 stripes regular: inside min/max 191/193; outside (backdrop) 0/255
//     W4 stripes clear: inside min/max 158/158; outside (backdrop) 0/255
//     W5 no container: gap centre (0,0,0), gap 12pt above centre (0,0,0), left circle centre (139,139,139)
//     W5 container spacing 4: gap centre (0,0,0), gap 12pt above centre (0,0,0), left circle centre (139,139,139)
//     W5 container spacing 40: gap centre (139,139,139), gap 12pt above centre (139,139,139), left circle centre (139,139,139)
//   --- W6-W9: rim, edge lensing, tint, merge threshold
//     W6 light regular over gray, luminance by px from edge: left -2:142 -1:92 0:197 1:197 2:197 3:197 4:197 6:197 8:197 12:197 20:197 | top -2:142 -1:108 0:197 1:197 2:197 3:197 4:197 6:197 8:197 12:197 20:197 | bottom 102:142 101:142 100:108 99:197 98:197 97:197 96:197 94:197 92:197 88:197 80:197 | right 202:142 201:142 200:92 199:197 198:197 197:197 196:197 194:197 192:197 188:197 180:197
//     W6 light clear over gray, luminance by px from edge: left -2:142 -1:75 0:167 1:167 2:167 3:167 4:167 6:167 8:167 12:167 20:167 | top -2:142 -1:142 0:167 1:167 2:167 3:167 4:167 6:167 8:167 12:167 20:167 | bottom 102:142 101:142 100:142 99:167 98:167 97:167 96:167 94:167 92:167 88:167 80:167 | right 202:142 201:142 200:75 199:167 198:167 197:167 196:167 194:167 192:167 188:167 180:167
//     W6 dark  regular over gray, luminance by px from edge: left -2:152 -1:84 0:132 1:132 2:132 3:132 4:132 6:132 8:132 12:132 20:132 | top -2:152 -1:106 0:132 1:132 2:132 3:132 4:132 6:132 8:132 12:132 20:132 | bottom 102:152 101:152 100:106 99:132 98:132 97:132 96:132 94:132 92:132 88:132 80:132 | right 202:152 201:152 200:84 199:132 198:132 197:132 196:132 194:132 192:132 188:132 180:132
//     W6 dark  clear over gray, luminance by px from edge: left -2:152 -1:68 0:133 1:133 2:133 3:133 4:133 6:133 8:133 12:133 20:133 | top -2:152 -1:152 0:133 1:133 2:133 3:133 4:133 6:133 8:133 12:133 20:133 | bottom 102:152 101:152 100:152 99:133 98:133 97:133 96:133 94:133 92:133 88:133 80:133 | right 202:152 201:152 200:68 199:133 198:133 197:133 196:133 194:133 192:133 188:133 180:133
//     W7 stripes(6pt) none, left edge band, luminance by px:  -6:0 -5:0 -4:0 -3:0 -2:0 -1:0 0:0 1:0 2:0 3:0 4:255 5:255 6:255 7:255 8:255 9:255 10:255 11:255 12:255 13:255 14:255 15:255 16:0 17:0 18:0 19:0 20:0 21:0 22:0 23:0 24:0
//     W7 stripes(6pt) regular, left edge band, luminance by px:  -6:0 -5:0 -4:0 -3:0 -2:0 -1:85 0:196 1:197 2:196 3:196 4:196 5:196 6:196 7:195 8:195 9:195 10:195 11:195 12:195 13:195 14:195 15:195 16:195 17:195 18:195 19:195 20:194 21:194 22:194 23:194 24:194
//     W7 stripes(6pt) clear, left edge band, luminance by px:  -6:0 -5:0 -4:0 -3:0 -2:0 -1:69 0:159 1:159 2:159 3:160 4:160 5:160 6:161 7:161 8:161 9:161 10:161 11:162 12:162 13:162 14:162 15:162 16:162 17:162 18:162 19:162 20:162 21:162 22:162 23:162 24:161
//     W8 regular.tint(blue) over gray: (172,172,174)
//     W8 regular.tint(red.opacity(0.3)) over gray: (189,189,192)
//     W8 clear.tint(red.opacity(0.3)) over gray: (197,124,130)
//     W8 regular.tint(white) over gray: (172,172,174)
//     W8 regular.tint(black) over gray: (172,172,174)
//     W9 spacing 4: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 8: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 10: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 11: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 12: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 16: gap centre lum 0; lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 24: gap centre lum 139; lum by pt above the row centre at the gap's x: 0:139 6:139 12:0 18:0 24:0 28:0 30:0 32:0
//     W9 spacing 40: gap centre lum 139; lum by pt above the row centre at the gap's x: 0:139 6:139 12:139 18:0 24:0 28:0 30:0 32:0
//   --- W10: merge threshold, circles 60 pt apart by gap g (model: polynomial smooth-min, blend k, merge iff k > 2g)
//     W10 gap 10 spacing 17: gap centre lum 0
//     W10 gap 10 spacing 19: gap centre lum 0
//     W10 gap 10 spacing 20: gap centre lum 64
//     W10 gap 10 spacing 21: gap centre lum 139
//     W10 gap 10 spacing 22: gap centre lum 139
//     W10 gap 10 spacing 23: gap centre lum 139
//     W10 gap 20 spacing 30: gap centre lum 0
//     W10 gap 20 spacing 40: gap centre lum 57
//     W10 gap 20 spacing 44: gap centre lum 139
//     W10 gap 20 spacing 50: gap centre lum 139
//     W10 gap 20 spacing 60: gap centre lum 139
//   --- W11: two shapes of different size in one container, gap 10, spacing 40: does the union stay a union of the two shapes (small circle 20 vs 60)
//     W11 lum by pt above row centre at x = big circle's right edge + 5 pt (inside the gap): 0:139 6:139 10:139 14:0 20:0
//   --- W12: glassEffectUnion in a container with spacing 4 (control: spacing 4 alone never merges at gap 30, W9/W10)
//     W12 gap 10 same union id=false: lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 29:0
//     W12 gap 10 same union id=true: lum by pt above the row centre at the gap's x: 0:139 6:139 12:139 18:139 24:139 29:139
//     W12 gap 30 same union id=false: lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 29:0
//     W12 gap 30 same union id=true: lum by pt above the row centre at the gap's x: 0:139 6:139 12:139 18:139 24:139 29:139
//     W12 gap 60 same union id=false: lum by pt above the row centre at the gap's x: 0:0 6:0 12:0 18:0 24:0 29:0
//     W12 gap 60 same union id=true: lum by pt above the row centre at the gap's x: 0:139 6:139 12:139 18:139 24:139 29:139
//   --- W13: the shape of a union (two 60 pt circles, gap 30, same union id; bbox 150x60 centred in 220x100)
//     W13 bbox corner inset (4,4): 0; (1,1): 0; top edge middle (75,1): 139; left edge middle (1,30): 0; (8,8): 0; (14,14): 0; (20,6): 0
//     W13 centre-line fill: (30,30): 0; (75,30): 139; (75,2): 139; (75,58): 139
//   --- W14: whole-row profile of the union and of the plain pair, gap 30 (lum every 10 pt across 220; rows: centre, 25 pt above, 29 pt above)
//     W14 same=false 0pt above centre: 0 0 0 0 139 139 139 139 139 139 0 0 0 139 139 139 139 139 139 0 0 0
//     W14 same=false 25pt above centre: 0 0 0 0 0 139 139 139 139 0 0 0 0 0 139 139 139 139 0 0 0 0
//     W14 same=false 29pt above centre: 0 0 0 0 0 0 139 139 0 0 0 0 0 0 0 139 139 0 0 0 0 0
//     W14 same=true 0pt above centre: 0 0 0 0 0 0 0 0 137 139 139 139 139 139 0 0 0 0 0 0 0 0
//     W14 same=true 25pt above centre: 0 0 0 0 0 0 0 0 0 0 139 139 139 0 0 0 0 0 0 0 0 0
//     W14 same=true 29pt above centre: 0 0 0 0 0 0 0 0 0 0 0 139 0 0 0 0 0 0 0 0 0 0
//   --- W15: GlassEffectContainer with no spacing argument (nil): merge threshold by gap between two 60 pt circles
//     W15 gap 2: gap centre lum 139
//     W15 gap 6: gap centre lum 0
//     W15 gap 10: gap centre lum 0
//     W15 gap 14: gap centre lum 0
//     W15 gap 20: gap centre lum 0
//     W15 gap 30: gap centre lum 0
//     W15 gap 40: gap centre lum 0
//
// READING.
//  A: this SDK's glassEffect has NO isEnabled parameter (A4, A5); default shape DefaultGlassEffectShape (a public Shape); Glass is
//     Equatable only (A14/A15), built from .regular/.clear/.identity, tint(_:) (optional Color) and interactive(_:); no initialiser.
//     GlassEffectContainer(spacing: CGFloat? = nil); glassEffectID takes any Hashable & Sendable? (A19 nil compiles; A20 shows a
//     non-Sendable id compiles with a warning-free typecheck here, i.e. the constraint is not enforced at this strictness);
//     glassEffectUnion(id:namespace:) ; GlassEffectTransition .matchedGeometry/.materialize/.identity; .buttonStyle(.glass/.glassProminent).
//  P: the default shape is a capsule (agreement 3972/4000, 9928/10000: the misses are the boundary pixels of Path.contains).
//  R: ImageRenderer draws NO glass (R1 equals R0): the headless route is unavailable; only a real window shows it.
//  W2: .identity equals no effect (control). Centre colour is affine in the backdrop: light regular 139 + 0.40 B (black 139, white 241,
//     gray 197); light clear 71 + 0.68 B; dark clear 25 + 0.71 B; DARK REGULAR is NOT affine (black 19, gray 132, white 169: the
//     chord from black misses gray by 24), i.e. adaptive. clear.tint(red) is source-over of the colour (saturated); regular.tint(c)
//     gives a colour-independent grey (W8: blue, white, black identical 172) -- unexplained, ruled LG-E.
//  W3/W4/W6/W7: the interior is FLAT: a 4 pt and a 6 pt stripe backdrop read 191-193 (regular) and 158-162 (clear); a stripe boundary 4 px
//     inside the edge leaves no trace (W7 -1..24 px: constant to +-2). No inner rim and no lensing is visible in a static capture. The one
//     edge feature is a 1 px band just OUTSIDE the shape darker than the backdrop (W6 regular left/right 92 and top/bottom 108 of 142;
//     clear left/right 75, top/bottom none): a hairline contact shadow, carried (LG-Q).
//  W9/W10/W15: merging: two circles with surface gap g in a container with spacing s merge at the gap centre iff s > 2g, exactly (g 10:
//     s 19 no, 20 half-covered, 21 yes; g 20: s 30 no, 40 half-covered, 44 yes) -- the polynomial smooth-min with blend radius k = s
//     (smin(a,b) = min - k/4 at a = b = g/2 crosses 0 at k = 2g). Neck at s 24 reaches 6 pt above the row, not 12. nil spacing: g 2 merges,
//     g 6 does not (k between 4 and 12; ruled 8).
//  W11: a small circle merges the same way (neck follows the smooth-min).
//  W12-W14: glassEffectUnion with one id renders ONE circle of the member's own size centred on the pair (width ~60 pt at gap 30), not
//     the union of the shapes -- contradicts the documentation and is unexplained (a mid-morph capture is not excluded); ruled LG-H.
//  NOT PROBED (cannot be headless): .interactive() press response, glassEffectID morphing and the transitions' animation, Reduce
//     Transparency's fallback (the swizzle route fails, MT-F), sigma beyond "at least ~5 pt" (a 12 pt stripe period reads flat),
//     the real specular behaviour in a key window.
import SwiftUI
import AppKit

func compiles(_ body: String) -> String {
    let dir = NSTemporaryDirectory() + "lg-\(UInt32.random(in: 0...UInt32.max))"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let src = dir + "/s.swift"
    try? ("import SwiftUI\n@available(macOS 26.0, *) struct Probe {}\n" + body + "\n").write(toFile: src, atomically: true, encoding: .utf8)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = ["swiftc", "-typecheck", src]
    let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if p.terminationStatus == 0 { return "compiles" }
    let line = out.split(separator: "\n").first { $0.contains("error:") }.map { String($0.split(separator: ":", maxSplits: 4).last ?? "") } ?? "?"
    return "ERROR" + line
}

func armA() {
    print("--- A: API surface (swiftc -typecheck)")
    let pre = "@available(macOS 26.0, *) "
    let arms: [(String, String)] = [
        ("A0 positive: glassEffect()", pre + "func f() -> some View { Text(\"x\").glassEffect() }"),
        ("A1 glassEffect(.clear, in: RoundedRectangle)", pre + "func f() -> some View { Text(\"x\").glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8)) }"),
        ("A2 Glass.regular.tint(.red).interactive()", pre + "func f() -> some View { Text(\"x\").glassEffect(.regular.tint(.red).interactive()) }"),
        ("A3 interactive(false)", pre + "func f() -> some View { Text(\"x\").glassEffect(.regular.interactive(false)) }"),
        ("A4 separating: glassEffect(isEnabled:)", pre + "func f() -> some View { Text(\"x\").glassEffect(.regular, isEnabled: false) }"),
        ("A5 separating: glassEffect(in: .capsule, isEnabled:)", pre + "func f() -> some View { Text(\"x\").glassEffect(.regular, in: .capsule, isEnabled: false) }"),
        ("A6 Glass.identity", pre + "func f() -> some View { Text(\"x\").glassEffect(.identity) }"),
        ("A7 tint(nil)", pre + "func f() -> some View { Text(\"x\").glassEffect(.regular.tint(nil)) }"),
        ("A8 GlassEffectContainer(spacing:)", pre + "func f() -> some View { GlassEffectContainer(spacing: 20) { Text(\"x\").glassEffect() } }"),
        ("A9 GlassEffectContainer() no spacing", pre + "func f() -> some View { GlassEffectContainer { Text(\"x\").glassEffect() } }"),
        ("A10 glassEffectID(_:in:)", pre + "struct V: View { @Namespace var ns; var body: some View { Text(\"x\").glassEffect().glassEffectID(\"a\", in: ns) } }"),
        ("A11 glassEffectUnion(id:namespace:)", pre + "struct V: View { @Namespace var ns; var body: some View { Text(\"x\").glassEffect().glassEffectUnion(id: 1, namespace: ns) } }"),
        ("A12 glassEffectTransition(.materialize/.matchedGeometry/.identity)", pre + "func f() -> some View { Text(\"x\").glassEffect().glassEffectTransition(.materialize).glassEffectTransition(.matchedGeometry).glassEffectTransition(.identity) }"),
        ("A13 buttonStyle(.glass) / (.glassProminent)", pre + "func f() -> some View { VStack { Button(\"a\") {}.buttonStyle(.glass); Button(\"b\") {}.buttonStyle(.glassProminent) } }"),
        ("A14 Glass is Equatable", pre + "func f() -> Bool { Glass.regular == Glass.clear }"),
        ("A15 separating: Glass is Hashable", pre + "func f() -> Set<Glass> { [] }"),
        ("A16 separating: Glass.tinted(.red)", pre + "func f() -> Glass { .tinted(.red) }"),
        ("A17 separating: Glass(shape)", pre + "func f() -> Glass { Glass(.regular) }"),
        ("A18 separating: glassEffect(_:in:) where shape is Path-based Shape", pre + "struct S: Shape { func path(in r: CGRect) -> Path { Path(r) } }\nfunc f() -> some View { Text(\"x\").glassEffect(.regular, in: S()) }"),
        ("A19 separating: glassEffectID with nil id", pre + "struct V: View { @Namespace var ns; var body: some View { Text(\"x\").glassEffect().glassEffectID(Optional<Int>.none, in: ns) } }"),
        ("A20 separating: glassEffectID(non-Sendable id)", pre + "final class K: Hashable { static func == (a: K, b: K) -> Bool { a === b }; func hash(into h: inout Hasher) {} }\nstruct V: View { @Namespace var ns; var body: some View { Text(\"x\").glassEffect().glassEffectID(K(), in: ns) } }"),
        ("A21 positive: GlassEffectContainer is a View over a stack of two", pre + "func f() -> some View { GlassEffectContainer(spacing: 8) { HStack { Text(\"a\").glassEffect(); Text(\"b\").glassEffect() } } }"),
        ("A22 DefaultGlassEffectShape is public", pre + "func f() -> some Shape { DefaultGlassEffectShape() }"),
    ]
    for (name, src) in arms { print("  \(name): \(compiles(src))") }
}

struct Bitmap { let w: Int; let h: Int; let bytes: [UInt8] }
func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Bitmap(w: w, h: h, bytes: d)
}
func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * b.w + x) * 4; return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2])) }

@available(macOS 26.0, *)
@MainActor func armP() {
    print("--- P: DefaultGlassEffectShape (Path.contains on a 1-pt grid)")
    for (w, h) in [(100.0, 40.0), (100.0, 100.0), (40.0, 100.0)] {
        let p = DefaultGlassEffectShape().path(in: CGRect(x: 0, y: 0, width: w, height: h))
        let r = min(w, h) / 2
        // capsule: a point is inside iff its distance to the core segment <= r.
        var agree = 0, total = 0, cornerOut = p.contains(CGPoint(x: 0.5, y: 0.5)) ? 0 : 1
        for xi in stride(from: 0.5, to: w, by: 1) { for yi in stride(from: 0.5, to: h, by: 1) {
            let cx = min(max(xi, r), w - r), cy = min(max(yi, r), h - r)
            let inside = hypot(xi - cx, yi - cy) <= r
            total += 1; if inside == p.contains(CGPoint(x: xi, y: yi)) { agree += 1 }
        } }
        print("  P \(Int(w))x\(Int(h)): bounding \(p.boundingRect), capsule agreement \(agree)/\(total), top-left corner pixel outside=\(cornerOut)")
    }
}

@available(macOS 26.0, *)
@MainActor func armR() {
    print("--- R: ImageRenderer (light, 80x40, red channel)")
    func px(_ v: some View) -> [Int] {
        let r = ImageRenderer(content: v.frame(width: 80, height: 40)); r.scale = 1
        guard let cg = r.cgImage else { return [-1] }
        let b = bytes(of: cg); return [rgb(b, 40, 20).0, rgb(b, 3, 20).0, rgb(b, 40, 2).0]
    }
    print("  R0 backdrop alone (centre, left edge, top edge): \(px(Color.gray))")
    print("  R1 glass over it: \(px(ZStack { Color.gray; Color.clear.glassEffect(.regular, in: Capsule()).padding(2) }))")
}

@MainActor func windowBitmap(_ content: some View, w: Int, h: Int, dark: Bool, tag: String) -> Bitmap? {
    let host = NSHostingView(rootView: content.frame(width: CGFloat(w), height: CGFloat(h)).environment(\.colorScheme, dark ? .dark : .light))
    let win = NSWindow(contentRect: NSRect(x: 200, y: 400, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
    let path = "/tmp/lg-win-\(tag).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(win.windowNumber), path]
    try? p.run(); p.waitUntilExit()
    win.orderOut(nil)
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    return bytes(of: cg)
}
func lum(_ c: (Int, Int, Int)) -> Int { (c.0 * 299 + c.1 * 587 + c.2 * 114) / 1000 }
func fmt(_ c: (Int, Int, Int)) -> String { "(\(c.0),\(c.1),\(c.2))" }

@available(macOS 26.0, *)
@MainActor func armW() {
    _ = NSApplication.shared
    print("--- W: real window (2x pixels; centre of a 100x50 capsule/rounded rect on a 160x100 backdrop)")
    func centre(_ back: Color, _ glass: Glass?, dark: Bool, tag: String) -> String {
        let v = ZStack { back; Color.clear.frame(width: 100, height: 50).modifier(GlassMod(glass: glass)) }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: dark, tag: tag) else { return "capture failed" }
        return fmt(rgb(b, b.w / 2, b.h / 2))
    }
    let cfgs: [(String, Glass?)] = [("none", nil), ("identity", .identity), ("regular", .regular), ("clear", .clear), ("regular.tint(red)", .regular.tint(.red)), ("clear.tint(red)", .clear.tint(.red))]
    for dark in [false, true] {
        for (n, g) in cfgs {
            print("  W2 \(dark ? "dark " : "light") \(n): over white \(centre(.white, g, dark: dark, tag: "a")), over black \(centre(.black, g, dark: dark, tag: "b")), over gray \(centre(.gray, g, dark: dark, tag: "c"))")
        }
    }
    // W3 row profile across the left edge of a 100x50 rounded rect (r=16) over a horizontal ramp.
    func profile(_ glass: Glass?, dark: Bool) -> String {
        let ramp = LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing)
        let v = ZStack { ramp; Color.clear.frame(width: 100, height: 50).modifier(GlassMod(glass: glass, shape: RoundedRectangle(cornerRadius: 16))) }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: dark, tag: "p") else { return "capture failed" }
        let y = b.h / 2, x0 = (b.w - 200) / 2
        var s = ""
        for dx in [-6, -2, 0, 2, 4, 6, 8, 12, 20, 40, 100] { s += " \(dx):\(lum(rgb(b, x0 + dx, y)))" }
        return s
    }
    for dark in [false, true] {
        print("  W3 \(dark ? "dark " : "light") ramp, luminance at x offsets from the left edge (px): none\(profile(nil, dark: dark))")
        print("  W3 \(dark ? "dark " : "light") ramp regular:\(profile(.regular, dark: dark))")
        print("  W3 \(dark ? "dark " : "light") ramp clear:\(profile(.clear, dark: dark))")
    }
    // W4 stripes: contrast inside the glass.
    func stripes(_ glass: Glass?) -> String {
        let st = HStack(spacing: 0) { ForEach(0..<40, id: \.self) { i in (i % 2 == 0 ? Color.black : Color.white).frame(width: 4) } }
        let v = ZStack { st; Color.clear.frame(width: 100, height: 50).modifier(GlassMod(glass: glass)) }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: false, tag: "s") else { return "capture failed" }
        var lo = 255, hi = 0
        for x in (b.w / 2 - 40)..<(b.w / 2 + 40) { let l = lum(rgb(b, x, b.h / 2)); lo = min(lo, l); hi = max(hi, l) }
        var elo = 255, ehi = 0
        for x in 0..<80 { let l = lum(rgb(b, x, 10)); elo = min(elo, l); ehi = max(ehi, l) }
        return "inside min/max \(lo)/\(hi); outside (backdrop) \(elo)/\(ehi)"
    }
    print("  W4 stripes none: \(stripes(nil))")
    print("  W4 stripes regular: \(stripes(.regular))")
    print("  W4 stripes clear: \(stripes(.clear))")
    // W5 container merging: two 60x60 circles with a 10 pt gap; the gap pixel.
    func gap(spacing: CGFloat?, contained: Bool) -> String {
        let pair = HStack(spacing: 10) {
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
        }
        let v = ZStack { Color.black; if contained { GlassEffectContainer(spacing: spacing) { pair } } else { pair } }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: false, tag: "g") else { return "capture failed" }
        // gap centre, and the waist (gap centre, 12 pt above the row centre)
        return "gap centre \(fmt(rgb(b, b.w / 2, b.h / 2))), gap 12pt above centre \(fmt(rgb(b, b.w / 2, b.h / 2 - 24))), left circle centre \(fmt(rgb(b, b.w / 2 - 70, b.h / 2)))"
    }
    print("  W5 no container: \(gap(spacing: nil, contained: false))")
    print("  W5 container spacing 4: \(gap(spacing: 4, contained: true))")
    print("  W5 container spacing 40: \(gap(spacing: 40, contained: true))")
}


@available(macOS 26.0, *)
@MainActor func armW2() {
    print("--- W6-W9: rim, edge lensing, tint, merge threshold")
    func row(_ v: some View, dark: Bool, vertical: Bool, offs: [Int], tag: String) -> String {
        guard let b = windowBitmap(v, w: 160, h: 100, dark: dark, tag: tag) else { return "capture failed" }
        let x0 = (b.w - 200) / 2, y0 = (b.h - 100) / 2
        var s = ""
        for d in offs {
            let c = vertical ? rgb(b, b.w / 2, y0 + d) : rgb(b, x0 + d, b.h / 2)
            s += " \(d):\(lum(c))"
        }
        return s
    }
    let shape = RoundedRectangle(cornerRadius: 16)
    let offs = [-2, -1, 0, 1, 2, 3, 4, 6, 8, 12, 20]
    for dark in [false, true] {
        for (n, g) in [("regular", Glass.regular), ("clear", Glass.clear)] {
            let v = ZStack { Color.gray; Color.clear.frame(width: 100, height: 50).glassEffect(g, in: shape) }
            let left = row(v, dark: dark, vertical: false, offs: offs, tag: "r1")
            let top = row(v, dark: dark, vertical: true, offs: offs, tag: "r2")
            let bot = row(v, dark: dark, vertical: true, offs: offs.map { 100 - $0 }, tag: "r3")
            let right = row(v, dark: dark, vertical: false, offs: offs.map { 200 - $0 }, tag: "r4")
            print("  W6 \(dark ? "dark " : "light") \(n) over gray, luminance by px from edge: left\(left) | top\(top) | bottom\(bot) | right\(right)")
        }
    }
    // W7: a 6 pt stripe backdrop; a stripe boundary every 6 pt; read 1 px steps across the left edge band.
    for (n, g) in [("none", nil), ("regular", Glass.regular), ("clear", Glass.clear)] as [(String, Glass?)] {
        let st = HStack(spacing: 0) { ForEach(0..<30, id: \.self) { i in (i % 2 == 0 ? Color.black : Color.white).frame(width: 6) } }
        let v = ZStack { st; Color.clear.frame(width: 100, height: 50).modifier(GlassMod(glass: g, shape: shape)) }
        print("  W7 stripes(6pt) \(n), left edge band, luminance by px: \(row(v, dark: false, vertical: false, offs: Array(-6...24), tag: "st"))")
    }
    // W8: tint variants over gray, light.
    for (n, g) in [("regular.tint(blue)", Glass.regular.tint(.blue)), ("regular.tint(red.opacity(0.3))", Glass.regular.tint(Color.red.opacity(0.3))), ("clear.tint(red.opacity(0.3))", Glass.clear.tint(Color.red.opacity(0.3))), ("regular.tint(white)", Glass.regular.tint(.white)), ("regular.tint(black)", Glass.regular.tint(.black))] {
        let v = ZStack { Color.gray; Color.clear.frame(width: 100, height: 50).glassEffect(g, in: shape) }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: false, tag: "t") else { continue }
        print("  W8 \(n) over gray: \(fmt(rgb(b, b.w / 2, b.h / 2)))")
    }
    // W9: merge threshold; two 60 pt circles 10 pt apart; gap centre by container spacing; and the neck profile.
    func gap(_ spacing: CGFloat) -> (Int, String) {
        let pair = HStack(spacing: 10) {
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
        }
        let v = ZStack { Color.black; GlassEffectContainer(spacing: spacing) { pair } }
        guard let b = windowBitmap(v, w: 160, h: 100, dark: false, tag: "m") else { return (-1, "") }
        var s = ""
        for dy in [0, 6, 12, 18, 24, 28, 30, 32] { s += " \(dy):\(lum(rgb(b, b.w / 2, b.h / 2 - dy * 2)))" }
        return (lum(rgb(b, b.w / 2, b.h / 2)), s)
    }
    for sp in [4, 8, 10, 11, 12, 16, 24, 40] {
        let (c, s) = gap(CGFloat(sp)); print("  W9 spacing \(sp): gap centre lum \(c); lum by pt above the row centre at the gap's x:\(s)")
    }
}


@available(macOS 26.0, *)
@MainActor func armW3() {
    print("--- W10: merge threshold, circles 60 pt apart by gap g (model: polynomial smooth-min, blend k, merge iff k > 2g)")
    for (g, sps) in [(10, [17, 19, 20, 21, 22, 23]), (20, [30, 40, 44, 50, 60])] as [(Int, [Int])] {
        for sp in sps {
            let pair = HStack(spacing: CGFloat(g)) {
                Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
                Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
            }
            let v = ZStack { Color.black; GlassEffectContainer(spacing: CGFloat(sp)) { pair } }
            guard let b = windowBitmap(v, w: 200, h: 100, dark: false, tag: "m2") else { continue }
            print("  W10 gap \(g) spacing \(sp): gap centre lum \(lum(rgb(b, b.w / 2, b.h / 2)))")
        }
    }
    print("--- W11: two shapes of different size in one container, gap 10, spacing 40: does the union stay a union of the two shapes (small circle 20 vs 60)")
    let pair = HStack(spacing: 10) {
        Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
        Color.clear.frame(width: 20, height: 20).glassEffect(.regular, in: Circle())
    }
    let v = ZStack { Color.black; GlassEffectContainer(spacing: 40) { pair } }
    if let b = windowBitmap(v, w: 200, h: 100, dark: false, tag: "m3") {
        var s = ""
        for dy in [0, 6, 10, 14, 20] { s += " \(dy):\(lum(rgb(b, b.w / 2 + 30 + 10, b.h / 2 - dy * 2)))" }
        print("  W11 lum by pt above row centre at x = big circle's right edge + 5 pt (inside the gap):\(s)")
    }
}


@available(macOS 26.0, *)
struct UnionProbe: View {
    @Namespace var ns
    let gap: CGFloat
    let sameID: Bool
    var body: some View {
        ZStack {
            Color.black
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: gap) {
                    Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle()).glassEffectUnion(id: "u", namespace: ns)
                    Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle()).glassEffectUnion(id: sameID ? "u" : "v", namespace: ns)
                }
            }
        }
    }
}

@available(macOS 26.0, *)
@MainActor func armW4() {
    print("--- W12: glassEffectUnion in a container with spacing 4 (control: spacing 4 alone never merges at gap 30, W9/W10)")
    for gap in [10, 30, 60] as [CGFloat] {
        for same in [false, true] {
            guard let b = windowBitmap(UnionProbe(gap: gap, sameID: same), w: 220, h: 100, dark: false, tag: "u") else { continue }
            var s = ""
            for dy in [0, 6, 12, 18, 24, 29] { s += " \(dy):\(lum(rgb(b, b.w / 2, b.h / 2 - dy * 2)))" }
            print("  W12 gap \(Int(gap)) same union id=\(same): lum by pt above the row centre at the gap's x:\(s)")
        }
    }
}


@available(macOS 26.0, *)
@MainActor func armW5() {
    print("--- W13: the shape of a union (two 60 pt circles, gap 30, same union id; bbox 150x60 centred in 220x100)")
    guard let b = windowBitmap(UnionProbe(gap: 30, sameID: true), w: 220, h: 100, dark: false, tag: "u2") else { return }
    let cx = b.w / 2, cy = b.h / 2, left = cx - 150, top = cy - 60
    func at(_ dxPt: Int, _ dyPt: Int) -> Int { lum(rgb(b, left + dxPt * 2, top + dyPt * 2)) }
    print("  W13 bbox corner inset (4,4): \(at(4, 4)); (1,1): \(at(1, 1)); top edge middle (75,1): \(at(75, 1)); left edge middle (1,30): \(at(1, 30)); (8,8): \(at(8, 8)); (14,14): \(at(14, 14)); (20,6): \(at(20, 6))")
    print("  W13 centre-line fill: (30,30): \(at(30, 30)); (75,30): \(at(75, 30)); (75,2): \(at(75, 2)); (75,58): \(at(75, 58))")
}


@available(macOS 26.0, *)
@MainActor func armW6() {
    print("--- W14: whole-row profile of the union and of the plain pair, gap 30 (lum every 10 pt across 220; rows: centre, 25 pt above, 29 pt above)")
    for same in [false, true] {
        guard let b = windowBitmap(UnionProbe(gap: 30, sameID: same), w: 220, h: 100, dark: false, tag: "u3") else { continue }
        for dy in [0, 25, 29] {
            var s = ""
            for x in stride(from: 0, to: 220, by: 10) { s += " \(lum(rgb(b, x * 2, b.h / 2 - dy * 2)))" }
            print("  W14 same=\(same) \(dy)pt above centre:\(s)")
        }
    }
}


@available(macOS 26.0, *)
@MainActor func armW7() {
    print("--- W15: GlassEffectContainer with no spacing argument (nil): merge threshold by gap between two 60 pt circles")
    for gap in [2, 6, 10, 14, 20, 30, 40] as [CGFloat] {
        let pair = HStack(spacing: gap) {
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
            Color.clear.frame(width: 60, height: 60).glassEffect(.regular, in: Circle())
        }
        guard let b = windowBitmap(ZStack { Color.black; GlassEffectContainer { pair } }, w: 220, h: 100, dark: false, tag: "n") else { continue }
        print("  W15 gap \(Int(gap)): gap centre lum \(lum(rgb(b, b.w / 2, b.h / 2)))")
    }
}

@available(macOS 26.0, *)
struct GlassMod: ViewModifier {
    var glass: Glass?
    var shape: any Shape = Capsule()
    func body(content: Content) -> some View {
        if let glass { content.glassEffect(glass, in: AnyShape(shape)) } else { content }
    }
}

MainActor.assumeIsolated {
    armA()
    if #available(macOS 26.0, *) {
        armP(); armR()
        if CommandLine.arguments.contains("--no-window") == false { armW(); armW2(); armW3(); armW4(); armW5(); armW6(); armW7() }
    }
}
