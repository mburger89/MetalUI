// SwiftUI probe: what does a modifier on a CUSTOM VIEW whose body is several
// views actually do — wrap the group, or apply to each member? And what does
// it do when the body is a single leaf?
//
// Evidence for rulings OM-D (`.padding` on a `Component` wraps each top-level
// node rather than amending its style), OM-E (chained padding accumulates) and
// OM-F (the `.frame`/`.width` divergence stays, task 4's) in
// docs/superpowers/2026-09-15-outer-modifiers-decisions.md. It re-measures the
// `Component` milestone's CO-U claim (`Component.swift`'s own doc: 120x26)
// from source, in this session, rather than citing it.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-component-distribution.swift
//   xcrun swiftc docs/probes/swiftui-component-distribution.swift -o /tmp/om-dist && /tmp/om-dist
//
// THE INSTRUMENT. `Pair` is a custom `View` whose body is two views (a
// `TupleView`): a 30x10 and a 50x10 `Color`. `Solo`'s body is one 30x10
// `Color`. Each member carries an `.overlay(GeometryReader)` recording its
// frame in the root coordinate space; every recorded frame is appended to a
// list, so a modifier that produces TWO background views is visible as two
// entries. The arm is hosted inside an `HStack` (default spacing 8) because a
// `TupleView` needs a container to be laid out at all; the `HStack` is sized
// by `.fixedSize()` and `NSHostingView.fittingSize`.
//
// POSITIVE CONTROLS. G0 (an inline pair) and G1 (`Pair()`) must read the same
// outer size — that is the layout-transparency control, and it is what makes a
// later arm's difference attributable to the modifier. C2 shows the bg
// instrument recording exactly one rect when one background is applied to one
// leaf.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83). Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under `xcrun swiftc`
// (the same 6.4): byte-identical stdout, exit 0 both, compiled stderr empty.
//
//   --- controls
//     G0 inline pair A(); B() (control): outer 88x10 a (0, 0) 30x10 b (38, 0) 50x10 bg none
//     G1 Pair()                        : outer 88x10 a (0, 0) 30x10 b (38, 0) 50x10 bg none
//     C2 A().background(BG)            : outer 30x10 a (0, 0) 30x10 b none bg (0, 0) 30x10
//   --- padding on a multi-view custom view
//     G2 Pair().padding(8)             : outer 120x26 a (8, 8) 30x10 b (62, 8) 50x10 bg none
//     G3 Group { A(); B() }.padding(8) : outer 120x26 a (8, 8) 30x10 b (62, 8) 50x10 bg none
//     G4 Pair().padding(4).padding(4)  : outer 120x26 a (8, 8) 30x10 b (62, 8) 50x10 bg none
//   --- padding on a single-leaf custom view
//     G5 Solo()                        : outer 30x10 a (0, 0) 30x10 b none bg none
//     G6 Solo().padding(8)             : outer 46x26 a (8, 8) 30x10 b none bg none
//   --- frame on a custom view
//     G7 Pair().frame(width: 70)       : outer 148x10 a (20, 0) 30x10 b (88, 0) 50x10 bg none
//     G8 Solo().frame(width: 70)       : outer 70x10 a (20, 0) 30x10 b none bg none
//   --- background on a multi-view custom view
//     G9 Pair().background(BG)         : outer 88x10 a (0, 0) 30x10 b (38, 0) 50x10 bg (38, 0) 50x10 + (0, 0) 30x10
//
// WHAT IT SHOWS.
// - G0 == G1 (88x10): a custom view whose body is two views contributes no
//   container — the transparency control.
// - G2 == G3 (120x26 = (30+16) + 8 + (50+16)): `.padding(8)` on it is applied
//   to EACH member, exactly as on a `Group`. This re-measures CO-U's figure.
// - G4 == G2: `.padding(4).padding(4)` equals `.padding(8)` — per member, the
//   two paddings ACCUMULATE.
// - G6: a SINGLE-LEAF custom view pads too (46x26 from 30x10), which is what
//   MetalUI's `Style.padding` distribution cannot do on a content-sized leaf.
// - G7/G8: `.frame(width: 70)` WRAPS each member — the members keep their own
//   30 and 50 widths and are CENTRED in 70 (a at x=20 of 0..70) — where
//   MetalUI's `StyledComponent` overwrites the member's own width.
// - G9: `.background` produces TWO background views, one per member.

import AppKit
import SwiftUI

@MainActor var recorded: [String: [CGRect]] = [:]

@MainActor func record(_ key: String, _ r: CGRect) { recorded[key, default: []].append(r) }

struct Probe: View {
    let key: String
    var body: some View {
        GeometryReader { g in
            let r = g.frame(in: .named("root"))
            let _ = MainActor.assumeIsolated { record(key, r) }
            return Color.clear
        }
    }
}

struct BG: View {
    var body: some View {
        GeometryReader { g in
            let r = g.frame(in: .named("root"))
            let _ = MainActor.assumeIsolated { record("bg", r) }
            return Color.red
        }
    }
}

struct A: View {
    var body: some View { Color.blue.frame(width: 30, height: 10).overlay(Probe(key: "a")) }
}

struct B: View {
    var body: some View { Color.green.frame(width: 50, height: 10).overlay(Probe(key: "b")) }
}

/// A custom view whose body is TWO views.
struct Pair: View {
    var body: some View {
        A()
        B()
    }
}

/// A custom view whose body is ONE leaf.
struct Solo: View {
    var body: some View { A() }
}

func fmt(_ rs: [CGRect]) -> String {
    rs.isEmpty ? "none"
        : rs.map { "(\(Int($0.minX)), \(Int($0.minY))) \(Int($0.width))x\(Int($0.height))" }
            .joined(separator: " + ")
}

@MainActor func arm<V: View>(_ label: String, @ViewBuilder _ content: () -> V) {
    recorded = [:]
    let root = HStack { content() }.fixedSize().coordinateSpace(name: "root")
    let host = NSHostingView(rootView: root)
    let fit = host.fittingSize
    host.frame = CGRect(origin: .zero, size: fit)
    host.layoutSubtreeIfNeeded()
    print("  \(label): outer \(Int(fit.width))x\(Int(fit.height))",
          "a \(fmt(recorded["a"] ?? []))", "b \(fmt(recorded["b"] ?? []))",
          "bg \(fmt(recorded["bg"] ?? []))")
}

@MainActor func run() {
    print("--- controls")
    arm("G0 inline pair A(); B() (control)") { A(); B() }
    arm("G1 Pair()                        ") { Pair() }
    arm("C2 A().background(BG)            ") { A().background(BG()) }

    print("--- padding on a multi-view custom view")
    arm("G2 Pair().padding(8)             ") { Pair().padding(8) }
    arm("G3 Group { A(); B() }.padding(8) ") { Group { A(); B() }.padding(8) }
    arm("G4 Pair().padding(4).padding(4)  ") { Pair().padding(4).padding(4) }

    print("--- padding on a single-leaf custom view")
    arm("G5 Solo()                        ") { Solo() }
    arm("G6 Solo().padding(8)             ") { Solo().padding(8) }

    print("--- frame on a custom view")
    arm("G7 Pair().frame(width: 70)       ") { Pair().frame(width: 70) }
    arm("G8 Solo().frame(width: 70)       ") { Solo().frame(width: 70) }

    print("--- background on a multi-view custom view")
    arm("G9 Pair().background(BG)         ") { Pair().background(BG()) }
}

MainActor.assumeIsolated { run() }
