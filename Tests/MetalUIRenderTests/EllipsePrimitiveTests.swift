import Testing
import Foundation
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

// Lane 1 of plan task 11 part 2 (ruling TE-AE): `MUIRect.shape == 1` draws the
// ellipse inscribed in its bounds, and its border is SwiftUI's inset-ellipse
// band — `strokeBorder(w)` is `inset(by: w/2).stroke(w)` (probe K8), not the
// ellipse minus a concentric one.

private func pixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3]))
}

private func shapeRect(_ w: Float, _ h: Float, shape: PrimitiveShape, radius: Float = 0,
                       border: Float = 0, background: Hsla, borderColor: Hsla = .transparent) -> MUIRect {
    MUIRect(bounds: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                           size: Size(width: ScaledPixels(w), height: ScaledPixels(h))),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: Size(width: ScaledPixels(w), height: ScaledPixels(h))),
            background: background, borderColor: borderColor,
            cornerRadii: Corners(all: ScaledPixels(radius)),
            borderWidths: Edges(all: ScaledPixels(border)),
            order: 0, shape: shape)
}

@MainActor
private func render(_ rect: MUIRect, width: Int, height: Int) throws -> [UInt8] {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    var scene = Scene()
    scene.insert(rect)
    scene.finalize()
    return try renderer.renderOffscreen(scene, size: Size(width: DevicePixels(Int32(width)),
                                                         height: DevicePixels(Int32(height))))
}

private let red = Hsla(h: 0, s: 1, l: 0.5, a: 1)
private let green = Hsla(h: 1.0 / 3.0, s: 1, l: 0.5, a: 1)

/// 1.1 — pixel (10, 10) of a 100×60 frame lies inside the radius-30 capsule of
/// the same bounds and outside its inscribed ellipse, so the two kinds must
/// disagree there; the ellipse also fills its centre and leaves (1, 1) empty.
@Test @MainActor func anEllipseFillsItsInscribedEllipseAndNotTheCapsule() throws {
    let ellipse = try render(shapeRect(100, 60, shape: .ellipse, radius: 30, background: red),
                             width: 100, height: 60)
    let capsule = try render(shapeRect(100, 60, shape: .roundedRectangle, radius: 30, background: red),
                             width: 100, height: 60)
    // The arms must disagree at the separating pixel, or the test sees nothing.
    try #require(pixel(capsule, 10, 10, width: 100).a == 255, "the capsule arm fills (10, 10)")
    #expect(pixel(ellipse, 10, 10, width: 100).a == 0, "(10, 10) is outside the inscribed ellipse")
    #expect(pixel(ellipse, 50, 30, width: 100) == (255, 0, 0, 255), "the centre is filled")
    #expect(pixel(ellipse, 1, 1, width: 100).a == 0)
    // On the axes the ellipse reaches its bounds (the half-pixel edge).
    #expect(pixel(ellipse, 1, 30, width: 100).a == 255)
    #expect(pixel(ellipse, 50, 1, width: 100).a == 255)
}

/// The exact distance from `p` to the ellipse with semi-axes `a`, `b`
/// (centred at the origin), by brute force over the curve — independent of
/// the shader's closed-point iteration. Negative inside.
private func bruteDistance(_ px: Double, _ py: Double, _ a: Double, _ b: Double) -> Double {
    var best = Double.infinity
    let steps = 4_000
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * Double.pi
        let dx = px - a * cos(t), dy = py - b * sin(t)
        best = min(best, (dx * dx + dy * dy).squareRoot())
    }
    let inside = (px * px) / (a * a) + (py * py) / (b * b) < 1
    return inside ? -best : best
}

/// 1.2 — the border of shape 1 is the band of half-width w/2 around the
/// ellipse inset by w/2 (K8), not the ellipse minus a concentric one inset by
/// w. **At 100×60, border 10 — K8's own frame — the two models' edges are at
/// most 0.11 px apart at any pixel centre** (measured on the CPU by the
/// search below): K8's 518 px are antialiased coverage, not classification,
/// and no pixel there separates the models by a margin a GPU's rounding
/// cannot blur. So this test uses 120×40, border 16, where the search finds a
/// pixel the models classify oppositely by more than 0.9 px (ruling TE-AR),
/// and asserts the renderer follows the band.
@Test @MainActor func anEllipseBorderIsTheStrokeOfTheInsetEllipse() throws {
    let w = 16.0, a = 60.0, b = 20.0
    var separating: (x: Int, y: Int, bandIsBorder: Bool)?
    search: for y in 0..<20 {
        for x in 0..<60 {
            let px = Double(x) + 0.5 - a, py = Double(y) + 0.5 - b
            guard bruteDistance(px, py, a, b) < -1.5 else { continue }   // well inside
            let band = bruteDistance(px, py, a - w / 2, b - w / 2)
            let hole = bruteDistance(px, py, a - w, b - w)
            let margin = 0.9
            if abs(band) < w / 2 - margin && hole < -margin { separating = (x, y, true); break search }
            if band < -w / 2 - margin && hole > margin { separating = (x, y, false); break search }
        }
    }
    let at = try #require(separating, "the two models must disagree somewhere, or 1.2 sees nothing")
    let pixels = try render(shapeRect(120, 40, shape: .ellipse, border: 16, background: green, borderColor: red),
                            width: 120, height: 40)
    let p = pixel(pixels, at.x, at.y, width: 120)
    if at.bandIsBorder {
        #expect(p.r > 200 && p.g < 50, "(\(at.x), \(at.y)) is in the inset-ellipse band: border colour, read \(p)")
    } else {
        #expect(p.g > 200 && p.r < 50, "(\(at.x), \(at.y)) is inside the band's inner edge: background, read \(p)")
    }
    #expect(pixel(pixels, 60, 20, width: 120) == (0, 255, 0, 255), "the centre is background")
    #expect(pixel(pixels, 60, 2, width: 120).r > 200, "the band reaches the top of the bounds")
}
