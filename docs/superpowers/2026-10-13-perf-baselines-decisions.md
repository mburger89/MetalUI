# Performance baselines — decisions

Rulings for item 9b of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**). Prefix `BL-`. Spec:
[`specs/2026-10-13-perf-baselines-design.md`](specs/2026-10-13-perf-baselines-design.md).
Record: `../record/105-perf-baselines.md`. Branch `perf/baselines` from
`848ee029`.

**Next unused id: `BL-D`.**

## Carried

`SA-M` (work counters on a branching tree), `HT-I` (`FrameWork`: benchmarks count
work, never time), `PF-G`, `BB-E`, `GT-A`, `TB-K`/`TB-L` (the 100k list), and the
practice "performance tests count work, never wall clock".

## BL-A — wall clock lives in a probe script, never in a test

Timed figures are re-taken by `docs/probes/perf-baselines.sh`, which builds
harnesses **outside the package** (a scratch directory, the checkout symlinked
as `MetalUI`) over public API plus the layout sources; no `Sources/` hook, no
test, no census row. A time is recorded with date, commit, machine, configuration
and command, as a median of three process runs, and is never `#expect`ed.

## BL-B — §07's CSS-engine tables are retired, not re-taken

`computeLayout` and the harness that timed it are gone (stage 9). The canonical
shapes (depth 12 branch 2 = 8,191 nodes; depth 10 branch 3 = 88,573) are rebuilt
on the native kernel, so the new numbers are **a different instrument on the same
shapes** and §07's old rows keep their text with a pointer to §105. The old
"~40 us debug / ~5 us release per node" is not carried.

## BL-C — these figures are C14's "before"

`perf/incremental-invalidation` is running in parallel. Every figure in §105 is
taken at `848ee029` and says so; C14 re-takes them with `perf-baselines.sh` and
the pinned counts.
