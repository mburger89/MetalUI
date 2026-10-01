import CoreText
import Foundation
import MetalUITextSystem

/// One display line: the `CTLine` CoreText produced for it, and how wide that
/// line measures.
///
/// **The parent spec already spends this name on a richer type, and this is not
/// it.** `2026-08-24-metalui-design.md` §6.5 specifies a `ShapedLine` that
/// caches a per-line **UTF-16 ↔ UTF-8 map** built at shape time — the seam that
/// keeps public byte offsets and CoreText's `CFIndex` from silently disagreeing
/// on the first non-ASCII line — and §6.6 gives it `runs`, `rows`,
/// `maxContentWidth` and the caret queries. None of that is here: M2 ships two
/// fields, and the map, the visual rows and the caret API arrive with the editor
/// at M6. Do not assume a `ShapedLine` in this repo can translate an offset.
///
/// **Deliberately not `Sendable`**, for the same reason ``ResolvedFont`` is not:
/// `CTLine` is a CoreFoundation class and carries no such guarantee. The plan's
/// draft declared both this and ``ShapedText`` `Sendable`; a `CTLine` cannot
/// honour that, and claiming it would be a lie the compiler happens not to
/// catch for a CF type. What crosses a concurrency boundary from this module is
/// ``FontKey`` and ``FontMetrics``, which are `Sendable` on their own.
public struct ShapedLine {
    /// CoreText's line, ready to be walked for runs and glyphs.
    public let line: CTLine

    /// The line's typographic width — `CTLineGetTypographicBounds`, which is
    /// the advance the text actually occupies, kerning included. This is the
    /// same metric ``FontResolver/resolve(family:size:)``'s ruling TX-C
    /// discussion quotes, so the two are comparable.
    public let advance: Double

    /// The UTF-16 range of the shaped string this line stands for — the
    /// range `CTLineGetStringRange` reports for a wrapped line, and for a line
    /// a limit truncated (ruling TE-T item 5) everything from its start to the
    /// string's end, which it stands for whatever part of it is drawn.
    public let sourceRange: Range<Int>

    /// `CTLineGetTrailingWhitespaceWidth`: the width of the whitespace that
    /// hangs past the line's end — what alignment leaves out of the line's
    /// width (ruling TE-J).
    public let trailingWhitespace: Double

    init(line: CTLine, advance: Double, sourceRange: Range<Int>? = nil) {
        self.line = line
        self.advance = advance
        let range = CTLineGetStringRange(line)
        self.sourceRange = sourceRange ?? range.location..<(range.location + range.length)
        trailingWhitespace = CTLineGetTrailingWhitespaceWidth(line)
    }

    // **The memberwise initialiser is internal on purpose, and the decision is
    // taken here rather than left to the first task that trips over it.** Both
    // fields are `public` so a consumer can walk a line's runs and place it —
    // in the event, ``ShapedText/placedGlyphs(at:font:scaleFactor:)`` one file
    // over, rather than `MetalUIRender` as first expected — but no module
    // outside `MetalUIText` can synthesise one: a
    // `ShapedLine` whose `advance` disagrees with its `line` is a lie the type
    // exists to prevent, and only ``Shaper`` can make the two agree. A renderer
    // test that needs one calls ``Shaper/shape(_:font:wrappingAt:)``, which is
    // cheap and needs no fixture. Promote it to `public` only alongside a reason
    // that a caller must be able to state a width the `CTLine` does not measure.
}

/// A string laid out into display lines at some offered width.
public struct ShapedText {
    /// The display lines, in order.
    public let lines: [ShapedLine]

    /// The widest line's ``ShapedLine/advance`` — the content width this text
    /// needs at the width it was wrapped to.
    public let widestLine: Double

    /// `lines.count × lineHeight`, where `lineHeight` is
    /// `ceil(ascent + descent + leading)` — see ``FontMetrics/lineHeight``.
    ///
    /// Uniform per spec §3.4, because a `Text` carries one font at one size
    /// (§2). Rich text makes line height per-line, and is out of M2.
    public let totalHeight: Double

    /// Each line's x offset inside the text's box, in points (ruling TE-J):
    /// `(box − (advance − trailingWhitespace)) × factor`, 0 for every line
    /// under leading alignment — so the spelling without options places
    /// exactly as it always did.
    public let lineOffsets: [Double]

    init(lines: [ShapedLine], widestLine: Double, totalHeight: Double, lineOffsets: [Double]? = nil) {
        self.lines = lines
        self.widestLine = widestLine
        self.totalHeight = totalHeight
        self.lineOffsets = lineOffsets ?? [Double](repeating: 0, count: lines.count)
    }
}

/// Turns a string and a ``ResolvedFont`` into display lines.
public enum Shaper {
    /// `shape(_:font:wrappingAt:)` under a line limit, truncation and
    /// alignment (ruling TE-C item 3).
    ///
    /// With more lines than `options.maxLines` (below 1 acts as 1): at a `nil`
    /// width the first lines are kept and the rest cut (L4); at a width the
    /// lines before the last kept one stand and the last is built from the
    /// rest by ``truncatedLine(_:from:wraps:font:width:mode:)`` (rulings TE-C
    /// item 3, TE-T). Each line's alignment offset is `(box − (advance −
    /// trailing whitespace)) × factor`, `box` the width or, unwrapped, the
    /// widest line (TE-J, measured on A5: a wrapped line centres without the
    /// whitespace it ends in).
    public static func shape(_ string: String, font: ResolvedFont, wrappingAt width: Double?,
                             options: TextLayoutOptions) -> ShapedText {
        let full = shape(string, font: font, wrappingAt: width)
        var lines = full.lines
        if let maxLines = options.maxLines.map({ max(1, $0) }), lines.count > maxLines {
            if let width {
                let last = lines[maxLines - 1].sourceRange
                lines = Array(lines.prefix(maxLines - 1))
                    + [truncatedLine(string, from: last.lowerBound, wraps: !endsParagraph(string, last),
                                     font: font, width: width, mode: options.truncation)]
            } else {
                lines = Array(lines.prefix(maxLines))
            }
        }
        let widest = lines.map(\.advance).max() ?? 0
        let factor: Double = switch options.alignment {
        case .leading: 0
        case .center: 0.5
        case .trailing: 1
        }
        let box = width ?? widest
        return ShapedText(lines: lines, widestLine: widest,
                          totalHeight: Double(lines.count) * font.metrics.lineHeight,
                          lineOffsets: lines.map { factor == 0 ? 0 : alignmentOffset(box - ($0.advance - $0.trailingWhitespace), factor) })
    }

    /// `slack × factor`, rounded to 1/256 pt (ruling TE-U). Rounded because
    /// the two text systems measure a line's width to within ~1e-13 pt, not
    /// bit for bit, and an offset that differs in its last bit can move a pen
    /// across a subpixel-variant boundary; on a 1/256 pt grid both systems
    /// compute the same offset, and the pen arithmetic after it is the
    /// unaligned pen's. The portable path's `PortableText.alignmentOffset` is
    /// this function.
    public static func alignmentOffset(_ slack: Double, _ factor: Double) -> Double {
        (slack * factor * 256).rounded() / 256
    }

    /// Whether `line` (a range of `string`'s UTF-16 units) ends its paragraph:
    /// its last unit is a hard break, or it reaches the string's end.
    static func endsParagraph(_ string: String, _ line: Range<Int>) -> Bool {
        let units = string.utf16
        guard line.upperBound < units.count, let last = line.last else { return true }
        return hardBreaks.contains(units[units.index(units.startIndex, offsetBy: last)])
    }

    /// UAX #14's hard-break characters (BK, CR, LF, NL) — the separators this
    /// type's own doc lists as CoreText's.
    static let hardBreaks: Set<UInt16> = [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029]

    /// The last line a limit keeps (ruling TE-T), from UTF-16 unit `start` of
    /// `string`: built from the rest's first paragraph `P` (to the first hard
    /// break, excluded, or the end), in a line of `P` alone.
    ///
    /// - The `…` token (U+2026, in `font`, CoreText's own fallback when the
    ///   face lacks it) wider than `width`: the longest prefix of whole
    ///   clusters that fits, at least one — `CTTypesetterSuggestClusterBreak`.
    /// - `P` wraps (`wraps`): `CTLineCreateTruncatedLine` of `P` in `mode`.
    /// - `P` fits, so text follows it: in tail mode a non-empty `P` takes the
    ///   token anyway — `CTLineCreateTruncatedLine` of `P` followed by one
    ///   glyph far wider than any width, so CoreText's own tail rule chooses
    ///   the kept prefix; an empty `P`, and `P` in head and middle mode, is
    ///   drawn whole (no token).
    static func truncatedLine(_ string: String, from start: Int, wraps: Bool, font: ResolvedFont,
                              width: Double, mode: TextTruncation) -> ShapedLine {
        let source = string as NSString
        var end = start
        while end < source.length, !hardBreaks.contains(source.character(at: end)) { end += 1 }
        let paragraph = source.substring(with: NSRange(location: start, length: end - start))
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let attributed = NSAttributedString(string: paragraph, attributes: [fontKey: font.ctFont])
        let whole = CTLineCreateWithAttributedString(attributed)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}",
                                                                        attributes: [fontKey: font.ctFont]))
        let range = start..<source.length
        func shaped(_ line: CTLine) -> ShapedLine {
            ShapedLine(line: line, advance: CTLineGetTypographicBounds(line, nil, nil, nil), sourceRange: range)
        }
        let type: CTLineTruncationType = switch mode {
        case .tail: .end
        case .head: .start
        case .middle: .middle
        }
        if CTLineGetTypographicBounds(token, nil, nil, nil) > width {
            guard attributed.length > 0 else { return shaped(whole) }
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let count = max(1, CTTypesetterSuggestClusterBreak(typesetter, 0, width))
            return shaped(CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: count)))
        }
        if wraps {
            return shaped(CTLineCreateTruncatedLine(whole, width, type, token) ?? whole)
        }
        // An EMPTY `P` takes no token in any mode, even with text after it
        // (TE-T item 3, probe E5: SwiftUI draws "A" alone for "A\n\nB" at
        // lineLimit(2), nothing for "\nB\nC" at lineLimit(1)).
        guard mode == .tail, attributed.length > 0 else { return shaped(whole) }
        // One glyph wider than any width follows `P`, in a run of its own (so
        // it kerns with nothing), and is never kept.
        let forced = NSMutableAttributedString(attributedString: attributed)
        forced.append(NSAttributedString(string: "M", attributes: [
            fontKey: CTFontCreateCopyWithAttributes(font.ctFont, 1e6, nil, nil)]))
        let overflowing = CTLineCreateWithAttributedString(forced)
        return shaped(CTLineCreateTruncatedLine(overflowing, width, .end, token) ?? whole)
    }

    /// Shapes `string` in `font`, wrapping at `width`.
    ///
    /// `width: nil` means "no soft wrapping" — the max-content answer: **one
    /// line per hard line break, never one line for the whole string.**
    ///
    /// ## `nil` is the same loop at an infinite width
    ///
    /// **This used to build one `CTLine` for the whole string with
    /// `CTLineCreateWithAttributedString`, and that was a defect the doc here
    /// called intended.** A whole-string line lays every hard break's segments
    /// side by side, while `CTTypesetterSuggestLineBreak` always breaks after
    /// one — so `.maxContent` reported the **sum** of the segments where every
    /// definite width reported the widest: `"Ready\nSet\nGo"` at 13pt measured
    /// 75.004 unwrapped and 37.565 wrapped, one line against three. The
    /// separators are CoreText's, measured: U+000A, U+000D, CR LF, U+2028,
    /// U+2029, U+0085, U+000B and U+000C.
    ///
    /// **Why `.infinity` and not "a large width".** For a break-free string the
    /// typesetter's one line at `.infinity` is byte-identical to the whole-string
    /// line — glyphs, positions, advances, string indices, run status and
    /// typographic bounds, over bidi, CJK, clusters and a 136,000-unit string
    /// (`anUnwrappedBreakFreeStringIsTheLineCoreTextBuildsWhole`). A finite
    /// stand-in is not: that same string soft-breaks at width `1e4` and at `1e5`.
    ///
    /// **A trailing break opens no empty last line** — `"Ready\n"` is one line
    /// with the separator inside it. That is the typesetter's answer, and the
    /// wrapping branch has always given it.
    ///
    /// ## Why this re-typesets per display line
    ///
    /// `CTTypesetterSuggestLineBreak` + `CTTypesetterCreateLine`, once per
    /// display line, is the branch that is **always** correct. The design spec's
    /// §6.3 fast path — shape the logical line once, then re-wrap arithmetically
    /// from cached advances — is not an available shortcut here, and §6.3
    /// measured why: for a base-RTL paragraph the per-display-line run origins
    /// (`-3.6 / 0.0 / 20.2 / 23.8 / 48.2`) are not reproducible from the
    /// whole-line advances at all, because UAX #9 L1 resets trailing-whitespace
    /// levels *per display line*. So the fast path needs a bidi gate, and this
    /// is what the gate falls back to. It is M6's optimisation over a working
    /// implementation, not a faster way to write this function.
    ///
    /// §6.4's hand-rolled UAX #14 subset is out for the same reason. §6.4's
    /// complaint — "CoreText exposes no width-independent line-break API" — is a
    /// complaint about the *fast path*: a width-taking API is precisely the
    /// right shape for "wrap at this width".
    ///
    /// ## The width must be positive
    ///
    /// Spec §3.4 requires callers to offer a **small positive** width rather
    /// than zero, and requires the violation to be loud. It is a
    /// ``Swift/precondition`` here rather than a clamp because a clamp would
    /// silently answer a different question than the one asked, and the caller
    /// that needs this is the min-content branch of Task 4's measure function —
    /// the one place where "narrowest possible" is a real request and `0` is the
    /// obvious wrong spelling of it. **A `.definite(0)` offered extent reaches
    /// the same precondition**, which is deliberate: that is a real case for a
    /// `Text` in a zero-width box, and the measure function owes it the same
    /// small positive width, not a zero passed through.
    public static func shape(_ string: String, font: ResolvedFont,
                             wrappingAt width: Double?) -> ShapedText {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont]
        )

        // Checked before the empty-string branch below, so that the contract is
        // "an offered width is positive", not "an offered width is positive when
        // it happens to be used".
        if let width {
            precondition(width > 0, """
                Shaper.shape was offered a wrapping width of \(width). \
                CTTypesetterSuggestLineBreak takes a width by construction, and a \
                non-positive one is not a narrower line — it is an ill-formed \
                request. Spec §3.4: min-content typesets at a SMALL POSITIVE \
                width, never at 0.
                """)
        }

        // No width is an infinite one: the loop below then breaks at hard line
        // breaks only. See "`nil` is the same loop at an infinite width" above.
        let lineWidth = width ?? .infinity

        var lines: [ShapedLine] = []

        // An empty string is one empty line, whether or not a width was offered.
        // Without this the loop never runs and returns zero lines, so an empty
        // `Text` would measure nothing high — and before hard breaks moved the
        // unwrapped case onto the loop, it measured a line high unwrapped and
        // nothing high wrapped. It also keeps
        // `CTTypesetterCreateWithAttributedString` off an empty string.
        if attributed.length > 0 {
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start: CFIndex = 0
            while start < attributed.length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, lineWidth)

                // **A hard error, not a skipped iteration** (spec §3.4). A
                // zero-length break would leave `start` unmoved and the loop
                // would never terminate; a guard that merely `continue`d or
                // advanced by one would convert that hang into an infinite quiet
                // loop, or into silently invented break positions, one refactor
                // later.
                //
                // **Why it cannot fire, structurally, which is stronger than any
                // measurement:** an offered `width` is preconditioned `> 0`
                // above, and a `nil` one becomes `+infinity`, so the widths a
                // zero-length break is rumoured to need — 0 and negatives — are
                // widths this call site can no longer pass. A **NaN** width is
                // excluded by the same guard rather than by a second one,
                // because `width > 0` is false for NaN; that is IEEE-754's
                // doing, not a deliberate clause, and it is named here so a
                // later rewrite to `!(width <= 0)` is visibly not equivalent.
                // And `start < attributed.length` holds by the loop condition,
                // which excludes the one argument CoreText is known to answer 0
                // for: `start == length`.
                //
                // **Measured too, over the range that remains:** at every start
                // index of a mixed Latin/CJK/Arabic string and for eighteen
                // strings chosen to begin on a break-sensitive character
                // (leading newline, CRLF, U+2028, U+2029, ZWSP, NBSP, soft
                // hyphen, U+FFFC, a ZWJ emoji sequence, Thai and Devanagari
                // clusters), `CTTypesetterSuggestLineBreak` returns at least one
                // UTF-16 unit — never 0. The review reproduced this at 84,300
                // calls across ten fonts, fifty-two strings and fifteen widths,
                // `+infinity` among them — the width a `nil` request now passes.
                //
                // So this is a **contract assertion, not a live guard**, and it
                // earns its place precisely because Apple documents no minimum
                // return: the invariant the loop's termination rests on is
                // CoreText's, not ours. Deleting it therefore reddens nothing —
                // by unreachability, not by a coverage gap, and no future test
                // can change that without first removing the `width > 0`
                // precondition above.
                precondition(count > 0, """
                    CTTypesetterSuggestLineBreak returned a zero-length break at \
                    UTF-16 index \(start) of \(attributed.length) for width \
                    \(lineWidth). Advancing by zero would not terminate.
                    """)

                let line = CTTypesetterCreateLine(
                    typesetter, CFRange(location: start, length: count))
                lines.append(ShapedLine(
                    line: line,
                    advance: CTLineGetTypographicBounds(line, nil, nil, nil)))
                start += count
            }
        } else {
            let line = CTLineCreateWithAttributedString(attributed)
            lines.append(ShapedLine(
                line: line,
                advance: CTLineGetTypographicBounds(line, nil, nil, nil)))
        }

        // `lines` is non-empty on both branches — the `else` appends
        // unconditionally, and the loop branch is gated on
        // `attributed.length > 0` with every iteration advancing `start` by a
        // positive `count`, so its loop runs at least once. `max()` returns an
        // Optional regardless, so the `?? 0` below spells that invariant rather
        // than handling a case: **no input reaches it**, and nothing would
        // notice if it fired, which is why it is stated here instead of left to
        // read as a fallback.
        return ShapedText(
            lines: lines,
            widestLine: lines.map(\.advance).max() ?? 0,
            totalHeight: Double(lines.count) * font.metrics.lineHeight
        )
    }
}
