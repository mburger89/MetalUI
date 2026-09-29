// SwiftUI probe: interaction (plan task 12, part 1) — gesture recognition and
// precedence, button semantics (pressed state, roles, keyboard shortcuts),
// disabled/inactive looks, keyboard focus (`@FocusState`, click-to-focus,
// focus across an identity change and across a disable) and content shapes.
//
// Evidence for rulings IX-A… in
// docs/superpowers/2026-09-29-interaction-decisions.md.
//
// HOW TO RUN (ruling SA-O's compiled form; the script form stopped with a JIT
// link error on this toolchain in task 10's probes and is not relied on):
//
//   xcrun swiftc docs/probes/swiftui-interaction.swift -o /tmp/ix-probe && /tmp/ix-probe
//
// THE INSTRUMENT. Every arm opens a fresh 200x200 window hosting the view in a
// `FirstMouseHost` (accepts first mouse — the script is not a bundled app, so
// the window is never key-active), and sends `NSEvent`s through
// `NSWindow.sendEvent` with a run-loop spin between each (the down/spin/up
// order `swiftui-disabled-interaction.swift` established; without the spin a
// synthesized click never reaches SwiftUI's gesture system, which is what
// `swiftui-controls-and-selection.swift`'s CK0 recorded). Window coordinates
// have their origin at the BOTTOM left. Keys go through `NSApp.sendEvent`.
// Each arm logs what fired, in order, into one string.
//
// POSITIVE CONTROLS. G0 (a full-window `onTapGesture`) reads 1: the harness
// delivers a click. K0 (a `.focusable()` view focused in `onAppear`) receives
// a key: the key harness works. C0 (a full-window colour) reads 1 at the
// corner point every shape arm uses. PX0 samples a known opaque colour. Every
// arm that reads 0 is read against one of these.
//
// RECORDED 2026-09-29 by the plan task 12 part 1 design session, macOS 27.0,
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen LOCKED (lock probe:
// `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Compiled form, run
// twice: stdout byte-identical (156 lines), exit 0, stderr empty both times.
// Two earlier revisions (without G2e-G2g/G5d/G5e, then without F9) were each
// run twice, byte-identical, and every line they share with this revision is
// identical to it. `swiftui-content-shape-hit-region.swift`,
// `swiftui-disabled-interaction.swift` and
// `swiftui-disabled-ancestor-and-order.swift` were re-run the same session and
// read their recorded values.
//
// WHAT THE INSTRUMENT CANNOT SEE (recorded as unmeasured, never as SwiftUI's):
// - TEXT AND BEZELS in the offscreen capture: the hosting layer renders
//   without its text and the AppKit bezels. PX11 (a bare `Text`) reads pure
//   white, so every PX "ink" column is blind, and PX1-PX16, PX18, PX20, PX21
//   and PX22 read the white canvas. Only an ACCENT FILL is visible (PX17,
//   PX19), and PX0 (a plain red rectangle) shows the capture itself works.
// - A KEY WINDOW: the script is never the active application, so an
//   unmodified window reads `controlActiveState` `inactive` (PX23); PX15-PX20
//   write the environment value directly instead.
// - THE FOCUS RING: F7 and F8 are identical.
//
//   --- G: gesture recognition (200x200 window; centre (100,100))
//     G0 Color.onTapGesture, click (control): tap
//     G1 Color.onTapGesture, log after DOWN then after UP: |down,tap
//     G2a tap, drag 60pt INSIDE then release inside: -
//     G2b tap, drag 5pt then release: -
//     G2e tap, drag 1pt then release: tap
//     G2f tap, a zero-distance dragged event then release: tap
//     G2g tap, drag 2pt in one event then release: tap
//     G2g tap, drag 3pt in one event then release: tap
//     G2g tap, drag 4pt in one event then release: tap
//     G2c tap in a 100x100 view, drag OUT and release outside: -
//     G2d tap in a 100x100 view, drag OUT and BACK, release inside: -
//     G3a onTapGesture(count: 2), single click: -
//     G3b onTapGesture(count: 2), double click: double
//     G4a count:2 then count:1 (double inner), single click: single
//     G4b count:2 then count:1 (double inner), double click: double
//     G5a count:1 then count:2 (single inner), single click: single
//     G5b count:1 then count:2 (single inner), double click: double
//     G5c G4's view, single click, log at 0.1s then at 0.8s: |0.15s,single
//     NSEvent.doubleClickInterval = 0.5
//     G5d G4's view, single click, log at 0.25s, 0.45s, 0.65s: |0.25s,single,|0.45s,|0.65s
//     G5e G4's view, single click, log every 0.04s from 0.27s to 0.43s after release: |0.27s,|0.31s,single,|0.35s,|0.39s,|0.43s
//     G6a LongPressGesture(0.3), hold 0.6s, log before release: long,|held
//     G6b LongPressGesture(0.3), quick click: -
//     G6c LongPressGesture(0.3), hold with a 30pt drag: -
//     G6d LongPressGesture(0.3), hold with a 5pt drag: long
//     G6e onLongPressGesture(0.3) perform+pressing, hold 0.6s: pressing=true,perform,|held,pressing=false
//     G6f onLongPressGesture(0.3) perform+pressing, quick click: pressing=true,pressing=false
//     G7a tap then .gesture(long) on one view, quick click: tap
//     G7b tap then .gesture(long) on one view, hold 0.6s: |held,tap
//     G8a DragGesture(), drag +50x in 10 steps: chg(10,0),chg(15,0),chg(20,0),chg(25,0),chg(30,0),chg(35,0),chg(40,0),chg(45,0),chg(50,0),end(50,0) start(100,100)
//     G8b DragGesture(), drag +50y (window up) in 10 steps: chg(0,-10),chg(0,-15),chg(0,-20),chg(0,-25),chg(0,-30),chg(0,-35),chg(0,-40),chg(0,-45),chg(0,-50),end(0,-50) start(100,100)
//     G8c DragGesture(), drag 6pt: -
//     G8d DragGesture(), click: -
//     G8e DragGesture(minimumDistance: 0), click: chg,end
//     G8f DragGesture(), drag out of the window and release outside: chg(16,0),chg(32,0),chg(48,0),chg(64,0),chg(80,0),chg(96,0),chg(112,0),chg(128,0),chg(144,0),chg(160,0),end(160,0) start(100,100)
//     G9a tap + .gesture(drag) one view, click: tap
//     G9b tap + .gesture(drag) one view, drag 50: dragEnd
//   --- H: parent/child precedence (child 100x100 centred; click child at centre, parent at edge)
//     H0 child onTap, parent onTap click child: c
//     H0 child onTap, parent onTap click parent-only area: p
//     H1 child onTap, parent .gesture(Tap) click child: c
//     H1 child onTap, parent .gesture(Tap) click parent-only area: p
//     H2 child onTap, parent .highPriorityGesture(Tap) click child: p
//     H2 child onTap, parent .highPriorityGesture(Tap) click parent-only area: p
//     H3 child onTap, parent .simultaneousGesture(Tap) click child: p,c
//     H3 child onTap, parent .simultaneousGesture(Tap) click parent-only area: p
//     H4a child drag, parent onTap: click child: p
//     H4b child drag, parent onTap: drag child 40: cDrag
//     H5a child onTap, parent .gesture(drag): click child: c
//     H5b child onTap, parent .gesture(drag): drag from child 40: pDrag
//     H6a child onTap, parent .highPriorityGesture(drag): click child: c
//     H6b child onTap, parent .highPriorityGesture(drag): drag from child 40: pDrag
//     H7 .plain Button child, parent .simultaneousGesture(Tap) click child: p,button
//     H7 .plain Button child, parent .simultaneousGesture(Tap) click parent-only area: p
//     H8 .plain Button child, parent .highPriorityGesture(Tap) click child: p
//     H8 .plain Button child, parent .highPriorityGesture(Tap) click parent-only area: p
//     H9 .plain Button child, parent onTap click child: button
//     H9 .plain Button child, parent onTap click parent-only area: p
//     H10 Button .simultaneousGesture(Tap) on the button itself: sim,button
//     H11 Button .highPriorityGesture(Tap) on the button itself: high
//     H12 Color .onTapGesture then .gesture(Tap) on one view: inner
//     H13 Color .onTapGesture then .simultaneousGesture(Tap) on one view: outer,inner
//     H14 Color .onTapGesture then .highPriorityGesture(Tap) on one view: outer
//     H15a Tap(2).exclusively(before: Tap), single: single
//     H15b Tap(2).exclusively(before: Tap), double: double
//     H16a Tap.simultaneously(with: Long 0.3), quick click: tap
//     H16b Tap.simultaneously(with: Long 0.3), hold 0.6: long,|held,tap
//     H17 disabled child drag, parent onTap: drag child: p
//     H18 plain Color over a tappable (no gesture on top): -
//   --- B: buttons
//     B0 isPressed: down, spin, up: pressed=true,|down,action,pressed=false
//     B1 isPressed: down, drag OUT, drag BACK, up inside: pressed=true,|down,pressed=false,|out,pressed=true,|back,action,pressed=false
//     B2 isPressed: down, drag OUT, up outside: pressed=true,pressed=false,|out
//     B3 isPressed: long hold 0.8s then up: pressed=true,|held,action,pressed=false
//     B4a keyboardShortcut(.defaultAction), Return: ok
//     B4b keyboardShortcut(.cancelAction), Escape: cancel
//     B4c Button(role: .cancel) no shortcut, Escape: -
//     B4d Button(role: .destructive) no shortcut, Return: -
//     B4e keyboardShortcut("k") (default .command), cmd-k: k
//     B4f keyboardShortcut("k") (default .command), plain k: -
//     B4g keyboardShortcut("k", modifiers: []), plain k: k
//     B4h two buttons, same cmd-k: A
//     B4i cmd-k on a .focusable() view's onKeyPress AND a button shortcut; view focused: view
//     B4j shortcut on a Button inside .hidden()? (opacity 0): k
//     B4k shortcut on a .plain onTapGesture-less Color? .keyboardShortcut on non-button view: -
//     B4l keyboardShortcut(.defaultAction) disabled, Return: -
//     B5 click on Button(role: .destructive) plain: d
//   --- PX: looks (offscreen capture of the hosting view; 200x200)
//     PX0 control: solid red 80x30: ink (255,0,0) red (255,0,0) fill (255,0,0)
//     PX1 Button("Delete") enabled: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX2 Button("Delete") .disabled(true): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX3 Button("Delete", role: .destructive): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX4 Button("Delete", role: .cancel): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX5 Button("Delete") .borderedProminent: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX6 Button("Delete") .borderedProminent .disabled(true): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX7 Button("Delete") .plain: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX8 Button("Delete") .plain .disabled(true): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX9 Button("Delete") .borderless: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX10 Button("Delete") .borderless .disabled(true): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX11 Text("Delete") plain: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX12 Text("Delete") .disabled(true): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX13 Button("Delete", role: .destructive) .borderedProminent: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX14 Button("Delete", role: .destructive) .plain: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX15 Button("Delete") env controlActiveState .key: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX16 Button("Delete") env controlActiveState .inactive: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX17 .borderedProminent env controlActiveState .key: ink (1,122,255) red (0,0,0) fill (255,255,255)
//     PX18 .borderedProminent env controlActiveState .inactive: ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX19 Toggle env controlActiveState .key (on): ink (6,126,255) red (0,0,0) fill (255,255,255)
//     PX20 Toggle env controlActiveState .inactive (on): ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX21 bordered Button pressed: before ink (255,255,255) red (0,0,0) fill (255,255,255) | held ink (255,255,255) red (0,0,0) fill (255,255,255)
//     PX22 borderedProminent pressed: before ink (255,255,255) red (0,0,0) fill (255,255,255) | held ink (255,255,255) red (0,0,0) fill (255,255,255)
//     controlActiveState read in the window: -
//     PX23 controlActiveState of an unmodified window: inactive
//   --- F: focus
//     NSApp.isFullKeyboardAccessEnabled = false
//     K0 focusable view focused in onAppear, key x (control): key
//     F1 focused .id("a") renamed to "b", then key, then back to "a", then key: focused=true,|start,focused=false,|renamed,|back
//     F2 focused view removed by an if, key, returned, key: focused=true,|start,focused=false,|removed,|returned
//     F3 click a .focusable() view (left), then click a tappable (right): focus=left,|clickedLeft,tapRight
//     F4 left focused; click a plain gesture-less view (right): focus=left,|start
//     F5 Tab from one (.focusable) past Button two to three: focus=one,|start
//     F9 .focusable().hidden() focused in onAppear, key x: -
//     F6 click a Button: does it take focus?: |start
//     F7 .focusable() white 80x30 unfocused: ink (152,152,157) red (0,0,0) fill (152,152,157)
//     F8 same, focused (ring?): ink (152,152,157) red (0,0,0) fill (152,152,157)
//   --- C: content shapes (a 200x200 view; clicks at centre and at corner (12,12))
//     C0 Color.onTapGesture (control) centre: hit
//     C0 Color.onTapGesture (control) corner: hit
//     C1 Color.contentShape(Circle()).onTapGesture centre: hit
//     C1 Color.contentShape(Circle()).onTapGesture corner: -
//     C2 Color.onTapGesture.contentShape(Circle()) (shape AFTER the gesture) centre: hit
//     C2 Color.onTapGesture.contentShape(Circle()) (shape AFTER the gesture) corner: -
//     C3 Color.clipShape(Circle()).onTapGesture centre: hit
//     C3 Color.clipShape(Circle()).onTapGesture corner: hit
//     C4 Color.onTapGesture.clipShape(Circle()) centre: hit
//     C4 Color.onTapGesture.clipShape(Circle()) corner: hit
//     C5 Circle().fill.onTapGesture centre: hit
//     C5 Circle().fill.onTapGesture corner: -
//     C6 RoundedRectangle(60).fill.onTapGesture centre: hit
//     C6 RoundedRectangle(60).fill.onTapGesture corner: -
//     C7 Circle().stroke(lineWidth: 10).onTapGesture centre: -
//     C7 Circle().stroke(lineWidth: 10).onTapGesture corner: -
//     C7b the same, click ON the stroke (100,5): hit
//     C8 Color.clipped() (rect) .onTapGesture centre: hit
//     C8 Color.clipped() (rect) .onTapGesture corner: hit
//     C9 Color.cornerRadius(60).onTapGesture centre: hit
//     C9 Color.cornerRadius(60).onTapGesture corner: hit
//     C10 Color.contentShape(Circle()) under .plain Button centre: hit
//     C10 Color.contentShape(Circle()) under .plain Button corner: -
//     C11 Color.contentShape(RoundedRectangle(60)).onTapGesture centre: hit
//     C11 Color.contentShape(RoundedRectangle(60)).onTapGesture corner: -
//     C12 Circle over tappable Color (Circle no gesture) centre: -
//     C12 Circle over tappable Color (Circle no gesture) corner: under
//     C13 Color.contentShape(Circle()).onHover-less .onTapGesture inside .padding(0) centre: hit
//     C13 Color.contentShape(Circle()).onHover-less .onTapGesture inside .padding(0) corner: -
//
// THE READING (rulings IX-C, IX-D, IX-E, IX-F, IX-H, IX-I, IX-K, IX-L).
// - G1: a tap ends on the release. G2: it fails once the pointer moves 5 pt
//   (4 pt passes, 5 pt fails), out-and-back included (G2d).
// - G3-G5: a count-2 tap ends on the second release; a count-1 tap sharing the
//   view waits until the double can no longer happen, whichever is inner, and
//   then fires between 0.31 and 0.35 s after its release (G5e) - not at
//   `doubleClickInterval` (0.5).
// - G6: a long press ends while held at its duration, fails on a quick click
//   and past 10 pt of movement (30 pt fails, 5 pt does not);
//   `onPressingChanged` brackets the press.
// - G8: a drag changes from exactly `minimumDistance` (first change at 10),
//   ends wherever it is released, is local and y-down; `minimumDistance: 0`
//   reports a click.
// - G7, G9, H0-H17: an inner normal gesture beats an outer one; a
//   high-priority outer gesture beats the inner; a simultaneous gesture fires
//   too, and FIRST; a lower gesture ends only after every higher one failed (a
//   failed child drag hands the click to the parent's tap, H4a; an outer long
//   press never ends while an inner tap is pending, G7b). One view's
//   modifiers read exactly as a parent/child pair (H12-H14 = H1-H3).
// - B0-B3: `isPressed` is "pressed and over it"; the action runs on a release
//   over the button, excursion allowed (B1), not outside (B2).
// - B4: a role binds no key; `.defaultAction`/`.cancelAction` are Return and
//   Escape; the modifiers match exactly; the first button in tree order wins a
//   shared shortcut; a focused view's key handler claims first; a disabled
//   button's shortcut is silent; an invisible one's fires;
//   `.keyboardShortcut` on a non-button does nothing.
// - PX17-PX20: an accent control loses its accent when `controlActiveState`
//   is `inactive`.
// - F1, F2: focus drops when the focused identity is renamed or removed, and
//   does not return with it. F3, F4: a click focuses a `.focusable()` view; a
//   click elsewhere does not unfocus it. F5, F6: with Full Keyboard Access
//   off, Tab moves focus nowhere and a clicked `Button` takes none. F9: a
//   hidden focusable view never takes focus, and its key handler never runs.
// - C1-C13: `.contentShape(Circle())` (either order) refuses the corner;
//   `clipShape`, `clipped()` and `cornerRadius` do not restrict a hit; a
//   filled shape is hit by its shape, a stroked one on its stroke; a
//   gesture-less shape over a tappable swallows where it draws.

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
        return lines.isEmpty ? "-" : lines.joined(separator: ",")
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin()
    return w
}

@MainActor func mouse(_ w: NSWindow, _ t: NSEvent.EventType, _ p: CGPoint, clicks: Int = 1) {
    let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                               clickCount: clicks, pressure: t == .leftMouseUp ? 0 : 1)!
    w.sendEvent(e)
}

@MainActor func click(_ w: NSWindow, at p: CGPoint, clicks: Int = 1, hold: Double = 0.05) {
    mouse(w, .leftMouseDown, p, clicks: clicks)
    spin(hold)
    mouse(w, .leftMouseUp, p, clicks: clicks)
    spin()
}

@MainActor func doubleClick(_ w: NSWindow, at p: CGPoint) {
    mouse(w, .leftMouseDown, p, clicks: 1); spin(0.03)
    mouse(w, .leftMouseUp, p, clicks: 1); spin(0.05)
    mouse(w, .leftMouseDown, p, clicks: 2); spin(0.03)
    mouse(w, .leftMouseUp, p, clicks: 2); spin(0.8)
}

/// Press at `from`, drag in `steps` equal moves to `to`, then release at `to`.
@MainActor func drag(_ w: NSWindow, from: CGPoint, to: CGPoint, steps: Int = 10) {
    mouse(w, .leftMouseDown, from); spin(0.05)
    for i in 1...steps {
        let f = CGFloat(i) / CGFloat(steps)
        mouse(w, .leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f))
        spin(0.02)
    }
    mouse(w, .leftMouseUp, to)
    spin()
}

@MainActor func key(_ w: NSWindow, _ chars: String, modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0) {
    let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                isARepeat: false, keyCode: keyCode)!
    NSApp.sendEvent(down)
    spin()
}

let centre = CGPoint(x: 100, y: 100)
let corner = CGPoint(x: 12, y: 12)
let edge = CGPoint(x: 20, y: 100)

@MainActor func arm<V: View>(_ label: String, _ view: V, _ act: (NSWindow) -> Void) {
    _ = Log.take()
    let w = makeWindow(view)
    act(w)
    print("  \(label): \(Log.take())")
    w.orderOut(nil)
}

// MARK: - pixels

/// The hosting view's pixels, drawn offscreen.
@MainActor func capture(_ w: NSWindow) -> NSBitmapImageRep {
    let v = w.contentView!
    v.layoutSubtreeIfNeeded()
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(v.bounds.width * scale),
                               pixelsHigh: Int(v.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.cgContext.scaleBy(x: scale, y: scale)
    // CALayer renders flipped relative to the bitmap's origin; flip so row 0 is the top.
    ctx.cgContext.translateBy(x: 0, y: v.bounds.height)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    v.layer!.render(in: ctx.cgContext)
    return rep
}

struct RGB: CustomStringConvertible {
    var r: Int, g: Int, b: Int
    var description: String { "(\(r),\(g),\(b))" }
    var luma: Int { (r * 299 + g * 587 + b * 114) / 1000 }
}

func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> RGB {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    return RGB(r: Int((c.redComponent * 255).rounded()), g: Int((c.greenComponent * 255).rounded()),
               b: Int((c.blueComponent * 255).rounded()))
}

/// The darkest pixel (label ink), the reddest pixel, and the colour at the
/// rep's centre row a few points in from the left of `rect` (the fill), in
/// view points scaled to the rep.
func sample(_ rep: NSBitmapImageRep, rect: CGRect) -> String {
    let sx = CGFloat(rep.pixelsWide) / 200, sy = CGFloat(rep.pixelsHigh) / 200
    var darkest = RGB(r: 255, g: 255, b: 255), reddest = RGB(r: 0, g: 0, b: 0)
    for y in Int(rect.minY * sy)..<Int(rect.maxY * sy) {
        for x in Int(rect.minX * sx)..<Int(rect.maxX * sx) {
            let p = pixel(rep, x, y)
            if p.luma < darkest.luma { darkest = p }
            if p.r - max(p.g, p.b) > reddest.r - max(reddest.g, reddest.b) { reddest = p }
        }
    }
    let fill = pixel(rep, Int((rect.minX + 3) * sx), Int(rect.midY * sy))
    return "ink \(darkest) red \(reddest) fill \(fill)"
}

// MARK: - G: gestures

@MainActor func armG() {
    print("--- G: gesture recognition (200x200 window; centre (100,100))")
    arm("G0 Color.onTapGesture, click (control)", Color.blue.onTapGesture { Log.add("tap") }) {
        click($0, at: centre)
    }
    arm("G1 Color.onTapGesture, log after DOWN then after UP", Color.blue.onTapGesture { Log.add("tap") }) { w in
        mouse(w, .leftMouseDown, centre); spin(0.2); Log.add("|down"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("G2a tap, drag 60pt INSIDE then release inside", Color.blue.onTapGesture { Log.add("tap") }) {
        drag($0, from: centre, to: CGPoint(x: 160, y: 100))
    }
    arm("G2b tap, drag 5pt then release", Color.blue.onTapGesture { Log.add("tap") }) {
        drag($0, from: centre, to: CGPoint(x: 105, y: 100), steps: 2)
    }
    arm("G2e tap, drag 1pt then release", Color.blue.onTapGesture { Log.add("tap") }) {
        drag($0, from: centre, to: CGPoint(x: 101, y: 100), steps: 1)
    }
    arm("G2f tap, a zero-distance dragged event then release", Color.blue.onTapGesture { Log.add("tap") }) {
        drag($0, from: centre, to: centre, steps: 1)
    }
    for d in [2, 3, 4] {
        arm("G2g tap, drag \(d)pt in one event then release", Color.blue.onTapGesture { Log.add("tap") }) {
            drag($0, from: centre, to: CGPoint(x: 100 + CGFloat(d), y: 100), steps: 1)
        }
    }
    arm("G2c tap in a 100x100 view, drag OUT and release outside",
        ZStack { Color.gray; Color.blue.frame(width: 100, height: 100).onTapGesture { Log.add("tap") } }) {
        drag($0, from: centre, to: CGPoint(x: 190, y: 100))
    }
    arm("G2d tap in a 100x100 view, drag OUT and BACK, release inside",
        ZStack { Color.gray; Color.blue.frame(width: 100, height: 100).onTapGesture { Log.add("tap") } }) { w in
        mouse(w, .leftMouseDown, centre); spin(0.05)
        mouse(w, .leftMouseDragged, CGPoint(x: 190, y: 100)); spin(0.05)
        mouse(w, .leftMouseDragged, CGPoint(x: 101, y: 100)); spin(0.05)
        mouse(w, .leftMouseUp, CGPoint(x: 101, y: 100)); spin()
    }
    arm("G3a onTapGesture(count: 2), single click", Color.blue.onTapGesture(count: 2) { Log.add("double") }) {
        click($0, at: centre); spin(0.6)
    }
    arm("G3b onTapGesture(count: 2), double click", Color.blue.onTapGesture(count: 2) { Log.add("double") }) {
        doubleClick($0, at: centre)
    }
    let doubleThenSingle = Color.blue.onTapGesture(count: 2) { Log.add("double") }.onTapGesture { Log.add("single") }
    arm("G4a count:2 then count:1 (double inner), single click", doubleThenSingle) {
        click($0, at: centre); spin(0.8)
    }
    arm("G4b count:2 then count:1 (double inner), double click", doubleThenSingle) { doubleClick($0, at: centre) }
    let singleThenDouble = Color.blue.onTapGesture { Log.add("single") }.onTapGesture(count: 2) { Log.add("double") }
    arm("G5a count:1 then count:2 (single inner), single click", singleThenDouble) {
        click($0, at: centre); spin(0.8)
    }
    arm("G5b count:1 then count:2 (single inner), double click", singleThenDouble) { doubleClick($0, at: centre) }
    arm("G5c G4's view, single click, log at 0.1s then at 0.8s", doubleThenSingle) { w in
        click(w, at: centre, hold: 0.03); Log.add("|0.15s"); spin(0.65)
    }
    print("  NSEvent.doubleClickInterval = \(NSEvent.doubleClickInterval)")
    arm("G5d G4's view, single click, log at 0.25s, 0.45s, 0.65s", doubleThenSingle) { w in
        click(w, at: centre, hold: 0.03); spin(0.1); Log.add("|0.25s"); spin(0.2); Log.add("|0.45s")
        spin(0.2); Log.add("|0.65s"); spin(0.3)
    }
    arm("G5e G4's view, single click, log every 0.04s from 0.27s to 0.43s after release", doubleThenSingle) { w in
        mouse(w, .leftMouseDown, centre); spin(0.03); mouse(w, .leftMouseUp, centre)
        spin(0.27); Log.add("|0.27s")
        for t in [0.31, 0.35, 0.39, 0.43] { spin(0.04); Log.add("|\(t)s") }
        spin(0.4)
    }
    let long = Color.blue.gesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in Log.add("long") })
    arm("G6a LongPressGesture(0.3), hold 0.6s, log before release", long) { w in
        mouse(w, .leftMouseDown, centre); spin(0.6); Log.add("|held"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("G6b LongPressGesture(0.3), quick click", long) { click($0, at: centre) }
    arm("G6c LongPressGesture(0.3), hold with a 30pt drag", long) { w in
        mouse(w, .leftMouseDown, centre); spin(0.05)
        mouse(w, .leftMouseDragged, CGPoint(x: 130, y: 100)); spin(0.6)
        mouse(w, .leftMouseUp, CGPoint(x: 130, y: 100)); spin()
    }
    arm("G6d LongPressGesture(0.3), hold with a 5pt drag", long) { w in
        mouse(w, .leftMouseDown, centre); spin(0.05)
        mouse(w, .leftMouseDragged, CGPoint(x: 105, y: 100)); spin(0.6)
        mouse(w, .leftMouseUp, CGPoint(x: 105, y: 100)); spin()
    }
    let pressing = Color.blue.onLongPressGesture(minimumDuration: 0.3) { Log.add("perform") }
        onPressingChanged: { Log.add("pressing=\($0)") }
    arm("G6e onLongPressGesture(0.3) perform+pressing, hold 0.6s", pressing) { w in
        mouse(w, .leftMouseDown, centre); spin(0.6); Log.add("|held"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("G6f onLongPressGesture(0.3) perform+pressing, quick click", pressing) { click($0, at: centre) }
    let longAndTap = Color.blue.onTapGesture { Log.add("tap") }
        .gesture(LongPressGesture(minimumDuration: 0.3).onEnded { _ in Log.add("long") })
    arm("G7a tap then .gesture(long) on one view, quick click", longAndTap) { click($0, at: centre) }
    arm("G7b tap then .gesture(long) on one view, hold 0.6s", longAndTap) { w in
        mouse(w, .leftMouseDown, centre); spin(0.6); Log.add("|held"); mouse(w, .leftMouseUp, centre); spin()
    }
    let dragView = Color.blue.gesture(DragGesture()
        .onChanged { v in Log.add("chg(\(Int(v.translation.width)),\(Int(v.translation.height)))") }
        .onEnded { v in Log.add("end(\(Int(v.translation.width)),\(Int(v.translation.height))) start(\(Int(v.startLocation.x)),\(Int(v.startLocation.y)))") })
    arm("G8a DragGesture(), drag +50x in 10 steps", dragView) {
        drag($0, from: centre, to: CGPoint(x: 150, y: 100))
    }
    arm("G8b DragGesture(), drag +50y (window up) in 10 steps", dragView) {
        drag($0, from: centre, to: CGPoint(x: 100, y: 150))
    }
    arm("G8c DragGesture(), drag 6pt", dragView) { drag($0, from: centre, to: CGPoint(x: 106, y: 100), steps: 3) }
    arm("G8d DragGesture(), click", dragView) { click($0, at: centre) }
    arm("G8e DragGesture(minimumDistance: 0), click", Color.blue.gesture(DragGesture(minimumDistance: 0)
        .onChanged { _ in Log.add("chg") }.onEnded { _ in Log.add("end") })) { click($0, at: centre) }
    arm("G8f DragGesture(), drag out of the window and release outside", dragView) {
        drag($0, from: centre, to: CGPoint(x: 260, y: 100))
    }
    let dragAndTap = Color.blue.onTapGesture { Log.add("tap") }
        .gesture(DragGesture().onEnded { _ in Log.add("dragEnd") })
    arm("G9a tap + .gesture(drag) one view, click", dragAndTap) { click($0, at: centre) }
    arm("G9b tap + .gesture(drag) one view, drag 50", dragAndTap) {
        drag($0, from: centre, to: CGPoint(x: 150, y: 100))
    }
}

// MARK: - H: hierarchy precedence (child 100x100 at the centre of a 200x200 parent)

@MainActor func child() -> some View { Color.blue.frame(width: 100, height: 100) }

@MainActor func armH() {
    print("--- H: parent/child precedence (child 100x100 centred; click child at centre, parent at edge)")
    func pc<V: View>(_ label: String, _ v: V) {
        arm("\(label) click child", v) { click($0, at: centre) }
        arm("\(label) click parent-only area", v) { click($0, at: edge) }
    }
    pc("H0 child onTap, parent onTap", ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .onTapGesture { Log.add("p") })
    pc("H1 child onTap, parent .gesture(Tap)", ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .gesture(TapGesture().onEnded { Log.add("p") }))
    pc("H2 child onTap, parent .highPriorityGesture(Tap)", ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .highPriorityGesture(TapGesture().onEnded { Log.add("p") }))
    pc("H3 child onTap, parent .simultaneousGesture(Tap)", ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .simultaneousGesture(TapGesture().onEnded { Log.add("p") }))
    let childDragParentTap = ZStack { Color.gray; child().gesture(DragGesture().onEnded { _ in Log.add("cDrag") }) }
        .onTapGesture { Log.add("p") }
    arm("H4a child drag, parent onTap: click child", childDragParentTap) { click($0, at: centre) }
    arm("H4b child drag, parent onTap: drag child 40", childDragParentTap) {
        drag($0, from: centre, to: CGPoint(x: 140, y: 100))
    }
    let childTapParentDrag = ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .gesture(DragGesture().onEnded { _ in Log.add("pDrag") })
    arm("H5a child onTap, parent .gesture(drag): click child", childTapParentDrag) { click($0, at: centre) }
    arm("H5b child onTap, parent .gesture(drag): drag from child 40", childTapParentDrag) {
        drag($0, from: centre, to: CGPoint(x: 140, y: 100))
    }
    let childTapParentHighDrag = ZStack { Color.gray; child().onTapGesture { Log.add("c") } }
        .highPriorityGesture(DragGesture().onEnded { _ in Log.add("pDrag") })
    arm("H6a child onTap, parent .highPriorityGesture(drag): click child", childTapParentHighDrag) {
        click($0, at: centre)
    }
    arm("H6b child onTap, parent .highPriorityGesture(drag): drag from child 40", childTapParentHighDrag) {
        drag($0, from: centre, to: CGPoint(x: 140, y: 100))
    }
    let buttonInTappable = ZStack { Color.gray; Button { Log.add("button") } label: { child() }.buttonStyle(.plain) }
    pc("H7 .plain Button child, parent .simultaneousGesture(Tap)",
       buttonInTappable.simultaneousGesture(TapGesture().onEnded { Log.add("p") }))
    pc("H8 .plain Button child, parent .highPriorityGesture(Tap)",
       buttonInTappable.highPriorityGesture(TapGesture().onEnded { Log.add("p") }))
    pc("H9 .plain Button child, parent onTap",
       buttonInTappable.onTapGesture { Log.add("p") })
    arm("H10 Button .simultaneousGesture(Tap) on the button itself", Button { Log.add("button") } label: {
        Color.blue }.buttonStyle(.plain).simultaneousGesture(TapGesture().onEnded { Log.add("sim") })) {
        click($0, at: centre)
    }
    arm("H11 Button .highPriorityGesture(Tap) on the button itself", Button { Log.add("button") } label: {
        Color.blue }.buttonStyle(.plain).highPriorityGesture(TapGesture().onEnded { Log.add("high") })) {
        click($0, at: centre)
    }
    arm("H12 Color .onTapGesture then .gesture(Tap) on one view", Color.blue.onTapGesture { Log.add("inner") }
        .gesture(TapGesture().onEnded { Log.add("outer") })) { click($0, at: centre) }
    arm("H13 Color .onTapGesture then .simultaneousGesture(Tap) on one view",
        Color.blue.onTapGesture { Log.add("inner") }
        .simultaneousGesture(TapGesture().onEnded { Log.add("outer") })) { click($0, at: centre) }
    arm("H14 Color .onTapGesture then .highPriorityGesture(Tap) on one view",
        Color.blue.onTapGesture { Log.add("inner") }
        .highPriorityGesture(TapGesture().onEnded { Log.add("outer") })) { click($0, at: centre) }
    let excl = Color.blue.gesture(TapGesture(count: 2).onEnded { Log.add("double") }
        .exclusively(before: TapGesture().onEnded { Log.add("single") }))
    arm("H15a Tap(2).exclusively(before: Tap), single", excl) { click($0, at: centre); spin(0.8) }
    arm("H15b Tap(2).exclusively(before: Tap), double", excl) { doubleClick($0, at: centre) }
    let simul = Color.blue.gesture(TapGesture().onEnded { Log.add("tap") }
        .simultaneously(with: LongPressGesture(minimumDuration: 0.3).onEnded { _ in Log.add("long") }))
    arm("H16a Tap.simultaneously(with: Long 0.3), quick click", simul) { click($0, at: centre) }
    arm("H16b Tap.simultaneously(with: Long 0.3), hold 0.6", simul) { w in
        mouse(w, .leftMouseDown, centre); spin(0.6); Log.add("|held"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("H17 disabled child drag, parent onTap: drag child",
        ZStack { Color.gray; child().gesture(DragGesture().onEnded { _ in Log.add("cDrag") }).disabled(true) }
        .onTapGesture { Log.add("p") }) { click($0, at: centre) }
    arm("H18 plain Color over a tappable (no gesture on top)",
        ZStack { Color.gray.onTapGesture { Log.add("under") }; child() }) { click($0, at: centre) }
}

// MARK: - B: buttons

struct LoggingStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, v in Log.add("pressed=\(v)") }
    }
}

@MainActor final class Holder: ObservableObject { @Published var disabled = false; @Published var name = "a" }

@MainActor func armB() {
    print("--- B: buttons")
    let logging = Button { Log.add("action") } label: { child() }.buttonStyle(LoggingStyle())
    let big = ZStack { Color.gray; logging }
    arm("B0 isPressed: down, spin, up", big) { w in
        mouse(w, .leftMouseDown, centre); spin(0.2); Log.add("|down"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("B1 isPressed: down, drag OUT, drag BACK, up inside", big) { w in
        mouse(w, .leftMouseDown, centre); spin(0.1); Log.add("|down")
        mouse(w, .leftMouseDragged, CGPoint(x: 190, y: 100)); spin(0.1); Log.add("|out")
        mouse(w, .leftMouseDragged, CGPoint(x: 101, y: 100)); spin(0.1); Log.add("|back")
        mouse(w, .leftMouseUp, CGPoint(x: 101, y: 100)); spin()
    }
    arm("B2 isPressed: down, drag OUT, up outside", big) { w in
        mouse(w, .leftMouseDown, centre); spin(0.1)
        mouse(w, .leftMouseDragged, CGPoint(x: 190, y: 100)); spin(0.1); Log.add("|out")
        mouse(w, .leftMouseUp, CGPoint(x: 190, y: 100)); spin()
    }
    arm("B3 isPressed: long hold 0.8s then up", big) { w in
        mouse(w, .leftMouseDown, centre); spin(0.8); Log.add("|held"); mouse(w, .leftMouseUp, centre); spin()
    }
    arm("B4a keyboardShortcut(.defaultAction), Return", Button("OK") { Log.add("ok") }
        .keyboardShortcut(.defaultAction)) { key($0, "\r", keyCode: 36) }
    arm("B4b keyboardShortcut(.cancelAction), Escape", Button("Cancel") { Log.add("cancel") }
        .keyboardShortcut(.cancelAction)) { key($0, "\u{1b}", keyCode: 53) }
    arm("B4c Button(role: .cancel) no shortcut, Escape", Button("Cancel", role: .cancel) { Log.add("cancel") }) {
        key($0, "\u{1b}", keyCode: 53)
    }
    arm("B4d Button(role: .destructive) no shortcut, Return", Button("Delete", role: .destructive) {
        Log.add("delete") }) { key($0, "\r", keyCode: 36) }
    arm("B4e keyboardShortcut(\"k\") (default .command), cmd-k", Button("K") { Log.add("k") }
        .keyboardShortcut("k")) { key($0, "k", modifiers: .command, keyCode: 40) }
    arm("B4f keyboardShortcut(\"k\") (default .command), plain k", Button("K") { Log.add("k") }
        .keyboardShortcut("k")) { key($0, "k", keyCode: 40) }
    arm("B4g keyboardShortcut(\"k\", modifiers: []), plain k", Button("K") { Log.add("k") }
        .keyboardShortcut("k", modifiers: [])) { key($0, "k", keyCode: 40) }
    arm("B4h two buttons, same cmd-k", VStack {
        Button("A") { Log.add("A") }.keyboardShortcut("k")
        Button("B") { Log.add("B") }.keyboardShortcut("k")
    }) { key($0, "k", modifiers: .command, keyCode: 40) }
    arm("B4i cmd-k on a .focusable() view's onKeyPress AND a button shortcut; view focused", VStack {
        FocusedKeyView(label: "view")
        Button("B") { Log.add("button") }.keyboardShortcut("k")
    }) { key($0, "k", modifiers: .command, keyCode: 40) }
    arm("B4j shortcut on a Button inside .hidden()? (opacity 0)", Button("K") { Log.add("k") }
        .keyboardShortcut("k").opacity(0)) { key($0, "k", modifiers: .command, keyCode: 40) }
    arm("B4k shortcut on a .plain onTapGesture-less Color? .keyboardShortcut on non-button view",
        Color.blue.onTapGesture { Log.add("tap") }.keyboardShortcut("k")) {
        key($0, "k", modifiers: .command, keyCode: 40)
    }
    arm("B4l keyboardShortcut(.defaultAction) disabled, Return", Button("OK") { Log.add("ok") }
        .keyboardShortcut(.defaultAction).disabled(true)) { key($0, "\r", keyCode: 36) }
    arm("B5 click on Button(role: .destructive) plain", Button(role: .destructive) { Log.add("d") } label: {
        Color.red }.buttonStyle(.plain)) { click($0, at: centre) }
}

struct FocusedKeyView: View {
    let label: String
    var hidden = false
    @FocusState var focused: Bool
    var body: some View {
        let base = Color.blue.frame(width: 50, height: 50).focusable().focused($focused)
            .onKeyPress { _ in Log.add(label); return .handled }
            .onChange(of: focused) { _, v in if hidden { Log.add("focused=\(v)") } }
        Group {
            if hidden { base.hidden() } else { base }
        }
        .onAppear { focused = true }
    }
}

// MARK: - PX: looks (pixels drawn offscreen)

@MainActor func armPX() {
    print("--- PX: looks (offscreen capture of the hosting view; 200x200)")
    func look<V: View>(_ label: String, _ v: V, rect: CGRect = CGRect(x: 60, y: 85, width: 80, height: 30)) {
        let w = makeWindow(ZStack { Color.white; v })
        spin(0.3)
        print("  \(label): \(sample(capture(w), rect: rect))")
        w.orderOut(nil)
    }
    look("PX0 control: solid red 80x30", Color(red: 1, green: 0, blue: 0).frame(width: 80, height: 30))
    look("PX1 Button(\"Delete\") enabled", Button("Delete") {})
    look("PX2 Button(\"Delete\") .disabled(true)", Button("Delete") {}.disabled(true))
    look("PX3 Button(\"Delete\", role: .destructive)", Button("Delete", role: .destructive) {})
    look("PX4 Button(\"Delete\", role: .cancel)", Button("Delete", role: .cancel) {})
    look("PX5 Button(\"Delete\") .borderedProminent", Button("Delete") {}.buttonStyle(.borderedProminent))
    look("PX6 Button(\"Delete\") .borderedProminent .disabled(true)",
         Button("Delete") {}.buttonStyle(.borderedProminent).disabled(true))
    look("PX7 Button(\"Delete\") .plain", Button("Delete") {}.buttonStyle(.plain))
    look("PX8 Button(\"Delete\") .plain .disabled(true)", Button("Delete") {}.buttonStyle(.plain).disabled(true))
    look("PX9 Button(\"Delete\") .borderless", Button("Delete") {}.buttonStyle(.borderless))
    look("PX10 Button(\"Delete\") .borderless .disabled(true)",
         Button("Delete") {}.buttonStyle(.borderless).disabled(true))
    look("PX11 Text(\"Delete\") plain", Text("Delete"))
    look("PX12 Text(\"Delete\") .disabled(true)", Text("Delete").disabled(true))
    look("PX13 Button(\"Delete\", role: .destructive) .borderedProminent",
         Button("Delete", role: .destructive) {}.buttonStyle(.borderedProminent))
    look("PX14 Button(\"Delete\", role: .destructive) .plain",
         Button("Delete", role: .destructive) {}.buttonStyle(.plain))
    look("PX15 Button(\"Delete\") env controlActiveState .key",
         Button("Delete") {}.environment(\.controlActiveState, .key))
    look("PX16 Button(\"Delete\") env controlActiveState .inactive",
         Button("Delete") {}.environment(\.controlActiveState, .inactive))
    look("PX17 .borderedProminent env controlActiveState .key",
         Button("Delete") {}.buttonStyle(.borderedProminent).environment(\.controlActiveState, .key))
    look("PX18 .borderedProminent env controlActiveState .inactive",
         Button("Delete") {}.buttonStyle(.borderedProminent).environment(\.controlActiveState, .inactive))
    look("PX19 Toggle env controlActiveState .key (on)", Toggle("Wi", isOn: .constant(true))
         .environment(\.controlActiveState, .key))
    look("PX20 Toggle env controlActiveState .inactive (on)", Toggle("Wi", isOn: .constant(true))
         .environment(\.controlActiveState, .inactive))
    // Pressed look: capture while the mouse is held down on the button.
    for (label, style) in [("PX21 bordered Button pressed", 0), ("PX22 borderedProminent pressed", 1)] {
        let v: AnyView = style == 0 ? AnyView(Button("Delete") {}) :
            AnyView(Button("Delete") {}.buttonStyle(.borderedProminent))
        let w = makeWindow(ZStack { Color.white; v })
        spin(0.3)
        let before = sample(capture(w), rect: CGRect(x: 60, y: 85, width: 80, height: 30))
        mouse(w, .leftMouseDown, centre); spin(0.3)
        let during = sample(capture(w), rect: CGRect(x: 60, y: 85, width: 80, height: 30))
        mouse(w, .leftMouseUp, centre); spin()
        print("  \(label): before \(before) | held \(during)")
        w.orderOut(nil)
    }
    print("  controlActiveState read in the window: \(ActiveReader.last)")
    let w = makeWindow(ActiveReader())
    spin(0.2)
    print("  PX23 controlActiveState of an unmodified window: \(ActiveReader.last)")
    w.orderOut(nil)
}

struct ActiveReader: View {
    nonisolated(unsafe) static var last = "-"
    @Environment(\.controlActiveState) var state
    var body: some View {
        Color.white.onAppear { ActiveReader.last = "\(state)" }.onChange(of: state) { _, s in ActiveReader.last = "\(s)" }
    }
}

// MARK: - F: focus

struct FocusRename: View {
    @ObservedObject var holder: Holder
    @FocusState var focused: Bool
    var body: some View {
        Color.blue.frame(width: 60, height: 60)
            .focusable().focused($focused)
            .onKeyPress { _ in Log.add("key(\(holder.name))"); return .handled }
            .id(holder.name)
            .onAppear { focused = true }
            .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct FocusIf: View {
    @ObservedObject var holder: Holder
    @FocusState var focused: Bool
    var body: some View {
        VStack {
            if holder.name == "a" {
                Color.blue.frame(width: 60, height: 60).focusable().focused($focused)
                    .onKeyPress { _ in Log.add("key"); return .handled }
            }
        }
        .frame(width: 200, height: 200)
        .onAppear { focused = true }
        .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

struct ClickToFocus: View {
    @FocusState var which: String?
    var body: some View {
        HStack(spacing: 0) {
            Color.blue.frame(width: 100, height: 200).focusable().focused($which, equals: "left")
            Color.green.frame(width: 100, height: 200).onTapGesture { Log.add("tapRight") }
        }
        .onChange(of: which) { _, v in Log.add("focus=\(v ?? "nil")") }
    }
}

struct ClickFocusThenPlain: View {
    @FocusState var which: String?
    var body: some View {
        HStack(spacing: 0) {
            Color.blue.frame(width: 100, height: 200).focusable().focused($which, equals: "left")
            Color.green.frame(width: 100, height: 200)
        }
        .onAppear { which = "left" }
        .onChange(of: which) { _, v in Log.add("focus=\(v ?? "nil")") }
    }
}

struct TabOrder: View {
    @FocusState var which: String?
    var body: some View {
        VStack {
            Color.blue.frame(width: 40, height: 40).focusable().focused($which, equals: "one")
            Button("Two") { }.focused($which, equals: "two")
            Color.green.frame(width: 40, height: 40).focusable().focused($which, equals: "three")
        }
        .onAppear { which = "one" }
        .onChange(of: which) { _, v in Log.add("focus=\(v ?? "nil")") }
    }
}

struct FocusRing: View {
    @FocusState var focused: Bool
    let focus: Bool
    var body: some View {
        Color.white.frame(width: 80, height: 30).focusable().focused($focused)
            .onAppear { focused = focus }
    }
}

@MainActor func armF() {
    print("--- F: focus")
    print("  NSApp.isFullKeyboardAccessEnabled = \(NSApp.isFullKeyboardAccessEnabled)")
    arm("K0 focusable view focused in onAppear, key x (control)", FocusedKeyView(label: "key")) {
        key($0, "x", keyCode: 7)
    }
    let rename = Holder()
    arm("F1 focused .id(\"a\") renamed to \"b\", then key, then back to \"a\", then key", FocusRename(holder: rename)) { w in
        Log.add("|start"); rename.name = "b"; spin(0.3); Log.add("|renamed"); key(w, "x", keyCode: 7)
        rename.name = "a"; spin(0.3); Log.add("|back"); key(w, "x", keyCode: 7)
    }
    let gone = Holder()
    arm("F2 focused view removed by an if, key, returned, key", FocusIf(holder: gone)) { w in
        Log.add("|start"); gone.name = "b"; spin(0.3); Log.add("|removed"); key(w, "x", keyCode: 7)
        gone.name = "a"; spin(0.3); Log.add("|returned"); key(w, "x", keyCode: 7)
    }
    arm("F3 click a .focusable() view (left), then click a tappable (right)", ClickToFocus()) { w in
        click(w, at: CGPoint(x: 50, y: 100)); Log.add("|clickedLeft"); click(w, at: CGPoint(x: 150, y: 100))
    }
    arm("F4 left focused; click a plain gesture-less view (right)", ClickFocusThenPlain()) { w in
        Log.add("|start"); click(w, at: CGPoint(x: 150, y: 100))
    }
    arm("F5 Tab from one (.focusable) past Button two to three", TabOrder()) { w in
        Log.add("|start"); key(w, "\t", keyCode: 48); key(w, "\t", keyCode: 48)
    }
    arm("F9 .focusable().hidden() focused in onAppear, key x", FocusedKeyView(label: "key", hidden: true)) {
        key($0, "x", keyCode: 7)
    }
    arm("F6 click a Button: does it take focus?", ButtonFocus()) { w in
        Log.add("|start"); click(w, at: centre)
    }
    for (label, f) in [("F7 .focusable() white 80x30 unfocused", false), ("F8 same, focused (ring?)", true)] {
        let w = makeWindow(ZStack { Color.gray; FocusRing(focus: f) })
        spin(0.4)
        print("  \(label): \(sample(capture(w), rect: CGRect(x: 52, y: 80, width: 96, height: 40)))")
        w.orderOut(nil)
    }
}

struct ButtonFocus: View {
    @FocusState var focused: Bool
    var body: some View {
        Button("Go") { Log.add("action") }.focused($focused)
            .onChange(of: focused) { _, v in Log.add("focused=\(v)") }
    }
}

// MARK: - C: content shapes

@MainActor func armC() {
    print("--- C: content shapes (a 200x200 view; clicks at centre and at corner (12,12))")
    func cc<V: View>(_ label: String, _ v: V) {
        arm("\(label) centre", v) { click($0, at: centre) }
        arm("\(label) corner", v) { click($0, at: corner) }
    }
    cc("C0 Color.onTapGesture (control)", Color.blue.onTapGesture { Log.add("hit") })
    cc("C1 Color.contentShape(Circle()).onTapGesture", Color.blue.contentShape(Circle()).onTapGesture { Log.add("hit") })
    cc("C2 Color.onTapGesture.contentShape(Circle()) (shape AFTER the gesture)",
       Color.blue.onTapGesture { Log.add("hit") }.contentShape(Circle()))
    cc("C3 Color.clipShape(Circle()).onTapGesture", Color.blue.clipShape(Circle()).onTapGesture { Log.add("hit") })
    cc("C4 Color.onTapGesture.clipShape(Circle())", Color.blue.onTapGesture { Log.add("hit") }.clipShape(Circle()))
    cc("C5 Circle().fill.onTapGesture", Circle().fill(.blue).onTapGesture { Log.add("hit") })
    cc("C6 RoundedRectangle(60).fill.onTapGesture",
       RoundedRectangle(cornerRadius: 60).fill(.blue).onTapGesture { Log.add("hit") })
    cc("C7 Circle().stroke(lineWidth: 10).onTapGesture", Circle().stroke(.blue, lineWidth: 10)
        .onTapGesture { Log.add("hit") })
    arm("C7b the same, click ON the stroke (100,5)", Circle().stroke(.blue, lineWidth: 10)
        .onTapGesture { Log.add("hit") }) { click($0, at: CGPoint(x: 100, y: 3)) }
    cc("C8 Color.clipped() (rect) .onTapGesture", Color.blue.clipped().onTapGesture { Log.add("hit") })
    cc("C9 Color.cornerRadius(60).onTapGesture", Color.blue.cornerRadius(60).onTapGesture { Log.add("hit") })
    cc("C10 Color.contentShape(Circle()) under .plain Button",
       Button { Log.add("hit") } label: { Color.blue }.buttonStyle(.plain).contentShape(Circle()))
    cc("C11 Color.contentShape(RoundedRectangle(60)).onTapGesture",
       Color.blue.contentShape(RoundedRectangle(cornerRadius: 60)).onTapGesture { Log.add("hit") })
    cc("C12 Circle over tappable Color (Circle no gesture)",
       ZStack { Color.gray.onTapGesture { Log.add("under") }; Circle().fill(.blue) })
    cc("C13 Color.contentShape(Circle()).onHover-less .onTapGesture inside .padding(0)",
       Color.blue.contentShape(Circle()).padding(0).onTapGesture { Log.add("hit") })
}

@MainActor func run() {
    armG(); armH(); armB(); armPX(); armF(); armC()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    run()
}
exit(0)
