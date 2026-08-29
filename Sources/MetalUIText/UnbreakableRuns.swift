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
    /// Every "widest" above is a **line's** advance as the typesetter produced
    /// it inside the paragraph, which is not the same number as shaping those
    /// characters on their own: the width-20 row's widest line is `"per"` at
    /// 19.894, while `"per"` shaped standalone measures **20.084** — 0.19 of
    /// kerning context, since in the paragraph that `r` is followed by a `c`.
    /// Worth knowing here of all places, because the min-content answer
    /// (`textMeasure`'s `.minContent` branch, in `MetalUI`) is built by shaping
    /// each of these runs **standalone**: min-content is therefore the width a
    /// run needs on a line of its own, which is exactly the question §4.5 asks,
    /// and it may differ in the second decimal from the same characters
    /// measured mid-paragraph.
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
    /// `CFStringTokenizer` with `kCFStringTokenizerUnitLineBreak`, the
    /// width-independent UAX #14 enumerator. The parent design spec's §6.4 said
    /// "CoreText exposes no width-independent line-break-opportunity API",
    /// which is literally true and materially misleading — the API is
    /// CoreFoundation's, not CoreText's — and §6.4 now carries the revision,
    /// with a nine-row table over the very line-break classes it enumerates.
    /// Measured here independently, `nil` locale and current locale identical
    /// on every sample:
    ///
    /// | string | runs |
    /// |---|---|
    /// | `"a bb supercalifragilistic dd"` | `a`, `bb`, `supercalifragilistic`, `dd` |
    /// | `"well-known thing"` | `well-`, `known`, `thing` |
    /// | `"hello\nworld"` | `hello`, `world` |
    /// | `"日本語"` | `日`, `本`, `語` |
    ///
    /// All four are UAX #14's answers rather than word boundaries'. Measured
    /// side by side, a word enumerator
    /// (`String.enumerateSubstrings(options: .byWords)`) answers
    /// `["well", "known", "thing"]` — it **splits at the hyphen and throws it
    /// away**, where a line breaker keeps it with the text it will sit beside —
    /// and `["日本", "語"]` for `"日本語"`, which is dictionary segmentation
    /// rather than the per-character break CSS wraps CJK at.
    ///
    /// **This sentence claimed the opposite for one commit** ("keeps
    /// `well-known` whole … CJK has no spaces to enumerate at all"), and the
    /// correction landed in `UnbreakableRunsTests` while this copy went on
    /// saying the wrong thing. Both numbers were **already written down** in the
    /// parent spec's §6.4 revision when it was written. The rule that earns:
    /// when you correct a claim, grep for its other copies — and for the copy
    /// that was right all along — before committing.
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
        // Counted only from the main thread; see `unbreakableRunCalls`.
        if Thread.isMainThread {
            MainActor.assumeIsolated { Self.unbreakableRunCalls += 1 }
        }
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

    /// Counts calls to ``unbreakableRuns(of:)`` **made on the main thread**.
    /// Internal and always on, at the cost of one branch and one increment: the
    /// function is the single largest line item in a frame, and a count is the
    /// only assertion that survives a change of machine. `ShapingCache`'s own
    /// `hits`/`misses` are the precedent.
    ///
    /// **Main-thread-only is what makes it safe, and it was a real data race
    /// before it was.** As a bare `nonisolated(unsafe) static var` this was
    /// written from every executor that ever tokenizes: every test that resets it
    /// and asserts a count is `@MainActor`, while `UnbreakableRunsTests` calls the
    /// function from ordinary nonisolated tests the runner may schedule
    /// concurrently. Two consequences, and only the first is a race in the
    /// sanitizer's sense — the second is what actually breaks a suite.
    /// Unsynchronised concurrent `+= 1` is undefined behaviour outright; and even
    /// with an atomic it would still be *wrong*, because a foreign increment
    /// landing inside a reset-and-assert window makes the count describe two
    /// callers instead of one. Reproduced deterministically in 3 of 3 runs by
    /// adding one slow nonisolated test that tokenizes in a loop:
    /// `aMinContentHitReStampsSoItSurvivesASweepingLoad`, which opens 512 such
    /// windows, fails with `(Shaper.unbreakableRunCalls -> 1) == 0`. The suite is
    /// green without that added test only because the real nonisolated callers
    /// (`UnbreakableRunsTests`, whose every case is one) run in microseconds.
    ///
    /// **So the fix is isolation rather than atomicity**, which is also the
    /// cheaper of the two: every frame this counter exists to measure runs on the
    /// main actor (`Frame.computeRootLayout` is `@MainActor`, and `Text`'s measure
    /// closure re-enters it through `MainActor.assumeIsolated`), so counting main-
    /// thread calls loses nothing a reader wants and makes every write and every
    /// read happen on one thread. `@MainActor` on the property is what enforces
    /// the read half at compile time; the `Thread.isMainThread` guard at the call
    /// site is what enforces the write half, and `assumeIsolated` under that guard
    /// is a check that cannot fail rather than an assumption. Measured: delete the
    /// guard and `theRunCounterIgnoresCallsMadeOffTheMainThread` does not merely
    /// fail, it takes the process down with signal 5 as `assumeIsolated` trips on
    /// a cooperative thread. A call from any other executor is simply not counted.
    @MainActor static var unbreakableRunCalls = 0

    @MainActor static func resetUnbreakableRunCalls() { unbreakableRunCalls = 0 }
}
