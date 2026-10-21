import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14-g (`AT-A`..`AT-E`, record 129): an `.equatable()` occurrence under render effects that moved by a translation replays its
// prepaint **with its accessibility records recomputed against the current effect**, so a warm pan with a client reading the
// tree grafts instead of redoing the frame. Counts are `FrameWork` work, never time; every differential draws two windows from
// one builder (one retaining, one with retention off) and compares the published tree and the scene.

private let atVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay and graft counts this test pins are not its to read"

/// A node: eight labelled rows (a hitbox, a focus stop, an accessibility record and a declared node each).
struct ATNode: Component, @MainActor Equatable {
    let k: Int
    var content: some ElementGroup {
        VStack(spacing: 1) {
            ForEach(Array(0..<8), id: \.self) { j in
                Button("n\(k) r\(j)") {}.accessibilityLabel("n\(k)r\(j)").frame(width: Pixels(50), height: Pixels(12))
            }
        }
    }
}

/// A node that opens an effect of its own over its rows (`AT-B`: an emission recorded under more effects than the occurrence began in).
struct ATNestedNode: Component, @MainActor Equatable {
    let k: Int
    var content: some ElementGroup {
        VStack(spacing: 1) {
            ForEach(Array(0..<4), id: \.self) { j in
                Button("m\(k) r\(j)") {}.accessibilityLabel("m\(k)r\(j)").frame(width: Pixels(50), height: Pixels(12))
            }
        }
        .offset(x: Pixels(2), y: Pixels(1))
    }
}

/// Ten nodes in a row, under `.scaleEffect(scale)` then `.offset(pan)`; `inputs.showExtra` raises the factor by a quarter (pin 4).
struct ATRoot: Component {
    let side: RPSide
    let scale: Double
    var clipped = false
    var nested = false
    var content: some ElementGroup {
        let pan = side.inputs.offset
        let factor = side.inputs.showExtra ? scale * 1.25 : scale
        let nested = nested
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(0..<10), id: \.self) { k in
                        if nested { ATNestedNode(k: k).equatable() } else { ATNode(k: k).equatable() }
                    }
                }
            }
            .scaleEffect(factor, anchor: .topLeading)
            .offset(x: Pixels(pan), y: Pixels(pan / 2))
        }
        .frame(width: Pixels(clipped ? 300 : 1100), height: Pixels(clipped ? 120 : 300), alignment: .topLeading)
        .clipped()
    }
}

@MainActor private func atPair(scale: Double, clipped: Bool = false, nested: Bool = false, warm: Int = 12, graft: Bool = true) throws -> RPPair<some Element> {
    try RPPair(size: sz(1200, 320), scale: 2, warm: warm, accessibility: true, graft: graft) { side in
        VStack(spacing: 0) { ATRoot(side: side, scale: scale, clipped: clipped, nested: nested) }
    }
}

@MainActor private func atStep(_ pair: RPPair<some Element>, pan: Float) async {
    pair.onSide.inputs.offset = pan; pair.offSide.inputs.offset = pan
    await rsSettle()
    pair.redraw()
}

/// 1 — a warm pan of ten nodes under a render effect, with an accessibility client, grafts: no redo, no backoff, the build a small
/// fraction of the unretained frame's. **Red at c502f14c**: the ledger's accessibility records refuse the translation
/// (`accessibilityRecords`), the grafted occurrence redoes the frame and backs prepaint replay off. Mutation: restore the
/// `axEmissions.isEmpty` condition in the effect branch.
@Test(.enabled(if: !rsVerifying, atVerifyingNote)) @MainActor
func aPanUnderAnEffectGraftsWithAccessibilityOn() async throws {
    let pair = try atPair(scale: 2)
    try pair.compare("warm")
    var grafts = 0, redos = 0, backoff = 0, reasons: [String: Int] = [:]
    var requests: [Int] = [], baselines: [Int] = []
    for step in 1...6 {
        await atStep(pair, pan: Float(step) * 3)
        let f = try #require(pair.frames.last)
        grafts += f.retainedGrafts; redos += f.retainedRedos; backoff += f.retainedBackoffFrames
        requests.append(f.elementRequests); baselines.append(pair.off.lastFrameWork.elementRequests)
        for (r, n) in f.retainedTranslationRefusedReasons { reasons[r, default: 0] += n }
        try pair.compare("pan step \(step)")
    }
    print("AT pin 1: grafts \(grafts) redos \(redos) backoff \(backoff) requests \(requests) baseline \(baselines) reasons \(reasons)")
    #expect(grafts > 0, "pan frames graft: \(grafts)")
    #expect(redos == 0, "no frame is redone: \(redos)")
    #expect(backoff == 0, "prepaint replay is never backed off: \(backoff)")
    #expect(reasons["accessibilityRecords"] == nil, "\(reasons)")
    for (r, b) in zip(requests, baselines) { #expect(Double(r) <= 0.15 * Double(b), "element requests \(r) of \(b)") }
}

struct ATScaleArm: CustomStringConvertible, Sendable {
    let scale: Double
    var description: String { "scale \(scale)" }
}

/// 2 — after every step of 0.37 points the published tree (nodes, geometry frame and visible frame, order, layer, roots) equals the
/// unretained window's, at scales 1, 2, 0.8 and 1.1 (non-dyadic: 0.8 and 1.1 are inexact in `Float`, so a shifted box differs from
/// a recomputed one by an ulp where scale 2 cannot show it). Mutations: the ledger's frames replayed unrecomputed (every step
/// reddens), the frames shifted by the delta instead of recomputed (the 0.8 and 1.1 arms redden).
@Test(arguments: [1.0, 2.0, 0.8, 1.1].map { ATScaleArm(scale: $0) }) @MainActor
func aPanUnderAnEffectPublishesTheFreshTree(arm: ATScaleArm) async throws {
    let pair = try atPair(scale: arm.scale, warm: 8)
    try pair.compare("warm")
    var grafts = 0, translated = 0
    for step in 1...10 {
        await atStep(pair, pan: Float(step) * 0.37)
        let f = try #require(pair.frames.last)
        grafts += f.retainedGrafts; translated += f.retainedTranslated
        try pair.compare("pan step \(step) at \(arm)")
    }
    if !rsVerifying { #expect(grafts + translated > 0, "the retaining side replayed nothing: the differential proves nothing") }
}

/// 3 — a clip the pan moves rows across: the visible frames are cut again at the new place and the tree equals the unretained one.
/// Mutations: the old `visibleFrame` reused, the `clipped` local dropped.
@Test @MainActor
func aPanThatCrossesTheClipRecomputesTheVisibleFrame() async throws {
    let pair = try atPair(scale: 2, clipped: true, warm: 8)
    try pair.compare("warm")
    var cut = 0
    for step in 1...8 {
        await atStep(pair, pan: -17.3 * Float(step))
        let tree = try pair.on.accessibilityTree
        cut += tree.geometry.values.filter { $0.visibleFrame != $0.frame }.count
        try pair.compare("pan step \(step)")
    }
    #expect(cut > 0, "some row is cut by the clip: the arm must meet a cut visible frame")
}

/// 4 — changing the scale between frames is an **affine** change, not a translation: since C14-i (`RZ-B`) it replays (prepaint and
/// paint) instead of refusing, with no `effectNotTranslation`, and the tree equals the unretained one (it was a refusal by name at
/// c502f14c: **red there**, the count read 0 and the reason did not exist). Mutation: `differsOnlyByEffectAffine` returning false.
@Test(.enabled(if: !rsVerifying, atVerifyingNote)) @MainActor
func aScaleChangeIsAnAffineReplayNotARefusal() async throws {
    let pair = try atPair(scale: 2, warm: 8, graft: false)
    try pair.compare("warm")
    pair.onSide.inputs.showExtra = true; pair.offSide.inputs.showExtra = true
    await rsSettle()
    pair.redraw()
    var refused = 0, replayed = 0
    for f in pair.frames {
        refused += f.retainedTranslationRefusedReasons["effectNotTranslation", default: 0]
        replayed += f.retainedPrepaintHits
    }
    try pair.compare("after the scale change")
    #expect(refused == 0, "a scale change is not refused: \(pair.frames.map(\.retainedTranslationRefusedReasons))")
    #expect(replayed > 0, "the scale change replays the prepaint: \(replayed)")
}

/// 5 — a node that opens an effect of its own over its rows (`AT-G`): its records are re-derived from the recorded steps of that
/// effect against the panned ambient, never refused by an accessibility reason, and the tree equals the unretained one.
/// Mutations: the nested step skipped (the inner frames keep the first pan's offset), the nested step's map dropped.
/// At scale 1 the node's hitboxes move too (an identity linear part), so its prepaint replays; at scale 2 a hitbox registered
/// inside the nested effect is refused by name (`hitboxes`, carried: its inverse is not the ambient's) and the records are still exact.
@Test(.enabled(if: !rsVerifying, atVerifyingNote), arguments: [1.0, 2.0].map { ATScaleArm(scale: $0) }) @MainActor
func anEffectOpenedInsideTheOccurrenceIsRecomputedFromItsSteps(arm: ATScaleArm) async throws {
    let pair = try atPair(scale: arm.scale, nested: true, warm: 8, graft: false)
    try pair.compare("warm")
    var accessibilityRefusals = 0, translated = 0
    for step in 1...4 {
        await atStep(pair, pan: Float(step) * 3.37)
        let f = try #require(pair.frames.last)
        translated += f.retainedPrepaintHits
        for (reason, n) in f.retainedTranslationRefusedReasons where reason.hasPrefix("accessibility") { accessibilityRefusals += n }
        try pair.compare("pan step \(step)")
    }
    #expect(accessibilityRefusals == 0, "no accessibility refusal: \(accessibilityRefusals)")
    if arm.scale == 1 { #expect(translated > 0, "the nested node replayed its prepaint translated: \(translated)") }
}

/// 6 — after a replayed pan step the retained accessibility node of a declared element reports the moved frame and is valid, as an
/// unretained window's. Mutation: skip the `$ax` write in the replay's node loop.
@Test @MainActor
func theAccessibilityNodeRetentionSlotFollowsAReplay() async throws {
    let pair = try atPair(scale: 2, warm: 8)
    for step in 1...4 {
        await atStep(pair, pan: Float(step) * 3.37)
        let onID = try pair.on.element(label: "n3r4").id, offID = try pair.off.element(label: "n3r4").id
        let onElement = try #require(onID.base.base as? GlobalElementID)
        let offElement = try #require(offID.base.base as? GlobalElementID)
        let on = try #require(pair.on.window.testingAXRetainedNode(onElement))
        let off = try #require(pair.off.window.testingAXRetainedNode(offElement))
        #expect(on.frame == off.frame, "step \(step): \(on.frame) vs \(off.frame)")
        #expect(on.isValid && off.isValid)
        let tree = try pair.on.accessibilityTree
        #expect(on.frame == tree.geometry[onID]?.frame)
    }
}

/// 7 — the bracket window's canvas pan with the tree read every frame: no redo on a steady frame. Counters are printed for the record.
@Test(.enabled(if: !rsVerifying, atVerifyingNote)) @MainActor
func theBracketPanGraftsUnderAccessibility() throws {
    let (on, model) = try bracketWindow(arm: .value, textSystem: harnessTextSystem)
    on.window.testingRetainedGraft = true
    for _ in 0..<4 { on.window.setNeedsRedraw(); on.tick(); _ = try on.accessibilityTree }
    var redos = 0, grafts = 0, requests: [Int] = []
    for _ in 0..<8 {
        model.panX -= 4
        on.window.setNeedsRedraw(); on.tick(); _ = try on.accessibilityTree
        let f = on.lastFrameWork
        redos += f.retainedRedos; grafts += f.retainedGrafts; requests.append(f.elementRequests)
    }
    print("AT pin 7 (bracket pan, tree read): grafts \(grafts) redos \(redos) requests \(requests)")
    #expect(redos == 0, "\(redos)")
    #expect(grafts > 0, "the node subtrees graft: \(grafts)")
}
