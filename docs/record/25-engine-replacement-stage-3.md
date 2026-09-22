# 25 — Engine replacement, stage 3: scrolling and `Component` distribution

**Renumbered from §24 to §25 at merge into `master` (2026-09-22):** the
FreeType rasterizer line (PR #8) was pushed first and keeps §24, so every
`§24` this track wrote was repointed to `§25` and the file renamed. The
FreeType line's own `§24` citations were left alone. Counts re-taken on the
merged tree: see §15 at the end of this file.

Plan task 7, stage 3 of the fourteen in
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1.
Design: `docs/superpowers/specs/2026-09-22-engine-stage-3-design.md`.
Rulings: `LR-BB`…`LR-BJ`, `LR-BK` (critic round 1), `LR-BL`, `LR-BM`, `LR-BN`,
`LR-BO`, `LR-BP` (lanes 1–5) in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md` (the same
decisions doc as stages 1 and 2).
Branch `feat/engine-stage-3` from `57893d0`, worktree
`/Users/maxburger/Developer/MetalUI-stage-3`.

**Status: all five lanes implemented** (§7–§11). Sections 1–6 are the design phase, in
which no file under `Sources/` or `Tests/` changed in any commit. Everything
here was measured on 2026-09-22 (PDT).

---

## 1. Baseline at `57893d0`

| measure | value |
|---|---|
| suite | **1550 tests passed** after 56.481 s, 0 `error:`, no `warning:` besides SwiftPM's `--build-system native` deprecation notice |
| goldens | **97** (`find Tests -name "*.json" \| wc -l`) |
| typecheck guards | **77** — 79 `canTypecheck` hits minus `Tests/MetalUITestSupport/Typecheck.swift`'s declaration and `UnitSafetyTests`' comment hit. Per file: `PhaseSeparationTests` 19, `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `GridCompileGuards` 4, `ContainerCompileGuards` 4, `DecorationCompileGuards` 3, `AXNodeTests` 3, `UnitSafetyTests` 2, `SceneBoundaryCompileGuards` 2, `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2, `LayoutAuthorityCompileGuards` 1 |
| screen | **unlocked**, 09:1x PDT: no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`, `displayActive main: 1`, one 2056×1329 screen at scale 2, `preflightScreenCaptureAccess: true` (`docs/probes/appkit-screen-lock-state.swift`; `IOConsoleLocked` not read, `FR-V`) |

### 1.1 One unattributed issue on the first run, not reproduced

The **first** unfiltered run at this commit printed

```
Test run with 1550 tests in 1 suite failed after 54.393 seconds with 1 issue.
```

The command piped through `tail -30`, so the failing test's name was not kept.
Two later unfiltered runs accounted for every issue they reported:

- the prototype run (§3) reported **15** issues, and 8 + 3 + 2 + 1 + 1 = 15 of
  them belong to five named tests, leaving none unexplained;
- a clean rebuild with the worktree restored printed
  `Test run with 1550 tests in 1 suite passed after 56.481 seconds`.

So the first run's issue did not reproduce. It is recorded rather than
explained: the one environmental difference on record is that **the screen was
unlocked for every run in this session**, which stage 1's and stage 2's runs
were not. **Lesson for the lanes: capture the whole test log, never its tail** —
a single unattributed issue that cannot be named is a worse outcome than a red
test.

**It is attributed or retired in lane 1, before lane 3** (critic round 1
finding 11): lane 3 takes the count of real `Window`s in `ScrollRoutingTests` +
`ScrollIndicatorTests` from 37 to 74, four of the scenarios drive the display
link, and the exit test is built out of them — so an unattributed flake living
there would double in rate and land in the exit criterion. "Recorded rather
than explained" is acceptable for a baseline; it is not acceptable under the
lane that doubles the surface.

**Retired in lane 1** (§7.1): three unfiltered whole-log runs at the baseline
tree and six more in the lane, all `Test run with 1550`/`1553 tests … passed`.
It did not reproduce.

## 2. Probes

### 2.1 Re-run and byte-identical

| probe | lines | result |
|---|---|---|
| `swiftui-stack-algorithms.swift` | 787 | the recorded block was extracted from the header (lines 236–1022, de-indented) and `diff`ed against a fresh `/usr/bin/swift` run: **identical** |
| `swiftui-component-distribution.swift` | **25** | fresh run **identical** to its header, G0–G16. (This row first said 22, and so did the design's §2.1. A fresh `/usr/bin/swift` run emits **25** output lines; `wc -l` of the extracted header block is also 25 and `diff`s clean. Content byte-identical, so nothing substantive moved — but a reader re-running the probe failed on the first number they compared. Critic round 1 finding 10.) |

### 2.2 New: `swiftui-engine-replacement-stage3.swift`

15 lines at the first recording, **18** after critic round 1 added W7–W9 (§6).
Script form run twice, byte-identical; `xcrun swiftc -O` produced the same
lines, exit 0, empty stderr in both forms. Recorded in its own header. The
block below is the first recording; W7–W9 are in §6.

```
--- V: is a ScrollView flexible inside a stack? (host 100x200)
  V0 control VStack{a 60x30; b 60x30}         : outer 100x200 a (20, 66) 60x30 b (20, 104) 60x30
  V1 VStack{a 60x30; ScrollView{c 60x300}}    : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 c (20, 38) 60x300 b none
  V2 control VStack{a 60x30; Color 60 wide}   : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 b none
  V3 VStack{a 60x30; ScrollView{c 60x20}}     : outer 100x200 a (20, 0) 60x30 sv (20, 38) 60x162 c (20, 38) 60x20 b none
  V4 HStack{a 30x60; ScrollView(.h){c 300x60}}: outer 100x200 a (0, 70) 30x60 sv (38, 70) 62x60 c (38, 70) 300x60 b none
  V5 VStack{a 60x30; ScrollView{c 60x300}.fixedSize()}: outer 100x200 a (20, -69) 60x30 sv (20, -31) 60x300 c (20, -31) 60x300 b none
--- W: a flexible or single-axis frame on a multi-member custom view (host 300x100)
  W0 control Pair()                           : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
  W1 Pair().frame(width: 70)                  : outer 300x100 a (96, 45) 30x10 b (164, 45) 50x10
  W2 Pair().frame(height: 40)                 : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
  W3 Pair().frame(maxWidth: .infinity)        : outer 300x100 a (58, 45) 30x10 b (202, 45) 50x10
  W4 Pair().frame(width: 70, height: 40)      : outer 300x100 a (96, 45) 30x10 b (164, 45) 50x10
  W5 Solo().frame(height: 40)                 : outer 300x100 a (135, 45) 30x10 b none
  W6 Pair().frame(maxWidth: .infinity, alignment: .leading): outer 300x100 a (0, 45) 30x10 b (154, 45) 50x10
```

**A bug in the first revision, found by reading the output against the label.**
V5's label said `.fixedSize()` and the arm body did not apply it, so V5 printed
V1's numbers. With the modifier actually applied the answer **inverts**: the
viewport becomes its content's 300 and the stack overflows the host. The header
records the corrected run. (The first revision's header was written before the
arm was run at all, with invented figures, and was replaced wholesale by the
real output — the practice that catches this is "walk every measurement back to
the line it came from in the same pass".)

## 3. Prototype P4

`s3proto-final.patch`, 133 lines, in the session scratchpad; applied, built,
run, restored with `git checkout Sources Tests` and the scratch test deleted;
`git status --short` empty afterwards. What it changed:

- `ScrollView.requestLayout`'s `pass.lowersToProposal` branch lowers (content
  through `lowerLegacyNode` at site `.scrollView`, viewport through
  `requestNativeScrollViewport`, the viewport recorded as the element's item);
- `StyledComponent.requestGroupLayout`'s amend registers a per-member native
  frame and its wrap goes through `lowerLegacyNode`;
- `lowerLegacyLayer` frames each child of a multi-node frame layer and rows
  them at spacing 0;
- `legacyFrameLayerDiagnostics` loses its `frame.multipleNodes` row.

### 3.1 Whole-suite effect

`swift test --build-system native --no-parallel --skip-build`:
**1554 tests (1550 + 4 scratch), 15 issues in 5 tests.** Every one is a
diagnostics expectation this stage owns; **no other test in the suite moved**.

| test | issues | what it saw |
|---|---|---|
| `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` | 8 | the report lost `scrollView.noLowering` in both modal states; three of its thirty rows' lowered rects changed |
| `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` | 3 | `ScrollView` arm `[]` vs `[scrollView.noLowering]`; `Component wrap` `[]` vs `[component.wrap]`; `AMEND-ENTRIES []` vs `[component.amend]` |
| `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` | 2 | the component-amend exit test exited `EXIT_SUCCESS` where `.failure` was required |
| `anItemFieldNoLoweredContainerConsumesIsReportedByName` | 1 | its "legacy `ScrollView`" arm read `[]` vs `[scrollView.noLowering]` |
| `aHiddenFrameLayerIsReportedAsDisplayNone` | 1 | its "two nodes, not hidden" arm read `[]` vs `[modifierLayer.frame.multipleNodes]` |

### 3.2 Scroll arms

`LayoutDifferential.compare`; "agrees" = empty report, no disagreement, and
`scenesEqual`/`hitboxesEqual`/`accessibilityEqual`/`stateSlotsEqual` all true.

| arm | shape | ids | result |
|---|---|---|---|
| A1 | `Box { ScrollView(.vertical) { 3 × 80×40 } }.width(80).height(60)` | 6 | **agrees** |
| A2 | demo spelling: `Box { ScrollView { 3 × 80×40 } }.width(80).flexGrow(1).flexBasis(0).minHeight(0)` in a 120×120 stretching column with a 80×20 sibling | 8 | **agrees** |
| A3 | `Box { ScrollView { 50×30 } }.height(100).alignItems(.stretch)` | 4 | **agrees** |
| A5 | 50×30 content in a 100×100 `Box` | 4 | **agrees** |
| A8 | 160×30 content in an 80×60 vertical viewport | 4 | **agrees** |
| A9 | a `ScrollView` inside a `ScrollView` | 7 | **agrees** |
| A4 | `Box { ScrollView(.horizontal) { 2 × 80×40 } }.width(100).height(50)` | 5 | viewport legacy **(0,0) 160×50** → lowered **(0,0) 100×50**; `scenesEqual` and `hitboxesEqual` **false** |
| A7 | centring `Row` 120×100 over a vertical scroller of two 50×30 | 5 | viewport legacy **(0,20) 50×60** → lowered **(0,0) 50×100**; children legacy (0,20) and (0,50) → lowered (0,0) and (0,30) |
| A10 | stretching column, declared 120×100 | 5 | viewport legacy **(0,0) 120×60** → lowered **(0,0) 120×100** — **the cross axis (120) agrees on both sides** |
| A11 | centring `Column`, 120×100 | 5 | viewport legacy **(35,0) 50×60** → lowered **(35,0) 50×100** — cross (50) agrees |
| A6 | `Box { ScrollView(.horizontal) { Text(long) } }.width(100).height(40)` | 4 | the `Text` legacy **225×40** → lowered **225×16**; `accessibilityEqual` false. **Stage 2's single-child stretch elision (`LR-AC`, X9), not a scroll fact**: the width, which is the scroll-relevant number, agrees at 225 in a 100pt viewport on both sides |

**Reading.** The cross axis never moved in any arm. The scrolling axis moved in
A4, A7, A10 and A11, always from "the content's extent" to "the proposal" —
which is SwiftUI's answer (probe V1–V4) and the reason a scroller scrolls. So
**divergence 54, stated as a cross-axis difference, is not what the lowering
produces**; see `LR-BC`.

**Correction, critic round 1 finding 5.** These arms measure **legacy against
lowered**. Divergence 54 is `ScrollView` against `ProposalScrollView`, and the
lowering **preserves** it: the kernel viewport's own cross answer is
`content.width` (the `ProposalScrollView` side), and a lowered `ScrollView`
reads its parent's 120 in A10 only because it records a `LoweredItem`, so stage
2 wraps it in a stretch item frame and `LoweringState.alias` reports that
frame's rect as the element's. `ProposalScrollView` records none. The first
writing of `LR-BC` said the lowering "closed" 54's cross-axis half; it does not,
and 54 has been moved out of stage 6b's retirement row.

### 3.3 `ScrollContext`

A custom element recording `pass.scrollContext` inside the scroller and again as
a sibling declared after it, rendered under each authority:

```
S3 context legacy:   ["off=0.0 vp=0.0 ax=vertical", "nil"]
S3 context proposal: ["off=0.0 vp=0.0 ax=vertical", "nil"]
```

Identical, the `nil` included. One frame only, so `viewportExtent` is 0 on both
sides — which is why the lane's test drives **two** frames (design 3.5).

### 3.4 Component arms

`Box(.row).width(300).height(40)` unless stated; members 30×10 and 50×10.

| arm | legacy | lowered |
|---|---|---|
| C1 `Pair().width(70)` | 70×10 at (0,0) and (70,0) | 30×10 at **(20,0)**, 50×10 at **(80,0)** |
| C2 `Solo().width(70)` | 70×10 at (0,0) | 30×10 at **(20,0)** |
| C3 `Pair().padding(8)` | — | **agrees**, 4 ids |
| C4 `.padding(4).width(70)` | 30×10 (4,4), 50×10 (74,4) | **(20,4)**, **(80,4)** |
| C5 `.width(70).padding(4)` | 70×10 (4,4) and (82,4) | 30×10 **(24,4)**, 50×10 **(92,4)** |
| C6 `Pair().frame(width:70,height:40)` (host 300×60) | one 70×40 layer, members 26×10 (0,15) and 44×10 (26,15) | a **140×40** row, members 30×10 **(20,15)** and 50×10 **(80,15)** |
| C7 `Pair().height(20)` | 30×20 (0,0), 50×20 (30,0) | 30×10 **(0,5)**, 50×10 **(30,5)** |

The lowered x coordinates match the SwiftUI probes exactly where they are
comparable: C4's 20 is component-distribution G13's 20, C5's 24 is G14's 24, and
C1/C6's "centred in its own 70" is W1/W4 and G7.

### 3.5 The correction the prototype forced

Recording the amend frame's `contentAlignment` as `.center` unconditionally put
C1's members at **y 15** instead of y 0, and C4's at y 15 instead of y 4: the
item frame a parent registers reads `LoweredItem.contentAlignment`, so a
width-only amend was centring its member on the height axis. Making the
alignment **per axis** — `.center`'s factor on a declared axis, 0 on an `auto`
one — restored y 0 and y 4. **The constraint that forced it is the legacy
agreement**: divergence 48 is about the axis the caller declares, and an amend
that also relocates the other axis is a second, undesigned divergence. Ruling
`LR-BG`.

The first writing of this section cited probe **W2** (`Pair().frame(height: 40)`
byte-identical to the W0 control) and **W5** as the SwiftUI evidence. They are
not evidence on their own — see the critic round below, and revision 2's
W7–W9.

### 3.6 `List` inside a lowered scroller

`Box { ScrollView { List(20 rows, rowHeight: 10) { … } } }.width(100).height(100)`:
report `[list.noLowering]` only; 45 ids, 2 agreeing, 3 disagreeing, 40
legacy-only (the rows the legacy side built and the proposal side did not).
The three disagreements are all width 80 → **0**, because the `List` reports and
builds no rows, so the viewport's non-scrolling axis — the content's answer —
is the empty content's 0. **That is stage 4's, not stage 3's.**

**And it is the whole reason design test 3.5 was renamed** (critic round 1
finding 4). This measurement was taken **under diagnostics**, where the `List`
builds zero rows, so "windows against the same context" is vacuous here; and
through a real `Window` it is not measurable at all, because `List` calls
`noteUnlowerable(.list, "noLowering")` before any row (`List.swift:351`) and a
`Window` aborts on that. 3.5 is now
`aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, with a non-`List`
recorder. `List` windowing is checked **only under the legacy authority** this
stage.

### 3.7 The demo, through the exit test

P4 passed `try #require(report.elements == 2036)` (modal off) and 2042 (modal
on) unchanged, and the 6-agreeing / 30-disagreeing and 36-disagreeing counts did
not move. What changed:

- report, modal off: `[list.noLowering, scrollView.noLowering]` → **`[list.noLowering]`**;
- report, modal on: `[stack.position, stack.inset, list.noLowering, scrollView.noLowering]`
  → **`[stack.position, stack.inset, list.noLowering]`**;
- three of the thirty rows (legacy values unchanged):

| row | legacy | lowered before | lowered after |
|---|---|---|---|
| the `ScrollView`'s viewport | (132, 439) 420×0 | (240, 455) 0×0 | (240, 455) 0×**73** |
| the `ScrollView`'s content node | (132, 439) 420×0 | **(0, 0)** 0×0 | **(240, 455)** 0×0 |
| the `List` | (132, 439) 420×14000 | (0, 0) 0×0 | (240, 455) 0×**14000** |

The 73 is the scroller `Box`'s own lowered height, which stage 2's exit table
already carries under cause **R**; it now arrives one level deeper.

## 4. Pixels

**No image was generated in this phase, and the reason is structural rather
than an omission**: the commits of this phase touch `docs/` only — the design,
the rulings, this record and one new probe. `Sources/` and `Tests/` are
byte-identical to `57893d0` (`git status --short` empty after the prototype was
restored; `git diff --name-only 57893d0 HEAD` lists doc paths only). The twelve
`CN-R` images are a function of `Sources/MetalUIDemoContent` and the library, so
they cannot move.

The design fixes the expectation per lane (§8 of the design): twelve images at
the end of **every** lane, controls read non-zero first (light vs dark
1 048 576; default vs modal 1 030 498; default vs animation 210 027; f0 vs f3 0;
preview light vs dark 1 048 576), **0 expected in all twelve**, with lane 1 —
the shared-chrome fold, the only lane editing production paint under both
authorities — the one where a non-zero reading is a finding rather than a
surprise.

Real-window captures are available again: the screen is unlocked (§1).

## 5. For the implementer

- The design's lane order is load-bearing: **lane 1 is a refactor on the
  production path** and must be measured against the twelve images before
  anything else lands on top of it.
- **Lane 3 runs AFTER lane 2, and its red-before is one exit-test arm.** The
  first writing of this section said the opposite — "lane 3's red-before must
  be taken at lane 1's commit … where a proposal-authority window still traps".
  That instruction cannot be carried out: `Window` never sets
  `reportsUnlowerableFields`, so the trap is a `preconditionFailure` that
  **aborts the process**, printing no summary line and no list of which arms
  failed. Lane 1 adds one arm to the existing exit test
  `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` instead;
  lane 2 converts it to an agreement arm. Critic round 1 finding 1.
- Every count in §3 is a prototype's, not an implementation's. Re-derive each
  before writing it into a literal, and record any row that does not reproduce
  as a finding before the expectation is written.
- **Three of the design's mutations were replaced because they could not
  redden anything** (M1f, M2d, M2e). Before banking any mutation in a lane,
  check that the mutant can differ from the original *in the observable the
  test reads* — a consumed `LoweredItem` is skipped by
  `reportUnconsumedLoweredItems`, and two folded implementations move together.

## 6. Critic round 1 (2026-09-22, after `ec83625`)

Twelve findings; dispositions in `LR-BK`. The critic re-ran all three probes
the design leans on and found each byte-identical to its header, confirmed the
worktree clean and the 97 goldens untouched, and located every defect in how
the design mapped those answers onto MetalUI's code — or in mutations and
red-before runs that could not do what they claimed.

**New measurement this round: stage-3 probe revision 2.** Arms W7, W8, W9,
added because W2 and W5 could not discriminate. Run 2026-09-22 (PDT) under
`/usr/bin/swift` twice byte-identical and under `xcrun swiftc -O` identical,
exit 0, empty stderr; the header's recorded block was re-extracted and `diff`ed
clean against the fresh run. 18 lines; the first 15 unchanged.

```
  W0 control Pair()                           : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
  W2 Pair().frame(height: 40)                 : outer 300x100 a (106, 45) 30x10 b (144, 45) 50x10
  W5 Solo().frame(height: 40)                 : outer 300x100 a (135, 45) 30x10 b none
  W7 Pair().frame(height: 40, alignment: .top): outer 300x100 a (106, 30) 30x10 b (144, 30) 50x10
  W8 Pair().frame(height: 40, alignment: .bottom): outer 300x100 a (106, 60) 30x10 b (144, 60) 50x10
  W9 Solo().frame(height: 40, alignment: .top): outer 300x100 a (135, 30) 30x10 b none
```

**Why the new arms were needed.** W2 is byte-identical to the W0 control and W5
puts its member where a bare `Solo()` would. Both outcomes are equally
consistent with "a per-member frame that passes the undeclared axis through"
**and** with "the frame did nothing at all" — the host centres either way
(a 10pt member centred in 100 is y 45; two 40pt frames centred in 100 is y 30
with the member centred in its own 40, also y 45). Reporting that as positive
evidence is practices shape 15. W7/W8 put free space on the **declared** axis,
where the two hypotheses separate: y 30 and y 60 against the control's y 45, so
the frame exists and aligns there; W9 shows the same for one member. With the
frame proved present, W2's and W5's unchanged x then do say the undeclared axis
is passed through at the child's own size.

**And what SwiftUI still cannot say.** `LoweredItem.contentAlignment` is how a
**parent's** item frame places a grown child. SwiftUI has no counterpart: a
frame with an undeclared axis has that axis equal to its child's size, so there
is no free space and its alignment there is unobservable in principle. `LR-BG`'s
per-axis alignment is therefore grounded on the **legacy agreement** it must
preserve (y 0 and y 4 in §3.5), with W2/W5/W7–W9 as the consistency check.

**Read from source, not measured** (each cited by file and line in `LR-BK`):
`Window` never sets `reportsUnlowerableFields`;
`reportUnconsumedLoweredItems` skips consumed records; `StateTable.withState`
always calls its closure, so both `lastScroll` seeds are dead and the two
indicator implementations are line-equivalent; `List` calls
`noteUnlowerable(.list, "noLowering")` before any row; `ProposalScrollView`
never calls `recordLoweredItem`, so `consume` returns `nil` for it and it gets
no stretch item frame — which is why divergence 54 **survives** the lowering;
`lowerLegacyNode` passes `site:` on to `planLegacyItems` as `parentSite:`, which
is what keeps `LoweringSite.scrollView` reachable; `lowerLegacyLayer` plans only
at `children.count == 1` and returns `.first`;
`ProposalScrollView`'s private members are at `:97-170`, not `:94-166`; and
`ScrollView.clamp` is named by five assertions
(`ScrollViewTests.swift:78,79,80,89,97`).

**Shape changes.** Lane order becomes 1 → 2 → 3 → 4 → 5; lanes 2, 4 and 5 each
gain one test (2.2a, 4.6, 5.1a) for a hole no prototype fixture could see; three
mutations are replaced; every lane states a predicted end-of-lane test count
(1553 / 1561 / 1563 / 1569 / 1572 from 1550). No finding is rejected outright,
and the two places where the disposition differs from what the finding asked
for — finding 1's option (b) and finding 9's premise — are named in `LR-BK`.

## 7. Lane 1 — the shared scroll chrome (`LR-BD`, corrections in `LR-BL`)

Four commits on `feat/engine-stage-3`:

| commit | what |
|---|---|
| `f0590d3` | the lane's four tests, written and read before the fold |
| `72762cc` | `ScrollChrome.swift`, and both elements folded onto it |
| `b2d888b` | 1.2's `.hidden` arm strengthened, found by M1d |
| `440fd78` | 1.4 given a second content height, found by M1f |

### 7.1 The baseline flake, retired

Three unfiltered whole-log runs at the baseline tree (`bafcc6a`, whose
`Sources/` and `Tests/` are byte-identical to `57893d0`):
`Test run with 1550 tests in 1 suite passed` after **52.087 s**, **51.817 s**
and **52.674 s**, exit 0, no `error:`, no `warning:` besides SwiftPM's
`--build-system native` deprecation notice. Six further unfiltered runs in the
lane were green as well; the only red runs were the six mutations. **§1.1's
single unattributed issue did not reproduce and is retired**, which is the
condition lane 3 was waiting on (critic round 1 finding 11). Every log in this
lane was kept whole, never tailed.

### 7.2 Red first — and it is honestly "green first"

All four tests are **characterization** and were green on arrival, at 1553
(1550 + 3, the prediction exactly: 1.3 is an arm of an existing test and the
exit-test arm is an arm). That is what `LR-BD`'s amended finding 3 predicts —
before the fold the two implementations were line-equivalent — so the lane's
evidence is §7.4's mutations, not a red run. The one genuinely new red-before
in the lane is **lane 3's**: the third arm on
`aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, a
proposal-authority `Window` over a `ScrollView`, which exits non-zero with
`scrollView.noLowering has no proposal lowering` on `stderr`. Lane 2 retires it.

### 7.3 What folded, and what did not

`Sources/MetalUI/ScrollChrome.swift`: `clamp` (static), `extent`, `delta`,
`indicatorBounds`, `paintIndicator` and both `resolvedOffset` overloads — seven
members, built **computed** from `axis`, `cornerRadius` and
`indicatorVisibility`, so no public type's storage moves and no
`swift package clean` was needed. The three pass-taking members are `@MainActor`
and the four pure ones are not (`LR-BL` item 4). The four load-bearing doc
comments moved with the code: the prepaint overload's overscroll measurement
("twenty −37 events stored 740, seventeen of the twenty dead"),
`paintIndicator`'s `offsetBy: .zero` rationale, the `guard alpha > 0` /
`requestAnotherFrame()` ordering note, and why `.hidden` is checked first.

`ScrollView.clamp` is **deleted**, not forwarded; the five assertions at
`ScrollViewTests.swift:78,79,80,89,97` re-point at `ScrollChrome.clamp`.
`ScrollView.extent` was `internal` and had no caller outside the type, so it
went with the rest (`LR-BL` item 5). Fourteen doc comments across
`ScrollView.swift`, `StateTable.swift`, `Window.swift`, `Hitbox.swift` and four
test files were re-pointed at `ScrollChrome`.

Unchanged, deliberately: the two `resolvedOffset` overloads stay two functions
(`Passes.swift` records why a shared pass protocol must not be invented) — four
copies became two, not one — and `ScrollContext` publication stays
`ScrollView`'s alone (`LR-BF`).

### 7.4 Mutations

Commit first, `cp` the file aside, apply, native build, **full unfiltered**
`swift test --build-system native --no-parallel`, restore from the copy,
`git status --short` empty. Every figure below is the final HEAD's (`440fd78`);
M1a–M1c were re-taken there after 1.2 and 1.4 changed.

| # | mutation | tests reddened (by name) |
|---|---|---|
| **M1a** | the prepaint overload's write-back deleted (the clamp still applied on read) | **8**: `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack` (the required pair), `theTwoScrollElementsShareOneChromeImplementation`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`, `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel`, `aProposalScrollViewClampsAnOffsetPastItsContentEndOnPrepaint`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints`, `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask` |
| **M1b** | the indicator's own clip given `delta(-offset)` instead of `.zero` | **8**: `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`, `theTwoScrollElementsShareOneChromeImplementation`, `theThumbReachesTheEndOfItsTrackAtMaximumOffset`, `theIndicatorIsTheLastPrimitiveInTheScene`, `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`, `theHorizontalIndicatorLiesAlongTheBottomOfItsViewport`, `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack` |
| **M1c** | the 20pt thumb floor removed | **3**: `theTwoScrollElementsShareOneChromeImplementation`, `theThumbIsProportionalAndFlooredAtTwentyPoints`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent` |
| **M1d** | `.hidden` checked after `requestAnotherFrame()` | **2**: `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`. **Before `b2d888b` it reddened only the first** — see below |
| **M1e** | `ScrollState.lastScrollTime`'s default and its init default set to `0` | **4**: `aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame` (**both** arms: `ScrollIndicatorTests.swift:513` and `:515` for the legacy arm, `:549` and `:551` for the `ProposalScrollView` one), `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `aProposalScrollViewsCornerRadiusMasksItsScrollingContent` |
| **M1f** | a private `paintIndicator` copy re-inlined into `ProposalScrollView` with a 30pt thumb floor | **2**: `theTwoScrollElementsShareOneChromeImplementation`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`. **Before `440fd78` it reddened only the second** — see below |

**Two mutations reddened the wrong test first, and both were findings rather
than broken instruments** (`LR-BL` items 2 and 3).

- **M1d** changes no rect at all: the `.hidden` guard still returns before the
  fill wherever it sits, so a rect-count assertion cannot see it. What it
  changes is that a hidden scroller asks for a frame on every tick, holding the
  display link awake — spec §4.4's exit criterion. 1.2's `.hidden` arm now reads
  `Frame.wantsAnotherFrame` on both halves of its differential.
- **M1f**'s 30pt floor is invisible at 1.4's original fixture, because
  `max(20, 100 × (100/200))` and `max(30, …)` are both 50. 1.4 now runs a second
  content height of 1000, where the proportional answer is 10 and the floor is
  what decides the thumb.

Both corrections were made in place; no test was added, and the total stayed at
1553.

### 7.5 Suite, goldens, guards

- `swift build --build-system native --build-tests`: 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice.
- `swift test --build-system native --no-parallel`, unfiltered, at `440fd78`:
  **`Test run with 1553 tests in 1 suite passed after 52.693 seconds`** — the
  design's predicted 1553 exactly.
- Goldens: `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty**;
  `find Tests -name "*.json" | wc -l` still **97**.
- Typecheck guards: **77**, unchanged — the lane adds no public spelling and no
  guard.

### 7.6 Pixels (`CN-R`), and the harness that had to be rebuilt

Record §18's generator (`scratchpad/harness/gen-lib.py`) lived in a session
scratchpad and is gone. The lane rebuilt it from §18's and `CN-R`'s description:
a test file injected into a `git archive` of the commit under test,
`@testable import MetalUIDemoContent`, twelve images through a real `Window`
over `FakePlatformWindow` — eight legacy demo at 1024² (light/dark × f0/f3,
modal light/dark, animation light/dark), two preview at 1024², and the 560²
two-authority chrome pair (`DifferentialRoot(560) { Column { CounterPanel() }.width(560) }`,
one window per authority) — writing raw BGRA and a scene dump per image.

**It is the same instrument, measured rather than assumed.** On an archive of
`57893d0` it reproduces every recorded figure exactly:

| control | recorded | rebuilt harness |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |

**Twelve of twelve read 0 differing pixels against `57893d0`, every scene dump
byte-identical**, taken twice: at the fold's commit `72762cc` and again at the
lane's HEAD `440fd78`. `chrome-legacy` vs `chrome-proposal` reads 0 as well.
This is the lane where a non-zero reading would have been a finding rather than
a surprise, because its edit is on the production path under both authorities.

**The twelve images never paint an indicator, so they cover less of this lane
than that sentence suggests** (verification round, §12, lane 1's issue 1). None
of the twelve scenes is ever scrolled, so `lastScrollTime` is `-.infinity`,
`alpha` is 0 and `ScrollChrome.paintIndicator` returns at its `guard alpha > 0`
before the `pass.fill`. Measured by the verifier, by scanning every scene dump
for the thumb's 3pt cross-axis rect — `grep '^R ' … | awk '{print $3}' | grep -c
'^3\.0x'` reads **0** in `default-light-f0`, `chrome-legacy`, `chrome-proposal`
and `preview-light`. The pixel evidence covers **the clamp, the prepaint
write-back and the content clip only**; the indicator half of the fold rests on
M1b–M1e alone.

The rebuilt harness is in the session scratchpad again and is **not committed**;
the seven numbers above are what tells the next person who rebuilds it that they
got it right. Committing it is deferred to stage 6b (§7.8).

### 7.7 Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate`, run at the end of the lane: **`session CGSSessionScreenIsLocked
= 1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. The screen was unlocked when the design phase measured
it this morning and is locked again now, so **no real-window capture was
taken** — the one the design called load-bearing for this lane. `IOConsoleLocked`
was not read (`FR-V`). The twelve offscreen images stand in, as they did for
stages 1 and 2.

### 7.8 Deferred out of lane 1

| item | why | owner |
|---|---|---|
| committing the `CN-R` harness | it has now been lost once and rebuilt once; the rebuild costs an hour and is only checkable against §7.6's seven numbers | stage 6b, which owns the root switch and needs this comparison most |
| a real-window capture of the fold | the screen locked again between the design phase and the end of the lane | whoever runs the next lane with an unlocked screen |
| a `ProposalScrollView` twin for `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake`'s display-link half | the property is now shared by construction, and 1.2's `wantsAnotherFrame` assertions catch the mutation that would break it; a twin would be a second window test for one shared line | — (judged not worth a test) |
| **rewriting `CLAUDE.md`/`AGENTS.md` lines 472–473**, "`ProposalScrollView`'s clamp and indicator are private copies of `ScrollView`'s — fix both" | this lane **falsifies** that sentence (both are `ScrollChrome` now), and the lane may not edit `CLAUDE.md`; `LR-BD`'s critic amendment deferred only the stale *line-range* citation, not this claim (verification round, §12, lane 1's issue 2) | the Docs phase, then `cp CLAUDE.md AGENTS.md` and `cmp` |

### 7.9 An unpinned sub-clause of the fold

In the shape record §09 uses for "unpinned sub-clauses, found by verifier
mutations that stayed green" — this one did not stay green, but it reddened one
test whose subject is the wrong half:

- **A scroller's axis is now one assignable property, `var chrome`, and
  mis-wiring `ScrollView`'s is caught only by an indicator test.** Verifier
  mutation **V3** — `ScrollChrome(axis: .vertical, …)` hard-coded in
  `ScrollView.chrome` (`ScrollView.swift:245`), so a horizontal scroller
  measures its extent, translates its content and lays out its thumb on the
  vertical axis — reddens exactly **one** test of 1553,
  `theHorizontalIndicatorLiesAlongTheBottomOfItsViewport`.
  `aHorizontalScrollViewMovesOnDeltaXNotDeltaY`
  (`ScrollRoutingTests.swift:284`, parameterised by authority since lane 3)
  survives it: it reads
  `stateTable.peek(region.id, as: ScrollState.self)?.offset` and the region's
  axis and never a painted rect, so **the horizontal content clip's
  `chrome.delta(-offset)` translation is pinned nowhere**. Pre-existing
  thinness; what the fold adds is the single property that concentrates it.
  Closing it is one assertion on the scrolled content rect's x translation in
  that routing test — not taken here, because the lane is closed and the change
  belongs with a test-owning lane (stage 6b, or whoever next edits
  `ScrollRoutingTests`).


## 8. Lane 2 — the `ScrollView` lowering (`LR-BB`, `LR-BC`; corrections in `LR-BM`)

Four commits on `feat/engine-stage-3`:

| commit | what |
|---|---|
| `5380d5d` | the lane's eight tests, written and read red before the lowering |
| `1798d2f` | the lowering, and the four amended pins |
| `512bc02` | arm A2b, found by mutation M2b reddening the wrong tests |
| (this one) | `LR-BM`, the spec's corrections, this section |

### 8.1 Red first, and what each test was red about

`swift test --build-system native --no-parallel --skip-build --filter
'aLoweredScrollView|divergence54Survives'` at lane 1's HEAD: **7 tests, 46
issues** (test 2.3 does not match that filter and was read separately). Every
one of them is a proposal-authority render in which `ScrollView` still reports
`scrollView.noLowering` and stands in as the 0×0 leaf `Frame.unlowerable`
returns.

| test | red lines |
|---|---|
| 2.1 | five arms × (`unlowerable.isEmpty`, `disagreeing.isEmpty`, `scenesEqual`, `hitboxesEqual`, `stateSlotsEqual`), plus A2's 80×110 scroller literal |
| 2.2 | `a7/a11/a10.unlowerable.isEmpty` and the three lowered rects, **and the three LEGACY rects passed** — (0, 20) 50×60, (35, 0) 50×60, (0, 0) 120×60 — so the hand derivation of the hugging side was confirmed before the lowering existed |
| 2.2a | `unlowerableFields.isEmpty` and both scrollers' rects |
| 2.3 | `unlowerable.isEmpty` alone: the legacy 160×50, the disagreement `#require`, `!scenesEqual` and `!hitboxesEqual` all passed |
| 2.4 | `unlowerable.isEmpty` and the lowered text rect; the legacy rect, derived from the shaping cache, passed |
| 2.5 | all four (a) readings and (b)'s record count |
| 2.6 | neither `$anim` slot exists under the proposal authority |
| 2.7 | `unlowerableFields.isEmpty` |

### 8.2 What the lowering is

`ScrollView.requestLayout`'s `pass.lowersToProposal` branch now calls a private
`loweredLayout(_:children:inner:pass:)` instead of
`frame.unlowerable(...)`. It registers the same two nodes in the same order
under the same ids:

- the **content node** through `pass.lowerLegacyNode(contentStyle, declared:
  declaredContent, children: children, site: .scrollView)` with a style carrying
  only `flexDirection` — stage 2's container lowering entire, so the children's
  stretch, grow, margins, gaps and `justifyContent` behave as under any other
  container — and **without `flexShrink: 0`**, which has no kernel counterpart;
- the **viewport** through `pass.frame.requestNativeScrollViewport(child:axis:)`,
  recorded as this element's own `LoweredItem` (`declared: Style()`, the animated
  viewport style, `kind: .leaf`, `contentAlignment: .topLeading`).

`Layout.node` is the viewport and `Layout.contentNode` the content node, as
before, so `prepaint`, `paint`, `registerScrollRegion`, the clip and the
indicator read the same two rects under both authorities. Both `animated(…)`
calls keep their named child ids (`LR-BE`). The content node's record is left
**unconsumed**.

**Every one of the eight tests' literals was green on the first implementation
run**, including 2.7's hand-derived 10 nodes / 11 cache misses / 9 hits / 3
measure calls, and 2.2's, 2.3's and 2.4's lowered rects, which had been written
from prototype P4's table before any of this existed.

### 8.3 The four amended pins

- `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` — lane
  1's transient third arm (a proposal-authority `Window` over a `ScrollView`
  exiting non-zero) is **retired**, as the design said lane 2 would retire it.
  The test keeps its `List` and component-amend arms and its name.
- `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` — the `ScrollView` arm
  moves from the site-level `scrollView.noLowering` to the **field-level**
  `scrollView.flexGrow.weights`, produced by two scroller children with unequal
  grow factors, matching how lanes 2–4 of stage 1 converted `box`, `stack`,
  `text` and `modifierLayer`.
- `anItemFieldNoLoweredContainerConsumesIsReportedByName` — the "legacy
  `ScrollView`" arm becomes an **agreement** arm: `lowerLegacyNode` consumes the
  child's record exactly as a `Row` does, so nothing reports.
- `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` — §8.4.

### 8.4 The demo census, measured against P4's prediction

| what | P4's prediction | lane 2's measurement |
|---|---|---|
| report, modal off | `[list.noLowering]` | **identical** |
| report, modal on | `[stack.position, stack.inset, list.noLowering]` | **identical** |
| ids / agreeing / disagreeing, modal off | 2036 / 6 / 30 | **unchanged, all three** |
| ids / agreeing / disagreeing, modal on | 2042 / 6 / 36 | **unchanged** |
| the viewport | (240, 455) 0×0 → 0×**73** | **identical** |
| the `List` | (0, 0) 0×0 → (240, 455) 0×**14000** | **identical** |
| the `List`'s row `Box` | (0, 0) 0×0 → (240, 455) 0×0 | **identical** |

The 73 is cause **R**'s own 73 — the scroller `Box`'s new height — arriving one
level deeper, which is the check the design asked for before believing the
number. Every width stays 0 because the `List` reports and builds no rows, so
the viewport's non-scrolling axis (its content's answer, `CN-M`) is the empty
content's 0; that half is stage 4's.

**Modal on, two of the three widths read 420 instead**, and neither the modal
nor the lowering is the cause — `LR-BM` item 3: `Deferred` hands its child's
node straight up, so the lowered content node has two children with the modal
on, stage 2's single-child stretch elision stops applying, and both children are
stretched. Recorded as three per-id overrides with the cause named in the test.

### 8.5 Mutations

Commit first, `cp` the file aside, apply, native build, **full unfiltered**
`swift test --build-system native --no-parallel`, restore from the copy,
`git status --short` empty (checked and empty after every one).

| # | mutation | tests reddened (by name) |
|---|---|---|
| **M2a** | the viewport registered as a plain native leaf | **8**: `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs`, `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredScrollViewsContentKeepsItsNaturalExtent`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` |
| **M2b** | the content node through `requestNativeLinearStack` instead of `lowerLegacyNode` | **5**: `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`. **Before arm A2b it reddened only the last four** — see §8.6 |
| **M2c** | the viewport lowered as a `fixedSize` over its content (`pass.frame.requestNativeFixedSize(child: contentNode)` in place of `requestNativeScrollViewport`) | **7**: 2.1, 2.2, 2.2a, 2.3, 2.5, **2.7** and the demo census. *Recorded as 6 by the lane and corrected in the verification round (§12): 2.7's hand-derived node and work counts move when the viewport's node kind changes. More reddening than recorded, not less* |
| **M2d** | `flexShrink: 0` carried onto the lowered content style | **10**: 2.1, 2.2, 2.2a, 2.3, 2.4, 2.5, 2.7, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` and the demo census, whose report becomes `[list.noLowering, scrollView.flexShrink.unconsumed]` — read off the failure, and the entry the omission is observable through |
| **M2e** | the content node registered with `site: .modifierLayer` | **2**: `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| **M2f** = **M2i** | `recordLoweredItem` dropped from the lowered `ScrollView` (the design lists two ids; it is one edit) | **4**: 2.2, 2.2a, 2.5, 2.7 |
| **M2g** | **`loweredLayout`'s two** `animated(…)` calls given the bare `id` | **2**: `aLoweredScrollViewKeepsItsTwoAnimationSlots`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape` (8 issues). *The lane recorded 4; that set is the **whole-file** spelling's, which hits the legacy branch's two byte-identical calls as well (`ScrollView.swift:319/330` and `386/396`) and reddens `aLoweredScrollViewKeepsItsTwoAnimationSlots` (once per authority), `everyRegisteringSiteAnimatesItsStyle` and `theResidentEntrySetStaysBoundedWhileScrolling10kRows` — and **not** 2.1, because mutating both branches keeps the two `StateTable.ids` sets equal and `stateSlotsEqual` stays true (`LayoutDifferential.swift:232`). Corrected in the verification round, §12* |
| **M2h** | the content node registered twice, **as an orphan childless duplicate stack** | **1**: `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork` (node count 10 → 11). *The literal reading — the same `children` array under a second `requestNativeLinearStack` — is **not applicable**: it traps at `LayoutTree.swift:743` (`native layout node … registered under a second parent … MC-G hole 4, ruling CN-L`) and truncates the run with no summary line. Spelled out in the verification round so a re-take does not hit that precondition* |

### 8.6 Three findings, and what each cost

1. **`planLegacyItems` raises exactly one report at `parentSite:`.** The design
   (critic round 1 finding 9) said a scroller child's `alignSelf: .baseline`
   would report `scrollView.alignSelf`. It reports `box.alignSelf.baseline`:
   every per-child entry is raised at `item.site`, and `flexGrow.weights` is the
   only entry raised at the parent's. Found by reading the function the ruling
   cited, while writing test 2.5 (c). `LR-BM` item 1; the rule now lives in
   `planLegacyItems`' own doc comment.
2. **Test 2.3's fixture was measuring `ProbeLeaf`.** It registers a raw native
   leaf and records no `LoweredItem`, so nothing lowered ever stretches it,
   where the legacy content container does. At the original 50pt parent its two
   leaves read 80×50 legacy against 80×40 lowered. The parent is now the leaves'
   own 40, and 2.1's doc records that all five of its arms rest on the same
   property. Found by the first **full** run — the filtered run that preceded it
   did not match this test's name, which is its own small lesson about
   `--filter`.
3. **M2b reddened nothing geometric, which means 2.1 could not see the container
   lowering at all.** Every 2.1 arm's scroll content is fixed-size leaves the
   container lowering is a no-op over, so a bare stack is byte-identical. Arm
   **A2b** gives the content a child declaring `alignSelf(.center)` — 40 wide in
   an 80-wide content column, centred at x 20 by the alignment frame
   `lowerLegacyNode` registers — and M2b now reddens 2.1 too. This is the one
   that would have shipped: `LR-BB`'s central claim was otherwise pinned by no
   rect anywhere in the lane.

### 8.7 Suite, goldens, guards

- `swift build --build-system native --build-tests`: 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice.
- `swift test --build-system native --no-parallel`, unfiltered, at the lane's
  HEAD: **`Test run with 1561 tests in 1 suite passed after 52.863 seconds`** —
  the design's predicted 1561 exactly. Whole logs kept, never tailed.
- Goldens: `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty**;
  `find Tests -name "*.json" | wc -l` still **97**.
- Typecheck guards: **77**, unchanged — **79** `canTypecheck` hits across the 15
  guard files and `Typecheck.swift`, minus that file's declaration and
  `UnitSafetyTests`' comment (the arithmetic is §1's; this paragraph first
  subtracted only one of the two, corrected in the verification round, §12). The
  lane adds no public spelling, so it adds no guard.

### 8.8 Pixels (`CN-R`), and the harness rebuilt a second time

`LR-BL` item 6's warning came true immediately: lane 1's rebuilt generator lived
in that session's scratchpad and was gone. It was rebuilt again from record
§18's and §7.6's description — a test file injected into a `git archive` of the
commit under test, `@testable import MetalUIDemoContent`, twelve images through
a real `Window` over `FakePlatformWindow`, raw BGRA plus a scene dump each.

**It reproduces all eight control figures**, which is what makes it the same
instrument:

| control | recorded | this rebuild |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |

**Twelve of twelve read 0 differing pixels** against `57893d0` at `512bc02`, and
every scene dump is byte-identical. Expected by construction — lanes 2–5 touch
only the proposal-authority branch of a legacy element, which no production
frame takes until stage 6b — and taken anyway, because "by construction" has
been wrong before.

The harness is **still not committed**; §10's deferral stands, and it has now
cost two rebuilds.

### 8.9 Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at the end of the lane: **`session CGSSessionScreenIsLocked =
1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. The screen was locked, exactly as at the end of lane 1,
so **no real-window capture was taken**. `IOConsoleLocked` was not read
(`FR-V`).

### 8.10 Deferred out of lane 2

| item | why | owner |
|---|---|---|
| committing the `CN-R` harness | lost and rebuilt twice now; §8.8's eight numbers are all that certify a rebuild | stage 6b |
| a real-window capture | screen locked at the end of both lanes so far | whoever runs a lane with an unlocked screen |
| the demo's remaining scroll-subtree width disagreement (0 vs 420, and 420 vs 420 with the modal on) | it is the `List` reporting, not the `ScrollView` | stage 4 |
| `ProposalScrollView` publishing a `ScrollContext`; its animation | `LR-BF`, `LR-BJ` — unchanged by this lane | stage 11 / task 10 |
| divergence 54's retirement | 2.2a now pins the surviving difference as a literal, as `LR-BC` (amended) asked | stage 11 / task 10 |


## 9. Lane 3 — the scroll suites under both authorities (`LR-BI`; corrections in `LR-BN`)

The stage's exit criterion. Two commits on `feat/engine-stage-3`:

| commit | what |
|---|---|
| `5fb562b` | the roll call (3.4) and `ScrollAuthorityCoverage`, read **red** before the parameterisation |
| `a1b8ff3` | the parameterisation, the two probe types re-spelled, the fixture cross axes, and 3.5 |
| (this one) | `LR-BN`, the spec's corrections, this section |

### 9.1 Red first, and it is a real red this time

Unlike lanes 1 and 2, lane 3 opens with a genuine red-before that does not
truncate anything: `everyScrollScenarioRanUnderBothLayoutAuthorities` written
against the 34 hand-derived names, with nothing recording coverage yet.

```
Test everyScrollScenarioRanUnderBothLayoutAuthorities() recorded an issue at
ScrollViewTests.swift:265:9: Expectation failed: missing.isEmpty
  these scenarios recorded no coverage: ["aDeferredScrollViewTakesTheWheel…", … 34 names …]
Test run with 1562 tests in 1 suite failed after 51.398 seconds with 1 issue.
```

The design's other red-before — lane 1's exit-test arm, a proposal-authority
`Window` over a `ScrollView` exiting non-zero — was retired by lane 2 and is not
re-taken here.

### 9.2 The census, and why it is 34 and not 37

`ScrollViewTests` (the file the design added to this lane without a census)
**declares no custom element type**: no `requestNode`, no `requestLeaf`, nothing
to re-spell. Three of its seven tests —
`theOffsetClampsToTheScrollableRange`, `contentShorterThanTheViewportDoesNotScroll`,
`aStoredOffsetPastTheEndIsClampedWhenItIsRead` — are one static
`ScrollChrome.clamp` call with three `Double`s each. Parameterising them would
add an argument the body never reads, so the two cases would run identical
assertions and neither could fail differently from the other. They stay as they
are; the hand-derived count is **34** (16 + 14 + 4), and 3.4 requires it.

### 9.3 What was re-spelled, and what had to change in the fixtures

- **`ScrollContextRecorder` (5 call sites) and `HitboxProbe` (2)** take
  `ProbeLeaf`'s shape — `pass.lowersToProposal ? requestNativeLeaf : requestLeaf`
  — with their declared `Style` replaced by a `width`/`height` pair so the two
  arms cannot drift. §4.2's census counted these as 9 legacy registrations.
- **`makeFakeWindow`, `ScrollIndicatorTests.fullyRendered` and
  `ScrollViewTests.laidOut`** take a `layoutAuthority`. Neither bare-`Frame`
  helper sets `reportsUnlowerableFields`: they fail the way a production frame
  does. `makeFakeWindow` writes the authority **only when it differs**, so the
  1561 existing call sites reach `drawFrameIfNeeded` through exactly the states
  they did before (a write dirties the window even when it changes nothing).
- **Seven fixtures declare a cross axis they used to leave `.auto`** — the one
  thing the design did not foresee (`LR-BN` item 3). Measured at 120×100:
  `ScrollView(.vertical) { Box(style: fixedHeight(200)) }` registers `(0, 0)
  120×100` under the legacy authority and `(60, 0) **0×100**` under the proposal
  one, because the kernel viewport's cross answer is its content's (`CN-M`) and
  a single child is exempt from the stretch item frame (`LR-AC`). That is stage
  2's ruled divergence, pinned by lane 2's test 2.4. Declaring the cross axis
  moved **no legacy number** — the stretch already produced these values, which
  is what all 34 unchanged legacy arms say.
- 3.5 uses a **horizontal** scroller for the same reason in reverse: a vertical
  one in a bounded wrapper measures 200 under the legacy engine (the viewport
  hugs its content and overflows) and 100 under the proposal authority, which is
  `LR-BC` and test 2.2's subject.

### 9.4 The exit test's shape, and the two claims it could not make

`LR-BI` asked for a counter. Swift Testing does not specify test order, so a
counter read by a test that runs first reads zero and passes; and `Test.all`,
which would have let the check read the *declared* parameterisation, does not
exist in this toolchain (measured: `type 'Test' has no member 'all'`, Swift 6.4
`swiftlang-6.4.0.33.1`). The claim is split (`LR-BN` item 1):

- `ScrollAuthorityCoverage.record` verifies the whole set when the last expected
  name first arrives — order-independent, fires exactly once per unfiltered run,
  skipping the name it is called with (a test's argument cases run back to back,
  measured, so every *other* name is complete by then).
- `everyScrollScenarioRanUnderBothLayoutAuthorities` holds the literals (34, and
  `authorities == allCases`) and reads what has been recorded. **Ordering
  measured, not assumed**: a file's tests run in source order and the files in
  path order — `ScrollIndicatorTests` → `ScrollRoutingTests` → `ScrollViewTests`,
  identical across two runs — so it is declared at the end of the last of the
  three, and if that changes it fails naming what it had not seen.

The first writing of `record` flagged the *current* name too, and the run
reported `aScrollViewWithNoCornerRadiusClipsSquare ran under [.legacy]` on a
healthy tree — found by the first full run, fixed in the same commit.

### 9.5 Mutations

Commit first, `cp` the file aside, apply, native build, **full unfiltered**
`swift test --build-system native --no-parallel`, restore from the copy,
`git status --short` empty (checked and empty after every one). Taken at
`a1b8ff3`.

| # | mutation | tests reddened (by name) |
|---|---|---|
| **M3a** | `registerScrollRegion` given the content node's rect | **6** (8 issues): `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove` (**both** arms), `aDeferredScrollViewNestedInAnotherEscapesItsClipForHitTesting`, `aLegacyScrollViewTakesItsCrossAxisFromItsParentWhereAProposalScrollViewTakesItsContents`, `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows`, `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` |
| **M3b** | the bounds alias dropped in `Frame.bounds(of:)` | **34** (202 issues), **none of them a scroll scenario** — see §9.6 |
| **M3c** | `ScrollAuthorityCoverage.authorities` reduced to `[.legacy]` | **2** (34 issues): `everyScrollScenarioRanUnderBothLayoutAuthorities` (the `authorities == allCases` require), `aScrollViewWithNoCornerRadiusClipsSquare` (33 issues from `record`'s whole-set check) |
| **M3d** | `withScrollContext` moved after the content build | **15**: `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, and `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`, `nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext` each under **both** authorities, plus 11 `List`/accessibility tests |
| **M3e** | the prepaint overload's `viewportExtent` write removed | **13**: `aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout` (both authorities), plus 11 `List`/accessibility tests |
| **M2a** re-taken | the viewport registered as a plain native leaf | **31** (77 issues), where lane 2 read **8**. The 23 new names include 21 of the 34 parameterised scenarios — `aWheelEventInsideARegionScrollsIt`, `theThumbIsProportionalAndFlooredAtTwentyPoints`, `theContentNodeOverflowsTheViewport`, `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt` among them. **This is the lane's headline** |
| **M2d** re-taken | `flexShrink: 0` carried onto the lowered content style | **aborts the run** — see §9.6 |
| **M1c** re-taken | the 20pt thumb floor removed | **3**: `theThumbIsProportionalAndFlooredAtTwentyPoints` under **both** authorities (lane 1 had one arm), `theTwoScrollElementsShareOneChromeImplementation`, `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent` |

### 9.6 Two findings

**1. M3b is not lane-3 evidence, and the design said it would be.** The bounds
alias is load-bearing for a scroller whose *lowered parent* stretches or grows
it; not one fixture in the two scroll suites is in that position — they are
window roots or single children. M3b reddens 34 tests, all of them stage 2's and
lane 2's, including the two that do pin the claim
(`aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel`,
`theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`). The lane owes
no new test for it; the spec's row is corrected rather than a test added, because
a scroll fixture built to see the alias would be a copy of lane 2's.

**2. An `…unconsumed` regression now truncates the suite.** M2d used to produce
ten red tests under diagnostics. At this HEAD the first proposal-authority
`Window` holding a `ScrollView` is test **#1251**,
`aScrollContextSurvivesALoweredViewportAcrossTwoFrames`, and a production frame
traps:

```
MetalUI/Frame.swift:1536: Fatal error: MetalUI: scrollView.flexShrink.unconsumed
has no proposal lowering (plan task 7, stage 3); a tree containing it cannot run
under the proposal layout authority.
```

Lane 2's ten tests had already recorded their issues by then, so the mutation's
evidence is intact; the summary line is not. **This is the trade `LR-BI`'s
amendment took deliberately**, and it is now a standing property of the suite.
The obvious mitigation — a per-fixture diagnostics pre-flight, as
`WindowPair.init` runs — was **not** applied, and the reason as first written
was broader than the measured fact. Corrected in the verification round (§12):
**exactly four of the 34 scenarios construct a `Seen` box**, all in
`ScrollRoutingTests` —
`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`,
`rawOffsetPublishedDuringRequestLayoutCanExceedTheClampedRange`,
`nestedScrollViewsInnermostWinsAndPoppingRestoresTheOuterContext` (two boxes)
and `aSiblingAfterAScrollViewSeesNoScrollContext` (measured: `awk
'/^func |^@Test/{last=$0} /Seen\(\)/{print NR": "last}'`). For those four, a
second render would add a phantom entry to every `Seen` and break the tests the
pre-flight was protecting. `HitboxProbe` (`:864`, `:902`) is stateless and
captures nothing, and **the remaining 30 scenarios are eligible** — so stage 6b
inherits a four-fixture problem, not an all-or-nothing one.

### 9.7 Suite, goldens, guards

- `swift build --build-system native --build-tests`: 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice.
- `swift test --build-system native --no-parallel`, unfiltered, at `a1b8ff3`:
  **`Test run with 1563 tests in 1 suite passed after 52.875 seconds`** — the
  design's predicted 1563 exactly. Whole logs kept, never tailed. No
  unattributed issue appeared in any of the lane's green runs (§7.1's retirement
  holds).
- Goldens: `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty**;
  `find Tests -name "*.json" | wc -l` still **97**.
- Typecheck guards: **77** — **79** `canTypecheck` hits minus
  `Tests/MetalUITestSupport/Typecheck.swift`'s declaration **and**
  `UnitSafetyTests`' comment, the same arithmetic as §1's baseline. (This
  paragraph first read "78 hits minus `UnitSafetyTests`' comment", which lands
  on 77 by subtracting one of the two; a reader re-deriving it computes 78 and
  concludes the count moved. Corrected in the verification round, §12 — the same
  class of defect as critic round 1's finding 10.) The lane adds no public
  spelling.
- The one `Sources/` change is `CaseIterable` on the internal `LayoutAuthority`.

### 9.8 Pixels (`CN-R`), and the harness rebuilt a third time

Rebuilt again from §7.6's description (it is still uncommitted; §10's deferral
now carries three rebuilds). **It reproduces all eight control figures** on an
archive of `57893d0`:

| control | recorded | this rebuild |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |

**Twelve of twelve read 0 differing pixels** against `57893d0` at `a1b8ff3`, and
every scene dump is byte-identical. Expected by construction — the lane's only
`Sources/` change is a protocol conformance on an internal enum — and taken
anyway.

### 9.9 Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at the end of the lane: **`session CGSSessionScreenIsLocked =
1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. Locked, exactly as at the end of lanes 1 and 2, so
**no real-window capture was taken**. `IOConsoleLocked` was not read (`FR-V`).

### 9.10 Deferred out of lane 3

| item | why | owner |
|---|---|---|
| committing the `CN-R` harness | rebuilt three times now; §9.8's eight numbers are all that certify a rebuild | stage 6b |
| a real-window capture | the screen has been locked at the end of all three lanes | whoever runs a lane with an unlocked screen |
| turning an `…unconsumed` trap back into a named failure in a scroll fixture | §9.6 finding 2: the pre-flight `WindowPair` uses would double-record every shared `Seen` box | stage 6b, which switches the root and owns what production traps on |
| `List` windowing under the proposal authority | it traps through a `Window` and builds zero rows under diagnostics | stage 4 |

## 10. Lane 4 — `Component` amend and wrap (`LR-BG`; corrections in `LR-BO`)

Commits: `7f07b2a` (tests, red), `801bb36` (the lowering), `9e217ee` (arm C3a,
after M4b), and this one (docs). Branch `feat/engine-stage-3`, on top of lane
3's `116bab6`.

### 10.1 Red first

Six tests written against stage-2 API, run before any `Sources/` change:

```
Test run with 6 tests in 0 suites failed after 0.043 seconds with 34 issues.
  aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt            5 issues
  aComponentsPaddingLowersAsAnOrdinaryOneChildContainer                      4 issues
  aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares                      6 issues
  theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities 6 issues
  chainedComponentAmendsComposeTheSameWayUnderBothAuthorities                7 issues
  anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned                   6 issues
```

Every issue is one of two shapes: `…unlowerable.isEmpty → false` with
`[component.amend]` or `[component.wrap]`, or `r.loweredBounds[id] == lowered`
against whatever the reported 0×0 leaf left behind. **No `legacy:` assertion
failed in any of the six** — the legacy half of every divergence pin was green
before the lowering existed, which is what makes each a pin rather than a guess.

**One fixture defect the red run found**, before it could have mattered: 4.6's
three arms were one component with a builder `switch` over an enum, and every id
read `nil`. A builder `switch` is an `EitherGroup`, and its branch does not take
the component's slot 0. Three structs instead.

### 10.2 What the lowering is

- `ComponentModifierOp.amend` carries a `Size<Dimension>`, not a
  `@Sendable (inout Style) -> Void`. `Component.width`/`.height` and
  `StyledComponent`'s three build it through two file-private helpers.
- **Legacy branch unchanged in effect**: it writes the axes the patch declares
  and leaves an `.auto` axis alone — "not named", not "reset" — so
  `.width(p).height(q)` does not undo itself. That guard is new; the old closure
  could not have this bug because each closure wrote one field.
- **Lowered branch**: `LayoutPass.loweredComponentFrame(_:_:)` consumes the
  member's `LoweredItem`, plans it (`planLegacyItems`, `parentKind: .stack`,
  `parentSite: .component`), registers the planned wrappers and one
  `requestNativeFrame` with the patch's declared axes, and records the frame
  with `kind: .frameLayer`. `componentFrameAlignment` is the per-axis rule;
  `componentFrameStyle` is the declared style it plans against — a
  `display: .stack` whose `justifyItems`/`alignItems` are non-stretching on
  every axis, so the frame aligns and never stretches. **Only "non-nil and
  non-stretching" is load-bearing there; the per-axis spelling is cosmetic**
  (verification round, §12): deleting both assignments reddens four tests
  (verifier mutation **Vi**), but replacing both ternaries with a constant
  `.center` *and* dropping `display` reddens nothing (**Vk**) —
  `alignsByStretching` and `stretches` are false for `.start`, `.flexStart` and
  `.center` alike, and `parentKind: .stack` is passed explicitly, so this
  style's `display` is never read. The per-axis alignment lives entirely in
  `componentFrameAlignment`; the helper's doc comment now says so, in the change
  that recorded this.
- **`.wrap`** lowers through `lowerLegacyNode(style, declared: style,
  children: [current], site: .component)`.

### 10.3 The prototype's arms, re-measured

**All seven reproduced on the first run, literal for literal**, with the
lowered rects as the design predicted them. The table is the design's §2.3 with
the lane's own numbers in it:

| arm | shape | legacy | lowered |
|---|---|---|---|
| C1 | `Pair().width(70)` | (0, 0, 70, 10), (70, 0, 70, 10) | (**20**, 0, 30, 10), (**80**, 0, 50, 10) |
| C2 | `Solo().width(70)` | (0, 0, 70, 10) | (**20**, 0, 30, 10) |
| C3 | `Pair().padding(8)` | (8, 8, 30, 10), (54, 8, 50, 10) | **identical** — agrees in every observation |
| C3a | `MarginSolo().padding(8)`, the member declaring `margin(4)` | (12, 12, 30, 10) | **identical** |
| C4 | `.padding(4).width(70)` | (4, 4, 30, 10), (74, 4, 50, 10) | (**20**, 4, 30, 10), (**80**, 4, 50, 10) |
| C5 | `.width(70).padding(4)` | (4, 4, 70, 10), (82, 4, 70, 10) | (**24**, 4, 30, 10), (**92**, 4, 50, 10) |
| C7 | `Pair().height(20)` | (0, 0, 30, **20**), (30, 0, 50, **20**) | (0, **5**, 30, 10), (30, **5**, 50, 10) |
| control | `.width(70).height(20)` | (0, 0, 70, 20), (70, 0, 70, 20) | (**20**, **5**, 30, 10), (**80**, **5**, 50, 10) |

Two arms the design did not have:

- `.width(70).width(90)` — legacy 90 wide at x 0 and 90 (`OM-E`, the later
  assignment wins); lowered two nested frames, members 30 and 50 at x **30** and
  **110**. **Both read the same outer 180**, measured through a 5×5 sibling
  written after the component, whose x is the only way to see an outer size the
  amend frames never report as elements.
- the `minWidth(40)` arm of 4.6 — legacy (0, 0, 70, 10), lowered (**15**, 0,
  **40**, 10): the member's `auto` width with a 40pt minimum, planned into the
  item frame W and centred in its own 70pt frame.

### 10.4 Four corrections and one dead mutation (`LR-BO`)

1. **`flexGrow` and `margin` on a member are consumed and DROPPED**, not
   "applied": `parentKind: .stack` is what "exactly as `lowerLegacyLayer`'s
   single-node arm does" means, and a stack parent ignores them (`LR-AZ`). Kept
   as `.stack`; the alternative is deferred to 6b with its reason.
2. **Site `component` has no reachable report left.** Both ops lower; an
   amend's record is `.frameLayer` (skipped by the unconsumed report) and both
   ops plan exactly one child, so neither can raise `flexGrow.weights`. The two
   `Component` arms of `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`
   invert to assert absence.
3. **M4f's `…unconsumed` entries name the MEMBER's site.** Measured:
   `[box.flexGrow.unconsumed]`, `[box.margin.unconsumed]`,
   `[box.minSize.unconsumed]` — not `component.*` as the design's 4.6 row said.
4. **Two fixtures could not see their subject** — 4.6 needed the `minWidth` arm
   for M4g, and 4.2 needed C3a for M4b (§10.5).

### 10.5 Mutations

Protocol: commit first, `cp` both source files aside, apply, native build, full
unfiltered `swift test --build-system native --no-parallel`, restore from the
copy, `git status --short` empty. Every run read `Test run with 1569 tests`.

| mutation | what it changes | tests it reddens (issues) |
|---|---|---|
| **M4a** | one frame around the whole group rather than one per member | all six lane-4 tests (19) |
| **M4b** | the wrap a bare `requestNativePadding`, not `lowerLegacyNode` | **over C3 alone: NOTHING, 1569 green.** With C3a: `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` (3) |
| **M4c** | `componentFrameAlignment` returns `.center` unconditionally | 4.1, 4.3, 4.4, 4.5, 4.6 (12) |
| **M4d** | `ops` applied in reverse | `aModifierOnAComponentAppliesInTheOrderItIsWritten`, `everyRegisteringSiteAnimatesItsStyle`, 4.4, 4.5 (20) |
| **M4e** | every amend collapsed into one patch, the earlier axis winning | `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities` (6) |
| **M4f** | the member's record read, not consumed | `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned` (3) |
| **M4g** | consumed, never planned | `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned` (**1** — the `minWidth` arm alone) |
| **M4a′** | the amend's lowered branch put back to `noteUnlowerable` | `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`, and all six lane-4 tests (33) |

**M4b is the lane's one dead mutation, and its death is the finding.** Over C3
the two spellings are byte-identical, because fixed 30×10 leaves declare no item
field and make `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized`
no-ops. This is exactly `LR-BM`'s M2b, one lane later, in the same shape — which
says the lesson from lane 2 did not transfer to lane 4's fixture design, and
that a "the lowering is the container lowering" claim needs a fixture whose
child gives the container something to do. C3a's member declares a `margin`, and
the legacy wrapper's content box is that member's **margin** box.

**M4g reddening exactly one issue is the third arm earning its place.** With
only the design's `flexGrow` and `margin` arms it reddens nothing at all.

### 10.6 Suite, goldens, guards, clean

| measure | value |
|---|---|
| suite | **1569 tests**, passed after 52.478 s — the design's predicted total, to the test |
| `error:` / `warning:` | 0 / only SwiftPM's `--build-system native` deprecation notice |
| goldens | `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty**; `find Tests -name "*.json" \| wc -l` = **97** |
| typecheck guards | **77** (**79** `canTypecheck` hits minus `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment — §1's arithmetic; the lane's own line subtracted one of the two and is corrected in §12), per-file counts unchanged from the baseline; the lane adds none |
| `swift package clean` | **a measurement, not an assertion** (critic round 1 finding 12): the incremental build over `ComponentModifierOp.amend`'s payload change was already correct at 1569, and a `swift package clean` + full rebuild + unfiltered run read **the same 1569**. The reasoning ("an `Array` is one word either way") held and was still checked |

### 10.7 Pixels (`CN-R`)

The lane-3 harness was still in this session's scratchpad and was reused rather
than rebuilt, and it was re-validated before being believed: on the archive of
`57893d0` it reproduces **all eight** control figures (light vs dark 1 048 576,
default vs modal 1 030 498, default vs animation 210 027, f0 vs f3 0, preview
light vs dark 1 048 576, distinct `default-light-f0` 544, distinct
`chrome-legacy` 216, `chrome-legacy` vs `chrome-proposal` 0), and the same eight
at this lane's HEAD.

**Twelve of twelve read 0 differing pixels against `57893d0`, every scene dump
byte-identical**: `animation-{light,dark}`, `chrome-{legacy,proposal}`,
`default-{light,dark}-{f0,f3}`, `modal-{light,dark}`, `preview-{light,dark}`.

Expected, and the reason is worth writing down rather than assuming: production
runs the legacy authority, the legacy amend and wrap are byte-for-byte what they
were, and the demo's one `Component` (`PreviewToggle`) carries no modifier at
all — so no `ComponentModifierOp` is constructed anywhere in the twelve images.

### 10.8 Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at the end of the lane: **`session CGSSessionScreenIsLocked =
1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. Locked, as at the end of lanes 1, 2 and 3, so **no
real-window capture was taken**. `IOConsoleLocked` was not read (`FR-V`).

### 10.9 Probes

Both probes this lane rests on were **re-run today** and every recorded line
reproduced verbatim against the header:
`swiftui-engine-replacement-stage3.swift` (18 lines, arms W1/W2/W4/W5/W7–W9) and
`swiftui-component-distribution.swift` (25 lines, arms G7/G8/G13/G14). No new
probe was needed: lane 4 asks no question of SwiftUI that those two do not
already answer, and `LR-BG`'s one unanswerable question — how a frame aligns on
an axis with no free space — is grounded on the legacy agreement instead.

### 10.10 Deferred out of lane 4

| item | why | owner |
|---|---|---|
| an amend frame applying a member's `flexGrow`/`margin` rather than dropping them | needs a non-arbitrary main axis for a one-child frame, and SwiftUI has no `flexGrow` to probe | stage 6b |
| a reachable diagnostic at site `component` | nothing can raise one after this lane, and adding a check would be a 6b trap rather than a divergence | whoever first needs one |
| divergence 48's retirement | answered here under the proposal authority, still wrong on purpose under the legacy one | stage 6b |
| framed members staying one flex item | `TB-M`'s associated type | stage 11 |
| committing the `CN-R` harness | still uncommitted; it survived from lane 3 only because this lane ran in the same session | stage 6b |
| a real-window capture | the screen has been locked at the end of all four lanes | whoever runs a lane with an unlocked screen |

## 11. Lane 5 — a frame layer over several member nodes (`LR-BH`; corrections in `LR-BP`)

Commits: `d47989b` (tests, red), `4401713` (the lowering), and this one (docs).
Branch `feat/engine-stage-3`, on top of lane 4's `275d8fb`.

### 11.1 Red first

Three tests written against lane 4's tree, run before any `Sources/` change,
plus the re-spelled control arm in `LoweringStackAndLayerTests.swift`:

```
Test run with 3 tests in 0 suites failed after 0.017 seconds with 8 issues.
  aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem  5 issues
  aFrameOverSeveralMembersStillPlansEachMembersItemFields                         3 issues
  aFrameOverOneMemberIsUnchanged                                                   0 (characterization)

Test run with 1 test in 0 suites failed after 0.007 seconds with 1 issue.
  aHiddenFrameLayerIsReportedAsDisplayNone
    two nodes, not hidden: [modifierLayer.frame.multipleNodes]
```

Every lowered rect read `(0, 0) 0×0` — the leaf `report(fields)` leaves behind
after `modifierLayer.frame.multipleNodes`. **No `legacy:` assertion failed and
neither `try #require(…elements == 5)` failed**, so the legacy half of both
divergence pins and the id derivation were right before the lowering existed.
The id derivation is the part that could have been wrong and was worth
checking in the red run: `.frame(…)` on a component is **not** a distributing
op like `.width`, it is the `Component` side door that returns a
`ModifiedElement`, so the layer takes the enclosing `Box`'s cursor slot and the
component sits one level deeper — `child(Box, 0)` → `child(layer, 0)` →
members. Lane 4's fixtures have the component at `child(Box, 0)`.

### 11.2 What the lowering is

- `lowerLegacyLayer`'s frame arm builds the `requestNativeFrame` call in a local
  `framed(_:)` and applies it **per child node**. Over one node (or none) the
  result is that one frame, exactly as before — no row wrapper. Over several it
  is `requestNativeLinearStack(children: items.map(framed), axis: .horizontal,
  spacing: 0, alignment: spec.alignment)`.
- `planLegacyItems(received, parent: declared, parentKind: .stack, parentSite:
  .modifierLayer, fields: &fields)` now runs for **every** child count, and
  `registerLegacyItems(children, plans)` is rowed in full rather than reduced to
  `.first`.
- `legacyFrameLayerDiagnostics` loses its `frame.multipleNodes` row and keeps
  two checks; `childCount` survives for the `lowered(_:childCount:)` comparison,
  which reads it to know whether an unmodified layer's display is `.stack` (one
  node) or a flex row (several).
- The recorded item is unchanged: `kind: .frameLayer`, `contentAlignment:
  spec.alignment`, site `modifierLayer`.

### 11.3 The prototype's arm, re-measured

**C6 reproduced on the first run, literal for literal.**

| | legacy | lowered |
|---|---|---|
| the frame layer | (0, 0) **70**×40 | (0, 0) **140**×40 |
| member a (30×10) | (0, **15**) **26**×10 | (**20**, 15) **30**×10 |
| member b (50×10) | (**26**, 15) **44**×10 | (**80**, 15) **50**×10 |

The legacy 26/44 are the 10pt overflow shared 30/80 : 50/80 by the flex row
inside the 70pt frame; y 15 on both sides is the members' 10pt height centred in
the 40. SwiftUI (stage-3 probe **W1**/**W4**, re-run today and byte-identical to
its header, 18 lines) reads a at **96** and b at **164** in a 300pt host — a
**148**pt pair, which is this 140 plus the enclosing `HStack`'s own 8pt spacing.

Two arms the design did not have:

- **the node counts.** Two per-member frames and one row are **+3** native nodes
  over `Box { Pair() }`; one member is **+1** over `Box { Solo() }`.
- **5.1a's field pair**, in an 80×40 frame so the legacy row does not shrink:
  a member declaring `width(30).margin(4)` reads legacy (5, 15) 30×10 and
  lowered (**25**, 15) 30×10 — the margin **dropped**; a member declaring
  `height(10).minWidth(40)` reads legacy (39, 15) **40**×10 and lowered
  (**100**, 15) **40**×10 — the floor carried into the item frame W.

### 11.4 Four corrections (`LR-BP`)

1. **The margin in 5.1a is dropped, so M5e cannot see it.** `parentKind: .stack`
   drops a member's `margin`, `flexGrow`, `flexShrink`, `flexBasis` and
   `alignSelf` with or without the planning (`LR-AZ`, `LR-BO` item 1), so the
   design's "both rects lose the margin and the floor" is wrong by one half.
   Measured: M5e reddens exactly one assertion. Same wrong sentence as lane 4's,
   about the two frames that share the same parent kind.
2. **M5d has no subject after the row is deleted**, and restated ("moved below
   the style comparison") it is stage 1's **M4i**. The re-spelled control arm is
   kept, its value inverted: as an empty expectation it is the only
   discriminator in that test for "`display.none` is checked first **and
   alone**".
3. **M5a cannot redden the demo exit test**, and §7's list was wrong to name it.
   `demoContent()` contains no `.frame` at all; `DemoContent.swift`'s only two
   `.frame(` sites are in `nativeLayoutPreviewContent()` and are proposal
   `ModifiedContent`. `LR-BN` item 5's M3b again.
4. **No rect can see the row.** M5c wrapped a lone frame in a one-child row and
   moved **no rect in the suite**; the node counts are the whole pin.

### 11.5 Mutations

Protocol: commit first, `cp Sources/MetalUI/LegacyLowering.swift` aside, apply,
native build, full unfiltered `swift test --build-system native --no-parallel`,
restore from the copy, `git status --short` empty after each (checked and empty
every time). Every run read `Test run with 1572 tests`.

| mutation | what it changes | tests it reddens (issues) |
|---|---|---|
| **M5a** | the row's `spacing: 0` → `nil` (the platform default 8) | 5.1 (2: the layer 148 not 140, b at 88 not 80), 5.1a (1). **Not** the demo exit test — §11.4 item 3 |
| **M5b** | `framed` applied to the first member only | 5.1 (3), 5.1a (1) |
| **M5c** | `items.count > 1` → `>= 1` (a lone frame rowed on its own) | `aFrameOverOneMemberIsUnchanged` (**1** — the node count alone; no rect anywhere moved) |
| **M5d** | `display.none` moved below the style comparison (= stage 1's M4i) | `aHiddenFrameLayerIsReportedAsDisplayNone` (4: the hidden arms read `[modifierLayer.style]`) |
| **M5e** | the planning skipped for `count > 1` | `aFrameOverSeveralMembersStillPlansEachMembersItemFields` (**1** — b reads (120, 15) **0**×10; a is unchanged) |
| **M5f** | `registerLegacyItems(children, plans)` reduced to `.first` | 5.1 (3), 5.1a (1) |
| **M5g** (verifier's, verification round §12) | the row's `alignment: spec.alignment` hard-coded to `.center` | **nothing — 1572 green.** Not an equivalent mutant: over uneven member heights (30×10, 50×30) under `.frame(width: 70, alignment:)` a scratch differential reads y 0/0 for `.top`, 25/15 for `.center`, 50/30 for `.bottom`. Both committed tests fix a height (`.frame(width: 70/80, height: 40)`), which makes every per-member frame the same height and the row's cross alignment invisible; probe arms W7/W8 are equal-height frames too, and SwiftUI has no row here at all (the framed members are siblings of the enclosing stack), so `spec.alignment` on the row is an unprobed MetalUI choice. Deferred, §11.10 |

**Every one of the six the lane took reddened its named test.** The two that reddened exactly
one issue are the informative ones: M5c says the row is geometrically invisible
at one child, and M5e says only the `minSize` half of 5.1a discriminates.

### 11.6 Suite, goldens, guards, clean

| measure | value |
|---|---|
| suite | **1572 tests**, passed after 52.245 s at the lowering's commit and 51.844 s on the restored tree after the mutations — the design's predicted total, to the test |
| `error:` / `warning:` | 0 / only SwiftPM's `--build-system native` deprecation notice |
| goldens | `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty**; `find Tests -name "*.json" \| wc -l` = **97** |
| typecheck guards | **77** (79 `canTypecheck` hits minus `UnitSafetyTests`' comment and `Typecheck.swift`'s declaration), per-file counts unchanged; the lane adds none |
| `swift package clean` | **not required and checked anyway**: the lane changes only function bodies inside one `internal extension LayoutPass`, no stored property and no public type's layout. A `swift package clean`, full rebuild and unfiltered run read the same **1572** (52.811 s) |

### 11.7 Pixels (`CN-R`)

The lane-4 harness (`cnr/CNRPixels.swift`) was still in this session's
scratchpad and was reused rather than rebuilt — and re-validated before being
believed. On a fresh `git archive` of `57893d0` it reproduces **all eight**
control figures, and the same eight at this lane's HEAD:

| control | recorded | base archive | lane HEAD |
|---|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** | **210 027** |
| f0 vs f3 (light) | 0 | **0** | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** | **1 048 576** |
| distinct, `default-light-f0` | 544 | **544** | **544** |
| distinct, `chrome-legacy` | 216 | **216** | **216** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** | **0** |

**Twelve of twelve read 0 differing pixels against `57893d0`, every scene dump
byte-identical**: `animation-{light,dark}`, `chrome-{legacy,proposal}`,
`default-{light,dark}-{f0,f3}`, `modal-{light,dark}`, `preview-{light,dark}`.

Expected, and for a reason this lane can state exactly rather than by
construction: production runs the legacy authority, and `demoContent()` has no
`.frame` at all (§11.4 item 3), so the edited arm is not merely unreached — the
shape it lowers does not exist in any of the twelve images.

### 11.8 Screen lock and captures

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at the end of the lane: **`session CGSSessionScreenIsLocked =
1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. Locked, as at the end of lanes 1–4, so **no real-window
capture was taken** in any lane of this stage. `IOConsoleLocked` was not read
(`FR-V`).

### 11.9 Probes

`docs/probes/swiftui-engine-replacement-stage3.swift` re-run today under
`/usr/bin/swift`: exit 0, 18 lines, **byte-identical to its recorded header**,
arms W1/W4 (and W0 as the control) being the ones this lane rests on. No new
probe was needed: lane 5 asks SwiftUI nothing that group W does not already
answer, and the one question it cannot answer — whether the per-member frames
should be siblings of the enclosing stack, as SwiftUI's are — is not this
stage's to close (`TB-M`, stage 11).

### 11.10 Deferred out of lane 5

| item | why | owner |
|---|---|---|
| a per-member frame applying its member's `flexGrow`/`margin` rather than dropping them | the multi-node arm has an axis its row supplies, but no reason to differ from the one-node arm, and SwiftUI has no `flexGrow` to probe | stage 6b |
| framed members staying **one** flex item where SwiftUI's stay siblings (the 140 vs 148) | `ElementGroup`'s associated type (`TB-M`) | stage 11 |
| **the per-member row's cross-axis `alignment: spec.alignment`** — unpinned (verifier mutation M5g stays green) and unprobed | both committed tests declare a height, so every per-member frame is the same height and the row's alignment cannot move a rect; and SwiftUI has no row to probe, which makes the choice between `spec.alignment` and the enclosing container's alignment part of the siblings question | stage 11, with `TB-M` and the siblings question — or one uneven-height, height-free arm on 5.1 by whoever next edits `LoweringComponentTests` |
| divergence 56's retirement | answered here under the proposal authority, still wrong on purpose under the legacy one | stage 6b |
| a demo shape that exercises a frame over a multi-member component | there is none, so the corpus test cannot cover this lane; its two tests are the whole coverage | whoever adds one, or 6b |
| committing the `CN-R` harness | survived from lane 4 only because this lane ran in the same session | stage 6b |
| a real-window capture | the screen has been locked at the end of all five lanes | whoever runs with an unlocked screen |

---

## 12. Verification round (2026-09-22, PDT) — this commit

Every lane's verifier returned **`ok: true`**. Between them they raised
**thirteen minor issues** — three on lane 1, four on lane 2, three on lane 3,
two on lane 4 and one on lane 5 — none blocking, and **not one a defect in a
landed behaviour**: eight were attribution or wording in this record and the
rulings, three were claims that are true but unpinned or not decisive, one was a
source doc comment broader than the code, and one is an obligation on the Docs
phase that nothing had written down. All thirteen are dispositioned below.

**Nothing executable changed in this round.** The three edits to `Sources/` are
doc comments: `ScrollView.loweredLayout`'s "unconsumed" paragraph, and
`loweredComponentFrame`'s and `componentFrameStyle`'s in `LegacyLowering.swift`.
The suite is re-run after them, and that run is this stage's final figure.

### 12.1 What the verifiers reproduced independently

This is the part worth keeping: four of the five verifiers did not read the
lane's numbers, they re-took them.

- **Lane 1's verifier ran 16 full unfiltered runs** — the baseline HEAD at 1553
  green, `f0590d3` at 1553 green, and 14 mutation runs — and **every issue in
  every one was attributable to a named test**. No unattributed flake appeared
  in any of them, which is a second, larger corroboration of §7.1's retirement
  of §1.1's single unexplained issue.
- **Lane 2's verifier rebuilt from scratch**: `git archive HEAD` into a clean
  tree with `.build` removed, full build, unfiltered run — `Test run with 1561
  tests in 1 suite passed after 53.577 seconds`, matching the incremental
  53.025 s run. It also **replayed the red-first run** at the test-only commit
  `5380d5d`: all 8 lane tests red, **49** issues — the lane's reported 46 from
  its filtered run **plus test 2.3's 3**, which that filter did not match (§8.6
  finding 2's own lesson, confirmed from the other side) — and 2.1's 26 = 5 arms
  × 5 assertions + A2's literal, exactly as §8.1 records.
- **Lane 2's verifier re-took the twelve `CN-R` images with its own harness**, a
  `VPixels.swift` it wrote itself and injected into `git archive` trees of
  `57893d0` and HEAD. All eight controls reproduced exactly at both trees, and
  **12 of 12 read 0 differing pixels with every scene dump byte-identical**.
  That is the strongest form this comparison has taken in three stages: the
  instrument was written twice, independently, and agrees.
- **Lane 1's verifier regenerated all twelve images too**, with the scratchpad
  harness, controls first (1 048 576 / 1 030 498 / 210 027 / 0 / 1 048 576, 544
  and 216 distinct, chrome pair 0): 12 of 12 at **0**.
- **Lane 3's verifier re-took M3a, M3b, M3c, M3d, M3e and M1c** and reproduced
  **each lane figure to the test and to the issue count**, and lanes 4 and 5's
  verifiers reproduced their lanes' tables the same way (lane 4's M4c 12 issues,
  M4d 20, M4e 6, M4f 3, M4g 1; lane 5's six rows).
- **The probe was re-run by two verifiers** under `/usr/bin/swift`: exit 0, 18
  lines, empty stderr, byte-identical to its header.

### 12.2 The verifiers' own mutations

Twenty mutations the lanes did not take. None found a defect; four stayed green
and three of those are now recorded as gaps rather than assumed equivalent.

| lane | mutation | reddened |
|---|---|---|
| 1 | **V2** — `ScrollChrome.extent` reads the wrong axis | **33** across routing, the indicator, `List` windowing, accessibility frames and clipping — the fold's instrument is alive |
| 1 | **V6** — the prepaint overload stops writing `$0.viewportExtent` (the `ScrollContext` / `List`-windowing hazard the brief names) | **12**, including `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows`, `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` — `List` windowing still depends on the published context, measured rather than argued |
| 1 | **V7** — a private `paintIndicator` re-inlined into **`ScrollView`** with a 30pt floor (M1f's drift in the other direction, which the lane never tested) | **2**: `theTwoScrollElementsShareOneChromeImplementation`, `theThumbIsProportionalAndFlooredAtTwentyPoints` |
| 1 | **V4** / **V5** — `ProposalScrollView.chrome` built with `cornerRadius: 0` / `indicatorVisibility: .automatic` | **1** each (`aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent`) |
| 1 | **V9** — `ScrollView.chrome` built with `indicatorVisibility: .automatic` | **2**: `hiddenEmitsNoIndicatorRect`, `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake` |
| 1 | **V3** — `ScrollView.chrome` built with a hard-coded `axis: .vertical` | **1** only — §7.9, the lane's one named gap |
| 1 | **V1** — the `PaintPass` overload's read clamp removed (`return stored`) | **nothing**. Argued equivalent **by reading, not measured**: the prepaint overload writes the clamped value back, so in any fixture that prepaints before painting the stored offset is already clamped and the paint-side clamp is belt and braces. Banked as an unpinned sub-clause, not as an equivalence proof |
| 3 | **V1** — the lowered viewport's axis inverted (`requestNativeScrollViewport(child:axis:)` given the other axis), touching **only** the proposal branch | **29 tests / 56 issues**, of which **20 of the 34 parameterised scenarios, every one on the `.proposal` arm and none on `.legacy`**. This is the exit criterion answering the question it exists for: a lowering defect invisible to the legacy arm is caught by 20 scenarios written years before the lowering |
| 3 | **V4** — one scenario's `ScrollAuthorityCoverage.record` call deleted | `everyScrollScenarioRanUnderBothLayoutAuthorities`, failing at `ScrollViewTests.swift:283` with `these scenarios recorded no coverage: ["theIndicatorIsTheLastPrimitiveInTheScene"]` — **it names the offender** |
| 3 | **V5** — one scenario's `@Test(arguments:)` reduced to `[.legacy]` (one arm dropped quietly, rather than the whole list as M3c does) | both halves of the split claim fire: `everyScrollScenarioRanUnderBothLayoutAuthorities` and `record`'s order-independent whole-set check in `aScrollViewWithNoCornerRadiusClipsSquare` |
| 4 | **M4a variant** — the ops applied once to the whole group instead of per member | 4 of the 6 lane-4 tests (a single-member component is unaffected by construction, so it reaches less than the lane's own M4a) |
| 4 | **M4a′ re-taken with BOTH ops reverted** to `noteUnlowerable` | 8 tests / 41 issues, both inverted arms naming themselves (`AMEND-ENTRIES [component.amend]`, `[component.wrap]`) — the lane mutated the amend alone and read 33 |
| 4 | **Vh** — the legacy branch's two `if patch.<axis> != .auto` guards replaced by `style.size = patch` | **8 tests / 21 issues**, including `widthAndHeightComposeOnAChainedModifier` — the new "an `.auto` axis means *not named*" semantics the payload change introduced is pinned |
| 4 | **Vi** — `componentFrameStyle`'s `justifyItems`/`alignItems` assignments deleted | **4 tests / 6 issues** — the two fields are load-bearing |
| 4 | **Vj** — the amend frame's record written with `kind: .stack` | **nothing** — §12.3 item 4 |
| 4 | **Vk** — `componentFrameStyle`'s `display = .stack` removed **and** both ternaries made constant `.center` | **nothing** — §12.3 item 5 |
| 5 | **M5g** — the per-member row's `alignment: spec.alignment` hard-coded to `.center` | **nothing**, and the mutant is **not** equivalent (§11.5's row has the uneven-height measurement) — §12.3 item 6 |
| 2 | **M2c, M2g, M2h re-taken** with the spelling written out | the three attribution corrections of §12.3 items 1–3 |

### 12.3 The thirteen, and what each cost

**Lane 1 (3).**

1. **The twelve images never paint an indicator.** §7.6 presented them as this
   lane's pixel evidence, and the verifier measured that no scene in any of the
   twelve contains the thumb's 3pt rect — none of them is ever scrolled, so
   `alpha` is 0 and `paintIndicator` returns at its guard. The pixel evidence
   covers the clamp, the write-back and the content clip; **the indicator half
   rests on M1b–M1e alone**. Recorded in §7.6.
2. **The lane falsified a sentence in `CLAUDE.md` and nothing said so.** Lines
   472–473, "`ProposalScrollView`'s clamp and indicator are private copies of
   `ScrollView`'s — fix both", is now false. `LR-BD`'s critic amendment deferred
   only the stale *line-range* citation, so the Docs phase had nothing pointing
   at the claim itself. Added as a deferral row in §7.8 and named in "For the
   integrator"; practices' "when a claim is refuted, grep for everywhere it was
   copied".
3. **The fold concentrates a scroller's axis into one assignable property** and
   only an indicator test catches `ScrollView`'s (V3). Recorded as §7.9, a named
   unpinned sub-clause, with the one assertion that would close it.

**Lane 2 (4).**

1. **M2g's row was the union of two spellings.** Scoped to `loweredLayout`'s two
   `animated(…)` calls it reddens **2**; applied whole-file it also hits the
   legacy branch's byte-identical pair and reddens 3 — a different set, and
   **not** 2.1, because mutating both branches keeps the two `StateTable.ids`
   sets equal. §8.5's row now names the branch and the set.
2. **M2c under-counted by one** (2.7's hand-derived node and work counts move
   when the viewport's kind changes): 7, not 6. §8.5 corrected, with the exact
   `requestNativeFixedSize` spelling.
3. **M2h is not applicable as literally written**: the same children under a
   second parent traps at `LayoutTree.swift:743` (`CN-L`'s one node, one slot)
   and truncates the run. The observation stands for the **orphan childless**
   duplicate; §8.5 says so.
4. **`loweredLayout`'s doc comment overstated which style carries the
   diagnostic.** `Frame.reportUnconsumedLoweredItems` reads `item.declared`
   only, never `item.animated` — a field added to `contentStyle` alone would
   vanish silently, which is why M2d has to be applied to `declaredContent` to
   be observable. The comment now names the declared style and `LR-AS`.

**Lane 3 (3).**

1. **§9.7's guard arithmetic was wrong** (78 hits less one, landing on the right
   77 by luck): it is **79** hits less `Typecheck.swift`'s declaration **and**
   `UnitSafetyTests`' comment, as §1 states. Corrected in §9.7 — **and in §8.7
   and §10.6, which carried the same slip**, because staleness is systematic.
2. **The pre-flight deferral was scoped larger than the measurement.** Exactly
   **four** of the 34 scenarios construct a `Seen` box; `HitboxProbe` is
   stateless; **30 are eligible** for a `WindowPair`-style diagnostics
   pre-flight. §9.6 and `LR-BN` item 5 now say four by name, so stage 6b
   inherits the true scope.
3. **The exit test's ordering dependence is not in `CLAUDE.md`'s CI list.** It
   is disclosed and ruled (`LR-BN` items 1 and 6) and it fails loudly naming
   what it had not seen, but on a runner whose file order differs it is a
   spurious red, and `swift test --filter everyScrollScenario` hard-fails. No
   code change; handed to the Docs phase in "For the integrator".

**Lane 4 (2).**

4. **`.frameLayer` is not today's decisive reason site `component` cannot
   report.** Vj — the amend frame's record as `kind: .stack` — left 1569 green,
   and the verifier traced why by reading: `componentFrameStyle` carries no
   field `reportUnconsumedLoweredItems` names, so the record stays silent even
   unconsumed and even as a `.stack`. `.frameLayer` is the guard that *takes
   over* when that stops being true. Written into `LR-BO` item 2 and
   `loweredComponentFrame`'s doc, with the obligation it creates: whoever puts a
   bound into `componentFrameStyle` owes a pin in the same change.
5. **`componentFrameStyle`'s per-axis ternaries are cosmetic.** Vk (constant
   `.center`, `display` dropped) left 1569 green; Vi (both fields deleted)
   reddens 4. So "non-nil and non-stretching" is the whole content of those two
   lines, and the per-axis alignment lives in `componentFrameAlignment`.
   Recorded in §10.2 and in the helper's doc rather than collapsed, because the
   spelling documents intent; the doc now warns that mutating it moves no rect.

**Lane 5 (1).**

6. **M5g stays green and the mutant is not equivalent.** The per-member row's
   `alignment: spec.alignment` is pinned by nothing: both committed tests
   declare a height, so every per-member frame is the same height and the row's
   cross alignment cannot move a rect; the probe's W7/W8 are equal-height frames
   too, and SwiftUI has no row here at all. The verifier's scratch differential
   over uneven members (30×10, 50×30) reads y 0/0, 25/15, 50/30 for
   `.top`/`.center`/`.bottom`, so the argument is settled by measurement.
   Recorded as a green mutation in §11.5 and as a deferral in §11.10, owned by
   stage 11 with the siblings question — or by one uneven-height arm from
   whoever next edits `LoweringComponentTests`.

### 12.4 Suite, goldens, guards after the round

- `swift build --build-system native --build-tests`: 0 `error:`, the only
  `warning:` SwiftPM's `--build-system native` deprecation notice.
- Unfiltered `swift test --build-system native --no-parallel`:
  **`Test run with 1572 tests in 1 suite passed after 52.055 seconds`**, exit 0,
  whole log kept.
- Goldens **97**; `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'`
  **empty**.
- Typecheck guards **77** (79 `canTypecheck` hits less `Typecheck.swift`'s
  declaration and `UnitSafetyTests`' comment) — **none added by any lane**, so
  "mutate each new guard red once" is vacuous for this stage.
- `@available(*, deprecated` hits **34**, unchanged.
- Screen: `docs/probes/appkit-screen-lock-state.swift` at the round —
  **`session CGSSessionScreenIsLocked = 1`**, `displayAsleep main: 1`,
  `displayActive main: 0`. **No real-window capture was taken at any point in
  this stage.** `IOConsoleLocked` was never read (`FR-V`).

---

## What landed, in one place

Branch `feat/engine-stage-3` from `57893d0`, 2026-09-22 (PDT), twenty-four
commits:

| commit | what |
|---|---|
| `ca7272a`, `ec83625`, `bafcc6a` | the stage-3 design, its ruling range, and critic round 1 applied (`LR-BB`…`LR-BK`, probe arms W7–W9) |
| `f0590d3`, `72762cc`, `b2d888b`, `440fd78`, `5996637` | **lane 1** — the shared scroll chrome (`ScrollChrome.swift`), two tests strengthened by their own mutations, `LR-BL` and record §7 |
| `5380d5d`, `1798d2f`, `512bc02`, `5c06966` | **lane 2** — the `ScrollView` lowering, arm A2b, `LR-BM` and record §8 |
| `5fb562b`, `a1b8ff3`, `116bab6` | **lane 3** — the exit test: both scroll suites under both authorities, `LR-BN` and record §9 |
| `7f07b2a`, `801bb36`, `9e217ee`, `0a34f3a`, `275d8fb` | **lane 4** — `Component` amend and wrap, arm C3a, `LR-BO` and record §10 |
| `d47989b`, `4401713`, `3a4346b` | **lane 5** — a frame layer over several member nodes, `LR-BP` and record §11 |
| (this commit) | the verification round: three doc comments, the record's corrections, record §12 and this closing half |

**The behaviour.** Under the **proposal authority only** — production still runs
the legacy authority until stage 6b — scrolling and `Component` distribution
lower onto the kernel:

- **`ScrollView` lowers** (`LR-BB`): its content node through `lowerLegacyNode`
  at site `scrollView`, so stage 2's whole container lowering applies to the
  scroll content; its viewport through `requestNativeScrollViewport`, recorded
  as the element's own `LoweredItem`, so a lowered parent stretches or grows it
  through stage 2's item frame and rect alias. `flexShrink: 0` is deliberately
  not carried (the kernel has no freeze loop), and the content record is left
  unconsumed so a later stage's field on the **declared** content style reports
  rather than vanishing.
- **The lowered viewport fills its proposal on the scrolling axis** where the
  legacy viewport hugs its content (`LR-BC`) — SwiftUI's answer, probe V1–V4,
  and the reason a scroller scrolls. The cross axis agrees. **Divergence 54
  survives**, and is now pinned as a literal
  (`divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`): only a
  `ScrollView` records an item, so only it gets the stretch frame that reports
  the parent's cross size.
- **One clamp and one indicator** (`LR-BD`): `ScrollChrome`, a computed struct
  both elements build per frame, holding `clamp`, `extent`, `delta`,
  `indicatorBounds`, `paintIndicator` and both `resolvedOffset` overloads.
  `ProposalScrollView`'s private copies are **gone**, and
  `ScrollView.clamp`/`.extent` with them. This is the stage's only edit that
  runs in production under both authorities.
- **`$anim-content` and `$anim-viewport` survive the lowering unchanged**
  (`LR-BE`), and **`ScrollContext` publication is untouched** (`LR-BF`) — same
  ids, same `withScrollContext` bracket before the content build, same
  `viewportExtent` write-back from prepaint, which is what `List` windows
  against (pinned by test 3.5 across two frames, and by the verifier's V6).
- **A `Component` amend is a per-member native frame** (`LR-BG`):
  `ComponentModifierOp.amend` carries a `Size<Dimension>` rather than a closure,
  the legacy branch writes only the axes the patch declares, and the lowered
  branch consumes and plans the member's record, then frames it, **aligned per
  axis** — `.center` on a declared axis, 0 on an `auto` one, which is what keeps
  the undeclared axis where the legacy engine puts it. `.wrap` lowers through
  `lowerLegacyNode` as an ordinary one-child container.
- **A `.frame` layer over several member nodes is a row of per-member frames**
  (`LR-BH`), at spacing 0, with every member's item fields planned;
  `frame.multipleNodes` leaves the diagnostics.
- **The exit criterion is met** (`LR-BI`): `ScrollRoutingTests`,
  `ScrollIndicatorTests` and `ScrollViewTests` run **34 scenarios under both
  authorities**, their two custom element types (`ScrollContextRecorder`,
  `HitboxProbe`, 9 registrations) re-spelled as native probe leaves, with a roll
  call that fails naming any scenario that stopped participating. Inverting the
  lowered viewport's axis reddens 20 of the 34 — on the `.proposal` arm only.

**What did not move**, deliberately and measured: production pixels (twelve
offscreen images, 0, at every lane and twice more in the verification round),
the 97 goldens, the seven reserved identity slots, wheel routing and the single
hitbox list, the overscroll clamp's behaviour, `List` windowing, hit testing,
accessibility records and the disabled gate.

## Tests and guards, per file

`@Test` functions, current count and the delta against `57893d0`. The deltas sum
to **+22**, exactly the suite delta 1550 → **1572**: a parameterised test counts
as **one** entry in the summary line, so lane 3's 34 scenarios × 2 authorities
add nothing to the total.

| file | now | delta | lane |
|---|---|---|---|
| `Tests/MetalUITests/LoweringScrollTests.swift` (new) | 12 | **+12** | 1 (3), 2 (8), 3 (3.5) |
| `Tests/MetalUITests/LoweringComponentTests.swift` (new) | 9 | **+9** | 4 (6), 5 (3) |
| `Tests/MetalUITests/ScrollViewTests.swift` | 8 | **+1** | 3 — `everyScrollScenarioRanUnderBothLayoutAuthorities`, the roll call |
| `Tests/MetalUITests/ScrollAuthorityCoverage.swift` (new) | 0 | 0 | 3 — the recorder and the 34 hand-derived names; no `@Test` of its own |
| `Tests/MetalUITests/ScrollIndicatorTests.swift` | 14 | 0 | 1, 3 — arms strengthened, all 14 parameterised by authority |
| `Tests/MetalUITests/ScrollRoutingTests.swift` | 16 | 0 | 3 — all 16 parameterised; the two probe types re-spelled |
| `Tests/MetalUITests/LayoutAuthorityTests.swift` | 11 | 0 | 1, 2, 4 — the exit-test arm added then retired, the site inventory inverted at `component`, the `ScrollView` arm moved to `flexGrow.weights` |
| `Tests/MetalUITests/LoweringCorpusTests.swift` | 3 | 0 | 2 — the demo census's report and three rows |
| `Tests/MetalUITests/LoweringStackAndLayerTests.swift` | 12 | 0 | 5 — `aHiddenFrameLayerIsReportedAsDisplayNone`'s control arm re-spelled |
| `Tests/MetalUITests/LoweringItemTests.swift` | 28 | 0 | 2 — `anItemFieldNoLoweredContainerConsumesIsReportedByName`'s `ScrollView` arm becomes an agreement arm |
| `Tests/MetalUITests/ComponentTests.swift`, `Fakes.swift`, `AbsoluteOverlayTests.swift`, `StateTests.swift` | — | 0 | 3, 4 — the authority parameter on the fakes, doc re-points |

By lane: **+3** (1), **+8** (2), **+2** (3), **+6** (4), **+3** (5), **0**
(verification round).

**Guards: 77, unchanged — this stage added none**, and per-file counts are
`57893d0`'s exactly (`PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
`EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6,
`ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `GridCompileGuards`
4, `ContainerCompileGuards` 4, `DecorationCompileGuards` 3, `AXNodeTests` 3,
`UnitSafetyTests` 2, `SceneBoundaryCompileGuards` 2,
`ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
`LayoutAuthorityCompileGuards` 1). Nothing in stage 3 narrows an access level or
adds a spelling that must not compile: `ScrollChrome` is internal, so is
`ComponentModifierOp`, and the authority's own guard already covers the seam.

## Probes

`docs/probes/swiftui-engine-replacement-stage3.swift`, **revision 2**, **18
lines** of recorded output in its header. Groups: **V** — is a `ScrollView`
flexible inside a stack (V0–V5, V5 under `.fixedSize()`); **W** — a flexible or
single-axis frame on a multi-member custom view (W0–W6, plus W7–W9 from critic
round 1).

- Recorded 2026-09-22 by the design session (revision 1, 15 lines); revision 2
  adds W7–W9, because W2 and W5 were byte-identical to their control and
  therefore consistent with "the frame did nothing" (practices shape 15).
- **V5 was wrong in the first revision** — its label said `.fixedSize()` and its
  body did not apply it, so it printed V1's numbers; with the modifier applied
  the answer inverts. Found by reading the output against the label, in the same
  pass that took it.
- **Re-run before its tests by lanes 2, 3, 4 and 5 and by two verifiers**, under
  `/usr/bin/swift` and (design phase) `xcrun swiftc -O`: exit 0, empty stderr,
  byte-identical to the header every time. No arm has ever moved.
- `swiftui-component-distribution.swift` (**25** lines, G0–G16) and
  `swiftui-stack-algorithms.swift` (787 lines) were re-run and diffed clean.
  The component probe's line count was recorded as 22 in the design and is 25;
  critic round 1 finding 10, and the reason §12.3's guard-arithmetic finding is
  treated as the same class of defect.
- **The one question in this stage SwiftUI cannot answer** is named as such:
  how a frame aligns on an axis with no free space (`LoweredItem.contentAlignment`
  has no SwiftUI counterpart). `LR-BG`'s per-axis rule is grounded on the legacy
  agreement it must preserve, with W2/W5/W7–W9 as the consistency check.

## Red runs, in one place

Full unfiltered runs unless noted. Lanes 1 and 4/5's characterization arms are
recorded honestly as green-on-arrival where they were.

| lane | commit | run | red |
|---|---|---|---|
| 1 | `f0590d3` | 1553 | **none — all four tests are characterization and were green on arrival**, which is what `LR-BD` predicted (the two implementations were line-equivalent before the fold). The lane's evidence is its six mutations. Its one genuine red-before is the transient exit-test arm (a proposal-authority `Window` over a `ScrollView` exiting non-zero with `scrollView.noLowering`), which lane 2 retired |
| 2 | `5380d5d` | 8 tests red; filtered 7 / 46 issues at the time, **49 across all 8** when the verifier replayed it unfiltered | exactly the eight lane-2 tests |
| 3 | `5fb562b` | 1562, 1 issue | `everyScrollScenarioRanUnderBothLayoutAuthorities`, naming all 34 scenarios as having recorded no coverage |
| 4 | `7f07b2a` | 6 tests, 34 issues | exactly the six lane-4 tests; **no `legacy:` assertion failed in any of them** |
| 5 | `d47989b` | 3 tests, 8 issues, plus the re-spelled control arm (1) | the two new pins; `aFrameOverOneMemberIsUnchanged` is characterization, and neither `try #require(…elements == 5)` failed |

## Verifier verdicts, in one place

| lane | verdict | minors |
|---|---|---|
| 1 | `ok: true` | 3 — the twelve images paint no indicator; the falsified `CLAUDE.md` sentence with no owner; the axis pinned only by an indicator test (V3) |
| 2 | `ok: true` | 4 — M2g's union of two spellings, M2c's under-count, M2h not applicable as written, the doc comment's unqualified "a field a later stage puts on it" |
| 3 | `ok: true` | 3 — §9.7's guard arithmetic, the pre-flight deferral scoped larger than measured, the exit test's order dependence missing from CI's list |
| 4 | `ok: true` | 2 — `.frameLayer` cited as decisive when it is latent (Vj), the cosmetic per-axis ternaries (Vk) |
| 5 | `ok: true` | 1 — M5g green and the row's alignment unpinned |

All thirteen are dispositioned in §12.3: eleven applied in this commit, one
(lane 3's CI row) handed to the Docs phase with the text it should carry, and
one (lane 1's `CLAUDE.md` sentence) recorded as a deferral pointing at the same
phase.

## Mutations that stayed green, and what has no mutation

- **M4b over C3 alone** (lane 4) — the `.wrap` as a bare `requestNativePadding`.
  The **finding**: fixed 30×10 leaves declare no item field, so
  `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` are all
  no-ops and the two spellings are byte-identical. Closed by arm **C3a**, whose
  member declares a `margin`; M4b reddens there.
- **M2b before arm A2b** (lane 2) — the same shape one lane earlier, over fixed
  leaves in 2.1. Closed by **A2b**, whose content child declares
  `alignSelf(.center)`. **The lesson did not transfer from lane 2 to lane 4**,
  which is the stage's most repeatable finding.
- **M1d and M1f before their tests changed** (lane 1) — a `.hidden` guard that
  moves no rect, and a 30pt floor invisible where `max(20, 50)` and
  `max(30, 50)` agree. Both closed in place: 1.2 reads `wantsAnotherFrame`, 1.4
  gained a second content height.
- **Vj** (lane 4) — the amend frame recorded as `kind: .stack`. Green, and
  traced by reading to a narrower true statement (§12.3 item 4); the kind is a
  latent guard, with an obligation attached rather than a pin.
- **Vk** (lane 4) — constant `.center` and no `display`. Green and **argued
  equivalent by reading**, not banked as a gap; recorded so nobody mutates the
  ternary expecting a rect.
- **M5g** (lane 5) — the row's cross alignment. Green, **not equivalent**
  (measured on uneven members), deferred with an owner.
- **V1** (lane 1) — the `PaintPass` overload's read clamp. Green; argued
  equivalent by reading only, recorded as an unpinned sub-clause.
- **Has no mutation, by name**: the horizontal content clip's
  `chrome.delta(-offset)` translation (§7.9); `measureNativeLayout`'s bracket
  and the other stage-1/stage-2 holes this stage did not touch.

## Demo comparisons, in one place

Every lane re-took the twelve `CN-R` images from a `git archive` of its own last
`Sources/`-changing commit against an archive of `57893d0`, controls read first.

| taker | twelve images | two-authority chrome pair |
|---|---|---|
| lane 1 (`72762cc`, then `440fd78`) | 12/12 **0**, scene dumps identical, taken twice | **0** |
| lane 2 (`512bc02`) | 12/12 **0** | **0** |
| lane 3 (`a1b8ff3`) | 12/12 **0** | **0** |
| lane 4 (`275d8fb`) | 12/12 **0** | **0** |
| lane 5 (`3a4346b`) | 12/12 **0** | **0** |
| lane 1's verifier (scratchpad harness, regenerated at both trees) | 12/12 **0** | **0** |
| lane 2's verifier (**an independently written harness**, `VPixels.swift`, injected into `git archive` trees of both commits) | 12/12 **0**, every scene dump byte-identical | **0** |

Controls on the head images, `57893d0`'s figures exactly, at every taking: light
vs dark f0 **1 048 576**; vs modal-light **1 030 498**; vs animation-light
**210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**; 544 distinct
values in `default-light-f0`; 216 in `chrome-legacy`.

**What the twelve images cannot see, and it matters this stage**: none of them
is ever scrolled, so no scene contains an indicator (§7.6). The pixel evidence
covers the clamp, the prepaint write-back and the content clip; the indicator
half of lane 1's fold is pinned by M1b–M1e.

**Real windows: none.** `docs/probes/appkit-screen-lock-state.swift` read
`CGSSessionScreenIsLocked = 1` / `displayAsleep main: 1` at the end of every one
of the five lanes and again at the verification round (`CGSSessionScreenLockedTime
= 1790087900` throughout). The screen was unlocked during the design phase only,
when there was nothing to capture. `IOConsoleLocked` was never read (`FR-V`).

## Hazards this stage introduced or exposed

1. **An `…unconsumed` regression now truncates the suite.** Since lane 3 the
   first proposal-authority `Window` holding a `ScrollView` is test #1251, and a
   production frame traps rather than reporting — no summary line, no list of
   failures. Deliberate (`LR-BI` as amended), and now a standing property.
   Mitigation is a `WindowPair`-style diagnostics pre-flight, eligible for **30
   of the 34** scenarios; the other four capture shared `Seen` boxes that a
   second render would double (§9.6, corrected).
2. **The exit test depends on cross-file declaration order**, which Swift
   Testing does not specify. It fails loudly and names what it had not seen, but
   on a different toolchain's file order that red is spurious, and
   `--filter everyScrollScenario` hard-fails by construction. Measured on
   Swift 6.4 (`swiftlang-6.4.0.33.1`) twice. **A new scroll scenario owes a
   `ScrollAuthorityCoverage.record` call and a bump of the 34 literal.**
3. **A scroller's axis is one assignable property now** (`var chrome`).
   Mis-wiring `ScrollView`'s reddens exactly one indicator test; the horizontal
   content clip's translation is pinned nowhere (§7.9).
4. **`reportUnconsumedLoweredItems` reads `item.declared` only.** A field a
   later stage adds to an animated style alone is dropped with no diagnostic —
   `LR-AS`'s convention is the only thing closing it. Now in
   `loweredLayout`'s doc.
5. **Site `component` has no reachable report left** (`LR-BO` item 2), and the
   two reasons are not equally strong: the decisive one is that
   `componentFrameStyle` carries no reportable field, and `.frameLayer` is the
   guard that takes over if that changes. Whoever puts a bound into that style
   owes a pin in the same change.
6. **The `CN-R` harness is still uncommitted**, and this stage rebuilt it three
   times and reused it twice; a fourth independent rebuild (lane 2's verifier)
   agreed with it, which is the strongest evidence yet that the eight control
   figures are a sufficient specification — and also the strongest argument for
   committing it. Owner: stage 6b.
7. **Shared-file collisions with any parallel track.** `ScrollView.swift` was
   rewritten heavily (the chrome removed, `loweredLayout` added),
   `ProposalScrollView.swift` lost 105 lines, `LegacyLowering.swift` and
   `Component.swift` gained the amend path, and **all three scroll test files
   are now parameterised by authority** — a merge that adds a scroll test
   without a `record` call turns the exit criterion red.
8. **No public type's storage moved** (`ScrollChrome` is a computed internal
   struct; `ComponentModifierOp` is internal), so `swift package clean` was not
   required. Lanes 4 and 5 ran it anyway and read the same totals. Re-run it
   after the merge regardless — CLAUDE.md's rule is about the merge, not the
   lane.

## Deferred, each with an owner

| deferred | owner |
|---|---|
| `List` windowing under the proposal authority (it traps through a `Window` and builds zero rows under diagnostics; the demo's scroll-subtree widths stay 0 because of it) | **stage 4** |
| turning an `…unconsumed` trap back into a named failure in a scroll fixture (30 of 34 scenarios are eligible) | stage 6b |
| committing the `CN-R` harness | stage 6b |
| a real-window capture of the fold and of the demo | whoever runs with an unlocked screen; `capture.sh` is ready |
| divergences **48** and **56**' retirement (answered here under the proposal authority, still wrong on purpose under the legacy one) | stage 6b |
| divergence **54**'s retirement — it **survives** the lowering and is now pinned as a literal | stage 11 / task 10, with `ProposalScrollView`'s own lowering |
| `ProposalScrollView` publishing a `ScrollContext`; `ProposalScrollView` animating | stage 11 / task 10 (`LR-BF`, `LR-BJ`) |
| an amend frame or a per-member frame applying a member's `flexGrow`/`margin` rather than dropping them | stage 6b (needs a non-arbitrary main axis, and SwiftUI has no `flexGrow` to probe) |
| framed members staying **one** flex item where SwiftUI's are siblings (140 vs 148) | stage 11, `TB-M`'s associated type |
| the per-member row's cross-axis `alignment:` (M5g green, unprobed) | stage 11 with the siblings question, or one uneven-height arm |
| the horizontal content clip's translation, unpinned (§7.9) | whoever next edits `ScrollRoutingTests`; stage 6b at the latest |
| a reachable diagnostic at site `component` | whoever first needs one |
| a demo shape exercising a frame over a multi-member component | whoever adds one, or stage 6b |
| everything stages 4–14 already own: percentages, unequal grow weights, a length `flexBasis`, a non-greedy `maxSize`, `baseline`, `hidden()`, `Deferred`, absolute positioning, custom elements, the root switch, the deletions | unchanged by this stage |

## For the integrator

**Verdict: all five lanes verified `ok: true`.** Thirteen minor issues in total,
none blocking and none a defect in a landed behaviour; eleven applied in this
commit (three source doc comments and the record's and rulings' corrections),
one handed to the Docs phase with its text below, one recorded as a deferral.
No lane needed a fix round.

This branch's figures at this commit: **1572 tests, 97 goldens, 77 guards, 0
`error:` / 0 `warning:`** (the lone `warning:` in a native log is SwiftPM's
deprecation notice); 34 `@available(*, deprecated` hits, unchanged. Re-take
every count after the merge, **after `swift package clean`**.

**`CLAUDE.md` (rules only; then `cp CLAUDE.md AGENTS.md` and `cmp`):**

1. **Ruling table.** `` `LR-` (next `LR-BB`) `` → `` `LR-` (next `LR-BQ`) ``. In
   the per-task list, after the stage-2 entry: `` 7 stage 3 `LR-BB`…`LR-BP`
   (§25, spec `specs/2026-09-22-engine-stage-3-design.md`, same decisions doc,
   probe `swiftui-engine-replacement-stage3.swift` revision 2) ``.
2. **Counts.** 1550 / 97 / 77 → **1572 / 97 / 77** on `feat/engine-stage-3`
   (**+22 tests**: lane 1 +3, lane 2 +8, lane 3 +2, lane 4 +6, lane 5 +3;
   **0 goldens, 0 guards** — no typecheck guard was added, so the per-file guard
   list and the "all 77 guards skip under the default build system" sentence are
   unchanged); record §25. Then re-take after the merge.
3. **The layout-authority paragraph**, after the stage-2 one, rules only:
   > "**Stage 3 lowers scrolling and `Component` distribution** (`LR-BB`…`LR-BP`).
   > A `ScrollView` lowers its content through `lowerLegacyNode` at site
   > `scrollView` (stage 2's container lowering entire) under a
   > `requestNativeScrollViewport`, and records **the viewport** as its own
   > `LoweredItem`; `flexShrink: 0` is not carried, and the content record is
   > left unconsumed, so a later field belongs on the **declared** content style
   > or it vanishes silently (`reportUnconsumedLoweredItems` never reads the
   > animated one). The lowered viewport **fills its proposal on the scrolling
   > axis** where the legacy one hugs; the cross axis agrees, and divergence 54
   > **survives** because only a `ScrollView` records an item. `ScrollContext`,
   > `$anim-content` and `$anim-viewport` are unchanged, and `List` still windows
   > against the published context. A `Component`'s `.width`/`.height` lowers to
   > **one native frame per member**, aligned per axis (`.center` on a declared
   > axis, 0 on an `auto` one) with the member's record consumed and planned at
   > `parentKind: .stack`, which **drops** its `flexGrow`, `flexShrink`,
   > `flexBasis`, `alignSelf` and `margin`; `.padding` lowers as an ordinary
   > one-child container; a `.frame` layer over several member nodes is a row of
   > per-member frames at spacing 0. Site `component` has **no reachable report**
   > left. **Both scroll suites run under both authorities** — 34 scenarios, a
   > roll call that names any scenario that stops participating, and a new one
   > owes a `ScrollAuthorityCoverage.record` call and a bump of the 34."
4. **The falsified sentence** (this is a correction, not an addition): lines
   472–473, "`ProposalScrollView`'s clamp and indicator are private copies of
   `ScrollView`'s — fix both" → "`ScrollView` and `ProposalScrollView` share one
   `ScrollChrome` (clamp, extent, delta, indicator bounds, `paintIndicator`,
   both `resolvedOffset` overloads), built computed per frame from `axis`,
   `cornerRadius` and `indicatorVisibility`; `ScrollView.clamp`/`.extent` are
   gone. A re-inlined private copy on either side reddens
   `theTwoScrollElementsShareOneChromeImplementation`." Then **grep the file for
   "private copies"** — the claim is copied in the spec too, which is this
   stage's own document and already corrected.
5. **CI — what lapses silently.** Two new rows:
   - "`everyScrollScenarioRanUnderBothLayoutAuthorities` reads coverage
     accumulated by two other files and so depends on Swift Testing's
     **unspecified** cross-file order (measured on Swift 6.4 only). On a runner
     with a different order it is a spurious red, and
     `swift test --filter everyScrollScenario` hard-fails. It always names what
     it had not seen — read the names before debugging."
   - "A proposal-authority regression that reports an `…unconsumed` field now
     **traps in a `Window` test and truncates the run with no summary line**
     (first such test is #1251). Read the last lines of the log, not the
     summary."
6. **Human verification.** Add a row: "engine replacement stage 3 (plan task 7,
   `feat/engine-stage-3`): release-window capture of the default demo and the
   preview against `57893d0` | **open** — the screen was locked at the end of
   all five lanes and at the verification round (`CGSSessionScreenIsLocked = 1`,
   `displayAsleep main: 1`). Offscreen stand-in: twelve images 0 differing at
   every lane and twice more in verification, once with an independently written
   harness, the two-authority chrome pair 0. **None of the twelve scenes is ever
   scrolled**, so no indicator is painted in any of them; the fold's indicator
   half is pinned by tests, not by pixels. Nothing in production runs under the
   proposal authority, so no demo look is owed until stage 6b (record §25)".
7. **Practices.** Add: "**A fixture of fixed-size leaves cannot see a container
   lowering** — `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized`
   are all no-ops over children that declare no item field, so 'this lowers as
   the container lowering' needs a child that gives the container something to
   do (stage 3's M2b and M4b, the same finding one lane apart)." And: "**Record
   which branch a mutation was applied to** — a whole-file substitution over two
   byte-identical call sites is a different mutation, with a different reddened
   set, from a scoped one (stage 3's M2g)."
8. **Nothing else in the rules changes.** Wheel routing, divergence 16, the
   seven reserved slots, `List`'s four requirements, hit testing, accessibility
   and the disabled gate are untouched by this stage, and their tests now run
   under both authorities.

**The plan's task 7 entry: do NOT tick it.** Append under the existing notes:

> *Progress 2026-09-22 on `feat/engine-stage-3` (`ca7272a..`record commit),
> stage 3 of 14, task still open.* Spec
> `specs/2026-09-22-engine-stage-3-design.md`; rulings `LR-BB`…`LR-BP` in
> `../2026-09-17-engine-replacement-decisions.md` (the same doc as stages 1 and
> 2); probe `docs/probes/swiftui-engine-replacement-stage3.swift` (revision 2,
> groups V and W); record §25. **Stage 3 delivered** (five lanes, each with its
> own mutation table, all verified `ok`, thirteen minors all dispositioned):
> `ScrollView` lowers onto the kernel scroll viewport with stage 2's container
> lowering as its content and the viewport as its own item record; the lowered
> viewport fills its proposal on the scrolling axis, and divergence 54
> **survives** the lowering (pinned as a literal) rather than closing;
> `ProposalScrollView`'s private clamp and indicator fold into one shared
> `ScrollChrome`, the stage's only production-path edit; `$anim-content`,
> `$anim-viewport` and `ScrollContext` publication are unchanged, and `List`
> still windows against the published context; a `Component` amend lowers to one
> per-member native frame aligned per axis and a `.frame` layer over several
> members to a row of per-member frames, which is SwiftUI's answer to
> divergences 48 and 56 under the proposal authority. **Exit criterion met**:
> `ScrollRoutingTests` + `ScrollIndicatorTests` + `ScrollViewTests` run 34
> scenarios under **both** authorities, their 9 custom registrations re-spelled
> as native probe leaves, with a roll call that names any scenario that stops
> participating — inverting the lowered viewport's axis reddens 20 of the 34, on
> the proposal arm only. Suite 1550 → **1572**, 97 goldens unmoved, 77 guards
> (none added); twelve offscreen demo images 0 differing at every lane and twice
> more in verification, once with an independently written harness; **no
> real-window capture** (screen locked throughout, `FR-V`). **Not done:**
> production still runs the legacy authority (stage 6b); `List` windowing under
> the proposal authority is stage 4's and is checked only under the legacy one
> here; an `…unconsumed` regression now truncates the suite instead of failing
> by name; `ProposalScrollView` still publishes no `ScrollContext` and never
> animates (stage 11 / task 10).

**README:**

- The count sentence → "On `feat/engine-stage-3` (2026-09-22, plan task 7
  stage 3) … **1572 tests** … **97** … **77** guards"; re-take after the merge.
- "Fifty-eight measured divergences" stays **fifty-eight**: this stage retires
  none and adds none. 48, 54 and 56 gain text, not numbers.
- In the record list, after `23-integration-stage-2-grids.md`: "and
  [`25-engine-replacement-stage-3.md`](docs/record/25-engine-replacement-stage-3.md)
  for its third stage — scrolling and `Component` distribution". In the specs
  list, extend the engine-replacement entry: "stages 1, 2, G and 3 of 14 landed;
  production still uses the CSS engine".

**Other owned documents:**

- `docs/record/README.md`: add `` | `25-engine-replacement-stage-3.md` | plan
  task 7 stage 3 on `feat/engine-stage-3`: `ScrollView` lowered onto the kernel
  scroll viewport, one shared `ScrollChrome` for both scrollers, `Component`
  amend and wrap as per-member native frames, a frame layer over several members
  as a row, and both scroll suites running under both layout authorities (the
  exit test); five lanes, red runs, verifier verdicts (all `ok`, thirteen
  minors), mutation tables including the verifiers' twenty, the twelve offscreen
  images and the independently rebuilt harness; counts 1572 / 97 / 77 | ``.
- **`docs/record/04-divergences.md`** — three rows gain text, none is retired
  and no number is added:
  - **48** (`.width` on a `Component` overwrites its members' declared width):
    append "**Answered under the proposal authority** by stage 3 lane 4
    (`LR-BG`): the amend is one native frame per member, aligned per axis, so
    each member keeps its own width and is centred in its own 70 — SwiftUI's
    G7/G8. Still wrong on purpose under the legacy authority; retirement is
    stage 6b's. New pins:
    `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt`,
    `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares`."
  - **54** (`ScrollView` takes its cross axis from its parent where
    `ProposalScrollView` takes its content's): append "**Survives the stage-3
    lowering**, and stage 3's first writing of `LR-BC` was wrong to say it
    closed: a lowered `ScrollView` records a `LoweredItem`, so stage 2 wraps it
    in a stretch item frame whose rect is aliased as the element's;
    `ProposalScrollView` records none. Now pinned as a literal by
    `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem`, and
    **removed from stage 6b's retirement row** — it is stage 11 / task 10's."
  - **56** (a `.frame` over a multi-member `Component` squeezes its members):
    append "**Answered under the proposal authority** by stage 3 lane 5
    (`LR-BH`): a row of per-member frames at spacing 0, so the members keep 30
    and 50 rather than being shrunk to 26 and 44. The 140 against SwiftUI's 148
    is the enclosing stack's own 8pt spacing, and framed members staying one
    flex item is `TB-M`'s, stage 11. Still wrong on purpose under the legacy
    authority. New pin:
    `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem`."
- **`docs/record/05-declared-but-inert.md`** — one row edited, one added:
  - `Style.overflow`: it still has exactly one write (in `ScrollView`) and no
    reader; add "the stage-3 lowering does not carry it either — the kernel
    reads `overflow` nowhere, and `loweredLayout` says so in a comment".
  - Add to the test-observables row (`Frame.scrollRegions`,
    `StateTable.isDirty`, …): `` `LayoutAuthority.allCases` `` — the
    `CaseIterable` conformance lane 3 added exists for
    `ScrollAuthorityCoverage`'s roll call and has no production reader.
  - **No row is deleted**: nothing in production sets
    `LayoutAuthority.proposal` until stage 6b.
- The `SA-`, `FR-`, `CN-`, `GR-` decisions docs: no change this stage.
- This stage's own decisions doc: `LR-BB`…`LR-BP` are appended; `LR-BL`,
  `LR-BM`, `LR-BN`, `LR-BO` and `LR-BP` carry paragraphs headed **Amended,
  verification round**; **`LR-BQ` is the next id**, and the header's "next
  unused" line already says so — unmoved, because this round appended no
  ruling.

## 14. Branch checker, 2026-09-22 (adversarial, `57893d0..f9adc0c`)

An independent pass over the whole branch. **Everything checkable was re-taken,
not read off this record.** Verdict and the two open code concerns are at the
end.

### 14.1 The numbers, re-measured from a clean tree

| measure | claimed | branch checker |
|---|---|---|
| suite | `Test run with 1572 tests in 1 suite passed` | **`Test run with 1572 tests in 1 suite passed after 52.480 seconds`** — after `swift package clean`, `swift build --build-system native --build-tests`, unfiltered `swift test --build-system native --no-parallel` |
| `error:` / `warning:` | 0 / only SwiftPM's deprecation notice | **0 / 1**, the notice — counted over the **whole** clean build log (256 lines), not its tail |
| baseline | 1550 at `57893d0` | **1551** in a `git archive` of `57893d0` carrying the checker's one extra harness test — i.e. **1550**, so the **+22** delta is confirmed |
| goldens | 97, none moved | **97**; `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` **empty** |
| guards | 77 (79 hits − declaration − comment), per-file list unchanged | **77**, same 79 hits and the same per-file split; stage 3 added none |
| `cmp CLAUDE.md AGENTS.md` | clean | **clean** |
| `@available(*, deprecated` | 34, unchanged | **34** at both `57893d0` and HEAD |
| 34 parameterised scenarios | 16 + 14 + 4 | **34** `ScrollAuthorityCoverage.record(#function` calls, 16/14/4, matching `expected.count` |
| test functions removed or renamed | none claimed | **none**: the whole-`Tests/` `func` inventory at `57893d0` is a strict subset of HEAD's (2124 → 2164) |
| ruling ids and test names cited in the branch's docs | — | 50 ruling ids: all defined except the four "next unused" (`LR-BQ`, `CN-V`, `GR-AU`, `OM-AN`). 113 identifiers: **one** has no definition, `aListInsideALoweredScrollerWindowsAgainstTheSameContextAsTheLegacyOne`, and that is `LR-BI`'s amendment **quoting the name it renamed away** — correct as written |

`ListTests`, `TombstoneTests`, `AccessibilityTreeTests`,
`AccessibilityEndToEndTests`, `AccessibilityDefaultsTests`, `AnimationTests`,
`AnimationDurationTrapTests`, `DisabledTests`, `FocusTests`, `HitboxTests`,
`HitRegionTests`, `InputDispatchTests` and `StateTableTests` are **byte-unchanged** on the branch and green in that run.

### 14.2 Three mutations, designed by the checker, run to completion

Each: commit first, `cp` aside, apply, native build, **full unfiltered** suite,
restore from the copy, `git status --short` empty (verified after each).

| # | mutation | reddened | reading |
|---|---|---|---|
| **BC1** | **one** scenario's `@Test(arguments:)` reduced to `[LayoutAuthority.legacy]` (`aWheelEventInsideARegionScrollsIt`) — strictly finer than M3c, which edits the shared list | **2**, and **both halves of the split instrument fire**: `everyScrollScenarioRanUnderBothLayoutAuthorities` at `ScrollViewTests.swift:287` and `record`'s order-independent whole-set check inside `aScrollViewWithNoCornerRadiusClipsSquare`, each printing `aWheelEventInsideARegionScrollsIt ran under 1 authority, not both` | the exit criterion has teeth at single-scenario resolution and **names the offender**. Independently reproduces the verifiers' lane-3 V5 |
| **BC2** | the lowered viewport's axis inverted (`requestNativeScrollViewport(child:axis:)`), proposal branch only | **29 tests / 56 issues**; **exactly 20 of the 34** parameterised scenarios, **all 30 parameterised issues on the `.proposal` arm and 0 on `.legacy`**; plus the 9 non-parameterised lowering tests | reproduces §12.2's lane-3 V1 **to the test, the issue and the arm**. The exit criterion catches a lowering defect the legacy arm cannot see |
| **BC3** | `$0.viewportExtent = viewport` deleted from `ScrollChrome.resolvedOffset`'s prepaint overload — the line `List` windows against | **13**: `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aListsWorkIsTheSameFor160RowsAsFor40`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `anOffScreenListRowsModelReadIsNotTracked`, `aClientDoesNotChangeStateRetention`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `synthesizedNodesCostNothingWhileNoClientIsActive`, `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`, `aScrollContextSurvivesALoweredViewportAcrossTwoFrames` | **`List` windowing is genuinely pinned, and pinned by the suite this branch did not touch.** 12 at lane 1 (V6) + test 3.5, which did not exist then — the expected superset |

### 14.3 The fold, checked textually rather than by trusting the tests

All seven `ScrollChrome` members were extracted and normalised against **both**
pre-fold copies. Every one is the **`ScrollView`** copy verbatim (`delta`'s only
difference is the parameter name `v` → `value`). The pre-existing drift between
the two copies was measured the same way and is exactly what `LR-BD` claims and
no more: `paintIndicator`'s `lastScroll` seed (`0` against `-Double.infinity`),
the `$0.viewportExtent` write's position **inside** the same `withState`
closure, and spelling (`clamp(offset:)` / `clamp(_:)`, `return Bounds(` /
`Bounds(`). Both seeds are dead — `withState` always runs its closure — so the
fold's only behavioural change to `ProposalScrollView` is to a dead initialiser.
`ScrollView`'s **legacy** `requestLayout` branch, `withScrollContext` and
`ScrollContext` publication are untouched in the diff.

### 14.4 The twelve `CN-R` images, on a harness written from scratch

The generator is still uncommitted, so the checker wrote a **fifth** one
(75 lines, `git archive` of each commit, `@testable import MetalUIDemoContent`,
twelve images through a real `Window` over `FakePlatformWindow`, raw BGRA plus
its own scene-dump format). **Controls read non-zero first, and all eight
recorded figures reproduce exactly at BOTH trees**: 1 048 576 / 1 030 498 /
210 027 / 0 / 1 048 576, 544 and 216 distinct values, chrome pair 0.

**`57893d0` against `f9adc0c`: 0 differing pixels in all twelve, every scene
dump byte-identical.**

§7.6's caveat was re-measured independently and **holds**: scanning all twelve
scene dumps for a 3pt cross-axis rect finds **zero** in every one, so no
indicator is painted anywhere in the set. `ScrollState.lastScrollTime` defaults
to `-.infinity`, which is why.

**Screen: still locked** (`session CGSSessionScreenIsLocked = 1`,
`CGSSessionScreenLockedTime = 1790087900` — the same lock as at every lane —
`displayAsleep main: 1`, `displayActive main: 0`). No real-window capture;
`IOConsoleLocked` not read (`FR-V`). The look stays open.

### 14.5 Doc defects found and fixed in this commit

1. **`CLAUDE.md` overclaimed the fold's pin.** "A re-inlined private copy on
   either side reddens `theTwoScrollElementsShareOneChromeImplementation`" is
   false for a **byte-identical** copy: that test compares the two elements'
   output, not their call graph. Both M1f and V7 drifted the thumb floor to
   30pt, and the test's own doc comment says so. Reworded to name the drift.
2. **The stage-3 spec's §5 file list contradicted its own §6 lane 3.** It said
   "doc comments only in … `LayoutAuthority.swift`", where lane 3 adds
   `CaseIterable`; and it omitted the three doc-comment-only citation renames in
   `Hitbox.swift`, `StateTable.swift` and `Window.swift` that §7.3 of this
   record already lists. Corrected, with the branch diff named as the check.
   The "**Not touched**" half was verified against the diff and is right.
3. **`specs/2026-09-17-engine-replacement-design.md`'s status header still read
   "stage 1 of 14"** — stale since stages 2 and G, so not stage 3's regression,
   but it is the doc `CLAUDE.md` sends a reader to for §4.1's table. A dated
   paragraph now names which stages have landed and points at the plan's stage
   list as the live status.

Nothing else was changed. `cmp CLAUDE.md AGENTS.md` clean afterwards; the
counts, the goldens and the guards are unaffected by all three edits.

### 14.6 Two code concerns, reported not fixed

Both are **already written down** by this stage, which is why neither blocks the
merge; they are repeated here because they are the two things a later stage will
trip over.

1. **A proposal-authority regression truncates the suite.** `Window` never sets
   `reportsUnlowerableFields`, so `noteUnlowerable` takes its
   `preconditionFailure` branch and the process aborts with no summary line.
   Lane 3 put 34 scenarios × 2 through real `Window`s, so this is now reachable
   from ordinary scroll work. Named in `LR-BI`'s amendment, in CLAUDE.md's CI
   list and in §13's deferrals (30 of the 34 are eligible for a diagnostics
   pre-flight). Owner: stage 6b.
2. **The exit test depends on an unspecified cross-file test order.**
   `everyScrollScenarioRanUnderBothLayoutAuthorities` reads coverage two other
   files accumulate. Verified by the checker: `swift test --filter
   everyScrollScenario` **fails**, by construction. It fails loudly and names
   what it had not seen, and the `record`-side whole-set check is
   order-independent (BC1 fired it), so the risk is a spurious red rather than a
   false green. Named in CLAUDE.md's CI list. Owner: whoever next sees a
   toolchain change the order.

**Verdict: merge.** Every claim the checker could test held, including three of
the verifiers' own mutation figures reproduced to the test and to the arm; the
twelve-image comparison reads 0 on an instrument written from scratch; nothing
in `List` windowing, wheel routing, the overscroll clamp, identity, hit testing,
accessibility or animation moved, and the one line `List` windowing depends on
is measured live rather than argued. Task 7's box is **not** ticked, and the
plan's stage note is a superset of §4.1 row 3's exit criterion
(`ScrollViewTests` added to the two suites the row names; both authorities where
it asks for the proposal one), which is what a delivered stage should read.

---

## 15. The merge into `master` (2026-09-22, `integrate/stage-3`)

`master` had moved to `b10594c` while stage 3 ran: PR #8, the FreeType
rasterizer line (`CFreeType` vendored, `MetalUIFreeType`, the CoreText oracle
suite, the separate `Tests/PortableTests` determinism package with Linux and
Windows CI, rulings `FT-A`…`FT-K`, record §24). It had itself merged `57893d0`
first and renumbered its own record from §21 to §24 in the process (`cb2b3aa`;
the note is at the end of record §24).

**Conflicts: three, all documentation** — `CLAUDE.md`, `AGENTS.md`,
`docs/record/README.md`. No source file conflicted: the FreeType line touches
`Sources/CFreeType/`, `Sources/MetalUIFreeType/` and `Package.swift`, stage 3
touches `Sources/MetalUI/`.

**Resolution — both sides kept in full.**

- `CLAUDE.md`'s ruling-prefix row takes stage 3's `LR-` (next `LR-BQ`,
  verified against the decisions doc's last `## LR-` heading, `LR-BP`) **and**
  the FreeType line's `FT-` (next `FT-L`, verified against its spec). The
  "not a task of this plan" sentence went from two record files to three:
  §19, §20 and §24.
- The counts bullet was rewritten from a measurement on the merged tree, not
  from either side (below).
- `docs/record/README.md` keeps both index rows, the FreeType one at §24 and
  stage 3's renumbered to §25.
- The root `README.md` count sentence was re-taken, and its record list — which
  had never mentioned the FreeType record — now names it.

**Record renumbering.** Both lines added a `24-*.md`. The FreeType line was
pushed to `origin` first, so it keeps §24 and this file moved 24 → 25, exactly
as record §23 §8 moved 19→21, 20→22, 21→23 for the same reason. The sweep
repointed **22 `§24` occurrences** and **7 path references** across
`Tests/MetalUITests/LoweringScrollTests.swift`, this file, records §03, §04 and
§05, the engine-replacement decisions doc, the SwiftUI-alignment plan, the
stage-3 and engine-replacement specs and the root `README.md`. The FreeType
side's own citations — its record's renumbering note, five in
`specs/2026-09-22-freetype-rasterizer-design.md` and its `README.md` index row
— were **left alone**.

**Counts on the merged tree** (`swift package clean`, `swift build
--build-system native --build-tests`, then unfiltered `swift test
--build-system native --no-parallel`):

- **`Test run with 1580 tests in 2 suites passed after 52.569 seconds`** — one
  summary line, not two, although the run now covers two suites
  (`MetalUIFreeTypeTests` is the second). **1580 = 1558 + 22 = 1550 + 8 + 22.**
  Three tests skipped and counted: `regenerateAllGoldens`,
  `aListsWorkIsTheSameFor100kRowsAsFor500`, and the FreeType oracle's gated
  `measure(file:)`.
- **97 goldens**, `find Tests -name "*.json" | wc -l` and
  `find Tests/MetalUILayoutTests -name "*.json" | wc -l` both 97;
  `git diff --name-only b10594c HEAD -- 'Tests/**/*.json'` empty.
- **77 guards** — 79 `canTypecheck` hits minus `Typecheck.swift`'s declaration
  and `UnitSafetyTests`' comment. Per file unchanged: `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8,
  `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `ContainerCompileGuards` 4, `GridCompileGuards` 4,
  `AXNodeTests` 3, `DecorationCompileGuards` 3, `UnitSafetyTests` 2,
  `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
  `SceneBoundaryCompileGuards` 2, `LayoutAuthorityCompileGuards` 1. The guards
  **ran**: the log carries one
  `FR-J no-argument frame: succeeded=true deprecations=2`.
- 0 `error:`; the only `warning:` is SwiftPM's `--build-system native`
  deprecation notice.
- Twelve non-test targets, unchanged by stage 3 (its Package.swift diff against
  `57893d0` is empty) and extended by the FreeType line with `CFreeType` and
  `MetalUIFreeType`.
