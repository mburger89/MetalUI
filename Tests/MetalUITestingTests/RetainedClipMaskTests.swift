import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// R4-5 PR C (`CM-A`, record 220): an ellipse clip inside an `.equatable()` occurrence is a masked group on a replayed frame too.
// The recorded leaves carry their mask mark; `replayPaint`'s fast path inserts them through `insertLeaves`, a moved replay
// translates the mask with the content (`RetainedTranslation.movedOps`), and a mask that cannot be moved refuses by name.

private struct ClippedPair: Component, @MainActor Equatable {
    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            Color(.accent).frame(width: Pixels(50), height: Pixels(60))
            Color(.separator).frame(width: Pixels(50), height: Pixels(60))
        }
        .clipShape(Ellipse())
    }
}

/// The group's mask scene's first rect and the group's content rects, as plain bytes: equal for equal draws.
private func maskedBytes(_ scene: Scene) -> [[UInt8]] {
    guard let inner = scene.groupScenes.first, let mask = scene.groupMasks.first.flatMap({ $0 }) else { return [] }
    return [scene.groups.withUnsafeBytes { Array($0) }, inner.rects.withUnsafeBytes { Array($0) },
            mask.rects.withUnsafeBytes { Array($0) }]
}

/// **CM-A.** Frame 2 replays (`retainedHits > 0`, `retainedReplayedOps > 0`) and its scene holds the same masked group as frame 1,
/// byte for byte. Mutation: `replayPaint`'s fast path back to `insertIntoScene` (the replay draws the bare rects and no group).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts are not its to read"))
@MainActor
func aRetainedReplayOfAMaskedClipEqualsAFreshFrame() throws {
    let window = try TestWindow(size: sz(200, 200), textSystem: { harnessTextSystem() }) { ZStack(alignment: .topLeading) { ClippedPair().equatable() } }
    window.window.setNeedsRedraw(); window.tick()
    let first = window.scene
    try #require(first.groups.count == 1 && first.groupMasks[0] != nil, "set up: the first frame is a masked group: \(first.groups.count)")
    let firstBytes = maskedBytes(first)
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.retainedHits > 0 && sum.retainedReplayedOps > 0, "a replay happened: \(sum.retainedHits) hits")
    let replayed = window.scene
    #expect(replayed.groups.count == 1 && replayed.groupMasks[0] != nil, "still one masked group")
    #expect(maskedBytes(replayed) == firstBytes, "the same bytes as the fresh frame")
}

/// A card under a header that grows: the card's occurrence moves down and replays translated.
private struct MovedCard: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: Pixels(0)) {
            Box().frame(width: Pixels(100), height: Pixels(10 + side.inputs.offset)).background(.accent)
            ClippedPair().equatable()
        }
    }
}

/// **CM-A.** An occurrence that holds a mask scope has passed a scope opened inside it, so a move is refused by name
/// (`innerScope`, `FS-D`) and the occurrence repaints: the retaining window's masked group equals the retention-off window's, the
/// mask's ellipse lower with the card, and no replay translated. `movedOps`' mark handling is thereby
/// unreachable today (the gate refuses first); it is kept for the day `innerScopes` loosens. Mutation: the mask scope not
/// counted as an inner scope would let the move through unmasked (the mask stays at its old place); the refusal is what holds.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"))
@MainActor
func aMaskedClipInsideAnOccurrenceMissesWhenItMovesAndEqualsAFreshFrame() throws {
    let pair = try RPPair(size: sz(200, 200), scale: 2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { MovedCard(side: side) }
    }
    let before = pair.on.scene
    try #require(before.groups.count == 1, "set up: \(before.groups.count) groups")
    let beforeY = try #require(before.groupMasks[0]?.rects.first?.bounds.origin.y)
    pair.on.resetFrameWork()
    for s in [pair.onSide, pair.offSide] { s.inputs.offset += 4 }
    pair.redraw()
    let work = pair.on.lastFrameWork
    #expect(work.retainedTranslated == 0 && work.retainedTranslationRefusedReasons["innerScope", default: 0] > 0,
            "the move is refused by name: \(work.retainedTranslated) translated, \(work.retainedTranslationRefusedReasons)")
    let moved = pair.on.scene, fresh = pair.off.scene
    let movedY = try #require(moved.groupMasks.first.flatMap { $0 }?.rects.first?.bounds.origin.y)
    #expect(movedY > beforeY, "the mask moved with the content: \(beforeY) to \(movedY)")
    #expect(maskedBytes(moved) == maskedBytes(fresh), "equal to the retention-off window's frame")
}

// R4-5 PR E lane 1 (`TZ-B`, record 222): a clip between two rotations is a masked group too, so a replay re-groups it.
private struct NestedClipCard: Component, @MainActor Equatable {
    var content: some ElementGroup {
        Color(.accent).frame(width: Pixels(100), height: Pixels(100)).rotationEffect(.degrees(30))
            .frame(width: Pixels(60), height: Pixels(60)).clipped().rotationEffect(.degrees(30))
            .padding(Edges(all: Pixels(60)))
    }
}

/// **TZ-B.** A clip between two 30-degree rotations inside an `.equatable()` occurrence replays (`retainedHits > 0`) as the same
/// masked group, byte for byte. Mutation **L8**: `replayPaint`'s fast path back to `insertIntoScene` per primitive (the replay
/// draws the content under its box and no group).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts are not its to read"))
@MainActor
func aRetainedReplayUnderANestedClipEqualsAFreshFrame() throws {
    let window = try TestWindow(size: sz(200, 200), textSystem: { harnessTextSystem() }) { ZStack(alignment: .topLeading) { NestedClipCard().equatable() } }
    window.window.setNeedsRedraw(); window.tick()
    let first = window.scene
    try #require(first.groups.count == 1 && first.groupMasks[0] != nil, "set up: the first frame is a masked group: \(first.groups.count)")
    let firstBytes = maskedBytes(first)
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.retainedHits > 0 && sum.retainedReplayedOps > 0, "a replay happened: \(sum.retainedHits) hits")
    let replayed = window.scene
    #expect(replayed.groups.count == 1 && replayed.groupMasks[0] != nil, "still one masked group")
    #expect(maskedBytes(replayed) == firstBytes, "the same bytes as the fresh frame")
}
