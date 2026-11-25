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

## Not done

Still +111 MiB for a 14 KB message: the per-glyph `font` in `PlacedGlyph` (56 bytes) and the memo itself
are kept; the placement memo and `[TextGlyph]` could be dropped for text longer than a screen, and
`Scene`'s per-frame arrays could keep their capacity across frames. Both are follow-ups, as is a byte
budget (not an entry count) on the ShapingCache.
