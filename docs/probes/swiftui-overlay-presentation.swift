// SwiftUI probe: overlay and presentation patterns against MetalUI's `Deferred`
// portal, and which of a view and its `.background` content receives a click.
// Evidence for rulings CN-K (background content's hit order) and CN-Q (the
// `Deferred` deferral) in docs/superpowers/2026-09-16-containers-decisions.md,
// and — revision 2, group Q — for plan task 7 stage 5's rulings LR-CH…
// (`Deferred`'s absolute content as a presentation root laid out against the
// window) in docs/superpowers/2026-09-17-engine-replacement-decisions.md.
//
// REVISION 2 (2026-09-23, stage 5 design): appends group Q between the P and H
// arms; the P and H lines are byte-identical to revision 1's (re-run today
// before the arms were added, and again after — `diff` of the P/H lines empty).
//
// HOW TO RUN (ruling SA-O):
//
//   xcrun swiftc docs/probes/swiftui-overlay-presentation.swift -o /tmp/cn-overlay
//   OS_ACTIVITY_DT_MODE=1 /tmp/cn-overlay 2>/dev/null
//
// COMPILED FORM ONLY. The script form (`/usr/bin/swift <file>`) fails before
// running with "JIT session error: Symbols not found:
// [ ___isPlatformVersionAtLeast ]" (an availability check that `ImageRenderer`
// or `.popover` pulls in); measured 2026-09-16.
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
// 27.0 (26A428), `xcrun swiftc` = Apple Swift 6.4 (swiftlang-6.4.0.33.1).
// Exit 0. Run twice; byte-identical stdout (stderr carries only AppKit's
// linkd/intents connection noise). One harness defect was found and fixed
// before recording, described where it was fixed (NSHostingView shrank the
// window to its fixed-size content, so the first recording clicked the wrong
// points: H0's centre click missed).
//
// REVISION 2 RECORDED 2026-09-23 (PDT) by the stage-5 design session, macOS
// 27.0 (26A428), `xcrun swiftc` = Apple Swift 6.4 (swiftlang-6.4.0.33.1). Exit 0.
// Run twice; byte-identical stdout (29 lines). Positive controls for group Q:
// each Q arm reads a pixel just inside AND just outside the box it predicts
// (Q1, Q1c, Q2 — a wrong placement reads white inside or red outside); Q3c,
// Q4c, Q5c and Q6c are separating arms whose answers differ from their
// partners' (100 against 50, 20x20 against 100x100, origin against centre, 100
// against 40).
//
// READING:
// - An overlay's content is clipped by an ancestor `.clipped()` (P1 white at
//   (25, 50) against P1c's blue) and is NOT hoisted above a later sibling (P2:
//   green at the centre, where P2c reads blue); `.zIndex(1)` hoists it within
//   one ZStack (P3). So SwiftUI's `.overlay` has neither of `Deferred`'s two
//   escapes (every ancestor clip; paint order above every sibling).
// - A presented `.sheet` or `.popover` is not in the presenting view's layout
//   or render tree: its content is never laid out (0 calls) and never drawn
//   (white), where an overlay's is laid out (3 calls) and drawn (red): P4, P5
//   against P6. No layout-protocol measurement of a presentation can be taken
//   from the presenting view; it is hosted by its own window.
// - Clicks: a `.background`'s content is BENEATH the view it backs for hit
//   testing (H1: a click over both reaches the primary; the background takes
//   one only outside the primary), and an `.overlay`'s is above it (H2: the
//   overlay takes both). A primary with NO gesture still blocks the
//   background's gesture beneath it (H3: centre 0, edge 1); MetalUI's
//   non-clickable elements do not block (the kind of difference divergence 23
//   records).
// - Group Q (revision 2): placing a box against the root is spelled with
//   padding and a filling frame. One inset per axis is `.padding` on that edge
//   inside `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment:)`
//   aligned to that edge (Q1 top-leading at (5, 5); Q1c bottom-trailing at
//   (100 - 7 - 30, 100 - 9 - 20) = (63, 71)); both insets on an axis with no
//   size is a greedy frame INSIDE the padding, filling the gap (Q2: x 20..<60,
//   y 10..<70). A leading inset of 50 proposes the content 50 of the root's 100
//   (Q3), so content that answers its proposal — a wrapping text — meets the
//   root's width MINUS the inset. An overlay is proposed the size of the view
//   it is attached to — the root's 100x100 at the root, 20x20 on a 20x20 view
//   (Q4/Q4c) — and adds nothing to that view's size (Q6: 40, where the same
//   view as a stack member makes 100). An overlay aligns at the centre by
//   default and at the origin with `.topLeading` (Q5/Q5c).
//
// OUTPUT:
//
//   --- P: paint, 100x100 ImageRenderer at scale 1
//   P0 control: red 20x20 centred on white: image 100x100; (50, 50) red(255,56,60,255); (5, 5) white(255,255,255,255)
//   P1c control: red 10x10 .overlay{blue 60x60} in a 20x20 frame, NOT clipped: image 100x100; (50, 50) blue(0,136,255,255); (25, 50) blue(0,136,255,255)
//   P1 the same inside a .clipped() 20x20 frame (does overlay content escape an ancestor clip?): image 100x100; (50, 50) blue(0,136,255,255); (25, 50) white(255,255,255,255)
//   P2 ZStack{red 20 .overlay{blue 60}; green 40} (is overlay content hoisted over a LATER sibling?): image 100x100; (50, 50) green(52,199,89,255); (25, 50) blue(0,136,255,255)
//   P2c control ZStack{green 40; red 20 .overlay{blue 60}}: image 100x100; (50, 50) blue(0,136,255,255); (25, 50) blue(0,136,255,255)
//   P3 ZStack{red 20 .overlay{blue 60} .zIndex(1); green 40}: image 100x100; (50, 50) blue(0,136,255,255); (25, 50) blue(0,136,255,255)
//   P4 white .sheet(isPresented: true){Leaf s: red} (is presented content in the render or layout tree?): image 100x100; (50, 50) white(255,255,255,255); sheet content layout calls 0
//   P5 white .popover(isPresented: true){Leaf p: red}: image 100x100; (50, 50) white(255,255,255,255); popover content layout calls 0
//   P6 control white .overlay{Leaf o: red 20x20}: image 100x100; (50, 50) red(255,56,60,255); overlay content layout calls 3
//   --- Q: placing a box against the root, the spelling stage 5 lowers insets to
//   Q1 red 22x20 .padding(top 5, leading 5) .frame(max inf, .topLeading): image 100x100; (5, 5) red(255,56,60,255); (26, 24) red(255,56,60,255); (4, 4) white(255,255,255,255); (27, 25) white(255,255,255,255)
//   Q1c red 30x20 .padding(bottom 9, trailing 7) .frame(max inf, .bottomTrailing): image 100x100; (63, 71) red(255,56,60,255); (92, 90) red(255,56,60,255); (62, 70) white(255,255,255,255); (93, 91) white(255,255,255,255)
//   Q2 red .frame(max inf) .padding(top 10, leading 20, bottom 30, trailing 40): image 100x100; (20, 10) red(255,56,60,255); (59, 69) red(255,56,60,255); (19, 9) white(255,255,255,255); (60, 70) white(255,255,255,255)
//   Q3 leading inset 50 proposes to its content: 50x100; Q3c no inset: 100x100
//   Q4 overlay on the root is proposed: 100x100; Q4c overlay on a 20x20 view: 20x20
//   Q5 root .overlay{red 20x20} (default alignment): image 100x100; (50, 50) red(255,56,60,255); (5, 5) white(255,255,255,255)
//   Q5c root .overlay(alignment: .topLeading){red 20x20}: image 100x100; (50, 50) white(255,255,255,255); (5, 5) red(255,56,60,255)
//   Q6 VStack{20; 20 .overlay{60}} size: 50x40; Q6c VStack{20; 20; 60}: 50x100
//   --- H: which of a view and its secondary content takes a click
//     H0 control: red 100x100 + tap alone click centre (100,100): primary 1, secondary 0
//     H0 control: red 100x100 + tap alone click edge (35,100): primary 0, secondary 0
//     H1 red 100 + tap .background{blue 150 + tap} click centre (100,100): primary 1, secondary 0
//     H1 red 100 + tap .background{blue 150 + tap} click edge (35,100): primary 0, secondary 1
//     H2 red 100 + tap .overlay{blue 150 + tap} click centre (100,100): primary 0, secondary 1
//     H2 red 100 + tap .overlay{blue 150 + tap} click edge (35,100): primary 0, secondary 1
//     H3 red 100 (no tap) .background{blue 150 + tap} click centre (100,100): primary 0, secondary 0
//     H3 red 100 (no tap) .background{blue 150 + tap} click edge (35,100): primary 0, secondary 1
//   DONE

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

// MARK: - presentation-placement arms (revision 2, plan task 7 stage 5)

/// Logs the proposal each call receives, by name, in points ("nil" for an
/// unspecified axis), and answers its child's size.
nonisolated(unsafe) var proposals: [String: [String]] = [:]

struct ProposalLog: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        func f(_ v: CGFloat?) -> String { v.map { String(Int($0)) } ?? "nil" }
        proposals[name, default: []].append("\(f(proposal.width))x\(f(proposal.height))")
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

func lastProposal(_ name: String) -> String { proposals[name]?.last ?? "none" }

@MainActor func placementArms() {
    print("--- Q: placing a box against the root, the spelling stage 5 lowers insets to")
    // Q1/Q1c: one inset per axis. A 22x20 red box, padding on the leading and top
    // edges, inside a frame that fills the root and aligns top-leading, spans
    // x 5..<27, y 5..<25. Q1c is the trailing mirror: 30x20, padding trailing 7,
    // bottom 9, aligned bottom-trailing, spans x 63..<93, y 71..<91.
    print("Q1 red 22x20 .padding(top 5, leading 5) .frame(max inf, .topLeading): " + pixels(
        ZStack { Color.white
            Color.red.frame(width: 22, height: 20)
                .padding(EdgeInsets(top: 5, leading: 5, bottom: 0, trailing: 0))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) },
        at: [(5, 5), (26, 24), (4, 4), (27, 25)]))
    print("Q1c red 30x20 .padding(bottom 9, trailing 7) .frame(max inf, .bottomTrailing): " + pixels(
        ZStack { Color.white
            Color.red.frame(width: 30, height: 20)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 9, trailing: 7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing) },
        at: [(63, 71), (92, 90), (62, 70), (93, 91)]))
    // Q2: both insets on both axes, no size: a greedy frame inside the padding
    // fills the gap, x 20..<60, y 10..<70.
    print("Q2 red .frame(max inf) .padding(top 10, leading 20, bottom 30, trailing 40): " + pixels(
        ZStack { Color.white
            Color.red.frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 30, trailing: 40)) },
        at: [(20, 10), (59, 69), (19, 9), (60, 70)]))
    // Q3/Q3c: what a leading inset proposes to the content. Inside the 100x100
    // root, `.padding(.leading, 50)` proposes 50 wide; the control, no padding,
    // proposes 100. (A wrapping text answers at the width it is proposed.)
    proposals = [:]
    _ = pixels(ZStack { Color.white
        ProposalLog(name: "q3") { Color.red.frame(width: 10, height: 10) }
            .padding(.leading, 50)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }, at: [(0, 0)])
    _ = pixels(ZStack { Color.white
        ProposalLog(name: "q3c") { Color.red.frame(width: 10, height: 10) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }, at: [(0, 0)])
    print("Q3 leading inset 50 proposes to its content: \(lastProposal("q3")); Q3c no inset: \(lastProposal("q3c"))")
    // Q4/Q4c: an overlay is proposed the size of the view it is attached to. On
    // the 100x100 root it is proposed 100x100 (the window); on a 20x20 view
    // declared inside it, 20x20. So an overlay at the DECLARATION site is not
    // laid out against the window; one attached to the root is.
    proposals = [:]
    _ = pixels(Color.white.frame(width: 100, height: 100)
        .overlay { ProposalLog(name: "q4") { Color.red } }, at: [(0, 0)])
    _ = pixels(ZStack { Color.white
        Color.blue.frame(width: 20, height: 20).overlay { ProposalLog(name: "q4c") { Color.red } } },
        at: [(0, 0)])
    print("Q4 overlay on the root is proposed: \(lastProposal("q4")); Q4c overlay on a 20x20 view: \(lastProposal("q4c"))")
    // Q5/Q5c: an overlay's default alignment is the centre; `.topLeading` puts a
    // 20x20 at the origin.
    print("Q5 root .overlay{red 20x20} (default alignment): " + pixels(
        Color.white.frame(width: 100, height: 100).overlay { Color.red.frame(width: 20, height: 20) },
        at: [(50, 50), (5, 5)]))
    print("Q5c root .overlay(alignment: .topLeading){red 20x20}: " + pixels(
        Color.white.frame(width: 100, height: 100).overlay(alignment: .topLeading) { Color.red.frame(width: 20, height: 20) },
        at: [(50, 50), (5, 5)]))
    // Q6/Q6c: an overlay adds nothing to the size of the view it is attached to:
    // a VStack of two 20pt bars reads 40 tall with a 60pt overlay on its second
    // bar, and 100 when the same 60pt view is a third member instead.
    proposals = [:]
    var q6 = CGSize.zero, q6c = CGSize.zero
    _ = pixels(ZStack { Color.white
        VStack(spacing: 0) { Color.red.frame(width: 50, height: 20)
            Color.blue.frame(width: 50, height: 20).overlay { Color.green.frame(width: 50, height: 60) } }
            .background(GeometryReader { g in Color.clear.onAppear { q6 = g.size }.preference(key: SizeKey.self, value: g.size) })
            .onPreferenceChange(SizeKey.self) { q6 = $0 } }, at: [(0, 0)])
    _ = pixels(ZStack { Color.white
        VStack(spacing: 0) { Color.red.frame(width: 50, height: 20)
            Color.blue.frame(width: 50, height: 20); Color.green.frame(width: 50, height: 60) }
            .background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
            .onPreferenceChange(SizeKey.self) { q6c = $0 } }, at: [(0, 0)])
    print("Q6 VStack{20; 20 .overlay{60}} size: \(Int(q6.width))x\(Int(q6.height)); Q6c VStack{20; 20; 60}: \(Int(q6c.width))x\(Int(q6c.height))")
    fflush(stdout)
}

struct SizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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
    placementArms()
    hitArms()
}
print("DONE")
