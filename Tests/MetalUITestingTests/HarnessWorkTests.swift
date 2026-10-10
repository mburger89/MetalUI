import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Spec §4.1 tests 1.33–1.37 (M7-b): warm frames and their work, counted and
// never timed (ruling `HT-I`), and the text-system default (`HT-J`).

/// 1.33 — the first frame uploads its glyphs and its image; a forced redraw of
/// the unchanged window uploads nothing (the atlas's dirty rect was cleared,
/// the image texture is the same identity). Mutation: the renderer skips
/// `clearDirtyRect()`.
@Test @MainActor func theSecondUnchangedFrameUploadsNothing() throws {
    let bitmap = ImageBitmap(width: 4, height: 4, rgba: [UInt8](repeating: 255, count: 64))
    let window = try harnessWindow {
        VStack {
            Text("Warm")
            Image(decorative: bitmap, scale: 1)
        }
    }
    let first = window.lastFrameWork
    #expect(first.atlasUploadPixels > 0, "the first frame packs and uploads its glyphs")
    #expect(first.newTextures == 1 && first.newTexturePixels == 16, "and its one 4 × 4 image")
    window.window.setNeedsRedraw()
    window.tick()
    let second = window.lastFrameWork
    #expect(second.atlasUploadPixels == 0)
    #expect(second.newTextures == 0 && second.newTexturePixels == 0)
    #expect(second.glyphs == first.glyphs && second.images == 1, "the same scene was presented")
}

/// A box whose `onAppear` widens it — a settle build at open (`LC-E`).
private struct HarnessSettling: Component {
    @State var width: Float = 10
    var content: some ElementGroup {
        Box().frame(width: Pixels(width), height: Pixels(7)).background(.accent)
            .onAppear { width = 30 }
    }
}

/// 1.34 — a frame's work sums every build of it: an `onAppear` write makes the
/// first frame build twice (`LC-E`), and `lastFrameWork.builds` reads 2.
/// Mutation: the accumulator reset per build.
@Test @MainActor func frameWorkSumsEveryBuildOfAFrame() throws {
    let window = try harnessWindow { VStack(spacing: 0) { HarnessSettling() } }
    #expect(window.framesDrawn == 1)
    #expect(window.lastFrameWork.builds == 2)
    #expect(window.frameWork.count == 1)
}

/// The drag loop's model, written from the window's fallback `onInput`.
@Observable @MainActor final class HarnessDragModel {
    var dragging = false
    var dx: Float = 0
}

/// One fixed 20 × 20 proposal leaf: a frame node over a shape leaf.
@MainActor private func workLeaf() -> some ProposalElementGroup {
    Rectangle().fill(.accent).frame(width: Pixels(20), height: Pixels(20))
}

/// 1.35 — a warm drag loop does the same layout work every frame, and the
/// literals are derived BEFORE the run from the stack algorithm
/// (`solveLinearStack`, CN-B; the cache is per run, SA-M; `HT-R` item 3):
///
/// The tree: `H = HStack(spacing: 0) { V1, V2 }`, each `V = VStack(spacing: 0)`
/// of three `F` (a fixed 20 × 20 frame) over `L` (a shape leaf); the last leaf
/// of V2 is `.offset` by the drag (a paint-only layer, no node). The root is
/// proposed (400, 300).
///
/// **Measure H at (400, 300)**: 1 miss. Two members, so each V is probed at
/// (∞, 300) and (0, 300), then V1 is served (200, 300) and V2 (380, 300).
/// - V at (∞, 300): 1 miss; three members, so each F is probed at (∞, ∞) and
///   (∞, 0) and served (∞, 100), (∞, 140), (∞, 260): 3 F misses each; every F
///   proposes L (20, 20): the first a miss and a call, the other two hits —
///   13 misses, 6 hits, 3 calls.
/// - V at (0, 300) and at the served (200, 300) / (380, 300): 1 miss, 9 F
///   misses, 9 L hits each — 10 misses, 9 hits.
/// - Per V: 33 misses, 24 hits, 3 calls; H: 1 + 66 = **67 misses, 48 hits,
///   6 calls**.
///
/// **Place H** (cross proposal given, no re-measure): its solve re-asks the
/// four probes and two offers (6 hits); placing each V re-solves at its served
/// proposal (2 F probes + 1 offer, × 3 = 9 hits) and placing each F asks L
/// (20, 20) once (3 hits): 12 per V. **30 hits.**
///
/// **Per frame: 6 calls, 78 hits, 67 misses**; one build per drag frame; 10
/// frames sum to 60, 780, 670. The frame the press draws (V2 inserted) reads
/// the same — the stale-read arm. Mutations: the frame accumulator not reset
/// at `finishFrame` (frame 2 reads twice frame 1); the hook reads the
/// previous build's work (the press frame reads the open frame's, one stack).
@Test @MainActor func aWarmDragLoopCountsLayoutWorkPerFrame() throws {
    let model = HarnessDragModel()
    let window = try harnessWindow(options: .init(accessibilityClientActive: false), recordsLayout: false) {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                workLeaf()
                workLeaf()
                workLeaf()
            }
            if model.dragging {
                VStack(spacing: 0) {
                    workLeaf()
                    workLeaf()
                    workLeaf().offset(x: Pixels(model.dx))
                }
            }
        }
    }
    window.window.onInput = { (event: InputEvent) -> Bool in
        switch event {
        case .mouseDown: model.dragging = true
        case .mouseDragged(let mouse): model.dx = mouse.position.x.value
        default: break
        }
        return false
    }
    let perFrame = [1, 6, 78, 67]
    func layout(_ work: FrameWork) -> [Int] {
        [work.builds, work.layoutMeasureCalls, work.layoutCacheHits, work.layoutCacheMisses]
    }
    window.send(.mouseDown(MouseEvent(position: pt(10, 10))))
    window.tick()
    #expect(layout(window.lastFrameWork) == perFrame, "the press frame, V2 inserted")

    window.resetFrameWork()
    for step in 1...10 {
        window.send(.mouseDragged(MouseEvent(position: pt(10 + Float(step), 10))))
        window.advanceFrames(1)
    }
    try #require(window.frameWork.count == 10)
    for (index, work) in window.frameWork.enumerated() {
        #expect(layout(work) == perFrame, "drag frame \(index + 1)")
    }
    let sum = window.frameWork.reduce(FrameWork(), +)
    #expect(layout(sum) == [10, 60, 780, 670])
}

/// 1.36 — an unchanged path is rasterized once: frame 1 rasterizes its
/// coverage, a forced redraw hits the window's `RasterCache` and rasterizes
/// nothing (`GX-K`). Mutation: the hook reads the counters before the build.
@Test @MainActor func anUnchangedPathIsRasterizedOnceAcrossFrames() throws {
    let triangle = Path { p in
        p.move(to: pt(0, 0))
        p.addLine(to: pt(40, 40))
        p.addLine(to: pt(0, 40))
        p.closeSubpath()
    }
    let window = try harnessWindow {
        triangle.fill(.accent).frame(width: Pixels(40), height: Pixels(40))
    }
    #expect(window.lastFrameWork.rasterizedPixels > 0, "frame 1 rasterized the triangle")
    window.window.setNeedsRedraw()
    window.tick()
    #expect(window.lastFrameWork.rasterizedPixels == 0, "frame 2 hit the cache")
    #expect(window.lastFrameWork.images == 1, "and still drew it")
}

#if canImport(Darwin)
/// 1.37 (Apple arm) — with no text system a harness window draws text with
/// CoreText, as `App` does (`HT-J`). Mutation: `App.hasDefaultTextSystem`
/// answers `false`.
@Test @MainActor func theDefaultTextSystemIsCoreTextOnApple() throws {
    let window = try TestWindow(size: sz(400, 300)) { Text("CoreText") }
    #expect(!window.scene.glyphs.isEmpty)
}
#else
/// 1.37 (Linux and Windows arm) — with no text system the harness throws
/// rather than trapping inside `Window.init` (`HT-J`). Off Apple the
/// `#else` branch of `TestApp.init` throws whatever `App.hasDefaultTextSystem`
/// answers; the macOS arm above is the mutated one.
@Test @MainActor func aMissingTextSystemThrowsOffApple() throws {
    #expect(throws: TestHarnessError.textSystemRequired) {
        _ = try TestWindow(size: sz(400, 300)) { Text("none") }
    }
}
#endif
