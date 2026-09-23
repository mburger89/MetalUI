# §28 — Engine replacement, stage 5: `Deferred`'s absolute content as a presentation root

Plan task 7, stage 5 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 5).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-5-design.md`. Rulings
`LR-CH`…`LR-CO` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-5` from `e5caefb`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-5`.

**Status, 2026-09-23 (PDT): design committed; no lane has run.** Every
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
- The consumer filter must run **before** `consume` and the child counts; the
  single-child elision reads the count.
- The placeholder's alias is `lowering.alias(content)` **resolved** — a stretched
  content's element rect is its W, not its own node.
- `inset` values come from the **animated** style; which edges are given, from the
  declared one (`LR-AS`), or lane 3's 3.5 goes red for the wrong reason.
- The census (1.8) is re-derived once, in lane 1, from measured pairs; do not
  predict the six modal ids' rects — measure and attribute them.
- `swift package clean` is not owed by any planned change (internal types only).
