import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy gap G6 (`DSA-A`...`DSA-H`, record 224): `defaultScrollAnchor(_:)` and `defaultScrollAnchor(_:for:)` through a real
// `Window` over the harness. The probe's readings (`docs/probes/swiftui-default-scroll-anchor.swift`) are the
// oracle: `.bottom` starts at the end (I1 1800 of 2000), follows growth while at the end (G1, W1), holds the offset
// after a wheel up (W1 1330 -> 1330) and re-pins on a wheel back to the end (W1 2600 of 2800), and the unmodified
// control stays at the top (I0, W0). Rows are text in a fixed-height frame, 200 x 200 window: a row's top is its
// accessibility frame corrected for the centring in its frame. No sleeps; the lazy counters are work.

@Observable @MainActor final class TranscriptModel {
    var count: Int
    var heights: [Int: Float] = [:]
    var defaultHeight: Float = 20
    init(count: Int) { self.count = count }
    func height(_ index: Int) -> Float { heights[index] ?? defaultHeight }
}

@MainActor private final class AnchorProxyBox {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

@MainActor private func settle(_ window: TestWindow, frames: Int = 8) {
    for _ in 0..<frames { window.tick() }
}

private enum Anchoring {
    case none, bottom, bottomFor(ScrollAnchorRole), center, top
}

@MainActor private func transcript(_ model: TranscriptModel, _ anchoring: Anchoring, size: Float = 200) throws -> TestWindow {
    try harnessWindow(size: sz(200, size)) {
        var scroller = ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<model.count, id: \.self) { index in
                    ProposalText("row \(index)").frame(height: Pixels(model.height(index)))
                }
            }
        }
        switch anchoring {
        case .none: break
        case .bottom: scroller = scroller.defaultScrollAnchor(.bottom)
        case .bottomFor(let role): scroller = scroller.defaultScrollAnchor(.bottom, for: role)
        case .center: scroller = scroller.defaultScrollAnchor(.center)
        case .top: scroller = scroller.defaultScrollAnchor(.top)
        }
        return scroller
    }
}

/// The top edge of the row labelled `row n`, or nil when the tree holds no such row (unrealised).
@MainActor private func top(_ window: TestWindow, _ n: Int, height: Float = 20) -> Float? {
    guard let element = ((try? window.elements(role: .staticText)) ?? []).first(where: { ($0.value ?? $0.label) == "row \(n)" })
    else { return nil }
    return element.frame.origin.y.value - (height - element.frame.size.height.value) / 2
}

/// Whether row `n` lies wholly inside the 200-point viewport.
@MainActor private func isVisible(_ window: TestWindow, _ n: Int, height: Float = 20, viewport: Float = 200) -> Bool {
    guard let y = top(window, n, height: height) else { return false }
    return y >= 0 && y + height <= viewport
}

@MainActor private func wheel(_ window: TestWindow, up points: Float) {
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: points)   // content moves down: toward the top
    settle(window)
}

@MainActor private func wheelToBottom(_ window: TestWindow) {
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -1_000_000)
    settle(window)
}

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

/// **DSA-B (probe I0, I1).** `.bottom` starts a 1000-row transcript at its end: row 999's bottom edge is the viewport's
/// (top 180) and row 0 is not realised; the control without the modifier starts at row 0 (top 0), so the
/// reading is the modifier's. Mutation: the initial fraction applied as `0` (the anchor applied to the top).
@Test @MainActor func bottomStartsATranscriptAtItsEndAndTheControlAtItsStart() throws {
    let anchored = try transcript(TranscriptModel(count: 1000), .bottom)
    settle(anchored)
    #expect(top(anchored, 999) == 180, "row 999 at \(String(describing: top(anchored, 999)))")
    #expect(top(anchored, 0) == nil)
    let control = try transcript(TranscriptModel(count: 1000), .none)
    settle(control)
    #expect(top(control, 0) == 0 && top(control, 999) == nil)
}

/// **DSA-C (probe G1, V1).** Rows appended while the scroller is at the end keep the last row in view, one append at a
/// time: after each of ten appends of 3 rows the last row's top is 180. Mutation: the placement at the end
/// removed (`offset = end` in `anchoredOffset`), which also reddens the variable-height, short-content and
/// `scrollTo` tests; `followsEnd` never published is caught by the cold-frame test only (the warm windows
/// converge through the staleness frame either way, which is the point of publishing it in the first frame).
@Test @MainActor func appendingRowsWhileAtTheEndKeepsTheLastRowVisible() throws {
    let model = TranscriptModel(count: 1000)
    let window = try transcript(model, .bottom)
    settle(window)
    for _ in 0..<10 {
        model.count += 3
        settle(window, frames: 4)
        #expect(top(window, model.count - 1) == 180, "row \(model.count - 1) at \(String(describing: top(window, model.count - 1)))")
    }
}

/// **DSA-C (probe V1).** Variable heights measured late: rows 20 / 50 / 90 tall in a repeating cycle (the lazy
/// index estimates the unmeasured rows from the measured ones, so the extent is wrong until the end window has
/// been measured), 1500 rows, then 40 more appended in bursts: the last row's bottom edge is the viewport's every time,
/// and the window never holds more than the viewport's few rows. Mutation: `ScrollChrome.anchoredOffset`'s
/// `offset = end` removed (the last row sits where the estimate put it).
@Test @MainActor func variableHeightsMeasuredLateStillEndAtTheBottomEdge() throws {
    let model = TranscriptModel(count: 1500)
    for index in 0..<2000 { model.heights[index] = [20, 50, 90][index % 3] }
    let window = try transcript(model, .bottom)
    settle(window, frames: 12)
    func lastBottom() -> Float? {
        guard let y = top(window, model.count - 1, height: model.height(model.count - 1)) else { return nil }
        return y + model.height(model.count - 1)
    }
    #expect(lastBottom() == 200, "bottom \(String(describing: lastBottom()))")
    for _ in 0..<8 {
        model.count += 5
        settle(window, frames: 8)
        #expect(lastBottom() == 200, "after append, bottom \(String(describing: lastBottom())) of row \(model.count - 1)")
    }
    #expect(window.lastFrameWork.lazyUnitsRealized <= 12, "realised \(window.lastFrameWork.lazyUnitsRealized)")
}

/// **DSA-D (probe W1).** A wheel up releases the pin: after it, appended rows leave the viewport exactly where it
/// was (a row that was on screen keeps its top), and the last row is no longer visible. Mutation: the release
/// removed (`memory.pinned = false` -> nothing), after which the append jumps to the end.
@Test @MainActor func aWheelUpReleasesTheEndAndAppendedRowsLeaveTheViewportAlone() throws {
    let model = TranscriptModel(count: 1000)
    let window = try transcript(model, .bottom)
    settle(window)
    wheel(window, up: 400)
    let before = try #require(top(window, 975), "row 975 should be on screen after 400 points up")
    #expect(!isVisible(window, 999))
    model.count += 20
    settle(window)
    #expect(top(window, 975) == before, "row 975 moved from \(before) to \(String(describing: top(window, 975)))")
    #expect(!isVisible(window, model.count - 1))
}

/// **DSA-D (probe W1).** Scrolling back to the end re-pins: wheel up, append (stays), wheel to the bottom, append
/// (the new last row is at the bottom edge). Mutation: `.bottom` as `initialOffset` only (see the role test).
/// Also pinned here: the settle after the last wheel asks for no further frame.
@Test @MainActor func scrollingBackToTheEndPinsAgain() throws {
    let model = TranscriptModel(count: 1000)
    let window = try transcript(model, .bottom)
    settle(window)
    wheel(window, up: 600)
    model.count += 10
    settle(window)
    #expect(!isVisible(window, model.count - 1))
    wheelToBottom(window)
    #expect(top(window, model.count - 1) == 180, "at the end after the wheel: \(String(describing: top(window, model.count - 1)))")
    model.count += 10
    settle(window)
    #expect(top(window, model.count - 1) == 180, "re-pinned: \(String(describing: top(window, model.count - 1)))")
}

/// **DSA-E (probe T1).** A block above the viewport that grows while the scroller is pinned leaves it pinned: row 988
/// (just above the viewport, realised as overscan) grows from 20 to 120 and the last row is still at the bottom
/// edge. Mutation: the `VL-G` adjustment applied to a following scroller (`DSA-E`), which moves the stored offset
/// by the growth and reads as the user leaving the end.
@Test @MainActor func aBlockAboveTheViewportGrowingWhilePinnedStaysPinned() throws {
    let model = TranscriptModel(count: 1000)
    let window = try transcript(model, .bottom)
    settle(window)
    #expect(top(window, 988) != nil, "row 988 is realised above the viewport (overscan)")
    model.heights[988] = 120
    settle(window, frames: 10)
    #expect(top(window, 999) == 180, "row 999 at \(String(describing: top(window, 999)))")
    model.count += 3
    settle(window)
    #expect(top(window, 1002) == 180, "and it still follows: \(String(describing: top(window, 1002)))")
}

/// **LZ-E, DSA-C.** Five thousand rows realise the window and only the window, in the first frame too: the cold frame
/// holds the LAST 32 rows (not the first 32), and the warm frames 12 rows (the bottom 10 on screen and 2 of overscan above; no line follows the last), at the end and after an append.
/// Mutation: the cold window left at `0 ..< 32` (row 4999 absent from the first frame).
@Test @MainActor func fiveThousandRowsRealizeOnlyTheWindowAtTheEnd() throws {
    let model = TranscriptModel(count: 5000)
    let window = try transcript(model, .bottom)
    let first = try #require(window.frameWork.first)
    #expect(first.lazyUnitsRealized >= 32 && first.lazyUnitsRealized < 200, "cold: \(first.lazyUnitsRealized)")
    #expect(top(window, 4999) != nil, "the first frame realised the end")
    settle(window)
    #expect(window.lastFrameWork.lazyUnitsRealized == 12, "warm: \(window.lastFrameWork.lazyUnitsRealized)")
    #expect(window.lastFrameWork.lazyUnbounded == 0)
    model.count += 7
    settle(window)
    #expect(window.lastFrameWork.lazyUnitsRealized == 12, "after append: \(window.lastFrameWork.lazyUnitsRealized)")
    #expect(top(window, 5006) == 180)
}

/// **DSA-C.** A pinned scroller that has settled asks for no further frame: the write that places the offset is the
/// compared one, so a window with nothing changing goes idle. Mutation: an unconditional write in `resolvedOffset`
/// (the window never settles).
@Test @MainActor func aSettledPinnedScrollerGoesIdle() async throws {
    let model = TranscriptModel(count: 1000)
    let window = try transcript(model, .bottom)
    settle(window, frames: 12)
    try await window.runUntilIdle()
}

/// **DSA-F (probe R2, G4, W2).** `for: .sizeChanges` alone does not start at the end (row 0 on top), does not follow
/// growth from the top, and follows once the user is at the end (a wheel to the bottom, then an append), and a
/// wheel up releases it. Mutation: the role ignored (`sizeChangesFraction` returns nil: no follow after the wheel).
@Test @MainActor func theSizeChangesRoleFollowsOnlyAScrollerThatIsAtTheEnd() throws {
    let model = TranscriptModel(count: 100)
    let window = try transcript(model, .bottomFor(.sizeChanges))
    settle(window)
    #expect(top(window, 0) == 0, "no initial offset")
    model.count += 20
    settle(window)
    #expect(top(window, 0) == 0, "not at the end: an append leaves it at the top")
    wheelToBottom(window)
    model.count += 20
    settle(window)
    #expect(top(window, model.count - 1) == 180, "at the end: followed, row \(model.count - 1) at \(String(describing: top(window, model.count - 1)))")
    wheel(window, up: 300)
    model.count += 20
    settle(window)
    #expect(!isVisible(window, model.count - 1), "wheel up released it")
}

/// **DSA-F (probe R1, W3).** `for: .initialOffset` starts at the end and follows until the user leaves, and does NOT
/// re-engage when they return (the end after a wheel back is not followed). Mutation: `pinned` set again whenever
/// the offset is at the end (re-engages, reddening the last expectation).
@Test @MainActor func theInitialOffsetRoleFollowsUntilTheUserLeavesAndNeverAgain() throws {
    let model = TranscriptModel(count: 100)
    let window = try transcript(model, .bottomFor(.initialOffset))
    settle(window)
    #expect(top(window, 99) == 180)
    model.count += 10
    settle(window)
    #expect(top(window, 109) == 180, "followed")
    wheel(window, up: 300)
    wheelToBottom(window)
    model.count += 10
    settle(window)
    #expect(!isVisible(window, 119), "did not re-engage: row 119 at \(String(describing: top(window, 119)))")
}

/// **DSA-G (probe S1, S2, N1).** Content shorter than the viewport sits at the anchor: three 20-point rows are
/// bottom-aligned (row 2 top 180, row 0 top 140) with `.bottom` and the `.alignment` role, top-aligned for the
/// `.sizeChanges` role (row 0 top 0); and when the bottom-aligned content grows past the viewport it keeps to the
/// end. Mutation: `alignedOffset` returns nil (the rows sit at the top).
@Test @MainActor func shortContentSitsAtTheAnchorAndKeepsToTheEndWhenItGrows() throws {
    let model = TranscriptModel(count: 3)
    let window = try transcript(model, .bottom)
    settle(window)
    #expect(top(window, 2) == 180 && top(window, 0) == 140, "rows 0 and 2 at \(String(describing: top(window, 0))), \(String(describing: top(window, 2)))")
    model.count = 30
    settle(window)
    #expect(top(window, 29) == 180, "grown past the viewport: row 29 at \(String(describing: top(window, 29)))")

    let alignment = try transcript(TranscriptModel(count: 3), .bottomFor(.alignment))
    settle(alignment)
    #expect(top(alignment, 2) == 180)
    let sizes = try transcript(TranscriptModel(count: 3), .bottomFor(.sizeChanges))
    settle(sizes)
    #expect(top(sizes, 0) == 0, "the size-changes role does not align (probe S3)")
}

/// **DSA-B (probe I3, I2).** Other anchors place the scroller once and do not follow: `.center` starts a 100-row
/// transcript with its middle in the viewport (offset 900 of 2000: row 45 on top) and an append leaves it there;
/// `.top` is the unmodified behaviour. Mutation: the fraction used as `1 - fraction` (row 55 on top).
@Test @MainActor func aCenterAnchorStartsInTheMiddleAndDoesNotFollow() throws {
    let model = TranscriptModel(count: 100)
    let window = try transcript(model, .center)
    settle(window)
    #expect(top(window, 45) == 0, "row 45 at \(String(describing: top(window, 45)))")
    model.count += 20
    settle(window)
    #expect(top(window, 45) == 0, "an append does not move a centred scroller")
    let topAnchored = try transcript(TranscriptModel(count: 100), .top)
    settle(topAnchored)
    #expect(top(topAnchored, 0) == 0)
}

/// **DSA-H (probe H1, H2, H3).** A horizontal scroller reads the anchor's x: `.trailing` starts a `LazyHStack` at its end
/// and follows an append, `.bottom` (a vertical component) is the centre, and `.leading` is the unmodified start.
/// Mutation: the anchor's y read for every axis (`.trailing` then centres).
@Test @MainActor func aHorizontalScrollerReadsTheTrailingAnchor() throws {
    func window(_ model: TranscriptModel, _ anchor: UnitPoint?) throws -> TestWindow {
        try harnessWindow(size: sz(200, 40)) {
            var scroller = ProposalScrollView(.horizontal) {
                LazyHStack(spacing: Pixels(0)) {
                    ForEach(0..<model.count, id: \.self) { index in ProposalText("col \(index)").frame(width: Pixels(20), height: Pixels(20)) }
                }
            }
            if let anchor { scroller = scroller.defaultScrollAnchor(anchor) }
            return scroller
        }
    }
    func left(_ w: TestWindow, _ n: Int) -> Float? {
        ((try? w.elements(role: .staticText)) ?? []).first(where: { ($0.value ?? $0.label) == "col \(n)" })?.frame.origin.x.value
    }
    let model = TranscriptModel(count: 100)
    let trailing = try window(model, .trailing)
    settle(trailing)
    let lastLeft = try #require(left(trailing, 99))
    #expect(lastLeft >= 170 && lastLeft < 200, "col 99 at \(lastLeft)")
    model.count += 5
    settle(trailing)
    let appended = try #require(left(trailing, 104))
    #expect(appended >= 170 && appended < 200, "followed: col 104 at \(appended)")
    let leading = try window(TranscriptModel(count: 100), .leading)
    settle(leading)
    #expect(left(leading, 0) != nil && left(leading, 99) == nil, ".leading is the middle of a horizontal scroller's cross axis and the start of it")
}

/// **DSA-I (probe P1, P2).** An explicit position wins over the anchor: `scrollTo(10)` from the first frame lands
/// row 10 at the top and the pin is released by it (an append leaves row 10 where it was). Mutation: the pin
/// survives a scroll away (`pinned` not released).
@Test @MainActor func aScrollToAwayFromTheEndReleasesThePin() throws {
    let box = AnchorProxyBox()
    let model = TranscriptModel(count: 1000)
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = box.keep(proxy)
                ProposalScrollView {
                    LazyVStack(spacing: Pixels(0)) {
                        ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                    }
                }.defaultScrollAnchor(.bottom)
            }
        }
    }
    settle(window)
    #expect(top(window, 999) == 180)
    box.proxy?.scrollTo(10)
    settle(window)
    #expect(top(window, 10) == 0, "row 10 at \(String(describing: top(window, 10)))")
    model.count += 10
    settle(window)
    #expect(top(window, 10) == 0, "an append after the scrollTo leaves it: \(String(describing: top(window, 10)))")
    box.proxy?.scrollTo(model.count - 1, anchor: .bottom)
    settle(window)
    #expect(top(window, model.count - 1) == 180)
    model.count += 4
    settle(window)
    #expect(top(window, model.count - 1) == 180, "a scrollTo to the last row at the bottom is at the end, so it pins")
}

/// **DSA-I.** A scroller nested in a pinned one is its own: the inner (no anchor) keeps its top and the outer
/// follows. Mutation: the context's `followsEnd` leaking to the inner scroller (inner windowed at its end).
@Test @MainActor func aNestedScrollerWithoutAnAnchorIsNotPinnedByItsParent() throws {
    let model = TranscriptModel(count: 200)
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            VStack(spacing: Pixels(0)) {
                ProposalScrollView {
                    LazyVStack(spacing: Pixels(0)) {
                        ForEach(0..<50, id: \.self) { ProposalText("inner \($0)").frame(height: Pixels(20)) }
                    }
                }.frame(height: Pixels(100))
                LazyVStack(spacing: Pixels(0)) {
                    ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                }
            }
        }.defaultScrollAnchor(.bottom)
    }
    settle(window)
    #expect(top(window, 199) == 180, "outer follows: \(String(describing: top(window, 199)))")
    model.count += 4
    settle(window)
    #expect(top(window, 203) == 180)
}

/// **DSA-A, DSA-C.** The legacy `ScrollView` carries the same modifier and the same pin (it has its own
/// `requestLayout`): a lazy stack in it starts at the end, follows an append and keeps the realised window.
/// Mutation: the legacy scroller's `followsEnd` left at `false` (the first frame realises the first 32 rows, so
/// row 4999 is absent from it).
@Test @MainActor func theLegacyScrollViewPinsALazyStackToo() throws {
    let model = TranscriptModel(count: 5000)
    let window = try harnessWindow(size: sz(200, 200)) {
        ScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
            }
        }.defaultScrollAnchor(.bottom)
    }
    #expect(top(window, 4999) != nil, "the first frame realised the end")
    settle(window)
    #expect(top(window, 4999) == 180, "row 4999 at \(String(describing: top(window, 4999)))")
    model.count += 3
    settle(window)
    #expect(top(window, 5002) == 180, "followed: \(String(describing: top(window, 5002)))")
    wheel(window, up: 400)
    model.count += 3
    settle(window)
    #expect(!isVisible(window, 5005), "released")
}
