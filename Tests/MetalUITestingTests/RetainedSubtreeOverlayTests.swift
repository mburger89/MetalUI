import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 1 (`SB-P`, GT-F): world-anchored `Text` overlays over a `GPUSurface`, each label an
// `.equatable()` component, counted at the text-system seam. The boundary of what retained subtrees
// remove: a label that does not move costs nothing after its first frame; one that moves under an `.offset`
// replays translated (`RK-S`) and costs nothing either. `MetalDrawContext.drawText` stays deferred (`RK-I`).

private struct OverlayLabel: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text) }
}

struct OverlayArm: CustomStringConvertible, Sendable {
    let labels: Int, moving: Bool, scale: Float
    var description: String { "\(labels) labels, \(moving ? "moving" : "static"), scale \(scale)" }
}
let overlayArms = [20, 100].flatMap { n in
    [false, true].flatMap { moving in [Float(1), Float(2)].map { OverlayArm(labels: n, moving: moving, scale: $0) } }
}

@MainActor private func equatableOverlay(labels n: Int, moving: Bool, model: CameraModel, scale: Float = 1,
                                         counting: CountingTextSystem) throws -> TestWindow {
    try TestWindow(size: sz(800, 600), scaleFactor: scale, textSystem: { counting }) {
        ZStack(alignment: .topLeading) {
            GPUSurface(redraw: .onDemand, value: model.phase) { _ in }
            ForEach(Array(0..<n), id: \.self) { i in
                ZStack { OverlayLabel(text: "\(i).5 mm").equatable() }
                    .offset(x: Pixels(Float(i % 10) * 70 + (moving ? model.phase : 0)),
                            y: Pixels(Float(i / 10) * 20 + (moving ? model.phase * 0.5 : 0)))
            }
        }
    }
}

/// 1.18 — GT-F re-taken twice. **`SB-P`** (lane 1 of C14b, a label that moves misses on the offset outside it and costs
/// the unchanged 1 measure and 1 `placeGlyphs` each) and **`RK-I`** (C14b-2, after translated replay, `RK-S`): per
/// camera frame, N labels, the camera moving every frame (the surface redraws), at scale 1 (the offsets move by
/// half-point steps: fractional device pixels) and 2 (whole device pixels), the criterion fixed beforehand: *a label moved
/// by a whole device pixel at scale 2 reads 0 `placeGlyphs` and 0 seam measures on the replay frame*, or `drawText` is
/// built. **Static labels** are all hits and cost 0 `placeGlyphs` and 0 seam measures after the first frame;
/// **moving labels** are now all translated hits too, at either scale (the paint replays through the live offset
/// scope), also at 0 `placeGlyphs` and 0 measures: the criterion holds and `MetalDrawContext.drawText` and its SDL
/// twin stay deferred (`GT-F`). The cost that remains for a moving label is the build (one layout memo hit) and the
/// ledger's hitbox move, never text. Mutation: `hit = false` in the decision reddens the static arm; the effect-translation
/// relaxation removed from `ReplayKey` reddens the moving arm (`retainedTranslated == 0`, `places == frames * n`).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the paint-skipped counts this test pins are not its to read"), arguments: overlayArms) @MainActor
func aStaticLabelOverlayReplaysAndAMovingOneReplaysTranslated(arm: OverlayArm) throws {
    let (n, moving, scale) = (arm.labels, arm.moving, arm.scale)
    let model = CameraModel()
    let counting = CountingTextSystem(harnessTextSystem())
    let window = try equatableOverlay(labels: n, moving: moving, model: model, scale: scale, counting: counting)
    for _ in 0..<3 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() } // warm
    counting.reset()
    window.resetFrameWork()
    let frames = 5
    for _ in 0..<frames { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
    let w = window.frameWork
    try #require(w.count == frames)
    let sum = w.dropFirst().reduce(w[0], +)
    #expect(sum.retainedHits + sum.retainedMisses + sum.retainedIneligible == frames * n)
    #expect(sum.retainedHits == frames * n)
    #expect(sum.retainedMisses == 0)
    #expect(counting.places == 0)
    if !layoutMemoVerifying { #expect(counting.measures == 0) }
    #expect(sum.retainedSkippedPaints > 0)
    #expect(sum.retainedTranslated == (moving ? frames * n : 0), "moving labels replay translated: \(sum.retainedTranslated)")
    #expect(sum.atlasUploadPixels == 0 && sum.rasterizedPixels == 0 && sum.newTextures == 0)
}
