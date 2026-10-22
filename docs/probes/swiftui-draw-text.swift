// SwiftUI probe: drawing a text into a drawing surface (round 2 item 5, ruling
// DT-D in docs/superpowers/2026-10-22-draw-text-decisions.md). SwiftUI's only
// public "draw a text into a surface" is `GraphicsContext.draw(_ text:
// GraphicsContext.ResolvedText, at: CGPoint, anchor: UnitPoint = .center)` and
// `draw(_:in: CGRect)` inside a `Canvas`. The answers the spelling rests on:
//   A0 positive control: a `.topLeading` anchor at (20, 20) puts the ink's
//      top-left at the point plus the glyphs' own bearings (ink box read from
//      the rendered pixels), the box measured via `ResolvedText.measure`.
//   A  the DEFAULT anchor is `.center` (the call with no anchor equals the
//      explicit `.center` call, pixel for pixel; and differs from `.topLeading`).
//   B  anchors move the layout box: `.trailing`/`.bottom` shift by the measured
//      size (ink box moves by width / height within a pixel).
//   C  `draw(_:in: rect)` WRAPS to the rect's width (a 30-wide rect makes a
//      multi-line ink box starting at the rect's top-left) — the separating arm
//      for MetalUI's `width:` parameter (DT-D).
//   D  a Canvas draws a resolved text through the Canvas's own environment
//      font, fixed at `resolve` time (the resolved value keeps its font when
//      drawn after the environment changes).
//
// HOW TO RUN (compiled form, SA-O):
//
//   xcrun swiftc docs/probes/swiftui-draw-text.swift -o /tmp/dt-probe && /tmp/dt-probe
//
// RECORDED OUTPUT (macOS 27.0, 2026-10-21; ink = pixels darker than half grey, scale 1):
//
//   A0 topLeading@(20,20) ink x 21...77 y 24...36; measured (60.0, 17.0)
//   A  default==center true  default==topLeading false  default ink x 71...127 y 46...58
//   B  trailing ink x 41...97 y 46...58; bottom ink x 71...127 y 37...49; center x 71...127 y 46...58
//   C  draw(in: 30x80 rect) ink x 21...47 y 24...50
//   D  resolved-then-env-changed ink x 21...77 y 24...36 equals A0 true
//
// READING. A0 positive control: the ink sits at the point plus bearings inside the
// measured 60 x 17 box. A: no anchor is `.center`. B: `.trailing` moves the ink
// left by half the measured width (30), `.bottom` up by half the height (9 for 17).
// C: the rect form wraps to its width. D: a resolved text keeps the font it was
// resolved with.
import SwiftUI
import AppKit

@MainActor
func ink(_ draw: @escaping @Sendable (inout GraphicsContext, CGSize) -> Void) -> (x0: Int, y0: Int, x1: Int, y1: Int, hash: Int) {
    let view = Canvas { context, size in draw(&context, size) }.frame(width: 200, height: 100)
        .background(Color.white)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.cgImage else { return (0, 0, -1, -1, 0) }
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    var x0 = w, y0 = h, x1 = -1, y1 = -1, hash = 0
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        if data[i] < 128 {
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        hash = hash &* 31 &+ Int(data[i])
    } }
    return (x0, y0, x1, y1, hash)
}

@MainActor
func run() {
    let text = Text("Hxlg 12.5").font(.system(size: 14)).foregroundColor(.black)
    var measured = CGSize.zero
    let a0 = ink { c, _ in
        let r = c.resolve(text)
        c.draw(r, at: CGPoint(x: 20, y: 20), anchor: .topLeading)
    }
    let probe = ImageRenderer(content: Canvas { c, _ in measured = c.resolve(text).measure(in: CGSize(width: 1000, height: 1000)) }
        .frame(width: 10, height: 10))
    _ = probe.cgImage
    print("A0 topLeading@(20,20) ink x \(a0.x0)...\(a0.x1) y \(a0.y0)...\(a0.y1); measured \(measured)")

    let def = ink { c, _ in c.draw(c.resolve(text), at: CGPoint(x: 100, y: 50)) }
    let ctr = ink { c, _ in c.draw(c.resolve(text), at: CGPoint(x: 100, y: 50), anchor: .center) }
    let tl = ink { c, _ in c.draw(c.resolve(text), at: CGPoint(x: 100, y: 50), anchor: .topLeading) }
    print("A  default==center \(def.hash == ctr.hash)  default==topLeading \(def.hash == tl.hash)  default ink x \(def.x0)...\(def.x1) y \(def.y0)...\(def.y1)")

    let tr = ink { c, _ in c.draw(c.resolve(text), at: CGPoint(x: 100, y: 50), anchor: .trailing) }
    let bt = ink { c, _ in c.draw(c.resolve(text), at: CGPoint(x: 100, y: 50), anchor: .bottom) }
    print("B  trailing ink x \(tr.x0)...\(tr.x1) y \(tr.y0)...\(tr.y1); bottom ink x \(bt.x0)...\(bt.x1) y \(bt.y0)...\(bt.y1); center x \(ctr.x0)...\(ctr.x1) y \(ctr.y0)...\(ctr.y1)")

    let inRect = ink { c, _ in c.draw(c.resolve(text), in: CGRect(x: 20, y: 20, width: 30, height: 80)) }
    print("C  draw(in: 30x80 rect) ink x \(inRect.x0)...\(inRect.x1) y \(inRect.y0)...\(inRect.y1)")

    let late = ink { c, _ in
        let r = c.resolve(text)
        c.environment.font = .system(size: 30)
        c.draw(r, at: CGPoint(x: 20, y: 20), anchor: .topLeading)
    }
    print("D  resolved-then-env-changed ink x \(late.x0)...\(late.x1) y \(late.y0)...\(late.y1) equals A0 \(late.hash == a0.hash)")
}

MainActor.assumeIsolated { run() }
