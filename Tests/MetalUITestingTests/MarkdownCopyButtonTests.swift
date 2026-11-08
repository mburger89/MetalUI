import Testing
import MetalUI
import MetalUITesting
import MetalUICore

// The code fence copy button's identifier and "Copied" feedback (`BM-L`, Alloy gap G15).

@MainActor private func buttonWindow(_ source: String, prefix: String?) throws -> TestWindow {
    var theme = MarkdownTheme()
    theme.showsCodeCopyButton = true
    theme.codeCopyButtonIdentifierPrefix = prefix
    let document = MarkdownDocument(parsing: source)
    let window = try TestWindow(size: sz(300, 600), textSystem: { harnessTextSystem() }) {
        VStack(alignment: .leading, spacing: Pixels(0)) { MarkdownView(document).markdownTheme(theme) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    markdownSettle(window, frames: 3)
    return window
}

@MainActor private func buttons(_ window: TestWindow) throws -> [TestElement] {
    try window.elements(where: { $0.label == "Copy code" || $0.label == "Copied" })
        .sorted { $0.frame.origin.y.value < $1.frame.origin.y.value }
}

/// What the button draws, as a comparable string (the symbol is an image primitive).
@MainActor private func look(_ window: TestWindow) -> String { String(describing: window.scene.images) }

private let nestedSource = "```\none\n```\n\npara\n\n- item\n\n  ```\n  two\n  ```\n\n> ```\n> three\n> ```\n\n```\nfour\n```"

/// **BM-L, test 1.** With a prefix, each button is `prefix + index`, the index counting code blocks (not blocks),
/// in source order, nested ones included. Mutation: the index taken from the block id (counts paragraphs too); a
/// nested container not passing its base on (every nested index restarts).
@Test @MainActor func eachCopyButtonCarriesItsCodeBlockIndex() throws {
    let window = try buttonWindow(nestedSource, prefix: "copy-")
    let all = try buttons(window)
    try #require(all.count == 4)
    #expect(all.map { $0.identifier } == ["copy-0", "copy-1", "copy-2", "copy-3"], "\(all.map { $0.identifier })")
    for (button, code) in zip(all, ["one", "two", "three", "four"]) {
        try window.click(button)
        #expect(window.platformWindow.clipboard == code)
    }
}

/// **BM-L, test 2.** Without a prefix no identifier is written. Mutation: a default prefix.
@Test @MainActor func noPrefixWritesNoIdentifier() throws {
    #expect(MarkdownTheme().codeCopyButtonIdentifierPrefix == nil)
    let window = try buttonWindow(nestedSource, prefix: nil)
    let all = try buttons(window)
    try #require(all.count == 4)
    #expect(all.allSatisfy { $0.identifier == nil })
}

/// **BM-L, test 3.** The indices survive a re-render of the same document and a document that grows: the earlier
/// blocks keep theirs and the streamed fence takes the next. Mutation: the base stored per render and not derived.
@Test @MainActor func indicesAreStableWhileTheDocumentGrows() throws {
    var theme = MarkdownTheme()
    theme.showsCodeCopyButton = true
    theme.codeCopyButtonIdentifierPrefix = "c"
    let model = MarkdownTranscriptModel(documents: [MarkdownDocument(parsing: "```\na\n```\n\ntext\n\n```\nb\n```")])
    model.theme = theme
    let window = try markdownTranscript(model)
    markdownSettle(window, frames: 3)
    #expect(try buttons(window).map { $0.identifier } == ["c0", "c1"])
    model.documents[0].append("\n\n```\nc\n```\n\n```\nd")
    markdownSettle(window, frames: 4)
    #expect(try buttons(window).map { $0.identifier } == ["c0", "c1", "c2", "c3"])
    markdownSettle(window, frames: 3)
    #expect(try buttons(window).map { $0.identifier } == ["c0", "c1", "c2", "c3"])
}

/// **BM-L, test 4.** A press shows "Copied" and the checkmark, still there just before 1.5 s, reverted at 1.5 s; the
/// clipboard got the code. Mutation: the animation duration 0.5 or 3 s; no label change; the same glyph.
@Test @MainActor func aPressShowsCopiedForOneAndAHalfSeconds() throws {
    let window = try buttonWindow("```\nlet a = 1\n```", prefix: "x")
    let idle = look(window)
    let button = try #require(try buttons(window).first)
    #expect(button.label == "Copy code")
    try window.click(button)
    window.advanceFrames(2)
    #expect(window.platformWindow.clipboard == "let a = 1")
    var now = try #require(try buttons(window).first)
    #expect(now.label == "Copied" && now.identifier == "x0")
    let copied = look(window)
    #expect(copied != idle, "the glyph changed")
    window.advance(by: 1.3)
    now = try #require(try buttons(window).first)
    #expect(now.label == "Copied", "still copied before 1.5 s")
    #expect(look(window) == copied)
    window.advance(by: 0.3)
    window.advanceFrames(2)
    now = try #require(try buttons(window).first)
    #expect(now.label == "Copy code" && now.identifier == "x0", "reverted after 1.5 s")
    #expect(look(window) == idle, "the copy glyph is back")
}

/// **BM-L, test 5.** A second press during the window restarts it. Mutation: the trigger not changing (a `Bool`
/// state set to true twice).
@Test @MainActor func aSecondPressRestartsTheWindow() throws {
    let window = try buttonWindow("```\ncode\n```", prefix: nil)
    try window.click(try #require(try buttons(window).first))
    window.advanceFrames(2)
    window.advance(by: 1.0)
    try window.click(try #require(try buttons(window).first))
    window.advanceFrames(2)
    window.advance(by: 1.0)   // 2.0 s after the first press, 1.0 after the second
    #expect(try #require(try buttons(window).first).label == "Copied", "restarted")
    window.advance(by: 0.6)
    window.advanceFrames(2)
    #expect(try #require(try buttons(window).first).label == "Copy code")
}

/// **BM-L, test 6.** The press still writes the whole code, and the feedback does not shape the fence's code again.
/// (Covered by `BM-K` tests 1 and 4, which stay green; this pins the accessibility action as well.)
@Test @MainActor func theAccessibilityActionAlsoShowsFeedback() throws {
    let window = try buttonWindow("```\ncode\n```", prefix: nil)
    let button = try #require(try buttons(window).first)
    try window.click(button)
    window.advanceFrames(2)
    #expect(window.platformWindow.clipboard == "code")
    #expect(try #require(try buttons(window).first).label == "Copied")
}
