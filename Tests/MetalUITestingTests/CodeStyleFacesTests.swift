import Testing
import Foundation
import MetalUI
import MetalUIScene
import MetalUITesting

// `CodeStyle` faces (ruling `CV-BY`, record 396): `italic` and `weight` on a style, drawn with the font's real faces.
// PLAIN imports; text is the harness's Noto Sans through `PortableTextSystem`.

private let red = Color(red: 1, green: 0, blue: 0)

/// **1** A style carries italic and weight, equal styles share an id, differing faces do not, and the id reads
/// the faces back. **Mutation:** the new fields left out of the memberwise init's assignments (every style reads
/// `nil`), and separately `italic` dropped from the interning table's equality (an italic style shares a plain id).
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
