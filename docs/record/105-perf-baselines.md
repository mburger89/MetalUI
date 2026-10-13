# 105 — Performance baselines re-measured (`BL-`, item 9b)

Branch `perf/baselines` from `848ee029`. **Not a plan task**: item 9b of the gpui-gap priority list (user
request 2026-10-02), the agent-doable half of item 9. Spec
`docs/superpowers/specs/2026-10-13-perf-baselines-design.md`; rulings `BL-A`…`BL-C` in
`docs/superpowers/2026-10-13-perf-baselines-decisions.md` (next unused `BL-D`). No `Sources/` change, no test,
no public declaration, no divergence.

**These are C14's "before".** Branch `perf/incremental-invalidation` (C14) was running in parallel and changes
these numbers; every figure below is `848ee029` (`BL-C`). C14 re-takes them with the same script.

## 1. Conditions, for every wall-clock figure

| | |
|---|---|
| Date | 2026-10-13 |
| Commit | `848ee029` (master after PR #76) |
| Machine | `MacBookPro18,2`, Apple M1 Max, macOS 27.0.1, Apple Swift 6.4 (swiftlang-6.4.0.33.1) |
| Command | `zsh docs/probes/perf-baselines.sh release` ×3 and `zsh docs/probes/perf-baselines.sh debug --quick` ×3 |
| Reported | the median of the three whole-process runs; each run is a median of 21 reps (`--quick`, used for debug: 5 for trees, 20 for the demo and lists); the range of the three in brackets |
| Load | **not uncontended.** Other workflows built and tested on the same Mac throughout. `uptime` at the start of each run: release 31.2 / 31.9 / 37.9, debug 25.8 / 9.8 / 8.4 (load averages). Read every time as an upper bound; the work counts are exact |

Release is `swift build -c release`; debug is `swift build` (the default `-Onone`). The harnesses are outside the package
(`BL-A`): `docs/probes/perf-layout` links the checkout's `MetalUICore`/`MetalUILayout` sources into a package of its own
so `LayoutTree.lastNativeLayoutWork` is readable; `docs/probes/perf-harness` drives whole frames through the public
`MetalUITesting` API (`TestWindow`, `FrameWork`) — a frame there is the real `Window` build, layout, prepaint and paint
over a headless platform and renderer, so it excludes GPU encoding and presentation. A time is never a test pin.

## 2. Layout kernel alone — §07's two shapes, rebuilt on the native kernel

`LayoutTree.computeNativeLayout` over alternating horizontal and vertical linear stacks of 10×10 leaves at an 800×600
proposal. **A different instrument from §07's** (that timed `computeLayout`, the CSS engine stage 9 deleted), on the same
node counts (`BL-B`).

| tree | nodes | release median [range] | us/node | debug median [range] | us/node |
|---|---|---|---|---|---|
| depth 12, branch 2 | 8,191 | **73.1 ms** [69.2–95.0] | 8.9 | **398.8 ms** [370.9–400.4] | 48.7 |
| depth 10, branch 3 | 88,573 | **416.3 ms** [377.4–593.9] | 4.70 | **1,898.5 ms** [1,845.3–1,921.9] | 21.4 |

Work, exact and identical in every run: 8,191 nodes: `measureCalls=32640 cacheHits=118474 cacheMisses=67603`; 88,573
nodes: `measureCalls=237169 cacheHits=629156 cacheMisses=356705`.

**Cost per node is not flat, and the counts say why.** 8.3 measurement bodies per node on the small tree against 4.0 on the
large one. Per measurement body (cache miss) the two agree: release 1.08 us and 1.17 us, debug 5.9 us and 5.3 us. The unit of
cost is the cache miss; per-node figures follow the tree's shape.

**Old against new (§07, 2026-08-29, CSS engine, MacBookPro18,2, macOS 26.6.2):**

| tree | §07 debug → now | §07 release → now |
|---|---|---|
| 8,191 | 362.8 ms (44.3 us) → 398.8 ms (48.7 us), +10% | 41.6 ms (5.08 us) → 73.1 ms (8.9 us), +76% |
| 88,573 | 3,467.6 ms (39.2 us) → 1,898.5 ms (21.4 us), −45% | 414.5 ms (4.68 us) → 416.3 ms (4.70 us), +0.4% |

Reason, partly known: the engine is different, the trees' interior nodes are different (a styleless CSS flex box against a
proposal linear stack), and the machine was contended. §07's "flat from 8k to 88k, ~40 us debug / ~5 us release" **no longer
describes the kernel**: it is flat per cache miss, not per node. The old rows are kept in §07 under a pointer here.

## 3. A whole frame over the same shapes (public API)

`Branch` is a `Component` per interior node (the only recursive spelling the public API allows: `AnyElement` is not an
`Element`) inside `HStack`/`VStack`, leaves `Color.blue.frame(10×10)`; one `Component` and one `.frame` layer per leaf add
nodes the table above does not have. Window 800×600, scale 2. "cold" is `TestWindow` open (build, layout, paint of frame 0);
"warm" is `setNeedsRedraw()` + `tick()`.

| tree | release cold / warm median | us per element (warm) | debug cold / warm median | us per element (warm) |
|---|---|---|---|---|
| depth 12, branch 2 (8,191) | 168.2 / **206.5 ms** | 25.2 | 610.8 / **727.1 ms** | 88.8 |
| depth 10, branch 3 (88,573) | 1,570 / **1,980 ms** | 22.4 | 4,736 / **6,254 ms** | 70.6 |

Release warm ranges 183–265 ms and 1,893–2,527 ms; debug 708–764 ms and 6,029–6,334 ms. Work per frame (exact):
8,191: `builds=1 measureCalls=4096 cacheHits=151115 cacheMisses=71700 rects=4096`; 88,573: `builds=1 measureCalls=59049
cacheHits=866326 cacheMisses=415755 rects=59049`. §07's own whole-frame row (2026-08-27: 51.6 / 520.7 ms release, 369.5 /
3,540 ms debug, legacy tree) is not comparable (different tree, deleted engine) and is not carried.

**Layout is a minority of the frame.** Taking the kernel-only time of §2 against the frame: release 35% (8,191) and 21%
(88,573); debug 55% and 30%. The frame's layout run has 71,700 / 415,755 cache misses against §2's 67,603 / 356,705, so the
comparison is approximate (+6% / +17% more bodies in the frame's tree).

## 4. The real demo tree and the windowed `List`

`demoContent()` (`MetalUIDemoContent`), 920×560, scale 2, dark, 200 warm renders (release) / 20 (debug) after 10 warm-ups:

| | release | debug |
|---|---|---|
| cold (open) | 74.6 ms [58.9–89.3] | 235.9 ms [229.2–236.5] |
| warm median | **1.458 ms** [1.421–1.487], min 1.346–1.428 | **8.185 ms** [8.142–8.324] |

Work: `builds=1 measureCalls=42 cacheHits=352 cacheMisses=357 rects=23 glyphs=464`. §07's last demo figure (2026-09-10,
`2457da8`, release) was 1.652 / 1.637 ms for a copy of the demo tree with a 40- or 500-row list in it; **today's
`demoContent()` is a different tree** (the list moved out, later milestones changed it), so the pair reads 1.65 → 1.46
(−12%) without being a like-for-like change. The 2026-09-10 `StateTable` resident counts (165 / 63) were not re-taken: that
harness copied the demo into the test target, and `StateTable.count` is internal (unmeasured, not carried).

`List` over 40, 500 and 100,000 rows in a 420×370 `ScrollView` (proposal vocabulary, `rowHeight: 28`), rows `Text`:

| rows | release cold | release warm | debug cold | debug warm | warm work (all three, exact) |
|---|---|---|---|---|---|
| 40 | 3.7 ms | **0.762 ms** | 13.3 ms | **4.637 ms** | `measureCalls=17 cacheHits=69 cacheMisses=86` |
| 500 | 46.1 ms | **0.766 ms** | 133.4 ms | **4.672 ms** | the same |
| 100,000 | **8,663 ms** [8,327–11,429] | **0.900 ms** | **29,003 ms** [28,819–29,597] | 14.695 ms | the same |

The warm cost is flat in row count in work (`O(window)`, TB-K) and in release time. **The 100,000-row warm figure includes
the harness building a 100,000-element data array every frame** (`(0..<n).map`, in the content closure): ~0.14 ms release
and ~10 ms debug of it, a harness artefact, not the `List`'s. The first 40-row cold in the first release run (39 ms) paid
the process's font warm-up; the median is the later two.

**The 100k cold frame (§07, `TB-K`, 2026-09-01):** 41.86 s debug / 16.84 s release → the suite's own
`aListsWorkIsTheSameFor100kRowsAsFor500` now prints **33.5 s debug** (`METALUI_RUN_100K_LIST_TEST=1`, one run, contended;
−20%); the harness reads 29.0 s debug and 8.7 s release for the proposal spelling. **The release figure is not like-for-like
with 16.84 s** (the test's tree is the legacy `Box`/`ScrollView`/`List` spelling; running the test itself in release was not
done): treat the release cold at 100k as **8.7 s for the proposal spelling and unmeasured for the test's spelling**. M3's
exit criterion is unchanged: scrolling yes, appearing no.

## 5. Per-node cost and the drag frame (MetalCreator's report)

MetalCreator reported ~0.5 ms per node in release and 2.5–3 ms in debug, and ~15 ms per drag frame for 20 nodes, ~43% of it
layout. **Unmeasured as stated: their scene is not in this repository.** What is measured:

- Per element, warm, branching tree (§3): **22–25 us release, 71–89 us debug**, 20–40× below the report. Their nodes carry
  text, state, gestures and effects this tree lacks.
- A 20-node drag (`drag20`: each node a padded `VStack` of `Text` and a colour, `.background`, `.offset`, `DragGesture`,
  one node dragged in 1-px steps; 800×600, scale 2, dark): **1.144 ms per frame in release** [1.055–1.288], **5.434 ms in
  debug** [5.341–5.715], work per frame `measureCalls=140 cacheHits=260 cacheMisses=341 rects=40 glyphs=110`. About 57 us
  (release) / 270 us (debug) per node, including 110 glyphs.
- The layout share of that frame is **unmeasured** directly (the frame is not split by phase). By the kernel's cost per
  measurement body (§2: ~1.1 us release) its 341 bodies are ~0.4 ms, about a third of the 1.14 ms, an estimate resting on
  one transferred constant.

So the ~15 ms figure is not reproduced by 20 simple nodes; a reproduction needs MetalCreator's scene or a phase split inside
`Frame` (a package-level hook, ruled under `BL-` if C14 wants one).

## 6. Work-counter benchmarks, re-read at `848ee029`

One unfiltered native run, `swift test --build-system native --no-parallel --skip AppKitPresentationTests` with
`METALUI_RUN_100K_LIST_TEST=1 METALUI_STORE_ALLOC_MEASURE=1 METALUI_COMPONENT_ALLOC_MEASURE=1`: **3573 tests in 3 suites
passed** (3582 less the nine `AppKitPresentationTests`, skipped, see §8), 0 `error:`, `FR-J no-argument frame:
succeeded=true`. The pins passed unchanged, so these literals still hold:

| pin | value at `848ee029` |
|---|---|
| warm `demoLikeRows`, `LayoutTree.lastNativeLayoutWork` (SA-M, `MeasurePerformanceTests.demoLikeRowsWarmWork`) | 17 measure calls / 103 hits / 120 misses, the same at 40 to 100,000 rows |
| `theOverlayCostIsLinearAndCounted` (GT-A), N = 20 and 100 `Text` overlays per camera frame | 1 build, N+1 measure calls, N+1 hits, N+2 misses, 2N seam measures, N `placeGlyphs`, 0 atlas / raster / texture work (**C14's "before"**) |
| `FrameWork` (HT-I), `RasterCache.lastTexturesMade` (PF-G), backdrop pass counters (BB-E) | their pins pass; their literals live in `HarnessWorkTests`, `RasterAnchorTests`, `BackdropRenderTests` |

Allocation measures (printed, not asserted; `CloseoutTests`), three settled frames each:

| measure | now | §66 §4 (older) |
|---|---|---|
| proposal preview | 18,546 allocations, 1,684,329 B, 12 store entries | 18,363 / 1,658,448 B |
| legacy demo | 83,297 / 9,691,280 B | 82,121 / 9,104,975 B (+1.4% / +6.4%) |
| 40 framed / 80 framed rectangles | 13,101 / 25,872 | 13,107 / 25,881 |
| 40 bare / 80 bare | 9,606 / 18,897 | 9,612 / 18,906 |
| one settled `.frame` layer | 29.00 allocations / 1,959 B | 29 / ~1.9 KB |
| one `Component` per settled frame | **3.00 allocations / 176.0 B** (80.42 against bare 77.42) | no figure recorded in §78; unmeasured before |

The text oracle `METALUI_*_MEASURE` tests (fallback, line emission, content size, truncation, bidi, line breaking, FreeType,
HarfBuzz, portable oracle) measure agreement with CoreText, not cost, and are not performance figures (not re-run).

## 7. What stays unmeasured

- The 43% layout share of a drag frame, and MetalCreator's 15 ms scene (§5).
- Phase split (build / layout / prepaint / paint) inside a frame: no hook, none added (`BL-A`).
- The 100k cold frame in release for the suite's own legacy-spelled tree (§4).
- GPU encode and present: the headless renderer draws nothing.
- Windows and Linux: macOS only.
- The identity-path-construction table (§07, 2026-08-27) and its linked-list-against-array counterfactual: the
  array form no longer exists to time against.

## 8. Must-hold checks

- `swift build --build-system native --build-tests`: 0 `error:`, the only `warning:` SwiftPM's deprecation notice;
  `swift build --build-tests`: 0 `warning:`.
- **The unfiltered run could not complete as asked.** The screen was locked and the display asleep
  (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`); `AppKitPresentationTests.appKitCancelledDialogArrivesAsQueuedInput`
  blocked in `NSOpenPanel.init()` for over three minutes with the process idle. Under the rule in the task, that run was killed
  (this lane's own PID only) and re-run with `--skip AppKitPresentationTests`. The suite's 3582 is therefore not read here;
  3573 is. The nine skipped tests are environmental (a sheet needs an unlocked screen), not touched by this change.
- No `Sources/` or `Tests/` change: pixels (the fourteen images) and `Expected.swift` cannot move; not re-run.
- Typecheck guards and `swift package clean`: no new guard, no stored-property change.
