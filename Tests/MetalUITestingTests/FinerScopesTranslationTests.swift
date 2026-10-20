import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// C14-d lane 2 (`FS-D`..`FS-G`, `FS-M`, record 126): an `.equatable()` occurrence whose layout origin or scroll offset moved replays
// moved instead of missing. Figures are `FrameWork` counts per frame (work, never time) on the 24 `FSCard` rows of
// `FinerScopesFixture.swift` at scale 2; red on arrival at 711ab9c4 (F2, F3: hits 0, translated 0).

private let fsTranslationVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 paints a hit as a miss: the replay counts this test pins are not its to read"

/// What moves the rows: an id inserted first (F2), a header above that grows 4 pt (F2), a wheel over a `ScrollView` (F3).
enum FSShift: CaseIterable, CustomStringConvertible {
    case insertFront, header, scroll
    var description: String {
        switch self { case .insertFront: "insertFront"; case .header: "header"; case .scroll: "scroll" }
    }
}

@MainActor final class FSShiftModel {
    var ids: [Int] = Array(0..<24)
    var header: Float = 10
    var step = 0
}

struct FSShiftRoot: Component {
    let model: FSShiftModel
    let kind: FSShift
    var content: some ElementGroup {
        switch kind {
        case .insertFront:
            VStack(spacing: 2) {
                ForEach(model.ids, id: \.self) { i in FSCard(id: i, value: 0).equatable() }
            }
        case .header:
            VStack(spacing: 2) {
                Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(model.header))
                ForEach(model.ids, id: \.self) { i in FSCard(id: i, value: 0).equatable() }
            }
        case .scroll:
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(model.ids, id: \.self) { i in FSCard(id: i, value: 0).equatable() }
                }
            }.frame(width: Pixels(300), height: Pixels(150))
        }
    }
}

/// `FSShiftRoot`'s cards driven by an `RPSide` (a pair's two windows share nothing else): `inputs.offset` is the header growth in
/// points for `.header`, and the number of ids inserted in front for `.insertFront`.
struct FSShiftSideRoot: Component {
    let side: RPSide
    let kind: FSShift
    var content: some ElementGroup {
        switch kind {
        case .insertFront:
            VStack(spacing: 2) {
                ForEach(Array((0..<Int(side.inputs.offset)).map { 100 + $0 }) + Array(0..<24), id: \.self) { i in
                    FSCard(id: i, value: 0).equatable()
                }
            }
        case .header:
            VStack(spacing: 2) {
                Color(red: 0.5, green: 0.5, blue: 0.5).frame(height: Pixels(10 + side.inputs.offset))
                ForEach(Array(0..<24), id: \.self) { i in FSCard(id: i, value: 0).equatable() }
            }
        case .scroll:
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(Array(0..<24), id: \.self) { i in FSCard(id: i, value: 0).equatable() }
                }
            }.frame(width: Pixels(300), height: Pixels(150))
        }
    }
}

/// Three frames after sixteen warm ones, each preceded by one step of `kind`'s movement.
@MainActor func fsShiftFrames(_ kind: FSShift, graft: Bool, accessibility: Bool, scale: Float = 2) throws -> [FrameWork] {
    let model = FSShiftModel()
    let options = HeadlessPlatformWindow.Options(scaleFactor: scale, accessibilityClientActive: accessibility)
    let w = try TestWindow(size: Size(width: Pixels(320), height: Pixels(400)), scaleFactor: scale, options: options,
                           textSystem: { harnessTextSystem() }) { VStack(spacing: 0) { FSShiftRoot(model: model, kind: kind) } }
    w.window.testingRetainedGraft = graft
    for _ in 0..<16 { w.window.setNeedsRedraw(); w.tick() }
    w.resetFrameWork()
    for step in 0..<3 {
        switch kind {
        case .insertFront: model.ids.insert(100 + step, at: 0)
        case .header: model.header += 4
        case .scroll: w.scroll(at: Point(x: Pixels(160), y: Pixels(200)), byDeltaX: 0, deltaY: -30)
        }
        w.window.setNeedsRedraw(); w.tick()
    }
    return w.frameWork
}

/// 2.1 to 2.3 — the rows of a stack shifted by an insertion, a header that grew and a wheel replay translated
/// (`FS-D`, K1 and K2). At 711ab9c4 every row missed (F2: 171 to 190 requests, 244 to 271 paints, hits 0; F3: 171, 172, 244).
@Test(.enabled(if: !rsVerifying, fsTranslationVerifyingNote), arguments: FSShift.allCases, [false, true]) @MainActor
func aShiftedOrScrolledRowReplaysTranslated(kind: FSShift, accessibility: Bool) throws {
    let frames = try fsShiftFrames(kind, graft: false, accessibility: accessibility)
    // A wheel draws a settle frame after the frame that moved (nothing moves in it): only the moving frames translate.
    var moving = 0
    for f in frames {
        #expect(f.retainedHits >= 23, "rows hit at paint: \(f.retainedHits)")
        #expect(f.elementPaints < 60, "element paints: \(f.elementPaints)")
        #expect(f.retainedRedos == 0)
        if f.retainedTranslated > 0 { moving += 1; #expect(f.retainedTranslated >= 23, "rows replayed translated: \(f.retainedTranslated)") }
    }
    #expect(moving >= 3, "each of the three movements translated: \(moving)")
}

extension RPPair {
    /// The retaining window's work since the last `resetFrameWork()`: every frame drawn, the wheel's own included.
    var stepWork: FrameWork { on.frameWork.reduce(FrameWork(), +) }
}

// MARK: the differential (2.5)

/// A scroller over a header that grows, an optional first card and six `RPCard`s: a card holds a button (hitbox, focus stop,
/// accessibility record), a context menu, five tallied regions and a rounded clip pushed inside the occurrence, so the move
/// meets every channel a translated replay stands for.
private struct FSShiftDiffRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + side.inputs.offset)).background(.accent)
                if side.inputs.showExtra { RPCard(title: "new", shade: 1, log: side.log).equatable() }
                ForEach(Array(0..<6), id: \.self) { k in RPCard(title: "c\(k)", shade: k, log: side.log).equatable() }
            }
            .padding(Edges(all: Pixels(8)))
        }
        .frame(width: Pixels(300), height: Pixels(260))
    }
}

/// 2.5 — the retaining window equals a retention-off window after every step of a script that grows the header (K1), wheels the
/// scroller (K2), inserts a first card (K1 with a new neighbour) and undoes them, at scales 1, 1.5, 2, 3 and 4, with and
/// without an accessibility client: scene bytes, hitboxes in order, accessibility tree, Tab order, element bounds and
/// registrations (`FS-D`, `FS-M`). Whatever the gate accepts is bit-identical; whatever it refuses is named and misses. At the
/// dyadic scales a move translates. Mutations: the add applied to the y axis twice (the scene differs at every scale), the
/// exactness test replaced by `true` (the 1.5 and 3 arms differ), the whole-pixel test replaced by `true` (the verify run traps
/// and the differential at 1.5 differs).
@Test(arguments: rpScaleArms) @MainActor
func aTranslatedLayoutReplayEqualsAFreshFrameAtEveryScale(arm: RPScaleArm) async throws {
    let pair = try RPPair(size: sz(320, 300), scale: arm.scale, warm: 4, accessibility: arm.accessibility, graft: false) { side in
        VStack(spacing: 0) { FSShiftDiffRoot(side: side) }
    }
    try pair.compare("warm")
    var translated = 0, refusals: [String: Int] = [:], redos = 0
    let steps: [(String, (_ sides: [RPSide], _ windows: [TestWindow]) -> Void)] = [
        ("header +4", { sides, _ in for s in sides { s.inputs.offset += 4 } }),
        ("header +4 again", { sides, _ in for s in sides { s.inputs.offset += 4 } }),
        ("wheel -30", { _, windows in for w in windows { w.scroll(at: pt(150, 120), byDeltaX: 0, deltaY: -30) } }),
        ("wheel -30 again", { _, windows in for w in windows { w.scroll(at: pt(150, 120), byDeltaX: 0, deltaY: -30) } }),
        ("first card", { sides, _ in for s in sides { s.inputs.showExtra = true } }),
        ("wheel +30", { _, windows in for w in windows { w.scroll(at: pt(150, 120), byDeltaX: 0, deltaY: 30) } }),
        ("header -8", { sides, _ in for s in sides { s.inputs.offset -= 8 } }),
        ("first card gone", { sides, _ in for s in sides { s.inputs.showExtra = false } }),
    ]
    for (index, (name, step)) in steps.enumerated() {
        pair.on.resetFrameWork()
        step([pair.onSide, pair.offSide], [pair.on, pair.off])
        await rsSettle()
        pair.redraw()
        for f in [pair.stepWork] {
            translated += f.retainedTranslated; redos += f.retainedRedos
            refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        }
        try pair.compare("step \(index) (\(name))")
        pair.redraw()   // the settle frame
        try pair.compare("step \(index) settled")
    }
    let allowed: Set<String> = ["accessibilityRecords", "contextMenus", "inexactTranslation", "fractionalTranslation", "hitboxClipped", "maskStraddlesEntryClip"]
    // Under `METALUI_VERIFY_RETAINED=1` the differential still runs (every hit is also compared with a fresh run), but a hit is
    // painted as a miss, so the counts are not its to read.
    #expect(Set(refusals.keys).isSubset(of: allowed), "refusals are named gates: \(refusals)")
    if !rsVerifying, [1, 2, 4].contains(arm.scale) { #expect(translated > 0, "a dyadic scale translates: \(translated), refused \(refusals)") }
    print("FS25 scale \(arm.scale) ax \(arm.accessibility): translated \(translated) refused \(refusals) redos \(redos)")
}

/// 2.1b — the three movements of 2.1 equal a fresh window after every frame (the retaining side may have translated; the
/// verify run compares each hit with a fresh run besides), with and without an accessibility client. Mutation: as 2.5.
struct FSShiftArm: CustomStringConvertible, Sendable {
    let kind: FSShift, scale: Float, accessibility: Bool
    var description: String { "\(kind) scale \(scale) accessibility \(accessibility)" }
}
let fsShiftArms = FSShift.allCases.flatMap { kind in
    [Float(1), 2, 4].flatMap { scale in [false, true].map { FSShiftArm(kind: kind, scale: scale, accessibility: $0) } }
}

@Test(arguments: fsShiftArms) @MainActor
func aShiftedCardStackEqualsAFreshWindow(arm: FSShiftArm) async throws {
    let kind = arm.kind, scale = arm.scale, accessibility = arm.accessibility
    let pair = try RPPair(size: sz(320, 400), scale: scale, warm: 4, accessibility: accessibility, graft: true) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: kind) }
    }
    try pair.compare("warm")
    var translated = 0
    for step in 0..<4 {
        pair.on.resetFrameWork()
        if kind == .scroll {
            for w in [pair.on, pair.off] { w.scroll(at: pt(160, 200), byDeltaX: 0, deltaY: step.isMultiple(of: 3) ? 30 : -30) }
        } else {
            for side in [pair.onSide, pair.offSide] { side.inputs.offset += kind == .header ? 4 : 1 }
        }
        await rsSettle()
        pair.redraw()
        translated += pair.stepWork.retainedTranslated
        try pair.compare("step \(step)")
    }
    if !rsVerifying { #expect(translated > 0, "the retaining side translated, or the differential proves nothing: \(translated)") }
}

// MARK: the registrations follow (2.6)

/// A card with one button whose rect a test reads by id and clicks.
struct FSClickCard: Component, @MainActor Equatable {
    let title: String
    let log: HarnessLog
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(80), height: Pixels(14))
            Button("go \(title)") { log.add("go \(title)") }.frame(width: Pixels(50), height: Pixels(18)).id("go-\(title)")
        }
        .padding(Edges(all: Pixels(4)))
    }
    static func == (l: FSClickCard, r: FSClickCard) -> Bool { l.title == r.title && l.log === r.log }
}

private struct FSClickRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Box().frame(height: Pixels(10 + side.inputs.offset)).background(.accent)
            ForEach(Array(0..<4), id: \.self) { k in FSClickCard(title: "c\(k)", log: side.log).equatable() }
        }
        .padding(Edges(all: Pixels(8)))
    }
}

/// 2.6 — after a header grew the cards (their prepaints replayed moved), a click at the button's **new** rect reaches it and a
/// click at its old rect does not; the logs, hitbox lists, element bounds (`frame(ofID:)`) and focus order equal a fresh window
/// (`FS-F`). The retaining side translated and replayed prepaint, or the click proves nothing. Mutations: the ledger's hitboxes
/// replayed unmoved (the click at the new rect misses, hitbox list differs), element bounds replayed unmoved (`frame(ofID:)`
/// differs from the fresh window's).
@Test(.enabled(if: !rsVerifying, fsTranslationVerifyingNote), arguments: [Float(1), 2], [false, true]) @MainActor
func aClickAfterAShiftReachesTheMovedButton(scale: Float, graft: Bool) async throws {
    let pair = try RPPair(size: sz(320, 400), scale: scale, warm: 4, accessibility: false, graft: graft) { side in
        VStack(spacing: 0) { FSClickRoot(side: side) }
    }
    try pair.compare("warm")
    var translated = 0, prepaintHits = 0
    for step in 0..<2 {
        pair.on.resetFrameWork()
        for side in [pair.onSide, pair.offSide] { side.inputs.offset += 4 }
        await rsSettle()
        pair.redraw()
        let f = pair.stepWork
        translated += f.retainedTranslated; prepaintHits += f.retainedPrepaintHits
        try pair.compare("shift \(step)")
    }
    #expect(translated >= 8 && prepaintHits >= 8, "the cards translated and replayed prepaint: \(translated), \(prepaintHits)")
    let was = try pair.off.frame(ofID: "go-c2"), now = try pair.on.frame(ofID: "go-c2")
    #expect(was == now, "element bounds follow the shift: \(was) vs \(now)")
    let center = Point(x: Pixels(now.origin.x.value + now.size.width.value / 2), y: Pixels(now.origin.y.value + now.size.height.value / 2))
    // 8 points down since the first frame: the old rect's centre is now over the card above's button or its padding.
    let stale = Point(x: center.x, y: Pixels(center.y.value - 8))
    for w in [pair.on, pair.off] { w.click(at: stale); w.click(at: center) }
    try pair.compare("after the clicks")
    #expect(pair.onSide.log.entries.contains("go c2"), "the button at its new rect was clicked: \(pair.onSide.log.entries)")
    #expect(pair.onSide.log.entries == pair.offSide.log.entries)
}

// MARK: fractional and resized (2.8, 2.9)

/// 2.9 — a shift that is not a whole number of device pixels is refused by name and the frame equals a fresh one: 1 point at
/// scale 1.5 is 1.5 pixels (`FS-M`; the add is exact in `Float` and draws different pixels, so exactness alone is not the gate).
/// A 4 point shift at 1.5 is 6 pixels and translates. Mutations: the whole-pixel test replaced by `true` (the 1 point arm
/// differs from the fresh window or the verify run traps), the reason string changed (the name pin).
@Test(arguments: [Float(1), 4]) @MainActor
func aFractionalShiftIsRefusedNotApproximated(step: Float) async throws {
    let pair = try RPPair(size: sz(320, 400), scale: 1.5, warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) { FSShiftSideRoot(side: side, kind: .header) }
    }
    var translated = 0, refusals: [String: Int] = [:]
    for index in 0..<3 {
        pair.on.resetFrameWork()
        for side in [pair.onSide, pair.offSide] { side.inputs.offset += step }
        await rsSettle()
        pair.redraw()
        let f = pair.stepWork
        translated += f.retainedTranslated
        refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        try pair.compare("step \(index) by \(step)")
    }
    if rsVerifying { return }
    if step == 1 {
        #expect(translated == 0, "no card translates by 1.5 pixels: \(translated)")
        #expect(refusals["fractionalTranslation", default: 0] >= 24, "refused by name: \(refusals)")
    } else {
        #expect(translated >= 24 * 3, "6 pixels is whole: \(translated)")
        #expect(refusals.isEmpty, "\(refusals)")
    }
}

private struct FSFlexCard: Component, @MainActor Equatable {
    let index: Int
    var content: some ElementGroup {
        Text("flex \(index)").frame(maxWidth: .infinity, alignment: .leading).frame(height: Pixels(20))
    }
}

/// 2.8 — the separating arm for the shape comparison: cards whose **size** changed (the window narrowed) hold equal values and
/// their record is valid, yet they are not a translation: no refusal is counted, nothing translates, they paint again
/// (`FS-D`: same node count and signature is not enough, the top rects' sizes are in the shape). Mutation: sizes left out of
/// `RetainedShape.shift` (the cards would replay the old width's pixels: the differential differs).
@Test(.enabled(if: !rsVerifying, fsTranslationVerifyingNote)) @MainActor
func aShiftThatAlsoResizesTheOccurrenceMisses() async throws {
    let pair = try RPPair(size: sz(320, 400), scale: 2, warm: 4, accessibility: false, graft: false) { _ in
        VStack(spacing: 2) { ForEach(Array(0..<6), id: \.self) { FSFlexCard(index: $0).equatable() } }
    }
    try pair.compare("warm")
    pair.on.resetFrameWork()
    for w in [pair.on, pair.off] { w.resize(to: sz(280, 400)) }
    await rsSettle()
    pair.redraw()
    let f = pair.stepWork
    #expect(f.retainedTranslated == 0 && f.retainedTranslationRefused == 0, "not a translation: \(f.retainedTranslated), \(f.retainedTranslationRefused)")
    try pair.compare("narrowed")
}

// MARK: every refusal has a name (2.7)

enum FSRefusal: CaseIterable, CustomStringConvertible {
    case gradient, path, backdrop, innerScope, maskStraddle, accessibility
    var description: String {
        switch self {
        case .gradient: "gradient"; case .path: "path"; case .backdrop: "backdrop"
        case .innerScope: "innerScope"; case .maskStraddle: "maskStraddle"; case .accessibility: "accessibility"
        }
    }
    var reason: String {
        switch self {
        case .gradient: "unlistedKind:gradient"; case .path: "unlistedKind:path"; case .backdrop: "unlistedKind:backdrop"
        case .innerScope: "innerScope"; case .maskStraddle: "maskStraddlesEntryClip"; case .accessibility: "accessibilityRecords"
        }
    }
}

private struct FSZigZag: Shape {
    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            let w = rect.size.width.value, h = rect.size.height.value
            path.move(to: Point(x: Pixels(0), y: Pixels(0)))
            path.addLine(to: Point(x: Pixels(w), y: Pixels(h / 2)))
            path.addLine(to: Point(x: Pixels(0), y: Pixels(h)))
            path.closeSubpath()
        }
    }
}

private struct FSRefusalCard: Component, @MainActor Equatable {
    let kind: FSRefusal
    let index: Int
    var content: some ElementGroup {
        switch kind {
        case .gradient:
            Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
                .frame(width: Pixels(60), height: Pixels(20))
        case .path:
            FSZigZag().fill(Color.red).frame(width: Pixels(60), height: Pixels(20))
        case .backdrop:
            Color.clear.frame(width: Pixels(60), height: Pixels(20)).background(.regularMaterial)
        case .innerScope:
            Color.red.frame(width: Pixels(60), height: Pixels(20)).offset(x: Pixels(2), y: Pixels(1))
        case .maskStraddle, .accessibility:
            Text("card \(index)").frame(width: Pixels(60), height: Pixels(20))
        }
    }
}

private struct FSRefusalRoot: Component {
    let side: RPSide
    let kind: FSRefusal
    var content: some ElementGroup {
        if kind == .maskStraddle {
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(Array(0..<6), id: \.self) { k in RPCard(title: "c\(k)", shade: k, log: side.log).equatable() }
                }
            }
            .frame(width: Pixels(300), height: Pixels(150))
        } else {
            VStack(spacing: 2) {
                Box().frame(height: Pixels(10 + side.inputs.offset))
                ForEach(Array(0..<3), id: \.self) { k in FSRefusalCard(kind: kind, index: k).equatable() }
            }
        }
    }
}

/// 2.7 — each thing a translation cannot carry refuses by its own name and the frame still equals a fresh window: a gradient, a
/// path and a backdrop (kinds off the allow-list), a paint scope opened inside the occurrence, a mask that may have been cut by
/// the entry clip (a rounded clip at the viewport's edge) and, with a client, accessibility records (`FS-F`). Mutation: the
/// allow-list widened to `true` (the three kind arms stop refusing; the differential differs on the gradient and path).
@Test(.enabled(if: !rsVerifying, fsTranslationVerifyingNote), arguments: FSRefusal.allCases) @MainActor
func everyUntranslatableKindRefusesByName(kind: FSRefusal) async throws {
    let pair = try RPPair(size: sz(320, 300), scale: 2, warm: 4, accessibility: kind == .accessibility, graft: false) { side in
        VStack(spacing: 0) { FSRefusalRoot(side: side, kind: kind) }
    }
    try pair.compare("warm")
    var refusals: [String: Int] = [:], translated = 0
    for index in 0..<3 {
        pair.on.resetFrameWork()
        if kind == .maskStraddle {
            for w in [pair.on, pair.off] { w.scroll(at: pt(150, 80), byDeltaX: 0, deltaY: -30) }
        } else {
            for side in [pair.onSide, pair.offSide] { side.inputs.offset += 4 }
        }
        await rsSettle()
        pair.redraw()
        let f = pair.stepWork
        refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        translated += f.retainedTranslated
        try pair.compare("step \(index)")
    }
    #expect(refusals[kind.reason, default: 0] > 0, "\(kind) refuses as \(kind.reason): \(refusals)")
    if kind != .maskStraddle && kind != .accessibility { #expect(translated == 0, "nothing of a \(kind) occurrence translates: \(translated)") }
}
