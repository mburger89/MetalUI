import MetalUI
import MetalUIMarkdown
import MetalUIScene
import MetalUITesting
import Testing

// The block Markdown view (`BM-E`..`BM-J`, record 235), through a real `Window` over the harness: portable, plain
// imports, text through Noto Sans. Documents are parsed by `MarkdownDocument`, never by `AttributedString(markdown:)`
// (which Linux and Windows lack). Layout facts are analytic, from the accessibility tree and the scene.

@MainActor private func markdownWindow(_ source: String, theme: MarkdownTheme = MarkdownTheme(), width: Float = 300,
                                       height: Float = 400, highlighter: (any MarkdownCodeHighlighter)? = nil) throws -> TestWindow {
    let document = MarkdownDocument(parsing: source)
    let window = try harnessWindow(size: sz(width, height)) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            MarkdownView(document).markdownTheme(theme).codeHighlighter(highlighter)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    markdownSettle(window, frames: 3)
    return window
}

@MainActor private func text(_ window: TestWindow, _ value: String) throws -> TestElement {
    try #require(try window.elements(role: .staticText).first { ($0.value ?? $0.label) == value }, "no text \(value)")
}

/// **BM-I, test 9.** A heading is an accessibility heading with its text; a paragraph's link run is a `.link` child
/// and a click on it asks the window's platform to open the URL (`\.openURL`, `LI-A`). Mutations: `.isHeader` dropped
/// (no `.heading`); `link` dropped from the run mapping (no `.link`, no open).
@Test @MainActor func aHeadingIsAnAccessibilityHeadingAndALinkOpensThroughOpenURL() throws {
    let window = try markdownWindow("# Title\n\nSee [the docs](https://x.org/a) now.")
    let headings = try window.elements(role: .heading)
    try #require(headings.count == 1)
    #expect((headings[0].value ?? headings[0].label) == "Title")
    let links = try window.elements(role: .link)
    try #require(links.count == 1, "one link run")
    #expect(window.platformWindow.openedURLs == [])
    try window.click(links[0])
    #expect(window.platformWindow.openedURLs == ["https://x.org/a"], "\(window.platformWindow.openedURLs)")
}

/// **BM-E (soft and hard breaks).** The inline parser keeps a break as written, so the view decides first: a soft
/// break is a space (the default) or a line break (`MarkdownTheme.softBreak`), and the spaces before a hard break
/// are trimmed. Mutation: the spaces before a hard break kept (the value reads `a  \nb`).
@Test @MainActor func softBreaksAreSpacesByDefaultAndHardBreaksTrimTheirSpaces() throws {
    let source = "one\ntwo\n\nthree  \nfour\n\nfive\\\nsix"
    let spaces = try markdownWindow(source)
    let values = Set(try spaces.elements(role: .staticText).compactMap(\.value))
    #expect(values == ["one two", "three\nfour", "five\nsix"], "\(values)")
    var theme = MarkdownTheme()
    theme.softBreak = .lineBreak
    let lines = try markdownWindow(source, theme: theme)
    let lineValues = try lines.elements(role: .staticText).compactMap(\.value)
    #expect(lineValues.contains("one\ntwo"), "\(lineValues)")
}

/// **BM-E, test 10.** A block's y is the previous block's maxY plus `blockSpacing`; a list item's content x is the
/// list's x plus `listMarkerWidth` plus `listMarkerSpacing`; a nested list adds `listIndent` per level; a quote's bar
/// is exactly as tall as its content. Mutations: spacing 0 (the y literals); the bar in an `HStack` (10 tall).
@Test @MainActor func blocksAreSpacedByTheThemeAndNestedListsAndQuoteBarsFollowIt() throws {
    var theme = MarkdownTheme()
    theme.blockSpacing = Pixels(7); theme.listMarkerWidth = Pixels(20); theme.listMarkerSpacing = Pixels(5)
    theme.listIndent = Pixels(9); theme.quoteBarWidth = Pixels(3); theme.quotePadding = Pixels(10)
    let window = try markdownWindow("Para one\n\n- a\n  - b\n\nPara two\n\n> q1\n>\n> q2", theme: theme)
    let one = try text(window, "Para one"), a = try text(window, "a"), b = try text(window, "b")
    let two = try text(window, "Para two"), q1 = try text(window, "q1"), q2 = try text(window, "q2")
    func maxY(_ e: TestElement) -> Float { e.frame.origin.y.value + e.frame.size.height.value }
    #expect(one.frame.origin.y.value == 0)
    #expect(a.frame.origin.y.value == maxY(one) + 7, "list after paragraph: \(a.frame.origin.y.value)")
    #expect(a.frame.origin.x.value == 25, "marker column 20 + gap 5")
    #expect(b.frame.origin.x.value == 25 + 9 + 25, "nested: the item content + listIndent + a marker column and gap")
    #expect(two.frame.origin.y.value == maxY(b) + 7)
    #expect(q1.frame.origin.y.value == maxY(two) + 7)
    #expect(q2.frame.origin.y.value == maxY(q1) + 7, "the quote's own blocks are spaced by blockSpacing too")
    #expect(q1.frame.origin.x.value == 3 + 10, "bar + padding")
    let bar = try #require(window.scene.rects.first { $0.bounds.size.width == 3 }, "the bar is one rect 3 wide")
    #expect(bar.bounds.size.height == maxY(q2) - q1.frame.origin.y.value, "the bar is as tall as the quote: \(bar.bounds.size.height)")
}

/// **BM-H, test 11.** A code fence is a box of `lines x line height + 2 x padding`, as wide as the proposal; its lines
/// are not wrapped and run past the box when the theme scrolls (`codeWraps = false`); by default there is no scroller
/// and the long line wraps inside the box. A highlighter run colours exactly its bytes, counted by glyphs of that colour, and
/// slices by UTF-8 bytes (a multibyte scalar before the run keeps the run on its glyphs). Mutations: `fixedSize`
/// dropped from the column; runs sliced by `Character`.
@Test @MainActor func aCodeFenceIsABoxOfItsLinesAndRunsColourTheirBytes() throws {
    #expect(MarkdownTheme().codeWraps && !MarkdownTheme().tableScrolls, "no horizontal scroller by default (BM-H)")
    let long = String(repeating: "abcdefghij", count: 30)
    var scrolling = MarkdownTheme()
    scrolling.codeWraps = false
    let one = try markdownWindow("```\nx\n```")
    let oneBox = try #require(try one.elements(role: .group).first ?? one.elements(where: { $0.label == "Code" }).first)
    let lineHeight = oneBox.frame.size.height.value - 20   // padding 10 + 10
    #expect(lineHeight > 10)
    let three = try markdownWindow("```\nl1\nl2\n\(long)\n```", theme: scrolling)
    let box = try #require(try three.elements(where: { $0.label == "Code" }).first)
    #expect(box.frame.size.height.value == 3 * lineHeight + 20, "3 lines: \(box.frame.size.height.value)")
    #expect(box.frame.size.width.value == 300, "as wide as the proposal, not the longest line")
    let chunk = try #require(try three.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("l1") })
    #expect(chunk.frame.size.width.value > 1000, "the long line is whole, past the box: \(chunk.frame.size.width.value)")
    #expect(chunk.frame.size.height.value == 3 * lineHeight, "no wrapping")
    #expect(chunk.visibleFrame.size.width.value <= 280, "the scroller clips the line to the box")
    let wrapped = try markdownWindow("```\nl1\nl2\n\(long)\n```")   // the default theme wraps
    let wrappedChunk = try #require(try wrapped.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("l1") })
    #expect(wrappedChunk.frame.size.width.value <= 280 && wrappedChunk.frame.size.height.value > 3 * lineHeight,
            "codeWraps (the default) wraps inside the box: \(wrappedChunk.frame)")
    // Colour: a run over `bb` colours exactly two glyphs, also after a multibyte scalar.
    let hue: Float = 0.321
    let colour = CodeStyle(foreground: Color(hue: Double(hue), saturation: 0.9, brightness: 0.9))
    for (code, range) in [("aabbcc", 2..<4), ("\u{e9}\u{e9}bbcc", 4..<6)] {   // bytes: each e-acute is 2
        let highlighter = RunHighlighter([MarkdownCodeRun(range: range, style: colour)])
        let window = try markdownWindow("```\n\(code)\n```", highlighter: highlighter)
        #expect(markdownGlyphs(window, hue: hue) == 2, "\(code): \(markdownGlyphs(window, hue: hue)) glyphs of the run colour")
        // ... and they are the third and fourth glyphs of the line, left to right (`bb` in `aabbcc`).
        let line = window.scene.glyphs.sorted { $0.bounds.origin.x < $1.bounds.origin.x }
        let coloured = line.map { abs($0.color.h - hue) < 0.001 }
        #expect(coloured == [false, false, true, true, false, false], "\(code): which glyphs carry the colour: \(coloured)")
        #expect(highlighter.calls == [.init(code: code, language: nil, isClosed: true)])
    }
}

/// A highlighter that answers fixed runs and records its calls.
@MainActor final class RunHighlighter: MarkdownCodeHighlighter {
    struct Call: Equatable { var code: String; var language: String?; var isClosed: Bool }
    var runs: [MarkdownCodeRun]
    var calls: [Call] = []
    init(_ runs: [MarkdownCodeRun]) { self.runs = runs }
    nonisolated func highlight(code: String, language: String?, isClosed: Bool) -> [MarkdownCodeRun] {
        MainActor.assumeIsolated {
            calls.append(Call(code: code, language: language, isClosed: isClosed))
            return runs
        }
    }
}

/// **BM-E, test 12.** A table's cells share their column's x across rows, and a right-aligned cell's maxX is the
/// column's maxX (a centred cell is centred in it). Mutation: the delimiter row's alignment ignored (`.leading`).
@Test @MainActor func aTableAlignsItsColumnsByTheDelimiterRow() throws {
    let window = try markdownWindow("| a | bb | c |\n|:--|--:|:-:|\n| ddddd | e | f |\n| g | hhhhhhh | i |")
    func el(_ s: String) throws -> TestElement { try text(window, s) }
    func maxX(_ e: TestElement) -> Float { e.frame.origin.x.value + e.frame.size.width.value }
    #expect(try el("a").frame.origin.x.value == (try el("ddddd")).frame.origin.x.value, "left column: one x")
    #expect(try el("g").frame.origin.x.value == (try el("ddddd")).frame.origin.x.value)
    let bb = maxX(try el("bb")), e = maxX(try el("e")), h = maxX(try el("hhhhhhh"))
    #expect(bb == e && e == h, "right column: one maxX (\(bb), \(e), \(h))")
    let c = try el("c"), f = try el("f"), i = try el("i")
    func centre(_ e: TestElement) -> Float { e.frame.origin.x.value + e.frame.size.width.value / 2 }
    #expect(abs(centre(c) - centre(f)) <= 0.5 && abs(centre(f) - centre(i)) <= 0.5,
            "centred column: one centre (within the pixel the frames round to): \(centre(c)), \(centre(f)), \(centre(i))")
    #expect(try el("a").frame.origin.y.value < (try el("ddddd")).frame.origin.y.value, "rows go down")
}

/// **BM-F, test 17.** The highlighter is called once per changed fence, with `isClosed` false while the fence streams
/// and true after its closing line, and never again on frames where nothing changed. Mutation: the fence's `==`
/// without the highlighter's identity (a new highlighter instance is never called).
@Test @MainActor func theHighlighterIsCalledOncePerChangedFenceAndSeesWhetherItClosed() throws {
    @MainActor final class Holder { var highlighter: RunHighlighter; var document: MarkdownDocument
        init(_ h: RunHighlighter, _ d: MarkdownDocument) { highlighter = h; document = d } }
    let first = RunHighlighter([])
    let holder = Holder(first, MarkdownDocument(parsing: "```swift\nlet a = 1"))
    let window = try harnessWindow(size: sz(300, 200)) {
        VStack(alignment: .leading, spacing: Pixels(0)) {
            MarkdownView(holder.document).codeHighlighter(holder.highlighter).equatable()
        }
    }
    markdownSettle(window, frames: 4)
    #expect(first.calls == [.init(code: "let a = 1", language: "swift", isClosed: false)], "\(first.calls)")
    markdownSettle(window, frames: 4)
    #expect(first.calls.count == 1, "frames where nothing changed do not call it")
    holder.document.append("\n```")
    markdownSettle(window, frames: 4)
    #expect(first.calls.last == .init(code: "let a = 1", language: "swift", isClosed: true) && first.calls.count == 2, "\(first.calls)")
    // A replacement instance is called: the view compares the highlighter by identity.
    let other = RunHighlighter([])
    holder.highlighter = other
    markdownSettle(window, frames: 4)
    #expect(other.calls.count == 1 && first.calls.count == 2, "\(other.calls.count) calls of the new one")
}

/// **BM-H.** A table wraps its cells by default and, with `tableScrolls`, keeps them whole in a horizontal scroller
/// Mutation: the cells' `fixedSize` dropped was GREEN (the scroller proposes no width), so it was deleted; the scroller dropped instead reddens this.
@Test @MainActor func aTableWrapsByDefaultAndScrollsWhenTheThemeAsks() throws {
    let source = "| a | b |\n|--|--|\n| a long cell with many words in it | another long cell with many more words |"
    let wrapped = try markdownWindow(source, width: 200)
    let cell = try #require(try wrapped.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("a long cell") })
    #expect(cell.frame.size.height.value > 20 && cell.frame.origin.x.value + cell.frame.size.width.value <= 200, "wrapped: \(cell.frame)")
    var theme = MarkdownTheme()
    theme.tableScrolls = true
    let scrolling = try markdownWindow(source, theme: theme, width: 200)
    let whole = try #require(try scrolling.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("a long cell") })
    #expect(whole.frame.size.height.value <= 20 && whole.frame.size.width.value > 150, "whole: \(whole.frame)")
    let other = try #require(try scrolling.elements(role: .staticText).first { ($0.value ?? "").hasPrefix("another long") })
    #expect(other.frame.origin.x.value + other.frame.size.width.value > 200, "the table is wider than its block: \(other.frame)")
}
