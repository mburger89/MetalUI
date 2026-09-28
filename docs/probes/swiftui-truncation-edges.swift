// SwiftUI probe: truncation's edges (plan task 11 part 1, lane 1) — a hard
// break inside the text a line limit truncates, and a width narrower than the
// token itself. Evidence for ruling TE-T in
// docs/superpowers/2026-09-28-text-semantics-decisions.md, cited by arm id.
//
// HOW TO RUN (ruling SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-truncation-edges.swift -o /tmp/trunc-edges && /tmp/trunc-edges
//   /usr/bin/swift docs/probes/swiftui-truncation-edges.swift
//
// INSTRUMENT. RENDER only, as `swiftui-text-semantics.swift`'s T/X arms:
// `ImageRenderer` at scale 2 on white, a `Text` in a fixed top-leading canvas,
// compared pixel for pixel (`differing` counts RGB mismatches) against
// candidate strings drawn `fixedSize()` in the same canvas. `ctKept` is
// CoreText's `CTLineCreateTruncatedLine` read back as a string (the kept
// characters by run string range, the token run spelled `…`). Headless: no
// window is ordered front.
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - E0 (positive control): `swiftui-text-semantics.swift`'s X8 case — the
//   rest after line 1 truncated as ONE line by CoreText — must read 0 px, and
//   the untruncated two-line text must not.
// - E1/E2: each candidate reading is separated from the others (the list is
//   printed with every candidate's pixel count, not only the best).
// - E3: at each width every candidate ("", "…", "H", "H…", …) is printed.
// - E4: the paragraph-only reading (E1/E2) against the whole rest, when the
//   paragraph itself overflows.
//
// RECORDED 2026-09-28 by plan task 11 part 1's lane 1, macOS 27.0 (26A428),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (lock probe:
// `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`) — irrelevant, no
// window is ordered front. Compiled form run twice and interpreted form once,
// stdout byte-identical (32 lines), exit 0, stderr empty.
//
//   --- E0 control: X8's paragraph, lineLimit(2) at 100
//     E0 tail: CT rest "gamma delta e…" — line1+CTrest=0px untruncated=2254px
//     E0 head: CT rest "…zeta eta theta" — line1+CTrest=0px untruncated=2076px
//     E0 middle: CT rest "gamma…a theta" — line1+CTrest=0px untruncated=2220px
//   --- E1 hard breaks: "Ready\nSet\nGo", lineLimit(2) at 100
//     E1 tail: CT one-line truncation of "Set\nGo" at 100 = "Set\nGo" — Ready/Set…=0px Ready/Set=54px Ready/CTrest=382px Ready/…Go=656px Ready/Set…Go=327px untruncated=382px
//     E1 head: CT one-line truncation of "Set\nGo" at 100 = "Set\nGo" — Ready/Set…=54px Ready/Set=0px Ready/CTrest=328px Ready/…Go=633px Ready/Set…Go=381px untruncated=328px
//     E1 middle: CT one-line truncation of "Set\nGo" at 100 = "Set\nGo" — Ready/Set…=54px Ready/Set=0px Ready/CTrest=328px Ready/…Go=633px Ready/Set…Go=381px untruncated=328px
//     E1 lineLimit(1) tail at 100: Ready…=0px Ready=54px CT=801px
//   --- E2 a hard break inside a long rest: lineLimit(2) at 100
//     E2 tail: CT rest "gamma\ndelta e…" — line1+CTrest=849px line1+gamma…=0px line1+gamma=54px untruncated=2481px
//     E2 head: CT rest "…zeta eta theta" — line1+CTrest=1948px line1+gamma…=54px line1+gamma=0px untruncated=2471px
//     E2 middle: CT rest "gamma…a theta" — line1+CTrest=798px line1+gamma…=54px line1+gamma=0px untruncated=2471px
//   --- E4 an overflowing paragraph with more text after it: lineLimit(2) at 100
//     E4 tail: line1+CTpara=0px line1+CTrest=0px
//     E4 head: line1+CTpara=0px line1+CTrest=2379px
//     E4 middle: line1+CTpara=0px line1+CTrest=1388px
//   --- E3 a width narrower than the token: "Hello", lineLimit(1)
//     E3 width 4.0: CT tail "nil" — empty=66px …=106px H…=148px H=94px Hello=513px
//     E3 width 8.0: CT tail "nil" — empty=122px …=158px H…=92px H=38px Hello=457px
//     E3 width 10.0: CT tail "nil" — empty=160px …=186px H…=54px H=0px Hello=419px
//     E3 width 11.0: CT tail "…" — empty=54px …=0px H…=240px H=186px Hello=605px
//     E3 width 12.0: CT tail "…" — empty=54px …=0px H…=240px H=186px Hello=605px
//     E3 width 14.0: CT tail "…" — empty=54px …=0px H…=240px H=186px Hello=605px
//     E3 width 20.0: CT tail "H…" — empty=214px …=240px H…=0px H=54px Hello=423px
//     E3 head width 8.0: CT "nil" — empty=122px …=158px H=38px o=197px …o=292px …lo=372px H…=92px H…o=226px
//     E3 middle width 8.0: CT "nil" — empty=122px …=158px H=38px o=197px …o=292px …lo=372px H…=92px H…o=226px
//     E3 head width 10.0: CT "nil" — empty=160px …=186px H=0px o=235px …o=320px …lo=400px H…=54px H…o=188px
//     E3 middle width 10.0: CT "nil" — empty=160px …=186px H=0px o=235px …o=320px …lo=400px H…=54px H…o=188px
//     E3 head width 20.0: CT "…o" — empty=188px …=134px H=320px o=286px …o=108px …lo=258px H…=343px H…o=477px
//     E3 middle width 20.0: CT "…" — empty=54px …=0px H=186px o=152px …o=134px …lo=214px H…=240px H…o=374px
//   done
//
// READING.
// - E0 reproduces X8 (0 px for all three modes, each separated from the
//   untruncated text by > 2000 px): without a hard break, the rest after the
//   kept lines is truncated as one line.
// - E1/E2: WITH a hard break, the last kept line is the rest's first
//   paragraph only — never the one-line truncation of the whole rest
//   (`line1+CTrest` 327–1948 px). In TAIL mode a token follows it whenever more
//   text follows ("Ready\nSet…", "Alpha beta\ngamma…", and lineLimit(1)
//   "Ready…": 0 px), even though the paragraph fits; in HEAD and MIDDLE mode a
//   paragraph that fits is drawn whole, no token ("Ready\nSet",
//   "Alpha beta\ngamma": 0 px). The 54 px between each pair is the token's ink.
// - E4: when that paragraph itself overflows, it is CoreText's one-line
//   truncation of the PARAGRAPH, in all three modes (0 px; the whole rest's
//   reads 2379/1388 px in head/middle, and equal in tail, where the two
//   truncations keep the same prefix).
// - E3: at a width narrower than the token (CoreText answers nil at 4, 8 and
//   10), SwiftUI draws no token in any mode; at 10 it draws "H" exactly (0 px),
//   at 8 and 4 a clipped "H" (38 and 94 px short of a whole one) — the longest
//   prefix that fits, and at least one character, clipped at the frame. From
//   11 the token alone (0 px), at 20 "H…" (tail, 0 px) and "…" (middle, 0 px).
// - Observed, not ruled on: head at 20 matches none of its candidates (nearest
//   "…o", CoreText's, 108 px) — `swiftui-text-semantics.swift`'s head arms
//   (X5, X7 at 60) agree with CoreText; this one-character case is not in
//   `TruncationOracleTests`' SwiftUI claims, which are CoreText's.

import AppKit
import CoreText
import SwiftUI

@MainActor
func bitmap(_ view: some View) -> (bytes: [UInt8], w: Int, h: Int) {
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

func differing(_ a: (bytes: [UInt8], w: Int, h: Int), _ b: (bytes: [UInt8], w: Int, h: Int)) -> Int {
    guard a.w == b.w, a.h == b.h else { return Int.max }
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

@MainActor
func canvas(_ view: some View, width: CGFloat) -> some View {
    view.frame(width: width, height: 70, alignment: .topLeading)
}

func ctKept(_ s: String, width: Double, type: CTLineTruncationType) -> String {
    let font = NSFont.systemFont(ofSize: 13) as CTFont
    let a = NSAttributedString(string: s, attributes: [.font: font])
    let marker = NSAttributedString.Key("probeToken")
    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}",
                                                                    attributes: [.font: font, marker: true]))
    guard let t = CTLineCreateTruncatedLine(CTLineCreateWithAttributedString(a), width, type, token) else { return "nil" }
    let utf16 = Array(s.utf16)
    var out = ""
    for run in CTLineGetGlyphRuns(t) as! [CTRun] {
        if (CTRunGetAttributes(run) as NSDictionary)[marker] != nil { out += "\u{2026}"; continue }
        let r = CTRunGetStringRange(run)
        out += String(utf16CodeUnits: Array(utf16[r.location..<(r.location + r.length)]), count: r.length)
    }
    return out
}

@MainActor
func readings(_ target: some View, width: CGFloat, _ candidates: [(String, String)]) -> String {
    let t = bitmap(canvas(target, width: width))
    return candidates.map { name, text in
        "\(name)=\(differing(t, bitmap(canvas(Text(text).fixedSize(), width: width))))px"
    }.joined(separator: " ")
}

func show(_ s: String) -> String { s.debugDescription }

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let modes: [(String, CTLineTruncationType, Text.TruncationMode)] =
        [("tail", .end, .tail), ("head", .start, .head), ("middle", .middle, .middle)]

    print("--- E0 control: X8's paragraph, lineLimit(2) at 100")
    do {
        let s = "Alpha beta gamma delta epsilon zeta eta theta"
        let line1 = "Alpha beta", rest = "gamma delta epsilon zeta eta theta"
        for (name, ct, mode) in modes {
            let kept = ctKept(rest, width: 100, type: ct)
            print("  E0 \(name): CT rest \(show(kept)) — " + readings(
                Text(s).lineLimit(2).truncationMode(mode).frame(width: 100, alignment: .leading), width: 100,
                [("line1+CTrest", line1 + "\n" + kept), ("untruncated", s)]))
        }
    }

    print("--- E1 hard breaks: \"Ready\\nSet\\nGo\", lineLimit(2) at 100")
    do {
        let s = "Ready\nSet\nGo"
        for (name, ct, mode) in modes {
            let kept = ctKept("Set\nGo", width: 100, type: ct)
            print("  E1 \(name): CT one-line truncation of \"Set\\nGo\" at 100 = \(show(kept)) — " + readings(
                Text(s).lineLimit(2).truncationMode(mode).frame(width: 100, alignment: .leading), width: 100,
                [("Ready/Set…", "Ready\nSet\u{2026}"), ("Ready/Set", "Ready\nSet"),
                 ("Ready/CTrest", "Ready\n" + kept), ("Ready/…Go", "Ready\n\u{2026}Go"),
                 ("Ready/Set…Go", "Ready\nSet\u{2026}Go"), ("untruncated", s)]))
        }
        print("  E1 lineLimit(1) tail at 100: " + readings(
            Text(s).lineLimit(1).frame(width: 100, alignment: .leading), width: 100,
            [("Ready…", "Ready\u{2026}"), ("Ready", "Ready"), ("CT", ctKept(s, width: 100, type: .end))]))
    }

    print("--- E2 a hard break inside a long rest: lineLimit(2) at 100")
    do {
        let s = "Alpha beta gamma\ndelta epsilon zeta eta theta"
        let rest = "gamma\ndelta epsilon zeta eta theta"
        for (name, ct, mode) in modes {
            let kept = ctKept(rest, width: 100, type: ct)
            let firstLine = ctKept("gamma", width: 100, type: ct)
            print("  E2 \(name): CT rest \(show(kept)) — " + readings(
                Text(s).lineLimit(2).truncationMode(mode).frame(width: 100, alignment: .leading), width: 100,
                [("line1+CTrest", "Alpha beta\n" + kept), ("line1+gamma…", "Alpha beta\ngamma\u{2026}"),
                 ("line1+gamma", "Alpha beta\n" + firstLine), ("untruncated", s)]))
        }
    }

    print("--- E4 an overflowing paragraph with more text after it: lineLimit(2) at 100")
    do {
        let s = "Alpha beta gamma delta epsilon zeta eta theta\nmore"
        let para = "gamma delta epsilon zeta eta theta", rest = para + "\nmore"
        for (name, ct, mode) in modes {
            print("  E4 \(name): " + readings(
                Text(s).lineLimit(2).truncationMode(mode).frame(width: 100, alignment: .leading), width: 100,
                [("line1+CTpara", "Alpha beta\n" + ctKept(para, width: 100, type: ct)),
                 ("line1+CTrest", "Alpha beta\n" + ctKept(rest, width: 100, type: ct))]))
        }
    }

    print("--- E3 a width narrower than the token: \"Hello\", lineLimit(1)")
    for w in [4.0, 8, 10, 11, 12, 14, 20] as [CGFloat] {
        print("  E3 width \(w): CT tail \(show(ctKept("Hello", width: Double(w), type: .end))) — " + readings(
            Text("Hello").lineLimit(1).frame(width: w, alignment: .leading), width: 40,
            [("empty", ""), ("…", "\u{2026}"), ("H…", "H\u{2026}"), ("H", "H"), ("Hello", "Hello")]))
    }
    for w in [8.0, 10, 20] as [CGFloat] {
        for (name, ct, mode) in modes.dropFirst() {
            print("  E3 \(name) width \(w): CT \(show(ctKept("Hello", width: Double(w), type: ct))) — " + readings(
                Text("Hello").lineLimit(1).truncationMode(mode).frame(width: w, alignment: .leading), width: 40,
                [("empty", ""), ("…", "\u{2026}"), ("H", "H"), ("o", "o"), ("…o", "\u{2026}o"), ("…lo", "\u{2026}lo"), ("H…", "H\u{2026}"), ("H…o", "H\u{2026}o")]))
        }
    }
    print("done")
}
