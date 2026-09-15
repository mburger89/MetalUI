// SwiftUI probe: what a DISABLED descendant does to an enabled ANCESTOR's tap
// (arm N), and whether a gesture or reader written AFTER `.disabled` /
// `.environment` sees the scope (arm O). Evidence for rulings EV-E (a disabled
// click target registers no hitbox), EV-X (modifiers after a scope, once the
// modifier-composition merge makes them spellable) in
// docs/superpowers/2026-09-15-environment-decisions.md.
//
// Added in the environment track's THIRD design pass, from a critic's scratch
// probe (same harness as `swiftui-disabled-interaction.swift`, which this file
// copies rather than imports: a probe is one self-contained script).
//
// HOW TO RUN. Either form; both were run on the final file and their filtered
// output is byte-identical to the recorded block below (and so is
// `/usr/bin/swiftc <file>` followed by the same filtered run):
//
//   /usr/bin/swift docs/probes/swiftui-disabled-ancestor-and-order.swift
//   swiftc docs/probes/swiftui-disabled-ancestor-and-order.swift -o /tmp/ancprobe
//   OS_ACTIVITY_DT_MODE=1 /tmp/ancprobe 2>&1 | grep -v 'Connection\]\|ntents\|WindowTab'
//
// It opens and orders out one small window per arm. Exit status 0.
//
// HARNESS: `FirstMouseHost` and the down/50 ms/up click through
// `NSWindow.sendEvent` are the fixes `swiftui-disabled-interaction.swift`'s
// header documents; without them every tap arm, controls included, reads 0.
// Every arm below that reads 0 has an enabled control in the same shape that
// reads 1 (N0/N3/N4 for N1/N2, O0 for O1).
//
// RECORDED 2026-09-15 (third design pass), macOS 26.6.2 (25G83), MacBook with a
// 2x display, system appearance dark, locale en_US. Run three ways, filtered
// output byte-identical: `/usr/bin/swift <file>` and `/usr/bin/swiftc` (Apple
// Swift 6.4, swiftlang-6.4.0.33.1), and `swiftc` from a swift.org 6.3.3
// toolchain (swiftly). Exit status 0 each time:
//
//   --- N: a click at the centre; the tap gesture is on the ANCESTOR ZStack
//     N0 control, enabled child gesture: child: 1
//     N0 control, enabled child gesture: parent: 0
//     N3 control, enabled .plain Button in a tappable card: button: 1
//     N3 control, enabled .plain Button in a tappable card: parent: 0
//     N4 control, gesture-less child in a tappable card: parent: 1
//     N1 disabled child gesture: child: 0
//     N1 disabled child gesture: parent: 1
//     N2 disabled .plain Button in a tappable card: button: 0
//     N2 disabled .plain Button in a tappable card: parent: 1
//   --- O: a tap gesture written inside vs after .disabled
//     O0 control, Color.onTapGesture: 1
//     O1 gesture INSIDE .disabled: Color.onTapGesture.disabled(true): 0
//     O2 gesture AFTER .disabled: Color.disabled(true).onTapGesture: 1
//     O3 gesture AFTER .disabled and .padding: Color.disabled(true).padding(4).onTapGesture: 1
//     O4 enabled VStack gesture over a disabled gesture-less child: 1
//   --- O5/O6: a background reader written before vs after .environment
//     O5 control, background BEFORE the writer: .background(R).environment(probe, 1): probe=1
//     O6 background AFTER the writer: .environment(probe, 1).background(R): probe=0
//
// READING (what the rulings rely on):
// - N1, N2: a DISABLED descendant does not block an enabled ANCESTOR's tap.
//   The ancestor fires (parent 1) for a disabled gesture and for a disabled
//   `.plain` Button alike. The controls moved the other way: with the child
//   enabled, the child takes the tap and the ancestor does not (N0, N3). N4:
//   a child with no gesture at all lets the ancestor fire, so N1/N2 read as
//   "a disabled gesture behaves like no gesture, towards its ancestors".
//   Contrast `swiftui-disabled-interaction.swift` P2/P2f/P2m: towards a SIBLING
//   underneath, SwiftUI's shape still blocks, disabled or not, with or without
//   a gesture. MetalUI has no shape apart from `onClick` (EV-E).
// - O1 vs O2/O3: `.disabled` reaches gestures written INSIDE it and not a
//   gesture written AFTER it, with or without a layout modifier between. O4:
//   an enabled ancestor's gesture over a disabled gesture-less child fires.
// - O5 vs O6: a background written AFTER an `.environment` writer does not see
//   the write; one written before it (inside the scope) does. Same shape as
//   `swiftui-environment-scoping.swift` F2 for an overlay.
import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Count {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static func bump(_ k: String) { hits[k, default: 0] += 1 }
    static func read(_ k: String) -> Int { hits[k, default: 0] }
}

enum Seen {
    nonisolated(unsafe) static var probe: [String: Int] = [:]
}

struct ProbeKey: EnvironmentKey { static let defaultValue: Int = 0 }
extension EnvironmentValues {
    var probe: Int {
        get { self[ProbeKey.self] }
        set { self[ProbeKey.self] = newValue }
    }
}

/// Records the `probe` value it sees, keyed by label.
struct Reader: View {
    let label: String
    @Environment(\.probe) var probe
    var body: some View {
        Color.clear.onAppear { Seen.probe[label] = probe }
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin()
    return w
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    w.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    w.sendEvent(ev(.leftMouseUp))
    spin()
}

@MainActor func tapArm(_ view: some View) {
    let w = makeWindow(view)
    click(w, at: CGPoint(x: 100, y: 100))
    w.orderOut(nil)
}

@MainActor func armN() -> [String] {
    tapArm(ZStack { Color.red.onTapGesture { Count.bump("N0 control, enabled child gesture: child") } }
        .onTapGesture { Count.bump("N0 control, enabled child gesture: parent") })
    tapArm(ZStack { Color.red.onTapGesture { Count.bump("N1 disabled child gesture: child") }.disabled(true) }
        .onTapGesture { Count.bump("N1 disabled child gesture: parent") })
    tapArm(ZStack {
        Button { Count.bump("N2 disabled .plain Button in a tappable card: button") } label: { Color.red }
            .buttonStyle(.plain).disabled(true)
    }.onTapGesture { Count.bump("N2 disabled .plain Button in a tappable card: parent") })
    tapArm(ZStack {
        Button { Count.bump("N3 control, enabled .plain Button in a tappable card: button") } label: { Color.red }
            .buttonStyle(.plain)
    }.onTapGesture { Count.bump("N3 control, enabled .plain Button in a tappable card: parent") })
    tapArm(ZStack { Color.red }
        .onTapGesture { Count.bump("N4 control, gesture-less child in a tappable card: parent") })
    return ["N0 control, enabled child gesture: child", "N0 control, enabled child gesture: parent",
            "N3 control, enabled .plain Button in a tappable card: button",
            "N3 control, enabled .plain Button in a tappable card: parent",
            "N4 control, gesture-less child in a tappable card: parent",
            "N1 disabled child gesture: child", "N1 disabled child gesture: parent",
            "N2 disabled .plain Button in a tappable card: button",
            "N2 disabled .plain Button in a tappable card: parent"]
}

@MainActor func armO() -> [String] {
    tapArm(Color.blue.onTapGesture { Count.bump("O0 control, Color.onTapGesture") })
    tapArm(Color.blue.onTapGesture { Count.bump("O1 gesture INSIDE .disabled: Color.onTapGesture.disabled(true)") }
        .disabled(true))
    tapArm(Color.blue.disabled(true)
        .onTapGesture { Count.bump("O2 gesture AFTER .disabled: Color.disabled(true).onTapGesture") })
    tapArm(Color.blue.disabled(true).padding(4)
        .onTapGesture { Count.bump("O3 gesture AFTER .disabled and .padding: Color.disabled(true).padding(4).onTapGesture") })
    tapArm(VStack { Color.blue.disabled(true) }
        .onTapGesture { Count.bump("O4 enabled VStack gesture over a disabled gesture-less child") })
    return ["O0 control, Color.onTapGesture",
            "O1 gesture INSIDE .disabled: Color.onTapGesture.disabled(true)",
            "O2 gesture AFTER .disabled: Color.disabled(true).onTapGesture",
            "O3 gesture AFTER .disabled and .padding: Color.disabled(true).padding(4).onTapGesture",
            "O4 enabled VStack gesture over a disabled gesture-less child"]
}

@MainActor func armOBackground() {
    let w = makeWindow(VStack {
        Color.clear.background(Reader(label: "O5 control, background BEFORE the writer: .background(R).environment(probe, 1)"))
            .environment(\.probe, 1)
        Color.clear.environment(\.probe, 1)
            .background(Reader(label: "O6 background AFTER the writer: .environment(probe, 1).background(R)"))
    })
    spin(0.3)
    w.orderOut(nil)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)

    print("--- N: a click at the centre; the tap gesture is on the ANCESTOR ZStack")
    for k in armN() { print("  \(k): \(Count.read(k))") }
    print("--- O: a tap gesture written inside vs after .disabled")
    for k in armO() { print("  \(k): \(Count.read(k))") }
    print("--- O5/O6: a background reader written before vs after .environment")
    armOBackground()
    for k in Seen.probe.keys.sorted() { print("  \(k): probe=\(Seen.probe[k]!)") }
}
