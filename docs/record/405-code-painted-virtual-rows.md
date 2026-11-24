# 405: `CodeDecorations.paintedVirtualRows(at:)` (`CV-CA`, Alloy)

Class `M` (MetalUI-only API), no divergence (labels unchanged). Branch `feat/code-virtual-row-readback`, base master `a11aedea`. Alloy's follow-up to #413 (`CV-BZ`, record 402): a plugin's message row paints a bar on its virtual row and its test could only assert `virtualLineCount == 1`. **Numbering:** 403 is taken and 404 belongs to the in-flight SB-AF cost fix, so this is 405.

## Change

- **API** (`CodeDecorations.swift`): `paintedVirtualRows(at: CodeVirtualRow.Anchor) -> [CodePaintedVirtualRow]`; `CodePaintedVirtualRow` (`anchor`, `lines`, `background`, `gutterBar`, `gutterMarker`, `tag`, `owner`). Addressing is by anchor (virtual rows have no id), then position in the array for owners sharing a gap. The inventory-map row `code-decorations` names them.
- **Resolution.** `rowMap.displayRow(ofBufferRow: gap)` gives the display row just below the gap; the walk goes up through `rowMap.row(atDisplay:)` (what the plan calls per display row) while it answers `.virtual`, collecting each group once. Because two gaps always have a buffer row between them, the walk ends at the gap's first line. The marker is the first line's, absent when its text is empty (the paint draws none).
- **Not a `CodePaintedLineDecoration`**: a group is one owner's, so there is nothing to merge, and `CodePaintedGutterBar.lines` is buffer rows. See `CV-CA`.

## Cost evidence

No stored state; the paint path is untouched. `readingVirtualRowsBackCostsTheViewNothing` pins that 50 reads schedule no frame (`frameWork.count == 0` after them) and that the next steady frame costs the same whole `FrameWork` (2 requests, 0/1/0 retention, 0 lines shaped) as with no reads.

## Tests

`CodeViewPaintedVirtualRowTests`, four: owners, tag, lines and spellings at one gap; an edit above moves the gap; agreement with the scene (3 pt bar rects and the tint over the group's display rows); the cost pin. Root 7315 to 7319 tests in 79 suites (+4), `--build-system native`, `--no-parallel`, green; both closeout probes print nothing.

## Mutations

Run on the committed code and restored from a backup copy.

| test | mutation | red |
|---|---|---|
| `aVirtualRowsBarOwnerTagAndLinesReadBack` | the groups returned bottom-up | itself, and the agreement test |
| `aVirtualRowsBarOwnerTagAndLinesReadBack` | `owner` read as `nil` | itself, and two others |
| same | the empty-text marker filter dropped | itself |
| same | the per-group de-duplication dropped (a line per entry) | itself, and the agreement test |
| `theVirtualReadBackIsWhatTheViewPaints` | the bar colour read from the tint | itself, and the first |
| `anEditAboveMovesTheReadBackGap` | `sync()` removed | itself |
| `readingVirtualRowsBackCostsTheViewNothing` | the read bumps `revision`, or calls `invalidateHighlights` (first attempt compared only the forced frame's work, which a coalesced redraw hides: the test now also counts frames the reads alone cause) | itself |
| (none) | `at == gap` in the walk: removed as an equivalent mutant, since a buffer row always separates two gaps | |
