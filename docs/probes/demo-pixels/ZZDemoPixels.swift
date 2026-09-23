// The `CN-R` twelve-image demo pixel harness — the TEST half.
//
// Committed by plan task 7, stage 4, lane 1 (ruling `LR-CB`), after the same
// generator had been lost and rebuilt **four** times: record §18 built it in a
// session scratchpad, record §25 §7.6, §8.8 and §9.8 each rebuilt it from that
// description at about an hour apiece, and §14.4's checker wrote a fifth. Every
// lane of every engine-replacement stage has "0 differing pixels in all twelve
// `CN-R` images" as its acceptance criterion, so the criterion was not
// reproducible from anything in the repository.
//
// **This file is not part of the suite.** It is copied into a `git archive` of
// the commit under test, at `Tests/MetalUITests/ZZDemoPixels.swift`, by
// `compare.sh` next to it — see that script's header for the whole method. It
// is named `ZZ…` so Swift Testing's path-order file walk runs it last, which
// keeps it out of the way of `AuthorityCoverage`'s roll-call ordering
// argument.
//
// **Twelve images, and what each is for.** Eight of the legacy demo at 1024²
// (light/dark x frame 0/frame 3, modal light/dark, animation light/dark), two
// of the proposal preview at 1024², and the 560² two-authority chrome pair
// (`DifferentialRoot(560) { Column { CounterPanel() }.width(560) }`, one window
// per layout authority) — the only image in the set that a proposal-path change
// can move, because `demoContent()` names no proposal type and production runs
// the legacy authority until stage 6b.
//
// Each image is written twice: raw BGRA (`<name>.bgra`, `side * side * 4`
// bytes, row-major, exactly what `FakeRenderSurface.readPixels()` hands back)
// and a scene dump (`<name>.scene`, one line per primitive of
// `Window.lastScene`, rects before glyphs, in the order the GPU receives them).
// The dump is what says *where* a difference is when the pixel count is not 0,
// and it is also how record §25 §7.6's caveat was measured: none of the twelve
// scenes is ever scrolled, so `ScrollState.lastScrollTime` is `-.infinity`,
// `alpha` is 0, and no scroll indicator is painted in any of them — scan for a
// 3pt cross-axis rect and the count is zero everywhere.
//
// **It writes files and asserts nothing.** The comparison is `compare.sh`'s.
// Set `METALUI_PIXEL_OUT` to a directory; without it the test skips, so a tree
// that accidentally keeps this file still runs its suite unchanged.

import Testing
import Foundation
import Metal
import MetalUICore
import MetalUILayout
@testable import MetalUI
@testable import MetalUIDemoContent

@MainActor
private func dumpScene(_ scene: Scene, to path: String) throws {
    var lines: [String] = []
    for r in scene.rects {
        let b = r.bounds, m = r.contentMask, c = r.background, bc = r.borderColor
        lines.append("R \(b.origin.x),\(b.origin.y) \(b.size.width)x\(b.size.height)"
            + " mask=\(m.origin.x),\(m.origin.y),\(m.size.width),\(m.size.height)"
            + " bg=\(c.h),\(c.s),\(c.l),\(c.a)"
            + " border=\(bc.h),\(bc.s),\(bc.l),\(bc.a)"
            + " widths=\(r.borderWidths.top),\(r.borderWidths.right),\(r.borderWidths.bottom),\(r.borderWidths.left)"
            + " radii=\(r.cornerRadii.topLeft),\(r.cornerRadii.topRight),\(r.cornerRadii.bottomRight),\(r.cornerRadii.bottomLeft)"
            + " order=\(r.order)")
    }
    for g in scene.glyphs {
        let b = g.bounds, a = g.atlasBounds, c = g.color
        lines.append("G \(b.origin.x),\(b.origin.y) \(b.size.width)x\(b.size.height)"
            + " atlas=\(a.origin.x),\(a.origin.y),\(a.size.width),\(a.size.height)"
            + " color=\(c.h),\(c.s),\(c.l),\(c.a)")
    }
    for run in scene.drawList { lines.append("D \(run.kind) \(run.start) \(run.count)") }
    try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
}

@MainActor
private func capture(_ name: String, out: String, side: Int, frames: Int,
                     appearance: Appearance,
                     authority: LayoutAuthority = .legacy,
                     content: @escaping @MainActor () -> some Element) throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
    let (window, platform) = try makeFakeWindow(device: device, size: side,
                                                appearance: appearance,
                                                layoutAuthority: authority,
                                                content: content)
    for _ in 0..<frames {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    let pixels = platform.fakeSurface.readPixels()
    try Data(pixels).write(to: URL(fileURLWithPath: "\(out)/\(name).bgra"))
    try dumpScene(window.lastScene, to: "\(out)/\(name).scene")
    print("PIXELS wrote \(name) \(side)x\(side) bytes=\(pixels.count)")
}

@Test @MainActor func zzCaptureDemoPixels() throws {
    guard let out = ProcessInfo.processInfo.environment["METALUI_PIXEL_OUT"] else { return }
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

    // The demo's model is a `@MainActor` global, so every arm sets the state it
    // wants and puts it back — an arm that leaked would silently change the
    // arms after it, which is the whole set's failure mode.
    demoModel.showModal = false
    demoModel.animationDemoActive = false

    for (suffix, appearance) in [("light", Appearance.light), ("dark", Appearance.dark)] {
        // Frame 0 and frame 3 of the same window would need one window driven
        // twice; two windows are used instead so that each image is a clean
        // first-frame-plus-N, which is what record §18's generator did and what
        // makes `f0 vs f3` a control that reads 0 rather than a measurement of
        // how a window warms up.
        try capture("default-\(suffix)-f0", out: out, side: 1024, frames: 1,
                    appearance: appearance) { demoContent() }
        try capture("default-\(suffix)-f3", out: out, side: 1024, frames: 4,
                    appearance: appearance) { demoContent() }
    }

    demoModel.showModal = true
    for (suffix, appearance) in [("light", Appearance.light), ("dark", Appearance.dark)] {
        try capture("modal-\(suffix)", out: out, side: 1024, frames: 1,
                    appearance: appearance) { demoContent() }
    }
    demoModel.showModal = false

    // The **A** look, settled: the flag is written outside `withAnimation`, so
    // both helpers take their snap branch and the first frame already shows the
    // end state. A mid-flight image would depend on a timestamp.
    demoModel.animationDemoActive = true
    for (suffix, appearance) in [("light", Appearance.light), ("dark", Appearance.dark)] {
        try capture("animation-\(suffix)", out: out, side: 1024, frames: 1,
                    appearance: appearance) { demoContent() }
    }
    demoModel.animationDemoActive = false

    for (suffix, appearance) in [("light", Appearance.light), ("dark", Appearance.dark)] {
        try capture("preview-\(suffix)", out: out, side: 1024, frames: 1,
                    appearance: appearance) { nativeLayoutPreviewContent() }
    }

    // The two-authority pair, and the only image in the set a proposal-path
    // change can move. 560² because the 1024 square never compresses this
    // subtree. `DifferentialRoot` is the differential harness's own root, so the
    // two authorities start from the same rect on both sides (`LR-D`).
    for (suffix, authority) in [("legacy", LayoutAuthority.legacy),
                                ("proposal", LayoutAuthority.proposal)] {
        try capture("chrome-\(suffix)", out: out, side: 560, frames: 1,
                    appearance: .light, authority: authority) {
            DifferentialRoot(width: 560, height: 560) {
                Column { CounterPanel() }.width(Pixels(560))
            }
        }
    }
}
