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
        // One more than needed when empty, so the pointer is never nil (a zero-capacity buffer has no base address).
        let base = UnsafeMutablePointer<UInt16>.allocate(capacity: max(units.count, 1))
        storage = UnsafeMutableBufferPointer(start: base, count: max(units.count, 1))
        _ = storage.initialize(from: units)
        var sequence = SBCodepointSequence(stringEncoding: SBStringEncoding(SBStringEncodingUTF16),
                                           stringBuffer: UnsafeRawPointer(base),
                                           stringLength: SBUInteger(units.count))
        algorithm = SBAlgorithmCreate(&sequence)
        var paragraphs: [(range: Range<Int>, paragraph: SBParagraphRef)] = []
        var levels = [UInt8](repeating: 0, count: units.count)
        var offset = 0
        while offset < units.count {
            // SheenBidi answers NULL only when it cannot allocate (the range is inside the text).
            guard let paragraph = SBAlgorithmCreateParagraph(algorithm, SBUInteger(offset),
                                                             SBUInteger(units.count - offset),
                                                             SBLevel(SBLevelDefaultLTR)),
                  let paragraphLevels = SBParagraphGetLevelsPtr(paragraph) else {
                preconditionFailure("SheenBidi could not resolve a paragraph's levels (out of memory)")
            }
            let length = Int(SBParagraphGetLength(paragraph))
            for unit in 0..<length { levels[offset + unit] = UInt8(paragraphLevels[unit]) }
            paragraphs.append((offset..<offset + length, paragraph))
            offset += max(length, 1)
        }
        self.paragraphs = paragraphs
        self.levels = levels

        var scripts = [UInt8](repeating: 0, count: units.count)
        guard let locator = SBScriptLocatorCreate() else { preconditionFailure("SheenBidi could not allocate a script locator") }
        SBScriptLocatorLoadCodepoints(locator, &sequence)
        while SBScriptLocatorMoveNext(locator) != 0 {
            // `MoveNext` answered true, so the locator has a current run.
            guard let agentPointer = SBScriptLocatorGetAgent(locator) else { break }
            let agent = agentPointer.pointee
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
              let holder = paragraphs.first(where: { $0.range.contains(range.lowerBound) }) else { return [] }
        let paragraph = holder.paragraph
        let length = min(range.upperBound, holder.range.upperBound) - range.lowerBound
        // NULL when SheenBidi cannot allocate the line: no runs, nothing drawn, rather than a trap.
        guard let line = SBParagraphCreateLine(paragraph, SBUInteger(range.lowerBound), SBUInteger(length)) else { return [] }
        defer { SBLineRelease(line) }
        guard let runs = SBLineGetRunsPtr(line) else { return [] }
        return (0..<Int(SBLineGetRunCount(line))).map {
            let run = runs[$0]
            return (Int(run.offset)..<Int(run.offset + run.length), UInt8(run.level))
        }
    }
}
