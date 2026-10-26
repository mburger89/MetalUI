import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// FS-O lane A (`EL-B`, `EL-C`, `EL-G`; record 157): an `.equatable()` occurrence whose layout origin moved **and** whose enclosing
// render effect changed in the same frame replays its **paint** (the record's leaves moved by the whole-device-pixel delta in the
// occurrence's own space, then the live effect scopes applied). Prepaint still runs in these frames (lane B). Every differential
// draws two windows from one builder (retaining, and retention off) and compares scene and logs; counts are `FrameWork` work.
//
// **Red at aad9faf4** (measured before any source change; `docs/probes/effect-layout-moved/trace.sh` prints the line): T1 reads
// `translated 0 hits 0 paints 98 skipped 0` at every combined step; T2 (3 arms), T4, T9 (8 arms) and the fractional and flattening
// arms of T3 fail on their counts; the pixel comparison against the retention-off window passes at the baseline (a miss is exact).
// The two inner-scope arms of T3 and T3b are green on arrival: the prepaint already asks the record's paint translation at the
// layout shift alone (`recordShiftAtPrepaint`) and counts its `innerScope` refusal.

private let elVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

/// T1 - six cards under a zooming effect, the header above them growing 4 points: every combined step replays the six paints
/// (`retainedTranslated` rises by six), the six cards paint nothing, and the frame equals the retention-off window's.
/// **Red at aad9faf4**: `retainedTranslated` 0 and `elementPaints` at the full count at every step.
/// Mutation M-delta: the delta add dropped in the combined case (the record replays unmoved: pixels differ).
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func aHeaderGrowingWhileAPanelSetZoomsReplaysItsPaint() async throws {
    let pair = try elPair()
    try pair.compare("warm")
    var lines: [String] = []
    for (step, (header, zoom)) in [(4, Float(1.1)), (8, 1.2), (12, 1.3)].enumerated() {
        await elStep(pair, header: header, zoom: zoom)
        let f = try #require(pair.frames.last)
        lines.append("T1 step \(step): translated \(f.retainedTranslated) hits \(f.retainedHits) paints \(f.elementPaints) skipped \(f.retainedSkippedPaints) refused \(f.retainedTranslationRefusedReasons)")
        try pair.compare("combined step \(step)")
        #expect(f.retainedTranslated >= 6, "the six cards' paints translated: \(f.retainedTranslated), \(f.retainedTranslationRefusedReasons)")
        #expect(f.retainedSkippedPaints > 0, "paint work skipped: \(f.retainedSkippedPaints)")
        #expect(f.retainedRedos == 0)
    }
    print(lines.joined(separator: "\n"))
}

/// T2 - the delta is added before the effect, not after: at scales 1.25, 1.5 and 2 (a delta under a scale `s` is `s * delta` in the
/// window) the combined frame equals the retention-off window's bit for bit. A scale of 1 cannot separate the order (the effect then
/// does not change, which is the layout arm), so the arms start above it.
/// **Red at aad9faf4**: nothing translates (the count assertion). Mutation M-order: the delta added to the post-effect scene.
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: [Float(1.25), 1.5, 2])  @MainActor
func aCombinedPaintMovesBeforeTheEffectNotAfter(zoom: Float) async throws {
    let pair = try elPair()
    try pair.compare("warm")
    await elStep(pair, header: 4, zoom: zoom)
    let f = try #require(pair.frames.last)
    try pair.compare("combined at \(zoom)")
    #expect(f.retainedTranslated >= 6, "translated \(f.retainedTranslated): \(f.retainedTranslationRefusedReasons)")
    await elStep(pair, header: 8, zoom: zoom * 1.25)
    try pair.compare("second combined at \(zoom)")
    #expect(try #require(pair.frames.last).retainedTranslated >= 6)
}

/// T3 - what the combined paint cannot carry is refused by the name of its own gate and the frame still equals the retention-off
/// window's: a fractional header step (1 point at display scale 1.5, `fractionalTranslation`), a card that opens an effect of its own (`innerScope`), a card that
/// opens a shadow (`innerScope`), an effect whose flattening class changes (`effectScopeChanged`/`effectFlatteningChanged`), a clip that moves with the
/// effect's frame (no relation: uncounted, equal). Never the retired umbrella name `effectAndLayoutMoved` for an affine change.
/// **Red at aad9faf4**: the named arms are silent (no refusal counted at all). Mutation M-name: the umbrella name counted instead.
struct ELRefusalArm: CustomStringConvertible, Sendable {
    let extra: ELExtra, display: Float, header: Int
    /// The names the gate may carry: the paint names a flattening crossing `effectScopeChanged` (the scope's vector differs in
    /// length), the prepaint of lane B names it `effectFlatteningChanged` first and the paint then leaves it to that count.
    let reasons: [String]
    var description: String { "\(extra) \(reasons.first ?? "-")" }
    static let all: [ELRefusalArm] = [
        ELRefusalArm(extra: .none, display: 1.5, header: 1, reasons: ["fractionalTranslation"]),
        ELRefusalArm(extra: .innerOffset, display: 2, header: 4, reasons: ["innerScope"]),
        ELRefusalArm(extra: .shadowInside, display: 2, header: 4, reasons: ["innerScope"]),
        ELRefusalArm(extra: .flatten, display: 2, header: 4, reasons: ["effectScopeChanged", "effectFlatteningChanged"]),
    ]
}

@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: ELRefusalArm.all) @MainActor
func aCombinedPaintRefusalKeepsItsName(arm: ELRefusalArm) async throws {
    let pair = try elPair(extra: arm.extra, scale: arm.display)
    try pair.compare("warm")
    // One combined step: the fractional arm moves the header by 1 point (1.5 device pixels at display scale 1.5, as `FS-M`'s own
    // pin) and the flattening arm crosses its class at 1.2, so the named gate is the first thing the step meets.
    await elStep(pair, header: arm.header, zoom: 1.2)
    let f = try #require(pair.frames.last)
    let refusals = f.retainedTranslationRefusedReasons, translated = f.retainedTranslated
    try pair.compare("step at \(arm)")
    #expect(refusals["effectAndLayoutMoved"] == nil, "the umbrella name is not the refusal: \(refusals)")
    #expect(arm.reasons.contains { refusals[$0, default: 0] > 0 }, "one of \(arm.reasons) is counted: \(refusals)")
    #expect(translated == 0, "nothing is replayed through a refused gate: \(translated), \(refusals)")
}

/// T3b - a clip that moves with the effect's frame is no relation at all (the ambient clip is part of the key): equal, uncounted.
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func aClipThatMovesWithTheHeaderIsNoRelation() async throws {
    let pair = try elPair(extra: .clipped)
    try pair.compare("warm")
    await elStep(pair, header: 4, zoom: 1.2)
    try pair.compare("clipped step")
    #expect(try #require(pair.frames.last).retainedTranslated == 0)
}

/// T4 - the record is made over at the new position with the whole new key: the frame after a combined step, with nothing moved,
/// is an exact hit (no translation, the cards paint nothing), and the next combined step translates again.
/// **Red at aad9faf4**: the first combined step translates nothing. Mutation M-rebase: `old.key = key` skipped (the settle frame
/// translates again, or replays at the wrong place).
@Test(.enabled(if: !rsVerifying, elVerifyingNote)) @MainActor
func theCombinedRecordIsRebasedAndTheNextFrameIsAnExactHit() async throws {
    let pair = try elPair()
    try pair.compare("warm")
    await elStep(pair, header: 4, zoom: 1.25)
    #expect(try #require(pair.frames.last).retainedTranslated >= 6)
    try pair.compare("combined")
    for settle in 0..<2 {
        pair.redraw()
        let f = try #require(pair.frames.last)
        #expect(f.retainedTranslated == 0, "settle \(settle): translated again \(f.retainedTranslated)")
        #expect(f.retainedHits >= 6, "settle \(settle): the six cards hit \(f.retainedHits)")
        try pair.compare("settle \(settle)")
    }
    await elStep(pair, header: 8, zoom: 1.5)
    #expect(try #require(pair.frames.last).retainedTranslated >= 6)
    try pair.compare("second combined")
}

/// T9 - a combined frame equals a fresh one at every display scale (1, 1.5, 2, 3), over twelve steps of header and zoom, with a
/// rotation joining the zoom in one arm. Mutations M-delta, M-order and M-effect-paint (the shifted record replayed through the
/// effect numbers it was made with: the live re-entry skipped) redden it at every zoom step.
@Test(.enabled(if: !rsVerifying, elVerifyingNote), arguments: [Float(1), 1.5, 2, 3], [ELExtra.none, .rotate]) @MainActor
func aCombinedFrameEqualsAFreshOneAtEveryScale(display: Float, extra: ELExtra) async throws {
    let pair = try elPair(extra: extra, scale: display)
    try pair.compare("warm")
    if extra == .rotate {
        // The first real rotation is a class change (an identity rotation flattens): re-recorded, the steps after it are affine.
        await elStep(pair, zoom: 1.05)
        for _ in 0..<4 { pair.redraw() }
    }
    var translated = 0, refused: [String: Int] = [:]
    for step in 1...12 {
        await elStep(pair, header: 4 * step, zoom: 1 + Float(step) * 0.05)
        let f = try #require(pair.frames.last)
        translated += f.retainedTranslated
        for (r, n) in f.retainedTranslationRefusedReasons { refused[r, default: 0] += n }
        try pair.compare("step \(step) at display \(display) \(extra)")
    }
    #expect(translated >= 6 * 6, "the combined arm replayed: translated \(translated), refused \(refused)")
}
