import Testing
@testable import MetalUI

// Rich text, lane 3 — MetalUI's own inline Markdown parser (ruling RT-B; spec
// §4.3 tests 3.1 and 3.3). Runs on Linux and Windows too: one parser on every
// platform, where `AttributedString(markdown:)` does not exist (`L2`). Every
// expectation is a row of `docs/probes/foundation-markdown-inline.swift`'s
// header (Foundation's parser on macOS, which agrees with SwiftUI's render of
// every `M` arm), the intents mapped as 1 italic, 2 bold, 3 both, 4 code,
// 32 strikethrough; Foundation's line-break (128) and inline-HTML (256)
// intents carry no style and join their neighbours.

private func plain(_ text: String) -> MarkdownRun { MarkdownRun(text: text) }
private func bold(_ text: String) -> MarkdownRun { MarkdownRun(text: text, bold: true) }
private func italic(_ text: String) -> MarkdownRun { MarkdownRun(text: text, italic: true) }
private func both(_ text: String) -> MarkdownRun { MarkdownRun(text: text, bold: true, italic: true) }
private func strike(_ text: String) -> MarkdownRun { MarkdownRun(text: text, strikethrough: true) }
private func code(_ text: String) -> MarkdownRun { MarkdownRun(text: text, code: true) }
private func link(_ text: String, _ destination: String) -> MarkdownRun { MarkdownRun(text: text, link: destination) }

/// The probe's rows: id, source, Foundation's runs.
let probedMarkdownRows: [(String, String, [MarkdownRun])] = [
    ("M1", "**b**", [bold("b")]),
    ("M3a", "*i*", [italic("i")]),
    ("M3b", "_i_", [italic("i")]),
    ("M4", "~~s~~", [strike("s")]),
    ("M4b", "~s~", [strike("s")]),
    ("M5", "`code`", [code("code")]),
    ("M6", "[link](https://x.org)", [link("link", "https://x.org")]),
    ("M7", "***bi***", [both("bi")]),
    ("M8a", "# H", [plain("# H")]),
    ("M8b", "- a", [plain("- a")]),
    ("M8c", "1. a", [plain("1. a")]),
    ("M8d", "> q", [plain("> q")]),
    ("M9", "\\*a\\*", [plain("*a*")]),
    ("M12a", "snake_case_name", [plain("snake_case_name")]),
    ("M12b", "a*b*c", [plain("a"), italic("b"), plain("c")]),
    ("M12c", "2 * 3 * 4", [plain("2 * 3 * 4")]),
    ("M13", "a  b\nc", [plain("a  b\nc")]),
    ("M15", "<https://x.org>", [link("https://x.org", "https://x.org")]),
    ("M15b", "https://x.org", [link("https://x.org", "https://x.org")]),
    ("M16", "**a _b_**", [bold("a "), both("b")]),
    ("M17", "**unclosed", [plain("**unclosed")]),
    ("M18", "a&amp;b", [plain("a&b")]),
    ("M19", "![alt](https://x.org/i.png)", [plain("alt")]),
    ("M20", "www.x.org", [link("www.x.org", "http://www.x.org")]),
    ("M21", "a@b.org", [link("a@b.org", "mailto:a@b.org")]),
    ("M22", "[**b**](https://x.org)", [link("b", "https://x.org")]),
    ("M23", "&#65;&copy;", [plain("A©")]),
    ("M24", "a\\\nb", [plain("a\nb")]),
    ("M25", "`**x**`", [code("**x**")]),
    ("M26", "http://x.org/a_b_c", [link("http://x.org/a_b_c", "http://x.org/a_b_c")]),
    ("M27", "__b__", [bold("b")]),
    ("M28", "[a](relative/path)", [link("a", "relative/path")]),
    ("N1", "<b>x</b>", [plain("<b>x</b>")]),
    ("N2", "[a][r]", [plain("[a][r]")]),
    ("N3", "a  \nb", [plain("a  \nb")]),
    ("N4", "[a](<u v>)", [link("a", "u%20v")]),
    ("N5", "[a](u \"t\")", [link("a", "u")]),
    ("N6", "``a`b``", [code("a`b")]),
    ("N7", "*a **b** c*", [italic("a "), both("b"), italic(" c")]),
    ("N8", "**a*", [plain("*"), italic("a")]),
    ("N9", "_a_b", [plain("_a_b")]),
    ("N10", "(www.x.org)", [plain("("), link("www.x.org", "http://www.x.org"), plain(")")]),
    ("N11", "https://x.org.", [link("https://x.org", "https://x.org"), plain(".")]),
    ("N12", "&bogus;", [plain("&bogus;")]),
    ("N13", "&nbsp;x", [plain("\u{A0}x")]),
    ("N14", "\\`", [plain("`")]),
    ("N15", "~~~a~~~", [plain("~~~a~~~")]),
    ("N16", "[a]", [plain("[a]")]),
    ("N17", "a\tb", [plain("a\tb")]),
    ("N18", "`` a ``", [code("a")]),
    ("N19", "*a*b*", [italic("a"), plain("b*")]),
    ("N20", "x_y_ z", [plain("x_y_ z")]),
]

/// **3.1** (ruling RT-B item 2). The parser answers every `M` and `N` row of
/// the Foundation probe (`N21` is 3.3's: divergence 153). Red before: the stub
/// returned the source as one plain run. Mutations: **M3.1a** intraword `_`
/// opens emphasis (`M12a`, `N9`, `N20`); **M3.1b** no extended autolinks
/// (`M15b`, `M20`, `M21`, `M26`, `N10`, `N11`); **M3.1c** keep emphasis inside
/// a link's text (`M22`); **M3.1d** parse block syntax (`M8a`).
@Test func theInlineGrammarMatchesTheProbedRuns() throws {
    try #require(probedMarkdownRows.count == 52, "the probe's 32 M rows and 20 N rows (N21 is 3.3's)")
    for (id, source, expected) in probedMarkdownRows {
        let parsed = parseInlineMarkdown(source)
        #expect(parsed == expected, "\(id) \(source.debugDescription): \(parsed) — expected \(expected)")
    }
}

/// **3.3** (ruling RT-B item 4, divergence 153). Numeric references and the
/// fixed subset of named ones decode; any other name stays literal — where
/// SwiftUI decodes HTML5's whole table (`M35`, `N21`). Red before: the stub
/// decoded nothing. Mutation **M3.3**: decode an unknown name to U+FFFD.
@Test func onlyTheEntitySubsetDecodes() {
    let decoded: [(String, String)] = [
        ("&amp;", "&"), ("&#65;", "A"), ("&#x41;", "A"), ("&#X41;", "A"), ("&copy;", "©"), ("&nbsp;", "\u{A0}"),
        ("&lt;&gt;&quot;&apos;", "<>\"'"), ("&mdash;&hellip;&euro;", "—…€"), ("&#0;", "\u{FFFD}"),
        ("&#x110000;", "\u{FFFD}"),
    ]
    for (source, expected) in decoded {
        #expect(parseInlineMarkdown(source) == [plain(expected)], "\(source) decodes to \(expected.debugDescription)")
    }
    for literal in ["&bogus;", "&alpha;", "&AMP;", "&alpha;&hearts;&ThickSpace;", "& amp;", "&#;", "&#x;"] {
        #expect(parseInlineMarkdown(literal) == [plain(literal)], "\(literal) stays literal (divergence 153)")
    }
}
