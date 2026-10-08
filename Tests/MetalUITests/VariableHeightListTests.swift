import Testing
import Observation
import MetalUICore
import MetalUILayout
@testable import MetalUI

// Variable-height `List`, lane 2 (spec
// `docs/superpowers/specs/2026-10-08-variable-height-list-design.md` §3.3 and
// §5 tests 2.1–2.18; rulings `VL-A`…`VL-H`, `VL-O`, `VL-P`, `VL-R`). Headless:
// a `Window` over `Fakes.swift`'s platform, or a bare `Frame`, driven by
// `drawFrameIfNeeded`/`simulateTick` only — no sleeps.
//
// **Red-before** (record §82 §4): the three `rowContent:` initialisers first
// landed routed to the uniform path at `rowHeight` 24; every test below fails
// against that stub on a line its comment names.
//
// **Fixtures.** Rows are `VLeaf`s: a lowered leaf of a fixed height, or of
// `area / width` (the width-dependent stand-in for wrapping text — no `Text`
// fixture, TX-B), that logs when it is built and where it is placed. The
// scrolled fixture is a 200 × 200 window: an optional header strip, then a
// vertical `ScrollView` (indicators hidden) under a `ScrollViewReader`, whose
// content is a column of `model.width` holding the `List`. The patterned rows
// are `h(i) = [20, 40, 60, 80][i % 4]`, so `offset(of: 4k) = 200k` and the
// mean is exactly 50: row 50 starts at 2460 and is 60 tall. "On screen" is a
// row's layout-space y minus the scroller's content origin minus the offset
// that frame painted at (`activeScrollerFrame`, read in the leaf's prepaint).
// Every literal is derived in the test's comment before the run.

private func px(_ v: Float) -> Pixels { Pixels(v) }

private struct VItem: Identifiable, Hashable { let id: Int }

/// The patterned height of row id `id` (ids ≥ 0).
private func patterned(_ id: Int) -> Double { [20, 40, 60, 80][id % 4] }

/// What the rows did this frame.
@MainActor
private final class VLog {
    /// Row keys whose leaf was built (its `requestLayout` ran), in order.
    var built: [Int] = []
    /// Each built leaf's element id.
    var ids: [Int: GlobalElementID] = [:]
    /// Each placed leaf's layout-space bounds (prepaint).
    var bounds: [Int: Bounds<Pixels>] = [:]
    /// Each placed leaf's on-screen y inside a vertical scroller.
    var screenY: [Int: Double] = [:]
    /// Clears what one frame records (ids are kept: they do not change).
    func reset() {
        built = []
        bounds = [:]
        screenY = [:]
    }
}

/// A lowered leaf: `height` tall when given, else `area / width` (width the
/// offered one, else `naturalWidth`). Logs into `log`.
private struct VLeaf: Element {
    let key: Int
    var height: Double?
    var area: Double = 0
    var naturalWidth: Double = 100
    let log: VLog?
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log?.built.append(key)
        log?.ids[key] = id
        let height = height, area = area, natural = naturalWidth
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { proposal in
                if let height {
                    let width = proposal.width.map { $0.isFinite ? $0 : natural } ?? natural
                    return LayoutMeasurement(size: SizeD(width: width, height: height))
                }
                return AreaLeaf.measure(area: area, naturalWidth: natural, proposal)
            }
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {
        log?.bounds[key] = bounds
        if let scroller = pass.frame.activeScrollerFrame, scroller.axis == .vertical {
            log?.screenY[key] = Double(bounds.origin.y.value - scroller.contentOrigin.y.value) - scroller.offset
        }
    }

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// The data and per-id heights the rows read, observed so a write dirties the
/// window (and a write inside `withAnimation` carries its transaction).
@Observable @MainActor
private final class VModel {
    var items: [VItem]
    var heights: [Int: Double] = [:]
    var width: Float = 200

    init(count: Int) { items = (0..<count).map(VItem.init) }

    func height(_ id: Int) -> Double { heights[id] ?? patterned(id) }
}

/// Holds the reader's proxy.
@MainActor
private final class ProxyBox {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool {
        self.proxy = proxy
        return true
    }
}

private func column(width: Float? = nil, height: Float? = nil) -> Style {
    var style = Style()
    style.flexDirection = .column
    if let width { style.size.width = .length(.pixels(px(width))); style.flexShrink = 0 }
    if let height { style.size.height = .length(.pixels(px(height))); style.flexShrink = 0 }
    return style
}

/// The scrolled fixture, drawn until it asks for nothing (the cold frame
/// builds and measures every row, `MP-I`).
@MainActor
private func scrolledWindow(_ model: VModel, log: VLog, header: Float = 0,
                            estimate: Pixels? = nil, proxyBox: ProxyBox? = nil,
                            startsDisplayLink: Bool = false) throws -> (Window, FakePlatformWindow) {
    let (window, platform) = try makeFakeWindowOnDefaultDevice(size: 200, startsDisplayLink: startsDisplayLink) {
        Box(style: column(width: 200, height: 200)) {
            if header > 0 { Box(style: column(width: 200, height: header)) }
            ScrollViewReader { proxy in
                let _ = proxyBox?.keep(proxy)
                ScrollView {
                    Box(style: column(width: model.width)) {
                        List(model.items, estimatedRowHeight: estimate) { item in
                            VLeaf(key: item.id, height: model.height(item.id), log: log)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
    window.recordsElementBounds = true
    if !startsDisplayLink { _ = settle(window) }
    return (window, platform)
}

/// Draws while the window asks for a frame (at most `cap`); returns how many.
@MainActor
@discardableResult
private func settle(_ window: Window, cap: Int = 12) -> Int {
    var frames = 0
    while window.needsRedraw && frames < cap {
        window.drawFrameIfNeeded()
        frames += 1
    }
    return frames
}

/// Draws exactly one frame, dirty or not, after clearing the log.
@MainActor
private func drawOne(_ window: Window, _ log: VLog) {
    log.reset()
    window.setNeedsRedraw()
    window.drawFrameIfNeeded()
}

@MainActor
private func scrollerID(_ window: Window) throws -> GlobalElementID {
    try #require(window.lastScrollRegions.first, "no scroller").id
}

@MainActor
private func storedOffset(_ window: Window) throws -> Double {
    window.stateTable.peek(try scrollerID(window), as: ScrollState.self)?.offset ?? 0
}

@MainActor
private func setOffset(_ window: Window, _ offset: Double) throws {
    window.stateTable.withState(try scrollerID(window), initial: ScrollState()) { $0.offset = offset }
}

/// The list's id: a row leaf's grandparent (leaf → named row `Box` → list).
@MainActor
private func listID(_ log: VLog, row: Int = 0) throws -> GlobalElementID {
    let leaf = try #require(log.ids[row], "row \(row) was never built")
    return try #require(leaf.parent?.parent)
}

/// The list's laid-out height (needs `recordsElementBounds`).
@MainActor
private func listHeight(_ window: Window, _ log: VLog) throws -> Float {
    try #require(window.lastElementBounds[try listID(log)], "the list recorded no bounds").size.height.value
}

/// 300 patterned rows, settled, then scrolled so row 50 is on top at 2460 and
/// drawn once (bounded, every row measured by the cold frame: no adjustment).
@MainActor
private func rowFiftyOnTop(estimate: Pixels? = nil, startsDisplayLink: Bool = false) throws
    -> (Window, FakePlatformWindow, VModel, VLog) {
    let model = VModel(count: 300)
    let log = VLog()
    let (window, platform) = try scrolledWindow(model, log: log, estimate: estimate,
                                                startsDisplayLink: startsDisplayLink)
    if startsDisplayLink {
        platform.simulateTick(timestamp: 100)
        try #require(!window.needsRedraw, "control: the cold frame asks for nothing")
    }
    try setOffset(window, 2460)
    drawOne(window, log)
    try #require(log.screenY[50] == 0, "control: row 50 on top, got \(String(describing: log.screenY[50]))")
    try #require(!window.needsRedraw, "control: a measured list at rest asks for nothing")
    return (window, platform, model, log)
}

// MARK: - 2.1–2.4: sizing and windowing

/// **2.1 (`VL-B`, divergence 145).** Outside every scroller, rows of content
/// 20, 60 and 40 sit at y 0, 20 and 80, each exactly its content's height (no
/// inset, no floor), and the list answers 120. Red-before: the stub's rows are
/// 24 (y 0/24/48, height 72). Mutation: pin rows to the estimate.
@Test @MainActor
func aVariableListSizesEachRowToItsContent() throws {
    let log = VLog()
    let heights: [Double] = [20, 60, 40]
    var root = Box(style: column(width: 200, height: 400)) {
        List((0..<3).map(VItem.init)) { item in VLeaf(key: item.id, height: heights[item.id], log: log) }
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(400)), scaleFactor: 1,
                      recordsElementBounds: true)
    frame.render(&root)
    #expect(log.bounds[0]?.origin.y == px(0))
    #expect(log.bounds[1]?.origin.y == px(20))
    #expect(log.bounds[2]?.origin.y == px(80))
    #expect(log.bounds.mapValues(\.size.height.value) == [0: 20, 1: 60, 2: 40])
    let list = try #require(frame.elementBounds[try listID(log)])
    #expect(list.size.height == px(120))
}

/// **2.2 (`VL-B`).** A row is measured at the list's width: `area` 4000 rows
/// are 20 tall in a 200-wide list and 10 tall in a 400-wide one. Red-before:
/// 24 at both. Mutation: propose rows `(nil, nil)` (they read 40, the leaf's
/// natural 100 width).
@Test @MainActor
func aVariableRowIsMeasuredAtTheListsWidth() throws {
    for (width, expected) in [(Float(200), Float(20)), (Float(400), Float(10))] {
        let log = VLog()
        var root = Box(style: column(width: width, height: 400)) {
            List((0..<3).map(VItem.init)) { item in VLeaf(key: item.id, area: 4000, log: log) }
        }
        let frame = Frame(contentSize: Size(width: px(width), height: px(400)), scaleFactor: 1)
        frame.render(&root)
        #expect(log.bounds[0]?.size.height.value == expected, "width \(width)")
        #expect(log.bounds[1]?.origin.y.value == expected, "width \(width)")
        #expect(log.bounds[2]?.origin.y.value == 2 * expected, "width \(width)")
    }
}

/// **2.3 (`VL-C`, `VL-R` item 6; divergence 147 at the list level).** 100 rows,
/// a 30pt header so the viewport is 170: rows 0…7 alternate 40/20, the rest are
/// 100 (cold extent 4·40 + 4·20 + 92·100 = 9440). The content narrows 200 → 180
/// (fixed heights: nothing re-wraps) — every measurement is forgotten
/// (`VL-E` item 2) and the window's rows re-recorded. The window at offset 0:
/// row 5 (160…180) holds 170, so rows 0 ..< 5 + 1 + 2 = 0…7, sum 240, mean 30.
/// The list then answers measured + mean × rest = 240 + 92 · 30 = **3000**
/// (the anchor is row 0 at 0, so nothing adjusts). Red-before: 100 × 24 = 2400.
/// Mutation: omit `trailingExtent` (240).
@Test @MainActor
func aVariableListAnswersMeasuredPlusEstimatedExtent() throws {
    let model = VModel(count: 100)
    for id in 0..<100 { model.heights[id] = id < 8 ? (id % 2 == 0 ? 40 : 20) : 100 }
    let log = VLog()
    let (window, _) = try scrolledWindow(model, log: log, header: 30)
    let region = try #require(window.lastScrollRegions.first)
    try #require(region.bounds.size.height.value == 170, "control: a 170pt viewport")
    drawOne(window, log)
    let cold = try listHeight(window, log)
    try #require(cold == 9440, "control: every row measured, \(cold)")
    model.width = 180
    drawOne(window, log)
    settle(window)
    drawOne(window, log)
    #expect(Set(log.built) == Set(0...7), "the window: \(log.built.sorted())")
    let height = try listHeight(window, log)
    #expect(height == 3000, "\(height)")
}

/// **2.4 (`VL-F`).** 300 patterned rows (all measured), offset 3030: row 61
/// spans 3020…3060 and holds 3030; row 65 spans 3220…3260 and holds 3230, so
/// the window is 61 − 2 ..< 65 + 1 + 2 = **59…67**. Red-before (24): 123…135.
/// Mutation: window by division at the estimate 50 (58…66).
@Test @MainActor
func aVariableListWindowsByPrefixOffsets() throws {
    let model = VModel(count: 300)
    let log = VLog()
    let (window, _) = try scrolledWindow(model, log: log)
    try setOffset(window, 3030)
    drawOne(window, log)
    #expect(log.built == Array(59...67), "built \(log.built)")
    #expect(log.screenY[61] == -10)
    #expect(!window.needsRedraw)
}

// MARK: - 2.5–2.8: anchoring

/// **2.5a (`VL-G` item 1).** Row 50 on top (offset 2460, window 48…56: row 54
/// at 2660 holds the viewport's bottom); row 48 (overscan) grows by 200
/// through the model. In the frame of the change row 50 is placed at its
/// anchor offset and row 48 grows upward: row 50's on-screen y stays **0**.
/// Red-before: the stub never builds row 50 at that offset (y nil). Mutation:
/// place from `offset(of: first)` (row 50 at 200).
@Test @MainActor
func aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopInThatFrame() throws {
    let (window, _, model, log) = try rowFiftyOnTop()
    model.heights[48] = 220
    drawOne(window, log)
    try #require(log.built.contains(48), "control: row 48 is realised: \(log.built)")
    #expect(log.screenY[50] == 0)
}

/// **2.5b (`VL-G` item 2).** The same change: after its frame the stored offset
/// is 2460 + 200 = **2660** (`D = offset(of: 50) − 2460 = 200`), and the next
/// frame draws row 50 at **0** again, now at content y 2660. Mutation: skip
/// `noteScrollAnchorAdjustment` (offset 2460; row 48 now holds it and row 50
/// is at 200).
@Test @MainActor
func aRowAboveTheTopMeasuredAnewDoesNotMoveTheRowOnTopOnTheNextFrame() throws {
    let (window, _, model, log) = try rowFiftyOnTop()
    model.heights[48] = 220
    drawOne(window, log)
    let offset = try storedOffset(window)
    #expect(offset == 2660, "\(offset)")
    #expect(window.needsRedraw, "the adjustment asks for the next frame")
    log.reset()
    window.drawFrameIfNeeded()
    #expect(log.screenY[50] == 0)
    #expect(!window.needsRedraw)
}

/// **2.6 (`VL-E` item 2, `VL-G`).** `area` rows `[4000, 8000, 12000, 16000][i %
/// 4]` (20/40/60/80 at width 200), declared estimate 50, offset 2470 (row 50
/// on top at −10; window 48…56). The content narrows to 100: heights double.
/// Frame A places row 50 at its anchor (−10), forgets every measurement and
/// records rows 48…56 (40, 80, 120, 160, 40, 80, 120, 160, 40 = 840); then
/// `offset(of: 50) = 48 · 50 + 40 + 80 = 2520`, `D = 60`, stored 2530. Frame B
/// draws row 50 at 2520 − 2530 = **−10**. The extent is 840 + 291 · 50 =
/// **15390**. Red-before: the stub never realises row 50. Mutations: (a) skip
/// `forgetMeasurements` (unrealised rows keep their width-200 heights: 15420);
/// (b) skip the anchor (row 50 at +50 in frame A).
@Test @MainActor
func aWidthChangeKeepsTheRowOnTopAndForgetsEveryMeasurement() throws {
    let model = VModel(count: 300)
    let log = VLog()
    let areas: [Double] = [4000, 8000, 12000, 16000]
    let (window, _) = try makeFakeWindowOnDefaultDevice(size: 200) {
        ScrollView {
            Box(style: column(width: model.width)) {
                List(model.items, estimatedRowHeight: px(50)) { item in
                    VLeaf(key: item.id, area: areas[item.id % 4], log: log)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
    window.recordsElementBounds = true
    settle(window)
    try setOffset(window, 2470)
    drawOne(window, log)
    try #require(log.screenY[50] == -10, "control: row 50 on top at −10, got \(String(describing: log.screenY[50]))")
    try #require(log.bounds[50]?.size.height == px(60), "control: row 50 is 60 at width 200")
    model.width = 100
    drawOne(window, log)
    try #require(log.bounds[50]?.size.height == px(120), "control: row 50 is 120 at width 100")
    #expect(log.screenY[50] == -10, "frame A")
    let offset = try storedOffset(window)
    #expect(offset == 2530, "\(offset)")
    log.reset()
    window.drawFrameIfNeeded()
    #expect(log.screenY[50] == -10, "frame B")
    #expect(!window.needsRedraw)
    let height = try listHeight(window, log)
    #expect(height == 15390, "\(height)")
}

/// **2.7 (`VL-G` item 3, divergence 146).** Row 50 on top; a 150-tall row
/// (id 1000) inserted at index 0. The rebuild finds the anchor by id: id 50,
/// now index 51, is placed at its old 2460 (on screen **0**); the new row is
/// unrealised and counts as the mean 50, so `D = 50` and the stored offset
/// settles at **2510**, id 50 still at 0. Red-before: the stub never realises
/// row 50 there. Mutation: anchor by index across the rebuild (id 49 at 2460,
/// id 50 at 40).
@Test @MainActor
func anInsertionAboveTheViewportKeepsTheRowOnTop() throws {
    let (window, _, model, log) = try rowFiftyOnTop()
    model.heights[1000] = 150
    model.items.insert(VItem(id: 1000), at: 0)
    drawOne(window, log)
    #expect(log.screenY[50] == 0, "the frame of the insertion")
    #expect(!log.built.contains(1000), "the new row is above the window")
    settle(window)
    log.reset()
    drawOne(window, log)
    #expect(log.screenY[50] == 0, "settled")
    let offset = try storedOffset(window)
    #expect(offset == 2510, "\(offset)")
}

/// **2.7b (`VL-O` item 1).** Declared estimate 50. Arm 1: row 50 (on top)
/// removed — the first recorded id after it still present, id 51, takes its
/// place at 2460 (on screen **0**). Arm 2: row 50 removed **and** id 1000
/// inserted at 0 in one change — id 51 is at index 51 and is still the anchor
/// (on screen **0**), where index 50 holds id 49. Red-before: the stub never
/// realises id 51 there. Mutations: (a) prefer the id before (id 49 on top,
/// id 51 at 40 — arm 1); (b) fall back to `oldAnchorIndex` (index 50 = id 49 —
/// arm 2).
@Test @MainActor
func removingTheRowOnTopPutsTheNextRowInItsPlace() throws {
    do {
        let (window, _, model, log) = try rowFiftyOnTop(estimate: px(50))
        model.items.removeAll { $0.id == 50 }
        drawOne(window, log)
        #expect(log.screenY[51] == 0, "arm 1, the frame of the removal")
        settle(window)
        drawOne(window, log)
        #expect(log.screenY[51] == 0, "arm 1, settled")
    }
    do {
        let (window, _, model, log) = try rowFiftyOnTop(estimate: px(50))
        model.items.removeAll { $0.id == 50 }
        model.items.insert(VItem(id: 1000), at: 0)
        drawOne(window, log)
        #expect(log.screenY[51] == 0, "arm 2, the frame of the change")
        settle(window)
        drawOne(window, log)
        #expect(log.screenY[51] == 0, "arm 2, settled")
        let offset = try storedOffset(window)
        #expect(offset == 2510, "arm 2: D = the new row's estimate, 50: \(offset)")
    }
}

/// **2.7c (`VL-R` item 8; animation unmoved).** 2.7's insertion inside
/// `withAnimation`, driven by `simulateTick`: id 50's on-screen y is **0** at
/// every tick until the window asks for nothing (legacy animation interpolates
/// `Style` fields, not a parent layout's placement, so the rows snap with the
/// offset). Red-before: the stub never realises row 50 there. Mutation: skip
/// `noteScrollAnchorAdjustment` (the tick after the change reads 50).
@Test @MainActor
func anInsertionAboveTheViewportUnderWithAnimationKeepsTheRowOnTopEveryTick() throws {
    let (window, platform, model, log) = try rowFiftyOnTop(startsDisplayLink: true)
    withAnimation(.linear(duration: 0.3)) {
        model.heights[1000] = 150
        model.items.insert(VItem(id: 1000), at: 0)
    }
    var ticks = 0
    var timestamp = 100.0
    repeat {
        log.reset()
        timestamp += 0.05
        platform.simulateTick(timestamp: timestamp)
        ticks += 1
        #expect(log.screenY[50] == 0, "tick \(ticks)")
    } while window.needsRedraw && ticks < 20
    #expect(ticks == 2, "the change's frame and the adjusted one: \(ticks)")
}

/// **2.8 (`VL-E` item 3).** Declared estimate 50. A same-count change: id 1000
/// inserted at 0 and the last row dropped. `data.count` is unchanged, so only
/// a realised row can see it — index 48 now holds id 47 — and the rebuild
/// finds the anchor by id (id 50, index 51), placed at 2460: on screen **0**.
/// Red-before: the stub never realises row 50 there. Mutation: skip the
/// realised-id check (anchor index 50 = id 49 at 2460, id 50 at 40).
@Test @MainActor
func aSameCountDataChangeIsDetectedFromARealizedRow() throws {
    let (window, _, model, log) = try rowFiftyOnTop(estimate: px(50))
    var items = model.items
    items.removeLast()
    items.insert(VItem(id: 1000), at: 0)
    model.items = items
    drawOne(window, log)
    #expect(log.screenY[50] == 0)
    #expect(log.screenY[51] == 60, "the rows below follow their own heights")
    settle(window)
    drawOne(window, log)
    #expect(log.screenY[50] == 0, "settled")
    let offset = try storedOffset(window)
    #expect(offset == 2510, "\(offset)")
}

// MARK: - 2.9–2.11: scrollTo and settling

/// 10 patterned rows (sum 460) settled, then 300 (a count change: rows 0…9
/// keep their heights, the rest are unmeasured at the declared 30), settled.
@MainActor
private func expandedList(estimate: Pixels? = px(30)) throws -> (Window, VModel, VLog, ProxyBox) {
    let model = VModel(count: 10)
    let log = VLog()
    let box = ProxyBox()
    let (window, _) = try scrolledWindow(model, log: log, estimate: estimate, proxyBox: box)
    model.items = (0..<300).map(VItem.init)
    settle(window)
    return (window, model, log, box)
}

/// **2.9 (`VL-H`, `T-bottom`).** `scrollTo(150, anchor: .bottom)` onto an
/// unmeasured row (real 60, estimate 30; rows 0…9 sum 460). Frame A resolves
/// at the estimate: `offset(of: 150) = 460 + 140 · 30 = 4660`, so 4660 − (200 −
/// 30) = 4490, and carries a refinement. Frame B (anchor 144 at 4480, window
/// 142…153) records the window: `offset(of: 144) = 4560`, `D = 80`; the
/// refinement resolves `offset(of: 150) = 4820` exactly: (4820 − 80) − 140 =
/// 4600, + D = 4680. Frame C draws row 150 at 4820 − 4680 = **140**: its bottom
/// on the viewport's. Three frames. (The clamp does not bind: 9160 of content,
/// `VL-P` item 3.) Red-before: the stub lands its 24-tall slot, the
/// leaf at 176. Mutation: no refinement carried (row 150 at 250).
@Test @MainActor
func scrollToAnUnmeasuredRowLandsExactlyOnceMeasured() throws {
    let (window, _, log, box) = try expandedList()
    let proxy = try #require(box.proxy)
    proxy.scrollTo(150, anchor: .bottom)
    let frames = settle(window)
    drawOne(window, log)
    #expect(log.screenY[150] == 140, "row 150's bottom on the viewport's: \(String(describing: log.screenY[150]))")
    #expect(frames == 3, "frames to settle: \(frames)")
}

/// **2.10 (`VL-H`).** A refined reveal never refines again. Frame A resolves
/// row 150 at its estimate and carries one refinement (one pending request
/// after it). The offset is then put back to 0 (a user scrolling away), so in
/// frame B the target is still unmeasured: the refinement resolves once more
/// and carries **nothing** (zero pending). Frame C lands at 4490 and records
/// rows 142…153 (`D = 80`, stored 4570); frame D (anchor 144, window 142…150)
/// asks for nothing: **two** frames after B. Red-before: the stub carries
/// nothing (zero pending after A). Mutation: drop the `refined` guard (one
/// pending after B).
@Test @MainActor
func aRefinedRevealNeverRefinesAgain() throws {
    let (window, _, _, box) = try expandedList()
    let proxy = try #require(box.proxy)
    proxy.scrollTo(150, anchor: .bottom)
    window.drawFrameIfNeeded()
    #expect(window.scrollRequests.pending.count == 1, "frame A carries one refinement")
    try setOffset(window, 0)
    window.drawFrameIfNeeded()
    #expect(window.scrollRequests.pending.count == 0, "frame B carries nothing")
    let frames = settle(window)
    #expect(frames == 2, "frames after B: \(frames)")
    let offset = try storedOffset(window)
    #expect(offset == 4570, "\(offset)")
}

/// **2.11 (`VL-F`, `VL-G`).** A jump to 5070 settles without input. Rows 10…
/// start at `460 + 30 · (i − 10)` while unmeasured, so frame A's anchor is row
/// 163 at 5050 (on screen −20) and its window 161…172 (5270 lies in row 170);
/// it records its rows — rows 161 and 162 are 40 + 60, not 2 · 30 — so `D =
/// 40` (stored 5110) and it asks for one frame; frame B (anchor 163 at 5090,
/// on screen −20, window 161…169) asks for nothing. Exactly **one** frame
/// asks. Red-before:
/// the stub never realises row 163 there. Mutation: request a frame whenever
/// `D` is computed (every frame asks).
@Test @MainActor
func aVariableListSettlesWithoutInput() throws {
    let (window, _, log, _) = try expandedList()
    try setOffset(window, 5070)
    var asking = 0
    var frames = 0
    window.setNeedsRedraw()
    repeat {
        log.reset()
        window.drawFrameIfNeeded()
        frames += 1
        #expect(log.screenY[163] == -20, "frame \(frames)")
        if window.needsRedraw { asking += 1 }
    } while window.needsRedraw && frames < 10
    #expect(asking == 1, "frames asking for another: \(asking)")
}

// MARK: - 2.12–2.15: what does not move (`VL-J`)

@MainActor
private final class Selection {
    var multi: Set<Int> = []
    var writes: [Set<Int>] = []
    var binding: Binding<Set<Int>> {
        Binding(get: { self.multi }, set: { self.multi = $0; self.writes.append($0) })
    }
}

/// **2.12 (`DD-Z`).** A selectable variable list (rows alternate 20/30, so
/// rows 0…3 fill the 100pt viewport at 0, 20, 50, 70) inside a scroller: click
/// 0 → [0]; ⌘-click 2 → [0, 2]; ⇧-click 3 → [2, 3] (from the anchor 2); ⇧↓ →
/// [2, 3, 4] — the uniform list's sets. Row 3's click target is 30 tall. Red-before: the stub's rows are 24. Mutation: the
/// variable branch skips `rowClick` (no click target).
@Test @MainActor
func selectionAndShiftRangesAreUnchangedInAVariableList() throws {
    let model = Selection()
    let (window, platform) = try controlWindow(size: 100) {
        Box(style: column(width: 100, height: 100)) {
            ScrollView {
                Box(style: column(width: 100)) {
                    List((0..<10).map(VItem.init), selection: model.binding) { item in
                        VLeaf(key: item.id, height: item.id % 2 == 0 ? 20 : 30, log: nil)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    _ = settle(window)
    controlRedraw(window)
    let list = GlobalElementID.child(of: controlID([0, 0, 0]), at: 0, name: nil)
    func row(_ i: Int) -> GlobalElementID { GlobalElementID.child(of: list, at: 0, name: ElementID("\(i)")) }
    func click(_ i: Int, _ modifiers: Modifiers = []) throws {
        let hitbox = try #require(window.lastHitboxes.first { $0.id == row(i) && $0.handlers.onClick != nil },
                                  "row \(i) registered no click target")
        let point = controlCentre(hitbox.bounds)
        platform.simulateInput(.mouseDown(MouseEvent(position: point, modifiers: modifiers)))
        platform.simulateInput(.mouseUp(MouseEvent(position: point, modifiers: modifiers)))
        controlRedraw(window)
    }
    let target = try #require(window.lastHitboxes.first { $0.id == row(3) && $0.handlers.onClick != nil },
                              "row 3 registered no click target")
    #expect(target.bounds.size.height == px(30), "a content-sized row")
    try click(0)
    try click(2, ControlKeys.selectionToggleModifier())
    try click(3, .shift)
    window.focus(list)
    controlRedraw(window)
    platform.simulateInput(controlKey(TextEditing.downArrow, .shift))
    controlRedraw(window)
    #expect(model.writes == [[0], [0, 2], [2, 3], [2, 3, 4]], "\(model.writes)")
}

private struct ExcursionItem: Identifiable { let id: String }

/// A 20-tall lowered leaf with one `@State` (`$state0`) that counts its
/// productions — `TombstoneTests.ExcursionRow` with a height.
private struct StatefulVRow: Element {
    @State var count = 0
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        count += 1
        let node = pass.lowerLegacyLeaf(Style(), declared: Style(), site: .box) {
            pass.frame.requestNativeLeaf { p in LayoutMeasurement(size: SizeD(width: p.width ?? 100, height: 20)) }
        }
        return (node, ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                           pass: inout PrepaintPass) {}
    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                        prepaint: inout Void, pass: inout PaintPass) {}
}

/// **2.13 (TB-AH).** `TombstoneTests`' excursion over a variable list of
/// twelve 20-tall rows in a 20pt viewport, the table held over its sweep
/// threshold. Windows (`VL-F`: `index(containing: top) − 2 ..<
/// index(containing: top + 20) + 3`): offset 100 → 3…8, 0 → 0…3, 60 → 1…6,
/// 140 → 5…10. Rows 4 (short) and 7 (long) are built at 100 twice (count 3),
/// both leave for two frames at 0; at 60 row 4 returns within the bound (4),
/// row 7 is still out and is reaped; at 140 row 7 returns fresh (1).
/// Red-before: the stub's 24pt windows never build row 7 at 100. Mutation:
/// drop the row's `.id(datum.id)` in the variable branch (state follows the
/// slot: the short half reddens).
@Test @MainActor
func aVariableListRowsStateSurvivesABoundedExcursionButNotALongerOne() throws {
    let data = (0..<12).map { ExcursionItem(id: "row\($0)") }
    let table = StateTable()
    let paddingIDs = (0..<260).map {
        GlobalElementID.child(of: nil, at: 10_000 + $0, name: ElementID("pad\($0)"))
    }
    for id in paddingIDs { table.write(id, 0) }
    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data) { _ in StatefulVRow() }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    func renderFrame(offset: Double?) {
        for id in paddingIDs { table.mark(id) }
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        let frame = Frame(contentSize: Size(width: px(100), height: px(20)), scaleFactor: 1, stateTable: table)
        frame.render(&tree)
    }
    let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
    func slotID(_ index: Int) -> GlobalElementID {
        let boxID = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[index].id))
        let rowID = GlobalElementID.child(of: boxID, at: 0, name: nil)
        return GlobalElementID.child(of: rowID, at: 0, name: ElementID("$state0"))
    }
    let shortSlot = slotID(4), longSlot = slotID(7)

    renderFrame(offset: nil)
    renderFrame(offset: 100)
    renderFrame(offset: 100)
    #expect(table.peek(shortSlot, as: Int.self) == 3)
    #expect(table.peek(longSlot, as: Int.self) == 3)
    renderFrame(offset: 0)
    renderFrame(offset: 0)
    renderFrame(offset: 60)
    #expect(table.isLive(shortSlot), "the short row is built this frame")
    #expect(table.peek(shortSlot, as: Int.self) == 4, "a two-generation excursion keeps @State")
    renderFrame(offset: 140)
    #expect(table.isLive(longSlot), "the long row is built this frame")
    #expect(table.peek(longSlot, as: Int.self) == 1, "a three-generation excursion does not")
}

/// **2.14 (`IX-I`).** A focused row of a variable list (twelve 20-tall
/// focusable rows, 20pt viewport) windowed out for two frames (offset 0 →
/// 0…3; it is built at 100 → 3…8 and back at 80 → 2…7) still holds focus; and
/// a selectable variable list takes focus. Its row `Box` is 20 tall.
/// Red-before: the stub's row is 24. Mutation: the variable branch drops the
/// list's `isFocusable` composition (the list refuses focus).
@Test @MainActor
func aFocusedVariableRowKeepsFocusOutOfWindow() throws {
    let data = (0..<12).map { ExcursionItem(id: "row\($0)") }
    let table = StateTable()
    var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
        List(data) { _ in Box(style: column(height: 20)).focusable() }
    }
    let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))
    let listID = GlobalElementID.child(of: scrollerID, at: 0, name: nil)
    let boxID = GlobalElementID.child(of: listID, at: 0, name: ElementID(data[4].id))
    let rowID = GlobalElementID.child(of: boxID, at: 0, name: nil)
    var focus: GlobalElementID?
    var lastFrame: Frame?
    func renderFrame(offset: Double?) {
        if let offset {
            let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
            table.write(scrollerID, ScrollState(offset: offset, lastScrollTime: current.lastScrollTime,
                                                viewportExtent: current.viewportExtent))
        }
        let frame = Frame(contentSize: Size(width: px(100), height: px(20)), scaleFactor: 1, stateTable: table,
                          focusedElement: focus, recordsElementBounds: true)
        frame.render(&tree)
        focus = frame.focusedElement
        lastFrame = frame
    }
    renderFrame(offset: nil)
    focus = rowID
    renderFrame(offset: 100)
    try #require(focus == rowID, "control: the row takes focus")
    #expect(lastFrame?.elementBounds[boxID]?.size.height == px(20), "a content-sized row")
    renderFrame(offset: 0)
    renderFrame(offset: 0)
    renderFrame(offset: 80)
    #expect(focus == rowID, "focus survives a two-frame excursion")

    let model = Selection()
    let (window, _) = try controlWindow(size: 100) {
        Box(style: column(width: 100, height: 100)) {
            ScrollView {
                Box(style: column(width: 100)) {
                    List((0..<10).map(VItem.init), selection: model.binding) { item in
                        VLeaf(key: item.id, height: 20, log: nil)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
    _ = settle(window)
    let list = GlobalElementID.child(of: controlID([0, 0, 0]), at: 0, name: nil)
    window.focus(list)
    controlRedraw(window)
    #expect(window.focusedElement == list, "a selectable variable list takes focus")
}

/// **2.15 (AB-L, AB-X).** 40 patterned rows in a 200pt scroller, two frames
/// through the differential harness: the table record's `logicalCount` is 40
/// and the realised rows carry indices 0…6 (row 4 at 200 holds the viewport's
/// bottom: 0 ..< 4 + 1 + 2). Red-before: the stub's 24pt window is 0…10.
/// Mutation: drop `logicalIndex` in the variable branch (no row records).
@Test @MainActor
func aVariableListPublishesItsLogicalCountAndRealizedRowIndices() throws {
    var column = Style()
    column.flexDirection = .column
    column.size = Size(width: .length(.pixels(px(200))), height: .length(.pixels(px(200))))
    let frame = LayoutDifferential.render(width: 200, height: 200, stateTable: StateTable(), frames: 2) {
        Box(style: column) {
            Box {
                ScrollView(.vertical) {
                    List((0..<40).map(VItem.init)) { item in VLeaf(key: item.id, height: patterned(item.id), log: nil) }
                }
            }
            .flexGrow(1).flexBasis(px(0)).cssMinHeight(px(0))
        }
    }
    let tables = frame.axEmissions.filter { $0.declared.logicalCount != nil }
    try #require(tables.count == 1, "exactly one table record")
    #expect(tables[0].declared.logicalCount == 40)
    let rows = frame.axEmissions.compactMap { $0.declared.logicalIndex }.sorted()
    #expect(rows == Array(0...6), "\(rows)")
}

// MARK: - 2.16–2.18

/// **2.16 (`VL-D`, `DD-F` item 1).** Outside every scroller a variable list
/// mints no `StateTable` entry over two frames (no index, no origin), and its
/// rows are content-sized (row 1 at 20). Red-before: the stub's row 1 is at
/// 24. Mutation: `withState` in `requestLayout` (an entry appears).
@Test @MainActor
func aVariableListOutsideAScrollerMintsNoStateEntry() throws {
    let log = VLog()
    let table = StateTable()
    var root = Box(style: column(width: 200, height: 400)) {
        List((0..<3).map(VItem.init)) { item in VLeaf(key: item.id, height: 20 + 40 * Double(item.id), log: log) }
    }
    for _ in 0..<2 {
        let frame = Frame(contentSize: Size(width: px(200), height: px(400)), scaleFactor: 1, stateTable: table)
        frame.render(&root)
    }
    #expect(log.bounds[1]?.origin.y == px(20))
    let list = try listID(log)
    #expect(table.peek(list, as: ListOrigin.self) == nil)
    #expect(!table.ids.contains(list), "no entry at the list's id")
}

/// **2.17 (`VL-B`; the nil-width path).** In a horizontal `ScrollView` a
/// variable list is offered no width: it takes the widest row's natural width
/// (rows of `area` 4000, natural widths 100 and 400 → 400) and measures every
/// row at it: 10 tall each, at y 0 and 10. Red-before: 24-tall rows.
/// Mutation: measure heights at `(nil, nil)` (row 0 reads 40).
@Test @MainActor
func aVariableListInAHorizontalScrollerMeasuresEveryRowAtItsWidestWidth() throws {
    let log = VLog()
    let natural: [Double] = [100, 400]
    var root = Box(style: column(width: 200, height: 200)) {
        ScrollView(.horizontal) {
            List((0..<2).map(VItem.init)) { item in
                VLeaf(key: item.id, area: 4000, naturalWidth: natural[item.id], log: log)
            }
        }
    }
    let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1)
    frame.render(&root)
    #expect(log.bounds[0]?.size.height == px(10))
    #expect(log.bounds[1]?.size.height == px(10))
    #expect(log.bounds[1]?.origin.y == (log.bounds[0].map { $0.origin.y + px(10) }))
}

/// **2.18 (spec §3.1, `VL-R` item 2).** `estimatedRowHeight: 0` and `-5` are
/// clamped to "not declared": after 10 patterned rows (sum 460, mean 46) grow
/// to 100, the extent is 460 + 90 · 46 = **4600** for nil, 0 and −5 alike.
/// Red-before: the stub answers 100 × 24 = 2400. Mutation: drop the clamp (a
/// declared 0 makes every unmeasured row 0: 460).
@Test @MainActor
func aNonPositiveEstimateIsTreatedAsUndeclared() throws {
    for estimate in [nil, px(0), px(-5)] as [Pixels?] {
        let model = VModel(count: 10)
        let log = VLog()
        let (window, _) = try scrolledWindow(model, log: log, estimate: estimate)
        model.items = (0..<100).map(VItem.init)
        settle(window)
        drawOne(window, log)
        let height = try listHeight(window, log)
        #expect(height == 4600, "estimate \(String(describing: estimate)): \(height)")
    }
}
