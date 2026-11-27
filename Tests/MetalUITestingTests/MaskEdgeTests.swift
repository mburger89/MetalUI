import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import ObjectiveC
import Testing

// Record 437 (`FS-Z`): the canonical crossing record. See `MaskEdgeFixture.swift`.

private let meVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the redo and refusal counts these tests pin are not its to read"

// MARK: Tests

/// The F3 table (`FS-Z`): a rounded row 31 pt tall under the viewport's straight top edge opens its crossing mask scope exactly when the cut passes through an
/// arc band (0 < hidden < r, or hidden > H - r) or leaves under two radii of its body (hidden > H - 2r); the same at r 8 and 10, scale 1 and 2.
@Test(arguments: [Float(8), 10], [Float(1), 2]) @MainActor
func aStraightEdgeCutMasksOnlyInTheArcBand(radius: Float, scale: Float) async throws {
    let pair = try meFixedPair(radius: radius, scale: scale)
    let height: Float = 31
    var at: Float = 0
    for hidden in [Float(0), 2, radius - 1, radius, radius + 1, height - 2 * radius, height - 2 * radius + 1, height - radius, height - 3, height + 1] {
        await meScroll(pair, by: hidden - at); at = hidden
        let crossing = (hidden > 0 && hidden < radius) || (hidden > height - 2 * radius && hidden < height)
        #expect((!pair.on.scene.groups.isEmpty) == crossing, "r \(radius) scale \(scale) hidden \(hidden): groups \(pair.on.scene.groups.count), crossing expected \(crossing)")
        try pair.compare("hidden \(hidden)")
        meCompareDeep(pair, "hidden \(hidden)")
    }
}

/// A crossing under an outer capturing scope keeps today's refusals (`FS-Z` rule 1: a scope opened with another scope around it is an inner scope), and the
/// work of 40 streamed steps is master's. Pinned at the numbers measured on master `eb25ea24`.
@Test(arguments: [Float(1), 2]) @MainActor
func aCrossingUnderAnOuterScopeStillRefusesByName(scale: Float) async throws {
    let pair = try mePair(arm: .outerScope, scale: scale)
    var reasons: [String: Int] = [:], redos = 0, requests = 0, translated = 0
    for step in 0..<40 {
        let f = await meStep(pair).reduce(FrameWork(), +)
        reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        redos += f.retainedRedos; requests += f.elementRequests; translated += f.retainedTranslated
        try pair.compare("step \(step)")
        meCompareDeep(pair, "step \(step)")
    }
    if rsVerifying { return }   // verify mode builds a replayed frame twice: its counts are not these tests' to read
    #expect(reasons == ["maskCrossingChanged": 5, "innerScope": 1], "refusals \(reasons)")
    #expect(redos == 7 && requests == 1389 && translated == 150, "redos \(redos) requests \(requests) translated \(translated)")
}

/// Alloy's streaming transcript in its island, 40 steps at both scales, with and without an accessibility client: no mask refusal and the redos master makes (`FS-Z`; 7 on master, 5 at the corner zones and one for the
/// row whose clip crosses as a recorded `innerScope`, steps 0 and 1 the first sight of the streaming row), every frame equal to a retention-off window's, deep.
/// Allocations are the ceiling master measured (546,500 and 547,500 at scales 1 and 2; 570,500 and 571,500 with an accessibility client).
@Test(arguments: [Float(1), 2], [false, true]) @MainActor
func anIslandTranscriptStreamsWithoutAMaskRedo(scale: Float, accessibility: Bool) async throws {
    let pair = try mePair(arm: .island, scale: scale, accessibility: accessibility)
    var reasons: [String: Int] = [:], redos = 0, allocations = 0
    for step in 0..<40 {
        let (frames, counted) = await meStepCounted(pair)
        let f = frames.reduce(FrameWork(), +)
        reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        redos += f.retainedRedos; allocations += counted
        try pair.compare("step \(step)")
        meCompareDeep(pair, "step \(step)")
    }
    if rsVerifying { return }   // verify mode builds a replayed frame twice: its counts are not these tests' to read
    // Master redoes 7 times here (5 corner-zone crossings, one `innerScope`, one at the first sight of the streaming row); the three that remain are the
    // geometry redos of rows realised as the lazy window grows, which a mask has nothing to do with (steps 1, 17 and 33 on master too).
    #expect(reasons.isEmpty, "no mask or innerScope refusal: \(reasons)")
    #expect(redos <= 3, "redos \(redos)")
    let ceiling = accessibility ? (scale == 1 ? 570_500 : 571_500) : (scale == 1 ? 546_500 : 547_500)
    #expect(allocations <= ceiling, "allocations \(allocations)")
}

/// What a record that never crosses pays (`FS-Z`): the same bytes and the same allocations as before. The structs are the sizes master has, the record is the
/// size master's is, no clip of a non-crossing record carries a scope bit, and a step that translates a record without crossing allocates what it did (3645).
@Test(arguments: [Float(1), 2]) @MainActor
func aRecordThatNeverCrossesPaysNothing(scale: Float) async throws {
    #expect(MemoryLayout<InnerClip>.stride == 60 && MemoryLayout<InnerClip>.size <= 60)
    #expect(MemoryLayout<CapturedPrimitive>.stride <= 280)
    #expect(MemoryLayout<UnitRange>.stride == 24)
    #expect(class_getInstanceSize(RetainedRecord.self) == 248, "RetainedRecord \(class_getInstanceSize(RetainedRecord.self))")
    let pair = try meFixedPair(radius: 8, scale: scale)
    await meScroll(pair, by: 8)   // row 0's cut at its radius: no crossing
    let records = pair.on.window.testingRetainedRecords().filter { !$0.scene.isEmpty }
    try #require(!records.isEmpty)
    for record in records where !(record.innerClips ?? []).contains(where: \.crosses) {
        #expect(record.innerClips?.allSatisfy { $0.flags & 32 == 0 } ?? true, "a non-crossing record carries a scope bit")
        #expect(record.finalIsScene || record.finalScene == nil, "a record made with no scope around it shares its stream")
    }
    let step = try await meInsideStep(scale: scale)
    if !rsVerifying {
        #expect(step.allocations == 3645, "a translated non-crossing step allocates \(step.allocations)")
        #expect(step.work.retainedRedos == 0)
    }
}

/// An idle frame of the island transcript costs what it did (`FS-Z`): at most 2360 allocations (master measures 2353 to 2357, by the order the suite runs in) and
/// 10 element requests, at both scales, after 30 streamed steps.
@Test(.enabled(if: !rsVerifying, meVerifyingNote), arguments: [Float(1), 2]) @MainActor
func anIdleFrameOfTheIslandTranscriptIsUnchanged(scale: Float) async throws {
    let pair = try mePair(arm: .island, scale: scale)
    for _ in 0..<30 { _ = await meStep(pair) }
    for _ in 0..<14 { pair.redraw() }
    for _ in 0..<4 {
        pair.off.window.setNeedsRedraw(); pair.off.tick()
        let allocations = countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() } ?? 0
        #expect(allocations <= 2360 && pair.on.lastFrameWork.elementRequests == 10, "idle: \(allocations) allocations, \(pair.on.lastFrameWork.elementRequests) requests")
        #expect(pair.on.lastFrameWork.retainedRedos == 0)
    }
}

// MARK: Stage 0 pins (master)

/// The fixed-scroller step a record translates through without crossing: row 0 from 8 pt above the edge to 9 pt (radius 8), the retaining window's draw counted.
@MainActor private func meInsideStep(scale: Float) async throws -> (allocations: Int, work: FrameWork) {
    let pair = try meFixedPair(radius: 8, scale: scale)
    await meScroll(pair, by: 8)
    await meScroll(pair, by: 1)   // settle: the record at 9 stands
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: pt(150, 120), byDeltaX: 0, deltaY: -1) }
    await rsSettle()
    pair.off.window.setNeedsRedraw(); pair.off.tick()
    let allocations = countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() } ?? 0
    return (allocations, pair.on.frameWork.reduce(FrameWork(), +))
}

/// The sequences of hidden points test 2 walks (`FS-Z`): row 0 of the fixed scroller 31 pt tall, r its radius. The cut is inside a corner zone below r and above
/// H - 2r; out is a row fully above the edge that is still painted (the lazy stack's two lines beyond the viewport).
@MainActor private func meSequence(_ name: String, radius r: Float) -> [Float] {
    let h: Float = 31
    switch name {
    case "insideToCrossing": return [r, r + 1, h - 2 * r + 2, h - 2 * r + 4]
    case "crossingToCrossing": return [2, 3, r - 1]
    case "crossingToOut": return [h - 3, h - 1, h + 1, h + 3]
    case "outToCrossing": return [h + 3, h + 1, h - 1, h - 3]
    default: return [2, r, r + 1, 2]   // crossingToInside and back
    }
}

/// A rounded row whose clip starts, keeps or stops crossing the viewport's straight edge moves by translation (`FS-Z`): no redo, no refusal, a translation each
/// step, and every frame equal to a retention-off window's, groups and masks included. The sequences go in, through and out of a crossing, and back.
/// Mutations: the seen-through scope treated as inner (`innerScope` refuses), the flags not rewritten on a move (the scope missing or left open: deep scene).
@Test(arguments: ["insideToCrossing", "crossingToCrossing", "crossingToOut", "outToCrossing", "crossingToInside"], [Float(1), 2]) @MainActor
func aRoundedRowCrossingAStraightEdgeTranslates(name: String, scale: Float) async throws {
    for radius in [Float(8), 10] {
        let pair = try meFixedPair(radius: radius, scale: scale)
        var at: Float = 0
        let sequence = meSequence(name, radius: radius)
        // The records are made where the sequence starts (a record made crossing is a record seen through a scope, the one a move must start from).
        await meScroll(pair, by: sequence[0]); at = sequence[0]
        pair.on.window.testingDropRetainedRecords()
        pair.redraw(); pair.redraw()
        for (step, hidden) in sequence.enumerated().dropFirst() {
            await meScroll(pair, by: hidden - at); at = hidden
            let f = pair.on.frameWork.reduce(FrameWork(), +)
            if !rsVerifying {   // verify mode builds a replayed frame twice: its counts are not these tests' to read
                #expect(f.retainedRedos == 0, "\(name) r \(radius) scale \(scale) step \(step) hidden \(hidden): redos \(f.retainedRedos)")
                #expect(f.retainedTranslationRefusedReasons.isEmpty, "r \(radius) step \(step) hidden \(hidden): refused \(f.retainedTranslationRefusedReasons)")
                #expect(f.retainedTranslated >= 1, "r \(radius) step \(step) hidden \(hidden): translated \(f.retainedTranslated)")
            }
            try pair.compare("\(name) r \(radius) step \(step)")
            meCompareDeep(pair, "\(name) r \(radius) step \(step)")
            #expect(pair.on.window.testingUnitRanges == pair.off.window.testingUnitRanges, "r \(radius) step \(step) hidden \(hidden): unit ranges")
        }
    }
}

/// A record made where its clip crosses is the record a paint with no crossing makes (`FS-Z`): the same op count, emitted count and unit ranges as the
/// record made inside, and the record moved there by a translation equals it (`differences`, no skip). The crossing record holds its glyphs as one op each and
/// one clip with a scope. Mutation: the split off (`scene.count`).
@Test(.enabled(if: !rsVerifying, meVerifyingNote), arguments: [Float(1), 2]) @MainActor
func aFreshCrossingRecordIsTheRecordANonCrossingPaintMakes(scale: Float) async throws {
    func row0(_ pair: RPPair<some Element>) throws -> RetainedRecord {
        try #require(pair.on.window.testingRetainedRecords().first { $0.key.rects.count >= 2 && $0.key.rects[1] == 0 && !$0.scene.isEmpty && $0.innerClips != nil })
    }
    // The record made where the cut is inside (hidden 8) and its numbers.
    let inside = try meFixedPair(radius: 8, scale: scale)
    await meScroll(inside, by: 8)
    inside.on.window.testingDropRetainedRecords()
    inside.redraw(); inside.redraw()
    let plain = try row0(inside)
    #expect(!plain.opensCrossingScope)
    let sceneCount = plain.scene.count, emitted = plain.emitted, ranges = plain.ranges
    // The record moved there by translation, and the record made fresh there (in the same window: an image's texture is one object per window).
    await meScroll(inside, by: -5)   // hidden 3: crossing
    let moved = try row0(inside)
    #expect(moved === plain, "the record moved in place")
    inside.on.window.testingDropRetainedRecords()
    inside.redraw(); inside.redraw()
    let crossing = try row0(inside)
    #expect(crossing !== moved)
    #expect(crossing.opensCrossingScope && !crossing.innerScopes, "a fresh crossing record: scope \(crossing.opensCrossingScope), inner scopes \(crossing.innerScopes)")
    #expect(crossing.innerClips?.filter(\.hasScope).count == 1)
    #expect(crossing.scene.count == sceneCount && crossing.emitted == emitted && crossing.ranges == ranges,
            "scene \(crossing.scene.count) vs \(sceneCount), emitted \(crossing.emitted) vs \(emitted), ranges \(crossing.ranges) vs \(ranges)")
    #expect(crossing.emitted == moved.emitted && crossing.ranges == moved.ranges)
    // The final stream the replay after the move captured is the stream a fresh paint there records, depths included (`FS-Z`).
    #expect(moved.differences(from: crossing) == nil, "\(moved.differences(from: crossing) ?? "")")
    #expect(crossing.finalScene != nil && !crossing.finalIsScene && crossing.finalScene?.count != crossing.scene.count)
}

/// A crossing record holds a text's glyphs as one op a glyph in its scene, and the masked group as one op in its final stream (`FS-Z`).
/// Mutation: the split off.
@Test(.enabled(if: !rsVerifying, meVerifyingNote)) @MainActor
func aCrossingRecordsGlyphsAreOneOpAGlyph() async throws {
    let pair = try meFixedPair(radius: 8, scale: 2)
    await meScroll(pair, by: 3)
    pair.on.window.testingDropRetainedRecords()
    pair.redraw(); pair.redraw()
    let record = try #require(pair.on.window.testingRetainedRecords().first { $0.opensCrossingScope && $0.key.rects[1] == 0 })
    let glyphs = record.scene.filter { op in op.leaves.contains { group in group.0.contains { if case .glyph = $0.kind { true } else { false } } } }
    try #require(!glyphs.isEmpty, "the row draws text")
    #expect(glyphs.allSatisfy { $0.leaves.count == 1 && $0.leaves[0].0.count == 1 }, "a glyph an op")
    let final = try #require(record.finalScene)
    #expect(final.count < record.scene.count, "the masked group is one op: final \(final.count) scene \(record.scene.count)")
    #expect(final.contains { $0.leaves.contains { $0.0.contains { !$0.groups.isEmpty } } }, "the merged leaf carries the mask")
}

/// The unit ranges a crossing row notes are what a fresh frame notes at every step, the exit included, and a conditional removed from a crossing row leaves the
/// ghost a fresh frame leaves (`FS-Z`). Mutations: true values stored in the record instead of the virtual ones, the re-note without the conversion.
@Test(arguments: [Float(1), 2]) @MainActor
func aUnitRangeInsideACrossingRowIsWhatAFreshFrameNotes(scale: Float) async throws {
    let pair = try meFixedPair(radius: 8, scale: scale)
    pair.onSide.inputs.showExtra = true; pair.offSide.inputs.showExtra = true
    pair.redraw(); pair.redraw()
    var at: Float = 0
    for hidden in [Float(4), 6, 12, 20, 28, 33, 28, 20, 6, 4] {
        await meScroll(pair, by: hidden - at); at = hidden
        #expect(pair.on.window.testingUnitRanges == pair.off.window.testingUnitRanges, "hidden \(hidden): unit ranges")
        try pair.compare("hidden \(hidden)")
        meCompareDeep(pair, "hidden \(hidden)")
    }
    await meScroll(pair, by: 4 - at)   // crossing again
    pair.onSide.inputs.showExtra = false; pair.offSide.inputs.showExtra = false
    for step in 0..<4 {
        await rsSettle(); pair.redraw()
        #expect(pair.on.window.testingUnitRanges == pair.off.window.testingUnitRanges, "ghost frame \(step): unit ranges")
        try pair.compare("ghost \(step)")
        meCompareDeep(pair, "ghost \(step)")
    }
}

/// What cannot be a canonical record refuses by name and still equals a fresh frame (`FS-Z`): two rounded clips crossing on one chain (`maskNested`), a leaf
/// a record cannot count one emission for (`maskNotCanonical`), a matched-geometry group inside (`maskMatchedGroups`). Mutations: the nested check off, the canonical-content check off.
@Test(arguments: [MERowKind.nested, .shape, .matched]) @MainActor
func eachCrossingThatCannotBeCanonicalRefusesByName(kind: MERowKind) async throws {
    let pair = try meFixedPair(radius: 10, scale: 2, kind: kind)
    await meScroll(pair, by: 10)   // the cut at the radius: the outer clip does not cross
    try pair.compare("inside")
    var reasons: [String: Int] = [:]
    var at: Float = 10
    for hidden in [Float(3), 10, 4, 12] {
        await meScroll(pair, by: hidden - at); at = hidden
        reasons.merge(pair.on.frameWork.reduce(FrameWork(), +).retainedTranslationRefusedReasons, uniquingKeysWith: +)
        try pair.compare("hidden \(hidden)")
        meCompareDeep(pair, "hidden \(hidden)")
    }
    let named = kind == .nested ? "maskNested" : kind == .matched ? "maskMatchedGroups" : "maskNotCanonical"
    if !rsVerifying { #expect(reasons[named, default: 0] >= 1, "\(kind): refusals \(reasons)") }
}
