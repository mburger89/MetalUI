import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14b lane 1 (`SB-P`, GT-F): world-anchored `Text` overlays over a `GPUSurface`, each label an
// `.equatable()` component, counted at the text-system seam. The boundary of what retained subtrees
// remove: a label that does not move costs nothing after its first frame; one that moves misses on the
// offset outside it and costs what it always did. `MetalDrawContext.drawText` stays deferred.

private struct OverlayLabel: Component, @MainActor Equatable {
    let text: String
    var content: some ElementGroup { Text(text) }
}

@MainActor private func equatableOverlay(labels n: Int, moving: Bool, model: CameraModel,
                                         counting: CountingTextSystem) throws -> TestWindow {
    try TestWindow(size: sz(800, 600), textSystem: { counting }) {
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

/// 1.18 — GT-F re-taken (`SB-P`). Per camera frame, N labels, the camera moving every frame (the
/// surface redraws): **static labels** are all hits and cost 0 `placeGlyphs` and 0 seam measures after
/// the first frame; **moving labels** (the overlay case GT-F is about) all miss on the offset outside
/// them and cost the unchanged 1 measure and 1 `placeGlyphs` each. Mutation: `hit = false` in the
/// decision reddens the static arm; the scope signature dropped from the key reddens the moving arm
/// (the labels replay at their old places).
@Test(arguments: [20, 100], [false, true]) @MainActor
func aStaticLabelOverlayReplaysAndAMovingOneDoesNot(labels n: Int, moving: Bool) throws {
    let model = CameraModel()
    let counting = CountingTextSystem(harnessTextSystem())
    let window = try equatableOverlay(labels: n, moving: moving, model: model, counting: counting)
    for _ in 0..<3 { model.phase += 1; window.window.setNeedsRedraw(); window.tick() } // warm
    counting.reset()
    window.resetFrameWork()
    let frames = 5
    for _ in 0..<frames { model.phase += 1; window.window.setNeedsRedraw(); window.tick() }
    let w = window.frameWork
    try #require(w.count == frames)
    let sum = w.dropFirst().reduce(w[0], +)
    #expect(sum.retainedHits + sum.retainedMisses + sum.retainedIneligible == frames * n)
    if moving {
        #expect(sum.retainedHits == 0)
        #expect(sum.retainedMisses == frames * n)
        #expect(counting.places == frames * n)
        if !layoutMemoVerifying { #expect(counting.measures == frames * n) }
    } else {
        #expect(sum.retainedHits == frames * n)
        #expect(sum.retainedMisses == 0)
        #expect(counting.places == 0)
        if !layoutMemoVerifying { #expect(counting.measures == 0) }
        #expect(sum.retainedSkippedPaints > 0)
    }
    #expect(sum.atlasUploadPixels == 0 && sum.rasterizedPixels == 0 && sum.newTextures == 0)
}
