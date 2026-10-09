import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI

// C10 lane 3 — gradients: values and geometry (rulings `LK-J`, `LK-R`; spec
// `docs/superpowers/specs/2026-10-08-controls-looks-design.md` §4.3). SwiftUI's
// side is `docs/probes/swiftui-controls-looks.swift`, arms G1–G11, R1, R2
// (ImageRenderer, scale 1, read as 8-bit sRGB).
//
// Every arm renders a headless `Frame` (`effectFrame`, a square window; the
// root is centred, `CN-J`, so each window side is chosen to put the gradient's
// origin on whole points along the axis read) and reads the scene's images the
// way the GPU samples them (`lkComposite`): a linear-filtered image bilinear
// with clamped edges, a nearest one by its texel, composited over white in draw
// order. Probe pixel `k` is read at the local pixel centre `k + 0.5`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

let lkRed = Color(red: 1, green: 0, blue: 0)
let lkGreen = Color(red: 0, green: 1, blue: 0)
let lkBlue = Color(red: 0, green: 0, blue: 1)
let lkBlack = Color(white: 0)
let lkWhite = Color(white: 1)

/// The premultiplied RGBA (0…255, fractional) `entry` draws at device point
/// (x, y), as the image pipeline samples it, or `nil` outside its quad or mask.
func lkSample(_ entry: (image: MUIImage, texture: ImageTexture), _ x: Double, _ y: Double) -> [Double]? {
    let b = entry.image.bounds, m = entry.image.contentMask
    func inside(_ r: MUIBounds) -> Bool {
        x >= Double(r.origin.x) && y >= Double(r.origin.y)
            && x < Double(r.origin.x + r.size.width) && y < Double(r.origin.y + r.size.height)
    }
    guard inside(b), inside(m) else { return nil }
    let t = entry.texture
    let u = (x - Double(b.origin.x)) / Double(b.size.width) * Double(t.width)
    let v = (y - Double(b.origin.y)) / Double(b.size.height) * Double(t.height)
    func texel(_ i: Int, _ j: Int) -> [Double] {
        let ci = min(max(i, 0), t.width - 1), cj = min(max(j, 0), t.height - 1)
        let k = (cj * t.width + ci) * 4
        return (0..<4).map { Double(t.pixels[k + $0]) }
    }
    if entry.image.filter == ImageFilter.nearest.rawValue {
        return texel(Int(u.rounded(.down)), Int(v.rounded(.down)))
    }
    let uu = u - 0.5, vv = v - 0.5
    let i = Int(uu.rounded(.down)), j = Int(vv.rounded(.down))
    let fu = uu - uu.rounded(.down), fv = vv - vv.rounded(.down)
    let a = texel(i, j), b1 = texel(i + 1, j), c = texel(i, j + 1), d = texel(i + 1, j + 1)
    return (0..<4).map { k in
        (a[k] * (1 - fu) + b1[k] * fu) * (1 - fv) + (c[k] * (1 - fu) + d[k] * fu) * fv
    }
}

/// Every image of `scene` composited over white at device point (x, y), in
/// draw order, each times its opacity: the RGB a viewer sees, rounded.
func lkComposite(_ scene: Scene, _ x: Double, _ y: Double) -> [Int] {
    var rgb: [Double] = [255, 255, 255]
    for entry in gxImages(scene) {
        guard let s = lkSample(entry, x, y) else { continue }
        let o = Double(entry.image.opacity)
        let a = s[3] * o / 255
        rgb = (0..<3).map { s[$0] * o + rgb[$0] * (1 - a) }
    }
    return rgb.map { Int($0.rounded()) }
}

/// Whether `got` is within `tolerance` of `want` on every channel.
func lkNear(_ got: [Int], _ want: [Int], _ tolerance: Int) -> Bool {
    got.count == want.count && zip(got, want).allSatisfy { abs($0 - $1) <= tolerance }
}

/// One headless frame of `element` in a `side` window, finalized.
@MainActor func lkScene<E: Element>(_ element: E, side: Float, scaleFactor: Float = 1) -> Scene {
    effectFrame(element, side: side, scaleFactor: scaleFactor).finalizedScene()
}

// MARK: - 3.1 (G11, G2, G5)

/// **3.1** (G11, G2, G5). Colours interpolate in premultiplied Oklab: a
/// red→blue 101-wide gradient reads (140, 83, 162) at x 50 — neither the gamma
/// mix (128, 0, 128) nor the linear-light one; black→white reads 99 (Oklab L
/// 0.5); clear red → blue reads (127, 128, 255) over white (premultiplied: the
/// clear end contributes no red). Mutation: interpolate in gamma sRGB.
@Test @MainActor func theOklabTableMatchesG11G2G5() {
    // 101 × 4 in a 201 window: the origin is at x 50.
    func at50(_ colors: [Color]) -> [Int] {
        let scene = lkScene(Rectangle().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            .frame(width: px(101), height: px(4)), side: 201)
        return lkComposite(scene, 50 + 50.5, 100.5)
    }
    let g11 = at50([lkRed, lkBlue])
    #expect(lkNear(g11, [140, 83, 162], 1), "G11 (140, 83, 162): \(g11)")
    let g2 = at50([lkBlack, lkWhite])
    #expect(lkNear(g2, [99, 99, 99], 1), "G2 99: \(g2)")
    let g5 = at50([lkRed.opacity(0), lkBlue])
    #expect(lkNear(g5, [127, 128, 255], 1), "G5 (127, 128, 255) over white: \(g5)")
}

// MARK: - 3.2 (G1)

/// **3.2** (G1). A vertical gradient is sampled at pixel centres: a red→blue
/// 10 × 101 reads (254, 9, 8) at y 0, (141, 82, 162) at y 50 and (2, 5, 254)
/// at y 100. Mutation: `t = y / H` (y 0 reads pure red).
@Test @MainActor func aVerticalGradientSamplesAtPixelCentresG1() {
    let scene = lkScene(Rectangle().fill(LinearGradient(colors: [lkRed, lkBlue], startPoint: .top, endPoint: .bottom))
        .frame(width: px(10), height: px(101)), side: 201)   // origin y 50
    for (y, want) in [(0, [254, 9, 8]), (50, [141, 82, 162]), (100, [2, 5, 254])] {
        let got = lkComposite(scene, 100, 50 + Double(y) + 0.5)
        #expect(lkNear(got, want, 1), "y \(y): \(got) vs G1 \(want)")
    }
}

// MARK: - 3.3 (G3)

/// **3.3** (G3). A diagonal gradient's parameter is the projection onto start
/// → end **in points**: in a 200 × 100 rect topLeading → bottomTrailing,
/// (100, 0) reads 73 and (0, 50) reads 3. The separating arm: projected in
/// unit space both read about t 0.25 (one grey). Mutation: project in unit
/// space.
@Test @MainActor func aDiagonalGradientsIsolinesArePerpendicularInPointsG3() {
    let scene = lkScene(Rectangle().fill(LinearGradient(colors: [lkBlack, lkWhite], startPoint: .topLeading,
                                                        endPoint: .bottomTrailing))
        .frame(width: px(200), height: px(100)), side: 300)   // origin (50, 100)
    let a = lkComposite(scene, 50 + 100.5, 100 + 0.5)
    let b = lkComposite(scene, 50 + 0.5, 100 + 50.5)
    #expect(lkNear(a, [73, 73, 72], 2), "G3 (100, 0) 73: \(a)")
    #expect(lkNear(b, [3, 3, 4], 2), "G3 (0, 50) 3: \(b)")
    #expect(a[0] - b[0] > 50, "the two points are on different isolines: \(a) \(b)")
}

// MARK: - 3.4 (G4, G4b, G4c, G7)

/// **3.4** (G4, G4b, G4c, G7). Stops are sorted by location (the same stops
/// given in reverse draw the same), padded beyond the ends, and two at one
/// location make a hard edge. Probe pixel 50 of G4c sits on the edge and is
/// not pinned (its neighbours are). Mutation: no sort.
@Test @MainActor func stopsAreSortedPaddedAndHardAtEqualLocationsG4G4bG4cG7() {
    func row(_ stops: [Gradient.Stop]? = nil, start: UnitPoint = .leading, end: UnitPoint = .trailing) -> Scene {
        let g = LinearGradient(stops: stops ?? [.init(color: lkRed, location: 0), .init(color: lkBlue, location: 1)],
                               startPoint: start, endPoint: end)
        return lkScene(Rectangle().fill(g).frame(width: px(101), height: px(4)), side: 201)
    }
    func at(_ scene: Scene, _ x: Int) -> [Int] { lkComposite(scene, 50 + Double(x) + 0.5, 100.5) }
    let g4 = row([.init(color: lkRed, location: 0.2), .init(color: lkBlue, location: 0.8)])
    for (x, want) in [(0, [255, 0, 0]), (10, [255, 0, 0]), (50, [140, 83, 162]), (90, [0, 0, 255]),
                      (100, [0, 0, 255])] {
        #expect(lkNear(at(g4, x), want, 2), "G4 x\(x): \(at(g4, x)) vs \(want)")
    }
    let g4b = row([.init(color: lkBlue, location: 0.8), .init(color: lkRed, location: 0.2)])
    for (x, want) in [(0, [255, 0, 0]), (50, [139, 83, 163]), (100, [0, 0, 255])] {
        #expect(lkNear(at(g4b, x), want, 2), "G4b x\(x): \(at(g4b, x)) vs \(want)")
    }
    let g4c = row([.init(color: lkRed, location: 0.5), .init(color: lkBlue, location: 0.5)])
    for (x, want) in [(48, [255, 0, 0]), (49, [255, 0, 0]), (51, [0, 0, 255]), (52, [0, 0, 255])] {
        #expect(lkNear(at(g4c, x), want, 2), "G4c x\(x): \(at(g4c, x)) vs \(want)")
    }
    let g7 = row(start: UnitPoint(x: 0.25, y: 0.5), end: UnitPoint(x: 0.75, y: 0.5))
    for (x, want) in [(0, [255, 0, 0]), (20, [255, 0, 0]), (50, [140, 83, 162]), (80, [0, 0, 255]),
                      (100, [0, 0, 255])] {
        #expect(lkNear(at(g7, x), want, 2), "G7 x\(x): \(at(g7, x)) vs \(want)")
    }
}

// MARK: - 3.5 (G6)

/// **3.5** (G6). Start == end draws the last colour everywhere. Mutation: the
/// first colour.
@Test @MainActor func aDegenerateGradientDrawsTheLastColourG6() {
    let scene = lkScene(Rectangle().fill(LinearGradient(colors: [lkRed, lkBlue], startPoint: .center, endPoint: .center))
        .frame(width: px(20), height: px(20)), side: 200)   // origin (90, 90)
    for x in [2, 17] {
        let got = lkComposite(scene, 90 + Double(x) + 0.5, 100.5)
        #expect(lkNear(got, [0, 0, 255], 1), "G6 (\(x), 10) blue: \(got)")
    }
}

// MARK: - 3.6 (R1, R2)

/// **3.6** (R1, R2). A radial gradient's distance is circular in points:
/// black→white r 0…50 reads 255 / 100 / 0 / 99 / 255 across a 101 square's
/// middle row, and in a 201 × 101 rect (100, 25) and (75, 50) — both 25 points
/// from the centre — read the same 100 while (50, 50) reads white. Mutation:
/// elliptical (distances scaled by the rect).
@Test @MainActor func aRadialGradientIsCircularInPointsR1R2() {
    let radial = RadialGradient(colors: [lkBlack, lkWhite], center: .center, startRadius: px(0), endRadius: px(50))
    let r1 = lkScene(Rectangle().fill(radial).frame(width: px(101), height: px(101)), side: 201)   // origin (50, 50)
    for (x, want) in [(0, 255), (25, 100), (50, 0), (75, 99), (100, 255)] {
        let got = lkComposite(r1, 50 + Double(x) + 0.5, 50 + 50.5)
        #expect(abs(got[0] - want) <= 2, "R1 x\(x): \(got) vs \(want)")
    }
    let r2 = lkScene(Rectangle().fill(radial).frame(width: px(201), height: px(101)), side: 301)   // origin (50, 100)
    for (x, y, want) in [(100, 25, 100), (75, 50, 99), (50, 50, 255)] {
        let got = lkComposite(r2, 50 + Double(x) + 0.5, 100 + Double(y) + 0.5)
        #expect(abs(got[0] - want) <= 2, "R2 (\(x), \(y)): \(got) vs \(want)")
    }
}

// MARK: - 3.7 (G8)

/// **3.7** (G8). A gradient-filled circle is cut by the circle: black→white
/// top→bottom in a 40 circle reads about 0 at (20, 1), 103 at the centre, 243
/// at (20, 38), and white (nothing drawn) at the corner (1, 1). Mutation: fill
/// the bounding rect.
@Test @MainActor func aGradientFilledCircleIsCutByTheCircleG8() {
    let scene = lkScene(Circle().fill(LinearGradient(colors: [lkBlack, lkWhite], startPoint: .top, endPoint: .bottom))
        .frame(width: px(40), height: px(40)), side: 200)   // origin (80, 80)
    func at(_ x: Int, _ y: Int) -> [Int] { lkComposite(scene, 80 + Double(x) + 0.5, 80 + Double(y) + 0.5) }
    #expect(lkNear(at(20, 1), [0, 1, 0], 3), "G8 (20, 1): \(at(20, 1))")
    #expect(lkNear(at(20, 20), [103, 103, 103], 2), "G8 centre: \(at(20, 20))")
    #expect(lkNear(at(20, 38), [243, 243, 242], 2), "G8 (20, 38): \(at(20, 38))")
    #expect(at(1, 1) == [255, 255, 255], "G8 corner, outside the circle: \(at(1, 1))")
}

// MARK: - 3.8 (G10)

/// **3.8** (G10). A `LinearGradient` is a greedy view with an ideal size of
/// 10 × 10, like a shape: in a 300 × 120 frame it fills 300 × 120, under
/// `fixedSize()` it is 10 × 10. The same for a `RadialGradient`. Mutation: an
/// ideal of 0.
@Test @MainActor func aLinearGradientViewIsGreedyWithAnIdealOfTenG10() throws {
    let linear = LinearGradient(colors: [lkBlack, lkWhite], startPoint: .top, endPoint: .bottom)
    let radial = RadialGradient(colors: [lkBlack, lkWhite], center: .center, startRadius: px(0), endRadius: px(5))
    func bounds(_ e: some Element) throws -> String {
        let images = gxImages(lkScene(e, side: 400))
        try #require(images.count == 1, "one image: \(images.count)")
        return gxDescribe(images[0].image.bounds)
    }
    #expect(try bounds(linear.frame(width: px(300), height: px(120))) == "(50.0, 140.0, 300.0×120.0)", "greedy")
    #expect(try bounds(linear.fixedSize()) == "(195.0, 195.0, 10.0×10.0)", "ideal 10 × 10")
    #expect(try bounds(radial.fixedSize()) == "(195.0, 195.0, 10.0×10.0)", "radial: ideal 10 × 10")
}

// MARK: - 3.9 (G9)

/// **3.9** (G9). `.background(gradient)` fills the frame on both vocabularies:
/// black→white leading→trailing behind a 60 × 20 reads 0 / 35 / 101 / 177 /
/// 252 at x 0 / 15 / 30 / 45 / 59. The legacy element is padded by 8 inside
/// its frame, so a fill under the padding (content) box reads otherwise.
/// Mutation: draw under the padding box.
@Test @MainActor func legacyAndProposalBackgroundGradientsFillTheFrameG9() {
    let g = LinearGradient(colors: [lkBlack, lkWhite], startPoint: .leading, endPoint: .trailing)
    let proposal = lkScene(Color.clear.frame(width: px(60), height: px(20)).background(g), side: 200)
    let legacy = lkScene(Box().padding(px(8)).frame(width: px(60), height: px(20)).background(g),
                         side: 200)
    for (name, scene) in [("proposal", proposal), ("legacy", legacy)] {
        for (x, want) in [(0, 0), (15, 35), (30, 101), (45, 177), (59, 252)] {
            let got = lkComposite(scene, 70 + Double(x) + 0.5, 100)   // origin (70, 90)
            #expect(abs(got[0] - want) <= 2, "\(name) x\(x): \(got) vs G9 \(want)")
        }
    }
}

// MARK: - 3.10 (LK-J item 7)

/// **3.10** (`LK-J` item 7, a rule). A gradient change snaps: a legacy box's
/// and a proposal view's gradient background changed under a one-second
/// linear transaction reads the new colours fully half-way. Mutation: route
/// the legacy gradient through `animatedBackground`.
@Test @MainActor func aGradientChangeSnaps() {
    func gradient(_ first: Color) -> LinearGradient {
        LinearGradient(colors: [first, lkBlue], startPoint: .leading, endPoint: .trailing)
    }
    func tree(_ first: Color) -> some Element {
        Column {
            Box().frame(width: px(100), height: px(20)).background(gradient(first))
            Color.clear.frame(width: px(100), height: px(20)).background(gradient(first))
        }
    }
    let h = TransitionHarness()
    h.frame(0, nil, tree(lkRed), side: 200)
    h.frame(0, Animation.linear(duration: 1), tree(lkGreen), side: 200)
    let scene = h.frame(0.5, nil, tree(lkGreen), side: 200).finalizedScene()
    // The column is 100 × 40 at (50, 80): the legacy box above, the view below.
    for y in [90.0, 110.0] {
        let got = lkComposite(scene, 50.5, y)
        #expect(lkNear(got, [0, 255, 0], 3), "y \(y): the new first colour at once: \(got)")
    }
}
