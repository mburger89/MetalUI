import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
@testable import MetalUI

// A two-axis scroller with the things inside it (Alloy gap G5, PR 3, rulings `XS-H`..`XS-K`; probe
// `docs/probes/swiftui-two-axis-scroll.swift`). `ScrollContext` and `ScrollerFrame` carry the horizontal axis as `cross`, and
// `along(_:)` answers the numbers of the axis a reader asks for, so a `LazyVStack` windows on the vertical offset and a
// `LazyHStack` on the horizontal one inside the same scroller. A bare `Frame` and a shared `StateTable` (the stand-in for a
// wheel is the offsets written into the scroller's `ScrollState`), or a `FakePlatformWindow`; nothing sleeps.

private func px(_ v: Float) -> Pixels { Pixels(v) }
private func pt(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: px(x), y: px(y)) }
private let both: Axis.Set = [.horizontal, .vertical]
private let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)

@MainActor
private final class CellLog {
    var built: [Int] = []
    func reset() { built = [] }
}

/// A cell `width` x `height` (where the proposal leaves the axis open), logging when it is built.
private struct Cell: ProposalElement {
    let key: Int
    let log: CellLog
    let width: Double, height: Double

    func requestProposalLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (ProposalNodeID, Void) {
        log.built.append(key)
        let w = width, h = height
        return (pass.requestNativeLeaf { proposal in
            LayoutMeasurement(size: SizeD(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? w,
                                          height: proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? h))
        }, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// The legacy twin, for a `List` row.
private struct LegacyCell: Element {
    let key: Int
    let log: CellLog
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.built.append(key)
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { proposal in
                LayoutMeasurement(size: SizeD(width: proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 300, height: 20))
            }
        }
        return (node, ())
    }
    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void,
                        pass: inout PaintPass) {}
}

private struct Item: Identifiable, Hashable { let id: Int }

@MainActor
private func setOffsets(_ states: StateTable, y: Double, x: Double) {
    states.withState(rootID, initial: ScrollState()) { $0.offset = y; $0.cross.offset = x }
}

@MainActor
private func render<Root: Element>(_ states: StateTable, _ log: CellLog, size: Float = 200, _ root: () -> Root) -> Frame {
    log.reset()
    let frame = Frame(contentSize: Size(width: px(size), height: px(size)), scaleFactor: 1, stateTable: states)
    var element = root()
    frame.render(&element)
    return frame
}

@MainActor
private func settle<Root: Element>(_ states: StateTable, _ log: CellLog, _ root: () -> Root) -> Frame {
    var frame = render(states, log, root)
    for _ in 0..<8 where frame.wantsAnotherFrame { frame = render(states, log, root) }
    return frame
}

// MARK: - Z1, Z2

/// **Z1** (`XS-H`). A `LazyVStack` of 1000 rows 20 tall and 800 wide in a 200 x 200 two-axis scroller realises the window of
/// ROWS: rows 0..<13 at rest (the bottom edge 200 is in row 10, plus one and two of overscan), the same after a `dx`-only move
/// (the horizontal offset is not the stack's axis), and rows 18..<33 at y 400 (row 20 holds the top, 18 after overscan; row 30
/// holds the bottom edge 600, so 33). The control is a one-axis vertical scroller. **Mutation:** `ScrollContext.along(.vertical)`
/// answering the cross slot (`other == .vertical ? cross`) windows on x: the dx move shifts the window and the dy one does not.
@Test @MainActor func aLazyVStackInATwoAxisScrollerWindowsOnTheVerticalOffsetOnly() throws {
    let states = StateTable(), log = CellLog()
    func root() -> some Element {
        ProposalScrollView(both) {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000, id: \.self) { Cell(key: $0, log: log, width: 800, height: 20) }
            }
        }
    }
    let rest = settle(states, log, root)
    #expect(!rest.wantsAnotherFrame && rest.lazyWork.unbounded == 0, "\(rest.lazyWork)")
    #expect(Set(log.built) == Set(0..<13), "at rest: \(log.built)")
    setOffsets(states, y: 0, x: 150)
    _ = settle(states, log, root)
    _ = render(states, log, root)
    #expect(Set(log.built) == Set(0..<13), "a dx-only move leaves the window: \(log.built)")
    setOffsets(states, y: 400, x: 150)
    _ = settle(states, log, root)
    let moved = render(states, log, root)
    #expect(Set(log.built) == Set(18..<33), "a dy move: \(log.built)")
    #expect(moved.lazyWork.linesRealized == 15, "\(moved.lazyWork)")
}

/// **Z2** (`XS-H`). A `LazyHStack` of 1000 columns 20 wide and 800 tall windows on the HORIZONTAL offset of the same kind of
/// scroller: columns 0..<13 at rest, unchanged by a `dy`-only move, 18..<33 at x 400. **Mutation:** `ScrollContext.along(.horizontal)` and
/// `ScrollerFrame.along(.horizontal)` answering `nil`: the stack is unbounded (every column realised).
@Test @MainActor func aLazyHStackInATwoAxisScrollerWindowsOnTheHorizontalOffset() throws {
    let states = StateTable(), log = CellLog()
    func root() -> some Element {
        ProposalScrollView(both) {
            LazyHStack(spacing: Pixels(0)) {
                ForEach(0..<1000, id: \.self) { Cell(key: $0, log: log, width: 20, height: 800) }
            }
        }
    }
    let rest = settle(states, log, root)
    #expect(rest.lazyWork.unbounded == 0, "\(rest.lazyWork)")
    #expect(Set(log.built) == Set(0..<13), "at rest: \(log.built)")
    setOffsets(states, y: 150, x: 0)
    _ = settle(states, log, root)
    _ = render(states, log, root)
    #expect(Set(log.built) == Set(0..<13), "a dy-only move leaves the window: \(log.built)")
    setOffsets(states, y: 150, x: 400)
    _ = settle(states, log, root)
    _ = render(states, log, root)
    #expect(Set(log.built) == Set(18..<33), "a dx move: \(log.built)")
}

/// **Z3** (`XS-H`). A `List` of 1000 rows in a two-axis scroller windows on the vertical offset exactly as in a one-axis vertical
/// scroller (the primary axis of a two-axis scroller is vertical): the same set of rows at rest, at y 400, and unchanged at a
/// `dx`. **Mutation:** `List` reading `context.along(.horizontal)` (`List.swift` windowing on the cross slot): the dx move
/// shifts the window.
@Test @MainActor func aListInATwoAxisScrollerWindowsVerticallyLikeAOneAxisOne() throws {
    func built(_ axes: Axis.Set, y: Double, x: Double) -> [Int] {
        let states = StateTable(), log = CellLog()
        func root() -> some Element {
            ScrollView(axes) {
                Box(style: columnStyle(width: 300)) {
                    List((0..<1000).map(Item.init)) { item in LegacyCell(key: item.id, log: log) }
                }
            }
        }
        _ = settle(states, log, root)
        setOffsets(states, y: y, x: x)
        _ = settle(states, log, root)
        _ = render(states, log, root)
        return Array(Set(log.built)).sorted()
    }
    let atRest = built(both, y: 0, x: 0)
    #expect(!atRest.isEmpty && atRest.count < 40 && atRest.first == 0, "windowed: \(atRest)")
    #expect(atRest == built(.vertical, y: 0, x: 0), "as the one-axis scroller")
    #expect(built(both, y: 0, x: 120) == atRest, "a dx-only move leaves the window")
    let moved = built(both, y: 400, x: 0)
    #expect(moved.first.map { $0 > 10 } == true && moved == built(.vertical, y: 400, x: 0), "a dy move: \(moved)")
}

private func columnStyle(width: Float) -> Style {
    var style = Style()
    style.flexDirection = .column
    style.size.width = .length(.pixels(px(width)))
    style.flexShrink = 0
    return style
}

// MARK: - Z4, Z5

@MainActor private final class Proxy { var proxy: ScrollViewProxy? }

/// A 10 x 10 grid of 30 x 30 cells (content 300 x 300) in a 100 x 100 two-axis scroller, each cell `.id("r,c")`.
@MainActor
private func gridWindow(_ holder: Proxy) throws -> Window {
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
        Box(style: columnStyle(width: 100)) {
            ScrollViewReader { proxy in
                let _ = { holder.proxy = proxy }()
                ScrollView(both) {
                    Column {
                        for r in 0..<10 {
                            Row {
                                for c in 0..<10 { Box().frame(width: px(30), height: px(30)).id("\(r),\(c)") }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    settleWindow(window)
    return window
}

@MainActor
private func settleWindow(_ window: Window) {
    window.setNeedsRedraw()
    for _ in 0..<8 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor
private func storedOffsets(_ window: Window) throws -> (y: Double, x: Double) {
    let region = try #require(window.lastScrollRegions.first)
    let state = window.stateTable.peek(region.id, as: ScrollState.self)
    return (state?.offset ?? 0, state?.cross.offset ?? 0)
}

/// **Z4** (`XS-I`, probe `T1`-`T5`). `scrollTo` into a two-axis scroller resolves BOTH axes by the one-axis rule: cell (5,5) is at
/// content (150, 150) 30 x 30 in a 100 x 100 viewport, so `.topLeading` lands at (150, 150), `.center` at `150 - 0.5 * 70` =
/// (115, 115), `.top` (anchor x 0.5, y 0) at x 115, y 150 (probe `T3`: `.top` centres x), `.bottomTrailing` at (80, 80); with no
/// anchor, from the origin, the least distance `150 + 30 - 100` = (80, 80), cell (9,9) the clamp (200, 200), cell (1,5) (row 1 is
/// visible on y) moves x only (80, 0) and cell (5,0) (column 0 is visible on x) moves y only (0, 80).
/// **Mutation:** the cross resolution dropped in `resolveScrollRequest` (`cross` always `nil`): x stays 0 in every row.
@Test @MainActor func scrollToResolvesBothAxesOfATwoAxisScroller() throws {
    let holder = Proxy()
    let window = try gridWindow(holder)
    let proxy = try #require(holder.proxy)
    func go(_ id: String, _ anchor: UnitPoint?) throws -> (y: Double, x: Double) {
        proxy.scrollTo(id, anchor: anchor)
        settleWindow(window)
        return try storedOffsets(window)
    }
    var o = try go("5,5", .topLeading)
    #expect(o.x == 150 && o.y == 150, ".topLeading \(o)")
    o = try go("5,5", .center)
    #expect(o.x == 115 && o.y == 115, ".center \(o)")
    o = try go("5,5", .top)
    #expect(o.x == 115 && o.y == 150, ".top centres x: \(o)")
    o = try go("5,5", .bottomTrailing)
    #expect(o.x == 80 && o.y == 80, ".bottomTrailing \(o)")
    _ = try go("0,0", .topLeading)
    o = try go("5,5", nil)
    #expect(o.x == 80 && o.y == 80, "no anchor, from the origin: least distance \(o)")
    o = try go("9,9", nil)
    #expect(o.x == 200 && o.y == 200, "clamped to the content: \(o)")
    _ = try go("0,0", .topLeading)
    o = try go("1,5", nil)   // row 1 is y 30..60: visible; column 5 is x 150..180: ahead
    #expect(o.x == 80 && o.y == 0, "visible on y only: y unmoved: \(o)")
    o = try go("5,0", nil)   // row 5 is y 150..180: ahead; column 0 is x 0..30: behind
    #expect(o.x == 0 && o.y == 80, "visible on x only (behind on x): \(o)")
}

/// **Z5** (`XS-C`, `SP-F`). A glide runs on each slot with its own clock reading: a linear 1-second glide from (0, 0) to (100, 60)
/// (y, x) read at half time paints both slots halfway (50, 30), through the one `resolveSlot`. The cross glide is only
/// resolved when it is in the slot. **Mutation:** the cross `resolveSlot` call dropped from `resolvedOffsets`: the cross offset
/// stays at its stored 0, and `ScrollState.cross.glide` never ends.
@Test @MainActor func aGlideRunsOnBothSlotsOfATwoAxisScroller() throws {
    let states = StateTable()
    states.withState(rootID, initial: ScrollState()) {
        $0.glide = ScrollGlide(from: 0, to: 100, start: 0, animation: .linear(duration: 1))
        $0.cross.glide = ScrollGlide(from: 0, to: 60, start: 0, animation: .linear(duration: 1))
    }
    func frame(at time: Double) -> Frame {
        let frame = Frame(contentSize: Size(width: px(100), height: px(100)), scaleFactor: 1, stateTable: states, timestamp: time)
        var element = ScrollView(both) { Column { Box().frame(width: px(300), height: px(400)) } }
        frame.render(&element)
        return frame
    }
    let half = frame(at: 0.5)
    var state = try #require(states.peek(rootID, as: ScrollState.self))
    #expect(abs(state.offset - 50) < 0.001 && abs(state.cross.offset - 30) < 0.001, "\(state.offset) \(state.cross.offset)")
    #expect(half.hasActiveAnimations, "a running glide keeps the link awake")
    _ = frame(at: 2)
    state = try #require(states.peek(rootID, as: ScrollState.self))
    #expect(state.offset == 100 && state.cross.offset == 60 && state.glide == nil && state.cross.glide == nil,
            "landed: \(state.offset) \(state.cross.offset)")
}

// MARK: - Z6

@MainActor private final class Size2 { var w: Float = 300; var h: Float = 400 }

/// **Z6** (`XS-J`, probe `S1`-`S5`). `defaultScrollAnchor` per axis: `.bottomTrailing` starts at (max, max) = (200, 300), `.bottom`
/// centres x (100, 300), `.trailing` centres y (200, 150); growth follows per axis (500 x 600: (400, 500)); a wheel away on x
/// only releases the x pin and the y pin keeps following (probe `S5`: x stays, y follows the growth). **Mutation:** the
/// cross slot's anchor memory shared with the primary (`resolveSlot(anchor: &$0.anchor)` for both): the x pin is the y pin's
/// and the wheel on x releases neither / both.
@Test @MainActor func defaultScrollAnchorWorksPerAxisInATwoAxisScroller() throws {
    func start(_ anchor: UnitPoint) throws -> (y: Double, x: Double) {
        let size = Size2()
        let (window, _) = try makeFakeWindowOnDefaultDevice(size: 100) {
            ScrollView(both) { Column { Box().frame(width: px(size.w), height: px(size.h)) } }
                .defaultScrollAnchor(anchor).scrollIndicators(.hidden)
        }
        settleWindow(window)
        return try storedOffsets(window)
    }
    var o = try start(.bottomTrailing)
    #expect(o.x == 200 && o.y == 300, ".bottomTrailing \(o)")
    o = try start(.bottom)
    #expect(o.x == 100 && o.y == 300, ".bottom centres x \(o)")
    o = try start(.trailing)
    #expect(o.x == 200 && o.y == 150, ".trailing centres y \(o)")

    let size = Size2()
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100) {
        ScrollView(both) { Column { Box().frame(width: px(size.w), height: px(size.h)) } }
            .defaultScrollAnchor(.bottomTrailing).scrollIndicators(.hidden)
    }
    settleWindow(window)
    size.w = 500; size.h = 600
    settleWindow(window)
    o = try storedOffsets(window)
    #expect(o.x == 400 && o.y == 500, "growth follows on both axes \(o)")
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(50, 50), delta: pt(40, 0), phase: .none, momentumPhase: .none,
                                                    isPrecise: true, timestamp: 1)))
    settleWindow(window)
    o = try storedOffsets(window)
    try #require(o.x == 360 && o.y == 500, "the wheel moved x away from the end: \(o)")
    size.w = 700; size.h = 800
    settleWindow(window)
    o = try storedOffsets(window)
    #expect(o.x == 360 && o.y == 700, "x is released (probe S5), y keeps following: \(o)")
}

// MARK: - Z7

@MainActor private final class IDBox {
    var id: Int?
    var writes = 0
    var binding: Binding<Int?> { Binding(get: { self.id }, set: { self.id = $0; self.writes += 1 }) }
}

/// **Z7** (`XS-K`, probe `P1`). `scrollPosition(id:)` on a two-axis scroller follows the vertical axis and ignores a `dx`-only
/// wheel: rows 20 tall in 200 points, a `dy -250` wheel reads row 12 (offset 250 / 20, rounded to the row holding the top, 12) and a
/// `dx -100` after it leaves the binding and its write count alone. **Mutation:** `Window.scroll` reporting `didScroll` for the
/// cross slot too (the `!isCross` guard removed): the dx wheel reports offset 0, row 0.
@Test @MainActor func scrollPositionFollowsTheVerticalAxisAndIgnoresAHorizontalWheel() throws {
    let box = IDBox()
    let binding = box.binding
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200) {
        ProposalScrollView(both) {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000, id: \.self) { index in
                    Cell(key: index, log: CellLog(), width: 600, height: 20)
                }
            }.scrollTargetLayout()
        }.scrollPosition(id: binding).scrollIndicators(.hidden)
    }
    settleWindow(window)
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(100, 100), delta: pt(0, -250), phase: .none, momentumPhase: .none,
                                                    isPrecise: true, timestamp: 1)))
    settleWindow(window)
    let afterY = try #require(box.id, "the binding follows the vertical offset")
    #expect(afterY == 12, "offset 250 holds row 12 at the top: \(afterY)")
    let writes = box.writes
    platform.simulateInput(.scrollWheel(ScrollEvent(position: pt(100, 100), delta: pt(-100, 0), phase: .none, momentumPhase: .none,
                                                    isPrecise: true, timestamp: 2)))
    settleWindow(window)
    #expect(box.id == afterY && box.writes == writes, "a dx wheel does not touch the binding: \(String(describing: box.id)), \(box.writes) writes")
    let o = try storedOffsets(window)
    #expect(o.x == 100 && o.y == 250, "the dx moved x only: \(o)")
}

// MARK: - Z9

/// **Z9** (`XS-G`). A precise stream with phases (what SDL synthesizes for a touchpad, `TP-`) locks to its first event's axis for
/// the whole gesture: `.began` (-2, -8), then two `.changed` (-8, -2) are y-dominant by the lock (y 8 + 2 + 2 = 12... each event's
/// y component only) and `.ended`; a plain wheel (phaseless, `isPrecise` false) decides each event by itself: (-6, -8) moves y 8,
/// then (-8, -6) moves x 8. **Mutation:** the lock dropped from `dispatchScrollChain` (`lock ?? ` removed): the stream's later
/// events move x.
@Test @MainActor func aPreciseStreamLocksAndAPlainWheelDecidesEachEvent() throws {
    func event(_ dx: Float, _ dy: Float, _ phase: InputPhase, precise: Bool = true, timestamp: Double = 1) -> InputEvent {
        .scrollWheel(ScrollEvent(position: pt(50, 50), delta: pt(dx, dy), phase: phase, momentumPhase: .none,
                                 isPrecise: precise, timestamp: timestamp))
    }
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 100) {
        ScrollView(both) { Column { Box().frame(width: px(300), height: px(400)) } }.scrollIndicators(.hidden)
    }
    settleWindow(window)
    platform.simulateInput(event(-2, -8, .began))
    platform.simulateInput(event(-8, -2, .changed))
    platform.simulateInput(event(-8, -2, .changed))
    platform.simulateInput(event(0, 0, .ended))
    settleWindow(window)
    var o = try storedOffsets(window)
    #expect(o.y == 8 + 2 + 2 && o.x == 0, "locked to the first event's axis (vertical): \(o)")
    platform.simulateInput(event(-6, -8, .none, precise: false, timestamp: 2))
    platform.simulateInput(event(-8, -6, .none, precise: false, timestamp: 3))
    settleWindow(window)
    o = try storedOffsets(window)
    #expect(o.y == 12 + 8 && o.x == 8, "a phaseless wheel is decided per event: \(o)")
}
