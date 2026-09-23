import Testing
import Foundation
import MetalUICore
import MetalUILayout
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
    static func render(_ content: () -> some Element,
                       size: Size<Pixels> = Size(width: Pixels(920), height: Pixels(560)),
                       states: StateTable, shapingCache: ShapingCache = ShapingCache()) -> Frame {
        let frame = Frame(contentSize: size, scaleFactor: 2, stateTable: states,
                          shapingCache: shapingCache, theme: .dark)
        var root = content()
        frame.render(&root)
        return frame
    }

    @Test
    func aWarmFrameTokenizesEachDistinctStringAtMostOnce() throws {
        let states = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states)   // warm

        let counter = Shaper.RunCallCounter()
        Shaper.$runCallCounter.withValue(counter) {
            _ = Self.render({ demoLikeRows(40) }, states: states)
        }

        // 40 rows share no strings, so 40 distinct strings is the ceiling a
        // per-string memo allows. `ShapingCache.minContentWidth` memoizes the
        // tokenizer walk, so within one frame the second of the two
        // min-content probes per `Text` hits the memo instead of
        // retokenizing — one call per distinct string per frame, hence 40.
        //
        // **Both probes reach the SAME line, not two different ones**
        // (measure-performance milestone, ruling MP-B): `FlexEngine`'s §4.5
        // automatic-minimum content-suggestion probe, called once from
        // `flexBaseSize`'s content-basis pass over an ancestor and once from
        // the real positioning pass floor-clamping the item for §9.7's freeze
        // loop. It is NOT "the direct measure pass and `collectItems`' cross-
        // axis fit-content probe" — that cross-axis site is dead on this tree,
        // because the row `.width(Pixels(420))` pin below (see this file's
        // `demoLikeRows` comment) removes the auto cross size it needs to
        // fire at all. A call-stack capture confirmed this; do not restate
        // the cross-axis probe as one of the two without re-measuring.
        //
        // This reads exactly 40 rather than 0 because `Self.render` above
        // hands each call a fresh `Frame` with no `shapingCache:` argument, so
        // the two renders in this test do not share a cache — only calls
        // *within* one frame benefit from the memo here. A `Window`-threaded
        // cache, persisted across frames the way production does it, reads 0
        // (measured directly). Do not "fix" this by threading a shared cache
        // into `Self.render` to make it read 0: that also makes
        // `aListsWorkIsTheSameFor160RowsAsFor40` read `0 == 0`, which would
        // pass today before windowing exists and forever after regardless of
        // whether windowing works. The cold-cache-per-frame shape is
        // load-bearing for that assertion, and this test's own instrument —
        // a per-frame call count, not a cross-frame one — is chosen to keep
        // it that way.
        #expect(counter.count <= 40)
    }

    /// **The cold frame — every `List` row built (ruling MP-I) — creates at
    /// most one line-break tokenizer**, where it created one per min-content
    /// miss: 40 on this harness before `ShapingCache.minContentWidth` re-pointed
    /// a shared one. A warm frame makes no tokenizer call at all, so the cold
    /// frame and newly revealed rows are the only places this saving exists;
    /// hence a cold render here and not a warm one.
    ///
    /// `calls == 40` proves the frame reached the min-content branch through the
    /// counted path — without it, a frame that never tokenized would read
    /// `0 <= 1`. At most one rather than zero because the tokenizer is
    /// process-wide and an earlier test may already have created it.
    @Test
    func aColdFrameCreatesAtMostOneLineBreakTokenizer() throws {
        let states = StateTable()
        let calls = Shaper.RunCallCounter()
        let creations = Shaper.RunCallCounter()
        Shaper.$runCallCounter.withValue(calls) {
            Shaper.$tokenizerCreationCounter.withValue(creations) {
                _ = Self.render({ demoLikeRows(40) }, states: states)
            }
        }
        #expect(calls.count == 40)
        #expect(creations.count <= 1)
    }

    /// Font resolution is memoized on the window's `ShapingCache`, so a warm
    /// frame over the same `Text`s reaches the uncached
    /// `FontResolver.resolve(family:size:)` **zero** times. Before the memo,
    /// `Text.requestLayout` and `Text.paint` each called it, so every `Text`
    /// the frame built paid two `CTFont` creations every frame.
    ///
    /// **One shared cache across both renders, deliberately** — the opposite of
    /// the note on `aWarmFrameTokenizesEachDistinctStringAtMostOnce` above, and
    /// for the reason that note gives: that test's instrument is per-frame and
    /// must stay so; this one is exactly the cross-frame question, and a
    /// `Window` owns one cache for its life.
    ///
    /// The cold arm reads **1**: every row asks for `(nil, 13)`, so one request
    /// is shared across all 40 rows *and* across the layout and paint phases.
    /// The `lookups` arm is the reachability control: it proves the warm frame
    /// did build and paint `Text`s, so a zero is not a frame that built none.
    @Test
    func aWarmFrameReachesTheUncachedFontResolverZeroTimes() throws {
        let states = StateTable()
        let cache = ShapingCache()

        let cold = FontResolver.CallCounter()
        FontResolver.$resolveCallCounter.withValue(cold) {
            _ = Self.render({ demoLikeRows(40) }, states: states, shapingCache: cache)
        }

        let lookupsBefore = cache.lookups
        let warm = FontResolver.CallCounter()
        FontResolver.$resolveCallCounter.withValue(warm) {
            _ = Self.render({ demoLikeRows(40) }, states: states, shapingCache: cache)
        }

        #expect(cache.lookups > lookupsBefore)
        #expect(warm.count == 0)
        #expect(cold.count == 1)
    }

    @Test
    func aListsWorkIsTheSameFor160RowsAsFor40() throws {
        let states40 = StateTable(), states160 = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states40)
        _ = Self.render({ demoLikeRows(160) }, states: states160)

        let counter40 = Shaper.RunCallCounter()
        let f40 = Shaper.$runCallCounter.withValue(counter40) {
            Self.render({ demoLikeRows(40) }, states: states40)
        }
        let calls40 = counter40.count

        let counter160 = Shaper.RunCallCounter()
        let f160 = Shaper.$runCallCounter.withValue(counter160) {
            Self.render({ demoLikeRows(160) }, states: states160)
        }
        let calls160 = counter160.count

        // Equal, not merely close: with a uniform row height the window is
        // computed by division, so the same ~13 rows are built either way and
        // the extra 120 rows cost nothing at all.
        #expect(calls160 == calls40)
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
    /// which reproduces the real mechanism on both dictionaries at once:
    /// `rowWidth` cycles so the item is genuinely re-wrapped at a changing
    /// width — `storage`'s `(string, font, width)` key changes every frame,
    /// the same way resizing a real window changes the fractional width
    /// `Text.swift`'s own measure function offers (divergence 8 measures this
    /// exact instability). The row's own text embeds the loop index, so
    /// `minContent`'s `(string, font)` key is new every frame too — the same
    /// way a scrolling list keeps presenting row numbers the cache has never
    /// seen. Neither dictionary can plateau the way `demoLikeRows` did.
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
        var lastMinContent = 0
        for i in 0..<300 {
            let w = 920.0 + Double(i) * 0.5
            let rowWidth = 80.0 + Double(i).truncatingRemainder(dividingBy: 40) * 0.5
            let frame = Self.render({
                Box { Text("Row \(i) of 4000 — a scrollable list item") }
                    .width(Pixels(Float(rowWidth)))
                    .alignItems(.stretch)
            }, size: Size(width: Pixels(Float(w)), height: Pixels(560)),
               states: states, shapingCache: cache)
            lastStorage = frame.shapingCache.storageCount
            lastMinContent = frame.shapingCache.minContentCount
        }
        // Today, with no sweep: storage climbs to 1508 and minContent
        // reaches exactly 300 — one new distinct row string per iteration,
        // never reused, never evicted.
        #expect(lastStorage <= ShapingCache.sweepThreshold)
        #expect(lastMinContent <= ShapingCache.sweepThreshold)
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
    /// frame with full text shaping (ruling MP-I). Every later task, review
    /// and fix round in this milestone would otherwise pay that on every run.
    /// Matches `regenerateAllGoldens`'s own gating shape
    /// (`Tests/MetalUILayoutTests/GeneratorTests.swift`) — an expensive
    /// deliberate act, not a per-run guard. Enable deliberately:
    ///   METALUI_RUN_100K_LIST_TEST=1 swift test --filter aListsWorkIsTheSameFor100kRowsAsFor500
    @Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_100K_LIST_TEST"] == "1"))
    func aListsWorkIsTheSameFor100kRowsAsFor500() throws {
        let states500 = StateTable(), states100k = StateTable()
        _ = Self.render({ demoLikeRows(500) }, states: states500)   // warm

        let clock = ContinuousClock()
        let coldElapsed = clock.measure {
            _ = Self.render({ demoLikeRows(100_000) }, states: states100k)   // warm — ruling MP-I's cold frame
        }
        // Step 2 of the brief: report, do not assert. Printing keeps the
        // number in `swift test`'s own output rather than in a threshold
        // this repo's own practice document says would flake on a loaded box.
        print("MeasurePerformanceTests: cold frame at 100,000 rows took \(coldElapsed)")

        let counter500 = Shaper.RunCallCounter()
        let f500 = Shaper.$runCallCounter.withValue(counter500) {
            Self.render({ demoLikeRows(500) }, states: states500)
        }
        let calls500 = counter500.count

        let counter100k = Shaper.RunCallCounter()
        let f100k = Shaper.$runCallCounter.withValue(counter100k) {
            Self.render({ demoLikeRows(100_000) }, states: states100k)
        }
        let calls100k = counter100k.count

        // Equal, not merely close — same reasoning as the 160-vs-40 test
        // above: a uniform row height means the window is found by division,
        // so the same ~13 rows are built regardless of whether the list holds
        // 500 rows or 100,000.
        #expect(calls100k == calls500)
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
        #expect(table.count == 2 * n + 5, """
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
                demoting it from a Box element to a bare legacy node.
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
                    policy that never reaps would sit at \(2 * n + 5) here, since every \
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
                .width(Pixels(420))
                .alignItems(.stretch)
            }
        }
    }
    .width(Pixels(420))
    .height(Pixels(370))
    .minHeight(Pixels(0))
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
private struct StatefulListRow: Element {
    @State var count = 0
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        count += 1
        return (pass.requestNode(style: Style(), children: []), ())
    }

    mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                           layout: inout Void, pass: inout PrepaintPass) {}

    mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        layout: inout Void, prepaint: inout Void, pass: inout PaintPass) {}
}

// MARK: - The red-before for lane 5's `.proposal` arms (`LR-BX`)

/// **`StatefulListRow`'s registration exactly as it stood at `9ad98db`**, kept as
/// a live fixture so the probe below keeps a subject after `StatefulListRow`
/// itself is re-spelled through `lowerLegacyNode` (plan task 7, stage 4, lane 5;
/// `TombstoneTests.LegacySpelledExcursionRow`'s shape, `LR-BW`).
///
/// It carries no `@State`: the probe never reads a slot, it reads a trap.
private struct LegacySpelledStatefulListRow: Element {
    var elementID: ElementID? { nil }

    mutating func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass)
        -> (LayoutNodeID, Void) {
        (pass.requestNode(style: Style(), children: []), ())
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
@Test func aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority() async {
    let run = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            var root = demoLikeRows(40)
            Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)),
                  scaleFactor: 2, stateTable: StateTable(), shapingCache: ShapingCache(),
                  theme: .dark, layoutAuthority: .proposal).render(&root)
        }
    }
    let err = String(decoding: run?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("box.minSize.unconsumed has no proposal lowering"),
            "aborted, but not at the root's own minSize:\n\(err)")
}

/// **The positive control for the probe above, and it is the lane's fix.** The
/// identical tree under the identical authority, with `reportsUnlowerableFields`
/// on, runs to completion: so the abort is the diagnostics flag and not the
/// `List`, the `ScrollView`, the `Text` or the proposal authority itself.
///
/// What the diagnostics frame then reports is asserted exactly by
/// `aListsWorkIsTheSameFor160RowsAsFor40`'s `.proposal` arm — one entry, the
/// root's own `minSize.unconsumed` — because under `reportsUnlowerableFields` a
/// site with no lowering is replaced by a 0×0 native leaf, so any OTHER entry
/// would mean the work counts beside it were taken over a partly degenerate tree.
@Test func aDiagnosticsFrameOverDemoLikeRowsRunsUnderTheProposalAuthority() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            var root = demoLikeRows(40)
            Frame(contentSize: Size(width: Pixels(920), height: Pixels(560)),
                  scaleFactor: 2, stateTable: StateTable(), shapingCache: ShapingCache(),
                  theme: .dark, layoutAuthority: .proposal,
                  reportsUnlowerableFields: true).render(&root)
        }
    }
}

/// **The second red.** `theResidentEntrySetStaysBoundedWhileScrolling10kRows`
/// builds a **production** frame of its own — `Frame(contentSize:scaleFactor:
/// stateTable:)`, which is what `Window` builds — so no diagnostics flag can help
/// it: its row must lower. Spelled `pass.requestNode(style:children:)` it hits
/// `Frame.requestNode`'s backstop (the one
/// `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` pins) and aborts.
///
/// Recorded, the assertion temporarily pointed at a string that cannot match
/// (reverted; `git status --short` clean afterwards):
///
///     MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode
///     has no proposal lowering (plan task 7, stage 6a); a tree containing it
///     cannot run under the proposal layout authority.
@Test func aLegacySpelledStatefulListRowAbortsAProductionProposalFrame() async {
    let run = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
        await MainActor.run {
            let data = (0..<50).map(MeasureRow.init)
            var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(data, rowHeight: Pixels(20)) { _ in LegacySpelledStatefulListRow() }
            }
            Frame(contentSize: Size(width: Pixels(200), height: Pixels(400)),
                  scaleFactor: 1, stateTable: StateTable(),
                  layoutAuthority: .proposal).render(&tree)
        }
    }
    let err = String(decoding: run?.standardErrorContent ?? [], as: UTF8.self)
    #expect(err.contains("customElement.requestNode has no proposal lowering"),
            "aborted, but not at the row's requestNode:\n\(err)")
}

/// **The positive control for the probe above** — `TombstoneTests`'
/// `aBoxSpelledListRowDoesNotAbortAProductionProposalFrame` in this file's own
/// fixture, kept here rather than cited, because without it the abort beside it
/// would read the same whether the row, the `List`, the `ScrollView` or the
/// production frame were the cause.
@Test func aBoxSpelledRowInTheResidentSetFixtureDoesNotAbort() async {
    await #expect(processExitsWith: .success) {
        await MainActor.run {
            let data = (0..<50).map(MeasureRow.init)
            var tree = ScrollView(.vertical, elementID: ElementID("scroller")) {
                List(data, rowHeight: Pixels(20)) { _ in Box() }
            }
            Frame(contentSize: Size(width: Pixels(200), height: Pixels(400)),
                  scaleFactor: 1, stateTable: StateTable(),
                  layoutAuthority: .proposal).render(&tree)
        }
    }
}
