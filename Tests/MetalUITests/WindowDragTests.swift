import Testing
import Metal
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// Window drag (item C22, rulings `WD-A`…`WD-J`; spec
// `docs/superpowers/specs/2026-10-12-window-drag-design.md` §5, tests 1.1–1.17).
// Everything runs through a real `Window` on a `FakePlatformWindow`; nothing
// sleeps. Geometry: a 300 × 300 window whose root fills it; the handle is a
// 32-point strip along the top, over a full-window viewport carrying the
// gestures MetalCreator's does (the C8-a reproduction). Under
// `windowStyle: .hiddenTitleBar` the fake reports a 32-point band.

@MainActor
private final class DLog {
    var entries: [String] = []
    func count(_ name: String) -> Int { entries.filter { $0 == name }.count }
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
private func rdown(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rdrag(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func rup(_ x: Float, _ y: Float) -> InputEvent {
    .rightMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 1))
}
private func odown(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseDown(MouseEvent(position: pt(x, y), buttonNumber: 2))
}
private func odrag(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseDragged(MouseEvent(position: pt(x, y), buttonNumber: 2))
}
private func oup(_ x: Float, _ y: Float) -> InputEvent {
    .otherMouseUp(MouseEvent(position: pt(x, y), buttonNumber: 2))
}

/// A window over `content`; `hidden` puts it under the hidden title bar with a
/// 32-point band (`AS-E`), otherwise the standard style and zero insets.
@MainActor
private func dragWindow<Root: Element>(hidden: Bool = true, performsWindowDrag: Bool = true,
                                       content: @escaping @MainActor () -> Root) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 300, content: content)
    platform.presentsMenusNatively = true
    platform.performsWindowDrag = performsWindowDrag
    if hidden {
        platform.titleBarInsets = Edges(top: px(32), right: px(0), bottom: px(0), left: px(0))
        window.windowStyle = .hiddenTitleBar
    }
    window.drawFrameIfNeeded()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
    return (window, platform)
}

/// The viewport: a 300 × 300 rectangle with the gestures of MetalCreator's.
@MainActor
private func viewport(_ log: DLog) -> some ProposalElementGroup {
    Rectangle().frame(width: px(300), height: px(300))
        .gesture(SpatialTapGesture().onEnded { _ in log.entries.append("tap") })
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in log.entries.append("changed") }
            .onEnded { _ in log.entries.append("ended") }
            .onCancelled { log.entries.append("cancelled") })
        .gesture(MagnifyGesture().onChanged { _ in log.entries.append("magnify") })
}

/// The handle: a 32-point strip carrying the window drag.
@MainActor
private func handle() -> some ProposalElementGroup {
    Rectangle().frame(width: px(300), height: px(32)).gesture(WindowDragGesture())
}

@MainActor
private func handleOverViewport(_ log: DLog) -> some Element {
    ZStack(alignment: .top) { viewport(log); handle() }
}

/// A press at (x, y), a move of `dx` to the right, the release.
@MainActor
private func dragged(_ platform: FakePlatformWindow, _ window: Window, _ x: Float = 100, _ y: Float = 16,
                     by dx: Float = 20, moves: Int = 1) {
    platform.simulateInput(ldown(x, y))
    for step in 1...max(1, moves) {
        platform.simulateInput(ldrag(x + dx * Float(step) / Float(max(1, moves)), y))
        window.drawFrameIfNeeded()
    }
    platform.simulateInput(lup(x + dx, y))
    window.drawFrameIfNeeded()
}

// MARK: - 1.1: the report, reproduced

/// **1.1** (C8-a, `AS-J`). With no handle a band press over a gesture viewport
/// forms an arena: `titleBarPresses == []`, no window drag, the viewport's drag
/// reported. The pin that `AS-J` is untouched and the bug is real.
/// Mutation: delete `!hasGestureArena` in `answerUnclaimedTitleBarPress`.
@MainActor
@Test func aBandPressOverAGestureViewportDragsNoWindowWithoutAHandle() throws {
    let log = DLog()
    let (window, platform) = try dragWindow { ZStack { viewport(log) } }
    try #require(window.titleBarStyleApplied)
    dragged(platform, window)
    #expect(platform.titleBarPresses.isEmpty, "the arena formed, so AS-J asked nothing")
    #expect(platform.windowDrags == 0)
    #expect(log.count("changed") >= 1, "the viewport's drag took the press: \(log.entries)")
}

// MARK: - 1.2–1.5: the arena

/// **1.2** (`WD-C`, `WD-D`; probe `W2`, separating arm `W9`). A handle over the viewport: a 20-point drag moves
/// the window once, the viewport sees nothing, the arena is gone.
/// Mutation: the leaf is never ready; or `act` does not fail the others.
@MainActor
@Test func aHandleOverAGestureViewportDragsTheWindowAndCancelsTheViewport() throws {
    let log = DLog()
    let (window, platform) = try dragWindow { handleOverViewport(log) }
    platform.simulateInput(ldown(100, 16))
    platform.simulateInput(ldrag(120, 16))
    #expect(platform.windowDrags == 1)
    #expect(!window.hasGestureArena, "the press was handed off")
    platform.simulateInput(lup(120, 16))
    window.drawFrameIfNeeded()
    #expect(log.entries.isEmpty, "the viewport, tap and magnify saw nothing: \(log.entries)")
    #expect(platform.titleBarPresses.isEmpty)
    #expect(platform.windowDrags == 1)
}

/// **1.3** (`WD-C`, `WD-D`). A move under the slop is no drag and a `Button` in
/// the handle still clicks once. Mutation: the leaf's slop → 0.
@MainActor
@Test func aMoveUnderTheSlopIsNoDragAndTheHandlesButtonStillClicks() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) {
            viewport(log)
            HStack {
                Button("B") { log.entries.append("button") }.frame(width: px(60), height: px(32))
                Spacer()
            }
            .frame(width: px(300), height: px(32))
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
        }
    }
    platform.simulateInput(ldown(30, 16))
    platform.simulateInput(ldrag(34, 16))
    platform.simulateInput(lup(34, 16))
    window.drawFrameIfNeeded()
    #expect(platform.windowDrags == 0)
    #expect(log.count("button") == 1, "the click went through: \(log.entries)")
}

/// **1.4** (`WD-C`). A move of exactly the slop begins one drag and never a
/// second; the release is no click. Mutation: the leaf is not ended after
/// acting.
@MainActor
@Test func aMoveOfExactlyTheSlopBeginsOneDragAndNeverASecond() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) {
            viewport(log)
            Rectangle().frame(width: px(300), height: px(32))
                .onTapGesture { log.entries.append("handleTap") }
                .gesture(WindowDragGesture())
        }
    }
    platform.simulateInput(ldown(100, 16))
    platform.simulateInput(ldrag(105, 16))
    #expect(platform.windowDrags == 1, "5 points is the slop")
    for x in [110, 120, 130, 140, 150, 160] as [Float] { platform.simulateInput(ldrag(x, 16)) }
    platform.simulateInput(lup(160, 16))
    window.drawFrameIfNeeded()
    #expect(platform.windowDrags == 1)
    #expect(log.entries.isEmpty, "no click, no viewport: \(log.entries)")
}

/// **1.5** (`WD-C`, `IF-F`). A handle inside a gesture-carrying viewport: the
/// viewport's drag reports (at the press and at the move), then runs `onCancelled` once and never
/// `onEnded`. Mutation: omit the cancel loop in the `.windowDrag` arm of `act`.
@MainActor
@Test func aHandleInsideTheViewportCutsTheViewportsDragThatHadReported() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) { handle() }
            .frame(width: px(300), height: px(300), alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }
                .onEnded { _ in log.entries.append("ended") }
                .onCancelled { log.entries.append("cancelled") })
    }
    dragged(platform, window)
    #expect(platform.windowDrags == 1)
    #expect(log.count("changed") >= 1, "the viewport reported before the handle acted: \(log.entries)")
    #expect(log.count("cancelled") == 1, "\(log.entries)")
    #expect(log.count("ended") == 0, "\(log.entries)")
}

// MARK: - 1.6–1.8: who outranks whom

/// **1.6** (probe `W3`). A `DragGesture` inside the handle outranks it.
/// Mutation: treat an undecided drag ahead as yielding in `isBlocked`.
@MainActor
@Test func aDragGestureInsideTheHandleOutranksIt() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) {
            viewport(DLog())
            Rectangle().frame(width: px(300), height: px(32))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in log.entries.append("inner") })
                .frame(width: px(300), height: px(32))
                .gesture(WindowDragGesture())
        }
    }
    dragged(platform, window)
    #expect(platform.windowDrags == 0)
    #expect(log.count("inner") >= 1, "\(log.entries)")
}

/// **1.7** (probe `W11b`). A high-priority ancestor `DragGesture` outranks the
/// handle. Mutation: register the leaf `.high` always.
@MainActor
@Test func aHighPriorityAncestorDragOutranksTheHandle() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) { handle() }
            .frame(width: px(300), height: px(300), alignment: .top)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0).onChanged { _ in log.entries.append("high") })
    }
    dragged(platform, window)
    #expect(platform.windowDrags == 0)
    #expect(log.count("high") >= 1, "\(log.entries)")
}

/// **1.8** (`WD-C`). A tap on the handle's own element still fires and drags
/// nothing. Mutation: drop `.windowDrag` from the yield rule.
@MainActor
@Test func aTapOnTheHandlesElementStillFiresAndDragsNothing() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) {
            viewport(DLog())
            Rectangle().frame(width: px(300), height: px(32))
                .onTapGesture { log.entries.append("tap") }
                .gesture(WindowDragGesture())
        }
    }
    platform.simulateInput(ldown(100, 16))
    platform.simulateInput(lup(100, 16))
    window.drawFrameIfNeeded()
    #expect(log.entries == ["tap"], "\(log.entries)")
    #expect(platform.windowDrags == 0)
}

// MARK: - 1.9–1.11: the hit region

/// **1.9** (probes `W2`, `W9`). A sibling viewport beneath the handle never
/// joins the arena; the same press outside the handle is the viewport's.
/// Mutation: register the handle non-opaque.
@MainActor
@Test func aSiblingViewportBeneathTheHandleNeverJoinsTheArena() throws {
    let log = DLog()
    let (window, platform) = try dragWindow { handleOverViewport(log) }
    dragged(platform, window, 100, 16)
    #expect(log.entries.isEmpty, "the handle took it: \(log.entries)")
    #expect(platform.windowDrags == 1)
    dragged(platform, window, 100, 150)
    #expect(log.count("changed") >= 1, "outside the handle the viewport's: \(log.entries)")
    #expect(platform.windowDrags == 1)
}

/// **1.10** (probe `W7`, `MN-B`). A secondary or other press in the handle drags
/// nothing, and the context menu still opens. Mutation: `isLive` true in a
/// button arena.
@MainActor
@Test func aSecondaryOrOtherPressInTheHandleDragsNothing() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        ZStack(alignment: .top) {
            viewport(log)
            Rectangle().frame(width: px(300), height: px(32))
                .gesture(WindowDragGesture())
                .contextMenu { Button("X") {} }
        }
    }
    platform.simulateInput(rdown(100, 16))
    platform.simulateInput(rdrag(130, 16))
    platform.simulateInput(rup(130, 16))
    window.drawFrameIfNeeded()
    #expect(platform.windowDrags == 0)
    #expect(platform.presentedMenus.count == 1, "the context menu still opens")
    platform.simulateInput(odown(100, 16))
    platform.simulateInput(odrag(130, 16))
    platform.simulateInput(oup(130, 16))
    window.drawFrameIfNeeded()
    #expect(platform.windowDrags == 0)
}

/// **1.11** (`WD-G`, `WD-J`, divergence 277). `.allowsHitTesting(false)`,
/// `.hidden()` and `.disabled(true)` each remove the handle: the press reaches
/// the viewport and no hitbox is left over; a fourth arm pins divergence 277 —
/// an `.opacity(0)` handle still captures. Mutation: remove
/// `hitTestingDisabledDepth == 0` from the opaque site (arms 1–2) or `enabled`
/// (arm 3).
@MainActor
@Test func allowsHitTestingFalseHiddenAndDisabledEachRemoveTheHandle() throws {
    func run<H: ElementGroup>(_ name: String, drags: Int, _ make: @escaping @MainActor () -> H) throws {
        let log = DLog()
        let (window, platform) = try dragWindow {
            ZStack(alignment: .top) { viewport(log); make() }
        }
        let (bare, _) = try dragWindow { ZStack(alignment: .top) { viewport(DLog()) } }
        if drags == 0 {
            #expect(window.lastHitboxes.count == bare.lastHitboxes.count, "\(name): the old hitbox count")
        }
        dragged(platform, window)
        #expect(platform.windowDrags == drags, "\(name): windowDrags")
        if drags == 0 {
            #expect(log.count("changed") >= 1, "\(name): the press reached the viewport: \(log.entries)")
        } else {
            #expect(log.entries.isEmpty, "\(name): the handle still captured: \(log.entries)")
        }
    }
    try run("allowsHitTesting(false)", drags: 0) { handle().allowsHitTesting(false) }
    try run("hidden()", drags: 0) {
        Box().frame(width: px(300), height: px(32)).hidden().gesture(WindowDragGesture())
    }
    try run("disabled(true)", drags: 0) { handle().disabled(true) }
    try run("opacity(0) (divergence 277)", drags: 1) { handle().opacity(0) }
}

// MARK: - 1.12–1.14: the platform answer and the press after

/// **1.12** (`WD-D`). A platform answering `false` still ends the press: the
/// members are cut, the arena gone, the release no click, the next press fresh.
/// Mutation: skip `endPressForDrag()` on `false`.
@MainActor
@Test func aPlatformAnsweringFalseStillEndsThePress() throws {
    let log = DLog()
    let (window, platform) = try dragWindow(performsWindowDrag: false) {
        ZStack(alignment: .top) {
            viewport(log)
            Rectangle().frame(width: px(300), height: px(32))
                .onTapGesture { log.entries.append("handleTap") }
                .gesture(WindowDragGesture())
        }
    }
    platform.simulateInput(ldown(100, 16))
    platform.simulateInput(ldrag(130, 16))
    #expect(platform.windowDrags == 1)
    #expect(!window.hasGestureArena)
    platform.simulateInput(lup(130, 16))
    window.drawFrameIfNeeded()
    #expect(log.entries.isEmpty, "the release is no click: \(log.entries)")
    dragged(platform, window)
    #expect(platform.windowDrags == 2, "the next press formed a fresh arena")
}

/// **1.13** (`WD-D`, `CI-AB`). A press after a window drag forms a fresh arena.
/// Mutation: omit `endPressForDrag()`.
@MainActor
@Test func aPressAfterAWindowDragFormsAFreshArena() throws {
    let (window, platform) = try dragWindow { handleOverViewport(DLog()) }
    dragged(platform, window)
    dragged(platform, window, 50, 10, by: 30, moves: 3)
    #expect(platform.windowDrags == 2)
}

/// **1.14** (`WD-H`). A handle works in a standard title-bar window and
/// anywhere in the window. Mutation: gate the callback on `windowStyle`.
@MainActor
@Test func aHandleWorksInAStandardTitleBarWindowAndAnywhereInTheWindow() throws {
    let (window, platform) = try dragWindow(hidden: false) {
        ZStack(alignment: .center) { viewport(DLog()); handle() }
    }
    dragged(platform, window, 100, 150)
    #expect(platform.windowDrags == 1)
    #expect(platform.titleBarPresses.isEmpty)
}

// MARK: - 1.15–1.17: classification and order

/// **1.15** (`WD-B`). The leaf is a pointer target, not a draggable.
/// Mutation: `isDraggable` includes `.windowDrag` (and 1.9).
@MainActor
@Test func aWindowDragLeafIsAPointerTargetNotADraggable() throws {
    let (window, _) = try dragWindow { handleOverViewport(DLog()) }
    let box = try #require(window.lastHitboxes.first { hit in
        hit.handlers.gestures.contains { if case .leaf(let l) = $0.node, case .windowDrag = l.kind { true } else { false } }
    })
    #expect(box.handlers.isPointerTarget)
    #expect(!box.handlers.hasDraggable)
    #expect(box.opaque)
}

/// **1.16** (divergence 275). On one element, attachment order decides:
/// `.gesture(drag).gesture(window)` is the drag's alone;
/// `.gesture(window).gesture(drag)` is the window's, cutting the drag.
/// Mutation: reverse the sort in `GestureArena.init`.
@MainActor
@Test func anAttachmentOrderOfHandleAndDragOnOneElementIsInnerFirst() throws {
    let a = DLog()
    let (windowA, platformA) = try dragWindow {
        Rectangle().frame(width: px(300), height: px(300))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in a.entries.append("changed") }.onEnded { _ in a.entries.append("ended") })
            .gesture(WindowDragGesture())
    }
    dragged(platformA, windowA, 100, 100)
    #expect(platformA.windowDrags == 0)
    #expect(a.count("changed") >= 1 && a.count("ended") == 1, "\(a.entries)")

    let b = DLog()
    let (windowB, platformB) = try dragWindow {
        Rectangle().frame(width: px(300), height: px(300))
            .gesture(WindowDragGesture())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in b.entries.append("changed") }.onEnded { _ in b.entries.append("ended") })
    }
    dragged(platformB, windowB, 100, 100)
    #expect(platformB.windowDrags == 1)
    #expect(b.count("ended") == 0, "the window cut the drag: \(b.entries)")
}

/// **1.17** (probe `W4`, mapped). A high-priority window drag outranks a drag
/// on the same element. Mutation: ignore `.high` for the leaf.
@MainActor
@Test func aHighPriorityWindowDragGestureOutranksTheViewport() throws {
    let log = DLog()
    let (window, platform) = try dragWindow {
        Rectangle().frame(width: px(300), height: px(300))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in log.entries.append("changed") }.onEnded { _ in log.entries.append("ended") })
            .highPriorityGesture(WindowDragGesture())
    }
    dragged(platform, window, 100, 100)
    #expect(platform.windowDrags == 1)
    #expect(log.count("ended") == 0, "\(log.entries)")
}
