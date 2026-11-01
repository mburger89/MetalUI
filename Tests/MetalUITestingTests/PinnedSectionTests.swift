import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// R3-4 (`SP-G`...`SP-J`, record 177): `LazyVStack`/`LazyHStack` `pinnedViews:` over `Section`, through a real
// `Window`. Three sections of header 20 + 100 rows of 20 + footer 20 (2040 each; one extent throughout, so the
// lazy index's estimate for unmeasured units is exact) in a 200 x 200 window; every
// figure is a unit's top (or left) edge in the window, read from the accessibility tree and corrected for the
// text being centred in its fixed frame. The probe's readings (`docs/probes/swiftui-scroll-position.swift` V1,
// O1, W1, H1) are the oracle: a pinned header at 0 where the unpinned control reads the negative offset, and no
// push-off at the end of its section.

@MainActor private func settle(_ window: TestWindow, frames: Int = 14) {
    for _ in 0..<frames { window.tick() }
}

@MainActor private func sectionsWindow(pinned: PinnedScrollableViews, sections: Int = 3, rows: Int = 100,
                                       log: HarnessLog? = nil) throws -> TestWindow {
    try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0), pinnedViews: pinned) {
                ForEach(0..<sections) { s in
                    Section {
                        ForEach(0..<rows) { r in ProposalText("r\(s)-\(r)").frame(height: Pixels(20)) }
                    } header: {
                        ProposalText("H\(s)").frame(height: Pixels(20))
                    } footer: {
                        ProposalText("F\(s)").frame(height: Pixels(20))
                    }
                }
            }
        }
    }
}

/// The top of the unit labelled `label` in the window, or nil when the tree holds no such unit.
@MainActor private func top(_ window: TestWindow, _ label: String, extent: Float) -> Float? {
    guard let element = ((try? window.elements(role: .staticText)) ?? []).first(where: { ($0.label ?? $0.value) == label })
    else { return nil }
    return element.frame.origin.y.value - (extent - element.frame.size.height.value) / 2
}

@MainActor private func scrollTo(_ window: TestWindow, offset: Float) {
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -offset)
    settle(window)
}

/// **SP-G.** `pinnedViews: [.sectionHeaders]` holds header 0 at the viewport's top while the viewport's top is in
/// section 0 (offsets 1000 and 2020, the latter inside its footer), where the unpinned control has no header
/// 0 on screen at all; at 2040 section 1 is current and its header sits at 0 with header 0 gone (probe V1/V0 for the
/// pin against the control, O for the absence of a push-off: the header leaves with its section).
/// Mutation: `max(natural, edge)` -> `natural` in `placeSubviews` (header 0 absent or off screen).
@Test @MainActor func aPinnedHeaderStaysAtTheTopWhileItsSectionIsCurrent() throws {
    let pinned = try sectionsWindow(pinned: .sectionHeaders)
    settle(pinned)
    scrollTo(pinned, offset: 1000)
    #expect(top(pinned, "H0", extent: 20) == 0, "H0 at \(String(describing: top(pinned, "H0", extent: 20)))")
    #expect(top(pinned, "H1", extent: 20) == nil)
    scrollTo(pinned, offset: 1020)   // total 2020
    #expect(top(pinned, "H0", extent: 20) == 0, "H0 at \(String(describing: top(pinned, "H0", extent: 20)))")
    #expect(top(pinned, "H1", extent: 20) == 20, "H1 sits at its natural place, 2040 - 2020: \(String(describing: top(pinned, "H1", extent: 20)))")
    scrollTo(pinned, offset: 20)     // total 2040
    #expect(top(pinned, "H1", extent: 20) == 0, "H1 at \(String(describing: top(pinned, "H1", extent: 20)))")
    #expect(top(pinned, "H0", extent: 20) == nil, "header 0 left with its section")

    let control = try sectionsWindow(pinned: [])
    settle(control)
    scrollTo(control, offset: 1000)
    #expect(top(control, "H0", extent: 20) == nil, "unpinned, header 0 is far above the viewport")
}

/// **SP-G.** Footers pin to the trailing edge: at offset 1000 footer 0 (natural place 2020 - 1000 = 1020) sits
/// at 180 ... 200; at 2020 the viewport's bottom is in section 1, so footer 1 takes the edge at 180 and footer
/// 0 shows at its natural 0 ... 20. Mutation: the footer branch uses `max` (footer 0 absent).
@Test @MainActor func aPinnedFooterStaysAtTheBottomWhileItsSectionIsCurrent() throws {
    let window = try sectionsWindow(pinned: .sectionFooters)
    settle(window)
    scrollTo(window, offset: 1000)
    #expect(top(window, "F0", extent: 20) == 180, "F0 at \(String(describing: top(window, "F0", extent: 20)))")
    scrollTo(window, offset: 1020)
    #expect(top(window, "F1", extent: 20) == 180, "F1 at \(String(describing: top(window, "F1", extent: 20)))")
    #expect(top(window, "F0", extent: 20) == 0, "F0 at \(String(describing: top(window, "F0", extent: 20)))")
    #expect(top(window, "H0", extent: 20) == nil, "headers are not pinned here")
}

/// **SP-I.** A pinned stack stays windowed: 3 sections of 100 rows (306 units) realise the window the unpinned
/// control realises and exactly the 2 pinned views outside it (header 0 and footer 0, far from the window at
/// offset 1000); none of the other 300 rows. Mutation: the pinned units realised for the whole section
/// (`pin.range` -> `section.all`: 100+ more units).
@Test @MainActor func aPinnedStackRealizesOnlyTheWindowAndThePinnedViews() throws {
    let control = try sectionsWindow(pinned: [])
    settle(control)
    scrollTo(control, offset: 1000)
    let window = try sectionsWindow(pinned: [.sectionHeaders, .sectionFooters])
    settle(window)
    scrollTo(window, offset: 1000)
    let baseline = control.lastFrameWork.lazyUnitsRealized
    #expect(baseline <= 15, "the control's window is \(baseline)")
    #expect(window.lastFrameWork.lazyUnitsRealized == baseline + 2,
            "pinned \(window.lastFrameWork.lazyUnitsRealized) vs control \(baseline)")
    #expect(window.lastFrameWork.lazyUnbounded == 0)
    let labels = Set(((try? window.elements(role: .staticText)) ?? []).compactMap { $0.label ?? $0.value })
    #expect(labels.contains("H0") && labels.contains("F0"), "the pinned views are in the tree")
}

/// **SP-G.** The pinned header is above the rows it covers, whether or not the window holds its unit. At offset 700
/// header 0 is outside the window and a click at (100, 10) reaches it; at offset 30 header 0 is in the window
/// (unit 0, natural place -30) and pinned at 0 over row 1, which sits at -10 ... 10, and a click at (100, 5)
/// reaches the header, not the row. Mutation: pinned boxes prepainted in unit order (the second click reaches row 1).
@Test @MainActor func aPinnedHeaderIsAboveTheRowsUnderIt() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0), pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(0..<100) { r in
                        ProposalText("r\(r)").frame(height: Pixels(20)).onTapGesture { log.add("row \(r)") }
                    }
                } header: {
                    ProposalText("H0").frame(height: Pixels(20)).onTapGesture { log.add("header") }
                }
            }
        }
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -30)
    settle(window)
    window.click(at: pt(100, 5))
    #expect(log.entries == ["header"], "header in the window: \(log.entries)")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -670)
    settle(window)
    window.click(at: pt(100, 10))
    #expect(log.entries == ["header", "header"], "header outside the window: \(log.entries)")
}

/// **SP-H.** Sections written directly in the stack (no `ForEach`) pin too, headers and footers: two sections of
/// 100 rows; at offset 1000 header 0 is at 0 and footer 0 at 180; at 2020 footer 1 takes the trailing edge and
/// header 0 still leads. Mutation: the footer role not recognised in `LazyUnitTable.sectionSpans` or
/// `LazySectionForEachSource.spans` (footer 0 absent).
@Test @MainActor func sectionsWrittenDirectlyInTheStackPinToo() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0), pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(0..<100) { r in ProposalText("a\(r)").frame(height: Pixels(20)) }
                } header: { ProposalText("H0").frame(height: Pixels(20)) }
                footer: { ProposalText("F0").frame(height: Pixels(20)) }
                Section {
                    ForEach(0..<100) { r in ProposalText("b\(r)").frame(height: Pixels(20)) }
                } header: { ProposalText("H1").frame(height: Pixels(20)) }
                footer: { ProposalText("F1").frame(height: Pixels(20)) }
            }
        }
    }
    settle(window)
    scrollTo(window, offset: 1000)
    #expect(top(window, "H0", extent: 20) == 0 && top(window, "F0", extent: 20) == 180,
            "H0 \(String(describing: top(window, "H0", extent: 20))) F0 \(String(describing: top(window, "F0", extent: 20)))")
    scrollTo(window, offset: 1020)
    #expect(top(window, "H0", extent: 20) == 0 && top(window, "F1", extent: 20) == 180,
            "H0 \(String(describing: top(window, "H0", extent: 20))) F1 \(String(describing: top(window, "F1", extent: 20)))")
}

/// **SP-J, divergence 915.** A lazy stack made eager by an `if` member lays its sections out in sequence and
/// pins nothing: header 0 is where the scroll left it, -200 at offset 200, though `pinnedViews` is set.
/// Mutation: pins computed for an unbounded plan (`plan.mode == .bounded` dropped; header 0 reads 0).
@Test @MainActor func anEagerLazyStackLaysItsSectionsOutInSequenceAndPinsNothing() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0), pinnedViews: .sectionHeaders) {
                ForEach(0..<3) { s in
                    Section {
                        ForEach(0..<20) { r in ProposalText("r\(s)-\(r)").frame(height: Pixels(20)) }
                    } header: { ProposalText("H\(s)").frame(height: Pixels(20)) }
                }
                if s3 { ProposalText("tail").frame(height: Pixels(20)) }
            }
        }
    }
    settle(window)
    #expect(window.lastFrameWork.lazyUnbounded == 1, "the stack is eager")
    scrollTo(window, offset: 200)
    #expect(top(window, "H0", extent: 20) == -200, "H0 at \(String(describing: top(window, "H0", extent: 20)))")
}
private let s3 = true

/// **SP-G.** A horizontal lazy stack pins along its axis: columns of 20 under headers of 30, the viewport
/// scrolled by 1000, header 0 is at the left edge. Mutation: `axis` ignored (header 0 absent).
@Test @MainActor func aLazyHStackPinsAlongItsAxis() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView(.horizontal) {
            LazyHStack(spacing: Pixels(0), pinnedViews: .sectionHeaders) {
                ForEach(0..<2) { s in
                    Section {
                        ForEach(0..<100) { c in ProposalText("c\(s)-\(c)").frame(width: Pixels(20)) }
                    } header: {
                        ProposalText("H\(s)").frame(width: Pixels(20))
                    }
                }
            }
        }
    }
    settle(window)
    window.scroll(at: pt(100, 100), byDeltaX: -1000, deltaY: 0)
    settle(window)
    let header = try #require(try window.elements(role: .staticText).first { ($0.label ?? $0.value) == "H0" })
    let left = header.frame.origin.x.value - (20 - header.frame.size.width.value) / 2
    #expect(left == 0, "header 0 at \(header.frame)")
}

/// **SP-H.** A `Section` outside a lazy stack is its header, content and footer in order, with no node or
/// identity of its own: in a `VStack` the heights stack to 30 + 2 x 20 + 30 and the order is header, rows,
/// footer. Mutation: `requestProposalGroupLayout` lays out the footer before the content.
@Test @MainActor func aSectionInAnOrdinaryStackIsItsPartsInSequence() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            Section {
                ProposalText("a").frame(height: Pixels(20))
                ProposalText("b").frame(height: Pixels(20))
            } header: {
                ProposalText("H").frame(height: Pixels(30))
            } footer: {
                ProposalText("F").frame(height: Pixels(30))
            }
        }
    }
    settle(window)
    let tops = ["H", "a", "b", "F"].map { top(window, $0, extent: $0 == "a" || $0 == "b" ? 20 : 30) }
    let first = try #require(tops.first ?? nil)
    #expect(tops.compactMap { $0 } == [first, first + 30, first + 50, first + 70], "\(tops)")
}
