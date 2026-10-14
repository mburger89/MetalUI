// SwiftUI/AppKit probe: PointerStyle.image(_:hotSpot:) (rulings IC-* in
// docs/superpowers/2026-10-14-cursors-headless-decisions.md).
//
// HOW TO RUN:
//   xcrun swiftc docs/probes/swiftui-image-cursor.swift -o /tmp/ic-probe && /tmp/ic-probe
//
// THE INSTRUMENT is swiftui-input-apis.swift's pointer arm (a key-window host,
// cursorUpdate/mouseMoved driven by hand, NSCursor.current read after). Its
// positive control is P0 (NSCursor.crosshair.set() reads back as crosshair) and
// the separating arms are the three hot spots and the two image sizes: a
// reading that ignored hotSpot or scale would give the same line for each.
//
// ARMS. I1..I3: a 16x16-point Image at hotSpot .topLeading, .center,
// .bottomTrailing: NSCursor.current.hotSpot (points, top-left origin).
// I4: the same bitmap as a 32x32-pixel CGImage with scale 2 (16 pt):
// current.image.size and representations' pixel sizes. I5: a resizable
// Image given a frame (does the frame size the cursor?). I6: hotSpot outside
// the unit square (.init(x: 2, y: -1)). I7: pointerStyle(.image) then nil.
//
// RECORDED 2026-10-14 by the item S4+S8 designer, macOS 27.0.1, Apple Swift 6.4,
// screen LOCKED (lock probe: CGSSessionScreenIsLocked = 1, displayAsleep main: 1).
// Compiled form run twice, stdout byte-identical (8 lines), exit 0:
//   I0 NSCursor.crosshair.set() then current (control): crosshair
//   I1 16px scale1 hot .topLeading: isArrow=false size=(16.0, 16.0) hot=(0.0, 0.0) reps=["32x32"]
//   I2 16px scale1 hot .center: isArrow=false size=(16.0, 16.0) hot=(8.0, 8.0) reps=["32x32"]
//   I3 16px scale1 hot .bottomTrailing: isArrow=false size=(16.0, 16.0) hot=(16.0, 16.0) reps=["32x32"]
//   I4 32px scale2 hot .center: isArrow=false size=(16.0, 16.0) hot=(8.0, 8.0) reps=["32x32"]
//   I5 resizable() 16px hot .center: isArrow=false size=(16.0, 16.0) hot=(8.0, 8.0) reps=["32x32"]
//   I6 hot (2,-1): isArrow=false size=(16.0, 16.0) hot=(32.0, 16.0) reps=["32x32"]
//   I7 image then nil (outer none): isArrow=false size=(16.0, 16.0) hot=(8.0, 8.0) reps=["32x32"]
// READ: the cursor's point size is pixels / scale (I1 vs I4: 16 px at scale 1 and 32 px at scale 2 are both
// 16 pt); hotSpot = unit point x point size, top-left origin (I1-I3); .resizable() changes nothing (I5); the
// rep is always 2x on this 2x display (SwiftUI resamples a 1x image, I1). I6 is NOT understood: x = 2 gave 32
// (unclamped) but y = -1 gave 16 (not -16, not 0) -- out-of-range hot spots are unprobed beyond "x unclamped,
// y odd", so MetalUI clamps (ruling IC-C, divergence 465). I7: the outer pointerStyle(nil) does not remove an
// inner image style (same rule as P12). A frame cannot size the cursor: .image takes an Image, not a View.
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

/// A CGEvent-made event at a window point, converted to an NSEvent. The
struct Offset<C: View>: View {
    let content: C
    var body: some View {
        content.frame(width: 100, height: 100)
            .padding(.leading, 40).padding(.top, 30)
            .frame(width: side, height: side, alignment: .topLeading)
    }
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

func makeCG(_ px: Int) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

@MainActor func imageArm<V: View>(_ label: String, _ view: V) {
    NSCursor.arrow.set()
    let w = makeWindow(Offset(content: view))
    let c = CGPoint(x: 60, y: 60)
    mouse(w, .mouseMoved, wp(c.x, c.y)); spin(0.1)
    _ = driveCursorUpdate(w, at: wp(c.x, c.y)); spin(0.5)
    _ = driveCursorUpdate(w, at: wp(c.x + 2, c.y + 1)); spin(0.5)
    _ = Log.take()
    let cur = NSCursor.current
    let reps = cur.image.representations.map { "\($0.pixelsWide)x\($0.pixelsHigh)" }
    print("  \(label): isArrow=\(cur == .arrow) size=\(cur.image.size) hot=\(cur.hotSpot) reps=\(reps)")
    w.orderOut(nil)
}

@MainActor func run() {
    NSCursor.crosshair.set()
    print("  I0 NSCursor.crosshair.set() then current (control): \(NSCursor.current == .crosshair ? "crosshair" : "other")")
    let one = Image(decorative: makeCG(16), scale: 1)
    let two = Image(decorative: makeCG(32), scale: 2)
    imageArm("I1 16px scale1 hot .topLeading", Color.gray.pointerStyle(.image(one, hotSpot: .topLeading)))
    imageArm("I2 16px scale1 hot .center", Color.gray.pointerStyle(.image(one, hotSpot: .center)))
    imageArm("I3 16px scale1 hot .bottomTrailing", Color.gray.pointerStyle(.image(one, hotSpot: .bottomTrailing)))
    imageArm("I4 32px scale2 hot .center", Color.gray.pointerStyle(.image(two, hotSpot: .center)))
    imageArm("I5 resizable() 16px hot .center", Color.gray.pointerStyle(.image(one.resizable(), hotSpot: .center)))
    imageArm("I6 hot (2,-1)", Color.gray.pointerStyle(.image(one, hotSpot: UnitPoint(x: 2, y: -1))))
    imageArm("I7 image then nil (outer none)", Color.gray.pointerStyle(.image(one, hotSpot: .center)).pointerStyle(nil))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
