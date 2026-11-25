import Testing
@testable import MetalUIPortableText

// Record 410 (lint pass): `BidiParagraph` wraps SheenBidi, whose `SBAlgorithmCreate` answers NULL for
// an empty code-point sequence (`SBCodepointSequenceIsValid` needs `stringLength > 0`). The wrapper
// stored that NULL as a non-optional reference, so an empty paragraph trapped at the first use.
@Suite struct BidiEdgeInputTests {
    @Test func anEmptyTextResolvesToNoLevelsAndNoScripts() {
        let bidi = BidiParagraph([])
        #expect(bidi.levels.isEmpty)
        #expect(bidi.scripts.isEmpty)
        #expect(!bidi.isMixed)
        #expect(!bidi.isRightToLeftParagraph(at: 0))
    }

    @Test func anEmptyTextHasNoVisualRuns() {
        let bidi = BidiParagraph([])
        #expect(bidi.visualRuns(0..<0).isEmpty)
        #expect(bidi.visualRuns(0..<3).isEmpty)
    }

    @Test func aLoneCombiningMarkIsOneLeftToRightRun() {
        let bidi = BidiParagraph([0x0301])   // COMBINING ACUTE ACCENT
        #expect(bidi.levels == [0])
        let runs = bidi.visualRuns(0..<1)
        #expect(runs.count == 1)
        #expect(runs.first?.range == 0..<1)
    }

    @Test func anEmptyOrOutOfRangeRunHasNoVisualRuns() {
        let bidi = BidiParagraph(Array("abc".utf16))
        #expect(bidi.visualRuns(1..<1).isEmpty)
        #expect(bidi.visualRuns(3..<5).isEmpty)
        #expect(bidi.visualRuns(7..<9).isEmpty)
    }

    @Test func aRunPastTheParagraphIsCutAtItsSeparator() {
        let bidi = BidiParagraph(Array("ab\ncd".utf16))
        let runs = bidi.visualRuns(0..<5)
        #expect(runs.map(\.range) == [0..<3])
    }
}
