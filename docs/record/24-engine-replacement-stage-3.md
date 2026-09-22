# 24 — Engine replacement, stage 3: scrolling and `Component` distribution

Plan task 7, stage 3 of the fourteen in
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1.
Design: `docs/superpowers/specs/2026-09-22-engine-stage-3-design.md`.
Rulings: `LR-BB`…`LR-BJ` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md` (the same
decisions doc as stages 1 and 2).
Branch `feat/engine-stage-3` from `57893d0`, worktree
`/Users/maxburger/Developer/MetalUI-stage-3`.

**Status: lane 1 implemented** (§7). Sections 1–6 are the design phase, in
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
