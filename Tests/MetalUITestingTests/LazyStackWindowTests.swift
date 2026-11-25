import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// Lazy containers, lane 1: the stacks through a real `Window` over the harness (spec section 5,
// tests 2.1, 2.2, 2.4b, 2.7, 2.12-2.16; rulings `LZ-E`, `LZ-H`, `LZ-I`, `LZ-J`, `LZ-O`, `LZ-P`,
// `LZ-R`). Counts, never time: `FrameWork` carries the three lazy counters beside the element work,
// and an eager `VStack` of the same 10 000 rows is the ratio's other side. Rows are 20 points
// tall unless a test says otherwise, in a 200 x 200 window: 10 on screen, 13 realised (the row
// holding the bottom edge + 1, + 2 overscan, divergence 637).
//
// Red-before (record section 134): the types did not exist, so the file failed to compile.

@MainActor private func present(_ window: TestWindow) throws -> [String] {
    try window.elements(role: .staticText).compactMap(\.value)
}

/// A window of `count` text rows (`Text` so the accessibility tree names each) in a lazy stack.
@MainActor private func textWindow(count: Int = 10_000, height: @escaping (Int) -> Float = { _ in 20 })
    throws -> TestWindow {
    try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<count) { index in ProposalText("row \(index)").frame(height: Pixels(height(index))) }
            }
        }
    }
}

/// **2.1 (`LZ-E`, `LZ-I`).** A 10 000-row lazy stack in a 200-point scroller realises the window,
/// and only the window: warm, **13** units and lines (rows of 20: the bottom edge 200 is in row 10,
/// 0 ..< 10 + 1 + 2), one container not unbounded, against an eager `VStack` of the same 10 000
/// rows whose element requests are at least **500 times** the lazy stack's (derived: 10 000 / 13 =
/// 769 at one request per row). Mutation: the window's upper bound widened to `count`.
@Test @MainActor func aTenThousandChildLazyVStackRealizesOnlyTheWindow() throws {
    let lazy = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<10_000) { _ in Color.gray.frame(height: Pixels(20)) }
            }
        }
    }
    lazy.tick(); lazy.tick()
    let work = lazy.lastFrameWork
    #expect(work.lazyUnitsRealized == 13 && work.lazyLinesRealized == 13 && work.lazyUnbounded == 0,
            "\(work.lazyUnitsRealized) \(work.lazyLinesRealized) \(work.lazyUnbounded)")

    let eager = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            VStack(spacing: Pixels(0)) {
                ForEach(0..<10_000) { _ in Color.gray.frame(height: Pixels(20)) }
            }
        }
    }
    eager.tick(); eager.tick()
    #expect(eager.lastFrameWork.lazyUnitsRealized == 0, "a VStack counts no lazy unit")
    #expect(work.elementRequests > 0)
    #expect(eager.lastFrameWork.elementRequests >= 500 * work.elementRequests,
            "eager \(eager.lastFrameWork.elementRequests) vs lazy \(work.elementRequests)")
}

/// **2.2 (`LZ-E`).** The cold frame (the scroller's viewport unknown) realises a BOUNDED slice - the
/// first **32** of 10 000 - not every row as a `List` does; the frame after it realises the viewport's 13.
/// Mutation: the cold slice `32` -> `count` (10 000 realised in frame 1).
@Test @MainActor func theColdFrameRealizesABoundedSliceThenTheViewportWindow() throws {
    let window = try textWindow()
    let first = try #require(window.frameWork.first)
    #expect(first.lazyUnitsRealized >= 32 && first.lazyUnitsRealized < 200, "cold: \(first.lazyUnitsRealized)")
    window.tick(); window.tick()
    #expect(window.lastFrameWork.lazyUnitsRealized == 13)
}

/// **2.4b (`LZ-E`, `LZ-J`).** A wheel to the 100th row realises the new window, and the accessibility
/// tree holds exactly the realised rows: ids 98 ... 112 (15 of them, 100 on top, derived at 2.4a), not
/// row 0 and not row 500. Mutation: the window not recomputed on scroll (rows 0 ... 12 stay).
@Test @MainActor func scrollingRealizesTheNewWindowAndTheAccessibilityTreeFollows() throws {
    let window = try textWindow()
    window.tick(); window.tick()
    #expect(try present(window).sorted() == (0..<13).map { "row \($0)" }.sorted())
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick(); window.tick()
    let labels = try present(window)
    #expect(Set(labels) == Set((98...112).map { "row \($0)" }), "labels \(labels.sorted())")
    #expect(window.lastFrameWork.lazyUnitsRealized == 15)
}

private final class Serials {
    var next = 0
    var seen: [Int: Int] = [:]
    func mint() -> Int { next += 1; return next }
}

private struct StateRow: Component {
    let index: Int
    let serials: Serials
    @State private var serial = 0
    var content: some ProposalElementGroup {
        let _ = serials.seen[index] = serial
        ProposalText("row \(index)").frame(height: Pixels(20))
            .onAppear { if serial == 0 { serial = serials.mint() } }
    }
}

/// **2.7 (`LZ-H`, `TB-AH`).** A scrolled-out child keeps its `@State`: row 0 mints a serial on its
/// first appearance, the window moves to row 100 (row 0 unrealised) and back, and row 0 still holds
/// the same serial (SwiftUI: probe S1, one serial across a 4000-point round trip).
/// Mutation: `noteLoop` called by the lazy `ForEach` (the departed element is reset at once: row 0
/// returns fresh with a new serial).
@Test @MainActor func aScrolledOutChildKeepsItsStateAndTheTableBoundsIt() throws {
    let serials = Serials()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { StateRow(index: $0, serials: serials) }
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    let first = serials.seen[0]
    #expect(first != nil && first != 0, "row 0's first serial \(String(describing: first))")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick(); window.tick()
    #expect(serials.seen[100] != nil && serials.seen[100] != 0)
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 4000)
    window.tick(); window.tick(); window.tick()
    #expect(serials.seen[0] == first, "after the round trip \(String(describing: serials.seen[0]))")
}

/// **2.7b (`LZ-H`, `TB-AH`).** The retention is BOUNDED, as a `List` row's: after the window has walked
/// through some 400 rows (more than 256 state entries) and returned to the top, row 0, more than two
/// generations out, starts fresh - a new serial. SwiftUI's retention looked unbounded in the one arm
/// run (probe S1), so this is the existing `TB-AH` family (divergence 84), no new label; the
/// documented rule is "keep durable values in data". Pins the claim, not a mutation of the lazy code.
@Test @MainActor func aScrolledOutChildLosesItsStateOnceTheTableIsLargeAndFarBehind() throws {
    let serials = Serials()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { StateRow(index: $0, serials: serials) }
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    let first = try #require(serials.seen[0])
    #expect(first != 0)
    for _ in 0..<45 {
        window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -200)
        window.tick()
    }
    #expect(serials.seen[400] != nil && serials.seen[400] != 0, "the walk reached row 400")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: 100_000)
    window.tick(); window.tick(); window.tick()
    let again = try #require(serials.seen[0])
    #expect(again != first, "row 0 returned with serial \(again), its first was \(first)")
}

/// **2.12 (`LZ-A`, `PE-C`).** A realised child is an ordinary occurrence: a click on a `Button` in a
/// realised row fires it, Tab walks the realised rows' buttons (row 0 first), and a row out of the window
/// has no element at all. The rows are legacy `Button`s, so this also runs the legacy `ForEach` path
/// (`LZ-S`). Mutation: hit registration skipped for units (the click fires nothing).
@Test @MainActor func aRealizedChildsHitTestingFocusAndButtonsAreOrdinary() throws {
    let log = HarnessLog()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { index in Button("Tap \(index)") { log.add("tap \(index)") } }
            }
        }
    }
    window.tick(); window.tick()
    try window.click(try window.element(label: "Tap 0"))
    #expect(log.entries == ["tap 0"], "\(log.entries)")
    #expect(throws: TestHarnessError.self) { try window.element(label: "Tap 500") }
    window.typeKey(.tab)
    #expect(try window.focusedElement?.label == "Tap 0")
    window.typeKey(.tab)
    #expect(try window.focusedElement?.label == "Tap 1")
}

private struct EqRow: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        Text("row \(index)").frame(width: Pixels(100), height: Pixels(20))
    }
    static func == (l: EqRow, r: EqRow) -> Bool { l.index == r.index }
}

/// **2.13 (`LZ-P`).** An `.equatable()` row in a lazy stack is an ordinary retained occurrence (legacy
/// content, so the legacy `ForEach` path, `LZ-S`): the window stays 13 rows, and a redraw with nothing
/// changed skips every row's getter (13 skips, 0 evaluations) instead of re-evaluating it. Under
/// `METALUI_VERIFY_RETAINED=1` the suite's own run builds each replay twice and traps on a difference.
/// Mutation: a unit box rebuilt so the memo key differs every frame (skips 0).
@Test @MainActor func anEquatableChildInsideALazyStackIsSkippedAndRetained() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { EqRow(index: $0).equatable() }
            }
        }
    }
    window.tick(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 13, "\(work.lazyUnitsRealized)")
    #expect(work.contentSkips == 13 && work.contentEvaluations == 0,
            "skips \(work.contentSkips) evaluations \(work.contentEvaluations)")
}

/// **2.13b (`LZ-S`).** Legacy STATIC members are units too, not an eager fallback: a legacy `Text` with a
/// legacy `.frame`, an `.equatable()` component and a `Button` as the three children of a lazy stack in a
/// scroller are three realised units, none of them counted unbounded, and the button is an ordinary
/// element. Mutation: `LegacyContent` not read as a unit source (the container turns eager:
/// `lazyUnbounded` 1).
@Test @MainActor func legacyStaticMembersAreUnitsAndNotAnEagerFallback() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                Text("legacy one").frame(width: Pixels(100), height: Pixels(20))
                EqRow(index: 1).equatable()
                Button("Tap") {}
            }
        }
    }
    window.tick(); window.tick()
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 3 && work.lazyUnbounded == 0,
            "units \(work.lazyUnitsRealized) unbounded \(work.lazyUnbounded)")
    _ = try window.element(label: "Tap")
    _ = try window.element(label: "row 1")
}

private final class ProxyBox {
    var proxy: ScrollViewProxy?
    @MainActor func keep(_ proxy: ScrollViewProxy) -> Bool { self.proxy = proxy; return true }
}

/// **2.14 (`LZ-O`, probe T10, `VL-H`, `VL-P`).** `scrollTo` reaches a row that was never realised, through
/// the index: rows 0 ... 599 are 20 tall and 600 ... 999 are 80 (the estimate from the first rows,
/// 20, is wrong by 6000 for row 700, whose true offset is 600 x 20 + 100 x 80 = 20 000), the request
/// lands on the estimate and the refinement carried into the next frame brings row 700 into the
/// 200-point viewport; it stays there. Mutation: the refinement carry removed (row 700 stays off screen).
@Test @MainActor func scrollToAnUnrealizedElementReachesItInAtMostTwoResolutions() throws {
    let box = ProxyBox()
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ScrollViewReader { proxy in
                let _ = box.keep(proxy)
                ProposalScrollView {
                    LazyVStack(spacing: Pixels(0)) {
                        ForEach(0..<1000) { index in
                            ProposalText("row \(index)").frame(height: Pixels(index < 600 ? 20 : 80))
                        }
                    }
                }
            }
        }
    }
    window.tick(); window.tick()
    #expect(throws: TestHarnessError.self) { try window.element(label: "row 700") }
    box.proxy?.scrollTo(700)
    for _ in 0..<3 { window.tick() }
    let row = try window.element(label: "row 700")
    #expect(row.frame.origin.y >= Pixels(0) && row.frame.origin.y + row.frame.size.height <= Pixels(200),
            "row 700 at \(row.frame)")
    window.tick(); window.tick()
    #expect(try window.element(label: "row 700").frame == row.frame, "the target stays put")
}

/// **2.15 (divergence 637).** The overscan is visible to the app: 13 rows are present (`onAppear` seen
/// and `onDisappear` not) where 10 are on screen - the viewport's 200 / 20 plus one and two more.
/// Mutation: overscan 2 -> 0 (11 present).
@Test @MainActor func theOverscanAppearsBeforeTheRowsAreOnScreen() throws {
    let present = PresentSet()
    let window = try harnessWindow(size: sz(200, 200)) {
        ProposalScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { index in
                    ProposalText("row \(index)").frame(height: Pixels(20))
                        .onAppear { present.rows.insert(index) }
                        .onDisappear { present.rows.remove(index) }
                }
            }
        }
    }
    window.tick(); window.tick(); window.tick()
    #expect(present.rows == Set(0..<13), "present \(present.rows.sorted())")
}

private final class PresentSet { var rows: Set<Int> = [] }

/// **2.16 (`LZ-F`, `LZ-R`, `IV-`).** A lazy container taints its ancestors for the layout memo: with a
/// `VStack` around the scroller no frame (a plain redraw, a scroll) is served by a whole-placement or
/// keyed hit, and the rows after a scroll are the new window's. Mutation: make `LazyStackLayout`
/// `Hashable` over its visible fields (axis, alignment, spacing) - a root hit appears on the warm frame.
@Test @MainActor func aLazyContainerTaintsItsAncestorsAndAMemoHitIsNeverStale() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        VStack(spacing: Pixels(0)) {
            ProposalScrollView {
                LazyVStack(spacing: Pixels(0)) {
                    ForEach(0..<1000) { _ in Color.gray.frame(height: Pixels(20)) }
                }
            }
        }
    }
    window.tick(); window.tick()
    window.window.setNeedsRedraw(); window.tick()
    #expect(window.lastFrameWork.layoutMemoRootHits == 0, "warm root hits \(window.lastFrameWork.layoutMemoRootHits)")
    window.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: -2000)
    window.tick()
    #expect(window.lastFrameWork.layoutMemoRootHits == 0, "scroll root hits \(window.lastFrameWork.layoutMemoRootHits)")
    #expect(window.lastFrameWork.lazyUnitsRealized == 15, "\(window.lastFrameWork.lazyUnitsRealized)")
}

/// **2.1b (`PE-V`).** The legacy `ScrollView` publishes the same scroll context, so the idiom
/// `ScrollView { LazyVStack { ForEach } }` windows too: 13 of 1000 realised, none unbounded.
/// Mutation: the window widened to `count` (M7) reddens it with 2.1.
@Test @MainActor func aLazyStackInALegacyScrollViewIsWindowedToo() throws {
    let window = try harnessWindow(size: sz(200, 200)) {
        ScrollView {
            LazyVStack(spacing: Pixels(0)) {
                ForEach(0..<1000) { index in ProposalText("row \(index)").frame(height: Pixels(20)) }
            }
        }
    }
    window.tick(); window.tick()
    #expect(window.lastFrameWork.lazyUnitsRealized == 13 && window.lastFrameWork.lazyUnbounded == 0,
            "\(window.lastFrameWork.lazyUnitsRealized) \(window.lastFrameWork.lazyUnbounded)")
}
