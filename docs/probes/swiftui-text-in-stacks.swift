// SwiftUI probe: a wrapping `Text` inside a stack whose height is tight —
// what the stack gives it once a text's answer depends on the height proposal
// (plan task 11 part 1, critic round, ruling TE-R).
//
// Why it exists. `TE-H` item 2 makes a text's height answer depend on a finite
// height proposal (`max(1, ⌊h / lineHeight⌋)` lines, arms L5/X9 of
// `swiftui-text-semantics.swift`). That turns every multi-line text from
// vertically rigid into vertically flexible inside MetalUI's SwiftUI-shaped
// stacks (`CN-B`: least-flexible-first, the remainder shared equally), which
// changes what a `VStack` allocates. L5/X9 measured a text ALONE; no arm
// measured a text beside a sibling. These arms do.
//
// HOW TO RUN (SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-text-in-stacks.swift -o /tmp/ts-probe && /tmp/ts-probe
//   /usr/bin/swift docs/probes/swiftui-text-in-stacks.swift
//
// INSTRUMENT. A one-child `Layout` (`Where`) records the bounds its parent
// places it at; an `ImageRenderer` render drives placement. The text is the
// paragraph of `swiftui-text-semantics.swift` (six lines of 16 at width 100,
// its M2/L1 control), in the default font, in a stack framed 100 wide.
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - K0: the paragraph alone at 100 × unspecified (100×96), the control every
//   height below is read against.
// - K1 (Spacer), K2 (a 40-tall colour), K3 (two paragraphs), K4 (Spacer with
//   minLength 0), at a tight and a roomy height: a tight row that reads fewer
//   than six lines is the text compressed by the stack; a roomy row that reads
//   six is the separating control.
//
// RECORDED 2026-09-28 by the plan task 11 part 1 critic round, macOS 27.0
// (26A428), Apple Swift 6.4, screen LOCKED (no window is ordered front). The
// compiled form was run twice and the interpreted form once, stdout
// byte-identical, exit 0. `y` is in the renderer's space (read heights; a
// child's y is only meaningful against its sibling's):
//
//   K0 paragraph alone at width 100: y=-48 h=96
//   K1 VStack{Text; Spacer} h=60: text y=0 h=15.5 spacer y=0 h=44.5
//   K1 VStack{Text; Spacer} h=100: text y=-50 h=47.5 spacer y=0 h=52.5
//   K1 VStack{Text; Spacer} h=200: text y=-100 h=96 spacer y=0 h=104
//   K2 VStack{Text; Color h40} h=80: text y=4.25 h=31.5 colour y=35.75 h=40
//   K2 VStack{Text; Color h40} h=200: text y=32 h=96 colour y=128 h=40
//   K3 VStack{Text; Text} h=100: a y=2.5 h=47.5 b y=50 h=47.5
//   K3 VStack{Text; Text} h=300: a y=54 h=96 b y=150 h=96
//   K4 VStack{Text; Spacer(minLength: 0)} h=60: text y=0 h=15.5 spacer y=0 h=44.5
//   K4 VStack{Text; Spacer(minLength: 0)} h=200: text y=-100 h=96 spacer y=0 h=104
//   done
//
// READING (ruling TE-R).
// - A stack DOES compress a wrapping text by the height proposal it shares
//   out: beside a `Spacer` at 60 the paragraph gets one line (15.5) and the
//   spacer the rest (44.5) although the spacer could have shrunk to 8 (K1);
//   at 100, three lines (47.5, half of 100 floored to whole lines); roomy
//   (200), all six (96) — the separating control. Beside a rigid 40-tall
//   colour at 80 it gets the 40 left, two lines (K2); two paragraphs at 100
//   share 50 each, three lines apiece (K3). `Spacer(minLength: 0)` changes
//   nothing (K4). This is exactly least-flexible-first with the remainder
//   shared equally (`CN-B`) over a text that answers `⌊h / lineHeight⌋` lines
//   (L5/X9): the text is less flexible than a spacer, so it is served first
//   with its equal share, and keeps no more lines than that share holds.
// - Heights read half a point under whole lines (15.5, 31.5, 47.5): the
//   pixel-grid placement of divergence 77, not a different line count. A
//   MetalUI pin reads line counts, or whole-point heights, never these.

import AppKit
import SwiftUI

nonisolated(unsafe) var log: [String: String] = [:]

func fmt(_ v: CGFloat) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

struct Where: Layout {
    let key: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log[key] = "y=\(fmt(bounds.minY)) h=\(fmt(bounds.height))"
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
}

@MainActor func render(_ v: some View) {
    let r = ImageRenderer(content: v.background(Color.white))
    r.scale = 2
    _ = r.cgImage
}

let para = "The quick brown fox jumps over the lazy dog and keeps on running far away."

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    log = [:]
    render(Where(key: "k0") { Text(para) }.frame(width: 100, alignment: .topLeading).fixedSize(horizontal: false, vertical: true))
    print("K0 paragraph alone at width 100: \(log["k0"] ?? "-")")
    for h in [60.0, 100.0, 200.0] {
        log = [:]
        render(VStack(spacing: 0) {
            Where(key: "t") { Text(para) }
            Where(key: "s") { Spacer() }
        }.frame(width: 100, height: h))
        print("K1 VStack{Text; Spacer} h=\(fmt(h)): text \(log["t"] ?? "-") spacer \(log["s"] ?? "-")")
    }
    for h in [80.0, 200.0] {
        log = [:]
        render(VStack(spacing: 0) {
            Where(key: "t") { Text(para) }
            Where(key: "c") { Color.red.frame(height: 40) }
        }.frame(width: 100, height: h))
        print("K2 VStack{Text; Color h40} h=\(fmt(h)): text \(log["t"] ?? "-") colour \(log["c"] ?? "-")")
    }
    for h in [100.0, 300.0] {
        log = [:]
        render(VStack(spacing: 0) {
            Where(key: "a") { Text(para) }
            Where(key: "b") { Text(para) }
        }.frame(width: 100, height: h))
        print("K3 VStack{Text; Text} h=\(fmt(h)): a \(log["a"] ?? "-") b \(log["b"] ?? "-")")
    }
    for h in [60.0, 200.0] {
        log = [:]
        render(VStack(spacing: 0) {
            Where(key: "t") { Text(para) }
            Where(key: "s") { Spacer(minLength: 0) }
        }.frame(width: 100, height: h))
        print("K4 VStack{Text; Spacer(minLength: 0)} h=\(fmt(h)): text \(log["t"] ?? "-") spacer \(log["s"] ?? "-")")
    }
    print("done")
}
