import CoreText
import Foundation

extension Shaper {
    /// The x offset of every grapheme boundary of `string` in `font`, laid
    /// out as one unwrapped line (ruling TI-E): `string.count + 1` values, the
    /// first 0.
    ///
    /// The line is the one ``shape(_:font:wrappingAt:)`` builds — a
    /// `CTTypesetter` over the same attributed string, its line created over
    /// the **whole** range, so a string without a hard break gets exactly the
    /// line `measure` reads its width from, and the last offset is that width.
    /// (A hard break would end `shape`'s line there; here it does not, since
    /// a caret line is one line by definition.)
    ///
    /// Each boundary asks `CTLineGetOffsetForStringIndex` at its **UTF-16**
    /// offset — `CFIndex` counts UTF-16 units, and Swift's `Character` is the
    /// grapheme. The last boundary is **not** asked: it is the line's
    /// typographic width, `measure`'s `widestLine` for a string with no hard
    /// break. Asked, CoreText sums its way there in a different order and
    /// lands up to one ulp off (measured: a tab, a flag and a ZWJ family each
    /// read `…000004`/`…999996` where the width reads exact), and a caret at
    /// the end of a field must sit exactly where the field measured its text
    /// (`caretOffsetsAreOnePerGraphemeBoundaryFromZeroToTheMeasuredWidth`).
    public static func caretOffsets(_ string: String, font: ResolvedFont) -> [Double] {
        guard !string.isEmpty else { return [0] }
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font.ctFont])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let line = CTTypesetterCreateLine(typesetter, CFRange(location: 0, length: attributed.length))
        var offsets: [Double] = [0]
        offsets.reserveCapacity(string.count + 1)
        var unit = 0
        for character in string.dropLast() {
            unit += character.utf16.count
            offsets.append(Double(CTLineGetOffsetForStringIndex(line, unit, nil)))
        }
        offsets.append(CTLineGetTypographicBounds(line, nil, nil, nil))
        return offsets
    }
}
