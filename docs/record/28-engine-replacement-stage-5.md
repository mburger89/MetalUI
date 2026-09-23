# §28 — Engine replacement, stage 5: `Deferred`'s absolute content as a presentation root

Plan task 7, stage 5 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 5).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md`. Rulings
`LR-CH`…`LR-CO` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-5` from `e5caefb`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-5`.

**Status, 2026-09-23 (PDT): design committed; lane 1 landed (§6, `LR-CQ`); lanes 2 and 3 have not run.** Every
measurement in §2 was taken from a scratch test file
(`Tests/MetalUITests/ZZScratchStage5.swift`, kept in the session scratchpad,
never committed) and one temporary edit to `ListTests.swift` restored from a `cp`
copy; `git status --short` afterwards showed only the design's docs and the
probe.

## 1. Baseline at `e5caefb`

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`, unfiltered: **`Test run with 1617 tests in
3 suites passed after 70.398 seconds`**; 0 `error:`; the only `warning:` is
SwiftPM's `--build-system native` deprecation notice. Goldens 97, guards 77,
working tree clean.

Filtered `DeferredTests|AbsoluteOverlayTests`: **10 tests passed** (9 + 1), every
one legacy-only.

Screen at 01:32 PDT: `appkit-screen-lock-state` printed no
`CGSSessionScreenIsLocked` line, `displayAsleep main: 0`, `displayActive main:
1` — unlocked.

## 2. Measurements

### 2.1 What the exit suites assert

`DeferredTests`: five pass-level tests (no layout, no authority —
`aDeferredFillDrawsAfterAPlainSiblingEmittedLater`,
`aDeferredFillInsideAnActiveClipEscapesToTheWholeSurface`,
`deferredsLayerAndClipBothPopOnExit`,
`deferredOnPrepaintEscapesTheActiveClipForScrollRegistration`,
`nestedDeferredsAllLandOnTheSameRootLayer`) and four tree tests, each rendering
straight into a `Frame` with the tree as root, each with an **in-flow**
`Deferred`: identity (`aNamedChildUnderDeferredResolvesTheSameAsUnderABox`),
paint order and widths (`aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt`),
the inner scroll region at x 30, 150 wide
(`aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting`), and the
deferred marker's y unchanged by a 40pt scroll
(`aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll`).
`AbsoluteOverlayTests`: `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`
— divergence 11 and its `Deferred` differential.

### 2.2 Scratch S5 and S6 — the same trees under both authorities

**S5** (plain `Frame`, tree as root; `rects` are finalized-scene rects with their
masks). The in-flow trees report nothing under `.proposal` but move, because the
native root is centred (`CN-J`):

```
D-hoist        [legacy]   (30,80 40x40) (0,85 30x30)
D-hoist        [proposal] (95,80 40x40) (65,85 30x30)          unlowerable=[]
D-nested-scroll[legacy]   outer (0,0) 50x20 L0; inner (30,0) 150x20 L1
D-nested-scroll[proposal] outer (125,0) 50x300 L0; inner (155,0) 145x300 L1   unlowerable=[]
D-scrolled     [legacy]   (0,300 21x20) (0,320 22x20)
D-scrolled     [proposal] (39,300 21x20) (39,320 22x20)         unlowerable=[]
AO plain       [legacy]   overlay (5,5 22x20) mask (60,30 41x60)
AO plain       [proposal] overlay 0x0; unlowerable=[box.position, box.inset]
AO deferring   [legacy]   overlay (5,5 22x20) mask (0,0 200x200)
AO deferring   [proposal] overlay 0x0; unlowerable=[box.position, box.inset]
```

**S6** (`LayoutDifferential.compare`, `DifferentialRoot`):

```
D-hoist          elements=5 agree=5 dis=[] unlowerable=[] scenes=true hit=true ax=true state=true
D-named          elements=5 agree=2 dis=3 (the ScrollView subtree, 10x200 -> 10x50)   unlowerable=[]
D-nested-scroll  elements=8 agree=3 dis=5 (heights 20 -> 300; x and width agree)       unlowerable=[] hit=false
D-scrolled       elements=6 agree=5 dis=1 (the viewport 22x340 -> 22x60)               unlowerable=[]
```

Every disagreement is a `ScrollView` viewport's scrolling-axis extent (stage 3's
`LR-BC`). The 22×340 legacy viewport in `DifferentialRoot` is why the two scroll
tests need a sized host (`LR-CO`): a viewport as tall as its content cannot
scroll.

### 2.3 The `ListTests` scenario, and a stage-4 claim

`aListInsideADeferredIgnoresTheEscapedScrollersOffset` with both
`renderWindowed(…, authority: .legacy)` calls edited to `.proposal` (sed over the
function, `ListTests.swift` restored from a `cp` copy afterwards, `git status
--short` clean): **passed** (filtered run). Scratch **S7**, the same shape with
diagnostics on and a plain `Box` row:

```
S7 list wrapped=true  [legacy]   unlowerable=[] elementBounds=82
S7 list wrapped=false [legacy]   unlowerable=[] elementBounds=17
S7 list wrapped=true  [proposal] unlowerable=[] elementBounds=82
S7 list wrapped=false [proposal] unlowerable=[] elementBounds=17
```

Record §27 §8.2 ("under `.proposal` a `Deferred` root **aborts** the run") is
therefore wrong at `e5caefb` — `LR-CN`. It was never measured.

### 2.4 Scratch L — the legacy engine's absolute answers

Inside `Box { Deferred { Box(style: s) { Box(30×20) } } }` at 200×100 unless
stated; legacy authority:

```
top5 left5                         (5,5 30x20)
+ margin 7, flexGrow 1, alignSelf  (5,5 30x20)        ignored
auto, minSize.width 50             (5,5 30x20)        min ignored
auto, maxSize.width 10             (5,5 30x20)        max ignored
left/right 5, maxSize.width 10     (5,5 190x20)       ignored
left/right 5, minSize.width 300    (5,5 190x20)       ignored
declared 40, minSize.width 50      (5,5 50x20)        clamped
declared 8x8, padding 10           (5,5 20x20)        BM-4
root border 4, top/left 5, 10x10   (9,9 10x10)        padding-box containing block
root width 100, right/bottom 5     (85,85 10x10)
absolute box as the root           (0,0 10x10)        root insets ignored
Deferred as the root               (0,0 10x10)
```

From S5 (same harness): right 7 / bottom 9, 30×20 → (163, 71); no insets after a
40×20 sibling → (0, 0); top 50 % / left 25 %, 10×10 → (50, 50); stretched
100/90/10/80 with padding 10 → (100, 10) 20×20; a `.relative` ancestor at (0, 30)
with border 3 → (58, 38); a gapped column [10×10, `Deferred` absolute, 11×10]
→ the second box at y 22; and the text arms, 200×200:

```
abs-text-left=0    [legacy] (0,0 196x32)
abs-text-left=50   [legacy] (50,0 196x32)
abs-text-left=150  [legacy] (150,0 196x32)
```

— the legacy engine measures an absolute box against the containing block's full
width (`placeAbsolute`: `available: cb.size`), so at left 150 it overflows by 146.
Every one of these arms reports `[<site>.position, <site>.inset]` under the
proposal authority today.

### 2.5 The probe

`docs/probes/swiftui-overlay-presentation.swift`, `xcrun swiftc`, Apple Swift 6.4
(swiftlang-6.4.0.33.1), macOS 27.0 (26A428). Revision 1 re-run first: exit 0,
**stdout identical to the header's recorded output**. Revision 2 appends group Q
(Q1, Q1c, Q2, Q3/Q3c, Q4/Q4c, Q5/Q5c, Q6/Q6c): exit 0, 29 lines, run twice,
byte-identical (`cmp`); the P and H lines `diff`ed against revision 1's run —
empty. Q's output and reading are in the probe's header; the spec's §2.5
summarises them.

## 3. What the design decided, in one place

| question | answer | ruling |
|---|---|---|
| which `Deferred` is a presentation root? | one whose content node is `.position(.absolute)`; an in-flow one stays transparent | `LR-CH` |
| how is it placed? | element → greedy W on stretched axes (aliased) → padding → a window-sized frame aligned per axis; percentages per axis against the window | `LR-CI` |
| where does it differ from legacy on purpose? | measured content proposed window − inset; stretched below padding keeps its box; min/max on an auto axis reports | `LR-CJ` |
| who reports an absolute box's fields? | its consumer, under the old names; outside a `Deferred` it is removed (stage 10) | `LR-CK` |
| the containing block? | the window; `deferred.containingBlock`/`nested`/`root`/`amended` otherwise (stage 9) | `LR-CL` |
| when is it laid out? | its own run, before the root, in `computeRootLayout` | `LR-CM` |
| divergences 9 / 10 / 11? | survives on both / unchanged, SwiftUI-backed / legacy-only | `LR-CN` |
| hosting, lanes | hosted exit arms; five pass-level tests unparameterised; three lanes | `LR-CO` |

## 4. For the implementer

- **Lane 1 first commits the source**, then 1.1–1.9 red-first where the spec's
  red-before column says so (the red is the pre-lane source: take it with the
  `Deferred` branch disabled in a scratch copy, not by aborting).
- The consumer filter must run **before** `consume`, planning and the
  single-child elision count — **but the frame arm's `legacyFrameLayerDiagnostics`
  keeps the undropped `children.count`** (`LR-CP` item 1; `declared` was built
  from it).
- The placeholder's alias is `lowering.alias(content)` **resolved** — a stretched
  content's element rect is its W, not its own node.
- `inset` values come from the **animated** style; which edges are given, from the
  declared one (`LR-AS`), or lane 3's 3.5 goes red for the wrong reason.
- The census (1.8) is re-derived once, in lane 1, from measured pairs; do not
  predict the six modal ids' rects — measure and attribute them.
- `swift package clean` is not owed by any planned change (internal types only).

## 5. Critic round 1 (design only; `LR-CP`)

The committed design (`7654e63`) attacked in the same worktree; no `Sources/` or
`Tests/` file changed in a commit.

- **Probe re-run, every arm.** `xcrun swiftc docs/probes/swiftui-overlay-presentation.swift`,
  run twice (exit 0 both), stdout byte-identical between runs and against the
  header's P/Q/H lines (`diff` empty). Lock probe at the time: no
  `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`.
- **Scratch `ZZScratchCritic.swift`** (legacy authority, plain `Frame` 200×100,
  root `Box { Deferred { Box(10×10, absolute, right 5, bottom 5) } }` under a
  root frame; deleted after, `git status --short` clean):

  | root | the absolute box |
  |---|---|
  | `.frame(maxWidth: 100)` | (85, 85) |
  | `.frame(maxWidth: 300)` | (185, 85) |
  | `.frame(maxWidth: ∞)` (no clamp) | (185, 85) |
  | `.frame(minWidth: 300)` | (285, 85) |

  The design's containing-block check (border, size) would have lowered the
  first and last rows against the window, silently; `LR-CP` item 2 adds the
  min/max clause, three arms to 1.5 and mutation M1p.
- **Read from source, not measured:** the frame arm's undropped count
  (`LR-CP` item 1, mutation M1o added to 1.4); `withAnimation`'s default curve is
  a spring (`Animation.swift:230`), so 3.5 names `.linear` (item 3); 2.7's
  red-before exists (item 4).
- **Rejected attacks** are listed in `LR-CP` with reasons (`SA-G`, the
  declared-below-padding case, root margin/min/max, M1d, lane size).


## 6. Lane 1 — the presentation root (`LR-CH`…`LR-CM`, `LR-CP` items 1–2; corrections `LR-CQ`)

Commits: `b447c9a` (red first), `1f83f45` (source), `97306d4` (corrections: three
1.5 arms and a stage-8 assertion, M1h's set narrowed) and the commit carrying
this section (M1g's set narrowed, this record, `LR-CQ`).

### 6.1 Suite

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`, unfiltered, at `97306d4`: **`Test run with
1624 tests in 3 suites passed after 64.682 seconds`** (1617 + 7: the seven
`PresentationLoweringTests`; the census and the site roll changed in place);
0 `error:`; the only `warning:` SwiftPM's deprecation notice; the log carries
`FR-J no-argument frame: succeeded=` (guards ran). No golden moved
(`git diff --name-only e5caefb HEAD -- 'Tests/**/*.json'` empty); no guard added
(77).

### 6.2 Red first

`b447c9a`'s tests over `83c6bd1`'s source (filtered to the nine touched tests):
**9 tests failed, 128 issues** — every presentation arm reported `[box.position,
box.inset]`, 1.6's child trapped naming `box.position`, stage 2, and 1.7's two
roots' work differed. Every legacy literal of 1.1–1.3 passed (spec §2.4
reproduced). The three arms and the owning-stage assertion `97306d4` added were
green on arrival (the source already held the behaviour); their red is M1q–M1t
below, each run.

### 6.3 Mutations

Each: committed tree, source copied with `cp`, one edit, `swift build
--build-system native --build-tests` (0 errors), unfiltered `swift test
--build-system native --no-parallel`, source restored from the copy, `git status
--short` empty after every one. Every run printed its summary line (none
truncated); every row is 1624 tests. Arms are named as the test's messages print
them.

| id | edit (file, branch) | issues | reddened |
|---|---|---|---|
| M1a | `lowerPresentation`, trailing-only axis: `plan.factor = 1` → `0` | 6 | 1.1 (`right/bottom px, declared size`) |
| M1b | `lowerPresentation`, vertical axis `extent: window.height` → `window.width` | 6 | 1.1 (`percent`) |
| M1c | `lowerPresentation`: `frame.lowering.alias(node, to: root)` (W) deleted | 15 | 1.1 (`all four, auto size`; `left/right, auto width, declared height`), 1.2, 1.8 `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (agreeing set; disagreeing 2035 vs 2033) |
| M1d | `Deferred.presentationPlaceholder`: the placeholder's alias deleted | 28 | 1.1 (all ten arms, the `Deferred` id), 1.4 (all six arms), 1.8 (2034) |
| M1e | `lowerPresentation`: W's `minWidth`/`minHeight` = padding + border sum | 1 | 1.2 (lowered 20×20) |
| M1f | `lowerPresentation`: padding's `left` → 0 | 78 | 1.1 (eight arms: every arm with a leading horizontal inset), 1.2, 1.3, 1.4 (all six), 1.7 (the presentation's box) |
| M1g | `lowerLegacyNode`: `droppingPresentations` deleted | 9 | 1.1 (`no insets, after an in-flow sibling`), 1.4 (`gapped column`, its third child at y 34; `ScrollView content`), 1.7, 1.8 (2034) — **not** 1.4's `Stack` or `.padding` arms (`LR-CQ` item 2) |
| M1h | `lowerLegacyLayer` frame arm: `droppingPresentations` deleted | 1 | 1.4 (`two-member .frame layer` only; `LR-CQ` item 1) |
| M1i | `reportPresentationContainingBlock`: the border/size/min-max condition made `false` | 7 | 1.5 (`bordered root`, `root width 100 in 200`, `root .frame(maxWidth: 100)`, `root .frame(minWidth: 300)`), 1.6 (exits with success; stderr lacks the line), 1.9 `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (`Deferred (a bordered root over a presentation)`) |
| M1j | `Deferred.presentationPlaceholder`: the nested check made `false` | 2 | 1.5 (`inside a top/left-5 presentation`, `inside a bordered inset(0) presentation`) |
| M1k | `presentationCoversWindow` always `false` | 1 | 1.5 (`inside an inset(0) presentation`) |
| M1l | `planLegacyItems`: `reports.append("position")` deleted | 1 | 1.5 (`absolute in a column, no Deferred`) |
| M1m | `owningStage` `.deferred` → "5" | 1 | 1.6 |
| M1n | `computeRootLayout`: presentations laid out in a `defer` (after the root) | 1 | 1.7 (`a == b`) |
| M1o | frame arm: `legacyFrameLayerDiagnostics` handed `children.count` (dropped) | 5 | 1.4 (`one-node .frame layer`, `two-member .frame layer`) |
| M1p | `clampsOff`: the three `minSize`/`maxSize` lines deleted | 2 | 1.5 (`root .frame(maxWidth: 100)`, `root .frame(minWidth: 300)`) |
| M1q | `owningStage`: `.absolute` → "2" | 2 | 1.5 (the stage-8 assertion, both fields) |
| M1r | `lowerPresentation`: the `maxSize.absolute` report deleted | 2 | 1.5 (`maxHeight on an auto axis`; the owning-stage `#require`) |
| M1s | `lowerPresentation`: the `minSize.percent` report deleted | 1 | 1.5 (`percentage minWidth on a declared axis`) |
| M1t | `presentationCoversWindow`: the border clause over an empty array | 1 | 1.5 (`inside a bordered inset(0) presentation`) |
| X1 | `lowerPresentation`: `length(animatedLeading/Trailing)` → `length(leading/trailing)` (both occurrences each) | 0 | **green** — owned by lane 3's 3.5 (it is spec §7's **M3c**); lane 3's verifier re-runs this exact edit |

M1a–M1p are the spec's; M1q–M1t were the lane-1 verifier's X2–X5 (each green at
`1f83f45`, 1624 passed), re-run here after `97306d4`'s arms; X1 is its X1.

### 6.4 Pixels and screen

`docs/probes/demo-pixels/compare.sh <scratch> e5caefb 97306d4`: every control at
its recorded value (1048576, 1030498, 210027, 0, 1048576, 0; distinct 544 and
216; indicator rects 0), and **all twelve images `differing=0`, scene
identical**. Lock probe at 03:11 PDT: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — locked, so `capture.sh` was not run (not owed).
