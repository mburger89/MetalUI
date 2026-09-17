# Engine replacement, stage 2 — flex-item semantics onto SwiftUI's (design)

**Status, 2026-09-17 (PDT): designed, not implemented.** Branch
`feat/engine-stage-2` from `cb2e708`. Plan task 7, stage 2 of the fourteen in
[`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 (its row 2) and §8 (its stage-2 row). Rulings `LR-AB`…`LR-AO` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md)
(the same decisions doc as stage 1). Record:
`docs/record/19-engine-replacement-stage-2.md`. Probe:
`docs/probes/swiftui-engine-replacement-stage2.swift` (arms F, X, P, J, R, C, V;
cited as *stage-2 probe*; stage 1's arms are *stage-1 probe*, the containers
probe's are *stack-algorithms*).

**Scope, in one sentence.** Under the **proposal** layout authority only, every
flex-item field the stage-1 lowering reports and the whole demo still carries
lowers onto kernel nodes — by the SwiftUI spelling a SwiftUI author would write,
with each place that spelling answers differently from CSS pinned against a
probe arm — or keeps reporting by name with a named later owner. Production
still runs the legacy authority (until stage 6b), so the eight legacy demo
images stay 0 px; the preview may move only where `SA-N` item 4 (a kernel
change) reaches it.

**Five lanes** (the brief's cap): 1 item records and the cross axis; 2 the main
axis and the exit test; 3 the box model and `SA-N` item 4; 4 justify
distribution and reverse; 5 `hidden()`. Everything else in the row is deferred
by name (§9).

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
| screen | locked at 07:1x PDT: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` | `docs/probes/appkit-screen-lock-state.swift` |

## 2. Evidence gathered for this design

**Probe** (`swiftui-engine-replacement-stage2.swift`, 157 lines, run twice
byte-identical; the reading is in its header). The arms this design rests on:

| arm | SwiftUI answer | CSS answer for the legacy spelling |
|---|---|---|
| F1 | greedy frame beside a rigid 40 at 300: 260 | `flexGrow` 1: 260 (agrees) |
| F2 | two greedy frames over 100 and 20 at 300: **150 / 150** | `flex-basis: auto`: 190 / 110; `flex-basis: 0`: 150 / 150 |
| F3 | over 200 and 20: 200 / 100 (never below its child) | — |
| F4, F8 | a declared minimum lets a greedy frame answer below its child (150 over 200) | `min-width: 0` does the same |
| F5 | a rigid 196 beside a greedy text frame at 400 keeps 196 | CSS shrinks the 196 (`SZ-L`, divergence 55) |
| F7 | `.fixedSize()` text overflows (302) | `flex-shrink: 0` overflows |
| X1, X2 | greedy cross frame: the stack's own cross size (40) or the concrete one (100) | `stretch`: the line's cross size (agrees) |
| X4 | a greedy view inside a **hugging** container fills that container's proposal (200) | CSS fit-content: 30 |
| X5 / X7 | `.frame(maxWidth: .infinity, alignment: .leading)`: exact in a definite column; fills an indefinite one (300 against 100) | `alignSelf: flex-start`: the column hugs (100) |
| X8, X9 | a nil-axis `.frame(width: 30)` is not stretched; an outer greedy frame is | a flex item with an auto cross size is stretched (`MC-Q` finding 7) |
| X10 | `.frame(maxHeight: 25)` in 100: 25 | stretched, then clamped: 25 |
| P1 | padding 12 inside a fixed 10×10 frame: the frame stays 10×10 and the padding overflows | border-box floor (`BM-4`): 34×34 |
| P3, P4 | padding outside a background is a margin; negative padding overlaps and clamps at 0 per axis | `margin` (agrees until the clamp) |
| P6 | `Text("alpha").padding(10)`: 53×36, text at (10, 10) | Style padding on a content-sized leaf is inert (33×16) |
| J1–J9 | spacers are `space-between` (min = gap), `space-evenly` / `space-around` (spacers at the ends, two between, a rigid gap leaf); overflowing, spacers pack from the start | `space-evenly`/`space-around` overflow falls back to `center` |
| R1, R2 | reversed children in a trailing frame are `row-reverse`, overflow included | agrees |
| C1 | `containerRelativeFrame` is relative to the window (500), not the 200 parent | percentages resolve against the parent |
| V1, V3 | `.hidden()` paints nothing and takes no tap (the tap reaches what is under it) | legacy `hidden()` is `display: none` |

Stage-1 probe arms also cited: H1 (`.hidden()` keeps its space), S1–S3, G1/G2,
T3/T4, W2. Stack-algorithms arms: A5, G9, G4r, S (default spacing).

**Prototype P3** (scratch, applied to this worktree, built, run, restored with
`git checkout Sources` and the scratch test deleted; patch kept in the session
scratchpad as `p3.patch`, never committed). It implemented §3's mechanism for
lanes 1–2 only: item records, the bounds alias, stretch (with and without the
single-child elision), `alignSelf`, `flexGrow`, `flexShrink: 0`, `minSize` /
`maxSize` on the item wrapper, and removed those fields' diagnostics.

| run | measured |
|---|---|
| whole demo, 920×560 in the harness root, modal off | **report `[list.noLowering, scrollView.noLowering]`**; 2036 ids, 6 agreeing, 30 disagreeing, 2000 legacy-only (the `List`'s rows), 0 lowered-only |
| the same, modal on | report `[stack.position, stack.inset, list.noLowering, scrollView.noLowering]`; 2042 ids, 6 agreeing, 36 disagreeing |
| full suite, **no** single-child elision | 1410 (1409 + the scratch test), 8 tests red: the five diagnostics pins below plus `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` (5 issues), `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` (9), `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` (4) — a padding layer's implicit stretch made its content greedy (X4) |
| full suite, **with** the elision (`LR-AC`) | 1410, **5 red, all diagnostics pins**: `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (6 issues), `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` (14), `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (3), `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst` (1), `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (1) |

The 30 whole-demo disagreements trace to three probe-backed causes and the two
site-level sites (§7).

## 3. The mechanism: item records and a bounds alias (`LR-AB`)

A flex-item field (`flexGrow`, `alignSelf`, …) means something only in its
**parent's** axis, and the legacy registration order is post-order: a child
registers before its parent exists. Three shapes were weighed (`LR-AB`); the
chosen one touches no group entry, no proposal element and no kernel case:

1. **The child records, the parent decides.** Every lowered legacy element
   records a `LoweredItem` for the node it returns — its declared and animated
   `Style`, its site, the alignment of its own content, and its kind (leaf,
   flex container, stack, frame layer) — in `Frame.loweredItems`, and reports
   no item field itself.
2. **A lowered container wraps its children** before registering its stack or
   overlay (`lowerLegacyItems`): for each child node with a record, by the
   container's axis and its own `alignItems`/`justifyItems`, it registers at
   most three nodes around the child, innermost first:
   - `fixedSize` on the main axis — `flexShrink: 0` (lane 2);
   - the **item frame** W — greedy on the main axis for `flexGrow > 0`, greedy
     on the cross axis for stretch, carrying the item's `minSize`/`maxSize`,
     aligned by the child's own content alignment;
   - the **alignment frame** — greedy on the cross axis, aligned by a
     non-stretch `alignSelf` (lane 1); then native **padding** for `margin`
     (lane 3), outermost.
3. **The item frame is the element's rect.** In CSS a grown or stretched box
   *is* bigger — its background, hitbox, accessibility frame and text wrap
   width are the grown ones. So when W is registered the container records
   `Frame.boundsAliases[child] = W`, and `Frame.bounds(of:)` and
   `LayoutPass.measuredWidth(of:)` resolve the alias. The alignment frame and
   the margin padding are **not** aliased: they are outside the box, as in CSS.

A record nobody consumes — the root, a child of a proposal container, of a
`ScrollView` or a `List` (site-level until stages 3–4) — lowers as though its
item fields were absent: under the legacy authority none of those trees exists
except the root, whose item fields the legacy engine ignores too.

## 4. The lowering table after stage 2

Stage 1's §5.4 table stands except where this one amends it. "Report" names the
field string in `UnlowerableField`.

### 4.1 Item fields (consumed by the parent; lanes 1–2)

| field | flex parent (`Box`/`Row`/`Column`, a `.padding` layer) | stack parent (`Stack`; a one-node frame layer is a stack, `CN-N`) | evidence |
|---|---|---|---|
| stretch (`alignItems` `nil`/`.stretch` on the parent, `alignSelf` `nil`/`.stretch` on the child), child's cross `size` `auto` | W greedy on the cross axis, aliased — **except** when the parent has exactly one child and no declared cross size (the stage-1 condition, `LR-AC`) | the same per axis (`alignItems` vertical, `justifyItems` horizontal) | X1, X2, X9; divergence (new) X4 |
| a frame layer child with a nil axis (`MC-Q` finding 7) | stretched on that axis like any auto item | the same | X8, X9 |
| `alignSelf` `.flexStart`/`.center`/`.flexEnd` differing from the parent's | alignment frame, greedy on the cross axis, not aliased | ignored (the legacy stack ignores it) | X5; divergence (new) X7 |
| `alignSelf` `.baseline` | report `alignSelf.baseline` (task 11) | ignored | — |
| `flexGrow > 0`, all growing siblings equal | W greedy on the main axis, aliased | ignored | F1; divergence (new) F2 |
| `flexGrow > 0` with unequal positive values among siblings | report `flexGrow.weights` **on the parent's site** | ignored | none exists (deleted concept, stage 10) |
| `flexBasis` `.auto` | nothing | ignored | — |
| `flexBasis` `0` (any unit) **with** `flexGrow > 0` | W's main-axis minimum is 0 (unless `minSize` is larger): a minimum's presence lets the greedy frame answer the equal share below its content, as CSS's zero basis does. A declared main `size` stays on the element's own fixed frame (the child registers before it can know which axis is main), so a **sized container** with a zero basis lays its content out at the declared size inside a smaller item rect — divergence (new), F4 | ignored | F4, F8 |
| `flexBasis` `0` without `flexGrow`, any other length, or a fraction | report `flexBasis` (CSS sizes such an item from the basis, which no SwiftUI spelling carries) | ignored | stage 8 / 10 |
| `flexShrink == 0`, main `size` `auto` | `fixedSize` on the main axis | ignored | F7 |
| `flexShrink > 0`, any value | nothing: SwiftUI's compression order (divergence 55, `LR-AF`) | ignored | F5, stack-algorithms G9, G1 |
| `minSize` px/rem on an axis whose `size` is `auto` | W's minimum on that axis, aliased (presence semantics) | the same | F4, F8 |
| `maxSize` px/rem on a greedy axis (grown or stretched) | W's maximum on that axis | the same | X10 |
| `minSize`/`maxSize` on an axis with a declared `size` | folded at registration into the element's own fixed frame: `clamp(size, min, max)` (the CSS used size) | the same | — (static) |
| `maxSize` on a non-greedy `auto` axis | report `maxSize` (stage 8) | the same | X10's greediness is why |
| `minSize`/`maxSize` a fraction | report `minSize.percent`/`maxSize.percent` (stage 8) | the same | C1 |
| `margin` px/rem, any sign (lane 3) | padding outside the alignment frame, not aliased | the same | P3, P4; divergence (new) past the clamp |
| `margin` `.auto` | nothing — the legacy engine resolves it to 0 (inert table) | nothing | — |
| `margin` a fraction | report `margin.percent` (stage 8) | the same | C1 |

A **frame layer** as an item: its kernel frame already carries its own
`FrameSpec` bounds, so W carries `minSize`/`maxSize` only on a greedy axis (the
stretched axis), where CSS stretches and then clamps.

### 4.2 Container and node fields (lanes 3–5)

| field | lowering | otherwise | lane |
|---|---|---|---|
| `flexDirection` `.rowReverse`/`.columnReverse` | the children's **nodes** in reverse order (identity, paint and hit order untouched), `justifyContent`'s main factor mirrored (flex-start → trailing) | — | 4 |
| `justifyContent` `.spaceBetween` | `Spacer(minLength: main gap)` between children, stack spacing 0 | — | 4 |
| `justifyContent` `.spaceAround` / `.spaceEvenly` | `Spacer(minLength: 0)` at both ends (evenly) or both ends and doubled between (around); a non-zero main gap as a rigid native leaf of that length beside the between-spacer | — | 4 |
| `Style.border` px/rem | added to the native padding's insets (inside the declared size) | a fraction → `border.percent` (stage 8) | 3 |
| `Style.padding` on a `Text` | native padding around the text leaf; glyphs painted at the **leaf's** origin | — | 3 |
| declared size below the padding (+ border) sum | the fixed frame wins and the padding overflows (SwiftUI P1) | — | 3 |
| `display: .none` (`hidden()`) | lowered as if shown; the element's node joins `Frame.hiddenNodes`: its subtree paints nothing, registers no pointer hitbox and publishes nothing to accessibility | — | 5 |
| `size`/`padding`/`gap` a fraction | — | `size.percent`, `padding.percent`, `gap.percent` stay (stage 8) | — |
| `alignItems` `.baseline`, `flexWrap`, `alignContent`, `position`, `inset` | — | unchanged (task 11; deleted concept; stage 5) | — |

**Order of a report** (`LR-Y`, amended): a leaf reports its every-node rows; a
container its container rows then its every-node rows; a container **then**
reports each child's item fields it cannot lower (`flexGrow.weights` once, at the
container's site; a child's `flexBasis`/`maxSize`/`…percent` at the child's
site), in child order. Production traps on the first.

## 5. API and files

All `internal`; `@testable` tests reach them.

```swift
// Sources/MetalUI/LoweredItem.swift (new, lane 1)
struct LoweredItem {
    enum Kind { case leaf, flex(isRow: Bool), stack, frameLayer }
    var declared: Style          // what the checks read
    var animated: Style          // what the frame bounds read (LR-H's rule, "a branch that lowers from a style needs an animated arm")
    var site: LoweringSite
    var contentAlignment: ProposalAlignment   // where the element's content sits when its box grows
    var kind: Kind
}

// Frame (appended, lane 1; `swift package clean` — stored properties on a public class)
var loweredItems: [LayoutNodeID: LoweredItem]            // empty under the legacy authority
private(set) var boundsAliases: [LayoutNodeID: LayoutNodeID]
func aliasBounds(of element: LayoutNodeID, to itemFrame: LayoutNodeID)
func bounds(of node: LayoutNodeID) -> Bounds<Pixels>      // resolves the alias (one-line change)
// lane 3
var textLeafNodes: [LayoutNodeID: LayoutNodeID]          // a padded lowered Text's element node → its leaf
// lane 5
private(set) var hiddenNodes: Set<LayoutNodeID>
func isHidden(_ node: LayoutNodeID) -> Bool               // `style(node).display == .none || hiddenNodes.contains(node)`

// LayoutPass (Passes.swift, lane 1)
public func measuredWidth(of node: LayoutNodeID) -> Double   // resolves the alias (one-line change)

// Sources/MetalUI/LegacyLowering.swift (lanes 1–5)
extension LayoutPass {
    /// Records `node` as a lowered item and returns it (lanes 1–2).
    func recordLoweredItem(_ node: LayoutNodeID, animated: Style, declared: Style,
                           site: LoweringSite, contentAlignment: ProposalAlignment,
                           kind: LoweredItem.Kind) -> LayoutNodeID
    /// A container's children, each wrapped per §4.1 for this parent; appends
    /// the parent-level and child-level item reports to `fields` (lanes 1–3).
    func lowerLegacyItems(_ children: [LayoutNodeID], parent declared: Style,
                          parentSite: LoweringSite, fields: inout [UnlowerableField]) -> [LayoutNodeID]
    /// The main-axis arrangement: reverse order and justify distribution (lane 4).
    func arrangeLegacyMainAxis(_ items: [LayoutNodeID], _ style: Style) -> (nodes: [LayoutNodeID], mainFactor: Double)
}

// LayoutTree.swift (lane 3): `placeNative`'s `.padding` case places the child at
// (origin + leading/top inset) at the child's measured size (SA-N item 4).
```

**Shared files touched** (the other track merges them; every edit is appended
or one line): `Frame.swift` (appended stored properties and methods; one line in
`bounds(of:)`; lane 5 one condition in `suppressingAccessibilityIfHidden` and
at the root in `render`), `Passes.swift` (one line), `LegacyLowering.swift`
(the lowering itself), `LayoutTree.swift` (lane 3, the `.padding` placement
case only), `ElementGroup.swift` (lane 5: `Element.prepaintGroup`/`paintGroup`
and `AnyElement`'s entry consult `isHidden`), `ModifiedElement.swift` (lane 5:
the per-layer mirror, `MC-B`), `Text.swift` (lane 3: the padded leaf and its
glyph origin). No edit to `NativeElements.swift` or `Box.swift`.

**New test files**: `Tests/MetalUITests/LoweringItemTests.swift` (lanes 1–2),
`LoweringBoxModelTests.swift` (lane 3), `LoweringDistributionTests.swift`
(lane 4), `LoweringHiddenTests.swift` (lane 5). Kernel test (lane 3) in
`Tests/MetalUILayoutTests/NativeValidationAcceptanceTests.swift`.

**No new typecheck guard** is planned: every addition is internal and no
public spelling changes. A lane that adds one mutates it red once.

## 6. Lanes

Each lane's tests are written first and read red — "red before" for a lowering
test means **a diagnostic in the report**, so no red run truncates the suite —
except tests marked **characterization** (green on arrival; their mutation is
their evidence) and **divergence pins** (a `try #require` that the two
authorities disagree, with both sides' rects literal, and a mutation toward the
CSS answer that reddens them). Every mutation: commit first, `cp` the file
aside, apply, native build, full unfiltered `swift test --build-system native
--no-parallel`, restore from the copy, `git status --short` empty; the lane's
record names **every** test it reddens. Every lane ends with the full suite
(its count read from the summary line), the goldens count (97, `git diff
--name-only cb2e708 -- '*.json'` empty), the twelve `CN-R` images (§8) and the
lock probe (§8).

"Agrees" means `LayoutDifferential.compare` reports an empty `unlowerable`,
`disagreeing` empty, `scenesEqual`, `hitboxesEqual`, `accessibilityEqual` and
`stateSlotsEqual` true, with `try #require(report.elements == N)` for an N
derived by hand. Where a text decides a rect, the expectation comes from the
shaping cache, not a literal (`LR-F`).

### Lane 1 — item records, the bounds alias, the cross axis

Files: `LoweredItem.swift` (new), `LegacyLowering.swift`, `Frame.swift`,
`Passes.swift`; tests `LoweringItemTests.swift` (new), and the amended pins
listed below. `swift package clean` (Frame's stored properties).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aStretchedChildFillsTheLineOnItsCrossAxis` — `Row` and `Column` × parent {unsized: line = tallest sibling (X1); sized (X2)} × stretched child {childless `Box` with a main size; `Text`; a `Row` with `justifyContent(.center)`}; every arm has ≥ 2 children; agrees | `box.alignItems.stretch` | **M1a** W registered but not aliased (the element rect stays hugging); **M1b** W greedy on the main axis instead of the cross |
| 1.2 | `aStretchedContainersContentSitsByItsOwnAlignment` — a stretched `Column` child with `alignItems` {start, centre, end} and a stretched `Row` child with `justifyContent` {start, centre, end}, fixed grandchildren at distinct sizes (practices shape 1); agrees | reported | **M1c** W aligned `.topLeading` always |
| 1.3 | **divergence pin** `aStretchedSingleChildContainerDoesNotStretchItsChild` — `Column { Box { Box().height(10) }; Box().width(80).height(10) }.alignItems(.stretch).width(200)` (sized, so cause R of §7 cannot confound it): the middle `Box` is 200 wide on both sides; its child is 200 wide on the legacy side and 0 wide lowered (X9: content inside an outer greedy frame keeps its size); plus the agreeing control `Box { Text("x") }` alone (the elision's reason: SwiftUI's `.padding` never makes content greedy) | reported | **M1d** the elision removed — reddens 1.3's pin, and (measured by P3) `aLoweredPaddingLayerAgreesWithTheLegacyWrapper`, `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement`, `aLoweredBranchingTreeRegistersAndMeasuresAHandDerivedAmountOfNativeWork` |
| 1.4 | `aStretchedItemIsClampedByItsOwnMinimumAndMaximum` — a sized 100-tall `Row` over `Box().width(20).maxHeight(25)` and `Box().width(20).minHeight(60)` (siblings present): 25 and 60, at the top (a stretched item aligns as flex-start; X10 is SwiftUI's centred spelling, which W's `.topLeading` alignment inside the stack does not use); agrees | reported (`minSize`/`maxSize`) | **M1e** W drops `maxSize` on the greedy axis |
| 1.5 | `alignSelfPlacesOneChildOnTheCrossAxisOfADefiniteContainer` — a 300-wide `Column(alignItems: .center)` over three fixed children, one each with `alignSelf` `.flexStart`, `.flexEnd`, `.stretch` (X5); agrees | `box.alignSelf` | **M1f** the alignment frame's factor always 0 |
| 1.6 | **divergence pin** `anAlignSelfWrapperFillsAnIndefiniteContainerWhereCSSHugs` — `Row { Column { a100; b20.alignSelf(.flexStart) } }` at 300: legacy column 100, lowered 300 (X7, X6) | reported | **M1g** the alignment frame not greedy (the column hugs; 1.5's `.flexEnd` arm also reddens) |
| 1.7 | **divergence pin** `aStretchedItemInsideAHuggingItemFillsItsProposal` — `Row { Column { Box().width(30).height(10); Box().height(10) }.alignItems(.stretch) }` at 200: legacy column 30, lowered 200 (X4, X3) | reported | **M1h** stretch made to fill only a parent with a declared cross size |
| 1.8 | `aNilAxisFrameLayerUnderAStretchingContainerIsStretched` (`MC-Q` finding 7) — `Box { a.frame(width: 30); b20x40 }` and the column transpose: the frame layer's rect is 30×40 and its child centred in it (X9's outer frame); a frame declaring both axes is not stretched; agrees | reported | **M1i** frame-layer records skipped by `lowerLegacyItems` |
| 1.9 | `aStackStretchesByItsItemsAlignmentAndIgnoresTheirFlexFields` — a sized `Stack` with `justifyItems`/`alignItems` nil over two auto children (stretched on both axes), and a `.center` `Stack` whose child declares `flexGrow`, `flexShrink(0)`, `alignSelf(.flexEnd)` (ignored, as legacy); agrees; stage 1's 4.1 stretch arms move here | `stack.alignItems.stretch` | **M1j** the overlay consumes `alignSelf` |
| 1.10 | `theBoundsAliasReachesDecorationHitboxesAccessibilityAndTextWrap` — a stretched clickable, labelled, backgrounded `Box` and a stretched multi-line `Text` in a sized column; agrees in every observation (glyph scene included) | reported | **M1a**; **M1k** the alias resolved in `bounds(of:)` but not `measuredWidth(of:)` (the glyph arm) |
| 1.11 | `aStretchedBranchingTreeRegistersAHandDerivedAmountOfNativeWork` (`SA-M`) — `Column { Row { a; b }; Row { c; d } }.alignItems(.stretch)` with fixed-height auto-width leaves in a 200×100 root: node count, calls, hits and misses **derived by hand in the doc comment before the first run** | the file does not compile until 1.1 lands; literal first | **M1l** W registered also for an elided single child (node count moves) |

**Amended pins** (each amendment is recorded with the red run it answers):
`everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` (arms that declared
stretch/`alignSelf` to produce a report re-declare a field still reported, e.g.
`size.percent`); `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(`alignSelf` → `alignSelf.baseline`; the count literal re-derived);
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (the
two-child and sized single-child stretch arms now agree; renamed
`spaceDistributionAndBaselineStillReport…` only if its subject changes — the
lane decides and records); `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes`
(its stretch arms move to 1.9); `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`
(the stretch and `alignSelf` entries leave its literal). **5.4–5.6**
(`aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements`,
`aLoweredWindowPublishesTheSameAccessibilityTree`,
`aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths`) replace the test-only
`LowerableCounter` with the demo's `CounterPanel()` (`LR-AA` item 2's handed
item; its chrome's `alignSelf` lowers here), and 5.5 gains `try
#require(pair.report().elements == N)` (lane-5 verifier minor 4); re-run M5d.

**Demo expectation**: legacy images 0 px; preview images 0 px (nothing in lane
1 reaches a proposal root).

### Lane 2 — the main axis; the exit test

Files: `LegacyLowering.swift`; tests `LoweringItemTests.swift`; the exit test
rewritten in `LoweringCorpusTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aGrowingChildTakesTheRemainingMainSpace` — `Row`/`Column` × grower {childless `Box`; `Text`; a `Row` with `justifyContent(.flexEnd)`} beside a rigid sibling (F1), with and without `gap`; agrees | `box.flexGrow` | **M2a** W greedy on the cross axis instead |
| 2.2 | **divergence pin** `growingSiblingsShareTheSurplusEquallyWhereCSSAddsItToTheirBases` — `Row { Box().width(100).height(10).flexGrow(1); Box().width(20).height(10).flexGrow(1) }.width(300)`: legacy 190/110, lowered 150/150 (F2); widths 200 and 20: legacy 240/60, lowered 200/100 (F3, a greedy frame never below its child); and the `flexBasis(0)` arms of both, which **agree** at 150/150 (F4/F8) | reported | **M2b** W given a main minimum of 0 without a zero basis (the 200/20 arm reads 150/150 lowered) |
| 2.3 | `unequalGrowWeightsAreReportedOnTheParent` — `Row { a.flexGrow(1); b.flexGrow(2) }` reports `box.flexGrow.weights` once; `(2, 2)` and `(0.5, 0.5)` lower and agree | reported per child | **M2c** the weights check removed |
| 2.4 | `aZeroBasisLowersWithGrowAndEveryOtherBasisIsReported` — basis `.auto`, and `0`/`0rem` with `flexGrow(1)` on a childless `Box().width(200)` beside a `width(20)` grower at 300 (150/150), lower and agree; **divergence pin** the same on a `Row { a40; b40 }.width(200).justifyContent(.flexEnd)`: the item rect agrees (150) and its children sit in the declared 200 (b's right edge 25 past the item's, F4's overflow) where legacy places them in 150; `flexBasis(0)` without grow, `flexBasis(40)` and `flexBasis(fraction: 0.5)` each report `box.flexBasis` | reported | **M2d** a non-zero length basis lowered as `auto`; **M2d′** the zero basis lowered without W's minimum (the leaf arm reads 200/100) |
| 2.5 | `aZeroShrinkKeepsItsNaturalMainSizeAndOverflows` — `Row { Text(long).flexShrink(0); Box().width(50).height(10) }.width(100)`: text one line, overflowing; the `Column` transpose; agrees (F7) | `box.flexShrink` | **M2e** `fixedSize` on the cross axis |
| 2.6 | **divergence pin** `aPositiveShrinkLowersAsSwiftUIsCompressionWhateverItsWeight` — `Row { Box().width(80).flexShrink(1); Box().width(80).flexShrink(3) }.width(100)`: lowered 80/80 from x 0 (stack-algorithms G9) for weights 1 and 3 alike; legacy 50/50 and 65/35 (divergence 55) | reported | **M2f** a shrink ≠ 1 reported |
| 2.7 | `aMinimumFloorsAnItemAndLetsAGrowerGoBelowItsContent` — `Box().minWidth(50)` over nothing (50); the demo scroller's shape `Box { Box().height(400) }.width(420).flexGrow(1).flexBasis(0).minHeight(0)` in a 300-tall column beside a fixed sibling (F4/F8: the grower takes the remainder, below its 400 content); `Box().width(40).minWidth(60)` (static fold: 60); agrees | reported (`minSize`, `flexBasis`, `flexGrow`) | **M2g** W drops the minimum (the scroller arm answers its 400 content); **M2h** the static fold skipped (60 → 40) |
| 2.8 | `aMaximumLowersOnAGreedyOrSizedAxisAndIsReportedElsewhere` — `maxWidth(80)` on a grower (80) and on `width(120)` (80, static) agree; `Text(long).maxWidth(80)` in a hugging row reports `text.maxSize` | reported | **M2i** a non-greedy maximum lowered onto W (the text arm reports nothing) |
| 2.9 | **divergence pin** `theDemosBodyRowKeepsTheSidebarAtItsDeclaredWidthWhereCSSShrinksIt` — the demo body row's shape (a `Column` of five 26-tall bars, `.flexGrow(1).padding(14).width(196)`, beside a growing column holding the demo paragraph) at 920×560: legacy sidebar 88, lowered 196 (F5; stack-algorithms G9, G4r) | reported | **M2j** a declared main size lowered as a greedy `frame(maxWidth: size)` with no minimum (a shrinkable CSS item; the pin reddens) |
| 2.10 | **exit test** `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn`, rewritten — §7 | 5.3's stage-1 literal | §7 |

**Amended pins**: `aLeafWithTwoUnlowerableFieldsTrapsNamingTheFirstInProduction`
(`margin` + `flexGrow` → two fields stage 2 leaves reported, `size.percent` +
`inset`); `aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`
(the literal loses `flexGrow`; lanes 3–4 remove `margin` and `reverse` in turn
and re-derive it from fields that stay reported: `gap.percent`, `flexWrap`,
`alignContent`, `position`); `everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf`
(`flexGrow`, `flexShrink`, `minSize`, `maxSize` arms re-spelled to what still
reports, `flexBasis` kept with a length).

**Depth.** The lane re-measures the whole demo's deepest native run under the
proposal authority (stage 1 estimated 22, `LR-Q`) and records it; W and the
alignment frame add at most two levels per item. `aLoweredChainAtTheNativeDepthLimitLaysOut`
and `…OnePastTheNativeDepthLimitTraps` declare `.alignItems(.flexStart)` and sizes,
so they register no item frame and must stay green unchanged.

**Demo expectation**: legacy images 0 px; preview 0 px.

### Lane 3 — the box model; `SA-N` item 4

Files: `LegacyLowering.swift`, `Text.swift` (the padded leaf; glyph origin),
`Frame.swift` (`textLeafNodes`), `LayoutTree.swift` (`.padding` placement);
tests `LoweringBoxModelTests.swift` (new),
`NativeValidationAcceptanceTests.swift` (amended), the kernel test below.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | `aStyleBorderLowersAsInsetsInsideTheDeclaredSize` — asymmetric `Style.border` (1, 2, 3, 4) on a sized container and a leaf, with padding; agrees | `box.border` | **M3a** border insets transposed top/left |
| 3.2 | **divergence pin** `paddingOnALoweredTextPadsItWhereTheLegacyLeafIgnoresIt` — `Text("alpha")` with `Style.padding` 10 in a harness column: legacy 33-wide box at the column origin, lowered text box = shaped width + 20 × 16 + 20, glyph origin (10, 10) from the box (P6) | `text.padding.text` | **M3b** glyphs painted at the element node's origin |
| 3.3 | **divergence pin** `aDeclaredSizeBelowThePaddingKeepsTheFrameWhereCSSFloorsTheBox` — `Box { Box().width(10).height(10) }` with `.width(10).height(10)` and `Style.padding` 12: legacy 34×34, lowered 10×10 with the child at (12, 12) (P1) | `box.padding.floor` | **M3c** the lowered frame given `max(size, padding sum)` |
| 3.4 | `aMarginLowersAsPaddingOutsideTheItem` — asymmetric px and rem margins on a fixed child in a `Row`, a `Column` and a `Stack`; a **stretched** item with cross margins (the line minus the margins — practices shape 9's "stretch × margins" pair); a **grown** item with main margins; agrees, element rects exclude the margin (P3) | `box.margin` | **M3d** the margin padding aliased (the element includes its margin); **M3e** the margin inside W (the stretched arm fills the line) |
| 3.5 | `aNegativeMarginOverlapsItsSibling` — `Row(center) { a20.margin(-8); b20 }` agrees (P4: a at −8, b at 4); **divergence pin** at −15 on 20, where SwiftUI's response clamps at 0 and CSS's margin box is −10 | reported | **M3f** negative margins clamped at registration |
| 3.6 | `anAutoMarginLowersAsZero` — characterization of the inert row: `margin(.auto)` via `Style` agrees (legacy resolves it to 0) | reported (`margin`) | **M3g** `.auto` reported |
| 3.7 | `percentagesStillReportByNameWithTheirOwner` — one arm each: `size.percent`, `padding.percent`, `border.percent`, `margin.percent`, `minSize.percent`, `maxSize.percent`, `gap.percent`, `flexBasis` (fraction); `try #require` on the arm count | — (each already reports, some under an older name) | **M3h** `margin.percent` lowered as 0 |
| 3.8 | kernel: `aNativePaddingPlacesItsChildAtTheChildsOwnSize` (`MetalUILayoutTests`) — a padding node placed in bounds larger than its answer (through a custom `ProposalLayout` placing it at 100×100) over a 20×20 leaf with insets (1, 2, 3, 4): child at (x + 4, y + 1), 20×20 (`SA-N` item 4) | stored at 100 − 6 × 100 − 4 | **M3i** bounds minus insets restored |
| amended | `negativePaddingIsAcceptedAndItsResponseClampsPerAxis` — its "pinned wrong on purpose" width re-derived: the −15 child stored at (25, 35) **20×20** (P2b). **Known hazard** (record §18, critic round 1): the stage-1 scratch of this change made the arm exit on `SIGTRAP`; the lane finds which checkpoint fires before writing the placement, and records it | — | M3i |

**Demo expectation**: legacy images 0 px; **preview images re-taken with the
real change**: expected 0 in all four (stage 1's scratch of `SA-N` item 4 read 0
in all 12, record §18); a non-zero image is a finding the lane explains against
a probe arm before continuing. The whole-demo exit literal (2.10) is re-run
unchanged.

### Lane 4 — justify distribution and reverse directions

Files: `LegacyLowering.swift` (`arrangeLegacyMainAxis`); tests
`LoweringDistributionTests.swift` (new); amended
`stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` (its
`space-*` and reverse arms move here) and
`aContainersReportListsItsContainerRowsBeforeItsEveryNodeRowsAndTrapsOnTheFirst`.

| # | test | red before | mutation |
|---|---|---|---|
| 4.1 | `spaceBetweenLowersToSpacersAtTheGap` — `Row`/`Column` × gap {0, 10} × three fixed children at 200 (J1, J2) and overflowing at 50 (J3); agrees | `box.justifyContent.spaceBetween` | **M4a** the spacer's minimum 0 whatever the gap (the gap-10 overflow arm) |
| 4.2 | `spaceAroundAndSpaceEvenlyLowerToSpacersWhileTheyFit` — around (J7) and evenly (J4) at gap 0; evenly and around at gap 10 (J8's rigid leaf); both axes; agrees | reported | **M4b** around's between-spacers not doubled; **M4c** the gap as `Spacer(minLength:)` instead of a rigid leaf (J5's answer) |
| 4.3 | **divergence pin** `spaceAroundAndSpaceEvenlyOverflowFromTheStartWhereCSSCentres` — three 20s at 40: lowered from x 0 (J9); legacy as `Alignment.swift` answers, which the lane reads before writing the literal (CSS's fallback for both is `center`, x −10) | reported | **M4d** the overflow centred |
| 4.4 | `aSpacerBesideAGrowingChildTakesNothing` — `Row { a.flexGrow(1); b }.justifyContent(.spaceBetween).width(200)`: a 180, b at 180 (J6; CSS free space 0); agrees | reported | **M4e** spacers given priority 0 (the grower shares) |
| 4.5 | `aReverseContainerPlacesItsChildrenFromTheMainEnd` — `rowReverse`/`columnReverse` × `justifyContent` {nil, center, flexEnd, spaceBetween} × gap {0, 10} at 200 (R1); agrees | `box.reverse` | **M4f** the node order not reversed; **M4g** the main factor not mirrored |
| 4.6 | `aReverseContainerOverflowsTowardItsMainStart` — two `flexShrink(0)` 80s in a `rowReverse` 100: a at 20, b at −60 (R2); agrees | reported | M4g |
| 4.7 | `reversingKeepsIdentityPaintOrderHitOrderAndAccessibilityOrder` — a reverse row of three clickable, labelled boxes with `@State`: `stateSlotsEqual`, `scenesEqual` (emission order), `hitboxesEqual`, `accessibilityEqual`; agrees | reported | **M4h** the children's *group* order reversed before registration (ids and paint order move) |
| 4.8 | **characterization** `aLoweredRowOrColumnSpacesByItsDeclaredGapNotTheStackDefault` (`LR-AL`) — `Row { a; b }` lowered with spacing 0 (the explicit `Style.gap`), not `nil` (8, stack-algorithms S); agrees with legacy | green on arrival | **M4i** the lowered stack given `spacing: nil` when the gap is 0 |

**Demo expectation**: legacy 0 px; preview 0 px.

### Lane 5 — `hidden()`

Files: `LegacyLowering.swift` (a `display: .none` node lowers and joins
`hiddenNodes`), `Frame.swift` (`hiddenNodes`, `isHidden`; `suppressingAccessibilityIfHidden`
and the root check in `render` read `isHidden`), `ElementGroup.swift`
(`Element.prepaintGroup` registers the subtree under the existing
`hitTestingDisabled` scope and `Element.paintGroup` skips `paint` when
`isHidden`; `AnyElement`'s entry mirrors both **and** gains the accessibility
suppression it lacked, record §18 finding), `ModifiedElement.swift` (the same
per inner layer, `MC-B`); tests `LoweringHiddenTests.swift` (new); amended
`aHiddenFrameLayerIsReportedAsDisplayNone` (→ lowers),
`everyStageOneUnlowerableNodeFieldIsReportedByNameOnALeaf` and
`aContainersReportLists…` (`display.none` alone arms), and 4.1's hidden arm.

| # | test | red before | mutation |
|---|---|---|---|
| 5.1 | **divergence pin** `aHiddenElementKeepsItsSpaceUnderTheProposalAuthority` — `Column { a20; b20.hidden(); c20 }`: legacy c at y 20, lowered c at 40 (H1, H2), for a hidden `Box`, `Text`, `Row`, frame layer and padding layer | `box.display.none` (and per site) | **M5a** a hidden node lowered as a 0×0 leaf |
| 5.2 | `aHiddenElementPaintsNothing` — a hidden backgrounded `Box` containing a `Text`, and a hidden two-layer chain: the lowered scene has no rect or glyph from the subtree; the legacy scene has none either (0-size rects are not emitted — the lane checks this before writing the assertion, and pins the legacy side's actual emissions if it is wrong) (V1) | reported | **M5b** `Element.paintGroup`'s skip removed; **M5c** the inner-layer mirror removed |
| 5.3 | `aHiddenClickTargetTakesNoClickAndTheClickReachesWhatIsUnder` — through `WindowPair` (pre-flighted, `LR-AA`): a hidden `onClick` box over a visible one; the click runs the lower handler under the proposal authority (V3) | reported | **M5d** the `hitTestingDisabled` scope removed |
| 5.4 | `aHiddenElementIsNotPublishedToAnAccessibilityClient` — lowered hidden `Box`, `Text`, inner frame layer and an `AnyElement`-wrapped element with an accessibility client active: no record (accessibility-bridge-rules R9, `AB-O`); the legacy side unchanged | reported | **M5e** `suppressingAccessibilityIfHidden` reads `display` only; **M5f** `AnyElement`'s suppression removed |
| 5.5 | **characterization** `aHiddenFocusableElementStillTakesKeysUnderBothAuthorities` — `.focusable().onKey{…}.hidden()` still receives keys (CLAUDE.md's `hidden()` row; SwiftUI unprobed, owner task 12) | green on arrival | **M5g** the focus registry gated on `isHidden` |

**Demo expectation**: legacy 0 px; preview 0 px. The exit test re-runs
unchanged (the demo has no `hidden()`).

## 7. The exit test (`LR-AN`)

`theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` keeps its name and
file (`LoweringCorpusTests.swift`), is rewritten in lane 2, and is re-run by
lanes 3–5. `demoContent()` imported from `MetalUIDemoContent`, 920×560 in the
harness root, diagnostics on, animation off:

1. **Modal off**: `report.unlowerable == [list.noLowering, scrollView.noLowering]`
   exactly (P3 measured this order). **Modal on**: `[stack.position,
   stack.inset, list.noLowering, scrollView.noLowering]`. No stage-2 field
   entry, as an array equality, not a multiset.
2. **Every disagreement is a literal with its cause.** `try
   #require(report.elements == 2036)` (modal off), 6 agreeing; the 30
   disagreeing rects written as literals (legacy and lowered), grouped in the
   doc comment by cause, each cause with a named pin that reproduces it in
   isolation:

| cause | probe arm | isolating pin | P3's rows (legacy → lowered) |
|---|---|---|---|
| **R** the harness root offers its proposal (divergence 53) and the demo's greedy column fills it | stack-algorithms A5; stage-2 X4 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent`, 1.7 | outer padding layer 920×439 → 920×560; outer column 888×407 → 888×528; body row 888×310 → 888×431; the heights of the sidebar and main-pane layers and the main column; the scroller `Box` 0 → 73 tall |
| **55** a declared 196 sidebar is served first where CSS shrinks it to 88 | F5; stack-algorithms G9, G4r | 2.9 | sidebar layer 88 → 196 wide; its column and five children 60 → 168 wide; main-pane layer x 116 → 224, 788 → 680 wide; main column 756 → 648; every main-pane descendant x + 108; "Text renders" 756 → 648 wide; the paragraph 756×48 → 648×64 (one more line at the narrower width); the scroller `Box` y 439 → 455 |
| **X9** a stretched single-child container does not stretch its child (`LR-AC`) | X9 | 1.3 | the sidebar column 282 → 160 tall |
| **3** `ScrollView` has no lowering | — (site-level) | stage 3 | the `ScrollView`'s two recorded ids |
| **4** `List` has no lowering | — (site-level) | stage 4 | the `List` (420×14000 → 0×0) |

   The lane re-measures and writes the table from its own run; P3's figures are
   the prediction it checks first, and any row that does not fall under one of
   these five causes is a finding recorded before the literal is written.
3. **Modal on**: the same assertions with 2042 ids and 36 disagreeing — the six
   extra rows are the modal's `Stack` (site-level `position`/`inset`, stage 5)
   and its descendants.

Mutations that must redden it: **M1a** (stretch not aliased), **M2a** (grow on
the cross axis), **M1d** (the elision removed: the X9 row moves), and **M5c′**
= stage 1's **M5c** re-spelled for stage 2 (the `flexGrow.weights` check always
reporting: the report literal moves).

## 8. Demo, pixels and captures

At the end of **every** lane, against `cb2e708`, the twelve `CN-R` images (eight
legacy demo, two preview, two 560²), generated by the harness that imports
`MetalUIDemoContent` (`gen-lib.py`, record §18) into a `git archive` of the
lane's commit, controls read non-zero first (light vs dark 1 048 576; default vs
modal 1 030 498; default vs animation 210 027; f0 vs f3 0; preview light vs dark
1 048 576). Expected: **0 in all twelve at every lane**; lane 3 is the only lane
whose change reaches a production root (the preview, through `SA-N` item 4),
and a non-zero preview image there is a finding explained against a probe arm.
Stage 1's two-authority chrome pair is re-taken with `CounterPanel()` (lane 1)
and must read 0 with M5d as its control.

**Real-window captures.** Before any capture: `xcrun swiftc -O
docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate`;
capture only if it prints no `CGSSessionScreenIsLocked` line and
`displayAsleep main: 0`, then `docs/probes/window-capture/capture.sh <scratch
dir> cb2e708 <lane HEAD>` and record its table. `IOConsoleLocked` is not read
(`FR-V`). At design time the probe read locked and asleep; no capture was taken.

## 9. Deferred, each with an owner

| item | why not stage 2 | owner |
|---|---|---|
| percentages: `size`, `padding`, `border`, `margin`, `gap`, `minSize`/`maxSize`, `flexBasis(fraction:)` (`FR-H`/`FR-T`) | SwiftUI has no parent-relative spelling (C1); each call site needs a respelling decision | stage 8 (recipe), stage 10 (deletion) |
| `maxSize` on a non-greedy axis | SwiftUI's maximum is greedy (X10, frame probe D4); the recipe converts `.maxWidth` to `.frame(maxWidth:)` and takes that answer | stage 8 |
| `flexBasis` with a non-zero length | no SwiftUI spelling (an ideal is used only at a nil proposal; a stack never proposes nil on its main axis) | stage 8 / 10 |
| unequal `flexGrow` weights | no SwiftUI spelling | deleted concept, stage 10; tests retired in 7b |
| overflow compression in production (divergence 55) | lowered to SwiftUI's answer here; production gains it at the root switch | stage 6b |
| `Row`/`Column` default spacing (divergence 52) | a spelling default, not a lowering (`LR-AL`) | stage 8 |
| `Text`/`ProposalText` measurement: the below-word answer (T3/T4, divergence 59) and W2 | one measurement already serves both on the proposal path (`LR-F`); the below-word answer is a character-wrapping rule the probe has not characterized (W2 disagrees with and without a clamp) | the legacy `textMeasure` deletion: stage 9; the below-word answer and W2: task 11 (`LR-AM`) |
| `hidden()` and focus/keys | SwiftUI unprobed | task 12 |
| `alignItems.baseline` / `alignSelf.baseline` | no baselines | task 11 |
| `Stack`/`ZStack` stretch fidelity beyond §4.1 (a greedy child in a hugging stack, X4) | pinned as a divergence here | stage 6b (root and demo re-spelling) |
| lane-5 verifier minor 2: `compareInWindows` has no caller | stage 2's window tests use `WindowPair` directly | the integrator (delete it, amend `LR-AA`) |
| lane-5 verifier minor 1: 5.8's doc comment and the 88/89 boundary | untouched by stage 2 (no item frame in that chain) | stage 6b's depth re-bisection |
