// SwiftUI probe: WHAT ELSE does `.allowsHitTesting(false)` take away?
//
// `swiftui-content-shape-hit-region.swift` (arms N1/N2) already shows it
// removes the POINTER target, including the receiver's own gesture. This file
// asks the two questions that decide how much of `Frame.registerHandlers` a
// MetalUI `allowsHitTesting(false)` scope may cover (ruling OM-T, lane 3):
//
//   1. is the view still in the ACCESSIBILITY tree?
//   2. does a KEYBOARD ask — a keyboard shortcut — still fire?
//
// MetalUI's scope gates only the hitbox insert: focus registration, the
// `$focus` retention write, the declared `AXNode` and the accessibility record
// all sit above that gate (`Frame.swift`). This probe is the evidence for the
// claim that SwiftUI keeps the same two halves, rather than that claim being
// derived from a mechanism MetalUI chose for itself.
//
// Evidence for OM-T (and its "cost if wrong" clause) in
// docs/superpowers/2026-09-15-outer-modifiers-decisions.md.
//
// HOW TO RUN (Apple's toolchain; swiftly's swift.org JIT cannot load SwiftUI —
// see docs/probes/swiftui-layout-protocol-contract.swift's header):
//
//   /usr/bin/swift docs/probes/swiftui-allows-hit-testing-side-effects.swift 2>&1 \
//     | grep -v 'Connection\]\|warning:\|deprecated\|note:'
//
// It opens one small window per arm and orders them out. Exit status 0.
//
// HOW IT READS THE AX TREE. `swiftui-accessibility-bridge.swift`'s walker:
// SwiftUI's `AccessibilityNode` objects answer the modern accessibility
// selectors through KVC (`value(forKey: "accessibilityRole")`) and nothing
// else, and the process must first set `AXEnhancedUserInterface` on `NSApp` or
// a hosting view reports zero children.
//
// POSITIVE CONTROLS.
//   - A0 is the same Button with no modifier: it must report AXButton/"Go", or
//     a nil in A1 is the walker failing rather than SwiftUI answering.
//   - A2 is `.accessibilityHidden(true)`: it must DISAPPEAR, or "A1 still shows
//     a button" is a walker that cannot see a removal at all (taxonomy shape
//     15 — require the arms to disagree before believing they agree).
//   - K0 is the same shortcut with no modifier: its counter must move, or K1's
//     zero would be the event harness rather than SwiftUI.
//
// RECORDED 2026-09-15 (lane 3), macOS 26.6.2 (25G83), /usr/bin/swift = Apple
// Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0; stdout verbatim. stderr carries one
// deprecation warning, for the `AXEnhancedUserInterface` write on line 133,
// and nothing else:
//
//   === A0 Button("Go") — control
//     NSHostingView<Button<Text>> role=AXGroup kids=1
//       AccessibilityNode role=AXButton label=Go value=nil
//   === A1 Button("Go").allowsHitTesting(false)
//     NSHostingView<ModifiedContent<Button<Text>, _AllowsHitTestingModifier>> role=AXGroup kids=1
//       AccessibilityNode role=AXButton label=Go value=nil
//   === A2 Button("Go").accessibilityHidden(true) — negative control
//     NSHostingView<ModifiedContent<Button<Text>, AccessibilityAttachmentModifier>> role=AXGroup kids=0
//   === K0 Button + keyboardShortcut("g"), no modifier — control
//     key "g" -> pressed 1 time(s)
//   === K1 the same under .allowsHitTesting(false)
//     key "g" -> pressed 1 time(s)
//
// WHAT IT SHOWS.
// - A0 vs A1 vs A2: `.allowsHitTesting(false)` leaves the view in the
//   accessibility tree, with its role and label intact. A2 shows the
//   instrument can see a view leave the tree, so A1's "still a button" is
//   SwiftUI's answer.
// - K0 vs K1: a keyboard shortcut declared on the view still fires under
//   `.allowsHitTesting(false)`. The modifier is a POINTER decision.
// - Together: MetalUI gating only the hitbox insert — and leaving focus
//   registration, the `$focus` write, the declared `AXNode` and the
//   accessibility record above the gate — is what SwiftUI does, not a MetalUI
//   convenience. Pinned on the MetalUI side by
//   `allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTargetAndItsSubtreesAndKeepsTheKeyboardOnes`
//   and `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload`
//   (`Tests/MetalUITests/HitRegionTests.swift`).

import SwiftUI
import AppKit

@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

func kv(_ o: NSObject, _ key: String) -> Any? {
    o.value(forKey: key)
}

func str(_ v: Any?) -> String { v.map { "\($0)" } ?? "nil" }

@MainActor func kids(_ o: NSObject) -> [NSObject] {
    ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}

@MainActor func describe(_ host: NSObject) {
    print("  \(type(of: host)) role=\(str(kv(host, "accessibilityRole"))) kids=\(kids(host).count)")
    for k in kids(host) {
        print("    \(type(of: k)) role=\(str(kv(k, "accessibilityRole"))) "
              + "label=\(str(kv(k, "accessibilityLabel"))) value=\(str(kv(k, "accessibilityValue")))")
    }
}

var windows: [NSWindow] = []

@MainActor func host<V: View>(_ name: String, _ v: V) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 200, height: 100),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.makeKeyAndOrderFront(nil)
    h.layoutSubtreeIfNeeded()
    spin(0.4)
    print("=== \(name)")
    windows.append(w)
    return (h, w).0
}

/// Sends one bare `g` keyDown/keyUp pair through the window's key-equivalent
/// path, the way a menu-less app receives a `keyboardShortcut`.
@MainActor func sendKey(_ w: NSWindow, _ characters: String) {
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.keyEvent(with: t, location: .zero, modifierFlags: [],
                         timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: w.windowNumber, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: 5)!
    }
    let down = ev(.keyDown)
    if !w.performKeyEquivalent(with: down) { w.sendEvent(down) }
    spin(0.2)
    w.sendEvent(ev(.keyUp))
    spin(0.3)
}

nonisolated(unsafe) var pressed = 0

@MainActor func run() {
    NSApp.accessibilitySetValue(true,
                                forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    spin(0.3)

    describe(host("A0 Button(\"Go\") — control", Button("Go") {}))
    describe(host("A1 Button(\"Go\").allowsHitTesting(false)",
                  Button("Go") {}.allowsHitTesting(false)))
    describe(host("A2 Button(\"Go\").accessibilityHidden(true) — negative control",
                  Button("Go") {}.accessibilityHidden(true)))

    pressed = 0
    let k0 = host("K0 Button + keyboardShortcut(\"g\"), no modifier — control",
                  Button("Go") { pressed += 1 }.keyboardShortcut("g", modifiers: []))
    sendKey(k0.window!, "g")
    print("  key \"g\" -> pressed \(pressed) time(s)")

    pressed = 0
    let k1 = host("K1 the same under .allowsHitTesting(false)",
                  Button("Go") { pressed += 1 }.keyboardShortcut("g", modifiers: [])
                      .allowsHitTesting(false))
    sendKey(k1.window!, "g")
    print("  key \"g\" -> pressed \(pressed) time(s)")

    for w in windows { w.orderOut(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated { run() }
