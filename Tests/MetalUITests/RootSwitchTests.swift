import Testing
import Metal
import MetalUICore
@testable import MetalUILayout
import MetalUIDemoContent
@testable import MetalUI

// Plan task 7, stage 6b, lane 3 (`docs/superpowers/specs/2026-09-23-engine-stage-6b-design.md`
// §8 tests 3.1–3.3; rulings LR-DF, LR-DG, LR-DK, LR-DL): the root switch seen
// through a production `Window` — a hugging legacy root is centred (`CN-J`),
// and every production root's deepest native level is read. (3.1, the exit
// test `noProductionFrameReachesTheLegacyEngine`, retired at stage 9 with the
// legacy root-layout branch and counter it read, `LR-FH` item 3; stage 10's
// symbol check is handed its role.)
//
// **Every window here is a production `makeFakeWindow` window**: diagnostics
// off, an unlowerable field traps.
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
            .cssHeight(Pixels(28))
            .padding(Edges(top: .pixels(Pixels(0)), right: .pixels(Pixels(12)),
                           bottom: .pixels(Pixels(0)), left: .pixels(Pixels(12))))
            .cssWidth(Pixels(420))
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
private func draw(_ root: ProductionRoot, frames: Int) throws -> Window {
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
        (window, platform) = try makeFakeWindow(device: device, size: root.width) { demoContent() }
    case .preview:
        (window, platform) = try makeFakeWindow(device: device, size: root.width) { nativeLayoutPreviewContent() }
    case .list:
        (window, platform) = try makeFakeWindow(device: device, size: root.width) { listRoot() }
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

// MARK: - 3.2 — root placement through a window

/// **3.2** (`LR-DG`, `CN-J`): a hugging legacy root is centred in a production
/// window. `Row { Box().width(58).height(20) }` in a 100×100 window: the box at
/// (21, 40) 58×20, as SwiftUI places a 58×20 root in a 100×100 host (stack probe
/// R1/R2, re-run 2026-09-23: `(21, 40) 58×20`). The literal is derived from
/// those probe arms — `((100 − 58) / 2, (100 − 20) / 2)` — not from another arm
/// of this test, so the arm is not vacuous on its own: a root placed top-leading
/// reads (0, 0), one placed at the window rect reads (0, 40).
///
/// **Stage 7b (record §49 row 245, `LR-EH`) removed this test's `.legacy` arm**,
/// which read divergence 4's CSS answer (`CS-I`: the auto row fills the window,
/// the box at (0, 40)) — the last pin of divergence 4 outside the CSS engine's
/// own retired tests; divergence 4 retires with it.
///
/// Green on arrival after the flip; its red is taken as **M2a** (the native
/// root top-leading) and **M2b** (placed at the window rect).
@MainActor
@Test func aHuggingLegacyRootIsCentredInAProductionWindow() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let rootID = GlobalElementID.child(of: nil, at: 0, name: nil)
    let boxID = GlobalElementID.child(of: rootID, at: 0, name: nil)
    func boxRect() throws -> Bounds<Pixels>? {
        let (window, _) = try makeFakeWindow(device: device, size: 100) {
            Row { Box().cssWidth(Pixels(58)).cssHeight(Pixels(20)) }
        }
        window.recordsElementBounds = true
        window.drawFrameIfNeeded()
        return window.lastElementBounds[boxID]
    }
    let production = try #require(try boxRect())
    #expect(production == Bounds(origin: Point(x: Pixels(21), y: Pixels(40)),
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
    // nothing. **29 again since stage 8** (`LR-EZ`, measured): the recipe drops
    // the list row's `.alignItems(.center).flexGrow(1)` (`LR-ES`'s R4 — the
    // frame's own `.center` does the centring), one lowered level fewer on the
    // same deepest path.
    let expected: [String: Int] = [
        "demo 1024": 29, "demo-modal 1024": 29, "demo-animation 1024": 29,
        "demo 920x560": 29, "demo-modal 920x560": 29, "demo-animation 920x560": 29,
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
