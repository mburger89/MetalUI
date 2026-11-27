import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Testing

// Hitboxes and accessibility rects cut by a clip their occurrence opened move exactly where the viewport edge now cuts them (`FS-X`, record 434): the
// clips a prepaint pushed are journalled, kept on the ledger when a registration sits deeper than its entry, and folded again with `pushClip`'s own
// arithmetic at the position the ledger was made and the one it moves to. Before, a row at the edge refused `accessibilityClipped` / `hitboxClipped` and the
// frame was redone (`graftedPrepaint`), quarantining the row for 8 builds and more.

private let cfVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the translation counts this test pins are not its to read"

/// A row 60 pt tall (the geometry of `MRRow`, so a 10 pt wheel step keeps the viewport edge clear of every corner zone): a `Text` and a `Button` inside a
/// rounded clip, each a hitbox and an accessibility record at an inner clip depth.
private struct CFRow: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 0) {
            Text("row \(id)").frame(height: Pixels(22))
            Button("go \(id)") {}.frame(height: Pixels(22))
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.2 + 0.1 * Double(id % 3)))
        .cornerRadius(Pixels(8))
    }
}

/// The same row with a rounded chrome and nothing registered inside it.
private struct CFChromeOnly: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        Box().frame(maxWidth: .infinity).frame(height: Pixels(60)).background(Color.accent.opacity(0.2)).cornerRadius(Pixels(8))
    }
}

/// A row with no clip at all.
private struct CFPlain: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        VStack(spacing: 0) { Text("row \(id)").frame(height: Pixels(22)); Button("go \(id)") {}.frame(height: Pixels(22)) }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: Pixels(60))
    }
}

private enum CFKind { case rounded, chromeOnly, plain }

private struct CFRoot: Component {
    let kind: CFKind
    var content: some ElementGroup {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(Array(0..<8), id: \.self) { k in
                    switch kind {
                    case .rounded: CFRow(id: k).equatable()
                    case .chromeOnly: CFChromeOnly(id: k).equatable()
                    case .plain: CFPlain(id: k).equatable()
                    }
                }
            }
        }
        .frame(width: Pixels(300), height: Pixels(150))
    }
}

@MainActor private func cfPair(_ kind: CFKind = .rounded, scale: Float = 2) throws -> RPPair<some Element> {
    try RPPair(size: sz(320, 300), scale: scale, warm: 16, accessibility: true, graft: false) { _ in VStack(spacing: 0) { CFRoot(kind: kind) } }
}

/// Scrolls both windows of the pair by `delta` points; the retaining window's work of the step.
@MainActor private func cfScroll(_ pair: RPPair<some Element>, by delta: Float) async -> FrameWork {
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.scroll(at: pt(150, 150), byDeltaX: 0, deltaY: -delta) }
    await rsSettle()
    pair.redraw()
    return pair.stepWork
}

private let cfGateReasons: Set<String> = ["accessibilityClipped", "hitboxClipped", "accessibilityNotFolded", "hitboxNotFolded",
                                          "accessibilityUnmapped", "hitboxUnmapped"]

/// A row cut by the viewport edge moves its hitboxes and accessibility records, equal to a fresh frame, with no redo and no refusal.
/// Three 10 pt steps: row 0 leaves the top edge, row 2 keeps the bottom edge in its body.
/// Mutations: the fold's new rect left as the old shifted rect (the pair compare differs at the edge), the slow path removed (every cut row refuses
/// `hitboxClipped` / `accessibilityClipped` again).
@Test(.enabled(if: !rsVerifying, cfVerifyingNote)) @MainActor
func aRowCutByTheViewportMovesItsAccessibilityAndHitbox() async throws {
    let pair = try cfPair()
    try pair.compare("warm")
    var translated = 0, hits = 0
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    for step in 0..<3 {
        let f = await cfScroll(pair, by: 10)
        translated += f.retainedTranslated
        hits += f.retainedPrepaintHits
        #expect(f.retainedTranslationRefusedReasons.isEmpty, "step \(step): refused \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedRedos == 0, "step \(step): redos \(f.retainedRedos)")
        try pair.compare("step \(step)")
    }
    #expect(hits >= translated && translated >= 3 * 3, "prepaint hits \(hits), translated \(translated)")
    #expect(!lines.contains { $0.contains("translationRefused") }, "a refusal was traced: \(lines.filter { $0.contains("translationRefused") })")
}

/// The streamed transcript of records 416 and 423 with an accessibility client: no frame refuses a clipped registration any more; what redos remain
/// name a mask (`maskCrossingChanged`, `innerScope`: the later fix).
/// Mutation: the slow path removed (the transcript refuses `accessibilityClipped` / `hitboxClipped` as on master).
@Test(.enabled(if: !rsVerifying, cfVerifyingNote)) @MainActor
func aStreamedTranscriptWithAccessibilityRefusesNoClippedRegistration() async throws {
    let pair = try ctPair(accessibility: true)
    var reasons: [String: Int] = [:]
    var redos = 0, requests = 0
    for step in 0..<40 {
        let f = await ctStep(pair).reduce(FrameWork(), +)
        reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        redos += f.retainedRedos; requests += f.elementRequests
        try pair.compare("step \(step)")
    }
    print("CF transcript: requests \(requests), redos \(redos), refusals \(reasons)")
    #expect(reasons.keys.allSatisfy { !cfGateReasons.contains($0) && !$0.hasPrefix("accessibility") && !$0.hasPrefix("hitbox") }, "refusals: \(reasons)")
    #expect(reasons.keys.allSatisfy { ["maskCrossingChanged", "innerScope", "maskCrossed"].contains($0) }, "only a mask refuses: \(reasons)")
}

/// The fold at the old position must give the rect that was recorded: a ledger whose recorded hitbox rect is not what the fold makes refuses
/// `hitboxNotFolded` (and an emission `accessibilityNotFolded`), and the redone frame is equal to a fresh one.
/// Mutation: the comparison against the recorded rect removed (the tampered rect moves, the pair compare differs).
@Test(.enabled(if: !rsVerifying, cfVerifyingNote), arguments: [false, true]) @MainActor
func theFoldAtTheOldPositionMustReproduceTheRecordedCut(emission: Bool) async throws {
    let pair = try cfPair()
    var tampered = 0
    for record in pair.on.window.testingRetainedRecords() {
        guard let ledger = record.prepaint, ledger.innerClips != nil else { continue }
        if emission {
            for index in ledger.axEmissions.indices {
                ledger.axEmissions[index].geometry.visibleFrame.size.width = Pixels(ledger.axEmissions[index].geometry.visibleFrame.size.width.value + 1)
                tampered += 1
            }
        } else {
            for index in ledger.hitboxes.indices {
                ledger.hitboxes[index].bounds.size.width = Pixels(ledger.hitboxes[index].bounds.size.width.value + 1)
                tampered += 1
            }
        }
    }
    try #require(tampered > 0, "no ledger holds inner clips")
    let f = await cfScroll(pair, by: 10)
    let name = emission ? "accessibilityNotFolded" : "hitboxNotFolded"
    #expect(f.retainedTranslationRefusedReasons[name, default: 0] >= 1, "named: \(f.retainedTranslationRefusedReasons)")
    #expect(f.retainedRedos == 0, "the refused ledger runs its prepaint again, no redo: \(f.retainedRedos)")
}

/// A cut row moves exactly at every scale, or refuses by name and is painted again: scale 1 and 9/8 with 8 and 16 pt steps move (the unmoved axis is free,
/// `FS-W`); at 1.2 a 5 pt step (6 px) is a whole pixel, yet the **paint record** refuses `inexactTranslation` there (its layout origins times 1.2 are not
/// sixteenths: `newY` 228, a leaf at 195.6) and the occurrence runs its prepaint again, so the ledger is never asked (record 434 reports this: the 1.2
/// arm the brief called "must move" is bounded by the paint record, not the fold), and a step that is not a whole pixel refuses `fractionalTranslation`.
/// In every arm the pair is equal to a fresh frame and no gate of the fold refuses.
/// Mutation: the fold's new rect left as the old shifted rect reddens the compare of the scale 1 and 9/8 arms (the edge cut differs).
@Test(.enabled(if: !rsVerifying, cfVerifyingNote), arguments: [(Float(1), Float(8)), (1, 16), (1.125, 8), (1.125, 16), (1.2, 5), (1.2, 1)])
@MainActor
func aCutRowMovesExactlyAtEveryScale(scale: Float, step: Float) async throws {
    let pair = try cfPair(scale: scale)
    var reasons: [String: Int] = [:]
    var translated = 0, hits = 0
    for index in 0..<4 {
        let f = await cfScroll(pair, by: step)
        reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        translated += f.retainedTranslated; hits += f.retainedPrepaintHits
        try pair.compare("scale \(scale) step \(step) #\(index)")
    }
    print("CF scale \(scale) step \(step): translated \(translated), prepaint hits \(hits), refusals \(reasons)")
    #expect(reasons.keys.allSatisfy { !cfGateReasons.contains($0) }, "the fold never refuses by its own gate: \(reasons)")
    if scale == 1.2, step == 1 {
        #expect(reasons["fractionalTranslation", default: 0] >= 1, "a step that is not a whole pixel refuses: \(reasons)")
    } else if scale == 1.2 {
        #expect(reasons["inexactTranslation", default: 0] >= 1, "bounded by the paint record's exactness: \(reasons)")
    } else {
        #expect(hits > 0 && translated > 0, "the cut rows move: prepaint hits \(hits), translated \(translated), \(reasons)")
    }
}

/// A ledger pays for the clips its occurrence pushed only where a registration sits inside them: rows with a plain layout, and a rounded chrome with
/// nothing registered inside, keep `innerClips == nil`; a rounded row with a text and a button keeps its one clip. An idle frame costs what it did.
/// Mutation: `innerClips` set whenever a clip was pushed (the chrome-only ledgers hold one).
@Test(.enabled(if: !rsVerifying, cfVerifyingNote)) @MainActor
func aLedgerPaysOnlyForTheClipsItsOccurrencePushed() async throws {
    func ledgers(_ pair: RPPair<some Element>) -> [PrepaintLedger] {
        pair.on.window.testingRetainedRecords().compactMap(\.prepaint).filter { !$0.hitboxes.isEmpty || !$0.axEmissions.isEmpty || !$0.elementBounds.isEmpty }
    }
    let plain = ledgers(try cfPair(.plain)), chrome = ledgers(try cfPair(.chromeOnly)), rounded = ledgers(try cfPair(.rounded))
    try #require(!plain.isEmpty && !rounded.isEmpty)
    #expect(plain.allSatisfy { $0.innerClips == nil }, "no clip pushed, none stored")
    #expect(chrome.allSatisfy { $0.innerClips == nil }, "a clip with nothing registered inside it is not stored")
    #expect(rounded.contains { $0.innerClips?.count == 1 }, "a rounded row keeps its one clip")
    #expect(rounded.allSatisfy { ($0.innerClips?.count ?? 0) <= 2 }, "bounded by the occurrence's own pushes")
    #expect(MemoryLayout<PrepaintClip>.stride <= 72, "the bytes a clip adds to a ledger: \(MemoryLayout<PrepaintClip>.stride)")
    // An idle frame: no clip is journalled (no recorder is open), so the cost is the frame's own.
    let pair = try cfPair()
    for _ in 0..<3 { pair.redraw() }
    #if canImport(Darwin)
    let allocations = try #require(countAllocations { pair.on.window.setNeedsRedraw(); pair.on.tick() })
    let requests = pair.on.lastFrameWork.elementRequests
    print("CF idle frame: allocations \(allocations), requests \(requests)")
    #endif
}

/// A clip pushed by a `Deferred` (a root clip) or at a flattening entry is never folded: its parent is another space, so a registration under it refuses
/// `rootClip`. The fold's primitive answers `nil` for it and for a clip below it, and the rect of an ordinary clip beside it.
/// Mutation: the root check of `state` removed (a root clip folds as an ordinary one and the first two expectations fail).
@Test @MainActor
func aRegistrationUnderARootClipStillRefuses() throws {
    let entry = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(300), height: Pixels(150)))
    func clip(parent: Int32, depth: Int32, flags: UInt8) -> PrepaintClip {
        PrepaintClip(clip: InnerClip(x: 4, y: 4, width: 100, height: 40, offsetX: 0, offsetY: 0, topLeft: 0, topRight: 0, bottomRight: 0,
                                     bottomLeft: 0, parent: parent, depth: depth, lo: 0, hi: 1, flags: flags), axLo: 0, axHi: 1)
    }
    let clips = [clip(parent: -1, depth: 2, flags: InnerClip.rootFlag), clip(parent: 0, depth: 3, flags: 0),
                 clip(parent: -1, depth: 2, flags: InnerClip.flatteningEntryFlag), clip(parent: -1, depth: 2, flags: 0)]
    func fold(_ index: Int) -> Bounds<Pixels>? {
        PrepaintClipFold.foldedClipRect(clips, at: index, entryClip: entry, entryRadii: Corners(all: Pixels(0)),
                                        entryOffset: Point(x: Pixels(0), y: Pixels(0)), origin: (10, 20))
    }
    #expect(fold(0) == nil, "a root clip")
    #expect(fold(1) == nil, "a clip pushed inside a root clip")
    #expect(fold(2) == nil, "a clip at a flattening entry")
    #expect(fold(3) == Bounds(origin: Point(x: Pixels(14), y: Pixels(24)), size: Size(width: Pixels(100), height: Pixels(40))), "an ordinary clip folds")
}

