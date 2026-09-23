import Testing
import Metal
import MetalUICore
@testable import MetalUILayout
import MetalUIDemoContent
@testable import MetalUI

// Plan task 7, stage 6b, lane 3 (`docs/superpowers/specs/2026-09-23-engine-stage-6b-design.md`
// §8 tests 3.1–3.3; rulings LR-DF, LR-DG, LR-DK, LR-DL): the root switch seen
// through a production `Window` — no production root reaches the CSS engine,
// a hugging legacy root is centred (`CN-J`), and every production root's
// deepest native level is read.
//
// **Every window here is a `makeFakeWindow` window at its DEFAULT authority**
// unless the test names `.legacy` — the default is production's
// (`Frame.defaultLayoutAuthority`, `LR-DF`), so these are production frames:
// diagnostics off, an unlowerable field traps.
//
// `demoContent()`, `nativeLayoutPreviewContent()` and `demoModel` are imported
// from `MetalUIDemoContent` with a plain import (`LR-S`): the demo the binary
// runs, not a copy of it.

private struct RootSwitchRow: Identifiable { let id: Int }

/// A production-shaped `List` root: a vertical `ScrollView` whose only
/// layout-contributing child is a `List` of 200 rows, each row spelled as the
/// demo spells its rows after `LR-DJ` (a centring `Box` with its height
/// declared, grown, horizontally padded and 420 wide).
@MainActor
private func listRoot() -> some Element {
    ScrollView(.vertical) {
        List((0..<200).map(RootSwitchRow.init), rowHeight: Pixels(28)) { row in
            Box {
                Text("Row \(row.id + 1)")
            }
            .alignItems(.center)
            .flexGrow(1)
            .height(Pixels(28))
            .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(12)),
                           bottom: .pixels(Pixels(0)), left: .pixels(Pixels(12))))
            .width(Pixels(420))
        }
    }
}

/// One production root, the size of the window it is drawn in, and the demo
/// state it needs. `height == nil` is a square window of side `width`.
private struct ProductionRoot {
    enum Content { case demo, preview, list }
    let name: String
    let content: Content
    let width: Int
    let height: Int?
    var modal = false
    var animation = false
}

/// Every production root this stage names (spec §8, 3.1 and 3.3): the demo in
/// its three states at the 1024² the pixel harness takes and at the 920×560
/// `MetalUIDemo` opens (`LR-DO` item 3), the preview, and a `List` root.
private let productionRoots: [ProductionRoot] = [
    ProductionRoot(name: "demo 1024", content: .demo, width: 1024, height: nil),
    ProductionRoot(name: "demo-modal 1024", content: .demo, width: 1024, height: nil, modal: true),
    ProductionRoot(name: "demo-animation 1024", content: .demo, width: 1024, height: nil, animation: true),
    ProductionRoot(name: "demo 920x560", content: .demo, width: 920, height: 560),
    ProductionRoot(name: "demo-modal 920x560", content: .demo, width: 920, height: 560, modal: true),
    ProductionRoot(name: "demo-animation 920x560", content: .demo, width: 920, height: 560, animation: true),
    ProductionRoot(name: "preview 1024", content: .preview, width: 1024, height: nil),
    ProductionRoot(name: "list 920x560", content: .list, width: 920, height: 560),
]

/// Draws `root` through a fresh window `frames` times (each frame forced with
/// `setNeedsRedraw`), and hands back the window. The demo's model is a
/// `@MainActor` global, so its state is set here and put back before
/// returning — a leak would silently change every test after this one.
@MainActor
private func draw(_ root: ProductionRoot, frames: Int,
                  authority: LayoutAuthority? = nil) throws -> Window {
    let device = try #require(MTLCreateSystemDefaultDevice())
    demoModel.showModal = root.modal
    demoModel.animationDemoActive = root.animation
    defer {
        demoModel.showModal = false
        demoModel.animationDemoActive = false
    }
    let window: Window, platform: FakePlatformWindow
    switch root.content {
    case .demo:
        (window, platform) = try makeFakeWindow(device: device, size: root.width,
                                                layoutAuthority: authority) { demoContent() }
    case .preview:
        (window, platform) = try makeFakeWindow(device: device, size: root.width,
                                                layoutAuthority: authority) { nativeLayoutPreviewContent() }
    case .list:
        (window, platform) = try makeFakeWindow(device: device, size: root.width,
                                                layoutAuthority: authority) { listRoot() }
    }
    if let height = root.height {
        platform.simulateResize(to: Size(width: Pixels(Float(root.width)), height: Pixels(Float(height))))
    }
    for _ in 0..<frames {
        window.setNeedsRedraw()
        window.drawFrameIfNeeded()
    }
    return window
}

// MARK: - 3.1 — the exit test

/// **3.1, the stage's exit test** (parent spec §4.1 row 6b, `LR-DL`): no
/// production frame reaches the legacy engine. Every root in
/// `productionRoots` — `demoContent()` with the modal off and on and the
/// animation on, at 1024² and 920×560, `nativeLayoutPreviewContent()`, and a
/// `ScrollView { List }` root — is drawn three frames through a window at the
/// default authority with `Frame.legacyRootLayoutCounter` bound: it reads 0.
///
/// **The positive control is in the same test**: the demo through a `.legacy`
/// window bumps the counter exactly once per frame drawn, so a counter that
/// cannot count cannot pass.
///
/// Red before: the counter declared and never bumped — the control read 0.
/// Mutations that must redden it: **M3a** `Frame.defaultLayoutAuthority` back
/// to `.legacy` (the production arms count); **M3b** the bump removed (the
/// control reads 0).
@MainActor
@Test func noProductionFrameReachesTheLegacyEngine() throws {
    let frames = 3
    for root in productionRoots {
        let counter = Frame.LegacyRootLayoutCounter()
        let window = try Frame.$legacyRootLayoutCounter.withValue(counter) {
            try draw(root, frames: frames)
        }
        #expect(window.layoutAuthority == .proposal, "\(root.name): not a production window")
        #expect(counter.count == 0, "\(root.name): \(counter.count) frame(s) reached the legacy engine")
    }

    // The positive control: the same demo, a `.legacy` window.
    for root in productionRoots where root.content == .demo {
        let control = Frame.LegacyRootLayoutCounter()
        _ = try Frame.$legacyRootLayoutCounter.withValue(control) {
            try draw(root, frames: frames, authority: .legacy)
        }
        #expect(control.count == frames,
                "\(root.name): a .legacy window must bump the counter once per frame (read \(control.count))")
    }
}

// MARK: - 3.2 — root placement through a window

/// **3.2** (`LR-DG`, `CN-J`): a hugging legacy root is centred in a production
/// window. `Row { Box().width(58).height(20) }` in a 100×100 window: the box at
/// (21, 40) 58×20, as SwiftUI places a 58×20 root in a 100×100 host (stack probe
/// R1/R2, re-run 2026-09-23: `(21, 40) 58×20`). The same tree through a
/// `.legacy` window is the CSS answer, divergence 4 (`CS-I`): the auto row
/// fills the window, starts its main axis at 0 and centres its cross axis —
/// the box at (0, 40). The two arms disagree, so neither is vacuous.
///
/// Green on arrival after the flip; its red is taken as **M2a** (the native
/// root top-leading) and **M2b** (placed at the window rect), and its
/// `.legacy` arm is the answer `aef88ce`'s production gave.
@MainActor
@Test func aHuggingLegacyRootIsCentredInAProductionWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let boxID = GlobalElementID.child(of: rootID, at: 0, name: nil)
    func boxRect(_ authority: LayoutAuthority?) throws -> Bounds<Pixels>? {
        let (window, _) = try makeFakeWindow(device: device, size: 100, layoutAuthority: authority) {
            Row { Box().width(Pixels(58)).height(Pixels(20)) }
        }
        window.recordsElementBounds = true
        window.drawFrameIfNeeded()
        return window.lastElementBounds[boxID]
    }
    let production = try #require(try boxRect(nil))
    #expect(production == Bounds(origin: Point(x: Pixels(21), y: Pixels(40)),
                                 size: Size(width: Pixels(58), height: Pixels(20))))
    let legacy = try #require(try boxRect(.legacy))
    #expect(legacy == Bounds(origin: Point(x: Pixels(0), y: Pixels(40)),
                             size: Size(width: Pixels(58), height: Pixels(20))))
}

// MARK: - 3.3 — every production root's depth

/// **3.3** (`LR-DK` item 2, `LR-Q`): every production root's deepest native
/// level, read through a window (`Window.lastNativeLayoutDeepestLevel`), each
/// well under `NativeLayoutRun.maxDepth`. The literals are **measured** (record
/// §41 §12), not derived: they move when a lowering adds or drops a level, and
/// that is the point — a production root creeping towards the limit reddens
/// here first, naming itself.
///
/// Red before: the window property declared and never captured (read 0).
/// Mutations that must redden it: **M3c** the property not captured (reads 0);
/// **M3d** one extra native level on every lowered `Box` (the demo and list
/// values move).
@MainActor
@Test func everyProductionRootsDeepestNativeLevelIsMeasured() throws {
    // Measured at stage 6b lane 3. The demo read 29 before `LR-DJ`'s re-spelling
    // (record §41 §5) and reads 30 after it: the row's declared height is one
    // more lowered level on the demo's deepest path (the `List` row). The same
    // row spelling is why this `List` root reads 16 where the design's fixture,
    // without the declared height, read 15 (and this one, with the line
    // removed, reads 15 — measured). The window size and the demo's state move
    // nothing.
    let expected: [String: Int] = [
        "demo 1024": 30, "demo-modal 1024": 30, "demo-animation 1024": 30,
        "demo 920x560": 30, "demo-modal 920x560": 30, "demo-animation 920x560": 30,
        "preview 1024": 10, "list 920x560": 16,
    ]
    for root in productionRoots {
        let window = try draw(root, frames: 2)
        let deepest = window.lastNativeLayoutDeepestLevel
        #expect(deepest == expected[root.name], "\(root.name): deepest native level \(deepest)")
        #expect(deepest > 0 && deepest < NativeLayoutRun.maxDepth,
                "\(root.name): \(deepest) against the limit \(NativeLayoutRun.maxDepth)")
    }
}
