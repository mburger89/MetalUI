// SwiftUI probe: `@Environment(Type.self)` and `.environment(_ object:)` for
// `@Observable` objects (port-gaps-medium design, rulings MD-… in
// docs/superpowers/2026-10-07-port-gaps-medium-decisions.md; MG-2).
//
// QUESTIONS.
// - N: nearest writer wins — `.environment(a)` outside `.environment(b)`;
//   two different types side by side in one chain; a sibling not under the
//   writer.
// - O: `@Environment(Model.self) var m: Model?` with no writer reads nil; with
//   one, the object.
// - K: keying — an object written as a subclass (`.environment(sub)`, static
//   type `Sub`) read as `@Environment(Base.self)`, and written upcast
//   (`.environment(sub as Base)`) read as `Base` and as `Sub`.
// - T: a non-optional read with no writer — the process's exit and its
//   message (run as a child process: `probe --trap`).
// - R: observation — a reader's body re-runs when a property it read changes,
//   and not when an unread property changes.
// - W: `.environment(nil as Model?)` below a writer: does it clear?
//
// INSTRUMENTS. Hosted `NSHostingView`s; each reader appends what it read to a
// log in its body. T: the probe re-executes itself with `--trap` and reports
// the child's termination status/reason and its stderr's last lines.
//
// POSITIVE CONTROL. N0 a reader under one writer reads that object's name
// ("a"). SEPARATING ARM. O1 (no writer, nil) vs O2 (writer, "a"); K1 vs K2.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-environment-object.swift -o /tmp/md-env && /tmp/md-env
//
// RECORDED and READING: the block at the end of this file.

import AppKit
import Observation
import SwiftUI

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@Observable class Base { var name: String; var count = 0; var other = 0; init(_ n: String) { name = n } }
@Observable final class Other { var tag: String; init(_ t: String) { tag = t } }
final class Sub: Base {}

final class Log: @unchecked Sendable { var lines: [String] = [] }
let log = Log()

struct ReadBase: View {
    let label: String
    @Environment(Base.self) var model
    var body: some View {
        let _ = log.lines.append("\(label) read \(model.name) count=\(model.count)")
        Text(model.name)
    }
}
struct ReadOptional: View {
    let label: String
    @Environment(Base.self) var model: Base?
    var body: some View {
        let _ = log.lines.append("\(label) read \(model?.name ?? "nil")")
        Text(model?.name ?? "nil")
    }
}
struct ReadSub: View {
    let label: String
    @Environment(Sub.self) var model: Sub?
    var body: some View {
        let _ = log.lines.append("\(label) read \(model?.name ?? "nil")")
        Text("s")
    }
}
struct ReadOther: View {
    let label: String
    @Environment(Other.self) var other
    var body: some View {
        let _ = log.lines.append("\(label) read \(other.tag)")
        Text(other.tag)
    }
}

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ label: String, _ v: V) {
    log.lines = []
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: v)
    w.orderFrontRegardless()
    spin(0.3)
    windows.append(w)
    print("\(label):")
    for l in log.lines { print("  \(l)") }
}

@MainActor func run() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let a = Base("a"), b = Base("b"), s = Sub("s")
    host("N0 one writer", ReadBase(label: "r").environment(a))
    host("N1 a outside b", ReadBase(label: "r").environment(b).environment(a))
    host("N2 two types", VStack { ReadBase(label: "r1"); ReadOther(label: "r2") }
            .environment(Other("o")).environment(a))
    host("N3 sibling outside", VStack { ReadOptional(label: "inside").environment(a); ReadOptional(label: "outside") })
    host("O1 optional no writer", ReadOptional(label: "r"))
    host("O2 optional writer", ReadOptional(label: "r").environment(a))
    host("K1 written as Sub, read Base?", ReadOptional(label: "r").environment(s))
    host("K1b written as Sub, read Sub?", ReadSub(label: "r").environment(s))
    host("K2 written as Base (upcast), read Base?", ReadOptional(label: "r").environment(s as Base))
    host("K2b written as Base (upcast), read Sub?", ReadSub(label: "r").environment(s as Base))
    host("W1 nil below a", ReadOptional(label: "r").environment(nil as Base?).environment(a))

    // R: observation.
    log.lines = []
    let m = Base("m")
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: ReadBase(label: "r").environment(m))
    w.orderFrontRegardless()
    spin(0.3)
    let before = log.lines.count
    m.other += 1            // not read by the body
    spin(0.3)
    let afterUnread = log.lines.count
    m.count += 1            // read by the body
    spin(0.3)
    print("R observation: initial bodies=\(before) after unread write=\(afterUnread - before) after read write=\(log.lines.count - afterUnread)")
    for l in log.lines { print("  \(l)") }

    // T: child process.
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["--trap"]
    let err = Pipe(); child.standardError = err; child.standardOutput = Pipe()
    try! child.run()
    child.waitUntilExit()
    let text = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    print("T missing object: status=\(child.terminationStatus) reason=\(child.terminationReason == .uncaughtSignal ? "signal" : "exit")")
    for line in text.split(separator: "\n").suffix(4) { print("  stderr: \(line)") }
}

@MainActor func trap() {
    NSApplication.shared.setActivationPolicy(.accessory)
    host("T child", ReadBase(label: "r"))
    print("T child survived")
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--trap") { trap() } else { run() }
}

// RECORDED 2026-10-06 on macOS 27.0.1 (26A434), Apple Swift 6.4
// (swiftlang-6.4.0.33.1), screen unlocked (appkit-screen-lock-state.swift: no
// CGSSessionScreenIsLocked line, displayAsleep main: 0), compiled form. Run three
// times by the design session; the three outputs (29 lines) are byte-identical.
//
// READING (the authority for MD-H):
// - N0 (positive control) reads "a". N1: the nearest writer wins (b inside a).
//   N2: two types coexist in one chain. N3: a sibling outside the writer reads
//   nil (optional form).
// - O1/O2 (separating arm): the optional form reads nil without a writer, the
//   object with one.
// - K: keyed by the static type written: written as Sub, read as Base? -> nil
//   (K1) and as Sub? -> s (K1b); written `as Base`, read as Base? -> s (K2) and
//   as Sub? -> nil (K2b).
// - W1: .environment(nil as Base?) below a writer clears it.
// - R: one body at first; a write to an unread property re-runs nothing; a write
//   to the read property re-runs the body once.
// - T: a non-optional read with no writer traps (uncaught signal, status 5):
//   "Fatal error: No Observable object of type Base found. A
//   View.environmentObject(_:) for Base may be missing as an ancestor of this
//   view." (SwiftUICore/Environment+Objects.swift:34).
//
// OUTPUT:
// N0 one writer:
//   r read a count=0
// N1 a outside b:
//   r read b count=0
// N2 two types:
//   r1 read a count=0
//   r2 read o
// N3 sibling outside:
//   inside read a
//   outside read nil
// O1 optional no writer:
//   r read nil
// O2 optional writer:
//   r read a
// K1 written as Sub, read Base?:
//   r read nil
// K1b written as Sub, read Sub?:
//   r read s
// K2 written as Base (upcast), read Base?:
//   r read s
// K2b written as Base (upcast), read Sub?:
//   r read nil
// W1 nil below a:
//   r read nil
// R observation: initial bodies=1 after unread write=0 after read write=1
//   r read m count=0
//   r read m count=1
// T missing object: status=5 reason=signal
//   stderr: SwiftUICore/Environment+Objects.swift:34: Fatal error: No Observable object of type Base found. A View.environmentObject(_:) for Base may be missing as an ancestor of this view.
