# Engine replacement, stage 8 — the sizing vocabulary (plan task 7)

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 8, §8; rulings `FR-F`, `FR-G`, `FR-H`, `FR-I`
([`../2026-09-15-frame-sizing-decisions.md`](../2026-09-15-frame-sizing-decisions.md)).
Rulings `LR-ER`…`LR-EX` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Record: `docs/record/50-engine-replacement-stage-8.md` (§2 the census, §3 the
scratch measurements, §4 the demo prototype, §5 the converter's viability).
Probe: `docs/probes/swiftui-engine-stage-8.swift` (groups F, P, T, output in its
header). Instruments: `docs/probes/stage-8-deprecation-sites.txt`,
`docs/probes/stage-8-demo-recipe.patch`, `docs/probes/stage-8-sizing-converter.py`.
Branch `feat/engine-stage-8` from `85217e3`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-8`.

**Status, 2026-09-24 (PDT): design.** No file under `Sources/`, `Tests/` or
`Package.swift` changed in a commit.

**What this stage is.** The eight `StyledElement` sizing modifiers (`width`,
`height`, `minWidth`, `maxWidth`, `minHeight`, `maxHeight`) and
`width(fraction:)`/`height(fraction:)` are **deprecated**, and every in-repo
caller moves off them **in the same change** — `FR-I`'s one move, as stage 6a
did for the public registrars, because the branch gates on 0 `warning:`. The
demo (production) is converted to `.frame` by the recipe (`LR-ES`) and reads 0
px against `85217e3`. Tests move by subject (`LR-EW`): to `.frame` where the
test is not about a `Style` field or a registration site (class **F**); to a
test-target spelling that writes the same `Style` field where it is (class
**K**, the stage-6a precedent of the internal undeprecated registrar); into a
deprecated protocol witness where the test's subject is the deprecated
modifier itself (class **D**). A framed box can now be an absolute
presentation's content (`LR-EV`), which is what makes the recipe total and
discharges the `…absolute` fields stage 5 left here. **It does not pre-empt
9–11**: no engine file, no `Style` field, no legacy registrar, no legacy
authority and no `Component` modifier is deleted or changed in meaning.

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [The recipe and the call-site classes](#5-the-recipe-and-the-call-site-classes)
6. [Lanes, and every test by name](#6-lanes-and-every-test-by-name)
7. [What must not move; the demo](#7-what-must-not-move-the-demo)
8. [Exit criteria](#8-exit-criteria)
9. [Handed on](#9-handed-on)

## 1. Baseline

At `85217e3`, measured 2026-09-24 in the worktree: `swift build --build-system
native --build-tests` (0 `error:`, one `warning:` — SwiftPM's deprecation
notice), unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1445 tests in 3 suites passed`**, the log carrying `FR-J
no-argument frame: succeeded=true`. 0 goldens, 78 guards, eleven gated tests
(record §49 §8).

## 2. The entry measurement

The deprecation, applied in a scratch build, warns at **1692** sites (record
§50 §2; `docs/probes/stage-8-deprecation-sites.txt` lists every one): **25 in
`Sources/MetalUIDemoContent`** (width 10, height 14, minHeight 1) and **1667 in
`Tests/MetalUITests`** across 55 files (width 822, height 800, minWidth 19,
minHeight 11, maxWidth 7, maxHeight 6, `fraction:` 2). Nothing in any other
target, `Backends/SDL`, `Tests/PortableTests`, `MetalUICrossPlatformTests`,
`MetalUILayoutTests` or `MetalUICoreTests` calls them, so **the portable CI count
(`MetalUICoreTests` + `MetalUILayoutTests` + `MetalUICrossPlatformTests`) does
not move**. One typecheck-guard fixture is affected (G4, §6 lane 3).

## 3. Decisions

| ruling | decides |
|---|---|
| `LR-ER` | scope: which ten modifiers are deprecated and which are not (`Component`'s, `flexBasis(fraction:)`, the item and container modifiers); every item earlier stages left to "stage 8" disposed by name — T7 closed by spelling, divergence 52 re-owned to stage 10, and **one rule for every `Style`-field report whose public modifier this stage deprecates**: the report stays, the spelling moves to `.frame` (which never reports), and the report dies with its field at stage 10; the `Style()` clause re-scoped |
| `LR-ES` | the recipe under the proposal authority (`FR-F` amended): R1–R8, each measured |
| `LR-ET` | `FR-G` amended: the automatic minimum under the proposal authority, the zero-minimum greedy frame as its spelling (probe F), and FR-G's live caller measured inert since 6b |
| `LR-EU` | `FR-I` and `FR-H` amended: the deprecation lands, with messages rather than `renamed:`; `fraction:` deprecated with no replacement; G4's control arm is a T row |
| `LR-EV` | a `.frame` layer written before `.position(.absolute)`/`.inset` is an absolute box: a presentation root under the proposal authority, its own bounds honoured as SwiftUI's frame (probe P); the `…absolute` `Style` reports re-owned to stage 10 |
| `LR-EW` | the call-site classes F, K, D (and R, expected empty); the identity, animation and site-coverage rules each conversion is checked against |
| `LR-EX` | three lanes, in order, deprecation last; the accounting (1445 − 0 + 7 = 1452; guards 78 → 79); the mutation plan |

## 4. API and files

**Public API.**

- `@available(*, deprecated, message: …)` on `StyledElement.width(_:)`,
  `height(_:)`, `minWidth(_:)`, `maxWidth(_:)`, `minHeight(_:)`,
  `maxHeight(_:)`, `width(fraction:)`, `height(fraction:)`
  (`Sources/MetalUI/Box.swift`, lane 3). Messages (`LR-EU`), each naming its
  replacement exactly as the guard N3.1 reads it:
  - `width`: `"use .frame(width:), which wraps this element in a layer instead of writing its own box (LR-ES)"`; `height` likewise with `.frame(height:)`;
  - `minWidth`/`maxWidth`/`maxHeight`: `"use .frame(minWidth:)"` (resp. `maxWidth:`, `maxHeight:`) `+ ", which wraps this element in a layer instead of writing its own box (LR-ES)"`;
  - `minHeight`: as `minWidth`, plus `"; a growing box's zero minimum is .frame(minHeight: 0, maxHeight: .infinity) (LR-ET)"`;
  - `width(fraction:)`/`height(fraction:)`: `"a fraction of the containing block has no SwiftUI counterpart and is unlowerable under the proposal layout authority (LR-AI); declare a length with .frame(width:)"` (resp. `height:`).
  - The existing `width(percent:)`/`height(percent:)` deprecations are unchanged.
- **Not deprecated** (`LR-ER` item 2): `Component.width`/`height`,
  `StyledComponent.width`/`height` (under the proposal authority each already
  lowers to one native frame per member — SwiftUI's answer, component
  distribution probe G7/G8 — and `Component.frame` over several members is a
  horizontal row, `LR-BH`, so it is not a rename target); `flexBasis(fraction:)`
  and every item or container modifier (stage 10's, with their fields).
- **Behaviour** (`LR-EV`, lane 1): a `.frame` layer whose declared style is
  `position: .absolute` (a `.position(.absolute)`/`.inset` written after the
  frame) no longer reports `modifierLayer.style` for those two fields; inside a
  `Deferred` it is a presentation root like any absolute box, its `FrameSpec`
  bounds honoured by its own kernel frame and never reported as `…absolute`;
  outside a `Deferred` it reports `modifierLayer.position`/`.inset` as an
  absolute box does. Every other field written after a frame still reports
  `style`. No production tree takes this path today (the demo has no sized
  absolute box); before this stage the spelling trapped.

**Internal / test API.** `Tests/MetalUITests/CSSSizing.swift` (new, lane 1): an
`extension StyledElement` in the test target with `cssWidth(_:)`,
`cssHeight(_:)`, `cssMinWidth(_:)`, `cssMaxWidth(_:)`, `cssMinHeight(_:)`,
`cssMaxHeight(_:)`, `cssWidth(fraction:)`, `cssHeight(fraction:)`, each one
line calling the internal `modifying { … }` with **the same closure body** as the
public modifier it stands in for (`@testable import MetalUI`). Undeprecated, and
visible to no other module. It dies with the fields at stage 10.

**Files.** Lane 1: `Sources/MetalUI/LegacyLowering.swift`,
`Sources/MetalUIDemoContent/DemoContent.swift`,
`Tests/MetalUITests/CSSSizing.swift` (new), `PresentationLoweringTests`,
`PresentationWindowTests`, `AnimationTests`, `FrameSizingTests`. Lane 2: the 28
K files of §5. Lane 3: `Sources/MetalUI/Box.swift`, the 22 F files and
`ModifierTests` of §5, `ContainerCompileGuards`, `FrameSizingCompileGuards`.
**Nothing under `Backends/`, `Tests/PortableTests`,
`Tests/MetalUICrossPlatformTests` (in particular `Expected.swift`) or
`Package.swift` changes.** `FrameSpec`, `ModifiedElement`, `Style` and every
public type's stored properties are unchanged (no `swift package clean` owed by
the design; a lane that adds a stored property to a public type owes one).

## 5. The recipe and the call-site classes

### 5.1 The recipe (`LR-ES`)

Each rule is stated with the measurement behind it (record §50 §3–§4).

- **R1 — one frame per run.** A run of adjacent sizing calls on one receiver
  becomes **one** `.frame(...)` at the run's place: fixed axes as
  `frame(width:height:)`, bounds as `frame(minWidth:maxWidth:minHeight:maxHeight:)`;
  a later call on an axis wins. Two frames where one was meant add a layer and
  an identity level for nothing. (S1, S6, S8.)
- **R2 — paint, input and identity go after the frame.** A decoration
  (`background`, `cornerRadius`, `border`, `hoverBackground`,
  `focusBackground`, `focusBorder`, `opacity`, `clipped`), a handler (`onClick`,
  `onKey`, `onAction`, `focusable`, `keyContext`, `contentShape`,
  `allowsHitTesting`, `disabled`), an accessibility modifier and `.id()` written
  on the sized element move **after** the frame, so they land on the outer layer
  at the frame's size (`FR-F`'s recipe; `.id()` must be outermost, `MC-C`). A
  decoration given in an initializer (`Box(decoration:)`) becomes the
  equivalent modifiers after the frame (S2: **SAME**, `Box(decoration:)` vs
  `.background.cornerRadius` after the frame).
- **R3 — a sized container's frame reproduces where it put its content.** A
  container's own size becomes the frame's; its content hugs inside and the
  frame's `alignment:` puts it back: `Row` `.leading`, `Column` `.top`, `Box`
  `.topLeading`, a centring container (`alignItems(.center)` +
  `justifyContent(.center)`) the default `.center` — those two container
  modifiers are then dropped (S2). A container whose content fills (a greedy
  child) is proposed the frame's size and fills it anyway. A padded container
  keeps `.padding` before the frame and the frame's alignment follows the
  content's placement inside the padding (S5: `alignment: .top`; the demo's
  list row: `.leading`). **The converter applies R1 and R3 and flags the rest**
  (record §50 §5: 20 issues → 1 on 80 frames).
- **R4 — an item field never shares a chain with a frame.** A `Style`-writing
  modifier after a frame reports `modifierLayer.style` (S3c, a production trap);
  before it, the frame consumes and **drops** it (S3b, silent). So the item
  field is re-spelled in SwiftUI's vocabulary: `flexGrow(1)` on the main axis
  with a fixed cross size → `.frame(<cross>: v).frame(max<Main>: .infinity)`
  (S3a **SAME**); `flexShrink(0)` beside a fixed main size → dropped (a fixed
  frame is never compressed, 7a probe S1); `margin` → `.padding(...)` written
  after the decorations it must not cover; `alignSelf` → a greedy cross-axis
  frame with that alignment. `position(.absolute)`/`inset` are the exception
  (R6).
- **R5 — a fixed axis and a bound.** A fixed size and a bound on the **same**
  axis fold to one fixed value, `max(min, min(size, max))` (CSS's used size, the
  fold the lowering already applies, `LR-AG`). A fixed axis and a bound on the
  **other** axis are two frames, the flexible one inner, the fixed one outer,
  **both** aligned where the content sat (S7a: the other order stretches the
  greedy frame across the parent; re-measured with the fixed frame outer, the
  box is right — 120×220 at (0, 80) — but a default-aligned outer frame centres
  the hugging greedy frame, content at x 35 where the old spelling put it at 0,
  so the outer frame takes `.leading` too). The demo prototype's scroller box
  writes `.frame(width: 420)` without `.leading` and still reads 0 px because its
  viewport fills the frame (record §50 §4, Mc); lane 1 writes `.leading` there
  for R5's sake and its own comparison covers it.
- **R6 — an absolute box's size is a frame before `.position`.**
  `X.width(w).height(h).position(.absolute).inset(e)` →
  `X.frame(width: w, height: h).position(.absolute).inset(e)` (`LR-EV`; A1
  agrees under both authorities once lane 1 lands).
- **R7 — identity.** A frame layer takes the sized element's slot and the element
  moves one level down (`MC-C`: the outermost layer takes the parent's slot,
  inner layers are `positional(0)`). No runtime reset follows — the spelling is
  the same every frame — but any test that names a structural path changes. A
  literal path used only to **locate** state (`stateTable.peek(path)`, a
  `focus(path)` call) is re-derived for the new structure, provided the test's
  own `#require` instrument still separates; a path that is **asserted** as a
  value keeps its assertion and the site takes class K.
- **R8 — animation.** A frame layer's fixed size is read from its **animated**
  style (`lowerShownLegacyFrameLayer`'s `bound`), and its `$anim` slot sits at
  the id the sized modifier's slot sat at (R7: the frame takes the slot), so an
  animated `.width(a ? x : y)` converted to `.frame(width: a ? x : y)`
  interpolates as before (N1.5). **No animation snaps as a result of the
  stage's conversions**; one that would is a finding, not a row. The element
  that moved a level down carries no animated field of its own after R1.

### 5.2 The call-site classes (`LR-EW`)

- **F — converted to `.frame` by R1–R8.** Verified by the test's unchanged
  assertions, under **both** authorities where the test runs both, and by the
  site-coverage check (lane 3, §6). A conversion that changes an assertion's
  answer is re-spelled by R2–R5; if no recipe spelling restores it, the site
  takes K and the lane records the test and the assertion that forced it.
  **No assertion is edited.**
- **K — the `Style` write kept, through `CSSSizing.swift`** (`.width(x)` →
  `.cssWidth(x)`, exactly at the census's positions, nothing else on the
  line). Identity, answers and sites are unchanged **by construction** (the
  same closure body; N1.1 pins it). K is the class of a test whose subject is
  (K1) the lowering of a legacy `Style` field or a comparison of the two
  authorities, or (K2) a registration site's own behaviour — its decoration,
  handler, focus, accessibility or animation — where R2 would move that
  modifier onto a `ModifiedElement` layer and leave the named site unpinned
  while the test still passed (record §50 §5: `DisabledTests`' site loop).
- **D — the deprecated modifier's own tests.** Calls kept, inside a
  `@available(*, deprecated, message: …)` **protocol witness** reached through
  its requirement, which warns nothing (`docs/probes/swift-deprecated-witness-silence.sh`,
  stage 6a's `LR-CV`): `ModifierTests`' eight sizing rows (the census's 8: the six clamps and sizes plus the two `fraction:` rows), and the old-spelling
  arms of N1.1, N1.5 and N1.6.
- **R — retired with a row.** **Expected empty**: K is always available and
  changes nothing, so no test needs to die for this stage. A lane that retires
  one writes a row in 7a/7b's format and says why K did not serve.

**The files, by class and lane** (site counts from the census):

| lane | class | files (sites) |
|---|---|---|
| 1 | F/K per test | `PresentationLoweringTests` (56, K1 — its subject is the presentation lowering — except arms that pin `LR-EV`), `PresentationWindowTests` (24, F: R6), `AnimationTests` (26, K2 — the own-style animation of each site, `everyRegisteringSiteAnimatesItsStyle`'s neighbours), `FrameSizingTests` (13, F), demo (25, F) |
| 2 | K | K1: `LoweringItemTests` 142, `LoweringComponentTests` 62, `HiddenLoweringTests` 42, `LoweringScrollTests` 36, `RootFieldLoweringTests` 26, `LoweringBoxModelTests` 23, `LoweringPipelineParityTests` 21, `LoweringCorpusTests` 19, `LoweringStackAndLayerTests` 18, `LoweringContainerTests` 18, `LayoutAuthorityTests` 18, `LoweringLeafTests` 12, `LoweringDistributionTests` 8, `GridLoweringInteractionTests` 6, `ListLoweringTests` 5, `MeasurePerformanceTests` 5, `RootSwitchTests` 4, `ElementLayoutTests` 54 (its subject is an element's own box reaching the engine). K2: `OuterModifierMatrixTests` 194, `ModifiedElementTests` 5, `ModifierCompositionProofTests` 4, `DecorationPaintTests` 112, `FrameDecorationInteractionTests` 42, `BackgroundChainTests` 14, `PointerStatePaintTests` 16, `DisabledTests` 111, `AXEmitSiteTests` 46, `HitRegionTests` 52 — **1115 sites, 28 files** |
| 3 | F (K fallback per test) | `AccessibilityTreeTests` 94, `InputDispatchTests` 68, `AccessibilityDefaultsTests` 67, `FocusTests` 48, `KeymapTests` 20, `ComponentTests` 20, `ObservationTests` 17, `TrackInteractionTests` 16, `EnvironmentTests` 12, `ThemeTests` 11, `ScrollViewTests` 10, `GlyphEmitterTests` 8, `ElementGroupTrapTests` 8, `AccessibilityEndToEndTests` 8, `ListTests` 4, `HitboxTests` 4, `StateTests` 2, `ProposalNodeIDTests` 2, `FrameLoopTests` 2, `DeferredTests` 2, `TextSystemSeamTests` 1, `TextMeasureTests` 1 — **425 sites, 22 files**; D: `ModifierTests` 8 |

Totals: 144 + 1115 + 433 = **1692**. K is the larger class (≈ 1200 of 1667
test sites) **on purpose**: those tests pin the legacy lowering and the
per-site registration code that stages 9 and 10 delete, and converting them now
would either change their subject or silently move their pin to another site.
Each dies or is re-spelled with its field (§9).

`ThemeTests` and `GlyphEmitterTests` carry a site loop each
(`grep "every.*Site"`); lane 3 decides them by the K2 rule and the site-coverage
check, not by the table.

## 6. Lanes, and every test by name

Three lanes, run in order on one branch; each commits green (unfiltered suite,
0 `error:`, only the SwiftPM notice as `warning:` — lanes 1 and 2 add no
deprecation, so the gate holds before lane 3). Every mutation: commit first,
restore from a copy, full unfiltered suite, `git status --short` after, name
every test reddened.

### Lane 1 — the absolute arm, the helpers, the demo (`LR-EV`, `LR-ET`, `LR-ES`)

Steps: (1) `CSSSizing.swift` and N1.1; (2) `LR-EV` in `LegacyLowering.swift` —
the two prototype conditions of record §50 §3 **plus** dropping `item.kind !=
.frameLayer` from `planLegacyItems`' outside-a-`Deferred` `position`/`inset`
report, with its comment rewritten — and N1.2–N1.4; (3) N1.5, N1.6; (4) apply
`docs/probes/stage-8-demo-recipe.patch` and rewrite the demo comments that
would lie (the scroller box's "removing `.minHeight(Pixels(0))` still silently
overrides … 14000pt" paragraph becomes `LR-ET`'s finding; the `.height(_:)`/
`.minWidth(_:)` mentions; the `Chrome` typealias comment); (5) convert the four
test files by class. `Box.swift` is **not** touched (lane 3).

| test (file) | asserts | red before | mutation that must redden it |
|---|---|---|---|
| **N1.1** `theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite` (`CSSSizing.swift`) | for each of the ten, the `Style` a `Box()` carries after `.cssX(v)` equals the one after the deprecated `.x(v)` (called in a D witness), with distinct values per axis so a swapped axis differs; the list's count `#require`d == 10 | the helpers do not exist (build) | **M1g**: `cssMinHeight` writes `maxSize.height` → N1.1 |
| **N1.2** `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities` (`PresentationLoweringTests`) | A1 — `Box().frame(width: 20, height: 20).background(.accent).onClick {}.position(.absolute).inset(top 10, left 30)` in a `Deferred`: rect and hitbox (30, 10) 20×20 under `.legacy` and `.proposal`, the proposal report empty; the old spelling (A0, in a D witness) the same | proposal: 0×0 and `modifierLayer.style` (record §50 §3) | **M1a**: restore the exact `style` comparison → N1.2, N1.4 |
| **N1.3** `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes` (`PresentationLoweringTests`) | A4/A5 under `.proposal`: `.frame(minWidth: 100)` → 100×16, `.frame(maxWidth: 80)` → 80×16 over `Text("hi")` (probe P1/P2), no report; control arm (no frame) 11×16 | reports `modifierLayer.style` | **M1b**: drop the `.frameLayer` skip in `lowerPresentation` → N1.3 (reports `modifierLayer.minSize.absolute`) |
| **N1.4** `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred` (`PresentationLoweringTests`) | under `.proposal` with diagnostics: `.frame(20×20).position(.absolute).inset(…).flexGrow(1)` in a `Deferred` reports `modifierLayer.style`; `.frame(20×20).position(.absolute).inset(…)` in a `Column` with no `Deferred` reports `modifierLayer.position` then `modifierLayer.inset` | arm 2 reports `style` (not `position`) before step 2 | **M1c**: skip the comparison entirely when absolute → arm 1 green-for-wrong-reason, N1.4 red; **M1d**: restore the `.frameLayer` guard in `planLegacyItems` → arm 2 lowers silently, N1.4 red |
| **N1.5** `anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid` (`AnimationTests`) | the demo sidebar's shape (`Column{…}.alignItems(.stretch).flexGrow(1).padding(14)` + width 196 → 320 under `withAnimation`), old spelling (D witness) vs `.frame(width:, alignment: .top)`, driven by `simulateTick` at 0, ¼, ½ and the end: the padded box's rect equal at every tick and the mid ticks strictly between 196 and 320 (`#require`, so a snapping pair cannot agree at 196) | green on arrival — a must-not-move pin; its instrument is the mutation | **M1e**: `bound(_:_:)` in `lowerShownLegacyFrameLayer` returns the declared value → the frame snaps, N1.5 red |
| **N1.6** `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum` (`FrameSizingTests`) | S7a/S7b under `.proposal` through a `Window`-free `Frame` (400×300, a stretching `Column`): 80pt header, a 50×400 content in `.frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading).frame(width: 120, alignment: .leading)` — the box 120×220 at (0, 80), the content at (0, 80); without `minHeight:` the box answers the content's 400 and the header moves to y −90 (probe F0/F1; measured, record §50 §3); the old `.width(120).flexGrow(1).flexBasis(0).minHeight(0)` spelling (D witness) gives the first arm's three rects exactly | green on arrival (the kernel already agrees) — the pin the demo cannot give (record §50 §4, Mb) | **M1f**: `framed(_:)` passes `minHeight: nil` → N1.6 red |

Demo mutations Ma, Md, Me, Mf (record §50 §4) are re-run once on the lane's
commit against `theDemoFrameMatchesTheValuesRecordedOnMacOS`; each must redden
it. The lane also builds and runs `Backends/SDL` (record §40/§44: `python3
Backends/SDL/scripts/fetch-accesskit.py`, then `PKG_CONFIG_PATH=$PWD/.accesskit
swift test` in `Backends/SDL`): `PortableReplay` and `DemoCapture` must pass
unedited — the scene is identical, so the fixtures are.

### Lane 2 — class K (`LR-EW`)

Mechanical: re-take the census on the lane's base (a scratch deprecation
build), then in the 28 files replace each warned `.<name>(` at its exact
`file:line:col` with `.css<Name>(` — from the end of each file backward, so
positions hold — and nothing else. No test is added.

| check | how | must read |
|---|---|---|
| no answer moved | unfiltered suite before and after | the same count (lane 1's), all green, no test renamed |
| K reaches the same code | **M2a** (`planLegacyItems`: a declared `minSize` on an auto axis ignored) and **M2b** (`Box.paint` skips `paintDecoration`'s background half), each run on the lane's base and on its head | identical reddened test names, base vs head |
| nothing else changed | `git diff` of the lane | only `.x(` → `.cssX(` substitutions on census lines |

### Lane 3 — class F, class D, the deprecation and its guard (`LR-EW`, `LR-EU`)

Steps: (1) **before any conversion**, run the site-coverage mutations **Ms1**
(`Box.prepaint` passes empty `Handlers` to `registerAndScope`), **Ms2**
(`Text.paint` skips `paintDecoration`'s background half), **Ms3**
(`Stack.paint` skips the same) and record every reddened test name; (2) convert
the 22 F files with `docs/probes/stage-8-sizing-converter.py` plus R2, R4–R7 by
hand, helper return types changed where the compiler says (`-> some Element`),
K fallback per test where an assertion would move; (3) re-run Ms1–Ms3: **each
reddened set after ⊇ before**, else the file whose tests dropped out reverts to
K; (4) `ModifierTests` to D; (5) the ten `@available` attributes in `Box.swift`
and its "Size" section comment rewritten (the "None of the eight is deprecated"
paragraph and `minHeight`'s "the only way to cancel" table become `LR-EU`'s and
`LR-ET`'s text); (6) N3.1 and G4's T row; (7) both build systems at 0
`warning:`.

| test (file) | asserts | red before | mutation that must redden it |
|---|---|---|---|
| **N3.1** `theSizingModifiersAreDeprecatedTowardFrame` (`FrameSizingCompileGuards`, `typecheckFile`, plain `import MetalUI`) | a fixture calling all ten compiles; exactly **10** deprecations; each message contains its replacement's spelling (`.frame(width:)`, …, `no SwiftUI counterpart` for the two fractions); a control fixture spelling the same sizes with `.frame` draws 0 | the modifiers are not deprecated (count 0) | **M3a**: delete one `@available` → 9, N3.1 red (the new guard mutated red once, as every new guard is) |
| **T3.1** `thePercentSizingModifiersAreDeprecatedRenamesOfFraction` (`ContainerCompileGuards`, G4) — **a T row, not a removal** | its control arm read `deprecations(control) == 0` for `width(fraction:)`, `height(fraction:)`, `flexBasis(fraction:)`; it now reads **2**, and `flexBasis(fraction:)` alone reads 0; the `percent:` arm is unchanged (3 deprecations, each a rename) | the control reads 0 | **M3b**: delete `width(fraction:)`'s `@available` → the control reads 1, T3.1 red |

## 7. What must not move; the demo

- **Production behaviour and pixels**: `compare.sh <scratch> 85217e3 <lane
  head>` reads **0 differing, scene identical, in all fourteen images** at
  lanes 1 and 3 (the design's prototype already does, record §50 §4), and
  `theDemoFrameMatchesTheValuesRecordedOnMacOS` stays green with
  `Expected.swift` unedited. The recipe's reordering is what the comparison can
  see (Ma, Md, Me, Mf redden it); the zero minimum is not (Mb), which N1.6
  covers.
- **Identity**: the demo's converted elements each gain one identity level
  (R7) — the `CounterPanel`'s buttons, readout and badge, the sidebar, header,
  hairline, bar, avatar, stack children, modal card, list rows and scroller box.
  None is looked up by path (`counterID` is the panel's own named id, which
  does not move), so no focus, `@State`, `$anim` or accessibility node resets
  at run time; the whole suite's demo users (`RootSwitchTests`,
  `LoweringCorpusTests`, `PresentationWindowTests`, `LoweringItemTests`,
  `DemoFrameDeterminismTests`) are the check.
- **Hit testing, accessibility, animation**: the demo's `onClick`s, labels and
  `hoverBackground` all move with R2 onto the layer that carries the frame, at
  the same rect (S2); N1.5 pins the one animated size.
- **Every test not retired keeps its assertion** (T3.1 is the one T row).
  **Before − removed + added = after: 1445 − 0 + 7 = 1452.**
- `Sources/` changes only in `LegacyLowering.swift` (lane 1's `LR-EV`),
  `DemoContent.swift` (lane 1) and `Box.swift` (lane 3: attributes and
  comments); `git diff 85217e3 -- Sources` names no other file.

## 8. Exit criteria

1. **0 `warning:`** besides SwiftPM's notice on `swift build --build-system
   native --build-tests` **and** on the default build system (`swift build
   --build-tests`), with the ten deprecations in place; 0 `error:`.
2. Unfiltered `swift test --build-system native --no-parallel` → **`Test run
   with 1452 tests in 3 suites passed`**, the log carrying `FR-J no-argument
   frame: succeeded=` (guards ran); **79 guards** (`FrameSizingCompileGuards`
   2 → 3; `typecheckFile`'s helper count 38 → 39).
3. With the deprecations in, criterion 1's 0 is the census re-taken: no call
   site outside a D witness remains. `grep -nE
   '\.(width|height|minWidth|maxWidth|minHeight|maxHeight)\(' Sources/MetalUIDemoContent`
   returns only comment lines, and every remaining test call of the ten is
   inside a declaration marked `@available(*, deprecated, …)`.
4. The fourteen-image comparison against `85217e3`: 0 differing, scene
   identical. `DemoFrameDeterminismTests` green unedited. `Backends/SDL`'s
   `PortableReplay` and `DemoCapture` green unedited.
5. N1.1–N1.6, N3.1 green; each named mutation reddened what §6 names, and the
   site-coverage sets held (⊇).

## 9. Handed on

- **To stage 9**: the K1 tests' legacy arms die with the legacy authority; their
  proposal arms keep the `css*` spelling until stage 10.
- **To stage 10**: `CSSSizing.swift` and every `css*` site (≈ 1200) die or are
  re-spelled with `Style.size`/`minSize`/`maxSize`; the `Style()` writes in
  tests (record §50 §2's census, 232 lines in 50 files) likewise (`LR-ER` item
  6); every `Style`-field report stage 8 inherited and kept (`LR-ER` item 4:
  percentages, a non-greedy `maxSize`, a length `flexBasis`, a root's auto-axis
  min/max and margin, a floored `space-*`, `…absolute` on a `Style`-written
  box) dies with its field; divergence 52 (`Row`/`Column` default spacing,
  `LR-ER` item 3).
- **To stage 11**: `Component.width`/`height` vs `Component.frame` over several
  members (`LR-ER` item 2).
- **To the Record phase** (not before): CLAUDE.md/AGENTS.md — the "Sizing
  modifiers" paragraph ("Not deprecated (`FR-I`)" and "`.minHeight(0)` is the
  only way to cancel flex's automatic minimum (`FR-G`)" replaced by `LR-EU`'s
  and `LR-ET`'s rules), the counts, `LR-` next unused, the stage-8 bullet under
  "SwiftUI alignment", the `Deferred` paragraph's `…absolute` sentence; the
  frame-sizing decisions doc's `FR-F`/`FR-G`/`FR-H`/`FR-I` each gain an
  "Amended, stage 8" pointer; records §04/§05 if a divergence or inert row
  moves (none is expected: the `…absolute` gap was never numbered, `LR-CJ`).
  The frozen §19, records §14/§49 and the delivered 7b spec keep their text.
