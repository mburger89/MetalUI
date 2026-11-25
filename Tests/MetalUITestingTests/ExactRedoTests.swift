import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Exact redo (record 417, `RK-AI`): the frame a redo builds equals the frame a fresh window builds, because what the abandoned
// attempt wrote is rolled back first. The fixture is Alloy's transcript (a bottom-anchored `LazyVStack` of `.equatable()` rows
// with a rounded, tinted chrome, streaming one word a frame) under an opacity ancestor that changes every frame: that is a
// replayed prepaint under a different paint-only ambient, so every frame is redone once (`RK-C`).

extension G49Block: Identifiable {}

/// A row with `BlockChrome`'s shape: a tinted rounded background around the text.
struct XRRow: Component, @MainActor Equatable {
    let block: G49Block
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(block.text.components(separatedBy: "\n\n"), id: \.self) { paragraph in Text(paragraph) }
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: Pixels(8)))
    }
}

/// The containers a rollback owes an exact undo: the transcript's lazy stack, a variable-height `List` and a lazy grid, each in a
/// scroller anchored to its end, with a streaming last element and a replayed card under an opacity that changes (`RK-C`).
/// `zoom` is `aZoomedNodeIsHitWhereItIsDrawn`'s shape (ten `.equatable()` nodes under `scaleEffect`, `RZ-`) under the same trigger: every
/// zoom step asks the atlas for glyphs at a scale it has not packed.
enum XRArm: String, CaseIterable { case transcript, variableList, grid, zoom }

/// A streaming word of letters no earlier word used (Latin Extended-A), so every step asks the atlas for a glyph it has not packed.
func xrStreaming(_ step: Int) -> String {
    "streaming" + (0..<step).map { " w" + (Unicode.Scalar(0x100 + $0 % 120).map(Character.init) ?? "x").description }.joined()
}

struct XRRoot: Component {
    let side: RPSide
    let arm: XRArm
    var content: some ElementGroup {
        let dimmed = side.model.n % 2 == 1
        let blocks = g49Blocks + [G49Block(id: 999, kind: 1, text: xrStreaming(Int(side.inputs.offset)))]
        VStack(spacing: 0) {
            // The redo's trigger: a replayed card under an ancestor whose opacity changes (`RK-C`).
            ZStack { RPCard(title: "A", shade: 1, log: side.log).equatable() }.opacity(dimmed ? 0.5 : 1)
            if arm == .zoom {
                ZoomRoot(side: side)
            } else {
            ScrollViewReader { _ in
                ScrollView {
                    switch arm {
                    case .transcript:
                        LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                            ForEach(blocks, id: \.id) { b in XRRow(block: b).equatable() }
                        }.padding(g49Inset)
                    case .variableList:
                        List(blocks, estimatedRowHeight: Pixels(60)) { b in VStack(spacing: 0) { XRRow(block: b) } }
                    case .zoom:
                        Box()
                    case .grid:
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Pixels(8)) {
                            ForEach(blocks, id: \.id) { b in XRRow(block: b) }
                        }.padding(g49Inset)
                    }
                }
                .defaultScrollAnchor(.bottom).contentMargins(.bottom, Pixels(40), for: .scrollContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
        }
    }
}

@MainActor func xrPair(_ arm: XRArm = .transcript) throws -> RPPair<some Element> {
    try RPPair(size: sz(420, 600), scale: 2, warm: 8, accessibility: false) { side in VStack(spacing: 0) { XRRoot(side: side, arm: arm) } }
}

/// One streamed word and one opacity change on both sides, settled, one frame each.
@MainActor func xrStep(_ pair: RPPair<some Element>, zoom: Bool = false) async {
    pair.onSide.model.n += 1; pair.offSide.model.n += 1
    for side in [pair.onSide, pair.offSide] { side.inputs.offset = zoom ? 1 + 0.02 * Float(side.model.n) : side.inputs.offset + 1 }
    await rsSettle()
    pair.redraw()
}

/// The ids whose registered element bounds differ between the two windows, with both values.
/// The glyph records of the window's last scene whose atlas rectangle the atlas holds no key for: a record that outlived a rollback of the glyph it
/// names (it would draw an empty slot).
@MainActor func xrDanglingGlyphs(_ window: TestWindow) -> Int {
    window.scene.glyphs.filter { glyph in
        glyph.atlasBounds.size.width > 0 && window.window.glyphAtlas.key(forAtlasX: glyph.atlasBounds.origin.x, y: glyph.atlasBounds.origin.y,
                                                                         width: glyph.atlasBounds.size.width, height: glyph.atlasBounds.size.height) == nil
    }.count
}

@MainActor func xrBoundsDifferences(_ pair: RPPair<some Element>) -> [String] {
    let a = pair.on.window.testingElementBounds, b = pair.off.window.testingElementBounds
    var out: [String] = []
    for id in Set(a.keys).union(b.keys) where a[id] != b[id] {
        func short(_ b: Bounds<Pixels>?) -> String { b.map { "(\($0.origin.x.value),\($0.origin.y.value) \($0.size.width.value)x\($0.size.height.value))" } ?? "none" }
        out.append("\(sbPath(id).suffix(60)): \(short(a[id])) vs \(short(b[id]))")
    }
    return out.sorted()
}

private let xrVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the redo counts this test pins are not its to read"

/// The frame a redo builds registers the element bounds a fresh frame does (record 416 "Found, separate": the rows 11 points from a
/// fresh frame's on master, the stack's spacing and a point of the anchor's remainder). The abandoned attempt's prepaint wrote the
/// scroller's anchor memory and clamp and the lazy container's index; the redo planned from them. Red on master.
/// Mutations: the state undo log off (`StateTable.logUndo` returning at once), the index journal off (`RowExtentIndex.beginAttempt` doing nothing).
@Test(.enabled(if: !rsVerifying, xrVerifyingNote)) @MainActor
func theRedoFrameRegistersTheElementBoundsAFreshFrameDoes() async throws {
    let pair = try xrPair()
    pair.frames = []
    var redone = 0
    for step in 0..<30 {
        await xrStep(pair)
        let f = try #require(pair.frames.last)
        redone += f.retainedRedos
        let differences = xrBoundsDifferences(pair)
        #expect(differences.isEmpty, "step \(step) (redos \(f.retainedRedos)): \(differences.prefix(6))")
        try pair.compare("step \(step)")
    }
    #expect(redone >= 2, "the opacity ancestor redid the frame in \(redone) of 30 steps (the backoff spaces them): a run with no redo proves nothing")
}

/// A rolled-back attempt leaves every store as it found it (`RK-AI`, `RK-AJ`): at each redo the state table's digest (every entry's value
/// description, liveness, generation and **version**, the mark set, the journals' lengths, and the contents of every `RowExtentIndex`
/// held in a `LazyOrigin` or `ListOrigin`, bit for bit) after the rollback equals the one before the attempt, and differs from the
/// one the attempt left (an attempt that wrote nothing proves nothing). Mutations: the undo log off (the entries differ), the
/// index journal off (the index contents differ), the marks not restored, the journals not truncated.
@Test(.enabled(if: !rsVerifying, xrVerifyingNote), arguments: XRArm.allCases) @MainActor
func aRolledBackAttemptLeavesEveryStoreAsItFoundIt(arm: XRArm) async throws {
    let pair = try xrPair(arm)
    pair.on.window.testingRollbackDigests = []
    for _ in 0..<30 { await xrStep(pair, zoom: arm == .zoom) }
    let rolled = try #require(pair.on.window.testingRollbackDigests)
    try #require(rolled.count >= 2, "\(arm.rawValue): redos \(rolled.count)")
    var wrote = 0, wroteAtlas = 0
    for (index, digests) in rolled.enumerated() {
        let differing = Set(digests.before).symmetricDifference(Set(digests.after)).sorted().prefix(3)
        #expect(digests.before == digests.after, "\(arm.rawValue) redo \(index): \(differing)")
        if digests.during != digests.before { wrote += 1 }
        // The atlas's lines (`GL-K`): the glyph map, the slot map and the packer line; the attempt packed glyphs the rollback had to forget.
        let atlasBefore = Set(digests.before.filter { $0.hasPrefix("packer ") || $0.hasPrefix("slot ") })
        if Set(digests.during.filter { $0.hasPrefix("packer ") || $0.hasPrefix("slot ") }) != atlasBefore { wroteAtlas += 1 }
    }
    #expect(wrote >= 1, "\(arm.rawValue): no attempt wrote anything the rollback had to undo")
    #expect(wroteAtlas >= 1, "\(arm.rawValue): no attempt packed a glyph the rollback had to forget")
    #expect(pair.on.window.testingAtlasAttempt.growthsInAbandoned == 0, "\(arm.rawValue): the atlas doubled inside an abandoned attempt")
}

/// A redone frame equals a fresh frame in every channel the rollback covers (`RK-AI`): the scene, hitboxes, tallies, Tab order and element
/// bounds of the window that redoes equal the window that never retains, at the redo frame and the three frames after it, and the state
/// table holds the same entries live. Mutations as `theRedoFrameRegistersTheElementBoundsAFreshFrameDoes`.
@Test(.enabled(if: !rsVerifying, xrVerifyingNote), arguments: XRArm.allCases) @MainActor
func aRedoneFrameEqualsAFreshFrameInEveryChannel(arm: XRArm) async throws {
    let pair = try xrPair(arm)
    pair.frames = []
    var redone = 0
    for step in 0..<30 {
        await xrStep(pair, zoom: arm == .zoom)
        let redo = pair.frames.last?.retainedRedos ?? 0
        redone += redo
        try pair.compare("\(arm.rawValue) step \(step)")
        let differences = xrBoundsDifferences(pair)
        #expect(differences.isEmpty, "\(arm.rawValue) step \(step) (redos \(redo)): \(differences.prefix(4))")
        #expect(pair.on.window.testingStateEntries == pair.off.window.testingStateEntries, "\(arm.rawValue) step \(step): live state entries")
        #expect(xrDanglingGlyphs(pair.on) == 0, "\(arm.rawValue) step \(step) (redos \(redo)): glyph records naming a slot the atlas forgot")
        let slotsOn = Set(pair.on.window.testingAtlasSlots), slotsOff = Set(pair.off.window.testingAtlasSlots)
        #expect(slotsOn == slotsOff, "\(arm.rawValue) step \(step) (redos \(redo)): atlas slots and packer: only on \(slotsOn.subtracting(slotsOff).map { $0.prefix(40) + "…" + $0.suffix(60) }.sorted().prefix(3)), only off \(slotsOff.subtracting(slotsOn).map { $0.prefix(40) + "…" + $0.suffix(60) }.sorted().prefix(3))")
        if redo > 0 {
            for after in 1...3 {
                pair.redraw()
                try pair.compare("\(arm.rawValue) step \(step), \(after) frames after the redo")
                #expect(xrBoundsDifferences(pair).isEmpty, "\(arm.rawValue) step \(step), \(after) frames after the redo: element bounds")
            }
        }
    }
    #expect(redone >= 2, "\(arm.rawValue): redos \(redone)")
    #expect(pair.on.window.testingAtlasAttempt.growthsInAbandoned == 0, "\(arm.rawValue): the atlas doubled inside an abandoned attempt")
}

/// The steady-frame cost (`RK-AI`): an unchanged frame in an armed window logs nothing. The rollback arms the build whenever it could
/// be redone, so a frame that writes no state costs the log no entry, and registers no store beyond the lazy container's index. 7 requests are the
/// card's 3 and the scroller's 4 (the same on master).
@Test(.enabled(if: !rsVerifying, xrVerifyingNote)) @MainActor
func aQuietFrameWithAnArmedRollbackLogsNothing() async throws {
    let pair = try xrPair()
    for _ in 0..<3 { await xrStep(pair) }
    for _ in 0..<12 { pair.redraw() }   // the backoff ends and the ledgers settle
    pair.frames = []
    let before = pair.on.window.testingLastAttempt
    for _ in 0..<4 { pair.redraw() }
    let tally = pair.on.window.testingLastAttempt
    for (i, f) in pair.frames.enumerated() { #expect(f.retainedRedos == 0 && f.elementRequests == 7, "frame \(i): \(f.elementRequests) requests, \(f.retainedRedos) redos") }
    #expect(tally.closed == before.closed + 4, "each quiet frame ran armed: \(before.closed) to \(tally.closed)")
    #expect(tally.loggedEntries == 0 && !tally.rolledBack, "a quiet frame logged \(tally.loggedEntries) entries")
    #expect(tally.registeredStores <= 1, "one lazy container's index: \(tally.registeredStores)")
    #expect(pair.on.window.testingAtlasAttempt.loggedKeys == 0, "a quiet frame packed \(pair.on.window.testingAtlasAttempt.loggedKeys) glyphs")
}

/// A streaming frame logs one entry per state it writes (`RK-AI`), never one per row: the log's size is the frame's writes. Measured: 1 (the
/// scroller's state; 0 in the frames the backoff leaves unarmed), on a 51-row transcript.
@Test(.enabled(if: !rsVerifying, xrVerifyingNote)) @MainActor
func aStreamingFrameLogsOneEntryPerWrittenState() async throws {
    let pair = try xrPair()
    var atlasKeys: [Int] = []
    for _ in 0..<14 { pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1; await rsSettle(); pair.redraw() }
    var logged: [Int] = []
    for _ in 0..<6 {
        pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
        await rsSettle()
        let writesBefore = pair.on.window.testingStatePlainWriteCount
        pair.redraw()
        let tally = pair.on.window.testingLastAttempt
        logged.append(tally.loggedEntries)
        atlasKeys.append(pair.on.window.testingAtlasAttempt.loggedKeys)
        #expect(tally.loggedEntries <= max(1, pair.on.window.testingStatePlainWriteCount - writesBefore),
                "logged \(tally.loggedEntries), plain writes \(pair.on.window.testingStatePlainWriteCount - writesBefore)")
    }
    // The scroller's own state (its anchor memory and clamp) is the one entry a streaming frame writes; the lazy container's origin is a
    // compared write that finds its value unchanged, and the index journals inside the class, not in the log.
    #expect(logged.allSatisfy { $0 <= 1 } && logged.contains(1), "the log is the frame's writes, not the table: \(logged)")
    // The atlas logs one key per glyph the frame packs for the first time (`GL-K`): the new letter of the streamed word, never a visible glyph.
    #expect(atlasKeys.allSatisfy { $0 <= 2 } && atlasKeys.contains { $0 > 0 }, "atlas keys logged a frame: \(atlasKeys)")
}

// MARK: the atlas (`GL-K`)

@MainActor private func zoomCentre(_ window: TestWindow, _ label: String) throws -> Point<Pixels> {
    let element = try window.element(label: label)
    let frame = try #require(try window.accessibilityTree.geometry[element.id]?.frame)
    return Point(x: Pixels(frame.origin.x.value + frame.size.width.value / 2), y: Pixels(frame.origin.y.value + frame.size.height.value / 2))
}

/// `aZoomedNodeIsHitWhereItIsDrawn`'s shape forced through redos (`GL-K`, record 418; it went red under a scoped redo in record 416 because the
/// abandoned attempt's glyphs were left packed): zoom steps under a replayed card whose opacity changes, a click at the drawn centre of a node
/// after each step. The retaining window equals the plain one at every step, the redo frames included, and it was redone.
@Test(.enabled(if: !rsVerifying, xrVerifyingNote)) @MainActor
func aZoomedNodeIsHitWhereItIsDrawnThroughARedo() async throws {
    let pair = try RPPair(size: sz(1500, 700), scale: 2, warm: 6, accessibility: true) { side in VStack(spacing: 0) { XRRoot(side: side, arm: .zoom) } }
    var redone = 0
    for step in 0..<24 {
        await xrStep(pair, zoom: true)
        redone += pair.frames.last?.retainedRedos ?? 0
        let drawn = try zoomCentre(pair.on, "z3")
        for w in [pair.on, pair.off] { w.click(at: drawn) }
        try pair.compare("clicks after zoom step \(step)")
        #expect(pair.onSide.log.entries.contains("z3"), "step \(step): the node is hit where it is drawn")
        #expect(pair.on.window.testingAtlasSlots == pair.off.window.testingAtlasSlots, "step \(step): atlas slots")
        #expect(xrDanglingGlyphs(pair.on) == 0, "step \(step): glyph records naming a slot the atlas forgot")
    }
    #expect(redone >= 2, "the opacity ancestor redid the zoom frame \(redone) times")
    #expect(pair.on.window.testingAtlasAttempt.growthsInAbandoned == 0)
}

private func atlasKey(_ i: Int) -> GlyphKey {
    GlyphKey(font: FontKey(resolvedPostScriptName: "Exact-Redo-Test", size: 13, variations: [],
                           matrix: .init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)),
             glyph: UInt16(i), size: 13, subpixelVariant: 0, scaleFactor: 1)
}

/// An abandoned attempt's glyphs are packed once (`GL-K`): an attempt that packs A, B and an empty glyph and is rolled back leaves the atlas
/// as it found it (map, slot map, shelf cursor, frame counter, area, pixels, dirty regions, stamps); the redo packing B and C finds B
/// at the shelf's origin, so the abandoned A leaves no hole, and `rasterize` runs once per key per pack. An attempt that was accepted
/// keeps everything. Growth inside an attempt is not undone and is counted. Mutations: the key log off (the glyph map keeps A and B), the
/// packer fields not restored (B lands after A's hole), the stamps not restored (the live area of a re-stamped glyph is lost), the
/// pixels not zeroed (the digest's pixel hash), `currentGeneration` not restored.
@Test @MainActor func anAbandonedAttemptsGlyphsArePackedOnce() throws {
    func image(_ w: Int, _ h: Int, _ fill: UInt8) -> GlyphImage { GlyphImage(width: w, height: h, bytes: [UInt8](repeating: fill, count: w * h)) }
    let atlas = GlyphAtlas(width: 64, height: 64, maximumExtent: 256)
    atlas.beginFrame()
    _ = try #require(atlas.slot(for: atlasKey(1), rasterize: { image(20, 10, 7) }))
    atlas.endFrame()
    atlas.clearDirtyRect()
    let before = atlas.attemptDigest, slotsBefore = atlas.slotDigest
    // The attempt: a frame that re-stamps glyph 1, packs A (2), B (3) and an empty glyph (4).
    atlas.beginAttempt()
    atlas.beginFrame()
    _ = try #require(atlas.slot(for: atlasKey(1), rasterize: { image(1, 1, 0) }))
    let a = try #require(atlas.slot(for: atlasKey(2), rasterize: { image(30, 12, 9) }))
    _ = try #require(atlas.slot(for: atlasKey(3), rasterize: { image(10, 8, 5) }))
    _ = atlas.packed(for: atlasKey(4), rasterize: { GlyphImage(width: 0, height: 0, bytes: []) })
    atlas.endFrame()
    #expect(atlas.attemptLoggedKeys == 3 && atlas.attemptDigest != before)
    atlas.rollbackAttempt()
    #expect(atlas.attemptDigest == before && atlas.slotDigest == slotsBefore && !atlas.isAttemptOpen, "rolled back")
    // The redo: B and C. B takes the slot A took.
    var rasterized = 0
    atlas.beginFrame()
    let b = try #require(atlas.slot(for: atlasKey(3), rasterize: { rasterized += 1; return image(30, 12, 5) }))
    _ = try #require(atlas.slot(for: atlasKey(5), rasterize: { rasterized += 1; return image(10, 8, 6) }))
    atlas.endFrame()
    #expect(b == a && rasterized == 2, "the abandoned glyph left no hole: \(b) against \(a)")
    // Accepted: nothing is undone; a doubling inside an attempt is counted and kept.
    let accepted = GlyphAtlas(width: 16, height: 16, maximumExtent: 64)
    accepted.beginAttempt()
    accepted.beginFrame()
    _ = try #require(accepted.slot(for: atlasKey(9), rasterize: { image(30, 30, 1) }))
    accepted.endFrame()
    let kept = accepted.attemptDigest
    accepted.acceptAttempt()
    #expect(accepted.attemptDigest == kept && accepted.growthsInAbandonedAttempts == 0 && accepted.attemptLoggedKeys == 0)
    let grown = GlyphAtlas(width: 16, height: 16, maximumExtent: 64)
    grown.beginAttempt()
    grown.beginFrame()
    _ = try #require(grown.slot(for: atlasKey(9), rasterize: { image(30, 30, 1) }))
    grown.endFrame()
    grown.rollbackAttempt()
    #expect(grown.growthsInAbandonedAttempts == 1 && grown.width == 32 && grown.slotDigest.count == 1, "growth stays and is counted")
}

/// The redo is the frame's one aging step for the text caches (`GL-K`): every abandoned attempt ends its text bracket with `abandonFrame()` (not
/// `endFrame()`, whose sweep and epoch advance a redo would count twice), the redo's own bracket ends with `endFrame()`, and the brackets balance.
/// Resolves the plan's question about `ShapingCache.beginFrame`: yes, a redo advanced the generation twice (`ShapingCache.beginFrame` is
/// `currentGeneration += 1` and the abandoned frame's `endFrame()` swept), so an entry last used the frame before aged one frame early.
/// Mutation: the abandon path calling `endFrame()` (abandons 0, ends one higher).
@Test(.enabled(if: !rsVerifying, xrVerifyingNote)) @MainActor
func aRedoAdvancesTheTextCachesEpochOnce() async throws {
    let counting = CountingTextSystem(harnessTextSystem())
    let side = RPSide()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: false)
    let window = try TestWindow(size: sz(420, 600), colorScheme: .light, scaleFactor: 2, options: options, textSystem: { counting }) {
        VStack(spacing: 0) { XRRoot(side: side, arm: .transcript) }
    }
    window.window.testingTimelineClockOffset = 0
    for _ in 0..<8 { window.window.setNeedsRedraw(); window.tick() }
    window.window.focus(nil)
    for _ in 0..<2 { window.window.setNeedsRedraw(); window.tick() }
    counting.begins = 0; counting.ends = 0; counting.abandons = 0
    var redos = 0, frames = 0
    for _ in 0..<30 {
        side.model.n += 1; side.inputs.offset += 1
        await rsSettle()
        window.window.setNeedsRedraw(); window.tick()
        redos += window.lastFrameWork.retainedRedos
        frames += 1
    }
    #expect(redos >= 2, "redos \(redos)")
    #expect(counting.abandons == redos, "abandoned brackets \(counting.abandons) for \(redos) redos")
    #expect(counting.begins == counting.ends + counting.abandons, "the brackets balance: \(counting.begins) begins, \(counting.ends) ends, \(counting.abandons) abandons")
    #expect(counting.ends >= frames, "each drawn frame ended its bracket once")
}

// MARK: the index's journal on its own

/// A `RowExtentIndex` journals what an attempt does to it (`RK-AJ`) and a rollback restores it bit for bit: records over measured and
/// unmeasured rows, a record that changes only an id, a width change, a data change (rows moved, dropped, added), and the three
/// together after records, each against a copy of the index as it was. Floats are accumulated in a history-dependent order, so a restore
/// by the inverse delta is not exact; the journal holds the old node values. Mutations: the node journal off (the trees differ), the
/// row journal off (heights and ids differ), the snapshot off (a rebuild or a width change is not undone), the snapshot taken after the
/// first rebuild's arrays are replaced.
@Test @MainActor func aRolledBackIndexIsTheIndexItWas() {
    func make() -> RowExtentIndex<Int> {
        let index = RowExtentIndex<Int>(count: 40, declaredEstimate: nil)
        index.forgetMeasurements(width: 300)
        for row in 0..<25 { index.record(Double(17 + (row * 7) % 13) / 3, at: row, id: row) }
        return index
    }
    let scenarios: [(String, (RowExtentIndex<Int>) -> Void)] = [
        ("records", { for row in [3, 30, 24, 3] { $0.record(41.37 + Double(row), at: row, id: row) } }),
        ("an id", { $0.record($0.extent(at: 5), at: 5, id: 500) }),
        ("a width", { $0.forgetMeasurements(width: 280) }),
        ("a rebuild", { $0.rebuild(ids: [3, 4, 5, 99, 7, 100, 0]) }),
        ("records then a rebuild", { index in
            for row in 0..<10 { index.record(9.9 + Double(row), at: row, id: row) }
            index.rebuild(ids: (0..<60).map { $0 % 41 })
            index.record(1.5, at: 2, id: 2)
        }),
        ("records, a width, then records", { index in
            index.record(88.8, at: 1, id: 1)
            index.forgetMeasurements(width: 123)
            index.record(7.7, at: 2, id: 2)
        })
    ]
    for (name, mutate) in scenarios {
        let index = make()
        let before = index.attemptContents
        index.beginAttempt()
        mutate(index)
        #expect(index.attemptContents != before, "\(name): the scenario changed nothing")
        index.rollbackAttempt()
        #expect(index.attemptContents == before, "\(name): rolled back")
        #expect(index.journalledWrites == 0, "\(name): the journal is freed")
        // The same scenario on an index that accepts: nothing is undone.
        let kept = make()
        kept.beginAttempt()
        mutate(kept)
        let after = kept.attemptContents
        kept.endAttempt()
        #expect(kept.attemptContents == after && kept.journalledWrites == 0, "\(name): accepted")
    }
    // A quiet attempt (equal values) journals nothing.
    let quiet = make()
    quiet.beginAttempt()
    for row in 0..<25 { quiet.record(quiet.extent(at: row), at: row, id: row) }
    #expect(quiet.journalledWrites == 0, "equal records journal \(quiet.journalledWrites)")
    quiet.endAttempt()
}

/// The undo log's own contract at the table (`RK-AI`): created, rewritten, deleted-by-reset and liveness-flipped entries come back as
/// they were, versions included; `marked` and the journals return; an accepted attempt keeps its writes and frees the log, and a log
/// above 1024 entries is dropped, not kept.
@Test @MainActor func aRolledBackStateTableIsTheTableItWas() {
    let table = StateTable()
    let a = GlobalElementID.child(of: nil, at: 0, name: ElementID("a"))
    let b = GlobalElementID.child(of: a, at: 0, name: ElementID("b")), c = GlobalElementID.child(of: a, at: 1, name: ElementID("c"))
    let d = GlobalElementID.child(of: a, at: 2, name: ElementID("d")), e = GlobalElementID.child(of: a, at: 3, name: ElementID("e"))
    let f = GlobalElementID.child(of: a, at: 4, name: ElementID("f")), g = GlobalElementID.child(of: a, at: 5, name: ElementID("g"))
    table.withState(a, initial: 1) { $0 = 2 }
    for id in [b, d, e, f, g] { table.write(id, "old") }
    table.sweep()   // every entry tombstoned: unmarked, not live
    let before = table.attemptDigest
    let counter = table.entryVersion(a)
    table.beginAttempt()
    table.withState(a, initial: 0) { $0 = 99 }   // rewritten
    table.write(b, 3.5)   // rewritten with another type
    table.withState(c, initial: 7) { $0 += 1 }   // created
    table.mark(g)   // the four ways a tombstone is made live again, each a flip the rollback undoes
    table.touchLive(d)
    table.markLive(e)
    table.mark(f, seeding: 0)
    table.markJournal.append(c); table.readJournal.append(a)
    #expect(table.attemptLogCount == 7 && table.attemptDigest != before)
    let created = table.rollbackAttempt()
    #expect(created == [c] && table.attemptDigest == before, "rolled back")
    #expect(table.entryVersion(a) == counter && !table.attemptArmed && table.attemptLogCount == 0)
    // A reset the attempt makes mid-frame (a conditional slot absent and produced again, `ID-C`) deletes what is under it; the rollback brings it back.
    let slot = GlobalElementID.child(of: nil, at: 5, name: ElementID("slot")), under = GlobalElementID.child(of: slot, at: 0, name: ElementID("under"))
    table.noteProduced(slot)
    table.write(under, "kept")
    table.sweep()
    let beforeReset = table.attemptDigest
    table.beginAttempt()
    table.noteAbsent(slot)
    table.noteProduced(slot)
    #expect(table.peek(under, as: String.self) == nil, "the reset deleted the entry under the slot")
    table.rollbackAttempt()
    #expect(table.attemptDigest == beforeReset && table.peek(under, as: String.self) == "kept", "the deleted entry is back")
    // Accepted: the writes stay.
    table.beginAttempt()
    table.withState(a, initial: 0) { $0 = 5 }
    table.acceptAttempt()
    #expect(table.peek(a, as: Int.self) == 5 && table.attemptLogCount == 0 && table.lastAttempt.loggedEntries == 1)
    // Nothing armed: a rollback does nothing.
    table.withState(a, initial: 0) { $0 = 6 }
    table.rollbackAttempt()
    #expect(table.peek(a, as: Int.self) == 6)
    // A big log is dropped at accept.
    table.beginAttempt()
    for index in 0..<(StateTable.attemptLogRetainedEntries + 5) { table.write(GlobalElementID.child(of: a, at: index, name: ElementID("n\(index)")), index) }
    #expect(table.attemptLogCount == StateTable.attemptLogRetainedEntries + 5)
    table.acceptAttempt()
    #expect(table.attemptLogCount == 0 && table.lastAttempt.loggedEntries == StateTable.attemptLogRetainedEntries + 5)
}

/// A record the attempt made names a glyph by its atlas rectangle, and the redo may pack a different glyph of the same size into the rectangle the rollback
/// emptied (the packer is rewound, bitmaps of digits and of most capitals share a size): the rectangle is occupied again, so "is the slot still packed" cannot
/// tell the record's glyph from the redo's. The atlas answers per rolled-back rectangle (`wasRolledBack`), whatever has been packed there since. Found by Linux CI
/// on `aRedoWithATimelineInTheTreeEqualsAFreshFrame` (the timeline's new digits drew the redo's glyphs from the attempt's record). Mutation: `wasRolledBack`
/// answering `false` (the aliased record is kept).
@Test @MainActor func aRecordNamingARolledBackSlotIsRefusedEvenWhenTheRedoRefilledIt() throws {
    func image(_ fill: UInt8) -> GlyphImage { GlyphImage(width: 12, height: 14, bytes: [UInt8](repeating: fill, count: 12 * 14)) }
    let atlas = GlyphAtlas(width: 64, height: 64)
    atlas.beginAttempt()
    atlas.beginFrame()
    let slot = try #require(atlas.slot(for: atlasKey(1), rasterize: { image(1) }))
    atlas.endFrame()
    atlas.rollbackAttempt()
    atlas.beginFrame()
    let again = try #require(atlas.slot(for: atlasKey(2), rasterize: { image(2) }))
    atlas.endFrame()
    #expect(again == slot, "another glyph of the same size takes the rectangle")
    #expect(atlas.key(forSlot: slot) != nil, "so the rectangle is occupied and a presence check cannot tell")
    #expect(atlas.wasRolledBack(x: Float(slot.x), y: Float(slot.y), width: Float(slot.width), height: Float(slot.height)))
    #expect(!atlas.wasRolledBack(x: 50, y: 50, width: 3, height: 3))
}
