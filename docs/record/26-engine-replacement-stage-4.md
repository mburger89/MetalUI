# §26 — Engine replacement, stage 4: the windowed proposal `List`

Plan task 7, stage 4 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 4).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-4-design.md`. Rulings
`LR-BQ`…`LR-BW` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`.
Branch `feat/engine-stage-4` from `f2e981f`.

**Status, 2026-09-23 (PDT): design only.** Nothing under `Sources/` or `Tests/`
has changed in a commit. Every prototype below was applied in
`/Users/maxburger/Developer/MetalUI-stage-4`, built, run and restored from a
`cp` copy, with `git status --short` empty afterwards.

## 1. Baseline at `f2e981f`

`swift build --build-system native --build-tests`, then `swift test
--build-system native --no-parallel`, unfiltered:

| measure | value |
|---|---|
| suite | **1580 tests in 2 suites**, passed, in 52.3 s |
| `error:` / `warning:` | 0 / only SwiftPM's `--build-system native` deprecation notice |
| goldens | **97** (`find Tests/MetalUILayoutTests -name "*.json" \| wc -l`) |
| working tree | clean |

Filtered run of the four suites this stage touches most
(`ListTests|TombstoneTests|FocusTests|MeasurePerformanceTests`): **62 tests, 1
suite, passed** in 2.5 s, with
`theResidentEntrySetStaysBoundedWhileScrolling10kRows` printing `table.count`
**256 / 256 / 150** at frames 10 / 100 / 299.

## 2. Measurements

### 2.1 Probe K6, re-run

`/usr/bin/swift docs/probes/swiftui-stack-algorithms.swift`, Apple Swift 6.4
(swiftlang-6.4.0.33.1), macOS 27.0. Exit 0.

**The whole stdout is byte-identical to the reading recorded in the probe's own
header.** Checked mechanically rather than by eye: the header's recorded output
was extracted (`grep -E '^//   '`, prefix stripped), trimmed to the first line
of real output, and `diff`ed against the run — 787 lines, empty diff. The K6
arms:

```
K6 control fixed 30x30 at 100x100 @100x100: size 30x30
K6a List{Text} at 100x100 @100x100: size 100x100
K6b List{Text} at nil @nilxnil: size 0x0
K6c List{Text} at 100 x nil @100xnil: size 100x0
K6d List{Text} at nil x 100 @nilx100: size 0x100
K6e List{Text} at inf x inf @infxinf (measured only): size infxinf
K6f List{leaf l 30x30} at 100x100 (is a row laid out?) @100x100: size 100x100
```

Reading: SwiftUI's `List` is greedy and content-blind — the proposal on a
concrete axis, 0 on a nil one, ∞ at ∞, and a row's own size never reaches the
answer (K6f 100×100 against the K6 control's 30×30). `LR-BR` records why
MetalUI's `List` follows this on one half of one axis and not elsewhere.

### 2.2 Prototype P1 — today's baseline, and `List`'s site check removed

All arms through `LayoutDifferential.compare`, which renders
`DifferentialRoot { … }` under each authority and compares element bounds,
scene bytes (as emitted and as finalized), hitboxes, accessibility records and
`StateTable` ids.

**P1a — at `f2e981f`, unmodified.** `ScrollView(.vertical) { List(20 rows,
rowHeight 10) { ProbeLeaf } }` at 100×100:

```
unlowerable: ["list.noLowering"]
elements=44 agree=3 disagree=1 legacyOnly=40 loweredOnly=0
scenes=false hitboxes=true ax=true state=false
```

The 40 legacy-only ids are the rows the proposal side does not build; the one
disagreement is the `ScrollView` viewport (legacy 0×200, lowered 0×100 — stage
3's `CN-M`). This is exactly the state record §25 §3.6 handed over.

**P1b — the site check deleted, nothing else changed.** `List.requestLayout`'s
four `lowersToProposal` lines replaced by `let lowersToProposal = false`, so
the existing spacer-plus-rows `Box` goes through stage 2's container lowering.
Five arms:

| arm | shape | result |
|---|---|---|
| **P1a6** | `Box(width 100, column) { List(3 rows, 28) { Box() } }` | **0 unlowerable, 11 ids, 0 disagreeing, `state=true`** |
| **P1a2** | bare `List(6 rows, 10) { ProbeLeaf(7×3) }` under the harness root | 0 unlowerable; every row's y (0, 10, 20, 30, 40, 50) and height (10) agree; widths differ (7 vs 100); row content 7×10 vs 7×3 |
| **P1a3** | `ScrollView { List(10 rows, 28) { ProbeLeaf }.padding(60) }` at 200×200 | 0 unlowerable, `state=true`; rows at y = 60, 88, 116, 144, 172, 200, 228, 256, 284, 312 on **both** sides; widths differ (7 vs 80); the `ScrollView` 127×400 vs 200×200 |
| **P1a4** | `List(3 rows, 28) { ProbeLeaf(7×60) }` | 0 unlowerable; row boxes 28 tall on both sides; row content 7×28 vs 7×60 |
| **P1a** (re-run) | as P1a but with the check removed | `unlowerable: []`, 44 ids, 43 disagreeing — all width-only, `state=true` |

**Attribution of the disagreements.** Two causes, both outside `List`:

1. **`DifferentialRoot`'s divergence 53** — the native `.topLeading` overlay
   root proposes its full `width × height` where the legacy `display: .stack`
   root offers fit-content (the harness's own header says so). Every arm
   without a declared-width container inherits it; P1a6 puts one in and the
   family vanishes.
2. **`ProbeLeaf` records no `LoweredItem`** — its proposal branch calls
   `pass.frame.requestNativeLeaf` directly, so `planLegacyItems` cannot plan it
   and it is never stretched. This is `LR-T` seen from the inside, and it is
   what `LR-BW` turns into a re-spelling rule for `ListTests`.

**The finding.** `List`'s CSS structure — a leading spacer `Box` sized
`window.lowerBound × rowHeight`, `flexShrink: 0` and `minSize.height: 0` on
every row, a declared `size.height` of `count × rowHeight` — **already lowers
through stage 2 with no diagnostic and, given a declared-width container,
agrees with the legacy engine element for element, windowed and unwindowed,
padded and scrolled.** `LR-BQ` is the ruling that builds the windowed layout
anyway, with its four reasons and the fallback this measurement provides.

### 2.3 Prototype P1c — the cold frame and the resident entry set

Debug, this machine, `ScrollView(.vertical) { List(n rows, rowHeight 20) { a row
registering a scroll region } }` at 200×400, legacy authority, one `StateTable`
across all frames:

| n | cold frame | cold regions | `table.count` cold | warm frame | warm regions | after 30 scroll frames |
|---|---|---|---|---|---|---|
| 500 | **0.0292 s** | 501 | 506 = `n + 6` | 0.00285 s | 25 | **128** |
| 10 000 | **0.534 s** | 10 001 | 10 006 = `n + 6` | 0.00686 s | 25 | **178** |

`n + 6` and not `2n + 6` because this fixture's rows carry no `@State` — only
each row `Box`'s unconditional `$anim`. The six fixed entries are the
scroller's `ScrollState`, the `List`'s `$ax` slot, the `List`'s own `Box`'s
`$anim`, **the windowing spacer `Box`'s `$anim`**, and `ScrollView`'s content
and viewport `$anim`s. `LR-BS` removes the fourth.

The warm window is 24 rows plus the scroller's own region at **both** row
counts (a 400pt viewport over 20pt rows, `overscan` 2 each side) — the
`O(window)` property the exit test counts, measured rather than argued.

### 2.4 Prototype P2 — the windowed `ProposalLayout`, through a group

A scratch `ElementGroup` registering its member `Box`es and then returning
**one** node — a `ProposalLayout` over them — under the proposal authority, and
a bare spacer node plus the members flat under the legacy one. The layout
answers `(proposal.width ?? 0, rowHeight × logicalCount)` and places subview
*i* at `(bounds.x, bounds.y + (firstIndex + i) × rowHeight)` with proposal
`(bounds.width, rowHeight)`. Host: `Box(width 100, column) { … }` at 100×300.

**P2, 6 rows, `firstIndex: 0`** — `0 unlowerable, 9 ids, 0 disagreeing,
state=true`:

```
== 0                      (0,0) 100x300  /  (0,0) 100x300
== 0/0                    (0,0) 100x60   /  (0,0) 100x60
== 0/0/0                  (0,0) 100x60   /  (0,0) 100x60
== 0/0/0/'item-0'         (0,0) 100x10   /  (0,0) 100x10
== 0/0/0/'item-1'         (0,10) 100x10  /  (0,10) 100x10
… 'item-2' 20, 'item-3' 30, 'item-4' 40, 'item-5' 50, all 100x10
```

**P2b, rows 3…8 of a 20-row list, `firstIndex: 3`** — `0 unlowerable, 9 ids, 0
disagreeing, state=true`; the container 100×200 on both sides; rows at y = 30,
40, 50, 60, 70, 80, each 100×10 on both sides.

**Three things this established, each of which `LR-BS` rests on:**

1. A group may return one node wrapping its members; the enclosing `Box`'s
   `lowerLegacyNode` consumes that node's `LoweredItem` exactly as it consumes
   a child element's, and `reportUnconsumedLoweredItems` names nothing.
2. The rows get their cross-axis stretch from the group's own
   `planLegacyItems`/`registerLegacyItems` call, with `parent:` the `List`'s
   declared style, `parentKind: .flex(isRow: false)` and `parentSite: .list` —
   which is also what keeps `LoweringSite.list` reachable (`LR-BV`).
3. `stateSlotsEqual` is **true**, because the spacer is a bare node on the
   legacy side rather than a `Box` element, so neither authority mints a
   `$anim` entry for it.

An earlier reading of P2 showed only 3 ids: the scratch group's
`prepaintGroup` was calling each row's `prepaint` with a placeholder
`GlobalElementID` and never calling `Frame.recordElementBounds`, so no row
reached `elementBounds`. Recorded because the same shape would make a real
lane's differential silently vacuous — a harness that compares nothing agrees.

### 2.5 Prototype P3 — the `ListTests` row re-spelling

`ListTests`' private `Row` re-spelled to branch on `pass.lowersToProposal` and
call `pass.lowerLegacyNode(Style(), declared: Style(), children: [], site:
.customElement)` — and `lowerLegacyLeaf` over a `requestNativeLeaf` in the
`contentHeight` arm — where it called `pass.requestNode`/`pass.requestLeaf`.
Host `Box(width 100, column) { List(3 rows, 28) { Row } }` at 100×300, with
P1b applied:

| arm | result |
|---|---|
| plain (`contentHeight` nil) | 0 unlowerable, 11 ids, **0 disagreeing**; rows 100×28 at y 0/28/56, row nodes 0×28 |
| tall (`contentHeight` 60) | 0 unlowerable, 11 ids, **0 disagreeing**; rows 100×28, row nodes **0×28** on both sides |

The tall arm is `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent`'s exact
assertion, agreeing under both authorities. Contrast P1a4, where the same shape
spelled with `ProbeLeaf` reads 7×28 legacy against 7×60 lowered. `LR-BW` is the
ruling.

### 2.6 Prototype P1d — kernel work over a stack of rows

`LayoutTree.lastNativeLayoutWork` over a vertical linear stack of *n* fixed
28pt rows inside a frame inside a scroll viewport, driven directly on the
kernel at a 400×100 proposal:

| n | `measureCalls` | `cacheHits` | `cacheMisses` |
|---|---|---|---|
| 14 | 14 | 86 | 59 |
| 500 | 500 | 3 002 | 2 003 |

Linear in the **realized** row count and independent of the logical count —
the claim the exit test makes. It also shows what `LR-BQ` reason 4 concedes:
the free lowering's work is already O(window), so the exit test cannot tell the
two arrangements apart. Lane 5 hand-derives the literals for the real shape
before running it.

## 3. What the design decided, in one place

| question | answer | ruling |
|---|---|---|
| build a windowed `ProposalLayout`, when the CSS structure already lowers? | yes — stage 9 forces it, it states the invariant once, and the free lowering becomes the oracle | `LR-BQ` |
| what does the layout answer? | content extent on the stacking axis, the proposal (else the widest row) on the other; K6 consulted and not followed | `LR-BR` |
| where does the arrangement live, given row identity? | an `ElementGroup`, not an element; the spacer demotes to a bare legacy node | `LR-BS` |
| divergences 13 and 14? | unchanged, and pinned on both authorities; 14's fix becomes available and is deferred to 6b | `LR-BT` |
| accessibility? | untouched by construction; the **records** pinned under both authorities, not reasoned about | `LR-BU` |
| `LoweringSite.list`? | stays, reachable through `parentSite:` and `…unconsumed` | `LR-BV` |
| how do `ListTests`' 224 nodes and 3 leaves re-spell? | through the lowering, not as bare native probe leaves | `LR-BW` |

## 4. For the implementer

Five lanes, each red first, in `docs/superpowers/specs/2026-09-23-engine-stage-4-design.md`
§6. Three things that are easy to get wrong and are measured above rather than
assumed:

- **`swift package clean` before lane 1's first build and again before the
  merge.** `List` is public and crosses a module boundary, and both its stored
  `box` property's type and its `Layout` change.
- **`aWindowedListAgreesWithTheLegacyEngineOnEveryWindowedShape`'s literals are
  §2.4's and §2.5's tables**, written before the implementation exists. They
  came from a prototype of the fallback, which is what makes them a red-first
  oracle rather than a transcription of the first green run.
- **A differential arm that records no element bounds agrees with everything**
  (§2.4's note). Any new harness code that walks rows owes a
  `recordElementBounds` call, and any arm reporting suspiciously few ids is
  measuring nothing.
