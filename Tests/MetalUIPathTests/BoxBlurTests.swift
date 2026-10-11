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

// MARK: - C13 / PERF-a, lane 2: the faster loops against 2155f1e (`PF-F`)

/// Bytes from a seeded 64-bit LCG (Knuth's MMIX constants), its high byte:
/// the same masks on every run and platform.
private struct SeededBytes {
    var state: UInt64
    mutating func next() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 56)
    }
}

/// The masks L2.1 and L2.2 run over: 1×1, 1×N, N×1, odd and even sizes, a
/// larger one, an off-origin one, seeded bytes; plus a solid and a sparse mask
/// (the extremes of the running sums).
private func referenceMasks() -> [AlphaMask] {
    var bytes = SeededBytes(state: 0xC13)
    func seeded(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> AlphaMask {
        AlphaMask(rect: RasterRect(x: x, y: y, width: w, height: h), alpha: (0..<(w * h)).map { _ in bytes.next() })
    }
    var sparse = [UInt8](repeating: 0, count: 23 * 17)
    for i in stride(from: 5, to: sparse.count, by: 41) { sparse[i] = 255 }
    return [
        seeded(0, 0, 1, 1), seeded(0, 0, 1, 37), seeded(0, 0, 37, 1),
        seeded(0, 0, 13, 9), seeded(0, 0, 16, 10), seeded(-3, 7, 61, 40),
        AlphaMask(rect: RasterRect(x: 2, y: -5, width: 20, height: 11), alpha: [UInt8](repeating: 255, count: 220)),
        AlphaMask(rect: RasterRect(x: 0, y: 0, width: 23, height: 17), alpha: sparse),
    ]
}

/// **L2.1** (`PF-F` item 1). `BoxBlur.blur` equals the 2155f1e loop copied in
/// `BoxBlurReference.swift`: sigmas 0.3, 0.8, 1, 2.5, 10 and 33 over every
/// reference mask — the same rectangle and 0 differing bytes. Mutations
/// **M2a** (`(sum + half)` → `sum`) and **M2b** (the vertical running sum off
/// by one row) redden it.
@Test func theFastBoxBlurEqualsTheReferenceByteForByte() throws {
    let masks = referenceMasks()
    try #require(masks.count == 8)
    var compared = 0
    for sigma in [0.3, 0.8, 1, 2.5, 10, 33] {
        for mask in masks {
            let fast = BoxBlur.blur(mask, sigma: sigma), reference = ReferenceBoxBlur.blur(mask, sigma: sigma)
            try #require(fast.rect == reference.rect, "σ \(sigma) \(mask.rect): rect \(fast.rect) vs \(reference.rect)")
            let differing = zip(fast.alpha, reference.alpha).filter { $0 != $1 }.count
            #expect(differing == 0, "σ \(sigma) \(mask.rect): \(differing) differing bytes")
            compared += fast.alpha.count
        }
    }
    #expect(compared > 100_000, "the comparison covered the padded areas: \(compared) bytes")
}

/// **L2.2** (`PF-F` item 2). `AlphaCompositor.union` equals the 2155f1e loop:
/// every ordered pair of the reference masks (overlapping, disjoint, nested,
/// off-origin) and an empty operand on either side — the same rectangle and 0
/// differing bytes.
@Test func theFastUnionEqualsTheReferenceByteForByte() throws {
    let masks = referenceMasks() + [AlphaMask.empty]
    for a in masks {
        for b in masks {
            let fast = AlphaCompositor.union(a, b), reference = ReferenceBoxBlur.union(a, b)
            try #require(fast.rect == reference.rect, "\(a.rect) ∪ \(b.rect): rect \(fast.rect) vs \(reference.rect)")
            let differing = zip(fast.alpha, reference.alpha).filter { $0 != $1 }.count
            #expect(differing == 0, "\(a.rect) ∪ \(b.rect): \(differing) differing bytes")
        }
    }
}
