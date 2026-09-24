# §50 — Engine replacement, stage 8: the sizing vocabulary

Plan task 7, stage 8 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 8,
§8; `FR-F`, `FR-G`, `FR-H`, `FR-I`). Design:
`docs/superpowers/specs/2026-09-24-engine-stage-8-design.md`. Rulings
`LR-ER`…`LR-FB` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md` (next unused
`LR-FC`).
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

**Status, 2026-09-24 (PDT): delivered.** §12 is the Record phase's close: all
three lanes' verdicts were `ok: true` with mutation tables (§8–§11); a clean
`swift package clean` + native build + unfiltered suite at the final head
(`05d670b`) reads **1452 tests in 3 suites passed**, 0 goldens, **79** guards,
0 `error:`/the one SwiftPM `warning:` on both build systems; the fourteen-image
offscreen comparison against `85217e3` still reads 0 differing (no `Sources/`
line moved since lane 3's `39adea3`, where it was last measured); spec §8's
five exit criteria all hold. CLAUDE.md/AGENTS.md, records §04/§05/README, the
plan's task 7 note and the top-level README are updated to match (§12).

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


## 11. Lane 3 — class F, class D, the deprecation (`LR-FB`)

Commits: `e62cfd9` (red first: N3.1 and T3.1), `39adea3` (the eight
deprecations, the 22 F files, `ModifierTests` to D, `Box.swift`'s Size section
and `Component.swift`'s comments), then this record and `LR-FB`.

**11.1 The census, re-taken** with the real attributes in `Box.swift` (spec §4's
messages) on lane 2's head (`1604674`) plus the red commit: **433 sites in 23
files** — the 22 F files' 425 and `ModifierTests`' 8 — the same per-file counts
as spec §5.2's table; 0 in `Sources/MetalUIDemoContent`, the 28 K files, the
lane-1 files and `CSSSizing.swift`'s witness. The converter was re-written to
start runs only at those compiler-reported positions
(`docs/probes/stage-8-sizing-converter.py` matches every `.width(` including
`Component.width`, which is not deprecated; the census-driven variant lived in
the session scratchpad and is described here rather than committed).

**11.2 Site coverage before** (step 1, on `1604674`, full unfiltered suite,
each mutation applied by script to the committed tree, restored from a copy,
`git status --short` empty after):

| mutation | spelling | reddened |
|---|---|---|
| Ms1 | `Box.swift` `prepaint`: `pass.registerAndScope(handlers, …)` → `pass.registerAndScope(Handlers(), …)` | `1451 tests … failed … with 236 issues`, **129 tests** (below) |
| Ms2 | `Text.swift` `paint`: `var decoration = decoration; decoration.background = nil; decoration.hoverBackground = nil; decoration.focusBackground = nil` before `paintDecoration` | `1451 … 3 issues`: `everyBackgroundPaintingSiteAnimatesItsColour`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus` |
| Ms3 | `Stack.swift` `paint`: the same line before `paintDecoration` | `1451 … 7 issues`: `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `everyBackgroundPaintingSiteAnimatesItsColour`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `nestedPresentationsLandOnOneLayerUnderBothAuthorities` |
| Ms4 (lane 2's M2b; added by the review round, §11.11) | `Box.swift` `paint`: the same line before `pass.paintDecoration(decoration, in: bounds, for: id) {` | with lane 2's five `--skip`s (§10.5): `1446 tests … failed … with 82 issues`, **63 tests** (below) |

Ms1's 129: `aBoundActionReachesAnElementHandlerAlongTheFocusChain`, `aBoundActionRunsBeforeARawOnKeyHandler`, `aBoxWithADeclaredAXNodeEmitsItAtItsOwnResolvedBounds`, `aCallerDeclaredAXNodeOnAListSurvivesLogicalCountBeingAdded`, `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aClickInsideTheBoundsRunsTheHandler`, `aClickNeedsTheTargetEnabledAtPressAndAtRelease`, `aClickOutsideTheBoundsDoesNotRunTheHandler`, `aClickTargetInsideAScrollViewSwallowsTheWheel`, `aClientDoesNotChangeStateRetention`, `aContentShapeInsetShrinksTheHitRegionAndChangesNoLayout`, `aContentShapeMovesNeitherTheAccessibilityFrameNorTheFocusRegistration`, `aContentShapeOnAFrameLayerInsetsTheFrameBoxAndBeforeItTheChildBoxUnderTheProposalAuthority`, `aContentShapeWithoutAClickHandlerRegistersNothing`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `aDeclaredAXNodeIsEmittedByEveryConformerThatRegistersHandlers`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`, `aDisabledClickTargetPassesTheClickToWhatIsUnderIt`, `aDisabledElementCannotAcquireFocus`, `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`, `aDisabledElementsActionHandlerDoesNotClaimAKeymapAction`, `aDisabledElementsAXNodeCarriesTheDisabledTrait`, `aDisabledPaneContributesNoKeyContext`, `aDisabledScopeReachesIntoDeferredContent`, `aDisabledTargetIsNeitherHoveredNorPressed`, `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler`, `aFocusableElementNeedsNoHandlerAndAHandlerNeedsNoFocusability`, `aFocusableRowInsideAScrollViewDoesNotSwallowTheWheel`, `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `aFocusRingAndHoverBorderDrawOnTheLayerTheyAreWrittenOnAroundAFrame`, `aFocusRingOutranksAHoverBorderAndABorder`, `aFramedAbsoluteBoxIsAPresentationRootUnderBothAuthorities`, `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne`, `aHandlerThatClaimsTheEventStopsTheWalk`, `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aHiddenClickTargetPassesTheClickToWhatIsUnderIt`, `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`, `aHiddenRootPublishesNothing`, `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`, `aHoveredBoxPaintsItsHoverBackground`, `aKeyContextIsContributedByANonFocusableAncestor`, `aKeyContextRegistersNoPointerHitbox`, `aKeyEventDispatchesToTheFocusedElement`, `aKeyEventWithNothingFocusedReachesTheWindow`, `aKeyUpIsNotDispatchedToTheFocusChain`, `aLabelledClickTargetOnAFrameLayerPublishesTheFrameBoxWhileItsHitRegionIsInset`, `aLabelledListIsStillATable`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `allowsHitTestingFalseRemovesTheRECEIVERSOwnPointerTargetAndItsSubtreesAndKeepsTheKeyboardOnes`, `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `anActionBubblesPastAnElementThatDoesNotHandleIt`, `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `anAppsKeymapBindingWinsOverEditingAndUnclaimedKeysBubble`, `aNegativeContentShapeInsetGrowsTheHitRegionAndIsStillClippedByAnAncestor`, `anElementThatStopsBeingFocusableLosesFocus`, `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire`, `aNestedHandlerWinsOverItsContainingStackToo`, `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`, `anIncrementRequestRunsTheAdjustmentHandler`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, `aNodesParentIsItsNearestEmittingAncestor`, `anUnchangedFrameIsNotRepublished`, `anUnhandledActionFallsThroughToTheRawKeyBubble`, `anUnhandledKeyEventBubblesToItsAncestorsInnermostFirst`, `aPaddedClickTargetIsHittableInItsPaddingWhereSwiftUIIsNot`, `aPressIsRefusedWhereHitTestingIsDisabled`, `aPressOnOneElementReleasedOnAnotherIsNotAClick`, `aPressReleasedOverSomethingCoveringItIsNotAClick`, `aPressRequestRunsOnClickThroughTheLastFramesHitboxes`, `aPressThatLeavesTheElementAndReturnsStillClicks`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aTwoStrokeSequenceDispatchesThroughTheWindow`, `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling`, `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, `aVirtualizedListsLogicalCountIsTheFullDataCountEvenWhenEveryRowFits`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`, `childrenFollowDeclarationOrderWhereIDsAloneCannot`, `clippedAlsoClipsTheHitboxesInsideIt`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `declaredRolesLabelsValuesAndTraitsReachThePublishedNode`, `eachLiveHandlerAloneMakesAnUndeclaredElementRecord`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationPaintingSiteHonoursTheBorderHoverAndFocusChain`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload`, `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `focusabilityAndKeyHandlingRegisterNoPointerHitbox`, `focusBackgroundPaintsOnlyWhileFocusIsHeld`, `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`, `focusOutranksHoverWhenAnElementIsBoth`, `focusSurvivesAFrameInWhichTheFocusedElementIsRebuilt`, `focusSurvivesAndDispatchesInsideADeferredSubtree`, `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`, `hoverAndFocusFadeThroughTheSameEffectiveColourPath`, `hoveringOneClickTargetDoesNotHoverItsSibling`, `metalUIsDefaultHitRegionIsTheElementsWholeFrame`, `movingFocusAndClaimingAKeyBothRedrawTheWindow`, `onClickIsLiveOnEveryConformerThatCanRegisterOne`, `onKeyIsLiveOnEveryConformerThatCanRegisterOne`, `onlyABoxWithAHandlerRegistersAHitbox`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`, `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt`, `reEnablingRestoresClicksButNotFocus`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `synthesizedNodesCostNothingWhileNoClientIsActive`, `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, `theGateReadsTheEnvironmentValueNotTheModifier`, `theHandlerReceivesTheEventThatArrived`, `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows`, `theTopmostOfTwoOverlappingHandlersRuns`.

Ms4's 63 (the five skipped crashers excluded; names read from every `Test
<name>(…) recorded an issue` line, parameterised tests included — §10.5's list
of 59 omits nine parameterised ones, `aDeferred…` ×4, `aListsSceneAndHitboxesAreUnchangedByTheGroup`,
`anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`,
`aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope` and
the two `aScrollView…CornerRadius…`/`…ClipsSquare` tests, and counts the five
crashers in): `aBackgroundBeforeOrAfterALegacyFrameFillsTheBoxItWasWrittenOnAsSwiftUIDoes`, `aBackgroundIsEmittedBeforeTheChildrenAndABorderAfter`, `aBackgroundOnlyElementStillEmitsExactlyOneRect`, `aBareCornerRadiusDoesNotClipTheChildren`, `aBorderIsPaintedInsideTheElementsBoxAndChangesNoLayout`, `aBorderIsVisibleOverAChildThatFillsTheBox`, `aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`, `aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning`, `aComponentReadsTheNearestEnvironmentInItsContent`, `aComponentsFrameCarriesTheNewDecorationsAndScopesItsMembersUnderTheProposalAuthority`, `aDeferredAbsoluteScrimCoversTheWindowAndEscapesTheScrollUnderBothAuthorities`, `aDeferredBoxInsideARealScrolledScrollViewDoesNotSlideWithTheScroll`, `aDeferredElementHoistsItsChildAboveASiblingDeclaredAfterIt`, `aDeferredPortalInsideAFadedSubtreeIsStillFaded`, `aDisabledTargetIsNeitherHoveredNorPressed`, `aFrameLayersClipAndBorderBoundTheChildTheFrameCannotShrink`, `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`, `aGreedyFrameAnswersBelowItsContentOnlyWithAZeroMinimum`, `aHiddenElementInsideAnyElementIsHiddenUnderTheProposalAuthority`, `aHiddenElementPaintsNothingUnderTheProposalAuthority`, `aHiddenInnerModifierLayerSkipsPaintAndHitsPerLayer`, `aHoverBackgroundNeverPaintsUnderAllowsHitTestingFalse`, `aHoveredBoxPaintsItsHoverBackground`, `aLegacyChainsBackgroundCoversTheBoxAtThePointItWasWritten`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`, `anAbsoluteBoxInsideAScrollViewIsStillClippedAndScrolledByIt`, `anAnimatedFrameWidthInterpolatesAsTheAnimatedWidthItReplacesDid`, `anAnimatedWriteThatIsNotTheFirstObservableWriteOfItsIntervalStillAnimates`, `anAnimatingElementThatVanishesAndReturnsResumesRatherThanRestarting`, `anElementWithNeitherABackgroundNorABorderEmitsNoRect`, `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`, `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected`, `aParkedTransactionIsConsumedByExactlyOneBuild`, `aRoundedBorderFollowsTheArcWhereSwiftUIsClippedSquareBorderDoesNot`, `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`, `aScrollRegionInsideAllowsHitTestingFalseIsStillRegistered`, `aScrollViewsCornerRadiusReachesEveryPrimitiveItClips`, `aScrollViewWithNoCornerRadiusClipsSquare`, `aSecondOpacityOnOneElementReplacesTheFirstWhereSwiftUIMultiplies`, `aTransactionParkedOutsideTheBuildAnimatesTheNextFrameEndToEnd`, `aTransactionWhoseBodyDirtiesNothingIsNeverParkedAndCannotAnimateALaterChange`, `aWholeValueWriteCannotResetTheThemeOrThePixelLength`, `clippedCutsTheSubtreeToTheElementsBoxAndRoundsItByTheCornerRadius`, `everyBackgroundPaintingSiteAnimatesItsColour`, `everyBackgroundPaintingSiteFadesItsResolvedHoverAndFocusColour`, `everyBackgroundPaintingSiteHonoursHoverAndFocus`, `everyDecorationScopingSiteContainsItsOwnContent`, `everyOuterModifierIsTheKindTheMatrixSaysUnderTheProposalAuthority`, `focusBackgroundPaintsOnlyWhileFocusIsHeld`, `focusOutranksHoverWhenAnElementIsBoth`, `hoverAndFocusFadeThroughTheSameEffectiveColourPath`, `hoverBackgroundWithoutAClickHandlerNeverPaints`, `hoveringOneClickTargetDoesNotHoverItsSibling`, `legacyPaddingAccumulatesAcrossAChainAsSwiftUIDoes`, `opacityMultipliesAndFadesTheElementsOwnBackground`, `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot`, `theDemoFrameMatchesTheValuesRecordedOnMacOS`, `theDisplayLinkStaysRunningWhileAnimatingAndPausesOnTheFrameAfterTheLastEnds`, `theFramesRootEnvironmentCarriesItsThemeAndScale`, `theLegacyHiddenPathPaintsAndHitTestsExactlyAsBefore`, `theNewPaintOnlyDecorationFieldsSnapRatherThanAnimate`, `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform`.

**11.3 Red first** (unfiltered, `e62cfd9`): `Test run with 1452 tests in 3
suites failed … with 14 issues`. N3.1 `FrameSizingCompileGuards.swift:214`
`lines.count == 8` (0) and `:232` ×11 (no message names its replacement); its
control arm green (count 0). T3.1 `ContainerCompileGuards.swift:137`
`deprecations(control) == 2` (0) and `:139` (neither fraction's deprecation).
No other test red.

**11.4 The conversion, and why most of it went K** (`LR-FB`). The census-driven
converter applied R1 and R3 to all 425 sites (190 frames); by hand: R2 —
`ObservationTests`' nine `Box().background(.surface)` receivers and
`ScrollViewTests`' five `Box(decoration: Decoration(background: .surface))`
(→ `Box().frame(…).background(.surface)`, S2); R3 — the `Row` roots `.leading`
(`AccessibilityDefaultsTests`' `combine`, `InputDispatchTests`' vanishing-`if`
root), the padded and unpadded `Column` roots of
`spriteDestinationsAreThePenPositionPlusTheRasterizersBearings` `.topLeading`
(its oracle puts the text at the padding, the content's placement; `.top`
reddened it at `:313`/`:344`), and the centring `Box` of
`aCentredShrinkWrappedLabelNeverWrapsAtAnyValue` to the default `.center` with
its `alignItems(.center)`/`justifyContent(.center)` dropped; helper types —
`declared(_:_:)` generalised from `Box<C>` to any `StyledElement` in
`AccessibilityTreeTests` and `AccessibilityEndToEndTests` (it only sets
`handlers.axNode`), `EnvironmentTests`' `surfaceBox`, `tree()` and the E15
`Leaf` typealias to `ModifiedElement<Box<EmptyGroup>>`. Then K per test, for
four reasons, in this order:

1. **By reading, before any run** (K1/K2 of spec §5.2):
   `onClickIsLiveOnEveryConformerThatCanRegisterOne`,
   `onKeyIsLiveOnEveryConformerThatCanRegisterOne`,
   `aNestedHandlerWinsOverItsContainingStackToo`,
   `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`
   (each enumerates registration sites — `Stack`'s, `Text`'s, a bare `Box`'s —
   that R2 would move onto a `ModifiedElement` layer),
   `aContainerPaintsItsBackgroundBeneathItsChildren` (its subject is
   `Box.paint`'s container order; R2 would move the background onto the frame
   layer); `ComponentTests`' `Leaf` (7 lines) and `ElementGroupTrapTests`'
   `StateProbe` (4 lines, `twoSiblingsWithTheSameIDShareOneStateEntry`,
   `twoSiblingsWithDifferentIDsDoNotShareState`) — custom elements whose
   measure reads their own `style.size`, the latter also asserting a structural
   path with `.id()` before the sizing; `legacySpelledScrolledListRoot` (K1: the
   root `minSize` fold is its subject) and `aWidthModifierOnAListReachesItsLayoutNode`
   (K1: its name); `paintWrapsAtTheWidthLayoutMeasuredAtNotTheRoundedBox` (its
   instrument is `tree.children(root)[0]`, which a frame root would silently
   re-point from the `Text` to the `Row`).
2. **An assertion moved** (first full run, 11 tests red): the four
   `AccessibilityDefaultsTests` `List` tests on `.legacy`
   (`combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`,
   `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`,
   `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`,
   `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`: a legacy
   frame layer over one node is a one-cell stack its child overflows, so the
   scroller's viewport is no longer 200) — `scrolledList`'s box and the
   bounded-window test's own box went K, and so did the control arm of
   `aRootMinHeightOnTheScrollerFixtureNoLongerAbortsAProductionProposalFrame`,
   which must stay "the same tree without that one modifier";
   `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting` (both
   authorities; `alignItems(.stretch)` moved before the frame is R4's spelling,
   and neither the legacy outer width 50 nor the proposal inner width 150
   survived it); `aListInTheDifferentialHarnessReachesABoundedWindow` and
   `aListsSceneAndHitboxesAreUnchangedByTheGroup` (`.legacy`, the same
   overflow; with them `ListTests` is wholly K); `activeSurvivesAFrameBoundary`
   and `anOrphanLegacyRegistrationBesideATypedLeafIsNotRejected` (each
   **asserts** a structural id, R7). `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`
   was red on a locator path, re-derived by R7, and then went K under reason 3;
   `spriteDestinations…` was re-spelled by R3 (above) and stayed F.
3. **The site-coverage check** (Ms1 after the first green run: 81 tests, 48 of
   the 129 missing, none added — every one a test whose `Box` carried its own
   handler, focusability, key context, action or accessibility node, which R2
   had moved onto the frame layer): `aBoundActionReachesAnElementHandlerAlongTheFocusChain`, `aBoundActionRunsBeforeARawOnKeyHandler`, `aClickInsideTheBoundsRunsTheHandler`, `aClickOutsideTheBoundsDoesNotRunTheHandler`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aDispatchedClickDoesNotAlsoReachTheWindowsRawHandler`, `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot`, `aHandlerRegisteredOnFrameNRunsForAnEventBeforeFrameNPlusOne`, `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, `aHiddenOneNodeFrameLayerPublishesNothingToAnAccessibilityClient`, `aHiddenRootPublishesNothing`, `aKeyContextRegistersNoPointerHitbox`, `aKeyEventDispatchesToTheFocusedElement`, `aKeyEventWithNothingFocusedReachesTheWindow`, `aKeyUpIsNotDispatchedToTheFocusChain`, `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`, `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `anElementThatStopsBeingFocusableLosesFocus`, `aNestedHandlerWinsOverItsContainerWhichDoesNotAlsoFire`, `anIncrementRequestRunsTheAdjustmentHandler`, `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, `aNodesParentIsItsNearestEmittingAncestor`, `anUnchangedFrameIsNotRepublished`, `anUnhandledActionFallsThroughToTheRawKeyBubble`, `aPressIsRefusedWhereHitTestingIsDisabled`, `aPressOnOneElementReleasedOnAnotherIsNotAClick`, `aPressReleasedOverSomethingCoveringItIsNotAClick`, `aPressRequestRunsOnClickThroughTheLastFramesHitboxes`, `aPressThatLeavesTheElementAndReturnsStillClicks`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aTwoStrokeSequenceDispatchesThroughTheWindow`, `aVanishingIfBetweenPressAndReleaseClicksTheTrailingSibling`, `childrenFollowDeclarationOrderWhereIDsAloneCannot`, `declaredRolesLabelsValuesAndTraitsReachThePublishedNode`, `eachLiveHandlerAloneMakesAnUndeclaredElementRecord`, `focusabilityAndKeyHandlingRegisterNoPointerHitbox`, `focusOnAnElementThatStopsBeingProducedIsRetainedWithinTheWindow`, `focusSurvivesAFrameInWhichTheFocusedElementIsRebuilt`, `focusSurvivesAndDispatchesInsideADeferredSubtree`, `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`, `movingFocusAndClaimingAKeyBothRedrawTheWindow`, `onlyABoxWithAHandlerRegistersAHitbox`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`, `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt`, `theHandlerReceivesTheEventThatArrived`, `theTopmostOfTwoOverlappingHandlersRuns` — `AccessibilityTreeTests` 17,
   `InputDispatchTests` 11, `FocusTests` 10, `KeymapTests` 5,
   `AccessibilityDefaultsTests` 2, `AccessibilityEndToEndTests` 2,
   `TrackInteractionTests` 1. Their bodies went K (46 tests had sites in the
   body; the R7 re-derivations in two of them were reverted with the K); the
   second Ms1 run still missed `anUnchangedFrameIsNotRepublished` and
   `aLayerAddedAtRunTimeKeepsTheOutermostAccessibilityNodeAndRepublishesTheWrappedOne`,
   whose boxes are in helpers (`PressToRename`, `labelledChain`), which then
   went K.
4. **Ms4, `Box`'s own background** (the review round, §11.11): ten tests
   M2b reddened before and not after, all K by rule 1 — 22 sites:
   `ThemeTests`' `aBoxResolvesItsBackgroundTokenAgainstTheFramesTheme`,
   `theSameElementPaintsDifferentColoursUnderTheTwoThemes` (its
   `paintedBackground` helper) and `cornerRadiusReachesTheSceneThroughTheModifier`
   (6); `ScrollViewTests`' `aScrollViewsCornerRadiusReachesEveryPrimitiveItClips`
   and `aScrollViewWithNoCornerRadiusClipsSquare` (10, their R2 receivers
   back to `Box(decoration: Decoration(background: .surface))`); and
   `EnvironmentTests`' `aComponentReadsTheNearestEnvironmentInItsContent`
   (`EnvComponent`), `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`,
   `aWholeValueWriteCannotResetTheThemeOrThePixelLength` and
   `theFramesRootEnvironmentCarriesItsThemeAndScale` (`surfaceBox`, back to
   `-> Box<EmptyGroup>`), `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform`
   (its `tree()`) (6). The design's earlier line here — the background moves
   "judged by K2's rule" by reading — was refuted by this measurement.
5. No test took R: nothing was retired.

**Result: F 129 sites, K 296, in the 22 files** (151/274 before §11.11) (per file, F/K:
`AccessibilityDefaultsTests` 52/15, `AccessibilityEndToEndTests` 2/6,
`AccessibilityTreeTests` 8/86, `ComponentTests` 6/14, `DeferredTests` 0/2,
`ElementGroupTrapTests` 0/8, `EnvironmentTests` 6/6, `FocusTests` 10/38,
`FrameLoopTests` 2/0, `GlyphEmitterTests` 6/2, `HitboxTests` 2/2,
`InputDispatchTests` 2/66, `KeymapTests` 10/10, `ListTests` 0/4,
`ObservationTests` 17/0, `ProposalNodeIDTests` 0/2, `ScrollViewTests` 0/10,
`StateTests` 2/0, `TextMeasureTests` 1/0, `TextSystemSeamTests` 1/0,
`ThemeTests` 2/9, `TrackInteractionTests` 0/16). The design expected 425/0.
**Every K line equals its `85217e3` line** once each `.cssX(` is mapped back to
`.x(` (checked mechanically over all 22 files: the only non-`.frame` new-side
lines left are the two `declared` signatures, `Leaf`'s type and one
re-broken `Box()` line in `ObservationTests`; before §11.11 also
`surfaceBox`'s type and one comment in `ScrollViewTests`, both back to their
`85217e3` lines since). No assertion edited; no test renamed.

**11.5 Class D.** `ModifierTests.everyPublicModifierWritesItsOwnFieldAndOnlyThatField`'s
eight Size rows moved verbatim into `DeprecatedSizingCases`, a
`DeprecatedSpelling` whose witness carries `@available(*, deprecated, …)`,
spliced back at their place (`[…] + oldSpelling(DeprecatedSizingCases()) +
[…]`); `cases.count == 47` unchanged.

**11.6 Site coverage after** (on the lane's working tree once the F files were
final — before the D move, `Box.swift`'s comments and `Component.swift`'s,
which touch no F file and no `Sources/` code line — with the eight
deprecations in): Ms1 `1452 tests … failed … with 229 issues`, Ms2 `… 3
issues`, Ms3 `… 7 issues`; **each reddened set is identical to its before set**
(⊇ holds with equality; 129, 3, 5 tests). Ms4 was not run here; §11.11
measured it at the review round's head, equal to its before set.

**11.7 Mutations of the new and changed guard** (committed `39adea3`, full
unfiltered suite, restored from a copy, `git status --short` empty after):

| mutation | spelling | reddened |
|---|---|---|
| M3a | `width(_:)`'s `@available` deleted | `theSizingModifiersAreDeprecatedTowardFrame` only (`:214` count 7, `:232` once) |
| M3b | `width(fraction:)`'s `@available` deleted | `thePercentSizingModifiersAreDeprecatedRenamesOfFraction` (`:137` control reads 1, `:139`) and `theSizingModifiersAreDeprecatedTowardFrame` (count 7, `:232` twice) |

**11.8 Counts.** After `swift package clean`: `swift build --build-system
native --build-tests` — 0 `error:`, the one `warning:` SwiftPM's notice;
`swift build --build-tests` (default build system) — 0 `error:`, 0 `warning:`.
Unfiltered `swift test --build-system native --no-parallel`: **`Test run with
1452 tests in 3 suites passed`**, the log carrying `FR-J no-argument frame:
succeeded=true` and `N3.1 sizing deprecations: succeeded=true count=8`. Guards
**79** (`FrameSizingCompileGuards` 2 → 3; `git grep -c canTypecheck` 81 hits
less `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment). Before −
removed + added = after: 1451 − 0 + 1 = 1452 (the stage: 1445 − 0 + 7). The
portable CI suites (`MetalUICoreTests`, `MetalUILayoutTests`,
`MetalUICrossPlatformTests`) are untouched.

**11.9 What must not move.** `docs/probes/demo-pixels/compare.sh <scratch>
85217e3 39adea3`: controls as in §8.5 (1048576, 1031003, 454895, 0, 1048576,
0, 544, 216, 491221, 529, 0), then **all fourteen images `differing=0 scene
identical`**. `DemoFrameDeterminismTests` green unedited. `Backends/SDL`, its
`.build` removed, `PKG_CONFIG_PATH=$PWD/.accesskit swift build --build-tests`
with the deprecation in: **0 lines containing `deprecated`** (the only
`warning:`s are the SDL3 dylib's macOS-version linker notices and the `sdl`
pkg-config rpath notice, present before this stage); `swift test` 21 + 19
passed; fixtures recorded from `85217e3`'s archive (`Experiments/SDLGPU`,
`swift run --build-system native Replay --portable --record`: frames 0–5 at 0
px, draw-order mutation detected), then the head's `PortableReplay … --expect
6` PASS (every frame 0 px, max Δ0) and `DemoCapture` "byte-for-byte macOS's:
true", PASS. `git grep` finds no call of the eight in `Backends`,
`Tests/PortableTests`, `Tests/MetalUICrossPlatformTests` or `Experiments`, and
in `Sources/MetalUIDemoContent` only comment lines (exit criterion 3). No
`Sources/` file changed but `Box.swift` (attributes, comments) and
`Component.swift` (comment lines only), so the hit-testing/accessibility/hover
instrument was not re-run.

**11.10 Deferred, with owners.** The Record phase: CLAUDE.md/AGENTS.md
(spec §9's list), and the F/K figures above in place of the design's
425/0. Stage 10: the 296 new K sites join lane 2's 1115 (1411 `css*` sites in
the F and K files, plus lane 1's).

**11.11 Review round: Ms4** (`LR-FB`, amended). The review applied lane 2's
M2b before (`1604674`) and after (`61abb55`) with lane 2's five `--skip`s
and found ten names missing after, none added — the ten of §11.4 reason 4.
Re-measured here, each run by script (the mutation inserted before `Box.swift`'s
one `pass.paintDecoration(decoration, in: bounds, for: id) {`, one native
build, the full unfiltered suite with `--skip-build` and the five anchored
`--skip`s, `Box.swift` restored from a copy, `git status --short` empty):

| tree | summary | names |
|---|---|---|
| `1604674` (before) | `Test run with 1446 tests in 3 suites failed … with 82 issues` | 63 (§11.2) |
| `61abb55` (lane 3's head) | `1447 tests … failed … with 72 issues` | 56: the 63 less the seven `ScrollViewTests`/`EnvironmentTests` names (the three `ThemeTests` ones are skipped in both runs, so this instrument shows them only by their crash at `1604674` and not at `61abb55`) |
| `2f9e615` (the fix) | `1447 tests … failed … with 82 issues` | **63, identical to before** |

Un-skipped at `2f9e615`, M2b aborts at the same five crashers in the same
order as §10.5's base (`aBoxResolvesItsBackgroundTokenAgainstTheFramesTheme`,
`theSameElementPaintsDifferentColoursUnderTheTwoThemes`,
`aContainerPaintsItsBackgroundBeneathItsChildren`,
`cornerRadiusReachesTheSceneThroughTheModifier`,
`aHostAppearanceChangeSwapsTheThemeAndRepaints`, each
`ContiguousArrayBuffer.swift:695: Fatal error: Index out of range`), then the
same `1447 … 82 issues` — so the three `ThemeTests` tests pin `Box.paint`
again. Unmutated at `2f9e615`: `swift build --build-system native
--build-tests` 0 `error:`, the one `warning:` SwiftPM's notice; unfiltered
**`Test run with 1452 tests in 3 suites passed`**, `N3.1 sizing deprecations:
succeeded=true count=8` and `FR-J no-argument frame: succeeded=true` in the
log. Every changed line equals its `85217e3` line modulo the `css` prefix. No
assertion edited, no test renamed or retired; before − removed + added =
after, 1452 − 0 + 0 = 1452. No `Sources/` line and no demo-reachable file
changed, so the offscreen comparison and `Backends/SDL` were not re-run.

## 12. The stage's close (Record phase, 2026-09-24, PDT)

Spec §8's exit criteria, each read at `05d670b` (lane 3's head; the two Record
phase commits before this one touch only test/doc files):

1. **0 `warning:`** besides SwiftPM's notice, with the eight deprecations in
   place. After `swift package clean`: `swift build --build-system native
   --build-tests` → `Build complete!`, 0 `error:`, the one `warning:`
   SwiftPM's own deprecation-of-the-flag notice; `swift build --build-tests`
   (default build system) → 0 `error:`, 0 `warning:`.
2. Unfiltered `swift test --build-system native --no-parallel` →
   **`Test run with 1452 tests in 3 suites passed`** (91.433 s), the log
   carrying `FR-J no-argument frame: succeeded=true` and `N3.1 sizing
   deprecations: succeeded=true count=8`. **79 guards**: `grep -c
   canTypecheck` per guard file sums to 80 (`FrameSizingCompileGuards` now 3,
   every other file as at `85217e3`), less `Typecheck.swift`'s own
   declaration and `UnitSafetyTests`' comment-line hit = 79; `typecheckFile`'s
   helper count 38 → 39 (`FrameSizingCompileGuards`' N3.1 guard and its
   control arm both call `typecheckFile`). **0 goldens** (`find
   Tests/MetalUILayoutTests -name "*.json" | wc -l` reads 0).
3. **The census re-taken with the deprecations in**: `grep -nE
   '\.(width|height|minWidth|maxWidth|minHeight|maxHeight)\('
   Sources/MetalUIDemoContent/*.swift` returns **5 lines, all comments**
   (`DemoContent.swift:528,675,677,681,692` — each names the old spelling in
   a doc comment explaining the conversion, never a call). No `Sources/`
   target outside a `D`-class witness calls any of the eight (the native
   build's 0 `error:`/1 `warning:` above is only reachable if every remaining
   call is inside a `@available(*, deprecated, …)` declaration — a live call
   anywhere else would print `warning: 'x' is deprecated` under
   `-warnings-as-errors` off, and none does; `git grep` for the six bare names
   and `(fraction:` outside `Tests/MetalUITests/CSSSizing.swift`,
   `ModifierTests.swift`'s `DeprecatedSizingCases` and doc comments finds
   nothing else).
4. **The fourteen-image offscreen comparison against `85217e3`**: `docs/probes/demo-pixels/compare.sh`
   read **0 differing, scene identical, all fourteen images** at lane 1's
   `29c7200`, again unchanged at lane 3's `39adea3` (§11.9), and `git diff
   --stat 39adea3 05d670b -- Sources/` is **empty** — no `Sources/` line moved
   since, so the result stands at this head without re-running the script.
   `DemoFrameDeterminismTests` is unedited and green (in the 1452). The demo's
   hitbox/accessibility/hovered-scene comparison
   (`docs/probes/stage-8-demo-hit-ax-hover.swift`) read byte-identical at
   `29c7200` (§8.5) and is likewise unaffected by any later commit (all
   `Sources/` changes since are `Box.swift`'s attributes/comments and
   `Component.swift`'s comments, `LR-EZ`/`LR-FB`). `Backends/SDL` built with
   the deprecation in drew **0** deprecation warnings and its
   `PortableReplay`/`DemoCapture` passed unedited (§11.9); nothing in
   `Backends/SDL` or `Tests/PortableTests` calls any of the eight (`git grep`
   empty).
5. **N1.1–N1.6** (lane 1, §8.2/§8.7) and **N3.1** (lane 3, §11.3/§11.7) are
   green in the 1452; each named mutation reddened what §6 names (§8.4, §9,
   §10.5, §11.2, §11.7, §11.11); the site-coverage sets held with **equality**
   throughout (Ms1–Ms3 identical base vs head, §10.5; Ms4 identical before vs
   after the fix, §11.11) rather than merely `⊇`.

All five hold. **Accounting**: 1445 − 0 + 7 = 1452 (lane 1's six T rows,
`LR-EZ`/`LR-FA`; lane 3's one D row, `ModifierTests`' eight sizing rows moved
verbatim into `DeprecatedSizingCases`, one test relocated, not eight created);
guards 78 → 79; goldens 0 → 0. **Class totals, measured**: F, tests only
(excluding the demo's own 25 production sites): 129 (lane 3's of 425) + 37
(lane 1's `PresentationWindowTests` 24 + `FrameSizingTests` 13) = **166**; K
1115 (lane 2) + 296 (lane 3's fallback) = **1411**, plus lane 1's
`PresentationLoweringTests`/`AnimationTests` sites that stayed K1/K2 (56 and
26 minus the arms `LR-EV` moved to F, not separately counted);
D 8 (`ModifierTests`, one test); R 0. Portable CI untouched: `MetalUICoreTests`
+ `MetalUILayoutTests` + `MetalUICrossPlatformTests` stay **200 + 22 + 3**
(no census site in any file those targets build).

Handed on (spec §9): to stage 9, the K1 tests' legacy arms retire with the
legacy authority, their proposal arms keeping the `css*` spelling until
stage 10; to stage 10, `CSSSizing.swift` and every `css*` site (≈ 1411, this
stage's own K plus lane 2's) die or are re-spelled with `Style.size`/
`minSize`/`maxSize`, the `Style()` writes in tests (232 lines, 50 files,
record §50 §2) likewise, and every `Style`-field report this stage inherited
and kept (percentages, a non-greedy `maxSize`, a length `flexBasis`, a root's
auto-axis min/max and margin, a floored `space-*`, `…absolute` on a
`Style`-written box) dies with its field; out of task 7, to plan task 15
(closeout), divergence 52 (`Row`/`Column` default spacing, re-owned from
stage 10 by `LR-EY`, since both stages' exit is "0 px against the prior
stage" and a public default under every default-gap caller's pixels cannot
satisfy both).

**Not done, with owners already assigned above**: no engine file, `Style`
field, legacy registrar, the legacy authority itself or a `Component`
modifier is deleted or changed in meaning (`Component.width`/`height` and
`StyledComponent.width`/`height` stay undeprecated, reconciliation stage 11's,
`LR-ER` item 2). The real-window capture and the demo-layout
human-verification rows record §03 re-opened at stage 6b remain owed to the
human; this stage's own changes to the demo (comments and the recipe's
reordering) are not visually distinguishable from stage 7b's state in any way
the offscreen comparison cannot already certify, so no new look is added to
that ledger.

Docs updated to match this close: `CLAUDE.md`/`AGENTS.md` (counts, the `LR-`
next letter, the record map, the "Sizing modifiers" paragraph and every
example using a deprecated spelling), `docs/record/04-divergences.md` and
`docs/record/05-declared-but-inert.md` (each gains a dated "no row changed"
section explaining why, since neither divergence 48 nor any inert-API row is
touched by the deprecation), `docs/record/README.md`, the plan's task 7 note
(dated, not ticked — stages 9–14 remain), and this repository's top-level
`README.md`.
