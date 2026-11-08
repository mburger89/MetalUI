import MetalUI
import MetalUIScene
import MetalUITesting
import Foundation
import Testing

// A two-axis scroller under retained replay (Alloy gap G5, ruling `XS-L`; `RK-`, `FS-D`). The ledger key's scroller vector holds the
// offset at index 7 and, appended, a two-axis scroller's horizontal offset and extent at 10 and 11; K2 (`FS-D`) translates a settled
// occurrence by the offset it moved, so BOTH offsets are set aside when two keys are compared.

/// A card of text and a bar: no handler, no menu (a card with a context menu refuses translation under any scroller).
struct XSCard: Component, @MainActor Equatable {
    let title: String
    var content: some ElementGroup {
        VStack(spacing: 2) {
            Text(title).frame(width: Pixels(80), height: Pixels(14))
            Box().frame(width: Pixels(60), height: Pixels(8)).background(.accent)
        }
    }
    static func == (l: XSCard, r: XSCard) -> Bool { l.title == r.title }
}

/// **Z8** (`XS-L`). Six equatable cards (`XSCard`) in a 60 x 100 two-axis scroller (the cards are 80 wide, so both axes scroll) are wheeled
/// down, across, down, back and down: after every step the retaining window equals the retention-off one (scene, hitboxes,
/// tallies), the cards replayed their prepaint (`retainedPrepaintHits > 0`: a differential that replays nothing proves
/// nothing) and no translation was refused. **Mutation:** `PrepaintExtras.zeroScrollOffsets` not zeroing index 10 (the horizontal
/// offset stays in the key): every `dx` step misses, the hits of those steps are 0 and the key differences name
/// `ledgerKey.extras.scroller`.
@Test(.enabled(if: !rsVerifying, "METALUI_VERIFY_RETAINED=1 builds a prepaint-replayed frame twice and presents the second: the prepaint counts this test pins are not its to read")) @MainActor
func aDiagonallyScrolledTwoAxisScrollerReplaysItsCardsTranslated() async throws {
    let pair = try RPPair(size: sz(160, 120), warm: 4, accessibility: false, graft: false) { side in
        VStack(spacing: 0) {
            ScrollView([.horizontal, .vertical]) {
                VStack(spacing: 4) {
                    for index in 0..<6 { XSCard(title: "c\(index)").equatable() }
                }
            }
            .frame(width: Pixels(60), height: Pixels(100))
        }
    }
    try pair.compare("warm")
    pair.redraw()
    try #require((pair.frames.last?.retainedPrepaintHits ?? 0) > 0, "the cards replay at rest: \(String(describing: pair.frames.last))")
    var xSteps = 0, xHits = 0, ySteps = 0, yHits = 0, refused = 0
    for (index, step) in [(0, -10), (-6, 0), (0, -15), (3, 0), (0, 8), (-4, 0)].enumerated() {
        let dx = Float(step.0), dy = Float(step.1)
        for w in [pair.on, pair.off] { w.scroll(at: pt(80, 50), byDeltaX: dx, deltaY: dy) }
        let f = pair.on.lastFrameWork   // the frame the wheel itself drew
        await rsSettle()
        pair.redraw()
        if dx != 0 { xSteps += 1; xHits += f.retainedPrepaintHits } else { ySteps += 1; yHits += f.retainedPrepaintHits }
        refused += f.retainedTranslationRefused
        try pair.compare("step \(index) (\(dx), \(dy))")
    }
    #expect(yHits == 3 * 6 && xHits == 3 * 6, "the cards replay translated after a vertical (\(yHits) over \(ySteps)) and a horizontal (\(xHits) over \(xSteps)) step: six cards per step")
    #expect(refused == 0, "no translation is refused: \(refused)")
}
