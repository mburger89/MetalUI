# MetalUI public API — an overview

A map of the public surface by area: what each area holds, how it relates to
SwiftUI, and where to read more. Every public declaration (2977 of them, in
fifteen modules) belongs to one of 156 inventory families; the mechanical map
is `probes/closeout-inventory-map.tsv`, checked by
`probes/closeout-inventory-check.sh` (it prints nothing when every
declaration is classified), and the human-readable table with each family's
evidence is [`record/66-closeout.md`](record/66-closeout.md) §1.

For task-led walk-throughs (layout, state and identity, input, presentations,
drawing, cross-platform) see [`guides/README.md`](guides/README.md); this page
is the reference they link to.

**Classes.** **A** — SwiftUI-aligned: the behaviour matches a measured
SwiftUI answer (a probe arm in `probes/`) and a test pins it; numbered
exceptions are in [`divergences.md`](divergences.md). **M** — MetalUI-only by
design: no SwiftUI counterpart. **X** — deprecated, with its replacement.
**D** — a documented divergence. What SwiftUI has and MetalUI does not is in
[`divergences.md`](divergences.md#not-offered).

Platforms: macOS (AppKit + Metal, the default), Linux and Windows (the
`MetalUISDL` product of the root package, behind its `SDL` and `AccessKit`
package traits, `PX-H`; [`getting-started.md`](getting-started.md) says what
to install). `SDLPlatform(options:)` takes `SDLPlatform.Options`; `.headless` opens hidden
windows that render offscreen, for a CI smoke test with no display
([`testing.md`](testing.md#a-ci-smoke-test-of-the-real-window), `IC-J`). iOS and the other Apple platforms are out of
scope (`PB-A`).

## App and window — M

`App` (`App(device:textSystem:)` on macOS, `App(platform:textSystem:)` for any `Platform` — the SDL one on Linux and Windows; `openWindow`, `run`), `Window` (theme,
environment, focus, keymap, input), `Frame`, `renderFrame(_:size:scaleFactor:textSystem:atlas:)`
for a headless frame. A window redraws on a display link, only when dirty.
SwiftUI's `App`/`Scene` lifecycle is not offered.

**Window sizing** (`SV-L`, `SV-M`; SwiftUI's `.defaultSize` and
`.windowResizability` scene modifiers become window state, `App` not being a
`Scene`): `App.openWindow(title:size:minSize:maxSize:windowResizability:startsDisplayLink:content:)`
— `size` is the default size — and `Window.minSize`, `Window.maxSize`,
`Window.windowResizability` (M), settable at any time; `WindowResizability`
(A) `.automatic`, `.contentMinSize` (the root's answer at a zero proposal is
the minimum, following the content), `.contentSize` (adds its answer at an
infinite proposal as the maximum). `.automatic` asks the content nothing
(divergence 126). The platform receives the effective limits through
`PlatformWindow.setContentSizeLimits(minimum:maximum:)` only when they change.
`Window.drawnChromeHeight` (M, read-only, `SG-F`) is the height MetalUI draws above
the root — the menu bar's 25 plus the toolbar strip's 39 — and 0 where the platform
shows its own; an explicit `minSize`/`maxSize` is the content's size **below** it
(AppKit's `contentMinSize` excludes its toolbar too), so the platform receives the
height plus the chrome.

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
- **`ProposalContentBuilder`** — the builder of every SwiftUI-vocabulary
  container's content (`HStack`, `VStack`, `ZStack`, `Grid`, `GridRow`,
  `ProposalScrollView`, `ProposalLayoutContainer`, a `ProposalLayout`'s
  `callAsFunction`): `ElementBuilder` plus one rule — proposal content keeps
  its type, and any other element, group or `Component` is adopted as
  **`LegacyContent`** (M; made by the builder, never written), identity- and
  layout-transparent, so `HStack { Text("Name"); TextField("Name", text: $name) }`
  composes as SwiftUI's does (`PE-B`, `PE-C`). A legacy item field there
  (`.flexGrow`, `.margin`, …) is reported by name.
- **A `for` loop over a helper returning `some …`** (`for t in texts {
  label(t) }` with `func label(_:) -> some ProposalElementGroup`) does not
  compile in either builder: "underlying type for opaque result type … could
  not be inferred" — a Swift 6.4 result-builder defect no `buildArray` can
  reach (`KF-M`; probe `probes/swift-builder-for-opaque.sh`; guard
  `aForLoopOverAnOpaqueHelperIsAToolchainLimitation`, which turns red when a
  toolchain fixes it). Write `ForEach(texts, id: \.self) { label($0) }`
  (SwiftUI's spelling — its `ViewBuilder` has no `for` at all), a helper
  returning a concrete type (`-> ProposalText`, or a `Component`), or the
  chain inline.
- **Identity** — structural by position; `.id(_:)` on any element group
  overrides it (`ID-G`); a departed name starts fresh (`ID-R`). Two siblings
  with one id share an identity (72).
- **`@State`**, **`Binding`** (SwiftUI's surface, `@MainActor` — 78),
  **`ForEach`** (identity by the id's Hashable value, as SwiftUI; the `List` residue is 255), **`@Environment`**/`EnvironmentValues`/
  `.environment`/`.transformEnvironment`/`.disabled`; `displayScale`,
  `pixelLength`, `controlActiveState`, `controlSize` (76), `dynamicTypeSize`
  (inert as on macOS), `accessibilityReduceMotion`, `accessibilityReduceTransparency` (SwiftUI's
  key, read-only outside; stamped from the platform; while true every `Material` draws an opaque
  grey with no blur, divergence 315; C27, `MT-D`, `MT-F`); `layoutDirection` is
  carried and mirrors nothing (25); `colorScheme`, readable while building
  ([Colour](#colour--a--d--m)). `Theme`/`ColorToken`/`.theme(_:)` are
  MetalUI's scoped, paint-only colour tokens (M). An `@Observable` object is
  provided with `.environment(model)` and read with `@Environment(Model.self)`
  (or `… var model: Model?`), keyed by its static type; a missing one traps
  (134, `MD-H`). `@Bindable` and `ObservableObject` are not offered.
- **`Component.equatable()`** (`where Self: Equatable`, returns `EquatableComponent<Self>`; A, item C14,
  record §104, `IV-B`) — SwiftUI's `View.equatable()`: the component's `content` getter is not run again
  while its value is `==` to the last evaluation's, its own `@State` is unwritten and the `@Observable`
  properties the last getter read are unchanged. No identity level, cursor index or initialiser is added;
  build recursion and layout run as for the bare component; the getter is skipped and, while the occurrence's
  layout, surrounding paint context and pointer/press/focus state are unchanged, its **prepaint and paint are
  replayed** from a record of their hitboxes, focus registrations, accessibility records and scene primitives
  (record §109, `SB-B`; `FrameWork.contentEvaluations`/`contentSkips`/`contentRefusals`, `elementRequests`/
  `elementPrepaints`/`elementPaints`, `retainedHits`/`retainedMisses`/`retainedIneligible`/
  `retainedSkippedPrepaints`/`retainedSkippedPaints`/`retainedLedgerSnapshots`/`retainedReplayedOps`, M). Their prepaint is replayed too, with a counted redo when a paint-time ambient differs, and an unchanged occurrence skips its build recursion (the graft; record §110, `RK-`; `FrameWork.retainedPrepaintHits`/`retainedPrepaintIneligible`/`retainedRedos`/`retainedBackoffFrames`/`retainedTranslated`/`retainedTranslationRefused`/`retainedGrafts`/`retainedGraftIneligible`/`retainedSkippedRequests`/`retainedGraftedNodes`, M). A component that declares
  `@FocusState`, or reads an `@Environment` value that cannot be compared (a closure, a struct holding one, `\.self`, `\.textMeasurer`), is evaluated every frame (divergence 346, `IV-D`, `EE-B`, `EE-E`); a component reading an `Equatable` value, a class or an `@Observable` object through `@Environment` is skipped while what it read is unchanged (C14-c, record §120, `EE-A`; no new declaration). The layout memo behind
  it is automatic and has no API (`IV-E`). `METALUI_INVALIDATION_DEMO=1` shows the getter memo and `METALUI_RETAINED_DEMO=1` the replay; human checks: groups IV and SB, unrun. An unfocused `TextField`/`TextEditor`, a `ScrollView`/`List` whose state is unchanged and a closed `Picker`/`Menu`/`.popover` declarer no longer make an occurrence ineligible: a framework read of state is a counted read set, not a write (record §121, `RW-`; one `MetalUITesting` field, `FrameWork.retainedIneligibleReasons`, M; human checks group RW, unrun).

## Layout, SwiftUI vocabulary — A

`HStack`, `VStack`, `ZStack`, `Spacer`, `VerticalAlignment` (with text
baselines), `HorizontalAlignment`, `.layoutPriority` — SwiftUI's stack
algorithms (51, 58, 70, 89). The containers take legacy content too — the
controls, `Text`, `Box`, a `Component` — through `ProposalContentBuilder`
(`PE-B`); `ProposalFrame`, `Padding`, `Background`, `FixedSize` and
`nativeOverlay` (MetalUI-only wrappers) still take proposal content only. `Grid`, `GridRow`, `.gridCellColumns`,
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
`.transaction`, `.id`. On legacy content, `.layoutPriority`, `.fixedSize`,
`.gridCellColumns`, `.gridCellAnchor`, `.gridColumnAlignment` and
`.gridCellUnsizedAxes` are spelled on `ElementGroup` and wrap it in
`LegacyContent` first (`PE-F` item 1); `.frame` and `.padding` are the legacy
layers, which lower onto the same kernel. `Pixels.infinity` is SwiftUI's
`.infinity`, so `.frame(maxWidth: .infinity)` compiles (`PE-F` item 2).

The `Native…` names and `.native…` modifiers are deprecated aliases (X) —
except `nativeFrame`, kept undeprecated (`SA-K`).

## Layout, legacy vocabulary — M

`Box`, `Row`, `Column`, `Stack`, `ScrollView` (54), `List` (13, 32, 84;
uniform `rowHeight:` rows, or content-sized rows through `List(_:rowContent:)`
and `estimatedRowHeight:`, 145–147),
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
(81, 82), `List(_:selection:rowHeight:row:)` and the content-sized
`List(_:selection:estimatedRowHeight:rowContent:)` (M; `VL-A`), `TextField` and
`TextEditor` (the `Binding<String>` initialisers A; the controlled
initialisers, submit, undo and paging M). Each composes in both vocabularies
— a `Row`/`Column` and, since `PE-B`, an `HStack`/`VStack`/`Grid` — with
SwiftUI's sizing classes: `TextField` and `Slider` greedy wide, `TextEditor`
greedy on both axes (`PE-D`), the rest hugging; the metrics and the
below-ideal answers are MetalUI's (130, 131), and `List` keeps its
`rowHeight × count` height (84) — a content-sized list answers its measured
rows plus estimates for the rest (147), each row exactly its content's height (145). Style modifiers (`.buttonStyle`,
`.pickerStyle`, `.keyboardShortcut`) return the control: write them on it,
before any wrapper (`PE-R`). `TextField` draws SwiftUI's bordered field by
default and takes `.textFieldStyle(_:)` (`TextFieldStyle`: `.automatic`,
`.roundedBorder`, `.squareBorder`, `.plain`), `TextEditor` an opaque background
and `.textEditorStyle(_:)` — each on the control or on a container, the
innermost winning (`MD-B`, `MD-F`; 132, 133).

## Text — A

`Text`/`ProposalText`, `Font` (system sizes, weights, designs, the eleven
text styles, custom families), `Font.Weight`, `Font.Design`, `Font.TextStyle`,
`TextAlignment`, `Text.TruncationMode`, `.font`, `.fontWeight`, `.italic`,
`.foregroundStyle`, `.foregroundColor`, `.lineLimit`, `.truncationMode`,
`.multilineTextAlignment` (60, 86, 87). Text is measured and drawn through
one `TextSystem` chosen per app: CoreText on Apple (`MetalUIText`), the
portable FreeType/HarfBuzz pipeline elsewhere (`MetalUIPortableText`,
`MetalUISystemFonts`) — M. `SystemFonts.designFamilies` (M, `SG-C`) names the
platform's monospaced and serif families per `FontDesign`, and `SystemFonts.resolver()`
registers the first installed one of each lazily (a name; no face is read until a
request resolves); `.rounded` off Apple resolves to the default face.

**Rich text** (rulings `RT-A`…, record §83): styled runs inside one `Text`
on both text systems. A string literal parses SwiftUI's inline Markdown
(`LocalizedStringKey`; bold, italic, strikethrough, code, links, bare URLs and
e-mail addresses) with MetalUI's own parser on every platform; a `String`
value and `Text(verbatim:)` never parse (154: control titles are verbatim).
Interpolation inserts values verbatim in the format's style (151, 156) and
keeps an interpolated `Text`'s or `AttributedString`'s runs; `Text + Text` is
deprecated as in SwiftUI (155: a decorated operand traps). `Text` modifiers:
`bold()`, `underline`/`strikethrough(_:pattern:color:)` with `Text.LineStyle`
(`.solid` only), `kerning`, `tracking`, `baselineOffset`, `monospaced`, and
`Font.monospaced()` (157, 158). `Text(AttributedString)` reads
`AttributeScopes.MetalUIAttributes` (SwiftUI's key names over MetalUI's types,
per-key dynamic-member subscripts) and Foundation's `link`; on Apple platforms
also `inlinePresentationIntent`. Links are styled in the accent and inert
(150); underlines and strikethroughs are the face's unsnapped bands (152);
only 34 named entities decode (153) — A / D. The seam is `StyledText` and three
defaultless `TextSystem` requirements (`MetalUITextSystem`) — M.

**Measuring text.** `@Environment(\.textMeasurer)` is a get-only `TextMeasurer`
(no public initialiser): `resolve(_:)` takes a `Text` or a `ProposalText` in the
environment of the element reading it, and `ResolvedText.measure(in:)` answers
the size layout gives that text under a proposal — a finite width wraps it, a
finite height caps its lines, an infinite axis is unbounded — through
`resolveTextStyle` and the frame's text system, with no layout, no node and no
state. The answer is the unrounded leaf answer (a laid-out frame is that rounded
to whole points), and an empty `Text` is one line tall (295). SwiftUI spells it
`GraphicsContext.resolve(_:)` + `ResolvedText.measure(in:)` in a `Canvas`; the
environment is the carrier here because MetalUI has no `Canvas` context (296) —
M / D. Use it to place a label or a chip over a `GPUSurface` before the labels
exist as elements (rulings `GT-B`…`GT-D`, `GT-I`).

## Shapes and images — A

`Shape` (`geometry(in:)` and, since paths, shadows and transforms, SwiftUI's
`path(in:)` — both defaulted, implement either; one implementing neither
traps naming `GX-D`), `ShapeGeometry` (`.roundedRectangle`, `.ellipse`,
`.path`), `Rectangle`, `RoundedRectangle`/`RoundedCornerStyle` (90),
`Circle`, `Capsule`, `Ellipse`, `ShapeView` (`.fill`, `.stroke`,
`.strokeBorder`, each also with a `FillStyle`/`StrokeStyle`),
`.background(_:in:)`; `Image` (`.resizable`, `.interpolation` — 93),
`Image.Interpolation`, `ContentMode`; `ImageBitmap` (M, the portable image
type). **Decoding** (`PX-B`…`PX-E`): `ImageBitmap(contentsOfFile:)`,
`ImageBitmap(data:)` and `ImageBitmap(resource:withExtension:subdirectory:bundle:)`
(M) decode PNG and JPEG with MetalUI's own decoder (stb_image, vendored as
`CStbImage`) on every platform — the same premultiplied sRGB bytes on macOS,
Linux and Windows, colour profiles ignored (138); other formats go through
ImageIO on macOS and are `nil` elsewhere; a corrupt or truncated file is
`nil`, never a trap. The `resource:` form decodes each resolved path once per
process, so every frame gets the same texture identity. SwiftUI's
`Image(_:bundle:)` (asset catalogs) is not offered.

**Pixel decoding and orientation** (`IB-A`…`IB-L`, record 113): `DecodedImage` (M) decodes PNG and JPEG
bytes with the same decoder to straight-alpha RGBA8 or 8-bit grey (`init?(data:format:)`,
`init?(contentsOfFile:format:)`; `width`, `height`, `bytesPerRow`, `pixels`), reports the file's EXIF
orientation (JPEG `APP1`, PNG `eXIf`; bounds-checked, damaged is `.up`) and does not apply it;
`applyingOrientation()`, `orientedSize` and `ImageBitmap(_:)` complete the path. `Image.Orientation`
(A) has SwiftUI's eight cases and raw values (plus MetalUI-only `init?(exifValue:)`, `exifValue`,
`swapsAxes`); `Image(decorative:scale:orientation:)` and `Image(_:scale:orientation:label:)` (A, no
default for `orientation`, `IB-K`) draw a bitmap turned by it through `ImageBitmap.oriented(_:)` (M;
one cached texture per orientation). A bitmap decoded from a tagged file still draws its stored
pixels (435).

**Header-only read and bounded decode** (`IH-A`…`IH-P`, record 117): `ImageInfo` (M; `init?(data:)`,
`init?(contentsOfFile:)`) reads a PNG's IHDR or a JPEG's first SOF (all thirteen dimension-bearing
markers) and the EXIF orientation without decoding a pixel: `format`, stored `width`/`height`,
`orientation`, `bitDepth`, `channelCount`, `orientedSize`. PNG and JPEG only, `nil` for anything else or a
damaged header, no size limit of its own; the file form seeks over the pixels through one 64 KiB window.
`DecodedImage.Limits` (`maxInputBytes`, `maxSide`, `maxPixels`, all optional and inclusive) with
`DecodedImage(data:format:limits:)` and `DecodedImage(contentsOfFile:format:limits:)` refuse an oversize
image from the header, before the decoder allocates; `DecodedImage` also refuses a decode whose size
disagrees with the header. Cancelling a decode is not offered (`IH-K`).

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
accessibility change. Colour, radius and offset animate. **One shadow per
container** is SwiftUI's own spelling, `compositingGroup()` (`PF-E`, both
vocabularies; a `LayoutModifier.compositingGroup` layer, on a `StyledElement`
it returns `Self`): an enclosing `.shadow` or `.blur` sees the group as one
leaf — one shadow of the union drawn below the whole group, one blur of the
composite. Alone it changes nothing; render only; an opacity outside it is not
composited (205). Shadow, blur, path and gradient rasters are cached
translation-free, so a whole-device-pixel move or pan reuses them (`PF-A`).
Not offered: `drawingGroup`, inner shadows.

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
`.onLongPressGesture` (A); `KeyEquivalent`, `KeyboardShortcut` (A) — their default
modifier is `EventModifiers.primary` (M, `SG-B`: `.command` on Apple, `.control`
elsewhere; SwiftUI's default, `.command`, is the same value on macOS, and SwiftUI has
no `.primary`, probe `swiftui-shortcut-modifiers.swift`);
`@FocusState`/`.focused` (A, 94). The keymap — `Keymap`, `KeyBinding`,
`Keystroke`, `KeyContext`, `ContextPredicate`, `Action` — is gpui's (M).

**The clipboard beyond text** (`CB-`, record 115;
[`superpowers/2026-10-14-clipboard-types-decisions.md`](superpowers/2026-10-14-clipboard-types-decisions.md)).
`.copyable(_:)`, `.cuttable(for:action:)` and `.pasteDestination(for:action:validator:)` on every `StyledElement`
and, once, on proposal content (A: SwiftUI's signatures, probe `swiftui-clipboard-types.swift` arm S) over MetalUI's
`Transferable`: the primary-modifier C, X and V and the Edit menu reach the handler of the focused element or its
nearest ancestor, after the keymap, `onKeyPress` and a focused field's own keys (D, 455, 456: one item, enablement by
presence). A copy writes one representation per exported type, most preferred first, so a type lists
`.utf8PlainText` after its own for a text fallback; a paste walks the destination's imported types in order.
`Window.clipboard` (M) is the same from code: `write(_:)`, `read(_:)`, `contentTypes`, `hasContent(of:)`.
`ClipboardRepresentation` and `ClipboardCommands` are the platform seam's (M). On SDL a custom identifier is the mime
type `application/x-<identifier>` with each byte outside `[a-z0-9.+-]` percent-encoded (`ClipboardMime`, `CB-D`).
`PasteButton` is not built (`CB-N`).

**Input for viewports and canvases** (`CI-`, record §81;
[`superpowers/2026-10-08-input-apis-decisions.md`](superpowers/2026-10-08-input-apis-decisions.md)).
SwiftUI's spellings, probe-backed (`probes/swiftui-input-apis.swift`):
`SpatialTapGesture` (`.location`, the release that ends the tap) and
`.onTapGesture(count:coordinateSpace:perform:)` (A); `MagnifyGesture`
(`.magnification`, `.startLocation`, `.startAnchor`) and `RotateGesture`
(`.rotation`, clockwise-positive) in their own pinch arena from the one
ranking (A; SDL has a pinch on macOS, Wayland and X11, and no rotate);
`CoordinateSpace` `.local` (the default) and `.global` — the window's content
space (D 139); `PointerStyle` and `.pointerStyle(_:)` (macOS 15's spelling:
`.default`, the I-beams, `.rectSelection` — the crosshair — the grab hands,
`.link`, the zooms, the resizes; innermost wins, sent to the platform only on a
change; a paint-only view does not cover it, D 141). MetalUI-only by ruling,
where SwiftUI has nothing: `.onScrollWheel { (event: ScrollEvent) -> Bool }`
(deltas precise or lines, phase, momentum phase, modifiers, `location` local;
offered innermost first before each enclosing `ScrollView`, `true` claims),
`DragGesture(minimumDistance:coordinateSpace:button:)` with `MouseButton`
(`.secondary`, `.middle`, `.other(n)` drag in their own arena; a secondary drag
defers the context menu to the release), `DragGesture.Value.modifiers` (D 140),
and the located `.contextMenu { (location: Point<Pixels>?) in … }` (M). At the
seam (M): `InputEvent.rightMouseDragged`/`.otherMouseDown`/`.otherMouseDragged`/
`.otherMouseUp`/`.magnify`/`.rotate`, `MagnifyEvent`, `RotateEvent`,
`InputPhase`, `ScrollEvent.phase`/`.momentumPhase`/`.isPrecise`/`.location`,
`PlatformPointerStyle`, and the defaultless `PlatformWindow.setPointerStyle(_:)`.
The canvas demo: `METALUI_CANVAS_DEMO=1`.

**Image cursors** (`IC-`, record §116;
[`superpowers/2026-10-14-cursors-headless-decisions.md`](superpowers/2026-10-14-cursors-headless-decisions.md);
probe `probes/swiftui-image-cursor.swift`). `PointerStyle.image(_ image: Image, hotSpot: UnitPoint)`,
SwiftUI's macOS 15 spelling (A): the cursor is the `Image`'s bitmap at `pixels / scale` points
(`resizable()` and `interpolation` are ignored), the hot spot a fraction of that size from the top-left,
clamped to the image (D 465). It is cached per bitmap identity — a bitmap rebuilt into an `Image` every
frame is one cursor — on AppKit (an `NSCursor`, sixteen per window) and on SDL (`SDL_CreateColorCursor`,
straight alpha, eight per platform, a 2x bitmap added as an alternate image). SDL has no hand or zoom
cursor, so an app that wants one supplies the bitmap (`IC-H`; `guides/input.md`). `shape(_:eoFill:size:)`
is carried (`IC-G`). At the seam (M): `PlatformPointerStyle.image` and `PlatformCursorImage`
(`texture`, `scale`, `hotSpotX`/`hotSpotY`, `pixelWidth`/`pixelHeight`, `pointWidth`/`pointHeight`).

**Input follow-ups** (`IF-`, record §93;
[`superpowers/2026-10-10-input-followups-decisions.md`](superpowers/2026-10-10-input-followups-decisions.md);
probe `probes/swiftui-input-followups.swift`). MetalUI-only by ruling, where SwiftUI's
values and callbacks have nothing (D 235, 236): `SpatialTapGesture.Value.modifiers` (the
last press's keys) and `DragGesture.Value.clickCount` (the press's, 1 by default);
`onCancelled(_:)` on `DragGesture`, `MagnifyGesture` and `RotateGesture`, run once for a
leaf that had reported when its arena is dropped (SwiftUI resets `@GestureState` and calls
no `onEnded`; `@GestureState` and `updating` are not built, `IF-A`).
`.onModifierKeysChanged(mask:initial:_:)` (M; SwiftUI's macOS 15 spelling, a transparent
scope whose action runs after the build) reports the held keys with a still pointer; a window
that loses key reports them released. A scroll's events, momentum included, go to the
element under its `.began`, and a scroll whose end never arrives (the window resigned key,
or closed) gets a synthesized `.cancelled`.

**Continuing press cancel** (`GC-`, record §100; no new API, no divergence). A leaf that
reported owes `onCancelled` whatever ends it: a primary press on the element whose press is
still down (a release the app never saw) cancels a reported `DragGesture` and starts a fresh
arena, instead of dropping the drag silently. A real double-click is unchanged.

**Window drag** (`WD-`, record §97;
[`superpowers/2026-10-12-window-drag-decisions.md`](superpowers/2026-10-12-window-drag-decisions.md);
probe `probes/swiftui-window-drag.swift`). `WindowDragGesture` (A; SwiftUI's macOS 15 spelling,
`Value` and `init()`, offered on every platform) attached with `.gesture`/`.highPriorityGesture`/
`.simultaneousGesture` makes its element an opaque pointer target that, after a 5-point move,
asks the platform to move the window and ends, cutting the other members of the press (D 275;
`onCancelled` runs for one that had reported). It wins over gestures on a sibling beneath it
(MetalCreator's full-window viewport under a hidden-title-bar handle) and loses to a `DragGesture`
ahead of it. AppKit only moves the window (D 276); `.opacity(0)` does not disable it (D 277). Not
built: `Scene.windowBackgroundDragBehavior`, `.windowDragArea()`, a double-click zoom. At the seam
(M): the defaultless `PlatformWindow.performWindowDrag() -> Bool`; `MetalUITesting` gains
`HeadlessPlatformWindow.windowDrags`, `Options.performsWindowDrag` and `TestWindow.windowDrags`.
Human checks: group WD, unrun.

**SDL GPU for apps** (`GA-`, items S5 and S6, record §114;
[`superpowers/2026-10-14-sdl-gpu-compute-decisions.md`](superpowers/2026-10-14-sdl-gpu-compute-decisions.md)). All class M,
in `Backends/SDL` behind the `SDL` trait, outside the public census (`GA-L`); SwiftUI has no GPU API. The product
`MetalUISDLGPU` is a thin typed layer over SDL_GPU: `SDLGPUDevice` (`make(debug:preferring:)`, `init(borrowing:)`),
`SDLGPUBuffer`, `SDLGPUTransferBuffer`, `SDLGPUTexture` (MSAA, depth, mips), `SDLGPUSampler`, `SDLGPUComputePipeline`,
`SDLGPUGraphicsPipeline`, `SDLGPUCommandBuffer` with `SDLGPUComputePass` and `SDLGPURenderPass`, `SDLGPUFence`
(`await fence.wait()` off the main actor), `SDLGPUShaderLibrary`; `SDLGPUDrawContext.view` records into the frame's own
command buffer. Every wrapper has `.raw` and the product re-exports `CSDL`. Shipping an app's own shaders is
`docs/packaging.md` section 4a; the guide is [`guides/drawing-and-gpu.md`](guides/drawing-and-gpu.md). Human checks:
group GA, unrun.

**Window chrome on SDL** (`CW-`, item S1, record §112;
[`superpowers/2026-10-13-sdl-chrome-decisions.md`](superpowers/2026-10-13-sdl-chrome-decisions.md);
probe `probes/swiftui-window-chrome.swift`). All class M: SwiftUI has no window-control API. On SDL
`.hiddenTitleBar` makes the window borderless (`CW-B`); `Window.drawsWindowControls` (default `true`) draws a
close, minimise and zoom cluster where the platform has no native buttons and zeroes the cluster inset when off
(`CW-C`, `CW-D`); `Window.minimize()`, `Window.toggleZoom()` and `Window.isZoomed` are the verbs an app-drawn
control calls (close is `performClose()`, through the `AS-B` veto). The band and each `WindowDragGesture` handle
become platform drag regions carved around everything that needs the pointer (`CW-E`, D 425, D 426), and a
borderless window resizes from a 6-point edge (`CW-G`). At the seam: four defaultless `PlatformWindow`
requirements (`setWindowDragRegions(_:) -> Bool`, `performWindowAction(_:) -> Bool`, `hasNativeWindowControls`,
`isZoomed`), `PlatformWindowAction` and the portable `ChromeHitSnapshot`/`ChromeHit` in `MetalUIPlatform`;
`MetalUITesting` gains `Options.sdlChrome`, `usesWindowDragRegions`, `hasNativeWindowControls`, `isZoomed`,
`hiddenTitleBarInsets`, `TestWindow.windowDragRegions` and `.windowActions`. Human checks: group CW, unrun.

**Key and focus scoping** (`KF-`, record §88;
[`superpowers/2026-10-08-key-focus-decisions.md`](superpowers/2026-10-08-key-focus-decisions.md);
probe `probes/swiftui-key-focus.swift`). SwiftUI's `onKeyPress` family — `(_
key:action:)`, `(_:phases:action:)`, `(keys:phases:action:)`,
`(characters:phases:action:)`, `(phases:action:)` — with `KeyPress`
(`.key`, `.characters`, `.modifiers`, `.phase`; made by MetalUI only),
`KeyPress.Phases`, `KeyPress.Result` (A), on a `StyledElement` (returning
`Self`) and on proposal content (returning `KeyboardModifier<Self>`, M). Keys
need focus and walk the chain **outermost first**, after the window's
`Keymap` and before a focused field's editing keys, `onKey`, a `Button`'s
shortcut and Tab; `.handled` stops the walk; a keystroke an app command binds
runs the command and never reaches `onKeyPress` (`KF-B`, `KF-C`, `KF-X`). A
typed character on a focused field is offered as `.down` (D 187); a native-only
menu item's ⌘-key is offered too (D 188). `focusable(_:)` (replacing
`focusable()`, which still resolves) and `focusable(_:interactions:)` with
`FocusInteractions` (A): `.edit` focuses on a primary press (SwiftUI's FC3),
`.activate`/`.automatic` do not (D 94, narrowed); nothing is focused when a
window shows (D 186). **MetalUI-only**: `.hoverKeyRegion(_:)` — with nothing
focused, keys (and the `Keymap`'s contexts) go to the key region under the
pointer; a press in it clears a field's focus (`KF-D`, `KF-E`); a press
elsewhere never resigns focus (`KF-G`, SwiftUI's answer). **MetalUI-only**: `.resignsFocusOnPress(_:)` (on an element and on proposal
content, where it joins the one `KeyboardModifier` layer) — an opt-in container
modifier: a primary press inside it resigns a focused field **without** routing
keys by hover (a text field or `.focusable(interactions: .edit)` inside takes
focus directly, no `nil` between; a secondary press never resigns; SwiftUI has
no equivalent, `RF-A`). Put it on an app root so a press on inert chrome ends
in-place editing. On proposal content
— a `MetalView`, a `GPUSurface` — the keyboard modifiers (`onKeyPress`,
`focusable`, `keyContext`, `focused`, `hoverKeyRegion`) wrap once in a
**`KeyboardModifier`** and every later one joins that layer, so focus, the
binding, the context and the handlers sit on one id: `MetalView { … }
.focusable(interactions: .edit).keyContext("Viewport").onKeyPress("f") { … }`
(`KF-H`); on one layer `onKeyPress` and `.focusable()` are order-free (D 185).
**A `TextEditor`'s commit key**: `.onKeyPress(keys: [.return]) { press in
press.modifiers.contains(commitModifier) ? commit() : .ignored }`, where
`commitModifier` is `.command` on macOS and `.control` on Linux and Windows
(an app's own `#if os(macOS)`; MetalUI exposes no constant) — ⌘↩ (⌃↩ off
macOS) is not one of a `TextEditor`'s editing keys, so a declined one reaches
the window; plain Return still breaks the line (`KF-Z` item 2). The demo:
`METALUI_KEY_FOCUS_DEMO=1`.

**Text selection** (`SL-`, record §96;
[`superpowers/2026-10-12-text-selection-decisions.md`](superpowers/2026-10-12-text-selection-decisions.md);
probe `probes/swiftui-text-selection.swift`). `TextSelection` (A, macOS 15: `indices`, `isInsertion`,
`init(range:)`, `init(insertionPoint:)`, `init(ranges:)`) and `TextField(_:text:selection:)` /
`TextEditor(_:text:selection:)` over `Binding<TextSelection?>` (A), plus the controlled spellings with
`selection:` and `onSelectionChange:` (M). The field writes the binding after each input that moved the
selection and applies a value it did not write on the next frame; nil is never an instruction.
Divergences 265 (a field focused from code keeps its caret) and 266 (nothing is written at focus or
resign). The demo: `METALUI_SELECTION_DEMO=1`.

**Overlays and coordinates** (`OV-`, record §92;
[`superpowers/2026-10-10-overlays-coords-decisions.md`](superpowers/2026-10-10-overlays-coords-decisions.md);
probe `probes/swiftui-overlays-coords.swift`). **Coordinates** (A): `CoordinateSpace` gains
`.named(AnyHashable)` and `NamedCoordinateSpace.named(_:)` (SwiftUI's, `@unchecked Sendable`,
`OV-L`); `.coordinateSpace(_:)` on both vocabularies is a transparent scope (no node, no identity
level) whose content resolves `.named` against the **nearest ancestor so named**, moving with
scrolls and effects, a rotated space reporting the unrotated frame, a name nobody declares
reading `.global` (`OV-E`, `OV-M`); `GeometryProxy.frame(in:)`, `DragGesture(coordinateSpace:)`,
`SpatialTapGesture(coordinateSpace:)` and `onTapGesture(coordinateSpace:)` accept it, and
`onContinuousHover(coordinateSpace:perform:)` (default `.local`) reports in it (`OV-F`, `OV-H`).
**MetalUI-only**: `EnvironmentValues.windowSize` — the window's content size, drawn chrome
included, read-only (`OV-G`, `OV-O`; SwiftUI has none). **Presentation**: `.popover` takes
SwiftUI's `attachmentAnchor: PopoverAttachmentAnchor` (`.rect(.bounds)` default, `.rect(.rect(r))`,
`.point(_:)`; a zero-size rect at the unit point, the popover centred across `arrowEdge`, D 225,
`OV-B`); **`anchoredOverlay(isPresented:at:in:anchor:content:)`** and `(item:…)` on both
vocabularies (M, `OV-A`) put the content's `anchor` corner (default top-leading) at a point in
`.local`, `.global` or a named space — **no panel, border, shadow or padding**, flipped per axis
when it would leave the window then clamped, replaced on a window resize, and dismissed by an
outside press of **any** button (the press still lands on what is beneath, a context menu
included; a press on the declarer dismisses and reaches the declarer) and by Escape; a press or
wheel on the overlay never reaches beneath, keys still reach a field inside it. The point
resolves at layout, so a `.local`/`.named` overlay waits one frame for its declarer's space
(`OV-K`, `OV-S`). `presentationBackground(_:)` is not built (`OV-C`). The demo:
`METALUI_OVERLAYS_DEMO=1`.

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

## App shell — M / A / D

The close veto, the terminate hook, the window title and edited marker, a
hidden title bar and open-document events (rulings `AS-A`…`AS-Q`,
[`superpowers/2026-10-08-app-shell-decisions.md`](superpowers/2026-10-08-app-shell-decisions.md),
whose "Final spellings" table is the short form).

- **Close veto** (M, `AS-B`; SwiftUI has none): `Window.onCloseRequest:
  (@MainActor () -> CloseRequestReply)?` is asked by the close button, ⌘W,
  SDL's `SDL_EVENT_WINDOW_CLOSE_REQUESTED` and `Window.performClose()` —
  `.now` closes, `.cancel` keeps, `.later` waits for
  `Window.replyToCloseRequest(_:)` (show an `.alert` from the handler, reply
  from its buttons; `isCloseRequestPending` while waiting, and a repeated
  request asks nobody). `Window.close()` closes without asking. A window's
  `onDisappear` runs only when it really closes.
- **Terminate hook** (M, `AS-C`, `AS-K`): `App.onTerminateRequest` answers
  ⌘Q, a logout or shutdown (AppKit's `applicationShouldTerminate`, `.later` →
  `.terminateLater`), `SDL_EVENT_QUIT` and `App.terminate()`; after `.later`,
  `App.replyToTerminateRequest(_:)`. **With no handler a quit asks each
  window's `onCloseRequest` in turn**, so a one-window app sets only the
  window's. An approved quit closes every window first (each `onDisappear`
  once); the last window's own close ends the app asking nobody; closing one
  of several windows no longer quits.
- **Title and document** (`AS-D`): `Window.title` (M, settable);
  `.navigationTitle(_:)` (A; inner beats outer, the first sibling wins, in the
  first presented frame; probe `swiftui-app-shell.swift` `N1`–`N5`) and
  `.navigationDocument(_ url: URL)` (A; the proxy icon, never the title) in
  the tree win while present; `Window.representedURL` and
  `Window.isDocumentEdited` (M; AppKit's edited dot). SDL records the edited
  marker and represented file and shows nothing.
- **Hidden title bar** (D, divergence 175; `AS-E`, `AS-J`):
  `App.openWindow(…, windowStyle: .hiddenTitleBar, …)` or `Window.windowStyle`
  (`WindowStyle` `.automatic`, `.titleBar`, `.hiddenTitleBar`) — SwiftUI's
  `.windowStyle(_:)` scene modifier as window state. The content lays out
  **under** the bar; `@Environment(\.titleBarInsets)` (M, `Edges<Pixels>`:
  `top` the band's height, `left` the window buttons' right edge) says what to
  pad by; a press nothing claims in the band drags the window, a double-click
  there zooms or minimises as System Settings says. On SDL the window is
  borderless, the insets read the band (32) and the drawn buttons' cluster
  edge (`right` 138, `left` 70 under macOS), and the window draws close,
  minimise and zoom buttons over the corner (`CW-`, below).
- **Open-document events** (A / D, divergence 176; `AS-G`, `AS-M`, `AS-Q`):
  `.onOpenURL { url in }` in the tree; `App.onOpenURL` when no window has one;
  `App.open(_ urls: [URL])` delivers as the platform does — the launch
  arguments recipe in [`packaging.md`](packaging.md). AppKit delivers Finder,
  `open -a`, Dock drops, Open Recent and URL schemes (the bundle declares its
  document types and schemes); SDL delivers a file dropped on the application
  (window 0). MetalUI never opens a window for an open.
  On SDL, `SingleInstance.claim(id:forwarding:)` (trait `SDL`, MetalUI-only, `Backends/SDL`, outside the census) makes a second launch hand its
  arguments to the running instance, which delivers them as an open event (`SN-A`…`SN-P`, `packaging.md` "One instance on Linux and Windows").
- **Seam** (`AS-H`, `AS-J`; defaultless, `docs/migration.md`): seven
  `PlatformWindow` requirements (`onCloseRequest`, `close()`,
  `setDocumentEdited(_:)`, `setRepresentedFilePath(_:)`,
  `setTitleBarStyle(_:) -> Bool`, `titleBarInsets`,
  `performTitleBarPress(clickCount:) -> Bool`) and four `Platform` ones
  (`onTerminateRequest`, `replyToTerminateRequest(_:)`, `terminate()`,
  `onOpenURLs`); `CloseRequestReply` and `PlatformTitleBarStyle` live in
  `MetalUIPlatform`.

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
`Section` and image items are not offered (a `.menu`-style `Picker` is a view, below).

**Pull-down (A).** `Menu("Title") { }` as a view: a button that opens its items
below itself, published as a menu button.

**Menu bar (A / M).** `App.commands { CommandMenu("Name") { }; CommandGroup(after:/before:/replacing:) { } }`
with `CommandGroupPlacement` (`.appInfo`, `.newItem`, `.undoRedo`, `.pasteboard`, …).
Every AppKit app installs the standard main menu (About, Hide, Quit, File ▸ Close,
Edit, Window); Edit reaches a focused `TextField`/`TextEditor` as its keys.
`Platform.setMenuBar(_:)` and `PlatformMenuBar` are the seam (M). SDL's `setMenuBar` answers
`false`, so every window draws the bar itself: a 25-point strip across its top, above a drawn
toolbar strip, the root laid out below (divergence 195, `SG-A`); command shortcuts fire through the same window shortcut pipeline as a `Button`'s.

**Popovers (A / D 111, 112, 115).** `.popover(isPresented:arrowEdge:content:)` and
`.popover(item:arrowEdge:content:)`: anchored to the declaring element, placed on
`arrowEdge`'s side (default `.top`), flipped then clamped inside the window, no
arrow; an outside press or Escape writes the binding false from input, and the
outside press then reaches what it lands on. Published as a non-modal popover.

**Tooltips (A / D 113).** `.help("text")` publishes `accessibilityHint`'s tree on
both bridges and shows a drawn tooltip after 1.0 s of display-link time, hidden by
a press, wheel, key or leaving.

## Dialogs, alerts and hover — A / D / M

**File dialogs** (`SV-C`, `SV-D`, `SV-E`; probe `swiftui-platform-services.swift`
`D1`–`D5`, `X1`–`X5`): `.fileImporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)`,
the one-file `.fileImporter(isPresented:allowedContentTypes:onCompletion:)` and
`.fileExporter(isPresented:item:contentTypes:defaultFilename:onCompletion:onCancellation:)`
(D: MetalUI's `ContentType` in place of `UTType` and its synchronous
`Transferable`; off Apple a type filters by filename extension only, 129) on
every element group, each returning `PresentationScope<Content>` (D:
transparent, its record in the window's registry; a legacy decoration after it
does not compile, 120). Presented after the frame in which `isPresented` turned
`true`, one per window at a time; `isPresented` is written `false` before the
callback; a cancelled import calls nothing, a cancelled export calls
`onCancellation`; a `nil` item still presents; the exporter writes the
representation conforming to the chosen type, else the first.
`FileExportError.noItem`. **The async call** (M): `FileDialogs.openFiles(allowedContentTypes:allowsMultipleSelection:) async throws -> [URL]`
and `saveFile(contentTypes:defaultFilename:) async throws -> URL?` (`[]`/`nil` on
cancel; `FileDialogError` `.noWindow`, `.unavailable`, `.busy`, `.platform`;
a cancelled task dismisses), `@MainActor`, holding its window weakly — read
`@Environment(\.fileDialogs)` (get-only outside MetalUI, stamped by the window)
or `Window.fileDialogs` from a menu command. `ContentType(_:conformingTo:filenameExtensions:)`,
`preferredFilenameExtension` and `ContentType.json` (D, 129).

**Alerts** (`SV-I`, `SV-X`, `SV-Y`; probes `swiftui-platform-services.swift`
`A1`–`A9`, `C1` and `swiftui-alert-presenting.swift` `R0`–`R4`, `K0`–`K3`; A):
`.alert(_:isPresented:actions:)`, `.alert(_:isPresented:actions:message:)`,
`.alert(_:isPresented:presenting:actions:)` and with `message:`,
`.confirmationDialog(_:isPresented:actions:)` and with `message:`; actions are
the closed `AlertActions` — `Button` with a `Text` label, `role: .cancel` or
`.destructive` — through `@AlertActionsBuilder` (`if`, `if`/`else`, `for`;
`AlertActionItems`). SwiftUI's buttons: the cancel button last and on Escape,
a synthesized "Cancel" beside a lone destructive, one "OK" for none, Return on
the first plain button only when none is destructive; `presenting: nil` still
presents the title and "OK". Any button writes `isPresented = false`, then runs
its action. An `NSAlert` sheet on AppKit; drawn in the window where the platform
declines (SDL). Not offered: `titleVisibility:`, alert text fields, a
non-`Text` button label.

**Window toolbar** (`MD-I`, `MD-J`, `MD-S`, `MD-X`; probes `swiftui-toolbar.swift`
`TB1`, `UP`, `SR` and `swiftui-toolbar-nested.swift` `NT1`, `PO`; D 135, 120):
`.toolbar { … }` with `ToolbarItem(id:placement:content:)` and
`ToolbarItemGroup(placement:content:)` (`ToolbarItemPlacement` `.automatic`,
`.navigation`, `.principal`, `.primaryAction`, `.status`; `@ToolbarContentBuilder`
with `if`/`switch`/`for`), and `.searchable(text:prompt:)`, on every element
group, each returning the transparent `ToolbarScope<Content>` — not an
`Element`, so write it inside the root's first container (120). Items are a
closed set (135): `Button` with a `Text` or `Image` label (`ToolbarButtonLabel`),
`Toggle`, `Picker` (`.menu` a pop-up, else segmented), `TextField`, `Text`, under
`.disabled`/`.help`. Every `.toolbar` in the main tree merges in pre-order, a
popover's or `Deferred` presentation's is ignored, the search field last. On
AppKit a real `NSToolbar` of native controls, updated in place (the window
grows; content keeps its size); the platform seam (M) is the defaultless
`PlatformWindow.setToolbar(_:) -> Bool` with `PlatformToolbar`/`PlatformToolbarItem`/
`PlatformToolbarControl`, outcomes as `InputEvent.toolbarAction(ToolbarActionEvent)`
run under `StateDispatch`. SDL answers `false` (the window draws the toolbar,
lane 3 of port gaps (medium)). Not offered: customization, `.toolbarRole`,
`.toolbar(removing:)`, `.windowToolbarStyle`, `ToolbarSpacer`, search
suggestions/scopes/tokens/`placement:` (`MD-L`).

**Hover** (`SV-N`, `SV-Z`; A — SwiftUI's spellings, MetalUI's semantics, its
probe arms `H1`–`H11` a broken instrument): `.onHover(perform:)` and
`.onContinuousHover(perform:)` with `HoverPhase` (`.active(Point<Pixels>)` in
the element's own space, `.ended`) on both vocabularies — `Self` on a
`StyledElement`, `HoverModifier<Content>` on typed content. A non-opaque
region, inside the disabled and `allowsHitTesting` gates; hovered while nothing
opaque or another hover region covers it on its layer (nested regions all
hover); callbacks from input and after a frame in which content moved under a
still pointer, leavings innermost first, then enterings outermost first; empty
while an in-window menu or a drawn alert is up.

**The drawn alert** (`SV-J` items 2–4, `SV-X`; M look, A rules): where the
platform declines an alert (SDL), the window draws it above everything — a
scrim, a 260-wide panel 24 from the top, the title, the message, the buttons
(two side by side with the resolver's first trailing, three or more stacked),
only the Return default accented. It is modal: Return, Escape, Tab/arrows and
Space, a click on a button; every other event is swallowed; an open drawn menu
closes. Published as one `.alert` node with `.button` children.

**`Divider()` as a view** (`SV-O`; A, D 127): in an element builder a 1-point
line across the nearest `HStack`/`Row` (vertical) or `VStack`/`Column`
(horizontal; also outside any stack and in a `ZStack`/`Grid`), its proposal (or
10) along; the theme's `.separator`; no accessibility node. In a menu builder it
is still a separator.

**Menu picker** (`SV-P`, `SV-AA`, `SV-Q`; A, D 81, 128):
`.pickerStyle(.menu)` — the title, 8, a pull-down button showing the selected
option's title (`""` when no tag matches), as wide as the widest option, opening
every option as a checked-or-not item (a native `NSMenu`, else the drawn panel,
which scrolls when taller than the window and opens on the selection); choosing
writes the tag. Options are recorded without layout (hundreds cost one record
each); a non-`Text` option is titled by its tag (128). Published as
`.popUpButton`. `.automatic` stays segmented (81).

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

## Lifecycle — A / D

`.onAppear(perform:)`, `.onDisappear(perform:)` and `.onChange(of:initial:_:)`
in both closure forms (`{ oldValue, newValue in }` and `{ }`, over an
`Equatable` value) on every element group of both vocabularies (A; `LC-B`,
`LC-G`; probe `swiftui-lifecycle.swift`). Each returns `LifecycleScope<Content>`
— layout- and identity-transparent, typed `ProposalElementGroup` over proposal
content; `LifecycleScopeLayout` is its group layout (M). **Presence is
membership in a build**, keyed on the scope's position: hidden, transparent,
zero-sized and clipped content is present; an `if` removing content, an `.id`
change inside the modifier, and a `List` row leaving its window are
disappearances; a modifier on a `ForEach` or group fires once for the group,
while it has content (`LC-C`, `LC-P`). **Actions run after the build, outside
every phase, under the element's `StateDispatch`** — a `@State`, `Binding` or
`@Observable` write there is legal; one settle build presents the first level
of writes in the same frame (`LC-E`). `onChange` compares against the previous
build's value for the same identity, coalesces writes between frames, and fires
on first sight only with `initial: true`. Order: changes, then appears, then
disappears, each children first (`LC-F`). A disappearance under a removal
transition waits for the fade to end; `onDisappear` reads its element's state
as it was (`LC-H`, `LC-I`). Closing a window runs every present `onDisappear`
once; a headless `renderFrame` runs no action (`LC-J`). Divergences 120–125: a
legacy decoration after the scope does not compile, and a scope cannot be a
window's root (120); the settle bound (121); one fixed order (122); re-inserted
mid-fade content is fresh (123); a `List`'s first frame appears every row
(124); a never-written `@State` default is re-seeded (125).

`.task(name:priority:file:line:_:)` and `.task(id:name:priority:file:line:_:)`
(A; `PX-F`, `PX-G`; probe `swiftui-task.swift`) — SwiftUI's spelling and
closure type (`@_inheritActorContext sending @escaping @isolated(any) () async
-> Void`, main-actor in an element), on the same `LifecycleScope`: the start
is an appearance (the body runs synchronously until its first `await`, under
the element's `StateDispatch`, so a write there is in the first frame), the
cancel a disappearance (parked under a removal transition; a re-inserted
element keeps its task), an id change a change event that cancels, then
starts. Closing a window cancels every task; a headless `renderFrame` starts
none. Priority defaults to `.userInitiated`, the name to `"View.task @
<file>:<line>"`. On macOS 14–25 the body starts on the next main-queue turn
(137). Under `SDLPlatform` a task progresses through the loop's main-queue
drain (`SV-H`).

**Geometry and time** (`KF-J`, `KF-K`, `KF-L`, `KF-S`, `KF-T`, record §88).
`.onGeometryChange(for:of:action:)` in both action forms (`{ new in }`, `{
old, new in }`) with `GeometryProxy` (`.size`, `.frame(in: .local / .global)`)
(A; wider than SwiftUI on concurrency — no `@Sendable`, no `Sendable` `T`,
`KF-S`): a transparent `GeometryChangeScope` (M) whose value is computed in
prepaint and whose action runs in the lifecycle drain, before the build's
lifecycle events — the initial value is in the first presented frame, a live
resize reports every frame; a legacy decoration after it does not compile (D
120). `TimelineView(_:content:)` with `TimelineSchedule`,
`TimelineScheduleMode`, `.animation`, `.animation(minimumInterval:paused:)`,
`.periodic(from:by:)`, `.everyMinute`, `.explicit(_:)`,
`TimelineViewDefaultContext` (`.date`, `.cadence`, always `.live`) and its
`Context` typealias (A): identity- and layout-transparent; `.animation` keeps
the display link running exactly while it is built, other schedules rebuild
through one wake at their next date.

## Animation and transitions — A

`Animation` (`linear`, `easeIn`, `easeOut`, `easeInOut`, `timingCurve`,
`spring`), `withAnimation`, `Transaction`, `withTransaction`,
`.transaction(_:)`, `.animation(_:value:)`, `Binding.animation(_:)`,
`AnyTransition` (`identity`, `opacity`, `move(edge:)`, `slide`, `offset`,
`scale`, `push(from:)`, `asymmetric`, `combined`), `Edge`, `.transition(_:)`
(96–99).

## Controls and looks — A / D / M

Rulings `LK-A`…, record §85 (C10). **Controls**: `Slider(value:in:step:onEditingChanged:)` —
`true` at the press or the first key of an edit, `false` at its end (the release,
a lost release ended by the next press, a close or a disabled gate; one pair per
gesture, SwiftUI's order — `LK-B`, `LK-Q`); `ColorPicker(_:selection:supportsOpacity:)` and
`ColorPicker(selection:supportsOpacity:label:)` over MetalUI's `Color`, a 48 × 24
well beside its label that opens a **drawn** panel on every platform — a
saturation–brightness square, a hue bar, an opacity bar, a swatch and a hex
field (165: not `NSColorPanel`; `LK-C`, `LK-D`); `ProgressView()` (the spinner,
sizes 32/16/10 by `controlSize`), `ProgressView(value:total:)` (a greedy 20-tall
bar; indeterminate when the value is `nil`), the `_ title:` and label /
current-value-label spellings, `.progressViewStyle(.automatic/.linear/.circular)`
on the view or a container (`LK-E`, `LK-F`, `LK-V`). Three accessibility roles
join `AccessibilityRole` (`.progressIndicator`, `.busyIndicator`, `.colorWell`; `LK-G`) — M.
**Animation**: `keyframeAnimator(initialValue:trigger:content:keyframes:)`,
`keyframeAnimator(initialValue:repeating:content:keyframes:)`, `KeyframeAnimator`,
`KeyframeTimeline`, `KeyframeTrack`, `LinearKeyframe`, `CubicKeyframe`,
`SpringKeyframe` (`duration:` required, 168), `MoveKeyframe`, `Spring`, `UnitCurve`
and `VectorArithmetic` (169; a zero-duration keyframe reads its target, 171);
`phaseAnimator` is not built (`LK-H`). **Looks**: `Gradient`, `LinearGradient` and
`RadialGradient` (colours, stops or a `Gradient`; views, `ShapeStyle`-like `fill`,
`stroke` and `background` overloads in both vocabularies, rasterized on the CPU
through the image path with a one-texel strip fast path, no shader change —
`LK-J`), `.blur(radius:)` (per leaf, sigma = radius, the shadow pipeline in colour;
a GPU surface leaf draws unblurred, 167; `LK-K`) and `Material` (`ultraThinMaterial`
… `ultraThickMaterial`, `bar`) as `.background`/`fill` — a **tint over a real
backdrop blur** of what is already drawn beneath it, GPU surfaces included, on both
renderers (item C21, record §94: sigma 52 pt, rounded rectangle or ellipse, clip,
transform, opacity and transitions; the flat tint of `LK-L` remains for a path
fill, inside a CPU-rasterized `.shadow`/`.blur`/`.compositingGroup()` leaf and where
a renderer cannot blur; divergences 166, 245–248, Reduce Transparency 315; `BB-A`…`BB-T`); `Material.tint(in:)`
reads a material's tint as a `Color` (MetalUI-only, class M; C27, `MT-B`; a material takes
no colour, `MT-C`). Not built:
`AngularGradient`, `EllipticalGradient`, `Gradient.colorSpace(_:)`,
`.foregroundStyle(gradient)`, `.blur(radius:opaque:)`, `phaseAnimator`, a native
`NSColorPanel` route, a material that takes a colour or an opacity (`MT-C`), saturation lift — each a
named deferral (`LK-A`, `BB-I`).

## Testing — M

`MetalUITesting` (a library product for test targets, portable; rulings
`HT-A`…, [`superpowers/2026-10-09-test-harness-decisions.md`](superpowers/2026-10-09-test-harness-decisions.md)):
`TestApp` and `TestWindow` run the real `App` and `Window` over
`HeadlessPlatform`/`HeadlessPlatformWindow`/`HeadlessWindowRenderer`, with a
simulated clock (`tick`, `advance(by:)`, `advanceFrames`, `runUntilIdle`),
input by point and by element in XCUITest's names (`click`, `typeText`,
`scroll`, `drag`, …), accessibility queries (`element(label:)`,
`element(identifier:)`, `elements(role:)`, `TestElement`), laid-out frames
(`frame(ofID:)`), presentations answered at the seam (`respondToAlert`,
`chooseMenuItem`, `performToolbarItem`, the menu bar's `performMenuBarItem`,
`MenuEvaluation`; `HeadlessPlatform` options such as `presentsMenusNatively` and `showsMenuBarNatively` choose whether the platform or the window draws) and per-frame work counters (`FrameWork`) for benchmarks
that count work, and an input-method driver beside `typeText` (M; `IM-A`, record §102: `setMarkedText(_:selectedRange:)`, `commitMarkedText()`, `commitMarkedText(_:)`, `cancelMarkedText()`, `markedText`, `markedSelection`, sending the platforms' own composition events through `onInput`) and the clipboard read-backs (M; `CB-K`: `clipboardRepresentations`, `setClipboard(_:)`, `setClipboard(text:)`). SwiftUI tests UI out of process, so this is MetalUI-only.
How an app uses it: [`testing.md`](testing.md).

## Backends and infrastructure — M

`MetalUICore` (geometry, units — `Pixels`, `Length`, `Dimension` — colours,
`Appearance`, `ControlActiveState` (A), `LayoutDirection` (25)),
`MetalUILayout` (the layout kernel: `LayoutTree`, `ProposalLayout`,
`ProposedSize`, rounding — 77), `MetalUIPlatform` (`Platform`,
`PlatformWindow`, `WindowRenderer`, input events, the accessibility tree; the
platform-services seam, `SV-B`: `PlatformFileType`, `PlatformFileDialog`,
`FileDialogResultEvent`, `PlatformAlert`, `PlatformAlertButton`,
`AlertResultEvent`, `InputEvent.pointerExited`/`.fileDialogResult`/`.alertResult`,
`AccessibilityRole.popUpButton`/`.alert`),
`MetalUIScene` (`Scene` — with its per-instance `MUITransform` table,
`Scene.transforms`/`insert(_:…transform:)`, `GX-F` — the glyph atlas,
`FontKey`, `ImageTexture`),
`MetalUIRender` (the Metal renderer), `MetalUIAppKit` (the AppKit platform),
`MetalUIPrimitives`, `MetalUITextSystem`, `MetalUIText`, `MetalUIFreeType`,
`MetalUIHarfBuzz`, `MetalUIPortableText`, `MetalUISystemFonts`,
`MetalUIPath` (paths, strokes, exact-area coverage, blur — `package` API,
no product, imports nothing, `GX-B`), and
`MetalUIDemoContent` (the demo trees, importable by tests).
