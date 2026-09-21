// SwiftUI probe: which outer modifiers change LAYOUT, and what area does
// `.background` cover when the chain is written in different orders?
//
// Evidence for the outer-modifier matrix and the order-sensitive chains in
// docs/superpowers/specs/2026-09-15-outer-modifiers-design.md, rulings OM-A
// (paint-only vs wrapping), OM-C (legacy `.background` is the outermost
// layer's) and OM-H (order chains) in
// docs/superpowers/2026-09-15-outer-modifiers-decisions.md.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-outer-modifier-order.swift
//   xcrun swiftc docs/probes/swiftui-outer-modifier-order.swift -o /tmp/om-order && /tmp/om-order
//
// THE INSTRUMENT. The leaf is a fixed 20x20 `Color`; an `.overlay` of a
// `GeometryReader` records the leaf's frame in the root's named coordinate
// space (an overlay, not a background, so the `.background` under test stays
// free). The background under test is `BG`, a `GeometryReader` that records
// its OWN frame and paints red — so "bg" is literally the area SwiftUI gave
// the background view. The root is `.fixedSize()`, hosted in an
// `NSHostingView` sized to its `fittingSize`, which is the "outer" size.
//
// POSITIVE CONTROLS. C0/C1/C2: the bare leaf reads 20x20 at (0, 0); padding 8
// moves and grows it; a plain `.background` reads 20x20 at (0, 0), so the
// bg instrument reports a real rect that CAN move. L1 (padding) is the
// layout-neutrality section's positive control: it is the one modifier there
// whose outer size changes.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83). Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under `xcrun swiftc`
// (the same 6.4): byte-identical stdout, exit 0 both, compiled stderr empty.
//
//   --- controls
//     C0 bare leaf                     : outer 20x20 leaf (0, 0) 20x20 bg none
//     C1 .padding(8)                   : outer 36x36 leaf (8, 8) 20x20 bg none
//     C2 .background(BG)               : outer 20x20 leaf (0, 0) 20x20 bg (0, 0) 20x20
//   --- L: does the modifier change layout at all? (outer must stay 20x20 except C1)
//     L1 .padding(8) (control, moves)  : outer 36x36 leaf (8, 8) 20x20 bg none
//     L2 .border(green, width: 4)      : outer 20x20 leaf (0, 0) 20x20 bg none
//     L3 .opacity(0.5)                 : outer 20x20 leaf (0, 0) 20x20 bg none
//     L4 .clipShape(Rectangle())       : outer 20x20 leaf (0, 0) 20x20 bg none
//     L5 .cornerRadius(6)              : outer 20x20 leaf (0, 0) 20x20 bg none
//     L6 .allowsHitTesting(false)      : outer 20x20 leaf (0, 0) 20x20 bg none
//     L7 .contentShape(Rectangle())    : outer 20x20 leaf (0, 0) 20x20 bg none
//     L8 .focusable()                  : outer 20x20 leaf (0, 0) 20x20 bg none
//     L9 .overlay(Color.green)         : outer 20x20 leaf (0, 0) 20x20 bg none
//   --- A: padding x background
//     A1 .padding(8).background(BG)    : outer 36x36 leaf (8, 8) 20x20 bg (0, 0) 36x36
//     A2 .background(BG).padding(8)    : outer 36x36 leaf (8, 8) 20x20 bg (8, 8) 20x20
//     A3 .padding(8).background(BG).padding(4): outer 44x44 leaf (12, 12) 20x20 bg (4, 4) 36x36
//   --- B: frame x background
//     B1 .frame(60x60).background(BG)  : outer 60x60 leaf (20, 20) 20x20 bg (0, 0) 60x60
//     B2 .background(BG).frame(60x60)  : outer 60x60 leaf (20, 20) 20x20 bg (20, 20) 20x20
//   --- D: padding x frame x background (three-deep)
//     D1 .padding(8).frame(60x60).background(BG): outer 60x60 leaf (20, 20) 20x20 bg (0, 0) 60x60
//     D2 .background(BG).padding(8).frame(60x60): outer 60x60 leaf (20, 20) 20x20 bg (20, 20) 20x20
//   --- E: padding accumulates?
//     E1 .padding(4)                   : outer 28x28 leaf (4, 4) 20x20 bg none
//     E2 .padding(4).padding(4)        : outer 36x36 leaf (8, 8) 20x20 bg none
//     E3 .padding(8)                   : outer 36x36 leaf (8, 8) 20x20 bg none
//   --- F: clip x padding (what area survives a clip)
//     F1 big.frame(20x20)              : outer 20x20 leaf none bg none
//     F2 big.frame(20x20).clipped().padding(8): outer 36x36 leaf none bg none
//     F3 big.frame(20x20).padding(8).clipped(): outer 36x36 leaf none bg none
//
// WHAT IT SHOWS.
// - L2..L9: `.border`, `.opacity`, `.clipShape`, `.cornerRadius`,
//   `.allowsHitTesting`, `.contentShape`, `.focusable` and `.overlay` are all
//   LAYOUT-NEUTRAL: outer stays 20x20 where `.padding(8)` (L1) reads 36x36.
// - A1/A2 and B1/B2: `.background` covers the box AS IT STOOD AT THE POINT IN
//   THE CHAIN WHERE IT WAS WRITTEN — 36x36 at (0,0) after a padding, 20x20 at
//   (8,8) before one; 60x60 after a frame, 20x20 inside one.
// - E2 == E3: `.padding(4).padding(4)` equals `.padding(8)`. Padding
//   ACCUMULATES; it does not replace.
// - F2/F3: `.clipped()` is layout-neutral in both orders (36x36 either way);
//   what it cuts is a paint question this probe cannot see (see
//   `swiftui-border-clip-paint.swift`).

import AppKit
import SwiftUI

@MainActor var frames: [String: CGRect] = [:]

struct Leaf: View {
    var body: some View {
        Color.blue.frame(width: 20, height: 20)
            .overlay(GeometryReader { g in
                let r = g.frame(in: .named("root"))
                let _ = MainActor.assumeIsolated { frames["leaf"] = r }
                return Color.clear
            })
    }
}

/// The background under test: records the area SwiftUI hands it.
struct BG: View {
    var body: some View {
        GeometryReader { g in
            let r = g.frame(in: .named("root"))
            let _ = MainActor.assumeIsolated { frames["bg"] = r }
            return Color.red
        }
    }
}

@MainActor func measure<V: View>(_ view: V) -> (CGSize, CGRect, CGRect) {
    frames = [:]
    let root = view.fixedSize().coordinateSpace(name: "root")
    let host = NSHostingView(rootView: root)
    let fit = host.fittingSize
    host.frame = CGRect(origin: .zero, size: fit)
    host.layoutSubtreeIfNeeded()
    return (fit, frames["leaf"] ?? .null, frames["bg"] ?? .null)
}

func fmt(_ r: CGRect) -> String {
    r.isNull ? "none" : "(\(Int(r.minX)), \(Int(r.minY))) \(Int(r.width))x\(Int(r.height))"
}

@MainActor func arm<V: View>(_ label: String, _ view: V) {
    let (fit, leaf, bg) = measure(view)
    print("  \(label): outer \(Int(fit.width))x\(Int(fit.height)) leaf \(fmt(leaf)) bg \(fmt(bg))")
}

@MainActor func run() {
    print("--- controls")
    arm("C0 bare leaf                     ", Leaf())
    arm("C1 .padding(8)                   ", Leaf().padding(8))
    arm("C2 .background(BG)               ", Leaf().background(BG()))

    print("--- L: does the modifier change layout at all? (outer must stay 20x20 except C1)")
    arm("L1 .padding(8) (control, moves)  ", Leaf().padding(8))
    arm("L2 .border(green, width: 4)      ", Leaf().border(Color.green, width: 4))
    arm("L3 .opacity(0.5)                 ", Leaf().opacity(0.5))
    arm("L4 .clipShape(Rectangle())       ", Leaf().clipShape(Rectangle()))
    arm("L5 .cornerRadius(6)              ", Leaf().cornerRadius(6))
    arm("L6 .allowsHitTesting(false)      ", Leaf().allowsHitTesting(false))
    arm("L7 .contentShape(Rectangle())    ", Leaf().contentShape(Rectangle()))
    arm("L8 .focusable()                  ", Leaf().focusable())
    arm("L9 .overlay(Color.green)         ", Leaf().overlay(Color.green))

    print("--- A: padding x background")
    arm("A1 .padding(8).background(BG)    ", Leaf().padding(8).background(BG()))
    arm("A2 .background(BG).padding(8)    ", Leaf().background(BG()).padding(8))
    arm("A3 .padding(8).background(BG).padding(4)",
        Leaf().padding(8).background(BG()).padding(4))

    print("--- B: frame x background")
    arm("B1 .frame(60x60).background(BG)  ", Leaf().frame(width: 60, height: 60).background(BG()))
    arm("B2 .background(BG).frame(60x60)  ", Leaf().background(BG()).frame(width: 60, height: 60))

    print("--- D: padding x frame x background (three-deep)")
    arm("D1 .padding(8).frame(60x60).background(BG)",
        Leaf().padding(8).frame(width: 60, height: 60).background(BG()))
    arm("D2 .background(BG).padding(8).frame(60x60)",
        Leaf().background(BG()).padding(8).frame(width: 60, height: 60))

    print("--- E: padding accumulates?")
    arm("E1 .padding(4)                   ", Leaf().padding(4))
    arm("E2 .padding(4).padding(4)        ", Leaf().padding(4).padding(4))
    arm("E3 .padding(8)                   ", Leaf().padding(8))

    print("--- F: clip x padding (what area survives a clip)")
    // A 40x40 leaf inside a 20x20 frame: the frame is smaller than its
    // content, so `.clipped()` has something to cut.
    let big = Color.blue.frame(width: 40, height: 40)
    arm("F1 big.frame(20x20)              ", big.frame(width: 20, height: 20))
    arm("F2 big.frame(20x20).clipped().padding(8)",
        big.frame(width: 20, height: 20).clipped().padding(8))
    arm("F3 big.frame(20x20).padding(8).clipped()",
        big.frame(width: 20, height: 20).padding(8).clipped())
}

MainActor.assumeIsolated { run() }
