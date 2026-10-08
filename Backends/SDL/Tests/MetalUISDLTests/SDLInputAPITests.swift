import Testing
import MetalUICore
import MetalUIPlatform
@testable import MetalUISDL
import SDLBridge

// Input APIs, lane 1, tests 1.11–1.18 (rulings `CI-E` item 4, `CI-H` item 8,
// `CI-I` item 6, `CI-K`; spec
// `docs/superpowers/specs/2026-10-08-input-apis-design.md` §4.1). Every
// pointer and pinch event goes through SDL's own queue — a raw SDL event
// pushed by `mui_push_raw_mouse_event`/`mui_push_raw_pinch_event`, its type,
// button and mask taken from the C-exported `mui_sdl_*` constants, never an
// SDL enum's `rawValue` in Swift (`Int32` on Windows) — then `translate` and
// `SDLWindow.handle`. None needs a presented frame, so none is gated on the
// offscreen driver.

@MainActor
private func inputWindow() throws -> (SDLPlatform, SDLWindow) {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let platform = try SDLPlatform(hiddenWindows: true)
    let window = try platform.openSDLWindow(title: "MetalUI input API test",
                                            size: Size(width: Pixels(320), height: Pixels(200)))
    platform.pumpEvents()   // drain whatever opening the window queued
    return (platform, window)
}

/// A pointer event as a short string: the kind, the position, the button
/// number (`odown(30,40)2`).
private func describe(_ event: InputEvent) -> String {
    func at(_ m: MouseEvent) -> String {
        "(\(Int(m.position.x.value)),\(Int(m.position.y.value)))\(m.buttonNumber)"
    }
    switch event {
    case .mouseDown(let m): return "down\(at(m))"
    case .mouseUp(let m): return "up\(at(m))"
    case .mouseMoved(let m): return "move\(at(m))"
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

// MARK: - 1.11, 1.12: buttons and drags

/// **1.11** (`CI-E` item 4). SDL's middle and extra buttons become
/// `.otherMouseDown`/`.otherMouseUp` with AppKit's numbers — middle 2, X1
/// (back) 3, X2 (forward) 4 — where they were dropped; the left and right
/// buttons are unchanged and carry 0 and 1.
///
/// Mutation: map X1 → 4 (the X1 pair reddens).
@MainActor
@Test func sdlMiddleAndExtraButtonsBecomeOtherMouseEventsWithAppKitNumbers() throws {
    let (platform, window) = try inputWindow()
    var received: [String] = []
    window.onInput = { received.append(describe($0)); return true }
    for button in [mui_sdl_button_middle, mui_sdl_button_x1, mui_sdl_button_x2,
                   mui_sdl_button_left, mui_sdl_button_right] {
        #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_down, window.id, button, 0, 30, 40))
        #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_button_up, window.id, button, 0, 30, 40))
    }
    platform.pumpEvents()
    #expect(received == ["odown(30,40)2", "oup(30,40)2", "odown(30,40)3", "oup(30,40)3",
                         "odown(30,40)4", "oup(30,40)4", "down(30,40)0", "up(30,40)0",
                         "rdown(30,40)1", "rup(30,40)1"])
}

/// **1.12** (`CI-E` item 4). Motion with buttons held: the right button alone
/// is a `.rightMouseDragged`, the middle alone an `.otherMouseDragged` (2), X1
/// alone one with 3, middle and X2 together the lowest held button (2) — and
/// the left button with the right is still a primary `.mouseDragged`. Motion
/// with nothing held is a move.
///
/// Mutation: test `RMASK` before `LMASK` (the left-and-right arm reddens).
@MainActor
@Test func sdlMotionWithRightOrMiddleHeldIsARightOrOtherDrag() throws {
    let (platform, window) = try inputWindow()
    var received: [String] = []
    window.onInput = { received.append(describe($0)); return true }
    let masks: [UInt32] = [mui_sdl_button_rmask, mui_sdl_button_mmask, mui_sdl_button_x1mask,
                           mui_sdl_button_mmask | mui_sdl_button_x2mask,
                           mui_sdl_button_lmask | mui_sdl_button_rmask, 0]
    for (i, mask) in masks.enumerated() {
        #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_motion, window.id, 0, mask, Float(10 + i), 20))
    }
    platform.pumpEvents()
    #expect(received == ["rdrag(10,20)1", "odrag(11,20)2", "odrag(12,20)3", "odrag(13,20)2",
                         "drag(14,20)0", "move(15,20)0"])
}

// MARK: - 1.13–1.15: pinch

/// **1.13** (`CI-K` items 1 and 2). A pinch — BEGIN, UPDATE 1.1, UPDATE 1.25,
/// END — becomes `.magnify` events with phases began / changed / changed /
/// ended and **this event's delta** under a cumulative driver (SDL's x11,
/// wayland and offscreen drivers send the scale since the gesture began): 0,
/// 0.1, 0.15, 0. A pinch has no position in SDL, so each is at the window's
/// last pointer position (the motion to (30, 40) before it).
///
/// The platform reads the driver once; on macOS that is `cocoa` (a ratio
/// driver), so the test sets the platform's reading to the offscreen driver's
/// — after requiring that the platform read the real driver as
/// `SDLPinch.isCumulative(driver:)` says. In CI's Linux image the driver is
/// the offscreen one and the override changes nothing.
///
/// Mutation: the ratio rule on a cumulative driver (`scale − 1`: the second
/// delta reads 0.25).
@MainActor
@Test func sdlPinchBecomesMagnifyAtTheLastPointerPosition() throws {
    let (platform, window) = try inputWindow()
    let driver = String(cString: mui_current_video_driver())
    try #require(platform.pinchIsCumulative == SDLPinch.isCumulative(driver: driver),
                 "the platform read the driver \(driver)")
    platform.pinchIsCumulative = SDLPinch.isCumulative(driver: "offscreen")
    var magnifies: [MagnifyEvent] = []
    window.onInput = { event in
        if case .magnify(let m) = event { magnifies.append(m) }
        return true
    }
    #expect(mui_push_raw_mouse_event(mui_sdl_event_mouse_motion, window.id, 0, 0, 30, 40))
    #expect(mui_push_raw_pinch_event(mui_sdl_event_pinch_begin, window.id, 1))
    #expect(mui_push_raw_pinch_event(mui_sdl_event_pinch_update, window.id, 1.1))
    #expect(mui_push_raw_pinch_event(mui_sdl_event_pinch_update, window.id, 1.25))
    #expect(mui_push_raw_pinch_event(mui_sdl_event_pinch_end, window.id, 1.25))
    platform.pumpEvents()
    try #require(magnifies.count == 4, "\(magnifies)")
    #expect(magnifies.map(\.phase) == [.began, .changed, .changed, .ended])
    let deltas = magnifies.map(\.magnification)
    for (delta, expected) in zip(deltas, [0, 0.1, 0.15, 0]) {
        #expect(abs(delta - expected) < 1e-5, "deltas \(deltas)")
    }
    for m in magnifies { #expect(m.position == Point(x: Pixels(30), y: Pixels(40))) }
}

/// **1.14** (`CI-K` item 1). The delta rule, pure: on a cumulative driver this
/// event's scale less the previous one; on cocoa (a per-event ratio) the scale
/// less 1. The driver reading: only `cocoa` is a ratio driver; x11, wayland,
/// offscreen, windows and an unknown name are cumulative.
///
/// Mutation: swap the two branches (both arms redden).
@Test func sdlPinchDeltaIsARatioOnCocoaAndCumulativeElsewhere() {
    #expect(abs(SDLPinch.delta(scale: 1.25, previous: 1.1, cumulative: true) - 0.15) < 1e-9)
    #expect(abs(SDLPinch.delta(scale: 1.25, previous: 1.1, cumulative: false) - 0.25) < 1e-9)
    #expect(abs(SDLPinch.delta(scale: 0.8, previous: 1, cumulative: true) - (-0.2)) < 1e-9)
    #expect(!SDLPinch.isCumulative(driver: "cocoa"))
    for driver in ["x11", "wayland", "offscreen", "windows", "dummy", ""] {
        #expect(SDLPinch.isCumulative(driver: driver), "\(driver)")
    }
}

/// **1.15** (`CI-K` item 2). Where a pinch goes, pure: to the window SDL
/// names; with window id 0 (cocoa sends none) to the window with mouse focus,
/// else the keyboard-focused window, else nowhere.
///
/// Mutation: prefer keyboard focus (the second arm reddens).
@Test func aPinchWithNoWindowGoesToTheMouseFocusThenTheKeyboardFocus() {
    #expect(SDLPinch.route(windowID: 7, mouseFocus: 3, keyboardFocus: 4) == 7)
    #expect(SDLPinch.route(windowID: 0, mouseFocus: 3, keyboardFocus: 4) == 3)
    #expect(SDLPinch.route(windowID: 0, mouseFocus: 0, keyboardFocus: 4) == 4)
    #expect(SDLPinch.route(windowID: 0, mouseFocus: 0, keyboardFocus: 0) == nil)
}

// MARK: - 1.16: the wheel

/// **1.16** (`CI-I` item 6). SDL 3.4 has no scroll phase, momentum or precise
/// flag: a wheel event's `phase` and `momentumPhase` are `.none`, `isPrecise`
/// is `false` (SDL's delta is lines, scaled to points), and `location` is the
/// seam's `position`.
///
/// Mutation: `isPrecise: true` (reddens).
@MainActor
@Test func sdlWheelHasNoPhaseMomentumOrPrecision() throws {
    let (platform, window) = try inputWindow()
    var scrolls: [ScrollEvent] = []
    window.onInput = { event in
        if case .scrollWheel(let s) = event { scrolls.append(s) }
        return true
    }
    var event = MUIEvent()
    event.kind = UInt32(MUI_EVENT_WHEEL)
    event.window_id = window.id
    event.x = 30; event.y = 40; event.dx = 0; event.dy = -2
    #expect(mui_push_event(&event))
    platform.pumpEvents()
    try #require(scrolls.count == 1)
    #expect(scrolls[0].phase == .none)
    #expect(scrolls[0].momentumPhase == .none)
    #expect(!scrolls[0].isPrecise)
    #expect(scrolls[0].location == Point(x: Pixels(30), y: Pixels(40)))
    #expect(scrolls[0].position == scrolls[0].location)
    #expect(scrolls[0].delta.y == Pixels(-20))
}

// MARK: - 1.17: cursors

/// **1.17** (`CI-H` item 8, `CI-K` item 4). Each `PlatformPointerStyle` maps to
/// an SDL system cursor: the arrow to `DEFAULT`, the I-beams to `TEXT`, the
/// crosshair to `CROSSHAIR`, the pointing hand to `POINTER`, the column and
/// row resizes to `EW`/`NS_RESIZE`, each frame edge to its own `N`…`SW_RESIZE`
/// — and, a documented platform constraint, **both grab hands to `MOVE` and
/// both zooms to `DEFAULT`** (SDL has no hand or zoom cursor). The window
/// records every requested style in order, so the request is seen even where
/// the offscreen driver cannot create a cursor.
///
/// Mutation: grab idle (`openHand`) → `DEFAULT` (reddens).
@MainActor
@Test func sdlPointerStylesMapToSystemCursorsAndAreRecorded() throws {
    let table: [(PlatformPointerStyle, SDLSystemCursor)] = [
        (.arrow, .default), (.iBeam, .text), (.verticalIBeam, .text), (.crosshair, .crosshair),
        (.openHand, .move), (.closedHand, .move), (.pointingHand, .pointer),
        (.columnResize, .ewResize), (.rowResize, .nsResize), (.zoomIn, .default), (.zoomOut, .default),
        (.frameResize(edge: .top, inward: true, outward: true), .nResize),
        (.frameResize(edge: .bottom, inward: true, outward: false), .sResize),
        (.frameResize(edge: .leading, inward: false, outward: true), .wResize),
        (.frameResize(edge: .trailing, inward: true, outward: true), .eResize),
        (.frameResize(edge: .topLeading, inward: true, outward: true), .nwResize),
        (.frameResize(edge: .topTrailing, inward: true, outward: true), .neResize),
        (.frameResize(edge: .bottomLeading, inward: true, outward: true), .swResize),
        (.frameResize(edge: .bottomTrailing, inward: true, outward: true), .seResize),
    ]
    for (style, cursor) in table {
        #expect(SDLCursorTable.systemCursor(for: style) == cursor, "\(style)")
    }
    let (_, window) = try inputWindow()
    window.setPointerStyle(.crosshair)
    window.setPointerStyle(.openHand)
    window.setPointerStyle(.arrow)
    #expect(window.pointerStyles == [.crosshair, .openHand, .arrow])
}

// MARK: - 1.18: the bridge's kinds

/// **1.18** (`CI-E` item 4, `CI-K` item 1). The bridge's event kinds before
/// this branch keep their C values — pinned as literals, so an insertion
/// anywhere among them reddens — and the five new kinds (`OTHER_DOWN`,
/// `OTHER_UP`, `RIGHT_DRAG`, `OTHER_DRAG`, `PINCH`) come after
/// `MUI_EVENT_MOUSE_LEAVE`, each distinct.
///
/// Mutation: insert `MUI_EVENT_PINCH` before `MUI_EVENT_DIALOG` (reddens).
@Test func theNewBridgeKindsAreAppendedAfterMouseLeave() {
    let old: [Int] = [
        Int(MUI_EVENT_NONE), Int(MUI_EVENT_QUIT), Int(MUI_EVENT_CLOSE), Int(MUI_EVENT_RESIZE),
        Int(MUI_EVENT_MOUSE_DOWN), Int(MUI_EVENT_MOUSE_UP), Int(MUI_EVENT_MOUSE_MOVE), Int(MUI_EVENT_WHEEL),
        Int(MUI_EVENT_KEY_DOWN), Int(MUI_EVENT_KEY_UP), Int(MUI_EVENT_THEME), Int(MUI_EVENT_EXPOSED),
        Int(MUI_EVENT_ACCESSIBILITY), Int(MUI_EVENT_MOUSE_DRAG), Int(MUI_EVENT_TEXT_INPUT),
        Int(MUI_EVENT_TEXT_EDITING), Int(MUI_EVENT_FOCUS_GAINED), Int(MUI_EVENT_FOCUS_LOST),
        Int(MUI_EVENT_DROP_BEGIN), Int(MUI_EVENT_DROP_POSITION), Int(MUI_EVENT_DROP_FILE),
        Int(MUI_EVENT_DROP_TEXT), Int(MUI_EVENT_DROP_COMPLETE), Int(MUI_EVENT_RIGHT_DOWN),
        Int(MUI_EVENT_RIGHT_UP), Int(MUI_EVENT_DIALOG), Int(MUI_EVENT_MOUSE_LEAVE),
    ]
    #expect(old == Array(0...26), "an existing kind moved: \(old)")
    let new = [Int(MUI_EVENT_OTHER_DOWN), Int(MUI_EVENT_OTHER_UP), Int(MUI_EVENT_RIGHT_DRAG),
               Int(MUI_EVENT_OTHER_DRAG), Int(MUI_EVENT_PINCH)]
    #expect(new.allSatisfy { $0 > Int(MUI_EVENT_MOUSE_LEAVE) }, "\(new)")
    #expect(Set(new).count == new.count)
}
