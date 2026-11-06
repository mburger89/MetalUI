import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// R4-5 PR A (`GO-G`, record 218): an opacity group inside an `.equatable()` occurrence composites again on a replayed
// frame. The recorded leaves carry their group mark; `replayPaint`'s fast path inserts them through `insertLeaves`,
// not `insertIntoScene` (which bakes a mark away and would replay the squares faded one by one).

private struct FadedPair: Component, @MainActor Equatable {
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            Color(.accent).frame(width: Pixels(60), height: Pixels(60))
            Color(.separator).frame(width: Pixels(60), height: Pixels(60)).offset(x: Pixels(30), y: Pixels(30))
        }
        .compositingGroup()
        .opacity(0.5)
    }
}

/// **GO-G.** Frame 2 replays (`retainedHits > 0`, `retainedReplayedOps > 0`) and its scene holds the same group as
/// frame 1: one quad at 0.5, two unfaded squares inside. Mutation: `replayPaint`'s fast path back to
/// `insertIntoScene` (the replay draws two half-alpha squares and no group).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts are not its to read"))
@MainActor func aRetainedReplayOfAnOpacityGroupStillComposites() throws {
    let window = try TestWindow(size: sz(200, 200), textSystem: { harnessTextSystem() }) { ZStack(alignment: .topLeading) { FadedPair().equatable() } }
    window.window.setNeedsRedraw(); window.tick()
    let first = window.scene
    try #require(first.groups.count == 1, "set up: the first frame composites: \(first.groups.count)")
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.retainedHits > 0 && sum.retainedReplayedOps > 0, "a replay happened: \(sum.retainedHits) hits")
    let replayed = window.scene
    #expect(replayed.groups.count == 1 && replayed.groups[0].opacity == 0.5, "still one group at 0.5")
    #expect(replayed.groupScenes[0].rects.count == 2 && replayed.groupScenes[0].rects.allSatisfy { $0.background.a == 1 },
            "two unfaded squares inside")
    #expect(replayed.rects.count == first.rects.count, "nothing drawn beside it")
}
