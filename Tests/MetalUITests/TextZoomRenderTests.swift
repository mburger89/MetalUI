import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIScene
@testable import MetalUI
@testable import MetalUIRender

// R4-5 PR E lane 2 (`TZ-A`, record 222; probe `Z0`/`Z1`, which reproduces T15b): 20 pt text under `scaleEffect(2)` has the edge
// sharpness of real 40 pt text, not of a bilinear upscale of the 20 pt raster. Sharpness is the count of partially covered
// pixels (0 < alpha < 255): a re-rasterized glyph has a one-pixel anti-aliased edge, a resample has two.

private let size200 = Size(width: DevicePixels(200), height: DevicePixels(200))

@MainActor private func alpha<E: Element>(_ content: E) throws -> [UInt8] {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let renderer = try Renderer(device: device)
    let boxed = VStack(alignment: .leading, spacing: Pixels(0)) { content }
        .frame(width: Pixels(200), height: Pixels(200), alignment: .topLeading)
    let frame = TransitionHarness().frame(0, nil, boxed, side: 200)
    renderer.upload(frame.glyphAtlas)
    let pixels = try renderer.renderOffscreen(frame.finalizedScene(), size: size200)
    return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
}

private func partials(_ a: [UInt8]) -> Int { a.filter { $0 > 0 && $0 < 255 }.count }

/// A bilinear 2x upscale of the top-left 100 x 100 of `a` (the test's own code, T15b's instrument).
private func upscaled(_ a: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: 200 * 200)
    func at(_ x: Int, _ y: Int) -> Double { Double(a[min(max(y, 0), 199) * 200 + min(max(x, 0), 199)]) }
    for y in 0..<200 { for x in 0..<200 {
        let sx = (Double(x) + 0.5) / 2 - 0.5, sy = (Double(y) + 0.5) / 2 - 0.5
        let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down)), fx = sx - Double(x0), fy = sy - Double(y0)
        let top = at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx, bottom = at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx
        out[y * 200 + x] = UInt8((top * (1 - fy) + bottom * fy).rounded())
    } }
    return out
}

/// **21 (`TZ-A`; probe `Z0`: 326 partials for 20 pt at 2x, 298 for real 40 pt, 1237 for the upscale).** The partial-pixel count of
/// 20 pt "Hag" under `scaleEffect(2, anchor: .topLeading)` is within 15 percent of real 40 pt text's, and a bilinear upscale of
/// the unscaled raster has at least 2.5 times as many. Mutation **T1**: the re-key disabled (the text is then resampled by the
/// renderer's sprite filter, which has the upscale's soft edges).
@Test @MainActor func aTwiceScaledTextHasTheSharpnessOfTwiceTheSize() throws {
    let scaled = partials(try alpha(Text("Hag").font(size: 20).scaleEffect(2, anchor: .topLeading)))
    let native = partials(try alpha(Text("Hag").font(size: 40)))
    let resampled = partials(upscaled(try alpha(Text("Hag").font(size: 20))))
    try #require(native > 150, "set up: real 40 pt text has partial pixels (\(native))")
    #expect(Double(abs(scaled - native)) <= 0.15 * Double(native), "scaled \(scaled) against real 40 pt \(native)")
    #expect(Double(resampled) >= 2.5 * Double(native), "the upscale (\(resampled)) is the soft control against \(native)")
}
