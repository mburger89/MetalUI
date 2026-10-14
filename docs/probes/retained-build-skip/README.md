# Retained build skip (C14b-2): graft cost probe

`graft-cost.patch` (applies to `fb9a7e42`; an experiment, never merged) measures, in situ on the bracket fixture, what
`RK-A` rules on: the wall time of each **outermost** `.equatable()` occurrence's build recursion
(`EquatableComponent.requestGroupLayout`, from after `enterComponent`'s content memo to the return of `finishComponent`)
against the wall time of copying that occurrence's layout rows into a scratch `LayoutTree`
(`LayoutTree.experimentGraftCost`: `childLists` with an index shift, `layouts`, `measuredWidths`, and the `nativeNodes`,
`leafKeys`, `spacerAxes`, `nativeParents` dictionary rows — every table `appendNode` and the registrars fill).

Run: `git apply docs/probes/retained-build-skip/graft-cost.patch && RK_EXPERIMENT=1 zsh docs/probes/perf-baselines.sh release --quick bracket`
(the harness prints one `RK_EXPERIMENT` line at exit; revert with `git checkout Sources`).

Recorded output (2026-10-13, MacBookPro18,2 / M1 Max, release, shared Mac, three arms of `--quick` = 6 reps x 21 drag frames,
nested occurrences not double counted):

    RK_EXPERIMENT frames=1 calls=7392 nodes=200927 buildMs=535.974774 graftMs=71.896987

Per outermost occurrence: **72.5 us build, 9.7 us graft (13 %), 27.2 nodes**. (`frames=1` is a defect of the probe's frame counter,
the `Frame` object being reused; the per-frame figure is derived: about 29 occurrences hit per drag frame in the three arms'
last frames, so about 1.4 ms of build and 0.19 ms of graft per frame.) The same run's drag medians (instrumented, so not a
baseline): `.value` 6.377, `.environment` 7.532, `.panels` 6.623 ms per drag frame.

What the probe does **not** measure: the `StateTable` journal's re-application, the element payload problem (`RK-B`), id remapping
of the `hiddenNodes`/`lowering` records, or the signature rows. Lane 2's step 1 re-takes it with the journal included (`RK-J`).


## Prepaint replay A/B (lane 1, `RK-J` gate, `RK-W`)

`zsh docs/probes/perf-baselines.sh release bracketab` (and `debug --quick bracketab`) runs the bracket node drag (`.value` and `.panels`) with
prepaint replay **off** (`METALUI_RETAINED_PREPAINT=0`, read when each window is made) and **on**, alternating inside one process for eight
rounds of fourteen drags, so the two arms see the same machine; it prints each arm's median and minimum drag frame in wall and thread-CPU
milliseconds and the last frame's work line (now with `elementRequests`, `elementPrepaints`, `skippedPrepaints`, `prepaintHits`,
`prepaintIneligible`, `redos`, `translated`). A cross-process comparison against `fb9a7e42` is `git archive fb9a7e42 | tar -x -C <dir>` and
the same script from there; on this shared Mac it moved by 2 ms between runs, which is why the in-process alternation is the reading.
