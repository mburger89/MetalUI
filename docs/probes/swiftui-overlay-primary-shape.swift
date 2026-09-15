// SwiftUI probe: does an overlay's state depend on how many views its PRIMARY
// contains, when a conditional inside the primary flips? Evidence for ruling
// MC-E as revised by the lane-1 critic (MC-P) in
// docs/superpowers/2026-09-15-modifier-composition-decisions.md. Written by the
// critic (arms A, B, P1-P4), extended by the designer with P5 and Q and with a
// raw evaluation count, then committed.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-overlay-primary-shape.swift
//   swiftc docs/probes/swiftui-overlay-primary-shape.swift -o /tmp/mc-overlay && /tmp/mc-overlay
//
// THE INSTRUMENT is swiftui-modifier-identity.swift's: `Probe` owns a
// `@StateObject Token` whose serial is minted once per view identity, and its
// body logs the serial. Each arm renders three generations, g0 flag TRUE, g1
// flag FALSE, g2 flag TRUE, and prints the DISTINCT serials each named probe
// logged per generation, then `n=` the number of body evaluations (so a
// modifier that silently duplicated the overlay, e.g. by distributing over a
// Group's children, would show two serials or be visible in the count).
//
// POSITIVE CONTROLS.
//   A   a plain probe, input changes: must read the SAME serial throughout.
//   B   `.id(generation)`: must read a NEW serial every generation.
//   P5  the primary's conditional holds a probe `c`: `c` must be present at g0,
//       ABSENT at g1 and NEW at g2 -- proof the flip really happened in the
//       primary and that the instrument sees it there.
//   Q   the overlay's OWN content flips if/else: `o` must read a new serial at
//       g1 and g2 -- proof the instrument sees a reset INSIDE an overlay, so
//       P1-P5's "kept" is not an overlay the instrument cannot see into.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83). Script form under /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1) and compiled form under swiftc
// (Apple Swift 6.3.3, swift-6.3.3-RELEASE) printed byte-identical stdout
// (`cmp`), exit status 0 each, empty stderr:
//
//   --- controls
//   A plain probe (kept expected): g0[p=[1] n=1] g1[p=[1] n=1] g2[p=[1] n=1]
//   B .id(g) (NEW expected): g0[p=[2] n=1] g1[p=[3] n=1] g2[p=[4] n=1]
//   --- overlay over a primary whose conditional flips
//   P1 ZStack{if; Color}.overlay: g0[o=[5] n=1] g1[o=[5] n=1] g2[o=[5] n=1]
//   P2 Group{if; Color}.overlay: g0[o=[6] n=1] g1[o=[6] n=1] g2[o=[6] n=1]
//   P3 multi-view body .overlay: g0[o=[7] n=1] g1[o=[7] n=1] g2[o=[7] n=1]
//   P4 Group{if EmptyView; Color}.overlay: g0[o=[8] n=1] g1[o=[8] n=1] g2[o=[8] n=1]
//   --- controls for the flip and for the overlay
//   P5 ZStack{if Probe c; Color}.overlay (c: present/ABSENT/NEW expected): g0[c=[9] n=1 o=[10] n=1] g1[c=[] n=0 o=[10] n=1] g2[c=[11] n=1 o=[10] n=1]
//   Q overlay's own if/else flips (o: NEW at g1 and g2 expected): g0[o=[12] n=1] g1[o=[13] n=1] g2[o=[14] n=1]
//
// The critic's own run (script form, same machine) printed A, B and P1-P4
// with the same serials, without the `n=` counts, before P5 and Q were added.
//
// WHAT IT SHOWS (controls first):
//   A/B   the instrument sees retention and re-creation.
//   P5    the primary's conditional really flips (c present, absent, new), and
//         the overlay o keeps serial 10 through it.
//   Q     a flip INSIDE the overlay is seen as new state (12, 13, 14), so the
//         overlay is not a place the instrument cannot see into.
//   P1-P4 SwiftUI keeps an overlay's state through a flip of its primary's
//         shape: a ZStack primary, a Group primary, a multi-view body, and a
//         Group whose conditional holds only EmptyView (the closest SwiftUI
//         shape to MetalUI's `{ if flag { EmptyProposalComponent() }; Rectangle }`).
//         Every n=1: no arm evaluated the overlay twice.
// So an overlay's identity does NOT depend on how many views (or indices) its
// primary consumed. MetalUI's threaded cursor (MC-E as first ruled, 6ff2d31)
// diverged from this; MC-P replaces it.
import AppKit
import SwiftUI

@MainActor var nextSerial = 0
@MainActor var log: [String: [Int]] = [:]

@MainActor final class Token: ObservableObject {
    let serial: Int
    init() { nextSerial += 1; serial = nextSerial }
}

struct Probe: View {
    let name: String
    let generation: Int
    @StateObject private var token = Token()
    var body: some View {
        let _ = MainActor.assumeIsolated { log[name, default: []].append(token.serial) }
        let _ = generation
        return Color.red.frame(width: 10, height: 10)
    }
}

struct MultiBody: View {
    let flag: Bool
    var body: some View {
        if flag { Color.blue.frame(width: 5, height: 5) }
        Color.green.frame(width: 60, height: 60)
    }
}

@MainActor func arm<V: View>(_ label: String, names: [String], _ make: @escaping (Int) -> V) {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    host.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    var readings: [String] = []
    for g in 0..<3 {
        log = [:]
        host.rootView = AnyView(make(g))
        host.layoutSubtreeIfNeeded()
        let r = names.map { n -> String in
            let all = log[n] ?? []
            return "\(n)=\(Set(all).sorted()) n=\(all.count)"
        }
        readings.append("g\(g)[\(r.joined(separator: " "))]")
    }
    print(label, readings.joined(separator: " "))
}

@MainActor func run() {
    // flag: g0 true, g1 false, g2 true
    func flag(_ g: Int) -> Bool { g != 1 }
    print("--- controls")
    arm("A plain probe (kept expected):", names: ["p"]) { g in Probe(name: "p", generation: g) }
    arm("B .id(g) (NEW expected):", names: ["p"]) { g in Probe(name: "p", generation: g).id(g) }
    print("--- overlay over a primary whose conditional flips")
    arm("P1 ZStack{if; Color}.overlay:", names: ["o"]) { g in
        ZStack {
            if flag(g) { Color.blue.frame(width: 5, height: 5) }
            Color.green.frame(width: 60, height: 60)
        }.overlay(alignment: .topLeading) { Probe(name: "o", generation: g) }
    }
    arm("P2 Group{if; Color}.overlay:", names: ["o"]) { g in
        Group {
            if flag(g) { Color.blue.frame(width: 5, height: 5) }
            Color.green.frame(width: 60, height: 60)
        }.overlay(alignment: .topLeading) { Probe(name: "o", generation: g) }
    }
    arm("P3 multi-view body .overlay:", names: ["o"]) { g in
        MultiBody(flag: flag(g)).overlay(alignment: .topLeading) { Probe(name: "o", generation: g) }
    }
    arm("P4 Group{if EmptyView; Color}.overlay:", names: ["o"]) { g in
        Group {
            if flag(g) { EmptyView() }
            Color.green.frame(width: 60, height: 60)
        }.overlay(alignment: .topLeading) { Probe(name: "o", generation: g) }
    }
    print("--- controls for the flip and for the overlay")
    arm("P5 ZStack{if Probe c; Color}.overlay (c: present/ABSENT/NEW expected):", names: ["c", "o"]) { g in
        ZStack {
            if flag(g) { Probe(name: "c", generation: g) }
            Color.green.frame(width: 60, height: 60)
        }.overlay(alignment: .topLeading) { Probe(name: "o", generation: g) }
    }
    arm("Q overlay's own if/else flips (o: NEW at g1 and g2 expected):", names: ["o"]) { g in
        Color.green.frame(width: 60, height: 60).overlay(alignment: .topLeading) {
            if flag(g) { Probe(name: "o", generation: g) } else { Probe(name: "o", generation: g) }
        }
    }
}
MainActor.assumeIsolated { run() }
