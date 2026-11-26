import Foundation
@testable import MetalUI
import MetalUIScene
import MetalUITesting
import MetalUITestSupport
import Testing

// Record 428 (`FS-W`): a retained paint record that moves along one axis only is moved when a leaf's number on the other axis is not a
// sixteenth. That axis does not move, the moved coordinate is the old value bit for bit, and no addition rounds; the axis that moves keeps
// both checks. Alloy's streaming transcript refused 236 records in 30 deltas for a text-measured x (`leaf=rect field=bounds.origin.x`) under
// moves of (0, -26), (0, -42) and (0, -91).

private let uaVerifyingNote: Comment =
    "METALUI_VERIFY_RETAINED=1 builds a replayed frame twice: the refusal counts are not its to read"

/// A card: a line of text whose second run has an inline background (Alloy's inline code). The portable text system measures in quarter points, so the
/// background's x is a quarter-point number (222.75 pt here) and its y a whole line; at scale 9/8 (a dyadic scale, every product exact in `Float`) a whole
/// point is 1.125 px and a quarter point 0.28125 px, which is no multiple of 1/16: the leaf's device x is the fractional number, its y is exact.
struct UACard: Component, @MainActor Equatable {
    let id: Int
    var content: some ElementGroup {
        Text(uaLine(id)).frame(width: Pixels(200), height: Pixels(20), alignment: .leading)
    }
}

func uaLine(_ id: Int) -> AttributedString {
    var head = AttributedString("card \(id) before ")
    head.foregroundColor = Color.primary
    var code = AttributedString("inline")
    code.backgroundColor = Color.accent.opacity(0.3)
    return head + code + AttributedString(" after")
}

private let uaScale: Float = 1.125

private struct UARoot: Component {
    let axis: Axis
    var content: some ElementGroup {
        if axis == .vertical {
            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(Array(0..<24), id: \.self) { i in UACard(id: i).equatable() }
                }
            }.frame(width: Pixels(300), height: Pixels(150))
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(0..<24), id: \.self) { i in UACard(id: i).equatable() }
                }
            }.frame(width: Pixels(300), height: Pixels(150))
        }
    }
}

/// Whole-pixel wheel steps over the scroller on both windows (scale 2, a step is whole points), compared with a fresh frame at each.
@MainActor private func uaScroll(axis: Axis, steps: [Float] = [8, 16, 8, 24]) async throws
    -> (reasons: [String: Int], translated: Int) {
    let pair = try RPPair(size: sz(320, 400), scale: uaScale, warm: 4, accessibility: false, graft: true) { _ in
        VStack(spacing: 0) { UARoot(axis: axis) }
    }
    var reasons: [String: Int] = [:]
    var translated = 0
    for d in steps {
        pair.on.resetFrameWork()
        for w in [pair.on, pair.off] {
            w.scroll(at: pt(160, 200), byDeltaX: axis == .horizontal ? -d : 0, deltaY: axis == .vertical ? -d : 0)
        }
        await rsSettle(); pair.redraw()
        reasons.merge(pair.stepWork.retainedTranslationRefusedReasons, uniquingKeysWith: +)
        translated += pair.stepWork.retainedTranslated
        try pair.compare("a \(axis) step of \(d)")
    }
    return (reasons, translated)
}

/// A rect leaf at a fractional x inside a vertical scroller moved by whole pixels is moved, not painted again, and the frame equals a fresh one.
/// Mutation: `movedLeaf`'s `exactMove` testing both axes of the origin whatever the shift (the old check) refuses every row `inexactTranslation`.
@Test @MainActor
func aLeafAtAFractionalXIsMovedByAVerticalScroll() async throws {
    let (reasons, translated) = try await uaScroll(axis: .vertical)
    // Verify mode builds a replayed frame twice (the counts are not its to read) and compares it with a fresh one: the compare inside `uaScroll` runs.
    if !rsVerifying {
        #expect(reasons["inexactTranslation", default: 0] == 0 && reasons["fractionalTranslation", default: 0] == 0, "refused: \(reasons)")
        #expect(translated > 0, "rows moved and replayed translated, or the test reads nothing")
    }
}

/// A fractional x under a horizontal move is a move along x: the axis that moves keeps both checks, so the rows still refuse `inexactTranslation`
/// (and the frame equals a fresh one). A fractional y under a vertical move is the same rule on the other axis, pinned by the helper test below:
/// the portable text system gives no fractional y, a line is a whole point.
@Test @MainActor
func aLeafAtAFractionalXIsStillRefusedByAHorizontalScroll() async throws {
    let (reasons, _) = try await uaScroll(axis: .horizontal)
    if !rsVerifying { #expect(reasons["inexactTranslation", default: 0] > 0, "refused as inexact: \(reasons)") }
}

/// The helpers: a zero shift passes whatever the number and returns it bit for bit where it is free; a moving axis needs both ends on a sixteenth;
/// and the skip is the frame's at a scale that is a multiple of 1/16 only (at 1.2 the unmoved axis keeps its check, `anInexactCoordinateIsRefusedNotApproximated`).
@Test @MainActor
func aZeroShiftIsExactAndReturnsTheValueItself() {
    #expect(isExactShift(369.356445, by: 0, free: true) && shifted(369.356445, by: 0).bitPattern == Float(369.356445).bitPattern)
    #expect(shifted(-0.0, by: 0).sign == .minus, "no addition: negative zero stays")
    #expect(!isExactShift(369.356445, by: 0, free: false), "not free: the old check")
    #expect(!isExactShift(369.356445, by: -26, free: true) && !isExactShift(10, by: 0.3, free: true) && isExactShift(10.5, by: -26, free: true))
    for (scale, free) in [(Float(1), true), (2, true), (1.125, true), (1.5, true), (1.2, false), (1.1, false), (4.0 / 3.0, false)] {
        #expect(isUnmovedAxisFree(scale: scale) == free, "scale \(scale)")
    }
}

// MARK: a streaming transcript with inline backgrounds

/// A row of the record 416 transcript (tinted rounded chrome around two paragraphs) whose first paragraph carries an inline background.
struct UATranscriptRow: Component, @MainActor Equatable {
    let id: Int
    let tail: String
    var content: some ElementGroup {
        VStack(alignment: .leading, spacing: 6) {
            Text(uaLine(id) + AttributedString(tail)).frame(maxWidth: .infinity, alignment: .leading)
            CTParagraph(text: "second paragraph \(id)").equatable()
        }
        .padding(Edges(all: Pixels(8)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.18 + 0.04 * Double(id % 3)))
        .cornerRadius(Pixels(8))
    }
}

struct UATranscriptRoot: Component {
    let side: RPSide
    var content: some ElementGroup {
        let rows = (0..<50).map { UATranscriptRow(id: $0, tail: " and a tail that wraps onto more than one line in a narrow column") }
            + [UATranscriptRow(id: 999, tail: ctText(Int(side.inputs.offset)))]
        ScrollViewReader { _ in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Pixels(10)) {
                    ForEach(rows, id: \.id) { row in row.equatable() }
                }.padding(g49Inset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Alloy's shape: a transcript of record 416 (chrome rows in a lazy stack, from the top: an offset of a multiple of 8 pt is exact in `Float`) with an inline background in every row, at a scale where
/// the background's text-measured x is no sixteenth (the portable text system measures 162.35774 at 9/8), wheeled by whole device pixels (8 pt is
/// 9 px; a streamed word's anchor move is a whole-point layout move, which is no whole pixel at this scale, so the stream itself is not driven here).
/// The frame equals a fresh one at every step; the figures the record quotes (requests a step, allocations a step, what refuses) are printed.
@Test @MainActor
func aWheeledTranscriptWithInlineBackgroundsMovesItsRows() async throws {
    let pair = try RPPair(size: sz(420, 600), scale: uaScale, warm: 8, accessibility: false) { side in
        VStack(spacing: 0) { UATranscriptRoot(side: side) }
    }
    var reasons: [String: Int] = [:]
    var translated = 0, requests = 0, allocations = 0
    let steps: [Float] = [8, 16, 8, 24, 8, 16, 8, 8, 16, 24, 8, 16]
    for d in steps {
        pair.on.resetFrameWork()
        for w in [pair.on, pair.off] { w.scroll(at: pt(210, 300), byDeltaX: 0, deltaY: -d) }
        await rsSettle()
        #if canImport(Darwin)
        let p = try #require(profileAllocations { pair.redraw() })
        allocations += p.allocations
        #else
        pair.redraw()
        #endif
        for f in pair.on.frameWork {
            reasons.merge(f.retainedTranslationRefusedReasons, uniquingKeysWith: +)
            translated += f.retainedTranslated
            requests += f.elementRequests
        }
        try pair.compare("a wheel step of \(d)")
    }
    print("UA transcript: requests/step \(Double(requests) / Double(steps.count)) allocations/step \(allocations / steps.count) translated \(translated) refused \(reasons)")
    if !rsVerifying { #expect(reasons["inexactTranslation", default: 0] == 0 && translated > 0, "translated \(translated), refused: \(reasons)") }
}
