# 415 - A streaming transcript's `phys_footprint` (G50)

Date: 2026-11-24. Branch `perf/g50-streaming-footprint`. Scope: the memory a long, growing `Text`
costs. The binding rule from the Alloy peer: fast **and** small; every cache bounded.

## Measured (release, CoreText text system, `TestWindow`, 200 static messages + one growing `Text` + a `TextField`)

`phys_footprint` (`task_vm_info`), not RSS. Probe: a temporary executable target (not committed)
driving 1500 frames, a word appended and a key typed per frame, a scroll every 40.

| run | footprint, start to end | live malloc | median frame |
| --- | --- | --- | --- |
| text grows, master, 1500 frames | 31.8 to 367.6 MiB (+336) | 20.8 to 80.2 MiB | 14.6-16.9 ms |
| text does not grow (60-word rolling window), master | 31.8 to 70.2 (+38) | 20.8 to 29.2 | 11.2 ms |
| no text change, redraw only, master | 31.8 to 46.0 (+14), flat after frame 300 | 20.8 to 19.8 | 6.4 ms |
| text grows, `autoreleasepool` around each frame's sync work, master | +328 | | 14.6 ms |
| text grows, 5000 frames, master | 31.9 to 582.0 (peaks 805) | 97.5 (peaks 293) | 93.6 ms |
| text grows, this branch, 1500 frames | 26.4 to 137.7 (+111; +100 to +111 over three runs) | 15.1 to 46.7 | 12.6-13.1 ms |
| text does not grow, this branch | 26.3 to 58.8 (+32) | 15.1 to 20.6 | 10.0 ms |

Growth follows **text length**, not frames: the fixed-length window and the idle redraw plateau, the
growing text does not (5000 frames is not a plateau: footprint swings 150-800 MiB with the text). No
autorelease-pool effect: the probe runs under the main run loop, and the per-frame pool changes nothing.
Nothing here is Metal or IOSurface (`TestWindow` is headless; no atlas page grows).

## Attribution

`vmmap --summary` at the end of 1500 frames: the dirty bytes are `Malloc Large` 31 MiB live plus
`Malloc Large (empty)` 190 MiB (60 regions of about 3 MB, freed and cached by malloc) and
`Malloc Small (empty)` 77 MiB. `malloc_zone_pressure_relief` returns none of it. No `IOAccelerator`, `CG image`
or `CoreText` region grows. `malloc_history` of the live blocks and `heap -s` put the 2-3 MB blocks in
`ShapedText.placedGlyphs` (the placement memo, `PlacementBox.memo`), the `[TextGlyph]` that
`CoreTextTextSystem.placeGlyphs` returns each frame, and `Scene` growth.

Cause: a placed glyph was 264 bytes and a `TextGlyph` 144, because every `GlyphKey` carried its
`FontKey` inline (88 bytes: the PostScript name, the variation array, six matrix `Double`s and a hash),
and a `PlacedGlyph` carried a `GlyphKey` **and** a `ResolvedFont` (which holds the `FontKey` again). A
14 KB message is 3.7 MB of memo and 2 MB of glyph array, rebuilt every frame its text changes, each a
slightly larger request than the freed one before it, so malloc's large-block cache cannot reuse them.
That is the legitimate-versus-unbounded split: the text really is that long (14 KB is about 3 MB of glyph
records even at 200 bytes); the cost per glyph was the avoidable part, and the count of kept entries
(ShapingCache, not touched here, `perf/g48-caret-offsets-cache`) is the rest.

## What changed

`FontKey` keeps the name, variations and matrix in one immutable `Sendable` box and the size and hash
inline. `FontKey` 88 to 24 bytes, `GlyphKey` 128 to 64, `ResolvedFont` 120 to 56, `PlacedGlyph` 264 to 136,
`TextGlyph` 144 to 80. No public signature changed (the three fields are now computed). Copying a key is
one retain instead of two; `==` short-circuits on the same box. Footprint +336 to +111 MiB, median frame
about 15.5 to 12.8 ms in the same probe.

Tests: `GlyphFootprintTests` pin the strides. Their bounds are below the sizes the probe's `MemoryLayout`
print measured on the unmodified tree (`FontKey` 88, `GlyphKey` 128, `PlacedGlyph` 264, `TextGlyph` 144), so each
expectation is false there; the tests were written after the change and not run red in the suite.

## Round 2: the remaining footprint, the paragraph case, and what is not fixed

Region counts at the end of 1500 frames (`vmmap --summary`), growing text, 14 KB:

| build | footprint | `Malloc Large (empty)` | `Malloc Small` / `(empty)` dirty | live malloc |
| --- | --- | --- | --- | --- |
| master | +242 (+336 in the earlier run) | 43 regions, 137 MiB | 81 / 99 MiB | 80 MiB |
| #432 (FontKey box) | +110 | 5 regions, 15 MiB | 78 / 41 MiB | 47 MiB |
| #432 + this round | +95 | 5 regions, 15 MiB | 78 / 47 MiB | 41 MiB |

The freed 3 MB blocks are gone (the 5 left are the live 3 MB scene and memo arrays); what remains is
`Malloc Small`, the per-line shapes (CoreText lines, run arrays) of about 220 cached entries of a text that
is new each frame. That is the ShapingCache's entry count, which `#427` (a shared byte budget) owns.

This round: placement memo and the `[TextGlyph]` array are reserved in quarter-power-of-two classes
(`GlyphCapacity`), `placeGlyphs` writes into the block the previous call returned (`KeptBuffer`, one per
system, at most 64 Ki glyphs, dropped when the next text needs under a quarter), and a `PlacedGlyph` holds its
font as one reference per run (`PlacedFont`): `PlacedGlyph` 136 to 88 bytes (`font` is a computed property;
the public `init(key:font:pixelX:baselineY:)` remains; four source files touched). The new tests failed to
compile on the tree without these members (`glyphBuffer`, `placedFont`), and the 96-byte bound is under the
136 measured before. A frame-time gain is inside the probe's noise on a loaded machine.

**The paragraph-split case (what Alloy sees)**: the same 14 KB in 40 paragraphs (`ForEach` of `Text`), 1500
frames, in the same probe: master +39 MiB, #432 +39, this round +38; the floor with no growing text is
+32 to +37. A message split into paragraphs costs nothing extra on master already, so the 550 MB per
25 KB reply Alloy measured is not reproduced by paragraph blocks. Probe counters
(`placeGlyphsCalls`, `placeGlyphsReturned`, `placeGlyphsComputed` on `CoreTextTextSystem`, `package`): in
that variant **every frame calls `placeGlyphs` for every `Text` on screen (about 205 calls, 30 000 glyphs
returned), and 2 of them compute a placement; the rest answer from the shape's memo.** That variant
had 200 static `Text` rows that were NOT under `.equatable()`: an un-wrapped `Text` runs `prepaint` and
`paint` every frame and rebuilds its `[TextGlyph]` from the memo (about 2 MB a frame). **Corrected in round 3
(the first version of this paragraph read the 200 static rows as settled paragraphs and said `.equatable()`
did not help): with `.equatable()` on every row (40 growing-message paragraphs and the 200 static rows) the
last frame is 2 `placeGlyphs` calls and 1 710 glyphs (the growing paragraph and the composer), 3 439 calls over
1500 frames, against 310 638 with the 200 static rows plain and 33 519 / 3 038 for 40 paragraphs alone plain /
equatable.** `METALUI_TRACE_RETAINED=1` over 500 frames of the fully wrapped variant prints only misses:
`first-or-dropped` and `noRecord` once per row, `replayDisallowed, quarantine` and `coverage.build` in the
warm-up frames, `ledgerKey.*` / `key.ambient.clip` with `extras.scroller` on the scroll frames (every 40th),
`serial` for the growing paragraph. No `recordCannotMove`, `maskStraddlesEntryClip`, `inexactTranslation`
or `requestRedo` line appeared. So the cost an app sees is a row that is not equatable (Alloy's
message-block rows must be), not the redo backoff.

## Not done

A `[TextGlyph]` memo in the placement box (settled text would skip the per-frame conversion; costs a second
array per entry unless `PlacedGlyph` is dropped for the system path), `Scene` capacity reuse (`#428`), and a
byte budget on the ShapingCache (`#427`).
