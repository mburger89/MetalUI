// SwiftUI probe: what resigns a focused TextField on a press (rulings RF-* in
// docs/superpowers/2026-10-12-resign-on-press-decisions.md; spec
// docs/superpowers/specs/2026-10-12-resign-on-press-design.md).
//
// HOW TO RUN (compiled form, as `swiftui-key-focus.swift`, whose instrument
// this file reuses unchanged: a `FirstMouseHost` in a `KeyWindow`, `NSEvent`s
// through `NSWindow.sendEvent`, a run-loop spin between events):
//
//   xcrun swiftc docs/probes/swiftui-resign-on-press.swift -o /tmp/rp-probe && /tmp/rp-probe
//
// Window coordinates have their origin at the BOTTOM left; the window is 200x200.
// RP0/RP1 are the controls (RP1 repeats key-focus probe arm RS1: a press on a
// plain colour resigns nothing); every other arm separates one candidate.
//
// RECORDED 2026-10-12 by the resign-on-press (C24) designer, macOS 27.0.1
// (26A434), Apple Swift 6.4, compiled form, run three times, stdout
// byte-identical (14 lines), exit 0. SCREEN LOCKED (lock probe printed
// CGSSessionScreenIsLocked = 1, `displayAsleep main: 1`): the synthetic
// events still reach the window and RP0/RP1 reproduce key-focus probe arms RS0
// and RS1 exactly, which is the check that the locked screen did not move this
// instrument; human check RF-1 repeats the answer with a real mouse.
//
// macOS Version 27.0.1 (Build 26A434)
// --- RP: what resigns a focused TextField on a press
//   RP0 field focused in onAppear, no click (control): focused=true,|start
//   RP1 click plain Color (RS1 repeated, control): focused=true,|start
//   RP2 Color.onTapGesture { focused = false }, click it: focused=true,|start,tap,focused=false
//   RP3 .focusable(false) on the Color, click it: focused=true,|start
//   RP4 .focusEffectDisabled() on the Color, click it: focused=true,|start
//   RP5 two fields A focused; press field B (no wrapper, control): focus=a,|start,focus=b
//   RP6 two fields; whole-stack .onTapGesture { tap }, press grey: focus=a,|start,tap
//   RP7 two fields; whole-stack .onTapGesture { tap }, press field B: focus=a,|start,focus=b
//   RP8 two fields; whole-stack simultaneousGesture(Tap { tap }), press field B: focus=a,|start,focus=b,tap
//   RP9 Color.onTapGesture, SECONDARY press on it: focused=true,|start,tap,focused=false
//   RP10 Color.onTapGesture.disabled(true), click it: focused=true,|start
//   RP11 Color.onTapGesture.allowsHitTesting(false), click it: focused=true,|start
//   RP12 Color.onTapGesture.hidden(), click it: focused=true,|start
//
// RESULT. SwiftUI has NO "resign on press" modifier: RP1 (plain colour), RP3
// (`.focusable(false)`) and RP4 (`.focusEffectDisabled()`) leave `focused=true`. The only way to end a field's editing
// from a press is code in a tap handler (RP2: `focused=false` after `tap`).
// A press on another field moves focus directly, a -> b with no nil between
// (RP5); a container tap does not fire for a press a field takes (RP7), but a
// `simultaneousGesture` tap does, AFTER the focus moved (RP8), so a naive
// `focus = nil` there would clear the field just focused: the exemption of
// text fields and click-focusable elements is what the MetalUI modifier must
// add. `.disabled`, `.allowsHitTesting(false)` and `.hidden()` each stop the
// region's tap (RP10-RP12). RP9 (a secondary press fires `onTapGesture`)
// is read as the instrument's, not as a ruling: NSEvent right-button events
// synthesized through `sendEvent` reach SwiftUI's primary tap recogniser; the
// MetalUI side is ruled by MN-B (a secondary press never focuses) alone.
//
import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.3)
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p); spin(0.05); mouse(w, .leftMouseUp, p); spin()
}

@MainActor func keyEvent(_ w: NSWindow, _ type: NSEvent.EventType, _ chars: String,
                         modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16, repeat isRepeat: Bool = false) {
    let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                             timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                             context: nil, characters: chars, charactersIgnoringModifiers: chars,
                             isARepeat: isRepeat, keyCode: keyCode)!
    NSApp.sendEvent(e)
    spin()
}

@MainActor func key(_ w: NSWindow, _ chars: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) {
    keyEvent(w, .keyDown, chars, modifiers: modifiers, keyCode: keyCode)
    keyEvent(w, .keyUp, chars, modifiers: modifiers, keyCode: keyCode)
}

let up = "\u{F700}"
let centre = CGPoint(x: 100, y: 100)
let topPoint = CGPoint(x: 100, y: 185)     // a 200x30 field pinned to the top
let bottomPoint = CGPoint(x: 100, y: 40)

@MainActor func arm<V: View>(_ label: String, _ view: V, _ act: (NSWindow) -> Void) {
    _ = Log.take()
    let w = makeWindow(view)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
    w.contentView = nil   // stop the hosting view (a TimelineView kept evaluating after orderOut, run 1)
}


// MARK: - RP: what resigns a focused TextField on a press, in SwiftUI?

struct RPOne<Region: View>: View {
    @State var text = "abc"
    @FocusState var focused: Bool
    let region: (FocusState<Bool>.Binding) -> Region
    var body: some View {
        VStack(spacing: 0) {
            TextField("f", text: $text).focused($focused).frame(height: 30)
            region($focused)
        }
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

enum Field: Hashable { case a, b }

struct RPTwo<Wrap: ViewModifier>: View {
    @State var ta = "a"
    @State var tb = "b"
    @FocusState var focus: Field?
    let wrap: Wrap
    var body: some View {
        VStack(spacing: 0) {
            TextField("a", text: $ta).focused($focus, equals: .a).frame(height: 30)
            TextField("b", text: $tb).focused($focus, equals: .b).frame(height: 30)
            Color.gray
        }
        .modifier(wrap)
        .onAppear { focus = .a }
        .onChange(of: focus) { _, v in Log.add("focus=\(v.map { "\($0)" } ?? "nil")") }
    }
}

struct ResignOnTap: ViewModifier {
    let set: @MainActor () -> Void
    func body(content: Content) -> some View { content.onTapGesture { set() } }
}
struct PlainWrap: ViewModifier { func body(content: Content) -> some View { content } }
struct SimWrap: ViewModifier {
    let set: @MainActor () -> Void
    func body(content: Content) -> some View { content.simultaneousGesture(TapGesture().onEnded { set() }) }
}

@MainActor func rightClick(_ w: NSWindow, at p: CGPoint) {
    let e = NSEvent.mouseEvent(with: .rightMouseDown, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 1)!
    w.sendEvent(e); spin(0.05)
    let u = NSEvent.mouseEvent(with: .rightMouseUp, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: 0)!
    w.sendEvent(u); spin()
}

// Window is 200x200: field A at the top (y 170-200 in window coordinates),
// field B below it (140-170), grey below that.
let pointA = CGPoint(x: 100, y: 185)
let pointB = CGPoint(x: 100, y: 155)

@MainActor func armRP() {
    print("--- RP: what resigns a focused TextField on a press")
    arm("RP0 field focused in onAppear, no click (control)", RPOne { _ in Color.gray }) { _ in Log.add("|start") }
    arm("RP1 click plain Color (RS1 repeated, control)", RPOne { _ in Color.gray }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP2 Color.onTapGesture { focused = false }, click it", RPOne { f in
        Color.gray.onTapGesture { f.wrappedValue = false; Log.add("tap") } }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP3 .focusable(false) on the Color, click it", RPOne { _ in Color.gray.focusable(false) }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP4 .focusEffectDisabled() on the Color, click it", RPOne { _ in Color.gray.focusEffectDisabled() }
        ) { w in Log.add("|start"); click(w, at: bottomPoint) }
    arm("RP5 two fields A focused; press field B (no wrapper, control)", RPTwo(wrap: PlainWrap())) { w in
        Log.add("|start"); click(w, at: pointB)
    }
    arm("RP6 two fields; whole-stack .onTapGesture { tap }, press grey", RPTwo(wrap: ResignOnTap { Log.add("tap") })) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP7 two fields; whole-stack .onTapGesture { tap }, press field B", RPTwo(wrap: ResignOnTap { Log.add("tap") })) { w in
        Log.add("|start"); click(w, at: pointB)
    }
    arm("RP8 two fields; whole-stack simultaneousGesture(Tap { tap }), press field B", RPTwo(wrap: SimWrap { Log.add("tap") })) { w in
        Log.add("|start"); click(w, at: pointB)
    }
    arm("RP9 Color.onTapGesture, SECONDARY press on it", RPOne { f in
        Color.gray.onTapGesture { f.wrappedValue = false; Log.add("tap") } }) { w in
        Log.add("|start"); rightClick(w, at: bottomPoint)
    }
    arm("RP10 Color.onTapGesture.disabled(true), click it", RPOne { f in
        Color.gray.onTapGesture { f.wrappedValue = false; Log.add("tap") }.disabled(true) }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP11 Color.onTapGesture.allowsHitTesting(false), click it", RPOne { f in
        Color.gray.onTapGesture { f.wrappedValue = false; Log.add("tap") }.allowsHitTesting(false) }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
    arm("RP12 Color.onTapGesture.hidden(), click it", RPOne { f in
        Color.gray.onTapGesture { f.wrappedValue = false; Log.add("tap") }.hidden() }) { w in
        Log.add("|start"); click(w, at: bottomPoint)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    armRP()
}
exit(0)
