@testable import MetalUIPath

// C13 / PERF-a, lane 2 (ruling `PF-F` items 1–2): the 2155f1e `BoxBlur.blur`
// and `AlphaCompositor.union`, copied verbatim (renamed only), so the faster
// loops are pinned byte for byte against the code they replaced (tests L2.1,
// L2.2 in BoxBlurTests.swift). Never edit these to follow the source: they ARE
// the reference.

enum ReferenceBoxBlur {
    /// 2155f1e's `BoxBlur.blur(_:sigma:)`.
    static func blur(_ mask: AlphaMask, sigma: Double) -> AlphaMask {
        let widths = BoxBlur.boxWidths(sigma: sigma)
        guard !widths.isEmpty, !mask.rect.isEmpty else { return mask }
        let pad = BoxBlur.padding(sigma: sigma)
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

    /// 2155f1e's `AlphaCompositor.union(_:_:)`.
    static func union(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask {
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
}
