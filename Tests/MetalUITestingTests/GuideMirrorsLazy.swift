import Foundation
import MetalUI
import MetalUITesting
import Testing

// The lazy containers' section of `docs/guides/layout.md` (item L1, lane 2; rulings `DG-C`, `DG-D`, `LZ-Q`):
// the mirrors of its two swift blocks, copied BY HAND between the `// guide:` and `// end guide` markers,
// byte for byte, so the ordinary build compiles them on every platform; `GuideDocCheck.swift` compares
// each region with its guide. Below the regions, the tests that run the blocks in a headless window and
// prove the claims the guide pins to them. Every top-level name carries the guide's topic as prefix
// (`DG-K`). Mutations: change the window of `LazyVStack`'s upper bound (13 becomes more), the minimum of the
// adaptive item (4 columns become 5).

// guide: layout #6
/// Ten thousand rows: only the rows near the viewport are built.
@MainActor
func layoutLazyRows() -> some Element {
    ProposalScrollView {
        LazyVStack(alignment: .leading, spacing: Pixels(0)) {
            ForEach(0..<10_000) { index in
                ProposalText("Row \(index)").frame(height: Pixels(20))
            }
        }
    }
    .frame(width: Pixels(200), height: Pixels(200))
}
// end guide

// guide: layout #7
/// Ten thousand cells: columns of at least 40 points, as many as fit.
@MainActor
func layoutLazyGrid() -> some Element {
    ProposalScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Pixels(40)))], spacing: Pixels(8)) {
            ForEach(0..<10_000) { index in
                ProposalText("\(index)").frame(height: Pixels(20))
            }
        }
    }
    .frame(width: Pixels(200), height: Pixels(200))
}
// end guide

/// **The guide's first block** (`LZ-E`, divergence 637). In a 200-point window of 20-point rows the lazy
/// stack builds 13 of its 10 000 rows (the ten on screen, the row holding the bottom edge's successor and two
/// more: 0 ..< 10 + 1 + 2), none unbounded, and the accessibility tree names exactly rows 0 ... 12.
/// Mutation: the window widened to `count` (10 000 realised).
@Test @MainActor func theLayoutGuideLazyRowsRealizeOnlyTheViewportAndTwoMore() throws {
    let window = try harnessWindow(size: sz(200, 200)) { layoutLazyRows() }
    window.tick(); window.tick()
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 13 && work.lazyUnbounded == 0, "\(work.lazyUnitsRealized) \(work.lazyUnbounded)")
    let labels = try window.elements(role: .staticText).compactMap(\.value)
    #expect(Set(labels) == Set((0..<13).map { "Row \($0)" }), "labels \(labels.sorted())")
}

/// **The guide's second block** (`LZ-K`, `LZ-L`, divergence 638). `.adaptive(minimum: 40)` in 200 points
/// with the default gap 8 packs n = floor((200 + 8) / 48) = 4 columns of (200 - 24) / 4 = 44; rows are 20 +
/// 8 = 28 apart, so the row holding the bottom edge is 200 / 28 = row 7, the window 0 ..< 7 + 1 + 2 = 10 rows
/// and the cells 40; the first frame has no width to pack from and builds one column. Mutation: the minimum
/// 40 -> 30 (n = floor(208 / 38) = 5, 50 cells).
@Test @MainActor func theLayoutGuideLazyGridPacksFourColumnsAndRealizesTenRows() throws {
    let window = try harnessWindow(size: sz(200, 200)) { layoutLazyGrid() }
    let first = try #require(window.frameWork.first)
    #expect(first.lazyUnitsRealized == 32, "first frame: one column, the cold slice: \(first.lazyUnitsRealized)")
    window.tick(); window.tick(); window.tick()
    let work = window.lastFrameWork
    #expect(work.lazyUnitsRealized == 40 && work.lazyLinesRealized == 10 && work.lazyUnbounded == 0,
            "\(work.lazyUnitsRealized) \(work.lazyLinesRealized) \(work.lazyUnbounded)")
    let labels = try window.elements(role: .staticText).compactMap(\.value)
    #expect(Set(labels) == Set((0..<40).map { "\($0)" }), "labels \(labels.sorted())")
}
