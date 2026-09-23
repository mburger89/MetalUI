# §26 — Engine replacement, stage 4: the windowed proposal `List`

Plan task 7, stage 4 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 4).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-4-design.md`. Rulings
`LR-BQ`…`LR-CF` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`
(`LR-BX`…`LR-CB` are critic round 1's, §5 below; `LR-CC` is lane 1's,
`LR-CD` lane 2's, `LR-CE` lane 3's and `LR-CF` lane 4's).
Branch `feat/engine-stage-4` from `f2e981f`.

**Status, 2026-09-23 (PDT): lanes 1–4 landed; lane 5 design only.** §6
is lane 1's record, §7 lane 2's, §8 lane 3's and §9 lane 4's. Every prototype in §2 was applied in
`/Users/maxburger/Developer/MetalUI-stage-4`, built, run and restored from a
`cp` copy, with `git status --short` empty afterwards, before any lane started;
§6.4's mutations were taken the same way, after lane 1's implementation commit.

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
| how does a lane take a red under `.proposal` when the fixture would trap? | re-spell in the same commit, or take the red in a child process — never by running an aborting suite | `LR-BX` |
| can the differential harness window a `List`? | **no, not today**; lane 1 gives `render` `stateTable:`/`frames:` and every `List` arm requires a bounded window first | `LR-BY` |
| what does the windowed layout really cost? | 1 lookup per realized row concrete; **2 per LOGICAL row** at a nil width, where every row is realized | `LR-CA` |
| the `CN-R` harness and the authority roll call? | committed in lane 1, and renamed in the change that makes its name wrong | `LR-CB` |

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

## 5. Critic round 1 (2026-09-23), and what it cost

A critic reviewed `6a943e1` against the source and raised **fifteen** defects.
**All fifteen were re-checked here against the source, all fifteen hold, and all
fifteen are applied** — nothing was rejected, so no ruling records a rejection.
The disposition table is spec §10; the rulings are `LR-BX`…`LR-CB`, plus
**Amended, stage-4 critic round 1** paragraphs on `LR-BQ`, `LR-BR`, `LR-BS`,
`LR-BT`, `LR-BU`, `LR-BV` and `LR-BW`.

### 5.1 Probes — re-run by the critic, not re-run again here

The critic re-ran two probes independently and both came back byte-identical to
their headers: `swiftui-stack-algorithms.swift` (exit 0, 787 lines, empty
`diff`, K6a–K6f as `LR-BR` quotes them) and
`swiftui-layout-protocol-contract.swift` (89 lines, byte-identical to the first
89 recorded; arm **I2** `I parent bounds (120.0, 70.0, 100.0, 100.0)`
independently supports `LR-BT`'s premise, and arms J/K support `SA-E`'s
record-then-place rule). **None of the fifteen findings is about SwiftUI** —
every one is about MetalUI's own source — so none changed a probed claim and
none needed a new probe. This round's one SwiftUI-adjacent correction (`LR-CA`)
is a cost, not a behaviour.

### 5.2 The six source reads that settled the high-severity findings

Each was read at the line, not inferred from the prose around it:

| claim | line | reading |
|---|---|---|
| `MeasurePerformanceTests.render` is a production frame | `:19-27` | no `reportsUnlowerableFields`; `demoLikeRows`' root `.minHeight(Pixels(0))` at `:505-519` is a `Self`-returning modifier (`Box.swift:905`), so it lands on the root's own `Style` |
| a root's non-`.auto` `minSize` still reports | `LoweringState.swift:109-133` | the root skip covers only `flexGrow`/`flexShrink`/`flexBasis`/`alignSelf`; `minSize` falls through to `noteUnlowerable`'s `preconditionFailure` (`Frame.swift:1535-1538`) |
| `LayoutDifferential` cannot window a `List` | `LayoutDifferential.swift:171-184` | own `StateTable()`, one frame; `viewportExtent` written only in prepaint (`ScrollView.swift:79-84`), so `visibleRange`'s guard (`List.swift:323-327`) returns `0..<count` and `windowIsBounded` is false (`:370`) |
| `elementBounds` is unreachable from `ListTests`' helpers | `Frame.swift:1463`, `:1524-1527`; `ListTests.swift:68-78`, `:204-224` | `recordsElementBounds` defaults false in both helpers; `laidOut` never prepaints |
| the `AB-L`/`AB-X` pins are in the wrong file | `AccessibilityDefaultsTests.swift:381, :461, :502, :570, :662, :740` | six tests; `AccessibilityTreeTests` has two `List` usages and `:144` asserts absence |
| `flexShrink: 0` lowers to nothing for a row | `LegacyLowering.swift:852-861` | `mainAuto` is `d.size.height == .auto` in a column parent and a row declares `rowHeight`; the assignment is `plan.fixedSizeHorizontal = isRow`, which is `false` there anyway |

### 5.3 Two arithmetic corrections, both against a literal in the source

- **Divergence 18's crossing moves 125 → 126.** The reap gate is
  `storage.count > Self.sweepThreshold` with `sweepThreshold == 256`
  (`StateTable.swift:228`, `:543`), so crossing needs **257**: `2n + 7 ≥ 257`
  first holds at 125, `2n + 6 ≥ 257` first holds at **126**, and *n* = 125 then
  reads 256. Spec §4.2(a) had asserted the crossing does not move. Lane 1
  re-measures both by running 125 and 126 rows; CLAUDE.md's row and
  `List.swift:50-62` are Docs-phase obligations.
- **The layout's measurement cost is not zero on either path.**
  `LayoutTree.placeCustom` (`:1040-1070`) measures every child again after
  `placeSubviews` returns, so placement costs 1 lookup per realized row on both
  paths; at a nil width it is 2 per row at two different proposals, and
  `visibleRange` declines a non-`.vertical` context, so **every logical row is
  realized** and the path is `O(logicalCount)`. `LR-CA`, spec §3.2.1, lane 2's
  new test 2.4b.

### 5.4 What the round changed about the lanes, in one place

| lane | what moved |
|---|---|
| 1 | now also lands the `LayoutDifferential` two-frame fix (`LR-BY`) and **commits the `CN-R` harness** (`LR-CB`, retiring `LR-BJ`'s carry); re-takes the windowed legacy literals through the real `List`; re-measures divergence 18's crossing by running it; new `M1f`; test renamed `theListsSpacerIsANodeNotAnElement` |
| 2 | its eight tests split into four red-by-failure and five that arrive with their subject (2.4b added); new `M2g` with a written-down "reddens nothing" prediction; the `.list` arm settled as an absence arm, `arms.count` stays 10 |
| 3 | the registry is **renamed** and its order argument extended and re-measured; the helpers get `recordsElementBounds: true` and `laidOut` a prepaint pass, with a full-suite run after; red-before moves to a child process; new `M3c` |
| 4 | `AccessibilityDefaultsTests` added with its six tests named; M4b/M4c's failure floors restated against them; red-before moves to a child process plus same-commit re-spellings of `ExcursionRow` and `FocusTests`' row |
| 5 | `MeasurePerformanceTests.render` gains `reportsUnlowerableFields:`; `StatefulListRow` re-spells; the diagnostics frame's cost and the one permitted report entry are stated **before** the lane starts |

### 5.5 The one thing the round checked and found sound

Row identity survives the spacer leaving cursor 0: a name replaces a position
and the `at:` argument is never consulted once a `name:` is supplied
(`TombstoneTests.swift:221-223`, repeated at `FocusTests.swift:982-985`). And
the spacer's demotion emits **no** accessibility record either way, because
`registerHandlers` appends only when `hasSomethingToSay`
(`Frame.swift:962-972`) and an empty-`Handlers` `Box` says nothing — which is
`LR-BU`'s claim, now by measurement rather than by its own reasoning.

**A note for the next round.** Three of the fifteen (`LR-BZ`'s four claims,
`LR-BV`'s deferral, `LR-BT`'s finding) were derived from what a doc comment or a
ruling *says* the code does rather than from the code. The practices rule "walk
every measurement back to the mutated line in the same pass" applies to a
mechanism claim as much as to a number, and this design did not apply it.

---

## 6. Lane 1 — `ListRows`, the harness, and the pixel rig (`LR-BS`, `LR-BY`, `LR-CB`; corrections in `LR-CC`)

Four commits on `feat/engine-stage-4`:

| commit | what |
|---|---|
| `511ae3d` | the red-before: three assertion failures on the unfiltered suite |
| `136f171` | `ListRows`, the spacer's demotion, `List`'s two public wrappers, `LayoutDifferential.render`'s `stateTable:`/`frames:` |
| `eb42883` | M1b's finding: two `List` pins that could not see their subject, each given an arm that can |
| `ca5a546` | `docs/probes/demo-pixels/` — the `CN-R` harness, committed and certified |

### 6.1 The red-before

Unfiltered, `swift test --build-system native --no-parallel` at `511ae3d`
(`f2e981f`'s sources, only tests changed): **1583 tests in 2 suites failed with
3 issues**.

```
theListsSpacerIsANodeNotAnElement
  ListTests.swift:517: Expectation failed: spacerEntries.isEmpty
aListInTheDifferentialHarnessReachesABoundedWindow
  ListTests.swift:573: Expectation failed: !rows.isEmpty
theResidentEntrySetStaysBoundedWhileScrolling10kRows
  MeasurePerformanceTests.swift:440: Expectation failed: table.count == 2 * n + 5
```

The third is the practice's "require the arms to disagree first": the literal is
written at `2 * n + 5` and read failing at `2 * n + 6`.

**`aListInTheDifferentialHarnessReachesABoundedWindow`'s red is taken on the
ONE-frame harness**, which is what makes it a red by failure rather than a
compile error (`LR-BX`: a test that does not compile is not a red-before, and
cannot be mutated). `136f171` adds the two parameters and changes that call and
nothing else in the test; M1f forces `frames` back to 1 and reproduces the
identical line.

`aListsSceneAndHitboxesAreUnchangedByTheGroup` landed green in the same commit,
as a characterization test whose evidence is M1a and M1b. Its two literal arrays
were taken by running it at `f2e981f`.

### 6.2 What landed

`Sources/MetalUI/ListRows.swift` (new, 142 lines with its doc comment).
`Pair(Box(spacerStyle), ArrayGroup(rows))` becomes `ListRows<Row>: ElementGroup`
— **legacy branch only**; `List`'s site check stays, so lane 2 still owns the
arrangement. The spacer is a bare node registered through the identical
registrar (`lowerLegacyNode` under the proposal authority, exactly as the `Box`
it replaced did, so a diagnostics frame is unchanged apart from §6.3's one id).

`List` gained `public struct Layout` and `public struct PrepaintState` over its
internal witnesses — **two**, as `LR-BZ` item 3 said and the first statement of
spec §5 did not. Built after `swift package clean`.

`LayoutDifferential.render` gained `stateTable:` and `frames:`; **`compare`
gained `frames:` only** (`LR-CC` item 1).

### 6.3 Every number that moved, measured

| measure | before | after | how |
|---|---|---|---|
| `theResidentEntrySetStaysBoundedWhileScrolling10kRows` cold frame | `2n + 6` | **`2n + 5`** | the test's own literal, red first |
| its three checkpoints (frames 10 / 100 / 299) | 256 / 256 / 150 | **255 / 255 / 149** | printed by the test |
| divergence 18's formula on `demoLikeRows(_:)` | `2n + 7` | **`2n + 6`** | scratch render at *n* = 40/124/125/126/127/500 |
| divergence 18's crossing | 125 | **126** | the same scratch, by whether a three-generation excursion was REAPED |
| demo census ids / disagreements | 2036 / 30 | **2035 / 29** | the test |
| the same, modal on | 2042 / 36 | **2041 / 35** | the test |
| scene rects and hitboxes of a windowed, painted, clickable `List` | — | **unchanged** | `aListsSceneAndHitboxesAreUnchangedByTheGroup` |
| twelve `CN-R` images | — | **0 differing, every scene dump identical** | §6.5 |
| goldens | 97 | 97 | `find Tests/MetalUILayoutTests -name "*.json" \| wc -l`; `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty |
| typecheck guards | 77 | 77 | per-file `grep -c canTypecheck` |
| suite | 1580 | **1583** | +3 tests, all lane 1's |

**Divergence 18 in full**, and it is the measurement `LR-BZ` item 2 asked for.
Each row renders `demoLikeRows(n)` on a fresh `StateTable`, then three frames of
`demoLikeRows(0)` on the same table — past `staleAfterGenerations` (2), so the
only thing that can keep the rows is the size gate:

| *n* | before, cold | reaped? | after, cold | reaped? |
|---|---|---|---|---|
| 40 | 87 | no | 86 | no |
| 124 | 255 | no | 254 | no |
| 125 | 257 | **yes** | 256 | **no** |
| 126 | 259 | yes | 258 | **yes** |
| 127 | 261 | yes | 260 | yes |
| 500 | 1007 | yes | 1006 | yes |

The gate is `storage.count > sweepThreshold` with `sweepThreshold == 256`, so
crossing needs 257; the before column reproduces CLAUDE.md's `2n + 7`, 125 and
1007 exactly, which is what says the instrument is the right one.
`List.swift`'s and `ElementGroup.swift`'s doc comments take the new numbers in
`136f171`; **CLAUDE.md's divergence-18 row is still a Docs-phase obligation.**

### 6.4 The four mutations

Taken after the implementation commit, each restored from a `cp` copy with
`git status --short` clean afterwards, each on the **full unfiltered** suite.

| mutation | what | reddened |
|---|---|---|
| **M1a** | the spacer's height from `window.count` rather than `window.lowerBound` | **13 issues in 12 tests**: `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `aRowKeepsItsIdentityWhenItsPositionChanges`, `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent`, `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight`, `distinctRowsGetDistinctIdentities`, `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, **`aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop`**, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, **`aScrolledListsSpacerDoesNotShrinkUnderPadding`**, `aFractionalOffsetRoundsFirstDownAndLastUp`, `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, `aListsSceneAndHitboxesAreUnchangedByTheGroup` (both arrays) |
| **M1b** | `spacerStyle.flexShrink = 0` deleted | **nothing**, before §6.6's fix; **`aScrolledListsSpacerDoesNotShrinkUnderPadding`**'s new `paddedYs == expected` after it |
| **M1c** | the group's cursor advanced past the spacer, as `Pair` did | **nothing**, and provably so — see below |
| **M1f** | `render`'s `frames:` forced to 1 | **`aListInTheDifferentialHarnessReachesABoundedWindow`**, at `!rows.isEmpty` — the red-before's own line |

**M1c is a proof, not a gap.** The practice is to show the mutant behaves
differently before banking "reddens nothing". Here the stronger statement is
available by reading: the cursor's only consumer is each row's
`GlobalElementID.enteringGroupMember`, every row supplies a `name`
(`.id(String(describing: datum.id))`), `child(of:at:name:)` never consults `at:`
once a `name:` is supplied, and the enclosing `Box` discards the cursor when the
group returns. The mutation changes a value nothing observes. That is the
measured reason row identity survives the spacer leaving cursor 0.

### 6.5 M1b's finding: two `List` pins that could not see their subject

M1b was predicted to redden `aScrolledListsSpacerDoesNotShrinkUnderPadding`. It
reddened nothing — and the instrument was **already** blind at `f2e981f`,
before this lane touched anything. Measured on an unmodified `f2e981f` tree:

- deleting `spacerStyle.flexShrink = 0` leaves `aScrolledListsSpacerDoesNotShrinkUnderPadding`
  and `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` green;
- deleting `rowStyle.flexShrink = 0` leaves the **whole 1580-test suite** green.

The cause is `f1944f8`: `.padding(_:)` became a wrapper, so the padding lands on
an outer `ModifiedElement` layer and the `List`'s own content box keeps its full
`count × rowHeight`. There is no negative free space left for a spacer or a row
to absorb, and both tests' doc comments describe a mechanism their fixtures
stopped reaching.

`Style.padding` written directly still shrinks the `List`'s own content box
(CLAUDE.md's declared-but-inert table draws that distinction), so each test
gained a second arm that writes it, restoring the deficit the first arm used to
create — 160 against 252 for the spacer, 64 against 84 for the rows. Both new
arms were then read red under their own mutation (`paddedYs == expected`; the ys
plus each of three heights). Both first arms are kept: they pin the wrapper
spelling's answer, which is the one a caller writes. `LR-CC` item 2.

### 6.6 The `CN-R` harness, committed and certified (`LR-CB`)

`docs/probes/demo-pixels/` — `compare.sh` (the driver), `ZZDemoPixels.swift`
(copied into a `git archive` of each commit at `Tests/MetalUITests/`) and
`rawdiff.swift`. Retires §9's deferral and `LR-BJ`'s carry, after the same
generator had been lost and rebuilt four times (record §18, §25 §7.6, §8.8,
§9.8, §14.4).

**Certified by running the controls, not by quoting them.** On a `git archive`
of `f2e981f` the rebuild reproduces all eight recorded figures exactly:

| control | recorded | this rebuild |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |

and record §25 §7.6's caveat re-measures as it stands: scanning all twelve scene
dumps for a 3pt cross-axis rect finds **zero**, so no scroll indicator is painted
anywhere in the set.

**`f2e981f` → `eb42883`: 0 differing pixels in all twelve, every scene dump
byte-identical.** Expected by construction — the lane's only legacy change is an
element that emits nothing becoming a node — and taken anyway.

The script prints the controls, with each one's expected value in brackets and
which two are expected to be 0, **before** any commit-to-commit row, so a
harness that had gone blank cannot read 0 everywhere and look like a pass.

### 6.7 Lane 2's oracle: the windowed `List`'s legacy-side literals

Through the two-frame harness, so these are literals lane 2's test 2.1 can be
written against rather than a transcription of its own first green run
(`LR-BY`). `Box(100 × 100, column) { Box{ ScrollView(.vertical, "scroller")
{ List(20 rows, rowHeight 10) { Box() }.width(100) } }.flexGrow(1).flexBasis(0).minHeight(0) }`
inside `DifferentialRoot(100 × 100)`, legacy authority, `frames: 2`:

| id path | unwindowed | windowed, stored `offset: 50` |
|---|---|---|
| `0` (outer `Box`) | (0,0) 100×100 | (0,0) 100×100 |
| `0/0` (grow `Box`) | (0,0) 100×100 | (0,0) 100×100 |
| `0/0/0` (`ScrollView` viewport) | (0,0) 100×100 | (0,0) 100×100 |
| `…/'scroller'` (the `List`) | (0,0) 100×200 | (0,0) 100×200 |
| `…/'scroller'/'item-i'` | (0, 10·i) 100×10 | (0, 10·i) 100×10 |
| `…/'item-i'/0` (the row's content) | (0, 10·i) 0×10 | (0, 10·i) 0×10 |
| realized rows | **0…11** (12) | **3…16** (14) |
| `StateTable` ids | 47 | 47 |

**The spacer appears in neither column**, which is the demotion seen from the
harness: it records no `Frame.elementBounds` row at all.

**The harness root's shape is load-bearing and had to be found by measurement.**
`DifferentialRoot`'s legacy arm is a `display: .stack` that offers its children
fit-content, so a bare `ScrollView { List }` takes its content's full 1120pt as
its viewport and windows nothing — measured, all 40 rows. So does a fixed-height
`Box` around the scroller, and so does a fixed-height `Box` with
`minSize.height: 0` inside it. Only the demo's own spelling
(`.flexGrow(1).flexBasis(0).minHeight(0)` inside a container with a declared
height) bounds the viewport. `aListInTheDifferentialHarnessReachesABoundedWindow`
carries that shape and the reasoning.

### 6.8 Screen lock

`xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate &&
/tmp/lockstate` at the end of the lane: **`session CGSSessionScreenIsLocked =
1`**, `CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0`. Locked, the same lock as at every lane of stage 3, so
**no real-window capture was taken**. `IOConsoleLocked` was not read (`FR-V`).
The twelve offscreen images stand in.

### 6.9 Deferred out of lane 1

| item | why | owner |
|---|---|---|
| CLAUDE.md's divergence-18 row (`2n + 7`, "crossing at **125 rows**", "1007 at 500") | the lane may not edit CLAUDE.md; the measured replacement is §6.3 | the Docs phase, then `cp CLAUDE.md AGENTS.md` and `cmp` |
| a real-window capture | the screen was locked | whoever runs a lane with an unlocked screen |
| the census's real re-derivation | lane 1 pays only the one-id edit the spacer forces | lane 5 (§4.2(c)) |
| **other fixtures blinded by `.padding` becoming a wrapper at `f1944f8`** | §6.5 found two in `ListTests` by mutation; nobody has swept for more, and the decay is silent by construction | unowned — worth a sweep by whoever next mutates a padded fixture |

---

## 7. Lane 2 — `WindowedRowsLayout`, the lowering, and the site check's deletion (`LR-BQ`, `LR-BR`; corrections in `LR-CD`)

Three commits on `feat/engine-stage-4`:

| commit | what |
|---|---|
| `a494777` | the red-before: four assertion failures, 21 issues, on the unfiltered suite |
| `13c12f0` | `WindowedRowsLayout`, `ListRows`' proposal branch, `List`'s site check deleted, two pins retired, five more tests arriving with their subject |
| `c124f40` | the mutations' three corrections, written into the pins they falsified |

### 7.1 The red-before

Unfiltered, `swift test --build-system native --no-parallel` at `a494777`
(lane 1's sources, only tests changed): **1587 tests in 2 suites failed with 21
issues**.

```
aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape   16 issues
  :247 r.unlowerable.isEmpty                 (the report is [list.noLowering])
  :247 r.legacyOnly.isEmpty && r.loweredOnly.isEmpty
  :247 r.stateSlotsEqual
  :252 b1.loweredBounds[row] == …            x6, one per row
  :254 b1.loweredBounds[row content] == …    x6
  :262 !rows.isEmpty                         (B2's bounded-window require)
aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight         1 issue
  :335 frame.unlowerableFields.isEmpty
theListSiteReportsNothingAndItsRowsItemFieldsAreLowered      3 issues
  :378 frame.unlowerableFields.isEmpty
  :379 no entry may name the list site
  :382 the lowered side must build its rows
aLoweredListsRowIdentitiesAreTheLegacyOnes                   1 issue
  :411 lowered.unlowerableFields.isEmpty
```

**Only four of the nine tests are here, and that is the classification spec §6
lane 2 prescribes** (`LR-BX`, critic round 1's D12): the other five read
`WindowedRowsLayout`'s own answer, so they cannot compile at lane 1's HEAD, and
a test that does not compile is not a red-before and cannot be mutated. They
arrive in `13c12f0` and their evidence is §7.4's mutations.

B2's `try #require` fires before B3, B4, B5 and B6 run. That is what a
red-before looks like when the first windowed arm cannot window at all.

### 7.2 What landed

`Sources/MetalUI/ListRows.swift` gains `WindowedRowsLayout` and
`ListRows.loweredNode`, its proposal arm: consume each realized row's
`LoweredItem`, plan and register its item wrappers with
`planLegacyItems`/`registerLegacyItems` at `parentSite: .list`, register one
`WindowedRowsLayout` over the wrapped rows, record **that** node as the group's
own item, and return it alone. `GroupLayout.spacer` becomes optional — there is
no spacer on that path.

`Sources/MetalUI/List.swift`: the `noteUnlowerable(.list, "noLowering")` check
and the `lowersToProposal ? 0..<0 : …` window are gone, and `requestLayout` is
authority-blind again. `ListRows` is constructed with `rowHeight`,
`logicalCount`, `firstIndex` and the `List`'s declared `listStyle`.

`Sources/MetalUI/LayoutAuthority.swift`: `owningStage`'s `.list` comment says
the site-level entry is gone and what the case survives for.

Two pins retired (§4.2(d)): `aListAndAComponentAmendTrap…` becomes
`aComponentAmendDoesNotTrapUnderTheProposalAuthority`, and
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`'s `List` arm becomes an
**absence** arm with `arms.count` still 10.

Built after `swift package clean` — `List` is public, crosses a module boundary,
and its stored `box`'s generic argument gained four fields.

### 7.3 Every number

| measure | before (lane 1's HEAD, `d811944`) | after (`c124f40`) |
|---|---|---|
| suite | 1583 | **1592** (+9, all lane 2's) |
| issues | 0 | **3**, all `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`'s — §7.6 |
| goldens | 97 | 97; `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty |
| typecheck guards | 77 | 77 (no guard added; stage 4 introduces no hazard a plain import can reach) |
| twelve `CN-R` images | 0 differing | **0 differing, every scene dump identical** — §7.5 |

### 7.4 The eight mutations

Taken on `13c12f0`, each restored from a `cp` copy with `git status --short`
clean afterwards, each on the **full unfiltered** suite. The prediction is kept
beside the reading.

| # | what | predicted | measured |
|---|---|---|---|
| **M2a** | `firstIndex` ignored in `placeSubviews` | 2.1, 2.5 | **2.1** (B3's rows, B4's window) and **2.5** — 30 issues |
| **M2b** | the height answer made greedy, i.e. K6's | 2.1, 2.2 | **2.2, 2.3, 2.4b** — and **not 2.1** |
| **M2c** | the width answer 0 on a nil axis, i.e. K6's | 2.4 **only** | **2.4, 2.2, 2.4b** |
| **M2d** | `planLegacyItems` skipped, rows registered raw | 2.1's width columns | **2.1 (all six arms), 2.5, 2.6** — 48 issues |
| **M2e** | the windowed node's `recordLoweredItem` dropped | 2.7, with an `…unconsumed` entry | **nothing** |
| **M2f** | the rows' records not consumed | 2.7 | **2.7, 2.1, 2.5, 2.6, 2.8, 2.4b** and `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` — 46 issues |
| **M2g** | `rowStyle.flexShrink` dropped from the record handed `planLegacyItems` | nothing | **not a mutation at all** |
| **M2h** | the planning parent's cross size left at the `List`'s own | *(not in the design)* | **2.1's B6 alone** |

**M2b's finding.** `List.init` declares
`style.size.height = rowHeight × data.count`, which `paddedAndSized` turns into
a fixed native frame **around** the arrangement, so `sizeThatFits`'s height
answer never reaches a rect through a real `List`. The layout's height is
observable only through the kernel. Recorded because it is the measured reason
2.2 is not redundant with 2.1, and because it says the invariant lives in two
places that must agree with no test that they do (`LR-CD` item 2).

**M2e's finding, and it is a proof rather than a gap.** A **dropped** record
never joins `LoweringState.order`, which `reportUnconsumedLoweredItems`
iterates, so it cannot raise an `…unconsumed` entry at all — an **unconsumed**
one can, which is M2f. And the record's only other effect is the stretch item
frame the enclosing `Box` would wrap the arrangement in, which is redundant
against a layout that already answers `proposal.width`. The record is kept for
`LR-AB`'s uniform convention and for the reachability
`UnlowerableField.owningStage`'s `.list` comment claims, and is documented as
inert-today in two places (`LR-CD` item 3).

**M2g is not a mutation.** The `[LegacyItemPlan]` the group hands
`registerLegacyItems` is byte-identical with and without `rowStyle.flexShrink`
on the record, printed for all six rows of a plain list through a scratch
instrument:

```
M2G-PLAN 0 fixedSizeH=nil W=Optional((min: Optional(0.0), max: Optional(inf))) H=nil
           align=topLeading alignFrame=nil margin=nil fields=[]
… identical for rows 1–5, and identical again under the mutation
```

`plan.fixedSizeHorizontal` is assigned only under
`d.flexShrink == 0 && mainAuto`, and a row declares `size.height = rowHeight` in
a column parent. **M2g′** — the line deleted from `List.requestLayout` outright
— reddens `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` (its `Style.padding`
arm, 4 issues) and `aScrolledListsSpacerDoesNotShrinkUnderPadding` (1 issue),
**both legacy arms, nothing on the proposal path**. That pair is the measurement
`LR-BS`'s "inert rather than removed" needed.

**M2h and the sixth arm.** The design's test 2.1 had five arms and none of them
could see `planLegacyItems`' single-child stretch elision, because every one had
three or more rows — and so did prototypes P1a6 and P2. A one-row `List`
declaring no width leaves its row **0 wide** against the legacy engine's stretch,
because the elision's premise (a fit-content parent) is false for a layout that
answers its proposal. Arm **B6** is the pin, the correction is in
`ListRows.loweredNode`, and M2h reddens B6 and nothing else (`LR-CD` item 1).

### 7.5 The twelve `CN-R` images

`docs/probes/demo-pixels/compare.sh <scratch> f2e981f c124f40`. All eight
controls reproduce their recorded values exactly before any commit-to-commit
row:

| control | recorded | this run |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |
| indicator rects in all twelve | 0 | **0** |

**`f2e981f` → `c124f40`: 0 differing pixels in all twelve, every scene dump
byte-identical.** Expected by construction — lane 2's only change on the legacy
path is `List.requestLayout` losing a branch that fired only under the proposal
authority — and taken anyway.

One later commit in this lane touches `docs/` and one test-file doc comment
(`LoweringScrollTests`' stale "a `List` under the proposal authority … traps"),
neither of which can move a rendered pixel.

**Screen lock**: `xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o
/tmp/lockstate && /tmp/lockstate` reads `session CGSSessionScreenIsLocked = 1`,
`CGSSessionScreenLockedTime = 1790087900`, `displayAsleep main: 1`,
`displayActive main: 0` — the same lock as at every lane of stage 3 and at lane
1 — so **no real-window capture was taken**. `IOConsoleLocked` was not read
(`FR-V`).

### 7.6 The one test left red, deliberately, and what it reads

`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (2.15) goes red the
moment the site check goes, and spec §6 lane 5 leaves it red across lanes 3 and
4 rather than patching it early, so the census is re-derived **once**, from a
finished stage. What it reads at `c124f40`, for whoever picks lane 5 up:

| | before (lane 1) | now |
|---|---|---|
| `report.unlowerable`, modal off | `[list.noLowering]` | **`[]`** — §4.2(c)'s prediction, confirmed |
| ids | 2035 | **2035**, unmoved (the `try #require` still passes) |
| agreeing | 6 | **6** |
| legacyOnly | 2000 | **0** — the demo's 500 rows and their contents are built on both sides now |
| loweredOnly | 0 | **0** |
| disagreeing | 29 | **2029** |

So the 2 000 rows moved from *legacy-only* to *disagreeing* rather than to
*agreeing*, which is what §4.2(c) said to expect from causes **55** and **R**
reaching a subtree that had no lowered counterpart before. Lane 5 owns
attributing every one of them; a disagreement not attributable to an existing
named cause is a finding.

### 7.7 Deferred out of lane 2

| item | why | owner |
|---|---|---|
| the demo census's re-derivation | §7.6; re-derived once from a finished stage | lane 5 (spec §4.2(c)) |
| `ListTests`' 224 nodes and 3 leaves re-spelled, and its scenarios parameterised | the lane touches no `ListTests` fixture | lane 3 (`LR-BW`) |
| retention, focus and the `AXTable` records under **both** authorities | lane 2 pins the records' *equality* through `accessibilityEqual`; the suites that pin the rules are lane 4's | lane 4 (`LR-BU`) |
| the nil-width path's `O(logicalCount)` cost | measured here (2.4b); mitigating it would change `visibleRange`, which `LR-BT` pins shut | stage 6b (spec §9) |
| a real-window capture | the screen was locked | whoever runs a lane with an unlocked screen |
| CLAUDE.md's divergence-18 row, and any CLAUDE.md rule about `List` and the proposal authority | the lane may not edit CLAUDE.md | the Docs phase |

---

## 8. Lane 3 — `ListTests` under both authorities, and the roll call renamed (`LR-BW`, `LR-BY`, `LR-CB`; corrections in `LR-CE`)

Three commits on `feat/engine-stage-4`:

| commit | what |
|---|---|
| `c4ce2f0` | the red-before: a child-process probe recording the trap, with `LegacySpelledRow` kept as its standing subject |
| `7c031b1` | the re-spelling, the host box, the twenty parameterised scenarios, and the registry's rename — one commit, because the first two cannot be separated |
| `352f838` | M3c's finding: a bounds pin that could not see its subject |

### 8.1 The red-before

The lane's red cannot be an assertion failure. Running `ListTests` under
`.proposal` with `Row` spelled as it was does not fail — it **aborts**, at
`Frame.requestNode`'s backstop, ending the run with no summary line and no list
of what failed. So the red is taken in a child process, in
`LayoutAuthorityTests`' shape (`LR-BX` shape (b)), over P1a6's host with the
legacy-spelled row, in both its spellings. Both children exit non-zero. The two
messages, captured by pointing the assertion at a string that cannot match and
then reverting (`git status --short` clean afterwards):

```
MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode has no
proposal lowering (plan task 7, stage 6a); a tree containing it cannot run under
the proposal layout authority.

MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestLeaf has no
proposal lowering (plan task 7, stage 6a); a tree containing it cannot run under
the proposal layout authority.
```

`LegacySpelledRow` and the probe **stay** after the re-spelling, rather than
being deleted with the spelling they describe. They are the standing evidence
for why `Row` goes through the lowering, and the thing that goes quiet if a
future edit puts `pass.requestNode` back — which is worth more than a commit
that removes its own red.

### 8.2 What landed

**`Row` re-spelled**, both registrations, branching on `pass.lowersToProposal`:
the childless arm through `lowerLegacyNode(…, children: [], site: .customElement)`
(which forwards to `lowerLegacyLeaf` over a 0×0 native leaf by itself), the
`contentHeight` arm through `lowerLegacyLeaf` over a `requestNativeLeaf`. Not
`ProbeLeaf`'s spelling, for the reason §2.5 measured.

**Three helpers, not two.** `laidOut` and `renderWindowed` gain the host box,
`recordsElementBounds: true` and — `laidOut` only — a prepaint pass.
`renderedInHost` is new: four tests called `Frame(…).render(&list)` directly and
needed the same host and the same authority as the rest.

**Twenty of twenty-two scenarios parameterised.** The two that are not each say
so at their own declaration and in `AuthorityCoverage.expected`'s doc:
`aListInsideADeferredIgnoresTheEscapedScrollersOffset` (a `Deferred` presentation
root is stage 5) and the child-process probe above.

**The registry renamed in the same commit**: `ScrollAuthorityCoverage` →
`AuthorityCoverage`, `everyScrollScenarioRanUnderBothLayoutAuthorities` →
`everyParameterisedScenarioRanUnderBothLayoutAuthorities`, the literal 34 → 54,
and the header's path-order argument extended (§8.5).

### 8.3 Every number

| measure | before (lane 2's HEAD, `688b834`) | after (`352f838`) |
|---|---|---|
| suite | 1592 | **1593** (+1, the child-process probe; the twenty parameterisations move the total by nothing, which is why the roll call exists) |
| issues | 3 | **3**, the same three — `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`'s, left red by lane 2 for lane 5 (§7.6) |
| goldens | 97 | 97; `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty |
| typecheck guards | 77 | 77 — no guard added, and none is owed: `Row` and the three helpers are `private` to one test file and `List`'s public surface did not move |
| twelve `CN-R` images | 0 differing | **0 differing, every scene dump identical** — §8.6 |
| real-window capture | never taken in this stage | **0 differing, default and preview** — §8.7, the first in the stage |

**Literals that moved: exactly one.**
`aWindowedListStillReportsItsFullContentHeight` renders at `frameHeight: 1200`
instead of 600. The host box declares the frame's own height, so a 1120pt list
inside a 600pt host is a flex item with 520pt of negative free space — which the
legacy engine absorbs by shrinking the `List`'s box to 600 and the kernel does
not, because `paddedAndSized` makes the declared height a fixed native frame.
That is a disagreement the harness would have introduced, and 1200 is the
smallest round number above 1120 (`LR-CE` item 1). Every other literal in the
file — every `y`-offset set, every row height, every scene rect and hitbox
string in `aListsSceneAndHitboxesAreUnchangedByTheGroup` — reads identically on
both authorities, unchanged from `688b834`.

**Adding a prepaint pass to `laidOut` moved nothing, and the whole change moved
one test.** The design named the prepaint pass as a behaviour change for every
test using the helper — hitboxes, scroll regions, focus entries and
accessibility records all register in prepaint — so the full unfiltered suite
was run after it. Nothing outside `ListTests` moved at all. Inside it, exactly
one test moved, and for the host box rather than for prepaint:
`theListsSpacerIsANodeNotAnElement` addressed the `List` as
`GlobalElementID.child(of: nil, at: 0, name: nil)`, which is now the **host**,
and reads `subjectID(named: nil)` instead. The three `laidOut` callers do now
collect the scroll regions their rows register, and none of them asserts on that
count except `anEmptyListHasZeroHeightAndTrapsNothing`, whose list has no rows —
so the pass is paid for and observed by nothing, which is the honest statement of
its cost.

**The row registration census, re-counted rather than carried over.** §4.2 read
224 nodes and 3 leaves at `f2e981f`. Measured at this HEAD with a temporary
counter on `Row`'s four branches, one unfiltered run, then reverted:

| | legacy | proposal |
|---|---|---|
| nodes | **289** | **241** |
| leaves | **3** | **3** |

Both deltas are attributable, and both confirm a number rather than replacing
one. `289 − 241 = 48` is exactly
`aListInsideADeferredIgnoresTheEscapedScrollersOffset`, the one legacy-only
scenario (40 escaped rows plus its 8-row windowed control). `289 − 224 = 65` is
lane 1's four additions: `theListsSpacerIsANodeNotAnElement` (6),
`aListInTheDifferentialHarnessReachesABoundedWindow` (40 on its unbounded first
frame, 10 on its windowed second), and the `Style.padding` arm added to each of
`paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` (3) and
`aScrolledListsSpacerDoesNotShrinkUnderPadding` (6). So §4.2's 224 is confirmed
at `f2e981f` by arithmetic that closes exactly.

### 8.4 The three mutations

Taken on `7c031b1` (M3a, M3b, M3c) and again on `352f838` (M3c), each restored
from a `cp` copy with `git status --short` clean afterwards, each on the **full
unfiltered** suite. The prediction is kept beside the reading.

| # | what | predicted | **measured** |
|---|---|---|---|
| **M3a** | `AuthorityCoverage.authorities` reduced to `[.legacy]` | the roll call | **2 tests, 54 issues** — `aScrollViewWithNoCornerRadiusClipsSquare` 53 (the arm whose `record` completes the set, one issue per other scenario seen under one authority), `everyParameterisedScenarioRanUnderBothLayoutAuthorities` 1 (its `authorities == allCases` require). Run total 57 issues, the 3 standing ones included |
| **M3b** | `Row`'s proposal leaf branch made a bare `requestNativeLeaf` | `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` under `.proposal` | **exactly that**, `.proposal` arm only, **3 issues** — `region.bounds.size.height == px(28)`, one per row. Nothing else moved, on either authority |
| **M3c** | `recordsElementBounds` dropped back to its default in `laidOut` | the **three** tests that read the `List`'s bounds | **two**: `aListSizesItselfToCountTimesRowHeight` and `aWidthModifierOnAListReachesItsLayoutNode`, one issue per arm. §8.4.1 |

M3a's shape reproduces stage 3's reading exactly, scaled: stage 3 measured 2
tests and 34 issues over 34 names, and 54 names give 53 + 1. That the completer
is still `aScrollViewWithNoCornerRadiusClipsSquare` — the last scenario in the
last file — is the order argument's second half confirming itself.

M3b is the measured reason `ProbeLeaf` is not the re-spelling. A directly
registered native leaf records no `LoweredItem`, so `planLegacyItems` cannot
plan it, the row `Box` never stretches or floors it, and all three rows read a
height other than `rowHeight`. It is also the only mutation in this lane that
distinguishes the two authorities: the legacy arm is untouched and stays green.

#### 8.4.1 M3c's finding: a pin that could not see its subject

`anEmptyListHasZeroHeightAndTrapsNothing` stayed green under M3c, and the
reason is the helper rather than the test. `laidOut` returned
`frame.elementBounds[subject] ?? <0×0>`, so "no record" and "zero" were the same
value — and that test's assertion is that the height **is** zero, which is the
mutation's own answer. Practices shape 14 arrived at through a convenience: the
`??` was written to keep the call sites tidy and it made one of them
unfalsifiable.

Fixed in `352f838`: both helpers return `Bounds<Pixels>?` and all four readers
`try #require` it. **M3c re-run against that commit reddens all three, six
issues** — one per arm. The `??` spelling is not to be reintroduced; any fixture
whose expected answer is zero on some axis is blind behind it, and this file has
one such fixture today.

### 8.5 The order argument, re-measured twice

The roll call's second half depends on Swift Testing running files in path
order. Re-measured at this HEAD by reading the order tests start in, twice,
identical both times (the index is the position among distinct test names in one
unfiltered run):

| | run 1 | run 2 |
|---|---|---|
| `ListTests` first scenario (`aListSizesItselfToCountTimesRowHeight`) | 1149 | 1149 |
| `ListTests` last scenario (`aListsSceneAndHitboxesAreUnchangedByTheGroup`) | 1169 | 1169 |
| `ScrollIndicatorTests` first (`theIndicatorIsTheLastPrimitiveInTheScene`) | 1419 | 1419 |
| `ScrollRoutingTests` first (`aWheelEventInsideARegionScrollsIt`) | 1433 | 1433 |
| `ScrollViewTests` first (`theContentNodeOverflowsTheViewport`) | 1449 | 1449 |
| `everyParameterisedScenarioRanUnderBothLayoutAuthorities` | **1456** | **1456** |

So `ListTests` → `ScrollIndicatorTests` → `ScrollRoutingTests` →
`ScrollViewTests`, roll call last. The argument now **states the sort it rests
on** — `Tests/MetalUITests/ListTests.swift` sorts before every
`Tests/MetalUITests/Scroll*.swift` — which the stage-3 version did not, and names
the case that would break it: a file added later whose path sorts after
`ScrollViewTests.swift`. That is exactly why `ZZDemoPixels.swift` carries its
`ZZ…` prefix, and the two comments now cross-reference.

`ListLoweringTests.swift` is **not** in the argument, against `LR-CB`'s wording,
because it contributes no name: its nine tests each run both authorities inside
one body through `LayoutDifferential.compare`, so none is a `@Test(arguments:)`
case and none calls `record` (`LR-CE` item 4).

### 8.6 The twelve `CN-R` images

`docs/probes/demo-pixels/compare.sh /tmp/pix-lane3 f2e981f 352f838`. All eight
controls reproduce their recorded values exactly before any commit-to-commit
row:

| control | recorded | this run |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |
| indicator rects in all twelve | 0 | **0** |

**`f2e981f` → `352f838`: 0 differing pixels in all twelve, every scene dump
identical.** Expected by construction — lane 3 changes nothing under `Sources/`
at all — and taken anyway, because "expected by construction" is what the
harness exists to stop a lane from asserting. One later commit in this lane
(`4ae0e27`) touches only `docs/`, which cannot move a rendered pixel.

### 8.7 The first real-window capture of the stage

`docs/probes/appkit-screen-lock-state.swift` at this lane prints **no**
`CGSSessionScreenIsLocked` and no `CGSSessionScreenLockedTime` line,
`kCGSSessionOnConsoleKey = 1`, `displayAsleep main: 0`, `displayActive main: 1`,
`preflightScreenCaptureAccess: true`, one screen `(0,0,2056,1329) scale=2.0`.
Unlocked, for the first time in this stage — lanes 1 and 2 and every lane of
stage 3 read a locked screen. `IOConsoleLocked` was not read (`FR-V`).

So `docs/probes/window-capture/capture.sh /tmp/win-lane3 f2e981f 352f838`, real
release windows captured by id with no shadow, no input sent and the pointer not
moved:

| row | result |
|---|---|
| `f2e981f` default, a vs b (1.5 s apart) | 1840×1176 differing=0 |
| `f2e981f` preview, a vs b | 1840×1176 differing=0 |
| `352f838` default, a vs b | 1840×1176 differing=0 |
| `352f838` preview, a vs b | 1840×1176 differing=0 |
| **`f2e981f` → `352f838` default** | **1840×1176 differing=0** |
| **`f2e981f` → `352f838` preview** | **1840×1176 differing=0** |
| control, default vs preview at `352f838` | 1840×1176 differing=**921 071**, bbox (0,15)–(1839,1175) |

The four stability pairs read 0 and the control reads non-zero, so the zeros in
the middle are a measurement rather than a broken instrument. This retires lanes
1 and 2's "a real-window capture — the screen was locked" deferral **for the
branch as it stands at `352f838`**; it does not retire it for lanes 4 and 5,
which change different files.

### 8.8 Deferred out of lane 3

| item | why | owner |
|---|---|---|
| retention, focus and the `AXTable` records under both authorities | lane 3 parameterises `ListTests`; the suites that pin `TB-AH`, `AB-L` and `AB-X` are lane 4's | lane 4 (`LR-BU`) |
| `aListInsideADeferredIgnoresTheEscapedScrollersOffset` under `.proposal` | `Deferred` as a presentation root has no lowering | stage 5 |
| the demo census's re-derivation, and the three issues still standing | §7.6 | lane 5 |
| **other fixtures blinded by `.padding` becoming a wrapper at `f1944f8`** | carried from §6.9; lane 3 swept nothing new for it | unowned |
| CLAUDE.md's `List`/`ScrollAuthorityCoverage` mentions, and the 1580 → 1593 count | the lane may not edit CLAUDE.md | the Docs phase |

---

## 9. Lane 4 — retention, focus and accessibility under both authorities (`LR-BU`; corrections in `LR-CF`)

Three commits on `feat/engine-stage-4`:

| commit | what |
|---|---|
| `a0cdc0a` | the red-before: four child-process probes and one positive control, each keeping the pre-lane spelling as a live fixture |
| `779a6a4` | the re-spellings, the eleven parameterised scenarios, the fixture's one dropped modifier, and the roll call's move — one commit, because a re-spelling and its `.proposal` arm cannot be separated (`LR-BX`) |
| `684ef95` | M4b's finding: a conjunct nothing can pin, written into the source |

### 9.1 The red-before

Lane 4's red cannot be four assertion failures. Three of its fixtures do not
fail under `.proposal` — they **abort**, ending the run with no summary line —
so the red is taken in child processes, in
`ListTests.aLegacySpelledListRowAbortsAProductionProposalFrame`'s shape. Each
was measured **before** anything was touched, with a throwaway probe file that
reported every arm's exit status and stderr, then committed as a permanent probe
with the pre-lane spelling kept beside it. The four messages, each confirmed by
pointing its assertion at a string that cannot match and then reverting (`git
status --short` clean afterwards; all four read red, then green):

```
MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode has no
proposal lowering (plan task 7, stage 6a); …        [TombstoneTests.ExcursionRow]

MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode has no
proposal lowering (plan task 7, stage 6a); …            [AXNodeTests.AXListLeaf]

MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.minSize.unconsumed has no
proposal lowering (plan task 7, stage 2); …   [scrolledList's root .minHeight(0)]

MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.display.none has no proposal
lowering (plan task 7, stage 2); …    [aListInsideHiddenContent…'s hidden() box]
```

Two of the five probe arms are **positive controls**, and both were load-bearing:

- `aBoxSpelledListRowDoesNotAbortAProductionProposalFrame` — the same
  `ScrollView { List { … } }` with `Box().focusable()` rows exits **0**. This is
  the measurement that refuted the design's premise about `FocusTests`
  (`LR-CF` item 1), and without it the `ExcursionRow` abort beside it would pass
  just as well if the `List`, the `ScrollView` or `@State` were what aborted.
- the minSize probe's second half and the hidden probe's second half — the same
  trees with the one modifier dropped, and shown, both exit **0**.

### 9.2 The scratch measurement the whole lane turned on

Before writing anything, nine fixture shapes were run under `.proposal` in child
processes from a throwaway `Tests/MetalUITests/ZZScratchLane4.swift` (deleted; it
never reached a commit). The table is the lane's plan:

| shape | result |
|---|---|
| `ScrollView { List { ExcursionRow } }` | SIGTRAP, `customElement.requestNode` |
| `ScrollView { List { Box().focusable() } }` | **exit 0** — the design's premise refuted |
| `List { AXListLeaf }` as root | SIGTRAP, `customElement.requestNode` |
| `scrolledList(50, 200)` as a frame root | SIGTRAP, `box.minSize.unconsumed` |
| `scrolledList(5000, 200)` in a fake `Window` | SIGTRAP, `box.minSize.unconsumed` |
| the same without `.minHeight(px(0))` | **exit 0** — so the modifier is the whole blocker |
| `Row { Column, Column, scrolledList }` (`aClientDoesNotChangeStateRetention`) | **exit 0** — a consumed record, not a root |
| `Column { box.hidden(), Text }` | SIGTRAP, `box.display.none` |
| `Box { List }.width(200).height(200)` (the no-context arm) | **exit 0** |

`.minHeight(px(0))` was then measured **inert under the legacy engine** rather
than argued: dropped from `scrolledList` with nothing else changed, the whole
suite unfiltered read **1593 tests in 2 suites, 3 issues** — the three lane 2
left red for lane 5 (§7.6). That is the number quoted in `LR-CF` item 2 and in
the fixture's own doc comment.

### 9.3 What landed

**Two fixtures re-spelled, not three.** `TombstoneTests.ExcursionRow` and
`AXNodeTests.AXListLeaf` branch on `pass.lowersToProposal` into
`lowerLegacyNode(…, children: [], site: .customElement)` — `ListTests.Row`'s
childless arm (§8.2), which forwards to `lowerLegacyLeaf` over a 0×0 native leaf
by itself. `ExcursionRow`'s `count += 1` stays **outside** the branch: a
production count that depended on the authority would make the two excursion
arms incomparable rather than comparable. `FocusTests`' row is untouched
(`LR-CF` item 1).

**Eleven scenarios parameterised over `AuthorityCoverage.authorities`:**

| file | scenarios |
|---|---|
| `TombstoneTests` | `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (`TB-AH`, both halves) |
| `FocusTests` | `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` (the same bound, one generation later) |
| `AXNodeTests` | `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, `aVirtualizedListsLogicalCountIsTheFullDataCountEvenWhenEveryRowFits`, `aCallerDeclaredAXNodeOnAListSurvivesLogicalCountBeingAdded` |
| `AccessibilityDefaultsTests` | `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `aClientDoesNotChangeStateRetention` |
| `AccessibilityTreeTests` | `aLabelledListIsStillATable` (completeness only) |

**Not one literal moved.** Every offset, window, count, index, emission bound
and notification count in all eleven reads the same on both authorities; the
only edit inside a body is the authority threaded into the frame or window it
builds. That is the lane's finding about stage 4 stated positively: the windowed
`ProposalLayout` changed what a row's rect comes through and changed nothing
about which rows are built, which ids they take, what they publish or when they
are reaped.

**Three helpers take an authority**: `AXNodeTests.bareFrame` and
`renderListWindowed`, `AccessibilityDefaultsTests.collect` and
`AccessibilityTreeTests.collect`, each defaulting `.legacy`. Every other caller
of all four builds no element tree, so a second authority there would be an
argument the body never reads (`LR-BN`'s rule).

**Three window-level arms build PRODUCTION frames.** `makeFakeWindow` never sets
`reportsUnlowerableFields`, so `activatingBefore…`, `scrollingAList…` and
`aClientDoesNotChangeStateRetention` trap on anything unlowered rather than
reporting it — which is why §9.2's table was taken first rather than after.

**`scrolledList` loses `.minHeight(px(0))`** (§9.2, `LR-CF` item 2), and
**`aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` stays
legacy-only** with its declaration saying why (`LR-CF` item 3).

**The roll call moved to `Tests/MetalUITests/ZZAuthorityRollCall.swift`**
(`LR-CF` item 4). `AuthorityCoverage.expected` 54 → **65**; the literal inside
the test moved with it, and its `#require` message now names all nine
contributing suites.

### 9.4 Every number

| measure | before (lane 3's HEAD, `16d6696`) | after (`684ef95`) |
|---|---|---|
| suite | 1593 | **1598** (+5: four abort probes and one positive control; the eleven parameterisations move the total by nothing, which is why the roll call exists) |
| issues | 3 | **3**, the same three — `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`'s, left red by lane 2 for lane 5 (§7.6) |
| goldens | 97 | 97; `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty |
| typecheck guards | 77 | 77 — lane 4 adds no hazard a plain import can reach |
| `error:` / `warning:` | 0 / only SwiftPM's deprecation notice | unchanged |
| `AuthorityCoverage.expected` | 54 | **65** |
| parameterised suites | 4 | **9** |

`find Tests -name "*.json" | wc -l` reads 115 with `Tests/PortableTests/.build`
present; the golden count is taken under `Tests/MetalUILayoutTests` only, as §1
says.

### 9.5 The five mutations

Each was run on the **full unfiltered suite** from a `cp` copy of the file, with
`git status --short` empty after the restore. The three standing issues of
§7.6 are excluded from every count below.

| id | mutation | arms reddened | issues | tests named |
|---|---|---|---|---|
| **M4a** | `StateTable.staleAfterGenerations` 2 → 3 | 4 | 4 | `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (.legacy, .proposal) at `TombstoneTests.swift:387`, `peek(longSlot) == 1`; `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne` (.legacy, .proposal) at `FocusTests.swift:1067`, `longResult == nil` |
| **M4b** | `indexesRows` forced to `pass.collectsAccessibility` | **0** | **0** | none — §9.6 |
| **M4b′** | `windowIsBounded` forced `true` | 6 | 22 | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` (8 per authority), `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` (2 per authority), `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (1 per authority) |
| **M4c** | `windowAwaitsViewport`'s `requestAccessibilityRetry()` deleted | 4 | 12 | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` (5 per authority), `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (1 per authority) |
| **M4d** | `AuthorityCoverage.authorities` → `[.legacy]` (M3a's twin, re-run against the moved roll call) | 2 tests | 65 | `everyParameterisedScenarioRanUnderBothLayoutAuthorities` at `ZZAuthorityRollCall.swift:46`; 64 raised by `record`'s own whole-set check inside `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` |

The individual assertions, for the two that the design set a floor for:

- **M4b′**, per authority: `lastEmissionCount <= 3`, `table0.children.isEmpty`,
  `window.needsRedraw`, `framesDrawn == 2`, `table1.children.count == 10`,
  `capped.needsRedraw`, `capped.framesDrawn == 2`,
  `unscrolledTable.node.children.isEmpty` (`activatingBefore…`);
  `zero.children.isEmpty`, `zeroHeight.all(.staticText).isEmpty`
  (`combinationReaches…`); `vended.count == 10` (`scrollingAList…`).
- **M4c**, per authority: `window.needsRedraw`, `framesDrawn == 2`,
  `table1.children.count == 10`, `capped.needsRedraw`, `capped.framesDrawn == 2`
  (`activatingBefore…`, the `AB-X` rule-3 half); `vended.count == 10`
  (`scrollingAList…`).

**Every count is symmetric across authorities**, which is the check `LR-BU`
asks for: a mutation that reddened only legacy arms would mean the proposal arm
is vacuous. None did.

M4d is also the measurement that the roll call's move works: the 64 issues come
from `record`'s order-independent half firing inside `TombstoneTests`' arm,
which is now the last expected name to arrive.

### 9.6 M4b's finding: a conjunct nothing can pin

M4b reddens nothing, and it is the finding rather than a broken instrument —
`LR-CD` item 4's shape again. The mechanism, read off the source after the run
and then re-measured:

`indexesRows` gates exactly one write, `rowBox.handlers.axNode.logicalIndex`, and
on an unbounded window both things that hint could reach are already shut:

1. **the record.** `List.prepaint` wraps the rows in
   `withAccessibilitySuppressed(except: id)` whenever the window is unbounded and
   a client is collecting, and `Frame.registerHandlers`' record branch is guarded
   by exactly that (`collectsAccessibility, !isAccessibilitySuppressed(for: id)`);
2. **the emission.** `Frame.registerHandlers` assigns
   `declaration.logicalIndex = nil` **before** its `declaration.isEmpty` test
   (`AB-L`: "a row hint is not a declaration"), so a row carrying only a hint
   emits no `AXNode` and writes no `$ax` slot (`AB-U`).

So the `windowIsBounded &&` conjunct is belt-and-braces with a guard one method
away. It stays — it states what the value means — and the measurement is now a
comment beside it in `List.requestLayout`, so a later reader does not take it for
a tested guard. `AB-X` rule 1 is pinned through the suppression instead, and
M4b′ is the mutation that measures that.

### 9.7 The order argument, re-measured twice

Lane 3 established that Swift Testing runs a file's tests in source order and
the files in path order, off `ScrollViewTests.swift` being last (§8.5). Lane 4
breaks that: `Tests/MetalUITests/TombstoneTests.swift` sorts **after**
`Tests/MetalUITests/ScrollViewTests.swift`. Rather than leave `TB-AH`'s suite out
of the exit criterion, the roll call moved to `ZZAuthorityRollCall.swift`.

Re-measured twice at this HEAD off the unfiltered runs' own `started` lines,
identical both times (line numbers from the second run):

| file | first scenario's `started` line |
|---|---|
| `AXNodeTests` | 1276 |
| `AccessibilityDefaultsTests` | 1310 |
| `AccessibilityTreeTests` | 1384 |
| `FocusTests` | 1941 |
| `ListTests` | 2428 |
| `ScrollIndicatorTests` / `ScrollRoutingTests` | between |
| `ScrollViewTests` | 3269 |
| `TombstoneTests` | 3395 |
| **`ZZAuthorityRollCall`** | **3407** |

Both arms of a parameterised test run back to back (`… → .legacy` then
`… → .proposal`), as `AuthorityCoverage`'s doc says.

### 9.8 The twelve `CN-R` images

`docs/probes/demo-pixels/compare.sh /tmp/…/pix f2e981f 684ef95`. All nine
controls reproduce their recorded values exactly before any commit-to-commit row:

| control | recorded | this run |
|---|---|---|
| light vs dark, f0 | 1 048 576 | **1 048 576** |
| default vs modal (light) | 1 030 498 | **1 030 498** |
| default vs animation (light) | 210 027 | **210 027** (bbox (16,113)–(981,1007)) |
| f0 vs f3 (light) | 0 | **0** |
| preview light vs dark | 1 048 576 | **1 048 576** |
| `chrome-legacy` vs `chrome-proposal` | 0 | **0** |
| distinct values, `default-light-f0` | 544 | **544** |
| distinct values, `chrome-legacy` | 216 | **216** |
| indicator rects in all twelve | 0 | **0** |

**`f2e981f` → `684ef95`: 0 differing pixels in all twelve, every scene dump
identical.** Expected by construction — the lane's only `Sources/` edit is a
comment — and taken anyway, because "expected by construction" is what the
harness exists to stop a lane from asserting. The demo is never scrolled in
these images, so no scroll indicator is painted in any of them (§7.6's caveat).

### 9.9 Screen lock

`docs/probes/appkit-screen-lock-state.swift` at this lane prints
`session CGSSessionScreenIsLocked = 1`,
`session CGSSessionScreenLockedTime = 1790140509`, `kCGSSessionOnConsoleKey = 1`,
`displayAsleep main: 1`, `displayActive main: 0`,
`preflightScreenCaptureAccess: true`, one screen `(0,0,2056,1329) scale=2.0`.
**Locked**, so no real-window capture was taken — the gate is the printed lock
state, not a judgement. `IOConsoleLocked` was not read (`FR-V`). Lane 3's
unlocked window (§8.7) retired the deferral for the branch as it stood at
`352f838` only; it does not cover this lane, and the offscreen twelve are what
this lane has.

### 9.10 Deferred out of lane 4

| item | why | owner |
|---|---|---|
| a real-window capture at this HEAD | the screen was locked (§9.9); the offscreen twelve read 0 | lane 5, or whichever lane next finds it unlocked |
| `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` under `.proposal` | `display: none` has no lowering (`LR-CF` item 3) | the stage that lowers `display` |
| `aListInsideADeferredIgnoresTheEscapedScrollersOffset` under `.proposal` | carried from §8.8 | stage 5 |
| the demo census's re-derivation, and the three issues still standing | §7.6 | lane 5 |
| `MeasurePerformanceTests.StatefulListRow`'s re-spelling and `render`'s `reportsUnlowerableFields:` parameter | spec §6 lane 5's own first obligation; lane 4 touches no performance fixture | lane 5 |
| **other fixtures blinded by `.padding` becoming a wrapper at `f1944f8`** | carried from §6.9 and §8.8; lane 4 swept nothing new for it | unowned |
| CLAUDE.md's `List` and roll-call mentions, and the 1580 → 1598 count | the lane may not edit CLAUDE.md | the Docs phase |
