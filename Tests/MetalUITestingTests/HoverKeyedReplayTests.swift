import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
#if canImport(Darwin)
import MetalUITestSupport
#endif
import Testing

// Record 442 (`RK-AR`): a retained occurrence is keyed on **what its paint reads of the hover**, not refused whenever the pointer is under it. The paint
// records the element ids it asked `isHovered` about (its readers, nested replays included) and which of them was hovered; it replays while that answer is the
// same, and the prepaint of an occurrence that is not grafted runs only where a reader could become hovered. The fixture is Alloy's long reply
// (`AlloyTranscriptFixture.swift`): 60 blocks in a lazy stack, the pointer resting over a fence's horizontal scroller while the transcript wheels. Counts are
// work, never time.

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read; the differential runs under it"

private func sum(_ frames: [FrameWork], _ key: KeyPath<FrameWork, Int>) -> Int { frames.reduce(0) { $0 + $1[keyPath: key] } }

/// What a step costs: the work of its frames, redone attempts included.
private struct HoverStepWork: Equatable, CustomStringConvertible {
    var requests: Int, prepaints: Int, paints: Int, redos: Int
    init(_ frames: [FrameWork]) {
        requests = sum(frames, \.elementRequests) + sum(frames, \.redoneElementRequests)
        prepaints = sum(frames, \.elementPrepaints) + sum(frames, \.redoneElementPrepaints)
        paints = sum(frames, \.elementPaints)
        redos = sum(frames, \.retainedRedos)
    }
    var description: String { "requests \(requests) prepaints \(prepaints) paints \(paints) redos \(redos)" }
}

/// The paint-miss lines of a trace and the reasons each names.
private func paintMissReasons(_ lines: [String]) -> [[String]] {
    lines.filter { $0.hasPrefix("retained paint miss") }.compactMap(traceReasons)
}

/// No redo of a step, or off Darwin only one with a cause that is not the pointer. On the portable text system's platforms the fences' Copy icon is a Lucide path,
/// which a moved paint record does not list (`unlistedKind:path`, `FenceTranslationTests`), so a row holding one refuses to move and a grafted one is redone whatever
/// the pointer does; macOS holds the strict count (no redo at all).
private func expectNoPointerRedo(_ frames: [FrameWork], _ step: Int) {
    let redos = sum(frames, \.retainedRedos), redone = sum(frames, \.redoneElementRequests)
    #if canImport(Darwin)
    #expect(redos == 0 && redone == 0, "step \(step): redos \(redos), redone requests \(redone)")
    #else
    var refused: [String: Int] = [:]
    for f in frames { refused.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +) }
    #expect((redos == 0 && redone == 0) || refused["unlistedKind:path", default: 0] > 0, "step \(step): redos \(redos), redone requests \(redone) with no path refusal: \(refused)")
    #endif
}

/// No redo line of a trace names the pointer or the hover.
private func redoLinesNameNoPointer(_ lines: [String]) -> Bool {
    !lines.contains { $0.contains("retained redo requested") && ($0.contains("pointerIn") || $0.contains("hover") || $0.contains("press")) }
}

// MARK: 1 - Alloy's case

/// **1** The pointer rests over a fence's scroller while the transcript wheels, graft on: no redo in any step, none for `pointerInMovedLedger`, no paint miss
/// names the hover or a press, and the window equals the retention-off one after each step. On master: 6 redos in 20 steps and 12 `pointerInMovedLedger`.
/// **Mutation:** the old rule at the prepaint (the pointer over any ledger hitbox, the predictor kept for a grafted occurrence): redos and `pointerInMovedLedger`.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFenceScrolledUnderARestingPointerReplaysWithNoRedo() throws {
    let pair = try atLongReplyPair(graft: true)
    let point = atRestingPoint(pair)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    var overFence = 0
    for step in 0..<20 {
        atRestingWheel(pair, at: point, dy: 40)
        let f = pair.on.frameWork
        expectNoPointerRedo(f, step)
        if pair.on.window.lastHitboxes.last(where: { $0.opaque && $0.contains(point) })?.scroll == .horizontal { overFence += 1 }
        try pair.compare("step \(step)")
    }
    RetainedTrace.sink = nil
    #expect(overFence >= 5, "set up: the pointer is over a horizontal scroller on \(overFence) of 20 steps")
    #expect(!lines.contains { $0.contains("pointerInMovedLedger") }, "no line names the moved ledger: \(lines.filter { $0.contains("pointerInMovedLedger") }.prefix(2))")
    #expect(redoLinesNameNoPointer(lines), "no redo names the pointer: \(lines.filter { $0.contains("retained redo requested") }.prefix(2))")
    let reasons = paintMissReasons(lines).flatMap { $0 }
    #expect(!reasons.contains("hover") && !reasons.contains("press") && !reasons.contains("pointer"), "no paint miss names the pointer: \(Set(reasons))")
}

/// **2** A pointer resting over the fences costs, per step, what one in the inset costs (requests with the redone ones, prepaints with the redone ones, paints).
/// Master: the graft refused every occurrence the pointer was over, 881 requests (with 253 redone) over 20 steps against 236.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aRestingPointerOverFencesCostsWhatAPointerInTheInsetCosts() throws {
    let over = try atLongReplyPair(graft: true), inset = try atLongReplyPair(graft: true)
    let point = atRestingPoint(over), away = pt(4, 300)
    for step in 0..<20 {
        atRestingWheel(over, at: point, dy: 40); atRestingWheel(inset, at: away, dy: 40)
        let a = HoverStepWork(over.on.frameWork), b = HoverStepWork(inset.on.frameWork)
        #expect(a == b, "step \(step): over a fence \(a) against the inset \(b)")
    }
    try over.compare("over a fence")
}

// MARK: 2 - equality with a fresh window

/// **3** The long reply with a reader, a link cursor and a help on blocks of every kind equals the retention-off window after each of 20 resting wheel steps,
/// graft off and on. Runs under verify mode: no counts.
@Test(arguments: [false, true]) @MainActor func theLongReplyEqualsAFreshWindowAtEveryRestingWheelStep(graft: Bool) throws {
    var options = ATOptions()
    for index in 0..<60 {
        switch index % 4 { case 1: options.readers.insert(index); case 2: options.cursors.insert(index); case 3: options.helps.insert(index); default: break }
    }
    let pair = try atLongReplyPair(graft: graft, options: options)
    for point in [atRestingPoint(pair), pt(60, 300)] {
        for step in 0..<10 {
            atRestingWheel(pair, at: point, dy: step.isMultiple(of: 3) ? -24 : 40)
            try pair.compare("point \(point.y.value) step \(step)")
        }
    }
}

// MARK: 3 - the readers

/// One row: a reader (an opaque tap, a hover background, an `onHover` that logs) and a `Button` beside it, which reads no hover. `covered` lays a later opaque
/// registration over the reader.
private struct HKRow: Component, @MainActor Equatable {
    let index: Int
    let log: HarnessLog
    let covered: Bool
    var content: some ElementGroup {
        let log = self.log, index = self.index
        HStack(spacing: Pixels(0)) {
            if covered {
                ZStack {
                    Text("reader \(index)").frame(width: Pixels(120), height: Pixels(18)).hoverBackground(.accent).onTapGesture {}
                        .onHover { log.add("hover \(index) \($0)") }
                    Color.clear.frame(width: Pixels(120), height: Pixels(18)).onTapGesture {}
                }
            } else {
                Text("reader \(index)").frame(width: Pixels(120), height: Pixels(18)).hoverBackground(.accent).onTapGesture {}
                    .onHover { log.add("hover \(index) \($0)") }
            }
            Button("b") {}.frame(width: Pixels(40), height: Pixels(18))
        }
    }
    static func == (l: HKRow, r: HKRow) -> Bool { l.index == r.index && l.log === r.log && l.covered == r.covered }
}

private struct HKList: Component {
    let log: HarnessLog
    let covered: Bool
    var content: some ElementGroup {
        let log = self.log, covered = self.covered
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(0)) {
                ForEach(0..<30, id: \.self) { HKRow(index: $0, log: log, covered: covered).equatable() }
            }
        }
    }
}

/// Thirty reader rows of 18 points in a 200 point window: the pointer at `hkPoint` is over row 5; a wheel of -18 puts row 6 there.
@MainActor private func hkPair(graft: Bool, covered: Bool = false) throws -> RPPair<some Element> {
    try RPPair(size: sz(200, 200), scale: 1, warm: 4, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { HKList(log: side.log, covered: covered) }
    }
}
private let hkPoint = pt(50, 99)

/// **4** One step moves the hovered reader out and the next one in: both logs end `hover 5 false`, `hover 6 true`, in that order, the scene equals the
/// retention-off one, and both rows' paint misses name `hover`. Without a graft no redo; with one exactly one, at `paintRecord`, for the arriving row (the
/// move is unknown at build, so nothing exact can refuse the graft). **Mutations:** `hoverMoved` forced false (the scene differs); the moved-hitbox predictor
/// removed (the row arriving is redone, graft off and on).
@Test(.enabled(if: !rsVerifying, verifyNote), arguments: [false, true]) @MainActor
func aHoveredRowMovingAwayFiresHoverFalseAndTheRowArrivingFiresHoverTrue(graft: Bool) throws {
    let pair = try hkPair(graft: graft)
    for w in [pair.on, pair.off] { w.hover(at: hkPoint) }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.onSide.log.entries.last == "hover 5 true", "set up: row 5 is hovered: \(pair.onSide.log.entries)")
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: hkPoint, byDeltaX: 0, deltaY: -18) }
    RetainedTrace.sink = nil
    let f = pair.on.frameWork
    #expect(pair.onSide.log.entries.suffix(2) == ["hover 5 false", "hover 6 true"], "on: \(pair.onSide.log.entries.suffix(3))")
    #expect(pair.offSide.log.entries.suffix(2) == ["hover 5 false", "hover 6 true"], "off: \(pair.offSide.log.entries.suffix(3))")
    #expect(paintMissReasons(lines).filter { $0.contains("hover") }.count >= 2, "the two rows miss for hover: \(paintMissReasons(lines))")
    #expect(sum(f, \.retainedRedos) == (graft ? 1 : 0), "redos \(sum(f, \.retainedRedos)) (graft \(graft))")
    if graft { #expect(lines.contains { $0.contains("paintRecord") || $0.contains("redo") }, "the redo is named: \(lines.filter { $0.contains("redo") }.prefix(2))") }
    try pair.compare("moved")
}

/// **4b** The pointer leaves a hovered reader between frames (graft on): the frame it leaves in builds the row (a record painted with a reader hovered is no
/// graft's to stand on even where the ledger's hitbox is no longer under the pointer), runs its prepaint, repaints it once and redoes nothing; `hover 5 false`
/// fires and the scene equals the retention-off one. **Mutation:** the graft guards on `recordHover.hovered` removed (`graftedPrepaint` redo).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aHoveredReaderThePointerLeavesIsBuiltAndNotGrafted() throws {
    let pair = try hkPair(graft: true)
    for w in [pair.on, pair.off] { w.hover(at: hkPoint) }
    for _ in 0..<3 { pair.redraw() }
    #expect(pair.onSide.log.entries.last == "hover 5 true", "set up: row 5 is hovered: \(pair.onSide.log.entries)")
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.hover(at: pt(190, 190)) }
    let f = pair.on.frameWork
    #expect(sum(f, \.retainedRedos) == 0, "the frame the pointer leaves in redoes nothing: \(sum(f, \.retainedRedos))")
    #expect(pair.onSide.log.entries.last == "hover 5 false" && pair.offSide.log.entries.last == "hover 5 false", "hover 5 false fired")
    try pair.compare("left the reader")
}

/// **5** The pointer rests on a reader: five redraws, and its record is hit every frame (master dropped it under the pointer), while its prepaint runs
/// (`pointerInLedger`), the log is unchanged and the window equals the retention-off one. **Mutations:** the store rule restored to refuse a hovered
/// element under the occurrence (misses); the reader filter widened to any ledger hitbox (the button part: its row's prepaint runs under the pointer).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aRestingPointerOverAReaderReplaysItsPaint() throws {
    let pair = try hkPair(graft: false)
    for w in [pair.on, pair.off] { w.hover(at: hkPoint) }
    for _ in 0..<3 { pair.redraw() }
    let logged = pair.onSide.log.entries
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    pair.frames = []
    for _ in 0..<5 { pair.redraw() }
    RetainedTrace.sink = nil
    for (step, f) in pair.frames.enumerated() { #expect(f.retainedMisses == 0 && f.retainedHits >= 1, "frame \(step): misses \(f.retainedMisses), hits \(f.retainedHits)") }
    #expect(lines.contains { $0.contains("pointerInLedger") }, "the prepaint of the hovered row runs for the pointer: \(lines.prefix(2))")
    #expect(pair.onSide.log.entries == logged, "nothing fired: \(pair.onSide.log.entries.suffix(2))")
    #expect(pair.on.window.testingRecordHovers().contains { $0.reads.hovered != nil }, "a record holds the reader it was painted with hovered")
    try pair.compare("resting on a reader")
    // The pointer moves onto the row's button, which reads no hover: one frame leaves the reader (its record misses once, `hover`), then every frame
    // replays with the prepaint of every row, the button's included, exactly as with the pointer away.
    let away = try hkPair(graft: false)
    away.redraw()
    let button = pair.on.window.lastHitboxes.last { $0.bounds.origin.x.value >= 119 && $0.bounds.origin.y.value <= 99 && 99 < $0.bounds.origin.y.value + $0.bounds.size.height.value }
    let onButton = try #require(button.map { pt($0.bounds.origin.x.value + $0.bounds.size.width.value / 2, 99) }, "set up: the row's button")
    for w in [pair.on, pair.off] { w.hover(at: onButton) }
    for _ in 0..<2 { pair.redraw() }
    pair.frames = []
    for _ in 0..<3 { pair.redraw() }
    for (step, f) in pair.frames.enumerated() {
        #expect(f.retainedMisses == 0 && f.retainedPrepaintHits == away.frames.last?.retainedPrepaintHits,
                "on the button, frame \(step): misses \(f.retainedMisses), prepaint hits \(f.retainedPrepaintHits) against \(String(describing: away.frames.last?.retainedPrepaintHits)) with the pointer away")
    }
    try pair.compare("resting on the button")
}

/// **6** A later opaque registration covers the reader: the reader is not hovered, the paint hits, and a wheel that brings every row under the pointer makes
/// no redo (graft on; the arriving row's answer is the same) and equals the retention-off window. **Mutation:** the moved-hitbox predictor kept for grafted occurrences (a redo).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aReaderCoveredByALaterRegistrationIsNotHoveredAndReplays() throws {
    let pair = try hkPair(graft: true, covered: true)
    for w in [pair.on, pair.off] { w.hover(at: hkPoint) }
    for _ in 0..<3 { pair.redraw() }
    for step in 0..<6 {
        atRestingWheel(pair, at: hkPoint, dy: -18)
        let f = pair.on.frameWork
        #expect(sum(f, \.retainedRedos) == 0, "step \(step): redos \(sum(f, \.retainedRedos))")
        try pair.compare("covered step \(step)")
    }
    #expect(!pair.onSide.log.entries.contains { $0.hasPrefix("hover") && $0.hasSuffix("true") }, "no reader was hovered: \(pair.onSide.log.entries)")
}

/// The centre of the first opaque hitbox of the last frame (the reader, or the element, the fixture holds alone).
@MainActor private func hkCentre(_ pair: RPPair<some Element>) -> Point<Pixels> {
    guard let box = pair.on.window.lastHitboxes.first(where: { $0.opaque }) else { return pt(100, 50) }
    return pt(box.bounds.origin.x.value + box.bounds.size.width.value / 2, box.bounds.origin.y.value + box.bounds.size.height.value / 2)
}

private struct HKInner: Component, @MainActor Equatable {
    let log: HarnessLog
    var content: some ElementGroup { HKRow(index: 0, log: log, covered: false) }
    static func == (l: HKInner, r: HKInner) -> Bool { l.log === r.log }
}

private struct HKOuter: Component, @MainActor Equatable {
    let counter: Int
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            HKInner(log: log).equatable()
            Text("n \(counter)")
        }
    }
    static func == (l: HKOuter, r: HKOuter) -> Bool { l.counter == r.counter && l.log === r.log }
}

/// **7** An outer occurrence holds an inner one with a reader. The counter changes (the outer misses, the inner hits), then the pointer moves onto the
/// reader: the outer's record must know it, so it misses for `hover` and the window equals the retention-off one. **Mutation:** the nested readers
/// not appended (the outer replays the unhovered background).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aNestedReaderKeepsItsOuterOccurrenceHonest() throws {
    let pair = try RPPair(size: sz(200, 100), accessibility: false) { side in
        VStack(spacing: 0) { HKOuter(counter: Int(side.inputs.offset), log: side.log).equatable() }
    }
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.redraw(); pair.redraw()
    #expect(pair.on.window.testingRecordHovers().filter { $0.reads.readers.count == 1 }.count == 2,
            "the outer record holds the reader its nested replay read: \(pair.on.window.testingRecordHovers().map { $0.reads.readers.count })")
    try pair.compare("counter changed")
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    let reader = hkCentre(pair)
    for w in [pair.on, pair.off] { w.hover(at: reader) }
    pair.redraw()
    RetainedTrace.sink = nil
    #expect(paintMissReasons(lines).filter { $0.contains("hover") }.count >= 2, "the outer and the inner miss for hover: \(paintMissReasons(lines))")
    try pair.compare("hovered")
}

// MARK: 4 - what is a reader

/// A background that never asks about hover, one with a hover background, a button that is not pressed.
private struct HKPlain: Component, @MainActor Equatable {
    var content: some ElementGroup { Box().frame(width: Pixels(60), height: Pixels(20)).background(.accent) }
    static func == (l: HKPlain, r: HKPlain) -> Bool { true }
}
private struct HKHoverBg: Component, @MainActor Equatable {
    var content: some ElementGroup { Box().frame(width: Pixels(60), height: Pixels(20)).background(.accent).hoverBackground(.separator) }
    static func == (l: HKHoverBg, r: HKHoverBg) -> Bool { true }
}
private struct HKButton: Component, @MainActor Equatable {
    var content: some ElementGroup { Button("go") {} }
    static func == (l: HKButton, r: HKButton) -> Bool { true }
}

/// **8** Only a hover read makes a hover reader: a background-only element and a `Button` that is not pressed read none (`recordHover` is nil: nothing
/// allocated, nothing refused), one with a hover background reads exactly itself. **Mutation:** the `resolvedForPointerState` reorder reverted
/// (every `Box` is a reader).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func onlyAHoverReadMakesAHoverReader() throws {
    let plain = try RPPair(size: sz(200, 60), accessibility: false) { _ in VStack(spacing: 0) { HKPlain().equatable() } }
    let hoverBg = try RPPair(size: sz(200, 60), accessibility: false) { _ in VStack(spacing: 0) { HKHoverBg().equatable() } }
    let button = try RPPair(size: sz(200, 60), accessibility: false) { _ in VStack(spacing: 0) { HKButton().equatable() } }
    #expect(plain.on.window.testingRecordHovers().isEmpty, "a background-only element reads no hover: \(plain.on.window.testingRecordHovers())")
    #expect(button.on.window.testingRecordHovers().isEmpty, "a button that is not pressed reads no hover: \(button.on.window.testingRecordHovers())")
    let reads = hoverBg.on.window.testingRecordHovers()
    #expect(reads.count == 1 && reads[0].reads.readers.count == 1 && !reads[0].reads.wholeSubtree, "one reader: \(reads)")
}

/// An element that asks `isHovered(HitboxID)`, an index that is not a function of the hovered element.
private struct HKKeyed: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 120, height: 18)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) -> HitboxID {
        pass.insertHitbox(bounds, id: id, opaque: true)
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout HitboxID, pass: inout PaintPass) {
        pass.fill(bounds, color: pass.isHovered(prepaint) ? Hsla(h: 0, s: 1, l: 0.5, a: 1) : Hsla(h: 0.6, s: 1, l: 0.5, a: 1))
    }
}
private struct HKKeyedCard: Component, @MainActor Equatable {
    var content: some ElementGroup { HKKeyed() }
    static func == (l: HKKeyedCard, r: HKKeyedCard) -> Bool { true }
}

/// **9** A custom element asks `isHovered(HitboxID)`: its record reads by hitbox (master's rule: not stored while the hovered element is under it), so the pointer anywhere in the ledger runs the prepaint (it does
/// not replay, and no frame is redone), the paint follows the hover, and the window equals the retention-off one. **Mutation:** `wholeSubtree` ignored (the
/// pointer is not seen: the prepaint replays, the paint misses and the frame is redone).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aHitboxKeyedHoverQueryKeepsTheWholeSubtreeRule() throws {
    let pair = try RPPair(size: sz(200, 60), accessibility: false) { _ in VStack(spacing: 0) { HKKeyedCard().equatable() } }
    #expect(pair.on.window.testingRecordHovers().first?.reads.byHitbox == true, "the record reads by hitbox: \(pair.on.window.testingRecordHovers())")
    pair.redraw()
    #expect(pair.frames.last?.retainedPrepaintHits ?? 0 >= 1, "away from the pointer the prepaint replays")
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.hover(at: hkCentre(pair)) }
    let entering = pair.on.frameWork
    #expect(sum(entering, \.retainedPrepaintHits) == 0 && sum(entering, \.retainedRedos) == 0,
            "the frame the pointer enters runs the prepaint and redoes nothing: prepaint hits \(sum(entering, \.retainedPrepaintHits)), redos \(sum(entering, \.retainedRedos))")
    try pair.compare("entered")
    pair.redraw()
    #expect(pair.frames.last?.retainedPrepaintHits == 0, "with the pointer in its ledger the prepaint runs: \(String(describing: pair.frames.last?.retainedPrepaintHits))")
    try pair.compare("hovered")
    for w in [pair.on, pair.off] { w.hover(at: pt(199, 59)) }
    pair.redraw()
    try pair.compare("left")
}

nonisolated(unsafe) private var hkOutsideID: GlobalElementID?

/// Records its own id, takes the pointer, paints nothing.
private struct HKIdRecorder: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        _ = pass.insertHitbox(bounds, id: id, opaque: true)
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        hkOutsideID = id
    }
}
/// Asks about the element above it, outside its occurrence.
private struct HKOutsideReader: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 100, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        let other = hkOutsideID.map { pass.isHovered($0) } ?? false
        pass.fill(bounds, color: other ? Hsla(h: 0, s: 1, l: 0.5, a: 1) : Hsla(h: 0.6, s: 1, l: 0.5, a: 1))
    }
}
private struct HKOutsideCard: Component, @MainActor Equatable {
    var content: some ElementGroup { HKOutsideReader() }
    static func == (l: HKOutsideCard, r: HKOutsideCard) -> Bool { true }
}

/// **10** An element whose paint asks about another element's hover (outside its occurrence) cannot be keyed: the occurrence is ineligible by name, and the
/// window equals the retention-off one when that other element's hover changes. **Mutation:** `hoverReadOutside` removed (the fill is stale).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aHoverReadOfAnotherElementIsIneligible() throws {
    let pair = try RPPair(size: sz(200, 60), accessibility: false) { _ in
        VStack(spacing: 0) { HKIdRecorder(); HKOutsideCard().equatable() }
    }
    pair.on.resetFrameWork()
    pair.redraw()
    #expect(pair.on.lastFrameWork.retainedIneligibleReasons["hoverReadOutside", default: 0] >= 1,
            "the occurrence is ineligible by name: \(pair.on.lastFrameWork.retainedIneligibleReasons)")
    for w in [pair.on, pair.off] { w.hover(at: hkCentre(pair)) }
    pair.redraw()
    try pair.compare("the other element hovered")
    for w in [pair.on, pair.off] { w.hover(at: pt(199, 59)) }
    pair.redraw()
    try pair.compare("left")
}

// MARK: 5 - the pointer's other outputs

/// **11** Blocks with a link cursor scroll under a resting pointer (graft on): the resolved cursor equals the retention-off window's after every step and takes at least
/// two values, no redo, no `pointerInMovedLedger`. A ledger holds the cursor regions, so the cursor is a function of the hitbox list the replay must leave.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aRowWithAPointerStyleScrolledUnderARestingPointerSetsTheCursorAsAFreshWindow() throws {
    var options = ATOptions()
    for index in 0..<60 where index % 3 == 2 { options.cursors.insert(index) }
    let pair = try atLongReplyPair(graft: true, options: options)
    let point = pt(60, 300)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    var styles = Set<String>()
    for step in 0..<25 {
        atRestingWheel(pair, at: point, dy: 40)
        let on = pair.on.window.resolvedPointerStyle, off = pair.off.window.resolvedPointerStyle
        #expect(on == off, "step \(step): cursor \(String(describing: on)) against \(String(describing: off))")
        styles.insert(String(describing: on))
        expectNoPointerRedo(pair.on.frameWork, step)
    }
    RetainedTrace.sink = nil
    #expect(styles.count >= 2, "the cursor changed under the resting pointer: \(styles)")
    #expect(!lines.contains { $0.contains("pointerInMovedLedger") }, "no moved-ledger refusal")
    #expect(redoLinesNameNoPointer(lines), "no redo names the pointer")
}

/// **12** Blocks with a help text scroll under a resting pointer (graft off, the move of a `.help` row is refused by name `hitboxHandlers`): after each
/// step the same point is hovered again and time advances past the delay: the visible tooltip equals the retention-off window's.
@Test @MainActor func aRowWithHelpScrolledUnderARestingPointerShowsTheFreshTooltip() throws {
    var options = ATOptions()
    for index in 0..<60 where index % 3 == 2 { options.helps.insert(index) }
    let pair = try atLongReplyPair(graft: false, options: options)
    let point = pt(60, 300)
    var shown = Set<String>()
    for step in 0..<25 {
        atRestingWheel(pair, at: point, dy: 40)
        for w in [pair.on, pair.off] { w.hover(at: pt(61, 301)); w.hover(at: point); w.advance(by: 2) }
        let on = pair.on.window.visibleTooltip?.text, off = pair.off.window.visibleTooltip?.text
        #expect(on == off, "step \(step): tooltip \(String(describing: on)) against \(String(describing: off))")
        shown.insert(on ?? "none")
    }
    #expect(shown.count >= 2, "a tooltip showed under the resting pointer: \(shown)")
    try pair.compare("help")
}

// MARK: 6 - allocation

#if canImport(Darwin)
/// **13** An idle frame with the pointer resting over a fence costs the retaining window no more, over what the retention-off window pays for the same frame,
/// than one with the pointer resting in the inset: the hover reads add no allocation to an idle frame (the window's own pointer bookkeeping is the off window's
/// too). On master the retaining window paid 16,179 over a fence against 13,112 with the pointer away (its records under the pointer were dropped).
/// **Mutation:** the old rule at the prepaint (occurrences under the pointer run their prepaint again).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aRestingPointerAddsNoAllocationToAnIdleFrame() throws {
    let pair = try atLongReplyPair(graft: true)
    let point = atRestingPoint(pair)
    // Eight interleaved idle frames of each window, the least count of each: a periodic sweep (a cache's epoch) only ever adds to a frame it lands on.
    func idle() throws -> (on: Int, off: Int) {
        var counts = (on: Int.max, off: Int.max)
        for _ in 0..<8 {
            counts.on = min(counts.on, try #require(countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() }))
            counts.off = min(counts.off, try #require(countAllocations { pair.off.window.setNeedsRedraw(); pair.off.tick() }))
        }
        return counts
    }
    for w in [pair.on, pair.off] { w.hover(at: pt(4, 300)) }
    for _ in 0..<6 { pair.redraw() }
    let inset = try idle()
    for w in [pair.on, pair.off] { w.hover(at: point) }
    for _ in 0..<6 { pair.redraw() }
    let over = try idle()
    // The counter is exact within a process, but what a window's caches do on the frame they sweep moves a frame's count by a few to some tens between
    // processes and test orders; the old rule cost over 3,000 more over a fence (master: 16,179 against 13,112 with the pointer away).
    let noise = 16
    #expect(over.on - over.off <= inset.on - inset.off + noise, "idle frame allocations: retaining window over a fence \(over.on) in the inset \(inset.on); retention off \(over.off) and \(inset.off)")
}
#endif

// MARK: 7 - verify mode

/// A card with a link cursor and a help text, the pointer over them: the pointer outputs the verify snapshot reads.
private struct HKPointerCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(spacing: 0) {
            Text("link").pointerStyle(.link).frame(width: Pixels(80), height: Pixels(20))
            Text("help").help("tip").frame(width: Pixels(80), height: Pixels(20))
        }
    }
    static func == (l: HKPointerCard, r: HKPointerCard) -> Bool { true }
}

/// **14** A verified prepaint replay whose cursor or help differs from a fresh prepaint's traps, naming the pointer outputs (`Hitbox.fingerprint` holds only
/// which handler members exist). **Mutation:** the snapshot's `pointer` channel dropped (the child exits normally).
@Test(.serialized, arguments: [("pointerStyle", 50.0), ("help", 70.0)]) @MainActor
func aVerifiedPrepaintReplayWithAStaleCursorOrHelpTraps(arm: (channel: String, y: Double)) async {
    setTestEnvironment("HK_VERIFY_CHANNEL", arm.channel)
    setTestEnvironment("HK_VERIFY_Y", String(arm.y))
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? TestWindow(size: sz(200, 120), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { HKPointerCard().equatable() }
            }) else { return }
            let y = Float(ProcessInfo.processInfo.environment["HK_VERIFY_Y"] ?? "10") ?? 10
            window.hover(at: pt(100, y))
            for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
            let damaged = window.window.testingCorruptPrepaintLedgers(ProcessInfo.processInfo.environment["HK_VERIFY_CHANNEL"] ?? "pointerStyle")
            guard damaged > 0 else { print("no ledger to damage"); return }
            window.window.setNeedsRedraw(); window.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("a replayed prepaint differs from a fresh one: pointer outputs"), "the trap names the pointer outputs: \(stderr)")
}

/// **15** A record whose hover reads differ from a fresh paint's traps, naming `hoverReads`. **Mutation:** the per-record comparison dropped.
@Test(.serialized) @MainActor func aVerifiedPaintReplayWithStaleHoverReadsTraps() async {
    let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let window = try? TestWindow(size: sz(200, 120), textSystem: harnessTextSystem, content: {
                VStack(spacing: 0) { HKPointerCard().equatable() }
            }) else { return }
            for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
            guard window.window.testingCorruptHoverReads() > 0 else { print("no record to damage"); return }
            window.window.setNeedsRedraw(); window.tick()
        }
    }
    let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
    #expect(stderr.contains("hoverReads"), "the trap names hoverReads: \(stderr)")
}

/// **16** The long reply with a resting pointer, a reader, a cursor and a help draws normally under verify mode: every replayed prepaint and paint is compared
/// with a fresh one and every frame equals the retention-off window's.
@Test(.serialized) @MainActor func theLongReplyWithARestingPointerDrawsNormallyUnderVerifyMode() async {
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            var options = ATOptions()
            for index in 0..<60 {
                switch index % 4 { case 1: options.readers.insert(index); case 2: options.cursors.insert(index); case 3: options.helps.insert(index); default: break }
            }
            guard let pair = try? atLongReplyPair(graft: true, options: options) else { exit(2) }
            let point = atRestingPoint(pair)
            for w in [pair.on, pair.off] { w.hover(at: point) }
            for step in 0..<12 {
                atRestingWheel(pair, at: point, dy: step.isMultiple(of: 3) ? -24 : 40)
                do { try pair.compare("step \(step)") } catch { exit(3) }
            }
        }
    }
}

/// One element with two opaque hitboxes under one id (the public `insertHitbox` allows it), painting each half from its own `HitboxID`.
private struct HKTwoBoxes: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 120, height: 18)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) -> [HitboxID] {
        let half = bounds.size.width.value / 2
        let left = Bounds(origin: bounds.origin, size: Size(width: Pixels(half), height: bounds.size.height))
        let right = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + half), y: bounds.origin.y), size: left.size)
        return [pass.insertHitbox(left, id: id, opaque: true), pass.insertHitbox(right, id: id, opaque: true)]
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout [HitboxID], pass: inout PaintPass) {
        let half = bounds.size.width.value / 2
        for (index, box) in prepaint.enumerated() {
            let part = Bounds(origin: Point(x: Pixels(bounds.origin.x.value + half * Float(index)), y: bounds.origin.y), size: Size(width: Pixels(half), height: bounds.size.height))
            pass.fill(part, color: pass.isHovered(box) ? Hsla(h: 0, s: 1, l: 0.5, a: 1) : Hsla(h: 0.6, s: 1, l: 0.5, a: 1))
        }
    }
}
private struct HKTwoBoxesCard: Component, @MainActor Equatable {
    var content: some ElementGroup { HKTwoBoxes() }
    static func == (l: HKTwoBoxesCard, r: HKTwoBoxesCard) -> Bool { true }
}

/// **9b** One element with two hitboxes under one id, painted from `isHovered(HitboxID)`: the pointer moving from its left half to its right leaves the hovered
/// *element* the same, so a record keyed on it replays the left half highlighted. The window equals the retention-off one at every move.
/// **Mutation:** `byHitbox` ignored in `HoverReads.answer` (the keyed-by-element answer: the stale half stays highlighted).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aPointerMovingBetweenTwoHitboxesOfOneElementEqualsAFreshWindow() throws {
    let pair = try RPPair(size: sz(200, 60), accessibility: false) { _ in VStack(spacing: 0) { HKTwoBoxesCard().equatable() } }
    let box = try #require(pair.on.window.lastHitboxes.first(where: { $0.opaque })?.bounds)
    let y = box.origin.y.value + 9
    for x in [box.origin.x.value + 20, box.origin.x.value + 100, box.origin.x.value + 20, box.origin.x.value + 100] {
        for w in [pair.on, pair.off] { w.hover(at: pt(x, y)) }
        pair.redraw()
        try pair.compare("pointer at \(x)")
    }
}

/// A component of `count` hover-reader rows, optionally with an element that asks about one outside its occurrence.
private struct HKReaderRows: Component, @MainActor Equatable {
    let count: Int
    let height: Float
    let outside: Bool
    var counter = 0
    var content: some ElementGroup {
        let count = self.count, height = self.height
        VStack(alignment: .leading, spacing: Pixels(0)) {
            ForEach(0..<count, id: \.self) { index in
                Text("r\(index)").frame(width: Pixels(60), height: Pixels(height)).hoverBackground(.accent).onTapGesture {}
            }
            if outside { HKOutsideReader() }
        }
    }
    static func == (l: HKReaderRows, r: HKReaderRows) -> Bool { l.count == r.count && l.outside == r.outside && l.counter == r.counter }
}

/// **10b** An occurrence with more readers than the limit (33) that also asks about an element outside it is still ineligible by name, and the window equals the
/// retention-off one when that element's hover changes. **Mutation:** the outside check skipped once the recorder overflowed.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func anOccurrenceOverTheReaderLimitStillTaintsAnOutsideRead() throws {
    let pair = try RPPair(size: sz(200, 120), accessibility: false) { _ in
        VStack(spacing: 0) { HKIdRecorder(); HKReaderRows(count: HoverReads.readerLimit + 1, height: 2, outside: true).equatable() }
    }
    pair.on.resetFrameWork()
    pair.redraw()
    #expect(pair.on.lastFrameWork.retainedIneligibleReasons["hoverReadOutside", default: 0] >= 1, "ineligible by name: \(pair.on.lastFrameWork.retainedIneligibleReasons)")
    for w in [pair.on, pair.off] { w.hover(at: hkCentre(pair)) }
    pair.redraw()
    try pair.compare("the other element hovered")
    for w in [pair.on, pair.off] { w.hover(at: pt(199, 119)) }
    pair.redraw()
    try pair.compare("left")
}

private struct HKNestedRows: Component, @MainActor Equatable {
    let counter: Int
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            HKReaderRows(count: 40, height: 2, outside: false).equatable()
            Text("n \(counter)")
        }
    }
    static func == (l: HKNestedRows, r: HKNestedRows) -> Bool { l.counter == r.counter }
}

/// **16a** An outer occurrence whose nested one (40 readers) replays while the outer is recorded again holds the same reads a fresh paint makes: the nested
/// record's overflow is handed to the enclosing recorder, so whether a sibling replayed never changes the representation. **Mutation:** the nested overflow not
/// handed on (the outer holds no reads, a fresh paint of it overflows).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aNestedOccurrencePastTheReaderLimitHandsItsOverflowToTheOuterOne() throws {
    let pair = try RPPair(size: sz(200, 300), accessibility: false) { side in
        VStack(spacing: 0) { HKNestedRows(counter: Int(side.inputs.offset)).equatable() }
    }
    pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
    pair.redraw(); pair.redraw()
    #expect(pair.on.window.testingRecordHovers().filter { $0.reads.wholeSubtree }.count == 2, "inner and outer overflow: \(pair.on.window.testingRecordHovers().map { $0.reads.wholeSubtree })")
    try pair.compare("counter changed")
}

/// **16b** Occurrences whose reads pass every limit draw normally under verify mode, whatever their siblings replayed: a sibling of 300 readers, and an outer
/// occurrence whose nested one (40 readers) replays while the outer is recorded again; each record's reads equal a fresh paint's. **Mutation:** none reddens it alone
/// (verify mode paints a nested occurrence fresh); it guards the sibling-independence of the representation (16a holds the nested hand-over).
@Test(.serialized) @MainActor func occurrencesPastTheReaderLimitDrawNormallyUnderVerifyMode() async {
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        await MainActor.run {
            guard let pair = try? RPPair(size: sz(200, 900), accessibility: false, graft: false, { side in
                VStack(spacing: 0) {
                    HKReaderRows(count: 300, height: 2, outside: false).equatable()
                    HKNestedRows(counter: Int(side.inputs.offset)).equatable()
                    HKReaderRows(count: 3, height: 18, outside: false).equatable()
                }
            }) else { exit(2) }
            for step in 0..<4 {
                pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
                pair.redraw(); pair.redraw()
                let point = pt(20, 3 + Float(step) * 40)
                for w in [pair.on, pair.off] { w.hover(at: point) }
                pair.redraw()
            }
        }
    }
}
