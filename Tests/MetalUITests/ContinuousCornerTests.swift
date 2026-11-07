import Testing
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUIPath
@testable import MetalUI

// Continuous rounded corners (divergence 90, ruling CC-, record 226). SwiftUI's side is
// `docs/probes/swiftui-continuous-corners.swift` (arms CC0-CC10): its own Beziers, read through
// `Path.forEach`, are the literals below (printed to 4 or 6 digits, compared within 1e-4).

/// An element list in the probe's own print format: `M(x,y) L(x,y) C[c1x,c1y|c2x,c2y|x,y] Z`.
private func parse(_ text: String) -> [[Double]] {
    text.split(separator: " ").map { token -> [Double] in
        let tag: Double = token.first == "M" ? 0 : token.first == "L" ? 1 : token.first == "C" ? 2 : 3
        let numbers = token.dropFirst().split(whereSeparator: { "(),[]|".contains($0) }).compactMap { Double($0) }
        return [tag] + numbers
    }
}

/// A path's elements as `parse` reads them, without the degenerate cubics SwiftUI emits at a square corner (all
/// six numbers at the current point), which MetalUI leaves out: they add no length.
@MainActor private func elements(_ path: Path) -> [[Double]] {
    var out: [[Double]] = []
    var current = (0.0, 0.0)
    for e in path.storage.elements {
        switch e {
        case .move(let a): out.append([0, a.x, a.y]); current = (a.x, a.y)
        case .line(let a): out.append([1, a.x, a.y]); current = (a.x, a.y)
        case .quad(_, let a): out.append([1, a.x, a.y]); current = (a.x, a.y)
        case .cubic(let c1, let c2, let a):
            out.append([2, c1.x, c1.y, c2.x, c2.y, a.x, a.y]); current = (a.x, a.y)
        case .close: out.append([3])
        }
    }
    _ = current
    return out
}

private func withoutDegenerate(_ list: [[Double]]) -> [[Double]] {
    var out: [[Double]] = []
    var current = (0.0, 0.0)
    for e in list {
        if e[0] == 2 {
            let degenerate = stride(from: 1, to: 7, by: 2).allSatisfy { abs(e[$0] - current.0) < 1e-9 && abs(e[$0 + 1] - current.1) < 1e-9 }
            if degenerate { continue }
            current = (e[5], e[6])
        } else if e[0] == 0 || e[0] == 1 { current = (e[1], e[2]) }
        out.append(e)
    }
    return out
}

private func agree(_ got: [[Double]], _ expected: String, count: Int? = nil, tolerance: Double = 1e-4) -> String? {
    let want = withoutDegenerate(parse(expected))
    let have = withoutDegenerate(got)
    let n = count ?? want.count
    guard have.count >= n, want.count >= n else { return "\(have.count) elements, expected \(want.count)" }
    for i in 0..<n {
        guard have[i].count == want[i].count, zip(have[i], want[i]).allSatisfy({ abs($0 - $1) <= tolerance }) else {
            return "element \(i): \(have[i]) against \(want[i])"
        }
    }
    return nil
}

private let wide = gxRect(0, 0, 100, 60)

/// **CC-A** (probe CC1-CC4, CC9). The continuous outline is SwiftUI's own, element for element: the start (the right
/// edge between the top-right and bottom-right radii), the run down, the three cubics of a corner, a side shared by
/// radius, a corner cut back by its neighbour, and an elliptical `cornerSize` scaled by its ratio. **Mutations**:
/// the reach `1.528664947` replaced by 1.5 reddens every case; the clipped-room control arms (`a1 + b1 t`) by the
/// full-reach ones reddens `r 20` and the capsule; the start moved reddens each case's first element; the room of
/// a side by half the side reddens `TL20 TR10`.
@Test @MainActor func aContinuousCornerPathIsSwiftUIs() {
    let r5 = "M(100,30) L(100,52.356675) C[100,54.55755|100,55.657965|99.625443,56.84253] C[99.1547,58.13588|98.13588,59.1547|96.84253,59.625443] C[95.657965,60|94.55755,60|92.356675,60] L(7.643325,60)"
    #expect(agree(elements(RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: wide)), r5) == nil, "r 5: the whole curve fits")
    let r20 = "M(100,30) L(100,30) C[100,38.369539|100,42.684354|98.501772,47.37012] C[96.6188,52.54352|92.54352,56.6188|87.37012,58.501772] C[82.63186,60|78.2302,60|69.426701,60] L(30.573299,60)"
    #expect(agree(elements(RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: wide)), r20) == nil,
            "r 20 on 100x60: the vertical reach is cut to 30, its control arms follow the room")
    let capsule = "M(100.0000,30.0000) L(100.0000,30.0000) C[100.0000,31.2000|100.0000,35.4000|97.7527,41.0552] C[94.9282,48.8153|88.8153,54.9282|81.0552,57.7527] C[73.9478,60.0000|67.3453,60.0000|54.1401,60.0000] L(45.8599,60.0000) C[32.6547,60.0000|26.0522,60.0000|18.9448,57.7527] C[11.1847,54.9282|5.0718,48.8153|2.2473,41.0552] C[0.0000,35.4000|0.0000,31.2000|0.0000,30.0000] L(0.0000,30.0000) C[0.0000,28.8000|0.0000,24.6000|2.2473,18.9448] C[5.0718,11.1847|11.1847,5.0718|18.9448,2.2473] C[26.0522,0.0000|32.6547,0.0000|45.8599,0.0000] L(54.1401,0.0000) C[67.3453,0.0000|73.9478,0.0000|81.0552,2.2473] C[88.8153,5.0718|94.9282,11.1847|97.7527,18.9448] C[100.0000,24.6000|100.0000,28.8000|100.0000,30.0000] Z"
    #expect(agree(elements(Capsule().path(in: wide)), capsule, tolerance: 1e-3) == nil, "the capsule: room equals radius on the vertical side")
    let sharedSide = "M(100.0000,35.0000) L(100.0000,60.0000) L(0.0000,60.0000) L(0.0000,30.5733) C[0.0000,21.7698|0.0000,17.3681|1.4982,12.6299] C[3.3812,7.4565|7.4565,3.3812|12.6299,1.4982] C[17.3681,0.0000|21.7698,0.0000|30.5733,0.0000] L(84.7134,0.0000) C[89.1151,0.0000|91.3159,0.0000|93.6851,0.7491] C[96.2718,1.6906|98.3094,3.7282|99.2509,6.3149] C[100.0000,8.6841|100.0000,10.8849|100.0000,15.2866] Z"
    let uneven = UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                        topTrailingRadius: 10, style: .continuous)
    #expect(agree(elements(uneven.path(in: wide)), sharedSide, tolerance: 1e-3) == nil, "TL 20 and TR 10 on a top of 100: no clipping, start (100, 35)")
    let halves = "M(100.0000,42.5000) L(100.0000,60.0000) L(0.0000,60.0000) L(0.0000,38.2166) C[0.0000,27.2123|0.0000,21.7102|1.8728,15.7873] C[4.2265,9.3206|9.3206,4.2265|15.7873,1.8728] C[21.7102,0.0000|27.2123,0.0000|38.2166,0.0000] L(61.7834,0.0000) C[72.7877,0.0000|78.2898,0.0000|84.2127,1.8728] C[90.6794,4.2265|95.7735,9.3206|98.1272,15.7873] C[100.0000,21.7102|100.0000,27.2123|100.0000,38.2166] Z"
    let pair = UnevenRoundedRectangle(topLeadingRadius: 25, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                      topTrailingRadius: 25, style: .continuous)
    #expect(agree(elements(pair.path(in: wide)), halves, tolerance: 1e-3) == nil, "TL 25 and TR 25: each reaches 38.2166, short of half the top")
    let cutBack = "M(100.0000,30.0000) L(100.0000,60.0000) L(30.5733,60.0000) C[21.7698,60.0000|17.3681,60.0000|12.6299,58.5018] C[7.4565,56.6188|3.3812,52.5435|1.4982,47.3701] C[0.0000,43.6000|0.0000,40.8000|0.0000,40.0000] L(0.0000,40.0000) C[0.0000,38.4000|0.0000,32.8000|2.9965,25.2598] C[6.7624,14.9130|14.9130,6.7624|25.2598,2.9965] C[34.7363,0.0000|43.5396,0.0000|61.1466,0.0000] L(100.0000,0.0000)"
    let cut = UnevenRoundedRectangle(topLeadingRadius: 50, bottomLeadingRadius: 20, bottomTrailingRadius: 0,
                                     topTrailingRadius: 0, style: .continuous)
    #expect(agree(elements(cut.path(in: wide)), cutBack, tolerance: 1e-3) == nil,
            "TL 50 beside BL 20 on a side of 60: the larger is cut to 40 and the side is shared 40 to 20")
    let ellipse60 = "M(100,30) L(100,34.5223) C[100,41.8585|100,45.5265|96.2544,49.4751] C[91.547,53.7863|81.3588,57.1823|68.4253,58.7515] C[59,60|52,60|50,60]"
    #expect(agree(elements(Path(roundedRect: wide, cornerSize: Size(width: Pixels(60), height: Pixels(20)), style: .continuous)),
                  ellipse60, tolerance: 1e-3) == nil, "cornerSize 60x20 scales together to 50x16.667")
    let ellipse = "M(100,30) L(100,44.7134) C[100,49.1151|100,51.3159|97.7527,53.6851] C[94.9282,56.2718|88.8153,58.3094|81.0552,59.2509] C[73.9478,60|67.3453,60|54.1401,60]"
    #expect(agree(elements(Path(roundedRect: wide, cornerSize: Size(width: Pixels(30), height: Pixels(10)), style: .continuous)),
                  ellipse, tolerance: 1e-3) == nil, "cornerSize 30x10: the cubics scale by the radii")
    #expect(elements(RoundedRectangle(cornerRadius: 0, style: .continuous).path(in: wide))
                == [[0, 0, 0], [1, 100, 0], [1, 100, 60], [1, 0, 60], [3]], "no radius is a plain rectangle")
}

/// **CC-B** (probe CC3, CC3c). The uneven fit: the horizontal sides first (top, then bottom), then the vertical sides
/// on what they left. 2000 random radii matched SwiftUI, the circular style's likewise (847, 0 mismatches). The
/// four cases here are the first mismatches of the old simultaneous rule and its neighbours. **Mutation**: the
/// vertical sides fitted first (`fit` ordered right, left, top, bottom) reddens the first case.
@Test func theUnevenFitIsHorizontalSidesFirst() {
    func fit(_ w: Double, _ h: Double, _ tl: Double, _ tr: Double, _ br: Double, _ bl: Double) -> [Double] {
        let f = ContinuousCorner.fit(width: w, height: h, topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
        return [f.topLeft, f.topRight, f.bottomRight, f.bottomLeft]
    }
    func close(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.06 } }
    #expect(close(fit(83.6, 146.2, 0, 112.8, 108.8, 112.2), [0, 83.6, 41.8, 41.8]), "the bottom halves first, then the right side has room")
    #expect(close(fit(102.5, 106.4, 95, 32.3, 67.7, 111.2), [55.2, 32.3, 51.2, 51.2]))
    #expect(close(fit(57.8, 98.3, 113.9, 0, 47, 59.5), [57.8, 0, 28.9, 28.9]))
    #expect(close(fit(100, 60, 50, 0, 0, 20), [40, 0, 0, 20]), "the larger gives way")
    #expect(close(fit(100, 60, 30, 0, 0, 30), [30, 0, 0, 30]))
}

/// **CC-C** (probe CC0, CC2). `Capsule()` and `RoundedRectangle` default to `.continuous` and emit the new kind;
/// `.circular` still emits kind 0; a plain rectangle (no radius) stays kind 0 in either style. **Mutation**:
/// `primitiveShape` answering `.roundedRectangle` for every rounded rectangle reddens the first two arms.
@Test @MainActor func aContinuousShapeEmitsTheContinuousKind() throws {
    let continuous = PrimitiveShape.continuousRoundedRectangle.rawValue, circular = PrimitiveShape.roundedRectangle.rawValue
    let rr = paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(20)))
    try #require(rr.count == 1)
    #expect(rr[0].kind == continuous, "\(rr[0])")
    let capsule = paintedShapes(100, 60, Capsule())
    try #require(capsule.count == 1)
    #expect(capsule[0].kind == continuous)
    #expect(paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(20), style: .circular))[0].kind == circular)
    #expect(paintedShapes(100, 60, Capsule(style: .circular))[0].kind == circular)
    #expect(paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(0)))[0].kind == circular, "no radius: kind 0")
    #expect(paintedShapes(60, 60, Circle())[0].kind == circular, "Circle is circular whatever the default")
}

/// **CC-D**. The cost pin (§8 (i)): a continuous rounded rectangle is **one** `MUIRect` of kind 2, no raster, no
/// image, no group, no CPU path call; a `.circular` one is one rect of kind 0. **Mutation**: the continuous kind
/// routed through `Path` (a path fill) reddens the rect count and the image count.
@Test @MainActor func aContinuousRectCostsOneRect() throws {
    var root = RoundedRectangle(cornerRadius: Pixels(20)).fill(.accent)
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
    frame.render(&root)
    let scene = frame.finalizedScene()
    #expect(scene.rects.count == 1 && scene.images.isEmpty && scene.groups.isEmpty && scene.glyphs.isEmpty,
            "rects \(scene.rects.count) images \(scene.images.count) groups \(scene.groups.count)")
    #expect(scene.rects.first?.shapeKind == PrimitiveShape.continuousRoundedRectangle.rawValue)
    #expect(scene.rects.first?.cornerRadii == Corners(all: ScaledPixels(20)))
    var circular = RoundedRectangle(cornerRadius: Pixels(20), style: .circular).fill(.accent)
    let other = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
    other.render(&circular)
    let flat = other.finalizedScene()
    #expect(flat.rects.count == 1 && flat.images.isEmpty && flat.rects.first?.shapeKind == PrimitiveShape.roundedRectangle.rawValue)
}

/// **CC-E** (probe CC8). A continuous content shape hits inside its curve, not the circle: at r 100 in a 200 square
/// the curve passes (29.1507, 29.1507) on the diagonal where the circle passes (29.2893, 29.2893), so the point
/// (29.22, 29.22) is inside the continuous shape and outside the circular one. **Mutation**: `contains` ignoring the
/// style reddens the first arm.
@Test @MainActor func aContinuousContentShapeHitsItsCurve() {
    let square = gxRect(0, 0, 200, 200)
    let continuous = RoundedRectangle(cornerRadius: 100, style: .continuous).geometry(in: square)
    let circular = RoundedRectangle(cornerRadius: 100, style: .circular).geometry(in: square)
    let p = gxPoint(29.22, 29.22)
    #expect(continuous.contains(p), "inside SwiftUI's curve (probe CC8)")
    #expect(!circular.contains(p), "outside the circle: the arms separate")
    #expect(continuous.contains(gxPoint(100, 0.5)) && !continuous.contains(gxPoint(14.6, 14.6)))
}

/// **CC-F** (the plan's eligibility). `UnevenRoundedRectangle(.continuous)` is the renderer's rect while each
/// corner's curve stays in its quadrant, else a `Path` (a CPU raster, `PG-G`): TL 20 beside TR 10 is one kind-2
/// rect; a lone TL 45 on 100x60 (its curve reaches 60 down a side of 60) is one image. **Mutation**: eligibility
/// always true reddens the second arm (the clamp to half the shorter side would draw TL 30).
@Test @MainActor func anUnevenContinuousCornerPastItsQuadrantIsAPath() throws {
    let fits = paintedShapes(100, 60, UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0,
                                                              bottomTrailingRadius: 0, topTrailingRadius: 10, style: .continuous).fill(.accent))
    try #require(fits.count == 1)
    #expect(fits[0].kind == PrimitiveShape.continuousRoundedRectangle.rawValue, "\(fits[0])")
    var root = UnevenRoundedRectangle(topLeadingRadius: 45, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                      topTrailingRadius: 0, style: .continuous).fill(.accent)
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
    frame.render(&root)
    let scene = frame.finalizedScene()
    #expect(scene.rects.isEmpty && scene.images.count == 1, "rects \(scene.rects.count) images \(scene.images.count)")
    #expect(ContinuousCorner.fitsQuadrants(width: 100, height: 60, topLeft: 20, topRight: 10, bottomRight: 0, bottomLeft: 0))
    #expect(!ContinuousCorner.fitsQuadrants(width: 100, height: 60, topLeft: 45, topRight: 0, bottomRight: 0, bottomLeft: 0))
    #expect(ContinuousCorner.fitsQuadrants(width: 100, height: 60, topLeft: 30, topRight: 30, bottomRight: 30, bottomLeft: 30), "a capsule")
}

/// **CC-G** (probe CC5, CC5b). A continuous stroke keeps its radii whole for the shader, which squares a corner whose
/// inset radius is not positive: `strokeBorder(10)` on `RR(4)` emits the radius 4 (the circular kind zeroes it,
/// K11). **Mutation**: the `kept` rule applied to the continuous kind reddens it.
@Test @MainActor func aContinuousStrokeKeepsItsRadii() throws {
    let continuous = paintedShapes(100, 60, RoundedRectangle(cornerRadius: Pixels(4)).strokeBorder(.accent, lineWidth: Pixels(10)))
    try #require(continuous.count == 1)
    #expect(continuous[0].kind == PrimitiveShape.continuousRoundedRectangle.rawValue)
    var root = RoundedRectangle(cornerRadius: Pixels(4)).strokeBorder(.accent, lineWidth: Pixels(10))
    let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
    frame.render(&root)
    #expect(frame.finalizedScene().rects.first?.cornerRadii == Corners(all: ScaledPixels(4)), "the radius reaches the shader whole")
    var circular = RoundedRectangle(cornerRadius: Pixels(4), style: .circular).strokeBorder(.accent, lineWidth: Pixels(10))
    let other = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
    other.render(&circular)
    #expect(other.finalizedScene().rects.first?.cornerRadii == Corners(all: ScaledPixels(0)), "K11: the circular kind squares it on the CPU")
}

/// **CC-H**. The raster cache keys carry the shape kind, so a shadow or blur of the continuous rect never reads the
/// circular one's raster: after the circular shadow is cached, the same rect with only its style changed is a
/// **miss** (it makes coverage). **Mutation**: `key.add(r.shapeKind)` removed from `keyLeaf` reddens it.
@Test @MainActor func aRastersKeyCarriesTheShapeKind() throws {
    func tree(_ style: RoundedCornerStyle) -> some Element {
        RoundedRectangle(cornerRadius: Pixels(20), style: style).fill(.accent)
            .frame(width: Pixels(60), height: Pixels(40)).shadow(radius: Pixels(6), x: Pixels(2), y: Pixels(3))
    }
    let h = WrapperHarness()
    h.frame(0, nil, tree(.circular))
    h.frame(0.1, nil, tree(.circular))
    let cache = h.store.rasters
    h.frame(0.2, nil, tree(.circular))
    try #require(cache.lastRasterizedPixels == 0, "set up: the circular shadow hits")
    h.frame(0.3, nil, tree(.continuous))
    #expect(cache.lastRasterizedPixels > 0, "the continuous rect's shadow is a new raster")
    h.frame(0.4, nil, tree(.continuous))
    h.frame(0.5, nil, tree(.continuous))
    #expect(cache.lastRasterizedPixels == 0, "and then it hits")
}

/// **CC-I** (the shadow follows the curve). The CPU silhouette of a continuous rect is the continuous outline, not
/// the circle: the shadow raster of `RR(20, .continuous)` and of `.circular`, same size and offset, differ.
/// **Mutation**: `RasterMath.outline` answering the circular outline for kind 2 reddens it.
@Test @MainActor func aContinuousShapesShadowFollowsItsCurve() throws {
    func shadowPixels(_ style: RoundedCornerStyle) throws -> [UInt8] {
        var root = RoundedRectangle(cornerRadius: Pixels(20), style: style).fill(.accent)
            .frame(width: Pixels(100), height: Pixels(60)).shadow(color: .textPrimary, radius: Pixels(0.5), x: Pixels(0), y: Pixels(0))
        let frame = Frame(contentSize: Size(width: Pixels(100), height: Pixels(60)), scaleFactor: 1)
        frame.render(&root)
        let scene = frame.finalizedScene()
        let image = try #require(scene.images.first, "the shadow is an image")
        return try #require(scene.textures.first?.pixels, "\(image)")
    }
    #expect(try shadowPixels(.continuous) != shadowPixels(.circular), "the silhouette follows the curve")
}
