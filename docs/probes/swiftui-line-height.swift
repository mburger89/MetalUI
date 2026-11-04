// SwiftUI probe: a single line of `Text`'s height against CoreText's metrics, 28 SF sizes and seven other
// families, plus a mixed-size stack and two-line texts. The evidence for divergence 86 as amended by R4-3b
// (Tasks.md; human check DS2 Finding B; erratum to ruling `TE-G` item 3 in
// docs/superpowers/2026-09-28-text-semantics-decisions.md; record 212).
//
// HOW TO RUN (ruling SA-O):
//
//   xcrun swiftc -O docs/probes/swiftui-line-height.swift -o /tmp/lh && /tmp/lh Tests/Fonts/NotoSans-Regular.ttf
//
// Apple's toolchain (`xcrun swiftc`); a swift.org toolchain's JIT fails on SwiftUI symbols. The one argument is
// the path of the Noto Sans file, registered for the process.
//
// NO ARM READS PIXELS. Every height is a layout reading (`NSHostingView` + `layoutSubtreeIfNeeded`, a custom
// `Layout` asking the subview `sizeThatFits(.unspecified)`), so it runs in a LOCKED session. Run twice on
// 2026-11-04 (macOS 27.2, locked), byte-identical stdout.
//
// WHAT IT SHOWS [MEASURED]:
// - SwiftUI's line is 16 / 30 / 56 at SF 13 / 26 / 48; MetalUI's `ceil(ascent + descent + leading)` is 16 / 31 / 57
//   (CoreText sums 15.311, 30.621, 56.531). `ceil` agrees with SwiftUI at 16 of 28 SF sizes.
// - `NSLayoutManager.defaultLineHeight` equals `round(a) + round(d) + round(l)` at every size and agrees with
//   SwiftUI at 21 of 28 SF sizes, 12 of 12 for Noto Sans, Menlo, Georgia, Courier New and Avenir Next, 5 for
//   Helvetica Neue, 2 for Times New Roman. At SF 10, 11, 15, 16, 19, 20 and 21 SwiftUI reads that sum + 1,
//   unexplained; no simple formula matches every row.
// - The mixed stack (13, 26, 60 x 30 block, 48, 13, 26, 13 pt) is 226.43 in SwiftUI; MetalUI's is 229.43, exactly
//   three line heights more (the gaps agree). Two lines of SF 26 are 60 (2 x 30), of SF 48 112 (2 x 56).
//
// RECORDED OUTPUT (macOS 27.2, 2026-11-04, locked session):
//
// size | SwiftUI h | ceil(sum) | CT sum | a d l (CT) | NSLayoutManager.defaultLineHeight | boundingRect(uses LM)
// 9 | 11.0 | 11.0 | 10.600 | 8.701 1.898 0.000 | 11.000 | used 11.000 br 11.000
// 10 | 13.0 | 12.0 | 11.777 | 9.668 2.109 0.000 | 12.000 | used 12.000 br 12.000
// 11 | 14.0 | 13.0 | 12.955 | 10.635 2.320 0.000 | 13.000 | used 13.000 br 13.000
// 12 | 15.0 | 15.0 | 14.133 | 11.602 2.531 0.000 | 15.000 | used 15.000 br 15.000
// 13 | 16.0 | 16.0 | 15.311 | 12.568 2.742 0.000 | 16.000 | used 16.000 br 16.000
// 14 | 17.0 | 17.0 | 16.488 | 13.535 2.953 0.000 | 17.000 | used 17.000 br 17.000
// 15 | 19.0 | 18.0 | 17.666 | 14.502 3.164 0.000 | 18.000 | used 18.000 br 18.000
// 16 | 19.0 | 19.0 | 18.844 | 15.469 3.375 0.000 | 18.000 | used 18.000 br 18.000
// 17 | 20.0 | 21.0 | 20.021 | 16.436 3.586 0.000 | 20.000 | used 20.000 br 20.000
// 18 | 21.0 | 22.0 | 21.199 | 17.402 3.797 0.000 | 21.000 | used 21.000 br 21.000
// 19 | 23.0 | 23.0 | 22.377 | 18.369 4.008 0.000 | 22.000 | used 22.000 br 22.000
// 20 | 24.0 | 24.0 | 23.555 | 19.336 4.219 0.000 | 23.000 | used 23.000 br 23.000
// 21 | 25.0 | 25.0 | 24.732 | 20.303 4.430 0.000 | 24.000 | used 24.000 br 24.000
// 22 | 26.0 | 26.0 | 25.910 | 21.270 4.641 0.000 | 26.000 | used 26.000 br 26.000
// 24 | 28.0 | 29.0 | 28.266 | 23.203 5.062 0.000 | 28.000 | used 28.000 br 28.000
// 26 | 30.0 | 31.0 | 30.621 | 25.137 5.484 0.000 | 30.000 | used 30.000 br 30.000
// 28 | 33.0 | 33.0 | 32.977 | 27.070 5.906 0.000 | 33.000 | used 33.000 br 33.000
// 30 | 35.0 | 36.0 | 35.332 | 29.004 6.328 0.000 | 35.000 | used 35.000 br 35.000
// 32 | 38.0 | 38.0 | 37.688 | 30.938 6.750 0.000 | 38.000 | used 38.000 br 38.000
// 34 | 40.0 | 41.0 | 40.043 | 32.871 7.172 0.000 | 40.000 | used 40.000 br 40.000
// 36 | 43.0 | 43.0 | 42.398 | 34.805 7.594 0.000 | 43.000 | used 43.000 br 43.000
// 40 | 47.0 | 48.0 | 47.109 | 38.672 8.438 0.000 | 47.000 | used 47.000 br 47.000
// 44 | 52.0 | 52.0 | 51.820 | 42.539 9.281 0.000 | 52.000 | used 52.000 br 52.000
// 48 | 56.0 | 57.0 | 56.531 | 46.406 10.125 0.000 | 56.000 | used 56.000 br 56.000
// 56 | 66.0 | 66.0 | 65.953 | 54.141 11.812 0.000 | 66.000 | used 66.000 br 66.000
// 64 | 76.0 | 76.0 | 75.375 | 61.875 13.500 0.000 | 76.000 | used 76.000 br 76.000
// 72 | 85.0 | 85.0 | 84.797 | 69.609 15.188 0.000 | 85.000 | used 85.000 br 85.000
// 96 | 113.0 | 114.0 | 113.062 | 92.812 20.250 0.000 | 113.000 | used 113.000 br 113.000
// agree LM 21/28 ceil 16/28
// --- other fonts: SwiftUI h | ceil(sum) | round(a)+round(d)+round(l) | LM
// Noto Sans: 10:14/14/14/14 11:15/15/15/15 13:18/18/18/18 15:20/21/20/20 17:23/24/23/23 20:27/28/27/27 22:30/30/30/30 24:33/33/33/33 26:36/36/36/36 30:41/41/41/41 36:49/50/49/49 48:65/66/65/65 | agree ceil 7 rr 12 LM 12 of 12
// Menlo: 10:11/12/11/11 11:13/13/13/13 13:15/16/15/15 15:18/18/18/18 17:20/20/20/20 20:24/24/24/24 22:25/26/25/25 24:28/28/28/28 26:30/31/30/30 30:35/35/35/35 36:41/42/41/41 48:56/56/56/56 | agree ceil 7 rr 12 LM 12 of 12
// Helvetica Neue: 10:12/12/12/12 11:12/14/12/12 13:15/16/15/15 15:17/18/17/17 17:20/21/20/20 20:23/24/24/24 22:26/27/27/27 24:28/29/29/29 26:31/32/32/32 30:35/36/36/36 36:42/43/43/43 48:56/58/57/57 | agree ceil 1 rr 5 LM 5 of 12
// Georgia: 10:11/12/11/11 11:12/13/12/12 13:15/15/15/15 15:17/18/17/17 17:20/20/20/20 20:22/23/22/22 22:25/25/25/25 24:27/28/27/27 26:30/30/30/30 30:35/35/35/35 36:41/41/41/41 48:55/55/55/55 | agree ceil 7 rr 12 LM 12 of 12
// Times New Roman: 10:11/12/11/11 11:12/13/12/12 13:15/15/16/16 15:16/18/17/17 17:19/20/20/20 20:22/23/23/23 22:25/26/26/26 24:26/28/27/27 26:29/30/30/30 30:33/35/34/34 36:40/42/42/42 48:53/56/55/55 | agree ceil 1 rr 2 LM 2 of 12
// Courier New: 10:11/12/11/11 11:12/13/12/12 13:15/15/15/15 15:17/17/17/17 17:19/20/19/19 20:23/23/23/23 22:25/25/25/25 24:27/28/27/27 26:30/30/30/30 30:34/34/34/34 36:41/41/41/41 48:54/55/54/54 | agree ceil 7 rr 12 LM 12 of 12
// Avenir Next: 10:14/14/14/14 11:15/16/15/15 13:18/18/18/18 15:20/21/20/20 17:23/24/23/23 20:27/28/27/27 22:30/31/30/30 24:33/33/33/33 26:36/36/36/36 30:41/41/41/41 36:49/50/49/49 48:66/66/66/66 | agree ceil 6 rr 12 LM 12 of 12
// mixed stack and multi-line
// VStack 13,26,48,13,26,13 + 60x30: height 226.4267578125
// two lines 26: 60.0  48: 112.0  13: 32.0
//
import AppKit
import SwiftUI
import CoreText
func f(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
final class Log { var a: [String] = [] }
nonisolated(unsafe) let log = Log()
struct Ask: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let s = subviews.first else { return .zero }
        let o = s.sizeThatFits(.unspecified)
        log.a.append("\(name) \(o.width)x\(o.height)")
        return o
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}
@MainActor func h<V: View>(_ v: V, name: String) -> CGFloat {
    log.a.removeAll()
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: Ask(name: name) { v })
    host.sizingOptions = []
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let s = log.a.last ?? "?"
    w.close()
    return CGFloat(Double(s.split(separator: "x").last ?? "0") ?? -1)
}
@MainActor func run() {
    let lm = NSLayoutManager()
    print("size | SwiftUI h | ceil(sum) | CT sum | a d l (CT) | NSLayoutManager.defaultLineHeight | boundingRect(uses LM)")
    var sizes: [CGFloat] = [9,10,11,12,13,14,15,16,17,18,19,20,21,22,24,26,28,30,32,34,36,40,44,48,56,64,72,96]
    sizes.sort()
    var agreeLM = 0, agreeCeil = 0, n = 0
    for s in sizes {
        let suih = h(Text("Hg").font(.system(size: s)), name: "t")
        let font = NSFont.systemFont(ofSize: s)
        let ct = font as CTFont
        let a = CTFontGetAscent(ct), d = CTFontGetDescent(ct), l = CTFontGetLeading(ct)
        let sum = a + d + l
        let dlh = lm.defaultLineHeight(for: font)
        let ts = NSTextStorage(string: "Hg", attributes: [.font: font])
        let lm2 = NSLayoutManager(); ts.addLayoutManager(lm2)
        let tc = NSTextContainer(size: NSSize(width: 1000, height: 1000)); tc.lineFragmentPadding = 0; lm2.addTextContainer(tc)
        lm2.ensureLayout(for: tc)
        let used = lm2.usedRect(for: tc).height
        let attr = NSAttributedString(string: "Hg", attributes: [.font: font])
        let br = attr.boundingRect(with: NSSize(width: 1000, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
        n += 1; if suih == dlh.rounded(.up) || suih == dlh { agreeLM += 1 }; if suih == ceil(sum) { agreeCeil += 1 }
        print("\(Int(s)) | \(suih) | \(ceil(sum)) | \(f(sum)) | \(f(a)) \(f(d)) \(f(l)) | \(f(dlh)) | used \(f(used)) br \(f(br))")
    }
    print("agree LM \(agreeLM)/\(n) ceil \(agreeCeil)/\(n)")
    print("--- other fonts: SwiftUI h | ceil(sum) | round(a)+round(d)+round(l) | LM")
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, .process, nil)
    for fam in ["Noto Sans", "Menlo", "Helvetica Neue", "Georgia", "Times New Roman", "Courier New", "Avenir Next"] {
        var line = "\(fam):"
        var c = 0, r = 0, m = 0
        for s: CGFloat in [10, 11, 13, 15, 17, 20, 22, 24, 26, 30, 36, 48] {
            guard let font = NSFont(name: fam == "Noto Sans" ? "NotoSans-Regular" : fam == "Menlo" ? "Menlo-Regular" : fam == "Helvetica Neue" ? "HelveticaNeue" : fam == "Georgia" ? "Georgia" : fam == "Times New Roman" ? "TimesNewRomanPSMT" : fam == "Courier New" ? "CourierNewPSMT" : "AvenirNext-Regular", size: s) else { line += " nofont"; continue }
            let suih = h(Text("Hg").font(.custom(font.fontName, fixedSize: s)), name: "t")
            let ct = font as CTFont
            let a = CTFontGetAscent(ct), d = CTFontGetDescent(ct), l = CTFontGetLeading(ct)
            let dl = lm.defaultLineHeight(for: font)
            let ce = ceil(a + d + l), rr = a.rounded() + d.rounded() + l.rounded()
            if suih == ce { c += 1 }; if suih == rr { r += 1 }; if suih == dl { m += 1 }
            line += " \(Int(s)):\(Int(suih))/\(Int(ce))/\(Int(rr))/\(Int(dl))"
        }
        print(line, "| agree ceil \(c) rr \(r) LM \(m) of 12")
    }
    print("mixed stack and multi-line")
    print("VStack 13,26,48,13,26,13 + 60x30: height", h(VStack(alignment: .leading) {
        Text("Aa").font(.system(size: 13)); Text("Bb").font(.system(size: 26)); Color.red.frame(width: 60, height: 30)
        Text("Cc").font(.system(size: 48)); Text("Dd").font(.system(size: 13)); Text("Ee").font(.system(size: 26)); Text("Ff").font(.system(size: 13))
    }, name: "t"))
    print("two lines 26:", h(Text("Hg\nHg").font(.system(size: 26)), name: "t"), " 48:", h(Text("Hg\nHg").font(.system(size: 48)), name: "t"), " 13:", h(Text("Hg\nHg").font(.system(size: 13)), name: "t"))
}
MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.accessory); run() }
exit(0)
