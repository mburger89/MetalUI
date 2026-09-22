# Engine replacement, stage 4 — the windowed proposal `List` (plan task 7)

**Status, 2026-09-23 (PDT): design only.** No file under `Sources/` or `Tests/`
has changed in a commit. Every source patch cited below as a *prototype* was
applied in `/Users/maxburger/Developer/MetalUI-stage-4`, built, run and
restored from a `cp` copy, with `git status --short` clean afterwards; the
measurements are in `docs/record/26-engine-replacement-stage-4.md`.

Parent design: [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md),
§4.1 row 4 and §8's stage-4 row. Stage 1 is record §18, stage 2 §21, stage G
§22, their integration §23, stage 3 §25 (spec
[`2026-09-22-engine-stage-3-design.md`](2026-09-22-engine-stage-3-design.md)).
Rulings are `LR-BQ`… in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
— the same decisions doc stages 1–3 use.

Branch `feat/engine-stage-4` from `f2e981f`.

**What §4.1 row 4 asks for.** *"`List`'s explicit site check replaced by a
windowed `ProposalLayout` placing realized rows at `index × rowHeight` against
the native `ScrollContext`; row identity (`TB-`), `AXTable` records (`AB-L`),
`MP-I` cold-frame work, probe K6's layout answer. Exit test:
`aListsWorkIsTheSameFor100kRowsAsFor500` and the `ListTests` windowing arms
under the proposal authority, counting work; `ListTests`' 224 custom nodes and
3 leaves re-spelled."*

**The one sentence this design turns on.** The measurements below (§2.3,
prototype P1b) found that `List`'s existing CSS structure — a leading spacer
`Box`, `flexShrink: 0` and `minSize.height: 0` on each row, a declared
`size.height` on the container — **already lowers through stage 2 with no
diagnostic and, in a container with a declared width, agrees with the legacy
engine element for element**. So this stage is not a rescue: the windowed
`ProposalLayout` is chosen over that free lowering for reasons that are
argued and costed in `LR-BQ`, and the free lowering is kept as the
differential oracle every lane measures against.

## Contents

1. [Baseline](#1-baseline)
2. [Evidence gathered for this design](#2-evidence-gathered-for-this-design)
3. [The mechanism](#3-the-mechanism)
4. [What must not move, and what does](#4-what-must-not-move-and-what-does)
5. [API and files](#5-api-and-files)
6. [Lanes](#6-lanes)
7. [The exit test](#7-the-exit-test)
8. [Demo, pixels and captures](#8-demo-pixels-and-captures)
9. [Deferred, each with an owner](#9-deferred-each-with-an-owner)

---

## 1. Baseline

At `f2e981f`, measured 2026-09-23 in `/Users/maxburger/Developer/MetalUI-stage-4`:

| measure | value | how |
|---|---|---|
| suite | **1580 tests in 2 suites**, passed; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel`, unfiltered |
| goldens | **97** | `find Tests/MetalUILayoutTests -name "*.json" \| wc -l` |
| typecheck guards | 77 (unchanged from stage 3) | CLAUDE.md's per-file `grep -c canTypecheck` |
| working tree | clean | `git status --short` empty |

**`find Tests -name "*.json"` reads 115** once `Tests/PortableTests/.build`
exists; that is not a regression, and the golden count is taken under
`Tests/MetalUILayoutTests` only.

**Stage 4 retires no golden and must move none.** Nothing in this stage touches
`Sources/MetalUILayout/` except by *calling* `newNativeLayout`, which the
fixtures do not run. The check is
`git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty.

## 2. Evidence gathered for this design

### 2.1 Probe K6, re-run today

`docs/probes/swiftui-stack-algorithms.swift`, `/usr/bin/swift` (Apple
Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0. **Exit 0, and the whole stdout is
byte-identical to the reading recorded in the probe's own header** (checked by
`diff` over the 787 output lines, empty). K6's arms, verbatim from today's run:

```
K6 control fixed 30x30 at 100x100 @100x100: size 30x30
K6a List{Text} at 100x100 @100x100: size 100x100
K6b List{Text} at nil @nilxnil: size 0x0
K6c List{Text} at 100 x nil @100xnil: size 100x0
K6d List{Text} at nil x 100 @nilx100: size 0x100
K6e List{Text} at inf x inf @infxinf (measured only): size infxinf
K6f List{leaf l 30x30} at 100x100 (is a row laid out?) @100x100: size 100x100
```

So SwiftUI's `List` is **greedy and content-blind**: the proposal on each
concrete axis, 0 on a nil axis, ∞ at ∞, and its row's own size never reaches
the answer (K6f is 100×100, not 30-anything, against the K6 control's 30×30).

**K6 is evidence that MetalUI's `List` must NOT copy it** (`LR-BR`). SwiftUI's
`List` owns its own scrolling: it *is* the viewport, so answering the proposal
is right for it. MetalUI's `List` is the scroller's **content** — the four
load-bearing requirements in its own type doc include "an enclosing
`ScrollView`" — and a content node that answered the viewport's proposal would
report a 400pt extent for a 14 000pt list, so the offset clamp, the thumb and
`aWindowedListStillReportsItsFullContentHeight` would all read the viewport.
The greedy answer belongs to the kernel's `scrollViewport`, which stage 3
already lowered `ScrollView` onto (`CN-M`, `LR-BC`). §3.2 states what the
windowed layout answers instead, and `LR-BR` records that K6 was consulted and
deliberately not followed on either axis.

### 2.2 No new probe

Stage 4 adds no probe. Every SwiftUI-facing question it asks — the List answer
(K6), the scroll viewport's answer (`CN-M`, stage-3 probe SC1/SC2/SC4), stretch
and compression (stage-2 probe S1–S3, G1/G2) — is already probed, and K6 was
re-run today rather than trusted. If a lane finds a question none of them
answers, it owes a probe under `docs/probes/` with a positive control and its
output in its header, not an assertion.

### 2.3 Prototypes (scratch, applied and restored)

Four prototypes, all in the worktree, all restored (`git status --short` empty
after each; the full tables are record §26 §2).

**P1a — today's baseline.** `ScrollView { List(20 rows, rowHeight 10) { ProbeLeaf } }`
through `LayoutDifferential.compare` at 100×100: report `[list.noLowering]`,
44 ids, 3 agreeing, 1 disagreeing, **40 legacy-only** (the rows the proposal
side does not build), `stateSlotsEqual` **false**, `scenesEqual` false. This is
the state stage 3 handed over (record §25 §3.6).

**P1b — `List`'s site check removed, nothing else changed.** The four lines of
`List.requestLayout`'s `lowersToProposal` branch replaced by `let
lowersToProposal = false`, so the existing spacer-plus-rows `Box` lowers through
stage 2's container lowering:

| shape | result |
|---|---|
| `Box(width 100, column) { List(3 rows, 28) { Box() } }` (**P1a6**) | **0 unlowerable, 0 disagreeing, 11 ids, `stateSlotsEqual` true** — the container, the spacer, every row `Box` and every row's content agree exactly |
| bare `List(6 rows, 10) { ProbeLeaf(7×3) }` under the harness root (**P1a2**) | 0 unlowerable; every row's **y agrees** (0, 10, 20, 30, 40, 50) and every row's **height agrees** (10); widths differ (legacy 7, lowered 100) |
| `ScrollView { List(10 rows, 28) { ProbeLeaf }.padding(60) }` (**P1a3**) | 0 unlowerable, `stateSlotsEqual` true; rows at y = 60, 88, 116 … 312 on **both** sides — the spacer, the row pins and the padding all lower |
| `List(3 rows, 28) { ProbeLeaf(7×60) }` (**P1a4**) | 0 unlowerable; row boxes 28 tall on both sides |

The width disagreements in P1a2/P1a3/P1a4 are **not `List`'s**: they are
`DifferentialRoot`'s own documented divergence (the native overlay root
proposes its full size where the legacy `display: .stack` root offers
fit-content, divergence 53, `LayoutDifferential.swift`'s header) plus
`ProbeLeaf` registering a native leaf **directly**, so it records no
`LoweredItem` and `planLegacyItems` cannot stretch it (`LR-T`: a proposal
element inside a lowered container is defined, not silent). P1a6 puts a
declared width on the container and uses `Box` row content, and everything
agrees.

**So the honest statement of this stage's difficulty is: the lowering is
already free, and what stage 4 buys is stated and costed in `LR-BQ`, not
assumed.**

**P2 — the windowed `ProposalLayout`, through a group.** A scratch
`ElementGroup` that registers its member `Box`es and then returns **one** node
— a `ProposalLayout` over them — under the proposal authority, and a bare
spacer node plus the members flat under the legacy one. The layout answers
`(proposal.width ?? 0, rowHeight × logicalCount)` and places subview *i* at
`(bounds.x, bounds.y + (firstIndex + i) × rowHeight)` with proposal
`(bounds.width, rowHeight)`.

| arm | result |
|---|---|
| P2, 6 rows, `firstIndex: 0` | **0 unlowerable, 9 ids, 0 disagreeing, `stateSlotsEqual` true**; rows at y = 0, 10, 20, 30, 40, 50, each 100×10 on both sides |
| P2b, rows 3…8 of 20, `firstIndex: 3` | **0 unlowerable, 9 ids, 0 disagreeing, `stateSlotsEqual` true**; rows at y = 30, 40, 50, 60, 70, 80, each 100×10 on both sides; the container 100×200 on both sides |

Three things P2 establishes, none of which was obvious:

1. **A group may return one node that wraps its members.** The enclosing
   `Box`'s `lowerLegacyNode` consumes that node's `LoweredItem` exactly as it
   consumes a child element's, and `reportUnconsumedLoweredItems` names
   nothing.
2. **The rows get their stretch from `planLegacyItems` called by the group**,
   with `parent:` the `List`'s declared style, `parentKind: .flex(isRow: false)`
   and `parentSite: .list` — which is also what keeps `LoweringSite.list`
   reachable after the site check goes.
3. **`stateSlotsEqual` is true** because the spacer is a bare **node** under
   the legacy authority rather than a `Box` **element**, so neither authority
   mints a `$anim` entry for it. Keeping it an element on one side only would
   have made the two authorities' `StateTable` id sets differ for every
   `List` — which stage 1's §5.1 item 4 forbids.

**P3 — the `ListTests` row re-spelling.** `ListTests`' private `Row` registers
`pass.requestNode(style: Style(), children: [])` (the 224 nodes of §4.2's
census) and, in its `contentHeight` arms, `pass.requestLeaf` (the 3 leaves).
Re-spelled to branch on `pass.lowersToProposal` and call
`pass.lowerLegacyNode(Style(), declared: Style(), children: [], site: .customElement)`
— and `lowerLegacyLeaf` over a `requestNativeLeaf` for the `contentHeight`
arm — inside `Box(width 100, column) { List(3 rows, 28) { … } }` with P1b
applied: **0 unlowerable and 0 disagreeing in both arms**, including the tall
arm, where the row box reads 28×100 and the row's own node 0×28 on **both**
sides. That is the exact assertion
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` makes.

**Why not `ProbeLeaf`** (`LayoutDifferential.swift`), which stage 3's lane 3
used for its nine custom nodes: `ProbeLeaf`'s proposal branch registers a
native leaf directly, records no `LoweredItem`, and is therefore never
stretched — P1a2/P1a4 measured it at 7×3 and 7×60 where legacy gives 7×10 and
7×28. `ListTests` reads a row's own **height** in two tests, so it needs the
lowered spelling, not the native-leaf one (`LR-BW`).

### 2.4 The cold frame and the resident entry set, on this machine

Debug, `swift test --build-system native --no-parallel --skip-build`, a
`ScrollView { List(n rows, rowHeight 20) { row registering a scroll region } }`
at 200×400, legacy authority, `StateTable` shared across frames:

| n | cold frame | regions on the cold frame | `table.count` cold | warm (windowed) frame | regions warm | `table.count` after 30 scroll frames |
|---|---|---|---|---|---|---|
| 500 | **0.0292 s** | 501 | 506 (`n + 6`) | 0.00285 s | 25 | **128** |
| 10 000 | **0.534 s** | 10 001 | 10 006 (`n + 6`) | 0.00686 s | 25 | **178** |

`n + 6` rather than `2n + 6` because this fixture's rows carry no `@State`
(only each row `Box`'s `$anim`); `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s
own fixture adds one `@State` per row and reads `2n + 6`. The **six** fixed
entries are the scroller's `ScrollState`, the `List`'s `$ax` slot, the `List`'s
own `Box`'s `$anim`, **the windowing spacer `Box`'s `$anim`**, and
`ScrollView`'s two nodes' `$anim`s. §4.2 is about the fourth of those.

The warm window is 24 rows (a 400pt viewport over 20pt rows, plus `overscan`
2 each side) plus the scroller's own region, at both row counts — the
`O(window)` property the exit test counts.

### 2.5 Native work, for the exit test's shape

`LayoutTree.lastNativeLayoutWork` over a vertical linear stack of *n* fixed
28pt rows inside a frame inside a scroll viewport, measured directly on the
kernel:

| n | `measureCalls` | `cacheHits` | `cacheMisses` |
|---|---|---|---|
| 14 | 14 | 86 | 59 |
| 25 | (lane 5 re-derives) | | |
| 500 | 500 | 3 002 | 2 003 |

So the kernel's work is linear in the number of **realized** rows and
independent of the logical count — which is exactly the claim the exit test
must make, and the reason it counts work rather than wall clock. Lane 5
hand-derives the literals for the real shape before running it.

## 3. The mechanism

### 3.1 `List`'s structure, before and after

**Today.** `List.requestLayout` builds
`Box(style:decoration:content: Pair(Box(spacerStyle), ArrayGroup(rows)))` and
returns `built.requestLayout(id, pass:)` — so the outer `Box` reuses the
`List`'s own id and the rows are **direct named children of the `List`'s id**.
That last fact is load-bearing: `TombstoneTests.rowID` and `FocusTests.rowID`
hand-compute
`scrollerID → listID → child(of: listID, name: datum.id) → child(at: 0)`,
and a `$state0` slot hangs off the last of those.

**After.** The same outer `Box`, the same id reuse, the same row `Box`es with
the same `.id(String(describing: datum.id))`. What changes is the **group**:

```
Box(style:decoration:content: ListRows<Row>(...))
```

`ListRows` registers each row `Box` under the `List`'s id at cursor 0, 1, 2 …
(names replace positions, so the row ids are unchanged even though the spacer
no longer occupies cursor 0) and then, per authority:

- **legacy** — registers the leading spacer as a **bare node**
  (`pass.frame.requestNode(style: spacerStyle, children: [])`, the identical
  style) and returns `[spacer] + rowNodes` flat, exactly what `Pair` returned;
- **proposal** — consumes each row's `LoweredItem`, plans and registers the
  item wrappers with `planLegacyItems`/`registerLegacyItems`, registers one
  `WindowedRowsLayout` over the wrapped nodes, records **that** node as the
  group's item, and returns `[windowedNode]`.

`List.prepaint`, `List.paint`, `List`'s handlers, its `AXNode`, its
`windowIsBounded`/`windowAwaitsViewport` threading and its
`withAccessibilitySuppressed(except:)` guard are **untouched** — they all go
through the outer `Box`, which is untouched.

**Three CSS-defeating devices go, on the proposal path only** (`LR-BS`): the
spacer (the layout places absolutely), `rowStyle.minSize.height = 0` (there is
no automatic minimum in the kernel) and `rowStyle.flexShrink = 0` (there is no
freeze loop). **The row style is written once and kept identical on both
paths** — `planLegacyItems` lowers `flexShrink: 0` to `fixedSize` and folds a
`minSize` of 0 into the declared 28, and P3 measured both sides identical — so
the devices are inert rather than removed, and the file keeps ONE row style
instead of two that can drift. `LR-BS` records the alternative (a
proposal-only row style) and why it was rejected.

### 3.2 `WindowedRowsLayout` (`LR-BR`)

```swift
struct WindowedRowsLayout: ProposalLayout {
    var rowHeight: Double      // > 0 is not required; see below
    var logicalCount: Int      // data.count, NOT the window's size
    var firstIndex: Int        // window.lowerBound
}
```

**`sizeThatFits(proposal:subviews:)`**

- **height** = `rowHeight × Double(logicalCount)` — always, whatever the
  proposal. This is the full content extent, which the scroller's clamp and
  thumb read and which `aWindowedListStillReportsItsFullContentHeight` pins at
  1120 for 40×28. It is where MetalUI's `List` diverges from SwiftUI's (K6b/K6c
  answer 0 on a nil height and K6a answers the proposal); §2.1 and `LR-BR` give
  the reason.
- **width** = `proposal.width`, when there is one; otherwise **the maximum of
  the subviews' answers** at `(nil, rowHeight)`. The concrete-axis half is
  K6's; the nil-axis half is **not** (K6b/K6d answer 0). A vertical `List`
  inside a horizontal `ScrollView` is measured at a nil width — CLAUDE.md
  already documents that composition, and `visibleRange` already declines to
  window it — and answering 0 there would render it blank, a second
  blank-render mode beside divergence 14's. So the nil axis answers the
  content, as the legacy engine does. Measuring costs one subview measurement
  per realized row and **only on the axis that is nil**.
- **no baselines** (`LayoutMeasurement.firstBaseline`/`lastBaseline` have no
  producer and no consumer; CLAUDE.md's declared-but-inert table).
- **zero measure calls on the common path** — a concrete width proposal is
  answered without touching a subview.

**`placeSubviews(in:proposal:subviews:)`** places subview *i* at
`(bounds.x, bounds.y + Double(firstIndex + i) × rowHeight)`, anchor
`.topLeading`, proposal `(bounds.width, rowHeight)`. Every subview is placed
exactly once, so `SA-E`'s "an unplaced subview is centred" never fires and the
"last record wins" rule is never exercised.

**Purity** (`SA-H`): the answer depends only on the layout's value, the
proposal and the subviews' answers. ✓

**Validation** (`SA-J`): the layout **rejects nothing**. `rowHeight ≤ 0` is
legal, quiet input that `List` has always accepted (`visibleRange`'s own guard
declines to window against it, and
`aZeroRowHeightDoesNotTrapOnceAScrollContextIsPresent` pins that); a negative
`rowHeight` gives a negative height, which checkpoint 2 (a stored rect may not
be infinite) does not forbid and checkpoint 3 (nothing may be NaN) does not
reach. `logicalCount` and `firstIndex` come from `data.count` and
`visibleRange`, both already clamped into `0..<count`. Adding a
`precondition` here would reject input SwiftUI accepts, against `SA-J`'s rule,
and relaxing a trap into a clamp later is the additive direction anyway.

**Depth** (`SA-L`): the windowed node replaces the legacy linear stack, so the
native path to a row is one level **shorter** than the P1b lowering's (no
spacer sibling, no stack). Lane 5 re-measures the demo's deepest native path
against `NativeLayoutRun.maxDepth` (88) and records it.

### 3.3 The scroll context is unchanged (`LR-BT`)

`List.visibleRange(count:pass:)` reads `pass.scrollContext`, published by
`ScrollView.requestLayout`'s `withScrollContext` **before** its authority
branch, so both authorities publish the identical value (stage 3 measured it:
record §25 §3.3, `["off=0.0 vp=0.0 ax=vertical", "nil"]` on both sides).
Stage 4 changes not one line of `visibleRange`, of `ScrollContext`, or of its
publication. The four escape hatches (no context; a horizontal one; a zero
viewport extent; `rowHeight ≤ 0`) and the clamp against `extent −
viewportExtent` are carried over verbatim.

**Consequently divergences 13 and 14 survive this stage unchanged**, and §4.1
says so with the measurement.

### 3.4 Accessibility is untouched (`LR-BU`)

Every mechanism `AB-L`/`AB-X` names lives outside the group:

- the `List`'s own `AXNode` (`role: .container` unless the caller declared one,
  `logicalCount = data.count`) is written onto `built.handlers` in
  `requestLayout` and emitted by the outer `Box`'s `registerAndScope`;
- each realized row's `handlers.axNode.logicalIndex` is written onto the row
  `Box` in `requestLayout`, gated on `windowIsBounded && pass.collectsAccessibility`;
- `windowIsBounded`/`windowAwaitsViewport` are computed from the same
  `pass.scrollContext` read, and `prepaint`'s `requestAccessibilityRetry()` and
  `withAccessibilitySuppressed(except: id)` are unchanged.

What stage 4 must **prove** rather than assume is that the row records come out
with the same geometry under the proposal authority — a row's published
`geometry` is its `visibleFrame`, and under the proposal authority a row's rect
comes through the item-frame **alias** stage 2 introduced rather than from the
row node itself. P2 measured the rects equal; lane 4 pins the **records**,
through `LayoutDifferential`'s `accessibilityEqual` and through
`AccessibilityTreeTests`' own table assertions under both authorities.

### 3.5 What `LoweringSite.list` means afterwards (`LR-BV`)

`list.noLowering` disappears. The `.list` case stays, and stays **reachable**,
for two entries:

- `flexGrow.weights`, raised at `parentSite:` by the group's own
  `planLegacyItems` call if two rows ever declared unequal grow factors (no row
  does today — `rowStyle` sets none — so this is the same "kept for the right
  stage number" shape `component` has since `LR-BO`);
- any item field a later stage puts on a row that `planLegacyItems` cannot
  lower, raised at the **child's** site, and `<field>.unconsumed` if the
  windowed node's record were ever left unconsumed.

`UnlowerableField.owningStage` keeps `case .list: return "4"`, with its comment
updated to say the site-level entry is gone.

## 4. What must not move, and what does

### 4.1 Must not move — the seven, each with its pin

| # | invariant | pinned by | why stage 4 could break it | how the design keeps it |
|---|---|---|---|---|
| 1 | **Row identity** is `child(of: listID, name: String(describing: datum.id))`, one level under the `List`'s own id, with the row element at `child(at: 0)` below it | `aRowKeepsItsIdentityWhenItsPositionChanges`, `distinctRowsGetDistinctIdentities`, and the hand-computed chains in `TombstoneTests.rowID` / `FocusTests.rowID` | an element introduced between the `List` and its rows adds an id level and resets every row's `@State`, focus, `$anim` and AX node once | the arranging thing is a **group**, not an element, and groups introduce no id level; the outer `Box` still reuses the `List`'s id. The spacer leaving cursor 0 moves no row id, because a name replaces a position |
| 2 | **`@State` retention across a bounded excursion, and loss past it** (`TB-AH`; `staleAfterGenerations` 2, `sweepThreshold` 256) | `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, asymmetric | the window's contents decide which rows are marked each generation | `visibleRange` is untouched (§3.3), and the window is the same range on both paths. Lane 4 runs the test under **both** authorities |
| 3 | **Focus retention on the same bound**, one generation later because `resolveFocus` reads before `sweep` | `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, asymmetric | as above | as above; lane 4's second arm |
| 4 | **The `AXTable` and its realized rows' `AXIndex`es**, the unbounded-window rule and the one-more-frame rule (`AB-L`, `AB-X`) | `AXNodeTests`' three `List` tests, `AccessibilityTreeTests`' two | the records' geometry now comes through an item-frame alias | §3.4; lane 4 pins `accessibilityEqual` and the table assertions under both authorities |
| 5 | **`MP-I`'s cold frame** — every row built on frame 0, because no `ScrollView.prepaint` has measured a viewport yet | `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s frame 0, `aListsWorkIsTheSameFor100kRowsAsFor500` | nothing in this stage touches it, but a lane could "optimise" the unbounded window away | the `viewportExtent > 0` guard is untouched; lane 5 re-measures the cold frame at 500 and 100 000 under **both** authorities and reports it (§2.4 is the legacy baseline) |
| 6 | **The resident entry set stays bounded while scrolling 10 000 rows** | `theResidentEntrySetStaysBoundedWhileScrolling10kRows` (`< n/10`, measured 128/178 in §2.4's lighter fixture) | the spacer's `$anim` entry disappears (§4.2) | the bound is re-measured, not re-derived, and the cold-frame literal moves by exactly one |
| 7 | **Divergence 16's wheel routing, hit testing, identity paths and the disabled gate** | `ScrollRoutingTests` (34 scenarios, both authorities since stage 3), `HitboxTests`, `DisabledTests` | the `List` registers no hitbox of its own beyond its handlers, and those go through the untouched `Box` | nothing in the group registers a hitbox, a scroll region or a focus entry |

### 4.2 What does move, each with a ruling

**(a) The spacer stops being an element** (`LR-BS`). It becomes a bare legacy
node with the identical `Style`. Consequences, each to be re-measured rather
than derived:

- `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s cold-frame literal
  `2 * n + 6` becomes `2 * n + 5`, and its doc comment's enumeration of the six
  fixed entries loses "the windowing spacer `Box`'s `$anim` slot". The
  **checkpoint** counts (256 / 256 / 150 today) are re-measured, not adjusted.
- Divergence 18's `2n + 7` figure and its **125 rows** crossing point were
  measured on `demoLikeRows(_:)`, whose rows have no `.padding`; that fixture's
  count moves by one per frame in the fixed overhead, not per row, so the
  crossing point does not move. Lane 1 re-measures it anyway and says so.
- The scene and the hitbox list must be **unchanged**: an empty `Decoration`
  emits nothing and an empty `Handlers` registers nothing. Lane 1 asserts
  `scenesEqual` and `hitboxesEqual` against `f2e981f`'s frames, and the twelve
  `CN-R` images must read 0.

**(b) A `List` under the proposal authority stops hugging its content and
fills its proposal on the width axis.** That is stage 2's stretch semantics
arriving, not a stage-4 choice: under the legacy engine a `List` whose rows
have no declared width is as wide as its widest row; under the proposal
authority it is as wide as the scroller's content box. Production is unaffected
until stage 6b. The demo's rows declare `.width(420)`, so the demo's own
numbers are governed by cause **55**, not by this.

**(c) The exit test `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
(2.15) changes substantially**, and lane 5 owns it. Predicted, to be measured:
the report becomes `[]` with the modal off and `[stack.position, stack.inset]`
with it on; cause **4**'s row ("`List` has no lowering") is retired; the
**2 000 legacy-only ids** — the demo's 500 rows and their contents — become
agreeing or disagreeing, and the `List`'s and its rows' widths stop being 0.
The counts (2036 ids, 6 agreeing, 30 disagreeing, 2000 legacy-only) are
**re-derived from the run**, and any disagreement that is not attributable to
an existing named cause (R, 55, X9, 3) is a finding, not a number to write
down.

**(d) `aListAndAComponentAmendTrapByTheirOwnSiteUnderTheProposalAuthority`
loses its `List` arm** — the arm asserts `list.noLowering has no proposal
lowering` on a process exit, which after this stage cannot happen. Stage 3
already retired this test's `ScrollView` arm the same way and left the name
naming its surviving arms; lane 2 retires the `List` arm, renames the test to
name what survives (the component amend), and its replacement is lane 2's own
agreement test. `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `List`
arm becomes a `flexGrow.weights` arm (two rows with unequal declared grow
factors) or, if that cannot be spelled from outside `List`, an **agreement**
arm — lane 2 decides by measurement and records which, exactly as stage 3's
lane 2 did for `anItemFieldNoLoweredContainerConsumesIsReportedByName`.

### 4.3 Divergences 13 and 14 — kept, and why (`LR-BT`)

**Divergence 13** (the window is computed against a one-frame-stale viewport
extent, wrong for one frame on resize, bounded by two rows of overscan) and
**divergence 14** (the window is placed against the *scroller's* origin, so a
`List` that is not its scroller's only layout-contributing child renders blank)
both follow from `visibleRange` reading the ambient `ScrollContext` in
`requestLayout`, where no element has a position. Stage 4 changes neither line.
Both pins stay exactly as they are, and lane 4 runs
`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` under **both**
authorities so that the wrong-on-purpose answer is pinned on the path
production will take at stage 6b.

**One thing did change, and it is a finding rather than a fix.** A
`ProposalLayout`'s `placeSubviews` receives **root-absolute `bounds`**, so for
the first time the windowed layout knows where the `List` actually sits inside
its scroller — one phase too late to choose the window, but early enough to
store for the next frame. Divergence 14 is therefore now fixable by the same
one-frame-feedback shape `ScrollView` already uses for `viewportExtent` (which
is divergence 13). Stage 4 does **not** take it: it would retire a
wrong-on-purpose pin, it needs its own measurement of the first-frame flash it
trades for, and it is a `List` feature rather than an engine replacement.
Deferred to **stage 6b** (§9), where the human-verification rows that read demo
layout re-open anyway.

## 5. API and files

All new API is `internal`. No public type gains a case or a requirement.

**`Sources/MetalUI/ListRows.swift`** (new, ~200 lines with its doc comment):

```swift
/// The windowed row arrangement `List` builds, as an `ElementGroup` so that it
/// introduces no identity level between the `List` and its rows.
struct ListRows<Row: Element>: ElementGroup {
    var rows: [Box<Row>]
    var rowHeight: Pixels
    var logicalCount: Int
    var firstIndex: Int
    /// The `List`'s DECLARED style, the parent `planLegacyItems` plans against
    /// (ruling LR-AS: structure from the declared style).
    var listStyle: Style

    struct GroupLayout { … }          // each row's id and layout
    typealias GroupPrepaint = [Row's GroupPrepaint]

    mutating func requestGroupLayout(under:at:pass:) -> ([LayoutNodeID], GroupLayout)
    mutating func prepaintGroup(layout:pass:) -> GroupPrepaint
    mutating func paintGroup(layout:prepaint:pass:)
}

struct WindowedRowsLayout: ProposalLayout { … }   // §3.2
```

**`Sources/MetalUI/List.swift`**: `box` becomes
`Box<ListRows<Row>>`; `Layout` becomes a `public struct Layout` of `List`'s own
with **internal** stored properties, so `ListRows` can stay internal while
`requestLayout`'s return type stays public; the `lowersToProposal` site check
and the `lowersToProposal ? 0..<0 : …` window collapse to
`visibleRange(count:pass:)`; the spacer moves into the group; the three row
style lines and every other line of `requestLayout`, `prepaint` and `paint`
stay. The type doc's paragraphs on the spacer, `minSize.height` and
`flexShrink` are rewritten to say which path each still serves — **not
deleted**: they are the only record of what the legacy answer depends on until
stage 9.

**`swift package clean` is required** before the first build of lane 1 and
again before the merge: `List` is a public type crossing a module boundary and
both its stored `box` property's type and its `Layout` change (CLAUDE.md's
rule, and record §12's "turning a stored property into a computed one fails the
incremental link instead").

**`Sources/MetalUI/LayoutAuthority.swift`**: `UnlowerableField.owningStage`'s
`.list` comment (§3.5). No case added or removed.

**Tests touched**: `ListTests.swift` (re-spelling, authority arms),
`TombstoneTests.swift`, `FocusTests.swift`, `AXNodeTests.swift`,
`AccessibilityTreeTests.swift`, `MeasurePerformanceTests.swift`,
`LayoutAuthorityTests.swift`, `LoweringCorpusTests.swift`; new
`Tests/MetalUITests/ListLoweringTests.swift` for the lowering's own tests, in
the shape `LoweringScrollTests.swift` has.

**No typecheck guard is added.** Stage 4 introduces no hazard a plain import
can reach: `ListRows` and `WindowedRowsLayout` are internal, and `List`'s
public surface is unchanged. If a lane finds one, it writes the guard in the
same change and mutates it red once.

## 6. Lanes

Five lanes, each red first, each its own commit, the suite green and the
goldens unmoved at every one. **Every lane's demo expectation is 0 differing
pixels in all twelve `CN-R` images** — production runs the legacy authority
until stage 6b, and the only legacy change in the whole stage is §4.2(a),
which emits nothing.

### Lane 1 — `ListRows`, legacy only (`LR-BS`)

`Pair(spacer, ArrayGroup(rows))` becomes `ListRows`, with the **legacy branch
only** (the site check stays, so the proposal branch is unreachable). The
spacer becomes a bare node.

**Red before.** Nothing here is a new behaviour, so this lane is honestly
"green first" for its geometry and **red first for its one moving number**:

| test | red how |
|---|---|
| `theResidentEntrySetStaysBoundedWhileScrolling10kRows` | write `2 * n + 5` **before** the change and read it fail at `2 * n + 6`, then make the change and read it pass — the practice's "require the arms to disagree first" |
| `aTheListsSpacerIsANodeNotAnElement` (new) | asserts the `StateTable` holds no entry under `child(of: listID, at: 0, name: nil)` after a windowed frame; red at `f2e981f` |

**Characterization, green both sides** (their evidence is their mutations, as
stage 3's lane 1 was): `aScrolledListsSpacerDoesNotShrinkUnderPadding`,
`paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`,
`aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop`, and a new
`aListsSceneAndHitboxesAreUnchangedByTheGroup` comparing a rendered frame's
scene bytes and hitbox list against literals taken at `f2e981f`.

**Mutations that must redden something, named up front.** M1a: the spacer's
height computed from the window's **size** rather than its `lowerBound`
(reddens `aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop`,
`aScrolledListsSpacerDoesNotShrinkUnderPadding`). M1b: `spacerStyle.flexShrink`
dropped (reddens `aScrolledListsSpacerDoesNotShrinkUnderPadding`). M1c: the
group's cursor advanced past the spacer as `Pair` did (reddens nothing today —
names replace positions — and if it reddens nothing the lane records that as
the measured reason row identity is safe, not as a gap).

**Measurements owed**: `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s
three checkpoints, re-run; divergence 18's `2n + 7` on `demoLikeRows`, re-run;
the twelve `CN-R` images.

### Lane 2 — `WindowedRowsLayout` and the lowering (`LR-BQ`, `LR-BR`)

`ListRows`' proposal branch, `WindowedRowsLayout`, and `List`'s site check
deleted. `Sources/` only reaches the proposal authority here.

**Red before**, in a new `ListLoweringTests.swift`, all eight failing at lane
1's HEAD because the `List` still reports `list.noLowering` and stands in as
`Frame.unlowerable`'s 0×0 leaf:

| # | test | asserts |
|---|---|---|
| 2.1 | `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` | five arms through `LayoutDifferential.compare` inside a declared-width container — unwindowed, windowed at `firstIndex 3`, padded, scrolled, and a tall row — each `unlowerable.isEmpty`, `disagreeing.isEmpty`, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual`, `stateSlotsEqual`. **Its literals are P2's and P3's tables**, written before the implementation exists |
| 2.2 | `aWindowedListAnswersItsFullContentHeightAndItsProposedWidth` | the layout's own answer: 40×28 → height 1120 at every proposal; width 100 at a 100 proposal |
| 2.3 | `aWindowedListMeasuresNoRowToAnswerAConcreteProposal` | `lastNativeLayoutWork.measureCalls` for the container's own answer, hand-derived |
| 2.4 | `aWindowedListAtANilWidthAnswersItsWidestRow` | the nil-axis half of §3.2, and the one place K6 is **not** followed |
| 2.5 | `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight` | row *i* at `firstIndex + i` under the proposal authority, read from `elementBounds` |
| 2.6 | `aZeroRowHeightLowersWithoutTrappingOrProducingNaN` | `SA-J`'s checkpoints on the degenerate input `List` has always accepted |
| 2.7 | `theListSiteReportsNothingAndItsRowsItemFieldsAreLowered` | `unlowerableFields.isEmpty` for a plain list; `flexGrow.weights` at site `.list` for the contrived two-unequal-grow-factor row shape, or the measured reason it cannot be spelled |
| 2.8 | `aLoweredListsRowIdentitiesAreTheLegacyOnes` | the two `StateTable` id sets equal, and the hand-computed `rowID(4)` present in both |

**Mutations.** M2a: `firstIndex` ignored (reddens 2.1, 2.5). M2b: the height
answer made greedy, i.e. K6's (reddens 2.1, 2.2). M2c: the width answer made 0
on a nil axis, i.e. K6's (reddens 2.4 only — which is what makes 2.4 the pin
for the half of `LR-BR` that diverges). M2d: `planLegacyItems` skipped, rows
registered raw (reddens 2.1's width columns; if it reddens nothing the stretch
claim is unpinned and the lane says so). M2e: the windowed node's
`recordLoweredItem` dropped (must redden 2.7 with an `…unconsumed` entry).
M2f: the rows' records not consumed (same).

### Lane 3 — `ListTests` under both authorities (`LR-BW`)

`ListTests`' private `Row` re-spelled per P3 (§2.3): 224 nodes and 3 leaves.
Every test parameterised over `LayoutAuthority.allCases`, with a roll call in
the shape stage 3's `ScrollAuthorityCoverage` has — **the same file, extended**,
not a second registry, with the 34 literal bumped and `ListTests`' scenario
names added.

**The root problem, and its fix.** `laidOut` and `renderWindowed` make the
`List` the frame's **root**, and a native root is stored at the full window
(`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`), so
`aListSizesItselfToCountTimesRowHeight` would read 600 instead of 280. Both
helpers gain a fixed-size `Box` wrapper (P1a6's shape, a declared width and a
column direction) under **both** authorities and read the `List`'s bounds from
`elementBounds` rather than from the root. Three tests' literals change
spelling, not value.

**Arms that stay legacy-only, each with its owner named in the test:**
`aListInsideADeferredIgnoresTheEscapedScrollersOffset` — `Deferred` as a
presentation root is **stage 5**.

**Red before.** Running `ListTests` under `.proposal` at lane 2's HEAD is the
red: the parameterised arms exist and the `Row` is still legacy-spelled, so the
proposal arms trap at `SA-G` (`legacy layout node given a native child`) — the
same shape P1a hit in this design's own first prototype run. The lane records
the trap message and the count.

**Mutations.** M3a: `ScrollAuthorityCoverage.authorities` reduced to
`[.legacy]` (must redden the roll call — the mutation stage 3's `LR-BN` wrote
the registry for). M3b: the re-spelled `Row`'s proposal branch made a bare
`requestNativeLeaf` (must redden
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` under `.proposal`,
because a directly-registered native leaf records no `LoweredItem` — the
measured reason `ProbeLeaf` is not the re-spelling, §2.3).

### Lane 4 — retention, focus and accessibility under both authorities (`LR-BU`)

The five suites that hold what §4.1 protects, each parameterised:

| test | arms |
|---|---|
| `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` | both authorities, both halves each (short excursion survives, long one does not) |
| `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` | both authorities, both halves |
| `AXNodeTests`' three `List` tests, including `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount` | both authorities |
| `AccessibilityTreeTests`' two `List` tests (the table, its rows and their `AXIndex`es) | both authorities |
| `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` (divergence 14) | both authorities, still asserting the **wrong** answer on purpose, with the message updated to say it is pinned on both paths |

**Red before.** Each is red under `.proposal` at lane 3's HEAD only if
`ListTests`' re-spelling has not reached these files' own row fixtures; the
lane's first act is to run them under `.proposal` and record which fail and
why, before changing anything.

**Mutations.** M4a: `staleAfterGenerations` 2 → 3 (must redden both excursion
tests, on both authorities — four failures, not two; fewer means an arm is
vacuous). M4b: `indexesRows` forced true regardless of `windowIsBounded`
(must redden the unbounded-window arm of the accessibility tests on both
authorities, `AB-X` rule 1). M4c: `windowAwaitsViewport`'s
`requestAccessibilityRetry()` removed (must redden `AB-X` rule 3's pin).

### Lane 5 — work, the 100 000-row test, and the demo census (the exit test)

`aListsWorkIsTheSameFor100kRowsAsFor500` parameterised over both authorities,
extended to count **native** work as well as tokenizer calls; the cold frame
re-measured and re-printed at both authorities; `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
re-derived per §4.2(c). §7 is this lane's exit criterion.

**Red before.** The `.proposal` arm of the 100 000-row test cannot run at lane
4's HEAD unless everything `demoLikeRows` builds is lowered; the lane runs it
first and records what it finds. `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
is red the moment lane 2 lands (its `#expect(report.unlowerable == [entry(.list,
"noLowering")])` cannot hold) and is deliberately left red across lanes 3 and
4 rather than patched early, so the census is re-derived once, from a finished
stage. **The lane must say so in its commit message**, because a red exit test
across three lanes is otherwise indistinguishable from a regression.

**Mutations.** M5a: the window widened by one row (must redden the work
equality at 500 vs 100 000 only if the literals are per-realized-row — if it
does not, the work test is counting something that does not depend on the
window and the lane says so). M5b: `visibleRange`'s `viewportExtent > 0` guard
removed (must redden the cold-frame row count at both authorities — `MP-I`).
M5c: the demo census's `report.elements` literal (must redden 2.15; a count a
later loop indexes on is `try #require`, shape 13).

## 7. The exit test

Two tests, both named by §4.1 row 4.

**(1) `aListsWorkIsTheSameFor100kRowsAsFor500`**, env-gated
(`METALUI_RUN_100K_LIST_TEST=1`), parameterised over both authorities:

- the cold frame at 100 000 rows is timed and **printed, not asserted** (its
  current shape, and CLAUDE.md's rule that performance tests count work);
- tokenizer calls and `ShapingCache.storageCount` equal at 500 and 100 000, as
  today;
- **new**: `LayoutTree.lastNativeLayoutWork`'s `measureCalls`, `cacheHits` and
  `cacheMisses` equal at 500 and 100 000 under the proposal authority, **and**
  each equal to a literal hand-derived before the run (§2.5 is the shape; lane
  5 derives the exact numbers on a branching count, not by reading them off the
  first run).

**(2) The `ListTests` windowing arms under the proposal authority**: every
scenario in `ListTests` except the `Deferred` one runs under
`LayoutAuthority.allCases`, and the roll call in `ScrollAuthorityCoverage`
verifies the set — so a lane that quietly reduced the `arguments:` list to
`[.legacy]` fails rather than passing with the same test count. A
parameterised test counts as **one** test in the summary line, which is why the
roll call exists at all (`LR-BN`).

**Plus the census**, which is not named in §4.1 but is the stage's real
integration check: `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
re-derived, with `report.unlowerable` empty (modal off).

## 8. Demo, pixels and captures

**Every lane: 0 differing pixels in all twelve `CN-R` images against
`f2e981f`**, controls non-zero first (light vs dark 1 048 576; default vs modal
1 030 498; default vs animation 210 027; f0 vs f3 0; preview light vs dark
1 048 576 — record §25 §7.6's figures). The demo is never scrolled in those
images, so no scroll indicator is painted in any of them.

Production runs the legacy authority until stage 6b, and §4.2(a) is the whole
of stage 4's legacy change: an element that emits nothing becomes a node. A
non-zero reading is a **finding**, not a number to record.

**Real-window capture** only if
`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` prints no `CGSSessionScreenIsLocked` line and `displayAsleep
main: 0`; then `docs/probes/window-capture/capture.sh <scratch dir> f2e981f
<HEAD>`, and its table goes in the record. Never `IOConsoleLocked` (`FR-V`).

## 9. Deferred, each with an owner

| deferred | owner |
|---|---|
| **Divergence 14's fix**, now mechanically available: `placeSubviews` receives root-absolute bounds, so the windowed layout can store its own offset within the scroller and window against it on the next frame (§4.3). Trades divergence 14 for a one-frame lag of divergence 13's shape | **stage 6b** |
| **Divergence 13's one-frame-stale viewport extent** | unchanged; stage 6b at the earliest, with 14 |
| The legacy spacer node, `rowStyle.flexShrink`, `rowStyle.minSize.height` and `List.style.flexDirection`/`size.height` — everything that exists only to make a CSS flex column behave like `index × rowHeight` | **stage 9/10**, with `Style`'s CSS fields |
| `LoweringSite.list`'s remaining reachability (`flexGrow.weights` on rows, which no row declares) | whoever first needs a row-level item field |
| `String(describing: datum.id)` not being injective (two ids that describe alike share one `StateTable` entry) — unchanged by this stage, still unguarded | unowned; `ElementID` is `String`-backed, a framework-wide job |
| Variable row heights (a prefix-sum index) | out of scope for task 7 entirely |
| Committing the `CN-R` harness | **stage 6b** (carried from `LR-BJ`) |
| A real-window capture of the demo | whoever runs with an unlocked screen |
| `ProposalScrollView` publishing a `ScrollContext`, so a `List` could window inside one | stage 11 / task 10 (carried from `LR-BF`) |
| Everything stages 5–14 already own | unchanged |
