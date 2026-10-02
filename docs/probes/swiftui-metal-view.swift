// SwiftUI probe: an app-owned GPU surface (rulings MV-A onward,
// docs/superpowers/2026-10-01-metal-view-decisions.md). SwiftUI has no
// `MetalView`; its closest analogues are `Canvas` (immediate drawing,
// re-run when its inputs change), `TimelineView(.animation)` (a continuous
// redraw schedule) and an `NSViewRepresentable` wrapping `MTKView` (app-owned
// Metal, composited by Core Animation). This probe asks how each SIZES, how
// each is COMPOSITED under clip/opacity, and when `Canvas` RE-RUNS.
//
// HOW TO RUN (SA-O's two forms), from the repository root, with the screen
// UNLOCKED (group C and R order a window front and capture it with
// `screencapture -l`; the lock probe must print no CGSSessionScreenIsLocked
// line and `displayAsleep main: 0`):
//
//   xcrun swiftc docs/probes/swiftui-metal-view.swift -o /tmp/mv-probe && /tmp/mv-probe
//   /usr/bin/swift docs/probes/swiftui-metal-view.swift
//
// INSTRUMENTS, each with a positive control:
// - `Probe`, a recording `Layout` that asks its one subview `sizeThatFits`
//   at a list of proposals and prints each answer. Control P1: a fixed
//   40×20 frame against a proposal-taking `Color` — the answers differ.
// - a real window, ordered front, captured by id (`screencapture -x -o -l`),
//   read back as pixels at points scaled by the backing scale. Control P2: a
//   red `Color` under `.clipShape(RoundedRectangle(cornerRadius: 20))` —
//   centre red, corner white (so the capture sees colour AND a clip).
// - a counter incremented inside a `Canvas` renderer closure. Control P3: a
//   change to a value the closure reads raises the count.
//
// GROUPS.
// - G: sizing at five proposals — Canvas (G1), an MTKView representable with
//   the default `sizeThatFits` (G2), TimelineView(.animation){Canvas} (G3).
// - C: compositing in the window — an MTKView clearing pure red, bare (C1),
//   under `.clipShape(RoundedRectangle(cornerRadius: 20))` (C2), under
//   `.opacity(0.5)` (C3); a red Canvas under the same clip (C4). D1: the
//   MTKView's drawableSize against its bounds × backingScaleFactor.
// - R: Canvas re-runs — after an unrelated sibling @State change (R1), after
//   a change to a value it reads (R2, = P3), with no change at all over 0.5 s
//   (R0, idle); R3 a Canvas in its own equatable child view over the same
//   unrelated change (separates "the declaring body re-ran" from "anything
//   in the window changed").
//
// RECORDED OUTPUT: see the block at the end of this header (filled in by the
// run that produced it, never by hand).
//
// RECORDED 2026-10-01 by the metal-view design, macOS 27.0, Apple Swift 6.4,
// screen unlocked (lock probe: no CGSSessionScreenIsLocked line,
// `displayAsleep main: 0`, one screen at scale 2.0):
//
// (G lines deduplicated: SwiftUI asks the `Probe` layout several times per
// pass; every repeat printed the same answer.)
//
//   == G
//   P1 fixed40x20 proposal nilxnil -> 40x20
//   P1 fixed40x20 proposal 0x0 -> 40x20
//   P1 fixed40x20 proposal 50x30 -> 40x20
//   P1 fixed40x20 proposal 300x200 -> 40x20
//   P1 fixed40x20 proposal infxinf -> 40x20
//   P1 Color proposal nilxnil -> 10x10
//   P1 Color proposal 0x0 -> 0x0
//   P1 Color proposal 50x30 -> 50x30
//   P1 Color proposal 300x200 -> 300x200
//   P1 Color proposal infxinf -> infxinf
//   G1 Canvas proposal nilxnil -> 10x10
//   G1 Canvas proposal 0x0 -> 0x0
//   G1 Canvas proposal 50x30 -> 50x30
//   G1 Canvas proposal 300x200 -> 300x200
//   G1 Canvas proposal infxinf -> infxinf
//   G2 MTKViewRep proposal nilxnil -> 0x0
//   G2 MTKViewRep proposal 0x0 -> 0x0
//   G2 MTKViewRep proposal 50x30 -> 50x30
//   G2 MTKViewRep proposal 300x200 -> 300x200
//   G2 MTKViewRep proposal infxinf -> infxinf
//   G3 TimelineCanvas proposal nilxnil -> 10x10
//   G3 TimelineCanvas proposal 0x0 -> 0x0
//   G3 TimelineCanvas proposal 50x30 -> 50x30
//   G3 TimelineCanvas proposal 300x200 -> 300x200
//   G3 TimelineCanvas proposal infxinf -> infxinf
//   == C, R
//   window backingScaleFactor 2.0 titleBar 32.0
//   capture 760x424
//   P2 Color+clip centre (241,106,96) corner(2,2) (255,254,255) outside(-5,30) (255,254,255)
//   C1 MTKView centre (240,74,45) corner(2,2) (240,74,45) outside(-5,30) (255,254,255)
//   C2 MTKView+clip centre (240,74,45) corner(2,2) (255,254,255) outside(-5,30) (255,254,255)
//   C3 MTKView+opacity0.5 centre (247,171,161) corner(2,2) (247,171,161) outside(-5,30) (255,254,255)
//   C4 Canvas+clip centre (241,106,96) corner(2,2) (255,254,255) outside(-5,30) (255,254,255)
//   D1 MTKView bounds (100.0, 60.0) drawableSize (200.0, 120.0) windowScale 2.0 draws(2s, default isPaused=false) 128
//   R0 idle 0.5s: canvas runs 1 -> 1
//   R1 unrelated sibling change: canvas runs 1 -> 2
//   R3 isolated canvas, same change: runs 1 -> 1
//   R2/P3 read value change: canvas runs 2 -> 3
//
// READING.
// - G1/G3: Canvas (and a TimelineView around it) is a greedy leaf exactly
//   like `Color` (P1): the proposal on every finite axis, 10 on a nil axis,
//   inf at inf. G2: an MTKView representable answers the proposal too but 0
//   on a nil axis (MTKView has no intrinsic size).
// - C1–C3 against P2: SwiftUI composites the app's Metal layer with the
//   same clip and opacity as any view — C2's corner reads the white
//   background (clipped, as P2's), C1's the surface's own red (unclipped
//   control); C3's centre is the 50 % mix of C1's red over white.
//   C4: Canvas clips identically. Colours read through the capture's
//   colour space, so only relations (equal / white / mixed) are claimed.
// - D1: the MTKView's drawable is its bounds × the window's backing scale
//   (100×60 pt → 200×120 px at 2.0); its default (isPaused = false) draws
//   continuously (128 draws in 2 s).
// - R0: an idle Canvas never re-runs. R2 (= P3): changing a value it reads
//   re-runs it. R1 vs R3: an UNRELATED change re-runs a Canvas whose
//   declaring body re-ran (a closure is a new value SwiftUI cannot compare)
//   but NOT one in its own child view whose inputs are unchanged — SwiftUI
//   re-draws a Canvas when ITS view's inputs change, not when the window
//   redraws.

import AppKit
import Metal
import MetalKit
import SwiftUI

// MARK: - G: sizing

struct Probe: Layout {
    let label: String
    func dim(_ v: CGFloat) -> String { v.isInfinite ? "inf" : "\(Int(v.rounded()))" }

let proposals: [ProposedViewSize]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        for p in proposals {
            let s = subviews[0].sizeThatFits(p)
            print("\(label) proposal \(fmt(p)) -> \(dim(s.width))x\(dim(s.height))")
        }
        return proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: .unspecified)
    }
}

func fmt(_ p: ProposedViewSize) -> String {
    func f(_ v: CGFloat?) -> String { v.map { $0.isInfinite ? "inf" : "\(Int($0))" } ?? "nil" }
    return "\(f(p.width))x\(f(p.height))"
}

func dim(_ v: CGFloat) -> String { v.isInfinite ? "inf" : "\(Int(v.rounded()))" }

let proposals: [ProposedViewSize] = [.unspecified, .zero, .init(width: 50, height: 30),
                                     .init(width: 300, height: 200), .infinity]

final class Red: NSObject, MTKViewDelegate {
    static let device = MTLCreateSystemDefaultDevice()!
    let queue = Red.device.makeCommandQueue()!
    var draws = 0
    var lastDrawable = CGSize.zero
    var lastBounds = CGSize.zero
    var lastScale: CGFloat = 0
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        draws += 1
        lastDrawable = view.drawableSize
        lastBounds = view.bounds.size
        lastScale = view.window?.backingScaleFactor ?? 0
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }
}

struct MetalRep: NSViewRepresentable {
    let delegate: Red
    func makeNSView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: Red.device)
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColor(red: 1, green: 0, blue: 0, alpha: 1)
        v.delegate = delegate
        return v
    }
    func updateNSView(_ nsView: MTKView, context: Context) {}
}

@MainActor func groupG() {
    let host = NSHostingView(rootView: VStack {
        Probe(label: "P1 fixed40x20", proposals: proposals) { Color.red.frame(width: 40, height: 20) }
        Probe(label: "P1 Color", proposals: proposals) { Color.red }
        Probe(label: "G1 Canvas", proposals: proposals) { Canvas { _, _ in } }
        Probe(label: "G2 MTKViewRep", proposals: proposals) { MetalRep(delegate: Red()) }
        Probe(label: "G3 TimelineCanvas", proposals: proposals) {
            TimelineView(.animation) { _ in Canvas { _, _ in } }
        }
    })
    host.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
    host.layoutSubtreeIfNeeded()
}

// MARK: - C and R: a real window

final class Counter: @unchecked Sendable { var canvasRuns = 0; var isolatedRuns = 0 }

/// R3: a Canvas in its own view whose inputs never change — the parent's
/// re-evaluation hands it equal inputs, so SwiftUI need not re-run it.
struct IsolatedCanvas: View, Equatable {
    var body: some View {
        Canvas { ctx, size in
            counter.isolatedRuns += 1
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.blue))
        }
    }
}
let counter = Counter()

final class Model: ObservableObject {
    @Published var unrelated = 0
    @Published var read = 0
}

struct Cells: View {
    @ObservedObject var model: Model
    let c1: Red, c2: Red, c3: Red
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                Color.red.frame(width: 100, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 20))          // P2
                MetalRep(delegate: c1).frame(width: 100, height: 60)        // C1
                MetalRep(delegate: c2).frame(width: 100, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 20))          // C2
            }
            HStack(spacing: 20) {
                MetalRep(delegate: c3).frame(width: 100, height: 60)
                    .opacity(0.5)                                           // C3
                Canvas { ctx, size in
                    counter.canvasRuns += 1
                    _ = model.read
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.red))
                }
                .frame(width: 100, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 20))              // C4, R
                ZStack {
                    IsolatedCanvas()                                        // R3
                    Text("u\(model.unrelated)")                            // R1's sibling
                }.frame(width: 100, height: 60)
            }
        }
        .padding(20)
        .background(Color.white)
    }
}

func spin(_ seconds: Double) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func capture(_ window: NSWindow) -> NSBitmapImageRep? {
    let path = NSTemporaryDirectory() + "mv-probe-\(window.windowNumber).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l", "\(window.windowNumber)", path]
    try? p.run(); p.waitUntilExit()
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return NSBitmapImageRep(data: data)
}

/// The window content's (x, y) in points, top-left origin, as RGBA.
func px(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat, scale: CGFloat, titleBar: CGFloat) -> String {
    guard let c = rep.colorAt(x: Int(x * scale), y: Int((y + titleBar) * scale))?.usingColorSpace(.sRGB) else { return "n/a" }
    return "(\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255)))"
}

@MainActor func groupsCR() {
    let model = Model()
    let c1 = Red(), c2 = Red(), c3 = Red()
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 220),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: Cells(model: model, c1: c1, c2: c2, c3: c3))
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    spin(2.0)
    let scale = window.backingScaleFactor
    let titleBar = window.frame.height - window.contentLayoutRect.height
    print("window backingScaleFactor \(scale) titleBar \(titleBar)")
    guard let rep = capture(window) else { print("capture FAILED"); return }
    print("capture \(rep.pixelsWide)x\(rep.pixelsHigh)")
    // Row 1 origin (20, 20); cells 100 wide, 20 apart. Row 2 at y = 100.
    func cell(_ name: String, _ ox: CGFloat, _ oy: CGFloat) {
        print("\(name) centre \(px(rep, ox + 50, oy + 30, scale: scale, titleBar: titleBar)) corner(2,2) \(px(rep, ox + 2, oy + 2, scale: scale, titleBar: titleBar)) outside(-5,30) \(px(rep, ox - 5, oy + 30, scale: scale, titleBar: titleBar))")
    }
    cell("P2 Color+clip", 20, 20)
    cell("C1 MTKView", 140, 20)
    cell("C2 MTKView+clip", 260, 20)
    cell("C3 MTKView+opacity0.5", 20, 100)
    cell("C4 Canvas+clip", 140, 100)
    print("D1 MTKView bounds \(c1.lastBounds) drawableSize \(c1.lastDrawable) windowScale \(c1.lastScale) draws(2s, default isPaused=false) \(c1.draws)")

    let r0 = counter.canvasRuns
    spin(0.5)
    print("R0 idle 0.5s: canvas runs \(r0) -> \(counter.canvasRuns)")
    let r1 = counter.canvasRuns, i1 = counter.isolatedRuns
    model.unrelated += 1
    spin(0.5)
    print("R1 unrelated sibling change: canvas runs \(r1) -> \(counter.canvasRuns)")
    print("R3 isolated canvas, same change: runs \(i1) -> \(counter.isolatedRuns)")
    let r2 = counter.canvasRuns
    model.read += 1
    spin(0.5)
    print("R2/P3 read value change: canvas runs \(r2) -> \(counter.canvasRuns)")
    window.orderOut(nil)
}

setvbuf(stdout, nil, _IONBF, 0)
MainActor.assumeIsolated {
    _ = NSApplication.shared
    print("== G")
    groupG()
    print("== C, R")
    groupsCR()
}
