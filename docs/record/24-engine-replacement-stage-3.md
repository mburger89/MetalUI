# 24 — Engine replacement, stage 3: scrolling and `Component` distribution

Plan task 7, stage 3 of the fourteen in
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1.
Design: `docs/superpowers/specs/2026-09-22-engine-stage-3-design.md`.
Rulings: `LR-BB`…`LR-BJ` in
`docs/superpowers/2026-09-17-engine-replacement-decisions.md` (the same
decisions doc as stages 1 and 2).
Branch `feat/engine-stage-3` from `57893d0`, worktree
`/Users/maxburger/Developer/MetalUI-stage-3`.

**Status: design phase only.** No file under `Sources/` or `Tests/` is changed
in any commit of this phase. Everything below was measured on 2026-09-22 (PDT).

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

## 2. Probes

### 2.1 Re-run and byte-identical

| probe | lines | result |
|---|---|---|
| `swiftui-stack-algorithms.swift` | 787 | the recorded block was extracted from the header (lines 236–1022, de-indented) and `diff`ed against a fresh `/usr/bin/swift` run: **identical** |
| `swiftui-component-distribution.swift` | 22 | fresh run **identical** to its header, G0–G16 |

### 2.2 New: `swiftui-engine-replacement-stage3.swift`

15 lines. Script form run twice, byte-identical; `xcrun swiftc -O` produced the
same 15 lines, exit 0, empty stderr in both forms. Recorded in its own header.

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
width-only amend was centring its member on the height axis. Probe **W2**
(`Pair().frame(height: 40)` byte-identical to the W0 control) and **W5** say
SwiftUI passes an undeclared axis through. Making the alignment **per axis** —
`.center`'s factor on a declared axis, 0 on an `auto` one — restored y 0 and
y 4, which is also the legacy answer. Ruling `LR-BG`.

### 3.6 `List` inside a lowered scroller

`Box { ScrollView { List(20 rows, rowHeight: 10) { … } } }.width(100).height(100)`:
report `[list.noLowering]` only; 45 ids, 2 agreeing, 3 disagreeing, 40
legacy-only (the rows the legacy side built and the proposal side did not).
The three disagreements are all width 80 → **0**, because the `List` reports and
builds no rows, so the viewport's non-scrolling axis — the content's answer —
is the empty content's 0. **That is stage 4's, not stage 3's.**

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
- **Lane 3's red-before must be taken at lane 1's commit**, not at the stage's
  head: once lane 2 lands, the parameterised scroll arms pass, and their
  "red before" has to be recorded from the commit where a proposal-authority
  window still traps.
- Every count in §3 is a prototype's, not an implementation's. Re-derive each
  before writing it into a literal, and record any row that does not reproduce
  as a finding before the expectation is written.
