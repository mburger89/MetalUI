// SwiftUI probe: paths, shadows and transforms (user request 2026-10-02, not
// a plan task; rulings GX-A onward in
// docs/superpowers/2026-10-02-paths-shadows-transforms-decisions.md, spec
// docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md).
//
// HOW TO RUN (compiled — the `/usr/bin/swift` JIT form fails to link on
// macOS 27, as the accessibility part-2 probe found):
//
//   xcrun swiftc docs/probes/swiftui-paths-shadows-transforms.swift -o /tmp/gx-probe
//   /tmp/gx-probe 2>&1 | grep -v 'Connection\]'
//
// It opens and orders out small windows (groups H, X, N). Run it with the
// screen UNLOCKED (the click harness needs a window server that delivers).
//
// INSTRUMENTS, each with a positive control in group P:
// - INK: `ImageRenderer` at scale 1 onto an opaque white 240×200 canvas, the
//   subject `fixedSize()` at (60, 50); boxes are reported RELATIVE to that
//   origin (`ink` any non-white pixel, `red`/`blue`/`black` exact colours),
//   plus single-pixel samples, also relative.
// - SIZES: a recording `Layout` that asks its one subview `sizeThatFits` at
//   five proposals (layout, independent of paint).
// - CLICKS: real `NSEvent`s sent into a 200×200 `NSWindow` hosting SwiftUI
//   (the content-shape probe's harness; window coordinates origin
//   BOTTOM-left). P3: a full-window tappable colour reads 1 at both points.
// - AX: a hosted `Button`'s `accessibilityFrame()`, relative to the window's
//   content rect, top-left origin (P4: an untransformed button's frame is its
//   layout frame).
// - ANIMATION: the transactions probe's recorder — a `CustomAnimation` that
//   records the TYPE and DELTA of every value SwiftUI animates (P5: a
//   `.frame(width:)` change records a geometry line; P6: no transaction
//   records nothing).
//
// SEPARATING ARMS are named in each group's comment.
//
// RECORDED 2026-10-02 by the paths/shadows/transforms design, macOS 27.0.1
// (26A434), Apple Swift 6.4 (swiftlang-6.4.0.33.1), screen UNLOCKED (lock
// probe: no CGSSessionScreenIsLocked line, `displayAsleep main: 0`). Compiled
// form, run twice, stdout byte-identical (120 lines), exit 0:
//
//   --- P: positive controls
//   P1 ink red 100x60: x0 y0 w100 h60 n6000 | 60x60: x0 y0 w60 h60 n3600 | empty: none
//   P2 sizes fixed 40x20: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   P2 sizes Color:       nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   P3 full-window tappable: (100,100) 1 (20,100) 1
//   P4 AX Button 100x40 centred, untransformed: x133.5 y138 w33 h24
//   P5 control: .frame(width: 100 + v) 0→100: P<P<F, F>, P<F, F>> [0.000, 0.000, 100.000, 0.000]
//   P6 control: same change, no transaction: (nothing animated)
//   --- PA: Path
//   PA1 Path(addRect 20,30 50x40) as a view in a 120x100 frame: x20 y30 w50 h40 n2000 red-default? (40,50)=(39,39,39)
//   PA1 sizes Path: nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   PA1b the same path in a 30x30 frame (not scaled to fit): x20 y30 w50 h40 n2000
//   PA2 same-direction rings: default (50,50)=(0,0,0) nonzero (50,50)=(0,0,0) evenOdd (50,50)=(255,255,255) ring (10,50)=(0,0,0)
//   PA2 reversed inner: nonzero (50,50)=(255,255,255) evenOdd (50,50)=(255,255,255)
//   PA3 addArc 0°→90° clockwise:false: below-right (70,70)=(0,0,0) above-right (70,30)=(255,255,255) ink x50 y50 w40 h40 n1289
//   PA3 addArc 0°→90° clockwise:true:  below-right (70,70)=(255,255,255) above-right (70,30)=(0,0,0) ink x10 y10 w80 h80 n3867
//   PA4 quad segment (0,100)-(50,0)-(100,100): dark area 3325.8 (analytic 3333.3) ink x0 y50 w100 h50 n3416
//   PA4 cubic (0,100)-(0,0)-(100,0)-(100,100): dark area 5977.3 (analytic 7500) ink x0 y25 w100 h75 n6088
//   PA5 addEllipse vs Ellipse(): 0px, dark area 4714.2 (analytic 4712.4)
//   PA5 addRoundedRect(cornerSize 20) vs RR(20,.circular): 196px vs RR(20) default: 0px
//   PA5 addRoundedRect(style: .continuous) vs RR(20) default: 0px
//   PA6 an open subpath fills as if closed: below-diagonal (80,20)=(0,0,0) above (20,80)=(255,255,255)
//   PA7 custom Shape path(in:) in 100x60: x0 y0 w100 h60 n3100 sizes nil×nil→10×10 100×60→100×60 0×0→0×0 inf×inf→inf×inf 100×nil→100×10
//   PA9 the rect a custom path(in:) receives (shape at 17,9 inside its parent): rect 0,0 50x30
//   PA8 bare Path view default fill (foreground): (40,50)=(39,39,39); .foregroundStyle(.red): (40,50)=(255,0,0)
//   --- ST: StrokeStyle
//   ST1 butt w10:   x20 y45 w60 h10 n600
//   ST2 round w10:  x14 y44 w72 h12 n696 corner (16,46)=(113,113,113)
//   ST3 square w10: x15 y45 w70 h10 n700 corner (16,46)=(0,0,0)
//   ST4 .stroke(Color) default: x20 y49 w60 h2 n120 | stroke(lineWidth: 10) == butt: 0px
//   ST5 V miter w10: x15 y7 w70 h85 n1670
//   ST5 V bevel w10: x15 y18 w70 h74 n1610
//   ST5 V round w10: x15 y15 w70 h77 n1634
//   ST5 default join == miter: 0px
//   ST6 sharp V w4 miterLimit default(10): x38 y-4 w24 h95 n798 limit 4: x38 y9 w24 h82 n758
//   ST7 dash [10,10] w4: [0…9] [20…29] [40…49] [60…69] [80…89]
//   ST7 dash [10,10] phase 5: [0…4] [15…24] [35…44] [55…64] [75…84] [95…99]
//   ST7 dash [10,5,2,5] w4: [0…9] [15…17] [22…31] [37…39] [44…53] [59…61] [66…75] [81…83] [88…97]
//   ST8 closed rect w10 corner (16,16): (16,16)=(0,0,0) | open (unclosed) start corner: (16,16)=(255,255,255)
//   ST9 Rectangle().stroke(style: round join) corner (-4,-4) of 100x60: (-4,-4)=(108,108,108) miter: (-4,-4)=(0,0,0)
//   ST10 stroke w0: none w-3: none
//   ST11 strokeBorder(style:) on Circle 60 w10: x0 y0 w60 h60 n1011
//   --- SH: shadow
//   SH0 control, no shadow: x0 y0 w40 h40 n1600 red x0 y0 w40 h40 n1600
//   SH1 shadow(black, r0, 10, 10): ink x0 y0 w51 h51 n2303 black x10 y10 w40 h40 n700 (45,45)=(0,0,0)
//   SH2 default colour, r0: (45,45)=(171,171,171) (45,15)=(171,171,171)
//   SH3 r10 x0 y0: ink x-24 y-24 w88 h88 n6140; row y20 from x40: 36:255 38:255 40:132 42:152 44:170 46:188 48:203 50:217 52:228 54:237 56:244 58:249 60:252 62:254 64:255 66:255 68:255 70:255
//   SH3b r4: ink x-9 y-9 w58 h58 n3180; row y20: 36:255 37:255 38:255 39:255 40:140 41:163 42:186 43:205 44:221 45:234 46:243 47:250 48:253 49:255 50:255 51:255 52:255 53:255 54:255 55:255 56:255
//   SH3c 4x4 square r6, row y32 (through centre): 18:253 20:250 22:244 24:235 26:224 28:211 30:255 32:255 34:204 36:217 38:229 40:240 42:247 44:252 46:254
//   SH4 Text shadow: red x3 y11 w45 h35 n452 black x6 y14 w45 h35 n251 | unshadowed red x3 y11 w45 h35 n452 ink x2 y10 w47 h37 n775
//   SH5 overlapping ZStack, shadow on the stack: (65,65)=(0,0,0) (black = per child, blue = composited) (95,95)=(0,0,0)
//   SH5c same, .compositingGroup().shadow: (65,65)=(0,0,255) (95,95)=(0,0,0)
//   SH5d VStack of two: black x5 y5 w40 h50 n544 (42,22)=(0,0,0) (42,52)=(0,0,0)
//   SH5e Text on a white background, shadowed: black x4 y4 w59 h55 n600
//   SH6 opacity(0.5) inside shadow: shadow-only (45,45)=(128,128,128) content-only (5,5)=(255,128,128)
//   SH6b opacity(0.5) outside: shadow-only (45,45)=(128,128,128) content-only (5,5)=(255,128,128)
//   SH7 shadow then clipped(): ink x0 y0 w40 h40 n1600
//   SH7b clipped content shadowed: black x10 y10 w40 h40 n700
//   SH8 sizes shadowed fixed 40x20: nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   SH9 stroked circle shadowed: centre (30,30)=(255,255,255) black x2 y2 w63 h63 n312
//   SH10 negative offset: black x-10 y-10 w40 h40 n700
//   SH11 two shadows: black x40 y0 w10 h40 n399 blue x0 y40 w50 h10 n500 (45,5)=(0,0,0) (45,45)=(0,0,255)
//   SH12 triangle path shadowed: black x10 y10 w39 h39 n570 (35,35)=(255,255,255)
//   SH13 shadow colour opacity 0.5: (45,45)=(128,128,128)
//   --- T: rotationEffect / scaleEffect / offset
//   T0 bar control: x0 y0 w100 h20 n2000
//   T1 rotationEffect(45°): x7 y-33 w86 h86 n2216 sizes nil×nil→100×20 100×60→100×20 0×0→100×20 inf×inf→100×20 100×nil→100×20
//   T1b rotationEffect(90°): x39 y-41 w22 h102 n2004 red x40 y-40 w20 h100 n2000
//   T2 rotationEffect(90°, anchor: .topLeading): x-21 y-1 w22 h102 n2004
//   T2b rotationEffect(-90°): x40 y-40 w20 h100 n2000
//   T3 scaleEffect(2): x-20 y-10 w80 h40 n3200 sizes nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   T3b scaleEffect(2, anchor: .topLeading): x0 y0 w80 h40 n3200
//   T4 scaleEffect(x: 2, y: 0.5): x-20 y5 w80 h10 n800
//   T4b scaleEffect(CGSize(2, 0.5)) == x:y: 0px
//   T5 halves scaleEffect(x: -1): red x20 y0 w20 h20 n400 blue x0 y0 w20 h20 n400
//   T5b scaleEffect(0): none
//   T6 offset(x: 30, y: 10): x30 y10 w40 h20 n800 sizes nil×nil→40×20 100×60→40×20 0×0→40×20 inf×inf→40×20 100×nil→40×20
//   T6b offset in an HStack: red x0 y30 w40 h20 n800 blue x40 y0 w40 h20 n800
//   T6c offset(CGSize(30,10)) == offset(x:y:): 0px
//   T7 clipped() then rotationEffect(90°): x20 y-20 w20 h60 n1200 
//   T7b rotationEffect(90°) then clipped(): x40 y0 w20 h20 n400
//   T8 background(blue) then rotationEffect(90°): blue x10 y-10 w30 h50 n700 | rotation then background: blue x0 y0 w40 h20 n400
//   T9 Text rotated 90°: ink x15 y-9 w16 h44 n375 | unrotated ink x1 y4 w44 h16 n376
//   T10 shadow(x10) then rotationEffect(90°): black x10 y30 w20 h10 n200 | rotation then shadow: black x30 y-10 w10 h40 n400
//   T11 rotation 45° then offset(30,0): x37 y-33 w86 h86 n2216 | offset then rotation: x29 y-11 w86 h86 n2228
//   T12 rotated square edge AA (partial pixels): x-8 y-8 w56 h56 n204 ink x-8 y-8 w56 h56 n1704 red x-6 y-6 w52 h52 n1500
//   T14 shadow(x10) then scaleEffect(2): black x60 y-10 w20 h40 n800
//   T15 Text(20pt).scaleEffect(2) vs Text(40pt): 499px differ; grey levels in scaled 126 vs big 123
//   T15b scaled vs a bilinear 2x upscale of the 20pt raster: 1444px differ; partial pixels: scaled 326 upscale 1237 40pt 298
//   T16 a 1pt diagonal Path scaled 4x: partial-coverage pixels x-2 y-2 w44 h44 n166 solid x0 y0 w40 h40 n118
//   T13 opacity(0.5) then rotation: (20,10)=(255,128,128)
//   --- H: hit testing
//   H1 160x20 bar rotated 90°, tap: (100,100) 1 (100,40) 1 (40,100) 0
//   H1c the same bar unrotated (control): (100,100) 1 (100,40) 0 (40,100) 1
//   H1b tap written AFTER rotationEffect: (100,40) 1 (40,100) 0
//   H2 160x160 scaleEffect(0.5): (100,100) 1 (30,100) 0
//   H3 60x60 scaleEffect(2): (100,100) 1 (50,100) 1
//   H4 60x60 offset(x: 60): (160,100) 1 (80,100) 0
//   H5 60x60 shadow(r0, 40, 40) — shadow-only point: (100,100) 1 (150,150) 0
//   H6 Button 100x30 rotated 90°: (100,40) 1 (40,100) 0
//   H7 square 80x80 rotated 45°: a corner of the frame / a diamond tip: (65,65) 0 (100,48) 1
//   --- X: accessibilityFrame
//   X1 offset(x: 50, y: 20): x183.5 y158 w33 h24
//   X2 rotationEffect(90°): x138 y133.5 w24 h33
//   X3 rotationEffect(45°): x132.321 y132.321 w35.358 h35.358
//   X4 scaleEffect(2): x117 y126 w66 h48
//   X5 scaleEffect(0.5, anchor: .topLeading): x116.75 y134 w16.5 h12
//   X6 shadow(r10, 30, 30): x133.5 y138 w33 h24
//   --- N: animation
//   N1 rotationEffect(.degrees(v)) 0→90: P<Double, P<F, F>> [201.062, 0.000, 0.000]
//   N2 scaleEffect(1 + v) 0→1: P<P<F, F>, P<F, F>> [1.000, 1.000, 0.000, 0.000]
//   N2b scaleEffect(x: 1 + v, y: 1): P<P<F, F>, P<F, F>> [1.000, 0.000, 0.000, 0.000]
//   N3 offset(x: v) 0→40: P<P<F, F>, P<F, F>> [40.000, 0.000, 0.000, 0.000]
//   N4 shadow radius 0→10: P<P<Float, P<Float, P<Float, Float>>>, P<F, P<F, F>>> [0.000, 0.000, 0.000, 0.000, 10.000, 0.000, 0.000]
//   N5 shadow x 0→10: P<P<Float, P<Float, P<Float, Float>>>, P<F, P<F, F>>> [0.000, 0.000, 0.000, 0.000, 0.000, 10.000, 0.000]
//   N6 shadow colour black→blue: P<P<Float, P<Float, P<Float, Float>>>, P<F, P<F, F>>> [47.606, 60.843, 109.728, 0.000, 0.000, 0.000, 0.000]
//   N7 Path view whose rect grows 20→60: (nothing animated)
//   N8 Rectangle().stroke(lineWidth: 1 + v) 0→5: P<EmptyAnimatableData, P<F, P<F, F>>> [5.000, 0.000, 0.000]
//   N9 rotationEffect anchor .center→.topLeading: P<Double, P<F, F>> [0.000, -64.000, -64.000]
//   N10 Path.trimmedPath(from: 0, to: 0.2 + v): P<P<EmptyAnimatableData, P<F, F>>, P<F, P<F, F>>> [0.000, 76.800, 0.000, 0.000, 0.000]
//
// READING (rulings GX-A onward; the decisions doc has each in full):
// - PATH. A `Path` view answers its proposal (nil → 10, PA1 sizes) and draws
//   at its own coordinates from the view's origin, neither scaled to nor
//   clipped by its frame (PA1, PA1b). Fill rules: the default is nonzero;
//   even-odd empties a same-direction inner ring; a reversed inner ring is a
//   hole under both (PA2). `addArc(clockwise: false)` from 0° to 90° sweeps
//   through the BELOW-right quadrant — SwiftUI's flag is in y-up terms, so in
//   y-down screen space `clockwise: false` is the visually clockwise sweep
//   (PA3). Curves are exact to coverage (PA4: 3325.8 of 3333.3), an open
//   subpath fills as if closed (PA6), `addEllipse` equals `Ellipse()` (PA5),
//   `addRoundedRect`'s default style is `.continuous` (PA5). A custom shape's
//   `path(in:)` receives its LOCAL rect, origin (0, 0) (PA9). A bare Path fills
//   with the foreground style (PA8).
// - STROKE. Caps: butt ends at the endpoint, round/square extend w/2 (ST1–3);
//   `.stroke(Color)` is width 1 (ST4); default join is miter (ST5) with limit
//   10 (ST6: a ratio-8.06 corner mitres at 10, bevels at 4); dash/phase walk
//   the arc length (ST7); a closed subpath joins at its start, an open one
//   caps there (ST8); a width <= 0 draws nothing (ST10); `strokeBorder(style:)`
//   takes the style too (ST11).
// - SHADOW. Drawn per LEAF, not composited: in an overlapping ZStack the top
//   child's shadow falls on the child below it (SH5 black at (65,65));
//   `compositingGroup()` composites (SH5c); text glyphs and a stroked ring
//   cast glyph- and ring-shaped shadows (SH4, SH9, SH5e: a text's shadow is
//   visible on its own background). Default colour is black at 0.33 (SH2:
//   171). The blur is Gaussian with sigma == radius (SH3/SH3b fitted: rms 3.5
//   and 1.6 grey levels at sigma/radius 1.02 and 1.00; the far tail is cut at
//   about 2.4 sigma). The shadow follows the content's alpha (SH6), is cut by a
//   clip outside it (SH7) and follows a clip inside it (SH7b), never changes
//   layout (SH8), never hits (H5) and changes no accessibility frame (X6). A
//   second `.shadow` shadows the first one's shadow too (SH11). Offsets may be
//   negative (SH10); a colour's own opacity multiplies (SH13).
// - TRANSFORMS. `rotationEffect`/`scaleEffect`/`offset` change paint and not
//   layout (T1/T3/T6 sizes, T6b sibling unmoved). Positive degrees rotate
//   visually clockwise about `anchor`, default `.center` (T1, T2, T2b).
//   `scaleEffect(x:y:)` equals the `CGSize` form (T4b), a negative factor
//   flips (T5), zero draws nothing (T5b). Modifier order composes as a
//   transform stack: a clip inside a rotation rotates with it, one outside
//   stays axis-aligned (T7, T7b); a background inside rotates, one outside
//   does not (T8); a shadow inside a rotation has its offset rotated, one
//   outside does not (T10); a shadow inside a scale has its offset scaled
//   (T14); offset/rotation order matters (T11). Text rotates legibly (T9).
//   Under `scaleEffect` text and paths are RE-RASTERIZED, not resampled: a
//   20 pt text scaled 2× has 326 partial pixels, a 40 pt text 298, a bilinear
//   upscale of the 20 pt raster 1237 (T15b); a 1 pt diagonal scaled 4× has 118
//   solid pixels, impossible for a resampled 1 px line (T16).
// - HIT TESTING follows every transform: a rotated bar is hit where it is
//   drawn and missed where its layout frame was (H1, H1b, H6), a rotated
//   square's frame corner misses and its diamond tip hits (H7), scale and
//   offset move the region (H2–H4). A shadow never hits (H5).
// - ACCESSIBILITY frames follow offset, scale and right-angle rotation as the
//   transformed frame's bounding box (X1, X2, X4, X5); a 45° rotation reports
//   a 35.36-point square where the bounding box of the 33×24 label is 40.31
//   (X3, unexplained).
// - ANIMATION. Rotation animates its angle and its anchor (N1, N9); scale its
//   two factors and anchor (N2, N2b); offset its two components (N3); shadow
//   its colour, radius and offset together (N4–N6). A `Path` view whose path
//   changes animates nothing (N7). `.stroke(lineWidth:)` animates (N8) and
//   `trim` animates (N10) — both outside this design (spec §9).

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

// Exact probe colours: SwiftUI's `Color.red`/`.blue` are the system palette
// ((255,56,60)/(0,136,255) here), which the exact-colour boxes cannot see.
extension Color {
    static let pr = Color(.sRGB, red: 1, green: 0, blue: 0)
    static let pb = Color(.sRGB, red: 0, green: 0, blue: 1)
}

// ---------------------------------------------------------------- ink
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

/// The subject placed at (60, 50) on a white canvas — by a `.position`-free
/// padding, so the instrument itself uses no transform under test.
@MainActor func render(_ v: some View) -> Bitmap {
    let c = ZStack(alignment: .topLeading) {
        Color.white
        v.fixedSize().padding(.leading, CGFloat(ox)).padding(.top, CGFloat(oy))
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
func bbox(_ b: Bitmap, _ pred: (UInt8, UInt8, UInt8) -> Bool) -> String {
    var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, n = 0
    for y in 0..<b.h { for x in 0..<b.w {
        let i = (y * b.w + x) * 4
        if pred(b.bytes[i], b.bytes[i + 1], b.bytes[i + 2]) {
            x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y); n += 1
        }
    } }
    if n == 0 { return "none" }
    return "x\(x0 - ox) y\(y0 - oy) w\(x1 - x0 + 1) h\(y1 - y0 + 1) n\(n)"
}
func ink(_ b: Bitmap) -> String { bbox(b) { r, g, bl in !(r == 255 && g == 255 && bl == 255) } }
func red(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 255 && g == 0 && bl == 0 } }
func blue(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 0 && g == 0 && bl == 255 } }
func black(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == 0 && g == 0 && bl == 0 } }
func grey(_ b: Bitmap) -> String { bbox(b) { r, g, bl in r == g && g == bl && r < 255 } }
/// Antialiased edge pixels of a pure-red subject: neither white nor exact red.
func partial(_ b: Bitmap) -> String { bbox(b) { r, g, bl in !(r == 255 && g == 255 && bl == 255) && !(r == 255 && g == 0 && bl == 0) } }
/// Coverage-weighted area of "not white" (1 − red channel / 255 for a red-free
/// colour — subjects here are black on white).
func darkArea(_ b: Bitmap) -> Double {
    var s = 0.0
    for i in stride(from: 0, to: b.bytes.count, by: 4) { s += 1 - Double(b.bytes[i]) / 255 }
    return (s * 10).rounded() / 10
}
func differing(_ a: Bitmap, _ b: Bitmap) -> Int {
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}
/// Ink runs along row `y` (relative): "[x0…x1] [x0…x1]".
func runs(_ b: Bitmap, y: Int, from: Int, to: Int) -> String {
    var out: [String] = [], start: Int?
    for x in from...to {
        let (r, g, bl) = rgb(b, x, y)
        let on = !(r == 255 && g == 255 && bl == 255)
        if on, start == nil { start = x }
        if !on, let s = start { out.append("[\(s)…\(x - 1)]"); start = nil }
    }
    if let s = start { out.append("[\(s)…\(to)]") }
    return out.isEmpty ? "none" : out.joined(separator: " ")
}

func fmt(_ v: CGFloat) -> String {
    if v == .infinity { return "inf" }
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

// ---------------------------------------------------------------- sizes
nonisolated(unsafe) var recorded: [String] = []
struct SizeProbe: Layout {
    static let proposals: [(String, ProposedViewSize)] = [
        ("nil×nil", .unspecified), ("100×60", ProposedViewSize(width: 100, height: 60)),
        ("0×0", .zero), ("inf×inf", .infinity), ("100×nil", ProposedViewSize(width: 100, height: nil))]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        recorded.append(Self.proposals.map { label, p in
            let s = subviews[0].sizeThatFits(p); return "\(label)→\(fmt(s.width))×\(fmt(s.height))"
        }.joined(separator: " "))
        return CGSize(width: 10, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
    }
}
@MainActor func sizes(_ v: some View) -> String {
    recorded = []; _ = render(SizeProbe { v }); return recorded.first ?? "none"
}

// ---------------------------------------------------------------- clicks
final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
enum Count {
    nonisolated(unsafe) static var hits = 0
    static func take() -> Int { let v = hits; hits = 0; return v }
}
@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
@MainActor func window<V: View>(_ view: V, size: CGFloat = 200) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: size, height: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.contentView = FirstMouseHost(rootView: view)
    w.makeKeyAndOrderFront(nil)
    spin()
    return w
}
@MainActor func click(_ w: NSWindow, at p: CGPoint) {
    func ev(_ t: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: t, location: p, modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                           clickCount: 1, pressure: t == .leftMouseDown ? 1 : 0)!
    }
    w.sendEvent(ev(.leftMouseDown)); spin(0.05)
    w.sendEvent(ev(.leftMouseUp)); spin()
}
/// Each point in a fresh window. Points are given TOP-left (like the ink
/// instrument) and flipped here.
@MainActor func hits<V: View>(_ label: String, _ points: [(Int, Int)], _ make: @escaping () -> V) {
    var parts: [String] = []
    for (x, y) in points {
        _ = Count.take()
        let w = window(make())
        click(w, at: CGPoint(x: x, y: 200 - y))
        parts.append("(\(x),\(y)) \(Count.take())")
        w.orderOut(nil)
    }
    print("\(label): " + parts.joined(separator: " "))
}
@MainActor func tappable(_ c: Color = .pb) -> some View {
    c.onTapGesture { Count.hits += 1 }
}

// ---------------------------------------------------------------- AX
func kv(_ o: NSObject, _ key: String) -> Any? {
    guard o.responds(to: Selector(key)) else { return nil }
    return o.value(forKey: key)
}
@MainActor func kids(_ o: NSObject) -> [NSObject] {
    ((kv(o, "accessibilityChildren") as? [Any]) ?? []).compactMap { $0 as? NSObject }
}
@MainActor func find(_ o: NSObject, role: String) -> NSObject? {
    if (kv(o, "accessibilityRole") as? String) == role { return o }
    for k in kids(o) { if let f = find(k, role: role) { return f } }
    return nil
}
@MainActor func axFrame<V: View>(_ label: String, _ v: V) {
    let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 300, height: 300),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v.frame(width: 300, height: 300))
    w.contentView = h
    w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.4)
    let content = w.convertToScreen(h.frame)
    if let b = find(h, role: "AXButton"), let f = kv(b, "accessibilityFrame") as? NSRect {
        let x = f.minX - content.minX, y = content.maxY - f.maxY
        print("\(label): x\(fmt(x)) y\(fmt(y)) w\(fmt(f.width)) h\(fmt(f.height))")
    } else {
        print("\(label): no button")
    }
    w.orderOut(nil)
}

// ---------------------------------------------------------------- animation recorder
nonisolated(unsafe) var seen: Set<String> = []
struct Rec: CustomAnimation {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        seen.insert("\(short(V.self)) \(nums(value))")
        if time > 0.15 { return nil }
        return value.scaled(by: time / 0.15)
    }
}
func nums<V>(_ v: V) -> String {
    let s = String(describing: v)
    let colour = s.contains("Resolved") ? "colour " : ""
    let re = try! NSRegularExpression(pattern: "-?[0-9]+\\.[0-9]+(e-?[0-9]+)?")
    let ns = re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m -> String in
        let d = Double(String(s[Range(m.range, in: s)!]))!
        return String(format: "%.3f", abs(d) < 0.0005 ? 0 : d)
    }
    return colour + "[" + ns.joined(separator: ", ") + "]"
}
func short(_ t: Any.Type) -> String {
    let s = String(describing: t)
    if s.contains("KeyedAnimatableArray") || s.contains("ResolvedShadow") { return s.contains("Shadow") ? "Shadow" : "ShapeStyle" }
    return s.replacingOccurrences(of: "AnimatablePair", with: "P").replacingOccurrences(of: "CGFloat", with: "F")
}
let A = Animation(Rec())
@MainActor final class M: ObservableObject { @Published var v = 0.0 }
struct Root<C: View>: View { @ObservedObject var m: M; let c: (M) -> C
    var body: some View { ZStack(alignment: .topLeading) { c(m) }.frame(width: 300, height: 200, alignment: .topLeading) } }
@MainActor func anim<C: View>(_ name: String, to target: Double, animated: Bool = true, _ content: @escaping (M) -> C) {
    let m = M()
    let host = NSHostingView(rootView: Root(m: m, c: content))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled],
                       backing: .buffered, defer: false)
    win.isReleasedWhenClosed = false
    win.contentView = host; win.orderFrontRegardless(); spin(0.25)
    seen.removeAll()
    if animated { withAnimation(A) { m.v = target } } else { m.v = target }
    spin(0.5)
    print("\(name): " + (seen.isEmpty ? "(nothing animated)" : seen.sorted().joined(separator: " | ")))
    win.orderOut(nil); win.contentView = nil; spin(0.05)
}

// ---------------------------------------------------------------- helpers
func pathView(_ build: @escaping (inout Path) -> Void) -> Path { Path { p in build(&p) } }
func vShape(tipY: CGFloat, half: CGFloat) -> Path {
    Path { p in p.move(to: CGPoint(x: 50 - half, y: 90)); p.addLine(to: CGPoint(x: 50, y: tipY))
        p.addLine(to: CGPoint(x: 50 + half, y: 90)) }
}
func line(_ x0: CGFloat, _ x1: CGFloat, y: CGFloat) -> Path {
    Path { p in p.move(to: CGPoint(x: x0, y: y)); p.addLine(to: CGPoint(x: x1, y: y)) }
}
/// A left-red / right-blue 40×20 block, to see a flip.
func halvesBlock() -> some View {
    HStack(spacing: 0) { Color.pr.frame(width: 20, height: 20); Color.pb.frame(width: 20, height: 20) }
}

// ---------------------------------------------------------------- arms
MainActor.assumeIsolated {
NSApplication.shared.setActivationPolicy(.accessory)
// SwiftUI publishes its NSAccessibility children only once a client is
// present; AXEnhancedUserInterface stands in for one (the accessibility
// part-2 probe's activation).
NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))

print("--- P: positive controls")
do {
    let a = render(Color.pr.frame(width: 100, height: 60)), b = render(Color.pr.frame(width: 60, height: 60))
    print("P1 ink red 100x60: \(red(a)) | 60x60: \(red(b)) | empty: \(ink(render(Color.clear.frame(width: 10, height: 10))))")
    print("P2 sizes fixed 40x20: \(sizes(Color.pr.frame(width: 40, height: 20)))")
    print("P2 sizes Color:       \(sizes(Color.pr))")
}
hits("P3 full-window tappable", [(100, 100), (20, 100)]) { tappable() }
axFrame("P4 AX Button 100x40 centred, untransformed", Button("A") {}.frame(width: 100, height: 40))
anim("P5 control: .frame(width: 100 + v) 0→100", to: 100) { m in Color.pr.frame(width: 100 + m.v, height: 20) }
anim("P6 control: same change, no transaction", to: 100, animated: false) { m in Color.pr.frame(width: 100 + m.v, height: 20) }

// PA: Path as a view and as a fill. Separating arms: PA2's two fill rules
// (centre pixel differs), PA3's two arc directions (quadrant differs).
print("--- PA: Path")
do {
    let rect = pathView { $0.addRect(CGRect(x: 20, y: 30, width: 50, height: 40)) }
    print("PA1 Path(addRect 20,30 50x40) as a view in a 120x100 frame: \(ink(render(rect.frame(width: 120, height: 100)))) red-default? \(px(render(rect.frame(width: 120, height: 100)), 40, 50))")
    print("PA1 sizes Path: \(sizes(rect))")
    print("PA1b the same path in a 30x30 frame (not scaled to fit): \(ink(render(rect.frame(width: 30, height: 30))))")
    let rings = pathView { p in
        p.addRect(CGRect(x: 0, y: 0, width: 100, height: 100)); p.addRect(CGRect(x: 25, y: 25, width: 50, height: 50))
    }
    let reversed = pathView { p in
        p.addRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        p.move(to: CGPoint(x: 25, y: 25)); p.addLine(to: CGPoint(x: 25, y: 75))
        p.addLine(to: CGPoint(x: 75, y: 75)); p.addLine(to: CGPoint(x: 75, y: 25)); p.closeSubpath()
    }
    @MainActor func fr(_ p: Path, _ eo: Bool?) -> Bitmap {
        let v: AnyView = eo == nil ? AnyView(p.fill(Color.black)) : AnyView(p.fill(Color.black, style: FillStyle(eoFill: eo!)))
        return render(v.frame(width: 100, height: 100))
    }
    print("PA2 same-direction rings: default \(px(fr(rings, nil), 50, 50)) nonzero \(px(fr(rings, false), 50, 50)) evenOdd \(px(fr(rings, true), 50, 50)) ring \(px(fr(rings, true), 10, 50))")
    print("PA2 reversed inner: nonzero \(px(fr(reversed, false), 50, 50)) evenOdd \(px(fr(reversed, true), 50, 50))")
    @MainActor func pie(_ cw: Bool) -> Bitmap {
        render(Path { p in p.move(to: CGPoint(x: 50, y: 50))
            p.addArc(center: CGPoint(x: 50, y: 50), radius: 40, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: cw)
            p.closeSubpath() }.fill(Color.black).frame(width: 100, height: 100))
    }
    print("PA3 addArc 0°→90° clockwise:false: below-right \(px(pie(false), 70, 70)) above-right \(px(pie(false), 70, 30)) ink \(ink(pie(false)))")
    print("PA3 addArc 0°→90° clockwise:true:  below-right \(px(pie(true), 70, 70)) above-right \(px(pie(true), 70, 30)) ink \(ink(pie(true)))")
    let quad = render(Path { p in p.move(to: CGPoint(x: 0, y: 100)); p.addQuadCurve(to: CGPoint(x: 100, y: 100), control: CGPoint(x: 50, y: 0)); p.closeSubpath() }.fill(Color.black).frame(width: 100, height: 100))
    print("PA4 quad segment (0,100)-(50,0)-(100,100): dark area \(darkArea(quad)) (analytic 3333.3) ink \(ink(quad))")
    let cubic = render(Path { p in p.move(to: CGPoint(x: 0, y: 100)); p.addCurve(to: CGPoint(x: 100, y: 100), control1: CGPoint(x: 0, y: 0), control2: CGPoint(x: 100, y: 0)); p.closeSubpath() }.fill(Color.black).frame(width: 100, height: 100))
    print("PA4 cubic (0,100)-(0,0)-(100,0)-(100,100): dark area \(darkArea(cubic)) (analytic 7500) ink \(ink(cubic))")
    let ell = render(pathView { $0.addEllipse(in: CGRect(x: 0, y: 0, width: 100, height: 60)) }.fill(Color.black).frame(width: 100, height: 60))
    let ellShape = render(Ellipse().fill(Color.black).frame(width: 100, height: 60))
    print("PA5 addEllipse vs Ellipse(): \(differing(ell, ellShape))px, dark area \(darkArea(ell)) (analytic 4712.4)")
    let rr = render(pathView { $0.addRoundedRect(in: CGRect(x: 0, y: 0, width: 100, height: 60), cornerSize: CGSize(width: 20, height: 20)) }.fill(Color.black).frame(width: 100, height: 60))
    let rrC = render(RoundedRectangle(cornerRadius: 20, style: .circular).fill(Color.black).frame(width: 100, height: 60))
    let rrK = render(RoundedRectangle(cornerRadius: 20).fill(Color.black).frame(width: 100, height: 60))
    print("PA5 addRoundedRect(cornerSize 20) vs RR(20,.circular): \(differing(rr, rrC))px vs RR(20) default: \(differing(rr, rrK))px")
    let rrS = render(pathView { $0.addRoundedRect(in: CGRect(x: 0, y: 0, width: 100, height: 60), cornerSize: CGSize(width: 20, height: 20), style: .continuous) }.fill(Color.black).frame(width: 100, height: 60))
    print("PA5 addRoundedRect(style: .continuous) vs RR(20) default: \(differing(rrS, rrK))px")
    let open = render(Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 100, y: 0)); p.addLine(to: CGPoint(x: 100, y: 100)) }.fill(Color.black).frame(width: 100, height: 100))
    print("PA6 an open subpath fills as if closed: below-diagonal \(px(open, 80, 20)) above \(px(open, 20, 80))")
    struct Tri: Shape { func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.closeSubpath() } } }
    print("PA7 custom Shape path(in:) in 100x60: \(ink(render(Tri().fill(Color.black).frame(width: 100, height: 60)))) sizes \(sizes(Tri()))")
    struct RecShape: Shape { func path(in r: CGRect) -> Path { recorded.append("rect \(fmt(r.minX)),\(fmt(r.minY)) \(fmt(r.width))x\(fmt(r.height))"); return Path(r) } }
    recorded = []; _ = render(RecShape().fill(Color.black).frame(width: 50, height: 30).padding(.leading, 17).padding(.top, 9))
    print("PA9 the rect a custom path(in:) receives (shape at 17,9 inside its parent): \(Set(recorded).sorted().joined(separator: " ; "))")
    print("PA8 bare Path view default fill (foreground): \(px(render(rect.frame(width: 120, height: 100)), 40, 50)); .foregroundStyle(.red): \(px(render(rect.foregroundStyle(Color.pr).frame(width: 120, height: 100)), 40, 50))")
}

// ST: strokes. Separating arms: ST1–ST3 caps (end extent differs), ST5 joins
// (tip extent differs), ST6 miter limit (miter vs bevel at one angle).
print("--- ST: StrokeStyle")
do {
    @MainActor func st(_ p: Path, _ s: StrokeStyle) -> Bitmap { render(p.stroke(Color.black, style: s).frame(width: 100, height: 100)) }
    let l = line(20, 80, y: 50)
    print("ST1 butt w10:   \(ink(st(l, StrokeStyle(lineWidth: 10, lineCap: .butt))))")
    print("ST2 round w10:  \(ink(st(l, StrokeStyle(lineWidth: 10, lineCap: .round)))) corner \(px(st(l, StrokeStyle(lineWidth: 10, lineCap: .round)), 16, 46))")
    print("ST3 square w10: \(ink(st(l, StrokeStyle(lineWidth: 10, lineCap: .square)))) corner \(px(st(l, StrokeStyle(lineWidth: 10, lineCap: .square)), 16, 46))")
    print("ST4 .stroke(Color) default: \(ink(render(l.stroke(Color.black).frame(width: 100, height: 100)))) | stroke(lineWidth: 10) == butt: \(differing(render(l.stroke(Color.black, lineWidth: 10).frame(width: 100, height: 100)), st(l, StrokeStyle(lineWidth: 10))))px")
    let v = vShape(tipY: 20, half: 30)
    print("ST5 V miter w10: \(ink(st(v, StrokeStyle(lineWidth: 10, lineJoin: .miter))))")
    print("ST5 V bevel w10: \(ink(st(v, StrokeStyle(lineWidth: 10, lineJoin: .bevel))))")
    print("ST5 V round w10: \(ink(st(v, StrokeStyle(lineWidth: 10, lineJoin: .round))))")
    print("ST5 default join == miter: \(differing(st(v, StrokeStyle(lineWidth: 10)), st(v, StrokeStyle(lineWidth: 10, lineJoin: .miter))))px")
    let sharp = vShape(tipY: 10, half: 10) // half-angle atan(10/80) = 7.1°, miter ratio 8.06
    print("ST6 sharp V w4 miterLimit default(10): \(ink(st(sharp, StrokeStyle(lineWidth: 4)))) limit 4: \(ink(st(sharp, StrokeStyle(lineWidth: 4, miterLimit: 4))))")
    let longLine = line(0, 100, y: 50)
    print("ST7 dash [10,10] w4: \(runs(st(longLine, StrokeStyle(lineWidth: 4, dash: [10, 10])), y: 50, from: 0, to: 99))")
    print("ST7 dash [10,10] phase 5: \(runs(st(longLine, StrokeStyle(lineWidth: 4, dash: [10, 10], dashPhase: 5)), y: 50, from: 0, to: 99))")
    print("ST7 dash [10,5,2,5] w4: \(runs(st(longLine, StrokeStyle(lineWidth: 4, dash: [10, 5, 2, 5])), y: 50, from: 0, to: 99))")
    let box = pathView { $0.addRect(CGRect(x: 20, y: 20, width: 60, height: 60)) }
    let openBox = Path { p in p.move(to: CGPoint(x: 20, y: 20)); p.addLine(to: CGPoint(x: 80, y: 20)); p.addLine(to: CGPoint(x: 80, y: 80)); p.addLine(to: CGPoint(x: 20, y: 80)); p.addLine(to: CGPoint(x: 20, y: 20)) }
    print("ST8 closed rect w10 corner (16,16): \(px(st(box, StrokeStyle(lineWidth: 10)), 16, 16)) | open (unclosed) start corner: \(px(st(openBox, StrokeStyle(lineWidth: 10)), 16, 16))")
    print("ST9 Rectangle().stroke(style: round join) corner (-4,-4) of 100x60: \(px(render(Rectangle().stroke(Color.black, style: StrokeStyle(lineWidth: 10, lineJoin: .round)).frame(width: 100, height: 60)), -4, -4)) miter: \(px(render(Rectangle().stroke(Color.black, style: StrokeStyle(lineWidth: 10)).frame(width: 100, height: 60)), -4, -4))")
    print("ST10 stroke w0: \(ink(st(l, StrokeStyle(lineWidth: 0)))) w-3: \(ink(st(l, StrokeStyle(lineWidth: -3))))")
    print("ST11 strokeBorder(style:) on Circle 60 w10: \(ink(render(Circle().strokeBorder(Color.black, style: StrokeStyle(lineWidth: 10, dash: [8, 8])).frame(width: 60, height: 60))))")
}

// SH: shadows. Separating arms: SH5 (per-child vs composited: one pixel where
// the two models disagree, with SH5c `compositingGroup()` as the composited
// control), SH6/SH6b (shadow alpha follows the content's alpha or not).
print("--- SH: shadow")
do {
    let sq = Color.pr.frame(width: 40, height: 40)
    print("SH0 control, no shadow: \(ink(render(sq))) red \(red(render(sq)))")
    let s1 = render(sq.shadow(color: .black, radius: 0, x: 10, y: 10))
    print("SH1 shadow(black, r0, 10, 10): ink \(ink(s1)) black \(black(s1)) \(px(s1, 45, 45))")
    let s2 = render(sq.shadow(radius: 0, x: 10, y: 10))
    print("SH2 default colour, r0: \(px(s2, 45, 45)) \(px(s2, 45, 15))")
    let s3 = render(sq.shadow(color: .black, radius: 10, x: 0, y: 0))
    print("SH3 r10 x0 y0: ink \(ink(s3)); row y20 from x40: " + stride(from: 36, through: 70, by: 2).map { x in "\(x):\(rgb(s3, x, 20).0)" }.joined(separator: " "))
    let s3b = render(sq.shadow(color: .black, radius: 4, x: 0, y: 0))
    print("SH3b r4: ink \(ink(s3b)); row y20: " + stride(from: 36, through: 56, by: 1).map { x in "\(x):\(rgb(s3b, x, 20).0)" }.joined(separator: " "))
    let s3c = render(Color.pr.frame(width: 4, height: 4).padding(30).shadow(color: .black, radius: 6, x: 0, y: 0))
    print("SH3c 4x4 square r6, row y32 (through centre): " + stride(from: 18, through: 46, by: 2).map { x in "\(x):\(rgb(s3c, x, 32).0)" }.joined(separator: " "))
    let t = render(Text("Hg").font(.system(size: 40)).foregroundStyle(Color.pr).shadow(color: .black, radius: 0, x: 3, y: 3))
    let t0 = render(Text("Hg").font(.system(size: 40)).foregroundStyle(Color.pr))
    print("SH4 Text shadow: red \(red(t)) black \(black(t)) | unshadowed red \(red(t0)) ink \(ink(t0))")
    @MainActor func overlap() -> some View {
        ZStack(alignment: .topLeading) {
            Color.pb.frame(width: 60, height: 60).padding(.leading, 30).padding(.top, 30)
            Color.pr.frame(width: 60, height: 60)
        }
    }
    let o = render(overlap().shadow(color: .black, radius: 0, x: 10, y: 10))
    let oc = render(overlap().compositingGroup().shadow(color: .black, radius: 0, x: 10, y: 10))
    print("SH5 overlapping ZStack, shadow on the stack: \(px(o, 65, 65)) (black = per child, blue = composited) \(px(o, 95, 95))")
    print("SH5c same, .compositingGroup().shadow: \(px(oc, 65, 65)) \(px(oc, 95, 95))")
    let vs = render(VStack(spacing: 10) { Color.pr.frame(width: 40, height: 20); Color.pr.frame(width: 40, height: 20) }.shadow(color: .black, radius: 0, x: 5, y: 5))
    print("SH5d VStack of two: black \(black(vs)) \(px(vs, 42, 22)) \(px(vs, 42, 52))")
    let bg = render(Text("Hg").font(.system(size: 30)).foregroundStyle(Color.pr).padding(10).background(Color.white).shadow(color: .black, radius: 0, x: 4, y: 4))
    print("SH5e Text on a white background, shadowed: black \(black(bg))")
    let op = render(sq.opacity(0.5).shadow(color: .black, radius: 0, x: 10, y: 10))
    print("SH6 opacity(0.5) inside shadow: shadow-only \(px(op, 45, 45)) content-only \(px(op, 5, 5))")
    let op2 = render(sq.shadow(color: .black, radius: 0, x: 10, y: 10).opacity(0.5))
    print("SH6b opacity(0.5) outside: shadow-only \(px(op2, 45, 45)) content-only \(px(op2, 5, 5))")
    let cl = render(sq.shadow(color: .black, radius: 0, x: 10, y: 10).frame(width: 40, height: 40).clipped())
    print("SH7 shadow then clipped(): ink \(ink(cl))")
    let ci = render(Color.pr.frame(width: 80, height: 40).frame(width: 40, height: 40).clipped().shadow(color: .black, radius: 0, x: 10, y: 10))
    print("SH7b clipped content shadowed: black \(black(ci))")
    print("SH8 sizes shadowed fixed 40x20: \(sizes(Color.pr.frame(width: 40, height: 20).shadow(radius: 10, x: 20, y: 20)))")
    let ring = render(Circle().stroke(Color.pr, lineWidth: 4).frame(width: 60, height: 60).shadow(color: .black, radius: 0, x: 3, y: 3))
    print("SH9 stroked circle shadowed: centre \(px(ring, 30, 30)) black \(black(ring))")
    let neg = render(sq.shadow(color: .black, radius: 0, x: -10, y: -10))
    print("SH10 negative offset: black \(black(neg))")
    let stack2 = render(sq.shadow(color: .black, radius: 0, x: 10, y: 0).shadow(color: .pb, radius: 0, x: 0, y: 10))
    print("SH11 two shadows: black \(black(stack2)) blue \(blue(stack2)) \(px(stack2, 45, 5)) \(px(stack2, 45, 45))")
    let pathShadow = render(pathView { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 40, y: 0)); p.addLine(to: CGPoint(x: 0, y: 40)); p.closeSubpath() }.fill(Color.pr).frame(width: 40, height: 40).shadow(color: .black, radius: 0, x: 10, y: 10))
    print("SH12 triangle path shadowed: black \(black(pathShadow)) \(px(pathShadow, 35, 35))")
    let colourAlpha = render(sq.shadow(color: Color.black.opacity(0.5), radius: 0, x: 10, y: 10))
    print("SH13 shadow colour opacity 0.5: \(px(colourAlpha, 45, 45))")
}

// T: transforms (paint). Separating arms: T2 anchor (box differs from T1's),
// T5 flip (colour order differs), T7 clip order (box differs), T10 shadow
// order (shadow displacement differs).
print("--- T: rotationEffect / scaleEffect / offset")
do {
    let bar = Color.pr.frame(width: 100, height: 20)
    print("T0 bar control: \(ink(render(bar)))")
    print("T1 rotationEffect(45°): \(ink(render(bar.rotationEffect(.degrees(45))))) sizes \(sizes(bar.rotationEffect(.degrees(45))))")
    print("T1b rotationEffect(90°): \(ink(render(bar.rotationEffect(.degrees(90))))) red \(red(render(bar.rotationEffect(.degrees(90)))))")
    print("T2 rotationEffect(90°, anchor: .topLeading): \(ink(render(bar.rotationEffect(.degrees(90), anchor: .topLeading))))")
    print("T2b rotationEffect(-90°): \(red(render(bar.rotationEffect(.degrees(-90)))))")
    let sq = Color.pr.frame(width: 40, height: 20)
    print("T3 scaleEffect(2): \(ink(render(sq.scaleEffect(2)))) sizes \(sizes(sq.scaleEffect(2)))")
    print("T3b scaleEffect(2, anchor: .topLeading): \(ink(render(sq.scaleEffect(2, anchor: .topLeading))))")
    print("T4 scaleEffect(x: 2, y: 0.5): \(ink(render(sq.scaleEffect(x: 2, y: 0.5))))")
    print("T4b scaleEffect(CGSize(2, 0.5)) == x:y: \(differing(render(sq.scaleEffect(CGSize(width: 2, height: 0.5))), render(sq.scaleEffect(x: 2, y: 0.5))))px")
    let f = render(halvesBlock().scaleEffect(x: -1, y: 1))
    print("T5 halves scaleEffect(x: -1): red \(red(f)) blue \(blue(f))")
    print("T5b scaleEffect(0): \(ink(render(sq.scaleEffect(0))))")
    print("T6 offset(x: 30, y: 10): \(ink(render(sq.offset(x: 30, y: 10)))) sizes \(sizes(sq.offset(x: 30, y: 10)))")
    let sib = render(HStack(spacing: 0) { sq.offset(x: 0, y: 30); Color.pb.frame(width: 40, height: 20) })
    print("T6b offset in an HStack: red \(red(sib)) blue \(blue(sib))")
    print("T6c offset(CGSize(30,10)) == offset(x:y:): \(differing(render(sq.offset(CGSize(width: 30, height: 10))), render(sq.offset(x: 30, y: 10))))px")
    let inner = Color.pr.frame(width: 100, height: 20).frame(width: 60, height: 20).clipped()
    print("T7 clipped() then rotationEffect(90°): \(ink(render(inner.rotationEffect(.degrees(90))))) ")
    print("T7b rotationEffect(90°) then clipped(): \(ink(render(bar.rotationEffect(.degrees(90)).clipped())))")
    print("T8 background(blue) then rotationEffect(90°): blue \(blue(render(sq.background(Color.pb).padding(5).background(Color.pb).rotationEffect(.degrees(90))))) | rotation then background: blue \(blue(render(sq.rotationEffect(.degrees(90)).background(Color.pb))))")
    let txt = render(Text("Hello").font(.system(size: 20)).foregroundStyle(Color.black).rotationEffect(.degrees(90)))
    let txt0 = render(Text("Hello").font(.system(size: 20)).foregroundStyle(Color.black))
    print("T9 Text rotated 90°: ink \(ink(txt)) | unrotated ink \(ink(txt0))")
    let sr = render(sq.shadow(color: .black, radius: 0, x: 10, y: 0).rotationEffect(.degrees(90)))
    let rs = render(sq.rotationEffect(.degrees(90)).shadow(color: .black, radius: 0, x: 10, y: 0))
    print("T10 shadow(x10) then rotationEffect(90°): black \(black(sr)) | rotation then shadow: black \(black(rs))")
    print("T11 rotation 45° then offset(30,0): \(ink(render(bar.rotationEffect(.degrees(45)).offset(x: 30)))) | offset then rotation: \(ink(render(bar.offset(x: 30).rotationEffect(.degrees(45)))))")
    let img = render(Color.pr.frame(width: 40, height: 40).rotationEffect(.degrees(30)))
    print("T12 rotated square edge AA (partial pixels): \(partial(img)) ink \(ink(img)) red \(red(img))")
    print("T14 shadow(x10) then scaleEffect(2): black \(black(render(sq.shadow(color: .black, radius: 0, x: 10, y: 0).scaleEffect(2))))")
    let big = render(Text("Hg").font(.system(size: 40)).foregroundStyle(Color.black).fixedSize().frame(width: 60, height: 50))
    let scaled = render(Text("Hg").font(.system(size: 20)).foregroundStyle(Color.black).fixedSize().frame(width: 30, height: 25).scaleEffect(2, anchor: .topLeading).frame(width: 60, height: 50, alignment: .topLeading))
    print("T15 Text(20pt).scaleEffect(2) vs Text(40pt): \(differing(big, scaled))px differ; grey levels in scaled \(Set(stride(from: 0, to: scaled.bytes.count, by: 4).map { scaled.bytes[$0] }).count) vs big \(Set(stride(from: 0, to: big.bytes.count, by: 4).map { big.bytes[$0] }).count)")
    let small = render(Text("Hg").font(.system(size: 20)).foregroundStyle(Color.black).fixedSize().frame(width: 30, height: 25, alignment: .topLeading).frame(width: 60, height: 50, alignment: .topLeading))
    var up = scaled; for y in 0..<50 { for x in 0..<60 {
        let sx = (Double(x) + 0.5) / 2 - 0.5, sy = (Double(y) + 0.5) / 2 - 0.5
        let x0 = Int(sx.rounded(.down)), y0 = Int(sy.rounded(.down)), fx = sx - Double(x0), fy = sy - Double(y0)
        func s(_ X: Int, _ Y: Int) -> Double { Double(rgb(small, min(max(X, 0), 29), min(max(Y, 0), 24)).0) }
        let v = (s(x0, y0) * (1 - fx) + s(x0 + 1, y0) * fx) * (1 - fy) + (s(x0, y0 + 1) * (1 - fx) + s(x0 + 1, y0 + 1) * fx) * fy
        let i = ((y + oy) * up.w + x + ox) * 4; let b = UInt8(v.rounded()); up.bytes[i] = b; up.bytes[i + 1] = b; up.bytes[i + 2] = b
    } }
    func partials(_ b: Bitmap) -> Int { var n = 0; for y in 0..<50 { for x in 0..<60 { let r = rgb(b, x, y).0; if r > 0 && r < 255 { n += 1 } } }; return n }
    print("T15b scaled vs a bilinear 2x upscale of the 20pt raster: \(differing(up, scaled))px differ; partial pixels: scaled \(partials(scaled)) upscale \(partials(up)) 40pt \(partials(big))")
    let cross = render(Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 10, y: 10)) }.stroke(Color.black, lineWidth: 1).frame(width: 10, height: 10).scaleEffect(4, anchor: .topLeading).frame(width: 40, height: 40, alignment: .topLeading))
    print("T16 a 1pt diagonal Path scaled 4x: partial-coverage pixels \(bbox(cross) { r, g, b in r > 0 && r < 255 }) solid \(black(cross))")
    print("T13 opacity(0.5) then rotation: \(px(render(sq.opacity(0.5).rotationEffect(.degrees(90))), 20, 10))")
}

// H: hit testing under transforms. 200×200 windows; points top-left.
// Separating arms: each arm has a point inside the transformed shape but
// outside the layout frame, and one inside the layout frame but outside the
// transformed shape.
print("--- H: hit testing")
hits("H1 160x20 bar rotated 90°, tap", [(100, 100), (100, 40), (40, 100)]) {
    tappable(.pr).frame(width: 160, height: 20).rotationEffect(.degrees(90)).frame(width: 200, height: 200)
}
hits("H1c the same bar unrotated (control)", [(100, 100), (100, 40), (40, 100)]) {
    tappable(.pr).frame(width: 160, height: 20).frame(width: 200, height: 200)
}
hits("H1b tap written AFTER rotationEffect", [(100, 40), (40, 100)]) {
    Color.pr.frame(width: 160, height: 20).rotationEffect(.degrees(90)).onTapGesture { Count.hits += 1 }.frame(width: 200, height: 200)
}
hits("H2 160x160 scaleEffect(0.5)", [(100, 100), (30, 100)]) {
    tappable(.pr).frame(width: 160, height: 160).scaleEffect(0.5).frame(width: 200, height: 200)
}
hits("H3 60x60 scaleEffect(2)", [(100, 100), (50, 100)]) {
    tappable(.pr).frame(width: 60, height: 60).scaleEffect(2).frame(width: 200, height: 200)
}
hits("H4 60x60 offset(x: 60)", [(160, 100), (80, 100)]) {
    tappable(.pr).frame(width: 60, height: 60).offset(x: 60).frame(width: 200, height: 200)
}
hits("H5 60x60 shadow(r0, 40, 40) — shadow-only point", [(100, 100), (150, 150)]) {
    tappable(.pr).frame(width: 60, height: 60).shadow(color: .black, radius: 0, x: 40, y: 40).frame(width: 200, height: 200)
}
hits("H6 Button 100x30 rotated 90°", [(100, 40), (40, 100)]) {
    Button { Count.hits += 1 } label: { Color.pr.frame(width: 160, height: 20) }.buttonStyle(.plain)
        .rotationEffect(.degrees(90)).frame(width: 200, height: 200)
}
hits("H7 square 80x80 rotated 45°: a corner of the frame / a diamond tip", [(65, 65), (100, 48)]) {
    tappable(.pr).frame(width: 80, height: 80).rotationEffect(.degrees(45)).frame(width: 200, height: 200)
}

// X: accessibility frames under transforms (P4 is the control).
print("--- X: accessibilityFrame")
axFrame("X1 offset(x: 50, y: 20)", Button("A") {}.frame(width: 100, height: 40).offset(x: 50, y: 20))
axFrame("X2 rotationEffect(90°)", Button("A") {}.frame(width: 100, height: 40).rotationEffect(.degrees(90)))
axFrame("X3 rotationEffect(45°)", Button("A") {}.frame(width: 100, height: 40).rotationEffect(.degrees(45)))
axFrame("X4 scaleEffect(2)", Button("A") {}.frame(width: 100, height: 40).scaleEffect(2))
axFrame("X5 scaleEffect(0.5, anchor: .topLeading)", Button("A") {}.frame(width: 100, height: 40).scaleEffect(0.5, anchor: .topLeading))
axFrame("X6 shadow(r10, 30, 30)", Button("A") {}.frame(width: 100, height: 40).shadow(radius: 10, x: 30, y: 30))

// N: which of these animate, and as what value (P5/P6 are the controls).
print("--- N: animation")
anim("N1 rotationEffect(.degrees(v)) 0→90", to: 90) { m in Color.pr.frame(width: 50, height: 20).rotationEffect(.degrees(m.v)) }
anim("N2 scaleEffect(1 + v) 0→1", to: 1) { m in Color.pr.frame(width: 50, height: 20).scaleEffect(1 + m.v) }
anim("N2b scaleEffect(x: 1 + v, y: 1)", to: 1) { m in Color.pr.frame(width: 50, height: 20).scaleEffect(x: 1 + m.v, y: 1) }
anim("N3 offset(x: v) 0→40", to: 40) { m in Color.pr.frame(width: 50, height: 20).offset(x: m.v) }
anim("N4 shadow radius 0→10", to: 10) { m in Color.pr.frame(width: 50, height: 20).shadow(color: .black, radius: m.v, x: 0, y: 0) }
anim("N5 shadow x 0→10", to: 10) { m in Color.pr.frame(width: 50, height: 20).shadow(color: .black, radius: 2, x: m.v, y: 0) }
anim("N6 shadow colour black→blue", to: 1) { m in Color.pr.frame(width: 50, height: 20).shadow(color: m.v == 0 ? .black : .pb, radius: 2, x: 0, y: 0) }
anim("N7 Path view whose rect grows 20→60", to: 40) { m in pathView { $0.addRect(CGRect(x: 0, y: 0, width: 20 + m.v, height: 20)) }.frame(width: 100, height: 20) }
anim("N8 Rectangle().stroke(lineWidth: 1 + v) 0→5", to: 5) { m in Rectangle().stroke(Color.black, lineWidth: 1 + m.v).frame(width: 50, height: 20) }
anim("N9 rotationEffect anchor .center→.topLeading", to: 1) { m in Color.pr.frame(width: 50, height: 20).rotationEffect(.degrees(30), anchor: m.v == 0 ? .center : .topLeading) }
anim("N10 Path.trimmedPath(from: 0, to: 0.2 + v)", to: 0.6) { m in Circle().trim(from: 0, to: 0.2 + m.v).stroke(Color.black, lineWidth: 2).frame(width: 50, height: 50) }
}
