// Measurement probe: what a CPU gradient raster costs (ruling LK-J in
// docs/superpowers/2026-10-08-controls-looks-decisions.md). Not a SwiftUI
// probe and not a test: wall clock is allowed here, never in the suite.
//
// HOW TO RUN:
//
//   xcrun swiftc -O docs/probes/gradient-raster-cost.swift -o /tmp/grad-cost && /tmp/grad-cost
//
// WHAT IT TIMES (median of 7 runs each, premultiplied RGBA8 out):
//   LUT   building a 1024-entry colour table in premultiplied Oklab (two
//         stops) — paid once per gradient value.
//   FULL  a full-surface linear gradient (3200×2000 device pixels: a
//         1600×1000-point window at 2×), per pixel t = dot(p − start, axis)
//         and a table lookup; then the same diagonal; then radial.
//   STRIP the axis-aligned fast path: one 1×2000 column of the same
//         gradient (stretched by the image pipeline, linear filter, no
//         per-pixel work on the other axis).
//   COV   for scale: a coverage-times-colour multiply over the full surface
//         (what a non-rectangular shape adds on top of FULL).
//
// RECORDED 2026-10-08 by the C10 designer, Apple M1 Max, macOS 27.0.1
// (26A434), Apple Swift 6.4, `-O`, run twice (the figures below are the
// first run; the second agreed within 0.06 ms on every line):
//
//   LUT 1024 entries: 0.050 ms
//   FULL vertical 3200x2000: 8.76 ms
//   FULL diagonal 3200x2000: 8.77 ms
//   FULL radial 3200x2000: 14.95 ms
//   STRIP 1x2000: 0.0047 ms
//   COV multiply 3200x2000: 8.89 ms
//   check: LUT midpoint red→blue = (140, 83, 162) (probe G11 reads (140, 83, 162)); sink 1
//
// READING: a full-surface CPU gradient costs ~9 ms of colour plus ~9 ms of
// coverage for a non-rectangular shape, plus a 25.6 MB texture upload, on
// every miss — inside one 16.7 ms frame only when nothing else is drawn, so
// a full raster is acceptable cached (static content) and not per frame (a
// window background during live resize). The strip is ~1/2000 of that. The
// premultiplied-Oklab table reproduces SwiftUI's red→blue midpoint exactly.

import Foundation

struct RGBA { var r, g, b, a: Float }

func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
func linearToSrgb(_ c: Float) -> Float { c <= 0.0031308 ? 12.92 * c : 1.055 * powf(max(c, 0), 1 / 2.4) - 0.055 }

func toOklab(_ c: RGBA) -> (Float, Float, Float) {
    let r = srgbToLinear(c.r), g = srgbToLinear(c.g), b = srgbToLinear(c.b)
    let l = cbrtf(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrtf(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrtf(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func fromOklab(_ L: Float, _ A: Float, _ B: Float) -> (Float, Float, Float) {
    let l = powf(L + 0.3963377774 * A + 0.2158037573 * B, 3)
    let m = powf(L - 0.1055613458 * A - 0.0638541728 * B, 3)
    let s = powf(L - 0.0894841775 * A - 1.2914855480 * B, 3)
    return (linearToSrgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            linearToSrgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            linearToSrgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
}

func lut(_ a: RGBA, _ b: RGBA, count: Int) -> [UInt32] {
    let la = toOklab(a), lb = toOklab(b)
    var out = [UInt32](repeating: 0, count: count)
    for i in 0..<count {
        let t = Float(i) / Float(count - 1)
        let alpha = a.a + (b.a - a.a) * t
        // Premultiplied interpolation (probe G5).
        let L = (la.0 * a.a + (lb.0 * b.a - la.0 * a.a) * t) / max(alpha, 1e-6)
        let A = (la.1 * a.a + (lb.1 * b.a - la.1 * a.a) * t) / max(alpha, 1e-6)
        let B = (la.2 * a.a + (lb.2 * b.a - la.2 * a.a) * t) / max(alpha, 1e-6)
        let (r, g, bl) = fromOklab(L, A, B)
        func byte(_ v: Float) -> UInt32 { UInt32(min(max(v * alpha, 0), 1) * 255 + 0.5) }
        out[i] = byte(r) | byte(g) << 8 | byte(bl) << 16 | UInt32(min(max(alpha, 0), 1) * 255 + 0.5) << 24
    }
    return out
}

func median(_ f: () -> Void) -> Double {
    var times: [Double] = []
    for _ in 0..<7 {
        let t0 = DispatchTime.now().uptimeNanoseconds
        f()
        times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    }
    return times.sorted()[3]
}

let W = 3200, H = 2000
let red = RGBA(r: 1, g: 0, b: 0, a: 1), blue = RGBA(r: 0, g: 0, b: 1, a: 1)
var table: [UInt32] = []
print("LUT 1024 entries: \(String(format: "%.3f", median { table = lut(red, blue, count: 1024) })) ms")
var pixels = [UInt32](repeating: 0, count: W * H)
var sink: UInt32 = 0

func linearFull(sx: Float, sy: Float, ex: Float, ey: Float) {
    let dx = ex - sx, dy = ey - sy, inv = 1 / (dx * dx + dy * dy)
    let n = Float(table.count - 1)
    pixels.withUnsafeMutableBufferPointer { p in
        table.withUnsafeBufferPointer { lut in
            for y in 0..<H {
                let py = Float(y) + 0.5
                var t = ((0.5 - sx) * dx + (py - sy) * dy) * inv
                let step = dx * inv
                let row = y * W
                for x in 0..<W {
                    let i = Int(min(max(t, 0), 1) * n + 0.5)
                    p[row + x] = lut[i]
                    t += step
                }
            }
        }
    }
    sink &+= pixels[W * H / 2]
}
print("FULL vertical 3200x2000: \(String(format: "%.2f", median { linearFull(sx: 0, sy: 0, ex: 0, ey: Float(H)) })) ms")
print("FULL diagonal 3200x2000: \(String(format: "%.2f", median { linearFull(sx: 0, sy: 0, ex: Float(W), ey: Float(H)) })) ms")
func radialFull() {
    let cx = Float(W) / 2, cy = Float(H) / 2, r = Float(H) / 2, n = Float(table.count - 1)
    pixels.withUnsafeMutableBufferPointer { p in
        table.withUnsafeBufferPointer { lut in
            for y in 0..<H {
                let dy = Float(y) + 0.5 - cy
                for x in 0..<W {
                    let dx = Float(x) + 0.5 - cx
                    let t = (dx * dx + dy * dy).squareRoot() / r
                    p[y * W + x] = lut[Int(min(t, 1) * n + 0.5)]
                }
            }
        }
    }
    sink &+= pixels[1]
}
var column = [UInt32](repeating: 0, count: H)
func strip() {
    let n = Float(table.count - 1)
    for y in 0..<H { column[y] = table[Int(min(max((Float(y) + 0.5) / Float(H), 0), 1) * n + 0.5)] }
    sink &+= column[7]
}
var coverage = [UInt8](repeating: 200, count: W * H)
func coverageMultiply() {
    pixels.withUnsafeMutableBufferPointer { p in
        coverage.withUnsafeBufferPointer { c in
            for i in 0..<(W * H) {
                let v = p[i], k = UInt32(c[i])
                let r = ((v & 0xFF) * k + 127) / 255, g = (((v >> 8) & 0xFF) * k + 127) / 255
                let b = (((v >> 16) & 0xFF) * k + 127) / 255, a = ((v >> 24) * k + 127) / 255
                p[i] = r | g << 8 | b << 16 | a << 24
            }
        }
    }
    sink &+= pixels[3]
}
print("FULL radial 3200x2000: \(String(format: "%.2f", median(radialFull))) ms")
print("STRIP 1x2000: \(String(format: "%.4f", median(strip))) ms")
print("COV multiply 3200x2000: \(String(format: "%.2f", median(coverageMultiply))) ms")
let mid = table[511]
print("check: LUT midpoint red→blue = (\(mid & 0xFF), \((mid >> 8) & 0xFF), \((mid >> 16) & 0xFF)) (probe G11 reads (140, 83, 162)); sink \(sink & 1)")
