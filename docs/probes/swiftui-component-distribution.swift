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
// RE-RECORDED 2026-09-15 (design review round 2), macOS 26.6.2 (25G83), after
// critic findings 11 and 13. Two additive groups: G10–G12 (a CONTENT-SIZED
// `Text` body, which is the row the spec's §4.4 table claims and which `Solo`'s
// fixed 30x10 `Color` body does not exercise — the first recording cited G5/G6
// at `.padding(8)` under a row that said "a `Text` body, `.padding(20)`"), and
// G13–G16 (the declaration ORDER of two distributing modifiers, which OM-E
// asserted and no arm measured). Script form under /usr/bin/swift (Apple Swift
// 6.4, swiftlang-6.4.0.33.1) and compiled form under `xcrun swiftc` (the same
// 6.4): byte-identical stdout, exit 0 both, compiled stderr empty.
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
//   --- padding on a content-sized (Text) single-leaf custom view
//     G10 SoloText()                   : outer 13x16 a (0, 0) 13x16 b none bg none
//     G11 SoloText().padding(20)       : outer 53x56 a (20, 20) 13x16 b none bg none
//     G12 Solo().padding(20)           : outer 70x50 a (20, 20) 30x10 b none bg none
//   --- declaration ORDER of two modifiers on a custom view
//     G13 Pair().padding(4).frame(w:70): outer 148x18 a (20, 4) 30x10 b (88, 4) 50x10 bg none
//     G14 Pair().frame(w:70).padding(4): outer 164x18 a (24, 4) 30x10 b (100, 4) 50x10 bg none
//     G15 Solo().padding(4).frame(w:70): outer 70x18 a (20, 4) 30x10 b none bg none
//     G16 Solo().frame(w:70).padding(4): outer 78x18 a (24, 4) 30x10 b none bg none
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
// - **G10/G11: a CONTENT-SIZED (`Text`) body pads too** — 13x16 becomes 53x56,
//   the leaf at (20, 20). That is the same 13x16 a MetalUI `Text("Hi")`
//   measures on this machine, and the same 53 a MetalUI `.padding(20)` on the
//   ELEMENT path produces (record §15, scratch T1/T2), so SwiftUI and MetalUI's
//   element path agree exactly here and only the COMPONENT path (inert, marker
//   stays at 13) diverges. G12 is the fixed-size body at the same padding, for
//   comparison: 30x10 → 70x50.
// - **G13 vs G14, G15 vs G16: declaration ORDER is observable.** Padding-then-
//   frame reads 148x18 / 70x18 with the member centred at x 20; frame-then-
//   padding reads 164x18 / 78x18 with the member at x 24. OM-E's requirement
//   that a component's ops apply in declaration order has an arm at last. Note
//   what it does NOT show: SwiftUI's `.frame` WRAPS (the member keeps its own
//   30) where MetalUI's `Component.width` AMENDS (OM-F), so MetalUI reproduces
//   the ORDER-SENSITIVITY and not the member geometry — the lane-4 test pins
//   MetalUI's own numbers and names OM-F's divergence.

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

/// A custom view whose body is one `Text` — a CONTENT-SIZED leaf, not a leaf
/// with a declared frame. Added after the first recording: MetalUI's inertness
/// in this row comes specifically from the content-sized-measured-leaf box
/// model (CLAUDE.md's inert table), and `Solo` — whose body is a fixed 30x10
/// `Color` — does not exercise it. Its size is font- and machine-dependent, so
/// the recorded numbers are this machine's.
struct SoloText: View {
    var body: some View { Text("Hi").overlay(Probe(key: "a")) }
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

    // G10/G11: the CONTENT-SIZED leaf body, which is the row the spec's §4.4
    // table claims and which `Solo` (a fixed 30x10 `Color`) does not exercise.
    // G12 is `Solo` at the same padding, so the two rows are comparable.
    print("--- padding on a content-sized (Text) single-leaf custom view")
    arm("G10 SoloText()                   ") { SoloText() }
    arm("G11 SoloText().padding(20)       ") { SoloText().padding(20) }
    arm("G12 Solo().padding(20)           ") { Solo().padding(20) }

    // G13/G14: does the ORDER of two distributing modifiers matter on a custom
    // view? OM-E asserts it must, and asserted it from padding-accumulation
    // arms that cannot see it. This is the arm that can.
    print("--- declaration ORDER of two modifiers on a custom view")
    arm("G13 Pair().padding(4).frame(w:70)") { Pair().padding(4).frame(width: 70) }
    arm("G14 Pair().frame(w:70).padding(4)") { Pair().frame(width: 70).padding(4) }
    arm("G15 Solo().padding(4).frame(w:70)") { Solo().padding(4).frame(width: 70) }
    arm("G16 Solo().frame(w:70).padding(4)") { Solo().frame(width: 70).padding(4) }
}

MainActor.assumeIsolated { run() }
