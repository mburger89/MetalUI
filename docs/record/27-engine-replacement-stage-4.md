# §27 — Engine replacement, stage 4: the windowed proposal `List`

**Renumbered from §26 to §27 at merge with `master` (2026-09-23):** the
HarfBuzz shaper line (PR #9, `f5e5651`) was pushed first and keeps §26, so
every `§26` this track wrote was repointed to `§27` and the file renamed. The
HarfBuzz line's own `§26` citations were left alone. Counts re-taken on the
merged tree: **1617 / 97 / 77** (`CLAUDE.md` "Build and test"). Figures
below that read 1602 are this branch's own, before the merge.

Plan task 7, stage 4 (parent design
`docs/superpowers/specs/2026-09-17-engine-replacement-design.md` §4.1 row 4).
Design: `docs/superpowers/specs/2026-09-23-engine-stage-4-design.md`. Rulings
`LR-BQ`…`LR-CG` in `docs/superpowers/2026-09-17-engine-replacement-decisions.md`
(`LR-BX`…`LR-CB` are critic round 1's, §5 below; `LR-CC` is lane 1's,
`LR-CD` lane 2's, `LR-CE` lane 3's, `LR-CF` lane 4's and `LR-CG` lane 5's).
Branch `feat/engine-stage-4` from `f2e981f`.

**Status, 2026-09-23 (PDT): DELIVERED — all five lanes landed, all five
verified `ok`, fifteen minors dispositioned.** §6 is lane 1's record, §7 lane
2's, §8 lane 3's, §9 lane 4's, §10 lane 5's and **§11 the verification round**,
after which come the closing sections — what landed, tests and guards per file,
probes, red runs, verifier verdicts, green mutations, demo comparisons, hazards,
deferrals and **For the integrator**. Final figures: **1602 tests, 97 goldens,
77 guards**, 0 `error:` and no `warning:` beyond SwiftPM's deprecation notice.
Every prototype in §2 was applied in
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
  (the design-time name; it landed as
  `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` — branch checker)
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

### 6.10 What the verification round added to this lane

Lane 1's verifier took **five mutations the lane did not** (V5–V9 below, V1–V4
being re-runs of M1a, M1b, M1b′ and M1f that reproduced the lane's readings) and
raised five minors, none of them a defect in a landed behaviour.

| mutation | reddened |
|---|---|
| **V5** — the demotion itself undone: the spacer registered again as a `Box<EmptyGroup>` element through `requestGroupLayout` | `theListsSpacerIsANodeNotAnElement`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` — the demotion's own two pins, alive |
| **V7** — the spacer node appended **last** instead of first, so the returned order is rows + [spacer] | **7**: `aFractionalOffsetRoundsFirstDownAndLastUp`, `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop` |
| **V9** — rows registered with `under: nil` rather than `under: parent`, breaking the id chain through the group | **6**, and they are the retention and accessibility pins lanes 4 and 5 own: `aListRowsStateSurvivesABoundedExcursionButNotALongerOne`, `aFocusedListRowSurvivesABoundedExcursionButNotALongerOne`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` |
| **V6** (= M1c) — the cursor advanced past the spacer | **nothing**, as §6.4 proves by reading |
| **V8** — `ListRows`' `pass.lowersToProposal ? lowerLegacyNode(…) : requestNode(…)` collapsed to `requestNode` unconditionally | **nothing**, and here the equivalence is *proved* rather than assumed — below |

**V8's equivalence, and why it is worth a line.** At lane 1's HEAD the branch
cannot be distinguished by any test the suite reaches:
`List.requestLayout` sets `let window = lowersToProposal ? 0..<0 : visibleRange(…)`,
so on the proposal path `spacerHeight == 0`; and `Frame.requestNode` under the
proposal authority falls through `unguardedLegacyRegistration` to
`requestNativeLeaf { 0x0 }` (`Frame.swift:1564-1590`), which is exactly what
`lowerLegacyNode` with empty children produces through `lowerLegacyLeaf`. The
mutant is **not** equivalent in a proposal frame with
`reportsUnlowerableFields == false` — there it traps — but no test renders a
`List` in that configuration at lane 1's HEAD. Lane 2 replaces the branch with
`WindowedRowsLayout`, so nothing is owed; it is recorded so that lane 2's reader
knows the branch it replaced had never been distinguished.

**Four things about `ListRows` the lane did not write down**, each raised by the
verifier, each true by reading and none of them a behaviour change:

1. **`LayoutDifferential.compare` gained a `frames:` parameter with no caller.**
   The only `frames:` call site in the suite is `ListTests.swift:606`, and it
   calls `render`. `compare(frames:)` is passed straight through to both
   `render` calls and is otherwise unexercised — dead today, and no mutation can
   redden it. Lane 2's `ListLoweringTests` is the first user of `compare`, but
   at its default. Not scaffolding a reader should treat as covered.
2. **`ListRows.GroupLayout.spacer` is stored every frame and never read.** Its
   own doc says it is "carried rather than dropped so that a later phase could
   read its rect; nothing does today"; `grep` finds no read in `Sources/` or
   `Tests/`. A deliberate inert field, recorded here rather than in CLAUDE.md's
   inert table because it is internal. Lane 2 makes it optional — the windowed
   path has no spacer at all.
3. **`ListRows`' two `countMismatch` preconditions are unpinned traps**, where
   `ArrayGroup`'s identical trap has an exit test
   (`changingAnArrayGroupsCountBetweenPhasesTraps`). A copy of a pinned
   implementation is unpinned (practices). They are, by reading, unreachable
   from any public API — `List.requestLayout` overwrites `box` inside itself, so
   the two arrays always come from the same build — but the argument is a
   reading, not a measurement, and `ListRows` is internal to a `@testable`
   target, so the trap *is* constructible from a test exactly as `ArrayGroup`'s
   is. Owner below.
4. **The spacer's style no longer passes through `animated(_:_:for:pass:)`.**
   Before the demotion the spacer was a `Box`, and `Box.requestLayout` is one of
   the nine registering sites, so its height interpolated under a live
   transaction; a bare node does not. The docs disclosed the bookkeeping half of
   the demotion (no `$anim` entry, no `elementBounds` row) and not this
   behavioural half, and no test covers it either way. **Intended**: the
   windowed proposal layout has no spacer, so an animatable spacer is a legacy
   artefact on the way out — and a windowed list's spacer height tracks the
   scroll offset, which is not a thing that should ease.

| item | owner |
|---|---|
| an exit test for `ListRows`' `countMismatch`, mirroring `changingAnArrayGroupsCountBetweenPhasesTraps` — or the reachability argument written into the source | the Docs phase or the branch checker |
| `compare`'s `frames:` given a caller or removed | whoever next edits `LayoutDifferential` |

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
| **M2a** | `firstIndex` ignored in `placeSubviews` | 2.1, 2.5 | **2.1** (B3's rows, B4's window) and **2.5** — **47 issues** beyond the 3-issue baseline. *Corrected in the verification round*: this row read "30 issues", which the mutation as worded does not reproduce; the verifier's re-run of the same spelling on the same restored HEAD reads 50 total / 47 attributable over exactly these two tests (§11.3) |
| **M2b** | the height answer made greedy, i.e. K6's | 2.1, 2.2 | **2.2, 2.3, 2.4b** — and **not 2.1** |
| **M2c** | the width answer 0 on a nil axis, i.e. K6's | 2.4 **only** | **2.4, 2.2, 2.4b** |
| **M2d** | `planLegacyItems` skipped, rows registered raw | 2.1's width columns | **2.1 (all six arms), 2.5, 2.6** — 48 issues |
| **M2e** | the windowed node's `recordLoweredItem` dropped | 2.7, with an `…unconsumed` entry | **nothing** |
| **M2f** | the rows' records **neither read nor consumed** — `received` forced to all-nil. *Corrected in the verification round*: this row said "not consumed", a different and smaller mutation | 2.7 | **2.7, 2.1, 2.5, 2.6, 2.8, 2.4b** and `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` — 46 issues. The **minimal** non-consuming variant (`lowering.items[$0]` in place of `lowering.consume($0)`) reddens the **same seven tests** with **12** issues (§11.3) |
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

**Twenty of twenty-two scenarios parameterised.** The two that are not are
`aListInsideADeferredIgnoresTheEscapedScrollersOffset` (a `Deferred`
presentation root is stage 5) and the child-process probe above.
**Correction, verification round:** this paragraph said both "say so at their own
declaration and in `AuthorityCoverage.expected`'s doc", and only the probe does.
`aListInsideADeferredIgnoresTheEscapedScrollersOffset`'s doc comment stops
before it gets there and its body just calls `renderWindowed(…, authority:
.legacy)` twice; the reason lives two files away in `AuthorityCoverage.expected`'s
doc. That matters more than a missing cross-reference, because parameterising it
by mistake is not a recoverable error — under `.proposal` a `Deferred` root
**aborts** the run rather than failing a test, which is the failure mode `LR-BX`
and this lane's own child-process probe exist to keep out of the suite. The two
lines it owes are in §8.8.

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

**Why the host declares a HEIGHT — re-stated from a measurement in the
verification round, because the reason first written here was an inference.**
This section, `LR-CE` item 1, spec §6 lane 3 and two doc comments in
`ListTests.swift` all attributed the declared height to **negative free space**
("six of this file's 40- and 100-row fixtures … which the legacy engine absorbs
and the kernel does not") and concluded that with it "the host is exactly the
window and the subject is never squeezed". The lane never ran the mutation that
would have checked either half, and the verifier did (**V2**, §8.4.2): dropping
the height back to `.auto` — P1a6's shape exactly — reddens **eleven**
scenarios, not six, **`.proposal` arms only**, 14 issues, every `.legacy` arm
green, and **four of the eleven are three-row, 84pt fixtures with no negative
free space at all**. For those the mechanism is **centring**: with an `auto`
main axis the kernel centres the host's content, so
`aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` reads ys
`[258, 286, 314]` — `(600 − 84)/2 = 258` — instead of `[0, 28, 56]`. And "never
squeezed" is false for the very fixtures the ruling names: a 1120pt list is
still a flex item inside the 600pt declared-height host, and a 2800pt one inside
the 2000pt one. **The conclusion — declare both axes — is right and the code is
right; the published reason was not measured.** The criterion a later reader
should apply is *not* "is there negative free space?" but "does the host's main
axis resolve to something other than the frame, by squeezing **or** by
centring?".

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

#### 8.4.2 The mutation the lane owed and did not take (verification round)

**V2** — `hostStyle`'s declared height dropped back to `.auto`, i.e. P1a6's
shape before `LR-CE` item 1 changed it (`ListTests.swift:130`). Full unfiltered
suite: **17 issues**, 14 attributable plus the 3 then standing. **Every
`.legacy` arm green**; eleven `.proposal` arms red:

| scenario (`.proposal` arm) | what it reads under the mutation |
|---|---|
| `aRowTallerThanRowHeightIsFlooredAtRowHeightNotContent` | ys `[258, 286, 314]` instead of `[0, 28, 56]` — the centring, on an 84pt fixture with no negative free space |
| `distinctRowsGetDistinctIdentities` | `no row registered at y == 0.0` |
| `aRowKeepsItsIdentityWhenItsPositionChanges` | — |
| `paddingOnAListDoesNotShrinkItsRowsBelowRowHeight` | 2 issues |
| `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan` | — |
| `aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop` | — |
| `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing` | — |
| `aScrolledListsSpacerDoesNotShrinkUnderPadding` | 2 issues |
| `aFractionalOffsetRoundsFirstDownAndLastUp` | — |
| `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` | — |
| `aListsSceneAndHitboxesAreUnchangedByTheGroup` | 2 issues |

This is the row that belongs in §8.4's table and was missing: the host box is
the lane's largest harness decision and nothing in the lane's own three
mutations touched it. The reading also corrects the mechanism (§8.3 above).

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
| **two lines at that test's own declaration** — that it is legacy-only, that `Deferred` as a presentation root has no lowering, that stage 5 owns it, and that parameterising it before then **aborts the run** rather than failing a test | the claim that it already says so is in §8.2 (now corrected), in `7c031b1`'s message and was in §8.2's first writing | the Docs phase or the branch checker |
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

**Discharged in the verification round.** The screen was unlocked when lane 4's
verifier ran — no `CGSSessionScreenIsLocked` line, `kCGSSessionOnConsoleKey = 1`,
`displayAsleep main: 0`, `displayActive main: 1`,
`preflightScreenCaptureAccess: true`, one screen `(0,0,2056,1329) scale=2.0` —
so it took the capture this section says it could not:
`docs/probes/window-capture/capture.sh <scratch>/win f2e981f 9ad98db` reads
a-vs-b stability **0** on all four windows (`f2e981f` default and preview,
`9ad98db` default and preview), **`f2e981f` → `9ad98db` default 1840×1176
differing = 0** and **preview differing = 0**, with the live control
`default vs preview at 9ad98db: differing = 920 994`, bbox (0,15)–(1839,1175).
`IOConsoleLocked` was not read (`FR-V`). Lane 5's verifier repeated it at the
branch's final HEAD (§10.9).

### 9.10 Deferred out of lane 4

| item | why | owner |
|---|---|---|
| ~~a real-window capture at this HEAD~~ | **discharged**: lane 4's verifier found the screen unlocked and captured `f2e981f` → `9ad98db`, 0 differing on default and preview, four stability zeros and a 920 994-pixel control (§9.9) | closed |
| `AuthorityCoverage.record` called **after** `try #require(MTLCreateSystemDefaultDevice())` in three `AccessibilityDefaultsTests` scenarios | on a display-less runner those three fail at the require without recording, and the roll call then fails a **second** time with a message pointing at the coverage registry rather than at the absent device | the Docs phase or the branch checker — a statement reorder, §11.3 |
| `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` under `.proposal` | `display: none` has no lowering (`LR-CF` item 3) | the stage that lowers `display` |
| `aListInsideADeferredIgnoresTheEscapedScrollersOffset` under `.proposal` | carried from §8.8 | stage 5 |
| the demo census's re-derivation, and the three issues still standing | §7.6 | lane 5 |
| `MeasurePerformanceTests.StatefulListRow`'s re-spelling and `render`'s `reportsUnlowerableFields:` parameter | spec §6 lane 5's own first obligation; lane 4 touches no performance fixture | lane 5 |
| **other fixtures blinded by `.padding` becoming a wrapper at `f1944f8`** | carried from §6.9 and §8.8; lane 4 swept nothing new for it | unowned |
| CLAUDE.md's `List` and roll-call mentions, and the 1580 → 1598 count | the lane may not edit CLAUDE.md | the Docs phase |

---

## 10. Lane 5 — work, the 100 000-row exit test, and the demo census (`LR-BX`; corrections in `LR-CG`)

Three commits on `feat/engine-stage-4`:

| commit | what |
|---|---|
| `a36a2cf` | the red-before: four child-process probes, two of them positive controls, with the pre-lane `StatefulListRow` spelling kept as a live fixture |
| `de2b6a5` | `render`'s two parameters, the re-spelling, three parameterised scenarios with hand-derived native-work literals, the roll call 65 → 67, and the census re-derived |
| this commit | `LR-CG`, the spec's corrections, this section |

### 10.1 The red-before

Lane 5's two reds are process aborts, not assertion failures, so the red was
taken in child processes in
`ListTests.aLegacySpelledListRowAbortsAProductionProposalFrame`'s shape
(`LR-BX`). Both messages were measured first in a throwaway
`Tests/MetalUITests/ZZScratchLane5.swift` (deleted; never committed) and are now
recorded in each probe's own doc:

```
MetalUI/Frame.swift:1536: Fatal error: MetalUI: box.minSize.unconsumed has no
proposal lowering (plan task 7, stage 2); …     [demoLikeRows' root .minHeight(0)]

MetalUI/Frame.swift:1536: Fatal error: MetalUI: customElement.requestNode has no
proposal lowering (plan task 7, stage 6a); …    [StatefulListRow.requestLayout]
```

Each of the four was confirmed red and then green — the two stderr assertions
pointed at strings that cannot match, the two controls flipped from `.success`
to `.failure` — with `git status --short` clean after the restore:

| probe | red as |
|---|---|
| `aProductionFrameOverDemoLikeRowsAbortsUnderTheProposalAuthority` | `Expectation failed: err.contains("NO-SUCH-STRING-A")` |
| `aDiagnosticsFrameOverDemoLikeRowsRunsUnderTheProposalAuthority` | `expected exit status ".failure", but ".exitCode(EXIT_SUCCESS)" was reported instead` |
| `aLegacySpelledStatefulListRowAbortsAProductionProposalFrame` | `Expectation failed: err.contains("NO-SUCH-STRING-B")` |
| `aBoxSpelledRowInTheResidentSetFixtureDoesNotAbort` | `expected exit status ".failure", but ".exitCode(EXIT_SUCCESS)" was reported instead` |

**Both controls are load-bearing**, and they control for different things. The
diagnostics one says the first abort is the FLAG, not the `List`, the
`ScrollView`, the `Text` or the proposal authority — which matters because that
flag is the lane's own fix. The `Box()`-row one says the second abort is the
ROW's spelling and not the production frame around it.

### 10.2 The scratch measurements the lane turned on

Taken before anything was written, in a throwaway file, and deleted:

| question | answer |
|---|---|
| what does the diagnostics frame report over `demoLikeRows`? | `[box.minSize.unconsumed]`, at 40, 160, 500 and 2000 rows alike — nothing else |
| warm native work under `.proposal`? | `measureCalls 17, cacheHits 103, cacheMisses 120` at **every** row count |
| cold native work? | `n + 1`, `6n + 7`, `7n + 8`, exactly, at all four counts |
| cold-frame wall clock, debug | 500: 0.16 s legacy / 0.11 s proposal; 5000: 1.68 / 1.16; 20 000: 7.06 / 4.76 |
| tokenizer calls, warm | legacy **16** (one per realized row); proposal **0** |
| `shapingCache.storageCount`, warm | legacy 72, proposal 32; constant in `n` on both |
| the 10 000-row resident fixture under `.proposal` | cold `table.count` 20 005 = `2n + 5`, checkpoints 255 / 255 / 149 — **identical to legacy** |
| the demo census now | report `[]`, 2035 ids, 6 agreeing, 0 legacy-only, 2029 disagreeing |

### 10.3 The work literals — derived, and how

`SA-M` and spec §7 ask for literals derived by hand on a branching count. §2.6's
prototype P1d is a bare kernel stack of rows; the exit test measures a whole
`demoLikeRows` frame, so its numbers were derived a different way (`LR-CG`
item 2):

1. **The window, from the source.** `visibleRange` at `offset == 0` with a 370pt
   viewport and 28pt rows: `rawFirst = floor(0/28) − 2 = −2 → 0`,
   `rawLast = ceil(370/28) + 2 = 14 + 2 = 16`. **r = 16 realized rows**, whatever
   the logical count.
2. **The function, from the cold column.** A cold frame realizes every row
   (`MP-I`), so cold work at n = 40 / 160 / 500 / 2000 samples the same function
   of `r`:

   | n | `measureCalls` | `cacheHits` | `cacheMisses` |
   |---|---|---|---|
   | 40 | 41 | 247 | 288 |
   | 160 | 161 | 967 | 1128 |
   | 500 | 501 | 3007 | 3508 |
   | 2000 | 2001 | 12007 | 14008 |

   — `r + 1`, `6r + 7`, `7r + 8`, reproducing all twelve numbers with no residue.
   The `+ 1` is `WindowedRowsLayout.sizeThatFits`; the `r` is the realized rows'
   `Text` leaf closures (`measureCalls` counts leaf closures as well as custom
   bodies, `ListLoweringTests` test 2.3's own correction).
3. **The prediction.** At r = 16: **17 / 103 / 120**. The warm frames read
   exactly that at all four counts.

**Said plainly**: the coefficients 6 and 7 are measured, not counted off
`LegacyLowering.swift`. What makes them a derivation rather than a
transcription is that they predict a point the fit never saw, and that M5a moves
the literals to exactly `18 / 109 / 127` when r becomes 17.

Under `.legacy` the same read is `NativeLayoutWork()` — the control that says the
proposal numbers are this frame's own native run.

### 10.4 The exit test, run

```
METALUI_RUN_100K_LIST_TEST=1 swift test --build-system native --no-parallel \
  --filter aListsWorkIsTheSameFor100kRowsAsFor500
MeasurePerformanceTests: cold frame at 100,000 rows, legacy, took 37.163447792 seconds
MeasurePerformanceTests: cold frame at 100,000 rows, proposal, took 24.978024166 seconds
Test aListsWorkIsTheSameFor100kRowsAsFor500(authority:) with 2 test cases passed after 62.914 seconds.
Test run with 1 test in 1 suite passed after 62.914 seconds.
```

Debug, this machine. **Release, re-run the same way** (`swift test -c release
--build-system native --no-parallel --filter …`):

```
MeasurePerformanceTests: cold frame at 100,000 rows, legacy, took 12.238558583 seconds
MeasurePerformanceTests: cold frame at 100,000 rows, proposal, took 7.552452 seconds
Test run with 1 test in 1 suite passed after 20.122 seconds.
```

| configuration | legacy | proposal |
|---|---|---|
| debug | 37.16 s | 24.98 s |
| release | **12.24 s** | **7.55 s** |

**The proposal path's cold frame is about a third faster than the legacy one at
100 000 rows, in both configurations** — not a goal of this stage and not
asserted anywhere, recorded because it is the first time the two have been timed
side by side on the same tree. `MP-I` stands: every row is still built on frame 0
at both authorities.

**CLAUDE.md's `MP-I` row quotes ~17 s release for this frame and this machine now
reads 12.24 s.** Not a change this stage made — the legacy arm is the same code
path the figure was taken on — but the quoted number is stale, and correcting it
is a Docs-phase obligation (§10.10).

The test is parameterised over both authorities and **does not** call
`AuthorityCoverage.record`, because a gated name would be permanently missing
from `seen` (`LR-CG` item 4). Its ungated twin carries the name.

### 10.5 Every number

| measure | before (lane 4's HEAD, `9ad98db`) | after (`de2b6a5`) |
|---|---|---|
| suite | 1598, **3 issues** | **1602**, **0 issues** (+4: the four abort probes; the three parameterisations move the total by nothing) |
| the three standing issues | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`'s, red since `c124f40` | **gone** — the census re-derived, which is what lanes 3 and 4 were leaving for this lane |
| goldens | 97 | 97; `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` empty |
| typecheck guards | 77 | 77 — lane 5 adds no hazard a plain import can reach |
| `error:` / `warning:` | 0 / only SwiftPM's deprecation notice | unchanged |
| `AuthorityCoverage.expected` | 65 | **67** |
| parameterised suites | 9 | **10** |
| census, modal off | report `[list.noLowering]`, 2035 ids, 6 agreeing, 2000 legacy-only, 29 disagreeing | report **`[]`**, 2035 ids, 6 agreeing, **0** legacy-only, **2029** disagreeing |
| census, modal on | `[stack.position, stack.inset, list.noLowering]`, 2041 ids, 35 disagreeing | **`[stack.position, stack.inset]`**, 2041 ids, **2035** disagreeing |
| `ScrollView` / `List` lowered width in the census | 0 | **420** |
| files under `Sources/` changed | — | **none** |

`find Tests -name "*.json" | wc -l` reads 115 with `Tests/PortableTests/.build`
present; the golden count is taken under `Tests/MetalUILayoutTests` only, as §1
says.

### 10.6 The four mutations

Each on the **full unfiltered suite** from a `cp` copy, `git status --short`
empty after each restore.

| id | mutation | tests reddened | issues | named |
|---|---|---|---|---|
| **M5a** | `List.overscan` 2 → 3 (at `offset == 0` the leading side clamps, so exactly one extra row) | **17** (this cell read 18; the names beside it are 17, and the verifier's independent re-run reddens exactly those 17 — corrected in the verification round, §11.3. The gated arm is the row below, not the missing one) | 39 | `aListsWorkIsTheSameFor160RowsAsFor40` (.proposal, both work literals); `aVirtualizedListsLogicalCountDiffersFromItsRealizedRowCount`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` (both authorities each); `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape`, `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight`; `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `aFractionalOffsetRoundsFirstDownAndLastUp`, `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, `theListsSpacerIsANodeNotAnElement`, `aListInTheDifferentialHarnessReachesABoundedWindow`, `aListsSceneAndHitboxesAreUnchangedByTheGroup` (both authorities each); `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (both) |
| **M5a**, gated | the same, against the exit test | 1 | 2 | `aListsWorkIsTheSameFor100kRowsAsFor500` (.proposal), both work literals |
| **M5b** | `visibleRange`'s `context.viewportExtent > 0` guard deleted | 5 | 16 | `theResidentEntrySetStaysBoundedWhileScrolling10kRows` (**both** authorities, `table.count == 2 * n + 5`); `aPresentContextWithZeroViewportExtentBuildsEveryRow` (both); `aColdFrameCreatesAtMostOneLineBreakTokenizer`; `aListRowsStateSurvivesABoundedExcursionButNotALongerOne` (both, five assertions each); `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (its `try #require`) |
| **M5c** | the census's `report.elements` literal 2035 → 2036 | 1 | **1** | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` — one issue and no cascade, which is shape 13's `try #require` doing its job |
| **M5d** (extra) | `WindowedRowsLayout.placeSubviews` places at `index` rather than `firstIndex + index` | 9 | 57 | `aLoweredListAgreesWithTheLegacyEngineOnEveryWindowedShape` (32), `aWindowedRowIsPlacedAtItsAbsoluteIndexTimesRowHeight` (15), and, `.proposal`-side only, `aScrolledListsSpacerDoesNotShrinkUnderPadding`, `aListsSceneAndHitboxesAreUnchangedByTheGroup`, `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, `aWindowedRowSitsAtItsAbsoluteOffsetNotTheWindowsTop`, `anOffsetPastTheEndClampsToTheTailInsteadOfRenderingNothing`, `aListBuildsOnlyTheRowsIntersectingTheViewportPlusOverscan`, `aFractionalOffsetRoundsFirstDownAndLastUp` |
| **MV5e** (verification round) | `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s `renderFrame` hard-coded to `layoutAuthority: .legacy`, so its `.proposal` arm never builds a proposal frame | **0** | **0** | **nothing** — and the mutant is **not** equivalent: it deletes a real check (a production `.proposal` frame over a 10 000-row `List`). §11.3, lane 5's first minor |

**M5a's conditional, resolved.** Spec §6 lane 5 says M5a "must redden the work
equality at 500 vs 100 000 **only if** the literals are per-realized-row — if it
does not, the work test is counting something that does not depend on the window
and the lane says so". It reddens the **literals** and leaves every **equality**
green, at both row counts and in both work tests. That is the honest reading: the
equality is window-invariant by construction — widening the window moves 500 and
100 000 by the same amount — so **the literals are the whole of the `O(window)`
claim** and an equality-only test would have been the shape the design feared.

**M5d's finding: the census cannot see the windowing, and that is structural.**
M5d moves nine tests and 57 issues and does not touch
`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`.
`LayoutDifferential.render` builds one frame, so the demo's `List` is always cold
and always at `firstIndex == 0`, where `firstIndex + index == index`. The census's
2 000 new rows pin the placement formula **at its origin** and the cross-axis and
box-model differences; the windowing itself is `ListLoweringTests`' and
`ListTests`' (`LR-BY`, `LR-BW`). Recorded so a later reader does not treat the
census as a windowing test.

### 10.7 The census, re-derived once from a finished stage

Left red across lanes 3 and 4 on purpose (spec §6 lane 5) so the census would be
taken once against the whole stage. What moved, and nothing else did:

| | lane 2 (`c124f40`) | now |
|---|---|---|
| `report.unlowerable`, modal off | `[]` (asserted `[list.noLowering]` → red) | **`[]`**, asserted |
| ids | 2035 | 2035 |
| agreeing | 6 | 6 |
| legacyOnly | 0 (asserted 2000 → red) | **0**, asserted |
| disagreeing | 2029 (asserted 29 → red) | **2029**, asserted |
| the `ScrollView`'s and the `List`'s lowered widths | 0 | **420** |
| the modal's lowered-width override table | two entries | **gone** |

**The 420s.** Until this stage the lowered `List` reported and built no rows, so
the viewport's non-scrolling axis — its content's answer, `CN-M` — was an empty
content's 0. The windowed layout answers its widest realized row, which is 420
(the demo's rows declare it), so the `List` and the viewport both read 420.

**The override table goes for a reason worth writing down.** It existed because
with one child the single-child stretch elision (`LR-AC`) left the `List`
unstretched and 0 wide, and the modal's `Deferred` arriving as a second child
stretched both to 420. The `List` now measures 420 on its own, so the two modal
states agree and the special case has nothing left to carry.

**The 2 000 rows, by formula** (`LR-CG` item 5). Four ids per row — the `List`'s
own row `Box`, the demo row's `.padding` layer, the inner `Box`, the `Text`:

| id | legacy | lowered | cause |
|---|---|---|---|
| row `Box`, `.padding` layer | `(132, 439 + 28i, 420, 28)` | `(240, 455 + 28i, 420, 28)` | **55** twice: x + 108 from the served 196 sidebar, y + 16 from the taller wrapped paragraph above |
| inner `Box` | `(144, 439 + 28i, 396, 28)` | `(252, 455 + 28i, 396, 16)` | **X9** — a stretched single-child container does not stretch its child (`LR-AC`) |
| `Text` | `(144, 445 + 28i, W, 16)` | `(252, 455 + 28i, round(natural), 16)` | **X9** again for the 6pt (the legacy inner box is 28 tall and `.alignItems(.center)` centres in it; the lowered one is 16 and the text sits at its top); **55's sub-pixel tail** for `W` |

**The sub-pixel tail, and the first reading of it was wrong.** 42 of the 500
legacy texts are one point narrower than their lowered twins. The first
hypothesis — "the legacy engine floors a text's width" — was refuted by counting:
**210** of the 500 natural widths have a fraction at or above 0.5 and only **42**
floor. The real mechanism is the origin. The lowered main pane starts at the
integer x = 252 (the sidebar is served its declared 196), so cumulative-edge
rounding gives `round(natural)`; the legacy one starts at `144 − d` because the
sidebar is flex-shrunk (`SZ-L`) to a width a hair under 88, so the same rounding
gives `floor(natural)` for exactly the rows whose fraction lies in
`[0.5, 0.5 + d)`.

`d` is not recoverable from anything the frame stores — no rect keeps an
unrounded origin, and `LayoutTree.measuredWidth` keeps a width and not an x — so
the test **solves for it from the 500 rows** and asserts the bracket, measured:

```
d ∈ (0.0615234375, 0.076171875]
```

with `lower < upper` asserted separately. That second assertion is the real one:
it says **one** fractional origin explains all 500 rows, and a row wrong for any
other reason empties the bracket. Both endpoints are committed literals, so a
change to the sidebar's shrunk width moves them and names itself.

**Nothing escapes attribution.** Both modal states assert
`Set(disagreeing.keys) == namedIDs`, where `namedIDs` is the 29 chrome ids plus
the 2 000 row ids (plus the six modal ids with the modal on). A disagreement with
no named cause fails by name rather than hiding in a count.

### 10.8 The twelve `CN-R` images

`docs/probes/demo-pixels/compare.sh <scratch>/pix5 f2e981f de2b6a5`, and again
at the lane's final HEAD `6c719e0`. All nine
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

**`f2e981f` → `de2b6a5` and `f2e981f` → `6c719e0`: 0 differing pixels in all
twelve, every scene dump identical, both runs.** Expected by construction — lane 5 changes no file under `Sources/`
at all — and taken anyway, because "expected by construction" is what the harness
exists to stop a lane from asserting. The demo is never scrolled in these images,
so no scroll indicator is painted in any of them.

### 10.9 Screen lock

`docs/probes/appkit-screen-lock-state.swift` at this lane prints
`session CGSSessionScreenIsLocked = 1`,
`session CGSSessionScreenLockedTime = 1790143129`, `kCGSSessionOnConsoleKey = 1`,
`displayAsleep main: 1`, `displayActive main: 0`,
`preflightScreenCaptureAccess: true`, one screen `(0,0,2056,1329) scale=2.0`.
**Locked**, so no real-window capture was taken — the gate is the printed lock
state, not a judgement. `IOConsoleLocked` was not read (`FR-V`). Lane 3's
unlocked window (§8.7) covers the branch as it stood at `352f838` only.

**Discharged in the verification round, at the branch's final HEAD.** Lane 5's
verifier read the probe again and it printed **no** `CGSSessionScreenIsLocked`
line and `displayAsleep main: 0`, so it ran
`docs/probes/window-capture/capture.sh <scratch> f2e981f a53daeb`: a-vs-b
stability **0** on all four windows, **`f2e981f` → `a53daeb` default differing =
0** and **preview differing = 0**, control `default vs preview at a53daeb:
differing = 921 071`. The record writer re-read the lock probe once more before
committing this section — still unlocked, `displayAsleep main: 0`,
`displayActive main: 1` — and did **not** re-take the capture, because the
verifier's run is at this exact commit and was taken independently.
`IOConsoleLocked` was not read (`FR-V`).

### 10.10 Deferred out of lane 5

| item | why | owner |
|---|---|---|
| ~~a real-window capture at stage 4's final HEAD~~ | **discharged in the verification round**: lane 5's verifier found the screen unlocked and captured `f2e981f` → `a53daeb`, four stability zeros, **0 differing on default and on preview**, control 921 071 (§10.9) | closed |
| `theResidentEntrySetStaysBoundedWhileScrolling10kRows` has no authority-discriminating read | hard-coding its `renderFrame` to `.legacy` leaves the whole suite green (MV5e); `AuthorityCoverage.record` sees the argument, not the frame | the Docs phase or the branch checker — one `lastNativeLayoutWork` read per arm, §11.3 |
| four prose/message literals left at `65` / "nine files" after `expected` moved to 67 and a tenth file joined | staleness is systematic; one of the four is a diagnostic a future author reads when the check fires | the Docs phase or the branch checker, §11.3 |
| `MeasurePerformanceTests.render`'s doc over-generalises the diagnostics contract | an unconsumed **item field** goes through `noteUnlowerable` (record only); only a **site** with no lowering goes through `Frame.unlowerable`'s 0×0 substitution. The fixture's one entry is the former, so "a non-empty report means a partly degenerate tree" is false for it | the Docs phase or the branch checker, §11.3 |
| CLAUDE.md's `MP-I` release figure (~17 s at 100 000 rows) | re-measured here at **12.24 s legacy / 7.55 s proposal** (§10.4); the lane may not edit CLAUDE.md | the Docs phase |
| CLAUDE.md's `MP-I` row, divergence 18's `2n + 7` / 125 crossing, `List.swift`'s type doc, and the 1580 → 1602 count | the lane may not edit CLAUDE.md | the Docs phase |
| the `d` bracket replaced by a derivation of the legacy sidebar's unrounded width | would need a §9.7 shrink computation in a test, or a harness field recording unrounded origins (`LR-CG` item 5) | unowned |
| the census being unable to see the windowing (§10.6, M5d) | structural: the differential harness renders one frame | unowned; `ListLoweringTests` and `ListTests` cover it |
| `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `aListInsideADeferredIgnoresTheEscapedScrollersOffset` under `.proposal` | carried from §9.10 | the stage that lowers `display`; stage 5 |
| everything §7.7, §8.8 and §9.10 hand on | unchanged | as recorded there |

---

## 11. Verification round (2026-09-23, PDT) — this commit

Every lane's verifier returned **`ok: true`**. Between them they raised
**fifteen minor issues** — five on lane 1, one on lane 2, three on lane 3, two
on lane 4 and four on lane 5 — none blocking, and **not one a defect in a
landed behaviour**. Six are attribution or wording in this record and the
rulings, five are claims that are true but unpinned or not decisive, two are doc
comments broader than the code they describe, one is a deferral that turned out
to be dischargeable, and one is an accurate disclosure that needed no action.

**Nothing executable changed in this round.** The record writer's scope is
docs: this record, the decisions doc (`LR-CE` and `LR-CG` carry paragraphs
headed **Amended, verification round**) and the spec's Status and §6 lane 3.
**Five small test-file obligations are handed on rather than applied**, each
with its text, in §11.3 and again in "For the integrator". The suite figure
below was re-taken after the doc edits and is this stage's final one.

### 11.1 What the verifiers reproduced independently

Four of the five verifiers did not read the lane's numbers; they re-took them,
and one reconstructed a red-before from the commit trail.

- **Lane 1's verifier rebuilt from clean** (`swift package clean`, then the
  native build) and read **1583 tests in 2 suites passed after 53.092 s**, the
  lane's figure. It also re-ran the **gated 100 000-row exit test** at lane 1's
  HEAD (cold frame 36.9 s, debug), and left the worktree clean after each of
  nine mutations.
- **Lane 2's verifier reconstructed the red-before rather than believing it**:
  `git checkout a494777 -- Sources Tests`, full unfiltered run, then restore —
  **1587 tests, 21 issues, at the exact lines §7.1 lists** (`:247` ×3, `:252`
  ×6, `:254` ×6, `:262`, `:335`, `:378`, `:379`, `:382`, `:411`). It then
  checked that the red-before had not been weakened into green: `a494777` is
  test-only (432 insertions, one file) and `git diff a494777 HEAD --
  ListLoweringTests.swift` **deletes no non-comment line**, while `c124f40`
  changed comment lines only. That is the strongest form this branch's
  red-first claim has taken.
- **Lane 2's verifier re-ran probe K6** under `/usr/bin/swift`: exit 0, 787
  lines, `diff` against the header's recorded output **empty**, K6a–K6f
  reproducing as `LR-BR` quotes them. Lane 5's verifier did the same.
- **Lane 2's verifier re-took the twelve `CN-R` images** at `688b834`, one
  commit past the implementer's own reading: all eight controls exact, then **0
  differing pixels in all twelve with every scene dump identical**. Lane 5's
  verifier repeated it at `a53daeb` — nine controls exact, **12 of 12 at 0**.
- **Lane 5's verifier re-ran the gated exit test itself**: 62.522 s, cold frame
  **36.73 s legacy / 25.03 s proposal** against the lane's 37.16 / 24.98 — the
  same measurement twice, on the same machine, a few percent apart.
- **Lanes 3, 4 and 5's verifiers rebuilt from clean** and read 1593 / 3, 1598 /
  3 and 1602 / 0, each matching its lane and each confirming the three standing
  issues were lane 2's disclosed hand-off and nothing else.
- **Two verifiers found the screen unlocked and captured real windows** (§9.9,
  §10.9), which no lane had been able to do past lane 3.

### 11.2 The verifiers' own mutations

Seventeen mutations the lanes did not take. **None found a defect**; two stayed
green, and one of those two is now recorded as a gap rather than assumed
equivalent.

| lane | mutation | reddened |
|---|---|---|
| 1 | **V5** — the demotion undone: the spacer registered again as a `Box<EmptyGroup>` element | `theListsSpacerIsANodeNotAnElement`, `theResidentEntrySetStaysBoundedWhileScrolling10kRows` |
| 1 | **V7** — the spacer node appended last, so the returned order is rows + [spacer] | **7** windowing tests (§6.10) |
| 1 | **V9** — rows registered `under: nil` rather than `under: parent` | **6** — the retention, focus and accessibility pins lanes 4 and 5 own (§6.10) |
| 1 | **V8** — `ListRows`' authority branch collapsed to `requestNode` unconditionally | **nothing**, and proved equivalent at that HEAD by reading both paths to the same `requestNativeLeaf { 0x0 }` (§6.10) |
| 2 | **M2f, both spellings** — the minimal non-consuming one (12 issues) against the coarse "neither read nor consumed" one (46) | the **same seven tests**; the difference is the count, which is why §7.4's row now says which mutant produced 46 |
| 2 | **M2a re-taken as worded** | the same two tests, **47** attributable issues, not 30 |
| 2 | **M2e re-taken** | **nothing**, and the verifier re-derived the equivalence argument from the source rather than accepting §7.4's |
| 2 | **M2h re-taken**, with `LegacyLowering.swift:812-1010` read to check the correction's scope | **B6 alone**, exactly as claimed — for `.flex(isRow: false)` the only read of `parent.size.width` is the elision's `parentCross` |
| 3 | **V1** — `WindowedRowsLayout.placeSubviews` drops `firstIndex`, asked of lane 3's **new** `.proposal` arms specifically | **60 issues**: seven of lane 3's parameterised scenarios on their `.proposal` arm, plus lane 2's two. The new arms have teeth independently of the tests written for the layout |
| 3 | **V2** — the host box's declared height dropped back to `.auto` | **11 scenarios, `.proposal` only, 14 issues** — the mutation the lane owed, and the one that corrects `LR-CE` item 1's mechanism (§8.4.2) |
| 3 | **V3** — the spacer restored to a `Box` element on `ListRows`' legacy arm, to ask whether lane 3's **re-pointed** id still addresses its subject | **5**, `theListsSpacerIsANodeNotAnElement` among them with `spacerEntries` non-empty — the re-pointed address is live, not blind |
| 3 | **V4** — the lane's one new test's expected stderr string made unmatchable | `aLegacySpelledListRowAbortsAProductionProposalFrame` |
| 4 | **V1** — the abort probe's own subject given the `lowersToProposal` branch | `aLegacySpelledExcursionRowAbortsAProductionProposalFrame`, on **both** halves (exit status and stderr) — the child-process instrument is live, not a test that passes on any exit |
| 4 | **V2** — `.minHeight(px(0))` re-added to `AccessibilityDefaultsTests.scrolledList`, the modifier `LR-CF` item 2 removed | **the run aborts with no summary line**, `box.minSize.unconsumed has no proposal lowering`, first inside `combinationReaches… → .proposal`. Both halves of the lane's finding confirmed at once: the modifier is exactly what blocked those tests, and the new `.proposal` arms really do run through the lowering |
| 4 | **V3** — `List.overscan` 2 → 3, asked of the accessibility arms' non-vacuity | **40 issues, every parameterised one symmetric across authorities** |
| 5 | **MV5e** — `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s `renderFrame` hard-coded to `.legacy` | **nothing**, and the mutant is **not** equivalent — §11.3, lane 5's first minor |
| 5 | **M5a re-taken** | the same 17 tests and 39 issues; the lane's cell said 18 |

### 11.3 The fifteen, and what each cost

**Lane 1 (5).** All five are recorded in §6.10; two carry an obligation.

1. **`LayoutDifferential.compare` gained a `frames:` parameter with no caller.**
   Dead today and unreddenable. Recorded so a later reader does not mistake it
   for covered scaffolding; lane 2's `ListLoweringTests` uses `compare` at its
   default. **Owner:** whoever next edits `LayoutDifferential` — give it a
   caller or remove it.
2. **`ListRows.GroupLayout.spacer` is stored every frame and never read.** A
   deliberate inert internal field, now stated as one. No row in CLAUDE.md's
   inert table: that table is public API, and lane 2 makes the field optional
   because the windowed path has no spacer.
3. **`ListRows`' two `countMismatch` preconditions are unpinned traps** where
   `ArrayGroup`'s identical trap has an exit test. Unreachable from any public
   API by reading; constructible from a `@testable` test exactly as
   `ArrayGroup`'s is. **Owner:** the Docs phase or the branch checker — an exit
   test mirroring `changingAnArrayGroupsCountBetweenPhasesTraps`, or the
   reachability argument written into the source.
4. **The spacer's style no longer passes through `animated(_:_:for:pass:)`.**
   A behavioural half of the demotion the docs did not disclose. Intended, and
   now written down: the windowed layout has no spacer, and a spacer height that
   tracks the scroll offset should not ease.
5. **The authority branch in `ListRows` was never distinguished by a test**
   (V8), with the equivalence proved rather than assumed. Nothing owed — lane 2
   replaces the branch — and recorded so lane 2's reader knows what it replaced.

**Lane 2 (1).**

6. **Two mutation rows gave counts the mutation as worded does not reproduce.**
   M2a's "30 issues" reads 47 attributable; M2f's "46" is the **coarse** mutant
   (`received` forced to all-nil — records neither read nor consumed), where the
   minimal non-consuming one reads 12. The **test sets** in both rows reproduce
   exactly. Both rows corrected in §7.4, with the spelling that produced the
   figure named. This is stage 3's "record which branch a mutation was applied
   to" recurring one stage later, in the form of *which spelling*.

**Lane 3 (3).**

7. **`LR-CE` item 1's stated mechanism is wrong where it is checkable**, and the
   lane never ran the mutation that would have shown it. Negative free space is
   not the whole reason the host needs a declared height — four of the eleven
   scenarios V2 reddens are 84pt fixtures with none — and "the subject is never
   squeezed" is false for the 1120pt and 2800pt fixtures the ruling names. The
   conclusion and the code are right. Corrected in §8.3, measured in §8.4.2,
   amended in `LR-CE` item 1, and corrected in spec §6 lane 3. **Two doc
   comments in `ListTests.swift` (around lines 117–126 and 412–417) still repeat
   it** — owner: the Docs phase or the branch checker.
8. **`aListInsideADeferredIgnoresTheEscapedScrollersOffset` says nothing at its
   own declaration**, against §8.2's claim, `7c031b1`'s message and spec §6
   lane 3's requirement. It matters because parameterising it by mistake
   **aborts the run** rather than failing a test. §8.2 corrected; the two lines
   it owes are in §8.8. **Owner:** the Docs phase or the branch checker.
9. **The branch was red at lane 3's HEAD (3 issues) and stayed red through lane
   4.** Verified to be exactly lane 2's disclosed hand-off and nothing of lanes
   3 or 4's. No action: lane 5 cleared it, and §7.6 is the disclosure. The
   lesson for a reader of the commit trail is that between `c124f40` and
   `de2b6a5` a 3-issue run is the baseline, and "green" is not the signal.

**Lane 4 (2).**

10. **A deferral that was dischargeable.** The screen was locked when lane 4
    finished and unlocked when its verifier ran, so the verifier took the
    capture the lane deferred: `f2e981f` → `9ad98db`, four stability zeros, **0
    differing on default and on preview**, control 920 994. §9.9 records it and
    §9.10's row is struck. Left as written, a discharged deferral would have
    propagated to the Docs phase as open work.
11. **Three `AccessibilityDefaultsTests` scenarios call
    `AuthorityCoverage.record` AFTER `try #require(MTLCreateSystemDefaultDevice())`**,
    where the other eight parameterised scenarios record first. On a runner with
    no display device those three fail at the require without recording, and the
    roll call then fails a **second** time with a message pointing at the
    coverage registry rather than at the absent device. CLAUDE.md's CI section
    already says device-dependent window tests hard-fail; this adds a
    mis-attributed cascade. **Owner:** the Docs phase or the branch checker — a
    statement reorder in `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`,
    `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` and
    `aClientDoesNotChangeStateRetention`; the suite must still read 1602 / 0
    afterwards.

**Lane 5 (4).**

12. **One of the two ungated twins has no authority-discriminating read**, and
    nothing pins its wiring: hard-coding
    `theResidentEntrySetStaysBoundedWhileScrolling10kRows`'s `renderFrame` to
    `.legacy` leaves all 1602 tests green (MV5e). The mutant is **not**
    equivalent — it deletes a production `.proposal` frame over a 10 000-row
    `List`, which is what says the re-spelled `StatefulListRow` does not abort at
    scale and that reaping is unchanged — so by this project's own rule it is a
    finding, not an equivalence. `AuthorityCoverage.record` cannot cover it: it
    sees the argument, not the frame. Its sibling
    `aListsWorkIsTheSameFor160RowsAsFor40` **is** discriminating (`NativeLayoutWork(17, 103, 120)`
    under `.proposal`, `NativeLayoutWork()` under `.legacy`). Recorded in §10.6
    and in `LR-CG` item 4's amendment. **Owner:** the Docs phase or the branch
    checker — one `lastNativeLayoutWork` read per arm, the control the work test
    already uses.
13. **M5a's row said 18 tests and names 17.** The issue count (39) is exact and
    the verifier's re-run reddens exactly those 17. Corrected in §10.6.
14. **Four prose and message literals left at the old values** when
    `AuthorityCoverage.expected` moved 65 → 67 and a tenth file joined:
    `AuthorityCoverage.swift:54` ("The nine contributing files sort …", followed
    by ten names), `:223` ("and re-derive the 65") — which is a **diagnostic a
    future author reads when the check fires** — and `ZZAuthorityRollCall.swift`
    lines 15–18 (nine suites listed, `MeasurePerformanceTests` missing), `:31`
    ("the 65 names") and `:45` ("every literal in the nine suites re-derived").
    Staleness is systematic; the whole table is owed, not the rows a reviewer
    sampled. **Owner:** the Docs phase or the branch checker.
15. **`MeasurePerformanceTests.render`'s doc over-generalises the diagnostics
    contract.** An unconsumed *item field* goes through `noteUnlowerable`
    (record only); only a *site* with no lowering goes through
    `Frame.unlowerable`, which substitutes a 0×0 leaf. The fixture's one entry
    (`[box.minSize.unconsumed]`) is the former, so "a non-empty report means the
    counters beside it were taken over a partly degenerate tree" is false for
    it, and a later reader could distrust or delete the exact-report assertion.
    `demoLikeRowsReport`'s own doc and `LR-CG` item 1 state it correctly.
    **Owner:** the Docs phase or the branch checker.

### 11.4 Suite, goldens, guards after the round

- `swift build --build-system native --build-tests`: 0 `error:`, the only
  `warning:` SwiftPM's `--build-system native` deprecation notice.
- Unfiltered `swift test --build-system native --no-parallel`: **`Test run with
  1602 tests in 2 suites passed after 56.264 seconds`**, exit 0.
- Goldens **97** (`find Tests/MetalUILayoutTests -name "*.json" | wc -l`);
  `git diff --name-only f2e981f HEAD -- 'Tests/**/*.json'` **empty**. A bare
  `find Tests` reads 115 with `Tests/PortableTests/.build` present; that is not a
  regression.
- Typecheck guards **77** (79 `canTypecheck` hits less `Typecheck.swift`'s
  declaration and `UnitSafetyTests`' comment) — **none added by any lane**, so
  "mutate each new guard red once" is vacuous for this stage.
- Screen at the round: **unlocked** — no `CGSSessionScreenIsLocked` line,
  `displayAsleep main: 0`, `displayActive main: 1`,
  `preflightScreenCaptureAccess: true`, one screen `(0,0,2056,1329) scale=2.0`.
  The capture was **not** re-taken here, because lane 5's verifier took it at
  this exact commit's `Sources/`/`Tests/` content, independently (§10.9).
  `IOConsoleLocked` was never read (`FR-V`).

---

## What landed, in one place

Branch `feat/engine-stage-4` from `f2e981f`, 2026-09-23 (PDT), twenty-five
commits (twenty-four before this one):

| commit | what |
|---|---|
| `6a943e1`, `8aafaee` | the stage-4 design (`LR-BQ`…`LR-BW`) and critic round 1 applied (`LR-BX`…`LR-CB`, fifteen defects, all confirmed and all applied) |
| `511ae3d`, `136f171`, `eb42883`, `ca5a546`, `d811944` | **lane 1** — `ListRows`, the spacer's demotion, the differential harness's two parameters, the committed `CN-R` pixel rig, `LR-CC` and record §6 |
| `a494777`, `13c12f0`, `c124f40`, `688b834` | **lane 2** — `WindowedRowsLayout`, the lowering, `List`'s site check deleted, `LR-CD` and record §7 |
| `c4ce2f0`, `7c031b1`, `352f838`, `4ae0e27`, `16d6696` | **lane 3** — `ListTests` under both authorities, the host box, the roll call renamed, `LR-CE` and record §8 |
| `a0cdc0a`, `779a6a4`, `684ef95`, `9ad98db` | **lane 4** — retention, focus and accessibility under both authorities, the roll call moved to `ZZ…`, `LR-CF` and record §9 |
| `a36a2cf`, `de2b6a5`, `6c719e0`, `a53daeb` | **lane 5** — work counted, the 100 000-row exit test at both authorities, the census re-derived, `LR-CG` and record §10 |
| (this commit) | the verification round: the record's corrections, `LR-CE` and `LR-CG` amended, the spec's Status, record §11 and this closing half |

**The behaviour.** Under the **proposal authority only** — production still runs
the legacy authority until stage 6b — `List` lowers onto the kernel:

- **`List`'s explicit site check is gone** (`LR-BQ`). `noteUnlowerable(.list,
  "noLowering")` and the `lowersToProposal ? 0..<0 : …` window are deleted and
  `List.requestLayout` is authority-blind again. `UnlowerableField.owningStage`'s
  `.list` case survives for item fields only; there is no site-level report left.
- **The rows are a group and the spacer is a node** (`LR-BS`).
  `Pair(Box(spacerStyle), ArrayGroup(rows))` became `ListRows<Row>`, and on the
  legacy path the leading spacer is a bare layout node rather than an element:
  no `$anim` entry, no `Frame.elementBounds` row, no animation of its height,
  and one fewer `StateTable` id per `List` — which moves the resident-entry
  formula `2n + 6` → **`2n + 5`** and divergence 18's `demoLikeRows` formula
  `2n + 7` → **`2n + 6`**, crossing `sweepThreshold` at **126** rows rather than
  125. Row identity is unaffected, and §6.4's M1c is the proof rather than an
  assumption.
- **The windowed rows are a `ProposalLayout`** (`LR-BQ`, `LR-BR`).
  `WindowedRowsLayout` answers `rowHeight × logicalCount` on the height and the
  proposal (or the widest realized row at a nil axis) on the width, and places
  realized row *i* at `(firstIndex + i) × rowHeight` — SwiftUI's `List` is
  greedy and content-blind (probe K6), and the kernel deliberately is not on the
  height, because a `List` is virtualized and its content height is the whole
  point. Each realized row is consumed, planned and wrapped by stage 2's item
  machinery at `parentSite: .list`, and the arrangement records **itself** as
  the group's item.
- **Everything that had to survive, survived, and is now measured under both
  authorities**: row `@State` and focus across a bounded excursion and their
  loss past it (`TB-AH`, `staleAfterGenerations` 2, `sweepThreshold` 256), the
  `AXTable` and its rows' `AXIndex`es, the unbounded-window and one-more-frame
  rules (`AB-L`, `AB-X`), `MP-I`'s cold frame, wheel routing, hit testing and the
  disabled gate. **Not one literal moved** in the eleven retention and
  accessibility scenarios.
- **Divergences 13 and 14 survive**, pinned wrong on purpose as before — and
  their pins now run under **both** authorities, so the windowing they describe
  is the same windowing on the kernel.
- **The exit criterion is met** (`LR-BW`, `LR-BX`): `ListTests`' 22 scenarios
  (20 parameterised), `TombstoneTests`, `FocusTests`, `AXNodeTests`,
  `AccessibilityDefaultsTests`, `AccessibilityTreeTests` and
  `MeasurePerformanceTests` run **67 named scenarios under both authorities**,
  the file's custom rows re-spelled through the legacy lowering rather than as
  bare native leaves (`ProbeLeaf`'s spelling would drop the item plan, measured
  as M3b), and `aListsWorkIsTheSameFor100kRowsAsFor500` runs at both
  authorities counting native work: **17 measure calls, 103 hits, 120 misses**
  at 500 rows and at 100 000, derived by hand from the window (r = 16) before
  the run.

**What did not move**, deliberately and measured: production pixels (twelve
offscreen images at 0 at every lane and twice more in verification; two real
window captures at 0), the 97 goldens, the 77 guards, the seven reserved
identity slots, and every legacy-authority answer in every suite this stage
touched.

## Tests and guards, per file

`@Test` functions, current count and the delta against `f2e981f`. The deltas sum
to **+22**, exactly the suite delta 1580 → **1602**: a parameterised test counts
as **one** entry in the summary line, so the 67 scenarios × 2 authorities add
nothing to the total, which is why the roll call exists.

| file | now | delta | lane |
|---|---|---|---|
| `Tests/MetalUITests/ListLoweringTests.swift` (new) | 9 | **+9** | 2 |
| `Tests/MetalUITests/ListTests.swift` | 22 | **+4** | 1 (+3), 3 (+1, the child-process abort probe); 20 of its 22 parameterised |
| `Tests/MetalUITests/MeasurePerformanceTests.swift` | 11 | **+4** | 5 — four abort probes, two of them positive controls; three scenarios parameterised |
| `Tests/MetalUITests/TombstoneTests.swift` | 7 | **+2** | 4 |
| `Tests/MetalUITests/AccessibilityDefaultsTests.swift` | 18 | **+2** | 4 |
| `Tests/MetalUITests/AXNodeTests.swift` | 19 | **+1** | 4 |
| `Tests/MetalUITests/ZZAuthorityRollCall.swift` (new) | 1 | **+1** | 4 — the roll call, moved out of `ScrollViewTests` so it sorts last |
| `Tests/MetalUITests/ScrollViewTests.swift` | 7 | **−1** | 4 — the same move |
| `Tests/MetalUITests/AuthorityCoverage.swift` (renamed from `ScrollAuthorityCoverage.swift`) | 0 | 0 | 3, 4, 5 — the registry and the 67 hand-derived names; no `@Test` of its own |
| `Tests/MetalUITests/LayoutDifferential.swift` | 0 | 0 | 1 — `stateTable:` and `frames:` |
| `Tests/MetalUITests/FocusTests.swift`, `AccessibilityTreeTests.swift` | 21, 19 | 0 | 4 — parameterised |
| `Tests/MetalUITests/LayoutAuthorityTests.swift`, `LoweringCorpusTests.swift`, `LoweringScrollTests.swift` | 11, 3, 12 | 0 | 2, 5 — the two retired pins, the census, one stale doc comment |
| `Tests/MetalUITests/ScrollIndicatorTests.swift`, `ScrollRoutingTests.swift` | 14, 16 | 0 | 3 — re-pointed at the renamed registry |

By lane: **+3** (1), **+9** (2), **+1** (3), **+5** (4), **+4** (5), **0**
(verification round).

**Guards: 77, unchanged — this stage added none.** Per-file, measured at this
HEAD: `PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
`EnvironmentCompileGuards` 8, `ProposalNodeIDCompileGuards` 6,
`ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `GridCompileGuards`
4, `ContainerCompileGuards` 4, `DecorationCompileGuards` 3, `AXNodeTests` 3,
`UnitSafetyTests` 2 (3 hits, one a comment), `SceneBoundaryCompileGuards` 2,
`ModifiedElementCompileGuards` 2, `FrameSizingCompileGuards` 2,
`LayoutAuthorityCompileGuards` 1, plus `Typecheck.swift`'s declaration, which is
not a guard. Nothing in stage 4 narrows an access level or adds a spelling that
must not compile: `ListRows` and `WindowedRowsLayout` are internal, and `List`'s
two new `public struct`s (`Layout`, `PrepaintState`) **widen** rather than
narrow.

## Probes

**No new SwiftUI probe.** Every SwiftUI behaviour claim this stage makes comes
from **K6** in `docs/probes/swiftui-stack-algorithms.swift` (787 lines), which
was re-run before it was relied on — by the design session, by lane 2, by lane
5 and by two verifiers, under `/usr/bin/swift` (Apple Swift 6.4,
swiftlang-6.4.0.33.1, macOS 27.0), exit 0, and each time **diffed
mechanically** against the output recorded in the probe's own header rather than
read by eye. Empty diff every time. K6's reading — SwiftUI's `List` is greedy
and content-blind, the proposal on a concrete axis, 0 on a nil one, ∞ at ∞, and
a row's own size never reaching the answer — is what `LR-BR` departs from on the
height axis, with the reason recorded.

**`docs/probes/demo-pixels/` is new and committed** (`ca5a546`, `LR-CB`): the
`CN-R` twelve-image harness — `compare.sh`, `ZZDemoPixels.swift` and
`rawdiff.swift`. It retires the standing deferral that this generator had been
lost and rebuilt four times (records §18, §25 §7.6, §8.8, §9.8, §14.4). It was
**certified by running its eight controls against a `git archive` of `f2e981f`
and reproducing every recorded figure**, and it prints the controls, with each
expected value in brackets, **before** any commit-to-commit row, so a harness
that had gone blank cannot read 0 everywhere and look like a pass. A ninth
control — zero indicator rects across all twelve scenes — carries record §25
§7.6's caveat forward mechanically.

`docs/probes/appkit-screen-lock-state.swift` is the gate before every capture
attempt (six readings this stage: locked at lanes 1, 2, 4 and 5, unlocked at
lane 3, at two verifiers and at this round). `IOConsoleLocked` was never read
(`FR-V`). `docs/probes/window-capture/capture.sh` took the three real-window
comparisons.

## Red runs, in one place

Full unfiltered runs unless noted. **Three of the five lanes could not take an
assertion failure at all**, because the pre-lane spelling *aborts* under the
proposal authority rather than failing — so their red is a child process with a
recorded exit status and stderr (`LR-BX`), and in every case the pre-lane
spelling was **kept** as a live fixture rather than deleted with the commit that
removed its subject.

| lane | commit | run | red |
|---|---|---|---|
| 1 | `511ae3d` | 1583, **3 issues** | `theListsSpacerIsANodeNotAnElement` (`spacerEntries.isEmpty`), `aListInTheDifferentialHarnessReachesABoundedWindow` (`!rows.isEmpty`, on the **one-frame** harness so that it is a failure and not a compile error), `theResidentEntrySetStaysBoundedWhileScrolling10kRows` (`2 * n + 5` read failing at `2 * n + 6` — the arms made to disagree first) |
| 2 | `a494777` | 1587, **21 issues** | exactly four tests, at the lines §7.1 lists; the other five lane-2 tests read `WindowedRowsLayout`'s own answer and cannot compile at lane 1's HEAD, so they are not red-befores and their evidence is §7.4's mutations. Reconstructed independently by the verifier |
| 3 | `c4ce2f0` | two child processes | both exit non-zero with `customElement.requestNode` / `customElement.requestLeaf … has no proposal lowering`; each assertion confirmed by pointing it at a string that cannot match |
| 4 | `a0cdc0a` | four child processes + **two positive controls** | `customElement.requestNode` (×2), `box.minSize.unconsumed`, `box.display.none`; the controls exit 0 and are load-bearing — one of them refuted the design's premise about `FocusTests` |
| 5 | `a36a2cf` | four child processes, **two of them positive controls** | `box.minSize.unconsumed` and `customElement.requestNode`; the controls separate the flag from the `List` and the row's spelling from the frame around it |

## Verifier verdicts, in one place

| lane | verdict | minors |
|---|---|---|
| 1 | `ok: true` | 5 — `compare(frames:)` unexercised; `GroupLayout.spacer` inert; `ListRows`' `countMismatch` traps unpinned; the spacer no longer animates; the authority branch never distinguished (V8) |
| 2 | `ok: true` | 1 — two mutation rows' issue counts not reproducible from the mutation as worded |
| 3 | `ok: true` | 3 — `LR-CE` item 1's mechanism unmeasured (V2); the `Deferred` scenario silent at its own declaration; the branch red at that HEAD (disclosure accurate, no action) |
| 4 | `ok: true` | 2 — a real-window capture deferral that was dischargeable (and discharged); `record` after `try #require` in three scenarios |
| 5 | `ok: true` | 4 — the 10 000-row twin has no discriminating read (MV5e); M5a's 18 vs 17; four stale `65`/"nine" literals; `render`'s doc over-general |

All fifteen are dispositioned in §11.3: ten applied in this commit (this
record's corrections, `LR-CE` and `LR-CG`'s amendments and the spec's), and five
handed on as test-file obligations with their text.

## Mutations that stayed green, and what has no mutation

- **M1c / V6** (lane 1) — the group's cursor advanced past the spacer. Green,
  and a **proof**: the cursor's only consumer is
  `GlobalElementID.enteringGroupMember`, every row supplies a `name`, and
  `child(of:at:name:)` never consults `at:` once a name is supplied. That is the
  measured reason row identity survives the spacer leaving cursor 0.
- **V8** (lane 1's verifier) — `ListRows`' authority branch collapsed. Green,
  and **proved equivalent at that HEAD** by reading both paths to the same
  `requestNativeLeaf { 0x0 }`; not equivalent in a production proposal frame,
  which no test reached. Replaced by lane 2.
- **M2e** (lane 2) — the windowed node's `recordLoweredItem` dropped. Green, and
  a **proof**: a dropped record never joins `LoweringState.order`, so it cannot
  raise an `…unconsumed` entry at all, and the stretch item frame it would have
  earned is redundant against a layout that already answers `proposal.width`.
  Kept for `LR-AB`'s uniform convention, documented as inert-today in two places.
- **M2g** (lane 2) — `rowStyle.flexShrink` dropped from the record handed
  `planLegacyItems`. **Not a mutation at all**: the `[LegacyItemPlan]` is
  byte-identical with and without it, printed for all six rows. The real
  measurement behind `LR-BS`'s "inert rather than removed" is **M2g′**, the line
  deleted from `List.requestLayout` outright, which reddens two **legacy** arms
  and nothing on the proposal path.
- **M4b** (lane 4) — `indexesRows`' `windowIsBounded &&` conjunct dropped.
  Green, and the equivalence **read off two guards one method away and written
  into the source as a comment**, so a later reader does not take the conjunct
  for a tested guard. `AB-X` rule 1 is pinned through the suppression instead,
  by M4b′.
- **M5d against the census** (lane 5) — the placement formula's `firstIndex`.
  Reddens nine tests and **not** the census, and the reason is structural: the
  differential harness renders one frame, so the demo's `List` is always cold and
  always at `firstIndex == 0`. Recorded so nobody reads the census as a
  windowing test.
- **MV5e** (lane 5's verifier) — `theResidentEntrySetStaysBoundedWhileScrolling10kRows`
  hard-coded to `.legacy`. Green, and **not equivalent**: a real check deleted.
  The stage's one banked gap, with an owner and the one-line fix named.
- **Has no mutation, by name**: `WindowedRowsLayout.sizeThatFits`'s height
  answer as it reaches a *composed* tree (M2b shows `List.init`'s declared height
  masks it, so the invariant lives in two places with no test that they agree);
  `ListRows`' two `countMismatch` traps; and every stage-1/2/3 hole this stage
  did not touch (`measureNativeLayout`'s bracket, the horizontal content clip's
  translation, site `component`'s report).

## Demo comparisons, in one place

Every lane re-took the twelve `CN-R` images from a `git archive` of its own last
`Sources/`-changing commit against an archive of `f2e981f`, controls read first.
**The harness is committed this stage**, so for the first time these are the
same instrument every time, not a rebuild.

| taker | commits | twelve images |
|---|---|---|
| lane 1 | `f2e981f` → `eb42883` | 12/12 **0**, scene dumps identical |
| lane 2 | → `c124f40` | 12/12 **0** |
| lane 3 | → `352f838` | 12/12 **0** |
| lane 4 | → `684ef95` | 12/12 **0** |
| lane 5 | → `de2b6a5`, and again → `6c719e0` | 12/12 **0**, both runs |
| lane 2's verifier | → `688b834` | 12/12 **0**, every scene dump identical |
| lane 5's verifier | → `a53daeb` | 12/12 **0**, every scene identical |

Controls on the head images, `f2e981f`'s figures exactly, at every taking: light
vs dark f0 **1 048 576**; vs modal-light **1 030 498**; vs animation-light
**210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**;
`chrome-legacy` vs `chrome-proposal` **0**; 544 distinct values in
`default-light-f0`; 216 in `chrome-legacy`; **0 indicator rects in all twelve**.

**Real windows: three, all at 0.** The screen was locked at lanes 1, 2, 4 and 5
and unlocked at lane 3 and at two verifiers.

| taker | commits | default | preview | stability (a vs b, ×4) | control |
|---|---|---|---|---|---|
| lane 3 | `f2e981f` → `352f838` | **0** | **0** | 0 | 921 071 |
| lane 4's verifier | `f2e981f` → `9ad98db` | **0** | **0** | 0 | 920 994 |
| lane 5's verifier | `f2e981f` → `a53daeb` | **0** | **0** | 0 | 921 071 |

**What the twelve images still cannot see**: none of the scenes is ever
scrolled, so no indicator is painted in any of them, and — this stage's own
caveat — **the demo's `List` is never windowed in them either**, because a
single cold frame realizes every row at `firstIndex == 0`. The windowing is
pinned by tests, not by pixels.

## Hazards this stage introduced or exposed

1. **`List` now lowers unconditionally**, so any proposal-authority frame
   holding a `List` runs `WindowedRowsLayout`. A regression in it **traps** in a
   production frame rather than reporting — stage 3's hazard 1, now reachable
   through the one element most likely to appear in a fixture. Read the last
   lines of a truncated log, not the summary.
2. **The roll call spans ten files and 67 names and depends on Swift Testing's
   unspecified cross-file order.** `ZZAuthorityRollCall.swift` carries its `ZZ…`
   prefix to sort last (lane 4 had to move it when `TombstoneTests.swift` sorted
   after `ScrollViewTests.swift`), and `ZZDemoPixels.swift` carries the same
   prefix for the same reason. **A new parameterised scenario owes an
   `AuthorityCoverage.record` call and a bump of the 67**, and
   `swift test --filter everyParameterisedScenario` hard-fails by construction.
   Four literals still say 65 / "nine files" (§11.3 item 14).
3. **Divergences 13 and 14 are unchanged and now pinned on both authorities.**
   A fix to either must delete or invert **both arms** of its pin. 14's pin is
   `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`, which says so
   in its own failure message; 13's contract pin is
   `scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`
   and its *effect* is still reached by nothing.
4. **`List.init`'s declared height masks `WindowedRowsLayout.sizeThatFits`'s
   height answer** (M2b): the layout's height is observable only through the
   kernel, so the invariant lives in two places with no test that they agree.
   Whoever changes either owes the other.
5. **The nil-width path measures every LOGICAL row, twice** (`LR-CA`, test
   2.4b): `O(logicalCount)`, not `O(window)`. It is unreachable from a real
   `List` today (a `List` declares a width through its `ScrollView`), and
   mitigating it would change `visibleRange`, which `LR-BT` pins shut. Stage 6b.
6. **Fixtures blinded by `.padding` becoming a wrapper at `f1944f8`.** §6.5
   found two in `ListTests` **by mutation**, and both had been blind since
   `f1944f8` — before this stage touched anything. Nobody has swept for more and
   the decay is silent by construction.
7. **Shared-file collisions with any parallel track.** `List.swift` lost 130
   lines and gained two public wrapper types; `ListRows.swift` is new;
   `ElementGroup.swift` and `LayoutAuthority.swift` changed; `ListTests.swift`,
   `TombstoneTests.swift`, `FocusTests.swift`, `AXNodeTests.swift`,
   `AccessibilityDefaultsTests.swift`, `AccessibilityTreeTests.swift` and
   `MeasurePerformanceTests.swift` are now parameterised by authority; and
   `ScrollAuthorityCoverage.swift` was **renamed** to `AuthorityCoverage.swift`,
   which a merge will not resolve for you. A merge that adds a `List`, scroll or
   retention test without a `record` call turns the exit criterion red.
8. **`swift package clean` is required after this stage's merge.** `List` is
   public, crosses a module boundary, and its stored `box`'s generic argument
   changed (lane 1 and lane 2 both cleaned before measuring).
9. **`MP-I`'s quoted release figure is stale** — CLAUDE.md says ~17 s for the
   100 000-row cold frame and this machine reads **12.24 s legacy / 7.55 s
   proposal** (§10.4). Not a change this stage made; the legacy arm is the same
   code path. Correcting it is a Docs-phase obligation.
10. **The 100 000-row exit test is gated and therefore outside the roll call**
    (`LR-CG` item 4). Its two ungated twins carry the names, and one of the two
    has no authority-discriminating read (§11.3 item 12).

## Deferred, each with an owner

| deferred | owner |
|---|---|
| the five test-file obligations of §11.3 — the two stale `ListTests` doc comments (item 7), the two lines the `Deferred` scenario owes (8), `record` before `try #require` in three scenarios (11), one discriminating read in the 10 000-row twin (12), four stale `65`/"nine" literals (14), and `render`'s over-general doc (15) | **the Docs phase or the branch checker** |
| an exit test for `ListRows`' `countMismatch`, or the reachability argument written into the source | the Docs phase or the branch checker |
| `LayoutDifferential.compare`'s `frames:` given a caller or removed | whoever next edits `LayoutDifferential` |
| `aListInsideADeferredIgnoresTheEscapedScrollersOffset` under `.proposal` | **stage 5** (`Deferred` as a presentation root) |
| `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` under `.proposal` | the stage that lowers `display: none` |
| the nil-width path's `O(logicalCount)` measurement cost | stage 6b (`LR-CA`, spec §9) |
| divergences **13** and **14** — they **survive** stage 4 unchanged and their pins now run on both authorities | unchanged owners; neither is stage 4's to retire |
| the `d` bracket in the census replaced by a derivation of the legacy sidebar's unrounded width | unowned (`LR-CG` item 5) |
| the census's structural blindness to windowing (one frame, `firstIndex == 0`) | unowned; `ListLoweringTests` and `ListTests` cover it |
| **other fixtures blinded by `.padding` becoming a wrapper at `f1944f8`** | unowned — worth a sweep by whoever next mutates a padded fixture |
| lazy grids (`LazyVGrid`/`LazyHGrid`), which needed this stage's windowing | stage G2 (`GR-L`) |
| everything stages 5–14 already own: `Deferred`, absolute positioning, `display`, custom elements, `ProposalScrollView`'s context and animation, the root switch, the deletions | unchanged by this stage |

## For the integrator

**Verdict: all five lanes verified `ok: true`.** Fifteen minor issues in total,
none blocking and none a defect in a landed behaviour; ten applied in this
commit (this record's corrections, `LR-CE` item 1 and `LR-CG` item 4's
**Amended, verification round** paragraphs, and the spec's Status and §6 lane 3),
five handed on as test-file obligations with their exact text. No lane needed a
fix round.

This branch's figures at this commit: **1602 tests, 97 goldens, 77 guards, 0
`error:` / 0 `warning:`** (the lone `warning:` in a native log is SwiftPM's
deprecation notice). Re-take every count after the merge, **after `swift package
clean`** — `List` is public and its stored `box`'s generic argument changed.

**`CLAUDE.md` (rules only; then `cp CLAUDE.md AGENTS.md` and `cmp`):**

1. **Ruling table**, line 36: `` `LR-` (next `LR-BQ`) `` → `` `LR-` (next
   `LR-CH`) ``. In the per-task list (around line 52), after the stage-3 entry:
   `` 7 stage 4 `LR-BQ`…`LR-CG` (§27, spec
   `specs/2026-09-23-engine-stage-4-design.md`, same decisions doc; no new
   probe — its SwiftUI claims are `swiftui-stack-algorithms.swift`'s K6) ``.
2. **Counts** (the bullet at line 84): 1580 / 97 / 77 → **1602 / 97 / 77** on
   `feat/engine-stage-4` (**+22 tests**: lane 1 +3, lane 2 +9, lane 3 +1, lane 4
   +5, lane 5 +4; **0 goldens, 0 guards** — no typecheck guard was added, so the
   per-file guard list and the "all 77 guards skip under the default build
   system" sentence are unchanged); record §27. The arithmetic sentence becomes
   **1602 = 1580 + 22**. Then re-take after the merge.
3. **The `List` paragraph** (lines 249–255) — rules only. Keep the four
   load-bearing requirements, divergence 14, "frame 0 builds every row", `TB-AH`
   and the `AXTable` sentence **exactly as they are**; append:
   > "Under the **proposal authority** a `List` lowers (stage 4, `LR-BQ`…`LR-CG`):
   > its rows are a `ListRows` group whose realized rows are consumed, planned
   > and wrapped by stage 2's item machinery and placed by a `WindowedRowsLayout`
   > at `(firstIndex + i) × rowHeight`; the layout answers `rowHeight ×
   > logicalCount` on the height (**not** SwiftUI's greedy answer, probe K6 —
   > a `List` is virtualized and its content height is the point) and the
   > proposal, or its widest realized row at a nil axis, on the width. There is
   > no site check and no `.list` site report left. On the **legacy** path the
   > leading spacer is now a bare node, not a `Box` element: it mints no `$anim`
   > entry, records no `elementBounds` row and no longer animates, which is one
   > fewer `StateTable` id per `List`. Everything else is unchanged and measured
   > so under both authorities — row identity, `@State` and focus retention and
   > their loss past the bound, the `AXTable` and its `AXIndex`es, the
   > unbounded-window and one-more-frame rules, `MP-I`'s cold frame, wheel
   > routing, hit testing and the disabled gate — and **divergences 13 and 14
   > survive**, their pins now running on both authorities."
4. **The layout-authority stage paragraphs** (after the stage-3 one at line 423):
   > "**Stage 4 lowers `List`** (`LR-BQ`…`LR-CG`). See the `List` paragraph
   > above for the behaviour. Two things a reader needs here: the exit criterion
   > is now **67 scenarios across ten files under both authorities**, and
   > `ScrollAuthorityCoverage` is **renamed `AuthorityCoverage`**, with
   > `everyScrollScenarioRanUnderBothLayoutAuthorities` renamed
   > `everyParameterisedScenarioRanUnderBothLayoutAuthorities` and moved to
   > `Tests/MetalUITests/ZZAuthorityRollCall.swift` so that it sorts after every
   > contributing file. A new parameterised scenario owes an
   > `AuthorityCoverage.record` call and a bump of the 67."
   And **correct line 443**: "`ScrollAuthorityCoverage.record` call and a bump
   of the 34" → "`AuthorityCoverage.record` call and a bump of the 67".
5. **CI — what lapses silently** (lines 678–682). Rewrite the first stage-3 row
   for the rename and the wider scope: the roll call now "reads coverage
   accumulated by **nine** other files"; `swift test --filter
   everyParameterisedScenario` hard-fails. Add one row: "**Three
   `AccessibilityDefaultsTests` scenarios call `AuthorityCoverage.record` after
   `try #require(MTLCreateSystemDefaultDevice())`**, so on a display-less runner
   they fail at the require *and* the roll call fails a second time naming them
   as having recorded no coverage — the second message points at the registry,
   not at the absent device." (If the Docs phase applies §11.3 item 11's
   reorder, drop this row instead of adding it.)
6. **Performance** bullet (the "Reference tables" list): `MP-I`'s 100 000-row
   cold frame re-measured on this machine at **12.24 s release legacy / 7.55 s
   release proposal**, and **37.16 s / 24.98 s debug**; CLAUDE.md's ~17 s is
   stale and is not a change this stage made. Also note the proposal path's cold
   frame is about a third faster than the legacy one at that size — measured,
   not a goal, and asserted by nothing.
7. **Human verification.** Add a row: "engine replacement stage 4 (plan task 7,
   `feat/engine-stage-4`): release-window capture of the default demo and the
   preview against `f2e981f` | **taken, 0 differing** — three times (lane 3 at
   `352f838`, and two verifiers at `9ad98db` and `a53daeb`), each with four
   a-vs-b stability zeros and a ~921 000-pixel default-vs-preview control, plus
   the twelve offscreen images at 0 at every lane and twice more in
   verification. **The demo's `List` is never windowed in any of them** (one
   cold frame, `firstIndex == 0`), so the windowing is pinned by tests, not by
   pixels. Nothing in production runs under the proposal authority, so no demo
   look is owed until stage 6b (record §27)". The three open looks listed in the
   "Human verification" bullet keep their text; stage 3's "the screen was locked
   at every lane" sentence is about stage 3 and stays.
8. **Lazy grids** (the `GR-L` sentence, around line 55): "proposed as stage G2
   after stage 4, which owns the windowing they need" → stage 4 **has landed**
   and the windowing exists (`WindowedRowsLayout`, `LR-BQ`); G2 is now unblocked
   rather than waiting.
9. **Practices.** Add: "**Record which SPELLING a mutation was applied to, not
   only which branch.** 'The records not consumed' and 'the records neither read
   nor consumed' redden the same seven tests with 12 and 46 issues; a later
   reader re-running the wording gets a different number with no way to tell
   which reading is the instrument (stage 4's M2f, and M2a's 30 vs 47)." And:
   "**A harness decision is a mutation site.** Stage 4 lane 3's host box — the
   largest decision in the lane — was pinned by none of the lane's three
   mutations, and the one the verifier took (drop its declared height) both
   reddened eleven scenarios and refuted the published reason for it."
10. **Nothing else in the rules changes.** The seven reserved slots, `Deferred`,
    `Component`, focus, text, the renderer, animation, environment and
    accessibility are untouched by this stage; the `List`-adjacent ones now run
    under both authorities.

**The plan's task 7 entry: do NOT tick it.** Append under the existing notes:

> *Progress 2026-09-23 on `feat/engine-stage-4` (`6a943e1..`record commit),
> stage 4 of 14, task still open.* Spec
> `specs/2026-09-23-engine-stage-4-design.md`; rulings `LR-BQ`…`LR-CG` in
> `../2026-09-17-engine-replacement-decisions.md` (the same doc as stages 1–3);
> no new probe — the SwiftUI answer is `swiftui-stack-algorithms.swift`'s K6,
> re-run and diffed byte-identical five times; record §27. **Stage 4 delivered**
> (five lanes, each with its own mutation table, all verified `ok`, fifteen
> minors all dispositioned): `List`'s explicit site check is **deleted** and its
> realized rows are placed by a `WindowedRowsLayout` at `(firstIndex + i) ×
> rowHeight`, each row consumed, planned and wrapped by stage 2's item
> machinery at `parentSite: .list`; the layout answers `rowHeight ×
> logicalCount` on the height rather than SwiftUI's greedy answer, with the
> reason ruled (`LR-BR`); on the legacy path the windowing spacer is demoted
> from a `Box` element to a bare node, which moves the resident-entry formula to
> `2n + 5` and divergence 18's to `2n + 6` (crossing at 126 rows, measured).
> **Everything that had to survive did, and is now measured under both
> authorities**: row identity, `@State` and focus retention across a bounded
> excursion and their loss past it, the `AXTable` records and their `AXIndex`es,
> the unbounded-window and one-more-frame rules, `MP-I`'s cold frame, wheel
> routing, hit testing and the disabled gate — **not one literal moved** in the
> eleven retention and accessibility scenarios. Divergences 13 and 14 **survive**
> and their pins now run on both authorities. **Exit criterion met**: 67
> scenarios across ten files under both authorities with a roll call that names
> any scenario that stops participating, `ListTests`' custom rows re-spelled
> through the legacy lowering (a bare native leaf drops the item plan —
> measured, M3b), and `aListsWorkIsTheSameFor100kRowsAsFor500` running at both
> authorities counting native work: 17 / 103 / 120 at 500 rows and at 100 000,
> derived by hand from the window before the run. Suite 1580 → **1602**, 97
> goldens unmoved, 77 guards (none added); twelve offscreen demo images 0
> differing at every lane and twice more in verification, on a harness that is
> **committed this stage** (`docs/probes/demo-pixels/`), and **three real-window
> captures at 0**. **Not done:** production still runs the legacy authority
> (stage 6b); `Deferred` as a presentation root (stage 5) and `display: none`
> keep one `List` scenario each on the legacy arm; the nil-width measurement path
> is `O(logicalCount)`; five small test-file obligations are listed in record
> §27 §11.3.

**README:**

- The count sentence (line 112) → "On `feat/engine-stage-4` (2026-09-23, plan
  task 7 stage 4) … **1602 tests**"; 97 goldens and 77 guards unchanged. Re-take
  after the merge.
- "Fifty-eight measured divergences" (line 260) stays **fifty-eight**: this
  stage retires none and adds none. 13 and 14 gain text, not numbers.
- In the record list, after `25-engine-replacement-stage-3.md` (line 315): "and
  [`27-engine-replacement-stage-4.md`](docs/record/27-engine-replacement-stage-4.md)
  for its fourth stage — the windowed proposal `List`".
- In the specs list (line 345), extend the engine-replacement entry: "stages 1,
  2, G, 3 and 4 of 14 landed; production still uses the CSS engine".

**Other owned documents:**

- `docs/record/README.md`: add `` | `27-engine-replacement-stage-4.md` | plan
  task 7 stage 4 on `feat/engine-stage-4`: `List`'s site check replaced by a
  windowed `ProposalLayout` placing realized rows at `(firstIndex + i) ×
  rowHeight`, the rows as a group with the spacer demoted to a bare node, and
  `ListTests`, `TombstoneTests`, `FocusTests`, `AXNodeTests` and the two
  accessibility suites running under both layout authorities (67 scenarios, ten
  files, the roll call renamed and moved to `ZZ…`); the 100 000-row exit test at
  both authorities with hand-derived work literals; five lanes, three of whose
  red-befores are child-process aborts, verifier verdicts (all `ok`, fifteen
  minors), mutation tables including the verifiers' seventeen, the `CN-R` pixel
  harness **committed at last** and three real-window captures at 0; counts
  1602 / 97 / 77 | ``.
- **`docs/record/04-divergences.md`** — **no number is retired and none is
  added; the table stays at 58.** Two rows gain text:
  - **13** (a `List`'s window is computed against a one-frame-stale viewport
    extent): append "**Survives stage 4 unchanged.** The windowed
    `ProposalLayout` reads the same `ScrollContext` at the same phase — the
    window is still decided in `requestLayout` against last frame's extent — so
    the one-frame resize error and its two rows of overscan are identical on
    both authorities. The contract pin
    (`scrollViewPublishesTheCurrentOffsetAndLastFramesViewportDuringRequestLayout`)
    is untouched and the *effect* is still reached by no test."
  - **14** (a `List` windows against its SCROLLER's origin, so a `List` with a
    flow sibling above it renders blank): append "**Survives stage 4 unchanged,
    and its pin now runs under both authorities.**
    `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows` is one of the
    20 `ListTests` scenarios lane 3 parameterised, so the wrong answer is
    asserted twice, once per engine — whoever fixes this must delete or invert
    **both arms**. `MP-L`'s blocker is unchanged: `requestLayout` still has no
    position, and the windowed layout does not give it one."
  - **18** (`@State` behind a removed `if` is retained): the **numbers move**.
    `2n + 7` → **`2n + 6`** on the committed `demoLikeRows(_:)` fixture, the
    crossing 125 → **126** rows, and 1007 → **1006** at 500 — because the
    windowing spacer is no longer an element and mints no `$anim` entry (record
    §27 §6.3, the whole before/after table at *n* = 40/124/125/126/127/500, with
    the before column reproducing the old figures exactly). The element-level
    consequence is still unpinned.
- **`docs/record/05-declared-but-inert.md`** — one row edited, one added, none
  deleted:
  - the test-observables row (`Frame.scrollRegions`, `StateTable.isDirty`,
    `LayoutTree.lastNativeLayoutWork`, `LayoutAuthority.allCases`): add
    `` `ListRows.GroupLayout.spacer` `` — stored on every frame of every legacy
    `List` and read by nothing; its own doc says so. Internal, so it is a note
    rather than a public-API row.
  - add: `` `UnlowerableField` site `.list` `` — **no site-level reporter left**
    after stage 4 deleted `List`'s check. The case survives for item fields, and
    `owningStage`'s `.list` comment says so; it is the same shape as stage 3's
    "site `component` has no reachable report".
  - **`LayoutAuthority.proposal` in production is still inert** — nothing sets
    it until stage 6b, so no row is deleted.
- The `SA-`, `FR-`, `CN-`, `GR-`, `AB-`, `TB-` decisions docs: **no change this
  stage.** `TB-AH`, `AB-L` and `AB-X` are unchanged in substance and are now
  measured on both authorities.
- This stage's own decisions doc: `LR-BQ`…`LR-CG` are appended; `LR-BQ`…`LR-BW`
  carry paragraphs headed **Amended, stage-4 critic round 1**, and `LR-CE` and
  `LR-CG` now carry **Amended, verification round** paragraphs. **`LR-CH` is the
  next id**, and the header's "next unused" line already says so — unmoved,
  because this round appended no ruling.
