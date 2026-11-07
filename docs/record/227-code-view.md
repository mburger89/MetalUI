# Record 227: the read-only code view (Alloy gap G1, PR 2)

PR 2 of Alloy gap G1, in two runs on branch `feat/code-view` (master `b3c60d27`, which has `MetalUICodeBuffer`, record 225). Run 1 built the view, the cache, the decorations and the pins (sections 1-6); run 2 added read-only virtual rows, scroll sync, the reveal pin, the accessibility node, the allocation cuts, the demo and the docs (section 7). Rulings `CV-J`..`CV-R` (run 1) and `CV-S`..`CV-V` (run 2, plus the `CV-R` amendment) in `docs/superpowers/2026-11-07-code-view-decisions.md` (next `CV-W`). Class `M`; no divergence added or retired. Record 226 is another line in flight (continuous corners), so this took 227.

## 1. What was built

`CodeView(buffer:decorations:)` (a `StyledElement` leaf, `Sources/MetalUI/Code/CodeView.swift`) with `font(family:size:)`, `showsLineNumbers(_:)` and `tabWidth(_:)`; `CodeDecorations` and its value types (`CodeDecorations.swift`: `CodeStyleID`, `CodeStyle`, `CodeStyleRun`, `CodeLineDecoration`, `CodeHighlightLayer` with `.annotations`, `CodeTheme`, `CodeHighlightProvider`); the internal pieces `RunTree.swift` (a treap of runs addressed by running extent, the "SumTree" of the plan), `CodeLineLayout.swift` (the two-frame cache, the key, the line builder with tab expansion and long-line windows) and `CodeViewPlan.swift` (state, the row map, the per-frame plan, geometry, hit testing, selection units, paint). Shared pieces changed: `ScrollChrome.paintIndicator(bounds:offset:content:viewport:lastScroll:pass:)` (numeric overload; the old method forwards) and `ScrollChrome.wheelOffset` (the `TextEditor` arm in `dispatchScrollChain` now calls it), `LifecycleStore.enqueue`, `CodeViewLeafKey` in `LayoutLeafKeys.swift`, `Frame.codeWork` and four `FrameWork` counters, and `Rope`'s chunk scans in `MetalUICodeBuffer` (`CV-R`). Tests: `Tests/MetalUITestingTests/CodeViewTests.swift` (portable: macOS, Linux, Windows).

## 2. Deviations from the plan

- **No `dispatchScrollChain` arm.** The plan had the editor arm become two-axis for a code target; the view instead registers the existing pointer attachment's `scrollWheel` handler, which the chain already runs innermost first, so `Handlers` stays at 488 bytes and `Window` gains nothing. The shared arithmetic is `ScrollChrome.wheelOffset` (per-axis clamp), which the `TextEditor` arm now also calls.
- **`SumTree` is a treap of runs (`RunTree`)**, not a B-tree: split and merge by running extent give the O(log n) splice the decorations need in about 150 lines, and one generic class serves both the byte-keyed highlight layers and the row-keyed line decorations. Expected O(log n), deterministic priorities.
- **Lowering site `.textEditor`** (no new `LoweringSite`): the diagnostics tables enumerate sites by hand (305 entries), and the leaf lowers exactly as the editor does.
- **The anchor maps with `bias: .before`**, so text inserted exactly at the anchor (a prepend at the top of a view scrolled to the top) stays in view; lines inserted strictly above shift it.
- **Allocation pin is a bound, not an equality.** Rope depth differs between 1k and 100k lines (2 against 3 levels), which costs a few allocations per visible row (`CV-R` removed the per-byte one); the pin is "within 20 per visible row" at the same position and "no growth with position" (`TODO(run 2)`: record the measured numbers in section 3).
- `codeViewEditable` and `indentUsingSpaces` are not declared (editing run): an unread property would be a declared-but-inert row.
- A first `.annotations`-under-syntax pin by scene `order` was impossible (`order` is a layer index, 0 here); a scene draws its rects before its glyphs, so a background rect is under the text by construction, and the pin states the rect's row and the glyph colour.

## 3. Numbers

Harness window 400 x 200 at 1x, Noto Sans 12 (pitch 17, 12 rows visible), macOS arm64 debug.

| Measure | 1k lines | 100k lines |
| --- | --- | --- |
| Lines shaped on open | 13 (12 visible + 1 overscan) | 13 |
| Rows painted on open | 12 | 12 |
| Lines shaped by a one-row scroll | 1 | 1 |
| Lines shaped by a warm frame | 0 | 0 |
| Allocations, one warm 1 px scroll frame, line numbers off, top (run 1) | 4380 | 4522 |
| Allocations, same, 600 rows down (run 1) | 5040 | 5077 |
| **Allocations, same, top (run 2)** | **764** | **764** |
| **Allocations, same, 600 rows down (run 2)** | **777** | **778** |
| Allocations, same, 90 000 rows down (run 2) | - | 750 |
| Allocations, line numbers on, top (run 2) | 825 | - |

The same-position difference in run 1 (142 and 37) was the rope's extra level; run 2's rope scans no longer allocate per element, so the two sizes agree (0 and 1) and the pin is tightened to 2 per visible row (section 7.4). Before `CV-R` the same frames allocated 7739 / 7881 at the top and 10821 / 18362 at 600 rows (one allocation per byte scanned by `Rope.lineStart`). A 20 KB line is shaped as one window: under 4000 bytes shaped on open, none for a 20 pt horizontal scroll. One edited line re-shapes one line (`aKeystrokeInTheBufferRelaysOutNothing`: 0 layout measure calls, 0 memo misses).

## 4. Mutations

Each applied alone to the committed tree in place and restored with `git checkout` (script and log in the session scratchpad); the whole `CodeViewTests` run per mutation.

| Mutation | Reddened |
| --- | --- |
| the cache key without the foreground digest | `aHighlightThatSplitsACachedLineRecoloursExactlyItsGlyphs` |
| the key without the scale | `aScaleChangeShapesTheVisibleLinesAgain` |
| pitch rounded up, not to nearest | `rowsAreWholeDevicePixelsAtAFractionalScale` |
| visible count floors | `openingShapesOnlyTheVisibleRows`, the allocation pin |
| no overscan below | `openingShapesOnlyTheVisibleRows` |
| row loop over every row (3000, the naive spelling) | `openingShapesOnlyTheVisibleRows`, `theOpenCostIsTheSameAt1kAnd100kLines`, `scrollingOneRowShapesOneLine`, `theLineCacheKeepsOnlyTwoFramesOfLines`, the allocation pin |
| horizontal clamp ignores measured widths | `theWheelScrollsBothAxesAndTheClampCountsMeasuredWidth` |
| tab stop from the glyph count | `tabsStopOnMultiplesOfTheSpaceAdvance` |
| line decorations not shifted | `lineDecorationsShiftInLogarithmicWork` |
| the leaf key reads `buffer.version` | `aKeystrokeInTheBufferRelaysOutNothing` |
| copy handler returns nothing | `draggingSelectsAndCopyWritesTheSelection` |
| anchor kept as a row number | `linesInsertedAboveKeepTheTopRowInPlace` |
| provider dedupe removed | first spelling reddened nothing (the test's provider answered synchronously, a broken instrument); `theProvidersAnswerIsInTheFrameThatAskedAndAnUnansweredAskIsNotRepeated` added with an unanswered provider, then red |
| provider called from prepaint, not queued | likewise green at first (the phase-time write still showed in later frames); the same new test reddens it on the open frame's build count (Apple platforms) |
| reveal does not centre | `revealCentresTheSelectionsLine` |
| long lines shaped whole | `aLongLineIsShapedInAWindow` |
| cache never rotates | `theLineCacheKeepsOnlyTwoFramesOfLines` |
| decorations do not follow the buffer | `anEditKeepsTheOldColoursAndAsksAgain`, `lineDecorationsShiftInLogarithmicWork` |
| `makePlan` copies the text each frame | the allocation pin |

Findings from the first runs: a dedupe test needs an unanswered provider; a blank line repeated in a fixture is one cache entry (fixtures keep lines distinct); a scene's `order` is a layer index, not a sequence; the tab test's first text ("ab") was wider than a stop in a proportional face; a view scrolled to the top and text prepended at its anchor needs `bias: .before`; `Rope.lineStart` allocated per byte.

## 5. Results

`swift package clean`, `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel`, unfiltered: `Test run with 5452 tests in 18 suites passed after 379.329 seconds.` and `FR-J no-argument frame: succeeded=true deprecations=2` (an earlier run of the same tree failed only `everyFrameChannelIsClassified`, fixed by classifying `Frame.codeWork` as `.buildOnly`). `zsh docs/probes/closeout-inventory-check.sh`, `closeout-undocumented.sh` and `record-05-check.sh` print nothing. `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_CODE_CACHE=1` over `CodeViewTests` both pass (26 tests; the allocation pin is skipped under them).

## 6. Linux (portable container)

`metalui-portable:db5aebc23d28`, fed by `git archive HEAD`: `swift build --build-tests` and `swift test --skip-build --no-parallel` pass: 859 tests in 10 suites (`MetalUITestingTests`, with the 26 `CodeViewTests`) and 9, 16, 73, 68, 49, 286, 154, 24 and 45 in the others. Off Apple the observation hop is asynchronous (`HT-I`), so the provider's same-frame pin runs on Apple only and the rest waits with `runUntilIdle`; the observation tests (`aBufferEditRedrawsTheWindowByObservation`) pass there. No stop condition arose.

## 7. Run 2: virtual rows, scroll sync, reveal, accessibility, allocations, demo

### 7.1 What was added

- **Virtual rows** (`CV-S`): `CodeVirtualRow` (anchor `.before(line:)`/`.after(line:)`, `lines`, per-line `styleRuns`, `gutterBar`, `background`, `gutterMarker: CodeGutterMarker?`, `CodeVirtualRow.filler(_:at:background:gutterBar:)`), `CodeDecorations.setVirtualRows(_:asOf:)`, `virtualLineCount`. `CodeRowMap` (`CodeRowMap.swift`) is a treap over gaps; geometry, anchor, reveal, extent and hit testing all go through `row(atDisplay:)` and `displayRow(ofBufferRow:)`. The scroll anchor is still a buffer row plus device pixels, negative when the view's top is inside the virtual lines before it; a fresh view starts at display row 0 (a first draft started at the first buffer row and scrolled the first virtual lines off, found by the accessibility test).
- **Scroll sync** (`CV-T`): `CodeScrollPosition(row:x:)`, `CodeScrollState` (`@Observable`, `position`), `CodeView.scrollState(_:)`, `CodeView.onScroll(_:)`. Display rows plus a fraction, not pixels (two views of one diff have the same display rows at any font size or scale; the filler makes them equal); horizontal in points. A report is queued with `LifecycleStore.enqueue` and runs after the build, outside every phase; an assignment bumps a revision the view observes, is adopted before the frame's wheel travel and is published back silently, so there is no echo and no redraw loop.
- **Reveal** (`CV-V`): `select(_:reveal: true)` centres the head's display row in every view of the buffer (top = row * pitch - (height - pitch) / 2, clamped). It was already implemented in run 1 for one view; run 2 pins it for two views of one buffer and through virtual rows, and documents the anchor.
- **Accessibility** (`CV-U`): one `.textArea` node, value = the visible rows' text (virtual lines included) capped at 64 KB, built only while `Frame.collectsAccessibility`.
- **Demo** `METALUI_CODE_DEMO=1` (`CodeViewDemo.swift`): a generated 100 000-line file, a provider colouring only the rows asked for, author bars, green diff tints, 200 groups of three red removed rows as virtual rows, a second narrow view synced through `onScroll`, buttons for Top, Line 50 000 (reveal) and Insert a line at the top. Built in `everyProductionTreeBuildsOnAOneMegabyteThread` by `buildTheCodeViewDemo()` (`@inline(never)`, over `CodeViewDemoModel(bare:)`: the generated file's initialiser runs main-actor closures, which trap their dynamic isolation check off the main thread; `CodeBuffer.init` and `CodeDecorations.init` therefore build with `nonisolated` helpers and loops, found by a SIGTRAP in `everyProductionTreeBuildsOnAOneMegabyteThread`); `CodeViewDemoTests` (macOS) builds the real model.
- **Tests** (`CodeViewVirtualRowsTests`, 14, portable; `CodeRowMapTests`, 2, macOS, a seeded model of 60 builds and 12 splices each; `CodeViewCoreTextTests`, macOS, 2 cases: the CoreText text system at 2x; `CodeViewDemoTests`, macOS). No guide: `GuideDocCheck` mirrors need compiled copies in `MetalUITestingTests` and the doc comments plus `docs/api-overview.md` carry the reference.

### 7.2 Counted work

| Measure | Value |
| --- | --- |
| Open, 100 000 lines, 10 000 virtual groups (20 000 virtual lines) | painted = visible rows; shaped at most visible + 1 (the same as with none) |
| One-row scroll with 20 000 virtual lines | at most 2 lines shaped |
| One newline above 100 / 10 000 groups, `RunTreeStats.nodesVisited` | 45 / 57 (difference 12; the pin: difference at most 60, and under 400) |
| `CodeRowMap.splice` above 10 000 groups in 30 000 rows | pinned under 200 nodes (the count itself was not recorded) |
| Debug build, headless, indicative only (never pinned): 5.6 MB, 100 001 lines | `CodeBuffer(utf8:)` 74 ms; window + first frame 12 ms; a warm frame 0.9 ms |

### 7.3 Allocations of one warm scroll frame: where they were

Run 1 measured about 4400 for 12 rows (5000 at 600 rows down). A `malloc_logger` that recorded the backtrace of each allocation on the test thread (a scratch instrument, not kept) and aggregated by the first MetalUI frame split them. **The view's own share was small and the rest was the debug build**: every `for x in array`, `for i in 0..<n`, `.enumerated()`, `.last`, `.contains` and `reduce` calls a protocol witness that allocates a coroutine frame once per element, because `-Onone` does not specialise the stdlib generics. A release build specialises them away, so this pin is a debug-build pin; the instrument counts what the debug build does. Same frame, top of a 1k-line file, line numbers off:

| Share | Before | After |
| --- | --- | --- |
| An empty view's frame (window, frame, state sweep, accessibility build, hit tests) | 157 | 157 |
| `Frame.activeClip`/`activeClipRadii`/`activeOffset` reads, once per glyph (`.last`) | 1248 | 0 |
| `Scene.finalize` (fill loops, run merge `.last`, sort of the primitives) | 1191 | 403 (the sort; scales with glyphs on screen) |
| `paintContent` loops (`for`, `enumerated`, `filter`, colour array per row) | 635 + 196 + 182 + 26 + 42 | 0 |
| `codeHash` (a `for` over every byte of every visible row) | 196 | 0 |
| `CodeDecorations.stylingOfLine` (tree walk, `Set`, `sorted` per row) | 756 + 56 + 98 | 14 |
| Rope scans (`lineStart`, `byte(at:)`, `forEachSlice`) | 56 + 54 + 54 + 30 | 0 |
| everything else (accessibility text of the visible rows 13, glyph atlas 19, `Scene.insert` 23, `utf8(in:)` 14, hit tests 39, ...) | | about 170 |
| **Total** | **4380** | **764** |

At 600 rows down 777 / 778 (1k / 100k), at 90 000 rows 750, line numbers on 825. The view's own share is now about 600 less the sort (about 200 of the 764 are the view: its rows' arrays, the layout keys, the accessibility text); the rest is the frame and `Scene.finalize`'s sort, whose generic tuple comparison allocates and which is left as a candidate for the scene's owner (`MetalUIScene`, shared with the shader work in flight). Pin (`aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition`): the two sizes agree within 2 per visible row at one position (0 and 1 measured), 90 000 rows down within 4 per visible row of 600 down (28 measured), every cell under 830. Edits outside the view: `Frame.swift` (four accessors and `spriteGlyph`), `Scene.finalize`, `Rope` scans; none changes a result, all are loop spellings (`CV-R`).

### 7.4 Mutations

Each applied alone to the committed tree in place, restored with `git checkout`, the reddening filter run (script and log in the session scratchpad). **Reddened tests are named, not counted.**

| Mutation | Reddened |
| --- | --- |
| `displayRow(ofBufferRow:)` ignores the gaps (returns the row) | `scrollingAndRevealGoThroughTheRowMap`, `theRowMapMatchesAnArrayModelUnderRandomBuildsAndSplices`, `aSpliceAboveTenThousandGroupsVisitsFewNodes` |
| the edit does not splice the row map (`apply(_:)`) | `anEditAboveKeepsVirtualRowsWithTheirRowAndTheReaderInPlace` |
| `splice` walks every node first | `aNewlineAboveManyVirtualRowsShiftsThemInLogarithmicWork`, `aSpliceAboveTenThousandGroupsVisitsFewNodes` |
| `setVirtualRows` ignores `asOf` (the replay loop off) | `virtualRowsGivenForAnOlderVersionAreMappedForward` |
| a gap at the edit's row moves with the new rows (`<` for `<=` in the split) | `theRowMapMatchesAnArrayModelUnderRandomBuildsAndSplices` only |
| gaps strictly inside removed rows are kept | `theRowMapMatchesAnArrayModelUnderRandomBuildsAndSplices` |
| a virtual line's hit range is 5 bytes of the next row | `aVirtualRowCannotBeSelected` |
| row loop over every display row | `openingShapesOnlyTheVisibleRows`, `openingWithTenThousandVirtualGroupsShapesOnlyTheVisibleRows` |
| an adopted position is reported (`silent` false) | `theScrollPositionIsObservableAndSettable`, `twoViewsSyncedThroughOnScrollShowNoFeedbackLoop` |
| an assigned position is never adopted | `theScrollPositionIsObservableAndSettable`, `twoViewsSyncedThroughOnScrollShowNoFeedbackLoop`, `aSyncedPositionIsInDisplayRowsSoFillerKeepsViewsAligned` |
| reveal puts the row at the top, not the middle | `revealCentresTheLineInEveryViewOfTheBuffer`, `revealCentresTheSelectionsLine`, `scrollingAndRevealGoThroughTheRowMap` |
| the accessibility text built without a client (`if true`) | `theAccessibilityNodeCarriesTheVisibleRowsCapped` |
| the accessibility value cap raised to 64 MB | `theAccessibilityNodeCarriesTheVisibleRowsCapped` |
| a fresh view starts at the first buffer row, not display row 0 | `theAccessibilityNodeCarriesTheVisibleRowsCapped` |
| paint's glyph loop back to `for (g, glyph) in glyphs.enumerated()` | `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` |
| `codeHash` back to a `for` over the bytes | `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` |
| `Frame.activeOffset` back to `clipStack.last?.offset` | `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` |
| `Scene.finalize`'s run merge back to `runs.last` | `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` |
| `Rope.lineStart`'s inner scan back to `for c in node.children` | `aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition` |
| `stylingOfLine` always walking the layers | (green, see below) |

Not reddened, and why: "a gap at the edit row moves with the new rows" (the `<` spelling of the split) is caught only by the model test; no window-level test puts a newline exactly at a gap's row (the model is the oracle for that rule). "`stylingOfLine` always walks the layers" stays green under the ceiling: with every layer unstyled the walk costs fewer than 66 extra allocations, so the `layerHasStyles` skip is an optimisation the ceiling does not pin. The first spelling of "edit does not splice the row map" (`if false {`) did not compile; the `_ = 0` spelling is the one recorded. The first spelling of "glyph loop back to enumerated" left `g += 1` behind and did not compile.

### 7.5 Measured and not measured

<RESULTS>

**Benchmark recipe** (from the plan's section 11; dated when run, never pinned; `BL-` convention). **Not run**: it needs a release build, a window on screen and injected input (`CGEvent`), which this run did not have (no windows). Run `METALUI_CODE_DEMO=1 METALUI_SIGNPOSTS=1 swift run -c release MetalUIDemo` with `window.frameTiming = FrameTiming(capacity: 4096)`. Typing needs the editing run. Scroll: a constant-delta wheel at 120 Hz; report `frameDuration` p50/p95 and gaps between `presented` greater than 1.5 refresh periods. Open: `FrameTiming.now()` before `CodeBuffer(utf8:)` until the first `onPresented`. Memory: `phys_footprint` before and after the 100k open. Instruments: the `Input→Frame` and `Frame` intervals. The headless debug numbers in 7.2 are indicative only.

### 7.6 Not in PR 2

The caret, editing, IME, find painting (PRs 3 and 4); gutter click callbacks on a bar's line range (Alloy's item 4, "PR 3 or later, low priority"); document-level accessibility (selected range, line attributes) and soft wrap (PR 6 of the plan). A virtual group anchored inside rows an edit removes is dropped with them (`CV-S`); the app gives rows again after such an edit.
