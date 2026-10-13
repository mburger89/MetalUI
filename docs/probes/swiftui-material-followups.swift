// SwiftUI probe: material follow-ups (C27; rulings MT-* in
// docs/superpowers/2026-10-12-material-followups-decisions.md, spec
// docs/superpowers/specs/2026-10-12-material-followups-design.md).
//
// HOW TO RUN (SA-O's compiled form; the screen must be unlocked for arm T:
//   xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate
//   prints no CGSSessionScreenIsLocked line and `displayAsleep main: 0`):
//
//   xcrun swiftc docs/probes/swiftui-material-followups.swift -o /tmp/mf-probe && /tmp/mf-probe 2>&1 | grep -v 'Connection\]'
//
// GROUPS.
//   A  API surface, by compiling one-line snippets with `swiftc -typecheck`. Each snippet has
//      a positive control (the spelling is known good) and a separating arm (a spelling that
//      would exist if SwiftUI exposed a material's tint or took a colour).
//   O  Material.opacity(_:) (a ShapeStyle method): over a uniform white and a uniform black
//      backdrop, the material at opacity 1 and 0.5 (ImageRenderer, light). Does the opacity
//      scale the tint (a half-weight composite over the backdrop)?
//   T  Reduce Transparency, in a REAL window (ImageRenderer ignores the setting; BB-I's probe
//      T read the same pixels both ways). NSWorkspace.accessibilityDisplayShouldReduceTransparency
//      is swizzled in-process (the system setting is never touched). T0 is the positive
//      control: a hosted view reading @Environment(\.accessibilityReduceTransparency) — does
//      the swizzle reach SwiftUI at all? T1: the window's pixel over a uniform white and a
//      uniform black backdrop, per material and scheme, with the setting off and on.
//
// RECORDED OUTPUT (2026-10-12, macOS 27.0.1, Apple Swift 6.4, screen unlocked):
//   --- A: API surface (swiftc -typecheck)
//     A0 positive: Rectangle().fill(Material.regularMaterial): compiles
//     A1 Material.opacity(0.5) as a fill: compiles
//     A2 separating: Material.tint(.red): ERROR cannot call value of non-function type 'TintShapeStyle'
//     A3 separating: material.color: ERROR value of type 'Material' has no member 'color'
//     A4 separating: material.fill(for:): ERROR static member 'fill' cannot be used on instance of type 'Material'
//     A5 separating: Material(tint:): ERROR 'Material' cannot be constructed because it has no accessible initializers
//     A6 separating: m.resolve(in:) as a Color: compiles
//     A7 positive: resolve(in:) exists and returns Never: compiles
//     A8 positive: read @Environment(\.accessibilityReduceTransparency): compiles
//     A9 separating: write .environment(\.accessibilityReduceTransparency, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A10 positive: .materialActiveAppearance (macOS 15): compiles
//   --- O: Material.opacity (ImageRenderer, light; red channel at the centre)
//     O regular over white: opacity 1 -> 239, opacity 0.5 -> 246, backdrop alone -> 255
//     O ultraThin over white: opacity 1 -> 246, opacity 0.5 -> 250, backdrop alone -> 255
//     O regular over black: opacity 1 -> 150, opacity 0.5 -> 77, backdrop alone -> 0
//     O ultraThin over black: opacity 1 -> 94, opacity 0.5 -> 49, backdrop alone -> 0
//   --- T: Reduce Transparency in a real window (swizzled getter)
//     T0 positive control: getter reads false; @Environment reads Optional(false)
//     T0 positive control: getter reads true; @Environment reads Optional(false)
//     T1 light ultraThin: reduce=false: over white 246, over black 92; reduce=true: over white 246, over black 92;
//     T1 light thin: reduce=false: over white 242, over black 119; reduce=true: over white 242, over black 119;
//     T1 light regular: reduce=false: over white 238, over black 149; reduce=true: over white 238, over black 149;
//     T1 light thick: reduce=false: over white 234, over black 177; reduce=true: over white 234, over black 177;
//     T1 light ultraThick: reduce=false: over white 230, over black 206; reduce=true: over white 230, over black 206;
//     T1 light bar: reduce=false: over white 255, over black 255; reduce=true: over white 255, over black 255;
//     T1 dark ultraThin: reduce=false: over white 169, over black 25; reduce=true: over white 169, over black 25;
//     T1 dark thin: reduce=false: over white 149, over black 29; reduce=true: over white 149, over black 29;
//     T1 dark regular: reduce=false: over white 126, over black 33; reduce=true: over white 126, over black 33;
//     T1 dark thick: reduce=false: over white 106, over black 37; reduce=true: over white 106, over black 37;
//     T1 dark ultraThick: reduce=false: over white 86, over black 41; reduce=true: over white 86, over black 41;
//     T1 dark bar: reduce=false: over white 40, over black 40; reduce=true: over white 40, over black 40;
//
// READING. A: SwiftUI has no public tint read, no tint-taking material and no material
// initialiser (A2-A5 fail where the positive controls A0/A1/A7/A8/A10 compile); A6 compiles
// only because resolve(in:) returns Never (A7), which converts to anything -- it is no read.
// opacity(_:) exists (A1). The environment key is READ-ONLY (A9: a KeyPath, not Writable).
// O: Material.opacity(0.5) halves the tint's weight over the backdrop (regular over black
// 150 -> 77, over white 239 -> 246): it composites the whole material at half, no blur change
// measured. T: INCONCLUSIVE AGAIN, now with a positive control that FAILS: T0 shows the swizzled
// getter reads true while SwiftUI's own @Environment(\.accessibilityReduceTransparency) still
// reads false, so the setting reaches SwiftUI by a path the swizzle cannot move, and T1's pixels
// are identical with it off and on. SwiftUI's fallback colour per material is therefore NOT
// measured (MT-F rules one; human check MT-1 compares against the real setting). Only the system
// setting would move it, and an agent does not touch the user's system settings.
import SwiftUI
import AppKit
import ObjectiveC

func compiles(_ body: String) -> String {
    let dir = NSTemporaryDirectory() + "mf-\(UInt32.random(in: 0...UInt32.max))"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let src = dir + "/s.swift"
    try? ("import SwiftUI\n" + body + "\n").write(toFile: src, atomically: true, encoding: .utf8)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = ["swiftc", "-typecheck", src]
    let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if p.terminationStatus == 0 { return "compiles" }
    let line = out.split(separator: "\n").first { $0.contains("error:") }.map { String($0.split(separator: ":", maxSplits: 4).last ?? "") } ?? "?"
    return "ERROR" + line
}

func armA() {
    print("--- A: API surface (swiftc -typecheck)")
    let arms: [(String, String)] = [
        ("A0 positive: Rectangle().fill(Material.regularMaterial)", "func f() -> some View { Rectangle().fill(Material.regularMaterial) }"),
        ("A1 Material.opacity(0.5) as a fill", "func f() -> some View { Rectangle().fill(Material.regularMaterial.opacity(0.5)) }"),
        ("A2 separating: Material.tint(.red)", "func f() -> some View { Rectangle().fill(Material.regularMaterial.tint(.red)) }"),
        ("A3 separating: material.color", "func f(_ m: Material) -> Color { m.color }"),
        ("A4 separating: material.fill(for:)", "func f(_ m: Material) -> Color { m.fill(for: .light) }"),
        ("A5 separating: Material(tint:)", "func f() -> Material { Material(tint: .red) }"),
        ("A6 separating: m.resolve(in:) as a Color", "func f(_ m: Material, e: EnvironmentValues) -> Color { m.resolve(in: e) }"),
        ("A7 positive: resolve(in:) exists and returns Never", "func f(_ m: Material, e: EnvironmentValues) { let r: Never = m.resolve(in: e); _ = r }"),
        ("A8 positive: read @Environment(\\.accessibilityReduceTransparency)", "struct V: View { @Environment(\\.accessibilityReduceTransparency) var r; var body: some View { Text(r ? \"a\" : \"b\") } }"),
        ("A9 separating: write .environment(\\.accessibilityReduceTransparency, true)", "func f() -> some View { Text(\"x\").environment(\\.accessibilityReduceTransparency, true) }"),
        ("A10 positive: .materialActiveAppearance (macOS 15)", "func f() -> some View { Text(\"x\").materialActiveAppearance(.inactive) }"),
    ]
    for (name, src) in arms { print("  \(name): \(compiles(src))") }
}

struct Bitmap { let w: Int; let h: Int; let bytes: [UInt8] }
func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return Bitmap(w: w, h: h, bytes: d)
}
func rgb(_ b: Bitmap, _ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * b.w + x) * 4; return (Int(b.bytes[i]), Int(b.bytes[i + 1]), Int(b.bytes[i + 2])) }

@MainActor func render(_ v: some View, scheme: ColorScheme) -> Bitmap {
    let r = ImageRenderer(content: v.frame(width: 40, height: 40).environment(\.colorScheme, scheme))
    r.scale = 1
    return bytes(of: r.cgImage!)
}

@MainActor func armO() {
    print("--- O: Material.opacity (ImageRenderer, light; red channel at the centre)")
    for (bn, bc) in [("white", Color.white), ("black", Color.black)] {
        for (mn, m) in [("regular", Material.regularMaterial), ("ultraThin", .ultraThinMaterial)] {
            let full = rgb(render(ZStack { bc; Rectangle().fill(m) }, scheme: .light), 20, 20).0
            let half = rgb(render(ZStack { bc; Rectangle().fill(m.opacity(0.5)) }, scheme: .light), 20, 20).0
            print("  O \(mn) over \(bn): opacity 1 -> \(full), opacity 0.5 -> \(half), backdrop alone -> \(bn == "white" ? 255 : 0)")
        }
    }
}

nonisolated(unsafe) var forceReduceTransparency = false
final class RTSwizzle: NSObject { @objc dynamic var fake: Bool { forceReduceTransparency } }
func installSwizzle() {
    let orig = class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceTransparency))!
    let repl = class_getInstanceMethod(RTSwizzle.self, #selector(getter: RTSwizzle.fake))!
    method_setImplementation(orig, method_getImplementation(repl))
}

nonisolated(unsafe) var envReading: Bool? = nil
struct EnvReader: View {
    @Environment(\.accessibilityReduceTransparency) var r
    var body: some View { envReading = r; return Color.clear.frame(width: 1, height: 1) }
}

@MainActor func windowRed(_ m: Material?, back: Color, dark: Bool, tag: String) -> Int {
    let content = ZStack { back; if let m { Rectangle().fill(m) }; EnvReader() }
        .frame(width: 60, height: 60)
        .environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: content)
    let win = NSWindow(contentRect: NSRect(x: 200, y: 400, width: 60, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.8))
    let path = "/tmp/mf-win-\(tag).png"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", String(win.windowNumber), path]
    try? p.run(); p.waitUntilExit()
    win.orderOut(nil)
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return -1 }
    let b = bytes(of: cg)
    return rgb(b, b.w / 2, b.h / 2).0
}

@MainActor func armT() {
    print("--- T: Reduce Transparency in a real window (swizzled getter)")
    _ = NSApplication.shared
    installSwizzle()
    for on in [false, true] {
        forceReduceTransparency = on
        envReading = nil
        _ = windowRed(nil, back: .white, dark: false, tag: "t0")
        print("  T0 positive control: getter reads \(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency); @Environment reads \(String(describing: envReading))")
    }
    let mats: [(String, Material)] = [("ultraThin", .ultraThinMaterial), ("thin", .thinMaterial), ("regular", .regularMaterial), ("thick", .thickMaterial), ("ultraThick", .ultraThickMaterial), ("bar", .bar)]
    for dark in [false, true] {
        for (n, m) in mats {
            var row = "  T1 \(dark ? "dark" : "light") \(n):"
            for on in [false, true] {
                forceReduceTransparency = on
                let w = windowRed(m, back: .white, dark: dark, tag: "w")
                let k = windowRed(m, back: .black, dark: dark, tag: "k")
                row += " reduce=\(on): over white \(w), over black \(k);"
            }
            print(row)
        }
    }
}

MainActor.assumeIsolated {
    armA(); armO()
    if CommandLine.arguments.contains("--no-window") == false { armT() }
}
