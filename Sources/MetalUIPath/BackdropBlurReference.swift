/// The backdrop blur's algorithm in `Float`, on the CPU (rulings `BB-D` 4 and
/// `BB-K`): what both renderers' shaders compute, so a readback has a ground
/// truth on every platform. **Imports nothing** (`GX-B`): the Gaussian's `exp`
/// is this file's own, basic operations only.
///
/// The algorithm, identical in `shaders.metal` and `replay.hlsl`:
///
/// 1. `L = levels(sigma:)` bilinear 2× downsamples, each sample at a texel
///    corner (so the mean of a 2×2 block, the last row/column duplicated
///    when a size is odd); level 0 is the region itself.
/// 2. A separable Gaussian at level `L`, `sigma / 2^L`, taps `±⌈3σ⌉`, the
///    weights computed from σ and normalized (the clamped edge repeats).
/// 3. The upsample: a bilinear read at the output pixel's centre.
///
/// Pixels are premultiplied, four `Float` channels per pixel, row-major.
package enum BackdropBlurReference {
    /// The downsample level count: the smallest `L ≥ 0` with
    /// `sigma / 2^L ≤ 4`, at most `maxLevel` (`MUIBackdropBlurMaxLevel`).
    package static func levels(sigma: Float, maxLevel: Int = 6) -> Int {
        var level = 0
        var s = sigma
        while s > 4, level < maxLevel { s *= 0.5; level += 1 }
        return level
    }

    /// `e^x` for `x ≤ 0` by halving to `|x| < 0.5`, a degree-7 Taylor
    /// polynomial and squaring: no libm.
    package static func expNonPositive(_ x: Float) -> Float {
        if x >= 0 { return 1 }
        if x < -87 { return 0 }
        var y = x
        var squarings = 0
        while y < -0.5 { y *= 0.5; squarings += 1 }
        var term: Float = 1
        var sum: Float = 1
        for n in 1...7 { term *= y / Float(n); sum += term }
        for _ in 0..<squarings { sum *= sum }
        return sum
    }

    /// The normalized one-sided-symmetric kernel `[w₀, w₁ … w_r]` of a
    /// Gaussian with standard deviation `sigma`, `r = ⌈3σ⌉` (`[1]` for
    /// `σ ≤ 0`).
    package static func gaussianWeights(sigma: Float) -> [Float] {
        guard sigma > 0 else { return [1] }
        let radius = Int((3 * sigma).rounded(.up))
        var weights = [Float](repeating: 0, count: radius + 1)
        var total: Float = 0
        for i in 0...radius {
            let w = expNonPositive(-Float(i * i) / (2 * sigma * sigma))
            weights[i] = w
            total += i == 0 ? w : 2 * w
        }
        return weights.map { $0 / total }
    }

    /// One 2× downsample: each output texel is the mean of its 2×2 source
    /// block, an odd edge repeating its last texel.
    package static func downsample(_ src: [Float], width: Int, height: Int) -> (pixels: [Float], width: Int, height: Int) {
        let w = (width + 1) / 2, h = (height + 1) / 2
        var out = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let y0 = min(2 * y, height - 1), y1 = min(2 * y + 1, height - 1)
            for x in 0..<w {
                let x0 = min(2 * x, width - 1), x1 = min(2 * x + 1, width - 1)
                for c in 0..<4 {
                    let a = src[(y0 * width + x0) * 4 + c] + src[(y0 * width + x1) * 4 + c]
                    let b = src[(y1 * width + x0) * 4 + c] + src[(y1 * width + x1) * 4 + c]
                    out[(y * w + x) * 4 + c] = (a + b) * 0.25
                }
            }
        }
        return (out, w, h)
    }

    /// A separable Gaussian, horizontal then vertical, clamped edges.
    package static func gaussian(_ src: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        let weights = gaussianWeights(sigma: sigma)
        let radius = weights.count - 1
        var tmp = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<4 {
                    var sum = weights[0] * src[(y * width + x) * 4 + c]
                    if radius > 0 {
                        for i in 1...radius {
                            let l = max(x - i, 0), r = min(x + i, width - 1)
                            sum += weights[i] * (src[(y * width + l) * 4 + c] + src[(y * width + r) * 4 + c])
                        }
                    }
                    tmp[(y * width + x) * 4 + c] = sum
                }
            }
        }
        var out = [Float](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<4 {
                    var sum = weights[0] * tmp[(y * width + x) * 4 + c]
                    if radius > 0 {
                        for i in 1...radius {
                            let t = max(y - i, 0), b = min(y + i, height - 1)
                            sum += weights[i] * (tmp[(t * width + x) * 4 + c] + tmp[(b * width + x) * 4 + c])
                        }
                    }
                    out[(y * width + x) * 4 + c] = sum
                }
            }
        }
        return out
    }

    /// Blurs `pixels` (`width × height`, premultiplied RGBA `Float`) with
    /// standard deviation `sigma` (device pixels): the whole chain.
    package static func blur(_ pixels: [Float], width: Int, height: Int, sigma: Float) -> [Float] {
        precondition(pixels.count == width * height * 4 && width > 0 && height > 0,
                     "BackdropBlurReference: pixel count does not match the size")
        let level = levels(sigma: sigma)
        var current = pixels
        var w = width, h = height
        for _ in 0..<level { (current, w, h) = downsample(current, width: w, height: h) }
        current = gaussian(current, width: w, height: h, sigma: sigma / Float(1 << level))
        if level == 0 { return current }
        var out = [Float](repeating: 0, count: pixels.count)
        for py in 0..<height {
            let fy = (Float(py) + 0.5) / Float(height) * Float(h) - 0.5
            let y0f = fy.rounded(.down)
            let ty = fy - y0f
            let y0 = min(max(Int(y0f), 0), h - 1), y1 = min(max(Int(y0f) + 1, 0), h - 1)
            for px in 0..<width {
                let fx = (Float(px) + 0.5) / Float(width) * Float(w) - 0.5
                let x0f = fx.rounded(.down)
                let tx = fx - x0f
                let x0 = min(max(Int(x0f), 0), w - 1), x1 = min(max(Int(x0f) + 1, 0), w - 1)
                for c in 0..<4 {
                    let top = current[(y0 * w + x0) * 4 + c] * (1 - tx) + current[(y0 * w + x1) * 4 + c] * tx
                    let bottom = current[(y1 * w + x0) * 4 + c] * (1 - tx) + current[(y1 * w + x1) * 4 + c] * tx
                    out[(py * width + px) * 4 + c] = top * (1 - ty) + bottom * ty
                }
            }
        }
        return out
    }
}
