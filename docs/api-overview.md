# MetalUI public API — an overview

A map of the public surface by area: what each area holds, how it relates to
SwiftUI, and where to read more. Every public declaration (1940 of them, in
fifteen modules) belongs to one of 99 inventory families; the mechanical map
is `probes/closeout-inventory-map.tsv`, checked by
`probes/closeout-inventory-check.sh` (it prints nothing when every
declaration is classified), and the human-readable table with each family's
evidence is [`record/66-closeout.md`](record/66-closeout.md) §1.

**Classes.** **A** — SwiftUI-aligned: the behaviour matches a measured
SwiftUI answer (a probe arm in `probes/`) and a test pins it; numbered
exceptions are in [`divergences.md`](divergences.md). **M** — MetalUI-only by
design: no SwiftUI counterpart. **X** — deprecated, with its replacement.
**D** — a documented divergence. What SwiftUI has and MetalUI does not is in
[`divergences.md`](divergences.md#not-offered).

Platforms: macOS (AppKit + Metal, the default), Linux and Windows (the
separate `Backends/SDL` package). iOS and the other Apple platforms are out of
scope (`PB-A`).

## App and window — M

`App` (`App(device:textSystem:)` on macOS, `App(platform:textSystem:)` for any `Platform` — the SDL one on Linux and Windows; `openWindow`, `run`), `Window` (theme,
environment, focus, keymap, input), `Frame`, `renderFrame(_:size:scaleFactor:textSystem:atlas:)`
for a headless frame. A window redraws on a display link, only when dirty.
SwiftUI's `App`/`Scene` lifecycle is not offered.

## Elements — M

MetalUI's equivalent of `View` is three protocols with gpui's phases:
`Element` (`requestLayout` → `prepaint` → `paint`), `ElementGroup` (zero or
more elements: what a builder closure produces), `StyledElement` (an element
with a `Style`, a `Decoration`, an id and `Handlers` — the legacy modifiers
hang off it), and for the SwiftUI vocabulary `ProposalElement`/
`ProposalElementGroup`. The phase objects are `LayoutPass`, `PrepaintPass`,
`PaintPass` (hover, active and focus are readable only in paint). A custom
leaf registers through `LayoutPass.requestNativeLeaf`; a custom container
writes a `ProposalLayout` (below). `Component` composes elements with its own
state, layout-transparent (a `.frame` on a multi-member one is divergence 56). `Deferred` hoists its content to
the window's top layer — a portal for modals, popovers and tooltips
(divergences 9, 10).

## Builders, identity, state, binding, environment — A

- **`ElementBuilder`** — `@ViewBuilder`'s shapes: blocks, `if`, `if`/`else`,
  `switch`, `for`; each `if`/`for` is one structural slot and content an
  evaluated conditional removes resets on return (`ID-B`, `ID-C`).
  `AnyElement` is `AnyView`.
- **Identity** — structural by position; `.id(_:)` on any element group
  overrides it (`ID-G`); a departed name starts fresh (`ID-R`). Two siblings
  with one id share an identity (72).
- **`@State`**, **`Binding`** (SwiftUI's surface, `@MainActor` — 78),
  **`ForEach`** (keyed identity, 79), **`@Environment`**/`EnvironmentValues`/
  `.environment`/`.transformEnvironment`/`.disabled`; `displayScale`,
  `pixelLength`, `controlActiveState`, `controlSize` (76), `dynamicTypeSize`
  (inert as on macOS), `accessibilityReduceMotion`; `layoutDirection` is
  carried and mirrors nothing (25). `Theme`/`ColorToken`/`.theme(_:)` are
  MetalUI's scoped, paint-only colour tokens (M).

## Layout, SwiftUI vocabulary — A

`HStack`, `VStack`, `ZStack`, `Spacer`, `VerticalAlignment` (with text
baselines), `HorizontalAlignment`, `.layoutPriority` — SwiftUI's stack
algorithms (51, 58, 70, 89). `Grid`, `GridRow`, `.gridCellColumns`,
`.gridCellAnchor`, `.gridColumnAlignment`, `.gridCellUnsizedAxes` (61–68, 88).
`ProposalScrollView`, `ScrollViewReader`/`ScrollViewProxy.scrollTo(_:anchor:)`,
`UnitPoint`, `.scrollIndicators`. `ProposalLayout` +
`ProposalLayoutContainer` — SwiftUI's `Layout` without a cache (`SA-A`), over
`MeasurementSubviews`/`PlacementSubviews` and `ProposedSize`.

Modifiers on proposal content (each one layer of one flat
`ModifiedContent<Content, LayoutModifier>`): `.frame` (fixed and flexible;
38), `.padding(Edges<Pixels>)`, `.fixedSize`, `.aspectRatio`/`.scaledToFit`/
`.scaledToFill`, `.background(token)`, `.background(alignment:content:)` (57,
73), `.overlay(alignment:content:)` (73), `.border`, `.opacity` (46),
`.clipShape`/`.clipped`/`.cornerRadius`/`.clip` (91, 92), `.allowsHitTesting`
(41, 44), `.contentShape`, `.onTap`, the gestures, the accessibility
modifiers, `.font` and the text modifiers, `.transition`, `.animation(_:value:)`,
`.transaction`, `.id`.

The `Native…` names and `.native…` modifiers are deprecated aliases (X) —
except `nativeFrame`, kept undeprecated (`SA-K`).

## Layout, legacy vocabulary — M

`Box`, `Row`, `Column`, `Stack`, `ScrollView` (54), `List` (13, 32, 84),
`Text`, `Style` (opaque outside the package), `Decoration`/`BorderStyle`, and
the `StyledElement` modifiers: `.padding` and `.frame` (A — SwiftUI's
answers), `.background`/`.hoverBackground`/`.cornerRadius`/`.border`/
`.hoverBorder` (47, 49), `.focusBackground`/`.focusBorder`, the CSS item and
container fields (`.margin`, `.gap`, `.justifyContent`, `.alignItems`,
`.flexGrow`, `.flexShrink`, `.flexBasis`, `.alignSelf`, `.position`,
`.inset`, `.flexDirection` — lowered onto the kernel, unlowerable cases
refused by name), `.hidden` (A), `.opacity` (A), `.clipped`/`.clipShape` (A),
`.allowsHitTesting`/`.contentShape` (A), `.onClick` (27), `.onKey`/
`.focusable`/`.onAction`/`.keyContext` (21, 22, 26, 94). Every legacy element
lowers onto the same kernel as the SwiftUI vocabulary. `Row`/`Column` default
to gap 0 (52). The eight sizing modifiers and the `fraction:`/`percent:`
spellings are deprecated toward `.frame` (X). Moving to the SwiftUI
vocabulary: [`migration.md`](migration.md).

## Controls — A

`Button` (`ButtonRole`, `ButtonStyle`, `.buttonStyle`, `.keyboardShortcut`;
76, 80), `Toggle`, `Slider`, `Stepper` (80, 82), `Picker`/`PickerStyle`/`.tag`
(81, 82), `List(_:selection:rowHeight:row:)` (M), `TextField` and
`TextEditor` (the `Binding<String>` initialisers A; the controlled
initialisers, submit, undo and paging M).

## Text — A

`Text`/`ProposalText`, `Font` (system sizes, weights, designs, the eleven
text styles, custom families), `Font.Weight`, `Font.Design`, `Font.TextStyle`,
`TextAlignment`, `Text.TruncationMode`, `.font`, `.fontWeight`, `.italic`,
`.foregroundStyle`, `.foregroundColor`, `.lineLimit`, `.truncationMode`,
`.multilineTextAlignment` (60, 86, 87). Text is measured and drawn through
one `TextSystem` chosen per app: CoreText on Apple (`MetalUIText`), the
portable FreeType/HarfBuzz pipeline elsewhere (`MetalUIPortableText`,
`MetalUISystemFonts`) — M.

## Shapes and images — A

`Shape` (`geometry(in:)`), `Rectangle`, `RoundedRectangle`/`RoundedCornerStyle`
(90), `Circle`, `Capsule`, `Ellipse`, `ShapeView` (`.fill`, `.stroke`,
`.strokeBorder`), `.background(_:in:)`; `Image` (`.resizable`,
`.interpolation` — 93), `Image.Interpolation`, `ContentMode`; `ImageBitmap`
(M, the portable image type).

## Input, gestures, focus — A / M

`Gesture`, `TapGesture`, `LongPressGesture`, `DragGesture`,
`.exclusively(before:)`, `.simultaneously(with:)`, `.gesture`,
`.simultaneousGesture`, `.highPriorityGesture`, `.onTapGesture`,
`.onLongPressGesture` (A); `KeyEquivalent`, `KeyboardShortcut` (A);
`@FocusState`/`.focused` (A, 94). The keymap — `Keymap`, `KeyBinding`,
`Keystroke`, `KeyContext`, `ContextPredicate`, `Action` — is gpui's (M).

## Drag and drop — A / D

`Transferable` and `ContentType` — MetalUI's own synchronous, `Data`-based
protocol with SwiftUI's call-site spellings; `String`, `URL` and `Data`
conform (A; the conformer spelling `transferRepresentation` is not offered,
`DN-B`, `DN-S`). `.draggable(_:)`, `.draggable(_:preview:)` and
`.dropDestination(for:action:isTargeted:)` on both vocabularies (A): a drag
begins on the first pointer move from a press, outranks a tap, long press or
click and yields to a `DragGesture` that outranks it; the destination is the
topmost one by the one hit ranking; the preview is the source's own
primitives replayed above everything at 70% opacity; Escape cancels (`DN-D`…
`DN-J`). A disabled source or destination does nothing (100); a drag leaving
the window becomes an `NSDraggingSession` on AppKit and stops at the edge on
SDL (101); external drops arrive from Finder and other apps through
`NSDraggingDestination` on AppKit and SDL's drop events, where the types are
unknown until the drop (102). At the seam: `InputEvent.drop` (`DropEvent`,
`DropItem`, `PasteboardType`) and `PlatformWindow.beginExternalDrag`
(`DragRepresentation`), defaultless (`DN-C`). Accessibility publishes
nothing for either, as SwiftUI's does not (`DN-N`). `.onDrag`/`.onDrop` and
the `DropSession` family are not offered (`DN-A`).

## Accessibility — A / M

On both vocabularies: `.accessibilityLabel`, `.accessibilityValue`,
`.accessibilityHint`, `.accessibilityIdentifier`, `.accessibilityHidden`,
`.accessibilityElement(children:)`, `.accessibilityAddTraits`/
`.accessibilityRemoveTraits` (`AccessibilityTraits`),
`.accessibilityAction(_:)`, `.accessibilityAction(named:_:)`,
`.accessibilityAdjustableAction` (A; 29–31, 33, 34, 82, 95). `AXNode`/`AXRole`/
`AXTrait` are the neutral record a `StyledElement` declares (M); `AXNode.actions`
and `AXActionKind` are deprecated (X). Bridged to NSAccessibility on macOS and
AccessKit through `Backends/SDL`.

## Animation and transitions — A

`Animation` (`linear`, `easeIn`, `easeOut`, `easeInOut`, `timingCurve`,
`spring`), `withAnimation`, `Transaction`, `withTransaction`,
`.transaction(_:)`, `.animation(_:value:)`, `Binding.animation(_:)`,
`AnyTransition` (`identity`, `opacity`, `move(edge:)`, `slide`, `offset`,
`scale`, `push(from:)`, `asymmetric`, `combined`), `Edge`, `.transition(_:)`
(96–99).

## Backends and infrastructure — M

`MetalUICore` (geometry, units — `Pixels`, `Length`, `Dimension` — colours,
`Appearance`, `ControlActiveState` (A), `LayoutDirection` (25)),
`MetalUILayout` (the layout kernel: `LayoutTree`, `ProposalLayout`,
`ProposedSize`, rounding — 77), `MetalUIPlatform` (`Platform`,
`PlatformWindow`, `WindowRenderer`, input events, the accessibility tree),
`MetalUIScene` (`Scene`, the glyph atlas, `FontKey`, `ImageTexture`),
`MetalUIRender` (the Metal renderer), `MetalUIAppKit` (the AppKit platform),
`MetalUIPrimitives`, `MetalUITextSystem`, `MetalUIText`, `MetalUIFreeType`,
`MetalUIHarfBuzz`, `MetalUIPortableText`, `MetalUISystemFonts`, and
`MetalUIDemoContent` (the demo trees, importable by tests).
