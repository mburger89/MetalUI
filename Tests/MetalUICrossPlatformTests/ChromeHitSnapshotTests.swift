import MetalUICore
import MetalUIPlatform
import Testing

// SDL custom chrome, lane 1 (rulings `CW-E`, `CW-G`, `CW-H`; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md`). `ChromeHitSnapshot.hit(at:)` is the
// **specification** the bridge's C `mui_chrome_hit` is checked against; `ChromeHitMap.carve` is the
// pure region function `Window` publishes through. Portable: plain Swift over geometry, so it runs on
// macOS, Linux and Windows (`CW-Q`: the spec's `Tests/MetalUIPlatformTests` is an AppKit target).

private func p(_ x: Float, _ y: Float) -> Point<Pixels> { Point(x: Pixels(x), y: Pixels(y)) }
private func r(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Bounds<Pixels> {
    Bounds(origin: p(x, y), size: Size(width: Pixels(w), height: Pixels(h)))
}

/// A 400 x 300 borderless window with the band as its one drag rect.
private func borderless(
    zoomedOrFullscreen: Bool = false, horizontal: Bool = true, vertical: Bool = true, border: Bool = true
) -> ChromeHitSnapshot {
    ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)),
                      dragRegions: [r(0, 0, 400, 32)], borderless: border,
                      zoomedOrFullscreen: zoomedOrFullscreen,
                      resizableHorizontally: horizontal, resizableVertically: vertical)
}

/// **1.1** (`CW-E`). A point in a drag rect is `.draggable`, one outside every rect is `.normal`.
/// Mutation: `hit` skips the rect loop (the first expectation reddens).
@Test func aPointInADragRectIsDraggable() {
    let snapshot = ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)),
                                     dragRegions: [r(20, 40, 100, 30), r(200, 100, 50, 50)])
    #expect(snapshot.hit(at: p(30, 50)) == .draggable)
    #expect(snapshot.hit(at: p(210, 120)) == .draggable)
    #expect(snapshot.hit(at: p(150, 50)) == .normal)
    #expect(snapshot.hit(at: p(30, 80)) == .normal)
}

/// **1.2** (`CW-E`). A rect is half-open on its max edges, as `Bounds.contains` is, so two rects sharing an
/// edge cannot both claim it. Mutation: `<` to `<=` on the max comparison.
@Test func aDragRectIsHalfOpenOnItsMaxEdges() {
    let snapshot = ChromeHitSnapshot(size: Size(width: Pixels(400), height: Pixels(300)),
                                     dragRegions: [r(20, 40, 100, 30)])
    #expect(snapshot.hit(at: p(20, 40)) == .draggable, "the min corner is inside")
    #expect(snapshot.hit(at: p(119.5, 69.5)) == .draggable)
    #expect(snapshot.hit(at: p(120, 50)) == .normal, "the max x is outside")
    #expect(snapshot.hit(at: p(50, 70)) == .normal, "the max y is outside")
}

/// **1.3** (`CW-E`). A point outside the window answers `.normal`, whatever the rects say.
@Test func aPointOutsideTheWindowIsNormal() {
    let snapshot = ChromeHitSnapshot(size: Size(width: Pixels(100), height: Pixels(100)),
                                     dragRegions: [r(0, 0, 500, 500)], borderless: true)
    #expect(snapshot.hit(at: p(150, 50)) == .normal)
    #expect(snapshot.hit(at: p(-1, 50)) == .normal)
    #expect(snapshot.hit(at: p(50, 100)) == .normal)
}

/// **1.4** (`CW-E`). Carving a blocker out of a candidate leaves the remainder only: a blocker inside the
/// band leaves a strip above, one below and one left and right of it, ordered top-to-bottom then
/// left-to-right. Mutation: `carve` ignores the blocker's y range (the strips above and below vanish).
@Test func aRectCarvedByABlockerLeavesTheRemainderOnly() {
    let carved = ChromeHitMap.carve(candidates: [r(0, 0, 400, 32)], blockers: [r(100, 4, 40, 20)], limit: 64)
    #expect(carved.rects == [r(0, 0, 400, 4), r(0, 4, 100, 20), r(140, 4, 260, 20), r(0, 24, 400, 8)])
    #expect(carved.truncated == 0)
}

/// **1.5** (`CW-E`). A blocker spanning the band's whole height leaves two rects; one outside the candidate
/// changes nothing; one covering it leaves none.
@Test func aSpanningBlockerSplitsAndAnOutsideBlockerChangesNothing() {
    let band = r(0, 0, 400, 32)
    #expect(ChromeHitMap.carve(candidates: [band], blockers: [r(100, 0, 40, 32)], limit: 64).rects
            == [r(0, 0, 100, 32), r(140, 0, 260, 32)])
    #expect(ChromeHitMap.carve(candidates: [band], blockers: [r(100, 100, 40, 32)], limit: 64).rects == [band])
    #expect(ChromeHitMap.carve(candidates: [band], blockers: [r(-10, -10, 500, 100)], limit: 64).rects.isEmpty)
}

/// **1.6** (`CW-E`). Overlapping candidates come out disjoint: a handle inside the band adds nothing, one
/// straddling its edge adds only the part outside. Mutation: skip the subtraction of earlier results.
@Test func overlappingCandidatesAreMadeDisjoint() {
    let band = r(0, 0, 400, 32)
    #expect(ChromeHitMap.carve(candidates: [band, r(300, 0, 100, 32)], blockers: [], limit: 64).rects == [band])
    #expect(ChromeHitMap.carve(candidates: [band, r(300, 20, 100, 40)], blockers: [], limit: 64).rects
            == [band, r(300, 32, 100, 28)])
}

/// **1.7** (`CW-G`). The order is corner, edge, drag rect, normal: at the band's top row a corner square
/// answers a corner, the 6-point top edge beats the drag rect, and below the edge the rect wins.
/// Mutation: test the drag rects before the edges (the second expectation reddens).
@Test func cornersBeatEdgesBeatDragRects() {
    let snapshot = borderless()
    #expect(snapshot.hit(at: p(3, 3)) == .resizeTopLeft)
    #expect(snapshot.hit(at: p(397, 3)) == .resizeTopRight)
    #expect(snapshot.hit(at: p(200, 3)) == .resizeTop, "the edge beats the band's drag rect")
    #expect(snapshot.hit(at: p(200, 10)) == .draggable)
    #expect(snapshot.hit(at: p(200, 150)) == .normal)
    #expect(snapshot.hit(at: p(3, 150)) == .resizeLeft)
    #expect(snapshot.hit(at: p(397, 150)) == .resizeRight)
    #expect(snapshot.hit(at: p(200, 297)) == .resizeBottom)
    #expect(snapshot.hit(at: p(3, 297)) == .resizeBottomLeft)
    #expect(snapshot.hit(at: p(397, 297)) == .resizeBottomRight)
}

/// **1.8** (`CW-G`). The edge is 6 points wide and the corner square 12: x 5.99 is an edge, 6 is not; a
/// point 11 in from both edges is a corner, 12 is the edge only. Mutation: border 6 to 7.
@Test func theBorderIsSixPointsAndTheCornerTwelve() {
    let snapshot = borderless()
    #expect(snapshot.hit(at: p(5.99, 150)) == .resizeLeft)
    #expect(snapshot.hit(at: p(6, 150)) == .normal)
    #expect(snapshot.hit(at: p(11, 200)) == .normal, "11 in from the left is not an edge")
    #expect(snapshot.hit(at: p(2, 11)) == .resizeTopLeft, "inside the 12 x 12 square")
    #expect(snapshot.hit(at: p(2, 12)) == .resizeLeft, "past the square: the left edge only")
    #expect(ChromeHitSnapshot.resizeBorder == 6)
}

/// **1.9** (`CW-G`). Never an edge on an axis whose limits are equal: with the horizontal axis fixed, the
/// sides answer `.normal`, the top and bottom still resize, and a corner is just the top edge.
/// Mutation: ignore `resizableHorizontally`.
@Test func noEdgeOnAnAxisWithEqualLimits() {
    let fixedWidth = borderless(horizontal: false)
    #expect(fixedWidth.hit(at: p(3, 150)) == .normal)
    #expect(fixedWidth.hit(at: p(397, 150)) == .normal)
    #expect(fixedWidth.hit(at: p(200, 3)) == .resizeTop)
    #expect(fixedWidth.hit(at: p(3, 3)) == .resizeTop, "a corner needs both axes")
    #expect(fixedWidth.hit(at: p(200, 297)) == .resizeBottom)
    let fixedHeight = borderless(vertical: false)
    #expect(fixedHeight.hit(at: p(200, 3)) == .draggable, "no top edge: the band's rect answers")
    #expect(fixedHeight.hit(at: p(3, 150)) == .resizeLeft)
    let fixed = borderless(horizontal: false, vertical: false)
    #expect(fixed.hit(at: p(3, 3)) == .draggable)
    #expect(fixed.hit(at: p(397, 297)) == .normal)
}

/// **1.10** (`CW-G`). A zoomed or fullscreen window has no edges (the drag rects stay answered).
/// Mutation: ignore `zoomedOrFullscreen`.
@Test func noEdgesWhenZoomedOrFullscreen() {
    let zoomed = borderless(zoomedOrFullscreen: true)
    #expect(zoomed.hit(at: p(3, 150)) == .normal)
    #expect(zoomed.hit(at: p(3, 3)) == .draggable)
    #expect(zoomed.hit(at: p(200, 297)) == .normal)
}

/// **1.11** (`CW-G`). A window that is not borderless has no edges: the system frame resizes itself.
/// Mutation: ignore `borderless`.
@Test func anUnborderedWindowHasNoEdges() {
    let bordered = borderless(border: false)
    #expect(bordered.hit(at: p(3, 150)) == .normal)
    #expect(bordered.hit(at: p(3, 3)) == .draggable)
    #expect(bordered.hit(at: p(397, 297)) == .normal)
}

/// **1.12** (`CW-E`). A list beyond the cap is cut and counted: 70 disjoint candidates under a limit of 64
/// answer 64 rects and `truncated == 6`; exactly 64 is not truncated. Mutation: the cap 64 to 65 (the
/// call's `limit` is `ChromeHitSnapshot.maximumRegions`, so the first two expectations redden).
@Test func aListBeyondSixtyFourRectsIsCappedAndCounted() {
    #expect(ChromeHitSnapshot.maximumRegions == 64)
    let candidates = (0..<70).map { r(Float($0) * 3, 0, 2, 2) }
    let capped = ChromeHitMap.carve(candidates: candidates, blockers: [],
                                    limit: ChromeHitSnapshot.maximumRegions)
    #expect(capped.rects.count == 64)
    #expect(capped.truncated == 6)
    #expect(capped.rects == Array(candidates.prefix(64)), "the first 64 in reading order survive")
    let exact = ChromeHitMap.carve(candidates: Array(candidates.prefix(64)), blockers: [],
                                   limit: ChromeHitSnapshot.maximumRegions)
    #expect(exact.rects.count == 64 && exact.truncated == 0)
}

/// **1.13** (`CW-E`). The result is ordered top-to-bottom then left-to-right and deduplicated by value,
/// whatever order the candidates came in. Mutation: drop the sort.
@Test func theResultIsInReadingOrderAndDeduplicated() {
    let carved = ChromeHitMap.carve(candidates: [r(200, 100, 10, 10), r(0, 0, 10, 10), r(0, 0, 10, 10), r(50, 0, 10, 10)],
                                    blockers: [], limit: 64)
    #expect(carved.rects == [r(0, 0, 10, 10), r(50, 0, 10, 10), r(200, 100, 10, 10)])
}
