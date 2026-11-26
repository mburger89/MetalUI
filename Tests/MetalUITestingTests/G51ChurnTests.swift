import Foundation
@testable import MetalUI
import MetalUITestSupport
import MetalUITesting
import Testing

// G51 (record 420): what a streamed frame of a long bottom-anchored transcript allocates, in a debug build on the harness text
// system. The fixture (`G51Fixture.swift`) paints every row inside a composite scope, as Alloy's rounded and clipped chrome does, so
// each text draw is a leaf group, each record holds captured primitives and every scope collects a viewport of them. The ceilings are a
// few percent over what the branch measures; each fix put back goes over at least one (record 420's table).

#if canImport(Darwin)
/// The mean of `frames` streamed frames after the warm-up.
@MainActor private func g51Profile(rows: Int, frames: Int = 12) async throws -> (bytes: Double, allocations: Double, large: Double, largeBytes: Double, work: FrameWork) {
    let inputs = G51Inputs()
    let w = try await g51Window(rows: rows, inputs: inputs)
    var total = AllocationProfile(allocations: 0, bytes: 0, large: 0, largeBytes: 0)
    var work = FrameWork()
    for _ in 0..<frames {
        inputs.words += 1
        await rsSettle()
        w.window.setNeedsRedraw()
        let p = try #require(profileAllocations { w.tick() })
        total.allocations += p.allocations; total.bytes += p.bytes; total.large += p.large; total.largeBytes += p.largeBytes
        work += w.lastFrameWork
    }
    withExtendedLifetime(w) {}
    let n = Double(frames)
    return (Double(total.bytes) / n, Double(total.allocations) / n, Double(total.large) / n, Double(total.largeBytes) / n, work)
}
#endif

private let g51Verifying: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the allocations this test pins are not its to read"

/// **G51-A** A streamed frame of the scoped transcript allocates under its ceilings: bytes, allocations and the requests of 128 KiB
/// and over (the blocks malloc keeps as `Malloc Large (empty)`). Mutations: the leaf group, the scope's captures or the fresh group
/// scenes without their reserve, the capture array copied at the close, the layout memo's generations remade empty, a
/// `CapturedPrimitive` that carries its path, shadow, gradient, blur and backdrop inline.
@Test(.enabled(if: !rsVerifying, g51Verifying)) @MainActor
func aStreamedFrameOfAScopedTranscriptStaysUnderItsCeilings() async throws {
    #if canImport(Darwin)
    let m = try await g51Profile(rows: 40)
    print("G51 streamed frame: bytes \(Int(m.bytes)) allocations \(Int(m.allocations)) large \(m.large) largeBytes \(Int(m.largeBytes)) redos \(m.work.retainedRedos)")
    #expect(m.bytes <= g51ByteCeiling, "bytes \(Int(m.bytes))")
    #expect(m.large <= g51LargeCeiling, "large requests \(m.large)")
    #expect(m.largeBytes <= g51LargeByteCeiling, "large bytes \(Int(m.largeBytes))")
    #expect(m.allocations <= g51AllocationCeiling, "allocations \(Int(m.allocations))")
    #endif
}

/// The redo frame and the one after it reserve what master's did (record 417): the abandoned attempt's storage is not dropped and reserved again
/// beyond the one capture scope reserve the redo has always repeated. Profiled per frame: the frame that redoes makes at most 13 requests of 128 KiB or
/// more (6 for a quiet streamed frame, master 16, 12 measured since record 424), the frame after it at most 7 (master 9, 6 measured: the six translated records are moved in place, `FS-V`). Mutation: a second
/// scene reserve in the redo (the first number), the redo's fresh frame reserving from no hint (the second).
@Test(.enabled(if: !rsVerifying, g51Verifying)) @MainActor
func aRedoFrameOfTheScopedTranscriptReservesWhatMastersDid() async throws {
    #if canImport(Darwin)
    let inputs = G51Inputs()
    let w = try await g51Window(rows: 40, inputs: inputs)
    var perFrame: [(large: Int, redos: Int)] = []
    for _ in 0..<14 {
        inputs.words += 1
        await rsSettle()
        w.window.setNeedsRedraw()
        let p = try #require(profileAllocations { w.tick() })
        perFrame.append((p.large, w.lastFrameWork.retainedRedos))
    }
    let redone = try #require(perFrame.firstIndex { $0.redos > 0 }, "the fixture redoes: \(perFrame)")
    #expect(perFrame[redone].large <= 13, "the redo frame: \(perFrame[redone].large) large requests, \(perFrame)")
    #expect(perFrame[redone + 1].large <= 7, "the frame after the redo: \(perFrame[redone + 1].large)")
    #expect(perFrame.enumerated().allSatisfy { $0.offset == redone || $0.offset == redone + 1 || $0.element.large <= 7 }, "a quiet streamed frame: \(perFrame)")
    #endif
}

/// **G51-B** The streamed frame costs the same however many rows lie above the window: rows realised, prepaints and paints are the
/// window's, and so are the bytes (a record, a scope or a dictionary that scaled with the transcript would show here).
@Test(.enabled(if: !rsVerifying, g51Verifying)) @MainActor
func aLongerTranscriptCostsTheSameStreamedFrame() async throws {
    #if canImport(Darwin)
    let short = try await g51Profile(rows: 60)
    let long = try await g51Profile(rows: 240)
    print("G51 rows 60 vs 240: bytes \(Int(short.bytes)) vs \(Int(long.bytes)), large \(short.large) vs \(long.large)")
    #expect(long.bytes <= short.bytes * 1.06, "bytes \(Int(long.bytes)) against \(Int(short.bytes))")
    #expect(long.large <= short.large + 1, "large requests \(long.large) against \(short.large)")
    #expect(long.work.elementRequests == short.work.elementRequests, "requests \(long.work.elementRequests) against \(short.work.elementRequests)")
    #endif
}

/// **G51-C** A captured primitive is a glyph or a rect with its flags, not the largest of its kinds: a record, a leaf group and
/// a scope's captures hold one per glyph. 424 bytes when a gradient (280), a backdrop (256) and a path (192) were inline.
@Test @MainActor func aCapturedPrimitiveDoesNotCarryItsRarestKindInline() {
    #expect(MemoryLayout<CapturedPrimitive>.stride <= 280, "\(MemoryLayout<CapturedPrimitive>.stride)")
    #expect(MemoryLayout<CapturedPrimitive.Kind>.stride <= 136, "\(MemoryLayout<CapturedPrimitive.Kind>.stride)")
}

// Measured on this fixture in a debug build (`--build-system native`), 12 streamed frames of 40 rows: 20.13 MB, 172342 allocations,
// 7.08 requests of 128 KiB or more (6.85 MB) a frame; on the tree before record 420 (bytes and large requests, measured by the probe
// at 20 and 100 rows) 39 and 44 MB, 28 and 30 large requests. The ceilings sit about 2.5 % over.
private let g51ByteCeiling = 20_400_000.0   // 19.89 MB measured (record 424; master 20.52 MB)
// 7.4 plus 0.5 (record 417 on #434): the frame after the profile's one redo translates the six moved rows' paint records again, `Frame.movedOps`,
// six requests of 239 392 bytes in 12 frames. Master's redo ran its layout over the attempt's own scroll writes, so its rows were already where
// the anchor put them and the next frame moved nothing; the rollback makes the redo a fresh frame, which applies the anchor's adjustment one
// frame later, as every non-redo wrap frame does. The copy is the translation's own (a record's ops are rebuilt at the new offset), not storage the
// abandoned attempt dropped: the redo frame itself costs the 16 master's does (`aRedoFrameOfTheScopedTranscriptReservesWhatMastersDid`).
// Record 424 (`FS-V`): 6.5 measured, 6.8 ceiling, down from 7.9 (master reads 7.58). The six translated records of the frame after the redo are no longer
// copied: the move is made in place in the paint decision (`applyPaintTranslation`), and prepaint's check of an abandoned attempt builds nothing.
private let g51LargeCeiling = 6.8
// Record 422 (`HP-N`): the scene's arrays reserve a size class, up to an eighth over, so the large bytes read 7.07 MB (the bytes are
// not the lever there, the sizes are: `G52StreamingCapacityTests`).
private let g51LargeByteCeiling = 7_250_000.0
private let g51AllocationCeiling = 165_100.0   // 161 081 measured (record 424; master 172 977, the ceiling was 176 500)
