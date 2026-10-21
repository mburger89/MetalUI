import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// C14-i lane 1 (`RZ-A`...`RZ-G`, record 133): an `.equatable()` occurrence under render effects whose **affine** changed (a zoom, a
// rotation, both) replays its paint and prepaint and grafts, instead of rebuilding. Every differential draws two windows from one
// builder (one retaining, one with retention off) and compares the scene, the published tree, the hitboxes and the logs. Counts
// are `FrameWork` work, never time.
//
// **Red at 1bdead8d** (measured before any source change, `zoomRedRun`): see each test's note.

private let zVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay and graft counts this test pins are not its to read"

struct ZArm: CustomStringConvertible, Sendable {
    let scale: Float
    var description: String { "scale \(scale)" }
}

/// The centre of a labelled element's drawn frame in `window`.
@MainActor private func zCentre(_ window: TestWindow, _ label: String) throws -> Point<Pixels> {
    let element = try window.element(label: label)
    let frame = try #require(try window.accessibilityTree.geometry[element.id]?.frame)
    return Point(x: Pixels(frame.origin.x.value + frame.size.width.value / 2),
                 y: Pixels(frame.origin.y.value + frame.size.height.value / 2))
}

/// Z1 — a warm zoom step of ten nodes grafts: no redo, no backoff, no `effectNotTranslation`, the build a small fraction of the
/// unretained frame's, the scene and published tree equal to the unretained window's at every step.
/// **Red at 1bdead8d**: every step counts `effectNotTranslation`, the grafted occurrences redo the frame and prepaint replay backs
/// off. Mutations: `differsOnlyByEffectAffine` returns false; `PrepaintExtras.change(from:)` returns nil for an affine change.
@Test(.enabled(if: !rsVerifying, zVerifyingNote)) @MainActor
func aZoomStepGraftsWithoutARedo() async throws {
    let pair = try zoomPair()
    try pair.compare("warm")
    var grafts = 0, redos = 0, backoff = 0, reasons: [String: Int] = [:]
    var requests: [Int] = [], baselines: [Int] = []
    for (step, scale) in [Float(1.1), 1.21, 1.331].enumerated() {
        await zoomStep(pair, to: scale)
        let f = try #require(pair.frames.last)
        grafts += f.retainedGrafts; redos += f.retainedRedos; backoff += f.retainedBackoffFrames
        requests.append(f.elementRequests); baselines.append(pair.off.lastFrameWork.elementRequests)
        for (r, n) in f.retainedTranslationRefusedReasons { reasons[r, default: 0] += n }
        try pair.compare("zoom step \(step) to \(scale)")
    }
    print("Z1: grafts \(grafts) redos \(redos) backoff \(backoff) requests \(requests) baseline \(baselines) reasons \(reasons)")
    #expect(grafts > 0, "zoom frames graft: \(grafts)")
    #expect(redos == 0, "no frame is redone: \(redos)")
    #expect(backoff == 0, "prepaint replay is never backed off: \(backoff)")
    #expect(reasons["effectNotTranslation"] == nil, "\(reasons)")
    for (r, b) in zip(requests, baselines) { #expect(Double(r) <= 0.15 * Double(b), "element requests \(r) of \(b)") }
}

/// Z2 — after every zoom step the published tree (nodes, geometry frame and visible frame) equals the unretained window's, at
/// scales 1.1, 0.8, 2 and 1.21 (0.8 and 1.1 are inexact in `Float`, so a frame shifted by a delta differs from one recomputed by an
/// ulp where scale 2 cannot show it). Mutations: the ledger's frames replayed unrecomputed; the frames scaled by the ratio of the
/// two scales instead of recomputed from the recorded pre-effect rects.
@Test(arguments: [1.1, 0.8, 2.0, 1.21].map { ZArm(scale: Float($0)) }) @MainActor
func aZoomPublishesTheFreshAccessibilityTree(arm: ZArm) async throws {
    let pair = try zoomPair(warm: 6)
    try pair.compare("warm")
    var replayed = 0
    for (step, scale) in [arm.scale, arm.scale * 1.05, arm.scale].enumerated() {
        await zoomStep(pair, to: scale)
        let f = try #require(pair.frames.last)
        replayed += f.retainedPrepaintHits + f.retainedTranslated
        try pair.compare("zoom step \(step) at \(arm)")
    }
    if !rsVerifying { #expect(replayed > 0, "the retaining side replayed nothing: the differential proves nothing") }
}

/// Z3 — after each zoom step a click at a node's drawn centre fires **that** node's action and one at another node's pre-zoom centre
/// does not fire it, equal to the unretained window's log. Mutation: `translatedHitboxes` keeps the recorded inverse.
@Test @MainActor
func aZoomedNodeIsHitWhereItIsDrawn() async throws {
    let pair = try zoomPair(warm: 6)
    let before = try zCentre(pair.on, "z7")
    var replayed = 0
    for (step, scale) in [Float(1.1), 1.21, 1.331].enumerated() {
        await zoomStep(pair, to: scale)
        let f = try #require(pair.frames.last)
        replayed += f.retainedPrepaintHits
        let drawn = try zCentre(pair.on, "z3")
        for w in [pair.on, pair.off] { w.click(at: drawn); w.click(at: before) }
        try pair.compare("clicks after zoom step \(step)")
        #expect(pair.onSide.log.entries.contains("z3"), "the node is hit where it is drawn: \(pair.onSide.log.entries)")
    }
    if !rsVerifying { #expect(replayed > 0, "no prepaint replayed: the differential proves nothing") }
}

/// Z4 — a stroked path under a zoom is re-rastered by the ordinary cache, work equal to a fresh frame and no refusal: the scene's
/// primitives and images equal the unretained window's, so does the rasterized-pixel and new-texture count of the step, at an exact
/// step and at a 1/16-pixel step. Mutation: the path leaf replayed from the record's final stream (the old scale's pixels).
@Test(arguments: [Float(1.25), 1.0625, 1.0001]) @MainActor
func aStrokedPathUnderAZoomIsRerasteredNotStale(step: Float) async throws {
    let pair = try zoomPair(warm: 6)
    try pair.compare("warm")
    await zoomStep(pair, to: step)
    try pair.compare("zoom to \(step)")
    let on = pair.on.lastFrameWork, off = pair.off.lastFrameWork
    #expect(on.rasterizedPixels == off.rasterizedPixels, "raster work equal: \(on.rasterizedPixels) vs \(off.rasterizedPixels)")
    #expect(on.newTextures == off.newTextures && on.newTexturePixels == off.newTexturePixels)
    #expect(off.rasterizedPixels > 0, "the step rasterized something: the path is the instrument")
}

/// Z5 — an effect change that is not an affine move of one scope is refused by name, the named reason is counted and only it, the
/// frame equals fresh. Arms: `flattensChanged` (`scaleEffect(x:y:)` leaves the uniform class), `outerClipChanged` (the frame outside
/// the effect, whose clip the effect opens under, moves with the scale), `namedSpaceNote` (a geometry note holding a space declared
/// inside the node), `anchor` (a closed `.popover` declarer: a window-space anchor), `contextMenu` (a window-space menu record).
/// Mutations, one per arm: the `flattens` equality dropped (in `change(from:)` and `effectRelation`), the outer-clip equality
/// dropped, the named-space guard dropped, the anchor guard dropped, the context-menu guard dropped.
enum ZRefusalArm: CaseIterable, CustomStringConvertible, Sendable {
    case flattensChanged, outerClipChanged, namedSpaceNote, anchor, contextMenu
    var description: String {
        switch self {
        case .flattensChanged: "flattensChanged"; case .outerClipChanged: "outerClipChanged"
        case .namedSpaceNote: "namedSpaceNote"; case .anchor: "anchor"; case .contextMenu: "contextMenu"
        }
    }
    var extra: ZExtra { self == .flattensChanged ? .nonUniform : self == .outerClipChanged ? .outerClip : .none }
    var kind: ZKind {
        switch self {
        case .namedSpaceNote: .namedSpace; case .anchor: .popover; case .contextMenu: .menu; default: .plain
        }
    }
    var reason: String {
        switch self {
        case .flattensChanged: "effectFlatteningChanged"; case .outerClipChanged: "effectClipChanged"
        case .namedSpaceNote: "geometryNamedSpace"; case .anchor: "presentationAnchor"; case .contextMenu: "contextMenus"
        }
    }
}

@Test(.enabled(if: !rsVerifying, zVerifyingNote), arguments: ZRefusalArm.allCases) @MainActor
func anEffectChangeThatIsNotAnAffineMoveIsRefusedByName(arm: ZRefusalArm) async throws {
    let pair = try zoomPair(extra: arm.extra, kind: arm.kind, warm: 6, graft: false)
    try pair.compare("warm")
    var refusals: [String: Int] = [:]
    for scale in [Float(1.1), 1.2] {
        await zoomStep(pair, to: scale)
        for (r, n) in try #require(pair.frames.last).retainedTranslationRefusedReasons { refusals[r, default: 0] += n }
        try pair.compare("step to \(scale) at \(arm)")
    }
    #expect(refusals[arm.reason, default: 0] > 0, "\(arm.reason) is counted: \(refusals)")
    #expect(Set(refusals.keys) == [arm.reason], "only \(arm.reason) refuses: \(refusals)")
}

/// Z6 — a rotation step together with a scale step is replayed exactly: scene, tree and hits equal fresh. Red at 1bdead8d:
/// `effectNotTranslation`. Mutation as Z1 (i).
@Test(.enabled(if: !rsVerifying, zVerifyingNote)) @MainActor
func aRotationStepIsReplayedExactly() async throws {
    let pair = try zoomPair(rotation: true, warm: 6)
    try pair.compare("warm")
    // The first rotation step turns an identity rotation (a flattening scope) into a real one: a class change, refused by name
    // (`effectFlatteningChanged`) and re-recorded; the steps after it are affine.
    await zoomStep(pair, to: 1.05)
    for _ in 0..<24 { pair.redraw() }
    var replayed = 0, refused: [String: Int] = [:]
    for (step, scale) in [Float(1.1), 1.15, 1.2].enumerated() {
        await zoomStep(pair, to: scale)
        let f = try #require(pair.frames.last)
        replayed += f.retainedPrepaintHits
        for (r, n) in f.retainedTranslationRefusedReasons { refused[r, default: 0] += n }
        let drawn = try zCentre(pair.on, "z2")
        for w in [pair.on, pair.off] { w.click(at: drawn) }
        try pair.compare("rotation step \(step)")
    }
    #expect(replayed > 0, "replayed: \(replayed), refused \(refused)")
    #expect(refused["effectNotTranslation"] == nil, "\(refused)")
}

/// Z7 — a node with an effect of its own: a click at its inner button after each outer step hits where it is drawn (`RL-I`'s step
/// walk from the current ambient). Mutation: the walk replaced by the recorded transform.
@Test @MainActor
func aHitboxInsideAnEffectTheOccurrenceOpenedFollowsTheZoom() async throws {
    let pair = try zoomPair(kind: .inner, warm: 6)
    try pair.compare("warm")
    var replayed = 0
    for (step, scale) in [Float(1.1), 1.21, 0.9].enumerated() {
        await zoomStep(pair, to: scale)
        replayed += try #require(pair.frames.last).retainedPrepaintHits
        let drawn = try zCentre(pair.on, "z4")
        for w in [pair.on, pair.off] { w.click(at: drawn) }
        try pair.compare("inner step \(step)")
        #expect(pair.onSide.log.entries.contains("z4"), "the inner button is hit where it is drawn: \(pair.onSide.log.entries)")
    }
    _ = replayed
}

/// Z8 — a stationary pointer, a zoom that carries a node under it: the node's hover paint equals fresh (the pointer is read against
/// the moved hitboxes). Mutation: the moved-hitbox pointer read skipped.
@Test @MainActor
func aZoomThatCarriesTheContentUnderAStationaryPointerRunsThePrepaint() async throws {
    let pair = try zoomPair(warm: 6)
    // A point on blank canvas at scale 1 that node 9's button covers at 1.5.
    let target = try zCentre(pair.on, "z9")
    let probe = pt(target.x.value + 150, target.y.value)
    for w in [pair.on, pair.off] { w.hover(at: probe) }
    try pair.compare("hover at rest")
    for (step, scale) in [Float(1.2), 1.5, 1.8].enumerated() {
        await zoomStep(pair, to: scale)
        try pair.compare("zoom step \(step) under a stationary pointer")
    }
}

/// Z9 — the report: element requests, grafts, redos, prepaints and paints of a zoom step and of a bracket pan step, retaining and
/// not. No threshold: the table is for the record (`print`).
@Test(.enabled(if: !rsVerifying, zVerifyingNote)) @MainActor
func aZoomBeforeAndAfterOnTheBracketFixtureIsReported() async throws {
    let pair = try zoomPair(warm: 8)
    await zoomStep(pair, to: 1.1)
    for scale in [Float(1.21), 1.331] { await zoomStep(pair, to: scale) }
    let on = try #require(pair.frames.last), off = pair.off.lastFrameWork
    print("Z9 zoom retaining:  requests \(on.elementRequests) prepaints \(on.elementPrepaints) paints \(on.elementPaints) grafts \(on.retainedGrafts) redos \(on.retainedRedos) translated \(on.retainedTranslated) hits \(on.retainedHits) refused \(on.retainedTranslationRefusedReasons)")
    print("Z9 zoom unretained: requests \(off.elementRequests) prepaints \(off.elementPrepaints) paints \(off.elementPaints)")
    let (bracket, model) = try bracketWindow(arm: .value, textSystem: harnessTextSystem)
    bracket.window.testingRetainedGraft = true
    for _ in 0..<4 { bracket.window.setNeedsRedraw(); bracket.tick() }
    var line: [FrameWork] = []
    for _ in 0..<6 { model.panX -= 4; bracket.window.setNeedsRedraw(); bracket.tick(); line.append(bracket.lastFrameWork) }
    let f = try #require(line.last)
    print("Z9 bracket pan: requests \(f.elementRequests) prepaints \(f.elementPrepaints) paints \(f.elementPaints) grafts \(f.retainedGrafts) redos \(f.retainedRedos) translated \(f.retainedTranslated)")
}

/// Z10 — a pure pan under the effect keeps the translation arm: with a context menu on every node (a window-space record the
/// affine arm refuses, `RZ-F`) a pan still replays the prepaint and counts no refusal, and the tree, scene and hits equal fresh
/// (at scale 0.8 and 2, where the pan of 0.37 points is inexact). Mutation: `change(from:)` asking the affine arm before the
/// translation arm reddens the replay count (every pan step refuses `contextMenus`).
@Test(.enabled(if: !rsVerifying, zVerifyingNote), arguments: [Float(0.8), 2]) @MainActor
func aPurePanStillTakesTheTranslationArm(scale: Float) async throws {
    let pair = try zoomPair(kind: .menu, warm: 6)
    await zoomStep(pair, to: scale)
    // The zoom step refuses `contextMenus` under a graft: one redo and a window-wide backoff of eight builds, flushed here.
    for _ in 0..<24 { pair.redraw() }
    try pair.compare("at scale \(scale)")
    var refused: [String: Int] = [:], replayed = 0
    for step in 1...4 {
        await zoomPan(pair, by: 3)
        let f = try #require(pair.frames.last)
        replayed += f.retainedPrepaintHits
        for (r, n) in f.retainedTranslationRefusedReasons { refused[r, default: 0] += n }
        try pair.compare("pan step \(step) at scale \(scale)")
    }
    #expect(replayed > 0, "a pan replays: \(replayed)")
    #expect(refused.isEmpty, "a pan refuses nothing: \(refused)")
}
