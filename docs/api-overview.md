# MetalUI public API — an overview

A map of the public surface by area: what each area holds, how it relates to
SwiftUI, and where to read more. Every public declaration (2305 of them, in
fifteen modules) belongs to one of 117 inventory families; the mechanical map
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
  carried and mirrors nothing (25); `colorScheme`, readable while building
  ([Colour](#colour--a--d--m)). `Theme`/`ColorToken`/`.theme(_:)` are
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
`.scaledToFill`, `.background(_ color:)`, `.background(alignment:content:)` (57,
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

`Shape` (`geometry(in:)` and, since paths, shadows and transforms, SwiftUI's
`path(in:)` — both defaulted, implement either; one implementing neither
traps naming `GX-D`), `ShapeGeometry` (`.roundedRectangle`, `.ellipse`,
`.path`), `Rectangle`, `RoundedRectangle`/`RoundedCornerStyle` (90),
`Circle`, `Capsule`, `Ellipse`, `ShapeView` (`.fill`, `.stroke`,
`.strokeBorder`, each also with a `FillStyle`/`StrokeStyle`),
`.background(_:in:)`; `Image` (`.resizable`, `.interpolation` — 93),
`Image.Interpolation`, `ContentMode`; `ImageBitmap` (M, the portable image
type).

**Paths** (rulings `GX-B`…`GX-E`, `GX-K`): `Path` — SwiftUI's initialisers and
mutators (`move`, `addLine`, `addLines`, `addQuadCurve`, `addCurve`, both
`addArc`s, `addRect`, `addRects`, `addRoundedRect`, `addEllipse`, `addPath`,
`closeSubpath`, `contains(_:eoFill:)`, `offsetBy`, `boundingRect`) over
`Point`/`Bounds`; a `Shape` and a view drawing its own coordinates from its
layout origin; rasterized on the CPU in device pixels after every effect (crisp
under `scaleEffect`), drawn as an image, cached by value. `FillStyle`
(nonzero, even-odd, antialiased), `StrokeStyle` (width, `LineCap`,
`LineJoin`, miter limit, dashes). A plain-width stroke of a built-in keeps the
renderer's exact band. `clipShape` of a path traps (91); a stroke width snaps
(97). Not offered: `applying`/`transform:`, `addRelativeArc`,
`trimmedPath`/`trim`, `strokedPath`.

**Shadows** (`GX-J`, `GX-Q`): `.shadow(color:radius:x:y:)` on both
vocabularies (a `LayoutModifier` case; on a `StyledElement` it returns `Self`),
default colour `ColorToken.shadow` (black at 0.33 in both themes; `Theme`'s
initialiser takes it as a trailing defaulted `shadow:`). Per leaf — a text draw
is one leaf, a `Box`'s background and border one, a surface its quad (104); a
triple box blur of sigma = radius (105); render only: no layout, hit region or
accessibility change. Colour, radius and offset animate. Not offered:
`compositingGroup`, `drawingGroup`, inner shadows.

## Colour — A / D / M

**Values (A; 1, 116–118).** `Color` is SwiftUI's value and still a view that
fills its proposal: `Color(red:green:blue:opacity:)`, `Color(.sRGB | .sRGBLinear,
red:…)`, `Color(white:opacity:)`, `Color(hue:saturation:brightness:opacity:)`
— gamma sRGB, stored as written and clamped at resolution (`CR-C`, 118);
`opacity(_:)` multiplies (on a `Color` view it is this value method, `CR-G`);
equality compares components. Statics: the thirteen hues and `gray` are the
macOS 27 light/dark values (117), `black`/`white`/`clear` fixed, `primary`/
`secondary`/`accentColor` through the theme (116). `Color.Resolved` and
`resolve(in:)` give clamped sRGB components. A literal is drawn like a token:
sRGB numbers on a Display P3 layer (1). No `.displayP3`, no asset catalog, no
`ShapeStyle` (`.foregroundStyle(.secondary)` is `Color.secondary`, 119).

**Theme-backed and dynamic (M).** `Color(.surface)` / `Color.surface` (the
nine tokens as statics, bit-exact), `Color(_ hsla:)`, `Color(light:dark:)`
(MetalUI-only; resolves against the element's `colorScheme`, `CR-O`), and an
app palette: a `ThemeColorKey` type with a `defaultValue`, read with
`Color(Key.self)` and overridden per theme with `theme[Key.self] = …`
(`CR-N`; SwiftUI's answer is an asset catalog). `PaintPass.resolve(_:)` turns
any `Color` into the `Hsla` a custom `paint` draws, against the element's
scoped theme and scheme (`CR-H`).

**Everywhere a token went.** `background`, `border`, `fill`, `stroke`,
`strokeBorder`, `shadow(color:)`, `foregroundColor`/`foregroundStyle`,
`Background`, `Rectangle(width:height:color:)`, `onTap(hoverColor:)` and the
legacy `hoverBackground`/`focusBackground`/`hoverBorder`/`focusBorder` take a
`Color` on both vocabularies; each `ColorToken` overload is kept, disfavoured
(`CR-E`). Colours animate as tokens do — RGB interpolation, a theme or scheme
change re-resolves and never fades (`CR-H`). No renderer change (`CR-I`).

**Colour scheme (A / M).** `ColorScheme` (`.light`, `.dark`; `Appearance` is
its typealias) and `@Environment(\.colorScheme)`, readable while building,
stamped from the window's appearance; an appearance change rebuilds
(`CR-J`). `.environment(\.colorScheme, …)` changes a subtree and selects the
window's matching theme variant (`CR-S`). `.preferredColorScheme(_:)` (A) is
window-wide with SwiftUI's reduction and sets the platform window's appearance
— AppKit's `NSWindow.appearance`; SDL's decorations stay with the system
(`CR-L`, `CR-M`). `Window.colorScheme`, `preferredColorScheme`, `lightTheme`,
`darkTheme` and `App`'s three defaults (M): the window's theme is the variant
for its scheme (`CR-K`). At the seam, `PlatformWindow.setPreferredColorScheme(_:)`,
defaultless.

## Render effects — A / D

`.rotationEffect(_:anchor:)`, `.scaleEffect(_:anchor:)` (a `Double` or a
`SizeD`), `.scaleEffect(x:y:anchor:)`, `.offset(x:y:)`, `.offset(_:)` and
`Angle` (paths, shadows and transforms, rulings `GX-G`…`GX-I`, `GX-P`): render
only — the layout is unchanged, hit testing follows the drawn shape and the
accessibility frame is the transformed frame's bounding box (107 at angles off
a right angle). On the proposal vocabulary each is one `LayoutModifier` layer
(`.rotationEffect`, `.scaleEffect`, `.offset` cases); on a `StyledElement`
each returns `Self` and wraps the whole element whatever the written order
(108). A clip between two nested rotations is its screen bounding box (109); a
handler written outside a padding over an effect hits its own axis-aligned
frame (41). Angle, factors, anchor and offset animate. Text and images under
a scale or rotation are resampled, not re-rasterized (106); paths and shadows
are re-rasterized. Not offered: `transformEffect`, `projectionEffect`,
`rotation3DEffect`.

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

## GPU surfaces — M / D

App-owned GPU rendering composited into the UI (spec §7.7, rulings `MV-A`…
`MV-Q`). `GPUSurface(redraw:draw:)` and `GPUSurface(redraw:value:draw:)` — a
portable proposal leaf sized like `Canvas` (the proposal, 10 on a nil axis;
probe G1) whose closure encodes into an offscreen render target of the
element's laid-out bounds × the window's scale (`bgra8Unorm`, never sRGB;
D1). MetalUI composites the target exactly as an `Image` — the active clip and
its corner radii, opacity, layer, transitions, drag preview (C1–C3) — and the
element takes input and accessibility from the ordinary modifiers, with no
hitbox of its own (`MV-I`). `RedrawPolicy`: `.onDemand` draws on a new target
(first sight, resize, rescale) or a changed `value:` — not whenever the tree
rebuilds, unlike a `Canvas` (103); `.continuous` draws every painted frame and
keeps the display link awake. A hidden, zero-size, fully clipped or
transparent surface does no GPU work and its target is released. The closure
gets `any GPUSurfaceContext` (`pixelSize`, `scaleFactor`, `time`,
`frameIndex`, `isNewTarget`, the portable `clear(red:green:blue:alpha:)`) and
downcasts to its backend's context: **`MetalDrawContext`** on the Metal
renderer (`device`, the frame's own `commandBuffer`, `target`,
`renderPassDescriptor(loadAction:clearColor:)`; `MetalView` is the Apple
spelling whose closure takes it directly) and **`SDLGPUDrawContext`** on the
SDL renderer (`device`, `commandBuffer`, `target` as SDL3 pointers;
`Backends/SDL`'s `MetalUISDL`). The draw runs on the main actor inside the
renderer's `finishFrame`, before MetalUI's own pass, into the frame's own
command buffer; it must not commit, submit, present or wait on it — Metal
traps if it does, SDL cannot tell (`MV-F` item 5). At the seam:
`PrimitiveKind.surface`, `SurfaceID`, `SurfaceTarget`, `SurfaceDrawRequest`,
`SurfaceTargetTable` (the one per-window target lifecycle both renderers use)
and the defaultless `WindowRenderer.finishFrame(scene:atlas:surfaces:)`
(migration note in [`migration.md`](migration.md)). Not offered: a depth
attachment, EDR targets, `NSViewRepresentable` (see
[`divergences.md`](divergences.md#not-offered)).

## Application icon — M

`App.icon: [ImageBitmap]` (M; `AI-A`): the application's icon, settable
before or after windows open and at runtime; `[]` (the default) leaves the
platform's own icon alone. Several sizes of one picture are welcome — the list
reaches the platform smallest first with repeated `width × height` dropped
(`AI-C`). AppKit sets `NSApplication.applicationIconImage`; SDL sets every open
and later window's icon (`AI-E`, `AI-F`); on SDL `[]` cannot restore the
default. SwiftUI has no runtime icon API — a SwiftUI app's icon is its
bundle's — so this is MetalUI-only by design and has no divergence row. At the
seam, `Platform.setApplicationIcon(_:)` over `ImageTexture`s, defaultless
(`AI-B`). Shipping an icon with the application itself is build-side:
[`packaging.md`](packaging.md).

## Menus, popovers and tooltips — A / D / M

**Context menus (A; 110, 114).** `.contextMenu { }` on both vocabularies, over a
closed `MenuContent` builder: `Button` (with `.keyboardShortcut` shown, `.disabled`
greyed), `Toggle` (a checked item), `Menu("Sub") { }` (a submenu), `Divider()`,
and `if`/`for`; evaluated at each open (`MN-D`). Opened by a right press (a
control-click on AppKit), the menu key or Shift-F10 off Apple, or VoiceOver's
show-menu. A native `NSMenu` on AppKit, MetalUI's drawn menu (keyboard, hover,
submenus, outside click) where the platform declines — SDL — through the
defaultless `PlatformWindow.presentMenu(_:at:)`; the choice returns as
`InputEvent.menuAction`. A secondary press never presses a `Button` (D 110).
`Picker`, `Section` and image items are not offered.

**Pull-down (A).** `Menu("Title") { }` as a view: a button that opens its items
below itself, published as a menu button.

**Menu bar (A / M).** `App.commands { CommandMenu("Name") { }; CommandGroup(after:/before:/replacing:) { } }`
with `CommandGroupPlacement` (`.appInfo`, `.newItem`, `.undoRedo`, `.pasteboard`, …).
Every AppKit app installs the standard main menu (About, Hide, Quit, File ▸ Close,
Edit, Window); Edit reaches a focused `TextField`/`TextEditor` as its keys.
`Platform.setMenuBar(_:)` and `PlatformMenuBar` are the seam (M). SDL draws no bar;
command shortcuts fire through the same window shortcut pipeline as a `Button`'s.

**Popovers (A / D 111, 112, 115).** `.popover(isPresented:arrowEdge:content:)` and
`.popover(item:arrowEdge:content:)`: anchored to the declaring element, placed on
`arrowEdge`'s side (default `.top`), flipped then clamped inside the window, no
arrow; an outside press or Escape writes the binding false from input, and the
outside press then reaches what it lands on. Published as a non-modal popover.

**Tooltips (A / D 113).** `.help("text")` publishes `accessibilityHint`'s tree on
both bridges and shows a drawn tooltip after 1.0 s of display-link time, hidden by
a press, wheel, key or leaving.

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
`MetalUIScene` (`Scene` — with its per-instance `MUITransform` table,
`Scene.transforms`/`insert(_:…transform:)`, `GX-F` — the glyph atlas,
`FontKey`, `ImageTexture`),
`MetalUIRender` (the Metal renderer), `MetalUIAppKit` (the AppKit platform),
`MetalUIPrimitives`, `MetalUITextSystem`, `MetalUIText`, `MetalUIFreeType`,
`MetalUIHarfBuzz`, `MetalUIPortableText`, `MetalUISystemFonts`,
`MetalUIPath` (paths, strokes, exact-area coverage, blur — `package` API,
no product, imports nothing, `GX-B`), and
`MetalUIDemoContent` (the demo trees, importable by tests).
