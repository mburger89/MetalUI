import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Input follow-ups, lane 1 — gesture values and cancellation (rulings `IF-B`,
// `IF-C`, `IF-E`, `IF-F`; spec `docs/superpowers/specs/2026-10-10-input-followups-design.md`
// §3, ids 1.1–1.15). Everything runs through a real `Window` on a
// `FakePlatformWindow`; nothing sleeps. Geometry: a 300 × 300 window whose
// 200 × 200 root is centred at (50, 50)–(250, 250) (`CN-J`); `twoBoxes` is two
// 100 × 200 boxes, A at x 50…150 and B at x 150…250.

@MainActor
private final class FLog {
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func ldown(_ x: Float, _ y: Float, count: Int = 1, _ mods: Modifiers = []) -> InputEvent {
    .mouseDown(MouseEvent(position: pt(x, y), modifiers: mods, clickCount: count))
}
private func ldrag(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseDragged(MouseEvent(position: pt(x, y), clickCount: count))
}
private func lup(_ x: Float, _ y: Float, count: Int = 1, _ mods: Modifiers = []) -> InputEvent {
    .mouseUp(MouseEvent(position: pt(x, y), modifiers: mods, clickCount: count))
}
private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }
private func rdown(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rdrag(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rup(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func odown(_ x: Float, _ y: Float, count: Int = 1, button: Int = 2) -> InputEvent {
    .otherMouseDown(MouseEvent(position: pt(x, y), clickCount: count, buttonNumber: button))
}
private func odrag(_ x: Float, _ y: Float, count: Int = 1, button: Int = 2) -> InputEvent {
    .otherMouseDragged(MouseEvent(position: pt(x, y), clickCount: count, buttonNumber: button))
}
private func oup(_ x: Float, _ y: Float, count: Int = 1, button: Int = 2) -> InputEvent {
    .otherMouseUp(MouseEvent(position: pt(x, y), clickCount: count, buttonNumber: button))
}
private func magnify(_ delta: Double, _ phase: InputPhase, at p: Point<Pixels> = pt(100, 100)) -> InputEvent {
    .magnify(MagnifyEvent(position: p, magnification: delta, phase: phase))
}

@MainActor
private func fWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    platform.presentsMenusNatively = true
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor private func square() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(200), height: px(200))
}

@MainActor private func twoBoxes<A: Element, B: Element>(_ a: A, _ b: B) -> some StyledElement {
    Row { a; b }
}

@MainActor private func half() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(100), height: px(200))
}

// MARK: - 1.1, 1.2: a spatial tap's modifiers

/// **1.1** (`IF-B`). A tap pressed with ⌘ and released with nothing reports ⌘.
/// Mutation: take the release's modifiers.
@MainActor
@Test func aSpatialTapReportsTheModifiersHeldAtItsPress() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().gesture(SpatialTapGesture().onEnded { log.entries.append("\($0.modifiers.rawValue)") })
    }
    platform.simulateInput(ldown(150, 150, [.command]))
    platform.simulateInput(lup(150, 150, []))
    #expect(log.entries == ["\(Modifiers.command.rawValue)"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.2** (`IF-B`). A `count: 2` tap reports the second press's modifiers.
/// Mutation: keep the first press's.
@MainActor
@Test func aTapSequenceReportsTheLastPressModifiers() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().gesture(SpatialTapGesture(count: 2).onEnded { log.entries.append("\($0.modifiers.rawValue)") })
    }
    platform.simulateInput(ldown(150, 150, count: 1, [.shift]))
    platform.simulateInput(lup(150, 150, count: 1))
    platform.simulateInput(ldown(150, 150, count: 2, [.command]))
    platform.simulateInput(lup(150, 150, count: 2))
    #expect(log.entries == ["\(Modifiers.command.rawValue)"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.3, 1.4: a drag's click count

/// **1.3** (`IF-C` item 1). A drag pressed with click count 2 carries 2 in
/// every `onChanged` and its `onEnded`, whatever the move events carry.
/// Mutation: hard-code 1, or read the move event's count.
@MainActor
@Test func aDragValueCarriesThePressClickCount() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().gesture(DragGesture(minimumDistance: 0)
            .onChanged { log.entries.append("c\($0.clickCount)") }
            .onEnded { log.entries.append("e\($0.clickCount)") })
    }
    platform.simulateInput(ldown(150, 150, count: 2))
    platform.simulateInput(ldrag(160, 150, count: 1))
    platform.simulateInput(ldrag(170, 150, count: 1))
    platform.simulateInput(lup(170, 150, count: 1))
    #expect(log.entries == ["c2", "c2", "c2", "e2"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.4** (`IF-C` item 1). A middle-button drag carries its own press's count.
/// Mutation: read the primary path only (1 here).
@MainActor
@Test func aSecondaryDragCarriesItsPressClickCount() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().gesture(DragGesture(minimumDistance: 0, button: .middle)
            .onChanged { log.entries.append("c\($0.clickCount)") }
            .onEnded { log.entries.append("e\($0.clickCount)") })
    }
    platform.simulateInput(odown(150, 150, count: 3))
    platform.simulateInput(odrag(160, 150))
    platform.simulateInput(oup(160, 150))
    #expect(log.entries == ["c3", "c3", "e3"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.5…1.9: where onCancelled runs, and where it does not

/// **1.5** (`IF-E`, `IF-F` item 1). A drag that reported on A and whose release
/// is lost is dropped by a press on B: `onCancelled` once, before B's own
/// callbacks, never `onEnded`. Mutation: drop the cancel in `abandon()`.
@MainActor
@Test func aDroppedPrimaryDragReportsCancelledOnceAndNotEnded() throws {
    let log = FLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in log.entries.append("\(name) changed") }
            .onEnded { _ in log.entries.append("\(name) end") }
            .onCancelled { log.entries.append("\(name) cancelled") }
    }
    let (window, platform) = try fWindow {
        twoBoxes(half().gesture(drag("A")), half().gesture(drag("B")))
    }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(110, 100))
    platform.simulateInput(ldown(200, 100))   // A's release is lost
    platform.simulateInput(lup(200, 100))
    #expect(log.entries == ["A changed", "A changed", "A cancelled", "B changed", "B end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.6** (`IF-F` item 2). The `CI-AB` 2.26 setup: a stale middle arena on A
/// replaced by the next middle press on B reports `onCancelled` before B's
/// first change. Mutation: restore `buttonArena = nil`.
@MainActor
@Test func aStaleButtonArenaReportsCancelledWhenTheSameButtonPressesAgain() throws {
    let log = FLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 0, button: .middle)
            .onChanged { _ in log.entries.append("\(name) changed") }
            .onEnded { _ in log.entries.append("\(name) end") }
            .onCancelled { log.entries.append("\(name) cancelled") }
    }
    let (window, platform) = try fWindow {
        twoBoxes(half().gesture(drag("A")), half().gesture(drag("B")))
    }
    platform.simulateInput(odown(100, 100))
    platform.simulateInput(odrag(110, 100))
    platform.simulateInput(odown(200, 100))
    platform.simulateInput(oup(200, 100))
    #expect(log.entries == ["A changed", "A changed", "A cancelled", "B changed", "B end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.7** (`IF-F` item 2). A magnify whose end is lost, followed by a new
/// `.began` at the same centre: `onCancelled` closes the first, and the new
/// pinch starts from 1 (120, not 130). Mutation: restore `pinchArena = nil`.
@MainActor
@Test func aStalePinchArenaReportsCancelledBeforeASameCentrePinchBegins() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        half().gesture(MagnifyGesture()
            .onChanged { log.entries.append("changed \(Int(($0.magnification * 100).rounded()))") }
            .onEnded { _ in log.entries.append("end") }
            .onCancelled { log.entries.append("cancelled") })
    }
    platform.simulateInput(magnify(0, .began))
    platform.simulateInput(magnify(0.1, .changed))
    platform.simulateInput(magnify(0, .began))   // the first pinch's end was lost
    platform.simulateInput(magnify(0.2, .changed))
    platform.simulateInput(magnify(0, .ended))
    #expect(log.entries == ["changed 110", "cancelled", "changed 120", "end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.8** (`IF-E` item 1). A drag that never reached its minimum is dropped
/// with no cancel. Mutation: cancel every leaf.
@MainActor
@Test func aDragThatNeverBeganIsNotCancelled() throws {
    let log = FLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { _ in log.entries.append("\(name) changed") }
            .onCancelled { log.entries.append("\(name) cancelled") }
    }
    let (window, platform) = try fWindow {
        twoBoxes(half().gesture(drag("A")), half().gesture(drag("B")))
    }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(103, 100))
    platform.simulateInput(ldown(200, 100))
    #expect(log.entries.isEmpty, "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.9** (`IF-E` item 1). A drag that ended is not cancelled by the next
/// press. Mutation: cancel after `onEnded` too.
@MainActor
@Test func aReleasedDragIsNotCancelledByTheNextPress() throws {
    let log = FLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { _ in log.entries.append("\(name) end") }
            .onCancelled { log.entries.append("\(name) cancelled") }
    }
    let (window, platform) = try fWindow {
        twoBoxes(half().gesture(drag("A")), half().gesture(drag("B")))
    }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(lup(100, 100))
    platform.simulateInput(ldown(200, 100))
    #expect(log.entries == ["A end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.10, 1.11: a move without a button

/// **1.10** (`IF-F` item 3, `IF-K` item 4). A `.mouseMoved` while a middle arena
/// is live means the release was lost: `onCancelled` once, no `onEnded`, the
/// late release runs nothing, and a later press of another button works. The
/// drag events of the same button keep the arena (the first half). Mutation:
/// remove the `.mouseMoved` arm.
@MainActor
@Test func aMoveWithoutAButtonCancelsALiveButtonArena() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square()
            .gesture(DragGesture(minimumDistance: 0, button: .middle)
                .onChanged { _ in log.entries.append("middle changed") }
                .onEnded { _ in log.entries.append("middle end") }
                .onCancelled { log.entries.append("middle cancelled") })
            .gesture(DragGesture(minimumDistance: 0, button: .other(3))
                .onChanged { _ in log.entries.append("back changed") }
                .onEnded { _ in log.entries.append("back end") })
    }
    platform.simulateInput(odown(150, 150))
    platform.simulateInput(odrag(155, 150))
    #expect(log.entries == ["middle changed", "middle changed"], "drag events keep the arena: \(log.entries)")
    platform.simulateInput(moved(160, 150))
    #expect(log.entries.suffix(1) == ["middle cancelled"], "\(log.entries)")
    platform.simulateInput(oup(160, 150))
    #expect(log.entries.filter { $0 == "middle cancelled" }.count == 1 && !log.entries.contains("middle end"),
            "\(log.entries)")
    platform.simulateInput(odown(150, 150, button: 3))
    platform.simulateInput(oup(150, 150, button: 3))
    #expect(log.entries.suffix(2) == ["back changed", "back end"], "a later press works: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.10b** (`IF-F` item 3). The same move drops a pending context menu: a
/// secondary press with a secondary drag declared defers the menu to the
/// release; a move in between drops it, so the late release opens nothing.
/// Mutation: leave `pendingContextMenu` alone in the `.mouseMoved` arm.
@MainActor
@Test func aMoveWithoutAButtonDropsAPendingContextMenu() throws {
    let (window, platform) = try fWindow {
        square()
            .contextMenu { Button("A") {} }
            .gesture(DragGesture(button: .secondary).onChanged { _ in })
    }
    platform.simulateInput(rdown(150, 150))
    platform.simulateInput(moved(152, 150))
    platform.simulateInput(rup(152, 150))
    #expect(platform.presentedMenus.isEmpty, "the release was lost; the menu is not opened late")
    withExtendedLifetime(window) {}
}

/// **1.11** (`IF-A`, `IF-F` item 3, the deferral). A move without a button does
/// not cancel the PRIMARY arena. Mutation: extend the arm to the primary arena.
@MainActor
@Test func aPrimaryArenaIsNotCancelledByAMoveWithoutAButton() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in log.entries.append("changed") }
            .onEnded { _ in log.entries.append("end") }
            .onCancelled { log.entries.append("cancelled") })
    }
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(moved(160, 150))
    platform.simulateInput(lup(160, 150))
    #expect(log.entries == ["changed", "end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.12, 1.13: the window leaves key

/// **1.12** (`IF-F` item 4). A window leaving key mid-pinch cancels the pinch
/// arena. Mutation: remove the control-state line.
@MainActor
@Test func aPinchArenaIsCancelledWhenTheWindowLeavesKey() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        half().gesture(MagnifyGesture()
            .onChanged { _ in log.entries.append("changed") }
            .onEnded { _ in log.entries.append("end") }
            .onCancelled { log.entries.append("cancelled") })
    }
    platform.simulateInput(magnify(0, .began))
    platform.simulateInput(magnify(0.1, .changed))
    platform.simulateControlActiveStateChange(to: .inactive)
    #expect(log.entries == ["changed", "cancelled"], "\(log.entries)")
    platform.simulateControlActiveStateChange(to: .key)
    platform.simulateInput(magnify(0.1, .ended))
    #expect(log.entries == ["changed", "cancelled"], "a late end finds no arena: \(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.13** (`IF-F` item 4, SwiftUI `C4`). Leaving key does not cancel a drag:
/// the release still ends it. Mutation: cancel every arena on key loss.
@MainActor
@Test func aDragIsNotCancelledWhenTheWindowLeavesKey() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square()
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("end") }
                .onCancelled { log.entries.append("cancelled") })
            .gesture(DragGesture(minimumDistance: 0, button: .middle)
                .onChanged { _ in log.entries.append("m changed") }
                .onEnded { _ in log.entries.append("m end") }
                .onCancelled { log.entries.append("m cancelled") })
    }
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(odown(150, 150))
    platform.simulateControlActiveStateChange(to: .inactive)
    platform.simulateInput(lup(150, 150))
    platform.simulateInput(oup(150, 150))
    #expect(!log.entries.contains("cancelled") && !log.entries.contains("m cancelled"), "\(log.entries)")
    #expect(log.entries.contains("end"), "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.14, 1.15: close and a draggable's preview

private struct FCloser: Component {
    let log: FLog
    var content: some ElementGroup {
        Box().frame(width: Pixels(200), height: Pixels(200))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("end") }
                .onCancelled { log.entries.append("cancelled") })
            .onDisappear { log.entries.append("disappear") }
    }
}

/// **1.14** (`IF-F` item 5). Closing the window cancels a live arena before the
/// `onDisappear`s. Mutation: run the cancel after the disappearances.
@MainActor
@Test func aWindowCloseCancelsLiveArenasBeforeOnDisappear() throws {
    let log = FLog()
    let (window, platform) = try fWindow { Column { FCloser(log: log) } }
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(ldrag(160, 150))
    window.runDisappearancesForClose()
    #expect(log.entries == ["changed", "changed", "cancelled", "disappear"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.15** (`IF-F` item 1). A `DragGesture` beside a draggable that reported
/// before the preview began is cancelled when the draggable wins. Mutation:
/// remove the cancel where the draggable fails the other members.
@MainActor
@Test func aDragStartedByADraggablesPreviewIsCancelled() throws {
    let log = FLog()
    let (window, platform) = try fWindow {
        square().draggable("payload")
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("end") }
                .onCancelled { log.entries.append("cancelled") })
    }
    platform.simulateInput(ldown(150, 150))
    platform.simulateInput(ldrag(160, 150))
    try #require(window.dragSession != nil, "set up: the draggable began its session")
    #expect(log.entries.contains("cancelled") && !log.entries.contains("end"), "\(log.entries)")
    #expect(log.entries.filter { $0 == "cancelled" }.count == 1, "\(log.entries)")
    withExtendedLifetime(window) {}
}
