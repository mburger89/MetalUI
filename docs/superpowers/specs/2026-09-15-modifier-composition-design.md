# Modifier composition design

**Milestone:** SwiftUI replacement task 3
(`plans/2026-09-12-swiftui-alignment.md`, "Build a typed modifier-composition
foundation", and its four open proofs).

**Status (2026-09-15): design only.** Written against `f64e58a` on
`feat/modifier-composition`, in the worktree
`/Users/maxburger/Developer/MetalUI-modifier-composition`. No source has
changed. Rulings are prefixed **`MC-`** and lettered, in
`docs/superpowers/2026-09-15-modifier-composition-decisions.md`; a bare `MC-3`
is a typo. The track's record is `docs/record/10-modifier-composition.md`.

This spec **supersedes** the design sections of
`specs/2026-09-12-typed-modifier-composition-design.md` ("Design", "First
feature", "Required proofs") for the legacy path. That file's Status block
stays the inventory of what existed at `7cfcddc`. It is not edited here.

## What this design delivers

| lane | closes | one line |
|---|---|---|
| 1. **proofs** | open proofs 1–3 on today's code; the overlay collision fixed | end-to-end `@State` tests across chains on both paths; one once-per-phase test over every wrapper; the overlay collision measured red, then fixed with one cursor; a hand-built-`Box` oracle for lane 2 |
| 2. **representation** | the task's wrapper representation | `ModifiedElement<Content>`: one flat type for legacy `.padding` and `.frame`; `FrameModifier` deleted; the oracle stays green; per-site guard arms; the default demo captured unchanged |
| 3. **typed node id** | open proof 4 (`SA-R`) | `ProposalNodeID` with an internal init, returned by a new `ProposalElementGroup` requirement; five lies become compile errors; three named holes pinned |

**Why this order.**

- **Lane 1 first.** It writes, against today's `Box`/`FrameModifier`, the tests
  lane 2 must keep green. That turns "preserves identity, `@State`, handlers,
  phase order" into a measurement rather than a promise (`MC-B`). The overlay
  fix is one line with no dependency.
- **Lane 2 before lane 3.** The two are independent: legacy path, proposal
  path. Lane 3 is the largest churn and edits the files the parallel tracks are
  likeliest to touch. If the track stops early, lanes 1–2 are a complete
  deliverable on their own.
- **Lane 3 last.** Lane 1's proposal `@State` test is the mutation target for
  lane 3's duplicated default (`MC-H`), so it must exist first.

**Not in this design:** `MC-L` lists every deferred item and its owner. In
brief: no `width`/`height` conversion (task 4), no change to `Component`
distribution (task 5), no paint-only legacy layers (task 5), no unification with
proposal `ModifiedContent` (task 7).

## Where things stand at `f64e58a`

All by reading, except where marked as measured.

- **Legacy `.padding`** returns `Box<Self>` (`Box.swift:640-650`).
- **Legacy `.frame(width:height:)`** returns `FrameModifier<Self>`
  (`FrameModifier.swift:62-67`), a `StyledElement` whose three phases are
  `Box`'s, with a centred style.
- **Each wrapper adds one node and one identity level.** Chained wrappers nest
  types (`chainedFramesRemainConcreteAndNestTheirLayoutNodes` stores
  `Row<FrameModifier<FrameModifier<TwoLeaves>>>`).
- **`OverlayModifier` gives primary and overlay one id — measured**
  (`MC-E`): an overlay never clicked read the primary's 3 taps, and hovering
  the primary painted both hover fills.
- **`ProposalElementGroup` has no requirements**, so a conformer registering a
  legacy node compiles and traps at run time (`SA-R`, `SA-G`).
- **Counts carried from `553b980`** (docs-only since): 1084 tests, 45 guards,
  97 goldens. Re-measured with the overlay fix applied temporarily: 1085 with
  one scratch test.

## Evidence

- `docs/probes/swiftui-modifier-identity.swift`: arms T, A–H (`MC-A`, `MC-C`,
  `MC-E`).
- `docs/probes/modifier-composition-skeletons/FlatChainOverloads.swift`
  (`MC-A`, `MC-B`).
- `docs/probes/modifier-composition-skeletons/TypedNodeKit.swift` and its eight
  `typed-client-*.swift` clients (`MC-G`).
- The scratch end-to-end runs recorded under `MC-E` and `MC-G` item 2. Their
  shapes are lane 1's tests 1–3 and lane 3's test 7.

---

## Lane 1 — proofs, and the overlay fix

### Rulings

`MC-B` (writes the oracle), `MC-D`, `MC-E`, `MC-F`.

### Source change

`Sources/MetalUI/NativeOverlayModifier.swift`, `requestLayout`: delete
`var overlayCursor = 0`, and pass `&contentCursor` to
`overlay.requestGroupLayout`. Rename the variable `cursor` and add a doc
comment. The comment says:

- that one cursor is threaded, as `Pair` threads it;
- what the collision did, with `MC-E`'s measured numbers;
- which tests pin it.

No other source changes in this lane.

### Files

- `Sources/MetalUI/NativeOverlayModifier.swift` (edit, above).
- `Tests/MetalUITests/ModifierCompositionProofTests.swift` (new). Private
  helpers:
  - **`PhaseLog`**, a `@MainActor final class`: per-name counts of
    `requestLayout`/`prepaint`/`paint`, per-name `GlobalElementID` (last
    prepaint), per-name `taps` read in paint, and an ordered event list.
  - **`CountingLeaf`**, a legacy `StyledElement` (all four requirements). It
    registers `requestNode` with a declared pixel size, holds
    `@State var taps = 0`, and in prepaint registers `handlers` with `onClick`
    defaulted to `{ taps += 1 }` when the caller set none. Paint logs, and
    paints a `.separator` fill over its bounds when `pass.isHovered(id)`, a
    colour no fixture uses for anything else.
  - **`CountingProposalLeaf`**, an `Element` + `ProposalElementGroup`
    registering `requestNativeLeaf` at a fixed size, with the same `@State`,
    handler, log and hover fill. It also takes an optional click action and
    an optional displayed value, so a `Component` can route its own `@State`
    through it. Lane 3 converts it to `ProposalElement`.
  - **`CountingProposalComponent`**, a `Component` + `ProposalElementGroup`
    (the `Toggle` precedent in `NativeBoundaryIntegrationTests.swift`). It
    holds its own `@State var taps`, and its content is one
    `CountingProposalLeaf` whose click increments the component's state and
    whose paint logs it.

### Tests

Each row gives what the test pins, its state before the change, and the
mutation that must redden it after. "Green on arrival" marks a
characterization of correct behaviour today; its proof is the mutation, run
in this lane on today's code, and again by lane 2 or 3 on theirs.

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1 | `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities` | `Frame` only. `ZStack { primary(60).overlay(.topLeading) { overlay(10) } }`: the ids differ; `overlay.id == .child(of: primary.id.parent, at: 1, name: nil)`. A second arm with an `HStack { A; B }` primary: `overlay.id == .child(of: A.id.parent!.parent, at: 1, name: nil)`, still index 1, because the stack is one element however many nodes it holds | **red, measured**: ids equal | restore a second cursor starting at 0 |
| 2 | `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState` | real `Window`, 100×100. Three clicks at (70, 70), primary only, then one at (25, 25), the overlay: primary reads 3, overlay reads 1 | **red, measured**: overlay 3 after the primary's clicks | same |
| 3 | `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay` | pointer at (70, 70): exactly one hover fill, 60pt wide. Pointer at (25, 25): exactly one, 10pt wide | **red, measured**: two fills, `[60, 10]` | same |
| 4 | `aModifierChainIsIdenticalToHandBuiltNestedBoxes` (`MC-B`) | chain `leaf.background(.accent).onClick{}.padding(4).id("mid").frame(width: 60, height: 40).background(.surface).onClick{}.padding(8).background(.separator).onClick{}` in a `Row` against hand-built `Box(style:decoration:content:)` values with the same styles, handlers and `.id`, one per wrapper. Compares: leaf id and bounds; `lastHitboxes` ids, bounds and order; scene rect order, bounds and colour; `tree.nodeCount`; `isLive(animRetentionSlot(for:))` per hitbox id. `try #require` first that a disagreeing oracle (paddings 4 and 8 swapped) gives different rects | green on arrival | today: `FrameModifier.prepaint` registers its handlers after its content. Lane 2: the layer loop runs innermost-first in prepaint; every inner layer takes the outermost id; `.id` lands on the wrong layer |
| 5 | `stateSurvivesFramesUnderALegacyModifierChain` (`MC-D`) | window. `Row { CountingLeaf().padding(4).frame(width: 60, height: 40).padding(8) }`: 3 clicks, 2 further frames, reads 3. The leaf and its two nearest ancestors each have component `.positional(0)`, and its third ancestor equals `.child(of: rootID, at: 0, name: nil)`, where `rootID = .child(of: nil, at: 0, name: nil)` is the `Row`'s. Each of the three ancestors has a live `$anim` slot | green on arrival | today: `FrameModifier.requestLayout`'s cursor starts at 1. Lane 2: content laid out under the outermost layer's id |
| 6 | `stateSurvivesFramesUnderAProposalModifierChain` (`MC-D`) | window. `HStack { CountingProposalLeaf("a").padding(…).frame(width: 40, height: 40).background(.surface); CountingProposalLeaf("b"); CountingProposalComponent("c") }`: 3 clicks on a and 2 on c, then 2 frames; a reads 3, b reads 0, c reads 2. `a` and its two nearest ancestors each have component `.positional(0)`, and its third ancestor is the `HStack`'s child at index 0 | green on arrival | today: `ModifiedContent.requestLayout`'s cursor starts at 1. Lane 3: delete `StateBinder.bind` from `ProposalElement`'s typed default (a reads 0); delete its `cursor += 1` (a and b share an id); delete the bind from `Component`'s typed default (c reads 0) |
| 7 | `everyModifierWrapperDelegatesEachPhaseExactlyOnce` (`MC-F`) | one arm per wrapper and code path, as listed in `MC-F`, each `[1, 1, 1]`. The control arm `Pair(leaf, leaf)` reads `[2, 2, 2]`. Counts are `try #require`d | green on arrival | today: the `allowsHitTesting` branch calls `prepaintGroup` twice (its arm reds); the `clip` paint branch loses its `else` (its arm reds); `OverlayModifier.paint` skips `overlay.paintGroup` (the overlay-side arm reds); `FrameModifier.prepaint` calls content twice. Lane 2: `ModifiedElement.paint` calls content once per layer |
| 8 | `aModifierChainRegistersAndPaintsOuterLayersFirst` (`MC-F`) | `leaf.background(.accent).onClick{"inner"}.padding(4).background(.surface).onClick{"outer"}`: hitbox order `[outer, leaf]`; `.surface` emitted before `.accent`; a click in the padding ring logs `outer`, one inside the leaf logs `inner` | green on arrival | today: `Box.prepaint` registers after content. Lane 2: the layer loop reversed in prepaint, and separately in paint |

**Mutation discipline.** Commit before mutating; back up each mutated file
with `cp` and restore from the copy; confirm with `git status --short` and a
grep for the marker. Run the whole suite per mutation (`swift test
--build-system native --no-parallel`), read the `Test run with N tests` line,
and name the tests each mutation reddens in `MC-D`/`MC-E`/`MC-F`'s Mutations
lines. Word coverage as a differential between named tests, never as
exclusivity.

### Expected counts

1084 → **1092** tests; guards unchanged at 45; goldens 97, unmoved.

### Docs owed by lane 1 (track files only)

- `MC-D`, `MC-E`, `MC-F` Mutations lines.
- Record §10: red lines for tests 1–3; the suite count.

---

## Lane 2 — `ModifiedElement`

### Rulings

`MC-A`, `MC-B`, `MC-C`, `MC-I`, `MC-J` (default demo), `MC-K`.

### Public API

```swift
/// One flat wrapper for the legacy path's outer modifiers (MC-A).
public struct ModifiedElement<Content: ElementGroup>: Element, StyledElement {
    public var content: Content
    // internal storage:
    //   var outermost: ModifierLayer
    //   var inner: [ModifierLayer]   // innermost first; empty for one layer (MC-K)

    // StyledElement: style / decoration / handlers / elementID read and write `outermost`.
    public struct Layout { /* internal: per-layer id + node, content's GroupLayout */ }
}

extension ModifiedElement {
    public func padding(_ points: Pixels) -> ModifiedElement<Content>        // appends
    public func padding(_ edges: Edges<Length>) -> ModifiedElement<Content>  // appends
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Content>
}

extension StyledElement {   // Box.swift, return types change
    public func padding(_ points: Pixels) -> ModifiedElement<Self>
    public func padding(_ edges: Edges<Length>) -> ModifiedElement<Self>
}

extension ElementGroup {    // moved from FrameModifier.swift
    public func frame(width: Pixels? = nil, height: Pixels? = nil) -> ModifiedElement<Self>
}

struct ModifierLayer {      // internal
    var style: Style; var decoration: Decoration; var handlers: Handlers; var elementID: ElementID?
}
```

A padding layer is `Style()` with `padding = edges`. A frame layer is
`Style()` with `alignItems = .center`, `justifyContent = .center`, and
`size.width`/`size.height` set for each non-nil argument: `FrameModifier.init`,
verbatim.

### Phases (`MC-B`, `MC-C`)

Let n be the layer count and `L[k]` the layer at depth k, 0 innermost.

- **`requestLayout(id)`:**
  - ids from the outside in: `id(L[n-1]) = id`, then
    `id(L[k]) = .child(of: id(L[k+1]), at: 0, name: L[k].elementID)`;
  - `content.requestGroupLayout(under: id(L[0]), at: &cursor)`, with `cursor`
    starting at 0;
  - then for k = 0 up to n-1: `(L[k].style, L[k].decoration) =
    animated(L[k].style, L[k].decoration, for: id(L[k]), pass:)`, and
    `node[k] = pass.requestNode(style: L[k].style, children: k == 0 ?
    contentNodes : [node[k-1]])`;
  - return `node[n-1]`.

  This is the order, node minting included, that nested `Box`es produce.
- **`prepaint`:** for k = n-1 down to 0,
  `pass.registerHandlers(L[k].handlers, at: pass.bounds(of: node[k]), id: id(L[k]))`;
  then `content.prepaintGroup` once.
- **`paint`:** for k = n-1 down to 0, if
  `animatedBackground(L[k].decoration, for: id(L[k]), pass:)` returns a colour,
  fill `bounds(of: node[k])` with `Corners(all: L[k].decoration.cornerRadius)`;
  then `content.paintGroup` once.
- **`Element`'s default `requestGroupLayout`** gives the whole chain its slot,
  named by `elementID`, which is the outermost layer's.

### Files

- `Sources/MetalUI/ModifiedElement.swift` (new): the type, `ModifierLayer`,
  the three concrete overloads, and `ElementGroup.frame`. The doc comment cites
  `MC-A`…`MC-C`, `MC-K` and the pinning tests.
- `Sources/MetalUI/FrameModifier.swift`: **deleted**.
- `Sources/MetalUI/Box.swift`: the two `padding` return types and their doc
  comments, which today say "applies that style to a new outer box".
- `Tests/MetalUITests/ModifiedElementTests.swift` (new).
- `Tests/MetalUITests/ComponentTests.swift`:
  `chainedFramesRemainConcreteAndNestTheirLayoutNodes` stores
  `ModifiedElement<TwoLeaves>` and `Row<ModifiedElement<TwoLeaves>>`. The node
  count stays 5. Its doc comment says the type is flat and the nodes still
  nest.
- `Tests/MetalUITests/NativeLayoutIntegrationTests.swift`: the doc comment at
  `:660` that names `FrameModifier`.
- One additive arm block in each of the six guards `MC-I` names:
  - `AnimationTests.swift` (2);
  - `BackgroundChainTests.swift` (2);
  - `InputDispatchTests.swift` (1);
  - `AXEmitSiteTests.swift` (1).

  Each arm uses a **two-layer** chain and asserts on the **inner** layer as
  well as the outermost.

### Tests

Build a **skeleton commit first**. `ModifiedElement` gets its storage, its
accessors and the `StyledElement`/`ElementGroup` return types, but **no concrete
overloads**, and phases that register **only the outermost layer** around the
content under the outermost id. Take tests 1–3's red runs on it.

| # | test | pins | before (on the skeleton) | mutation that must redden it after |
|---|---|---|---|---|
| 1 | `legacyModifierChainsInferOneConcreteType` (`MC-A`) | `String(describing: type(of:))` of `Leaf().padding(4).frame(width: 60).padding(Edges(all: .pixels(8))).width(70)` is `"ModifiedElement<Leaf>"`; of a component's `.frame(width:).padding(_:)` is `"ModifiedElement<Comp>"`; plus a stored `let s: ModifiedElement<Leaf>` and `Row<ModifiedElement<Leaf>>` built from chains | **red**: `ModifiedElement<ModifiedElement<…>>` | delete the concrete `padding(_ points:)`; separately `padding(_ edges:)`; separately `frame` |
| 2 | `aNestedModifiedElementIsIdenticalToItsFlatChain` (`MC-B`) | `func wrap<T: StyledElement>(_ t: T) -> ModifiedElement<T> { t.padding(8) }` applied to `leaf.padding(4).frame(…)`, against the flat `leaf.padding(4).frame(…).padding(8)`: every observation from lane 1 test 4. `try #require` that the two type names differ | **red**: flat registers one wrapper node, nested two | inner layer ids `at: 1`; `animated` skipped for inner layers |
| 3 | `addingALayerAtRunTimeResetsTheWrappedElementsState` (`MC-C`, probe D1/D3) | window, `generation` captured by the content closure: `var c = CountingLeaf().padding(4); if generation > 0 { c = c.padding(8) }`. Three clicks at generation 0, flip, one frame: reads **0** | **red**: the skeleton lays content out under the outermost id whatever the count, so it reads 3 | content laid out under the outermost id |
| 4 | `changingALayersValueKeepsTheWrappedElementsState` (`MC-C`, probe C/D2) | the same, with `.padding(generation == 0 ? 4 : 12).frame(width: generation == 0 ? 60 : 80, height: 40)`: reads **3** | green on the skeleton | name each layer by its style, e.g. `ElementID("\(style.padding)")` when `elementID` is nil |
| — | lane 1 tests 4, 5, 7, 8 | the migration proof | green before (on `Box`/`FrameModifier`) and must stay green | their lane-2 mutations in lane 1's table |
| — | six guard arms (`MC-I`) | inner and outer layer each animate style, animate colour, honour and fade hover/focus, fire `onClick`, emit a declared AX node | red on the skeleton for the inner layer | outermost-only `animated`; outermost-only `animatedBackground`; outermost-only `registerHandlers` (the onClick, AX and hover arms) |

**`MC-K`, allocations.** Copy `FreezeLoopAllocationTests.swift`'s
`countAllocations` and calibration into `ModifiedElementTests.swift`. Count
`requestLayout` over 500 one-layer chains and over 500 hand-built `Box<Leaf>`.
Keep a test named `aSingleLayerChainAllocatesNoMoreThanTheBoxItReplaces` **only
if** the mutation "one `layers` array for all layers" reddens it. Either way,
record both counts under `MC-K`.

**The default demo (`MC-J`).** Take the baseline capture at the lane's start
commit, before any source edit. After the lane, rebuild release, re-capture and
count differing pixels. Record both captures' dimensions, the count, the
coordinates of any difference, and the logged pointer position in record §10.
Anything beyond record §03's desktop-corner pixels is a regression to fix
before commit.

### Expected counts

1092 → **1096** tests (**1097** with the allocation test); guards 45; goldens
97.

### Docs owed by lane 2 (track files and the lines it makes false)

- `MC-A`, `MC-B`, `MC-C`, `MC-I`, `MC-K` Mutations lines; `MC-J`'s capture
  result.
- Source doc comments the change makes false, corrected at the line (practices
  record-mechanism 1):
  - `Box.swift`'s `padding` docs;
  - `Component.swift:387-405`'s `Box.swift:NNN` line citations, if the
    `Box.swift` edit moves them. Its parameter-signature claim stays true.
    This is a doc-only edit.
- Record §10: the per-site accounting change. `FrameModifier`'s layout and
  background sites are gone; `ModifiedElement` is one layout site and one
  background site, looping per layer. CLAUDE.md's counts are the integration
  step's.

---

## Lane 3 — the typed native node id

### Rulings

`MC-G`, `MC-H`, `MC-J` (preview).

### Public API

```swift
// Sources/MetalUI/ProposalNodeID.swift (new)
public struct ProposalNodeID: Hashable, Sendable {
    public let layoutNodeID: LayoutNodeID
    init(_ id: LayoutNodeID)
}

@MainActor
public protocol ProposalElement: Element, ProposalElementGroup {
    associatedtype LayoutState            // restated: inference fails without it (MC-G)
    mutating func requestProposalLayout(_ id: GlobalElementID,
                                        pass: inout LayoutPass) -> (ProposalNodeID, LayoutState)
}

extension ProposalElement {
    public mutating func requestLayout(_ id: GlobalElementID,
                                       pass: inout LayoutPass) -> (LayoutNodeID, LayoutState)
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], SingleElementLayout<Self>)
        // repeats Element's default: .child(of:at:name:), StateBinder.bind, cursor += 1 (MC-H)
}

extension Component where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], ComponentLayout<Self>)
        // repeats Component's default: id, StateBinder.bind, cursor += 1,
        // content materialized once, laid out under the component's id from 0
}

// Sources/MetalUI/ProposalElementGroup.swift
public protocol ProposalElementGroup: ElementGroup {
    mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                             at cursor: inout Int,
                                             pass: inout LayoutPass) -> ([ProposalNodeID], GroupLayout)
}
// EmptyGroup, and conditionally Pair, OptionalGroup and ArrayGroup, implement it
// beside their existing conformance lines, mirroring their untyped bodies. The
// 13 element types' conformances become `ProposalElement`.
```

**`LayoutPass` (`Passes.swift`, registrar block only).** Every
`requestNative*` registrar and `requestNativeLayout(_:children:)` returns
`ProposalNodeID`, and each `child:`/`overlay:`/`children:` parameter takes
`ProposalNodeID`. Bodies wrap and unwrap around `Frame`'s unchanged internal
registrars.

**Every proposal container and wrapper** — `HStack`, `VStack`, `ZStack`,
`ProposalFrame`, `Padding`, `Background`, `FixedSize`, `ModifiedContent`,
`OnTapModifier`, `OverlayModifier`, `ProposalScrollView`,
`ProposalLayoutContainer`, `callAsFunction` — calls
`content.requestProposalGroupLayout`. `Spacer`, `Rectangle`, `Color` and
`ProposalText` implement `requestProposalLayout` over the typed leaf registrar.
`OnTapModifier` returns its child's typed id. `ModifiedContent`'s passthrough
cases return the child's typed id.

### Files

- **Sources:**
  - `Sources/MetalUI/ProposalNodeID.swift` (new);
  - `ProposalElementGroup.swift`;
  - `Passes.swift` (the registrar block);
  - `NativeElements.swift`, `NativeModifiedContent.swift`,
    `NativeOverlayModifier.swift`, `NativeTappable.swift`,
    `ProposalScrollView.swift`, `ProposalText.swift`,
    `ProposalLayoutContainer.swift`.
- **Demo:** `Sources/MetalUIDemo/main.swift`. `PreviewToggle.content` becomes
  `some ProposalElementGroup`; `PriorityPreviewPanel` becomes `ProposalElement`
  with `requestProposalLayout`.
- **Not edited:** `Element.swift`, `ElementGroup.swift`, `Component.swift`,
  `Frame.swift` (`MC-H`).
- **Tests:**
  - helper conversions to `ProposalElement`: `NativeLayoutIntegrationTests.swift`
    (5), `ProposalLayoutIntegrationTests.swift` (1),
    `ProposalModifierValidationTests.swift` (1), `ModifierCompositionProofTests.swift`
    (1), and `NativeBoundaryIntegrationTests.swift`. There, `Toggle`'s content
    becomes `some ProposalElementGroup`; `RegisteredAfterTheContainer` becomes a
    `ProposalElement`; and `LegacyNodeUnderAProposalMarker` becomes a
    `ProposalElement` whose typed entry returns
    `ProposalNodeID(pass.requestNode(style: Style(), children: []))` through
    `@testable`'s internal init, so the existing trap test still reaches the
    trap (`MC-G` item 3);
  - `ProposalLayoutCompileGuards.swift`: its external fixtures now write the
    typed entry, keeping each guard's assertion and diagnostic;
  - `Tests/MetalUITests/ProposalNodeIDCompileGuards.swift` (new), plain import,
    file scope, Swift 6 mode, `typecheckFile` as `SA-P` requires;
  - `Tests/MetalUITests/ProposalNodeIDTests.swift` (new): test 7.

### Tests

Run `swift build --build-system native` before the first guard run. **Mutate
each new guard red once** and record the red line, since guards skip silently
when the modules directory is not found. **Print each real diagnostic before
asserting on it**; the expected fragments below are the skeleton's and must be
confirmed against the real module.

| # | test | pins | before | mutation that must redden it |
|---|---|---|---|---|
| 1 | guard `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` | today's `LegacyNodeUnderAProposalMarker` shape (`Element` + marker, `requestNode`) is rejected with "does not conform to protocol 'ProposalElementGroup'" | **red**: it compiles today (`SA-R`) | add `extension ProposalElementGroup { public mutating func requestProposalGroupLayout(…) -> … { preconditionFailure() } }` |
| 2 | guard `aProposalNodeIDCannotBeMintedOutsideMetalUI` | `ProposalNodeID(pass.requestNode(…))` fails with "initializer is inaccessible due to 'internal' protection level" | **red**: "cannot find 'ProposalNodeID' in scope" lacks the fragment | make the init `public` |
| 3 | guard `aComponentOnlyTakesTheProposalMarkerWithProposalContent` | three fixtures: a `Component` with `Text` content, one with `var content: some ElementGroup` over a `Rectangle` (both rejected, "does not conform to protocol 'ProposalElementGroup'"), and one with `some ProposalElementGroup` (accepted). `#require` that the fixtures disagree | **red**: both negatives compile today | an unconstrained `extension Component { requestProposalGroupLayout … preconditionFailure() }` |
| 4 | guard `aNativeRegistrarRejectsALegacyChild` | `pass.requestNativeFrame(child: pass.requestNode(style: Style(), children: []))` fails with "cannot convert value of type 'LayoutNodeID' to expected argument type 'ProposalNodeID'" | **red**: compiles today | add a `requestNativeFrame(child: LayoutNodeID, …)` overload |
| 5 | guard `aProposalLayoutContainerOnlyAcceptsTypedChildren` | an external element over `requestNativeLayout(_:children:)` passing `[LayoutNodeID]` is rejected, and passing `requestProposalGroupLayout`'s result is accepted | **red**: untyped compiles today, typed does not exist | a `children: [LayoutNodeID]` overload |
| 6 | guard `aProposalGroupWhoseEntryPointsDisagreeStillCompiles` (**pinned wrong on purpose**, `MC-G` item 1) | `liar4`'s shape against the real module typechecks | **red**: the requirement does not exist | none available. It exists to be inverted by whoever closes the hole; its red-before run is its proof it runs |
| 7 | `anOrphanLegacyNodeBesideATypedLeafIsNotRejected` (**pinned wrong on purpose**, `MC-G` item 2) | a `ProposalElement` whose typed entry calls `pass.requestNode(style: Style(), children: [])`, discards it, and returns a typed leaf. In `VStack { HStack { it }; Rectangle(width: 5, height: 5, color: .accent) }` it renders: its prepaint bounds are 10×10, and the scene has 1 rect | **green, as measured on today's code** (`MC-G`) | adding an orphan check in `LayoutPass.requestNode` during native registration reddens it. Nothing else is available, and the doc comment says so |
| — | lane 1 test 6 | the typed defaults bind state and advance the cursor (`MC-H`) | green | delete `StateBinder.bind` from `ProposalElement.requestProposalGroupLayout`; separately, delete its `cursor += 1`; separately, delete the bind from `Component`'s typed default |
| — | `aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer` (existing, rewritten helper) | the run-time backstop survives | green | its existing mutation: delete `newNativeLinearStack`'s child loop (`SA-T` item 1) |
| — | the existing SA-F guards | an external leaf, container and algorithm still build from public API, on the typed entry | green after the fixture edits | make `ProposalElement`'s `requestLayout` default `internal`; the external leaf fixture must redden |

**The demo (`MC-J`).**

- Capture the release preview window (`METALUI_NATIVE_LAYOUT_PREVIEW=1`) and
  the default window at the lane's start commit.
- After the lane, re-capture both and count differing pixels. The expected
  difference is none, beyond desktop corners.

### Expected counts

1096 (or 1097) → **1103** (or 1104) tests: five new guards, the hole guard and
test 7. Guards 45 → **51**, re-counted by `grep -c canTypecheck` per file, not
from this number. Goldens 97.

### Docs owed by lane 3

- `MC-G`, `MC-H` Mutations lines; each guard's red line and real diagnostic;
  the preview capture.
- Doc comments made false at their lines: `ProposalElementGroup.swift`'s ("Marks
  … subtree"), `Passes.swift`'s registrar docs, `ProposalLayoutContainer`'s
  "calls `content.requestGroupLayout`", and `NativeBoundaryIntegrationTests`'
  "The marker has no requirements, so this compiles (ruling SA-R)".
- Record §10: that `SA-R`'s amended criterion is now met, with `MC-G`'s holes.
  Editing the SA doc itself is the integration step's.

---

## Verification common to every lane

- **The suite.** `swift test --no-parallel` (and `--build-system native` for
  the guards). Read the `Test run with N tests` line, not the exit status, and
  grep the log for `error:` and `warning:`. Both must be 0, apart from SwiftPM's
  own deprecation notice under `--build-system native`, which CLAUDE.md
  records.
- **Goldens.** `find Tests -name '*.json' | wc -l` is 97, and
  `git diff --stat f64e58a -- '*.json'` is empty.
- **No sleeps; counts, not clocks.** Window tests drive
  `drawFrameIfNeeded`/`simulateInput`. The allocation measurement counts.
- **Traps** are exit tests (`#expect(processExitsWith:)`) asserting a stderr
  fragment, as in `FontResolverTrapTests.swift`.
- **Mutation.** This worktree runs one agent at a time, so it is not
  contended. Commit first, restore from `cp` backups, verify with
  `git status --short`. Discard and re-take any run taken while another
  process was editing the tree.
- **`swift package clean`** after lane 2 deletes a public type and after lane 3
  changes public signatures across modules (CLAUDE.md's build rule), before the
  run that is recorded.
- **Demo captures.** `MC-J`'s method: no input sent, pointer not moved, pointer
  position logged.

## Merge notes for the integration step

- **Shared files edited:**
  - `Passes.swift`: lane 3, the registrar block's types only;
  - `Box.swift`: lane 2, the two `padding` signatures and docs;
  - `AXEmitSiteTests.swift`, `AnimationTests.swift`,
    `BackgroundChainTests.swift`, `InputDispatchTests.swift`: lane 2, one
    additive arm block each.
- **Shared files NOT edited:** `Element.swift`, `ElementGroup.swift`,
  `Handlers.swift`, `Frame.swift`, `Window.swift`, `Platform.swift`,
  `Tests/MetalUITests/Fakes.swift`.
- **Likely textual conflicts:**
  - any parallel track that adds AX, focus or environment reads to proposal
    elements, which lane 3 rewrites the layout entry of;
  - `AXEmitSiteTests.swift`'s arm list.
- **For CLAUDE.md, owned by integration:** the guard count; "seven registering
  points" and the background-site count (`FrameModifier` gone,
  `ModifiedElement` in); a Component-section note that a caller's `.frame` now
  returns `ModifiedElement`; `SA-R`'s status; the overlay collision's removal
  from record §09's hazards.
