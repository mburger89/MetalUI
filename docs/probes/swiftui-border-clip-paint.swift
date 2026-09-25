// SwiftUI probe: WHERE does `.border` draw, and what does the order of
// `.background`, `.cornerRadius`/`.clipShape` and `.border` change? Measured by
// rendering an `NSHostingView` into a bitmap and reading pixels, because these
// are paint questions and no frame-reading instrument can see them.
//
// Evidence for rulings OM-B (a legacy `.border` is paint-only and draws INSIDE
// the element's box), OM-G (a corner radius rounds what was declared before it,
// not after) and OM-L (the focus ring is MetalUI's own affordance, drawn as a
// border on the element's own box) in
// docs/superpowers/2026-09-15-outer-modifiers-decisions.md.
//
// HOW TO RUN (both forms were run):
//
//   /usr/bin/swift docs/probes/swiftui-border-clip-paint.swift
//   xcrun swiftc docs/probes/swiftui-border-clip-paint.swift -o /tmp/om-paint && /tmp/om-paint
//
// THE INSTRUMENT. Each arm is a 40x40 view over an opaque white backdrop,
// rendered through `NSHostingView.cacheDisplay(in:to:)` into a bitmap, then
// sampled at SEVEN points: the corner (1, 1), two points stepping in along the
// diagonal (3, 3) and (6, 6), two points INSIDE the corner arc (5, 5) and
// (7, 7), the top edge's midpoint (20, 1) and the centre (20, 20). Colours are
// classified by nearest named colour so that the backdrop (white) is
// distinguishable from an unpainted area.
//
// POSITIVE CONTROLS. K0: a plain red 40x40 reads red at all seven points — the
// sampler sees paint everywhere. K1: a white-only arm reads white at all seven,
// so "white" really does mean "nothing was drawn here".
//
// RE-RECORDED 2026-09-15 (design review round 2), macOS 26.6.2 (25G83), after
// critic findings 3 and 4. Three changes, all additive: the two `arc` sample
// points, arm B3 (is the border drawn over a filling CHILD?) and arm M1 (the
// MetalUI-equivalent single rounded bordered rect, as a reference for D2).
// **The first recording's five points could not separate D2 from M1** — every
// one of them agreed — so the spec's "`.border.cornerRadius` is the same as
// MetalUI's one-emission answer" row was unfalsifiable rather than true.
// RE-RUN 2026-09-15 (plan task 5 lane 2's REVIEW round), script form, empty
// stderr: all twenty-six lines below reproduce, controls included. The re-run was
// for arms G1/G2, which the spec's §6.2 matrix had read as an agreement with
// MetalUI — they are one view with two `.opacity` calls, where MetalUI's legacy
// path writes one `Decoration` field twice and the last write wins. Divergence
// `OM-AH`; the probe was right and the row was wrong.
//
// Script form under /usr/bin/swift (Apple Swift 6.4, swiftlang-6.4.0.33.1) and
// compiled form under `xcrun swiftc` (the same 6.4): byte-identical stdout,
// exit 0 both, compiled stderr empty, run stderr empty.
// RE-RUN AND EXTENDED 2026-09-24 (plan task 7 stage 11, ruling LR-FW), macOS
// 27.0 (26A428), Apple Swift 6.4 (swiftlang-6.4.0.33.1): every one of the
// twenty-six lines below reproduced byte for byte, controls included, BEFORE
// group H was added; then group H (three arms) was added between G and F and the
// whole file re-run in both forms — script and compiled stdout byte-identical
// (`cmp`), exit 0, stderr empty, the twenty-six earlier lines unchanged. H
// asks whether G3/G4's order rule holds for a BORDER, and for a background
// written between two opacities. Its separating arm is H1 vs H2 (faded vs the
// full border colour B2 reads); H3 reads G3's single fade, not G2's double one.
//
//   --- controls
//     K0 red 40x40 (control)                  : corner(1,1)=rgb(1.00,0.15,0.00) in(3,3)=rgb(1.00,0.15,0.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     K1 nothing (backdrop control)           : corner(1,1)=white in(3,3)=white arc(5,5)=white arc(7,7)=white in(6,6)=white topmid(20,1)=white centre(20,20)=white
//   --- B: where does .border draw?
//     B1 red.border(blue, width: 4)           : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     B2 clear.border(blue, width: 4)         : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=white arc(7,7)=white in(6,6)=white topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=white
//     B3 box{fillingChild}.border(blue, 4)    : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//   --- C: corner radius x background
//     C1 red.cornerRadius(12)                 : corner(1,1)=white in(3,3)=white arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     C2 clear.background(red).cornerRadius(12): corner(1,1)=white in(3,3)=white arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     C3 clear.cornerRadius(12).background(red): corner(1,1)=rgb(1.00,0.15,0.00) in(3,3)=rgb(1.00,0.15,0.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//   --- D: corner radius x border
//     D1 red.cornerRadius(12).border(blue, 4) : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     D2 red.border(blue, 4).cornerRadius(12) : corner(1,1)=white in(3,3)=white arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     M1 RoundedRect(12) fill+strokeBorder 4  : corner(1,1)=white in(3,3)=white arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(0.28,0.16,0.83) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//   --- E: clipShape x background
//     E1 clear.background(red).clipShape(RR 12): corner(1,1)=white in(3,3)=white arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     E2 clear.clipShape(RR 12).background(red): corner(1,1)=rgb(1.00,0.15,0.00) in(3,3)=rgb(1.00,0.15,0.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//   --- G: opacity — does it multiply, and does it reach a background written after it?
//     G1 red.opacity(0.5)                   : corner(1,1)=rgb(1.00,0.58,0.58) in(3,3)=rgb(1.00,0.58,0.58) arc(5,5)=rgb(1.00,0.58,0.58) arc(7,7)=rgb(1.00,0.58,0.58) in(6,6)=rgb(1.00,0.58,0.58) topmid(20,1)=rgb(1.00,0.58,0.58) centre(20,20)=rgb(1.00,0.58,0.58)
//     G2 red.opacity(0.5).opacity(0.5)      : corner(1,1)=rgb(1.00,0.80,0.80) in(3,3)=rgb(1.00,0.80,0.80) arc(5,5)=rgb(1.00,0.80,0.80) arc(7,7)=rgb(1.00,0.80,0.80) in(6,6)=rgb(1.00,0.80,0.80) topmid(20,1)=rgb(1.00,0.80,0.80) centre(20,20)=rgb(1.00,0.80,0.80)
//     G3 clear.background(red).opacity(0.5) : corner(1,1)=rgb(1.00,0.58,0.58) in(3,3)=rgb(1.00,0.58,0.58) arc(5,5)=rgb(1.00,0.58,0.58) arc(7,7)=rgb(1.00,0.58,0.58) in(6,6)=rgb(1.00,0.58,0.58) topmid(20,1)=rgb(1.00,0.58,0.58) centre(20,20)=rgb(1.00,0.58,0.58)
//     G4 clear.opacity(0.5).background(red) : corner(1,1)=rgb(1.00,0.15,0.00) in(3,3)=rgb(1.00,0.15,0.00) arc(5,5)=rgb(1.00,0.15,0.00) arc(7,7)=rgb(1.00,0.15,0.00) in(6,6)=rgb(1.00,0.15,0.00) topmid(20,1)=rgb(1.00,0.15,0.00) centre(20,20)=rgb(1.00,0.15,0.00)
//   --- H: opacity x border order, and a background between two opacities
//     H1 clear.border(blue,4).opacity(0.5)  : corner(1,1)=rgb(0.57,0.59,1.00) in(3,3)=rgb(0.57,0.59,1.00) arc(5,5)=white arc(7,7)=white in(6,6)=white topmid(20,1)=rgb(0.57,0.59,1.00) centre(20,20)=white
//     H2 clear.opacity(0.5).border(blue,4)  : corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=white arc(7,7)=white in(6,6)=white topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=white
//     H3 clear.opacity(.5).background(red).opacity(.5): corner(1,1)=rgb(1.00,0.58,0.58) in(3,3)=rgb(1.00,0.58,0.58) arc(5,5)=rgb(1.00,0.58,0.58) arc(7,7)=rgb(1.00,0.58,0.58) in(6,6)=rgb(1.00,0.58,0.58) topmid(20,1)=rgb(1.00,0.58,0.58) centre(20,20)=rgb(1.00,0.58,0.58)
//   --- F: padding x background x corner radius
//     F1 red20.padding(8).background(blue).cornerRadius(12): corner(1,1)=white in(3,3)=white arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(0.02,0.20,1.00) in(6,6)=rgb(0.02,0.20,1.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//     F2 red20.padding(8).cornerRadius(12).background(blue): corner(1,1)=rgb(0.02,0.20,1.00) in(3,3)=rgb(0.02,0.20,1.00) arc(5,5)=rgb(0.02,0.20,1.00) arc(7,7)=rgb(0.02,0.20,1.00) in(6,6)=rgb(0.02,0.20,1.00) topmid(20,1)=rgb(0.02,0.20,1.00) centre(20,20)=rgb(1.00,0.15,0.00)
//
// WHAT IT SHOWS. The fill samples as rgb(1.00,0.15,0.00), the border as
// rgb(0.02,0.20,1.00), the backdrop as white; no two are confusable.
// - B1/B2: `.border(c, width: 4)` draws INSIDE the box — the border colour at
//   (1,1) and (3,3), the content at (6,6). It is not centred on the edge and
//   not outset.
// - B3: **`.border` is an OVERLAY.** A child filling the whole 40x40 does not
//   hide it: the corner still reads the border colour. MetalUI's single
//   `MUIRect` emitted BEFORE the children would be hidden by that child, which
//   is why ruling OM-V makes the border a second emission after `content()`.
// - C1/C2 vs C3: a corner radius rounds what was declared BEFORE it, and it
//   clips the CONTENT, not only a fill (C1's red leaf loses its corner). A
//   background written after `.cornerRadius` is square (C3 corner = fill).
// - D1 vs D2: `.cornerRadius(12).border(4)` draws a SQUARE border over rounded
//   content (corner = border colour); `.border(4).cornerRadius(12)` rounds the
//   border away at the corner (white) and keeps it at the edge midpoint. A
//   border does NOT inherit a radius applied before it, and a radius applied
//   after DOES cut a border declared before it.
// - **D2 vs M1: `.border.cornerRadius` is NOT MetalUI's one-emission answer.**
//   At arc(5,5) — inside the corner arc — SwiftUI reads the FILL (D2) where a
//   single rounded rect with a 4pt inset border reads the BORDER (M1); in(6,6)
//   likewise differs (fill vs the antialiased blend rgb(0.28,0.16,0.83) across
//   M1's inner edge). SwiftUI clips a SQUARE border by the radius, leaving the
//   arc's interior unbordered; a rounded stroke follows the arc. The two agree
//   at all five of the originally-sampled points, which is why the first
//   recording called them the same. Ruling OM-W.
// - E1/E2: `.clipShape(RoundedRectangle)` behaves exactly as `.cornerRadius`.
// - G1/G2: opacity MULTIPLIES — 0.58 after one 0.5, 0.80 after two.
// - G3 vs G4: opacity fades a background declared BEFORE it (G3) and does NOT
//   reach one declared AFTER it (G4 reads the full fill).
// - H1 vs H2: the same for a BORDER — faded when declared before `.opacity`
//   (rgb(0.57,0.59,1.00) at the corner and top edge), the full border colour
//   B2 reads when declared after it. H3: a background declared between two
//   opacities is faded ONCE (G3's rgb(1.00,0.58,0.58), not G2's 0.80) — only the
//   opacity written after it reaches it. Together: whatever a view declares
//   after an `.opacity` is outside it, fill and border alike (stage 11,
//   LR-FW).
// - F1/F2: the background covers the padding in both orders; only the rounding
//   differs.

import AppKit
import SwiftUI

let side = 40

/// Authored in sRGB rather than as `Color.red`/`Color.blue`. Neither spelling
/// round-trips — compositing happens in the display's own space, so the
/// classifier prints the sampled triple. On this machine the fill reads
/// rgb(1.00,0.15,0.00) and the border rgb(0.02,0.20,1.00); the two are never
/// confusable with each other or with the white backdrop, which is all the
/// arms need.
let red = Color(.sRGB, red: 1, green: 0, blue: 0)
let blue = Color(.sRGB, red: 0, green: 0, blue: 1)

@MainActor func render<V: View>(_ view: V) -> NSBitmapImageRep {
    let root = ZStack {
        Color.white
        view
    }
    .frame(width: CGFloat(side), height: CGFloat(side))
    let host = NSHostingView(rootView: root)
    host.frame = CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    return rep
}

let named: [(String, (CGFloat, CGFloat, CGFloat))] = [
    ("white", (1, 1, 1)), ("black", (0, 0, 0)),
    ("red", (1, 0, 0)), ("green", (0, 1, 0)), ("blue", (0, 0, 1)),
]

func classify(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "?" }
    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
    var best = "?", bestD = Double.infinity
    for (name, v) in named {
        let d = Double(pow(r - v.0, 2) + pow(g - v.1, 2) + pow(b - v.2, 2))
        if d < bestD { bestD = d; best = name }
    }
    return bestD < 0.02 ? best : String(format: "rgb(%.2f,%.2f,%.2f)", r, g, b)
}

/// Sample points, in the bitmap's top-left origin coordinates.
///
/// **`arc(5,5)` and `arc(7,7)` were added after the first recording**, because
/// the original five could not separate "a square border clipped by a later
/// radius" from "a rounded stroke": both read white at (1,1) and (3,3), the
/// fill at (6,6), and the border at the edge midpoint. Inside the corner arc of
/// a radius-12 rounded rect with a 4pt inset border they differ — see M1 vs D2
/// in the header.
let points = [("corner(1,1)", (1, 1)), ("in(3,3)", (3, 3)),
              ("arc(5,5)", (5, 5)), ("arc(7,7)", (7, 7)), ("in(6,6)", (6, 6)),
              ("topmid(20,1)", (20, 1)), ("centre(20,20)", (20, 20))]

@MainActor func arm<V: View>(_ label: String, _ view: V) {
    let rep = render(view)
    let sx = rep.pixelsWide / side
    let sy = rep.pixelsHigh / side
    let readings = points.map { name, p in
        "\(name)=\(classify(rep.colorAt(x: p.0 * sx, y: p.1 * sy)))"
    }
    print("  \(label): \(readings.joined(separator: " "))")
}

@MainActor func run() {
    print("--- controls")
    arm("K0 red 40x40 (control)                  ", red)
    arm("K1 nothing (backdrop control)           ", Color.clear)

    print("--- B: where does .border draw?")
    arm("B1 red.border(blue, width: 4)           ", red.border(blue, width: 4))
    arm("B2 clear.border(blue, width: 4)         ",
        Color.clear.frame(width: 40, height: 40).border(blue, width: 4))
    // B3: is the border drawn OVER a child that fills the whole box, or under
    // it? MetalUI's single emitted `MUIRect` is drawn before the children, so a
    // filling child would hide it. This arm settles SwiftUI's side directly
    // rather than inferring it from B1's leaf-is-the-content shape.
    arm("B3 box{fillingChild}.border(blue, 4)    ",
        Color.clear.frame(width: 40, height: 40)
            .overlay(red).border(blue, width: 4))

    print("--- C: corner radius x background")
    arm("C1 red.cornerRadius(12)                 ", red.cornerRadius(12))
    arm("C2 clear.background(red).cornerRadius(12)",
        Color.clear.frame(width: 40, height: 40).background(red).cornerRadius(12))
    arm("C3 clear.cornerRadius(12).background(red)",
        Color.clear.frame(width: 40, height: 40).cornerRadius(12).background(red))

    print("--- D: corner radius x border")
    arm("D1 red.cornerRadius(12).border(blue, 4) ",
        red.cornerRadius(12).border(blue, width: 4))
    arm("D2 red.border(blue, 4).cornerRadius(12) ",
        red.border(blue, width: 4).cornerRadius(12))
    // M1 is the MetalUI EQUIVALENT of D2, not another SwiftUI question: one
    // rounded rect carrying a fill, a radius and an inset border — exactly what
    // `paintDecoration`'s single `pass.fill` emits. If D2 and M1 read the same
    // at every point, MetalUI's one-emission answer reproduces SwiftUI's
    // `.border.cornerRadius`; where they differ, that order is not expressible.
    arm("M1 RoundedRect(12) fill+strokeBorder 4  ",
        RoundedRectangle(cornerRadius: 12).fill(red)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(blue, lineWidth: 4))
            .frame(width: 40, height: 40))

    print("--- E: clipShape x background")
    arm("E1 clear.background(red).clipShape(RR 12)",
        Color.clear.frame(width: 40, height: 40).background(red)
            .clipShape(RoundedRectangle(cornerRadius: 12)))
    arm("E2 clear.clipShape(RR 12).background(red)",
        Color.clear.frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 12)).background(red))

    print("--- G: opacity — does it multiply, and does it reach a background written after it?")
    arm("G1 red.opacity(0.5)                   ", red.opacity(0.5))
    arm("G2 red.opacity(0.5).opacity(0.5)      ", red.opacity(0.5).opacity(0.5))
    arm("G3 clear.background(red).opacity(0.5) ",
        Color.clear.frame(width: 40, height: 40).background(red).opacity(0.5))
    arm("G4 clear.opacity(0.5).background(red) ",
        Color.clear.frame(width: 40, height: 40).opacity(0.5).background(red))

    // H (stage 11, plan task 7): does the G3/G4 order rule hold for a BORDER,
    // and for a background between two opacities? B2 is the unfaded border.
    print("--- H: opacity x border order, and a background between two opacities")
    arm("H1 clear.border(blue,4).opacity(0.5)  ",
        Color.clear.frame(width: 40, height: 40).border(blue, width: 4).opacity(0.5))
    arm("H2 clear.opacity(0.5).border(blue,4)  ",
        Color.clear.frame(width: 40, height: 40).opacity(0.5).border(blue, width: 4))
    arm("H3 clear.opacity(.5).background(red).opacity(.5)",
        Color.clear.frame(width: 40, height: 40).opacity(0.5).background(red).opacity(0.5))

    print("--- F: padding x background x corner radius")
    arm("F1 red20.padding(8).background(blue).cornerRadius(12)",
        red.frame(width: 20, height: 20).padding(10)
            .background(blue).cornerRadius(12))
    arm("F2 red20.padding(8).cornerRadius(12).background(blue)",
        red.frame(width: 20, height: 20).padding(10)
            .cornerRadius(12).background(blue))
}

MainActor.assumeIsolated { run() }
