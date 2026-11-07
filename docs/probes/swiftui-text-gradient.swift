// SwiftUI probe: how a GRADIENT `foregroundStyle` PAINTS on `Text` (round 4 item R4-5 PR D; divergence 975,
// rulings `TG-` in docs/superpowers/2026-11-0X-text-gradient-decisions.md, record 221).
//
// HOW TO RUN (compiled form, SA-O; ImageRenderer needs neither a window nor an unlocked session):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-text-gradient.swift -o /tmp/tg-probe
//   /tmp/tg-probe > /tmp/tg-1.txt; /tmp/tg-probe > /tmp/tg-2.txt; cmp /tmp/tg-1.txt /tmp/tg-2.txt
//
// INSTRUMENT. `ImageRenderer` at scale 1, transparent background, a 320 x 140 pt canvas with the content at
// `.topLeading` (a layout box starts at 0,0), sRGB bitmap. Glyphs are U+2588 FULL BLOCK at 40 pt (solid
// interiors; U+2580/U+2594 for the decoration arms). `g` is `LinearGradient([r, b], .leading, .trailing)`
// with r = sRGB (1,0,0), b = (0,0,1). **SwiftUI interpolates a gradient perceptually, so B is not t**: every
// span question is therefore decided against a RECTANGLE filled with the same style over each hypothesised
// span (`cmp`: the maximum and mean of the largest channel difference over the pixels the text covers fully;
// the text's own renderer differs from a Rectangle's by up to .07-.09, so a hypothesis reads as the span when
// it is within that and the others are far above it). `arm` prints the ink bands and runs with B at the run
// ends and the reference B of a Rectangle over each hypothesis; `colDump` prints the vertical runs of one
// column. B and alpha are printed to two decimals: the renderer's low bits flicker between runs, and with
// this quantisation the output was byte-identical over six runs. The BOX arms read the layout box (green).
//
// RECORDED 2026-11-06, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9). Compiled form, run six times:
// stdout byte-identical (71 lines, shasum b079600c629341b24e80063be0f3ba881ef16fb5), exit 0.
//
//   --- BOX: the layout boxes (green)
//   BOX1 4 blocks -> layout box x0..159 y0..50 (w 160 h 51)
//   BOX2 2 blocks, gap, 2 blocks -> layout box x0..177 y0..50 (w 178 h 51)
//   BOX3 space 2 space -> layout box x0..97 y0..50 (w 98 h 51)
//   BOX4 2 blocks -> layout box x0..79 y0..50 (w 80 h 51)
//   BOX5 2 lines 2/2 -> layout box x0..79 y0..97 (w 80 h 98)
//   BOX6 2 lines 4/2 -> layout box x0..159 y0..97 (w 160 h 98)
//   BOX7 VStack leading 2 / 6 -> layout box x0..239 y0..97 (w 240 h 98)
//   BOX8 2 + 2 concatenated -> layout box x0..159 y0..50 (w 160 h 51)
//   BOX9 3 blocks -> layout box x0..119 y0..50 (w 120 h 51)
//   --- TG0 .. TG2: does it separate, and per glyph / line / frame (hyp: box=the layout box, ink=the run)
//   TG0 4 blocks, gradient (SEPARATING: B rises left to right) -> | band0 y3..50 [row26 run x0(G0.05 B0.09 a1.00) box=0.02 .. x159(G0.06 B0.99 a1.00) box=1.00]
//   TG0c 4 blocks, Color.red (control) -> | band0 y3..50 [row26 run x0(G0.00 B0.00 a1.00) .. x159(G0.00 B0.00 a1.00)]
//   TG1 2 blocks, gap, 2 blocks (box 178 wide; per glyph would restart at the second cluster) -> | band0 y3..50 [row26 run x0(G0.05 B0.08 a1.00) frame=0.02 cluster=0.04 .. x79(G0.33 B0.59 a1.00) frame=0.60 cluster=1.00 run x97(G0.32 B0.67 a1.00) frame=0.67 cluster=1.00 .. x176(G0.06 B0.99 a1.00) frame=0.99 cluster=1.00]
//   TG2a 2 lines, top-to-bottom: V profile, per line would restart at y49 -> | band0 y3..97 [row50 run x0(G0.32 B0.63 a0.93) .. x79(G0.33 B0.63 a0.94)] V@x4 y3(G0.06 B0.09 a0.78) y26(G0.29 B0.43 a1.00) y50(G0.33 B0.63 a0.94) y73(G0.28 B0.80 a1.00) y97(G0.09 B0.98 a0.72)
//   TG2b 2 lines 4/2, horizontal, rows 25 and 75 (line 2 right edge: per line B1.0, per frame mid) -> | band0 y3..97 [row25 run x0(G0.05 B0.09 a1.00) frame=0.02 line=0.04 .. x159(G0.06 B0.98 a1.00) frame=1.00 line=1.00] [row75 run x0(G0.05 B0.09 a1.00) frame=0.02 line=0.04 .. x79(G0.33 B0.64 a1.00) frame=0.64 line=1.00]
//   --- TG3: which box
//   TG3a space 2 space (box 98 wide, first ink at x8): box B=ref(98, 8), ink B=ref(80, 0) -> | band0 y3..50 [row26 run x8(G0.08 B0.09 a1.00) box=0.24 ink=0.04 .. x87(G0.10 B0.98 a1.00) box=0.92 ink=1.00]
//   TG3b frame(width 300) then the style (box = the frame would be 300 wide) -> | band0 y3..50 [row26 run x0(G0.10 B0.13 a1.00) leaf=0.04 frame=0.01 .. x79(G0.09 B0.98 a1.00) leaf=1.00 frame=0.44]
//   TG3b2 Text.foregroundStyle then frame(width 300) -> | band0 y3..50 [row26 run x0(G0.10 B0.13 a1.00) leaf=0.04 frame=0.01 .. x79(G0.09 B0.98 a1.00) leaf=1.00 frame=0.44]
//   TG3c padding(20) then the style (padded box 120 wide) -> | band0 y23..70 [row46 run x20(G0.10 B0.13 a1.00) leaf=0.04 padded=0.35 .. x99(G0.09 B0.98 a1.00) leaf=1.00 padded=0.88]
//   --- TG4: a container (BOX7: 240 wide, the short text 80)
//   TG4 VStack leading { 2 blocks; 6 blocks }.foregroundStyle(g), rows 25 and 75 -> | band0 y3..97 [row25 run x0(G0.10 B0.13 a1.00) container=0.01 text=0.04 .. x79(G0.10 B0.98 a1.00) container=0.50 text=1.00] [row75 run x0(G0.04 B0.07 a1.00) container=0.01 text=0.04 .. x239(G0.05 B0.99 a1.00) container=1.00 text=1.00]
//   TG4b the same, each Text styled, rows 25 and 75 -> | band0 y3..97 [row25 run x0(G0.10 B0.13 a1.00) container=0.01 text=0.04 .. x79(G0.10 B0.98 a1.00) container=0.50 text=1.00] [row75 run x0(G0.04 B0.07 a1.00) container=0.01 text=0.04 .. x239(G0.05 B0.99 a1.00) container=1.00 text=1.00]
//   --- TG5: concatenation (BOX8: 160 wide, runs 80 each)
//   TG5a interpolation, red first run, gradient second run -> | band0 y3..50 [row26 run x0(G0.00 B0.00 a1.00) whole=0.02 run=0.04 .. x159(G0.10 B0.98 a1.00) whole=1.00 run=1.00]
//   TG5b (Text + Text).foregroundStyle(g) -> | band0 y3..50 [row26 run x0(G0.05 B0.09 a1.00) whole=0.02 run=0.04 .. x159(G0.06 B0.99 a1.00) whole=1.00 run=1.00]
//   TG5c both runs carry g separately -> | band0 y3..50 [row26 run x0(G0.05 B0.09 a1.00) whole=0.02 run=0.04 .. x159(G0.06 B0.99 a1.00) whole=1.00 run=1.00]
//   --- CMP: the span, read as the maximum channel difference against a Rectangle over each hypothesis
//   TG0x 4 blocks: box vs ink span -> box0,0,160x51: max 0.07 mean 0.01 n=7360; ink0,3,160x48: max 0.07 mean 0.01 n=7360; frame0,0,320x140: max 0.52 mean 0.25 n=7360;
//   TG1x 2 blocks, gap, 2 blocks, whole: frame vs ink vs frame-of-first-cluster -> frame178: max 0.07 mean 0.01 n=7360; ink177: max 0.07 mean 0.01 n=7360; cluster80: max 0.58 mean 0.26 n=3680;
//   TG1y the second cluster alone (x >= 97): frame vs its own box -> frame178: max 0.02 mean 0.00 n=3680; cluster97+80: max 0.63 mean 0.26 n=3680;
//   TG2ax 2 lines top-to-bottom: frame vs ink vs line -> frame80x98: max 0.05 mean 0.02 n=7360; ink y3..97: max 0.05 mean 0.01 n=7360; line1 only: max 0.55 mean 0.28 n=3600;
//   TG2ay line 2 alone (y >= 49): frame vs its own line -> frame80x98: max 0.05 mean 0.02 n=3760; line2 0,49,80x49: max 0.56 mean 0.22 n=3760;
//   TG2c one line, vertical: layout box vs ink rows -> layout0,0,80x51: max 0.07 mean 0.04 n=3680; ink3,48: max 0.06 mean 0.02 n=3680;
//   TG2bx 4/2 lines horizontal: the frame vs a per-line span (line 2 rows only) -> frame160: max 0.07 mean 0.01 n=3840; line80: max 0.54 mean 0.24 n=3760;
//   TG3ax space 2 space: layout box vs ink columns -> box98: max 0.15 mean 0.04 n=3680; ink x8..87 y0: max 0.08 mean 0.01 n=3680; ink x8 y3: max 0.08 mean 0.01 n=3680;
//   TG3bx frame(300): leaf vs frame -> leaf80: max 0.09 mean 0.02 n=3680; frame300: max 0.71 mean 0.36 n=3680;
//   TG3cx padding(20): leaf vs padded box -> leaf@20,20 80x51: max 0.09 mean 0.02 n=3680; padded 120x91: max 0.22 mean 0.08 n=3680;
//   TG4x VStack, text 1 (y < 49): its own box vs the container -> text80x49: max 0.09 mean 0.02 n=3600; container240x98: max 0.65 mean 0.33 n=3600;
//   TG4y VStack, text 2 (y >= 49): its own box vs the container -> text240x49: max 0.65 mean 0.01 n=11120; container240x98: max 0.65 mean 0.01 n=11120;
//   TG5ax red run then a gradient run, second run (x >= 80): whole vs the run's own box -> whole160: max 0.51 mean 0.24 n=3680; run80@80: max 0.09 mean 0.02 n=3680;
//   TG5bx (Text + Text).foregroundStyle(g): whole vs run 2 own box (x >= 80) -> whole160: max 0.05 mean 0.01 n=3680; run80@80: max 0.60 mean 0.23 n=3680;
//   TG5cx both runs carry g: run 2 (x >= 80): whole vs its own box -> whole160: max 0.05 mean 0.01 n=3680; run80@80: max 0.60 mean 0.23 n=3680;
//   TG8x radial 0..40 on 3 blocks: box vs ink vs the canvas -> box120x51: max 0.11 mean 0.02 n=5520; ink120x48: max 0.03 mean 0.00 n=5520; canvas320x140: max 0.99 mean 0.29 n=5520;
//   TG8y radial 0..100 on 3 blocks: box vs ink vs the canvas -> box120x51: max 0.07 mean 0.01 n=5520; ink120x48: max 0.03 mean 0.00 n=5520; canvas320x140: max 1.00 mean 0.59 n=5520;
//   TG8z radial topLeading 0..100 on 3 blocks: box vs ink vs the canvas -> box120x51: max 0.07 mean 0.01 n=5520; ink120x48: max 0.08 mean 0.02 n=5520; canvas320x140: max 0.07 mean 0.01 n=5520;
//   TG7x opacity .5: box (alpha compared at .49) -> box160x51: max 0.07 mean 0.01 n=7360;
//   TG2d upper half blocks, top-to-bottom: layout box vs ink rows y7..28 (the TG10n dump) -> layout0,0,96x51: max 0.31 mean 0.13 n=1920; ink y7 h22: max 0.09 mean 0.03 n=1920; ink y6 h24: max 0.04 mean 0.02 n=1920; ink y7 h23: max 0.05 mean 0.02 n=1920;
//   BOX10 8 spaces, 2 blocks, 8 spaces -> layout box x0..217 y0..50 (w 218 h 51)
//   TG3d0 8 spaces, 2 blocks, 8 spaces: the ink run -> | band0 y3..50 [row26 run x68(G0.09 B0.09 a1.00) box=0.48 .. x147(G0.10 B0.98 a1.00) box=0.76]
//   TG3d 8 spaces, 2 blocks, 8 spaces: layout box vs ink -> box218: max 0.40 mean 0.15 n=3680; ink x68: max 0.08 mean 0.01 n=3680;
//   TG5d g, green, g: the third run (x >= 160): its own box vs the whole -> whole240: max 0.03 mean 0.01 n=3680; run3 80@160: max 0.72 mean 0.32 n=3680;
//   TG5e g, green, g: the first run (x < 80): its own box vs the whole -> whole240: max 0.05 mean 0.01 n=3680; run1 80@0: max 0.68 mean 0.32 n=3680;
//   --- TG6 .. TG14
//   TG6 shadow black r0 x8 under g, at y25 (ink x0..159; the shadow-only pixels are x160..167) -> x2y25=(G0.10 B0.12 a1.00) x100y25=(G0.31 B0.73 a1.00) x158y25=(G0.07 B0.99 a1.00) x160y25=(G0.01 B0.23 a1.00) x163y25=(G0.00 B0.00 a1.00) x167y25=(G0.00 B0.00 a1.00)
//   TG7 opacity .5 -> | band0 y4..49 [row26 run x0(G0.05 B0.09 a0.50) box=0.02 .. x159(G0.05 B0.99 a0.50) box=1.00]
//   TG8 radial red->blue, center, 0..40 pt, 3 blocks (box 120 x 51: center (60, 25)) -> | band0 y3..50 [row25 run x0(G0.00 B1.00 a1.00) .. x119(G0.00 B1.00 a1.00)]
//   TG9 .secondary over a gradient parent -> | band0 y4..49 [row26 run x0(G0.05 B0.09 a0.50) box=0.02 .. x159(G0.05 B0.99 a0.50) box=1.00]
//   TG10 upper half blocks + underline then the style: column dumps at x4 and x90 -> | x4: y7..28[first a0.24 G0.16 B0.21; last a0.61 G0.16 B0.21] y41..42[first a1.00 G0.16 B0.20; last a1.00 G0.16 B0.20] | x90: y7..28[first a0.24 G0.16 B0.95; last a0.61 G0.16 B0.95] y41..42[first a1.00 G0.16 B0.95; last a1.00 G0.16 B0.95]
//   TG10n the same without an underline (the glyph rows alone) -> | x4: y7..28[first a0.24 G0.16 B0.21; last a0.61 G0.16 B0.21] | x90: y7..28[first a0.24 G0.16 B0.95; last a0.61 G0.16 B0.95]
//   TG10v vertical gradient + underline: does the underline extend the span? (glyph rows y7..28, underline y41..42) -> | x4: y7..28[first a0.24 G0.13 B0.16; last a0.61 G0.32 B0.71] y41..42[first a1.00 G0.15 B0.95; last a1.00 G0.11 B0.97]
//   TG10vn the same without an underline -> | x4: y7..28[first a0.24 G0.15 B0.19; last a0.61 G0.19 B0.93]
//   TG10b underline(color: green) -> | x4: y7..28[first a0.24 G0.16 B0.21; last a0.61 G0.16 B0.21] y41..42[first a1.00 G0.78 B0.35; last a1.00 G0.78 B0.35] | x90: y7..28[first a0.24 G0.16 B0.95; last a0.61 G0.16 B0.95] y41..42[first a1.00 G0.78 B0.35; last a1.00 G0.78 B0.35]
//   TG10c upper one-eighth blocks + strikethrough then the style -> | x4: y5..10[first a0.55 G0.12 B0.17; last a0.62 G0.13 B0.16] y27..29[first a1.00 G0.13 B0.16; last a1.00 G0.12 B0.16] | x90: y5..10[first a0.55 G0.32 B0.71; last a0.62 G0.32 B0.71] y27..29[first a1.00 G0.32 B0.71; last a1.00 G0.32 B0.71]
//   TG10cn the same without a strikethrough -> | x4: y5..10[first a0.55 G0.12 B0.17; last a0.62 G0.13 B0.16] | x90: y5..10[first a0.55 G0.32 B0.71; last a0.62 G0.32 B0.71]
//   TG10d strikethrough(color: green) -> | x4: y5..10[first a0.55 G0.12 B0.17; last a0.62 G0.13 B0.16] y27..29[first a1.00 G0.78 B0.35; last a1.00 G0.78 B0.35] | x90: y5..10[first a0.55 G0.32 B0.71; last a0.62 G0.32 B0.71] y27..29[first a1.00 G0.78 B0.35; last a1.00 G0.78 B0.35]
//   TG11 background(yellow): the yellow stays -> | band0 y0..50 [row25 run x0(G0.05 B0.09 a1.00) .. x159(G0.06 B0.98 a1.00)]
//   TG14 Rectangle().frame(160, 20).foregroundStyle(g) (the P14c control) -> | band0 y0..19 [row9 run x0(G0.02 B0.02 a1.00) box=0.02 .. x159(G0.01 B1.00 a1.00) box=1.00]
//   TG12 .ultraThinMaterial on text: NOT MEASURABLE (ImageRenderer draws no material)
//   TG13 selection of gradient text: NOT MEASURABLE (no selection in ImageRenderer)
//
// READING (the rulings `TG-` rest on these).
//   TG0 separates: left B .09, right B .99 (red to blue); the control `Color.red` reads B 0 twice. **A gradient
//   foreground style on Text is a gradient, not its first stop.**
//   TG1, TG2: ONE span over the whole text, not per glyph, cluster or line. `TG1x` frame178 .07 against the
//   first cluster's own box .58 (`TG1y`: the second cluster against the frame .02, against its own box .63);
//   `TG2ax`/`TG2ay` frame .05 against the line .55; `TG2bx` frame .07 against the line .54. The wrapped lines
//   share one gradient.
//   TG3: the span is the glyphs' INK, on both axes. `TG3d` (eight spaces each side): ink .08 against the layout
//   box .40; `TG3ax` ink .08 against the box .15; `TG2d` (upper half blocks, a vertical gradient over ink rows
//   y7..28): ink .04-.09 against the layout box .31; `TG8x` radial: ink .03 against the box .11. Leading and
//   trailing spaces and the line's ascent and descent are not in it. `TG3bx`: a frame(width: 300) is not it
//   (.09 against .71), `TG3cx`: nor is padding(20) (.09 against .22).
//   TG4: a container's gradient spans each Text separately (`TG4x`: the text's own box .09 against the
//   container .65), the same as styling each Text.
//   TG5: **the span is the union of the ink of every run that carries that same gradient.** `TG5ax` (a red run
//   then a gradient run): the gradient run's own box .09, the whole text .51. `TG5bx`/`TG5cx` (both runs
//   carry g, by the whole text's modifier or each run's own): one span over both (.05 against .60 for a run's
//   own box). `TG5d`/`TG5e` (g, green, g): the first and third runs share one span over the whole text
//   (.03/.05 against .72/.68 for their own boxes).
//   TG6: the shadow is the shadow colour: black at x163 and x167 (B 0, a 1.00), beyond the gradient glyphs.
//   TG7: an opacity of .5 is alpha .50 and the same gradient (the fade applies once).
//   TG8: radial: the centre and the radius are over the INK box (`TG8x` ink .03, box .11, canvas .99; `TG8y`
//   ink .03, canvas 1.00); `endRadius` is in points.
//   TG9: `.secondary` over a gradient parent keeps the gradient at alpha .50 (P14 on text, the same as a shape).
//   TG10, TG10c: the underline and the strikethrough are part of the gradient: their rows read B .20 at x4 and
//   .95 at x90 (the glyph rows .21 and .95); `TG10v` (a vertical gradient with an underline, glyph rows y7..28,
//   underline y41..42): the glyph's last row reads B .71 with the underline against .93 without, so **the
//   decoration extends the span**. `TG10b`, `TG10d`: a decoration with its own colour stays that colour
//   (G .78 B .35 at both x4 and x90).
//   TG11: a background keeps its own colour (G 1.00 B 0.00 at the top row).
//   TG14: `Rectangle().foregroundStyle(g)` paints the gradient (P14c).
//   TG12 (a material on text) and TG13 (selection) cannot be measured: `ImageRenderer` draws no material and
//   has no selection.
import SwiftUI
import AppKit

nonisolated(unsafe) var lines: [String] = []

struct Px { var r: Double; var g: Double; var b: Double; var a: Double }

struct Shot {
    var w: Int, h: Int, data: [UInt8]
    func px(_ x: Int, _ y: Int) -> Px {
        let i = (y * w + x) * 4
        let a = Double(data[i + 3]) / 255
        guard a > 0 else { return Px(r: 0, g: 0, b: 0, a: 0) }
        func c(_ k: Int) -> Double { min(1, Double(data[i + k]) / 255 / a) }
        return Px(r: c(0), g: c(1), b: c(2), a: a)
    }
}

@MainActor
func shot<V: View>(_ view: V) -> Shot {
    let content = view.frame(width: 320, height: 140, alignment: .topLeading).environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let image = renderer.cgImage else { return Shot(w: 0, h: 0, data: []) }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Shot(w: w, h: h, data: data)
}

func f1(_ v: Double) -> String { String(format: "%.2f", v) }
func f2(_ v: Double) -> String { String(format: "%.2f", v) }
/// One reading: the blue channel to one decimal (the ImageRenderer gradient flickers by 1/255 in the low
/// bits between runs, so the output keeps one decimal of B and two of alpha) and the alpha.
func fp(_ p: Px) -> String { "(G\(f1(p.g)) B\(f1(p.b)) a\(f2(p.a)))" }

/// The blue channel of a `width`-wide horizontal gradient Rectangle at column `x` (the calibration the
/// hypotheses are read against: the gradient interpolates perceptually, so B is not t).
@MainActor
func refB(width: Int, x: Int) -> Double {
    let s = shot(Rectangle().frame(width: CGFloat(width), height: 6).foregroundStyle(
        LinearGradient(colors: [Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1),
                                Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)],
                       startPoint: .leading, endPoint: .trailing)))
    return s.px(max(0, min(width - 1, x)), 3).b
}

/// Ink bands and runs, as the header describes. `rows` are explicit sample rows (default: each band's middle);
/// `hyp` are (name, x0, width) spans whose horizontal-gradient B at a run's end columns is printed as `name=`.
@MainActor
func arm<V: View>(_ id: String, _ what: String, minAlpha: Double = 0.5, rows: [Int]? = nil, v: Bool = false,
                  hyp: [(String, Int, Int)] = [], _ view: V) {
    let s = shot(view)
    var out = "\(id) \(what) ->"
    func ink(_ x: Int, _ y: Int) -> Bool { s.px(x, y).a >= minAlpha }
    var bands: [(Int, Int)] = []
    var y = 0
    while y < s.h {
        if (0..<s.w).contains(where: { ink($0, y) }) {
            let y0 = y
            while y < s.h, (0..<s.w).contains(where: { ink($0, y) }) { y += 1 }
            bands.append((y0, y - 1))
        } else { y += 1 }
    }
    if bands.isEmpty { lines.append(out + " nothing drawn"); return }
    for (bi, band) in bands.enumerated() {
        out += " | band\(bi) y\(band.0)..\(band.1)"
        for mid in rows ?? [(band.0 + band.1) / 2] {
            var runs: [(Int, Int)] = []
            var x = 0
            while x < s.w {
                if ink(x, mid) {
                    let x0 = x
                    while x < s.w, ink(x, mid) { x += 1 }
                    runs.append((x0, x - 1))
                } else { x += 1 }
            }
            out += " [row\(mid)"
            for run in runs {
                func at(_ x: Int) -> String {
                    var t = "x\(x)\(fp(s.px(x, mid)))"
                    for h in hyp { t += " \(h.0)=\(f1(refB(width: h.2, x: x - h.1)))" }
                    return t
                }
                out += " run \(at(run.0)) .. \(at(run.1))"
            }
            out += "]"
        }
        if v, let first = (0..<s.w).first(where: { ink($0, (band.0 + band.1) / 2) }) {
            let cx = first + 4
            let h = band.1 - band.0
            let ys = [0, h / 4, h / 2, 3 * h / 4, h].map { band.0 + $0 }
            out += " V@x\(cx) " + ys.map { "y\($0)\(fp(s.px(cx, $0)))" }.joined(separator: " ")
        }
    }
    lines.append(out)
}

/// Compares a text arm with a Rectangle filled with the SAME style over a hypothesised span, at every pixel
/// the text covers fully (alpha >= `minA`) inside `where`: prints the maximum and mean of the largest
/// channel difference (R, G, B) and the pixel count. A hypothesis with a small maximum is the span.
@MainActor
func cmp<V: View, S: ShapeStyle>(_ id: String, _ what: String, minA: Double = 0.99, _ style: S,
                                 hyps: [(String, Int, Int, Int, Int)],
                                 where keep: (Int, Int) -> Bool = { _, _ in true }, _ view: V) {
    let text = shot(view)
    var out = "\(id) \(what) ->"
    for h in hyps {
        let rect = shot(Rectangle().fill(style).frame(width: CGFloat(h.3), height: CGFloat(h.4))
            .padding(.leading, CGFloat(h.1)).padding(.top, CGFloat(h.2)))
        var worst = 0.0, sum = 0.0, n = 0
        for y in 0..<text.h { for x in 0..<text.w {
            let a = text.px(x, y), b = rect.px(x, y)
            guard a.a >= minA, keep(x, y), b.a >= 0.99 else { continue }
            let d = max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b))
            worst = max(worst, d); sum += d; n += 1
        } }
        out += " \(h.0): max \(f2(worst)) mean \(f2(n == 0 ? 0 : sum / Double(n))) n=\(n);"
    }
    lines.append(out)
}

/// Vertical dumps: for each x, every row with alpha > .05 as y:a/G/B (two decimals), grouped into runs of rows.
@MainActor
func colDump<V: View>(_ id: String, _ what: String, xs: [Int], _ view: V) {
    let s = shot(view)
    var out = "\(id) \(what) ->"
    for x in xs {
        out += " | x\(x):"
        var y = 0
        while y < s.h {
            if s.px(x, y).a > 0.05 {
                let y0 = y
                while y < s.h, s.px(x, y).a > 0.05 { y += 1 }
                let a = s.px(x, y0), b = s.px(x, y - 1)
                out += " y\(y0)..\(y - 1)[first a\(f2(a.a)) G\(f2(a.g)) B\(f2(a.b)); last a\(f2(b.a)) G\(f2(b.g)) B\(f2(b.b))]"
            } else { y += 1 }
        }
    }
    lines.append(out)
}

/// The layout box of a view whose body is painted green.
@MainActor
func box<V: View>(_ id: String, _ what: String, _ view: V) {
    let s = shot(view)
    var x0 = s.w, x1 = -1, y0 = s.h, y1 = -1
    for y in 0..<s.h { for x in 0..<s.w where s.px(x, y).a > 0.5 {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    lines.append("\(id) \(what) -> layout box x\(x0)..\(x1) y\(y0)..\(y1) (w \(x1 - x0 + 1) h \(y1 - y0 + 1))")
}

/// Shadow-only pixel readings: the pixel left of the first ink column and right of the last, at mid height.
@MainActor
func row<V: View>(_ id: String, _ what: String, xs: [Int], y: Int, _ view: V) {
    let s = shot(view)
    lines.append("\(id) \(what) -> " + xs.map { "x\($0)y\(y)=\(fp(s.px($0, y)))" }.joined(separator: " "))
}

@MainActor
func run() {
    let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)
    let blue = Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1)
    let g = LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)
    let gv = LinearGradient(colors: [red, blue], startPoint: .top, endPoint: .bottom)
    func t(_ s: String) -> Text { Text(s).font(.system(size: 40)) }
    let lime = Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1)

    lines.append("--- BOX: the layout boxes (green)")
    box("BOX1", "4 blocks", t("\u{2588}\u{2588}\u{2588}\u{2588}").background(lime))
    box("BOX2", "2 blocks, gap, 2 blocks", t("\u{2588}\u{2588}  \u{2588}\u{2588}").background(lime))
    box("BOX3", "space 2 space", t(" \u{2588}\u{2588} ").background(lime))
    box("BOX4", "2 blocks", t("\u{2588}\u{2588}").background(lime))
    box("BOX5", "2 lines 2/2", t("\u{2588}\u{2588}\n\u{2588}\u{2588}").background(lime))
    box("BOX6", "2 lines 4/2", t("\u{2588}\u{2588}\u{2588}\u{2588}\n\u{2588}\u{2588}").background(lime))
    box("BOX7", "VStack leading 2 / 6", VStack(alignment: .leading, spacing: 0) {
        t("\u{2588}\u{2588}").background(lime); t("\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}").background(lime) })
    box("BOX8", "2 + 2 concatenated", (t("\u{2588}\u{2588}") + t("\u{2588}\u{2588}")).background(lime))
    box("BOX9", "3 blocks", t("\u{2588}\u{2588}\u{2588}").background(lime))

    let B = "\u{2588}"
    lines.append("--- TG0 .. TG2: does it separate, and per glyph / line / frame (hyp: box=the layout box, ink=the run)")
    arm("TG0", "4 blocks, gradient (SEPARATING: B rises left to right)", hyp: [("box", 0, 160)],
        t(String(repeating: B, count: 4)).foregroundStyle(g))
    arm("TG0c", "4 blocks, Color.red (control)", t(String(repeating: B, count: 4)).foregroundStyle(red))
    arm("TG1", "2 blocks, gap, 2 blocks (box 178 wide; per glyph would restart at the second cluster)",
        hyp: [("frame", 0, 178), ("cluster", 0, 80)], t(B + B + "  " + B + B).foregroundStyle(g))
    arm("TG2a", "2 lines, top-to-bottom: V profile, per line would restart at y49", v: true, t(B + B + "\n" + B + B).foregroundStyle(gv))
    arm("TG2b", "2 lines 4/2, horizontal, rows 25 and 75 (line 2 right edge: per line B1.0, per frame mid)",
        rows: [25, 75], hyp: [("frame", 0, 160), ("line", 0, 80)],
        t(String(repeating: B, count: 4) + "\n" + B + B).foregroundStyle(g))

    lines.append("--- TG3: which box")
    arm("TG3a", "space 2 space (box 98 wide, first ink at x8): box B=ref(98, 8), ink B=ref(80, 0)",
        hyp: [("box", 0, 98), ("ink", 8, 80)], t(" " + B + B + " ").foregroundStyle(g))
    arm("TG3b", "frame(width 300) then the style (box = the frame would be 300 wide)",
        hyp: [("leaf", 0, 80), ("frame", 0, 300)], t(B + B).frame(width: 300, alignment: .leading).foregroundStyle(g))
    arm("TG3b2", "Text.foregroundStyle then frame(width 300)",
        hyp: [("leaf", 0, 80), ("frame", 0, 300)], t(B + B).foregroundStyle(g).frame(width: 300, alignment: .leading))
    arm("TG3c", "padding(20) then the style (padded box 120 wide)",
        hyp: [("leaf", 20, 80), ("padded", 0, 120)], t(B + B).padding(20).foregroundStyle(g))

    lines.append("--- TG4: a container (BOX7: 240 wide, the short text 80)")
    arm("TG4", "VStack leading { 2 blocks; 6 blocks }.foregroundStyle(g), rows 25 and 75",
        rows: [25, 75], hyp: [("container", 0, 240), ("text", 0, 80)],
        VStack(alignment: .leading, spacing: 0) { t(B + B); t(String(repeating: B, count: 6)) }.foregroundStyle(g))
    arm("TG4b", "the same, each Text styled, rows 25 and 75",
        rows: [25, 75], hyp: [("container", 0, 240), ("text", 0, 80)],
        VStack(alignment: .leading, spacing: 0) { t(B + B).foregroundStyle(g); t(String(repeating: B, count: 6)).foregroundStyle(g) })

    lines.append("--- TG5: concatenation (BOX8: 160 wide, runs 80 each)")
    arm("TG5a", "interpolation, red first run, gradient second run",
        hyp: [("whole", 0, 160), ("run", 80, 80)],
        Text("\(Text(B + B).foregroundStyle(red))\(Text(B + B).foregroundStyle(g))").font(.system(size: 40)))
    arm("TG5b", "(Text + Text).foregroundStyle(g)", hyp: [("whole", 0, 160), ("run", 0, 80)], (t(B + B) + t(B + B)).foregroundStyle(g))
    arm("TG5c", "both runs carry g separately", hyp: [("whole", 0, 160), ("run", 0, 80)],
        (t(B + B).foregroundStyle(g) + t(B + B).foregroundStyle(g)))

    lines.append("--- CMP: the span, read as the maximum channel difference against a Rectangle over each hypothesis")
    let b4 = String(repeating: B, count: 4), b6 = String(repeating: B, count: 6)
    let U = "\u{2580}"
    let u4 = String(repeating: U, count: 4)
    cmp("TG0x", "4 blocks: box vs ink span", g,
        hyps: [("box0,0,160x51", 0, 0, 160, 51), ("ink0,3,160x48", 0, 3, 160, 48), ("frame0,0,320x140", 0, 0, 320, 140)],
        t(b4).foregroundStyle(g))
    cmp("TG1x", "2 blocks, gap, 2 blocks, whole: frame vs ink vs frame-of-first-cluster", g,
        hyps: [("frame178", 0, 0, 178, 51), ("ink177", 0, 3, 177, 48), ("cluster80", 0, 0, 80, 51)],
        t(B + B + "  " + B + B).foregroundStyle(g))
    cmp("TG1y", "the second cluster alone (x >= 97): frame vs its own box", g,
        hyps: [("frame178", 0, 0, 178, 51), ("cluster97+80", 97, 0, 80, 51)], where: { x, _ in x >= 97 },
        t(B + B + "  " + B + B).foregroundStyle(g))
    cmp("TG2ax", "2 lines top-to-bottom: frame vs ink vs line", gv,
        hyps: [("frame80x98", 0, 0, 80, 98), ("ink y3..97", 0, 3, 80, 95), ("line1 only", 0, 0, 80, 49)],
        t(B + B + "\n" + B + B).foregroundStyle(gv))
    cmp("TG2ay", "line 2 alone (y >= 49): frame vs its own line", gv,
        hyps: [("frame80x98", 0, 0, 80, 98), ("line2 0,49,80x49", 0, 49, 80, 49)], where: { _, y in y >= 49 },
        t(B + B + "\n" + B + B).foregroundStyle(gv))
    cmp("TG2c", "one line, vertical: layout box vs ink rows", gv,
        hyps: [("layout0,0,80x51", 0, 0, 80, 51), ("ink3,48", 0, 3, 80, 48)],
        t(B + B).foregroundStyle(gv))
    cmp("TG2bx", "4/2 lines horizontal: the frame vs a per-line span (line 2 rows only)", g,
        hyps: [("frame160", 0, 49, 160, 49), ("line80", 0, 49, 80, 49)], where: { _, y in y >= 49 },
        t(b4 + "\n" + B + B).foregroundStyle(g))
    cmp("TG3ax", "space 2 space: layout box vs ink columns", g,
        hyps: [("box98", 0, 0, 98, 51), ("ink x8..87 y0", 8, 0, 80, 51), ("ink x8 y3", 8, 3, 80, 48)],
        t(" " + B + B + " ").foregroundStyle(g))
    cmp("TG3bx", "frame(300): leaf vs frame", g,
        hyps: [("leaf80", 0, 0, 80, 51), ("frame300", 0, 0, 300, 51)],
        t(B + B).frame(width: 300, alignment: .leading).foregroundStyle(g))
    cmp("TG3cx", "padding(20): leaf vs padded box", g,
        hyps: [("leaf@20,20 80x51", 20, 20, 80, 51), ("padded 120x91", 0, 0, 120, 91)],
        t(B + B).padding(20).foregroundStyle(g))
    cmp("TG4x", "VStack, text 1 (y < 49): its own box vs the container", g,
        hyps: [("text80x49", 0, 0, 80, 49), ("container240x98", 0, 0, 240, 98)], where: { _, y in y < 49 },
        VStack(alignment: .leading, spacing: 0) { t(B + B); t(b6) }.foregroundStyle(g))
    cmp("TG4y", "VStack, text 2 (y >= 49): its own box vs the container", g,
        hyps: [("text240x49", 0, 49, 240, 49), ("container240x98", 0, 0, 240, 98)], where: { _, y in y >= 49 },
        VStack(alignment: .leading, spacing: 0) { t(B + B); t(b6) }.foregroundStyle(g))
    cmp("TG5ax", "red run then a gradient run, second run (x >= 80): whole vs the run's own box", g,
        hyps: [("whole160", 0, 0, 160, 51), ("run80@80", 80, 0, 80, 51)], where: { x, _ in x >= 80 },
        Text("\(Text(B + B).foregroundStyle(red))\(Text(B + B).foregroundStyle(g))").font(.system(size: 40)))
    cmp("TG5bx", "(Text + Text).foregroundStyle(g): whole vs run 2 own box (x >= 80)", g,
        hyps: [("whole160", 0, 0, 160, 51), ("run80@80", 80, 0, 80, 51)], where: { x, _ in x >= 80 },
        (t(B + B) + t(B + B)).foregroundStyle(g))
    cmp("TG5cx", "both runs carry g: run 2 (x >= 80): whole vs its own box", g,
        hyps: [("whole160", 0, 0, 160, 51), ("run80@80", 80, 0, 80, 51)], where: { x, _ in x >= 80 },
        (t(B + B).foregroundStyle(g) + t(B + B).foregroundStyle(g)))
    let rg = RadialGradient(colors: [red, blue], center: .center, startRadius: 0, endRadius: 40)
    let rg2 = RadialGradient(colors: [red, blue], center: .center, startRadius: 0, endRadius: 100)
    let rg3 = RadialGradient(colors: [red, blue], center: .topLeading, startRadius: 0, endRadius: 100)
    cmp("TG8x", "radial 0..40 on 3 blocks: box vs ink vs the canvas", rg,
        hyps: [("box120x51", 0, 0, 120, 51), ("ink120x48", 0, 3, 120, 48), ("canvas320x140", 0, 0, 320, 140)],
        t(B + B + B).foregroundStyle(rg))
    cmp("TG8y", "radial 0..100 on 3 blocks: box vs ink vs the canvas", rg2,
        hyps: [("box120x51", 0, 0, 120, 51), ("ink120x48", 0, 3, 120, 48), ("canvas320x140", 0, 0, 320, 140)],
        t(B + B + B).foregroundStyle(rg2))
    cmp("TG8z", "radial topLeading 0..100 on 3 blocks: box vs ink vs the canvas", rg3,
        hyps: [("box120x51", 0, 0, 120, 51), ("ink120x48", 0, 3, 120, 48), ("canvas320x140", 0, 0, 320, 140)],
        t(B + B + B).foregroundStyle(rg3))
    cmp("TG7x", "opacity .5: box (alpha compared at .49)", minA: 0.49, g,
        hyps: [("box160x51", 0, 0, 160, 51)], t(b4).foregroundStyle(g).opacity(0.5))

    cmp("TG2d", "upper half blocks, top-to-bottom: layout box vs ink rows y7..28 (the TG10n dump)", gv,
        hyps: [("layout0,0,96x51", 0, 0, 96, 51), ("ink y7 h22", 0, 7, 96, 22), ("ink y6 h24", 0, 6, 96, 24),
               ("ink y7 h23", 0, 7, 96, 23)],
        t(u4).foregroundStyle(gv))
    box("BOX10", "8 spaces, 2 blocks, 8 spaces", t("        " + B + B + "        ").background(lime))
    arm("TG3d0", "8 spaces, 2 blocks, 8 spaces: the ink run", hyp: [("box", 0, 80 + 2 * 8 * 9)],
        t("        " + B + B + "        ").foregroundStyle(g))
    cmp("TG3d", "8 spaces, 2 blocks, 8 spaces: layout box vs ink", g,
        hyps: [("box218", 0, 0, 218, 51), ("ink x68", 68, 0, 80, 51)],
        t("        " + B + B + "        ").foregroundStyle(g))
    let red2 = Color(.sRGB, red: 0, green: 0.5, blue: 0, opacity: 1)
    cmp("TG5d", "g, green, g: the third run (x >= 160): its own box vs the whole", g,
        hyps: [("whole240", 0, 0, 240, 51), ("run3 80@160", 160, 0, 80, 51)], where: { x, _ in x >= 160 },
        Text("\(Text(B + B).foregroundStyle(g))\(Text(B + B).foregroundStyle(red2))\(Text(B + B).foregroundStyle(g))").font(.system(size: 40)))
    cmp("TG5e", "g, green, g: the first run (x < 80): its own box vs the whole", g,
        hyps: [("whole240", 0, 0, 240, 51), ("run1 80@0", 0, 0, 80, 51)], where: { x, _ in x < 80 },
        Text("\(Text(B + B).foregroundStyle(g))\(Text(B + B).foregroundStyle(red2))\(Text(B + B).foregroundStyle(g))").font(.system(size: 40)))

    lines.append("--- TG6 .. TG14")
    row("TG6", "shadow black r0 x8 under g, at y25 (ink x0..159; the shadow-only pixels are x160..167)",
        xs: [2, 100, 158, 160, 163, 167], y: 25,
        t(String(repeating: B, count: 4)).foregroundStyle(g).shadow(color: .black, radius: 0, x: 8, y: 0))
    arm("TG7", "opacity .5", hyp: [("box", 0, 160)], t(String(repeating: B, count: 4)).foregroundStyle(g).opacity(0.5))
    arm("TG8", "radial red->blue, center, 0..40 pt, 3 blocks (box 120 x 51: center (60, 25))",
        rows: [25], t(B + B + B).foregroundStyle(RadialGradient(colors: [red, blue], center: .center, startRadius: 0, endRadius: 40)))
    arm("TG9", ".secondary over a gradient parent", hyp: [("box", 0, 160)],
        t(String(repeating: B, count: 4)).foregroundStyle(.secondary).foregroundStyle(g))
    colDump("TG10", "upper half blocks + underline then the style: column dumps at x4 and x90", xs: [4, 90],
            t(u4).underline().foregroundStyle(g))
    colDump("TG10n", "the same without an underline (the glyph rows alone)", xs: [4, 90], t(u4).foregroundStyle(g))
    colDump("TG10v", "vertical gradient + underline: does the underline extend the span? (glyph rows y7..28, underline y41..42)",
            xs: [4], t(u4).underline().foregroundStyle(gv))
    colDump("TG10vn", "the same without an underline", xs: [4], t(u4).foregroundStyle(gv))
    colDump("TG10b", "underline(color: green)", xs: [4, 90], t(u4).underline(color: .green).foregroundStyle(g))
    let o4 = String(repeating: "\u{2594}", count: 4)
    colDump("TG10c", "upper one-eighth blocks + strikethrough then the style", xs: [4, 90], t(o4).strikethrough().foregroundStyle(g))
    colDump("TG10cn", "the same without a strikethrough", xs: [4, 90], t(o4).foregroundStyle(g))
    colDump("TG10d", "strikethrough(color: green)", xs: [4, 90], t(o4).strikethrough(color: .green).foregroundStyle(g))
    arm("TG11", "background(yellow): the yellow stays", rows: [25],
        t(String(repeating: B, count: 4)).foregroundStyle(g).background(Color(.sRGB, red: 1, green: 1, blue: 0, opacity: 1)))
    arm("TG14", "Rectangle().frame(160, 20).foregroundStyle(g) (the P14c control)", hyp: [("box", 0, 160)],
        Rectangle().frame(width: 160, height: 20).foregroundStyle(g))
    lines.append("TG12 .ultraThinMaterial on text: NOT MEASURABLE (ImageRenderer draws no material)")
    lines.append("TG13 selection of gradient text: NOT MEASURABLE (no selection in ImageRenderer)")
}

MainActor.assumeIsolated { run() }
print(lines.joined(separator: "\n"))
