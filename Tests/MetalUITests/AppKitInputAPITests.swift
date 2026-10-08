import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// Input APIs, lane 1, tests 1.5–1.10 and 1.19 (rulings `CI-C` item 2, `CI-E`
// items 1 and 3, `CI-H` item 8, `CI-J`, `CI-P`, `CI-T`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.1). A real
// `AppKitPlatform` window and its own `MetalHostView`, driven with real
// `NSEvent`s: `NSEvent.mouseEvent` for the primary and secondary buttons,
// CG-made events converted with `NSEvent(cgEvent:)` for the other buttons and
// for trackpad gestures (the probe `swiftui-input-apis.swift`'s recipe: the
// gesture type 29, HID type in field 110 — 8 zoom, 5 rotation — the value in
// field 113 or 114 and the phase in field 132). Nothing sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private final class ConstantSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private final class Log {
    var events: [InputEvent] = []
}

/// A real 400 × 200 AppKit window with nothing drawn, its `onInput` logging.
@MainActor private func hostWindow() throws -> (AppKitPlatform, AppKitWindow, NSWindow, Log) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let platform = AppKitPlatform(device: device, accessibilitySignal: { ConstantSignal() })
    let platformWindow = try platform.openWindow(title: "Input APIs \(UUID().uuidString)",
                                                 size: Size(width: px(400), height: px(200)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    let nsWindow = try #require(appKit.hostView.window)
    let log = Log()
    appKit.onInput = { event in log.events.append(event); return true }
    return (platform, appKit, nsWindow, log)
}

/// A mouse event at MetalUI's top-left point `(x, y)` in a 200-point-high
/// window (AppKit's window coordinates have a bottom-left origin).
@MainActor private func mouse(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat,
                              _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 200 - y), modifierFlags: flags,
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    eventNumber: 0, clickCount: 1, pressure: 1))
}

/// An input event as a short string: `rdrag(55,65)^1` — the kind, the
/// position, `^` for control, then the button number.
private func describe(_ event: InputEvent) -> String {
    func at(_ m: MouseEvent) -> String {
        "(\(Int(m.position.x.value)),\(Int(m.position.y.value)))\(m.modifiers.contains(.control) ? "^" : "")\(m.buttonNumber)"
    }
    switch event {
    case .mouseDown(let m): return "down\(at(m))"
    case .mouseUp(let m): return "up\(at(m))"
    case .mouseDragged(let m): return "drag\(at(m))"
    case .rightMouseDown(let m): return "rdown\(at(m))"
    case .rightMouseUp(let m): return "rup\(at(m))"
    case .rightMouseDragged(let m): return "rdrag\(at(m))"
    case .otherMouseDown(let m): return "odown\(at(m))"
    case .otherMouseDragged(let m): return "odrag\(at(m))"
    case .otherMouseUp(let m): return "oup\(at(m))"
    default: return "other"
    }
}

/// A CG trackpad gesture event (the probe's recipe): HID type `hid` (8 zoom,
/// 5 rotation), `value` in `field` (113 zoom, 114 rotation), CG phase `phase`
/// (1 began, 2 changed, 4 ended), converted to an `NSEvent`.
private func gesture(hid: Int64, field: UInt32, value: Double, phase: Int64) throws -> NSEvent {
    let cg = try #require(CGEvent(source: nil))
    cg.type = try #require(CGEventType(rawValue: 29))
    cg.location = CGPoint(x: 60, y: 50)
    cg.setIntegerValueField(try #require(CGEventField(rawValue: 110)), value: hid)
    cg.setDoubleValueField(try #require(CGEventField(rawValue: field)), value: value)
    cg.setIntegerValueField(try #require(CGEventField(rawValue: 132)), value: phase)
    return try #require(NSEvent(cgEvent: cg))
}

// MARK: - 1.5: magnify and rotate

/// **1.5** (`CI-C` item 2, `CI-J` item 1). Real trackpad gesture events to the
/// host view's `magnify(with:)`/`rotate(with:)` reach `onInput` as `.magnify`
/// and `.rotate` with this event's delta and phase: a began / changed / ended
/// sequence. **The rotation is negated once at the seam**: AppKit's +10°
/// (counterclockwise) is `RotateEvent.rotation` −10 (clockwise-positive, probe
/// `Q1`); the magnification is AppKit's own (+0.1, probe `M0`). The converted
/// events' types and values are required first, so the instrument cannot pass
/// on events it did not make.
///
/// Mutation: drop the negation in `rotate(with:)` (the rotation arm reddens).
@MainActor
@Test func appKitMagnifyAndRotateReachOnInputWithDeltasAndPhases() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { nsWindow.close() }
    let view = appKit.hostView
    let zooms = try [(0.0, Int64(1)), (0.1, 2), (0.0, 4)].map { try gesture(hid: 8, field: 113, value: $0.0, phase: $0.1) }
    let turns = try [(0.0, Int64(1)), (10.0, 2), (0.0, 4)].map { try gesture(hid: 5, field: 114, value: $0.0, phase: $0.1) }
    try #require(zooms.allSatisfy { $0.type == .magnify }, "premise: \(zooms.map(\.type))")
    try #require(turns.allSatisfy { $0.type == .rotate }, "premise: \(turns.map(\.type))")
    try #require(abs(zooms[1].magnification - 0.1) < 1e-6 && zooms[1].phase == .changed,
                 "premise: \(zooms[1].magnification) \(zooms[1].phase)")
    try #require(abs(turns[1].rotation - 10) < 1e-4 && turns[1].phase == .changed,
                 "premise: \(turns[1].rotation) \(turns[1].phase)")

    for event in zooms { view.magnify(with: event) }
    for event in turns { view.rotate(with: event) }

    let magnifies = log.events.compactMap { if case .magnify(let m) = $0 { m } else { nil } }
    let rotates = log.events.compactMap { if case .rotate(let r) = $0 { r } else { nil } }
    try #require(magnifies.count == 3 && rotates.count == 3, "\(log.events)")
    #expect(magnifies.map(\.phase) == [.began, .changed, .ended])
    #expect(abs(magnifies[1].magnification - 0.1) < 1e-6, "magnification \(magnifies[1].magnification)")
    #expect(magnifies[0].magnification == 0 && magnifies[2].magnification == 0)
    #expect(rotates.map(\.phase) == [.began, .changed, .ended])
    #expect(abs(rotates[1].rotation - (-10)) < 1e-4,
            "AppKit's +10° (counterclockwise) is −10 clockwise-positive: \(rotates[1].rotation)")
    let expected = view.convert(zooms[1].locationInWindow, from: nil)
    #expect(magnifies[1].position == Point(x: px(Float(expected.x)), y: px(Float(expected.y))))
}

// MARK: - 1.6, 1.7: other buttons, right-drag, the control-drag

/// **1.6** (`CI-E` items 1 and 3). CG-made `otherMouseDown/Dragged/Up` events
/// for the centre button reach `onInput` as the three `other…` cases with
/// `buttonNumber` 2 (AppKit's, required on the converted events first); a real
/// `rightMouseDragged` reaches it as `.rightMouseDragged` with `buttonNumber` 1
/// — the secondary cases carry 1 by construction (`CI-E` item 1), whatever the
/// `NSEvent` says.
///
/// Mutation: remove the `otherMouseDragged(with:)` override (the drag
/// reddens).
@MainActor
@Test func appKitOtherButtonsAndRightDragReachOnInput() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { nsWindow.close() }
    let view = appKit.hostView
    func other(_ type: CGEventType, _ x: CGFloat, _ y: CGFloat) throws -> NSEvent {
        let cg = try #require(CGEvent(mouseEventSource: nil, mouseType: type,
                                      mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .center))
        return try #require(NSEvent(cgEvent: cg))
    }
    let down = try other(.otherMouseDown, 30, 40)
    let drag = try other(.otherMouseDragged, 35, 45)
    let up = try other(.otherMouseUp, 35, 45)
    try #require(down.type == .otherMouseDown && drag.type == .otherMouseDragged && up.type == .otherMouseUp)
    try #require(down.buttonNumber == 2 && drag.buttonNumber == 2 && up.buttonNumber == 2,
                 "premise: \(down.buttonNumber) \(drag.buttonNumber) \(up.buttonNumber)")
    view.otherMouseDown(with: down)
    view.otherMouseDragged(with: drag)
    view.otherMouseUp(with: up)
    view.rightMouseDown(with: try mouse(.rightMouseDown, 50, 60, in: nsWindow))
    view.rightMouseDragged(with: try mouse(.rightMouseDragged, 55, 65, in: nsWindow))
    view.rightMouseUp(with: try mouse(.rightMouseUp, 55, 65, in: nsWindow))
    let kinds = log.events.map(describe).map { String($0.prefix { $0.isLetter }) }
    #expect(kinds == ["odown", "odrag", "oup", "rdown", "rdrag", "rup"], "\(log.events.map(describe))")
    let numbers = log.events.compactMap { event -> Int? in
        switch event {
        case .otherMouseDown(let m), .otherMouseDragged(let m), .otherMouseUp(let m),
             .rightMouseDown(let m), .rightMouseDragged(let m), .rightMouseUp(let m): m.buttonNumber
        default: nil
        }
    }
    #expect(numbers == [2, 2, 2, 1, 1, 1])
    #expect(log.events.map(describe).suffix(3) == ["rdown(50,60)1", "rdrag(55,65)1", "rup(55,65)1"])
}

/// **1.7** (`CI-E` item 3, the migration of `MN-AC` item 1; `CI-T`). A
/// control-press is a secondary press on AppKit, and its drag now goes out as
/// a **secondary drag** (`.rightMouseDragged`, `buttonNumber` 1, the control
/// modifier kept) — it was dropped. Its release is `.rightMouseUp`, and a
/// plain drag after it is primary again.
///
/// Mutation: restore `if controlClickInFlight { return }` in
/// `mouseDragged(with:)` (the secondary drag reddens).
@MainActor
@Test func aControlDragOnAppKitIsASecondaryDrag() throws {
    let (_, appKit, nsWindow, log) = try hostWindow()
    defer { nsWindow.close() }
    let view = appKit.hostView
    view.mouseDown(with: try mouse(.leftMouseDown, 50, 60, .control, in: nsWindow))
    view.mouseDragged(with: try mouse(.leftMouseDragged, 55, 65, .control, in: nsWindow))
    view.mouseUp(with: try mouse(.leftMouseUp, 55, 65, .control, in: nsWindow))
    view.mouseDown(with: try mouse(.leftMouseDown, 70, 80, in: nsWindow))
    view.mouseDragged(with: try mouse(.leftMouseDragged, 75, 85, in: nsWindow))
    view.mouseUp(with: try mouse(.leftMouseUp, 75, 85, in: nsWindow))
    #expect(log.events.map(describe) == ["rdown(50,60)^1", "rdrag(55,65)^1", "rup(55,65)^1",
                                         "down(70,80)0", "drag(75,85)0", "up(75,85)0"])
}

// MARK: - 1.8–1.10: the pointer style

/// Every frame-resize edge with the AppKit position the probe read for it
/// (`P9`, `P17`; `CI-P` item 2: `leading` → `.left`, `trailing` → `.right`).
@available(macOS 15, *)
private let frameEdges: [(PlatformResizeEdge, NSCursor.FrameResizePosition)] = [
    (.top, .top), (.leading, .left), (.bottom, .bottom), (.trailing, .right),
    (.topLeading, .topLeft), (.topTrailing, .topRight),
    (.bottomLeading, .bottomLeft), (.bottomTrailing, .bottomRight),
]

/// **1.8** (`CI-H` item 8, `CI-P`). Every `PlatformPointerStyle` but the
/// frame resizes maps to the `NSCursor` the probe read (`P1`–`P10`, `P15`,
/// `P16`) — compared as cursors, each distinct. **The frame-resize table is
/// compared as values** from `AppKitCursor.frameResize(for:inward:outward:)`:
/// `NSCursor ==` compares images, and with `.all` a position equals its
/// opposite (`P17`), so a cursor comparison could not see `top` and `bottom`
/// swapped. Eight edges × three direction sets.
///
/// Mutations: swap `openHand`/`closedHand` (the cursor arm reddens); swap
/// `top`/`bottom` in the frame table (the value arm reddens).
@MainActor
@Test func appKitPointerStylesMapAsTheProbeMeasured() throws {
    guard #available(macOS 15, *) else { return }
    let cursors: [(PlatformPointerStyle, NSCursor)] = [
        (.arrow, .arrow), (.iBeam, .iBeam), (.verticalIBeam, .iBeamCursorForVerticalLayout),
        (.crosshair, .crosshair), (.openHand, .openHand), (.closedHand, .closedHand),
        (.pointingHand, .pointingHand), (.columnResize, .columnResize), (.rowResize, .rowResize),
        (.zoomIn, .zoomIn), (.zoomOut, .zoomOut),
    ]
    // The instrument: the expected cursors are pairwise distinct, so a swap
    // between any two of them is visible.
    for (i, a) in cursors.enumerated() {
        for b in cursors[(i + 1)...] { try #require(a.1 != b.1, "\(a.0) and \(b.0) read the same cursor") }
    }
    for (style, cursor) in cursors {
        #expect(AppKitCursor.cursor(for: style) == cursor, "\(style)")
    }
    let sets: [(Bool, Bool, NSCursor.FrameResizeDirection.Set)] = [
        (true, false, .inward), (false, true, .outward), (true, true, .all),
    ]
    for (edge, position) in frameEdges {
        for (inward, outward, directions) in sets {
            let mapped = AppKitCursor.frameResize(for: edge, inward: inward, outward: outward)
            #expect(mapped.position == position && mapped.directions == directions,
                    "\(edge) inward=\(inward) outward=\(outward) → \(mapped)")
        }
    }
    // The cursor is the table's: one edge, read as a cursor.
    #expect(AppKitCursor.cursor(for: .frameResize(edge: .trailing, inward: true, outward: false))
            == NSCursor.frameResize(position: .right, directions: .inward))
}

/// A `.cursorUpdate` event for `window`, as the tracking area delivers it.
@MainActor private func cursorUpdateEvent(in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.enterExitEvent(with: .cursorUpdate, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        eventNumber: 0, trackingNumber: 0, userData: nil))
}

/// **1.9** (`CI-H` item 8, `CI-J` item 2). `AppKitWindow.setPointerStyle(_:)`
/// stores the cursor, and the host view's `cursorUpdate(with:)` — which AppKit
/// calls whenever the pointer enters the view or the cursor rects are
/// re-evaluated — sets it. The current cursor is reset to the arrow before
/// each `cursorUpdate`, so only the override can bring the style back.
///
/// Mutation: `cursorUpdate(with:)` sets `arrow` (both arms redden).
@MainActor
@Test func appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt() throws {
    let (_, appKit, nsWindow, _) = try hostWindow()
    defer { nsWindow.close(); NSCursor.arrow.set() }
    appKit.setPointerStyle(.crosshair)
    NSCursor.arrow.set()
    try #require(NSCursor.current == NSCursor.arrow, "premise: the arrow is current")
    appKit.hostView.cursorUpdate(with: try cursorUpdateEvent(in: nsWindow))
    #expect(NSCursor.current == NSCursor.crosshair)

    appKit.setPointerStyle(.openHand)
    NSCursor.arrow.set()
    appKit.hostView.cursorUpdate(with: try cursorUpdateEvent(in: nsWindow))
    #expect(NSCursor.current == NSCursor.openHand)
}

/// **1.10** (`CI-H` item 8). The host view's tracking area asks for cursor
/// updates, so AppKit calls `cursorUpdate(with:)` on entry; the existing
/// options stay.
///
/// Mutation: drop `.cursorUpdate` from the options.
@MainActor
@Test func theHostViewsTrackingAreaRequestsCursorUpdates() throws {
    let (_, appKit, nsWindow, _) = try hostWindow()
    defer { nsWindow.close() }
    let view = appKit.hostView
    view.updateTrackingAreas()
    let options = view.trackingAreas.map(\.options)
    try #require(options.count == 1, "one tracking area: \(options)")
    #expect(options[0].contains(.cursorUpdate))
    #expect(options[0].isSuperset(of: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]))
}

// MARK: - 1.19: the fake

/// **1.19** (`CI-J` items 2 and 4). `FakePlatformWindow` records every
/// `setPointerStyle` argument in order, and its `simulateInput` stamps a
/// scroll event's `location` with its `position`, as both platforms do at the
/// seam — a test that hands it a different `location` sees the seam's.
///
/// Mutation: the fake ignores `location` (the stamp arm reddens).
@MainActor
@Test func theFakeWindowRecordsPointerStylesAndStampsScrollLocation() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let fake = try FakePlatformWindow(device: device)
    fake.setPointerStyle(.crosshair)
    fake.setPointerStyle(.arrow)
    fake.setPointerStyle(.frameResize(edge: .top, inward: true, outward: false))
    #expect(fake.pointerStyles == [.crosshair, .arrow, .frameResize(edge: .top, inward: true, outward: false)])

    var seen: [ScrollEvent] = []
    fake.onInput = { event in
        if case .scrollWheel(let scroll) = event { seen.append(scroll) }
        return true
    }
    var scroll = ScrollEvent(position: Point(x: px(30), y: px(40)), delta: Point(x: px(0), y: px(-5)))
    scroll.location = Point(x: px(1), y: px(2))
    fake.simulateInput(.scrollWheel(scroll))
    try #require(seen.count == 1)
    #expect(seen[0].location == Point(x: px(30), y: px(40)))
    #expect(seen[0].position == Point(x: px(30), y: px(40)))
}
