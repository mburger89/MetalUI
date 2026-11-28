@testable import MetalUI
import MetalUITesting
import MetalUITestSupport
import Testing

// `FrameWork.redoneElementPrepaints` and its five siblings (record 441): the work of the attempts a redo abandoned. `FrameWork`'s other fields read
// the adopted `Frame` alone, so a redone frame reported less prepaint work than its neighbours (a redo that replays the rest of the frame prepaints
// little) and a benchmark that compared a tree with redos against one without was biased in favour of the redos (Alloy). The new fields carry what the
// dropped attempts did, summed over every abandoned attempt of the frame; the existing fields keep their meaning.

private let rwNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the redo counts this test pins are not its to read"

/// The redo fixture of `RedoCounterTests` without its counter: two cards, the first under an opacity that flips with the model.
@MainActor private func rwRoot(_ side: RPSide) -> some Element {
    let n = side.model.n
    let log = side.log
    return VStack(spacing: 4) {
        ZStack { RPCard(title: "A", shade: 1, log: log).equatable() }.opacity(n % 2 == 1 ? 0.5 : 1)
        RPCard(title: "B", shade: 2, log: log).equatable()
    }
}

/// The frames of one window-wide redo (`testingRedoFault`): the steady frame before the change, the redo frame, and the retention-off window's frame
/// of the same state, which prepaints every element once.
@MainActor private func rwRedo() async throws -> (pair: RPPair<some Element>, before: FrameWork, redo: FrameWork, off: FrameWork) {
    let pair = try RPPair(size: sz(200, 260), warm: 4) { rwRoot($0) }
    pair.on.window.testingRedoFault = .unrestorableChannel
    pair.redraw()
    let before = try #require(pair.frames.last)
    try #require(before.retainedPrepaintHits == 2, "both cards replay before the change: \(before.retainedPrepaintHits)")
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    await rsSettle()
    pair.redraw()
    let redo = try #require(pair.frames.last)
    try #require(redo.retainedRedos == 1, "the ambient change redoes the frame once: \(redo.retainedRedos)")
    return (pair, before, redo, pair.off.lastFrameWork)
}

/// **W1** A redone frame reports the abandoned attempt's prepaints, paints and requests in the `redone` fields. The attempt that was dropped is the
/// first one, which replayed both cards' prepaint, so it did exactly what the steady frame before the change did (`before`). Mutation: the dropped
/// frame not added to `dropped` in `redoAbandonedFrame`.
@Test(.enabled(if: !rsVerifying, rwNote)) @MainActor
func aRedoneFrameReportsTheWorkOfTheAttemptItDropped() async throws {
    let r = try await rwRedo()
    print("redone: prepaints \(r.redo.redoneElementPrepaints) paints \(r.redo.redoneElementPaints) requests \(r.redo.redoneElementRequests); before \(r.before.elementPrepaints) \(r.before.elementPaints) \(r.before.elementRequests); adopted \(r.redo.elementPrepaints) \(r.redo.elementPaints) \(r.redo.elementRequests); off \(r.off.elementPrepaints)")
    #expect(r.redo.redoneElementPrepaints > 0, "prepaints \(r.redo.redoneElementPrepaints)")
    #expect(r.redo.redoneElementPrepaints == r.before.elementPrepaints, "\(r.redo.redoneElementPrepaints) vs \(r.before.elementPrepaints)")
    #expect(r.redo.redoneElementRequests == r.before.elementRequests, "\(r.redo.redoneElementRequests) vs \(r.before.elementRequests)")
    #expect(r.redo.redoneElementPaints == r.before.elementPaints, "\(r.redo.redoneElementPaints) vs \(r.before.elementPaints)")
}

/// **W2** The two attempts' prepaints, counted from outside the redo. The adopted attempt turns every replay off, so it prepaints what the
/// retention-off window's frame of the same state does (`off`); the dropped one is the steady frame's figure (`before`). `elementPrepaints +
/// redoneElementPrepaints` is their sum, and the adopted field alone (what `FrameWork` reported until now) is less than a frame's work.
/// Mutation: `elementPrepaints` replaced by the sum in `testingOnFrameAdopted` (the first expectation).
@Test(.enabled(if: !rsVerifying, rwNote)) @MainActor
func aRedoneFramesTotalPrepaintsAreTheTwoAttemptsFromOutside() async throws {
    let r = try await rwRedo()
    #expect(r.redo.elementPrepaints == r.off.elementPrepaints, "adopted \(r.redo.elementPrepaints) vs the unretained frame \(r.off.elementPrepaints)")
    #expect(r.redo.elementPrepaints + r.redo.redoneElementPrepaints == r.off.elementPrepaints + r.before.elementPrepaints,
            "total \(r.redo.elementPrepaints + r.redo.redoneElementPrepaints)")
    #expect(r.redo.elementRequests == r.off.elementRequests)
}

/// **W3** A frame that was not redone reports 0 in every `redone` field: the warm-up, the steady frames, an idle frame and the retention-off window's.
/// Mutation: `abandonedWork` set on every frame in `buildAndAdoptFrame` (the element counters of the frame itself).
@Test @MainActor
func aFrameThatWasNotRedoneReportsNoRedoneWork() async throws {
    let pair = try RPPair(size: sz(200, 260), warm: 4) { rwRoot($0) }
    for _ in 0..<3 { pair.redraw() }
    let all = (pair.frames + pair.off.frameWork).reduce(FrameWork(), +)
    #expect(all.builds > 0 && all.elementPrepaints > 0)
    #expect(all.retainedRedos == 0)
    #expect(all.redoneElementRequests == 0 && all.redoneElementPrepaints == 0 && all.redoneElementPaints == 0, "\(all)")
    #expect(all.redoneLayoutMeasureCalls == 0 && all.redoneLayoutCacheHits == 0 && all.redoneLayoutCacheMisses == 0)
}

/// **W4** The sum and `+=` carry all six fields. Mutation: any one dropped from `+`.
@Test func theSumOfTwoRecordsAddsTheRedoneWork() {
    let a = FrameWork(redoneElementRequests: 1, redoneElementPrepaints: 2, redoneElementPaints: 3,
                      redoneLayoutMeasureCalls: 4, redoneLayoutCacheHits: 5, redoneLayoutCacheMisses: 6)
    let b = FrameWork(redoneElementRequests: 10, redoneElementPrepaints: 20, redoneElementPaints: 30,
                      redoneLayoutMeasureCalls: 40, redoneLayoutCacheHits: 50, redoneLayoutCacheMisses: 60)
    let sum = a + b
    #expect(sum.redoneElementRequests == 11 && sum.redoneElementPrepaints == 22 && sum.redoneElementPaints == 33)
    #expect(sum.redoneLayoutMeasureCalls == 44 && sum.redoneLayoutCacheHits == 55 && sum.redoneLayoutCacheMisses == 66)
    var c = a
    c += b
    #expect(c == sum)
    #expect(FrameWork() == FrameWork(redoneElementPrepaints: 0))
    #expect(FrameWork().redoneElementPrepaints == 0)
}

/// **W5** Every frame of Alloy's scoped-redo transcript that redoes reports the dropped attempt's work, and every other frame none; the scoped redo
/// drops its first attempt like the window-wide one. Mutation: the carry deleted (the redone frames read 0).
@Test(.enabled(if: !rsVerifying, rwNote)) @MainActor
func aScopedRedoOfTheTranscriptReportsItsDroppedAttempt() async throws {
    let pair = try ctOuterScopePair()
    var redone = 0, layout = 0
    for _ in 0..<40 {
        let frames = await ctStep(pair)
        for f in frames {
            if f.retainedRedos > 0 {
                redone += 1
                layout += f.redoneLayoutMeasureCalls + f.redoneLayoutCacheHits + f.redoneLayoutCacheMisses
                #expect(f.redoneElementPrepaints > 0 && f.redoneElementRequests > 0 && f.redoneElementPaints > 0,
                        "prepaints \(f.redoneElementPrepaints) requests \(f.redoneElementRequests) paints \(f.redoneElementPaints)")
            } else {
                #expect(f.redoneElementPrepaints == 0 && f.redoneElementRequests == 0 && f.redoneElementPaints == 0)
            }
        }
    }
    #expect(redone >= 2, "the fixture redoes: \(redone)")
    print("scoped transcript: \(redone) redone frames, dropped layout work \(layout)")
    #expect(layout > 0, "the dropped attempts' layout work: \(layout)")
}

/// **W6** The fields add nothing to an idle frame: a 200 x 100 clipped two-leaf island costs the requests and allocations it did on master
/// `ae044e77` (measured there: 5 requests, 222 allocations, 19,322 bytes). The six counts sit out of line behind one optional reference, so a stored `FrameWork` grows by 8 bytes
/// (stride 552 to 560, pinned below), not 48: a 48-byte growth moved the growth schedule of the harness's history array (capacity 8 to 9, 18 to 17 slots) and
/// with it the one allocation `snappingAddsNoAllocationsAndNoElementRequestsToIdleAndScrolledFrames` pins, whose 1562 stays. The bytes measured here are 19,378.
/// Mutation: a `[String: Int]` built per frame in `testingOnFrameAdopted` (the allocation count rises).
@Test @MainActor func theRedoneWorkFieldsAddNothingToAnIdleFrame() async throws {
    let w = try harnessWindow(size: sz(200, 100)) {
        HStack(spacing: Pixels(0)) {
            Color(.accent).frame(width: Pixels(46), height: Pixels(60))
            Color(.separator).frame(width: Pixels(46), height: Pixels(60))
        }
        .clipShape(RoundedRectangle(cornerRadius: Pixels(10)))
        .frame(width: Pixels(200), height: Pixels(100))
    }
    try await w.runUntilIdle()
    w.window.setNeedsRedraw(); w.tick()
    w.resetFrameWork()
    #if canImport(Darwin)
    let seen = countAllocatedBytes { w.window.setNeedsRedraw(); w.tick() }
    let measured = try #require(seen)
    print("FrameWork redone fields, idle: requests \(w.lastFrameWork.elementRequests) allocations \(measured.allocations) bytes \(measured.bytes)")
    #expect(measured.allocations == 222, "allocations \(measured.allocations)")
    #expect(measured.bytes <= 19_322 + 56, "bytes \(measured.bytes)")
    #else
    w.window.setNeedsRedraw(); w.tick()
    #endif
    #expect(MemoryLayout<FrameWork>.stride == 560, "a stored record's stride \(MemoryLayout<FrameWork>.stride)")
    #expect(w.lastFrameWork.elementRequests == 5, "requests \(w.lastFrameWork.elementRequests)")
    #expect(w.lastFrameWork.redoneElementPrepaints == 0)
}
