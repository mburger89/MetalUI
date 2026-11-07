import Testing
@testable import MetalUIMarkdown

// Tests 1-3 and 7 of the block-markdown plan (rulings BM-A, BM-B, BM-D). Expectations are cmark-gfm's; on
// Darwin `MarkdownOracleBlockTests` (MetalUITests) compares the same structures against Foundation.

@Suite struct BlockKindTests {
    @Test func paragraphsJoinTheirLinesAndDropIndentation() {
        #expect(parse("a\nb") == "p'a¶b'")
        #expect(parse("a\n   b\n\nc") == "p'a¶b' p'c'")
        #expect(parse("a  \nb") == "p'a  ¶b'")  // the two spaces are a hard break for the inline parser
        #expect(parse("  a  ") == "p'a'")
        #expect(parse("").isEmpty && parse("\n\n").isEmpty)
    }

    @Test func atxHeadingsOfEveryLevel() {
        #expect(parse("# a\n## b\n### c\n#### d\n##### e\n###### f") == "h1'a' h2'b' h3'c' h4'd' h5'e' h6'f'")
        #expect(parse("####### a") == "p'####### a'")
        #expect(parse("#a") == "p'#a'")
        #expect(parse("# a ##") == "h1'a'")
        #expect(parse("## a \\##") == "h2'a \\##'")
        #expect(parse("### ###") == "h3''")
        #expect(parse("#") == "h1''")
        #expect(parse("# a #b") == "h1'a #b'")
    }

    @Test func setextHeadingsTakeTheWholeParagraph() {
        #expect(parse("a\n===") == "h1'a'")
        #expect(parse("a\nb\n---") == "h2'a¶b'")
        #expect(parse("a\n=") == "h1'a'")
        #expect(parse("- a\n---") == "ul/tight[[p'a']] hr")  // the rule ends the list, it is not a setext line
        #expect(parse("- a\n===") == "ul/tight[[p'a¶===']]")  // an equals line is a lazy continuation
        #expect(parse("> a\n---") == "bq[p'a'] hr")
        #expect(parse("===") == "p'==='")
    }

    @Test func fencedAndIndentedCode() {
        #expect(parse("```swift x\nlet a = 1\n```") == "code(swift,closed)'let a = 1'")
        #expect(parse("~~~\na\n~~~") == "code(-,closed)'a'")
        #expect(parse("```\nunclosed\n\nmore") == "code(-,open)'unclosed¶¶more'")
        #expect(parse("````\n```\n````") == "code(-,closed)'```'")
        #expect(parse("```\na\n``") == "code(-,open)'a¶``'")
        #expect(parse("``` a`b\nx") == "p'``` a`b¶x'")  // a backtick in a backtick fence's info string is not a fence
        #expect(parse("  ```js\n  a\n   b\n c\n  ```") == "code(js,closed)'a¶ b¶c'")
        #expect(parse("    a\n     b\n\n    c\n\n\n") == "code(-,closed)'a¶ b¶¶c'")
        #expect(parse("a\n    b") == "p'a¶b'")  // indented code cannot interrupt a paragraph
        #expect(parse("```\n```\nx") == "p'x'")  // an empty fence has no text
    }

    @Test func blockQuotesAndThematicBreaks() {
        #expect(parse("> a\n> b") == "bq[p'a¶b']")
        #expect(parse("> a\nb") == "bq[p'a¶b']")  // lazy continuation
        #expect(parse("> a\n\nb") == "bq[p'a'] p'b'")
        #expect(parse("> > a\n> b") == "bq[bq[p'a¶b']]")
        #expect(parse(">a") == "bq[p'a']")
        #expect(parse("> # h\n> ```\n> x") == "bq[h1'h' code(-,open)'x']")
        #expect(parse("---\n***\n___\n- - -\n _ _ _") == "hr hr hr hr hr")
        #expect(parse("--\n**") == "p'--¶**'")
    }

    @Test func listsAreTightOrLooseAndKeepTheirStartNumber() {
        #expect(parse("- a\n- b") == "ul/tight[[p'a'] [p'b']]")
        #expect(parse("- a\n\n- b") == "ul/loose[[p'a'] [p'b']]")
        #expect(parse("- a\n\n  b\n- c") == "ul/loose[[p'a' p'b'] [p'c']]")
        #expect(parse("- a\n- b\n\n  c") == "ul/loose[[p'a'] [p'b' p'c']]")
        #expect(parse("- a\n\n\n- b") == "ul/loose[[p'a'] [p'b']]")
        #expect(parse("3. a\n4. b") == "ol3/tight[[p'a'] [p'b']]")
        #expect(parse("1) a\n2) b") == "ol1/tight[[p'a'] [p'b']]")
        #expect(parse("0. a") == "ol0/tight[[p'a']]")
        #expect(parse("- a\n* b\n+ c") == "ul/tight[[p'a']] ul/tight[[p'b']] ul/tight[[p'c']]")
        #expect(parse("1. a\n1) b") == "ol1/tight[[p'a']] ol1/tight[[p'b']]")
        #expect(parse("-\n- b\n-") == "ul/tight[[] [p'b'] []]")
        #expect(parse("- [ ] a\n- [x] b") == "ul/tight[[p'[ ] a'] [p'[x] b']]")  // task boxes are plain text (BM-B)
        #expect(parse("1234567890. a") == "p'1234567890. a'")
    }

    @Test func aListInterruptsAParagraphOnlyWhenItStartsAtOneAndHasText() {
        #expect(parse("a\n- b") == "p'a' ul/tight[[p'b']]")
        #expect(parse("a\n1. b") == "p'a' ol1/tight[[p'b']]")
        #expect(parse("a\n2. b") == "p'a¶2. b'")
        #expect(parse("a\n-") == "h2'a'")  // an empty bullet is a setext underline here
        #expect(parse("a\n1.") == "p'a¶1.'")
        #expect(parse("a\n*") == "p'a¶*'")
        #expect(parse("a\n\n2. b") == "p'a' ol2/tight[[p'b']]")
    }
}

@Suite struct NestedListTests {
    @Test func theContentColumnDecidesWhatBelongsToAnItem() {
        // the marker and its spaces set the column: "- " is 2, "1. " is 3, "-   " is 4
        #expect(parse("- a\n  - b") == "ul/tight[[p'a' ul/tight[[p'b']]]]")
        #expect(parse("- a\n - b") == "ul/tight[[p'a'] [p'b']]")  // indented 1 < 2: a sibling
        #expect(parse("1. a\n   - b") == "ol1/tight[[p'a' ul/tight[[p'b']]]]")
        #expect(parse("1. a\n  - b") == "ol1/tight[[p'a']] ul/tight[[p'b']]")  // 2 < 3: not inside the item
        #expect(parse("-   a\n  - b") == "ul/tight[[p'a'] [p'b']]")
        #expect(parse("-   a\n    - b") == "ul/tight[[p'a' ul/tight[[p'b']]]]")
        #expect(parse("- a\n  - b\n    - c") == "ul/tight[[p'a' ul/tight[[p'b' ul/tight[[p'c']]]]]]")
        #expect(parse("- a\n  - b\n- c") == "ul/tight[[p'a' ul/tight[[p'b']]] [p'c']]")
        #expect(parse("10. a\n    - b") == "ol10/tight[[p'a' ul/tight[[p'b']]]]")
        #expect(parse("3. a\n   4. b") == "ol3/tight[[p'a¶4. b']]")  // 4 cannot interrupt a paragraph
        #expect(parse("- a\n\n    b") == "ul/loose[[p'a' p'b']]")
        #expect(parse("- a\n\n b") == "ul/tight[[p'a']] p'b'")
        #expect(parse("-\n  a") == "ul/tight[[p'a']]")
        #expect(parse("-\n\n  a") == "ul/tight[[]] p'a'")  // a list item can begin with at most one blank line
    }

    @Test func tabsCountToTheNextMultipleOfFour() {
        #expect(parse("- a\n\t- b") == "ul/tight[[p'a' ul/tight[[p'b']]]]")  // one tab is four columns >= 2
        #expect(parse("-\ta") == "ul/tight[[p'a']]")
        #expect(parse("-\ta\n\t\tb") == "ul/tight[[p'a¶b']]")
        #expect(parse("\ta\n\tb") == "code(-,closed)'a¶b'")
        #expect(parse("  \ta") == "code(-,closed)'a'")  // two spaces and a tab reach column 4
        #expect(parse(" \t a") == "code(-,closed)' a'")
        #expect(parse(">\ta") == "bq[p'a']")
        #expect(parse(">\t\ta") == "bq[code(-,closed)'  a']")  // the tab after > gives one column; the rest is code
    }

    @Test func lazyContinuationBelongsToTheInnermostOpenParagraph() {
        #expect(parse("- a\nb") == "ul/tight[[p'a¶b']]")
        #expect(parse("- a\n  - b\nc") == "ul/tight[[p'a' ul/tight[[p'b¶c']]]]")
        #expect(parse("> - a\nb") == "bq[ul/tight[[p'a¶b']]]")
        #expect(parse("> a\n> b\nc\n\nd") == "bq[p'a¶b¶c'] p'd'")
        #expect(parse("- a\n\nb") == "ul/tight[[p'a']] p'b'")  // not after a blank line
        #expect(parse("> ```\n> a\nb") == "bq[code(-,open)'a'] p'b'")  // never into code
        #expect(parse("- a\n# h") == "ul/tight[[p'a']] h1'h'")  // a block start is not lazy text
    }
}

@Suite struct TableTests {
    @Test func alignmentsComeFromTheDelimiterRow() {
        #expect(parse("|a|b|c|d|\n|:--|:-:|--:|---|\n|1|2|3|4|") == "table(l,c,r,n){a|b|c|d}{1|2|3|4}")
        #expect(parse("a|b\n-|-\nc|d") == "table(n,n){a|b}{c|d}")  // the outer pipes are optional
        #expect(parse("| a | b |\n| :- | -: |") == "table(l,r){a|b}")
    }

    @Test func anEscapedPipeStaysInsideItsCell() {
        #expect(parse("|a\\|b|c|\n|-|-|\n|d|e\\|f|") == "table(n,n){a|b|c}{d|e|f}")
        let doc = MarkdownDocument.parseWhole("|a\\|b|c|\n|-|-|")
        guard case .table(_, let header, _) = doc[0].kind else { Issue.record("not a table"); return }
        #expect(header == ["a|b", "c"])
    }

    @Test func raggedRowsArePaddedOrCutToTheHeader() {
        #expect(parse("|a|b|\n|-|-|\n|1|\n|2|3|4|\n|") == "table(n,n){a|b}{1|}{2|3} p'|'")
        #expect(parse("|a|b|\n|-|-|\n1") == "table(n,n){a|b}{1|}")
    }

    @Test func aHeaderWithoutAMatchingDelimiterRowStaysAParagraph() {
        #expect(parse("|a|b|") == "p'|a|b|'")
        #expect(parse("|a|b|\n|-|") == "p'|a|b|¶|-|'")
        #expect(parse("|a|b|\n|-|-|-|") == "p'|a|b|¶|-|-|-|'")  // three columns against two
        #expect(parse("|a|b|c|\n|-|-|") == "p'|a|b|c|¶|-|-|'")
        #expect(parse("a\n|-|-|") == "p'a¶|-|-|'")
        #expect(parse("|a|b|\n|x|y|") == "p'|a|b|¶|x|y|'")
        // once a delimiter row has failed against a paragraph, a later one cannot make it a table (probe B18, B19)
        #expect(parse("a\n|-|-|\n|-|-|") == "p'a¶|-|-|¶|-|-|'")
        #expect(parse("a\n|-|-|\n|b|c|\n|-|-|") == "p'a¶|-|-|¶|b|c|¶|-|-|'")
        #expect(parse("|a|b|\n\n|-|-|") == "p'|a|b|' p'|-|-|'")
    }

    @Test func aTableStartsMidParagraphAndEndsAtABlankLineOrABlockStart() {
        #expect(parse("x\n|a|b|\n|-|-|\n|c|d|") == "p'x' table(n,n){a|b}{c|d}")
        #expect(parse("|a|b|\n|-|-|\n|c|d|\n\ne") == "table(n,n){a|b}{c|d} p'e'")
        #expect(parse("|a|b|\n|-|-|\n|c|d|\n> q") == "table(n,n){a|b}{c|d} bq[p'q']")
        #expect(parse("|a|b|\n|-|-|\n# h") == "table(n,n){a|b} h1'h'")
        #expect(parse("> |a|b|\n> |-|-|\n> |c|d|") == "bq[table(n,n){a|b}{c|d}]")
        #expect(parse("- |a|b|\n  |-|-|") == "ul/tight[[table(n,n){a|b}]]")
    }
}

@Suite struct IdTests {
    @Test func aBlockKeepsItsIdWhenItChangesKindAndEarlierIdsNeverMove() {
        var doc = MarkdownDocument()
        doc.append("a")
        #expect(doc.blocks == [MarkdownBlock(id: 0, kind: .paragraph("a"))])
        doc.append("\n===")
        #expect(doc.blocks == [MarkdownBlock(id: 0, kind: .heading(level: 1, text: "a"))])
        doc.append("\n\nsecond\n|a|b|")
        doc.append("\n|-|-|\n|c|d|")
        let ids = doc.blocks.map(\.id)
        #expect(ids == [0, 1, 2], "a paragraph and the table split from it take consecutive ids")
        #expect(render(doc.blocks) == "h1'a' p'second' table(n,n){a|b}{c|d}")
        let before = doc.blocks
        doc.append("\n\n- x\n- y")
        #expect(Array(doc.blocks.prefix(3)) == before)
        #expect(doc.blocks.map(\.id) == [0, 1, 2, 3])
    }

    @Test func nestedBlocksNumberThemselvesWithinTheirParent() {
        let blocks = MarkdownDocument.parseWhole("> a\n>\n> b\n\n- x\n\n  y\n- z\n")
        guard case .blockQuote(let inner) = blocks[0].kind, case .list(_, _, _, let items) = blocks[1].kind else {
            Issue.record("unexpected shape")
            return
        }
        #expect(inner.map(\.id) == [0, 1])
        #expect(items.map { $0.map(\.id) } == [[0, 1], [0]])
        #expect(blocks.map(\.id) == [0, 1])
    }
}
