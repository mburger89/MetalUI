import Foundation
import Testing
import MetalUITextSystem
@testable import MetalUI

// Rich text, lane 3 — `Text(AttributedString)` over MetalUI's attribute scope,
// code spans and links (rulings RT-B item 5, RT-D, RT-K; spec §4.3 tests 3.9,
// 3.13, 3.14). Runs on Linux and Windows too, and **writes every key by its
// dynamic-member spelling** (`RT-O` item 16), so the Linux image compiles the
// per-key subscripts (guard 3.12 is macOS-only).

/// **3.9** (`C11`, `C12`, `C12b`; ruling RT-D item 4). Every key of the scope
/// builds the run its modifier spelling builds: an attributed string is the
/// concatenation. Red before: the stub read no attribute. Mutation **M3.9**:
/// ignore `kern`.
@MainActor
@Test func anAttributedStringBuildsTheConcatenationsRuns() {
    var s = AttributedString("fcbusktol")
    func range(_ i: Int) -> Range<AttributedString.Index> {
        s.index(s.startIndex, offsetByCharacters: i)..<s.index(s.startIndex, offsetByCharacters: i + 1)
    }
    s[range(0)].font = .title
    s[range(1)].foregroundColor = .red
    s[range(2)].backgroundColor = .yellow
    s[range(3)].underlineStyle = Text.LineStyle(pattern: .solid, color: .blue)
    s[range(4)].strikethroughStyle = .single
    s[range(5)].kern = 2
    s[range(6)].tracking = 3
    s[range(7)].baselineOffset = 4
    s[range(8)].link = URL(string: "https://x.org")
    let expected: [TextRunRequest] = [
        segments(Text("f").font(.title))[0],
        segments(Text("c").foregroundColor(.red))[0],
        TextRunRequest(string: "b", background: .yellow),
        segments(Text("u").underline(color: .blue))[0],
        segments(Text("s").strikethrough())[0],
        segments(Text("k").kerning(2))[0],
        segments(Text("t").tracking(3))[0],
        segments(Text("o").baselineOffset(4))[0],
        TextRunRequest(string: "l", link: "https://x.org"),
    ]
    #expect(segments(Text(s)) == expected, "\(Text(s).content)")
    #expect(ProposalText(s).content == .runs(expected), "ProposalText reads the same runs")

    var joined = AttributedString("ab")
    joined.foregroundColor = .red
    #expect(segments(Text(joined)) == [TextRunRequest(string: "ab", foreground: .red)],
            "neighbours that resolve alike are one run")
    #expect(Text(AttributedString("")).string == "", "an empty attributed string is an empty text")
}

/// **3.13** (`M5`; ruling RT-B item 5, `RT-O` item 12). A code span is the
/// run's font made monospaced: the run sets `monospaced`, and its descriptor
/// asks the system face's `.monospaced` design (on the portable system the
/// face is whatever `TE-B` resolves for it). Red before: the stub parsed
/// nothing. Mutation **M3.13**: map code to italic.
@MainActor
@Test func theCodeSpanIsMonospaced() throws {
    let runs = segments(Text("a `c`"))
    try #require(runs.count == 2, "\(runs)")
    #expect(runs[1] == TextRunRequest(string: "c", monospaced: true), "\(runs[1])")
    let request = TextStyleRequest(font: runs[1].font ?? .inherit, weight: runs[1].weight,
                                   italic: runs[1].italic ?? false, foreground: nil,
                                   monospaced: runs[1].monospaced ?? false)
    let descriptor = resolveTextStyle(request, in: EnvironmentValues()).descriptor
    #expect(descriptor.design == .monospaced && !descriptor.italic, "\(descriptor)")
}

/// **3.14** (`M6`, `M20`, `M21`; ruling RT-K). A Markdown link and an
/// attributed link build one run kind — the destination on `link`; `www.`
/// gains `http://`, an e-mail address `mailto:`. Red before: the stub built
/// no link. Mutation **M3.14**: drop the `http://` prefix for `www.`.
@MainActor
@Test func aMarkdownLinkAndAnAttributedLinkBuildOneRunKind() {
    var attributed = AttributedString("site")
    attributed.link = URL(string: "https://x.org")
    #expect(segments(Text(attributed)) == segments(Text("[site](https://x.org)")),
            "\(Text(attributed).content) vs \(Text("[site](https://x.org)").content)")
    #expect(segments(Text("www.x.org")) == [TextRunRequest(string: "www.x.org", link: "http://www.x.org")])
    #expect(segments(Text("a@b.org")) == [TextRunRequest(string: "a@b.org", link: "mailto:a@b.org")])
}
