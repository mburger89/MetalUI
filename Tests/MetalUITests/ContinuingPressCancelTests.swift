import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Continuing press cancel (C26; rulings `GC-A`…`GC-F`, decisions
// `docs/superpowers/2026-10-12-continuing-press-cancel-decisions.md`; spec
// `docs/superpowers/specs/2026-10-12-continuing-press-cancel-design.md` §3,
// ids 1.1–1.10). A leaf that reported a change owes `onCancelled` whatever ends
// it. `W` tests run through a real `Window` on a `FakePlatformWindow`; `A` tests
// drive `GestureArena` directly. Nothing sleeps. Geometry as `GestureFollowupTests`:
// a 300 × 300 window whose 200 × 200 root is centred at (50, 50)–(250, 250);
// `half()` boxes are 100 × 200.

@MainActor
private final class CLog {
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }

private func ldown(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseDown(MouseEvent(position: pt(x, y), clickCount: count))
}
private func ldrag(_ x: Float, _ y: Float) -> InputEvent { .mouseDragged(MouseEvent(position: pt(x, y))) }
private func lup(_ x: Float, _ y: Float, count: Int = 1) -> InputEvent {
    .mouseUp(MouseEvent(position: pt(x, y), clickCount: count))
}

@MainActor
private func cWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    platform.presentsMenusNatively = true
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

@MainActor private func half() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(100), height: px(200))
}

private let rootID = GlobalElementID(component: .positional(0), parent: nil)

@MainActor
private func region(_ gestures: [GestureAttachment]) -> Hitbox {
    var handlers = Handlers()
    handlers.gestures = gestures
    return Hitbox(bounds: Bounds(origin: pt(40, 30), size: Size(width: px(100), height: px(100))), id: rootID,
                  layer: 0, opaque: true, scroll: nil, handlers: handlers, origin: pt(40, 30), shape: nil,
                  transform: nil)
}

@MainActor
private func run(_ callbacks: [GestureCallback]) {
    for callback in callbacks {
        switch callback {
        case .gesture(_, let run): run()
        case .click(_, let handler, _): handler()
        case .beginDrag, .beginWindowDrag: break
        }
    }
}

@MainActor
private func loggedDrag(_ log: CLog, minimumDistance: Pixels = 0) -> some Gesture {
    DragGesture(minimumDistance: minimumDistance)
        .onChanged { _ in log.entries.append("changed") }
        .onEnded { _ in log.entries.append("end") }
        .onCancelled { log.entries.append("cancelled") }
}

// MARK: - 1.1, 1.4

/// **1.1** (`GC-A`, `GC-C`; SwiftUI probe `L1`). A drag that reported and whose
/// release is lost is cancelled by the next primary press on the same element,
/// which then starts a drag of its own. Mutation: revert `GC-C`'s condition.
@MainActor
@Test func aPrimaryPressOnTheSameElementAfterALostReleaseCancelsTheReportedDrag() throws {
    let log = CLog()
    let (window, platform) = try cWindow { half().gesture(loggedDrag(log)) }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(110, 100))
    platform.simulateInput(ldown(100, 100))   // the release is lost
    platform.simulateInput(lup(100, 100))
    #expect(log.entries == ["changed", "changed", "cancelled", "changed", "end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.4** (`GC-B`). Driven directly, a continuing press fails a reported drag
/// through the cancel path: `onCancelled`, never `onEnded`. Mutation: `GC-B` back
/// to `fail(leaf)`.
@MainActor
@Test func aContinuingPressCancelsAReportedDragThroughTheCancelPath() throws {
    let log = CLog()
    var arena = try #require(GestureArena(target: region([GestureAttachment(loggedDrag(log), priority: .normal)]),
                                          ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false))
    run(arena.move(to: pt(60, 60)))
    run(arena.press(at: pt(50, 60), clickCount: 2, continuing: true))
    #expect(log.entries == ["changed", "changed", "cancelled"], "\(log.entries)")
}
