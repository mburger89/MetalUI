# Engine replacement, stage 3 — scrolling and `Component` distribution (design)

**Status, 2026-09-22 (PDT): DELIVERED — all five lanes implemented and
verified** (record §7–§11, verification round §12). Every lane's verifier
returned `ok: true`; thirteen minor issues, none a defect in a landed behaviour,
are dispositioned in record §12.3 — eleven applied in the verification round
(three source doc comments and the record's and rulings' corrections), one
handed to the Docs phase, one recorded as a deferral. Final figures: **1572
tests, 97 goldens, 77 guards**, 0 `error:`, SwiftPM's deprecation notice the
only `warning:`; twelve offscreen `CN-R` images 0 differing pixels at every lane
and twice more in verification (once with an independently written harness); no
real-window capture — the screen was locked at the end of all five lanes and at
the verification round. The design-phase status below describes the state before
lane 1.

**Status, 2026-09-22 (PDT): DESIGNED. No file under `Sources/` or `Tests/`
changed in a commit; every source patch cited as *prototype P4* was applied in
this worktree, built, run and restored with `git checkout Sources Tests` (the
scratch test deleted), `git status --short` empty afterwards, and the suite
re-measured green at the baseline.** Branch `feat/engine-stage-3` from
`57893d0`. Plan task 7, stage 3 of the fourteen in
[`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 (its row 3), §4.2 (its dependency census) and §8 (its stage-3 row).
Rulings `LR-BB`…`LR-BJ`, critic round 1 `LR-BK`, lane 1 `LR-BL`, lane 2 `LR-BM`, lane 3 `LR-BN`, lane 4 `LR-BO`, lane 5 `LR-BP`, in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
— the same decisions doc as stages 1 and 2. Record:
`docs/record/25-engine-replacement-stage-3.md`. Probe:
`docs/probes/swiftui-engine-replacement-stage3.swift` (groups V and W, cited as
the *stage-3 probe*); stage 1's and stage 2's arms are cited as the *stage-1
probe* and *stage-2 probe*, the containers probe's as *stack-algorithms*, and
`swiftui-component-distribution.swift`'s as *component-distribution*.

**Scope, in one sentence.** `ScrollView` lowers onto the kernel scroll viewport;
`ProposalScrollView`'s private copies of the clamp, the offset resolution and
the fading indicator fold into one implementation both elements call;
`ScrollContext` keeps being published across a native viewport; and a
`Component`'s distributing modifiers stop needing `LayoutTree.setStyle` — an
amend becomes a per-member native frame and a `.frame` layer over several member
nodes becomes a row of per-member frames, which is SwiftUI's answer to
divergences 48 and 56 under the proposal authority.

**Five lanes** (the brief's cap), in order: 1 the shared scroll chrome (a
refactor under **both** authorities, so the only lane that can move a production
pixel); 2 the `ScrollView` lowering and its pins; 3 the two scroll suites
re-spelled to run under both authorities — the exit test, and it runs **after**
lane 2 because a proposal-authority `Window` traps until the lowering lands
(critic round 1 finding 1, `LR-BI`); 4 `Component` amend and wrap; 5 the frame
layer over several member nodes, and the amended pins.

**Critic round 1, 2026-09-22.** Twelve findings, dispositions in `LR-BK`;
`LR-BB`, `LR-BC`, `LR-BD`, `LR-BG`, `LR-BH`, `LR-BI` and `LR-BJ` carry an
**Amended, stage-3 critic round 1** paragraph each. The round added probe arms
**W7–W9**, replaced three mutations that could not redden anything (M1f, M2d,
M2e), moved lane 3 after lane 2, and added one test each to lanes 4 and 5 for
an item-field hole no prototype fixture could see.

---

## Contents

1. [Baseline](#1-baseline)
2. [Evidence gathered for this design](#2-evidence-gathered-for-this-design)
3. [The mechanism](#3-the-mechanism)
4. [The lowering table after stage 3](#4-the-lowering-table-after-stage-3)
5. [API and files](#5-api-and-files)
6. [Lanes](#6-lanes)
7. [The exit test](#7-the-exit-test)
8. [Demo, pixels and captures](#8-demo-pixels-and-captures)
9. [What must not move](#9-what-must-not-move)
10. [Deferred, each with an owner](#10-deferred-each-with-an-owner)

---

## 1. Baseline

At `57893d0`, measured 2026-09-22 in `/Users/maxburger/Developer/MetalUI-stage-3`:

| measure | value | how |
|---|---|---|
| suite | **1550 tests**, passed after 56.481 s; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel --skip-build` |
| goldens | **97** | `find Tests -name "*.json" \| wc -l` |
| typecheck guards | **77** in 15 guard files (79 `canTypecheck` hits minus `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment) | per-file `grep -c canTypecheck`; `PhaseSeparationTests` 19, `ErasureCompileGuards` 10, `EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6, `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `GridCompileGuards` 4, `ContainerCompileGuards` 4, `DecorationCompileGuards` 3, `AXNodeTests` 3, `UnitSafetyTests` 2, `SceneBoundaryCompileGuards` 2, `ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2, `LayoutAuthorityCompileGuards` 1 |
| screen | **UNLOCKED** at 09:1x PDT: no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`, `displayActive main: 1`, one 2056×1329 screen at scale 2 | `docs/probes/appkit-screen-lock-state.swift` (`FR-V`: `IOConsoleLocked` not read) |

**One baseline caveat, retired in lane 1 (`LR-BL`): it did not reproduce in
three unfiltered whole-log runs at the baseline tree, nor in any later run of
the lane.** The *first*
unfiltered run at this commit printed `Test run with 1550 tests in 1 suite
failed after 54.393 seconds with 1 issue`. The harness kept only the last 30
lines of that run, so the failing test's name is lost. A clean rebuild and a
second unfiltered run at the same commit, with the worktree restored, printed
`Test run with 1550 tests in 1 suite passed after 56.481 seconds`, and the
prototype run in between accounted for **every** one of its 15 issues by name
(§2). Treat a single unattributed issue at this commit as a possible flake —
**re-run before acting on it, and capture the whole log, not its tail**. The
screen was unlocked for every run in this session, which earlier stages' runs
were not; that is the one environmental difference on record.

**It is attributed or retired in lane 1, before lane 3** (critic round 1
finding 11). Lane 3 takes the count of real `Window`s in `ScrollRoutingTests` +
`ScrollIndicatorTests` from 37 to 74 — each a Metal device sharing one main run
loop, and four of the scenarios drive the display link — so leaving an
unattributed flake live under the one lane that doubles that surface would put
it in the exit test. Lane 1 runs the two suites unfiltered, whole log kept, and
records the result either way.

## 2. Evidence gathered for this design

### 2.1 Probes re-run today, unchanged

| probe | result |
|---|---|
| `swiftui-stack-algorithms.swift` | 787 lines, **byte-identical** to the output recorded in its header (extracted from the header and `diff`ed). Its SC1–SC5, SCG and SCG2 arms are this stage's SwiftUI authority for what a `ScrollView` answers and where it places content |
| `swiftui-component-distribution.swift` | **25 lines**, **byte-identical** to its header. G0–G16 are this stage's authority for what `.padding`/`.frame` do to a multi-member custom view. (The first writing of this row, and record §2.1, said 22; a fresh run emits 25, content unchanged. Critic round 1 finding 10.) |

### 2.2 New probe: `swiftui-engine-replacement-stage3.swift`

**18 lines** (15 at the first recording; W7–W9 were added in critic round 1),
run twice under `/usr/bin/swift` byte-identical, and `xcrun swiftc -O` produced
the same 18 lines with empty stderr and exit 0. The header's recorded block was
re-extracted and `diff`ed clean against the fresh run. Full output and the
reading are in its header. The arms this design rests on:

| arm | SwiftUI answer | what it settles |
|---|---|---|
| **V0** (control) | a `VStack` of two fixed 60×30 colours in a 200pt host hugs: 68pt block, `a` at y 66 | the stack is not filling by itself, so V1's filling is the `ScrollView`'s |
| **V1** | `VStack { 60×30; ScrollView { 60×300 } }` at 200: the scroller is **162** = 200 − 30 − 8 | a `ScrollView` answers its **proposal** on the scrolling axis |
| **V2** (control) | a maximally flexible `Color` in the same shape: also **162** | V1's scroller is as greedy as `.frame(maxHeight: .infinity)` |
| **V3** | the same over a 60×**20** child: still 162, the child at the viewport's own origin (y 38) | it fills even when the content is shorter, and places content at the leading edge |
| **V4** | `HStack { 30×60; ScrollView(.horizontal) { 300×60 } }` at 100: the scroller **62**, its content 300 and overflowing | the horizontal axis behaves identically |
| **V5** | the same with `.fixedSize()`: the scroller becomes its content's **300** and the 338pt stack overflows the 200pt host (`a` at y **−69**) | the flexibility is a *response to the proposal*; the ideal on the scrolling axis is the content's size (agrees with stack-algorithms SC1 at nil×nil: 50×300) |
| **W0** (control) | `Pair()` bare in a 300pt host: `a` (106, 45) 30×10, `b` (144, 45) 50×10 | layout transparency, == component-distribution G1 |
| **W1**, **W4** | `Pair().frame(width: 70)` (and `+ height: 40`): `a` at **96**, `b` at **164** — each member centred in its own 70, the pair 148 wide | a fixed `.frame` frames **each member**; re-measures G7 through a different host |
| **W7**, **W8**, **W9** | `Pair().frame(height: 40, alignment: .top)` puts both members at y **30** and `.bottom` at y **60**, against W0's y 45; `Solo().frame(height: 40, alignment: .top)` the same at y 30 | the single-axis frame **exists** and aligns on the axis it declares — these are the discriminating arms (finding 6) |
| **W2**, **W5** | `.frame(height: 40)` is byte-identical to W0; `Solo().frame(height: 40)` leaves its member at x 135 | **given W7–W9**, the undeclared axis is passed through at the child's own size. Alone these two are **not** evidence: "a per-member frame passing the axis through" and "no frame at all" predict the same output (practices shape 15). And note that `LoweredItem.contentAlignment` — how a **parent's** item frame places a grown child — has no SwiftUI counterpart at all, because in SwiftUI an undeclared axis leaves no free space to align in. `LR-BG`'s ground is the legacy agreement; these arms are its consistency check |
| **W3**, **W6** | `.frame(maxWidth: .infinity)`: `a` at **58**, `b` at **202** (each member greedy in its own 146); with `alignment: .leading`, `a` at **0** and `b` at **154** | a flexible frame distributes too, one greedy frame **per member** — wrapping the group in one would have put `b` at 38 |

### 2.3 Prototype P4 (scratch, applied and restored)

`s3proto-final.patch` (133 lines) in the session scratchpad, never committed:
`ScrollView.requestLayout`'s proposal branch lowers instead of reporting;
`StyledComponent`'s amend becomes a per-member native frame and its wrap goes
through `lowerLegacyNode`; `lowerLegacyLayer` frames each member of a
multi-node frame layer and rows them; the `frame.multipleNodes` diagnostic row
is deleted. Plus a scratch test file printing `LayoutDifferential` reports.

**Full unfiltered suite under P4: 1554 tests (1550 + 4 scratch), 15 issues in
5 tests — every one of them a diagnostics expectation this stage owns, and no
other test in the suite moved.**

| test | issues | why |
|---|---|---|
| `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` | 8 | the report loses `scrollView.noLowering`; three of its thirty rows' lowered rects change (§7) |
| `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` | 3 | the `ScrollView`, `Component amend` and `Component wrap` arms report nothing |
| `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` | 2 | the component-amend exit test no longer traps |
| `anItemFieldNoLoweredContainerConsumesIsReportedByName` | 1 | its "legacy `ScrollView`" arm expected `scrollView.noLowering` |
| `aHiddenFrameLayerIsReportedAsDisplayNone` | 1 | its "two nodes, not hidden" arm expected `modifierLayer.frame.multipleNodes` |

**The scroll arms** (`LayoutDifferential.compare`; "agrees" = empty report, no
disagreement, scenes/hitboxes/accessibility/state slots equal):

| arm | shape | result |
|---|---|---|
| A1 | `Box { ScrollView(.vertical) { 3 × 80×40 } }.width(80).height(60)` | **agrees**, 6 ids |
| A2 | the demo's spelling: the scroller `Box` `.width(80).flexGrow(1).flexBasis(0).minHeight(0)` in a stretching column | **agrees**, 8 ids |
| A5 | content (50×30) smaller than a 100×100 viewport | **agrees**, 4 ids |
| A8 | content **wider** than a vertical viewport (160×30 in 80×60) | **agrees**, 4 ids |
| A9 | a `ScrollView` inside a `ScrollView` | **agrees**, 7 ids |
| A4 | `Box { ScrollView(.horizontal) { 2 × 80×40 } }.width(100).height(50)` | viewport legacy **160×50** → lowered **100×50** |
| A7 | a **centring** `Row` parent, 120×100, over a vertical scroller of two 50×30 | viewport legacy (0, 20) 50×**60** → lowered (0, 0) 50×**100**; both children move up 20 |
| A10 | a **stretching** column parent with a declared cross size (120×100) | **cross axis agrees at 120 on both sides**; only the scrolling axis moves, 60 → **100** |
| A11 | a **centring** `Column` parent, 120×100 | cross agrees at 50; scrolling 60 → **100** |
| A6 | `ScrollView(.horizontal) { Text(long) }` in a 100×40 `Box` | the `Text` legacy 225×**40** → lowered 225×**16**, and `accessibilityEqual` false — **stage 2's single-child stretch elision** (`LR-AC`, X9), not a scroll fact |

**`ScrollContext`**, recorded by a custom element inside and after the scroller,
under each authority: `["off=0.0 vp=0.0 ax=vertical", "nil"]` — **identical**.

**The component arms** (after the per-axis alignment correction below):

| arm | legacy | lowered | SwiftUI |
|---|---|---|---|
| C1 `Pair().width(70)` in a 300-wide `Box` | members **70**×10 at x 0 and 70 | members keep **30** and **50**, at x **20** and **80** (each centred in its own 70) | W1/G7: centred in its own 70 |
| C2 `Solo().width(70)` | member 70×10 at x 0 | member 30×10 at x **20** | G8 |
| C3 `Pair().padding(8)` | — | **agrees** | G2 |
| C4 `.padding(4).width(70)` | members at x 4 and 74 | x **20** and **80** | G13's x 20 |
| C5 `.width(70).padding(4)` | members 70 wide at x 4 and 82 | 30 at x **24**, 50 at x **92** | G14's x 24 |
| C7 `Pair().height(20)` | members 30×**20** and 50×**20** at y 0 | 30×**10** and 50×**10** at y **5** (centred in their own 20) | W2's per-axis rule |
| C6 `Pair().frame(width: 70, height: 40)` | one 70×40 frame squeezing the members to **26** and **44** | a **140**×40 row of two 70-wide frames, members 30 and 50 centred at x **20** and **80** | W1/W4's 148 minus the enclosing stack's 8pt spacing |

**One correction the prototype forced.** Recording the amend frame's content
alignment as `.center` unconditionally moved C1's members from y 0 to y **15**:
the item frame the parent registers reads `LoweredItem.contentAlignment`, so an
amend that declares only a width was centring its member on the *height* axis
too. Making the alignment **per axis** — centred on a declared axis, leading on
an undeclared one — put them back at y 0. **The ground is the legacy answer it
must preserve**: divergence 48 is about the axis the caller declares, and an
amend that also relocates the other axis is a second, undesigned divergence.
Probe W7–W9 (the frame exists and aligns on its declared axis) with W2/W5 (the
undeclared axis passes through) are the consistency check. That correction is
`LR-BG`.

**What the arms say about the cross-authority scroll comparison.** The A-arms
above measure **legacy against lowered**. They do **not** measure `ScrollView`
against `ProposalScrollView`, which is what divergence 54 is about, and the
lowering does not close that (§3.2, `LR-BC` amended).

## 3. The mechanism

### 3.1 `ScrollView`, lowered (`LR-BB`)

Under the proposal authority `ScrollView.requestLayout` builds, in the same
order and under the same ids as before:

1. the content children, inside `pass.withScrollContext(…)` exactly as today;
2. a **content node** through `lowerLegacyNode(_:declared:children:site: .scrollView)`
   with a style carrying only `flexDirection` (the axis). That reuses stage 2's
   container lowering whole: the children's item records are consumed and
   wrapped, the cross-axis `alignItems` default (stretch) applies, and a `gap`
   or a `Text` child behaves as it does under any other lowered container;
3. a **viewport node** through `frame.requestNativeScrollViewport(child:axis:)`;
4. the viewport is recorded as this element's own `LoweredItem` — declared
   `Style()`, animated the viewport style, `kind: .leaf`, content alignment
   `.topLeading` — so a lowered container above it stretches or grows it exactly
   as the legacy flex line did.

`Layout.node` is the viewport and `Layout.contentNode` the content node, as
before, so `prepaint`, `paint`, `registerScrollRegion`, the clip and the
indicator read the same two rects under both authorities.

**The content node's record is left UNCONSUMED** (critic round 1 finding 2;
prototype P4 consumed it, and the step is deleted). The viewport lowers no item
field of its content, so an unconsumed record is the truthful state: today the
content style carries only `flexDirection`, every item field is at its default
and `reportUnconsumedLoweredItems` names nothing, and a field added to that
style by a later stage **reports** rather than being dropped in silence.

**`flexShrink: 0` is not carried into the lowered content style.** Under the
legacy engine that line stops the freeze loop shrinking the content node below
its max-content size (the type's own doc measures it: 200 vs 508). The kernel
viewport has no freeze loop — it measures its content at an unspecified
scrolling axis and places it at its own answer — so the line has no kernel
counterpart. With the record unconsumed, carrying it does not merely do
nothing: it **reports** `scrollView.flexShrink.unconsumed`. That is **M2d**, and
it is what makes the omission observable at all — consumed, as P4 had it,
neither carrying the field nor failing to consume could be seen by any test.
The behaviour is pinned by A6's shape: the `Text` is 225 wide inside a 100pt
viewport on both sides.

### 3.2 The scrolling axis, and what divergence 54 actually is (`LR-BC`)

The kernel viewport answers **its proposal on the scrolling axis** when it has
one and **its content's answer on the other** (`CN-M`, `CN-F`;
stack-algorithms SC1/SC2/SC4). The legacy viewport node answers whatever the
flex line gives it, which is its content's size floored by CSS §4.5's automatic
minimum. So:

- **the cross axis does not move between the legacy and the lowered
  `ScrollView`.** A10 (a stretching parent with a declared cross size) agrees at
  120 on both sides, because stage 2's stretch wrapper already gives the lowered
  viewport the line's cross size; A11 (a centring parent) agrees at 50, because
  both sides hug. **That is a legacy-vs-lowered agreement, which is a different
  proposition from divergence 54** — 54 is `ScrollView` against
  `ProposalScrollView`, and the lowering **preserves** it (below);
- **the scrolling axis does move, towards SwiftUI.** A7/A10/A11: 60 → 100 (the
  viewport fills the space offered instead of hugging two 30pt rows). A4:
  160 → 100 (the viewport is bounded by its parent instead of overflowing it).
  Probe V1/V2/V3/V4 say that is SwiftUI's answer, and V5 says the hug is
  reachable there only through `.fixedSize()`.

**Divergence 54 survives this stage, and the mechanism is the alias** (critic
round 1 finding 5). The kernel viewport's own cross answer is `content.width`
(`LayoutTree.swift`'s `scrollViewportSize`) — the **`ProposalScrollView`** side.
A lowered `ScrollView` reads its parent's 120 in A10 only because it records a
`LoweredItem`, so stage 2 wraps it in a stretch item frame and
`LoweringState.alias` reports that frame's rect as the element's.
`ProposalScrollView` records none — it calls `requestNativeScrollViewport` and
never `recordLoweredItem` — so `consume` returns `nil` and it gets no such
frame. In a stretching container the two therefore still disagree exactly as 54
says. **54 is removed from stage 6b's retirement row and sent to stage 11 /
task 10**, where `LR-BF` already sends the two scroll types' unification; lane 2
test 2.2 gains an arm that pins the surviving difference as a literal.

Consequence for stage 6b, named here and owned there: the demo's
`.flexGrow(1).flexBasis(Pixels(0)).minHeight(Pixels(0))` incantation on the
scroller `Box` exists only to bound a viewport that hugs its 14 000pt content;
a lowered viewport is bounded by construction.

### 3.3 One clamp, one indicator (`LR-BD`)

`ProposalScrollView.swift:97-170` holds private copies of `clamp`,
both `resolvedOffset` overloads, `paintIndicator`, `indicatorBounds`, `delta`
and `extent` (the design first cited `:94-166`, inherited from CLAUDE.md; line
94 is a call site inside `paint`). They are a copy of a pinned implementation
and therefore unpinned (CLAUDE.md's practice), and they have already drifted:
`ScrollView` seeds `paintIndicator`'s `lastScroll` at `0` and
`ProposalScrollView` at `-Double.infinity` (dead in both, since `withState`
always overwrites it — `StateTable.swift:334-342`).

The fold is a `ScrollChrome` value — axis, corner radius, indicator visibility
— holding all seven, which both elements build **computed from their existing
stored properties**. Nothing gains or loses a stored property on a public type,
so no `swift package clean` is needed and the incremental-layout hazard is not
touched.

**The doc comments move with the code.** Four pieces of prose at the old sites
are the only record of why their lines exist, and a fold that leaves them
behind loses exactly the evidence the mutations are named for: the prepaint
overload's overscroll measurement ("twenty −37 events stored 740, seventeen of
the twenty dead"), `paintIndicator`'s `offsetBy: .zero` rationale, the
`guard alpha > 0` / `requestAnotherFrame()` ordering note, and why `.hidden` is
checked first. Lane 1 carries all four to `ScrollChrome`.

Two things do **not** fold:

- the two `resolvedOffset` overloads stay two functions, because `PrepaintPass`
  and `PaintPass` have no common protocol and `Passes.swift` records why one
  must not be invented. They fold from four copies to two;
- `ScrollContext` publication stays `ScrollView`'s alone (`LR-BF`).

### 3.4 `ScrollContext` across a native viewport (`LR-BF`)

Nothing changes. The context is published from `ScrollState` during layout and
its `viewportExtent` is written by the prepaint `resolvedOffset` from the
element's `bounds`, which `Frame.bounds(of:)` resolves through stage 2's alias.
Prototype P4 reads the same context under both authorities.

`ProposalScrollView` gains **no** publisher. Nothing can read one: no proposal
element reads `pass.scrollContext`, and `List` is an `ElementGroup`, not a
`ProposalElementGroup`, so it cannot be a `ProposalScrollView`'s content at all.
Publishing one would be exactly the declared-but-inert shape CLAUDE.md's table
exists to keep out. Named deferral: whoever unifies the two scroll types (stage
11 / task 10's two-axis scrolling) owns it.

### 3.5 `Component` distribution without `setStyle` (`LR-BG`, `LR-BH`)

- `ComponentModifierOp.amend` stops carrying a `(inout Style) -> Void` closure
  and carries a **`Size<Dimension>` patch** — the only thing `width`/`height`
  ever wrote. The legacy branch applies the patch through `setStyle` exactly as
  before; the lowered branch registers **one native frame per member** with the
  patch's declared axes. No diagnostic is needed for "an amend wrote something
  other than a size", because after this change nothing can.
- The frame's alignment is **per axis**: `.center`'s factor on an axis the patch
  declares, `0` on an axis it leaves `auto` (§2.3's correction; probe W7–W9
  with W2/W5 as the consistency check, the legacy agreement as the ground).
  The same value is recorded as the item's `contentAlignment`, so the parent's
  item frame places the member the same way.
- **`loweredComponentFrame` consumes and plans the member's own record**
  (critic round 1 finding 8). As first specified it registered a `.frameLayer`
  frame around the member and recorded *that*; the parent consumed the frame
  and the **member's** record was left unconsumed, which
  `reportUnconsumedLoweredItems` turns into `<site>.<field>.unconsumed` for any
  non-default item field — and in a production frame every report is a **trap**.
  `MyComponent().width(70)` over a member declaring `.flexGrow(1)` would work
  under the legacy authority and abort under the proposal one at 6b. So it
  consumes the member's record and plans it through `planLegacyItems` exactly as
  `lowerLegacyLayer`'s single-node arm does. (`.wrap` already did, through
  `lowerLegacyNode` — which is why arm C3 agrees and the hole survived P4: none
  of C1–C7 has a member with an item field.)
- **Corrected in lane 4 (`LR-BO` item 1): "the frame lowers with the field
  applied" is wrong for `flexGrow` and `margin`.** Planning at
  `parentKind: .stack` — which is what "exactly as `lowerLegacyLayer`'s
  single-node arm does" means — makes a stack parent IGNORE a child's
  `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf` and `margin` (`LR-AZ`,
  `MC-Q` finding 7). The parent kind stays `.stack` and those fields are
  consumed and **dropped**: a rect disagreement the harness prints, never a
  report and never a 6b trap. A `minSize` on an `auto` axis IS planned, into
  the item frame W, and that is the only arm mutation M4g can redden.
- `.wrap` (a `.padding`) lowers through `lowerLegacyNode(style, declared: style,
  children: [current], site: .component)` — the padding wrapper is an ordinary
  one-child legacy container. Prototype arm C3 agrees.
- A **`.frame` layer over several member nodes** (`ModifiedElement` over a
  multi-member `Component`, divergence 56) lowers to a native linear stack
  (horizontal, spacing 0, the spec's alignment) of **one native frame per
  member**, each carrying the whole `FrameSpec`. The `frame.multipleNodes`
  diagnostic row is deleted.
- **That multi-child arm must PLAN the members' item fields** (critic round 1
  finding 7). `lowerLegacyLayer` consumes every child's record up front but runs
  `planLegacyItems` only at `children.count == 1`, leaves `plans` as default
  `LegacyItemPlan()`s (which `registerLegacyItems` turns into a no-op) and
  returns `.first`. Today the `frame.multipleNodes` diagnostic short-circuits
  before any of that; deleting the row makes the path live, and with the plans
  defaulted **every member's `minSize`, `maxSize`, `margin`, `alignSelf` and
  `flexGrow` would be consumed and dropped with no diagnostic**. Lane 5 runs
  `planLegacyItems(received, parent: declared, parentKind: .stack,
  parentSite: .modifierLayer, fields: &fields)` for `count > 1` too and rows
  `registerLegacyItems(children, plans)` **in full** rather than taking `.first`.
  **What that planning does and does not carry is `LR-BO` item 1's answer again**
  (`LR-BP` item 1): at `parentKind: .stack` a member's `margin`, `flexGrow`,
  `flexShrink`, `flexBasis` and `alignSelf` are consumed and **dropped**, and a
  `minSize` on an `auto` axis is the only field the plan applies — into the item
  frame W. The planning's other purpose is the consume itself, which keeps
  `reportUnconsumedLoweredItems` — and so a 6b trap — off a member that declares
  any of them.
- Both amend frames and per-member frames record `kind: .frameLayer`, so a
  parent stretches them only on an axis they leave `nil` (`MC-Q` finding 7).

**What still diverges from SwiftUI, and why it cannot close here.** SwiftUI's
framed members stay siblings of the enclosing stack (W1's 148 = 70 + 8 + 70,
the 8 being the *stack's* spacing). MetalUI's `ModifiedElement.requestLayout`
returns **one** `LayoutNodeID`, so the framed members are one flex item of the
parent. Closing that needs `ElementGroup`'s associated-type change ruling `TB-M`
names; stage 11 owns it.

## 4. The lowering table after stage 3

### 4.1 `ScrollView` (site `scrollView`)

| what | lowers to | note |
|---|---|---|
| the content children | `lowerLegacyNode` at site `scrollView`, style = `flexDirection` only | stage 2's container lowering entire |
| a scroller child's **unequal grow weights** | `scrollView.flexGrow.weights` | `lowerLegacyNode` passes `site:` to `planLegacyItems` as `parentSite:`, and that is the **only** entry raised there — every other per-child entry is raised at the child's own site (`LR-BM` item 1). This is one of the two routes that keep the case reachable |
| the content node's own record | **left unconsumed** | nothing reports today (all defaults); a future field on that style reports rather than vanishing (§3.1) |
| `flexShrink: 0` on the content node | **nothing** (carrying it reports) | no kernel freeze loop (§3.1); **M2d** |
| `overflow: .scroll` on the viewport | **nothing** | already inert (CLAUDE.md's table) |
| the viewport | `requestNativeScrollViewport(child:axis:)` | `CN-M`, `CN-F` |
| the element's own item fields | a `LoweredItem` with a default `Style()` | it has no modifier surface |
| `$anim-content` / `$anim-viewport` | unchanged; structure reads the declared style and lengths the animated one | `LR-AS` |
| `cornerRadius`, `indicatorVisibility` | not layout — paint and prepaint, shared through `ScrollChrome` | `LR-BD` |

**Nothing at site `scrollView` reports for the shapes stage 2 lowers** — which
is what the demo exercises, and what §7's report pins. The site stays in
`LoweringSite`, and `UnlowerableField.owningStage`'s `case .scrollView` with it,
for the two reachable routes in the table above: a scroller child's **unequal
grow weights**, reporting `scrollView.flexGrow.weights` through `parentSite:`,
and a field carried onto the unconsumed content style. The design's first
writing gave the reason as "`LoweredItem.site` names it in a `…unconsumed`
report", which is unreachable: the viewport's record is `declared: Style()` and
`ScrollView` is not a `StyledElement`, so it has no modifier surface to set an
item field with (critic round 1 finding 9). **Critic round 1's replacement was
itself half wrong** and is corrected in lane 2 (`LR-BM` item 1): it named
`alignSelf: .baseline` and a percentage `flexBasis` as well, and both report at
the **child's** site — `planLegacyItems` raises exactly one entry at
`parentSite:`, `flexGrow.weights`, and every per-child entry at `item.site`.
Test 2.5 (c) produces `scrollView.flexGrow.weights` on purpose, so the case is
pinned live rather than asserted live, and
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `ScrollView` arm uses
the same shape.

### 4.2 `Component` (site `component`)

| what | lowers to | note |
|---|---|---|
| `.width(p)` / `.height(p)` (amend) | one native frame per member, per-axis alignment | `LR-BG`; divergence 48's SwiftUI answer |
| `.padding(p)` (wrap) | `lowerLegacyNode` per member at site `component` | agrees with legacy (C3) |
| `.frame(…)` over **one** member node | unchanged (`lowerLegacyLayer`'s frame arm, `LR-H`) | |
| `.frame(…)` over **several** member nodes | a row of per-member frames, at site `modifierLayer` | `LR-BH`; divergence 56's SwiftUI answer. Each member's record is consumed and planned as the single-node arm's is, so the same fields are dropped (`LR-BO` item 1, `LR-BP` item 1) |
| a non-size amend | **not expressible** | the op's payload becomes `Size<Dimension>` |
| a member's `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`, `margin` | consumed and **dropped** | `LR-BO` item 1; a stack/frame parent ignores them (`LR-AZ`) |
| a member's `minSize` on an `auto` axis | the item frame W's minimum | `LR-BO` item 4 |
| anything at all | **nothing reports at site `component` any more** | `LR-BO` item 2: the amend's record is `.frameLayer` (skipped) and both ops plan exactly one child, so neither can raise `flexGrow.weights` |

## 5. API and files

All `internal` except where noted; `@testable` tests reach them.

```swift
// Sources/MetalUI/ScrollChrome.swift (NEW, lane 1; LR-BD)
/// The clamp, the offset resolution and the fading overlay indicator, shared by
/// `ScrollView` and `ProposalScrollView`. Built COMPUTED from each element's
/// own stored properties, so neither public type's storage changes.
struct ScrollChrome {
    var axis: ScrollAxis
    var cornerRadius: Pixels
    var indicatorVisibility: ScrollIndicatorVisibility

    static func clamp(offset: Double, content: Double, viewport: Double) -> Double
    func extent(_ size: Size<Pixels>) -> Double
    func delta(_ value: Double) -> Point<Pixels>
    func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        contentNode: LayoutNodeID, pass: PrepaintPass) -> Double   // clamps AND writes back
    func resolvedOffset(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                        contentNode: LayoutNodeID, pass: PaintPass) -> Double       // clamps, no write-back
    func paintIndicator(_ id: GlobalElementID, bounds: Bounds<Pixels>, offset: Double,
                        contentNode: LayoutNodeID, pass: inout PaintPass)
    func indicatorBounds(bounds: Bounds<Pixels>, thumb: Double, travel: Double) -> Bounds<Pixels>
}

// ScrollView.swift (lanes 1–2)
extension ScrollView { var chrome: ScrollChrome { … } }   // computed
// `ScrollView.clamp` is DELETED, not kept as a forwarder: five assertions name
// it (ScrollViewTests.swift:78,79,80,89,97) and nothing in Sources/ will once
// the fold lands, so a forwarder is a production member with no production
// caller. The five re-point at `ScrollChrome.clamp` in lane 1.

// ProposalScrollView.swift (lane 1): :97-170's seven private members deleted,
// replaced by the same computed `chrome` and six forwarding call sites — with
// their four load-bearing doc comments moved to ScrollChrome (§3.3).

// LegacyLowering.swift (lanes 2, 4, 5)
extension LayoutPass {
    /// One component amend as a per-member native frame (LR-BG). CONSUMES and
    /// plans the member's own record, as lowerLegacyLayer's single-node arm does.
    func loweredComponentFrame(_ node: LayoutNodeID, _ size: Size<Dimension>) -> LayoutNodeID
    /// Centred on each axis `size` declares, leading on the others (LR-BG;
    /// the legacy agreement, with probe W7-W9/W2/W5 as the consistency check).
    func componentFrameAlignment(_ size: Size<Dimension>) -> ProposalAlignment
    /// `proposalAlignment` loses its `private` (both of the above call it).
}
// lowerLegacyLayer gains the `children.count > 1` arm (LR-BH), which PLANS the
// members' item fields and rows registerLegacyItems(children, plans) in full
// rather than returning `.first`;
// legacyFrameLayerDiagnostics loses its `frame.multipleNodes` row.

// Component.swift (lane 4)
enum ComponentModifierOp {
    case amend(Size<Dimension>)      // was: (inout Style) -> Void
    case wrap(Style)
}
```

**Shared files touched**: `ScrollView.swift`, `ProposalScrollView.swift`,
`ScrollChrome.swift` (new), `Component.swift`, `LegacyLowering.swift`, and
`LayoutAuthority.swift` — **corrected by the branch checker**: this paragraph
said "doc comments only" of `LayoutAuthority.swift`, and lane 3 adds a
`CaseIterable` conformance to the internal `LayoutAuthority` there (§6 lane 3's
own text says so; record §25 §9 and record §05's 2026-09-22 section record it).
Doc comments only in `LoweringState.swift` (`Kind.leaf` now also names a lowered
viewport), plus — also omitted from the original list, recorded at record §25
line 416 — one renamed citation each in `Hitbox.swift`, `StateTable.swift` and
`Window.swift` (`ScrollView.resolvedOffset` → `ScrollChrome.resolvedOffset`).
**Not touched**: `Frame.swift`, `Passes.swift`, `LayoutTree.swift`,
`List.swift`, `ModifiedElement.swift`, `Box.swift`, `ElementGroup.swift`
(verified on the branch diff).

**New test files**: `Tests/MetalUITests/LoweringScrollTests.swift` (lanes 2–3),
`Tests/MetalUITests/LoweringComponentTests.swift` (lanes 4–5).
**Amended**: `ScrollRoutingTests.swift`, `ScrollIndicatorTests.swift`,
`ScrollViewTests.swift` (lane 3), `LayoutAuthorityTests.swift`,
`LoweringItemTests.swift`, `LoweringCorpusTests.swift`,
`LoweringStackAndLayerTests.swift`.

**No new typecheck guard is planned**: every addition is internal and no public
spelling changes. A lane that adds one mutates it red once.

**`swift package clean` is a measurement in lane 4, not an assertion.** No
stored property on a public type moves in lanes 1–3 or 5 (§3.3). Lane 4 changes
`ComponentModifierOp.amend`'s payload from a 2-word closure to a
`Size<Dimension>`, and `ComponentModifierOp` is the element type of `ops` on the
**public** generic `StyledComponent` — an `Array` is one word either way, so the
reasoning says no clean is needed, but that is the exact shape CLAUDE.md records
as having been wrong three times. Lane 4 builds incrementally first and records
the result, then cleans and rebuilds; either outcome is written down (critic
round 1 finding 12).

## 6. Lanes

Each lane's tests are written first and read red — for a lowering test "red
before" means **a diagnostic in the report or a literal mismatch in a test that
compiles against stage-2 API**, so no red run truncates the suite — except tests
marked **characterization** (green on arrival; their mutation is their evidence)
and **divergence pins** (a `try #require` that the two authorities disagree,
both sides' rects literal or derived, and a mutation *towards* the legacy answer
that reddens them). Every mutation: commit first, `cp` the file aside, apply,
native build, full unfiltered `swift test --build-system native --no-parallel`,
restore from the copy, `git status --short` empty; the lane's record names
**every** test it reddens, not only the count. Every lane ends with the full
suite (its count read from the summary line), the goldens check (`git diff
--name-only 57893d0 HEAD -- 'Tests/**/*.json'` empty), the twelve `CN-R` images
and the lock probe (§8).

"Agrees" means `LayoutDifferential.compare` reports an empty `unlowerable`,
`disagreeing` empty, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual` and
`stateSlotsEqual` true, with `try #require(report.elements == N)` for an `N`
derived by hand before the run.

**A red-before is never taken through a real `Window` under the proposal
authority.** `Window` never sets `reportsUnlowerableFields` (`Window.swift`'s
`Frame(...)` call passes `layoutAuthority` and `recordsElementBounds` and
nothing else), so `noteUnlowerable` takes its `preconditionFailure` branch and
the process aborts: no summary line, no list of what failed. Such a trap is
pinned by an **exit test** and nothing else (critic round 1 finding 1). This is
why lane 3 runs after lane 2.

**Predicted test count, per lane.** Parameterised scenarios count as **one**
each, so lane 3's 37 re-spellings move nothing. Re-derive before each run; a
deviation from the prediction is a finding, not a rounding.

| lane | new tests | predicted total |
|---|---|---|
| — | baseline at `57893d0` | **1550** |
| 1 | 1.1, 1.2, 1.4 — 3 (1.3 and the exit-test trap arm are arms of existing tests) | **1553** ✓ measured |
| 2 | 2.1, 2.2, 2.2a, 2.3, 2.4, 2.5, 2.6, 2.7 — 8 (A2b is an arm of 2.1) | **1561** ✓ measured |
| 3 | 3.4, 3.5 — 2 (3.1–3.3 parameterise in place) | **1563** ✓ measured |
| 4 | 4.1–4.6 — 6 (C3a and the `minWidth` arm are arms, not tests) | **1569** ✓ measured |
| 5 | 5.1, 5.1a, 5.2 — 3 (5.3 amends, 5.4 re-runs) | **1572** ✓ measured |

### Lane 1 — the shared scroll chrome (`LR-BD`)

The only lane that changes behaviour reachable by **production**: it edits
`ScrollView` and `ProposalScrollView` under both authorities. It must move no
pixel and no test.

Files: `ScrollChrome.swift` (new), `ScrollView.swift`, `ProposalScrollView.swift`;
tests `LoweringScrollTests.swift` (new).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aProposalScrollViewClampsAStoredOffsetPastTheEndAndWritesItBack` — `ProposalScrollView`'s half of `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind` and of `aStoredOffsetPastTheEndIsClampedWhenItIsRead`, driven through a real `Window` with wheel events; the numbers derived from the fixture, not copied | **characterization** — `ProposalScrollView`'s clamp was never pinned | **M1a** the prepaint overload's write-back deleted (must redden this **and** `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`) |
| 1.2 | `aProposalScrollViewsIndicatorFadesOnTheSameRampAndIsClippedLikeTheContent` — `ProposalScrollView` arms of `theIndicatorFadesOnARampAndTakesItsColourFromTheScrollIndicatorToken`, `theThumbIsProportionalAndFlooredAtTwentyPoints`, `theThumbReachesTheEndOfItsTrackAtMaximumOffset`, `theIndicatorIsClippedByTheViewportsRoundedCornerWithoutScrollingWithIt`, `hiddenEmitsNoIndicatorRect` | characterization | **M1b** the indicator's clip given `delta(-offset)` instead of `.zero`; **M1c** the 20pt thumb floor removed; **M1d** `.hidden` checked after `requestAnotherFrame()`. **Built, `LR-BL` item 2**: M1d changes no rect, so the `.hidden` arm reads `Frame.wantsAnotherFrame` on both halves of its differential or M1d reddens only `hiddenIndicatorDoesNotKeepTheWindowDirtyOrTheLinkAwake` |
| 1.3 | `aNeverScrolledScrollViewPaintsNoIndicatorOnTheWindowsPreTickFirstFrame` gains a `ProposalScrollView` arm | characterization. (The first writing said "the fold is what makes the second arm exist" — false: `ProposalScrollView` already reads `ScrollState()` at `57893d0`, so the arm is writable and green today. It is the fold that must not change it) | **M1e** `ScrollState.lastScrollTime`'s default set to `0` (must redden both arms) |
| 1.4 | `theTwoScrollElementsShareOneChromeImplementation` — the same fixture (same axis, corner radius, content extent, offset, timestamps) rendered as a `ScrollView` and as a `ProposalScrollView`, asserting the **indicator rect and colour are equal** and the clamped offsets are equal. The fixture's **content fills the cross axis**, so the `try #require` that the two viewport rects agree first is satisfiable — divergence 54 is a cross-axis difference between exactly these two types (`LR-BC`), and a hugging fixture would fail the require rather than pass it. **Built, `LR-BL` item 3: two content heights, not one** — at 200 over a 100pt viewport the thumb is the proportional 50 and the floor is inactive, so M1f's 30pt floor answers the same number; the 1000pt arm is where the floor decides it | **characterization**, green at `57893d0`: the two implementations are line-equivalent and both `lastScroll` seeds are dead (`withState` always overwrites), so there is no discriminator before the fold. The first writing claimed RED here and was wrong | **M1f** (replacing the old one, which post-fold moved both sides together): **re-inline a private copy of `paintIndicator` into one element with a different thumb floor** — the drift this test actually guards |

Existing pins that must stay green, named because they are the regression
surface: all 14 `ScrollIndicatorTests`, all 16 `ScrollRoutingTests`, all 7
`ScrollViewTests` (five of whose assertions move from `ScrollView.clamp` to
`ScrollChrome.clamp`, §5), `aNestedScrollViewInsideAScrolledOneGetsAnEmptyContentMask`,
`aClippedBoxInsideAScrolledScrollViewClipsWhereItPaints`,
`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`.

**Also in lane 1, for lane 3**: one arm added to the existing exit test
`aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority` —
a proposal-authority `Window` holding a `ScrollView` exits non-zero. It passes
at this HEAD and is lane 3's whole red-before; lane 2 converts it to an
agreement arm. It is an arm, not a new test, so the count does not move for it.

**Before lane 3 (taken here, recorded here): attribute or retire §1's
unattributed baseline issue. RETIRED — it did not reproduce** in three
unfiltered whole-log runs at the baseline tree (52.087 s, 51.817 s, 52.674 s,
all `Test run with 1550 tests in 1 suite passed`) or in any of the lane's six
later green runs. Run the suite unfiltered, **whole log kept**, enough times to
name it or to retire it as not reproducing. Lane 3 takes the count of real `Window`s in
those two suites from 37 to 74 — each a Metal device on one shared main run
loop — and four of the scenarios are display-link timing tests, so an
unattributed flake living there would double in rate and land in the exit test.

**Demo expectation**: **all twelve images 0 px** — and this lane is the one
where a non-zero reading is a real finding rather than an expectation, because
its edit is on the production path under both authorities. *Measured: 0 in all
twelve, twice in the lane and twice again in the verification round. **But the
twelve images never paint an indicator** — none of the scenes is ever scrolled,
so `alpha` is 0 and `paintIndicator` returns at its guard — so this expectation
covers the clamp, the prepaint write-back and the content clip only, and the
indicator half of the fold is pinned by M1b–M1e alone (record §7.6, §12.3).*

### Lane 2 — the `ScrollView` lowering (`LR-BB`, `LR-BC`)

Files: `ScrollView.swift`, `LoweringState.swift` (doc), `LayoutAuthority.swift`
(doc); tests `LoweringScrollTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aLoweredScrollViewAgreesWithTheLegacyEngineOnEveryBoundedShape` — prototype arms A1, A2, A5, A8, A9 (6, 8, 4, 4, 7 ids) plus lane 2's **A2b** (5 ids), each agreeing, `try #require` on the id counts | `scrollView.noLowering` | **M2a** the viewport registered as a plain native leaf (A1's content rects collapse); **M2b** the content node registered through `requestNativeLinearStack` directly instead of `lowerLegacyNode` — which moves **A2b's** centred row, not "A2's stretch rows" as first written: every other arm's content is fixed-size leaves the container lowering is a no-op over, so a bare stack is geometrically identical and M2b reddened only the diagnostics tests (`LR-BM` item 2b) |
| 2.2 | **divergence pin** `aLoweredScrollViewFillsItsProposalOnTheScrollingAxisWhereTheLegacyViewportHugs` — A7 (`Row` parent 120×100: viewport (0, 20) 50×60 → (0, 0) 50×100, both children up 20), A11 (`Column` parent: the same), and the agreeing-cross-axis control A10 (**120 on both sides**), each with `try #require` that the two authorities disagree before the equalities are read | reported | **M2c** the viewport lowered as a `fixedSize` over the content (both sides read 60 and the pin's `#require` fails) |
| 2.2a | **divergence pin** `divergence54SurvivesTheLoweringBecauseOnlyAScrollViewRecordsAnItem` — a lowered `ScrollView` and a `ProposalScrollView` as the two children of **one** stretching lowered `Box` with a declared cross size: the `ScrollView` takes the line's cross size through stage 2's stretch item frame and the alias, the `ProposalScrollView` keeps its content's (`LR-BC` amended, critic round 1 finding 5). `try #require` the two disagree; both rects literal | reported (the `ScrollView` half) | **M2i** `recordLoweredItem` dropped from the lowered `ScrollView` (the two agree and the `#require` fails — which is also how the surviving divergence would silently close) |
| 2.3 | **divergence pin** `aLoweredHorizontalScrollViewIsBoundedByItsParentWhereTheLegacyOneOverflows` — A4: viewport 160×50 → 100×50, `scenesEqual` and `hitboxesEqual` both **false** and asserted false | reported | **M2c** |
| 2.4 | `aLoweredScrollViewsContentKeepsItsNaturalExtent` — A6's shape: the `Text` is 225 wide inside a 100pt viewport on **both** sides (the width derived from the shaping cache, `LR-F`), and the height disagreement (40 → 16) is asserted as stage 2's single-child stretch elision with `LR-AC` named | reported | **M2d** (restated, critic round 1 finding 2) `flexShrink: 0` carried into the lowered content style: with the record left unconsumed this **reports** `scrollView.flexShrink.unconsumed`. One edit. (The first writing had the record consumed, which made this mutation inert — a consumed record is skipped by `reportUnconsumedLoweredItems`) |
| 2.5 | `aLoweredScrollViewRecordsItsViewportAsItsItemAndKeepsItsSiteReachable` — three things: (a) a **horizontal** `Box { ScrollView { … } }.alignItems(.stretch)` with a declared cross size stretches the viewport, read three ways (element rect, scroll region, the content leaf's `contentMask`); (b) the content node's record is left unconsumed and the viewport's is consumed, asserted structurally on `Frame.lowering`, and with only `flexDirection` on that style **nothing** reports; (c) two scroller **children** with unequal `flexGrow` factors report **`scrollView.flexGrow.weights`** — the route that keeps `LoweringSite.scrollView` and `owningStage`'s `.scrollView` branch reachable (§4.1; `LR-BM` item 1 corrects critic round 1's `alignSelf: .baseline`, which reports at the child's site) | reported | **M2e** (restated) the content node registered with `site: .modifierLayer` — (c) reads the wrong site; **M2f** the viewport not recorded (its parent stops stretching it) |
| 2.6 | `aLoweredScrollViewKeepsItsTwoAnimationSlots` (`LR-BE`) — `$anim-content` and `$anim-viewport` still hold distinct entries under the proposal authority, and `theSevenRetentionSlotsAreMutuallyDistinct` still passes | reported | **M2g** both `animated(…)` calls given the bare `id` |
| 2.7 | `aLoweredScrollViewRegistersAHandDerivedAmountOfNativeWork` (`SA-M`) — A1's tree, `LayoutTree.lastNativeLayoutWork`'s calls/hits/misses and the node count **derived by hand in the doc comment before the first run** | written against stage-2 API, so it compiles; the report carries `scrollView.noLowering` and the literals mismatch | **M2h** the content node registered twice |

**Amended pins** (each with the red run it answers, from prototype P4):
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (its `ScrollView` arm now
expects `[]` and an agreeing render);
`anItemFieldNoLoweredContainerConsumesIsReportedByName` (its "legacy
`ScrollView`" arm becomes an agreement arm: the field is consumed, not
reported); `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (§7).

**Demo expectation**: eight legacy images 0 px (no production root lowers); two
preview images 0 px (`ProposalScrollView` untouched by this lane); the 560²
pair 0 px. **Measured: 0 in all twelve, every scene dump byte-identical**, with
all eight of §8's control figures reproduced by a rebuilt harness (`LR-BM`
item 4). Screen **locked** at the end of the lane, so no real-window capture.

### Lane 3 — the scroll suites under both authorities (the exit test, `LR-BI`)

**Runs after lane 2**, and its red-before is lane 1's single exit-test arm, not
a red run of these suites: until the lowering lands a proposal-authority
`Window` **aborts the process** rather than failing a test (§6's preamble;
critic round 1 finding 1). The lane's evidence is its mutations — **M3a**,
**M3b**, lane 2's **M2a** and **M2d**, lane 1's **M1c**.

Files: `ScrollRoutingTests.swift`, `ScrollIndicatorTests.swift`,
`ScrollViewTests.swift`, `LoweringScrollTests.swift`.

**Census first.** `ScrollViewTests` was added to this lane without appearing in
task 7's §4.2 dependency census. Take its census before parameterising: if it
registers no custom legacy node, the record says so; if it does, that type
re-spells as a native probe leaf like the other two. **Taken: it declares no
custom element** — no `requestNode`, no `requestLeaf`, nothing to re-spell
(`LR-BN` item 2).

The two custom test elements — `ScrollContextRecorder` (5 call sites) and
`HitboxProbe` (2) — register through the public legacy `requestNode`, which is
`customElement` under the proposal authority. Each grows the `ProbeLeaf` shape:
`pass.lowersToProposal ? pass.frame.requestNativeLeaf { … } : pass.requestLeaf(…)`,
answering the same size from the same `Style`. §4.2's census counted **9**
legacy registrations from `ScrollRoutingTests` in its filtered run, across those
two types.

Every scenario in the two suites becomes `@Test(arguments: LayoutAuthority.allCases)`
(a `CaseIterable` conformance is added to the internal enum) and builds its fake
window under the argument. A parameterised test counts as **one** test in the
summary line, so the suite total does not move for these.

**Seven fixtures declare a cross axis they used to leave `.auto`** (`LR-BN` item
3, unforeseen by the design). A `ScrollView` whose only child declares just the
scrolling axis relied on the legacy engine stretching it across the definite
viewport; the kernel viewport's cross answer is its content's (`CN-M`) and a
single child is exempt from the stretch item frame (`LR-AC`), so the same
fixture measures a **0-wide viewport centred at the window's midpoint** under
the proposal authority — measured at 120×100: `(0, 0) 120×100` legacy against
`(60, 0) 0×100` lowered. That is stage 2's ruled divergence, pinned by 2.4, not
what these scenarios are about. Declaring the cross axis **moves no legacy
number**: the stretch already produced exactly these values, which is what the
34 unchanged legacy arms say.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | the 16 `ScrollRoutingTests` scenarios, each under both authorities: wheel routing, the topmost-region ranking, momentum, the clipped nested region, the horizontal axis, the overscroll write-back, the `Deferred` scrim pair, the nested-scroller wheel | lane 1's exit-test arm (a proposal-authority `Window` over a `ScrollView` exits non-zero). **Not** a red run of these suites: that aborts the process and records nothing | **M3a** `registerScrollRegion` given the content node's rect instead of the element's; ~~**M3b** the bounds alias dropped in `Frame.bounds(of:)` (the lowered arms' regions move)~~ — **built: M3b reddens 34 tests and no scroll scenario among them** (`LR-BN` item 5). No fixture in these suites has a lowered parent that stretches or grows its scroller, so the alias is inert in all of them; the claim is pinned by lane 2's `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` and stage 2's `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap`, both of which it reddens |
| 3.2 | the 14 `ScrollIndicatorTests` scenarios under both authorities, including the display-link pause/wake pair and `.hidden` | as 3.1 | **M2a** (the viewport a plain leaf: the thumb ratio changes) — re-taken: **31** tests, where lane 2 read 8; **M1c** — re-taken: `theThumbIsProportionalAndFlooredAtTwentyPoints` under **both** authorities |
| 3.3 | **4** of the 7 `ScrollViewTests` scenarios under both authorities, `aScrollViewOfTextDoesNotShrinkItsContentToTheViewport` included. **Built: 4, not 7** — the other three call `ScrollChrome.clamp` with three `Double`s and take no authority in their call path (`LR-BN` item 2). The census `LR-BI` asked for: the file declares **no** custom element, so nothing in it re-spells | as 3.1 | **M2d** — re-taken: at this HEAD it **aborts the process** at 3.5, naming `scrollView.flexShrink.unconsumed` on `stderr`, after lane 2's ten tests have already recorded issues (`LR-BN` item 5) |
| 3.4 | `everyScrollScenarioRanUnderBothLayoutAuthorities` — the exit test's guard. **Built as a roll call, not a counter** (`LR-BN` item 1): Swift Testing does not specify test order and this toolchain has no `Test.all`, so a counter read early reads zero and passes. `ScrollAuthorityCoverage` holds the 34 names and the one `arguments:` list; `record` verifies the whole set order-independently when the last name arrives, and 3.4 holds the literals | literal mismatch (measured: `Expectation failed: missing.isEmpty`, naming all 34) | **M3c** the `arguments:` list reduced to `[.legacy]` |
| 3.5 | `aScrollContextSurvivesALoweredViewportAcrossTwoFrames` — a **non-`List`** recorder inside the scroller and again after it, two frames through a `Window` per authority, wheel between them, comparing the published `ScrollContext` (offset, viewport extent, axis) frame by frame; the second frame is what makes `viewportExtent` non-zero, so the first frame's zero cannot make it vacuous. **Built with a HORIZONTAL scroller** (`LR-BN` item 3): a vertical one in a bounded wrapper measures 200 under the legacy engine and 100 under the proposal authority, which is `LR-BC` and is test 2.2's subject, not this one's. **Renamed and re-scoped** (critic round 1 finding 4): a `List` under the proposal authority calls `noteUnlowerable(.list, "noLowering")` before any row (`List.swift:351`), so through a `Window` it traps — and under diagnostics, where P4 measured it, it builds **zero** rows, so a `List` arm would be vacuous even there. `List` windowing under the proposal authority is **stage 4's** | **characterization** (P4 read the contexts identical on frame 1) | **M3d** `withScrollContext` moved after the content build; **M3e** the prepaint overload's `viewportExtent` write removed |

### Lane 4 — `Component` amend and wrap (`LR-BG`)

Files: `Component.swift`, `LegacyLowering.swift`; tests
`LoweringComponentTests.swift` (new).

| # | test | red before | mutation |
|---|---|---|---|
| 4.1 | **divergence pin** `aComponentsWidthFramesEachMemberWhereTheLegacyAmendOverwritesIt` — C1 and C2: legacy members 70 wide at x 0/70, lowered 30 and 50 at x **20**/**80**; probe W1/G7 named as SwiftUI's answer | `component.amend` | **M4a** the frame registered around the whole group rather than per member |
| 4.2 | `aComponentsPaddingLowersAsAnOrdinaryOneChildContainer` — C3 agrees (4 ids), plus **C3a** (added in lane 4, `LR-BO` item 4): a member declaring a `margin`, both sides (12, 12, 30, 10) | `component.wrap` | **M4b** the wrap registered as a bare padding without `lowerLegacyNode`. **Over C3 alone it reddens NOTHING** — fixed leaves make `planLegacyItems`, `arrangeLegacyMainAxis` and `paddedAndSized` no-ops, `LR-BM`'s M2b finding again. C3a moves to (8, 8) and reports `box.margin.unconsumed` |
| 4.3 | **divergence pin** `aComponentAmendsFrameIsCentredOnlyOnTheAxisItDeclares` — C7 (`height(20)`: lowered 30×10 at y **5**) and C1's y **0**; the control is the same tree with both axes declared. This is §2.3's correction, pinned | reported | **M4c** the alignment `.center` unconditionally (C1's members move to y 15 — the exact value the prototype read) |
| 4.4 | `theOrderOfAComponentsDistributingModifiersIsObservableUnderBothAuthorities` — C4 and C5: legacy x 4/74 and 4/82, lowered **20**/**80** and **24**/**92**, the lowered pair matching probe G13/G14's 20 and 24 | reported | **M4d** `ops` applied in reverse |
| 4.5 | `chainedComponentAmendsComposeTheSameWayUnderBothAuthorities` — the payload change is internal, so it is pinned by behaviour, not by a guard: `.width(p).height(q)` is two ops and lowers to two nested frames; `.width(p).width(q)` leaves the later one standing (`OM-E`); both read the same outer size under both authorities, with the member rects literal | characterization | **M4e** the two amends collapsed into one frame (the `.width(p).width(q)` arm keeps the earlier value) |
| 4.6 | `anAmendedComponentsMemberItemFieldsAreConsumedAndPlanned` — **three** arms whose **member** declares an item field: `.flexGrow(1)`, a `margin` and (added in lane 4, `LR-BO` item 4) `minWidth(40)` on an `auto` width. The amend must consume and plan the member's record so **nothing reports**. Without it the record is left unconsumed and the `…unconsumed` entries appear — a **trap** in a production frame at 6b, not a divergence (critic round 1 finding 8, `LR-BG`) — **at the MEMBER's site, `box`, not `component`** (`LR-BO` item 3) | reported (`component.amend`) | **M4f** the member's record not consumed (`box.flexGrow.unconsumed`, `box.margin.unconsumed`, `box.minSize.unconsumed` appear); **M4g** consumed but not planned — only the `minWidth` arm can see it (40 wide at x 15 → 0 wide at x 35); the other two are dropped either way |

**Amended pins**: `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`
— the component-amend half no longer traps; it becomes an agreement arm and the
test keeps its `List` half and its name (the name names both). It stays a
**child process** and now requires `EXIT_SUCCESS` with an empty stderr over a
**production** proposal frame carrying both ops in both orders, because a
production frame traps rather than reports and an in-process regression would
end the run with no summary line.
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `Component amend` and
`Component wrap` arms **invert to assert the absence of an entry** (`LR-BO`
item 2: `component` has no reachable report left, and the site survives for
`owningStage`'s trap message alone); its arm count stays 10.
`aComponentsWidthStillOverwritesItsMembersDeclaredWidth`
(divergence 48) keeps its name and its wrong-on-purpose legacy assertion and
gains a sentence naming 4.1 as the proposal-authority answer.

### Lane 5 — a frame layer over several member nodes (`LR-BH`, corrections in `LR-BP`)

Files: `LegacyLowering.swift`; tests `LoweringComponentTests.swift` and
`LoweringStackAndLayerTests.swift` (5.3's arm).

| # | test | red before | mutation |
|---|---|---|---|
| 5.1 | **divergence pin** `aFrameOverAMultiMemberComponentFramesEachMemberWhereTheLegacyLayerSqueezesThem` — C6: legacy one 70×40 frame with members **26** and **44** at y 15; lowered a **140**×40 row with members 30 and 50 at x **20**/**80**, y 15; probe W1/W4 named. **Built, `LR-BP` item 4: the layer's own bounds and a node count as well as the members' rects** — two per-member frames and one row are **+3** native nodes over the same component with no frame, and no rect can see the row at all | `modifierLayer.frame.multipleNodes` | **M5a** the per-member frames rowed at the platform default spacing instead of 0 (140 → 148; reddens 5.1 and 5.1a, **and nothing else — not the demo exit test**, `LR-BP` item 3); **M5b** the spec applied to only the first member |
| 5.1a | `aFrameOverSeveralMembersStillPlansEachMembersItemFields` — the same C6 shape but with the two members declaring `margin` and `minSize`. `lowerLegacyLayer` consumes every child's record up front and today plans only at `count == 1`, returning `.first`; once the `frame.multipleNodes` row is deleted that path goes live, and without planning both members' fields are **consumed and dropped with no diagnostic** (critic round 1 finding 7, `LR-BH`). The margin's offset and the minimum's floor are literal on both sides | reported (`modifierLayer.frame.multipleNodes`) | **M5e** the planning skipped for `count > 1` (the plans stay default and `registerLegacyItems` is a no-op). **Corrected, `LR-BP` item 1: only the `minSize` floor moves** — the margin is dropped at `parentKind: .stack` with or without the planning (`LR-AZ`, `LR-BO` item 1), so the member declaring it reads the same rect either way and M5e reddens exactly one assertion, b's 40×10 at x 100 becoming 0×10 at x 120; **M5f** `registerLegacyItems(children, plans)` reduced to `.first` again (only one member survives) |
| 5.2 | `aFrameOverOneMemberIsUnchanged` — the existing single-node arm still takes `lowerLegacyLayer`'s frame arm, node count by hand (**+1** over the same component with no frame), plus a rect arm asserting the single-node geometry is unchanged on both sides | characterization, green at lane 4's HEAD | **M5c** the `count > 1` arm entered at `count == 1` — which moves **no rect in the whole suite** and reddens this test's node count alone (`LR-BP` item 4) |
| 5.3 | `aHiddenFrameLayerIsReportedAsDisplayNone`'s "two nodes, not hidden" arm re-spelled: it now **agrees** rather than reporting; the hidden arms are unchanged (`display.none` is still checked first and alone, `LR-J`). The arm's value inverts — as an empty expectation it is that test's only discriminator for "first **and alone**" | its literal `[modifierLayer.frame.multipleNodes]` | **M5d** `display.none` checked after the multi-node arm — which **has no subject once the row is deleted** (`LR-BP` item 2); restated as "moved below the style comparison" it is literally stage 1's **M4i**, and reddens the four hidden arms with `[modifierLayer.style]` |
| 5.4 | the exit test re-run and its table re-measured (§7) | — | **M2a**, **M4a**; **not M5a** (`LR-BP` item 3) |

## 7. The exit test

Two tests carry the exit criterion.

**(a) The stage's own exit test**, the brief's: `everyScrollScenarioRanUnderBothLayoutAuthorities`
(3.4) together with the parameterised `ScrollRoutingTests` and
`ScrollIndicatorTests` scenarios (3.1, 3.2). A run in which any of those
scenarios' proposal arm was skipped, or in which the two custom element types
still reached the legacy registrars, fails.

**(b) `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`** keeps its
name and file (`LoweringCorpusTests.swift`) and is amended in lane 2, re-run by
lanes 3–5. Prototype P4's measurement, which the lane checks before writing the
expectation:

1. **The report, exactly.** Modal off: **`[list.noLowering]`**. Modal on:
   **`[stack.position, stack.inset, list.noLowering]`**. `scrollView.noLowering`
   is gone from both; no stage-2 field and no `…unconsumed` entry.
2. **The counts do not move**: `try #require(report.elements == 2036)` and 6
   agreeing / 30 disagreeing (modal off), 2042 / 36 (modal on) — P4 passed both
   `#require`s unchanged.
3. **Three of the thirty rows' lowered rects change**, and only three. Legacy
   values unchanged throughout. **Measured in lane 2, identical to P4's
   prediction in every cell** (the middle row is the `List`'s row `Box`, which
   P4 labelled "the `ScrollView`'s content node"; the content node is not an
   element and has no id):

| row | legacy | lowered before | lowered after (P4; lane 2) |
|---|---|---|---|
| the `ScrollView`'s viewport | (132, 439) 420×0 | (240, 455) 0×0 | (240, 455) 0×**73** |
| the `List`'s row `Box` | (132, 439) 420×0 | **(0, 0)** 0×0 | **(240, 455)** 0×0 |
| the `List` | (132, 439) 420×14000 | (0, 0) 0×0 | (240, 455) 0×**14000** |

   **Modal on, two of those three widths read 420 rather than 0**, and the cause
   is stage 2's, not stage 3's: `Deferred` registers no node of its own and hands
   its child's node straight up, so the lowered content node has **two** children
   with the modal on, the single-child stretch elision (`LR-AC`) stops applying,
   the `List` takes a greedy item frame and reads the 420 its scroller was
   proposed, and the viewport's non-scrolling axis (`CN-M`) reads 420 with it.
   The row `Box` stays 0×0. Recorded as three per-id overrides in the test's
   modal half (`LR-BM` item 3); it disappears when stage 4 lowers `List`.

   The three rows' **widths stay 0** because the `List` reports and builds no
   rows, so the viewport's non-scrolling axis — the content's answer (`CN-M`) —
   is the empty content's 0. That is stage 4's, and cause **4** in the table
   below absorbs it; cause **3** ("`ScrollView` has no lowering") is retired and
   replaced by a row naming what the scroll subtree now contributes.
4. Cause **R** (the harness root offers its proposal, so the demo's greedy
   column fills it) already predicted "the scroller `Box` 0 → 73 tall"; the
   viewport's new 73 is that same 73 arriving one level deeper, which is the
   check the lane makes before believing the number.

Mutations that must redden it: **M2a**, **M2d** (which adds
`scrollView.flexShrink.unconsumed` to the demo's report), **M4a**, and stage 2's
**M1a** and **M2a** (unchanged). **M5a is NOT in this list** (`LR-BP` item 3,
measured): `demoContent()` contains no `.frame` at all — `DemoContent.swift`'s
only two `.frame(` sites are inside `nativeLayoutPreviewContent()` and are
proposal `ModifiedContent` wrappers — so no shape in the demo is a
`ModifiedElement` frame layer over a multi-member `Component` and no lane-5
mutation can reach this test. **M2e** is no longer in this list:
restated as "the content node registered with the wrong `site:`", it does not
change the demo's report, because the demo's scroller children produce no
item-field entry — 2.5 (c)'s unequal-`flexGrow` arm is what sees it (`LR-BM`
item 1).

## 8. Demo, pixels and captures

At the end of **every** lane, against `57893d0`, the twelve `CN-R` images (eight
legacy demo, two preview, two 560² two-authority chrome), generated by the
`CN-R` harness into a `git archive` of the lane's commit,
`DEMO_PIXELS_SMALL=1`, with the controls read **non-zero first**: light vs dark
1 048 576; default vs modal 1 030 498; default vs animation 210 027; f0 vs f3 0;
preview light vs dark 1 048 576. **Expected: 0 in all twelve at every lane.**

**The generator is not in the repository, and lane 1 had to rebuild it**
(`LR-BL` item 6): record §18's `scratchpad/harness/gen-lib.py` lived in a
session scratchpad and is gone. The rebuilt one is a test file injected into the
archive (`@testable import MetalUIDemoContent`, twelve images through a real
`Window` over `FakePlatformWindow`, raw BGRA plus a scene dump each). **Its
controls are what prove it is the same instrument** — on an archive of
`57893d0` it reproduces all five recorded figures exactly, plus record §18's two
distinct-value counts (544 for `default-light-f0`, 216 for `chrome-legacy`).
A later lane that rebuilds it again checks itself against those seven numbers.

- **Lane 1 is the one that can genuinely move a pixel** (it edits production
  paint on both authorities and the preview's `ProposalScrollView`). A non-zero
  reading there stops the lane. *Verification round: it read 0, and the reading
  is **blind to the indicator** — no scene among the twelve is scrolled, so no
  thumb is painted in any of them (measured by scanning every scene dump for the
  3pt cross-axis rect: zero hits). The pixel evidence covers the clamp, the
  prepaint write-back and the content clip.*
- Lanes 2–5 touch only the proposal-authority branch of legacy elements, which
  no production frame takes until stage 6b, so 0 is by construction; the images
  are still taken, because "by construction" has been wrong before.
- The two-authority chrome pair (`DifferentialRoot(560) { Column { CounterPanel() }.width(560) }`
  through a 560² fake `Window` per authority) must read 0 with stage 1's **M5d**
  as its control.

**Real-window captures.** The screen was **unlocked** when this design was
written; it has been **locked at the end of every lane since** (1, 2 and 3), so
no capture has been taken. Before any capture:
`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate`; capture only if it prints no `CGSSessionScreenIsLocked` line
and `displayAsleep main: 0`. Then
`docs/probes/window-capture/capture.sh <scratch dir> 57893d0 <lane HEAD>` and
record its table. `IOConsoleLocked` is never read (`FR-V`). Take them at
**lane 1's** HEAD and at the stage's HEAD; lane 1's is the load-bearing one.

## 9. What must not move

Each row names how the stage checks it rather than asserting it.

| invariant | check |
|---|---|
| production runs the legacy authority | the twelve `CN-R` images, every lane (§8) |
| `List` windowing (`MP-`, `TB-`) | **under the LEGACY authority only this stage**, which is what production runs: all `ListTests` green every lane. The mechanism `List` windows against — `ScrollContext` across a lowered viewport — is checked by 3.5's two-frame comparison with a **non-`List`** recorder. A `List` under the proposal authority cannot be measured here at all: it traps through a `Window` and builds zero rows under diagnostics (critic round 1 finding 4). **Stage 4 owns the proposal half** |
| wheel routing and the one hitbox list (divergence 16, `IN-`) | 3.1's 16 scenarios under both authorities; **M3a** (which reddens `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove` under both). **M3b is not evidence here** — it reddens 34 tests and no scroll scenario, because no fixture in these suites has a lowered parent that stretches its scroller (`LR-BN` item 5); lane 2's `aScrollViewInsideASingleChildLegacyFrameKeepsItsViewportAndWheel` is |
| scroll direction | 3.1's `aHorizontalScrollViewMovesOnDeltaXNotDeltaY` and `momentumDeltasScrollLikeDirectOnes`, both authorities |
| the overscroll clamp's shipped intermittent defect | 1.1 and `scrollingPastTheEndDoesNotBankAnOffsetTheUserMustUnwind`, both reddened by **M1a** |
| identity paths and the seven reserved slots | 2.6; `theSevenRetentionSlotsAreMutuallyDistinct`; every agreement arm asserts `stateSlotsEqual` |
| hit testing | every agreement arm asserts `hitboxesEqual`; 2.3 asserts it **false** with the reason named |
| accessibility records | every agreement arm asserts `accessibilityEqual`; 2.4 asserts it false for A6's shape and names `LR-AC` as the cause |
| the disabled gate | untouched: no lane edits `Frame.registerHandlers` |
| the 97 goldens | `git diff --name-only 57893d0 HEAD -- 'Tests/**/*.json'` empty at every lane (scoped to `Tests/`, since the SDL line keeps shader-reflection JSON elsewhere) |

## 10. Deferred, each with an owner

| item | why not stage 3 | owner |
|---|---|---|
| the remaining scroll-subtree width disagreement in the demo (0 vs 420) | it is the `List` reporting, not the `ScrollView` | stage 4 |
| `ProposalScrollView` publishing a `ScrollContext` | nothing can read one: no proposal element reads `pass.scrollContext` and `List` cannot be a `ProposalScrollView`'s content. Publishing it now would be declared-but-inert | stage 11 / task 10, with the two scroll types' unification |
| `ProposalScrollView`'s animation (`$anim-content`/`$anim-viewport`) | it has no `Style` and no modifier surface to animate; the fold shares chrome, not animation | stage 11 |
| `ProposalScrollView`'s multi-child lowering always being **vertical** (`aHorizontalProposalScrollViewAlsoStacksDirectChildrenVertically`) | probe-backed (stack-algorithms SC3) and unchanged by this stage | — (it is SwiftUI's answer) |
| the demo's `.flexGrow(1).flexBasis(0).minHeight(0)` on the scroller `Box` | it exists to bound a hugging viewport; a lowered viewport is bounded by construction (`LR-BC`), but removing it is a production respelling | stage 6b |
| divergence 48's and 56's retirement | each is answered under the proposal authority here and pinned wrong-on-purpose under the legacy one; the retirement is the root switch | stage 6b |
| **divergence 54's retirement** | the lowering **preserves** it: the kernel viewport's cross answer is the `ProposalScrollView` side, and a lowered `ScrollView` reads its parent's cross size only because it records a `LoweredItem` where `ProposalScrollView` records none (§3.2, `LR-BC` amended, critic round 1 finding 5). Retiring it needs the two scroll types unified; 2.2a pins the surviving difference meanwhile | stage 11 / task 10, with `LR-BF`'s unification |
| framed component members staying **one** flex item where SwiftUI's stay siblings | needs `ElementGroup`'s associated type (`TB-M`) | stage 11 |
| two-axis scrolling | never designed | task 10 |
| committing the `CN-R` twelve-image harness | lane 1 had to rebuild it from record §18's prose, its own copy having been lost with a session scratchpad; the rebuild is only checkable against §8's five controls plus record §25 §7.6's two distinct-value counts (`LR-BL` item 6) | stage 6b |
| the single-child stretch elision inside a `ScrollView` (A6's 40 → 16) | stage 2's `LR-AC`, unchanged here | stage 6b (the root and demo respelling) |
| `Style.overflow`'s inert write in `ScrollView.requestLayout` | it documents intent under the legacy authority and is not carried by the lowering | stage 10, with `Style`'s CSS fields |
| **an amend frame or a per-member frame APPLYING its member's `flexGrow`/`margin` instead of dropping them** (`parentKind: .flex(isRow:)`, with `isRow` read off the patch) | lanes 4 and 5 both kept `.stack`, which is every other frame's parent kind, so those fields are consumed and dropped (`LR-BO` item 1, `LR-BP` item 1). Applying them needs a non-arbitrary main axis for a one-child frame and a probe SwiftUI cannot supply — it has no `flexGrow`. The multi-node arm has an axis (its row is horizontal) but not a reason to differ from the one-node arm | stage 6b, which owns what production trips over |
| **site `component` having no reachable report** | both ops lower and neither can raise an entry at its own site (`LR-BO` item 2); the case stays for `owningStage`'s trap message | whoever first needs a component-level diagnostic |
