import Foundation
import Testing
@testable import MetalUIText

/// **The runs are UAX #14 soft-wrap opportunities, not word boundaries.** The
/// hyphen tells the two apart: a line breaker keeps the hyphen with the text
/// before it (`"well-"`, which is what will actually sit on that line), while a
/// word enumerator throws it away (`"well"`). The second half of this test
/// **measures** the word enumerator rather than asserting it from memory — the
/// first draft of this comment claimed it kept `"well-known"` whole, which is
/// not what it does.
///
/// This matters because the widest run is the min-content width a text item is
/// floored at (§4.5), so the difference is a floor that is wrong by a hyphen's
/// width on every hyphenated word — and, measured on the same API,
/// `"日本語のテキスト"` enumerates as `["日本", "語", "の", "テキスト"]`, which
/// is dictionary segmentation rather than the per-character break CSS wraps CJK
/// at.
@Test func unbreakableRunsAreLineBreakOpportunitiesNotWordBoundaries() {
    #expect(Shaper.unbreakableRuns(of: "a bb supercalifragilistic dd")
            == ["a", "bb", "supercalifragilistic", "dd"])
    #expect(Shaper.unbreakableRuns(of: "well-known thing") == ["well-", "known", "thing"])
    #expect(Shaper.unbreakableRuns(of: "hello\nworld") == ["hello", "world"])
    #expect(Shaper.unbreakableRuns(of: "日本語") == ["日", "本", "語"])
    #expect(Shaper.unbreakableRuns(of: "one") == ["one"])

    // What a word enumerator answers for the same string, measured here rather
    // than claimed: it drops the hyphen entirely.
    var words: [String] = []
    let subject = "well-known thing"
    subject.enumerateSubstrings(in: subject.startIndex ..< subject.endIndex,
                                options: .byWords) { word, _, _, _ in
        if let word { words.append(word) }
    }
    #expect(words == ["well", "known", "thing"])
    #expect(Shaper.unbreakableRuns(of: subject) != words)
}

/// Trailing whitespace is trimmed from every run and a whitespace-only run is
/// dropped, so an empty or blank string has **no** runs — a caller's `max` must
/// therefore start at 0 rather than at `runs[0]`.
///
/// CSS's reason for the trim is that trailing spaces hang past a soft wrap;
/// the measured consequence is in `textMeasure`'s tests — min-content for
/// `"a bb supercalifragilistic dd"` is 110.348 with the trim and 113.928
/// without, and 110.348 is exactly the width at which CoreText stops breaking
/// the long word in half.
@Test func runsAreTrimmedOfTrailingWhitespaceAndBlankOnesAreDropped() {
    #expect(Shaper.unbreakableRuns(of: "") == [])
    #expect(Shaper.unbreakableRuns(of: "   ") == [])
    #expect(Shaper.unbreakableRuns(of: "trail  ") == ["trail"])
    #expect(Shaper.unbreakableRuns(of: "  lead") == ["lead"])
    #expect(Shaper.unbreakableRuns(of: "a  b") == ["a", "b"])
}
