// SwiftUI probe: how a hierarchical style (`.secondary`, `.tertiary`, ...) PAINTS relative to the style
// it inherits (round 4 item R4-4 PR A; divergence 119, rulings `HY-` in
// docs/superpowers/2026-11-04-hierarchical-styles-decisions.md).
// The sibling probe `swiftui-colour-hierarchical.swift` (CR-U) measures only the TYPE a leading-dot static
// infers; this one measures the PIXELS, which that probe said were "unmeasured and not claimed".
//
// HOW TO RUN (compiled form, SA-O; ImageRenderer needs neither an unlocked session nor a window server
// beyond the process's own, and a compiled probe needs no JIT shim):
//
//   xcrun swiftc -swift-version 6 docs/probes/swiftui-hierarchical-paint.swift -o /tmp/hy-probe
//   /tmp/hy-probe > /tmp/hy-1.txt; /tmp/hy-probe > /tmp/hy-2.txt; cmp /tmp/hy-1.txt /tmp/hy-2.txt
//
// INSTRUMENT. `ImageRenderer` at scale 1, transparent background, a 70 x 70 pt canvas, sRGB bitmap. Each arm
// prints the ALPHA of one pixel (byte / 255, three places) and its un-premultiplied RGB (two places; the
// premultiplied byte at a low alpha limits the RGB, so read the alpha). A shape arm reads the
// maximum-alpha pixel (a solid interior); a text arm renders U+2588 at 60 pt and reads the maximum-alpha
// pixel too; the gradient arms read one named column. The colour scheme is `.environment(\.colorScheme, _)`.
// A modifier written LATER is the PARENT of one written before it, so `X.foregroundStyle(.secondary)
// .foregroundStyle(red)` is a `.secondary` under red.
//
// ARMS. Table arms: NL/ND (no parent, light/dark), RL/RD (a red parent, light/dark; RD is the arm the first
// reading missed), each at the five levels (1 primary ... 5 quinary).
//   P6 `Color.secondary` under red: SEPARATING ARM, stays the grey (a `Color` is not a level).
//   P7 `.secondary` under `.secondary`; P8 red -> `.secondary` -> `.secondary` (levels do not compound);
//   P9 a plain child under red -> `.secondary`; P10 `red.opacity(0.5)` -> `.secondary`;
//   P11/P12 `foregroundStyle(red, blue)` with a child `.secondary` / `.tertiary`; P13 three styles;
//   P14 a gradient parent (left and right columns); P15 `.tint(green)` as the parent;
//   S1..S6 the sinks (`fill`, `stroke`, `strokeBorder`, `background`, `overlay`, `border`) under red, `.secondary`
//   and `.primary`; S9 `.secondary` then `.foregroundStyle(blue)` (the later modifier is the parent), S9r the
//   reverse order (blue is innermost, nothing is hierarchical over it);
//   T2 a view-level `.secondary` over a `Text`, T3 `Text.foregroundStyle(.secondary)` its own, T6
//   `AnyShapeStyle(.secondary)` on a shape and on a `Text`, T9 `Color.red.secondary`.
//
// The original readings of the first session were taken through `swift -` on stdin and never committed;
// this file is their transcription (arm ids kept, arm bodies rebuilt from the plan's descriptions), so the
// RECORDED block below is the first committed run.
//
// RECORDED 2026-11-04, macOS 27.2, Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), screen LOCKED
// (CGSSessionScreenIsLocked = 1; ImageRenderer does not need an unlocked session). Compiled form, run twice:
// stdout byte-identical (62 lines, shasum d5d13f00df4154177d7637983ef9d9b9b23a9a67), exit 0, stderr empty.
// exit 0, stderr empty.
//
//   --- table: five levels, no parent / red parent, light / dark
//   NL1 primary no parent light -> a=0.847 rgb=(0.00,0.00,0.00)
//   NL2 secondary no parent light -> a=0.498 rgb=(0.00,0.00,0.00)
//   NL3 tertiary no parent light -> a=0.259 rgb=(0.00,0.00,0.00)
//   NL4 quaternary no parent light -> a=0.098 rgb=(0.00,0.00,0.00)
//   NL5 quinary no parent light -> a=0.047 rgb=(0.00,0.00,0.00)
//   ND1 primary no parent dark -> a=0.847 rgb=(1.00,1.00,1.00)
//   ND2 secondary no parent dark -> a=0.549 rgb=(1.00,1.00,1.00)
//   ND3 tertiary no parent dark -> a=0.247 rgb=(1.00,1.00,1.00)
//   ND4 quaternary no parent dark -> a=0.098 rgb=(1.00,1.00,1.00)
//   ND5 quinary no parent dark -> a=0.047 rgb=(1.00,1.00,1.00)
//   RL1 primary under red light -> a=1.000 rgb=(1.00,0.22,0.24)
//   RL2 secondary under red light -> a=0.502 rgb=(1.00,0.22,0.23)
//   RL3 tertiary under red light -> a=0.251 rgb=(1.00,0.22,0.23)
//   RL4 quaternary under red light -> a=0.180 rgb=(1.00,0.22,0.24)
//   RL5 quinary under red light -> a=0.180 rgb=(1.00,0.22,0.24)
//   RD1 primary under red dark -> a=1.000 rgb=(1.00,0.26,0.27)
//   RD2 secondary under red dark -> a=0.502 rgb=(1.00,0.26,0.27)
//   RD3 tertiary under red dark -> a=0.251 rgb=(1.00,0.25,0.27)
//   RD4 quaternary under red dark -> a=0.180 rgb=(1.00,0.26,0.26)
//   RD5 quinary under red dark -> a=0.180 rgb=(1.00,0.26,0.26)
//   --- P: how a level composes
//   P6 Color.secondary under red (stays grey) -> a=0.498 rgb=(0.00,0.00,0.00)
//   P6d Color.secondary under red, dark -> a=0.549 rgb=(1.00,1.00,1.00)
//   P7 .secondary under .secondary -> a=0.498 rgb=(0.00,0.00,0.00)
//   P8 red -> .secondary -> .secondary -> a=0.502 rgb=(1.00,0.22,0.23)
//   P9 plain child under red -> .secondary -> a=0.502 rgb=(1.00,0.22,0.23)
//   P10 red.opacity(0.5) -> .secondary -> a=0.251 rgb=(1.00,0.22,0.23)
//   P11 foregroundStyle(red, blue), child .secondary -> a=1.000 rgb=(0.00,0.53,1.00)
//   P12 foregroundStyle(red, blue), child .tertiary -> a=1.000 rgb=(0.00,0.53,1.00)
//   P13 foregroundStyle(red, blue, green), child .tertiary -> a=1.000 rgb=(0.20,0.78,0.35)
//   P13b foregroundStyle(red, blue, green), child .secondary -> a=1.000 rgb=(0.00,0.53,1.00)
//   P13c foregroundStyle(red, blue, green), child .quaternary -> a=1.000 rgb=(0.20,0.78,0.35)
//   P14l gradient red->blue parent, child .secondary, left column -> a=0.502 rgb=(0.98,0.25,0.28)
//   P14r gradient red->blue parent, child .secondary, right column -> a=0.502 rgb=(0.16,0.53,0.97)
//   P14c gradient red->blue parent, child plain, left column -> a=1.000 rgb=(0.98,0.25,0.28)
//   P15 .tint(green) -> foregroundStyle(.tint) -> child .secondary -> a=0.502 rgb=(0.20,0.77,0.35)
//   --- S: sinks read the parent
//   S1 fill(.secondary) under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S2 stroke under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S3 strokeBorder under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S4 background under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S5 overlay under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S6 border under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   S1p fill(.primary) under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S2p stroke under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S3p strokeBorder under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S4p background under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S5p overlay under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S6p border under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   S9 .secondary then foregroundStyle(blue) -> a=0.502 rgb=(0.00,0.53,1.00)
//   S9r foregroundStyle(blue) then .secondary (blue innermost) -> a=1.000 rgb=(0.00,0.53,1.00)
//   --- T: text and erasure
//   T0 Text, no style, no parent -> a=0.847 rgb=(0.00,0.00,0.00)
//   T2 view-level .secondary over a Text, under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   T3 Text.foregroundStyle(.secondary) under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   T3p Text.foregroundStyle(.primary) under red -> a=1.000 rgb=(1.00,0.22,0.24)
//   T3n Text.foregroundStyle(.secondary), no parent -> a=0.498 rgb=(0.00,0.00,0.00)
//   T6s AnyShapeStyle(.secondary) on a shape, under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   T6t Text.foregroundStyle(AnyShapeStyle(.secondary)), under red -> a=0.502 rgb=(1.00,0.22,0.23)
//   T9 Rectangle().fill(Color.red.secondary) -> a=0.502 rgb=(1.00,0.22,0.23)
//   T9b Rectangle().fill(Color.red.secondary) under blue -> a=0.502 rgb=(1.00,0.22,0.23)
//
// READING. A level is a FACTOR of the inherited style: the parent's colour at alpha 1 / .5 / .25 / .18 / .18
// (RL, RD: the same factors in both schemes; the red differs, FF383C light and FF4245 dark), and with NO
// parent the system label colour at .847 / .498 / .259 / .098 / .047 light and .847 / .549 / .247 / .098 /
// .047 dark (NL, ND). Levels do not compound (P7, P8: two `.secondary` are one). A plain child inherits the
// level (P9) and a parent's own opacity multiplies (P10, .251). `Color.secondary` is NOT a level: it stays the
// grey under a red parent (P6, P6d), the separating arm. Every sink reads the parent (S1..S6; `.primary` is
// the parent at 1); the later modifier is the parent (S9 against S9r). `Text` matches shapes (T2, T3), erasure
// keeps the level (T6s, T6t), and a style's own `.secondary` is a factor of THAT style (T9, T9b: red, not the
// inherited blue). `foregroundStyle(a, b, c)` lets a level SELECT: `.primary` the first style, `.secondary`
// the second, `.tertiary` the third, and a level past the last repeats the last (P11..P13c; the selected
// style is drawn at full alpha, not a factor). A gradient parent keeps the gradient and applies the factor
// to every stop (P14l, P14r, different colours at .502); the `.tint(green)` parent is the tint at the factor
// (P15). MetalUI lowers a gradient foreground to its first stop (divergence 975), so P14r is a difference
// the port keeps, not one it reproduces.
import SwiftUI
import AppKit

nonisolated(unsafe) var lines: [String] = []

@MainActor
func pixels<V: View>(_ view: V, scheme: ColorScheme) -> (w: Int, h: Int, data: [UInt8]) {
    let content = view.frame(width: 70, height: 70).environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let image = renderer.cgImage else { return (0, 0, []) }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, data)
}

enum Sample { case maxAlpha, column(Int) }

@MainActor
func arm<V: View>(_ id: String, _ what: String, scheme: ColorScheme = .light, sample: Sample = .maxAlpha,
                  _ view: V) {
    let p = pixels(view, scheme: scheme)
    var best = -1
    var bestAlpha: UInt8 = 0
    switch sample {
    case .maxAlpha:
        for i in 0..<(p.w * p.h) where p.data[i * 4 + 3] > bestAlpha { bestAlpha = p.data[i * 4 + 3]; best = i }
    case let .column(x):
        let i = (p.h / 2) * p.w + x
        if i < p.w * p.h { best = i; bestAlpha = p.data[i * 4 + 3] }
    }
    guard best >= 0, bestAlpha > 0 else { lines.append("\(id) \(what) -> alpha 0.000 (nothing drawn)"); return }
    let a = Double(bestAlpha) / 255
    func channel(_ k: Int) -> Double { min(1, Double(p.data[best * 4 + k]) / 255 / a) }
    let alpha = String(format: "%.3f", a)
    let rgb = String(format: "%.2f,%.2f,%.2f", channel(0), channel(1), channel(2))
    lines.append("\(id) \(what) -> a=\(alpha) rgb=(\(rgb))")
}

@MainActor
func run() {
    let levels: [(String, HierarchicalShapeStyle)] = [
        ("primary", .primary), ("secondary", .secondary), ("tertiary", .tertiary),
        ("quaternary", .quaternary), ("quinary", .quinary),
    ]
    let red = Color.red, blue = Color.blue, green = Color.green

    lines.append("--- table: five levels, no parent / red parent, light / dark")
    for (name, scheme, parent) in [("NL", ColorScheme.light, false), ("ND", .dark, false),
                                   ("RL", .light, true), ("RD", .dark, true)] {
        for (i, level) in levels.enumerated() {
            let id = "\(name)\(i + 1)"
            let what = "\(level.0) \(parent ? "under red" : "no parent") \(scheme == .dark ? "dark" : "light")"
            if parent {
                arm(id, what, scheme: scheme, Rectangle().foregroundStyle(level.1).foregroundStyle(red))
            } else {
                arm(id, what, scheme: scheme, Rectangle().foregroundStyle(level.1))
            }
        }
    }

    lines.append("--- P: how a level composes")
    arm("P6", "Color.secondary under red (stays grey)",
        Rectangle().foregroundStyle(Color.secondary).foregroundStyle(red))
    arm("P6d", "Color.secondary under red, dark",
        scheme: .dark, Rectangle().foregroundStyle(Color.secondary).foregroundStyle(red))
    arm("P7", ".secondary under .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(.secondary))
    arm("P8", "red -> .secondary -> .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(.secondary).foregroundStyle(red))
    arm("P9", "plain child under red -> .secondary",
        Group { Rectangle() }.foregroundStyle(.secondary).foregroundStyle(red))
    arm("P10", "red.opacity(0.5) -> .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(red.opacity(0.5)))
    arm("P11", "foregroundStyle(red, blue), child .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(red, blue))
    arm("P12", "foregroundStyle(red, blue), child .tertiary",
        Rectangle().foregroundStyle(.tertiary).foregroundStyle(red, blue))
    arm("P13", "foregroundStyle(red, blue, green), child .tertiary",
        Rectangle().foregroundStyle(.tertiary).foregroundStyle(red, blue, green))
    arm("P13b", "foregroundStyle(red, blue, green), child .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(red, blue, green))
    arm("P13c", "foregroundStyle(red, blue, green), child .quaternary",
        Rectangle().foregroundStyle(.quaternary).foregroundStyle(red, blue, green))
    let gradient = LinearGradient(colors: [red, blue], startPoint: .leading, endPoint: .trailing)
    arm("P14l", "gradient red->blue parent, child .secondary, left column",
        sample: .column(2), Rectangle().foregroundStyle(.secondary).foregroundStyle(gradient))
    arm("P14r", "gradient red->blue parent, child .secondary, right column",
        sample: .column(67), Rectangle().foregroundStyle(.secondary).foregroundStyle(gradient))
    arm("P14c", "gradient red->blue parent, child plain, left column",
        sample: .column(2), Rectangle().foregroundStyle(gradient))
    arm("P15", ".tint(green) -> foregroundStyle(.tint) -> child .secondary",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(.tint).tint(green))

    lines.append("--- S: sinks read the parent")
    for (suffix, level) in [("", HierarchicalShapeStyle.secondary), ("p", .primary)] {
        arm("S1\(suffix)", "fill(.\(suffix.isEmpty ? "secondary" : "primary")) under red",
            Rectangle().fill(level).foregroundStyle(red))
        arm("S2\(suffix)", "stroke under red",
            Rectangle().stroke(level, lineWidth: 20).foregroundStyle(red))
        arm("S3\(suffix)", "strokeBorder under red",
            Rectangle().strokeBorder(level, lineWidth: 20).foregroundStyle(red))
        arm("S4\(suffix)", "background under red",
            Color.clear.frame(width: 40, height: 40).background(level).foregroundStyle(red))
        arm("S5\(suffix)", "overlay under red",
            Color.clear.frame(width: 40, height: 40).overlay(level).foregroundStyle(red))
        arm("S6\(suffix)", "border under red",
            Color.clear.frame(width: 40, height: 40).border(level, width: 10).foregroundStyle(red))
    }
    arm("S9", ".secondary then foregroundStyle(blue)",
        Rectangle().foregroundStyle(.secondary).foregroundStyle(blue))
    arm("S9r", "foregroundStyle(blue) then .secondary (blue innermost)",
        Rectangle().foregroundStyle(blue).foregroundStyle(.secondary))

    lines.append("--- T: text and erasure")
    func glyph() -> Text { Text("\u{2588}").font(.system(size: 60)) }
    arm("T0", "Text, no style, no parent", glyph())
    arm("T2", "view-level .secondary over a Text, under red",
        VStack { VStack { glyph() }.foregroundStyle(.secondary) }.foregroundStyle(red))
    arm("T3", "Text.foregroundStyle(.secondary) under red",
        VStack { glyph().foregroundStyle(.secondary) }.foregroundStyle(red))
    arm("T3p", "Text.foregroundStyle(.primary) under red",
        VStack { glyph().foregroundStyle(.primary) }.foregroundStyle(red))
    arm("T3n", "Text.foregroundStyle(.secondary), no parent", glyph().foregroundStyle(.secondary))
    arm("T6s", "AnyShapeStyle(.secondary) on a shape, under red",
        Rectangle().foregroundStyle(AnyShapeStyle(HierarchicalShapeStyle.secondary)).foregroundStyle(red))
    arm("T6t", "Text.foregroundStyle(AnyShapeStyle(.secondary)), under red",
        VStack { glyph().foregroundStyle(AnyShapeStyle(HierarchicalShapeStyle.secondary)) }.foregroundStyle(red))
    arm("T9", "Rectangle().fill(Color.red.secondary)", Rectangle().fill(Color.red.secondary))
    arm("T9b", "Rectangle().fill(Color.red.secondary) under blue", Rectangle().fill(Color.red.secondary).foregroundStyle(blue))
}

MainActor.assumeIsolated { run() }
print(lines.joined(separator: "\n"))
