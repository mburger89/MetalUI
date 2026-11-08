import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// `ScrollView([.horizontal, .vertical])` (Alloy gap G5, PR 2, rulings `XS-A`..`XS-D`; probe
// `docs/probes/swiftui-two-axis-scroll.swift`). A two-axis scroller keeps the vertical axis as its PRIMARY slot
// (`ScrollState.offset`) and the horizontal one in `ScrollState.cross`; one chrome core resolves each slot. The wheel goes
// WHOLE to one axis, so no event moves both offsets. Everything runs on a bare `Frame` or a `FakePlatformWindow`; nothing sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private let both: Axis.Set = [.horizontal, .vertical]
private let listID = ElementID("list")
private let rootID = GlobalElementID.child(of: nil, at: 0, name: listID)

private func wheel(_ at: Point<Pixels>, dx: Float = 0, dy: Float = 0, timestamp: Double = 1) -> InputEvent {
    .scrollWheel(ScrollEvent(position: at, delta: pt(dx, dy), phase: .none, momentumPhase: .none,
                             isPrecise: true, timestamp: timestamp))
}

@MainActor
private func windowFor<Root: Element>(size: Int = 100, _ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: size, content: content)
    settle(window)
    return (window, platform)
}

@MainActor
private func settle(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

/// (primary y, cross x) stored offsets of the one scroller.
@MainActor
private func stored(_ window: Window) throws -> (y: Double, x: Double) {
    let region = try #require(window.lastScrollRegions.first)
    let state = window.stateTable.peek(region.id, as: ScrollState.self)
    return (state?.offset ?? 0, state?.cross.offset ?? 0)
}

/// `element` through all three phases by hand, handing back its layout state (`ScrollIndicatorTests`' helper).
@MainActor
private func fullyRendered<E: Element>(_ element: inout E, width: Float, height: Float,
                                       stateTable: StateTable = StateTable(),
                                       timestamp: Double = 0) -> (Frame, E.LayoutState) {
    let frame = Frame(contentSize: Size(width: px(width), height: px(height)), scaleFactor: 1,
                      stateTable: stateTable, timestamp: timestamp)
    let id = GlobalElementID.child(of: nil, at: 0, name: element.elementID)
    var layoutPass = LayoutPass(frame: frame)
    let (root, layoutState) = element.requestLayout(id, pass: &layoutPass)
    var state = layoutState
    frame.computeRootLayout(root: root)
    let rootBounds = frame.bounds(of: root)
    var prepaintPass = PrepaintPass(frame: frame)
    var prepaintState = element.prepaint(id, bounds: rootBounds, layout: &state, pass: &prepaintPass)
    var paintPass = PaintPass(frame: frame)
    element.paint(id, bounds: rootBounds, layout: &state, prepaint: &prepaintState, pass: &paintPass)
    return (frame, state)
}

@MainActor private func content(_ w: Float, _ h: Float) -> some Element {
    Column { Box().frame(width: px(w), height: px(h)) }
}

// MARK: - X2, X7

/// **X2** (`XS-A`). `ScrollView(Axis.Set.horizontal)` is the scroller `ScrollView(.horizontal)` is, and so for `.vertical` and for
/// `ProposalScrollView`: the same rects, the same `measureCalls`, the same `axis`. Stop condition 4: the one-axis path is
/// byte-identical. **Mutation:** the `Axis.Set` init storing `[.horizontal, .vertical]` for a one-axis set reddens it.
@Test @MainActor func aOneAxisSetIsTheScrollerTheScrollAxisSpellingIs() throws {
    func measured(_ element: inout some Element) -> (Frame, NativeLayoutWork) {
        let (frame, _) = fullyRendered(&element, width: 100, height: 100)
        return (frame, frame.tree.lastNativeLayoutWork)
    }
    for (name, axes, axis) in [("horizontal", Axis.Set.horizontal, ScrollAxis.horizontal), ("vertical", .vertical, .vertical)] {
        var a = ScrollView(axis, elementID: listID) { content(300, 300) }
        var b = ScrollView(axes, elementID: listID) { content(300, 300) }
        try #require(a.axis == b.axis && b.axes == axes, "\(name)")
        let (fa, wa) = measured(&a), (fb, wb) = measured(&b)
        #expect(wa == wb, "\(name): \(wa) against \(wb)")
        #expect(fa.finalizedScene().rects.count == fb.finalizedScene().rects.count, "\(name)")
        let regionA = fa.hitboxes.first(where: { $0.scroll != nil }), regionB = fb.hitboxes.first(where: { $0.scroll != nil })
        #expect(regionA?.bounds == regionB?.bounds && regionA?.scrollAxes == regionB?.scrollAxes
                && regionA?.scrollTakes == regionB?.scrollTakes && regionA?.scrollRoom == regionB?.scrollRoom, "\(name)")
        var pa = ProposalScrollView(axis, elementID: listID) { Spacer() }
        let pb = ProposalScrollView(axes, elementID: listID) { Spacer() }
        #expect(pa.axes == pb.axes && pa.axis == pb.axis, "\(name)")
        pa.axis = .vertical
        #expect(pa.axes == .vertical, "the axis setter writes the set")
    }
}

// MARK: - X3

/// **X3** (`XS-C`, `XS-D`, probe `A1`, `A2`, `A3`, `A7`). A 100 x 100 two-axis scroller over 300 x 400: a horizontal wheel moves x,
/// a vertical one y, and a diagonal goes WHOLE to its dominant axis (-30, -40: y only); an overshoot clamps to (200, 300) and the
/// clamp is written back to BOTH slots, so the reverse wheel moves at once (no banked excess). **Mutation:** the cross slot's
/// `resolveSlot` run on a copy (`ScrollChrome.resolvedOffsets`), so the clamp is read but not written back: the stored x stays
/// 550 and the reverse wheel pays the 350 excess first.
@Test @MainActor func aTwoAxisScrollerMovesEachAxisAndClampsAndWritesBackBoth() throws {
    let (window, platform) = try windowFor { ScrollView(both) { content(300, 400) } }
    let at = pt(50, 50)
    platform.simulateInput(wheel(at, dx: -50)); settle(window)
    var s = try stored(window)
    #expect(s.x == 50 && s.y == 0, "\(s)")
    platform.simulateInput(wheel(at, dy: -70)); settle(window)
    s = try stored(window)
    #expect(s.x == 50 && s.y == 70, "\(s)")
    platform.simulateInput(wheel(at, dx: -30, dy: -40)); settle(window)
    s = try stored(window)
    #expect(s.x == 50 && s.y == 110, "a diagonal goes whole to the dominant axis (y): \(s)")
    platform.simulateInput(wheel(at, dx: -500)); settle(window)
    platform.simulateInput(wheel(at, dy: -500)); settle(window)
    s = try stored(window)
    #expect(s.x == 200 && s.y == 300, "clamped to the content, written back: \(s)")
    platform.simulateInput(wheel(at, dx: 10)); settle(window)
    platform.simulateInput(wheel(at, dy: 10)); settle(window)
    s = try stored(window)
    #expect(s.x == 190 && s.y == 290, "the reverse moves at once: \(s)")
}

// MARK: - X4

/// **X4** (`XS-D`). The content's translation takes both offsets: after scrolling (50, 70) the 20 x 20 box at content (165, 150) (the Row
/// is centred in the 400 wide Column)
/// sits at window (115, 80), so a click there fires it, and a click at its old place (175, 160) does not. **Mutation:** drop x
/// from `ScrollChrome.translation(offset:cross:)`: the box sits at (165, 80) and the click at (125, 90) misses.
@Test @MainActor func aTwoAxisScrollersContentIsTranslatedByBothOffsets() throws {
    let log = Fired()
    let (window, platform) = try windowFor(size: 300) {
        ScrollView(both) {
            Column {
                Box().frame(width: px(150), height: px(150))
                Row {
                    Box().frame(width: px(150), height: px(20))
                    Box().frame(width: px(20), height: px(20)).onClick { log.count += 1 }
                    Box().frame(width: px(200), height: px(20))
                }
                Box().frame(width: px(400), height: px(300))
            }
        }
    }
    platform.simulateInput(wheel(pt(10, 10), dx: -50)); settle(window)
    platform.simulateInput(wheel(pt(10, 10), dy: -70)); settle(window)
    let s = try stored(window)
    try #require(s.x == 50 && s.y == 70, "\(s)")
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(125, 90)))); platform.simulateInput(.mouseUp(MouseEvent(position: pt(125, 90))))
    #expect(log.count == 1, "the box moved to window (115, 80)..<(135, 100)")
    platform.simulateInput(.mouseDown(MouseEvent(position: pt(175, 160)))); platform.simulateInput(.mouseUp(MouseEvent(position: pt(175, 160))))
    #expect(log.count == 1, "nothing is at the unscrolled place any more")
}

@MainActor private final class Fired { var count = 0 }

// MARK: - X5

@MainActor private func scrolledState(y: Double, x: Double, lastScrollTime: Double = 0) -> StateTable {
    let table = StateTable()
    table.withState(rootID, initial: ScrollState()) {
        $0.offset = y
        $0.cross.offset = x
        $0.lastScrollTime = lastScrollTime
    }
    return table
}

@MainActor private func thumbs(_ frame: Frame) -> [(x: Double, y: Double, w: Double, h: Double)] {
    frame.finalizedScene().rects.map { (Double($0.bounds.origin.x), Double($0.bounds.origin.y), Double($0.bounds.size.width), Double($0.bounds.size.height)) }
}

/// **X5** (`XS-D`). Two thumbs at analytic rects. 100 x 100 over 300 x 400 scrolled (50, 70): both axes scroll, so each track stops
/// 8 short of the shared corner: vertical track 92, thumb `92 * 100/400` = 23, travel `70/300 * (92 - 23)` = 16.1, at x 95, 3 wide;
/// horizontal track 92, thumb `92 * 100/300` = 30.667, travel `50/200 * (92 - 30.667)` = 15.333, at y 95, 3 tall. Content that fits
/// on x (100 x 400) has the one vertical thumb with no inset: thumb 25, travel `70/300 * 75` = 17.5. `.hidden` paints nothing and
/// asks for no frame. **Mutation:** `crossChrome.paintIndicator` skipped: one thumb. **Mutation 2:** the inset 0: tracks 100.
@Test @MainActor func aTwoAxisScrollerPaintsOneThumbPerAxisWithTheCornerInset() throws {
    var view = ScrollView(both, elementID: listID) { content(300, 400) }
    let (frame, _) = fullyRendered(&view, width: 100, height: 100, stateTable: scrolledState(y: 70, x: 50))
    let rects = thumbs(frame)
    try #require(rects.count == 2, "\(rects)")
    let v = rects[0], h = rects[1]
    #expect(abs(v.x - 95) < 0.01 && abs(v.w - 3) < 0.01 && abs(v.h - 23) < 0.01 && abs(v.y - 16.1) < 0.01, "vertical \(v)")
    #expect(abs(h.y - 95) < 0.01 && abs(h.h - 3) < 0.01 && abs(h.w - 30.667) < 0.01 && abs(h.x - 15.333) < 0.01, "horizontal \(h)")

    var fits = ScrollView(both, elementID: listID) { content(100, 400) }
    let (fitFrame, _) = fullyRendered(&fits, width: 100, height: 100, stateTable: scrolledState(y: 70, x: 0))
    let one = thumbs(fitFrame)
    try #require(one.count == 1, "\(one)")
    #expect(abs(one[0].h - 25) < 0.01 && abs(one[0].y - 17.5) < 0.01 && abs(one[0].x - 95) < 0.01, "\(one)")

    var hidden = ScrollView(both, elementID: listID) { content(300, 400) }.scrollIndicators(.hidden)
    let (hiddenFrame, _) = fullyRendered(&hidden, width: 100, height: 100, stateTable: scrolledState(y: 70, x: 50))
    #expect(thumbs(hiddenFrame).isEmpty && !hiddenFrame.hasActiveAnimations, "hidden costs nothing")
}
