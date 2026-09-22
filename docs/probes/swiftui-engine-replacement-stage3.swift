// SwiftUI probe: plan task 7, engine replacement **stage 3** — scrolling and
// `Component` distribution.
//
// Evidence for rulings `LR-BB`… in
// docs/superpowers/2026-09-17-engine-replacement-decisions.md, cited as the
// *stage-3 probe*. It answers the two questions no existing arm answers:
//
//   1. **Is a SwiftUI `ScrollView` FLEXIBLE inside a stack?** — i.e. does it
//      take the remaining main space the way a greedy frame does, or does it
//      hug its content the way MetalUI's legacy viewport node does? (Group V.)
//      The existing `swiftui-stack-algorithms.swift` arms SC1–SC5/SCG2 measure
//      a `ScrollView` at an EXPLICIT proposal; none puts one in a stack.
//   2. **What does a `.frame` with a MAXIMUM, or one axis only, do to a
//      multi-member custom view?** (Group W.) `swiftui-component-distribution.swift`
//      G7/G8/G13–G16 measure a FIXED `.frame(width:)`; nothing measures a
//      flexible one, and stage 3 lowers `Component.width`/`.height` and a
//      `.frame` layer over several member nodes.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-engine-replacement-stage3.swift
//   xcrun swiftc docs/probes/swiftui-engine-replacement-stage3.swift -o /tmp/s3 && /tmp/s3
//
// THE INSTRUMENT. Every arm is hosted in an `NSHostingView` sized by an outer
// `.frame(width:height:)`, and every measured view carries an
// `.overlay(GeometryReader)` that records its frame in the host's coordinate
// space. So each line reads "outer WxH" followed by the recorded members.
//
// POSITIVE CONTROLS.
//   - V0 — a `VStack` of two fixed colours in a 200pt-tall host: the stack's
//     children are at their own heights and the stack does NOT fill. That is
//     what makes V1's filling attributable to the `ScrollView`.
//   - V2 — `Color` (maximally flexible) in the same shape, the known-greedy
//     reference V1 is compared against.
//   - W0 — `Pair()` bare, the layout-transparency control (== G1 of the
//     component-distribution probe).
//
// RECORDED OUTPUT, 2026-09-22 (PDT), macOS 27.0 (26A428), /usr/bin/swift
// (Apple Swift 6.4, swiftlang-6.4.0.33.1). Run twice under the script form,
// byte-identical; `xcrun swiftc -O` produced the same 15 lines, exit 0, empty
// stderr in both forms. (`b none` on a ScrollView arm is the instrument saying
// that arm has no `b` member, not a missing measurement.)
//
//   --- V: is a ScrollView flexible inside a stack? (host 100x200)
//     V0 control VStack{a 60x30; b 60x30}         : outer 100x200 a (20, 66) 60x30 b (20, 104) 60x30
//     V1 VStack{a 60x30; ScrollView{c 60x300}}    : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 c (20, 38) 60x300 b none
//     V2 control VStack{a 60x30; Color 60 wide}   : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 b none
//     V3 VStack{a 60x30; ScrollView{c 60x20}}     : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 c (20, 38) 60x20 b none
//     V4 HStack{a 30x60; ScrollView(.h){c 300x60}}: outer 100x200 a (0, 70) 30x60 sv (38, 70) 62x60 c (38, 70) 300x60 b none
//     V5 VStack{a 60x30; ScrollView{c 60x300}.fixedSize()}: outer 100x200 a (20, -69) 60x30 sv (20, -31) 60x300 c (20, -31) 60x300 b none
//   --- W: a flexible or single-axis frame on a multi-member custom view (host 300x100)
//     W0 control Pair()                           : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
//     W1 Pair().frame(width: 70)                  : outer 300x100 a (96, 45) 30x10 b (164, 45) 50x10
//     W2 Pair().frame(height: 40)                 : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
//     W3 Pair().frame(maxWidth: .infinity)        : outer 300x100 a (58, 45) 30x10 b (202, 45) 50x10
//     W4 Pair().frame(width: 70, height: 40)      : outer 300x100 a (96, 45) 30x10 b (164, 45) 50x10
//     W5 Solo().frame(height: 40)                 : outer 300x100 a (135, 45) 30x10 b none
//     W6 Pair().frame(maxWidth: .infinity, alignment: .leading): outer 300x100 a (0, 45) 30x10 b (154, 45) 50x10
//
// WHAT IT SHOWS.
//
// - **V1 vs V0: a SwiftUI `ScrollView` IS flexible inside a stack.** V0's
//   stack hugs — its two 30pt children form a 68pt block centred in the 200pt
//   host (a at y 66) — so the stack is not filling by itself. In V1 the
//   `ScrollView` takes every point the fixed sibling and the 8pt default
//   spacing leave, 200 - 30 - 8 = **162**, and V2 shows a maximally flexible
//   `Color` in the same shape taking exactly the same 162. So on its scrolling
//   axis a `ScrollView` answers its proposal, as `.frame(maxHeight: .infinity)`
//   would; it never hugs its content there.
// - **V3: it fills even when its CONTENT is shorter than the viewport** — a
//   20pt child still leaves a 162pt viewport — and the content sits at the
//   viewport's leading edge (y 38, the viewport's own origin), not centred.
//   That is `SCG2`'s placement rule seen inside a stack.
// - **V4: the horizontal axis behaves identically** — the scroller takes
//   100 - 30 - 8 = 62 and its 300pt content overflows it.
// - **V5: `.fixedSize()` DOES opt out of it, so the flexibility is a response
//   to the proposal rather than a fixed answer.** With `.fixedSize()` the
//   viewport becomes its content's own 300 and the 338pt stack overflows the
//   200pt host (a at y **-69**). So a `ScrollView`'s IDEAL on its scrolling
//   axis is its content's size — which is also what `stack-algorithms` SC1
//   reads at a nil proposal (50x300) — and what it answers at a concrete
//   proposal is the proposal.
// - **W1/W4: a fixed `.frame` on a multi-member body frames EACH member.**
//   The pair's total width grows 88 -> 148 (= 70 + 8 + 70), centred at x 76;
//   a is centred in its own 70 (76 + 20 = **96**) and b in its own (154 + 10 =
//   **164**). This re-measures `swiftui-component-distribution.swift`'s G7
//   through a different host and agrees with it. W4 adding a height moves
//   neither member's x.
// - **W2/W5: a frame that declares only the CROSS axis leaves the other axis
//   alone.** W2 is byte-identical to the W0 control, and W5's single member
//   stays at x 135. So the per-member frame is PER AXIS: an undeclared axis is
//   passed through, not centred in anything.
// - **W3/W6: a FLEXIBLE frame distributes too, and each member grows.** With
//   `maxWidth: .infinity` each member gets its own greedy frame and they share
//   the host minus the spacing (300 - 8 = 292, 146 each): a is centred in the
//   first 146 (x **58**) and b in the second (154 + 48 = x **202**).
//   `alignment: .leading` puts a at x **0** and b at x **154**, each at its own
//   frame's leading edge — so the group is NOT wrapped in one greedy frame,
//   which would have put a at 0 and b at 38.

import SwiftUI
import AppKit

// MARK: - the recording instrument

final class Sink: @unchecked Sendable {
    var frames: [String: CGRect] = [:]
    func record(_ key: String, _ rect: CGRect) { frames[key] = rect }
}

let sink = Sink()

struct Mark: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        content.overlay(GeometryReader { g in
            Color.clear.onAppear { sink.record(key, g.frame(in: .named("host"))) }
                .onChange(of: g.frame(in: .named("host"))) { _, new in sink.record(key, new) }
        })
    }
}

extension View {
    func mark(_ key: String) -> some View { modifier(Mark(key: key)) }
}

struct A: View { var body: some View { Color.red.frame(width: 30, height: 10).mark("a") } }
struct B: View { var body: some View { Color.blue.frame(width: 50, height: 10).mark("b") } }
struct Pair: View { var body: some View { A(); B() } }
struct Solo: View { var body: some View { A() } }

@MainActor
func measure<V: View>(_ label: String, width: CGFloat, height: CGFloat,
                      @ViewBuilder _ make: () -> V) {
    sink.frames.removeAll()
    let root = make()
        .frame(width: width, height: height)
        .coordinateSpace(name: "host")
    let host = NSHostingView(rootView: AnyView(root))
    host.frame = CGRect(x: 0, y: 0, width: width, height: height)
    host.layoutSubtreeIfNeeded()
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    func show(_ key: String) -> String {
        guard let r = sink.frames[key] else { return "\(key) none" }
        return "\(key) (\(fmt(r.origin.x)), \(fmt(r.origin.y))) \(fmt(r.width))x\(fmt(r.height))"
    }
    var parts = ["outer \(fmt(width))x\(fmt(height))"]
    for key in ["a", "sv", "c", "b"] where sink.frames[key] != nil || key == "a" || key == "b" {
        parts.append(show(key))
    }
    print("  \(label.padding(toLength: max(44, label.count), withPad: " ", startingAt: 0)): "
            + parts.joined(separator: " "))
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r.rounded())) : String(format: "%.2f", r)
}

// MARK: - arms

@MainActor
func run() {
    print("--- V: is a ScrollView flexible inside a stack? (host 100x200)")
    measure("V0 control VStack{a 60x30; b 60x30}", width: 100, height: 200) {
        VStack {
            Color.red.frame(width: 60, height: 30).mark("a")
            Color.blue.frame(width: 60, height: 30).mark("b")
        }
    }
    measure("V1 VStack{a 60x30; ScrollView{c 60x300}}", width: 100, height: 200) {
        VStack {
            Color.red.frame(width: 60, height: 30).mark("a")
            ScrollView(.vertical) {
                Color.green.frame(width: 60, height: 300).mark("c")
            }.mark("sv")
        }
    }
    measure("V2 control VStack{a 60x30; Color 60 wide}", width: 100, height: 200) {
        VStack {
            Color.red.frame(width: 60, height: 30).mark("a")
            Color.green.frame(width: 60).mark("sv")
        }
    }
    measure("V3 VStack{a 60x30; ScrollView{c 60x20}}", width: 100, height: 200) {
        VStack {
            Color.red.frame(width: 60, height: 30).mark("a")
            ScrollView(.vertical) {
                Color.green.frame(width: 60, height: 20).mark("c")
            }.mark("sv")
        }
    }
    measure("V4 HStack{a 30x60; ScrollView(.h){c 300x60}}", width: 100, height: 200) {
        HStack {
            Color.red.frame(width: 30, height: 60).mark("a")
            ScrollView(.horizontal) {
                Color.green.frame(width: 300, height: 60).mark("c")
            }.mark("sv")
        }
    }
    measure("V5 VStack{a 60x30; ScrollView{c 60x300}.fixedSize()}", width: 100, height: 200) {
        VStack {
            Color.red.frame(width: 60, height: 30).mark("a")
            ScrollView(.vertical) {
                Color.green.frame(width: 60, height: 300).mark("c")
            }.fixedSize().mark("sv")
        }
    }

    print("--- W: a flexible or single-axis frame on a multi-member custom view (host 300x100)")
    measure("W0 control Pair()", width: 300, height: 100) { HStack { Pair() } }
    measure("W1 Pair().frame(width: 70)", width: 300, height: 100) {
        HStack { Pair().frame(width: 70) }
    }
    measure("W2 Pair().frame(height: 40)", width: 300, height: 100) {
        HStack { Pair().frame(height: 40) }
    }
    measure("W3 Pair().frame(maxWidth: .infinity)", width: 300, height: 100) {
        HStack { Pair().frame(maxWidth: .infinity) }
    }
    measure("W4 Pair().frame(width: 70, height: 40)", width: 300, height: 100) {
        HStack { Pair().frame(width: 70, height: 40) }
    }
    measure("W5 Solo().frame(height: 40)", width: 300, height: 100) {
        HStack { Solo().frame(height: 40) }
    }
    measure("W6 Pair().frame(maxWidth: .infinity, alignment: .leading)", width: 300, height: 100) {
        HStack { Pair().frame(maxWidth: .infinity, alignment: .leading) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
