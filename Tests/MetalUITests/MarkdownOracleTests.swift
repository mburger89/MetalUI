#if canImport(Darwin)
import Foundation
import Testing
@testable import MetalUI

// Rich text, lane 3 — Foundation's inline Markdown parser as the oracle for
// MetalUI's own (ruling RT-B item 3; spec §4.3 tests 3.2, 3.11). Darwin only:
// `AttributedString(markdown:)` and `inlinePresentationIntent` exist only on
// Apple platforms (`L2`, `L3`), which is why MetalUI parses for itself.

/// Foundation's answer for `source` under SwiftUI's options
/// (`.inlineOnlyPreservingWhitespace`), as `MarkdownRun`s: intents mapped as
/// MetalUI maps them (strong → bold, emphasis → italic, strikethrough, code);
/// line breaks and inline HTML carry no style; an image is its alt text.
private func foundationRuns(_ source: String) throws -> [MarkdownRun] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    let parsed = try AttributedString(markdown: source, options: options)
    return joinedMarkdownRuns(parsed.runs.map { run in
        let intent = run.inlinePresentationIntent ?? []
        return MarkdownRun(text: String(parsed[run.range].characters),
                           bold: intent.contains(.stronglyEmphasized), italic: intent.contains(.emphasized),
                           strikethrough: intent.contains(.strikethrough), code: intent.contains(.code),
                           link: run.link?.absoluteString)
    })
}

/// Sources beyond the probe's `M`/`N1`–`N21` rows that settled a parser rule
/// against Foundation while lane 3 built it — compared live here; the ones a
/// ruling rests on are also recorded as the probe's arms `N22`–`N28` (ruling
/// RT-T item 2's skip characters, a link's flattened content, an empty
/// destination).
let markdownOracleExtraSources = [
    "[`c` *i* ~~s~~](u)", "**[a](u)**", "*a [b](u) c*", "[a *b](u) c*", "x http://a.b/*c*", "*http://x.org*",
    "see www.x.org/a_(b) end", "a.http://x.org", "xhttp://x.org", "HTTP://x.org", "ftp://x.org", "http://x",
    "www.x", "www.x_y.z", "a_b@c.org", "*a@b.org*", "x@y", "a@b.c-", "a@b.org.", "[a](u v)", "[a](u%20v)",
    "[a](é)", "[a](<u>)", "[a](\\*u)", "[a](&amp;u)", "<a@b.org>", "<foo:bar>", "<x>", "\\a", "a\\", "`a",
    "&#0;", "&#x110000;", "&#12345678;", "![a *b*](s)", "[![i](s)](u)", "[a](u) [b]", "***a** b*",
    "*a **b***", "~a~~", "~~a~", "_a_", "a~~b~~c", "a~b~c", "*_**~", "*_**!", "**~~** ", "a~~*_**", "[a]()",
    "[www.x.org](u)", "[ www.x.org", "aw@b.org", "<a href=\"*x*\">", "` \n`",
    "[a](http://x.org:ab/c)", "http://x.org:ab", "[a](http://u@x.org:ab)",
]

/// **3.2** (ruling RT-B items 2–3). On the probe's corpus, the sources above,
/// and every four-token string over `*`, `**`, `_`, `~~`, a backtick, `a` and
/// a space (generated: 7⁴ = 2401), MetalUI's parser and Foundation's answer
/// the same runs. Red before: the stub returned the source unparsed.
/// Mutation **M3.2**: drop CommonMark's rule of 3 (`(open + close) % 3`).
@Test func theParserAgreesWithFoundationOnTheCorpus() throws {
    let tokens = ["*", "**", "_", "~~", "`", "a", " "]
    var generated: [String] = []
    for a in tokens { for b in tokens { for c in tokens { for d in tokens { generated.append(a + b + c + d) } } } }
    try #require(generated.count == 2401)
    let corpus = probedMarkdownSources + markdownOracleExtraSources + generated
    try #require(corpus.count == 53 + markdownOracleExtraSources.count + 2401,
                 "the probe's 53 sources (N21 included), the extras and the generated strings")
    var disagreements: [String] = []
    for source in corpus {
        let ours = parseInlineMarkdown(source), theirs = try foundationRuns(source)
        if ours != theirs, source != "&alpha;&hearts;&ThickSpace;" {
            disagreements.append("\(source.debugDescription): ours \(ours), Foundation \(theirs)")
        }
    }
    #expect(disagreements.isEmpty, "\(disagreements.count) disagreements:\n\(disagreements.prefix(40).joined(separator: "\n"))")
}

/// **3.2b** (ruling RT-T items 4 and 9). The trigger scan is sound against
/// the parser: on the whole corpus of 3.2 (the probe's sources, the extras
/// and the generated strings), every source `markdownMayApply` skips parses
/// to itself as one unstyled run, so skipping the parser changes no answer.
/// Mutation **MT.trig**: the pre-amendment `http` trigger in place of `://`
/// (`ftp://x.org`, `HTTP://x.org` are autolinks the scan would skip).
@Test func aFormatTheTriggerScanSkipsParsesToItself() throws {
    let tokens = ["*", "**", "_", "~~", "`", "a", " "]
    var generated: [String] = []
    for a in tokens { for b in tokens { for c in tokens { for d in tokens { generated.append(a + b + c + d) } } } }
    let corpus = probedMarkdownSources + markdownOracleExtraSources + generated
    let skipped = corpus.filter { !markdownMayApply($0) }
    // 23 today: seven probe sources (`# H`, `- a`, `1. a`, `> q` and three
    // whitespace rows) and the 16 generated strings over `a` and a space.
    try #require(skipped.count >= 23, "the corpus holds markup-free sources: \(skipped.count)")
    var wrong: [String] = []
    for source in skipped where parseInlineMarkdown(source) != [MarkdownRun(text: source)] {
        wrong.append("\(source.debugDescription): \(parseInlineMarkdown(source))")
    }
    #expect(wrong.isEmpty, "skipped by the trigger scan yet parsed to something else:\n\(wrong.joined(separator: "\n"))")
}

/// The probe's 53 sources (`foundation-markdown-inline.swift`), `N21` included.
let probedMarkdownSources = [
    "**b**", "*i*", "_i_", "~~s~~", "~s~", "`code`", "[link](https://x.org)", "***bi***", "# H", "- a", "1. a",
    "> q", "\\*a\\*", "snake_case_name", "a*b*c", "2 * 3 * 4", "a  b\nc", "<https://x.org>", "https://x.org",
    "**a _b_**", "**unclosed", "a&amp;b", "![alt](https://x.org/i.png)", "www.x.org", "a@b.org",
    "[**b**](https://x.org)", "&#65;&copy;", "a\\\nb", "`**x**`", "http://x.org/a_b_c", "__b__",
    "[a](relative/path)", "<b>x</b>", "[a][r]", "a  \nb", "[a](<u v>)", "[a](u \"t\")", "``a`b``",
    "*a **b** c*", "**a*", "_a_b", "(www.x.org)", "https://x.org.", "&bogus;", "&nbsp;x", "\\`", "~~~a~~~",
    "[a]", "a\tb", "`` a ``", "*a*b*", "x_y_ z", "&alpha;&hearts;&ThickSpace;",
]

/// **3.11** (`C12c`; ruling RT-D item 5). On Apple platforms
/// `Text(AttributedString)` honours `inlinePresentationIntent`, so
/// `Text(try AttributedString(markdown: s))` builds the runs the literal
/// `Text(s)` builds. Red before: the stub ignored every attribute. Mutation
/// **M3.11**: ignore the intent.
@MainActor
@Test func inlinePresentationIntentIsHonouredOnDarwin() throws {
    let source = "**b** _i_ ~~s~~ `c`"
    let attributed = Text(try AttributedString(markdown: "**b** _i_ ~~s~~ `c`"))
    let literal = Text("**b** _i_ ~~s~~ `c`")
    #expect(attributed.content == literal.content, "\(source): \(attributed.content) vs \(literal.content)")
    #expect(literal.content == .runs([
        TextRunRequest(string: "b", weight: .bold), TextRunRequest(string: " "),
        TextRunRequest(string: "i", italic: true), TextRunRequest(string: " "),
        TextRunRequest(string: "s", strikethrough: .single), TextRunRequest(string: " "),
        TextRunRequest(string: "c", monospaced: true),
    ]), "\(literal.content)")
}
#endif
