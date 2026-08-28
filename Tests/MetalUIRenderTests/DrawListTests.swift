import Testing
import MetalUIShaderTypes
@testable import MetalUIRender

private func rect(order: MUIUInt) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                              size: MUISize(width: 10, height: 10)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                   size: MUISize(width: 1000, height: 1000)),
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: order, _reserved: 0)
}

private func glyph(order: MUIUInt) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                               size: MUISize(width: 8, height: 12)),
             atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                    size: MUISize(width: 8, height: 12)),
             contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                    size: MUISize(width: 1000, height: 1000)),
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: order, _reserved: 0)
}

/// The draw list is the whole of spec §7.3's promise: "draw-call count is the
/// number of type transitions in z-order". Before it, `encode` drew every rect
/// and then every glyph, so a rect could never occlude text.
@Test func theDrawListIsOneRunPerTypeTransitionInZOrder() throws {
    var scene = Scene()
    scene.insert(rect(order: 0))
    scene.insert(glyph(order: 1))
    scene.insert(rect(order: 2))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 3, "expected 3 type transitions, got \(runs.count)")
    #expect(runs[0].kind == .rect  && runs[0].start == 0 && runs[0].count == 1)
    #expect(runs[1].kind == .glyph && runs[1].start == 0 && runs[1].count == 1)
    #expect(runs[2].kind == .rect  && runs[2].start == 1 && runs[2].count == 1)
}

/// Consecutive same-kind primitives coalesce — that is what keeps the count at
/// "type transitions" rather than "primitives".
@Test func consecutiveSameKindPrimitivesCoalesceIntoOneRun() throws {
    var scene = Scene()
    scene.insert(rect(order: 0))
    scene.insert(rect(order: 1))
    scene.insert(glyph(order: 2))
    scene.insert(glyph(order: 3))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 2, "expected 2 runs, got \(runs.count)")
    #expect(runs[0].kind == .rect  && runs[0].count == 2)
    #expect(runs[1].kind == .glyph && runs[1].count == 2)
}

/// **The tiebreak is load-bearing.** `finalize()`'s existing comment says
/// "painters at the same layer must stack predictably". A merged sort across two
/// arrays has no inherent order between them, so insertion sequence must be
/// carried explicitly — without it, equal-order rects and glyphs interleave
/// arbitrarily and a container's background can land on top of its own text.
@Test func equalOrdersKeepEmissionSequenceAcrossTypes() throws {
    var scene = Scene()
    scene.insert(glyph(order: 5))
    scene.insert(rect(order: 5))
    scene.finalize()

    let runs = scene.drawList
    try #require(runs.count == 2)
    #expect(runs[0].kind == .glyph, "the glyph was emitted first and must draw first")
    #expect(runs[1].kind == .rect)
}

/// Each kind's array is permuted so every run is contiguous within it. A run
/// that pointed at a non-contiguous span would draw the wrong instances.
@Test func eachRunIndexesAContiguousSpanOfItsOwnArray() throws {
    var scene = Scene()
    scene.insert(rect(order: 10))
    scene.insert(glyph(order: 0))
    scene.insert(rect(order: 20))
    scene.insert(glyph(order: 30))
    scene.finalize()

    // z-order: glyph(0), rect(10), rect(20), glyph(30) -> 3 runs
    let runs = scene.drawList
    try #require(runs.count == 3, "expected 3 runs, got \(runs.count)")
    #expect(runs[0].kind == .glyph && runs[0].start == 0 && runs[0].count == 1)
    #expect(runs[1].kind == .rect  && runs[1].start == 0 && runs[1].count == 2)
    #expect(runs[2].kind == .glyph && runs[2].start == 1 && runs[2].count == 1)
    // And the arrays are in z-order within themselves.
    #expect(scene.rects.map(\.order) == [10, 20])
    #expect(scene.glyphs.map(\.order) == [0, 30])
}

/// An empty scene produces no runs, so `encode`'s early return stays correct.
@Test func anEmptySceneHasAnEmptyDrawList() {
    var scene = Scene()
    scene.finalize()
    #expect(scene.drawList.isEmpty)
}

/// **Ruling PF-1.** The brief's first draft of `finalize()` permuted `rects`
/// and `glyphs` into global order but left the `sequence` arrays unpermuted —
/// after one `finalize()` those arrays no longer line up with their
/// primitives, so a second `finalize()` on the same scene would tiebreak with
/// stale sequence numbers and could silently reorder equal-order primitives
/// differently the second time. `finalize()` must be idempotent: calling it
/// twice on a scene holding equal-order primitives of both kinds must produce
/// the identical draw list both times.
@Test func finalizingTwiceGivesTheSameDrawList() throws {
    var scene = Scene()
    scene.insert(glyph(order: 5))
    scene.insert(rect(order: 5))
    scene.insert(rect(order: 1))
    scene.insert(glyph(order: 1))

    scene.finalize()
    let runsAfterFirst = scene.drawList
    let rectsAfterFirst = scene.rects
    let glyphsAfterFirst = scene.glyphs

    scene.finalize()
    let runsAfterSecond = scene.drawList

    try #require(runsAfterFirst.count == runsAfterSecond.count)
    #expect(runsAfterFirst == runsAfterSecond)
    #expect(scene.rects.map(\.order) == rectsAfterFirst.map(\.order))
    #expect(scene.glyphs.map(\.order) == glyphsAfterFirst.map(\.order))
}
