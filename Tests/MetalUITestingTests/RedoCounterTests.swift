import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-e lane 1 (`CF-C`, `CF-D`, record 127): what `FrameWork` reports on a redo frame (`RK-D`: abandoned after paint,
// rebuilt once with every replay off). The redo's counters, plus the content getters the abandoned attempt evaluated
// (the redo skips them: the entry holds the result). Tests R1-R4 of `docs/superpowers/specs/2026-10-20-warm-settle-design.md` §4.

/// A component that shows its value; the getter is the evaluation the counters count.
private struct RRCounter: Component, @MainActor Equatable {
    let n: Int
    var content: some ElementGroup {
        Text("count \(n)").frame(width: Pixels(80), height: Pixels(14))
    }
}

/// The redo fixture of `aChangedPaintOnlyAmbientRedoesTheFrameOnce`, plus a counter whose value changes in the same
/// frame as the ambient, and (optionally) a refused reader.
@MainActor private func rrRoot(_ side: RPSide, refused: Bool) -> some Element {
    let n = side.model.n
    let log = side.log
    let fn = n
    return VStack(spacing: 4) {
        ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.opacity(n % 2 == 1 ? 0.5 : 1)
        RPCard(title: "B", shade: 2, log: log).equatable()
        RRCounter(n: n).equatable()
        if refused {
            EEFnReader(log: EELog()).equatable().environment(\.eeFn, EEFn(run: { fn }))
        }
    }
}

@MainActor private func rrRedoFrames(refused: Bool) async throws -> (pair: RPPair<some Element>, redo: FrameWork, after: FrameWork) {
    let pair = try RPPair(size: sz(200, 260), warm: 4) { rrRoot($0, refused: refused) }
    pair.redraw()
    try #require(pair.frames.last?.retainedPrepaintHits == 3, "all three replay before the change: \(String(describing: pair.frames.last))")
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    await rsSettle()
    pair.redraw()
    let redo = try #require(pair.frames.last)
    try #require(redo.retainedRedos == 1, "the ambient change redoes the frame once: \(redo.retainedRedos)")
    pair.redraw()
    let after = try #require(pair.frames.last)
    return (pair, redo, after)
}

/// R1 — the content getter the abandoned attempt evaluated is reported on the redo frame. **Red before (679f5d7d):**
/// `contentEvaluations == 0`. Mutation: the carry deleted in `endFrame`.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the counts this test pins are not its to read"))
@MainActor func aRedoFrameReportsTheContentGetterTheAbandonedAttemptEvaluated() async throws {
    let r = try await rrRedoFrames(refused: false)
    #expect(r.redo.contentEvaluations == 1, "the counter changed in the redo's frame: \(r.redo.contentEvaluations)")
}

/// R2 — an evaluation is not counted twice, and a refusal is the redo's own. Mutation: the carry also added to
/// `refusals`.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the counts this test pins are not its to read"))
@MainActor func aRedoFrameDoesNotCountAnEvaluationTwice() async throws {
    let r = try await rrRedoFrames(refused: true)
    #expect(r.redo.contentEvaluations == 1, "evaluations \(r.redo.contentEvaluations)")
    #expect(r.redo.contentRefusals == 1, "refusals \(r.redo.contentRefusals)")
}

/// R3 — everything else on a redo frame is the redo's work alone: the rebuild with every replay off, so the same
/// element and layout work as the next (backoff) build of the unchanged tree. Mutation: every counter carried.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the counts this test pins are not its to read"))
@MainActor func aRedoFrameKeepsTheRedosOtherCounters() async throws {
    let r = try await rrRedoFrames(refused: false)
    #expect(r.redo.builds == 1)
    #expect(r.redo.elementRequests == r.after.elementRequests, "requests \(r.redo.elementRequests) vs \(r.after.elementRequests)")
    #expect(r.redo.elementPrepaints == r.after.elementPrepaints, "prepaints \(r.redo.elementPrepaints) vs \(r.after.elementPrepaints)")
    // Paints differ by design: the backoff build still replays paint records, the redo (every replay off) repaints.
    #expect(r.redo.retainedRedos == 1 && r.redo.retainedPrepaintHits == 0, "the redo replays no prepaint: \(r.redo.retainedPrepaintHits)")
    #expect(r.redo.layoutMeasureCalls == r.after.layoutMeasureCalls, "measures \(r.redo.layoutMeasureCalls) vs \(r.after.layoutMeasureCalls)")
}

/// R4 — the frame after a redo (backoff) reports no carried count. Mutation: the carry not cleared.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the counts this test pins are not its to read"))
@MainActor func theFrameAfterARedoReportsNoCarriedEvaluation() async throws {
    let r = try await rrRedoFrames(refused: false)
    #expect(r.after.retainedBackoffFrames == 1 && r.after.retainedRedos == 0)
    #expect(r.after.contentEvaluations == 0, "carried into the next frame: \(r.after.contentEvaluations)")
    r.pair.redraw()
    #expect(r.pair.frames.last?.contentEvaluations == 0)
}
