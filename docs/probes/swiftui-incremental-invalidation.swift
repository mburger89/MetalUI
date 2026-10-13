// SwiftUI probe: what a change re-evaluates and re-lays-out (C14, incremental
// invalidation; rulings IV-… in
// docs/superpowers/2026-10-13-incremental-invalidation-decisions.md).
//
// QUESTIONS.
// - R: a model change re-runs the body of exactly the views that READ the
//   changed property (siblings reading another property, and the parent, do
//   not).
// - S: a parent's @State change re-runs the parent body; a child whose stored
//   inputs are plain equal values is skipped, a child holding a closure is not
//   (SwiftUI's reflective input comparison).
// - T: a child's own @State change re-runs only that child (not its parent).
// - U: a reference-typed (non-Equatable class) input that did not change.
// - L: layout. A custom `Layout` wrapping each of N children counts its
//   `sizeThatFits`/`placeSubviews`. Changing one child's COLOUR (geometry
//   unchanged) vs one child's WIDTH: which wrappers re-measure?
//
// INSTRUMENTS. Hosted `NSHostingView` in an offscreen NSWindow; every body and
// every Layout method appends to a log; the probe drains the main run loop
// after each change and prints the log delta per arm.
//
// POSITIVE CONTROL. R0: the first render evaluates every body once (the log is
// not empty, the counting works). SEPARATING ARMS. R vs R-unread (changing a
// property nobody reads evaluates nothing); L-colour vs L-width.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-incremental-invalidation.swift -o /tmp/iv-probe && /tmp/iv-probe
//
// RECORDED and READING: the block at the end of this file.

import AppKit
import Observation
import SwiftUI

@MainActor func spin(_ s: Double = 0.4) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class Log: @unchecked Sendable {
    var lines: [String] = []
    func take() -> [String] { defer { lines = [] }; return lines }
}
let log = Log()

@Observable final class Model {
    var a = 0
    var b = 0
    var unread = 0
    var width: CGFloat = 40
}
final class Ref { var n = 0 }

struct ReadA: View {
    let model: Model
    var body: some View { let _ = log.lines.append("ReadA"); Text("a \(model.a)") }
}
struct ReadB: View {
    let model: Model
    var body: some View { let _ = log.lines.append("ReadB"); Text("b \(model.b)") }
}
struct Plain: View {
    let n: Int
    var body: some View { let _ = log.lines.append("Plain"); Text("p \(n)") }
}
struct WithClosure: View {
    let n: Int
    let f: () -> Void
    var body: some View { let _ = log.lines.append("WithClosure"); Text("c \(n)") }
}
struct PlainTick: View {
    let n: Int
    var body: some View { let _ = log.lines.append("PlainTick"); Text("pt \(n)") }
}
struct WithCapture: View {
    let f: () -> Void
    var body: some View { let _ = log.lines.append("WithCapture"); Text("cap") }
}
struct WithRef: View {
    let ref: Ref
    var body: some View { let _ = log.lines.append("WithRef"); Text("r") }
}
struct Own: View {
    @State var n = 0
    static var poke: (() -> Void)?
    var body: some View {
        let _ = log.lines.append("Own")
        let _ = { Own.poke = { n += 1 } }()
        Text("own \(n)")
    }
}
struct Top: View {
    let model: Model
    let ref: Ref
    var fresh = false
    @State var tick = 0
    static var bump: (() -> Void)?
    var body: some View {
        let _ = log.lines.append("Top")
        let _ = { Top.bump = { tick += 1 } }()
        VStack {
            Text("tick \(tick)")
            ReadA(model: model)
            ReadB(model: model)
            Plain(n: 1)
            WithClosure(n: 1, f: {})
            WithCapture(f: { _ = tick })
            PlainTick(n: tick)
            WithRef(ref: fresh ? Ref() : ref)
            Own()
        }
    }
}

struct Counting: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        log.lines.append("fit \(name)")
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        log.lines.append("place \(name)")
        subviews.first?.place(at: bounds.origin, proposal: proposal)
    }
}
struct Row: View {
    let model: Model
    let i: Int
    var body: some View {
        Counting(name: "c\(i)") {
            Rectangle().fill(i == 2 && model.a % 2 == 1 ? Color.red : Color.blue)
                .frame(width: i == 3 ? model.width : 40, height: 10)
        }
    }
}
struct Rows: View {
    let model: Model
    var body: some View { VStack(spacing: 0) { ForEach(0..<5) { Row(model: model, i: $0) } } }
}

@MainActor func host<V: View>(_ v: V) -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 300, height: 300),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.contentView = NSHostingView(rootView: v)
    w.orderFront(nil)
    return w
}
@MainActor func report(_ arm: String) {
    spin()
    // Counts per entry, in first-seen order: `Name xN`.
    var order: [String] = [], counts: [String: Int] = [:]
    for l in log.take() { if counts[l] == nil { order.append(l) }; counts[l, default: 0] += 1 }
    print("\(arm): \(order.map { "\($0) x\(counts[$0]!)" }.joined(separator: ", "))")
}

@MainActor func run() {
    let model = Model(), ref = Ref()
    let w1 = host(Top(model: model, ref: ref))
    report("R0 first render")
    model.unread += 1; report("R-unread (property nobody reads)")
    model.a += 1; report("R  (model.a)")
    model.b += 1; report("R  (model.b)")
    Top.bump?(); report("S  (Top @State)")
    Own.poke?(); report("T  (Own @State)")
    ref.n += 1; Top.bump?(); report("U  (Top @State; ref mutated, same instance)")
    w1.close()
    let w3 = host(Top(model: model, ref: ref, fresh: true))
    report("V0 first render, WithRef gets a NEW Ref instance every evaluation")
    Top.bump?(); report("V  (Top @State; WithRef input is a new instance each time)")
    w3.close()

    let m2 = Model()
    let w2 = host(Rows(model: m2))
    report("L0 first layout")
    m2.unread += 1; report("L-unread (property nobody reads)")
    m2.a += 1; report("L-colour (row 2 changes colour)")
    m2.width += 5; report("L-width (row 3 changes width)")
    w2.close()
}
MainActor.assumeIsolated { _ = NSApplication.shared; run() }

// RECORDED (macOS 27 arm64, 2026-10-13, hosted NSHostingView, `xcrun swiftc
// -swift-version 6`; each arm's log delta after a 0.4 s run-loop drain):
//
//   R0 first render: Top, ReadA, ReadB, Plain, WithClosure, WithCapture,
//      PlainTick, WithRef, Own — each x1                         (positive control)
//   R-unread (property nobody reads):                  (nothing evaluated)
//   R  (model.a): ReadA x1                    R  (model.b): ReadB x1
//   S  (Top @State, read by Top): Top, WithCapture, PlainTick x1 each
//        -- Plain(n: 1), WithClosure(n: 1, f: {}), ReadA/ReadB (same model
//        instance), WithRef (same Ref instance) and Own did NOT re-run
//   T  (Own @State): Own x1 only                (Top did not re-run)
//   U  (Top @State; a Ref's field mutated, same instance): as S
//   V  (WithRef given a NEW Ref instance each evaluation): WithRef re-ran
//   L0 first layout: each Counting layout fit x8..12, place x9..10
//   L-unread: nothing
//   L-colour (row 2: geometry unchanged): every row's wrapper re-measured and
//        re-placed (fit x6 per row, place x4..5): HALF of L0's counts, and NOT
//        confined to row 2
//   L-width (row 3 wider): fit x12 per row, place x9..10: L0's counts
//
// READING. (1) A change re-evaluates exactly the bodies that READ the changed
// observed property: R, T, and an unread property or an unread @State (the
// first run of S, before `tick` was read, ran nothing at all) evaluates
// nothing. (2) A parent's re-evaluation skips a child whose stored inputs
// compare equal (plain values, class references by identity, a non-capturing
// closure) and re-runs one whose input changed (PlainTick: Int differs; V: a
// new reference; WithCapture: a capturing closure is never equal): SwiftUI
// compares a child's inputs reflectively (S, U, V). (3) Layout is NOT
// incremental at this granularity for a custom `Layout`: a colour change that
// moves nothing still re-measured every sibling wrapper (L-colour, half the
// first layout's passes), and a width change re-measured them at the full
// count. So "re-measure only dirty paths" is the goal of the item, not what
// SwiftUI does for a custom Layout; MetalUI's cache work is its own design
// (IV-D), not a parity claim. Not probed: built-in stacks' internal caching
// (opaque to a counter), which is why L uses custom Layouts.
