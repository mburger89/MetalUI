// SwiftUI probe: the shadow raster cache (C13, PERF-a; user request
// 2026-10-02, item of the gpui-gap priority list, not a plan task). Rulings
// PF-A onward in docs/superpowers/2026-10-09-shadow-cache-decisions.md, spec
// docs/superpowers/specs/2026-10-09-shadow-cache-design.md.
//
// HOW TO RUN (compiled — the `/usr/bin/swift` JIT form fails to link on
// macOS 27):
//
//   xcrun swiftc docs/probes/swiftui-shadow-cache.swift -o /tmp/pf-probe
//   /tmp/pf-probe 2>&1 | grep -v 'Connection\]'
//
// No window is opened: every arm renders through `ImageRenderer`.
//
// INSTRUMENT: INK, copied from docs/probes/swiftui-paths-shadows-transforms.swift
// (`ImageRenderer` at scale 1 onto an opaque white 240×200 canvas, the subject
// `fixedSize()` at (60, 50); pixel samples RELATIVE to that origin), plus
// `differing(a, b, shift:)`: pixels whose RGB differs between `a` and `b`
// moved right by `shift` whole pixels.
//
// QUESTIONS
// - CG: what `.compositingGroup()` does to a shadow, an opacity, a blur and
//   layout. Positive control P1 (SH5 re-run: per leaf) against P2 (SH5c:
//   composited) is the separating pair for the instrument.
// - SP: whether SwiftUI's shadow is shift-invariant under whole-pixel moves
//   (the property a translation-free cache relies on) and whether it moves by
//   sub-pixel amounts (whether quantizing a fractional offset would be a
//   visible divergence). Positive control SP0: the unshadowed square itself
//   at x 0.25 differs from x 0 (the canvas sees sub-pixel placement at all).
//
// RECORDED 2026-10-09 by the C13 design, macOS 27.0.1 (26A434), Apple Swift
// 6.4 (swiftlang-6.4.0.33.1), compiled form, run twice, stdout byte-identical
// (25 lines), exit 0:
//
//   --- P: positive controls (the SH5 / SH5c separating pair, re-run)
//   P1 shadow on the stack (black = per leaf): (65,65)=(0,0,0)
//   P2 .compositingGroup().shadow (blue = composited): (65,65)=(0,0,255)
//   --- CG: compositingGroup
//   CG1 opacity(0.5) overlap pixel: plain (45,45)=(191,64,128) | compositingGroup (45,45)=(255,128,128)
//   CG2 blur(6): differing plain vs compositingGroup 678; (60,45)=(118,0,137) vs (60,45)=(118,0,137)
//   CG3 layout: ink plain x0 y0 w90 h90 n6300 | compositingGroup x0 y0 w90 h90 n6300
//   CG4 compositingGroup alone vs plain: differing 0
//   CG5 half-blue background + text, shadow: differing plain vs compositingGroup 399
//   CG6 compositingGroup().shadow.shadow (outer per leaf over the group's two leaves): (75,75)=(0,0,255) (105,105)=(255,0,0)
//   CG7 .drawingGroup().shadow: (65,65)=(0,0,255)
//   --- SP: shift invariance and sub-pixel shadows
//   SP0 control, square alone at x 0.25 vs 0: differing 0
//   SP1 r10 at x 0 vs x 1 moved 1: differing 0; x 0 vs x 7 moved 7: 0
//   SP2 r10 at x 0.125 vs x 0: differing 0; row y20: 40:132 42:152 44:170 46:188 48:203 50:217 52:228
//   SP2 r10 at x 0.25 vs x 0: differing 0; row y20: 40:132 42:152 44:170 46:188 48:203 50:217 52:228
//   SP2 r10 at x 0.5 vs x 0: differing 3748; row y20: 40:255 42:142 44:161 46:179 48:195 50:210 52:223
//   SP2 r10 at x 0 row y20: 40:132 42:152 44:170 46:188 48:203 50:217 52:228
//   SP2b x 0.5 vs x 0 moved 1 (layout snapped to the pixel grid): differing 0
//   SP4c control, square alone .offset(x: 0.25) vs 0: differing 0
//   SP4 r10 .offset(x: 0.125) vs 0: differing 0; row y20: 40:132 42:152 44:170 46:188 48:203 50:217 52:228
//   SP4 r10 .offset(x: 0.25) vs 0: differing 0; row y20: 40:132 42:152 44:170 46:188 48:203 50:217 52:228
//   SP4 r10 .offset(x: 0.5) vs 0: differing 3748; row y20: 40:255 42:142 44:161 46:179 48:195 50:210 52:223
//   SP4b r10 .offset(x: 1) vs x 0 moved 1: differing 0
//   SP3 near-clear square r10 (the shadow follows alpha): ink none
//
// READING.
// - P1/P2 separate (black vs blue at (65,65)): the instrument sees per-leaf vs
//   composited. SwiftUI's `.shadow` is per leaf (SH5 again); `.compositingGroup()`
//   (P2) and `.drawingGroup()` (CG7) make the shadow one, under the group.
// - CG1: `.compositingGroup().opacity(0.5)` composites the opacity (the overlap
//   reads the top colour over white, (255,128,128), not red over blue,
//   (191,64,128)). CG2: a composited blur differs from the per-leaf one (678
//   pixels). CG3/CG4: no layout change and, alone, no visible change. CG5: a
//   group with a translucent background casts the composited silhouette.
// - SP0 (the positive control for the sub-pixel arms) reads 0: `ImageRenderer`
//   snaps layout positions AND `.offset` to whole pixels (SP2b, SP4c; 0.5
//   rounds up to 1). So SwiftUI never shows a sub-pixel-placed shadow here and
//   the sub-pixel question has no SwiftUI answer through this instrument; only
//   SP1/SP4b stand: a whole-pixel move draws the identical shadow, moved
//   (0 differing pixels at 1 and 7 px) — the property a translation-free cache
//   relies on.

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
    print("--- P: positive controls (the SH5 / SH5c separating pair, re-run)")
    do {
        let o = render(overlap().shadow(color: .black, radius: 0, x: 10, y: 10))
        let oc = render(overlap().compositingGroup().shadow(color: .black, radius: 0, x: 10, y: 10))
        print("P1 shadow on the stack (black = per leaf): \(px(o, 65, 65))")
        print("P2 .compositingGroup().shadow (blue = composited): \(px(oc, 65, 65))")
    }

    print("--- CG: compositingGroup")
    do {
        let plainOpacity = render(overlap().opacity(0.5))
        let groupOpacity = render(overlap().compositingGroup().opacity(0.5))
        print("CG1 opacity(0.5) overlap pixel: plain \(px(plainOpacity, 45, 45)) | compositingGroup \(px(groupOpacity, 45, 45))")
        let plainBlur = render(overlap().blur(radius: 6))
        let groupBlur = render(overlap().compositingGroup().blur(radius: 6))
        print("CG2 blur(6): differing plain vs compositingGroup \(differing(plainBlur, groupBlur)); \(px(plainBlur, 60, 45)) vs \(px(groupBlur, 60, 45))")
        print("CG3 layout: ink plain \(ink(render(overlap()))) | compositingGroup \(ink(render(overlap().compositingGroup())))")
        print("CG4 compositingGroup alone vs plain: differing \(differing(render(overlap()), render(overlap().compositingGroup())))")
        let textBg = render(Text("Hg").font(.system(size: 30)).foregroundStyle(Color.pr).padding(10)
            .background(Color.pb.opacity(0.5)).compositingGroup().shadow(color: .black, radius: 0, x: 4, y: 4))
        let textBgPlain = render(Text("Hg").font(.system(size: 30)).foregroundStyle(Color.pr).padding(10)
            .background(Color.pb.opacity(0.5)).shadow(color: .black, radius: 0, x: 4, y: 4))
        print("CG5 half-blue background + text, shadow: differing plain vs compositingGroup \(differing(textBgPlain, textBg))")
        let nested = render(overlap().compositingGroup().shadow(color: .black, radius: 0, x: 10, y: 10)
            .shadow(color: .pr, radius: 0, x: 10, y: 10))
        print("CG6 compositingGroup().shadow.shadow (outer per leaf over the group's two leaves): \(px(nested, 75, 75)) \(px(nested, 105, 105))")
        let dg = render(overlap().drawingGroup().shadow(color: .black, radius: 0, x: 10, y: 10))
        print("CG7 .drawingGroup().shadow: \(px(dg, 65, 65))")
    }

    print("--- SP: shift invariance and sub-pixel shadows")
    do {
        let sq = Color.pr.frame(width: 40, height: 40)
        print("SP0 control, square alone at x 0.25 vs 0: differing \(differing(render(sq), render(sq, leading: 0.25)))")
        let s0 = render(sq.shadow(color: .black, radius: 10))
        let s1 = render(sq.shadow(color: .black, radius: 10), leading: 1)
        let s7 = render(sq.shadow(color: .black, radius: 10), leading: 7)
        print("SP1 r10 at x 0 vs x 1 moved 1: differing \(differing(s0, s1, shift: 1)); x 0 vs x 7 moved 7: \(differing(s0, s7, shift: 7))")
        for f in [0.125, 0.25, 0.5] {
            let sf = render(sq.shadow(color: .black, radius: 10), leading: CGFloat(f))
            print("SP2 r10 at x \(f) vs x 0: differing \(differing(s0, sf)); row y20: \(row(sf, y: 20, stride(from: 40, through: 52, by: 2)))")
        }
        print("SP2 r10 at x 0 row y20: \(row(s0, y: 20, stride(from: 40, through: 52, by: 2)))")
        let shadowOnly = render(Color.clear.frame(width: 40, height: 40).background(Color.pr.opacity(0.0001))
            .shadow(color: .black, radius: 10))
        let s05 = render(sq.shadow(color: .black, radius: 10), leading: 0.5)
        print("SP2b x 0.5 vs x 0 moved 1 (layout snapped to the pixel grid): differing \(differing(s0, s05, shift: 1))")
        print("SP4c control, square alone .offset(x: 0.25) vs 0: differing \(differing(render(sq), render(sq.offset(x: 0.25))))")
        for f in [0.125, 0.25, 0.5] {
            let so = render(sq.shadow(color: .black, radius: 10).offset(x: CGFloat(f)))
            print("SP4 r10 .offset(x: \(f)) vs 0: differing \(differing(s0, so)); row y20: \(row(so, y: 20, stride(from: 40, through: 52, by: 2)))")
        }
        let so1 = render(sq.shadow(color: .black, radius: 10).offset(x: 1))
        print("SP4b r10 .offset(x: 1) vs x 0 moved 1: differing \(differing(s0, so1, shift: 1))")
        print("SP3 near-clear square r10 (the shadow follows alpha): ink \(ink(shadowOnly))")
    }
}

MainActor.assumeIsolated { probe() }
