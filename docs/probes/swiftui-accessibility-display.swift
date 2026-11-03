// SwiftUI probe: accessibility display settings (R3-10 item 7; rulings AD-* in
// docs/superpowers/2026-11-02-accessibility-display-decisions.md, record 194).
//
// HOW TO RUN (SA-O's compiled form; the screen must be unlocked for arms H, C, D, B, I, L1:
//   xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate
//   prints no CGSSessionScreenIsLocked line and `displayAsleep main: 0`):
//
//   xcrun swiftc docs/probes/swiftui-accessibility-display.swift -o "$TMPDIR/ad-probe" && "$TMPDIR/ad-probe" 2>&1 | grep -v 'Connection\]'
//
// GROUPS.
//   A   API surface, by compiling one-line snippets with `swiftc -typecheck`: positive reads of
//       every key, separating arms (`.environment(\.key, v)` on a get-only key fails; on
//       legibilityWeight it compiles; LegibilityWeight.allCases fails).
//   V0  a bare EnvironmentValues() read of every key (the defaults a struct must match).
//   H0  a hosted NSHostingView in a real window reads every key via @Environment, beside the
//       machine's NSWorkspace values.
//   H1  the three NSWorkspace display getters are swizzled in-process and the display-options
//       notification posted (the system setting is never touched): does the hosted value move?
//       (Record 315's T0 said no for Reduce Transparency.)
//   C0  Color.primary/.secondary/.gray/.accentColor resolved with _colorSchemeContrast
//       .standard vs .increased.
//   C1 D1 B1 I1  NSHostingView + cacheDisplay of Button (.bordered/.borderless/.plain), Toggle
//       (.switch/.checkbox), Divider, TextField(.roundedBorder), Picker(.segmented), with the
//       underscored setter off then on; the count of differing bytes per control.
//   L1  Text ink width under legibilityWeight nil / .regular / .bold (ImageRenderer).
//
// RECORDED OUTPUT (2026-11-02, macOS 27.2, Apple Swift 6.4, screen unlocked; two runs identical):
//   --- A: API surface (swiftc -typecheck -warnings-as-errors)
//     A positive: read @Environment(\.colorSchemeContrast): compiles (no warning)
//     A positive: read @Environment(\.accessibilityDifferentiateWithoutColor): compiles (no warning)
//     A positive: read @Environment(\.accessibilityInvertColors): compiles (no warning)
//     A positive: read @Environment(\.accessibilityShowButtonShapes): compiles (no warning)
//     A positive: read @Environment(\.accessibilityDimFlashingLights): compiles (no warning)
//     A positive: read @Environment(\.accessibilityPlayAnimatedImages): compiles (no warning)
//     A positive: read @Environment(\.legibilityWeight): compiles (no warning)
//     A separating: write .environment(\.colorSchemeContrast, .increased): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, ColorSchemeContrast>' to expected argument type 'WritableKeyPath<EnvironmentValues, ColorSchemeContrast>'
//     A separating: write .environment(\.accessibilityDifferentiateWithoutColor, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A separating: write .environment(\.accessibilityInvertColors, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A separating: write .environment(\.accessibilityShowButtonShapes, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A separating: write .environment(\.accessibilityDimFlashingLights, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A separating: write .environment(\.accessibilityPlayAnimatedImages, true): ERROR cannot convert value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
//     A separating: write .environment(\.legibilityWeight, .bold): compiles (no warning)
//     A positive: accessibilityShowBorders (macOS 11 spelling): compiles (no warning)
//     A positive: accessibilityVoiceOverEnabled (not built): compiles (no warning)
//     A separating: LegibilityWeight.allCases: ERROR type 'LegibilityWeight' has no member 'allCases'
//     A positive: ColorSchemeContrast.allCases: compiles (no warning)
//     A positive: LegibilityWeight is Hashable: compiles (no warning)
//   --- V0: a bare EnvironmentValues()
//     V0 contrast=standard differentiate=false invert=false showBorders=false dimFlashing=false playAnimatedImages=false legibilityWeight=nil
//   --- H0: hosted view in a real window; machine values beside
//     H0 NSWorkspace: increaseContrast=false differentiate=false invert=false reduceMotion=false reduceTransparency=false
//     H0 hosted @Environment: contrast=standard differentiate=false invert=false showBorders=false dimFlashing=false playAnimatedImages=true legibilityWeight=nil
//   --- H1: swizzled NSWorkspace getters + display-options notification
//     H1 getters=false/false/false; hosted: nil (no re-render, value unchanged)
//     H1 getters=true/true/true; hosted: contrast=increased differentiate=true invert=true showBorders=false dimFlashing=false playAnimatedImages=true legibilityWeight=nil
//   --- C0: Color.resolve(in:) under _colorSchemeContrast
//     C0 primary: standard (0.000,0.000,0.000,0.847), increased (0.000,0.000,0.000,1.000), DIFFERS
//     C0 secondary: standard (0.000,0.000,0.000,0.498), increased (0.000,0.000,0.000,0.757), DIFFERS
//     C0 gray: standard (0.557,0.557,0.576,1.000), increased (0.412,0.412,0.431,1.000), DIFFERS
//     C0 accentColor: standard (0.000,0.533,1.000,1.000), increased (0.118,0.431,0.957,1.000), DIFFERS
//     C0 blue: standard (0.000,0.533,1.000,1.000), increased (0.118,0.431,0.957,1.000), DIFFERS
//   --- C1/D1/B1/I1: cacheDisplay of each control, underscored setter off vs on
//     C1 _colorSchemeContrast standard vs increased:
//       C1 Button .bordered: off-vs-off 0 bytes differ of 19968; off-vs-on 1908 bytes differ of 19968
//       C1 Button .borderless: off-vs-off 0 bytes differ of 15360; off-vs-on 0 bytes differ of 15360
//       C1 Button .plain: off-vs-off 0 bytes differ of 8960; off-vs-on 158 bytes differ of 8960
//       C1 Toggle .switch: off-vs-off 0 bytes differ of 24576; off-vs-on 225 bytes differ of 24576
//       C1 Toggle .checkbox: off-vs-off 0 bytes differ of 18368; off-vs-on 564 bytes differ of 18368
//       C1 Divider: off-vs-off 0 bytes differ of 67200; off-vs-on 306 bytes differ of 67200
//       C1 TextField .roundedBorder: off-vs-off 0 bytes differ of 46080; off-vs-on 0 bytes differ of 46080
//       C1 Picker .segmented: off-vs-off 0 bytes differ of 24576; off-vs-on 154 bytes differ of 24576
//       C1 Gallery: off-vs-off 0 bytes differ of 216960; off-vs-on 3225 bytes differ of 216960
//     D1 _accessibilityDifferentiateWithoutColor false vs true:
//       D1 Button .bordered: off-vs-off 0 bytes differ of 19968; off-vs-on 0 bytes differ of 19968
//       D1 Button .borderless: off-vs-off 0 bytes differ of 15360; off-vs-on 0 bytes differ of 15360
//       D1 Button .plain: off-vs-off 0 bytes differ of 8960; off-vs-on 0 bytes differ of 8960
//       D1 Toggle .switch: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       D1 Toggle .checkbox: off-vs-off 0 bytes differ of 18368; off-vs-on 0 bytes differ of 18368
//       D1 Divider: off-vs-off 0 bytes differ of 67200; off-vs-on 0 bytes differ of 67200
//       D1 TextField .roundedBorder: off-vs-off 0 bytes differ of 46080; off-vs-on 0 bytes differ of 46080
//       D1 Picker .segmented: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       D1 Gallery: off-vs-off 0 bytes differ of 216960; off-vs-on 0 bytes differ of 216960
//     B1 _accessibilityShowButtonShapes false vs true:
//       B1 Button .bordered: off-vs-off 0 bytes differ of 19968; off-vs-on 242 bytes differ of 19968
//       B1 Button .borderless: off-vs-off 0 bytes differ of 15360; off-vs-on 0 bytes differ of 15360
//       B1 Button .plain: off-vs-off 0 bytes differ of 8960; off-vs-on 0 bytes differ of 8960
//       B1 Toggle .switch: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       B1 Toggle .checkbox: off-vs-off 0 bytes differ of 18368; off-vs-on 90 bytes differ of 18368
//       B1 Divider: off-vs-off 0 bytes differ of 67200; off-vs-on 0 bytes differ of 67200
//       B1 TextField .roundedBorder: off-vs-off 0 bytes differ of 46080; off-vs-on 0 bytes differ of 46080
//       B1 Picker .segmented: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       B1 Gallery: off-vs-off 0 bytes differ of 216960; off-vs-on 332 bytes differ of 216960
//     I1 _accessibilityInvertColors false vs true:
//       I1 Button .bordered: off-vs-off 0 bytes differ of 19968; off-vs-on 0 bytes differ of 19968
//       I1 Button .borderless: off-vs-off 0 bytes differ of 15360; off-vs-on 0 bytes differ of 15360
//       I1 Button .plain: off-vs-off 0 bytes differ of 8960; off-vs-on 0 bytes differ of 8960
//       I1 Toggle .switch: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       I1 Toggle .checkbox: off-vs-off 0 bytes differ of 18368; off-vs-on 0 bytes differ of 18368
//       I1 Divider: off-vs-off 0 bytes differ of 67200; off-vs-on 0 bytes differ of 67200
//       I1 TextField .roundedBorder: off-vs-off 0 bytes differ of 46080; off-vs-on 0 bytes differ of 46080
//       I1 Picker .segmented: off-vs-off 0 bytes differ of 24576; off-vs-on 0 bytes differ of 24576
//       I1 Gallery: off-vs-off 0 bytes differ of 216960; off-vs-on 0 bytes differ of 216960
//   --- L1: Text ink width under legibilityWeight (ImageRenderer, scale 1)
//     L1 nil: ink width 207
//     L1 .regular: ink width 207
//     L1 .bold: ink width 218
//
// READING. A: all six non-weight keys are READ-ONLY (a KeyPath, not Writable); legibilityWeight is
// writable; LegibilityWeight is not CaseIterable, ColorSchemeContrast is; accessibilityShowButtonShapes
// reads without a warning. V0: a BARE EnvironmentValues() reads playAnimatedImages == false (the
// plan guessed true), so the struct's default is false; a hosted app reads true (H0), so a platform
// that has no setting answers true explicitly. H1: unlike record 315's T0 (Reduce Transparency),
// swizzling NSWorkspace's contrast / differentiate / invert getters and posting the display-options
// notification DID move the hosted values (the first "off" pass printed nil only because nothing
// re-rendered: the values were unchanged); show-borders, dim-flashing and animated-images are not
// NSWorkspace values and stayed. C0/C1: colorSchemeContrast .increased changes Color.primary/
// .secondary/.gray/.accentColor and the pixels of Button .bordered and .plain, Toggle both styles,
// Divider and Picker .segmented (TextField and Button .borderless: no difference) -> divergence 1076.
// D1: differentiateWithoutColor changes nothing in any built-in control here -> a section-05 row,
// label 1077 unused. B1: showButtonShapes changes Button .bordered and Toggle .checkbox -> 1078.
// I1: invertColors changes nothing here -> section-05 row, 1080 unused. L1: legibilityWeight .bold
// widens Text ink (207 -> 218), .regular equals nil -> 1079 (Text does not read it). H0:
// legibilityWeight reads nil in a hosted view, so the window stamps none.
import SwiftUI
import AppKit
import ObjectiveC

func compiles(_ body: String) -> String {
    let dir = NSTemporaryDirectory() + "ad-\(UInt32.random(in: 0...UInt32.max))"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let src = dir + "/s.swift"
    try? ("import SwiftUI\n" + body + "\n").write(toFile: src, atomically: true, encoding: .utf8)
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = ["swiftc", "-typecheck", "-warnings-as-errors", src]
    let pipe = Pipe(); p.standardError = pipe; p.standardOutput = pipe
    try? p.run(); p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    if p.terminationStatus == 0 { return "compiles (no warning)" }
    let line = out.split(separator: "\n").first { $0.contains("error:") }.map { String($0.split(separator: ":", maxSplits: 4).last ?? "") } ?? "?"
    return "ERROR" + line
}

func armA() {
    print("--- A: API surface (swiftc -typecheck -warnings-as-errors)")
    let keys = ["colorSchemeContrast", "accessibilityDifferentiateWithoutColor", "accessibilityInvertColors",
                "accessibilityShowButtonShapes", "accessibilityDimFlashingLights", "accessibilityPlayAnimatedImages",
                "legibilityWeight"]
    for k in keys {
        print("  A positive: read @Environment(\\.\(k)): \(compiles("struct V: View { @Environment(\\.\(k)) var r; var body: some View { Text(\"\\(String(describing: r))\") } }"))")
    }
    let writes: [(String, String)] = [
        ("colorSchemeContrast", ".increased"), ("accessibilityDifferentiateWithoutColor", "true"),
        ("accessibilityInvertColors", "true"), ("accessibilityShowButtonShapes", "true"),
        ("accessibilityDimFlashingLights", "true"), ("accessibilityPlayAnimatedImages", "true"),
        ("legibilityWeight", ".bold"),
    ]
    for (k, v) in writes {
        print("  A separating: write .environment(\\.\(k), \(v)): \(compiles("func f() -> some View { Text(\"x\").environment(\\.\(k), \(v)) }"))")
    }
    print("  A positive: accessibilityShowBorders (macOS 11 spelling): \(compiles("struct V: View { @Environment(\\.accessibilityShowBorders) var r; var body: some View { Text(r ? \"a\" : \"b\") } }"))")
    print("  A positive: accessibilityVoiceOverEnabled (not built): \(compiles("struct V: View { @Environment(\\.accessibilityVoiceOverEnabled) var r; var body: some View { Text(r ? \"a\" : \"b\") } }"))")
    print("  A separating: LegibilityWeight.allCases: \(compiles("let a = LegibilityWeight.allCases"))")
    print("  A positive: ColorSchemeContrast.allCases: \(compiles("let a = ColorSchemeContrast.allCases"))")
    print("  A positive: LegibilityWeight is Hashable: \(compiles("let a: Set<LegibilityWeight> = [.bold]"))")
}

struct Probe {
    var contrast: String, diff: Bool, invert: Bool, borders: Bool, flashing: Bool, anim: Bool, weight: String
    var line: String { "contrast=\(contrast) differentiate=\(diff) invert=\(invert) showBorders=\(borders) dimFlashing=\(flashing) playAnimatedImages=\(anim) legibilityWeight=\(weight)" }
}
func weightName(_ w: LegibilityWeight?) -> String { w.map { $0 == .bold ? "bold" : "regular" } ?? "nil" }
func probe(_ e: EnvironmentValues) -> Probe {
    Probe(contrast: e.colorSchemeContrast == .increased ? "increased" : "standard", diff: e.accessibilityDifferentiateWithoutColor,
          invert: e.accessibilityInvertColors, borders: e.accessibilityShowButtonShapes, flashing: e.accessibilityDimFlashingLights,
          anim: e.accessibilityPlayAnimatedImages, weight: weightName(e.legibilityWeight))
}

nonisolated(unsafe) var hosted: Probe? = nil
struct HostedReader: View {
    @Environment(\.colorSchemeContrast) var c
    @Environment(\.accessibilityDifferentiateWithoutColor) var d
    @Environment(\.accessibilityInvertColors) var i
    @Environment(\.accessibilityShowButtonShapes) var b
    @Environment(\.accessibilityDimFlashingLights) var f
    @Environment(\.accessibilityPlayAnimatedImages) var a
    @Environment(\.legibilityWeight) var w
    var body: some View {
        hosted = Probe(contrast: c == .increased ? "increased" : "standard", diff: d, invert: i, borders: b, flashing: f, anim: a, weight: weightName(w))
        return Color.clear.frame(width: 1, height: 1)
    }
}

@MainActor func makeWindow<V: View>(_ v: V, size: CGSize) -> (NSWindow, NSHostingView<V>) {
    let host = NSHostingView(rootView: v)
    let win = NSWindow(contentRect: NSRect(x: 200, y: 400, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = host
    win.appearance = NSAppearance(named: .aqua)
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    return (win, host)
}
@MainActor func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5)) }

@MainActor func armV0() {
    print("--- V0: a bare EnvironmentValues()")
    print("  V0 \(probe(EnvironmentValues()).line)")
}

@MainActor func armH0() {
    print("--- H0: hosted view in a real window; machine values beside")
    let ws = NSWorkspace.shared
    print("  H0 NSWorkspace: increaseContrast=\(ws.accessibilityDisplayShouldIncreaseContrast) differentiate=\(ws.accessibilityDisplayShouldDifferentiateWithoutColor) invert=\(ws.accessibilityDisplayShouldInvertColors) reduceMotion=\(ws.accessibilityDisplayShouldReduceMotion) reduceTransparency=\(ws.accessibilityDisplayShouldReduceTransparency)")
    hosted = nil
    let (win, _) = makeWindow(HostedReader(), size: CGSize(width: 20, height: 20))
    settle()
    print("  H0 hosted @Environment: \(hosted?.line ?? "nil (did not render)")")
    win.orderOut(nil)
}

nonisolated(unsafe) var forceContrast = false
nonisolated(unsafe) var forceDiff = false
nonisolated(unsafe) var forceInvert = false
final class DispSwizzle: NSObject {
    @objc dynamic var c: Bool { forceContrast }
    @objc dynamic var d: Bool { forceDiff }
    @objc dynamic var i: Bool { forceInvert }
}
func swizzle(_ sel: Selector, _ repl: Selector) {
    let orig = class_getInstanceMethod(NSWorkspace.self, sel)!
    let r = class_getInstanceMethod(DispSwizzle.self, repl)!
    method_setImplementation(orig, method_getImplementation(r))
}

@MainActor func armH1() {
    print("--- H1: swizzled NSWorkspace getters + display-options notification")
    swizzle(#selector(getter: NSWorkspace.accessibilityDisplayShouldIncreaseContrast), #selector(getter: DispSwizzle.c))
    swizzle(#selector(getter: NSWorkspace.accessibilityDisplayShouldDifferentiateWithoutColor), #selector(getter: DispSwizzle.d))
    swizzle(#selector(getter: NSWorkspace.accessibilityDisplayShouldInvertColors), #selector(getter: DispSwizzle.i))
    let (win, _) = makeWindow(HostedReader(), size: CGSize(width: 20, height: 20))
    for on in [false, true] {
        forceContrast = on; forceDiff = on; forceInvert = on
        hosted = nil
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        settle()
        let w = NSWorkspace.shared
        print("  H1 getters=\(w.accessibilityDisplayShouldIncreaseContrast)/\(w.accessibilityDisplayShouldDifferentiateWithoutColor)/\(w.accessibilityDisplayShouldInvertColors); hosted: \(hosted?.line ?? "nil (no re-render, value unchanged)")")
    }
    forceContrast = false; forceDiff = false; forceInvert = false
    win.orderOut(nil)
}

@MainActor func armC0() {
    print("--- C0: Color.resolve(in:) under _colorSchemeContrast")
    func fmt(_ r: Color.Resolved) -> String { String(format: "(%.3f,%.3f,%.3f,%.3f)", r.red, r.green, r.blue, r.opacity) }
    for (n, c) in [("primary", Color.primary), ("secondary", Color.secondary), ("gray", Color.gray), ("accentColor", Color.accentColor), ("blue", Color.blue)] {
        var std = EnvironmentValues(); std._colorSchemeContrast = .standard
        var inc = EnvironmentValues(); inc._colorSchemeContrast = .increased
        let a = fmt(c.resolve(in: std)), b = fmt(c.resolve(in: inc))
        print("  C0 \(n): standard \(a), increased \(b), \(a == b ? "equal" : "DIFFERS")")
    }
}

struct Gallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Bordered") {}.buttonStyle(.bordered)
            Button("Borderless") {}.buttonStyle(.borderless)
            Button("Plain") {}.buttonStyle(.plain)
            Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch)
            Toggle("Checkbox", isOn: .constant(true)).toggleStyle(.checkbox)
            Divider()
            TextField("Field", text: .constant("text")).textFieldStyle(.roundedBorder)
            Picker("Seg", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented)
        }.padding(12).frame(width: 240)
    }
}

@MainActor func capture<V: View>(_ v: V, size: CGSize) -> [UInt8] {
    let (win, host) = makeWindow(v, size: size)
    settle()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { win.orderOut(nil); return [] }
    host.cacheDisplay(in: host.bounds, to: rep)
    win.orderOut(nil)
    guard let d = rep.bitmapData else { return [] }
    return Array(UnsafeBufferPointer(start: d, count: rep.bytesPerRow * rep.pixelsHigh))
}
func diffCount(_ a: [UInt8], _ b: [UInt8]) -> String {
    if a.isEmpty || b.isEmpty { return "capture failed" }
    if a.count != b.count { return "sizes differ \(a.count) vs \(b.count)" }
    var n = 0; for i in 0..<a.count where a[i] != b[i] { n += 1 }
    return "\(n) bytes differ of \(a.count)"
}

@MainActor func armPixels() {
    print("--- C1/D1/B1/I1: cacheDisplay of each control, underscored setter off vs on")
    let size = CGSize(width: 264, height: 320)
    func controls() -> [(String, AnyView)] {
        [("Button .bordered", AnyView(Button("Bordered") {}.buttonStyle(.bordered).padding(12))),
         ("Button .borderless", AnyView(Button("Borderless") {}.buttonStyle(.borderless).padding(12))),
         ("Button .plain", AnyView(Button("Plain") {}.buttonStyle(.plain).padding(12))),
         ("Toggle .switch", AnyView(Toggle("Switch", isOn: .constant(true)).toggleStyle(.switch).padding(12))),
         ("Toggle .checkbox", AnyView(Toggle("Checkbox", isOn: .constant(true)).toggleStyle(.checkbox).padding(12))),
         ("Divider", AnyView(VStack { Text("a"); Divider(); Text("b") }.padding(12))),
         ("TextField .roundedBorder", AnyView(TextField("Field", text: .constant("text")).textFieldStyle(.roundedBorder).padding(12))),
         ("Picker .segmented", AnyView(Picker("Seg", selection: .constant(1)) { Text("A").tag(1); Text("B").tag(2) }.pickerStyle(.segmented).padding(12))),
         ("Gallery", AnyView(Gallery()))]
    }
    let small = CGSize(width: 240, height: 80)
    func run(_ tag: String, _ label: String, off: (AnyView) -> AnyView, on: (AnyView) -> AnyView) {
        print("  \(tag) \(label):")
        for (n, v) in controls() {
            let sz = n == "Gallery" ? size : small
            // Capture the off state twice first: a nonzero off-vs-off diff means the capture is not stable.
            let a0 = capture(off(v), size: sz)
            let a1 = capture(off(v), size: sz)
            let b = capture(on(v), size: sz)
            print("    \(tag) \(n): off-vs-off \(diffCount(a0, a1)); off-vs-on \(diffCount(a0, b))")
        }
    }
    run("C1", "_colorSchemeContrast standard vs increased",
        off: { AnyView($0.environment(\._colorSchemeContrast, .standard)) }, on: { AnyView($0.environment(\._colorSchemeContrast, .increased)) })
    run("D1", "_accessibilityDifferentiateWithoutColor false vs true",
        off: { AnyView($0.environment(\._accessibilityDifferentiateWithoutColor, false)) }, on: { AnyView($0.environment(\._accessibilityDifferentiateWithoutColor, true)) })
    run("B1", "_accessibilityShowButtonShapes false vs true",
        off: { AnyView($0.environment(\._accessibilityShowButtonShapes, false)) }, on: { AnyView($0.environment(\._accessibilityShowButtonShapes, true)) })
    run("I1", "_accessibilityInvertColors false vs true",
        off: { AnyView($0.environment(\._accessibilityInvertColors, false)) }, on: { AnyView($0.environment(\._accessibilityInvertColors, true)) })
}

func inkWidth(_ cg: CGImage) -> Int {
    let w = cg.width, h = cg.height
    var d = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &d, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var lo = w, hi = -1
    for y in 0..<h { for x in 0..<w where d[(y * w + x) * 4] < 128 { lo = min(lo, x); hi = max(hi, x) } }
    return hi < 0 ? 0 : hi - lo + 1
}
@MainActor func armL1() {
    print("--- L1: Text ink width under legibilityWeight (ImageRenderer, scale 1)")
    for (n, w) in [("nil", nil), (".regular", LegibilityWeight.regular), (".bold", LegibilityWeight.bold)] as [(String, LegibilityWeight?)] {
        let r = ImageRenderer(content: Text("Legibility weight sample").font(.system(size: 20)).foregroundStyle(.black).padding(4).background(.white).environment(\.legibilityWeight, w))
        r.scale = 1
        print("  L1 \(n): ink width \(r.cgImage.map(inkWidth) ?? -1)")
    }
}

MainActor.assumeIsolated {
    armA(); armV0()
    _ = NSApplication.shared
    if CommandLine.arguments.contains("--no-window") == false {
        armH0(); armH1(); armC0(); armPixels()
    }
    armL1()
}
