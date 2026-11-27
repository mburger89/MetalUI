import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Testing

// An occurrence whose entry clip changed with the move is related to the one that was recorded (`FS-Y`, record 434): the same add, with every cut made again
// from the clip now in force by the arithmetic a fresh frame uses. Before, the streaming row's second paragraph (a grafted `.equatable()` occurrence under
// the row's own growing clip) missed its ledger on `ambient.clip` and the frame was redone.

private let ceVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the translation counts this test pins are not its to read"

private func ceEnvironment(_ edit: (inout EnvironmentValues) -> Void = { _ in }) -> EnvironmentFingerprint {
    var values = EnvironmentValues()
    edit(&values)
    return values.retainedFingerprint
}

/// A rounded card: a text, a button and a text, so registrations sit under the card's own clip, and the paint record holds leaves under it.
private struct CEInner: Component, @MainActor Equatable {
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) {
            Text("inner top").frame(height: 22)
            Button("go") {}.frame(height: 22)
            Text("inner bottom").frame(height: 22)
        }
        .padding(Edges(all: Pixels(6)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.2))
        .cornerRadius(Pixels(8))
    }
}

/// The card under a box that grows 2 pt a step (the viewport edge of the streaming row), top-aligned so the card stands still, or pushed down 1 pt a step
/// so it moves **and** its entry clip changes. `fades` also changes the opacity a step: an ambient field other than the clip.
private struct CERoot: Component {
    let side: RPSide
    let moving: Bool
    let fades: Bool
    var content: some ElementGroup {
        let n = Pixels(side.inputs.offset)
        let box = VStack(alignment: .leading, spacing: 0) { CEInner().equatable() }
            .padding(Edges(top: moving ? n : Pixels(0), right: Pixels(0), bottom: Pixels(0), left: Pixels(0)))
            .frame(width: Pixels(200), height: Pixels(40) + n + n, alignment: .top)
            .clipped()
        if fades { box.opacity(1 - side.inputs.offset / 100) } else { box }
    }
}

@MainActor private func cePair(moving: Bool, fades: Bool = false, accessibility: Bool = true, scale: Float = 2) throws -> RPPair<some Element> {
    try RPPair(size: sz(320, 300), scale: scale, warm: 16, accessibility: accessibility, graft: true) { side in
        VStack(spacing: 0) { CERoot(side: side, moving: moving, fades: fades) }
    }
}

private struct CEOutcome {
    var reasons: [String: Int] = [:]
    var lines: [String] = []
    var hits = 0, moves = 0, redos = 0
}

/// Twelve steps of the growing box (the card is cut by the clip until step 8), equal to a fresh frame at each.
@MainActor private func ceRun(_ pair: RPPair<some Element>, steps: Int = 12) async throws -> CEOutcome {
    var out = CEOutcome()
    RetainedTrace.sink = { out.lines.append($0) }
    defer { RetainedTrace.sink = nil }
    for step in 0..<steps {
        pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
        pair.on.resetFrameWork()
        await rsSettle()
        pair.redraw()
        let f = pair.on.frameWork.reduce(FrameWork(), +)
        out.reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        out.hits += f.retainedPrepaintHits; out.moves += f.retainedTranslated; out.redos += f.retainedRedos
        try pair.compare("step \(step)")
    }
    return out
}

private let ceGateReasons = ["NotFolded", "Unmapped", "hitboxClipped", "accessibilityClipped", "entryClipChanged"]

private func ceNamesAGate(_ reasons: [String: Int]) -> [String] {
    reasons.keys.filter { key in ceGateReasons.contains { key.hasSuffix($0) || key == $0 } }.sorted()
}

/// The streamed transcript's second paragraph is no longer redone for its clip: over 40 words, with and without an accessibility client, at most the two
/// redos of rows 45 and 46 (`maskCrossingChanged`, `innerScope`) remain, none names `ambient.clip`, no prepaint miss is for the clip alone, and the frame is
/// equal to a fresh one at each step. Pins: element requests 547 (593 before), the retaining window's allocations 885,000 (919,667 before; 879,6xx measured).
/// Mutation: a leaf read at the entry depth keeping the old mask (`movedMask`'s entry arm answering `(mask, radii)`): the compare differs at every step
/// the clip grows.
@Test(.enabled(if: !rsVerifying, ceVerifyingNote), arguments: [false, true]) @MainActor
func aParagraphUnderAGrowingRowReplaysTranslated(accessibility: Bool) async throws {
    let pair = try ctPair(accessibility: accessibility)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    var redos = 0, requests = 0, allocations = 0
    for step in 0..<40 {
        pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
        pair.on.resetFrameWork()
        await rsSettle()
        pair.off.window.setNeedsRedraw(); pair.off.tick()
        #if canImport(Darwin)
        allocations += countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() } ?? 0
        #else
        pair.on.window.setNeedsRedraw(); pair.on.tick()
        #endif
        let f = pair.on.frameWork.reduce(FrameWork(), +)
        redos += f.retainedRedos; requests += f.elementRequests
        try pair.compare("step \(step)")
    }
    print("CE transcript (accessibility \(accessibility)): requests \(requests), allocations \(allocations), redos \(redos)")
    #expect(redos <= 2, "redos \(redos) in 40 steps")
    #expect(!lines.contains { $0.contains("redo requested") && $0.contains("ambient.clip") }, "a redo for the clip: \(lines.filter { $0.contains("redo requested") })")
    #expect(!lines.contains { $0.contains("prepaint miss") && $0.contains("ledgerKey.ambient.clip") }, "a prepaint miss for the clip")
    if accessibility {
        #expect(requests <= 547, "element requests \(requests) (593 at 4a1e3856)")
        #if canImport(Darwin)
        #expect(allocations <= 885_000, "allocations \(allocations) (919,667 at 4a1e3856)")
        #endif
    }
}

/// A rect cut by the clip it was made under is tested against **that** clip, the moved rect against the clip now: the card's hitbox and accessibility rects
/// touch the box's edge until the box has grown past them, and a test of both against the new clip would move the old cut rect as it was. Equal to a fresh
/// frame at each of 12 steps, the card standing still and moving (a different clip and a zero move, and a different clip and a move), and the ledger is
/// replayed moved, not run again.
/// Mutation: `movedHitbox` testing the old rect against the new clip (`inside(b, c)`): the hitbox keeps its old cut, the compare differs.
@Test(.enabled(if: !rsVerifying, ceVerifyingNote), arguments: [false, true]) @MainActor
func anOldRectIsTestedAgainstTheOldClip(moving: Bool) async throws {
    let pair = try cePair(moving: moving)
    let out = try await ceRun(pair)
    #expect(out.hits >= 8, "the ledger is replayed moved, not run again: \(out.hits) prepaint hits")
    #expect(ceNamesAGate(out.reasons).isEmpty, "refusals: \(out.reasons)")
    #expect(!out.lines.contains { $0.contains("prepaint miss") && $0.contains("ledgerKey.ambient.clip") }, "a miss for the clip")
    #expect(out.redos == 0, "redos \(out.redos)")
}

/// The fold starts from each key's own clip: the card's clip is folded from the entry clip it was made under at the old position (which must give the recorded
/// cut, else `…NotFolded`) and from the one now at the new, for the paint record's masks and the ledger's registrations alike.
/// Mutation: the old position folded from the new entry clip (`PrepaintClipFold`'s `oldEntryClip` replaced by `entryClip`, `foldedRecord`'s `was` likewise):
/// the two refuse by name and the test sees them.
@Test(.enabled(if: !rsVerifying, ceVerifyingNote), arguments: [false, true]) @MainActor
func theFoldStartsFromEachKeysOwnClip(moving: Bool) async throws {
    let pair = try cePair(moving: moving)
    try #require(pair.on.window.testingRetainedRecords().contains { $0.prepaint?.innerClips != nil }, "the fixture's ledger holds an inner clip")
    let out = try await ceRun(pair)
    #expect(ceNamesAGate(out.reasons).isEmpty, "a fold refused: \(out.reasons)")
    #expect(out.reasons["maskNotFolded", default: 0] == 0 && out.reasons["maskUnmapped", default: 0] == 0, "\(out.reasons)")
    #expect(out.moves >= 8, "the paint record moves too: \(out.moves) translated")
}

/// A change of anything else than the clip is not a clip change: with the opacity changing as the clip grows the paint record's miss is named by that field
/// (the prepaint ledger does not key the opacity, and still replays moved), the record is not translated, and every frame equals a fresh one.
/// Mutation: `equalsIgnoringOffsetAndClip` ignoring `layerOpacityScale` (the record moves with the old opacity, the compare differs) - and its arm in
/// `everyAmbientFieldButTheOffsetAndClipSeparates`.
@Test(.enabled(if: !rsVerifying, ceVerifyingNote)) @MainActor
func aChangedScopeIsNotAClipChange() async throws {
    let pair = try cePair(moving: false, fades: true)
    let out = try await ceRun(pair)
    let named = out.lines.filter { $0.contains("retained paint miss") && $0.contains("key.ambient.layerOpacityScale") }
    #expect(named.count >= 8, "the miss names the opacity: \(named.count) of \(out.lines.count) lines")
    #expect(out.moves == 0, "no record is translated across a change of opacity: \(out.moves)")
}

/// `equalsIgnoringOffsetAndClip` is `==` with the offset and the clip set aside, the clips of one count: every other stored field separates it alone, the
/// offset and the clip alone do not, and a clip of another count does. The Mirror count makes a new field owe a row.
/// Mutation: one field dropped from `equalsIgnoringOffsetAndClip` (reddens that field's arm).
@Test @MainActor func everyAmbientFieldButTheOffsetAndClipSeparates() throws {
    let base = AmbientKey(clip: [0, 0, 10, 10], offset: [1, 2], layerOpacityScale: [1], depths: [0], scopes: [[1, 2]],
                          environment: ceEnvironment(), snappingTransaction: false, disablesAnimations: false)
    try #require(Mirror(reflecting: base).children.count == 9, "a new AmbientKey field owes a row in equalsIgnoringOffsetAndClip and here")
    #expect(base.equalsIgnoringOffsetAndClip(base))
    var moved = base; moved.offset = [9, 9]
    var grown = base; grown.clip = [0, 0, 10, 99]
    var both = moved; both.clip = [0, 0, 10, 99]
    #expect(moved != base && moved.equalsIgnoringOffsetAndClip(base), "the offset alone is set aside")
    #expect(grown != base && grown.equalsIgnoringOffsetAndClip(base), "the clip alone is set aside")
    #expect(both.equalsIgnoringOffsetAndClip(base), "both together")
    var rounded = base; rounded.clip = [0, 0, 10, 10, 1, 1, 1, 1]
    #expect(!rounded.equalsIgnoringOffsetAndClip(base), "a clip of another count (radii present) is another shape")
    let edits: [(String, (inout AmbientKey) -> Void)] = [
        ("layerOpacityScale", { $0.layerOpacityScale = [2] }), ("depths", { $0.depths = [1] }),
        ("scopes", { $0.scopes = [[1, 3]] }), ("environment", { $0.environment = ceEnvironment { $0.isEnabled = false } }),
        ("snappingTransaction", { $0.snappingTransaction.toggle() }), ("disablesAnimations", { $0.disablesAnimations.toggle() }),
        ("atlasGeneration", { $0.atlasGeneration = 1 })
    ]
    for (name, edit) in edits {
        var other = base; edit(&other)
        #expect(!other.equalsIgnoringOffsetAndClip(base), "\(name) separates")
        var and = other; and.offset = [9, 9]; and.clip = [0, 0, 10, 99]
        #expect(!and.equalsIgnoringOffsetAndClip(base), "\(name) separates under a moved offset and a grown clip too")
    }
}

/// The relation of two replay keys: a changed clip alone relates with a **zero** shift, a changed clip with a moved origin relates with the move, equal clips
/// are `shift(from:)`'s and nothing here, and a changed clip with a changed shape, another ambient field or a clip of another count relates to nothing.
/// Mutation: `allowZero` false (the first arm answers `nil`).
@Test @MainActor func aChangedClipRelatesWhereTheShapeAndTheRestAreTheSame() {
    func ambient(_ clip: [Float], offset: [Float] = [0, 0]) -> AmbientKey {
        AmbientKey(clip: clip, offset: offset, layerOpacityScale: [1], depths: [0], scopes: [], environment: ceEnvironment(),
                   snappingTransaction: false, disablesAnimations: false)
    }
    func key(_ x: Float, shape: Int = 7, _ a: AmbientKey) -> ReplayKey {
        ReplayKey(rects: [x, 0, 50, 20], interior: 1, shapeInterior: shape, nodeCount: 1, ambient: a)
    }
    let old = key(0, ambient([0, 0, 100, 100]))
    let zero = key(0, ambient([0, 0, 100, 140]))
    #expect(zero.shift(from: old) == nil, "a zero move is no shift")
    let related = zero.clippedShift(from: old)
    #expect(related != nil && related?.windowX == 0 && related?.windowY == 0, "a changed clip alone relates, with a zero shift")
    let moved = key(8, ambient([0, 0, 100, 140]))
    #expect(moved.clippedShift(from: old)?.windowX == 8, "a changed clip and a move relate with the move")
    #expect(old.clippedShift(from: old) == nil && key(8, ambient([0, 0, 100, 100])).clippedShift(from: old) == nil, "equal clips are not this relation's")
    #expect(key(0, shape: 8, ambient([0, 0, 100, 140])).clippedShift(from: old) == nil, "another shape")
    var other = ambient([0, 0, 100, 140]); other.snappingTransaction = true
    #expect(key(0, other).clippedShift(from: old) == nil, "another ambient field")
    #expect(key(0, ambient([0, 0, 100, 140, 4, 4, 4, 4])).clippedShift(from: old) == nil, "a clip of another count")
}
