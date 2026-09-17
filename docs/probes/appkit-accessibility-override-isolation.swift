// Probe: the isolation of the NSAccessibility overrides lane 2 of the
// accessibility bridge writes, and the thread AppKit calls them on. Evidence
// for ruling AB-AE in docs/superpowers/2026-09-15-accessibility-bridge-decisions.md.
//
// FOUND BY LANE 2'S IMPLEMENTER, NOT BY THE DESIGN. The committed overrides
// probe (appkit-accessibility-overrides-typecheck.swift) typechecks every
// override spelling with CONSTANT bodies, so it could not see that AppKit's
// `NSAccessibility` protocol and `NSAccessibilityElement` carry no main-actor
// annotation: every override is NONISOLATED, on `NSView` as well, and a body
// that reads the bridge's `@MainActor` state warns
// `main actor-isolated property … can not be referenced from a nonisolated
// context`. The first build of lane 2 printed dozens of them; the first fix
// (a helper whose closure captured `self`) then failed with
// `sending 'self' risks causing data races`, which `-typecheck` cannot see.
//
// Three questions, three arms:
//
//   A. TYPECHECK — in its own file, appkit-accessibility-override-isolation-typecheck.swift,
//      because its controls need library mode and SIL diagnostics. Which
//      spelling reads main-actor state from a nonisolated override with 0
//      diagnostics? `MainActor.assumeIsolated` requires a `Sendable` result and
//      an override returns `Any?` / `[Any]?`, so the adopted helper takes the
//      object as a PARAMETER, boxes it and its answer in an `@unchecked
//      Sendable` wrapper that never leaves the main thread, and answers a
//      FALLBACK off the main thread instead of trapping.
//   B. THREAD (two processes; the client needs the Accessibility permission).
//      Which thread does an out-of-process client's request arrive on? The spy
//      logs `Thread.isMainThread` per entry point.
//   C. OFF-MAIN (one process). The adopted helper called from a background
//      thread returns its fallback and does not trap; on the main thread the
//      same element answers (the control).
//
// HOW TO RUN (bash):
//
//   # A: see the typecheck file's header
//   # B
//   /usr/bin/swift docs/probes/appkit-accessibility-override-isolation.swift host > "$TMPDIR/ax-iso-host.log" 2>&1 &
//   until grep -q '^READY' "$TMPDIR/ax-iso-host.log"; do sleep 0.2; done
//   /usr/bin/swift docs/probes/appkit-accessibility-override-isolation.swift client $(awk '/^READY/{print $2, $3, $4}' "$TMPDIR/ax-iso-host.log")
//   wait; grep -v 'warning:\|^ *[0-9]* |\|^ *|\|note:' "$TMPDIR/ax-iso-host.log"
//   # C
//   /usr/bin/swift docs/probes/appkit-accessibility-override-isolation.swift offmain
//
// RECORDED 2026-09-15 by lane 2's implementer, macOS 26.6.2 (25G83), Apple
// Swift 6.4 (swiftlang-6.4.0.33.1), Xcode-beta's MacOSX27.0 SDK, VoiceOver off:
//
//   A (xcrun swiftc -emit-sil -o /dev/null -swift-version 6 -parse-as-library):
//     NONE      0 diagnostics
//     NEGATIVE  :56:60: warning: main actor-isolated property 'label' can not be
//               referenced from a nonisolated context
//     CAPTURE   :58:95: error: sending 'self' risks causing data races
//               [#RegionIsolation::SendingRisksDataRace]
//               — and 0 diagnostics under `-typecheck`: the diagnostic is SIL's
//     UNBOXED   :37:22: error: type 'T' does not conform to the 'Sendable' protocol
//   B, three runs, identical:
//     client: AXIsProcessTrusted=true
//     client: focused err=0 got=true
//     client: position err=0 got=true
//       passive: []
//       focused: []
//       position: ["hitTest@main"]
//     The position query reached `accessibilityHitTest` ON THE MAIN THREAD.
//     The focused query reached nothing this time (the design session's probe,
//     whose spy called `super`, logged ["focused", "isElement"]; this spy
//     answers `self` without `super`, and the window was never key). LIMIT: one
//     entry point observed, three times; that every AppKit accessibility call
//     arrives on the main thread is not established by this arm, which is why
//     the helper keeps a fallback rather than trapping.
//   C:
//     offmain: main thread label=live children=1
//     offmain: background label=nil children=0 isMain=false
//     offmain: no trap
//   The runtime file itself: `xcrun swiftc -typecheck -swift-version 6` 0 diagnostics.

import AppKit
import ApplicationServices

// MARK: - C's subject: the adopted helper, as in AppKitAccessibility.swift
// (arm A, with its controls, is appkit-accessibility-override-isolation-typecheck.swift)

/// Never crosses a thread: built and unwrapped on the main thread.
struct MainThreadAnswer<T>: @unchecked Sendable { let value: T }

nonisolated func mainActorAnswer<Object: AnyObject, T>(_ object: Object, fallback: T,
                                                      _ body: @MainActor (Object) -> T) -> T {
    guard Thread.isMainThread else { return fallback }
    let boxed = MainThreadAnswer(value: object)
    return MainActor.assumeIsolated { MainThreadAnswer(value: body(boxed.value)) }.value
}

@MainActor final class Bridge { var label = "live" }

// Not `@MainActor` here, unlike the source: in SCRIPT mode a call to an
// override of a `@MainActor` subclass from the background thread below is
// rejected at compile time, which is a script-mode rule, not the package's
// (the suite's `anOffMainThreadQueryAnswersNothingAndDoesNotTrap` makes the same
// call on the real, `@MainActor` element with 0 diagnostics).
final class Element: NSAccessibilityElement {
    let bridge: Bridge
    @MainActor init(bridge: Bridge) { self.bridge = bridge; super.init() }
    override func accessibilityLabel() -> String? { mainActorAnswer(self, fallback: nil) { $0.bridge.label } }
    override func accessibilityChildren() -> [Any]? { mainActorAnswer(self, fallback: []) { [$0] } }
}

// MARK: - B. the spy

setvbuf(stdout, nil, _IOLBF, 0)
let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ax-isolation-probe.phase")

final class Spy: NSView {
    nonisolated(unsafe) var log: [String] = []
    nonisolated(unsafe) var phase = "passive"
    override var isFlipped: Bool { true }
    nonisolated func note(_ s: String) { log.append("\(phase):\(s)@\(Thread.isMainThread ? "main" : "OFF-MAIN")") }
    override func accessibilityChildren() -> [Any]? { note("children"); return [] }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { note("hitTest"); return self }
    override var accessibilityFocusedUIElement: Any? { note("focused"); return self }
    override func isAccessibilityElement() -> Bool { note("isElement"); return true }
    override func accessibilityRole() -> NSAccessibility.Role? { note("role"); return .group }
}

let args = CommandLine.arguments
if args.count >= 2, args[1] == "host" {
    MainActor.assumeIsolated {
        try? FileManager.default.removeItem(at: marker)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()   // without it every client request fails -25204
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        let spy = Spy(frame: .zero)
        w.contentView = spy
        app.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let frame = w.frame
        print("READY \(ProcessInfo.processInfo.processIdentifier) \(Int(frame.midX)) \(Int(frame.midY))")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let p = try? String(contentsOf: marker, encoding: .utf8) {
                let phase = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if phase == "DONE" { break }
                spy.phase = phase
            }
        }
        for phase in ["passive", "focused", "position"] {
            print("  \(phase): \(spy.log.filter { $0.hasPrefix(phase + ":") }.map { $0.dropFirst(phase.count + 1) })")
        }
        try? FileManager.default.removeItem(at: marker)
    }
} else if args.count >= 2, args[1] == "client", args.count >= 5, let pid = pid_t(args[2]) {
    print("client: AXIsProcessTrusted=\(AXIsProcessTrusted())")
    let app = AXUIElementCreateApplication(pid)
    func announce(_ phase: String) {
        try? phase.write(to: marker, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.3)
    }
    announce("focused")
    var focused: CFTypeRef?
    let e1 = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
    print("client: focused err=\(e1.rawValue) got=\(focused != nil)")
    announce("position")
    let screenHeight = Double(CGDisplayBounds(CGMainDisplayID()).height)
    var hit: AXUIElement?
    let e2 = AXUIElementCopyElementAtPosition(app, Float(args[3]) ?? 0,
                                              Float(screenHeight - (Double(args[4]) ?? 0)), &hit)
    print("client: position err=\(e2.rawValue) got=\(hit != nil)")
    announce("DONE")
} else if args.count >= 2, args[1] == "offmain" {
    // C. The same element, asked on the main thread (the control) and from a
    // detached thread.
    // Boxed only to hand the element to the background thread; the box's
    // `@unchecked` is this arm's deliberate violation, not the helper's.
    let boxed = MainActor.assumeIsolated { MainThreadAnswer(value: Element(bridge: Bridge())) }
    let element = boxed.value
    print("offmain: main thread label=\(element.accessibilityLabel() ?? "nil") children=\(element.accessibilityChildren()?.count ?? -1)")
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        let element = boxed.value
        print("offmain: background label=\(element.accessibilityLabel() ?? "nil") children=\(element.accessibilityChildren()?.count ?? -1) isMain=\(Thread.isMainThread)")
        done.signal()
    }
    done.wait()
    print("offmain: no trap")
} else {
    print("usage: host | client <pid> <midX> <midY> | offmain")
}
