// SwiftUI probe: does the ORDER of `.padding` and `.frame` change a wrapped
// view's size and placement, and by how much? Evidence for ruling MC-L's
// "frame ordering" row and spec lane 1 test 10 in
// docs/superpowers/2026-09-15-modifier-composition-decisions.md (design-review
// finding 10, ruling MC-N).
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-modifier-order.swift
//   swiftc docs/probes/swiftui-modifier-order.swift -o /tmp/mc-order && /tmp/mc-order
//
// THE INSTRUMENT. The leaf is a fixed 20x20 `Color`; a `GeometryReader` in its
// background records its frame in the root's named coordinate space. The root
// is `.fixedSize()`, hosted in an `NSHostingView` sized to its `fittingSize`,
// which is the "outer" size printed.
//
// POSITIVE CONTROLS. K0-K2: the bare leaf reads 20x20 at (0, 0), and padding 8
// and 16 read different outer sizes and origins, so the instrument sees both a
// size change and an offset change.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83). Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under swiftc
// (Apple Swift 6.3.3, swift-6.3.3-RELEASE): byte-identical stdout, exit 0 both,
// stderr empty in the compiled run:
//
//   --- controls
//   K0 bare 20x20 leaf: outer 20x20 leaf origin (0, 0) size 20x20
//   K1 padding 8: outer 36x36 leaf origin (8, 8) size 20x20
//   K2 padding 16: outer 52x52 leaf origin (16, 16) size 20x20
//   --- order
//   O1 padding(8) then frame(60x60): outer 60x60 leaf origin (20, 20) size 20x20
//   O2 frame(60x60) then padding(8): outer 76x76 leaf origin (28, 28) size 20x20
//   O3 padding(4).frame(40x40).padding(8): outer 56x56 leaf origin (18, 18) size 20x20
//   O4 frame(40x40).padding(4).padding(8): outer 64x64 leaf origin (22, 22) size 20x20
//
// WHAT IT SHOWS. Order changes both outer size and placement: O1/O2 and O3/O4
// hold the same modifiers in different orders and disagree.
//
// METALUI AT f64e58a, measured the same session by an uncommitted scratch test
// (`zzScratchLegacyModifierOrder`, `--filter`, deleted): a legacy
// `StyledElement` leaf declaring 20x20, the same seven chains through today's
// `Box<Self>` / `FrameModifier<Self>`, outer width read from a 1pt sibling in a
// `Row` and outer height from one in a `Column`, both `.alignItems(.flexStart)`:
//   K0 20x20 (0, 0)   K1 36x36 (8, 8)   K2 52x52 (16, 16)
//   O1 60x60 (20, 20) O2 76x76 (28, 28) O3 56x56 (18, 18) O4 64x64 (22, 22)
// All seven agree with SwiftUI. The claim is for a FIXED-SIZE leaf only: a
// flexible SwiftUI view (a bare `Color`) fills a frame, and the legacy engine's
// sizing of an undeclared leaf is task 4's.

import AppKit
import SwiftUI

@MainActor var frames: [String: CGRect] = [:]

struct Leaf: View {
    let name: String
    var body: some View {
        Color.red.frame(width: 20, height: 20)
            .background(GeometryReader { g in
                let r = g.frame(in: .named("root"))
                let _ = MainActor.assumeIsolated { frames[name] = r }
                return Color.clear
            })
    }
}

@MainActor func arm<V: View>(_ label: String, _ view: V) {
    frames = [:]
    let root = view.fixedSize().coordinateSpace(name: "root")
    let host = NSHostingView(rootView: root)
    let fit = host.fittingSize
    host.frame = CGRect(origin: .zero, size: fit)
    host.layoutSubtreeIfNeeded()
    let leaf = frames["leaf"] ?? .null
    print(label, "outer \(Int(fit.width))x\(Int(fit.height))", "leaf origin (\(Int(leaf.minX)), \(Int(leaf.minY))) size \(Int(leaf.width))x\(Int(leaf.height))")
}

@MainActor func run() {
    print("--- controls")
    arm("K0 bare 20x20 leaf:", Leaf(name: "leaf"))
    arm("K1 padding 8:", Leaf(name: "leaf").padding(8))
    arm("K2 padding 16:", Leaf(name: "leaf").padding(16))
    print("--- order")
    arm("O1 padding(8) then frame(60x60):", Leaf(name: "leaf").padding(8).frame(width: 60, height: 60))
    arm("O2 frame(60x60) then padding(8):", Leaf(name: "leaf").frame(width: 60, height: 60).padding(8))
    arm("O3 padding(4).frame(40x40).padding(8):", Leaf(name: "leaf").padding(4).frame(width: 40, height: 40).padding(8))
    arm("O4 frame(40x40).padding(4).padding(8):", Leaf(name: "leaf").frame(width: 40, height: 40).padding(4).padding(8))
}
MainActor.assumeIsolated { run() }
