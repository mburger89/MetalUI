// SwiftUI probe: overlay and presentation patterns against MetalUI's `Deferred`
// portal, and which of a view and its `.background` content receives a click.
// Evidence for rulings CN-K (background content's hit order) and CN-Q (the
// `Deferred` deferral) in docs/superpowers/2026-09-16-containers-decisions.md.
//
// HOW TO RUN (ruling SA-O):
//
//   /usr/bin/swift docs/probes/swiftui-overlay-presentation.swift
//
// It renders with `ImageRenderer` (no window) for the P arms, and opens and
// orders out one small window per click for the H arms, with the harness of
// swiftui-content-shape-hit-region.swift (FirstMouseHost, down/spin/up).
//
// THE INSTRUMENTS.
// - P (paint): `ImageRenderer` at scale 1 renders a 100x100 view; a pixel is
//   read back through a CGContext and printed as the name of the nearest of
//   white/red/green/blue/black/clear. Pixel coordinates have their origin at the
//   top left. A `Leaf` layout logs whether a presented view is laid out at all.
// - H (hit): a real click at a window point; each handler bumps a named count.
//
// POSITIVE CONTROLS. P0: a red 20x20 centred on white reads red at (50, 50)
// and white at (5, 5) — the renderer and the readback work. P1c differs from P1
// (blue at (25, 50) with no clip), P2c from P2 (the paint-order arms read
// different colours at (50, 50)), H0 reads one tap. H1/H2 click the same view at
// two points and must disagree for the instrument to see which handler fired.
//
// RECORDED 2026-09-16 by the containers design session (critic round), macOS
// 27.0 (26A428), `/usr/bin/swift` = Apple Swift 6.4 (swiftlang-6.4.0.33.1).
// Output: see the block below (filled in from the run).
//
// READING: see the block below.

import AppKit
import SwiftUI

// MARK: - paint arms

nonisolated(unsafe) var laidOut: [String: Int] = [:]

struct Leaf: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        laidOut[name, default: 0] += 1
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        laidOut[name, default: 0] += 1
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

func colourName(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> String {
    if a < 16 { return "clear" }
    let named: [(String, (Int, Int, Int))] = [
        ("white", (255, 255, 255)), ("red", (255, 0, 0)), ("green", (0, 255, 0)),
        ("blue", (0, 0, 255)), ("black", (0, 0, 0)),
    ]
    func dist(_ c: (Int, Int, Int)) -> Int {
        abs(Int(r) - c.0) + abs(Int(g) - c.1) + abs(Int(b) - c.2)
    }
    return named.min { dist($0.1) < dist($1.1) }!.0 + "(\(r),\(g),\(b),\(a))"
}

@MainActor func pixels<V: View>(_ view: V, at points: [(Int, Int)]) -> String {
    let renderer = ImageRenderer(content: view.frame(width: 100, height: 100))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return "NO IMAGE" }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // CGContext's buffer row 0 is the TOP row of the drawn image.
    return "image \(w)x\(h); " + points.map { (x, y) in
        let i = (y * w + x) * 4
        return "(\(x), \(y)) " + colourName(data[i], data[i + 1], data[i + 2], data[i + 3])
    }.joined(separator: "; ")
}

@MainActor func paintArms() {
    print("--- P: paint, 100x100 ImageRenderer at scale 1")
    print("P0 control: red 20x20 centred on white: " + pixels(
        ZStack { Color.white; Color.red.frame(width: 20, height: 20) }, at: [(50, 50), (5, 5)]))
    print("P1c control: red 10x10 .overlay{blue 60x60} in a 20x20 frame, NOT clipped: " + pixels(
        ZStack { Color.white; Color.red.frame(width: 10, height: 10).overlay { Color.blue.frame(width: 60, height: 60) }.frame(width: 20, height: 20) },
        at: [(50, 50), (25, 50)]))
    print("P1 the same inside a .clipped() 20x20 frame (does overlay content escape an ancestor clip?): " + pixels(
        ZStack { Color.white; Color.red.frame(width: 10, height: 10).overlay { Color.blue.frame(width: 60, height: 60) }.frame(width: 20, height: 20).clipped() },
        at: [(50, 50), (25, 50)]))
    print("P2 ZStack{red 20 .overlay{blue 60}; green 40} (is overlay content hoisted over a LATER sibling?): " + pixels(
        ZStack { Color.white; Color.red.frame(width: 20, height: 20).overlay { Color.blue.frame(width: 60, height: 60) }; Color.green.frame(width: 40, height: 40) },
        at: [(50, 50), (25, 50)]))
    print("P2c control ZStack{green 40; red 20 .overlay{blue 60}}: " + pixels(
        ZStack { Color.white; Color.green.frame(width: 40, height: 40); Color.red.frame(width: 20, height: 20).overlay { Color.blue.frame(width: 60, height: 60) } },
        at: [(50, 50), (25, 50)]))
    print("P3 ZStack{red 20 .overlay{blue 60} .zIndex(1); green 40}: " + pixels(
        ZStack { Color.white; Color.red.frame(width: 20, height: 20).overlay { Color.blue.frame(width: 60, height: 60) }.zIndex(1); Color.green.frame(width: 40, height: 40) },
        at: [(50, 50), (25, 50)]))
    laidOut = [:]
    print("P4 white .sheet(isPresented: true){Leaf s: red} (is presented content in the render or layout tree?): " + pixels(
        Color.white.sheet(isPresented: .constant(true)) { Leaf(name: "s") { Color.red } },
        at: [(50, 50)]) + "; sheet content layout calls \(laidOut["s"] ?? 0)")
    laidOut = [:]
    print("P5 white .popover(isPresented: true){Leaf p: red}: " + pixels(
        Color.white.popover(isPresented: .constant(true)) { Leaf(name: "p") { Color.red } },
        at: [(50, 50)]) + "; popover content layout calls \(laidOut["p"] ?? 0)")
    laidOut = [:]
    print("P6 control white .overlay{Leaf o: red 20x20}: " + pixels(
        Color.white.overlay { Leaf(name: "o") { Color.red.frame(width: 20, height: 20) } },
        at: [(50, 50)]) + "; overlay content layout calls \(laidOut["o"] ?? 0)")
    fflush(stdout)
}

// MARK: - hit arms

final class FirstMouseHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum Count {
    nonisolated(unsafe) static var hits: [String: Int] = [:]
    static func bump(_ k: String) { hits[k, default: 0] += 1 }
    static func takeAll() -> String {
        let s = ["primary", "secondary"].map { "\($0) \(hits[$0, default: 0])" }.joined(separator: ", ")
        hits = [:]
        return s
    }
}

@MainActor func spin(_ s: Double = 0.15) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

@MainActor func makeWindow<V: View>(_ view: V) -> NSWindow {
    let w = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 200, height: 200),
                     styleMask: [.titled], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    // A first recording without the 200x200 frame and with the default
    // sizing options read the centre click as a miss and the edge click as a
    // hit on the 100x100 primary: NSHostingView had shrunk the window to its
    // fixed-size content, so (35, 100) landed on the primary's top edge.
    let host = FirstMouseHost(rootView: view.frame(width: 200, height: 200))
    host.sizingOptions = []
    w.contentView = host
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
    w.sendEvent(ev(.leftMouseDown))
    spin(0.05)
    w.sendEvent(ev(.leftMouseUp))
    spin()
}

/// Window coordinates, origin bottom left. The views are centred in a 200x200
/// window: a 100x100 primary spans 50...150, a 150x150 secondary 25...175, so
/// (100, 100) is over both and (35, 100) is over the secondary only.
@MainActor func hitArm<V: View>(_ label: String, _ make: @escaping () -> V) {
    _ = Count.takeAll()
    for (name, point) in [("centre (100,100)", CGPoint(x: 100, y: 100)), ("edge (35,100)", CGPoint(x: 35, y: 100))] {
        let w = makeWindow(make())
        click(w, at: point)
        print("  \(label) click \(name): \(Count.takeAll())")
        w.orderOut(nil)
    }
    fflush(stdout)
}

@MainActor func hitArms() {
    print("--- H: which of a view and its secondary content takes a click")
    hitArm("H0 control: red 100x100 + tap alone") {
        Color.red.frame(width: 100, height: 100).onTapGesture { Count.bump("primary") }
    }
    hitArm("H1 red 100 + tap .background{blue 150 + tap}") {
        Color.red.frame(width: 100, height: 100).onTapGesture { Count.bump("primary") }
            .background { Color.blue.frame(width: 150, height: 150).onTapGesture { Count.bump("secondary") } }
    }
    hitArm("H2 red 100 + tap .overlay{blue 150 + tap}") {
        Color.red.frame(width: 100, height: 100).onTapGesture { Count.bump("primary") }
            .overlay { Color.blue.frame(width: 150, height: 150).onTapGesture { Count.bump("secondary") } }
    }
    hitArm("H3 red 100 (no tap) .background{blue 150 + tap}") {
        Color.red.frame(width: 100, height: 100)
            .background { Color.blue.frame(width: 150, height: 150).onTapGesture { Count.bump("secondary") } }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    paintArms()
    hitArms()
}
print("DONE")
