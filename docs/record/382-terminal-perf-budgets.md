# 382 - Terminal performance budgets (`TRM-BL`)

Branch `feat/terminal-perf-budgets` on `feat/terminal-perf-closeout` (PR #384, record 381). No divergence, no public API (`TerminalRow.forEachCellByRun`, `attributes(ofRun:)`, `runCount` and `TerminalGlyphCache.sprites(at:in:)` are `package`).

**SGR allocations.** `FeedAllocationTests` (release, `PA-J` counter): a line of four SGR sequences allocated 8 001 times per 2 000 lines. Reading the parser first ruled it out: `CSIParameters` keeps its arrays' capacity (`clear` is `removeAll(keepingCapacity:)`) and the handler is lent the struct. The source was `TerminalRow.setAttributes`, which on every overwrite of stored text built a new `[Run]` (`reserveCapacity`) from a copy of the old one: one per attribute run written, about one per sequence. It now splices in place and merges equal neighbours in place. Also made allocation-free: the `Array(values[...])` copies in `sgr` and the `compactMap` in `colon`. Result: **8 001 to 4** per 2 000 lines (the plain row's constant 1 is the same kind); pinned at 8 in all.

**Full-grid frame.** `METALUI_RUN_TERMINAL_BENCH=1 swift test -c release --filter surfaceOnlyFrameCPUOfAFullGrid`, three runs each (the bench's own figure is the minimum of 50 frames):

| | run 1 | run 2 | run 3 | median |
|---|---|---|---|---|
| before | 1136 us | 1107 us | 1115 us | **1115 us** |
| after | 594 us | 580 us | 564 us | **580 us** |

One damaged row: 19 us to 9-10 us. Same 11 860 instances. Where it went: the atlas probe per glyph (a `GlyphKey` hash and compare, 11 860 per frame) is now per cluster per layout plus a per-frame stamp; per-cell `TerminalAttributes ==` and `Resolved` lookups are per run; the dictionary lookup of the glyph colour is per run with a one-entry memo. No profiler was needed beyond the bench: the three changes were the per-cell work the loop had.

**Selection frame.** Kept at two draws. The Copy text is a value in the view tree (`.copyable(model.copyItems())`); a lazy one needs a closure-valued public `copyable` or a blocking hop to the emulator queue. The extra frame is empty. See `TRM-BL` item 3.

**Tests and mutation.** `FeedAllocationTests` bound 8 in all; new `RowSetAttributesTests` (random overwrites against a per-column model). Mutation: `sgr` copying its parameters (`var values = p.values; values.append(0); values.removeLast()`) gives SGR 8 004 and `coloured <= 8` fails; reverted.
