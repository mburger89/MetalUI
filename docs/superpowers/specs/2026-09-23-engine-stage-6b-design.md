# Engine replacement, stage 6b — the root switch (plan task 7)

**Status, 2026-09-23 (PDT): DELIVERED.** Critic round 1 applied (`LR-DO`); lane 1
landed (hidden(), the root fold, depth; record §41 §10, `LR-DH`/`LR-DI`/`LR-DK`,
suite 1697); lane 2 landed (every red test made independent of the default;
record §41 §11, `LR-DG`/`LR-DQ`, suite 1698 at the inherited default); lane 3
landed and threw the switch (record §41 §12, `LR-DF`/`LR-DJ`/`LR-DL`/`LR-DR`) —
**1701 tests, 0 `warning:` on both build systems, `noProductionFrameReachesTheLegacyEngine`
green, production now runs `.proposal` by default.** **The Record phase (record
§41 §13–§18) has updated CLAUDE.md, AGENTS.md, records §03/§04/§05/README and
the plan; the suite was re-taken independently after `swift package clean` and
reads the same 1701 / 97 / 78.** The real-window capture was not taken at any
point in the stage — the screen was locked every time it was checked — and is
owed to the human (`LR-DM`). Every measurement below was taken on
`feat/engine-stage-6b` from `aef88ce` in
`/Users/maxburger/Developer/worktrees/MetalUI/stage-6b`, on scratch commits
`431d8bd` (arm F), `1c2fd9e` (arm G), `947cdd5` (arm H), `fd036b9`/`7218cd7`
(arm H0), reverted by `b77118e`, and `6cdde03` (arm G2, reverted by `e77375e`)
— after each revert `git diff --quiet aef88ce HEAD -- Sources Tests` succeeds. The
measurements, their logs' readings and the per-test tables are in
`docs/record/41-engine-replacement-stage-6b.md` §1–§8. Rulings `LR-DF`…`LR-DN`
in [`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md).
Probes: three SwiftUI probes **re-run 2026-09-23** with every output line found
verbatim in their recorded headers (`swiftui-stack-algorithms.swift` — the R
control and R1–R4 arms, `CN-J`; `swiftui-engine-replacement-stage1.swift` — H0–H2;
`swiftui-engine-replacement-stage2.swift` — V0–V3), and two new harnesses under
`docs/probes/`: `native-depth-ceiling/` (the release and debug re-bisection,
with its positive control) and `stage-6b-flip-instrument.patch` (arm G2, the
default flipped with its thirteen test-helper defaults and traps printed rather
than fatal). The twelve-image
harness `demo-pixels/ZZDemoPixels.swift` now captures the demo at the
window's default authority (`LR-DJ`).

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 row 6b, `LR-Q`, `LR-S`, §8. Stage 1 is record §18, stage 2 §21, stage 3
§25, stage 4 §27, stage 5 §29, stage 6a §38 (its §4 is this stage's work list).

**What §4.1 row 6b asks for.** *"`Window`'s default authority becomes proposal;
the demo is re-spelled for the semantics stage 2 changed, each pixel change
probe-backed; root placement ruled (divergence 4 vs `CN-J`); the native depth
limit re-bisected in release and re-measured on every production root
(`LR-Q`); the human-verification rows that read demo layout re-opened;
real-window captures. Exit: `noProductionFrameReachesTheLegacyEngine` —
`demoContent()` and `nativeLayoutPreviewContent()` imported from
`MetalUIDemoContent` (`LR-S`), plus a `List`, driven through a `Window`, with a
counter showing the legacy branch of `computeRootLayout` never ran. Goldens 0,
pixels **change**, each difference named."*

**The sentence this design turns on.** After stages 2–6a the flip is small in
`Sources/` (two defaults and a counter) and large in `Tests/`: **92 tests are
red** under the flipped default at `aef88ce` (record §41 §2), and **55 of the
92 (54 RP and the root arm of the RP+CSS-frame row), plus the 23 tests stage 6a
pinned to `.legacy` for this stage — record §38's 78 — are one thing: root
placement.** `CN-J` (probe R1/R2, re-run today) centres a native root at
its own answer; the legacy root filled every `auto` axis with the window
(`CS-I`, divergence 4) and sat at (0, 0). Those tests are about hit testing,
decoration, focus and accessibility, not about the root; they encoded
divergence 4 by writing literals for a top-left root. This design keeps `CN-J`
(`LR-DG`) and re-spells each fixture by one mechanical rule: **an `auto` root
axis gets the window's extent declared on it (the answer `CS-I` gave, now
spelled), a declared root axis gets its literals re-derived under centring.**

## 0. Critic round 1 (`LR-DO`) — overrides the sections it names

A critic round on `138746c` re-ran two probes byte for byte
(`swiftui-engine-replacement-stage1.swift`: 79 lines, 0 missing from its
header, H0 20×60 / H1 20×60 / H2 20×40; `swiftui-stack-algorithms.swift`: 787
lines, 0 missing, R control (0, 0) 100×100, R1/R2 (21, 40) 58×20), checked
that the instrument patch still applies (`git apply --check` clean) and that
`grep -rn "LayoutAuthority = \.legacy" Tests` reads the thirteen defaults
`LR-DF` names. Six defects, each fixed below and ruled in `LR-DO`:

1. **The root's `minSize`/`maxSize` were deferred past the stage that owns
   them.** `LR-AQ` (stage 2) wrote "a root frame is stage 6b's placement
   ruling"; `LR-DI` item 4 handed it to stage 8 and left a **production trap
   with no exit test** — any app whose root `Box` says `.height(370).minHeight(0)`
   (the shape `demoLikeRows` copies from real use) aborts on its first frame
   after the flip. **Fixed (lane 1):** at the root, a px/rem `minSize`/`maxSize`
   on an axis the root **declares** folds into that size exactly as stage 2's
   item fold does (`max(min, min(size, max))`, already ruled and pinned for
   items; CSS gives the same number, because a declared root axis is not
   touched by `CS-I`), and the root's record is consumed for that field. A
   min/max on an **auto** root axis, a root margin, a percentage, and a root
   `.absolute` keep reporting (owner 8 / 9 as `LR-DI` said) — and **each is
   pinned by an exit test through a production `Window`** (1.8), because a
   trap production ships is a trap the suite must show. §5.5 changes with it:
   `demoLikeRows`' root no longer reports, so the font-resolver test runs at
   the default with an **empty** report asserted (not `demoLikeRowsReport`), and
   the two tokenizer tests keep `.legacy` only for their own reason (the
   min-content probe pair), recorded per test.
2. **The animation hazard was stated, not measured, and pinned wrong.** §5.4
   says "the proposal path has no site-by-site animates-its-style guard" and
   hands one to 7b. Per-site proposal arms **exist**
   (`aLoweredBoxRegistersItsAnimatedWidth`, `aLoweredStackLaysOutItsAnimatedWidthAndPadding`,
   `aLoweredContainerLaysOutItsAnimatedWidthPaddingAndGap`,
   `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries`,
   `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle`,
   `aLoweredMarginRegistersItsAnimatedValue`,
   `aLoweredScrollViewKeepsItsTwoAnimationSlots`), and `ScrollView`'s lowered
   path calls `animated(` at **its own two sites** (`ScrollView.swift:393`,
   `:403` at `aef88ce`) that the legacy-pinned guard never reaches. Animation is
   on this stage's must-not-move list, so **lane 2 closes it here**: before
   pinning `everyRegisteringSiteAnimatesItsStyle` to `.legacy`, map each of its
   site arms (Box; Stack; ScrollView content; ScrollView viewport; Component's
   member declaration and a caller's modifier; ModifiedElement's inner layer and
   outermost) to the proposal-side test that pins it, write the missing arms as
   one new test `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`
   (2.1, §8), and mutate each new arm once (drop that site's `animated(` on its
   proposal path; name what reddens). The 7b hazard row in §11 is deleted.
3. **The pixels were accounted at a size production never opens.** The demo
   opens at **920×560** (`Sources/MetalUIDemo/main.swift`); the twelve images
   are 1024² and 560². A 560-tall window is where a vertical compression the
   square never sees would show. **Fixed (lane 3):** the harness gains two
   images, `prod-default-light` and `prod-modal-light` at 920×560 (a
   `width`/`height` pair in `capture`, the square arms untouched), taken at
   both commits by the same `compare.sh`, each differing region named against
   §9's causes; any region §9 does not name is a finding. The exit test (3.1)
   and the depth readings (3.3) drive the demo at 920×560 as well as 1024².
4. **Lane 3 was the largest lane and depth does not depend on the flip.**
   `maxDepth` 88 → 72, its doc table, the eight literal boundary tests,
   `LayoutTree.lastNativeLayoutDeepestLevel` and M3e/M3f **move to lane 1**
   (none reads the default authority). 3.3 stays in lane 3.
5. **1.6 could not be red.** If the legacy path emits nothing for a hidden
   subtree, M1g (the paint skip reading `display == .none`) changes nothing and
   1.6 stays green — a broken instrument. 1.6's fixture must give the legacy
   path something to emit for the hidden element (a `Text` child's glyphs, or
   its decoration), established by a `try #require` on a non-empty legacy
   emission before the comparison.
6. **Two predicted mutation sets were incomplete.** M3a (default back to
   `.legacy`) also reddens 3.2's proposal arm and 3.3 (a legacy frame runs no
   native layout, so its deepest level reads 0) — the prediction now says so.
   Lane 1's edits to `Frame.swift` may stop the instrument patch applying; if
   `git apply --check` fails, lane 1 regenerates it against its own HEAD and
   commits the regenerated patch, so lane 2 measures with the same instrument.

**Lane 1 (`LR-DP`) — overrides the rows it names.** (a) A hidden node lowers
as the display `hidden()` overwrote: `.stack` at site `stack`, a frame layer as
`lowered(frameSpec.style(), childCount:)`, `.flex` elsewhere; a `Box(style:)`
that declared `.stack` itself and was hidden lowers as flex (recorded
limitation). (b) The root carries `LR-DH`'s paint and hit gates too (root arms
in 1.2/1.3; M1i, M1j). (c) 1.8's px control is red before the fold. (d) The
eight depth tests' at-limit arms also read `lastNativeLayoutDeepestLevel == 72`
and `maxDepth == 72`; 4.8's chain is 13 inner rows over a bare `Box()` (no
whole N reaches 72 with a two-level innermost). (e) M1b re-spelled as M1b2
(both hidden branches), the first spelling being unable to reach 1.1. (f) The
rewritten tests are listed by name in `LR-DP` item 6; §5.5's font-resolver
report is empty. Measured in record §41 §10.

**Lane 2 (`LR-DQ`) — overrides the rows it names.** (a) The instrument reading
is **12 X** + 2 D (lane 1 retired three X rows and added 1.8), with no
`SIXB-WOULD-TRAP` line. (b) Two P-6b rows green under neither recipe and stay
`.legacy`, owner 7b: `alignItemsAndAlignSelfBothReachTheEngine` (the Dual leaf
records no `LoweredItem`, X2) and `hiddenAfterASingleChildLegacyFrameStillHidesTheElement`
(CSS's "takes no space", `LR-DH`); so 19 P-6b rows are re-spelled and M2d removes
20 pins. (c) A third recipe for the two `FrameLoopTests` resize tests: a greedy
flexible-frame root, since R-fill would make the rect follow the declaration.
(d) 14 rows took a recipe other than the predicted one (listed in `LR-DQ` item 4).
(e) Required-authority helpers' R-filled tests loop over both authorities.
(f) M2b leaves eight centre-reading R-centred tests green; M2a reddens all 28.
(g) §0 item 2's map, measured: the inner `ModifiedElement` layer and the lowered
`ScrollView` content's value were the unpinned arms (2.1 arms (a), (b)); the
viewport's values are unobservable under `LR-AS`; B-7 is pinned on the proposal
path by arm (c). (h) M2e is the fold removed, not the diagnostics flag dropped.
Suite after lane 2: **1698** (lane 1 closed at 1697 with 1.9). Measured in
record §41 §11.

**Lane 3 (`LR-DR`) — overrides the rows it names.** (a) The flip commit read
red exactly the two D tests (1698 tests, 3 issues); M3a reddens five tests (the
two D, 3.1, 3.2, 3.3). (b) 3.3's demo literal is **30**, not 29: re-measured
after `LR-DJ`'s re-spelling, whose declared row height is one more lowered level
(29 before it); the `List` root is **16**, its row spelled as the demo's (15
without the declared height, measured). (c) `LayoutTree.lastNativeLayoutDeepestLevel`
is `package` so `Window` can copy it into an internal
`Window.lastNativeLayoutDeepestLevel` (§4 did not list it). (d) The two 920×560
images read 95 649 / 100 745 differing, every region 55, its re-wrap or C — no
vertical compression; the twelve square images read §9's arm H numbers exactly.
(e) Captures owed to the human: the screen was locked at lane close. Measured in
record §41 §12.

**Suite count:** 1688 + 6 (lane 1, `hidden()`) + 2 (lane 1, 1.7–1.8) + 1 (lane
2, 2.1) + 3 (lane 3) = **1700**, re-measured by each lane — **1701** measured at
lane 3's close: lane 1 also added 1.9 (record §41 §10).

## Contents

1. [Baseline](#1-baseline)
2. [The entry measurement](#2-the-entry-measurement)
3. [Decisions](#3-decisions)
4. [API and files](#4-api-and-files)
5. [Every red test, with its disposition](#5-every-red-test-with-its-disposition)
6. [What must not move, and what does](#6-what-must-not-move-and-what-does)
7. [Lanes](#7-lanes)
8. [The exit test and the new tests](#8-the-exit-test-and-the-new-tests)
9. [Demo, pixels and captures](#9-demo-pixels-and-captures)
10. [Depth](#10-depth)
11. [Handed on, each with an owner](#11-handed-on-each-with-an-owner)

## 1. Baseline

`aef88ce`, `swift build --build-system native --build-tests` then unfiltered
`swift test --build-system native --no-parallel`: **`Test run with 1688 tests in
3 suites passed after 92.588 seconds`**, 0 `error:`, the only `warning:`
SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true` in the
log. Goldens 97, guards 78 (CLAUDE.md "Build and test", record §38 header).

## 2. The entry measurement

Three arms, each a full unfiltered run (record §41 §2):

- **Arm F** (`431d8bd`) is record §38's A2 re-taken at `aef88ce`: `Frame.init`
  and `Window` default `.proposal` with diagnostics on, §38's "eight helper
  defaults" flipped (as its commit `2a7cec0` spelled them: nine sites in eight
  files — `makeFakeWindow` and eight file-local helpers, `AXNodeTests` holding
  two), traps printed. **1688 tests, 90 red, 318 issues.** Of §38's 153
  rows, 89 are still red; the other 64 are every row stage 6a re-spelled or
  pinned (CE 6, CE+RP 23, CSS-frame 10, CSS-d48 5, CSS-pin 2, CSS-box 2,
  CSS-structure 12, N9 2) plus **two CSS-style rows that only looked fixed**
  (below). One red is new:
  `aDeprecatedRegistrarStillLaysOutUnderTheLegacyAuthorityAndTrapsUnderTheProposalOne`
  (stage 6a's own exit test, class X — its trap half cannot trap under the
  instrument).
- **Arm G** (`1c2fd9e`) is the real flip on the same helpers: diagnostics
  **off** as in production, only the traps made non-fatal and printed
  `SIXB-WOULD-TRAP: <site>.<field>` so the run cannot truncate. **The same 90
  red.**
- **Arm G2** (`6cdde03`; **the instrument**, `docs/probes/stage-6b-flip-instrument.patch`)
  is arm G plus **four more file-local helpers that default to `.legacy` and
  that §38's instrument never flipped** — `TextSystemSeamTests.render`,
  `EnvironmentTests.frame` and `.counts`, `ContainerIntegrationTests.render` —
  so **thirteen** test-helper defaults in all. **1688 tests, 92 red, 319
  issues**: the 90 plus `EnvironmentTests.aLocaleChangesNoTextMeasurement` and
  `dynamicTypeSizeChangesNoTextMeasurement`, §38's CSS-style rows, which were
  green in arms F and G only because their helper still said `.legacy`. **Arm
  G2 is this stage's entry measurement.** Its WOULD-TRAP lines are the tests a
  real flip would **abort**, not fail: the five AV rows (`display.none`), the
  RT row, `everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays`
  (`box.display.none`) and **two tests green in every arm** that §38's table
  never listed — `aWarmFrameTokenizesEachDistinctStringAtMostOnce` and
  `aWarmFrameReachesTheUncachedFontResolverZeroTimes` (`box.minSize.unconsumed`
  on `demoLikeRows`' root). Without the instrument either of those two
  truncates the suite.

| class (record §38 §4) | §38 count | red in arm G2 | owner here |
|---|---|---|---|
| X — exit tests of production traps; red only under the instrument | 13 | **14** (+ 6a's exit test) | — (green in the real flip; untouched) |
| D — asserts the default | 2 | 2 | lane 3 rewrites |
| N9 — legacy-authority boundary at the default | 5 | 3 (6a pinned 2) | lane 2 pins `.legacy`, owner 9 |
| RP — root placement | 54 | 54 | lane 2 re-spells (`LR-DG`) |
| CE+RP — pinned `.legacy` by 6a *for 6b* (P-6b) | 23 | 0 (pinned) | lane 2 unpins 21 and re-spells; 2 stay pinned as CSS answers |
| AV — `hidden()` reported | 5 | 5 | lane 1 lowers `hidden()` (`LR-DH`) |
| RT — a root's `minSize` no parent consumes | 1 | 1 (+ 2 aborting siblings) | lane 2 (`LR-DI` item 4) |
| CSS-structure / CSS-style / CSS-text | 14 / 7 / 3 | 2 / 7 / 3 | lane 2 pins `.legacy`, owner 7b |
| RP+CSS-frame | 1 | 1 | lane 2 pins `.legacy`, owner 7b |
| CE, CSS-frame, CSS-d48, CSS-pin, CSS-box | 25 | 0 | — (6a) |
| **total** | **153** | **92** | |

**Pixels, flipped against unflipped** (record §41 §4; the twelve-image
comparison `aef88ce` → `1c2fd9e`, arm G; the four extra helpers are
test-only and cannot move an image): the eight demo images differ
(172 789 pixels in `default-light-f0`), the two preview images and the chrome
pair read **0, scene identical** — the preview was already native, and the
chrome pair names its authority. Every differing region is named in §9.

**Depth** (record §41 §5): release and debug ceilings for nine node kinds on a
1 MB thread; the production roots' deepest native level through a `Window`.
§10.

## 3. Decisions

| id | decision |
|---|---|
| `LR-DF` | **The switch.** One constant, `Frame.defaultLayoutAuthority = .proposal`, is `Frame.init`'s default and `Window.layoutAuthority`'s initial value. Diagnostics stay off in production (`reportsUnlowerableFields` false). **No public spelling** of the authority (`LR-B`'s open question closed): `layoutAuthority` stays internal, pinned by the existing `aPlainImportCannotChooseTheLayoutAuthority`. The test helpers follow production: `makeFakeWindow`'s `layoutAuthority` becomes `LayoutAuthority? = nil` (nil leaves `Window`'s default), and the **twelve** file-local helpers that default to `.legacy` at `aef88ce` (record §41 §2 lists them; four were missed by §38's instrument) default to `Frame.defaultLayoutAuthority`. A grep for `LayoutAuthority = .legacy` in `Tests/` reads empty afterwards. |
| `LR-DG` | **Root placement: `CN-J` stands for every production root**; divergence 4 (`CS-I`) stays a live row **of the legacy authority only** until 7b retires the CSS-engine tests that pin it. Evidence: the R control and R1–R4 re-run today (a 58×20 root in a 100×100 host at (21, 40); a greedy root at (0, 0) 100×100). The fixture rule for tests that encoded divergence 4 by accident: **R-fill** an `auto` root axis (declare the window's extent on it with the root's own `Self`-returning `.width`/`.height` — identity unchanged, the legacy answer unchanged because it is what `CS-I` computed), **R-centre** a declared root axis (re-derive its literals by `(W − w) / 2`). |
| `LR-DH` | **`hidden()` lowers under the proposal authority**, as `LR-AK` ruled and `LR-AV` constrained: laid out as if shown (keeps its space — H1), joins `Frame.hiddenNodes`; paint skipped and hitboxes registered under `hitTestingDisabled` for nodes in `hiddenNodes` **only**; accessibility suppression reads `display == .none ∨ hiddenNodes`; `ModifiedElement` mirrors per inner layer (`MC-B`); `AnyElement`'s entry gains all three gates **reading `hiddenNodes` only**, so the legacy path is byte-identical. Focus and keys ungated (task 12). The legacy `hidden()` takes no space (CSS) — a divergence between the authorities pinned by `aHiddenChildTakesNoSpace` (stays `.legacy`, owner 7b). |
| `LR-DI` | **The 92 reds, disposed** (§5): X untouched; D rewritten; N9 pinned `.legacy` (owner 9); RP and 21 of the 23 P-6b re-spelled by `LR-DG`'s rule; `aHiddenChildTakesNoSpace` and `aNestedLayoutMatchesTheEngineRunDirectly` stay pinned as CSS answers; the twelve CSS rows and the RP+CSS-frame row pinned `.legacy` with owner 7b; **item 4 — the root's `minSize`/`maxSize`/`margin` keep reporting** (a production trap, `LR-AQ`'s measured "CSS applies them to a root"), owner stage 8, whose recipe turns `min*`/`max*` into `.frame`, a layer whose record is never reported. The two tokenizer tests are pinned `.legacy` (their subject is the min-content probe pair, legacy-only by their own comments); the font-resolver test runs `.proposal` with diagnostics and asserts the report exactly (`MeasurePerformanceTests`' `LR-BX` pattern). |
| `LR-DJ` | **The demo: one re-spelling, every other difference kept and named.** The list row's inner `Box` gains `.height(Pixels(28))` before its `.padding` (stage 2's `LR-AC`/X9: a stretched single-child container does not stretch its child, so the row's `.alignItems(.center)` had nothing to centre in; measured: legacy 0 differing in all twelve, the 15 392 row-label glyphs' `y − 6` gone). Kept: divergence 55 (the sidebar served its declared 196 / 320 where CSS shrank it), its paragraph re-wrap and, in the animation image, the one-line-taller paragraph; cause C (the modal card measured at 320); a one-point centring round in the counter's readout. Preview and chrome: 0. The pixel harness captures at the default authority. |
| `LR-DK` | **Depth: `NativeLayoutRun.maxDepth` 88 → 72** by `SA-L`'s own rule (0.60 × the smallest **debug** ceiling on a 1 MB thread, rounded down to a multiple of 8: 0.60 × 127 = 76.2). Release re-bisected for the first time: smallest ceiling 653 (stacks), 1 256 for the single-child kinds — 9× the guard. Production roots through a `Window`: demo **29** (modal and animation states alike), preview **10**, a `List` root **15**, all well under 72 (the demo at 0.40). Eight boundary tests re-derived. |
| `LR-DL` | **The exit test counts the legacy branch itself**: a `@TaskLocal` counter bumped only in `computeRootLayout`'s legacy branch (the only `computeLayout(` caller in `MetalUI`), read around a `Window` drawing the demo (modal off/on, animation on), the preview and a `List` root; a `.legacy` window in the same test is the positive control that the counter is reachable. |
| `LR-DM` | **Captures owed to the human; §03 rows re-opened by the Record phase.** The lock probe read `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at design; if it still reads so at stage close the real-window capture is recorded as owed. The rows re-opened: every §03 reading that names demo geometry — the sidebar width readings (`SZ-L`, 69/97/73/70 against 196), the animation look (73 → 114 → 113 pt), the modal card and list-row look, the release-window captures of 2026-09-17. |
| `LR-DO` | **Critic round 1** (§0): the root's px/rem `minSize`/`maxSize` on a declared axis fold into it (lane 1, `LR-AQ`'s hand-off honoured) and every root field that still traps is pinned through a production `Window`; the animation guard's proposal twin written in 6b, not owed to 7b; two 920×560 production-size images; depth moved to lane 1; 1.6 given something to emit; M3a's set completed. **Amends `LR-DI` item 4, §5.4's `AnimationTests` row, §5.5, `LR-DJ`'s image list, `LR-DK`'s lane and `LR-DN`.** |
| `LR-DN` | **Three lanes, run in this order, each ending green at the default it inherits**: lane 1 `hidden()` (Sources + its tests, no default change); lane 2 every red test made independent of the default (tests only); lane 3 the switch, the exit test, the demo, depth, pixels. Lane 3's first commit is the flip — the two `Sources/` defaults **and** the thirteen test-helper defaults, the real-flip half of the instrument patch — and must read red **exactly** the two D tests (the fourteen X tests are green again: their traps are fatal). |

## 4. API and files

**`Sources/`** (lanes 1 and 3 only):

- `Frame.swift` — `static let defaultLayoutAuthority: LayoutAuthority = .proposal`
  (internal); `init`'s `layoutAuthority` defaults to it; `computeRootLayout`'s
  legacy branch bumps `Frame.$legacyRootLayoutCounter` (a `@TaskLocal static var
  legacyRootLayoutCounter: LegacyRootLayoutCounter?`, `nil` in production, the
  `Shaper.runCallCounter` shape); lane 1's `hiddenNodes: Set<LayoutNodeID>`,
  `isHidden(_:)`, and `suppressingAccessibilityIfHidden` / `render`'s root
  check reading it.
- `Window.swift` — `var layoutAuthority: LayoutAuthority = Frame.defaultLayoutAuthority`;
  doc comment rewritten (no longer "`.legacy` until stage 6b").
- `LegacyLowering.swift` (lane 1) — the six `display == .none` report sites
  (`:94`, `:170`, `:207`, `:255`, `:346`, `:682` at `aef88ce`) lower as if shown
  and insert the element's node into `frame.hiddenNodes`.
- `ElementGroup.swift`, `ModifiedElement.swift`, `AnyElement.swift` (lane 1) —
  the paint skip and hitbox scope for `hiddenNodes`, per `LR-DH`.
- `NativeLayoutRun.swift` (lane 3) — `maxDepth = 72` and its table (release
  column added, the stale 151/128 rows superseded by the re-bisection); an
  internal `LayoutTree.lastNativeLayoutDeepestLevel` (the run's maximum
  `depth`, recorded where `lastNativeLayoutWork` is) for 3.3.
- `MetalUIDemoContent/DemoContent.swift` (lane 3) — the one `.height(Pixels(28))`.
- **Goldens and `Sources/MetalUILayout/` beyond `NativeLayoutRun.swift`: untouched.**
  `maxDepth` is not read by the CSS engine, so no golden can move; the 97 are
  checked anyway.

**`Tests/`**: lane 1 — `HiddenLoweringTests.swift` (new), the five AV tests;
lane 2 — the files of §5.2–§5.5; lane 3 — `Fakes.swift`, the twelve file-local
helper defaults (in `AXNodeTests` ×2, `DecorationPaintTests`,
`AccessibilityTreeTests`, `ScrollIndicatorTests`, `AccessibilityDefaultsTests`,
`ScrollViewTests`, `MeasurePerformanceTests`, `TextSystemSeamTests`,
`EnvironmentTests` ×2, `ContainerIntegrationTests`), `LayoutAuthorityTests.swift`,
`NativeDepthGuardTests.swift`, `LoweringPipelineParityTests.swift`,
`LoweringBoxModelTests.swift`, `LoweringCorpusTests.swift`, and a new
`RootSwitchTests.swift`.

## 5. Every red test, with its disposition

Arms: each row's reading in record §38's arms (C2: native root placed at the
window rect; C3: top-leading at its own answer; B3: custom elements lowered as
a `Box`, top-leading). **Red-before** for every row below is arm G's red (or,
for a P-6b row, arm F/§38 A2's red with its `.legacy` removed), recorded per
test in record §41 §3.

### 5.1 Lane 1 — AV (5)

`AccessibilityDefaultsTests.aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`,
`AccessibilityTreeTests.aHiddenInnerModifierLayerSuppressesEverythingInsideIt`,
`…aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`,
`…aHiddenRootPublishesNothing`,
`…hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`.
Each becomes a scenario parameterised over both authorities, recording
`AuthorityCoverage` (the roll call's 82 → **87**). Red-before: arm G reports
`box`/`modifierLayer.display.none` and aborts. Mutation **M1a** (the lowered
`hidden()` not inserted into `hiddenNodes`): all five red under `.proposal`,
green under `.legacy`.

### 5.2 Lane 2 — root placement (54 RP + 21 P-6b), by `LR-DG`

**The rule, per root axis, applied by reading the fixture — not by the arm
column**: an `auto` axis is R-filled (`.width(Pixels(W))`/`.height(Pixels(H))`
on the root, `Self`-returning, written where the root's other sizing modifiers
sit — **after** a `.padding` if the root has one, per CLAUDE.md's legacy
container rule, and never after a `.frame`, which reports `modifierLayer.style`);
a declared axis is R-centred (every absolute literal on that axis moves by
`(W − w) / 2`, derived in a comment before the run). A root that is not a
`StyledElement` (a `ScrollView`, a `Component`) or is a frame layer is R-centred
on both axes. A test whose root declares both axes is pure R-centre, whatever
its arm column says: C2 green there means only that the kernel's forced
window rect made a 40×40 root 100×100, not that filling is the fixture's meaning.

Every R-filled test must pass under **both** authorities (lane 2 runs the suite
at the default it inherits, `.legacy`, and again with the flip instrument —
both green); an R-centred test passes `.proposal` explicitly until lane 3's
flip makes it redundant (lane 3 may leave the argument). A P-6b row also moves
its custom element off the internal `Frame.requestNode`/`requestLeaf` onto
`requestNativeLeaf` of its declared size (6a's `declaredSizeNativeLeaf`) and
drops its `.legacy`.

Mutations for the section (lane 2, each a full unfiltered run under the flip
instrument): **M2a** `computeRootLayout` places the native root top-leading at
its answer (C3's placement) — must redden **every R-centred test and no
R-filled one**; **M2b** it places the root at the window rect (C2's) — must
redden every R-centred test with a declared axis smaller than the window;
**M2c** one R-filled fixture per file with its added sizing removed — must
redden that test (its red-before, re-read on the re-spelled tree).

| class | file | test | arms (§38) | predicted recipe |
|---|---|---|---|---|
| RP | AXEmitSiteTests | `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers` | C2 f C3 p B3 p | centre |
| RP | AXEmitSiteTests | `aNestedTextEmitsItsDeclaredAXNodeAtItsAbsoluteBounds` | C2 f C3 p B3 p | centre |
| RP | AXNodeTests | `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds` | C2 f C3 p B3 p | centre |
| RP | AccessibilityTreeTests | `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` | C2 p C3 p B3 p | fill |
| RP | AnimationTests | `hoverAndFocusFadeThroughTheSameEffectiveColourPath` | C2 p C3 p B3 p | fill |
| RP | BackgroundChainTests | `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour` | C2 f C3 p B3 p | centre |
| RP | BackgroundChainTests | `everyBackgroundPaintingSiteHonoursHoverAndFocus` | C2 f C3 p B3 p | centre |
| RP | DecorationPaintTests | `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `aBorderIsVisibleOverAChildThatFillsTheBox` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `aChainsOuterLayerScopesContainTheLayersInsideIt` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `aFocusRingOutranksAHoverBorderAndABorder` | C2 f C3 p B3 p | centre |
| RP | DecorationPaintTests | `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `clippedAlsoClipsTheHitboxesInsideIt` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain` | C2 p C3 p B3 p | fill |
| RP | DecorationPaintTests | `everyDecorationScopingSiteContainsItsOwnContent` | C2 p C3 p B3 p | fill |
| RP | DisabledTests | `aClickNeedsTheTargetEnabledAtPressAndAtRelease` | C2 p C3 f B3 f | fill |
| RP | DisabledTests | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` | C2 p C3 f B3 f | fill |
| RP | DisabledTests | `aDisabledScrollViewStillScrollsOnTheWheel` | C2 p C3 p B3 p | fill (a `ScrollView` root: centre) |
| RP | DisabledTests | `aDisabledTargetIsNeitherHoveredNorPressed` | C2 p C3 f B3 f | fill |
| RP | DisabledTests | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` | C2 p C3 f B3 f | fill |
| RP | DisabledTests | `theGateReadsTheEnvironmentValueNotTheModifier` | C2 p C3 f B3 f | fill |
| RP | EnvironmentTests | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` | C2 p C3 f B3 f | fill |
| RP | FrameDecorationInteractionTests | `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes` | C2 p C3 p B3 p | fill |
| RP | FrameDecorationInteractionTests | `aDisabledScopeAroundAFramedFocusRingSuppressesRingHoverAndClick` | C2 p C3 p B3 p | fill |
| RP | FrameDecorationInteractionTests | `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame` | C2 p C3 p B3 p | fill |
| RP | FrameDecorationInteractionTests | `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink` | C2 p C3 p B3 p | fill |
| RP | FrameDecorationInteractionTests | `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset` | C2 p C3 p B3 p | fill |
| RP | FrameLoopTests | `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` | C2 p C3 f B3 f | fill (at each window size) |
| RP | FrameLoopTests | `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize` | C2 p C3 f B3 f | fill (at each window size) |
| RP | GlyphEmitterTests | `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox` | C2 p C3 p B3 p | fill |
| RP | GlyphEmitterTests | `spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` | C2 p C3 p B3 p | fill |
| RP | HitRegionTests | `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout` | C2 f C3 p B3 p | centre |
| RP | HitRegionTests | `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration` | C2 f C3 p B3 p | centre |
| RP | HitRegionTests | `aContentShapeWithoutAClickHandlerRegistersNothing` | C2 f C3 p B3 p | centre |
| RP | HitRegionTests | `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse` | C2 f C3 p B3 p | centre |
| RP | HitRegionTests | `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor` | C2 f C3 p B3 p | centre |
| RP | HitRegionTests | `everyHandlerRegisteringSiteHonoursAllowsHitTesting` | C2 p C3 p B3 p | fill |
| RP | InputDispatchTests | `aClickInsideTheBoundsRunsTheHandler` | C2 p C3 p B3 p | **centre** (a 40×40 root: both axes declared) |
| RP | InputDispatchTests | `aClickOutsideTheBoundsDoesNotRunTheHandler` | C2 f C3 p B3 p | centre |
| RP | InputDispatchTests | `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler` | C2 f C3 p B3 p | centre |
| RP | InputDispatchTests | `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne` | C2 p C3 p B3 p | **centre** (40×40 root) |
| RP | InputDispatchTests | `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire` | C2 p C3 p B3 p | fill |
| RP | InputDispatchTests | `aNestedHandlerWinsOverItsContainingStackToo` | C2 f C3 p B3 p | centre |
| RP | InputDispatchTests | `aPressThatLeavesTheElementAndReturnsStillClicks` | C2 p C3 p B3 p | **centre** (40×40 root) |
| RP | InputDispatchTests | `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling` | C2 p C3 f B3 f | fill |
| RP | InputDispatchTests | `onClickIsLiveOnEveryConformerThatCanRegisterOne` | C2 p C3 p B3 p | fill |
| RP | InputDispatchTests | `onlyABoxWithAHandlerRegistersAHitbox` | C2 f C3 p B3 p | centre |
| RP | LayoutAuthorityTests | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` | C2 p C3 f B3 f | fill |
| RP | OuterModifierMatrixTests | `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten` | C2 p C3 p B3 p | fill |
| RP | OuterModifierMatrixTests | `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot` | C2 p C3 p B3 p | fill |
| RP | OuterModifierMatrixTests | `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes` | C2 p C3 p B3 p | fill |
| RP | PointerStatePaintTests | `aHoveredBoxPaintsItsHoverBackground` | C2 p C3 f B3 f | fill |
| RP | PointerStatePaintTests | `focusOutranksHoverWhenAnElementIsBoth` | C2 p C3 f B3 f | fill |
| P-6b | ComponentTests | `aComponentInsideAComponentFlattensThroughBothLevels` | C2 p C3 f B3 f | fill |
| P-6b | ComponentTests | `aComponentsContentFlattensIntoItsParent` | C2 p C3 f B3 f | fill |
| P-6b | ElementLayoutTests | `aStackCentresOnTheCrossAxisWhereABoxStretches` | C2 p C3 f B3 f | fill |
| P-6b | ElementLayoutTests | `alignItemsAndAlignSelfBothReachTheEngine` | C2 p C3 f B3 p | fill |
| P-6b | ElementLayoutTests | `anExplicitAnyElementIsStillAcceptedAsAChild` | C2 p C3 f B3 f | fill |
| P-6b | ElementLayoutTests | `childrenAreRegisteredAndLaidOutInSourceOrder` | C2 p C3 f B3 f | fill |
| P-6b | ElementLayoutTests | `columnStacksOnTheAxisRowDoesNot` | C2 p C3 f B3 f | fill |
| P-6b | ElementLayoutTests | `gapIsPerAxisAndTheRowReadsTheHorizontalOne` | C2 p C3 f B3 f | fill |
| P-6b | EnvironmentTests | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` | C2 p C3 f B3 f | fill |
| P-6b | FrameSizingTests | `aLegacyFramePlacesItsChildAtEachOfTheNineAlignments` | C2 f C3 f B3 p | centre (a frame-layer root) |
| P-6b | FrameSizingTests | `aLegacyFrameProposesItsWidthToAMeasuredLeaf` | C2 p C3 p B3 p | fill or centre by its helper's root |
| P-6b | FrameSizingTests | `chainedLegacyFramesAgreeWithSwiftUIsOrderingRules` | C2 p C3 f B3 p | fill or centre by its helper's root |
| P-6b | FrameSizingTests | `hiddenAfterASingleChildLegacyFrameStillHidesTheElement` | C2 p C3 p B3 p | fill; **needs lane 1** |
| P-6b | HitboxTests | `aMouseMovedEventMakesTheBoxUnderItHoveredOnTheNextFrame` | C2 p C3 f B3 f | fill |
| P-6b | HitboxTests | `aPressThatLeavesTheHitboxAndReturnsStaysActive` | C2 p C3 f B3 p | fill |
| P-6b | HitboxTests | `activeIsSetOnMouseDownAndHeldUntilMouseUp` | C2 p C3 f B3 p | fill |
| P-6b | HitboxTests | `activeSurvivesAFrameBoundary` | C2 p C3 f B3 f | fill |
| P-6b | HitboxTests | `hoverResolvedThroughARealRenderHasNoLag` | C2 p C3 f B3 p | fill |
| P-6b | ModifiedElementTests | `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer` | C2 p C3 f B3 p | fill |
| P-6b | ModifiedElementTests | `changingALayersValueKeepsTheWrappedElementsState` | C2 p C3 f B3 p | fill |
| P-6b | ModifierCompositionProofTests | `modifierOrderChangesSizeAndPlacementAsSwiftUIDoes` | C2 p C3 f B3 p | fill |

"Predicted" is the arm column read through the rule; the lane reads each
fixture's root and records every row where the rule gives a different recipe
(three are already marked **centre** above) — a disagreement is not a finding,
a test that neither recipe greens **is**, recorded with its arm and its cause.
`FrameSizingTests`' `render`/`widthInRow`/`nodeCount` and the two `observe`
helpers take the authority as a **required** argument (record §38 §17): lane 2
edits their calls, not a default.

### 5.3 Lane 2 — stays pinned `.legacy`, CSS answers (2 P-6b)

`ElementLayoutTests.aHiddenChildTakesNoSpace` (SwiftUI keeps a hidden child's
space — H1, re-run today — so "takes no space" is the CSS answer `LR-DH` leaves
on the legacy authority) and `ElementLayoutTests.aNestedLayoutMatchesTheEngineRunDirectly`
(its oracle is `computeLayout` itself). Each keeps `.legacy`; its doc line
moves from "Pinned … by stage 6a (CE+RP)" to "P-CSS, owner 7b (stage 6b,
`LR-DI`)". No mutation: an unchanged pin (their 6a mutations stand).

### 5.4 Lane 2 — pinned `.legacy`, owner 7b (13) or 9 (3)

| test | class | why a CSS / legacy answer |
|---|---|---|
| `FrameDecorationInteractionTests.aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembers` | CSS-structure | reads the legacy tree's node shape |
| `OuterModifierMatrixTests.everyOuterModifierIsWrapsOrPaintOnlyOrDistributesAsTheMatrixSays` | CSS-structure | ditto (its `box.display.none` report is gone after lane 1) |
| `AnimationTests.everyRegisteringSiteAnimatesItsStyle` | CSS-style | reads `tree.style`; **7b owes a proposal-side guard** (hazard, §11) |
| `StackElementTests.allNineAlignmentsMapToTheirPairAndTheNineAreDistinct` | CSS-style | reads `Style` alignment fields |
| `StackElementTests.stackDefaultsToCentreNotStretch` | CSS-style | ditto |
| `StackElementTests.stackWritesDisplayAndBothAlignmentFields` | CSS-style | ditto |
| `TextMeasureTests.aTextLeafCarriesAMeasureFunctionWhereABoxDoesNot` | CSS-style | reads `tree.measure` |
| `EnvironmentTests.aLocaleChangesNoTextMeasurement` | CSS-style | reads `tree.measure` through `textMeasure`; green in arms F/G only through its helper's `.legacy` default |
| `EnvironmentTests.dynamicTypeSizeChangesNoTextMeasurement` | CSS-style | ditto |
| `TextMeasureTests.aCentringColumnShrinkWrapsItsTextLikeWebKit` | CSS-text | a WebKit answer |
| `TextMeasureTests.aLongLabelInAStretchedColumnWrapsRatherThanOverflowing` | CSS-text | ditto |
| `TextMeasureTests.aTextPaintsItsBackgroundAndItsGlyphs` | CSS-text | ditto |
| `FrameDecorationInteractionTests.aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBox` | RP+CSS-frame | its fourth arm is `FR-E`'s legacy flexible frame (record §38 §7.2) |
| `NativeBoundaryIntegrationTests.aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration` | N9 | `SA-G`'s legacy-authority trap; owner 9 |
| `NativeBoundaryIntegrationTests.aPaddingModifierOnAProposalComponentTraps` | N9 | ditto |
| `NativeBoundaryIntegrationTests.aProposalElementInsideALegacyContainerTrapsAtRegistration` | N9 | ditto |

Mutation **M2d**, taken over the flip instrument: the sixteen `.legacy`
arguments removed together — exactly these sixteen red, nothing else. (The two
`EnvironmentTests` rows are pinned by passing `authority: .legacy` to
`textMeasure`'s frame, not by keeping the helper's default — lane 3 flips
that default.)

### 5.5 Lane 2 — `MeasurePerformanceTests`, `LR-DI` item 4 (3)

`aColdFrameCreatesAtMostOneLineBreakTokenizer` (RT, red) and
`aWarmFrameTokenizesEachDistinctStringAtMostOnce` (aborting, green in both
arms): **`.legacy`**, owner 9 (the min-content probe pair is deleted with the
tokenizer min-content). `aWarmFrameReachesTheUncachedFontResolverZeroTimes`
(aborting): **`.proposal` with `reportsUnlowerableFields: true`**, both renders'
reports asserted equal to `demoLikeRowsReport(.proposal)`; red-before: arm G's
WOULD-TRAP. Mutation **M2e**: the font-resolver test's `reportsUnlowerableFields`
dropped — it aborts (taken as an exit-test arm or over the instrument, recorded
which). `demoLikeRows`' root `.minHeight(Pixels(0))` is **not** removed (its
header's reason stands).

### 5.6 Lane 3 — D (2)

`aFrameAndAWindowDefaultToTheLegacyAuthority` → renamed
**`aFrameAndAWindowDefaultToTheProposalAuthority`**: `Frame.defaultLayoutAuthority
== .proposal`, a bare `Frame` and a `makeFakeWindow` window both read it,
`reportsUnlowerableFields` false. `aWindowBuildsEveryFrameUnderItsLayoutAuthority`:
the write order flips (`.legacy` then `.proposal`), log `[true, false, true]`.
Red-before: lane 3's bare-flip commit (these two and nothing else). Mutation
**M3a**: the default back to `.legacy` — both red, plus the exit test.

## 6. What must not move, and what does

### 6.1 Must not move — each with its pin

| what | pin |
|---|---|
| identity, `@State`, focus, `$anim` across a root switch | the R-filled tests keep their id literals (`Self`-returning sizing adds no layer); `ModifiedElementTests`, `ModifierCompositionProofTests`, `TombstoneTests`, `FocusTests` unchanged at the new default |
| hit testing, `allowsHitTesting`, `contentShape` | `HitRegionTests`, `InputDispatchTests`, `HitboxTests` after §5.2 — same assertions, only coordinates re-derived |
| accessibility | `AccessibilityTreeTests`, `AccessibilityDefaultsTests`, `AXNodeTests`, `AXEmitSiteTests` |
| animation | `AnimationTests` (one pin to `.legacy`, §5.4) |
| the modal scrim (hoist, clip and scroll escape, click-to-dismiss, the wheel not scrolling the list — `AP-I`, `IN-W`) and `Deferred`'s environment / opacity (`OM-AA`) | `PresentationWindowTests`, `DeferredTests`, `AbsoluteOverlayTests` at the new default; the demo's `modal-*` images differ only by cause C (§9) |
| `List` windowing and state retention, `AXTable`, every parameterised scenario still run under both authorities | `ListTests`, `ListLoweringTests`, `TombstoneTests`, the roll call (`AuthorityCoverage.expected` 82 → 87 with lane 1's five) |
| 0 `warning:` on both build systems | lane 3's gate |
| tests pinned `.legacy` keep their answers | the 6a pins and §5.3/§5.4/§5.5's, unchanged assertions |
| the 97 goldens | `git diff --name-only aef88ce HEAD -- 'Tests/**/*.json'` empty |

### 6.2 What moves

Production layout (every legacy root now lowers; a hugging root is centred —
`CN-J`); the demo's pixels (§9); `hidden()` under the proposal authority keeps
its space; `maxDepth` 88 → 72; the parameterised roll call 82 → 87.

## 7. Lanes

At most three, **sequential** (agents run one at a time in this worktree),
each ending with a full unfiltered suite green at the default it inherits and
`git status --short` clean. Opus for all three (each carries mutations);
the Record phase is one Sonnet agent.

### Lane 1 — `hidden()` under the proposal authority (`LR-DH`)

Sources: `LegacyLowering.swift`, `Frame.swift` (hidden half only),
`ElementGroup.swift`, `ModifiedElement.swift`, `AnyElement.swift`. Tests:
`HiddenLoweringTests.swift` (new: 1.1–1.6, §8), the five AV tests parameterised
(§5.1), `ZZAuthorityRollCall.swift`'s expected count. Every existing test that
asserts `display.none` is **reported** under `.proposal` (e.g.
`aHiddenFrameLayerIsReportedAsDisplayNone`, the `display.none` rows of
`everyContainerFieldEitherLowersAndAgreesOrIsReportedByName`,
`everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`,
`aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`) is
rewritten to assert the lowering — the lane lists each by name with its
red-before (the first run after the lowering). `LR-AV`'s inert-table row
("layout filters it, paint does not") stays for the legacy path.
Mutations: M1a (§5.1), and 1.1–1.6's own.

**Also lane 1 since critic round 1 (`LR-DO`):** (a) the root fold — in
`reportUnconsumedLoweredItems`' root arm (`LoweringState.swift`) and the root's
lowering, a px/rem `minSize`/`maxSize` on a declared root axis folds into the
declared size and stops reporting; tests 1.7 and 1.8 (§8); mutation **M1h**
(the fold removed: 1.7 red, and `MeasurePerformanceTests`' font-resolver test
aborts — taken as an exit-test arm, recorded which). (b) Depth, all of §10
except 3.3: `maxDepth = 72`, the doc table, the eight boundary tests,
`LayoutTree.lastNativeLayoutDeepestLevel`, M3e/M3f. (c) If lane 1's
`Frame.swift` edits stop `docs/probes/stage-6b-flip-instrument.patch` applying,
regenerate and commit it.

### Lane 2 — every red test made independent of the default (`LR-DG`, `LR-DI`)

Tests only; no `Sources/` line. §5.2–§5.5. The lane's two readings: the suite
at `.legacy` (the inherited default) green, and the suite **with
`docs/probes/stage-6b-flip-instrument.patch` applied** reading red **exactly**
the 14 X tests and the 2 D tests and printing no `SIXB-WOULD-TRAP` outside the X
tests (then the patch reverted, `git status --short` clean). Mutations M2a–M2e.
**Since critic round 1:** the animation map and test 2.1 (§0 item 2) come
**before** the `AnimationTests` pin; §5.5 follows §0 item 1.

### Lane 3 — the switch (`LR-DF`, `LR-DJ`, `LR-DK`, `LR-DL`)

Order: (1) the flip — `Frame.defaultLayoutAuthority`, `Window`, and the
thirteen helper defaults (`makeFakeWindow` to `LayoutAuthority? = nil`, the
twelve file-local ones to `Frame.defaultLayoutAuthority`) — red exactly the two
D tests, recorded; a flip of `Sources/` alone would leave every
`makeFakeWindow` window on `.legacy` and read almost nothing; (2) D rewritten; (3) exit test 3.1 red-first against a counter that
is not yet bumped, then the counter; (4) 3.2 (`CN-J` through a `Window`);
(5) the demo re-spelling and `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
re-derived (its part 2b loses cause X9 for the rows: the inner `Box` is 28 tall
on both sides, the `Text` 6 pt down on both; red-before: the demo change alone,
assertions named), plus any other `demoContent()` reader it reddens
(`LoweringItemTests`' paragraph copy, `PresentationWindowTests`) named;
(6) depth — **moved to lane 1 by `LR-DO`**; lane 3 only takes 3.3 and
re-measures the demo's deepest level after the re-spelling; (7) the
twelve-image comparison **plus the two 920×560 production-size images**
(`LR-DO`) and the region accounting (§9); (8) the gate: 0 `warning:` on both build systems after `swift package
clean`; (9) `METALUI_RUN_100K_LIST_TEST=1 swift test --filter
aListsWorkIsTheSameFor100kRowsAsFor500` once, under the new default, both
authorities' times recorded; (10) the lock probe, and the real-window capture
if and only if it reads unlocked (`LR-DM`).

## 8. The exit test and the new tests

| # | test | file | red-before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aHiddenChildKeepsItsSpaceUnderTheProposalAuthority` — `Column(gap: 0) { a 20×20; b 20×20 .hidden(); c 20×20 }` in a `DifferentialRoot`: lowered `c.y == 40` (H1: `VStack(spacing:0){a20; b20.hidden(); c20}` is 20×60), legacy `c.y == 20` (CSS) — both arms, both asserted | `HiddenLoweringTests` | reports `box.display.none` | **M1b** `hidden()` lowered as a 0×0 leaf |
| 1.2 | `aHiddenElementPaintsNothingUnderTheProposalAuthority` — a hidden red `Box` over a white window: the scene carries no rect of its colour; the shown control does (V0/V1) | ″ | trap | **M1c** the paint skip removed |
| 1.3 | `aHiddenClickTargetPassesTheClickToWhatIsUnderIt` — `Stack { under.onClick; top.onClick.hidden() }`: a click reaches `under` (V3; control V2 — unhidden, `top` wins) | ″ | trap | **M1d** the hitbox scope removed |
| 1.4 | `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer` — the chain shape of `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` (an inner `ModifiedElement` layer hidden, an outer layer decorated and clickable, `MC-C`'s layer order): the outer layer paints and takes its click, the hidden layer and everything inside it paint nothing and take none | ″ | trap | **M1e** `ModifiedElement`'s per-layer mirror removed |
| 1.5 | `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority` — paint, hit and AX, through `AnyElement` | ″ | trap | **M1f** `AnyElement`'s entry gates removed |
| 1.6 | `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore` — under `.legacy`, the scene and hitbox list of a tree with a hidden, clickable, decorated child are **identical to `aef88ce`'s** (the lane records what the legacy path emits for it first — measured, not assumed) and `hiddenNodes` is empty | ″ | green on arrival (a pin) | **M1g** the paint skip reading `display == .none` |
| 1.7 | `aRootsMinimumAndMaximumFoldIntoItsDeclaredSize` (`LR-DO`) — roots `Box{…}.height(370).minHeight(0)`, `.height(370).minHeight(500)`, `.height(370).maxHeight(300)`, each in a production-shaped frame at both authorities: the root's height is 370 / 500 / 300 on both, and the proposal report is empty; the second and third arms disagree with the declared height alone (the separating arms) | `RootFieldLoweringTests` (new, lane 1) | reports `box.minSize.unconsumed` / `maxSize.unconsumed` | **M1h** the fold removed |
| 1.8 | `aRootFieldWithNoLoweringTrapsInAProductionWindow` (`LR-DO`) — exit tests through a `.proposal` `makeFakeWindow` (explicit, since lane 1 runs before the flip): a root `minHeight` on an **auto** axis, a root margin, a root percent `maxWidth`; each process exits naming `box.<field>.unconsumed` | ″ | green on arrival (the trap exists today) → its red is the arm where the field is removed, which must not exit | the trap made non-fatal (instrument) — all three arms red |
| 2.1 | `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority` (`LR-DO`, lane 2) — only the site arms lane 2's map finds unpinned under `.proposal`; each drives `withAnimation(.linear(duration: 1))` and reads the lowered rect at t = 0 and 0.5 | `AnimationTests` | the arm's site with `animated(` dropped on its proposal path | one per new arm |
| 3.1 | **`noProductionFrameReachesTheLegacyEngine`** — `demoContent()` (modal off, modal on, animation on) and `nativeLayoutPreviewContent()` imported from `MetalUIDemoContent`, and a `ScrollView { List(…) }` root, each through `makeFakeWindow` at the default authority, several frames each, inside `Frame.$legacyRootLayoutCounter.withValue(c)`: `c.count == 0`; positive control in the same test: the same demo through a `.legacy` window bumps it (`> 0`, and exactly one per frame drawn) | `RootSwitchTests` | red-first: before the counter is bumped, the positive control reads 0 | **M3a** `Frame.defaultLayoutAuthority` back to `.legacy`; **M3b** the counter bump removed (the control reddens) |
| 3.2 | `aHuggingLegacyRootIsCentredInAProductionWindow` — `Row { Box().width(58).height(20) }` in a 100×100 window: the box at (21, 40) 58×20 (R1, re-run today); the same through a `.legacy` window at (0, 40) (`CS-I`: the row fills the window and centres its cross axis) | `RootSwitchTests` | green on arrival after the flip → its red is taken as M2a/M2b, and its `.legacy` arm checked green at `aef88ce` first | **M2a** (top-leading), **M2b** (window rect) |
| 3.3 | `everyProductionRootsDeepestNativeLevelIsMeasured` — `LayoutTree.lastNativeLayoutDeepestLevel` through a `Window`: demo (all three states) **the lane's measured value** (29 at design, before the re-spelling; re-measured after it), preview 10, `List` root 15; each `< NativeLayoutRun.maxDepth` asserted too | `RootSwitchTests` | the property does not exist | **M3c** the property not recorded (reads 0); **M3d** a lowering that adds one level to every lowered `Box` (the demo value moves) |

Rewritten, not new: 1.1/1.2 of `LayoutAuthorityTests` (§5.6), the eight depth
tests (§10), `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`.
Suite count: 1688 + 6 (lane 1) + 3 (lane 3) = **1697** at design; **1700** after critic round 1 (§0: +1.7, +1.8, +2.1); guards 78, goldens 97.

## 9. Demo, pixels and captures

**The comparison is `docs/probes/demo-pixels/compare.sh <scratch> aef88ce
<lane-3 HEAD>`** (the harness now captures at the default authority; at
`aef88ce` it reads exactly what its predecessor read — 0 in all twelve, scenes
identical, measured). Controls at their recorded values. **Expected, and each
region to be accounted for from the `.scene` dumps** (record §41 §4, measured
at arm H, which is arm G plus the re-spelling):

| image | expected | every rect / glyph delta, and its cause |
|---|---|---|
| `preview-*`, `chrome-*` (4) | **0, scene identical** | the preview was native already; the chrome pair names its authority |
| `default-*` (4) | ≈168 380 differing, bbox (92,113)–(987,1007) | **55**: sidebar and its four bars +100 wide (5 rects), main pane x +100 w −100 (1), 507 main-pane rects x +100 (the cluster, counter, scroller and 500 rows); glyphs x +100 (15 509); **55's re-wrap**: the paragraph's line breaks move (glyphs x +194/+294/+295, and −548/−652 with y +16); **55's rounding**: "Count 0" x +101 (six glyphs) |
| `modal-*` (2) | ≈172 126 | the above plus **C**: the card y −8 h +16 and its 86 glyphs y −8 |
| `animation-*` (2) | ≈341 608 | **55** at the animated 320 (CSS shrank it to 139): +181 on the same rects; the paragraph one line taller, so the scroller and its 500 rows y +16 and the scroller h −16 |
| `prod-default-light`, `prod-modal-light` (2, `LR-DO`) | **not predicted** — first taken by lane 3 at both commits | each region attributed to 55, its re-wrap, C or the rounding at 920 wide and 560 tall; a region none of them explains (a vertical compression the 1024² square cannot show) is a finding, probed before it is kept |

Any delta outside these rows is a finding. **Before the re-spelling** (arm G)
the same comparison also carried the 15 392 row-label glyphs at y −6 — X9 —
and that row must be absent at lane 3's HEAD (the re-spelling's own
measurement: `aef88ce` → arm H0, the re-spelling alone under `.legacy`, 0 in
all twelve, scenes identical).

Probe backing, every arm re-run today with its output found verbatim in its
recorded header: **55** → `swiftui-engine-replacement-stage2.swift` F5 (a
declared 196 beside a greedy text is served its 196) and
`swiftui-stack-algorithms.swift` G9/G4r (a fixed child is not shrunk below its
size); **C** → `swiftui-engine-replacement-stage1.swift` T3/T4 (a `Text`
answers at the width it is proposed), the mechanism that measures the modal's
paragraph at the card's 320; **X9** → `swiftui-engine-replacement-stage2.swift`
X9 (an outer greedy-height frame around a fixed child places the child at its
own height, centred — `LR-AC`), which is why the row needed its height
declared; **root placement** → the R control and R1–R4 (the demo root is
greedy, answers the window and sits at (0, 0), so `CN-J` does not move it).

**Captures.** The lock probe at design: locked, display asleep. Lane 3 runs it
again; unlocked → `docs/probes/window-capture/capture.sh <scratch> aef88ce
<HEAD>` and each differing region named as above; locked → the capture is
recorded as **owed to the human**.

## 10. Depth

**Lane 1 since `LR-DO`** (3.3 stays in lane 3). Re-bisected with `docs/probes/native-depth-ceiling/bisect.sh` at `aef88ce`
(1 MB thread; positive control `padding 10` completes and `padding 2000000`
dies in both configurations):

| kind | debug last / first-dies | release last / first-dies |
|---|---|---|
| padding | 194 / 195 | 1256 / 1257 |
| fixed frame | 194 / 195 | 1256 / 1257 |
| flexible frame (0…∞ both axes) | 194 / 195 | 1256 / 1257 |
| one-child vertical stack | **127 / 128** | **653 / 654** |
| one-child horizontal stack | 127 / 128 | 653 / 654 |
| overlay (`ZStack`) | 169 / 170 | 1256 / 1257 |
| custom `ProposalLayout` (measures and places its child) | 178 / 179 | 1037 / 1038 |
| scroll viewport | 194 / 195 | 1256 / 1257 |
| two-cell grid row (placement path) | 155 / 156 | 1256 / 1257 |

`SA-L`'s rule on the debug row gives **72** (`LR-DK`). Lane 3 sets it, rewrites
the table in `NativeLayoutRun.maxDepth`'s doc comment, and re-derives the eight
literal boundary tests: `aChainOf88GridsTraps`/`aChainOf87GridsDoesNotTrap`
(→ 72 / 71, renamed), `aLoweredChainAtTheNativeDepthLimitLaysOut` /
`…OnePastTheNativeDepthLimitTraps` (29/30 boxes → **24 / 25**, 72 / 75 levels),
the two `itemChain` tests of `LoweringPipelineParityTests` (2.14) and the two
`marginItemChain` tests of `LoweringBoxModelTests` (4.8), each re-derived by
hand before the run with its node count, and every message literal
`exceeded 88 levels` → `72`. `NativeDepthGuardTests`' arithmetic tests follow
`maxDepth` by themselves. Red-before: the constant alone reddens exactly the
eight literal tests (recorded). Mutation **M3e**: `maxDepth` back to 88 — the
eight red again; **M3f**: 71 — the at-limit arms red.

## 11. Handed on, each with an owner

| item | owner |
|---|---|
| divergence 4 (`CS-I`) as a legacy-authority row, and the §5.3/§5.4 pins | 7b |
| ~~`AnimationTests.everyRegisteringSiteAnimatesItsStyle`'s proposal twin~~ — closed in 6b by `LR-DO` (lane 2's map and 2.1); the legacy pin itself retires with 7b | 7b (the pin only) |
| a root's `minSize`/`maxSize` on an **auto** axis, a root percentage, a root `margin` and a root `.absolute` still trap in production — each pinned by 1.8 (`LR-DO`); the declared-axis fold is done here | 8 (the recipe), 9 |
| the N9 pins, the tokenizer pins, the legacy authority | 9 |
| the real-window capture, if locked at close | the human |
| CLAUDE.md, AGENTS.md, records §03/§04/§05/README, the plan's 6b row, the parent spec's status; §03's re-opened rows (`LR-DM`) | the Record phase |
