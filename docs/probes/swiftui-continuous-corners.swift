// SwiftUI probe: continuous rounded corners (R4-5 PR F, divergence 90; ruling prefix CC-, record 226).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-continuous-corners.swift -o /tmp/cc-probe
//   /tmp/cc-probe 2>&1 | grep -v 'Connection\]'
//
// No window is opened: every pixel arm renders through `ImageRenderer`; the curve arms read
// SwiftUI's own Beziers through `Path.forEach`, so the corner is READ, not fitted from pixels.
//
// INSTRUMENT: `bytes`/`differing`/`ink` are copied from docs/probes/swiftui-clip-mask.swift.
//
// QUESTIONS. CC0 is the separating arm (FR-M): a RoundedRectangle(20, .continuous) at 100x60 against
// (a) .circular (expected ~196 px apart), (b) a Path built from the model below (expected 0),
// (c) superellipse polylines n=4, n=5; exactly one reference must read 0 and channel gap <= 1.
// CC1..CC4 compare SwiftUI's element lists with the MODEL, element by element, on a grid of
// RoundedRectangle, Capsule, UnevenRoundedRectangle and elliptical cornerSize, plus a random sweep.
// CC5 asks whether strokeBorder is the inset band; CC6 whether a continuous clip equals the fill;
// CC7 whether a shadow follows the curve; CC8 hit testing; CC9 the start point; CC10 scale.
//
// THE MODEL (a corner of radius r with room x/y along the two sides it touches; local axes u along
// the horizontal side inward, v along the vertical side inward, in units of r):
//   T0 = 1.528664947   c1(t) = 0.96 + (1.088490009 - 0.96) (t-1)/(T0-1)   c2(t) = 0.82 + (0.868407011 - 0.82) (t-1)/(T0-1)
//   t_u = min(roomX / r, T0)   t_v = min(roomY / r, T0)
//   cubic A: (t_u,0) (c1(t_u),0) (c2(t_u),0) (0.631493986, 0.074911401)
//   cubic B: (0.631493986,0.074911401) (0.372824013,0.169060007) (0.169060007,0.372824013) (0.074911401,0.631493986)
//   cubic C: (0.074911401,0.631493986) (0,c2(t_v)) (0,c1(t_v)) (0,t_v)
// An elliptical corner scales u by rx and v by ry. For UnevenRoundedRectangle:
//   r_i' = min(r_i, max(side/2, side - r_j)) over both sides i touches; room_i = side * r_i'/(r_i'+r_j').
//
// RECORDED 2026-11-07 by R4-5 PR F run 1, macOS 27.2, compiled form, run twice, stdout identical, screen not touched:
//
//   --- CC0: the separating arm (exact-area metric: sum of |coverage difference| in pt2, 100x60 canvas)
//   CC0 scale 1: continuous area 5643.153 | |diff| pt2 vs default 0.000, vs MODEL(flattened) 5.302 gap 17, vs MODEL(cubic path) 11.310, vs circular 16.118 (differing px 196), vs superellipse n4 239.890 n5 276.973
//   CC0 scale 2: continuous area 5641.149 | |diff| pt2 vs default 0.000, vs MODEL(flattened) 3.722 gap 35, vs MODEL(cubic path) 7.087, vs circular 17.598 (differing px 428), vs superellipse n4 241.922 n5 278.878
//   CC0 scale 4: continuous area 5640.404 | |diff| pt2 vs default 0.000, vs MODEL(flattened) 3.016 gap 47, vs MODEL(cubic path) 4.286, vs circular 18.088 (differing px 964), vs superellipse n4 242.716 n5 279.578
//   CC0 scale 8: continuous area 5640.212 | |diff| pt2 vs default 0.000, vs MODEL(flattened) 2.719 gap 81, vs MODEL(cubic path) 3.332, vs circular 18.165 (differing px 2532), vs superellipse n4 242.863 n5 279.838
//   CC0 noise floor, circular fill vs its own flattened elements, scale 1: |diff| 2.753 pt2 gap 13
//   CC0 noise floor, circular fill vs its own flattened elements, scale 8: |diff| 0.654 pt2 gap 32
//   CC0 INSTRUMENT: SwiftUI's own path(in:) filled vs the shape fill 0 px; the same path's ELEMENTS re-filled as a plain Path vs it 240 px (gap 36): the shape fill is not rasterised like a generic cubic path at 1x, so the pixel arm uses the exact-area metric and a flattened model
//   --- CC1: RoundedRectangle element lists against the model
//   CC1 100x60 at (0.0,0.0) r5.0: structure same max err 2.22e-09
//   CC1 100x60 at (0.0,0.0) r10.0: structure same max err 4.44e-09
//   CC1 100x60 at (0.0,0.0) r19.62: structure same max err 8.71e-09
//   CC1 100x60 at (0.0,0.0) r20.0: structure same max err 8.32e-07
//   CC1 100x60 at (0.0,0.0) r25.0: structure same max err 1.63e-06
//   CC1 100x60 at (0.0,0.0) r30.0: structure same max err 6.44e-07
//   CC1 100x60 at (0.0,0.0) r50.0: structure same max err 6.44e-07
//   CC1 100x100 at (0.0,0.0) r20.0: structure same max err 8.88e-09
//   CC1 100x100 at (0.0,0.0) r32.7: structure same max err 1.45e-08
//   CC1 100x100 at (0.0,0.0) r40.0: structure same max err 2.45e-06
//   CC1 100x100 at (0.0,0.0) r50.0: structure same max err 1.07e-06
//   CC1 200x60 at (0.0,0.0) r25.0: structure same max err 1.63e-06
//   CC1 200x60 at (10.0,5.0) r25.0: structure same max err 1.63e-06
//   CC1 100x60 at (0.0,0.0) r0.0: structure DIFFERENT (5 vs 18) max err -
//   CC1 100x60 at (0.0,0.0) r1.0: structure same max err 4.44e-10
//   CC1 1000x600 at (0.0,0.0) r256.0: structure same max err 7.51e-06
//   CC1 100x60 at (0.0,0.0) r22.0: structure same max err 1.23e-06
//   CC1 worst error / r over the RoundedRectangle grid 6.529e-08
//   CC1 dump (M, L and the first corner, BR) 100x60 r5: M(100
//   CC1 dump (M, L and the first corner, BR) 100x60 r20: M(100
//   CC1 dump (M, L and the first corner, BR) 100x60 r30: M(100
//   CC1 dump (M, L and the first corner, BR) 100x100 r40: M(100.000000,50.000000) L(100.000000,50.000000) C[100.000000,59.169540|100.000000,66.284354|97.003544,74.740241] C[93.237600,85.087039|85.087039,93.237600|74.740241,97.003544] C[66.284354,100.000000|59.169540,100.000000|50.000000,100.000000]
//   --- CC2: Capsule
//   CC2 capsule 100x60 vs model r=min/2: 6.44e-07
//   CC2 capsule 60x100 vs model r=min/2: 6.44e-07
//   CC2 capsule 200x40 vs model r=min/2: 4.29e-07
//   CC2 capsule 60x60 vs model r=min/2: 6.44e-07
//   CC2 capsule 30x30 vs model r=min/2: 3.22e-07
//   CC2 Capsule vs RR(50,.continuous) 0 | Capsule(.circular) vs RR(30,.circular) 0 | Capsule(.continuous) vs circular 230 | 60x60 capsule vs Circle 0
//   --- CC3: UnevenRoundedRectangle
//   CC3 tl40.0 tr0.0 br0.0 bl0.0: max err 1.66e-06
//   CC3 tl20.0 tr10.0 br0.0 bl0.0: max err 8.88e-09
//   CC3 tl25.0 tr0.0 br0.0 bl25.0: max err 1.63e-06
//   CC3 tl25.0 tr25.0 br0.0 bl0.0: max err 1.11e-08
//   CC3 tl40.0 tr40.0 br0.0 bl0.0: max err 2.45e-06
//   CC3 tl40.0 tr0.0 br0.0 bl40.0: max err 6.44e-07
//   CC3 tl30.0 tr0.0 br0.0 bl30.0: max err 6.44e-07
//   CC3 tl60.0 tr0.0 br0.0 bl0.0: max err 1.29e-06
//   CC3 tl50.0 tr30.0 br0.0 bl0.0: max err 3.26e-06
//   CC3 tl70.0 tr20.0 br0.0 bl0.0: max err 3.68e-06
//   CC3 tl60.0 tr40.0 br0.0 bl0.0: max err 1.66e-06
//   CC3 tl45.0 tr45.0 br0.0 bl0.0: max err 2.38e-06
//   CC3 tl80.0 tr10.0 br0.0 bl0.0: max err 2.84e-06
//   CC3 tl30.0 tr10.0 br0.0 bl0.0: max err 1.33e-08
//   CC3 tl50.0 tr0.0 br0.0 bl10.0: max err 1.07e-06
//   CC3 tl50.0 tr0.0 br0.0 bl20.0: max err 8.58e-07
//   CC3 tl40.0 tr0.0 br0.0 bl20.0: max err 8.58e-07
//   CC3 tl35.0 tr0.0 br0.0 bl25.0: max err 7.51e-07
//   CC3 tl55.0 tr0.0 br0.0 bl5.0: max err 1.18e-06
//   CC3 tl20.0 tr20.0 br20.0 bl20.0: max err 8.32e-07
//   CC3 tl10.0 tr40.0 br25.0 bl5.0: max err 7.51e-07
//   CC3 worst abs error over the named grid 3.681e-06
//   CC3order [0, 1, 2, 3] one pass fails 38/2000, two passes fail 38/2000
//   CC3order [0, 1, 3, 2] one pass fails 87/2000, two passes fail 87/2000
//   CC3order [0, 2, 1, 3] one pass fails 0/2000, two passes fail 0/2000
//   CC3order [0, 2, 3, 1] one pass fails 0/2000, two passes fail 0/2000
//   CC3order [0, 3, 1, 2] one pass fails 87/2000, two passes fail 87/2000
//   CC3order [0, 3, 2, 1] one pass fails 49/2000, two passes fail 49/2000
//   CC3order [1, 0, 2, 3] one pass fails 80/2000, two passes fail 80/2000
//   CC3order [1, 0, 3, 2] one pass fails 129/2000, two passes fail 129/2000
//   CC3order [1, 2, 0, 3] one pass fails 80/2000, two passes fail 80/2000
//   CC3order [1, 2, 3, 0] one pass fails 137/2000, two passes fail 137/2000
//   CC3order [1, 3, 0, 2] one pass fails 186/2000, two passes fail 186/2000
//   CC3order [1, 3, 2, 0] one pass fails 186/2000, two passes fail 186/2000
//   CC3order [2, 0, 1, 3] one pass fails 0/2000, two passes fail 0/2000
//   CC3order [2, 0, 3, 1] one pass fails 0/2000, two passes fail 0/2000
//   CC3order [2, 1, 0, 3] one pass fails 42/2000, two passes fail 42/2000
//   CC3order [2, 1, 3, 0] one pass fails 99/2000, two passes fail 99/2000
//   CC3order [2, 3, 0, 1] one pass fails 57/2000, two passes fail 57/2000
//   CC3order [2, 3, 1, 0] one pass fails 99/2000, two passes fail 99/2000
//   CC3order [3, 0, 1, 2] one pass fails 144/2000, two passes fail 144/2000
//   CC3order [3, 0, 2, 1] one pass fails 106/2000, two passes fail 106/2000
//   CC3order [3, 1, 0, 2] one pass fails 186/2000, two passes fail 186/2000
//   CC3order [3, 1, 2, 0] one pass fails 186/2000, two passes fail 186/2000
//   CC3order [3, 2, 0, 1] one pass fails 106/2000, two passes fail 106/2000
//   CC3order [3, 2, 1, 0] one pass fails 148/2000, two passes fail 148/2000
//   CC3c circular UnevenRoundedRectangle, 847 random all-positive radii: horizontal-then-vertical rule mismatches 0, simultaneous (the shipped fitted(width:height:)) mismatches 39
//   --- CC4: elliptical cornerSize
//   CC4 cornerSize 30.0x10.0: max err 1.33e-08 | SwiftUI TL rx,ry 30.000, 10.000
//   CC4 cornerSize 10.0x30.0: max err 6.44e-07 | SwiftUI TL rx,ry 10.000, 30.000
//   CC4 cornerSize 60.0x20.0: max err 1.07e-06 | SwiftUI TL rx,ry 50.000, 16.667
//   CC4 cornerSize 20.0x50.0: max err 6.44e-07 | SwiftUI TL rx,ry 12.000, 30.000
//   CC4 cornerSize 40.0x40.0: max err 6.44e-07 | SwiftUI TL rx,ry 30.000, 30.000
//   --- CC5: strokeBorder is the inset band
//   CC5 r20.0 w6.0: strokeBorder vs inset band 0 gap 0 | strokeBorder vs centred stroke 1944 | strokeBorder ink 1716 fill ink 5724
//   CC5 r20.0 w6.0: stroke vs centred path stroke 0
//   CC5 r40.0 w20.0: strokeBorder vs inset band 0 gap 0 | strokeBorder vs centred stroke 5024 | strokeBorder ink 4236 fill ink 5316
//   CC5 r40.0 w20.0: stroke vs centred path stroke 0
//   CC5 r20.0 w2.0: strokeBorder vs inset band 0 gap 0 | strokeBorder vs centred stroke 868 | strokeBorder ink 688 fill ink 5724
//   CC5 r20.0 w2.0: stroke vs centred path stroke 0
//   CC5 r30.0 w24.0: strokeBorder vs inset band 0 gap 0 | strokeBorder vs centred stroke 5832 | strokeBorder ink 4752 fill ink 5316
//   CC5 r30.0 w24.0: stroke vs centred path stroke 0
//   CC5b strokeBorder(10) on RR(4): corner pixel (0,0) (255, 0, 0) | vs inset Rectangle stroke miter differing 0 | outer corner (0,0) of RR(4) fill (255, 255, 255)
//   --- CC6: a continuous clip equals the fill
//   CC6 clipShape(.continuous) vs fill 0 gap 0 | cornerRadius(20) vs fill 0 | clip circular vs fill 196
//   --- CC7: shadow
//   CC7 shadow continuous vs circular differing 1384 gap 66
//   --- CC8: hit testing / contains
//   CC8 r100 contains (100,0.5) continuous true circular true | diagonal (29.22,29.22) continuous true circular false | (14.6,14.6) continuous false circular false | model diagonal point is (29.1507, 29.1507) vs circular (29.2893, 29.2893)
//   --- CC9: the start point
//   CC9 r5.0 first move (100.0, 30.0)
//   CC9 r20.0 first move (100.0, 30.0)
//   CC9 r0.0 first move (0.0, 0.0)
//   CC9 r30.0 first move (100.0, 30.0)
//   CC9 trim 0..0.25 ink 282 (path length of the model: see CC10)
//   --- CC10: scale invariance is read in CC0 (scales 1, 2, 4, 8 above): the |diff| against the MODEL falls with scale, against circular it does not
//
// READING. The corner is READ, not fitted: SwiftUI's own Beziers (Path.forEach) agree with the MODEL to 7.5e-6 absolute
// (6.5e-8 of r) over the RoundedRectangle grid, the Capsules, the UnevenRoundedRectangle grid, 2000 random uneven radii
// (rule: horizontal sides first, then vertical, pairClamp, rooms by radius ratio: 0 failures; the other 23 edge orders fail
// 38..186; CC3c: the CIRCULAR UnevenRoundedRectangle fits the same way, 0 of 847, and MetalUI's shipped simultaneous fit missed
// 39) and the elliptical cornerSize (the pair scales together to fit half the sides, keeping its ratio).
// THE RASTERISER caveat (CC0 INSTRUMENT): the shape fill of a RoundedRectangle is NOT rasterised like the same cubics as a
// generic Path at 1x (240 px, gap 36), so pixel equality with a Path is unreachable; the exact-area metric reads the
// MODEL at 2.72 pt2 (scale 8; noise floor of the same comparison for the circular corner 0.65 pt2), circular 18.2, superellipse
// n4 243, n5 280: the model separates, residual about 0.02 pt mean offset at r 20 (1e-3 r). The max pixel gap at 1x vs the
// flattened model is 17/255. CC5: strokeBorder(w) is exactly the inset band (0 px, four (r, w) pairs) and CC5b: an inset
// radius <= 0 draws a square OUTER corner. CC6: a continuous clip equals the fill (0 px); cornerRadius(20) equals it; the
// circular clip is 196 px away. CC7/CC8: shadow and contains follow the curve. CC9: the start is the right edge's midpoint
// between the TR and BR radii; every corner emits its line and three cubics even at radius 0 (zero radii everywhere: a plain rect).
//
import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

typealias Bitmap = (bytes: [UInt8], w: Int, h: Int)
let canvasW = 240, canvasH = 200, ox = 60, oy = 50

func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (b, w, h)
}
@MainActor func render(_ v: some View, scale: CGFloat = 1) -> Bitmap {
    let c = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().padding(.leading, CGFloat(ox)).padding(.top, CGFloat(oy))
    }.frame(width: CGFloat(canvasW), height: CGFloat(canvasH), alignment: .topLeading)
    let r = ImageRenderer(content: c)
    r.scale = scale
    return bytes(of: r.cgImage!)
}
func rgb(_ b: Bitmap, _ x: Int, _ y: Int, scale: Int = 1) -> (Int, Int, Int) {
    let X = x * scale + ox * scale, Y = y * scale + oy * scale
    guard X >= 0, Y >= 0, X < b.w, Y < b.h else { return (-1, -1, -1) }
    let i = (Y * b.w + X) * 4
    return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2]))
}
func differing(_ a: Bitmap, _ b: Bitmap) -> Int {
    var n = 0
    for i in stride(from: 0, to: min(a.bytes.count, b.bytes.count), by: 4)
    where a.bytes[i] != b.bytes[i] || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}
func gap(_ a: Bitmap, _ b: Bitmap) -> Int {
    var m = 0
    for i in 0..<min(a.bytes.count, b.bytes.count) { m = max(m, abs(Int(a.bytes[i]) - Int(b.bytes[i]))) }
    return m
}
func ink(_ b: Bitmap) -> Int {
    var n = 0
    for i in stride(from: 0, to: b.bytes.count, by: 4) where !(b.bytes[i] == 255 && b.bytes[i + 1] == 255 && b.bytes[i + 2] == 255) { n += 1 }
    return n
}

// MARK: the model

enum El { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close }
let k0 = 0.631493986, k1 = 0.074911401, m1 = 0.372824013, m2 = 0.169060007
let T0 = 1.528664947
func c1(_ t: Double) -> Double { 0.96 + (1.088490009 - 0.96) * (t - 1) / (T0 - 1) }
func c2(_ t: Double) -> Double { 0.82 + (0.868407011 - 0.82) * (t - 1) / (T0 - 1) }

struct Corner { var rx = 0.0, ry = 0.0, roomX = 0.0, roomY = 0.0 }
/// Canonical order (horizontal side first): three cubics of four points each, local coordinates.
func segments(_ c: Corner) -> [[CGPoint]] {
    guard c.rx > 0, c.ry > 0 else { return Array(repeating: Array(repeating: .zero, count: 4), count: 3) }
    let tu = min(c.roomX / c.rx, T0), tv = min(c.roomY / c.ry, T0)
    func P(_ u: Double, _ v: Double) -> CGPoint { CGPoint(x: u * c.rx, y: v * c.ry) }
    return [[P(tu, 0), P(c1(tu), 0), P(c2(tu), 0), P(k0, k1)],
            [P(k0, k1), P(m1, m2), P(m2, m1), P(k1, k0)],
            [P(k1, k0), P(0, c2(tv)), P(0, c1(tv)), P(0, tv)]]
}
/// corners order: tl, tr, br, bl. Clockwise on screen from the right edge going down: BR, BL, TL, TR.
func elements(_ r: CGRect, tl: Corner, tr: Corner, br: Corner, bl: Corner) -> [El] {
    var out: [El] = [.move(CGPoint(x: r.maxX, y: r.minY + (tr.ry + r.height - br.ry) / 2))]
    func place(_ c: Corner, _ ox: Double, _ oy: Double, _ sx: Double, _ sy: Double, vertFirst: Bool) {
        var segs = segments(c)
        if vertFirst { segs = segs.reversed().map { $0.reversed() } }
        func g(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + sx * p.x, y: oy + sy * p.y) }
        out.append(.line(g(segs[0][0])))
        for s in segs { out.append(.curve(g(s[3]), g(s[1]), g(s[2]))) }
    }
    place(br, r.maxX, r.maxY, -1, -1, vertFirst: true)
    place(bl, r.minX, r.maxY, 1, -1, vertFirst: false)
    place(tl, r.minX, r.minY, 1, 1, vertFirst: true)
    place(tr, r.maxX, r.minY, -1, 1, vertFirst: false)
    out.append(.close)
    return out
}
func path(_ els: [El]) -> Path {
    var p = Path()
    for e in els {
        switch e {
        case .move(let a): p.move(to: a)
        case .line(let a): p.addLine(to: a)
        case .curve(let a, let b, let c): p.addCurve(to: a, control1: b, control2: c)
        case .close: p.closeSubpath()
        }
    }
    return p
}
func read(_ p: Path) -> [El] {
    var out: [El] = []
    p.forEach { e in
        switch e {
        case .move(let a): out.append(.move(a))
        case .line(let a): out.append(.line(a))
        case .curve(let a, let b, let c): out.append(.curve(a, b, c))
        case .quadCurve(let a, _): out.append(.line(a))
        case .closeSubpath: out.append(.close)
        }
    }
    return out
}
/// Max abs coordinate difference between two element lists, or nil if the structure differs.
func maxErr(_ a: [El], _ b: [El]) -> Double? {
    guard a.count == b.count else { return nil }
    var m = 0.0
    func d(_ p: CGPoint, _ q: CGPoint) { m = max(m, abs(p.x - q.x), abs(p.y - q.y)) }
    for (x, y) in zip(a, b) {
        switch (x, y) {
        case (.move(let p), .move(let q)), (.line(let p), .line(let q)): d(p, q)
        case (.curve(let p1, let p2, let p3), .curve(let q1, let q2, let q3)): d(p1, q1); d(p2, q2); d(p3, q3)
        case (.close, .close): break
        default: return nil
        }
    }
    return m
}
func fmt(_ els: some Sequence<El>) -> String {
    els.map { e -> String in
        switch e {
        case .move(let a): return String(format: "M(%.6f,%.6f)", a.x, a.y)
        case .line(let a): return String(format: "L(%.6f,%.6f)", a.x, a.y)
        case .curve(let a, let b, let c): return String(format: "C[%.6f,%.6f|%.6f,%.6f|%.6f,%.6f]", b.x, b.y, c.x, c.y, a.x, a.y)
        case .close: return "Z"
        }
    }.joined(separator: " ")
}

/// The four effective radii (tl, tr, br, bl) of an element list from the chord of each middle cubic.
func radii(_ els: [El]) -> [Double] {
    // layout: M, then BR: L C C C, BL: L C C C, TL: L C C C, TR: L C C C, Z; middle cubics at 3, 7, 11, 15.
    var start: [CGPoint] = [], out: [Double] = []
    var cur = CGPoint.zero
    for e in els { switch e {
        case .move(let a), .line(let a): cur = a; start.append(cur)
        case .curve(let a, _, _): start.append(cur); cur = a
        case .close: break } }
    var idx: [Int] = []; var k = 0
    for (i, e) in els.enumerated() { if case .curve = e { k += 1; if k % 3 == 2 { idx.append(i) } } }
    for i in idx { if case .curve(let a, _, _) = els[i] { let s0 = start[i]; out.append(hypot(a.x - s0.x, a.y - s0.y) / ((k0 - k1) * 2.0.squareRoot())) } }
    if out.count < 4 { return [0, 0, 0, 0] }
    return [out[2], out[3], out[0], out[1]]
}

/// The TL corner's (rx, ry) from its middle cubic (element 11).
func tlEllipse(_ els: [El]) -> (Double, Double)? {
    guard els.count > 11, case .curve(let e, _, _) = els[11], case .curve(let prev, _, _) = els[10] else { return nil }
    return ((e.x - prev.x) / (k0 - k1), (prev.y - e.y) / (k0 - k1))
}

// MARK: model constructors

func uniform(_ r: CGRect, _ radius: Double) -> [El] {
    let rr = min(radius, r.width / 2, r.height / 2)
    let c = Corner(rx: rr, ry: rr, roomX: r.width / 2, roomY: r.height / 2)
    return elements(r, tl: c, tr: c, br: c, bl: c)
}
func elliptical(_ r: CGRect, _ rx: Double, _ ry: Double) -> [El] {
    let k = min(1, r.width / 2 / rx, r.height / 2 / ry)   // the pair scales together, keeping its ratio
    let c = Corner(rx: rx * k, ry: ry * k, roomX: r.width / 2, roomY: r.height / 2)
    return elements(r, tl: c, tr: c, br: c, bl: c)
}
/// The uneven rule: r_i' = min(r_i, max(side/2, side - r_j)) over both sides i touches
/// (r_j the ORIGINAL neighbour, `sequential == false`) or the already-clamped neighbour (`true`).
/// Edge-by-edge resolution: for each edge in `order` (0 top, 1 right, 2 bottom, 3 left) the two corners it joins
/// are resolved against the side by `pair`, using the radii as updated so far.
func pairClamp(_ a: Double, _ b: Double, _ side: Double) -> (Double, Double) {
    if a + b <= side { return (a, b) }
    if a >= side / 2 && b >= side / 2 { return (side / 2, side / 2) }
    return a > b ? (side - b, b) : (a, side - a)
}
func resolveByEdges(_ w: Double, _ h: Double, _ r: [Double], order: [Int]) -> [Double] {
    var r = r // tl, tr, br, bl
    for e in order {
        switch e {
        case 0: (r[0], r[1]) = pairClamp(r[0], r[1], w)
        case 1: (r[1], r[2]) = pairClamp(r[1], r[2], h)
        case 2: (r[3], r[2]) = pairClamp(r[3], r[2], w)
        default: (r[0], r[3]) = pairClamp(r[0], r[3], h)
        }
    }
    return r
}
func unevenResolved(_ r: CGRect, _ rr: [Double]) -> [El] {
    let w = r.width, h = r.height
    func share(_ a: Double, _ b: Double, _ side: Double) -> Double { a + b > 0 ? side * a / (a + b) : side }
    let (tl, tr, br, bl) = (rr[0], rr[1], rr[2], rr[3])
    return elements(r,
        tl: Corner(rx: tl, ry: tl, roomX: share(tl, tr, w), roomY: share(tl, bl, h)),
        tr: Corner(rx: tr, ry: tr, roomX: share(tr, tl, w), roomY: share(tr, br, h)),
        br: Corner(rx: br, ry: br, roomX: share(br, bl, w), roomY: share(br, tr, h)),
        bl: Corner(rx: bl, ry: bl, roomX: share(bl, br, w), roomY: share(bl, tl, h)))
}
/// The probe's reading of UnevenRoundedRectangle: horizontal sides first (top, then bottom), then the vertical sides
/// (right, then left); each side resolves its two corners by `pairClamp`; rooms are shared by radius ratio.
func uneven(_ r: CGRect, tl: Double, tr: Double, br: Double, bl: Double) -> [El] {
    unevenResolved(r, resolveByEdges(r.width, r.height, [tl, tr, br, bl], order: [0, 2, 1, 3]))
}

// MARK: reference shapes for CC0

func superellipse(_ r: CGRect, _ radius: Double, n: Double) -> Path {
    var p = Path()
    let rr = min(radius, r.width / 2, r.height / 2)
    var first = true
    func add(_ pt: CGPoint) { if first { p.move(to: pt); first = false } else { p.addLine(to: pt) } }
    // corners TL, TR, BR, BL, walking clockwise; quarter curve |u|^n + |v|^n = 1 scaled by rr.
    let cs: [(CGPoint, Double, Double, Double)] = [
        (CGPoint(x: r.minX + rr, y: r.minY + rr), -1, -1, 0), (CGPoint(x: r.maxX - rr, y: r.minY + rr), 1, -1, 0),
        (CGPoint(x: r.maxX - rr, y: r.maxY - rr), 1, 1, 0), (CGPoint(x: r.minX + rr, y: r.maxY - rr), -1, 1, 0)]
    for (c, sx, sy, _) in cs {
        for i in 0...48 {
            let a = Double(i) / 48 * .pi / 2
            // angle from the x-axis toward the y-axis in the corner's own frame, ordered so the walk is clockwise
            let ca = cos(a), sa = sin(a)
            let ux = pow(ca, 2 / n), uy = pow(sa, 2 / n)
            let pt: CGPoint
            if sx < 0 && sy < 0 { pt = CGPoint(x: c.x - rr * ux, y: c.y - rr * uy) }       // TL: left edge to top edge
            else if sx > 0 && sy < 0 { pt = CGPoint(x: c.x + rr * uy, y: c.y - rr * ux) }   // TR: top edge to right edge
            else if sx > 0 && sy > 0 { pt = CGPoint(x: c.x + rr * ux, y: c.y + rr * uy) }   // BR: right edge to bottom edge
            else { pt = CGPoint(x: c.x - rr * uy, y: c.y + rr * ux) }                        // BL: bottom edge to left edge
            add(pt)
        }
    }
    p.closeSubpath()
    return p
}

let R = CGRect(x: 0, y: 0, width: 100, height: 60)
let red = Color(.sRGB, red: 1, green: 0, blue: 0)

@MainActor func probe() {
    print("--- CC0: the separating arm (exact-area metric: sum of |coverage difference| in pt2, 100x60 canvas)")
    func flat(_ els: [El], _ n: Int) -> Path {
        var p = Path(); var cur = CGPoint.zero
        for e in els { switch e {
            case .move(let a): p.move(to: a); cur = a
            case .line(let a): p.addLine(to: a); cur = a
            case .curve(let a, let b, let c):
                for i in 1...n { let t = Double(i) / Double(n), u = 1 - t
                    p.addLine(to: CGPoint(x: u*u*u*cur.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*a.x, y: u*u*u*cur.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*a.y)) }
                cur = a
            case .close: p.closeSubpath() } }
        return p
    }
    func area(_ x: Bitmap, _ sc: Double) -> Double { var t = 0; for i in stride(from: 1, to: x.bytes.count, by: 4) { t += 255 - Int(x.bytes[i]) }; return Double(t) / 255 / (sc * sc) }
    func absDiff(_ a: Bitmap, _ b: Bitmap, _ sc: Double) -> Double { var t = 0; for i in stride(from: 1, to: min(a.bytes.count, b.bytes.count), by: 4) { t += abs(Int(a.bytes[i]) - Int(b.bytes[i])) }; return Double(t) / 255 / (sc * sc) }
    for sc in [1.0, 2, 4, 8] {
        let sub = render(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(red).frame(width: 100, height: 60), scale: sc)
        let dflt = render(RoundedRectangle(cornerRadius: 20).fill(red).frame(width: 100, height: 60), scale: sc)
        let circ = render(RoundedRectangle(cornerRadius: 20, style: .circular).fill(red).frame(width: 100, height: 60), scale: sc)
        let mdl = render(flat(uniform(R, 20), 400).fill(red).frame(width: 100, height: 60), scale: sc)
        let cub = render(path(uniform(R, 20)).fill(red).frame(width: 100, height: 60), scale: sc)
        let se4 = render(superellipse(R, 20, n: 4).fill(red).frame(width: 100, height: 60), scale: sc)
        let se5 = render(superellipse(R, 20, n: 5).fill(red).frame(width: 100, height: 60), scale: sc)
        print(String(format: "CC0 scale %.0f: continuous area %.3f | |diff| pt2 vs default %.3f, vs MODEL(flattened) %.3f gap %d, vs MODEL(cubic path) %.3f, vs circular %.3f (differing px %d), vs superellipse n4 %.3f n5 %.3f",
                     sc, area(sub, sc), absDiff(sub, dflt, sc), absDiff(sub, mdl, sc), gap(sub, mdl), absDiff(sub, cub, sc), absDiff(sub, circ, sc), differing(sub, circ), absDiff(sub, se4, sc), absDiff(sub, se5, sc)))
    }
    // Noise floor: the same comparison for the CIRCULAR corner, where the exact curve is known (SwiftUI's own arc elements, flattened).
    for sc in [1.0, 8] {
        let circ = render(RoundedRectangle(cornerRadius: 20, style: .circular).fill(red).frame(width: 100, height: 60), scale: sc)
        let circFlat = render(flat(read(RoundedRectangle(cornerRadius: 20, style: .circular).path(in: R)), 400).fill(red).frame(width: 100, height: 60), scale: sc)
        print(String(format: "CC0 noise floor, circular fill vs its own flattened elements, scale %.0f: |diff| %.3f pt2 gap %d", sc, absDiff(circ, circFlat, sc), gap(circ, circFlat)))
    }
    let swPath = render(RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: R).fill(red).frame(width: 100, height: 60))
    let subOne = render(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(red).frame(width: 100, height: 60))
    let rt = render(path(read(RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: R))).fill(red).frame(width: 100, height: 60))
    print("CC0 INSTRUMENT: SwiftUI's own path(in:) filled vs the shape fill \(differing(subOne, swPath)) px; the same path's ELEMENTS re-filled as a plain Path vs it \(differing(swPath, rt)) px (gap \(gap(swPath, rt))): the shape fill is not rasterised like a generic cubic path at 1x, so the pixel arm uses the exact-area metric and a flattened model")
    print("--- CC1: RoundedRectangle element lists against the model")
    var worstRR = 0.0
    for (w, h, r, ox, oy) in [(100.0, 60.0, 5.0, 0.0, 0.0), (100, 60, 10, 0, 0), (100, 60, 19.62, 0, 0), (100, 60, 20, 0, 0), (100, 60, 25, 0, 0),
                              (100, 60, 30, 0, 0), (100, 60, 50, 0, 0), (100, 100, 20, 0, 0), (100, 100, 32.7, 0, 0), (100, 100, 40, 0, 0),
                              (100, 100, 50, 0, 0), (200, 60, 25, 0, 0), (200, 60, 25, 10, 5), (100, 60, 0, 0, 0), (100, 60, 1, 0, 0), (1000, 600, 256, 0, 0), (100, 60, 22, 0, 0)] {
        let rect = CGRect(x: ox, y: oy, width: w, height: h)
        let sw = read(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect))
        let mine = uniform(rect, r)
        let e = maxErr(sw, mine)
        if let e { worstRR = max(worstRR, e / max(min(r, w / 2, h / 2), 1)) }
        print("CC1 \(Int(w))x\(Int(h)) at (\(ox),\(oy)) r\(r): structure \(e != nil ? "same" : "DIFFERENT (\(sw.count) vs \(mine.count))") max err \(e.map { String(format: "%.2e", $0) } ?? "-")")
    }
    print("CC1 worst error / r over the RoundedRectangle grid \(String(format: "%.3e", worstRR))")
    print("CC1 dump (M, L and the first corner, BR) 100x60 r5: \(fmt(read(RoundedRectangle(cornerRadius: 5, style: .continuous).path(in: R))).prefix(5))")
    print("CC1 dump (M, L and the first corner, BR) 100x60 r20: \(fmt(read(RoundedRectangle(cornerRadius: 20, style: .continuous).path(in: R))).prefix(5))")
    print("CC1 dump (M, L and the first corner, BR) 100x60 r30: \(fmt(read(RoundedRectangle(cornerRadius: 30, style: .continuous).path(in: R))).prefix(5))")
    print("CC1 dump (M, L and the first corner, BR) 100x100 r40: \(fmt(read(RoundedRectangle(cornerRadius: 40, style: .continuous).path(in: CGRect(x: 0, y: 0, width: 100, height: 100))).prefix(5)))")

    print("--- CC2: Capsule")
    for (w, h) in [(100.0, 60.0), (60, 100), (200, 40), (60, 60), (30, 30)] {
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        let sw = read(Capsule(style: .continuous).path(in: rect))
        let e = maxErr(sw, uniform(rect, min(w, h) / 2))
        print("CC2 capsule \(Int(w))x\(Int(h)) vs model r=min/2: \(e.map { String(format: "%.2e", $0) } ?? "STRUCTURE DIFFERS")")
    }
    let capV = render(Capsule(style: .continuous).fill(red).frame(width: 100, height: 60))
    let rr50 = render(RoundedRectangle(cornerRadius: 50, style: .continuous).fill(red).frame(width: 100, height: 60))
    let capC = render(Capsule(style: .circular).fill(red).frame(width: 100, height: 60))
    let rr30c = render(RoundedRectangle(cornerRadius: 30, style: .circular).fill(red).frame(width: 100, height: 60))
    let circle = render(Circle().fill(red).frame(width: 60, height: 60))
    let cap60 = render(Capsule(style: .continuous).fill(red).frame(width: 60, height: 60))
    print("CC2 Capsule vs RR(50,.continuous) \(differing(capV, rr50)) | Capsule(.circular) vs RR(30,.circular) \(differing(capC, rr30c)) | Capsule(.continuous) vs circular \(differing(capV, capC)) | 60x60 capsule vs Circle \(differing(cap60, circle))")

    print("--- CC3: UnevenRoundedRectangle")
    func U(_ tl: Double, _ tr: Double, _ br: Double, _ bl: Double, _ rect: CGRect) -> [El] {
        read(UnevenRoundedRectangle(cornerRadii: .init(topLeading: tl, bottomLeading: bl, bottomTrailing: br, topTrailing: tr), style: .continuous).path(in: rect))
    }
    var worstU = 0.0
    for (tl, tr, br, bl) in [(40.0, 0.0, 0.0, 0.0), (20, 10, 0, 0), (25, 0, 0, 25), (25, 25, 0, 0), (40, 40, 0, 0), (40, 0, 0, 40), (30, 0, 0, 30), (60, 0, 0, 0),
                             (50, 30, 0, 0), (70, 20, 0, 0), (60, 40, 0, 0), (45, 45, 0, 0), (80, 10, 0, 0), (30, 10, 0, 0), (50, 0, 0, 10), (50, 0, 0, 20), (40, 0, 0, 20),
                             (35, 0, 0, 25), (55, 0, 0, 5), (20, 20, 20, 20), (10, 40, 25, 5)] {
        let sw = U(tl, tr, br, bl, R)
        let m = uneven(R, tl: tl, tr: tr, br: br, bl: bl)
        let e = maxErr(sw, m)
        if let e { worstU = max(worstU, e) }
        print("CC3 tl\(tl) tr\(tr) br\(br) bl\(bl): \(e.map { String(format: "max err %.2e", $0) } ?? "STRUCTURE DIFFERS")")
    }
    print("CC3 worst abs error over the named grid \(String(format: "%.3e", worstU))")
    // edge-order search
    func perms(_ a: [Int]) -> [[Int]] { a.count <= 1 ? [a] : a.flatMap { x in perms(a.filter { $0 != x }).map { [x] + $0 } } }
    var seed2: UInt64 = 777
    func rnd2() -> Double { seed2 = seed2 &* 6364136223846793005 &+ 1442695040888963407; return Double(seed2 >> 33) / Double(1 << 31) }
    var cases: [(CGRect, [Double], [El])] = []
    for _ in 0..<2000 {
        let w = 40 + rnd2() * 160, h = 40 + rnd2() * 160
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        func pick() -> Double { rnd2() < 0.2 ? 0 : rnd2() * 120 }
        var rr = [pick(), pick(), pick(), pick()]
        if rr.allSatisfy({ $0 == 0 }) { rr[0] = 7 }
        cases.append((rect, rr, U(rr[0], rr[1], rr[2], rr[3], rect)))
    }
    for order in perms([0, 1, 2, 3]) {
        var bad = 0
        for (rect, rr, sw) in cases { let e = maxErr(sw, unevenResolved(rect, resolveByEdges(rect.width, rect.height, rr, order: order))) ?? 1e9; if e > 1e-3 { bad += 1 } }
        var bad2 = 0
        for (rect, rr, sw) in cases { let e = maxErr(sw, unevenResolved(rect, resolveByEdges(rect.width, rect.height, rr, order: order + order))) ?? 1e9; if e > 1e-3 { bad2 += 1 } }
        if order == [0, 2, 1, 3] { for (rect, rr, sw) in cases { let e = maxErr(sw, unevenResolved(rect, resolveByEdges(rect.width, rect.height, rr, order: order))) ?? 1e9; if e > 1e-3 { print(String(format: "CC3orderfail %.2fx%.2f in %@ | SwiftUI %@ | model %@", rect.width, rect.height, rr.map { String(format: "%.2f", $0) }.joined(separator: " "), radii(sw).map { String(format: "%.2f", $0) }.joined(separator: " "), resolveByEdges(rect.width, rect.height, rr, order: order).map { String(format: "%.2f", $0) }.joined(separator: " "))) } } }
        print("CC3order \(order) one pass fails \(bad)/\(cases.count), two passes fail \(bad2)/\(cases.count)")
    }

    // CC3c: does the CIRCULAR UnevenRoundedRectangle fit the same way? Its arcs are one cubic per corner (chord = r sqrt 2).
    func circRadii(_ els: [El]) -> [Double]? {
        var cur = CGPoint.zero, out: [Double] = []
        for e in els { switch e {
            case .move(let a), .line(let a): cur = a
            case .curve(let a, _, _): out.append(hypot(a.x - cur.x, a.y - cur.y) / 2.0.squareRoot()); cur = a
            case .close: break } }
        return out.count == 4 ? [out[2], out[3], out[0], out[1]] : nil
    }
    var seqMismatch = 0, simMismatch = 0, usable = 0
    for (rect, rr, _) in cases {
        let sw = read(UnevenRoundedRectangle(cornerRadii: .init(topLeading: rr[0], bottomLeading: rr[3], bottomTrailing: rr[2], topTrailing: rr[1]), style: .circular).path(in: rect))
        guard let got = circRadii(sw), rr.allSatisfy({ $0 > 0 }) else { continue }
        usable += 1
        func fit(_ a: Double, _ b: Double, _ side: Double) -> (Double, Double) { pairClamp(a, b, side) }
        let seq = resolveByEdges(rect.width, rect.height, rr, order: [0, 2, 1, 3])
        let top = fit(rr[0], rr[1], rect.width), bottom = fit(rr[3], rr[2], rect.width), left = fit(rr[0], rr[3], rect.height), right = fit(rr[1], rr[2], rect.height)
        let sim = [min(top.0, left.0), min(top.1, right.0), min(bottom.1, right.1), min(bottom.0, left.1)]
        if zip(got, seq).contains(where: { abs($0 - $1) > 1e-3 }) { seqMismatch += 1 }
        if zip(got, sim).contains(where: { abs($0 - $1) > 1e-3 }) { simMismatch += 1 }
    }
    print("CC3c circular UnevenRoundedRectangle, \(usable) random all-positive radii: horizontal-then-vertical rule mismatches \(seqMismatch), simultaneous (the shipped fitted(width:height:)) mismatches \(simMismatch)")

    print("--- CC4: elliptical cornerSize")
    for (rx, ry) in [(30.0, 10.0), (10, 30), (60, 20), (20, 50), (40, 40)] {
        let sw = read(Path(roundedRect: R, cornerSize: CGSize(width: rx, height: ry), style: .continuous))
        let e = maxErr(sw, elliptical(R, rx, ry))
        print("CC4 cornerSize \(rx)x\(ry): \(e.map { String(format: "max err %.2e", $0) } ?? "STRUCTURE DIFFERS") | SwiftUI TL rx,ry \(tlEllipse(sw).map { String(format: "%.3f, %.3f", $0.0, $0.1) } ?? "-")")
    }

    print("--- CC5: strokeBorder is the inset band")
    for (r, w) in [(20.0, 6.0), (40, 20), (20, 2), (30, 24)] {
        let sb = render(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(red, lineWidth: w).frame(width: 100, height: 60))
        let inset = R.insetBy(dx: w / 2, dy: w / 2)
        let band = render(RoundedRectangle(cornerRadius: max(r - w / 2, 0), style: .continuous).path(in: inset).stroke(red, lineWidth: w).frame(width: 100, height: 60))
        let naive = render(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: R).stroke(red, lineWidth: w).frame(width: 100, height: 60))
        let outerOnly = render(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: R).fill(red).frame(width: 100, height: 60))
        print("CC5 r\(r) w\(w): strokeBorder vs inset band \(differing(sb, band)) gap \(gap(sb, band)) | strokeBorder vs centred stroke \(differing(sb, naive)) | strokeBorder ink \(ink(sb)) fill ink \(ink(outerOnly))")
        let strokeC = render(RoundedRectangle(cornerRadius: r, style: .continuous).stroke(red, lineWidth: w).frame(width: 100, height: 60))
        print("CC5 r\(r) w\(w): stroke vs centred path stroke \(differing(strokeC, naive))")
    }
    let sq = render(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(red, lineWidth: 10).frame(width: 100, height: 60))
    let sqRect = render(Rectangle().path(in: R.insetBy(dx: 5, dy: 5)).stroke(red, lineWidth: 10).frame(width: 100, height: 60))
    let sqRound = render(RoundedRectangle(cornerRadius: 4, style: .continuous).path(in: R).fill(red).frame(width: 100, height: 60))
    let a0 = rgb(sq, 0, 0)
    print("CC5b strokeBorder(10) on RR(4): corner pixel (0,0) \(a0) | vs inset Rectangle stroke miter differing \(differing(sq, sqRect)) | outer corner (0,0) of RR(4) fill \(rgb(sqRound, 0, 0))")

    print("--- CC6: a continuous clip equals the fill")
    let clipv = render(red.frame(width: 100, height: 60).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)))
    let cornerR = render(red.frame(width: 100, height: 60).cornerRadius(20))
    let fillv = render(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(red).frame(width: 100, height: 60))
    let clipc = render(red.frame(width: 100, height: 60).clipShape(RoundedRectangle(cornerRadius: 20, style: .circular)))
    print("CC6 clipShape(.continuous) vs fill \(differing(clipv, fillv)) gap \(gap(clipv, fillv)) | cornerRadius(20) vs fill \(differing(cornerR, fillv)) | clip circular vs fill \(differing(clipc, fillv))")

    print("--- CC7: shadow")
    let shC = render(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(red).shadow(color: .black, radius: 4, x: 0, y: 3).frame(width: 100, height: 60))
    let shR = render(RoundedRectangle(cornerRadius: 20, style: .circular).fill(red).shadow(color: .black, radius: 4, x: 0, y: 3).frame(width: 100, height: 60))
    print("CC7 shadow continuous vs circular differing \(differing(shC, shR)) gap \(gap(shC, shR))")

    print("--- CC8: hit testing / contains")
    let big = CGRect(x: 0, y: 0, width: 200, height: 200)
    let rr100 = RoundedRectangle(cornerRadius: 100, style: .continuous).path(in: big)
    let rr100c = RoundedRectangle(cornerRadius: 100, style: .circular).path(in: big)
    print("CC8 r100 contains (100,0.5) continuous \(rr100.contains(CGPoint(x: 100, y: 0.5))) circular \(rr100c.contains(CGPoint(x: 100, y: 0.5))) | diagonal (29.22,29.22) continuous \(rr100.contains(CGPoint(x: 29.22, y: 29.22))) circular \(rr100c.contains(CGPoint(x: 29.22, y: 29.22))) | (14.6,14.6) continuous \(rr100.contains(CGPoint(x: 14.6, y: 14.6))) circular \(rr100c.contains(CGPoint(x: 14.6, y: 14.6))) | model diagonal point is (29.1507, 29.1507) vs circular (29.2893, 29.2893)")

    print("--- CC9: the start point")
    for (r, rect) in [(5.0, R), (20, R), (0, R), (30, R)] {
        if case .move(let a)? = read(RoundedRectangle(cornerRadius: r, style: .continuous).path(in: rect)).first { print("CC9 r\(r) first move (\(a.x), \(a.y))") }
    }
    let trim = render(RoundedRectangle(cornerRadius: 20, style: .continuous).trim(from: 0, to: 0.25).stroke(red, lineWidth: 3).frame(width: 100, height: 60))
    print("CC9 trim 0..0.25 ink \(ink(trim)) (path length of the model: see CC10)")

    print("--- CC10: scale invariance is read in CC0 (scales 1, 2, 4, 8 above): the |diff| against the MODEL falls with scale, against circular it does not")
}

MainActor.assumeIsolated { probe() }
