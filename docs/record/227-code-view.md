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

`TODO(final)`: lines shaped on open and on a one-row scroll at 1k and 100k lines; allocations per warm scroll frame.

## 4. Mutations

`TODO(final)`: the table (each applied alone to the committed tree in place, restored with `git checkout`; log `scratchpad/mut.log`).

## 5. Results

`TODO(final)`: `swift package clean`, native build, unfiltered `--no-parallel` summary and `FR-J no-argument frame: succeeded=`, `METALUI_VERIFY_RETAINED=1`, `METALUI_VERIFY_CODE_CACHE=1`.

## 6. Linux (portable container)

`TODO(final)`.

## 7. Not in run 1 (`TODO(run 2)`)

Read-only virtual rows (`setVirtualRows`, filler rows for side-by-side alignment) through the row map; the scroll-sync API (an observable scroll position, `onScroll`, programmatic scroll that does not feed back); the accessibility node (`.textArea`, the visible rows' text, capped); the `METALUI_CODE_DEMO=1` demo (a generated 100k-line file) and its 1 MB-stack builder; `docs/guides/code-view.md`, `docs/api-overview.md`, the human-check group `CV`, the `CLAUDE.md` demo list and counts; the benchmark recipe numbers. Not in PR 2 at all: the caret, editing, IME, find painting (PRs 3 and 4).
