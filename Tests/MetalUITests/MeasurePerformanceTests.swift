import Testing
import Foundation
import MetalUICore
@testable import MetalUILayout
@testable import MetalUIText
@testable import MetalUI

/// Performance assertions that survive a change of machine.
///
/// **These count work rather than timing it.** Every defect these were written
/// for is a count — a tokenizer walk repeated per probe, a per-run loop, a cost
/// linear in total rows rather than visible ones — and a count fails identically
/// on a loaded CI box where a committed millisecond baseline would flake or rot.
@MainActor
struct MeasurePerformanceTests {

    /// Builds a frame over `content` and returns it, so a caller can read the
    /// counters the render just moved.
    ///
    /// **`reportsUnlowerableFields` is a parameter, and a `.proposal` caller must
    /// pass it** (plan task 7, stage 4, lane 5; `LR-BX`, `LR-CG`). This builds a
    /// PRODUCTION frame by default — the shape `Window` builds — and
    /// `demoLikeRows`' root `Box` declares `.minHeight(Pixels(0))`, which
    /// `reportUnconsumedLoweredItems` reported for a root until stage 6b's lane 1,
    /// so a `.proposal` arm without the flag aborted the whole run with no summary
    /// line. The root declares its height, so since that lane the minimum folds
    /// (`LR-DO` item 1) and a production frame completes —
    /// `aProductionFrameOverDemoLikeRowsCompletesUnderTheProposalAuthority` at the
    /// foot of this file, inverted from the abort it used to keep. The flag stays:
    /// any future report must read red here, not abort.
    ///
    /// **`demoLikeRows` is NOT changed to drop the modifier**, deliberately: its
    /// own header says removing a pin from it "would silently inflate every later
    /// before/after ratio measured against this harness", and every committed
    /// literal in this file is measured against it.
    ///
    /// A diagnostics frame replaces a site with no lowering by a 0×0 native leaf
    /// (`Frame.unlowerable`), so a non-empty report means the counters beside it
    /// were taken over a partly degenerate tree. Every `.proposal` arm therefore
    /// asserts `unlowerableFields` **exactly**, against
    /// `demoLikeRowsReport(_:)` below.
    static func render(_ content: () -> some Element,
                       size: Size<Pixels> = Size(width: Pixels(920), height: Pixels(560)),
                       states: StateTable, shapingCache: ShapingCache = ShapingCache(),
                       reportsUnlowerableFields: Bool = false) -> Frame {
        let frame = Frame(contentSize: size, scaleFactor: 2, stateTable: states,
                          shapingCache: shapingCache, theme: .dark,
                          reportsUnlowerableFields: reportsUnlowerableFields)
        var root = content()
        frame.render(&root)
        return frame
    }

    /// `demoLikeRows(_:)`'s whole diagnostics report. (At either authority until
    /// stage 9, which deleted the legacy one.)
    ///
    /// **Empty at both since stage 6b's lane 1** (`LR-DO` item 1). Until then it
    /// was one entry at `.proposal`, the root's own `box.minSize.unconsumed`:
    /// `reportUnconsumedLoweredItems` exempted a root from `flexGrow`,
    /// `flexShrink`, `flexBasis` and `alignSelf` and from nothing else, so the
    /// fixture's root `.minHeight(Pixels(0))` reported. The root **declares** its
    /// height (370), and a px/rem minimum or maximum on a declared root axis now
    /// folds into it (the element's own frame already folded it, `LR-AG`) and
    /// stops reporting, so the report is empty. The tree was never degenerate for
    /// it — the root's report was noted after registration, not replaced by a leaf
    /// — so no work literal in this file moves. **Any entry is a finding**, and the
    /// work numbers taken alongside it are not this stage's (spec §6 lane 5).
    static var demoLikeRowsReport: [UnlowerableField] {
        []
    }

    /// The native layout work one warm `demoLikeRows(_:)` frame does —
    /// `LayoutTree.lastNativeLayoutWork` after `Frame.render`, which is
    /// `computeRootLayout`'s own `computeNativeLayout` call (ruling `SA-M`;
    /// `LR-CG`).
    ///
    /// **Derived before it was read, from the window and from the cold sweep.**
    /// `visibleRange` at `offset == 0` over a 370pt viewport of 28pt rows takes
    /// `first = max(0, 0 − 2) = 0` and `last = ceil(370/28) + 2 = 14 + 2 = 16`,
    /// so a warm frame realizes **r = 16** rows whatever the logical count. A
    /// COLD frame realizes all `n` of them (`MP-I`), which gives the same function
    /// at four points two orders of magnitude apart — measured at
    /// n = 40 / 160 / 500 / 2000:
    ///
    /// | n | `measureCalls` | `cacheHits` | `cacheMisses` |
    /// |---|---|---|---|
    /// | 40 | 41 | 247 | 288 |
    /// | 160 | 161 | 967 | 1128 |
    /// | 500 | 501 | 3007 | 3508 |
    /// | 2000 | 2001 | 12007 | 14008 |
    ///
    /// — exactly `r + 1`, `6r + 7` and `7r + 8`. The `+ 1` is
    /// `WindowedRowsLayout.sizeThatFits` itself, the `r` the realized rows'
    /// `Text` leaf closures; `measureCalls` counts leaf closures as well as
    /// custom `sizeThatFits` bodies (`NativeLayoutWork.measureCalls`' own doc),
    /// which is `ListLoweringTests`' test 2.3's correction applied here rather
    /// than re-learnt. Evaluated at r = 16 the model predicts **17 / 103 / 120**,
    /// and the warm frames read exactly that at every one of the four counts —
    /// the prediction was made on the cold column and confirmed on the warm one.
    ///
    /// **`O(window)`, not `O(logicalCount)`: that is the whole exit criterion**
    /// (spec §7), and these three literals are what make
    /// `aListsWorkIsTheSameFor100kRowsAsFor500`'s equality say something. An
    /// equality alone would hold just as well if the counters were stuck.
    ///
    /// (Until stage 9 a `.legacy` arm read zero here, as a control that the
    /// numbers were the frame's own native run; each frame below is fresh, which
    /// is what that control established.)
    static let demoLikeRowsWarmWork = NativeLayoutWork(measureCalls: 17, cacheHits: 103, cacheMisses: 120)

    /// Font resolution is memoized on the window's `ShapingCache`, so a warm
    /// frame over the same `Text`s reaches the uncached
    /// `FontResolver.resolve(family:size:)` **zero** times. Before the memo,
    /// `Text.requestLayout` and `Text.paint` each called it, so every `Text`
    /// the frame built paid two `CTFont` creations every frame.
    ///
    /// **One shared cache across both renders, deliberately** — the opposite of
    /// `aListsWorkIsTheSameFor160RowsAsFor40`'s fresh cache per frame: that test's
    /// instrument is per-frame and must stay so; this one is exactly the
    /// cross-frame question, and a `Window` owns one cache for its life.
    ///
    /// The cold arm reads **1**: every row asks for `(nil, 13)`, so one request
    /// is shared across all 40 rows *and* across the layout and paint phases.
    /// The `lookups` arm is the reachability control: it proves the warm frame
    /// did build and paint `Text`s, so a zero is not a frame that built none.
    @Test
    func aWarmFrameReachesTheUncachedFontResolverZeroTimes() throws {
        // Stage 6b (`LR-DI`, `LR-DO` item 1): runs at the helper's default
        // authority — stage 6b's flip makes it `.proposal` — with diagnostics
        // on, and asserts each render's report EXACTLY against
        // `demoLikeRowsReport(_:)` (empty at both since lane 1's root fold), so
        // a report reads red here instead of aborting the suite (`LR-BX`'s
        // pattern). Before lane 1 a production frame over this fixture trapped
        // on the root's `box.minSize.unconsumed`.
        let states = StateTable()
        let cache = ShapingCache()

        let cold = FontResolver.CallCounter()
        var coldFrame: Frame?
        FontResolver.$resolveCallCounter.withValue(cold) {
            coldFrame = Self.render({ demoLikeRows(40) }, states: states, shapingCache: cache,
                                    reportsUnlowerableFields: true)
        }

        let lookupsBefore = cache.lookups
        let warm = FontResolver.CallCounter()
        var warmFrame: Frame?
        FontResolver.$resolveCallCounter.withValue(warm) {
            warmFrame = Self.render({ demoLikeRows(40) }, states: states, shapingCache: cache,
                                    reportsUnlowerableFields: true)
        }

        for (name, frame) in [("cold", try #require(coldFrame)), ("warm", try #require(warmFrame))] {
            #expect(frame.unlowerableFields == Self.demoLikeRowsReport,
                    "\(name) frame: \(frame.unlowerableFields)")
        }
        #expect(cache.lookups > lookupsBefore)
        #expect(warm.count == 0)
        #expect(cold.count == 1)
    }

    /// **The ungated twin of the 100 000-row exit test**, run on every unfiltered
    /// suite (under both layout authorities from stage 4's lane 5, `LR-CG`, until
    /// stage 9).
    ///
    /// **The native work counters carry it.** Until stage 9 it also counted
    /// `Shaper.unbreakableRuns` calls: a legacy arm required a non-zero count and
    /// compared 160 against 40, and the proposal arm asserted the zero (a lowered
    /// `Text` measures through `proposalTextMeasurement` and takes no min-content
    /// probe). Stage 9 deleted the tokenizer min-content path and its counter
    /// (`LR-FD`), so that half is gone; the literals below and the cache-entry
    /// equality are what say `O(window)`.
    @Test
    func aListsWorkIsTheSameFor160RowsAsFor40() throws {
        let diagnostics = true
        let states40 = StateTable(), states160 = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states40, reportsUnlowerableFields: diagnostics)
        _ = Self.render({ demoLikeRows(160) }, states: states160, reportsUnlowerableFields: diagnostics)

        let f40 = Self.render({ demoLikeRows(40) }, states: states40, reportsUnlowerableFields: diagnostics)
        let f160 = Self.render({ demoLikeRows(160) }, states: states160, reportsUnlowerableFields: diagnostics)

        // The diagnostics frame's whole cost, asserted exactly: one entry, the
        // root's own, or the counters below were taken over a degenerate tree.
        #expect(f40.unlowerableFields == Self.demoLikeRowsReport, "\(f40.unlowerableFields)")
        #expect(f160.unlowerableFields == Self.demoLikeRowsReport, "\(f160.unlowerableFields)")

        // The native half — `O(window)`, hand-derived in `demoLikeRowsWarmWork`.
        #expect(f40.tree.lastNativeLayoutWork == Self.demoLikeRowsWarmWork,
                "40 rows: \(f40.tree.lastNativeLayoutWork)")
        #expect(f160.tree.lastNativeLayoutWork == Self.demoLikeRowsWarmWork,
                "160 rows: \(f160.tree.lastNativeLayoutWork)")

        // Equal, not merely close: with a uniform row height the window is
        // computed by division, so the same 16 rows are built either way and
        // the extra 120 rows cost nothing at all.
        // `shapingCache.storageCount` rather than `scene.glyphs.count`: the
        // row text embeds `n` ("Row i of n — …", matching the demo), so at
        // n == 160 every visible row's string is one character longer than
        // at n == 40 — a glyph-count comparison would fail by exactly one
        // glyph per visible row regardless of whether windowing works,
        // because it is sensitive to string LENGTH, not row count.
        // `storageCount` counts cache entries, one per distinct (string,
        // font, width) actually shaped — invariant to how long each string
        // is, and still ~4x apart between a correct and a disabled window.
        #expect(f160.shapingCache.storageCount == f40.shapingCache.storageCount)
    }

    /// Task 7's held-back assertion, and the reason it changed shape from
    /// its own held-back form. That form swept the outer `Frame`'s width
    /// while rendering `demoLikeRows(40)`, whose every internal width is
    /// pinned (see that function's own comment) precisely so an unrelated
    /// test's probe count stays deterministic — which makes it, measured,
    /// invariant to the outer frame's width: sharing one `ShapingCache`
    /// across the original 120-iteration sweep produces a one-time warm-up
    /// value and then a byte-identical `storageCount` on every later
    /// iteration, never exceeding it. That is not this defect — §6 describes
    /// unbounded growth from a *drag*, i.e. new distinct content arriving
    /// over many frames, not from a fixed 40-row list re-rendered at
    /// different container widths.
    ///
    /// This sweeps a **row width and a per-frame-unique row string** instead,
    /// which reproduces the real mechanism (on both dictionaries at once until
    /// stage 9 deleted the min-content one, `LR-FD`):
    /// `rowWidth` cycles so the item is genuinely re-wrapped at a changing
    /// width — `storage`'s `(string, font, width)` key changes every frame,
    /// the same way resizing a real window changes the fractional width
    /// `Text.swift`'s own measure function offers (divergence 8 measures this
    /// exact instability). The row's own text embeds the loop index, so the
    /// string is new every frame too — the same way a scrolling list keeps
    /// presenting row numbers the cache has never seen. The dictionary cannot
    /// plateau the way `demoLikeRows` did.
    ///
    /// **The assertion is `<= sweepThreshold`, which this workload happens to
    /// satisfy — it is not a general ceiling the type enforces.**
    /// `ShapingCache.sweepThreshold` is a sweep trigger, not a bound (see its
    /// own doc comment): the sweep can only remove entries the current frame
    /// did not touch, so a workload whose live per-frame set itself exceeded
    /// the threshold would settle above it forever, correctly. This
    /// workload's per-frame set stays small (one new width and one new
    /// string, plus a handful of shared words), so the two dictionaries
    /// settle near the recent-generation window rather than at the
    /// threshold — this test is evidence the sweep runs and keeps pace with
    /// unbounded input, not evidence of a hard cap.
    @Test
    func theShapingCacheStaysNearTheSweepThresholdAcrossAWidthSweep() {
        let states = StateTable()
        let cache = ShapingCache()
        var lastStorage = 0
        for i in 0..<300 {
            let w = 920.0 + Double(i) * 0.5
            let rowWidth = 80.0 + Double(i).truncatingRemainder(dividingBy: 40) * 0.5
            let frame = Self.render({
                Box { Text("Row \(i) of 4000 — a scrollable list item") }
                    .cssWidth(Pixels(Float(rowWidth)))
                    .alignItems(.stretch)
            }, size: Size(width: Pixels(Float(w)), height: Pixels(560)),
               states: states, shapingCache: cache)
            lastStorage = frame.shapingCache.storageCount
        }
        // Today, with no sweep: storage climbs to 1508 — one new distinct row
        // string per iteration, never reused, never evicted. (Until stage 9 a
        // second dictionary, the min-content memo, was bounded here too; stage 9
        // deleted it with tokenizer min-content, `LR-FD`.)
        #expect(lastStorage <= ShapingCache.sweepThreshold)
    }

    // MARK: - Task 8: M3's exit criterion — a 100k-row list

    /// **Design spec §12 milestone 3's own exit criterion**: "a 100k-row
    /// virtualized list scrolling smoothly." This is the same instrument as
    /// `aListsWorkIsTheSameFor160RowsAsFor40`, extended two and a half orders
    /// of magnitude — 100,000 against 500 rather than 160 against 40 — and it
    /// asserts the SHAPE, not the time: a count fails identically on a loaded
    /// machine where a millisecond baseline would flake, per this file's own
    /// header comment.
    ///
    /// **The cold-frame timing is folded into this same test rather than
    /// given its own** (Step 2 of the brief: "measure the cold frame
    /// separately and report it"). Reaching steady state at 100k requires one
    /// full cold-frame render regardless — ruling MP-I, a `ScrollView`'s
    /// viewport is not measured until its own `prepaint` has run once, so
    /// `List` builds every row on frame 0 — and that render is exactly the
    /// number Step 2 asks for. Timing a SECOND, separate cold render would
    /// double this test's own cost for no new information; the `warm-up`
    /// comment below is where that number is taken and printed.
    ///
    /// **Reported here, not asserted**: `swift test` output carries the
    /// printed line; the task report quotes the numbers it produced on this
    /// machine, in both debug and release.
    ///
    /// **Disabled by default: it alone adds ~42 s debug / ~17 s release to the
    /// suite's wall clock**, dominated by the one mandatory 100,000-row cold
    /// frame with full text shaping (ruling MP-I). **Twice that since stage 4's
    /// lane 5**, which gave it a second authority: re-measured on this machine,
    /// one cold 100 000-row frame is **37.16 s legacy / 24.98 s proposal** in
    /// debug (whole test 62.9 s) and **12.24 s / 7.55 s** in release (20.1 s).
    /// The ~17 s release figure `MP-I` carries predates both. Every later task, review
    /// and fix round in this milestone would otherwise pay that on every run.
    /// The gating shape the WebKit golden regenerator had before stage 7a
    /// retired it with the goldens (record §48) — an expensive
    /// deliberate act, not a per-run guard. Enable deliberately:
    ///   METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
    ///
    /// **Parameterised over both layout authorities since plan task 7's stage 4,
    /// lane 5** — spec §4.1 row 4's exit test, which is why it now also counts
    /// `LayoutTree.lastNativeLayoutWork` against the literals
    /// `demoLikeRowsWarmWork(_:)` derives, and prints the cold frame at **each**
    /// authority (spec §4.1 row 5: `MP-I`'s cold frame is re-measured, not
    /// re-reasoned).
    ///
    /// **One authority since stage 9** (`LR-FE`), and with it no tokenizer half
    /// (`LR-FD`): the same collapse as its ungated twin
    /// `aListsWorkIsTheSameFor160RowsAsFor40`, which runs the identical
    /// instrument at 40 against 160.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_100K_LIST_TEST"] == "1"))
    func aListsWorkIsTheSameFor100kRowsAsFor500() throws {
        let diagnostics = true
        let states500 = StateTable(), states100k = StateTable()
        _ = Self.render({ demoLikeRows(500) }, states: states500, reportsUnlowerableFields: diagnostics)   // warm

        let clock = ContinuousClock()
        let coldElapsed = clock.measure {
            // warm — ruling MP-I's cold frame
            _ = Self.render({ demoLikeRows(100_000) }, states: states100k, reportsUnlowerableFields: diagnostics)
        }
        // Step 2 of the brief: report, do not assert. Printing keeps the
        // number in `swift test`'s own output rather than in a threshold
        // this repo's own practice document says would flake on a loaded box.
        print("MeasurePerformanceTests: cold frame at 100,000 rows took \(coldElapsed)")

        let f500 = Self.render({ demoLikeRows(500) }, states: states500, reportsUnlowerableFields: diagnostics)
        let f100k = Self.render({ demoLikeRows(100_000) }, states: states100k, reportsUnlowerableFields: diagnostics)

        // The diagnostics frame's whole cost, exactly — a second entry would mean
        // every count below was taken over a partly degenerate tree.
        #expect(f500.unlowerableFields == Self.demoLikeRowsReport, "\(f500.unlowerableFields)")
        #expect(f100k.unlowerableFields == Self.demoLikeRowsReport, "\(f100k.unlowerableFields)")

        // **The new half, and the one the proposal arm rests on**: the kernel's
        // own work is the same at 500 and at 100,000, and equal to the literal
        // `demoLikeRowsWarmWork(_:)` derives from the window alone. The equality
        // by itself would hold for a stuck counter; the literals are what make it
        // say `O(window)`.
        #expect(f500.tree.lastNativeLayoutWork == Self.demoLikeRowsWarmWork,
                "500 rows: \(f500.tree.lastNativeLayoutWork)")
        #expect(f100k.tree.lastNativeLayoutWork == Self.demoLikeRowsWarmWork,
                "100k rows: \(f100k.tree.lastNativeLayoutWork)")
        #expect(f100k.tree.lastNativeLayoutWork == f500.tree.lastNativeLayoutWork)

        // Equal, not merely close — same reasoning as the 160-vs-40 test
        // above: a uniform row height means the window is found by division,
        // so the same 16 rows are built regardless of whether the list holds
        // 500 rows or 100,000.
        #expect(f100k.shapingCache.storageCount == f500.shapingCache.storageCount)
    }

    /// **Step 3 of the brief: the resident `StateTable` entry set stays
    /// bounded while scrolling a large list, with tombstones live.**
    /// `demoLikeRows(_:)` cannot see this — its rows carry no `@State` at all
    /// (measured live set of 1, the scroller's own offset), so it cannot
    /// exercise the tombstone/reap machinery `StateTable.sweep()` added this
    /// milestone. `StatefulListRow` below is this file's own version of
    /// `TombstoneTests.ExcursionRow` — a row that increments a `@State` every
    /// time it is actually built — and this test drives the scroller's stored
    /// `ScrollState` directly (`TombstoneTests`' idiom, `ScrollRoutingTests`'
    /// `stateTable.peek(id, as: ScrollState.self)` run in reverse) rather than
    /// simulating wheel events.
    ///
    /// **Deliberately content-free** (no `Text`): Step 1's test above already
    /// covers the shaping-heavy shape (`demoLikeRows`'s rows carry a distinct
    /// string apiece); this one isolates the `StateTable` question and keeps
    /// the mandatory cold frame cheaper by not also paying for thousands of
    /// distinct strings' worth of shaping.
    ///
    /// **10,000 rows, not 100,000 — a fix-round finding, not a shortcut.**
    /// The checkpoint counts this test asserts depend on the *window size* and
    /// `staleAfterGenerations`, not on total row count: measured side by side,
    /// 10k and 100k produce byte-identical checkpoints (77 / 127 / 99 at
    /// frames 10/100/299 — re-measured fresh for this fix round, at both row
    /// counts, rather than shifted by arithmetic; the byte-identical property
    /// still holds) and a byte-identical cold-frame peak shape
    /// (`n + 2` as of Task 7 — see below). 10k reaches the same demonstration in 0.181 s against
    /// 1.3-1.9 s release for 100k, and this test alone was ~49 s of the
    /// suite's added wall clock at 100k. `aListsWorkIsTheSameFor100kRowsAsFor500`
    /// above is the one that must keep the real 100k — it is timing the M3
    /// exit-criterion number itself — but this test's question ("does the
    /// bound hold, does it stay away from the peak") does not need six figures
    /// of rows to ask.
    ///
    /// **Why the bound is safe rather than a guess.** After the cold frame,
    /// every one of the rows already has a `StateTable` entry — a later frame
    /// that re-marks an already-resident row does not create a new entry, it
    /// only flips `isLive`/`lastSeenGeneration` on the existing one
    /// (`StateTable.mark`/`withState`). So `table.count` cannot climb back
    /// toward `2n + 6` once it has fallen: entries leave storage only through
    /// `sweep()`'s reap, and this scroll never introduces an id `sweep()` has
    /// not already seen. A policy that never reaps (the pre-tombstone
    /// `sweep()`, or a reap with the size gate deleted the wrong way) would
    /// leave `table.count` at exactly `2n + 6` forever, since nothing would
    /// ever remove an entry; this test's bound (`n / 10` = 1000) is **3.9x**
    /// the resident count steady scrolling actually leaves today, not an
    /// order of magnitude — that overstatement was this comment's own fix-
    /// round mistake, corrected here rather than only in the report
    /// (practices doc mechanism 1). Measured 150-256 entries at this test's
    /// checkpoints as of the animation milestone's Task 4, against
    /// **77 / 127 / 99 measured at the same three checkpoints one commit
    /// before Task 4** (`2edf193`, re-run directly rather than carried
    /// forward from CLAUDE.md's own quote of the same three numbers) — a
    /// **1.5x-3.3x** increase across the three checkpoints, not the "roughly
    /// double the pre-Task-4 figure (~20-41)" this comment claimed in its
    /// first draft. That "~20-41" was never this test's own pre-Task-4
    /// number at all — it was CLAUDE.md's own quote of an EARLIER
    /// milestone's steady-scrolling figure, anchored to here without
    /// re-measuring this test's actual baseline first (practices doc
    /// mechanism 3, staleness inherited rather than produced). The real
    /// mechanism behind the increase stands: every windowed row's own
    /// wrapping `Box` now also carries a `$anim` retention slot alongside
    /// its `StatefulListRow`'s `@State` one — see the cold-frame assertion
    /// below. The 3.9x margin is loose enough to hold under any working
    /// reap policy and tight enough to fail hard under a reap that does not
    /// run at all.
    ///
    /// **One thing changed in KIND, not only in size, and it bounds how far
    /// that 3.9x can be trusted.** Before Task 4 the steady set was
    /// *working-set*-limited — 77 / 127 / 99, whatever the visible window
    /// plus its overscan happened to need. It is now *gate*-limited: the reap
    /// runs the table down toward `StateTable.sweepThreshold` (256) and
    /// stops, which is why two of the three checkpoints read exactly 256
    /// rather than some workload-shaped number. That is not a defect — the
    /// entries above the gate are genuinely stale and genuinely removed — but
    /// it means this test's margin is now a function of a CONSTANT rather
    /// than of the workload, so raising `sweepThreshold` past `n / 10`
    /// (1000 at this fixture's size) would redden this test for a reason
    /// having nothing to do with reaping. Whoever raises it owns this
    /// assertion.
    ///
    /// **This test cannot see whether the size-gated reap exists at all — a
    /// fix-round caveat, not a hedge.** `storage.count` sits above
    /// `StateTable.sweepThreshold` throughout this test (10,002 rows against
    /// a 256 threshold), so the size gate is permanently satisfied here and a
    /// mutation that deleted the gate (`storage.count > sweepThreshold`) would
    /// still redden nothing in THIS test — it would only change how early the
    /// first reap fires, which this test does not distinguish. Task 3 of this
    /// milestone found exactly this shape in its own `List` fixture: a
    /// permanently-true guard condition cannot test whether the guard exists.
    /// `aStaleEntryIsRetainedForeverWhileStorageStaysAtOrBelowSweepThreshold`
    /// (`TombstoneTests.swift`) is the test that actually pins the gate — a
    /// single stale entry with `storage.count == 1`, nowhere near the
    /// threshold, retained forever. Read that test for the size-gate claim;
    /// read this one only for "the bound holds at scale."
    ///
    /// **Under both layout authorities from plan task 7's stage 4, lane 5, to
    /// stage 9** (spec §4.1 rows 5 and 6; `LR-CG`). Every literal below — the cold
    /// `2n + 6` (`2n + 5` before `DD-O`) and all three checkpoints — read identically on both, which is the
    /// measurement that says the windowed `ProposalLayout` changed what a row's
    /// rect comes through and changed nothing about which rows are built or when
    /// they are reaped. **A PRODUCTION frame**: this fixture sets no
    /// `reportsUnlowerableFields`, so anything unlowered aborts rather than
    /// reporting — which is why `StatefulListRow` is spelled through
    /// `lowerLegacyNode`.
    @Test
    func theResidentEntrySetStaysBoundedWhileScrolling10kRows() throws {
        func px(_ v: Float) -> Pixels { Pixels(v) }
        let rowHeight = px(20)
        let n = 10_000
        let data = (0..<n).map(DemoRow.init)
        let table = StateTable()

        var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
            List(data, rowHeight: rowHeight) { _ in StatefulListRow() }
        }
        let contentSize = Size<Pixels>(width: px(200), height: px(400))
        let scrollerID = GlobalElementID.child(of: nil, at: 0, name: ElementID("scroller"))

        func renderFrame(offset: Double?) {
            if let offset {
                let current = table.peek(scrollerID, as: ScrollState.self) ?? ScrollState()
                table.write(scrollerID, ScrollState(offset: offset,
                                                    lastScrollTime: current.lastScrollTime,
                                                    viewportExtent: current.viewportExtent))
            }
            let frame = Frame(contentSize: contentSize, scaleFactor: 1, stateTable: table)
            frame.render(&tree)
        }

        // Frame 0: cold. No `ScrollView.prepaint` has run yet, so `List`
        // builds every row (ruling MP-I) rather than windowing — the peak
        // this test exists to see reaped.
        renderFrame(offset: nil)
        // **`2n + 6` since plan task 10 (ruling `DD-O`)**: `DD-F` stores the
        // `List`'s origin within its scroller at the list's own id
        // (`ListOrigin`, through `withState`), one more fixed entry for a
        // `List` inside a vertical scroller — the sixth below. It read `2n + 5`
        // before, as this paragraph goes on to derive.
        //
        // `2n + 5`, not `n + 2` — moved by the animation milestone's Task 4
        // (20006 at n = 10_000, re-run after wiring `animated(_:_:for:pass:)`
        // into `Box.requestLayout`) and moved again by plan task 7's stage 4
        // lane 1 (`LR-BS`), which demoted the windowing spacer from a `Box`
        // ELEMENT to a bare legacy node and took its `$anim` entry with it.
        // Measured rather than derived, at both steps. Every
        // row is wrapped in its OWN `Box` (`List.requestLayout`, `rows`), and
        // `Box` now unconditionally substitutes through `animated` — first
        // sighting always writes a settled baseline (ruling Q,
        // `AnimatedStyle.swift`), so every one of the `n` built rows' wrapping
        // `Box` gains a persistent `$anim` slot alongside its
        // `StatefulListRow`'s own `@State` one: `n` (row state) + `n` (row
        // `Box` `$anim`) = `2n`. The fixed overhead grew from 2 to 6 the same
        // way and is now **5**: the scroller's `ScrollState`, the `List`'s own
        // `$ax` retention slot (Task 7, unchanged), the `List`'s own wrapping
        // `Box`'s `$anim` slot, and `ScrollView`'s two
        // registering nodes' `$anim` slots (content and viewport) — five
        // fixed entries regardless of row count, none of them per-row. The
        // sixth used to be the windowing spacer `Box`'s `$anim` slot;
        // `theListsSpacerIsANodeNotAnElement` (`ListTests.swift`) pins its
        // absence directly, and this literal is the arithmetic half of the
        // same claim.
        #expect(table.count == 2 * n + 6, """
                the cold frame must build every row plus the scroller's own \
                ScrollState entry plus the List's own $ax retention slot — Task 7 made \
                a List unconditionally emit ITS OWN AXNode (role .container, carrying \
                logicalCount) so spec §9's exit criterion 4 holds regardless of whether \
                a caller declared one, and Frame.emitAXNode retains a durable copy of \
                every emission under a distinct \"$ax\" child slot (Task 6) — one more \
                entry than before Task 7, for exactly one List, not per row. The animation \
                milestone's Task 4 then wired every Box (including one per row, the List's \
                own wrapper and ScrollView's two nodes) through \
                animated(_:_:for:pass:), which unconditionally persists a $anim baseline on \
                first sighting — doubling the per-row cost and adding three more fixed entries. \
                Stage 4 lane 1 (LR-BS) then took the windowing spacer's own entry away by \
                demoting it from a Box element to a bare legacy node. Plan task 10's DD-F \
                added the List's stored origin (DD-O): 2n + 6.
                """)

        // Scroll in large jumps across the FULL 10k-row range — each
        // frame's window barely overlaps the last, so this is the shape that
        // would grow `storage` without bound under a policy that never
        // reaps: the cold frame already created every entry, so nothing here
        // needs a NEW entry to be built, only for stale ones to be removed.
        // `staleAfterGenerations` (2) is why a handful of frames is enough
        // for the cold spike itself to become reapable.
        let viewportExtent = Double(contentSize.height.value)
        let totalExtent = Double(rowHeight.value) * Double(n)
        let frameCount = 300
        var countAtCheckpoint: [Int: Int] = [:]
        for i in 0..<frameCount {
            let offset = (totalExtent - viewportExtent) * Double(i) / Double(frameCount - 1)
            renderFrame(offset: offset)
            if i == 10 || i == 100 || i == frameCount - 1 {
                countAtCheckpoint[i] = table.count
            }
        }

        for (frame, count) in countAtCheckpoint.sorted(by: { $0.key < $1.key }) {
            print("MeasurePerformanceTests: table.count after scroll frame \(frame) = \(count)")
            #expect(count < n / 10, """
                    after frame \(frame) of scrolling, \(count) entries survive — a \
                    policy that never reaps would sit at \(2 * n + 6) here, since every \
                    jump only re-marks entries the cold frame already created.
                    """)
        }
    }
}

// `ScrollView` conforms to `Element`, not `StyledElement` (CLAUDE.md's
// declared-but-inert table), so `.width`/`.height`/`.minHeight` land on a
// wrapping `Box` — the same shape `Sources/MetalUIDemoContent/DemoContent.swift` uses for
// its own list. This builds through `List`, matching the demo's own
// row shape (`DemoRow` mirrors the identity a real caller's data would carry;
// `List` requires `Data.Element: Identifiable` and a bare `Range<Int>`'s
// `Int` does not conform).
//
// Each row's `.width(Pixels(420))` is pinned, matching the demo's own row
// closure (search `DemoContent.swift` for `.width(Pixels(420))`, which appears on
// the row and again on the `Box` wrapping the `ScrollView`) rather than left
// `auto`. An
// auto-width row is an auto-cross item, so `collectItems`' fit-content probe
// on the cross axis recurses into §4.5's automatic minimum a THIRD time —
// three `unbreakableRuns` calls per `Text` instead of two. Measured: an A/B
// over exactly this one line moved the call count from 120 to 80 for 40
// rows, with `alignItems` (`.stretch` vs `.center`) ruled out as the cause
// first. The pin sits on the `Box` this file's own row closure contributes,
// not on anything inside `List` — `List`'s internal row wrapper has no width
// of its own, so an un-pinned `Text` here would still hit the same third
// probe. Removing this pin would silently inflate every later before/after
// ratio measured against this harness.
private struct DemoRow: Identifiable {
    let id: Int
}

@MainActor
func demoLikeRows(_ n: Int) -> some Element {
    Box {
        ScrollView(.vertical) {
            List((0..<n).map(DemoRow.init), rowHeight: Pixels(28)) { datum in
                Box {
                    Text("Row \(datum.id + 1) of \(n) — a scrollable list item")
                }
                .cssWidth(Pixels(420))
                .alignItems(.stretch)
            }
        }
    }
    .cssWidth(Pixels(420))
    .cssHeight(Pixels(370))
    .cssMinHeight(Pixels(0))
}

/// A `List` row with a live `@State` slot and no content — this file's own
/// version of `TombstoneTests.ExcursionRow`, used by
/// `theResidentEntrySetStaysBoundedWhileScrolling10kRows` because
/// `demoLikeRows(_:)`'s rows carry no `@State` at all (measured live set of
/// 1, the scroller's own offset) and so cannot exercise `StateTable`'s
/// tombstone/reap machinery. Deliberately content-free — `Step 1`'s test
/// above already covers the shaping-heavy shape, and a 10,000-row cold
/// frame is cheaper without also shaping 10,000 distinct strings.
/// `elementID` is computed rather than stored so `Mirror` sees only `count`:
/// its ordinal is 0, matching `TombstoneTests.ExcursionRow` and every other
/// single-`@State` fixture in this suite (`$state0`).
///
/// **Spelled through the legacy lowering** (plan task 7, stage 4, lane 5;
/// `ListTests.Row`'s own re-spelling, `LR-BW`). `lowerLegacyNode` over no
/// children forwards to `lowerLegacyLeaf` over a 0×0 native leaf by itself,
/// which is the lowering of a childless `Box`. (Until stage 9 it also kept a
/// legacy branch, and `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame`
/// kept the pre-stage-4 `pass.requestNode` spelling's abort as an observable;
/// stage 9 deleted the registrar, and with it that test, `LR-FH` item 1.)
private struct StatefulListRow: Element {
    @State var count = 0
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        count += 1
        return (pass.lowerLegacyNode(Style(), declared: Style(), children: [], site: .box), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

private struct MeasureRow: Identifiable { let id: Int }

/// **The first of lane 5's two reds, and neither could be taken in-process**
/// (`LR-BX`, spec §6 lane 5's own first paragraph).
/// `MeasurePerformanceTests.render` builds a **production** frame — no
/// `reportsUnlowerableFields` — and `demoLikeRows`' root `Box` declares
/// `.minHeight(Pixels(0))`, a `Self`-returning modifier that lands on the root's
/// own `Style`. `reportUnconsumedLoweredItems` exempts a root from `flexGrow`,
/// `flexShrink`, `flexBasis` and `alignSelf` and from nothing else, so a
/// non-`.auto` `minSize` on the root still reports, and in a production frame
/// `noteUnlowerable` traps. So a `.proposal` arm of any test in this file does
/// not fail — it **aborts the whole run**, with no summary line.
///
/// Recorded, with the assertion temporarily pointed at a string that cannot
/// match (reverted; `git status --short` clean afterwards):
///
///     MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.minSize.unconsumed
///     has no proposal lowering (plan task 7, stage 2); a tree containing it
///     cannot run under the proposal layout authority.
///
/// **The fix is `render`'s `reportsUnlowerableFields:` parameter, not removing
/// `.minHeight(0)` from `demoLikeRows`** — that fixture's own header says
/// removing a pin from it "would silently inflate every later before/after ratio
/// measured against this harness", and every committed literal in this file is
/// measured against it.
///
/// **Inverted by stage 6b's lane 1** (`LR-DO` item 1; it was
/// `aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority`, expecting
/// `.failure`). The root declares its height, so its `.minHeight(0)` folds into it
/// and no longer reports: a production frame over `demoLikeRows` now **completes**.
/// The abort it used to pin is kept, for a root minimum that cannot fold (an
/// **auto** axis), by `RootFieldLoweringTests`' 1.8 through a production `Window`.
///
/// Mutation that must redden it: **M1h**, the root fold removed (the child aborts on
/// `box.minSize.unconsumed`).
@Test func aProductionFrameOverDemoLikeRowsCompletesUnderTheProposalAuthority() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            var root = demoLikeRows(40)
            Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)),
                  scaleFactor: 2, stateTable: StateTable(), shapingCache: ShapingCache(),
                  theme: .dark).render(&root)
        }
    }
}

/// **The positive control for the probe above, and it is the lane's fix.** The
/// identical tree under the identical authority, with `reportsUnlowerableFields`
/// on, runs to completion: so the abort is the diagnostics flag and not the
/// `List`, the `ScrollView`, the `Text` or the proposal authority itself.
///
/// What the diagnostics frame then reports is asserted exactly by
/// `aListsWorkIsTheSameFor160RowsAsFor40` (empty since stage 6b's root fold),
/// because under `reportsUnlowerableFields` a
/// site with no lowering is replaced by a 0×0 native leaf, so any OTHER entry
/// would mean the work counts beside it were taken over a partly degenerate tree.
@Test func aDiagnosticsFrameOverDemoLikeRowsRunsUnderTheProposalAuthority() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            var root = demoLikeRows(40)
            Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)),
                  scaleFactor: 2, stateTable: StateTable(), shapingCache: ShapingCache(),
                  theme: .dark,
                  reportsUnlowerableFields: true).render(&root)
        }
    }
}

/// **The positive control for `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame`**
/// (retired at stage 9 with the registrar it read) — `TombstoneTests`'
/// `aBoxSpelledListRowDoesNotAbortAProductionProposalFrame` in this file's own
/// fixture. It stays as the fact that a production frame over this fixture's
/// `List` completes.
@Test func aBoxSpelledRowInTheResidentSetFixtureDoesNotAbort() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let data = (0..<50).map(MeasureRow.init)
            var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(data, rowHeight: Pixels(20)) { _ in Box() }
            }
            Frame(contentSize: Size(width: Pixels(200), height: Pixels(400)),
                  scaleFactor: 1, stateTable: StateTable()).render(&tree)
        }
    }
}
