import Foundation
import Testing
@testable import MetalUIText

private var font: ResolvedFont { FontResolver.resolve(family: nil, size: 13) }

/// Forty distinct strings shaped like the demo's rows, so every one is a
/// `minContentWidth` MISS — the only branch that tokenizes at all.
private func distinctRows(_ tag: String) -> [String] {
    (0..<40).map { "Row \($0 + 1) of 40 (\(tag)) — a scrollable list item" }
}

/// **A min-content miss must not create a `CFStringTokenizer` per string.**
/// Creation is a fixed setup cost independent of the string's length, so on a
/// UI's short strings it dominated each miss; `minContentWidth` now re-points
/// one main-actor tokenizer. Red on arrival: 40 creations in each pass.
///
/// - The **first** pass may create one: the tokenizer is process-wide, so
///   whether this test or an earlier one creates it depends on test order.
///   The **second**, on a fresh cache, must create none — it is still all
///   misses, which is what makes that zero mean anything.
/// - `calls == 40` in each pass is the reachability control **and** the pin on
///   the hazard: the reusing path must still bump `Shaper.runCallCounter`, or
///   every existing count test that reads it (`aWarmFrameTokenizesEach…`,
///   `aListsWorkIsTheSameFor160RowsAsFor40`) reads 0 and passes forever.
@MainActor
@Test func aMinContentMissReusesOneTokenizerRatherThanCreatingOnePerString() {
    let first = ShapingCache()
    let firstCalls = Shaper.RunCallCounter()
    let firstCreations = Shaper.RunCallCounter()
    Shaper.$runCallCounter.withValue(firstCalls) {
        Shaper.$tokenizerCreationCounter.withValue(firstCreations) {
            for s in distinctRows("first") { _ = first.minContentWidth(s, font: font) }
        }
    }

    let second = ShapingCache()
    let secondCalls = Shaper.RunCallCounter()
    let secondCreations = Shaper.RunCallCounter()
    Shaper.$runCallCounter.withValue(secondCalls) {
        Shaper.$tokenizerCreationCounter.withValue(secondCreations) {
            for s in distinctRows("second") { _ = second.minContentWidth(s, font: font) }
        }
    }

    #expect(firstCalls.count == 40)
    #expect(secondCalls.count == 40)
    #expect(firstCreations.count <= 1)
    #expect(secondCreations.count == 0)
}

/// The strings a reused tokenizer is most likely to answer differently for,
/// if it answers differently at all: scripts that break by dictionary or by
/// cluster, every separator class that is or is not a break, and pairs of
/// equal UTF-16 length with different content (a re-point that kept the old
/// string or range would still walk the right number of units).
private let identityCorpus: [String] = [
    "مرحبا بالعالم، هذا نص عربي للاختبار",                 // Arabic
    "สวัสดีครับยินดีต้อนรับสู่การทดสอบ",                    // Thai, no spaces
    "नमस्ते दुनिया, यह हिंदी पाठ है",                          // Devanagari
    "👨‍👩‍👧‍👦 family 🏳️‍🌈 flag 👍🏽",                     // ZWJ sequences, modifiers
    "line\u{2028}separator\u{2029}paragraph",               // U+2028 / U+2029
    "hyph\u{00AD}en\u{00AD}ation and co\u{00AD}operation", // soft hyphen
    "no\u{00A0}break\u{00A0}here but here",                 // NBSP
    "zero\u{200B}width\u{200B}space",                       // ZWSP
    "first\r\nsecond\r\n\r\nthird",                         // CRLF
    "obj\u{FFFC}ect \u{FFFC} replacement",                  // U+FFFC
    "a bb supercalifragilistic dd",
    "well-known thing",
    "日本語のテキスト",
    "Row 1 of 40 — a scrollable list item",
    "abc def",
    "xyz uvw",                                              // same length as "abc def"
    "x",
    "",
    "   ",
    "trail  ",
]

/// `ShapingCache.minContentWidth` now reads its runs from one re-pointed
/// tokenizer rather than a fresh one, and the walk is shared, so the only way
/// the two can differ is state the reused tokenizer carries from its previous
/// string. **Every ordered pair** of the corpus is visited — each string is
/// asked for right after every other string, including itself and including a
/// longer or shorter one — and each answer is compared with a fresh tokenizer's.
@MainActor
@Test func theReusedTokenizerAnswersExactlyAsAFreshOneDoes() throws {
    let fresh = identityCorpus.map { Shaper.unbreakableRuns(of: $0) }
    // The corpus must be able to disagree: a reused tokenizer answering with
    // its PREVIOUS string's runs is only visible if neighbours' runs differ.
    try #require(Set(fresh).count == identityCorpus.count - 1)   // "" and "   " are both []

    var comparisons = 0
    var previous = "(none)"
    func ask(_ k: Int) {
        let reused = Shaper.unbreakableRunsReusingTokenizer(of: identityCorpus[k])
        #expect(reused == fresh[k],
                "\(identityCorpus[k].debugDescription) asked right after \(previous.debugDescription)")
        previous = identityCorpus[k]
        comparisons += 1
    }
    for i in identityCorpus.indices {
        for j in identityCorpus.indices {
            ask(i)
            ask(j)
        }
    }
    #expect(comparisons == identityCorpus.count * identityCorpus.count * 2)
}
