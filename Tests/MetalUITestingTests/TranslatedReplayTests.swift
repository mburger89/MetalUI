import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Observation
import Testing

// C14b-2 lane 1, M3 (`RK-G`, `RK-S`): an occurrence under render effects that moved by a translation replays its paint
// and prepaint at the new position. Counts and values, never time. Every differential draws two windows from one
// builder and compares what the frame hands the platform bit for bit.

/// Three occurrences, each in a `ZStack` under an `.offset` that follows the pan, in a clipped frame (`RK-S`).
struct RPPanRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let pan = side.inputs.offset, log = side.log
        ZStack(alignment: .topLeading) {
            ForEach(Array(0..<3), id: \.self) { k in
                ZStack(alignment: .topLeading) { RPCard(title: "P\(k)", shade: k, log: log).equatable() }
                    .offset(x: Pixels(Float(k * 70) + pan), y: Pixels(Float(k * 10) + pan / 2))
            }
        }
        .frame(width: Pixels(300), height: Pixels(130), alignment: .topLeading)
        .clipped()
    }
}

/// The pan values of the script: whole points, a half, a quarter and a third of a point, and back.
let rpPanScript: [Float] = [0, 7, 14, 14.5, 21.25, 21.25 + 1.0 / 3.0, 6, 0]

struct RPScaleArm: CustomStringConvertible, Sendable {
    let scale: Float, accessibility: Bool
    var description: String { "scale \(scale), accessibility \(accessibility)" }
}
let rpScaleArms = [1, 1.5, 2, 3, 4].flatMap { [RPScaleArm(scale: $0, accessibility: false), RPScaleArm(scale: $0, accessibility: true)] }

/// 11 — a pan of three equal occurrences equals a fresh frame at every step, at every scale, with and without an
/// accessibility client (`RK-S`: the recorded leaves are replayed through the live effect scope, so the arithmetic
/// is the fresh arithmetic; the hitbox transforms move by the same amount; an accessibility record's frames are
/// computed boxes, so a ledger holding them is refused and counted). The pan moves by whole points, halves, quarters
/// and thirds, so scale 3 and 1.5 meet the fractions `SB-H` measured as inexact for a final-stream translation.
/// The retaining side must have translated at the steps that move. Mutations: the translation applied to hitboxes only
/// (the scene differs), to paint only (the hitbox transforms differ at a hover), the accessibility refusal removed
/// (the tree's frames differ), the accessibility recomputation removed (`prepaintHits` falls, `AT-A`), the effect-translation relaxation removed from the paint key (`translated == 0`).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: rpScaleArms) @MainActor
func aTranslatedReplayEqualsAFreshFrameAtEveryScale(arm: RPScaleArm) async throws {
    let pair = try RPPair(size: sz(320, 150), scale: arm.scale, warm: 4, accessibility: arm.accessibility, graft: false) { side in
        VStack(spacing: 0) { RPPanRoot(side: side) }
    }
    try pair.compare("warm")
    var translated = 0, prepaintHits = 0, refused = 0, redos = 0
    for (index, pan) in rpPanScript.enumerated() {
        pair.onSide.inputs.offset = pan; pair.offSide.inputs.offset = pan
        await rsSettle()
        pair.redraw()
        let f = try #require(pair.frames.last)
        translated += f.retainedTranslated; prepaintHits += f.retainedPrepaintHits
        refused += f.retainedTranslationRefused; redos += f.retainedRedos
        try pair.compare("pan step \(index) (\(pan))")
        // The pointer: a hover over the translated first card must reach its button through the moved transform.
        if arm.accessibility == false, index == 3 {
            let target = pt(Float(0) + pan + 14, Float(0) + pan / 2 + 40)
            for w in [pair.on, pair.off] { w.hover(at: target) }
            try pair.compare("hover at step \(index)")
            for w in [pair.on, pair.off] { w.hover(at: pt(318, 148)) }
        }
    }
    #expect(translated >= 3 * 5, "the pan's moving steps replay translated: \(translated)")
    #expect(redos == 0, "a pan moves no paint-only ambient: \(redos)")
    // C14-g (`AT-A`): an accessibility ledger translates too, its records recomputed against the current effect.
    #expect(prepaintHits >= 3 * 5, "the prepaint translates, with or without a client: \(prepaintHits)")
    #expect(refused == 0, "\(refused)")
}

/// 12 — a pan of the bracket window's graph by whole points replays every visible node, and one by a fraction
/// replays them too and equals a fresh frame (`RK-S`: no gate on the scale or on whole device pixels is owed — the
/// paint replay is the live scope's arithmetic). The wires change with the pan (their ends moved) and rebuild.
/// Mutations: the relaxation removed (`retainedTranslated == 0`), hitbox transforms left unmoved (the differential's
/// hitbox list differs).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read"), arguments: [Float(4), Float(0.3), Float(2.5)]) @MainActor
func aPanOfTheWholeGraphReplaysEveryNodeAndEqualsAFreshFrame(step: Float) throws {
    let (on, onModel) = try bracketWindow(arm: .value, textSystem: harnessTextSystem)
    let (off, offModel) = try bracketWindow(arm: .value, textSystem: harnessTextSystem)
    off.window.testingRetainedSubtrees = false
    for w in [on, off] { for _ in 0..<4 { w.window.setNeedsRedraw(); w.tick() } }
    for difference in try RPSnapshot(on, accessibility: false).differences(from: RPSnapshot(off, accessibility: false)) {
        Issue.record("before the pan: \(difference)")
    }
    var translated = 0
    for index in 0..<8 {
        onModel.panX -= step; offModel.panX -= step
        on.window.setNeedsRedraw(); off.window.setNeedsRedraw()
        on.tick(); off.tick()
        translated += on.lastFrameWork.retainedTranslated
        let differences = try RPSnapshot(on, accessibility: false).differences(from: RPSnapshot(off, accessibility: false))
        #expect(differences.isEmpty, "after pan step \(index) by \(step): \(differences)")
    }
    #expect(translated >= 8 * 8, "every visible node replays translated at every step: \(translated)")
}

/// A card whose hit regions sit under an effect opened **after** a clip was pushed: that effect's outer clip is the ambient
/// effect's map of the clip, so it moves with the pan and a ledger cannot move its hitboxes by the inverse alone.
struct RPClippedEffectCard: Component, @MainActor Equatable {
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text("clipped").frame(width: Pixels(80), height: Pixels(14))
            Button("go clipped") { log.add("go clipped") }.frame(width: Pixels(60), height: Pixels(18))
        }
        .offset(x: Pixels(2), y: Pixels(1))
        .clipShape(RoundedRectangle(cornerRadius: Pixels(6)))
    }
    static func == (l: RPClippedEffectCard, r: RPClippedEffectCard) -> Bool { l.log === r.log }
}

/// 11b — a hitbox registered under an effect whose outer clip depended on the translation (`RK-S` item 2) is **re-derived from its
/// recorded step chain** (`RL-I`, was refused by name `hitboxes` before C14-h): the walk of the effect's own step from the current
/// ambient gives the outer clip a fresh prepaint registers, so the prepaint replays translated, the paint translates too and the frame,
/// the hitbox list included, equals a fresh frame. Mutation: the walked outer clip replaced by the recorded one in `translatedHitboxes`
/// (the hitbox fingerprints differ at the first pan).
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor
func aHitboxWhoseClipDependedOnTheTranslationIsRecomputedFromItsSteps() async throws {
    let pair = try RPPair(size: sz(320, 150), warm: 4, accessibility: false, graft: false) { side in
        let pan = side.inputs.offset, log = side.log
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) { RPClippedEffectCard(log: log).equatable() }
                    .offset(x: Pixels(10 + pan), y: Pixels(10 + pan / 2))
            }
            .frame(width: Pixels(300), height: Pixels(130), alignment: .topLeading)
            .clipped()
        }
    }
    try pair.compare("warm")
    var refused = 0, translated = 0, hits = 0
    for (index, pan) in [Float(0), 5, 9.5, 20, 3].enumerated() {
        pair.onSide.inputs.offset = pan; pair.offSide.inputs.offset = pan
        await rsSettle()
        pair.redraw()
        refused += pair.frames.last?.retainedTranslationRefused ?? 0
        translated += pair.frames.last?.retainedTranslated ?? 0
        hits += pair.frames.last?.retainedPrepaintHits ?? 0
        try pair.compare("pan \(pan) (step \(index))")
        let at = pt(10 + pan + 20, 10 + pan / 2 + 28)
        for w in [pair.on, pair.off] { w.hover(at: at) }
        try pair.compare("hover at pan \(pan)")
        for w in [pair.on, pair.off] { w.hover(at: pt(318, 148)) }
    }
    print("11b: refused \(refused) translated \(translated) prepaint hits \(hits)")
    #expect(refused == 0, "nothing is refused any more: \(refused)")
    #expect(hits >= 3, "the moving steps replay the prepaint translated: \(hits)")
    #expect(translated >= 3, "the paint translates too: \(translated)")
}
