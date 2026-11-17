// SwiftUI probe: focus and Escape for a TextField inside `.popover` (ruling CV-BW in
// docs/superpowers/2026-11-07-code-view-decisions.md; evidence for the follow-up MN-AS, "a popover returns focus on
// dismiss", and for the order of the key stages in MetalUI's text-anchored popover).
//
// HOW TO RUN (compiled form, SA-O; needs an UNLOCKED screen, see below):
//
//   xcrun swiftc docs/probes/swiftui-popover-focus.swift -o /tmp/popover-focus
//   /tmp/popover-focus
//
// THE INSTRUMENT. An NSApplication with a titled NSWindow hosting a SwiftUI view (`NSHostingView`) with a focusable
// `TextField("main")` and a button-less presenter; a `.popover(isPresented:)` holding a `TextField("pop")` is presented by
// flipping an observable flag. Everything is read back from AppKit: `NSWindow.firstResponder` (the field editor's
// delegate is the field), `isKeyWindow`, and the `@FocusState` value the presenter's body last saw. Escape is a
// synthesized key-down NSEvent handed to the key window's `sendEvent`.
//
// ARMS.
//   PF1  does the TextField in the popover become first responder on open, with no `@FocusState` anywhere in it?
//   PF2  after the dismissal, is the presenter's previously focused field first responder again, and does its
//        `@FocusState` read true?
//   PF3  does `onKeyPress(.escape)` on the popover's field run before the popover closes?
// POSITIVE CONTROLS. C1: the presenter's `main` field is made first responder by `makeFirstResponder`, and the probe
// reads that back before anything opens (an instrument that cannot see a focused field would also print "no"). C2: a
// `onKeyPress(.escape)` on the PRESENTER's field, with no popover, runs on a synthesized Escape (an instrument that
// cannot deliver Escape would also print "did not run").
//
// WHAT A LOCKED SCREEN COSTS. As in MN-N P3 (docs/probes/swiftui-menus-popovers.swift), on a locked screen the app never
// becomes active and no window becomes key (`isKeyWindow` false, `NSApp.keyWindow` nil even after `makeKey`); then the
// first-responder arms are NOT answered. The probe prints `KEY-WINDOW-UNAVAILABLE` and each arm prints `UNRESOLVED`
// instead of a verdict. Nothing is inferred.
//
// RECORDED 2026-11-17, macOS 27.2, Apple Swift 6.4, screen LOCKED (`ioreg -n Root -d1 -a`:
// CGSSessionScreenIsLocked = true). Compiled form, run once, exit 0. It compiles; no arm is answered:
//
//   main window key=false appActive=false keyWindow=nil
//   KEY-WINDOW-UNAVAILABLE: no window became key (locked screen or no session), the arms are not answered
//   C1 UNRESOLVED
//   C2 UNRESOLVED
//   PF1 UNRESOLVED
//   PF2 UNRESOLVED
//   PF3 UNRESOLVED
//
// So PF1, PF2 and PF3 are OPEN, not "no": the same failure as MN-N P3. Human checks MN-PF1..MN-PF3 in
// docs/verification/human-checks.md carry them; re-run this probe on an unlocked screen and paste its output here.

import SwiftUI
import AppKit

@MainActor final class Model: ObservableObject {
    @Published var shown = false
    var mainFocusReads: [Bool] = []
    var escapeRuns = 0
    var escapeResult: KeyPress.Result = .ignored
}

struct Presenter: View {
    @ObservedObject var m: Model
    @FocusState var mainFocused: Bool
    @State var main = ""
    @State var pop = ""
    var body: some View {
        let _ = { m.mainFocusReads.append(mainFocused) }()
        VStack {
            TextField("main", text: $main).focused($mainFocused)
                .onKeyPress(.escape) { m.escapeRuns += 100; return .ignored }
                .popover(isPresented: Binding(get: { m.shown }, set: { m.shown = $0 })) {
                    TextField("pop", text: $pop)
                        .onKeyPress(.escape) { m.escapeRuns += 1; return m.escapeResult }
                        .frame(width: 160, height: 30).padding(8)
                }
        }.frame(width: 300, height: 120)
    }
}

func spin(_ seconds: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds)) }

func responderName(_ w: NSWindow?) -> String {
    guard let r = w?.firstResponder else { return "nil" }
    if let tv = r as? NSTextView, tv.isFieldEditor, let d = tv.delegate as? NSObject { return "fieldEditor(\(type(of: d)))" }
    return "\(type(of: r))"
}

func escapeEvent(_ w: NSWindow) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                     windowNumber: w.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                     isARepeat: false, keyCode: 53)!
}

@MainActor func run() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let m = Model()
    let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: Presenter(m: m))
    w.contentView = host
    app.activate(ignoringOtherApps: true)
    w.orderFrontRegardless(); w.makeKey(); host.layoutSubtreeIfNeeded(); spin(0.5)
    print("main window key=\(w.isKeyWindow) appActive=\(app.isActive) keyWindow=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil")")
    guard w.isKeyWindow else {
        print("KEY-WINDOW-UNAVAILABLE: no window became key (locked screen or no session), the arms are not answered")
        for a in ["C1", "C2", "PF1", "PF2", "PF3"] { print("\(a) UNRESOLVED") }
        return
    }
    // C1: make the presenter's field first responder, read it back.
    func firstTextField(_ v: NSView) -> NSTextField? {
        if let t = v as? NSTextField, t.isEditable { return t }
        for s in v.subviews { if let f = firstTextField(s) { return f } }
        return nil
    }
    if let f = firstTextField(host) { w.makeFirstResponder(f); spin(0.3) }
    print("C1 presenter field made first responder: \(responderName(w)) @FocusState main=\(m.mainFocusReads.last.map(String.init) ?? "nil")")
    // C2: Escape on the presenter's field, no popover.
    w.sendEvent(escapeEvent(w)); spin(0.3)
    print("C2 presenter onKeyPress(.escape) with no popover: runs=\(m.escapeRuns) (100 per run)")
    m.escapeRuns = 0

    // PF1 / PF2 / PF3.
    m.shown = true; spin(0.8)
    let popWindows = NSApp.windows.filter { "\(type(of: $0))".contains("Popover") }
    let pw = popWindows.first
    print("PF1 popover open: shown=\(m.shown) popoverWindow=\(pw.map { "\(type(of: $0)) key=\($0.isKeyWindow)" } ?? "none")")
    print("PF1 first responder: popoverWindow=\(responderName(pw)) mainWindow=\(responderName(w)) keyWindow=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil")")
    let target = (NSApp.keyWindow ?? pw) ?? w
    target.sendEvent(escapeEvent(target)); spin(0.5)
    print("PF3 Escape sent to \(type(of: target)): popoverFieldHandlerRuns=\(m.escapeRuns) shown=\(m.shown)")
    if m.shown { m.shown = false; spin(0.5) }
    print("PF2 after dismiss: mainWindow key=\(w.isKeyWindow) firstResponder=\(responderName(w)) @FocusState main=\(m.mainFocusReads.last.map(String.init) ?? "nil")")
}

MainActor.assumeIsolated { run() }
