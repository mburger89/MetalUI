import Testing
@testable import MetalUIPath

// Lane 1 (ruling GX-J): the triple box blur that stands in for SwiftUI's
// Gaussian (sigma = radius, probe SH3/SH3b), and the compositor that resamples
// a coverage or RGBA source under an affine.

/// 1.28 (SH3, SH3b) — a 40×40 square of alpha 255 blurred with sigma 10:
/// along the row through its centre, outside the square, the alpha is within
/// ±8 of SwiftUI's (255 − the red channel SH3 printed over white); sigma 4
/// within ±6 of SH3b's. With sigma = radius / 2 the falloff is twice as
/// steep and x 46 alone is off by about 50.
@Test func theBoxBlurApproximatesAGaussianOfSigmaRadius() throws {
    let square = AlphaMask(rect: RasterRect(x: 0, y: 0, width: 40, height: 40),
                           alpha: [UInt8](repeating: 255, count: 1600))
    let sh3: [(Int, Int)] = [(40, 132), (42, 152), (44, 170), (46, 188), (48, 203), (50, 217), (52, 228), (54, 237),
                             (56, 244), (58, 249), (60, 252), (62, 254), (64, 255), (66, 255), (68, 255), (70, 255)]
    let ten = BoxBlur.blur(square, sigma: 10)
    try #require(ten.rect.x <= -30 && ten.rect.maxX >= 70, "padded by 3σ: \(ten.rect)")
    for (x, red) in sh3 {
        let alpha = Int(ten.value(atX: x, y: 20))
        #expect(abs(alpha - (255 - red)) <= 8, "σ 10 x \(x): \(alpha) vs \(255 - red)")
    }
    let sh3b: [(Int, Int)] = [(40, 140), (41, 163), (42, 186), (43, 205), (44, 221), (45, 234), (46, 243), (47, 250),
                              (48, 253), (49, 255), (50, 255), (52, 255), (56, 255)]
    let four = BoxBlur.blur(square, sigma: 4)
    for (x, red) in sh3b {
        let alpha = Int(four.value(atX: x, y: 20))
        #expect(abs(alpha - (255 - red)) <= 6, "σ 4 x \(x): \(alpha) vs \(255 - red)")
    }
}

/// 1.30 — the compositor resamples bilinearly: a 2×2 checker turned a
/// quarter about its centre lands on a 2×2 destination as an exact
/// permutation (every sample on a texel centre); scaled ×10 and turned 45°
/// about the destination's centre, the centre pixel samples where the four
/// texels meet — their mean, 127.5 — where nearest would read 0 or 255.
@Test func aRotatedRasterIsResampledBilinearlyByTheCompositor() {
    let checker: [UInt8] = [255, 0, 0, 255]
    // Source (x, y) → destination (2 − y, x).
    let quarter = PathAffine(a: 0, b: 1, c: -1, d: 0, tx: 2, ty: 0)
    let turned = AlphaCompositor.resample(source: checker, width: 2, height: 2, channels: 1, transform: quarter,
                                          into: RasterRect(x: 0, y: 0, width: 2, height: 2), filter: .bilinear)
    for j in 0..<2 {
        for i in 0..<2 {
            // Destination (i, j) samples source (j, 1 − i).
            #expect(turned.value(atX: i, y: j) == checker[(1 - i) * 2 + j], "(\(i), \(j))")
        }
    }
    let diagonal = PathAffine.translation(10, 10)
        .concatenating(.rotation(Double.pi / 4))
        .concatenating(.scale(10, 10))
        .concatenating(.translation(-1, -1))
    let wide = AlphaCompositor.resample(source: checker, width: 2, height: 2, channels: 1, transform: diagonal,
                                        into: RasterRect(x: 0, y: 0, width: 20, height: 20), filter: .bilinear)
    let centre = Int(wide.value(atX: 10, y: 10))
    #expect(abs(centre - 128) <= 8, "centre \(centre)")
    // RGBA reads the alpha channel.
    let rgba: [UInt8] = [9, 9, 9, 200]
    let one = AlphaCompositor.resample(source: rgba, width: 1, height: 1, channels: 4, transform: .identity,
                                       into: RasterRect(x: 0, y: 0, width: 1, height: 1), filter: .nearest)
    #expect(one.alpha == [200])
}
