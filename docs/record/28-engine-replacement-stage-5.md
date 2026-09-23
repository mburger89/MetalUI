# §28 — Engine replacement, stage 5: `Deferred`'s absolute content as a presentation root

Plan task 7, stage 5 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 5).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md`. Rulings
`LR-CH`…`LR-CO` (design), `LR-CP` (critic round 1) and `LR-CQ`…`LR-CS` (lanes 1–3) in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-5` from `e5caefb`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-5`.

**Status, 2026-09-23 (PDT): all three lanes landed — lane 1 (§6, `LR-CQ`), lane 2 (§7, `LR-CR`), lane 3 (§8, `LR-CS`); the stage is closed in §9–§16, and the Record phase (§17) has updated CLAUDE.md, AGENTS.md, records §03/§04/§05/README and the plan. Only integration (the §28→§29 renumber) is left.** Every
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

## 7. Lane 2 — the exit suites under both authorities (`LR-CN`, `LR-CO`; corrections `LR-CR`)

Commits: `52ff491` (red first: the five scenarios parameterised **before**
hosting, 2.5, 2.7, 2.8, the roll call at 74), `985c443` (hosted; the five
pass-level tests each say why they are not parameterised; headers), and the
commit carrying this section (`LR-CR`, the spec's host row corrected). Tests only:
`DeferredTests`, `AbsoluteOverlayTests`, `ListTests`, `AuthorityCoverage`,
`ZZAuthorityRollCall`.

### 7.1 Suite

At `985c443`, `swift build --build-system native --build-tests` (0 `error:`, the
only `warning:` SwiftPM's deprecation notice), then unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1626 tests in 3 suites
passed after 64.289 seconds`** — 1624 + 2 (2.5
`aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities` and
2.7 `anAbsoluteBoxOutsideADeferredTrapsAProductionProposalFrame`; the six
parameterised in place move no count). The log carries `FR-J no-argument frame:
succeeded=` (guards ran). No golden moved; no guard added (77).
`AuthorityCoverage.expected` **74** (67 + 5 `DeferredTests` + 1
`AbsoluteOverlayTests` + 1 `ListTests`), read back green by
`everyParameterisedScenarioRanUnderBothLayoutAuthorities`. The exit criterion
(spec §8): **5 of `DeferredTests`' 10** under both authorities (the other five
pass-level) and **1 of 1** in `AbsoluteOverlayTests`, plus its exit test 2.7.

### 7.2 Red first

Filtered, `52ff491` over lane 1's source, unhosted, proposal frames with
diagnostics on:

- `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting(_:)` →
  `.proposal`: `inner.bounds.origin.x == 30 → false` (inner x 155, width 145; outer
  x 125 — the native root centred, `CN-J`).
- `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt(_:)` → `.proposal`:
  `scene.rects.first { … == 22 && … == 20 } → nil` (report `[box.position,
  box.inset]`; every rect 0×0 at (0, 0), mask (100, 85) 0×60).
- Green unhosted under both: the identity, hoist and scrolled tests and 2.8.
- 2.5 with lane 1's `Deferred` branch disabled (`guard false, …`, scratch, restored):
  `frame.unlowerableFields.isEmpty` → `[stack.position, stack.inset]` (`.proposal`).
- 2.7 with the `position`/`inset` owning-stage line removed (scratch, restored):
  stderr `MetalUI: box.position has no proposal lowering (plan task 7, stage 2)`.
- 2.5's first draft in a **column** host: `.legacy`, `markerY` 30 against −10 —
  the finding behind `LR-CR` item 1 (`viewportExtent` 300 in a 70pt clip).

### 7.3 Mutations

Each: committed tree (`985c443`), source copied with `cp`, one edit, build (0
errors), unfiltered suite, source restored from the copy, `git status --short`
empty after every one. Every run printed its summary line; every row is 1626
tests.

| id | edit (file, branch) | issues | reddened |
|---|---|---|---|
| M2a | `Deferred.prepaint`: `pass.deferred { … }` removed, `content.prepaintGroup` called directly | 20 | `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting` (both), 2.5 (both; the two hitbox assertions), `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`, `aDeferredScrollViewTakesTheWheelFromAnOverlappingSiblingBeneathIt` (both), `anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath` (both), `withinOneLayerTheLastRegisteredRegionStillWins` (both) |
| M2b | `Deferred.paint`: `pass.deferred { … }` removed | 20 | `aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt` (both), `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll` (both), 2.5 (both: scrim rect, mask, paint order, card), `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt` (both; the portal's mask) |
| M2d | `owningStage`: the `position`/`inset` line's `"10"` → `"2"` | 1 | 2.7 only |
| M2e | `Deferred.requestLayout`: `pass.withoutScrollContext { … }` removed | 2 | `aListInsideADeferredIgnoresTheEscapedScrollersOffset` (both) |

### 7.4 Pixels and screen

`docs/probes/demo-pixels/compare.sh <scratch> e5caefb 985c443`: every control at
its recorded value (1048576, 1030498, 210027, 0, 1048576, 0; distinct 544 and
216; indicator rects 0), and **all twelve images `differing=0`, scene
identical**. Lock probe at 04:02 PDT: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — locked, so `capture.sh` was not run (not owed).

### 7.5 Deferred

Nothing of lane 2's. The erratum to record §27 §8.2 (`LR-CN`) belongs to the
Record phase, as `LR-CN` says.


## 8. Lane 3 — the must-not-move set through real windows (`LR-CO`; corrections `LR-CS`)

Commits: `7c0c414` (`PresentationWindowTests` 3.1–3.6, the two in-flow pins 3.7–3.8
parameterised, `AuthorityCoverage` 74 → 82), `be5c697` (3.3's layout-phase
reading, after M3b as spelled was measured green), and the commit carrying this
section (`LR-CS`, the spec's lane-3 rows corrected, §9–§16). Tests only:
`PresentationWindowTests` (new), `DecorationPaintTests`, `EnvironmentTests`,
`AuthorityCoverage`, `ZZAuthorityRollCall`.

**What the six tests hold, each under both authorities through a real `Window`**
over a `FakePlatformWindow`, each window opened only after the same content's
`LayoutDifferential.compare` report is `try #require`d empty, and each hosted in a
window-sized `DifferentialRoot` except 3.1:

| # | test | holds |
|---|---|---|
| 3.1 | `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheelUnderBothAuthorities` | `demoContent()` as the root of a 920 window, modal up: over the `List` and outside the card the topmost opaque hitbox is the scrim at the window on layer 1; a wheel there is claimed and the list stays at 0 (`IN-W`); a card click keeps the modal, a scrim click dismisses it; then the same wheel scrolls the list by 37 (the separating arm). Pre-flighted in both modal states, through the harness **and** as the frame's root under diagnostics |
| 3.2 | `aPresentationInsideAFadedSubtreeIsStillFadedUnderBothAuthorities` | a presentation at the window's (10, 10), declared in a 0.5-faded box at x 50, paints at half its unfaded alpha (`OM-AA`, divergence 46) |
| 3.3 | `aPresentationKeepsItsDeclaringScopesEnvironmentUnderBothAuthorities` | inside `.environment(\.presentationProbe, 7).theme(.dark).disabled(d)`: dark (a sibling outside, light); disabled → no hitbox, no click, no focus (control: hit, 1 click, focused); the layout-phase reading is 7 |
| 3.4 | `aPresentationsAccessibilityRecordAndFocusMatchUnderBothAuthorities` | the `inset(0)` scrim's "Close modal" record: a `.button`, a root of the tree, geometry the window on layer 1; the card inside focusable, focus survives a frame, a key reaches it |
| 3.5 | `anAnimatedInsetInterpolatesItsValueUnderBothAuthorities` | `withAnimation(.linear(duration: 1))` `top` 10 → 50: 10 at the transition's first frame, **30** at half (required to differ from both endpoints), 50 at the end; pre-flighted in both end states |
| 3.6 | `nestedPresentationsLandOnOneLayerUnderBothAuthorities` | a tooltip presentation inside the `inset(0)` scrim: no report, both hitboxes on layer 1, the tooltip at the window's (5, 5), outranking the scrim there and painting after it (`AP-H`) |

3.7 `aDeferredPortalInsideAFadedSubtreeIsStillFaded(_:)` and 3.8
`aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope(_:)` are the
existing in-flow pins, parameterised: 3.7 pre-flights through the harness before
its proposal window, 3.8 is a plain `Frame` that runs its proposal arm with
diagnostics and requires an empty report.

### 8.1 Suite

At `be5c697`, `swift build --build-system native --build-tests` (0 `error:`, the
only `warning:` SwiftPM's deprecation notice), then unfiltered `swift test
--build-system native --no-parallel`: **`Test run with 1632 tests in 3 suites
passed after 66.710 seconds`** (taken at `7c0c414`; every mutation run below at
`be5c697` printed 1632 too) — 1626 + 6, the six `PresentationWindowTests`; 3.7
and 3.8 move no count. The log carries `FR-J no-argument frame: succeeded=`
(guards ran). No golden moved (`git diff --name-only e5caefb HEAD --
'Tests/**/*.json'` empty); no guard added (77). `AuthorityCoverage.expected`
**82**, read back green by `everyParameterisedScenarioRanUnderBothLayoutAuthorities`,
whose contributing files are now fifteen (`DecorationPaintTests`,
`EnvironmentTests` and `PresentationWindowTests` all sort before
`ZZAuthorityRollCall`). Filtered, the eight lane-3 tests take 2.8 s, 2.6 s of it
3.1 (four 920×920 demo renders of pre-flight and a 920 window).

### 8.2 Red first

The lane is tests-only and its subject landed in lane 1, so the red is the
pre-lane-1 behaviour, taken as lanes 1 and 2 took theirs: `Deferred.swift`'s
presentation `guard` made `guard false, …` in a scratch copy, filtered run,
source restored from the copy, `git status --short` clean. **8 tests, 12 issues**:
every `PresentationWindowTests` arm, both authorities, fails its pre-flight —

- 3.1 `modal true: [stack.position, stack.inset]`;
- 3.2, 3.3 `[box.position, box.inset]`; 3.5 `the end state: [box.position, box.inset]`;
- 3.4 `[stack.position, stack.inset]`;
- 3.6 `[box.position, box.inset, stack.position, stack.inset]` (the tooltip and the scrim).

3.7 and 3.8 green under both authorities, as spec §7 predicted (their
`Deferred`s are in-flow). Over lane 1's source (unchanged since `1f83f45`) all
eight are green.

### 8.3 Mutations

Each: committed tree (`7c0c414` for M3a and the first M3b run, `be5c697` for the rest),
source copied with `cp`, one edit, build (0 errors), **unfiltered** suite, source
restored from the copy, `git status --short` empty after every one. Every run
printed its summary line; every row is 1632 tests.

| id | edit (file, branch) | issues | reddened |
|---|---|---|---|
| M3a | `Frame.pushLayer`: stash `opacityStack` in a static and clear it; `popLayer`: restore it (`LR-CS` item 5 — `opacityStack` is private, and `pushLayer` has no caller but the two `deferred`s) | 4 | 3.2 (both), 3.7 `aDeferredPortalInsideAFadedSubtreeIsStillFaded` (both) |
| M3b | `Deferred.requestLayout`: `pass.withoutScrollContext { … }` wrapped in `frame.withEnvironment(frame.rootEnvironment) { … }` — at `7c0c414` | 0 | **none** — the theme and the gate are prepaint/paint readings `EnvironmentScope` re-pushes around the `Deferred` (`LR-CS` item 1) |
| M3b | the same edit, at `be5c697` | 2 | 3.3 (both; the layout reading `[0]` for `[7]`) |
| M3b′ | as M3b, plus `Deferred.prepaint`'s and `.paint`'s `pass.deferred { … }` each wrapped in the root environment | 12 | 3.3 (both, 4 each: theme, gate, disabled theme, reading), 3.8 `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope` (both; `colour(12)` light), `aDisabledScopeReachesIntoDeferredContent` (clicks 1, focused) |
| M3c | `lowerPresentation`: `length(animatedLeading)` → `length(leading)` and `length(animatedTrailing)` → `length(trailing)`, both occurrences each — lane 1's X1, the identical edit | 2 | 3.5 `.proposal` only (first frame 50 for 10; mid-flight 50, the `#require` stops the arm) |
| M3d | `Frame.pushLayer`: `layerStack.append(activeLayer + Self.rootLayer)` | 3 | 3.6 (both; tooltip layer 2), `nestedDeferredsAllLandOnTheSameRootLayer` |
| M1c | `lowerPresentation`: `frame.lowering.alias(node, to: root)` (W) deleted — lane 1's M1c re-run over lane 3 | 22 | lane 3: 3.1 `.proposal` (4: the hit at the wheel point is the `List`'s region at (240, 455); the list scrolls; the scrim click does not dismiss; the separating arm reads 74), 3.4 `.proposal` (record (80, 85) 40×30), 3.6 `.proposal` (no window-sized scrim hitbox); and lane 1's and 2's: 1.1 (12), 1.2, 1.8 (2), 2.5 `.proposal` |

### 8.4 Pixels and screen

`docs/probes/demo-pixels/compare.sh <scratch> e5caefb be5c697`: every control at
its recorded value (1048576, 1030498, 210027, 0, 1048576, 0; distinct 544 and
216; indicator rects 0), and **all twelve images `differing=0`, scene
identical**. Lock probe at 04:41 PDT: `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1` — locked, so `capture.sh` was not run (not owed).

## 9. What landed — the stage

- **A `Deferred` whose one content node is `.position(.absolute)` is a
  presentation root under the proposal authority** (`LR-CH`): its content lowers
  as element → greedy W on each stretched axis (aliased as the element's rect) →
  padding for the given insets → a window-sized frame aligned per axis (`LR-CI`),
  laid out in its own native run before the root in `computeRootLayout` (`LR-CM`),
  and the `Deferred` hands its parent a 0×0 placeholder aliased to the content's
  element rect, which every lowered container drops
  (`LoweringState.droppingPresentations`, `LR-CK`). An in-flow `Deferred` lowers
  as before; the legacy authority is untouched.
- **Reports by name** where the legacy containing block is not the window
  (`deferred.containingBlock`, `deferred.nested`, `deferred.root`,
  `deferred.amended` — owner stage 9, `LR-CL`), for `minSize`/`maxSize` on an
  absolute box's auto axis (`…absolute`, stage 8, `LR-CJ`), and for an absolute
  box outside a `Deferred` (`position`/`inset` at the consumer, stage 10,
  `LR-CK`).
- **Two deliberate proposal-only answers** (`LR-CJ`), pinned by name: content
  measured at window − inset on an axis with one inset, and a box stretched below
  its padding keeping its inset box.
- **The exit test** (spec §8): 5 of `DeferredTests`' 10 element-level scenarios
  and 1 of 1 in `AbsoluteOverlayTests` under both authorities, plus the exit test
  2.7 — lane 2 (§7). **The must-not-move set** through real windows under both
  authorities — lane 3 (§8).
- **The demo with the modal on lowers with an empty report** (1.8), which removes
  the last `Deferred`/absolute entry stage 6b would have trapped on.
- Divergence 9 survives on both authorities; 10 unchanged (agrees with SwiftUI's
  presentation, P4/P5); 11 legacy-only from here (`LR-CN`). The rows' amendments
  belong to the Record phase.

## 10. Tests per file

1617 at `e5caefb` → **1632** (+15). Guards 77, goldens 97, both unchanged.

| file | change | count |
|---|---|---|
| `PresentationLoweringTests.swift` | new (lane 1: 1.1–1.7) | +7 |
| `PresentationWindowTests.swift` | new (lane 3: 3.1–3.6) | +6 |
| `DeferredTests.swift` | four scenarios parameterised and hosted, 2.5 new, five pass-level tests say why they are not parameterised (lane 2) | +1 |
| `AbsoluteOverlayTests.swift` | divergence 11 parameterised, 2.7 new (lane 2) | +1 |
| `ListTests.swift` | 2.8 parameterised (lane 2) | 0 |
| `DecorationPaintTests.swift`, `EnvironmentTests.swift` | one pin each parameterised (lane 3: 3.7, 3.8) | 0 |
| `LoweringCorpusTests.swift` | the census's modal half re-derived (lane 1: 1.8) | 0 |
| `LayoutAuthorityTests.swift` | the site roll's `deferred` arm (lane 1: 1.9) | 0 |
| `AuthorityCoverage.swift`, `ZZAuthorityRollCall.swift` | 67 → 74 (lane 2) → **82** (lane 3); fifteen contributing files | 0 |

## 11. Red runs, in one place

Lane 1 §6.2 (9 tests, 128 issues over `83c6bd1`'s source); lane 2 §7.2 (two of
five scenarios red unhosted, 2.5 and 2.7 red with lane 1's branch / owning-stage
line reverted in scratch); lane 3 §8.2 (8 tests, 12 issues with lane 1's branch
disabled). **No red-before was taken by aborting the process** (`LR-BX`): every
proposal window was pre-flighted, every trap is an exit test (1.6, 2.7).

## 12. Mutations, in one place

Lane 1 M1a–M1t and X1 (§6.3); lane 2 M2a, M2b, M2d, M2e (§7.3); lane 3 M3a, M3b
(twice), M3b′, M3c, M3d and M1c re-run (§8.3). **Green mutants, each explained**:
lane 1's X1 (owned by 3.5, and red there as M3c) and the first M3b (the spelling
could not reach the phases it was named for; 3.3 gained a layout reading,
`LR-CS`).

## 13. Demo comparisons

Every lane: `compare.sh` against `e5caefb`, all twelve `CN-R` images
`differing=0`, scene identical, controls at their recorded values (§6.4, §7.4,
§8.4). **`capture.sh` was never owed**: the screen was locked at every lane
(03:11, 04:02, 04:41 PDT). No demo look is owed: production runs the legacy
authority until stage 6b.

## 14. Hazards

- **3.1 writes the global `demoModel.showModal`** (and `animationDemoActive =
  false`), restored by `defer`. `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
  sets both explicitly, so order does not matter today; a new demo test that
  reads the model without setting it inherits whatever ran last.
- **3.1 is the slowest lane-3 test** (2.6 s filtered): four 920×920 demo renders
  of pre-flight plus a 920 window.
- **The roll call now reads fifteen files' coverage** and depends on Swift
  Testing's unspecified cross-file order (CLAUDE.md's CI hazard); it still names
  what it had not seen.
- **Every lane-3 scenario records coverage before `try #require(MTLCreateSystemDefaultDevice())`**,
  so a display-less runner fails at the require without the roll call's second,
  misleading failure (the `AccessibilityDefaultsTests` hazard CLAUDE.md lists does
  not grow).
- **The layout-phase half of "a presentation keeps its declaring scope" is pinned
  by one reading** (3.3's `LayoutEnvironmentProbe`); nothing else in the suite
  reads the environment in layout inside a `Deferred`. `LayoutEnvironmentProbe`
  forwards the three phases and does not mirror `Element`'s group hooks (`MC-B`)
  — correct over a single `Box`, not a general wrapper.
- **A proposal-authority regression in a presentation traps in a `Window`** and
  truncates the run with no summary line; the pre-flights exist to make that a
  failure. A new presentation window test owes one (and one per animated end
  state).

## 15. Deferred, each with an owner

Unchanged from spec §10: the four `deferred.*` reports (stage 9); an absolute box
outside a `Deferred`, `Position.relative`, `inset` on a static box, the public
spelling of a presentation's insets (stage 10); `…absolute` and `size.percent` on
an absolute box (stage 8); divergence 11's retirement (stage 9); root placement
(stage 6b); numbering the two `LR-CJ` answers and amending divergence rows 9, 10
and 11 (the Docs phase). Added by this lane: **the real-window capture**, owed
whenever the screen is next unlocked against this branch (not owed for
acceptance: no legacy path changed, and the offscreen twelve read 0).

## 16. For the integrator

- **Record number collision.** This file is `§28`, written against `e5caefb`;
  `master` has since taken §28 for the portable text line (`42b9ab4`). At the
  merge this record becomes **§29** (the renumbering precedent: record §23 §8,
  §25 and §27 headers), and every "record §28" in this branch's spec, rulings,
  test comments and this file must move with it — sweep `grep -rn "§28"` over
  `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md`,
  `docs/superpowers/2026-09-17-engine-replacement-decisions.md` (`LR-CH`…`LR-CS`
  only) and `Tests/MetalUITests/`, leaving portable text's own citations alone.
- **Counts**: 1632 tests on this branch alone (1617 + 15), 97 goldens, 77 guards.
  Merged with `master` (portable text's +8 over 1617): **1640** expected, to be
  measured after `swift package clean`.
- **`AuthorityCoverage.expected` is 82**; its literal and the roll call's
  `#require` move together.
- **Decisions doc**: next unused `LR-CT`.
- **CLAUDE.md (Record phase)**: the `Deferred` paragraph (presentation root under
  `.proposal`), the stage list (stage 5 → record §29, `LR-CH`…`LR-CS`), the
  counts, the roll call's 67 → 82 and its file list, divergence rows 9/10/11
  (record §04), and "no demo look owed until 6b". `AGENTS.md` copied after.

## 17. Record phase (2026-09-23, PDT) — docs pass over `d1f295a..HEAD`

No file under `Sources/` changed in this pass.

**Two lane-2 minor issues fixed, not deferred.** The verifier's lane-2 verdict
flagged two doc drifts, both still present at `1627f7c`: `LR-CO`'s body still
read "a sized column `Box`" for the scroll host after `LR-CR` item 1
corrected it, with no amendment pointer — fixed with an **Amended, stage-5
lane 2** paragraph on `LR-CO`, in the same style as `LR-CP`'s amendments to
`LR-CK`/`LR-CL`; and `ZZAuthorityRollCall.swift`'s first `#require` message
still said "the nine suites" after the contributing count reached fifteen —
fixed to "the fifteen suites" (`Tests/MetalUITests/ZZAuthorityRollCall.swift`
line 56 — the file's doc comment and the 82-scenario literal were already
correct; only this one string had not moved).

**Suite, re-taken.** `swift package clean`, then `swift build --build-system
native --build-tests` (0 `error:`, the only `warning:` SwiftPM's deprecation
notice), then unfiltered `swift test --build-system native --no-parallel`:
`Test run with 1632 tests in 3 suites passed after 67.485 seconds.` The log
carries `FR-J no-argument frame: succeeded=true` (guards ran). Goldens 97
(`git diff --name-only e5caefb HEAD -- 'Tests/**/*.json'` empty). Guards 77
by CLAUDE.md's per-file split, re-counted file by file and matching exactly
(`UnitSafetyTests` 2 guards, 3 `canTypecheck` hits, one a comment). `git
status --short` after the two doc fixes: only the two files above (no
`Sources/` or other `Tests/` file touched).

**Docs updated in this pass**: `CLAUDE.md` (the `Deferred` paragraph gains
its proposal-authority half; the `LR-` next-unused note; the counts block
gains this stage's layer on top of `e5caefb`'s; the SwiftUI-alignment
stage-5 bullet; the roll call's fifteen-file count in the CI-hazards bullet
and the presentation-window trap note; the known-divergences and
declared-but-inert bullets gain this stage's dated sub-clauses; the
human-verification bullet's fourth open look), `AGENTS.md` (copied,
`cmp` clean), `docs/record/04-divergences.md` (a new 2026-09-23 dated
section amending 9, 10 and 11, plus the record §27 §8.2 erratum),
`docs/record/05-declared-but-inert.md` (a new 2026-09-23 dated section
recording that no row changed), `docs/record/03-verified-on-real-hardware.md`
(a new 2026-09-23 dated section for the open capture), `docs/record/README.md`
(the §28 row), `docs/superpowers/plans/2026-09-12-swiftui-alignment.md`
(task 7's stage-5 progress paragraph, appended after stage 4's; the checkbox
stays unticked), `docs/superpowers/specs/2026-09-17-engine-replacement-design.md`
("Where the task actually stands" gains a stage-5 sentence), this spec's
Status line (DESIGN → DELIVERED, with lane commits and corrections), and
`README.md` (the branch/count line, the record-file list, the engine-replacement
spec bullet).

**Left as found**: this file's own §16 "Record number collision" note
(the §28→§29 renumbering is integration's, not this pass's); the two
`LayoutAuthority.proposal`-is-inert-in-production facts, unchanged; the four
`deferred.*`/`…absolute`/`position`·`inset` reports, each still owned by its
named future stage. **Verdict: mergeable** (subject to the pending
`e5caefb`→`master` portable-text rebase noted in §16, which is integration's
job, not this pass's).
