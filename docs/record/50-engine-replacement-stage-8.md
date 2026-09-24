# §50 — Engine replacement, stage 8: the sizing vocabulary

Plan task 7, stage 8 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 8,
§8; `FR-F`, `FR-G`, `FR-H`, `FR-I`). Design:
`docs/superpowers/specs/2026-09-24-engine-stage-8-design.md`. Rulings
`LR-ER`…`LR-EX` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-8` from `85217e3`, worktree
`/Users/maxburger/Developer/worktrees/MetalUI/stage-8`. Probe:
`docs/probes/swiftui-engine-stage-8.swift` (groups F, P, T; output in its
header). Instruments: `docs/probes/stage-8-deprecation-sites.txt` (the
compiler's census), `docs/probes/stage-8-demo-recipe.patch` (the demo
conversion, measured at 0 px), `docs/probes/stage-8-sizing-converter.py` (the
recipe's two mechanical rules).

**Numbering hazard.** Written as §50, the next free number at `85217e3`
(§49 is stage 7b). If another line reaches `master` first with a §50, this file
is renumbered at merge by the precedent of record §23 §8 and the
§25/§27/§29/§38/§41/§48 headers.

**Status, 2026-09-24 (PDT): design.** §1–§5 were written with no file under
`Sources/`, `Tests/` or `Package.swift` changed in a commit. Every prototype
below was applied to the working tree, built, run, captured (as a patch in
the session scratchpad or under `docs/probes/`) and reverted; `git status
--short` showed only this design's `docs/` files afterwards. The lanes append
§7 onward.

## 1. Baseline at `85217e3`

`swift build --build-system native --build-tests` → `Build complete!`, 0
`error:`, the one `warning:` SwiftPM's deprecation notice; unfiltered `swift
test --build-system native --no-parallel` → **`Test run with 1445 tests in 3
suites passed after 87.328 seconds`**, the log carrying `FR-J no-argument
frame: succeeded=true deprecations=2` (the guards ran). 0 goldens, 78 guards.

## 2. The entry measurement: the deprecation's warning count

`@available(*, deprecated, message: "SCRATCH8")` on the eight
`StyledElement` sizing modifiers and `width(fraction:)`/`height(fraction:)`
(`Sources/MetalUI/Box.swift`), one scratch build, reverted. **1692 distinct
`file:line:col` warnings** — the committed census,
`docs/probes/stage-8-deprecation-sites.txt`:

| where | `width` | `height` | `minWidth` | `minHeight` | `maxWidth` | `maxHeight` | `fraction:` | total |
|---|---|---|---|---|---|---|---|---|
| `Sources/MetalUIDemoContent` | 10 | 14 | 0 | 1 | 0 | 0 | 0 | **25** |
| `Tests/MetalUITests` (55 files) | 822 | 800 | 19 | 11 | 7 | 6 | 2 | **1667** |
| every other target and package | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

The parent row's figures (demo 10/13/1, tests 557/519/13) are from
2026-09-17; the demo's extra `height` is stage 6b's list-row height (`LR-DJ`).
**No other `Sources/` target calls them** (the one internal caller,
`width(percent:)` → `width(fraction:)`, is inside a deprecated declaration and
does not warn). `Backends/SDL`, `Tests/PortableTests`,
`Tests/MetalUICrossPlatformTests`, `MetalUILayoutTests` and `MetalUICoreTests`:
0 — grep and the compiler agree. `Component.width`/`height` and
`StyledComponent.width`/`height` were **not** deprecated in the scratch build
(`LR-ER` item 2), so their callers are not in the census.

Per file (`Tests/MetalUITests/`): OuterModifierMatrixTests 194,
LoweringItemTests 142, DecorationPaintTests 112, DisabledTests 111,
AccessibilityTreeTests 94, InputDispatchTests 68, AccessibilityDefaultsTests 67,
LoweringComponentTests 62, PresentationLoweringTests 56, ElementLayoutTests 54,
HitRegionTests 52, FocusTests 48, AXEmitSiteTests 46, HiddenLoweringTests 42,
FrameDecorationInteractionTests 42, LoweringScrollTests 36,
RootFieldLoweringTests 26, AnimationTests 26, PresentationWindowTests 24,
LoweringBoxModelTests 23, LoweringPipelineParityTests 21, KeymapTests 20,
ComponentTests 20, LoweringCorpusTests 19, LoweringStackAndLayerTests 18,
LoweringContainerTests 18, LayoutAuthorityTests 18, ObservationTests 17,
TrackInteractionTests 16, PointerStatePaintTests 16, BackgroundChainTests 14,
FrameSizingTests 13, LoweringLeafTests 12, EnvironmentTests 12, ThemeTests 11,
ScrollViewTests 10, ModifierTests 8, LoweringDistributionTests 8,
GlyphEmitterTests 8, ElementGroupTrapTests 8, AccessibilityEndToEndTests 8,
GridLoweringInteractionTests 6, ModifiedElementTests 5, MeasurePerformanceTests
5, ListLoweringTests 5, RootSwitchTests 4, ModifierCompositionProofTests 4,
ListTests 4, HitboxTests 4, StateTests 2, ProposalNodeIDTests 2, FrameLoopTests
2, DeferredTests 2, TextSystemSeamTests 1, TextMeasureTests 1.

**Typecheck-guard fixtures** (strings compiled by `swiftc -typecheck`, not in
the census): only `ContainerCompileGuards`' G4
(`thePercentSizingModifiersAreDeprecatedRenamesOfFraction`), whose control arm
asserts `width(fraction:)`/`height(fraction:)` draw **0** deprecations — it
moves with `LR-EU` (a T row, spec §6).

**`Style()` writes in tests** (the parent row's "651 `Style()` uses" at
2026-09-17): **232 lines in 50 files** today — `MetalUITests` 211 (largest:
ScrollRoutingTests 35, LayoutAuthorityTests 18, AnimationTests 18,
ScrollIndicatorTests 11, ListTests 11, LoweringContainerTests 8, AXNodeTests
7), `MetalUILayoutTests` 39 (LayoutTreeTests 23, NativeBoundaryTrapTests 7,
StyleTests 4, NativeGridTrapTests 3, NativeInvalidationContractTests 2). Field
writes following them (one grep over `<var>.<field> =`): `size.width` 123,
`size.height` 99, `size` 84, `flexGrow` 37, `flexDirection` 34, `alignItems`
24, `padding` 20, `flexShrink` 14, `display` 12, `gap` 11, `border` 9,
`justifyItems` 8, `inset` 7, `justifyContent` 6, `position` 5, `minSize` 5,
`flexBasis` 5, `margin` 4, the rest ≤ 3. Disposed by `LR-ER` item 6.

## 3. What the conversion does under the proposal authority (scratch S, A, O)

A scratch `@Test` (`Tests/MetalUITests/ZZScratch8.swift`, never committed)
rendered each pair through a `Frame` at `.proposal` with diagnostics on and
compared the finalized scene's rects and glyphs, the hitboxes, the node count
and the report. **SAME** means every rect, glyph and hitbox identical, in order.

| arm | old spelling | new spelling | result |
|---|---|---|---|
| S1 | `Column { Box().width(40).height(40).background.cornerRadius }` | `Box().frame(width: 40, height: 40).background.cornerRadius` | **SAME**, 3 nodes both |
| S2 | `Box(decoration:) { Text }.width(36).height(36).alignItems(.center).justifyContent(.center).hoverBackground.onClick` | `Box { Text }.frame(width: 36, height: 36).background.cornerRadius.hoverBackground.onClick` | **SAME**, 4 nodes both |
| S3a | `Row(gap: 12) { 40×40; Box().height(12).flexGrow(1).background }` | `Box().frame(height: 12).frame(maxWidth: .infinity).background` | **SAME**, 6 nodes both |
| S3b | same | `Box().flexGrow(1).frame(height: 12).background` | DIFF — the grow is on the inner element, consumed and dropped by the frame (a stack parent, `LR-AZ`); 5 nodes |
| S3c | same | `Box().frame(height: 12).flexGrow(1).background` | DIFF — reports `modifierLayer.style` (a production trap) |
| S4 | stretched `Column { Box().height(1).background; … }` | `Box().frame(height: 1).background` | **SAME** — the frame layer is stretched on its `nil` axis (`MC-Q` finding 7) and the background rides it |
| S5 | sidebar: `Column{…}.alignItems(.stretch).flexGrow(1).padding(14).width(196).background` in a stretched `Row` | `….padding(14).frame(width: 196).background` | DIFF — the frame layer is stretched to 300, but its child (the padding layer) is not stretched inside a frame and is centred: the column's text moves from y 16 to y 131. `alignment: .top` restores it (the demo prototype, §4) |
| S6 | header: `Row{…}.alignItems(.center).flexGrow(1).padding(16).height(72).background` | `….padding(16).frame(height: 72).background` | **SAME** |
| S7a | scroller box: `Box { 50×400 }.width(120).flexGrow(1).flexBasis(0).minHeight(0)` under an 80pt header, 300pt host | `.frame(width: 120).frame(minHeight: 0, maxHeight: .infinity)` | height right (220), but the outer greedy frame is stretched to 400 wide and the content centred: the fixed frame must be OUTER and the greedy one aligned `.topLeading` |
| S7b | same | `.frame(width: 120).frame(maxHeight: .infinity)` (no minimum) | the greedy frame answers the content's 400: header pushed to y −90 — the "automatic minimum" analogue (probe F0) |
| S7c | same | `.frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading).frame(width: 120)` (fixed frame outer) | the box right — 120×220 at (0, 80), as the old spelling — but the content at x **35** where the old spelling put it at 0: the default-aligned outer frame centres the hugging greedy frame. Hence R5's "both aligned" (spec §5.1): the outer frame takes `.leading` |
| S7d | same, **no** minimum, fixed frame outer | as S7c without `minHeight:` | header at y −90, box 120×400 at y −10: S7b's answer with the order corrected |
| S8 | `Column { Text("hi").width(100) }` | `Text("hi").frame(width: 100, alignment: .leading)` | **SAME** |

**Node counts are equal wherever the answers are** (S1, S2, S3a, S4, S6, S8):
under the proposal authority an element's own declared size already lowers to
a native frame node (`paddedAndSized`), so a `.frame` layer replaces that node
rather than adding one. The **identity** level is still added — a frame layer is
a `ModifiedElement` layer with its own `GlobalElementID` (spec §5, R7).

**Absolute boxes** (`Box { Deferred { … } }.alignItems(.flexStart)`, 200×200,
both authorities):

| arm | spelling | legacy | proposal (at `85217e3`) |
|---|---|---|---|
| A0 | `Box().width(20).height(20).background.onClick.position(.absolute).inset(top 10, left 30)` | 30,10 20×20, hitbox same | same |
| A1 | `Box().frame(width: 20, height: 20).background.onClick.position(.absolute).inset(…)` | 30,10 20×20 | **0×0 and `modifierLayer.style`** — a production trap |
| A2 | the size on a child: `Box { Box().frame(20×20).background.onClick }.position(.absolute).inset(…)` | 30,10 20×20 | 30,10 20×20 |
| A3 | `Box { Text("hi") }.minWidth(100).background.position(.absolute).inset(…)` | 11×16 (ignored, `AP-E`) | 11×16 and `box.minSize.absolute` |

**Prototype of `LR-EV`** (two conditions in `Sources/MetalUI/LegacyLowering.swift`:
the frame layer's `style` comparison takes `position`/`inset` from the declared
style when it is absolute; `lowerPresentation`'s `…absolute` check skips a
`.frameLayer` record, whose bounds are its own kernel frame's):

| arm | spelling | legacy | proposal |
|---|---|---|---|
| A1 | as above | 30,10 20×20 | **30,10 20×20, no report** — agrees |
| A4 | `Box { Text("hi") }.frame(minWidth: 100).background.position(.absolute).inset(…)` | 11×16 | **100×16** (probe P1: 100) |
| A5 | `… .frame(maxWidth: 80) …` | 11×16 | **80×16** (probe P2: 80) |
| A6 | `Box().frame(height: 40)…inset(top 10, right 20, left 30)` (stretched) | 150×40 | 150×40 |
| A7 | `Box().height(40)…` (the same, old spelling) | 150×40 | 150×40 |

With the prototype applied, the unfiltered suite (plus the scratch test) read
**`Test run with 1446 tests in 3 suites passed`** — no existing test pins that
a `.position` after `.frame` reports `style`, so the exemption is unpinned
until the stage's own test (spec N1.4). **The prototype has a hole** the lane
closes: `planLegacyItems` skips the outside-a-`Deferred` `position`/`inset`
report for a `.frameLayer` record (its comment: "a `.position` written after
`.frame` is its own `style` report"), so with the exemption alone a framed
absolute box outside a `Deferred` would lower silently in flow.

**FR-G's live caller is inert in production** (O1, O2). At `85217e3`, deleting
the demo's `.minHeight(Pixels(0))` — and, separately, both it and
`.flexBasis(Pixels(0))` — leaves `theDemoFrameMatchesTheValuesRecordedOnMacOS`
green: under the proposal authority the scroller box holds a lowered
`ScrollView`, whose viewport **fills its proposal on the scrolling axis**
(`LR-BB`), so the box's content never floors it. The minimum mattered to the
legacy engine (the demo's comment: "14000pt") and to nothing production runs
since stage 6b. S7a/S7b show it still matters to a greedy frame over content
that does not fill (probe F).

## 4. The demo prototype

`docs/probes/stage-8-demo-recipe.patch` (29 insertions, 41 deletions in
`DemoContent.swift`; comments untouched) converts all 25 sites by the recipe.
Built, `theDemoFrameMatchesTheValuesRecordedOnMacOS` and
`theDemoFrameDrawsRectsAndText` green unedited; then, from `git stash create`
(`c6997e2`), `docs/probes/demo-pixels/compare.sh <scratch> 85217e3 c6997e2`:

    controls at 85217e3 (85217e3) — every one must be non-zero except the two marked 0:
      light vs dark, f0 [1048576]        differing=1048576 bbox=(0,0)-(1023,1023)
      default vs modal, light [1030498]  differing=1031003 bbox=(0,0)-(1023,1023)
      default vs animation, light [210027] differing=454895 bbox=(16,113)-(987,1007)
      f0 vs f3, light [0]                differing=0
      preview light vs dark [1048576]    differing=1048576 bbox=(0,0)-(1023,1023)
      chrome legacy vs proposal [0]      differing=0
      distinct, default-light-f0 [544]   distinct=544 pixels=1048576
      distinct, chrome-legacy [216]      distinct=216 pixels=313600
      prod default vs modal [not 0]      differing=491221 bbox=(0,0)-(919,559)
      distinct, prod-default-light       distinct=529 pixels=515200
      indicator rects in all twelve [0]  0

    85217e3 (85217e3) -> c6997e258422f224c1f0ae52e305ab035e499f27 (c6997e2):
      default-light-f0 … prod-modal-light   differing=0   scene identical   (all fourteen)

The two controls whose bracketed figure differs (1031003, 454895) are the
post-6b values record §48 already corrected (`LR-DZ`); the rest match.

**What the demo can and cannot see** — six mutations of the prototype, each
built and run against `theDemoFrameMatchesTheValuesRecordedOnMacOS` (the
scene byte-for-byte at two scales):

| mutation | result |
|---|---|
| Ma: the sidebar's `alignment: .top` dropped | **red** (2 issues) |
| Md: the list row's `alignment: .leading` dropped | **red** |
| Me: the bar's `.frame(maxWidth: .infinity)` replaced by `.flexGrow(1)` before the frame | **red** |
| Mf: the button's `.background`/`.cornerRadius` moved before its frame | **red** |
| Mb: the scroller box's `minHeight: 0` dropped | green — O1's inertness |
| Mc: the scroller box's `.topLeading` dropped | green — the viewport fills the frame |

Mb and Mc are why spec N1.6 exists: the demo cannot pin the zero minimum.

## 5. The converter's viability (F class)

`docs/probes/stage-8-sizing-converter.py` on `DisabledTests` and
`FocusTests` (80 frames), built and run filtered (a diagnostic, not a verdict):
**R1 alone** — 20 issues in 37 tests, every one a sized container whose
hugging content moved to the frame's centre; **R1 + R3** — **1 issue**,
`aDisabledScrollViewStillScrollsOnTheWheel`, which locates its scroller's
`ScrollState` through a literal structural path (`root/0/0/"list"`) that the
new frame layers deepen (spec R7). The same run on `AccessibilityTreeTests`,
`DecorationPaintTests` and `HitRegionTests` did not build: helpers returning
`Box<…>` (`FR-F`'s "type-level cost", 224 errors, most cascading from a few
helpers). Reverted.

**And why `DisabledTests` is NOT converted anyway** (spec §5, class K2): its
`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` enumerates sites —
`Box`, `Row`, `Column`, `Stack`, `Text` — each carrying `.width(40).height(40)
.onClick`. Converted, every arm's `onClick` lands on a `ModifiedElement` layer
(R2), so the test would pass while no longer exercising `Box`'s, `Text`'s or
`Stack`'s own `registerHandlers` — the "copy of a pinned implementation is
unpinned" hazard, arriving silently. The converter's green run is exactly that
trap.

## 6. Probe

`docs/probes/swiftui-engine-stage-8.swift`, run twice under `/usr/bin/swift`
(Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0 (26A428): exit 0,
byte-identical, 10 lines, recorded in its header. F0/F1 (a greedy frame
answers its content's 400 without a minimum, 120 with `minHeight: 0`), P0–P2
(11 → 100 with `minWidth: 100`, → 80 with `maxWidth: 80`, proposed 170), T0/T1
(a `.frame(width: 100)` centres its text at x 94.5; `.leading` puts it at 50).
Each group's control differs from its arm.
