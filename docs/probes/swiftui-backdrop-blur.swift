// SwiftUI probe: backdrop blur behind a Material (C21; rulings BB-* in
// docs/superpowers/2026-10-10-backdrop-blur-decisions.md, spec
// docs/superpowers/specs/2026-10-10-backdrop-blur-design.md).
//
// HOW TO RUN (SA-O's compiled form):
//
//   xcrun swiftc docs/probes/swiftui-backdrop-blur.swift -o /tmp/bb-probe && /tmp/bb-probe 2>&1 | grep -v 'Connection\]'
//
// INSTRUMENT: ImageRenderer at scale 1 (the controls-looks probe's), no window.
// Its screen-state independence is why it is used; a real key window is
// unmeasured (LK-O item 2) and stays a human check.
//
// GROUPS.
//   P  positive controls. P1: a black|white vertical step with no material
//      reads a one-pixel step (the profile instrument sees an unblurred edge).
//      P2: the same step under a Color.clear overlay still reads a step (an
//      overlay alone blurs nothing). P3: .blur(radius: 8) on the step reads a
//      wide ramp (the instrument can see a blur).
//   S  the profile of the backdrop under each material, light and dark: the
//      step is at x=100 in a 200x40 image, the material covers it all. The
//      10%-90% rise distance of the red channel, divided by 2.563, is a
//      Gaussian sigma (the B1 method of swiftui-controls-looks.swift).
//   E  the edge: black outside the material's rect, white inside. Does the
//      blur read the backdrop OUTSIDE the material's shape? (An interior
//      pixel near the edge darkens if it does.) Compared with a white-only
//      control (no black outside) to prove the darkening is the outside.
//   R  the shape: a regular material filled in a circle / rounded rect over
//      the step; a pixel outside the shape reads the unblurred backdrop.
//   N  nesting: a regular material over an ultraThin one over the step.
//   O  .opacity(0.5) on the material: is the blur kept at half strength, or
//      is it a plain half-weight composite of the (blurred, tinted) layer
//      over the unblurred backdrop? Read on the step's neighbours.
//   T  Reduce Transparency: NSWorkspace.accessibilityDisplayShouldReduceTransparency
//      swizzled in-process (the controls-looks probe's Reduce Motion
//      technique; the system setting is never touched). Does the material
//      stay blurred, go flat, or go opaque?
//
// RECORDED 2026-10-10 by the C21 (backdrop blur) designer, macOS 27.0.1, Apple Swift 6.4,
// screen UNLOCKED (lock probe: no CGSSessionScreenIsLocked line, displayAsleep main: 0).
// Two runs with --window were byte-identical (58 lines each; the W arm is abbreviated
// below to its distinct values, the full row is 20 samples).
//
//   --- P: positive controls
//     P1 no material: 96:0 98:0 99:0 100:255 101:255 102:255 104:255
//     P2 Color.clear overlay: 96:0 98:0 99:0 100:255 101:255 102:255 104:255
//     P3 .blur(radius: 8): range 94..255 rise10-90 10.24 px sigma 4.00
//   --- S: the backdrop profile under each material (step at x=100, material covers all)
//     S light ultraThin: range 100..242 rise10-90 126.60 px sigma 49.40; samples 60:132 80:150 90:162 100:172 110:184 120:195 140:213
//     S light thin: range 126..242 rise10-90 125.80 px sigma 49.08; samples 60:153 80:167 90:177 100:185 110:194 120:202 140:219
//     S light regular: range 154..239 rise10-90 115.25 px sigma 44.97; samples 60:174 80:184 90:192 100:199 110:206 120:213 140:224
//     S light thick: range 181..235 rise10-90 104.20 px sigma 40.66; samples 60:195 80:202 90:208 100:212 110:218 120:222 140:231
//     S light ultraThick: range 207..231 rise10-90 88.90 px sigma 34.69; samples 60:217 80:221 90:223 100:225 110:228 120:231 140:231
//     S light bar: range 206..253 rise10-90 127.60 px sigma 49.79; samples 60:217 80:222 90:226 100:230 110:233 120:237 140:243
//     S dark ultraThin: range 30..163 rise10-90 125.40 px sigma 48.93; samples 60:61 80:77 90:88 100:98 110:109 120:119 140:136
//     S dark thin: range 33..145 rise10-90 126.60 px sigma 49.40; samples 60:58 80:72 90:83 100:89 110:99 120:107 140:123
//     S dark regular: range 36..126 rise10-90 128.00 px sigma 49.94; samples 60:56 80:67 90:74 100:81 110:88 120:95 140:106
//     S dark thick: range 40..106 rise10-90 127.80 px sigma 49.86; samples 60:54 80:62 90:68 100:72 110:78 120:84 140:92
//     S dark ultraThick: range 44..87 rise10-90 109.40 px sigma 42.68; samples 60:52 80:57 90:61 100:65 110:68 120:72 140:77
//     S dark bar: range 39..82 rise10-90 124.40 px sigma 48.54; samples 60:49 80:54 90:58 100:61 110:64 120:68 140:73
//   --- E: does the blur read the backdrop outside the material's rect? (material x 100..200, black left of 100, white right; interior probe at 102, 110, 130)
//     E1 regular: black outside: 102:233 110:235 130:239 190:239  | white-only control: 102:239 110:239 130:239 190:239
//     E1 ultraThin: black outside: 102:228 110:230 130:236 190:246  | white-only control: 102:246 110:246 130:246 190:246
//   --- R: shape (regular material in a Circle / rounded rect 12; pixel outside the shape must read the unblurred backdrop)
//     R1 circle 60x40 centred on the step: outside 60:0 69:0 70:0 130:255 131:255 140:255 inside 85:187 100:199 115:209
//     R2 rrect 60x40: outside 60:0 69:0 70:179 130:255 131:255 140:255 inside 85:187 100:199 115:210
//   --- N: nesting (regular over ultraThin over the step, light)
//     N1 nested: range 192..237 rise10-90 144.75 px sigma 56.48; single regular: range 154..239 rise10-90 115.25 px sigma 44.97
//   --- O: opacity(0.5) on a regular material over the step (light)
//     O1 opacity 0.5: range 79..245 rise10-90 24.80 px sigma 9.68; samples 60:90 90:98 100:226 110:230 140:239 | full: 60:174 90:192 100:199 110:206 140:224
//   --- T: Reduce Transparency (light, regular)
//     T reduceTransparency=false (getter reads false): range 154..239 rise10-90 115.25 px sigma 44.97; samples 60:174 100:199 140:224
//     T reduceTransparency=true (getter reads true): range 154..239 rise10-90 115.25 px sigma 44.97; samples 60:174 100:199 140:224
//   --- S2: normalised profile ((v - black)/(white - black), black/white = the same material over uniform black/white) of a step in images of two widths
//     S2 regular width 200 black 150 white 239: 0:0.04 10:0.07 20:0.09 30:0.11 40:0.16 50:0.20 60:0.27 70:0.33 80:0.38 90:0.47 100:0.55 110:0.63 120:0.71 130:0.78 140:0.83 150:0.89 160:0.94 170:0.98 180:1.00 190:1.00
//     S2 regular width 400 black 150 white 239: 0:0.00 20:0.00 40:0.00 60:0.01 80:0.01 100:0.04 120:0.09 140:0.16 160:0.27 180:0.39 200:0.56 220:0.72 240:0.83 260:0.94 280:1.00 300:1.00 320:1.00 340:1.00 360:1.00 380:1.00
//     S2 ultraThin width 200 black 94 white 246: 0:0.04 10:0.05 20:0.08 30:0.11 40:0.15 50:0.20 60:0.25 70:0.30 80:0.37 90:0.45 100:0.51 110:0.59 120:0.66 130:0.72 140:0.78 150:0.84 160:0.88 170:0.91 180:0.95 190:0.97
//     S2 ultraThin width 400 black 94 white 246: 0:0.00 20:0.00 40:0.00 60:0.01 80:0.01 100:0.03 120:0.08 140:0.15 160:0.25 180:0.37 200:0.51 220:0.66 240:0.78 260:0.88 280:0.95 300:0.99 320:1.00 340:1.00 360:1.00 380:1.00
//   --- E2: bleed from outside the shape: material x 100..300 over white, black strip x 0..100 left of it; normalised drop of the interior pixel at distance d from the left edge
//     E2 regular: d0:0.056 d1:0.056 d2:0.067 d4:0.056 d8:0.045 d16:0.034 d32:0.000 d64:0.000
//     E2 ultraThin: d0:0.118 d1:0.118 d2:0.118 d4:0.112 d8:0.105 d16:0.092 d32:0.059 d64:0.020
//   --- F: Gaussian sigma (points) fitted to the step in a 400-wide image (x = 60..340 against erf((x-200)/(sigma*sqrt2)), plateaus read at x = 10 and 390), per material and scheme
//     F light ultraThin: sigma 53.8 pt rms 0.014 (plateaus 94..246)
//     F light thin: sigma 50.8 pt rms 0.025 (plateaus 122..242)
//     F light regular: sigma 49.1 pt rms 0.042 (plateaus 150..239)
//     F light thick: sigma 45.6 pt rms 0.076 (plateaus 178..235)
//     F light ultraThick: sigma 50.1 pt rms 0.168 (plateaus 206..231)
//     F light bar: sigma 55.1 pt rms 0.008 (plateaus 204..255)
//     F dark ultraThin: sigma 51.8 pt rms 0.010 (plateaus 29..169)
//     F dark thin: sigma 52.2 pt rms 0.010 (plateaus 32..149)
//     F dark regular: sigma 50.2 pt rms 0.012 (plateaus 36..128)
//     F dark thick: sigma 49.5 pt rms 0.016 (plateaus 40..107)
//     F dark ultraThick: sigma 45.8 pt rms 0.021 (plateaus 44..87)
//     F dark bar: sigma 55.1 pt rms 0.012 (plateaus 37..84)
//   --- W: real window, red channel along y = 20, step at x = 200 (the capture is of the window only)
//     W step under ultraThin light (capture 800x80): every sampled x reads 222
//     W step under regular light (capture 800x80): every sampled x reads 234
//     W step under ultraThick light (capture 800x80): every sampled x reads 246
//     W step under ultraThin dark (capture 800x80): every sampled x reads 32
//     W step under regular dark (capture 800x80): every sampled x reads 44
//     W step under ultraThick dark (capture 800x80): every sampled x reads 56
//
// READING (rulings BB-F, BB-D, BB-G, BB-H, BB-I):
//   P1-P3: the instrument sees a sharp step (P1, P2) and a blur (P3 widens the 1 px step to a
//     10 px rise). P3's printed sigma is NOT B1's (swiftui-controls-looks.swift): the plateau
//     it reads, 94, is the image edge bleeding the white underlay in, so only the widening is
//     the control. The same edge bleed (0.05-0.12, E2) puts a few percent of error on the
//     plateaus F reads at x = 10 and 390: the fitted sigmas are +-10 %, not exact.
//   S, S2, F: under a Material the ImageRenderer backdrop is a wide, smooth, near-Gaussian
//     profile: fitted sigma 49-55 pt for the six materials in both schemes where the tint
//     leaves contrast (rms <= 0.021; thick/ultraThick light are low-contrast, rms 0.08/0.17,
//     and not used), independent of the image width (S2: 200 and 400). One constant, 52 pt.
//   E, E2: the interior pixel at the shape's edge drops only 0.056 (regular) / 0.118
//     (ultraThin) of the black step's full effect, decaying to 0 by 32-64 px: outside the
//     shape contributes little, nothing like a Gaussian of sigma 50 reading across the edge.
//     The backdrop is (nearly) clamped to the shape.
//   R: outside a Circle / rounded rect the backdrop reads sharp (0 / 255 / 179 at the rrect's
//     antialiased edge).
//   N: nested materials blur twice (rise 144.75 px vs 115.25 for one).
//   O: opacity 0.5 on the material is a half-weight composite of the (blurred, tinted) layer
//     over the SHARP backdrop (x=60: 90 = (0 + 174)/2 +- 3; x=100: 226 = (255 + 199)/2 -1).
//   T: INCONCLUSIVE. The getter swizzle reads true but ImageRenderer draws identical pixels:
//     the separating arm failed, so SwiftUI's Reduce Transparency answer is UNMEASURED.
//   W: in a real window (borderless NSWindow + NSHostingView, opaque or clear) the material
//     samples what is behind the WINDOW, not the sibling step: every sampled x reads one value.
//     SwiftUI's in-window blur exists only in ImageRenderer; MetalUI follows the in-window
//     reading (the only one that exists to follow) and records the difference (divergence 245).

import SwiftUI
import AppKit
import ObjectiveC

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
@MainActor func render(_ v: some View, w: Int, h: Int, scheme: ColorScheme = .light) -> Bitmap {
    let c = ZStack(alignment: .topLeading) { Color.white; v }
        .frame(width: CGFloat(w), height: CGFloat(h), alignment: .topLeading)
        .environment(\.colorScheme, scheme)
    let r = ImageRenderer(content: c)
    r.scale = 1
    return bytes(of: r.cgImage!)
}
func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Int, Int, Int) {
    guard x >= 0, y >= 0, x < b.w, y < b.h else { return (-1, -1, -1) }
    let i = (y * b.w + x) * 4
    return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2]))
}
extension Color {
    static let pk = Color(.sRGB, red: 0, green: 0, blue: 0)
    static let pw = Color(.sRGB, red: 1, green: 1, blue: 1)
}
/// Black on the left half, white on the right (step at x = 100), 200x40.
func step() -> some View { HStack(spacing: 0) { Color.pk.frame(width: 100, height: 40); Color.pw.frame(width: 100, height: 40) } }
/// 10%..90% rise distance of the red channel along y = 20, in pixels (fractional by interpolation), and the Gaussian sigma it implies.
func rise(_ b: Bitmap) -> String {
    let row = (0..<b.w).map { Double(rgb(b, $0, 20).0) }
    let lo = row[2], hi = row[b.w - 3]
    guard hi - lo > 8 else { return "range \(Int(lo))..\(Int(hi)) too small" }
    func at(_ f: Double) -> Double {
        let t = lo + (hi - lo) * f
        for x in 0..<(b.w - 1) where row[x] <= t && row[x + 1] >= t { return Double(x) + (row[x + 1] == row[x] ? 0 : (t - row[x]) / (row[x + 1] - row[x])) }
        return .nan
    }
    let d = at(0.9) - at(0.1)
    return String(format: "range %d..%d rise10-90 %.2f px sigma %.2f", Int(lo), Int(hi), d, d / 2.563)
}
func band(_ b: Bitmap, _ xs: [Int]) -> String { xs.map { "\($0):\(rgb(b, $0, 20).0)" }.joined(separator: " ") }

nonisolated(unsafe) var forceReduceTransparency = false
final class RTSwizzle: NSObject { @objc dynamic var fake: Bool { forceReduceTransparency } }
func installReduceTransparencySwizzle() {
    let orig = class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceTransparency))!
    let repl = class_getInstanceMethod(RTSwizzle.self, #selector(getter: RTSwizzle.fake))!
    method_setImplementation(orig, method_getImplementation(repl))
}

@MainActor func run() {
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar)]
    print("--- P: positive controls")
    let p1 = render(step(), w: 200, h: 40)
    print("  P1 no material: " + band(p1, [96, 98, 99, 100, 101, 102, 104]))
    let p2 = render(ZStack { step(); Color.clear }, w: 200, h: 40)
    print("  P2 Color.clear overlay: " + band(p2, [96, 98, 99, 100, 101, 102, 104]))
    let p3 = render(step().blur(radius: 8), w: 200, h: 40)
    print("  P3 .blur(radius: 8): " + rise(p3))
    print("--- S: the backdrop profile under each material (step at x=100, material covers all)")
    for scheme in [ColorScheme.light, .dark] {
        for (name, m) in mats {
            let b = render(ZStack { step(); Rectangle().fill(m) }, w: 200, h: 40, scheme: scheme)
            print("  S \(scheme) \(name): \(rise(b)); samples " + band(b, [60, 80, 90, 100, 110, 120, 140]))
        }
    }
    print("--- E: does the blur read the backdrop outside the material's rect? (material x 100..200, black left of 100, white right; interior probe at 102, 110, 130)")
    for (name, m) in [("regular", Material.regularMaterial), ("ultraThin", .ultraThinMaterial)] {
        let withOutside = render(ZStack(alignment: .topLeading) { HStack(spacing: 0) { Color.pk.frame(width: 100, height: 40); Color.pw.frame(width: 100, height: 40) }; Rectangle().fill(m).frame(width: 100, height: 40).offset(x: 100) }, w: 200, h: 40)
        let whiteOnly = render(ZStack(alignment: .topLeading) { Color.pw.frame(width: 200, height: 40); Rectangle().fill(m).frame(width: 100, height: 40).offset(x: 100) }, w: 200, h: 40)
        print("  E1 \(name): black outside: " + band(withOutside, [102, 110, 130, 190]) + "  | white-only control: " + band(whiteOnly, [102, 110, 130, 190]))
    }
    print("--- R: shape (regular material in a Circle / rounded rect 12; pixel outside the shape must read the unblurred backdrop)")
    let rc = render(ZStack { step(); Circle().fill(Material.regularMaterial).frame(width: 60, height: 40) }, w: 200, h: 40)
    print("  R1 circle 60x40 centred on the step: outside " + band(rc, [60, 69, 70, 130, 131, 140]) + " inside " + band(rc, [85, 100, 115]))
    let rr = render(ZStack { step(); RoundedRectangle(cornerRadius: 12).fill(Material.regularMaterial).frame(width: 60, height: 40) }, w: 200, h: 40)
    print("  R2 rrect 60x40: outside " + band(rr, [60, 69, 70, 130, 131, 140]) + " inside " + band(rr, [85, 100, 115]))
    print("--- N: nesting (regular over ultraThin over the step, light)")
    let n1 = render(ZStack { step(); Rectangle().fill(Material.ultraThinMaterial); Rectangle().fill(Material.regularMaterial) }, w: 200, h: 40)
    let n0 = render(ZStack { step(); Rectangle().fill(Material.regularMaterial) }, w: 200, h: 40)
    print("  N1 nested: \(rise(n1)); single regular: \(rise(n0))")
    print("--- O: opacity(0.5) on a regular material over the step (light)")
    let o1 = render(ZStack { step(); Rectangle().fill(Material.regularMaterial).opacity(0.5) }, w: 200, h: 40)
    let o0 = render(ZStack { step(); Rectangle().fill(Material.regularMaterial) }, w: 200, h: 40)
    print("  O1 opacity 0.5: \(rise(o1)); samples " + band(o1, [60, 90, 100, 110, 140]) + " | full: " + band(o0, [60, 90, 100, 110, 140]))
    print("--- T: Reduce Transparency (light, regular)")
    installReduceTransparencySwizzle()
    for on in [false, true] {
        forceReduceTransparency = on
        let t = render(ZStack { step(); Rectangle().fill(Material.regularMaterial) }, w: 200, h: 40)
        print("  T reduceTransparency=\(on) (getter reads \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)): \(rise(t)); samples " + band(t, [60, 100, 140]))
    }
}

@MainActor func profile2() {
    print("--- S2: normalised profile ((v - black)/(white - black), black/white = the same material over uniform black/white) of a step in images of two widths")
    for (name, m) in [("regular", Material.regularMaterial), ("ultraThin", .ultraThinMaterial)] {
        for width in [200, 400] {
            func stepW() -> some View { HStack(spacing: 0) { Color.pk.frame(width: CGFloat(width / 2), height: 40); Color.pw.frame(width: CGFloat(width / 2), height: 40) } }
            let k = render(ZStack { Color.pk; Rectangle().fill(m) }, w: width, h: 40)
            let wv = render(ZStack { Color.pw; Rectangle().fill(m) }, w: width, h: 40)
            let b = render(ZStack { stepW(); Rectangle().fill(m) }, w: width, h: 40)
            let lo = Double(rgb(k, 5, 20).0), hi = Double(rgb(wv, 5, 20).0)
            let pts = stride(from: 0, to: width, by: width / 20).map { x in String(format: "%d:%.2f", x, (Double(rgb(b, x, 20).0) - lo) / (hi - lo)) }
            print("  S2 \(name) width \(width) black \(Int(lo)) white \(Int(hi)): " + pts.joined(separator: " "))
        }
    }
    print("--- E2: bleed from outside the shape: material x 100..300 over white, black strip x 0..100 left of it; normalised drop of the interior pixel at distance d from the left edge")
    for (name, m) in [("regular", Material.regularMaterial), ("ultraThin", .ultraThinMaterial)] {
        let ctrl = render(ZStack(alignment: .topLeading) { Color.pw.frame(width: 300, height: 40); Rectangle().fill(m).frame(width: 200, height: 40).offset(x: 100) }, w: 300, h: 40)
        let b = render(ZStack(alignment: .topLeading) { Color.pw.frame(width: 300, height: 40); Color.pk.frame(width: 100, height: 40); Rectangle().fill(m).frame(width: 200, height: 40).offset(x: 100) }, w: 300, h: 40)
        let ref = Double(rgb(ctrl, 200, 20).0)
        let kk = render(ZStack { Color.pk; Rectangle().fill(m) }, w: 300, h: 40)
        let drop = Double(rgb(kk, 5, 20).0)
        let pts = [0, 1, 2, 4, 8, 16, 32, 64].map { d in String(format: "d%d:%.3f", d, (ref - Double(rgb(b, 100 + d, 20).0)) / (ref - drop)) }
        print("  E2 \(name): " + pts.joined(separator: " "))
    }
}

// ------------------------------------------------------------------ W: a real window
// Only when the lock probe allows (no CGSSessionScreenIsLocked line, displayAsleep
// main: 0). A borderless window at (200, 200), 400x40 points, hosts the step under
// one material; `screencapture -x -o -l <id>` captures that window alone (no
// shadow), 2x pixels, read back at 1 px per point by taking every second pixel.
@MainActor func windowProfile(_ name: String, _ m: Material, dark: Bool, caption: String) -> String {
    let content = ZStack { HStack(spacing: 0) { Color.pk.frame(width: 200, height: 40); Color.pw.frame(width: 200, height: 40) }; Rectangle().fill(m) }
        .frame(width: 400, height: 40)
        .environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: content)
    let win = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 400, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    win.isOpaque = !CommandLine.arguments.contains("--clear")
    if !win.isOpaque { win.backgroundColor = .clear }
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.2))
    let path = "/tmp/bb-win-\(name)-\(dark).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(win.windowNumber), path]
    try? p.run(); p.waitUntilExit()
    win.orderOut(nil)
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "  W \(name): no capture" }
    let b = bytes(of: cg)
    let scale = b.w / 400
    let row = (0..<400).map { Int(b.bytes[((20 * scale) * b.w + $0 * scale) * 4]) }
    let lo = Double(row[100 / 1] ), hi = Double(row[300])
    let pts = stride(from: 0, to: 400, by: 20).map { "\($0):\(row[$0])" }.joined(separator: " ")
    _ = (lo, hi)
    return "  W \(caption) \(name) \(dark ? "dark" : "light") (capture \(b.w)x\(b.h)): " + pts
}
@MainActor func windowArm() {
    print("--- W: real window, red channel along y = 20, step at x = 200 (the capture is of the window only)")
    _ = NSApplication.shared
    for dark in [false, true] {
        for (n, m) in [("ultraThin", Material.ultraThinMaterial), ("regular", .regularMaterial), ("ultraThick", .ultraThickMaterial)] {
            print(windowProfile(n, m, dark: dark, caption: "step under"))
        }
    }
}

@MainActor func fit() {
    print("--- F: Gaussian sigma (points) fitted to the step in a 400-wide image (x = 60..340 against erf((x-200)/(sigma*sqrt2)), plateaus read at x = 10 and 390), per material and scheme")
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar)]
    for scheme in [ColorScheme.light, .dark] {
        for (name, m) in mats {
            let b = render(ZStack { HStack(spacing: 0) { Color.pk.frame(width: 200, height: 40); Color.pw.frame(width: 200, height: 40) }; Rectangle().fill(m) }, w: 400, h: 40, scheme: scheme)
            let lo = Double(rgb(b, 10, 20).0), hi = Double(rgb(b, 390, 20).0)
            var best = (sigma: 0.0, rms: 1e9)
            for tenth in 50...1200 {
                let sg = Double(tenth) / 10
                var sum = 0.0, n = 0.0
                for x in stride(from: 60, through: 340, by: 4) {
                    let model = 0.5 * (1 + erf((Double(x) - 200) / (sg * 2.0.squareRoot())))
                    let v = (Double(rgb(b, x, 20).0) - lo) / (hi - lo)
                    sum += (v - model) * (v - model); n += 1
                }
                let rms = (sum / n).squareRoot()
                if rms < best.rms { best = (sg, rms) }
            }
            print(String(format: "  F %@ %@: sigma %.1f pt rms %.3f (plateaus %d..%d)", "\(scheme)", name, best.sigma, best.rms, Int(lo), Int(hi)))
        }
    }
}
MainActor.assumeIsolated { run(); profile2(); fit(); if CommandLine.arguments.contains("--window") { windowArm() } }
