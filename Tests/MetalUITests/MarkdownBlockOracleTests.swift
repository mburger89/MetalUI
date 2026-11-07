#if canImport(Darwin)
import Foundation
import Testing
@testable import MetalUI

// Block Markdown, test 8 of the plan (rulings BM-A, BM-B): Foundation's `.full` parse as the oracle for
// `MetalUIMarkdown`'s block structure. Darwin only: `AttributedString(markdown:)` with `.full` and
// `presentationIntent` exist only on Apple platforms, which is why MetalUI parses for itself
// (`docs/probes/foundation-markdown-blocks.swift` records what the arms below rest on).
//
// Both sides are reduced to one canonical string: block kinds, heading levels, list ordinals, code text and
// the first word of its info string, table alignments and non-empty cells, and each paragraph's plain text
// (through MetalUI's own inline parser, so a hard break reads as "\n" and a soft break as a space).
// Differences that are Foundation reporting less, not a disagreement, are normalised away on BOTH sides
// (`BM-B`): a container with no text has no run in Foundation, so empty items, quotes, headings, fences and
// cells are dropped; Foundation has no "no alignment", so `.none` reads as `left`; Foundation has no
// tight/loose, which test 1 pins instead; a fence holding one blank line reads as empty.

private final class FoundationNode {
    var kind: String
    var children: [FoundationNode] = []
    var text = ""
    init(_ kind: String) { self.kind = kind }
}

private func foundationCanonical(_ source: String) throws -> String {
    let parsed = try AttributedString(markdown: source, options: .init(interpretedSyntax: .full))
    let root = FoundationNode("doc")
    var byIdentity: [Int: FoundationNode] = [:]
    for run in parsed.runs {
        var parent = root
        var leaf: FoundationNode?
        for component in (run.presentationIntent?.components ?? []).reversed() {
            let node: FoundationNode
            if let known = byIdentity[component.identity] {
                node = known
            } else {
                let kind: String
                switch component.kind {
                case .paragraph: kind = "P"
                case .header(let level): kind = "H\(level)"
                case .orderedList: kind = "OL"
                case .unorderedList: kind = "UL"
                case .listItem(let ordinal): kind = "LI\(ordinal)"
                case .codeBlock(let hint): kind = "CODE:" + (hint.flatMap { $0.split(separator: " ").first.map(String.init) } ?? "")
                case .blockQuote: kind = "BQ"
                case .thematicBreak: kind = "HR"
                case .table(let columns): kind = "TABLE:" + columns.map { "\($0.alignment)" }.joined(separator: ",")
                case .tableHeaderRow: kind = "TH"
                case .tableRow(let row): kind = "TR\(row)"
                case .tableCell(let column): kind = "TD\(column)"
                @unknown default: kind = "?"
                }
                node = FoundationNode(kind)
                byIdentity[component.identity] = node
                parent.children.append(node)
            }
            parent = node
            leaf = node
        }
        leaf?.text += String(parsed[run.range].characters)
    }
    return foundationOutput(root.children)
}

private func foundationOutput(_ nodes: [FoundationNode]) -> String {
    nodes.compactMap { node -> String? in
        let k = node.kind
        switch k {
        case "P": return "P(\(node.text))"
        case "HR": return "HR"
        case "BQ", "UL", "OL", "TH":
            let inner = foundationOutput(node.children)
            return inner.isEmpty ? nil : "\(k)[\(inner)]"
        default:
            if k.hasPrefix("CODE") { return node.text == "\n" ? nil : "\(k)(\(node.text.debugDescription))" }
            if k.hasPrefix("H") { return "\(k)(\(node.text))" }
            if k.hasPrefix("LI") || k.hasPrefix("TR") || k.hasPrefix("TABLE") {
                let inner = foundationOutput(node.children)
                return inner.isEmpty ? nil : "\(k)[\(inner)]"
            }
            if k.hasPrefix("TD") { return node.text.isEmpty ? nil : "\(k)(\(node.text))" }
            return "?"
        }
    }.joined(separator: " ")
}

private func plain(_ inline: String) -> String {
    parseInlineMarkdown(inline).map(\.text).joined()
}

private func ourCanonical(_ blocks: [MarkdownBlock]) -> String {
    var out: [String] = []
    for block in blocks {
        switch block.kind {
        case .paragraph(let text): out.append("P(\(plain(text)))")
        case .heading(let level, let text): if !text.isEmpty { out.append("H\(level)(\(plain(text)))") }
        case .codeBlock(let language, let code, _): if !code.isEmpty { out.append("CODE:\(language ?? "")(\((code + "\n").debugDescription))") }
        case .blockQuote(let inner): let x = ourCanonical(inner); if !x.isEmpty { out.append("BQ[\(x)]") }
        case .thematicBreak: out.append("HR")
        case .list(let ordered, let start, _, let items):
            var parts: [String] = []
            for (i, item) in items.enumerated() {
                let x = ourCanonical(item)
                if !x.isEmpty { parts.append("LI\(ordered ? start + i : i + 1)[\(x)]") }
            }
            if !parts.isEmpty { out.append("\(ordered ? "OL" : "UL")[" + parts.joined(separator: " ") + "]") }
        case .table(let alignments, let header, let rows):
            func cells(_ row: [String]) -> [String] {
                row.enumerated().filter { !$0.element.isEmpty }.map { "TD\($0.offset)(\(plain($0.element)))" }
            }
            var parts: [String] = []
            let head = cells(header)
            if !head.isEmpty { parts.append("TH[" + head.joined(separator: " ") + "]") }
            for (i, row) in rows.enumerated() {
                let c = cells(row)
                if !c.isEmpty { parts.append("TR\(i + 1)[" + c.joined(separator: " ") + "]") }
            }
            let names = alignments.map { a -> String in
                switch a { case .none, .left: return "left"; case .center: return "center"; case .right: return "right" }
            }
            if !parts.isEmpty { out.append("TABLE:" + names.joined(separator: ",") + "[" + parts.joined(separator: " ") + "]") }
        }
    }
    return out.joined(separator: " ")
}

private let lineKinds = ["# a", "a", "", "- a", "1. a", "  - a", "> a", "```", "    a", "---", "===", "|a|b|", "|-|-|"]

@Suite struct MarkdownBlockOracleTests {
    private func disagreements(in sources: [String]) throws -> [String] {
        var out: [String] = []
        for source in sources {
            let theirs = try foundationCanonical(source)
            let ours = ourCanonical(MarkdownDocument.parseWhole(source))
            if theirs != ours {
                out.append("\(source.debugDescription)\n  Foundation: \(theirs)\n  ours:       \(ours)")
                if out.count >= 5 { break }
            }
        }
        return out
    }

    /// Every four-line source over thirteen line kinds (28,561): the block structure agrees with Foundation's.
    @Test func everyFourLineSourceAgreesWithFoundation() throws {
        var sources: [[String]] = [[]]
        for _ in 0..<4 { sources = sources.flatMap { prefix in lineKinds.map { prefix + [$0] } } }
        let found = try disagreements(in: sources.map { $0.joined(separator: "\n") })
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    /// A seeded corpus of longer sources with tabs, other markers, ordered lists, info strings and escaped pipes.
    @Test func randomLongerSourcesAgreeWithFoundation() throws {
        let rich = [
            "# a", "## a ##", "a", "b", "", "- a", "* a", "+ b", "1. a", "2. a", "1) a", "10. a", "  - a", "   - b", "    - c",
            "> a", ">", "> > a", ">b", "```", "``` js x", "~~~", "~~~~", "````", "    a", "     a", "\ta", "\t\ta", "  \ta",
            "---", "***", "___", "- - -", "===", "= =", "|a|b|", "|-|-|", "a|b", "-|-", ":-|-:", "|:-:|:--|", "|a|", "|", "-",
            "-  a", "   ```", "  ", "a  ", "1.", "-\ta", "#", "####### a", "#a", "|a\\|b|c|", "| a | b |",
        ]
        var seed: UInt64 = 8
        func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed >> 33 }
        let sources = (0..<20_000).map { _ -> String in
            let count = 2 + Int(next() % 6)
            return (0..<count).map { _ in rich[Int(next() % UInt64(rich.count))] }.joined(separator: "\n")
        }
        let found = try disagreements(in: sources)
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
    }

    /// The rulings that are not disagreements to find but differences to know (`BM-B`), each in its own arm.
    @Test func theRulingsAgainstFoundation() throws {
        // BM-B: the language is the info string's first word; Foundation's hint is the whole string.
        let doc = MarkdownDocument.parseWhole("```swift linenos\nx\n```")
        guard case .codeBlock(let language, _, _) = doc[0].kind else { Issue.record("not code"); return }
        #expect(language == "swift")
        // BM-B: link reference definitions, HTML blocks and task boxes are paragraph text in v1; so is
        // Foundation's task list text ("[ ] a"), which is why the two agree there.
        #expect(try foundationCanonical("- [ ] a") == ourCanonical(MarkdownDocument.parseWhole("- [ ] a")))
        // BM-B: a list that is loose in Markdown reads the same to Foundation (it has no tight/loose), so
        // tightness is pinned by BlockKindTests.listsAreTightOrLooseAndKeepTheirStartNumber, not here.
        #expect(try foundationCanonical("- a\n\n- b") == ourCanonical(MarkdownDocument.parseWhole("- a\n\n- b")))
        #expect(try foundationCanonical("- a\n- b") == ourCanonical(MarkdownDocument.parseWhole("- a\n- b")))
    }
}
#endif
