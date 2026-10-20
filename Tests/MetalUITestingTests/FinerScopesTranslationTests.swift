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
