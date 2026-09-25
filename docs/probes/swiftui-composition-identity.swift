// SwiftUI probe: composition and identity (plan task 8). Which structural
// changes keep a view's state, which create new state, whether two copies of
// one view VALUE share state, whether state works through `AnyView`, whether
// `.id()` on a container resets what is inside it, and what a modifier on a
// `Group` / multi-view custom view does to its members (overlay, background,
// frame in a vertical parent, frame over an EMPTY group).
//
// Evidence for rulings ID-A… in
// docs/superpowers/2026-09-25-composition-identity-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms):
//
//   /usr/bin/swift docs/probes/swiftui-composition-identity.swift
//   xcrun swiftc docs/probes/swiftui-composition-identity.swift -o /tmp/id-probe && /tmp/id-probe
//
// THE STATE INSTRUMENT (as in `swiftui-modifier-identity.swift`). `P` owns a
// `@StateObject Token`; `StateObject`'s autoclosure runs once per view
// identity, so a new serial means new state for that identity and the same
// serial across an update means the state was kept. Every `P` body logs its
// serial under its name, and every serial seen under a name is kept (a set),
// so a modifier that instantiates its content once PER MEMBER shows two
// serials under one name. Each arm hosts generation 0, then swaps `rootView`
// to generation 1 (and 2, for the three-generation arms) and lays out again.
//
// THE COUNTER INSTRUMENT (arms S*). `Counter` owns `@State var n = 0` and adds
// 1 to it from `.onAppear` — a closure the view registers, capturing the
// struct, exactly the shape of a MetalUI handler capturing `@State`. Its body
// logs `n`. Two occurrences with SEPARATE storage each read 1 after their own
// append; SHARED storage would read 2 in one of them.
//
// THE LAYOUT INSTRUMENT (arms L*). The arm's content is hosted in a `VStack`
// (spacing 0) or `HStack` (spacing 0), `.fixedSize()`, and
// `NSHostingView.fittingSize` is printed. The 30x10 / 50x10 members are
// `Color`s with fixed frames.
//
// POSITIVE CONTROLS. A0 (plain, input changes) must read "kept" and A1
// (`.id(generation)`) must read "NEW", or the instrument cannot see retention
// or re-creation. S0 (two DIFFERENT values) is the counter instrument's
// control for S1. L0 (the group with no frame) is the layout control for L1.
// Separating arms: V1's trailing view and X2's pair distinguish "kept own
// state" from "adopted the vanished/sibling view's state" by printing the
// other view's serial beside it.
//
// RECORDED 2026-09-25 by the plan task 8 design session, macOS 27.0 (26A428);
// revision 2 (the critic round, same day, same toolchain) added S5/S6 and
// L8-L10 and re-ran every earlier arm byte-identical.
// Script form under /usr/bin/swift and compiled form under `xcrun swiftc` (both
// Apple Swift 6.4, swiftlang-6.4.0.33.1) printed byte-identical stdout, exit
// status 0, stderr empty (0 lines) in both:
//
//   --- controls
//   A0 plain, input changes: p 1 / 1
//   A1 .id(generation): p 2 / 3
//   --- conditional content
//   V1 vanishing if, unnamed trailing sibling: c 4 / none, t 5 / 5
//   V2 appearing if, unnamed trailing sibling: c none / 7, t 6 / 6
//   V3 vanishing two-member if, trailing sibling: c1 8 / none, c2 9 / none, t 10 / 10
//   V4 if/else flip: a 11 / none, b none / 12
//   V5 if true, false, true (3 generations): c 13 / none / 15, t 14 / 14 / 14
//   V6 ForEach count 2 -> 1, trailing sibling: f0 16 / 16, f1 17 / none, t 18 / 18
//   V7 vanishing if inside a GridRow: c 19 / none, t 20 / 20
//   V8 vanishing GridRow, next row: r0 21 / none, r1 22 / 22
//   V9 if/else true, false, true (3 generations): a 23 / none / 25, b none / 24 / none
//   V10 ForEach count 2, 1, 2 (3 generations): f0 26 / 26 / 26, f1 27 / none / 28
//   --- explicit identity
//   X1 .id constant, input changes: p 29 / 29
//   X2 two siblings with the SAME .id: a 30 / 30, b 31 / 31
//   X3 named trailing sibling past a vanishing if: c 32 / none, t 33 / 33
//   X4 .id(generation) on an HStack resets its child: in 34 / 35
//   X5 .id(generation) on a Grid resets its cell: in 36 / 37
//   X6 .id(generation) on a custom view (Group body) resets both: a 38 / 40, b 39 / 41
//   X7 .id(generation) written INSIDE a padding: p 42 / 43
//   X8 .id(generation) on a vanishing-if's trailing sibling (control for X3): t 45 / 46
//   --- one value placed twice, and erasure
//   S0 two DIFFERENT Counter values (control): x 0+1, y 0+1
//   S1 one Counter VALUE placed twice: x 0+0+1+1
//   S2 Counter inside AnyView: x 0+1
//   S3 AnyView of the same type, input changes: e 47 / 47
//   S4 one P VALUE placed twice (serials): v 48+49 / 48+49
//   S5 one Stash VALUE placed twice, closures called outside dispatch: closures 2, call 0: x 1, call 1: x 1
//   S6 two DIFFERENT Stash values (control for S5): closures 2, call 0: x none y 1, call 1: x 1 y none
//   --- modifiers on a Group / multi-view custom view (state)
//   G1 Group{a;b}.overlay{o} as the ROOT: a 50 / 50, b 51 / 51, o 52 / 52
//   G2 Group{a;b}.background{k} as the ROOT: a 53 / 53, b 54 / 54, k 55 / 55
//   G3 HStack{ Group{a;b}.overlay{o} }: a 57 / 57, b 56 / 56, o 58+59 / 58+59
//   G4 VStack{ Group{a;b}.background{k} }: a 61 / 61, b 60 / 60, k 62+63 / 62+63
//   G5 HStack{ Group{a}.overlay{o} } (control: one member): a 64 / 64, o 65 / 65
//   G6 HStack{ HStack{a;b}.overlay{o} } (control: one container): o 68 / 68
//   G7 HStack{ Group{a;b}.onTapGesture{} } then a vanishing if before it: a 70 / 70, b 71 / 71
//   --- modifiers on a Group / multi-view custom view (layout)
//   L0 VStack{ Two() } (control): 50x20
//   L1 VStack{ Two().frame(width: 70) }: 70x20
//   L2 VStack{ Group{30x10;50x10}.frame(width: 70) }: 70x20
//   L3 HStack{ Two().frame(width: 70) }: 140x10
//   L4 VStack{ Two().frame(height: 20, alignment: .top) }: 50x40
//   L5 VStack{ 30x10; Group{ if false {..} }.frame(width: 70) }: 30x10
//   L6 VStack{ 30x10; EmptyView().frame(width: 70) } (control): 30x10
//   L7 VStack{ Two().padding(5) }: 60x40
//   L8 HStack{ TallPair().frame(width: 70, alignment: .top) }: 140x30, short minY 10, tall minY 0
//   L9 HStack{ TallPair() } (control): 80x30, short minY 10, tall minY 0
//   L10 HStack(alignment: .top){ TallPair() } (control: top is visible): 80x30, short minY 0, tall minY 0
//
// WHAT IT SHOWS, arm by arm (controls first):
//   A0/A1 the instrument sees retention (A0) and re-creation (A1).
//   V1-V3 an `if` with no `else` is ONE structural slot: when it vanishes (V1,
//         V3 with two members) or appears (V2) the trailing sibling KEEPS its
//         own state (t's serial unchanged) — it neither adopts the vanished
//         view's serial nor resets. The separating value is printed beside it:
//         V1's t keeps its own serial, not c's.
//   V4    an if/else flip creates new state for the new branch.
//   V5    content that vanishes and comes back gets NEW state: an
//         absent `if` does not retain its content's state.
//   V6    a ForEach whose count shrinks is one slot too: the trailing sibling
//         keeps its state.
//   V9    an if/else that flips away and back gives the first branch NEW
//         state on its return (V5's answer for the two-branch form).
//   V10   a ForEach element that is removed and comes back gets NEW state.
//   V7/V8 the same inside a `GridRow` and for a whole vanishing `GridRow`.
//   X1    a constant `.id` keeps state. X2: two siblings with the SAME `.id`
//         have DISTINCT state (two serials) — the explicit id is scoped to the
//         structural position. X3 (named) agrees with V1 (unnamed); X8, the
//         same trailing sibling with a CHANGING id, is its control (NEW).
//   X4-X6 `.id(generation)` on an HStack, a Grid and a Group resets what is
//         inside them. X7: an `.id` written inside a `.padding` still resets.
//   S0/S1 one `Counter` VALUE placed twice has separate storage per
//         occurrence: its four body reads are 0, 0, 1, 1 — shared storage would
//         read a 2 (each occurrence's `.onAppear` adds 1). S0 is the control.
//   S2/S3 `@State` works inside `AnyView` and is kept across an update when
//         the erased type is unchanged. S4: two serials for one value placed
//         twice, both kept.
//   G1/G2 at the ROOT (no parent stack) one overlay/background instance.
//   G3/G4 inside a stack, `.overlay`/`.background` on a two-member `Group`
//         instantiates its content once PER MEMBER (two serials), each kept.
//         G5 (one member, one serial) and G6 (a real container, one serial)
//         are the controls.
//   G7    `.onTapGesture` on a Group keeps its members' state past a vanishing
//         `if` before it.
//   L0/L1/L2 `.frame(width: 70)` on a two-member custom view or `Group` in a
//         VStack frames EACH member and the parent stacks them: 70x20 (L0, no
//         frame, is 50x20). L3: in an HStack (spacing 0) 140x10.
//   L4    `.frame(height: 20, alignment: .top)` per member: 50x40.
//   L5/L6 a `.frame` over an EMPTY group, like one over `EmptyView`, adds
//         nothing to its parent (30x10 = the sibling alone).
//   L7    `.padding(5)` per member: 60x40.
//   S5/S6 (revision 2, the critic round) a closure capturing `@State`, stored
//         from `.onAppear` and called DIRECTLY afterwards — outside any
//         SwiftUI dispatch — writes its OWN occurrence's storage: each call
//         re-renders exactly one body reading 1. Last-bound storage (MetalUI's
//         divergence 71) would read 2 on call 1; shared storage "1+1". S6 (two
//         different values) is the control: each call moves exactly one name.
//   L8-L10 (revision 2) `.frame(width: 70, alignment: .top)` per member of a
//         30x10 / 50x30 pair in an HStack: the short member sits at minY 10 —
//         the PARENT's centre alignment, not the frame's `.top` (a member's
//         frame is as tall as the member). L9 (no frame) reads the same 10;
//         L10 (`HStack(alignment: .top)`) reads 0, so the instrument can see
//         a top-aligned member.

import AppKit
import SwiftUI

@MainActor var nextSerial = 0
@MainActor var serials: [String: [Int]] = [:]
@MainActor var counts: [String: [Int]] = [:]

@MainActor final class Token: ObservableObject {
    let serial: Int
    init() { nextSerial += 1; serial = nextSerial }
}

struct P: View {
    let name: String
    let generation: Int
    init(_ name: String, _ generation: Int) { self.name = name; self.generation = generation }
    @StateObject private var token = Token()
    var body: some View {
        let _ = MainActor.assumeIsolated {
            if serials[name]?.contains(token.serial) != true {
                serials[name, default: []].append(token.serial)
            }
        }
        let _ = generation
        return Color.red.frame(width: 10, height: 10)
    }
}

struct Counter: View {
    let name: String
    @State private var n = 0
    var body: some View {
        let _ = MainActor.assumeIsolated { counts[name, default: []].append(n) }
        return Color.blue.frame(width: 10, height: 10).onAppear { n += 1 }
    }
}

/// Arm S5/S6: registers a closure capturing its `@State` from `.onAppear`;
/// the probe later calls the closures DIRECTLY, outside any SwiftUI
/// dispatch (the shape of a MetalUI closure run by a timer or a task).
@MainActor var stashed: [() -> Void] = []

struct Stash: View {
    let name: String
    @State private var n = 0
    var body: some View {
        let _ = MainActor.assumeIsolated { counts[name, default: []].append(n) }
        return Color.blue.frame(width: 10, height: 10)
            .onAppear { MainActor.assumeIsolated { stashed.append { n += 1 } } }
    }
}

/// Arm L8/L9: members of different heights, each recording its own minY in
/// the enclosing stack's coordinate space from a `GeometryReader` body.
@MainActor var minYs: [String: Int] = [:]

struct Tagged: View {
    let name: String
    let width: CGFloat
    let height: CGFloat
    var body: some View {
        Color.gray.frame(width: width, height: height).background(GeometryReader { g in
            let _ = MainActor.assumeIsolated { minYs[name] = Int(g.frame(in: .named("stack")).minY) }
            Color.clear
        })
    }
}

/// The `Component` analogue with members 30x10 and 50x30.
struct TallPair: View {
    var body: some View {
        Tagged(name: "short", width: 30, height: 10)
        Tagged(name: "tall", width: 50, height: 30)
    }
}

/// A custom view whose body is two views (the `Component` analogue).
struct Two: View {
    var body: some View {
        Color.blue.frame(width: 30, height: 10)
        Color.green.frame(width: 50, height: 10)
    }
}

func show(_ xs: [Int]?) -> String {
    guard let xs, !xs.isEmpty else { return "none" }
    return xs.map(String.init).joined(separator: "+")
}

/// Hosts each generation in turn and prints, per name, the serials seen in
/// each generation (`g0 / g1 / …`).
@MainActor func arm<V: View>(_ label: String, names: [String], generations: Int = 2,
                             _ make: @escaping (Int) -> V) {
    serials = [:]
    let host = NSHostingView(rootView: AnyView(make(0)))
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    host.layoutSubtreeIfNeeded()
    var perGen: [[String: [Int]]] = [serials]
    for g in 1..<generations {
        serials = [:]
        host.rootView = AnyView(make(g))
        host.layoutSubtreeIfNeeded()
        perGen.append(serials)
    }
    let rendered = names.map { n in "\(n) " + perGen.map { show($0[n]) }.joined(separator: " / ") }
    print(label, rendered.joined(separator: ", "))
}

@MainActor func counterArm<V: View>(_ label: String, names: [String], _ make: () -> V) {
    counts = [:]
    let host = NSHostingView(rootView: make())
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    host.layoutSubtreeIfNeeded()
    // Let `.onAppear` run and the state write re-render.
    for _ in 0..<5 {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
    }
    print(label, names.map { "\($0) \(show(counts[$0]))" }.joined(separator: ", "))
}

@MainActor func layoutArm<V: View>(_ label: String, vertical: Bool, @ViewBuilder _ content: () -> V) {
    let host: NSView
    if vertical {
        host = NSHostingView(rootView: VStack(spacing: 0) { content() }.fixedSize())
    } else {
        host = NSHostingView(rootView: HStack(spacing: 0) { content() }.fixedSize())
    }
    let fit = host.fittingSize
    print(label, "\(Int(fit.width))x\(Int(fit.height))")
}

/// Hosts `make()`, lets `.onAppear` run, then calls `stashed[0]` and
/// `stashed[1]` in turn, printing the body reads each call caused.
@MainActor func stashArm<V: View>(_ label: String, names: [String], _ make: () -> V) {
    counts = [:]
    stashed = []
    let host = NSHostingView(rootView: make())
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    host.layoutSubtreeIfNeeded()
    for _ in 0..<5 {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
    }
    var parts: [String] = ["closures \(stashed.count)"]
    for index in 0..<min(2, stashed.count) {
        counts = [:]
        stashed[index]()
        for _ in 0..<5 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            host.layoutSubtreeIfNeeded()
        }
        parts.append("call \(index): " + names.map { "\($0) \(show(counts[$0]))" }.joined(separator: " "))
    }
    print(label, parts.joined(separator: ", "))
}

@MainActor func positionArm<V: View>(_ label: String, @ViewBuilder _ content: () -> V) {
    minYs = [:]
    let host = NSHostingView(rootView: HStack(spacing: 0) { content() }
        .coordinateSpace(name: "stack").fixedSize())
    host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    host.layoutSubtreeIfNeeded()
    let fit = host.fittingSize
    print(label, "\(Int(fit.width))x\(Int(fit.height)),",
          "short minY \(minYs["short"].map(String.init) ?? "none"),",
          "tall minY \(minYs["tall"].map(String.init) ?? "none")")
}

@MainActor func run() {
    print("--- controls")
    arm("A0 plain, input changes:", names: ["p"]) { g in P("p", g) }
    arm("A1 .id(generation):", names: ["p"]) { g in P("p", g).id(g) }

    print("--- conditional content")
    arm("V1 vanishing if, unnamed trailing sibling:", names: ["c", "t"]) { g in
        HStack { if g == 0 { P("c", g) }; P("t", g) }
    }
    arm("V2 appearing if, unnamed trailing sibling:", names: ["c", "t"]) { g in
        HStack { if g == 1 { P("c", g) }; P("t", g) }
    }
    arm("V3 vanishing two-member if, trailing sibling:", names: ["c1", "c2", "t"]) { g in
        HStack { if g == 0 { P("c1", g); P("c2", g) }; P("t", g) }
    }
    arm("V4 if/else flip:", names: ["a", "b"]) { g in
        HStack { if g == 0 { P("a", g) } else { P("b", g) } }
    }
    arm("V5 if true, false, true (3 generations):", names: ["c", "t"], generations: 3) { g in
        HStack { if g != 1 { P("c", g) }; P("t", g) }
    }
    arm("V6 ForEach count 2 -> 1, trailing sibling:", names: ["f0", "f1", "t"]) { g in
        HStack { ForEach(0..<(g == 0 ? 2 : 1), id: \.self) { i in P("f\(i)", g) }; P("t", g) }
    }
    arm("V7 vanishing if inside a GridRow:", names: ["c", "t"]) { g in
        Grid { GridRow { if g == 0 { P("c", g) }; P("t", g) } }
    }
    arm("V8 vanishing GridRow, next row:", names: ["r0", "r1"]) { g in
        Grid { if g == 0 { GridRow { P("r0", g) } }; GridRow { P("r1", g) } }
    }
    arm("V9 if/else true, false, true (3 generations):", names: ["a", "b"], generations: 3) { g in
        HStack { if g != 1 { P("a", g) } else { P("b", g) } }
    }
    arm("V10 ForEach count 2, 1, 2 (3 generations):", names: ["f0", "f1"], generations: 3) { g in
        HStack { ForEach(0..<(g == 1 ? 1 : 2), id: \.self) { i in P("f\(i)", g) } }
    }

    print("--- explicit identity")
    arm("X1 .id constant, input changes:", names: ["p"]) { g in P("p", g).id("k") }
    arm("X2 two siblings with the SAME .id:", names: ["a", "b"]) { g in
        HStack { P("a", g).id("k"); P("b", g).id("k") }
    }
    arm("X3 named trailing sibling past a vanishing if:", names: ["c", "t"]) { g in
        HStack { if g == 0 { P("c", g) }; P("t", g).id("t") }
    }
    arm("X4 .id(generation) on an HStack resets its child:", names: ["in"]) { g in
        HStack { P("in", g) }.id(g)
    }
    arm("X5 .id(generation) on a Grid resets its cell:", names: ["in"]) { g in
        Grid { GridRow { P("in", g) } }.id(g)
    }
    arm("X6 .id(generation) on a custom view (Group body) resets both:", names: ["a", "b"]) { g in
        Group { P("a", g); P("b", g) }.id(g)
    }

    arm("X7 .id(generation) written INSIDE a padding:", names: ["p"]) { g in
        P("p", g).id(g).padding(4)
    }
    arm("X8 .id(generation) on a vanishing-if's trailing sibling (control for X3):", names: ["t"]) { g in
        HStack { if g == 0 { P("c", g) }; P("t", g).id(g) }
    }

    print("--- one value placed twice, and erasure")
    counterArm("S0 two DIFFERENT Counter values (control):", names: ["x", "y"]) {
        HStack { Counter(name: "x"); Counter(name: "y") }
    }
    counterArm("S1 one Counter VALUE placed twice:", names: ["x"]) {
        let c = Counter(name: "x")
        return HStack { c; c }
    }
    counterArm("S2 Counter inside AnyView:", names: ["x"]) {
        HStack { AnyView(Counter(name: "x")) }
    }
    arm("S3 AnyView of the same type, input changes:", names: ["e"]) { g in
        HStack { AnyView(P("e", g)) }
    }
    arm("S4 one P VALUE placed twice (serials):", names: ["v"]) { g in
        let p = P("v", g)
        return HStack { p; p }
    }

    stashArm("S5 one Stash VALUE placed twice, closures called outside dispatch:", names: ["x"]) {
        let s = Stash(name: "x")
        return HStack { s; s }
    }
    stashArm("S6 two DIFFERENT Stash values (control for S5):", names: ["x", "y"]) {
        HStack { Stash(name: "x"); Stash(name: "y") }
    }

    print("--- modifiers on a Group / multi-view custom view (state)")
    arm("G1 Group{a;b}.overlay{o} as the ROOT:", names: ["a", "b", "o"]) { g in
        Group { P("a", g); P("b", g) }.overlay { P("o", g) }
    }
    arm("G2 Group{a;b}.background{k} as the ROOT:", names: ["a", "b", "k"]) { g in
        Group { P("a", g); P("b", g) }.background { P("k", g) }
    }
    arm("G3 HStack{ Group{a;b}.overlay{o} }:", names: ["a", "b", "o"]) { g in
        HStack { Group { P("a", g); P("b", g) }.overlay { P("o", g) } }
    }
    arm("G4 VStack{ Group{a;b}.background{k} }:", names: ["a", "b", "k"]) { g in
        VStack { Group { P("a", g); P("b", g) }.background { P("k", g) } }
    }
    arm("G5 HStack{ Group{a}.overlay{o} } (control: one member):", names: ["a", "o"]) { g in
        HStack { Group { P("a", g) }.overlay { P("o", g) } }
    }
    arm("G6 HStack{ HStack{a;b}.overlay{o} } (control: one container):", names: ["o"]) { g in
        HStack { HStack { P("a", g); P("b", g) }.overlay { P("o", g) } }
    }
    arm("G7 HStack{ Group{a;b}.onTapGesture{} } then a vanishing if before it:",
        names: ["a", "b"]) { g in
        HStack { if g == 0 { P("c", g) }; Group { P("a", g); P("b", g) }.onTapGesture {} }
    }

    print("--- modifiers on a Group / multi-view custom view (layout)")
    layoutArm("L0 VStack{ Two() } (control):", vertical: true) { Two() }
    layoutArm("L1 VStack{ Two().frame(width: 70) }:", vertical: true) { Two().frame(width: 70) }
    layoutArm("L2 VStack{ Group{30x10;50x10}.frame(width: 70) }:", vertical: true) {
        Group { Color.blue.frame(width: 30, height: 10); Color.green.frame(width: 50, height: 10) }
            .frame(width: 70)
    }
    layoutArm("L3 HStack{ Two().frame(width: 70) }:", vertical: false) { Two().frame(width: 70) }
    layoutArm("L4 VStack{ Two().frame(height: 20, alignment: .top) }:", vertical: true) {
        Two().frame(height: 20, alignment: .top)
    }
    layoutArm("L5 VStack{ 30x10; Group{ if false {..} }.frame(width: 70) }:", vertical: true) {
        Color.blue.frame(width: 30, height: 10)
        Group { if nextSerial < 0 { Color.green.frame(width: 50, height: 10) } }.frame(width: 70)
    }
    layoutArm("L6 VStack{ 30x10; EmptyView().frame(width: 70) } (control):", vertical: true) {
        Color.blue.frame(width: 30, height: 10)
        EmptyView().frame(width: 70)
    }
    layoutArm("L7 VStack{ Two().padding(5) }:", vertical: true) { Two().padding(5) }
    positionArm("L8 HStack{ TallPair().frame(width: 70, alignment: .top) }:") {
        TallPair().frame(width: 70, alignment: .top)
    }
    positionArm("L9 HStack{ TallPair() } (control):") { TallPair() }
    positionArm("L10 HStack(alignment: .top){ TallPair() } (control: top is visible):") {
        HStack(alignment: .top, spacing: 0) { TallPair() }
    }
}

MainActor.assumeIsolated { run() }
