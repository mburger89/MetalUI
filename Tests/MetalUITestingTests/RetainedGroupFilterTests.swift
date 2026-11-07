import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// R4-5 PR B (`GF-D`, record 219): a filtered group inside an `.equatable()` occurrence is produced again on a replayed
// frame. The recorded leaves are the paint values (the shadow's leaf holds an opacity mark the replay keeps), and
// `replayPaint` inserts them through `insertLeaves` -> `insertIntoScene`, which routes the GPU filter again.

private struct MixedShadow: Component, @MainActor Equatable {
    var content: some ElementGroup {
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color(.accent).frame(width: Pixels(60), height: Pixels(60))
                Color(.separator).frame(width: Pixels(60), height: Pixels(60)).offset(x: Pixels(30), y: Pixels(30))
            }
            .compositingGroup()
            .opacity(0.5)
            Color(.accent).frame(width: Pixels(20), height: Pixels(20)).offset(x: Pixels(100), y: Pixels(100))
        }
        .compositingGroup()
        .shadow(color: .black, radius: Pixels(2), x: Pixels(4), y: Pixels(4))
    }
}

/// **T10** (`GF-D`). Frame 2 replays (`retainedHits > 0`, `retainedReplayedOps > 0`) and holds the same filtered group as
/// frame 1: a shadow filter of the same sigma and tint, with the inner opacity group inside it. Mutation: the sigma read
/// from the live scope at insert instead of from the paint (a replay outside the scope would read 0).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the hit counts are not its to read"))
@MainActor func aRetainedReplayOfAFilteredGroupEqualsAFreshFrame() throws {
    let window = try TestWindow(size: sz(200, 200), textSystem: { harnessTextSystem() }) { ZStack(alignment: .topLeading) { MixedShadow().equatable() } }
    window.window.setNeedsRedraw(); window.tick()
    let first = window.scene
    let filtered = first.groupFilters.firstIndex { $0.kind == .shadow }
    try #require(filtered != nil, "set up: the first frame filters on the GPU route: \(first.groupFilters)")
    window.resetFrameWork()
    for _ in 0..<3 { window.window.setNeedsRedraw(); window.tick() }
    let sum = window.frameWork.dropFirst().reduce(window.frameWork[0], +)
    #expect(sum.retainedHits > 0 && sum.retainedReplayedOps > 0, "a replay happened: \(sum.retainedHits) hits")
    let replayed = window.scene
    #expect(replayed.groupFilters == first.groupFilters, "the same filters: \(replayed.groupFilters) for \(first.groupFilters)")
    #expect(replayed.groups.map { [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height] } == first.groups.map { [$0.bounds.origin.x, $0.bounds.origin.y, $0.bounds.size.width, $0.bounds.size.height] }, "the same boxes")
    let index = try #require(replayed.groupFilters.firstIndex { $0.kind == .shadow })
    #expect(replayed.groupScenes[index].groups.count == first.groupScenes[filtered!].groups.count, "the inner opacity group is kept")
}
