// SwiftUI probe: stage 8 of plan task 7 (the sizing vocabulary).
// Evidence for the SwiftUI half of the stage-8 rulings in
// docs/superpowers/2026-09-17-engine-replacement-decisions.md (LR-ET for F,
// LR-EV for P, LR-ER item 5 for T). Every other claim of the stage rests on MetalUI's own measured
// behaviour (record §50), not on SwiftUI. Three groups:
//
//   F — FR-G's shape in SwiftUI's vocabulary: a greedy frame answers no
//       smaller than its content unless it declares a zero minimum. This is
//       what `.minHeight(Pixels(0))` (flex §4.5's automatic minimum,
//       cancelled) becomes under the recipe: `.frame(minHeight: 0,
//       maxHeight: .infinity)`.
//   P — a frame's own minimum and finite maximum, when the frame is proposed
//       "the window minus one inset" (how stage 5 lowers an absolute box,
//       LR-CH/LR-CJ: padding for the insets inside a window-sized frame,
//       aligned top-leading). SwiftUI has no absolute positioning; the arms
//       model the LOWERING's structure, and the claim is only about what a
//       SwiftUI frame answers there.
//   T — a `Text` in a fixed-width frame is centred by default, and placed at
//       the leading edge only when the frame says `.leading` (the parent
//       spec's T7 row, "SwiftUI's centring of `Text(…).width(w)`").
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-engine-stage-8.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. The stage-7a probe's instrument, unchanged: each arm is hosted in an
// `NSHostingView` of the stated size inside a borderless window; `mark(key)`
// records the marked view's frame in the host's coordinate space through a
// `GeometryReader` overlay. Every group opens with a positive control that
// must DIFFER from the arm under test (practices shape 15).
//
// RECORDED 2026-09-24 by the stage-8 design session, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0. Run twice;
// the two outputs are byte-identical (`diff` empty), 10 lines (three group
// headers, seven arms).
//
// READING.
// - F: without a minimum the greedy frame answers its content's 400 and the
//   VStack overflows, pushing the header to y -140 (F0); with `minHeight: 0`
//   it answers the 120 left under the header and the content overflows the
//   frame instead (F1). A greedy frame's lower bound is its content unless a
//   minimum is declared — SwiftUI's own spelling of cancelling an "automatic
//   minimum". MetalUI's kernel answers the same (record §50 §3, scratch S7a/S7b).
// - P: proposed 170 (the window minus the 30pt inset), the text alone is 11
//   wide (P0); `.frame(minWidth: 100)` answers 100 (P1) and
//   `.frame(maxWidth: 80)` answers 80 — a finite maximum grows toward the
//   proposal, `FR-E`'s D4 again (P2).
// - T: a `.frame(width: 100)` centres its 11pt text at x 94.5 (T1); only
//   `alignment: .leading` puts it at the frame's leading edge, x 50 (T0).
//
// OUTPUT (whole stdout):
// --- F: does a greedy frame answer below its content? host 200x200, an 80pt header above
//   F0 control VStack(0){a 80; c 50x400 .frame(maxHeight: inf) = b}: host 200x200 a (0, -140) 200x80 b (75, -60) 50x400 c (75, -60) 50x400
//   F1 ... .frame(minHeight: 0, maxHeight: inf) = b               : host 200x200 a (0, 0) 200x80 b (75, 80) 50x120 c (75, -60) 50x400
// --- P: a frame's own bounds, proposed the window minus one inset (top 10, left 30), host 200x200
//   P0 control Text("hi") = b                                     : host 200x200 b (30, 10) 11x16
//   P1 Text("hi").frame(minWidth: 100) = b                        : host 200x200 b (30, 10) 100x16
//   P2 Text("hi").frame(maxWidth: 80) = b                         : host 200x200 b (30, 10) 80x16
// --- T: where does a fixed-width frame put its Text? host 200x100
//   T0 control Text("hi") = c .frame(width: 100, alignment: .leading) = b: host 200x100 b (50, 42) 100x16 c (50, 42) 11x16
//   T1 Text("hi") = c .frame(width: 100) = b                      : host 200x100 b (50, 42) 100x16 c (94.50, 42) 11x16

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

@MainActor
func measure<V: View>(_ label: String, width: CGFloat, height: CGFloat,
                      keys: [String] = ["a", "b", "c"],
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
    var parts = ["host \(fmt(width))x\(fmt(height))"]
    for key in keys {
        guard let r = sink.frames[key] else { continue }
        parts.append("\(key) (\(fmt(r.origin.x)), \(fmt(r.origin.y))) \(fmt(r.width))x\(fmt(r.height))")
    }
    print("  \(label.padding(toLength: max(62, label.count), withPad: " ", startingAt: 0)): "
            + parts.joined(separator: " "))
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r.rounded())) : String(format: "%.2f", r)
}

func box(_ w: CGFloat, _ h: CGFloat, _ key: String) -> some View {
    Color.gray.frame(width: w, height: h).mark(key)
}

/// The stage-5 lowering's shape for an absolute box with `top: 10, left: 30`
/// in a 200x200 window: padding for the insets inside a window-sized frame,
/// aligned top-leading.
func presented<V: View>(_ content: V) -> some View {
    content.padding(.leading, 30).padding(.top, 10)
        .frame(width: 200, height: 200, alignment: .topLeading)
}

// MARK: - arms

@MainActor
func run() {
    print("--- F: does a greedy frame answer below its content? host 200x200, an 80pt header above")
    measure("F0 control VStack(0){a 80; c 50x400 .frame(maxHeight: inf) = b}", width: 200, height: 200) {
        VStack(spacing: 0) {
            box(200, 80, "a")
            box(50, 400, "c").frame(maxHeight: .infinity).mark("b")
        }
    }
    measure("F1 ... .frame(minHeight: 0, maxHeight: inf) = b", width: 200, height: 200) {
        VStack(spacing: 0) {
            box(200, 80, "a")
            box(50, 400, "c").frame(minHeight: 0, maxHeight: .infinity).mark("b")
        }
    }

    print("--- P: a frame's own bounds, proposed the window minus one inset (top 10, left 30), host 200x200")
    measure("P0 control Text(\"hi\") = b", width: 200, height: 200) {
        presented(Text("hi").mark("b"))
    }
    measure("P1 Text(\"hi\").frame(minWidth: 100) = b", width: 200, height: 200) {
        presented(Text("hi").frame(minWidth: 100).mark("b"))
    }
    measure("P2 Text(\"hi\").frame(maxWidth: 80) = b", width: 200, height: 200) {
        presented(Text("hi").frame(maxWidth: 80).mark("b"))
    }

    print("--- T: where does a fixed-width frame put its Text? host 200x100")
    measure("T0 control Text(\"hi\") = c .frame(width: 100, alignment: .leading) = b", width: 200, height: 100) {
        Text("hi").mark("c").frame(width: 100, alignment: .leading).mark("b")
    }
    measure("T1 Text(\"hi\") = c .frame(width: 100) = b", width: 200, height: 100) {
        Text("hi").mark("c").frame(width: 100).mark("b")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
