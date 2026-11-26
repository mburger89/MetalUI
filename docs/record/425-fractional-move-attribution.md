# 425: whose number is fractional, and does SwiftUI snap the scroll position (`RK-AO`; Piece 3(b) step 0 and its SwiftUI probe)

Class `M`, no divergence, no public API. Branch `perf/fractional-move-probe`, base master `ef42c1b9`. **Evidence, not a fix**: no snapping and no recompute is landed; the plan's Piece 3(b) chooses between them from this record. Plan: `docs/superpowers/plans/2026-11-25-exact-redo-and-movable-records.md`, Piece 3(b).

## Step 0: the refusal trace names the number

`Frame.paintTranslation` printed `retained paint translation refused <path>: inexactTranslation`. It now appends, for `fractionalTranslation` and `inexactTranslation` only, a bracket built by `Frame.describeFractionalMove` (`RetainedTranslationDetail.swift`):

- the gate on the first top node's device origin: `[entry field=<dx|dy|newX|newY|oldX|oldY> value=<device px> fractional=<entryOffset|layoutOrigin|both|sum> ...]`, with `layoutDeltaPx`/`offsetDeltaPx` for `fractionalTranslation` and `entryOffsetPx` for `inexactTranslation`;
- or the first leaf `movedLeaf` cannot add exactly: `[leaf=<rect|glyph|image; groupMask. before it for a mask> field=<bounds|contentMask>.origin.<x|y> value=<v> fractional=<leaf|sum> move=(dx,dy) entryOffsetPx=(x,y)]`.

Real lines (scale 2, 24-card scroller, wheel 0.3 pt then 0.5 pt): `fractionalTranslation [entry field=dy value=-0.600006 fractional=entryOffset layoutDeltaPx=(0,0) offsetDeltaPx=(0,-0.6)]`, then `inexactTranslation [entry field=newY value=248.4 fractional=entryOffset entryOffsetPx=(0,-1.6)]`. At scale 1.2 (10 pt header growth): `[entry field=newY value=122.4 fractional=layoutOrigin entryOffsetPx=(0,0)]`, and one leaf `[leaf=rect field=bounds.origin.x value=234 fractional=leaf move=(0,6) ...]` (`x * 1.2` one ulp off a sixteenth: six digits printed 234, so leaf values now print nine).

The description re-reads the gates in `movedPaintRecord`'s order and decides nothing; the counters keep their one name. It lives in a new file and the only edit in `RetainedTranslation.swift` is the trace call (Piece 3(a) retires `maskStraddlesEntryClip` in the same file).

**Off costs nothing.** The call sits inside `RetainedTrace.emit`'s autoclosure; `RetainedTrace.detailsBuilt` (package, a test counter) stays 0 while nothing listens, with `linesBuilt` and `pathsBuilt` (`theRefusalDetailIsBuiltOnlyWhileSomethingListens`). Nothing is stored per frame; the steady-frame pins (`aNonAnimatableComponentAllocatesWhatItDid`, `everyFrameChannelIsClassified`) are unchanged.

## Tests (`FractionalMoveAttributionTests`, 5) and their mutations

| Test | Mutation that reddens it |
|---|---|
| `aFractionalScrollIsRefusedWithItsFieldAndWhoIsFractional` | `describeFractionalMove` returns `""` (red); `who` always `layoutOrigin` (red, 24 issues) |
| `anInexactLayoutOriginIsNamedAsTheLayoutOrigin` | `describeFractionalMove` returns `""` (red) |
| `aLeafWithAFractionalOriginIsNamedByKindAndField` | content mask not read and `x` only (red, 2 issues) |
| `theRefusalDetailIsBuiltOnlyWhileSomethingListens` | the call hoisted out of the autoclosure into a local (red) |
| `theTranscriptFixtureRefusesNoFractionalMoveWhileItStreams` | a pin on the finding below; reddens if a fractional offset reaches the fixture |

(`who` always `entryOffset` was not run; it is the mirror of the second red above.)

## The record 416 fixture: no fractional refusal at all

`ChromeTranscriptFixture` (rounded tinted rows, nested `.equatable()` paragraphs, bottom anchor, scale 2) over 12 and 40 streamed words refuses only `maskStraddlesEntryClip` (8, 8, 5, 1, 1 per row id over 40 steps) and `innerScope` (2). **There is no `inexactTranslation` and no `fractionalTranslation`**; a fractional bottom margin (`contentMargins` 40.3, 40.25) changes nothing, because layout rounds rects to whole points (divergence 77) and the anchored offset is a difference of whole points. So record 416's "`inexactTranslation` (a fractional device-pixel move)" is not reproduced by streaming alone: at whole-point offsets the rows move by whole device pixels and every origin is an exact sixteenth.

Where a fractional offset does enter MetalUI: a wheel or trackpad delta that is not a whole number of device pixels. A 0.3 pt wheel step on the 24-card scroller is `entryOffset` fractional (0.6 px), the next whole-pixel step is `inexactTranslation` on the entry gate: **the entry offset, not the leaves, is the fractional number**, with the layout origin 0 and every leaf's origin exact (scale 2). A wheel step on the transcript fixture did not reach the retained translation in my probes (4 to 25 requests, no refusal line; not investigated). Alloy's own `inexactTranslation` count therefore needs its own run with the new trace: if its lines say `fractional=entryOffset` the scroll offset is the cause (cure 1, snapping the painted offset, applies and the leaves never need an origin side table); `layoutOrigin` or `leaf` would send the cure to the layout or to FS-W.

## The SwiftUI probe (`docs/probes/swiftui-scroll-offset-pixel-snap.swift`, SA-O header with the recorded output)

Run twice (`/usr/bin/swift` and `xcrun swiftc -O`), identical output. 1x on the real display; "2x" offscreen: `.environment(\.displayScale, 2)` plus an `NSBitmapImageRep` at twice the point size and `cacheDisplay(in:to:)`, the hairline at each row top read back at pixel resolution (crisp = whole pixel rows).

- **Leaf origins are snapped.** Hairlines at 30.25, 70.3, 90.75, 233.3, 246.7, 12.25, 0.3 are crisp at 1x and at 2x (nearest pixel, ties up: 30.25 draws at 30.0 at 1x and 30.5 at 2x). The control and the injection both reach layout (`contentSize` 399.5 at 2x against 400 at 1x for twelve 33.3 pt rows).
- **The scroll position is snapped and reported snapped.** In every arm SwiftUI drives, the clip origin and the `onScrollGeometryChange` `contentOffset` are the same whole number: `scrollPosition(y:)` 0.3, 100.3, 100.7, 100.8 gives 0, 100, 101, 101 at both passes (a 2x device grid would give 100.5 for 100.3); the bottom anchor of a 399.5 content at 2x reports 99.0; `contentOffset` is never fractional unless AppKit was handed a fractional bounds directly.
- **An AppKit-given fractional clip is not snapped.** `NSClipView.scroll(to: 0.15/0.3/0.45)` draws blended (0.85/0.15 at 1x, 0.70/0.30, 0.40/0.60, 0.10/0.90 at 2x) and reports the raw fraction; so does F5's 87.75. SwiftUI snaps what it places, not a clip it did not set.
- **Not measurable offscreen:** the real 2x grid of the scroll position (the window's backing stays 1; `scrollPosition` gave the same whole points under the injected scale, so its grid follows the real backing or is whole points), AppKit's wheel accumulation at 2x, and a fractional wheel delta (`NSEvent(cgEvent:)` truncates 0.3 and 0.7 to 0 and scales whole values by 8). `cacheDisplay` is Core Animation's software render, not the Metal compositor. Confidence: high for the leaf rounding and for the 1x scroll grid (positive and negative controls agree); moderate that the 2x scroll grid is half a point, which is expected from AppKit but unmeasured here.

**Verdict for Piece 3(b):** SwiftUI never presents a fractional offset of its own making: leaves are on the pixel grid and the scroll position, drawn and reported, is on a grid. That favours **cure (1)**: snap the scroller's painted offset to `round(offset * scale) / scale`, and the stored/reported one too (SwiftUI's `contentOffset` is snapped, so a stored snap is not a divergence). The grid at 2x should be confirmed on a Retina machine before the ruling (`DSA-J`) is written; the human check is one run of the probe on a 2x display, whose backing-scale line and F4a rows say it directly.

## Counts

Root: see the CLAUDE.md line (+5 `FractionalMoveAttributionTests`). `swiftlint lint --strict --baseline .swiftlint-baseline.json` prints nothing new; the closeout inventory and undocumented scripts print nothing.
