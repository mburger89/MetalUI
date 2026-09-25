// SwiftUI probe: `ScrollViewReader`'s reach and `scrollTo`'s key matching
// (plan task 10, part 1 — the critic round). Two questions the design's
// `DD-G` answered without an arm:
//
//   1. Is a proxy's reach its reader's subtree? (arms S0–S2)
//   2. Does `scrollTo` compare keys by value (`AnyHashable`) or by
//      description — does `scrollTo(10)` reach `.id("10")`? (arms S3–S5)
//   3. Are two `ForEach` ids equal in description but not in value one
//      element or two? (arms S6–S7; `DD-B` item 4 answered it without one)
//
// Evidence for rulings DD-K and DD-L in
// docs/superpowers/2026-09-25-data-and-scrolling-decisions.md.
//
// HOW TO RUN (ruling SA-O's two forms):
//
//   /usr/bin/swift docs/probes/swiftui-scrollviewreader-scope.swift
//   xcrun swiftc docs/probes/swiftui-scrollviewreader-scope.swift -o /tmp/svr-probe && /tmp/svr-probe
//
// THE INSTRUMENT is `swiftui-data-and-scrolling.swift`'s T instrument:
// offsets read with `.onScrollGeometryChange(for:)`, the proxy stashed at
// `.onAppear` and called outside any SwiftUI dispatch, the run loop spun,
// each host a borderless window ordered in (window-less, `scrollTo` moves
// nothing). Every scroller is 100x100 over a 250-tall spacer, the 30-tall
// target, and a 400-tall spacer, so a `.top` hit reads 250.
//
// POSITIVE CONTROLS. S0 (one reader, `scrollTo("x")`) must read 250; S3's
// first reading (`scrollTo("10")` onto `.id("10")`) must read 250. The
// separating arms: S2 (the key exists ONLY outside the called reader —
// unscoped would move B) and S3's second reading / S4 (same description,
// different type).
//
// RECORDED 2026-09-25 by the plan task 10 part 1 critic session, macOS 27.0
// (26A428), Apple Swift 6.4, screen LOCKED (`CGSSessionScreenIsLocked = 1`,
// `displayAsleep main: 1`; the T instrument does not need an unlocked screen,
// as `swiftui-data-and-scrolling.swift`'s T arms show). Script form and
// compiled form printed byte-identical stdout, exit 0, stderr empty:
//
//   --- S: a proxy's reach
//   S0 one reader, scrollTo("x", .top) (control): a 250
//   S1 two readers, both with .id("x"); A's proxy scrollTo("x", .top): a 250 b 0
//   S2 .id("x") only under reader B; A's proxy scrollTo("x", .top): a 0 b 0
//   --- K: key matching
//   S3 .id("10"); scrollTo("10", .top) (control), then back to 0, then scrollTo(10 as Int, .top): a 250 -> a 0 -> a 0
//   S4 .id(10 as Int); scrollTo("10", .top), then scrollTo(10, .top) (control): a 0 -> a 250
//   S5 ForEach(0..<1, id: \.self) at 250 (no .id); scrollTo("0", .top), then scrollTo(0, .top) (control): a 0 -> a 250
//   --- D: ids equal in description, different in value
//   S6 ForEach over ids AnyHashable(1) and AnyHashable("1"): evaluated int 1, string 1
//   S7 ForEach over ids AnyHashable(1) twice (control, F7's shape): evaluated first
//
// WHAT IT SHOWS:
//   S0/S1 the instrument sees a proxy scroll its own reader's scroller, and
//         only that one when both hold the key.
//   S2    the separating arm: the key exists only under reader B, and A's
//         proxy moves NOTHING — a proxy's reach is its reader's subtree.
//   S3-S5 keys are compared by VALUE (`AnyHashable`), not by description:
//         `scrollTo(10)` does not reach `.id("10")`, `scrollTo("10")` does
//         not reach `.id(10)`, and `scrollTo("0")` does not reach a
//         `ForEach` element whose key is the Int 0; each control does.
//   S6/S7 `ForEach` ids that are equal in description but different in
//         value (`AnyHashable(1)`, `AnyHashable("1")`) are two elements, both
//         evaluated; equal values (S7, F7's shape) produce only the first.

import AppKit
import SwiftUI

@MainActor var offsets: [String: CGFloat] = [:]
@MainActor var proxies: [String: ScrollViewProxy] = [:]
@MainActor var windows: [NSWindow] = []

@MainActor func spin(_ n: Int = 8) {
    for _ in 0..<n { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
}

@MainActor func host<V: View>(_ size: CGSize, _ view: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: view)
    let w = NSWindow(contentRect: CGRect(x: 100, y: 100, width: size.width, height: size.height),
                     styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = h
    w.orderFrontRegardless()
    windows.append(w)
    h.layoutSubtreeIfNeeded()
    spin()
    h.layoutSubtreeIfNeeded()
    return h
}

/// A 100x100 scroller over a 250 spacer, `target` (30 tall), a 400 spacer.
struct Column<Target: View>: View {
    let name: String
    @ViewBuilder let target: () -> Target
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.gray.frame(width: 100, height: 250).id("top")
                target()
                Color.gray.frame(width: 100, height: 400)
            }
        }
        .frame(width: 100, height: 100)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, n in
            MainActor.assumeIsolated { offsets[name] = n }
        }
    }
}

struct Reader<Content: View>: View {
    let name: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollViewReader { proxy in
            content().onAppear { MainActor.assumeIsolated { proxies[name] = proxy } }
        }
    }
}

@MainActor func run<V: View>(_ label: String, _ view: V, names: [String],
                             _ calls: [(String, (ScrollViewProxy) -> Void)]) {
    offsets = [:]
    proxies = [:]
    let h = host(CGSize(width: 200, height: 100), view)
    var readings: [String] = []
    for (reader, call) in calls {
        guard let proxy = proxies[reader] else { readings.append("no proxy \(reader)"); continue }
        call(proxy)
        spin(); h.layoutSubtreeIfNeeded(); spin()
        readings.append(names.map { "\($0) \(Int(offsets[$0] ?? 0))" }.joined(separator: " "))
    }
    print(label, readings.joined(separator: " -> "))
}

func red() -> some View { Color.red.frame(width: 100, height: 30) }

@MainActor var evaluated: [String] = []

/// Logs its label each time its body is evaluated.
struct Logged: View {
    let label: String
    var body: some View {
        let _ = MainActor.assumeIsolated { evaluated.append(label) }
        return Color.red.frame(width: 10, height: 10)
    }
}

struct Keyed: Identifiable { let id: AnyHashable; let label: String }

setvbuf(stdout, nil, _IOLBF, 0)
MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    print("--- S: a proxy's reach")
    run("S0 one reader, scrollTo(\"x\", .top) (control):",
        Reader(name: "A") { Column(name: "a") { red().id("x") } },
        names: ["a"], [("A", { $0.scrollTo("x", anchor: .top) })])
    run("S1 two readers, both with .id(\"x\"); A's proxy scrollTo(\"x\", .top):",
        HStack(spacing: 0) {
            Reader(name: "A") { Column(name: "a") { red().id("x") } }
            Reader(name: "B") { Column(name: "b") { red().id("x") } }
        }, names: ["a", "b"], [("A", { $0.scrollTo("x", anchor: .top) })])
    run("S2 .id(\"x\") only under reader B; A's proxy scrollTo(\"x\", .top):",
        HStack(spacing: 0) {
            Reader(name: "A") { Column(name: "a") { red().id("y") } }
            Reader(name: "B") { Column(name: "b") { red().id("x") } }
        }, names: ["a", "b"], [("A", { $0.scrollTo("x", anchor: .top) })])
    print("--- K: key matching")
    run("S3 .id(\"10\"); scrollTo(\"10\", .top) (control), then back to 0, then scrollTo(10 as Int, .top):",
        Reader(name: "A") { Column(name: "a") { red().id("10") } },
        names: ["a"], [("A", { $0.scrollTo("10", anchor: .top) }),
                       ("A", { $0.scrollTo("top", anchor: .top) }),
                       ("A", { $0.scrollTo(10, anchor: .top) })])
    run("S4 .id(10 as Int); scrollTo(\"10\", .top), then scrollTo(10, .top) (control):",
        Reader(name: "A") { Column(name: "a") { red().id(10) } },
        names: ["a"], [("A", { $0.scrollTo("10", anchor: .top) }),
                       ("A", { $0.scrollTo(10, anchor: .top) })])
    run("S5 ForEach(0..<1, id: \\.self) at 250 (no .id); scrollTo(\"0\", .top), then scrollTo(0, .top) (control):",
        Reader(name: "A") { Column(name: "a") { ForEach(0..<1, id: \.self) { _ in red() } } },
        names: ["a"], [("A", { $0.scrollTo("0", anchor: .top) }),
                       ("A", { $0.scrollTo(0, anchor: .top) })])
    print("--- D: ids equal in description, different in value")
    evaluated = []
    let both = host(CGSize(width: 100, height: 100), VStack {
        ForEach([Keyed(id: AnyHashable(1), label: "int 1"), Keyed(id: AnyHashable("1"), label: "string 1")]) {
            Logged(label: $0.label)
        }
    })
    _ = both
    print("S6 ForEach over ids AnyHashable(1) and AnyHashable(\"1\"): evaluated",
          Set(evaluated).sorted().joined(separator: ", "))
    evaluated = []
    let dup = host(CGSize(width: 100, height: 100), VStack {
        ForEach([Keyed(id: AnyHashable(1), label: "first"), Keyed(id: AnyHashable(1), label: "second")]) {
            Logged(label: $0.label)
        }
    })
    _ = dup
    print("S7 ForEach over ids AnyHashable(1) twice (control, F7's shape): evaluated",
          Set(evaluated).sorted().joined(separator: ", "))
}
