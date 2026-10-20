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
