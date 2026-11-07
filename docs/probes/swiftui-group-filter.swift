// SwiftUI probe: a shadow and a blur over a group (R4-5 PR B, retires divergences
// 221 and 1066 and moves 167; ruling prefix GF-,
// docs/superpowers/2026-11-06-group-filter-decisions.md, record 219).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-group-filter.swift -o /tmp/gf-probe
//   /tmp/gf-probe 2>&1 | grep -v 'Connection\]'
//
// No window is opened: every arm renders through `ImageRenderer`.
//
// INSTRUMENT: INK, copied from docs/probes/swiftui-group-opacity.swift.
//
// QUESTIONS. GF0 is the separating arm (FR-M): a shadow outside an opacity group
// either lands in the group's opacity (model F: the fade is applied after the shadow,
// so the shadow does not show through the half-faded content) or is cast by the
// faded composite and drawn under it (model S). Exactly one reference must read 0
// differing pixels. GF3 separates a blur of the composited group from a blur of
// per-leaf faded leaves. GF5 asks whether a projective effect's content is shadowed
// and blurred at all. GF6 (a platform view) cannot be measured here and W1 needs an
// unlocked screen.
//
// RECORDED 2026-11-06 by R4-5 PR B, macOS 27.2, Apple Swift 6.4.2, compiled form, run
// twice, stdout byte-identical (14 lines), exit 0, screen locked, no computer use:
//
//   --- GF0: the separating arm (F against S)
//   GF0 subject (95,95) (95,95)=(128,128,128) (65,65) (65,65)=(128,128,255) | F differing 0 (65,65) (65,65)=(128,128,255) | S differing 4800 (65,65) (65,65)=(64,64,191)
//   --- GF1: is F group-only (a leaf's opacity before the shadow)
//   GF1 leaf .opacity.shadow (55,55) (55,55)=(255,128,128) (65,65) (65,65)=(128,128,128) | Color.opacity.shadow (55,55) (55,55)=(191,64,64) | F-form (55,55) (55,55)=(255,128,128) (65,65) (65,65)=(128,128,128)
//   --- GF2: radius 6, default colour, against the F reference
//   GF2 differing vs F 0 row y95: 80:222 84:222 88:223 92:225 96:231 100:240 104:248 108:253 112:255 116:255
//   --- GF3: blur of the composite against blur of per-leaf faded leaves
//   GF3 composite (45,45) (45,45)=(255,128,128) | per-leaf (45,45) (45,45)=(192,64,128) | differing 5611
//   --- GF4: mixed marks under a shadow
//   GF4 shadow-only under the faded part (95,95) (95,95)=(128,128,128) | under the green part (65,125) (65,125)=(0,0,0)
//   --- GF5: a projective effect, shadowed and blurred
//   GF5 projected ink x-4 y-14 w51 h88 n3526 | shadowed ink x-4 y-14 w61 h98 n4626 differing from plain 1181 | blurred ink x-18 y-26 w78 h112 n7321 differing from plain 6428 row y30: -4:122 2:35 8:2 14:0 20:0 26:0 32:0 38:14 44:76 50:181 56:242 62:255 68:255
//   --- GF6: a platform view cannot be measured (ImageRenderer draws no platform view)
//   GF6 control, a plain colour blurred: ink x-13 y-13 w86 h86 n7234
//
// READING. GF0 separates: model F (the fade is applied to the shadow and the content
// together) differs 0, model S (the shadow of the faded composite drawn under it)
// differs 4800. GF1: a VIEW's .opacity before a shadow is F as well (55,55 reads half
// red over white, the shadow hidden under it), but a COLOUR's alpha is S (191,64,64).
// GF2: radius 6 equals the F reference (0 differing). GF3 separates: the composite
// (255,128,128) against per-leaf (192,64,128), 5611 pixels. GF4: the shadow-only pixel
// under the faded part is half black (128), under the unfaded green part it is full
// black (0). GF5: a rotation3DEffect's projected content is shadowed (1181 pixels
// added) and blurred (ink grows to 78 x 112): 1066 is real. GF6 and W1 (a platform
// view, a real window): see record 219 (W1 NOT RUN, the screen was locked).

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

@MainActor func overlap() -> some View {
    ZStack(alignment: .topLeading) {
        Color.pb.frame(width: 60, height: 60).padding(.leading, 30).padding(.top, 30)
        Color.pr.frame(width: 60, height: 60)
    }
}

@MainActor func probe() {
    print("--- GF0: the separating arm (F against S)")
    let subject = render(overlap().compositingGroup().opacity(0.5).shadow(color: .black, radius: 0, x: 10, y: 10))
    let refF = render(overlap().compositingGroup().shadow(color: .black, radius: 0, x: 10, y: 10).compositingGroup().opacity(0.5))
    let refS = render(ZStack(alignment: .topLeading) {
        overlap().compositingGroup().colorMultiply(.black).opacity(0.5).offset(x: 10, y: 10)
        overlap().compositingGroup().opacity(0.5)
    })
    print("GF0 subject (95,95) \(px(subject, 95, 95)) (65,65) \(px(subject, 65, 65)) | F differing \(differing(refF, subject)) (65,65) \(px(refF, 65, 65)) | S differing \(differing(refS, subject)) (65,65) \(px(refS, 65, 65))")

    print("--- GF1: is F group-only (a leaf's opacity before the shadow)")
    let leafOp = render(Color.pr.frame(width: 60, height: 60).opacity(0.5).shadow(color: .black, radius: 0, x: 10, y: 10))
    let colorOp = render(Color.pr.opacity(0.5).frame(width: 60, height: 60).shadow(color: .black, radius: 0, x: 10, y: 10))
    let leafF = render(Color.pr.frame(width: 60, height: 60).shadow(color: .black, radius: 0, x: 10, y: 10).compositingGroup().opacity(0.5))
    print("GF1 leaf .opacity.shadow (55,55) \(px(leafOp, 55, 55)) (65,65) \(px(leafOp, 65, 65)) | Color.opacity.shadow (55,55) \(px(colorOp, 55, 55)) | F-form (55,55) \(px(leafF, 55, 55)) (65,65) \(px(leafF, 65, 65))")

    print("--- GF2: radius 6, default colour, against the F reference")
    let g2 = render(overlap().compositingGroup().opacity(0.5).shadow(radius: 6, x: 10, y: 10))
    let g2F = render(overlap().compositingGroup().shadow(radius: 6, x: 10, y: 10).compositingGroup().opacity(0.5))
    print("GF2 differing vs F \(differing(g2F, g2)) row y95: \(row(g2, y: 95, stride(from: 80, through: 116, by: 4)))")

    print("--- GF3: blur of the composite against blur of per-leaf faded leaves")
    let b1 = render(overlap().compositingGroup().opacity(0.5).blur(radius: 6))
    let b2 = render(overlap().opacity(0.5).compositingGroup().blur(radius: 6))
    print("GF3 composite (45,45) \(px(b1, 45, 45)) | per-leaf (45,45) \(px(b2, 45, 45)) | differing \(differing(b2, b1))")

    print("--- GF4: mixed marks under a shadow")
    let mixed = render(VStack(spacing: 0) {
        overlap().compositingGroup().opacity(0.5)
        Color.green.frame(width: 30, height: 30)
    }.compositingGroup().shadow(color: .black, radius: 0, x: 10, y: 10))
    print("GF4 shadow-only under the faded part (95,95) \(px(mixed, 95, 95)) | under the green part (65,125) \(px(mixed, 65, 125))")

    print("--- GF5: a projective effect, shadowed and blurred")
    let proj = render(Color.pr.frame(width: 60, height: 60).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0)))
    let projS = render(Color.pr.frame(width: 60, height: 60).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0)).shadow(color: .black, radius: 0, x: 10, y: 10))
    let projB = render(Color.pr.frame(width: 60, height: 60).rotation3DEffect(.degrees(40), axis: (x: 0, y: 1, z: 0)).blur(radius: 6))
    print("GF5 projected ink \(ink(proj)) | shadowed ink \(ink(projS)) differing from plain \(differing(proj, projS)) | blurred ink \(ink(projB)) differing from plain \(differing(proj, projB)) row y30: \(row(projB, y: 30, stride(from: -4, through: 70, by: 6)))")

    print("--- GF6: a platform view cannot be measured (ImageRenderer draws no platform view)")
    let host = render(Color.pr.frame(width: 60, height: 60).blur(radius: 6))
    print("GF6 control, a plain colour blurred: ink \(ink(host))")
}

MainActor.assumeIsolated { probe() }
