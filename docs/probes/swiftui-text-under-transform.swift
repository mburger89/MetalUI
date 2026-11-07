// SwiftUI probe: text under transforms and a clip between nested rotations
// (R4-5 PR E; divergences 106 and 109; prefix TZ-, record 222).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//   xcrun swiftc -O docs/probes/swiftui-text-under-transform.swift -o /tmp/tz-probe
//   /tmp/tz-probe 2>&1 | grep -v 'Connection\]'
//
// Run it twice and `cmp` the two outputs. It opens no window; `ImageRenderer`
// needs a window server session (run with the screen unlocked).
//
// INSTRUMENTS (each Z arm has a positive control, group P):
// - INK: `ImageRenderer` at scale 1 onto an opaque white canvas; the subject
//   `fixedSize()` at (ox, oy). `partials` counts pixels with 0 < r < 255 over
//   the whole canvas (black text on white); `differing` counts pixels whose
//   RGB differs; `sad` is the sum of |r difference| / 255 ("ink units"; it
//   falls as two rasters agree).
// - BILINEAR: a CPU bilinear resample of a SwiftUI raster at 1x (or a 2x
//   raster), pixel-centre convention, T15b's code generalised to any inverse
//   map. P2 checks it reproduces T15b's 1237.
// - VECTOR: CoreGraphics `CTLineDraw` of the same string in
//   `NSFont.systemFont(ofSize:)`, drawn under a CTM (scale, rotation) about
//   the same pivot, font smoothing off, sub-pixel positioning on. Its pen
//   offset inside the frame is CALIBRATED on the upright control (P3 prints
//   the offset and the residual); the transformed references reuse it. The
//   reference is therefore only as good as P3's residual: read a Z arm as
//   "which of the two references is nearer", never as an absolute.
// - QUAD (Z5, NC3): the projected quad of a solid-colour rect of the same
//   frame under the same `rotation3DEffect`, fitted from column coverage
//   (vertical edges, two slanted lines); a homography from it warps the 1x
//   or 2x raster. Good to about 0.1 px (P4 prints the fit residual).
//
// Z arms are for 106, NC arms for 109. The on-screen renderer is not
// ImageRenderer; that gap is human check TZ1.
//
// [MEASURED] 2026-11-06, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9),
// screen unlocked. Compiled with `-O`, run twice, stdout byte-identical
// (25 lines), exit 0:
//
//   --- P: positive controls
//   P1 partials: Text(20) 164 Text(40) 298; the two differ in 879px
//   P2 bilinear 2x of the 20 pt raster (generic warp): partials 1237
//   P3 CoreText vector reference, upright 20 pt: pen offset (0.00, 19.00) residual sad 22.7 of ink 146.2
//   --- Z: text under transforms
//   Z0 T15b verbatim resample: 1237px differ (T15b recorded 1444); partials upscale 1237
//   Z0 T15b: scaled vs bilinear upscale 1237px differ; partial pixels: scaled 326 upscale 1237 40pt 298; vector(CTM 2) 317; sad(scaled,40pt) 281.1
//   Z1 scaleEffect(1.5): partials sw 246 bilinear 685 vector 253 | sad(sw,bilinear) 97.9 sad(sw,vector) 61.4 | Text(30) partials 237 sad(sw,Text30) 102.9
//   Z2 scaleEffect(0.5): partials sw 77 bilinear 81 vector 79 | sad(sw,bilinear) 18.5 sad(sw,vector) 18.0 (bilinear column = 2x2 box) | Text(10) partials 77 sad(sw,Text10) 19.7
//   Z3 rotationEffect(30): partials sw 187 bilinear 303 vector 194 | sad(sw,bilinear) 42.7 sad(sw,vector) 25.5
//   Z3 control (upright, no rotation): sad(sw,vector) 22.7; the vector reference is trusted when Z3's sad(sw,vector) is of that order
//   Z4 scaleEffect(2).rotationEffect(30): partials sw 380 bilinear 1221 vector 384 | sad(sw,bilinear) 197.9 sad(sw,vector) 92.6 | reverse order differs from it in 0px (partials 380)
//   P4 quad fit for Z5: TL (58.27,44.15) TR (83.84,53.09) BR (83.84,71.91) BL (58.27,80.85) rms 0.01
//   Z5 rotation3DEffect(40, y, perspective 1): partials sw 363 1x raster projected 317 supersampled vector 200 | sad(sw,1x) 21.3 sad(sw,vector) 38.8 sad(1x,vector) 25.3
//   Z5b scaleEffect(2) then rotation3DEffect(40, y, perspective 1): partials sw 1844 1x raster projected 2823 2x device-scale raster projected 1255 supersampled vector 600 | sad(sw,1x) 403.8 sad(sw,2x) 244.9 sad(sw,vector) 319.5 sad(1x,vector) 513.4
//   Z6 scaleEffect(x: 2, y: 1): partials sw 227 bilinear 512 vector 215 | sad(sw,bilinear) 68.6 sad(sw,vector) 48.4 | uniform 2x raster squeezed: partials 229 sad(sw,squeezed) 12.7
//   Z7 scaleEffect(8) of 20 pt H (160 pt on screen): partials sw 578 Text(160) 477 bilinear 9648 | sad(sw,native) 1610.1 sad(sw,bilinear) 1744.3 sad(native,bilinear) 2308.0
//   Z7 scaleEffect(20) of 20 pt H (400 pt on screen): partials sw 1443 Text(400) 1443 bilinear 59763 | sad(sw,native) 9859.3 sad(sw,bilinear) 11954.4 sad(native,bilinear) 14424.8
//   --- NC: a clip between nested effects (60x60 clip, centre (90, 80))
//   NC0 T7 clipped() then rotationEffect(90): x20 y-20 w20 h60 n1200 | T7b rotationEffect(90) then clipped(): x40 y0 w20 h20 n400
//   NC1 clipped() between two 30 rotations: ink outside the exact rotated square (>1px) 0 (>=50% 0); inside 3600 of 3600; box model would add 2724 outside pixels
//   NC2 clipShape(RoundedRectangle(12)): ink outside the exact rounded square (>1px) 0 (>=50% 0); corner-cut ink >=50% 0; inside 3476 (analytic 3476.4); outside the plain square 0
//   NC3 clipped() then rotation3DEffect(40, y, perspective 1): ink outside the projected quad (>1px) 6 (>=50% 0); inside 3424; control, the solid rect's own ink outside its fitted quad 6 (fit rms 0.01)
//   NC4 clipShape(Ellipse) 60x40 between two 30 rotations: ink outside the exact ellipse (>1px) 0 (>=50% 0); inside 1892 (analytic 1885.0)
//   NC5 clip outside a flattening scaleEffect(2) of the inner rotation: ink outside the exact rotated square (>1px) 0 (>=50% 0); inside 3600 of 3600
//
// READING (rulings TZ-; the decisions doc has each in full):
// - Z0 reproduces T15b's partial counts exactly (326 scaled / 298 40 pt / 1237
//   bilinear). Its "differing" count is 1237 here against the 1444 T15b
//   recorded on 2026-10-02 (the macOS 27.0.1 raster differed by a few
//   pixels); the partial counts, which carry the claim, did not move.
// - Z1, Z6, Z7: under `scaleEffect` SwiftUI RE-RASTERIZES at the effective
//   scale, on both axes independently (Z6: 227 partials; the device-scale-2
//   raster squeezed 229, a bilinear resample 512) and without a visible cap:
//   a 20 pt "H" at 20x has exactly the 1443 partials of a native 400 pt "H"
//   (Z7). Z1's 1.5x has 246 partials against 253 for the vector reference,
//   237 for native 30 pt and 685 for a resample, so a ladder step of 1.5 is
//   not needed to match; the rung size is MetalUI's choice. Z2 (0.5x) does
//   not separate re-rasterization from a box downsample (77 / 81 / 79).
// - Z3, Z4: under `rotationEffect` SwiftUI is VECTOR-exact, not a resample of
//   the upright raster: Z3 187 partials against 194 (CoreText rotated) and
//   303 (bilinear rotation), sad 25.5 against 42.7, where the vector
//   reference's own floor on the upright control is 22.7. Z4: scale then
//   rotate and rotate then scale are pixel-identical (0px) and vector-exact
//   (380 against 384 and 1221). So rotated and skewed text remains a
//   residue of 106 in MetalUI, which rasterizes upright and resamples.
// - Z5: under `rotation3DEffect` alone SwiftUI RESAMPLES the 1x raster:
//   sad(sw, projected 1x) 21.3 at the control floor, against 38.8 for a
//   supersampled vector projection. A projection with no scale in it is
//   therefore NOT a 106 difference. Z5b (scaleEffect(2) then rotation3D):
//   the text is sharper than a resample of the 1x raster (1844 partials
//   against 2823) and nearer the 2x device-scale raster (sad 244.9 against
//   403.8): SwiftUI rasterizes at the SCALE and resamples through the
//   projection. The projective factor itself must not raise the raster
//   scale (the plan's sigma over the Jacobian is not supported by Z5).
// - NC1, NC2, NC3, NC4, NC5: a clip between two rotations is EXACT in
//   SwiftUI: zero ink beyond 1 px of the rotated 60x60 square (NC1; the
//   screen bounding-box model would paint 2724 more pixels), of the rotated
//   rounded square, with the corners cut (NC2: 3476 inside, analytic
//   3476.4), of the projected quad under `rotation3DEffect` (NC3: 6, the
//   same 6 the solid rect itself has beyond its fitted quad), of the rotated
//   ellipse (NC4) and with a flattening `scaleEffect(2)` inside the clip
//   (NC5). Divergence 109 is real.
// - Instruments' limits: P3's residual (22.7 of 146.2 ink) is the vector
//   reference's own noise, a few percent of the ink; the 4-tap bilinear and
//   the 4 x 4 supersample are the CPU stand-ins for SwiftUI's own filters.

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

extension Color {
    static let pr = Color(.sRGB, red: 1, green: 0, blue: 0)
}

// ---------------------------------------------------------------- bitmaps
struct Bmp { var b: [UInt8]; var w: Int; var h: Int
    func g(_ x: Int, _ y: Int) -> Int { (x < 0 || y < 0 || x >= w || y >= h) ? 255 : Int(b[(y * w + x) * 4 + 1]) }
    func r(_ x: Int, _ y: Int) -> Int { (x < 0 || y < 0 || x >= w || y >= h) ? 255 : Int(b[(y * w + x) * 4]) }
}
func bmp(_ cg: CGImage) -> Bmp {
    let w = cg.width, h = cg.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Bmp(b: b, w: w, h: h)
}
func blank(_ w: Int, _ h: Int) -> Bmp { Bmp(b: [UInt8](repeating: 255, count: w * h * 4), w: w, h: h) }

struct Cv { var w = 240, h = 200, ox = 60, oy = 50 }
/// The subject at (ox, oy) on a white canvas, as the paths/shadows probe does.
/// `scale` 2 is a true device-scale-2 raster of the same layout (Z5, Z6).
@MainActor func render(_ v: some View, _ c: Cv = Cv(), scale: CGFloat = 1) -> Bmp {
    let s = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().padding(.leading, CGFloat(c.ox)).padding(.top, CGFloat(c.oy))
    }.frame(width: CGFloat(c.w), height: CGFloat(c.h), alignment: .topLeading)
    let r = ImageRenderer(content: s)
    r.scale = scale
    return bmp(r.cgImage!)
}

func partials(_ b: Bmp) -> Int { var n = 0; for y in 0..<b.h { for x in 0..<b.w { let v = b.r(x, y); if v > 0 && v < 255 { n += 1 } } }; return n }
func inkCount(_ b: Bmp) -> Int { var n = 0; for y in 0..<b.h { for x in 0..<b.w where b.r(x, y) < 255 || b.g(x, y) < 255 { n += 1 } }; return n }
func differing(_ a: Bmp, _ b: Bmp) -> Int {
    var n = 0
    for i in stride(from: 0, to: min(a.b.count, b.b.count), by: 4) where a.b[i] != b.b[i] || a.b[i + 1] != b.b[i + 1] || a.b[i + 2] != b.b[i + 2] { n += 1 }
    return n
}
func sad(_ a: Bmp, _ b: Bmp) -> Double {
    var s = 0
    for i in stride(from: 0, to: min(a.b.count, b.b.count), by: 4) { s += abs(Int(a.b[i]) - Int(b.b[i])) }
    return (Double(s) / 255 * 10).rounded() / 10
}
func f1(_ v: Double) -> String { String(format: "%.1f", v) }
func f2(_ v: Double) -> String { String(format: "%.2f", v) }

/// Bilinear resample of a grey (black on white) raster `src`; `inv` maps a
/// destination pixel centre to a source continuous coordinate.
func warp(_ src: Bmp, _ w: Int, _ h: Int, _ inv: (Double, Double) -> (Double, Double)) -> Bmp {
    var out = blank(w, h)
    for y in 0..<h { for x in 0..<w {
        let (sx, sy) = inv(Double(x) + 0.5, Double(y) + 0.5)
        let fx0 = sx - 0.5, fy0 = sy - 0.5
        let x0 = Int(fx0.rounded(.down)), y0 = Int(fy0.rounded(.down))
        let fx = fx0 - Double(x0), fy = fy0 - Double(y0)
        func s(_ X: Int, _ Y: Int) -> Double { Double(src.r(X, Y)) }
        let v = (s(x0, y0) * (1 - fx) + s(x0 + 1, y0) * fx) * (1 - fy) + (s(x0, y0 + 1) * (1 - fx) + s(x0 + 1, y0 + 1) * fx) * fy
        let i = (y * w + x) * 4; let q = UInt8(max(0, min(255, v.rounded())))
        out.b[i] = q; out.b[i + 1] = q; out.b[i + 2] = q
    } }
    return out
}

/// `warp` with n x n sub-samples per destination pixel (a coverage-accurate
/// projection of a high-resolution raster: the projective "vector" reference).
func warpSS(_ src: Bmp, _ w: Int, _ h: Int, n: Int, _ inv: (Double, Double) -> (Double, Double)) -> Bmp {
    var out = blank(w, h)
    for y in 0..<h { for x in 0..<w {
        var acc = 0.0
        for j in 0..<n { for i in 0..<n {
            let (sx, sy) = inv(Double(x) + (Double(i) + 0.5) / Double(n), Double(y) + (Double(j) + 0.5) / Double(n))
            let fx0 = sx - 0.5, fy0 = sy - 0.5
            let x0 = Int(fx0.rounded(.down)), y0 = Int(fy0.rounded(.down))
            let fx = fx0 - Double(x0), fy = fy0 - Double(y0)
            func q(_ X: Int, _ Y: Int) -> Double { Double(src.r(X, Y)) }
            acc += (q(x0, y0) * (1 - fx) + q(x0 + 1, y0) * fx) * (1 - fy) + (q(x0, y0 + 1) * (1 - fx) + q(x0 + 1, y0 + 1) * fx) * fy
        } }
        let k = (y * w + x) * 4; let v = UInt8(max(0, min(255, (acc / Double(n * n)).rounded())))
        out.b[k] = v; out.b[k + 1] = v; out.b[k + 2] = v
    } }
    return out
}

// ---------------------------------------------------------------- vector reference
/// `text` drawn with CoreText in the system font at `size`, pen origin
/// (`px`, `py`) in canvas coordinates (y down), under the affine `m` about
/// `pivot`.
func cgText(_ text: String, size: CGFloat, px: Double, py: Double, pivot: CGPoint, m: CGAffineTransform, _ c: Cv) -> Bmp {
    var b = [UInt8](repeating: 255, count: c.w * c.h * 4)
    let ctx = CGContext(data: &b, width: c.w, height: c.h, bitsPerComponent: 8, bytesPerRow: c.w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
    ctx.setAllowsFontSmoothing(false); ctx.setShouldSmoothFonts(false)
    ctx.setAllowsFontSubpixelPositioning(true); ctx.setShouldSubpixelPositionFonts(true)
    ctx.setAllowsFontSubpixelQuantization(false); ctx.setShouldSubpixelQuantizeFonts(false)
    ctx.translateBy(x: 0, y: CGFloat(c.h)); ctx.scaleBy(x: 1, y: -1)          // y down
    ctx.translateBy(x: pivot.x, y: pivot.y); ctx.concatenate(m); ctx.translateBy(x: -pivot.x, y: -pivot.y)
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: px, y: py)
    let a = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
    CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
    return Bmp(b: b, w: c.w, h: c.h)
}

// ---------------------------------------------------------------- homography
func solve(_ a: [[Double]], _ b: [Double]) -> [Double] {
    var m = a.enumerated().map { $0.element + [b[$0.offset]] }
    let n = b.count
    for i in 0..<n {
        let p = (i..<n).max { abs(m[$0][i]) < abs(m[$1][i]) }!
        m.swapAt(i, p)
        for j in 0..<n where j != i { let f = m[j][i] / m[i][i]; for k in i...n { m[j][k] -= f * m[i][k] } }
    }
    return (0..<n).map { m[$0][n] / m[$0][$0] }
}
/// Homography taking the four `from` points to the four `to` points.
func homography(_ from: [(Double, Double)], _ to: [(Double, Double)]) -> [Double] {
    var a: [[Double]] = [], b: [Double] = []
    for i in 0..<4 {
        let (x, y) = from[i], (u, v) = to[i]
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    }
    return solve(a, b) + [1]
}
func apply(_ h: [Double], _ x: Double, _ y: Double) -> (Double, Double) {
    let w = h[6] * x + h[7] * y + h[8]
    return ((h[0] * x + h[1] * y + h[2]) / w, (h[3] * x + h[4] * y + h[5]) / w)
}
func invert3(_ h: [Double]) -> [Double] {
    let (a, b, c, d, e, f, g, hh, i) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8])
    let det = a * (e * i - f * hh) - b * (d * i - f * g) + c * (d * hh - e * g)
    return [(e * i - f * hh) / det, (c * hh - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * hh - e * g) / det, (b * g - a * hh) / det, (a * e - b * d) / det]
}
/// Fit the quad a solid-red rect covers after a rotation about the y axis
/// (vertical left/right edges, slanted top and bottom): TL, TR, BR, BL, and
/// the rms residual of the two column fits.
func fitQuad(_ b: Bmp) -> (quad: [(Double, Double)], rms: Double) {
    var A = [Double](repeating: 0, count: b.w), M = A
    for y in 0..<b.h { for x in 0..<b.w {
        let c = 1 - Double(b.g(x, y)) / 255
        A[x] += c; M[x] += c * (Double(y) + 0.5)
    } }
    let cols = (0..<b.w).filter { A[$0] > 0.01 }
    let e0 = cols.first!, e1 = cols.last!
    let xs = Array((e0 + 2)...(e1 - 2))
    func fit(_ ys: [Double]) -> (Double, Double) {
        let n = Double(xs.count), sx = xs.reduce(0) { $0 + Double($1) + 0.5 }, sy = ys.reduce(0, +)
        let sxx = xs.reduce(0) { $0 + (Double($1) + 0.5) * (Double($1) + 0.5) }
        let sxy = zip(xs, ys).reduce(0) { $0 + (Double($1.0) + 0.5) * $1.1 }
        let k = (n * sxy - sx * sy) / (n * sxx - sx * sx); return (k, (sy - k * sx) / n)
    }
    let (hk, hc) = fit(xs.map { A[$0] }), (ck, cc) = fit(xs.map { M[$0] / A[$0] })
    var res = 0.0
    for x in xs { let dh = A[x] - (hk * (Double(x) + 0.5) + hc), dc = M[x] / A[x] - (ck * (Double(x) + 0.5) + cc); res += dh * dh + dc * dc }
    let hAt = { (x: Double) in hk * x + hc }, cAt = { (x: Double) in ck * x + cc }
    let xl = Double(e0 + 1) - A[e0] / hAt(Double(e0) + 0.5)
    let xr = Double(e1) + A[e1] / hAt(Double(e1) + 0.5)
    func pt(_ x: Double, _ s: Double) -> (Double, Double) { (x, cAt(x) + s * hAt(x) / 2) }
    return ([pt(xl, -1), pt(xr, -1), pt(xr, 1), pt(xl, 1)], (res / Double(xs.count)).squareRoot())
}

/// Signed distance (positive outside) of a pixel centre to a convex quad
/// listed clockwise on screen.
func quadOutside(_ q: [(Double, Double)], _ x: Double, _ y: Double) -> Double {
    var worst = -Double.infinity
    for i in 0..<4 {
        let (x0, y0) = q[i], (x1, y1) = q[(i + 1) % 4]
        let len = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).squareRoot()
        let d = ((x - x0) * (y1 - y0) - (y - y0) * (x1 - x0)) / len   // clockwise in y-down: inside is negative
        worst = max(worst, d)
    }
    return worst
}

// ---------------------------------------------------------------- the arms
let base = Cv()                       // 240 x 200, subject at (60, 50)
let W = 30.0, H = 25.0                // the 20 pt "Hg" frame
func txt(_ size: CGFloat) -> some View { Text("Hg").font(.system(size: size)).foregroundStyle(Color.black).fixedSize() }
@MainActor func upright(_ size: CGFloat, w: Double, h: Double, _ c: Cv = base) -> Bmp {
    render(txt(size).frame(width: w, height: h, alignment: .topLeading), c)
}

MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)

print("--- P: positive controls")
// P1: the instrument tells 20 pt from 40 pt text (T15's 499 differing).
let small = upright(20, w: W, h: H)
let big = upright(40, w: 2 * W, h: 2 * H)
print("P1 partials: Text(20) \(partials(small)) Text(40) \(partials(big)); the two differ in \(differing(small, big))px")

// P2: the generic bilinear warp reproduces T15b's upscale (1237 partials).
let up2 = warp(small, base.w, base.h) { x, y in (Double(base.ox) + (x - Double(base.ox)) / 2, Double(base.oy) + (y - Double(base.oy)) / 2) }
print("P2 bilinear 2x of the 20 pt raster (generic warp): partials \(partials(up2))")

// P3: calibrate the CoreText pen inside the frame on the upright control.
var best = (sad: Double.infinity, dx: 0.0, dy: 0.0)
for dxi in -8...8 { for dyi in 12...30 {
    let dx = Double(dxi) * 0.25, dy = Double(dyi)
    let r = cgText("Hg", size: 20, px: Double(base.ox) + dx, py: Double(base.oy) + dy, pivot: .zero, m: .identity, base)
    let s = sad(small, r)
    if s < best.sad { best = (s, dx, dy) }
} }
for dyi in stride(from: -3.0, through: 3.0, by: 0.25) {
    let dy = best.dy + dyi
    let r = cgText("Hg", size: 20, px: Double(base.ox) + best.dx, py: Double(base.oy) + dy, pivot: .zero, m: .identity, base)
    let s = sad(small, r); if s < best.sad { best = (s, best.dx, dy) }
}
let penX = Double(base.ox) + best.dx, penY = Double(base.oy) + best.dy
print("P3 CoreText vector reference, upright 20 pt: pen offset (\(f2(best.dx)), \(f2(best.dy))) residual sad \(f1(best.sad)) of ink \(f1(sad(small, blank(base.w, base.h))))")

/// The CG reference at 20 pt under `m` about `pivot` (canvas coordinates).
func cg(_ m: CGAffineTransform, pivot: CGPoint, _ c: Cv = base) -> Bmp {
    cgText("Hg", size: 20, px: penX, py: penY, pivot: pivot, m: m, c)
}
let tl = CGPoint(x: base.ox, y: base.oy)

func line(_ name: String, _ sw: Bmp, bilinear: Bmp, vector: Bmp, extra: String = "") {
    print("\(name): partials sw \(partials(sw)) bilinear \(partials(bilinear)) vector \(partials(vector)) | sad(sw,bilinear) \(f1(sad(sw, bilinear))) sad(sw,vector) \(f1(sad(sw, vector)))\(extra)")
}

print("--- Z: text under transforms")
// Z0: T15b again. Expected scaled 326 / 40 pt 298 / bilinear upscale 1237.
do {
    let scaled = render(txt(20).frame(width: W, height: H, alignment: .topLeading).scaleEffect(2, anchor: .topLeading).frame(width: 60, height: 50, alignment: .topLeading))
    // T15b's own resample, clamping to the 30 x 25 frame as it did.
    var upT = scaled
    for y in 0..<50 { for x in 0..<60 {
        let sx = (Double(x) + 0.5) / 2 - 0.5, sy = (Double(y) + 0.5) / 2 - 0.5
        let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down)), fx = sx - Double(x0), fy = sy - Double(y0)
        func s(_ X: Int, _ Y: Int) -> Double { Double(small.r(min(max(X, 0), 29) + base.ox, min(max(Y, 0), 24) + base.oy)) }
        let v = (s(x0, y0) * (1 - fx) + s(x0 + 1, y0) * fx) * (1 - fy) + (s(x0, y0 + 1) * (1 - fx) + s(x0 + 1, y0 + 1) * fx) * fy
        let i = ((y + base.oy) * upT.w + x + base.ox) * 4; let q = UInt8(v.rounded()); upT.b[i] = q; upT.b[i + 1] = q; upT.b[i + 2] = q
    } }
    print("Z0 T15b verbatim resample: \(differing(upT, scaled))px differ (T15b recorded 1444); partials upscale \(partials(upT))")
    print("Z0 T15b: scaled vs bilinear upscale \(differing(up2, scaled))px differ; partial pixels: scaled \(partials(scaled)) upscale \(partials(up2)) 40pt \(partials(big)); vector(CTM 2) \(partials(cg(CGAffineTransform(scaleX: 2, y: 2), pivot: tl))); sad(scaled,40pt) \(f1(sad(scaled, big)))")
}
// Z1: 1.5x.
do {
    let sw = render(txt(20).frame(width: W, height: H, alignment: .topLeading).scaleEffect(1.5, anchor: .topLeading).frame(width: 60, height: 50, alignment: .topLeading))
    let native = upright(30, w: 1.5 * W, h: 1.5 * H)
    let bl = warp(small, base.w, base.h) { x, y in (Double(base.ox) + (x - Double(base.ox)) / 1.5, Double(base.oy) + (y - Double(base.oy)) / 1.5) }
    line("Z1 scaleEffect(1.5)", sw, bilinear: bl, vector: cg(CGAffineTransform(scaleX: 1.5, y: 1.5), pivot: tl), extra: " | Text(30) partials \(partials(native)) sad(sw,Text30) \(f1(sad(sw, native)))")
}
// Z2: 0.5x against Text(10) and a 2x2 box downsample.
do {
    let sw = render(txt(20).frame(width: W, height: H, alignment: .topLeading).scaleEffect(0.5, anchor: .topLeading).frame(width: 60, height: 50, alignment: .topLeading))
    let native = upright(10, w: 0.5 * W, h: 0.5 * H)
    var box = blank(base.w, base.h)
    for y in 0..<base.h { for x in 0..<base.w {
        let sx = base.ox + (x - base.ox) * 2, sy = base.oy + (y - base.oy) * 2
        guard x >= base.ox, y >= base.oy else { continue }
        let v = (small.r(sx, sy) + small.r(sx + 1, sy) + small.r(sx, sy + 1) + small.r(sx + 1, sy + 1)) / 4
        let i = (y * base.w + x) * 4; box.b[i] = UInt8(v); box.b[i + 1] = UInt8(v); box.b[i + 2] = UInt8(v)
    } }
    line("Z2 scaleEffect(0.5)", sw, bilinear: box, vector: cg(CGAffineTransform(scaleX: 0.5, y: 0.5), pivot: tl), extra: " (bilinear column = 2x2 box) | Text(10) partials \(partials(native)) sad(sw,Text10) \(f1(sad(sw, native)))")
}
// Z3: rotation 30 degrees about the frame centre: THE separating arm.
let centre = CGPoint(x: Double(base.ox) + W / 2, y: Double(base.oy) + H / 2)
do {
    let sw = render(txt(20).frame(width: W, height: H, alignment: .topLeading).rotationEffect(.degrees(30)))
    let a = 30.0 * .pi / 180, ca = cos(a), sa = sin(a)
    let bl = warp(small, base.w, base.h) { x, y in
        let dx = x - centre.x, dy = y - centre.y
        return (centre.x + ca * dx + sa * dy, centre.y - sa * dx + ca * dy)
    }
    let vec = cg(CGAffineTransform(rotationAngle: a), pivot: centre)
    line("Z3 rotationEffect(30)", sw, bilinear: bl, vector: vec)
    let ctlUp = sad(small, cg(.identity, pivot: centre))
    print("Z3 control (upright, no rotation): sad(sw,vector) \(f1(ctlUp)); the vector reference is trusted when Z3's sad(sw,vector) is of that order")
}
// Z4: scale then rotate, and the reverse (same pivot, so they commute in effect).
do {
    let a = 30.0 * .pi / 180
    let m = CGAffineTransform(rotationAngle: a).scaledBy(x: 2, y: 2)
    let fr = txt(20).frame(width: W, height: H, alignment: .topLeading)
    let sr = render(fr.scaleEffect(2).rotationEffect(.degrees(30)))
    let rs = render(fr.rotationEffect(.degrees(30)).scaleEffect(2))
    let ca = cos(a), sa = sin(a)
    let bl = warp(small, base.w, base.h) { x, y in
        let dx = x - centre.x, dy = y - centre.y
        return (centre.x + (ca * dx + sa * dy) / 2, centre.y + (-sa * dx + ca * dy) / 2)
    }
    line("Z4 scaleEffect(2).rotationEffect(30)", sr, bilinear: bl, vector: cg(m, pivot: centre), extra: " | reverse order differs from it in \(differing(sr, rs))px (partials \(partials(rs)))")
}
// Z5: rotation3DEffect, axis y, perspective 1; Z5b with a scaleEffect(2) first.
@MainActor func z5(_ name: String, _ scale: Double, _ show: Bool) {
    let c1 = base
    func fx<V: View>(_ v: V) -> some View {
        v.scaleEffect(scale).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0), perspective: 1)
    }
    let sw = render(fx(txt(20).frame(width: W, height: H, alignment: .topLeading)))
    let rect = render(fx(Color.pr.frame(width: W, height: H)))
    let (quad, rms) = fitQuad(rect)
    let local = [(Double(c1.ox), Double(c1.oy)), (Double(c1.ox) + W, Double(c1.oy)), (Double(c1.ox) + W, Double(c1.oy) + H), (Double(c1.ox), Double(c1.oy) + H)]
    let hInv = invert3(homography(local, quad))
    let b1 = warp(small, c1.w, c1.h) { x, y in apply(hInv, x, y) }
    // The scale-factor raster: the same 20 pt layout rendered at device scale `scale`.
    let big2 = render(txt(20).frame(width: W, height: H, alignment: .topLeading), c1, scale: CGFloat(scale))
    let b2 = warp(big2, c1.w, c1.h) { x, y in let (u, v) = apply(hInv, x, y); return (scale * u, scale * v) }
    // The projective "vector" reference: the same layout at device scale 4 times the scale, supersampled 4 x 4.
    let k = 4 * Int(scale)
    let big4 = render(txt(20).frame(width: W, height: H, alignment: .topLeading), c1, scale: CGFloat(k))
    let vec = warpSS(big4, c1.w, c1.h, n: 4) { x, y in let (u, v) = apply(hInv, x, y); return (Double(k) * u, Double(k) * v) }
    if show { print("P4 quad fit for Z5: TL (\(f2(quad[0].0)),\(f2(quad[0].1))) TR (\(f2(quad[1].0)),\(f2(quad[1].1))) BR (\(f2(quad[2].0)),\(f2(quad[2].1))) BL (\(f2(quad[3].0)),\(f2(quad[3].1))) rms \(f2(rms))") }
    print("\(name): partials sw \(partials(sw)) 1x raster projected \(partials(b1))" + (scale == 1 ? "" : " \(Int(scale))x device-scale raster projected \(partials(b2))") + " supersampled vector \(partials(vec)) | sad(sw,1x) \(f1(sad(sw, b1)))" + (scale == 1 ? "" : " sad(sw,\(Int(scale))x) \(f1(sad(sw, b2)))") + " sad(sw,vector) \(f1(sad(sw, vec))) sad(1x,vector) \(f1(sad(b1, vec)))")
}
z5("Z5 rotation3DEffect(40, y, perspective 1)", 1, true)
z5("Z5b scaleEffect(2) then rotation3DEffect(40, y, perspective 1)", 2, false)
// Z6: scaleEffect(x: 2, y: 1) about the centre.
do {
    let sw = render(txt(20).frame(width: W, height: H, alignment: .topLeading).scaleEffect(x: 2, y: 1))
    let m = CGAffineTransform(scaleX: 2, y: 1)
    // A uniform device-scale-2 raster of the same layout, squeezed in y by 1/2.
    let big2 = render(txt(20).frame(width: W, height: H, alignment: .topLeading), base, scale: 2)
    let sq = warp(big2, base.w, base.h) { x, y in
        (2 * centre.x + 2 * (x - centre.x) / 2, 2 * centre.y + 2 * (y - centre.y))
    }
    let bl = warp(small, base.w, base.h) { x, y in (centre.x + (x - centre.x) / 2, y) }
    line("Z6 scaleEffect(x: 2, y: 1)", sw, bilinear: bl, vector: cg(m, pivot: centre), extra: " | uniform 2x raster squeezed: partials \(partials(sq)) sad(sw,squeezed) \(f1(sad(sw, sq)))")
}
// Z7: how far does the re-rasterization go? "H" at 20 pt, scaled 8 and 20.
for s in [8.0, 20.0] {
    let c = Cv(w: Int(16 * s) + 60, h: Int(24 * s) + 60, ox: 30, oy: 30)
    let fr = Text("H").font(.system(size: 20)).foregroundStyle(Color.black).fixedSize().frame(width: 16, height: 24, alignment: .topLeading)
    let sw = render(fr.scaleEffect(s, anchor: .topLeading).frame(width: 16 * s, height: 24 * s, alignment: .topLeading), c)
    let native = render(Text("H").font(.system(size: 20 * s)).foregroundStyle(Color.black).fixedSize().frame(width: 16 * s, height: 24 * s, alignment: .topLeading), c)
    let one = render(fr, c)
    let bl = warp(one, c.w, c.h) { x, y in (Double(c.ox) + (x - Double(c.ox)) / s, Double(c.oy) + (y - Double(c.oy)) / s) }
    print("Z7 scaleEffect(\(Int(s))) of 20 pt H (\(Int(20 * s)) pt on screen): partials sw \(partials(sw)) Text(\(Int(20 * s))) \(partials(native)) bilinear \(partials(bl)) | sad(sw,native) \(f1(sad(sw, native))) sad(sw,bilinear) \(f1(sad(sw, bl))) sad(native,bilinear) \(f1(sad(native, bl)))")
}

// ------------------------------------------------------------ nested clips
print("--- NC: a clip between nested effects (60x60 clip, centre (\(base.ox + 30), \(base.oy + 30)))")
let cxy = (x: Double(base.ox) + 30, y: Double(base.oy) + 30)
func local(_ x: Double, _ y: Double, deg: Double) -> (Double, Double) {
    let a = deg * .pi / 180
    let dx = x - cxy.x, dy = y - cxy.y
    return (cos(a) * dx + sin(a) * dy, -sin(a) * dx + cos(a) * dy)
}
/// Pixels of `b` darker than `level` (g channel) for which `outside` is more
/// than `band` px outside the exact shape; and the same count of those inside.
func outside(_ b: Bmp, band: Double = 1, level: Int = 255, _ dist: (Double, Double) -> Double) -> (out: Int, out50: Int, inside: Int) {
    var o = 0, o50 = 0, i = 0
    for y in 0..<b.h { for x in 0..<b.w where b.g(x, y) < level {
        let d = dist(Double(x) + 0.5, Double(y) + 0.5)
        if d > band { o += 1; if b.g(x, y) < 128 { o50 += 1 } } else if d <= 0 { i += 1 }
    } }
    return (o, o50, i)
}
func boxDist(_ deg: Double) -> (Double, Double) -> Double {
    { x, y in let (u, v) = local(x, y, deg: deg); return max(abs(u), abs(v)) - 30 }
}
func rrDist(_ deg: Double, r: Double) -> (Double, Double) -> Double {
    { x, y in
        let (u, v) = local(x, y, deg: deg)
        let qx = abs(u) - (30 - r), qy = abs(v) - (30 - r)
        return (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot() + min(max(qx, qy), 0) - r
    }
}
func ellDist(_ deg: Double) -> (Double, Double) -> Double {
    { x, y in let (u, v) = local(x, y, deg: deg); return (((u / 30) * (u / 30) + (v / 20) * (v / 20)).squareRoot() - 1) * 20 }
}
func bboxOfRotated(_ deg: Double) -> Double { 60 * (abs(cos(deg * .pi / 180)) + abs(sin(deg * .pi / 180))) / 2 }

// NC0: T7 / T7b again (controls).
do {
    let bar = Color.pr.frame(width: 100, height: 20)
    let t7 = render(bar.frame(width: 60, height: 20).clipped().rotationEffect(.degrees(90)))
    let t7b = render(bar.rotationEffect(.degrees(90)).clipped())
    func box(_ b: Bmp) -> String {
        var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, n = 0
        for y in 0..<b.h { for x in 0..<b.w where b.g(x, y) < 255 { x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y); n += 1 } }
        return n == 0 ? "none" : "x\(x0 - 60) y\(y0 - 50) w\(x1 - x0 + 1) h\(y1 - y0 + 1) n\(n)"
    }
    print("NC0 T7 clipped() then rotationEffect(90): \(box(t7)) | T7b rotationEffect(90) then clipped(): \(box(t7b))")
}
let sq100 = Color.pr.frame(width: 100, height: 100).rotationEffect(.degrees(30))
// What the screen bounding box of the clip would paint (MetalUI today): the
// 60-degree-rotated 100 square clipped to the clip's bounding box.
var boxModel = 0
do {
    let hb = bboxOfRotated(30)
    for y in 0..<base.h { for x in 0..<base.w {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        let (u, v) = local(px, py, deg: 60)
        let inBox = abs(px - cxy.x) <= hb && abs(py - cxy.y) <= hb
        if inBox && max(abs(u), abs(v)) <= 50 && boxDist(30)(px, py) > 1 { boxModel += 1 }
    } }
}
do {
    let nc1 = render(sq100.frame(width: 60, height: 60).clipped().rotationEffect(.degrees(30)))
    let o = outside(nc1, boxDist(30))
    print("NC1 clipped() between two 30 rotations: ink outside the exact rotated square (>1px) \(o.out) (>=50% \(o.out50)); inside \(o.inside) of 3600; box model would add \(boxModel) outside pixels")
}
do {
    let nc2 = render(sq100.frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 12)).rotationEffect(.degrees(30)))
    let o = outside(nc2, rrDist(30, r: 12))
    let sqOut = outside(nc2, boxDist(30)).out
    // Pixels in the corner cut: inside the square, more than 1 px outside the rounded rect, ink present.
    var cut = 0
    for y in 0..<nc2.h { for x in 0..<nc2.w where nc2.g(x, y) < 128 { if rrDist(30, r: 12)(Double(x) + 0.5, Double(y) + 0.5) > 1 { cut += 1 } } }
    print("NC2 clipShape(RoundedRectangle(12)): ink outside the exact rounded square (>1px) \(o.out) (>=50% \(o.out50)); corner-cut ink >=50% \(cut); inside \(o.inside) (analytic \(f1(3600 - (4 - Double.pi) * 144))); outside the plain square \(sqOut)")
}
do {
    let rect = render(Color.pr.frame(width: 60, height: 60).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0), perspective: 1))
    let (quad, rms) = fitQuad(rect)
    let nc3 = render(sq100.frame(width: 60, height: 60).clipped().rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0), perspective: 1))
    var o = 0, o50 = 0, i = 0, rectOut = 0
    for y in 0..<nc3.h { for x in 0..<nc3.w {
        let d = quadOutside(quad, Double(x) + 0.5, Double(y) + 0.5)
        if nc3.g(x, y) < 255 { if d > 1 { o += 1; if nc3.g(x, y) < 128 { o50 += 1 } } else if d <= 0 { i += 1 } }
        if rect.g(x, y) < 255 && d > 1 { rectOut += 1 }
    } }
    print("NC3 clipped() then rotation3DEffect(40, y, perspective 1): ink outside the projected quad (>1px) \(o) (>=50% \(o50)); inside \(i); control, the solid rect's own ink outside its fitted quad \(rectOut) (fit rms \(f2(rms)))")
}
do {
    let nc4 = render(sq100.frame(width: 60, height: 40).clipShape(Ellipse()).frame(width: 60, height: 60).rotationEffect(.degrees(30)))
    let o = outside(nc4, ellDist(30))
    print("NC4 clipShape(Ellipse) 60x40 between two 30 rotations: ink outside the exact ellipse (>1px) \(o.out) (>=50% \(o.out50)); inside \(o.inside) (analytic \(f1(Double.pi * 30 * 20)))")
}
do {
    let nc5 = render(sq100.scaleEffect(2).frame(width: 60, height: 60).clipped().rotationEffect(.degrees(30)))
    let o = outside(nc5, boxDist(30))
    print("NC5 clip outside a flattening scaleEffect(2) of the inner rotation: ink outside the exact rotated square (>1px) \(o.out) (>=50% \(o.out50)); inside \(o.inside) of 3600")
}
}
