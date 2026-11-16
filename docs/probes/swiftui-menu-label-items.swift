// SwiftUI probe: image and `Label` items in a menu (Alloy request, 2026-11-15)
// — `Button(_:systemImage:action:)`, `Button { } label: { Label(…) }`,
// `Toggle(_:systemImage:isOn:)`, `Menu(_:systemImage:)`, and what a tint
// (`.foregroundStyle`, `.tint`, `.symbolRenderingMode`) does to the item's
// image in the `NSMenu` SwiftUI builds on macOS. Evidence for ruling MN-AP in
// docs/superpowers/2026-10-02-menus-popovers-decisions.md; record 322.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-menu-label-items.swift -o /tmp/menu-label-probe
//   /tmp/menu-label-probe
//
// Headless and self-exiting: the `NSMenu` is read from the hit view under a
// synthesized right-mouse event (`menu(for:)`, as swiftui-menus-popovers.swift
// C1); nothing is shown or tracked. For each item the probe prints the
// title, `image` (size, `isTemplate`), the image's centre-pixel RGBA after
// drawing it into a bitmap (black alpha = a template, not yet tinted by the
// menu; a coloured pixel = a non-template, the colour is baked in) and
// `attributedTitle`.
//
// POSITIVE CONTROL / SEPARATING ARMS. L0 (`Button("T")`, no image): image nil.
// L1 against L2: the `systemImage:` spelling against the `Label` spelling.
// L3/L4/L5 against L2: each tint spelling against the untinted label.
//
// RECORDED 2026-11-15, macOS 27.0, Apple Swift 6.4; compiled form, run twice,
// stdout byte-identical, exit 0.
//
// FINDINGS (read before resting a ruling on them):
// - An image reaches the NSMenuItem from `Button(_:systemImage:)`, from a
//   `Label` (L1, L2), from a bare `Image` beside a `Text` in the label (L8),
//   on a `Toggle(_:systemImage:)` (L9, with state=on) and on a `Menu(_:
//   systemImage:)` submenu item and the items inside it (L10). Disabled items
//   keep their image (L11). `role: .destructive` adds no tint (L14).
// - An untinted image is a TEMPLATE `NSImage` (15x15 for a 14pt symbol; the
//   size follows the glyph): AppKit paints it in the menu's text colour.
// - `.foregroundStyle(.green)` on the Label, the Button, the label's Image or
//   the `systemImage:` button changes nothing: still a black template (L3,
//   L3b, L3c, L5, L5b, L5c). Only `.tint(.green)` on the Button (L4) makes a
//   NON-template image with the colour baked in (system green), and
//   `.symbolRenderingMode(.palette)` with `.foregroundStyle(.green)` on the
//   Image does the same (L6b). `.multicolor` on a one-layer symbol stays a
//   template (L6).
// - A bitmap `Image(nsImage:)` in a Label is a non-template image at its own
//   size (L7, L7b: `.resizable().frame` is ignored).
// - An unknown symbol name or asset name yields no image, silently (L12, L15).
// - `labelStyle(.titleOnly)` drops the image (L13), `.iconOnly` leaves an
//   empty title (L13b). `Text.foregroundStyle` gives an attributed title (L16).
//
// OUTPUT, verbatim:
//
//   === L0 control: Button(T)
//     "T" image=nil
//   === L1 Button(T, systemImage: circle.fill)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L2 Button { Label(T, systemImage: circle.fill) }
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L3 Button { Label(...).foregroundStyle(.green) }
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L3b Button { Label(...) }.foregroundStyle(.green)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L3c Button(T, systemImage:).foregroundStyle(.green)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L4 Button { Label }.tint(.green)
//     "T" image(size=15x15 template=false rgba=(0.19,0.82,0.35,1.00))
//   === L5 Label icon: Image(systemName).foregroundStyle(.green)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L5b label: HStack { Image(systemName).foregroundStyle(.green); Text }
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L5c label: { Image(systemName:).foregroundStyle(.green); Text(T) } (no stack)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L6 Label icon: Image(systemName).symbolRenderingMode(.multicolor)
//     "T" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L6b Label icon: Image(systemName).symbolRenderingMode(.palette).foregroundStyle(.green)
//     "T" image(size=15x15 template=false rgba=(0.19,0.82,0.35,1.00))
//   === L7 Label icon: Image(nsImage: red 16x16 bitmap)
//     "T" image(size=16x16 template=false rgba=(1.00,0.00,0.00,1.00))
//   === L7b same bitmap resizable().frame(12x12)
//     "T" image(size=16x16 template=false rgba=(1.00,0.00,0.00,1.00))
//   === L8 Button { Image(systemName:); Text } plain content, no Label
//     "T" image(size=17x16 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L9 Toggle(T, systemImage:, isOn:)
//     "T" state=on image(size=17x16 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L10 Menu(T, systemImage:) { Button(Sub, systemImage:) }
//     "T" image(size=19x14 template=true rgba=(0.00,0.00,0.00,1.00)) submenu:
//       "Sub" image(size=17x16 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L11 Button(T, systemImage:).disabled(true)
//     "T" disabled image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L12 Button(T, systemImage: no.such.symbol)
//     "T" image=nil
//   === L13 Label.labelStyle(.titleOnly)
//     "T" image=nil
//   === L13b Label.labelStyle(.iconOnly)
//     "" image(size=15x15 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L14 Button(T, systemImage:, role: .destructive)
//     "T" image(size=15x17 template=true rgba=(0.00,0.00,0.00,1.00))
//   === L15 Label(T, image: asset name that does not exist)
//     "T" image=nil
//   === L16 Text(T) alone inside Button label with .foregroundStyle(.red)
//     "T" image=nil attributedTitle
//   --- end
//
import SwiftUI
import AppKit

@MainActor func spin(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(x: 300, y: 400, width: 300, height: 200), styleMask: [.titled],
                     backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); w.makeKey(); h.layoutSubtreeIfNeeded(); spin(0.3)
    print("=== \(name)"); windows.append(w)
    return h
}
@MainActor func menuOf<V: View>(_ h: NSHostingView<V>) -> NSMenu? {
    let w = h.window!
    let pt = CGPoint(x: h.bounds.midX, y: h.bounds.midY)
    let e = NSEvent.mouseEvent(with: .rightMouseDown, location: pt, modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    return (h.hitTest(h.convert(pt, from: nil)) ?? h).menu(for: e)
}
@MainActor func pixel(_ image: NSImage) -> String {
    let s = 64
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: s, pixelsHigh: s, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return "?" }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    NSGraphicsContext.restoreGraphicsState()
    // The most opaque pixel stands for the glyph's colour.
    var best: NSColor?
    for y in 0..<s { for x in 0..<s {
        if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > (best?.alphaComponent ?? 0.5) { best = c }
    } }
    guard let c = best else { return "transparent" }
    return String(format: "rgba=(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}
@MainActor func dump(_ m: NSMenu?, _ d: Int = 1) {
    guard let m else { print("  menu: nil"); return }
    for item in m.items {
        let pad = String(repeating: "  ", count: d)
        if item.isSeparatorItem { print(pad + "----"); continue }
        var s = pad + "\"\(item.title)\""
        if !item.isEnabled { s += " disabled" }
        if item.state == .on { s += " state=on" }
        if let i = item.image {
            s += " image(size=\(Int(i.size.width))x\(Int(i.size.height)) template=\(i.isTemplate) \(pixel(i)))"
        } else { s += " image=nil" }
        if item.attributedTitle != nil { s += " attributedTitle" }
        if item.submenu != nil { s += " submenu:" }
        print(s)
        if let sub = item.submenu { dump(sub, d + 1) }
    }
}

final class Model: ObservableObject { @Published var flag = true }
let bitmap: NSImage = {
    let i = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
        NSColor.red.setFill(); r.fill(); return true
    }
    return i
}()

struct Target<C: View>: View {
    let c: C
    var body: some View { Text("Target").frame(width: 200, height: 100).contextMenu { c } }
}
@MainActor func arm<C: View>(_ name: String, @ViewBuilder _ c: () -> C) {
    let h = host(name, Target(c: c())); dump(menuOf(h))
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    let m = Model()
    arm("L0 control: Button(T)") { Button("T") {} }
    arm("L1 Button(T, systemImage: circle.fill)") { Button("T", systemImage: "circle.fill") {} }
    arm("L2 Button { Label(T, systemImage: circle.fill) }") { Button { } label: { Label("T", systemImage: "circle.fill") } }
    arm("L3 Button { Label(...).foregroundStyle(.green) }") {
        Button { } label: { Label("T", systemImage: "circle.fill").foregroundStyle(.green) } }
    arm("L3b Button { Label(...) }.foregroundStyle(.green)") {
        Button { } label: { Label("T", systemImage: "circle.fill") }.foregroundStyle(.green) }
    arm("L3c Button(T, systemImage:).foregroundStyle(.green)") {
        Button("T", systemImage: "circle.fill") {}.foregroundStyle(.green) }
    arm("L4 Button { Label }.tint(.green)") {
        Button { } label: { Label("T", systemImage: "circle.fill") }.tint(.green) }
    arm("L5 Label icon: Image(systemName).foregroundStyle(.green)") {
        Button { } label: { Label { Text("T") } icon: { Image(systemName: "circle.fill").foregroundStyle(.green) } } }
    arm("L5b label: HStack { Image(systemName).foregroundStyle(.green); Text }") {
        Button { } label: { HStack { Image(systemName: "circle.fill").foregroundStyle(.green); Text("T") } } }
    arm("L5c label: { Image(systemName:).foregroundStyle(.green); Text(T) } (no stack)") {
        Button { } label: { Image(systemName: "circle.fill").foregroundStyle(.green); Text("T") } }
    arm("L6 Label icon: Image(systemName).symbolRenderingMode(.multicolor)") {
        Button { } label: { Label { Text("T") } icon: { Image(systemName: "circle.fill").symbolRenderingMode(.multicolor) } } }
    arm("L6b Label icon: Image(systemName).symbolRenderingMode(.palette).foregroundStyle(.green)") {
        Button { } label: { Label { Text("T") } icon: { Image(systemName: "circle.fill").symbolRenderingMode(.palette).foregroundStyle(.green) } } }
    arm("L7 Label icon: Image(nsImage: red 16x16 bitmap)") {
        Button { } label: { Label { Text("T") } icon: { Image(nsImage: bitmap) } } }
    arm("L7b same bitmap resizable().frame(12x12)") {
        Button { } label: { Label { Text("T") } icon: { Image(nsImage: bitmap).resizable().frame(width: 12, height: 12) } } }
    arm("L8 Button { Image(systemName:); Text } plain content, no Label") {
        Button { } label: { Image(systemName: "star"); Text("T") } }
    arm("L9 Toggle(T, systemImage:, isOn:)") { Toggle("T", systemImage: "star", isOn: Binding(get: { m.flag }, set: { m.flag = $0 })) }
    arm("L10 Menu(T, systemImage:) { Button(Sub, systemImage:) }") {
        Menu("T", systemImage: "folder") { Button("Sub", systemImage: "star") {} } }
    arm("L11 Button(T, systemImage:).disabled(true)") { Button("T", systemImage: "circle.fill") {}.disabled(true) }
    arm("L12 Button(T, systemImage: no.such.symbol)") { Button("T", systemImage: "no.such.symbol.xyz") {} }
    arm("L13 Label.labelStyle(.titleOnly)") {
        Button { } label: { Label("T", systemImage: "circle.fill").labelStyle(.titleOnly) } }
    arm("L13b Label.labelStyle(.iconOnly)") {
        Button { } label: { Label("T", systemImage: "circle.fill").labelStyle(.iconOnly) } }
    arm("L14 Button(T, systemImage:, role: .destructive)") {
        Button("T", systemImage: "trash", role: .destructive) {} }
    arm("L15 Label(T, image: asset name that does not exist)") {
        Button { } label: { Label("T", image: "NoSuchAsset") } }
    arm("L16 Text(T) alone inside Button label with .foregroundStyle(.red)") {
        Button { } label: { Text("T").foregroundStyle(.red) } }
    print("--- end")
}
exit(0)
