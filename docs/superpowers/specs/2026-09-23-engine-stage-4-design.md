# Engine replacement, stage 4 — the windowed proposal `List` (plan task 7)

**Status, 2026-09-23 (PDT): lane 1 landed; lanes 2–5 design only.** Lane 1's
four commits are on `feat/engine-stage-4` (`511ae3d`, `136f171`, `eb42883`,
`ca5a546`); its corrections are `LR-CC` and record §26 §6. Nothing of lanes 2–5
under `Sources/` or `Tests/` has changed in a commit. Every source patch cited
below as a *prototype* was applied in `/Users/maxburger/Developer/MetalUI-stage-4`,
built, run and restored from a `cp` copy, with `git status --short` clean
afterwards; the measurements are in `docs/record/26-engine-replacement-stage-4.md`.

**Critic round 1 raised 15 defects; all 15 were confirmed against the source and
all 15 are applied.** Five carried a design decision of their own and are ruled
`LR-BX`…`LR-CB`; six amended an existing ruling in place (`LR-BQ`, `LR-BR`,
`LR-BS`, `LR-BT`, `LR-BU`, `LR-BV`, `LR-BW` carry a paragraph headed **Amended,
stage-4 critic round 1**). §10 is the disposition table. Nothing was rejected,
so no ruling records a rejection.

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
10. [Critic round 1 — the fifteen, and where each landed](#10-critic-round-1--the-fifteen-and-where-each-landed)

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

**Critic round 1 re-ran two probes independently, both byte-identical to their
headers**: `swiftui-stack-algorithms.swift` (exit 0, 787 lines, empty `diff`,
K6a–K6f reproducing as `LR-BR` quotes them) and
`swiftui-layout-protocol-contract.swift` (89 lines, byte-identical to the first
89 recorded, its arm **I2** independently supporting `LR-BT`'s premise that
`placeSubviews` bounds are host-absolute and its arms J/K supporting `SA-E`'s
record-then-place rule the windowed layout depends on). **The round's fifteen
findings are all about MetalUI's own source, not about SwiftUI**, so none of
them changed a probed claim and none of them needed a new probe. The round's
one SwiftUI-facing correction is a *cost*, not a behaviour (§3.2, `LR-CA`).

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
paths**, because `planLegacyItems` renders both remaining lines inert and P3
measured both sides identical — so the devices are inert rather than removed,
and the file keeps ONE row style instead of two that can drift. `LR-BS` records
the alternative (a proposal-only row style) and why it was rejected.

**How each is inert, corrected after critic round 1 (`LR-BZ`).** The first
statement of this paragraph said `flexShrink: 0` "lowers to a `fixedSize` over a
node whose frame already declares `rowHeight`". **That is false for a `List`
row**, and a later reader would have believed a wrapper protects `List` that is
never registered:

- `minSize.height: 0` — right as stated. `paddedAndSized`'s `folded(...)`
  (`LegacyLowering.swift:490-491`) folds a zero minimum into the declared
  `size.height`, which already reads `rowHeight`.
- `flexShrink: 0` — **lowers to nothing at all, no wrapper and no report.**
  `plan.fixedSizeHorizontal` is assigned only under
  `d.flexShrink == 0 && mainAuto` (`LegacyLowering.swift:858-861`), and it is
  assigned `isRow`. A `List` fails that twice over: in a column parent
  `mainAuto` is `d.size.height == .auto` and a row declares
  `size.height = rowHeight`, and `isRow` is `false` there anyway, so the
  assignment would write the default even if it were reached.

The conclusion survives, and more strongly than before — the line is not merely
rendered inert by a compensating wrapper, it is dropped on the floor. **Lane 2
owes mutation M2g** (`rowStyle.flexShrink` dropped from the record the group
hands `planLegacyItems`, proposal path only) with the prediction written down
first: **it reddens nothing**, in the shape `LR-BQ` reason 4 already uses. A
mutation that reddens nothing is a broken instrument or the finding, so the lane
must also show the mutant's `LegacyItemPlan` differing from the original's
before banking the prediction — or, if the plans are byte-identical, say that
the "mutation" changed no program and find another.

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
  content, as the legacy engine does. What that costs is §3.2.1, corrected
  after critic round 1.
- **no baselines** (`LayoutMeasurement.firstBaseline`/`lastBaseline` have no
  producer and no consumer; CLAUDE.md's declared-but-inert table).

#### 3.2.1 What the two paths actually measure (`LR-CA`)

The first statement of this section priced the concrete path at **zero** subview
measurements and the nil path at **one per realized row**. Both understate, and
the second understates badly. The corrected arithmetic, read off
`LayoutTree.placeCustom` (`Sources/MetalUILayout/LayoutTree.swift:1040-1070`)
and `List.visibleRange` (`Sources/MetalUI/List.swift:323-339`):

- **`placeCustom` measures every child again after `placeSubviews` returns**, at
  the recorded proposal, to turn the record into a rect. So *placement alone*
  costs **one `measureNative` per realized row on both paths**, whatever
  `sizeThatFits` did. "Zero measure calls on the common path" was true of
  `sizeThatFits` and false of the layout.
- **On the concrete-width path** that is the whole cost: 1 lookup per realized
  row, and the realized row count is the window's — `O(window)`, independent of
  `logicalCount`, which is the exit test's claim.
- **On the nil-width path it is 2 lookups per row at two different proposals**
  — `sizeThatFits` measures at `(nil, rowHeight)`, `placeSubviews` records
  `(bounds.width, rowHeight)` — so the second is a cache **miss**, not a hit.
- **And on that path every row is realized.** The only composition that reaches
  a nil width is a vertical `List` inside a horizontal `ScrollView`, and
  `visibleRange` declines to window a non-`.vertical` context, returning
  `0..<count`. So the nil-width path is **2 lookups per LOGICAL row**, not per
  windowed row: `O(logicalCount)`, unbounded, at any row count.

That is a real cost and it is named rather than hidden. It is **not** a
regression — the legacy engine lays out every row in the same composition, for
the same reason — and it is not on any path production or the demo builds. Two
obligations follow, both lane 2's:

- **test 2.4b** takes `lastNativeLayoutWork` (`measureCalls`, `cacheHits`,
  `cacheMisses`) on the nil-width path at **two row counts** and records the
  slope, so the `O(logicalCount)` claim is measured rather than argued;
- the numbers go in the record beside §2.5's, and if the slope is not 2 per
  logical row the lane has found something this section did not predict.

Mitigating it (windowing a nil-width `List` against something other than a
scroll context, or answering a cached widest row) is **not** stage 4's: it
would change `visibleRange`, which §3.3 and `LR-BT` pin shut. §9 carries it.

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
  **checkpoint** counts (256 / 256 / 150 today) are re-measured, not adjusted —
  **lane 1 read 255 / 255 / 149**.
- **Divergence 18's crossing point moves from 125 rows to 126** (`LR-BZ`; the
  first statement of this bullet said it does not move, and was wrong). The
  count moves by one in the fixed overhead, not per row — `2n + 7` becomes
  `2n + 6` on `demoLikeRows(_:)`, whose rows have no `.padding` — but the reap
  gate is `storage.count > Self.sweepThreshold` with `sweepThreshold == 256`
  (`StateTable.swift:228`, `:543`), so crossing needs **257**, not 256:

  | | formula | first crossing *n* | value there |
  |---|---|---|---|
  | today | `2n + 7 ≥ 257` | **125** | 257 |
  | after `LR-BS` | `2n + 6 ≥ 257` | **126** | 258 — and *n* = 125 reads 256, which does **not** cross |

  Lane 1 re-measures both the formula and the crossing **by running them**, not
  by this arithmetic: it renders `demoLikeRows(125)` and `demoLikeRows(126)` and
  reads `table.count` and whether a reap occurred. Two documents quote the old
  pair and are **Docs-phase obligations**: CLAUDE.md's divergence-18 row
  (`2n + 7`, "crossing at **125 rows**", "1007 at 500") and `List.swift`'s type
  doc (`:50-62`, "`storage.count` is exactly `2n + 7`, so 40 rows read 87,
  **125 rows read 257 and cross**, and 500 rows read 1007"). Both take the
  measured numbers, not derived ones.
- The scene and the hitbox list must be **unchanged**: an empty `Decoration`
  emits nothing and an empty `Handlers` registers nothing. Lane 1 asserts them
  against literals taken at `f2e981f` — one string per emitted rect and one per
  hitbox, from a SCROLLED list with painted, clickable rows, so an emission for
  the 84pt spacer would land where nothing else is — and the twelve
  `CN-R` images must read 0. (`scenesEqual`/`hitboxesEqual` are
  `LayoutDifferential`'s cross-AUTHORITY fields and cannot see a before/after
  change on one authority, which is why the pin is literals.)
- **The demo census `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
  loses one id here, and lane 1 pays it** rather than leaving the suite red for
  lane 5: the spacer's `Frame.elementBounds` row disappears from **both** sides,
  so 2036 → **2035** ids and 30 → **29** disagreements, 2042 → **2041** and
  36 → **35** with the modal on, with `agreeing` 6 and `legacyOnly` 2000
  unmoved. Measured. Lane 5 still owns the census's real re-derivation, §4.2(c).

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
agreement test.

**`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `List` arm becomes an
ABSENCE arm, and the source already settles which** — the first statement of
this bullet deferred the choice to lane 2 "by measurement", which critic round 1
showed was deferring a question the source answers (`LR-BZ`, and `LR-BV` amended
in place). `planLegacyItems`' weights check filters
`$0.declared.flexGrow > 0` and fires only at **two or more distinct** factors
(`LegacyLowering.swift:810-823`). Every record the group hands it is a row
`Box` carrying `rowStyle`, built inside `List.requestLayout`
(`List.swift:360-363`), which sets no `flexGrow`; the caller's closure produces
the row's **content**, one level below the row `Box`, and its records are planned
at the row `Box`'s own site, not at `.list`. So the weights entry is
**unreachable from outside `List`** — provably, not by measurement — and `.list`
sits in exactly `component`'s post-`LR-BO` position. The arm therefore asserts
`[]`, in the shape the two `Component` arms already have, and
`try #require(arms.count == 10)` **stays at 10**.

Lane 2 still runs it: what the source proves is that the *weights* entry cannot
be raised, not that the arm reports nothing at all. Test 2.7's first half — a
plain `List`'s `unlowerableFields.isEmpty` — is the measurement that says the
absence is total, and a non-empty report there is a finding.

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

**One term of divergence 14's fix became available; the other did not**
(`LR-BT` amended after critic round 1, which caught this claim overstating
itself). A `ProposalLayout`'s `placeSubviews` receives **root-absolute
`bounds`** — true, and independently re-confirmed by arm **I2** of
`docs/probes/swiftui-layout-protocol-contract.swift`, re-run today
(`I parent bounds (120.0, 70.0, 100.0, 100.0)`). So the windowed layout now
learns, one phase too late to use it, where the `List` sits **in root
coordinates**.

That is one term of two. The window must be chosen against the `List`'s offset
**within the scroller's content**, which is

```
absolute-List-y  −  absolute-scroller-content-y
```

and `ScrollContext` publishes only `offset`, `viewportExtent` and `axis`
(`ScrollView.swift:82-100`). **The second term does not exist**, so the fix is
not "now available by the same one-frame-feedback shape `ScrollView` already
uses": it needs a `ScrollContext` field (the scroller's own content origin,
published from the native viewport stage 3 built) **as well as** the stored
bounds. Stage 4 neither measures nor prototypes that.

Stage 4 does not take it for the reasons it did not take it before — it retires
a wrong-on-purpose pin, it needs its own measurement of the first-frame flash it
trades for, and it is a `List` feature rather than an engine replacement — and
now also because it is a **two-part** change, one part of which is a public
type's storage. The hand-off to **stage 6b** (§9) is re-stated accordingly: 6b
inherits a fix that is *mechanically possible*, not one that is *mechanically
available*, and its first task there is publishing the missing term.

## 5. API and files

All new API is `internal`. No public type gains a case or a requirement.

**`Sources/MetalUI/ListRows.swift`** (new, ~200 lines with its doc comment):

```swift
/// The windowed row arrangement `List` builds, as an `ElementGroup` so that it
/// introduces no identity level between the `List` and its rows.
// Lane 1 lands `rows` and `spacerStyle` only — the legacy arrangement. The
// four fields below it and `WindowedRowsLayout` are lane 2's.
struct ListRows<Row: Element>: ElementGroup {
    var rows: [Box<Row>]
    var spacerStyle: Style
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

**`ListRows` must call each row's `requestGroupLayout` / `prepaintGroup` /
`paintGroup`, not its `requestLayout` / `prepaint` / `paint`.** Those three
entries are where `Element`'s group defaults live
(`ElementGroup.swift:120-170`), and a hand-written group inherits
`recordElementBounds`, `StateBinder.bind`'s per-phase re-bind and
`Frame.suppressingAccessibilityIfHidden` **only** by going through them. Skipping
them compiles, and costs: no row reaches `elementBounds` (so every differential
arm over the list agrees vacuously — record §26 §2.4's own note), `@State` stops
re-binding per phase (`MC-H`, divergence 19), and a `display: none` layer stops
suppressing the rows below it (`AB-O`). `_wrap` has a default, so `ListRows`
owes no witness for it.

**`Sources/MetalUI/List.swift`**: `box` becomes `Box<ListRows<Row>>`, and **two**
of `List`'s witnesses need a public wrapper, not one (`LR-BZ`; the first
statement of this paragraph wrapped only `Layout`):

- `Layout` becomes a `public struct Layout` of `List`'s own with **internal**
  stored properties;
- `PrepaintState` likewise. `List.prepaint` today returns
  `Pair<Box<EmptyGroup>, ArrayGroup<Box<Row>>>.GroupPrepaint`
  (`List.swift:439-442`) and `paint` takes it `inout` (`:462-465`); both become
  `ListRows<Row>.GroupPrepaint`, an **internal** type in a **public** method's
  return and parameter positions. `public struct PrepaintState` with internal
  storage closes it, exactly as `Layout` does.

Then the `lowersToProposal` site check and the `lowersToProposal ? 0..<0 : …`
window collapse to `visibleRange(count:pass:)`; the spacer moves into the group;
the three row style lines and every other line of `requestLayout`, `prepaint`
and `paint` stay. The type doc's paragraphs on the spacer, `minSize.height` and
`flexShrink` are rewritten to say which path each still serves — **not
deleted**: they are the only record of what the legacy answer depends on until
stage 9 — and its divergence-18 paragraph takes lane 1's re-measured numbers
(§4.2(a)).

**`swift package clean` is required** before the first build of lane 1 and
again before the merge: `List` is a public type crossing a module boundary and
its stored `box` property's type **and both** of its witness types change
(CLAUDE.md's rule, and record §12's "turning a stored property into a computed
one fails the incremental link instead").

**`Sources/MetalUI/LayoutAuthority.swift`**: `UnlowerableField.owningStage`'s
`.list` comment (§3.5). No case added or removed.

**Tests touched.** The first statement of this list named the wrong
accessibility file and understated three edits as edits when they are
**re-spellings of a row fixture** (`LR-BX`, `LR-BY`):

| file | what |
|---|---|
| `ListTests.swift` | `Row` re-spelled through the lowering (`LR-BW`); every scenario parameterised; `laidOut` and `renderWindowed` fixed per lane 3 |
| `ListLoweringTests.swift` (new) | the lowering's own eight tests, in the shape `LoweringScrollTests.swift` has |
| `LayoutDifferential.swift` | `render` gains `stateTable:` and `frames:` (`LR-BY`), without which no `List` inside the harness ever reaches a **bounded** window |
| `TombstoneTests.swift` | **`ExcursionRow` re-spelled** — it calls `pass.requestNode` directly (`:93-101`), which under `.proposal` hits `Frame.requestNode`'s backstop and **aborts the process** |
| `MeasurePerformanceTests.swift` | **`StatefulListRow` re-spelled** for the same reason (`:533-541`); `render` gains `reportsUnlowerableFields:` (§7, `LR-BX`) |
| `FocusTests.swift` | its own row fixture, same check as `TombstoneTests`' |
| `AXNodeTests.swift` | three `List` tests (`:642`, `:677`, `:706`), parameterised |
| **`AccessibilityDefaultsTests.swift`** | **the file that actually holds the `AB-L` / `AB-X` pins** — six tests, named in lane 4 |
| `AccessibilityTreeTests.swift` | its two `List` usages (`:144`, `:734`); `:144` sits inside `anInactiveWindowBuildsAndPublishesNothing` and asserts **absence**, so it pins nothing about a table and is not lane 4's subject |
| `ScrollAuthorityCoverage.swift` | renamed, its order argument extended (`LR-CB`) |
| `LayoutAuthorityTests.swift`, `LoweringCorpusTests.swift` | §4.2(d)'s two pins — and, in **lane 1**, the census's one-id edit (§4.2(a)) |
| `ListTests.swift` (again) | **lane 1** strengthens `aScrolledListsSpacerDoesNotShrinkUnderPadding` and `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` with a `Style.padding` arm apiece, because neither could see its subject (`LR-CC` item 2) |
| `Sources/MetalUI/ElementGroup.swift` | doc only: `OptionalGroup`'s divergence-18 paragraph quotes `2n + 7` and 125 (`LR-BZ` item 2) |

**The rule the three re-spellings come from** (`LR-BX`): any row fixture that
registers through `pass.requestNode` / `pass.requestLeaf` **aborts the whole
run** the first time it is built under the proposal authority in a production
frame, with no summary line — so it re-spells through `lowerLegacyNode` /
`lowerLegacyLeaf` **in the same commit that adds its `.proposal` arm**, never
after it.

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

**No lane takes a red-before by aborting the process** (`LR-BX`). A
proposal-authority production `Frame` traps rather than reports, and a trap ends
the run with **no summary line and no list of what failed** —
`LayoutAuthorityTests.swift:180-199` records stage 3 finding exactly this, in
the sentence that says lane 3 could not take its red-before that way. A lane
that needs a red under `.proposal` from a fixture that would trap has two legal
shapes and no third:

- **(a)** re-spell the fixture through `lowerLegacyNode` / `lowerLegacyLeaf`
  **in the same commit** that adds the `.proposal` arm, and take the red on the
  re-spelled fixture — the red is then an assertion failure, which is a red;
- **(b)** take the red **in a child process** with
  `#expect(processExitsWith:)`, as `LayoutAuthorityTests` does, and record the
  trap message and the exit from the child's captured output.

### Lane 1 — `ListRows`, the harness, and the pixel rig (`LR-BS`, `LR-BY`, `LR-CB`)

`Pair(spacer, ArrayGroup(rows))` becomes `ListRows`, with the **legacy branch
only** (the site check stays, so the proposal branch is unreachable). The
spacer becomes a bare node. Lane 1 also lands the two pieces of scaffolding
every later lane reads, because both are wrong today and both are silent about
it:

**(i) `LayoutDifferential.render` renders ONE frame with a fresh `StateTable`,
so no `List` inside the harness is ever windowed** (`LR-BY`;
`LayoutDifferential.swift:171-184`). `ScrollContext.viewportExtent` is one frame
stale, written only by `ScrollChrome.resolvedOffset`'s `PrepaintPass` overload,
so on frame 1 it is 0; `visibleRange` then takes its guard and returns
`0..<count`, and `windowIsBounded` is false, which sends `List.prepaint` down
the `withAccessibilitySuppressed(except: id)` branch that publishes **the table
and no rows**. Prototype P1a3 shows it directly: all ten rows at y = 60…312, no
window. So today `accessibilityEqual` over a `List` compares one record with one
record and passes **vacuously** — record §26 §2.4's own "a harness that compares
nothing agrees". Lane 1 gives `render` a `stateTable:` parameter and a `frames:`
parameter (default 1), threads one `StateTable` through the frames of one side,
and returns the last; `compare` grows **`frames:` only**. It cannot grow
`stateTable:`, and `LR-BY`'s "the same two" was wrong: `Report.stateSlotsEqual`
compares the two sides' tables, so one shared table would make that field read
`true` for every tree — the exact vacuity `frames:` exists to remove, arriving
through the parameter added to remove it (`LR-CC` item 1). A `List` arm that uses it
**must** `try #require` a bounded window and a **non-empty** row-record set on
both sides before asserting anything — the anti-vacuity check is part of the
arm, not a review note.

**(ii) The twelve-image `CN-R` harness is committed here**, under
`docs/probes/demo-pixels/`, with its recipe in its own header (`LR-CB`). It has
now been lost and rebuilt **three times in stage 3 alone** (record §25 §7.6,
§8.8, §9.8), at about an hour each, and five lanes of this stage plus every
later stage read it. Committing it retires §9's "committing the `CN-R` harness"
deferral and `LR-BJ`'s carry. The rebuild is certified against record §25 §7.6's
control figures, **re-taken by running them**, not copied.

**Red before.** The geometry here is not a new behaviour, so this lane is
honestly "green first" for its rects and **red first for its moving numbers**:

| test | red how |
|---|---|
| `theResidentEntrySetStaysBoundedWhileScrolling10kRows` | write `2 * n + 5` **before** the change and read it fail at `2 * n + 6`, then make the change and read it pass — the practice's "require the arms to disagree first" |
| `theListsSpacerIsANodeNotAnElement` (new) | asserts the `StateTable` holds no entry under `child(of: listID, at: 0, name: nil)` after a windowed frame; red at `f2e981f` |
| `aListInTheDifferentialHarnessReachesABoundedWindow` (new) | on the **legacy** authority, two frames, `try #require` a bounded window and a non-empty row-record set; red at `f2e981f` because `render` renders one frame |

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
the measured reason row identity is safe, not as a gap). **M1f**: `render`'s
`frames:` forced back to 1 (must redden
`aListInTheDifferentialHarnessReachesABoundedWindow`; if it does not, the
anti-vacuity check is itself vacuous and the lane says so).

**What lane 1 actually read** (record §26 §6.4, `LR-CC`). M1a reddened 13 issues
across 12 tests, the two named among them. **M1b reddened nothing** — and the
instrument was already blind at `f2e981f`: deleting `spacerStyle.flexShrink`
leaves that test green there, and deleting `rowStyle.flexShrink` leaves the whole
1580-test suite green, because `.padding(_:)` became a WRAPPER at `f1944f8` and
no longer shrinks the `List`'s own content box. Both tests gained a second arm
writing `Style.padding` directly, which still does, and both new arms were then
read red under the mutation they exist for. M1c reddened nothing, for a reason
provable by reading rather than merely unmeasured (the cursor's only consumer is
`enteringGroupMember`, every row supplies a name, and the enclosing `Box`
discards the cursor). M1f reddened
`aListInTheDifferentialHarnessReachesABoundedWindow` at its `!rows.isEmpty`,
reproducing the red-before exactly.

**Measurements owed**: `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s
three checkpoints, re-run; **divergence 18's formula AND its crossing point on
`demoLikeRows`, by rendering 125 and 126 rows and reading `table.count` and
whether a reap occurred** (§4.2(a) — the arithmetic predicts `2n + 6` and a
crossing at 126, and the prediction is written down before the run);
**the windowed `List`'s legacy-side literals through the two-frame harness**,
which are the oracle lane 2's test 2.1 is written against (§4.2 and `LR-BY`:
P2/P2b's `firstIndex: 3` numbers came from a scratch group handed the index
directly, **not** from a real windowed `List`, so they cannot be test 2.1's
literals); the twelve `CN-R` images.

### Lane 2 — `WindowedRowsLayout` and the lowering (`LR-BQ`, `LR-BR`)

`ListRows`' proposal branch, `WindowedRowsLayout`, and `List`'s site check
deleted. `Sources/` only reaches the proposal authority here.

**Red before, and which KIND of red each is.** The first statement of this lane
said all eight "fail at lane 1's HEAD"; four of them do not **compile** there,
because they read `WindowedRowsLayout`'s own answer, and a test that does not
compile is not a red-before and cannot be mutated (`LR-BX`). Splitting the lane
in two was considered and rejected: the layout and the site-check deletion
cannot be green independently — until the check goes, nothing in `List` reaches
the layout — so the honest fix is to classify, not to split. In a new
`ListLoweringTests.swift`:

| # | test | red how | asserts |
|---|---|---|---|
| 2.1 | `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` | **red by failure** at lane 1's HEAD (`list.noLowering`, the 0×0 stand-in) | five arms through `LayoutDifferential.compare` inside a declared-width container — unwindowed, windowed at `firstIndex 3`, padded, scrolled, and a tall row — each `unlowerable.isEmpty`, `disagreeing.isEmpty`, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual`, `stateSlotsEqual`. The windowed, padded and scrolled arms render **two frames per side** and `try #require` a bounded window and a non-empty row-record set first (`LR-BY`). **Its literals are lane 1's re-taken legacy-side numbers**, plus P3's tall-row table |
| 2.5 | `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight` | **red by failure** | row *i* at `firstIndex + i` under the proposal authority, read from `elementBounds` |
| 2.7 | `theListSiteReportsNothingAndItsRowsItemFieldsAreLowered` | **red by failure** | `unlowerableFields.isEmpty` for a plain list; and the **absence** of a `.list` entry, §4.2(d) |
| 2.8 | `aLoweredListsRowIdentitiesAreTheLegacyOnes` | **red by failure** | the two `StateTable` id sets equal, and the hand-computed `rowID(4)` present in both |
| 2.2 | `aWindowedListAnswersItsFullContentHeightAndItsProposedWidth` | **arrives with its subject** — its literals are hand-derived and written into the test before the type compiles, and the first run of the pair is the check | 40×28 → height 1120 at every proposal; width 100 at a 100 proposal |
| 2.3 | `aWindowedListPlacesEachRealizedRowWithExactlyOneMeasurement` | arrives with its subject | `lastNativeLayoutWork` for a concrete-width proposal: **one lookup per realized row, from `placeCustom`, not zero** (§3.2.1), hand-derived before the run |
| 2.4 | `aWindowedListAtANilWidthAnswersItsWidestRow` | arrives with its subject | the nil-axis half of §3.2, and the one place K6 is **not** followed |
| 2.4b | `aNilWidthListMeasuresEveryLogicalRowTwice` (new) | arrives with its subject | §3.2.1's cost, at **two row counts**, recording the slope — the predicted 2 lookups per **logical** row is written down first, and a different slope is a finding |
| 2.6 | `aZeroRowHeightLowersWithoutTrappingOrProducingNaN` | arrives with its subject | `SA-J`'s checkpoints on the degenerate input `List` has always accepted |

The four "arrives with its subject" tests carry no red-before, so **their
evidence is their mutations** — M2b, M2c and the two work counts below — exactly
as stage 3's lane 1 characterization tests did. The lane's commit message says
which four, so a reader does not mistake the absence of a red for an oversight.

**Mutations.** M2a: `firstIndex` ignored (reddens 2.1, 2.5). M2b: the height
answer made greedy, i.e. K6's (reddens 2.1, 2.2). M2c: the width answer made 0
on a nil axis, i.e. K6's (reddens 2.4 only — which is what makes 2.4 the pin
for the half of `LR-BR` that diverges). M2d: `planLegacyItems` skipped, rows
registered raw (reddens 2.1's width columns; if it reddens nothing the stretch
claim is unpinned and the lane says so). M2e: the windowed node's
`recordLoweredItem` dropped (must redden 2.7 with an `…unconsumed` entry).
M2f: the rows' records not consumed (same). **M2g**: `rowStyle.flexShrink`
dropped from the record the group hands `planLegacyItems`, proposal path only —
**predicted to redden nothing**, for the reason §3.1 now measures
(`fixedSizeHorizontal` is never assigned for a column parent's row with a
declared main size), and the lane shows the two `LegacyItemPlan`s before banking
the prediction.

### Lane 3 — `ListTests` under both authorities (`LR-BW`)

`ListTests`' private `Row` re-spelled per P3 (§2.3): 224 nodes and 3 leaves.
Every test parameterised over `LayoutAuthority.allCases`, with a roll call in
the shape stage 3's registry has.

**The registry is RENAMED in this change, not just extended** (`LR-CB`; the
first statement said "the same file, extended"). `ScrollAuthorityCoverage` /
`everyScrollScenarioRanUnderBothLayoutAuthorities` verify a **scroll** set, and
a name that says "scroll" over a set containing `ListTests`' scenarios is a name
that lies to the next reader. They become `AuthorityCoverage` /
`everyParameterisedScenarioRanUnderBothLayoutAuthorities`, in the same commit
that adds the `ListTests` names, with the 34 literal bumped.

**The header's order argument is extended and re-measured, not inherited.** Its
second half depends on Swift Testing running files in path order, and today it
argues that `ScrollIndicatorTests` → `ScrollRoutingTests` → `ScrollViewTests`
with the roll call declared at the END of the last of the three
(`ScrollAuthorityCoverage.swift:31-38`). Adding `ListTests.swift` and
`ListLoweringTests.swift` happens to be safe **only because both sort before
`Scroll*`** — an accident the header does not state. The lane names the new
files in the argument and **re-measures the ordering twice at its own HEAD**, as
the header's own claim was measured twice.

**The root problem, and the fix stated in terms of observables that exist**
(`LR-BY`; the first statement said both helpers "read the `List`'s bounds from
`elementBounds`", which neither can today). `laidOut` and `renderWindowed` make
the `List` the frame's **root**, and a native root is stored at the full window
(`aNativeRootRunsThroughTheFramePipelineWithoutInvokingFlexLayout`), so
`aListSizesItselfToCountTimesRowHeight` would read 600 instead of 280. Both
helpers gain a fixed-size `Box` wrapper (P1a6's shape, a declared width and a
column direction) under **both** authorities — and to read the `List`'s own
bounds out of that wrapper, three things must change that the design had not
named:

- `Frame.elementBounds` is written only when `recordsElementBounds` is set
  (`Frame.swift:1524-1527`), and **both helpers construct
  `Frame(contentSize:scaleFactor:)`, where it defaults to `false`**
  (`Frame.swift:1463`). Both pass `recordsElementBounds: true`.
- `elementBounds` is written by `Element.prepaintGroup`
  (`ElementGroup.swift:158`) and by `Frame.render` for the root, both
  **prepaint-time**. `laidOut` runs `requestLayout` + `computeRootLayout` and
  **never prepaints** (`ListTests.swift:68-78`), so it would record nothing.
  It gains a prepaint pass. `renderWindowed` already prepaints.
- Both helpers are `private` to `ListTests.swift`, so this is a local copy, not
  an edit to the `ScrollViewTests` / `TextMeasureTests` idiom they were modelled
  on. Neither of those files changes.

**Adding a prepaint pass to `laidOut` is a behaviour change for every test that
uses it**, not only the three: hitboxes, scroll regions, focus entries and
accessibility records all register in prepaint. The lane runs the **full
unfiltered suite** after the change and names anything that moves. **The three
tests' literals are re-measured by running them**, not predicted.

**Arms that stay legacy-only, each with its owner named in the test:**
`aListInsideADeferredIgnoresTheEscapedScrollersOffset` — `Deferred` as a
presentation root is **stage 5**.

**Red before, in a child process** (`LR-BX`). Running `ListTests` under
`.proposal` with a legacy-spelled `Row` does not fail: it **aborts**, at
`Frame.requestNode`'s backstop or at `SA-G`, ending the whole run with no
summary line — the exact failure `LayoutAuthorityTests.swift:180-199` already
documents. So the red is taken as a one-off child-process probe in that file's
shape: `#expect(processExitsWith: .failure)` around a single `.proposal` render
of `ListTests`' host shape with the legacy-spelled `Row`, capturing and
recording the trap message. Then the re-spelling and the `.proposal` arms land
**in one commit**, and from there the reds are ordinary assertion failures.

**Mutations.** M3a: the registry's `authorities` reduced to `[.legacy]` (must
redden the roll call — the mutation stage 3's `LR-BN` wrote the registry for).
M3b: the re-spelled `Row`'s proposal branch made a bare `requestNativeLeaf`
(must redden `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` under
`.proposal`, because a directly-registered native leaf records no `LoweredItem`
— the measured reason `ProbeLeaf` is not the re-spelling, §2.3). **M3c**:
`recordsElementBounds` dropped back to its default in `laidOut` (must redden the
three tests that read the `List`'s bounds; if it reddens nothing, they are not
reading what the lane thinks they read).

### Lane 4 — retention, focus and accessibility under both authorities (`LR-BU`)

The suites that hold what §4.1 protects, each parameterised. **The first
statement of this table named the wrong accessibility file**, which would have
left M4b and M4c reddening legacy arms only — two failures, which `LR-BU` itself
says means an arm is vacuous. The `AXTable`, its `rowCount`, its realized rows'
`rowIndex`es, the unbounded-window rule and the one-more-frame rule are pinned in
**`Tests/MetalUITests/AccessibilityDefaultsTests.swift`**:

| file | test | arms |
|---|---|---|
| `TombstoneTests` | `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` | both authorities, both halves each (short excursion survives, long one does not) |
| `FocusTests` | `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` | both authorities, both halves |
| `AXNodeTests` | its three `List` tests (`:642`, `:677`, `:706`), including `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount` | both authorities |
| **`AccessibilityDefaultsTests`** | `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` (`:461`) — `table.rowCount == 500` at `:475`, `rows.map(\.rowIndex) == (38..<50)…` at `:480` | both authorities |
| **`AccessibilityDefaultsTests`** | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` (`:502`) — `AB-X` rules 1 and 3, at `:515-524` | both authorities |
| **`AccessibilityDefaultsTests`** | `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (`:570`) | both authorities |
| **`AccessibilityDefaultsTests`** | `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` (`:381`) | both authorities |
| **`AccessibilityDefaultsTests`** | `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` (`:740`) | both authorities |
| **`AccessibilityDefaultsTests`** | `aClientDoesNotChangeStateRetention` (`:662`) | both authorities |
| `ListTests` | `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` (divergence 14) | both authorities, still asserting the **wrong** answer on purpose, with the message updated to say it is pinned on both paths |

`AccessibilityTreeTests` has exactly **two** `List` usages (`:144`, `:734`), and
`:144` is inside `anInactiveWindowBuildsAndPublishesNothing`, which asserts
absence and can pin nothing about a table. It is not this lane's subject; its
`:734` arm is parameterised for completeness only.

**Red before, in a child process or on a re-spelled fixture** (`LR-BX`; the
first statement said "run them under `.proposal` and record which fail", which
is a run that aborts). `TombstoneTests.ExcursionRow` (`:93-101`) and
`MeasurePerformanceTests.StatefulListRow` (`:533-541`) both call
`pass.requestNode(style:children:)` directly, which under `.proposal` hits the
backstop `aSiteThatSkipsItsOwnCheckIsStoppedByFramesBackstop` pins as an **exit
test**. So: the lane's first act is one child-process probe per abort-capable
fixture, recording the trap message; then each fixture re-spells through
`lowerLegacyNode` **in the same commit** as its `.proposal` arm, and the reds
from there are assertion failures.

**Mutations, with their required failure counts restated against the right
file.** M4a: `staleAfterGenerations` 2 → 3 (must redden both excursion tests, on
both authorities — **four** failures, not two). M4b: `indexesRows` forced true
regardless of `windowIsBounded` (must redden
`activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` and
`aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` on **both**
authorities — at least **four** failures, `AB-X` rule 1; a mutation that reddens
only legacy arms means the proposal arm is vacuous). M4c:
`windowAwaitsViewport`'s `requestAccessibilityRetry()` removed (must redden
`activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`'s rule-3
half on **both** authorities — at least **two** failures). For each, the lane
**names every test the mutation reddens**, not only the count.

### Lane 5 — work, the 100 000-row test, and the demo census (the exit test)

`aListsWorkIsTheSameFor100kRowsAsFor500` parameterised over both authorities,
extended to count **native** work as well as tokenizer calls; the cold frame
re-measured and re-printed at both authorities; `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
re-derived per §4.2(c). §7 is this lane's exit criterion.

**The lane's first obligation, before any red: `MeasurePerformanceTests.render`
builds a PRODUCTION frame, so its `.proposal` arm aborts the process before it
measures anything** (`LR-BX`; the first statement of this lane said "the lane
runs it first and records what it finds", and there is nothing to record — the
run dies). `render` (`:19-27`) passes no `reportsUnlowerableFields`, and
`demoLikeRows` declares `.minHeight(Pixels(0))` on its root `Box` (`:505-519`),
a `Self`-returning modifier (`Box.swift:905`) that lands on the root's own
`Style`. `reportUnconsumedLoweredItems` skips only `flexGrow`, `flexShrink`,
`flexBasis` and `alignSelf` for the root and **still reports a non-`.auto`
`minSize`** (`LoweringState.swift:109-133`), which reaches `noteUnlowerable`'s
`preconditionFailure` (`Frame.swift:1535-1538`).
`anItemFieldNoLoweredContainerConsumesIsReportedByName`'s root arms already
document that a root's `minSize` reports.

**The fix is a `reportsUnlowerableFields:` parameter on
`MeasurePerformanceTests.render`, defaulting `false`, set `true` for the
`.proposal` arms** — *not* removing `.minHeight(0)` from `demoLikeRows`. That
fixture's own header says removing a pin from it "would silently inflate every
later before/after ratio measured against this harness", and every committed
literal in the file is measured against it; changing the fixture to make one new
arm run would move numbers this stage is supposed to hold still.

**What the diagnostics frame costs, said before the lane starts.** Under
`reportsUnlowerableFields` a site with no lowering gets a 0×0 native leaf in
place of its node (`Frame.unlowerable`), so a report that is *not* empty means
the work counts were taken over a partly degenerate tree. The lane therefore
asserts the report **exactly**: the only entry it may contain is the root's own
`minSize.unconsumed`, which is an artifact of the root being unconsumed and has
nothing to do with `List`. **Any other entry is a finding, and the work numbers
taken alongside it are not to be recorded as this stage's.** The exact site and
spelling of that one entry are read off the run, not predicted here.

**Red before.** With the parameter in place, the `.proposal` arm of the
100 000-row test runs and its reds are ordinary failures.
`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
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
(`METALUI_RUN_100K_LIST_TEST=1`), parameterised over both authorities — **and
its `.proposal` arm needs `MeasurePerformanceTests.render`'s new
`reportsUnlowerableFields:` parameter, or it aborts the process rather than
measuring** (lane 5's first paragraph, `LR-BX`). Two other tests in that file
take `.proposal` arms and share the same two hazards, the frame and
`StatefulListRow`'s direct `pass.requestNode`; the lane fixes both before it
parameterises anything:

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
`LayoutAuthority.allCases`, and the roll call in `AuthorityCoverage` (renamed
from `ScrollAuthorityCoverage` in lane 3, `LR-CB`) verifies the set — so a lane that quietly reduced the `arguments:` list to
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

**The harness this reads is committed by lane 1**, under
`docs/probes/demo-pixels/` with its recipe in its own header (`LR-CB`; the first
statement of this section made five lanes' acceptance criterion rest on a
harness §9 deferred to stage 6b, so it was reproducible from nothing in the
repo). Lane 1 rebuilds it from record §25 §7.6's recipe, **re-takes the control
figures by running them** rather than quoting the five numbers above, and
commits it; lanes 2–5 then run the committed script. If a lane's rebuild
disagrees with a quoted control, the disagreement is the finding and the quoted
number is what gets corrected.

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
| **Divergence 14's fix**, now mechanically POSSIBLE but not available: `placeSubviews` receives root-absolute bounds, which is **one of the two terms**; the other — the scroller's own content origin — needs a new `ScrollContext` field, published from the native viewport (§4.3, `LR-BT` as amended). 6b's first task there is publishing the missing term; only then can the one-frame-feedback shape be written | **stage 6b** |
| **The nil-width `List` path's `O(logicalCount)` measurement cost** (§3.2.1): 2 `measureNative` lookups per **logical** row, because `visibleRange` declines to window a horizontal context so every row is realized. Measured by lane 2's test 2.4b; mitigating it would change `visibleRange`, which `LR-BT` pins shut | **stage 6b**, with divergence 14 and 13 |
| **Divergence 13's one-frame-stale viewport extent** | unchanged; stage 6b at the earliest, with 14 |
| The legacy spacer node, `rowStyle.flexShrink`, `rowStyle.minSize.height` and `List.style.flexDirection`/`size.height` — everything that exists only to make a CSS flex column behave like `index × rowHeight` | **stage 9/10**, with `Style`'s CSS fields |
| `LoweringSite.list`'s remaining reachability (`flexGrow.weights` on rows, which no row declares) | whoever first needs a row-level item field |
| `String(describing: datum.id)` not being injective (two ids that describe alike share one `StateTable` entry) — unchanged by this stage, still unguarded | unowned; `ElementID` is `String`-backed, a framework-wide job |
| Variable row heights (a prefix-sum index) | out of scope for task 7 entirely |
| ~~Committing the `CN-R` harness~~ | **retired: lane 1 commits it** (`LR-CB`), ending `LR-BJ`'s carry |
| A real-window capture of the demo | whoever runs with an unlocked screen |
| `ProposalScrollView` publishing a `ScrollContext`, so a `List` could window inside one | stage 11 / task 10 (carried from `LR-BF`) |
| Everything stages 5–14 already own | unchanged |

## 10. Critic round 1 — the fifteen, and where each landed

Critic round 1 (2026-09-23, against `6a943e1`) raised fifteen defects and
re-ran two probes byte-identically (§2.2). **Every one of the fifteen was
checked against the source and every one holds**, so nothing here is rejected
and no ruling records a rejection. Three of them (D7, D9, D11) corrected a
*mechanism* this design had asserted without reading the code that implements
it; two (D1, D2) would each have ended a lane's run with no summary line; two
(D3, D4) would have left a mutation or a differential arm measuring nothing.

| # | defect | disposition | where |
|---|---|---|---|
| D1 | lane 5's exit test aborts before it measures: `MeasurePerformanceTests.render` is a production frame and `demoLikeRows`' root `.minHeight(0)` reports | **applied** — `render` gains `reportsUnlowerableFields:`; `demoLikeRows` is **not** changed, and the diagnostics frame's cost is stated | §6 lane 5, §7, `LR-BX` |
| D2 | lanes 3 and 4 prescribe red-befores that are process aborts | **applied** — a stage-wide rule with exactly two legal shapes; three row fixtures re-spell in the same commit as their arm | §6 preamble, lanes 3–5, §5, `LR-BX` |
| D3 | lane 4 names the wrong file; `AB-L`/`AB-X` live in `AccessibilityDefaultsTests` | **applied** — six tests named, M4b/M4c's failure floors restated | §5, §6 lane 4, `LR-BU` amended |
| D4 | test 2.1 is unreachable: `LayoutDifferential.render` renders one frame, so no `List` in it is ever windowed and `accessibilityEqual` passes vacuously | **applied** — lane 1 extends the harness; every `List` arm requires a bounded window and a non-empty row-record set; P2/P2b's literals are re-taken through the real `List` | §6 lanes 1–2, `LR-BY` |
| D5 | lane 3's fix reads `elementBounds`, which neither helper produces | **applied** — `recordsElementBounds: true` on both, a prepaint pass in `laidOut`, the literals re-measured, and the suite-wide cost of adding prepaint named | §6 lane 3, `LR-BY` |
| D6 | divergence 18's crossing moves 125 → 126; §4.2(a) said it does not | **applied** — corrected, with the gate arithmetic, and lane 1 re-measures by running; CLAUDE.md's row and `List.swift`'s doc become Docs-phase obligations | §4.2(a), `LR-BZ` |
| D7 | `flexShrink: 0` does **not** lower to a `fixedSize` for a `List` row; it lowers to nothing | **applied** — §3.1 corrected with the two reasons it fails the guard, plus mutation M2g with its prediction written first | §3.1, §6 lane 2, `LR-BZ`, `LR-BS` amended |
| D8 | `PrepaintState` needs the same public wrapper as `Layout` | **applied** — two wrappers, and `swift package clean` covers both | §5, `LR-BZ` |
| D9 | `LR-BV` defers a question the source answers: the `.list` weights entry is provably unreachable | **applied** — stated with the reasoning; the arm becomes an absence arm; `arms.count` stays 10 | §4.2(d), `LR-BZ`, `LR-BV` amended |
| D10 | the nil-width branch has no work bound; and `placeCustom` measures every child again, so "zero measure calls" was wrong on both paths | **applied** — §3.2.1 is the corrected arithmetic (`O(logicalCount)`, 2 per logical row); test 2.4b measures the slope; §9 carries the mitigation | §3.2.1, §6 lane 2, §9, `LR-CA`, `LR-BQ`/`LR-BR` amended |
| D11 | `LR-BT`'s "now fixable" is one term of two; `ScrollContext` cannot supply the other | **applied — downgraded rather than prototyped.** Prototyping it would mean designing a `ScrollContext` change stage 4 has ruled itself out of touching; the honest statement costs nothing and the 6b hand-off is re-stated | §4.3, §9, `LR-BT` amended |
| D12 | four of lane 2's eight "red-befores" do not compile at lane 1's HEAD | **applied — classified rather than split.** Splitting lane 2 would separate the layout from the site-check deletion, and neither half can be green alone | §6 lane 2, `LR-BX` |
| D13 | the roll call's name will lie, and its order argument rests on an unstated accident | **applied** — renamed to `AuthorityCoverage` in the same change, the argument extended to the new files and re-measured twice | §6 lane 3, §7, `LR-CB` |
| D14 | every lane's demo criterion rests on an uncommitted harness | **applied, in the stronger form the finding offered** — lane 1 commits it, retiring the deferral, because it has been rebuilt three times in stage 3 alone at about an hour each | §8, §9, §6 lane 1, `LR-CB` |
| D15 | `aTheListsSpacerIsANodeNotAnElement` | **applied** — `theListsSpacerIsANodeNotAnElement` | §6 lane 1 |

**One thing the round checked and found sound**, recorded so the implementer
does not re-derive it: row identity survives the spacer leaving cursor 0, because
a name replaces a position and the `at:` argument is never consulted once a
`name:` is supplied (`TombstoneTests.swift:221-223`, repeated at
`FocusTests.swift:982-985`); and the spacer's demotion emits **no** accessibility
record either way, because `registerHandlers` appends only when
`hasSomethingToSay` (`Frame.swift:962-972`) and an empty-`Handlers` `Box` says
nothing — which is `LR-BU`'s claim, now by measurement rather than by its own
reasoning.
