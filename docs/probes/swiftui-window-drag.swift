// SwiftUI/AppKit probe: WindowDragGesture and the window-drag surface (rulings
// WD-* in docs/superpowers/2026-10-12-window-drag-decisions.md; spec
// docs/superpowers/specs/2026-10-12-window-drag-design.md).
//
// HOW TO RUN (compiled form, as `swiftui-input-followups.swift`):
//
//   xcrun swiftc docs/probes/swiftui-window-drag.swift -o /tmp/wd-probe && /tmp/wd-probe
//
// THE INSTRUMENT is `swiftui-input-followups.swift`'s: a `KeyWindow` hosting an
// `NSHostingView` that accepts the first mouse, `NSEvent`s through
// `NSWindow.sendEvent` with a run-loop spin between events; the probe runs every
// arm twice, the second time delivering through `NSApp.postEvent` and the
// application's own event pump (`NSApp.currentEvent` set). The window is a
// `ProbeWindow` that overrides `performDrag(with:)`, `performZoom(_:)` and
// `miniaturize(_:)` to log (never calling super: a real `performDrag` runs a
// nested tracking loop that needs live events). SwiftUI's WindowDragGesture
// calls NONE of them (all arms read no such log), so a window move is detected
// by AppKit's own stderr diagnostic instead, attributed per arm by an "ARM"
// marker written to stderr after each arm (run with `2>&1`). The positive
// control W1 must show the diagnostic and the no-gesture controls must not.
//
// ARMS. The view is a 200x200 content: a base layer carrying a gesture that
// logs ("below:..."), and a 100x100 region at the top left carrying the
// `WindowDragGesture`; the press is at (50, 50), inside both. Events: press,
// two moves, release unless stated.
//   W0 control   — no WindowDragGesture; DragGesture(minimumDistance: 0) below.
//                  Reads that the instrument delivers (below: begins/changes/ends).
//   W1 positive  — the region alone.
//   W2           — region (WindowDragGesture) in an `.overlay` above a base view
//                  carrying DragGesture(minimumDistance: 0): who wins?
//   W3           — SAME view, `.gesture(DragGesture).gesture(WindowDragGesture)`
//                  then the reverse order (W3b).
//   W4           — `.highPriorityGesture(WindowDragGesture())` over the same
//                  view's DragGesture; W4b `.simultaneousGesture`.
//   W5 separating— region over a base carrying a `TapGesture`/`SpatialTapGesture`
//                  (no movement: press, release): does the tap still fire?
//   W6           — double click (clickCount 2) in the region: performZoom?
//   W7           — secondary press (rightMouseDown/Dragged/Up) in the region.
//   W8 gates     — region with .allowsHitTesting(false); .disabled(true);
//                  .opacity(0) (hidden by opacity); .hidden(); a view with the
//                  gesture on a Color.clear (no content shape).
//   W9           — the press lands OUTSIDE the region (x 150): no drag, the
//                  base's gesture fires (separating arm for W2).
//   W11          — the region is a CHILD of a view carrying a DragGesture (the
//                  MetalCreator case: gestures on an ancestor, the handle inside);
//                  W11b with the parent's gesture high priority; W11c separating
//                  arm: the press outside the child reaches the parent.
//   W10          — `.windowBackgroundDragBehavior(.enabled)` is a SCENE modifier
//                  (interface census below), so it is read, not run, here.
//
// RECORDED 2026-10-12 by the window-drag designer, macOS 27.0.1, Apple Swift
// 6.4, screen LOCKED (the instrument is `sendEvent`, not the session; the
// input-follow-ups probe ran the same arms locked and unlocked alike).
//
// INTERFACE CENSUS (MacOSX SDK, arm64e swiftinterface, SwiftUI):
//   @available(macOS 15.0) struct WindowDragGesture : Gesture { struct Value: Equatable {}  init() }
//     — Value has no members; macOS only (iOS/tvOS/watchOS/visionOS unavailable).
//   @available(macOS 15.0) Scene.windowBackgroundDragBehavior(_ b: WindowInteractionBehavior)
//     — a SCENE modifier; WindowInteractionBehavior: .automatic .enabled .disabled
//   @available(iOS 18, macOS 15) View.allowsWindowActivationEvents(_ Bool?) — the first
//     click on an inactive window also reaches the view (not a drag API).
//
// OUTPUT, verbatim:
//
// stdout (the same under both deliveries, byte-identical across runs, md5
// 2cbb77aa2cfe92ee3ec16b5463de18c4, 58 lines, exit 0). The stderr line "Warning:
// Window move completed without beginning" (AppKit's own diagnostic, issued by
// the system window mover that SwiftUI's WindowDragGesture starts; NOT produced
// by W0, W5c, W11d or any arm with no WindowDragGesture) is the ONLY sign of a
// window move, and appeared before exactly these arms' labels (7 of 22, in both
// deliveries): W1, W2, W3b, W4, W4b, W8f, W11. `performDrag(with:)` and
// `performZoom`/`miniaturize` were never called in any arm.
//
//   === delivery: NSWindow.sendEvent
//   --- W0..W1 controls
//       W0 control: no WindowDragGesture, DragGesture below: -
//       W1 positive: region alone: -
//   --- W2..W4 who wins over a DragGesture
//       W2 overlay region above DragGesture base: -
//       W3 same view .gesture(drag).gesture(window): drag:changed | drag:changed | drag:changed | drag:ended
//       W3b same view .gesture(window).gesture(drag): drag:changed | drag:changed | drag:changed | drag:ended
//       W4 highPriority(window) over drag: drag:changed | drag:changed | drag:changed | drag:ended
//       W4b simultaneous(window) with drag: drag:changed | drag:changed | drag:changed | drag:ended
//   --- W5 a tap beneath (press, release, no move)
//       W5 region over onTapGesture base: -
//       W5c control: region replaced by clear: below:tap
//   --- W6..W7 double click, secondary
//       W6 double click (clickCount 2): -
//       W7 secondary press and drag: -
//   --- W8 gates
//       W8a allowsHitTesting(false): below:changed | below:changed | below:changed | below:ended
//       W8b disabled(true): -
//       W8c opacity(0): below:changed | below:changed | below:changed | below:ended
//       W8d hidden(): below:changed | below:changed | below:changed | below:ended
//       W8e gesture on Color.clear (no content shape): below:changed | below:changed | below:changed | below:ended
//       W8f gesture on Color.clear + contentShape: -
//   --- W11 the region is a CHILD of a view carrying a DragGesture (the viewport case)
//       W11 child region, parent .gesture(drag), press inside child: parent:changed | parent:changed | parent:changed | parent:ended
//       W11b child region, parent .highPriorityGesture(drag): parent:changed | parent:changed | parent:changed | parent:ended
//       W11c separating: same, press outside the child: parent:changed | parent:changed | parent:changed | parent:ended
//       W11d separating: child carries a plain DragGesture instead: child:changed | child:changed | child:changed | child:ended
//   --- W9 separating: press outside the region
//       W9 press at (150, 150): below:changed | below:changed | below:changed | below:ended
//
// READING (what rests on it, and what does not).
//  * W1 (positive control) moves the window by the diagnostic, so the
//    instrument sees a window drag; W0/W5c/W11d (no WindowDragGesture) never do.
//  * W2: a WindowDragGesture region OVERLAYING a DragGesture base takes the
//    press: the window moves and the base's gesture sees nothing; W9 (press
//    outside the region) is the separating arm: the base gets it, no move.
//  * It does NOT exclude the gestures it shares a view or a parent with: W3b
//    (window inner, drag outer), W4 (high priority), W4b (simultaneous) and
//    W11 (child region inside a parent DragGesture) all move the window AND
//    fire the other gesture's callbacks (W11d: a plain child DragGesture
//    excludes the parent, so the difference is the window gesture's). The
//    synthetic events do not enter the system's tracking loop, so what a REAL
//    drag does to the other gesture after the window starts moving is NOT
//    measured (human check WD-1).
//  * It loses to a DragGesture ahead of it: W3 (drag inner, window outer: no
//    move) and W11b (parent .highPriorityGesture(drag): no move).
//  * Not a tap killer: W5 the press-release with no movement moves nothing
//    and the base's tap does NOT fire either (the region occluded it); W5c
//    (region replaced by clear) fires it.
//  * W6 double click and W7 secondary press: no move; no performZoom or
//    miniaturize seen (the title bar's own double-click path may not go
//    through those methods, so "no zoom" is weak evidence).
//  * Gates: .allowsHitTesting(false), .hidden(), .opacity(0), a Color.clear with
//    no contentShape (W8a, W8c, W8d, W8e) are inert and the base gets the press;
//    .disabled(true) (W8b) is inert too but the region still swallows the press
//    (the base reads "-"); a contentShape on the clear view (W8f) makes it a
//    handle again.
//  * Not probed, and not claimed: Scene.windowBackgroundDragBehavior (a Scene
//    modifier: interface census only), allowsWindowActivationEvents.
//
import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: " | ")
    }
}

@MainActor func spin(_ s: Double = 0.12) {
    // Pump the application's own queue so a posted event is dispatched by
    // `NSApp.sendEvent` with `NSApp.currentEvent` set, as in a live session.
    let end = Date().addingTimeInterval(s)
    while Date() < end {
        if let e = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02), inMode: .default, dequeue: true) {
            NSApp.sendEvent(e)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
}

let side: CGFloat = 200

final class ProbeWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
    override func performDrag(with event: NSEvent) { Log.add("performDrag(\(event.type.rawValue))") }
    override func performZoom(_ sender: Any?) { Log.add("performZoom") }
    override func miniaturize(_ sender: Any?) { Log.add("miniaturize") }
    override func setFrameOrigin(_ p: NSPoint) { Log.add("setFrameOrigin"); super.setFrameOrigin(p) }
}

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = ProbeWindow(contentRect: CGRect(x: 200, y: 200, width: side, height: side),
                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin(0.5)
    return w
}

func wp(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: side - y) }

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint, clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: (t == .leftMouseUp || t == .rightMouseUp) ? 0 : 1)!
    if viaPost { NSApp.postEvent(e, atStart: false) } else { w.sendEvent(e) }
}
nonisolated(unsafe) var viaPost = false

func base(_ tag: String) -> some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { _ in Log.add("\(tag):changed") }
        .onEnded { _ in Log.add("\(tag):ended") }
}

struct Layered<Region: View>: View {
    let region: Region
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.red.gesture(base("below"))
            region.frame(width: 100, height: 100)
        }.frame(width: side, height: side)
    }
}

@MainActor func press(_ label: String, _ view: some View, at: CGPoint = wp(50, 50),
                      button: Int = 0, clicks: Int = 1, moves: Bool = true) {
    let w = makeWindow(view)
    _ = Log.take()
    let origin = w.frame.origin
    let (d, g, u): (NSEvent.EventType, NSEvent.EventType, NSEvent.EventType) =
        button == 0 ? (.leftMouseDown, .leftMouseDragged, .leftMouseUp)
                    : (.rightMouseDown, .rightMouseDragged, .rightMouseUp)
    mouse(w, d, at, clicks: clicks); spin()
    if moves {
        mouse(w, g, CGPoint(x: at.x + 20, y: at.y - 10), clicks: clicks); spin()
        mouse(w, g, CGPoint(x: at.x + 40, y: at.y - 20), clicks: clicks); spin()
    }
    mouse(w, u, CGPoint(x: at.x + (moves ? 40 : 0), y: at.y - (moves ? 20 : 0)), clicks: clicks); spin()
    let moved = w.frame.origin != origin ? " [window moved]" : ""
    let line = "    \(label): \(Log.take())\(moved)"
    print(line)
    // AppKit's own diagnostic is the only sign of a window move (see the
    // recorded output): echo each arm's line to stderr so a merged run
    // (`2>&1`) shows which arm produced "Window move completed without beginning".
    fputs("ARM " + label + "\n", stderr)
    w.close()
}

struct TapBelow<Region: View>: View {
    let region: Region
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.red.onTapGesture { Log.add("below:tap") }
            region.frame(width: 100, height: 100)
        }.frame(width: side, height: side)
    }
}

struct Nested: View {
    let high: Bool
    var inner: some View { Color.blue.gesture(WindowDragGesture()).frame(width: 100, height: 100) }
    var body: some View {
        Group {
            if high {
                ZStack(alignment: .topLeading) { Color.red; inner }.highPriorityGesture(base("parent"))
            } else {
                ZStack(alignment: .topLeading) { Color.red; inner }.gesture(base("parent"))
            }
        }.frame(width: side, height: side)
    }
}

struct NestedPlain: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.red
            Color.blue.gesture(base("child")).frame(width: 100, height: 100)
        }.gesture(base("parent")).frame(width: side, height: side)
    }
}

struct Both: View {
    enum Order { case dragThenWindow, windowThenDrag, high, simultaneous }
    let order: Order
    var body: some View {
        Group {
            switch order {
            case .dragThenWindow:
                Color.red.gesture(base("drag")).gesture(WindowDragGesture())
            case .windowThenDrag:
                Color.red.gesture(WindowDragGesture()).gesture(base("drag"))
            case .high:
                Color.red.gesture(base("drag")).highPriorityGesture(WindowDragGesture())
            case .simultaneous:
                Color.red.gesture(base("drag")).simultaneousGesture(WindowDragGesture())
            }
        }.frame(width: side, height: side)
    }
}

@MainActor func run() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    spin(0.4)
    for mode in [false, true] {
    viaPost = mode
    print("=== delivery: \(mode ? "NSApp.postEvent + application pump" : "NSWindow.sendEvent")")
    print("--- W0..W1 controls")
    press("W0 control: no WindowDragGesture, DragGesture below", Layered(region: Color.blue.opacity(0.01)))
    press("W1 positive: region alone", Color.blue.gesture(WindowDragGesture()).frame(width: side, height: side))
    print("--- W2..W4 who wins over a DragGesture")
    press("W2 overlay region above DragGesture base", Layered(region: Color.blue.gesture(WindowDragGesture())))
    press("W3 same view .gesture(drag).gesture(window)", Both(order: .dragThenWindow))
    press("W3b same view .gesture(window).gesture(drag)", Both(order: .windowThenDrag))
    press("W4 highPriority(window) over drag", Both(order: .high))
    press("W4b simultaneous(window) with drag", Both(order: .simultaneous))
    print("--- W5 a tap beneath (press, release, no move)")
    press("W5 region over onTapGesture base", TapBelow(region: Color.blue.gesture(WindowDragGesture())), moves: false)
    press("W5c control: region replaced by clear", TapBelow(region: Color.clear), moves: false)
    print("--- W6..W7 double click, secondary")
    press("W6 double click (clickCount 2)", Layered(region: Color.blue.gesture(WindowDragGesture())), clicks: 2, moves: false)
    press("W7 secondary press and drag", Layered(region: Color.blue.gesture(WindowDragGesture())), button: 1)
    print("--- W8 gates")
    press("W8a allowsHitTesting(false)", Layered(region: Color.blue.gesture(WindowDragGesture()).allowsHitTesting(false)))
    press("W8b disabled(true)", Layered(region: Color.blue.gesture(WindowDragGesture()).disabled(true)))
    press("W8c opacity(0)", Layered(region: Color.blue.gesture(WindowDragGesture()).opacity(0)))
    press("W8d hidden()", Layered(region: Color.blue.gesture(WindowDragGesture()).hidden()))
    press("W8e gesture on Color.clear (no content shape)", Layered(region: Color.clear.gesture(WindowDragGesture())))
    press("W8f gesture on Color.clear + contentShape", Layered(region: Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture())))
    print("--- W11 the region is a CHILD of a view carrying a DragGesture (the viewport case)")
    press("W11 child region, parent .gesture(drag), press inside child", Nested(high: false))
    press("W11b child region, parent .highPriorityGesture(drag)", Nested(high: true))
    press("W11c separating: same, press outside the child", Nested(high: false), at: wp(150, 150))
    press("W11d separating: child carries a plain DragGesture instead", NestedPlain())
    print("--- W9 separating: press outside the region")
    press("W9 press at (150, 150)", Layered(region: Color.blue.gesture(WindowDragGesture())), at: wp(150, 150))
    }
}
MainActor.assumeIsolated { run() }
