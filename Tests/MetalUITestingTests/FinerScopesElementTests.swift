import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-d lane 1 (`FS-`, record 126): a `List` row that is an `.equatable()` occurrence retains like the same row in a `VStack`.
// Figures are `FrameWork` counts per frame (work, never time), taken at 711ab9c4 by `docs/probes/finer-scopes/`.

private let fsVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay and graft counts this test pins are not its to read"

/// F1 (green on arrival, `FS-A`): one `ForEach` row's value changes, the other 23 replay and graft.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote)) @MainActor
func aChangedRowMissesAloneAndItsSiblingsReplayAndGraft() throws {
    let frames = try fsFrames(graft: true) { $0.values[10] += 1 }
    for f in frames {
        #expect(f.retainedHits == 23 && f.retainedMisses == 1)
        #expect(f.retainedPrepaintHits == 23 && f.retainedGrafts == 23)
        #expect(f.elementRequests == 8 && f.retainedSkippedRequests == 161)
        #expect(f.elementPrepaints == 9 && f.elementPaints == 11)
    }
}

/// F4, the target (`FS-C`, red on arrival at 711ab9c4: prepaint hits 0, grafts 0, 84 requests): nothing moves, every visible
/// row of an `.equatable()` card replays its prepaint and grafts.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases) @MainActor
func aStaticListOfEquatableRowsReplaysPrepaintAndGrafts(branch: FSBranch) throws {
    let frames = try fsFrames(graft: true, list: branch)
    for f in frames {
        #expect(f.retainedHits > 0 && f.retainedMisses == 0)
        #expect(f.retainedPrepaintHits == f.retainedHits, "every row that hits at paint hits at prepaint: \(f.retainedPrepaintHits) of \(f.retainedHits)")
        #expect(f.retainedGrafts == f.retainedHits, "every row that hits grafts: \(f.retainedGrafts) of \(f.retainedHits)")
        // Literals taken on the fixed tree (red on arrival at 711ab9c4: 84 requests, 85 prepaints, 22 paints, 0 / 0 for uniform).
        let expected = branch == .uniform ? (rows: 9, requests: 21, skipped: 63, prepaints: 22, paints: 22)
                                          : (rows: 10, requests: 23, skipped: 70, prepaints: 24, paints: 24)
        #expect(f.retainedHits == expected.rows)
        #expect(f.elementRequests == expected.requests && f.retainedSkippedRequests == expected.skipped)
        #expect(f.elementPrepaints == expected.prepaints && f.elementPaints == expected.paints)
        #expect(f.retainedRedos == 0)
    }
}

/// F4 with the value of one row changing (red on arrival): that row misses alone, the others replay and graft.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases) @MainActor
func aChangedListRowMissesAloneAndTheOthersGraft(branch: FSBranch) throws {
    let frames = try fsFrames(graft: true, list: branch) { $0.values[3] += 1 }
    for f in frames {
        #expect(f.retainedMisses == 1)
        #expect(f.retainedPrepaintHits == f.retainedHits, "\(f.retainedPrepaintHits) of \(f.retainedHits)")
        #expect(f.retainedGrafts == f.retainedHits, "\(f.retainedGrafts) of \(f.retainedHits)")
        let expected = branch == .uniform ? (rows: 8, requests: 28, prepaints: 29, paints: 32)
                                          : (rows: 9, requests: 30, prepaints: 31, paints: 34)
        #expect(f.retainedHits == expected.rows)
        #expect(f.elementRequests == expected.requests && f.elementPrepaints == expected.prepaints && f.elementPaints == expected.paints)
    }
}

/// With no accessibility client the same list already replays (green on arrival): the defect needs a client, because the
/// suppression part of the prepaint key (`AB-X`) exists only while one collects (`FS-N`).
@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases) @MainActor
func aStaticListWithNoAccessibilityClientAlreadyReplays(branch: FSBranch) throws {
    let frames = try fsFrames(graft: true, accessibility: false, list: branch)
    for f in frames {
        #expect(f.retainedHits > 0)
        #expect(f.retainedPrepaintHits == f.retainedHits && f.retainedGrafts == f.retainedHits)
    }
}

// MARK: the differential

private struct FSDiffRoot: Component {
    let side: RPSide
    let branch: FSBranch
    var content: some ElementGroup {
        ScrollView(.vertical) {
            switch branch {
            case .uniform:
                List((0..<8).map { FSRow(id: $0) }, rowHeight: Pixels(100)) { r in
                    Column { RPCard(title: "r\(r.id)", shade: r.id == 2 ? Int(side.inputs.offset) : 0, log: side.log).equatable() }
                }
            case .variable:
                List((0..<8).map { FSRow(id: $0) }) { r in
                    Column { RPCard(title: "r\(r.id)", shade: r.id == 2 ? Int(side.inputs.offset) : 0, log: side.log).equatable() }
                }
            }
        }.frame(width: Pixels(300), height: Pixels(260))
    }
}

/// A retained `List` frame equals a retention-off frame (scene, hitboxes in order, accessibility tree, Tab order, bounds)
/// through a row edit, a click and a wheel, with a client active and with none; the retaining side did replay prepaint
/// (a differential that replays nothing proves nothing). Red on arrival with a client: no row replays.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases, [true, false]) @MainActor
func aListRowReplayEqualsAFreshWindowWithAccessibilityOnAndOff(branch: FSBranch, accessibility: Bool) throws {
    let pair = try RPPair(size: sz(320, 300), accessibility: accessibility) { side in
        VStack(spacing: 0) { FSDiffRoot(side: side, branch: branch) }
    }
    try pair.compare("warm")
    // Phase A: edits and quiet frames, nothing focused or hovered: every unchanged row replays its prepaint.
    for step in 0..<3 {
        for side in [pair.onSide, pair.offSide] { side.inputs.offset = Float(step + 1) }
        pair.redraw()
        try pair.compare("edit \(step)")
    }
    pair.redraw(); pair.redraw()
    let quiet = try #require(pair.frames.last)
    try pair.compare("quiet")
    #expect(quiet.retainedHits > 0 && quiet.retainedPrepaintHits == quiet.retainedHits,
            "a quiet frame replays every row's prepaint: \(quiet.retainedPrepaintHits) of \(quiet.retainedHits)")
    // Phase B: a click, a wheel and an edit, each compared whole.
    for step in 0..<4 {
        for w in [pair.on, pair.off] { w.click(at: pt(60, 40 + Float(step) * 30)) }
        try pair.compare("click \(step)")
        for w in [pair.on, pair.off] { w.scroll(at: pt(100, 100), byDeltaX: 0, deltaY: step.isMultiple(of: 2) ? -20 : 20) }
        try pair.compare("scroll \(step)")
        for side in [pair.onSide, pair.offSide] { side.inputs.offset = Float(step + 5) }
        pair.redraw()
        try pair.compare("edit after \(step)")
    }
}

// MARK: C14-c4

/// C14-c4 (`FS-H`, green on arrival by construction): an occurrence under a function-holding custom key never grafts and is counted
/// ineligible, the frame equals the retention-off window's. The refusal is the key's (`BuildKey.environment` never equals itself);
/// `aBuildKeyUnderAnUncomparableReadingEqualsNothing` pins that half where a mutation of the key reaches it.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote)) @MainActor
func aGraftIsRefusedUnderAnUncomparableKey() throws {
    let sides = EESides()
    let pair = try RPPair(size: sz(200, 80), warm: 16) { side in
        VStack(spacing: 4) {
            EESchemeReader(log: sides.of(side).log).equatable().environment(\.eeFn, EEFn(run: { 3 }))
        }
    }
    for _ in 0..<3 {
        pair.redraw()
        let f = try #require(pair.frames.last)
        #expect(f.retainedGrafts == 0 && f.retainedHits == 0, "\(f.retainedGrafts) grafts, \(f.retainedHits) hits")
        #expect(f.retainedIneligible == 1, "counted ineligible: \(f.retainedIneligible)")
        try pair.compare("a function key")
    }
}

// MARK: the differential on the F4 fixture

/// The F4 rows (text cards with no handler, the list whose first frame is unbounded under a collecting client, `AB-X`) through
/// a retaining window and a retention-off one: scene, accessibility tree (every row's text), hitboxes, Tab order equal through an
/// edit of one row and quiet frames; the retaining side replayed every visible row's prepaint (`FS-N`).
/// Mutation: `suppression` ignored by `retainedPrepaintKey` (a ledger made while the rows were suppressed replays in a bounded frame).
@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases) @MainActor
func aSuppressedFirstFrameLedgerReplaysTheSameTreeAsAFreshWindow(branch: FSBranch) throws {
    let onModel = FSModel(), offModel = FSModel()
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: true)
    func make(_ model: FSModel) throws -> TestWindow {
        try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: 2, options: options,
                       textSystem: { harnessTextSystem() }) { VStack(spacing: 0) { FSListRoot(model: model, branch: branch) } }
    }
    let on = try make(onModel), off = try make(offModel)
    on.window.testingTimelineClockOffset = 0; off.window.testingTimelineClockOffset = 0
    off.window.testingRetainedSubtrees = false
    on.window.testingRetainedGraft = true
    func redraw() { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    func compare(_ step: String) throws {
        let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(differences.isEmpty, "after \(step): \(differences)")
    }
    for _ in 0..<16 { redraw() }
    try compare("warm")
    var quiet = FrameWork()
    for step in 0..<4 {
        if step == 2 { onModel.values[3] += 1; offModel.values[3] += 1 }
        redraw()
        quiet = on.lastFrameWork
        try compare("frame \(step)")
    }
    #expect(quiet.retainedHits > 0 && quiet.retainedPrepaintHits == quiet.retainedHits && quiet.retainedGrafts == quiet.retainedHits,
            "\(quiet.retainedPrepaintHits) prepaint hits and \(quiet.retainedGrafts) grafts of \(quiet.retainedHits) rows")
}

// MARK: the reads-subset guard of `refreshLedger`

/// A card whose prepaint reads state (an unfocused `TextField`, `RW-`): its fresh ledger names entries a record must version.
private struct FSFieldCard: Component, @MainActor Equatable {
    let id: Int
    let value: Int
    static func == (l: FSFieldCard, r: FSFieldCard) -> Bool { l.id == r.id && l.value == r.value }
    var content: some ElementGroup {
        HStack(spacing: 4) {
            Text("Card \(id) = \(value)")
            TextField("name", text: .constant("x"))
        }
        .frame(height: Pixels(24))
    }
}

private struct FSFieldListRoot: Component {
    let model: FSModel
    let branch: FSBranch
    var content: some ElementGroup {
        ScrollView(.vertical) {
            switch branch {
            case .uniform:
                List(model.ids.map { FSRow(id: $0) }, rowHeight: Pixels(26)) { r in
                    Column { FSFieldCard(id: r.id, value: r.id == 3 ? model.values[3] : 0).equatable() }
                }
            case .variable:
                List(model.ids.map { FSRow(id: $0) }) { r in
                    Column { FSFieldCard(id: r.id, value: r.id == 3 ? model.values[3] : 0).equatable() }
                }
            }
        }.frame(width: Pixels(300), height: Pixels(150))
    }
}

@Test(.enabled(if: !rsVerifying, fsVerifyingNote), arguments: FSBranch.allCases) @MainActor
func aFieldRowListReplaysAndEqualsAFreshWindow(branch: FSBranch) throws {
    let onModel = FSModel(), offModel = FSModel()
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: true)
    func make(_ model: FSModel) throws -> TestWindow {
        try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: 2, options: options,
                       textSystem: { harnessTextSystem() }) { VStack(spacing: 0) { FSFieldListRoot(model: model, branch: branch) } }
    }
    let on = try make(onModel), off = try make(offModel)
    on.window.testingTimelineClockOffset = 0; off.window.testingTimelineClockOffset = 0
    off.window.testingRetainedSubtrees = false
    on.window.testingRetainedGraft = true
    for _ in 0..<16 { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    var quiet = FrameWork()
    for step in 0..<4 {
        if step == 2 { onModel.values[3] += 1; offModel.values[3] += 1 }
        for w in [on, off] { w.window.setNeedsRedraw(); w.tick() }
        quiet = on.lastFrameWork
        let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
        #expect(differences.isEmpty, "frame \(step): \(differences)")
    }
    #expect(quiet.retainedHits > 0 && quiet.retainedPrepaintHits == quiet.retainedHits && quiet.retainedGrafts == quiet.retainedHits,
            "\(quiet.retainedPrepaintHits) prepaint hits and \(quiet.retainedGrafts) grafts of \(quiet.retainedHits) rows")
}

/// Whether `FSContextReader` reads its second entry; the test turns it on after the window's first frame.
@MainActor private enum FSReaderGate {
    static var readsSecond = false
    /// An entry a sibling outside every card creates in every frame: it exists before the cards ever read it.
    static var shared: GlobalElementID?
}

private struct FSSharedOwner: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        _ = pass.readState(id, initial: 0)
        FSReaderGate.shared = id
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 1, height: 1)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {}
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

/// An element whose prepaint reads one state entry once the gate is on (a sibling outside the list made it): a ledger made under the `List`'s unbounded first
/// frame (suppressed, `AB-X`) reads {A}, a later bounded frame's reads {A, B}, and B is an entry the standing record does not
/// version.
private struct FSContextReader: Element {
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 40, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        if FSReaderGate.readsSecond {
            if let shared = FSReaderGate.shared { _ = pass.readState(shared, initial: 0) }
        }
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        pass.fill(bounds, color: Hsla(h: 0.6, s: 0.5, l: 0.5, a: 1))
    }
}

private struct FSReaderCard: Component, @MainActor Equatable {
    let id: Int
    static func == (l: FSReaderCard, r: FSReaderCard) -> Bool { l.id == r.id }
    var content: some ElementGroup {
        HStack(spacing: 4) { Text("Card \(id)"); FSContextReader() }.frame(height: Pixels(24))
    }
}

private struct FSReaderListRoot: Component {
    let model: FSModel
    var content: some ElementGroup {
        ScrollView(.vertical) {
            List(model.ids.map { FSRow(id: $0) }, rowHeight: Pixels(28)) { r in
                Column { FSReaderCard(id: r.id).equatable() }
            }
        }.frame(width: Pixels(300), height: Pixels(150))
    }
}

/// `refreshLedger`'s reads-subset guard (`FS-N`): a fresh ledger that read an entry the standing record does not version
/// must not replace the record's ledger, or a change of that entry would replay a stale prepaint. The rows keep their paint
/// record and replay no prepaint; the frame equals the retention-off window's.
/// Mutation: delete the `for id in fresh.reads where !old.versions.contains(…) { return }` line of `refreshLedger`.
@Test(.enabled(if: !rsVerifying, fsVerifyingNote)) @MainActor
func aFreshLedgerThatReadAnUnversionedEntryIsNotSwappedIn() throws {
    let onModel = FSModel(), offModel = FSModel()
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: true)
    func make(_ model: FSModel) throws -> TestWindow {
        try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: 2, options: options,
                       textSystem: { harnessTextSystem() }) { VStack(spacing: 0) { FSSharedOwner(); FSReaderListRoot(model: model) } }
    }
    FSReaderGate.readsSecond = false
    let on = try make(onModel), off = try make(offModel)
    defer { FSReaderGate.readsSecond = false }
    on.window.testingTimelineClockOffset = 0; off.window.testingTimelineClockOffset = 0
    off.window.testingRetainedSubtrees = false
    on.window.testingRetainedGraft = true
    FSReaderGate.readsSecond = true   // after the window's first frames: the rows' ledgers were made reading nothing
    for _ in 0..<16 { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    for _ in 0..<3 { for w in [on, off] { w.window.setNeedsRedraw(); w.tick() } }
    let quiet = on.lastFrameWork
    let differences = try RPSnapshot(on).differences(from: RPSnapshot(off))
    #expect(differences.isEmpty, "\(differences)")
    #expect(quiet.retainedHits > 0, "the rows still replay their paint")
    #expect(quiet.retainedPrepaintHits == 0, "no row replays a ledger the record cannot version: \(quiet.retainedPrepaintHits)")
}
