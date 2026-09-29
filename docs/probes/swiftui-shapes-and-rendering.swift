// SwiftUI probe: shapes, fills/strokes, clipping, overlays/backgrounds with
// shapes, and images (plan task 11, part 2 — rulings TE-AC onward).
//
// HOW TO RUN (SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-shapes-and-rendering.swift -o /tmp/shapes-probe && /tmp/shapes-probe
//   /usr/bin/swift docs/probes/swiftui-shapes-and-rendering.swift
//
// INSTRUMENTS. Two, each with its own positive control in group P:
// - `ImageRenderer` at scale 1 onto an opaque white canvas; a view's ink is
//   read back as bounding boxes — `ink` (any pixel not white), `solid` (the
//   exact probe colour, alpha 255) — plus single-pixel samples.
// - a recording `Layout` (`Probe`) that asks its one subview
//   `sizeThatFits(_:)` at a list of proposals and prints each answer: the
//   shape's or image's own sizing, independent of any renderer.
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - P1: the ink reader separates a 100×60 red rect from a 60×60 one (bbox
//   differs), and from nothing (no ink). P2: `Probe` separates a fixed 40×20
//   leaf from a proposal-taking `Color` (answers differ at every proposal).
// - S: sizing of every built-in shape at five proposals (S1), and where each
//   draws inside a 100×60 frame (S2); S3 RoundedRectangle's default corner
//   style against `.circular` and `.continuous` (pixel counts differing);
//   S4 an over-large radius, S5 a negative one, S6 a tall capsule.
// - F: fill defaults — a bare shape draws the foreground style (F1), a
//   container's `.foregroundStyle` reaches it (F2), `.fill` wins (F3),
//   `.fill(...).stroke(...)` draws the stroke over the fill (F4).
// - K: strokes — centred on the edge (K1), `strokeBorder` inside (K2), the
//   default width (K3), a circle's (K4), layout unchanged by a stroke (K5),
//   a rounded rect's stroke radii (K6), a circle's (K7), an ellipse's inner
//   edge against a concentric ellipse (K8), zero/negative widths (K9), a
//   border wider than half the shape (K10).
// - C: clipping — `.cornerRadius` clips a child (C1), `.clipShape(Circle())`
//   (C2), `.clipped()` (C3), cornerRadius vs clipShape(RoundedRectangle) (C4),
//   `.clipShape(Ellipse())` on a non-square frame (C5), nested clips (C6),
//   an unclipped overflowing child (C0, the control for C1/C3).
// - O: overlays/backgrounds with shapes — a shape background takes the
//   content's size (O1), `.background(_:in:)` (O2), `.overlay(Circle().stroke())`
//   (O3), `.background(in:)`'s default style (O4).
// - I: images — fixed size (I1), `.resizable()` (I2), `.aspectRatio(contentMode:)`
//   fit/fill (I3, I4), `scaledToFit`/`scaledToFill` equal them (I5), an
//   explicit ratio (I6), a resizable image's ideal size (I7), default
//   interpolation vs `.none` (I8), `Image(decorative:scale:)` points (I9),
//   a `.fill` image is not clipped by its frame (I10).
//
// - Revision 2 (same session, the spec's separating arms): A1–A4
//   `aspectRatio(nil)` on a non-image (the ratio is the child's nil×nil
//   answer; a fixed child keeps its size), C8 `clipShape` leaves layout alone,
//   I11 `.medium` against default and `.high`, I12 a half-alpha premultiplied
//   image composited over white, K11/K12 a stroke wider than twice the corner
//   radius (the outer corner of `strokeBorder` and of `stroke`).
//
// RECORDED 2026-09-28 by the plan task 11 part 2 design, macOS 27.0 (26A428),
// Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen locked (lock probe:
// `CGSSessionScreenIsLocked = 1`), no window ordered front
// (ImageRenderer and a Layout only). Revision 1 (68 lines) was run by the
// design's first pass; revision 2 re-ran it whole: the compiled form twice and
// the interpreted form once, stdout byte-identical (77 lines, the first 68
// byte-identical to revision 1's), exit 0:
//
//   P1 red 100x60: x0 y0 w100 h60 n6000 | 60x60: x0 y0 w60 h60 n3600 | empty: none
//   P2 fixed 40x20: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   P2 Color:       nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   S1 Rectangle:        nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   S1 RoundedRectangle: nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   S1 Circle:           nil×nil→10×10 100×60→60×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×100
//   S1 Capsule:          nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   S1 Ellipse:          nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   S1 Circle.fill:      nil×nil→10×10 100×60→60×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×100
//   S1 Circle.stroke:    nil×nil→10×10 100×60→60×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×100
//   S2 Rectangle in frame: ink x0 y0 w100 h60 n6000 solid x0 y0 w100 h60 n6000
//   S2 RoundedRectangle(12) in frame: ink x0 y0 w100 h60 n5908 solid x0 y0 w100 h60 n5808
//   S2 Circle in frame: ink x20 y0 w60 h60 n2920 solid x20 y0 w60 h60 n2716
//   S2 Capsule in frame: ink x0 y0 w100 h60 n5316 solid x0 y0 w100 h60 n5080
//   S2 Ellipse in frame: ink x0 y0 w100 h60 n4848 solid x1 y0 w98 h60 n4564
//   S2 Circle tall in frame: ink x0 y25 w40 h40 n1324 solid x0 y26 w40 h38 n1180
//   S3 RoundedRectangle(20) default vs .circular: 196px, default vs .continuous: 0px, circular vs continuous: 196px
//   S3 corner pixel (4,4): default (255,255,255) circular (255,255,255) continuous (255,255,255)
//   S3 Capsule default vs RoundedRectangle(30,.circular): 230px; Capsule(.circular) vs it: 0px
//   S3 Circle(60) vs RoundedRectangle(30,.circular) 60x60: 0px
//   S4 RR(50,.circular) 100x60 vs Capsule(.circular): 0px
//   S5 RR(-5) vs Rectangle: 0px
//   S6 Capsule tall 40x90: ink x0 y0 w40 h90 n3320
//   F1 bare Rectangle: pixel (10,10) (39,39,39) black none
//   F2 foregroundStyle(blue) container → Circle: blue x0 y0 w60 h60 n2716
//   F3 fill(red) under foregroundStyle(blue): red x0 y0 w60 h60 n2716 blue none
//   F4 fill(red).stroke(blue,10): ink x-5 y-5 w110 h70 n7700 red x5 y5 w90 h50 n4496 blue x-5 y-5 w110 h70 n3196 pixel (0,0) (0,0,255) (-4,-4) (0,0,255)
//   F5 Rectangle().foregroundColor(red): red x0 y0 w100 h60 n6000
//   K1 Rectangle.stroke(10) 100x60: ink x-5 y-5 w110 h70 n3204 solid x-5 y-5 w110 h70 n3196 centre (255,255,255) (4,4) (255,0,0) (6,6) (255,255,255)
//   K2 Rectangle.strokeBorder(10): ink x-1 y-1 w102 h62 n2804 solid x0 y0 w100 h60 n2796 (9,9) (255,40,40) (10,10) (255,255,255)
//   K3 default stroke: ink x-1 y-1 w102 h62 n639 (0,0) (255,255,255) (-1,-1) (255,128,128) (1,1) (255,255,255)
//   K4 Circle.stroke(10) 60: ink x-5 y-5 w70 h70 n2104; strokeBorder: ink x0 y0 w60 h60 n1744 centre (255,255,255)
//   K5 layout: Rectangle.stroke(10): nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10 | strokeBorder: nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   K6 RR(20).stroke(10) vs RR(25).strokeBorder(10) grown by 5: 0px
//   K7 Circle(60).stroke(10) vs Circle(70).strokeBorder(10) grown by 5: 0px
//   K8 Ellipse.strokeBorder(10) 100x60 vs Ellipse minus a concentric 80x40 ellipse: 518px of x0 y0 w100 h60 n2444
//   K9 stroke(0): ink none; stroke(-4): ink none
//   K10 strokeBorder(40) on 100x60: ink x-1 y-1 w102 h62 n6004 solid x0 y0 w100 h60 n6000
//   C0 overflow unclipped: blue x-30 y20 w160 h20 n3200
//   C1 .cornerRadius(12): blue x0 y20 w100 h20 n2000 ink x0 y0 w100 h60 n5908 corner (1,1) (255,255,255)
//   C2 .clipShape(Circle()) 100x60: ink x20 y0 w60 h60 n2920
//   C3 .clipped(): blue x0 y20 w100 h20 n2000 ink x0 y0 w100 h60 n6000 corner (0,0) (255,0,0)
//   C4 cornerRadius(20) vs clipShape(RR 20 default): 0px, vs clipShape(RR 20 .circular): 196px
//   C5 .clipShape(Ellipse()): ink x0 y0 w100 h60 n4848; red-only area vs Ellipse fill ink: x0 y0 w100 h60 n4848
//   C6 RR(30) then Circle vs Circle alone: 0px
//   C7 .clipShape(Capsule()): ink x0 y0 w100 h60 n5316 (0,30) (0,0,255) (1,30) (0,0,255)
//   O1 background(Capsule) on 80x40: blue x1 y0 w78 h40 n1556 ink x0 y0 w80 h40 n2920
//   O2 background(blue, in: Capsule): ink x0 y0 w80 h40 n2920 blue x1 y0 w78 h40 n1556; vs O1: 0px
//   O3 overlay(Circle.stroke(4)) on 100x60: blue x18 y-2 w64 h64 n544 ink x0 y-2 w100 h64 n6080
//   O4 background(in: RR8) default style: centre (255,255,255) ink none
//   O5 layout background(Capsule): nil×nil→60×20 100×60→60×20 0×0→60×20 inf×inf→60×20 100×nil→60×20
//   I1 Image 40x20 sizes: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   I1 in 100x60 frame: red x30 y20 w20 h20 n400 blue x50 y20 w20 h20 n400
//   I2 resizable sizes: nil×nil→40×20 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×20
//   I2 resizable in 100x60: red x0 y0 w49 h60 n2940 blue x51 y0 w49 h60 n2940
//   I3 fit in 100x60: ink x0 y5 w100 h50 n5000 red x0 y5 w49 h50 n2450 blue x51 y5 w49 h50 n2450
//   I4 fill in 100x60: ink x-10 y0 w120 h60 n7200 red x-10 y0 w59 h60 n3540 blue x51 y0 w59 h60 n3540
//   I5 scaledToFit vs fit: 0px, scaledToFill vs fill: 0px
//   I5 layout fit: nil×nil→40×20 100×60→100×50 0×0→0×0 inf×inf→inf×inf 100×nil→100×50
//   I5 layout fill: nil×nil→40×20 100×60→120×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×50
//   I6 aspectRatio(1, .fit) in 100x60: ink x20 y0 w60 h60 n3600
//   I7 non-resizable fit layout: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   I8 default: 0(255,0,0) 10(255,0,0) 24(255,0,0) 25(252,0,3) 40(176,0,79) 49(130,0,125) 50(125,0,130) 60(74,0,181) 75(0,0,255) 76(0,0,255) 90(0,0,255) 99(0,0,255)
//   I8 .none:   0(255,0,0) 10(255,0,0) 24(255,0,0) 25(255,0,0) 40(255,0,0) 49(255,0,0) 50(0,0,255) 60(0,0,255) 75(0,0,255) 76(0,0,255) 90(0,0,255) 99(0,0,255)
//   I8 default vs .none 500px, vs .low 0px, vs .high 880px
//   I9 Image(decorative: 80x40 px, scale: 2) sizes: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   I10 fill unclipped ink x-10 y0 w120 h60 n7200; .clipped() ink x0 y0 w100 h60 n6000
//   A1 Color.aspectRatio(contentMode: .fit) sizes: nil×nil→10×10 100×60→60×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×100
//   A2 Color.scaledToFill sizes: nil×nil→10×10 100×60→100×100 0×0→0×0 inf×inf→inf×inf 100×nil→100×100
//   A3 Color ideal 40x20 .aspectRatio(.fit) sizes: nil×nil→40×20 100×60→100×50 0×0→0×0 inf×inf→inf×inf 100×nil→100×50
//   A4 fixed 40x20 .aspectRatio(.fit) sizes: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   C8 layout clipShape(Circle): nil×nil→100×60 100×60→100×60 0×0→100×60 inf×inf→100×60 100×nil→100×60
//   I11 default vs .medium 0px, .medium vs .high 880px
//   I12 half-alpha red over white: centre (255,127,127)
//   K11 RR(3).strokeBorder(10) corner (0,0) (255,0,0) vs RR(3) fill (255,252,252); outer-edge pixels differing from the fill's: 3228px
//   K12 RR(3).stroke(10) corner (-5,-5) (255,255,255) (-4,-4) (255,255,255)
//   done
//
// READING (rulings TE-AC onward): see the decisions doc; the short form —
// every shape answers its proposal (nil → 10), except Circle, which answers
// the square of the smaller proposed side (and a nil axis takes the other's
// value); a Circle draws centred in its frame. `stroke` is centred on the
// edge (half outside, layout unchanged), `strokeBorder` inside, default
// width 1; stroke(w) on r equals strokeBorder(w) on the shape grown by w/2 at
// r + w/2 (K6, K7); an ellipse's strokeBorder inner edge is NOT a concentric
// ellipse (K8, 518 px); a width <= 0 draws nothing (K9); a radius clamps to
// half the shorter side and a negative one is 0 (S4, S5). RoundedRectangle's and Capsule's default corner style is
// `.continuous`, which differs from `.circular` (S3); `.cornerRadius(r)`
// clips and equals `clipShape(RoundedRectangle(cornerRadius: r))` with the
// continuous default (C1, C4). A bare shape fills with the foreground style
// (F1, F2); `.fill` wins (F3); `.fill(...).stroke(...)` strokes over the
// fill (F4). A shape background takes the content's size and does not change
// layout (O1, O5). An image answers its point size (pixels ÷ scale) until
// `.resizable()`, which answers the proposal (nil → its point size);
// fit/fill are `aspectRatio` of its point size and a fill image overflows
// its frame unless `.clipped()` (I3–I5, I10); default interpolation is
// bilinear with clamped edges and equals `.low` and `.medium`; `.none` is
// nearest; only `.high` differs (I8, I11). `aspectRatio(nil)` takes the ratio
// of the child's nil×nil answer, and a fixed child keeps its own size (A1–A4).
// A `strokeBorder` whose width exceeds twice the radius has a square outer
// corner; a `stroke` over a radius > 0 keeps a round one of radius r + w/2
// (K11, K12). `clipShape` changes no layout (C8).

import AppKit
import SwiftUI

typealias Bitmap = (bytes: [UInt8], w: Int, h: Int)

func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (b, w, h)
}

let canvasW = 200, canvasH = 140

/// The view placed at (50, 40) on a white 200×140 canvas, rendered at scale 1.
@MainActor func render(_ v: some View) -> Bitmap {
    let c = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().offset(x: 50, y: 40)
    }.frame(width: CGFloat(canvasW), height: CGFloat(canvasH))
    let r = ImageRenderer(content: c)
    r.scale = 1
    return bytes(of: r.cgImage!)
}

func px(_ b: Bitmap, _ x: Int, _ y: Int) -> String {
    let i = (y * b.w + x) * 4
    return "(\(b.bytes[i]),\(b.bytes[i + 1]),\(b.bytes[i + 2]))"
}

/// Bounding box, in canvas pixels RELATIVE to the view's origin (50, 40).
func bbox(_ b: Bitmap, _ pred: (UInt8, UInt8, UInt8) -> Bool) -> String {
    var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, n = 0
    for y in 0..<b.h { for x in 0..<b.w {
        let i = (y * b.w + x) * 4
        if pred(b.bytes[i], b.bytes[i + 1], b.bytes[i + 2]) {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y); n += 1
        }
    } }
    if n == 0 { return "none" }
    return "x\(x0 - 50) y\(y0 - 40) w\(x1 - x0 + 1) h\(y1 - y0 + 1) n\(n)"
}

func ink(_ b: Bitmap) -> String { bbox(b) { r, g, bl in !(r == 255 && g == 255 && bl == 255) } }
func red(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 255 && g == 0 && bl == 0 } }
func blue(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 0 && g == 0 && bl == 255 } }
func black(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 0 && g == 0 && bl == 0 } }
func differing(_ a: Bitmap, _ b: Bitmap) -> Int {
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

func fmt(_ v: CGFloat) -> String {
    if v == .infinity { return "inf" }
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

/// Asks its one subview `sizeThatFits` at each proposal and records the answers.
nonisolated(unsafe) var recorded: [String] = []
struct Probe: Layout {
    static let proposals: [(String, ProposedViewSize)] = [
        ("nil×nil", .unspecified), ("100×60", ProposedViewSize(width: 100, height: 60)),
        ("0×0", .zero), ("inf×inf", .infinity), ("100×nil", ProposedViewSize(width: 100, height: nil))]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var parts: [String] = []
        for (label, p) in Self.proposals {
            let s = subviews[0].sizeThatFits(p)
            parts.append("\(label)→\(fmt(s.width))×\(fmt(s.height))")
        }
        recorded.append(parts.joined(separator: " "))
        return CGSize(width: 10, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
    }
}

@MainActor func sizes(_ v: some View) -> String {
    recorded = []
    _ = render(Probe { v })
    return recorded.first ?? "none"
}

/// A 40×20 image: left half red, right half blue.
func halves(scale: CGFloat = 1) -> Image {
    let w = Int(40 * scale), h = Int(20 * scale)
    var b = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        if x < w / 2 { b[i] = 255; b[i + 1] = 0; b[i + 2] = 0 } else { b[i] = 0; b[i + 1] = 0; b[i + 2] = 255 }
    } }
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return Image(decorative: ctx.makeImage()!, scale: scale)
}

/// A 2×1 image: red, blue.
func twoPixels() -> Image {
    var b: [UInt8] = [255, 0, 0, 255, 0, 0, 255, 255]
    let ctx = CGContext(data: &b, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return Image(decorative: ctx.makeImage()!, scale: 1)
}

let R = SwiftUI.Color(.sRGB, red: 1, green: 0, blue: 0)
let B = SwiftUI.Color(.sRGB, red: 0, green: 0, blue: 1)

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)

    // P — controls.
    let p100 = render(Rectangle().fill(R).frame(width: 100, height: 60))
    let p60 = render(Rectangle().fill(R).frame(width: 60, height: 60))
    print("P1 red 100x60: \(red(p100)) | 60x60: \(red(p60)) | empty: \(ink(render(SwiftUI.Color.clear.frame(width: 100, height: 60))))")
    print("P2 fixed 40x20: \(sizes(SwiftUI.Color.red.frame(width: 40, height: 20)))")
    print("P2 Color:       \(sizes(SwiftUI.Color.red))")

    // S — sizing and placement.
    print("S1 Rectangle:        \(sizes(Rectangle()))")
    print("S1 RoundedRectangle: \(sizes(RoundedRectangle(cornerRadius: 12)))")
    print("S1 Circle:           \(sizes(Circle()))")
    print("S1 Capsule:          \(sizes(Capsule()))")
    print("S1 Ellipse:          \(sizes(Ellipse()))")
    print("S1 Circle.fill:      \(sizes(Circle().fill(R)))")
    print("S1 Circle.stroke:    \(sizes(Circle().stroke(R, lineWidth: 10)))")
    for (name, img) in [("Rectangle", render(Rectangle().fill(R).frame(width: 100, height: 60))),
                        ("RoundedRectangle(12)", render(RoundedRectangle(cornerRadius: 12).fill(R).frame(width: 100, height: 60))),
                        ("Circle", render(Circle().fill(R).frame(width: 100, height: 60))),
                        ("Capsule", render(Capsule().fill(R).frame(width: 100, height: 60))),
                        ("Ellipse", render(Ellipse().fill(R).frame(width: 100, height: 60))),
                        ("Circle tall", render(Circle().fill(R).frame(width: 40, height: 90)))] {
        print("S2 \(name) in frame: ink \(ink(img)) solid \(red(img))")
    }
    let rrDefault = render(RoundedRectangle(cornerRadius: 20).fill(R).frame(width: 100, height: 60))
    let rrCircular = render(RoundedRectangle(cornerRadius: 20, style: .circular).fill(R).frame(width: 100, height: 60))
    let rrContinuous = render(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(R).frame(width: 100, height: 60))
    print("S3 RoundedRectangle(20) default vs .circular: \(differing(rrDefault, rrCircular))px, default vs .continuous: \(differing(rrDefault, rrContinuous))px, circular vs continuous: \(differing(rrCircular, rrContinuous))px")
    print("S3 corner pixel (4,4): default \(px(rrDefault, 54, 44)) circular \(px(rrCircular, 54, 44)) continuous \(px(rrContinuous, 54, 44))")
    let capRR = render(RoundedRectangle(cornerRadius: 30, style: .circular).fill(R).frame(width: 100, height: 60))
    let cap = render(Capsule().fill(R).frame(width: 100, height: 60))
    let capC = render(Capsule(style: .circular).fill(R).frame(width: 100, height: 60))
    print("S3 Capsule default vs RoundedRectangle(30,.circular): \(differing(cap, capRR))px; Capsule(.circular) vs it: \(differing(capC, capRR))px")
    let circ = render(Circle().fill(R).frame(width: 60, height: 60))
    let circRR = render(RoundedRectangle(cornerRadius: 30, style: .circular).fill(R).frame(width: 60, height: 60))
    print("S3 Circle(60) vs RoundedRectangle(30,.circular) 60x60: \(differing(circ, circRR))px")

    let rr50 = render(RoundedRectangle(cornerRadius: 50, style: .circular).fill(R).frame(width: 100, height: 60))
    print("S4 RR(50,.circular) 100x60 vs Capsule(.circular): \(differing(rr50, capC))px")
    let rrNeg = render(RoundedRectangle(cornerRadius: -5, style: .circular).fill(R).frame(width: 100, height: 60))
    print("S5 RR(-5) vs Rectangle: \(differing(rrNeg, render(Rectangle().fill(R).frame(width: 100, height: 60))))px")
    print("S6 Capsule tall 40x90: ink \(ink(render(Capsule().fill(R).frame(width: 40, height: 90))))")

    // F — fill defaults.
    let bare = render(Rectangle().frame(width: 100, height: 60))
    print("F1 bare Rectangle: pixel (10,10) \(px(bare, 60, 50)) black \(black(bare))")
    let styled = render(VStack { Circle().frame(width: 60, height: 60) }.foregroundStyle(B))
    print("F2 foregroundStyle(blue) container → Circle: blue \(blue(styled))")
    let beat = render(VStack { Circle().fill(R).frame(width: 60, height: 60) }.foregroundStyle(B))
    print("F3 fill(red) under foregroundStyle(blue): red \(red(beat)) blue \(blue(beat))")
    let both = render(Rectangle().fill(R).stroke(B, lineWidth: 10).frame(width: 100, height: 60))
    print("F4 fill(red).stroke(blue,10): ink \(ink(both)) red \(red(both)) blue \(blue(both)) pixel (0,0) \(px(both, 50, 40)) (-4,-4) \(px(both, 46, 36))")
    let colourFill = render(Rectangle().foregroundColor(R).frame(width: 100, height: 60))
    print("F5 Rectangle().foregroundColor(red): red \(red(colourFill))")

    // K — strokes.
    let k1 = render(Rectangle().stroke(R, lineWidth: 10).frame(width: 100, height: 60))
    print("K1 Rectangle.stroke(10) 100x60: ink \(ink(k1)) solid \(red(k1)) centre \(px(k1, 100, 70)) (4,4) \(px(k1, 54, 44)) (6,6) \(px(k1, 56, 46))")
    let k2 = render(Rectangle().strokeBorder(R, lineWidth: 10).frame(width: 100, height: 60))
    print("K2 Rectangle.strokeBorder(10): ink \(ink(k2)) solid \(red(k2)) (9,9) \(px(k2, 59, 49)) (10,10) \(px(k2, 60, 50))")
    let k3 = render(Rectangle().stroke(R).frame(width: 100, height: 60))
    print("K3 default stroke: ink \(ink(k3)) (0,0) \(px(k3, 50, 40)) (-1,-1) \(px(k3, 49, 39)) (1,1) \(px(k3, 51, 41))")
    let k4 = render(Circle().stroke(R, lineWidth: 10).frame(width: 60, height: 60))
    let k4b = render(Circle().strokeBorder(R, lineWidth: 10).frame(width: 60, height: 60))
    print("K4 Circle.stroke(10) 60: ink \(ink(k4)); strokeBorder: ink \(ink(k4b)) centre \(px(k4b, 80, 70))")
    print("K5 layout: Rectangle.stroke(10): \(sizes(Rectangle().stroke(R, lineWidth: 10))) | strokeBorder: \(sizes(Rectangle().strokeBorder(R, lineWidth: 10)))")
    let k6 = render(RoundedRectangle(cornerRadius: 20, style: .circular).stroke(R, lineWidth: 10).frame(width: 100, height: 60))
    let k6ref = render(RoundedRectangle(cornerRadius: 25, style: .circular).strokeBorder(R, lineWidth: 10).frame(width: 110, height: 70).offset(x: -5, y: -5))
    print("K6 RR(20).stroke(10) vs RR(25).strokeBorder(10) grown by 5: \(differing(k6, k6ref))px")
    let k7 = render(Circle().stroke(R, lineWidth: 10).frame(width: 60, height: 60))
    let k7ref = render(Circle().strokeBorder(R, lineWidth: 10).frame(width: 70, height: 70).offset(x: -5, y: -5))
    print("K7 Circle(60).stroke(10) vs Circle(70).strokeBorder(10) grown by 5: \(differing(k7, k7ref))px")

    let k8 = render(Ellipse().strokeBorder(R, lineWidth: 10).frame(width: 100, height: 60))
    let k8hole = render(ZStack { Ellipse().fill(R); Ellipse().fill(SwiftUI.Color.white).frame(width: 80, height: 40) }.frame(width: 100, height: 60))
    print("K8 Ellipse.strokeBorder(10) 100x60 vs Ellipse minus a concentric 80x40 ellipse: \(differing(k8, k8hole))px of \(ink(k8))")
    let k9 = render(Rectangle().stroke(R, lineWidth: 0).frame(width: 100, height: 60))
    let k9n = render(Rectangle().stroke(R, lineWidth: -4).frame(width: 100, height: 60))
    print("K9 stroke(0): ink \(ink(k9)); stroke(-4): ink \(ink(k9n))")
    let k10 = render(Rectangle().strokeBorder(R, lineWidth: 40).frame(width: 100, height: 60))
    print("K10 strokeBorder(40) on 100x60: ink \(ink(k10)) solid \(red(k10))")

    // C — clipping.
    func overflowing() -> some View {
        R.frame(width: 100, height: 60).overlay(B.frame(width: 160, height: 20))
    }
    let c0 = render(overflowing())
    print("C0 overflow unclipped: blue \(blue(c0))")
    let c1 = render(overflowing().cornerRadius(12))
    print("C1 .cornerRadius(12): blue \(blue(c1)) ink \(ink(c1)) corner (1,1) \(px(c1, 51, 41))")
    let c2 = render(overflowing().clipShape(Circle()))
    print("C2 .clipShape(Circle()) 100x60: ink \(ink(c2))")
    let c3 = render(overflowing().clipped())
    print("C3 .clipped(): blue \(blue(c3)) ink \(ink(c3)) corner (0,0) \(px(c3, 50, 40))")
    let c4a = render(overflowing().cornerRadius(20))
    let c4b = render(overflowing().clipShape(RoundedRectangle(cornerRadius: 20)))
    let c4c = render(overflowing().clipShape(RoundedRectangle(cornerRadius: 20, style: .circular)))
    print("C4 cornerRadius(20) vs clipShape(RR 20 default): \(differing(c4a, c4b))px, vs clipShape(RR 20 .circular): \(differing(c4a, c4c))px")
    let c5 = render(overflowing().clipShape(Ellipse()))
    let c5e = render(Ellipse().fill(R).frame(width: 100, height: 60))
    print("C5 .clipShape(Ellipse()): ink \(ink(c5)); red-only area vs Ellipse fill ink: \(ink(c5e))")
    let c6 = render(overflowing().clipShape(RoundedRectangle(cornerRadius: 30, style: .circular)).padding(0).clipShape(Circle()))
    let c6ref = render(overflowing().clipShape(Circle()))
    print("C6 RR(30) then Circle vs Circle alone: \(differing(c6, c6ref))px")
    let c7 = render(overflowing().clipShape(Capsule()))
    print("C7 .clipShape(Capsule()): ink \(ink(c7)) (0,30) \(px(c7, 50, 70)) (1,30) \(px(c7, 51, 70))")

    // O — overlay / background with shapes.
    let o1 = render(R.frame(width: 60, height: 20).padding(10).background(Capsule().fill(B)))
    print("O1 background(Capsule) on 80x40: blue \(blue(o1)) ink \(ink(o1))")
    let o2 = render(R.frame(width: 60, height: 20).padding(10).background(B, in: Capsule()))
    print("O2 background(blue, in: Capsule): ink \(ink(o2)) blue \(blue(o2)); vs O1: \(differing(o1, o2))px")
    let o3 = render(R.frame(width: 100, height: 60).overlay(Circle().stroke(B, lineWidth: 4)))
    print("O3 overlay(Circle.stroke(4)) on 100x60: blue \(blue(o3)) ink \(ink(o3))")
    let o4 = render(SwiftUI.Color.clear.frame(width: 100, height: 60).background(in: RoundedRectangle(cornerRadius: 8)))
    print("O4 background(in: RR8) default style: centre \(px(o4, 100, 70)) ink \(ink(o4))")
    print("O5 layout background(Capsule): \(sizes(R.frame(width: 60, height: 20).background(Capsule().fill(B))))")

    // I — images.
    print("I1 Image 40x20 sizes: \(sizes(halves()))")
    let i1 = render(halves().frame(width: 100, height: 60))
    print("I1 in 100x60 frame: red \(red(i1)) blue \(blue(i1))")
    print("I2 resizable sizes: \(sizes(halves().resizable()))")
    let i2 = render(halves().resizable().frame(width: 100, height: 60))
    print("I2 resizable in 100x60: red \(red(i2)) blue \(blue(i2))")
    let i3 = render(halves().resizable().aspectRatio(contentMode: .fit).frame(width: 100, height: 60))
    print("I3 fit in 100x60: ink \(ink(i3)) red \(red(i3)) blue \(blue(i3))")
    let i4 = render(halves().resizable().aspectRatio(contentMode: .fill).frame(width: 100, height: 60))
    print("I4 fill in 100x60: ink \(ink(i4)) red \(red(i4)) blue \(blue(i4))")
    let i5a = render(halves().resizable().scaledToFit().frame(width: 100, height: 60))
    let i5b = render(halves().resizable().scaledToFill().frame(width: 100, height: 60))
    print("I5 scaledToFit vs fit: \(differing(i3, i5a))px, scaledToFill vs fill: \(differing(i4, i5b))px")
    print("I5 layout fit: \(sizes(halves().resizable().aspectRatio(contentMode: .fit)))")
    print("I5 layout fill: \(sizes(halves().resizable().aspectRatio(contentMode: .fill)))")
    let i6 = render(halves().resizable().aspectRatio(1, contentMode: .fit).frame(width: 100, height: 60))
    print("I6 aspectRatio(1, .fit) in 100x60: ink \(ink(i6))")
    print("I7 non-resizable fit layout: \(sizes(halves().aspectRatio(contentMode: .fit)))")
    let i8 = render(twoPixels().resizable().frame(width: 100, height: 10))
    let i8n = render(twoPixels().resizable().interpolation(.none).frame(width: 100, height: 10))
    let i8l = render(twoPixels().resizable().interpolation(.low).frame(width: 100, height: 10))
    let i8h = render(twoPixels().resizable().interpolation(.high).frame(width: 100, height: 10))
    let xs = [0, 10, 24, 25, 40, 49, 50, 60, 75, 76, 90, 99]
    print("I8 default: " + xs.map { "\($0)\(px(i8, 50 + $0, 45))" }.joined(separator: " "))
    print("I8 .none:   " + xs.map { "\($0)\(px(i8n, 50 + $0, 45))" }.joined(separator: " "))
    print("I8 default vs .none \(differing(i8, i8n))px, vs .low \(differing(i8, i8l))px, vs .high \(differing(i8, i8h))px")
    print("I9 Image(decorative: 80x40 px, scale: 2) sizes: \(sizes(halves(scale: 2)))")
    let i10 = render(halves().resizable().scaledToFill().frame(width: 100, height: 60))
    let i10c = render(halves().resizable().scaledToFill().frame(width: 100, height: 60).clipped())
    print("I10 fill unclipped ink \(ink(i10)); .clipped() ink \(ink(i10c))")

    // Revision 2 (same design session): the separating arms the spec's rulings needed.
    // A — aspectRatio(nil) on a non-image: the ratio comes from the child's nil×nil answer.
    print("A1 Color.aspectRatio(contentMode: .fit) sizes: \(sizes(R.aspectRatio(contentMode: .fit)))")
    print("A2 Color.scaledToFill sizes: \(sizes(R.scaledToFill()))")
    print("A3 Color ideal 40x20 .aspectRatio(.fit) sizes: \(sizes(R.frame(idealWidth: 40, idealHeight: 20).aspectRatio(contentMode: .fit)))")
    print("A4 fixed 40x20 .aspectRatio(.fit) sizes: \(sizes(R.frame(width: 40, height: 20).aspectRatio(contentMode: .fit)))")
    // C8 — clipShape leaves layout alone.
    print("C8 layout clipShape(Circle): \(sizes(R.frame(width: 100, height: 60).clipShape(Circle())))")
    // I11 — .medium interpolation; I12 — a translucent image composites source-over.
    let i11 = render(twoPixels().resizable().interpolation(.medium).frame(width: 100, height: 10))
    print("I11 default vs .medium \(differing(i8, i11))px, .medium vs .high \(differing(i11, i8h))px")
    var half: [UInt8] = [128, 0, 0, 128]  // premultiplied red at alpha 0.5
    let hctx = CGContext(data: &half, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let i12 = render(Image(decorative: hctx.makeImage()!, scale: 1).resizable().frame(width: 20, height: 20))
    print("I12 half-alpha red over white: centre \(px(i12, 60, 50))")
    // K11 — strokeBorder wider than twice the radius: the outer corner.
    let k11 = render(RoundedRectangle(cornerRadius: 3, style: .circular).strokeBorder(R, lineWidth: 10).frame(width: 100, height: 60))
    let k11f = render(RoundedRectangle(cornerRadius: 3, style: .circular).fill(R).frame(width: 100, height: 60))
    print("K11 RR(3).strokeBorder(10) corner (0,0) \(px(k11, 50, 40)) vs RR(3) fill \(px(k11f, 50, 40)); outer-edge pixels differing from the fill's: \(differing(k11, k11f))px")
    let k12 = render(RoundedRectangle(cornerRadius: 3, style: .circular).stroke(R, lineWidth: 10).frame(width: 100, height: 60))
    print("K12 RR(3).stroke(10) corner (-5,-5) \(px(k12, 45, 35)) (-4,-4) \(px(k12, 46, 36))")
    print("done")
}
