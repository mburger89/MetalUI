import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// FS-O lane B (`EL-B`..`EL-H`; record 157): an `.equatable()` occurrence whose layout origin moved **and** whose enclosing render
// effect changed in one frame replays its **prepaint** too: hitboxes, accessibility records, geometry notes and element bounds are
// the ledger's, the whole-device-pixel delta added in the occurrence's own space first and the effect now in force applied second,
// so the frame equals a retention-off window's (`RPPair.compare`: scene, accessibility tree, hitbox fingerprints, tallies, Tab
// order, element bounds, registrations) and the six cards cost no element prepaint. Counts are `FrameWork` work, never time.
//
// **Red at 6d628eca** (lane A's head, the prepaint still the counted refusal): see each test's header; `docs/probes/effect-layout-moved/
// trace.sh` prints the combined frame's counters.

private let elVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the replay counts this test pins are not its to read"

/// The window points a click grid visits: over the zoomed card column, a step finer than a button.
private func elGrid() -> [Point<Pixels>] {
    var points: [Point<Pixels>] = []
    for y in stride(from: Float(8), to: 230, by: 9) { for x in stride(from: Float(8), to: 250, by: 11) { points.append(pt(x, y)) } }
    return points
}

/// Clicks every grid point on both windows and compares the logs, scenes and hitboxes; the pointer then leaves, so the next
/// combined step meets no pointer inside a ledger.
@MainActor private func elClickGrid(_ pair: RPPair<some Element>, _ label: String) throws {
    for point in elGrid() { for w in [pair.on, pair.off] { w.click(at: point) } }
    try pair.compare("click grid \(label)")
    for w in [pair.on, pair.off] { w.exitPointer() }
}

/// T5 - a combined step re-derives every hitbox: at display scales 2 and 3 the six cards replay their prepaint (`retainedPrepaintHits`
/// rises by six, nothing is refused), the frame equals the retention-off window's (the whole hitbox list in order), and a click at
/// every point of a grid fires the same buttons on both windows (a click at a card's new place fires it, at the old one does not).
/// **Red at 6d628eca**: `retainedPrepaintHits` 0 (the prepaint runs, `effectAndLayoutMoved` counted by the old branch).
/// Mutation M-effect: the recorded transform kept (the current-inverse rewrite skipped): the clicks land on the stale spot.
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: [Float(2), 3]) @MainActor
func aCombinedMoveReDerivesEveryHitbox(display: Float) async throws {
    let pair = try elPair(scale: display)
    try pair.compare("warm")
    var hits = 0
    for (step, (header, zoom)) in [(4, Float(1.25)), (8, 1.5)].enumerated() {
        await elStep(pair, header: header, zoom: zoom)
        let f = try #require(pair.frames.last)
        hits += f.retainedPrepaintHits
        #expect(f.retainedPrepaintHits >= 6, "step \(step): prepaint replayed \(f.retainedPrepaintHits), refused \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedTranslationRefusedReasons.isEmpty, "step \(step): \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedRedos == 0)
        try pair.compare("combined step \(step)")
        try elClickGrid(pair, "step \(step)")
    }
    #expect(!pair.onSide.log.entries.isEmpty, "the grid reached a button")
    #expect(hits >= 12)
}

/// T5b - the delta is applied in the occurrence's own space first and the effect second: at zooms 1.25, 1.5 and 2 (a delta under a
/// scale `s` is `s * delta` in the window) every probe point of the grid picks the same button as the retention-off window, over
/// three steps. Mutation M-order (hitboxes): the delta added to `transform.inverse` instead of `bounds` (the hit lands `delta` off
/// in the window, wrong at every scale but 1).
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: [Float(1.25), 1.5, 2]) @MainActor
func aCombinedMoveAppliesTheDeltaInLocalSpaceFirst(zoom: Float) async throws {
    let pair = try elPair()
    try pair.compare("warm")
    for step in 1...3 {
        await elStep(pair, header: 4 * step, zoom: zoom * (1 + 0.25 * Float(step)))
        let f = try #require(pair.frames.last)
        #expect(f.retainedPrepaintHits >= 6, "step \(step): \(f.retainedPrepaintHits), \(f.retainedTranslationRefusedReasons)")
        try pair.compare("step \(step) at \(zoom)")
        try elClickGrid(pair, "step \(step) at \(zoom)")
    }
    #expect(!pair.onSide.log.entries.isEmpty)
}

/// T6 - a combined step grafts and costs no redo: with the graft on, the six cards' element requests and prepaints fall from the
/// full frame's to a handful, `retainedGrafts` rises, nothing is redone, and the frame equals the retention-off window's.
/// **Red at 6d628eca**: grafts 0, requests and prepaints at the full count. Mutation M-graft: the graft site refuses a combined key.
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func aCombinedMoveGraftsAndCostsNoRedo() async throws {
    let pair = try elPair(graft: true)
    try pair.compare("warm")
    pair.on.resetFrameWork()
    var lines: [String] = []
    for (step, (header, zoom)) in [(4, Float(1.25)), (8, 1.5), (12, 1.75)].enumerated() {
        await elStep(pair, header: header, zoom: zoom)
        let f = try #require(pair.frames.last)
        lines.append("T6 step \(step): requests \(f.elementRequests) prepaints \(f.elementPrepaints) grafts \(f.retainedGrafts) prepaintHits \(f.retainedPrepaintHits) translated \(f.retainedTranslated) redos \(f.retainedRedos) refused \(f.retainedTranslationRefusedReasons) graftIneligible \(f.retainedGraftIneligible)")
        #expect(f.retainedGrafts >= 6, "step \(step): grafts \(f.retainedGrafts), refused \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedRedos == 0)
        #expect(f.elementRequests < 40, "step \(step): element requests \(f.elementRequests)")
        #expect(f.elementPrepaints < 40, "step \(step): element prepaints \(f.elementPrepaints)")
        try pair.compare("grafted combined step \(step)")
    }
    print(lines.joined(separator: "\n"))
}

/// T7 - with an accessibility client a combined step recomputes every record: the accessibility tree equals the retention-off
/// window's at the step, at the two settle frames after it (the rebased ledger holds the moved locals, `EL-G`) and at the next
/// combined step; no record is unrecorded.
/// **Red at 6d628eca**: the prepaint runs. Mutation M-ax: `shiftedLocals` skipped (the frames sit at the old position).
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: [Float(1), 2]) @MainActor
func aCombinedMoveRecomputesAccessibility(display: Float) async throws {
    let pair = try elPair(scale: display, accessibility: true)
    try pair.compare("warm")
    for (step, (header, zoom)) in [(4, Float(1.25)), (8, 1.5)].enumerated() {
        await elStep(pair, header: header, zoom: zoom)
        let f = try #require(pair.frames.last)
        #expect(f.retainedPrepaintHits >= 6, "step \(step): \(f.retainedPrepaintHits), \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedTranslationRefusedReasons["accessibilityUnrecorded"] == nil, "\(f.retainedTranslationRefusedReasons)")
        try pair.compare("combined step \(step)")
        for settle in 0..<2 {
            pair.redraw()
            try pair.compare("settle \(settle) after step \(step)")
            #expect(try #require(pair.frames.last).retainedPrepaintHits >= 6, "settle \(settle): an exact hit")
        }
    }
}

/// T8 - a geometry note on a card's global frame is made again at the new position and the current effect: the observer's logged
/// value equals the retention-off window's at every step, the prepaint replays, and a note holding a named space refuses
/// `geometryNamedSpace` (and the frame still equals).
/// **Red at 6d628eca**: the prepaint runs (no refusal named). Mutation M-geom: the `moved` shift skipped in the remade note.
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func aCombinedMoveRemakesGeometryNotes() async throws {
    let pair = try elPair(extra: .geometry)
    try pair.compare("warm")
    for (step, (header, zoom)) in [(4, Float(1.25)), (8, 1.5), (12, 1.75)].enumerated() {
        await elStep(pair, header: header, zoom: zoom)
        let f = try #require(pair.frames.last)
        #expect(f.retainedPrepaintHits >= 6, "step \(step): \(f.retainedPrepaintHits), \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedTranslationRefusedReasons["geometryNamedSpace"] == nil)
        try pair.compare("geometry step \(step)")
    }
    #expect(pair.onSide.log.entries.contains { $0.hasPrefix("G0:") }, "the notes were delivered: \(pair.onSide.log.entries.count)")
    let named = try elPair(extra: .namedSpace)
    try named.compare("warm named")
    await elStep(named, header: 4, zoom: 1.25)
    let f = try #require(named.frames.last)
    try named.compare("named step")
    #expect(f.retainedTranslationRefusedReasons["geometryNamedSpace", default: 0] > 0, "\(f.retainedTranslationRefusedReasons)")
    #expect(f.retainedRedos == 0)
}

/// T10 - what the combined arm cannot carry is refused by the name of its own gate, the frame equals the retention-off window's and
/// nothing is redone: a popover declarer (`presentationAnchor`), a context menu (`contextMenus`), a hit-only box inside an effect
/// the card opens (`effectAndLayoutInner`: no primitive passes the scope, so the paint moves and only the prepaint can name it) and
/// a named-space note (`geometryNamedSpace`). A pointer inside a card (hover) is read against the moved hitboxes: equal.
/// Mutation M-inner: the inner chain let through (the hit lands unmoved).
struct ELPrepaintRefusalArm: CustomStringConvertible, Sendable {
    let extra: ELExtra, reason: String
    var description: String { "\(extra) \(reason)" }
    static let all: [ELPrepaintRefusalArm] = [
        ELPrepaintRefusalArm(extra: .popover, reason: "presentationAnchor"),
        ELPrepaintRefusalArm(extra: .menu, reason: "contextMenus"),
        ELPrepaintRefusalArm(extra: .innerHit, reason: "effectAndLayoutInner"),
        ELPrepaintRefusalArm(extra: .namedSpace, reason: "geometryNamedSpace"),
    ]
}

@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: ELPrepaintRefusalArm.all) @MainActor
func aCombinedMoveRefusesWhatItCannotCarryByName(arm: ELPrepaintRefusalArm) async throws {
    let pair = try elPair(extra: arm.extra)
    try pair.compare("warm")
    await elStep(pair, header: 4, zoom: 1.25)
    let f = try #require(pair.frames.last)
    try pair.compare("step at \(arm)")
    #expect(f.retainedTranslationRefusedReasons[arm.reason, default: 0] > 0, "\(arm.reason) counted: \(f.retainedTranslationRefusedReasons)")
    #expect(f.retainedTranslationRefusedReasons["effectAndLayoutMoved"] == nil)
    #expect(f.retainedRedos == 0)
    try elClickGrid(pair, "\(arm)")
}

@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func aPointerInsideACardIsReadAgainstTheMovedHitboxes() async throws {
    let pair = try elPair()
    try pair.compare("warm")
    for w in [pair.on, pair.off] { w.hover(at: pt(60, 40)) }
    pair.redraw()
    try pair.compare("hovering")
    await elStep(pair, header: 4, zoom: 1.25)
    try pair.compare("hovered combined step")
    await elStep(pair, header: 8, zoom: 1.5)
    try pair.compare("hovered second step")
    #expect(try #require(pair.frames.last).retainedRedos == 0)
}

/// T11 - the two arms the combined one is built on are unchanged: a header step alone (the effect equal) still names
/// `accessibilityUnderEffect` (or `hitboxUnderEffect`) for the effect-made records (`EL-I`) and a zoom step alone (rects equal) replays prepaint as before; both
/// equal the retention-off window. Mutation M-delegate: the new relation not delegating (accepting equal-effect keys itself).
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func theLayoutOnlyAndEffectOnlyArmsAreUnchanged() async throws {
    let pair = try elPair()
    try pair.compare("warm")
    await elStep(pair, header: 4)
    var f = try #require(pair.frames.last)
    try pair.compare("header only")
    // The accessibility records of the cards are checked first (an effect-made record), the hitbox rule is the same (`EL-I`).
    let kept = ["hitboxUnderEffect", "accessibilityUnderEffect"].reduce(0) { $0 + f.retainedTranslationRefusedReasons[$1, default: 0] }
    #expect(kept > 0, "\(f.retainedTranslationRefusedReasons)")
    #expect(f.retainedPrepaintHits == 0, "the layout arm still refuses a hitbox under an effect: \(f.retainedPrepaintHits)")
    await elStep(pair, zoom: 1.25)
    f = try #require(pair.frames.last)
    try pair.compare("zoom only")
    #expect(f.retainedPrepaintHits >= 6, "the effect arm replays: \(f.retainedPrepaintHits), \(f.retainedTranslationRefusedReasons)")
}

/// T13 - the retired umbrella name is never emitted: across a script of combined, layout-only, effect-only and refused steps of the
/// fixture's variants the dictionary never holds `effectAndLayoutMoved`.
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: ELExtra.allCases) @MainActor
func theRetiredEffectAndLayoutMovedNameIsNeverEmitted(extra: ELExtra) async throws {
    let pair = try elPair(extra: extra)
    try pair.compare("warm")
    var seen: [String: Int] = [:]
    for (header, zoom) in [(4, Float(1.25)), (8, 1.25), (8, 1.5), (12, 1.5), (16, 1.75)] {
        await elStep(pair, header: header, zoom: zoom)
        for (r, n) in try #require(pair.frames.last).retainedTranslationRefusedReasons { seen[r, default: 0] += n }
        try pair.compare("\(extra) \(header) \(zoom)")
    }
    #expect(seen["effectAndLayoutMoved"] == nil, "\(extra): \(seen)")
}
