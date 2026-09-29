// SwiftUI probe: does `.controlSize` reach a `Text`'s DRAWN default font, or
// only its measurement? (plan task 11 part 1, critic round, ruling TE-Q.)
//
// Why it exists. `swiftui-text-semantics.swift` arm F8 reads the default
// `Text` under `.controlSize(.mini)` as 76.5×11 (a 9 pt answer) through an
// `NSHostingView`'s layout, but its render-identification field
// (`equals=`) reads `.system(size: 13)` in EVERY row, including `.mini` and
// `.small`. That field renders through `ImageRenderer`. The two instruments
// contradict each other, so rulings resting on F8 (`TE-F`) need to know which
// one is the drawn answer. This probe identifies the default Text's font
// under each control size through both instruments against `.system(size: s)`
// candidates measured by the same instrument.
//
// HOW TO RUN (SA-O's two forms), from the repository root:
//
//   xcrun swiftc docs/probes/swiftui-controlsize-text-render.swift -o /tmp/cs-probe && /tmp/cs-probe
//   /usr/bin/swift docs/probes/swiftui-controlsize-text-render.swift
//
// SEPARATING ARMS AND POSITIVE CONTROLS.
// - R0: each instrument separates 9 pt from 13 pt (ImageRenderer by a pixel
//   count, the hosting view's fitting size by its answer), so a match against
//   one candidate is a real identification.
// - R1: ImageRenderer, the default Text under each control size, identified
//   against `.system(size: 8 … 14)` renders — reproduces F8's `equals=` field
//   (the instrument under suspicion).
// - R2: the hosting view's fitting size for the same views, identified
//   against the same candidates' fitting sizes (every candidate that matches
//   is listed, so a non-unique match would show).
// An `NSHostingView.cacheDisplay` render was tried as a third instrument and
// dropped: with the screen locked it returned a blank bitmap even inside an
// offscreen borderless window (its own 9-vs-13 control read 0 px), so it
// could not separate anything. The drawn answer in an on-screen window is
// therefore NOT measured here.
//
// RECORDED 2026-09-28 by the plan task 11 part 1 critic round, macOS 27.0
// (26A428), Apple Swift 6.4, screen LOCKED (no window is ordered front). The
// compiled form was run twice and the interpreted form once, stdout
// byte-identical, exit 0:
//
//   R0 ImageRenderer 9 vs 13: 2404px
//   R0 fitting 9: 77x11 13: 106x16
//   R1 ImageRenderer mini: equals .system(size: 13)
//   R1 ImageRenderer small: equals .system(size: 13)
//   R1 ImageRenderer regular: equals .system(size: 13)
//   R2 fitting mini: 77x11 same fitting size as .system(size:) ["9"]
//   R2 fitting small: 92x14 same fitting size as .system(size:) ["11"]
//   R2 fitting regular: 106x16 same fitting size as .system(size:) ["13"]
//   done
//
// READING (ruling TE-Q).
// - `ImageRenderer` does not apply `.controlSize` to a `Text`'s default font
//   at all (R1: 13 pt at every size, against a 2404 px 9-vs-13 control). F8's
//   `equals=` field in `swiftui-text-semantics.swift` is this instrument's
//   blind spot, not evidence that the drawn font stays 13 pt.
// - Layout does apply it, uniquely: the default Text under `.mini` answers
//   exactly `.system(size: 9)`'s size, `.small` 11, `.regular` 13, and no other
//   candidate size (R2). This is the evidence `TE-F` rests on; the drawn font
//   in a real window is unmeasured (owed with the real-window capture).

import AppKit
import SwiftUI

func fmt(_ v: CGFloat) -> String {
    let r = (v * 1000).rounded() / 1000
    return r == r.rounded() ? String(Int(r)) : String(Double(r))
}

typealias Bitmap = (bytes: [UInt8], w: Int, h: Int)

func bytes(of cg: CGImage) -> Bitmap {
    let w = cg.width, h = cg.height
    var b = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &b, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (b, w, h)
}

func differing(_ a: Bitmap, _ b: Bitmap) -> Int {
    guard a.w == b.w, a.h == b.h else { return Int.max }
    var n = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) where a.bytes[i] != b.bytes[i]
        || a.bytes[i + 1] != b.bytes[i + 1] || a.bytes[i + 2] != b.bytes[i + 2] { n += 1 }
    return n
}

func canvas(_ v: some View) -> some View {
    v.fixedSize().frame(width: 260, height: 40, alignment: .topLeading).background(Color.white)
}

@MainActor func viaRenderer(_ v: some View) -> Bitmap {
    let r = ImageRenderer(content: canvas(v))
    r.scale = 2
    return bytes(of: r.cgImage!)
}

@MainActor func fitting(_ v: some View) -> String {
    let host = NSHostingView(rootView: v.environment(\.displayScale, 2))
    let s = host.fittingSize
    return "\(fmt(s.width))x\(fmt(s.height))"
}

let sample = "Hello, world 0123"

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    let t9 = Text(sample).font(.system(size: 9)), t13 = Text(sample).font(.system(size: 13))
    print("R0 ImageRenderer 9 vs 13: \(differing(viaRenderer(t9), viaRenderer(t13)))px")
    print("R0 fitting 9: \(fitting(t9)) 13: \(fitting(t13))")
    let sizes: [(String, ControlSize)] = [("mini", .mini), ("small", .small), ("regular", .regular)]
    for (label, cs) in sizes {
        let target = viaRenderer(Text(sample).controlSize(cs))
        var eq = "none"
        for s in stride(from: 8.0, through: 14.0, by: 0.5) {
            if differing(target, viaRenderer(Text(sample).font(.system(size: s)))) == 0 {
                eq = ".system(size: \(fmt(s)))"; break
            }
        }
        print("R1 ImageRenderer \(label): equals \(eq)")
    }
    for (label, cs) in sizes {
        let target = fitting(Text(sample).controlSize(cs))
        var eq: [String] = []
        for s in stride(from: 8.0, through: 14.0, by: 0.5) where fitting(Text(sample).font(.system(size: s))) == target {
            eq.append(fmt(s))
        }
        print("R2 fitting \(label): \(target) same fitting size as .system(size:) \(eq)")
    }
    print("done")
}
