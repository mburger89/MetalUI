// SwiftUI probe: stage 7a of plan task 7 (the 97 WebKit goldens retired).
// Evidence for the SwiftUI half of rulings LR-DS…LR-DX in
// docs/superpowers/2026-09-17-engine-replacement-decisions.md. Every other
// retirement row rests on MetalUI's own measured behaviour (record §42 §2), not
// on a SwiftUI claim; these five groups back the claims the rulings make
// about SwiftUI itself:
//
//   W — a SwiftUI stack lays out ONE line and never wraps (the `flex-wrap`,
//       `align-content`, `wrap-reverse` and wrapping-content goldens);
//   G — equally flexible greedy children share the surplus equally, and the
//       only per-child knob, `layoutPriority`, is a priority, not a weight (the
//       unequal-grow and sub-one-grow goldens);
//   S — a fixed `.frame(width:)` is not shrunk by its stack, which overflows
//       instead, where a flexible frame is compressed (the weighted-shrink and
//       specified-size-suggestion goldens);
//   A/B — a fixed frame answers its own size whatever its content or padding
//       asks for (the automatic-minimum and border-box-floor goldens).
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-engine-stage-7a.swift
//
// `/usr/bin/swift` is Apple's toolchain; a swift.org toolchain's JIT fails on
// SwiftUI symbols.
//
// METHOD. Each arm is hosted in an `NSHostingView` of the stated size inside a
// borderless window; `mark(key)` records the marked view's frame in the host's
// coordinate space through a `GeometryReader` overlay (the stage-3 probe's
// instrument). Every group opens with a positive control that must DIFFER from
// the arm under test (practices shape 15).
//
// RECORDED 2026-09-23 by the stage-7a design session, macOS 27.0 (26A428),
// `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0. Run twice;
// the two outputs are byte-identical (`diff` empty), 17 lines (five group
// headers, twelve arms; the design first wrote 15 — corrected by LR-DY).
// RE-RUN 2026-09-23 by stage 7a's critic round 1, same machine and toolchain:
// exit 0, twice, both byte-identical to the OUTPUT block below.
//
// READING.
// - W: the VStack control stacks the four at y 10/30/50/70; the HStack puts all
//   four on ONE line (y 40 each), centred and overflowing the 120pt host
//   (x -40 ... 110+50), with or without a `.frame(width: 120)` around it. A
//   SwiftUI stack never starts a second line.
// - G: two greedy frames beside a fixed 100 take 300/300 of 700 (G0). The one
//   per-child knob, `layoutPriority(1)`, hands b the WHOLE surplus (600) and a
//   its minimum (0) (G1) — a priority, not a weight: neither arm is 1:2. G2
//   is a side observation, not a claim a ruling rests on: a greedy frame capped
//   at 50 beside two uncapped ones reads 50/175/175, the same numbers as the
//   `flex_row_grow_with_max` golden.
// - S: two flexible 0...200 frames in a 200pt host are compressed to 100/100
//   (S0); two FIXED 200 frames are not compressed at all — 200 each, centred,
//   the pair overflowing to x -100 (S1).
// - A: a 200pt child alone is 200 wide (A0); inside `.frame(width: 130)` the
//   frame answers 130 and the child overflows it, centred at x -75 (A1). A
//   fixed frame is not floored by its content.
// - B: a 10x10 padded by 60/50 answers 110x130 (B0); inside `.frame(width:
//   100, height: 80)` the frame answers 100x80 and the padded view still
//   answers 110x130, overflowing it (B1). A fixed frame is not floored by its
//   content's padding. (Where the overflowing child sits inside the frame is
//   NOT claimed by any ruling: MetalUI's lowering places it differently.)
//
// OUTPUT (whole stdout):
// --- W: does a stack wrap? four 50x20 children, host 120x100
//   W0 control VStack(spacing: 0){a; b; c; d}                 : host 120x100 a (35, 10) 50x20 b (35, 30) 50x20 c (35, 50) 50x20 d (35, 70) 50x20
//   W1 HStack(spacing: 0){a; b; c; d}                         : host 120x100 a (-40, 40) 50x20 b (10, 40) 50x20 c (60, 40) 50x20 d (110, 40) 50x20
//   W2 HStack(spacing: 0){a; b; c; d}.frame(width: 120)       : host 120x100 a (-40, 40) 50x20 b (10, 40) 50x20 c (60, 40) 50x20 d (110, 40) 50x20
// --- G: how do greedy children share a surplus? host 700x100
//   G0 control HStack(spacing: 0){a greedy; b greedy; c 100}  : host 700x100 a (0, 40) 300x20 b (300, 40) 300x20 c (600, 40) 100x20
//   G1 ... b.layoutPriority(1)                                : host 700x100 a (0, 40) 0x20 b (0, 40) 600x20 c (600, 40) 100x20
//   G2 HStack(spacing: 0){a greedy max 50; b greedy; c greedy}: host 400x100 a (0, 40) 50x20 b (50, 40) 175x20 c (225, 40) 175x20
// --- S: is a fixed frame shrunk by its stack? host 200x100
//   S0 control HStack(spacing: 0){a flex 0...200; b flex 0...200}: host 200x100 a (0, 40) 100x20 b (100, 40) 100x20
//   S1 HStack(spacing: 0){a 200; b 200}                       : host 200x100 a (-100, 40) 200x20 b (100, 40) 200x20
// --- A: does content floor a fixed frame? host 150x100
//   A0 control HStack(spacing: 0){c 200x20; b 100}            : host 150x100 b (125, 40) 100x20 c (-75, 40) 200x20
//   A1 HStack(spacing: 0){c 200x20 .frame(width: 130) = a; b 100}: host 150x100 a (-40, 40) 130x20 b (90, 40) 100x20 c (-75, 40) 200x20
// --- B: does padding floor a fixed frame? host 400x300
//   B0 control c 10x10 .padding(60 v, 50 h) = a               : host 400x300 a (145, 85) 110x130 c (195, 145) 10x10
//   B1 c 10x10 .padding(60 v, 50 h) = a .frame(100x80) = b    : host 400x300 a (145, 85) 110x130 b (150, 110) 100x80 c (195, 145) 10x10

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
                      keys: [String] = ["a", "b", "c", "d"],
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
    print("  \(label.padding(toLength: max(58, label.count), withPad: " ", startingAt: 0)): "
            + parts.joined(separator: " "))
}

func fmt(_ v: CGFloat) -> String {
    let r = (v * 100).rounded() / 100
    return r == r.rounded() ? String(Int(r.rounded())) : String(format: "%.2f", r)
}

func box(_ w: CGFloat, _ h: CGFloat, _ key: String) -> some View {
    Color.gray.frame(width: w, height: h).mark(key)
}

// MARK: - arms

@MainActor
func run() {
    print("--- W: does a stack wrap? four 50x20 children, host 120x100")
    measure("W0 control VStack(spacing: 0){a; b; c; d}", width: 120, height: 100) {
        VStack(spacing: 0) { box(50, 20, "a"); box(50, 20, "b"); box(50, 20, "c"); box(50, 20, "d") }
    }
    measure("W1 HStack(spacing: 0){a; b; c; d}", width: 120, height: 100) {
        HStack(spacing: 0) { box(50, 20, "a"); box(50, 20, "b"); box(50, 20, "c"); box(50, 20, "d") }
    }
    measure("W2 HStack(spacing: 0){a; b; c; d}.frame(width: 120)", width: 120, height: 100) {
        HStack(spacing: 0) { box(50, 20, "a"); box(50, 20, "b"); box(50, 20, "c"); box(50, 20, "d") }
            .frame(width: 120)
    }

    print("--- G: how do greedy children share a surplus? host 700x100")
    measure("G0 control HStack(spacing: 0){a greedy; b greedy; c 100}", width: 700, height: 100) {
        HStack(spacing: 0) {
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("a")
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("b")
            box(100, 20, "c")
        }
    }
    measure("G1 ... b.layoutPriority(1)", width: 700, height: 100) {
        HStack(spacing: 0) {
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("a")
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("b").layoutPriority(1)
            box(100, 20, "c")
        }
    }
    measure("G2 HStack(spacing: 0){a greedy max 50; b greedy; c greedy}", width: 400, height: 100) {
        HStack(spacing: 0) {
            Color.gray.frame(maxWidth: 50).frame(height: 20).mark("a")
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("b")
            Color.gray.frame(maxWidth: .infinity).frame(height: 20).mark("c")
        }
    }

    print("--- S: is a fixed frame shrunk by its stack? host 200x100")
    measure("S0 control HStack(spacing: 0){a flex 0...200; b flex 0...200}", width: 200, height: 100) {
        HStack(spacing: 0) {
            Color.gray.frame(minWidth: 0, idealWidth: 200, maxWidth: 200).frame(height: 20).mark("a")
            Color.gray.frame(minWidth: 0, idealWidth: 200, maxWidth: 200).frame(height: 20).mark("b")
        }
    }
    measure("S1 HStack(spacing: 0){a 200; b 200}", width: 200, height: 100) {
        HStack(spacing: 0) { box(200, 20, "a"); box(200, 20, "b") }
    }

    print("--- A: does content floor a fixed frame? host 150x100")
    measure("A0 control HStack(spacing: 0){c 200x20; b 100}", width: 150, height: 100) {
        HStack(spacing: 0) { box(200, 20, "c"); box(100, 20, "b") }
    }
    measure("A1 HStack(spacing: 0){c 200x20 .frame(width: 130) = a; b 100}", width: 150, height: 100) {
        HStack(spacing: 0) { box(200, 20, "c").frame(width: 130).mark("a"); box(100, 20, "b") }
    }

    print("--- B: does padding floor a fixed frame? host 400x300")
    measure("B0 control c 10x10 .padding(60 v, 50 h) = a", width: 400, height: 300) {
        box(10, 10, "c").padding(EdgeInsets(top: 60, leading: 50, bottom: 60, trailing: 50)).mark("a")
    }
    measure("B1 c 10x10 .padding(60 v, 50 h) = a .frame(100x80) = b", width: 400, height: 300) {
        box(10, 10, "c").padding(EdgeInsets(top: 60, leading: 50, bottom: 60, trailing: 50)).mark("a")
            .frame(width: 100, height: 80).mark("b")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
