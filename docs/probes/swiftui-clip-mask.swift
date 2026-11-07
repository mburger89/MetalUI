// SwiftUI probe: a shape clip as a masked group (R4-5 PR C, retires divergences 91
// and 92; ruling prefix CM-, docs/superpowers/2026-11-06-clip-mask-decisions.md,
// record 220).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-clip-mask.swift -o /tmp/cm-probe
//   /tmp/cm-probe 2>&1 | grep -v 'Connection\]'
//
// No window is opened: every arm renders through `ImageRenderer`.
//
// INSTRUMENT: INK, copied from docs/probes/swiftui-group-filter.swift.
//
// QUESTIONS. CM0 is the separating arm (FR-M): a red 100x60 clipped to an Ellipse
// either reads like an Ellipse().fill (model E) or like the bounding box (model B,
// MetalUI's fallback); exactly one reference must read 0 differing pixels. CM1 asks
// a path clip's winding, even-odd and non-antialiased forms. CM2/CM2b ask whether two
// crossing rounded clips intersect exactly. CM3..CM5 ask what a shadow, a rotation and
// a blur do to a clipped view. CM6 decides whether an opacity outside a clip (no
// compositingGroup) is per-leaf or composited. CM7 is the control.
//
// RECORDED 2026-11-06 by R4-5 PR C, macOS 27.2, compiled form, run twice, stdout identical, screen not touched:
//
//   --- CM0: the separating arm (E against B)
//   CM0 subject (2,2)=(255,255,255) (50,30)=(255,0,0) | E differing 0 | B differing 1436
//   CM0 edge alphas y30 subject: -1:0 0:254 1:255 2:255 3:255 4:255 | E: -1:0 0:254 1:255 2:255 3:255 4:255
//   CM0 max channel gap subject vs Ellipse().fill 0
//   --- CM1: a path clip (nonzero), even-odd, non-antialiased
//   CM1 triangle inside the box outside the triangle (5,5) (5,5)=(255,255,255) | inside (50,50) (50,50)=(255,0,0)
//   CM1b even-odd centre (40,40)=(255,255,255) ring (10,10)=(255,0,0) | nonzero centre (40,40)=(255,0,0)
//   CM1c non-antialiased ellipse edge alphas y30 -1:0 0:255 1:255 2:255 3:255 4:255 only 0/255: true
//   --- CM2: two crossing rounded clips
//   CM2 offset form (52,52) (52,52)=(255,255,255) (97,97) (97,97)=(255,255,255) (60,60) (60,60)=(255,0,0)
//   CM2b no effect between (outer square corner region) (2,2) (2,2)=(255,255,255) (97,97) (97,97)=(255,255,255)
//   CM2c inner touching outer corner: outer corner (127,127) (127,127)=(255,255,255) inner corner (30,30) (30,30)=(255,255,255) (100,100) (100,100)=(255,0,0)
//   --- CM3: shadow of an ellipse clip
//   CM3 box corner + offset (108,68) (108,68)=(255,255,255) | shadow-only (105,40) (105,40)=(0,0,0) centre (60,40)=(255,0,0)
//   --- CM4: rotation
//   CM4 ink x30 y-31 w40 h102 n3252 | (2,-48) (2,-48)=(255,255,255) centre (50,20) (50,20)=(255,0,0)
//   --- CM5: blur against clip order
//   CM5 blur then clip: row y30 -6:0 -5:0 -4:0 -3:0 -2:0 -1:0 0:137 1:155 2:172 3:187 4:200 5:212 6:223 | clip then blur: -6:33 -5:44 -4:56 -3:69 -2:84 -1:101 0:119 1:137 2:155 3:172 4:187 5:200 6:212
//   --- CM6: opacity outside a clip, no compositingGroup
//   CM6 overlap (45,45) (45,45)=(191,64,128) (per-leaf (191,64,128), composited (255,128,128))
//   --- CM7: control
//   CM7 circle ink x0 y0 w60 h60 n2920
//   CM7 capsule ink x0 y0 w100 h40 n3720
//
// READING. CM0 separates: model E differs 0, model B 1436; edge alpha gap 0/255. CM2/CM2b/CM2c read white at the
// square-box corners: crossing rounded clips intersect exactly, so 92 is real. CM6 reads per-leaf (191,64,128).
//
import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

extension Color {
    static let pr = Color(.sRGB, red: 1, green: 0, blue: 0)
    static let pb = Color(.sRGB, red: 0, green: 0, blue: 1)
}

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

@MainActor func render(_ v: some View, leading: CGFloat = 0) -> Bitmap {
    let c = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().padding(.leading, CGFloat(ox) + leading).padding(.top, CGFloat(oy))
    }.frame(width: CGFloat(canvasW), height: CGFloat(canvasH), alignment: .topLeading)
    let r = ImageRenderer(content: c)
    r.scale = 1
    return bytes(of: r.cgImage!)
}

func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Int, Int, Int) {
    let X = x + ox, Y = y + oy
    guard X >= 0, Y >= 0, X < b.w, Y < b.h else { return (-1, -1, -1) }
    let i = (Y * b.w + X) * 4
    return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2]))
}
func px(_ b: Bitmap, _ x: Int, _ y: Int) -> String {
    let (r, g, bl) = rgb(b, x, y)
    return "(\(x),\(y))=(\(r),\(g),\(bl))"
}
func ink(_ b: Bitmap) -> String {
    var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, n = 0
    for y in 0..<b.h { for x in 0..<b.w {
        let i = (y * b.w + x) * 4
        if !(b.bytes[i] == 255 && b.bytes[i + 1] == 255 && b.bytes[i + 2] == 255) {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y); n += 1
        }
    } }
    if n == 0 { return "none" }
    return "x\(x0 - ox) y\(y0 - oy) w\(x1 - x0 + 1) h\(y1 - y0 + 1) n\(n)"
}
/// Pixels whose RGB differs between `a` moved right by `shift` and `b`
/// (columns a cannot supply are skipped).
func differing(_ a: Bitmap, _ b: Bitmap, shift: Int = 0) -> Int {
    var n = 0
    for y in 0..<b.h { for x in shift..<b.w {
        let i = (y * b.w + x) * 4, j = (y * a.w + x - shift) * 4
        if a.bytes[j] != b.bytes[i] || a.bytes[j + 1] != b.bytes[i + 1] || a.bytes[j + 2] != b.bytes[i + 2] { n += 1 }
    } }
    return n
}
func row(_ b: Bitmap, y: Int, _ xs: StrideThrough<Int>) -> String {
    xs.map { "\($0):\(rgb(b, $0, y).1)" }.joined(separator: " ")
}


@MainActor func tri() -> Path {
    var p = Path(); p.move(to: CGPoint(x: 50, y: 0)); p.addLine(to: CGPoint(x: 100, y: 80)); p.addLine(to: CGPoint(x: 0, y: 80)); p.closeSubpath(); return p
}
@MainActor func twoRects() -> Path {
    var p = Path(); p.addRect(CGRect(x: 0, y: 0, width: 80, height: 80)); p.addRect(CGRect(x: 20, y: 20, width: 40, height: 40)); return p
}
func alphas(_ b: Bitmap, y: Int, _ xs: StrideThrough<Int>) -> String {
    xs.map { "\($0):\(255 - rgb(b, $0, y).1)" }.joined(separator: " ")
}

@MainActor func overlap() -> some View {
    ZStack(alignment: .topLeading) {
        Color.pb.frame(width: 60, height: 60).padding(.leading, 30).padding(.top, 30)
        Color.pr.frame(width: 60, height: 60)
    }
}

@MainActor func probe() {
    print("--- CM0: the separating arm (E against B)")
    let subject = render(Color.pr.frame(width: 100, height: 60).clipShape(Ellipse()))
    let refE = render(Ellipse().fill(Color.pr).frame(width: 100, height: 60))
    let refB = render(Rectangle().fill(Color.pr).frame(width: 100, height: 60))
    print("CM0 subject \(px(subject, 2, 2)) \(px(subject, 50, 30)) | E differing \(differing(refE, subject)) | B differing \(differing(refB, subject))")
    print("CM0 edge alphas y30 subject: \(alphas(subject, y: 30, stride(from: -1, through: 4, by: 1))) | E: \(alphas(refE, y: 30, stride(from: -1, through: 4, by: 1)))")
    var maxGap = 0
    for y in 0..<60 { for x in 0..<100 { maxGap = max(maxGap, abs(rgb(subject, x, y).1 - rgb(refE, x, y).1)) } }
    print("CM0 max channel gap subject vs Ellipse().fill \(maxGap)")

    print("--- CM1: a path clip (nonzero), even-odd, non-antialiased")
    let c1 = render(Color.pr.frame(width: 100, height: 80).clipShape(tri()))
    print("CM1 triangle inside the box outside the triangle (5,5) \(px(c1, 5, 5)) | inside (50,50) \(px(c1, 50, 50))")
    let c1b = render(Color.pr.frame(width: 80, height: 80).clipShape(twoRects(), style: FillStyle(eoFill: true)))
    let c1n = render(Color.pr.frame(width: 80, height: 80).clipShape(twoRects()))
    print("CM1b even-odd centre \(px(c1b, 40, 40)) ring \(px(c1b, 10, 10)) | nonzero centre \(px(c1n, 40, 40))")
    let c1c = render(Color.pr.frame(width: 100, height: 60).clipShape(Ellipse(), style: FillStyle(antialiased: false)))
    var hard = true
    for y in 0..<60 { for x in 0..<100 { let g = rgb(c1c, x, y).1; if g != 0 && g != 255 { hard = false } } }
    print("CM1c non-antialiased ellipse edge alphas y30 \(alphas(c1c, y: 30, stride(from: -1, through: 4, by: 1))) only 0/255: \(hard)")

    print("--- CM2: two crossing rounded clips")
    let c2 = render(Color.pr.frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 30)).offset(x: 50, y: 50).frame(width: 100, height: 100, alignment: .topLeading).clipShape(RoundedRectangle(cornerRadius: 30)))
    print("CM2 offset form (52,52) \(px(c2, 52, 52)) (97,97) \(px(c2, 97, 97)) (60,60) \(px(c2, 60, 60))")
    let c2b = render(Color.pr.frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 30)).frame(width: 100, height: 100, alignment: .topLeading).padding(.leading, 0).clipShape(RoundedRectangle(cornerRadius: 30)))
    print("CM2b no effect between (outer square corner region) (2,2) \(px(c2b, 2, 2)) (97,97) \(px(c2b, 97, 97))")
    let c2c = render(Color.pr.frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 30)).frame(width: 130, height: 130, alignment: .bottomTrailing).clipShape(RoundedRectangle(cornerRadius: 30)))
    print("CM2c inner touching outer corner: outer corner (127,127) \(px(c2c, 127, 127)) inner corner (30,30) \(px(c2c, 30, 30)) (100,100) \(px(c2c, 100, 100))")

    print("--- CM3: shadow of an ellipse clip")
    let c3 = render(Color.pr.frame(width: 100, height: 60).clipShape(Ellipse()).shadow(color: .black, radius: 0, x: 10, y: 10))
    print("CM3 box corner + offset (108,68) \(px(c3, 108, 68)) | shadow-only (105,40) \(px(c3, 105, 40)) centre \(px(c3, 60, 40))")

    print("--- CM4: rotation")
    let c4 = render(Color.pr.frame(width: 100, height: 40).clipShape(Ellipse()).rotationEffect(.degrees(90)))
    print("CM4 ink \(ink(c4)) | (2,-48) \(px(c4, 2, -48)) centre (50,20) \(px(c4, 50, 20))")

    print("--- CM5: blur against clip order")
    let c5a = render(Color.pr.frame(width: 100, height: 60).blur(radius: 6).clipShape(Ellipse()))
    let c5b = render(Color.pr.frame(width: 100, height: 60).clipShape(Ellipse()).blur(radius: 6))
    print("CM5 blur then clip: row y30 \(alphas(c5a, y: 30, stride(from: -6, through: 6, by: 1))) | clip then blur: \(alphas(c5b, y: 30, stride(from: -6, through: 6, by: 1)))")

    print("--- CM6: opacity outside a clip, no compositingGroup")
    let c6 = render(ZStack(alignment: .topLeading) {
        Color.pb.frame(width: 60, height: 60).clipShape(Ellipse()).padding(.leading, 30).padding(.top, 30)
        Color.pr.frame(width: 60, height: 60).clipShape(Ellipse())
    }.opacity(0.5))
    print("CM6 overlap (45,45) \(px(c6, 45, 45)) (per-leaf (191,64,128), composited (255,128,128))")

    print("--- CM7: control")
    for (n, v) in [("circle", AnyView(Color.pr.frame(width: 60, height: 60).clipShape(Circle()))), ("capsule", AnyView(Color.pr.frame(width: 100, height: 40).clipShape(Capsule())))] {
        print("CM7 \(n) ink \(ink(render(v)))")
    }
}

MainActor.assumeIsolated { probe() }
