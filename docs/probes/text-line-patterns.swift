// SwiftUI probe: Text.LineStyle patterns and the view-level text modifiers (round 3 item
// R3-10 part 1, rulings TM-* in docs/superpowers/2026-11-01-text-view-modifiers-decisions.md).
// Questions the rulings rest on:
//   P   For each `Text.LineStyle.Pattern` (.solid .dot .dash .dashDot .dashDotDot), the on/off
//       run lengths (in points, measured at 8x scale along the middle row of the decoration
//       band) of an underline and of a strikethrough, at two font sizes, and the band's
//       thickness; so segment and gap lengths can be stated as multiples of thickness.
//   PL  Does a pattern restart at each wrapped line's start (the phase at x = 0 of line 2
//       equals line 1's)?
//   PR  Across two adjacent runs with the same pattern (`Text + Text`), does the phase carry
//       across the run boundary, or restart at the second run?
//   V   View-level modifiers read by a `Text` below: kerning, tracking, baselineOffset,
//       monospaced, bold, underline (ink extent compared with the Text-level spelling).
//   W   Precedence: a modifier written on the `Text` wins over the environment (inner wins),
//       for kerning, underline(false) and a pattern.
//   B   Reach: a Button label under a view-level `.kerning`.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/text-line-patterns.swift -o /tmp/tlp && /tmp/tlp
//
// RECORDED OUTPUT (macOS 27.0, 2026-11-01; lengths in points, measured at 8x scale along the middle row of
// the decoration band; ink extents at 4x):
//
//   P underline solid size 13.0 thickness 1.000 y 14.0...15.0 runs(on,off,...) 230.00
//   P strikethrough solid size 13.0 thickness 1.000 y 9.0...10.0 runs(on,off,...) 230.00
//   P underline dot size 13.0 thickness 1.000 y 14.0...15.0 runs(on,off,...) 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00
//   P strikethrough dot size 13.0 thickness 1.000 y 9.0...10.0 runs(on,off,...) 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00
//   P underline dash size 13.0 thickness 1.000 y 14.0...15.0 runs(on,off,...) 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   P strikethrough dash size 13.0 thickness 1.000 y 9.0...10.0 runs(on,off,...) 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   P underline dashDot size 13.0 thickness 1.000 y 14.0...15.0 runs(on,off,...) 10.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 10.00
//   P strikethrough dashDot size 13.0 thickness 1.000 y 9.0...10.0 runs(on,off,...) 10.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 10.00
//   P underline dashDotDot size 13.0 thickness 1.000 y 14.0...15.0 runs(on,off,...) 10.00 3.00 3.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 3.00 3.00 10.00
//   P strikethrough dashDotDot size 13.0 thickness 1.000 y 9.0...10.0 runs(on,off,...) 10.00 3.00 3.00 3.00 3.00 3.00 10.00 3.00 3.00 3.00 3.00 3.00 10.00
//   P underline solid size 28.0 thickness 2.000 y 30.0...32.0 runs(on,off,...) 400.00
//   P strikethrough solid size 28.0 thickness 2.000 y 19.0...21.0 runs(on,off,...) 400.00
//   P underline dot size 28.0 thickness 2.000 y 30.0...32.0 runs(on,off,...) 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00
//   P strikethrough dot size 28.0 thickness 2.000 y 19.0...21.0 runs(on,off,...) 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00 6.00
//   P underline dash size 28.0 thickness 2.000 y 30.0...32.0 runs(on,off,...) 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00
//   P strikethrough dash size 28.0 thickness 2.000 y 19.0...21.0 runs(on,off,...) 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00 10.00 20.00
//   P underline dashDot size 28.0 thickness 2.000 y 30.0...32.0 runs(on,off,...) 20.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 20.00
//   P strikethrough dashDot size 28.0 thickness 2.000 y 19.0...21.0 runs(on,off,...) 20.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 20.00
//   P underline dashDotDot size 28.0 thickness 2.000 y 30.0...32.0 runs(on,off,...) 20.00 6.00 6.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 6.00 6.00 20.00
//   P strikethrough dashDotDot size 28.0 thickness 2.000 y 19.0...21.0 runs(on,off,...) 20.00 6.00 6.00 6.00 6.00 6.00 20.00 6.00 6.00 6.00 6.00 6.00 20.00
//   PL bands 4
//   PL band y 112...119 startsOn true runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PL band y 240...247 startsOn true runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PL band y 368...375 startsOn true runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PL band y 496...503 startsOn true runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PR one run: runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PR two runs, same style: runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PR two runs, colour differs: runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   T  size 9.0 SwiftUI thickness 1.0  CoreText system-font underline thickness 0.527 (SFNS 0.444)
//   T  size 11.0 SwiftUI thickness 1.0  CoreText system-font underline thickness 0.645 (SFNS 0.542)
//   T  size 13.0 SwiftUI thickness 1.0  CoreText system-font underline thickness 0.762 (SFNS 0.641)
//   T  size 15.0 SwiftUI thickness 1.0  CoreText system-font underline thickness 0.879 (SFNS 0.740)
//   T  size 17.0 SwiftUI thickness 1.0  CoreText system-font underline thickness 0.996 (SFNS 0.838)
//   T  size 20.0 SwiftUI thickness 2.0  CoreText system-font underline thickness 1.172 (SFNS 0.986)
//   T  size 24.0 SwiftUI thickness 2.0  CoreText system-font underline thickness 1.406 (SFNS 1.184)
//   T  size 28.0 SwiftUI thickness 2.0  CoreText system-font underline thickness 1.641 (SFNS 1.381)
//   T  size 36.0 SwiftUI thickness 3.0  CoreText system-font underline thickness 2.109 (SFNS 1.775)
//   T  size 48.0 SwiftUI thickness 3.0  CoreText system-font underline thickness 2.812 (SFNS 2.367)
//   T  size 72.0 SwiftUI thickness 5.0  CoreText system-font underline thickness 4.219 (SFNS 3.551)
//   PS plain 8H then dash 8H (lead-in = plain width): lead-in 76.62 first runs 8.38 5.00 10.00 5.00 10.00 5.00 10.00
//   PS dash 8H then plain 8H: lead-in 0.00 first runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PS centered 6H dash in 300 frame: lead-in 121.25 first runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PS trailing 6H dash in 300 frame: lead-in 242.50 first runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PS RTL 6H dash: lead-in 0.12 first runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   PS dash 8H then dot 8H (all runs): lead-in 0.00 first runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 2.00 1.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 3.00 147.00
//   V  kerning 5 on Text    x 0.5...66.25 y 4.75...19.0
//   V  kerning 5 on view    x 0.5...66.25 y 4.75...19.0
//   V  kerning 5 view-level x 0.5...66.25 y 4.75...19.0
//   V  tracking 5 text      x 0.5...66.25 y 4.75...19.0
//   V  tracking 5 view      x 0.5...66.25 y 4.75...19.0
//   V  baselineOffset 6 text x 0.5...51.25 y 4.75...19.0
//   V  baselineOffset 6 view x 0.5...51.25 y 4.75...19.0
//   V  monospaced text      x 2.0...49.5 y 3.0...19.0
//   V  monospaced view      x 2.0...49.5 y 3.0...19.0
//   V  plain iiWW           x 1.25...45.75 y 4.25...19.0
//   V  bold text            x 0.5...56.0 y 4.75...19.0
//   V  bold view            x 0.5...56.0 y 4.75...19.0
//   V  plain                x 0.5...51.25 y 4.75...19.0
//   V  underline view       x 0.0...52.0 y 4.75...23.0
//   V  underline text       x 0.0...52.0 y 4.75...23.0
//   V  underline dash view  x 0.0...51.25 y 4.75...23.0
//   W  kerning 2 text in kerning 5: x 0.5...57.25 y 4.75...19.0   (text 2 alone: x 0.5...57.25 y 4.75...19.0, 5 alone: x 0.5...66.25 y 4.75...19.0)
//   W  kerning 5 around plain text, outer 0 inside: x 0.5...51.25 y 4.75...19.0
//   W  underline(false) text in underline view: x 0.5...51.25 y 4.75...19.0  (plain x 0.5...51.25 y 4.75...19.0)
//   W  underline(false) VIEW inside underline view: x 0.5...51.25 y 4.75...19.0
//   W  view-level dash, plain text: runs 10.00 5.00 10.00 5.00 10.00 5.00 10.00 5.00 10.00
//   W  text solid black inside view dash red: first runs 154.00 46.00
//   W  view kerning 2 inside view kerning 5: x 0.5...57.25 y 4.75...19.0
//   W  weight: light outside bold x 0.5...50.25 y 4.75...19.0  bold outside light x 0.5...50.25 y 4.75...19.0  light alone x 0.5...50.25 y 4.75...19.0
//   W  light font + view bold: x 0.5...50.25 y 4.75...19.0  light font alone x 0.5...50.25 y 4.75...19.0
//   W  headline + view bold: x 0.5...39.0 y 3.75...13.0  headline alone x 0.5...37.25 y 3.75...13.0  headline.bold() x 0.5...39.0 y 3.75...13.0
//   W  text fontWeight(.light) inside view bold: x 0.5...50.25 y 4.75...19.0
//   B  Button under kerning 5: x 0.5...66.25 y 4.75...19.0   plain x 0.5...51.25 y 4.75...19.0)
//
// READING.
//   P/T  Every pattern is a cycle of whole multiples of the band's thickness t, starting "on":
//        dot 3t on / 3t off; dash 10t / 5t; dashDot 10t / 3t / 3t / 3t; dashDotDot 10t / 3t / 3t / 3t /
//        3t / 3t; underline and strikethrough alike. SwiftUI's thickness is a whole number of points
//        (1 for 9-17 pt, 2 for 20-28 pt, 3 for 36-48 pt, 5 for 72 pt): exactly ceil of CoreText's
//        underline thickness at every size measured (0.527 -> 1 ... 4.219 -> 5). Ruling TM-C.
//   PL/PS/PR  The phase belongs to the LINE: every wrapped line starts "on" at its own start (a
//        centred or trailing line too: lead-in 121.25 / 242.50, then a full 10); an underline that
//        begins mid-line is cut from the line's cycle (plain 8H then dash: 8.38 on = 10 - (76.62 mod 15));
//        neighbouring runs of one pattern continue the cycle whatever their colour; at a pattern change
//        the new shape takes over at the same x with ITS cycle from the line start (dash then dot:
//        the dot "on" resumes at x = 78, a multiple of the dot period 6). Ruling TM-D.
//   V/W  A view-level kerning, tracking, baselineOffset, monospaced, bold and underline reach the Text
//        below exactly as its own modifier does (equal ink extents); a Text's own value wins (kerning 2
//        inside kerning 5 draws kerning 2); the nearest writer wins (an inner kerning(0) resets an outer
//        5); an own underline replaces the environment's whole - pattern and colour (solid black own
//        inside dashed red view: solid black); underline(false) on the Text or on a nearer view is none.
//        Bold is a weight of last resort: under `.fontWeight(.light)` and in a `.light` font it stays
//        light in either nesting order, on `.headline` it equals `Font.headline.bold()`. A Button label
//        reads the view-level kerning. Rulings TM-A, TM-F.

import SwiftUI
import AppKit
import CoreText

struct Bitmap { var w: Int; var h: Int; var data: [UInt8]
    func dark(_ x: Int, _ y: Int) -> Bool { data[(y * w + x) * 4] < 128 }
}

@MainActor
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, scale: CGFloat) -> Bitmap {
    let framed = view.frame(width: width, height: height, alignment: .topLeading).background(Color.white)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = scale
    guard let image = renderer.cgImage else { return Bitmap(w: 0, h: 0, data: []) }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Bitmap(w: w, h: h, data: data)
}

/// Rows containing any dark pixel, as contiguous bands (y0, y1).
func bands(_ b: Bitmap) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    var start: Int? = nil
    for y in 0..<b.h {
        let any = (0..<b.w).contains { b.dark($0, y) }
        if any, start == nil { start = y }
        if !any, let s = start { out.append((s, y - 1)); start = nil }
    }
    if let s = start { out.append((s, b.h - 1)) }
    return out
}

/// Alternating on/off run lengths of row y, starting with whatever the row starts with;
/// returns (startsOn, [lengths in px]).
func runs(_ b: Bitmap, row y: Int) -> (Bool, [Int]) {
    var lens: [Int] = []
    var cur = b.dark(0, y), n = 0
    let first = cur
    for x in 0..<b.w {
        let d = b.dark(x, y)
        if d == cur { n += 1 } else { lens.append(n); n = 1; cur = d }
    }
    lens.append(n)
    return (first, lens)
}

func inkBox(_ b: Bitmap) -> (Int, Int, Int, Int) {
    var x0 = b.w, y0 = b.h, x1 = -1, y1 = -1
    for y in 0..<b.h { for x in 0..<b.w where b.dark(x, y) {
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    return (x0, y0, x1, y1)
}

func fmt(_ lens: [Int], scale: Double) -> String {
    lens.map { String(format: "%.2f", Double($0) / scale) }.joined(separator: " ")
}

let patterns: [(String, Text.LineStyle.Pattern)] = [
    ("solid", .solid), ("dot", .dot), ("dash", .dash), ("dashDot", .dashDot), ("dashDotDot", .dashDotDot),
]

@MainActor
func patternArms() {
    let scale: CGFloat = 8
    for size in [13.0, 28.0] {
        for (name, p) in patterns {
            for kind in ["underline", "strikethrough"] {
                let base = Text("HHHHHHHHHHHHHHHHHHHHHHHH").font(.system(size: size)).foregroundStyle(.clear)
                let t = kind == "underline" ? base.underline(true, pattern: p, color: .black)
                                            : base.strikethrough(true, pattern: p, color: .black)
                let b = render(t, width: 400, height: 80, scale: scale)
                guard let band = bands(b).first else { print("P \(kind) \(name) size \(size): no ink"); continue }
                let mid = (band.0 + band.1) / 2
                let (startsOn, lens) = runs(b, row: mid)
                // Drop the leading blank margin and the trailing blank.
                var core = lens
                var on = startsOn
                if !on { core.removeFirst(); on = true }
                if core.count % 2 == 0 { core.removeLast() }
                let thick = Double(band.1 - band.0 + 1) / Double(scale)
                print("P \(kind) \(name) size \(size) thickness \(String(format: "%.3f", thick)) y \(Double(band.0) / Double(scale))...\(Double(band.1 + 1) / Double(scale)) runs(on,off,...) \(fmt(Array(core.prefix(13)), scale: Double(scale)))")
            }
        }
    }
}

@MainActor
func phaseArms() {
    let scale: CGFloat = 8
    // PL: a wrapped two-line text, each line underlined .dash, glyphs clear.
    let wrapped = Text("HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHH").font(.system(size: 13))
        .foregroundStyle(.clear).underline(true, pattern: .dash, color: .black)
    let b = render(wrapped.frame(width: 120, alignment: .leading), width: 140, height: 80, scale: scale)
    let bs = bands(b)
    print("PL bands \(bs.count)")
    for band in bs.prefix(4) {
        let mid = (band.0 + band.1) / 2
        let (startsOn, lens) = runs(b, row: mid)
        print("PL band y \(band.0)...\(band.1) startsOn \(startsOn) runs \(fmt(Array(lens.prefix(9)), scale: Double(scale)))")
    }
    // PR: two adjacent runs with the same pattern; and a run boundary where only colour differs.
    let two = (Text("HHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, pattern: .dash, color: .black))
        + Text("HHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, pattern: .dash, color: .black)
    let one = Text("HHHHHHHHHHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, pattern: .dash, color: .black)
    let two2 = (Text("HHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, pattern: .dash, color: .black))
        + Text("HHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, pattern: .dash, color: .red)
    for (name, view) in [("one run", AnyView(one)), ("two runs, same style", AnyView(two)), ("two runs, colour differs", AnyView(two2))] {
        let bb = render(view, width: 300, height: 40, scale: scale)
        guard let band = bands(bb).first else { print("PR \(name): no ink"); continue }
        // Red counts as dark in channel 0? Red R=255 -> not dark; use any non-white channel.
        let mid = (band.0 + band.1) / 2
        var lens: [Int] = []; var cur = false; var n = 0
        func ink(_ x: Int) -> Bool { let i = (mid * bb.w + x) * 4; return bb.data[i] < 128 || bb.data[i + 1] < 128 }
        cur = ink(0)
        for x in 0..<bb.w { let d = ink(x); if d == cur { n += 1 } else { lens.append(n); n = 1; cur = d } }
        lens.append(n)
        print("PR \(name): runs \(fmt(Array(lens.prefix(17)), scale: Double(scale)))")
    }
}

@MainActor
func thicknessArms() {
    // T: SwiftUI's underline/strikethrough thickness (solid, 8x scale) against the face's own
    // CoreText underline thickness, over sizes, to choose the unit the patterns are multiples of.
    for size in [9.0, 11.0, 13.0, 15.0, 17.0, 20.0, 24.0, 28.0, 36.0, 48.0, 72.0] {
        let t = Text("HHHH").font(.system(size: size)).foregroundStyle(.clear).underline(true, color: .black)
        let b = render(t, width: 400, height: 120, scale: 8)
        let th = bands(b).first.map { Double($0.1 - $0.0 + 1) / 8 } ?? -1
        let ct = CTFontGetUnderlineThickness(CTFontCreateWithName("SFNS" as CFString, size, nil))
        let nsf = CTFontGetUnderlineThickness(NSFont.systemFont(ofSize: size) as CTFont)
        print("T  size \(size) SwiftUI thickness \(th)  CoreText system-font underline thickness \(String(format: "%.3f", nsf)) (SFNS \(String(format: "%.3f", ct)))")
    }
}

@MainActor
func startArms() {
    let scale: CGFloat = 8
    func firstRuns(_ view: some View, _ name: String, width: CGFloat = 300, count: Int = 7) {
        let b = render(view, width: width, height: 40, scale: scale)
        guard let band = bands(b).first else { print("PS \(name): no ink"); return }
        let (startsOn, lens) = runs(b, row: (band.0 + band.1) / 2)
        // Print the blank lead-in (x of the first inked column) and the first runs.
        var lead = 0.0, rest = lens
        if !startsOn { lead = Double(lens[0]) / Double(scale); rest.removeFirst() }
        print("PS \(name): lead-in \(String(format: "%.2f", lead)) first runs \(fmt(Array(rest.prefix(count)), scale: Double(scale)))")
    }
    func h(_ n: Int = 8) -> Text { Text(String(repeating: "H", count: n)).font(.system(size: 13)).foregroundStyle(.clear) }
    let plainThenDash = h().underline(false) + h().underline(true, pattern: .dash, color: .black)
    firstRuns(plainThenDash, "plain 8H then dash 8H (lead-in = plain width)")
    let dashThenPlain = h().underline(true, pattern: .dash, color: .black) + h().underline(false)
    firstRuns(dashThenPlain, "dash 8H then plain 8H")
    firstRuns(h(6).underline(true, pattern: .dash, color: .black).frame(width: 300, alignment: .center), "centered 6H dash in 300 frame")
    firstRuns(h(6).underline(true, pattern: .dash, color: .black).frame(width: 300, alignment: .trailing), "trailing 6H dash in 300 frame")
    firstRuns(h(6).underline(true, pattern: .dash, color: .black).frame(width: 300, alignment: .trailing).environment(\.layoutDirection, .rightToLeft), "RTL 6H dash")
    // Mixed patterns across a run boundary.
    let mixed = h().underline(true, pattern: .dash, color: .black) + h().underline(true, pattern: .dot, color: .black)
    firstRuns(mixed, "dash 8H then dot 8H (all runs)", count: 40)
}

@MainActor
func extent<V: View>(_ v: V) -> String {
    let b = render(v, width: 300, height: 60, scale: 4)
    let (x0, y0, x1, y1) = inkBox(b)
    return "x \(Double(x0) / 4)...\(Double(x1 + 1) / 4) y \(Double(y0) / 4)...\(Double(y1 + 1) / 4)"
}

@MainActor
func environmentArms() {
    func t(_ s: String = "AAAA") -> Text { Text(s).font(.system(size: 20)).foregroundStyle(.black) }
    print("V  kerning 5 on Text    \(extent(t().kerning(5)))")
    print("V  kerning 5 on view    \(extent(t().kerning(5) .self.opaqueView()))")
    print("V  kerning 5 view-level \(extent(HStack { t() }.kerning(5)))")
    print("V  tracking 5 text      \(extent(t().tracking(5)))")
    print("V  tracking 5 view      \(extent(HStack { t() }.tracking(5)))")
    print("V  baselineOffset 6 text \(extent(t().baselineOffset(6)))")
    print("V  baselineOffset 6 view \(extent(HStack { t() }.baselineOffset(6)))")
    print("V  monospaced text      \(extent(t("iiWW").monospaced()))")
    print("V  monospaced view      \(extent(HStack { t("iiWW") }.monospaced()))")
    print("V  plain iiWW           \(extent(t("iiWW")))")
    print("V  bold text            \(extent(t().bold()))")
    print("V  bold view            \(extent(HStack { t() }.bold()))")
    print("V  plain                \(extent(t()))")
    print("V  underline view       \(extent(HStack { t() }.underline()))")
    print("V  underline text       \(extent(t().underline()))")
    print("V  underline dash view  \(extent(HStack { t() }.underline(true, pattern: .dash)))")
    // Precedence.
    print("W  kerning 2 text in kerning 5: \(extent(HStack { t().kerning(2) }.kerning(5)))   (text 2 alone: \(extent(t().kerning(2))), 5 alone: \(extent(t().kerning(5))))")
    print("W  kerning 5 around plain text, outer 0 inside: \(extent(HStack { HStack { t() }.kerning(0) }.kerning(5)))")
    print("W  underline(false) text in underline view: \(extent(HStack { t().underline(false) }.underline()))  (plain \(extent(t())))")
    print("W  underline(false) VIEW inside underline view: \(extent(HStack { HStack { t() }.underline(false) }.underline()))")
    let outerDash = render(HStack { Text("HHHHHHHHHHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear).underline(true, color: .black) }.underline(true, pattern: .dash, color: .red), width: 200, height: 30, scale: 8)
    let innerDash = render(HStack { Text("HHHHHHHHHHHHHHHH").font(.system(size: 13)).foregroundStyle(.clear) }.underline(true, pattern: .dash, color: .black), width: 200, height: 30, scale: 8)
    if let band = bands(innerDash).first { let (_, lens) = runs(innerDash, row: (band.0 + band.1) / 2); print("W  view-level dash, plain text: runs \(fmt(Array(lens.prefix(9)), scale: 8))") }
    if let band = bands(outerDash).first { let (_, lens) = runs(outerDash, row: (band.0 + band.1) / 2); print("W  text solid black inside view dash red: first runs \(fmt(Array(lens.prefix(5)), scale: 8))") }
    // Precedence among view-level writers.
    print("W  view kerning 2 inside view kerning 5: \(extent(HStack { HStack { t() }.kerning(2) }.kerning(5)))")
    print("W  weight: light outside bold \(extent(HStack { t() }.bold().fontWeight(.light)))  bold outside light \(extent(HStack { t() }.fontWeight(.light).bold()))  light alone \(extent(t().fontWeight(.light)))")
    print("W  light font + view bold: \(extent(HStack { Text("AAAA").font(.system(size: 20, weight: .light)).foregroundStyle(.black) }.bold()))  light font alone \(extent(Text("AAAA").font(.system(size: 20, weight: .light)).foregroundStyle(.black)))")
    print("W  headline + view bold: \(extent(HStack { Text("AAAA").font(.headline).foregroundStyle(.black) }.bold()))  headline alone \(extent(Text("AAAA").font(.headline).foregroundStyle(.black)))  headline.bold() \(extent(Text("AAAA").font(.headline.bold()).foregroundStyle(.black)))")
    print("W  text fontWeight(.light) inside view bold: \(extent(HStack { t().fontWeight(.light) }.bold()))")
    // Button label reach.
    print("B  Button under kerning 5: \(extent(Button("AAAA") {}.buttonStyle(.plain).font(.system(size: 20)).kerning(5)))   plain \(extent(Button("AAAA") {}.buttonStyle(.plain).font(.system(size: 20)))))")
}

extension View { func opaqueView() -> some View { self } }

MainActor.assumeIsolated {
    patternArms()
    phaseArms()
    thicknessArms()
    startArms()
    environmentArms()
}
