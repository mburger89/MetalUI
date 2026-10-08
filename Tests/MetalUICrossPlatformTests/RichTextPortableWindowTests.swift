import Foundation
import Testing
import MetalUIPortableText
import MetalUIScene
import MetalUITextSystem
@testable import MetalUI

// Rich text, lane 2 — a styled `Text` drawn through the portable text system
// (spec §4.2 test 2.26). Runs on Linux and Windows CI too: this is the path
// those platforms draw.

private let fontURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Fonts/NotoSans-Regular.ttf")

/// The requirement a deprecated witness answers without a warning at the call
/// (`RT-O` item 9, `LR-CV`).
@MainActor
private protocol PortableConcatenating {
    func concatenate(_ parts: [Text]) -> Text
}

private struct PortablePlus: PortableConcatenating {
    @available(*, deprecated, message: "calls the deprecated Text + Text on purpose: it is the subject of test 2.26 (RT-E, RT-O item 9)")
    func concatenate(_ parts: [Text]) -> Text { parts.dropFirst().reduce(parts[0]) { $0 + $1 } }
}

@MainActor
private func concatenate<C: PortableConcatenating>(_ witness: C, _ parts: [Text]) -> Text {
    witness.concatenate(parts)
}

private func same(_ color: MUIHsla, _ expected: Hsla) -> Bool {
    color.h == expected.h && color.s == expected.s && color.l == expected.l && color.a == expected.a
}

/// **2.26**. A headless frame over `PortableTextSystem` (Noto Sans) draws a
/// styled text: `ab` red, `cd` blue, and one green underline across both at
/// Noto Sans's own underline position and thickness, below the line's
/// baseline from the text's box (its background's origin). Red before: the
/// stub drew every glyph in one colour and no underline. Mutation: as 2.4
/// (colour every glyph with run 0's colour).
@MainActor
@Test func aStyledTextDrawsThroughThePortableSystem() throws {
    let system = PortableTextSystem(resolver: try PortableFontResolver(defaultFont: [UInt8](Data(contentsOf: fontURL))))
    let text = concatenate(PortablePlus(), [Text("ab").foregroundColor(.red), Text("cd").foregroundColor(.blue)])
        .underline(color: .green)
        .background(.surface)
    let frame = Frame(contentSize: Size(width: Pixels(200), height: Pixels(200)), scaleFactor: 1, textSystem: system)
    var root = text
    frame.render(&root)
    let glyphs = frame.scene.glyphs
    try #require(glyphs.count == 4, "four glyphs: \(glyphs.count)")
    let red = frame.resolve(.red), blue = frame.resolve(.blue), green = frame.resolve(.green)
    #expect(same(glyphs[0].color, red) && same(glyphs[1].color, red)
                && same(glyphs[2].color, blue) && same(glyphs[3].color, blue),
            "two colours: \(glyphs.map(\.color))")

    let box = try #require(frame.scene.rects.first { same($0.background, frame.resolve(.surface)) })
    let underlines = frame.scene.rects.filter { same($0.background, green) }
    try #require(underlines.count == 1, "one underline: \(underlines.count)")
    let key = system.resolveFont(FontDescriptor(size: 13))
    let face = system.decorationMetrics(key)
    let line = try #require(system.measure(StyledText("abcd", style: TextRunStyle(font: key)), wrappingAt: nil,
                                           options: TextLayoutOptions()).lines.first)
    let expectedY = Double(box.bounds.origin.y) + line.baseline - face.underlinePosition - face.underlineThickness / 2
    #expect(abs(Double(underlines[0].bounds.origin.y) - expectedY) < 1e-3
                && abs(Double(underlines[0].bounds.size.height) - face.underlineThickness) < 1e-3,
            "at Noto Sans's geometry: y \(underlines[0].bounds.origin.y) vs \(expectedY), h \(underlines[0].bounds.size.height) vs \(face.underlineThickness)")
    #expect(abs(Double(underlines[0].bounds.origin.x - box.bounds.origin.x) - line.visibleMinX) < 1e-3
                && abs(Double(underlines[0].bounds.size.width) - (line.visibleMaxX - line.visibleMinX)) < 1e-3,
            "across the visible extent: \(underlines[0].bounds), line \(line)")
}
