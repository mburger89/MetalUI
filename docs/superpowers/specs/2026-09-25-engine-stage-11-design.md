# Engine replacement, stage 11 — modifier unification (design)

Plan task 7, stage 11: the last row of
[`2026-09-17-engine-replacement-design.md`](2026-09-17-engine-replacement-design.md)
§4.1 (`LR-V`, §8). Branch `feat/engine-stage-11` from `47c0d98`. Rulings
`LR-FV`…`LR-FZ` in
[`../2026-09-17-engine-replacement-decisions.md`](../2026-09-17-engine-replacement-decisions.md);
measurements in `docs/record/54-engine-replacement-stage-11.md`.

**Status: design.** No file under `Sources/` or `Tests/` changed in a commit.
Two scratch measurements were applied, run and reverted (`git checkout
Sources`, scratch tests deleted, `git status --short` showing only this
design's docs and probes afterwards); record §54 §3–§4 has them.

## Contents

1. Baseline
2. What stage 11 owns
3. The unified type
4. Opacity order (G4, divergence 45, `OM-AA` a)
5. The legacy `.overlay`
6. The other stage-11 items
7. Lanes
8. Accounting, pixels, stack budget, gates
9. Task 7's close: what the Record phase must check
10. Deferred, with owners
11. Risks

---

## 1. Baseline (`47c0d98`, measured 2026-09-24)

- `swift build --build-system native --build-tests`: 0 `error:`, one
  `warning:` (SwiftPM's deprecation notice). `swift test --build-system
  native --no-parallel`, unfiltered: **`Test run with 1426 tests in 3 suites
  passed`**; the guards ran (`FR-J no-argument frame: succeeded=` in the log).
  Goldens 0; guards 82.
- **Probes re-run** on macOS 27.0 (26A428), Apple Swift 6.4, script form:
  `swiftui-outer-modifier-order.swift`, `swiftui-overlay-primary-shape.swift`
  and `swiftui-border-clip-paint.swift` each reproduced its recorded output byte
  for byte, controls included. `swiftui-border-clip-paint.swift` then gained
  **group H** (three arms, `LR-FW`), run in both forms, byte-identical, the
  twenty-six earlier lines unchanged. Each header carries the re-run.
- **Value sizes** (`MemoryLayout`, debug, macOS arm64): `Decoration` 77,
  `Handlers` 320, `ModifierLayer` 662, `LayoutModifier` 46,
  `ModifiedElement<Box<EmptyGroup>>` 1272, `Box<EmptyGroup>` 600,
  `ModifiedContent<Rectangle>` 62, `ModifiedContent<ModifiedContent<Rectangle>>`
  110, `OverlayModifier<Rectangle, Rectangle>` 23; `demoContent()` **33 912**,
  `nativeLayoutPreviewContent()` 935, `textInputDemoContent()` 5 312.
- **Smallest thread stack that builds every production tree** (the
  `DemoStackBudgetTests` harness in exit tests, 16 KB steps): SIGBUS at 512 KB,
  success at 528 KB — **> 512 and ≤ 528 KB**.

## 2. What stage 11 owns

Every hand-off to stage 11 in records §29, §38, §41, §48–§53, the parent spec
and the source, found by `grep -rn -i "stage 11\|task 7's unification"` over
`Sources`, `Tests` and those records:

| # | item | handed by | disposed in |
|---|---|---|---|
| 1 | `ModifiedElement`/`ModifiedContent` unified | outer-modifiers spec §9, modifier-composition decisions `MC-A`, `LR-V` | §3, `LR-FV` |
| 2 | legacy `.overlay` | `CN-Q`, outer-modifiers §9 | §5, `LR-FX` |
| 3 | `.opacity` reaching a background written after it (G4, divergence 45) | `OM-N`, outer-modifiers §9 | §4, `LR-FW` |
| 4 | `.opacity` answering the same on both paths | `OM-AA` a | §4, `LR-FW` |
| 5 | `deferred.amended` — `Component.width` over a presentation member | `LR-CK`, `LR-FF`; `UnlowerableField.owner`; record §51 §3, §53 §6.3 | §6.1, `LR-FY` |
| 6 | `Component.width`/`height` and `StyledComponent.width`/`height` reconciled with `.frame` | `LR-ER` item 2, `LR-EY` item 3; `Component.swift:495, 509, 535` | §6.2, `LR-FY` |
| 7 | a multi-member `Component`'s absolute `.frame` in a `Deferred` reports `modifierLayer.style` "owner stage 11, with `Component.frame`" | `LegacyLowering.swift:411`, `PresentationLoweringTests.swift:640` | §6.3, `LR-FY` |
| 8 | the parent row's exit cites "the outer-modifier-order probe's G3/G4 arms", which that probe does not have | §4.1 row 11, `LR-V` | §6.4, `LR-FY` |

Divergence **46** (a second `.opacity` on one legacy element replaces the
first, `OM-AH`) is **not** stage 11's — no row hands it here, and `OM-AH`
keeps it on reasoning this stage does not overturn (§10).

## 3. The unified type (`LR-FV`)

### 3.1 The shape

```swift
public struct ModifiedContent<Content: ElementGroup, Modifier: ModifierLayerKind>: Element {
    public var content: Content
    var outermost: Modifier          // the layer StyledElement's accessors / `.modifier` read
    var inner: [Modifier]            // every other layer of this vocabulary, innermost first
    var prefix: [LayoutModifier]     // proposal layers a legacy wrapper absorbed, innermost of all
}

@MainActor public protocol ModifierLayerKind {       // not for conformers (§3.7)
    var _elementID: ElementID? { get set }
    mutating func _requestLayout(_ id: GlobalElementID, children: [LayoutNodeID],
                                 pass: inout LayoutPass) -> LayoutNodeID
    func _prepaint<R>(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PrepaintPass,
                      inside: () -> R) -> R
    func _paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, pass: PaintPass,
                inside: () -> Void)
    static func _legacyStack(_ outermost: Self, _ inner: [Self], _ prefix: [LayoutModifier])
        -> (prefix: [LayoutModifier], layers: [ModifierLayer])
}
extension ModifierLayer: ModifierLayerKind { … }     // the legacy arm, moved verbatim
extension LayoutModifier: ModifierLayerKind { … }    // the proposal arm, moved verbatim

public typealias ModifiedElement<Content: ElementGroup> = ModifiedContent<Content, ModifierLayer>
```

**`ModifiedContent` survives and takes SwiftUI's second generic parameter**;
`ModifiedElement` becomes a public, **undeprecated** generic typealias for
`ModifiedContent<Content, ModifierLayer>`. The second parameter names the
chain's **vocabulary** — its layer type — not a single modifier: a chain is
flat whatever its length, as `MC-A` made the legacy one (plan task 3's "a
representation that can nest without forcing callers to expose ever-growing
types"), so the proposal chain stops nesting too:

| spelling | type at `47c0d98` | type after |
|---|---|---|
| `Box().padding(4).frame(width: 60)` | `ModifiedElement<Box<EmptyGroup>>` | `ModifiedContent<Box<EmptyGroup>, ModifierLayer>` (= `ModifiedElement<Box<EmptyGroup>>`) |
| `Rectangle().padding(e).frame(width: 60)` | `ModifiedContent<ModifiedContent<Rectangle>>` | `ModifiedContent<Rectangle, LayoutModifier>` |
| `Rectangle().padding(e).padding(Pixels(8))` | `ModifiedElement<ModifiedContent<Rectangle>>` | `ModifiedContent<Rectangle, ModifierLayer>`, `prefix == [.padding(e)]` |
| `Rectangle().padding(Pixels(8))` | `ModifiedElement<Rectangle>` | `ModifiedContent<Rectangle, ModifierLayer>` |
| `Rectangle().overlay { … }` | `OverlayModifier<Rectangle, …>` | unchanged |

**Why not the other two shapes** (skeleton probe
`docs/probes/stage-11-unified-modifier-skeleton/`, record §54 §2):

- **SwiftUI's nesting** (`ModifiedContent<ModifiedContent<C, M1>, M2>` for
  every modifier) cannot hold a run-time layer count in one type, and
  `growableChain(_:adding:)` (`addingALayerAtRunTimeResetsTheWrappedElementsState`)
  and `labelledChain(adding:)` (`TrackInteractionTests`) are written against
  exactly that; nesting would have to edit the state-retention tests this stage
  must leave unedited.
- **A one-parameter flat type** would be `StyledElement` unconditionally and
  `ProposalElement` whenever its content is proposal content, and
  `.background(token)`/`.opacity`/`.border`/`.allowsHitTesting` are declared on
  both protocols with different results (`Self` vs a new layer), so every
  proposal chain's decoration call becomes ambiguous; choosing by the *base*
  content instead would turn today's `Rectangle().padding(Pixels(8)).background(x)`
  (one id level) into two id levels.

### 3.2 Conformances, and why the vocabularies cannot collide

- `ModifiedContent: Element` — unconditional; one layer recursion (§3.3).
- `ModifiedContent: StyledElement where Modifier == ModifierLayer` — `style`,
  `decoration`, `handlers`, `elementID` read and write `outermost`, as
  `ModifiedElement`'s did.
- `ModifiedContent: ProposalElementGroup, ProposalElement where Content:
  ProposalElementGroup, Modifier == LayoutModifier`, with `typealias
  ProposalBase = Content` and an appending `_wrapLayout`.
- `ElementGroup.LayerBase == Content` **for both vocabularies** (one witness —
  `Swift` allows no other): `_wrap` on a proposal chain absorbs its layers into
  the new legacy chain's `prefix` (`LayoutModifier._legacyStack`), so a legacy
  wrapper after a proposal chain yields the legacy vocabulary with the same id
  path `ModifiedElement<ModifiedContent<X>>` had.
- **`ProposalElementGroup` gains `associatedtype ProposalBase:
  ProposalElementGroup = Self` and `func _wrapLayout(_: LayoutModifier) ->
  ModifiedContent<ProposalBase, LayoutModifier>`**, defaulted where
  `ProposalBase == Self` — `MC-A`'s `LayerBase`/`_wrap` design, mirrored. Every
  proposal modifier on `ProposalElementGroup` (`frame` ×2, `nativeFrame` ×2,
  `padding(Edges<Pixels>)`, `fixedSize`, `background(_: ColorToken)`, `clip`,
  `border`, `opacity`, `allowsHitTesting`, `aspectRatio`, `layoutPriority`, and
  their deprecated `native…` spellings) returns `ModifiedContent<ProposalBase,
  LayoutModifier>` through `_wrapLayout` — **one overload each, as today**.
- A legacy chain is never a `ProposalElementGroup` and a proposal chain never a
  `StyledElement`, so each decoration spelling has exactly one candidate
  (skeleton: `.background(Token())` resolves on both chains; `Rect().padding(1).id(2)`
  is rejected, `Rect().padding(Pixels(8)).opacity(0.5).id(2)` compiles).

**The typed and untyped entries.** `Element.requestLayout` (the root, a legacy
parent) registers the content through `requestGroupLayout`; the conditional
`requestProposalLayout` (a proposal parent) through `requestProposalGroupLayout`;
**both then call one shared `wrapLayers(contentNodes:…)`**, so only the
content-entry line is written twice. At `47c0d98` a proposal `ModifiedContent`
at the root reached the typed entry through `ProposalElement`'s default; after,
the root uses the untyped one. The two are line-for-line copies for every
built-in group (`MC-H`); only a conformer whose two entries disagree (`MC-G`
hole 1, pinned compile-only by `aProposalGroupWhoseEntryPointsDisagreeStillCompiles`)
can tell, and it already could at every legacy parent.

### 3.3 One layer recursion, and the identity proof

The recursion is `ModifiedElement`'s, moved (its `requestLayout`,
`prepaintLayer`/`prepaintLayerBody`, `paintLayer`), iterating over the virtual
list *prefix, inner, outermost* and dispatching each layer's work to its kind:

| step | `ModifierLayer` arm (legacy) | `LayoutModifier` arm (proposal) |
|---|---|---|
| id | `.child(of: id(next outer), at: 0, name: layer.elementID)`; outermost takes the parent's slot | the same, `name: nil` |
| layout | `lowered(_:childCount:)`, then `animated(_:_:for:pass:)` under the layer's id, then `lowerLegacyLayer` (today's code) | `nativeWrapperNode(for:)` (today's code); no `$anim`, no record |
| prepaint | `registerAndScope(handlers, decoration, …) { inside }` | `allowsHitTesting`/`clip` scope or none (today's `ModifiedContent.prepaint`); **no** `registerHandlers` — so no hitbox, focus or accessibility record, as today |
| paint | `paintDecoration(decoration, …) { inside }` | today's `ModifiedContent.paint` arms |
| per inner layer (`MC-B` mirrors) | `recordElementBounds`, `suppressingAccessibilityIfHidden`, `disablingHitTestingIfHidden`, the `hiddenNodes` paint skip — today's code, now run for proposal layers too, which at `47c0d98` got them from `Element.prepaintGroup`/`paintGroup` at every nested level |

**Every existing id path is byte-identical** (`LR-FV` item 3):

1. *Legacy chains*: the formula and the code are `ModifiedElement`'s.
2. *Proposal chains*: a nested `ModifiedContent` entered its content as a
   group member at cursor 0 with `name: nil` — `.child(of: outer, at: 0, name:
   nil)` — which is the flat recursion's rule with `LayoutModifier._elementID
   == nil`. Skeleton: `Rect().padding(4).frame(…).background(…)` registers its
   layers at `[7]`, `[7, 0]`, `[7, 0, 0]` and the content at `[7, 0, 0, 0]`.
3. *Proposal then legacy*: `[7]` (legacy), `[7, 0]` (proposal), content
   `[7, 0, 0]` — `ModifiedElement<ModifiedContent<Rect>>`'s path.
4. *Overlays*: `OverlayModifier`'s code and `MC-P`'s `-1` are unchanged (§5).
5. The state-retention and identity tests below stay green **unedited** (a lane
   that must edit one has found a defect in this design, and stops):
   `addingALayerAtRunTimeResetsTheWrappedElementsState`,
   `changingALayersValueKeepsTheWrappedElementsState`,
   `aLayerAddedAtRunTimeIsAdoptedByTheNewOutermostLayer`,
   `anIDAfterAChainsLastWrapperNamesTheOutermostLayer`,
   `aGenericWrapOverAChainIsIdenticalToTheFlatChainUnderTheProposalAuthority`,
   `aModifierChainIsIdenticalToHandBuiltNestedBoxesUnderTheProposalAuthority`,
   `stateSurvivesFramesUnderAProposalModifierChain`,
   `theOverlaysPrimaryAndOverlayElementsHaveDistinctIdentities`,
   `aTapOnAnOverlaysPrimaryWritesOnlyThePrimarysState`,
   `hoveringAnOverlaysPrimaryDoesNotHoverTheOverlay`,
   `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`,
   `oneElementValuePlacedTwiceDoesNotShareItsState`,
   `theSevenRetentionSlotsAreMutuallyDistinct`,
   `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`,
   `aModifierChainAllocatesABoundedAmountOverNestedBoxes` (an empty `prefix`
   owns no buffer, so `MC-K`'s bound holds),
   and every `TrackInteractionTests`, `AnimationTests`, `FocusTests`,
   `HitRegionTests`, `AccessibilityTreeTests` test that builds a chain.

Node minting order is unchanged (content first, then each layer innermost
out), so every native work literal (`SA-M`) and every scene is unchanged.

### 3.4 Public API: what changes, and each migration spelling

| change | source-compatible? | migration |
|---|---|---|
| `ModifiedElement<C>` becomes a typealias | **yes** (every `ModifiedElement<X>` annotation, `extension ModifiedElement`, and `ElementGroup._wrap`'s signature still compile — skeleton) | none; its deprecation is task 15's (§10) |
| `ModifiedContent<C>` (one argument) | **no** | `ModifiedContent<C, LayoutModifier>`, or the deprecated `NativeModifiedContent<C>`, retargeted to it |
| a proposal chain's type flattens | **no** for a nested annotation | annotate the flat type, or use `some ProposalElementGroup` |
| `ModifiedContent.content` on a proposal chain | behaviour: it is the **base** content, not the next-inner `ModifiedContent` | read `.content` of the flat chain |
| `ModifiedContent.modifier` | yes, for `Modifier == LayoutModifier`: reads/writes the outermost layer | — |
| `ModifiedContent(content:modifier:)` | yes, constrained to `Content: ProposalElementGroup, Modifier == LayoutModifier`; over an existing chain it nests (same ids, §3.3) | — |
| `ProposalElementGroup` gains `ProposalBase`/`_wrapLayout` | yes (defaulted) | none; a conformer that forwards `_wrapLayout` drops its receiver, `MC-A`'s hole mirrored (§3.7) |
| `OverlayModifier<C, O>`'s constraints widen to `ElementGroup` | yes | — |
| `ProposalElementGroup.overlay(alignment:content:)` moves to `ElementGroup` | yes (one overload, as before) | — |
| `String(describing:)` of a chain type | behaviour | `ModifiedElement<X>` prints `ModifiedContent<X, ModifierLayer>` |
| a proposal container rejecting a **legacy chain** | diagnostic text | now "requires the types 'ModifierLayer' and 'LayoutModifier' be equivalent" (skeleton); a legacy **leaf** still names `ProposalElementGroup` |

### 3.5 What stays a separate type, and why

- **`OverlayModifier<Content, Overlay>`** (and **`BackgroundModifier`**): a
  second subtree has a type of its own, which a flat layer list cannot store
  without erasure (`AnyElement`'s `@State` is inert, so erasure would break the
  overlay-primary-shape answer itself), and it cannot be a third vocabulary
  either — `LayerBase` has one witness, and a legacy wrapper after an overlay
  would have to drop the overlay's subtree to return `ModifiedContent<Content,
  ModifierLayer>`. The outer-modifiers spec's "a second needs a second generic
  parameter, which is the `ModifiedContent` unification" is answered by the
  parameter `OverlayModifier` already has, generalized (§5).
- **`OnTapModifier`** holds a closure and a hover colour; it is not one of the
  two types this row unifies.

### 3.6 Guards and tests that read the old types

- `ModifiedElementCompileGuards` (2): `aNestedModifiedElementCannotBeSpelled`
  keeps its fixtures (the typealias spells the same annotations);
  `aTwentyFourModifierChainTypechecksWithinASolverWorkBudget` must stay green
  **at its literal `solverScopeThreshold` (1000)** with its negative still
  "unable to type-check" — the skeleton shows `extension ModifiedElement` in
  its negative fixture still compiles; if the negative stops exhausting the
  budget, re-spell it as `extension ModifiedContent where Modifier ==
  ModifierLayer` and record why.
- `FrameSizingCompileGuards.everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`:
  its four `ModifiedContent<ProposalLeaf>` pins gain `, LayoutModifier`.
- `ElementGroupTrapTests.proposalLayoutConstructorsRequireProposalContent`:
  `OverlayModifier(content: Text("legacy")) { Rectangle() }` moves from the
  negatives to the positives, and the negative `HStack { Text("legacy").overlay
  { Rectangle() } }` (message naming `ProposalElementGroup`) replaces it;
  `proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`'s
  `-> ModifiedContent<ProposalText>` gains `, LayoutModifier`.
- `ErasureCompileGuards`, `ProposalLayoutCompileGuards`,
  `ProposalNodeIDCompileGuards`: no fixture spells either type (grep); they must
  stay green untouched.

### 3.7 The holes

`ModifierLayerKind`'s requirements are public because it constrains a public
generic parameter. An external conformer compiles and is **inert**: nothing
public builds a `ModifiedContent` over it (the memberwise init is internal; the
public init is constrained to `LayoutModifier`). Pinned by guard G1.2.
`_wrapLayout`, like `_wrap`, is a requirement a conformer can forward; its
`.padding` then drops the receiver. No access-control spelling closes either.

### 3.8 Value sizes

`ModifiedContent` adds one empty array (8 bytes) to a legacy chain; a proposal
chain costs `content + LayoutModifier + 16` for any length, where nesting cost
`content + k × ~48`. Predicted: `demoContent()` moves by less than 1 %; the
smallest stack stays within one 16 KB step of `(512, 528]`. The lanes
**measure** both (§8) — prediction is not evidence.

## 4. Opacity order (`LR-FW`)

**SwiftUI** (border-clip-paint probe): **G3** `background(red).opacity(0.5)`
fades the fill; **G4** `opacity(0.5).background(red)` does not; **H1**
`border(blue, 4).opacity(0.5)` fades the border (rgb(0.57,0.59,1.00)); **H2**
`opacity(0.5).border(blue, 4)` does not (B2's full colour); **H3**
`opacity(0.5).background(red).opacity(0.5)` fades the fill **once**. Rule:
*whatever a view declares after an `.opacity` is outside it.*

**MetalUI at `47c0d98`**: the proposal path already answers all five that way
(each modifier is its own layer); the legacy path fades the fill and the
border in every order, because `opacity`, `background` and `border` are fields
of one `Decoration` whose write order is lost (`OM-H`, `OM-N`). H2 is the
border twin of divergence 45, found by group H.

**The fix — the write order, recorded, not a new layer** (a new layer would
add an id level and move every chain that writes both):

- `Decoration` gains two internal stored `Bool`s, `backgroundFollowsOpacity`
  and `borderFollowsOpacity`, default `false`.
- `.background(_:)`, `.hoverBackground(_:)` and `.focusBackground(_:)` set
  `backgroundFollowsOpacity = true`; `.border`, `.hoverBorder` and
  `.focusBorder` (every overload) set `borderFollowsOpacity = true`;
  `.opacity(_:)` sets both `false`. (The three background spellings resolve
  into the one fill, `focus ?? hover ?? plain`, so the flag is the fill's; a
  direct write of a public field records no order and stays inside, today's
  answer.)
- `paintDecoration`, when `opacity < 1`: a following fill is emitted **before**
  the scope opens, a following border **after** it closes; everything else is
  inside, as today. **Emission order is unchanged** (fill, content, border), so
  only the alpha of the escaped emission changes.
- Divergence 46 is untouched: two `.opacity` writes still replace (H3's legacy
  fill reads 0.5, SwiftUI's single fade; the content reads 0.5 where SwiftUI's
  reads 0.25 — `OM-AH`, still recorded).

**Both paths** then answer G3, G4, H1, H2 and H3 the same (`OM-AA` a closed),
which N2.1 asserts through a `ModifiedContent<…, ModifierLayer>` and a
`ModifiedContent<…, LayoutModifier>` chain — the exit criterion's "through the
unified type". **Divergence 45 retires** (Record phase: record §04; 58 → 57
live per CLAUDE.md's count, which the Record phase re-counts).

## 5. The legacy `.overlay` (`LR-FX`)

- `OverlayModifier<Content: ElementGroup, Overlay: ElementGroup>`, conforming to
  `ProposalElementGroup, ProposalElement where Content: ProposalElementGroup,
  Overlay: ProposalElementGroup`. **One** `.overlay(alignment:content:)`
  overload, on `ElementGroup` (the `ProposalElementGroup` one is deleted, the
  deprecated `nativeOverlay` kept), so no chain gains a candidate.
- Identity: `MC-P`, unchanged — the primary numbers from 0 under the modifier's
  id, the overlay from 0 under `.child(of: id, at: -1, name: nil)`.
- Layout: the untyped entry registers both sides through `requestGroupLayout`,
  the typed one through `requestProposalGroupLayout` (§3.2's split, one shared
  body). Both sides then go through **`lowerAttachmentChildren`**, new in
  `Sources/MetalUI/AttachmentLowering.swift`: each node's `LoweredItem` is
  consumed and planned at `parentKind: .stack`, `parentSite: .modifierLayer`,
  and registered — exactly a frame layer's single-node arm (`LR-AZ`: `flexGrow`,
  `flexShrink`, `flexBasis`, `alignSelf`, `margin` dropped; a `minSize` on an
  `auto` axis planned). A proposal node carries no record, gets an empty plan
  and is registered unwrapped, so a proposal overlay mints exactly the nodes it
  did (N1.6). `parentSite` is reachable only through `flexGrow.weights`, which a
  `.stack` plan never raises (`LR-BM`), so reusing `.modifierLayer` adds no
  unreachable site to `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.
- The attachment itself is `requestSecondaryContentAttachment` (today's),
  called with the lowered nodes.
- **Presentations**: an overlay-side `Deferred` is dropped
  (`droppingPresentations`) as every lowered container drops it — it presents
  against the window (`N3.1`); a **primary** that is a presentation is dropped
  too, leaving zero primary nodes, and the existing precondition traps naming
  the count (N1.5). An overlay has nothing to be proposed from a portal's
  placeholder; a trap by name is the answer, not a 0×0 overlay at an in-flow
  point.
- Paint and prepaint: unchanged (primary, then overlay).
- **Not here**: a legacy `.background { content }` (§10).

## 6. The other stage-11 items (`LR-FY`)

### 6.1 `deferred.amended`

Measured (record §54 §3): `Box { SSolo().frame(width: 70) }` — a legacy
`.frame` **layer** over a presentation member — reports nothing and puts the
presented box's hitbox at **(5, 5) 10×10**; `Box { SSolo().width(70) }`
reports `deferred.amended` with the hitbox at the same (5, 5) 10×10. The amend
therefore answers **as the `.frame` layer already does**: the placeholder is
handed on and dropped (`LR-CK`), the presentation's containing block is the
window whatever surrounds it (`N3.1`). `loweredComponentFrame`'s
`isPresentation` branch returns the node without a report; the `amended`
entry is deleted, `UnlowerableField.owner` loses its `"plan task 7, stage
11"` branch (so every owner reads `"plan task 11"` or `nil`), and
`LoweringSite.deferred` **stays** — it is still the site of the placeholder's
own `LoweredItem` (`Deferred.swift:117`).

### 6.2 `Component.width`/`height`, `StyledComponent.width`/`height`

**Reconciled by ruling, no API change.** A `.width` on a component is one
native frame per member (`LR-BG`, SwiftUI's G7/G8 shape for a frame on a
`Group`); `.frame` on a component is one layer over the members' row
(`LR-BH`). They are different modifiers, and both stay undeprecated with their
doc comments saying so. Making `.frame` distribute per member (SwiftUI's
`Group` answer) would move members and add id levels — `Group` semantics is
plan task 8's (`CN-Q`, "builder wrappers with zero or several nodes"), and it
takes this with it (§10).

### 6.3 A multi-member absolute `.frame` in a `Deferred`

Measured (record §54 §4): with `legacyFrameLayerDiagnostics`'
`&& childCount <= 1` removed, `Box { Deferred { SPair().frame(width: 20,
height: 20).position(.absolute).inset(top: 10, left: 30) } }` reports nothing
and places its two 10×10 members at **(35, 15)** and **(55, 15)**: `LR-BH`'s
row of per-member 20×20 frames, laid out as the presentation's element at the
insets — the same relative shape as the in-flow row (members 20 apart). The
condition is deleted; the row is the presentation root.

### 6.4 The exit citation

G3/G4 are `swiftui-border-clip-paint.swift`'s arms; `swiftui-outer-modifier-order.swift`
has groups C, L, A, B, D, E, F and no G. The exit is read as **border-clip-paint
G3/G4 (plus group H) and overlay-primary-shape P1–P5/A/B/Q**, through the
unified type. The probe headers and this ruling say so; the parent row is
corrected by the Record phase.

## 7. Lanes

Two lanes, **run in order** (lane 2's exit test annotates the lane-1 type);
the files are disjoint. Each lane: commit, build under both build systems, run
the whole suite unfiltered, read the summary line; `swift package clean`
first (public generic arity, `OverlayModifier`'s constraints and `Decoration`'s
stored properties all cross module boundaries).

### Lane 1 — the unified type and the legacy overlay (Opus)

**Files.** New `Sources/MetalUI/ModifiedContent.swift` (the struct,
`ModifierLayerKind`, the recursion, the conditional conformances,
`typealias ModifiedElement`) and `Sources/MetalUI/AttachmentLowering.swift`;
`ModifiedElement.swift` (keeps `ModifierLayer`, gains its `ModifierLayerKind`
arm, keeps the fixed `frame` overload and `_wrap`'s default, `FR-S`);
`NativeModifiedContent.swift` (`LayoutModifier`'s arm; proposal modifiers
through `_wrapLayout`; `NativeModifiedContent` retargeted);
`ProposalElementGroup.swift` (`ProposalBase`, `_wrapLayout` and its default;
the unconditional `ModifiedContent: ProposalElement` line deleted);
`NativeOverlayModifier.swift`, `NativeBackgroundModifier.swift` (the attachment
helper's input); doc lines in `ElementGroup.swift`, `DecorationScope.swift`,
`Element.swift`, `ProposalNodeID.swift`. Tests: new
`Tests/MetalUITests/UnifiedModifiedContentTests.swift` and
`UnifiedModifiedContentCompileGuards.swift`; body changes in
`ModifiedElementTests.swift`, `NativeLayoutIntegrationTests.swift`,
`FrameSizingCompileGuards.swift`, `ElementGroupTrapTests.swift` (and
`ModifiedElementCompileGuards.swift` only under §3.6's condition). **Not**
`Box.swift`, `AnimatedColor.swift`, `LegacyLowering.swift`,
`LayoutAuthority.swift`, `Component.swift` (lane 2's).

| test | red before (at `47c0d98`) | mutation that must redden it |
|---|---|---|
| **N1.1** `aProposalChainIsOneFlatModifiedContentWithTheNestedChainsIdentities` — `Rectangle(…)`-probe `.padding(e).frame(w).background(t)` vs the same built with three nested explicit `ModifiedContent(content:modifier:)` inits, compared on every `elementBounds` key and rect, `tree.nodeCount`, `lastNativeLayoutWork` and the scene's rects; disagreeing oracle: the chain with its middle layer removed (the `#require`d disagreement); plus `type(of:) == ModifiedContent<…, LayoutModifier>.self` | does not compile (two-argument type); semantically the chain nests | **M1a** delete `typealias ProposalBase = Content` (chains nest; the type assertion); **M1b** a `LayoutModifier` inner layer's id `at: 1`; **M1i** skip `recordElementBounds` for an inner proposal layer |
| **N1.2** `aLegacyWrapperAfterAProposalChainAbsorbsItAsItsInnermostLayers` — `Rectangle().padding(e).padding(Pixels(8)).background(.accent)`: type `ModifiedContent<Rectangle, ModifierLayer>`, id literals `root`, `.child(root, 0)`, content `.child(.child(root, 0), 0)`, the fill at the padded box, node count literal derived at `47c0d98` | does not compile | **M1d** `LayoutModifier._legacyStack` drops the prefix (node count, rect); **M1d′** absorbed layers placed outermost (rect) |
| **N1.3** (exit) `aLegacyOverlayKeepsItsOverlaysStateThroughAFlipOfItsPrimarysShape` — the overlay-primary-shape arms with `anOverlaysIdentityDoesNotDependOnTheIndicesItsPrimaryConsumed`'s instrument (taps into the overlay's own `@State`, read after each flip): L1 `Box { if flag { Box() }; Box() }`, L2 `Box { if flag { EmptyComponent() }; Box() }`, L3 L1 `.padding(Pixels(2))` (a legacy `ModifiedContent`), L4 `ZStack { if flag { Rectangle() }; Rectangle() }.padding(e)` (a proposal `ModifiedContent`) — each keeps its taps through false→true; controls A (no flip, kept), B (`Box { tally }.id("g\(g)")`, reset every generation), P5 (a stateful probe inside the primary's conditional: present, absent, new) and Q (the overlay's own `if/else`, reset) | does not compile (legacy primaries) | **M1c** overlay side under `.child(of: id, at: 0)`; **M1c′** one cursor threaded through primary and overlay |
| **N1.4** `aLegacyOverlayConsumesItsPrimarysAndOverlaysRecordsAsAFrameLayerDoes` — in a `Row`, a `Box` primary declaring `flexGrow(1)` and an overlay `Box` declaring `margin`, under diagnostics: the report is empty, the grow and the margin are dropped (rect literals), the overlay is placed by `alignment` over the primary's rect | does not compile | **M1e** skip consuming the primary (report `…unconsumed`); **M1e′** skip consuming the overlay side |
| **N1.5** (exit test) `anOverlayOnAPresentationTrapsNamingItsPrimaryCount` — a production frame over `Deferred { … }.overlay { Box() }` exits with failure, stderr containing `requires one primary node, got 0` | does not compile | **M1f** the primary not passed through `droppingPresentations` |
| **N1.6** `aProposalOverlayRegistersExactlyTheNodesItDidBeforeUnification` — `ZStack { Rectangle(…).padding(e).overlay { Rectangle(…) }.opacity(0.5) }`: `tree.nodeCount` and `lastNativeLayoutWork` equal literals taken at `47c0d98` before the change (a must-not-move pin, green on both sides by design, stated in its doc) | — | **M1g** `lowerAttachmentChildren` wraps a record-less child in a frame |
| **G1.1** `aProposalModifierChainInfersOneFlatModifiedContent` (`typecheckFile`) — `let c: ModifiedContent<Leaf, LayoutModifier> = Leaf().padding(e).frame(width: w).background(.accent)` compiles; the nested annotation is rejected; `#require`d to disagree | the positive does not compile | **M1a** |
| **G1.2** `anExternalModifierLayerKindCannotBuildAModifiedContent` (`typecheckFile`) — an external conformer compiles; building a `ModifiedContent` over it does not | the conformer does not compile (no protocol) | **M1h** the memberwise init made `public` |

Body changes (T), each with its reason in the lane's record section:
`legacyModifierChainsInferOneConcreteType` (expected strings become
`ModifiedContent<…, ModifierLayer>`),
`nativeModifierChainsRemainConcreteAndWrapInDeclarationOrder` and
`proposalLayoutFrameUsesTheTypedProposalWrapper` (annotations),
`everyFrameSpellingOnAProposalElementResolvesToTheProposalOverload`,
`proposalLayoutConstructorsRequireProposalContent`,
`proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`. None
changes its answer except the overlay arm of
`proposalLayoutConstructorsRequireProposalContent`, whose change is this
lane's subject.

### Lane 2 — opacity order and the owned lowering items (Opus)

**Files.** `Box.swift` (`Decoration`'s two fields; the background, border and
opacity modifiers; doc mentions of `ModifiedElement`'s recursion),
`AnimatedColor.swift` (`paintDecoration`), `LegacyLowering.swift`
(`loweredComponentFrame`'s presentation branch, the one-node condition, their
docs), `LayoutAuthority.swift` (`owner`, the `.deferred` doc), `Component.swift`
(docs, §6.2). Tests: `DecorationPaintTests.swift`, new
`Tests/MetalUITests/OpacityOrderTests.swift`,
`PresentationContainingBlockTests.swift`, `PresentationLoweringTests.swift`,
`LayoutAuthorityTests.swift`.

| test | red before | mutation that must redden it |
|---|---|---|
| **T2.1** `opacityReachesABackgroundWrittenAfterItWhereSwiftUIDoesNot` → renamed `aBackgroundOrBorderWrittenAfterOpacityEscapesIt` — arms G3, G4, H1, H2, H3 on a bare `Box`, emitted alphas against the opaque control; `#require` G3 ≠ G4 and H1 ≠ H2 | G4 reads `0.5 × a` (faded), H2's border faded | **M2a** `.background` stops setting the flag; **M2b** `paintDecoration` ignores it; **M2c** `.opacity` stops clearing the flags (H3); **M2d** the border flag ignored (H2); **M2e** the flag inverted (G3; also `opacityMultipliesAndFadesTheElementsOwnBackground`) |
| **N2.1** (exit) `theOpacityOrderAnswersTheSameOnBothPathsThroughTheUnifiedType` — G3, G4, H1, H2, H3 as annotated `ModifiedContent<Box<EmptyGroup>, ModifierLayer>` chains (`.padding(Pixels(2))` first) and `ModifiedContent<Rectangle, LayoutModifier>` chains (`.padding(e)` first); per arm the two paths' alphas are equal, and per path the order arms disagree | does not compile; semantically the legacy G4 and H2 arms disagree with the proposal ones | **M2a**, **M2d**; **M2h** `LayoutModifier`'s `.opacity` arm paints its content outside the scope (proposal G3) |
| **N2.2** `aComponentAmendOverAPresentationMemberAnswersAsAFrameLayerDoes` — `.width(70)`, `.height(70)` and a `StyledComponent`'s `.width(70)` over a presenting member vs the same `Deferred` under `.frame(width: 70)`: empty reports, hitboxes (5, 5) 10×10 | reports `["deferred.amended"]` | **M2f** the report restored |
| **N2.3** `aTwoMemberAbsoluteFrameInADeferredIsARowOfPerMemberFramesAgainstTheWindow` — empty report, hitboxes (35, 15) and (55, 15) 10×10 | reports `["modifierLayer.style"]`, hitboxes 0×0 at (0, 0) | **M2g** `&& childCount <= 1` restored |

Body changes (T): `aPresentationsContainingBlockIsTheWindowWhateverSurroundsIt`
(its amended arm leaves, to N2.2), `everyReportNamesALiveOwnerOrIsRefusedByName`
(the `deferred`/stage-11 row leaves), and
`aFramedAbsoluteBoxStillReportsEveryOtherFieldAndItsPositionOutsideADeferred`
(arm 3 leaves, to N2.3; its doc's M1h line updated).

Lane 2 also measures the value sizes and the stack budget (§8) after both
lanes.

## 8. Accounting, pixels, stack budget, gates

- **Suite: 1426 → 1437** (+8 lane 1: N1.1–N1.6, G1.1, G1.2; +3 lane 2: N2.1–N2.3;
  T2.1 is a rename; no test retired). **Guards 82 → 84.** Goldens 0.
  `goldensUnchanged`: no `@Test` is removed, so no retirement row is owed; the
  T rows above are the only retained tests whose bodies change, and only
  `proposalLayoutConstructorsRequireProposalContent`'s overlay arm and the
  renamed T2.1 change an answer, both as ruled.
- **Pixels: 0 differing in all fourteen images** against `47c0d98`
  (`docs/probes/demo-pixels/compare.sh`). No demo site writes a legacy
  `.opacity` before a `.background` or `.border` (the demo's two `.opacity`
  calls are on proposal chains, already SwiftUI-shaped), and every chain keeps
  its nodes, ids and emissions. Any non-zero difference is a finding, not a
  named change. `Expected.swift` (`theDemoFrameMatchesTheValuesRecordedOnMacOS`)
  must not move; `Backends/SDL`'s `PortableReplay` and `DemoCapture` must read
  0 px.
- **Stack budget**: re-take §1's sizes and the smallest-stack bisection (16 KB
  steps, then 4 KB) after lane 2; `everyProductionTreeBuildsOnAOneMegabyteThread`
  green. Record before/after.
- **Gates**: 0 `error:`, 0 `warning:` beyond SwiftPM's notice under **both**
  build systems (`swift build --build-tests` too); `MetalUILayout` imports only
  `MetalUICore` (no file of it changes); `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  and the three `StyleSurfaceCompileGuards` green; `Backends/SDL` builds and
  tests (`PKG_CONFIG_PATH=$PWD/.accesskit`); a `swift:6.4-noble` container, if
  Docker is available, builds the root package and runs `MetalUICoreTests`,
  `MetalUILayoutTests`, `MetalUICrossPlatformTests`.
- **Mutations**: commit first; restore from a copy; the full unfiltered suite
  per mutation; `git status --short` after each; name every test reddened, and
  which spelling and branch the mutation was applied to.

## 9. Task 7's close: what the Record phase must check

Task 7 is ticked in the plan **only** if the adversarial branch check confirms
each row's exit criterion **on this branch** — reading the test or grep, not a
record's claim. Where a later stage retired a row's named exit test, the check
names the replacement and confirms it:

| row | exit criterion (§4.1) | what to confirm |
|---|---|---|
| 1 | `theStageOneCorpusLowersWithNoDiagnosticAndAgreesElementByElement` | absent from `Tests` — retired with the two-engine harness (stage 9, `LR-FI`); confirm the retirement row and that the corpus lowers with no diagnostic today |
| 2 | `theWholeDemoReportsExactlyTheFieldsAndSitesLaterStagesOwn` (5.3) | present (`LoweringCorpusTests.swift`); confirm it now asserts an empty report |
| 3 | `ScrollRoutingTests`/`ScrollIndicatorTests` under the proposal authority | the files run under the only authority |
| 4 | `aListsWorkIsTheSameFor100kRowsAsFor500`, `ListTests`' windowing arms | present; run it gated (`METALUI_RUN_100K_LIST_TEST=1`) |
| 5 | `DeferredTests`, `AbsoluteOverlayTests` under the proposal authority | present, green |
| G | the grids probe's arms | `GridTests` et al. green; probe headers |
| 6a | 0 `warning:` with the deprecation; `aDeprecatedRegistrarStillLays…` | the registrars are deleted (stage 9); confirm the retirement row and 0 warnings |
| 6b | `noProductionFrameReachesTheLegacyEngine` | retired at stage 9, replaced by 10's `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` — confirm it passes and cannot skip |
| 7a | `find Tests -name "*.json" \| wc -l` = 0 (excluding `.build`) | 0 at `47c0d98` |
| 7b | retirement table; `grep -rn "computeLayout(" Tests` empty | 0 hits at `47c0d98` |
| 8 | 0 `warning:`, demo 0 px against 6b | records §50 |
| 9 | suite green with the engine files gone | `git ls-files Sources/MetalUILayout` |
| 10 | `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` + guards + grep | green |
| 11 | this stage's N1.3 and N2.1 | green, and their mutations recorded |

The Record phase also writes task 7's closing summary in the plan and in
CLAUDE.md, retires divergence 45 (record §04), updates CLAUDE.md's
`StyledElement` sites ("`ModifiedElement` (per layer)" → the unified type's
legacy arm), its `.overlay` sentence and its identity bullets, and corrects
the parent row's G3/G4 citation.

## 10. Deferred, with owners

| item | why not here | owner |
|---|---|---|
| deprecating or removing the `ModifiedElement` typealias | a public spelling decision with no behaviour, alongside the eight deprecated sizing modifiers (`LR-FN` item 5) | plan task 15 |
| a legacy `.background { content }` | not in the row; its `ElementGroup` overload would add a candidate to every legacy `.background(token)` call, the budget guard's own fixture | plan task 8 |
| `.frame` on a multi-member `Component` distributing per member (SwiftUI's `Group`) | `Group` semantics | plan task 8 (`CN-Q`) |
| divergence 46 (two `.opacity` calls replace) | `OM-AH`'s reasons stand; no row hands it here | recorded, kept |
| `OnTapModifier` and `BackgroundModifier` as layers | not the two types this row names | plan task 8 |

## 11. Risks

- **Solver work.** `ProposalBase` mirrors `LayerBase`, measured cheap in
  `MC-A`; the real overload set is the budget guard's to judge, and lane 1 runs
  it before anything else.
- **Typed vs untyped content entry at a root** (§3.2): visible only to a liar
  conformer.
- **A diagnostic moves** (§3.4): a legacy chain in a proposal container no
  longer names `ProposalElementGroup`. The three guards that read that message
  at `47c0d98` — `ElementGroupTrapTests.swift:97`,
  `EnvironmentCompileGuards.swift:232`, `GridCompileGuards.swift:57` — each
  reject a leaf or an environment scope, never a chain (grepped), so none moves.
- **Reflection counts.** Fewer distinct nested types means fewer `StateBinder`
  cache misses; `StateTests.swift:196` pins `reflectionCount == 2` for its own
  fixture, which builds no proposal chain — lane 1 confirms.
