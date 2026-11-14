import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// Alloy G33(a) A0 follow-ups (`RK-AG`, record 292): a redo suspends replay under the occurrences that caused it, not window-wide.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read"

// MARK: The redo's backoff is scoped (`RK-AG`)

/// An outer occurrence with a nested one: the nested one is hidden from the paint check while the outer one replays.
private struct RPTOuter: Component, @MainActor Equatable {
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("outer").frame(width: Pixels(60), height: Pixels(10))
            RPCard(title: "N", shade: 1, log: log).equatable()
        }
    }
    static func == (l: RPTOuter, r: RPTOuter) -> Bool { l.log === r.log }
}

/// `nested`: the occurrence under the changing ambient holds a nested one. B and C are siblings the ambient does not touch.
@MainActor private func rptRedoRoot(_ side: RPSide, nested: Bool) -> some Element {
    let n = side.model.n
    let log = side.log
    return VStack(spacing: 4) {
        ZStack {
            if nested { RPTOuter(log: log).equatable() } else { RPCard(title: "A", shade: 1, log: log).equatable() }
        }.opacity(n % 2 == 1 ? 0.5 : 1)
        RPCard(title: "B", shade: 2, log: log).equatable()
        RPCard(title: "C", shade: 3, log: log).equatable()
    }
}

/// One redo, then the frames after it: `redo` is the redo frame, `after` the next fourteen builds.
@MainActor private func rptRedoFrames(nested: Bool) async throws -> (pair: RPPair<some Element>, redo: FrameWork, after: [FrameWork]) {
    let pair = try RPPair(size: sz(200, 380), warm: 5) { rptRedoRoot($0, nested: nested) }
    pair.redraw()
    try #require(pair.frames.last?.retainedPrepaintHits ?? 0 >= 3, "replaying before the change: \(String(describing: pair.frames.last))")
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    await rsSettle()
    pair.frames = []
    pair.redraw()
    let redo = try #require(pair.frames.last)
    try #require(redo.retainedRedos == 1, "the ambient change redoes the frame once: \(redo.retainedRedos)")
    try pair.compare("the redo")
    var after: [FrameWork] = []
    for step in 0..<14 {
        pair.redraw()
        after.append(try #require(pair.frames.last))
        try pair.compare("after the redo \(step)")
    }
    return (pair, redo, after)
}

/// A redo suspends replay under the occurrence that caused it, not window-wide: the next frame replays the two siblings the
/// ambient did not touch (it replayed nothing for nine builds, 86 element requests a frame against 30), the offender and
/// what it holds wait their quarantine, there is no second redo, and every frame equals the retention-off window's.
/// **Red before:** hits `[0 x 9, 3 ...]`, requests `[86 x 9, 2 ...]`. **Mutation:** the descendants walk in
/// `prepaintReplayAllowed(under:)` dropped (the nested occurrence replays hidden under the offender's stale record: a second
/// redo, or a scene that differs), and the suspension widened back to every id (the hits read 0).
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: [false, true]) @MainActor
func aRedoSuspendsReplayOnlyUnderTheOccurrenceThatCausedIt(nested: Bool) async throws {
    let r = try await rptRedoFrames(nested: nested)
    let first = try #require(r.after.first)
    #expect(first.retainedPrepaintHits >= 2, "B and C replay the frame after the redo: \(first.retainedPrepaintHits)")
    #expect(first.elementRequests < 40, "…and their builds are skipped: \(first.elementRequests)")
    #expect(r.after.allSatisfy { $0.retainedRedos == 0 }, "no second redo: \(r.after.map(\.retainedRedos))")
    #expect(first.retainedBackoffFrames == 1, "the suspension is still counted: \(first.retainedBackoffFrames)")
    let last = try #require(r.after.last)
    #expect(last.retainedPrepaintHits == 3 && last.retainedBackoffFrames == 0, "everything replays after the quarantine: \(last.retainedPrepaintHits)/\(last.retainedBackoffFrames)")
}

/// The ambient keeps changing every frame (an animation's stand-in): the occurrence under it, and the nested one it hides
/// while it replays, wait; the siblings replay; one redo in all, and every frame equals the retention-off window's.
/// **Mutation:** the walk up the identity (`current = c.parent`) cut so only the offender itself is suspended (the nested
/// occurrence replays under a changed ambient: more redos).
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aNestedOccurrenceUnderAChangingAmbientWaitsWithItsOuterOne() async throws {
    let pair = try RPPair(size: sz(200, 380), warm: 5) { rptRedoRoot($0, nested: true) }
    pair.redraw()
    var redos = 0
    for step in 0..<7 {
        pair.onSide.model.n += 1; pair.offSide.model.n += 1
        await rsSettle()
        pair.redraw()
        redos += pair.frames.last?.retainedRedos ?? 0
        try pair.compare("step \(step)")
    }
    #expect(redos == 1, "one redo for seven changes: \(redos)")
}
