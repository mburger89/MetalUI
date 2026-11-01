import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// `GL-A`..`GL-F` (record 184): a full glyph atlas used to drop text silently and for good. The window now
// grows the atlas inside a frame (no slot moves), rebuilds it between frames (every holder of a slot misses),
// and counts what it must drop past its cap. Counts and pixels, never time.
//
// **The oracle for "this glyph's pixels are its coverage"** is a fresh window drawing the same content: the
// i-th emitted glyph's atlas block must equal the i-th block of the fresh window's frame, byte for byte.
// The atlas rect alone cannot be compared (a rebuilt or grown atlas puts glyphs elsewhere); the pixels at it can.

private let sample = "The quick brown fox 0123456789%"

@MainActor private final class ZoomModel {
    var zoom = 1.0
    var banner = ""
    var text = sample
}

/// A card: its text at `14 * zoom`, `.equatable()` on its value like MetalFlow's node cards.
private struct Card: Component, @MainActor Equatable {
    let k: Int
    let zoom: Double
    var content: some ElementGroup {
        Text("Card \(k) \(sample)").font(size: 14 * zoom).frame(width: Pixels(380), height: Pixels(40))
    }
}

@MainActor private func zoomWindow(_ model: ZoomModel, scale: Float = 2) throws -> TestWindow {
    try harnessWindow(size: sz(400, 300), scaleFactor: scale) {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.banner).font(size: 20).frame(width: Pixels(380), height: Pixels(30))
            Card(k: 1, zoom: model.zoom).equatable()
            Card(k: 2, zoom: model.zoom).equatable()
            Text(model.text).font(size: 14 * model.zoom).frame(width: Pixels(380), height: Pixels(40))
        }
    }
}

private func glyphBytes(_ glyphs: [MUIGlyph]) -> [UInt8] {
    glyphs.withUnsafeBytes { Array($0) }
}

@MainActor private func redraw(_ window: TestWindow) {
    window.window.setNeedsRedraw()
    window.tick()
}

/// The atlas bytes under every emitted glyph, in emission order.
@MainActor private func blocks(_ window: TestWindow) -> [[UInt8]] {
    let atlas = window.window.glyphAtlas
    return window.scene.glyphs.map { glyph in
        let box = glyph.atlasBounds
        let x = Int(box.origin.x), y = Int(box.origin.y), w = Int(box.size.width), h = Int(box.size.height)
        var out: [UInt8] = []
        guard x >= 0, y >= 0, x + w <= atlas.width, y + h <= atlas.height else { return [255, 255, 255] }
        for row in 0..<h { out += atlas.pixels[((y + row) * atlas.width + x)..<((y + row) * atlas.width + x + w)] }
        return out
    }
}

/// A fresh window's blocks for `model`'s current content.
@MainActor private func freshBlocks(zoom: Double, text: String, banner: String = "") throws -> (blocks: [[UInt8]], glyphs: [MUIGlyph]) {
    let model = ZoomModel()
    model.zoom = zoom; model.text = text; model.banner = banner
    let fresh = try zoomWindow(model)
    redraw(fresh)
    return (blocks(fresh), fresh.scene.glyphs)
}

/// **The sweep** (`GL-A`, `GL-B`): MetalFlow's zoom from 25% to 150% in 1% steps at scale 2 used to fill
/// all 1024 rows and then drop every new glyph ("150%" drew as "15 %"). Now no frame drops one, every glyph
/// of the last frame is inked and equals a fresh window's, and the atlas was rebuilt along the way.
/// Mutations (each reddens it): `maximumExtent` back to the starting size and `wantsReclaim` false (drops > 0
/// and a blank block); `wantsReclaim` false alone (the atlas grows to its cap and then drops).
@Test @MainActor func aZoomSweepNeverDropsAGlyph() throws {
    let model = ZoomModel()
    let window = try zoomWindow(model)
    redraw(window)
    var blank = 0
    for percent in 25...150 {
        model.zoom = Double(percent) / 100
        model.text = "Zoom \(percent)%"
        redraw(window)
        for block in blocks(window) where !block.contains(where: { $0 != 0 }) { blank += 1 }
    }
    let atlas = window.window.glyphAtlas
    #expect(atlas.droppedGlyphs == 0, "a glyph was dropped during the sweep")
    #expect(blank == 0, "\(blank) emitted glyphs pointed at blank pixels")
    // The sweep needed far more than one atlas of 1024 x 1024: it grew or rebuilt along the way.
    #expect(atlas.growCount + atlas.reclaimCount >= 2, "grew \(atlas.growCount), rebuilt \(atlas.reclaimCount)")
    #expect(atlas.reclaimCount >= 1, "stale glyphs are reclaimed, not grown over for ever")

    // A string never drawn before, at a size never drawn before.
    model.zoom = 1.37
    model.text = "Fresh glyphs 150%"
    redraw(window)
    let fresh = try freshBlocks(zoom: 1.37, text: "Fresh glyphs 150%")
    let swept = blocks(window)
    #expect(window.scene.glyphs.count == fresh.glyphs.count, "a glyph is missing from the swept window's frame")
    try #require(swept.count == fresh.blocks.count)
    #expect(swept == fresh.blocks, "a swept glyph's pixels are not its coverage")
    #expect(swept.allSatisfy { $0.contains { $0 != 0 } })
    #expect(window.window.glyphAtlas.droppedGlyphs == 0)
}

/// **One frame bigger than one atlas** (`GL-B`): ten 250-point glyphs at scale 2 are about 1.4 million pixels,
/// more than 1024 x 1024. The first frame that asks grows the atlas in place; every glyph draws, in that
/// same frame. Mutation: `growAndPlace` returns nil (drops > 0, glyph count short).
@Test @MainActor func aSingleFramesWorkingSetLargerThanTheAtlasGrowsIt() throws {
    let model = ZoomModel()
    model.text = "ABCDEFGHIJ"
    let window = try harnessWindow(size: sz(2600, 500), scaleFactor: 2) {
        Text(model.text).font(size: 250).frame(width: Pixels(2500), height: Pixels(400))
    }
    redraw(window)
    let atlas = window.window.glyphAtlas
    #expect(atlas.growCount >= 1 && atlas.width >= 2048, "the atlas stayed \(atlas.width) wide")
    #expect(atlas.droppedGlyphs == 0)
    #expect(window.scene.glyphs.count == 10, "every glyph of the frame draws in the frame")
    #expect(blocks(window).allSatisfy { $0.contains { $0 != 0 } })
    #expect(atlas.layoutGeneration == 0, "growth moves no slot, so it advances no generation")
}

/// **A retained occurrence across a rebuild** (`GL-D`): two `.equatable()` cards hit their paint record while
/// a banner above them fills the atlas first. The banner goes and the atlas is rebuilt, so the cards' glyphs
/// now sit at other rects. A record keyed without `GlyphAtlas.layoutGeneration` replays the old rects; keyed
/// with it the cards miss and repaint, and the frame equals a fresh window's. Mutation: drop
/// `atlasGeneration` from `retainedAmbientKey()` (the glyph arrays differ).
@Test(.enabled(if: !rsVerifyingForAtlas, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit count is not its to read"))
@MainActor func aRetainedOccurrenceMissesAfterTheAtlasIsRebuilt() throws {
    let model = ZoomModel()
    model.banner = "QWERTYUIOPASDFGHJKL"
    let window = try zoomWindow(model)
    for _ in 0..<6 { redraw(window) }
    #expect(window.lastFrameWork.retainedHits > 0, "the cards must be replaying before the rebuild")

    model.banner = ""
    window.window.glyphAtlas.reclaim()        // between frames, as the window's own policy would
    redraw(window)
    #expect(window.window.glyphAtlas.layoutGeneration == 1)
    #expect(window.lastFrameWork.retainedMisses > 0, "a record from before the rebuild must not replay")
    #expect(window.lastFrameWork.retainedRedos == 0, "the miss is decided before prepaint, not by redoing the frame")

    let fresh = try freshBlocks(zoom: 1.0, text: sample)
    #expect(glyphBytes(window.scene.glyphs) == glyphBytes(fresh.glyphs), "the rebuilt window's glyph sprites differ from a fresh window's")
    #expect(blocks(window) == fresh.blocks)
    redraw(window)
    redraw(window)
    #expect(window.lastFrameWork.retainedHits > 0, "the cards replay again once recorded against the new atlas")
    #expect(glyphBytes(window.scene.glyphs) == glyphBytes(fresh.glyphs))
}

private let rsVerifyingForAtlas = ProcessInfo.processInfo.environment["METALUI_VERIFY_RETAINED"] == "1"

/// **Past the cap** (`GL-E`): an atlas that cannot grow drops what does not fit, counts every drop, asks for
/// no more frames (nothing older to reclaim), and the glyphs that fit still draw. Mutation: no increment
/// (counter 0), or `reclaimRequested` set unconditionally (the window redraws for ever).
@Test @MainActor func pastTheCapGlyphsAreDroppedAndCounted() throws {
    let model = ZoomModel()
    let window = try zoomWindow(model)
    window.window.glyphAtlas = GlyphAtlas(width: 128, height: 128, maximumExtent: 128)
    model.zoom = 1.1   // the cards' values change, so no retained record from the first atlas replays into this one
    redraw(window)
    let atlas = window.window.glyphAtlas
    let fresh = try freshBlocks(zoom: 1.1, text: sample)
    #expect(atlas.droppedGlyphs > 0)
    #expect(window.scene.glyphs.count + atlas.droppedGlyphs == fresh.glyphs.count,
            "every inked glyph of the frame is either drawn or counted")
    #expect(!atlas.reclaimRequested && !window.window.needsRedraw, "nothing older to reclaim: no one more frame")
    #expect(blocks(window).allSatisfy { $0.contains { $0 != 0 } }, "what was drawn is real")
}

/// **Recovery by the next frame at the cap** (`GL-A`): the cap is reached holding the previous text; the
/// next text overflows it, the frame drops, and exactly one more frame is requested - which rebuilds and
/// draws all of it. Mutation: `noteAtlasPressureAfterFrame` does not redraw (the second tick draws nothing
/// new), or `reclaimRequested` is never set (no redraw).
@Test @MainActor func aDropWithStaleGlyphsIsRecoveredByTheNextFrame() throws {
    let model = ZoomModel()
    model.text = "pack my box"
    let window = try harnessWindow(size: sz(400, 100), scaleFactor: 2) {
        Text(model.text).font(size: 14).frame(width: Pixels(380), height: Pixels(40))
    }
    window.window.glyphAtlas = GlyphAtlas(width: 112, height: 112, maximumExtent: 112)
    redraw(window)
    try #require(window.window.glyphAtlas.droppedGlyphs == 0, "the first text must fit, or the fixture proves nothing")
    model.text = "with five dozen liquor jugs"
    redraw(window)
    let atlas = window.window.glyphAtlas
    try #require(atlas.droppedGlyphs > 0, "the second text must overflow, or the fixture proves nothing")
    #expect(window.window.needsRedraw, "the frame that dropped asks for the next one")
    window.tick()
    let dropsBefore = atlas.droppedGlyphs
    let expected = try harnessWindow(size: sz(400, 100), scaleFactor: 2) {
        Text("with five dozen liquor jugs").font(size: 14).frame(width: Pixels(380), height: Pixels(40))
    }
    #expect(atlas.reclaimCount == 1)
    #expect(window.scene.glyphs.count == expected.scene.glyphs.count, "the next frame drew every glyph")
    #expect(atlas.droppedGlyphs == dropsBefore && !window.window.needsRedraw, "and dropped and asked for nothing more")
}

/// **Quiet is quiet** (the hot path): an atlas that is not nearly full rebuilds nothing, grows nothing,
/// requests nothing, over many frames of the same content. Counts, never time.
@Test @MainActor func aSteadyWindowNeverRebuildsOrGrows() throws {
    let model = ZoomModel()
    let window = try zoomWindow(model)
    for _ in 0..<30 { redraw(window) }
    let atlas = window.window.glyphAtlas
    #expect(atlas.reclaimCount == 0 && atlas.growCount == 0 && atlas.droppedGlyphs == 0)
    #expect(atlas.layoutGeneration == 0 && !atlas.wantsReclaim)
}

/// `GL-D`: the window notices a generation it did not cause (the atlas rebuilt by anyone between frames) and
/// drops its atlas-dependent state once. Mutation: drop the `layoutGeneration` comparison in
/// `reclaimAtlasIfNeeded` (the seen generation stays 0).
@Test @MainActor func aWindowNoticesARebuild() throws {
    let model = ZoomModel()
    let window = try zoomWindow(model)
    redraw(window)
    #expect(window.window.atlasLayoutGenerationSeen == 0)
    window.window.glyphAtlas.reclaim()
    redraw(window)
    #expect(window.window.atlasLayoutGenerationSeen == 1)
}
