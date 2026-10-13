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
    run(arena.cancel())   // the leaf failed with its cancel: nothing is owed twice
    run(arena.abandon())
    #expect(log.entries == ["changed", "changed", "cancelled"], "\(log.entries)")
}

private func moved(_ x: Float, _ y: Float) -> InputEvent { .mouseMoved(MouseEvent(position: pt(x, y))) }

@MainActor private func twoBoxes<A: Element, B: Element>(_ a: A, _ b: B) -> some StyledElement {
    Row { a; b }
}

// MARK: - 1.2, 1.3

/// **1.2** (`GC-C`; probe `L2`). A drag with a minimum distance that reported,
/// lost its release and is pressed again is cancelled once, and the new press
/// starts a full second drag (it is not swallowed). Mutation: revert `GC-C`.
@MainActor
@Test func aLostReleaseDragWithAMinimumDistanceStartsAgainOnTheNextPress() throws {
    let log = CLog()
    let (window, platform) = try cWindow { half().gesture(loggedDrag(log, minimumDistance: px(10))) }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(120, 100))
    platform.simulateInput(ldown(100, 100))   // the release is lost
    platform.simulateInput(ldrag(125, 100))
    platform.simulateInput(lup(125, 100))
    #expect(log.entries == ["changed", "cancelled", "changed", "end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.3** (`GC-A`). A leaf is cancelled once: a further press elsewhere after the
/// lost-release press, and a second `cancel()` of the arena, report nothing more.
/// Mutation: make `cancel` not fail the leaf.
@MainActor
@Test func aLostReleaseCancelsOnceAndALaterReleaseDoesNotCancelAgain() throws {
    let log = CLog()
    let (window, platform) = try cWindow { twoBoxes(half().gesture(loggedDrag(log)), half()) }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(110, 100))
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(lup(100, 100))
    platform.simulateInput(ldown(200, 100))
    platform.simulateInput(lup(200, 100))
    #expect(log.entries == ["changed", "changed", "cancelled", "changed", "end"], "\(log.entries)")

    let arenaLog = CLog()
    var arena = try #require(GestureArena(target: region([GestureAttachment(loggedDrag(arenaLog), priority: .normal)]),
                                          ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false))
    run(arena.move(to: pt(60, 60)))
    run(arena.cancel())
    run(arena.cancel())
    run(arena.abandon())
    #expect(arenaLog.entries == ["changed", "changed", "cancelled"], "\(arenaLog.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.5

/// **1.5** (`GC-B`). A drag that never reported owes nothing: a continuing press
/// fails it silently. Mutation: `cancelCallback` ignoring `activated`.
@MainActor
@Test func aContinuingPressDoesNotCancelADragThatNeverReported() throws {
    let log = CLog()
    var arena = try #require(GestureArena(
        target: region([GestureAttachment(loggedDrag(log, minimumDistance: px(10)), priority: .normal)]),
        ancestors: []))
    run(arena.press(at: pt(50, 60), clickCount: 1, continuing: false))
    run(arena.press(at: pt(50, 60), clickCount: 2, continuing: true))
    #expect(log.entries.isEmpty, "\(log.entries)")
}

// MARK: - 1.6, 1.7: a real second press still continues

/// **1.6** (`GC-C`, `GC-F`). A real double-click (press, release, press, release)
/// completes a `count: 2` tap beside an undecided drag: the tap fires once, the
/// drag reports nothing. Mutation: always abandon and form a fresh arena.
@MainActor
@Test func aRealDoubleClickStillCompletesATapCountTwoAndFiresNothingSpurious() throws {
    let log = CLog()
    let (window, platform) = try cWindow {
        half()
            .gesture(SpatialTapGesture(count: 2).onEnded { _ in log.entries.append("tap") })
            .gesture(loggedDrag(log, minimumDistance: px(5)))
    }
    platform.simulateInput(ldown(100, 100, count: 1))
    platform.simulateInput(lup(100, 100, count: 1))
    #expect(log.entries.isEmpty, "\(log.entries)")
    platform.simulateInput(ldown(100, 100, count: 2))
    platform.simulateInput(lup(100, 100, count: 2))
    #expect(log.entries == ["tap"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.7** (`IF-C`, `GC-C`). A drag pressed after a release carries the second
/// press's click count, and the first drag ended normally. Mutation: as 1.6.
@MainActor
@Test func aDragWithClickCountTwoStillReportsTheSecondPress() throws {
    let log = CLog()
    let (window, platform) = try cWindow {
        half().gesture(DragGesture(minimumDistance: 0)
            .onChanged { log.entries.append("c\($0.clickCount)") }
            .onEnded { log.entries.append("e\($0.clickCount)") }
            .onCancelled { log.entries.append("cancelled") })
    }
    platform.simulateInput(ldown(100, 100, count: 1))
    platform.simulateInput(lup(100, 100, count: 1))
    platform.simulateInput(ldown(100, 100, count: 2))
    platform.simulateInput(lup(100, 100, count: 2))
    #expect(log.entries == ["c1", "e1", "c2", "e2"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

// MARK: - 1.8, 1.9

/// **1.8** (`GC-C`, option (b) not built; SwiftUI probe `L3`). A bare move after
/// a lost release cancels nothing. Mutation: add a `.mouseMoved` cancel.
@MainActor
@Test func aMouseMovedWhileTheLostPrimaryArenaIsPressingDoesNotCancelIt() throws {
    let log = CLog()
    let (window, platform) = try cWindow { half().gesture(loggedDrag(log)) }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(110, 100))
    platform.simulateInput(moved(112, 100))
    #expect(log.entries == ["changed", "changed"], "\(log.entries)")
    withExtendedLifetime(window) {}
}

/// **1.9** (`IF-F` item 1 beside `GC-C`). A press on another element still
/// cancels once, before the new callbacks. Mutation: drop the cancel in `abandon()`.
@MainActor
@Test func aLostReleaseOnAnotherElementStillCancelsOnceAndBeforeTheNewCallbacks() throws {
    let log = CLog()
    func drag(_ name: String) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in log.entries.append("\(name) changed") }
            .onEnded { _ in log.entries.append("\(name) end") }
            .onCancelled { log.entries.append("\(name) cancelled") }
    }
    let (window, platform) = try cWindow {
        twoBoxes(half().gesture(drag("A")), half().gesture(drag("B")))
    }
    platform.simulateInput(ldown(100, 100))
    platform.simulateInput(ldrag(110, 100))
    platform.simulateInput(ldown(200, 100))
    platform.simulateInput(lup(200, 100))
    #expect(log.entries == ["A changed", "A changed", "A cancelled", "B changed", "B end"], "\(log.entries)")
    withExtendedLifetime(window) {}
}
