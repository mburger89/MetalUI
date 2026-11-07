import Testing
@testable import MetalUIPath

// SwiftUI's continuous corner (divergence 90, ruling CC-, record 226) in `MetalUIPath`, which is portable: these run on
// Linux and Windows CI too. The literals are SwiftUI's own Beziers, read through `Path.forEach` by
// `docs/probes/swiftui-continuous-corners.swift` (CC1, CC2, CC4); the public-`Path` and renderer tests are
// `MetalUITests/ContinuousCornerTests` and `MetalUIRenderTests/ContinuousCornerRenderTests`.

/// The probe's print format, `M(x,y) L(x,y) C[c1x,c1y|c2x,c2y|x,y] Z`, to numbers: tag 0 M, 1 L, 2 C, 3 Z.
private func parse(_ text: String) -> [[Double]] {
    text.split(separator: " ").map { token -> [Double] in
        let tag: Double = token.first == "M" ? 0 : token.first == "L" ? 1 : token.first == "C" ? 2 : 3
        return [tag] + token.dropFirst().split(whereSeparator: { "(),[]|".contains($0) }).compactMap { Double($0) }
    }
}

private func elements(_ g: PathGeometry) -> [[Double]] {
    g.elements.map { e -> [Double] in
        switch e {
        case .move(let a): return [0, a.x, a.y]
        case .line(let a): return [1, a.x, a.y]
        case .quad(_, let a): return [1, a.x, a.y]
        case .cubic(let c1, let c2, let a): return [2, c1.x, c1.y, c2.x, c2.y, a.x, a.y]
        case .close: return [3]
        }
    }
}

/// Without the degenerate cubics SwiftUI emits at a square corner.
private func nondegenerate(_ list: [[Double]]) -> [[Double]] {
    var out: [[Double]] = []
    var current = (0.0, 0.0)
    for e in list {
        if e[0] == 2 {
            if stride(from: 1, to: 7, by: 2).allSatisfy({ abs(e[$0] - current.0) < 1e-9 && abs(e[$0 + 1] - current.1) < 1e-9 }) { continue }
            current = (e[5], e[6])
        } else if e[0] < 2 { current = (e[1], e[2]) }
        out.append(e)
    }
    return out
}

private func matches(_ g: PathGeometry, _ expected: String, tolerance: Double) -> Bool {
    let have = nondegenerate(elements(g)), want = nondegenerate(parse(expected))
    guard have.count == want.count else { return false }
    return zip(have, want).allSatisfy { $0.count == $1.count && zip($0, $1).allSatisfy { abs($0 - $1) <= tolerance } }
}

private func continuousRect(_ w: Double, _ h: Double, _ tl: Double, _ tr: Double, _ br: Double, _ bl: Double) -> PathGeometry {
    var g = PathGeometry()
    let f = ContinuousCorner.fit(width: w, height: h, topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
    g.addContinuousRoundedRect(x: 0, y: 0, width: w, height: h, topLeft: f.topLeft, topRight: f.topRight,
                               bottomRight: f.bottomRight, bottomLeft: f.bottomLeft)
    return g
}

/// SwiftUI's outline, element for element (probe CC1/CC2): a corner whose reach fits (r 5), one whose vertical reach is
/// cut to the half side so its control arms follow the room (r 20 on 100 x 60), the capsule, and a side shared by
/// radius (TL 20, TR 10). **Mutations**: the reach 1.528664947 as 1.5 reddens all four; `a1`/`b1` swapped for the
/// full-reach arms reddens the r 20 and capsule arms; the room of a shared side as half the side reddens the last.
@Test func theContinuousOutlineIsSwiftUIsElementForElement() {
    #expect(matches(continuousRect(100, 60, 5, 5, 5, 5),
                    "M(100,30) L(100,52.356675) C[100,54.55755|100,55.657965|99.625443,56.84253] C[99.1547,58.13588|98.13588,59.1547|96.84253,59.625443] C[95.657965,60|94.55755,60|92.356675,60] L(7.643325,60) C[5.44245,60|4.342035,60|3.15747,59.625443] C[1.86412,59.1547|0.8453,58.13588|0.374557,56.84253] C[0,55.657965|0,54.55755|0,52.356675] L(0,7.643325) C[0,5.44245|0,4.342035|0.374557,3.15747] C[0.8453,1.86412|1.86412,0.8453|3.15747,0.374557] C[4.342035,0|5.44245,0|7.643325,0] L(92.356675,0) C[94.55755,0|95.657965,0|96.84253,0.374557] C[98.13588,0.8453|99.1547,1.86412|99.625443,3.15747] C[100,4.342035|100,5.44245|100,7.643325] Z",
                    tolerance: 1e-4), "r 5: the whole curve fits")
    #expect(matches(continuousRect(100, 60, 20, 20, 20, 20),
                    "M(100,30) L(100,30) C[100,38.369539|100,42.684354|98.501772,47.37012] C[96.6188,52.54352|92.54352,56.6188|87.37012,58.501772] C[82.63186,60|78.2302,60|69.426701,60] L(30.573299,60) C[21.7698,60|17.36814,60|12.62988,58.501772] C[7.45648,56.6188|3.3812,52.54352|1.498228,47.37012] C[0,42.684354|0,38.369539|0,30] L(0,30) C[0,21.630461|0,17.315646|1.498228,12.62988] C[3.3812,7.45648|7.45648,3.3812|12.62988,1.498228] C[17.36814,0|21.7698,0|30.573299,0] L(69.426701,0) C[78.2302,0|82.63186,0|87.37012,1.498228] C[92.54352,3.3812|96.6188,7.45648|98.501772,12.62988] C[100,17.315646|100,21.630461|100,30] Z",
                    tolerance: 1e-4), "r 20 on 100 x 60: the vertical reach is the half side")
    #expect(matches(continuousRect(100, 60, 30, 30, 30, 30),
                    "M(100,30) L(100,30) C[100,31.2|100,35.4|97.7527,41.0552] C[94.9282,48.8153|88.8153,54.9282|81.0552,57.7527] C[73.9478,60|67.3453,60|54.1401,60] L(45.8599,60) C[32.6547,60|26.0522,60|18.9448,57.7527] C[11.1847,54.9282|5.0718,48.8153|2.2473,41.0552] C[0,35.4|0,31.2|0,30] L(0,30) C[0,28.8|0,24.6|2.2473,18.9448] C[5.0718,11.1847|11.1847,5.0718|18.9448,2.2473] C[26.0522,0|32.6547,0|45.8599,0] L(54.1401,0) C[67.3453,0|73.9478,0|81.0552,2.2473] C[88.8153,5.0718|94.9282,11.1847|97.7527,18.9448] C[100,24.6|100,28.8|100,30] Z",
                    tolerance: 1e-3), "the capsule")
    #expect(matches(continuousRect(100, 60, 20, 10, 0, 0),
                    "M(100,35) L(100,60) L(0,60) L(0,30.5733) C[0,21.7698|0,17.3681|1.4982,12.6299] C[3.3812,7.4565|7.4565,3.3812|12.6299,1.4982] C[17.3681,0|21.7698,0|30.5733,0] L(84.7134,0) C[89.1151,0|91.3159,0|93.6851,0.7491] C[96.2718,1.6906|98.3094,3.7282|99.2509,6.3149] C[100,8.6841|100,10.8849|100,15.2866] Z",
                    tolerance: 1e-3), "TL 20 and TR 10: the start is the right edge between the radii (10 and 0 -> 35)")
}

/// The three cubics of a corner meet, turn by under 0.05 rad at a joint (SwiftUI's own are not exactly tangent: the
/// probe's elements kink by 0.043 rad at the full reach, which the model keeps), start and end on their sides at the
/// reach, and mirror each other across the diagonal when the two sides leave the same room. For every room from the
/// capsule's to the full reach. **Mutation**: `m1`/`m2` swapped breaks the joint and the mirror.
@Test func aCornersCubicsMeetAndMirror() {
    for room in stride(from: 20.0, through: 40.0, by: 2.5) {
        let c = ContinuousCorner.cubics(ContinuousCornerSpec(rx: 20, ry: 20, roomX: room, roomY: room))
        #expect(c.count == 3)
        for i in 0..<2 {
            let a = c[i], b = c[i + 1]
            #expect(abs(a[3].x - b[0].x) < 1e-12 && abs(a[3].y - b[0].y) < 1e-12, "room \(room): cubic \(i) ends where \(i + 1) starts")
            let t1 = (x: a[3].x - a[2].x, y: a[3].y - a[2].y), t2 = (x: b[1].x - b[0].x, y: b[1].y - b[0].y)
            let cross = t1.x * t2.y - t1.y * t2.x
            let scale = (t1.x * t1.x + t1.y * t1.y).squareRoot() * (t2.x * t2.x + t2.y * t2.y).squareRoot()
            #expect(abs(cross / scale) < 0.05, "room \(room): the tangent at joint \(i) turns by \(cross / scale)")
        }
        let reach = min(room, 20 * ContinuousCorner.extent)
        #expect(abs(c[0][0].x - reach) < 1e-9 && c[0][0].y == 0, "the outer cubic starts on the horizontal side at the reach")
        #expect(abs(c[2][3].y - reach) < 1e-9 && c[2][3].x == 0, "and the last ends on the vertical side")
        for k in 0..<4 {
            #expect(abs(c[0][k].x - c[2][3 - k].y) < 1e-12 && abs(c[0][k].y - c[2][3 - k].x) < 1e-12, "room \(room): A and C mirror across the diagonal")
            #expect(abs(c[1][k].x - c[1][3 - k].y) < 1e-12 && abs(c[1][k].y - c[1][3 - k].x) < 1e-12, "the middle cubic mirrors itself")
        }
    }
}

/// The uneven fit, probe CC3/CC3c: the horizontal sides first (top, then bottom), then the vertical sides on what they
/// left. **Mutation**: the vertical sides first reddens the first case.
@Test func theUnevenFitIsHorizontalSidesFirst() {
    func fit(_ w: Double, _ h: Double, _ tl: Double, _ tr: Double, _ br: Double, _ bl: Double) -> [Double] {
        let f = ContinuousCorner.fit(width: w, height: h, topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
        return [f.topLeft, f.topRight, f.bottomRight, f.bottomLeft]
    }
    func close(_ a: [Double], _ b: [Double]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.06 } }
    #expect(close(fit(83.6, 146.2, 0, 112.8, 108.8, 112.2), [0, 83.6, 41.8, 41.8]))
    #expect(close(fit(102.5, 106.4, 95, 32.3, 67.7, 111.2), [55.2, 32.3, 51.2, 51.2]))
    #expect(close(fit(57.8, 98.3, 113.9, 0, 47, 59.5), [57.8, 0, 28.9, 28.9]))
    #expect(close(fit(100, 60, 50, 0, 0, 20), [40, 0, 0, 20]), "the larger gives way")
    #expect(close(fit(100, 60, 30, 0, 0, 30), [30, 0, 0, 30]))
    #expect(close(fit(100, 60, -5, 0, 10, 10), [0, 0, 10, 10]), "a negative radius is 0")
}

/// Which uneven rectangles the renderer's distance may draw (a curve past its quadrant is a path), and the tail rule:
/// a reach past the half by `d` is allowed while the tail beyond is under 0.01 px off its side. **Mutation**: the rule
/// admitting every overshoot reddens the lone TL 45 and the TL 30 beside BL 10; admitting none reddens the card.
@Test func theQuadrantRuleAdmitsAnOvershootOnlyWhileItsTailIsInvisible() {
    func fits(_ w: Double, _ h: Double, _ tl: Double, _ tr: Double, _ br: Double, _ bl: Double) -> Bool {
        let f = ContinuousCorner.fit(width: w, height: h, topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl)
        return ContinuousCorner.fitsQuadrants(width: w, height: h, topLeft: f.topLeft, topRight: f.topRight,
                                              bottomRight: f.bottomRight, bottomLeft: f.bottomLeft)
    }
    #expect(fits(100, 60, 30, 30, 30, 30), "a capsule")
    #expect(fits(100, 60, 20, 20, 0, 0), "a card: reach 30.57 on a half of 30, a tail 1.5e-5 px off its side")
    #expect(fits(100, 200, 20, 20, 0, 0), "a tall card")
    #expect(!fits(100, 60, 45, 0, 0, 0), "a lone TL 45 reaches 60 down a side of 60")
    #expect(!fits(100, 60, 30, 0, 0, 10), "TL 30 beside BL 10 takes 45 of the left side")
    #expect(fits(100, 60, 0, 0, 0, 0), "no radius")
}
