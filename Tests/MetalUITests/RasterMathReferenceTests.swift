import Testing
import MetalUICore
import MetalUIPath
@testable import MetalUI

// C13 / PERF-a, lane 1 — the mask loops of `RasterCache.swift` against copies
// of their 2155f1e code (rulings `PF-F` item 2, `PF-K` item 2; spec
// `docs/superpowers/specs/2026-10-09-shadow-cache-design.md` test L1.11). The
// copies below are the checked per-pixel loops as they stood at 2155f1e; the
// sources may be rewritten for speed but must answer the same bytes.

/// A deterministic byte stream (a 32-bit LCG's high byte).
private struct LCG {
    var state: UInt32
    mutating func next() -> UInt8 {
        state = state &* 1_664_525 &+ 1_013_904_223
        return UInt8(state >> 24)
    }
}

/// A mask over `rect` of seeded bytes, every fourth one forced to 0 or 255 so
/// the ends of the range are exercised.
private func seeded(_ rect: RasterRect, seed: UInt32) -> AlphaMask {
    var lcg = LCG(state: seed)
    return AlphaMask(rect: rect, alpha: (0..<rect.area).map { i in
        let b = lcg.next()
        return i % 4 == 0 ? (b < 128 ? 0 : 255) : b
    })
}

// MARK: - The 2155f1e copies

private enum Reference {
    static func tint(_ mask: AlphaMask, color: Hsla) -> [UInt8] {
        let rgb = color.toRgba()
        func byte(_ v: Float) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let r = byte(rgb.r), g = byte(rgb.g), b = byte(rgb.b), a = byte(color.a)
        var pixels = [UInt8](repeating: 0, count: mask.alpha.count * 4)
        for i in 0..<mask.alpha.count {
            let alpha = (Int(mask.alpha[i]) * a + 127) / 255
            pixels[i * 4] = UInt8((r * alpha + 127) / 255)
            pixels[i * 4 + 1] = UInt8((g * alpha + 127) / 255)
            pixels[i * 4 + 2] = UInt8((b * alpha + 127) / 255)
            pixels[i * 4 + 3] = UInt8(alpha)
        }
        return pixels
    }

    static func multiply(_ a: AlphaMask, _ b: AlphaMask) -> AlphaMask {
        let r = a.rect.intersection(b.rect)
        guard !r.isEmpty else { return AlphaMask(rect: RasterRect(x: a.rect.x, y: a.rect.y, width: 0, height: 0), alpha: []) }
        var out = [UInt8](repeating: 0, count: r.area)
        for y in 0..<r.height {
            for x in 0..<r.width {
                let p = Int(a.value(atX: r.x + x, y: r.y + y)), q = Int(b.value(atX: r.x + x, y: r.y + y))
                out[y * r.width + x] = UInt8((p * q + 127) / 255)
            }
        }
        return AlphaMask(rect: r, alpha: out)
    }

    static func scale(_ mask: AlphaMask, by factor: Float) -> AlphaMask {
        guard factor < 1 else { return mask }
        let f = Int((max(factor, 0) * 255).rounded())
        return AlphaMask(rect: mask.rect, alpha: mask.alpha.map { UInt8((Int($0) * f + 127) / 255) })
    }

    static func crop(_ mask: AlphaMask, to rect: RasterRect) -> AlphaMask {
        let r = mask.rect.intersection(rect)
        guard !r.isEmpty else { return AlphaMask(rect: RasterRect(x: rect.x, y: rect.y, width: 0, height: 0), alpha: []) }
        if r == mask.rect { return mask }
        var out = [UInt8](repeating: 0, count: r.area)
        for y in 0..<r.height {
            for x in 0..<r.width { out[y * r.width + x] = mask.value(atX: r.x + x, y: r.y + y) }
        }
        return AlphaMask(rect: r, alpha: out)
    }
}

// MARK: - L1.11

private let rects = [RasterRect(x: 0, y: 0, width: 1, height: 1), RasterRect(x: -3, y: 5, width: 17, height: 1),
                     RasterRect(x: 4, y: -2, width: 1, height: 23), RasterRect(x: 10, y: 10, width: 31, height: 19),
                     RasterRect(x: -7, y: 3, width: 64, height: 40), RasterRect(x: 2, y: 2, width: 0, height: 5)]

/// **L1.11** (`PF-F` item 2). `RasterCache.tint` answers the 2155f1e bytes for
/// seeded masks under opaque, translucent, black, white and out-of-range
/// colours. Mutation **M1h**: one `+ 127` rounding changed to `+ 128`.
@Test func tintMatchesItsReferenceCopy() {
    let colours = [Hsla(h: 0.6, s: 0.8, l: 0.5, a: 1), Hsla(h: 0.1, s: 0.5, l: 0.3, a: 0.33),
                   Hsla(h: 0, s: 0, l: 0, a: 1), Hsla(h: 0, s: 0, l: 1, a: 0.5), Hsla(h: 0.9, s: 1, l: 0.7, a: 0),
                   Hsla(h: 0.3, s: 1.2, l: -0.1, a: 1.4)]
    var differing = 0
    for (i, rect) in rects.enumerated() where !rect.isEmpty {
        let mask = seeded(rect, seed: UInt32(i * 7 + 1))
        for colour in colours {
            let texture = RasterCache.tint(mask, color: colour)
            let expected = Reference.tint(mask, color: colour)
            if texture.pixels != expected || texture.width != rect.width || texture.height != rect.height {
                differing += 1
            }
        }
    }
    #expect(differing == 0, "\(differing) of \((rects.count - 1) * colours.count) tints differ from the 2155f1e copy")
}

/// **L1.11** (`PF-F` item 2). `RasterMath.multiply`, `scale` and `crop` answer
/// the 2155f1e masks over every pair of seeded rectangles (overlapping,
/// nested, disjoint, empty) and factors 0, 0.33, 0.5, 0.999, 1, 1.5.
@Test func maskArithmeticMatchesItsReferenceCopies() {
    var multiplies = 0, scales = 0, crops = 0
    for (i, a) in rects.enumerated() {
        let m = seeded(a, seed: UInt32(i + 11))
        for (j, b) in rects.enumerated() {
            let n = seeded(b, seed: UInt32(j + 101))
            if RasterMath.multiply(m, n) != Reference.multiply(m, n) { multiplies += 1 }
            if RasterMath.crop(m, to: b) != Reference.crop(m, to: b) { crops += 1 }
        }
        for factor: Float in [0, 0.33, 0.5, 0.999, 1, 1.5] where RasterMath.scale(m, by: factor) != Reference.scale(m, by: factor) {
            scales += 1
        }
    }
    #expect(multiplies == 0 && scales == 0 && crops == 0,
            "differing: multiply \(multiplies), scale \(scales), crop \(crops)")
}
