import Testing
@testable import MetalUIPath

// P4 lane 2 (rulings `OS-H`, `OS-L`, `OS-P`): the pooled rasterizer scratch. A `RasterScratch` is borrowed
// `inout` for one `rasterize`/`blur` call, handed back zero-filled on every use, and never grown past
// `capacityLimit`. Every pin compares a pooled run, on a scratch deliberately left dirty by a larger earlier
// use, with a fresh one (or the 2155f1e reference) byte for byte.

/// Leaves `scratch` holding non-zero garbage in every slot, `count` elements long.
func dirty(_ scratch: inout RasterScratch, count: Int = 300_000) {
    var cells = scratch.takeCells(count: count)
    for i in cells.indices { cells[i] = 3.5 }
    scratch.returnCells(cells)
    for slot in RasterScratch.Slot.allCases {
        var ints = scratch.takeInts(slot, count: count)
        for i in ints.indices { ints[i] = 77 }
        scratch.returnInts(slot, ints)
    }
}

private func polygon(_ w: Double, _ h: Double, dx: Double = 0.3) -> [Polyline] {
    [Polyline(points: [PathPoint(dx, 0.4), PathPoint(w + dx, 0.2), PathPoint(w * 0.5, h), PathPoint(dx, h * 0.7)],
              closed: true),
     Polyline(points: [PathPoint(w * 0.25, h * 0.25), PathPoint(w * 0.75, h * 0.25), PathPoint(w * 0.5, h * 0.6)],
              closed: true)]
}

/// **P1** (`OS-H`). A pooled `rasterize` equals a fresh one, for sizes that shrink and grow on one scratch
/// that holds the previous (larger, non-zero) cells, both fill rules and both antialiasing modes. Mutations:
/// `takeCells` skipping its zero-fill; reusing the array without `removeAll(keepingCapacity:)`.
@Test func aPooledRasterizerEqualsAFreshOneAcrossShrinkingAndGrowingSizes() throws {
    var scratch = RasterScratch()
    dirty(&scratch)
    var compared = 0
    for (w, h) in [(180.0, 120.0), (7.0, 5.0), (60.0, 90.0), (300.0, 40.0), (1.0, 1.0), (33.0, 33.0)] {
        for rule in [FillRule.nonZero, .evenOdd] {
            for aa in [true, false] {
                let clip = RasterRect(x: -2, y: -2, width: 400, height: 400)
                var pooled = CoverageRasterizer(), fresh = CoverageRasterizer()
                var cold = RasterScratch()
                let a = pooled.rasterize(polygon(w, h), rule: rule, clip: clip, antialiased: aa, scratch: &scratch)
                let b = fresh.rasterize(polygon(w, h), rule: rule, clip: clip, antialiased: aa, scratch: &cold)
                try #require(a.rect == b.rect, "\(w)×\(h): rect \(a.rect) vs \(b.rect)")
                let differing = zip(a.alpha, b.alpha).filter { $0 != $1 }.count
                #expect(differing == 0, "\(w)×\(h) \(rule) aa \(aa): \(differing) bytes differ")
                #expect(pooled.lastRasterizedPixels == fresh.lastRasterizedPixels)
                compared += a.alpha.count
            }
        }
    }
    #expect(compared > 100_000, "the comparison covered real areas: \(compared)")
}

/// **P2** (`OS-H`). A pooled `BoxBlur.blur` equals the 2155f1e reference byte for byte over every reference
/// mask and sigma in one scratch that never returns to zero by itself. Mutation: `takeInts` skipping its
/// zero-fill (the padding ring of `a`/`b` and `columnSums` start non-zero).
@Test func aPooledBoxBlurEqualsTheReferenceByteForByte() throws {
    var scratch = RasterScratch()
    dirty(&scratch)
    var compared = 0
    for sigma in [0.3, 0.8, 1, 2.5, 10, 33] {
        for mask in pooledBlurMasks() {
            let pooled = BoxBlur.blur(mask, sigma: sigma, scratch: &scratch)
            let reference = ReferenceBoxBlur.blur(mask, sigma: sigma)
            try #require(pooled.rect == reference.rect, "σ \(sigma) \(mask.rect)")
            let differing = zip(pooled.alpha, reference.alpha).filter { $0 != $1 }.count
            #expect(differing == 0, "σ \(sigma) \(mask.rect): \(differing) differing bytes")
            compared += pooled.alpha.count
        }
    }
    #expect(compared > 100_000, "the comparison covered the padded areas: \(compared) bytes")
}

private func pooledBlurMasks() -> [AlphaMask] {
    func seeded(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ seed: UInt8) -> AlphaMask {
        AlphaMask(rect: RasterRect(x: x, y: y, width: w, height: h),
                  alpha: (0..<(w * h)).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ Int(seed)) })
    }
    return [seeded(0, 0, 61, 40, 3), seeded(0, 0, 1, 1, 9), seeded(-3, 7, 13, 9, 1), seeded(0, 0, 90, 70, 5),
            seeded(2, 2, 37, 1, 7), seeded(0, 0, 5, 80, 2)]
}

/// **P4** (`OS-H`). The pool does not pin a huge buffer: after a raster whose cells exceed
/// `RasterScratch.capacityLimit` the scratch holds nothing, while a small one is kept (the separating arm: a
/// cap that drops everything would fail P3). Mutation: removing the cap in `returnCells`.
@Test func thePoolDoesNotPinAHugeBuffer() throws {
    var scratch = RasterScratch()
    var rasterizer = CoverageRasterizer()
    let small = polygon(100, 100)
    _ = rasterizer.rasterize(small, rule: .nonZero, clip: RasterRect(x: 0, y: 0, width: 200, height: 200), scratch: &scratch)
    try #require(scratch.heldElements >= 100 * 100, "a small raster is kept: \(scratch.heldElements)")
    let side = Int(Double(RasterScratch.capacityLimit).squareRoot()) + 64
    let huge = [Polyline(points: [PathPoint(0, 0), PathPoint(Double(side), 0), PathPoint(Double(side), Double(side)),
                                  PathPoint(0, Double(side))], closed: true)]
    let mask = rasterizer.rasterize(huge, rule: .nonZero, clip: RasterRect(x: 0, y: 0, width: side, height: side),
                                    scratch: &scratch)
    try #require(mask.rect.area > RasterScratch.capacityLimit)
    #expect(scratch.heldElements == 0, "a raster past the limit is not pinned: \(scratch.heldElements)")
    // Blur buffers obey the same cap.
    var blurScratch = RasterScratch()
    let big = AlphaMask(rect: RasterRect(x: 0, y: 0, width: side, height: side),
                        alpha: [UInt8](repeating: 9, count: side * side))
    _ = BoxBlur.blur(big, sigma: 1, scratch: &blurScratch)
    // The two planes (side² each) are dropped; only the column sums (one row) may stay.
    #expect(blurScratch.heldElements < 2 * side, "blur planes past the limit are not pinned: \(blurScratch.heldElements)")
}
