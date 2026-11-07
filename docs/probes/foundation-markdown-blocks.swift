// Foundation probe: what `AttributedString(markdown:, interpretedSyntax: .full)` answers on the block
// structure the arms below choose between (arms B1-B30, with B6b), and what ruling each one sets.
//
// Evidence for rulings BM-B (the scope and the oracle) and BM-C (finality) in
// docs/superpowers/2026-11-07-block-markdown-decisions.md; the oracle test is
// Tests/MetalUITests/MarkdownBlockOracleTests.swift. Darwin only: `.full` and `presentationIntent` do not
// exist off Apple platforms (the inline probe, foundation-markdown-inline.swift, records L2/L3).
//
// HOW TO RUN, from the repository root:
//
//   xcrun swiftc docs/probes/foundation-markdown-blocks.swift -o /tmp/md-blocks && /tmp/md-blocks
//
// RECORDED 2026-11-07 on macOS 27.2 (each run is "block stack  text  inline intent"; a stack lists
// the block and its ancestors outermost first, `#n` is the block's identity; inline intent 64 is a soft
// break, 128 a hard break). What the arms decide:
//
//   B1-B3   soft break is a " " run, hard break (two spaces or a backslash) a "\n" run: MetalUI's inline parser
//           already reads both that way, so `MarkdownTheme.softBreak` defaults to a space (BM-E).
//   B4      task lists are plain paragraph text (no checkbox intent): v1 agrees by not parsing them (BM-B).
//   B5-B6b  table alignment: a long row is cut, a short row's missing cell has no run, "no alignment" reads
//           as left (the oracle maps `.none` to left), centre and right are reported (BM-B).
//   B7-B8   a loose list carries the same intents as a tight one: Foundation cannot show tightness, so test 1
//           pins it, not the oracle (BM-B).
//   B9      the language hint is the WHOLE info string ("swift linenos"); v1 takes its first word (BM-B).
//   B10-B16 lazy continuation, a rule after an item, equals after an item, setext levels, empty items (no run:
//           the next item keeps its ordinal 2), "4." not interrupting a paragraph, an item with two paragraphs.
//   B17     a table starts at the paragraph's LAST line; the earlier lines stay a paragraph.
//   B18-B21 once a delimiter-looking line has failed to match a paragraph's last line, the paragraph can never
//           become a table (B18, B19); a delimiter-looking line that was indented (B20) or lazy (B21) made no
//           attempt, so it does not (BM-B; the parser's `tableRefused`).
//   B22-B25 a fence with one blank line has text "\n", an empty fence no run; indented code keeps inner blank
//           lines; a rule is one run "⸻".
//   B26     ATX closing sequences, seven hashes and "#nospace" are not headings.
//   B27-B28 a one-column table needs no outer pipes; the delimiter row may be a bare ":-".
//   B29-B30 nesting; ")" and "." ordered lists.
//
//     B1 "a\nb"
//         p#1 "a"
//         p#1 " " inline=64
//         p#1 "b"
//     B2 "a  \nb"
//         p#1 "a"
//         p#1 "\n" inline=128
//         p#1 "b"
//     B3 "a\\\nb"
//         p#1 "a"
//         p#1 "\n" inline=128
//         p#1 "b"
//     B4 "- [ ] a\n- [x] b"
//         ul#1>li1#2>p#3 "[ ] a"
//         ul#1>li2#4>p#5 "[x] b"
//     B5 "|a|b|\n|:-|-:|\n|1|2|3|\n|4|"
//         table[left,right]#1>th#2>td0#3 "a"
//         table[left,right]#1>th#2>td1#4 "b"
//         table[left,right]#1>tr1#5>td0#6 "1"
//         table[left,right]#1>tr1#5>td1#7 "2"
//         table[left,right]#1>tr2#8>td0#9 "4"
//     B6 "|a|b|\n|-|-|"
//         table[left,left]#1>th#2>td0#3 "a"
//         table[left,left]#1>th#2>td1#4 "b"
//     B6b "|a|b|c|\n|:-|:-:|-:|"
//         table[left,center,right]#1>th#2>td0#3 "a"
//         table[left,center,right]#1>th#2>td1#4 "b"
//         table[left,center,right]#1>th#2>td2#5 "c"
//     B7 "- a\n- b\n\n- c"
//         ul#1>li1#2>p#3 "a"
//         ul#1>li2#4>p#5 "b"
//         ul#1>li3#6>p#7 "c"
//     B8 "- a\n- b"
//         ul#1>li1#2>p#3 "a"
//         ul#1>li2#4>p#5 "b"
//     B9 "```swift linenos\ncode\n```"
//         code(swift linenos)#1 "code\n"
//     B10 "> a\nb\n\n> c"
//         bq#1>p#2 "a"
//         bq#1>p#2 " " inline=64
//         bq#1>p#2 "b"
//         bq#3>p#4 "c"
//     B11 "- a\n---"
//         ul#1>li1#2>p#3 "a"
//         hr#4 "⸻"
//     B12 "- a\n==="
//         ul#1>li1#2>p#3 "a"
//         ul#1>li1#2>p#3 " " inline=64
//         ul#1>li1#2>p#3 "==="
//     B13 "a\n===\n\nb\n---"
//         h1#1 "a"
//         h2#2 "b"
//     B14 "-\n- b\n-"
//         ul#1>li2#3>p#4 "b"
//     B15 "3. a\n   4. b"
//         ol#1>li3#2>p#3 "a"
//         ol#1>li3#2>p#3 " " inline=64
//         ol#1>li3#2>p#3 "4. b"
//     B16 "- a\n\n  b\n- c"
//         ul#1>li1#2>p#3 "a"
//         ul#1>li1#2>p#4 "b"
//         ul#1>li2#5>p#6 "c"
//     B17 "x\n|a|b|\n|-|-|\n|c|d|"
//         p#1 "x"
//         table[left,left]#2>th#3>td0#4 "a"
//         table[left,left]#2>th#3>td1#5 "b"
//         table[left,left]#2>tr1#6>td0#7 "c"
//         table[left,left]#2>tr1#6>td1#8 "d"
//     B18 "a\n|-|-|\n|-|-|"
//         p#1 "a"
//         p#1 " " inline=64
//         p#1 "|-|-|"
//         p#1 " " inline=64
//         p#1 "|-|-|"
//     B19 "a\n|-|-|\n|b|c|\n|-|-|"
//         p#1 "a"
//         p#1 " " inline=64
//         p#1 "|-|-|"
//         p#1 " " inline=64
//         p#1 "|b|c|"
//         p#1 " " inline=64
//         p#1 "|-|-|"
//     B20 "a\n    |-|-|\n|b|c|\n|-|-|"
//         p#1 "a"
//         p#1 " " inline=64
//         p#1 "|-|-|"
//         table[left,left]#2>th#3>td0#4 "b"
//         table[left,left]#2>th#3>td1#5 "c"
//     B21 "> a\n|-|-|\n> |b|c|\n> |-|-|"
//         bq#1>p#2 "a"
//         bq#1>p#2 " " inline=64
//         bq#1>p#2 "|-|-|"
//         bq#1>table[left,left]#3>th#4>td0#5 "b"
//         bq#1>table[left,left]#3>th#4>td1#6 "c"
//     B22 "```\n\n```"
//         code(nil)#1 "\n"
//     B23 "```\n```"
//     B24 "    a\n     b\n\n    c"
//         code(nil)#1 "a\n b\n\nc\n"
//     B25 "---"
//         hr#1 "⸻"
//     B26 "# h #\n## h2 ##  \n####### no\n#nospace"
//         h1#1 "h"
//         h2#2 "h2"
//         p#3 "####### no"
//         p#3 " " inline=64
//         p#3 "#nospace"
//     B27 "a\n|-|\n|b|"
//         table[left]#1>th#2>td0#3 "a"
//         table[left]#1>tr1#4>td0#5 "b"
//     B28 "a\n:-"
//         table[left]#1>th#2>td0#3 "a"
//     B29 "- a\n  - b\n    - c"
//         ul#1>li1#2>p#3 "a"
//         ul#1>li1#2>ul#4>li1#5>p#6 "b"
//         ul#1>li1#2>ul#4>li1#5>ul#7>li1#8>p#9 "c"
//     B30 "1) a\n2) b"
//         ol#1>li1#2>p#3 "a"
//         ol#1>li2#4>p#5 "b"

import Foundation

// One arm: an id, the Markdown source, and what the arm decides.
let arms: [(id: String, source: String)] = [
    ("B1", "a\nb"),                                   // soft break: one run " " with inline intent 64
    ("B2", "a  \nb"),                                 // hard break: a "\n" run with inline intent 128
    ("B3", "a\\\nb"),                                 // backslash hard break
    ("B4", "- [ ] a\n- [x] b"),                       // task list: plain paragraph text, no checkbox intent
    ("B5", "|a|b|\n|:-|-:|\n|1|2|3|\n|4|"),           // alignment, a long row cut, a short row's missing cell has no run
    ("B6", "|a|b|\n|-|-|"),                           // no alignment reads as left (Foundation has no "none")
    ("B6b", "|a|b|c|\n|:-|:-:|-:|"),                  // left, centre, right all reported
    ("B7", "- a\n- b\n\n- c"),                        // loose list: identical intents to a tight one
    ("B8", "- a\n- b"),                               // tight list
    ("B9", "```swift linenos\ncode\n```"),            // the hint is the whole info string
    ("B10", "> a\nb\n\n> c"),                         // lazy continuation
    ("B11", "- a\n---"),                              // a rule after a list item: list, then a break
    ("B12", "- a\n==="),                              // equals after a list item: lazy text, not a heading
    ("B13", "a\n===\n\nb\n---"),                      // setext levels
    ("B14", "-\n- b\n-"),                             // empty items have no run: the ordinal still counts
    ("B15", "3. a\n   4. b"),                         // 4 cannot interrupt the paragraph
    ("B16", "- a\n\n  b\n- c"),                       // an item holding two paragraphs
    ("B17", "x\n|a|b|\n|-|-|\n|c|d|"),                // a table starts mid-paragraph; the earlier lines stay a paragraph
    ("B18", "a\n|-|-|\n|-|-|"),                       // a failed delimiter row poisons the paragraph: no table
    ("B19", "a\n|-|-|\n|b|c|\n|-|-|"),                // ...even for a later well-formed header
    ("B20", "a\n    |-|-|\n|b|c|\n|-|-|"),            // an indented delimiter-looking line is not an attempt: a table
    ("B21", "> a\n|-|-|\n> |b|c|\n> |-|-|"),          // nor is a lazy one
    ("B22", "```\n\n```"),                            // a fence holding one blank line: text "\n"
    ("B23", "```\n```"),                              // an empty fence has no run
    ("B24", "    a\n     b\n\n    c"),                // indented code keeps inner blank lines
    ("B25", "---"),                                   // a thematic break is one run
    ("B26", "# h #\n## h2 ##  \n####### no\n#nospace"),
    ("B27", "a\n|-|\n|b|"),                           // a one-column table needs no outer pipes on its header
    ("B28", "a\n:-"),                                 // ...nor a delimiter row with pipes
    ("B29", "- a\n  - b\n    - c"),                   // nesting
    ("B30", "1) a\n2) b"),                            // both ordered delimiters are one list type
]

func name(_ kind: PresentationIntent.Kind) -> String {
    switch kind {
    case .paragraph: return "p"
    case .header(let level): return "h\(level)"
    case .orderedList: return "ol"
    case .unorderedList: return "ul"
    case .listItem(let ordinal): return "li\(ordinal)"
    case .codeBlock(let hint): return "code(\(hint ?? "nil"))"
    case .blockQuote: return "bq"
    case .thematicBreak: return "hr"
    case .table(let columns): return "table[" + columns.map { "\($0.alignment)" }.joined(separator: ",") + "]"
    case .tableHeaderRow: return "th"
    case .tableRow(let row): return "tr\(row)"
    case .tableCell(let column): return "td\(column)"
    @unknown default: return "?"
    }
}

for (id, source) in arms {
    let parsed = try AttributedString(markdown: source, options: .init(interpretedSyntax: .full))
    print("\(id) \(source.debugDescription)")
    for run in parsed.runs {
        let stack = (run.presentationIntent?.components ?? []).reversed().map { "\(name($0.kind))#\($0.identity)" }.joined(separator: ">")
        let inline = run.inlinePresentationIntent.map { " inline=\($0.rawValue)" } ?? ""
        print("    \(stack) \(String(parsed[run.range].characters).debugDescription)\(inline)")
    }
}
