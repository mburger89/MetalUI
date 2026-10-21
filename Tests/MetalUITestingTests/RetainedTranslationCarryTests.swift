import Foundation
import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import MetalUITextSystem
import Testing

// C14-h lane 2 (`RL-E`...`RL-I`, record 131): the translation carries. A translated replay (a layout or scroll shift, `FS-D`; a
// render-effect pan, `RK-G`) of an `.equatable()` occurrence now keeps what it used to refuse: a geometry note (`RG-C`, recomputed:
// the proxy is rebuilt and the user's transform runs again), accessibility records of a layout shift (`AT-C`, recomputed from the
// recorded post-offset rects), and a hitbox registered inside an effect the occurrence opened (`AT-G`, re-derived from the recorded
// step chain at any scale). Every test is a differential over a pair (`RPPair`: one window retaining, one with retention off) that
// compares the delivered geometry values (the side log), the published accessibility tree and the whole hitbox list after every step,
// and counts the work: `FrameWork` counters, never time.
//
// Red on arrival at c55d44e8 (the lines are in record 131 section 4): 12, 13, 14, 15b, 16, 17, 19 (scales 2 and 0.8), 20 (hits arm).
// 15a, 18 and the compare halves are green there: they pin what the build must keep.

private let rcVerifyNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay and graft counts this test pins are not its to read"

private func rcFrame(_ p: GeometryProxy, _ space: CoordinateSpace) -> String {
    let f = p.frame(in: space)
    return "\(f.origin.x.value),\(f.origin.y.value) \(f.size.width.value)x\(f.size.height.value)"
}

enum RCKind { case local, global, named, outer }

/// One observed card. `local` reads the size only (translation-invariant), `global` the window frame, `named` the global frame and
/// the frame in a space declared **inside** the card, `outer` the frame in a space declared **outside** it.
struct RCCard: Component, @MainActor Equatable {
    let id: Int
    let kind: RCKind
    let log: HarnessLog
    static func == (l: RCCard, r: RCCard) -> Bool { l.id == r.id && l.kind == r.kind && l.log === r.log }
    var content: some ElementGroup {
        switch kind {
        case .local:
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onGeometryChange(for: String.self, of: { rcFrame($0, .local) }) { log.add("L\(id):\($0)") }
        case .global:
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onGeometryChange(for: String.self, of: { rcFrame($0, .global) }) { log.add("G\(id):\($0)") }
        case .named:
            HStack(spacing: 0) {
                Box().frame(width: Pixels(16), height: Pixels(20)).background(.accent)
                Box().frame(width: Pixels(24), height: Pixels(20)).background(.accent)
                    .onGeometryChange(for: String.self, of: { "\(rcFrame($0, .global)) in \(rcFrame($0, .named("in")))" }) {
                        log.add("N\(id):\($0)")
                    }
            }
            .coordinateSpace(.named("in"))
        case .outer:
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .onGeometryChange(for: String.self, of: { rcFrame($0, .named("outer")) }) { log.add("O\(id):\($0)") }
        }
    }
}

enum RCMode { case plain, scrolled, pan }

/// Two cards under a header the test grows (`inputs.offset`, a layout shift), in a scroller (a scroll shift) or under
/// `.scaleEffect(scale)` + `.offset` (the effect translation; `inputs.offset` is the pan).
struct RCRoot: Component {
    let side: RPSide
    let kind: RCKind
    let mode: RCMode
    var scale: Double = 1
    var content: some ElementGroup {
        let pad = side.inputs.offset
        switch mode {
        case .plain:
            if kind == .outer {
                VStack(spacing: 2) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + pad))
                    RCCard(id: 0, kind: kind, log: side.log).equatable()
                    RCCard(id: 1, kind: kind, log: side.log).equatable()
                }
                .coordinateSpace(.named("outer"))
            } else {
                VStack(spacing: 2) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + pad))
                    RCCard(id: 0, kind: kind, log: side.log).equatable()
                    RCCard(id: 1, kind: kind, log: side.log).equatable()
                }
            }
        case .scrolled:
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + pad))
                    RCCard(id: 0, kind: kind, log: side.log).equatable()
                    RCCard(id: 1, kind: kind, log: side.log).equatable()
                    Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(400))
                }
            }
            .frame(width: Pixels(150), height: Pixels(120))
        case .pan:
            ZStack(alignment: .topLeading) {
                VStack(spacing: 2) {
                    RCCard(id: 0, kind: kind, log: side.log).equatable()
                    RCCard(id: 1, kind: kind, log: side.log).equatable()
                }
            }
            .scaleEffect(scale, anchor: .topLeading)
            .offset(x: Pixels(pad), y: Pixels(pad / 2))
        }
    }
}

@MainActor private func rcPair(_ kind: RCKind, _ mode: RCMode, scale: Double = 1, graft: Bool = false, warm: Int = 6)
    throws -> RPPair<some Element> {
    try RPPair(size: sz(220, 260), scale: 2, warm: warm, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { RCRoot(side: side, kind: kind, mode: mode, scale: scale) }
    }
}

/// The work of the frame just drawn, summed over its builds.
@MainActor private func rcStep(_ pair: RPPair<some Element>, _ name: String, _ act: () -> Void) async throws -> FrameWork {
    pair.on.resetFrameWork()
    act()
    await rsSettle()
    pair.redraw()
    let work = pair.stepWork
    try pair.compare(name)
    return work
}

@MainActor private func rcShift(_ pair: RPPair<some Element>, by delta: Float) {
    for side in [pair.onSide, pair.offSide] { side.inputs.offset += delta }
}

// MARK: geometry

/// 12 (`RL-E`). A whole-pixel layout shift of two occurrences that read only their `.local` size: both prepaints replay translated, no
/// `geometryTranslated` refusal is counted, nothing is delivered (the value is equal), and the side log equals a fresh window's.
/// Red at c55d44e8: `geometryTranslated == 2`, hits 0. Mutation: re-add the `geometryTranslated` refusal in `movedPrepaintLedger`.
@Test(.enabled(if: !rsVerifying, rcVerifyNote)) @MainActor
func aLayoutShiftKeepsALocalGeometryNote() async throws {
    let pair = try rcPair(.local, .plain)
    try pair.compare("warm")
    #expect(pair.onSide.log.entries.count == 2, "\(pair.onSide.log.entries)")
    let work = try await rcStep(pair, "shift") { rcShift(pair, by: 4) }
    #expect(work.retainedTranslationRefusedReasons["geometryTranslated", default: 0] == 0, "\(work.retainedTranslationRefusedReasons)")
    #expect(work.retainedPrepaintHits == 2, "both prepaints replay translated: \(work.retainedPrepaintHits)")
    #expect(pair.onSide.log.entries.count == 2, "a local value does not change under a shift: \(pair.onSide.log.entries)")
}

/// 13 (`RL-E`). A window-frame note over layout shifts (a header that grows, no scroller) and over scroll shifts (a wheel, K2): each
/// step's delivery equals a fresh window's (the value is recomputed from the translated frame, never the recorded one), nothing is
/// refused as `geometryTranslated` and the prepaints replay. Red at c55d44e8 (`geometryTranslated` refused, no hit). Mutations: keep
/// the recorded value in the translated note (every step differs); leave the scroll offset out of the moved frame (the wheel steps differ).
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [RCMode.plain, .scrolled]) @MainActor
func aGlobalFrameNoteIsRecomputedUnderShiftAndScroll(mode: RCMode) async throws {
    let pair = try rcPair(.global, mode)
    try pair.compare("warm")
    var refused = 0, hits = 0
    func record(_ w: FrameWork) {
        print("RC13 \(mode): hits \(w.retainedPrepaintHits) translated \(w.retainedTranslated) refused \(w.retainedTranslationRefusedReasons)")
        refused += w.retainedTranslationRefusedReasons["geometryTranslated", default: 0]; hits += w.retainedPrepaintHits
    }
    if mode == .plain {
        record(try await rcStep(pair, "shift 4") { rcShift(pair, by: 4) })
        record(try await rcStep(pair, "shift 8") { rcShift(pair, by: 8) })
        record(try await rcStep(pair, "shift -6") { rcShift(pair, by: -6) })
    } else {
        for delta in [Float(-30), -30, 30] {
            record(try await rcStep(pair, "wheel \(delta)") {
                for w in [pair.on, pair.off] { w.scroll(at: pt(110, 130), byDeltaX: 0, deltaY: delta) }
            })
        }
    }
    #expect(refused == 0, "no frame note is refused: \(refused)")
    #expect(hits > 0, "the prepaints replay: \(hits)")
    #expect(pair.onSide.log.entries.count > 2, "the moved frames were delivered: \(pair.onSide.log.entries)")
    #expect(pair.onSide.log.entries == pair.offSide.log.entries)
}

struct RCScaleArm: CustomStringConvertible, Sendable {
    let scale: Double
    var description: String { "scale \(scale)" }
}

/// 14 (`RL-E`). The same note under a pan effect (`.scaleEffect` then `.offset`) at scales 1, 2 and 0.8: the occurrence's frame is
/// recomputed from the **current** ambient effect after each pan step and equals a fresh window's delivery; not refused, prepaint
/// replayed. Red at c55d44e8. Mutations: recompute from the recorded ambient (the pan steps differ); skip the translated note.
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [1.0, 2.0, 0.8].map { RCScaleArm(scale: $0) }) @MainActor
func aGlobalFrameNoteUnderAPanEffectIsRecomputed(arm: RCScaleArm) async throws {
    let pair = try rcPair(.global, .pan, scale: arm.scale)
    try pair.compare("warm")
    var refused = 0, hits = 0
    for step in 1...4 {
        let w = try await rcStep(pair, "pan \(step) at \(arm)") { rcShift(pair, by: 4) }
        refused += w.retainedTranslationRefusedReasons["geometryTranslated", default: 0]; hits += w.retainedPrepaintHits
    }
    #expect(refused == 0, "\(refused)")
    #expect(hits > 0, "the pan replays prepaint: \(hits)")
    #expect(pair.onSide.log.entries.count > 2, "the moved frames were delivered: \(pair.onSide.log.entries)")
}

/// 15a (`RL-F`, amended by `RL-O`). A space declared **outside** the occurrence is in force at its entry: no ledger is made at all
/// (`prepaintRefusal`'s `namedSpaces`, upstream of the geometry note), so a shift never replays and never refuses by a geometry
/// name; the delivery equals a fresh window's. Green at c55d44e8 and kept so.
@Test(.enabled(if: !rsVerifying, rcVerifyNote)) @MainActor
func anOuterNamedSpaceIsIneligibleBeforeAnyGeometryNote() async throws {
    let pair = try rcPair(.outer, .plain)
    try pair.compare("warm")
    let work = try await rcStep(pair, "shift") { rcShift(pair, by: 4) }
    #expect(work.retainedPrepaintHits == 0, "\(work.retainedPrepaintHits)")
    #expect(work.retainedTranslationRefusedReasons["geometryNamedSpace", default: 0] == 0)
    #expect(work.retainedTranslationRefusedReasons["geometryTranslated", default: 0] == 0)
    #expect(work.retainedIneligibleReasons["namedSpaces", default: 0] > 0, "\(work.retainedIneligibleReasons)")
}

/// 15b (`RL-F`). A space declared **inside** the occurrence moves with it: the frame in that space is translation-invariant and the
/// window frame beside it is recomputed. Under a layout shift and a pan at scales 1 and 2 nothing is refused, the prepaints replay
/// and every delivery equals a fresh window's. Red at c55d44e8 (`geometryTranslated`). Mutation: leave the spaces' `toSpace` as
/// recorded (the named half of the value goes stale under the pan at scale 2); delete the identity-linear guard.
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [1.0, 2.0].map { RCScaleArm(scale: $0) }) @MainActor
func aNamedSpaceDeclaredInsideTheOccurrenceIsInvariant(arm: RCScaleArm) async throws {
    for mode in [RCMode.plain, .pan] {
        let pair = try rcPair(.named, mode, scale: arm.scale)
        try pair.compare("warm \(mode)")
        var refused = 0, hits = 0
        for step in 1...3 {
            let w = try await rcStep(pair, "\(mode) \(step) at \(arm)") { rcShift(pair, by: 4) }
            refused += w.retainedTranslationRefusedReasons.values.reduce(0, +); hits += w.retainedPrepaintHits
        }
        #expect(refused == 0, "\(mode): \(refused)")
        #expect(hits > 0, "\(mode): \(hits)")
        #expect(pair.onSide.log.entries.count > 2, "\(mode): \(pair.onSide.log.entries)")
    }
}

/// 16 (`RL-G`). With a frame note in the ledger a steady occurrence grafts (the `geometryGraft` refusal is gone) and a layout shift
/// across the graft costs no redo and no backoff: the translated replay the graft counts on exists. Red at c55d44e8 (graft refused
/// by name `geometryGraft`, grafts 0). Mutation: re-add the `geometryGraft` refusal (grafts 0); or lift it with the translated
/// notes removed (`aGlobalFrameNote...` and this test's delivery compare redden, redos 1).
@Test(.enabled(if: !rsVerifying, rcVerifyNote)) @MainActor
func anObserverGraftsAndAShiftNeedsNoRedo() async throws {
    let pair = try rcPair(.global, .plain, graft: true, warm: 8)
    try pair.compare("warm")
    let steady = try await rcStep(pair, "steady") {}
    #expect(!pair.on.window.testingGraftRefusals.contains("geometryGraft"), "\(pair.on.window.testingGraftRefusals)")
    #expect(steady.retainedGrafts == 2, "both observed cards graft: \(steady.retainedGrafts)")
    var redos = 0, backoff = 0, grafts = 0
    for step in 1...3 {
        let w = try await rcStep(pair, "shift \(step)") { rcShift(pair, by: 4) }
        redos += w.retainedRedos; backoff += w.retainedBackoffFrames; grafts += w.retainedGrafts
    }
    #expect(redos == 0, "a shift across a graft needs no redo: \(redos)")
    #expect(backoff == 0, "\(backoff)")
    #expect(grafts > 0, "the shift frames graft: \(grafts)")
}

// MARK: accessibility and hitboxes

/// A card of labelled rows: a hitbox, a focus stop, an accessibility record and a declared node each.
struct RCRow: Component, @MainActor Equatable {
    let k: Int
    var inner = false
    var content: some ElementGroup {
        if inner {
            VStack(spacing: 1) {
                Button("c\(k) r0") {}.accessibilityLabel("c\(k)r0").frame(width: Pixels(60), height: Pixels(12))
                Text("c\(k) t1").frame(width: Pixels(60), height: Pixels(12))
                Button("c\(k) r2") {}.accessibilityLabel("c\(k)r2").frame(width: Pixels(60), height: Pixels(12))
            }
            .frame(width: Pixels(60), height: Pixels(40)).clipped()
        } else {
            VStack(spacing: 1) {
                Button("c\(k) r0") {}.accessibilityLabel("c\(k)r0").frame(width: Pixels(60), height: Pixels(12))
                Text("c\(k) t1").frame(width: Pixels(60), height: Pixels(12))
                Button("c\(k) r2") {}.accessibilityLabel("c\(k)r2").frame(width: Pixels(60), height: Pixels(12))
            }
        }
    }
}

enum RCAXMode: CaseIterable, CustomStringConvertible { case scroller, clippedStack, effect, effectText, cutCards
    var description: String { switch self { case .scroller: "scroller"; case .clippedStack: "clippedStack"; case .effect: "effect"; case .effectText: "effectText"; case .cutCards: "cutCards" } }
}

/// A card whose own clip (derived inside the occurrence) cuts its second and third records: a text half cut, a button wholly cut.
struct RCCutRow: Component, @MainActor Equatable {
    let k: Int
    var content: some ElementGroup {
        VStack(spacing: 1) {
            Button("c\(k) r0") {}.accessibilityLabel("c\(k)r0").frame(width: Pixels(60), height: Pixels(12))
            Text("c\(k) t1").frame(width: Pixels(60), height: Pixels(12))
            Button("c\(k) r2") {}.accessibilityLabel("c\(k)r2").frame(width: Pixels(60), height: Pixels(12))
        }
        .frame(width: Pixels(60), height: Pixels(20), alignment: .top).clipped()
    }
}

struct RCTextRow: Component, @MainActor Equatable {
    let k: Int
    var content: some ElementGroup {
        VStack(spacing: 1) {
            Text("c\(k) t0").frame(width: Pixels(60), height: Pixels(12))
            Text("c\(k) t1").frame(width: Pixels(60), height: Pixels(12))
        }
    }
}

struct RCAXRoot: Component {
    let side: RPSide
    var inner = false
    var mode: RCAXMode = .scroller
    var content: some ElementGroup {
        let pad = side.inputs.offset
        switch mode {
        case .effectText:
            // Text only under the same effect: an accessibility record with no declared node and no hitbox.
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + pad))
                ForEach(Array(0..<3), id: \.self) { k in RCTextRow(k: k).equatable() }
            }
            .frame(width: Pixels(100), height: Pixels(200), alignment: .topLeading)
            .scaleEffect(2, anchor: .topLeading)
        case .effect:
            // The cards sit under `.scaleEffect(2)`: their records and hitboxes are under an ambient effect.
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + pad))
                ForEach(Array(0..<3), id: \.self) { k in RCRow(k: k, inner: inner).equatable() }
            }
            .frame(width: Pixels(100), height: Pixels(200), alignment: .topLeading)   // the effect's own box does not move
            .scaleEffect(2, anchor: .topLeading)
        case .cutCards:
            // Cards well inside the ambient clip, each cut by a clip of its own: the paint replays (no mask straddles the entry
            // clip) and the accessibility records are cut at a depth below the entry (`movedAccessibility`'s inner branch).
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + pad))
                ForEach(Array(0..<3), id: \.self) { k in RCCutRow(k: k).equatable() }
            }
            .padding(Edges(all: Pixels(10)))   // strictly inside the ambient clip on every side
            .frame(width: Pixels(150), height: Pixels(200), alignment: .topLeading)
            .clipped()
        case .clippedStack:
            // A header that grows over a stack cut by a clip: rows cross the clip's edge as they shift.
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + pad))
                ForEach(Array(0..<8), id: \.self) { k in RCRow(k: k, inner: inner).equatable() }
            }
            .frame(width: Pixels(150), height: Pixels(130), alignment: .topLeading)
            .clipped()
        case .scroller:
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    Box().frame(height: Pixels(10))
                    ForEach(Array(0..<8), id: \.self) { k in RCRow(k: k, inner: inner).equatable() }
                }
            }
            .frame(width: Pixels(150), height: Pixels(130))
        }
    }
}

@MainActor private func rcAXPair(inner: Bool = false, mode: RCAXMode = .scroller) throws -> RPPair<some Element> {
    try RPPair(size: sz(240, 300), scale: 2, warm: 6, accessibility: true, graft: false) { side in
        VStack(spacing: 0) { RCAXRoot(side: side, inner: inner, mode: mode) }
    }
}

/// 17 (`RL-H`, `AT-C`). A layout shift under a clip (a growing header), and wheel scrolls that cut rows at the viewport's edge and
/// back: every step's published tree (nodes, frames, visible frames, order) equals a fresh window's, the records are recomputed (no
/// `accessibilityRecords` refusal) and the prepaints replay translated. `inner` adds a clip derived inside each card. Red at c55d44e8
/// (`accessibilityRecords` refused where the prepaint is asked, no hit). Mutations: shift the visible frame by the delta without
/// cutting it again at the ambient clip (the clipped arms differ); use the old frame (every step differs).
struct RCAXArm: CustomStringConvertible, Sendable {
    let inner: Bool, mode: RCAXMode
    var description: String { "\(mode) inner \(inner)" }
}

@Test(.enabled(if: !rsVerifying, rcVerifyNote),
      arguments: [RCAXArm(inner: false, mode: .scroller), RCAXArm(inner: false, mode: .clippedStack),
                  RCAXArm(inner: true, mode: .clippedStack)]) @MainActor
func aLayoutShiftReplaysAccessibilityRecordsRecomputed(arm: RCAXArm) async throws {
    let pair = try rcAXPair(inner: arm.inner, mode: arm.mode)
    try pair.compare("warm")
    var refused = 0, hits = 0, cut = 0, stepsWithoutHit = 0
    var steps: [(String, () -> Void)] = []
    if arm.mode == .scroller {
        for delta in [Float(-17), -17, -40, 30, 30] {
            steps.append(("wheel \(delta)", { for w in [pair.on, pair.off] { w.scroll(at: pt(120, 150), byDeltaX: 0, deltaY: delta) } }))
        }
    } else {
        for delta in [Float(4), 8, 20, -12, -20] { steps.append(("header \(delta)", { rcShift(pair, by: delta) })) }
    }
    for (name, act) in steps {
        let w = try await rcStep(pair, name, act)
        print("RC17 \(arm) \(name): hits \(w.retainedPrepaintHits) translated \(w.retainedTranslated) refused \(w.retainedTranslationRefusedReasons)")
        refused += arm.inner ? w.retainedTranslationRefusedReasons["accessibilityRecords", default: 0]
            : w.retainedTranslationRefusedReasons.values.reduce(0, +)
        hits += w.retainedPrepaintHits
        if w.retainedPrepaintHits == 0 { stepsWithoutHit += 1 }
        cut += try pair.on.accessibilityTree.geometry.values.filter { $0.visibleFrame != $0.frame }.count
    }
    #expect(refused == 0, "no accessibilityRecords refusal: \(refused)")
    // A clip derived inside each card is a paint-record refusal (`maskStraddlesEntryClip`) that asks for no prepaint: the tree compare is the pin.
    if !arm.inner {
        #expect(hits > 0, "the prepaints replay: \(hits)")
        // Every step replays: a record the rebased ledger lost (`axNodeLocals`) refuses the next shift by name `accessibilityUnrecorded`.
        #expect(stepsWithoutHit == 0, "every step replays its prepaint: \(stepsWithoutHit) did not")
    }
    #expect(cut > 0, "some record is cut by the viewport: the arm must meet a cut visible frame")
}

/// 17b (`RL-H`). A layout shift of cards that each cut their own accessibility records with a clip pushed inside the occurrence (the
/// cards stay strictly inside the ambient clip, so the paint replays too): the prepaints replay translated, the cut visible frames move
/// with the card instead of being cut again at the ambient clip, and every step's published tree equals a fresh window's. Mutation:
/// replace `emission.clipDepth == entryDepth` in `movedAccessibility` with `true` (an inner record's visible frame is then the whole
/// frame, uncut by its card's clip).
@Test(.enabled(if: !rsVerifying, rcVerifyNote)) @MainActor
func aLayoutShiftMovesARecordCutByAClipInsideTheOccurrence() async throws {
    let pair = try rcAXPair(mode: .cutCards)
    try pair.compare("warm")
    var hits = 0, stepsWithoutHit = 0, cut = 0
    for delta in [Float(4), 8, -6, 10, -12] {
        let w = try await rcStep(pair, "header \(delta)") { rcShift(pair, by: delta) }
        print("RC17b \(delta): hits \(w.retainedPrepaintHits) translated \(w.retainedTranslated) refused \(w.retainedTranslationRefusedReasons) ineligible \(w.retainedIneligibleReasons)")
        hits += w.retainedPrepaintHits
        if w.retainedPrepaintHits == 0 { stepsWithoutHit += 1 }
        cut += try pair.on.accessibilityTree.geometry.values.filter { $0.visibleFrame != $0.frame }.count
    }
    #expect(hits > 0 && stepsWithoutHit == 0, "every step replays its prepaint: hits \(hits), \(stepsWithoutHit) without")
    #expect(cut > 0, "some record is cut by its card's own clip: the arm must meet a cut visible frame")
}

/// 18 (`RL-H`). A record made under an effect still refuses a layout shift, by its own name `accessibilityUnderEffect` (the effect
/// translation owns it, `AT-A`); the tree equals a fresh window's. Mutation: delete the refusal (the shifted ambient-effect records
/// are replayed unrecomputed and the tree differs).
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [RCAXMode.effect, .effectText]) @MainActor
func anAccessibilityRecordUnderAnEffectStillRefusesOnLayoutShift(mode: RCAXMode) async throws {
    let pair = try rcAXPair(mode: mode)
    try pair.compare("warm")
    var reasons: [String: Int] = [:]
    for step in 1...3 {
        let w = try await rcStep(pair, "header \(step)") { rcShift(pair, by: 4) }
        reasons.merge(w.retainedTranslationRefusedReasons, uniquingKeysWith: +)
    }
    print("RC18 \(mode) reasons \(reasons)")
    #expect(reasons["accessibilityUnderEffect", default: 0] > 0, "\(reasons)")
    #expect(reasons["accessibilityRecords", default: 0] == 0, "\(reasons)")
}

/// A pan pair over `ATRoot`'s nodes with a nested effect (`AT-G`) at `scale`.
@MainActor private func rcNestedPair(scale: Double, accessibility: Bool) throws -> RPPair<some Element> {
    try RPPair(size: sz(1200, 320), scale: 2, warm: 8, accessibility: accessibility, graft: false) { side in
        VStack(spacing: 0) { ATRoot(side: side, scale: scale, nested: true) }
    }
}

/// 19 (`RL-I`). A hitbox registered inside an effect the occurrence opened is re-derived from the recorded step chain: at scales 1, 2
/// and 0.8 the nested nodes replay their prepaint under a pan (no `hitboxes` refusal), and the whole hitbox list (inverse transform,
/// outer clip, order) equals a fresh window's after every step. Red at c55d44e8 for 2 and 0.8 (`hitboxes` refused, no hit).
/// Mutations: the hitbox's old inverse kept; the delta rule (`tx - dx`) restored for every scale (0.8 and 2 redden).
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [1.0, 2.0, 0.8].map { RCScaleArm(scale: $0) }) @MainActor
func aHitboxOpenedInsideTheOccurrencesEffectReplaysAtNonIdentityScale(arm: RCScaleArm) async throws {
    let pair = try rcNestedPair(scale: arm.scale, accessibility: false)
    try pair.compare("warm")
    var hits = 0, refused: [String: Int] = [:]
    for step in 1...4 {
        let w = try await rcStep(pair, "pan \(step) at \(arm)") { for s in [pair.onSide, pair.offSide] { s.inputs.offset = Float(step) * 3.37 } }
        hits += w.retainedPrepaintHits
        refused.merge(w.retainedTranslationRefusedReasons, uniquingKeysWith: +)
    }
    #expect(refused["hitboxes", default: 0] == 0, "\(refused)")
    #expect(hits > 0, "the nested nodes replay their prepaint: \(hits)")
}

/// 20 (`RL-I`, `AT-G`'s M6). With a client reading the tree, the nested nodes' records are recomputed from the recorded steps at
/// scale 2 and 0.8, where the replay now actually runs (the hitboxes no longer refuse it, so test 5 of record 129 saw no walk at scale
/// 2): the tree equals a fresh window's after every step. **The mutation that skips the nested steps (`for step in chain.steps[base...]`
/// emptied) was green at scale 2 at c55d44e8 (record 129 section 8, M6) and must redden here.** Red at c55d44e8: hits 0.
@Test(.enabled(if: !rsVerifying, rcVerifyNote), arguments: [2.0, 0.8].map { RCScaleArm(scale: $0) }) @MainActor
func aNestedEffectAccessibilityRecordIsRecomputedAtScaleTwo(arm: RCScaleArm) async throws {
    let pair = try rcNestedPair(scale: arm.scale, accessibility: true)
    try pair.compare("warm")
    var hits = 0, accessibilityRefusals = 0
    for step in 1...4 {
        let w = try await rcStep(pair, "pan \(step) at \(arm)") { for s in [pair.onSide, pair.offSide] { s.inputs.offset = Float(step) * 3.37 } }
        hits += w.retainedPrepaintHits
        for (reason, n) in w.retainedTranslationRefusedReasons where reason.hasPrefix("accessibility") { accessibilityRefusals += n }
    }
    #expect(hits > 0, "the nested nodes replay: the walk ran, so the tree compares what it computed: \(hits)")
    #expect(accessibilityRefusals == 0, "\(accessibilityRefusals)")
}

/// 15c (`RL-O`). A named space declared inside the occurrence under a **non-dyadic** ambient scale (0.8) is not moved: the pan refuses by
/// name `geometryNamedSpace` (its moved map would not be bit-equal to a fresh prepaint's), the prepaint runs, and the deliveries equal a
/// fresh window's. Mutation: drop the dyadic guard in `translatedGeometryNotes` (the refusal count reads 0).
@Test(.enabled(if: !rsVerifying, rcVerifyNote)) @MainActor
func aNamedSpaceUnderANonDyadicScaleRefusesByName() async throws {
    let pair = try rcPair(.named, .pan, scale: 0.8)
    try pair.compare("warm")
    var refused = 0
    for step in 1...3 {
        let w = try await rcStep(pair, "pan \(step)") { rcShift(pair, by: 4) }
        refused += w.retainedTranslationRefusedReasons["geometryNamedSpace", default: 0]
    }
    #expect(refused > 0, "refused by name: \(refused)")
    #expect(pair.onSide.log.entries.count > 2, "\(pair.onSide.log.entries)")
}
