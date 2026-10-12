import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPlatform
import MetalUIDemoContent
@testable import MetalUI

// Overlays and coordinates (C15), lane B — the MetalUI-only `anchoredOverlay`:
// tests B6–B24 (rulings `OV-A`, `OV-K`, `OV-N`, `OV-S`; spec
// `docs/superpowers/specs/2026-10-10-overlays-coords-design.md` §4.2). B1–B5
// (`.popover`'s `attachmentAnchor:`) are in `PopoverTests.swift`. SwiftUI has
// no chrome-less point-anchored popover (probe arms A0–A7, B0–B2), so the
// semantics are gpui's `anchored()` with `on_mouse_down_out`, ruled in `OV-A`.
//
// Everything runs through a real `Window` on a 400 × 400 `FakePlatformWindow`
// — nothing sleeps. Red before, for every test: the file does not compile at
// `ebcf3c7` (no `anchoredOverlay`); against the lane-B stub (the overlay a
// chromed popover above its declarer, the point and space ignored) each
// failure line is recorded in the red commit.

// MARK: - Fixtures

@MainActor
private final class OLog {
    var shown = true
    var item: OItem?
    var point = Point(x: Pixels(120), y: Pixels(80))
    var text = ""
    var level = 0.5
    var entries: [String] = []
}

private struct OItem: Identifiable { let id: Int }

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private func ldown(_ x: Float, _ y: Float) -> InputEvent { .mouseDown(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float) -> InputEvent { .mouseUp(MouseEvent(position: pt(x, y))) }
private func key(_ c: String, _ mods: Modifiers = []) -> InputEvent {
    .keyDown(KeyEvent(charactersIgnoringModifiers: c, characters: c, modifiers: mods, timestamp: 0))
}

/// A press and its release of button `button` (0 primary, 1 secondary, 2 other).
private func press(_ button: Int, _ x: Float, _ y: Float) -> (InputEvent, InputEvent) {
    let at = MouseEvent(position: pt(x, y), buttonNumber: button)
    switch button {
    case 0: return (.mouseDown(at), .mouseUp(at))
    case 1: return (.rightMouseDown(at), .rightMouseUp(at))
    default: return (.otherMouseDown(at), .otherMouseUp(at))
    }
}

@MainActor private func shownBinding(_ log: OLog) -> Binding<Bool> {
    Binding(get: { log.shown }, set: { log.shown = $0; log.entries.append("shown=\($0)") })
}

@MainActor private func itemBinding(_ log: OLog) -> Binding<OItem?> {
    Binding(get: { log.item }, set: { log.item = $0; log.entries.append("item=\($0.map { "\($0.id)" } ?? "nil")") })
}

@MainActor private func textBinding(_ log: OLog) -> Binding<String> {
    Binding(get: { log.text }, set: { log.text = $0 })
}

/// A `width` × `height` overlay content (default 100 × 50) — no chrome, so the
/// overlay's box.
@MainActor private func content(_ width: Float = 100, _ height: Float = 50) -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(width), height: px(height))
}

/// The 400 × 400 canvas filling the window, declaring an overlay of
/// `content()` at `log.point` in `space` with `anchor`.
@MainActor private func canvas(_ log: OLog, in space: CoordinateSpace = .local, anchor: UnitPoint = .topLeading,
                               width: Float = 100, height: Float = 50) -> some Element {
    Box().frame(width: px(400), height: px(400))
        .anchoredOverlay(isPresented: shownBinding(log), at: log.point, in: space, anchor: anchor) {
            content(width, height)
        }
}

/// `anchor` (`width` × `height`) with its top-left corner at (`left`, `top`) in
/// a 400 × 400 root (legacy `Column`/`Row` have no gap).
@MainActor private func at<A: ElementGroup>(top: Float, left: Float, width: Float = 40, height: Float = 20,
                                            _ anchor: A) -> some Element {
    Column {
        Box().frame(width: px(1), height: px(top))
        Row {
            Box().frame(width: px(left), height: px(1))
            anchor
            Box().frame(width: px(400 - left - width), height: px(1))
        }
        Box().frame(width: px(1), height: px(400 - top - height))
    }
}

/// A `size` square window over `content`, drawn until clean. The window is
/// held only weakly by its platform window: every test keeps it to its end.
@MainActor
private func overlayWindow<Root: Element>(size: Int = 400, settle: Bool = true,
                                          _ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    if settle { drawUntilClean(window) }
    return (window, platform)
}

@MainActor private func drawUntilClean(_ window: Window) {
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    drawUntilClean(window)
}

/// The topmost open overlay's box, required.
@MainActor private func overlay(_ window: Window, sourceLocation: SourceLocation = #_sourceLocation) throws
    -> Bounds<Pixels> {
    try #require(window.lastOpenPopovers.last, "an overlay is open", sourceLocation: sourceLocation).bounds
}

private func xywh(_ b: Bounds<Pixels>) -> [Float] {
    [b.origin.x.value, b.origin.y.value, b.size.width.value, b.size.height.value]
}

private func centre(_ b: Bounds<Pixels>) -> (Float, Float) {
    (b.origin.x.value + b.size.width.value / 2, b.origin.y.value + b.size.height.value / 2)
}

// MARK: - B6–B9: placement (`OV-A` item 2)

/// **B6** (`OV-A` item 2; gpui `Anchor::TopLeft`). An overlay puts its
/// top-leading corner at the point: (120, 80) in the canvas's space, which
/// fills the window from (0, 0). Red on the stub: a chromed popover above the
/// canvas's centre. Mutation: the origin centred on the point (70, 55).
@MainActor
@Test func anOverlayPutsItsTopLeadingCornerAtThePoint() throws {
    let log = OLog()
    let (window, _) = try overlayWindow { canvas(log) }
    #expect(xywh(try overlay(window)) == [120, 80, 100, 50])
    withExtendedLifetime(window) {}
}

/// The point and the overlay's expected origin for B7's arms.
private let flipArms: [([Float], [Float])] = [([350, 80], [250, 80]), ([120, 380], [120, 330]),
                                              ([350, 380], [250, 330])]

/// **B7** (`OV-A` item 2; gpui `SwitchAnchor`). An overlay that would leave
/// the window flips per axis — the mirrored unit point at the same point — and
/// only on the axis that overflows: at the right edge (350, 80) it goes left
/// of the point, at the bottom (120, 380) above it, at both (350, 380) both.
/// Red on the stub. Mutations: flip both axes when either overflows (the right
/// arm reads (250, 30)); no flip, clamp only (the right arm reads (300, 80)).
@MainActor
@Test(arguments: flipArms)
func anOverlayFlipsPerAxisAtTheRightAndBottomEdges(point: [Float], origin: [Float]) throws {
    let log = OLog()
    log.point = pt(point[0], point[1])
    let (window, _) = try overlayWindow { canvas(log) }
    #expect(xywh(try overlay(window)) == origin + [100, 50], "\(point)")
    withExtendedLifetime(window) {}
}

/// **B8** (`OV-A` item 2). An overlay that fits neither way on an axis keeps
/// its own anchor and is clamped inside the window with no margin: a 300-wide
/// content at x 200 would end at 500, mirrored start at −100, so it is clamped
/// to 100. Red on the stub. Mutation: the clamp dropped (reads 200).
@MainActor
@Test func anOverlayThatFitsNeitherWayIsClampedInsideTheWindow() throws {
    let log = OLog()
    log.point = pt(200, 80)
    let (window, _) = try overlayWindow { canvas(log, width: 300) }
    #expect(xywh(try overlay(window)) == [100, 80, 300, 50])
    withExtendedLifetime(window) {}
}

/// **B9** (`OV-A` item 2). The `anchor` unit point of the content goes at the
/// point: `.bottomTrailing` at (200, 200) puts the content at (100, 150),
/// `.center` at (150, 175). Red on the stub. Mutation: the anchor ignored
/// (both read (200, 200)).
@MainActor
@Test func anOverlayHonoursItsAnchorUnitPoint() throws {
    let log = OLog()
    log.point = pt(200, 200)
    let (trailing, _) = try overlayWindow { canvas(log, anchor: .bottomTrailing) }
    let (centred, _) = try overlayWindow { canvas(log, anchor: .center) }
    #expect(xywh(try overlay(trailing)) == [100, 150, 100, 50], ".bottomTrailing")
    #expect(xywh(try overlay(centred)) == [150, 175, 100, 50], ".center")
    withExtendedLifetime((trailing, centred)) {}
}

// MARK: - B10: no chrome (`OV-A` item 1)

/// **B10** (`OV-A` item 1; probe B1: SwiftUI's `.presentationBackground(.clear)`
/// keeps the frame). An overlay draws no chrome and no padding: on its layer
/// the only rect is its content's own accent background, at the point, and
/// there is no shadow image. Red on the stub (a panel rect and its shadow).
/// Mutation: `chrome: true` for overlays.
@MainActor
@Test func anOverlayDrawsNoChromeAndNoPadding() throws {
    let log = OLog()
    let (window, _) = try overlayWindow {
        Box().frame(width: px(400), height: px(400))
            .anchoredOverlay(isPresented: shownBinding(log), at: log.point) { content().background(.accent) }
    }
    let scene = window.lastScene
    let layer = try #require(scene.highestLayer)
    try #require(layer > 0, "the overlay is on a higher layer")
    let rects = scene.rects.indices.filter { scene.layer(of: .rect, at: $0) == layer }.map { scene.rects[$0] }
    let images = scene.images.indices.filter { scene.layer(of: .image, at: $0) == layer }
    try #require(rects.count == 1, "one rect, the content's: \(rects.count)")
    let rect = rects[0]
    #expect([rect.bounds.origin.x, rect.bounds.origin.y, rect.bounds.size.width, rect.bounds.size.height]
            == [120, 80, 100, 50], "the content at the point: no padding")
    let accent = window.theme[.accent]
    #expect(rect.background.h == accent.h && rect.background.l == accent.l, "the content's own fill, not .surface")
    #expect(images.isEmpty, "no shadow: \(images.count)")
    withExtendedLifetime(window) {}
}

// MARK: - B11–B16: dismissal and interaction (`OV-A` items 3–5)

/// **B11** (`OV-A` item 3; gpui `on_mouse_down_out`). A press of every button
/// outside the overlay — here on the canvas, its declarer — writes its binding
/// `false` from input. Red on the stub for none (an outside press dismissed a
/// popover already): a pin of the shared stage. Mutation: the secondary and
/// other arms skip overlays.
@MainActor
@Test(arguments: [0, 1, 2])
func anOutsidePressOfEveryButtonDismissesAnOverlay(button: Int) throws {
    let log = OLog()
    let (window, platform) = try overlayWindow { canvas(log) }
    _ = try overlay(window)
    let (down, up) = press(button, 20, 300)
    platform.simulateInput(down)
    #expect(log.entries == ["shown=false"], "button \(button): dismissed at the press")
    platform.simulateInput(up)
    redraw(window)
    #expect(window.lastOpenPopovers.isEmpty)
    withExtendedLifetime(window) {}
}

/// B12's fixture: a field, a slider and a context-menu card above a 400 × 200
/// box declaring an overlay at the window's (300, 300).
@MainActor private func sideControls(_ log: OLog) -> some Element {
    Column {
        TextField("F", text: textBinding(log)).frame(width: px(200))
        Slider(value: Binding(get: { log.level }, set: { log.level = $0 }), in: 0...1).frame(width: px(200))
        Box().frame(width: px(200), height: px(40)).contextMenu { Button("C") { log.entries.append("menu") } }
        Box().frame(width: px(400), height: px(200))
            .anchoredOverlay(isPresented: shownBinding(log), at: pt(300, 300), in: .global) { content() }
    }
}

/// **B12** (EP-b; `OV-A` evidence 4). A press into a field, a slider or a
/// context menu — each a stage that claims its press — dismisses the overlay
/// **and** still lands: the field focuses, the slider writes, the menu opens.
/// MetalCreator's stopgap missed these presses because it read
/// `Window.onInput`. Red on the stub for none (a pin of the stage order).
/// Mutation: the popover stage moved after `dispatchTextInput` (the field arm).
@MainActor
@Test(arguments: ["field", "slider", "menu"])
func aPressIntoAFieldASliderOrAContextMenuDismissesAndStillLands(target: String) throws {
    let log = OLog()
    let (window, platform) = try overlayWindow { sideControls(log) }
    try #require(xywh(try overlay(window)) == [300, 300, 100, 50])
    switch target {
    case "field":
        let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field")
        let (x, y) = centre(field.bounds)
        platform.simulateInput(ldown(x, y))
        platform.simulateInput(lup(x, y))
        #expect(log.entries == ["shown=false"])
        #expect(window.focusedElement == field.id, "the press focused the field")
    case "slider":
        let slider = try #require(window.lastHitboxes.first { $0.handlers.valueTrack != nil }, "the slider")
        let x = slider.bounds.origin.x.value + slider.bounds.size.width.value * 0.95
        let (_, y) = centre(slider.bounds)
        platform.simulateInput(ldown(x, y))
        platform.simulateInput(lup(x, y))
        #expect(log.entries == ["shown=false"])
        #expect(log.level > 0.8, "the press wrote the slider: \(log.level)")
    default:
        let card = try #require(window.lastHitboxes.first { $0.handlers.contextual != nil }, "the card")
        let (x, y) = centre(card.bounds)
        let (down, up) = press(1, x, y)
        platform.simulateInput(down)
        platform.simulateInput(up)
        #expect(log.entries == ["shown=false"])
        #expect(platform.presentedMenus.count == 1, "the press opened the context menu")
    }
    withExtendedLifetime(window) {}
}

/// **B13** (`OV-A` item 3). A press on the overlay's declarer dismisses it
/// **and passes on** — unlike `.popover`'s anchor (`MN-Y` item 2): the canvas
/// under a pointer-placed palette hears the click. Red on the stub (the
/// popover consumes its anchor's press). Mutation: `consumesAnchorPress` true
/// for overlays.
@MainActor
@Test func aPressOnTheDeclarerDismissesTheOverlayAndPassesOn() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow {
        Box().frame(width: px(400), height: px(400)).onClick { log.entries.append("canvas") }
            .anchoredOverlay(isPresented: shownBinding(log), at: log.point) { content() }
    }
    _ = try overlay(window)
    platform.simulateInput(ldown(20, 300))
    platform.simulateInput(lup(20, 300))
    #expect(log.entries == ["shown=false", "canvas"], "dismissed, then the canvas clicked")
    withExtendedLifetime(window) {}
}

/// An overlay at (120, 80) holding a 100-wide field whose `onKeyPress(.escape)`
/// would claim Escape.
@MainActor private func fieldOverlay(_ log: OLog) -> some Element {
    Box().frame(width: px(400), height: px(400))
        .anchoredOverlay(isPresented: shownBinding(log), at: log.point, in: .global) {
            TextField("In", text: textBinding(log))
                .onKeyPress(.escape) {
                    log.entries.append("field escape")
                    return .handled
                }
                .frame(width: px(100))
        }
}

/// **B14** (`OV-A` item 5). Escape dismisses the topmost overlay even while a
/// field inside it is focused and would claim Escape itself (`onKeyPress`):
/// the popover stage runs before every key stage. Focus then leaves with the
/// field's identity (`IX-I`). Red on the stub for none (a pin). Mutation: the
/// Escape arm after the key stages (the field's handler claims it).
@MainActor
@Test func escapeDismissesTheTopmostOverlayEvenWithAFieldInsideFocused() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow { fieldOverlay(log) }
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field")
    let (x, y) = centre(field.bounds)
    platform.simulateInput(ldown(x, y))
    platform.simulateInput(lup(x, y))
    try #require(window.focusedElement == field.id, "a click focused the field")
    platform.simulateInput(key("\u{1b}"))
    #expect(log.entries == ["shown=false"], "the overlay took Escape: \(log.entries)")
    redraw(window)
    #expect(window.lastOpenPopovers.isEmpty)
    #expect(window.focusedElement == nil, "focus left with the field")
    withExtendedLifetime(window) {}
}

/// **B15** (`MN-Z`, `OV-A` item 4). A press or a wheel on the overlay never
/// reaches beneath, though its content registers nothing: the raw opaque
/// hitbox at the overlay's box. Control: the same wheel outside reaches the
/// canvas. Mutation: the raw opaque hitbox skipped when `chrome == false`.
@MainActor
@Test func aPressOrWheelOnTheOverlayNeverReachesBeneath() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow {
        Box().frame(width: px(400), height: px(400)).onClick { log.entries.append("canvas") }
            .onScrollWheel { _ in log.entries.append("wheel"); return true }
            .anchoredOverlay(isPresented: shownBinding(log), at: log.point) { content() }
    }
    #expect(xywh(try overlay(window)) == [120, 80, 100, 50])
    platform.simulateInput(ldown(170, 105))
    platform.simulateInput(lup(170, 105))
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(170, 105), delta: pt(0, 10))))
    #expect(log.entries == [], "nothing beneath ran: \(log.entries)")
    #expect(log.shown, "a press inside does not dismiss")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(20, 300), delta: pt(0, 10))))
    #expect(log.entries == ["wheel"], "control: outside, the wheel reaches the canvas")
    withExtendedLifetime(window) {}
}

/// **B16** (`OV-A` item 5). Keys reach a focused field inside the overlay:
/// typed text and the delete key edit it. Red on the stub for none (a pin).
/// Mutation: the popover stage claims every key while one is open.
@MainActor
@Test func keysReachAFocusedTextFieldInsideTheOverlay() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow { fieldOverlay(log) }
    let field = try #require(window.lastHitboxes.first { $0.handlers.textInput != nil }, "the field")
    let (x, y) = centre(field.bounds)
    platform.simulateInput(ldown(x, y))
    platform.simulateInput(lup(x, y))
    platform.simulateInput(.textInput("qr"))
    window.drawFrameIfNeeded()
    platform.simulateInput(key("\u{7f}"))
    #expect(log.text == "q", "typed and deleted: \(log.text)")
    #expect(log.shown, "still open")
    withExtendedLifetime(window) {}
}

// MARK: - B17–B19: the point at layout (`OV-K`, `OV-N`)

/// **B17** (`OV-K`). A point written with the binding is drawn there in the
/// frame presenting the write — not one frame later — and a point moved while
/// open moves the overlay in the frame presenting the move. Red on the stub.
/// Mutation: the point taken from the last frame.
@MainActor
@Test func anOverlayAtAPointWrittenWithItsBindingAppearsThereInTheFirstFrame() throws {
    let log = OLog()
    log.shown = false
    let (window, _) = try overlayWindow { canvas(log) }
    try #require(window.lastOpenPopovers.isEmpty)
    log.point = pt(250, 100)
    log.shown = true
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(xywh(try overlay(window)) == [250, 100, 100, 50], "there in the first frame")
    log.point = pt(50, 60)
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
    #expect(xywh(try overlay(window)) == [50, 60, 100, 50], "moved in the frame presenting the move")
    withExtendedLifetime(window) {}
}

/// **B18** (`OV-K`, `OV-N`). The point's space: `.global` is the window's
/// (10, 20) itself, though the declarer sits at (180, 190); `.named("canvas")`
/// is relative to the space's origin (50, 100) — (60, 120); `.local` on a
/// declarer under a `.scaleEffect(2)` is its own space, effect included: the
/// 100 × 100 rectangle centred at (150, 150) scaled about (200, 200) maps its
/// (10, 10) to (120, 120). Red on the stub. Mutations: `.named` placed as
/// `.global` (reads (10, 20)); `.local` as the bounds' origin plus the point
/// (reads (160, 160)).
@MainActor
@Test func anOverlayInGlobalAndNamedSpaces() throws {
    let log = OLog()
    log.point = pt(10, 20)
    let (global, _) = try overlayWindow {
        at(top: 190, left: 180, Box().frame(width: px(40), height: px(20))
            .anchoredOverlay(isPresented: shownBinding(log), at: log.point, in: .global) { content() })
    }
    let (named, _) = try overlayWindow {
        at(top: 100, left: 50, width: 200, height: 200, Box().frame(width: px(200), height: px(200))
            .anchoredOverlay(isPresented: shownBinding(log), at: log.point, in: .named("canvas")) { content() }
            .coordinateSpace(.named("canvas")))
    }
    let (local, _) = try overlayWindow {
        HStack {
            Rectangle().frame(width: px(100), height: px(100))
                .anchoredOverlay(isPresented: shownBinding(log), at: pt(10, 10)) { content() }
                .scaleEffect(2)
        }
    }
    #expect(xywh(try overlay(global)) == [10, 20, 100, 50], ".global")
    #expect(xywh(try overlay(named)) == [60, 120, 100, 50], ".named")
    let scaled = try overlay(local)
    #expect(abs(scaled.origin.x.value - 120) < 0.01 && abs(scaled.origin.y.value - 120) < 0.01,
            ".local under the scale: \(xywh(scaled))")
    #expect(scaled.size == Size(width: px(100), height: px(50)), "the overlay itself is not scaled")
    withExtendedLifetime((global, named, local)) {}
}

/// **B19** (`OV-K`). A window resize re-places the overlay, re-flipped, in the
/// frame presenting it: (250, 100) fits a 400 window and flips left of the
/// point in a 300 one. Red on the stub. Mutation: the placement cached across
/// frames.
@MainActor
@Test func anOverlayIsReplacedOnAWindowResize() throws {
    let log = OLog()
    log.point = pt(250, 100)
    let (window, platform) = try overlayWindow { canvas(log, in: .global) }
    #expect(xywh(try overlay(window)) == [250, 100, 100, 50])
    platform.simulateResize(to: Size(width: px(300), height: px(300)))
    drawUntilClean(window)
    #expect(xywh(try overlay(window)) == [150, 100, 100, 50], "re-flipped in the smaller window")
    withExtendedLifetime(window) {}
}

// MARK: - B20–B23: identity, state, accessibility, both vocabularies

/// **B20** (`MN-L` item 2). `anchoredOverlay` adds one identity level, for its
/// caller only: the declarer at cursor 0 under the wrapper, its siblings
/// unmoved, the overlay's content under cursor 1. Red on the stub for none
/// (the stub is `.popover`'s wrapper): a pin. Mutation: the slot at cursor 0.
@MainActor
@Test func anOverlayAddsOneIdentityLevelOnlyForItsCaller() throws {
    let log = OLog()
    let (plain, _) = try overlayWindow {
        Column {
            Button("A") { log.entries.append("A") }
            Button("B") { log.entries.append("B") }
            Button("C") { log.entries.append("C") }
        }
    }
    let (wrapped, _) = try overlayWindow {
        Column {
            Button("A") { log.entries.append("A") }
            Button("B") { log.entries.append("B") }
                .anchoredOverlay(isPresented: shownBinding(log), at: pt(300, 300), in: .global) {
                    Button("In") { log.entries.append("In") }
                }
            Button("C") { log.entries.append("C") }
        }
    }
    try #require(!wrapped.lastOpenPopovers.isEmpty, "presented")
    let before = wrapped.lastHitboxes.filter { $0.opaque && $0.handlers.onClick != nil }.map(\.id)
    let after = plain.lastHitboxes.filter { $0.opaque && $0.handlers.onClick != nil }.map(\.id)
    try #require(before.count == 4 && after.count == 3, "A, B, C (and In): \(before.count), \(after.count)")
    let a = after[0], b = after[1], c = after[2]
    #expect(before.contains(a) && before.contains(c), "the siblings' ids are unmoved")
    #expect(before.contains(GlobalElementID.child(of: b, at: 0, name: nil)), "the declarer at 0 under the wrapper")
    let slot = GlobalElementID.child(of: b, at: 1, name: nil)
    let inner = try #require(before.first { ![a, c, GlobalElementID.child(of: b, at: 0, name: nil)].contains($0) })
    var cursor: GlobalElementID? = inner
    var underSlot = false
    while let id = cursor { if id == slot { underSlot = true }; cursor = id.parent }
    #expect(underSlot, "the overlay's content descends from the slot at cursor 1: \(inner)")
    withExtendedLifetime((plain, wrapped)) {}
}

/// **B21** (`MN-O`, `MN-M` item 2). An overlay writes no `StateTable` entry of
/// its own — every entry presenting adds descends from its slot, and
/// dismissing returns the table to its count — and, while a client is active,
/// publishes the `.popover` node holding its content, isolating nothing. Red
/// on the stub for none: a pin. Mutation: `popoverHint` dropped for overlays.
@MainActor
@Test func anOverlayWritesNoStateTableEntryAndPublishesAPopoverNode() throws {
    let log = OLog()
    log.shown = false
    let (window, platform) = try overlayWindow {
        Column {
            Button("Under") { log.entries.append("under") }
            Box().frame(width: px(400), height: px(200))
                .anchoredOverlay(isPresented: shownBinding(log), at: pt(150, 300), in: .global) {
                    Button("In") { log.entries.append("in") }
                }
        }
    }
    let dismissed = window.stateTable.count
    let before = window.stateTable.ids
    log.shown = true
    redraw(window)
    let wrapper = try #require(window.lastOpenPopovers.first, "presented").id
    let slot = GlobalElementID.child(of: wrapper, at: 1, name: nil)
    func descends(_ id: GlobalElementID, from ancestor: GlobalElementID) -> Bool {
        var cursor: GlobalElementID? = id
        while let current = cursor { if current == ancestor { return true }; cursor = current.parent }
        return false
    }
    let added = window.stateTable.ids.subtracting(before)
    try #require(!added.isEmpty, "the overlay's box and content write their element slots")
    #expect(added.allSatisfy { descends($0, from: slot) }, "every added entry is inside the overlay's slot")

    platform.simulateAccessibilityRequest(.activate)
    redraw(window)
    let tree = try #require(platform.publishedAccessibilityTrees.last)
    let popovers = tree.nodes.filter { $0.value.role == .popover }
    try #require(popovers.count == 1, "one popover node: \(tree.nodes.values.map(\.role))")
    #expect(tree.nodes.values.contains { $0.label == "Under" && $0.role == .button }, "nothing isolated")
    #expect(popovers.values.first.map { !$0.children.isEmpty } == true, "it holds its content")

    log.shown = false
    redraw(window)
    #expect(window.stateTable.count == dismissed, "dismissed again: the overlay's entries are gone")
    withExtendedLifetime(window) {}
}

/// **B22** (`MN-L` item 2, `OV-S`). The proposal path presents, places and
/// dismisses through its own entry: a fixed 40 × 20 `ProposalText` centred at
/// (180, 190) by its `HStack` root, an overlay at its local (5, 5) — window
/// (185, 195), top-leading — shown once the declarer has been laid out (the
/// first frame has no space yet and asks for another); an outside press
/// dismisses. Red on the stub. Mutation: the proposal overload forwards
/// `.topLeading` as `.center` (reads (135, 170)).
@MainActor
@Test func aProposalPathOverlayPresentsPlacesAndDismisses() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow(settle: false) {
        HStack {
            ProposalText("a").frame(width: px(40), height: px(20))
                .anchoredOverlay(isPresented: shownBinding(log), at: pt(5, 5)) { content() }
        }
    }
    #expect(window.lastOpenPopovers.isEmpty, "frame 0: no space yet")
    try #require(window.needsRedraw, "frame 0 asked for another")
    window.drawFrameIfNeeded()
    #expect(xywh(try overlay(window)) == [185, 195, 100, 50], "frame 1: at the local point")
    platform.simulateInput(ldown(20, 20))
    #expect(log.entries == ["shown=false"], "an outside press dismisses, from input")
    platform.simulateInput(lup(20, 20))
    redraw(window)
    #expect(window.lastOpenPopovers.isEmpty)
    withExtendedLifetime(window) {}
}

/// A 100 × 50 button counting its presses in `@State`, logging each count.
private struct OCounter: Component {
    @State var n = 0
    let log: OLog

    var content: some ElementGroup {
        Button("Count") { n += 1; log.entries.append("n=\(n)") }.frame(width: Pixels(100), height: Pixels(50))
    }
}

/// **B23** (`ID-R`). `anchoredOverlay(item:)`: `nil` presents nothing; item 1
/// presents at its point, its counter counting; item 2 starts fresh; an outside
/// press writes `nil`. Red on the stub (placement). Mutation: the item's name
/// not applied.
@MainActor
@Test func anOverlayItemFollowsTheItemAndResetsOnANewID() throws {
    let log = OLog()
    let (window, platform) = try overlayWindow {
        Box().frame(width: px(400), height: px(400))
            .anchoredOverlay(item: itemBinding(log), at: pt(150, 150), in: .global) { _ in OCounter(log: log) }
    }
    #expect(window.lastOpenPopovers.isEmpty, "nil: nothing")
    log.item = OItem(id: 1)
    redraw(window)
    #expect(xywh(try overlay(window)) == [150, 150, 100, 50], "item 1 presents at its point")
    for _ in 0..<2 {
        platform.simulateInput(ldown(200, 175))
        platform.simulateInput(lup(200, 175))
        redraw(window)
    }
    log.item = OItem(id: 2)
    redraw(window)
    platform.simulateInput(ldown(200, 175))
    platform.simulateInput(lup(200, 175))
    #expect(log.entries == ["n=1", "n=2", "n=1"], "item 2's content starts fresh")
    platform.simulateInput(ldown(20, 20))
    #expect(log.entries.last == "item=nil", "an outside press writes nil")
    withExtendedLifetime(window) {}
}

// MARK: - B24: the demo

/// **B24** (spec §3.2). Headless, through a real `Window` on the overlays
/// demo: a click on the canvas at its (100, 60) opens the palette with its
/// top-leading corner there (the readout's named frame agrees);
/// a press on the side field closes it and
/// focuses that field.
@MainActor
@Test func overlaysDemoOpensThePaletteAtThePointerAndClosesOnAnOutsidePress() throws {
    overlaysDemoModel.reset()
    defer { overlaysDemoModel.reset() }
    let (window, platform) = try overlayWindow(size: 1000) { overlaysDemoContent() }
    let canvas = try #require(window.lastHitboxes.first {
        $0.opaque && $0.bounds.size == Size(width: px(520), height: px(380))
    }, "the canvas")
    let x = canvas.bounds.origin.x.value + 100, y = canvas.bounds.origin.y.value + 60
    platform.simulateInput(ldown(x, y))
    platform.simulateInput(lup(x, y))
    redraw(window)
    #expect(overlaysDemoModel.paletteShown, "the click opened the palette")
    let palette = try overlay(window)
    #expect([palette.origin.x.value, palette.origin.y.value] == [x, y], "its corner at the click: \(xywh(palette))")
    #expect(overlaysDemoModel.paletteFrame.hasPrefix("(100, 60) "), "\(overlaysDemoModel.paletteFrame)")

    let note = try #require(window.lastHitboxes.first {
        $0.handlers.textInput != nil && !palette.contains($0.bounds.origin)
    }, "the note field")
    let (nx, ny) = centre(note.bounds)
    platform.simulateInput(ldown(nx, ny))
    platform.simulateInput(lup(nx, ny))
    #expect(!overlaysDemoModel.paletteShown, "the press outside closed it")
    #expect(window.focusedElement == note.id, "and focused the note field")
    redraw(window)
    #expect(window.lastOpenPopovers.isEmpty)
    withExtendedLifetime(window) {}
}
