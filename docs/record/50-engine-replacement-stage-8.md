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
--short` showed only this design's `docs/` files afterwards. §7 is the design
critic round; the lanes append §8 onward.

## 1. Baseline at `85217e3`

`swift build --build-system native --build-tests` → `Build complete!`, 0
`error:`, the one `warning:` SwiftPM's deprecation notice; unfiltered `swift
test --build-system native --no-parallel` → **`Test run with 1445 tests in 3
suites passed after 87.328 seconds`**, the log carrying `FR-J no-argument
frame: succeeded=true deprecations=2` (the guards ran). 0 goldens, 78 guards.

## 2. The entry measurement: the deprecation's warning count

`@available(*, deprecated, message: "SCRATCH8")` on the eight
`StyledElement` sizing modifiers — the six sizes and clamps and
`width(fraction:)`/`height(fraction:)` (this sentence first read as if the six
were eight, and the spec and rulings then said "ten"; `LR-EY` item 1)
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

## 7. Design critic round 1 (`LR-EY`)

**Probe re-run.** `/usr/bin/swift docs/probes/swiftui-engine-stage-8.swift`,
twice, macOS 27.0, Apple Swift 6.4: exit 0, both runs byte-identical to each
other and to the 10 lines recorded in the probe's header (`diff` empty) — F0/F1,
P0–P2, T0/T1 with their controls.

**The demo's hit testing, accessibility and hover.** The fourteen-image
comparison cannot see them. `docs/probes/stage-8-demo-hit-ax-hover.swift`,
copied into `Tests/MetalUITests` as a scratch test, run filtered at `85217e3`
and at `85217e3` + `docs/probes/stage-8-demo-recipe.patch`, then deleted
(`git status --short` clean afterwards):

| what | modal off | modal on |
|---|---|---|
| hitboxes (bounds, layer, opacity, order) | 3, identical | 5, identical |
| accessibility tree, ids excluded | 9 nodes, identical | identical (adds "Close modal" and the card) |
| scene hovered at (270, 299), (470, 299), (370, 299), (400, 280), (300, 480) | identical | identical |

Whole output 91 882 241 bytes each side, `diff` empty. The instrument separates:
hovered over the minus button vs over the readout (no hitbox) the scenes differ
(md5 `c37a1f61…` vs `9b3db702…`), and `hovered` reads true at the two buttons
and the list row, false at the readout and the stack cluster, with the modal
off. R7's extra identity level is invisible to all three, as argued.

**Findings** (applied or rejected in `LR-EY`): "ten" modifiers were eight
(N1.1/N3.1/M3a literals would have been wrong); divergence 52's new owner
(stage 10) exits at 0 px too; `LR-EV` was unruled over a multi-member frame;
`Component.swift`'s promised comments had no lane; R4 contradicted the demo
patch; hit testing/accessibility/hover were argued, now measured; `Backends/SDL`
was never built with the deprecation in; four more CLAUDE.md/README copies
recommend a deprecated spelling. The accounting is unchanged: 1445 − 0 + 7 =
1452, guards 78 → 79.


## 8. Lane 1 — the absolute arm, the helpers, the demo (`LR-EV`, `LR-EZ`)

Commits: `9296f67` (red first: N1.1–N1.6, `CSSSizing.swift`, the demo recipe,
the four files by class), `29c7200` (`LR-EV` in `LegacyLowering.swift`;
`owningStage` for `…absolute` 8 → 10; the demo's structural literals
re-derived), then this record and `LR-EZ`.

**8.1 What changed.** `Tests/MetalUITests/CSSSizing.swift` (new): the eight
`css*` helpers, each one line with its public modifier's closure body, and the
class-D instrument (`DeprecatedSpelling`, a `@MainActor` protocol whose
conformers' witnesses carry `@available(*, deprecated, …)`, reached through
`oldSpelling(_:)`). `LegacyLowering.swift`: the frame layer's `style`
comparison takes `position`/`inset` from the declared style when it is
absolute **and the frame is over at most one node**; `lowerPresentation`'s
`…absolute` flags skip a `.frameLayer` record; `planLegacyItems`' outside-a-
`Deferred` `position`/`inset` report no longer skips a frame layer.
`LayoutAuthority.swift`: `…absolute` owned by stage 10 (`LR-EZ` item 3).
`DemoContent.swift`: the design's patch applied, the scroller box's outer
frame `.leading` (R5), and the comments that would have lied rewritten — the
`Square`/`Chrome` typealias, the header's modifier-order paragraph (size is
`.frame` after `.padding`; no item modifier after the frame), the sidebar's
animated width (R8, `alignment: .top`), the scroller box's automatic-minimum
paragraph (now marked as the legacy engine's history, followed by `LR-ET`'s
finding: two frames, `minHeight: 0` inert here and pinned by N1.6), the
`.minWidth(_:)` mention, and the list row's `.height`/`.alignItems(.center)`
mentions (the frame's `.center` does the centring).

**By class.** `PresentationLoweringTests` 56 sites and `AnimationTests` 26 → K
(`.x(` → `.cssX(` at the census positions, by script, no other change);
`PresentationWindowTests` 24 → F (R1, R6 on the absolute boxes, `.topLeading`
on 3.2's sized `Box` around a `Deferred`); `FrameSizingTests` 13 → F (the
three `Row` roots `.frame(…, alignment: .topLeading)` — they declare
`alignItems(.flexStart)`, so their content sat top-leading; the two `Column`
roots `.top`; the three scroller arms' own-box size a `.frame` on the same
axis). No F site fell back to K; no assertion in the four files changed except
the owning-stage one (§8.3).

**8.2 Red first** (unfiltered, `9296f67`): `Test run with 1451 tests in 3
suites failed … with 29 issues`. Designed reds — N1.2
(`PresentationLoweringTests.swift:580` `r.unlowerable.isEmpty`, and
disagreeing/scenes/hitboxes/accessibility; `:582` `loweredBounds[box] ==
expected`; `:588` the hitbox; `:591` `frame.unlowerableFields.isEmpty`), N1.3
(`:638` `minimum.0 == pBounds(30, 10, 100, 16) && minimum.1.isEmpty`; `:640`
the 80 arm), N1.4 (`:690` `inFlow == ["modifierLayer.position",
"modifierLayer.inset"]`), and `PresentationWindowTests` 3.2, 3.3, 3.5, 3.6 on
both authorities (their pre-flight's report: R6 needs `LR-EV`). N1.1 (its red
was the build), N1.5 and N1.6 green on arrival. **Undesigned reds** — the
demo's structural literals (`LR-EZ` items 1–2): `LoweringCorpusTests.swift:258`
`chrome.elements == 8` (11), `:571` `report.elements == 2035` (3053),
`LoweringPipelineParityTests.swift:119`/`:186` `elements == 9` (12),
`RootSwitchTests.swift:213` `deepest == expected` ×6 (29, expected 30).

**8.3 The re-derived census.** With the element count corrected, the
whole-demo census read 3031 agreeing / 22 disagreeing (modal: 3060 ids, 3033 /
27), where it read 6 / 2029 (modal 8 / 2033). Every disagreement, printed by a
scratch test (never committed) and attributed:

| cause | ids (legacy → lowered) |
|---|---|
| R + O | outer layer 920×14439 → 920×560; outer column 888×14407 → 888×528; body, sidebar frame, main layer ×14310 → ×431; main column 648×14278 → 648×399 |
| O | the header bar's outer frame (486, 46) 0×12 → (84, 46) 804×12; the scroller's outer frame, greedy frame, `Box` and `ScrollView` (240, 455) 420×14000 → 420×73 |
| 53f | header padding layer (418, 16) 84×72 → (16, 16) 888×72; its row (434, 32) 52×40 → (32, 32) 856×40; the avatar's frame (434, 32) → (32, 32) and `Box` (454, 52) → (52, 52); sidebar padding layer (79, 113) 70×188 → (16, 113) 196×188; its column (93, 127) 42×160 → (30, 127) 168×160; "Library" and the four bars' frames 42 → 168 wide at x 93 → 30 |
| C (modal) | the card's frame and padding layer (280, 235) 360×90 → (280, 227) 360×106; its column 320×50 → 320×66; the two texts 8 pt higher |

The test asserts each row by literal (legacy heights derived from the shaping
cache as before, plus the `List`'s 28 × 500), that the 22 (27) are the whole
of the report's disagreements, and the counts. The old part 2b (`rowCensus`,
the 42-of-500 sub-pixel bracket) went with the row disagreements;
`centredRounded` with the chrome's centred texts, which agree now.

**8.4 Mutations**, each committed-from, restored from a copy, full unfiltered
suite, `git status --short` empty after every restore:

| mutation | reddened |
|---|---|
| M1a — exemption off (`if false && …`) | `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities`, `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred`, `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes`, `aPresentationInsideAFadedSubtreeIsStillFadedUnderBothAuthorities`, `aPresentationKeepsItsDeclaringScopesEnvironmentUnderBothAuthorities`, `anAnimatedInsetInterpolatesItsValueUnderBothAuthorities`, `nestedPresentationsLandOnOneLayerUnderBothAuthorities` (19 issues) |
| M1b — `lowerPresentation` flags a frame layer's bounds | `aFramesOwnBoundsOnAnAbsoluteAutoAxisAnswerAsSwiftUIsFrameDoes` |
| M1c — comparison skipped entirely when absolute | `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred` |
| M1d — `.frameLayer` guard restored in `planLegacyItems` | `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred` |
| M1e — `bound(_:_:)` returns the declared value | `anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid`, `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries`, `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle`, `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` |
| M1f — `framed(_:)` passes `minHeight: nil` | `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`, `aFrameLayerLowersItsMinimaAndFiniteMaximaFromItsAnimatedStyle` |
| M1g — `cssMinHeight` writes `maxSize.height` | `theCSSSizingHelpersWriteWhatTheDeprecatedModifiersWrite` (only) |
| M1h — one-node condition dropped | `aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred` |
| M-EZa — a frame layer's infinite maximum passed as `nil` | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`, `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps`, `resizingTheWindowDirtiesItAndTheNextFrameLaysOutAtTheNewSize`, `aRealAppKitResizeDirtiesTheWindowAndTheNextFrameReflows` |
| M-EZb — `…absolute` owned by "8" again | `aPresentationWhoseContainingBlockIsNotTheWindowIsReportedByName` |
| Ma — sidebar `alignment: .top` dropped | `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| Md — list row `.leading` dropped | `theDemoFrameMatchesTheValuesRecordedOnMacOS` |
| Me — bar `.flexGrow(1)` before `.frame(height:)` for `.frame(maxWidth: .infinity)` | `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| Mf — button `.background`/`.cornerRadius` before its frame | `theDemoFrameMatchesTheValuesRecordedOnMacOS` |

**8.5 What must not move.** `docs/probes/demo-pixels/compare.sh <scratch>
85217e3 29c7200`: controls as in §4 (1048576, 1031003, 454895, 0, 1048576, 0,
544, 216, 491221, 529, 0), then **all fourteen images `differing=0 scene
identical`**. The hit-testing/accessibility/hover instrument
(`docs/probes/stage-8-demo-hit-ax-hover.swift`, copied in, run filtered,
deleted) at `85217e3`'s sources and at `29c7200`: **byte-identical**, 91 882 241
bytes each (md5 `0017b034…`), 3 hitboxes modal off (8 `hit` lines in all),
`hovered` true at both buttons and the list row, false at the readout and the
stack cluster, modal off. `Backends/SDL` (fetch-accesskit, then
`PKG_CONFIG_PATH=$PWD/.accesskit swift test`): 21 + 19 passed; fixtures
recorded from `85217e3`'s archive (`Experiments/SDLGPU`, `swift run
--build-system native Replay --portable --record`: frames 0–5 at 0 px, the
draw-order mutation detected), then the lane head's `PortableReplay … --expect
6` PASS (every frame 0 px, max Δ0) and `DemoCapture`: "scene built here: 518
rects, 15710 glyphs, 1008 runs; byte-for-byte macOS's: true", PASS.
`DemoFrameDeterminismTests` green unedited.

**8.6 T7's MetalUI half** (`LR-EZ` item 4): in a 300-wide `Column` under
`.proposal`, `Text("hi").frame(width: 100)` → frame (100, 0) 100×16, text at
x **145**, glyph origins 145 and 152; `alignment: .leading` → text at x **100**.
Centred, as SwiftUI's T1 (94.5 in a frame at 50). T7 is closed by spelling.

**8.7 Counts.** Unfiltered `swift test --build-system native --no-parallel`:
**`Test run with 1451 tests in 3 suites passed`** (1445 + 6), the log carrying
`FR-J no-argument frame: succeeded=true`. `swift build --build-system native
--build-tests`: 0 `error:`, the one `warning:` SwiftPM's notice; `swift build
--build-tests` (default build system): 0 `warning:`, 0 `error:`. No test
removed; six T rows (`LR-EZ`).

**8.8 Deferred, with owners.** `LoweringCorpusTests`' doc-comment mutations
from stages 2–5 were not re-run against the re-derived census (lane 3 or the
Record phase may; each is recorded where it was taken). *Superseded in part by
§9.2: four were re-run.* `Backends/SDL`'s build
with the deprecation in is lane 3's step 8. Nothing else.

## 9. Lane 1 review round (`LR-FA`)

**9.1 The framed absolute root (major).** The reviewer found that a framed
absolute box **as the frame's root** reported nothing under `.proposal` with
diagnostics (`[]`), where the own-box spelling reports
`[box.position.unconsumed, box.inset.unconsumed]` and the pre-stage-8 framed
spelling reported `modifierLayer.style`: `Frame.reportUnconsumedLoweredItems`
skipped every `.frameLayer` record, and `LR-EV` item 3's fix reached only
`planLegacyItems`, which a root is never planned by. Red first: N1.4 gained
arm 4 (`aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred`,
`PresentationLoweringTests.swift:707`), which read `arm 4, the frame's root:
[]`. Fix (`LR-FA`): an unconsumed `.frameLayer` record whose declared style is
absolute reports `position.unconsumed` and, with an inset, `inset.unconsumed`
— nothing else. A scratch test (never committed) read, with the fix: a
two-member component frame as an absolute root
`[modifierLayer.style, modifierLayer.position.unconsumed, modifierLayer.inset.unconsumed]`;
`.frame(20×20).flexGrow(1).position(.absolute)` as root
`[modifierLayer.style, modifierLayer.position.unconsumed]`; a plain framed root
`[]`. Unfiltered suite: `Test run with 1451 tests in 3 suites passed`, the log
carrying `FR-J no-argument frame: succeeded=true`; 0 `error:`, the one
`warning:` SwiftPM's notice. No test added or removed (an arm), so 1451 stands.

**M1i** — the unconditional skip restored (`guard d.position == .absolute else
{ continue }` → `continue`), committed-from, restored from a copy, full
unfiltered suite: `1451 tests … failed … with 1 issue`, reddening
`aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred`
only (arm 4). `git status --short` empty after the restore.

**9.2 The census's earlier mutations (minor), re-run.** Each committed-from
(`fix(stage 8 lane 1): LR-FA`), applied by script, full unfiltered suite,
`Sources` restored from `HEAD`, `git status --short` showing only this round's
uncommitted docs after each:

| mutation | spelling applied | reddened |
|---|---|---|
| stage 5 M1c | `LegacyLowering.swift` `lowerPresentation`: `frame.lowering.alias(node, to: root)` deleted | 24 issues: `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `aDeferredAbsoluteBoxResolvesItsInsetsAgainstTheWindowAndLeavesTheFlow`, `anAbsoluteBoxStretchedBelowItsPaddingKeepsItsInsetBoxWhereTheLegacyEngineFloorsIt`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| stage 5 M1d | `Deferred.swift` `presentationPlaceholder`: `frame.lowering.alias(placeholder, to: frame.lowering.alias(node))` deleted | 31 issues: `aDeferredAbsoluteBoxLowersAgainstTheWindowOnEveryInsetShape`, `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| stage 3 M2a | `ScrollView.swift` `loweredLayout`: `requestNativeScrollViewport(child: contentNode, …)` replaced by `requestNativeLeaf { p in LayoutMeasurement(size: SizeD(width: p.width ?? 0, height: p.height ?? 0)) }` (content node orphaned) — stage 3 did not record its spelling, so this is a re-spelling | 126 issues, 21 tests: `aClickTargetInsideAScrollViewSwallowsTheWheel`, `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`, `aDisabledScrollViewStillScrollsOnTheWheel`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs`, `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `aLoweredScrollViewsContentKeepsItsNaturalExtent`, `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, `aPresentationPlaceholderIsDroppedByEveryLoweredContainer`, `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`, `aScrollViewInsideAFrameKeepsItsViewportAndWheelUnderTheProposalAuthority`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `everyProductionRootsDeepestNativeLevelIsMeasured`, `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theTwoScrollElementsShareOneChromeImplementation`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| stage 3 M2d | `ScrollView.swift` `loweredLayout`: `declaredContent.flexShrink = 0` added | **aborts the run**: `Frame.swift:1603: Fatal error: MetalUI: scrollView.flexShrink.unconsumed has no proposal lowering`, inside `theDemoFrameMatchesTheValuesRecordedOnMacOS`; no summary line — as at stage 3 (record §25 §9.6). The census never ran |

All four are still caught; three redden the census itself. Stage 2's six
(M1a, M2a, M1d, M2k, M1m′, M5c′) were not re-run and remain owed to lane 3 or
the Record phase; the census's doc comment now says so by name.


## 10. Lane 2 — class K (`LR-EW`)

**10.1 The census, re-taken on lane 1's head** (`c8f731a`): the eight
`StyledElement` sizing modifiers given `@available(*, deprecated, message:
"LANE2CENSUS")` in a scratch edit of `Box.swift`, `swift build --build-system
native --build-tests`, every `warning:` carrying that message parsed to
`file:line:col`, `Box.swift` restored (`git checkout`, `git status --short`
empty). **1115 sites in the 28 K files**, the same per-file counts as the
committed census (`docs/probes/stage-8-deprecation-sites.txt`); the positions
agree exactly except 24 lines in the two K files lane 1 edited
(`LoweringCorpusTests` 4, `LoweringPipelineParityTests` 20), which moved by
line number only. An exit-test body (`#expect(processExitsWith:)`) is warned
twice, once at its source position and once inside `macro expansion #expect`
(29 such); only the source positions are sites, as in the committed census.

**10.2 The substitution.** A script replaced each warned `.<name>(` with
`.css<Name>(` at its census position, from the end of each file backward,
asserting the text at the column is `<name>(` preceded by `.` (the two
`fraction:` spellings map to `cssWidth(fraction:)`/`cssHeight(fraction:)`; none
of the 1115 is one). `git diff`: 28 files, 608 lines changed, 608 removed;
every `+` line equals its `-` line once each `.cssX(` is mapped back to `.x(`,
and the `+` lines carry exactly 1115 `.css…(` calls. Nothing else changed. The
scratch deprecation re-applied on the head warns **0** times in the 28 files;
what still warns is lane 3's 22 F files and `ModifierTests` alone.

**10.3 Red first.** No test is added in this lane, so there is no red line;
the lane's instruments are the unchanged suite and M2a/M2b below.

**10.4 Counts.** Unfiltered `swift test --build-system native --no-parallel`
on lane 1's head: `Test run with 1451 tests in 3 suites passed`; on this
lane's head (`6e621da`): **`Test run with 1451 tests in 3 suites passed`**,
the log carrying `FR-J no-argument frame: succeeded=`, and the sorted list of
passed/skipped test names identical to the base's (no test renamed). `swift
build --build-system native --build-tests`: 0 `error:`, the one `warning:`
SwiftPM's notice; `swift build --build-tests` (default build system): 0
`error:`, 0 `warning:`. Before − removed + added = after: 1451 − 0 + 0 = 1451.

**10.5 Mutations**, each applied by script to the committed tree, one build,
the full unfiltered suite with `--skip-build`, the file restored from a copy,
`git status --short` empty after each; run once on the lane's base (`c8f731a`)
and once on its head (`6e621da`):

| mutation | spelling applied | base | head |
|---|---|---|---|
| M2a | `LegacyLowering.swift` `planLegacyItems`, `axis(…)`'s non-greedy auto-axis tail: `return hasMin ? (resolvedDimension(animatedMin), nil) : nil` → `return nil` | `1451 tests … failed … with 16 issues`: `aFrameOverSeveralMembersStillPlansEachMembersItemFields`, `aGrownUnsizedSpaceDistributionContainerIsReported`, `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent`, `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned`, `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` | the same five, 16 issues |
| M2b | `Box.swift` `paint`: before `pass.paintDecoration(decoration, …)`, `var decoration = decoration; decoration.background = nil; decoration.hoverBackground = nil; decoration.focusBackground = nil` | 59 tests (below) | the same 59 |

**M2b aborts the unfiltered run** (`Swift/ContiguousArrayBuffer.swift:695:
Fatal error: Index out of range`) in tests that index `scene.rects[0]` after an
unrequired count check, so the run was repeated with each crashing test added
to `--skip` (anchored `name\(`) until a summary line printed: five crashers, in
order `aBoxResolvesItsBackgroundTokenAgainstTheFramesTheme`,
`theSameElementPaintsDifferentColoursUnderTheTwoThemes`,
`aContainerPaintsItsBackgroundBeneathItsChildren`,
`cornerRadiusReachesTheSceneThroughTheModifier`,
`aHostAppearanceChangeSwapsTheThemeAndRepaints` — the same five, in the same
order, on base and head — then `Test run with 1446 tests in 3 suites failed …
with 82 issues` on both. The 59 (the five crashers included):
`aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes`,
`aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter`,
`aBackgroundOnlyElementStillEmitsExactlyOneRect`,
`aBareCornerRadiusDoesNotClipTheChildren`,
`aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout`,
`aBorderIsVisibleOverAChildThatFillsTheBox`,
`aBoxResolvesItsBackgroundTokenAgainstTheFramesTheme`,
`aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`,
`aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning`,
`aComponentReadsTheNearestEnvironmentInItsContent`,
`aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`,
`aContainerPaintsItsBackgroundBeneathItsChildren`,
`aDisabledTargetIsNeitherHoveredNorPressed`,
`aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`,
`aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`,
`aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`,
`aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`,
`aHiddenElementPaintsNothingUnderTheProposalAuthority`,
`aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`,
`aHostAppearanceChangeSwapsTheThemeAndRepaints`,
`aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`,
`aHoveredBoxPaintsItsHoverBackground`,
`aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`,
`aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`,
`anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid`,
`anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`,
`anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting`,
`anElementWithNeitherABackgroundNorABorderEmitsNoRect`,
`aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`,
`anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected`,
`aParkedTransactionIsConsumedByExactlyOneBuild`,
`aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`,
`aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`,
`aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`,
`aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd`,
`aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`,
`aWholeValueWriteCannotResetTheThemeOrThePixelLength`,
`clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius`,
`cornerRadiusReachesTheSceneThroughTheModifier`,
`everyBackgroundPaintingSiteAnimatesItsColour`,
`everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`,
`everyBackgroundPaintingSiteHonoursHoverAndFocus`,
`everyDecorationScopingSiteContainsItsOwnContent`,
`everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`,
`focusBackgroundPaintsOnlyWhileFocusIsHeld`,
`focusOutranksHoverWhenAnElementIsBoth`,
`hoverAndFocusFadeThroughTheSameEffectiveColourPath`,
`hoverBackgroundWithoutAClickHandlerNeverPaints`,
`hoveringOneClickTargetDoesNotHoverItsSibling`,
`legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`,
`opacityMultipliesAndFadesTheElementsOwnBackground`,
`opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`,
`theDemoFrameMatchesTheValuesRecordedOnMacOS`,
`theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds`,
`theFramesRootEnvironmentCarriesItsThemeAndScale`,
`theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore`,
`theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`,
`theSameElementPaintsDifferentColoursUnderTheTwoThemes`,
`theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform`.
Identical sets base vs head for both: K reaches the same code.

**10.6 What must not move.** `docs/probes/demo-pixels/compare.sh <scratch>
85217e3 6e621da`: controls at `85217e3` as in §8.5 (1048576, 1031003, 454895,
0, 1048576, 0, 544, 216, 491221, 529, 0), then **all fourteen images
`differing=0 scene identical`**. No `Sources/` file changed in the lane, so the
hit-testing/accessibility/hover instrument and `Backends/SDL` were not re-run.

**10.7 Deferred.** Nothing.
