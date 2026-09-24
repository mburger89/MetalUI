# Engine replacement — design (plan task 7), with stage 1 in detail

**Status, 2026-09-17 (PDT): stage 1 implemented and verified; the task is open
(stage 1 of 14).** Five lanes on `feat/engine-replacement`, `4ceb3e0`…`95234ae`,
each red first; all five verified `ok: true`, lane 5 with four minor issues left
open (record §18, "Verifier round (lane 5)": 5.8's doc comment and the
bracketed 88/89 depth boundary, `compareInWindows` with no caller — §5.2 below
still describes it as the window comparison — the demo's lazy globals, and 5.5
passing on an empty bounds log). Suite 1409 (1357 + 52), 97 goldens unmoved, 71
guards; the twelve demo images 0 differing pixels at every lane; no production
frame runs under the proposal authority. Stages 2–11 (§4) are designed only at
the level of §4's table; each needs its own design. Record:
`docs/record/18-engine-replacement-stage-1.md`, whose "For the integrator"
section names the documentation edits.

**Where the task actually stands (branch checker, 2026-09-22).** The status
paragraph above is stage 1's own and was never re-dated; read it as history, not
as the task's state. **Stages 1, 2, G and 3 of the fourteen have landed** — 2 and
G merged on `integrate/stage-2-grids` (records §21, §22, §23), 3 on
`feat/engine-stage-3` (record §25, spec
[`2026-09-22-engine-stage-3-design.md`](2026-09-22-engine-stage-3-design.md)) —
and each has its own design beside this one. **Stage 4 (the windowed proposal
`List`) has landed too** (branch checker, 2026-09-23): `feat/engine-stage-4`,
record §27, spec
[`2026-09-23-engine-stage-4-design.md`](2026-09-23-engine-stage-4-design.md).
It departs from §4.1 row 4's wording in two ruled places — the windowed layout
answers `rowHeight × logicalCount` on the height rather than probe K6's greedy
answer (`LR-BR`), and `ListTests`' custom rows are re-spelled through the
legacy lowering rather than as native probe leaves (`LR-BW`). **Stage 5
(`Deferred`'s absolute content as a presentation root) has landed,
merged with `master` at `42b9ab4`** (record §29, spec
[`2026-09-23-engine-stage-5-design.md`](2026-09-23-engine-stage-5-design.md)):
it matches §4.1 row 5's wording, and its own two proposal-only answers
(`LR-CJ`) are noted there rather than as a departure from this table. **Stage
6a (the public custom-element registrars deprecated) is complete on its
branch, not yet merged** (Record phase and branch checker, 2026-09-23): `feat/engine-stage-6a`, record §38, spec
[`2026-09-23-engine-stage-6a-design.md`](2026-09-23-engine-stage-6a-design.md).
It matches §4.1 row 6a's wording — `LayoutPass.requestNode`/`requestLeaf`
deprecated with every in-repo caller moved in the same change, and the
flipped-default classification table recorded as its entry measurement
(153 reds, handed to stage 6b's root-placement ruling and stage 7b's CSS
retirements). **Stage 6b (the root switch) has landed, complete on its
branch, not yet merged** (Record phase, 2026-09-23): `feat/engine-stage-6b`,
record §41, spec
[`2026-09-23-engine-stage-6b-design.md`](2026-09-23-engine-stage-6b-design.md).
It matches §4.1 row 6b's wording — `Window`'s default authority is
`.proposal`, the demo is re-spelled for stage 2's semantics with every pixel
change probe-backed and named, root placement is ruled (`CN-J`, divergence 4
becomes legacy-authority only), the native depth limit is re-bisected in
release and re-measured on every production root (88 → 72), and
`noProductionFrameReachesTheLegacyEngine` is green — with the real-window
capture and the demo-layout human-verification rows owed to the human (the
screen was locked at every check). **Stage 7a (the goldens retired) has
landed on its branch** (Record phase, 2026-09-23): `feat/engine-stage-7a` from
`2cc763d`, record §42, spec
[`2026-09-23-engine-stage-7a-design.md`](2026-09-23-engine-stage-7a-design.md).
It meets §4.1 row 7a's exit with one respelling: the check is `find
Tests/MetalUILayoutTests -name "*.json"`, not `find Tests`, because
`Tests/PortableTests/.build/` holds JSON build artifacts — it reads 0, and every
one of the 97 goldens has a row naming its native replacement arm (44) or its
deleted CSS-only concept (53). Suite 1616, 0 px. §4.1's
table below is still the plan of record for the remaining stages; the **live** per-stage status is the
stage list under task 7 in
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`, and task 7's box there
is still open. **Production now runs the proposal engine by default as of
stage 6b** — every earlier "production still runs the legacy authority"
sentence in this document describes history up to that stage, not the
present.

Plan task 7 (`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`): *"Port
advanced layout, then remove the legacy engine. … Migrate the remaining
elements off `FlexEngine` (including a windowed proposal `List` and a proposal
portal for `Deferred`), delete the CSS layout paths and dead `Style` fields, and
replace browser-fixture goldens with SwiftUI probes or deterministic native
layout tests. No production layout request may pass through the legacy engine
after this task."*

Rulings are `LR-A`… in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md);
the measurements behind them are in `docs/record/18-engine-replacement-stage-1.md`.
Probe: `docs/probes/swiftui-engine-replacement-stage1.swift`, revision 2 (its
arm names T, B, H, S, G, W are cited as *stage-1 probe* arms; arms of other
probes are cited with the probe's name). Branch `feat/engine-replacement` from
`c2290fc`.

**Revised after critic round 1** (24 findings; dispositions in `LR-W`). What
changed: the stage plan is fourteen stages, not nine (6 split into 6a/6b, 7
into 7a/7b, 8 into 8/9/10, a modifier-unification stage 11), with dependencies
derived from a diagnostics census rather than asserted (§4.2); every legacy
site reports or traps by itself, including `List`, `Component`'s amend and
wrap, and custom elements (§5.1, lane 1); the below-word text clamp left stage
1 (`LR-F`); `FrameSpec` gains its ideal fields and the frame-layer check
compares against the layer's own lowering (`LR-H`); the native depth guard is
measured and pinned (`LR-Q`); the demo's content moves into a library target the
tests import (`LR-S`); mixed legacy/proposal trees are ruled (`LR-T`); the
closing check no longer rests on guards that can skip (`LR-P`).

**This task does not fit one run.** This document is (1) the inventory of
everything that still reaches `FlexEngine`, (2) the whole task as ordered,
independently mergeable stages, and (3) stage 1 in implementable detail. Stage
1 deletes nothing, retires no golden, and moves no demo pixel.

## Contents

1. [Baseline](#1-baseline)
2. [Inventory: what reaches the legacy engine](#2-inventory-what-reaches-the-legacy-engine)
3. [The migration shape (`LR-A`)](#3-the-migration-shape-lr-a)
4. [The whole task, as stages (`LR-L`)](#4-the-whole-task-as-stages-lr-l)
5. [Stage 1: lowering foundation](#5-stage-1-lowering-foundation)
6. [Stage 1 lanes](#6-stage-1-lanes)
7. [Demo comparison (`LR-M`)](#7-demo-comparison-lr-m)
8. [Deferred to later stages (`LR-N`)](#8-deferred-to-later-stages-lr-n)

---

## 1. Baseline

At `c2290fc`, measured 2026-09-16 in `/Users/maxburger/Developer/MetalUI-engine`:

| measure | value | how |
|---|---|---|
| suite | **1357 tests**, passed; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice; only `regenerateAllGoldens` and `aListsWorkIsTheSameFor100kRowsAsFor500` skipped | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel` |
| goldens | **97** (`flex_` 69, `stack_` 14, `sizing_` 9, `abs_` 5) | `find Tests -name "*.json" \| wc -l` |
| typecheck guards | **70** in **12** guard files (`UnitSafetyTests`' third hit is a comment; `Typecheck.swift`'s declaration excluded) | per-file `grep -c canTypecheck` (record §18 lists them) |
| demo harness controls | light vs dark **1 048 576**; default vs modal **1 030 498**; default vs animation **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576** | `CN-R`'s harness (`scratchpad/harness/gen.py`), 1024², `FakePlatformWindow`; the same figures record §16/§17 read |
| deepest element tree | legacy **13** node levels (the default demo), estimated **22** native levels once lowered; no element root in the suite estimates above 22 | scratch P2 instrument over the whole suite plus the demo harness, record §18 (`LR-Q`) |
| screen lock | design time 20:36 PDT: `IOConsoleLocked` `<false/>` but `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`; critic round 21:16 PDT: `IOConsoleLocked` `<true/>` | see `LR-M` for the override this recorded |

## 2. Inventory: what reaches the legacy engine

### 2.1 Engine entry points

| entry | production callers | test callers |
|---|---|---|
| `MetalUILayout.computeLayout(_:root:available:rootFontSize:)` (`FlexEngine.swift:95`) | **1**: `Frame.computeRootLayout` (`Frame.swift:1608`), taken whenever the root node is not native | 16 files in `MetalUILayoutTests` call it directly (216 call sites) plus `ElementLayoutTests` (1) |
| `LayoutTree.newNode(style:children:)` / `newLeaf(style:measure:)` | 1 each, through `Frame.requestNode`/`requestLeaf` | 24 test files |
| `LayoutTree.setStyle` / `style(_:)` | `Frame.setStyle` (Component amend), `Frame.style` (Component amend; `display: none` checks at `Frame.swift:1092` and `:1804`) | — |

**Measured flow** (scratch instrument I1, whole suite, reverted; record §18):
in one unfiltered run the element pipeline laid out **2 414 legacy roots** and
**237 native roots**; `computeLayout` ran **4 443** times in total, so **2 029**
runs came straight from `MetalUILayoutTests`. Legacy nodes registered, by
calling file: `Box.swift` **70 166**, `ModifiedElement.swift` **12 401**,
`Text.swift` (leaves) **12 061**, `ScrollView.swift` **1 124**, `Stack.swift`
**56**, `Component.swift` **32**; custom elements defined in 24 test files
**18 533** nodes and **3** leaves (`MeasurePerformanceTests` 17 494 of the nodes).

### 2.2 Legacy registration sites in `Sources/`

| site | registers | reaches it | load-bearing for |
|---|---|---|---|
| `Box.requestLayout` (`Box.swift:87`) | `requestNode(style:)` after `animated(…)` | `Box`, `Row`, `Column` (wrap a `Box`), the demo's `CounterPanel` | the demo root, `$anim` |
| `List.requestLayout` (`List.swift:341–424`) | **no node of its own**: builds a `Box` of a spacer `Box` and row `Box`es and returns `built.requestLayout(id, pass:)` | `List` | windowing (`MP-`, `TB-`), `AXTable` (`AB-L`) |
| `Stack.requestLayout` (`Stack.swift:106`) | `display: .stack` node | `Stack` | demo stack cluster, modal scrim |
| `ScrollView.requestLayout` (`:316`, `:327`) | content node + viewport node, each with its own `$anim` prefix | `ScrollView` | `ScrollContext`, `List`, wheel routing, divergences 11/15/16/54 |
| `ModifiedElement.requestLayout` (`:220`, `:228`) | one node per layer; a frame layer over exactly one node is `display: .stack` (`ModifierLayer.lowered`, `CN-N`) | every legacy `.padding`/`.frame` | identity levels (`MC-C`), divergence 20 |
| `Text.requestLayout` (`Text.swift:236`) | `requestLeaf` with `textMeasure` (tokenizer min-content, `TX-F`) | `Text` | text wrapping, shaping counts |
| `StyledComponent.requestGroupLayout` (`Component.swift:419–440`) | `setStyle` (**amend**, which traps on a native node, `LayoutTree.swift:603`, `SA-G`) and `requestNode` (**wrap**) on each member | a `Component`'s `.width`/`.height` (amend) and `.padding` (wrap) | `CO-U`, `OM-D`/`OM-F`, divergences 48/56 |
| `LayoutPass.requestNode`/`requestLeaf` (public) | — | any custom `Element` outside the module, and 24 test files | `SA-F`'s migration table |

Layout-transparent (no node, forward their content's): `Deferred`,
`EnvironmentScope`, `AnyElement`, `Component` (unmodified), the builder products
(`Pair`, `OptionalGroup`, `ArrayGroup`, `EmptyGroup`).

### 2.3 `Style` readers outside the engine

| reader | fields | why |
|---|---|---|
| `AnimatedStyle.swift` (568 lines) | 28 animatable keys over `size`, `minSize`, `maxSize`, `inset`, `flexBasis`, `margin`, `padding`, `border`, `gap`, `flexGrow`, `flexShrink` | the layout-phase animation helper (`AN-`) |
| `Frame.suppressingAccessibilityIfHidden`, `Frame.render` root | `display` | `AB-O`/`AB-AD` |
| `ModifierLayer.lowered` | `display` (reads `.none`, writes `.stack`) | `CN-N` and the `hidden()` fix `ed5fbc2` |
| `StyledComponent` | whole `Style` (amend) | `CO-U` |
| writers: `FrameLayer.style()`, `List` (row/spacer styles), `ScrollView` (content/viewport), `Flex.swift`, `Stack.init`, `Box.swift`'s 29 modifiers | — | — |

### 2.4 Public CSS-shaped API and its callers

`StyledElement` requires `style`; `Box.swift` declares 29 `Style`-writing
modifiers. Call sites (non-comment `.<name>(`), demo / `Sources/MetalUI` / `Tests`:

| modifier | demo | Sources | Tests |
|---|---|---|---|
| `width` / `height` | 10 / 13 | 0 | 557 / 519 |
| `minWidth` `minHeight` `maxWidth` `maxHeight` | 0 1 0 0 | 0 | 2 7 2 2 |
| `margin` / `gap` | 0 / 0 | 0 | 5 / 6 |
| `justifyContent` `alignItems` `alignContent` `flexWrap` | 3 10 0 0 | 0 | 3 35 1 1 |
| `flexGrow` `flexShrink` `flexBasis` `alignSelf` | 10 0 1 2 | 0 | 12 18 9 5 |
| `position` / `inset` / `hidden` / `flexDirection` | 1 / 1 / 0 / 0 | 0 | 5 / 4 / 27 / 4 |

Legacy element spellings in `Tests/` (occurrences / files): `Box(` 651/54,
`Box {` 77/19, `Row(` 71/14, `Row {` 289/28, `Column {` 85/23, `Stack {` 126/27
(the `Stack(` count, 168/21, includes `HStack(`/`VStack(`/`ZStack(`),
`ScrollView(` 95/23, `List(` 56/15, `Deferred {` 16/9, `Text(` 141/29 (this pattern also matches `ProposalText(`); `Style()`
651. Proposal spellings: `HStack` 130/21, `VStack` 69/8, `ZStack` 48/10,
`ProposalScrollView` 35/4.

### 2.5 CSS-only engine files (`Sources/MetalUILayout`, 6 204 lines total)

`FlexEngine.swift` 2 893, `ResolveFlexibleLengths.swift` 316, `Alignment.swift`
235 (flex main/cross distribution), `FlexBaseSize.swift` 178, `LayoutContext.swift`
165, `Resolve.swift` 142, `Style.swift` 139, `FlexLines.swift` 116, and the
legacy half of `MeasureFunction.swift` (48: `AvailableSpace`, `MeasureFunction`).
Shared with the kernel: `LayoutTree.swift` (1 510; `styles` rows are still
appended as placeholders for native nodes), `Rounding.swift` 72. Kernel-only:
`NativeLayoutRun.swift`, `ProposalLayout.swift`, `ProposalSpacing.swift`,
`ProposedSize.swift`. Outside the layout module the CSS measure is
`Text.swift`'s `textMeasure` and the tokenizer min-content path it drives (`TX-F`).

### 2.6 Tests that exercise the CSS engine

`MetalUILayoutTests` holds **440** `@Test`s. **295** of them are in **24 files
that test the CSS engine or its inputs** (tests / `computeLayout(` call sites):
`BoxModelTests` 38/38, `FlexEngineTests` 35/34, `WrappingTests` 35/26,
`FreezeLoopTests` 33/33, `StackLayoutTests` 22/11, `AbsolutePositioningTests`
17/15, `AlignmentTests` 15/7, `StackFixtureTests` 15/15, `LayoutContextTests`
10/7, `MeasureNodeTests` 10/0, `SizingFixtureTests` 9/9, `FlexBaseSizeTests` 8/0,
`FitContentFixtureTests` 6/6, `MeasureCacheTests` 6/0, `ResolveTests` 6/0,
`AbsoluteFixtureTests` 5/5, `GeneratorTests` 5/0, `ContentSizingFixtureTests` 4/4,
`IntrinsicModeTests` 4/0, `StyleTests` 4/0, `OracleTests` 3/0,
`FreezeLoopAllocationTests` 2/0, `LeafProbeShortcutTests` 2/2,
`ScrollLayoutTests` 1/1. Shared with the kernel: `LayoutTreeTests` 12,
`RoundingTests` 4. The rest (`Native*`, `ProposalLayoutTests`,
`ProposedSizeTests`) are the kernel's.

Goldens by consumer: `GeneratorTests` (all 97: regeneration and
`committedGoldensMatchTheBrowser`), `OracleTests` (1); assertion consumers
`FlexEngineTests` 16, `WrappingTests` 17, `StackFixtureTests` 15,
`FreezeLoopTests` 13, `BoxModelTests` 12, `SizingFixtureTests` 9,
`FitContentFixtureTests` 6, `AbsoluteFixtureTests` 5,
`ContentSizingFixtureTests` 4 — 97. So **most CSS-engine tests are not goldens**
(stage 7b, `LR-U`).

### 2.7 What the default demo needs that does not lower today

Two measurements (record §18):

1. **The demo minus its scroll area, inside the harness root** (`CounterPanel`
   and the `ScrollView`/`List`/`Deferred` box replaced by a sized `Box`, rendered
   inside `DifferentialRoot` at 920×560; critic round 1 finding 11): **22
   elements, 2 agreeing** (the harness root and one other); the fields with no
   lowering were `alignItems: stretch` ×8, `flexGrow` ×8, `flexBasis` ×1,
   `alignSelf(.flexStart)` ×1. The design's first figure, "0 of 21", was taken
   with the tree as the frame's own root and is withdrawn: `LR-D`'s own
   measurement shows a bare root offsets every descendant.
2. **The whole demo, every legacy site reporting instead of trapping**
   (`demoContent()` through the `CN-R` fake window, scratch P2 with
   `SCRATCH_ALL`, one run of eight images' frames): `alignItems.stretch`
   8 084, `flexGrow` 4 066, `flexShrink` 4 008, `minSize` 4 008, `alignSelf`
   16, `flexBasis` 8, `position.absolute` 2, `inset` 2, and `ScrollView.swift`'s
   registrar 16 — the `List`'s rows (their `flexShrink = 0` and `minSize`
   pins) dominate. Deepest lowered native run: **12**.

The scroll area adds `ScrollView`, `List`, `Deferred`, `position(.absolute)` and
`inset`.

---

## 3. The migration shape (`LR-A`)

**Lower in place, per root.** Every legacy element keeps its type, its
`prepaint` and its `paint`; only the `requestLayout` branch that registers
nodes changes, and which branch runs is decided by the **layout authority of
the frame**, not by the element. Under the legacy authority (the default, and
the only one production uses until stage 6b) nothing changes. Under the proposal
authority each legacy element registers kernel nodes, and a tree that contains
anything with no lowering yet traps, naming the site and the field.

Why this and not the alternatives (full reasoning and figures in `LR-A`):

- **The pipeline after layout is engine-agnostic.** Hit testing, focus,
  accessibility records, decoration paint, `@State` slots and `$anim` all read
  `pass.bounds(of: node)` and ids, never the engine. Measured on a clickable,
  focusable, labelled counter chrome lowered by the prototype: scene rects,
  glyph sprites, hitboxes, accessibility emissions, per-element bounds and the
  `StateTable` entry count were identical to the legacy tree, and a one-point
  lowering change (stack spacing + 1) made rects, glyphs, hitboxes and bounds
  differ — the control. The prototype's accessibility comparison read each
  emission's id, declared node and text but not its `geometry`, so it stayed
  equal under the control; lane 1's comparison includes `AXEmission.geometry`
  (test 1.9 is what proves it can differ). A width animated 196→320
  read 196, 196, **258** at t = 0, 0, 0.5 under both authorities.
- **Conforming legacy types to `ProposalElementGroup` instead is ruled out by
  measurement.** Adding only `Text: ProposalElement` and a conditional
  `Box: ProposalElement` produced **83 compile errors in 13 test files** and one
  in the demo (66 of them `ambiguous use of 'background'`, plus `opacity`,
  `allowsHitTesting` and three solver time-outs): the shared modifier spellings
  are unambiguous only because no built-in type is both.
- **Rewriting every caller onto the proposal vocabulary** would first need the
  proposal vocabulary to grow handlers, focus, key contexts, accessibility,
  decorations and animation — a second element pipeline.
- **Porting `FlexEngine` into a `ProposalLayout`** keeps CSS as the authority,
  which is what the task removes.

**Mixed trees** (`LR-T`). Under the proposal authority a proposal element inside
a lowered legacy container is a single-authority tree — every node is native —
and is allowed: scratch P2 laid out `Column { Box; HStack {…};
ProposalScrollView {…}.frame(…) }` with no diagnostic and one scroll region.
Under the legacy authority the same tree still traps in `newNode` (`SA-G`),
unchanged. Lane 3 pins both.

## 4. The whole task, as stages (`LR-L`)

Each stage merges on its own with the suite green. "Demo" is the twelve-image
`CN-R` comparison against the previous stage's merge (plus, from stage 1 lane 5
on, the two-authority chrome pair).

### 4.1 The stages

| # | stage | depends on | delivers | exit test (named in its own design) | goldens | demo |
|---|---|---|---|---|---|---|
| **1** | **Lowering foundation** (this design) | — | per-frame layout authority; every legacy site reports or traps by name (including `List`, `Component` amend/wrap, custom elements); bounds log; differential harness; lowering of `Text`, `Box`, `Row`, `Column`, `Stack` and `ModifiedElement` layers on the stage-1 subset (§5.4); ideal under the proposal authority; mixed-tree ruling; demo content in a library target; pipeline parity, depth and work-count pins | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` | 0 retired | 0 px |
| 2 | **Flex-item semantics onto SwiftUI's** | 1 | `flexGrow` → greedy main-axis frame (stage-1 probe G1/G2); `alignItems`/`alignSelf` `.stretch` → greedy cross-axis frame (S1–S3), including a nil-axis frame under a stretching `Box` (`MC-Q` finding 7); CSS `min`/`max` clamps (`FR-G`), `flexBasis`, `flexShrink`, `justifyContent` distribution, percentages (`FR-H`/`FR-T`), `margin`, `hidden()` (probe H: SwiftUI keeps the space; `AB-O` moves off `display`), Style padding on a leaf, the `BM-4` floor; `SA-N` item 4 (padding places its child at the child's size); `Row`/`Column` default spacing (divergence 52); overflow compression (divergence 55: stack-algorithms G9/X13 for fixed children, G1 for order among flexible ones); `Text`/`ProposalText` measurement unified, including the below-word answer (stage-1 probe T3/T4, W2) | lane 5's `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (5.3), rewritten to require **no stage-2 field** diagnostic: only the `scrollView.noLowering` and `list.noLowering` site entries remain, plus, with the modal shown, the `position`/`inset` fields, stage 5's — `Deferred` has no `LoweringSite`, being layout-transparent; branch checker's correction of "only site diagnostics for `ScrollView`/`List`/`Deferred`/absolute"), each remaining disagreement with a probe arm | 0 | legacy images 0 px (no production root lowers). **Preview images: `SA-N` item 4 is a kernel change reaching a production root.** Measured with a scratch implementation (child placed at origin + inset at its own size): **0 differing pixels in all 12**, the instrument live (it changes the `SA-N` pin's exit-test child's outcome); the stage re-takes them with its real change and treats non-zero as a finding |
| 3 | **Scrolling and `Component` distribution** | 1, 2 (census: `ScrollRoutingTests` needs stretch ×35, `Stack` stretch ×4, `minSize` ×3; `ScrollIndicatorTests` stretch ×11) | `ScrollView` lowered onto the kernel scroll viewport, **one** clamp/indicator implementation shared with `ProposalScrollView` (its private copies folded), `$anim-content`/`$anim-viewport`, `ScrollContext` from a native viewport, divergence 54; `Component` distribution without `setStyle` (amend → per-member frame, `OM-F`, divergences 48/56, a frame over a multi-member component) | the `ScrollRoutingTests` and `ScrollIndicatorTests` scenarios under the proposal authority, their 9 custom test nodes re-spelled as native probe leaves | 0 | 0 px |
| 4 | **Windowed proposal `List`** | 2 (census: stretch ×251, `flexShrink` ×249, `minSize` ×222), 3 | `List`'s explicit site check replaced by a windowed `ProposalLayout` placing realized rows at `index × rowHeight` against the native `ScrollContext`; row identity (`TB-`), `AXTable` records (`AB-L`), `MP-I` cold-frame work, probe K6's layout answer | `aListsWorkIsTheSameFor100kRowsAsFor500` and the `ListTests` windowing arms under the proposal authority, counting work; `ListTests`' 224 custom nodes and 3 leaves re-spelled | 0 | 0 px |
| 5 | **Portal and absolute positioning** | 2 (census: `DeferredTests` stretch ×3, `AbsoluteOverlayTests` stretch ×2), 3 (both suites register `ScrollView`s: 10 and 2) | `Deferred` as a presentation root laid out against the window (overlay-presentation P4/P5), `.position(.absolute)`/`.inset` (census: 1 each in `AbsoluteOverlayTests`, 2 each in the demo) lowered onto it or removed; divergences 9–11 | `DeferredTests` and `AbsoluteOverlayTests` under the proposal authority | 0 | 0 px |
| G | **Grids** | — (no legacy twin; nothing to compare) | `Grid`/`GridRow` as probe-backed `ProposalLayout`s (task text: "grids") | its own probe's arms | 0 | 0 px |
| 6a | **Custom elements, and tests that are about CSS answers** (`LR-R`) | 1 | the public `LayoutPass.requestNode`/`requestLeaf` deprecated **and** every in-repo caller moved in the same change (`FR-I`): each custom test element re-spelled onto `requestNativeLeaf`/`ProposalLayout`, or — where the test is about a CSS answer — pinned to the internal `.legacy` authority through the internal, undeprecated `Frame.requestNode`; the list of such tests produced by running the suite with the default authority flipped and diagnostics on, each red test classified (lowering gap owned by a stage / CSS answer to retire in 7b) | **0 `warning:`** with the deprecation in place (the gate that makes it one move), and `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`; the flipped-default classification table recorded as the stage's entry measurement | 0 | 0 px |
| 6b | **Root switch** | 2, 3, 4, 5, 6a | `Window`'s default authority becomes proposal; the demo is re-spelled for the semantics stage 2 changed, each pixel change probe-backed; root placement ruled (divergence 4 vs `CN-J`); the native depth limit re-bisected in release and re-measured on every production root (`LR-Q`); the human-verification rows that read demo layout re-opened; real-window captures | `noProductionFrameReachesTheLegacyEngine` — `demoContent()` and `nativeLayoutPreviewContent()` **imported from `MetalUIDemoContent`** (`LR-S`), plus a `List`, driven through a `Window`, with a counter showing the legacy branch of `computeRootLayout` never ran | 0 | **changes**, each difference named |
| 7a | **Goldens replaced** | 2 (the native equivalents exist) | each of the 97 goldens retired with a ruling naming the deterministic native test or probe arm that replaces it, or naming the CSS-only concept (wrap, reverse, margins, percent padding, absolute insets) deleted with it; `GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/` removed | `find Tests -name "*.json" \| wc -l` reads 0 and every replacement is listed in the ruling | **97** | 0 px |
| 7b | **Non-golden CSS-engine tests retired** (`LR-U`) | 2, 6a, 7a | the 295 − (golden-consuming) tests of §2.6's 24 files, and the element-level tests 6a pinned to `.legacy`, each retired with the same rigour as 7a: a named replacement native test or probe arm, or the named deleted concept. Named up front: `LayoutContextTests`' depth guard → `NativeDepthGuardTests` (exists); `StackLayoutTests` → native overlay tests + stage 1's 4.1; `AlignmentTests` → `NativeStackDistributionTests` for what stage 2 maps, deleted concept (`justifyContent` distribution, `alignContent`) for the rest; `LeafProbeShortcutTests`, `FreezeLoopTests`, `FreezeLoopAllocationTests`, `FlexBaseSizeTests`, `IntrinsicModeTests`, `MeasureCacheTests`, `MeasureNodeTests` → deleted concept (flex §9.7 and the CSS measure cache), with `NativeLayoutWorkTests` as the kernel's work-count pin and CLAUDE.md's CI section on the freeze loop's allocation pin retired with it; `AbsolutePositioningTests` → stage 5's replacement; `MeasurePerformanceTests` (17 494 legacy nodes) → a native work-count test | the retirement table accounts for every `@Test` removed (count before − count after = rows), and `grep -rn "computeLayout(" Tests` is empty | 0 | 0 px |
| 8 | **Sizing vocabulary** (`FR-F`/`FR-G`'s recipe) | 6b | `width`/`height`/`min*`/`max*` converted to `.frame` by the recipe (demo 10/13/1, tests 557/519/13), deprecated in the same change; `Style()` writes of CSS fields in tests (651 `Style()` uses) moved onto modifiers or deleted with their tests | 0 `warning:`, and the demo pixel comparison against 6b reads 0 (the recipe's reordering is what it can see) | 0 | 0 px against 6b |
| 9 | **Engine deletion** | 6b, 7a, 7b, 8 | `FlexEngine.swift`, `ResolveFlexibleLengths.swift`, `FlexBaseSize.swift`, `FlexLines.swift`, `Alignment.swift`'s flex half, `LayoutContext.swift`, `Resolve.swift`'s percentage half, the legacy `MeasureFunction`, `textMeasure` and tokenizer min-content, the legacy registrars and the legacy authority; `LayoutTree`'s placeholder `styles` rows | the suite green with the files gone; `noProductionFrameReachesTheLegacyEngine` deleted with the branch it counted, replaced by 10's symbol check | — | 0 px against 8 |
| 10 | **`Style`'s CSS fields and the closing check** (`LR-P`) | 9 | `Style`'s CSS fields deleted; `StyledElement.style` narrowed to what paint/animation read; the mechanical check | `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` (`dlsym`, cannot skip) + plain-import guards + the recorded grep | — | 0 px against 9 |
| 11 | **Modifier unification** (`LR-V`) | 9 | `ModifiedElement` and `ModifiedContent` unified (outer-modifiers spec §9); legacy `.overlay` (`CN-Q`); `.opacity` reaching a background written after it (G4, divergence 45) and answering the same on both paths (`OM-AA` a) | the outer-modifier-order probe's G3/G4 arms and the overlay-primary-shape probe through the unified type | 0 | named per change |

Task 7's other clauses are already met on the proposal path — unspecified,
ideal, min/max, fixed-size, layout priority (task 2, task 4), compression and
expansion (`CN-B`), custom layouts (`SA-A`) — and reach legacy spellings through
stages 1–2.

**"Ideal on the legacy path"** (a handed item) has two halves (`LR-H`). A legacy
`.frame(idealWidth:)` **under the proposal authority** is stage 1 (lane 4:
`FrameSpec` gains `idealWidth`/`idealHeight`). **Under the legacy authority** it
is never implemented: an ideal has no CSS lowering (`FR-D`), so it keeps
trapping, now at legacy registration instead of construction. Production gains
it at stage 6b, when the default authority becomes proposal; stage 9 deletes the
legacy authority and with it the trap.

### 4.2 How the dependencies were derived (critic round 1 finding 20)

Scratch P2 (record §18) ran each later stage's exit suite, filtered, with every
frame under the proposal authority and every legacy site **reporting** instead of
trapping (a legacy registrar returned a 0×0 native leaf and counted its caller's
file; `Component` amends were skipped and counted; the native depth guard
recorded instead of trapping), and printed the census per suite. A filtered run
is a different program; these are diagnostics counts, not verdicts, and the
suites' own assertions were expected to fail (they did: `ScrollRoutingTests`
16 tests / 20 issues, `ScrollIndicatorTests` 14/16, `DeferredTests` 9/3,
`AbsoluteOverlayTests` 1/1, `ListTests` 29/16). P2 lowered `minSize`/`maxSize`
as frames while counting them, so they appear; it did not report `%` or `rem`.

| suite | stage | stretch | `flexGrow` | `flexShrink` | `minSize` | other | legacy registrars |
|---|---|---|---|---|---|---|---|
| `ScrollRoutingTests` | 3 | 35 (+4 `Stack`) | — | — | 3 | — | `ScrollView.swift` 70, test file 9 |
| `ScrollIndicatorTests` | 3 | 11 | — | — | — | — | `ScrollView.swift` 38 |
| `ListTests` | 4 | 251 | — | 249 | 222 | — | test file 224 nodes + 3 leaves |
| `DeferredTests` | 5 | 3 | — | — | — | — | `ScrollView.swift` 10 |
| `AbsoluteOverlayTests` | 5 | 2 | — | — | 1 | `position` 1, `inset` 1 | `ScrollView.swift` 2 |
| the demo (all eight legacy images) | 6b | 8 084 | 4 066 | 4 008 | 4 008 | `alignSelf` 16, `flexBasis` 8, `position` 2, `inset` 2 | `ScrollView.swift` 16 |

Every exit suite of stages 3–5 needs stretch, so each depends on stage 2; stages
4 and 5 need a lowered `ScrollView`, so they depend on 3; three suites build
custom test elements, which their stage re-spells (or 6a has already). Grids
have no legacy twin, so G depends on nothing here.

## 5. Stage 1: lowering foundation

### 5.1 What stage 1 must leave true

1. Under the legacy authority every observable is byte-identical to `c2290fc`:
   the suite's existing 1357 tests pass unchanged except the one pin `LR-H`
   deliberately amends, and all twelve demo images read 0 differing pixels.
2. Under the proposal authority, every element in the stage-1 subset registers
   only kernel nodes, and the differential harness reports each element's rect
   either **equal** to the legacy engine's or **different by a named probe arm**.
3. **Nothing whose lowering is undefined lays out silently.** Every legacy site
   checks the authority **itself**, before it registers anything: `Box`,
   `Stack`, `Text`, both `ModifiedElement` registrars, `ScrollView`, `List`
   (**before** it builds its `Box`, so a later stage's `Box` lowering cannot
   carry an unwindowed `List`), `StyledComponent`'s amend and its wrap, and the
   public `LayoutPass.requestNode`/`requestLeaf` (a custom element). Each traps
   in production and reports `(site, field)` under diagnostics. Proposal
   elements inside a lowered container are **defined**, not silent (`LR-T`).
4. Identity, `@State`/`$focus`/`$anim`/`$ax` slots, hitboxes, focus,
   accessibility records and animation are identical between the two
   authorities on every agreeing tree (lane 5 pins).
5. The native depth guard is not reached by any tree the suite or the demo
   builds, and its boundary under lowering is pinned (`LR-Q`).

### 5.2 API (all `internal`; `@testable` tests reach it)

```swift
// Sources/MetalUI/LayoutAuthority.swift (new)
enum LayoutAuthority: Sendable, Equatable { case legacy, proposal }

enum LoweringSite: String, Sendable { case box, stack, text, modifierLayer,
                                      scrollView, list, component, customElement }

struct UnlowerableField: Hashable, Sendable {
    let site: LoweringSite
    let field: String   // "flexGrow", "alignItems.stretch", "minSize.width", "noLowering",
                        // "amend", "wrap", "requestNode", "requestLeaf", …
}

// Frame
init(contentSize:scaleFactor:…, collectsAccessibility: Bool = false,
     layoutAuthority: LayoutAuthority = .legacy,
     reportsUnlowerableFields: Bool = false,
     recordsElementBounds: Bool = false)
let layoutAuthority: LayoutAuthority
private(set) var unlowerableFields: [UnlowerableField]      // empty unless reporting
private(set) var elementBounds: [GlobalElementID: Bounds<Pixels>]  // empty unless recording
/// Traps unless reporting ("MetalUI: <site>.<field> has no proposal lowering …");
/// reporting: records, returns a 0×0 native leaf. The SITE is always the caller's
/// own argument — `Frame` never infers it.
func unlowerable(_ field: UnlowerableField) -> LayoutNodeID
/// The internal, undeprecated legacy registrars stay; the public forwarders on
/// `LayoutPass` check the authority and report `.customElement` (stage 6a
/// deprecates the public pair, `LR-R`).
func requestNode(style: Style, children: [LayoutNodeID]) -> LayoutNodeID

// LayoutPass
var lowersToProposal: Bool { frame.layoutAuthority == .proposal }

// Window
var layoutAuthority: LayoutAuthority = .legacy   // passed to every Frame it builds; a write marks dirty

// StateTable
var ids: Set<GlobalElementID> { get }            // test observable (inert-table row at Docs)

// Sources/MetalUI/LegacyLowering.swift (new, lanes 2–4)
extension LayoutPass {
    /// Lowers one legacy node — `style` already animated — over native children.
    /// `declared` is the pre-animation style, read only by the checks. Lane 2: a
    /// childless node lowers through `lowerLegacyLeaf` over a 0×0 native leaf.
    /// Lane 3: a node with children lowers to linear stack → padding → frame
    /// (§5.4's container table). Lane 4: a `display: .stack` container lowers to
    /// overlay → padding → frame.
    func lowerLegacyNode(_ style: Style, declared: Style, children: [LayoutNodeID],
                         site: LoweringSite) -> LayoutNodeID
    /// Lane 4 (`LR-Z`: the design's `frameSpec:` parameter on `lowerLegacyNode`
    /// became this method, because the check needs `ModifierLayer.lowered`): a
    /// `.padding` layer → `lowerLegacyNode(site: .modifierLayer)`; a `.frame`
    /// layer → one native frame (`LR-H`), after `legacyFrameLayerDiagnostics`.
    func lowerLegacyLayer(_ layer: ModifierLayer, declared: Style,
                          children: [LayoutNodeID]) -> LayoutNodeID
    /// Lane 4: `display.none` alone; `style`; `frame.multipleNodes` (`LR-Z`).
    func legacyFrameLayerDiagnostics(_ layer: ModifierLayer, declared: Style,
                                     childCount: Int) -> [UnlowerableField]
    /// Lane 3: §5.4's container "otherwise" column, then `legacyLeafDiagnostics`
    /// (`LR-Y`: `display.none` alone first; lane 4, `LR-Z`: a `display: .stack`
    /// container reports only the stack rows, then the every-node rows).
    func legacyContainerDiagnostics(_ declared: Style, childCount: Int,
                                    site: LoweringSite) -> [UnlowerableField]
    /// Lane 2: the leaf table's checks on `declared`; then `content()` → native
    /// padding (non-zero `Style.padding`) → fixed `.topLeading` frame (a declared
    /// `Style.size`). Returns the element's node; `content()` is not called when
    /// anything is reported.
    func lowerLegacyLeaf(_ style: Style, declared: Style, site: LoweringSite,
                         content: () -> LayoutNodeID) -> LayoutNodeID
    /// Lane 2: §5.4's every-node "otherwise" column for a leaf.
    func legacyLeafDiagnostics(_ declared: Style, site: LoweringSite) -> [UnlowerableField]
}

// FrameSpec gains `idealWidth: Pixels?`, `idealHeight: Pixels?`; `style()` does not
// read them; `trapIfLaidOutByTheLegacyEngine()` holds FR-D's two preconditions.
// ModifierLayer gains `frameSpec: FrameSpec?` — a stored property on a public type:
// the lane that adds it runs `swift package clean` before its suite — and its
// stored `isFrame` becomes `var isFrame: Bool { frameSpec != nil }`, its init
// `init(style:frameSpec:)` (lane 4).
// (`Text.Layout.measuredNode` was in this list; lane 2 added it, measured it wrong
// and removed it, `LR-X`.)
```

The trap message names both halves: `"MetalUI: <site>.<field> has no proposal
lowering (plan task 7, stage <n>); a tree containing it cannot run under the
proposal layout authority."`

Test support (`Tests/MetalUITests/LayoutDifferential.swift`, new):

```swift
@MainActor struct DifferentialRoot<Content: Element>: Element  // legacy: a topLeading Stack node W×H;
                                                               // proposal: native overlay(.topLeading) in a W×H frame
@MainActor struct ProbeLeaf: Element   // legacy leaf / native leaf per authority; optional per-authority
                                       // width offset, onClick + accessibilityLabel, and a `$probe` state
                                       // entry minted only under a chosen authority
@MainActor enum LayoutDifferential {
    struct Report {
        var elements: Int
        var agreeing: [GlobalElementID]
        var disagreeing: [(id: GlobalElementID, legacy: Bounds<Pixels>, lowered: Bounds<Pixels>)]
        var legacyOnly: [GlobalElementID], loweredOnly: [GlobalElementID]
        var unlowerable: [UnlowerableField]
        var scenesEqual, hitboxesEqual, accessibilityEqual, stateSlotsEqual: Bool  // scene: emitted and finalized bytes, drawList
    }
    static func compare<E: Element>(width: Float, height: Float, scaleFactor: Float = 1,
                                    _ make: @MainActor () -> E) -> Report
    /// The same comparison through a real `Window` per authority, with
    /// `DifferentialRoot` as the window's root content (lane 5; `LR-AA`: square,
    /// the root the window's size, built on `WindowPair`, which pre-flights the
    /// tree under diagnostics before it opens a window).
    static func compareInWindows<Content: ElementGroup>(device: any MTLDevice, size: Int,
                                                        _ make: @escaping @MainActor () -> Content,
                                                        drive: @MainActor (Window, FakePlatformWindow) throws -> Void) throws -> Report
}
@MainActor struct WindowPair { init(device:size:startsDisplayLink:_:) throws; func both(_:); func report() -> LayoutDifferential.Report }

// Window (lane 5, LR-AA): internal test observables
var recordsElementBounds: Bool                                  // passed to every Frame
private(set) var lastElementBounds: [GlobalElementID: Bounds<Pixels>]  // captured beside lastScene
```

`compare` renders `DifferentialRoot { make() }` twice at W×H — legacy, then
proposal with diagnostics on — with `recordsElementBounds` and
`collectsAccessibility` on and separate `StateTable`s, and compares per id.

### 5.3 Why the harness root is a top-leading, fixed-size root (`LR-D`)

Measured (record §18): with the twelve scratch trees rendered **directly** as
roots, **4 of 50** element rects agreed (all four in the `Stack` cluster, T3) —
the legacy root fills the window (divergence 4, `CS-I`) and the native root is
centred at its own answer (`CN-J`), so every descendant is offset. With the same
trees inside a top-leading fixed-size root on both paths, **57 of 62** agreed
(45 of 50 excluding the twelve harness roots), and the five disagreements traced
to fields outside the subset (T4: four rects, stretch and grow) or to a
probe-backed SwiftUI answer (T8: one rect, text hug, stage-1 probe T7). Root
placement is stage 6b's ruling, not the harness's.

**The root carries a divergence of its own** (critic round 1 finding 12). Its
legacy side is a `Stack`, which offers a child fit-content; its proposal side is
an overlay, which offers W×H (divergence 53, `LR-G`). A wrapping `Text` or a
greedy child placed **directly** under the root therefore disagrees because of
the harness, not the lowering. Corpus trees put such content inside a container
of their own; test 1.10 pins the root on fixed children only; lane 5's `Window`
tests (5.4–5.6) and the two-authority images use `DifferentialRoot` as the
window content, never a bare tree.

### 5.4 The stage-1 lowering table (`LR-E`)

Order, innermost first: **content** (leaf / linear stack / overlay) → **native
padding** (from `Style.padding`) → **fixed frame** (from `Style.size`). This is
CSS's border-box spelled as SwiftUI: stage-1 probe B1 places a 10×26 child at
(12, 12) inside `.padding(12).frame(60×60, .topLeading)`, and B3 reproduces the
counter chrome's legacy rects.

**Containers** (a node with at least one child):

| `Style` field | lowering | otherwise |
|---|---|---|
| `flexDirection` `.row`/`.column` | native linear stack, horizontal/vertical | `.rowReverse`/`.columnReverse` → reported `reverse` |
| `gap` (main axis: `horizontal` for a row, `vertical` for a column; px, rem × `rootFontSize`) | stack `spacing`, explicit | a main-axis `%` → reported `gap.percent`; the cross-axis gap is read by nothing on one line and is not checked (`LR-Y`) |
| `alignItems` `.flexStart`/`.center`/`.flexEnd` | stack cross alignment; and the size frame's cross alignment | `.baseline` → reported `alignItems.baseline` (task 11) |
| `alignItems` `nil`/`.stretch` (a `Box`'s default) | **lowerable only where CSS cannot show it**: exactly 1 child **and** no declared cross-axis size | else reported `alignItems.stretch` (stage 2) |
| `justifyContent` `nil`/`.flexStart`/`.center`/`.flexEnd` | the size frame's main-axis alignment | — |
| `justifyContent` `.spaceBetween`/`.spaceAround`/`.spaceEvenly` | lowerable only with no declared main-axis size (no free space exists) | else reported `justifyContent.spaceBetween`/`.spaceAround`/`.spaceEvenly` (stage 2) |
| `display: .stack` (`Stack`) | native overlay; alignment from `alignItems` (vertical) × `justifyItems` (horizontal), nine — lane 4, on any site (a `Box` declaring it too; before lane 4 it reported `noLowering` alone, `LR-Y`). **Every other row of this table is ignored on a stack** — the legacy engine branches to its stack layout before reading them (4.1's arm, `LR-Z`) | `alignItems` `nil`/`.stretch` → `alignItems.stretch`; `.baseline` → `alignItems.baseline`; `justifyItems` `nil`/`.stretch` → `justifyItems.stretch`; then the every-node rows |
| `flexWrap` ≠ `.noWrap`, `alignContent` ≠ nil | — | reported `flexWrap`, `alignContent` (deleted concept, stage 9/10) |
| `aspectRatio`, `overflow`; `justifyItems` on a flex node | ignored — the legacy engine ignores them too (inert table) | — |

A container's report is `display.none` alone if hidden; else the container rows
in this table's order, then the **every node** rows (`LR-Y`); production traps
on the first.

**Leaves** (a childless `Box`, a `Text`; critic round 1 finding 6). The legacy
engine lays out no children for a leaf, so every **container** field is
ignored on a leaf, whatever its value — `flexDirection` (including the reverse
cases), `gap` (including `%`), `alignItems` (including `.baseline` and
`.stretch`), `justifyContent` (including `space-*`), `justifyItems`,
`flexWrap`, `alignContent`, `display: .stack`. Test 2.4 carries one arm per
container field with its most "unlowerable" value, and requires the leaf's
report to be empty and its rect to agree.

**Every node** (container or leaf):

| `Style` field | lowering | otherwise |
|---|---|---|
| `display: .none` | — | reported `display.none` (stage 2; stage-1 probe H) — checked **first** |
| `size` px/rem | fixed native frame, alignment as above | `%` → reported `size.percent` (stage 2, `FR-H`) |
| `padding` px/rem on a container, a layer or a childless `Box` | native padding inside the size frame | `%` → reported `padding.percent`; declared size below the padding sum on an axis → reported `padding.floor` (`BM-4`); **on a `Text`** → reported `padding.text` (inert on legacy, stage 2) |
| `minSize`, `maxSize` | — | reported (CSS clamps, `FR-G`; stage 2) |
| `margin`, `border`, `position` ≠ `.static`, `inset`, `flexGrow` ≠ 0, `flexShrink` ≠ 1, `flexBasis` ≠ `.auto`, `alignSelf` ≠ nil | — | reported by field name (stages 2, 5) |

**Not a diagnostic: overflow compression** (`LR-I`). A fixed-size child in a
container too small for it is shrunk by CSS (`flexShrink` 1, divergence 55) and
overflows in SwiftUI (stack-algorithms **G9**: `HStack(0){a fixed 80; b fixed
80}` at 100×50 answers 160×20, a at 0, b at 80; **X13** the nil-proposal
control); the sizes are unknown at registration, so the harness reports it as a
disagreement and lane 3's test 3.6 pins it.

**Frame layers** (`LR-H`). A frame layer lowers to one `newNativeFrame`: fixed
width/height and finite min/max read from the layer's **animated** `Style`
(the fields `FrameSpec.style()` writes), ideals, infinite maxima and alignment
from `frameSpec`. **The check** reads the layer's **declared** style (after
`lowered(_:childCount:)`, before `animated(…)`) and compares it with
`lowered(frameSpec.style(), childCount:)` — the same `display: .stack` a
one-node frame gets — so an unmodified frame layer always passes and an
animation never trips it. `display: .none` (a `hidden()` after the frame) is
reported as `display.none` before the comparison. Any other difference — a
caller's `.width`, `.minWidth`, `.maxHeight`, `.flexGrow` or `.alignItems`
written after `.frame`, which lands on the frame layer — is reported as
`modifierLayer.style` (lane 4 test 4.8). A frame layer over **more than one**
node (a multi-member `Component`) is reported `frame.multipleNodes` (stage 3,
`LR-Z`); over **no** node it lowers over a 0×0 native leaf. A **`.padding`
layer** is a one-child container and lowers through the container table at site
`modifierLayer`. The kernel frame is SwiftUI's
(`FR-A`/`FR-M`), so under the proposal authority a lowered `.frame(minWidth: 40,
maxWidth: 80)` over a 20pt child answers 80 at a 100pt proposal (frame probe D
control; legacy 40, divergence 35) and `.frame(maxWidth: .infinity)` fills on
one axis (`FR-O`'s inert arm).

**`Text`** (`LR-F`) lowers to a native leaf measured by
`proposalTextMeasurement`, **unchanged**: it answers its widest line after
wrapping at the proposed width (stage-1 probe T1/T2/T5/T6), and its widest
**character** (with the trailing space the typesetter hangs on its line; 11.18 for
probe T's string at 13pt) below a word's width, where SwiftUI answers the proposal
(T3/T4) — a disagreement stage 1 pins and stage 2 owns (`LR-X`: this said "widest
word"). Its declared `size` wraps it in a fixed frame aligned `.topLeading`;
glyphs are painted at the element's bounds origin, wrapped at **the element
node's** measured width — the frame's, the width the leaf was proposed — which
keeps legacy glyphs for `Text(…).width(w)` at every `w`, including one narrower
than a word (`LR-X`: this said "`measuredNode`'s", the leaf's, which lane 2
measured drawing fewer lines at widths 30 and 5). SwiftUI would centre (T7) —
that belongs to stage 8's `.width` → `.frame` conversion.

## 6. Stage 1 lanes

Five lanes, in order; each lane's tests are written first and read red, except
tests marked **characterization** (they pin behaviour that already exists and are
green on arrival; their mutation is what proves they can fail). "Red before" for
a lowering test means **a diagnostic in the report** (the harness never traps),
so no red run truncates the suite. Every mutation below is applied after the
lane's commit, from a `cp` backup, whole suite unfiltered, `git status --short`
empty afterwards, and reddens **at least** the tests named; the lane's record
names every test it actually reddens. **Every lane re-takes the twelve images
with its real change** (§7).

### Lane 1 — authority, every site's own check, bounds log, harness

Files: `Sources/MetalUI/LayoutAuthority.swift` (new), `Frame.swift` (init
parameters, `unlowerable`, bounds recording at the root in `render`),
`Passes.swift` (`lowersToProposal`; the public `requestNode`/`requestLeaf`
report `.customElement`), `Window.swift` (`layoutAuthority`), `StateTable.swift`
(`ids`), `ElementGroup.swift` (record in `Element.prepaintGroup`),
`ModifiedElement.swift` (both registrars' checks; record per inner layer in
`prepaintLayer`), **`Box.swift`, `Stack.swift`, `Text.swift`, `ScrollView.swift`,
`List.swift`, `Component.swift`** (each site's own check);
`Tests/MetalUITests/LayoutDifferential.swift`, `LayoutAuthorityTests.swift`,
`LayoutAuthorityCompileGuards.swift` (new).

In lane 1 every site under the proposal authority reports `(<site>,
"noLowering")` — `StyledComponent` reports `(.component, "amend")` and
`(.component, "wrap")` and **skips the `setStyle`**, so `SA-G`'s own
precondition is never the message — and lanes 2–4 replace `box`, `text`,
`stack` and `modifierLayer` with field-level entries. `scrollView`, `list` and
`component` stay site-level through all of stage 1. `List` checks before it
builds its `Box`; under diagnostics it then lays out a zero-row `Box`, whose own
report is additional, never instead.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aFrameAndAWindowDefaultToTheLegacyAuthority` | does not compile | **none claimed.** Changing either default traps the first legacy frame of the suite and truncates it (no summary line), which no single test can report; the default is pinned by the whole suite's printed count, read per CLAUDE.md, not by 1.1 (critic round 1 finding 13) |
| 1.2 | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` — a `ProbeLeaf` logs `pass.lowersToProposal` through a real `Window` | does not compile | **M1b** `Window` builds its `Frame` without passing the authority |
| 1.3 | `aCustomElementsLegacyRegistrationTrapsUnderTheProposalAuthority` (exit test; two children: `requestNode`, `requestLeaf`; stderr names `customElement.requestNode` / `.requestLeaf`) | does not compile | **M1c** the public forwarder's check removed (the message becomes the site-less internal one, or none) |
| 1.4 | `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` (exit test; two children: `ScrollView { List(3 rows) }` names `list.noLowering`, **not** `box`; `MyComponent().width(70)` names `component.amend`, **not** `setStyle on a native layout node`) | does not compile | **M1d** `List`'s check removed (message names `box`); **M1d′** the amend's check removed (message is `SA-G`'s) |
| 1.5 | `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` — one arm each: `Box`, `Stack`, `Text`, both `ModifiedElement` registrars, `ScrollView`, `List` (its entry precedes any `box` entry and no row `Box` is built), `Component` amend (`.width`), `Component` wrap (`.padding`), custom `requestNode`, custom `requestLeaf`; each frame completes; `try #require` on the arm count. **The `Component` amend arm runs in a child process** (lane-1 verifier round), so M1d′ reddens 1.5 by name instead of truncating the run on `SA-G`'s `setStyle` precondition | does not compile | **M1e** `ScrollView`'s record dropped; **M1e′** `List`'s check moved after its `Box` is built (row boxes appear); **M1d′** (child arm) |
| 1.5b | `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` (lane-1 verifier round) — exit test, two children calling `Frame.requestNode` / `requestLeaf` directly under the proposal authority: stderr names `Frame.requestNode` / `.requestLeaf` `reached under the proposal layout authority`; in-process under diagnostics: a native node and no entry | passes on arrival (pins existing code) | **M1n** the backstop guard removed from `Frame.requestNode` (left the suite green before 1.5b) |
| 1.6 | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` — legacy authority; literal id count and rects derived by hand | does not compile | **M1f** inner-layer recording removed; **M1g** root recording removed |
| 1.7 | `theElementBoundsLogIsEmptyUnlessRequested` | does not compile | **M1h** recording defaults on |
| 1.8 | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement` — three `ProbeLeaf`s, one answering 21 wide only under the proposal authority; `try #require(report.elements == 4)` | does not compile | **M1i** `compare` renders the legacy authority twice |
| 1.9 | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` — three arms: (a) a clickable labelled `ProbeLeaf` offset under the proposal authority: `scenesEqual`, `hitboxesEqual`, `accessibilityEqual` false (geometry), `stateSlotsEqual` true; (b) unoffset, minting its `$probe` state entry **only under the proposal authority**: `stateSlotsEqual` false, the other three true; (c) unoffset, no extra entry: all four true; (d) (lane-1 verifier round) two unoffset leaves, the first painted on a raised layer under the proposal authority only: `scenesEqual` false (the finalized scene), the other three true | does not compile; arm (d) red at `ea7ac56` (`scenesEqual` compared emission bytes only) | **M1j** the hitbox comparison returns `true`; **M1l** `stateSlotsEqual` returns `true` (arm b reddens); **M1m** the scene comparison reads emission bytes only (arm d) |
| 1.10 | `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities` — fixed children only (`§5.3`) | does not compile | **M1k** the proposal-side root aligned `.center` |
| G1 | guard `aPlainImportCannotChooseTheLayoutAuthority` (`typecheckFile`, `SA-P`): `Window(…).layoutAuthority = …` does not compile outside the module | — (new guard) | **mutated red once**: `LayoutAuthority` and the property made `public` |

### Lane 2 — the lowering table's leaf half: childless `Box`, `Text`

Files: `Sources/MetalUI/LegacyLowering.swift` (new), `Box.swift`, `Text.swift`
(`swift package clean` — `Layout.measuredNode` was added and then removed,
`LR-X`); `Tests/MetalUITests/LoweringLeafTests.swift`, and 1.5's `Box`, `Text`,
`ModifiedElement` and `List` arms in `LayoutAuthorityTests.swift` (a leaf now
lowers: the `Box` and `Text` arms declare `flexGrow`, the layers' `Box` reports
nothing, `List`'s spacer reports `box.flexShrink`). **No change to
`ProposalText.swift`** (`LR-F`, critic round 1 finding 10).

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` — px and rem arms, decorated and clickable | `(.box, "noLowering")` reported | **M2a** rem lowered as px (× 1) |
| 2.2 | `aLoweredBoxPaddingSitsInsideItsDeclaredSize` — padded sized (agrees, probe B1), padded unsized (agrees), size below padding (reports `padding.floor`) | reported | **M2b** padding placed outside the size frame |
| 2.3 | `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` — one arm per row of §5.4's **every node** table's "otherwise" column (`display.none`, `size.percent`, `padding.percent`, `padding.floor`, `padding.text` on a `Text`, `minSize`, `maxSize`, `margin`, `border`, `position`, `inset`, `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`), each on a childless `Box` and on a `Text` except where the row names one; plus four combined rows on both sites (verifier round, lane 2): `padding.floor` on the width axis alone and on the height axis alone, `display.none` with a margin reported alone (`LR-J`), `margin` + `flexGrow` reported in the table's order; `try #require` on the arm count (37) | reported at site level only | **M2c** the `margin` check deleted; **V3** the floor check's height half deleted; **V4** `display.none` not returned alone; **V5** only the last field recorded |
| 2.3b | exit test `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction` — diagnostics off, `margin` + `flexGrow` on a `Box`: stderr names `box.margin`, not `box.flexGrow` | — | **V5** |
| 2.3c | `aLoweredBoxRegistersItsAnimatedWidth` — width 20 → 100 under `withAnimation(.linear(duration: 1))`: 20 at the transaction's start, 60 half-way, under both authorities (lane 2's own pin; 5.6 remains the stage's) | — | **V7** `Box` lowers its declared style |
| 2.4 | `everyContainerFieldIsIgnoredOnALoweredLeaf` — one arm per container field of §5.4's leaf paragraph, with its most unlowerable value, plus `aspectRatio` and `overflow`; empty report, rect agrees | reported | **M2d** `.rowReverse` reported on a leaf |
| 2.5 | `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` — short/long × 13/22pt × with/without `.foregroundColor`; bounds and glyph scene | reported | **M2e** the lowered leaf ignores `fontSize` |
| 2.6 | `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` — `Text(long)` **directly in a 60-wide harness root** (`LR-X`: a `Column` lowers only in lane 3; the root `Stack`'s fit-content offer is a column item's cross-size rule, ST-H/TX-H): legacy 60, lowered the shaping cache's widest line at 60 (44 on the design machine; SwiftUI 45, T2), `try #require(legacy != lowered)` | reported | **M2f** the answer is the proposed width |
| 2.7 | **characterization** `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal` — widths 0 and 5 answer the widest character with its hanging space (11.18; `LR-X`: the design said widest word, 40.44) and 592 tall (SwiftUI 0 and 5 × 592, T3/T4), pinned wrong on purpose, owner stage 2 | green on arrival | **M2g** a `min(widest, proposal)` clamp added to `proposalTextMeasurement` |
| 2.8 | `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` — `Text(long).width(100)`, `.width(30)`, `.width(5)` and `.height(40)`: bounds and glyphs equal; **the arms run in a child process** (`LR-X`) | reported; the 30 and 5 arms red on the `measuredNode` spelling (`57c6250`) | **M2h** the element's node returned as the leaf, not the frame (in-process it truncated the suite on `CN-L`'s one-parent precondition); **M2i** glyphs wrapped at the leaf's answer rather than the frame's width |

### Lane 3 — containers: `Row`, `Column`, `Box` with children; mixed trees

Files: `LegacyLowering.swift`, `Box.swift` (the container branch; `Row`/`Column`
reach it through `box`); `Tests/MetalUITests/LoweringContainerTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` — axis × gap {0, 10} × `alignItems` {start, centre, end} over three children of different cross sizes | reported | **M3a** cross `flexStart`↔`flexEnd` swapped; **M3b** spacing dropped |
| 3.2 | `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` — `gap(horizontal: 4, vertical: 20)` on a row and a column | reported | **M3c** the gap's axes swapped |
| 3.3 | `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` — 100×60 × 3 × 3 | reported | **M3d** the frame's main and cross alignments swapped |
| 3.4 | `aLoweredContainerPaddingSitsInsideItsDeclaredSize` — the counter chrome's shape (B3) and a sized padded container | reported | **M3e** padding outside the frame |
| 3.5 | `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` — agreeing: single-child auto `Box` over a fixed child and over a `Row`, unsized `spaceBetween`; reported, one arm each (`try #require` 16): two-child stretch (legacy rect pinned), sized single-child stretch, the three `space-*` with a main size, both reverses, baseline, wrap, `alignContent`, main-axis `gap.percent`, cross-axis `%` gap (not reported), `margin` and `padding.floor` on a container, a hidden reverse container (`display.none` alone), a `display: .stack` `Box` container (`noLowering`, added after M3l, `LR-Y`) | reported | **M3f** stretch always lowerable (the two-child arm reports nothing and disagrees); M3i–M3r each row's check deleted |
| 3.6 | `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` — `Row { 80; 80 }.width(100)`: legacy 50/50, lowered 80/80 from x 0; `try #require` disagreement (divergence 55; stack-algorithms **G9**, **X13**) | reported | **M3g** the size frame aligned `.center` (lowered x −30) |
| 3.7 | `aProposalElementInsideALoweredContainerLaysOutUnderTheProposalAuthorityAndTrapsUnderTheLegacyOne` (`LR-T`) — `Column { Box; HStack {…}; ProposalScrollView {…}.frame(…) }`: proposal arm lays out with an empty report (**a `try #require`**: the `Window` half renders without diagnostics, and as an `#expect` the red run truncated there, practices shape 13), literal rects, one scroll region, and a wheel event through a `Window` moves the `ProposalScrollView`'s offset; legacy arm is an exit test naming `SA-G`'s `newNode` message | reported (`box`) | **M3h** the container branch reports `box.nativeChild` for a native child (the proposal arm's empty report reddens; every child is native under this authority, so the mutant reddens every lane-3 test) |
| 3.8 | `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap` (verifier round) — a row `Box` over two 10×10 children animating width 40→120, padding 0→8, main-axis gap 0→20 under `.linear(duration: 1)`: transaction start 40×10 with b at x 10, half-way 80×18 with a (4, 4), b (24, 4), under both authorities | green on arrival (pins current behaviour) | **V1** the container branch lays out `declared` (size frame, padding, gap) |
| 3.9 | `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (verifier round, `LR-Y`) — `Box { a; b }` with `rowReverse`, `flexWrap`, `margin`, `flexGrow`: report `[reverse, flexWrap, margin, flexGrow]`; exit test: production traps naming `box.reverse`, not `box.margin` | green on arrival | **V2** every-node rows first; **V2b** `flexWrap` checked before `reverse` |

### Lane 4 — `Stack` and `ModifiedElement` layers; ideal under the proposal authority

Files: `LegacyLowering.swift`, `Stack.swift`, `ModifiedElement.swift`
(`ModifierLayer.frameSpec`; `swift package clean`), `FrameLayer.swift`
(`FrameSpec.idealWidth`/`idealHeight`; the `FR-D` trap moves from
`frame(minWidth:idealWidth:…)` to the legacy registration branch);
`Tests/MetalUITests/LoweringStackAndLayerTests.swift`, and the amended pin in
`FrameSizingTests.swift`; also (lane 4) 1.5's `Stack` and both `ModifiedElement`
arms in `LayoutAuthorityTests.swift` (they now declare a field the tables report)
and 3.5's `display: .stack` `Box` arm (`LR-Y`'s amendment), and a doc comment in
`NativeModifiedContent.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 4.1 | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` — nine alignments × unsized and sized-with-`Style.padding`; plus (lane 4) an arm declaring the flex container fields a stack does not read (empty report, agrees) and five reported arms (`Box` with `display: .stack` → `alignItems.stretch`, `justifyItems.stretch`; stretch; baseline; `margin`; hidden → `display.none` alone) | reported | **M4a** the overlay's horizontal and vertical factors swapped |
| 4.2 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` — `Stack { Text(long) }` inside a 60-wide `Column` in the harness root: legacy text box 60, lowered its widest line; `try #require` disagreement (divergence 53, stack-algorithms A5) | reported | **M4b** each lowered child wrapped in a native `fixedSize` |
| 4.3 | `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` — `.padding(4).padding(8)`, asymmetric edges, over `Box` and `Text`, with backgrounds | reported | **M4c** top and bottom insets swapped |
| 4.4 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` — nine alignments × child smaller and larger than the frame; plus (lane 4) a frame over no node | reported | **M4d** frame alignment forced `.center` |
| 4.5 | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` — `minWidth 40, maxWidth 80` over 20 (legacy 40, lowered 80; D control) and `maxWidth: .infinity` alone (legacy 20, lowered 100; `FR-O`), each inside a 100-wide `Column` | reported | **M4e** the maxima not passed to the kernel frame (a frame without a maximum is not greedy: 40 and 20, the CSS clamp's answers) |
| 4.6 | `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne` — exit test at legacy **render** (stderr names `idealWidth` / `idealHeight`); proposal arm, in a child process, measured at a nil proposal by a test-only `NilProposal` layout answers the ideal (frame probe C1: 80×20; and 20×80 for `idealHeight`). **Lane 4:** the first spelling put the frame in a lowered `Row`, which proposes its own finite proposal, so the frame answered its child (C control, 20×20) — nothing the stage-1 lowering registers proposes nil (`LR-Z`) | the construction trap fires first (the child exits on `SIGTRAP`) | **M4f** the ideal dropped from the lowering |
| 4.7 | `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries` — `.frame(width: 40)` animating to 80 reads the interpolated width under both authorities, and the report is empty at every frame | reported | **M4g** lowered from `FrameSpec` alone; **M4g′** the check compares the **animated** style (the mid-flight frame reports `modifierLayer.style`) |
| 4.8 | `aSizingModifierWrittenAfterAFrameIsReportedOnTheFrameLayer` — `.frame(width: 40).width(60)`, `.frame(width: 40).minWidth(10)`, `.frame(maxWidth: 80).flexGrow(1)`, and (lane 4) `.frame(width: 40).alignItems(.flexEnd).padding(4)` on an inner layer: each reports `modifierLayer.style`; control `.frame(width: 40).background(.accent)` reports nothing and agrees | reported (`modifierLayer.noLowering`) | **M4h** the comparison made against `frameSpec.style()` without `lowered(_:childCount:)` (the control arm, a one-node frame, reports) |
| 4.9 | `aHiddenFrameLayerIsReportedAsDisplayNone` — `.frame(width: 40).hidden()` on one node and on two, with a `.width` after it, and on an inner layer; plus (lane 4, `LR-Z`) a two-node frame, not hidden, reporting `frame.multipleNodes` | reported | **M4i** the `display.none` check moved after the comparison (the entry reads `modifierLayer.style`) |
| 4.10 | `aLoweredStackLaysOutItsAnimatedWidthAndPadding` (verifier round) — a `.topLeading` `Stack` over a 10×10 box, height 20, width 40→120 and `Style.padding` 0→8 under `.linear(duration: 1)`: start 40×20 box (0, 0), half-way 80×20 box (4, 4), both authorities | passes on arrival (pins current behaviour) | **V4** the `Stack` branch's `paddedAndSized` reads `declared` |
| 4.11 | `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle` (verifier round) — `.frame(minWidth:)`, `minHeight`, `maxWidth` (over 100×10), `maxHeight` (over 10×100), each 40→80: 40, 40, 60 on the animated axis, both authorities | passes on arrival | **V2**/**V2h**/**V2x**/**V2y** that bound read from `FrameSpec` instead of the animated style |
| 4.12 | `aFrameOverNoNodeFixedOnOneAxisOrMinOnlyIsZeroOnTheOther` (verifier round) — `NoNodes().frame(width: 40)` and `.frame(minWidth: 40)`: 40×0 on both sides, full agreement | passes on arrival | **V6** the stand-in leaf answers 10×10 |
| amended | `anIdealDimensionOnTheLegacyFrameTraps` — its closures now **render** under the legacy authority (the proposal control renders a proposal root: a legacy harness `Stack` over a native node is `SA-G`'s trap); stderr still names `idealWidth` | — | the lane records that its old spelling (construction only) goes green-by-success, which is the amendment's evidence |

### Lane 5 — demo content as a library; corpus; pipeline parity; depth and work

Files: `Package.swift` (a `MetalUIDemoContent` library target, `LR-S`),
`Sources/MetalUIDemoContent/` (the part of `Sources/MetalUIDemo/main.swift` before
`runDemo()`: models, actions, `CounterPanel`, `demoContent()`,
`PreviewToggle`, `PriorityPreviewPanel`, `nativeLayoutPreviewContent()`, with
`@MainActor` on the module-level state `gen.py` today rewrites to
`nonisolated(unsafe)`), `Sources/MetalUIDemo/main.swift` (imports it);
`Tests/MetalUITests/LoweringCorpusTests.swift`,
`LoweringPipelineParityTests.swift`. The lane's first commit is the move alone,
verified by the twelve images (0 px against `c2290fc`, the generator reading the
library instead of copying `main.swift`) and the unchanged suite count.
**Lane 5 also changed** (`LR-AA`): `Window.swift` (`recordsElementBounds`,
`lastElementBounds`; `swift package clean`), `ElementGroup.swift` (`AnyElement`'s
group entry records its bounds — the corpus found the log blind to it),
`LayoutDifferential.swift` (`WindowPair`, `compareInWindows`), and doc comments
that cited `Sources/MetalUIDemo/main.swift` for content now in
`Sources/MetalUIDemoContent/DemoContent.swift`. The corpus's demo trees drop the
stage-2 fields they carry (`LR-AA` item 1), and 5.4–5.6 use a test-only
`LowerableCounter` (item 2).

| # | test | red before (on lane 4's tree) | mutation |
|---|---|---|---|
| 5.1 | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` — the counter chrome, the demo header and stack cluster in lowerable spelling (`LR-AA`), T5/T5b/T6/T7, a `ModifierCompositionProofTests` chain (over a `Box`, not its custom `CountingLeaf`), and transparent groups (`if`/`else`, `if`, `for`, `EnvironmentScope`, `.disabled`, `AnyElement`), ten trees; per tree `try #require(report.elements == N)` with N derived by hand, and literal rects where no text decides them | the corpus file does not exist; the lane runs each tree against lane 4 first and records any disagreement as a finding before writing the literal. **Red on `f508003`**: the transparent groups read 10 elements where the derivation says 11 (`AnyElement` recorded no bounds, `LR-AA`) | **M5a** the proposal-side harness root proposes nil×nil; also re-run one mutation from each of M2–M4 and name 5.1 among the reddened (M2e, M3b, M4h); **MA** `AnyElement`'s record removed |
| 5.2 | `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm` — T8 text hug (T2/T7), `Stack` fit-content (A5), flexible frame (D), row overflow (G9): literal rects on both sides, `try #require` disagreement | — | **M5b** a probe-backed branch reverted (M2f) reddens it |
| 5.3 | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` — **`demoContent()` imported from `MetalUIDemoContent`**, one frame at 920×560 inside the harness root under diagnostics; the multiset of `(site, field)` as a literal the lane measures, each entry annotated with its owning stage (measured by the lane, not predicted: scratch P2's whole-demo census in §2.7 item 2 is not this literal, because P2 built the `List`'s rows and lane 1's `List` check does not) | site-level only | **M5c** two-child stretch made lowerable (the count moves) |
| 5.4 | `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` — a `WindowPair` (400²) with the counter (`LowerableCounter`, `LR-AA`) **inside `DifferentialRoot`**; click "+" twice, focus, "=" bound to `Increment`; the count reads 2 then 3 under both, every observation agreeing after each step | does not compile (`Window.lastElementBounds`) | **M5d** lowered stack spacing + 50 (the click misses); **MW** `lastElementBounds` not captured |
| 5.5 | `aLoweredWindowPublishesTheSameAccessibilityTree` — the same root, activated, clicked and focused; every tree `FakePlatformWindow` received, equal in order under both authorities, the two buttons' frames literal | does not compile | M5d |
| 5.6 | `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` — the same root; `StateTable.ids` equal, containing the counter's `$state0` (after a click), `$focus`, `$anim` and the "+" button's `$ax` (`LR-AA` item 6); a `Box` width and a frame layer width at t = 100, 100, 100.5 through the display link read 196, 196, 258 under both (measured by the prototype for the `Box`) | does not compile | **M5e** `lowerLegacyNode` given the style captured before `animated(…)`; MW |
| 5.7 | `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (`SA-M`'s method) — `Column { Row { a; b }; Row { c; Box { d }.padding(4) } }` of fixed leaves (10×20, 30×10, 20×10, 10×10) in a 200×100 harness root under the proposal authority: 16 native nodes, 118 misses, 94 hits, 4 calls, derived by hand **before** the run (the first run matched) | the file does not exist; the literals are written first and the run must match them, or the derivation is recorded as wrong before correcting it | **M5f** every lowered `Box` wrapped in an extra `padding(0)` (node count and work move) |
| 5.8 | `aLoweredChainAtTheNativeDepthLimitLaysOut` (`LR-Q`) — **an exit test whose child expects success**, so a mutation that makes it trap reddens it without truncating the suite: 29 nested `Box`es, each `Style.padding` 1, a declared size and `.alignItems(.flexStart)` (content → padding → frame = 3 native levels each, 87 in all, counted against `NativeLayoutRun.enter`), **as a production frame's root** — inside `DifferentialRoot` the root adds 2 levels (`LR-AA` item 7); the child prints 87 nodes | — | **M5g** the lowering emits a fourth native level per `Box` — the same edit as M5f (`LR-AA` item 8) |
| 5.9 | `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` — exit test: 30 such `Box`es (90 levels); stderr names `SA-L`'s message | — | **M5h** `NativeLayoutRun.maxDepth` raised to 96 (the child succeeds) |

**Stage 1's exit test is 5.1**; 5.3 is stage 2's entry.

**Counts.** Stage 1 adds 11 + 8 + 7 + 9 + 9 = **44 tests**, one of them the
guard G1 (a guard is a `@Test` and counts toward the suite); the amended pin is
not new. Expected at the end: **1401 tests**, **97 goldens**, **71 guards** — to
be re-measured, not trusted. Measured so far: lane 1 +12 (1369), lane 2 +10
(1379), lane 3 +7 (1386), lane 3's verifier round +2 (1388), lane 4 +9 (1397),
lane 4's verifier round +3 (1400), lane 5 +9 (**1409**, 97 goldens, 71 guards) —
lanes 1–4 each added verifier-round tests the plan did not count.

## 7. Demo comparison (`LR-M`)

At the end of **every** lane, against `c2290fc`, the twelve `CN-R` images (eight
legacy demo, two preview, two 560²): **0 differing pixels, scene identical**,
**re-taken on that lane's own tree with its real change**. The design's
prototype figure — 12 of 12 read 0 — belongs to **prototype P1** (record §18),
which had no `measuredNode`, no `frameSpec`, no `FR-D` trap move and no demo
library; it is not evidence for any lane (critic round 1 finding 8).

- **No stage-1 change reaches a production root.** The below-word clamp that the
  first design put into `proposalTextMeasurement` (the preview's measurement)
  is withdrawn (`LR-F`), so the preview's images are not evidence for any lane
  either; lane 5's library move is the one lane whose images are evidence (for
  "the move moved nothing").
- **The legacy images show only that the default branch moved nothing.** The
  harness's power to see a change is the base controls in §1.
- **Lane 5 adds two images** — the counter chrome **inside `DifferentialRoot`**,
  rendered through a `Window` under each authority — expected equal, with the
  M5d mutant as the control that must differ. (Lane 5: the corpus chrome,
  `StageOneCorpus.counterChrome`, in a 560² root in a 560² window, `LR-AA`.)
- **Real release-window captures.** The orchestrator's trigger is
  `IOConsoleLocked` reading `<false/>`. At design time it did, and captures were
  skipped because the session dictionary read locked (`FR-V`) — an override of
  the instruction, recorded in `LR-M`. From now on: at each lane's end, if
  `IOConsoleLocked` reads `<false/>`, run the lock probe; if the session
  dictionary also reads unlocked and awake, take the captures by `MC-J`'s method
  with no input; if it reads locked, **take one capture anyway** and record both
  readings and what the capture shows, so the override rests on an observation
  rather than on the ruling alone. At the critic round (21:16 PDT)
  `IOConsoleLocked` read `<true/>`.

## 8. Deferred to later stages (`LR-N`)

| item | stage |
|---|---|
| `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`, stretch with siblings or a declared cross size (including `MC-Q` finding 7, a nil-axis frame under a stretching `Box`), `justifyContent` distribution with a main size, CSS `min`/`max` clamps, percentages, `margin`, `border`, `display: none`/`hidden()`, Style padding on a leaf, the `BM-4` floor, overflow compression (divergence 55), `Row`/`Column` default spacing (52), `SA-N` item 4, `ProposalText`/`Text` unification and the below-word answer (T3/T4, W2), reverse directions | 2 |
| `flexWrap`/`alignContent` | deleted, 9/10 |
| `ScrollView` lowering and the fold of `ProposalScrollView`'s private clamp/indicator; divergence 54; `Component` distribution (`setStyle`), divergences 48 and 56, a frame over a multi-member component | 3 |
| windowed proposal `List` (`CN-T`'s transfer), `AXTable`, `MP-I`/`TB-AH`, probe K6 | 4 |
| `Deferred` as presentation (`CN-Q`); `position(.absolute)`/`inset`; divergences 9, 10, 11 | 5 |
| grids | G |
| custom elements' migration and the public legacy registrars' deprecation (`FR-I`'s one move, `LR-R`); tests about CSS answers pinned to `.legacy` | 6a |
| root placement (divergence 4 vs `CN-J`), default authority, the demo re-spelled, the release depth re-bisection, human-verification rows, real-window captures; production gains ideal, the greedy finite maximum (`FR-E`, divergence 35), the single-axis infinite maximum (`FR-O`) and `ZStack`'s offer (divergence 53) — all already lowered under the proposal authority in stage 1 | 6b |
| the 97 goldens, `GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/` | 7a |
| the non-golden CSS-engine tests and the `.legacy`-pinned element tests (`LR-U`) | 7b |
| `FR-F`/`FR-G`'s recipe, SwiftUI's centring of `Text(…).width(w)` (T7) | 8 |
| deleting the engine, legacy registrars, `textMeasure`/tokenizer min-content, the legacy authority | 9 |
| `Style`'s CSS fields; the mechanical check | 10 |
| `ModifiedElement`/`ModifiedContent` unification, legacy `.overlay`, `.opacity` before a background (G4, divergence 45), `.opacity` on both paths (`OM-AA` a) | 11 |
| `Component` `background`/`onClick`/`focusable` (outer-modifiers spec §9, "task 7 or later") | **task 8** (`LR-V`: not a layout item; nothing in the engine's deletion needs it) |
| text-edge spacing, baselines (`alignItems.baseline`) | task 11 |
| two-axis scrolling | task 10 |
