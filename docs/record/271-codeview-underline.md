# 271. CodeView underlines and squiggles (Alloy gap G35 PR C, `CV-AM`, `CV-AN`)

Branch `feat/codeview-underline` (master `b7df7e6a`). Rulings `CV-AM` and `CV-AN` in `docs/superpowers/2026-11-07-code-view-decisions.md` (PRs A, B, D, E and F of G35 take `CV-AJ`..`CV-AL` and `CV-AO`..`CV-AS`; records 270 and 272 belong to the parallel PRs). Class `M`; no divergence added or retired.

## What Alloy asked

LSP diagnostics need an underline and a squiggle on a highlight run (answers 2 and 6 of the G35 round): overlapping diagnostics are merged by Alloy with the most severe on top, empty and end-of-line ranges are passed as the server gave them and MetalUI draws a one-character minimum (at a line's end one space advance past the last glyph), and the wave matches Zed (about 1.5 pt high, 4 pt per period, scaled with the font size, 1 pt thick, phase anchored at the line start so scrolling does not shimmer it).

## API as shipped

```swift
public struct CodeUnderline: Hashable, Sendable {
    public enum Shape: Hashable, Sendable { case line(Text.LineStyle.Pattern), wavy }
    public var shape: Shape
    public var color: Color?          // nil: the colour of the text the run starts under
    public init(_ shape: Shape = .line(.solid), color: Color? = nil)
    public static func wavy(_ color: Color? = nil) -> CodeUnderline
    public init(_ style: Text.LineStyle)
}
CodeStyle.underline: CodeUnderline?   // init(foreground:background:underline: = nil)
```

As planned; `Text.LineStyle.Pattern` has no wavy case. No other public declaration.

## How

- `CodeDecorations.LineStyling.underlines` (package) is filled by `underlinesOfLine` from `computeStylingOfLine`, only once a run with an underlining style has been given (`anyLayerHasUnderlines`; resets with `.resync`). Per stretch the last (highest) layer with an underline wins; adjacent equal stretches join. It is cached by the `CV-AH` row cache and is not in the digest.
- Empty runs: `RunTree` cannot hold an empty range, so `setHighlights` gives an empty underlined run the character at its offset, the line break's first byte at a line's end, or the last character at the text's end. The styling reads a stored run that covers exactly the break's first byte (and does not continue into the next row) as an underline starting at the line's end, and paint extends any range that reaches past the line's end by one space advance. Virtual rows' styled runs underline too (their own coordinates, no tail).
- Paint (`CodeViewPlan.paintUnderlines`): a second loop over the shown rows after every row's glyphs, then the marked text (moved out of the row loop), then the caret. Straight lines: whole-pixel rects via `linePatternSegments`, cycle origin at `plan.textOriginX`. Wavy: a cubic S-curve path of whole periods from the period boundary at or before the run's start (counted from `textOriginX`), stroked with `pass.drawPath` under a clip cut to the run. The underline position, thickness and baseline come from `TextDecorationMetrics` and a one-glyph layout, cached per (face, scale) in `CodeLineCache.underlineMetrics`.

## Deviations from the plan, and why

- The plan's mutation for the cache pin ("phase from run start causes cache misses") does not hold for this geometry: with integer periods and an integer origin the path a run needs is the same path translated by whole pixels whichever boundary it starts at, so the cache hits either way. The phase is pinned by the overlap test instead (`aWavyUnderlineIsOnePathPerRunAnchoredAtTheLineStart`), the cache by `aSquiggleIsCachedAcrossAScroll`; mutations are in the tests' doc comments.
- Amplitude is read as 1.5 pt peak to peak (so about 2.5 pt with the stroke). Only the human check can say whether Zed's looks like this; CV19 asks.
- The zero-width run at the very end of a text that ends in a newline attaches to the previous row's end; an adjacent same-style run starting on the next row's first byte merges with a tail and loses it. Both named in `CV-AM`.

## Counts

See the PR description for the suite totals and the warm-scroll allocation value (`aWarmScrollFrameAllocatesTheSameAt1kAnd100kLinesAndAtAnyPosition`, ceiling 910, `CV-Z`), unmoved with the feature unused.
