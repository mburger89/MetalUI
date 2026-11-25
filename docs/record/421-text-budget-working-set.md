# 421 - the text budget bounds stale entries, never the working set (G48-B)

Date: 2026-11-25. Branch `fix/g48b-text-budget-working-set`, from master e2abf48f. Ruling `TS-G`
(`docs/superpowers/specs/2026-09-23-text-seam-design.md`). Class M, no divergence label. Evidence: Alloy re-measured after
#427 (record 411): typing in the composer went from 95 misses in 28 frames to 546 in 30 (3.4 to 18 a frame), each key still
shaped at four widths.

## What was found

Record 411's revision sized one budget (1024 entries, 192 KiB) at 2.4 times the largest live set, each fixture measured by
itself, and applied it to everything the cache held, the current frame's entries included. A window with a Table of a big
file, a transcript with a streaming reply, a code view, a file tree and a composer in one text system has a live set none of
those has alone. The probe's `combined` mode (a 1M x 10 table, a 300-row tree, a 5k-line code view, a 200-message transcript
with a streaming reply and a composer, scaled by `BIGK`):

| `BIGK` | live set (entries, p50) | misses/frame, before #427 / master / this | evictions/frame master |
| --- | --- | --- | --- |
| 1 (1800x900) | 840 | - / 3.0 / (not rerun) | 3.0 (the cap at 1024 binds only as the set approaches it) |
| 2 | 1294 | 1.87 / **273.3** / 1.87 | 273.3 |
| 3 | 1654 | 1.00 / **633.1** / 1.00 | 633.1 |

At `BIGK` 2 and 3 master held 1024 entries and **0 caret entries**: the shared budget's oldest-generation cut took the
caret table whole (it is the newest and smallest), so every key re-typeset and every frame re-shaped the overage. Typing
25 keys: 270 misses a key on master at `BIGK` 2, 0 here. This is the thrash the single-fixture measurement could not see; it
is not caret lookups newly counted as misses (the composer alone is unchanged, below).

## What changed

- `ShapingCache.bound` offers only **stale** entries (last touched before the previous frame) to the eviction; the current
  and the previous frame's entries are the working set and stay. The budget counts the stale ones. `endFrame` and the in-frame
  trim both use it; an in-frame scan that found nothing arms the next one a quarter-budget of inserts later.
- `TextCacheBudget.rank` and the in-frame ordering went (`appendStaleStamps(before:)`, `count(inGeneration:)`,
  `evict(olderThan:andUpTo:)`); `PortableTextSystem` lost its budget and its `entryLimit`/`costLimit` init: its two-frame
  lifetime is the working set and leaves nothing stale to bound.
- `package` access for `ShapingCache(entryLimit:costLimit:)`, `hits`, `misses`, `caretMisses`, and `evictionCount` (new).
  `MetalUITestingTests` depends on `MetalUIText` on macOS.

## Memory under the new rule

Working set (the app's, two frames' union) plus at most 1024 stale entries and 192 KiB of stale weight: about 9 MiB of heap
at the measured 50 bytes a weight unit, 11 MiB inside a frame, as in record 411's worst case but on top of the live set. The
combined window at `BIGK` 3 ends at 28.3 MiB live malloc and +54 MiB `phys_footprint` (master 23.5 MiB and +60 at the same
size: the bytes are not the cache's).

## Measurements

Release, CoreText, 60 stream+key frames and 25 key-only frames after warm-up; interleaved three runs where noted.

| Fixture | before #427 | master (#427) | this |
| --- | --- | --- | --- |
| combined `BIGK` 2, misses/frame (stream + key / key only) | 1.87 / 0.00 | 273.3 / 270.0 | 1.87 / 0.00 |
| combined `BIGK` 3 | 1.00 / 0.00 | 633.1 / 632.0 | 1.00 / 0.00 |
| combined `BIGK` 2, ms/frame, 3 runs | 26.0, 35.2, 25.1 | 42.3 (one run, first build) | 35.8, 25.6, 24.8 |
| combined `BIGK` 2, `phys_footprint` growth, MiB | +51.3, +73.1, +54.8 | +58.0 | +59.0, +56.6, +52.6 |
| composer alone, misses / caret lookups per key | 1.0 / 2.0 uncached | 2.0 / 1.0 | 2.0 / 1.0 |
| composer alone, ms/key, 3 runs | 1.03, 1.03, 1.04 | 0.84, 0.90, 0.89 | 0.98, 0.93, 0.92 |
| table 1M x 10, misses/frame | 20.0 | 20.0 | 20.0 |
| transcript, misses/frame | 2.0 | 3.0 | 3.0 |

The composer alone is the same on master and here, so Alloy's 3.4 to 18 was the combined window's thrash. The four widths a
key is shaped at are unchanged by this and are the field's, not the cache's (`misses` 2.0 a key counts the shape at the field
width and its measure). The master `BIGK` figures are from the first probe build (single runs); the base and this were
interleaved. Frame times on this machine (load 30+) spread by 40 percent between identical runs; read the misses, not the ms.

## Tests

`SharedTextBudgetTests` (1, macOS): the combined window with a budget of 64 and a live set of 313 stops missing once warm, at
most 4 misses a frame (the new word and the typed line); fails on master-style bounding (misses and the live-set precondition).
`ShapingCacheBoundTests` 9 -> 10: `aWorkingSetOverTheBudgetReShapesTheOverageAndNoMore` became
`aWorkingSetOverTheBudgetIsNeverEvicted` (0 misses, not 36 a frame), `theFrameBeforeIsTheWorkingSetToo` added, and the
streaming, pool-sharing and weight tests now age their entries to stale before they expect the bound (the rule applies to
stale entries only). `PortableCaretCacheTests` 3: the portable budget test became `thePortableTablesKeepTheTwoFramesALargeFrameLooksUp`.
Mutations, each killed: protection off (`protectedFrom` past the current frame: the combined test and six bound tests fail);
only the current frame protected (the combined test and `theFrameBeforeIsTheWorkingSetToo` fail).
