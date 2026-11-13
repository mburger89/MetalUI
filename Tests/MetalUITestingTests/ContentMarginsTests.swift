import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy gap G43 (`CMG-A`...`CMG-F`, record 287): `contentMargins(_:_:for:)` through a real `Window` over the harness.
// Rows are 20 points tall in a 200 x 200 window; the scroll-content margins are 40 above and 60 below unless a test says
// otherwise, so row 0's top is 40 at offset 0 and the last of 30 rows ends at 140 at the end of the scroll (the
// visible region is 40...140). SwiftUI's documented behaviour is the oracle (the probe,
// `docs/probes/swiftui-content-margins.swift`, was written and NOT run: an agent opens no window).

@Observable @MainActor private final class MarginModel {
    var count = 30
    var top: Float = 40
    var bottom: Float = 60
}

@MainActor private final class MarginProxyBox {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

@MainActor private func settle(_ window: TestWindow, frames: Int = 8) {
    window.window.setNeedsRedraw()
    for _ in 0..<frames { window.tick() }
}

/// The top edge of the row labelled `row n`, or nil when the tree holds no such row.
@MainActor private func top(_ window: TestWindow, _ n: Int, prefix: String = "row", height: Float = 20) -> Float? {
    guard let element = ((try? window.elements(role: .staticText)) ?? []).first(where: { ($0.value ?? $0.label) == "\(prefix) \(n)" })
    else { return nil }
    return element.frame.origin.y.value - (height - element.frame.size.height.value) / 2
}

@MainActor private func wheel(_ window: TestWindow, _ deltaY: Float) {
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: deltaY)
    settle(window)
}

/// A scroller over `model.count` rows, with `placement` margins of `model.top` and `model.bottom`.
@MainActor private func rows(_ model: MarginModel, lazy: Bool = false, legacy: Bool = false,
                             placement: ContentMarginPlacement = .scrollContent, anchor: UnitPoint? = nil,
                             box: MarginProxyBox? = nil, pad: Float = 0) throws -> TestWindow {
    try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = box?.keep(proxy)
                if legacy {
                    ScrollView {
                        LazyVStack(spacing: Pixels(0)) {
                            ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                        }
                    }
                    .defaultScrollAnchor(anchor)
                    .contentMargins(.top, Pixels(model.top), for: placement)
                    .contentMargins(.bottom, Pixels(model.bottom), for: placement)
                } else if lazy {
                    ProposalScrollView {
                        LazyVStack(spacing: Pixels(0)) {
                            ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                        }
                    }
                    .defaultScrollAnchor(anchor)
                    .contentMargins(.top, Pixels(model.top), for: placement)
                    .contentMargins(.bottom, Pixels(model.bottom), for: placement)
                } else {
                    ProposalScrollView {
                        VStack(spacing: Pixels(0)) {
                            ForEach(0..<model.count, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                        }.padding(Pixels(pad))
                    }
                    .defaultScrollAnchor(anchor)
                    .contentMargins(.top, Pixels(model.top), for: placement)
                    .contentMargins(.bottom, Pixels(model.bottom), for: placement)
                }
            }
        }
    }
}

/// **CMG-A (probe M1).** A top and a bottom `.scrollContent` margin put row 0 at the top margin at offset 0 and the last row above the
/// bottom margin at the end; the control without margins starts at 0 and ends at 180. Mutation: the margin padding
/// dropped in `paddedForContentMargins` (row 0 at 0, the last row at 180).
@Test @MainActor func scrollContentMarginsPositionTheContentAtBothEnds() throws {
    for legacy in [false, true] {
        let window = try rows(MarginModel(), lazy: legacy, legacy: legacy)
        settle(window)
        #expect(top(window, 0) == 40, "legacy \(legacy): row 0 at \(String(describing: top(window, 0)))")
        wheel(window, -1_000_000)
        #expect(top(window, 29) == 120, "legacy \(legacy): row 29 at \(String(describing: top(window, 29)))")
    }
    let none = MarginModel(); none.top = 0; none.bottom = 0
    let control = try rows(none)
    settle(control)
    #expect(top(control, 0) == 0)
    wheel(control, -1_000_000)
    #expect(top(control, 29) == 180)
}

/// **CMG-A.** The content scrolls and draws under the margin region: scrolled by 30, row 0 sits at 10, inside the 40-point
/// margin, in the accessibility tree and as a drawn text run; nothing clips at the margin. Mutation: a clip pushed at
/// the margin's edge (row 0 absent from the scene).
@Test @MainActor func contentStillDrawsAndScrollsUnderTheMarginRegion() throws {
    let window = try rows(MarginModel())
    settle(window)
    wheel(window, -30)
    #expect(top(window, 0) == 10, "row 0 at \(String(describing: top(window, 0)))")
    // Drawn: a glyph's quad survives its own content mask somewhere above y = 40.
    let drawn = window.scene.glyphs.contains { glyph in
        let low = max(glyph.bounds.origin.y, glyph.contentMask.origin.y)
        let high = min(glyph.bounds.origin.y + glyph.bounds.size.height, glyph.contentMask.origin.y + glyph.contentMask.size.height)
        return high > low && low < 40
    }
    #expect(drawn, "a glyph is drawn inside the top margin region")
}

/// **CMG-C.** A `.scrollIndicators` margin moves only the indicator: row 0 stays at 0, and the thumb's track starts
/// at the margin (the control's thumb starts at 0). Mutation: the indicator inset ignored (thumb top 0 + travel).
@Test @MainActor func aScrollIndicatorsMarginMovesOnlyTheIndicator() throws {
    func thumb(_ window: TestWindow) -> MUIRect? { window.scene.rects.first { $0.bounds.size.width == 3 } }
    let margins = MarginModel(); margins.top = 30; margins.bottom = 30
    let window = try rows(margins, placement: .scrollIndicators)
    settle(window, frames: 1)
    wheel(window, -10)
    #expect(top(window, 0) == -10, "the content is not inset: row 0 at \(String(describing: top(window, 0)))")
    let none = MarginModel(); none.top = 0; none.bottom = 0
    let control = try rows(none, placement: .scrollIndicators)
    settle(control, frames: 1)
    wheel(control, -10)
    let inset = try #require(thumb(window)), plain = try #require(thumb(control))
    #expect(inset.bounds.origin.y >= 30, "thumb top \(inset.bounds.origin.y)")
    #expect(inset.bounds.origin.y + inset.bounds.size.height <= 170, "thumb bottom \(inset.bounds.origin.y + inset.bounds.size.height)")
    #expect(plain.bounds.origin.y < 30, "control thumb top \(plain.bounds.origin.y)")
}

/// **CMG-A.** A margin adds to the content's own padding: 10 points of padding under a 40-point margin puts row 0 at 50.
/// Mutation: the margin replacing the padding (row 0 at 40).
@Test @MainActor func marginsAddToTheContentsOwnPadding() throws {
    let window = try rows(MarginModel(), pad: 10)
    settle(window)
    #expect(top(window, 0) == 50, "row 0 at \(String(describing: top(window, 0)))")
}

/// **CMG-B.** The nearest `contentMargins` of a placement overrides the one above it, per edge: an inner top of 10 under an
/// outer 40/60 leaves the outer bottom. Mutation: the inner write replacing every edge.
@Test @MainActor func aNearerMarginOverridesTheOneAbovePerEdge() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ProposalScrollView {
                VStack(spacing: Pixels(0)) {
                    ForEach(0..<30, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
                }
            }
            .contentMargins(.bottom, Pixels(60), for: .scrollContent)   // innermost, applied last
            .contentMargins(.top, Pixels(10), for: .scrollContent)
            .contentMargins(.top, Pixels(40), for: .scrollContent)   // outermost: the 10 below it wins
        }
    }
    settle(window)
    #expect(top(window, 0) == 10, "row 0 at \(String(describing: top(window, 0)))")
    wheel(window, -1_000_000)
    #expect(top(window, 29) == 120, "bottom 60 kept: row 29 at \(String(describing: top(window, 29)))")
}

/// **CMG-D.** `scrollTo` measures against the viewport minus the margins: `.top` puts row 10 just below the top margin
/// (40), `.bottom` just above the bottom one (its top 120), and with no anchor a row below is brought to the bottom
/// margin and one above to the top margin. Mutation: the margin left out of `scrollOffset(bringing:)`.
@Test @MainActor func scrollToPlacesATargetInsideTheMargins() throws {
    let box = MarginProxyBox()
    let window = try rows(MarginModel(), lazy: true, box: box)
    settle(window)
    box.proxy?.scrollTo(10, anchor: .top)
    settle(window)
    #expect(top(window, 10) == 40, "row 10 at \(String(describing: top(window, 10)))")
    box.proxy?.scrollTo(20, anchor: .bottom)
    settle(window)
    #expect(top(window, 20) == 120, "row 20 at \(String(describing: top(window, 20)))")
    box.proxy?.scrollTo(2)
    settle(window)
    #expect(top(window, 2) == 40, "least distance, above: row 2 at \(String(describing: top(window, 2)))")
    box.proxy?.scrollTo(12)
    settle(window)
    #expect(top(window, 12) == 120, "least distance, below: row 12 at \(String(describing: top(window, 12)))")
}

/// **CMG-D, CMG-E.** `defaultScrollAnchor(.bottom)` keeps the last row above the bottom margin, and a bottom margin that
/// grows (a composer taller) or shrinks keeps it there in the SAME frame: one tick after the model write, no lag.
/// Mutation: the margin read from last frame (the one-frame lag), or `followsEnd` ignored after a margin change.
@Test @MainActor func aBottomPinnedScrollerFollowsAChangingBottomMargin() throws {
    for legacy in [false, true] {
        let model = MarginModel()
        let window = try rows(model, lazy: true, legacy: legacy, anchor: .bottom)
        settle(window)
        #expect(top(window, 29) == 120, "legacy \(legacy): pinned: row 29 at \(String(describing: top(window, 29)))")
        model.bottom = 100
        window.window.setNeedsRedraw(); window.tick()
        #expect(top(window, 29) == 80, "legacy \(legacy): grown, same frame: row 29 at \(String(describing: top(window, 29)))")
        model.bottom = 20
        window.window.setNeedsRedraw(); window.tick()
        #expect(top(window, 29) == 160, "legacy \(legacy): shrunk, same frame: row 29 at \(String(describing: top(window, 29)))")
    }
}

/// **CMG-E.** A scroller scrolled away from the bottom keeps its row where it is when the bottom margin changes: row 10
/// stays at the top margin through a grow and a shrink. Mutation: the margin change re-pinning or re-centring the
/// offset.
@Test @MainActor func aScrollerAwayFromTheBottomKeepsItsRowWhenTheBottomMarginChanges() throws {
    let model = MarginModel()
    let box = MarginProxyBox()
    let window = try rows(model, lazy: true, anchor: .bottom, box: box)
    settle(window)
    box.proxy?.scrollTo(10, anchor: .top)
    settle(window)
    #expect(top(window, 10) == 40)
    model.bottom = 120
    window.window.setNeedsRedraw(); window.tick()
    #expect(top(window, 10) == 40, "grown: row 10 at \(String(describing: top(window, 10)))")
    model.bottom = 10
    window.window.setNeedsRedraw(); window.tick()
    #expect(top(window, 10) == 40, "shrunk: row 10 at \(String(describing: top(window, 10)))")
}

@MainActor private final class BuildLog { var builds = 0 }

private struct CountedRows: Component, @MainActor Equatable {
    let log: BuildLog
    var content: some ElementGroup {
        let _ = bump()
        return VStack(spacing: Pixels(0)) {
            ForEach(0..<30, id: \.self) { ProposalText("row \($0)").frame(height: Pixels(20)) }
        }
    }
    @MainActor private func bump() { log.builds += 1 }
    static func == (l: CountedRows, r: CountedRows) -> Bool { l.log === r.log }
}

/// **CMG-F.** A margin change relays out without rebuilding the content's elements: an equatable component under the
/// scroller is built once through three margin changes, and row 0 follows the margin. Mutation: the component made
/// unequal (built every frame).
@Test @MainActor func aMarginChangeRelaysOutWithoutRebuildingTheContent() throws {
    let model = MarginModel()
    let log = BuildLog()
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ProposalScrollView { CountedRows(log: log).equatable() }
                .contentMargins(.top, Pixels(model.top), for: .scrollContent)
        }
    }
    settle(window)
    let built = log.builds
    #expect(built >= 1)
    for margin: Float in [10, 60, 25] {
        model.top = margin
        settle(window, frames: 2)
        #expect(top(window, 0) == margin, "row 0 at \(String(describing: top(window, 0))) for \(margin)")
    }
    #expect(log.builds == built, "built \(log.builds) times, \(built) before the margin changed")
}

private struct MarginListRow: Identifiable { let id: Int }

/// **CMG-A.** A `List` inside a scroller gets the margins too: its first row starts at the top margin and, scrolled to the
/// end, its last row ends above the bottom one. Mutation: the margin padding dropped from the legacy scroller.
@Test @MainActor func aListInsideAScrollerGetsTheMargins() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollView {
                List((0..<30).map(MarginListRow.init), rowHeight: Pixels(20)) { row in
                    Text("row \(row.id)").frame(height: Pixels(20))
                }
            }
            .contentMargins(.top, Pixels(40), for: .scrollContent)
            .contentMargins(.bottom, Pixels(60), for: .scrollContent)
        }
    }
    settle(window)
    #expect(top(window, 0) == 40, "row 0 at \(String(describing: top(window, 0)))")
    wheel(window, -1_000_000)
    #expect(top(window, 29) == 120, "row 29 at \(String(describing: top(window, 29)))")
}
