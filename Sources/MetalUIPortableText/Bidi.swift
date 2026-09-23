import CSheenBidi

/// A text's Unicode Bidirectional Algorithm (UAX #9) and script runs, through
/// SheenBidi (ruling BD-A). The text is split into UAX #9 paragraphs at each
/// paragraph separator (a newline, U+2029, …); each paragraph's direction is
/// found from its first strong character, left to right when there is none —
/// CoreText's "natural" writing direction.
final class BidiParagraph {
    /// The paragraph's text, owned here: SheenBidi reads it in place.
    private let storage: UnsafeMutableBufferPointer<UInt16>
    private let algorithm: SBAlgorithmRef
    /// The paragraphs, in order, covering the text.
    private let paragraphs: [(range: Range<Int>, paragraph: SBParagraphRef)]
    /// Each UTF-16 unit's resolved embedding level; odd is right to left.
    let levels: [UInt8]
    /// Each UTF-16 unit's script (SheenBidi's `SBScript`), common and
    /// inherited characters resolved to their neighbours'.
    let scripts: [UInt8]

    init(_ units: [UInt16]) {
        storage = UnsafeMutableBufferPointer<UInt16>.allocate(capacity: max(units.count, 1))
        _ = storage.initialize(from: units)
        var sequence = SBCodepointSequence(stringEncoding: SBStringEncoding(SBStringEncodingUTF16),
                                           stringBuffer: UnsafeRawPointer(storage.baseAddress!),
                                           stringLength: SBUInteger(units.count))
        algorithm = SBAlgorithmCreate(&sequence)
        var paragraphs: [(range: Range<Int>, paragraph: SBParagraphRef)] = []
        var levels = [UInt8](repeating: 0, count: units.count)
        var offset = 0
        while offset < units.count {
            let paragraph = SBAlgorithmCreateParagraph(algorithm, SBUInteger(offset),
                                                       SBUInteger(units.count - offset),
                                                       SBLevel(SBLevelDefaultLTR))!
            let length = Int(SBParagraphGetLength(paragraph))
            let paragraphLevels = SBParagraphGetLevelsPtr(paragraph)!
            for unit in 0..<length { levels[offset + unit] = UInt8(paragraphLevels[unit]) }
            paragraphs.append((offset..<offset + length, paragraph))
            offset += max(length, 1)
        }
        self.paragraphs = paragraphs
        self.levels = levels

        var scripts = [UInt8](repeating: 0, count: units.count)
        let locator = SBScriptLocatorCreate()!
        SBScriptLocatorLoadCodepoints(locator, &sequence)
        while SBScriptLocatorMoveNext(locator) != 0 {
            let agent = SBScriptLocatorGetAgent(locator)!.pointee
            for unit in Int(agent.offset)..<Int(agent.offset + agent.length) { scripts[unit] = UInt8(agent.script) }
        }
        SBScriptLocatorRelease(locator)
        self.scripts = scripts
    }

    deinit {
        for (_, paragraph) in paragraphs { SBParagraphRelease(paragraph) }
        SBAlgorithmRelease(algorithm)
        storage.deallocate()
    }

    /// Whether the paragraph holding `unit` runs right to left.
    func isRightToLeftParagraph(at unit: Int) -> Bool {
        guard let paragraph = paragraphs.first(where: { $0.range.contains(unit) })?.paragraph else { return false }
        return SBParagraphGetBaseLevel(paragraph) % 2 == 1
    }

    /// Whether anything in the paragraph is right to left.
    var isMixed: Bool { levels.contains { $0 != 0 } }

    /// The runs of `range` — one line, which never crosses a paragraph
    /// separator — in visual order, left to right, each with its level, after
    /// UAX #9's L1 (trailing whitespace to the paragraph level) and L2
    /// (reversal).
    func visualRuns(_ range: Range<Int>) -> [(range: Range<Int>, level: UInt8)] {
        guard !range.isEmpty,
              let paragraph = paragraphs.first(where: { $0.range.contains(range.lowerBound) })?.paragraph else { return [] }
        let paragraphEnd = paragraphs.first(where: { $0.range.contains(range.lowerBound) })!.range.upperBound
        let length = min(range.upperBound, paragraphEnd) - range.lowerBound
        let line = SBParagraphCreateLine(paragraph, SBUInteger(range.lowerBound), SBUInteger(length))!
        defer { SBLineRelease(line) }
        let runs = SBLineGetRunsPtr(line)!
        return (0..<Int(SBLineGetRunCount(line))).map {
            let run = runs[$0]
            return (Int(run.offset)..<Int(run.offset + run.length), UInt8(run.level))
        }
    }
}
