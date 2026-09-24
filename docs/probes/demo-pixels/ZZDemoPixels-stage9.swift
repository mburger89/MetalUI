// The `CN-R` demo pixel harness — the TEST half, **stage-9 copy** (plan task 7,
// stage 9, ruling `LR-FG` item 7; record §51, lane 3).
//
// Stage 9 deleted the layout authority (`LR-FC`), so this copy is
// `ZZDemoPixels.swift` with its one authority-naming arm removed:
// `capture` takes no `authority:` and never passes `layoutAuthority:` to
// `makeFakeWindow` (whose parameter stage 9 deleted), and the chrome pair —
// `chrome-legacy` and `chrome-proposal` — is rendered **twice under the one
// authority**, with the same file names, so that `compare.sh`'s control
// "chrome legacy vs proposal [0]" still reads two independent renders and a
// commit-to-commit row compares each against its pre-stage-9 image. At
// `b9a5d7f` the two chrome images were equal (0 differing), so the head's
// `chrome-legacy` against `b9a5d7f`'s is the check that the one remaining
// path draws what the legacy one drew. `compare.sh` picks this copy for a
// commit whose `Tests/MetalUITests/Fakes.swift` has no `layoutAuthority:`
// parameter, and `ZZDemoPixels.swift` otherwise. Everything else — the
// fourteen images, their sizes, their frame counts, the scene dump — is
// byte-for-byte the original's; read that file's header for the method.
//
// **This file is not part of the suite**, and without `METALUI_PIXEL_OUT` it
// skips.

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

/// `height`, when given and below `side`, makes the window `side` wide and
/// `height` tall (stage 6b, `LR-DO` item 3): the fake surface is square, so the
/// window is resized the way `AppKitWindow` reports a resize
/// (`FakePlatformWindow.simulateResize`) and only the top `height` rows of the
/// `side`-square readback are written — `side * height * 4` bytes. Uses nothing
/// `aef88ce`'s `Fakes.swift` lacks, so the same file captures at both commits.
@MainActor
private func capture(_ name: String, out: String, side: Int, height: Int? = nil, frames: Int,
                     appearance: Appearance,
                     content: @escaping @MainActor () -> some Element) throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
    let (window, platform) = try makeFakeWindow(device: device, size: side, appearance: appearance,
                                                content: content)
    if let height {
        platform.simulateResize(to: Size(width: Pixels(Float(side)), height: Pixels(Float(height))))
    }
    for _ in 0..<frames {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    var pixels = platform.fakeSurface.readPixels()
    if let height { pixels = Array(pixels.prefix(side * height * 4)) }
    try Data(pixels).write(to: URL(fileURLWithPath: "\(out)/\(name).bgra"))
    try dumpScene(window.lastScene, to: "\(out)/\(name).scene")
    print("PIXELS wrote \(name) \(side)x\(height ?? side) bytes=\(pixels.count)")
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

    // Stage 6b (`LR-DO` item 3): the demo at the 920×560 `MetalUIDemo` opens
    // (`Sources/MetalUIDemo/main.swift`), default and modal, light only — the
    // size where a vertical compression the 1024 square never shows would.
    try capture("prod-default-light", out: out, side: 920, height: 560, frames: 1,
                appearance: .light) { demoContent() }
    demoModel.showModal = true
    try capture("prod-modal-light", out: out, side: 920, height: 560, frames: 1,
                appearance: .light) { demoContent() }
    demoModel.showModal = false

    for (suffix, appearance) in [("light", Appearance.light), ("dark", Appearance.dark)] {
        try capture("preview-\(suffix)", out: out, side: 1024, frames: 1,
                    appearance: appearance) { nativeLayoutPreviewContent() }
    }

    // The chrome pair, both under the one authority since stage 9 (`LR-FG` item
    // 7): two independent renders of the same tree, keeping the pre-stage-9
    // names so every commit-to-commit row and the `[0]` control still read.
    for suffix in ["legacy", "proposal"] {
        try capture("chrome-\(suffix)", out: out, side: 560, frames: 1, appearance: .light) {
            DifferentialRoot(width: 560, height: 560) {
                Column { CounterPanel() }.width(Pixels(560))
            }
        }
    }
}
