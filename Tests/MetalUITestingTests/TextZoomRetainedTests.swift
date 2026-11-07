import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// R4-5 PR E lane 2 (`TZ-A`, record 223): a retained zoom replays its paint through the live scopes, so its text is re-keyed at
// insert (`RZ-A`: the replayed glyphs are base glyphs, the scene is re-keyed when it is built). The differential is the
// retained-zoom fixture (`ZoomFixture.swift`), whose nodes hold text under `scaleEffect`.

/// **16 (`TZ-A`, `RZ-A`).** A zoom step to 2 of the retained-zoom fixture grafts (no redo) and its scene equals the unretained
/// window's, glyph for glyph; every glyph's slot is about twice the slot before the step (the fixture draws at window scale 2,
/// so the glyphs rasterize at 2 then 4). Mutation **T9**: the replayed glyphs inserted without the re-key (a re-key gated on a
/// fresh emission): the slots stay at the base raster and the step no longer separates.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the graft counts are not its to read"))
@MainActor func aRetainedZoomReplayRekeysItsGlyphs() async throws {
    let pair = try zoomPair()
    try pair.compare("warm")
    let before = pair.on.scene.glyphs.map { $0.atlasBounds.size.width }
    try #require(before.count > 50, "set up: the fixture paints text (\(before.count) glyphs)")
    await zoomStep(pair, to: 2)
    let step = try #require(pair.frames.last)
    try pair.compare("zoom to 2")
    #expect(step.retainedGrafts > 0 && step.retainedRedos == 0, "grafts \(step.retainedGrafts) redos \(step.retainedRedos)")
    let after = pair.on.scene.glyphs.map { $0.atlasBounds.size.width }
    try #require(after.count == before.count, "the same glyphs")
    var enlarged = 0
    for (b, a) in zip(before, after) where a > 1.5 * b { enlarged += 1 }
    #expect(enlarged == before.count, "\(enlarged) of \(before.count) glyph slots are re-keyed")
}
