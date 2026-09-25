extension PortableText {
    /// `text` split after every UAX #14 break opportunity, trailing whitespace
    /// trimmed from each piece and empty pieces dropped — the runs a line
    /// breaker may not break inside. The portable counterpart of
    /// `Shaper.unbreakableRuns(of:)` (TX-F; deleted from `MetalUIText` at stage
    /// 9, `LR-FD`, and kept as `ContentSizeOracleTests`' reference), with
    /// libunibreak's opportunities (``lineBreaks(in:)``) where that uses
    /// `CFStringTokenizer`'s.
    ///
    /// An empty string yields no runs.
    public static func unbreakableRuns(of text: String) -> [String] {
        let units = Array(text.utf16)
        var runs: [String] = []
        var start = 0
        for (index, opportunity) in lineBreaks(in: text).enumerated() where opportunity != .none {
            var run = Substring(String(decoding: units[start...index], as: UTF16.self))
            while let last = run.last, last.isWhitespace { run = run.dropLast() }
            if !run.isEmpty { runs.append(String(run)) }
            start = index + 1
        }
        return runs
    }

    /// CSS's min-content width: the widest unbreakable run, each shaped on a
    /// line of its own (TX-F) — what `ShapingCache.minContentWidth(_:font:)`
    /// answered on Apple platforms until stage 9 (`LR-FD`). Library API; no
    /// framework path calls it since.
    public static func minContentWidth(_ text: String, font: PortableFont) throws -> Double {
        try unbreakableRuns(of: text).reduce(0) { widest, run in
            max(widest, try maxContentWidth(run, font: font))
        }
    }

    /// CSS's max-content width: the widest line when nothing wraps, one line
    /// per hard break (TX-K) — `Shaper.shape(_:font:wrappingAt: nil).widestLine`.
    public static func maxContentWidth(_ text: String, font: PortableFont) throws -> Double {
        try lines(text, font: font, wrappingAt: nil).reduce(0) { max($0, $1.advance) }
    }
}
