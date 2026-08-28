import CoreText
import Foundation

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
}

/// Turns a string and a ``ResolvedFont`` into display lines.
public enum Shaper {
    /// Shapes `string` in `font`, wrapping at `width`.
    ///
    /// `width: nil` means "one line, no wrapping" — the max-content answer.
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

        var lines: [ShapedLine] = []

        // An empty string is one empty line, on both branches. Without this the
        // wrapping branch would return zero lines (its loop never runs) while
        // the unwrapped branch returned one, so an empty `Text` would measure a
        // line high unwrapped and nothing high wrapped. It also keeps
        // `CTTypesetterCreateWithAttributedString` off an empty string.
        if let width, attributed.length > 0 {
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start: CFIndex = 0
            while start < attributed.length {
                let count = CTTypesetterSuggestLineBreak(typesetter, start, width)

                // **A hard error, not a skipped iteration** (spec §3.4). A
                // zero-length break would leave `start` unmoved and the loop
                // would never terminate; a guard that merely `continue`d or
                // advanced by one would convert that hang into an infinite quiet
                // loop, or into silently invented break positions, one refactor
                // later.
                //
                // **Why it cannot fire, structurally, which is stronger than any
                // measurement:** `width` is preconditioned `> 0` nine lines
                // above, so the widths a zero-length break is rumoured to need —
                // 0 and negatives — are widths this call site can no longer
                // pass. A **NaN** width is excluded by the same guard rather
                // than by a second one, because `width > 0` is false for NaN;
                // that is IEEE-754's doing, not a deliberate clause, and it is
                // named here so a later rewrite to `!(width <= 0)` is visibly
                // not equivalent. And `start < attributed.length` holds by the
                // loop condition, which excludes the one argument CoreText is
                // known to answer 0 for: `start == length`.
                //
                // **Measured too, over the range that remains:** at every start
                // index of a mixed Latin/CJK/Arabic string and for eighteen
                // strings chosen to begin on a break-sensitive character
                // (leading newline, CRLF, U+2028, U+2029, ZWSP, NBSP, soft
                // hyphen, U+FFFC, a ZWJ emoji sequence, Thai and Devanagari
                // clusters), `CTTypesetterSuggestLineBreak` returns at least one
                // UTF-16 unit — never 0. The review reproduced this at 84,300
                // calls across ten fonts, fifty-two strings and fifteen widths.
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
                    \(width). Advancing by zero would not terminate.
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
        // unconditionally, and the wrapping branch is gated on
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
