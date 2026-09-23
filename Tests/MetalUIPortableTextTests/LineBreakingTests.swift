import Testing
@testable import MetalUIPortableText

// LB-B and LB-C's contract, independent of the oracle.

@Test func breakOpportunitiesAreUAX14sAfterEachUTF16Unit() {
    #expect(PortableText.lineBreaks(in: "") == [])
    // After "b" no, after the space allowed, after "\n" mandatory, and the end
    // of the text is mandatory (LB3).
    #expect(PortableText.lineBreaks(in: "ab c\nd")
            == [.none, .none, .allowed, .none, .mandatory, .mandatory])
    // A surrogate pair: no break between its halves.
    let pair = PortableText.lineBreaks(in: "a \u{1F600} b")
    #expect(pair.count == 6)
    #expect(pair[2] == .none)
    // A no-break space joins; a closing parenthesis does not start a line.
    #expect(PortableText.lineBreaks(in: "a\u{A0}b")[1] == .none)
    #expect(PortableText.lineBreaks(in: "a )")[1] == .none)
}

@Test func linesKeepShapersContract() throws {
    let font = try PortableFont(data: fontBytes(notoSans), size: 13)
    // An empty string is one empty line.
    #expect(try PortableText.lines("", font: font, wrappingAt: nil) == [PortableLine(range: 0..<0, advance: 0)])
    // No width: one line per hard break, and a trailing break opens no line.
    #expect(try PortableText.lines("Ready\nSet\nGo", font: font, wrappingAt: nil).map(\.range)
            == [0..<6, 6..<10, 10..<12])
    #expect(try PortableText.lines("Ready\n", font: font, wrappingAt: nil).map(\.range) == [0..<6])
    // CR LF is one hard break.
    #expect(try PortableText.lines("a\r\nb", font: font, wrappingAt: nil).map(\.range) == [0..<3, 3..<4])
    // Lines tile the string with no gap and no overlap.
    let text = "The quick brown fox jumps over the lazy dog."
    let lines = try PortableText.lines(text, font: font, wrappingAt: 50)
    #expect(lines.first?.range.lowerBound == 0)
    #expect(lines.last?.range.upperBound == text.utf16.count)
    #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.range.upperBound == $1.range.lowerBound })
}

@Test func aNonPositiveWidthTraps() async {
    await #expect(processExitsWith: .failure) {
        let font = try PortableFont(data: fontBytes(notoSans), size: 13)
        _ = try PortableText.lines("x", font: font, wrappingAt: 0)
    }
}
