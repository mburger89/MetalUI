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
    /// toward `n + 2` once it has fallen: entries leave storage only through
    /// `sweep()`'s reap, and this scroll never introduces an id `sweep()` has
    /// not already seen. A policy that never reaps (the pre-tombstone
    /// `sweep()`, or a reap with the size gate deleted the wrong way) would
    /// leave `table.count` at exactly `n + 2` forever, since nothing would
    /// ever remove an entry; this test's bound (`n / 10`, an order of
    /// magnitude above the ~20-41 entries steady scrolling actually leaves
    /// resident — shifted by the +1 this task's own `$ax` retention slot
    /// adds, confirmed flat regardless of scroll parameters by a differential
    /// probe rather than re-derived from the original harness, which this
    /// range's own comment does not preserve) is loose enough to hold under
    /// any working reap policy and tight enough to fail hard under a reap
    /// that does not run at all.
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
        #expect(table.count == n + 2, """
                the cold frame must build every row plus the scroller's own \
                ScrollState entry plus the List's own $ax retention slot — Task 7 made \
                a List unconditionally emit ITS OWN AXNode (role .container, carrying \
                logicalCount) so spec §9's exit criterion 4 holds regardless of whether \
                a caller declared one, and Frame.emitAXNode retains a durable copy of \
                every emission under a distinct \"$ax\" child slot (Task 6) — one more \
                entry than before Task 7, for exactly one List, not per row
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
                    policy that never reaps would sit at \(n + 2) here, since every \
                    jump only re-marks entries the cold frame already created.
                    """)
        }
    }
}

// `ScrollView` conforms to `Element`, not `StyledElement` (CLAUDE.md's
// declared-but-inert table), so `.width`/`.height`/`.minHeight` land on a
// wrapping `Box` — the same shape `Sources/MetalUIDemo/main.swift` uses for
// its own list. This builds through `List`, matching the demo's own
// row shape (`DemoRow` mirrors the identity a real caller's data would carry;
// `List` requires `Data.Element: Identifiable` and a bare `Range<Int>`'s
// `Int` does not conform).
//
// Each row's `.width(Pixels(420))` is pinned, matching the demo's own row
// closure (search `main.swift` for `.width(Pixels(420))`, which appears on
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
