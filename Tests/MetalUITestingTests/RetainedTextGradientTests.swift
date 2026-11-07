import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// R4-5 PR D (`TG-C`, `TG-D`, record 221): a gradient text inside an `.equatable()` occurrence is one masked group on a replayed
// frame too. The recorded leaf is the gradient primitive carrying its mark (`noteDirect` before `insertLeaves`); a replay
// re-groups it, a moved replay translates the content and EVERY glyph of the mask (the first test that reaches
// `RetainedTranslation.movedLeaf`'s mark loop: a gradient text pushes no scope, so the occurrence is not refused with
// `innerScope`), and a changed gradient parent repaints it. Bytes, never pixels: these run on every platform.

private let tgSweep = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)

private struct GradientLabel: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Text("Hello gradient").frame(width: Pixels(100), height: Pixels(16)).foregroundStyle(tgSweep)
    }
}

/// The group's quad, content (rects, glyphs, images) and mask glyph bytes: equal for equal draws.
private func groupBytes(_ scene: Scene) -> [[UInt8]] {
    guard let inner = scene.groupScenes.first, let mask = scene.groupMasks.first.flatMap({ $0 }) else { return [] }
    return [scene.groups.withUnsafeBytes { Array($0) }, inner.images.withUnsafeBytes { Array($0) },
            inner.glyphs.withUnsafeBytes { Array($0) }, mask.glyphs.withUnsafeBytes { Array($0) },
            mask.rects.withUnsafeBytes { Array($0) }]
}

/// **TG-C.** Frame 2 replays (`retainedHits > 0`) and holds the same masked group as frame 1, byte for byte. Mutation: `replayPaint`
/// back to `insertIntoScene` per primitive (the replay draws a bare gradient box); no `noteDirect` of the marked primitive
/// (the replay draws nothing).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts are not its to read"))
@MainActor
func aRetainedReplayOfGradientTextEqualsAFreshFrame() throws {
    let window = try TestWindow(size: sz(200, 80), textSystem: { harnessTextSystem() }) {
        VStack(alignment: .leading, spacing: 0) { GradientLabel().equatable() }
    }
    window.window.setNeedsRedraw(); window.tick()
    let first = window.scene
    try #require(first.groups.count == 1 && first.groupMasks[0] != nil, "set up: a masked group: \(first.groups.count)")
    try #require(first.glyphs.isEmpty, "set up: the glyphs are the mask's alone")
    let before = groupBytes(first)
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.retainedHits > 0 && sum.retainedReplayedOps > 0, "a replay happened: \(sum.retainedHits) hits")
    #expect(window.scene.groups.count == 1 && window.scene.glyphs.isEmpty)
    #expect(groupBytes(window.scene) == before, "the same bytes as the fresh frame")
}

private struct MovedLabel: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Box().frame(width: Pixels(100), height: Pixels(10 + side.inputs.offset)).background(.accent)
            GradientLabel().equatable()
        }
    }
}

/// **TG-D (stop condition 5).** A moved occurrence holding a gradient text is refused by name, `unlistedKind:gradient` (`FS-E`: the
/// translation allow-list is a rect, a glyph and an image, and a gradient fill has always been refused the same way), NOT
/// `innerScope` (a gradient text pushes no scope), and the repaint equals the retention-off window's frame with the whole mask moved.
/// `RetainedTranslation.movedLeaf`'s mark loop over N mask elements is therefore unreachable today, as `CM` M27 was; it is kept for
/// the day the gate lists a gradient. Mutation: the refusal removed would translate the gradient's old raster and misplace it.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"))
@MainActor
func aMovedOccurrenceHoldingGradientTextIsRefusedByNameAndEqualsAFreshFrame() throws {
    let pair = try RPPair(size: sz(200, 120), scale: 2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { MovedLabel(side: side) }
    }
    let before = pair.on.scene
    try #require(before.groups.count == 1, "set up: \(before.groups.count) groups")
    let beforeY = try #require(before.groupMasks[0]?.glyphs.last?.bounds.origin.y)
    pair.on.resetFrameWork()
    for s in [pair.onSide, pair.offSide] { s.inputs.offset += 4 }
    pair.redraw()
    let work = pair.on.lastFrameWork
    #expect(work.retainedTranslated == 0 && work.retainedTranslationRefusedReasons["unlistedKind:gradient", default: 0] > 0
            && work.retainedTranslationRefusedReasons["innerScope", default: 0] == 0,
            "refused by name: \(work.retainedTranslated), \(work.retainedTranslationRefusedReasons)")
    let moved = pair.on.scene, fresh = pair.off.scene
    let movedY = try #require(moved.groupMasks.first.flatMap { $0 }?.glyphs.last?.bounds.origin.y)
    #expect(movedY > beforeY, "the last glyph of the mask moved with the content: \(beforeY) to \(movedY)")
    #expect(groupBytes(moved) == groupBytes(fresh), "equal to the retention-off window's frame")
}

@Observable @MainActor final class TGParentBox { var fill = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing) }

private struct TGChip: Component, @MainActor Equatable {
    let tag: Int
    var content: some ElementGroup { Text("Hello gradient").frame(width: Pixels(100), height: Pixels(16)) }
    static func == (l: TGChip, r: TGChip) -> Bool { l.tag == r.tag }
}

private struct TGParent: Component {
    let box: TGParentBox
    var content: some ElementGroup {
        let fill = box.fill
        VStack(alignment: .leading, spacing: 4) { TGChip(tag: 1).equatable() }.foregroundStyle(fill)
    }
}

/// **TG-A.** An `.equatable()` child that inherits a gradient reads it through the environment, so a parent that changes the
/// gradient repaints it (the fingerprint's `foregroundStyle` is the whole storage): the new gradient's raster differs, and the
/// retained window equals the retention-off twin. Mutation: the fingerprint equality comparing the representative colour (both
/// gradients start red).
@Test @MainActor func aGradientChangeAboveAnEquatableSubtreeMisses() throws {
    var rasters: [[UInt8]] = []
    for retain in [true, false] {
        let box = TGParentBox()
        let window = try TestWindow(size: sz(200, 80), textSystem: { harnessTextSystem() }) {
            VStack(alignment: .leading, spacing: 0) { TGParent(box: box) }
        }
        window.window.testingRetainedSubtrees = retain
        for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
        let first = window.scene.groupScenes.first?.textures.first?.pixels ?? []
        try #require(!first.isEmpty, "set up: a gradient raster")
        box.fill = LinearGradient(colors: [.red, .green], startPoint: .leading, endPoint: .trailing)
        for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
        let second = window.scene.groupScenes.first?.textures.first?.pixels ?? []
        #expect(second != first, "retain \(retain): the new gradient repainted")
        rasters.append(second)
    }
    #expect(rasters[0] == rasters[1], "the retained frame equals the retention-off twin's")
}
