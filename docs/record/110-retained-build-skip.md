# 110 — Retained build skip (C14b-2)

Branch `perf/retained-build-skip` from `fb9a7e42`. Not a plan task: item C14b-2 of the gpui-gap priority list (user request
2026-10-02), the carried half of record §109. Spec `docs/superpowers/specs/2026-10-13-retained-build-skip-design.md`; rulings
`RK-A`…`RK-L` in `docs/superpowers/2026-10-13-retained-build-skip-decisions.md` (next unused `RK-M`); probe
`docs/probes/retained-build-skip/`. Divergence labels reserved 405–414: **none taken**.

**Status: DESIGN ONLY (2026-10-13).** Nothing is built; the Record phase fills §2 onward.

## §1 The measurement (design phase, `fb9a7e42`, 2026-10-13, shared Mac)

The graft the design of `SB-N` assumed and `SB-AE` called untested, prototyped as an experiment patch
(`docs/probes/retained-build-skip/graft-cost.patch`, README there): per outermost `.equatable()` occurrence of the bracket
fixture, release: **build 72.5 µs, graft of its rows 9.7 µs (13 %)**, 27.2 nodes, 7392 occurrences (three arms, `--quick`). About
1.4 ms of build and 0.19 ms of graft per drag frame of 6.0–6.4 ms. The graft omits the journal and id remapping (`RK-A`).
`.value` last drag frame: measureCalls 52, cacheHits 331, cacheMisses 162, rects 182, glyphs 550, images 6, elementPaints 178, hits 32;
`.panels` elementPaints 110, hits 34, ineligible 1; `.environment` elementPaints 1000, hits 21 (the counters of `fb9a7e42`, equal to §109 §13's).

## §2 What the design decided

See the rulings: the graft forces prepaint replay because a skipped build leaves no element payload (`RK-B`); the paint-only
ambient is decided optimistically and checked exactly at paint with a counted redo (`RK-C`, `RK-D`); translated replay only at a
power-of-two scale and whole device pixels (`RK-G`); `drawText` has a criterion fixed beforehand (`RK-I`); the ceiling is -28 %
and the item is not expected to bring MetalCreator's frames under 16.67 ms alone (`RK-L`).
