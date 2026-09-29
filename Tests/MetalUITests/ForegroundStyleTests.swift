import Testing
@testable import MetalUI

// Plan task 11 part 1, lane 3 (spec rows 3.6, 3.7; ruling TE-D): a text's
// glyph colour is its own token, else the environment's `foregroundStyle`,
// else `.textPrimary` — read off the scene's glyph colours.

/// Every glyph colour `content` paints, in a light-theme `controlRoot`.
@MainActor
private func glyphColours<C: ElementGroup>(@ElementBuilder _ content: () -> C) throws -> Set<[Float]> {
    let frame = try controlRender(controlRoot { content() })
    let colours = frame.finalizedScene().glyphs.map { [$0.color.h, $0.color.s, $0.color.l, $0.color.a] }
    try #require(!colours.isEmpty, "the fixture draws no glyphs")
    return Set(colours)
}

/// A token's light-theme colour, as `glyphColours` reads one.
private func tokenColour(_ token: ColorToken) -> Set<[Float]> {
    let c = Theme.light[token]
    return [[c.h, c.s, c.l, c.a]]
}

/// **3.6.** A container's `.foregroundStyle(_:)` or `.foregroundColor(_:)`
/// reaches a `Text` (C2, C3); the text's own token wins under either
/// spelling (C4, C5); the nearest writer wins (C6); none gives
/// `.textPrimary` (C0); the text's own `foregroundStyle` is its token (C1).
///
/// Mutation **M3f**: the environment's colour read before the text's own.
@MainActor
@Test func aContainersForegroundStyleReachesATextAndTheTextsOwnWins() throws {
    let primary = tokenColour(.textPrimary)
    let accent = tokenColour(.accent)
    let separator = tokenColour(.separator)
    try #require(primary != accent && accent != separator && primary != separator)
    #expect(try glyphColours { Text("Hg") } == primary, "C0")
    #expect(try glyphColours { Text("Hg").foregroundStyle(.accent) } == accent, "C1")
    #expect(try glyphColours { Column { Text("Hg") }.foregroundStyle(.accent) } == accent, "C2")
    #expect(try glyphColours { Column { Text("Hg") }.foregroundColor(.accent) } == accent, "C3")
    #expect(try glyphColours { Column { Text("Hg").foregroundColor(.separator) }.foregroundStyle(.accent) }
            == separator, "C4")
    #expect(try glyphColours { Column { Text("Hg").foregroundStyle(.separator) }.foregroundColor(.accent) }
            == separator, "C5")
    #expect(try glyphColours {
        Column { Column { Text("Hg") }.foregroundStyle(.accent) }.foregroundStyle(.separator)
    } == accent, "C6")
    #expect(try glyphColours { Text("Hg").foregroundStyle(.accent).foregroundStyle(.separator) } == separator,
            "the text's own: the last write")
}

/// **3.7.** A `ProposalText` reads the environment's font and foreground
/// style exactly as a `Text` does, and its own win.
///
/// Mutation **M3g**: `ProposalText` skips the environment.
@MainActor
@Test func aProposalTextReadsTheEnvironmentsFontAndForegroundStyle() throws {
    let title = teExpectedSize("Hg ag", FontDescriptor(size: 22))
    try #require(title != teExpectedSize("Hg ag", FontDescriptor(size: 13)))
    #expect(try glyphColours { VStack { ProposalText("Hg") }.foregroundStyle(.accent) } == tokenColour(.accent))
    #expect(try glyphColours { VStack { ProposalText("Hg").foregroundStyle(.separator) }.foregroundStyle(.accent) }
            == tokenColour(.separator))
    #expect(teSize(try teBounds([0, 0, 0]) { VStack { ProposalText("Hg ag") }.font(.title) }) == title)
    let caption = teExpectedSize("Hg ag", FontDescriptor(size: 10))
    #expect(teSize(try teBounds([0, 0, 0]) { VStack { ProposalText("Hg ag").font(.caption) }.font(.title) })
            == caption)
    #expect(teSize(try teBounds([0, 0]) { Text("Hg ag").font(.title).proposalLayout() }) == title,
            "Text.proposalLayout() carries the request")
    // The weight and slope too (spec §6): a bold italic `Text` converted keeps
    // the bold italic face's size, which differs from the regular face's.
    let boldItalic = teExpectedSize("Hg ag", FontDescriptor(size: 13, weight: Font.Weight.bold.value, italic: true))
    try #require(boldItalic != teExpectedSize("Hg ag", FontDescriptor(size: 13)))
    #expect(teSize(try teBounds([0, 0]) { Text("Hg ag").fontWeight(.bold).italic().proposalLayout() }) == boldItalic,
            "Text.proposalLayout() carries the weight and slope")
}
