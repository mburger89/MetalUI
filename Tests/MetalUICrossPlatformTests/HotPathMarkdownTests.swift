import Testing
@testable import MetalUI

/// Test 9 (`HP-D`). A literal's Markdown format is parsed once per distinct key: a second `Text` made from
/// the same key leaves the parse counter where it was, a different key parses once. Red before: every
/// `Text.init` parsed. Mutation: remove the table.
@MainActor
@Test func aSteadyMarkdownLiteralParsesZeroTimes() {
    let before = markdownParserRuns
    let first = Text("**hot-path-one** and _two_")
    #expect(markdownParserRuns == before + 1)
    for _ in 0..<5 { _ = Text("**hot-path-one** and _two_") }
    #expect(markdownParserRuns == before + 1, "\(markdownParserRuns - before - 1) re-parses of one key")
    _ = Text("**hot-path-three**")
    #expect(markdownParserRuns == before + 2)
    // The table answers what the parser answers.
    #expect(first.content == Text("**hot-path-one** and _two_").content)
    // An interpolated value is part of the key: a changed value parses again and shows its own text.
    let n = 7, m = 8
    let a = Text("**hot-path-n** \(n)"), b = Text("**hot-path-n** \(m)")
    #expect(a.content != b.content)
}
