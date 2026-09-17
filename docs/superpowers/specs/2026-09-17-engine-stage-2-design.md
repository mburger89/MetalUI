# Engine replacement, stage 2 — flex-item semantics onto SwiftUI's (design)

**Status, 2026-09-17 (PDT): designed, critic round 1 applied; lanes 1 and 2
implemented** (lane 1: `0e4a209` red, `ba908ad` implementation, corrections `LR-AW`
marked *lane 1*; lane 2: `27a9e23` red, `f25889a` implementation, `30737bd`,
corrections `LR-AX` marked *lane 2*; record §19).
Branch `feat/engine-stage-2` from `cb2e708`. Plan task 7, stage 2 of the fourteen
in [`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 (its row 2) and §8 (its stage-2 row). Rulings `LR-AB`…`LR-AV` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
(the same decisions doc as stage 1; critic round 1's dispositions are `LR-AP`).
Record: `docs/record/19-engine-replacement-stage-2.md`. Probe:
`docs/probes/swiftui-engine-replacement-stage2.swift` (groups F, X, P, J, R, C, V,
and revision 2's C2, X11–X18, F9–F10, P7–P9, Y; cited as *stage-2 probe*; stage
1's arms are *stage-1 probe*, the containers probe's are *stack-algorithms*).

**Scope, in one sentence.** Under the **proposal** layout authority only, every
flex-item field the stage-1 lowering reports and the whole demo still carries
lowers onto kernel nodes — by the SwiftUI spelling a SwiftUI author would write,
with each place that spelling answers differently from CSS pinned against a
probe arm — or keeps reporting by name with a named later owner; and the two
proposal-path answers the row names (`SA-N` item 4, the below-word text answer)
move to SwiftUI's. Production still runs the legacy authority (until stage 6b),
so the eight legacy demo images stay 0 px; the preview may move only where those
two probe-backed kernel-path changes move it, and each lane expects 0.

**Five lanes** (the brief's cap, `LR-AO` as amended): 1 item records, the bounds
alias and the cross axis; 2 the main axis and the exit test; 3 the two
production proposal-path answers (`SA-N` item 4; the below-word clamp), one
commit each; 4 the box model; 5 justify distribution and reverse. `hidden()` is
deferred with constraints for its owner (`LR-AV`); everything else deferred is in
§9.

## Contents

1. [Baseline](#1-baseline)
2. [Evidence gathered for this design](#2-evidence-gathered-for-this-design)
3. [The mechanism: item records and a bounds alias (`LR-AB`)](#3-the-mechanism-item-records-and-a-bounds-alias-lr-ab)
4. [The lowering table after stage 2](#4-the-lowering-table-after-stage-2)
5. [API and files](#5-api-and-files)
6. [Lanes](#6-lanes)
7. [The exit test (`LR-AN`)](#7-the-exit-test-lr-an)
8. [Demo, pixels and captures](#8-demo-pixels-and-captures)
9. [Deferred, each with an owner](#9-deferred-each-with-an-owner)

---

## 1. Baseline

At `cb2e708`, measured 2026-09-17 in `/Users/maxburger/Developer/MetalUI-engine-stage-2`:

| measure | value | how |
|---|---|---|
| suite | **1409 tests**, passed after 42.660 s; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel --skip-build` |
| goldens | **97** | `find Tests -name "*.json" \| wc -l` |
| guards | 71 (stage 1's figure, not re-taken: this design adds none) | record §18 |
| screen | locked at 07:1x and again at 07:49 PDT: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` | `docs/probes/appkit-screen-lock-state.swift` |

## 2. Evidence gathered for this design

**Probe** (`swiftui-engine-replacement-stage2.swift`; revision 1 157 lines,
revision 2 235 lines with the first 157 unchanged; each revision run twice,
byte-identical; the reading is in its header). The arms this design rests on:

| arm | SwiftUI answer | CSS answer for the legacy spelling |
|---|---|---|
| F1 | greedy frame beside a rigid 40 at 300: 260 | `flexGrow` 1: 260 (agrees) |
| F2 | two greedy frames over 100 and 20 at 300: **150 / 150** | `flex-basis: auto`: 190 / 110; `flex-basis: 0`: 150 / 150 |
| F3 | over 200 and 20: 200 / 100 (never below its child) | zero basis, automatic minimum: 200 / 100 (agrees) |
| F4, F8 | a declared minimum lets a greedy frame answer below its child (150 over 200) | `min-width: 0` does the same |
| F5 | a rigid 196 beside a greedy text frame at 400 keeps 196 | CSS shrinks the 196 (`SZ-L`, divergence 55) |
| F7 | `.fixedSize()` text overflows (302) | `flex-shrink: 0` overflows |
| F9 | greedy frame over "alphabravocharlie" at a 50 share: 50, the text broken inside its word | zero basis: the word's min-content |
| F10 | greedy frame over a rigid 200 stack at a 75 share: 200, the row overflows | automatic minimum 200 (agrees) |
| X1, X2 | greedy cross frame: the stack's own cross size (40) or the concrete one (100) | `stretch`: the line's cross size (agrees) |
| X4 | a greedy view inside a **hugging** container fills that container's proposal (200) | CSS fit-content: 30 |
| X5 / X7 | `.frame(maxWidth: .infinity, alignment: .leading)`: exact in a definite column; fills an indefinite one (300 against 100) | `alignSelf: flex-start`: the column hugs (100) |
| X8, X9 | a nil-axis `.frame(width: 30)` is not stretched; an outer greedy frame is | a flex item with an auto cross size is stretched (`MC-Q` finding 7) |
| X10 | `.frame(maxHeight: 25)` in 100: 25 | stretched, then clamped: 25 |
| X12 (X11) | a greedy frame inside `.padding(8)` makes the padding fill the leftover: 160 (46) | a hugging padding layer: 46 |
| X14 (X13) | a trailing alignment frame inside a padding makes an indefinite `VStack` fill: 300 (100), b at 272 | the padding layer hugs; `alignSelf` inert |
| X16 (X15) | a greedy child makes a hugging `ZStack` fill: 200 (30) | fit-content: 30 |
| X18 (X17) | a grower on a `VStack`'s main axis fills a concrete proposal: 200 tall (30) | fit-content column: 30 |
| P1 | padding 12 inside a fixed 10×10 `.topLeading` frame: the frame stays 10×10, child at (12, 12) | border-box floor (`BM-4`): 34×34 |
| P7, P8, P9 | the same under `.leading`: child (12, 0); `.top`: (0, 12); centre: (0, 0) | 34×34 |
| P3, P4 | padding outside a background is a margin; negative padding overlaps and clamps at 0 per axis | `margin` (agrees until the clamp) |
| P6 | `Text("alpha").padding(10)`: 53×36, text at (10, 10) | Style padding on a content-sized leaf is inert (33×16) |
| J1–J9 | spacers are `space-between` (min = gap), `space-evenly` / `space-around` (spacers at the ends, two between, a rigid gap leaf); overflowing, spacers pack from the start | `space-evenly`/`space-around` overflow falls back to `center` |
| R1, R2 | reversed children in a trailing frame are `row-reverse`, overflow included | agrees |
| C1, C2 | `containerRelativeFrame` is relative to the window (500), not the 200 parent; a `GeometryReader` child at `0.5 ×` its width is 100 (the reader takes 200) | percentages resolve against the parent |
| Y0–Y9 | a `Text` breaks where CoreText's line-break loop breaks, inside a word that does not fit; width `min(proposal, ceil(widest line with its trailing space))` | the legacy leaf floors at the longest word |
| V1, V3 | `.hidden()` paints nothing and takes no tap | legacy `hidden()` is `display: none` (deferred, `LR-AV`) |

Stage-1 probe arms also cited: H1, S1–S3, G1/G2, T3/T4, W2. **Re-run this round**
(record §19): stack-algorithms (787 lines, identical to its record — A5, G1, G9,
G4r, S), accessibility-bridge-rules (62 lines, identical — R9), frame-semantics
(291 lines; D4 identical; its G1 child-proposal *sequence* differs on this OS,
sizes and rects identical).

**Prototype P3** (scratch, restored; `p3.patch` in the session scratchpad). Lanes
1–2's mechanism: item records, the bounds alias, stretch (with and without the
single-child elision), `alignSelf`, `flexGrow`, `flexShrink: 0`, `minSize` /
`maxSize` on the item wrapper, those fields' diagnostics removed.

| run | measured |
|---|---|
| whole demo, 920×560 in the harness root, modal off | **report `[list.noLowering, scrollView.noLowering]`**; 2036 ids, 6 agreeing, 30 disagreeing, 2000 legacy-only (the `List`'s rows), 0 lowered-only |
| the same, modal on | report `[stack.position, stack.inset, list.noLowering, scrollView.noLowering]`; 2042 ids, 6 agreeing, 36 disagreeing |
| full suite, **no** single-child elision | 1410 (1409 + the scratch test), 8 tests red: the five diagnostics pins below plus `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (5 issues), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (9), `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (4) |
| full suite, **with** the elision (`LR-AC`) | 1410, **5 red, all diagnostics pins**: `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (6 issues), `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (14), `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (3), `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (1), `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1) |

**Scratch R2** (critic round 1: P3 **plus** `SA-N` item 4, restored, `swift
package clean` after). The demo census is identical to P3's in both modal states,
every rect pair included. Four critic shapes, legacy → lowered, report empty in
each: S1 an unsized `space-between` row grown by its parent (b 240 → 20); S2
`x.flexGrow(1).padding(8)` in a hugging parent (padding 46 → 160); S3
`x.alignSelf(.flexEnd).padding(8)` in a column (padding 26 → 90 tall); S4
`maxHeight(25)` in a centring `Row` (legacy 20×0 at y 50; P3, which put every
maximum on W, 20×25).

**Scratch `SIGTRAP`**: `SA-N` item 4 alone makes
`negativePaddingIsAcceptedAndItsResponseClampsPerAxis` exit on `SIGTRAP`; setting
its pinned-wrong precondition to SwiftUI's 20×20 makes it pass (`LR-AU`).

**Scratch text**: `proposalTextMeasurement` at probe Y's widths breaks the same
number of lines in every arm and answers the widest line with its hung space,
unclamped (7.86 at 5, 33.31 at 30, 11.18 at 0) (`LR-AU`).

## 3. The mechanism: item records and a bounds alias (`LR-AB`)

A flex-item field (`flexGrow`, `alignSelf`, …) means something only in its
**parent's** axis, and the legacy registration order is post-order: a child
registers before its parent exists. Three shapes were weighed (`LR-AB`); the
chosen one touches no group entry, no proposal element and no kernel case:

1. **The child records, the parent decides.** Every lowered legacy element
   records a `LoweredItem` for the node it returns — its declared and animated
   `Style`, its site, the alignment of its own content, its kind (leaf, flex
   container, stack, frame layer) and `consumed = false` — in
   `Frame.lowering` (`LR-AT`), and reports no item field itself.
2. **A lowered container wraps its children** before registering its stack or
   overlay (`lowerLegacyItems`), and marks each record it receives consumed. For
   each child node with a record, by the container's axis and its own
   `alignItems`/`justifyItems`, it registers at most **four** nodes around the
   child, innermost first:
   - `fixedSize` on the main axis — `flexShrink: 0` (lane 2);
   - the **item frame** W — greedy on the main axis for `flexGrow > 0`, greedy
     on the cross axis for stretch, carrying the item's `minSize`/`maxSize`
     (*lane 1*: a minimum of 0 on a stretched axis when none is declared, stage-2
     probe Z1, `LR-AW`), aligned by the child's own content alignment;
   - the **alignment frame** — greedy on the cross axis, aligned by a
     non-stretch `alignSelf` (lane 1);
   - native **padding** for `margin` (lane 4), outermost.
   Which wrappers exist and where they are greedy reads the **declared** style;
   their minima, maxima and insets read the **animated** style (`LR-AS`).
3. **The item frame is the element's rect.** In CSS a grown or stretched box
   *is* bigger — its background, hitbox, accessibility frame and text wrap width
   are the grown ones. So when W is registered the container records an alias
   `child → W`, and `Frame.bounds(of:)` and `PaintPass.measuredWidth(of:)`
   resolve it. The alignment frame and the margin padding are **not** aliased:
   they are outside the box, as in CSS.
4. **The parent re-checks the free space it creates** (`LR-AR`): a child flex
   container with `space-*` and no declared main size that W makes greedy on its
   own main axis reports. A declared `flexGrow` or `alignSelf` inside a one-child
   container is lowered (its fill pinned); only stretch keeps the single-child
   elision.
5. **Nothing is dropped silently** (`LR-AQ`). A record no lowered container
   consumes — the root, a child of any proposal container — reports each
   non-default item field as `<site>.<field>.unconsumed` when the root's
   registration returns. A site that reports `noLowering` marks its records
   consumed. At the root, `flexGrow`/`flexShrink`/`flexBasis`/`alignSelf` lower
   as absent only where lane 1's differential arm shows the legacy root ignores
   them.

**Depth** (`LR-AB` as amended). Four wrappers per item count against
`NativeLayoutRun.maxDepth` (88); lane 2 pins the limit with three per level, lane
4 with four, and lane 2 records the demo's deepest native run.

## 4. The lowering table after stage 2

Stage 1's §5.4 table stands except where this one amends it. "Report" names the
field string in `UnlowerableField`.

### 4.1 Item fields (consumed by the parent; lanes 1–2)

| field | flex parent (`Box`/`Row`/`Column`, a `.padding` layer) | stack parent (`Stack`; a one-node frame layer is a stack, `CN-N`) | evidence |
|---|---|---|---|
| stretch (`alignItems` `nil`/`.stretch` on the parent — `Box` by default, `Row`/`Column` only when declared, EP-8 — `alignSelf` `nil`/`.stretch` on the child), child's cross `size` `auto` | W greedy on the cross axis, aliased — **except** when the parent has exactly one child and no declared cross size (`LR-AC`) | the same per axis (`alignItems` vertical, `justifyItems` horizontal) | X1, X2, X9; divergences X4, X16 |
| a frame layer child with a nil axis (`MC-Q` finding 7) | stretched on that axis like any auto item | the same | X8, X9 |
| `alignSelf` `.flexStart`/`.center`/`.flexEnd` differing from the parent's | alignment frame, greedy on the cross axis, not aliased — in a one-child container too (`LR-AR`) | ignored (the legacy stack ignores it) | X5; divergences X7, X14 |
| `alignSelf` `.baseline` | report `alignSelf.baseline` (task 11) | ignored | — |
| `flexGrow > 0`, all growing siblings' **declared** factors equal | W greedy on the main axis, aliased — in a one-child container too (`LR-AR`) | ignored | F1; divergences F2, X12, X18 |
| `flexGrow > 0` with unequal declared positive values among siblings | report `flexGrow.weights` **on the parent's site** | ignored | none exists (deleted concept, stage 10) |
| a child flex container with `justifyContent` `space-*`, no declared main size, made greedy on its own main axis by W — *lane 2:* or floored there by W's declared minimum (`LR-AX` item 4) | report `<child>.justifyContent.<case>` at the child's position (`LR-AR`) | the same (stretch, minimum) | S1 |
| `flexBasis` `.auto`, or `0` (any unit) **with** `flexGrow > 0` and no declared main size | nothing: W's main minimum comes only from `minSize` (`LR-AE` as amended); never below its child (F3, F10); a `Text` grower breaks inside its word (F9, divergence) | ignored | F3, F9, F10 |
| `flexBasis` `0` with `flexGrow > 0`, a declared main size and a declared `minSize` | W's minimum = that minimum; the declared size stays on the element's own frame, so a sized **container** lays its content out at the declared size inside a smaller item rect — divergence, F4 | ignored | F4, F8 |
| `flexBasis` `0` with `flexGrow > 0`, a declared main size and no `minSize` | report `flexBasis` (CSS's floor is min(size, content)) | ignored | `LR-AE` |
| `flexBasis` `0` without `flexGrow`, any other length, or a fraction | report `flexBasis` | ignored | stage 8 / 10 |
| `flexShrink == 0`, main `size` `auto` | `fixedSize` on the main axis | ignored | F7 |
| `flexShrink > 0`, any value | nothing: SwiftUI's compression order (divergence 55, `LR-AF`) | ignored | F5, stack-algorithms G9, G1 |
| `flexGrow < 0` or `flexShrink < 0` (*lane 2*) | report `flexGrow` / `flexShrink` (`LR-AX` item 5) | ignored | — (CSS rejects both) |
| `minSize` px/rem on an axis whose `size` is `auto` | W's minimum on that axis, aliased (presence semantics) | the same | F4, F8 |
| `maxSize` px/rem on a greedy axis (grown or stretched) | W's maximum on that axis | the same | X10 |
| `minSize`/`maxSize` on an axis with a declared `size` | folded at registration into the element's own fixed frame: `clamp(size, min, max)` | the same | — (static) |
| `maxSize` on a non-greedy `auto` axis (a centring `Row`'s cross axis included) | report `maxSize` (stage 8) | the same | X10's greediness; S4 |
| `minSize`/`maxSize` a fraction | report `minSize.percent`/`maxSize.percent` (stage 8) | the same | C1, C2 |
| `margin` px/rem, any sign (lane 4) | padding outside the alignment frame, not aliased | the same | P3, P4; divergence past the clamp |
| `margin` `.auto` | nothing — the legacy engine resolves it to 0 (inert table) | nothing | — |
| `margin` a fraction | report `margin.percent` (stage 8) | the same | C1, C2 |
| any item field on a record **no lowered container consumes** | report `<site>.<field>.unconsumed` (`LR-AQ`) | — | finding 1 |

A **frame layer** as an item: its kernel frame already carries its own
`FrameSpec` bounds, so W carries `minSize`/`maxSize` only on a greedy axis (the
stretched axis), where CSS stretches and then clamps.

### 4.2 Container and node fields (lanes 3–5)

| field | lowering | otherwise | lane |
|---|---|---|---|
| `flexDirection` `.rowReverse`/`.columnReverse` | the children's **nodes** in reverse order (identity, paint and hit order untouched), `justifyContent`'s main factor mirrored (flex-start → trailing) | — | 5 |
| `justifyContent` `.spaceBetween`, declared main size | `Spacer(minLength: main gap)` between children, stack spacing 0 | unsized: flex-start (stage 1), reported if grown (§4.1) | 5 |
| `justifyContent` `.spaceAround` / `.spaceEvenly`, declared main size | `Spacer(minLength: 0)` at both ends (evenly) or both ends and doubled between (around); a non-zero main gap as a rigid native leaf of that length beside the between-spacer | the same | 5 |
| `Style.border` px/rem | added to the native padding's insets (inside the declared size) | a fraction → `border.percent` (stage 8) | 4 |
| `Style.padding` on a `Text` | native padding around the text leaf; glyphs painted at the **leaf's** origin and wrapped at the **leaf's** measured width | — | 4 |
| declared size below the padding (+ border) sum | the fixed frame wins and the padding overflows by the container's content alignment (P1 `Box`, P7 `Row`, P8 `Column`) | — | 4 |
| a native padding's child placement (`SA-N` item 4) | the child at origin + leading/top inset at **its own measured size** | — | 3 |
| a concrete width below a text's widest broken line | `min(proposal, widest line)` (Y5, Y8, T3/T4) | — | 3 |
| `display: .none` (`hidden()`) | — | `display.none` stays reported (`LR-AV`) | deferred |
| `size`/`padding`/`gap` a fraction | — | `size.percent`, `padding.percent`, `gap.percent` stay (stage 8) | — |
| `alignItems` `.baseline`, `flexWrap`, `alignContent`, `position`, `inset` | — | unchanged (task 11; deleted concept; stage 5) | — |

**Order of a report** (`LR-Y`, amended): a leaf reports its every-node rows; a
container its container rows then its every-node rows; a container **then**
reports each child's item fields it cannot lower (`flexGrow.weights` once, at the
container's site; a child's `flexBasis`/`maxSize`/`…percent`/`justifyContent`
re-check at the child's site), in child order; after the root returns, the
`…unconsumed` rows in registration order. Production traps on the first.

## 5. API and files

All `internal`; `@testable` tests reach them.

```swift
// Sources/MetalUI/LoweringState.swift (new, lane 1; LR-AT)
struct LoweredItem {
    enum Kind { case leaf, flex(isRow: Bool), stack, frameLayer }
    var declared: Style          // structure: which wrappers, greed, weights, reports (LR-AS)
    var animated: Style          // values: W's min/max, margin insets (LR-H, LR-AS)
    var site: LoweringSite
    var contentAlignment: ProposalAlignment   // where the element's content sits when its box grows
    var kind: Kind
    var consumed = false         // LR-AQ
}
struct LoweringState {
    var items: [LayoutNodeID: LoweredItem] = [:]      // empty under the legacy authority
    var order: [LayoutNodeID] = []                     // registration order, for LR-AQ's report
    private(set) var aliases: [LayoutNodeID: LayoutNodeID] = [:]
    mutating func alias(_ element: LayoutNodeID, to itemFrame: LayoutNodeID)
    func alias(_ node: LayoutNodeID) -> LayoutNodeID  // the item frame, or the node itself
    var textLeaves: [LayoutNodeID: LayoutNodeID] = [:] // lane 4: a padded lowered Text's element node → its leaf
}

// Frame (lane 1: ONE appended line; `swift package clean`)
var lowering = LoweringState()
func bounds(of node: LayoutNodeID) -> Bounds<Pixels>      // tree.layout(lowering.alias(node)) — one expression

// PaintPass (Passes.swift:607, lane 1)
public func measuredWidth(of node: LayoutNodeID) -> Double // frame.tree.measuredWidth(frame.lowering.alias(node))

// Sources/MetalUI/LegacyLowering.swift (lanes 1, 2, 4, 5)
extension LayoutPass {
    /// Records `node` as a lowered item and returns it (lanes 1–2).
    func recordLoweredItem(_ node: LayoutNodeID, animated: Style, declared: Style,
                           site: LoweringSite, contentAlignment: ProposalAlignment,
                           kind: LoweredItem.Kind) -> LayoutNodeID
    /// A container's children, each marked consumed and wrapped per §4.1 for this
    /// parent; appends the parent-level and child-level item reports to `fields`.
    func lowerLegacyItems(_ children: [LayoutNodeID], parent declared: Style,
                          parentSite: LoweringSite, fields: inout [UnlowerableField]) -> [LayoutNodeID]
    /// The main-axis arrangement: reverse order and justify distribution (lane 5).
    func arrangeLegacyMainAxis(_ items: [LayoutNodeID], _ style: Style) -> (nodes: [LayoutNodeID], mainFactor: Double)
}
// Frame.render (lane 1): after the root registers, `lowering`'s unconsumed rows
// join `unlowerableFields` (LR-AQ); the `ScrollView`/`List` site checks mark the
// records they receive.

// LayoutTree.swift (lane 3, commit 1): `placeNative`'s `.padding` case places the
// child at (origin + leading/top inset) at the child's measured size (SA-N item 4).
// ProposalText.swift (lane 3, commit 2): `proposalTextMeasurement` answers
// min(proposal.width, widestLine) for a concrete width.
```

**Shared files touched** (the other track merges them; every edit appended or one
expression, `LR-AT`): `Frame.swift` (one stored line; one expression in
`bounds(of:)`; the unconsumed rows in `render`), `Passes.swift` (one expression),
`LegacyLowering.swift` (the lowering), `LayoutTree.swift` (lane 3's `.padding`
case only, its own commit, named in the record for the other track's padding
tests), `Text.swift` (lane 4: the padded leaf, its glyph origin and wrap width).
**Not touched**: `ElementGroup.swift`, `ModifiedElement.swift` (with `hidden()`
deferred), `NativeElements.swift`, `Box.swift`.

**New test files**: `Tests/MetalUITests/LoweringItemTests.swift` (lanes 1–2),
`LoweringBoxModelTests.swift` (lane 4), `LoweringDistributionTests.swift`
(lane 5). Lane 3's tests go in `Tests/MetalUILayoutTests/NativeValidationAcceptanceTests.swift`
(kernel) and `Tests/MetalUITests/LoweringLeafTests.swift` (text).

**No new typecheck guard** is planned: every addition is internal and no public
spelling changes. A lane that adds one mutates it red once.

## 6. Lanes

Each lane's tests are written first and read red — "red before" for a lowering
test means **a diagnostic in the report or a literal mismatch in a test that
compiles against stage-1 API**, so no red run truncates the suite — except tests
marked **characterization** (green on arrival; their mutation is their evidence)
and **divergence pins** (a `try #require` that the two authorities disagree, with
both sides' rects literal or derived, and a mutation toward the CSS answer that
reddens them). Every mutation: commit first, `cp` the file aside, apply, native
build, full unfiltered `swift test --build-system native --no-parallel`, restore
from the copy, `git status --short` empty; the lane's record names **every** test
it reddens. Every lane ends with the full suite (its count read from the summary
line), the goldens count (97, `git diff --name-only cb2e708 -- '*.json'` empty),
the twelve `CN-R` images (§8) and the lock probe (§8).

"Agrees" means `LayoutDifferential.compare` reports an empty `unlowerable`,
`disagreeing` empty, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual` and
`stateSlotsEqual` true, with `try #require(report.elements == N)` for an N
derived by hand. Where a text decides a rect, the expectation comes from the
shaping cache, not a literal (`LR-F`). **Every stretch arm declares
`.alignItems(.stretch)` or uses a `Box`**: `Row` and `Column` centre by default
(`Flex.swift:55`, `:111`).

### Lane 1 — item records, the bounds alias, the cross axis; unconsumed records

Files: `LoweringState.swift` (new), `LegacyLowering.swift`, `Frame.swift` (one
line and one expression), `Passes.swift` (one expression); tests
`LoweringItemTests.swift` (new) and the amended pins below. `swift package clean`.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aStretchedChildFillsTheLineOnItsCrossAxis` — parents `Row{…}.alignItems(.stretch)`, `Column{…}.alignItems(.stretch)` and a `Box` (its default) × {*lane 1:* stretched to 60 by a sized two-child grandparent — an unsized parent whose line is its tallest sibling is offered the harness root's size and fills it, cause R (`LR-AW`); sized, 70 (X2)} × stretched child {childless `Box` with a main size; `Text`; a `Row` with `justifyContent(.center)`}; every arm has ≥ 2 children; agrees | `box.alignItems.stretch` | **M1a** W registered but not aliased; **M1b** W greedy on the main axis instead of the cross |
| 1.2 | `aStretchedContainersContentSitsByItsOwnAlignment` — a stretched `Column` child with `alignItems` {start, centre, end} and a stretched `Row` child with `justifyContent` {start, centre, end}, fixed grandchildren at distinct sizes (practices shape 1), parents declaring `.alignItems(.stretch)`; agrees | reported | **M1c** W aligned `.topLeading` always |
| 1.3 | **divergence pin** `aStretchedSingleChildContainerDoesNotStretchItsChild` — `Column { Box { Box().height(10) }.flexDirection(.column); Box().width(80).height(10) }.alignItems(.stretch).width(200)` (*lane 1*: the middle `Box` a column, or its child's width is its main axis and 0 on both sides, `LR-AW`): the middle `Box` is 200 wide on both sides; its child 200 legacy, 0 lowered (X9); plus the agreeing control `Box { Text("x") }` alone | reported | **M1d** the elision removed — reddens 1.3, and (P3) `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` |
| 1.4 | `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` — `Row { Box().width(20).maxHeight(25); Box().width(20).minHeight(60); Box().width(20).height(10) }.alignItems(.stretch).height(100)`: 25, **100** (*lane 1*: CSS clamps the stretched 100 by the 60 minimum to 100) and 10, at the top; and the same row stretched to 40 by a sized grandparent: 25, 60, 10, the row 40 over 60-tall content (`LR-AW` item 1); agrees | reported (`minSize`/`maxSize`) | **M1e** W drops `maxSize` on the greedy axis; **M1r** (*lane 1*) W's minimum left absent |
| 1.5 | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` — a 300-wide `Column` (its centring default) over three fixed children, one each with `alignSelf` `.flexStart`, `.flexEnd`, `.stretch` (X5); agrees | `box.alignSelf` | **M1f** the alignment frame's factor always 0 |
| 1.6 | **divergence pin** `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs` — `Row { Column { a100; b20.alignSelf(.flexStart) } }` at 300: legacy column 100, lowered 300 (X7, X6) | reported | **M1g** the alignment frame not greedy |
| 1.7 | **divergence pin** `aStretchedItemInsideAHuggingItemFillsItsProposal` — `Row { Column { Box().width(30).height(10); Box().height(10) }.alignItems(.stretch) }` at 200: legacy column 30, lowered 200 (X4, X3) | reported | **M1h** stretch made to fill only a parent with a declared cross size |
| 1.8 | `aNilAxisFrameLayerUnderAStretchingContainerIsStretched` (`MC-Q` finding 7) — `Box { a.frame(width: 30); b20x40 }.height(40)` and the column transpose (*lane 1*: the `Box` declares its cross size): the layer 30×40, its child centred (X9); a frame declaring both axes is not stretched; agrees | reported | **M1i** frame-layer records skipped |
| 1.9 | `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields` — a sized `Stack` with nil `justifyItems`/`alignItems` over two auto children, and a `.center` `Stack` whose child declares `flexGrow`, `flexShrink(0)`, `alignSelf(.flexEnd)` (ignored, as legacy, and **consumed**, so not `…unconsumed`); agrees; stage 1's 4.1 stretch arms move here. **Divergence arm** (X16): `Row { Stack { Box().width(30).height(10); Box().height(10) } }` at 200, the `Stack`'s items `nil` (*lane 1*: `Stack(alignment:)` never stretches): legacy `Stack` 30 wide, lowered 200 | `stack.alignItems.stretch` | **M1j** the overlay consumes `alignSelf`; **M1j′** a stack parent's stretch not greedy (the X16 arm) |
| 1.10 | `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` — a stretched clickable, labelled, backgrounded `Box` and a stretched multi-line `Text` in a sized `Column{…}.alignItems(.stretch)`; agrees in every observation (glyph scene included) | reported | **M1a**; **M1k** the alias resolved in `bounds(of:)` but not `PaintPass.measuredWidth(of:)` |
| 1.11 | `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork` (`SA-M`) — `Column { Row { a; b }; Row { c; d }; Box { e } }.alignItems(.stretch)` with fixed-height auto-width leaves in a 200×100 root; `Box { e }` is a one-child container with no declared cross size, so its stretch is elided. Node count, calls, hits and misses **derived by hand in the doc comment before the first run** | written against stage-1 API only (`LayoutDifferential`, `LayoutTree.lastNativeLayoutWork`), so it compiles: the report carries `box.alignItems.stretch` and the node-count literal mismatches | **M1l** W registered also for an elided single child (the node count moves by 1) |
| 1.12 | `theCentringDefaultOfRowAndColumnStretchesNothing` — `Row { Box().width(20); Box().width(20).height(40) }.height(100)` and the `Column` transpose, no `alignItems`: the auto child 0 tall, centred, no W registered (node count by hand); agrees. Arm: `Box().width(20).maxHeight(25)` in that `Row` reports `box.maxSize` (S4) | characterization for the agreeing arm (green on arrival); the report arm: `box.maxSize` already reported | **M1o** stretch applied for `.center` (the child fills 100; node count moves) |
| 1.13 | `anItemFieldNoLoweredContainerConsumesIsReportedByName` (`LR-AQ`) — `Box().width(20).height(10).flexGrow(1)` under `HStack`, `VStack`, `ZStack`, `ProposalFrame`, `.padding` `ModifiedContent`, the `.overlay` primary and overlay slots, `ProposalLayoutContainer` and `ProposalScrollView`: each reports exactly `box.flexGrow.unconsumed`; one arm each for `minWidth`, `maxWidth`, `alignSelf`, `flexShrink(0)`, `flexBasis(0)` under `HStack`; root arms `.maxWidth(600)` and `.minWidth(50)` report; root `.flexGrow(1)`/`.flexShrink(0)`/`.flexBasis(0)`/`.alignSelf(.flexEnd)`: each arm first compares the two authorities with the field and without it, and asserts agreement **or** the report, whichever that comparison licenses (recorded); a legacy `ScrollView` over the same child reports only `scrollView.noLowering`; control `Row { same }` reports nothing. `try #require` on the arm count | proposal-container arms: stage 1 reports `box.flexGrow` (no `.unconsumed`); literal mismatch | **M1m** the unconsumed check removed; **M1m′** the `noLowering` sites do not mark (the `ScrollView` arm) |
| 1.14 | `aStretchedUnsizedSpaceDistributionContainerIsReported` (`LR-AR`) — `Column { Row { a20; b20 }.justifyContent(.spaceBetween); c200 }.alignItems(.stretch).width(200)` (*lane 1*: the column declares its width) reports `box.justifyContent.spaceBetween` at the inner `Row`'s site, and `spaceAround`/`spaceEvenly` likewise; controls `.center` and `.flexEnd` agree (b at the line's centre / end) | stage 1's report is empty for the unsized row; literal mismatch | **M1p** the re-check removed (report empty; the S1-shaped disagreement shows) |
| 1.15 | **divergence pin** `anAlignSelfInsideAOneChildWrapperFillsTheWrapperWhereCSSIgnoresIt` (`LR-AR`, S3) — `Column { Box().width(100).height(10); Box().width(20).height(10).alignSelf(.flexEnd).padding(8) }` in a 300×100 root: legacy padding layer 36×26 at (32, 10), child at (40, 18); lowered (scratch R2) 36×90, child at (40, 82); X14 is SwiftUI's transposed spelling | reported | **M1q** `alignSelf` elided in a one-child container (lowered = legacy) |

**Amended pins** (each amendment recorded with the red run it answers; *lane 1*:
the unconsumed check moves every item field under the harness root to
`…unconsumed`, so `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`
and `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
were re-spelled here rather than in lane 2, `CounterPanel()` sits in a 400-wide
`Column`, the census became an ordered literal, and stage 1's M3f and M5c are
retired — `LR-AW` items 3 and 7; the lane also runs **M1t**, the parent's
`flexGrow` report dropped, and **M1u**, the root not exempt):
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (arms that declared
stretch/`alignSelf` to produce a report re-declare a field still reported, e.g.
`size.percent`); `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(`alignSelf` → `alignSelf.baseline`; the count literal re-derived);
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (the
two-child and sized single-child stretch arms now agree; renamed only if its
subject changes — the lane decides and records); `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`
(its stretch arms move to 1.9); `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
(the stretch and `alignSelf` entries leave its literal). Stage 1's **5.4–5.6**
(`aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`,
`aLoweredWindowPublishesTheSameAccessibilityTree`,
`aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`) replace the
test-only `LowerableCounter` with the demo's `CounterPanel()` (`LR-AA` item 2; its
chrome's `alignSelf` lowers here), and stage 1's 5.5 gains `try #require(pair.report().elements
== N)`. Their `CounterPanel`-specific mutation is **M1n**, the alignment frame
aliased (the chrome's hitbox and accessibility frame widen to the column): the
lane records which of stage 1's 5.4–5.6 it reddens; 5.6's state-slot half is id-keyed and
cannot see a rect, so if M1n leaves 5.6 green its width half is checked with a
mutation that moves the chrome's width and the result recorded — a 5.x no
`CounterPanel`-specific mutation reddens is a finding. Stage 1's M5d is re-run as before.

**Demo expectation**: legacy images 0 px; preview images 0 px (nothing in lane
1 reaches a proposal root).

### Lane 2 — the main axis; animated fields; depth; the exit test

Files: `LegacyLowering.swift`; tests `LoweringItemTests.swift`; the exit test
rewritten in `LoweringCorpusTests.swift`; depth pins beside stage 1's.

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aGrowingChildTakesTheRemainingMainSpace` — `Row`/`Column` × grower {childless `Box`; `Text`; a `Row` with `justifyContent(.flexEnd)`} beside a rigid sibling (F1), with and without `gap`; agrees | `box.flexGrow` | **M2a** W greedy on the cross axis instead |
| 2.2 | **divergence pin** `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` — `Row { Box().width(100).height(10).flexGrow(1); Box().width(20).height(10).flexGrow(1) }.width(300)`: legacy 190/110, lowered 150/150 (F2); widths 200 and 20: legacy 240/60, lowered 200/100 (F3); and the `.flexBasis(0).minWidth(0)` arms of both, which **agree** at 150/150 (F4/F8) | reported | **M2b** W given a main minimum of 0 without a declared minimum (the 200/20 arm reads 150/150) |
| 2.3 | `unequalGrowWeightsAreReportedOnTheParent` — `Row { a.flexGrow(1); b.flexGrow(2) }` reports `box.flexGrow.weights` once; `(2, 2)` and `(0.5, 0.5)` lower and agree | reported per child | **M2c** the weights check removed |
| 2.4 | `aZeroBasisGrowerTakesItsShareDownToItsContent` (`LR-AE` as amended) — at 300: `Row { a40; b40 }.flexGrow(1).flexBasis(0)` beside `Box().height(10).flexGrow(1).flexBasis(0)` (150/150) agrees; at 150, `Row { a100; c100 }` as the first grower (F10: 200, overflowing) agrees. **Divergence arm** (F9): `Text("alphabravocharlie").flexGrow(1).flexBasis(0)` beside a zero-basis `Box` at 100: lowered item 50 (the text broken inside its word, its height from the shaping cache), legacy the word's min-content. **Report arms**: `Box().width(200).flexGrow(1).flexBasis(0)` reports `box.flexBasis`; `flexBasis(0)` without grow, `flexBasis(40)`, `flexBasis(fraction: 0.5)` each report. **Divergence arm** (F4; *lane 2*, `LR-AX` item 1: re-spelled, the design's rigid `a40; b40` under `.flexEnd` land where CSS puts them): `Row { a40; g.flexGrow(1) }.width(200).flexGrow(1).flexBasis(0).minWidth(0)` beside a zero-basis grower at 300: the item rect agrees (150), g is laid out at the declared 200 (160 wide, 50 past the item) where legacy lays it out in 150 (110) | reported | **M2d** a non-zero length basis lowered as `auto`; **M2d′** a zero basis given W's minimum 0 with no declared minimum (the F10 arm answers 150); **M2d″** a sized zero-basis grower lowered instead of reported |
| 2.5 | `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows` — `Row { Text(long).flexShrink(0); Box().width(50).height(10) }.width(100)` (*lane 2*: the box declares `.flexShrink(0)` too — legacy shrinks it to 0, divergence 55, `LR-AX` item 2): text one line, overflowing; the `Column` transpose (`.alignItems(.stretch)`); agrees (F7) | `box.flexShrink` | **M2e** `fixedSize` on the cross axis |
| 2.6 | **divergence pin** `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` — `Row { Box().width(80).flexShrink(1); Box().width(80).flexShrink(3) }.width(100)`: lowered 80/80 from x 0 (G9) for weights 1 and 3; legacy 50/50 and 65/35 (divergence 55) | reported | **M2f** a shrink ≠ 1 reported |
| 2.7 | `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` — `Box().minWidth(50)` over nothing in a `Row` (50); the demo scroller's shape `Box { Box().height(400) }.width(420).flexGrow(1).flexBasis(0).minHeight(0)` in a 300-tall column beside a fixed sibling (F4/F8); `Box().width(40).minWidth(60)` (static fold: 60); agrees | reported (`minSize`, `flexBasis`, `flexGrow`) | **M2g** W drops the minimum (the scroller arm answers its 400 content); **M2h** the static fold skipped (60 → 40) |
| 2.8 | `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere` — `maxWidth(80)` on a grower (80) and on `width(120)` (80, static) agree; `Text(long).maxWidth(80)` in a hugging row reports `text.maxSize` | reported | **M2i** a non-greedy maximum lowered onto W |
| 2.9 | **divergence pin** `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt` — the demo body row's shape at 920×560: legacy sidebar 88, lowered 196 (F5; G9, G4r) | reported | **M2j** a declared main size lowered as a greedy `frame(maxWidth: size)` with no minimum |
| 2.10 | **divergence pin** `aGrowerOnAHuggingContainersMainAxisFillsItsProposal` (cause R's isolating pin, X18) — `Column { Box().width(30).height(20); Box().width(30).height(10).flexGrow(1) }` in a 200×200 harness root: legacy column 30×30, lowered 30×200 | reported | **M2k** W not greedy when the parent declares no main size (pin and exit test's cause-R rows move) |
| 2.11 | **divergence pin** `aGrowInsideAOneChildPaddingFillsTheWrapperWhereCSSLeavesItUngrown` (`LR-AR`, S2, X12) — `Row { Box().width(40).height(10); Box().width(30).height(10).flexGrow(1).padding(8) }.width(200)`: legacy padding 46×26, child 30 wide; lowered (scratch R2) 160×26, child 144 | reported | **M2l** grow elided in a one-child container (the pin reddens; the lane records what else — by reading, the exit test's main-pane rows) |
| 2.12 | `aGrownUnsizedSpaceDistributionContainerIsReported` (`LR-AR`, S1) — `Row { Row { a20; b20 }.justifyContent(.spaceBetween).flexGrow(1); c40 }.width(300)` reports `box.justifyContent.spaceBetween` at the inner `Row`'s site; controls `.flexEnd` and `.center` agree; *lane 2:* a `.minWidth(200)` arm reports the same | report empty (S1), literal mismatch | **M2m** the grow half of the re-check removed; **M2m′** (*lane 2*) the re-check limited to a greedy W |
| 2.13 | `anAnimatedItemFieldSnapsItsStructureAndInterpolatesItsValues` (`LR-AS`) — through one fake `Window` per authority in turn (*lane 2*: not `WindowPair`, whose one closure cannot give each window its own model, and a parked transaction is consumed once; `LR-AX` item 3), every state pre-flighted (`LR-AA`), `withAnimation` and `simulateTick`, never a sleep. Arm A: `flexGrow` 0 → 1 beside a rigid 40 at 300: legacy 0, 0, 65, 130, 260, lowered 0, 260, 260, 260, 260 (**divergence**). Arm B (*lane 2*: `(0 → 2, 2)` — `(1 → 2, 2)` starts reporting weights — in a child process): no report at any tick, lowered 150/150 at every tick after the change, legacy 60/240 and 100/200 mid-flight (**divergence**). Arm C: `minWidth` 40 → 80 on a grower (*lane 2*: in a 300 row beside a rigid 260 — a hugging row fills, cause R): 40, 40, 50, 60, 80 on both sides (agrees) | stage 1 reports `box.flexGrow` / `box.minSize` | **M2n** W's existence read from the animated style with a threshold of 0.5 (arm A hugs at an early tick); **M2o** the weights check reads the animated style (arm B reports mid-flight); **M2p** W's minimum read from the declared style (arm C snaps) |
| 2.14 | `aLoweredItemChainWithThreeWrappersPerLevelAtTheNativeDepthLimitLaysOut` and `…OnePastTheNativeDepthLimitTraps` (exit test) — each level an item declaring `flexShrink(0)`, `flexGrow(1)` and `alignSelf(.flexEnd)` in a two-child `Row` (so `fixedSize`, W, the alignment frame and the row's own nodes); the level count derived by hand from 88 (*lane 2*: 21 rows, exactly 88 and 89 levels by the innermost child, 130 and 131 nodes; the demo's deepest native run is 18, `LR-AX` item 8). The lane also records the whole demo's deepest native run under the proposal authority (stage 1 measured 12 by scratch) | the chain reports its fields | **M2q** `maxDepth` raised by 8 (the trap arm exits 0) |
| 2.15 | **exit test** `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`, rewritten — §7 | 5.3's stage-1 literal | §7 |

**Amended pins**: `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`
(`margin` + `flexGrow` → two fields stage 2 leaves reported, `size.percent` +
`inset`); `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
(the literal loses `flexGrow`; lanes 4–5 remove `margin` and `reverse` in turn
and re-derive it from fields that stay reported: `gap.percent`, `flexWrap`,
`alignContent`, `position`); `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(`flexGrow`, `flexShrink`, `minSize`, `maxSize` arms re-spelled to what still
reports, `flexBasis` kept with a length). `aLoweredChainAtTheNativeDepthLimitLaysOut`
and `…OnePastTheNativeDepthLimitTraps` declare `.alignItems(.flexStart)` and
sizes, so they register no item wrapper and must stay green unchanged. *Lane 2*: the
first two were already re-spelled in lane 1 (`LR-AW` item 3); what moved instead is
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (the `List`'s spacer no
longer reports), `anItemFieldNoLoweredContainerConsumesIsReportedByName` (its
control `Row` reports nothing) and the leaf test's in-`Row` arms (a percentage
`minSize`, negative grow and shrink, `LR-AX` item 5); the two stage-1 depth pins
stayed green.

**Demo expectation**: legacy images 0 px; preview 0 px.

### Lane 3 — the proposal-path answers that reach production (`LR-AU`)

Two commits, each with its own full suite, pixels and record entry. Files:
`LayoutTree.swift` (commit 1, the `.padding` placement case only), `ProposalText.swift`
(commit 2); tests `NativeValidationAcceptanceTests.swift`, `LoweringLeafTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | commit 1, kernel: `aNativePaddingPlacesItsChildAtTheChildsOwnSize` (`MetalUILayoutTests`) — **three arms** (`LR-AY` item 3; a custom `ProposalLayout` cannot show this, `SA-C`): the clamped response in a stack (N1, `.padding(−15)` on 20×20 beside a sibling — the pad answers 0×0 and the child is (−15, −5) 20×20, not 30×30); the caller-bounds entry `computeNativeLayout(root:proposal:in:)` with insets (1, 2, 3, 4) in (10, 20, 100, 100) — child at (14, 21) 20×20 where the old rule read 94×96; and control N2, a proposal-filling child, which must NOT move | stored at 94×96 | **M3a** bounds minus insets restored |
| 3.2 | commit 1, amended: `negativePaddingIsAcceptedAndItsResponseClampsPerAxis` — the pinned-wrong precondition `clampedRect.width == 30 && … == 30` becomes SwiftUI's 20×20 and the doc's "pinned wrong on purpose" paragraph is replaced. **Measured at design time**: with item 4 applied this test exits `SIGTRAP` on exactly that precondition and passes once it reads 20 (`LR-AU`) | exits `SIGTRAP` once 3.1's change lands (the red run is the implementation's, recorded) | M3a |
| 3.3 | commit 2: `aProposalTextBelowItsNarrowestWordAnswersItsWidestCharacterWhereSwiftUIAnswersTheProposal` (stage 1's 2.7) re-derived and renamed `aProposalTextBelowItsWidestBrokenLineAnswersTheProposal`: at 0 and 5 the width is the proposal, the height still 592 (T3/T4) | the old pin passes; the renamed one fails on `answer.size.width == width` | **M3b** the clamp removed |
| 3.4 | commit 2: `aProposalTextBreaksInsideAWordAndAnswersItsWidestLineUpToTheProposal` — probe Y's widths over its **three** strings (`LR-AY` item 1): Y1–Y5 `"alpha"`, Y6–Y7 `"Short"`, Y8–Y9 the sentence. The line count equals probe Y's (literal: 1, 2, 2, 4, 5, 2, 2, 12, 7) and the width equals `min(w, cache.shaped(s, wrappingAt: w).widestLine)` read from the shaping cache — never a probe literal, since SwiftUI ceils and this does not (Y2 19 against 18.17, Y9 45 against 44.02). Y0 at nil is one line at its unwrapped width. `try #require(clamped == 2)`: only Y5 and Y8 have a widest line above their proposal | Y5 and Y8 answer wider than the proposal | **M3b**; **M3c** the clamp applied as `proposal` whenever a line breaks (Y2's 18.17 reads 25) |

**Demo expectation — met, measured** (record §"Lane 3"): all twelve `CN-R` images
read **0 differing pixels, scene identical** after commit 1 and again after commit
2, the preview among them, so neither production answer reaches a production
root's pixels — measured for commit 2 where this row predicted it (`LR-AY` item
5). The exit test (2.15) re-ran unchanged after both commits, and the 97 goldens
did not move. The record names commit 1 for the other track: its padding tests
must be re-checked after the merge. **Divergence 59 closes in commit 2**; W2 stays
unpinned and deferred (`LR-AM` as amended, `LR-AY` item 6).

### Lane 4 — the box model

Files: `LegacyLowering.swift`, `Text.swift` (the padded leaf; glyph origin and
wrap width), `LoweringState.swift` (`textLeaves`); tests
`LoweringBoxModelTests.swift` (new).

| # | test | red before | mutation |
|---|---|---|---|
| 4.1 | `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` — asymmetric `Style.border` (1, 2, 3, 4) on a sized container and a leaf, with padding; agrees | `box.border` | **M4a** border insets transposed top/left |
| 4.2 | **divergence pin** `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt` — `Text("alpha")` with `Style.padding` 10 beside a sibling in a harness column: legacy 33-wide box at the column origin, lowered text box = shaped width + 20 × 16 + 20, glyph origin (10, 10) from the box (P6). **Stretched arm**: a multi-line `Text` with `Style.padding` 10 in a 200-wide `Column{…}.alignItems(.stretch)` with a sibling: the lowered glyphs wrap at 180 (the leaf's measured width), the line count from the shaping cache at 180, no glyph past x 190 | `text.padding.text` | **M4b** glyphs painted at the element node's origin; **M4b′** glyphs wrapped at the element's (aliased) width (the stretched arm gains width and loses lines) |
| 4.3 | **divergence pin** `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox` — a 10×10 child with `.width(10).height(10)` and `Style.padding` 12 on a `Box` (child at (12, 12), P1), a `Row` (its content alignment: child at (12, 0), P7) and a `Column` ((0, 12), P8): legacy 34×34 with the child at (12, 12) in all three, lowered 10×10 | `box.padding.floor` | **M4c** the lowered frame given `max(size, padding sum)`; **M4c′** the frame aligned `.topLeading` whatever the container (the `Row` and `Column` arms) |
| 4.4 | `aMarginLowersAsPaddingOutsideTheItem` — asymmetric px and rem margins on a fixed child in a `Row`, a `Column` and a `Stack`; a **stretched** item with cross margins (`.alignItems(.stretch)`; practices shape 9's "stretch × margins" pair); a **grown** item with main margins; agrees, element rects exclude the margin (P3) | `box.margin` | **M4d** the margin padding aliased; **M4e** the margin inside W |
| 4.5 | `aNegativeMarginOverlapsItsSibling` — `Row { a20.margin(-8); b20 }` agrees (P4: a at −8, b at 4); **divergence pin** at −15 on 20, where SwiftUI's response clamps at 0 and CSS's margin box is −10 | reported | **M4f** negative margins clamped at registration |
| 4.6 | `anAutoMarginLowersAsZero` — characterization: `margin(.auto)` via `Style` agrees | reported (`margin`) | **M4g** `.auto` reported |
| 4.7 | `percentagesStillReportByNameWithTheirOwner` — one arm each: `size.percent`, `padding.percent`, `border.percent`, `margin.percent`, `minSize.percent`, `maxSize.percent`, `gap.percent`, `flexBasis` (fraction); `try #require` on the arm count | — (each already reports, some under an older name) | **M4h** `margin.percent` lowered as 0 |
| 4.8 | `aLoweredItemChainWithFourWrappersPerLevel…` — 2.14's pair with a `margin` added per level; the level count re-derived from 88 | the margin reports until this lane | **M4i** `maxDepth` raised by 8 |

**Demo expectation**: legacy images 0 px; preview 0 px. The exit test re-runs
unchanged (the demo declares no margin, border or leaf padding).

### Lane 5 — justify distribution and reverse directions (`LR-AJ`)

Files: `LegacyLowering.swift` (`arrangeLegacyMainAxis`); tests
`LoweringDistributionTests.swift` (new); amended
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (its
`space-*` and reverse arms move here) and
`aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`.

| # | test | red before | mutation |
|---|---|---|---|
| 5.1 | `spaceBetweenLowersToSpacersAtTheGap` — `Row`/`Column` × gap {0, 10} × three fixed children at 200 (J1, J2) and overflowing at 50 (J3); agrees | `box.justifyContent.spaceBetween` | **MJa** the spacer's minimum 0 whatever the gap |
| 5.2 | `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit` — around (J7) and evenly (J4) at gap 0; evenly and around at gap 10 (J8's rigid leaf); both axes; agrees | reported | **MJb** around's between-spacers not doubled; **MJc** the gap as `Spacer(minLength:)` (J5) |
| 5.3 | **divergence pin** `spaceAroundAndSpaceEvenlyOverflowFromTheStartWhereCSSCentres` — three 20s at 40: lowered from x 0 (J9); legacy as `Alignment.swift` answers, read before the literal is written | reported | **MJd** the overflow centred |
| 5.4 | `aSpacerBesideAGrowingChildTakesNothing` — `Row { a.flexGrow(1); b }.justifyContent(.spaceBetween).width(200)`: a 180, b at 180 (J6); agrees | reported | **MJe** spacers given priority 0 |
| 5.5 | `aReverseContainerPlacesItsChildrenFromTheMainEnd` — `rowReverse`/`columnReverse` × `justifyContent` {nil, center, flexEnd, spaceBetween} × gap {0, 10} at 200 (R1); agrees | `box.reverse` | **MJf** the node order not reversed; **MJg** the main factor not mirrored |
| 5.6 | `aReverseContainerOverflowsTowardItsMainStart` — two `flexShrink(0)` 80s in a `rowReverse` 100: a at 20, b at −60 (R2); agrees | reported | MJg |
| 5.7 | `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` — a reverse row of three clickable, labelled boxes with `@State`: `stateSlotsEqual`, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual`; agrees | reported | **MJh** the children's *group* order reversed before registration |
| 5.8 | **characterization** `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` (`LR-AL`) — `Row { a; b }` lowered with spacing 0, not `nil` (8, stack-algorithms S); agrees | green on arrival | **MJi** the lowered stack given `spacing: nil` when the gap is 0 |
| 5.9 | `aGrownReverseContainerPlacesFromTheMainEndOfItsItemFrame` — an unsized `rowReverse` row grown by its parent (the mirrored factor in W's content alignment); agrees; and its `spaceBetween` variant still reports (`LR-AR`) | reported | MJg (the grown arm) |

**Demo expectation**: legacy 0 px; preview 0 px.

## 7. The exit test (`LR-AN`)

`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (2.15) keeps its name
and file (`LoweringCorpusTests.swift`), is rewritten in lane 2, and is re-run by
lanes 3–5. `demoContent()` imported from `MetalUIDemoContent`, 920×560 in the
harness root, diagnostics on, animation off:

1. **Modal off**: `report.unlowerable == [list.noLowering, scrollView.noLowering]`
   exactly (P3 and scratch R2 measured this order). **Modal on**:
   `[stack.position, stack.inset, list.noLowering, scrollView.noLowering]`. No
   stage-2 field entry and no `…unconsumed` entry, as an array equality.
2. **Every disagreement is an expectation with its cause.** `try
   #require(report.elements == 2036)` (modal off), 6 agreeing, 30 disagreeing,
   each pair grouped in the doc comment by cause, each cause with a named pin that
   reproduces it in isolation. **Rects no text reaches are literals** (the root and
   sidebar padding layers' widths, the sidebar bars, the stack cluster, panel,
   badge frame, counter chrome and buttons' sizes, the `List`); **rects a text
   reaches are derived in the test** (`LR-F`): the lowered sizes of "Library",
   "Text renders", the paragraph and the three counter texts from
   `proposalTextMeasurement` at the widths the test derives (648 for the main
   column's texts, 168 for the sidebar's), the legacy ones from the legacy text
   measure at 756 and 60, and every rect below a text in its column (the
   scroller `Box`'s y, the main column's and its layers' heights) as expressions
   of those.

| cause | probe arm | isolating pin | P3 / R2 rows (legacy → lowered) |
|---|---|---|---|
| **R** the harness root offers its proposal (divergence 53) and the demo's greedy column fills it | stack-algorithms A5; stage-2 X4, X18 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`, 1.7, 2.10 | outer padding layer 920×439 → 920×560; outer column 888×407 → 888×528; body row 888×310 → 888×431; the heights of the sidebar and main-pane layers and the main column; the scroller `Box` 0 → 73 tall |
| **55** a declared 196 sidebar is served first where CSS shrinks it to 88 | F5; stack-algorithms G9, G4r | 2.9 | sidebar layer 88 → 196 wide; its column and five children 60 → 168 wide; main-pane layer x 116 → 224, 788 → 680 wide; main column 756 → 648; every main-pane descendant x + 108; "Text renders" 756 → 648 wide; the paragraph 756×48 → 648×64; the scroller `Box` y 439 → 455 |
| **X9** a stretched single-child container does not stretch its child (`LR-AC`) | X9 | 1.3 | the sidebar column 282 → 160 tall |
| **3** `ScrollView` has no lowering | — (site-level) | stage 3 | the `ScrollView`'s two recorded ids |
| **4** `List` has no lowering | — (site-level) | stage 4 | the `List` (420×14000 → 0×0) |

   The lane re-measures and writes the table from its own run; P3's and R2's
   figures (identical) are the prediction it checks first, and any row under none
   of these five causes is a finding recorded before the expectation is written.
3. **Modal on**: the same assertions with 2042 ids and 36 disagreeing — the six
   extra rows are the modal's `Stack` (site-level `position`/`inset`, stage 5) and
   its descendants. *Lane 2* (`LR-AX` item 9): the six (the `Deferred`, the
   `Stack`, the card's layer, its column and two texts) are asserted by id; the
   `List`'s two ids sit one index later; the 30 pairs are asserted in both states.

Mutations that must redden it: **M1a** (stretch not aliased), **M2a** (grow on
the cross axis), **M1d** (the elision removed: the X9 row moves), **M2k** (cause
R's rows move), **M1m′** only if the demo reaches a `noLowering` site's records
(recorded either way), and **M5c′** = stage 1's **M5c** re-spelled for stage 2
(the `flexGrow.weights` check always reporting).

## 8. Demo, pixels and captures

At the end of **every** lane (lane 3: every commit), against `cb2e708`, the twelve
`CN-R` images (eight legacy demo, two preview, two 560²), generated by the harness
that imports `MetalUIDemoContent` (`gen-lib.py`, record §18) into a `git archive`
of the lane's commit, controls read non-zero first (light vs dark 1 048 576;
default vs modal 1 030 498; default vs animation 210 027; f0 vs f3 0; preview
light vs dark 1 048 576). Expected: **0 in all twelve at every lane**. Lane 3's
two commits are the only changes that reach a production root (the preview); a
non-zero preview image there stops the lane (`LR-AU`). Stage 1's two-authority
chrome pair is re-taken with `CounterPanel()` (lane 1) and must read 0 with stage 1's
M5d as its control.

**Real-window captures.** Before any capture: `xcrun swiftc -O
docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate`;
capture only if it prints no `CGSSessionScreenIsLocked` line and
`displayAsleep main: 0`, then `docs/probes/window-capture/capture.sh <scratch
dir> cb2e708 <lane HEAD>` and record its table. `IOConsoleLocked` is not read
(`FR-V`). At design time and at critic round 1 the probe read locked and asleep;
no capture was taken.

## 9. Deferred, each with an owner

| item | why not stage 2 | owner |
|---|---|---|
| `hidden()` (probe H1, V1/V3; `AB-O` off `display`) | the lane cap after lane 3's split; its hooks sit in `ElementGroup.swift`/`ModifiedElement.swift` group defaults; the design's gating would have changed legacy paint and hitboxes (critic finding 4). Constraints handed in `LR-AV` | task 7 before stage 9 (proposed as stage 5's companion); focus and keys under it: task 12 |
| `AnyElement`'s missing accessibility suppression for `hidden()` (record §18) | a legacy production change needing its own legacy pins | the integrator hands it with `LR-AV` |
| percentages: `size`, `padding`, `border`, `margin`, `gap`, `minSize`/`maxSize`, `flexBasis(fraction:)` (`FR-H`/`FR-T`) | no one-to-one SwiftUI spelling: `containerRelativeFrame` is container-relative (C1); a parent fraction needs a greedy `GeometryReader` (C2); each call site needs a respelling decision | stage 8 (recipe), stage 10 (deletion) |
| `maxSize` on a non-greedy axis | SwiftUI's maximum is greedy (X10, frame probe D4, re-run identical); the recipe converts `.maxWidth` to `.frame(maxWidth:)` and takes that answer | stage 8 |
| `flexBasis` with a non-zero length; a zero basis on a sized grower without a minimum | no SwiftUI spelling (an ideal is used only at a nil proposal); CSS's min(size, content) floor | stage 8 / 10 |
| unequal `flexGrow` weights | no SwiftUI spelling | deleted concept, stage 10; tests retired in 7b |
| `space-*` on an unsized container its parent grows or stretches | the child registers before it knows (`LR-AR`) | stage 8's recipe (declare the size or respell with `Spacer`s) |
| overflow compression in production (divergence 55) | lowered to SwiftUI's answer here; production gains it at the root switch | stage 6b |
| `Row`/`Column` default spacing (divergence 52) | a spelling default, not a lowering (`LR-AL`) | stage 8 |
| W2: a priority-1 text beside a short one in a narrow `HStack` (kernel 75/5, SwiftUI 59/18 with the clamp) | stack allocation around text, not measurement: "Short" measures 18 at 21 on both sides (Y6) | task 11 (`LR-AM` as amended), with divergence 51 |
| the ceiling on a text's width (SwiftUI 19 where the kernel measures 18.17, Y2) | the kernel rounds rects, not measurements; not a stage-2 field | task 11 |
| the legacy `textMeasure` and tokenizer min-content | the legacy engine's | stage 9 |
| `alignItems.baseline` / `alignSelf.baseline` | no baselines | task 11 |
| `Stack`/`ZStack` stretch fidelity beyond §4.1 (a greedy child in a hugging stack, X16) | pinned as a divergence here (1.9) | stage 6b (root and demo re-spelling) |
| stage-1 lane-5 verifier minor 2: `compareInWindows` has no caller | stage 2's window tests use `WindowPair` directly | the integrator (delete it, amend `LR-AA`) |
| stage-1 lane-5 verifier minor 1: stage 1's 5.8 doc comment and the 88/89 boundary | untouched by stage 2 (no item frame in that chain) | stage 6b's depth re-bisection |
