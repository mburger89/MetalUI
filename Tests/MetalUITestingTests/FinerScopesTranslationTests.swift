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
    for f in frames {
        #expect(f.retainedTranslated >= 23, "rows replayed translated: \(f.retainedTranslated)")
        #expect(f.retainedHits >= 23, "rows hit at paint: \(f.retainedHits)")
        #expect(f.elementPaints < 60, "element paints: \(f.elementPaints)")
        #expect(f.retainedRedos == 0)
    }
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
        step([pair.onSide, pair.offSide], [pair.on, pair.off])
        await rsSettle()
        pair.redraw()
        for f in pair.frames.suffix(1) {
            translated += f.retainedTranslated; redos += f.retainedRedos
            refusals.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        }
        try pair.compare("step \(index) (\(name))")
        pair.redraw()   // the settle frame
        try pair.compare("step \(index) settled")
    }
    let allowed: Set<String> = ["accessibilityRecords", "inexactTranslation", "fractionalTranslation", "hitboxClipped", "maskStraddlesEntryClip"]
    // Under `METALUI_VERIFY_RETAINED=1` the differential still runs (every hit is also compared with a fresh run), but a hit is
    // painted as a miss, so the counts are not its to read.
    #expect(Set(refusals.keys).isSubset(of: allowed), "refusals are named gates: \(refusals)")
    if !rsVerifying, [1, 2, 4].contains(arm.scale) { #expect(translated > 0, "a dyadic scale translates: \(translated), refused \(refusals)") }
    print("FS25 scale \(arm.scale) ax \(arm.accessibility): translated \(translated) refused \(refusals) redos \(redos)")
}

/// 2.1b — the three movements of 2.1 equal a fresh window after every frame (the retaining side may have translated; the
/// verify run compares each hit with a fresh run besides). Mutation: as 2.5.
@Test(arguments: FSShift.allCases, [Float(1), 2, 4]) @MainActor
func aShiftedCardStackEqualsAFreshWindow(kind: FSShift, scale: Float) async throws {
    var models: [ObjectIdentifier: FSShiftModel] = [:]
    let pair = try RPPair(size: sz(320, 400), scale: scale, warm: 4, accessibility: false, graft: true) { side in
        let model = FSShiftModel()
        models[ObjectIdentifier(side)] = model
        return VStack(spacing: 0) { FSShiftRoot(model: model, kind: kind) }
    }
    let on = try #require(models[ObjectIdentifier(pair.onSide)]), off = try #require(models[ObjectIdentifier(pair.offSide)])
    try pair.compare("warm")
    for step in 0..<4 {
        for model in [on, off] {
            switch kind {
            case .insertFront: model.ids.insert(100 + step, at: 0)
            case .header: model.header += 4
            case .scroll: break
            }
        }
        if kind == .scroll { for w in [pair.on, pair.off] { w.scroll(at: pt(160, 200), byDeltaX: 0, deltaY: step.isMultiple(of: 3) ? 30 : -30) } }
        await rsSettle()
        pair.redraw()
        try pair.compare("step \(step)")
    }
}
