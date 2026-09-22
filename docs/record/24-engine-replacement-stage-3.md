# 24 — Engine replacement, stage 3: scrolling and `Component` distribution

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
| **M2c** | the viewport lowered as a `fixedSize` over its content | **6**: 2.1, 2.2, 2.2a, 2.3, 2.5 and the demo census |
| **M2d** | `flexShrink: 0` carried onto the lowered content style | **10**: 2.1, 2.2, 2.2a, 2.3, 2.4, 2.5, 2.7, `anItemFieldNoLoweredContainerConsumesIsReportedByName`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` and the demo census, whose report becomes `[list.noLowering, scrollView.flexShrink.unconsumed]` — read off the failure, and the entry the omission is observable through |
| **M2e** | the content node registered with `site: .modifierLayer` | **2**: `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable`, `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` |
| **M2f** = **M2i** | `recordLoweredItem` dropped from the lowered `ScrollView` (the design lists two ids; it is one edit) | **4**: 2.2, 2.2a, 2.5, 2.7 |
| **M2g** | both `animated(…)` calls given the bare `id` | **4**: `aLoweredScrollViewKeepsItsTwoAnimationSlots`, `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape`, `everyRegisteringSiteAnimatesItsStyle`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` |
| **M2h** | the content node registered twice | **1**: `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork` |

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
- Typecheck guards: **77**, unchanged (78 `canTypecheck` hits across the 15 guard
  files minus `UnitSafetyTests`' comment). The lane adds no public spelling, so
  it adds no guard.

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
`WindowPair.init` runs — was **not** applied: these fixtures' content closures
capture shared recorder boxes, so rendering the tree a second time would add a
phantom entry to every `Seen` and break the tests it was protecting.

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
- Typecheck guards: **77**, unchanged (78 `canTypecheck` hits minus
  `UnitSafetyTests`' comment). The lane adds no public spelling.
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
  every axis, so the frame aligns and never stretches.
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
| typecheck guards | **77** (78 `canTypecheck` hits minus `UnitSafetyTests`' comment), per-file counts unchanged from the baseline; the lane adds none |
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

**Every one of the six reddened its named test.** The two that reddened exactly
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
| divergence 56's retirement | answered here under the proposal authority, still wrong on purpose under the legacy one | stage 6b |
| a demo shape that exercises a frame over a multi-member component | there is none, so the corpus test cannot cover this lane; its two tests are the whole coverage | whoever adds one, or 6b |
| committing the `CN-R` harness | survived from lane 4 only because this lane ran in the same session | stage 6b |
| a real-window capture | the screen has been locked at the end of all five lanes | whoever runs with an unlocked screen |
