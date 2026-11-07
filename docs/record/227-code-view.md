# Record 227: the read-only code view (Alloy gap G1, PR 2 run 1) - DRAFT

**DRAFT: run 1 of PR 2.** Sections marked `TODO(run 2)` are written when virtual rows, the scroll-sync API, the accessibility node, the demo and the final docs land. Branch `feat/code-view` (master `b3c60d27`, which has `MetalUICodeBuffer`, record 225). Rulings `CV-J`..`CV-R` in `docs/superpowers/2026-11-07-code-view-decisions.md` (next `CV-S`). Class `M`; no divergence added or retired. Record 226 is another line in flight (continuous corners), so this took 227.

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
| Allocations, one warm 1 px scroll frame, line numbers off, top | 4380 | 4522 |
| Allocations, same, 600 rows down | 5040 | 5077 |

The same-position difference (142 and 37) is the rope's extra level; the pin is within 20 per visible row (260). Before `CV-R` the same frames allocated 7739 / 7881 at the top and 10821 / 18362 at 600 rows (one allocation per byte scanned by `Rope.lineStart`). A 20 KB line is shaped as one window: under 4000 bytes shaped on open, none for a 20 pt horizontal scroll. One edited line re-shapes one line (`aKeystrokeInTheBufferRelaysOutNothing`: 0 layout measure calls, 0 memo misses).

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

## 7. Not in run 1 (`TODO(run 2)`)

Read-only virtual rows (`setVirtualRows`, filler rows for side-by-side alignment) through the row map; the scroll-sync API (an observable scroll position, `onScroll`, programmatic scroll that does not feed back); the accessibility node (`.textArea`, the visible rows' text, capped); the `METALUI_CODE_DEMO=1` demo (a generated 100k-line file) and its 1 MB-stack builder; `docs/guides/code-view.md`, `docs/api-overview.md`, the human-check group `CV`, the `CLAUDE.md` demo list and counts; the benchmark recipe numbers. Not in PR 2 at all: the caret, editing, IME, find painting (PRs 3 and 4).
