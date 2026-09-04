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
        // Counted only for a caller that bound a counter; see `runCallCounter`.
        Self.runCallCounter?.bump()
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

    /// Counts calls to ``unbreakableRuns(of:)`` **made while the calling task
    /// has a ``RunCallCounter`` bound to** ``runCallCounter``. Internal and
    /// always on, at the cost of one optional check: the function is the
    /// single largest line item in a frame, and a count is the only assertion
    /// that survives a change of machine. `ShapingCache`'s own `hits`/`misses`
    /// are the precedent.
    ///
    /// **It was a bare `nonisolated(unsafe) static var` first, and that was a
    /// real data race** — written from every executor that ever tokenizes,
    /// while every test that reset it and asserted a count was `@MainActor`
    /// and `UnbreakableRunsTests` called the function from ordinary
    /// nonisolated tests the runner could schedule concurrently.
    /// Unsynchronised concurrent `+= 1` was undefined behaviour outright, and
    /// even an atomic would still have been *wrong*, because a foreign
    /// increment landing inside a reset-and-assert window makes the count
    /// describe two callers instead of one. Reproduced deterministically in 3
    /// of 3 runs by adding one slow nonisolated test that tokenized in a
    /// loop, opening 512 such windows.
    ///
    /// **The next fix was `@MainActor` isolation plus a `Thread.isMainThread`
    /// guard at the call site, and it closed only the nonisolated half of
    /// that problem — kept here, corrected in place, because the gap is the
    /// more useful thing to see than a clean rewrite would be.** Main-thread
    /// isolation does stop a *nonisolated* caller's increment from landing in
    /// another test's window, exactly as measured above. It does nothing
    /// about two `@MainActor` **tests** racing each other for the same
    /// global: `@MainActor` serialises access to the variable, it does not
    /// serialise the *tests*, and Swift Testing runs `@MainActor` tests as
    /// separate tasks that interleave on the main actor at every suspension
    /// point. Under a plain, parallel `swift test` — not `--no-parallel` —
    /// that is exactly what a shared global let happen: measured directly at
    /// this repo's HEAD before this fix, **`theRunCounterIgnoresCallsMadeOffTheMainThread`
    /// itself** — the very test that was supposed to demonstrate main-thread
    /// isolation — failed **8 of 10** plain `swift test` runs, both of its
    /// own assertions, always with the count *higher* than expected by
    /// exactly the calls another `@MainActor` test's window contributed.
    /// (Two earlier, smaller samples — **3 of 5** and **1 of 3** — came from
    /// an earlier session's dispatch rather than from a re-measurement here;
    /// they are the same failure, on the same test, and are superseded by
    /// the 8/10 figure rather than added to it.) `--no-parallel` passed every
    /// time, which is why this went unnoticed for as long as it did: nobody
    /// who saw it fail was running tests the way `swift test` runs them by
    /// default.
    ///
    /// **So the fix is scope rather than isolation.** ``runCallCounter`` is a
    /// `@TaskLocal`: `nil` in production and in any test that never binds it,
    /// and visible only within the task that bound it and that task's
    /// non-detached children — never to a sibling task's window, however the
    /// two happen to interleave. A test that wants a count creates a fresh
    /// ``RunCallCounter`` and calls
    /// `Shaper.$runCallCounter.withValue(counter) { … }` around the work it
    /// is measuring; binding a new counter *is* the reset, so there is no
    /// separate reset call any more. **This is a real behaviour change and
    /// not merely a rewrite of the same guarantee**: a call made from a
    /// foreign executor now counts if the task making it inherited the
    /// binding — a non-detached child task, or a `TaskGroup` child — where
    /// the old main-thread guard silently ignored every off-main-thread call
    /// regardless of who made it or why. `aCounterOnlyCountsCallsWithinItsOwnBinding`
    /// (`ShapingCacheTests.swift`) pins both halves: a `Task.detached`
    /// closure does not inherit the binding by design, so its calls are
    /// invisible to the counter the calling task bound; a `TaskGroup` child
    /// — off the main actor, still inheriting — is counted.
    final class RunCallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); defer { lock.unlock() }; n += 1 }
        /// The number of ``Shaper/unbreakableRuns(of:)`` calls made while
        /// this instance was bound to ``Shaper/runCallCounter``.
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
        init() {}
    }

    /// The counter, if any, that the calling task — or the task it was
    /// created from, transitively, unless a `Task.detached` broke the chain
    /// — has bound via `$runCallCounter.withValue(_:operation:)`. `nil` in
    /// production, where nothing ever binds it.
    ///
    /// **`internal`, deliberately — this is a test instrument, not API.**
    /// Both test targets that use it (`Tests/MetalUITextTests`,
    /// `Tests/MetalUITests`) import `MetalUIText` with `@testable`, which
    /// widens `internal` to visible; nothing needs `public` here, and the
    /// symbols this replaces (`unbreakableRunCalls`, `resetUnbreakableRunCalls`)
    /// were both `internal` too. Verified: narrowing all four declarations in
    /// this type (the class, `count`, `init()`, this property) from `public`
    /// to `internal` builds clean and the suite still passes 811/811 — no
    /// `swiftc -typecheck` guard is added for it, because this restores the
    /// original access level rather than making a new claim the way the
    /// `LayoutPass` narrowing did, and no test ever depended on the wider one.
    @TaskLocal static var runCallCounter: RunCallCounter?
}
