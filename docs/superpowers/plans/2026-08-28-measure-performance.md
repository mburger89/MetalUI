# Measure-Path Performance and List Virtualization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the demo tree's release frame from 4.97 ms to under 8.33 ms with headroom, by memoizing the min-content width and making a list's cost proportional to visible rows rather than total rows.

**Architecture:** Two independent wins behind one committed harness. `Text.requestLayout`'s `.minContent` branch tokenizes a string and shapes every run separately on every probe; memoizing the resulting width per `(string, font)` collapses both. Separately, a new `List` element with a uniform declared row height builds only the rows intersecting the viewport, reading an ambient scroll context `ScrollView` publishes during `requestLayout`.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing, CoreText, Metal. macOS.

**Spec:** `docs/superpowers/specs/2026-08-28-measure-performance-design.md`

## Global Constraints

- **Read the test summary line, never the exit status.** `swift test --no-parallel`, unfiltered. Baseline at plan start: **577 tests**.
- **No golden may move. 81 today.** This milestone touches the measure path; a moved golden means something reached the engine that should not have — **STOP and report, do not regenerate**.
- Build warning-free, **including `MetalUIDemo`** — no test target imports it, so only `swift build` catches a broken demo.
- **Any count a later loop indexes on must be `try #require`, not `#expect`** — `#expect` records and continues, so a short array sends the next loop past its own end and truncates the suite with no summary line.
- **The harness asserts counts and complexity, never wall-clock.** Committed timing baselines are machine-specific and rot.
- **A mutation that reddens nothing is a broken instrument or it is the finding.** Prove the mutant behaves differently before banking a coverage gap.
- **Nothing may be keyed on a font family or PostScript name** (design spec §6.1/§3.2). `FontKey` identifies the resolved `CTFont`. *(Erratum 2026-09-10: it identifies the font for glyph identity, not its shaping behaviour — the UI font and `"System Font"` at one size share a key and shape non-Latin text differently; `twoRequestsWithEqualFontKeysShareOneShapeThoughTheyShapeDifferently`, pinned wrong on purpose.)*
- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored pattern.
- Comments explain mechanism, not task or milestone history.
- **Stale-incremental hazard:** adding a stored property to a public struct crossing module boundaries has produced a `SIGSEGV` with no summary line, or an assertion whose *expected* value contains something its own source could not construct. Run `swift package clean` before debugging either as a logic bug. `ScrollState` and `Scene` are both such structs.
- If a plan step conflicts with what you measure, **STOP and report** rather than working around it.

---

### Task 1: Counters and the performance harness

Lands against today's code with **all three assertions failing**. A performance test that passes on arrival has proven nothing.

**Files:**
- Modify: `Sources/MetalUIText/ShapingCache.swift` (add a lookup counter beside `hits`/`misses` at :70-71, and `storageCount`)
- Modify: `Sources/MetalUIText/UnbreakableRuns.swift` (add a call counter)
- Test: `Tests/MetalUITests/MeasurePerformanceTests.swift` (create)

**Interfaces:**
- Consumes: `ShapingCache.hits` / `.misses` (existing, `private(set)`, internal).
- Produces: `Shaper.unbreakableRunCalls: Int` and `Shaper.resetUnbreakableRunCalls()`; `ShapingCache.lookups: Int` and `ShapingCache.storageCount: Int`. All internal, always on, one `Int` increment.

- [ ] **Step 1: Add the counters**

In `Sources/MetalUIText/UnbreakableRuns.swift`, inside `enum Shaper`, above `unbreakableRuns(of:)`:

```swift
/// Counts calls to ``unbreakableRuns(of:)``. Internal and always on, at the
/// cost of one increment: the function is the single largest line item in a
/// frame, and a count is the only assertion that survives a change of
/// machine. `ShapingCache`'s own `hits`/`misses` are the precedent.
nonisolated(unsafe) static var unbreakableRunCalls = 0

static func resetUnbreakableRunCalls() { unbreakableRunCalls = 0 }
```

As the first line of the body of `unbreakableRuns(of:)`:

```swift
Self.unbreakableRunCalls += 1
```

In `Sources/MetalUIText/ShapingCache.swift`, beside `hits`/`misses`:

```swift
/// Every call to ``shaped(_:font:wrappingAt:)``, hit or miss. `hits + misses`
/// already gives this; it is named separately because the assertion that
/// matters is the *lookup* count — the per-run loop in `Text`'s min-content
/// branch drives it, and a hit is not free at 604 ns.
var lookups: Int { hits + misses }

/// Entry count, for the bound assertion. `storage` stays private.
var storageCount: Int { storage.count }
```

- [ ] **Step 2: Write the three failing assertions**

Create `Tests/MetalUITests/MeasurePerformanceTests.swift`:

```swift
import Testing
import MetalUICore
import MetalUILayout
import MetalUIText
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
                       states: StateTable) -> Frame {
        var frame = Frame(generation: 1, size: size, scaleFactor: 2, theme: .dark,
                          states: states)
        var root = content()
        frame.render(&root)
        return frame
    }

    @Test
    func aWarmFrameTokenizesEachDistinctStringAtMostOnce() throws {
        let states = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states)   // warm

        Shaper.resetUnbreakableRunCalls()
        _ = Self.render({ demoLikeRows(40) }, states: states)

        // 40 rows share no strings, so 40 distinct strings is the ceiling a
        // per-string memo allows. Today this is ~80: two min-content probes
        // per `Text`, each tokenizing in full.
        #expect(Shaper.unbreakableRunCalls <= 40)
    }

    @Test
    func aListsWorkIsTheSameFor160RowsAsFor40() throws {
        let states40 = StateTable(), states160 = StateTable()
        _ = Self.render({ demoLikeRows(40) }, states: states40)
        _ = Self.render({ demoLikeRows(160) }, states: states160)

        Shaper.resetUnbreakableRunCalls()
        let f40 = Self.render({ demoLikeRows(40) }, states: states40)
        let calls40 = Shaper.unbreakableRunCalls

        Shaper.resetUnbreakableRunCalls()
        let f160 = Self.render({ demoLikeRows(160) }, states: states160)
        let calls160 = Shaper.unbreakableRunCalls

        // Equal, not merely close: with a uniform row height the window is
        // computed by division, so the same ~13 rows are built either way and
        // the extra 120 rows cost nothing at all.
        #expect(calls160 == calls40)
        #expect(f160.scene.glyphs.count == f40.scene.glyphs.count)
    }

    @Test
    func theShapingCacheStaysUnderItsBoundAcrossAWidthSweep() throws {
        let states = StateTable()
        var last = 0
        for i in 0..<120 {
            let w = 920.0 + Double(i) * 0.5
            let frame = Self.render({ demoLikeRows(40) },
                                    size: Size(width: Pixels(Float(w)), height: Pixels(560)),
                                    states: states)
            last = frame.shapingCache.storageCount
        }
        // Today: 276 -> 739 and climbing, with no eviction path in the file.
        #expect(last <= ShapingCache.entryBound)
    }
}
```

**`demoLikeRows(_:)` and `ShapingCache.entryBound` do not exist yet.** Add the helper in this file now; `entryBound` arrives in Task 7, so until then the third test will not compile — write it commented out with a `// Task 7` marker, and uncomment it there. Say so in your report rather than silently omitting it.

```swift
@MainActor
func demoLikeRows(_ n: Int) -> some Element {
    ScrollView(.vertical) {
        for i in 0..<n {
            Box {
                Text("Row \(i + 1) of \(n) — a scrollable list item")
            }
            .height(Pixels(28))
            .alignItems(.stretch)
        }
    }
    .width(Pixels(420))
    .height(Pixels(370))
    .minHeight(Pixels(0))
}
```

- [ ] **Step 3: Run and confirm the assertions FAIL**

```
swift test --no-parallel 2>&1 | tail -3
```

Expected: the suite total rises by 2 (the third is commented out), and **both new tests FAIL**. Record the actual numbers `unbreakableRunCalls` came back with — that is the baseline every later task is measured against. If either test *passes*, stop and report: the harness is not measuring what it claims.

- [ ] **Step 4: Verify the counters are real**

Set `unbreakableRunCalls += 1` to `+= 0`. Confirm `aWarmFrameTokenizesEachDistinctStringAtMostOnce` now passes (a counter that never moves trivially satisfies a `<=`). Revert. This proves the assertion is reading the counter and not a constant.

- [ ] **Step 5: Commit**

```bash
git add Sources/MetalUIText/ShapingCache.swift Sources/MetalUIText/UnbreakableRuns.swift Tests/MetalUITests/MeasurePerformanceTests.swift
git commit -m "test: performance harness asserting counts, failing on arrival"
```

---

### Task 2: Memoize the min-content width

**Files:**
- Modify: `Sources/MetalUIText/ShapingCache.swift`
- Modify: `Sources/MetalUI/Text.swift:74-90` (the `.minContent` branch)
- Test: `Tests/MetalUITextTests/ShapingCacheTests.swift`

**Interfaces:**
- Consumes: `ShapingCache.shaped(_:font:wrappingAt:)`, `Shaper.unbreakableRuns(of:)`, `FontKey`.
- Produces: `ShapingCache.minContentWidth(_ string: String, font: ResolvedFont) -> Double`.

- [ ] **Step 1: Write the failing test**

In `Tests/MetalUITextTests/ShapingCacheTests.swift`:

```swift
@Test
func aSecondMinContentQueryTokenizesNothing() throws {
    let cache = ShapingCache()
    let font = try #require(FontResolver.resolve(.init(size: 13)))
    let s = "Row 1 of 40 — a scrollable list item"

    _ = cache.minContentWidth(s, font: font)
    Shaper.resetUnbreakableRunCalls()
    let second = cache.minContentWidth(s, font: font)

    #expect(Shaper.unbreakableRunCalls == 0)
    // The memo must return the same number it computed, not a fresh zero.
    #expect(second == cache.minContentWidth(s, font: font))
    #expect(second > 0)
}

/// Width is deliberately NOT part of the key: min-content is width-independent
/// by definition, which is exactly why §4.5 can use it as a floor. A key that
/// included width would miss on every frame of a resize and cache nothing.
@Test
func minContentIsTheLongestWordAndDoesNotVaryWithAnyWidth() throws {
    let cache = ShapingCache()
    let font = try #require(FontResolver.resolve(.init(size: 13)))
    let s = "a bb supercalifragilistic dd"

    let w = cache.minContentWidth(s, font: font)
    let longest = Shaper.unbreakableRuns(of: s)
        .map { cache.shaped($0, font: font, wrappingAt: nil).widestLine }
        .max() ?? 0
    #expect(abs(w - longest) < 0.001)
}
```

- [ ] **Step 2: Run and confirm it fails**

```
swift test --no-parallel --filter ShapingCacheTests 2>&1 | tail -3
```

Expected: compile failure — `minContentWidth` does not exist.

- [ ] **Step 3: Implement the memo**

In `ShapingCache.swift`, beside the existing `Key`:

```swift
/// **Keyed on the string and the resolved font, and deliberately NOT on any
/// width.** Min-content is width-independent by definition — that is what lets
/// CSS Sizing §4.5 use it as a floor — so folding a width in would miss on
/// every frame of a resize and cache nothing.
private struct MinContentKey: Hashable {
    var string: String
    var font: FontKey
}

private var minContent: [MinContentKey: Double] = [:]
```

And the accessor:

```swift
/// The width of the longest unbreakable run — CSS's min-content — memoized.
///
/// **Memoizing the result rather than the runs is the point.** Caching
/// `Shaper.unbreakableRuns` alone removes the tokenizer walk and leaves the
/// per-run shaping lookups behind; measured, that is ~0.79 ms of a 4.97 ms
/// frame still on the table. Storing the width collapses the tokenizer walk
/// and the whole loop into one dictionary hit.
public func minContentWidth(_ string: String, font: ResolvedFont) -> Double {
    let key = MinContentKey(string: string, font: font.key)
    if let cached = minContent[key] { return cached }
    var width = 0.0
    for run in Shaper.unbreakableRuns(of: string) {
        width = max(width, shaped(run, font: font, wrappingAt: nil).widestLine)
    }
    minContent[key] = width
    return width
}
```

Check `ResolvedFont`'s key accessor is spelled `.key` before writing it; if it differs, use the real spelling and say so in your report.

- [ ] **Step 4: Call it from `Text`**

Replace the loop in `Sources/MetalUI/Text.swift`'s `.minContent` branch:

```swift
case .minContent:
    // The widest unbreakable run, memoized per (string, font). `Shaper`
    // character-breaks a word it cannot fit, so `shape(wrappingAt: tiny)`
    // answers "the widest character" (11.489) where §4.5 needs "the longest
    // word" (110.348) — hence runs rather than a narrow typeset.
    let minContent = cache.minContentWidth(string, font: font)
    wrapWidth = max(minContent, smallestWrapWidth)
    reportedWidth = minContent
```

**The comment being replaced is why this defect survived** — it argued correctly that the runs are cache-shared between frames and "a second frame adds no misses", which is true of the shaping and silently not true of the tokenizer walk above it. Do not carry that sentence forward.

- [ ] **Step 5: Run the full suite and the harness**

```
swift test --no-parallel 2>&1 | tail -3
```

Expected: `aWarmFrameTokenizesEachDistinctStringAtMostOnce` now **passes**. Every existing text test still passes — the memo must not change any measured width. **No golden moved.**

- [ ] **Step 6: Mutate**

Delete the `if let cached` line. Confirm `aSecondMinContentQueryTokenizesNothing` and the harness test both redden. Revert; confirm `git diff --stat Sources/` is empty.

- [ ] **Step 7: Re-measure and record**

Time a warm frame over `demoLikeRows(40)` in release, before and after this task, with a throwaway harness you then delete. Record both numbers and the ratio in your report. The prediction is 4.97 → ~1.8 ms; **report what you measure, not the prediction.**

- [ ] **Step 8: Commit**

```bash
git add Sources/MetalUIText/ShapingCache.swift Sources/MetalUI/Text.swift Tests/MetalUITextTests/ShapingCacheTests.swift
git commit -m "perf: memoize min-content width per (string, font)"
```

---

### Task 3: Re-measure the probe count and rule on it

**No code is guaranteed by this task.** Its deliverable is a measurement and a recorded ruling.

**Files:**
- Modify: `docs/superpowers/2026-08-28-measure-performance-decisions.md` (create; rulings `MP-` prefixed and **lettered**, `MP-A`…)

- [ ] **Step 1: Measure the probe count after Task 2**

With a throwaway harness: how many `textMeasure(.minContent)` calls per `Text` per frame, and what does one now cost? Before Task 2 it was 2.02 probes at 30,660 ns. Report both.

- [ ] **Step 2: Rule**

Design spec §8 says this fix's value falls ~98% once a probe is one dictionary hit, and that changing what the engine measures puts 81 goldens downstream of the change.

Write ruling `MP-A` either way, with its reasoning **and what it costs if wrong**. If the remaining cost is under ~5% of the frame, rule it **out of scope** and say so plainly — a milestone that declines work on measurement is doing its job.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/2026-08-28-measure-performance-decisions.md
git commit -m "docs: rule on the min-content probe count (MP-A)"
```

---

### Task 4: `List` with a uniform row height and data identity — not yet windowed

Builds every row. Windowing is Task 6. Splitting them means a reviewer can reject the element's shape without reasoning about the offset plumbing.

**Files:**
- Create: `Sources/MetalUI/List.swift`
- Test: `Tests/MetalUITests/ListTests.swift`

**Interfaces:**
- Consumes: `Element`, `ElementGroup`, `LayoutPass.requestNode(style:children:)`, `GlobalElementID`, `ElementID`.
- Produces: `List<Data: RandomAccessCollection, Row: Element>` where `Data.Element: Identifiable`, `init(_ data: Data, rowHeight: Pixels, @ElementBuilder row: @escaping (Data.Element) -> Row)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func aListSizesItselfToCountTimesRowHeight() throws {
    // 10 rows x 28 = 280, regardless of what any row measures.
    let frame = render { List(items(10), rowHeight: Pixels(28)) { Row($0) } }
    #expect(frame.bounds(ofRoot:).size.height == Pixels(280))
}

/// Identity comes from the DATA, not from position — the property windowing
/// depends on. A row that moves position keeps its state; under positional
/// identity it would adopt its new neighbour's.
@Test
func aRowKeepsItsIdentityWhenItsPositionChanges() throws {
    let a = render { List(items(3), rowHeight: Pixels(28)) { Row($0) } }
    let b = render { List(items(3).reversed(), rowHeight: Pixels(28)) { Row($0) } }
    #expect(a.id(ofRowWith: "item-0") == b.id(ofRowWith: "item-0"))
}
```

Write the real `render`/`items`/`Row` helpers concretely against `Frame`'s actual API — read `Tests/MetalUITests/DeferredTests.swift` for the established idiom rather than inventing one. If `Frame` exposes no way to recover a child's `GlobalElementID`, the second test must find another observable — a `ScrollView`'s registered region id is the technique `DeferredTests` uses. **Do not add a production accessor purely for a test without saying so.**

- [ ] **Step 2: Run and confirm they fail**

Expected: compile failure — `List` does not exist.

- [ ] **Step 3: Implement `List`**

```swift
/// A vertically stacked, uniformly sized sequence of rows built from data.
///
/// **Rows take identity from the data, and that is forced rather than
/// preferred.** Identity in this framework is structural: `.positional(Int)`
/// components are assigned by the cursor walking the built children. Once
/// Task 6 builds only the visible window, a row that scrolls out and back
/// lands on a different position — so a positionally-identified row would
/// adopt a neighbour's state, which is the vanishing-`if` hazard made routine.
/// `Data.Element: Identifiable` is what stops that.
///
/// **A uniform `rowHeight` is what makes windowing O(visible).** The window is
/// computed by division, with no row laid out to find it. Variable heights need
/// a prefix-sum index and are out of scope.
public struct List<Data: RandomAccessCollection, Row: Element>: Element
where Data.Element: Identifiable {
    ...
}
```

Fill the body against the real `Element` protocol. `requestLayout` builds one child per datum, each named `.named(ElementID(String(describing: datum.id)))`, in a column whose height is `Pixels(Float(data.count)) * rowHeight`.

- [ ] **Step 4: Run and confirm they pass, full suite**

**No golden moved.**

- [ ] **Step 5: Mutate**

Change the row's identity from `.named(...)` to positional. Confirm `aRowKeepsItsIdentityWhenItsPositionChanges` reddens. Revert.

- [ ] **Step 6: Commit**

```bash
git add Sources/MetalUI/List.swift Tests/MetalUITests/ListTests.swift
git commit -m "feat: List with uniform row height and data identity"
```

---

### Task 5: `ScrollView` publishes an ambient scroll context — pin routing first

**Files:**
- Modify: `Sources/MetalUI/ScrollView.swift` (`ScrollState`, `requestLayout` at :184, `prepaint` at :215)
- Modify: `Sources/MetalUI/Passes.swift` (`LayoutPass`)
- Test: `Tests/MetalUITests/ScrollRoutingTests.swift`, `Tests/MetalUITests/ScrollLayoutTests.swift`

**Interfaces:**
- Consumes: `LayoutPass.withState` (`Passes.swift:355`), `ScrollState`.
- Produces: `ScrollState.viewportExtent: Double`; `LayoutPass.scrollContext: (offset: Double, viewportExtent: Double, axis: ScrollAxis)?` and `LayoutPass.withScrollContext(_:_:)`.

- [ ] **Step 1: Pin today's routing behaviour BEFORE changing anything**

The clipping milestone shipped two intermittent scroll defects only a human found — an offset clamped on read and unbounded on write that banked 740 of invisible dead band. Add tests for whatever is not already pinned: that the stored offset is clamped and written back in prepaint, and that overscroll does not bank.

Run them. They must **pass** on today's code — these are a safety net, not a TDD step. If one fails now, **STOP and report**: that is a pre-existing defect, not something this task introduced.

- [ ] **Step 2: Write the failing test for the ambient context**

```swift
/// The offset is CURRENT during requestLayout; the viewport extent is one
/// frame stale. `Window.applyScroll` writes the offset before requesting the
/// redraw, so a scroll is visible to the phase that builds the tree — but the
/// viewport is pure layout output and can only be had by storing it last frame.
@Test
func scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout() throws {
    // Render once so a viewport extent is stored, scroll, then render again
    // and assert what a descendant would read during requestLayout.
}
```

- [ ] **Step 3: Run and confirm it fails**

- [ ] **Step 4: Add `viewportExtent` to `ScrollState`, written in prepaint**

`ScrollState` is public and crosses a module boundary — **if the suite crashes or truncates with no summary line after this step, run `swift package clean` before debugging it as a logic bug.**

- [ ] **Step 5: Publish the context in `requestLayout`**

Read the raw stored offset with `pass.withState`, pair it with the stored `viewportExtent`, and push it around the `content.requestGroupLayout` call in the shape of the existing clip stack — pushed before, popped after, via `defer`.

**Do not attempt to resolve or clamp the offset here.** `resolvedOffset` (`:378`) clamps against `extent(bounds.size)` and the content node's laid-out size, neither of which exists yet; the clamp is why that function lives in prepaint. The consumer clamps, because `List` knows its own content extent exactly.

- [ ] **Step 6: Run the full suite**

Every existing scroll test must still pass, including Step 1's. **No golden moved.**

- [ ] **Step 7: Mutate**

Drop the `defer` that pops the context. Confirm something reddens — a sibling after a `ScrollView` must not inherit its scroll context. If nothing reddens, that is the finding: add the test.

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: ScrollView publishes an ambient scroll context in requestLayout"
```

---

### Task 6: Windowing and overscan

**Files:**
- Modify: `Sources/MetalUI/List.swift`
- Test: `Tests/MetalUITests/ListTests.swift`, `Tests/MetalUITests/MeasurePerformanceTests.swift`

**Interfaces:**
- Consumes: `LayoutPass.scrollContext` from Task 5.

- [ ] **Step 1: Write the failing tests**

```swift
@Test
func aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan() throws { ... }

/// The list's own height must stay count x rowHeight even though only a
/// window is built — otherwise the scrollbar and the offset clamp are wrong.
@Test
func aWindowedListStillReportsItsFullContentHeight() throws { ... }

/// A row scrolled past keeps its position, so the window is placed rather
/// than merely sized: row 50 sits at 50 x rowHeight, not at the window's top.
@Test
func aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop() throws { ... }
```

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement windowing**

Clamp the ambient offset against this list's own exact content extent (`count * rowHeight`), derive `first = floor(offset / rowHeight) - overscan` and `last = ceil((offset + viewportExtent) / rowHeight) + overscan`, clamp both into `0..<count`, and build only that slice — each row still named from its datum's id, and positioned at its absolute offset.

With no ambient context (a `List` outside a `ScrollView`), build everything: a list nobody scrolls must still render.

- [ ] **Step 4: Run, and uncomment the harness's third assertion's sibling**

`aListsWorkIsTheSameFor160RowsAsFor40` must now **pass** with `demoLikeRows` switched to use `List`. Update that helper in the same step and say so.

- [ ] **Step 5: Mutate**

Set overscan to 0 and confirm a partially-scrolled edge test reddens. Then build the full range instead of the window and confirm the harness test reddens. Revert both.

- [ ] **Step 6: Commit**

```bash
git commit -m "feat: List builds only the rows intersecting the viewport"
```

---

### Task 7: Bound both caches with a generation sweep

**Files:**
- Modify: `Sources/MetalUIText/ShapingCache.swift`
- Modify: `Sources/MetalUI/Frame.swift` (the existing frame brackets)
- Test: `Tests/MetalUITextTests/ShapingCacheTests.swift`, `Tests/MetalUITests/MeasurePerformanceTests.swift`

**Interfaces:**
- Produces: `ShapingCache.entryBound: Int` (static), `ShapingCache.beginFrame()` / `endFrame()`.

- [ ] **Step 1: Uncomment the harness's third assertion**

`theShapingCacheStaysUnderItsBoundAcrossAWidthSweep`, held from Task 1. Run it: it must **fail**.

- [ ] **Step 2: Write the eviction tests**

```swift
@Test
func anEntryUntouchedForAFrameIsDropped() throws { ... }

/// The bound must not evict something this frame still needs — that is the
/// atlas's recorded trap in a new place: `GlyphAtlas.evictUnusedSince` has zero
/// callers precisely because freeing an entry there strands its pixels and
/// makes the next frame pack a second copy. A sweep that drops a live entry
/// costs a re-shape every frame forever, which is slower than never evicting.
@Test
func aSweepNeverDropsAnEntryTheCurrentFrameTouched() throws { ... }
```

- [ ] **Step 3: Implement mark-on-use and sweep**

Mark an entry's generation on every hit and insert; on `endFrame`, drop entries untouched for N generations, only when over `entryBound`. Bracket from `Frame.render`, which already has `beginFrame`/`endFrame` around the paint phase for the atlas.

- [ ] **Step 4: Run the full suite**

**No golden moved.**

- [ ] **Step 5: Mutate**

Remove the sweep call. Confirm the bound assertion reddens. Then make the sweep drop entries touched this frame; confirm the second eviction test reddens. Revert both.

- [ ] **Step 6: Commit**

```bash
git commit -m "perf: bound the shaping caches with a generation sweep"
```

---

### Task 8: Demo, documentation, human verification

**Files:**
- Modify: `Sources/MetalUIDemo/main.swift` (rows become a `List`)
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/2026-08-28-measure-performance-decisions.md`

- [ ] **Step 1: Switch the demo's 40 rows to `List`**

Then bump it to a count that would have been unusable before — 500 — and confirm by measurement that the frame cost is unchanged from 40.

- [ ] **Step 2: Re-measure and record every number**

Release frame for the demo tree, before and after the milestone; the machine named; suite count from the **summary line**; golden count. **Re-measure rather than copying any number from this plan.**

- [ ] **Step 3: Update `CLAUDE.md`**

The layout-cost section's `~40 us per node in debug and ~5.3 us in release` predates this work and the measure path is exactly what changed — correct it or date it. Add `List` to the container discussion (`Row`, `Column`, `Stack` are described as the three containers; `List` is not a fourth container but a windowed sequence — say which). Record the two limitations as divergences at the **next free labels**: `List` rows losing element state when scrolled out, and the one-frame-stale viewport extent. **Labels 1-6 and 8-11 exist; 7 is permanently unused and must stay unused, so the next free label is 12.**

- [ ] **Step 4: Rulings**

Complete `docs/superpowers/2026-08-28-measure-performance-decisions.md` — `MP-` prefixed, **lettered**, each with reasoning **and what it costs if wrong**.

- [ ] **Step 5: Human verification**

Build and confirm the demo launches. **Do not describe how it looks or claim the criterion is closed** — a launch is a smoke check, not a look. Write the record so the criterion reads as **open**, naming what a human must do: run the demo in **both debug and release**, drag the window edge, and report whether the stutter is gone.

- [ ] **Step 6: Commit**

```bash
git commit -m "docs: record the measure-performance milestone"
```

---

## Self-Review

**Spec coverage.** §4 harness → Task 1. §5 memo → Task 2. §6 bounds → Task 7. §7.1-7.3 `List` → Task 4. §7.4 ambient context → Task 5. §7.5 state limitation → Task 8 Step 3. §8 contingent probe fix → Task 3. §9 exit criteria → Tasks 2, 6, 8. §10 divergences → Task 8 Step 3.

**Known gap, stated rather than hidden.** Tasks 4, 5 and 6 give test *names* and intent but not complete bodies, because they depend on `Frame`'s real test idiom and on `Element`'s exact protocol requirements, which the implementer must read rather than have transcribed from memory. Every such step says which existing file to copy the idiom from. This is a deliberate trade against this plan's own "no placeholders" rule: two API signatures written from memory on the previous milestone were both wrong, and a confidently wrong signature costs more than an explicit instruction to go read one.

**Type consistency.** `unbreakableRunCalls` / `resetUnbreakableRunCalls()` (Task 1) used in Tasks 1, 2. `minContentWidth(_:font:)` (Task 2) used in Task 2 Step 4. `entryBound`, `beginFrame`, `endFrame` (Task 7) used in Task 1's held-back assertion. `scrollContext` (Task 5) used in Task 6. `demoLikeRows(_:)` (Task 1) updated in Task 6 Step 4.
