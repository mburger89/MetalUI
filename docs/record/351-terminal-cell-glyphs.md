# 351 - Terminal cell metrics, grapheme cache and synthesised glyphs (`TRM-AZ`)

Numbered 351: 349 is #352's and 350 the ConPTY branch's; expect renumbering. `TRM-AX` and `TRM-AY` belong to the ConPTY branch, so this starts at `TRM-AZ`.

Branch `feat/terminal-cell-glyphs` from master `49630aaf`; Phase 5.2 of `docs/superpowers/plans/2026-11-16-terminal.md`. Class M, `package` only, no divergence label, no inventory row (no public declaration; `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing).

**Where it lives.** The new target `MetalUITerminalUI` (`TRM-A`: `MetalUI` + `MetalUITerminal`, plus the lower modules it reads; a library product; no MetalUI target depends on it), portable (wherever MetalUI builds, Linux included). `MetalUITerminal` gains one `package` method, `TerminalRow.forEachCell` (one pass over bytes and runs, no allocation per cell), because `bytes` and `runs` are internal and `graphemes` allocates an array.

**What landed.**
- `TerminalCellMetrics`: width, height, baseline, underline and strike rows in whole device pixels; each measured in points and rounded to nearest once at the scale (see `TRM-AZ` item 1). Menlo 13 pt reads 8 x 16 at scale 1; Noto Sans 14 pt (the portable pin) 13 x 20 and 25 x 40.
- `TerminalGlyphCache`: `(cluster, bold, italic)` to placed glyphs through the text system (the fallback is the system's: CoreText's cascade or `shapeCascading`), emptied when the atlas `layoutGeneration` moves; ASCII is a flat table. 漢 in Menlo falls back to another font through CoreText and is wider than one cell.
- `SyntheticGlyphs`: box drawing (all weights, dashes, doubles with corner and junction rules), blocks and shades, braille, and Powerline E0B0-E0BF; rects through `SurfaceTextSink.fillRect` where exact, cell-sized R8 bitmaps (4 x 4 supersampled) for arcs, diagonals and the Powerline curves and slants.
- `TerminalColorScheme`: ANSI 16, cube, greys, truecolour, bold-as-bright, inverse, dim, hidden, underline colour.
- `TerminalRowPainter`: a row's merged opaque backgrounds, glyphs masked to the row, then underline (five styles) and strikethrough runs.

**Not done here.** The view, cursor, selection, blink and the public `TerminalPalette` (5.3); U+E0A0-E0A3 and E0C0-E0D4 stay with the font (icons of a patched font).

**Tests.** Portable `MetalUITerminalUITests` (macOS, Linux): metrics at both scales (literal pins) and Menlo, the palette table, geometry of every synthesised scalar (no gap or overlap through three cells, every arm meets its neighbour at the edge across the whole block, blocks partition the cell, braille dots, arcs meet their lines, Powerline coverage), cache hits counted, generation rebuild, cluster and wide-cell handling, the warm 80 x 24 screen shaping 0 glyphs and the 0-allocation lookup (macOS), row painter records. macOS `TerminalGlyphMetalTests` (line through three cells without a gap at scale 1 and 2, shades and halves at their coverage, triangle coverage, a closed rounded box); SDL `SDLTerminalGlyphTests` (a box-drawing row equals the oracle rects pixel for pixel at both scales, an arc equals its R8 coverage). Mutations, each red then reverted: floor instead of round for the width, no ASCII cache write, ignore the atlas generation, right arm one pixel short (portable, Metal and SDL), one background rect per cell, grey step 11, draw hidden glyphs, shade coverage 32, Powerline apex at the top, braille bits 3 and 7 swapped, arcs centred on `cw / 2`, bold-as-bright always on, dim before inverse, double line's outer stroke one pixel in.

**Counts.** `swift test --build-system native --no-parallel --filter 'Terminal|GridSink|Glyph|Atlas|Font'`: 490 tests in 40 suites, green (26 new in `MetalUITerminalUITests`, 4 in `TerminalGlyphMetalTests`); Linux (`swift:6.4-noble`, separate scratch): `MetalUITerminalUI` builds and its 23 portable tests pass; SDL `SDLTerminalGlyphTests` 2 pass. The full root suite was not run.

**Findings.** A debug build's `ArraySlice.first` and a `for ... in` over an array of slices each allocate (so the cache reads `bytes[startIndex]` and the allocation test indexes); the test counts the cache, not the iterator. Whole-slot sampling is unnecessary for bitmaps: a sprite is a 1:1 blit, so only stretched rects needed the solid slot's margin (`TRM-AU`).
