@testable import MetalUI
import Foundation
import MetalUITesting
import Testing

// Alloy's three `ScrollView` gaps (`SP-M`..`CMG-G`, record 438): a padding folded into the scroller's own layout (no wrapper
// element), an accessibility identifier that names the scroller's own node (SwiftUI's `AXScrollArea`, probe
// `docs/probes/swiftui-scrollview-inset.swift` `I1`..`I3`), and the cross-axis `.scrollIndicators` margin (probe `N1`..`N9`).
// The fixture is Alloy's transcript: a bottom-anchored `ProposalScrollView` of lazily realised rows, each carrying a `block-N`
// identifier, inset 7 points on each side, streaming a delta into its last row.

@Observable @MainActor private final class Stream {
    var count = 40
    var tail = "tail"
}

@MainActor private final class ProxyBox {
    var proxy: ScrollViewProxy?
    func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

/// How the transcript is inset.
private enum Inset { case none, wrapped, direct }

@MainActor private func transcriptRows(_ stream: Stream) -> some ProposalElementGroup {
    LazyVStack(spacing: Pixels(0)) {
        ForEach(0..<stream.count, id: \.self) { index in
            ProposalText(index == stream.count - 1 ? "row \(index) \(stream.tail)" : "row \(index)")
                .frame(height: Pixels(20))
                .accessibilityIdentifier("block-\(index)")
        }
    }
}

@MainActor private func transcript(_ stream: Stream, _ inset: Inset, id: String? = nil, box: ProxyBox? = nil,
                                   size: Size<Pixels> = sz(300, 200)) throws -> TestWindow {
    try harnessWindow(size: size) {
        VStack(spacing: Pixels(0)) {
        if inset == .none {
            ProposalScrollView { transcriptRows(stream) }.defaultScrollAnchor(.bottom)
        } else if inset == .wrapped {
            VStack(spacing: Pixels(0)) {
                ScrollViewReader { proxy in
                    let _: Bool? = box?.keep(proxy)
                    ProposalScrollView { transcriptRows(stream) }.defaultScrollAnchor(.bottom)
                }
            }.padding(.horizontal, Pixels(7))
        } else {
            ScrollViewReader { proxy in
                let _: Bool? = box?.keep(proxy)
                ProposalScrollView { transcriptRows(stream) }.defaultScrollAnchor(.bottom).padding(.horizontal, Pixels(7))
            }
        }
        }
    }
}

@MainActor private func settle(_ window: TestWindow, frames: Int = 8) {
    window.window.setNeedsRedraw()
    for _ in 0..<frames { window.tick() }
}

/// Every row's frame by its text.
@MainActor private func frames(_ window: TestWindow) throws -> [String: Bounds<Pixels>] {
    var result: [String: Bounds<Pixels>] = [:]
    for element in try window.elements(role: .staticText) { result[element.value ?? element.label ?? "?"] = element.frame }
    return result
}

/// The element requests of one streamed delta: the tail grows and one frame runs.
@MainActor private func deltaRequests(_ window: TestWindow, _ stream: Stream) -> Int {
    stream.tail += "x"
    window.window.setNeedsRedraw(); window.tick()
    return window.lastFrameWork.elementRequests
}

@MainActor private func steadyRequests(_ window: TestWindow) -> Int {
    settle(window)
    window.window.setNeedsRedraw(); window.tick()
    return window.lastFrameWork.elementRequests
}

// MARK: - Gap 1: the padding

/// **SP-M.** A padding written on the scroller lays out exactly as the wrapped form does: the same row frames at the end
/// of the transcript (the bottom anchor), after a wheel to the top, and after `scrollTo` with each anchor. The padding is
/// deliberately lopsided so a transposed edge shows. Mutation: the padding node left out of `requestProposalLayout`
/// (the rows span the whole window), or the viewport's bounds not re-read in prepaint (the rows move).
@Test @MainActor func aPaddingOnTheScrollerLaysOutLikeTheWrappedForm() throws {
    func lopsided(_ inset: Inset, box: ProxyBox) throws -> TestWindow {
        try harnessWindow(size: sz(300, 200)) {
            VStack(spacing: Pixels(0)) {
            if inset == .wrapped {
                VStack(spacing: Pixels(0)) {
                    ScrollViewReader { proxy in
                        let _: Bool? = box.keep(proxy)
                        ProposalScrollView { transcriptRows(Stream()) }.defaultScrollAnchor(.bottom)
                    }
                }.padding(Edges(top: Pixels(5), right: Pixels(30), bottom: Pixels(11), left: Pixels(7)))
            } else {
                ScrollViewReader { proxy in
                    let _: Bool? = box.keep(proxy)
                    ProposalScrollView { transcriptRows(Stream()) }.defaultScrollAnchor(.bottom)
                        .padding(Edges(top: Pixels(5), right: Pixels(30), bottom: Pixels(11), left: Pixels(7)))
                }
            }
            }
        }
    }
    let wrappedBox = ProxyBox(), directBox = ProxyBox()
    let wrapped = try lopsided(.wrapped, box: wrappedBox), direct = try lopsided(.direct, box: directBox)
    for window in [wrapped, direct] { settle(window) }
    let atEnd = try frames(direct)
    #expect(atEnd == (try frames(wrapped)), "the bottom anchor")
    #expect(atEnd["row 39 tail"]?.origin.x.value ?? -1 >= 7, "the row starts inside the inset: \(String(describing: atEnd["row 39 tail"]))")
    #expect((atEnd["row 39 tail"]?.origin.y.value ?? 0) + (atEnd["row 39 tail"]?.size.height.value ?? 0) <= 189,
            "the last row ends above the bottom padding")
    for window in [wrapped, direct] {
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 1_000_000)
        settle(window)
    }
    #expect(try frames(direct) == (try frames(wrapped)), "a wheel to the top")
    #expect(try frames(direct)["row 0"]?.origin.y.value == 5 + 1)
    for (anchor, key) in [(UnitPoint.top, 10), (.bottom, 20), (.center, 30)] {
        wrappedBox.proxy?.scrollTo(key, anchor: anchor)
        directBox.proxy?.scrollTo(key, anchor: anchor)
        for window in [wrapped, direct] { settle(window) }
        #expect(try frames(direct) == (try frames(wrapped)), "scrollTo(\(key), \(anchor))")
    }
}

/// **SP-M.** The viewport is the padded rectangle: a wheel inside the inset scrolls and one in the padding does not,
/// as the wrapped form answers. Mutation: the scroll region registered at the padding node's bounds.
@Test @MainActor func theScrollRegionIsTheInsetViewport() throws {
    for inset in [Inset.wrapped, .direct] {
        let window = try transcript(Stream(), inset)
        settle(window)
        let before = try frames(window)
        window.scroll(at: pt(3, 100), byDeltaX: 0, deltaY: 40)   // in the 7-point padding
        settle(window)
        #expect(try frames(window) == before, "\(inset): a wheel in the padding scrolls nothing")
        window.scroll(at: pt(150, 100), byDeltaX: 0, deltaY: 40)
        settle(window)
        #expect(try frames(window) != before, "\(inset): a wheel in the viewport scrolls")
    }
}

/// **SP-M.** Two paddings add, as nested paddings do, and an `Edge.Set` form pads only its edges. Mutation: the second
/// padding replacing the first.
@Test @MainActor func paddingsOnTheScrollerAdd() throws {
    let window = try harnessWindow(size: sz(300, 200)) {
        ProposalScrollView { transcriptRows(Stream()) }.padding(.leading, Pixels(10)).padding(Edges(all: Pixels(5)))
    }
    settle(window)
    let hand = try harnessWindow(size: sz(300, 200)) {
        ProposalScrollView { transcriptRows(Stream()) }.padding(Edges(top: Pixels(5), right: Pixels(5), bottom: Pixels(5), left: Pixels(15)))
    }
    settle(hand)
    #expect(try frames(window) == (try frames(hand)))
    #expect(try frames(window).isEmpty == false)
}

/// **SP-M, the cost rule.** Streaming a delta into the padded transcript costs exactly what the unpadded one does, and
/// the wrapped form costs two more (the `VStack` and the padding element). Mutation: the padding built as a wrapper
/// element again (direct becomes bare + 1). Numbers measured on this branch, with the unpadded one equal to master's.
@Test @MainActor func aPaddedTranscriptStreamsAtTheCostOfAnUnpaddedOne() throws {
    var costs: [Inset: (steady: Int, delta: Int)] = [:]
    for inset in [Inset.none, .wrapped, .direct] {
        let stream = Stream()
        let window = try transcript(stream, inset)
        let steady = steadyRequests(window)
        _ = deltaRequests(window, stream)
        let delta = deltaRequests(window, stream)
        costs[inset] = (steady, delta)
        print("SP-M \(inset): steady \(steady), delta \(delta)")
    }
    let none = try #require(costs[.none]), wrapped = try #require(costs[.wrapped]), direct = try #require(costs[.direct])
    #expect(direct.steady == none.steady, "steady direct \(direct.steady) vs bare \(none.steady)")
    #expect(direct.delta == none.delta, "delta direct \(direct.delta) vs bare \(none.delta)")
    #expect(wrapped.delta == none.delta + 2, "delta wrapped \(wrapped.delta)")
    #expect(none.steady == 38 && none.delta == 38, "the unpadded transcript: steady \(none.steady), delta \(none.delta)")
    #expect(direct.delta == 38, "the padded transcript: delta \(direct.delta)")
    #expect(wrapped.delta == 40, "the wrapped transcript: delta \(wrapped.delta)")
}

// MARK: - Gap 2: the identifier

/// A transcript whose last row has no identifier of its own, with `identifier` on the scroller when given.
@MainActor private func identified(_ identifier: String?, contain: Bool = false) throws -> TestWindow {
    try harnessWindow(size: sz(300, 200)) {
        VStack(spacing: Pixels(0)) {
            ProposalScrollView {
                VStack(spacing: Pixels(0)) {
                    ProposalText("alpha").frame(height: Pixels(20)).accessibilityIdentifier("block-0")
                    ProposalText("beta").frame(height: Pixels(20)).accessibilityIdentifier("block-1")
                    ProposalText("gamma").frame(height: Pixels(20))
                }.frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier(identifier ?? "none")
            .padding(.horizontal, Pixels(7))
        }
    }
}

/// **SP-N (probe `I1`..`I3`).** An identifier on a `ScrollView` is the scroll area's own: the node carrying it is a group
/// holding the three rows, framed as the viewport (inside the padding), each row keeps its own identifier and a row
/// with none stays without, where the generic modifier pushed "transcript" onto every leaf and over the rows' own. Mutation:
/// the identifier written through `AccessibilityModifier` again (rows read "transcript", no node of the scroller's own).
@Test @MainActor func anIdentifierOnTheScrollerNamesItsOwnNodeAndLeavesTheRowsAlone() throws {
    let window = try identified("transcript")
    settle(window)
    let area = try window.element(identifier: "transcript")
    #expect(area.role == .group, "role \(area.role)")
    #expect(area.frame.origin.x.value == 7 && area.frame.size.width.value == 286, "frame \(area.frame)")
    #expect(area.children.count == 3, "children \(area.children.count)")
    let rows = try window.elements(role: .staticText)
    let byText = Dictionary(uniqueKeysWithValues: rows.map { ($0.value ?? "", $0.identifier) })
    #expect(byText["alpha"] == "block-0" && byText["beta"] == "block-1", "rows keep their own: \(byText)")
    #expect(byText["gamma"] == .some(nil), "a row without one does not inherit: \(byText)")
    #expect(try window.elements(where: { $0.identifier == "transcript" }).count == 1)
}

/// **SP-N, the cost rule.** The identifier costs no element request: the transcript with it costs what the one without
/// does, where Alloy's workaround (`accessibilityElement(children: .contain)` around the scroller) costs one more.
/// Mutation: the identifier through the generic wrapper (+1).
@Test @MainActor func anIdentifierOnTheScrollerCostsNoElementRequest() throws {
    func requests(_ build: @escaping @MainActor () -> some Element) throws -> Int {
        let window = try harnessWindow(size: sz(300, 200)) { build() }
        return steadyRequests(window)
    }
    func plain() -> ProposalScrollView<some ProposalElementGroup> { ProposalScrollView { transcriptRows(Stream()) }.defaultScrollAnchor(.bottom) }
    let bare = try requests { VStack(spacing: Pixels(0)) { plain() } }
    let named = try requests { VStack(spacing: Pixels(0)) { plain().accessibilityIdentifier("transcript") } }
    let contained = try requests { VStack(spacing: Pixels(0)) { plain().accessibilityElement(children: .contain) } }
    #expect(bare == 38, "bare \(bare)")
    #expect(named == 38, "named \(named)")
    #expect(contained == 39, "the workaround \(contained)")
}

/// **SP-N.** A scroller without an identifier publishes no node of its own: the tree is what it was. Mutation: the
/// node registered unconditionally.
@Test @MainActor func aScrollerWithoutAnIdentifierPublishesNoNodeOfItsOwn() throws {
    let window = try harnessWindow(size: sz(300, 200)) {
        VStack(spacing: Pixels(0)) { ProposalScrollView { transcriptRows(Stream()) }.defaultScrollAnchor(.bottom) }
    }
    settle(window)
    let groups = try window.elements(role: .group)
    #expect(groups.isEmpty, "groups: \(groups.count)")
}

// MARK: - Gap 3: the indicator's margin across its axis

/// The thumb of a 300 x 200 scroller over 40 rows (or 40 columns), wheeled a little.
@MainActor private func thumb(horizontal: Bool = false, margin: (Edge.Set, Pixels)? = nil) throws -> MUIBounds {
    let window = try harnessWindow(size: sz(300, 200)) {
        VStack(spacing: Pixels(0)) {
            if horizontal {
                ProposalScrollView(.horizontal) {
                    HStack(spacing: Pixels(0)) { ForEach(0..<40, id: \.self) { ProposalText("c\($0)").frame(width: Pixels(40), height: Pixels(200)) } }
                }
                .contentMargins(margin?.0 ?? [], margin?.1 ?? Pixels(0), for: .scrollIndicators)
            } else {
                ProposalScrollView { transcriptRows(Stream()) }
                    .contentMargins(margin?.0 ?? [], margin?.1 ?? Pixels(0), for: .scrollIndicators)
            }
        }
    }
    settle(window, frames: 1)
    window.scroll(at: pt(100, 10), byDeltaX: horizontal ? -10 : 0, deltaY: horizontal ? 0 : -10)
    settle(window, frames: 1)
    return try #require(window.scene.rects.first { $0.bounds.size.width == 3 || $0.bounds.size.height == 3 }).bounds
}

/// **CMG-G (probe `N0`..`N9`).** SwiftUI moves a vertical scroller by the scroll-indicator margin on its trailing side, inward
/// when positive and outward when negative, and ignores the leading one; a horizontal scroller follows its bottom
/// margin. Unset, the thumb is where it always was: 5 points inside the edge. Mutation: `indicatorAcross` not subtracted
/// in `indicatorBounds`, or read from the leading edge.
@Test @MainActor func aTrailingIndicatorMarginMovesTheThumbAcrossItsAxis() throws {
    #expect(try thumb().origin.x == 295, "the default is unchanged")
    #expect(try thumb(margin: (.trailing, Pixels(4))).origin.x == 291, "a positive margin moves inward")
    #expect(try thumb(margin: (.trailing, Pixels(-3))).origin.x == 298, "a negative one outward, toward the edge")
    #expect(try thumb(margin: (.leading, Pixels(4))).origin.x == 295, "the leading margin is the far side's")
    #expect(try thumb(margin: (.horizontal, Pixels(4))).origin.x == 291)
    #expect(try thumb(horizontal: true).origin.y == 195, "a horizontal scroller's default")
    #expect(try thumb(horizontal: true, margin: (.bottom, Pixels(4))).origin.y == 191)
    #expect(try thumb(horizontal: true, margin: (.bottom, Pixels(-3))).origin.y == 198)
    #expect(try thumb(horizontal: true, margin: (.top, Pixels(4))).origin.y == 195)
}
