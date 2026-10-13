# Performance baselines re-measured — design

Item 9b of the gpui-gap priority list (user request 2026-10-02; **not a plan
task**), the agent-doable half of item 9. Branch `perf/baselines` from
`848ee029`. Rulings: `docs/superpowers/2026-10-13-perf-baselines-decisions.md`
(prefix `BL-`). Record: `docs/record/105-perf-baselines.md`.

## Why

CLAUDE.md calls record §07 "most figures stale". §07's tables were taken on the
deleted CSS engine (`computeLayout`, stage 9) and on a demo tree that has since
changed shape; MetalCreator reported ~0.5 ms per node in release and 2.5–3 ms in
debug and ~15 ms per drag frame for 20 nodes (~43% layout). Branch
`perf/incremental-invalidation` (C14) changes these numbers; this item is its
**before**.

## What is measured, and how

1. **Wall clock, dated, never a pin.** `docs/probes/perf-baselines.sh
   [release|debug] [--quick] [scenario]` builds two throwaway harnesses in a
   scratch directory against this checkout and prints a TSV: the layout kernel
   alone over §07's two shapes (`docs/probes/perf-layout`: the checkout's
   `MetalUICore`/`MetalUILayout` sources linked into a package of its own, so the
   `package` work counters are readable), and whole frames through the public
   `MetalUITesting` API (`docs/probes/perf-harness`): two branching trees, the
   real `demoContent()`, a windowed `List` at 40 / 500 / 100,000 rows, and 20
   draggable nodes under a drag. No `Sources/` change, no new test.
2. **Counts, the durable observable.** `FrameWork` (HT-I), `LayoutTree.
   lastNativeLayoutWork` (SA-M), the work literals of the suite's own
   benchmarks and the env-gated measure tests, read from one unfiltered native
   run.
3. Every figure carries date, commit, machine, configuration and command; a
   median of three whole-process runs (each a median/min of several reps); the
   machine's load average, because other workflows share it.
4. A claim that cannot be re-measured is **unmeasured**, never carried.

## Not in scope

No optimisation, no test pin of a time, no `Sources/` hook. The text oracle
`METALUI_*_MEASURE` tests measure CoreText agreement, not cost, and are not
performance figures.
