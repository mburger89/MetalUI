import Testing
@testable import MetalUICodeBuffer

// The snippet model and parser (`CV-BP`, record 376). Pure values: no buffer, no state. The session that walks
// the stops is `CV-BQ`.
//
// Mutations run against this file (each reddened the named rows, then was restored):
//  - mirror propagation off (every stop keeps only its own default): `mirrorAfterDefault`, `mirrorBeforeDefault`,
//    `firstDefaultWins`, `transformedMirror`.
//  - `first default wins` taking the last default instead of the first: `firstDefaultWins`.
//  - the implicit `$0` not appended: every row without an explicit `$0`.
//  - a choice taking its last option: `choice`, `choiceEscapes`.
//  - escapes off (`\$` kept as two bytes): `escapes`, `escapedBraceInDefault`.
//  - a variable with a default becoming a stop: `variableWithDefault`, `variableWithNestedStop`.
//  - stops recorded after their children (inner before outer): `nested`.
//  - UTF-8 counted as scalars (`unicode`): `unicode`.
//  - the failed-attempt memo removed: `unclosedNestingIsLinear` times out (exponential).
//  - the validation's partial-overlap test removed: `rejects partial overlap`.

struct CodeSnippetTests {
    struct Row: Sendable, CustomTestStringConvertible {
        var name: String
        var template: String
        var text: String
        /// `(index, start, end)`.
        var stops: [[Int]]
        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(name: "empty", template: "", text: "", stops: [[0, 0, 0]]),
        Row(name: "plain", template: "hello", text: "hello", stops: [[0, 5, 5]]),
        Row(name: "bare", template: "a$1b", text: "ab", stops: [[1, 1, 1], [0, 2, 2]]),
        Row(name: "braced", template: "a${1}b", text: "ab", stops: [[1, 1, 1], [0, 2, 2]]),
        Row(name: "default", template: "${1:x}", text: "x", stops: [[1, 0, 1], [0, 1, 1]]),
        Row(name: "twoDefaults", template: "f(${1:a}, ${2:b})", text: "f(a, b)",
            stops: [[1, 2, 3], [2, 5, 6], [0, 7, 7]]),
        Row(name: "nested", template: "${1:a ${2:b}}", text: "a b", stops: [[1, 0, 3], [2, 2, 3], [0, 3, 3]]),
        Row(name: "selfNested", template: "${1:${1:x}}", text: "x", stops: [[1, 0, 1], [1, 0, 1], [0, 1, 1]]),
        Row(name: "mirrors", template: "$1 and $1", text: " and ", stops: [[1, 0, 0], [1, 5, 5], [0, 5, 5]]),
        Row(name: "mirrorAfterDefault", template: "${1:foo} $1", text: "foo foo",
            stops: [[1, 0, 3], [1, 4, 7], [0, 7, 7]]),
        Row(name: "mirrorBeforeDefault", template: "$1 ${1:foo}", text: "foo foo",
            stops: [[1, 0, 3], [1, 4, 7], [0, 7, 7]]),
        Row(name: "firstDefaultWins", template: "${1:a} ${1:b}", text: "a a", stops: [[1, 0, 1], [1, 2, 3], [0, 3, 3]]),
        Row(name: "transformedMirror", template: #"${1:foo} ${1/o/0/g}"#, text: "foo foo",
            stops: [[1, 0, 3], [1, 4, 7], [0, 7, 7]]),
        Row(name: "escapes", template: #"\$1 \} \\"#, text: #"$1 } \"#, stops: [[0, 6, 6]]),
        Row(name: "escapedBraceInDefault", template: #"${1:a\}b}"#, text: "a}b", stops: [[1, 0, 3], [0, 3, 3]]),
        Row(name: "unknownEscape", template: #"\n"#, text: #"\n"#, stops: [[0, 2, 2]]),
        Row(name: "choice", template: "${1|one,two,three|}", text: "one", stops: [[1, 0, 3], [0, 3, 3]]),
        Row(name: "choiceEscapes", template: #"${1|a\,b,c|}"#, text: "a,b", stops: [[1, 0, 3], [0, 3, 3]]),
        Row(name: "variable", template: "x$TM_FILENAME y", text: "x y", stops: [[0, 3, 3]]),
        Row(name: "variableWithDefault", template: "${NAME:dflt}!", text: "dflt!", stops: [[0, 5, 5]]),
        Row(name: "variableWithNestedStop", template: "${NAME:a${1:b}}", text: "ab", stops: [[1, 1, 2], [0, 2, 2]]),
        Row(name: "variableTransform", template: #"${TM_FILENAME/(.*)\..*/$1/}"#, text: "", stops: [[0, 0, 0]]),
        Row(name: "malformedOpen", template: "${", text: "${", stops: [[0, 2, 2]]),
        Row(name: "malformedNoClose", template: "${1:", text: "${1:", stops: [[0, 4, 4]]),
        Row(name: "malformedDefaultUnclosed", template: "${1:abc", text: "${1:abc", stops: [[0, 7, 7]]),
        Row(name: "unclosedKeepsInnerStop", template: "${1:a $2", text: "${1:a ", stops: [[2, 6, 6], [0, 6, 6]]),
        Row(name: "badName", template: "${a b}", text: "${a b}", stops: [[0, 6, 6]]),
        Row(name: "choiceUnclosed", template: "${1|a,b}", text: "${1|a,b}", stops: [[0, 8, 8]]),
        Row(name: "dollarAlone", template: "$", text: "$", stops: [[0, 1, 1]]),
        Row(name: "dollarInText", template: "cost $ 5", text: "cost $ 5", stops: [[0, 8, 8]]),
        Row(name: "trailingBackslash", template: #"a\"#, text: #"a\"#, stops: [[0, 2, 2]]),
        Row(name: "strayBrace", template: "a}b", text: "a}b", stops: [[0, 3, 3]]),
        Row(name: "explicitZero", template: "$0", text: "", stops: [[0, 0, 0]]),
        Row(name: "explicitZeroKeepsPlace", template: "a$0b$1", text: "ab", stops: [[0, 1, 1], [1, 2, 2]]),
        Row(name: "emptyDefault", template: "${1:}", text: "", stops: [[1, 0, 0], [0, 0, 0]]),
        Row(name: "multiDigit", template: "$12${13:x}", text: "x", stops: [[12, 0, 0], [13, 0, 1], [0, 1, 1]]),
        Row(name: "digitsThenLetter", template: "$1a", text: "a", stops: [[1, 0, 0], [0, 1, 1]]),
        Row(name: "indexOverflow", template: "$99999999999999999999", text: "$99999999999999999999",
            stops: [[0, 21, 21]]),
        Row(name: "unicode", template: "é${1:ü}😀$2", text: "éü😀", stops: [[1, 2, 4], [2, 8, 8], [0, 8, 8]]),
    ]

    @Test(arguments: rows)
    func parserTable(_ row: Row) {
        let s = CodeSnippet(parsing: row.template)
        #expect(s.text == row.text)
        #expect(s.tabStops.map { [$0.index, $0.range.lowerBound, $0.range.upperBound] } == row.stops)
        // Whatever the parser produces satisfies the initialiser's own precondition.
        #expect(CodeSnippet.isValid(text: s.text, tabStops: s.tabStops))
    }

    @Test func unclosedNestingIsLinear() {
        // 60 unclosed `${1:` (inside the depth cap) take 2^60 steps without the memo.
        let s = CodeSnippet(parsing: String(repeating: "${1:", count: 60))
        #expect(s.text == String(repeating: "${1:", count: 60))
    }

    @Test func hostileDepthIsLiteralNotAStackOverflow() {
        let n = 100_000
        let closed = String(repeating: "${1:", count: n) + String(repeating: "}", count: n)
        let s = CodeSnippet(parsing: closed)
        #expect(CodeSnippet.isValid(text: s.text, tabStops: s.tabStops))
        #expect(s.tabStops.count <= 66)
    }

    @Test func parsingNeverTrapsOnArbitraryBytes() {
        let alphabet = Array("$\\{}|,:/01aZ é")
        var seed: UInt64 = 0x9E3779B97F4A7C15
        for _ in 0..<2000 {
            var t = ""
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            var n = Int(seed >> 59)
            var r = seed
            while n > 0 { t.append(alphabet[Int(r >> 33) % alphabet.count]); r = r &* 2862933555777941757 &+ 3037000493; n -= 1 }
            let s = CodeSnippet(parsing: t)
            #expect(CodeSnippet.isValid(text: s.text, tabStops: s.tabStops))
            #expect(s.tabStops.contains { $0.index == 0 })
        }
    }

    // MARK: init(text:tabStops:)

    typealias S = CodeSnippet.TabStop

    @Test func acceptsNestedDisjointAndAdjacentRanges() {
        #expect(CodeSnippet.isValid(text: "abcdef", tabStops: []))
        #expect(CodeSnippet.isValid(text: "abcdef", tabStops: [S(index: 1, range: 0..<6), S(index: 2, range: 1..<3), S(index: 3, range: 3..<5)]))
        #expect(CodeSnippet.isValid(text: "abcdef", tabStops: [S(index: 1, range: 0..<3), S(index: 2, range: 3..<6)]))
        #expect(CodeSnippet.isValid(text: "abc", tabStops: [S(index: 1, range: 0..<3), S(index: 1, range: 0..<3), S(index: 0, range: 3..<3), S(index: 2, range: 0..<0)]))
        let s = CodeSnippet(text: "ab", tabStops: [S(index: 1, range: 0..<2)])
        #expect(s.text == "ab" && s.tabStops.count == 1)
    }

    @Test func rejectsPartialOverlap() {
        #expect(!CodeSnippet.isValid(text: "abcdef", tabStops: [S(index: 1, range: 0..<4), S(index: 2, range: 2..<6)]))
        // Order in the array does not matter.
        #expect(!CodeSnippet.isValid(text: "abcdef", tabStops: [S(index: 2, range: 2..<6), S(index: 1, range: 0..<4)]))
        // Overlap hidden behind a nesting.
        #expect(!CodeSnippet.isValid(text: "abcdefgh", tabStops: [S(index: 1, range: 0..<8), S(index: 2, range: 1..<4), S(index: 3, range: 3..<6)]))
    }

    @Test func rejectsRangesOutsideTheText() {
        #expect(!CodeSnippet.isValid(text: "abc", tabStops: [S(index: 1, range: 0..<4)]))
        #expect(!CodeSnippet.isValid(text: "abc", tabStops: [S(index: 1, range: -1..<2)]))
        #expect(!CodeSnippet.isValid(text: "", tabStops: [S(index: 1, range: 0..<1)]))
        #expect(!CodeSnippet.isValid(text: "abc", tabStops: [S(index: -1, range: 0..<1)]))
    }

    @Test func rejectsOffsetsInsideAScalar() {
        // "é" is two bytes: offset 1 is inside it.
        #expect(!CodeSnippet.isValid(text: "é", tabStops: [S(index: 1, range: 1..<2)]))
        #expect(!CodeSnippet.isValid(text: "é", tabStops: [S(index: 1, range: 0..<1)]))
        #expect(CodeSnippet.isValid(text: "é", tabStops: [S(index: 1, range: 0..<2)]))
    }

    // MARK: Hashable

    @Test func equalSnippetsHashEqualAndDifferencesShow() {
        let a = CodeSnippet(parsing: "${1:x} $0")
        let b = CodeSnippet(text: "x ", tabStops: [S(index: 1, range: 0..<1), S(index: 0, range: 2..<2)])
        #expect(a == b && a.hashValue == b.hashValue)
        #expect(Set([a, b]).count == 1)
        #expect(a != CodeSnippet(parsing: "${2:x} $0"))
        #expect(a != CodeSnippet(parsing: "${1:y} $0"))
        #expect(a != CodeSnippet(text: "x ", tabStops: [S(index: 1, range: 0..<1)]))
        #expect(S(index: 1, range: 0..<1) != S(index: 1, range: 0..<2))
    }
}
