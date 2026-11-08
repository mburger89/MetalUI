import MetalUI
import MetalUIMarkdown
import Testing
@testable import MetalUIDemoContent

// The block Markdown demo's content (`BM-`, record 235): its script holds every block kind and its highlighter answers
// valid runs. Pure values; the streamed window is a human look (group BM).

/// **BM-E.** The demo's reply script parses to every block kind (the demo is only a tour if it has all of them), and
/// the demo highlighter's runs are sorted, disjoint and inside the fence's bytes. Mutation: the table removed from the
/// script (no `.table`).
@Test func theDemoReplyHoldsEveryBlockKindAndTheHighlighterAnswersValidRuns() throws {
    let blocks = MarkdownDocument(parsing: markdownDemoReply(7)).blocks
    func kinds(_ blocks: [MarkdownBlock]) -> Set<String> {
        var out: Set<String> = []
        for block in blocks {
            switch block.kind {
            case .paragraph: out.insert("paragraph")
            case .heading: out.insert("heading")
            case .codeBlock: out.insert("code")
            case .blockQuote(let inner): out.insert("quote"); out.formUnion(kinds(inner))
            case .list(_, _, _, let items): out.insert("list"); for item in items { out.formUnion(kinds(item)) }
            case .thematicBreak: out.insert("rule")
            case .table: out.insert("table")
            }
        }
        return out
    }
    #expect(kinds(blocks) == ["paragraph", "heading", "code", "quote", "list", "rule", "table"], "\(kinds(blocks))")
    guard case .codeBlock(let language, let code, let isClosed)? = blocks.first(where: { if case .codeBlock = $0.kind { true } else { false } })?.kind
    else { Issue.record("no fence"); return }
    #expect(language == "swift" && isClosed)
    let runs = MarkdownDemoHighlighter().highlight(code: code, language: language, isClosed: isClosed)
    #expect(!runs.isEmpty)
    var end = 0
    for run in runs {
        #expect(run.range.lowerBound >= end && run.range.upperBound <= code.utf8.count && !run.range.isEmpty, "\(run.range)")
        end = run.range.upperBound
    }
}
