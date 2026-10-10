/// A Gaussian of standard deviation `sigma` approximated by three box blurs
/// per axis (ruling GX-J: SwiftUI's shadow is Gaussian with sigma = radius,
/// probe SH3/SH3b). Integer arithmetic on the alpha channel, box widths from
/// sigma by the standard formula (`sqrt` and rounding only), zero padding —
/// deterministic everywhere and O(1) per pixel whatever the radius.
package enum BoxBlur {
    /// Three odd box widths whose successive application has variance σ²
    /// as nearly as odd widths allow: `wl` and `wl + 2`, `m` of the former.
    package static func boxWidths(sigma: Double) -> [Int] {
        guard sigma > 0, sigma.isFinite else { return [] }
        let n = 3.0
        let ideal = (12 * sigma * sigma / n + 1).squareRoot()
        var lower = Int(ideal.rounded(.down))
        if lower % 2 == 0 { lower -= 1 }
        if lower < 1 { lower = 1 }
        let upper = lower + 2
        let wl = Double(lower)
        let m = Int(((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4)).rounded())
        return (0..<3).map { $0 < m ? lower : upper }
    }

    /// The margin a blurred mask grows by on every side: ⌈3σ⌉, at least the
    /// boxes' combined reach.
    package static func padding(sigma: Double) -> Int {
        guard sigma > 0, sigma.isFinite else { return 0 }
        let reach = boxWidths(sigma: sigma).reduce(0) { $0 + ($1 - 1) / 2 }
        return max(reach, Int((3 * sigma).rounded(.up)))
    }

    /// `mask` blurred, over its rectangle grown by ``padding(sigma:)``. A
    /// non-positive sigma returns the mask unchanged.
    ///
    /// **Fast and byte-identical** (ruling `PF-F` item 1): one pair of `Int32`
    /// buffers behind unchecked buffer pointers; the horizontal passes run per
    /// row, the vertical passes row-major with one running sum per column (the
    /// cache-friendly order); each pass rounds `(sum + half) / width` with zero
    /// padding exactly as the 2155f1e loop did, and the narrowing runs in the
    /// same unchecked style. Pinned against that loop, copied verbatim, by
    /// `theFastBoxBlurEqualsTheReferenceByteForByte` (L2.1). Integer sums are
    /// exact, so the order of the additions cannot move a byte; an `Int32` sum
    /// holds `width × 255` for any width below eight million.
    package static func blur(_ mask: AlphaMask, sigma: Double) -> AlphaMask {
        let widths = boxWidths(sigma: sigma)
        guard !widths.isEmpty, !mask.rect.isEmpty else { return mask }
        let pad = padding(sigma: sigma)
        let rect = RasterRect(x: mask.rect.x - pad, y: mask.rect.y - pad,
                              width: mask.rect.width + 2 * pad, height: mask.rect.height + 2 * pad)
        let w = rect.width, h = rect.height
        let mw = mask.rect.width, mh = mask.rect.height
        var a = [Int32](repeating: 0, count: w * h)
        var b = [Int32](repeating: 0, count: w * h)
        var columnSums = [Int32](repeating: 0, count: w)
        var out = [UInt8](repeating: 0, count: w * h)
        mask.alpha.withUnsafeBufferPointer { src in
            a.withUnsafeMutableBufferPointer { pa in
                b.withUnsafeMutableBufferPointer { pb in
                    columnSums.withUnsafeMutableBufferPointer { sums in
                        out.withUnsafeMutableBufferPointer { dst in
                            var x0 = pa.baseAddress!, x1 = pb.baseAddress!
                            let s = src.baseAddress!
                            for y in 0..<mh {
                                let row = x0 + (y + pad) * w + pad, from = s + y * mw
                                for x in 0..<mw { row[x] = Int32(from[x]) }
                            }
                            for width in widths {
                                horizontalPass(x0, into: x1, w: w, h: h, width: Int32(width))
                                swap(&x0, &x1)
                            }
                            for width in widths {
                                verticalPass(x0, into: x1, sums: sums.baseAddress!, w: w, h: h, width: Int32(width))
                                swap(&x0, &x1)
                            }
                            let d = dst.baseAddress!
                            for i in 0..<(w * h) {
                                let v = x0[i]
                                d[i] = v >= 255 ? 255 : (v <= 0 ? 0 : UInt8(truncatingIfNeeded: v))
                            }
                        }
                    }
                }
            }
        }
        return AlphaMask(rect: rect, alpha: out)
    }

    /// One moving-sum box of odd `width` along every row, zero outside,
    /// rounded to nearest.
    private static func horizontalPass(_ source: UnsafeMutablePointer<Int32>, into out: UnsafeMutablePointer<Int32>,
                                       w: Int, h: Int, width: Int32) {
        let r = Int((width - 1) / 2)
        let half = width / 2
        for line in 0..<h {
            let src = source + line * w, dst = out + line * w
            var sum: Int32 = 0
            for k in 0...min(r, w - 1) { sum &+= src[k] }
            for i in 0..<w {
                dst[i] = (sum &+ half) / width
                let entering = i + r + 1, leaving = i - r
                if entering < w { sum &+= src[entering] }
                if leaving >= 0 { sum &-= src[leaving] }
            }
        }
    }

    /// One moving-sum box of odd `width` down every column, zero outside,
    /// rounded to nearest — walked row by row with `sums` holding each
    /// column's running sum, so every read and write is sequential.
    private static func verticalPass(_ source: UnsafeMutablePointer<Int32>, into out: UnsafeMutablePointer<Int32>,
                                     sums: UnsafeMutablePointer<Int32>, w: Int, h: Int, width: Int32) {
        let r = Int((width - 1) / 2)
        let half = width / 2
        for x in 0..<w { sums[x] = 0 }
        for k in 0...min(r, h - 1) {
            let src = source + k * w
            for x in 0..<w { sums[x] &+= src[x] }
        }
        for i in 0..<h {
            let dst = out + i * w
            for x in 0..<w { dst[x] = (sums[x] &+ half) / width }
            let entering = i + r + 1, leaving = i - r
            if entering < h {
                let src = source + entering * w
                for x in 0..<w { sums[x] &+= src[x] }
            }
            if leaving >= 0 {
                let src = source + leaving * w
                for x in 0..<w { sums[x] &-= src[x] }
            }
        }
    }
}

/// Coverage masks combined and resampled (ruling GX-J): the union of
/// overlapping silhouettes as alpha compositing does, and a source bitmap
/// (an R8 glyph atlas slot, an RGBA8 image) drawn into a device rectangle
/// under an affine.
package enum AlphaCompositor {
    package enum Filter: Hashable, Sendable { case nearest, bilinear }

    /// `a + b − ab` per pixel, over the union of the two rectangles.
    /// Unchecked row loops (ruling `PF-F` item 2), byte-identical to the
    /// 2155f1e per-pixel lookup: each operand's row is copied into a union-wide
    /// row of zeros, then combined — pinned by
    /// `theFastUnionEqualsTheReferenceByteForByte` (L2.2).
    package static func union(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask {
        if a.rect.isEmpty { return b }
        if b.rect.isEmpty { return a }
        let rect = a.rect.union(b.rect)
        let w = rect.width
        var out = [UInt8](repeating: 0, count: rect.area)
        var rowA = [UInt8](repeating: 0, count: w), rowB = [UInt8](repeating: 0, count: w)
        a.alpha.withUnsafeBufferPointer { pa in
            b.alpha.withUnsafeBufferPointer { pb in
                rowA.withUnsafeMutableBufferPointer { ra in
                    rowB.withUnsafeMutableBufferPointer { rb in
                        out.withUnsafeMutableBufferPointer { po in
                            func fill(_ row: UnsafeMutablePointer<UInt8>, _ m: AlphaMask,
                                      _ p: UnsafePointer<UInt8>, _ y: Int) {
                                for x in 0..<w { row[x] = 0 }
                                guard y >= m.rect.y, y < m.rect.maxY else { return }
                                let src = p + (y - m.rect.y) * m.rect.width, dst = row + (m.rect.x - rect.x)
                                for x in 0..<m.rect.width { dst[x] = src[x] }
                            }
                            let ra = ra.baseAddress!, rb = rb.baseAddress!, o = po.baseAddress!
                            for y in rect.y..<rect.maxY {
                                fill(ra, a, pa.baseAddress!, y)
                                fill(rb, b, pb.baseAddress!, y)
                                let row = o + (y - rect.y) * w
                                for x in 0..<w {
                                    let p = Int(ra[x]), q = Int(rb[x])
                                    row[x] = UInt8(truncatingIfNeeded: p + q - (p * q + 127) / 255)
                                }
                            }
                        }
                    }
                }
            }
        }
        return AlphaMask(rect: rect, alpha: out)
    }

    /// The source's coverage (`channels` 1) or alpha (`channels` 4, the last
    /// byte of each texel) sampled at every pixel centre of `rect`, mapped
    /// back through `transform` (source pixels → device pixels). Bilinear
    /// samples between texel centres; outside the source reads 0.
    package static func resample(source: [UInt8], width: Int, height: Int, channels: Int,
                                 transform: PathAffine, into rect: RasterRect, filter: Filter) -> AlphaMask {
        var out = [UInt8](repeating: 0, count: rect.area)
        guard let inverse = transform.inverted, width > 0, height > 0 else {
            return AlphaMask(rect: rect, alpha: out)
        }
        func texel(_ x: Int, _ y: Int) -> Double {
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return Double(source[(y * width + x) * channels + channels - 1])
        }
        for y in 0..<rect.height {
            for x in 0..<rect.width {
                let p = inverse.apply(PathPoint(Double(rect.x + x) + 0.5, Double(rect.y + y) + 0.5))
                let value: Double
                switch filter {
                case .nearest:
                    value = texel(Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
                case .bilinear:
                    let u = p.x - 0.5, v = p.y - 0.5
                    let u0 = u.rounded(.down), v0 = v.rounded(.down)
                    let fu = u - u0, fv = v - v0
                    let i = Int(u0), j = Int(v0)
                    let top = texel(i, j) * (1 - fu) + texel(i + 1, j) * fu
                    let bottom = texel(i, j + 1) * (1 - fu) + texel(i + 1, j + 1) * fu
                    value = top * (1 - fv) + bottom * fv
                }
                let rounded = value + 0.5
                out[y * rect.width + x] = rounded >= 255 ? 255 : (rounded <= 0 ? 0 : UInt8(rounded))
            }
        }
        return AlphaMask(rect: rect, alpha: out)
    }
}
