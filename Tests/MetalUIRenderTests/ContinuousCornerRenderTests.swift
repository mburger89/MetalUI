import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIPath
import MetalUIShaderTypes
@testable import MetalUIRender

// `MUIRect.shape == 2` draws SwiftUI's continuous rounded rectangle (divergence 90, ruling CC-, record 226).
// The oracle is `PathRaster.fill`/`stroke` of the same outline built by `PathGeometry.addContinuousRoundedRect`:
// exact-area coverage, independent of the shader's closest-point iteration. `ContinuousCorner` itself is pinned to
// SwiftUI's own elements in `aContinuousCornerPathIsSwiftUIs` (MetalUITests/PathTests).

private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)

private func rect(_ w: Float, _ h: Float, shape: PrimitiveShape, radii: Corners<ScaledPixels>,
                  border: Float = 0, background: Hsla, borderColor: Hsla = .transparent) -> MUIRect {
    MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(w), height: ScaledPixels(h))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(w), height: ScaledPixels(h))),
            background: background, borderColor: borderColor, cornerRadii: radii,
            borderWidths: Edges(all: ScaledPixels(border)), order: 0, shape: shape)
}

@MainActor
private func alphas(_ r: MUIRect, width: Int, height: Int) throws -> [Int] {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(r)
    scene.finalize()
    let pixels = try renderer.renderOffscreen(scene, size: Size(width: DevicePixels(Int32(width)),
                                                               height: DevicePixels(Int32(height))))
    return (0..<(width * height)).map { Int(pixels[$0 * 4 + 3]) }
}

private func coverage(_ geometry: PathGeometry, width: Int, height: Int) -> [Int] {
    var rasterizer = CoverageRasterizer()
    let mask = PathRaster.fill(geometry, rule: .nonZero, clip: RasterRect(x: 0, y: 0, width: width, height: height),
                               rasterizer: &rasterizer)
    return (0..<(width * height)).map { Int(mask.value(atX: $0 % width, y: $0 / width)) }
}

private func continuousPath(_ w: Double, _ h: Double, _ r: Double) -> PathGeometry {
    var g = PathGeometry()
    g.addContinuousRoundedRect(x: 0, y: 0, width: w, height: h, topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
    return g
}

private func circularPath(_ w: Double, _ h: Double, _ r: Double) -> PathGeometry {
    var g = PathGeometry()
    g.addRoundedRect(x: 0, y: 0, width: w, height: h, rx: r, ry: r)
    return g
}

private func maxGap(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).map { abs($0 - $1) }.max() ?? 0 }
private func differing(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).filter { abs($0 - $1) > 8 }.count }

/// The exact signed distance from the pixel centre (x + 0.5, y + 0.5) to `geometry`'s outline, by brute force over
/// its flattening (0.001 px) — independent of the shader's closest-point iteration. Negative inside.
private struct ExactOutline {
    let segments: [(PathPoint, PathPoint)]
    init(_ geometry: PathGeometry) {
        var out: [(PathPoint, PathPoint)] = []
        for line in Flattener.flatten(geometry, tolerance: 0.001) {
            for i in 0..<line.points.count {
                let a = line.points[i], b = line.points[(i + 1) % line.points.count]
                if a != b { out.append((a, b)) }
            }
        }
        segments = out
    }
    func distance(_ x: Double, _ y: Double) -> Double {
        var best = Double.infinity
        var inside = false
        for (a, b) in segments {
            let dx = b.x - a.x, dy = b.y - a.y
            let t = max(0, min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
            let ex = a.x + t * dx - x, ey = a.y + t * dy - y
            best = min(best, (ex * ex + ey * ey).squareRoot())
            if (a.y > y) != (b.y > y), x < a.x + (y - a.y) / (b.y - a.y) * dx { inside.toggle() }
        }
        return inside ? -best : best
    }
}

private func saturate(_ v: Double) -> Double { min(1, max(0, v)) }

/// What the renderer should write for the continuous kind if its distance were exact: the half-pixel coverage of
/// the exact distance (`fill`), or of the band `|d| <= band / 2` around the inset outline (`band`). The brute-force
/// distance is taken only where the area-exact raster `edges` has a partial pixel within a pixel — elsewhere the
/// coverage is 0 or 1 whatever the distance.
private func exactCoverage(_ outline: ExactOutline, edges: [Int], width: Int, height: Int, band: Double? = nil) -> [Int] {
    func near(_ x: Int, _ y: Int) -> Bool {
        for dy in -2...2 { for dx in -2...2 {
            let xx = x + dx, yy = y + dy
            guard xx >= 0, yy >= 0, xx < width, yy < height else { continue }
            if edges[yy * width + xx] != edges[y * width + x] { return true }
        } }
        return edges[y * width + x] != 0 && edges[y * width + x] != 255
    }
    return (0..<(width * height)).map { i in
        guard near(i % width, i / width) else { return edges[i] }
        let d = outline.distance(Double(i % width) + 0.5, Double(i / width) + 0.5)
        guard let band else { return Int((255 * saturate(0.5 - d)).rounded()) }
        return Int((255 * (saturate(0.5 - (d - band / 2)) - saturate(0.5 - (d + band / 2)))).rounded())
    }
}

/// The renderer's continuous fill against the brute-force exact distance: the arithmetic of the closest-point
/// iteration alone (a quarter of an 8-bit level of coverage at r 20; stop condition 5 of the plan: a thirty-second of
/// a pixel is 8 levels), at radii whose curves are small, large and clipped by the room (r 100 in a 200 square is
/// a circle-sized corner; r 20 in 120 x 40 is a capsule's; r 150 in 400 x 300 a capsule's with room to spare).
@Test @MainActor func aContinuousRectDrawsItsCurve() throws {
    for (w, h, r) in [(100.0, 60.0, 20.0), (400.0, 300.0, 150.0), (200.0, 200.0, 100.0), (120.0, 40.0, 20.0), (256.0, 256.0, 90.0), (100.0, 60.0, 22.0)] {
        let iw = Int(w), ih = Int(h)
        let radii = Corners(all: ScaledPixels(Float(r)))
        let drawn = try alphas(rect(Float(w), Float(h), shape: .continuousRoundedRectangle, radii: radii, background: red), width: iw, height: ih)
        let area = coverage(continuousPath(w, h, r), width: iw, height: ih)
        let oracle = exactCoverage(ExactOutline(continuousPath(w, h, r)), edges: area, width: iw, height: ih)
        let gap = maxGap(drawn, oracle)
        #expect(gap <= 3, "r \(r) in \(iw)x\(ih): the renderer's coverage is \(gap) levels from the exact distance's")
    }
}

/// The renderer's continuous outline against the area-exact path raster, with the circular kind's own gap against its
/// path as the calibration: both pay the distance model's antialiasing, which is not area coverage (about 24 levels at
/// a 45 degree edge), so what is left is the geometry. A kind-0 draw would fail this at r 200 by the curve itself.
@Test @MainActor func aContinuousRectIsTheCurveThePathRasterFills() throws {
    for (w, h, r) in [(100.0, 60.0, 20.0), (400.0, 300.0, 150.0), (200.0, 200.0, 100.0), (256.0, 256.0, 90.0)] {
        let iw = Int(w), ih = Int(h)
        let radii = Corners(all: ScaledPixels(Float(r)))
        let circular = try alphas(rect(Float(w), Float(h), shape: .roundedRectangle, radii: radii, background: red), width: iw, height: ih)
        let continuous = try alphas(rect(Float(w), Float(h), shape: .continuousRoundedRectangle, radii: radii, background: red), width: iw, height: ih)
        let curve = coverage(continuousPath(w, h, r), width: iw, height: ih)
        let calibration = maxGap(circular, coverage(circularPath(w, h, r), width: iw, height: ih))
        #expect(maxGap(continuous, curve) <= calibration + 8, "r \(r): \(maxGap(continuous, curve)) levels from the path raster; the circular kind is \(calibration)")
        // The instrument separates the styles: the circular draw is far from the continuous curve where it matters.
        if r >= 90 { #expect(differing(circular, curve) > 100, "a circular corner differs from the curve at r \(r)") }
        #expect(differing(continuous, circular) > 0 || r < 25, "kind 2 is not kind 0 at r \(r)")
    }
}

/// Probe CC5: `strokeBorder(w)` is the stroke of the shape inset by w/2 (0 px apart), so the shader's band is the inset
/// curve's — against the brute-force distance to that inset outline (3 levels) — and **not** `continuous(r)` minus
/// `continuous(r - w)`, which is far from it.
@Test @MainActor func aContinuousStrokeBorderIsTheInsetCurvesBand() throws {
    for (w, h, r, bw) in [(100.0, 60.0, 20.0, 6.0), (140.0, 140.0, 40.0, 20.0), (100.0, 60.0, 30.0, 24.0)] {
        let iw = Int(w), ih = Int(h)
        let radii = Corners(all: ScaledPixels(Float(r)))
        let drawn = try alphas(rect(Float(w), Float(h), shape: .continuousRoundedRectangle, radii: radii, border: Float(bw),
                                    background: .transparent, borderColor: red), width: iw, height: ih)
        let inset = bw / 2
        var insetOutline = PathGeometry()
        insetOutline.addContinuousRoundedRect(x: inset, y: inset, width: w - 2 * inset, height: h - 2 * inset,
                                              topLeft: r - inset, topRight: r - inset, bottomRight: r - inset, bottomLeft: r - inset)
        var sr = CoverageRasterizer()
        let strokeArea = PathRaster.stroke(insetOutline, style: StrokeParameters(width: bw), clip: RasterRect(x: 0, y: 0, width: iw, height: ih), rasterizer: &sr)
        let edges = (0..<(iw * ih)).map { Int(strokeArea.value(atX: $0 % iw, y: $0 / iw)) }
        let oracle = exactCoverage(ExactOutline(insetOutline), edges: edges, width: iw, height: ih, band: bw)
        #expect(maxGap(drawn, oracle) <= 3, "r \(r) border \(bw): the band is \(maxGap(drawn, oracle)) levels from the inset curve's")
        // The wrong model: the outline minus the outline of radius r - w inset by w.
        var wrong = continuousPath(w, h, r)
        var hole = PathGeometry()
        hole.addContinuousRoundedRect(x: bw, y: bw, width: w - 2 * bw, height: h - 2 * bw, topLeft: max(0, r - bw), topRight: max(0, r - bw),
                                      bottomRight: max(0, r - bw), bottomLeft: max(0, r - bw))
        wrong.append(hole)
        var wr = CoverageRasterizer()
        let wrongMask = PathRaster.fill(wrong, rule: .evenOdd, clip: RasterRect(x: 0, y: 0, width: iw, height: ih), rasterizer: &wr)
        let concentric = (0..<(iw * ih)).map { Int(wrongMask.value(atX: $0 % iw, y: $0 / iw)) }
        try #require(differing(oracle, concentric) > 0, "the concentric model differs from the inset band at r \(r) border \(bw)")
        #expect(differing(drawn, concentric) > 0, "r \(r) border \(bw): the drawn band is not the concentric one")
    }
}

/// Probe CC5b: an inset radius that is not positive leaves the band's outer corner square (a miter), as K11's circular.
@Test @MainActor func aContinuousBorderWiderThanItsRadiusKeepsASquareOuterCorner() throws {
    let drawn = try alphas(rect(100, 60, shape: .continuousRoundedRectangle, radii: Corners(all: ScaledPixels(4)), border: 10,
                                background: .transparent, borderColor: red), width: 100, height: 60)
    #expect(drawn[0] == 255 && drawn[99] == 255, "the outer corner pixel is covered: a square corner, not a rounded one")
}

/// A zero width draws the fill alone, the band never; and past the centre the band is the whole shape.
@Test @MainActor func aContinuousBorderPastTheCentreFillsTheShape() throws {
    let fill = try alphas(rect(60, 60, shape: .continuousRoundedRectangle, radii: Corners(all: ScaledPixels(20)), background: red), width: 60, height: 60)
    let wide = try alphas(rect(60, 60, shape: .continuousRoundedRectangle, radii: Corners(all: ScaledPixels(20)), border: 80,
                               background: .transparent, borderColor: red), width: 60, height: 60)
    #expect(maxGap(fill, wide) <= 1, "a border at least as wide as the shape covers the shape")
}
