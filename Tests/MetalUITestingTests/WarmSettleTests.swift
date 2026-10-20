import MetalUI
import MetalUITesting
import Testing

// C14-e lane 2 (`CF-E`, `CF-G`, `CF-J`, record 127): the warm frame pin. MetalCreator saw `layoutMeasureCalls` read 2, 80, 2, 2...
// over seven `redraw()`s of a persistent window. Reproduced here on the bracket fixture's `.panels` arm (its panels are
// `.equatable()` components over a `List`, a canvas and text): the spike is the first frame that grafts a retained occurrence,
// whose layout the placement memo had restored (and so not looked up) for a frame before. Fixed in `LayoutMemo` (a placement
// carries a footprint, a restore touches it): the frame after the retained records exist does exactly the work of every later one.

@MainActor private func wsWarm(frames: Int, afterWarm warm: Int) throws -> [FrameWork] {
    let model = BracketModel(), viewport = BracketViewport()
    let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2, recordsLayout: false,
                           textSystem: harnessTextSystem) { bracketRoot(arm: .panels, model: model, viewport: viewport) }
    for _ in 0..<warm { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    for _ in 0..<frames { w.window.setNeedsRedraw(); w.tick() }
    return w.frameWork
}

/// W1 — with one frame drawn before `resetFrameWork()` (the retained records exist), seven unchanged redraws do exactly the
/// same work on every `FrameWork` field, and none of it is raster, atlas or texture work. **Red before (679f5d7d):** frame 0
/// reads `layoutMeasureCalls` 135 against 52 (249 memo misses). **Mutation:** `memo.touch` removed from `subtreePlacement`.
@Test @MainActor func aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst() throws {
    let frames = try wsWarm(frames: 7, afterWarm: 1)
    try #require(frames.count == 7)
    for (n, work) in frames.enumerated() {
        #expect(work == frames[0], "frame \(n) differs from frame 0: \(work)")
        #expect(work.atlasUploadPixels == 0 && work.rasterizedPixels == 0 && work.newTextures == 0)
    }
    #expect(frames[0].layoutMemoMisses == 0 && frames[0].layoutMeasureCalls == frames[6].layoutMeasureCalls)
}

/// W2 — with nothing drawn before the reset, frame 0 makes the retained records (a counted miss each) and is the one frame
/// that differs; every frame after it equals every other (`CF-E`'s ruling: stable from the frame after the records exist).
/// **Red before:** frame 1 reads 135 measures, frames 0 and 2 read 52. **Mutation:** as W1.
@Test @MainActor func theFrameAfterTheRecordsAreMadeIsAlreadySettled() throws {
    let frames = try wsWarm(frames: 7, afterWarm: 0)
    try #require(frames.count == 7)
    #expect(frames[0].retainedMisses > 0 && frames[1].retainedMisses == 0, "frame 0 makes the records: \(frames[0].retainedMisses)")
    for (n, work) in frames.enumerated().dropFirst() {
        #expect(work == frames[1], "frame \(n) differs from frame 1: \(work)")
        #expect(work.atlasUploadPixels == 0 && work.rasterizedPixels == 0 && work.newTextures == 0)
    }
}
