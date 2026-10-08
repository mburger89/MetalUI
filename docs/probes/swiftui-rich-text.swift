// SwiftUI probe: rich text (item 6 of the gpui-gap list) — Markdown in a
// string literal, `Text + Text` with per-segment modifiers, `Text(AttributedString)`
// with SwiftUI's attribute scope, mixed-size lines, kerning/tracking,
// baseline offset, underline/strikethrough geometry and colour, background
// colour, links, and the truncation ellipsis of a styled line.
//
// Evidence for rulings RT-A… in
// docs/superpowers/2026-10-08-rich-text-decisions.md, cited by arm id.
//
// HOW TO RUN (ruling SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-rich-text.swift -o /tmp/rich-probe && /tmp/rich-probe
//   /usr/bin/swift docs/probes/swiftui-rich-text.swift
//
// INSTRUMENTS (all headless; a locked screen measures the same):
// - RENDER: `ImageRenderer` at scale 2 on white inside a fixed top-leading
//   canvas; `differing` counts RGB mismatches. "≡ X" means 0 px against X.
// - MEASURE: a one-child `Layout` records `sizeThatFits` and the first/last
//   text baselines for a proposal, inside an `NSHostingView` (displayScale 2).
// - ROWS: the device rows (and columns) where two renders differ — how an
//   underline or strikethrough is read (`Text(s).underline()` against `Text(s)`).
// - INK: the darkest pixel's RGB inside a column range.
// - CT: CoreText's own answers for the same attributed string (`CTLine`
//   typographic bounds, a typesetter's line breaks, the font's underline
//   position/thickness), for the comparisons the rulings make.
//
// SEPARATING ARMS / POSITIVE CONTROLS: P0 (bold ≠ regular, red ≠ blue ink,
// underline ≠ none, so a 0-px match names one candidate); every identify row
// lists its nearest miss.
//
// NOTE: SwiftUI deprecates `Text + Text` in macOS 26.0 — compiling this probe
// prints 138 warnings "'+' was deprecated in macOS 26.0: Use string
// interpolation on `Text` instead: `Text("Hello \(name)")`" (evidence for
// RT-E); arm C14 shows the interpolation renders as the concatenation.
//
// RECORDED 2026-10-08 by the rich-text design session, macOS 27.0, screen
// unlocked, compiled twice (byte-identical) and interpreted once: the
// interpreted run printed every line identically except P0a's self-compare,
// "self: 12" (an interpreter-run rendering wobble of the same view; no
// identify verdict changed). Device pixels are scale 2; rows are top-down
// device rows of a 300x90-point canvas.
//
//     P0a bold vs regular: 709 px; self: 0
//     P0b red vs blue ink: 362 px
//     P0c underline vs none: 144 px
//     M1 Text("**b**") ≡ bold  [verbatim:582 bold:0]
//     M2 Text(var "**b**") ≡ verbatim  [verbatim:0 bold:582]
//     M3a Text("*i*") ≡ italic  [verbatim:258 italic:0]
//     M3b Text("_i_") ≡ italic  [verbatim:270 italic:0]
//     M4 Text("~~s~~") ≡ strike  [verbatim:428 strike:0]
//     M4b Text("~s~") ≡ strike  [verbatim:324 strike:0]
//     M5 Text("`code`") ≡ monospaced()  [verbatim:896 monospaced():0 design.monospaced:0 body.monospaced():0]
//     M6 Text("[link](https://x.org)") ≡ accentColor  [plain:421 accentColor:0 accent+underline:84 linkColor:420 linkColor+underline:504 blue:0]
//     M6c link ink rgb(0,136,255) accentColor ink rgb(0,136,255)
//     M7 Text("***bi***") ≡ bold+italic  [verbatim:841 bold+italic:0]
//     M8a Text("# H") ≡ verbatim  [verbatim:0 bold H:419]
//     M8b Text("- a") ≡ verbatim  [verbatim:0 a:285 • a:43]
//     M8c Text("1. a") ≡ verbatim  [verbatim:0 a:343]
//     M8d Text("> q") ≡ verbatim  [verbatim:0 q:344]
//     M9 Text("\\*a\\*") ≡ verbatim *a*  [verbatim *a*:0 verbatim \*a\*:614 italic a:393]
//     M10 Text("a \(v)") v="**x**" ≡ verbatim  [verbatim:0 bold x:500]
//     M10b Text("**\(name)**") name="n" ≡ bold n  [verbatim:525 bold n:0]
//     M11 Text("v \(3.5)") ≡ v 3.500000  [v 3.5:832 v 3.500000:0]
//     M11b Text("n \(7)") ≡ n 7  [n 7:0]
//     M12a Text("snake_case_name") ≡ verbatim  [verbatim:0 italic case:1559]
//     M12b Text("a*b*c") ≡ italic b  [verbatim:572 italic b:0]
//     M12c Text("2 * 3 * 4") ≡ verbatim  [verbatim:0]
//     M13 Text("a  b\nc") ≡ verbatim  [verbatim:0 a b c:503]
//     M14 Text(LocalizedStringKey(var "**b**")) ≡ bold  [verbatim:582 bold:0]
//     M15 Text("<https://x.org>") ≡ accent url  [verbatim:2224 accent url:0]
//     M15b Text("https://x.org") ≡ accent url  [verbatim:1421 accent url:0]
//     M16 Text("**a _b_**") ≡ nested  [nested:0 verbatim:889]
//     M17 Text("**unclosed") ≡ verbatim  [verbatim:0]
//     M18 Text("a&amp;b") ≡ a&b  [verbatim:747 a&b:0]
//     C1 (Text("Ab").bold() + Text("cd")) width size=33x16 first=13 last=13 | ct w=32.944 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16
//     C2 (red aaaa + bbbb).foregroundColor(.blue): left rgb(255,56,60) right rgb(0,136,255)
//     C2b (light aaaa + bbbb).bold() ≡ light+bold  [light+bold:0 bold+bold:1618]
//     C3 (20pt aaaa + bbbb).font(10pt) ≡ 20+10  [20+10:0 10+10:2157] size size=66.5x24 first=19 last=19
//     C3b (aaaa + bbbb).font(20).foregroundStyle(green) ≡ whole  [whole:0]
//     C4 foobar ct w=39.432 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16; at width 36.432: Text("foo")+Text("bar") size=35x32 first=13 last=29 vs Text("foobar") size=35x32 first=13 last=29 vs Text("foo bar") size=23.5x32 first=13 last=29
//     C4b bold/regular at that width: Text("foo").bold()+Text("bar") size=36x32 first=13 last=29
//     C4c render at width 36.432 ≡ foobar  [foobar:0]
//     C4d "word "+bold "next"+" more" at 40: size=34x48 first=13 last=45 | ct [0+5 w=33.516 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16] [5+5 w=31.865 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16] [10+4 w=30.875 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16]
//     C5 10pt a + 30pt B size=24.5x35 first=29 last=29 | 30pt B alone size=19x35 first=29 last=29 | 10pt a alone size=6x13 first=10 last=10
//     C5ct w=24.165 ascent=29.004 descent=6.328 leading=0 ceil(sum)=36 | 30 alone w=18.53 ascent=29.004 descent=6.328 leading=0 ceil(sum)=36 | 10 alone w=5.635 ascent=9.668 descent=2.109 leading=0 ceil(sum)=12
//     C6 wrap at 90: size=84.5x48 first=10 last=42
//     C6ct [0+18 w=84.082 ascent=9.668 descent=2.109 leading=0 ceil(sum)=12] [18+13 w=82.354 ascent=29.004 descent=6.328 leading=0 ceil(sum)=36]
//     C6b three 10pt lines + one 30pt word line ("x x x" 10 at 12 width) size=12x166 first=10 last=160
//     C7 Text("a")+Text("b").baselineOffset(5) size=15.5x21 first=18 last=18 | -5 size=15.5x21 first=13 last=13 | plain ab size=15.5x16 first=13 last=13
//     C7b render offset +5 vs plain: rows=11…36 cols=1…12
//     C7c wrapped 2 lines, offset on line 2's word: size=30x60 first=13 last=57 | plain size=30x48 first=13 last=45
//     C8 abc size=22.5x16 first=13 last=13 kerning(4) size=34.5x16 first=13 last=13 tracking(4) size=34.5x16 first=13 last=13
//     C8ct plain w=22.204 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16 | kern 4 w=34.204 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16 | tracking 4 w=34.204 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16
//     C8b ffi kerning(4) vs tracking(4): 0 px; widths size=24.5x16 first=13 last=13 / size=24.5x16 first=13 last=13 | ct ffi kern w=24.391 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16 tracking w=24.391 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16
//     C8c kerning in a run: Text("ab")+Text("cd").kerning(4) size=38.5x16 first=13 last=13 | ct w=38.113 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16
//     C8d abc kerning(4) render ≡ ct-kern-attributed? ≡ attr kern  [attr kern:0]
//     C9ct 13pt underlinePosition=-1.968 thickness=0.762 ascent=12.568 descent=2.742 xHeight=6.843 capHeight=9.16
//     C9 Text("xxxx").underline() diff rows=28…29 cols=0…53; plain ink cols (0, 52) baseline size=27x16 first=13 last=13
//     C9s Text("xxxx").strikethrough() diff rows=18…19 cols=0…53
//     C9w Text("x   ").underline() diff rows=28…29 cols=0…13 | Text("   x") rows=28…29 cols=21…35
//     C9g Text("gypq").underline() diff rows=28…29 cols=25…54 (descender skipping?)
//     C9ct30 30pt underlinePosition=-4.541 thickness=1.758 xHeight=15.234
//     C9m 10pt a.underline + 30pt B.underline diff rows=66…69 cols=0…193 | a-only rows=60…61 cols=0…45 | B-only rows=66…69 cols=45…195
//     C9ms same, strikethrough: a-only rows=52…53 cols=0…45 | B-only rows=40…43 cols=45…195
//     C9b Text("xx").underline() + Text("xx").underline() vs Text("xxxx").underline(): 0 px
//     C9l two lines underlined ("aaaa bbbb" at 30): rows=28…29,60…61,92…93 cols=0…57
//     C9bo baselineOffset(5) underline vs underline: rows=11…36 cols=1…78
//     C9k kerning(4) underline extent rows=28…29 cols=0…85
//     C10 underline(color:.red) diff vs no-underline rows=28…29 cols=0…53; underline vs underline(color:.red) rows=28…29 cols=0…53
//     C10b green text underline: ink in underline rows rows=28…29 cols=0…53
//     C10c underline ink: red-colour rgb(255,56,60); green text default rgb(52,199,89); strikethrough(color:.blue) rgb(0,136,255)
//     C10d underline(pattern: .dash) vs solid: 60 px
//     C11 Text(attributed) ≡ concatenation  [concatenation:0]
//     C11bg backgroundColor diff rows=0…31 cols=0…62 | plain size=32x16 first=13 last=13
//     C11bg2 backgroundColor on 30pt run beside 10pt: rows=0…70 cols=21…158
//     C11ul underlineStyle(.solid, red) ≡ underline(color:.red)  [underline(color:.red):0]
//     C11ln AttributedString.link ≡ accentColor  [plain:421 accentColor:0 accent+underline:84 linkColor:420 linkColor+underline:504 blue:0]
//     C11lnc link + foregroundColor red ≡ red  [red:0 accent:421]
//     C11lne link under .foregroundStyle(.green) ≡ accent  [green:447 accent:0]
//     C11lnt link under .tint(.green) ≡ green  [green:0 accent:447]
//     C12 Text(red+plain).font(20).foregroundStyle(blue) ≡ red+blue@20  [red+blue@20:0]
//     C12b Text(30pt run + plain).font(10) ≡ 30+10  [30+10:0]
//     C12c inlinePresentationIntent .stronglyEmphasized ≡ bold  [bold:0 plain:149]
//     C12d appKit.foregroundColor red no exact match  [red:296 plain:298]
//     C13 red aaaa + green bbbb… at 70: last ink rgb(52,199,89); first ink rgb(255,56,60)
//     C13b red aaaa…(cut inside red) + green bbbb at 70: last ink rgb(255,56,60)
//     C13c 10pt aaaa + 20pt BBB… at 70: size=62.5x24 first=19 last=19 | 20pt ellipsis? no exact match  [ok:1293]
//     C13d head truncation: first ink rgb(255,56,60)
//     C14 Text("a \(Text("b").bold())") ≡ concat  [concat:0]
//     C15 centre 2 lines mixed size=30x105 first=29 last=99
//     C16 height cap 30 on 10pt+30pt two lines size=8.5x26 first=10 last=23
//     C17 Text("")+Text("a") size=7.5x16 first=13 last=13 | Text("a") size=7.5x16 first=13 last=13 | Text("")+Text("") size=0x14 first=11 last=11 | Text("") size=0x14 first=11 last=11
//     C17b Text("").font(30)+Text("a") size=7.5x16 first=13 last=13
//     F1 ct ffi plain w=12.391 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16 | ct ffi kern 4 w=24.391 ascent=12.568 descent=2.742 leading=0 ceil(sum)=16 | glyphs plain 3 kern 3 tracking 3
//     F1b SwiftUI ffi plain size=12.5x16 first=13 last=13 kerning(4) size=24.5x16 first=13 last=13
//     F2 both strikethrough rows=40…43,52…53 cols=0…195
//     F3 underline red(10pt)+blue(30pt) diff rows=60…61,66…69 cols=0…195; ink left cols 0..40 rows 66..69 rgb(255,255,255) rows 60..61 rgb(255,56,60); right cols 60..190 rows 66..69 rgb(0,136,255)
//     F3b 13pt underline red+blue: left rgb(255,56,60) right rgb(0,136,255)
//     F4 Text("x   x").underline() diff rows=28…29 cols=0…49 | plain ink (0, 47)
//     F4b Text("x ") + Text("  x").underline() diff rows=28…29 cols=20…48
//     F4c Text("x") + Text("   ").underline() + Text("x") diff rows=28…29 cols=13…35
//     F4d wrapped "aaaa bbbb" underline at 30: line 1 rows 28-29 cols rows=28…29 cols=0…49
//     F4e Text("x   ").background(yellow attr) rows=0…31 cols=0…34
//     M19 Text("![alt](https://x.org/i.png)") ≡ alt  [alt:0 verbatim:2866 empty:283 accent alt:312]
//     M20 Text("www.x.org") ≡ accent  [verbatim:1126 accent:0]
//     M21 Text("a@b.org") ≡ accent  [verbatim:1030 accent:0]
//     M22 Text("[**b**](https://x.org)") ≡ accent  [bold accent:136 accent:0]
//     M23 Text("&#65;&copy;") ≡ A©  [A©:0 verbatim:1704]
//     M24 Text("a\\nb") (backslash-newline) ≡ a\nb  [a\nb verbatim:91 a\nb:0]
//     M25 Text("`**x**`") ≡ mono **x**  [mono **x**:0 mono bold x:699]
//     M26 Text("http://x.org/a_b_c") ≡ accent url  [accent url:0 verbatim:1982]
//     M27 Text("__b__") ≡ bold  [bold:0 verbatim:602]
//     M28 Text("[a](relative/path)") ≡ accent  [accent:0 plain a:145]
//     M29 Text("Count: \(n)") with n=42 renders ≡ Count: 42  [Count: 42:0]
//     M32 Text("<b>x</b>") ≡ verbatim  [verbatim:0 bold x:961]
//     M33 Text("a  \nb") ≡ verbatim  [verbatim:0]
//     M34 Text("&nbsp;x") ≡ nbsp x  [nbsp x:0 space x:0]
//     C7d Text("b").baselineOffset(5) alone size=8x21 first=18 last=18 | -5 size=8x21 first=13 last=13 | plain b size=8x16 first=13 last=13
//     C18 reservesSpace 3 on 10pt+30pt one line size=24.5x36 first=29 last=29 | 30pt B reservesSpace 3 size=19x105 first=29 last=29 | 10pt a reservesSpace 3 size=6x36 first=10 last=10 | 30pt B + 10pt a size=24.5x105 first=29 last=29
//     C19 lineLimit(1) on 10pt line + 30pt second line, wrap 40: size=38x35 first=29 last=29
//     M30 Button("**b**") {} ≡ Text(bold) label  [Text(bold) label:0 verbatim label:2808]
//     M31 Toggle("**b**") ≡ bold label  [bold label:0 verbatim label:582]

import AppKit
import CoreText
import SwiftUI

// MARK: - instruments

nonisolated(unsafe) var log: [String: String] = [:]

struct Measure: Layout {
    let key: String
    let proposal: ProposedViewSize
    func sizeThatFits(proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let s = subviews[0].sizeThatFits(proposal)
        let d = subviews[0].dimensions(in: proposal)
        log[key] = "size=\(fmt(s.width))x\(fmt(s.height)) first=\(fmt(d[.firstTextBaseline])) last=\(fmt(d[.lastTextBaseline]))"
        return s
    }
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

@MainActor
func measure(_ view: some View, _ proposal: ProposedViewSize = .unspecified) -> String {
    let key = UUID().uuidString
    let host = NSHostingView(rootView: Measure(key: key, proposal: proposal) { view }
        .environment(\.displayScale, 2))
    _ = host.fittingSize
    return log[key] ?? "not measured"
}

typealias Bitmap = (bytes: [UInt8], w: Int, h: Int)

@MainActor
func bitmap(_ view: some View) -> Bitmap {
    let r = ImageRenderer(content: view.background(Color.white))
    r.scale = 2
    guard let cg = r.cgImage else { return ([], 0, 0) }
    let w = cg.width, h = cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (bytes, w, h)
}

func differing(_ a: Bitmap, _ b: Bitmap) -> Int {
    guard a.w == b.w, a.h == b.h else { return Int.max }
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

/// Rows (device px, top-down) and columns where `a` and `b` differ.
func diffBox(_ a: Bitmap, _ b: Bitmap) -> String {
    guard a.w == b.w, a.h == b.h else { return "size mismatch" }
    var rows = Set<Int>(), minX = Int.max, maxX = -1
    for y in 0..<a.h { for x in 0..<a.w {
        let i = (y * a.w + x) * 4
        if a.bytes[i] != b.bytes[i] || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] {
            rows.insert(y); minX = min(minX, x); maxX = max(maxX, x)
        }
    } }
    guard !rows.isEmpty else { return "no difference" }
    return "rows=\(ranges(rows.sorted())) cols=\(minX)…\(maxX)"
}

func ranges(_ v: [Int]) -> String {
    var out: [String] = [], start = v[0], prev = v[0]
    for x in v.dropFirst() { if x == prev + 1 { prev = x; continue }; out.append(start == prev ? "\(start)" : "\(start)…\(prev)"); start = x; prev = x }
    out.append(start == prev ? "\(start)" : "\(start)…\(prev)")
    return out.joined(separator: ",")
}

/// The darkest pixel's RGB inside columns `cols` (rows `rows`, default all).
func ink(_ b: Bitmap, cols: Range<Int>, rows: Range<Int>? = nil) -> String {
    var best = (sum: 766, r: 0, g: 0, bl: 0)
    for y in (rows ?? 0..<b.h) where y < b.h { for x in cols where x < b.w {
        let i = (y * b.w + x) * 4
        let s = Int(b.bytes[i]) + Int(b.bytes[i + 1]) + Int(b.bytes[i + 2])
        if s < best.sum { best = (s, Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2])) }
    } }
    return best.sum == 766 ? "white" : "rgb(\(best.r),\(best.g),\(best.bl))"
}

/// The first and last non-white column.
func inkColumns(_ b: Bitmap) -> (Int, Int) {
    var minX = Int.max, maxX = -1
    for y in 0..<b.h { for x in 0..<b.w where b.bytes[(y * b.w + x) * 4] < 250 || b.bytes[(y * b.w + x) * 4 + 1] < 250 || b.bytes[(y * b.w + x) * 4 + 2] < 250 {
        minX = min(minX, x); maxX = max(maxX, x)
    } }
    return (minX, maxX)
}

@MainActor
func canvas(_ view: some View, width: CGFloat = 300, height: CGFloat = 90) -> some View {
    view.frame(width: width, height: height, alignment: .topLeading)
}

@MainActor
func identify(_ target: some View, _ candidates: [(String, AnyView)], width: CGFloat = 300,
              height: CGFloat = 90) -> String {
    let t = bitmap(canvas(target, width: width, height: height))
    var results: [String] = []
    var match: String?
    for (name, view) in candidates {
        let n = differing(t, bitmap(canvas(view, width: width, height: height)))
        if n == 0 && match == nil { match = name }
        results.append("\(name):\(n)")
    }
    return (match.map { "≡ \($0)" } ?? "no exact match") + "  [" + results.joined(separator: " ") + "]"
}

func ctFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> CTFont {
    NSFont.systemFont(ofSize: size, weight: weight) as CTFont
}

func ctLine(_ parts: [(String, [NSAttributedString.Key: Any])]) -> CTLine {
    let s = NSMutableAttributedString()
    for (t, a) in parts { s.append(NSAttributedString(string: t, attributes: a)) }
    return CTLineCreateWithAttributedString(s)
}

func ctBounds(_ line: CTLine) -> String {
    var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
    let w = CTLineGetTypographicBounds(line, &a, &d, &l)
    return "w=\(fmt(w)) ascent=\(fmt(a)) descent=\(fmt(d)) leading=\(fmt(l)) ceil(sum)=\(fmt((a + d + l).rounded(.up)))"
}

/// CoreText's line breaks of `parts` at `width`: each line's typographic bounds.
func ctLines(_ parts: [(String, [NSAttributedString.Key: Any])], width: Double) -> String {
    let s = NSMutableAttributedString()
    for (t, a) in parts { s.append(NSAttributedString(string: t, attributes: a)) }
    let ts = CTTypesetterCreateWithAttributedString(s)
    var start = 0, out: [String] = []
    while start < s.length {
        let n = CTTypesetterSuggestLineBreak(ts, start, width)
        let line = CTTypesetterCreateLine(ts, CFRange(location: start, length: n))
        out.append("[\(start)+\(n) \(ctBounds(line))]")
        start += n
    }
    return out.joined(separator: " ")
}

func sys(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> [NSAttributedString.Key: Any] {
    [.font: ctFont(size, weight: weight)]
}

// MARK: - arms

@MainActor
func run() {
    func out(_ id: String, _ s: String) { print("\(id) \(s)") }
    let body = Font.system(size: 13)

    // P0 — positive controls.
    let plainB = bitmap(canvas(Text("bold").font(body)))
    out("P0a", "bold vs regular: \(differing(plainB, bitmap(canvas(Text("bold").font(body).bold())))) px; self: \(differing(plainB, bitmap(canvas(Text("bold").font(body)))))")
    out("P0b", "red vs blue ink: \(differing(bitmap(canvas(Text("ink").foregroundColor(.red))), bitmap(canvas(Text("ink").foregroundColor(.blue))))) px")
    out("P0c", "underline vs none: \(differing(bitmap(canvas(Text("under").underline())), bitmap(canvas(Text("under"))))) px")

    // M — Markdown in a literal.
    out("M1", "Text(\"**b**\") " + identify(Text("**b**"), [("verbatim", AnyView(Text(verbatim: "**b**"))), ("bold", AnyView(Text("b").bold()))]))
    let bVar = "**b**"
    out("M2", "Text(var \"**b**\") " + identify(Text(bVar), [("verbatim", AnyView(Text(verbatim: "**b**"))), ("bold", AnyView(Text("b").bold()))]))
    out("M3a", "Text(\"*i*\") " + identify(Text("*i*"), [("verbatim", AnyView(Text(verbatim: "*i*"))), ("italic", AnyView(Text("i").italic()))]))
    out("M3b", "Text(\"_i_\") " + identify(Text("_i_"), [("verbatim", AnyView(Text(verbatim: "_i_"))), ("italic", AnyView(Text("i").italic()))]))
    out("M4", "Text(\"~~s~~\") " + identify(Text("~~s~~"), [("verbatim", AnyView(Text(verbatim: "~~s~~"))), ("strike", AnyView(Text("s").strikethrough()))]))
    out("M4b", "Text(\"~s~\") " + identify(Text("~s~"), [("verbatim", AnyView(Text(verbatim: "~s~"))), ("strike", AnyView(Text("s").strikethrough()))]))
    out("M5", "Text(\"`code`\") " + identify(Text("`code`"), [
        ("verbatim", AnyView(Text(verbatim: "`code`"))),
        ("monospaced()", AnyView(Text("code").monospaced())),
        ("design.monospaced", AnyView(Text("code").font(.system(size: 13, design: .monospaced)))),
        ("body.monospaced()", AnyView(Text("code").font(.body.monospaced()))),
    ]))
    let linkCandidates: [(String, AnyView)] = [
        ("plain", AnyView(Text(verbatim: "link"))),
        ("accentColor", AnyView(Text(verbatim: "link").foregroundColor(.accentColor))),
        ("accent+underline", AnyView(Text(verbatim: "link").foregroundColor(.accentColor).underline())),
        ("linkColor", AnyView(Text(verbatim: "link").foregroundColor(Color(nsColor: .linkColor)))),
        ("linkColor+underline", AnyView(Text(verbatim: "link").foregroundColor(Color(nsColor: .linkColor)).underline())),
        ("blue", AnyView(Text(verbatim: "link").foregroundColor(.blue))),
    ]
    out("M6", "Text(\"[link](https://x.org)\") " + identify(Text("[link](https://x.org)"), linkCandidates))
    out("M6c", "link ink " + ink(bitmap(canvas(Text("[link](https://x.org)"))), cols: 0..<80) + " accentColor ink " + ink(bitmap(canvas(Text("link").foregroundColor(.accentColor))), cols: 0..<80))
    out("M7", "Text(\"***bi***\") " + identify(Text("***bi***"), [("verbatim", AnyView(Text(verbatim: "***bi***"))), ("bold+italic", AnyView(Text("bi").bold().italic()))]))
    out("M8a", "Text(\"# H\") " + identify(Text("# H"), [("verbatim", AnyView(Text(verbatim: "# H"))), ("bold H", AnyView(Text("H").bold()))]))
    out("M8b", "Text(\"- a\") " + identify(Text("- a"), [("verbatim", AnyView(Text(verbatim: "- a"))), ("a", AnyView(Text(verbatim: "a"))), ("• a", AnyView(Text(verbatim: "• a")))]))
    out("M8c", "Text(\"1. a\") " + identify(Text("1. a"), [("verbatim", AnyView(Text(verbatim: "1. a"))), ("a", AnyView(Text(verbatim: "a")))]))
    out("M8d", "Text(\"> q\") " + identify(Text("> q"), [("verbatim", AnyView(Text(verbatim: "> q"))), ("q", AnyView(Text(verbatim: "q")))]))
    out("M9", "Text(\"\\\\*a\\\\*\") " + identify(Text("\\*a\\*"), [("verbatim *a*", AnyView(Text(verbatim: "*a*"))), ("verbatim \\*a\\*", AnyView(Text(verbatim: "\\*a\\*"))), ("italic a", AnyView(Text("a").italic()))]))
    let v = "**x**"
    out("M10", "Text(\"a \\(v)\") v=\"**x**\" " + identify(Text("a \(v)"), [("verbatim", AnyView(Text(verbatim: "a **x**"))), ("bold x", AnyView(Text(verbatim: "a ") + Text(verbatim: "x").bold()))]))
    out("M10b", "Text(\"**\\(name)**\") name=\"n\" " + identify(Text("**\("n")**"), [("verbatim", AnyView(Text(verbatim: "**n**"))), ("bold n", AnyView(Text(verbatim: "n").bold()))]))
    out("M11", "Text(\"v \\(3.5)\") " + identify(Text("v \(3.5)"), [("v 3.5", AnyView(Text(verbatim: "v 3.5"))), ("v 3.500000", AnyView(Text(verbatim: "v 3.500000")))]))
    out("M11b", "Text(\"n \\(7)\") " + identify(Text("n \(7)"), [("n 7", AnyView(Text(verbatim: "n 7")))]))
    out("M12a", "Text(\"snake_case_name\") " + identify(Text("snake_case_name"), [("verbatim", AnyView(Text(verbatim: "snake_case_name"))), ("italic case", AnyView(Text(verbatim: "snake") + Text(verbatim: "case").italic() + Text(verbatim: "name")))]))
    out("M12b", "Text(\"a*b*c\") " + identify(Text("a*b*c"), [("verbatim", AnyView(Text(verbatim: "a*b*c"))), ("italic b", AnyView(Text(verbatim: "a") + Text(verbatim: "b").italic() + Text(verbatim: "c")))]))
    out("M12c", "Text(\"2 * 3 * 4\") " + identify(Text("2 * 3 * 4"), [("verbatim", AnyView(Text(verbatim: "2 * 3 * 4")))]))
    out("M13", "Text(\"a  b\\nc\") " + identify(Text("a  b\nc"), [("verbatim", AnyView(Text(verbatim: "a  b\nc"))), ("a b c", AnyView(Text(verbatim: "a b c")))]))
    out("M14", "Text(LocalizedStringKey(var \"**b**\")) " + identify(Text(LocalizedStringKey(bVar)), [("verbatim", AnyView(Text(verbatim: "**b**"))), ("bold", AnyView(Text("b").bold()))]))
    out("M15", "Text(\"<https://x.org>\") " + identify(Text("<https://x.org>"), [("verbatim", AnyView(Text(verbatim: "<https://x.org>"))), ("accent url", AnyView(Text(verbatim: "https://x.org").foregroundColor(.accentColor)))]))
    out("M15b", "Text(\"https://x.org\") " + identify(Text("https://x.org"), [("verbatim", AnyView(Text(verbatim: "https://x.org"))), ("accent url", AnyView(Text(verbatim: "https://x.org").foregroundColor(.accentColor)))]))
    out("M16", "Text(\"**a _b_**\") " + identify(Text("**a _b_**"), [("nested", AnyView(Text(verbatim: "a ").bold() + Text(verbatim: "b").bold().italic())), ("verbatim", AnyView(Text(verbatim: "**a _b_**")))]))
    out("M17", "Text(\"**unclosed\") " + identify(Text("**unclosed"), [("verbatim", AnyView(Text(verbatim: "**unclosed")))]))
    out("M18", "Text(\"a&amp;b\") " + identify(Text("a&amp;b"), [("verbatim", AnyView(Text(verbatim: "a&amp;b"))), ("a&b", AnyView(Text(verbatim: "a&b")))]))

    // C — concatenation.
    out("C1", "(Text(\"Ab\").bold() + Text(\"cd\")) width " + measure(Text("Ab").bold() + Text("cd")) + " | ct " + ctBounds(ctLine([("Ab", sys(13, .bold)), ("cd", sys(13))])))
    do {
        let c = (Text("aaaa").foregroundColor(.red) + Text("bbbb")).foregroundColor(.blue)
        let b = bitmap(canvas(c)), (lo, hi) = inkColumns(b), mid = (lo + hi) / 2
        out("C2", "(red aaaa + bbbb).foregroundColor(.blue): left \(ink(b, cols: lo..<mid - 4)) right \(ink(b, cols: mid + 4..<hi + 1))")
        let c2 = (Text("aaaa").fontWeight(.light) + Text("bbbb")).bold()
        out("C2b", "(light aaaa + bbbb).bold() " + identify(c2, [
            ("light+bold", AnyView(Text("aaaa").fontWeight(.light) + Text("bbbb").bold())),
            ("bold+bold", AnyView(Text("aaaa").bold() + Text("bbbb").bold())),
        ]))
        let c3 = (Text("aaaa").font(.system(size: 20)) + Text("bbbb")).font(.system(size: 10))
        out("C3", "(20pt aaaa + bbbb).font(10pt) " + identify(c3, [
            ("20+10", AnyView(Text("aaaa").font(.system(size: 20)) + Text("bbbb").font(.system(size: 10)))),
            ("10+10", AnyView(Text("aaaabbbb").font(.system(size: 10)))),
        ]) + " size " + measure(c3))
        let c3b = (Text("aaaa") + Text("bbbb")).font(.system(size: 20)).foregroundStyle(.green)
        out("C3b", "(aaaa + bbbb).font(20).foregroundStyle(green) " + identify(c3b, [("whole", AnyView(Text("aaaabbbb").font(.system(size: 20)).foregroundStyle(.green)))]))
    }
    // C4 — line breaking across a run boundary.
    do {
        let w = ctBounds(ctLine([("foobar", sys(13))]))
        let full = CTLineGetTypographicBounds(ctLine([("foobar", sys(13))]), nil, nil, nil)
        let p = ProposedViewSize(width: full - 3, height: nil)
        out("C4", "foobar ct \(w); at width \(fmt(full - 3)): Text(\"foo\")+Text(\"bar\") " + measure(Text("foo") + Text("bar"), p) + " vs Text(\"foobar\") " + measure(Text("foobar"), p) + " vs Text(\"foo bar\") " + measure(Text("foo bar"), p))
        out("C4b", "bold/regular at that width: Text(\"foo\").bold()+Text(\"bar\") " + measure(Text("foo").bold() + Text("bar"), p))
        let img = identify(Text("foo") + Text("bar"), [("foobar", AnyView(Text("foobar")))], width: full - 3)
        out("C4c", "render at width \(fmt(full - 3)) " + img)
        let wrapped = measure(Text("word ") + Text("next").bold() + Text(" more"), ProposedViewSize(width: 40, height: nil))
        out("C4d", "\"word \"+bold \"next\"+\" more\" at 40: \(wrapped) | ct " + ctLines([("word ", sys(13)), ("next", sys(13, .bold)), (" more", sys(13))], width: 40))
    }
    // C5/C6 — mixed sizes.
    do {
        let mixed = Text("a").font(.system(size: 10)) + Text("B").font(.system(size: 30))
        out("C5", "10pt a + 30pt B " + measure(mixed) + " | 30pt B alone " + measure(Text("B").font(.system(size: 30))) + " | 10pt a alone " + measure(Text("a").font(.system(size: 10))))
        out("C5ct", ctBounds(ctLine([("a", sys(10)), ("B", sys(30))])) + " | 30 alone " + ctBounds(ctLine([("B", sys(30))])) + " | 10 alone " + ctBounds(ctLine([("a", sys(10))])))
        let wrap = Text("small small small ").font(.system(size: 10)) + Text("BIG").font(.system(size: 30)) + Text(" tail tail").font(.system(size: 10))
        let pw = ProposedViewSize(width: 90, height: nil)
        out("C6", "wrap at 90: " + measure(wrap, pw))
        out("C6ct", ctLines([("small small small ", sys(10)), ("BIG", sys(30)), (" tail tail", sys(10))], width: 90))
        out("C6b", "three 10pt lines + one 30pt word line (\"x x x\" 10 at 12 width) " + measure(Text("x x x").font(.system(size: 10)) + Text(" BIG").font(.system(size: 30)), ProposedViewSize(width: 12, height: nil)))
    }
    // C7 — baseline offset.
    out("C7", "Text(\"a\")+Text(\"b\").baselineOffset(5) " + measure(Text("a") + Text("b").baselineOffset(5)) + " | -5 " + measure(Text("a") + Text("b").baselineOffset(-5)) + " | plain ab " + measure(Text("ab")))
    out("C7b", "render offset +5 vs plain: " + diffBox(bitmap(canvas(Text("a") + Text("b").baselineOffset(5))), bitmap(canvas(Text("a") + Text("b")))))
    out("C7c", "wrapped 2 lines, offset on line 2's word: " + measure(Text("aaaa ") + Text("bbbb").baselineOffset(6), ProposedViewSize(width: 30, height: nil)) + " | plain " + measure(Text("aaaa bbbb"), ProposedViewSize(width: 30, height: nil)))
    // C8 — kerning, tracking.
    do {
        let plain = measure(Text("abc")), k = measure(Text("abc").kerning(4)), t = measure(Text("abc").tracking(4))
        out("C8", "abc \(plain) kerning(4) \(k) tracking(4) \(t)")
        let f = ctFont(13)
        out("C8ct", "plain " + ctBounds(ctLine([("abc", [.font: f])])) + " | kern 4 " + ctBounds(ctLine([("abc", [.font: f, .kern: 4])])) + " | tracking 4 " + ctBounds(ctLine([("abc", [.font: f, .tracking: 4])])))
        out("C8b", "ffi kerning(4) vs tracking(4): \(differing(bitmap(canvas(Text("ffi").kerning(4))), bitmap(canvas(Text("ffi").tracking(4))))) px; widths " + measure(Text("ffi").kerning(4)) + " / " + measure(Text("ffi").tracking(4)) + " | ct ffi kern " + ctBounds(ctLine([("ffi", [.font: f, .kern: 4])])) + " tracking " + ctBounds(ctLine([("ffi", [.font: f, .tracking: 4])])))
        out("C8c", "kerning in a run: Text(\"ab\")+Text(\"cd\").kerning(4) " + measure(Text("ab") + Text("cd").kerning(4)) + " | ct " + ctBounds(ctLine([("ab", [.font: f]), ("cd", [.font: f, .kern: 4])])))
        out("C8d", "abc kerning(4) render ≡ ct-kern-attributed? " + identify(Text("abc").kerning(4), [("attr kern", AnyView(Text({ var a = AttributedString("abc"); a.kern = 4; return a }())))]))
    }
    // C9 — underline/strikethrough geometry.
    do {
        let f = ctFont(13)
        out("C9ct", "13pt underlinePosition=\(fmt(CTFontGetUnderlinePosition(f))) thickness=\(fmt(CTFontGetUnderlineThickness(f))) ascent=\(fmt(CTFontGetAscent(f))) descent=\(fmt(CTFontGetDescent(f))) xHeight=\(fmt(CTFontGetXHeight(f))) capHeight=\(fmt(CTFontGetCapHeight(f)))")
        out("C9", "Text(\"xxxx\").underline() diff " + diffBox(bitmap(canvas(Text("xxxx").underline())), bitmap(canvas(Text("xxxx")))) + "; plain ink cols \(inkColumns(bitmap(canvas(Text("xxxx"))))) baseline " + measure(Text("xxxx")))
        out("C9s", "Text(\"xxxx\").strikethrough() diff " + diffBox(bitmap(canvas(Text("xxxx").strikethrough())), bitmap(canvas(Text("xxxx")))))
        out("C9w", "Text(\"x   \").underline() diff " + diffBox(bitmap(canvas(Text("x   ").underline())), bitmap(canvas(Text("x   ")))) + " | Text(\"   x\") " + diffBox(bitmap(canvas(Text("   x").underline())), bitmap(canvas(Text("   x")))))
        out("C9g", "Text(\"gypq\").underline() diff " + diffBox(bitmap(canvas(Text("gypq").underline())), bitmap(canvas(Text("gypq")))) + " (descender skipping?)")
        let f30 = ctFont(30)
        out("C9ct30", "30pt underlinePosition=\(fmt(CTFontGetUnderlinePosition(f30))) thickness=\(fmt(CTFontGetUnderlineThickness(f30))) xHeight=\(fmt(CTFontGetXHeight(f30)))")
        out("C9m", "10pt a.underline + 30pt B.underline diff " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)).underline() + Text("BBBB").font(.system(size: 30)).underline())), bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))))) + " | a-only " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)).underline() + Text("BBBB").font(.system(size: 30)))), bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))))) + " | B-only " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30)).underline())), bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))))))
        out("C9ms", "same, strikethrough: a-only " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)).strikethrough() + Text("BBBB").font(.system(size: 30)))), bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))))) + " | B-only " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30)).strikethrough())), bitmap(canvas(Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))))))
        out("C9b", "Text(\"xx\").underline() + Text(\"xx\").underline() vs Text(\"xxxx\").underline(): \(differing(bitmap(canvas(Text("xx").underline() + Text("xx").underline())), bitmap(canvas(Text("xxxx").underline())))) px")
        out("C9l", "two lines underlined (\"aaaa bbbb\" at 30): " + diffBox(bitmap(canvas(Text("aaaa bbbb").underline().frame(width: 30, alignment: .leading))), bitmap(canvas(Text("aaaa bbbb").frame(width: 30, alignment: .leading)))))
        out("C9bo", "baselineOffset(5) underline vs underline: " + diffBox(bitmap(canvas(Text("a") + Text("bbbb").baselineOffset(5).underline())), bitmap(canvas(Text("a") + Text("bbbb").underline()))))
        out("C9k", "kerning(4) underline extent " + diffBox(bitmap(canvas(Text("xxxx").kerning(4).underline())), bitmap(canvas(Text("xxxx").kerning(4)))))
    }
    // C10 — underline colour.
    do {
        let u = bitmap(canvas(Text("xxxx").underline(color: .red)))
        let rows = 0..<u.h
        _ = rows
        out("C10", "underline(color:.red) diff vs no-underline " + diffBox(u, bitmap(canvas(Text("xxxx")))) + "; underline vs underline(color:.red) " + diffBox(u, bitmap(canvas(Text("xxxx").underline()))))
        out("C10b", "green text underline: ink in underline rows " + { () -> String in
            let g = bitmap(canvas(Text("xxxx").foregroundColor(.green).underline()))
            let n = bitmap(canvas(Text("xxxx").foregroundColor(.green)))
            return diffBox(g, n)
        }())
        // Read the underline's colour from rows that only the underline paints.
        func underlineInk(_ view: some View, _ base: some View) -> String {
            let a = bitmap(canvas(view)), b = bitmap(canvas(base))
            var rows = Set<Int>()
            for y in 0..<a.h { for x in 0..<a.w { let i = (y * a.w + x) * 4; if a.bytes[i] != b.bytes[i] || a.bytes[i+1] != b.bytes[i+1] || a.bytes[i+2] != b.bytes[i+2] { rows.insert(y) } } }
            guard let lo = rows.min(), let hi = rows.max() else { return "none" }
            return ink(a, cols: 0..<a.w, rows: lo..<hi + 1)
        }
        out("C10c", "underline ink: red-colour \(underlineInk(Text("xxxx").underline(color: .red), Text("xxxx"))); green text default \(underlineInk(Text("xxxx").foregroundColor(.green).underline(), Text("xxxx").foregroundColor(.green))); strikethrough(color:.blue) \(underlineInk(Text("xxxx").strikethrough(color: .blue), Text("xxxx")))")
        out("C10d", "underline(pattern: .dash) vs solid: \(differing(bitmap(canvas(Text("xxxxxxxx").underline(pattern: .dash))), bitmap(canvas(Text("xxxxxxxx").underline())))) px")
    }
    // C11 — AttributedString with SwiftUI's scope ≡ the concatenation.
    do {
        var a = AttributedString("Ab")
        a.font = .system(size: 13, weight: .bold)
        var b = AttributedString("cd")
        b.foregroundColor = .red
        var c = AttributedString("ef")
        c.underlineStyle = .single
        var d = AttributedString("gh")
        d.strikethroughStyle = .single
        var e = AttributedString("ij")
        e.kern = 3
        var f = AttributedString("kl")
        f.tracking = 3
        var g = AttributedString("mn")
        g.baselineOffset = 4
        let attr = a + b + c + d + e + f + g
        let concat = Text("Ab").font(.system(size: 13, weight: .bold)) + Text("cd").foregroundColor(.red)
            + Text("ef").underline() + Text("gh").strikethrough() + Text("ij").kerning(3) + Text("kl").tracking(3)
            + Text("mn").baselineOffset(4)
        out("C11", "Text(attributed) " + identify(Text(attr), [("concatenation", AnyView(concat))]))
        var bg = AttributedString("bgbg")
        bg.backgroundColor = .yellow
        let bgB = bitmap(canvas(Text(bg))), plainBg = bitmap(canvas(Text("bgbg")))
        out("C11bg", "backgroundColor diff " + diffBox(bgB, plainBg) + " | plain " + measure(Text("bgbg")))
        var bg2 = AttributedString("bgbg")
        bg2.backgroundColor = .yellow
        out("C11bg2", "backgroundColor on 30pt run beside 10pt: " + diffBox(bitmap(canvas(Text("aa").font(.system(size: 10)) + Text(bg2).font(.system(size: 30)))), bitmap(canvas(Text("aa").font(.system(size: 10)) + Text("bgbg").font(.system(size: 30))))))
        var ul = AttributedString("xxxx")
        ul.underlineStyle = Text.LineStyle(pattern: .solid, color: .red)
        out("C11ul", "underlineStyle(.solid, red) " + identify(Text(ul), [("underline(color:.red)", AnyView(Text("xxxx").underline(color: .red)))]))
        var ln = AttributedString("link")
        ln.link = URL(string: "https://x.org")
        out("C11ln", "AttributedString.link " + identify(Text(ln), linkCandidates))
        var lnc = AttributedString("link")
        lnc.link = URL(string: "https://x.org")
        lnc.foregroundColor = .red
        out("C11lnc", "link + foregroundColor red " + identify(Text(lnc), [("red", AnyView(Text(verbatim: "link").foregroundColor(.red))), ("accent", AnyView(Text(verbatim: "link").foregroundColor(.accentColor)))]))
        out("C11lne", "link under .foregroundStyle(.green) " + identify(Text(ln).foregroundStyle(.green), [("green", AnyView(Text(verbatim: "link").foregroundColor(.green))), ("accent", AnyView(Text(verbatim: "link").foregroundColor(.accentColor)))]))
        out("C11lnt", "link under .tint(.green) " + identify(Text(ln).tint(.green), [("green", AnyView(Text(verbatim: "link").foregroundColor(.green))), ("accent", AnyView(Text(verbatim: "link").foregroundColor(.accentColor)))]))
    }
    // C12 — inheritance into an attributed run.
    do {
        var r = AttributedString("red")
        r.foregroundColor = .red
        let x = AttributedString(" plain")
        out("C12", "Text(red+plain).font(20).foregroundStyle(blue) " + identify(Text(r + x).font(.system(size: 20)).foregroundStyle(.blue), [("red+blue@20", AnyView(Text("red").foregroundColor(.red).font(.system(size: 20)) + Text(" plain").foregroundColor(.blue).font(.system(size: 20))))]))
        var big = AttributedString("BIG")
        big.font = .system(size: 30)
        out("C12b", "Text(30pt run + plain).font(10) " + identify(Text(big + x).font(.system(size: 10)), [("30+10", AnyView(Text("BIG").font(.system(size: 30)) + Text(" plain").font(.system(size: 10))))]))
        var bold = AttributedString("b")
        bold.inlinePresentationIntent = .stronglyEmphasized
        out("C12c", "inlinePresentationIntent .stronglyEmphasized " + identify(Text(bold), [("bold", AnyView(Text("b").bold())), ("plain", AnyView(Text("b")))]))
        var appkit = AttributedString("ak")
        appkit.appKit.foregroundColor = .red
        out("C12d", "appKit.foregroundColor red " + identify(Text(appkit), [("red", AnyView(Text("ak").foregroundColor(.red))), ("plain", AnyView(Text("ak")))]))
    }
    // C13 — the ellipsis of a styled truncated line.
    do {
        let t = (Text("aaaa").foregroundColor(.red) + Text("bbbbbbbbbbbbbbbb").foregroundColor(.green)).lineLimit(1)
        let b = bitmap(canvas(t.frame(width: 70, alignment: .leading), width: 80, height: 30))
        let (_, hi) = inkColumns(b)
        out("C13", "red aaaa + green bbbb… at 70: last ink \(ink(b, cols: hi - 8..<hi + 1)); first ink \(ink(b, cols: 0..<10))")
        let t2 = (Text("aaaaaaaaaaaaaaaa").foregroundColor(.red) + Text("bbbb").foregroundColor(.green)).lineLimit(1)
        let b2 = bitmap(canvas(t2.frame(width: 70, alignment: .leading), width: 80, height: 30))
        let (_, hi2) = inkColumns(b2)
        out("C13b", "red aaaa…(cut inside red) + green bbbb at 70: last ink \(ink(b2, cols: hi2 - 8..<hi2 + 1))")
        let t3 = (Text("aaaa").font(.system(size: 10)) + Text("BBBBBBBBBBBBB").font(.system(size: 20))).lineLimit(1)
        out("C13c", "10pt aaaa + 20pt BBB… at 70: " + measure(t3, ProposedViewSize(width: 70, height: nil)) + " | 20pt ellipsis? " + identify(t3.frame(width: 70, alignment: .leading), [("ok", AnyView(Text("")))], width: 80, height: 40))
        let t4 = (Text("aaaa").foregroundColor(.red) + Text("bbbbbbbbbbbbbbbb").foregroundColor(.green)).lineLimit(1).truncationMode(.head)
        let b4 = bitmap(canvas(t4.frame(width: 70, alignment: .leading), width: 80, height: 30))
        let (lo4, _) = inkColumns(b4)
        out("C13d", "head truncation: first ink \(ink(b4, cols: lo4..<lo4 + 8))")
    }
    // C14 — interpolating a Text inside a Text literal.
    out("C14", "Text(\"a \\(Text(\"b\").bold())\") " + identify(Text("a \(Text("b").bold())"), [("concat", AnyView(Text("a ") + Text("b").bold()))]))
    // C15 — multiline alignment with mixed sizes, centre.
    out("C15", "centre 2 lines mixed " + measure((Text("aa aa").font(.system(size: 10)) + Text(" BB").font(.system(size: 30))).multilineTextAlignment(.center), ProposedViewSize(width: 30, height: nil)))
    // C16 — a line limit by height with mixed lines.
    out("C16", "height cap 30 on 10pt+30pt two lines " + measure(Text("x x x").font(.system(size: 10)) + Text(" BIG").font(.system(size: 30)), ProposedViewSize(width: 12, height: 30)))
    // C17 — empty segments.
    out("C17", "Text(\"\")+Text(\"a\") " + measure(Text("") + Text("a")) + " | Text(\"a\") " + measure(Text("a")) + " | Text(\"\")+Text(\"\") " + measure(Text("") + Text("")) + " | Text(\"\") " + measure(Text("")))
    out("C17b", "Text(\"\").font(30)+Text(\"a\") " + measure(Text("").font(.system(size: 30)) + Text("a")))
}


// MARK: - follow-up arms (the second pass, after reading the first)

@MainActor
func followUp() {
    func out(_ id: String, _ s: String) { print("\(id) \(s)") }
    let f = ctFont(13)
    out("F1", "ct ffi plain " + ctBounds(ctLine([("ffi", [.font: f])])) + " | ct ffi kern 4 " + ctBounds(ctLine([("ffi", [.font: f, .kern: 4])])) + " | glyphs plain \(CTLineGetGlyphCount(ctLine([("ffi", [.font: f])]))) kern \(CTLineGetGlyphCount(ctLine([("ffi", [.font: f, .kern: 4])]))) tracking \(CTLineGetGlyphCount(ctLine([("ffi", [.font: f, .tracking: 4])])))")
    out("F1b", "SwiftUI ffi plain " + measure(Text("ffi")) + " kerning(4) " + measure(Text("ffi").kerning(4)))
    let base = Text("aaaa").font(.system(size: 10)) + Text("BBBB").font(.system(size: 30))
    out("F2", "both strikethrough " + diffBox(bitmap(canvas(Text("aaaa").font(.system(size: 10)).strikethrough() + Text("BBBB").font(.system(size: 30)).strikethrough())), bitmap(canvas(base))))
    do {
        let u = bitmap(canvas(Text("aaaa").font(.system(size: 10)).underline(color: .red) + Text("BBBB").font(.system(size: 30)).underline(color: .blue)))
        out("F3", "underline red(10pt)+blue(30pt) diff " + diffBox(u, bitmap(canvas(base))) + "; ink left cols 0..40 rows 66..69 \(ink(u, cols: 0..<40, rows: 66..<70)) rows 60..61 \(ink(u, cols: 0..<40, rows: 60..<62)); right cols 60..190 rows 66..69 \(ink(u, cols: 60..<190, rows: 66..<70))")
        let same = bitmap(canvas(Text("xx").underline(color: .red) + Text("xx").underline(color: .blue)))
        out("F3b", "13pt underline red+blue: left \(ink(same, cols: 0..<20, rows: 28..<30)) right \(ink(same, cols: 35..<53, rows: 28..<30))")
    }
    out("F4", "Text(\"x   x\").underline() diff " + diffBox(bitmap(canvas(Text("x   x").underline())), bitmap(canvas(Text("x   x")))) + " | plain ink \(inkColumns(bitmap(canvas(Text("x   x")))))")
    out("F4b", "Text(\"x \") + Text(\"  x\").underline() diff " + diffBox(bitmap(canvas(Text("x ") + Text("  x").underline())), bitmap(canvas(Text("x   x")))))
    out("F4c", "Text(\"x\") + Text(\"   \").underline() + Text(\"x\") diff " + diffBox(bitmap(canvas(Text("x") + Text("   ").underline() + Text("x"))), bitmap(canvas(Text("x   x")))))
    out("F4d", "wrapped \"aaaa bbbb\" underline at 30: line 1 rows 28-29 cols " + diffBox(bitmap(canvas(Text("aaaa bbbb").underline().frame(width: 30, alignment: .leading), height: 16)), bitmap(canvas(Text("aaaa bbbb").frame(width: 30, alignment: .leading), height: 16))))
    out("F4e", "Text(\"x   \").background(yellow attr) " + { () -> String in
        var a = AttributedString("x   "); a.backgroundColor = .yellow
        return diffBox(bitmap(canvas(Text(a))), bitmap(canvas(Text("x   "))))
    }())
    out("M19", "Text(\"![alt](https://x.org/i.png)\") " + identify(Text("![alt](https://x.org/i.png)"), [("alt", AnyView(Text(verbatim: "alt"))), ("verbatim", AnyView(Text(verbatim: "![alt](https://x.org/i.png)"))), ("empty", AnyView(Text(verbatim: ""))), ("accent alt", AnyView(Text(verbatim: "alt").foregroundColor(.accentColor)))]))
    out("M20", "Text(\"www.x.org\") " + identify(Text("www.x.org"), [("verbatim", AnyView(Text(verbatim: "www.x.org"))), ("accent", AnyView(Text(verbatim: "www.x.org").foregroundColor(.accentColor)))]))
    out("M21", "Text(\"a@b.org\") " + identify(Text("a@b.org"), [("verbatim", AnyView(Text(verbatim: "a@b.org"))), ("accent", AnyView(Text(verbatim: "a@b.org").foregroundColor(.accentColor)))]))
    out("M22", "Text(\"[**b**](https://x.org)\") " + identify(Text("[**b**](https://x.org)"), [("bold accent", AnyView(Text(verbatim: "b").bold().foregroundColor(.accentColor))), ("accent", AnyView(Text(verbatim: "b").foregroundColor(.accentColor)))]))
    out("M23", "Text(\"&#65;&copy;\") " + identify(Text("&#65;&copy;"), [("A©", AnyView(Text(verbatim: "A\u{A9}"))), ("verbatim", AnyView(Text(verbatim: "&#65;&copy;")))]))
    out("M24", "Text(\"a\\\\nb\") (backslash-newline) " + identify(Text("a\\\nb"), [("a\\nb verbatim", AnyView(Text(verbatim: "a\\\nb"))), ("a\\nb", AnyView(Text(verbatim: "a\nb")))]))
    out("M25", "Text(\"`**x**`\") " + identify(Text("`**x**`"), [("mono **x**", AnyView(Text(verbatim: "**x**").monospaced())), ("mono bold x", AnyView(Text(verbatim: "x").monospaced().bold()))]))
    out("M26", "Text(\"http://x.org/a_b_c\") " + identify(Text("http://x.org/a_b_c"), [("accent url", AnyView(Text(verbatim: "http://x.org/a_b_c").foregroundColor(.accentColor))), ("verbatim", AnyView(Text(verbatim: "http://x.org/a_b_c")))]))
    out("M27", "Text(\"__b__\") " + identify(Text("__b__"), [("bold", AnyView(Text("b").bold())), ("verbatim", AnyView(Text(verbatim: "__b__")))]))
    out("M28", "Text(\"[a](relative/path)\") " + identify(Text("[a](relative/path)"), [("accent", AnyView(Text(verbatim: "a").foregroundColor(.accentColor))), ("plain a", AnyView(Text(verbatim: "a")))]))
    out("M29", "Text(\"Count: \\(n)\") with n=42 renders " + identify(Text("Count: \(42)"), [("Count: 42", AnyView(Text(verbatim: "Count: 42")))]))
    out("M32", "Text(\"<b>x</b>\") " + identify(Text("<b>x</b>"), [("verbatim", AnyView(Text(verbatim: "<b>x</b>"))), ("bold x", AnyView(Text(verbatim: "x").bold()))]))
    out("M33", "Text(\"a  \\nb\") " + identify(Text("a  \nb"), [("verbatim", AnyView(Text(verbatim: "a  \nb")))]))
    out("M34", "Text(\"&nbsp;x\") " + identify(Text("&nbsp;x"), [("nbsp x", AnyView(Text(verbatim: "\u{A0}x"))), ("space x", AnyView(Text(verbatim: " x")))]))
    out("C7d", "Text(\"b\").baselineOffset(5) alone " + measure(Text("b").baselineOffset(5)) + " | -5 " + measure(Text("b").baselineOffset(-5)) + " | plain b " + measure(Text("b")))
    out("C18", "reservesSpace 3 on 10pt+30pt one line " + measure((Text("a").font(.system(size: 10)) + Text("B").font(.system(size: 30))).lineLimit(3, reservesSpace: true)) + " | 30pt B reservesSpace 3 " + measure(Text("B").font(.system(size: 30)).lineLimit(3, reservesSpace: true)) + " | 10pt a reservesSpace 3 " + measure(Text("a").font(.system(size: 10)).lineLimit(3, reservesSpace: true)) + " | 30pt B + 10pt a " + measure((Text("B").font(.system(size: 30)) + Text("a").font(.system(size: 10))).lineLimit(3, reservesSpace: true)))
    out("C19", "lineLimit(1) on 10pt line + 30pt second line, wrap 40: " + measure((Text("aa aa").font(.system(size: 10)) + Text(" BB").font(.system(size: 30))).lineLimit(1), ProposedViewSize(width: 40, height: nil)))
    out("M30", "Button(\"**b**\") {} " + identify(Button("**b**") {}, [("Text(bold) label", AnyView(Button {} label: { Text("b").bold() })), ("verbatim label", AnyView(Button {} label: { Text(verbatim: "**b**") }))]))
    out("M31", "Toggle(\"**b**\") " + identify(Toggle("**b**", isOn: .constant(false)), [("bold label", AnyView(Toggle(isOn: .constant(false)) { Text("b").bold() })), ("verbatim label", AnyView(Toggle(isOn: .constant(false)) { Text(verbatim: "**b**") }))]))
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    run()
    followUp()
}
