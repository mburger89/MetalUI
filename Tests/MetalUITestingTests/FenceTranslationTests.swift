import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITestSupport
import MetalUITesting
import Testing

// Record 439 (`FS-AA`): a retained row that holds a horizontal scroller (Alloy's markdown code fences and tables) moves its
// ledger exactly. `Hitbox.moved` carries every field the `XS-E` scroll payload added (it rebuilt the hitbox through `init`
// and dropped them), and `movedHitbox` no longer refuses `hitboxScrolls`. Counts are work, never time.

private let verifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice and presents the second: the counts this test pins are not its to read; the differential runs under it"

/// The scrollers the window's last frame registered that scroll on `axis`, topmost last.
@MainActor private func scrollers(_ w: TestWindow, _ axis: ScrollAxis) -> [Hitbox] {
    w.window.lastHitboxes.filter { $0.scroll == axis }
}

@MainActor private func scrollOffset(_ w: TestWindow, _ id: GlobalElementID) -> Double? {
    w.window.stateTable.peek(id, as: ScrollState.self)?.offset
}

/// The scrollers wider than a button that scroll sideways (a two-axis one reports `.vertical` as its primary slot).
@MainActor private func sideways(_ w: TestWindow) -> [Hitbox] {
    w.window.lastHitboxes.filter { $0.scrollAxes.contains(.horizontal) && $0.bounds.size.width.value > 40 }
}

/// The refusal tally and the redo count of `frames`.
private func tally(_ frames: [FrameWork]) -> (scrolls: Int, redos: Int, requests: Int, translated: Int) {
    var scrolls = 0, redos = 0, requests = 0, translated = 0
    for f in frames {
        scrolls += f.retainedTranslationRefusedReasons["hitboxScrolls"] ?? 0
        redos += f.retainedRedos; requests += f.elementRequests; translated += f.retainedTranslated
    }
    return (scrolls, redos, requests, translated)
}

/// One wheel step of the transcript, the retaining window's frames of it.
@MainActor private func wheelFrames(_ pair: RPPair<some Element>, dy: Float) -> [FrameWork] {
    atWheel(pair, dy: dy)
    return pair.on.frameWork
}

/// **Test 1.** One wheel step moves the fences' and tables' rows: no row refuses `hitboxScrolls`, nothing is redone, the rows
/// replay their ledgers moved (rebased in place, `FS-U`: no ledger is made). On master: `hitboxScrolls` on every row that holds a scroller.
/// Mutation: the refusal restored (`hitboxScrolls` named, rows miss).
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFenceRowMovedByAWheelReplaysItsLedgerMoved() async throws {
    let pair = try atPair()
    let visible = sideways(pair.on).count
    #expect(visible >= 2, "the fixture shows fences and tables: \(visible)")
    let made = PrepaintLedger.madeCount
    let frames = wheelFrames(pair, dy: 24)
    let t = tally(frames)
    var refused: [String: Int] = [:]
    for f in frames { refused.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +) }
    let detail = "refused \(refused), misses \(frames.reduce(0) { $0 + $1.retainedMisses }), prepaint hits \(frames.reduce(0) { $0 + $1.retainedPrepaintHits }), ineligible \(frames.reduce(0) { $0 + $1.retainedPrepaintIneligible })"
    #expect(t.scrolls == 0, "no row refuses hitboxScrolls: \(t)")
    #expect(t.redos == 0, "nothing is redone: \(t)")
    #expect(t.translated >= visible, "every visible fence and table row moved its ledger: \(t), \(visible) scrollers")
    // A moved ledger is rebased in place (`FS-U`); the two made are the rows the step brings into the viewport (measured). A row
    // whose paint record refuses by another name runs its prepaint and makes one: on the portable text system the fences' Copy
    // icon is a Lucide path, which `movedLeaf` does not list (`unlistedKind:path`, 6 on Linux), so those rows are counted too.
    let refusedRows = refused.values.reduce(0, +)
    #expect(PrepaintLedger.madeCount - made <= 2 + refusedRows, "a moved ledger is rebased in place, only a new row makes one: \(PrepaintLedger.madeCount - made); \(detail)")
    try pair.compare("a wheel step")
}

enum FenceArm: CaseIterable, CustomTestStringConvertible {
    case proposal, legacy, twoAxis, rightToLeft
    var testDescription: String { "\(self)" }
}

private struct FTRow: Component, @MainActor Equatable {
    let id: Int
    let arm: FenceArm
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 4) {
            Text("row \(id)").frame(height: Pixels(18))
            switch arm {
            case .proposal, .rightToLeft:
                ProposalScrollView(.horizontal) { Box().frame(width: Pixels(700), height: Pixels(30)).background(.accent) }
                    .frame(height: Pixels(30))
            case .legacy:
                ScrollView(.horizontal) { Box().frame(width: Pixels(700), height: Pixels(30)).background(.accent) }
                    .frame(height: Pixels(30))
            case .twoAxis:
                ProposalScrollView([.horizontal, .vertical]) { Box().frame(width: Pixels(700), height: Pixels(70)).background(.accent) }
                    .frame(height: Pixels(30))
            }
        }
    }
}

private struct FTRoot: Component {
    let arm: FenceArm
    var content: some ElementGroup {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                ForEach(Array(0..<30), id: \.self) { FTRow(id: $0, arm: arm).equatable() }
            }.padding(g49Inset)
        }
        .defaultScrollAnchor(.bottom)
        .environment(\.layoutDirection, arm == .rightToLeft ? LayoutDirection.rightToLeft : LayoutDirection.leftToRight)
    }
}

/// **Test 2.** A scroller's hitbox, moved with its row, equals the one a retention-off window registers: every field, the `XS-E`
/// payload included (`fingerprint`). Explicit where the arm fixes it. Mutations: `moved` back to the `init` body (the payload is
/// dropped: `scrollTakes` empty), `scrollRoom` alone dropped.
@Test(arguments: FenceArm.allCases) @MainActor func aMovedScrollerHitboxEqualsAFreshOne(arm: FenceArm) async throws {
    let pair = try RPPair(size: sz(420, 400), scale: 2, warm: 6, accessibility: false) { _ in VStack(spacing: 0) { FTRoot(arm: arm) } }
    for step in 0..<6 {
        atWheel(pair, dy: step.isMultiple(of: 2) ? 16 : -8)
        try pair.compare("step \(step)")
    }
    let on = sideways(pair.on), off = sideways(pair.off)
    #expect(!on.isEmpty && on.map(\.fingerprint) == off.map(\.fingerprint))
    if !rsVerifying { #expect(pair.work.retainedTranslated > 0, "the rows moved their ledgers: \(pair.work.retainedTranslated)") }
    let probe = try #require(on.first)
    switch arm {
    case .proposal, .legacy:
        #expect(probe.scrollTakes == [.horizontal] && probe.scrollRoom.contains(.increaseX) && !probe.scrollMirrored, "\(probe.fingerprint)")
    case .twoAxis:
        #expect(probe.scrollAxes == [.horizontal, .vertical], "\(probe.fingerprint)")
    case .rightToLeft:
        #expect(probe.scrollMirrored, "\(probe.fingerprint)")
    }
}

/// **Test 3.** After the transcript moved, a horizontal wheel at the fence's new centre moves the fence in both windows alike and
/// leaves the transcript where it was: the moved hitbox still takes the wheel it takes (`scrollTakes`, `scrollRoom`) and passes the rest.
/// Mutations: `moved` back to the `init` body (the wheel passes through the fence to the transcript), `unclipped` not moved.
@Test @MainActor func aWheelOverAMovedFenceScrollsTheFence() async throws {
    let pair = try atPair()
    _ = wheelFrames(pair, dy: 24)
    _ = wheelFrames(pair, dy: 24)
    let transcript = try #require(scrollers(pair.on, .vertical).first)
    let before = scrollOffset(pair.on, transcript.id)
    let id = try #require(atFenceWheel(pair, dx: -30))
    #expect(scrollOffset(pair.on, id) == scrollOffset(pair.off, id) && (scrollOffset(pair.on, id) ?? 0) != 0,
            "the fence scrolled, alike in both windows: \(String(describing: scrollOffset(pair.on, id))) / \(String(describing: scrollOffset(pair.off, id)))")
    #expect(scrollOffset(pair.on, transcript.id) == before && scrollOffset(pair.off, transcript.id) == before, "the transcript did not")
    try pair.compare("a fence wheel")
}

/// **Test 4.** A fence's own horizontal scroll still makes its row miss (its offset is in `versions`, the trace names it) and paints
/// at the new offset, equal to the fresh window's.
@Test(.enabled(if: !rsVerifying, verifyNote)) @MainActor func aFenceRowsOwnHorizontalScrollStillMisses() async throws {
    let pair = try atPair()
    _ = wheelFrames(pair, dy: 24)
    var lines: [String] = []
    RetainedTrace.sink = { lines.append($0) }
    defer { RetainedTrace.sink = nil }
    let id = try #require(atFenceWheel(pair, dx: -30))
    RetainedTrace.sink = nil
    #expect(lines.contains { $0.contains("versions") }, "a row missed on its versions: \(lines.prefix(6))")
    #expect((scrollOffset(pair.on, id) ?? 0) != 0 && scrollOffset(pair.on, id) == scrollOffset(pair.off, id))
    try pair.compare("the fence's own scroll")
    _ = wheelFrames(pair, dy: 24)
    try pair.compare("then a transcript step")
}

/// **Test 5.** A fence cut by the viewport's top edge moves its hitbox exactly: its cut is recomputed from the uncut rect moved. The
/// transcript is walked until a scroller is cut, and every step equals the fresh window. Redos are not asserted: a paint refusal
/// at the edge is `FS-Z`'s. Mutation: `unclipped` not moved (the cut is computed from the old rect).
@Test @MainActor func aFenceCutByTheViewportEdgeMovesItsHitboxExactly() async throws {
    let pair = try atPair()
    var cut = 0
    for step in 0..<40 {
        let frames = wheelFrames(pair, dy: step < 20 ? 8 : -8)
        if !rsVerifying { #expect(tally(frames).scrolls == 0, "step \(step): hitboxScrolls") }
        cut += sideways(pair.on).filter { $0.unclipped != nil && $0.unclipped != $0.bounds }.count
        try pair.compare("step \(step)")
    }
    #expect(cut > 0, "a scroller was cut by the viewport edge at some step")
}

/// Measured on master `9aec1177` at step 0, the retaining window's redos over 20 deltas: graft off 0 (the 61 `hitboxScrolls`
/// refusals were misses), graft on 2.
private let masterStreamRedos = [false: 0, true: 2]

/// **Test 6.** A streamed reply with fences and a table costs no scroller refusal at any step, and no more redos than master's.
/// Mutation: the refusal restored.
@Test(.enabled(if: !rsVerifying, verifyNote), arguments: [false, true]) @MainActor func aStreamedReplyWithFencesAndATableCostsNoScrollerRedo(graft: Bool) async throws {
    let pair = try atPair(graft: graft)
    var total = (scrolls: 0, redos: 0, requests: 0, translated: 0)
    for step in 0..<20 {
        let t = tally(await atStream(pair))
        #expect(t.scrolls == 0, "step \(step): hitboxScrolls \(t.scrolls)")
        total.redos += t.redos; total.requests += t.requests; total.translated += t.translated
    }
    #expect(total.redos <= masterStreamRedos[graft] ?? 0, "redos \(total.redos) against master's \(masterStreamRedos[graft] ?? 0)")
    try pair.compare("20 deltas")
}

/// **Test 7 (shared with the focus work).** The transcript equals a fresh window at every step: 20 stream deltas, 10 wheel steps
/// and two horizontal fence wheels, composer focused or not, grafts on or off. Runs under `METALUI_VERIFY_RETAINED=1`, which
/// builds every replay twice and traps on a hitbox `moved` cannot reproduce.
@Test(arguments: [false, true], [false, true]) @MainActor func theAlloyTranscriptEqualsAFreshWindowAtEveryStep(focused: Bool, graft: Bool) async throws {
    let pair = try atPair(focused: focused, graft: graft)
    if focused { #expect(pair.on.window.focusedElement != nil && pair.off.window.focusedElement != nil, "the composer is focused") }
    for step in 0..<20 {
        _ = await atStream(pair)
        try pair.compare("stream \(step)")
    }
    for step in 0..<10 {
        atWheel(pair, dy: step < 5 ? 24 : -24)
        try pair.compare("wheel \(step)")
        if step == 3 || step == 7 {
            atFenceWheel(pair, dx: -30)
            try pair.compare("fence wheel after \(step)")
        }
    }
    if focused { #expect(pair.on.window.focusedElement == pair.off.window.focusedElement) }
}

#if canImport(Darwin)   // `countAllocations` counts Darwin's malloc zones only
/// Records the fixture's counts for the record (`FS-AA`): printed, never asserted.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_PRINT_FENCE_BASELINES"] == "1"), arguments: [false, true], [false, true])
@MainActor func printTheFenceBaselines(focused: Bool, graft: Bool) async throws {
    rpRedoBackoff = false; defer { rpRedoBackoff = true }
    let pair = try atPair(focused: focused, graft: graft)
    var s = FrameWork()
    var allocations = 0
    for _ in 0..<20 {
        pair.onSide.inputs.offset += 1; pair.offSide.inputs.offset += 1
        pair.on.resetFrameWork()
        await rsSettle()
        allocations += countAllocations { pair.redraw() } ?? 0
        for f in pair.on.frameWork { s += f }
    }
    var w = FrameWork()
    var wheelAllocations = 0
    for i in 0..<10 {
        pair.on.resetFrameWork()
        wheelAllocations += countAllocations { atWheel(pair, dy: i.isMultiple(of: 2) ? -24 : 24) } ?? 0
        for f in pair.on.frameWork { w += f }
    }
    print("BASE focused=\(focused) graft=\(graft) stream: hitboxScrolls=\(s.retainedTranslationRefusedReasons["hitboxScrolls"] ?? 0) redos=\(s.retainedRedos) requests=\(s.elementRequests) allocations=\(allocations) translated=\(s.retainedTranslated) misses=\(s.retainedMisses)")
    print("BASE focused=\(focused) graft=\(graft) wheel: hitboxScrolls=\(w.retainedTranslationRefusedReasons["hitboxScrolls"] ?? 0) redos=\(w.retainedRedos) requests=\(w.elementRequests) allocations=\(wheelAllocations) translated=\(w.retainedTranslated) misses=\(w.retainedMisses)")
}
#endif
