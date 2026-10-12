// SwiftUI probe: overlays and coordinates (C15, user request 2026-10-02, item
// of the gpui-gap priority list; not a plan task) — a popover's
// `attachmentAnchor: .point(_:)`, `.presentationBackground(_:)` on a macOS
// popover, `onGeometryChange` in named coordinate spaces, and whether the
// environment carries a window size. Evidence for rulings OV-A… in
// docs/superpowers/2026-10-10-overlays-coords-decisions.md; spec
// docs/superpowers/specs/2026-10-10-overlays-coords-design.md. The
// compile-time arms (what spellings exist) are the companion script
// swiftui-overlays-coords-typecheck.sh.
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-overlays-coords.swift -o /tmp/ov-probe
//   /tmp/ov-probe
//
// It orders windows front (never key-dependent) and closes them; nothing is
// posted at the HID tap.
//
// THE INSTRUMENTS.
// - A (anchor): a 100 × 40 anchor centred in a 300 × 200 window; its frame in
//   window points read by `onGeometryChange(... .global)`; the popover's
//   `_NSPopoverWindow` frame is reported relative to the anchor's top-left
//   corner, in top-left-origin points (x right, y down), with the anchor's
//   size. A0 is `.rect(.bounds)` (control: must match the menus probe's P1
//   offsets); A1… are `.point(_:)` arms, each against A0 (the separating arm).
// - B (background): the popover window's view tree (class names, depth ≤ 6),
//   every NSVisualEffectView's state/material/alpha/hidden, the window's
//   `hasShadow`/`isOpaque`/`backgroundColor`, and the colour of one pixel
//   inside the popover's frame but outside its content (the panel's padding
//   ring), read from `cacheDisplay` of the window's frame view. B0 has no
//   `presentationBackground` (control); B1 `.presentationBackground(.clear)`;
//   B2 `.presentationBackground(.red)` (separating: does the call reach the
//   chrome at all).
// - G (geometry): `onGeometryChange(for: CGRect.self)` on a 40 × 20 leaf at a
//   known offset inside a container named "outer" (padding 30 inside a window
//   whose content puts the container at x 50, y 40); frames in `.local`
//   (control: origin 0), `.global`, `.named("outer")`, `.named("missing")`;
//   G2 two nested spaces named alike; G3 the named container offset by
//   `.offset(x: 7, y: 9)` (written after `coordinateSpace`); G4 the named
//   container rotated 90° (`rotationEffect`), so a translation-only and a true
//   transform disagree (separating arm); G6 the container rotated 30°, where
//   "the global bounding box mapped back" and "the element's own map composed
//   with the space's inverse" disagree (separating — at 90° they coincide);
//   G7 the same 30° on the LEAF inside the named container (an effect between
//   the space and the element; G6's global, a different named frame).
// - W (window size): every key of `EnvironmentValues`' description inside a
//   hosted view, filtered to names containing "size", "Size", "window",
//   "Window", "frame" or "Frame" (W0 control: `displayScale`'s key is listed
//   unfiltered by name `DisplayScale`).
//
// RECORDED 2026-10-10 by the C15 design session, macOS 27.0, Apple Swift
// 6.4, screen UNLOCKED (no CGSSessionScreenIsLocked line, displayAsleep main:
// 0), app activation policy `.accessory` (never key). Compiled form, run
// twice: stdout byte-identical (90 lines), stderr empty. RE-RUN 2026-10-10 by
// the C15 critic: the 90 lines reproduced byte for byte; arms G6 and G7 added,
// run twice, byte-identical (100 lines), stderr empty — the block below.
//
// WHAT IT SAYS (read before resting a ruling on an arm):
// - A: a point anchor is a zero-size rect at the unit point of the anchor's
//   bounds. A1 (`.point(.topLeading)`, `.bottom`) puts the popover window
//   centred on the point's x (-73 = -146/2) with its top at the point's y + 1;
//   A7 (`.rect(.rect(10,10,0,0))`) is A1 moved by (10,10) exactly; A4/A5/A6
//   are the other edges, centred on the point along the other axis. The
//   window (146 x 76 for 120 x 50 content) includes NSPopover's 13-pt arrow
//   margin on every side, so the arrow's tip touches the point; MetalUI's
//   popover has no arrow and keeps 8 pt instead (MN-M, divergence 112).
//   There is no placement that puts a CORNER of the popover at the point.
// - B: `.presentationBackground(_:)` reaches a macOS popover's chrome (B2's
//   red changes both the content's and the frame ring's pixel), but `.clear`
//   (B1) leaves every measured property and pixel equal to B0's: the
//   `NSPopoverFrame` / `NSGlassView` stay, `hasShadow` stays true. SwiftUI on
//   macOS has no chrome-less popover (T15: no `popoverStyle`).
// - G: `frame(in: .named("outer"))` is the frame relative to the NEAREST
//   ancestor so named (G2: 30,30, not 40,40); a name not on an ancestor
//   falls back to `.global` (G1 missing, G5 sibling); a render effect on the
//   named container (G3 offset, G4 rotation) moves `.global` but not the
//   named frame — the named space moves with its container, transform and
//   all (G4: global is the rotated bounding box 20x40, named stays 40x20;
//   G6 at 30°: global 44.6x37.3, named still exactly (30,30,40x20) — so the
//   named frame is NOT the global bounding box mapped back, which would be
//   larger). An effect between the space and the element (G7) reports the
//   element's bounding box IN the space (27.7,21.3,44.6x37.3): the same
//   bounding-box rule `.global` uses.
//   SwiftUI's `.global` here is measured from the window frame's top-left,
//   32-pt title bar included (MetalUI's is the content space, divergence 139).
// - W: no environment key's name mentions a size, window frame or bounds
//   (the four hits are dynamic type, two window actions and sidebar rows);
//   T5-T8 of the companion script refuse every plausible spelling.
//
// OUTPUT, verbatim:
//
//   --- A: attachmentAnchor
//   === A0 control .rect(.bounds) arrowEdge .bottom
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-23,40,146x76); main frame (0,0,300x232)
//   === A1 .point(.topLeading) arrowEdge .bottom
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-73,1,146x76); main frame (0,0,300x232)
//   === A2 .point(.bottomTrailing) arrowEdge .bottom
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (27,41,146x76); main frame (0,0,300x232)
//   === A3 .point(UnitPoint(x: 0.25, y: 0.5)) arrowEdge .bottom
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-48,21,146x76); main frame (0,0,300x232)
//   === A4 .point(.topLeading) arrowEdge .top
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-73,-76,146x76); main frame (0,0,300x232)
//   === A5 .point(.topLeading) arrowEdge .trailing
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (1,-37,146x76); main frame (0,0,300x232)
//   === A6 .point(.topLeading) arrowEdge .leading
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-146,-37,146x76); main frame (0,0,300x232)
//   === A7 .rect(.rect(CGRect(x: 10, y: 10, width: 0, height: 0))) arrowEdge .bottom
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-63,11,146x76); main frame (0,0,300x232)
//   --- B: presentationBackground
//   === B0 control (none)
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-23,40,146x76); main frame (0,0,300x232)
//     window hasShadow=true isOpaque=false backgroundColor=Generic Gray Gamma 2.2 Profile colorspace 0 0
//       NSPopoverFrame [effect state=0 material=0 blending=0 alpha=1 hidden=false] (0,0,146x76)
//         NSGlassView (0,0,146x76)
//           ContentHolderView (0,0,146x76)
//           _NSCoreHostingView (0,0,146x76)
//         PopoverHostingView (0,0,146x76)
//     pixel at frame-local (6, mid): rgba(0.14,0.09,0.55,1.00)
//     pixel at frame centre (content): rgba(0.86,0.86,0.86,1.00)
//   === B1 .presentationBackground(.clear)
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-23,40,146x76); main frame (0,0,300x232)
//     window hasShadow=true isOpaque=false backgroundColor=Generic Gray Gamma 2.2 Profile colorspace 0 0
//       NSPopoverFrame [effect state=0 material=0 blending=0 alpha=1 hidden=false] (0,0,146x76)
//         NSGlassView (0,0,146x76)
//           ContentHolderView (0,0,146x76)
//           _NSCoreHostingView (0,0,146x76)
//         PopoverHostingView (0,0,146x76)
//     pixel at frame-local (6, mid): rgba(0.14,0.09,0.55,1.00)
//     pixel at frame centre (content): rgba(0.86,0.86,0.86,1.00)
//   === B2 .presentationBackground(.red)
//     control (not shown): popover window none
//     anchor (global) (100,112,100x40); popover window rel anchor top-left (-23,40,146x76); main frame (0,0,300x232)
//     window hasShadow=true isOpaque=false backgroundColor=Generic Gray Gamma 2.2 Profile colorspace 0 0
//       NSPopoverFrame [effect state=0 material=0 blending=0 alpha=1 hidden=false] (0,0,146x76)
//         NSGlassView (0,0,146x76)
//           ContentHolderView (0,0,146x76)
//           _NSCoreHostingView (0,0,146x76)
//         PopoverHostingView (0,0,146x76)
//     pixel at frame-local (6, mid): rgba(0.95,0.43,0.38,1.00)
//     pixel at frame centre (content): rgba(0.99,0.90,0.90,1.00)
//   --- G: named coordinate spaces
//   === G1 leaf padded 30 in named container at (50,40)
//     local: (0,0,40x20)
//     global: (80,102,40x20)
//     named(outer): (30,30,40x20)
//     named(missing): (80,102,40x20)
//   === G2 nested spaces both named outer (inner at +10)
//     local: (0,0,40x20)
//     global: (90,112,40x20)
//     named(outer): (30,30,40x20)
//     named(missing): (90,112,40x20)
//   === G3 named container .offset(x: 7, y: 9)
//     local: (0,0,40x20)
//     global: (87,111,40x20)
//     named(outer): (30,30,40x20)
//     named(missing): (87,111,40x20)
//   === G4 named container .rotationEffect(90°)
//     local: (0,0,40x20)
//     global: (90,92,20x40)
//     named(outer): (30,30,40x20)
//     named(missing): (90,92,20x40)
//   === G5 space named on a sibling
//     local: (0,0,40x20)
//     global: (70,72,40x20)
//     named(outer): (70,72,40x20)
//     named(missing): (70,72,40x20)
//   === G6 named container .rotationEffect(30°)
//     local: (0,0,40x20)
//     global: (77.7,93.3,44.6x37.3)
//     named(outer): (30,30,40x20)
//     named(missing): (77.7,93.3,44.6x37.3)
//   === G7 leaf .rotationEffect(30°) inside the named container
//     local: (0,0,40x20)
//     global: (77.7,93.3,44.6x37.3)
//     named(outer): (27.7,21.3,44.6x37.3)
//     named(missing): (77.7,93.3,44.6x37.3)
//   --- W: window size in the environment
//     W total distinct *Key names: 39
//     W0 control DisplayScale listed: true
//     W1 names containing size/window/frame: ["DynamicTypeSizeKey", "EnvironmentValues.DismissWindowActionKey", "EnvironmentValues.WithCurrentWindowKey", "SidebarRowSize.Key"]
//   === W environment keys

import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)
@MainActor func spin(_ s: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

final class Model: ObservableObject {
    @Published var shown = false
    @Published var anchor: CGRect = .zero
}
final class Frames: @unchecked Sendable { var lines: [String: CGRect] = [:] }
let frames = Frames()

var windows: [NSWindow] = []
@MainActor func host<V: View>(_ name: String, _ v: V, size: CGSize = CGSize(width: 300, height: 200),
                              origin: CGPoint = CGPoint(x: 400, y: 500)) -> NSHostingView<V> {
    let w = NSWindow(contentRect: NSRect(origin: origin, size: size),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    let h = NSHostingView(rootView: v)
    w.contentView = h
    w.orderFrontRegardless(); h.layoutSubtreeIfNeeded(); spin(0.4)
    print("=== \(name)"); windows.append(w)
    return h
}
func r(_ x: CGFloat) -> String { x == x.rounded() ? "\(Int(x))" : String(format: "%.1f", x) }
func rect(_ f: CGRect) -> String { "(\(r(f.minX)),\(r(f.minY)),\(r(f.width))x\(r(f.height)))" }

// ---------------------------------------------------------------- A, B
struct PopHost: View {
    @ObservedObject var m: Model
    let anchorSpec: PopoverAttachmentAnchor
    let edge: Edge
    let background: Int   // 0 none, 1 clear, 2 red
    var body: some View {
        Color.gray.frame(width: 100, height: 40)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { m.anchor = $0 }
            .popover(isPresented: $m.shown, attachmentAnchor: anchorSpec, arrowEdge: edge) {
                content
            }
            .frame(width: 300, height: 200)
    }
    @ViewBuilder var content: some View {
        switch background {
        case 1: Text("Popover").frame(width: 120, height: 50).presentationBackground(.clear)
        case 2: Text("Popover").frame(width: 120, height: 50).presentationBackground(.red)
        default: Text("Popover").frame(width: 120, height: 50)
        }
    }
}

@MainActor func popoverWindow() -> NSWindow? {
    NSApp.windows.first { "\(type(of: $0))".contains("Popover") && $0.isVisible }
}

@MainActor func showPopover(_ name: String, anchor: PopoverAttachmentAnchor, edge: Edge,
                            background: Int = 0) -> (NSWindow, NSWindow?) {
    let m = Model()
    let h = host(name, PopHost(m: m, anchorSpec: anchor, edge: edge, background: background))
    print("  control (not shown): popover window \(popoverWindow() == nil ? "none" : "PRESENT")")
    m.shown = true; spin(0.9)
    let main = h.window!
    guard let pw = popoverWindow() else { print("  popover window: none"); return (main, nil) }
    // The anchor's top-left in screen points (bottom-left origin), then the
    // popover window's frame relative to it, y flipped to grow downward.
    // SwiftUI's `.global` on macOS 27 is measured from the window FRAME's
    // top-left (the 32-pt title bar included: G1's global y is 102 for a
    // leaf 70 below the content's top), so the frame, not the content rect,
    // converts it.
    let ax = main.frame.minX + m.anchor.minX, ayTop = main.frame.maxY - m.anchor.minY
    let f = pw.frame
    let rel = CGRect(x: f.minX - ax, y: ayTop - f.maxY, width: f.width, height: f.height)
    print("  anchor (global) \(rect(m.anchor)); popover window rel anchor top-left \(rect(rel)); main frame \(rect(main.frame.offsetBy(dx: -main.frame.minX, dy: -main.frame.minY)))")
    return (main, pw)
}

@MainActor func closePopover(_ main: NSWindow, _ pw: NSWindow?) {
    pw?.orderOut(nil); main.orderOut(nil)
}

@MainActor func viewTree(_ v: NSView, _ d: Int = 0, maxDepth: Int = 6) {
    var s = String(repeating: "  ", count: d + 2) + "\(type(of: v))".components(separatedBy: "<").first!
    if let e = v as? NSVisualEffectView {
        s += " [effect state=\(e.state.rawValue) material=\(e.material.rawValue) blending=\(e.blendingMode.rawValue) alpha=\(r(e.alphaValue)) hidden=\(e.isHidden)]"
    }
    if v.isHidden { s += " hidden" }
    if v.alphaValue != 1 { s += " alpha=\(r(v.alphaValue))" }
    s += " \(rect(v.frame))"
    print(s)
    if d < maxDepth { for k in v.subviews { viewTree(k, d + 1, maxDepth: maxDepth) } }
}

@MainActor func pixel(_ pw: NSWindow, atTopLeft p: CGPoint) -> String {
    guard let frameView = pw.contentView?.superview ?? pw.contentView else { return "no view" }
    let b = frameView.bounds
    guard let rep = frameView.bitmapImageRepForCachingDisplay(in: b) else { return "no rep" }
    frameView.cacheDisplay(in: b, to: rep)
    let px = Int(p.x * CGFloat(rep.pixelsWide) / b.width), py = Int(p.y * CGFloat(rep.pixelsHigh) / b.height)
    guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return "no colour" }
    return String(format: "rgba(%.2f,%.2f,%.2f,%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

// ---------------------------------------------------------------- G
struct GeoLeaf: View {
    let tag: String
    var body: some View {
        Color.blue.frame(width: 40, height: 20)
            .onGeometryChange(for: [CGRect].self, of: { p in
                [p.frame(in: .local), p.frame(in: .global), p.frame(in: .named("outer")), p.frame(in: .named("missing"))]
            }) { v in
                frames.lines[tag + " local"] = v[0]; frames.lines[tag + " global"] = v[1]
                frames.lines[tag + " named(outer)"] = v[2]; frames.lines[tag + " named(missing)"] = v[3]
            }
    }
}
struct G1: View {   // container at (50,40) in a 300x200 window, leaf padded 30
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G1").padding(30).background(Color.yellow)
                .coordinateSpace(.named("outer"))
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G2: View {   // two nested spaces named "outer": inner one at +30,+30
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G2").padding(30).coordinateSpace(.named("outer"))
                .padding(10).coordinateSpace(.named("outer"))
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G3: View {   // named container then .offset(7, 9)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G3").padding(30).coordinateSpace(.named("outer")).offset(x: 7, y: 9)
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G4: View {   // named container rotated 90 degrees about its centre
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G4").padding(30).coordinateSpace(.named("outer")).rotationEffect(.degrees(90))
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G6: View {   // named container rotated 30 degrees: a bounding box of the global frame mapped back is not the named frame (separating)
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G6").padding(30).coordinateSpace(.named("outer")).rotationEffect(.degrees(30))
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G7: View {   // an effect BETWEEN the named container and the leaf: the leaf rotated 30 degrees inside it
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeoLeaf(tag: "G7").rotationEffect(.degrees(30)).padding(30).coordinateSpace(.named("outer"))
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}
struct G5: View {   // the space declared on a sibling, not an ancestor
    var body: some View {
        HStack(spacing: 0) {
            Color.green.frame(width: 20, height: 20).coordinateSpace(.named("outer"))
            GeoLeaf(tag: "G5")
        }
        .padding(.leading, 50).padding(.top, 40)
        .frame(width: 300, height: 200, alignment: .topLeading)
    }
}

// ---------------------------------------------------------------- W
struct EnvDump: View {
    @Environment(\.self) var env
    var body: some View {
        let d = String(describing: env)
        Text("env").onAppear {
            // Keys are printed as `KeyName = value` or `EnvironmentPropertyKey<KeyName>`.
            let pattern = try! NSRegularExpression(pattern: "(?:EnvironmentPropertyKey<|PropertyKey<)?([A-Za-z_.]+Key)\\b")
            let ns = d as NSString
            var keys = Set<String>()
            for m in pattern.matches(in: d, range: NSRange(location: 0, length: ns.length)) {
                keys.insert(ns.substring(with: m.range(at: 1)))
            }
            let all = keys.sorted()
            print("  W total distinct *Key names: \(all.count)")
            print("  W0 control DisplayScale listed: \(all.contains { $0.contains("DisplayScale") })")
            let hits = all.filter { k in ["size", "Size", "window", "Window", "frame", "Frame"].contains { k.contains($0) } }
            print("  W1 names containing size/window/frame: \(hits)")
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    print("--- A: attachmentAnchor")
    let arms: [(String, PopoverAttachmentAnchor, Edge)] = [
        ("A0 control .rect(.bounds) arrowEdge .bottom", .rect(.bounds), .bottom),
        ("A1 .point(.topLeading) arrowEdge .bottom", .point(.topLeading), .bottom),
        ("A2 .point(.bottomTrailing) arrowEdge .bottom", .point(.bottomTrailing), .bottom),
        ("A3 .point(UnitPoint(x: 0.25, y: 0.5)) arrowEdge .bottom", .point(UnitPoint(x: 0.25, y: 0.5)), .bottom),
        ("A4 .point(.topLeading) arrowEdge .top", .point(.topLeading), .top),
        ("A5 .point(.topLeading) arrowEdge .trailing", .point(.topLeading), .trailing),
        ("A6 .point(.topLeading) arrowEdge .leading", .point(.topLeading), .leading),
        ("A7 .rect(.rect(CGRect(x: 10, y: 10, width: 0, height: 0))) arrowEdge .bottom",
         .rect(.rect(CGRect(x: 10, y: 10, width: 0, height: 0))), .bottom),
    ]
    for (name, anchor, edge) in arms {
        let (main, pw) = showPopover(name, anchor: anchor, edge: edge)
        closePopover(main, pw); spin(0.3)
    }

    print("--- B: presentationBackground")
    for (i, name) in ["B0 control (none)", "B1 .presentationBackground(.clear)", "B2 .presentationBackground(.red)"].enumerated() {
        let (main, pw) = showPopover(name, anchor: .rect(.bounds), edge: .bottom, background: i)
        if let pw {
            print("  window hasShadow=\(pw.hasShadow) isOpaque=\(pw.isOpaque) backgroundColor=\(pw.backgroundColor.map { "\($0)" } ?? "nil")")
            if let frameView = pw.contentView?.superview { viewTree(frameView) } else if let cv = pw.contentView { viewTree(cv) }
            // The pixel 6 pt inside the popover frame from its left edge, at
            // its vertical middle — outside the 120 × 50 content.
            let mid = CGPoint(x: 6, y: pw.frame.height / 2)
            print("  pixel at frame-local (6, mid): \(pixel(pw, atTopLeft: mid))")
            print("  pixel at frame centre (content): \(pixel(pw, atTopLeft: CGPoint(x: pw.frame.width / 2, y: pw.frame.height / 2)))")
        }
        closePopover(main, pw); spin(0.3)
    }

    print("--- G: named coordinate spaces")
    for (name, view) in [("G1 leaf padded 30 in named container at (50,40)", AnyView(G1())),
                         ("G2 nested spaces both named outer (inner at +10)", AnyView(G2())),
                         ("G3 named container .offset(x: 7, y: 9)", AnyView(G3())),
                         ("G4 named container .rotationEffect(90°)", AnyView(G4())),
                         ("G5 space named on a sibling", AnyView(G5())),
                         ("G6 named container .rotationEffect(30°)", AnyView(G6())),
                         ("G7 leaf .rotationEffect(30°) inside the named container", AnyView(G7()))] {
        let h = host(name, view)
        let tag = String(name.prefix(2))
        for kind in ["local", "global", "named(outer)", "named(missing)"] {
            print("  \(kind): \(frames.lines["\(tag) \(kind)"].map(rect) ?? "never reported")")
        }
        h.window!.orderOut(nil)
    }

    print("--- W: window size in the environment")
    let wh = host("W environment keys", EnvDump())
    spin(0.3)
    wh.window!.orderOut(nil)
    exit(0)
}
