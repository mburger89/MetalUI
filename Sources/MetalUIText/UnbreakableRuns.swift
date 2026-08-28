import CoreText
import Foundation

extension Shaper {
    /// `string` split at every UAX #14 soft-wrap opportunity, with trailing
    /// whitespace removed from each piece — the runs a line breaker may **not**
    /// break inside.
    ///
    /// The widest of these, shaped, is CSS's min-content width for a piece of
    /// text, which is what §4.5's automatic minimum floors a text item at.
    ///
    /// ## Why min-content is not `shape(_:font:wrappingAt: someTinyWidth)`
    ///
    /// Spec §3.4 defines min-content as "typeset at a **small positive** width;
    /// the **widest** resulting line — the longest unbreakable run", and the two
    /// halves of that sentence are not the same thing on this platform.
    /// **`CTTypesetterSuggestLineBreak` breaks inside a word once the word
    /// cannot fit**, so a tiny width does not answer "what is the longest run
    /// that cannot be broken" — it answers "how wide is the widest single
    /// character".
    ///
    /// Measured, system font at 13pt, `"a bb supercalifragilistic dd"`:
    ///
    /// | offered width | lines | widest |
    /// |---|---|---|
    /// | 0.001, 0.5, 1, 5 | 25, one character each | **11.489** |
    /// | 10 | 20 (`"li"`, `"fr"`, `"ili"`, …) | 11.489 |
    /// | 20 | 10 (`"su"`, `"per"`, `"cal"`, …) | 19.894 |
    /// | 120 | 3 (`"a bb "`, `"supercalifragilistic "`, `"dd"`) | 113.928 |
    ///
    /// The longest word alone measures **110.348**. So the tiny-width spelling
    /// of min-content is off by a factor of ten here, and it is off in the
    /// direction that matters: §4.5's automatic minimum would floor a text item
    /// at one character, letting a `Row` squeeze a long label until CoreText
    /// broke it mid-word. That is the failure §3.4 names as "indistinguishable
    /// from a bug" — reached by the other road than the single-line
    /// implementation it warns about.
    ///
    /// **`CTParagraphStyle`'s `byWordWrapping` does not change it** — measured
    /// too, since it is the obvious first fix: attaching
    /// `kCTLineBreakByWordWrapping` to the attributed string produces the
    /// identical 25 single-character lines at width 0.5. The character break is
    /// the typesetter's fallback for "no break opportunity fits", not a
    /// paragraph-style choice, and there is no width at which the typesetter can
    /// be asked for break opportunities alone.
    ///
    /// ## What this uses instead
    ///
    /// `CFStringTokenizer` with `kCFStringTokenizerUnitLineBreak`, which is the
    /// width-independent UAX #14 enumerator the design spec's §6.4 says CoreText
    /// does not expose — it is CoreFoundation's, not CoreText's, which is why
    /// §6.4's complaint stands and this is still available. Measured on the same
    /// machine, `nil` locale and current locale identical on every sample:
    ///
    /// | string | runs |
    /// |---|---|
    /// | `"a bb supercalifragilistic dd"` | `a`, `bb`, `supercalifragilistic`, `dd` |
    /// | `"well-known thing"` | `well-`, `known`, `thing` |
    /// | `"hello\nworld"` | `hello`, `world` |
    /// | `"日本語"` | `日`, `本`, `語` |
    ///
    /// All four are UAX #14's answers rather than word boundaries': a word
    /// enumerator (`String.enumerateSubstrings(options: .byWords)`, measured for
    /// comparison) keeps `well-known` whole and drops the hyphen, and CJK has no
    /// spaces to enumerate at all.
    ///
    /// The locale is deliberately `nil`. A locale would make this answer depend
    /// on the machine's region for the scripts that break by dictionary (Thai),
    /// which is a layout that changes when the user's language does — a property
    /// no test in this repo could hold still.
    ///
    /// **Trailing whitespace is trimmed from each run**, which is CSS's rule
    /// (trailing spaces hang at a soft wrap) and is also what "unbreakable run"
    /// means: a space is a place the line *may* break, so it is not part of the
    /// run before it. Measured cost of getting this wrong: min-content for the
    /// string above becomes 113.928 rather than 110.348 — a floor carrying a
    /// space nobody sees.
    ///
    /// An empty string yields **no runs**, so a caller's `max` must start at 0
    /// rather than at the first run.
    public static func unbreakableRuns(of string: String) -> [String] {
        let cf = string as CFString
        let length = CFStringGetLength(cf)
        guard length > 0,
              let tokenizer = CFStringTokenizerCreate(
                kCFAllocatorDefault, cf, CFRangeMake(0, length),
                kCFStringTokenizerUnitLineBreak, nil)
        else { return [] }

        let utf16 = Array(string.utf16)
        var runs: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            var run = Substring(String(
                decoding: utf16[range.location ..< range.location + range.length],
                as: UTF16.self))
            while let last = run.last, last.isWhitespace { run = run.dropLast() }
            if !run.isEmpty { runs.append(String(run)) }
        }
        return runs
    }
}
