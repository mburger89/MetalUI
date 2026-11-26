import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// A paint record whose rounded mask is cut by the entry clip (the scroll viewport) replays translated, exactly (`FS-V`, record 424): the clips the
// occurrence pushed are recorded and folded again at the new position with `pushClip`'s own arithmetic, so a leaf's mask and its radii are the ones a
// fresh frame computes. The fixture's rows are 60 pt tall under a 150 pt viewport with a rounded clip of 8 pt (`BlockChrome`'s shape), so a wheel step of
// 10 pt leaves the viewport edge clear of every corner zone (a cut that leaves under 16 pt of a row, or runs within 8 pt of its far edge, is one: the square-box fallback of `CM-J`) and a step of 45 pt leaves 15 pt of the fourth row.

private let mrVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the translation counts this test pins are not its to read"

private struct MRRow: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) { Text("row \(id)").frame(height: Pixels(44)) }
            .padding(Edges(all: Pixels(8)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accent.opacity(0.2 + 0.1 * Double(id % 3)))
            .cornerRadius(Pixels(8))   // a clip (`BlockChrome`), as the transcript fixture's rows
    }
}

/// A row that holds a nested `.equatable()` occurrence with a rounded clip of its own: the outer record holds the inner one's leaves, so it must hold its
/// clips too (`FS-V`: a replayed record's clips are noted into the recorders open around it).
private struct MRNested: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        VStack(spacing: 0) { MRRow(id: id).equatable() }
            .background(Color.green.opacity(0.1)).cornerRadius(Pixels(8))
    }
}

private struct MRRoot: Component {
    let nested: Bool
    var content: some ElementGroup {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(0..<8), id: \.self) { k in
                    if nested { MRNested(id: k).equatable() } else { MRRow(id: k).equatable() }
                }
            }
        }
        .frame(width: Pixels(300), height: Pixels(150))
    }
}

@MainActor private func mrPair(nested: Bool) throws -> RPPair<some Element> {
    try RPPair(size: sz(320, 300), scale: 2, warm: 16, accessibility: false, graft: false) { _ in VStack(spacing: 0) { MRRoot(nested: nested) } }
}

/// Scrolls both windows of the pair by `delta` points and answers the retaining window's work.
@MainActor private func mrScroll(_ pair: RPPair<some Element>, by delta: Float) async -> FrameWork {
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: pt(150, 150), byDeltaX: 0, deltaY: -delta) }
    await rsSettle()
    pair.redraw()
    return pair.stepWork
}

/// A rounded row cut by the viewport edge replays translated and equals a fresh frame (`FS-V`; was `maskStraddlesEntryClip`, a refusal and with it a
/// redo for Alloy's transcript). Three 10 pt steps: row 0 leaves the top edge (its top corners are cut square), row 2 keeps the bottom edge in its body.
/// Mutations: the radii not re-folded (row 0 keeps its four round corners where a fresh frame cuts two), the old move in place of the fold (every cut row refuses).
@Test(.enabled(if: !rsVerifying, mrVerifyingNote), arguments: [false, true]) @MainActor
func aRoundedRowAtTheViewportEdgeReplaysTranslated(nested: Bool) async throws {
    let pair = try mrPair(nested: nested)
    try pair.compare("warm")
    var translated = 0
    for step in 0..<3 {
        let f = await mrScroll(pair, by: 10)
        translated += f.retainedTranslated
        #expect(f.retainedTranslationRefusedReasons.isEmpty, "step \(step): refused \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedRedos == 0)
        try pair.compare("step \(step)")
    }
    #expect(translated >= 3 * 3, "the rows replay translated: \(translated)")
}

/// A move that puts the viewport edge inside a corner zone changes the push's crossing: the record refuses by name and the frame is painted again, equal
/// to a fresh one (`FS-V`). Mutation: the crossing check off (the replay keeps the square cut a fresh frame replaces by the exact pair coverage).
@Test(.enabled(if: !rsVerifying, mrVerifyingNote)) @MainActor
func aRowWhoseCornerZoneCrossesTheEdgeRefusesByName() async throws {
    let pair = try mrPair(nested: false)
    try pair.compare("warm")
    let f = await mrScroll(pair, by: 45)   // the bottom edge now leaves 15 pt of the fourth row, too little for its two top corners
    #expect(f.retainedTranslationRefusedReasons["maskCrossingChanged", default: 0] >= 1, "named: \(f.retainedTranslationRefusedReasons)")
    try pair.compare("crossed")
    let g = await mrScroll(pair, by: 10)   // and out of it again
    #expect(g.retainedTranslationRefusedReasons["maskStraddlesEntryClip"] == nil)
    try pair.compare("after")
}

/// What a record with inner clips costs, and what one without pays (`FS-V`): a record whose occurrence pushed nothing stores nothing; the clips of one that
/// did are one 60-byte struct each, bounded by the occurrence's own pushes.
@Test @MainActor
func aRecordPaysOnlyForTheClipsItsOccurrencePushed() async throws {
    #expect(MemoryLayout<InnerClip>.stride == 60, "the bytes a clip adds to a record: \(MemoryLayout<InnerClip>.stride)")
    let plain = try RPPair(size: sz(320, 300), scale: 2, warm: 4, accessibility: false, graft: false) { _ in
        VStack(spacing: 0) { ScrollView(.vertical) { VStack(spacing: 0) { ForEach(Array(0..<8), id: \.self) { k in
            MRPlain(id: k).equatable() } } }.frame(width: Pixels(300), height: Pixels(150)) }
    }
    let rounded = try mrPair(nested: false)
    func records(_ pair: RPPair<some Element>) -> [RetainedRecord] { pair.on.window.testingRetainedRecords() }
    let plainRecords = records(plain).filter { $0.scene.count > 0 }, roundedRecords = records(rounded).filter { $0.scene.count > 0 }
    try #require(!plainRecords.isEmpty && !roundedRecords.isEmpty)
    #expect(plainRecords.allSatisfy { $0.innerClips == nil }, "no clip pushed, none stored")
    #expect(roundedRecords.contains { ($0.innerClips?.count ?? 0) == 1 }, "one rounded clip a row")
}

private struct MRPlain: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        Text("row \(id)").frame(maxWidth: .infinity, alignment: .leading).frame(height: Pixels(60)).background(Color.accent.opacity(0.2))
    }
}

/// The transcript fixture of records 416 and 423, streaming 40 words: rows cut by the viewport edge no longer refuse, so the requests a streamed word costs
/// drop (mean 24.85 on `fix/exact-redo-verify`'s scoped redo, record 423). The redos that remain are the corner-zone crossings (`maskCrossingChanged`).
@Test(.enabled(if: !rsVerifying, mrVerifyingNote)) @MainActor
func theStreamingTranscriptRefusesOnlyAtACornerZone() async throws {
    let pair = try ctPair()
    var reasons: [String: Int] = [:]
    var requests: [Int] = []
    for step in 0..<40 {
        let f = await ctStep(pair).reduce(FrameWork(), +)
        reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        requests.append(f.elementRequests)
        try pair.compare("step \(step)")
    }
    let mean = Double(requests.reduce(0, +)) / Double(requests.count)
    #expect(reasons["maskStraddlesEntryClip"] == nil && reasons["maskNotFolded"] == nil && reasons["maskUnmapped"] == nil, "refusals: \(reasons)")
    #expect(reasons.keys.allSatisfy { ["maskCrossingChanged", "innerScope", "maskCrossed"].contains($0) }, "only the corner zone refuses: \(reasons)")
    #expect(mean < 20, "mean requests a streamed word \(mean) (24.85 before)")
}
