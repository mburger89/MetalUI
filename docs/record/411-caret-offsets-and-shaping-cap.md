# 411 - `caretOffsets` cached, `ShapingCache` bounded (G48)

Date: 2026-11-24. Branch `perf/g48-caret-offsets-cache`, from master 4d030e94. Ruling `TS-F`
(`docs/superpowers/specs/2026-09-23-text-seam-design.md`). Class M, no divergence label. Evidence: Alloy's
`METALUI_TRACE_SHAPING=1` traces (#419, record 406) on MetalUI 2d9259c5.

## What was found

- **Callers of `caretOffsets`.** `TextField.geometry` (`Sources/MetalUI/TextField.swift`, `system.caretOffsets(shown, ...)`,
  line 431 at 4d030e94, and line 441 while composing) is called by `prepaint` (line 486) and by `paintText` (line 587): twice a
  key and twice a frame, each through `traceBypass` and a fresh `CTTypesetter`. A vertical field's
  `MultilineText.geometry` -> `TextEditor.lineModel` (`TextEditor.swift:262`) calls it per wrapped line in each phase; the
  code view per line it draws (`Code/CodeLineLayout.swift:380,393`); selectable text per run (`SelectableText.swift:116`).
- **The empty unfocused composer** asked for `""` twice a frame for the same reason, and cost nothing but the trace line:
  `Shaper.caretOffsets` returns `[0]` for an empty string, but `CoreTextTextSystem.caretOffsets` (and the portable twin) wrote
  its `uncached:` entry first. Fixed by answering `""` before any lookup or trace.
- **`ShapingCache` bound.** Only the stale sweep above 256 entries; a live set of any size, and anything touched in the last
  three frames, was never evicted.

## What changed

- `ShapingCache.caretOffsets(_:font:)` and `PortableTextSystem.caretOffsets`: a `(string, font)` cache with the generation
  stamp and the lifetime of the shape dictionaries (CoreText: bounded as below; portable: two frames). Not derived from the
  cached `CTLine`: its last-boundary offset differs by an ulp and a hard break ends it, so the same function runs on a miss and
  every answer is bit-identical (`cachedCaretOffsetsAreTheShapersOffsets`, `portableCaretOffsetsAreTheOldComputationsOnAMissAndOnAHit`).
- Bound: `Table` (a dictionary plus its running cost) with `bound(entries:cost:)`, `entryCap` 4096, `costCap` 512 KiB per
  dictionary (`storage`, `styledStorage`, `caretStorage`), applied in `endFrame` after the stale sweep and, at twice a cap, in
  the frame (`trimInFrame`). Oldest generation first, arbitrary within one. `fonts`/`resolvedFonts` stay unswept: one entry per
  distinct font request.
- The trace lists a caret lookup as a hit or a miss `"…"(caretOffsets <font>)`; `uncached:` is the portable styled `layOut` only.
- `package` counts on `ShapingCache` for tests and the probe (`storageCount`, `styledStorageCount`, `caretStorageCount`,
  `registeredFontCount`, `resolvedFontCount`).

## Measurements

Release builds, CoreText text system, master 4d030e94 (`caret-base`) against the branch, interleaved, three runs each, the
probe `Tests/G48Probe` (kept out of the commit: the G47 probe's chat shape with a long transcript, a composer, a streaming
mode, a 1M-row table and a fill mode).

| Fixture (150 keys) | master | branch |
| --- | --- | --- |
| Single-line composer, ms/key (median of runs) | 1.27, 1.82, 1.53 | 1.24, 1.05, 1.08 |
| caret lookups / key | 2 uncached typesets | 1 typeset (the stroke), 1 hit |
| Vertical composer (12 lines), ms/key | 2.46, 2.49, 2.46 | 1.40, 1.38, 1.45 |
| caret lookups / key | 20 uncached typesets | 0.56 typesets, 0 uncached |

- **Streaming, 1500 frames** (200-message transcript, a streaming paragraph, a scroll every 40 frames, a key a frame):
  `phys_footprint` +237 and +239 MiB on master, +254 and +259 on the branch; live malloc blocks +14.4k and +13.8k on master,
  +14.8k and +14.8k on the branch; the cache holds 222 shaped and 230 caret entries and one font at the end. **The growth is the
  same on both sides and is not the shaping cache** (about 450 entries); it is not explained here and belongs to whoever owns
  the frame's other retained state. The cap does not bind in this run, by design: the live set is 408 lookups a frame.
- **Table, 1M x 10, 600 scroll steps:** 830 lookups a frame (470 distinct entries), 7.6 ms vs 8.3 ms a step (no caret
  offsets in a table; within noise).
- **Entry weight** (the fill mode): 4096 20-byte labels with their caret lines +13.2 MiB malloc; 4096 120-byte lines +34 MiB; 1024
  1000-byte paragraphs +53 MiB (about 50 bytes a source byte). Worst case at the caps: about 13 MiB (labels) to about 25 MiB
  (paragraphs) a dictionary after a frame, twice inside one.

## Tests (+13 net; mutation-checked, each killed by the test named)

`ShapingCacheBoundTests` (8): at-or-below-cap working set never re-misses; over-cap re-shapes the overage and no more
(36 of 100 under 64, every frame); least recently touched goes first; a streaming paragraph plus a scrolling list stays under
the cap after every frame and under twice inside one; weight bound; font memos; cached offsets equal `Shaper.caretOffsets`
(RTL, Hebrew, combining marks, ZWJ family, flags, tab, CJK, two sizes); one typeset per string in use. `PortableCaretCacheTests`
(2). `CaretOffsetsCacheTests` (3): a focused field typing 20 keys typesets once a key and takes the uncached path 0 times; an
empty unfocused field across 30 frames of other text changing asks 0 times; an idle field with text typesets once.
`aCaretOffsetsCallIsReportedAsUncached` became `aCaretOffsetsCallIsACachedLookupTheTraceCanSee`. Mutations (13): the caret cache not
storing (CoreText, portable); the empty guard removed (both); the key leaving out the font; the portable `endFrame` not
filtering; eviction newest-first; `endFrame` not bounding; `trimInFrame` removed; cost ignored (two forms); a hit not re-stamping;
the system bypassing the cache. Caret placement, click-to-caret, selection and IME ran through the unchanged field suites.
Full run: root 7369 tests in 80 suites green (`--build-system native`, `--no-parallel`). Steady-frame and allocation pins
unchanged (no pin moved in the full run).
