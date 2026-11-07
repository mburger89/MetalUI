import Testing
@testable import MetalUIMarkdown

// Tests 4-6 of the block-markdown plan (ruling BM-C): appending equals parsing the whole text, re-parses only
// the tail, and copies only the tail when a copy diverges.

/// The thirteen line kinds the exhaustive corpus draws from: every block start, every continuation hazard and
/// both halves of a table.
private let lineKinds = [
    "# a", "a", "", "- a", "1. a", "  - a", "> a", "```", "    a", "---", "===", "|a|b|", "|-|-|",
]

/// Every `length`-line source over `lineKinds`, joined with newlines (so the last line never ends in one).
private func corpus(lines length: Int) -> [String] {
    var result: [[String]] = [[]]
    for _ in 0..<length { result = result.flatMap { prefix in lineKinds.map { prefix + [$0] } } }
    return result.map { $0.joined(separator: "\n") }
}

private func chunks(of text: String, scalars step: Int) -> [String] {
    let scalars = Array(text.unicodeScalars)
    var out: [String] = []
    var i = 0
    while i < scalars.count {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[i..<min(i + step, scalars.count)])
        out.append(String(view))
        i += step
    }
    return out
}

private func streamed(_ text: String, scalars step: Int) -> [MarkdownBlock] {
    var doc = MarkdownDocument()
    for chunk in chunks(of: text, scalars: step) { doc.append(chunk) }
    return doc.blocks
}

@Suite struct StreamingInvariantTests {
    /// Core: for every four-line source, appending one scalar at a time, or 3 or 7 at a time, ends at the blocks
    /// and ids that parsing the whole text gives. Reddens when the tail starts anywhere but the last block's
    /// first line, when the last block is finalised too, or when a half-typed line is trusted (`BM-C`).
    @Test func streamingEqualsWholeParsingOverEveryFourLineSource() throws {
        let sources = corpus(lines: 4)
        #expect(sources.count == 28_561)
        var failures: [String] = []
        for source in sources {
            let whole = MarkdownDocument.parseWhole(source)
            for step in [1, 3, 7] where streamed(source, scalars: step) != whole {
                failures.append("step \(step): \(source.debugDescription)")
                break
            }
            if failures.count >= 5 { break }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func oneShotInitialiserEqualsWholeParsing() {
        for source in corpus(lines: 3) {
            #expect(MarkdownDocument(parsing: source).blocks == MarkdownDocument.parseWhole(source), "\(source.debugDescription)")
        }
    }

    /// A seeded corpus of longer sources over a richer set of lines (tabs, CRLF, non-ASCII, other markers).
    @Test func streamingEqualsWholeParsingOverRandomLongerSources() {
        let rich = [
            "# a", "## a ##", "a", "b", "", "- a", "* a", "+ b", "1. a", "2. a", "1) a", "10. a", "  - a", "   - b", "    - c",
            "> a", ">", "> > a", ">b", "```", "``` js x", "~~~", "~~~~", "````", "    a", "     a", "\ta", "\t\ta", "  \ta",
            "---", "***", "___", "- - -", "===", "= =", "|a|b|", "|-|-|", "a|b", "-|-", ":-|-:", "|:-:|:--|", "|a|", "|", "-",
            "-  a", "   ```", "  ", "a  ", "1.", "-\ta", "#", "####### a", "#a", "|a\\|b|c|", "| a | b |", "é ü", "日本 語", "a😀b",
        ]
        var rng = SplitMix64(seed: 2026)
        var failures: [String] = []
        for _ in 0..<6000 {
            let count = 2 + Int(rng.next() % 7)
            let separator = rng.next() % 4 == 0 ? "\r\n" : "\n"
            let source = (0..<count).map { _ in rich[Int(rng.next() % UInt64(rich.count))] }.joined(separator: separator)
            let whole = MarkdownDocument.parseWhole(source)
            for step in [1, 3, 7] where streamed(source, scalars: step) != whole {
                failures.append("step \(step): \(source.debugDescription)")
                break
            }
            if failures.count >= 5 { break }
        }
        #expect(failures.isEmpty, "\(failures)")
    }

    @Test func aTailThatEndsInCarriageReturnThenLineFeedEqualsOneCRLF() {
        var doc = MarkdownDocument()
        doc.append("- a\r")
        doc.append("\n- b")
        #expect(doc.blocks == MarkdownDocument.parseWhole("- a\r\n- b"))
        #expect(render(doc.blocks) == "ul/tight[[p'a'] [p'b']]")
    }
}

@Suite struct StreamingWorkTests {
    private func counted<T>(_ body: () -> T) -> (T, scanned: Int, finalized: Int, copied: Int) {
        MarkdownParseStats.reset()
        let value = body()
        return (value, MarkdownParseStats.bytesScanned, MarkdownParseStats.blocksFinalized, MarkdownParseStats.bytesCopied)
    }

    private func document(finalBlocks k: Int, last: String) -> MarkdownDocument {
        var doc = MarkdownDocument()
        for i in 0..<k { doc.append("paragraph number \(i) of the reply\n\n") }
        doc.append(last)
        return doc
    }

    /// One token after k final blocks scans the last block and the token, for every k. Reddens when the parse
    /// starts at byte 0 instead of the tail.
    @Test func appendingATokenScansOnlyTheTailAndTheToken() {
        let last = "the block being written"
        let token = " now"
        var scanned: [Int] = []
        for k in [1, 10, 1000] {
            var doc = document(finalBlocks: k, last: last)
            #expect(doc.blocks.count == k + 1)
            let (_, bytes, _, _) = counted { doc.append(token) }
            scanned.append(bytes)
            #expect(doc.blocks.count == k + 1)
        }
        let expected = last.utf8.count + token.utf8.count
        #expect(scanned == [expected, expected, expected], "k = 1, 10 and 1000 must each scan exactly the tail and the token: \(scanned)")
    }

    /// While a line holds a letter the block above is final; while it is still only structure characters
    /// (`-`, `1`) that block stays in the tail too, and no further.
    @Test func aHalfTypedStructureLineKeepsExactlyOneBlockAboveItInTheTail() {
        let above = "the block above"
        var doc = document(finalBlocks: 500, last: above + "\n\n")
        // a letter line: only the line itself and the token are scanned, however long the block above is
        doc.append("T")
        let (_, letter, _, _) = counted { doc.append("hen") }
        #expect(letter == "T".utf8.count + "hen".utf8.count, "scanned \(letter)")
        // a structure-only line: the block above (and its blank line) is parsed again with it
        var second = document(finalBlocks: 500, last: above + "\n\n")
        second.append("1")
        let (_, structure, _, _) = counted { second.append(".") }
        #expect(structure == above.utf8.count + 2 + "1.".utf8.count, "scanned \(structure)")
        // ...and the block above is only kept, never re-finalised: the document still equals a whole parse
        second.append(" item")
        #expect(second.blocks.count == 502)
        #expect(render(Array(second.blocks.suffix(2))) == "p'\(above)' ol1/tight[[p'item']]")
    }

    @Test func blocksAreFinalisedOnceEachAsTheNextOneStarts() {
        var doc = MarkdownDocument()
        MarkdownParseStats.reset()
        for i in 0..<20 { doc.append("block \(i)\n\n") }
        doc.append("end")
        #expect(MarkdownParseStats.blocksFinalized == 20)
        #expect(doc.blocks.count == 21)
    }

    /// A document copied by a "view" and then appended to copies only the tail, never the final blocks' bytes.
    /// Reddens when the document stores one growing source array.
    @Test func divergingFromACopyCopiesOnlyTheTail() {
        let last = "tail of the block"
        var doc = document(finalBlocks: 1000, last: last)
        let viewCopy = doc
        let whole = doc.blocks.count
        let (_, _, _, copied) = counted { doc.append("!") }
        #expect(copied > 0, "the shared tail must be copied once: the instrument works")
        #expect(copied <= last.utf8.count, "copied \(copied) bytes, the tail is \(last.utf8.count)")
        #expect(viewCopy.blocks.count == whole)
        #expect(render(Array(viewCopy.blocks.suffix(1))) == "p'\(last)'", "the copy is unchanged")
        #expect(render(Array(doc.blocks.suffix(1))) == "p'\(last)!'")
        // an unshared document copies nothing
        let (_, _, _, again) = counted { doc.append("?") }
        #expect(again == 0)
    }
}
