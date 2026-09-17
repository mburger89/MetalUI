// Two-process probe: which of a host view's accessibility entry points does an
// OUT-OF-PROCESS accessibility client reach, with VoiceOver off? Evidence for
// ruling AB-B's query triggers (second critic round, finding 9) in
// docs/superpowers/2026-09-15-accessibility-bridge-decisions.md.
//
// Arm Q (swiftui-accessibility-bridge-rules.swift) showed that AppKit itself
// sends a plain content view NO accessibility call through a key window, events
// and a resize, and that IN-PROCESS window queries do reach it. It could not
// say what a utility running in another process — a window manager, a
// text-expansion or grammar tool, a mouse-over dictionary — reaches. This probe
// is that client: the same `AXUIElement` calls such utilities make, against a
// spy window in a second process.
//
// HOW TO RUN (the client needs the Accessibility permission for the process
// that runs it; `AXIsProcessTrusted()` is printed first, and an untrusted client
// reads nothing, so its line is the precondition):
//
//   /usr/bin/swift docs/probes/appkit-accessibility-activation-clients.swift host > /tmp/ax-host.log 2>&1 &
//   sleep 6   # the host prints READY <pid> after its idle phase
//   /usr/bin/swift docs/probes/appkit-accessibility-activation-clients.swift client $(awk '/^READY/{print $2, $3, $4}' /tmp/ax-host.log)
//   wait; grep -v 'warning:\|^ *[0-9]* |\|^ *|\|note:' /tmp/ax-host.log
//
// The host activates itself and makes its window key (the focused-element
// query needs a focused app), idles 4 s logging every entry-point call
// (the PASSIVE phase: any call there is a system service, not the client),
// prints READY, then keeps logging until the client prints DONE (it polls a
// marker file) and prints its log with each call tagged by the client phase
// that preceded it.
//
// Client phases, one AX request each, 0.5 s apart, each announced to the host
// through the marker file BEFORE the request:
//   1. windows      kAXWindowsAttribute on the application element
//   2. focused      kAXFocusedUIElementAttribute on the application element
//                   (what a system-wide focused-element poll resolves to once
//                   it has picked the frontmost app)
//   3. position     AXUIElementCopyElementAtPosition at the window's centre
//                   (mouse-follow utilities)
//   4. children     kAXChildrenAttribute on the first element of phase 1's list
//   5. contentChildren
//                   kAXChildrenAttribute on the elements phases 2 and 3
//                   returned, with their roles
//
// CONTROLS. The PASSIVE phase and phase 1 read [] while phases 2 and 3 reach
// the spy: so the spy sees an out-of-process request when one arrives, and an
// empty phase is not a spy that cannot see. A first run without
// `finishLaunching()` read [] in EVERY phase, with every client request failing
// -25204 (kAXErrorCannotComplete): that is what a broken harness looks like
// here, and it is why the line is there.
//
// LIMIT, measured and not worked around. Phases 4 and 5 were meant as the
// tree-walk positive control (a client reading the content view's children)
// and never reached the spy: the elements the client got back resolve to
// `AXApplication` (printed), because the script process could not activate
// itself (`key=false`, start and end), so a client here cannot walk into the
// window. So this probe measures the FOCUSED-ELEMENT and POSITION entry points
// only; that a tree walk reaches `accessibilityChildren` is arm Q's in-process
// positive control, not this probe's.
//
// RECORDED 2026-09-15 by the accessibility-bridge design session (second critic
// round), macOS 26.6.2 (25G83), /usr/bin/swift = Apple Swift 6.4
// (swiftlang-6.4.0.33.1), VoiceOver off:
//
//   client: AXIsProcessTrusted=true
//   client: windows err=0 count=1
//   client: focused err=0 got=true
//   client: position err=0 got=true
//   client: children err=0 count=2
//   client: contentChildren of AXApplication err=0 count=2
//   client: contentChildren of AXApplication err=0 count=2
//   host: isVoiceOverEnabled=false key=false
//   READY 95165 350 316
//   host: key at end=false
//     passive: []
//     windows: []
//     focused: ["focused", "isElement"]
//     position: ["hitTest", "children", "role", "isElement"]
//     children: []
//     contentChildren: []

import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IOLBF, 0)
let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ax-activation-probe.phase")

final class Spy: NSView {
    var log: [String] = []
    var phase = "passive"
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    func note(_ s: String) { log.append("\(phase):\(s)") }
    override func accessibilityChildren() -> [Any]? { note("children"); return super.accessibilityChildren() }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { note("hitTest"); return super.accessibilityHitTest(point) }
    override var accessibilityFocusedUIElement: Any? { note("focused"); return super.accessibilityFocusedUIElement }
    override func isAccessibilityElement() -> Bool { note("isElement"); return true }
    override func accessibilityRole() -> NSAccessibility.Role? { note("role"); return .group }
}

let args = CommandLine.arguments
if args.count >= 2, args[1] == "host" {
    MainActor.assumeIsolated {
        try? FileManager.default.removeItem(at: marker)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        // A real app has finished launching; without this the process is not
        // registered with the accessibility server and every client request
        // fails with kAXErrorCannotComplete (-25204), observed on the first run.
        app.finishLaunching()
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        let spy = Spy(frame: .zero)
        w.contentView = spy
        app.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(spy)
        print("host: isVoiceOverEnabled=\(NSWorkspace.shared.isVoiceOverEnabled) key=\(w.isKeyWindow)")
        RunLoop.main.run(until: Date().addingTimeInterval(4))
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
        print("host: key at end=\(w.isKeyWindow)")
        for phase in ["passive", "windows", "focused", "position", "children", "contentChildren"] {
            print("  \(phase): \(spy.log.filter { $0.hasPrefix(phase + ":") }.map { $0.dropFirst(phase.count + 1) })")
        }
        try? FileManager.default.removeItem(at: marker)
    }
} else if args.count >= 2, args[1] == "client", args.count >= 3, let pid = pid_t(args[2]) {
    print("client: AXIsProcessTrusted=\(AXIsProcessTrusted())")
    let app = AXUIElementCreateApplication(pid)
    func announce(_ phase: String) {
        try? phase.write(to: marker, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.3)
    }
    func copy(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (err, value)
    }
    announce("windows")
    let (e1, windows) = copy(app, kAXWindowsAttribute)
    let windowList = (windows as? [AXUIElement]) ?? []
    print("client: windows err=\(e1.rawValue) count=\(windowList.count)")
    announce("focused")
    let (e2, focused) = copy(app, kAXFocusedUIElementAttribute)
    print("client: focused err=\(e2.rawValue) got=\(focused != nil)")
    announce("position")
    // Screen coordinates for AX are top-left origin; the host printed its frame
    // centre in AppKit's bottom-left space, so flip against the main screen.
    let mx = Float(args.count >= 4 ? Double(args[3]) ?? 0 : 0)
    let myAppKit = Double(args.count >= 5 ? args[4] : "0") ?? 0
    let screenHeight = Double(CGDisplayBounds(CGMainDisplayID()).height)
    var hit: AXUIElement?
    let e3 = AXUIElementCopyElementAtPosition(app, mx, Float(screenHeight - myAppKit), &hit)
    print("client: position err=\(e3.rawValue) got=\(hit != nil)")
    announce("children")
    if let window = windowList.first {
        let (e4, kids) = copy(window, kAXChildrenAttribute)
        print("client: children err=\(e4.rawValue) count=\(((kids as? [AXUIElement]) ?? []).count)")
    } else {
        print("client: children skipped, no window")
    }
    announce("contentChildren")
    // The element phase 3 hit (the spy's content view: role read here, so
    // `role`/`isElement` in this phase's log are expected); `children` is the
    // entry point this phase is about.
    // Phase 2's focused element is tried first, then phase 3's hit.
    for candidate in [focused.map { $0 as! AXUIElement }, hit].compactMap({ $0 }) {
        let content = candidate
        let (_, role) = copy(content, kAXRoleAttribute)
        let (e5, grandkids) = copy(content, kAXChildrenAttribute)
        print("client: contentChildren of \(role as? String ?? "nil") err=\(e5.rawValue) count=\(((grandkids as? [AXUIElement]) ?? []).count)")
    }
    announce("DONE")
} else {
    print("usage: host | client <pid> <midX> <midY>")
}
