# Engine replacement — design (plan task 7), with stage 1 in detail

Plan task 7 (`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`): *"Port
advanced layout, then remove the legacy engine. … Migrate the remaining
elements off `FlexEngine` (including a windowed proposal `List` and a proposal
portal for `Deferred`), delete the CSS layout paths and dead `Style` fields, and
replace browser-fixture goldens with SwiftUI probes or deterministic native
layout tests. No production layout request may pass through the legacy engine
after this task."*

Rulings are `LR-A`… in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md);
the measurements behind them are in `docs/record/18-engine-replacement-stage-1.md`.
Probe: `docs/probes/swiftui-engine-replacement-stage1.swift` (arm names T, B, H,
S, G below are its). Branch `feat/engine-replacement` from `c2290fc`.

**This task does not fit one run.** This document is (1) the inventory of
everything that still reaches `FlexEngine`, (2) the whole task as ordered,
independently mergeable stages, and (3) stage 1 in implementable detail. Stage
1 deletes nothing, retires no golden, and moves no demo pixel.

## Contents

1. [Baseline](#1-baseline)
2. [Inventory: what reaches the legacy engine](#2-inventory-what-reaches-the-legacy-engine)
3. [The migration shape (`LR-A`)](#3-the-migration-shape-lr-a)
4. [The whole task, as stages (`LR-L`)](#4-the-whole-task-as-stages-lr-l)
5. [Stage 1: lowering foundation](#5-stage-1-lowering-foundation)
6. [Stage 1 lanes](#6-stage-1-lanes)
7. [Demo comparison (`LR-M`)](#7-demo-comparison-lr-m)
8. [Deferred to later stages (`LR-N`)](#8-deferred-to-later-stages-lr-n)

---

## 1. Baseline

At `c2290fc`, measured 2026-09-16 in `/Users/maxburger/Developer/MetalUI-engine`:

| measure | value | how |
|---|---|---|
| suite | **1357 tests**, passed; 0 `error:`; the only `warning:` is SwiftPM's deprecation notice; only `regenerateAllGoldens` and `aListsWorkIsTheSameFor100kRowsAsFor500` skipped | `swift build --build-system native --build-tests`, then `swift test --build-system native --no-parallel` |
| goldens | **97** (`flex_` 69, `stack_` 14, `sizing_` 9, `abs_` 5) | `find Tests -name "*.json" \| wc -l` |
| typecheck guards | **70** (13 files; `UnitSafetyTests`' third hit is a comment) | per-file `grep -c canTypecheck` |
| demo harness controls | light vs dark **1 048 576**; default vs modal **1 030 498**; default vs animation **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576** | `CN-R`'s harness (`scratchpad/harness/gen.py`), 1024², `FakePlatformWindow`; the same figures record §16/§17 read |
| screen lock | `IOConsoleLocked` `<false/>`, **but** `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` (20:36 PDT) | `docs/probes/appkit-screen-lock-state.swift`; `FR-V`: the session dictionary decides, so no real-window capture was attempted |

## 2. Inventory: what reaches the legacy engine

### 2.1 Engine entry points

| entry | production callers | test callers |
|---|---|---|
| `MetalUILayout.computeLayout(_:root:available:rootFontSize:)` (`FlexEngine.swift:95`) | **1**: `Frame.computeRootLayout` (`Frame.swift:1608`), taken whenever the root node is not native | 16 files in `MetalUILayoutTests` call it directly (216 call sites) plus `ElementLayoutTests` (1) |
| `LayoutTree.newNode(style:children:)` / `newLeaf(style:measure:)` | 1 each, through `Frame.requestNode`/`requestLeaf` | 24 test files |
| `LayoutTree.setStyle` / `style(_:)` | `Frame.setStyle` (Component amend), `Frame.style` (Component amend; `display: none` checks at `Frame.swift:1092` and `:1804`) | — |

**Measured flow** (scratch instrument, whole suite, reverted; record §18 "Instrument"):
in one unfiltered run the element pipeline laid out **2 414 legacy roots** and
**237 native roots**; `computeLayout` ran **4 443** times in total, so **2 029**
runs came straight from `MetalUILayoutTests`. Legacy nodes registered, by
calling file: `Box.swift` **70 166**, `ModifiedElement.swift` **12 401**,
`Text.swift` (leaves) **12 061**, `ScrollView.swift` **1 124**, `Stack.swift`
**56**, `Component.swift` **32**; custom elements defined in 24 test files
**18 533** nodes and **3** leaves (`MeasurePerformanceTests` 17 494 of the nodes).

### 2.2 Legacy registration sites in `Sources/`

| site | registers | reaches it | load-bearing for |
|---|---|---|---|
| `Box.requestLayout` (`Box.swift:87`) | `requestNode(style:)` after `animated(…)` | `Box`, `Row`, `Column` (wrap a `Box`), `List` (a `Box` of a spacer `Box` and row `Box`es), the demo's `CounterPanel` | the demo root, `List` windowing, `$anim` |
| `Stack.requestLayout` (`Stack.swift:106`) | `display: .stack` node | `Stack` | demo stack cluster, modal scrim |
| `ScrollView.requestLayout` (`:316`, `:327`) | content node + viewport node, each with its own `$anim` prefix | `ScrollView` | `ScrollContext`, `List`, wheel routing, divergences 11/15/16/54 |
| `ModifiedElement.requestLayout` (`:220`, `:228`) | one node per layer; frame layers lowered to a one-cell stack (`CN-N`) | every legacy `.padding`/`.frame` | identity levels (`MC-C`), divergence 20 |
| `Text.requestLayout` (`Text.swift:236`) | `requestLeaf` with `textMeasure` (tokenizer min-content, `TX-F`) | `Text` | text wrapping, shaping counts |
| `StyledComponent.requestGroupLayout` (`Component.swift:432–436`) | `setStyle` (amend) and `requestNode` (wrap) on each member | a `Component`'s `.width`/`.height`/`.padding` | `CO-U`, `OM-D`/`OM-F`, divergences 48/56 |
| `LayoutPass.requestNode`/`requestLeaf` (public) | — | any custom `Element` outside the module | `SA-F`'s migration table |

Layout-transparent (no node, forward their content's): `Deferred`,
`EnvironmentScope`, `AnyElement`, `Component` (unmodified), the builder products
(`Pair`, `OptionalGroup`, `ArrayGroup`, `EmptyGroup`).

### 2.3 `Style` readers outside the engine

| reader | fields | why |
|---|---|---|
| `AnimatedStyle.swift` (27 lines) | 28 animatable keys over `size`, `minSize`, `maxSize`, `inset`, `flexBasis`, `margin`, `padding`, `border`, `gap`, `flexGrow`, `flexShrink` | the layout-phase animation helper (`AN-`) |
| `Frame.suppressingAccessibilityIfHidden`, `Frame.render` root | `display` | `AB-O`/`AB-AD` |
| `ModifierLayer.lowered` | `display` | `CN-N` and the `hidden()` fix `ed5fbc2` |
| `StyledComponent` | whole `Style` (amend) | `CO-U` |
| writers: `FrameLayer.style()` (19 lines), `List` (row/spacer styles), `ScrollView` (content/viewport), `Flex.swift`, `Stack.init`, `Box.swift`'s 29 modifiers | — | — |

### 2.4 Public CSS-shaped API and its callers

`StyledElement` requires `style`; `Box.swift` declares 29 `Style`-writing
modifiers. Call sites (non-comment `.<name>(`), demo / `Sources/MetalUI` / `Tests`:

| modifier | demo | Sources | Tests |
|---|---|---|---|
| `width` / `height` | 10 / 13 | 0 | 557 / 519 |
| `minWidth` `minHeight` `maxWidth` `maxHeight` | 0 1 0 0 | 0 | 2 7 2 2 |
| `margin` / `gap` | 0 / 0 | 0 | 5 / 6 |
| `justifyContent` `alignItems` `alignContent` `flexWrap` | 3 10 0 0 | 0 | 3 35 1 1 |
| `flexGrow` `flexShrink` `flexBasis` `alignSelf` | 10 0 1 2 | 0 | 12 18 9 5 |
| `position` / `inset` / `hidden` / `flexDirection` | 1 / 1 / 0 / 0 | 0 | 5 / 4 / 27 / 4 |

Legacy element spellings in `Tests/` (occurrences / files): `Box(` 651/54,
`Box {` 77/19, `Row(` 71/14, `Row {` 289/28, `Column {` 85/23, `Stack {` 126/27
(the `Stack(` count, 168/21, includes `HStack(`/`VStack(`/`ZStack(`),
`ScrollView(` 95/23, `List(` 56/15, `Deferred {` 16/9, `Text(` 141/29 (this pattern also matches `ProposalText(`); `Style()`
651. Proposal spellings: `HStack` 130/21, `VStack` 69/8, `ZStack` 48/10,
`ProposalScrollView` 35/4.

### 2.5 CSS-only engine files (`Sources/MetalUILayout`, 6 204 lines total)

`FlexEngine.swift` 2 893, `ResolveFlexibleLengths.swift` 316, `Alignment.swift`
235 (flex main/cross distribution), `FlexBaseSize.swift` 178, `LayoutContext.swift`
165, `Resolve.swift` 142, `Style.swift` 139, `FlexLines.swift` 116, and the
legacy half of `MeasureFunction.swift` (48: `AvailableSpace`, `MeasureFunction`).
Shared with the kernel: `LayoutTree.swift` (1 510; `styles` rows are still
appended as placeholders for native nodes), `Rounding.swift` 72. Kernel-only:
`NativeLayoutRun.swift`, `ProposalLayout.swift`, `ProposalSpacing.swift`,
`ProposedSize.swift`. Outside the layout module the CSS measure is
`Text.swift`'s `textMeasure` and the tokenizer min-content path it drives (`TX-F`).

### 2.6 Goldens by consuming test file

`GeneratorTests` (all 97: regeneration and `committedGoldensMatchTheBrowser`),
`OracleTests` (1). Assertion consumers: `FlexEngineTests` 16, `WrappingTests` 17,
`StackFixtureTests` 15, `FreezeLoopTests` 13, `BoxModelTests` 12,
`SizingFixtureTests` 9, `FitContentFixtureTests` 6, `AbsoluteFixtureTests` 5,
`ContentSizingFixtureTests` 4 — 97.

### 2.7 What the default demo needs that does not lower today

Measured on the demo's own tree minus its scroll area (`CounterPanel` and the
`ScrollView`/`List`/`Deferred` box replaced by a sized `Box`), through the stage-1
prototype with diagnostics on (record §18, "Scratch differential"): **21
elements, 0 agreeing rects**, and the fields with no lowering were
`alignItems: stretch` ×8, `flexGrow` ×8, `flexBasis` ×1, `alignSelf(.flexStart)`
×1 (that prototype lowered `minHeight` as a frame; stage 1 does not, `LR-E`). The
scroll area adds `ScrollView`, `List`, `Deferred`, `position(.absolute)` and
`inset`.

---

## 3. The migration shape (`LR-A`)

**Lower in place, per root.** Every legacy element keeps its type, its
`prepaint` and its `paint`; only the `requestLayout` branch that registers
nodes changes, and which branch runs is decided by the **layout authority of
the frame**, not by the element. Under the legacy authority (the default, and
the only one production uses until stage 6) nothing changes. Under the proposal
authority each legacy element registers kernel nodes, and a tree that contains
anything with no lowering yet traps, naming the element and the field.

Why this and not the alternatives (full reasoning and figures in `LR-A`):

- **The pipeline after layout is engine-agnostic.** Hit testing, focus,
  accessibility records, decoration paint, `@State` slots and `$anim` all read
  `pass.bounds(of: node)` and ids, never the engine. Measured on a clickable,
  focusable, labelled counter chrome lowered by the prototype: scene rects,
  glyph sprites, hitboxes, accessibility emissions, per-element bounds and the
  `StateTable` entry count were identical to the legacy tree, and a one-point
  lowering change (stack spacing + 1) made rects, glyphs, hitboxes and bounds
  differ — the control. The prototype's accessibility comparison read each
  emission's id, declared node and text but not its `geometry`, so it stayed
  equal under the control; lane 1's comparison includes `AXEmission.geometry`
  (test 1.9 is what proves it can differ). A width animated 196→320
  read 196, 196, **258** at t = 0, 0, 0.5 under both authorities.
- **Conforming legacy types to `ProposalElementGroup` instead is ruled out by
  measurement.** Adding only `Text: ProposalElement` and a conditional
  `Box: ProposalElement` produced **83 compile errors in 13 test files** and one
  in the demo (66 of them `ambiguous use of 'background'`, plus `opacity`,
  `allowsHitTesting` and three solver time-outs): the shared modifier spellings
  are unambiguous only because no built-in type is both.
- **Rewriting every caller onto the proposal vocabulary** would first need the
  proposal vocabulary to grow handlers, focus, key contexts, accessibility,
  decorations and animation — a second element pipeline.
- **Porting `FlexEngine` into a `ProposalLayout`** keeps CSS as the authority,
  which is what the task removes.

## 4. The whole task, as stages (`LR-L`)

Each stage merges on its own with the suite green. "Demo" is the twelve-image
`CN-R` comparison against the previous stage's merge.

| # | stage | depends on | delivers | exit test (named in its own design) | goldens | demo |
|---|---|---|---|---|---|---|
| **1** | **Lowering foundation** (this design) | — | per-frame layout authority; legacy registrars trap under it; bounds log; differential harness; lowering of `Text`, `Box`, `Row`, `Column`, `Stack` and `ModifiedElement` layers on the stage-1 subset (§5.4); pipeline parity pins | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` | 0 retired | 0 px |
| 2 | **Flex-item semantics onto SwiftUI's** | 1 | `flexGrow` → greedy main-axis frame (probe G1/G2); `alignItems`/`alignSelf` `.stretch` → greedy cross-axis frame (S1–S3); CSS `min`/`max` clamps (`FR-G`), `flexBasis`, `flexShrink`, `justifyContent` distribution, percentages (`FR-H`/`FR-T`), `margin`, `hidden()` (probe H: SwiftUI keeps the space), Style padding on a leaf, the `BM-4` floor; `SA-N` item 4 (padding places its child at the child's size); `Row`/`Column` default spacing (divergence 52); `ProposalText`/`Text` measurement unified; overflow compression (divergence 55) | the stage-1 test `theDemoOutsideItsScrollAreaReportsExactlyTheFieldsStageTwoOwns` rewritten to require **no** diagnostic, each remaining disagreement with a probe arm | 0 | 0 px (no default root changes) |
| 3 | **Scrolling and composition** | 1 (2 for stretch inside scrollers) | `ScrollView` lowered onto the kernel scroll viewport, **one** clamp/indicator implementation shared with `ProposalScrollView` (its private copies folded), `$anim-content`/`$anim-viewport`, `ScrollContext` from a native viewport, divergence 54; `Component` distribution without `setStyle` (amend → per-member frame, `OM-F`, divergences 48/56, a frame over a multi-member component); custom external elements' migration message | the `ScrollRoutingTests` and `ScrollIndicatorTests` scenarios re-run under the proposal authority | 0 | 0 px |
| 4 | **Windowed proposal `List`** | 3 | `List` lowered to a windowed `ProposalLayout` placing realized rows at `index × rowHeight` against the native `ScrollContext`; row identity (`TB-`), `AXTable` records (`AB-L`), `MP-I` cold-frame work, probe K6's layout answer | `aListsWorkIsTheSameFor100kRowsAsFor500` and the `ListTests` windowing arms under the proposal authority, counting work | 0 | 0 px |
| 5 | **Portal and absolute positioning** | 1, 3 | `Deferred` as a presentation root laid out against the window (probe P4/P5), `.position(.absolute)`/`.inset` lowered onto it or removed; divergences 9–11 | `DeferredTests` and `AbsoluteOverlayTests` under the proposal authority | 0 | 0 px |
| G | **Grids** | 1 | `Grid`/`GridRow` as probe-backed `ProposalLayout`s (task text: "grids") | its own probe's arms | 0 | 0 px |
| 6 | **Root switch** | 2, 3, 4, 5 | `Window`'s default authority becomes proposal; the demo is spelled for the semantics stage 2 changed, pixel changes deliberate and probe-backed; root placement ruled (divergence 4 vs `CN-J`); the human-verification rows that read demo layout re-opened | `noProductionFrameReachesTheLegacyEngine` (a `Window`-level counter that the legacy authority is never taken outside `@testable` construction) | 0 | **changes**, each difference named |
| 7 | **Goldens replaced** | 2 (the native equivalents exist) | each of the 97 goldens retired with a ruling naming the deterministic native test or probe arm that replaces it, or naming the CSS-only concept (wrap, reverse, margins, percent padding, absolute insets) that is deleted with it; `GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/` removed | `find Tests -name "*.json" \| wc -l` reads 0 and every replacement test is listed in the ruling | **97** | 0 px |
| 8 | **Deletion** | 6, 7 | `FlexEngine.swift`, `ResolveFlexibleLengths.swift`, `FlexBaseSize.swift`, `FlexLines.swift`, `Alignment.swift`'s flex half, `LayoutContext.swift`, `Resolve.swift`, the legacy `MeasureFunction`, `textMeasure`, the legacy registrars, the legacy authority and `Style`'s CSS fields; `width`/`height`/`min`/`max` moved onto the frame representation by `FR-F`/`FR-G`'s recipe; tests migrated | **mechanical check** (`LR-P`): plain-import typecheck guards that `computeLayout`, `LayoutPass.requestNode(style:children:)`, `LayoutPass.requestLeaf(style:measure:)` and `Style.flexGrow` do not compile, plus `grep -rn "FlexEngine\|computeLayout(" Sources` empty in the closeout record | — | 0 px against stage 6 |

Task 7's other clauses are already met on the proposal path — unspecified,
ideal, min/max, fixed-size, layout priority (task 2, task 4), compression and
expansion (`CN-B`), custom layouts (`SA-A`) — and reach legacy spellings through
stages 1–2. **Ideal on the legacy path** is stage 1 (lane 4).

## 5. Stage 1: lowering foundation

### 5.1 What stage 1 must leave true

1. Under the legacy authority every observable is byte-identical to `c2290fc`:
   the suite's existing 1357 tests pass unchanged except the one pin `LR-H`
   deliberately amends, and all twelve demo images read 0 differing pixels.
2. Under the proposal authority, every element in the stage-1 subset registers
   only kernel nodes, and the differential harness reports each element's rect
   either **equal** to the legacy engine's or **different by a named probe arm**.
3. Nothing outside the subset silently lays out: it traps (production) or is
   reported by name (harness diagnostics).
4. Identity, `@State`/`$focus`/`$anim`/`$ax` slots, hitboxes, focus,
   accessibility records and animation are identical between the two
   authorities on every agreeing tree (lane 5 pins).

### 5.2 API (all `internal`; `@testable` tests reach it)

```swift
// Sources/MetalUI/LayoutAuthority.swift (new)
enum LayoutAuthority: Sendable, Equatable { case legacy, proposal }

enum LoweringSite: String, Sendable { case box, stack, text, modifierLayer,
                                      scrollView, list, component, customElement }

struct UnlowerableField: Hashable, Sendable {
    let site: LoweringSite
    let field: String          // "flexGrow", "alignItems.stretch", "minSize.width", "requestNode", …
}

// Frame
init(contentSize:scaleFactor:…, collectsAccessibility: Bool = false,
     layoutAuthority: LayoutAuthority = .legacy,
     reportsUnlowerableFields: Bool = false,
     recordsElementBounds: Bool = false)
let layoutAuthority: LayoutAuthority
private(set) var unlowerableFields: [UnlowerableField]      // empty unless reporting
private(set) var elementBounds: [GlobalElementID: Bounds<Pixels>]  // empty unless recording
func unlowerable(_ field: UnlowerableField) -> LayoutNodeID  // traps unless reporting;
                                                            // reporting: records, returns a 0×0 native leaf

// LayoutPass
var lowersToProposal: Bool { frame.layoutAuthority == .proposal }

// Window
var layoutAuthority: LayoutAuthority = .legacy   // passed to every Frame it builds; a write marks dirty

// Sources/MetalUI/LegacyLowering.swift (new, lanes 2–4)
extension LayoutPass {
    /// Lowers one legacy node — `style` already animated — over native children.
    func lowerLegacyNode(_ style: Style, children: [LayoutNodeID],
                         site: LoweringSite, frameSpec: FrameSpec? = nil) -> LayoutNodeID
}

// Text.Layout gains `measuredNode: LayoutNodeID` (the leaf whose measured width
// paint wraps at; `node` stays the element's outer node). ModifierLayer gains
// `frameSpec: FrameSpec?`. Both are stored properties on public types: every lane
// that adds one runs `swift package clean` before its suite.
```

The trap message names both halves: `"MetalUI: <site>.<field> has no proposal
lowering (plan task 7, stage <n>); a tree containing it cannot run under the
proposal layout authority."`

Test support (`Tests/MetalUITests/LayoutDifferential.swift`, new):

```swift
@MainActor struct DifferentialRoot<Content: Element>: Element  // legacy: a topLeading Stack node W×H;
                                                               // proposal: native overlay(.topLeading) in a W×H frame
@MainActor enum LayoutDifferential {
    struct Report {
        var elements: Int
        var agreeing: [GlobalElementID]
        var disagreeing: [(id: GlobalElementID, legacy: Bounds<Pixels>, lowered: Bounds<Pixels>)]
        var legacyOnly: [GlobalElementID], loweredOnly: [GlobalElementID]
        var unlowerable: [UnlowerableField]
        var scenesEqual, hitboxesEqual, accessibilityEqual, stateSlotsEqual: Bool
    }
    static func compare<E: Element>(width: Float, height: Float, scaleFactor: Float = 1,
                                    _ make: @MainActor () -> E) -> Report
}
```

`compare` renders `DifferentialRoot { make() }` twice at W×H — legacy, then
proposal with diagnostics on — with `recordsElementBounds` and
`collectsAccessibility` on and separate `StateTable`s, and compares per id.

### 5.3 Why the harness root is a top-leading, fit-content root (`LR-D`)

Measured (record §18): with the twelve scratch trees rendered **directly** as
roots, **4 of 50** element rects agreed (all four in the `Stack` cluster, T3) —
the legacy root fills the window (divergence 4, `CS-I`) and the native root is
centred at its own answer (`CN-J`), so every descendant is offset. With the same
trees inside a top-leading fixed-size root on both paths, **57 of 62** agreed
(45 of 50 excluding the twelve harness roots), and the five disagreements traced
to fields outside the subset (T4: four rects, stretch and grow) or to a
probe-backed SwiftUI answer (T8: one rect, text hug, probe T7). Root placement is
stage 6's ruling, not the harness's.

### 5.4 The stage-1 lowering table (`LR-E`)

Order, innermost first: **content** (leaf / linear stack / overlay) → **native
padding** (from `Style.padding`) → **fixed frame** (from `Style.size`). This is
CSS's border-box (spec §5.2) spelled as SwiftUI: probe B1 places a 10×26 child at
(12, 12) inside `.padding(12).frame(60×60, .topLeading)`, and B3 reproduces the
counter chrome's legacy rects.

| `Style` field | lowering | otherwise |
|---|---|---|
| `flexDirection` `.row`/`.column` | native linear stack, horizontal/vertical (a leaf ignores it) | `.rowReverse`/`.columnReverse` → unlowerable `reverse` |
| `gap` (main axis; px, rem × `rootFontSize`) | stack `spacing`, explicit | `%` → unlowerable |
| `alignItems` `.flexStart`/`.center`/`.flexEnd` | stack cross alignment; and the size frame's cross alignment | `.baseline` → unlowerable (task 11) |
| `alignItems` `nil`/`.stretch` (a `Box`'s default) | **lowerable only where CSS cannot show it**: ≤ 1 child **and** no declared cross-axis size | else unlowerable `alignItems.stretch` (stage 2) |
| `justifyContent` `nil`/`.flexStart`/`.center`/`.flexEnd` | the size frame's main-axis alignment | — |
| `justifyContent` `.spaceBetween`/`.spaceAround`/`.spaceEvenly` | lowerable only with no declared main-axis size (no free space exists) | else unlowerable (stage 2) |
| `display: .stack` (`Stack`) | native overlay; alignment from `alignItems` × `justifyItems` (nine) | either `.stretch` → unlowerable |
| `display: .none` | — | unlowerable `display.none` (stage 2; probe H) |
| `size` px/rem | fixed native frame, alignment as above | `%` → unlowerable (stage 2, `FR-H`) |
| `padding` px/rem on a container, layer or childless `Box` | native padding inside the size frame | `%` → unlowerable; declared size below the padding sum on an axis → unlowerable `padding.floor` (`BM-4`); on `Text` → unlowerable (inert on legacy, stage 2) |
| `minSize`, `maxSize` | — | unlowerable (CSS clamps, `FR-G`; stage 2) |
| `margin`, `border`, `position`, `inset`, `flexWrap` ≠ `.noWrap`, `alignContent` ≠ nil, `flexGrow` ≠ 0, `flexShrink` ≠ 1, `flexBasis` ≠ `.auto`, `alignSelf` ≠ nil | — | unlowerable, by field name (stages 2, 5) |
| `aspectRatio`, `overflow`, `justifyItems` on a flex node; container fields on a leaf | ignored — the legacy engine ignores them too (inert table) | — |

**Not a diagnostic: overflow compression** (`LR-I`). A fixed-size child in a
container too small for it is shrunk by CSS (`flexShrink` 1, divergence 55) and
overflows in SwiftUI; the sizes are unknown at registration, so the harness
reports it as a disagreement and a lane-3 test pins it.

**Frame layers** (`LR-H`) lower from the layer's **animated** `Style` for what
`FrameLayer.style()` wrote (`size`/`minSize` for a fixed axis, finite `maxSize`)
plus `FrameSpec` for what `Style` cannot carry (ideal, infinite maxima,
alignment), onto the kernel's frame — which is SwiftUI's (`FR-A`/`FR-M`). So
under the proposal authority a lowered `.frame(minWidth: 40, maxWidth: 80)` over a
20pt child answers 80 at a 100pt proposal (probe D control; legacy 40,
divergence 35) and `.frame(maxWidth: .infinity)` fills on one axis (`FR-O`'s
inert arm). A frame layer whose `Style` was edited by a `Self`-returning
modifier after it in a way `FrameSpec` cannot express → unlowerable
`modifierLayer.style`.

**`Text`** (`LR-F`) lowers to a native leaf measured by `proposalTextMeasurement`,
amended to answer `min(widest line, proposed width)` — probe T2 (45×112 at 60),
T3 (0×592 at 0), T4 (5×592 at 5), T1/T5/T6 (one line at nil/1000/∞). Its declared
`size` wraps it in a fixed frame aligned `.topLeading`; glyphs are painted at the
element's bounds origin, wrapped at `measuredNode`'s measured width, which keeps
legacy glyph placement for `Text(…).width(w)` (SwiftUI would centre, T7 — that
belongs to stage 8's `.width` → `.frame` conversion).

## 6. Stage 1 lanes

Five lanes, in order; each lane's tests are written first and read red. "Red
before" for a lowering test means **a diagnostic in the report** (the harness
never traps), so no red run truncates the suite. Every mutation below is applied
after the lane's commit, from a `cp` backup, whole suite unfiltered, `git status
--short` empty afterwards, and reddens **at least** the tests named; the lane's
record names every test it actually reddens.

### Lane 1 — authority, traps, bounds log, harness

Files: `Sources/MetalUI/LayoutAuthority.swift` (new), `Frame.swift` (init
parameters, `unlowerable`, traps in `requestNode`/`requestLeaf`, bounds recording
at the root in `render`), `Passes.swift` (`lowersToProposal`), `Window.swift`
(`layoutAuthority`), `ElementGroup.swift` (record in `Element.prepaintGroup`),
`ModifiedElement.swift` (record per inner layer in `prepaintLayer`);
`Tests/MetalUITests/LayoutDifferential.swift`, `LayoutAuthorityTests.swift`,
`LayoutAuthorityCompileGuards.swift` (new). In lane 1 every legacy site under the
proposal authority reports `(<site>, "noLowering")`; lanes 2–4 replace that with
field-level entries.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aFrameAndAWindowDefaultToTheLegacyAuthority` | does not compile | **M1a** `Frame`'s default `.proposal` — the suite truncates (no summary line; practices shape 13); 1.1 filtered is red. Recorded as truncation, not as a count |
| 1.2 | `aWindowBuildsEveryFrameUnderItsLayoutAuthority` — a test `ProbeLeaf` (legacy leaf / native leaf per authority) logs `pass.lowersToProposal` through a real `Window` | does not compile | **M1b** `Window` builds its `Frame` without passing the authority |
| 1.3 | `aLegacyNodeRegistrationTrapsUnderTheProposalAuthority` (exit test; stderr names `requestNode`) | does not compile | **M1c** the trap replaced by the reporting branch |
| 1.4 | `aLegacyLeafRegistrationTrapsUnderTheProposalAuthority` (exit test) | does not compile | **M1d** as M1c for `requestLeaf` |
| 1.5 | `anUnlowerableSiteIsReportedByNameWhenDiagnosticsAreOn` — `ScrollView` and `List` (unlowerable through all of stage 1) report `(.scrollView, …)`, `(.list, …)` and the frame still completes | does not compile | **M1e** the site dropped from the record |
| 1.6 | `theElementBoundsLogRecordsTheRootEveryGroupMemberAndEveryInnerModifierLayer` — legacy authority; literal id count and rects derived by hand | does not compile | **M1f** inner-layer recording removed; **M1g** root recording removed |
| 1.7 | `theElementBoundsLogIsEmptyUnlessRequested` | does not compile | **M1h** recording defaults on |
| 1.8 | `theDifferentialHarnessSeesAOnePointDisagreementAtExactlyThatElement` — three `ProbeLeaf`s, one answering 21 wide only under the proposal authority; `try #require(report.elements == 4)` | does not compile | **M1i** `compare` renders the legacy authority twice |
| 1.9 | `theDifferentialHarnessComparesPaintHitboxesAccessibilityAndState` — a clickable labelled `ProbeLeaf` offset under the proposal authority: `scenesEqual`, `hitboxesEqual`, `accessibilityEqual` false, `stateSlotsEqual` true; unoffset: all true | does not compile | **M1j** the hitbox comparison returns `true` |
| 1.10 | `theDifferentialRootPlacesItsContentTopLeadingAtItsSizeUnderBothAuthorities` | does not compile | **M1k** the proposal-side root aligned `.center` |
| G1 | guard `aPlainImportCannotChooseTheLayoutAuthority` (`typecheckFile`, `SA-P`): `Window(…).layoutAuthority = …` does not compile outside the module | — (new guard) | **mutated red once**: `LayoutAuthority` and the property made `public` |

Lane 1 needs a `StateTable` id observable for 1.9: `StateTable.ids` (internal,
test observable; an inert-table row at Docs).

### Lane 2 — the lowering table's leaf half: childless `Box`, `Text`

Files: `Sources/MetalUI/LegacyLowering.swift` (new), `Box.swift`, `Text.swift`
(`Layout.measuredNode`; `swift package clean`), `ProposalText.swift`
(`proposalTextMeasurement`'s clamp); `Tests/MetalUITests/LoweringLeafTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aLoweredFixedSizeBoxAgreesWithTheLegacyBoxInEveryObservation` — px and rem arms, decorated and clickable | `(.box, "noLowering")` reported | **M2a** rem lowered as px (× 1) |
| 2.2 | `aLoweredBoxPaddingSitsInsideItsDeclaredSize` — padded sized (agrees, probe B1), padded unsized (agrees), size below padding (reports `padding.floor`) | reported | **M2b** padding placed outside the size frame |
| 2.3 | `everyStageOneUnlowerableStyleFieldIsReportedByName` — one arm per row of §5.4's "otherwise" column, on a childless `Box` and on a `Text`; `try #require` on the arm count | reported at site level only | **M2c** the `margin` check deleted |
| 2.4 | `everyIgnoredStyleFieldLeavesTheLoweredLeafUnchanged` — `aspectRatio`, `overflow`, `justifyItems` and the container fields on a leaf | reported | **M2d** `aspectRatio` reported |
| 2.5 | `aLoweredTextAgreesWithTheLegacyTextAtItsNaturalWidth` — short/long × 13/22pt × with/without `.foregroundColor`; bounds and glyph scene | reported | **M2e** the lowered leaf ignores `fontSize` |
| 2.6 | `aLoweredTextHugsItsWidestLineWhereTheLegacyTextFillsItsContainingBlock` — `Text(long)` in a 60-wide root: legacy 60, lowered the shaping cache's widest line at 60 (44 on the design machine; SwiftUI 45, T2), `try #require(legacy != lowered)` | reported | **M2f** the answer is the proposed width |
| 2.7 | `proposalTextAnswersItsProposalBelowItsNarrowestWord` — widths 0 and 5 answer 0 and 5 (T3, T4); nil answers one line (T1) | answers its widest glyph run | **M2g** the `min(…, proposal)` clamp removed |
| 2.8 | `aLoweredTextWithADeclaredWidthKeepsItsBoundsAndGlyphOrigin` — `Text(long).width(100)` and `.height(40)`: bounds and glyphs equal | reported | **M2h** the element's node returned as the leaf, not the frame |

Lane 2 also re-reads the preview images: the clamp only changes an answer below
a word's width, which no preview proposal reaches, so 0 differing pixels is
expected; a non-zero figure is a finding. Any existing `ProposalText` test that
reads an answer below a word's width changes with the clamp; the lane runs the
suite on the clamp alone first and lists each such test, with probe T3/T4 as the
reason, before writing its own.

### Lane 3 — containers: `Row`, `Column`, `Box` with children

Files: `LegacyLowering.swift`, `Box.swift` (the container branch; `Row`/`Column`
reach it through `box`); `Tests/MetalUITests/LoweringContainerTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | `aLoweredRowAndColumnAgreeWithTheLegacyContainersOverFixedChildren` — axis × gap {0, 10} × `alignItems` {start, centre, end} over three children of different cross sizes | reported | **M3a** cross `flexStart`↔`flexEnd` swapped; **M3b** spacing dropped |
| 3.2 | `aLoweredContainerSpacesItsChildrenByTheGapOnItsMainAxis` — `gap(horizontal: 4, vertical: 20)` on a row and a column | reported | **M3c** the gap's axes swapped |
| 3.3 | `aLoweredSizedContainerPlacesItsContentByJustifyContentAndAlignItems` — 100×60 × 3 × 3 | reported | **M3d** the frame's main and cross alignments swapped |
| 3.4 | `aLoweredContainerPaddingSitsInsideItsDeclaredSize` — the counter chrome's shape (B3) and a sized padded container | reported | **M3e** padding outside the frame |
| 3.5 | `stretchAndSpaceDistributionLowerOnlyWhereTheLegacyEngineCannotShowThem` — single-child auto `Box` (agrees), two-child stretch row, sized single-child stretch, `spaceBetween` with and without a main size, reverse, baseline | reported | **M3f** stretch always lowerable (the two-child arm reports nothing and disagrees) |
| 3.6 | `aLoweredRowOverflowsWhereTheLegacyRowShrinksItsChildren` — `Row { 80; 80 }.width(100)`: legacy 50/50, lowered 80/80 from x 0; `try #require` disagreement (divergence 55; stack-algorithms probe G1) | reported | **M3g** the size frame aligned `.center` (lowered x −30) |

### Lane 4 — `Stack` and `ModifiedElement` layers; ideal on the legacy path

Files: `LegacyLowering.swift`, `Stack.swift`, `ModifiedElement.swift`
(`ModifierLayer.frameSpec`; `swift package clean`), `FrameLayer.swift` (the
`FR-D` trap moves from `frame(minWidth:idealWidth:…)` to legacy registration);
`Tests/MetalUITests/LoweringStackAndLayerTests.swift`, and the amended pin in
`FrameSizingTests.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 4.1 | `aLoweredStackPlacesFixedChildrenAtAllNineAlignmentsAsTheLegacyStackDoes` | reported | **M4a** the overlay's horizontal and vertical factors swapped |
| 4.2 | `aLoweredStackOffersItsProposalWhereTheLegacyStackOffersFitContent` — `Stack { Text(long) }` in a 60 root: legacy text box 60, lowered its widest line; `try #require` disagreement (divergence 53, stack-algorithms A5) | reported | **M4b** each lowered child wrapped in a native `fixedSize` |
| 4.3 | `aLoweredPaddingLayerAgreesWithTheLegacyWrapper` — `.padding(4).padding(8)`, asymmetric edges, over `Box` and `Text`, with backgrounds | reported | **M4c** top and bottom insets swapped |
| 4.4 | `aLoweredFixedFrameLayerAgreesWithTheLegacyFrameOverAFixedChild` — nine alignments × child smaller and larger than the frame | reported | **M4d** frame alignment forced `.center` |
| 4.5 | `aLoweredFlexibleFrameLayerTakesSwiftUIsAnswerWhereTheLegacyFrameClamps` — `minWidth 40, maxWidth 80` over 20 in a 100 root (legacy 40, lowered 80; D control) and `maxWidth: .infinity` alone (legacy 20, lowered 100; `FR-O`) | reported | **M4e** the flexible frame lowered as a CSS clamp (child's size clamped) |
| 4.6 | `anIdealFrameLowersUnderTheProposalAuthorityAndStillTrapsUnderTheLegacyOne` — exit test at legacy **render**; proposal arm measured at a nil proposal answers the ideal (frame probe C1) | the construction trap fires first | **M4f** the ideal dropped from the lowering |
| 4.7 | `aFrameLayerLowersFromItsAnimatedStyleForWhatStyleCarries` — `.frame(width: 40)` animating to 80 reads the interpolated width under both authorities | reported | **M4g** lowered from `FrameSpec` alone |
| amended | `anIdealDimensionOnTheLegacyFrameTraps` — its closures now **render** under the legacy authority; stderr still names `idealWidth` | — | the lane records that its old spelling (construction only) goes green-by-success, which is the amendment's evidence |

### Lane 5 — the real-tree corpus and pipeline parity

Files: `Tests/MetalUITests/LoweringCorpusTests.swift`,
`LoweringPipelineParityTests.swift`; no `Sources/` change is expected.

| # | test | red before (on lane 4's tree) | mutation |
|---|---|---|---|
| 5.1 | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` — the counter chrome, the demo header and stack cluster in lowerable spelling, T5/T5b/T6/T7, a `ModifierCompositionProofTests` chain, and transparent groups (`if`, `for`, `EnvironmentScope`, `.disabled`, `AnyElement`); per tree `try #require(report.elements == N)` with N derived by hand | the corpus file does not exist; the lane runs each tree against lane 4 first and records any disagreement as a finding before writing the literal | **M5a** the proposal-side harness root proposes nil×nil; also re-run one mutation from each of M2–M4 and name 5.1 among the reddened |
| 5.2 | `theStageOneCorpusPinsEveryKnownDisagreementWithItsProbeArm` — T8 text hug (T7), `Stack` fit-content (A5), flexible frame (D), row overflow (divergence 55): literal rects on both sides, `try #require` disagreement | — | **M5b** a probe-backed branch reverted (M2f) reddens it |
| 5.3 | `theDemoOutsideItsScrollAreaReportsExactlyTheFieldsStageTwoOwns` — the §2.7 tree; the multiset of diagnostics as a literal the lane measures (the prototype's was stretch 8, grow 8, basis 1, `alignSelf` 1, before `minHeight` became unlowerable) | site-level only | **M5c** two-child stretch made lowerable (the count moves) |
| 5.4 | `aLoweredWindowDispatchesClicksFocusAndKeysToTheSameElements` — a real `Window` per authority; click "+" twice, focus, `Increment` action; the label reads the same count | — | **M5d** lowered stack spacing + 50 (the click misses) |
| 5.5 | `aLoweredWindowPublishesTheSameAccessibilityTree` — `FakePlatformWindow.publishAccessibilityTree` under both authorities | — | M5d |
| 5.6 | `aLoweredTreeMintsTheSameStateSlotsAndAnimatesTheSameWidths` — `StateTable.ids` equal; a `Box` width and a frame layer width at t = 0, 0, 0.5 read 196, 196, 258 under both (measured by the prototype for the `Box`) | — | **M5e** `lowerLegacyNode` given the style captured before `animated(…)` |

**Stage 1's exit test is 5.1**; 5.3 is stage 2's entry.

**Counts.** Stage 1 adds 11 + 8 + 6 + 7 + 6 = **38 tests**, one of them the
guard G1 (a guard is a `@Test` and counts toward the suite); the amended pin is
not new. Expected at the end: **1395 tests**, **97 goldens**, **71 guards** — to
be re-measured, not trusted.

## 7. Demo comparison (`LR-M`)

At the end of **every** lane, against `c2290fc`, the twelve `CN-R` images (eight
legacy demo, two preview, two 560²): **0 differing pixels, scene identical**.
Measured already for the lane-1–4 prototype built with the default authority:
12 of 12 read 0 (record §18).

- **The legacy images are not evidence for any lane.** No production root takes
  the proposal authority in stage 1, so a lowering change cannot reach them; they
  show only that the default branch moved nothing. The harness's power to see a
  change is the base controls in §1.
- **The preview images are evidence for lane 2 only** (the shared
  `proposalTextMeasurement` clamp), with 0 as the expected figure; their control
  is preview light vs dark.
- **Lane 5 adds two images** — the counter chrome rendered through a `Window`
  under each authority — expected equal, with the M5d mutant as the control
  that must differ.
- **Real release-window captures** only if the lock probe reads
  `CGSSessionScreenIsLocked = 0` and `displayAsleep main: 0` at that lane's end
  (`FR-V`); at design time it read locked.

## 8. Deferred to later stages (`LR-N`)

| item | stage |
|---|---|
| `flexGrow`, `flexShrink`, `flexBasis`, `alignSelf`, stretch with siblings or a declared cross size, `justifyContent` distribution with a main size, CSS `min`/`max` clamps, percentages, `margin`, `border`, `display: none`/`hidden()`, Style padding on a leaf, the `BM-4` floor, overflow compression (divergence 55), `Row`/`Column` default spacing (52), `SA-N` item 4, `ProposalText`/`Text` unification, reverse directions, `flexWrap`/`alignContent` (delete) | 2 (the last two: 8) |
| `ScrollView` lowering and the fold of `ProposalScrollView`'s private clamp/indicator; divergence 54; `Component` distribution (`setStyle`), divergences 48 and 56, a frame over a multi-member component; custom elements calling `requestNode` | 3 |
| windowed proposal `List`, `AXTable`, `MP-I`/`TB-AH`, probe K6 | 4 |
| `Deferred` as presentation; `position(.absolute)`/`inset`; divergences 9, 10, 11 | 5 |
| grids | G |
| root placement (divergence 4 vs `CN-J`), default authority, the demo re-spelled, human-verification rows | 6 |
| the 97 goldens, `GeneratorTests`, `OracleTests`, `Fixtures/`, `Oracle/` | 7 |
| deleting the engine, `Style`'s CSS fields, legacy registrars, `textMeasure`/tokenizer min-content, the legacy authority; `FR-F`/`FR-G`'s recipe; SwiftUI's centring of `Text(…).width(w)` (T7) | 8 |
| text-edge spacing, baselines (`alignItems.baseline`) | task 11 |
| two-axis scrolling | task 10 |
