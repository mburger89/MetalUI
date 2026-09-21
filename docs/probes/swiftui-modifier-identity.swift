// SwiftUI probe: which modifier changes keep a wrapped view's state, and
// whether an overlay's (or background's) view shares state with its primary.
// Evidence for rulings MC-A (arm T: SwiftUI's chain type nests), MC-C (arms
// C, D1-D3: which chain changes keep state) and MC-E (arms E-H: overlay and
// background identity) in
// docs/superpowers/2026-09-15-modifier-composition-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms; both were run):
//
//   /usr/bin/swift docs/probes/swiftui-modifier-identity.swift
//   swiftc docs/probes/swiftui-modifier-identity.swift -o /tmp/mc-identity && /tmp/mc-identity
//
// THE INSTRUMENT. `Probe` owns a `@StateObject Token`. `StateObject`'s
// initializer is an autoclosure evaluated ONCE per view identity, so a new
// `Token` serial means SwiftUI created new state for that position, and the
// same serial across an update means it kept the state. Every `Probe` body
// logs its token's serial; each arm hosts a root, reads the log, swaps
// `rootView` for the next generation, lays out again and reads again.
//
// POSITIVE CONTROLS. Arm B (`.id(generation)`) must show a NEW serial after the
// update, or the instrument cannot see re-creation. Arm A must show the SAME
// serial, or the instrument cannot see retention. Arm H is the control for
// arm E's "distinct": two siblings in an HStack, known to be two identities.
//
// RECORDED 2026-09-15 by the modifier-composition design session, macOS 26.6.2
// (25G83). Script form under /usr/bin/swift (Apple Swift 6.4,
// swiftlang-6.4.0.33.1) and compiled form under swiftc (Apple Swift 6.3.3,
// swift-6.3.3-RELEASE) printed byte-identical stdout, exit status 0:
//
//   --- T: the static type of a two-modifier chain
//   T ModifiedContent<ModifiedContent<Color, _PaddingLayout>, _PaddingLayout>
//   --- controls
//   A plain probe, input changes: p 1->1 | kept
//   B control .id(generation): p 2->3 | NEW
//   --- chained modifiers
//   C chain, every VALUE changes: p 4->4 | kept
//   D1 chain LENGTH changes via if/else: p 5->6 | NEW
//   D2 same modifier count, value-only (padding 0 then 8): p 7->7 | kept
//   D3 AnyView erases a chain whose LENGTH changes: p 8->9 | NEW
//   --- attachments
//   E overlay, stateful on both sides: primary 10->10, overlay 11->11 | kept, kept
//   F background, stateful on both sides: primary 12->12, background 13->13 | kept, kept
//   G overlay with a multi-view primary side: a 14->14, b 15->15, overlay 16->16 | kept, kept, kept
//   H control, two HStack siblings: left 17->17, right 18->18 | kept, kept
//
// WHAT IT SHOWS, arm by arm (read with the controls first):
//   T   SwiftUI's chain type NESTS: two paddings are two ModifiedContent levels.
//   A/B the instrument sees both retention (A) and re-creation (B).
//   C   changing every modifier's VALUE in a three-modifier chain keeps state.
//   D1  changing the chain's LENGTH through if/else creates new state.
//   D2  a modifier whose value goes 0 -> 8 (count unchanged) keeps state.
//   D3  the same length change behind AnyView also creates new state: the
//       reset follows the structure, not the if/else.
//   E/F an overlay's (background's) view has its OWN state, distinct from the
//       primary's, and both keep it across an update.
//   G   the same with a two-view primary side.
//   H   control for "distinct": two HStack siblings.
// No arm can show SHARED state, because SwiftUI never shares it here; the
// instrument's ability to report "same" is arm A's, across time.
//
// stderr was empty in the compiled run (0 lines); stdout above is all of it.

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

/// Runs `make(0)`, then `make(1)`, and prints each named probe's serials:
/// the first serial seen at generation 0 and the last seen at generation 1.
@MainActor func arm<V: View>(_ label: String, names: [String], _ make: @escaping (Int) -> V) {
    log = [:]
    let host = NSHostingView(rootView: AnyView(make(0)))
    host.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
    host.layoutSubtreeIfNeeded()
    let before = names.map { log[$0]?.last ?? -1 }
    log = [:]
    host.rootView = AnyView(make(1))
    host.layoutSubtreeIfNeeded()
    let after = names.map { log[$0]?.last ?? -1 }
    let rendered = zip(names, zip(before, after)).map { "\($0.0) \($0.1.0)->\($0.1.1)" }
    let kept = zip(before, after).map { $0 == $1 ? "kept" : "NEW" }
    print(label, rendered.joined(separator: ", "), "|", kept.joined(separator: ", "))
}

@MainActor func run() {
    print("--- T: the static type of a two-modifier chain")
    print("T", String(describing: type(of: Color.red.padding(4).padding(8))))
    print("--- controls")
    arm("A plain probe, input changes:", names: ["p"]) { g in
        Probe(name: "p", generation: g)
    }
    arm("B control .id(generation):", names: ["p"]) { g in
        Probe(name: "p", generation: g).id(g)
    }
    print("--- chained modifiers")
    arm("C chain, every VALUE changes:", names: ["p"]) { g in
        Probe(name: "p", generation: g)
            .padding(g == 0 ? 4 : 8)
            .frame(width: g == 0 ? 100 : 120, height: 50)
            .padding(g == 0 ? 2 : 6)
    }
    arm("D1 chain LENGTH changes via if/else:", names: ["p"]) { g in
        Group {
            if g == 0 {
                Probe(name: "p", generation: g).padding(4)
            } else {
                Probe(name: "p", generation: g).padding(4).padding(8)
            }
        }
    }
    arm("D2 same modifier count, value-only (padding 0 then 8):", names: ["p"]) { g in
        Probe(name: "p", generation: g).padding(g == 0 ? 0 : 8).padding(4)
    }
    arm("D3 AnyView erases a chain whose LENGTH changes:", names: ["p"]) { g in
        g == 0 ? AnyView(Probe(name: "p", generation: g).padding(4))
               : AnyView(Probe(name: "p", generation: g).padding(4).padding(8))
    }
    print("--- attachments")
    arm("E overlay, stateful on both sides:", names: ["primary", "overlay"]) { g in
        Probe(name: "primary", generation: g)
            .overlay { Probe(name: "overlay", generation: g) }
    }
    arm("F background, stateful on both sides:", names: ["primary", "background"]) { g in
        Probe(name: "primary", generation: g)
            .background { Probe(name: "background", generation: g) }
    }
    arm("G overlay with a multi-view primary side:", names: ["a", "b", "overlay"]) { g in
        HStack { Probe(name: "a", generation: g); Probe(name: "b", generation: g) }
            .overlay { Probe(name: "overlay", generation: g) }
    }
    arm("H control, two HStack siblings:", names: ["left", "right"]) { g in
        HStack { Probe(name: "left", generation: g); Probe(name: "right", generation: g) }
    }
}

MainActor.assumeIsolated { run() }
