# SwiftUI layout replacement inventory

**Status:** baseline for task 1 of
`plans/2026-09-12-swiftui-alignment.md`. This is a migration inventory, not an
implementation specification. It identifies what the new layout kernel owns and
what the existing CSS-derived system must eventually lose.

**Updated 2026-09-14 (checked against `7cfcddc`).** Dispositions below that
have been acted on carry a dated note.

The work so far has built a *parallel* proposal-layout surface beside the CSS
elements rather than re-lowering them:
- the kernel, in `LayoutTree.swift`'s native section;
- `HStack`/`VStack`/`ZStack`/`Spacer`/`Rectangle`/`Color`;
- `ProposalFrame`/`Padding`/`Background`/`FixedSize`;
- `ProposalScrollView` and `ProposalText`;
- `ModifiedContent`, `OverlayModifier` and `OnTapModifier`.

`Row`, `Column`, `Stack`, `Box`, `ScrollView`, `List` and `Text` still lower
through `FlexEngine`.

## Target model

MetalUI layout will follow SwiftUI's direction of travel:

1. A parent proposes an optional width and height to each child.
2. A leaf or container reports the size it needs for that proposal.
3. The parent places the measured children within its resolved bounds.

Proposal, measurement, and placement are distinct operations. A container is
not a CSS `display` mode; it is a layout algorithm. Modifier order is expressed
by typed wrapper nodes, rather than by mutating one inherited style bag.

This does **not** alter MetalUI's three rendering phases. Elements still build
a fresh tree in `requestLayout`, resolve geometry before `prepaint`, and paint
after handler registration. The new tree must keep generation-stamped node IDs
and root-absolute bounds, since state, hit testing, scrolling, painting and
accessibility already depend on those contracts.

## Current production seam

```
Element.requestLayout
  -> LayoutPass.requestNode(style:children:) / requestLeaf(style:measure:)
  -> LayoutTree { Style, child IDs, CSS MeasureFunction, resolved rect }
  -> Frame.computeRootLayout
  -> computeLayout / FlexEngine
  -> Frame.bounds(of:) -> prepaint -> paint
```

`Frame`, `LayoutNodeID`, tree generation checks, root-absolute resolved bounds,
the phase boundary, and leaf content measurement are retained. The `Style`
payload and the `computeLayout` implementation are not.

The public `LayoutPass.requestNode(style:children:)` and
`requestLeaf(style:measure:)` methods make the legacy representation externally
reachable. Task 2 must introduce replacement registration methods before these
are deprecated; deleting `Style` first would strand custom `Element`
implementations.

*2026-09-14 (at `7cfcddc`).* A second seam now sits beside the first:

```
Element.requestLayout
  -> LayoutPass.requestNative*(…)            (Passes.swift:60-129, 11 methods)
  -> LayoutTree native store { NativeNode }  (LayoutTree.swift:53, 110-266)
  -> Frame.computeRootLayout: tree.isNativeLayoutNode(root)?   (Frame.swift:1166)
  -> computeNativeLayout(root:proposal:in:)  (LayoutTree.swift:275)
  -> Frame.bounds(of:) -> prepaint -> paint
```

The ordering above was kept: replacement registration methods exist, and
`requestNode`/`requestLeaf` are still not deprecated (`Passes.swift:32, 49`).

The replacements can register only a leaf or one of eleven built-in algorithms
(`NativeNode` is a `private enum`, `LayoutTree.swift:835`). No API registers a
custom layout algorithm, so an external custom **container** has no migration
path yet. An external custom leaf does: `pass.requestNativeLeaf` plus a
`ProposalElementGroup` conformance, as the demo's `PriorityPreviewPanel` does
(`Sources/MetalUIDemo/main.swift:913-938`).
*Corrected 2026-09-14 (`00a1e22`, `SA-A`…`SA-F`):* a custom algorithm now
registers through `ProposalLayout` (`newNativeLayout` /
`LayoutPass.requestNativeLayout` / `ProposalLayoutContainer`), stored as a
twelfth `NativeNode` case, `custom`; an external custom container's migration
path is the table under "Completion criteria for task 1" below.

The root switch reads only the root. Every native node still also occupies a
`Style.default` slot in the legacy arrays (`LayoutTree.swift:111`).

## CSS-debt map

| Existing concept | Current owner | Replacement or disposition |
| --- | --- | --- |
| `LayoutTree` graph, generation, resolved rects | `MetalUILayout/LayoutTree.swift` | Retain as the per-frame geometry store, renamed only if it improves clarity. Add proposal/measurement cache and placement data. |
| `Style` | `MetalUILayout/Style.swift` | Retire as the universal layout bag. Split its surviving semantics among typed modifiers, decoration, a container's layout configuration, and explicit presentation/scroll nodes. |
| `Display.flex`, `Display.stack`, `Display.none` | `Style` + `FlexEngine` | Replace with node/layout-algorithm kinds. `Stack`/`Row`/`Column` choose algorithms directly; no generic CSS display switch. |
| Flex direction, wrapping, gaps, distribution and align-self | `Style`, `FlexEngine`, `FlexLines`, `Alignment` | Replace with measured `HStack`/`VStack` algorithms and later explicit flow/grid/custom-layout types. Retire flex names from the public surface. |
| Flex grow, shrink and basis | `Style`, `ResolveFlexibleLengths` | Replace with SwiftUI-style proposal, layout priority, fixed-size, and container-specific expansion/compression rules. Do not mechanically rename flex factors. |
| `aspectRatio` | `Style`, `FlexEngine` | Reintroduce only as SwiftUI-style aspect-ratio modifier semantics, including fit/fill content mode, after the new proposal contract exists. *2026-09-14:* reintroduced on the proposal path only, as `.aspectRatio(_:contentMode:)` on `ProposalElementGroup` (`NativeModifiedContent.swift:269`) over a native node (`LayoutTree.swift:203-211, 753-781`). The fit and fill tests cover only a proposal with both axes finite. `Style.aspectRatio` is still present and still unread. |
| CSS box sizing, padding, border and margin | `Style`, `FlexEngine` | Padding becomes an outer modifier wrapper. Border becomes a render/layout wrapper that retains resolved widths for paint. Margin has no direct SwiftUI counterpart and must be removed or quarantined behind a compatibility API. *2026-09-14:* **Padding** is an outer wrapper on both paths. On the legacy path `StyledElement.padding` returns `Box<Self>`, whose wrapper still carries the value in `Style.padding` (`Box.swift:640-650`). On the proposal path it is a native node (`LayoutModifier.padding`). **Border** draws only on the proposal path: `.border(_:width:cornerRadius:)` paints through the new `PaintPass.fill(…borderColor:borderWidths:)` (`Passes.swift:570-576`) and adds no footprint. Legacy `borderWidth(_:)` still shrinks the content box and paints nothing (`Box.swift:666-676`). **Margin** is unchanged. |
| Percentage and `rem` dimensions | `Dimension`, `Resolve.swift` | Re-evaluate individually. Fixed points survive; percentage sizing needs a measured SwiftUI comparison and may be unsupported rather than inherited. `rem` is not a SwiftUI layout primitive. |
| Position, inset, containing blocks | `Style`, absolute placement in `FlexEngine` | Move to a distinct overlay/presentation or explicit positioned-layout feature. It must not be an implicit CSS containing-block rule in the new kernel. |
| Overflow | `Style`; clipping is actually in `Frame` / `ScrollView` | Remove the inert layout field. Keep clipping and translation as explicit paint/prepaint behaviour owned by scrolling or clipping modifiers. |
| CSS min-content/max-content measurement | `AvailableSpace`, `MeasureFunction`, text engine | Keep only as internal leaf-measurement tools where necessary. Replace CSS's `known`/`available` contract with a proposal result capable of baseline data. *2026-09-14:* the proposal result exists as `ProposalMeasureFunction` → `LayoutMeasurement`, with optional baselines. `ProposalText` measures with `shaped(wrappingAt:)` at `proposal.width.map { max($0, smallestWrapWidth) }` only, with no min-content probe, and reports no baselines (`ProposalText.swift:80-88`). That clamp is why `Text.swift`'s `smallestWrapWidth` lost `private` (`Text.swift:21`). |
| `computeLayout`, `FlexEngine`, `FlexBaseSize`, `FlexLines`, `Resolve*`, `ResolveFlexibleLengths` | `MetalUILayout` | Delete after every production node uses the new kernel and their browser fixtures have a SwiftUI-equivalent proof or are archived as historical migration evidence. |

## Public API classification

| Surface | Status | Migration decision |
| --- | --- | --- |
| `Box` | CSS-derived generic container | Keep as a temporary spelling only. Migrate callers toward typed wrappers and explicit layouts; do not preserve its CSS-default stretch semantics as an implicit framework default. |
| `Row` / `Column` | SwiftUI-inspired facade over flex | Replace their lowering with native horizontal/vertical stack algorithms. Rename only in a source-compatible migration decision; their default spacing must be probe-backed rather than hard-coded. *2026-09-14:* `Row`/`Column` are not re-lowered. Separate proposal `HStack`/`VStack` exist instead. Their 8pt default is a constant (`NativeElements.swift:16, 58`); the kernel's own default is 0 (`LayoutTree.swift:245`). The probe behind the 8pt is recorded only in prose, in the plan and a test doc comment, for one pair of rectangles. They read only the cross-axis factor of their nine-case alignment (`LayoutTree.swift:594-606`), deliberately: `newNativeLinearStack`'s doc comment states it (`LayoutTree.swift:240-243`) and `aNativeLinearStackUsesItsAlignmentOnTheCrossAxisOnly` (`NativeLayoutTests.swift:364`) pins it. |
| `Stack` | SwiftUI-inspired facade over CSS one-cell grid | Replace its lowering with a native overlay/ZStack algorithm; retain the nine-position `Alignment` surface after probe validation. *2026-09-14:* `Stack` is untouched. A separate proposal `ZStack` over the native overlay uses a new nine-case `ProposalAlignment`, pinned by `everyProposalAlignmentPlacesAnOverlayChildAtItsNamedPosition`. No SwiftUI probe is cited for its positions. |
| `.frame(width:height:)` | Additive typed wrapper | Keep and expand to SwiftUI frame constraints and alignment. It becomes the canonical sizing modifier once the composition foundation exists. *2026-09-14:* there are now two `.frame`s, and neither is canonical yet. The legacy one on `ElementGroup` returns `FrameModifier` (`FrameModifier.swift:63-67`), a CSS node that centres its content and does not propose its size to it. It is a handler/animation/background site that no per-conformer guard covers. The proposal one on `ProposalElementGroup` (`NativeModifiedContent.swift:250`) has min/ideal/max and alignment. `nativeFrame(...)` (`:147`) is a non-deprecated duplicate of it. |
| `width`, `height`, min/max and percentage helpers | Direct `Style` mutations | Migrate to frame semantics or deprecate. Percentage helpers do not automatically survive. |
| `.padding` | Outer wrapper for ordinary elements; distributed style on `Component` | Keep the measured component rule, but reimplement it without mutating `Style`. Complete its ordering matrix with background, frame and clipping. *2026-09-14:* the element half landed in `f1944f8`. `StyledElement.padding` returns a default-`Style()` `Box<Self>` wrapper (`Box.swift:640-650`), and chained paddings accumulate (`chainedPaddingCreatesNestedWrappers`). The wrapper adds a layout node and an identity level, and any modifier written after `.padding` now configures the wrapper. The legacy demo's padded containers still write `.alignItems(.stretch)` and `.background` after `.padding` (e.g. `Sources/MetalUIDemo/main.swift:486-490, 859-866`). Its render at this commit is unverified. `Component.padding` still distributes by amending `Style` (`Component.swift:391-393`). The ordering matrix is not written. |
| `.margin`, flex modifier family, `justifyContent`, `alignItems`, `alignContent`, `alignSelf`, `flexWrap` | Direct CSS API | Deprecate and remove from the SwiftUI-facing API. Reintroduce only a genuinely SwiftUI-equivalent capability. |
| `borderWidth`, `cornerRadius`, background | Mixed layout/paint decorations | Separate layout footprint from paint decoration. Fix border rendering as part of the wrapper migration; corner radius remains paint-only until a clip modifier is provided. *2026-09-14:* proposal-path only. `.background`, `.border` and `.clip(cornerRadius:)` exist as paint wrappers on `ModifiedContent`, and `.clip` also scopes hitboxes. None of them animates. Legacy decorations are unchanged. |
| `.position(.absolute)` / `.inset` / `Deferred` | CSS positioning plus a MetalUI portal | Preserve `Deferred` as a documented portal. Redesign absolute position separately around SwiftUI overlay/presentation semantics; do not port CSS containing blocks. |
| `ScrollView` | Two flex nodes plus phase-owned clipping | Replace the two-node flex lowering with a viewport/content layout pair. Keep phase-owned clipping, input routing and stable offset state. *2026-09-14:* `ScrollView` is untouched. A separate `ProposalScrollView` over a native `scrollViewport` node shares `ScrollView`'s scroll-region and `ScrollState` plumbing (`ProposalScrollView.swift:54-139`). It lowers several direct children to a vertical native stack with hard-coded spacing 8 on both axes (`:59-60`), and it does not use `ScrollView`'s animated `$anim-content`/`$anim-viewport` ids. |
| `List` | Windowed flex column with a uniform height | Keep virtualization as an implementation choice, but replace its flex spacers and only-child constraint. Align data identity, scrolling and accessibility with SwiftUI before claiming `List` parity. |
| `Text` | CSS leaf measurement closure | Retain shaping and intrinsic measurement, but change its input from CSS known/available spaces to the new proposal. Carry first/last baselines in the result. *2026-09-14:* `Text` is unchanged. `Text.proposalLayout()` converts it to a separate `ProposalText` leaf that copies only `string`, `fontFamily`, `fontSize` and `foregroundColor` (`ProposalText.swift:93-99`). Style, decoration, handlers and `elementID` are silently dropped. `ProposalText` carries no baselines. |
| `Component`, `Group`, `AnyElement` | Structural composition above the engine | Retain structural identity and measured modifier-distribution rules. Ensure the new node registration API does not make type erasure or component modifiers inert. |

## Migration boundaries and invariants

- There is one active layout authority per rendered subtree. During migration,
  an adapter may host legacy nodes beneath an explicit compatibility boundary;
  arbitrary mixing of flex and native nodes in one container is prohibited.
- The new kernel writes the same root-absolute `LayoutRect` contract consumed by
  `Frame.bounds(of:)`. Prepaint, paint, input, scrolling and animation do not
  acquire a second geometry store.
- Node IDs remain generation-scoped. A new measurement cache is frame-local and
  may not retain `LayoutNodeID`s across frames.
- Every replacement container needs a SwiftUI probe and a discriminating native
  test before its legacy counterpart is removed. Browser goldens are not proof
  of SwiftUI semantics.
- Keep the current engine available only behind an explicit compatibility
  boundary until a migrated root no longer invokes `computeLayout`.

*2026-09-14 (at `7cfcddc`).* How these invariants hold in the source:

- *Rewritten 2026-09-14 (`3c701a2`, ruling `SA-G`).* **One authority per
  rendered subtree.** This holds, and is enforced at run time in every
  direction. There is still no adapter or compatibility boundary below the
  root; the root switch is the boundary, by ruling.
  - A native node under a legacy node traps in `newNode`
    (`aNativeNodeRegisteredUnderALegacyNodeTraps`,
    `aProposalElementInsideALegacyContainerTrapsAtRegistration`).
  - A legacy node under any native registrar traps, custom layouts included
    (`aLegacyNodeRegisteredUnderANativeStackTraps`,
    `aLegacyNodeRegisteredUnderACustomLayoutTraps`).
  - A `Style` written onto a native node traps
    (`aStyleWrittenOntoANativeNodeTraps`,
    `aLegacyStyleModifierOnAProposalComponentTrapsAtRegistration`), and so does
    `computeLayout` on a native root (`computeLayoutRejectsANativeRoot`).
  - Built-in legacy content is still rejected at compile time by the
    `Content: ProposalElementGroup` constraints, now including
    `ProposalLayoutContainer` and `callAsFunction`. The overlay side still has
    no negative case.
  - `ProposalElementGroup` still has no requirements. A lying conformer traps
    at registration
    (`aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`).
    The compile-time check is plan task 3's (`SA-R`).

  *As written at `7cfcddc`, now history:* this held only where the root was
  native, and it was not enforced both ways.
  - A native container traps on a legacy child at registration
    (`LayoutTree.swift:379-385`). No test pins that trap.
  - Built-in legacy content is rejected at compile time by the
    `Content: ProposalElementGroup` constraints. Three typecheck guards reject
    legacy content, in `Tests/MetalUITests/ElementGroupTrapTests.swift:20, 48,
    73`. A fourth, at `:145`
    (`proposalTextSelectsProposalModifiersWithoutMakingLegacyTextAmbiguous`),
    is a positive-only overload check with no rejection case.
    Legacy content on the overlay side has no negative case: neither the
    `content:` closure of `.overlay(alignment:content:)`
    (`NativeOverlayModifier.swift:56-57`) nor the `overlay:` closure of
    `OverlayModifier.init` (`:13-14`) is tested with it.
  - A native subtree under a legacy container is accepted with no check
    (`LayoutTree.swift:89-90`). By reading, it lays out as `Style.default` CSS
    nodes whose native measures never run: a native leaf is a childless
    default node, while a native container keeps its children as a default
    flex row (`LayoutTree.swift:125, 138, 159, 248`; `FlexEngine.swift:180`).
    No run confirms that.
  - `ProposalElementGroup` has no requirements, so a legacy type can declare
    conformance and reach the trap.
  - No adapter or compatibility boundary exists.
- **The kernel writes the same root-absolute `LayoutRect` store.** This holds
  (`LayoutTree.swift:495`).
- **The measurement cache is frame-local and retains no ids across frames.**
  This holds, and the cache is narrower than that: it lives for one
  `computeNativeLayout` call (`LayoutTree.swift:275-282`). *2026-09-14:* this is
  now a written, pinned contract (`SA-H`, `NativeInvalidationContractTests.swift`).
- **Every replacement container has a SwiftUI probe.** Not yet: no probe source
  is versioned in the repository. Probe results exist only as prose in the
  plan and in test doc comments.

## Execution order from this inventory

1. Specify the new `ProposedSize`, measured result (including baselines), layout
   algorithm interface, node registration API, and frame-local cache.
2. Implement that kernel beside the existing tree with a single root switch;
   prove it on a leaf and a fixed-size overlay before migrating general stacks.
3. Add typed modifier wrappers that register native nodes and preserve identity.
4. Port `Stack`, then `Row`/`Column`, then frame/padding. Migrate `ScrollView`,
   `List`, positioning and advanced layout only after those basic nodes no
   longer use the CSS engine.
5. Remove the compatibility boundary, legacy public modifiers, engine source
   and CSS-only tests after the closeout criteria are met.

*2026-09-14 (at `7cfcddc`).* Progress against the numbered steps above:

1. Partly done. `ProposedSize`, the measured result with baselines, the
   registration API and the per-call cache exist. The layout-algorithm
   interface, which this step names, does not: the kernel is a closed
   `private enum`, listed under the kernel spec's "Not shipped".
   *Done 2026-09-14 (`00a1e22`):* the interface is `ProposalLayout` (`SA-A`).
2. Done. The single root switch and the overlay proof exist.
3. Partly done, on the proposal path only (`ModifiedContent`), and not as the
   protocol-based design in the typed-modifier spec. "Preserve identity" is
   not shown: `OverlayModifier` gives its primary and overlay elements one id
   by reading (`NativeOverlayModifier.swift:28-33`), no test checks `@State`
   across chained modifiers, and the plan keeps task 3 open.
4. Not done as ordered. No legacy container was ported. Parallel proposal
   containers, frame, padding and a `ProposalScrollView` were added instead,
   along with aspectRatio and layoutPriority from step 4's "advanced layout".
5. Not started. No compatibility boundary exists to remove, every legacy
   public modifier and `FlexEngine` remain, and the 97 browser goldens are
   unchanged.

The only production caller of any of these is the opt-in demo window
`METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run MetalUIDemo`
(`Sources/MetalUIDemo/main.swift:1009`).

## Completion criteria for task 1

This inventory is complete enough to begin task 2 because every production
engine entry point and every `Style` field has a disposition, and the public
compatibility boundary is explicit. Before task 2 is marked complete, add the
new kernel specification and a compile-time migration story for external custom
elements.

*2026-09-14 (at `7cfcddc`).* The kernel specification exists
(`specs/2026-09-12-native-layout-kernel-design.md`). It no longer describes
the shipped representation; its Status line says where.

The compile-time migration story is written nowhere. As it stands in the
source:
- Custom leaves can migrate, through `requestNativeLeaf` and a marker
  conformance.
- ~~Custom containers cannot.~~ *Struck 2026-09-14 (`00a1e22`): they can,
  through `ProposalLayout`.*
- Nothing checks that a marker conformer registers native nodes.
  *2026-09-14, ruling `SA-R`:* this criterion is **amended, not met**. The
  migration story is compile-checked for every spelling an external module
  writes. A marker conformer that registers a legacy node remains a
  **run-time trap**, pinned by lane 2
  (`aProposalMarkedElementThatRegistersALegacyNodeTrapsInsideAProposalContainer`).
  The compile-time check moves to plan task 3's open proofs.

Task 2 therefore stays open.

*2026-09-14 (`feat/kernel-completion`, at `553b980`).* **The migration story
for external custom elements**
(`specs/2026-09-14-native-kernel-completion-design.md`, ruling `SA-F`):

| an outside module wants | it uses | compile-checked by |
|---|---|---|
| a leaf | `requestNativeLeaf` + `ProposalElementGroup` conformance | `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` |
| an algorithm | a `ProposalLayout` conformer, used as `MyLayout { … }` or `ProposalLayoutContainer(MyLayout()) { … }` | the same guard; `aCustomLayoutContainerRejectsLegacyContent`; `aMeasurementSubviewCannotBePlaced`; `subviewProxiesCannotBeConstructedOutsideTheKernel` |
| a container with its own paint or input | `requestGroupLayout` + `LayoutPass.requestNativeLayout` | `anExternalModuleCanBuildACustomLeafAndContainerFromPublicAPI` |
| a legacy root | unchanged; `requestNode`/`requestLeaf` are not deprecated | — |

All six guards typecheck a whole file at file scope in Swift 6 mode
(`typecheckFile`). Under `SA-R`'s amended criterion, the plan's task 2 is
closed.
