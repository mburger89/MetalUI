// SwiftUI probe: group opacity (R4-5 PR A, retires divergence 205; ruling
// prefix GO-, docs/superpowers/2026-11-06-group-opacity-decisions.md, record 218).
//
// HOW TO RUN (compiled; the `/usr/bin/swift` JIT form fails to link on macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-group-opacity.swift -o /tmp/go-probe
//   /tmp/go-probe 2>&1 | grep -v 'Connection\]'
//
// No window is opened: every arm renders through `ImageRenderer`.
//
// INSTRUMENT: INK, copied from docs/probes/swiftui-shadow-cache.swift
// (`ImageRenderer` at scale 1 onto an opaque white 240x200 canvas, the subject
// `fixedSize()` at (60, 50); pixel samples RELATIVE to that origin). The
// overlap pixel is (45,45): the red square covers 0..<60, the blue one 30..<90.
//
// QUESTIONS. What an opacity does to a container with and without
// `.compositingGroup()`, nested, under a rotation, and what a shadow or blur
// outside the group does to the group's opacity. GO0 is the separating pair
// (FR-M): a plain `.opacity(0.5)` reads per leaf, the group one composited.
// GO8 (a material in a group) cannot be measured here: `ImageRenderer` draws
// no material, so divergence 222 rests on BB-A. W1/W2 (the GO0 pair in a real
// NSHostingView window, captured by window id) need an unlocked screen.
//
// RECORDED 2026-11-06 by R4-5 PR A, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9),
// compiled form, run twice, stdout byte-identical (16 lines), exit 0:
//
//   --- GO0: the separating pair (CG1 re-run)
//   GO0 plain opacity(0.5) (45,45)=(191,64,128) | compositingGroup().opacity(0.5) (45,45)=(255,128,128) | differing 900
//   --- GO1: opacity inside, group outside
//   GO1 overlap().opacity(0.5).compositingGroup(): (45,45)=(191,64,128) (per leaf expected, equal to plain: differing 0)
//   --- GO2: two opacities on one group
//   GO2 compositingGroup().opacity(0.5).opacity(0.5): (45,45)=(255,191,191) (15,15)=(255,191,191) (75,75)=(191,191,255)
//   --- GO3: a rotated group
//   GO3 compositingGroup().rotationEffect(30).opacity(0.5) centre: (45,45)=(255,128,128) | plain (45,45)=(191,64,128) | differing 1039
//   --- GO4: nested groups with a third square
//   GO4 outer group over an inner group + green: overlap (45,45)=(255,191,191) green (100,100)=(154,227,172) red (10,10)=(255,191,191)
//   --- GO5: shadow outside an opacity group
//   GO5 group.opacity(0.5).shadow(0, 10, 10): shadow-only (95,95) (95,95)=(128,128,128) overlap (45,45)=(255,128,128) (65,65) (65,65)=(128,128,255)
//   --- GO6: blur outside an opacity group
//   GO6 group.opacity(0.5).blur(6): (45,45)=(255,128,128) (30,45)=(255,128,128) ink x-13 y-12 w115 h115 n11134
//   --- GO7: drawingGroup
//   GO7 drawingGroup().opacity(0.5): (45,45)=(255,128,128)
//
// READING.
// - GO0 separates (900 pixels differ): plain `.opacity` on a container is per leaf
//   (191,64,128), `.compositingGroup().opacity` composites (255,128,128). GO1: an
//   opacity inside the group is per leaf (equal to plain). GO2: opacities on one
//   group multiply (0.25: 255,191,191). GO3: the group composites under a rotation.
//   GO4: an inner group inside an outer one composites twice (outer-group density
//   on the inner overlap 255,191,191). GO5: the shadow outside an opacity group is
//   cast by the faded group (95,95 reads gray 128, not black) and the group is drawn
//   over it unchanged at (65,65) = half blue over white: the shadow does not show
//   through the translucent group, which the per-primitive model cannot reproduce
//   (divergence 221). GO6: blur outside the group reads the composited group
//   (221). GO7: drawingGroup composites an opacity too.
// - GO8 (material in a group) and W1/W2 (real window) were not measured: see record 218.

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
    xs.map { "\($0):\(rgb(b, $0, y).0)" }.joined(separator: " ")
}

@MainActor func overlap() -> some View {
    ZStack(alignment: .topLeading) {
        Color.pb.frame(width: 60, height: 60).padding(.leading, 30).padding(.top, 30)
        Color.pr.frame(width: 60, height: 60)
    }
}

@MainActor func probe() {
    print("--- GO0: the separating pair (CG1 re-run)")
    let plain = render(overlap().opacity(0.5))
    let group = render(overlap().compositingGroup().opacity(0.5))
    print("GO0 plain opacity(0.5) \(px(plain, 45, 45)) | compositingGroup().opacity(0.5) \(px(group, 45, 45)) | differing \(differing(plain, group))")

    print("--- GO1: opacity inside, group outside")
    let inner = render(overlap().opacity(0.5).compositingGroup())
    print("GO1 overlap().opacity(0.5).compositingGroup(): \(px(inner, 45, 45)) (per leaf expected, equal to plain: differing \(differing(plain, inner)))")

    print("--- GO2: two opacities on one group")
    let two = render(overlap().compositingGroup().opacity(0.5).opacity(0.5))
    print("GO2 compositingGroup().opacity(0.5).opacity(0.5): \(px(two, 45, 45)) \(px(two, 15, 15)) \(px(two, 75, 75))")

    print("--- GO3: a rotated group")
    let rot = render(overlap().compositingGroup().rotationEffect(.degrees(30)).opacity(0.5))
    let rotPlain = render(overlap().rotationEffect(.degrees(30)).opacity(0.5))
    print("GO3 compositingGroup().rotationEffect(30).opacity(0.5) centre: \(px(rot, 45, 45)) | plain \(px(rotPlain, 45, 45)) | differing \(differing(rotPlain, rot))")

    print("--- GO4: nested groups with a third square")
    let nested = render(ZStack(alignment: .topLeading) {
        overlap().compositingGroup().opacity(0.5)
        Color.green.frame(width: 60, height: 60).padding(.leading, 60).padding(.top, 60)
    }.compositingGroup().opacity(0.5))
    print("GO4 outer group over an inner group + green: overlap \(px(nested, 45, 45)) green \(px(nested, 100, 100)) red \(px(nested, 10, 10))")

    print("--- GO5: shadow outside an opacity group")
    let sh = render(overlap().compositingGroup().opacity(0.5).shadow(color: .black, radius: 0, x: 10, y: 10))
    print("GO5 group.opacity(0.5).shadow(0, 10, 10): shadow-only (95,95) \(px(sh, 95, 95)) overlap \(px(sh, 45, 45)) (65,65) \(px(sh, 65, 65))")

    print("--- GO6: blur outside an opacity group")
    let bl = render(overlap().compositingGroup().opacity(0.5).blur(radius: 6))
    print("GO6 group.opacity(0.5).blur(6): \(px(bl, 45, 45)) \(px(bl, 30, 45)) ink \(ink(bl))")

    print("--- GO7: drawingGroup")
    let dg = render(overlap().drawingGroup().opacity(0.5))
    print("GO7 drawingGroup().opacity(0.5): \(px(dg, 45, 45))")
}

MainActor.assumeIsolated { probe() }
