# Proposal controls — controls in SwiftUI stacks, and a Component tree's stack — design

User request 2026-10-02, an item of the gpui-gap priority list (**not a plan
task**): the SMK configurator port's two high gaps,
**MG-1** (controls are not proposal elements, so `HStack { Button("x") {} }`
does not compile and a SwiftUI port is a rewrite into `Row`/`Column`) and
**MG-15** (a `Component`'s layout record holds its whole content type; the
configurator's debug build overflowed an 8 MB main-thread stack), written up
with reproductions in
`~/Developer/worktrees/smk_configurator/metalui-port/docs/superpowers/2026-10-06-metalui-gaps.md`.

Rulings: [`../2026-10-06-proposal-controls-decisions.md`](../2026-10-06-proposal-controls-decisions.md)
(`PE-A`…`PE-X`; `PE-T` is lane 2's measurement suspending `PE-L` item 4, `PE-U` its mutation table; `PE-V` (a `ProposalScrollView` publishes its `ScrollContext`) and `PE-W` (a ninth flipped guard, two measured spellings) and `PE-X` (lane 1's mutation table) are lane 1's; `PE-O`…`PE-S` are the critic pass's revisions and win where they differ). Probe: [`../../probes/swiftui-controls-in-stacks.swift`](../../probes/swiftui-controls-in-stacks.swift)
(its header's READING is the authority for every SwiftUI claim here). Record
(Record phase): `docs/record/78-proposal-controls.md`.

**In one paragraph.** The controls keep their types, their modifiers and
every line of their implementation. The SwiftUI-named containers switch their
content closure to a new result builder, `ProposalContentBuilder`, whose
`buildExpression` passes proposal content through untouched and wraps any
other element, group or `Component` in `LegacyContent<_>` — an identity- and
layout-transparent adapter that hands the stack the legacy element's native
nodes (`PE-B`, `PE-C`). Three greedy controls learn SwiftUI's answer to an
infinite proposal (`PE-D`), six proposal-only modifiers and `Pixels.infinity`
reach legacy content (`PE-F`). For MG-15, `ComponentLayout` moves its payload
into one heap box (`PE-J`): a shell over twelve panes costs 4.5 KB more stack
than one pane instead of 508 KB; what a compiler property leaves (an inline
`switch` in one builder) gets a rule and a debug-only meter that warns once
at 512 KiB (`PE-K`, `PE-L`) — **the warning is suspended by `PE-T`**: four
production trees measure above 512 KiB with the meter as landed.

---

## 0. Baseline (re-taken by the design session at `e54c3f6`)

| measure | value |
|---|---|
| `swift build --build-system native --build-tests` | 0 `error:`; the only `warning:` SwiftPM's deprecation notice |
| `swift test --build-system native --no-parallel`, unfiltered | **2546 tests in 3 suites** passed; `FR-J no-argument frame: succeeded=true` present |
| `swift build --build-tests` (default build system) | 0 `warning:` |
| native typecheck guards | 163 (record §77 §12; not re-counted by the design session) |
| `docs/divergences.md` | 96 live, next label **130** |
| SwiftUI probe | three runs, 95 lines byte-identical |

---

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory

- **The boundary.** `HStack`, `VStack`, `ZStack` (`NativeElements.swift`),
  `Grid`, `GridRow` (`Grid.swift`), `ProposalScrollView`,
  `ProposalLayoutContainer` and `ProposalLayout.callAsFunction` declare
  `Content: ProposalElementGroup` and take `@ElementBuilder` closures; the
  conformance list is `ProposalElementGroup.swift` ~181–193. `Button`
  (`Button.swift:46`), `Toggle`, `TextField`, `TextEditor`, `Picker`,
  `Slider`, `Stepper`, `List`, `Text`, `Box`, `Stack`, `ScrollView` are
  `Element, StyledElement`; `Menu` is menu content and an element through its
  pull-down (`PullDownMenu.swift`). `Divider`, `Image`, shapes, `Color`,
  `Spacer` are already `ProposalElement`s usable in both vocabularies.
- **Every node is native** since stage 9 (`LR-T`): a lowered legacy element
  registers kernel nodes through `lowerLegacyLeaf`/`lowerLegacyNode`, and
  records a `LoweredItem` that its parent consumes (`LR-AB`) or that is
  reported `…unconsumed` after the root returns (`LR-AQ`). The test-only
  `LegacyUnderProposal` (`LoweringItemTests.swift:91`,
  `GridLoweringInteractionTests.swift:73`) already places legacy content in
  proposal containers through the internal `ProposalNodeID` initializer, and
  `LoweringItemTests`' arms pin the reports it produces ("HStack Text
  flexGrow" → `text.flexGrow.unconsumed`).
- **Modifier overlap** (`PE-B`'s evidence): 37 names are declared on both
  `StyledElement` and `ProposalElementGroup`, 2 (`frame`, `background`) on
  both `ElementGroup` and `ProposalElementGroup`. On `ProposalElementGroup`
  only: `aspectRatio`, `clip`, `fixedSize`, the four `gridCell*`/
  `gridColumnAlignment`, `layoutPriority`, `scaledToFit/Fill`, the `native*`
  spellings and `onTap`.
- **Sizing code** the item touches: `TextField.requestLayout`
  (`TextField.swift:134`, the measurement `proposal.width.flatMap { $0.isFinite ? $0 : nil }`),
  `TextEditor.requestLayout` (`TextEditor.swift:122`, both axes),
  `Slider.size(proposedWidth:)` (`Slider.swift:~100`).
- **MG-15 code**: `ComponentLayout<C>` (`Component.swift:89`, stores
  `content` and `contentLayout` inline), `Component.requestGroupLayout`/
  `prepaintGroup`/`paintGroup` (`Component.swift`), the typed default
  (`ProposalNodeID.swift:~124`), `EitherGroup.Layout`/`Prepaint`
  (`ElementGroup.swift:~390`), `ElementBuilder` (`ElementBuilder.swift`).
- **Stack rules already in force**: Windows threads have 1 MB
  (`DemoStackBudgetTests.swift`, `everyProductionTreeBuildsOnAOneMegabyteThread`;
  the demo's build needs 528 KB on macOS arm64); "a debug build reserves a
  slot for every temporary a builder closure holds" (record §50).
- **The port**: `Sources/SMKConfigurator/Views/StatusBarView.swift` (the
  `Row(gap: 16)` status bar `ST0` mirrors) and every pane in `Views/`, written
  in the legacy vocabulary because of MG-1; `Views/KeyModeViews.swift`'s
  `pane { }` (`AnyElement(Box { … })`) is MG-15's workaround.

### 1.2 SwiftUI's answers (summary; the probe's READING is the authority)

| control | ideal (nil) | at ∞ | finite offer | class |
|---|---|---|---|---|
| `Button("Go")` | 41.50×24 | 41.50×24 | 41.50×24 | hugs |
| `.buttonStyle(.plain)` | 17.50×16 | same | same | hugs (the label) |
| `Toggle("Wi-Fi")` | 53.50×16.42 | same | w50: 43×32 (label wraps) | hugs |
| `TextField` empty / "Hello" | 47.50×24 / 43×24 | **∞×24** | w200: 200×24 | greedy width |
| `TextEditor` | 0×12 | **∞×∞** | w200: 200×12, h200: 0×200 | greedy both |
| `Slider` | 30×16 | **∞×16** | w200: 200×16 | greedy width |
| `Stepper("Qty")` | 50×24 | same | same | hugs |
| `Picker` `.menu` / `.segmented` / `.radioGroup` | 124.50×24 / 159.50×24 / 98×38.84 | same | w50: 50×64 / 118.50×64 / 50×150 | hugs |
| `Menu("Actions")` | 93×24 | same | w50: 50×24 | hugs |
| `Divider` (in a `VStack`) | 10×1 | ∞×1 | w200: 200×1 | greedy along |
| `List(selection:)` | 0×0 | ∞×∞ | w200: 200×0 | greedy both |
| `Text("A much longer label")` | 120.50×16 | same | w50: 49.50×48 | wraps |

Modifiers on a `Button` (FL15–FL20, MD0–MD4): `.padding(8)` adds 16 on each
axis (57.50×40), `.frame(width: 120)` fixes 120×24, `.disabled`, `.help`,
`.keyboardShortcut` change nothing, `.controlSize(.small)` 35×20,
`Toggle.frame(maxWidth: .infinity)` greedy width (FL21).

The form `FM0` (a `VStack(alignment: .leading)` of rows in a 400-wide
window, `.padding()`), the status bar `ST0` (600 wide) and the split arms
`SP0`–`SP2` are quoted with MetalUI's answers in §1.3.

### 1.3 MetalUI's answers (measured by the design session, scratch tests)

Measured through `LegacyUnderProposal` semantics (= `PE-C`'s adapter) with a
recording `ProposalLayout`, at `e54c3f6`; **bold** where `PE-D` changes it.

| control | zero | ideal | ∞ | w200 | h200 | w50 |
|---|---|---|---|---|---|---|
| `Text("Go")` / `ProposalText("Go")` | 0×16 | 17.23×16 | 17.23×16 | 17.23×16 | 17.23×16 | 17.23×16 |
| `Text(long)` / `ProposalText(long)` | 0×16 | 120.12×16 | same | same | same | 49.36×48 |
| `Button("Go")` | 24×24 | 41.23×24 | 41.23×24 | 41.23×24 | 41.23×24 | 41.23×24 |
| `.buttonStyle(.plain)` | 0×16 | 17.23×16 | same | same | same | same |
| `Toggle("Wi-Fi")` | 21×16 | 53.20×16 | same | same | same | 42.70×32 |
| `TextField` empty / "Hello" | 0×16 | 36.25×16 | **36.25×16 → ∞×16** | 200×16 | 36.25×16 | 50×16 |
| `TextEditor("Hello")` | 0×0 | 31.95×16 | **31.95×16 → ∞×∞** | 200×16 | 31.95×200 | 50×16 |
| `Slider` | 0×16 | 30×16 | **30×16 → ∞×16** | 200×16 | 30×16 | 50×16 |
| `Stepper("Qty")` | 28×24 | 49.58×24 | same | same | same | same |
| `Picker` `.menu` | 67×24 | 112.56×24 | same | same | same | 67×64 |
| `Picker` `.segmented` | 124.85×24 | 159.00×24 | same | same | same | 124.85×64 |
| `Picker` `.radioGroup` | 29×38 | 97.57×38 | same | same | same | 50×150 |
| `Divider` | 0×1 | 10×1 | ∞×1 | 200×1 | 10×1 | 50×1 |
| `Menu("Actions")` | 24×24 | 80.66×24 | same | same | same | 49.64×64 |
| `Button.padding(8)` | 40×40 | 57.23×40 | same | same | same | 49.63×48 |
| `Button.frame(width: 120)` | 120×24 | 120×24 | same | same | same | 120×24 |
| `Toggle.frame(maxWidth: ∞)` | 21×16 | 53.20×16 | ∞×16 | 200×16 | 53.20×16 | 50×32 |
| `Button.disabled(true)` | as `Button` | | | | | |

Every class matches SwiftUI's except the three bold infinite answers
(`PE-D`) and `List(selection:)`, which this table omits: SwiftUI's is greedy on
both axes (`FL14`), MetalUI's answers `rowHeight × count` — divergence 84,
kept (`PE-Q`; test 1.1 gains the row, measured by the lane). The remaining differences are metrics and below-ideal compression
(divergences 130, 131) and text widths (divergence 60).

**`FM0`** — MetalUI (today, through the adapter) vs SwiftUI; MetalUI's after
`PE-D` in the last column where it moves:

| element | SwiftUI | MetalUI e54c3f6 | after `PE-D` |
|---|---|---|---|
| row a | (16, 16, 368, 24) | (16, 16, 368, 16) | |
| label "Name" | (16, 20, 35.50, 16) | (16, 16, 35, 16) | |
| `TextField` | (59.50, 16, 324.50, 24) | (59, 16, 325, 16) | |
| row b | (16, 48.15, 368, 24) | (16, 40, 368, 24) | |
| `Toggle("Enabled")` | (16, 51.94, 70, 16.42) | (16, 44, 70, 16) | |
| `Button("Apply")` | (325, 48.15, 59, 24) | (325, 40, 59, 24) | |
| row c | (16, 76.89, 368, 16) | (16, 72, 227, 16) | **(16, 72, 368, 16)** |
| label "Speed" | (16, 76.89, 39, 16) | (16, 72, 39, 16) | |
| `Slider` | (63, 76.89, 321, 16) | (63, 72, 180, 16) | **(63, 72, 321, 16)** |
| `Picker` `.menu` | (16, 101.04, 124.50, 24) | (16, 96, 113, 24) | |
| `Divider` | (16, 133.04, 368, 1) | (16, 128, 368, 1) | |
| row f | (16, 142.04, 368, 24) | (16, 137, 368, 24) | |
| `Stepper("Qty")` | (16, 142.04, 50, 24) | (16, 137, 50, 24) | |
| form | (0, 0, 400, 182.04) | (0, 0, 400, 177) | |

Row origins differ by the `TextField`'s 16-vs-24 height (divergence 131) and
SwiftUI's text-derived extra spacing (CN-H's note); every horizontal fact —
who hugs, who takes the rest, the trailing `Button` at 384 − 59 — agrees
once `PE-D` lands.

**`ST0`** (the configurator's status bar) — SwiftUI vs MetalUI e54c3f6
(unchanged by this branch):

| element | SwiftUI | MetalUI |
|---|---|---|
| bar | (0, 0, 600, 26) | (0, 0, 600, 26) |
| dot group | (16, 6, 96, 14) | (16, 7, 96, 13) |
| dot | (16, 9.50, 7, 7) | (16, 10, 7, 7) |
| "USB Connected" | (29, 6, 83, 14) | (29, 7, 83, 13) |
| "Default · 5×14" | (128, 6, 74, 14) | (128, 7, 74, 13) |
| "4 layers" | (218, 6, 41.50, 14) | (218, 7, 41, 13) |
| "fw 1.2.3" | (275.50, 6, 40.50, 14) | (275, 7, 40, 13) |
| "keymap.json — unsaved changes" | (411, 6, 173, 14) | (411, 7, 173, 13) |

(13 vs 14: line advance at 11 pt, divergence 86.) **`SP0`/`SP1`**: two greedy
controls split 300 as (0, 146) + (154, 146) in both. **`SP2`**: Buttons
(0, 41) and (49, 107) vs SwiftUI's 41.50 and 107.50.

---

## 2. Public API

```swift
// Sources/MetalUI/ProposalContentBuilder.swift (new, lane 1)

/// The builder of a SwiftUI-vocabulary container's content: `ElementBuilder`,
/// plus one rule — proposal content keeps its type, and any other element,
/// group or `Component` is adopted as `LegacyContent` (`PE-B`).
@MainActor @resultBuilder
public enum ProposalContentBuilder {
    public static func buildExpression<E: ProposalElementGroup>(_ element: E) -> E
    @_disfavoredOverload
    public static func buildExpression<E: ElementGroup>(_ element: E) -> LegacyContent<E>
    public static func buildBlock() -> EmptyGroup                                    // forwards to ElementBuilder
    public static func buildPartialBlock<G: ElementGroup>(first: G) -> G            // forwards
    public static func buildPartialBlock<A: ElementGroup, N: ElementGroup>(accumulated: A, next: N) -> Pair<A, N>
    public static func buildOptional<G: ElementGroup>(_ group: G?) -> OptionalGroup<G>
    public static func buildEither<F: ElementGroup, S: ElementGroup>(first: F) -> EitherGroup<F, S>
    public static func buildEither<F: ElementGroup, S: ElementGroup>(second: S) -> EitherGroup<F, S>
    public static func buildArray<G: ElementGroup>(_ groups: [G]) -> ArrayGroup<G>
}

/// A legacy element, group or `Component` inside a SwiftUI-vocabulary
/// container — made by `ProposalContentBuilder`, never written by hand
/// (`PE-C`). Identity- and layout-transparent; a legacy item field on its
/// content is reported by name (`LR-AQ`).
public struct LegacyContent<Content: ElementGroup>: ProposalElementGroup {
    public var content: Content
    public init(_ content: Content)
    // requestGroupLayout / requestProposalGroupLayout / prepaintGroup / paintGroup
    // (GroupLayout == Content.GroupLayout, GroupPrepaint == Content.GroupPrepaint)
}

// The containers of PE-E: `@ElementBuilder content` → `@ProposalContentBuilder content`
// on HStack (both inits), VStack (both), ZStack (all), Grid, GridRow,
// ProposalScrollView, ProposalLayoutContainer.init, ProposalLayout.callAsFunction.
// Generic constraints unchanged (`Content: ProposalElementGroup`).

// Sources/MetalUI/LegacyProposalModifiers.swift (new, lane 1) — PE-F item 1
extension ElementGroup {
    public func layoutPriority(_ value: Double) -> ModifiedContent<LegacyContent<Self>, LayoutModifier>
    public func fixedSize(horizontal: Bool = true, vertical: Bool = true)
        -> ModifiedContent<LegacyContent<Self>, LayoutModifier>
    public func gridCellColumns(_ count: Int) -> GridCellModifier<LegacyContent<Self>>
    public func gridCellAnchor(_ anchor: ProposalAlignment) -> GridCellModifier<LegacyContent<Self>>
    public func gridCellAnchor(_ anchor: UnitPoint) -> GridCellModifier<LegacyContent<Self>>
    public func gridColumnAlignment(_ alignment: HorizontalAlignment) -> GridCellModifier<LegacyContent<Self>>
    public func gridCellUnsizedAxes(_ axes: ProposalAxes) -> GridCellModifier<LegacyContent<Self>>
}
// (Each is `LegacyContent(self).<the ProposalElementGroup spelling>`; the
// existing signatures on ProposalElementGroup decide the exact parameter
// lists — copy them, including fixedSize's overload set.)

// Sources/MetalUICore/Units.swift — PE-F item 2
extension Pixels { /// SwiftUI's `.infinity` … public static var infinity: Pixels { Pixels(.infinity) } }
```

Every new public declaration carries a doc comment and a row in
`docs/probes/closeout-inventory-map.tsv` (`ProposalContentBuilder` and its
methods **A** — SwiftUI's `ViewBuilder` role; `LegacyContent` **M**; the
`ElementGroup` modifiers **A**; `Pixels.infinity` **A**); the census is
re-recorded (`docs/probes/closeout-public-api.sh`). Lane 2 adds **no** public
declaration (`StackMeter` and `ComponentLayout`'s storage are internal).

---

## 3. Implementation — lane 1 (MG-1)

1. **`ProposalContentBuilder` + `LegacyContent`** (new file). `LegacyContent`'s
   untyped entry forwards `requestGroupLayout(under:at:pass:)` unchanged; the
   typed entry calls the same, then
   `pass.frame.lowering.droppingPresentations(nodes).map(ProposalNodeID.init)`;
   `prepaintGroup`/`paintGroup` forward. It records nothing, consumes nothing
   (`PE-C`). The builder's non-`buildExpression` methods call
   `ElementBuilder`'s (so lane 2's sampling covers both).
2. **Containers** (`PE-E`): the attribute change in `NativeElements.swift`
   (HStack/VStack/ZStack only — not ProposalFrame/Padding/Background/FixedSize),
   `Grid.swift`, `ProposalScrollView.swift`, `ProposalLayoutContainer.swift`.
   Rewrite `HStack`'s header paragraph ("Its content must resolve exclusively
   to native layout nodes … a legacy element does not satisfy …") to say what
   is true now; `ProposalNodeID.swift`'s header gains the second minting site
   (`PE-C` item 2) — not a hole.
3. **`PE-D`**: in the three measurement closures, an infinite proposed width
   (and, for `TextEditor`, height) is answered with infinity; `nil` keeps the
   ideal. Update each doc comment (Slider's "else 30" is then "30 at nil,
   infinity at an infinite offer (FL6)"). `SliderTests`'
   `aSliderIsGreedyOnTheWidthAndSixteenTall` last arm expects `.infinity`
   (cite `PE-D`). **Moved to lane 2 by `PE-O`** (it runs first and re-takes
   the fourteen images straight after this change; a moved image stops it).
4. **`PE-F`**: the seven `ElementGroup` spellings (new file) and
   `Pixels.infinity`.
5. **Flip the guards** of `PE-H`, each with its new `ProposalFrame` control —
   nine with `PE-W`'s `aCustomLayoutContainerAdoptsLegacyContent`
   (`ProposalLayoutCompileGuards.swift`).
5a. **`PE-V`**: `ProposalScrollView.requestProposalLayout` publishes its
   `ScrollContext` exactly as `ScrollView.requestLayout` does, so a `List`
   inside it windows (`ScrollChrome.swift`'s header corrected).
6. **Inventory**: map rows, census, `closeout-inventory-check.sh` and
   `closeout-undocumented.sh` print nothing.

Nothing else in `Sources/MetalUI` and nothing in `Sources/MetalUILayout`, `MetalUIScene`, `MetalUIRender`,
`MetalUIPlatform`, `Backends/SDL` or any shader changes.

## 4. Implementation — lane 2 (MG-15)

0. **`PE-D` first** (`PE-O`): §3 item 3 exactly, then the fourteen images
   re-taken before anything else lands; tests 1.9 and 1.23 in
   `GreedyControlSizingTests.swift` (1.9 measures each control through a test-local copy of
   `LoweringItemTests`' `LegacyUnderProposal` under a recording layout, and
   1.23 is a legacy `Row`, so neither waits for lane 1's builder).

1. **`ComponentLayout`** (`PE-J`): `struct Payload { var content: C.Content;
   var contentLayout: C.Content.GroupLayout }`, `final class Storage { var
   payload: Payload }`, `let storage: Storage`, `init(content:contentLayout:)`,
   `var content: C.Content { storage.payload.content }` (read-only),
   `func withPayload<R>(_ body: (inout Payload) -> R) -> R`. Both
   `requestGroupLayout` defaults (untyped `Component.swift`, typed
   `ProposalNodeID.swift`) build it with the initializer; `prepaintGroup`/
   `paintGroup` go through `withPayload`. The interrupted predecessor's patch
   is exactly this plus `indirect` on `EitherGroup`'s two enums — **drop the
   `indirect`** (`PE-J`). Update the `ComponentLayout` doc comment with the
   figures and the rule. Run `swift package clean` after the change.
2. **`StackMeter`** (`PE-L`, new file `Sources/MetalUI/StackMeter.swift`,
   internal, `@MainActor`): `measuring<R>(_ body: () throws -> R) rethrows ->
   (R, highWater: Int, deepestComponent: String?)`, `sample()`,
   `sample(component: Any.Type)`; a no-op unless
   `_isDebugAssertConfiguration()`; the stack address is
   `withUnsafeMutablePointer(to: &local)`, compared as `UInt` against the
   entry address (the stack grows down on every supported platform; say so in
   the comment). Nested `measuring` calls: the inner returns its own figure
   and folds into the outer. **`PE-P`**: `sample()` asserts no isolation
   (no `assumeIsolated`, no `dispatchPrecondition`) and counts only on the
   main thread (`Thread.isMainThread`) inside an open scope —
   `everyProductionTreeBuildsOnAOneMegabyteThread` runs every builder off
   the main thread.
3. **Samples**: every `ElementBuilder` static method; both `Component`
   layout entries (with the type); `Frame.requestNativeLeaf`.
4. **Suspended by `PE-T`** (four production trees measure above 512 KiB; the
   threshold is to be re-taken). As designed: **`Window`**: each frame's build-and-render runs inside
   `StackMeter.measuring`; above `Window.stackWarningThreshold` (512 KiB,
   internal static) the internal `stackWarningSink: (String) -> Void`
   (default: one line on standard error via `FileHandle.standardError`) is
   called **once per window**: `MetalUI: laying out this window used <N> KiB
   of stack (warning at 512 KiB; Windows threads have 1 MiB) — deepest
   Component: <type>. A switch or if over large inline subtrees grows a debug
   build's frames with every branch: give each branch its own Component
   (record §78).`
5. **Docs on the type**: `Component`'s doc comment gains the rule (`PE-K`).

## 5. Divergences (lane 3 writes the rows; lane 1 owns the pins)

| # | what | SwiftUI | MetalUI | ruling | pin | owner |
|---|---|---|---|---|---|---|
| 130 | controls below their ideal size | a Button compresses to 10×8 at a zero offer; a menu Picker and a Menu shrink to 50 (FL0, FL8, FL13) | the Button keeps 24×24 (strut and padding); the menu Picker keeps 67 and the Menu wraps its label at 50 | `PE-N` | test 1.1's `zero`/`w50` arms | none |
| 131 | control metrics | `TextField` 24 tall, ideal placeholder + chrome (47.50); menu Picker 124.50, Menu 93, Toggle 16.42 tall | `TextField` one line (16), ideal text/placeholder + 1 (36.25); menu Picker 112.56, Menu 80.66, Toggle 16 | `PE-N` | test 1.1's `ideal` arms | MG-20 |

Header: 98 live, next label 132; the dated history line names this branch.
`docs/record/04-divergences.md` gains the two sections (Record phase).

---

## 6. Tests

Every test names its red-before (what it does at `e54c3f6`) and the mutation
that must redden it; a lane commits before mutating, restores from a copy,
runs the **full unfiltered** suite per mutation, checks `git status --short`
and names every reddened test. **New typecheck guards are each mutated red
once.** No test sleeps; window tests drive `simulateTick`.

### 6.1 Lane 1 — `Tests/MetalUITests/ProposalControlsTests.swift`, `ProposalControlsCompileGuards.swift` (new)

Shared helpers in the new file: a recording `ProposalLayout` (`Ask`, as the
scratch: measures child 0 at zero, nil×nil, ∞×∞, 200×nil, nil×200, 50×nil),
`controlID`/`LayoutDifferential` from the existing support.

| # | test | asserts | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `everyControlAnswersInSwiftUIsClassInsideAProposalContainer` | §1.3's table after `PE-D`, row by row (each control inside `ProposalLayoutContainer(Ask())`), values to 0.01; each row's comment cites its FL arm and class; plus a `List(rows, rowHeight: 20, selection:)` row pinning MetalUI's measured `rowHeight × count` answers, citing divergence 84 (`PE-Q`) | does not compile (legacy content in a proposal container) | M1.1a: `TextField`'s infinite answer reverted → its ∞ arm; M1.1b: `Toggle` label gap +1 → its ideal arm (a non-`PE-D` arm can fail) |
| 1.2 | `proposalContentKeepsItsTypeAndLegacyContentIsAdopted` (guard, `typecheckFile`, plain import) | `let _: HStack<Pair<Spacer, Rectangle>> = HStack { Spacer(); Rectangle() }` and `let _: HStack<Pair<LegacyContent<Text>, Spacer>> = HStack { Text("a"); Spacer() }` both typecheck; control: `let _: HStack<LegacyContent<Spacer>> = HStack { Spacer() }` fails | `LegacyContent` does not exist | M1.2: delete the `ProposalElementGroup` `buildExpression` overload → the first line fails |
| 1.3 | `aSwiftUIVocabularyFormTypechecksWithAPlainImport` (guard) | one file, plain import: an `HStack`/`VStack`/`ZStack`/`Grid`/`GridRow`/`ProposalScrollView`/custom-layout tree holding `Text`, `Button`, `Toggle`, `TextField`, `TextEditor`, `Picker` (three styles), `Slider`, `Stepper`, `Menu`, `List(selection:)`, `Divider`, `Spacer`, an `if`/`else`, a `switch`, a `for`, a `ForEach` and a legacy `Component`; modifiers on controls `.frame(width:)`, `.frame(maxWidth: .infinity)`, `.padding(8)`, `.disabled(true)`, `.help`, `.keyboardShortcut(.defaultAction)`, `.buttonStyle(.plain)`, `.pickerStyle(.segmented)`, `.onHover`, `.layoutPriority(1)`, `.fixedSize()`, `.gridCellColumns(2)`, `.font(.system(size: 11))`; control: the same body inside `ProposalFrame { }` fails naming `ProposalElementGroup`; second control (`PE-R`): `Button("x") {}.padding(Edges(all: 8)).buttonStyle(.plain)` fails (a style modifier is written on the control) | fails | M1.3: `GridRow` back to `@ElementBuilder` → reddens |
| 1.4 | `aLegacyControlTakesTheIDAProposalElementWouldInItsPosition` | in `HStack { Rectangle(); Button("b") {}; Toggle(…) }` the Button's id is `.child(of: hstack, at: 1)` and the Toggle's `at: 2`, exactly the ids two `Rectangle`s take there; a legacy `Component` with `@State` inside a `VStack` keeps its value across three frames and across an `if` toggling a sibling before it | does not compile | M1.4a: `LegacyContent` passes a fresh cursor (`var c = 0`) → ids collide; M1.4b: it enters a group member level → ids shift |
| 1.5 | `aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt` | `FM0` in SwiftUI's spelling (`VStack(alignment: .leading) { HStack { Text; TextField }; HStack { Toggle; Spacer(); Button }; HStack { Text; Slider }; Picker.pickerStyle(.menu); Divider(); HStack { Stepper; Spacer() } }.padding(Edges(all: 16)).frame(width: 400).fixedSize(horizontal: false, vertical: true)`) at 400×300: §1.3's "after `PE-D`" literals; plus the probe's relations derived from the measured widths (trailing `Button` maxX = 384; `Slider`/`TextField` width = 368 − label width − 8; `Divider` 368); diagnostics report empty (pre-flight `try #require`) | does not compile; at runtime the `Slider` is 180 | M1.5: `Slider`'s `PE-D` reverted → slider 180 |
| 1.6 | `theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary` | `ST0` as the port would write it (`HStack(spacing: 16) { HStack(spacing: 6) { Circle().frame(width: 7, height: 7); Text("USB Connected") }; Text("Default · 5×14"); Text("4 layers"); Text("fw 1.2.3"); Spacer(); Text("keymap.json — unsaved changes") }.font(.system(size: 11)).padding(Edges(top: 0, right: 16, bottom: 0, left: 16)).frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)`) at 600×26: §1.3's MetalUI column | does not compile (`Text` in `HStack`, `.infinity`) | M1.6: `LegacyContent`'s typed entry returns `nodes.reversed()` — reddens only the test's second spelling (the middle labels as one `ForEach`, a multi-node adopted expression; `PE-X`) |
| 1.7 | `aLegacyItemFieldInAProposalStackIsReportedByName` | diagnostics: `HStack { TextField(…).flexGrow(1) }` → `[textField.flexGrow.unconsumed]`; `VStack { Text("a").margin(Pixels(4)) }` → `[text.margin.unconsumed]` | does not compile | M1.7: `LegacyContent` consumes its nodes' records (`frame.lowering.consume`) → `[]` |
| 1.8 | `aPresentationInsideAProposalStackTakesNoSlot` | `HStack { Text("a"); Deferred { Box().position(.absolute).inset(…) }; Text("b") }`: b's minX = a's maxX + 8, and the presentation root is laid out against the window | does not compile | M1.8: drop `droppingPresentations` → b's minX = a's maxX + 16 |
| 1.9 | `theGreedyControlsAnswerAnInfiniteProposalWithInfinity` | `TextField`/`Slider` at ∞×nil → ∞ wide, ideal at nil; `TextEditor` at ∞×∞ → ∞×∞, at nil → its ideal | red at `e54c3f6` (30, 36.25, 31.95) | M1.9a/b/c: each control's change reverted alone → its own arm |
| 1.10 | `textInAProposalStackLaysOutAsProposalText` | `HStack { Text(long); Text("b") }` vs the `ProposalText` spelling at 120×100 (wrapping): equal frames element by element; `HStack(alignment: .firstTextBaseline) { Text("A").font(.system(size: 20)); Text("b") }` equal to its `ProposalText` spelling | does not compile | M1.10: `Text.requestLayout` measures with `wrappingAt: nil` → wrapping arm |
| 1.11 | `aButtonInAProposalStackHasOneHitboxAndActsAsInARow` | in `HStack`, and in `Row` for comparison: one hitbox at the Button's frame; a click runs the action once; Tab focuses it; Space activates; `HStack { … }.disabled(true)` and `Button.disabled(true)` gate the click | does not compile | M1.11 (`PE-S`): `LegacyContent.prepaintGroup` runs its content's prepaint twice (a discarded first call; skipping is unwritable — it must return `Content.GroupPrepaint`) → two hitboxes at the Button's frame (the prepaint half, `OM-AI`) |
| 1.12 | `aControlInAProposalStackPaints` | the scene holds the Button's chrome rect and its label glyphs at its frame, as in a `Row` | does not compile | M1.12: `LegacyContent.paintGroup` skips its content (the paint half) |
| 1.13 | `accessibilityRecordsOfControlsAgreeAcrossVocabularies` | with a client active, `HStack { Button("Go"); Toggle("Wi-Fi"); Slider; TextField; Picker }` records the literal expected roles, labels and values (written in the test, `PE-S`) **and** the same as the `Row` spelling (frames differ by spacing only) | does not compile | M1.13: `Toggle`'s AX role → `.button` (the comparison can fail); *M1.11 does **not** redden it — measured, `PE-X`* |
| 1.14 | `tabVisitsControlsInAProposalStackInTreeOrder` | `VStack { TextField; Button; Toggle; Picker; Slider; Stepper }`: Tab order is the literal id list written in the test (`PE-S`) and equals the `Column` spelling's | does not compile | M1.14: `Stepper`'s `isFocusable = false` |
| 1.15 | `aShortcutHelpAndHoverWorkOnAButtonInAProposalStack` | `.keyboardShortcut("k")` fires with focus elsewhere; `.help("tip")` is the AX hint; `.onHover` reports enter/exit from injected moves | does not compile | M1.15: `Window`'s shortcut stage skips a `ShortcutTarget` → the shortcut arm |
| 1.16 | `aLegacyFrameAnimatesInsideAProposalStack` | `Button.frame(width: w)` in an `HStack`, `w` changed under `withAnimation(.linear(duration: 1))`: at `simulateTick(0.5)` the width is midway | does not compile | M1.16: the frame layer's `animated(_:_:for:pass:)` call removed |
| 1.17 | `aDragFromAControlInAProposalStackCarriesAPreview` | `Text("drag").draggable("x")` in an `HStack`: after press-and-move a drag session exists and its preview capture is non-empty (`DN-X`) | does not compile | M1.17: `Text.paint` bypasses `paintDecoration` |
| 1.18 | `aSelectableListInAProposalScrollViewWindowsAndSelects` | `ProposalScrollView { VStack { List(rows, rowHeight: 20, selection: $sel) { … } } }` over two frames: bounded window (`try #require`), rows recorded, a click selects and focuses the list | does not compile; with `PE-B` alone all 40 rows realised (`PE-V`) | M1.18: `List.visibleRange` returns `0..<count`; M1.18b (`PE-V`): the scroller publishes no context |
| 1.19 | `aPopoverOnAButtonInAProposalStackPresents` | `.popover(isPresented: .constant(true))` on a Button in an `HStack`: a presentation root is laid out and the Button's frame equals the frame without the popover | does not compile | M1.19: the popover's presentation registration skipped |
| 1.20 | `theProposalOnlyModifiersReachLegacyContent` | `HStack { Text(long).layoutPriority(1); TextField }` at 200: the Text takes its whole width first; `VStack { Text(long).fixedSize() }` at 50 keeps one line; `Grid { GridRow { Text("a").gridCellColumns(2) }; GridRow { Text("b"); Text("c") } }` spans both columns | does not compile | M1.20: the `ElementGroup.layoutPriority` spelling returns `LegacyContent(self)` without the layer |
| 1.21 | `pixelsInfinityIsSwiftUIsFrameSpelling` (guard) | `.frame(maxWidth: .infinity)` on a legacy and a proposal element typechecks with a plain import; control: `.frame(maxWidth: .greatest)` fails | fails | M1.21: delete `Pixels.infinity` |
| 1.22 | `aGridFormGivesItsFieldColumnTheRest` | `Grid { GridRow { Text("Name"); TextField(…) }; GridRow { Text("Description"); Slider(…) } }` at 300: column 0 = the wider label, column 1 = 300 − column 0 − 8 (hand-derived from the measured label widths) | does not compile | M1.4a/M1.4b; *M1.22 (`Slider`'s `PE-D` reverted) does **not** redden it — measured, `PE-X`* |
| 1.23 | `aLegacyRowServesItsSliderLast` | `PE-D`'s named exception in a legacy container: `Row(gap: 8) { Text("Speed"); Slider(…) }` declared 368 wide: Slider 321 | red at `e54c3f6` (180) | M1.5's mutation |
| 1.24 | `PE-H`'s flipped guards (9 tests with `PE-W`) | each as the table in `PE-H` | — | each new control arm is shown to fail by switching `ProposalFrame.init` to `@ProposalContentBuilder` in a scratch build (legacy content is then adopted, so all eight controls compile and redden) |

### 6.2 Lane 2 — `Tests/MetalUITests/ComponentStackTests.swift` (new), `CloseoutTests.swift`

Synthetic trees as the design session's scratch: twelve pane types (a
`Component` over a `Column` of twelve `Row { Text; Box().cssWidth(4); Text }`),
a shell `switch`ing over 2/12 of them, and an inline shell (one `Component`
whose `switch` holds the twelve `Column`s inline). Generated source, checked
in (no build-time generation).

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 2.1 | `aShellOverTwelveComponentPanesUsesTheStackOfOnePane` | `StackMeter` high-water(shell 12) − high-water(pane) ≤ 16 KiB (design: 4.5 KB; also print both figures) | lane 2 lands the meter first and runs 2.1 before the box: red (design: 508 KB) | M2.1: `ComponentLayout` stores its payload inline |
| 2.2 | `theStackMeterSeesTheContentGettersFrame` | high-water(inline 12) − high-water(inline 2) > 200 KiB (design: 583 KB) — the separating arm: the meter sees builder getter frames | new | M2.2: no sampling in `ElementBuilder` (Δ ≈ 0) |
| 2.3 | `theStackMeterMeasuresOnlyInsideAMeasurement` | a sample outside `measuring` changes nothing; a nested `measuring` returns its own figure and the outer's ≥ it; a sample from a secondary thread (a `Thread` joined with a semaphore, no sleep) while a scope is open changes nothing (`PE-P`) | new | M2.3: `sample()` ignores the missing base; M2.3b: drop the main-thread check → the secondary-thread arm |
| 2.4 *(suspended, `PE-T`)* | `aWindowWarnsOnceWhenAFramePassesTheStackThreshold` | a `Window` over a `FakePlatformWindow` showing the inline-12 shell: the sink receives exactly one line naming 512 KiB and the inline shell's type, still one after three frames; a window showing one pane receives none | new | M2.4a: no once-flag (3 lines); M2.4b: threshold 4 MiB (0 lines) |
| 2.5 *(suspended, `PE-T`: four trees above)* | `everyProductionTreeLaysOutUnderTheStackWarningThreshold` | every tree `buildEveryProductionTree` names, rendered once in a `Frame` at 920×560 inside `measuring`: high-water < 512 KiB; prints each figure (recorded in record §78); **if any production tree is at or above the threshold, the lane stops and `PE-L` is re-taken** | new | M2.5: threshold 64 KiB |
| 2.6 | `measureComponentBoxAllocations` (figure, `METALUI_COMPONENT_ALLOC_MEASURE=1`, in `CloseoutTests.swift` beside 1.6, reusing `countCloseoutAllocations` — no third `malloc_logger` installer) | allocations per settled frame for rows of 0/40/80 one-leaf `Component`s; the slope (design expectation: +1 per `Component`) recorded in record §78 | figure | — |
| 2.7 | (conditional) `aComponentsLayoutWritesReachItsPaint` | write the `withPayload` mutation first: `withPayload` mutates a copy (`var p = storage.payload; return body(&p)`); **if no existing test reddens**, add this test (a `Component` whose content writes layout state in `prepaint` that `paint` reads) | — | the same mutation |

### 6.3 Lane 3 — demo and docs

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 3.1 | `theControlsDemosSwiftUISectionLaysOutWithoutReports` | the new section (`swiftUIVocabularySection()`), rendered in diagnostics mode at 920×560: empty report; its `HStack` rows hold the expected controls (ids by path) | new | M3.1: the section's `TextField` gains `.flexGrow(1)` → `textField.flexGrow.unconsumed` |

`everyProductionTreeBuildsOnAOneMegabyteThread` covers the section (it
builds `controlsDemoContent()`); test 2.5 covers its layout.

---

## 7. Demo (lane 3)

The controls demo (`METALUI_CONTROLS_DEMO=1`) gains a section "SwiftUI
vocabulary", in **its own function** `swiftUIVocabularySection()` passed to
the composer (Windows 1 MB rule): `FM0`'s form wired to the demo's existing
`@State` (name, enabled, speed, flavour, quantity) plus `ST0`'s status bar
under it. Not one of the fourteen offscreen images (they render
`demoContent()` and the preview only), so those stay **0 px**; lane 3 re-takes
them anyway (`docs/probes/demo-pixels/compare.sh <scratch> e54c3f6 HEAD`).
`DemoFrameDeterminismTests`' `Expected.swift` is not edited.

## 8. Docs (lane 3; Record phase for CLAUDE.md, AGENTS.md, README, record)

- `docs/migration.md`: "Migrate inside-out" rewritten — legacy content now
  composes inside `HStack`/`VStack`/`ZStack`/`Grid`/`GridRow`/
  `ProposalScrollView`/custom layouts (`PE-B`); what still does not
  (`ProposalFrame`/`Padding`/`Background`/`FixedSize`, the `native*`
  modifiers); a legacy item field there is reported (`PE-C` item 4) with its
  SwiftUI replacement. The `Text` row (`PE-G`). Part 2 "Behaviour changes":
  `PE-D` (TextField/TextEditor/Slider at an infinite offer; a legacy `Row`
  now serves them last). The `Component` stack rule (`PE-K`) and the warning
  (`PE-L`) under a new "Large trees in a debug build" heading.
- `docs/api-overview.md`: `ProposalContentBuilder`, `LegacyContent`, the
  `ElementGroup` proposal-only spellings, `Pixels.infinity`, and one sentence
  in the containers paragraph.
- `docs/divergences.md`: 130, 131, header counts (§5).
- `docs/getting-started.md`: if it states the inside-out rule, the same
  correction (grep; no change otherwise).

## 9. Human checks (lane 3, `docs/verification/human-checks.md` group V)

- **V1** Run `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo`: the "SwiftUI
  vocabulary" form's rows read left to right as `FM0`'s: the field and the
  slider fill to the trailing edge, Apply sits at the trailing edge, the
  menu picker hugs, the divider spans.
- **V2** Click, Tab, Space and type in the form: each control behaves as the
  same control in the legacy section above it.
- **V3** VoiceOver (an agent cannot): the form's controls announce as the
  legacy section's.
- **V4** Resize the window narrower than the form's ideal: nothing overlaps
  except as divergence 130 says (the Button and menu picker keep their
  minimums).
- **V5** In a debug build, a scratch app with a 12-way inline `switch` (spec
  §6.2's inline shell) prints the one stack warning to the console once.

## 10. Lanes (`PE-M`)

| lane | model | files (disjoint) | done when |
|---|---|---|---|
| **1 — builder, adapter** (second) | Opus | new `Sources/MetalUI/ProposalContentBuilder.swift`, new `Sources/MetalUI/LegacyProposalModifiers.swift`; `NativeElements.swift`, `Grid.swift`, `ProposalScrollView.swift` (with `PE-V`), `ScrollChrome.swift` (header comment, `PE-V`), `ProposalLayoutContainer.swift`, `ProposalNodeID.swift` (header only), `Sources/MetalUICore/Units.swift`; tests: new `ProposalControlsTests.swift` (all of §6.1 but 1.9 and 1.23), `ProposalControlsCompileGuards.swift`; `ElementGroupTrapTests.swift`, `ForEachCompileGuards.swift`, `GridCompileGuards.swift`, `EnvironmentCompileGuards.swift`, `ExplicitIdentityCompileGuards.swift`, `ConditionalIdentityCompileGuards.swift`, `ProposalLayoutCompileGuards.swift` (`PE-W`); `docs/probes/closeout-inventory-map.tsv`, `closeout-public-api.tsv` | §6.1 green, every mutation named; images 0 px; §12 |
| **2 — MG-15, the meter, `PE-D` sizing** (first) | Opus | `TextField.swift`, `TextEditor.swift`, `Slider.swift` (`PE-D`, first; images re-taken at once); `Component.swift`, `ProposalNodeID.swift` (the `Component` typed default only, ~line 125), `ElementBuilder.swift`, new `StackMeter.swift`, `Frame.swift` (the `requestNativeLeaf` sample only), `Window.swift` (the measuring scope and warning only); tests: `SliderTests.swift`, new `GreedyControlSizingTests.swift` (1.9, 1.23 — neither needs the builder), new `ComponentStackTests.swift`, `CloseoutTests.swift` (2.6) | 1.9, 1.23 and §6.2 green, mutations named, figures printed for the record; images 0 px after `PE-D`; `swift package clean` run; §12 |
| **3 — demo, docs** | Sonnet, after 1 and 2 merge | `Sources/MetalUIDemoContent/ControlsDemo.swift`; `docs/migration.md`, `docs/api-overview.md`, `docs/divergences.md`, `docs/verification/human-checks.md`, `docs/getting-started.md` (if needed); test 3.1 in new `Tests/MetalUITests/ControlsDemoSwiftUISectionTests.swift` | §6.3; images 0 px; §12 |

**Order (`PE-O`): lane 2, then lane 1, then lane 3, one at a time in this
worktree.** `ProposalNodeID.swift` is the one file both touch (lane 2 the
`Component` typed default, lane 1 the header) — sequential, never parallel.
Lane 1's 1.1, 1.5 and 1.22 assert the post-`PE-D` values lane 2 lands.
Lane 2's `ElementBuilder` sampling covers lane 1's builder because lane 1
forwards to `ElementBuilder` (`PE-B`). The Record phase
(record §78, CLAUDE.md/AGENTS.md rules — one or two sentences each for
`PE-B`/`PE-C`, `PE-D`, `PE-J`/`PE-K`/`PE-L` — README, record README, record
§04 for 130/131) follows lane 3.

## 11. Deferred (reason, owner)

| item | reason | owner |
|---|---|---|
| `.padding(.horizontal, 16)`, `.padding()` on legacy elements | a separate surface; the tests write `Edges` | MG-11 (gpui-gap list) |
| `.help` after `.disabled` | `.help` needs a node; an `EnvironmentScope` has none | MG-13 |
| `TextField`/`TextEditor` bezel chrome (24 tall), `.textFieldStyle` | a look, divergence 131 | MG-20 |
| an `ElementGroup` eraser | `PE-K`'s spelling (a `Component`) needs none | MG-22 |
| shrinking element values (copy-on-write `Handlers`/`Decoration`/`Style`) | the only lever on an inline switch (`PE-K`); broad, every `StyledElement` | gpui-gap list (performance), with `StackMeter` as the instrument |
| deprecating `ProposalText`/`proposalLayout()` | warnings in every test using them | a later closeout |
| `aspectRatio`/`scaledToFit`/`scaledToFill` on legacy content | no control needs them | on request |
| `ProposalFrame`/`Padding`/`Background`/`FixedSize`/`nativeOverlay` taking legacy content | MetalUI-only wrappers; they are the guards' controls | none |
| below-ideal compression of the hugging controls | divergence 130 | none |
| SwiftUI's text-derived stack spacing | CN-H's existing note | none |

## 12. Must not move — the checklist each lane re-measures

- Identity and state: `theSevenRetentionSlotsAreMutuallyDistinct`, `MC-A`/
  `MC-C`/`MC-P` numbering, `.id()` outermost — no change to any id outside a
  legacy element's new position in a proposal container (test 1.4).
- Hit testing (one ranking), accessibility (both bridges, `Mirror` counts),
  animation, focus, `List` windowing and `TB-AH`, `Deferred`, text input:
  their existing suites green unchanged; tests 1.11–1.19 add the
  proposal-container arms.
- `Handlers` sixteen members; `HandlerShape`/`HandlerFingerprint` unchanged;
  no new arm in `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn` or the
  D2 guard (`PE-C` item 5) — say so in the lane's report.
- Pixels: 0 differing in all fourteen offscreen images against `e54c3f6`;
  `DemoFrameDeterminismTests`' `Expected.swift` unedited.
- 0 `warning:` on both build systems (the SwiftPM deprecation notice aside);
  0 `error:`; the summary line read, the `FR-J` line present.
- `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` only
  `MetalUIShaderTypes`; no shader change.
- `Backends/SDL` builds and its tests pass (`PKG_CONFIG_PATH=$PWD/.accesskit`);
  the `swift:6.4-noble` container builds and runs it (MetalUI and
  MetalUICore are portable and both lanes touch them) — OrbStack started if
  stopped and stopped after.
- `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
