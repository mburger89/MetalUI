import MetalUI
import MetalUICore
import MetalUILayout
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14b-3 lane A (`RW-`): the instruments (`retainedIneligibleReasons`), the orbit-with-panel scenario counted at `f557d339`
// (**before** pins, green) and what lane B must reach (**after** pins, red on arrival), the mechanism end to end through an
// element that reads state in all three phases, and the memory pin. Counts, never time. Under `METALUI_VERIFY_RETAINED=1` a
// hit is painted as a miss, so the count assertions are off (`rsVerifying`) and the differentials stay.

private let verifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

// MARK: Test 1 — the orbit with a panel

/// One arm's orbit frame (the fourth of six after three warm frames), literals taken by this lane at `f557d339` and equal to the
/// design phase's (spec §1).
private struct OrbitFrame {
    let arm: BracketArm
    let requests: Int, skipped: Int, prepaints: Int, paints: Int
    let hits: Int, misses: Int, ineligible: Int, prepaintIneligible: Int, graftIneligible: Int
    let reasons: [String: Int]
}

private let orbitBefore: [OrbitFrame] = [
    OrbitFrame(arm: .value, requests: 156, skipped: 642, prepaints: 160, paints: 178, hits: 32, misses: 0,
               ineligible: 0, prepaintIneligible: 0, graftIneligible: 0, reasons: [:]),
    // The graph panel (`stateWrite`: the text field's, the scroller's and the list's reads, at paint, prepaint and graft) and
    // the top bar (`presentationAnchor`: its `Picker`/`Menu` anchors, at prepaint).
    OrbitFrame(arm: .panels, requests: 115, skipped: 683, prepaints: 117, paints: 110, hits: 34, misses: 0,
               ineligible: 1, prepaintIneligible: 2, graftIneligible: 1, reasons: ["stateWrite": 3, "presentationAnchor": 1]),
]

/// **Test 1, before arm** (green at `f557d339`, `RW-A`): the counts the item improves, taken with retention, prepaint replay and the
/// graft on. `requests + skipped` is the retention-off 798 (the conservation law) on the `.panels` arm.
/// **Mutations:** the `noteIneligible` funnel recording `"?"` reddens the reasons; `graftsBuild` forced off reddens requests.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: [BracketArm.value, BracketArm.panels]) @MainActor
func theOrbitWithPanelIsCountedBeforeReadOnlyState(arm: BracketArm) throws {
    let expected = try #require(orbitBefore.first { $0.arm == arm })
    let frames = try bracketOrbitFrames(arm: arm, frames: 6).frames
    try #require(frames.count == 6)
    let f = frames[3]
    #expect(f.builds == 1)
    #expect(f.elementRequests == expected.requests, "requests \(f.elementRequests)")
    #expect(f.retainedSkippedRequests == expected.skipped, "skipped \(f.retainedSkippedRequests)")
    #expect(f.elementRequests + f.retainedSkippedRequests == 798, "conservation against a retention-off frame")
    #expect(f.elementPrepaints == expected.prepaints, "prepaints \(f.elementPrepaints)")
    #expect(f.elementPaints == expected.paints, "paints \(f.elementPaints)")
    #expect(f.retainedHits == expected.hits && f.retainedMisses == expected.misses, "hits \(f.retainedHits) misses \(f.retainedMisses)")
    #expect(f.retainedIneligible == expected.ineligible, "paint ineligible \(f.retainedIneligible)")
    #expect(f.retainedPrepaintIneligible == expected.prepaintIneligible, "prepaint ineligible \(f.retainedPrepaintIneligible)")
    #expect(f.retainedGraftIneligible == expected.graftIneligible, "graft ineligible \(f.retainedGraftIneligible)")
    #expect(f.retainedIneligibleReasons == expected.reasons, "reasons \(f.retainedIneligibleReasons)")
    #expect(f.retainedRedos == 0)
    // The reasons sum to the three counters (`RW-M`).
    #expect(f.retainedIneligibleReasons.values.reduce(0, +)
            == f.retainedIneligible + f.retainedPrepaintIneligible + f.retainedGraftIneligible)
}

/// **Test 1, after arm — red on arrival** (`RW-A`; lane B turns it green by converting the call sites): in steady state the
/// panels arm's orbit frame has no ineligible occurrence at paint, prepaint or graft, no reason, and the graph panel and the top
/// bar join the hits (34 + 2), so the requests fall below the 115 of `f557d339`. **Red before:** ineligible 1, 2, 1.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func theOrbitWithPanelHasNoIneligibleOccurrencesAfterReadOnlyState() throws {
    let f = try bracketOrbitFrames(arm: .panels, frames: 6).frames[3]
    #expect(f.retainedIneligible == 0, "paint ineligible \(f.retainedIneligible)")
    #expect(f.retainedPrepaintIneligible == 0, "prepaint ineligible \(f.retainedPrepaintIneligible)")
    #expect(f.retainedGraftIneligible == 0, "graft ineligible \(f.retainedGraftIneligible)")
    #expect(f.retainedIneligibleReasons.isEmpty, "reasons \(f.retainedIneligibleReasons)")
    #expect(f.retainedHits == 36, "the graph panel and the top bar replay too: \(f.retainedHits)")
    #expect(f.elementRequests < 115, "requests \(f.elementRequests)")
}

// MARK: The probe element: state read in layout, prepaint and paint

@MainActor final class RWIDs { var id: GlobalElementID?; var layouts = 0; var paints = 0 }

private enum RWMode: String, CaseIterable, CustomTestStringConvertible {
    case readOnly, compared, plainWrite
    var testDescription: String { rawValue }
}

/// The phase(s) a probe reads its state in: only there, so a read set that leaves one window out shows as a stale replay.
private enum RWPhase: String, CaseIterable, CustomTestStringConvertible {
    case layout, prepaint, paint, all
    var testDescription: String { rawValue }
    func reads(_ other: RWPhase) -> Bool { self == .all || self == other }
}

/// A leaf whose width is ten times its state and whose rectangle's alpha is a tenth of it, the state read through the mode's spelling
/// in the phase(s) `phase` names (layout feeds the width, paint the alpha, prepaint nothing visible: a miss is its only trace).
private struct RWLeaf: Element {
    let mode: RWMode
    let ids: RWIDs
    var phase: RWPhase = .all
    var elementID: ElementID? { nil }

    private func value(_ id: GlobalElementID, layout: LayoutPass?, prepaint: PrepaintPass?, paint: PaintPass?) -> Int {
        var out = 0
        switch mode {
        case .readOnly:
            if let layout { out = layout.readState(id, initial: 1) }
            if let prepaint { out = prepaint.readState(id, initial: 1) }
            if let paint { out = paint.readState(id, initial: 1) }
        case .compared:
            if let layout { layout.withState(id, initial: 1, unchanged: { $0 == $1 }) { out = $0 } }
            if let prepaint { prepaint.withState(id, initial: 1, unchanged: { $0 == $1 }) { out = $0 } }
            if let paint { paint.withState(id, initial: 1, unchanged: { $0 == $1 }) { out = $0 } }
        case .plainWrite:
            if let layout { layout.withState(id, initial: 1) { out = $0 } }
            if let prepaint { prepaint.withState(id, initial: 1) { out = $0 } }
            if let paint { paint.withState(id, initial: 1) { out = $0 } }
        }
        return out
    }

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        ids.id = id; ids.layouts += 1
        let v = phase.reads(.layout) ? Double(value(id, layout: pass, prepaint: nil, paint: nil)) : 1
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10 * v, height: 20)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        if phase.reads(.prepaint) { _ = value(id, layout: nil, prepaint: pass, paint: nil) }
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        ids.paints += 1
        let v = phase.reads(.paint) ? value(id, layout: nil, prepaint: nil, paint: pass) : 1
        pass.fill(bounds, color: Hsla(h: 0.5, s: 0.5, l: 0.5, a: Float(v) / 10))
    }
}

private struct RWCard: Component, @MainActor Equatable {
    let mode: RWMode
    let ids: RWIDs
    var phase: RWPhase = .all
    var content: some ElementGroup { RWLeaf(mode: mode, ids: ids, phase: phase) }
    static func == (l: RWCard, r: RWCard) -> Bool { l.mode == r.mode && l.ids === r.ids && l.phase == r.phase }
}

@MainActor private func rwWindow(_ mode: RWMode, phase: RWPhase = .all, retained: Bool = true) throws -> (TestWindow, RWIDs) {
    let ids = RWIDs()
    let window = try TestWindow(size: sz(300, 100), textSystem: harnessTextSystem) {
        VStack(spacing: 4) { RWCard(mode: mode, ids: ids, phase: phase).equatable() }
    }
    window.window.testingRetainedSubtrees = retained
    return (window, ids)
}

@MainActor private func rwDraw(_ window: TestWindow) -> FrameWork {
    window.window.setNeedsRedraw(); window.tick()
    return window.lastFrameWork
}

/// The probe's rectangle: alpha and width are the state it read.
@MainActor private func rwRect(_ window: TestWindow) -> (alpha: Float, width: Float)? {
    guard let r = window.scene.rects.last else { return nil }
    return (r.background.a, r.bounds.size.width)
}

private let rwCases: [(RWMode, RWPhase)] = [(.readOnly, .layout), (.readOnly, .prepaint), (.readOnly, .paint), (.readOnly, .all), (.compared, .all)]

/// **The mechanism, end to end** (`RW-B`, `RW-C`, `RW-D`; no call site converted): an element that only reads its state in
/// layout, prepaint and paint replays every frame once its entry exists, and **an input write to the entry misses on the
/// version** and draws the new value in all three phases, as a retention-off twin does. A compared write with an equal value is a
/// read (same hits); the plain `withState` stays ineligible by name. **Red before:** `readState` does not exist.
/// Arms: the state read in layout only, prepaint only, paint only, all three, and the compared spelling. **Mutations:** the build
/// window's reads (`phase.build.reads`) left out of `record.versions` reddens the layout arm (a stale width), the prepaint
/// window's (`phase.prepaintReads`) the prepaint arm (a replay where the twin misses), the paint window's the paint arm (a stale
/// alpha); `readState` bumping the version reddens every arm (never a hit); the graft's `stateReads` check is covered by
/// the layout arm with `old.versions` mutated away too.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: rwCases.map { "\($0.0.rawValue)/\($0.1.rawValue)" }) @MainActor
private func aReadOnlyOccurrenceReplaysAndAnInputWriteToItsStateMisses(label: String) throws {
    let (mode, phase) = try #require(rwCases.first { "\($0.0.rawValue)/\($0.1.rawValue)" == label })
    let (window, ids) = try rwWindow(mode, phase: phase)
    let (twin, twinIDs) = try rwWindow(mode, phase: phase, retained: false)
    var f = FrameWork()
    for _ in 0..<2 { _ = rwDraw(window); _ = rwDraw(twin) }
    // The entry was created in the first frame (a write, `RW-F`), so a record made then may lack a prepaint ledger (a record that
    // hits keeps what it was made with): an input write of the same value makes the next two frames record whole.
    window.window.testingWriteState(try #require(ids.id), 1)
    twin.window.testingWriteState(try #require(twinIDs.id), 1)
    for _ in 0..<4 { f = rwDraw(window); _ = rwDraw(twin) }
    #expect(f.retainedHits == 1 && f.retainedMisses == 0 && f.retainedIneligible == 0 && f.retainedIneligibleReasons.isEmpty,
            "steady: hits \(f.retainedHits) misses \(f.retainedMisses) ineligible \(f.retainedIneligible) \(f.retainedIneligibleReasons)")
    #expect(f.retainedGrafts == 1 && f.retainedPrepaintHits == 1, "the build and prepaint are skipped too: \(f.retainedGrafts)/\(f.retainedPrepaintHits)")
    let id = try #require(ids.id)
    let version = window.window.testingStateVersion(id)
    let paints = ids.paints
    f = rwDraw(window)
    #expect(ids.paints == paints, "a hit runs no element paint")
    #expect(window.window.testingStateVersion(id) == version, "a replayed frame writes nothing")
    #expect(window.window.testingStateIsLive(id), "the entry stays live across replays")

    // An input write: the next frame misses on the version and draws 4 where the phase read it.
    window.window.testingWriteState(id, 4)
    twin.window.testingWriteState(try #require(twinIDs.id), 4)
    f = rwDraw(window); _ = rwDraw(twin)
    let rect = try #require(rwRect(window)), want = try #require(rwRect(twin))
    #expect(rect.alpha == want.alpha && rect.width == want.width, "equals the retention-off twin: \(rect) vs \(want)")
    if phase.reads(.layout) { #expect(rect.width == 40, "layout read the new state: \(rect)") }
    if phase.reads(.paint) { #expect(rect.alpha == 0.4, "paint read the new state: \(rect)") }
    #expect(f.retainedHits == 0 && f.retainedMisses == 1, "a miss on the version: hits \(f.retainedHits) misses \(f.retainedMisses)")
    // A record made on a miss covers only its paint (`SB-V`), so the next frame records again and the one after replays.
    f = rwDraw(window); _ = rwDraw(twin)
    #expect(f.retainedHits == 0 && f.retainedMisses == 1, "the frame after a miss records once more: \(f.retainedHits)/\(f.retainedMisses)")
    f = rwDraw(window); _ = rwDraw(twin)
    #expect(f.retainedHits == 1, "replays again: \(f.retainedHits)")
    let again = try #require(rwRect(window)), twinAgain = try #require(rwRect(twin))
    #expect(again.alpha == twinAgain.alpha && again.width == twinAgain.width)
}

/// **Liveness across replays** (`RW-E`; spec test 6's channel arms, here at the mechanism): an entry that only a replayed window read
/// stays live and is not reaped, once the table is past its reaping threshold (256 entries, `TB-AH`) and the occurrence has
/// replayed for a long run of frames. One arm per channel: layout-only reads live through the graft's `.liveState` event,
/// prepaint-only through the ledger's `liveStates`, paint-only through the record's `lives`. **Mutations (three):** that channel's
/// replay removed (`reapply`'s `.liveState` arm, `replayPrepaintLedger`'s `touchLive` loop, `replayPaint`'s `touchLive` loop)
/// reddens its own arm (`isLive` false at once, the entry gone once reaped).
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: [RWPhase.layout, RWPhase.prepaint, RWPhase.paint]) @MainActor
private func aReadOnlyEntryStaysLiveAcrossManyReplays(phase: RWPhase) throws {
    let (window, ids) = try rwWindow(.readOnly, phase: phase)
    var f = FrameWork()
    for _ in 0..<2 { _ = rwDraw(window) }
    let id = try #require(ids.id)
    window.window.testingWriteState(id, 3)   // an input write: the next frames record whole (ledger and graft included)
    for index in 0..<300 {   // fillers: the table is past 256 entries, so unmarked stale entries are reaped
        window.window.testingWriteState(GlobalElementID.child(of: nil, at: index, name: ElementID("rw-filler-\(index)")), index)
    }
    for _ in 0..<5 { f = rwDraw(window) }
    #expect(f.retainedHits == 1 && f.retainedGrafts == 1 && f.retainedPrepaintHits == 1,
            "steady and fully replayed: hits \(f.retainedHits) grafts \(f.retainedGrafts) prepaint hits \(f.retainedPrepaintHits)")
    let version = window.window.testingStateVersion(id)
    #expect(version != 0)
    for _ in 0..<40 { f = rwDraw(window) }
    #expect(f.retainedHits == 1, "still replaying: \(f.retainedHits)")
    #expect(window.window.testingStateVersion(id) == version, "the entry was not reaped and not rewritten")
    #expect(window.window.testingStateIsLive(id), "the entry is live in the last frame")
}

/// The plain `withState` is ineligible, by name, at all three counters, whatever the frame count (`RW-C`: a site is
/// conservative until converted). **Mutation:** the plain write path made to skip its taint reddens `ineligible == 1`.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aPlainWithStateWriteStaysIneligibleByName() throws {
    let (window, _) = try rwWindow(.plainWrite)
    var f = FrameWork()
    for _ in 0..<4 { f = rwDraw(window) }
    #expect(f.retainedHits == 0 && f.retainedIneligible == 1, "hits \(f.retainedHits) ineligible \(f.retainedIneligible)")
    #expect(f.retainedIneligibleReasons["stateWrite"] == 3, "paint, prepaint and graft each: \(f.retainedIneligibleReasons)")
}

// MARK: Test 9 — every ineligible occurrence is counted by its reason

private enum RWChannel: String, CaseIterable, CustomTestStringConvertible {
    case surface, continuousSurface, popover, alert, stateWrite
    var testDescription: String { rawValue }
}

private struct RWChannelProbe: Component, @MainActor Equatable {
    let channel: RWChannel
    let ids: RWIDs
    var content: some ElementGroup {
        switch channel {
        case .surface:
            GPUSurface(redraw: .onDemand, value: 0) { _ in }.frame(width: Pixels(40), height: Pixels(30))
        case .continuousSurface:
            GPUSurface(redraw: .continuous, value: 0) { _ in }.frame(width: Pixels(40), height: Pixels(30))
        case .popover:
            Text("anchor").frame(width: Pixels(60), height: Pixels(20))
                .popover(isPresented: Binding(get: { true }, set: { _ in })) { Text("popover") }
        case .alert:
            Text("anchor").frame(width: Pixels(60), height: Pixels(20))
                .alert("Title", isPresented: Binding(get: { true }, set: { _ in })) { Button("OK") {} }
        case .stateWrite:
            RWLeaf(mode: .plainWrite, ids: ids)
        }
    }
    static func == (l: RWChannelProbe, r: RWChannelProbe) -> Bool { l.channel == r.channel }
}

/// What each channel costs, measured by this lane's first run (`RW-M`): the plain neighbour's hits, the three ineligible counters and
/// the reasons (the funnel's names are the trace's). A surface is refused at paint only (the graft and prepaint audits do not see
/// an `.onDemand` or `.continuous` request); a popover at all three, under three names; an alert only at the graft (its paint
/// replays, hits 2: the presentation is the window's, not the occurrence's).
private struct RWChannelCost { let hits: Int, paint: Int, prepaint: Int, graft: Int, reasons: [String: Int] }
private let rwExpected: [RWChannel: RWChannelCost] = [
    .surface: RWChannelCost(hits: 1, paint: 1, prepaint: 0, graft: 0, reasons: ["surface": 1]),
    .continuousSurface: RWChannelCost(hits: 1, paint: 1, prepaint: 0, graft: 0, reasons: ["surface": 1]),
    .popover: RWChannelCost(hits: 1, paint: 1, prepaint: 1, graft: 1, reasons: ["popover": 1, "presentation": 1, "portal": 1]),
    .alert: RWChannelCost(hits: 2, paint: 0, prepaint: 0, graft: 1, reasons: ["presentation": 1]),
    .stateWrite: RWChannelCost(hits: 1, paint: 1, prepaint: 1, graft: 1, reasons: ["stateWrite": 3]),
]

/// **Test 9** — one arm per channel an occurrence cannot replay: the occurrence is ineligible, a plain neighbour replays (so
/// "ineligible" is not "nothing replays"), and the reasons dictionary names the channel and sums to the three counters.
/// **Mutation:** the funnel recording `"?"` reddens every arm's dictionary.
@Test(.enabled(if: !rsVerifying, verifyingNote), arguments: RWChannel.allCases) @MainActor
private func everyIneligibleOccurrenceIsCountedByItsReason(channel: RWChannel) throws {
    let ids = RWIDs(), neighbour = RWIDs()
    let window = try TestWindow(size: sz(300, 160), textSystem: harnessTextSystem) {
        VStack(spacing: 4) {
            RWCard(mode: .readOnly, ids: neighbour).equatable()
            RWChannelProbe(channel: channel, ids: ids).equatable()
        }
    }
    var f = FrameWork()
    for _ in 0..<4 { f = rwDraw(window) }
    let want = try #require(rwExpected[channel])
    #expect(f.retainedHits == want.hits, "the plain neighbour: hits \(f.retainedHits)")
    #expect(f.retainedIneligible == want.paint && f.retainedPrepaintIneligible == want.prepaint
            && f.retainedGraftIneligible == want.graft,
            "\(channel.rawValue): paint/prepaint/graft \(f.retainedIneligible)/\(f.retainedPrepaintIneligible)/\(f.retainedGraftIneligible)")
    #expect(f.retainedIneligibleReasons == want.reasons, "reasons: \(f.retainedIneligibleReasons)")
    #expect(f.retainedIneligibleReasons.values.reduce(0, +)
            == f.retainedIneligible + f.retainedPrepaintIneligible + f.retainedGraftIneligible)
}

// MARK: Test 15 — the read set holds no strong reference (`IV-R`)

@Observable @MainActor private final class RWModel { var count = 0 }

/// A leaf whose state entry **is** the model (its seed), read in layout, prepaint and paint: a record, ledger or graft record that
/// kept the entry's value (rather than its id) would keep the model alive.
private struct RWModelLeaf: Element {
    let model: RWModel
    var elementID: ElementID? { nil }
    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        _ = pass.readState(id, initial: model)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 20, height: 20)) }.layoutNodeID, ())
    }
    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, pass: inout PrepaintPass) {
        _ = pass.readState(id, initial: model)
    }
    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {
        _ = pass.readState(id, initial: model)
        pass.fill(bounds, color: Hsla(h: 0.2, s: 0.5, l: 0.5, a: 1))
    }
}

private struct RWHolder: Component, @MainActor Equatable {
    let model: RWModel
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("holder \(model.count)").frame(width: Pixels(100), height: Pixels(14))
            RWModelLeaf(model: model)
        }
    }
    static func == (l: RWHolder, r: RWHolder) -> Bool { l.model === r.model }
}

private struct RWWeak {
    weak var model: RWModel?
    weak var testWindow: TestWindow?
    weak var window: Window?
    weak var store: ContentMemoStore?
}

/// **Test 15** — a window closed after retained frames (records, ledgers and graft records holding read sets) is freed with the model
/// held by an entry the read set names. **Mutation:** `noteRead` appending the entry's *value* to a static array (a strong hold on
/// what the read set names) reddens the model arm.
@Test(.enabled(if: !rsVerifying, verifyingNote)) @MainActor
func aRetainedReadSetHoldsNoStrongReference() throws {
    var refs = RWWeak()
    do {
        let model = RWModel()
        let window = try TestWindow(size: sz(300, 100), textSystem: harnessTextSystem) {
            VStack { RWHolder(model: model).equatable() }
        }
        for _ in 0..<5 { window.window.setNeedsRedraw(); window.tick() }
        let f = window.lastFrameWork
        #expect(f.retainedHits == 1, "the occurrence replays, so a record and a ledger exist: \(f.retainedHits)")
        refs = RWWeak(model: model, testWindow: window, window: window.window, store: window.window.testingContentMemos)
        window.close()
    }
    #expect(refs.testWindow == nil, "the TestWindow is freed")
    #expect(refs.window == nil, "the Window is freed")
    #expect(refs.store == nil, "the ContentMemoStore is freed")
    #expect(refs.model == nil, "the model is freed")
}
