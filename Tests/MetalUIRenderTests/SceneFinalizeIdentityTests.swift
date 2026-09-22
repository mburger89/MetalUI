import Testing
import MetalUIShaderTypes
@testable import MetalUIRender
@testable import MetalUIScene  // DrawRun/AtlasSlot memberwise inits (PS-F)

// `Scene`'s side tables went from two `[PrimitiveKind: [Int]]` dictionaries to
// four plain `[Int]` arrays. That is a refactor of `finalize()`'s bookkeeping,
// so its acceptance is OUTPUT IDENTITY: the draw list and each kind's permuted
// order must be exactly what the dictionary version produced.
//
// **Where the expected values came from.** Every literal below was printed by a
// capture probe run against the UNMODIFIED `Scene` (commit 950d12f), before
// `Scene.swift` was edited, and then checked by hand against an independent
// rule — each pattern's paint order is its emission order stably sorted by
// `(layer, order)`, which is what the insertion-sequence tiebreak means. All six
// agreed, so no literal here is just the code under test echoing itself.

/// One emitted primitive: its kind, a unique id carried in `bounds.origin.x`,
/// the layer it was inserted at, and its `order`.
private typealias Emission = (kind: PrimitiveKind, id: Float, layer: Int, order: MUIUInt)

private func rect(id: Float, order: MUIUInt) -> MUIRect {
    MUIRect(bounds: MUIBounds(origin: MUIPoint(x: id, y: 0),
                              size: MUISize(width: 10, height: 10)),
            contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                   size: MUISize(width: 1000, height: 1000)),
            maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            background: MUIHsla(h: 0, s: 0, l: 0.5, a: 1),
            borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
            cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
            order: order, _reserved: 0)
}

private func glyph(id: Float, order: MUIUInt) -> MUIGlyph {
    MUIGlyph(bounds: MUIBounds(origin: MUIPoint(x: id, y: 0),
                               size: MUISize(width: 8, height: 12)),
             atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                    size: MUISize(width: 8, height: 12)),
             contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0),
                                    size: MUISize(width: 1000, height: 1000)),
             maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
             color: MUIHsla(h: 0, s: 0, l: 1, a: 1),
             order: order, _reserved: 0)
}

private func emit(_ script: [Emission], into scene: inout Scene) {
    for e in script {
        switch e.kind {
        case .rect: scene.insert(rect(id: e.id, order: e.order), layer: e.layer)
        case .glyph: scene.insert(glyph(id: e.id, order: e.order), layer: e.layer)
        }
    }
}

private let r = PrimitiveKind.rect
private let g = PrimitiveKind.glyph

private func run(_ kind: PrimitiveKind, _ start: Int, _ count: Int) -> DrawRun {
    DrawRun(kind: kind, start: start, count: count)
}

private struct Pattern {
    let name: String
    let script: [Emission]
    let runs: [DrawRun]
    let rectIDs: [Float]
    let glyphIDs: [Float]
}

/// Every id is unique across both kinds, so a primitive landing in the wrong
/// slot changes an id list, not only a count.
private let patterns: [Pattern] = [
    // Production's shape: `Frame.fill`/`Frame.draw` emit `order: 0` at
    // `activeLayer`, boxes and text interleaved, all on the root layer. The
    // sort is what turns rects-then-glyphs `merged` into this interleave.
    Pattern(name: "interleavedOneLayer",
            script: [(r, 1, 0, 0), (g, 2, 0, 0), (g, 3, 0, 0), (r, 4, 0, 0), (g, 5, 0, 0),
                     (g, 6, 0, 0), (g, 7, 0, 0), (r, 8, 0, 0), (r, 9, 0, 0), (g, 10, 0, 0)],
            runs: [run(r, 0, 1), run(g, 0, 2), run(r, 1, 1), run(g, 2, 3), run(r, 2, 2), run(g, 5, 1)],
            rectIDs: [1, 4, 8, 9], glyphIDs: [2, 3, 5, 6, 7, 10]),
    // `Frame.pushLayer()` mid-emission, `popLayer()` after: the hoisted
    // subtree's primitives arrive BETWEEN root-layer ones and must draw after
    // all of them, still interleaved by kind among themselves.
    Pattern(name: "pushLayerMidEmission",
            script: [(r, 1, 0, 0), (g, 2, 0, 0),
                     (r, 3, 1, 0), (g, 4, 1, 0), (g, 5, 1, 0),
                     (r, 6, 0, 0), (g, 7, 0, 0)],
            runs: [run(r, 0, 1), run(g, 0, 1), run(r, 1, 1), run(g, 1, 1), run(r, 2, 1), run(g, 2, 2)],
            rectIDs: [1, 6, 3], glyphIDs: [2, 7, 4, 5]),
    // Layers raised and lowered more than once, a third layer, and the kinds
    // swapping places across every boundary.
    Pattern(name: "nestedLayersRaisedAndLowered",
            script: [(g, 1, 0, 0), (r, 2, 1, 0), (g, 3, 2, 0), (r, 4, 2, 0), (g, 5, 1, 0),
                     (r, 6, 0, 0), (r, 7, 1, 0), (g, 8, 0, 0), (g, 9, 2, 0), (r, 10, 0, 0)],
            runs: [run(g, 0, 1), run(r, 0, 1), run(g, 1, 1), run(r, 1, 2), run(g, 2, 1),
                   run(r, 3, 1), run(g, 3, 1), run(r, 4, 1), run(g, 4, 1)],
            rectIDs: [6, 10, 2, 7, 4], glyphIDs: [1, 8, 5, 3, 9]),
    // Distinct and equal orders across two layers: order decides within a
    // layer, sequence breaks ties within an order, layer outranks both.
    Pattern(name: "mixedOrdersAndLayers",
            script: [(g, 1, 0, 5), (r, 2, 0, 5), (r, 3, 0, 1), (g, 4, 0, 1), (r, 5, 1, 0),
                     (g, 6, 0, 9), (g, 7, 1, 0), (r, 8, 0, 3), (g, 9, 1, 7), (r, 10, 1, 7)],
            runs: [run(r, 0, 1), run(g, 0, 1), run(r, 1, 1), run(g, 1, 1), run(r, 2, 1),
                   run(g, 2, 1), run(r, 3, 1), run(g, 3, 2), run(r, 4, 1)],
            rectIDs: [3, 8, 2, 5, 10], glyphIDs: [4, 1, 6, 7, 9]),
    Pattern(name: "glyphsOnly",
            script: [(g, 1, 1, 0), (g, 2, 0, 4), (g, 3, 0, 2), (g, 4, 1, 0)],
            runs: [run(g, 0, 4)],
            rectIDs: [], glyphIDs: [3, 2, 1, 4]),
    Pattern(name: "rectsOnly",
            script: [(r, 1, 0, 3), (r, 2, 1, 0), (r, 3, 0, 3), (r, 4, 0, 0)],
            runs: [run(r, 0, 4)],
            rectIDs: [4, 1, 3, 2], glyphIDs: []),
]

private func expectMatches(_ scene: Scene, _ p: Pattern, _ when: String) {
    #expect(scene.drawList == p.runs, "\(p.name), \(when): draw list")
    #expect(scene.rects.map(\.bounds.origin.x) == p.rectIDs, "\(p.name), \(when): rect order")
    #expect(scene.glyphs.map(\.bounds.origin.x) == p.glyphIDs, "\(p.name), \(when): glyph order")
}

/// Output identity on a fresh scene, for every pattern.
@Test func finalizeReproducesTheCapturedDrawListAndPerKindOrder() {
    for p in patterns {
        var scene = Scene()
        emit(p.script, into: &scene)
        scene.finalize()
        expectMatches(scene, p, "first finalize")
    }
}

/// A second `finalize()` reads the side tables back after they were permuted
/// — the ruling PF-1 / AP-G trap, across every pattern rather than one pair.
@Test func aSecondFinalizeReproducesTheCapturedOutput() {
    for p in patterns {
        var scene = Scene()
        emit(p.script, into: &scene)
        scene.finalize()
        scene.finalize()
        expectMatches(scene, p, "second finalize")
    }
}

/// `clear()` then re-emission on a scene that already held, and had finalized,
/// a DIFFERENT pattern: a side table or sequence counter that `clear()` left
/// stale would hand the new primitives the old pattern's layers or sequences.
@Test func aClearedSceneReEmittedReproducesTheCapturedOutput() {
    for (i, p) in patterns.enumerated() {
        let previous = patterns[(i + 1) % patterns.count]
        var scene = Scene()
        emit(previous.script, into: &scene)
        scene.finalize()
        scene.clear()
        emit(p.script, into: &scene)
        scene.finalize()
        expectMatches(scene, p, "after clear()")
    }
}

/// **The finding itself, as a count rather than a timing.** `insert` did a
/// `Dictionary` subscript per primitive and `finalize()` two per element, each
/// handing back a whole `[Int]` before the integer index, and `clear()`
/// replaced both dictionaries outright — dropping their arrays' capacity every
/// time. The fix is four plain `[Int]` side tables emptied with
/// `removeAll(keepingCapacity: true)`, like `rects`/`glyphs`/`drawList`.
///
/// Read through `Mirror` because the tables are `private`: this counts
/// `Dictionary`-typed and `[Int]`-typed stored properties and reads each
/// `[Int]`'s capacity after a `clear()`. `clear()` has no production caller
/// (`Frame` builds a fresh `Scene` per frame), so the capacity half pins the
/// method's contract, not a measured frame cost.
@Test func sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear() throws {
    let primitivesPerKind = 64
    var scene = Scene()
    for i in 0..<primitivesPerKind {
        scene.insert(rect(id: Float(2 * i), order: 0), layer: i % 2)
        scene.insert(glyph(id: Float(2 * i + 1), order: 0), layer: i % 3)
    }
    scene.finalize()
    scene.clear()

    // EXACT dynamic types, never `is`/`as?`: an EMPTY `[MUIRect]` casts
    // successfully to `[Int]` (there is no element to fail the cast), so after
    // `clear()` an `as? [Int]` filter also counts `rects`, `glyphs` and
    // `drawList`. Measured: on the dictionary version it counted 3 `[Int]`
    // tables, all three of them those empty primitive arrays.
    let children = Array(Mirror(reflecting: scene).children)
    let dictionaries = children
        .filter { String(describing: type(of: $0.value)).hasPrefix("Dictionary<") }
        .map { $0.label ?? "?" }
    #expect(dictionaries.isEmpty, "side tables held in dictionaries: \(dictionaries)")

    let intArrays = children.compactMap { child -> (label: String, array: [Int])? in
        guard type(of: child.value) == [Int].self, let array = child.value as? [Int] else { return nil }
        return (child.label ?? "?", array)
    }
    try #require(intArrays.count == 4,
                 "expected four [Int] side tables, found \(intArrays.map(\.label))")
    for table in intArrays {
        #expect(table.array.isEmpty, "\(table.label) is not empty after clear()")
        #expect(table.array.capacity >= primitivesPerKind,
                "\(table.label) dropped its capacity in clear(): \(table.array.capacity)")
    }
}
