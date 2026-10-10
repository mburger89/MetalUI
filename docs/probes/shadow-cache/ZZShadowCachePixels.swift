// The shadow-cache pixel harness — the TEST half (C13 / PERF-a, rulings
// `PF-C`, `PF-K` item 1; spec `docs/superpowers/specs/2026-10-09-shadow-cache-design.md`
// §6). The fourteen `demo-pixels` images hold no shadow, no blur and no
// gradient, so a 0 there proves only that paths are untouched; this file
// renders what they do not.
//
// **This file is not part of the suite.** `run.sh pixels` (next to it) copies
// it into a `git archive` of each commit under test, at
// `Tests/MetalUITests/ZZShadowCachePixels.swift`, and runs the one test with
// `METALUI_SHADOW_PIXEL_OUT` set — the `demo-pixels` method. Without the
// variable the test returns at once.
//
// **It spells only API present at 2155f1e**, so the same file captures before
// and after the shadow cache, and lane 2's LooksDemo section moves nothing it
// compares: the looks rows are a FROZEN COPY of 2155f1e's LooksDemo Q3 shadow
// row, gradients row and blur row, not the live demo.
//
// Images (raw BGRA, `side * side * 4` bytes, one window each unless noted):
//
//   looks-light, looks-dark       the frozen rows, 600 × 600 at 1×
//   looks-light-2x                the same, 300 × 300 points at 2× (600 px)
//   drag-1x-f0 … drag-1x-f4       ONE warm window, a nine-leaf shadowed node
//   drag-2x-f0 … drag-2x-f4       dragged: +1 pt (layout), +0.5 pt (offset),
//                                 +0.3 pt (offset), +1 pt (layout) — so frames
//                                 1 and 4 hit the cache after this branch and
//                                 must still draw 2155f1e's pixels.
//
// It writes files and asserts nothing; `run.sh` compares.

import Testing
import Foundation
import Metal
import MetalUICore
import MetalUILayout
@testable import MetalUI

@MainActor private var zzDrag: (layout: Float, offset: Float) = (0, 0)

/// An 8 × 8 two-tone checker (2155f1e's `looksCheckerBitmap`).
@MainActor private let zzChecker: ImageBitmap = {
    var rgba: [UInt8] = []
    for y in 0..<8 { for x in 0..<8 { rgba += (x + y) % 2 == 0 ? [230, 80, 40, 255] : [40, 90, 220, 255] } }
    return ImageBitmap(width: 8, height: 8, rgba: rgba)
}()

/// 2155f1e's LooksDemo Q3 row: a card with a shadow and a shadowed text.
@MainActor private func zzShadowRow() -> some Element {
    Row(gap: Pixels(24)) {
        Box {
            Text("A card with a shadow")
        }
        .padding(Pixels(12))
        .background(.surface)
        .cornerRadius(Pixels(10))
        .shadow(radius: Pixels(8), y: Pixels(4))
        Text("A shadowed text").font(size: 18).shadow(radius: Pixels(2), x: Pixels(1), y: Pixels(2))
    }
}

/// 2155f1e's `LooksGradientsRow`.
@MainActor private func zzGradientsRow() -> some Element {
    HStack(spacing: Pixels(12)) {
        RoundedRectangle(cornerRadius: Pixels(8))
            .fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.82)], startPoint: .top,
                                 endPoint: .bottom))
            .frame(width: Pixels(90), height: Pixels(60))
        Rectangle()
            .fill(LinearGradient(colors: [.orange, .pink, .indigo], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: Pixels(90), height: Pixels(60))
        Circle()
            .fill(RadialGradient(colors: [.yellow, .red.opacity(0)], center: .center, startRadius: Pixels(0),
                                 endRadius: Pixels(30)))
            .frame(width: Pixels(60), height: Pixels(60))
    }
}

/// 2155f1e's `looksBlurRow()`.
@MainActor private func zzBlurRow() -> some Element {
    HStack(spacing: Pixels(12)) {
        ForEach([0, 2, 6], id: \.self) { radius in
            VStack(spacing: Pixels(4)) {
                Text("Blur \(radius)").font(size: 13).blur(radius: Pixels(Float(radius)))
                Image(zzChecker, scale: 1, label: Text("Checker"))
                    .frame(width: Pixels(32), height: Pixels(32))
                    .blur(radius: Pixels(Float(radius)))
            }
        }
    }
}

@MainActor private func zzLooks() -> some Element {
    Column(gap: Pixels(16)) {
        zzShadowRow()
        zzGradientsRow()
        zzBlurRow()
    }
    .alignItems(.flexStart)
}

/// A nine-leaf node (a rounded rectangle, six bars, a circle, a text) with
/// `.shadow(radius: 10)`, at the drag position.
@MainActor private func zzDragNode() -> some Element {
    VStack(spacing: Pixels(2)) {
        RoundedRectangle(cornerRadius: 4).fill(.accent).frame(width: Pixels(70), height: Pixels(12))
        Color(.separator).frame(width: Pixels(60), height: Pixels(6))
        Color(.separator).frame(width: Pixels(50), height: Pixels(6))
        Color(.separator).frame(width: Pixels(60), height: Pixels(6))
        Color(.separator).frame(width: Pixels(40), height: Pixels(6))
        Color(.separator).frame(width: Pixels(60), height: Pixels(6))
        Color(.separator).frame(width: Pixels(30), height: Pixels(6))
        Circle().fill(.accent).frame(width: Pixels(10), height: Pixels(10))
        Text("Node").font(size: 11)
    }
    .shadow(radius: Pixels(10))
    .padding(Edges(top: Pixels(60), right: Pixels(0), bottom: Pixels(0), left: Pixels(60 + zzDrag.layout)))
    .frame(width: Pixels(300), height: Pixels(300), alignment: .topLeading)
    .offset(x: Pixels(zzDrag.offset))
}

@MainActor private func zzWrite(_ platform: FakePlatformWindow, _ name: String, out: String, side: Int) throws {
    let pixels = platform.fakeSurface.readPixels()
    try Data(pixels).write(to: URL(fileURLWithPath: "\(out)/\(name).bgra"))
    print("SHADOWPIXELS wrote \(name) \(side)x\(side) bytes=\(pixels.count)")
}

@MainActor private func zzWindow(side: Int, scale: Float, appearance: Appearance,
                                 content: @escaping @MainActor () -> some Element) throws
    -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
    let (window, platform) = try makeFakeWindow(device: device, size: side, appearance: appearance, content: content)
    if scale != 1 {
        platform.simulateBackingScaleChange(to: scale)
        let points = Pixels(Float(side) / scale)
        platform.simulateResize(to: Size(width: points, height: points))
    }
    return (window, platform)
}

@Test @MainActor func zzCaptureShadowCachePixels() throws {
    guard let out = ProcessInfo.processInfo.environment["METALUI_SHADOW_PIXEL_OUT"] else { return }
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

    for (name, appearance, scale) in [("looks-light", Appearance.light, Float(1)), ("looks-dark", .dark, 1),
                                      ("looks-light-2x", .light, 2)] {
        let (window, platform) = try zzWindow(side: 600, scale: scale, appearance: appearance) { zzLooks() }
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
        try zzWrite(platform, name, out: out, side: 600)
    }

    let steps: [(layout: Float, offset: Float)] = [(0, 0), (1, 0), (1, 0.5), (1, 0.8), (2, 0.8)]
    for (suffix, scale) in [("1x", Float(1)), ("2x", Float(2))] {
        zzDrag = steps[0]
        let side = scale == 1 ? 300 : 600
        let (window, platform) = try zzWindow(side: side, scale: scale, appearance: .light) { zzDragNode() }
        for (i, step) in steps.enumerated() {
            zzDrag = step
            window.setNeedsRedraw()
            window.drawFrameIfNeeded()
            try zzWrite(platform, "drag-\(suffix)-f\(i)", out: out, side: side)
        }
    }
    zzDrag = (0, 0)
}
