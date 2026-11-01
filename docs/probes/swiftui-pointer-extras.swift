// SwiftUI/AppKit probe: pointer extras (rulings PH-* in
// docs/superpowers/2026-11-01-pointer-extras-decisions.md).
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-input-apis.swift`):
//
//   xcrun swiftc docs/probes/swiftui-pointer-extras.swift -o /tmp/ph-probe && /tmp/ph-probe
//
// THE INSTRUMENT is `swiftui-input-apis.swift`'s P arms: a `FirstMouseHost`
// window, the pointer moved by `NSEvent`s, `cursorUpdate`/`mouseMoved` driven
// into every cursor-update tracking area under the point (a synthesized move
// does not reach AppKit's own cursor tracking), then `NSCursor.current` read.
// The control P00/P0 are `swiftui-input-apis.swift`'s.
//
// ARMS AND THEIR CONTROLS.
//   D  — columnResize(directions:) and rowResize(directions:): which NSCursor
//        each direction set gives. D0 (the plain `.columnResize`) is the
//        control; D4/D9 (the empty set) is the "what does nothing mean" arm.
//   V  — pointerVisibility(_:): NSCursor.current after the move, plus
//        `CGCursorIsVisible()`; V1 (no modifier) is the control. V5/V6 nest an
//        inner modifier inside an outer one, V7 puts it with a pointerStyle.
//
// RECORDED 2026-11-01 by the pointer-extras designer, macOS 27.2 (26B123), Xcode SDK
// MacOSX27.2, screen UNLOCKED, session able to run windows. Compiled form, run
// twice after the instrument settled: stdout byte-identical (compared with cmp),
// exit 0, stderr empty. `over[...]` is the call tally of the swizzled hide/unhide/
// setHiddenUntilMouseMoves while the pointer is over the view, `after-leaving[...]`
// the tally after the pointer moved to a point outside it (omitted below: it read
// hide=1 unhide=1 for every arm that hid, and 0/0 for the rest). `V0` is the
// instrument's positive control: a direct NSCursor.hide() counts. D4/D9: the
// empty direction set shows the arrow. V7: the pointing hand AND a hide.
//
// INSTRUMENT HISTORY (discarded runs, not answers). Run 1 read `CGCursorIsVisible()`
// (unavailable since macOS 10.9: compile error) and then a private CGS symbol
// (not found: "?") - discarded; hiding is read by swizzling the three
// NSCursor class methods. Run 2 read NSCursor.current AFTER the pointer left the
// view (every arm read `arrow`) and its tallies were cumulative across arms -
// discarded; each arm now resets the tallies and reads the cursor before leaving.
//
// OUTPUT (after-leaving columns trimmed):
//     V0 NSCursor.hide() (instrument control): calls[hide=1 unhide=0 untilMove=0]
//     V00 after unhide: calls[hide=1 unhide=1 untilMove=0]
//   --- D: column/row resize directions
//     D0 .columnResize (control): current=resizeLeftRight=columnResize=columnResize(.all) over[hide=0 unhide=0 untilMove=0]
//     D1 .columnResize(directions: .all): current=resizeLeftRight=columnResize=columnResize(.all) over[hide=0 unhide=0 untilMove=0]
//     D2 .columnResize(directions: .leading): current=resizeLeft=columnResize(.left) over[hide=0 unhide=0 untilMove=0]
//     D3 .columnResize(directions: .trailing): current=resizeRight=columnResize(.right) over[hide=0 unhide=0 untilMove=0]
//     D4 .columnResize(directions: []): current=arrow over[hide=0 unhide=0 untilMove=0]
//     D5 .rowResize (control): current=resizeUpDown=rowResize=rowResize(.all) over[hide=0 unhide=0 untilMove=0]
//     D6 .rowResize(directions: .all): current=resizeUpDown=rowResize=rowResize(.all) over[hide=0 unhide=0 untilMove=0]
//     D7 .rowResize(directions: .up): current=resizeUp=rowResize(.up) over[hide=0 unhide=0 untilMove=0]
//     D8 .rowResize(directions: .down): current=resizeDown=rowResize(.down) over[hide=0 unhide=0 untilMove=0]
//     D9 .rowResize(directions: []): current=arrow over[hide=0 unhide=0 untilMove=0]
//   --- V: pointerVisibility
//     V1 no modifier (control): current=arrow over[hide=0 unhide=0 untilMove=0]
//     V2 .pointerVisibility(.hidden): current=arrow over[hide=1 unhide=0 untilMove=0]
//     V3 .pointerVisibility(.visible): current=arrow over[hide=0 unhide=0 untilMove=0]
//     V4 .pointerVisibility(.automatic): current=arrow over[hide=0 unhide=0 untilMove=0]
//     V5 outer .hidden, inner 40x40 .visible, over inner: current=arrow over[hide=0 unhide=0 untilMove=0]
//     V6 outer .hidden, inner 40x40 .automatic, over inner: current=arrow over[hide=1 unhide=0 untilMove=0]
//     V7 .hidden with .pointerStyle(.link): current=pointingHand over[hide=1 unhide=0 untilMove=0]
//     V7c .pointerStyle(.link) alone (control for V7): current=pointingHand over[hide=0 unhide=0 untilMove=0]
//     V7b .pointerVisibility(.hidden) then .pointerStyle(.link): current=pointingHand over[hide=1 unhide=0 untilMove=0]
//     V8 outer .hidden, pointer off the inner square (control): current=arrow over[hide=1 unhide=0 untilMove=0]
//     V9 outer .hidden, an opaque 40x40 onTapGesture sibling over the pointer: current=arrow over[hide=0 unhide=0 untilMove=0]


import SwiftUI
import AppKit

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Log {
    nonisolated(unsafe) static var lines: [String] = []
    nonisolated(unsafe) static var phase = ""
    static func add(_ s: String) { lines.append(s) }
    static func take() -> String {
        defer { lines = [] }
        return lines.isEmpty ? "-" : lines.joined(separator: " | ")
    }
}

func f(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
func p(_ v: CGPoint) -> String { "(\(f(v.x)), \(f(v.y)))" }

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

let side: CGFloat = 200

/// Reads as key: this unbundled accessory process's windows are never key
/// (the screen may be locked), and `pointerStyle`'s tracking area is
/// `.activeInKeyWindow` (the P arms print its options, 0x222).
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var canBecomeKey: Bool { true }
}

@MainActor func makeWindow(_ content: NSView) -> NSWindow {
    let w = KeyWindow(contentRect: CGRect(x: 200, y: 200, width: side, height: side),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = content
    w.makeKeyAndOrderFront(nil)
    spin(0.6)
    return w
}

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow { makeWindow(FirstMouseHost(rootView: view)) }


/// A window point (y up) for a top-left-origin content point.
func wp(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: side - y) }

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ pt: CGPoint, flags: NSEvent.ModifierFlags = [],
                      clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: flags,
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: (t == .leftMouseUp || t == .rightMouseUp) ? 0 : 1)!
    w.sendEvent(e)
}


struct Offset<C: View>: View {
    let content: C
    var body: some View {
        content.frame(width: 100, height: 100)
            .padding(.leading, 40).padding(.top, 30)
            .frame(width: side, height: side, alignment: .topLeading)
    }
}

// MARK: - P: pointer style

final class CrosshairView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a); area = a
    }
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }
}

@MainActor func cursorName(_ c: NSCursor) -> String {
    let known: [(String, NSCursor)] = [
        ("arrow", .arrow), ("crosshair", .crosshair), ("openHand", .openHand), ("closedHand", .closedHand),
        ("pointingHand", .pointingHand), ("IBeam", .iBeam), ("IBeamVertical", .iBeamCursorForVerticalLayout),
        ("resizeLeftRight", .resizeLeftRight), ("resizeUpDown", .resizeUpDown),
        ("columnResize", .columnResize), ("rowResize", .rowResize), ("zoomIn", .zoomIn), ("zoomOut", .zoomOut),
        ("frameResize(.trailing)", .frameResize(position: .right, directions: .all)),
    ]
    let names = known.filter { $0.1 == c }.map(\.0)
    return names.isEmpty ? "other(size=\(c.image.size) hot=\(c.hotSpot))" : names.joined(separator: "=")
}

/// Drives cursor updates directly: AppKit sends `cursorUpdate(with:)` to a
/// tracking area's owner from the window server's pointer tracking, which a
/// synthesized `mouseMoved` does not reach (the first run's control P0 read
/// `arrow`). So every `.cursorUpdate` tracking area in `w`'s view tree whose
/// rect contains the point has its owner sent `cursorUpdate(with:)` with an
/// `.cursorUpdate` event, innermost view last — what AppKit does for the
/// area under the pointer — and `NSCursor.current` is read after.
@MainActor func driveCursorUpdate(_ w: NSWindow, at pt: CGPoint) -> Int {
    var count = 0
    func visit(_ v: NSView) {
        for area in v.trackingAreas where area.options.contains(.cursorUpdate) {
            let rect = area.options.contains(.inVisibleRect) ? v.visibleRect : area.rect
            guard rect.contains(v.convert(pt, from: nil)), let owner = area.owner as? NSObject,
                  owner.responds(to: #selector(NSResponder.cursorUpdate(with:))) else { continue }
            if let e = NSEvent.enterExitEvent(with: .cursorUpdate, location: pt, modifierFlags: [],
                                              timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                              trackingNumber: 0, userData: nil) {
                owner.perform(#selector(NSResponder.cursorUpdate(with:)), with: e)
                count += 1
            }
        }
        // `pointerStyle`'s own area is mouse-moved/entered only (0x222): hand
        // its owner the move AppKit would.
        for area in v.trackingAreas where area.options.contains(.mouseMoved) && !area.options.contains(.cursorUpdate) {
            guard let owner = area.owner as? NSObject else { continue }
            for (sel, type) in [(#selector(NSResponder.mouseEntered(with:)), NSEvent.EventType.mouseEntered),
                                (#selector(NSResponder.mouseMoved(with:)), NSEvent.EventType.mouseMoved)]
                where owner.responds(to: sel) {
                let e = type == .mouseMoved
                    ? NSEvent.mouseEvent(with: .mouseMoved, location: pt, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                         clickCount: 0, pressure: 0)
                    : NSEvent.enterExitEvent(with: .mouseEntered, location: pt, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                             trackingNumber: 0, userData: nil)
                if let e { owner.perform(sel, with: e); count += 1 }
            }
            Log.add("owner=\(type(of: owner))")
        }
        v.subviews.forEach(visit)
    }
    if let root = w.contentView { visit(root) }
    // And the mouseMoved/cursorUpdate a real pointer move hands the view under
    // it, sent to the hit view and to the content view directly (a
    // synthesized `mouseMoved` through `sendEvent` goes to the first responder).
    if let root = w.contentView,
       let move = NSEvent.mouseEvent(with: .mouseMoved, location: pt, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                     clickCount: 0, pressure: 0) {
        let hit = root.hitTest(root.superview?.convert(pt, from: nil) ?? pt)
        for v in [root, hit].compactMap({ $0 }) {
            v.mouseMoved(with: move)
            if let cu = NSEvent.enterExitEvent(with: .cursorUpdate, location: pt, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                               trackingNumber: 0, userData: nil) {
                v.cursorUpdate(with: cu)
            }
        }
        spin(0.1)
    }
    return count
}

/// `at` is a content point (top-left origin); the default (60,60) is local
/// (20,30) of the 100x100 view; (90,80) is its centre (50,50).
@MainActor func pointerArm<V: View>(_ label: String, _ view: V, at c: CGPoint = CGPoint(x: 60, y: 60)) {
    NSCursor.arrow.set()
    let w = makeWindow(Offset(content: view))
    mouse(w, .mouseMoved, wp(c.x, c.y)); spin(0.1)
    var n = driveCursorUpdate(w, at: wp(c.x, c.y)); spin(0.5)
    n += driveCursorUpdate(w, at: wp(c.x + 2, c.y + 1)); spin(0.5)
    let areas = w.contentView.map { v in v.trackingAreas.map { String($0.options.rawValue, radix: 16) } } ?? []
    print("  \(label): current=\(cursorName(NSCursor.current)) (events to owners: \(n), host tracking areas: \(areas) \(Log.take()))")
    w.orderOut(nil)
}


// MARK: - arms

/// The instrument for visibility: SwiftUI's hide, if it goes through AppKit,
/// goes through `+[NSCursor hide]`/`unhide`/`setHiddenUntilMouseMoves:`, which
/// are swizzled to count calls (the public CoreGraphics visibility query is
/// unavailable since 10.9 and the private one was not found). V0 is the
/// control: a direct `NSCursor.hide()` must count.
enum Hides {
    nonisolated(unsafe) static var hides = 0, unhides = 0, untilMove = 0
}
@MainActor func swizzleHides() {
    func swap(_ sel: Selector, _ block: Any) {
        guard let m = class_getClassMethod(NSCursor.self, sel) else { return }
        let orig = method_getImplementation(m)
        _ = orig
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
    swap(NSSelectorFromString("hide"), { (_: AnyObject) in Hides.hides += 1 } as @convention(block) (AnyObject) -> Void)
    swap(NSSelectorFromString("unhide"), { (_: AnyObject) in Hides.unhides += 1 } as @convention(block) (AnyObject) -> Void)
    swap(NSSelectorFromString("setHiddenUntilMouseMoves:"), { (_: AnyObject, _: Bool) in Hides.untilMove += 1 } as @convention(block) (AnyObject, Bool) -> Void)
}
func cursorVisible() -> String { "hide=\(Hides.hides) unhide=\(Hides.unhides) untilMove=\(Hides.untilMove)" }

@MainActor func nameD(_ c: NSCursor) -> String {
    var known: [(String, NSCursor)] = [
        ("arrow", .arrow), ("pointingHand", .pointingHand), ("resizeLeftRight", .resizeLeftRight), ("resizeUpDown", .resizeUpDown),
        ("resizeLeft", .resizeLeft), ("resizeRight", .resizeRight), ("resizeUp", .resizeUp), ("resizeDown", .resizeDown),
        ("columnResize", .columnResize), ("rowResize", .rowResize),
    ]
    let h: [(String, NSHorizontalDirection.Set)] = [("left", .left), ("right", .right), ("all", .all)]
    let v: [(String, NSVerticalDirection.Set)] = [("up", .up), ("down", .down), ("all", .all)]
    for (n, d) in h { known.append(("columnResize(.\(n))", .columnResize(directions: d))) }
    for (n, d) in v { known.append(("rowResize(.\(n))", .rowResize(directions: d))) }
    let names = known.filter { $0.1 == c }.map(\.0)
    return names.isEmpty ? "other(size=\(c.image.size) hot=\(c.hotSpot))" : names.joined(separator: "=")
}

@MainActor func arm<V: View>(_ label: String, _ view: V, at c: CGPoint = CGPoint(x: 60, y: 60)) {
    NSCursor.arrow.set()
    let w = makeWindow(Offset(content: view))
    Hides.hides = 0; Hides.unhides = 0; Hides.untilMove = 0
    mouse(w, .mouseMoved, wp(c.x, c.y)); spin(0.1)
    _ = driveCursorUpdate(w, at: wp(c.x, c.y)); spin(0.5)
    _ = driveCursorUpdate(w, at: wp(c.x + 2, c.y + 1)); spin(0.5)
    _ = Log.take()
    let inside = cursorVisible(), shown = nameD(NSCursor.current)
    // Leave the view (still inside the window): read the balance.
    mouse(w, .mouseMoved, wp(10, 10)); spin(0.1)
    _ = driveCursorUpdate(w, at: wp(10, 10)); spin(0.5)
    print("  \(label): current=\(shown) over[\(inside)] after-leaving[\(cursorVisible())]")
    w.orderOut(nil)
}

@MainActor func run() {
    swizzleHides()
    NSCursor.hide(); spin(0.2)
    print("  V0 NSCursor.hide() (instrument control): calls[\(cursorVisible())]")
    NSCursor.unhide(); spin(0.2)
    print("  V00 after unhide: calls[\(cursorVisible())]")
    Hides.hides = 0; Hides.unhides = 0; Hides.untilMove = 0
    print("--- D: column/row resize directions")
    arm("D0 .columnResize (control)", Color.gray.pointerStyle(.columnResize))
    arm("D1 .columnResize(directions: .all)", Color.gray.pointerStyle(.columnResize(directions: .all)))
    arm("D2 .columnResize(directions: .leading)", Color.gray.pointerStyle(.columnResize(directions: .leading)))
    arm("D3 .columnResize(directions: .trailing)", Color.gray.pointerStyle(.columnResize(directions: .trailing)))
    arm("D4 .columnResize(directions: [])", Color.gray.pointerStyle(.columnResize(directions: [])))
    arm("D5 .rowResize (control)", Color.gray.pointerStyle(.rowResize))
    arm("D6 .rowResize(directions: .all)", Color.gray.pointerStyle(.rowResize(directions: .all)))
    arm("D7 .rowResize(directions: .up)", Color.gray.pointerStyle(.rowResize(directions: .up)))
    arm("D8 .rowResize(directions: .down)", Color.gray.pointerStyle(.rowResize(directions: .down)))
    arm("D9 .rowResize(directions: [])", Color.gray.pointerStyle(.rowResize(directions: [])))
    print("--- V: pointerVisibility")
    let center = CGPoint(x: 90, y: 80)
    arm("V1 no modifier (control)", Color.gray)
    arm("V2 .pointerVisibility(.hidden)", Color.gray.pointerVisibility(.hidden))
    arm("V3 .pointerVisibility(.visible)", Color.gray.pointerVisibility(.visible))
    arm("V4 .pointerVisibility(.automatic)", Color.gray.pointerVisibility(.automatic))
    arm("V5 outer .hidden, inner 40x40 .visible, over inner",
        ZStack { Color.gray; Color.blue.frame(width: 40, height: 40).pointerVisibility(.visible) }.pointerVisibility(.hidden), at: center)
    arm("V6 outer .hidden, inner 40x40 .automatic, over inner",
        ZStack { Color.gray; Color.blue.frame(width: 40, height: 40).pointerVisibility(.automatic) }.pointerVisibility(.hidden), at: center)
    arm("V7 .hidden with .pointerStyle(.link)", Color.gray.pointerStyle(.link).pointerVisibility(.hidden))
    arm("V7c .pointerStyle(.link) alone (control for V7)", Color.gray.pointerStyle(.link))
    arm("V7b .pointerVisibility(.hidden) then .pointerStyle(.link)", Color.gray.pointerVisibility(.hidden).pointerStyle(.link))
    arm("V8 outer .hidden, pointer off the inner square (control)",
        ZStack { Color.gray; Color.blue.frame(width: 40, height: 40).pointerVisibility(.visible) }.pointerVisibility(.hidden))
    arm("V9 outer .hidden, an opaque 40x40 onTapGesture sibling over the pointer",
        ZStack { Color.gray.pointerVisibility(.hidden); Color.blue.frame(width: 40, height: 40).onTapGesture {} }, at: center)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
