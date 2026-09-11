import CoreText
import Foundation
import Testing
import MetalUICore
import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

// Finding B-6, at the consumer: what a hard line break did to `Text`'s
// max-content answer and to where a centring `Column` put the label.
//
// Oracles are CoreText's, reached without `Shaper` (shape 12), exactly as in
// `TextMeasureTests.swift`, whose private helpers these repeat.

private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

private let ctFontKey = NSAttributedString.Key(kCTFontAttributeName as String)

private func ctAdvance(_ text: String) -> Double {
    let attributed = NSAttributedString(string: text, attributes: [ctFontKey: font.ctFont])
    return CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil)
}

private func ctLineHeight() -> Double {
    let f = font.ctFont
    return ceil(Double(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)))
}

/// Three lines, the widest first, so the sum of the segments (75.004 at 13pt)
/// and their maximum (37.565) are far apart.
private let threeLines = "Ready\nSet\nGo"

/// **`.maxContent` of a label with hard breaks is its widest line, three lines
/// tall — not the sum of its lines, one line tall.**
///
/// Before the fix `textMeasure` answered 75.004 × 16 for this label: the one
/// `CTLine` the unwrapped shaper built laid `"Ready"`, `"Set"` and `"Go"` side
/// by side, so the width was the sum and the height a single line. Every
/// `.definite` width at or above 37.565 already answered 37.565 × 48.
///
/// **And through the engine**, where the over-report was visible. A centring
/// `Column` (EP-8) sizes its child's inline axis fit-content, which is
/// `min(max(min-content, offered), max-content)` — so max-content is the
/// answer whenever the column is wider than the label. Measured before the fix,
/// at 400 wide: the label's box was **76 wide and 48 tall** — the height
/// already three lines, because the engine asks for it at a definite width —
/// so the box itself was centred and a box-centre assertion passed. The ink was
/// not: `Text.paint` re-wraps at the measured width and lays every line from
/// the box's left edge, so `"Ready"`, the widest line, sat centred on ~181
/// rather than 200. The assertion below is therefore on the widest line's
/// centre, not the box's.
@MainActor
@Test func aLabelWithHardBreaksMeasuresItsWidestLineAtMaxContent() {
    let font = font
    let cache = ShapingCache()
    let widest = ctAdvance("Ready")
    let lineHeight = ctLineHeight()

    // The arms disagree: this is a sample the defect is visible in.
    #expect(ctAdvance(threeLines) > widest + 30)

    let maxContent = textMeasure(threeLines, font: font, cache: cache,
                                 known: .unspecified, available: .maxContent)
    #expect(abs(maxContent.width - widest) < 0.001)
    #expect(abs(maxContent.height - 3 * lineHeight) < 0.001)

    // Max-content agrees with a generous definite width, as it does for a
    // label with no hard break.
    let wide = textMeasure(threeLines, font: font, cache: cache,
                           known: .unspecified, available: .definite(400))
    #expect(abs(maxContent.width - wide.width) < 0.001)
    #expect(abs(maxContent.height - wide.height) < 0.001)

    // Through a centring column 400 wide.
    let frame = Frame(contentSize: Size(width: Pixels(400), height: Pixels(600)),
                      scaleFactor: 1, stateTable: StateTable(), shapingCache: cache)
    var column = Column { Text(threeLines) }
    var pass = LayoutPass(frame: frame)
    let (root, _) = column.requestLayout(GlobalElementID.child(of: nil, at: 0, name: nil),
                                         pass: &pass)
    frame.computeRootLayout(root: root)
    let rect = frame.tree.layout(frame.tree.children(root)[0])

    // Pixel rounding moves each edge by at most half a point, so the rounded
    // box is within 1 of the oracle width, and the widest line — laid from the
    // box's left edge — is centred within 1 of the column's centre.
    #expect(abs(rect.width - widest) <= 1)
    #expect(abs(rect.x + widest / 2 - 200) <= 1)
    #expect(rect.height == (3 * lineHeight).rounded())
}
