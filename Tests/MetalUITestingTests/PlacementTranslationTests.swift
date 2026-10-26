import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-f lane 2 (`RG-E`, `RG-F`, `RG-G`): the placement memo under a shifted origin through a real `Window` (the kernel's pins are
// `MetalUILayoutTests/SubtreePlacementTranslationTests.swift`), the two sides of `movedPrepaintLedger`'s `hitboxClipped` guard, and a shift
// under a moved render effect. Counts and equalities, never time.

private let ptVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

/// The cards of `FSShiftRoot` in a `ScrollView` (ten of them). A scroller proposes no height, so a card's proposal is the same before and
/// after a shift; in a plain `VStack` the stack divides the remaining height among the children left, so **every** shift changes every
/// card's proposal and the key (the FS fixture's 24 cards, `RG-E`): a header that grows 4 points, or an id inserted in front.
@MainActor private func ptShiftFrames(_ kind: FSShift) throws -> [FrameWork] {
    let model = FSShiftModel()
    model.ids = Array(0..<10)
    let options = HeadlessPlatformWindow.Options(scaleFactor: 2, accessibilityClientActive: false)
    let w = try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: 2, options: options,
                           textSystem: { harnessTextSystem() }) {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    if kind == .header { Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(model.header)) }
                    ForEach(model.ids, id: \.self) { i in FSCard(id: i, value: 0).equatable() }
                }
            }.frame(width: Pixels(300), height: Pixels(250))
        }
    }
    w.window.testingRetainedGraft = false
    for _ in 0..<16 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    for step in 0..<3 {
        if kind == .header { model.header += 4 } else { model.ids.insert(100 + step, at: 0) }
        w.window.setNeedsRedraw(); w.tick()
    }
    return w.frameWork
}

/// 1 (`RG-E`) - the cards of a scroller's stack, shifted by a header that grows or an insertion: the marked card subtrees stand at a new
/// origin with an equal signature, proposal and size. At 99b21a1c every one re-placed (`layoutSubtreeHits` 0; figures in the commit
/// message and `RG-E`); translated, the second and third shifted frames restore them (the first has nothing recorded: a root hit covers a
/// steady frame and touches no subtree). Mutation: the translated lookup removed (`lookupPlacementTranslated` returning nil).
@Test(.enabled(if: !rsVerifying, ptVerifyingNote), arguments: [FSShift.header, .insertFront]) @MainActor
func aShiftedFrameRestoresTheCardPlacementsTranslated(kind: FSShift) throws {
    let frames = try ptShiftFrames(kind)
    try #require(frames.count == 3)
    // At 99b21a1c the second and third frames read 0 subtree hits and 140 (header) or 162 and 176 (insertion) memo lookups.
    for f in frames.dropFirst() {
        #expect(f.layoutSubtreeHits >= 9, "card subtrees restored where they moved: \(f.layoutSubtreeHits)")
        #expect(f.layoutMemoHits <= 30, "memo lookups: \(f.layoutMemoHits)")
    }
}

// MARK: hitboxClipped (`RG-F`)

/// A card whose click target sits in a legacy `.clipped()` box and paints nothing itself: the hitbox is cut by a clip pushed **inside** the
/// occurrence, so it is registered at an inner clip depth, and no painted leaf of the inner mask refuses first (`maskStraddlesEntryClip`
/// is the paint record's twin of the guard), so the guard of `movedPrepaintLedger` decides whether it moves.
private struct HCCard: Component, @MainActor Equatable {
    let id: Int
    static func == (l: HCCard, r: HCCard) -> Bool { l.id == r.id }
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("c\(id)").frame(width: Pixels(60), height: Pixels(12))
            Box { Box().onClick {}.frame(width: Pixels(80), height: Pixels(20)) }
                .frame(width: Pixels(100), height: Pixels(18)).clipped()
        }
    }
}

private struct HCRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + side.inputs.offset))
            ForEach(Array(0..<6), id: \.self) { k in HCCard(id: k).equatable() }
        }
    }
}

private struct HCRun {
    var translated = 0, prepaintHits = 0, redos = 0
    var refusals: [String: Int] = [:]
}

/// A window `height` points tall, the header grown by 4 points per step; every step compared with a retention-off window.
@MainActor private func hcRun(height: Float) async throws -> HCRun {
    let pair = try RPPair(size: sz(200, height), scale: 2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { HCRoot(side: side) }
    }
    try pair.compare("warm")
    var run = HCRun()
    for step in 0..<3 {
        pair.on.resetFrameWork()
        for s in [pair.onSide, pair.offSide] { s.inputs.offset += 4 }
        await rsSettle()
        pair.redraw()
        let f = pair.stepWork
        run.translated += f.retainedTranslated; run.prepaintHits += f.retainedPrepaintHits; run.redos += f.retainedRedos
        run.refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        try pair.compare("step \(step)")
    }
    return run
}

/// 9 - every inner-clipped hitbox stays strictly inside the ambient clip before and after the move: the rows replay translated, nothing
/// is refused and the scene and hitbox list equal a retention-off window's. Mutation: the `hitboxClipped` line deleted (this one
/// stays green: it is the separating control of 10).
@Test(.enabled(if: !rsVerifying, ptVerifyingNote)) @MainActor
func anInnerClippedHitboxInsideBothClipsMoves() async throws {
    let run = try await hcRun(height: 400)
    #expect(run.refusals.isEmpty, "nothing refused: \(run.refusals)")
    #expect(run.translated >= 6 * 3, "the six rows translated at every step: \(run.translated)")
    #expect(run.prepaintHits == run.translated, "every translated row replayed its prepaint: \(run.prepaintHits)")
    #expect(run.redos == 0)
}

/// 10 - rows whose clipped hitbox touches or leaves the ambient clip (the window's bottom edge) after the move are refused, run their
/// prepaint and equal a fresh window (the cut is recomputed by the build, not shifted); the rows above the edge still translate.
/// Mutation: the `guard inside(b), inside(moved)` line deleted (the straddling row's cut hitbox is moved, not recomputed: the hitbox
/// list differs from the fresh window's).
@Test(.enabled(if: !rsVerifying, ptVerifyingNote)) @MainActor
func anInnerClippedHitboxTouchingTheAmbientClipRefuses() async throws {
    let run = try await hcRun(height: 100)
    #expect(run.prepaintHits > 0, "the rows below the edge's reach replay their prepaint: \(run.prepaintHits)")
    #expect(run.prepaintHits < run.translated, "the cut rows run it: \(run.prepaintHits) of \(run.translated)")
    #expect(run.redos == 0)
}

/// 11 - the refusal is named: `hitboxClipped` counted, and only that gate refuses. Mutation: as 10.
@Test(.enabled(if: !rsVerifying, ptVerifyingNote)) @MainActor
func theClippedRowsAreRefusedByTheNameHitboxClipped() async throws {
    let run = try await hcRun(height: 100)
    #expect(run.refusals["hitboxClipped", default: 0] > 0, "hitboxClipped counted: \(run.refusals)")
    #expect(Set(run.refusals.keys) == ["hitboxClipped"], "only that gate: \(run.refusals)")
}

// MARK: a shift under a moved render effect (`RG-G`)

private struct EFRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + side.inputs.offset))
            ForEach(Array(0..<6), id: \.self) { k in
                ZStack { FSCard(id: k, value: 0).equatable() }.offset(x: Pixels(0), y: Pixels(side.inputs.offset / 2))
            }
        }
    }
}

/// 12 - an occurrence whose layout origin **and** the render effect above it move in one frame is replayed combined (`FS-O`,
/// `EL-B`; was `aShiftUnderAMovedRenderEffectIsRefusedByName`, which pinned the counted refusal `effectAndLayoutMoved`): the name is
/// never emitted, nothing is redone, the prepaint of the cards replays and the frame equals a retention-off window's at every step.
/// Mutation: the counter line restored (the name is back); the combined branch removed (no prepaint hit).
@Test(.enabled(if: !rsVerifying, ptVerifyingNote)) @MainActor
func aShiftUnderAMovedRenderEffectIsReplayedCombined() async throws {
    let pair = try RPPair(size: sz(200, 400), scale: 2, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { EFRoot(side: side) }
    }
    try pair.compare("warm")
    var refusals: [String: Int] = [:], redos = 0, prepaintHits = 0
    for step in 0..<3 {
        pair.on.resetFrameWork()
        for s in [pair.onSide, pair.offSide] { s.inputs.offset += 4 }
        await rsSettle()
        pair.redraw()
        let f = pair.stepWork
        refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +); redos += f.retainedRedos
        prepaintHits += f.retainedPrepaintHits
        try pair.compare("step \(step)")
    }
    #expect(refusals["effectAndLayoutMoved"] == nil, "the retired name is never emitted: \(refusals)")
    #expect(prepaintHits >= 6 * 3, "the six cards replayed their prepaint at each step: \(prepaintHits), \(refusals)")
    #expect(redos == 0)
}

