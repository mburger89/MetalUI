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
    package static func blur(_ mask: AlphaMask, sigma: Double) -> AlphaMask {
        let widths = boxWidths(sigma: sigma)
        guard !widths.isEmpty, !mask.rect.isEmpty else { return mask }
        let pad = padding(sigma: sigma)
        let rect = RasterRect(x: mask.rect.x - pad, y: mask.rect.y - pad,
                              width: mask.rect.width + 2 * pad, height: mask.rect.height + 2 * pad)
        let w = rect.width, h = rect.height
        var a = [Int](repeating: 0, count: w * h)
        for y in 0..<mask.rect.height {
            for x in 0..<mask.rect.width {
                a[(y + pad) * w + x + pad] = Int(mask.alpha[y * mask.rect.width + x])
            }
        }
        var b = [Int](repeating: 0, count: w * h)
        for width in widths { boxPass(a, into: &b, count: w, lines: h, step: 1, lineStep: w, width: width); swap(&a, &b) }
        for width in widths { boxPass(a, into: &b, count: h, lines: w, step: w, lineStep: 1, width: width); swap(&a, &b) }
        return AlphaMask(rect: rect, alpha: a.map { UInt8(min(255, max(0, $0))) })
    }

    /// One moving-sum box of odd `width` along every line, zero outside,
    /// rounded to nearest.
    private static func boxPass(_ source: [Int], into out: inout [Int], count: Int, lines: Int,
                                step: Int, lineStep: Int, width: Int) {
        let r = (width - 1) / 2
        let half = width / 2
        for line in 0..<lines {
            let base = line * lineStep
            var sum = 0
            for k in 0...min(r, count - 1) { sum += source[base + k * step] }
            for i in 0..<count {
                out[base + i * step] = (sum + half) / width
                let entering = i + r + 1, leaving = i - r
                if entering < count { sum += source[base + entering * step] }
                if leaving >= 0 { sum -= source[base + leaving * step] }
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
    package static func union(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask {
        if a.rect.isEmpty { return b }
        if b.rect.isEmpty { return a }
        let rect = a.rect.union(b.rect)
        var out = [UInt8](repeating: 0, count: rect.area)
        for y in rect.y..<rect.maxY {
            for x in rect.x..<rect.maxX {
                let p = Int(a.value(atX: x, y: y)), q = Int(b.value(atX: x, y: y))
                out[(y - rect.y) * rect.width + (x - rect.x)] = UInt8(p + q - (p * q + 127) / 255)
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
