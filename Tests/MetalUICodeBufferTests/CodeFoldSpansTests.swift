import Testing
@testable import MetalUICodeBuffer

/// `FoldSpans`, the outermost spans a view lays out and motion steps over (`CV-BM`).
@MainActor
struct CodeFoldSpansTests {
    private func spans(_ ranges: [Range<Int>]) -> FoldSpans {
        let buffer = CodeBuffer((0..<40).map { "l\($0)" }.joined(separator: "\n"))
        let state = CodeFoldState(selectionState: buffer.selectionState, folded: ranges)
        return withExtendedLifetime(buffer) { state.spans }
    }

    /// The hidden lines by brute force: the union of `lowerBound+1 ..< upperBound`.
    private func hidden(_ ranges: [Range<Int>], lines: Int) -> Set<Int> {
        var out = Set<Int>()
        for r in ranges { for l in (r.lowerBound + 1)..<r.upperBound where l < lines { out.insert(l) } }
        return out
    }

    /// Nested, overlapping and adjacent folds are the union of their hidden rows, and the shown index and its inverse
    /// are a bijection over the shown lines. **Mutation:** a merge that ends the span at the later range's end
    /// instead of the larger of the two (the nested `4..<6` shrinks `2..<8`); a prefix sum that counts the header.
    @Test func shownIndexAndItsInverseMatchABruteForceOverTheUnionOfHiddenRows() {
        let cases: [[Range<Int>]] = [[], [2..<8], [2..<8, 4..<6], [2..<8, 5..<12], [2..<5, 5..<9], [2..<8, 2..<4],
                                     [0..<40], [30..<40, 3..<5, 10..<14]]
        for ranges in cases {
            let model = hidden(ranges.sorted { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }, lines: 40)
            let s = spans(ranges)
            let shown = (0..<40).filter { !model.contains($0) }
            #expect(s.shownCount(lineCount: 40) == shown.count, "\(ranges)")
            for (index, line) in shown.enumerated() {
                #expect(s.shownIndex(of: line) == index && s.line(atShownIndex: index) == line, "\(ranges) line \(line)")
            }
            for line in 0..<40 { #expect(s.hides(line) == model.contains(line), "\(ranges) hides \(line)") }
        }
    }

    /// A hidden line counts as its header; stepping skips the hidden rows and ends at `nil`. **Mutation:** a step
    /// counted in lines (`line + step`) lands in the hidden rows.
    @Test func steppingSkipsHiddenRowsAndEndsAtTheDocument() {
        let s = spans([2..<8, 4..<6])
        #expect(s.shownLine(5) == 2 && s.shownLine(8) == 8 && s.shownLine(2) == 2)
        #expect(s.shownLine(from: 2, by: 1, lineCount: 40) == 8)
        #expect(s.shownLine(from: 8, by: -1, lineCount: 40) == 2)
        #expect(s.shownLine(from: 0, by: -1, lineCount: 40) == nil)
        #expect(s.shownLine(from: 39, by: 1, lineCount: 40) == nil)
        #expect(s.shownLine(from: 1, by: 3, lineCount: 40) == 9)
        #expect(s.folds == [2..<8] && s.spanIndex(headedBy: 2) == 0 && s.spanIndex(headedBy: 3) == nil)
    }
}
