# SwiftUI layout replacement inventory

**Status:** baseline for task 1 of
`plans/2026-09-12-swiftui-alignment.md`. This is a migration inventory, not an
implementation specification. It identifies what the new layout kernel owns and
what the existing CSS-derived system must eventually lose.

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

## CSS-debt map

| Existing concept | Current owner | Replacement or disposition |
| --- | --- | --- |
| `LayoutTree` graph, generation, resolved rects | `MetalUILayout/LayoutTree.swift` | Retain as the per-frame geometry store, renamed only if it improves clarity. Add proposal/measurement cache and placement data. |
| `Style` | `MetalUILayout/Style.swift` | Retire as the universal layout bag. Split its surviving semantics among typed modifiers, decoration, a container's layout configuration, and explicit presentation/scroll nodes. |
| `Display.flex`, `Display.stack`, `Display.none` | `Style` + `FlexEngine` | Replace with node/layout-algorithm kinds. `Stack`/`Row`/`Column` choose algorithms directly; no generic CSS display switch. |
| Flex direction, wrapping, gaps, distribution and align-self | `Style`, `FlexEngine`, `FlexLines`, `Alignment` | Replace with measured `HStack`/`VStack` algorithms and later explicit flow/grid/custom-layout types. Retire flex names from the public surface. |
| Flex grow, shrink and basis | `Style`, `ResolveFlexibleLengths` | Replace with SwiftUI-style proposal, layout priority, fixed-size, and container-specific expansion/compression rules. Do not mechanically rename flex factors. |
| `aspectRatio` | `Style`, `FlexEngine` | Reintroduce only as SwiftUI-style aspect-ratio modifier semantics, including fit/fill content mode, after the new proposal contract exists. |
| CSS box sizing, padding, border and margin | `Style`, `FlexEngine` | Padding becomes an outer modifier wrapper. Border becomes a render/layout wrapper that retains resolved widths for paint. Margin has no direct SwiftUI counterpart and must be removed or quarantined behind a compatibility API. |
| Percentage and `rem` dimensions | `Dimension`, `Resolve.swift` | Re-evaluate individually. Fixed points survive; percentage sizing needs a measured SwiftUI comparison and may be unsupported rather than inherited. `rem` is not a SwiftUI layout primitive. |
| Position, inset, containing blocks | `Style`, absolute placement in `FlexEngine` | Move to a distinct overlay/presentation or explicit positioned-layout feature. It must not be an implicit CSS containing-block rule in the new kernel. |
| Overflow | `Style`; clipping is actually in `Frame` / `ScrollView` | Remove the inert layout field. Keep clipping and translation as explicit paint/prepaint behaviour owned by scrolling or clipping modifiers. |
| CSS min-content/max-content measurement | `AvailableSpace`, `MeasureFunction`, text engine | Keep only as internal leaf-measurement tools where necessary. Replace CSS's `known`/`available` contract with a proposal result capable of baseline data. |
| `computeLayout`, `FlexEngine`, `FlexBaseSize`, `FlexLines`, `Resolve*`, `ResolveFlexibleLengths` | `MetalUILayout` | Delete after every production node uses the new kernel and their browser fixtures have a SwiftUI-equivalent proof or are archived as historical migration evidence. |

## Public API classification

| Surface | Status | Migration decision |
| --- | --- | --- |
| `Box` | CSS-derived generic container | Keep as a temporary spelling only. Migrate callers toward typed wrappers and explicit layouts; do not preserve its CSS-default stretch semantics as an implicit framework default. |
| `Row` / `Column` | SwiftUI-inspired facade over flex | Replace their lowering with native horizontal/vertical stack algorithms. Rename only in a source-compatible migration decision; their default spacing must be probe-backed rather than hard-coded. |
| `Stack` | SwiftUI-inspired facade over CSS one-cell grid | Replace its lowering with a native overlay/ZStack algorithm; retain the nine-position `Alignment` surface after probe validation. |
| `.frame(width:height:)` | Additive typed wrapper | Keep and expand to SwiftUI frame constraints and alignment. It becomes the canonical sizing modifier once the composition foundation exists. |
| `width`, `height`, min/max and percentage helpers | Direct `Style` mutations | Migrate to frame semantics or deprecate. Percentage helpers do not automatically survive. |
| `.padding` | Outer wrapper for ordinary elements; distributed style on `Component` | Keep the measured component rule, but reimplement it without mutating `Style`. Complete its ordering matrix with background, frame and clipping. |
| `.margin`, flex modifier family, `justifyContent`, `alignItems`, `alignContent`, `alignSelf`, `flexWrap` | Direct CSS API | Deprecate and remove from the SwiftUI-facing API. Reintroduce only a genuinely SwiftUI-equivalent capability. |
| `borderWidth`, `cornerRadius`, background | Mixed layout/paint decorations | Separate layout footprint from paint decoration. Fix border rendering as part of the wrapper migration; corner radius remains paint-only until a clip modifier is provided. |
| `.position(.absolute)` / `.inset` / `Deferred` | CSS positioning plus a MetalUI portal | Preserve `Deferred` as a documented portal. Redesign absolute position separately around SwiftUI overlay/presentation semantics; do not port CSS containing blocks. |
| `ScrollView` | Two flex nodes plus phase-owned clipping | Replace the two-node flex lowering with a viewport/content layout pair. Keep phase-owned clipping, input routing and stable offset state. |
| `List` | Windowed flex column with a uniform height | Keep virtualization as an implementation choice, but replace its flex spacers and only-child constraint. Align data identity, scrolling and accessibility with SwiftUI before claiming `List` parity. |
| `Text` | CSS leaf measurement closure | Retain shaping and intrinsic measurement, but change its input from CSS known/available spaces to the new proposal. Carry first/last baselines in the result. |
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

## Completion criteria for task 1

This inventory is complete enough to begin task 2 because every production
engine entry point and every `Style` field has a disposition, and the public
compatibility boundary is explicit. Before task 2 is marked complete, add the
new kernel specification and a compile-time migration story for external custom
elements.
