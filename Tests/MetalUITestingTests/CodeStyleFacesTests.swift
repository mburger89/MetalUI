import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUIPortableText
import MetalUITesting
@testable import MetalUI

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

// MARK: Shaping in the real faces

private func fontBytes(_ name: String) -> [UInt8] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fonts/\(name).ttf")
    guard let data = try? Data(contentsOf: url) else { preconditionFailure("Tests/Fonts/\(name).ttf is missing") }
    return [UInt8](data)
}

/// Noto Sans Regular, Bold and Italic: a family with real faces. Kept out of `harnessTextSystem`, so no other test's
/// `.bold()` or `.italic()` result changes.
@MainActor private func facesTextSystem(bold: Bool = true, italic: Bool = true) -> any TextSystem {
    guard let resolver = try? PortableFontResolver(defaultFont: harnessFontBytes) else { preconditionFailure("Noto Sans did not load") }
    if bold { try! resolver.register(fontBytes("NotoSans-Bold")) }
    if italic { try! resolver.register(fontBytes("NotoSans-Italic")) }
    return PortableTextSystem(resolver: resolver)
}

private func descriptor(italic: Bool = false, weight: Font.Weight? = nil) -> FontDescriptor {
    FontDescriptor(family: nil, size: 12, weight: weight?.value, italic: italic, design: .monospaced)
}

@MainActor private struct Faced {
    let window: TestWindow
    let buffer: CodeBuffer
    let decorations: CodeDecorations
    let geometry: CodeViewGeometry
    let system: any TextSystem
    /// The x of every glyph on display row `row`, left to right, in points, and their widths.
    func glyphs(row: Int) -> [(x: Float, width: Float, y: Float)] {
        let pitch = codePitch(scale: 1)
        return window.scene.glyphs.filter { $0.bounds.origin.y >= Float(row) * pitch - 4 && $0.bounds.origin.y < Float(row + 1) * pitch }
            .map { (x: $0.bounds.origin.x, width: $0.bounds.size.width, y: $0.bounds.origin.y) }.sorted { $0.x < $1.x }
    }
    func redraw() { window.window.setNeedsRedraw(); window.tick() }
}

@MainActor private func faced(_ text: String, system makeSystem: @escaping @MainActor @Sendable () -> any TextSystem = { facesTextSystem() },
                              setup: (CodeBuffer, CodeDecorations) -> Void = { _, _ in }) throws -> Faced {
    let buffer = CodeBuffer(text)
    let decorations = CodeDecorations(buffer: buffer)
    setup(buffer, decorations)
    let geometry = CodeViewGeometry()
    let window = try TestWindow(size: sz(400, 120), textSystem: makeSystem) {
        CodeView(buffer: buffer, decorations: decorations).font(size: 12).showsLineNumbers(false).codeCaretBlink(.off).geometry(geometry)
    }
    return Faced(window: window, buffer: buffer, decorations: decorations, geometry: geometry, system: makeSystem())
}

private let sentence = "go The quick brown fox jumps over tail"

/// **7** An italic run is shaped in the italic face: its glyphs are not the regular ones, the glyphs before it are, and
/// the text after it moves by the italic face's advance (measured on the text system) and nothing else.
/// **Mutation:** `closeRun` always uses the view font, so every run is shaped in the regular face.
@Test @MainActor func anItalicRunShapesInTheItalicFace() throws {
    let plain = try faced(sentence)
    let run = 3..<22   // "The quick brown fox"
    let slanted = try faced(sentence, setup: { buffer, decorations in
        decorations.setHighlights([CodeStyleRun(range: run, style: decorations.register(CodeStyle(italic: true)))],
                                  in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
    })
    let before = plain.glyphs(row: 0), after = slanted.glyphs(row: 0)
    #expect(before.count == after.count && before.count > 20, "\(before.count) \(after.count)")
    #expect(zip(before, after).prefix(2).allSatisfy { $0.x == $1.x && $0.width == $1.width }, "glyphs before the run are the regular ones")
    #expect(zip(before, after).dropFirst(2).prefix(19).contains { $0.width != $1.width || $0.x != $1.x }, "the run's glyphs are not")
    let regular = plain.system.resolveFont(descriptor()), italic = plain.system.resolveFont(descriptor(italic: true))
    #expect(regular != italic, "the fixture's family has an italic face")
    let text = String(sentence.dropFirst(3).prefix(19))
    let expected = Float(plain.system.measure(text, font: italic, wrappingAt: nil).widestLine
                         - plain.system.measure(text, font: regular, wrappingAt: nil).widestLine)
    let moved = (after.last!.x - before.last!.x)
    #expect(abs(expected) > 2 && abs(moved - expected) <= 1.5, "the tail moved \(moved), the faces differ by \(expected)")
}

/// **8** A bold run's caret, hit and range rectangles follow the bold face's shaped advances (the family is
/// proportional, so a grid would be wrong): the rectangle of each stretch is as wide as the text system measures it in
/// its own face, a press in the bold run lands on the grapheme under it, and the caret after it sits where the run ends.
/// **Mutation:** the per-run caret offsets taken from the view font (`runFont` always `font`).
@Test @MainActor func aBoldRunKeepsCaretHitAndSelectionOnItsShapedAdvances() throws {
    let text = "iiiiWWWWWWmmmmmmiiii"
    let fx = try faced(text, setup: { buffer, decorations in
        decorations.setHighlights([CodeStyleRun(range: 4..<16, style: decorations.register(CodeStyle(weight: .bold)))],
                                  in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
    })
    let regular = fx.system.resolveFont(descriptor()), bold = fx.system.resolveFont(descriptor(weight: .bold))
    #expect(regular != bold)
    func width(_ s: String, _ font: FontKey) -> Float { Float(fx.system.measure(s, font: font, wrappingAt: nil).widestLine) }
    let lead = try #require(fx.geometry.rects(for: 0..<4).first), run = try #require(fx.geometry.rects(for: 4..<16).first)
    let x0 = lead.origin.x.value
    #expect(abs(lead.size.width.value - width("iiii", regular)) <= 1.01, "\(lead.size.width.value)")
    #expect(abs(run.size.width.value - width("WWWWWWmmmmmm", bold)) <= 1.01, "\(run.size.width.value) vs bold \(width("WWWWWWmmmmmm", bold)) regular \(width("WWWWWWmmmmmm", regular))")
    #expect(abs(width("WWWWWWmmmmmm", bold) - width("WWWWWWmmmmmm", regular)) > 4, "the fixture would not tell a grid from shaped advances")
    #expect(abs(run.origin.x.value - x0 - width("iiii", regular)) <= 1.01)
    // A press on the third bold letter selects the boundary and grapheme under it.
    let third = try #require(fx.geometry.rects(for: 6..<7).first)
    let hit = try #require(fx.geometry.hit(at: pt(third.origin.x.value + third.size.width.value / 2, 6)))
    #expect(hit.character == 6..<7, "\(hit)")
    #expect(abs(third.size.width.value - (width("WWW", bold) - width("WW", bold))) <= 1.01)
    // The caret after the run, and the run after it.
    fx.buffer.select(16..<16)
    fx.redraw()
    let caret = try #require(fx.geometry.caretRect())
    #expect(abs(caret.origin.x.value - x0 - width("iiii", regular) - width("WWWWWWmmmmmm", bold)) <= 1.01, "\(caret.origin.x.value)")
}

/// **9** A line with faces sits on the view font's baseline: its glyphs' baselines are the plain line's, and when a
/// face has another ascent the glyphs are put back on the view font's baseline rather than where the face's own line
/// puts them. **Mutation:** the baseline shift left at 0.
@Test @MainActor func aFacedLineSitsOnTheViewFacesBaseline() throws {
    let plain = try faced(sentence)
    let slanted = try faced(sentence, setup: { buffer, decorations in
        decorations.setHighlights([CodeStyleRun(range: 3..<22, style: decorations.register(CodeStyle(italic: true, weight: .bold)))],
                                  in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
    })
    let a = plain.glyphs(row: 0), b = slanted.glyphs(row: 0)
    #expect(a.count == b.count && Set(a.map(\.y)).count > 0)
    #expect(zip(a, b).filter { $0.width != $1.width }.count > 5, "the run really is another face")
    #expect(zip(a, b).allSatisfy { abs($0.y + 0 - $1.y) <= 1 || $0.width != $1.width }, "glyphs of the same size are at the same height")
    // Noto's faces share one ascent, so also drive the shift directly: a face whose line starts lower than the view font's.
    let system = facesTextSystem()
    let base = system.resolveFont(descriptor()), bold = system.resolveFont(descriptor(weight: .bold))
    let bytes = Array("abc def".utf8)
    let parts: [(bytes: Int, style: CodeStyleID?, face: UInt8)] = [(3, nil, 0), (4, nil, CodeDecorations.faceCode(italic: nil, weight: .bold))]
    let natural = buildCodeLine(bytes: bytes[...], windowStart: 0, windowX: 0, parts: parts, partOffset: 0, font: base, scale: 1,
                                tabColumns: 4, spaceAdvance: 6, system: system,
                                faces: CodeFaces(font: { _ in bold }, baselinePx: { 0 }))
    let wanted = natural.glyphs[0].baselineY + 4
    let shifted = buildCodeLine(bytes: bytes[...], windowStart: 0, windowX: 0, parts: parts, partOffset: 0, font: base, scale: 1,
                                tabColumns: 4, spaceAdvance: 6, system: system,
                                faces: CodeFaces(font: { _ in bold }, baselinePx: { wanted }))
    #expect(shifted.glyphs.allSatisfy { $0.baselineY == wanted }, "\(shifted.glyphs.map(\.baselineY)) wanted \(wanted)")
}

/// **10** A family without the face keeps its upright or regular face: with no italic or no bold registered, a run that
/// asks for it draws the glyphs of a run that asks for nothing, and nothing is synthesised.
/// **Mutation:** the face request ignores the system's answer and shifts every glyph of an italic run by 2 px (a fake slant).
@Test @MainActor func aFamilyWithoutAnItalicKeepsItsUprightFace() throws {
    let cases: [(system: @MainActor @Sendable () -> any TextSystem, style: CodeStyle)] = [
        ({ facesTextSystem(bold: true, italic: false) }, CodeStyle(italic: true)),
        ({ facesTextSystem(bold: false, italic: true) }, CodeStyle(weight: .bold)),
        ({ harnessTextSystem() }, CodeStyle(italic: true, weight: .heavy)),
    ]
    for (system, style) in cases {
        let plain = try faced(sentence, system: system)
        let asked = try faced(sentence, system: system, setup: { buffer, decorations in
            decorations.setHighlights([CodeStyleRun(range: 3..<22, style: decorations.register(style))],
                                      in: 0..<buffer.utf8Count, layer: .syntax, asOf: buffer.version)
        })
        let before = plain.glyphs(row: 0), after = asked.glyphs(row: 0)
        #expect(!after.isEmpty && before.count == after.count)
        #expect(before.map(\.x) == after.map(\.x), "positions")
        #expect(before.map(\.width) == after.map(\.width), "shapes")
    }
}

/// **12** A virtual row's style run can be italic: the row is shaped in the italic face over the stretch, like a buffer row.
/// **Mutation:** `resolveVirtualGroup` giving every virtual part face 0.
@Test @MainActor func aVirtualRowRunCanBeItalic() throws {
    func fixture(italic: Bool) throws -> Faced {
        try faced("first\nsecond\n", setup: { buffer, decorations in
            let runs: [[CodeStyleRun]] = italic ? [[CodeStyleRun(range: 0..<19, style: decorations.register(CodeStyle(italic: true)))]] : []
            decorations.setVirtualRows([CodeVirtualRow(anchor: .before(line: 1), lines: ["The quick brown fox tail"], styleRuns: runs)],
                                       asOf: buffer.version)
        })
    }
    let plain = try fixture(italic: false), slanted = try fixture(italic: true)
    #expect(slanted.decorations.hasFaces && !plain.decorations.hasFaces)
    let a = plain.glyphs(row: 1), b = slanted.glyphs(row: 1)
    #expect(a.count == b.count && a.count > 15, "\(a.count) \(b.count)")
    #expect(zip(a, b).contains { $0.width != $1.width || $0.x != $1.x })
    let regular = plain.system.resolveFont(descriptor()), italic = plain.system.resolveFont(descriptor(italic: true))
    let expected = Float(plain.system.measure("The quick brown fox", font: italic, wrappingAt: nil).widestLine
                         - plain.system.measure("The quick brown fox", font: regular, wrappingAt: nil).widestLine)
    #expect(abs((b.last!.x - a.last!.x) - expected) <= 1.5, "\(b.last!.x - a.last!.x) vs \(expected)")
    // The buffer rows are untouched.
    #expect(plain.glyphs(row: 0).map(\.x) == slanted.glyphs(row: 0).map(\.x))
}
