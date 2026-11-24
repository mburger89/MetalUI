import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeStyle` faces (ruling `CV-BY`, record 396): `italic` and `weight` on a style, drawn with the font's real faces.
// PLAIN imports; text is the harness's Noto Sans through `PortableTextSystem`.

private let red = Color(red: 1, green: 0, blue: 0)

/// **1** A style carries italic and weight, equal styles share an id, differing faces do not, and the id reads
/// the faces back. **Mutation:** `self.italic = italic` removed from the init (an italic style reads `nil`
/// and shares the plain style's id).
@Test @MainActor func aStyleCarriesItalicAndWeightAndInternsThem() {
    let decorations = CodeDecorations(buffer: CodeBuffer("a\n"))
    let plain = decorations.register(CodeStyle(foreground: red))
    let italic = decorations.register(CodeStyle(foreground: red, italic: true))
    let bold = decorations.register(CodeStyle(foreground: red, weight: .bold))
    let both = decorations.register(CodeStyle(foreground: red, italic: true, weight: .bold))
    #expect(Set([plain, italic, bold, both]).count == 4)
    #expect(decorations.register(CodeStyle(foreground: red, italic: true, weight: .bold)) == both)
    #expect(decorations.style(plain).italic == nil && decorations.style(plain).weight == nil)
    #expect(decorations.style(italic).italic == true && decorations.style(italic).weight == nil)
    #expect(decorations.style(bold).weight == .bold && decorations.style(bold).italic == nil)
    #expect(decorations.style(both).italic == true && decorations.style(both).weight == .bold)
    #expect(decorations.register(CodeStyle(italic: false)) != decorations.register(CodeStyle()), "false is a setting, nil is none")
}

private let blue = Color(red: 0, green: 0, blue: 1)

@MainActor private func set(_ decorations: CodeDecorations, _ buffer: CodeBuffer, _ runs: [(Range<Int>, CodeStyle)],
                            layer: CodeHighlightLayer) {
    let coded = runs.map { CodeStyleRun(range: $0.0, style: decorations.register($0.1)) }
    decorations.setHighlights(coded, in: 0..<buffer.utf8Count, layer: layer, asOf: buffer.version)
}

/// **2** For each stretch the highest layer that sets `italic` wins it, and likewise `weight`, each independently
/// of `foreground`; a higher `italic: false` turns the slope off; a layer that sets neither lets the one below through.
/// **Mutation:** the first layer to set a face keeps it (`if italic == nil { italic = i }`) so the lowest layer wins.
@Test @MainActor func theHighestLayerThatSetsAFaceWinsPerStretch() {
    let buffer = CodeBuffer(String(repeating: "a", count: 30) + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    set(decorations, buffer, [(0..<20, CodeStyle(foreground: red, italic: true, weight: .bold))], layer: .syntax)
    set(decorations, buffer, [(8..<12, CodeStyle(italic: false)), (16..<24, CodeStyle(foreground: blue))], layer: .semantic)
    set(decorations, buffer, [(10..<14, CodeStyle(weight: .light))], layer: .diagnostics)
    let got = decorations.paintedRuns(in: 0..<30).map { ($0.range, $0.style.foreground, $0.style.italic, $0.style.weight) }
    let want: [(Range<Int>, Color?, Bool?, Font.Weight?)] = [
        (0..<8, red, true, .bold), (8..<10, red, nil, .bold), (10..<12, red, nil, .light), (12..<14, red, true, .light),
        (14..<16, red, true, .bold), (16..<20, blue, true, .bold), (20..<24, blue, nil, nil),
    ]
    #expect(got.count == want.count && zip(got, want).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 && $0.3 == $1.3 },
            "\(got)")
    // The partition splits where a face changes even though the colour does not (0..<8 / 8..<10 are both red).
    let parts = decorations.stylingOfLine(0..<30).foreground
    #expect(parts.map(\.bytes) == [8, 2, 2, 2, 2, 4, 4, 6], "\(parts.map(\.bytes))")
    #expect(Set(parts.map(\.face)).count == 5 && parts.first!.face != 0 && parts.last!.face == 0)
}

/// **3** A partition with no faces digests as it did before faces existed: the literal is the digest master computes
/// for 3 bytes of style 0, 5 unstyled and 1 of style 1, and it holds on a decorations that has faces on another row.
/// **Mutation:** the face term mixed into the digest for every part, not only a part with a face.
@Test @MainActor func aFaceFreePartitionDigestsAsBefore() {
    let buffer = CodeBuffer("let x = 1\nlet y = 2\n")
    let decorations = CodeDecorations(buffer: buffer)
    set(decorations, buffer, [(0..<3, CodeStyle(foreground: red)), (8..<9, CodeStyle(foreground: blue))], layer: .syntax)
    let first = buffer.snapshot().lineRange(0)
    #expect(decorations.stylingOfLine(first).digest == 0xA11D_AC70_9782_B74F, "\(String(decorations.stylingOfLine(first).digest, radix: 16))")
    #expect(!decorations.hasFaces)
    set(decorations, buffer, [(10..<13, CodeStyle(italic: true))], layer: .semantic)
    #expect(decorations.hasFaces)
    #expect(decorations.stylingOfLine(first).digest == 0xA11D_AC70_9782_B74F, "a row with no face keeps master's digest")
    #expect(decorations.stylingOfLine(buffer.snapshot().lineRange(1)).foreground.contains { $0.face != 0 })
}

/// **11** `paintedRuns` reports the face that wins: a stretch with only a face is a run, italic and weight read back,
/// `italic: false` and `.regular` report nothing, equal neighbours join, and a colour under a face keeps both.
/// **Mutation:** the face left out of the painted style (`painted.italic` never set).
@Test @MainActor func paintedRunsReportTheWinningFace() {
    let buffer = CodeBuffer(String(repeating: "b", count: 20) + "\n")
    let decorations = CodeDecorations(buffer: buffer)
    set(decorations, buffer, [(0..<4, CodeStyle(italic: true)), (4..<8, CodeStyle(italic: true)), (8..<10, CodeStyle(weight: .semibold)),
                              (10..<12, CodeStyle(italic: false, weight: .regular)), (12..<16, CodeStyle(foreground: red, italic: true, weight: .black))],
        layer: .syntax)
    let got = decorations.paintedRuns(in: 0..<20)
    #expect(got.map(\.range) == [0..<8, 8..<10, 12..<16], "\(got.map(\.range))")
    #expect(got[0].style == CodeStyle(italic: true))
    #expect(got[1].style == CodeStyle(weight: .semibold))
    #expect(got[2].style == CodeStyle(foreground: red, italic: true, weight: .black))
}
