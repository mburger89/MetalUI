// SwiftUI probe: what re-runs an `.equatable()` view that reads the environment (C14-c,
// environment epoch; rulings EE-… in docs/superpowers/2026-10-14-environment-epoch-decisions.md).
//
// QUESTIONS.
// - K1: an Equatable key value that changes re-runs a reader; one that is REWRITTEN EQUAL
//   (the writer's parent re-evaluates, same value) does not (compare by ==, not by write).
// - K2: a key whose value is NOT Equatable (a class instance, a closure) rewritten with the
//   SAME instance / a NEW instance: which re-run?
// - O1: `@Environment(Model.self)` where the provided instance is SWAPPED for another of the same
//   type: re-run? O2: a property of the same instance changes and the reader read it: re-run?
// - B1: a built-in value (`colorScheme`) changes under readers of `\.colorScheme` and of a
//   custom key only: only the reader of the changed value re-runs (per-key-read granularity).
// - F1: `@FocusState` is not probed (SwiftUI-internal; MetalUI's refusal is a ruling, EE-E).
//
// INSTRUMENTS. As swiftui-incremental-invalidation.swift: a hosted NSHostingView in an offscreen
// NSWindow, every body appends to a log, the run loop drains after each change.
//
// POSITIVE CONTROL. P0: the first render runs every body once; PlainInt (no .equatable()) re-runs on
// every parent evaluation, so the counting works. SEPARATING ARMS: K1 changed vs rewritten-equal;
// B1 reader of the changed key vs reader of another.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-environment-epoch.swift -o /tmp/ee-probe && /tmp/ee-probe
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

struct IntKey: EnvironmentKey { static let defaultValue = 0 }
final class Box { var n = 0; init(_ n: Int = 0) { self.n = n } }
struct BoxKey: EnvironmentKey { nonisolated(unsafe) static var defaultValue = Box() }
struct FnKey: EnvironmentKey { static let defaultValue: @Sendable () -> Int = { 0 } }
extension EnvironmentValues {
    var intKey: Int { get { self[IntKey.self] } set { self[IntKey.self] = newValue } }
    var boxKey: Box { get { self[BoxKey.self] } set { self[BoxKey.self] = newValue } }
    var fnKey: @Sendable () -> Int { get { self[FnKey.self] } set { self[FnKey.self] = newValue } }
}
@Observable final class Model { var a = 0; var unread = 0 }

struct EqInt: View, Equatable {
    @Environment(\.intKey) var v
    nonisolated static func == (l: EqInt, r: EqInt) -> Bool { true }
    var body: some View { let _ = log.lines.append("EqInt"); Text("i \(v)") }
}
struct PlainInt: View {
    @Environment(\.intKey) var v
    var body: some View { let _ = log.lines.append("PlainInt"); Text("p \(v)") }
}
struct EqBox: View, Equatable {
    @Environment(\.boxKey) var v
    nonisolated static func == (l: EqBox, r: EqBox) -> Bool { true }
    var body: some View { let _ = log.lines.append("EqBox"); Text("b \(v.n)") }
}
struct EqFn: View, Equatable {
    @Environment(\.fnKey) var v
    nonisolated static func == (l: EqFn, r: EqFn) -> Bool { true }
    var body: some View { let _ = log.lines.append("EqFn"); Text("f \(v())") }
}
struct EqObj: View, Equatable {
    @Environment(Model.self) var m
    nonisolated static func == (l: EqObj, r: EqObj) -> Bool { true }
    var body: some View { let _ = log.lines.append("EqObj"); Text("o \(m.a)") }
}
struct EqScheme: View, Equatable {
    @Environment(\.colorScheme) var s
    nonisolated static func == (l: EqScheme, r: EqScheme) -> Bool { true }
    var body: some View { let _ = log.lines.append("EqScheme"); Text("s \(s == .dark ? 1 : 0)") }
}

struct Top: View {
    @State var tick = 0
    @State var intValue = 0
    @State var box = Box()
    @State var model = Model()
    @State var modelB = Model()
    @State var useB = false
    @State var dark = false
    @State var fnValue = 0
    nonisolated(unsafe) static var act: ((String) -> Void)?
    var body: some View {
        let _ = { Top.act = { name in
            switch name {
            case "tick": tick += 1
            case "int": intValue += 1
            case "box-new": box = Box()
            case "swap": useB.toggle()
            case "dark": dark.toggle()
            case "fn": fnValue += 1
            case "model-a": model.a += 1
            case "model-unread": model.unread += 1
            default: break
            } } }()
        let m = useB ? modelB : model
        VStack {
            Text("t \(tick)")
            EqInt().equatable()
            PlainInt()
            EqBox().equatable()
            EqFn().equatable()
            EqObj().equatable()
            EqScheme().equatable()
        }
        .environment(\.intKey, intValue)
        .environment(\.boxKey, box)
        .environment(\.fnKey, { [fnValue] in fnValue })
        .environment(m)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
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
    var order: [String] = [], counts: [String: Int] = [:]
    for l in log.take() { if counts[l] == nil { order.append(l) }; counts[l, default: 0] += 1 }
    print("\(arm): \(order.map { "\($0) x\(counts[$0]!)" }.joined(separator: ", "))")
}
@MainActor func act(_ name: String, _ arm: String) { Top.act?(name); report(arm) }

@MainActor func run() {
    let w = host(Top())
    report("P0 first render")
    act("tick", "K0-tick (first parent re-evaluation; discarded as a possible first-run artefact)")
    act("tick", "K1-equal-2 (second parent re-evaluation)")
    act("tick", "K1-equal (third; parent re-evaluates; every value rewritten equal / same instance)")
    act("int", "K1-changed (intKey 0 -> 1)")
    act("box-new", "K2-new (boxKey: a NEW non-Equatable instance)")
    act("tick", "K2-same (parent re-evaluates; same Box instance rewritten)")
    act("fn", "K2-fn (fnKey: a new closure with a different capture)")
    act("tick", "K2-fn-again (parent re-evaluates; a fresh closure with the same capture)")
    act("model-a", "O2 (provided model's property a, read by EqObj)")
    act("model-unread", "O2-unread (provided model's property nobody reads)")
    act("swap", "O1 (the provided instance swapped for another of the same type)")
    act("dark", "B1 (colorScheme changes; EqScheme reads it, the others read custom keys)")
    w.close()
}
MainActor.assumeIsolated { run() }
// RECORDED (2026-10-14, macOS 27, screen locked, hosted offscreen; run twice, identical):
//   P0 first render: EqInt, PlainInt, EqBox, EqFn, EqObj, EqScheme x1                     (positive control)
//   K0-tick (first parent re-evaluation): EqFn, EqObj x1                                  (first-run artefact, as in
//        swiftui-incremental-invalidation.swift S2/S3; K1-equal-2 and K1-equal are empty)
//   K1-equal-2, K1-equal (parent re-evaluates, every value rewritten equal): nothing re-runs
//   K1-changed (intKey 0 -> 1): EqInt, PlainInt, EqFn
//   K2-new (a NEW Box instance, a class that is not Equatable): EqBox, EqFn
//   K2-same (the same Box rewritten): nothing
//   K2-fn (a closure with a different capture): EqFn;  K2-fn-again (same capture, fresh closure): nothing
//   O2 (property read by EqObj): EqObj;  O2-unread (a property nobody reads): nothing
//   O1 (the provided instance swapped for another of the same type): EqFn, EqObj
//   B1 (colorScheme changes): EqFn, EqScheme  (EqInt, EqBox, EqObj, which read other keys, do NOT re-run)
//
// READING.
// - Granularity is PER KEY READ: B1 and K1-changed re-run only the readers of the changed key (EqInt
//   does not re-run for the scheme, EqScheme does not for intKey). Built-in and custom keys alike.
// - A write that leaves the value equal re-runs nothing (K1-equal); a class value compares as its
//   identity (K2-new re-runs, K2-same does not); a swapped object instance re-runs its reader (O1)
//   although the type is the same; an unread property of the object does not (O2-unread).
// - A value SwiftUI cannot compare (a closure) is treated as changed whenever the environment was
//   otherwise re-diffed (EqFn runs in K1-changed, K2-new, O1, B1) and not when nothing changed (K2-fn-again,
//   K1-equal). MetalUI cannot replicate that timing; it treats an uncomparable value as always changed
//   (a superset, never stale) and counts it. The only measured separating facts are the first four bullets.
