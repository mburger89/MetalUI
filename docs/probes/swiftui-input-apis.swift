// SwiftUI/AppKit probe: input APIs for viewports and canvases (rulings CI-*
// in docs/superpowers/2026-10-08-input-apis-decisions.md; spec
// docs/superpowers/specs/2026-10-08-input-apis-design.md).
//
// HOW TO RUN (SA-O's compiled form, as `swiftui-interaction.swift`):
//
//   xcrun swiftc docs/probes/swiftui-input-apis.swift -o /tmp/ci-probe && /tmp/ci-probe
//
// THE INSTRUMENT is `swiftui-gesture-presentation-arena.swift`'s: a
// `FirstMouseHost` window, `NSEvent`s through `NSWindow.sendEvent` with a
// run-loop spin between events. Buttons other than the primary, scroll and
// trackpad gestures are made as `CGEvent`s and converted with
// `NSEvent(cgEvent:)`; each such arm prints the converted event's type and
// `locationInWindow` for the first event so a mis-addressed event is visible.
// Magnify/rotate events are `CGEvent`s of the gesture type (29) with the
// HID-type field (110) set to zoom (8) or rotation (5), the value in field 113
// (zoom) or 114 (rotation) and the phase in field 132 — undocumented fields;
// the AppKit arm (M0/Q0, an `NSView` overriding `magnify(with:)` /
// `rotate(with:)`) is the positive control that the instrument delivers a
// real `.magnify`/`.rotate` event with the value set.
//
// ARMS AND THEIR CONTROLS.
//   T  — SpatialTapGesture / onTapGesture(coordinateSpace:) location. T0 (a
//        plain onTapGesture) is the control; T2 (.global) separates T1's
//        local answer from "the window point".
//   R  — Does DragGesture follow a right or a middle (other) button? R0 (the
//        primary button through the same CGEvent path) is the control.
//   M  — MagnifyGesture: cumulative or per-event magnification, startLocation,
//        startAnchor; M0 AppKit control; M3 control+scroll (no pinch) is the
//        "does SwiftUI synthesize magnify from ctrl-wheel" arm.
//   Q  — RotateGesture: sign and unit of rotation; Q0 AppKit control.
//   P  — pointerStyle → NSCursor.current after a mouseMoved over the view; P0
//        (an NSView whose cursorUpdate sets the crosshair) is the control.
//   C  — When does a context menu open: AppKit NSView.menu and SwiftUI
//        .contextMenu, on the right press or on its release? The menu is
//        cancelled from the main queue once it begins tracking.
//   (No runtime arm for modifiers during a drag: DragGesture.Value has no
//   modifier field — the interface census below is the evidence.)
//
// RECORDED 2026-10-07 by the input-APIs designer, macOS 27.0.1 (26A434),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), Xcode-beta SDK, screen LOCKED (lock
// probe: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Compiled
// form, run twice after the instrument settled: stdout byte-identical (50
// lines), exit 0, stderr empty both times.
//
// RE-RUN 2026-10-07 by the CI critic, same machine and toolchain, screen
// UNLOCKED (lock probe: no CGSSessionScreenIsLocked line, `displayAsleep
// main: 0`): the 50 recorded lines re-read byte for byte, twice. Arms
// P15–P19 were then appended (the mappings CI-H item 8 named but P1–P10 never
// measured) and the whole probe run twice: 61 lines, byte-identical, exit 0,
// stderr empty; lines 1–46 and the C arms unchanged. P15–P19 read through
// `cursorNameWide`, so no earlier line could move.
//
// RE-RUN 2026-10-08 by the second CI critic (ruling CI-AE item 1), same
// machine and toolchain, screen LOCKED: compiled form run twice, all 61
// recorded lines byte-identical both times, exit 0, stderr empty.
//
// INSTRUMENT HISTORY (discarded runs, not answers). Run 1: every CGEvent-made
// event carried a screen location, so R0 (the control) and M0/Q0 read "-" —
// discarded; the CG location is now the window point. Runs 1–4: the P control
// or every P arm read `arrow` — a synthesized `mouseMoved` never reaches
// `pointerStyle`'s tracking-area owner (a `PointerBridge`, area options 0x222:
// mouseMoved | activeInKeyWindow | inVisibleRect), and the window was never
// key; the instrument now uses `KeyWindow` and sends `mouseEntered`/
// `mouseMoved` to the area's owner directly, twice with a 0.5 s spin (run 4,
// with one 0.3 s spin, read `arrow` on every arm but P7 — a timing artefact,
// discarded). Run 6: the nesting arms pointed at local (20,30), outside the
// inner square, so they measured nothing about nesting — discarded; they now
// point at the centre and each has an off-the-inner control (P11c, P13c).
//
// RESULT.
//   T  SpatialTapGesture's `location` is in the gesture view's LOCAL space,
//      top-left origin (T1 (20,10)); `.global` differs (T2 (60,72): the window
//      content's space, here 40+20, 30+10+32 — the hosting view's safe-area/
//      title offset), which separates T1 from "the window point". A double
//      tap reports the location (T4). `onTapGesture(count:coordinateSpace:
//      perform:)` hands the same local point (T3).
//   R  DragGesture follows the PRIMARY button only: a real right press
//      (buttonNumber 1, R4) and a middle press (buttonNumber 2, R2) report
//      nothing, while the primary through the same CGEvent path does (R3).
//      R1's positive answer is an artefact: `NSEvent.mouseEvent(with:
//      .rightMouseDown…)` makes buttonNumber 0, which SwiftUI reads as the
//      primary — R4 is the right button as hardware sends it.
//   M  MagnifyGesture's `magnification` is CUMULATIVE and ADDITIVE from 1:
//      AppKit deltas +0.1, +0.1 read 1.1 then 1.2 (not 1.21); −0.2 reads 0.8.
//      `startLocation` is the local point under the pointer at the gesture's
//      start; `startAnchor` is that point as a UnitPoint of the view's size
//      ((20,20) in 100×100 → (0.2, 0.2)). Control+scroll is not a magnify
//      (M3 "-"): SwiftUI synthesizes no pinch from a modified wheel.
//   Q  RotateGesture's `rotation` is cumulative and its sign is the NEGATIVE
//      of AppKit's `NSEvent.rotation` (AppKit +10°, +10° counterclockwise →
//      −10°, −20°): positive is clockwise on screen, y down. Anchor/start as M.
//   P  `pointerStyle` maps to NSCursor: default → arrow (P1), rectSelection →
//      crosshair, grabIdle → openHand, grabActive → closedHand, link →
//      pointingHand, columnResize → resizeLeftRight (== columnResize),
//      rowResize → resizeUpDown (== rowResize), horizontalText → IBeam,
//      frameResize(position: .trailing) → frameResize(.right), zoomIn → zoomIn.
//      NESTING: the innermost view with a style wins (P11 crosshair; P11c,
//      off the inner square, the outer's pointingHand); an inner
//      `pointerStyle(nil)` has no opinion and the outer's applies (P12).
//      COVER: a view drawn above at the pointer hides a style beneath it,
//      whether it has a gesture (P13 arrow; P13c, off it, crosshair) or only
//      paints (P14 arrow) — SwiftUI's hit region is the drawn view; MetalUI
//      has no hitbox for a view that only paints (divergence, ruling CI-H).
//   P15–P19 (critic): verticalText → iBeamCursorForVerticalLayout; zoomOut →
//      zoomOut; frameResize(position:) maps leading→left, trailing→right,
//      topLeading→topLeft and so on (each read equals the natural AppKit
//      position). BUT `NSCursor ==` compares images: with `.all` a position
//      equals its opposite (top == bottom, topLeft == bottomRight), and
//      (trailing, inward) == (leading, outward). A test comparing cursors
//      therefore cannot separate a mirrored table — pin the position/direction
//      mapping as values, not as cursors (spec §4.1 1.8).
//   C  A context menu opens on the right PRESS, both AppKit's `NSView.menu`
//      (C0) and SwiftUI's `.contextMenu` (C2): tracking began during
//      `rightMouseDown`, before any drag. (C0's view then saw the drag and
//      release only because the probe cancelled the menu.) There is no
//      native "right-drag that does not open the menu" — MetalUI's rule for
//      it is its own (ruling CI-F).
//
// INTERFACE CENSUS (same SDK; `grep -c` over SwiftUI's
// arm64e-apple-macos.swiftinterface, recorded with the run):
//   onScrollWheel 0 · func onScrollPhaseChange 2 · struct SpatialTapGesture 2
//   · struct MagnifyGesture 2 · struct RotateGesture 2 · func pointerStyle 1 ·
//   struct PointerStyle 1 · func onModifierKeysChanged 1 · onTapGesture(count:
//   coordinateSpace:perform:) 3 · DragGesture.Value fields: time, location,
//   startLocation, translation, velocity, predictedEndLocation,
//   predictedEndTranslation — NO `modifiers`; no button parameter on any
//   gesture (the macOS 27 `inputKinds: GestureInputKinds` is directTouch/
//   indirectTouch/pencil/pointer, not a button); "MouseButton|buttonMask|
//   PointerButton" 0 in SwiftUI and SwiftUICore. MagnifyGesture.Value: time,
//   magnification, velocity, startAnchor, startLocation;
//   init(minimumScaleDelta: = 0.01). RotateGesture.Value: time, rotation,
//   velocity, startAnchor, startLocation; init(minimumAngleDelta: = 1°).
//   SpatialTapGesture.Value: location; init(count: = 1, coordinateSpace: =
//   .local). PointerStyle statics: default, horizontalText, verticalText,
//   rectSelection, grabIdle, grabActive, link, zoomIn, zoomOut, columnResize
//   (+ directions:), rowResize (+ directions:), frameResize(position:
//   directions:), image(_:hotSpot:), shape(_:eoFill:size:).
//   Added by the critic (same SDK, `grep -o "func contextMenu[^{]*"`): seven
//   `contextMenu` signatures — `menuItems:`, `menuItems:preview:` (×2),
//   `forSelectionType:menu:primaryAction:`, `_ contextMenu: ContextMenu?`, the
//   `TabContent` and table-row forms — and none passes a location (ruling
//   CI-R).
//
// OUTPUT:
//   --- T: tap location (view 100x100 at (40,30) in a 200x200 window)
//     T0 onTapGesture (control): tap
//     T1 SpatialTapGesture() at local (20,10): loc (20.000, 10.000)
//     T2 SpatialTapGesture(coordinateSpace: .global) at local (20,10): loc (60.000, 72.000)
//     T3 onTapGesture(count: 1, coordinateSpace: .local) at local (70,55): loc (70.000, 55.000)
//     T4 SpatialTapGesture(count: 2) double click at local (20,10): loc (20.000, 10.000)
//   --- R: DragGesture(minimumDistance: 0) pressed by each button at local (20,30) → (60,40)
//       event: type=1 button=0 inWindow=(60.000, 140.000) window=true
//     R0 primary (control): 4 callbacks, first=changed (20.000, 30.000) last=ended (60.000, 40.000)
//       event: type=3 button=0 inWindow=(60.000, 140.000) window=true
//     R1 right: 4 callbacks, first=changed (20.000, 30.000) last=ended (60.000, 40.000)
//       event: type=25 button=2 inWindow=(60.000, 140.000) window=false
//     R2 middle (other), CGEvent path: -
//       event: type=1 button=0 inWindow=(60.000, 140.000) window=false
//     R3 primary, CGEvent path (control for R2/R4): 4 callbacks, first=changed (20.000, 30.000) last=ended (60.000, 40.000)
//       event: type=3 button=1 inWindow=(60.000, 140.000) window=false
//     R4 right, CGEvent path (buttonNumber 1): -
//   --- M: magnify
//       event: type=30 inWindow=(60.000, 150.000) magnification=0.100 rotation=n/a
//     M0 AppKit magnify(with:) (control): magnify 0.000 phase=1 at=(60.000, 150.000) | magnify 0.100 phase=4 at=(60.000, 150.000) | magnify 0.100 phase=4 at=(60.000, 150.000) | magnify 0.000 phase=8 at=(60.000, 150.000)
//     M1 MagnifyGesture, +0.1 +0.1 at local (20,20): changed m=1.100 start=(20.000, 20.000) anchor=(0.200, 0.200) | changed m=1.200 start=(20.000, 20.000) anchor=(0.200, 0.200) | ended m=1.200
//     M2 MagnifyGesture, -0.2 at local (90,90): changed m=0.800 start=(90.000, 90.000) anchor=(0.900, 0.900) | ended m=0.800
//     M3 MagnifyGesture, control+scroll x3 (no pinch): -
//   --- Q: rotate
//       event: type=18 inWindow=(60.000, 150.000) magnification=n/a rotation=10.000
//     Q0 AppKit rotate(with:) (control): rotate 0.000 phase=1 | rotate 10.000 phase=4 | rotate 10.000 phase=4 | rotate 0.000 phase=8
//     Q1 RotateGesture, AppKit +10 +10 (counterclockwise) at local (20,20): changed r=-10.000deg anchor=(0.200, 0.200) start=(20.000, 20.000) | changed r=-20.000deg anchor=(0.200, 0.200) start=(20.000, 20.000) | ended r=-20.000deg
//   --- P: pointerStyle → NSCursor.current after mouseMoved over the view
//     P00 NSCursor.crosshair.set() then NSCursor.current (instrument): crosshair
//     P0 NSView cursorUpdate sets crosshair (control): current=crosshair (cursorUpdate owners: 1)
//     P1 no pointerStyle: current=arrow (events to owners: 0, host tracking areas: [] -)
//     P2 .rectSelection: current=crosshair (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P3 .grabIdle: current=openHand (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P4 .grabActive: current=closedHand (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P5 .link: current=pointingHand (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P6 .columnResize: current=resizeLeftRight=columnResize (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P7 .rowResize: current=resizeUpDown=rowResize (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P8 .horizontalText: current=IBeam (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P9 .frameResize(position: .trailing): current=frameResize(.trailing) (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P10 .zoomIn: current=zoomIn (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<Color, PointerStyleModifier>>>)
//     P11 outer .link, inner 40x40 .rectSelection, over inner: current=crosshair (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>>)
//     P11c same, pointer off the inner square (control): current=pointingHand (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>>)
//     P12 outer .link, inner 40x40 .pointerStyle(nil), over inner: current=pointingHand (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>> | owner=PointerBridge<Offset<ModifiedContent<ZStack<TupleContent<Pack{Color, ModifiedContent<ModifiedContent<Color, _FrameLayout>, PointerStyleModifier>}>>, PointerStyleModifier>>>)
//     P13 .rectSelection on the back view, an opaque 40x40 .onTapGesture sibling over the pointer: current=arrow (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<ModifiedContent<Color, _FrameLayout>, TapGestureModifier>}>>>> | owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<ModifiedContent<Color, _FrameLayout>, TapGestureModifier>}>>>>)
//     P13c same, pointer off the sibling (control): current=crosshair (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<ModifiedContent<Color, _FrameLayout>, TapGestureModifier>}>>>> | owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<ModifiedContent<Color, _FrameLayout>, TapGestureModifier>}>>>>)
//     P14 back view .rectSelection, a 40x40 Color sibling with NO gesture over the pointer: current=arrow (events to owners: 2, host tracking areas: ["222"] owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<Color, _FrameLayout>}>>>> | owner=PointerBridge<Offset<ZStack<TupleContent<Pack{ModifiedContent<Color, PointerStyleModifier>, ModifiedContent<Color, _FrameLayout>}>>>>)
//     P15 .verticalText: current=IBeamVertical
//     P16 .zoomOut: current=zoomOut
//     P17 .frameResize(position: .top): current=frameResize(.top, .all)=frameResize(.bottom, .all)
//     P17 .frameResize(position: .leading): current=frameResize(.left, .all)=frameResize(.right, .all)
//     P17 .frameResize(position: .bottom): current=frameResize(.top, .all)=frameResize(.bottom, .all)
//     P17 .frameResize(position: .topLeading): current=frameResize(.topLeft, .all)=frameResize(.bottomRight, .all)
//     P17 .frameResize(position: .topTrailing): current=frameResize(.topRight, .all)=frameResize(.bottomLeft, .all)
//     P17 .frameResize(position: .bottomLeading): current=frameResize(.topRight, .all)=frameResize(.bottomLeft, .all)
//     P17 .frameResize(position: .bottomTrailing): current=frameResize(.topLeft, .all)=frameResize(.bottomRight, .all)
//     P18 .frameResize(position: .trailing, directions: .inward): current=frameResize(.left, .outward)=frameResize(.right, .inward)
//     P19 .frameResize(position: .top, directions: .outward): current=frameResize(.top, .outward)=frameResize(.bottom, .inward)
//   --- C: context menu: right press at (60,60), right drag to (90,60), release
//     C0 AppKit NSView.menu: menu began tracking during rightMouseDown | view rightMouseDragged | view rightMouseUp
//     C1 AppKit NSView, no menu (control: drag/up reach the view): view rightMouseDragged | view rightMouseUp
//     C2 SwiftUI .contextMenu: menu began tracking during rightMouseDown

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
/// converted event has no window, so `locationInWindow` is the CG location
/// read as a bottom-left screen point; `NSWindow.sendEvent` hit-tests it as a
/// window point. The CG location is therefore the WINDOW point, flipped — the
/// `event:` note line shows `inWindow` equal to the intended point.
@MainActor func cgEvent(_ w: NSWindow, _ make: (CGPoint) -> CGEvent?, _ pt: CGPoint) -> NSEvent? {
    let screenH = NSScreen.screens.first?.frame.height ?? 0
    let loc = CGPoint(x: pt.x, y: screenH - pt.y)
    guard let cg = make(loc) else { return nil }
    cg.location = loc
    return NSEvent(cgEvent: cg)
}

/// A button event made with `NSEvent.mouseEvent` (addressed to `w`); for the
/// other button the CG-made event's `buttonNumber` is carried by converting
/// through CGEvent with the window point.
@MainActor func button(_ w: NSWindow, _ type: CGEventType, _ b: CGMouseButton, _ pt: CGPoint, note: Bool = false,
                       viaCG: Bool = false) {
    let e: NSEvent?
    if b == .center || viaCG {
        e = cgEvent(w, { CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: $0, mouseButton: b) }, pt)
    } else {
        let t: NSEvent.EventType = switch type {
        case .leftMouseDown: .leftMouseDown
        case .leftMouseDragged: .leftMouseDragged
        case .leftMouseUp: .leftMouseUp
        case .rightMouseDown: .rightMouseDown
        case .rightMouseDragged: .rightMouseDragged
        default: .rightMouseUp
        }
        e = NSEvent.mouseEvent(with: t, location: pt, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: 1, pressure: (t == .leftMouseUp || t == .rightMouseUp) ? 0 : 1)
    }
    guard let e else { print("    (no event)"); return }
    if note { print("    event: type=\(e.type.rawValue) button=\(e.buttonNumber) inWindow=\(p(e.locationInWindow)) window=\(e.window === w)") }
    w.sendEvent(e)
}

func gesture(hid: Int64, valueField: UInt32, value: Double, phase: Int64) -> (CGPoint) -> CGEvent? {
    return { loc in
        guard let e = CGEvent(source: nil) else { return nil }
        e.type = CGEventType(rawValue: 29)!
        e.location = loc
        e.setIntegerValueField(CGEventField(rawValue: 110)!, value: hid)
        e.setDoubleValueField(CGEventField(rawValue: valueField)!, value: value)
        e.setIntegerValueField(CGEventField(rawValue: 132)!, value: phase)
        return e
    }
}

// MARK: - T: tap location

struct Offset<C: View>: View {
    let content: C
    var body: some View {
        content.frame(width: 100, height: 100)
            .padding(.leading, 40).padding(.top, 30)
            .frame(width: side, height: side, alignment: .topLeading)
    }
}

@MainActor func tapArm<C: View>(_ label: String, _ view: C, at local: CGPoint, clicks: Int = 1) {
    _ = Log.take()
    let w = makeWindow(Offset(content: view))
    let pt = wp(40 + local.x, 30 + local.y)
    for c in 1...clicks {
        mouse(w, .leftMouseDown, pt, clicks: c); spin(0.05)
        mouse(w, .leftMouseUp, pt, clicks: c); spin(0.05)
    }
    spin(0.6)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
}

// MARK: - R: drag by button

@MainActor func dragArm(_ label: String, _ b: CGMouseButton, viaCG: Bool = false) {
    _ = Log.take()
    let view = Color.gray.gesture(DragGesture(minimumDistance: 0)
        .onChanged { Log.add("changed \(p($0.location))") }
        .onEnded { Log.add("ended \(p($0.location))") })
    let w = makeWindow(Offset(content: view))
    let (down, drag, up): (CGEventType, CGEventType, CGEventType) = switch b {
    case .left: (.leftMouseDown, .leftMouseDragged, .leftMouseUp)
    case .right: (.rightMouseDown, .rightMouseDragged, .rightMouseUp)
    default: (.otherMouseDown, .otherMouseDragged, .otherMouseUp)
    }
    button(w, down, b, wp(60, 60), note: true, viaCG: viaCG); spin(0.05)
    button(w, drag, b, wp(80, 60), viaCG: viaCG); spin(0.05)
    button(w, drag, b, wp(100, 70), viaCG: viaCG); spin(0.05)
    button(w, up, b, wp(100, 70), viaCG: viaCG); spin(0.4)
    // Only the first and last entries: a drag logs one line per move.
    let lines = Log.lines
    _ = Log.take()
    print("  \(label): \(lines.isEmpty ? "-" : "\(lines.count) callbacks, first=\(lines.first!) last=\(lines.last!)")")
    w.orderOut(nil)
}

// MARK: - M / Q: magnify and rotate

final class GestureView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func magnify(with event: NSEvent) {
        Log.add("magnify \(f(event.magnification)) phase=\(event.phase.rawValue) at=\(p(convert(event.locationInWindow, from: nil)))")
    }
    override func rotate(with event: NSEvent) {
        Log.add("rotate \(f(CGFloat(event.rotation))) phase=\(event.phase.rawValue)")
    }
}

@MainActor func sendGesture(_ w: NSWindow, hid: Int64, field: UInt32, values: [Double], at pt: CGPoint, note: Bool) {
    // phases: began (1), changed (2) for each value, ended (4)
    let seq: [(Double, Int64)] = [(0, 1)] + values.map { ($0, 2) } + [(0, 4)]
    for (i, (v, phase)) in seq.enumerated() {
        guard let e = cgEvent(w, gesture(hid: hid, valueField: field, value: v, phase: phase), pt) else {
            print("    (no gesture event)"); return
        }
        if note && i == 1 {
            print("    event: type=\(e.type.rawValue) inWindow=\(p(e.locationInWindow)) magnification=\(e.type == .magnify ? f(e.magnification) : "n/a") rotation=\(e.type == .rotate ? f(CGFloat(e.rotation)) : "n/a")")
        }
        w.sendEvent(e)
        spin(0.05)
    }
    spin(0.4)
}

@MainActor func magnifyArms() {
    _ = Log.take()
    var w = makeWindow(GestureView(frame: CGRect(x: 0, y: 0, width: side, height: side)))
    sendGesture(w, hid: 8, field: 113, values: [0.1, 0.1], at: wp(60, 50), note: true)
    print("  M0 AppKit magnify(with:) (control): \(Log.take())")
    w.orderOut(nil)

    let mag = Color.gray.gesture(MagnifyGesture(minimumScaleDelta: 0)
        .onChanged { Log.add("changed m=\(f($0.magnification)) start=\(p($0.startLocation)) anchor=(\(f($0.startAnchor.x)), \(f($0.startAnchor.y)))") }
        .onEnded { Log.add("ended m=\(f($0.magnification))") })
    w = makeWindow(Offset(content: mag))
    sendGesture(w, hid: 8, field: 113, values: [0.1, 0.1], at: wp(60, 50), note: false)
    print("  M1 MagnifyGesture, +0.1 +0.1 at local (20,20): \(Log.take())")
    w.orderOut(nil)

    w = makeWindow(Offset(content: mag))
    sendGesture(w, hid: 8, field: 113, values: [-0.2], at: wp(130, 120), note: false)
    print("  M2 MagnifyGesture, -0.2 at local (90,90): \(Log.take())")
    w.orderOut(nil)

    w = makeWindow(Offset(content: mag))
    for _ in 0..<3 {
        if let e = cgEvent(w, { loc in
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0)
            cg?.flags = .maskControl
            return cg
        }, wp(60, 50)) { w.sendEvent(e) }
        spin(0.05)
    }
    spin(0.4)
    print("  M3 MagnifyGesture, control+scroll x3 (no pinch): \(Log.take())")
    w.orderOut(nil)
}

@MainActor func rotateArms() {
    _ = Log.take()
    var w = makeWindow(GestureView(frame: CGRect(x: 0, y: 0, width: side, height: side)))
    sendGesture(w, hid: 5, field: 114, values: [10, 10], at: wp(60, 50), note: true)
    print("  Q0 AppKit rotate(with:) (control): \(Log.take())")
    w.orderOut(nil)

    let rot = Color.gray.gesture(RotateGesture(minimumAngleDelta: .zero)
        .onChanged { Log.add("changed r=\(f($0.rotation.degrees))deg anchor=(\(f($0.startAnchor.x)), \(f($0.startAnchor.y))) start=\(p($0.startLocation))") }
        .onEnded { Log.add("ended r=\(f($0.rotation.degrees))deg") })
    w = makeWindow(Offset(content: rot))
    sendGesture(w, hid: 5, field: 114, values: [10, 10], at: wp(60, 50), note: false)
    print("  Q1 RotateGesture, AppKit +10 +10 (counterclockwise) at local (20,20): \(Log.take())")
    w.orderOut(nil)
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

@MainActor func pointerArms() {
    NSCursor.crosshair.set()
    print("  P00 NSCursor.crosshair.set() then NSCursor.current (instrument): \(cursorName(NSCursor.current))")
    NSCursor.arrow.set()
    let w = makeWindow(CrosshairView(frame: CGRect(x: 0, y: 0, width: side, height: side)))
    let n = driveCursorUpdate(w, at: wp(60, 60)); spin(0.3)
    print("  P0 NSView cursorUpdate sets crosshair (control): current=\(cursorName(NSCursor.current)) (cursorUpdate owners: \(n))")
    w.orderOut(nil)
    pointerArm("P1 no pointerStyle", Color.gray)
    pointerArm("P2 .rectSelection", Color.gray.pointerStyle(.rectSelection))
    pointerArm("P3 .grabIdle", Color.gray.pointerStyle(.grabIdle))
    pointerArm("P4 .grabActive", Color.gray.pointerStyle(.grabActive))
    pointerArm("P5 .link", Color.gray.pointerStyle(.link))
    pointerArm("P6 .columnResize", Color.gray.pointerStyle(.columnResize))
    pointerArm("P7 .rowResize", Color.gray.pointerStyle(.rowResize))
    pointerArm("P8 .horizontalText", Color.gray.pointerStyle(.horizontalText))
    pointerArm("P9 .frameResize(position: .trailing)", Color.gray.pointerStyle(.frameResize(position: .trailing)))
    pointerArm("P10 .zoomIn", Color.gray.pointerStyle(.zoomIn))
    // Nesting: an inner view's style inside an outer one's, pointer over the
    // 100x100 view's centre, inside the centred 40x40 inner square. P11c is
    // the same tree with the pointer OFF the inner square (control: outer).
    let center = CGPoint(x: 90, y: 80)
    let nested = ZStack { Color.gray; Color.blue.frame(width: 40, height: 40).pointerStyle(.rectSelection) }
        .pointerStyle(.link)
    pointerArm("P11 outer .link, inner 40x40 .rectSelection, over inner", nested, at: center)
    pointerArm("P11c same, pointer off the inner square (control)", nested)
    pointerArm("P12 outer .link, inner 40x40 .pointerStyle(nil), over inner",
               ZStack { Color.gray; Color.blue.frame(width: 40, height: 40).pointerStyle(nil) }
                   .pointerStyle(.link), at: center)
    pointerArm("P13 .rectSelection on the back view, an opaque 40x40 .onTapGesture sibling over the pointer",
               ZStack { Color.gray.pointerStyle(.rectSelection); Color.blue.frame(width: 40, height: 40).onTapGesture {} },
               at: center)
    pointerArm("P13c same, pointer off the sibling (control)",
               ZStack { Color.gray.pointerStyle(.rectSelection); Color.blue.frame(width: 40, height: 40).onTapGesture {} })
    pointerArm("P14 back view .rectSelection, a 40x40 Color sibling with NO gesture over the pointer",
               ZStack { Color.gray.pointerStyle(.rectSelection); Color.blue.frame(width: 40, height: 40) }, at: center)
    // Added by the CI critic (2026-10-07): the mappings CI-H item 8 names
    // that P1–P10 did not measure. Read with `cursorNameWide`, so the earlier
    // arms' lines (read with `cursorName`) cannot change.
    pointerArmWide("P15 .verticalText", Color.gray.pointerStyle(.verticalText))
    pointerArmWide("P16 .zoomOut", Color.gray.pointerStyle(.zoomOut))
    for (label, pos) in [("top", FrameResizePosition.top), ("leading", .leading), ("bottom", .bottom),
                         ("topLeading", .topLeading), ("topTrailing", .topTrailing),
                         ("bottomLeading", .bottomLeading), ("bottomTrailing", .bottomTrailing)] {
        pointerArmWide("P17 .frameResize(position: .\(label))", Color.gray.pointerStyle(.frameResize(position: pos)))
    }
    pointerArmWide("P18 .frameResize(position: .trailing, directions: .inward)",
                   Color.gray.pointerStyle(.frameResize(position: .trailing, directions: .inward)))
    pointerArmWide("P19 .frameResize(position: .top, directions: .outward)",
                   Color.gray.pointerStyle(.frameResize(position: .top, directions: .outward)))
}

/// `cursorName` widened to every `NSCursor.frameResize(position:directions:)`
/// (eight positions × inward/outward/all) and the vertical I-beam; used only
/// by P15–P19.
@MainActor func cursorNameWide(_ c: NSCursor) -> String {
    var known: [(String, NSCursor)] = [
        ("arrow", .arrow), ("crosshair", .crosshair), ("openHand", .openHand), ("closedHand", .closedHand),
        ("pointingHand", .pointingHand), ("IBeam", .iBeam), ("IBeamVertical", .iBeamCursorForVerticalLayout),
        ("resizeLeftRight", .resizeLeftRight), ("resizeUpDown", .resizeUpDown),
        ("columnResize", .columnResize), ("rowResize", .rowResize), ("zoomIn", .zoomIn), ("zoomOut", .zoomOut),
    ]
    let positions: [(String, NSCursor.FrameResizePosition)] = [
        ("top", .top), ("left", .left), ("bottom", .bottom), ("right", .right),
        ("topLeft", .topLeft), ("topRight", .topRight), ("bottomLeft", .bottomLeft), ("bottomRight", .bottomRight),
    ]
    let directions: [(String, NSCursor.FrameResizeDirection.Set)] = [("inward", .inward), ("outward", .outward), ("all", .all)]
    for (pn, pos) in positions { for (dn, dir) in directions {
        known.append(("frameResize(.\(pn), .\(dn))", .frameResize(position: pos, directions: dir)))
    } }
    let names = known.filter { $0.1 == c }.map(\.0)
    return names.isEmpty ? "other(size=\(c.image.size) hot=\(c.hotSpot))" : names.joined(separator: "=")
}

@MainActor func pointerArmWide<V: View>(_ label: String, _ view: V, at c: CGPoint = CGPoint(x: 60, y: 60)) {
    NSCursor.arrow.set()
    let w = makeWindow(Offset(content: view))
    mouse(w, .mouseMoved, wp(c.x, c.y)); spin(0.1)
    _ = driveCursorUpdate(w, at: wp(c.x, c.y)); spin(0.5)
    _ = driveCursorUpdate(w, at: wp(c.x + 2, c.y + 1)); spin(0.5)
    _ = Log.take()
    print("  \(label): current=\(cursorNameWide(NSCursor.current))")
    w.orderOut(nil)
}

// MARK: - C: context menu timing

final class MenuView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func rightMouseDragged(with event: NSEvent) { Log.add("view rightMouseDragged") }
    override func rightMouseUp(with event: NSEvent) { Log.add("view rightMouseUp") }
}

@MainActor func contextArm(_ label: String, _ content: NSView) {
    _ = Log.take()
    Log.phase = "before-down"
    let token = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification,
                                                       object: nil, queue: nil) { note in
        let current = Log.phase
        MainActor.assumeIsolated {
            Log.add("menu began tracking during \(current)")
            DispatchQueue.main.async { (note.object as? NSMenu)?.cancelTracking() }
        }
    }
    let w = makeWindow(content)
    Log.phase = "rightMouseDown"
    mouse(w, .rightMouseDown, wp(60, 60)); spin(0.1)
    Log.phase = "rightMouseDragged"
    button(w, .rightMouseDragged, .right, wp(90, 60)); spin(0.1)
    Log.phase = "rightMouseUp"
    mouse(w, .rightMouseUp, wp(90, 60)); spin(0.3)
    NotificationCenter.default.removeObserver(token)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
}

@MainActor func contextArms() {
    let v = MenuView(frame: CGRect(x: 0, y: 0, width: side, height: side))
    let m = NSMenu(); m.addItem(withTitle: "Item", action: nil, keyEquivalent: "")
    v.menu = m
    contextArm("C0 AppKit NSView.menu", v)
    let noMenu = MenuView(frame: CGRect(x: 0, y: 0, width: side, height: side))
    contextArm("C1 AppKit NSView, no menu (control: drag/up reach the view)", noMenu)
    contextArm("C2 SwiftUI .contextMenu", FirstMouseHost(rootView: Color.gray.contextMenu { Button("Item") {} }))
}

// MARK: - run

@MainActor func run() {
    print("--- T: tap location (view 100x100 at (40,30) in a 200x200 window)")
    tapArm("T0 onTapGesture (control)", Color.gray.onTapGesture { Log.add("tap") }, at: CGPoint(x: 20, y: 10))
    tapArm("T1 SpatialTapGesture() at local (20,10)",
           Color.gray.gesture(SpatialTapGesture().onEnded { Log.add("loc \(p($0.location))") }), at: CGPoint(x: 20, y: 10))
    tapArm("T2 SpatialTapGesture(coordinateSpace: .global) at local (20,10)",
           Color.gray.gesture(SpatialTapGesture(coordinateSpace: .global).onEnded { Log.add("loc \(p($0.location))") }),
           at: CGPoint(x: 20, y: 10))
    tapArm("T3 onTapGesture(count: 1, coordinateSpace: .local) at local (70,55)",
           Color.gray.onTapGesture(count: 1, coordinateSpace: .local) { Log.add("loc \(p($0))") }, at: CGPoint(x: 70, y: 55))
    tapArm("T4 SpatialTapGesture(count: 2) double click at local (20,10)",
           Color.gray.gesture(SpatialTapGesture(count: 2).onEnded { Log.add("loc \(p($0.location))") }),
           at: CGPoint(x: 20, y: 10), clicks: 2)
    print("--- R: DragGesture(minimumDistance: 0) pressed by each button at local (20,30) → (60,40)")
    dragArm("R0 primary (control)", .left)
    dragArm("R1 right", .right)
    dragArm("R2 middle (other), CGEvent path", .center)
    dragArm("R3 primary, CGEvent path (control for R2/R4)", .left, viaCG: true)
    dragArm("R4 right, CGEvent path (buttonNumber 1)", .right, viaCG: true)
    print("--- M: magnify")
    magnifyArms()
    print("--- Q: rotate")
    rotateArms()
    print("--- P: pointerStyle → NSCursor.current after mouseMoved over the view")
    pointerArms()
    print("--- C: context menu: right press at (60,60), right drag to (90,60), release")
    contextArms()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
