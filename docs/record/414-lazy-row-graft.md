# 414: a streaming row no longer takes the rows above it off the replay path (`G49-A`, Alloy)

Class `M`, no public API, no divergence. Branch `perf/g49-lazy-row-graft`, base master `4d030e94`. Records 411-413 belong to concurrent branches.

## The report

Alloy's chat transcript (`ScrollViewReader > ScrollView(.defaultScrollAnchor(.bottom), .contentMargins(.bottom)) > LazyVStack(.leading, 10).padding > ForEach(blocks) { ChatBlockView.equatable() }`, 51 blocks, 30 deltas into one block) ran 1.0 body per delta for the rows once they were `.equatable()`, but 489 element requests and 516 prepaints a delta: memo hits skipped the getters, the graft and the prepaint replay did not engage.

## Reproduction and attribution

`LazyRowGraftTests.swift` mirrors the shape: 50 settled rows of five kinds (text bubble, two-paragraph stack, icon row, label row, text and a button) and a streaming row that grows one word a frame, in a 420 x 600 window at scale 2. Counts per frame, base `4d030e94`, 24 streamed words:

| | element requests | prepaints | grafts | redos |
|---|---|---|---|---|
| frames before the first wrap | 8 | 9 | 9 | 0 |
| first frame that wraps (the extent grows, the anchor moves the offset) | 58 | 59 | 0 | 1 |
| every later frame (a backoff is always running; a wrap re-arms it) | 53 to 58 | 54 to 59 | 0 | 2 in 24 |
| mean of the 24 | **48** | 49 | 1 | 2 |

Bisection (12 words, mean per frame): the anchor is the condition. With `.defaultScrollAnchor(.bottom)` the stack streams at 28 requests (the redo frames averaged in); without it the same rows never move and cost 4. `ScrollViewReader`, `contentMargins` and the stack's padding change nothing (28, 28, 23). An eager `VStack` is a different case (120 requests, all 51 rows built, no window; 4 translated); a lazy stack outside a scroller grafts 50 of 50 rows at 6 requests.

`METALUI_TRACE_RETAINED=1 METALUI_TRACE_RETAINED_PATH=400`, the frame the first wrap lands in, for each realised settled row (ids 41 to 49):

```
retained prepaint miss ... named(41) ... reasons=[ledgerKey.ambient.offset, ledgerKey.extras.scroller] frame: grafted=true
```

then the redo attempt for every row: `reasons=[replayDisallowed, quarantine]`, and `[replayDisallowed]` for the next eight builds. The chain: the wrap grows the content extent, the anchor moves the offset (a K2 translation, which the paint record takes: `retainedTranslated` 9). The prepaint key's `scroller` vector holds the extent at index 8 (`PrepaintExtras`), so `shift(to:)` and `equalIgnoringScrollOffset` refuse the translation (they set aside only the offsets, 7 and 10). A grafted occurrence has no element layout to prepaint, so the frame is abandoned (`requestRedo`, `RK-C`), and `noteRedo` suspends prepaint replay for 8 builds window-wide and quarantines each entry for 8, 16 ... 256. A reply that wraps every few words re-arms it before it ends, so the transcript is never on the replay path.

## The fix

`Frame.prepaintExtras()` writes 0 at indices 8 and 11 (primary and cross content extent). Exact because the extent has two readers, both refused before a ledger exists: `resolveScrollRequest` (`scrollRequests` in `prepaintRefusal`, and the `scrollRequest` audit channel) and `scrollPosition`'s target notes (`scrollTarget` audit channel); `ScrollerFrame.logicalStart` reads it only for a mirrored horizontal scroller, which feeds those notes. The vector keeps its indices (`RZ-M`).

After, same fixture: 8 requests, 9 prepaints, 8 to 9 grafts, 0 redos in every one of the 24 frames; the frames that move the rows replay translated (`retainedTranslated` 8 to 9).

## Pins (`LazyRowGraftTests.swift`)

- `aStreamingRowKeepsTheRowsAboveOnTheReplayPath` (2 shapes): per frame no redo or backoff, at most 12 requests and 14 prepaints, at least 7 grafts and 7 prepaint hits, at least 5 of 24 frames translated, and the scene, hitboxes, tallies and element bounds equal a non-retaining window's after every word. **Red without the fix:** 206 issues (redo 18, requests 21, prepaints 21, grafts 21, replays 21 per shape), and the differential reports `element bounds` differing at step 3, the redo frame (a pre-existing difference of the redo path under a bottom anchor, gone with the redo; not chased).
- `aQuietTranscriptFrameCostsOnlyTheScroller`: an unchanged frame costs 4 requests and no redo, the same before and after (the steady frame pays nothing for the change).

## Measurement

Release build, a throw-away `G49Probe` executable (the fixture above in a `TestWindow`, 120 streamed words, thread CPU per `tick`, `malloc_logger` allocation count per tick, `phys_footprint` from `task_info`), base against branch, three interleaved runs on a loaded machine:

| | requests / prepaints / paints a frame | redos in 120 | CPU ms a frame (median) | allocations a frame (median) | `phys_footprint` start to end |
|---|---|---|---|---|---|
| base | 35 / 36 / 10 | 4 | 1.29, 1.19, 1.30 | 4576, 4572, 4574 | 12.1 to 16.0, 14.8, 14.8 MB |
| branch | 8 / 9 / 11 | 0 | 1.19, 1.12, 1.04 | 4195, 4197, 4195 | 11.7 to 15.6, 14.6, 14.7 MB |

-8 % allocations, about -10 % frame CPU on this light fixture (Alloy's rows are heavier: 489 requests a frame), footprint -0.2 to -0.4 MB; the 3 MB growth over the run is the same on both (the growing text's shaping and glyph caches). No cache is added; idle is unchanged (a quiet frame is 4 requests before and after).

## Memoizing a generic container whose body is closure-built

`BlockChrome<Body: ElementGroup>` evaluates its builder eagerly in `init` into `let body: Body` (Alloy already does). `extension Chrome: @MainActor Equatable where Body: Equatable` compiles and `.equatable()` works on the specialisations that satisfy it: with `Body` a single `Equatable` component (`buildBlock(_ group)` returns it unwrapped) the occurrence skipped its getter (skips 1, evaluations 0); with two statements `.equatable()` is a compile error, `'TupleGroup<Text, Text>' conform to 'Equatable'`. No builder result type conforms: `TupleGroup`, `Pair`, `OptionalGroup`, `EitherGroup`, `ArrayGroup`, `ForEach`, `Text`, `VStack`, `HStack`, `Padding` and the modifier wrappers hold closures or non-`Equatable` storage. A closure-built body is therefore memoized by comparing the inputs that produced it, not the built value: store the inputs (value types, the `Equatable` leaf components) and build in `content`, or write `==` over `kind`, `title` and the body's own inputs and keep `body` out of it (the closure is then not evaluated per parent body either, if the builder is stored). SwiftUI is the same: `EquatableView` needs the conformance of the whole view, and a view holding a `@ViewBuilder` closure or built content of non-`Equatable` types is compared as unequal by its field-by-field diff.

## Left

A grafted occurrence whose prepaint ledger misses still redoes the frame for everyone: one bad row costs the window 8 builds. A finer outcome (build only that occurrence again) is the next candidate; nothing here needs it.
