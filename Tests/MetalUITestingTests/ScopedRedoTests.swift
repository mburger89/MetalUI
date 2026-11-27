import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// The scoped redo (`RK-AM`, `RK-AN`, record 423): a frame abandoned because a grafted occurrence's record cannot follow the scroll move is built again
// with graft and prepaint replay off only for that occurrence and what is under and above it, after a rollback that makes the second attempt a legal build
// (records 417 to 419). The fixture is Alloy's transcript (`ChromeTranscriptFixture.swift`); it redoes three times in 40 streamed words.

private let srVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the redo counts this test pins are not its to read"

/// Runs `steps` streamed words and answers each step's work summed over the frames the step drew.
@MainActor private func srRun(_ pair: RPPair<some Element>, steps: Int, compare: Bool = true) async throws -> [FrameWork] {
    var out: [FrameWork] = []
    for step in 0..<steps {
        let frames = await ctStep(pair)
        out.append(frames.reduce(FrameWork(), +))
        if compare { try pair.compare("step \(step)") }
    }
    return out
}

/// A redo rebuilds the failing row and what is under it, not the frame (`RK-AM`): in the frames that redo, the other rows still graft and the work is a
/// fraction of the window-wide redo's (70 requests, no graft, on `fix/exact-redo-verify`), and no build is backed off. Mutations: the scope check off in
/// `graftRecord` (every row rebuilds: the grafts and the requests), the scope never set (the same).
@Test(.enabled(if: !rsVerifying, srVerifyingNote)) @MainActor
func aScopedRedoRebuildsOnlyTheFailingRowAndItsDescendants() async throws {
    let pair = try ctOuterScopePair()
    let frames = try await srRun(pair, steps: 40)
    let redone = frames.filter { $0.retainedRedos > 0 }
    try #require(redone.count >= 2, "the fixture redoes: \(redone.count)")
    for (index, f) in redone.enumerated() {
        #expect(f.retainedGrafts >= 3, "redo \(index): the rows that did not fail still graft: \(f.retainedGrafts)")
        #expect(f.elementRequests <= 50, "redo \(index): \(f.elementRequests) requests (70 window-wide)")
        #expect(f.retainedRedoEscalations == 0, "redo \(index) escalated")
    }
    #expect(frames.allSatisfy { $0.retainedBackoffFrames == 0 }, "no build is suspended by a scoped redo")
    let mean = Double(frames.map(\.elementRequests).reduce(0, +)) / Double(frames.count)
    #expect(mean < 30, "mean requests a step \(mean) (39.1 on fix/exact-redo-verify)")
}

/// A redo does not cascade into the row's descendants (`RK-AN`; record 416: a nested `.equatable()` paragraph grafted in the next frame and failed the same
/// way one level down, a redo a frame): over 40 words the transcript redoes at most twice (the pin was 3 and the transcript made 4 before `FS-Y`: the growing row's second paragraph no longer misses its ledger on the clip), never in two frames running. Mutation: the scope quarantine
/// off (`isInQuarantinedScope` answering false: the paragraphs graft again and the redos repeat).
@Test(.enabled(if: !rsVerifying, srVerifyingNote)) @MainActor
func aRedoDoesNotCascadeIntoTheRowsDescendants() async throws {
    let pair = try ctOuterScopePair()
    let frames = try await srRun(pair, steps: 40)
    let redos = frames.map(\.retainedRedos)
    #expect(redos.reduce(0, +) <= 2, "redos \(redos.reduce(0, +)) in 40 steps")
    #expect(!zip(redos, redos.dropFirst()).contains { $0 > 0 && $1 > 0 }, "a redo in two frames running: \(redos)")
    #expect(frames.allSatisfy { $0.retainedRedoEscalations == 0 })
    #expect(pair.on.window.testingQuarantinedScopes > 0 || redos.reduce(0, +) == 0, "the failing rows were quarantined as scopes")
}

/// A scoped redo equals a fresh frame in every channel (`RK-AM`, `RK-AI`, `GL-K`): scene, hitboxes, tallies, Tab order, element bounds, the live state
/// entries and the atlas slots of the redoing window equal the plain window's at every step, redo frames included, no glyph record names a slot the atlas
/// forgot. Mutation: the rollback off in `rollBackAttempt` (attempt 2 plans from what attempt 1 wrote).
@Test(.enabled(if: !rsVerifying, srVerifyingNote)) @MainActor
func aScopedRedoEqualsAFreshFrameInEveryChannel() async throws {
    let pair = try ctOuterScopePair()
    var redone = 0
    for step in 0..<40 {
        let frames = await ctStep(pair)
        redone += frames.map(\.retainedRedos).reduce(0, +)
        try pair.compare("step \(step)")
        #expect(xrBoundsDifferences(pair).isEmpty, "step \(step): element bounds \(xrBoundsDifferences(pair).prefix(3))")
        #expect(pair.on.window.testingStateEntries == pair.off.window.testingStateEntries, "step \(step): live state entries")
        #expect(pair.on.window.testingAtlasSlots == pair.off.window.testingAtlasSlots, "step \(step): atlas slots")
        #expect(xrDanglingGlyphs(pair.on) == 0, "step \(step): dangling glyph records")
    }
    #expect(redone >= 2, "redos \(redone)")
    #expect(pair.on.window.testingAtlasAttempt.growthsInAbandoned == 0)
}

/// The window backs off only on escalation (`RK-AM`): a scoped redo suspends nothing, a channel declared unrestorable makes the redo window-wide (nine builds
/// of backoff, every replay off in the redo), and an attempt 2 that asks again is built a third time with every replay off and counted in
/// `retainedRedoEscalations`; the scene equals a fresh frame's in all three. Mutations: `noteRedo` suspending replay when scoped (the first arm), the fault ignored.
@Test(.enabled(if: !rsVerifying, srVerifyingNote), arguments: [0, 1, 2]) @MainActor
func theWindowBacksOffOnlyOnEscalation(arm: Int) async throws {
    let pair = try ctOuterScopePair()
    pair.on.window.testingRedoFault = arm == 1 ? .unrestorableChannel : arm == 2 ? .secondAttemptAsksAgain : nil
    let frames = try await srRun(pair, steps: 40)
    let backoff = frames.map(\.retainedBackoffFrames).reduce(0, +)
    let escalations = frames.map(\.retainedRedoEscalations).reduce(0, +)
    let redos = frames.map(\.retainedRedos).reduce(0, +)
    try #require(redos >= 1, "the fixture redoes")
    switch arm {
    case 0: #expect(backoff == 0 && escalations == 0, "a scoped redo: backoff \(backoff), escalations \(escalations)")
    case 1: #expect(backoff >= 8 && escalations == 0, "an unrestorable channel: backoff \(backoff), escalations \(escalations)")
    default: #expect(backoff >= 8 && escalations >= 1, "an attempt 2 that asks again: backoff \(backoff), escalations \(escalations)")
    }
}

/// An unchanged transcript frame costs the scroller's own 4 requests and redoes nothing (`RK-AM`: the armed attempt costs the steady frame nothing).
@Test(.enabled(if: !rsVerifying, srVerifyingNote)) @MainActor
func aQuietChromeTranscriptFrameCostsOnlyTheScroller() async throws {
    let pair = try ctPair()
    _ = try await srRun(pair, steps: 3)
    for _ in 0..<12 { pair.redraw() }   // the quarantine ends
    pair.frames = []
    for _ in 0..<4 { pair.redraw() }
    for (i, f) in pair.frames.enumerated() {
        #expect(f.retainedRedos == 0 && f.elementRequests == 4, "frame \(i): \(f.elementRequests) requests, \(f.retainedRedos) redos")
    }
    try pair.compare("quiet")
}
