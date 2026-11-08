# Migrating to MetalUI's SwiftUI vocabulary

MetalUI has two element vocabularies over one layout engine:

- **The SwiftUI vocabulary** — `HStack`, `VStack`, `ZStack`, `Spacer`,
  `Grid`, `ProposalScrollView`, `ProposalText`, the shapes, `Image`, and the
  modifiers on proposal content (`.frame`, `.padding`, `.background`,
  `.overlay`, `.clipShape`, …). It follows SwiftUI on macOS, with the
  differences listed in [`divergences.md`](divergences.md).
- **The legacy vocabulary** — `Box`, `Row`, `Column`, `Stack`, `ScrollView`,
  `List`, `Text` and the `StyledElement` modifiers. It began as a CSS flexbox
  API; since plan task 7 stage 9 (2026-09-24) the CSS engine is deleted and
  every legacy element **lowers onto the same propose/measure/place kernel**.
  It keeps working, but a few of its defaults are still CSS-shaped (below).

This page is for code moving from the legacy vocabulary to the SwiftUI one,
and for code written against MetalUI before 2026-09-12 (when the
SwiftUI-alignment plan began). Part 1 maps the spellings; part 2 lists every
breaking or behaviour change since then, with its migration spelling and the
ruling that made it (rulings are in [`superpowers/`](superpowers/)).

## Part 1 — legacy spellings and their SwiftUI-vocabulary replacements

### Migrate inside-out — or not at all

**Since proposal controls (`PE-B`, 2026-10-06), the two vocabularies nest
both ways.** A SwiftUI-vocabulary element sits inside a legacy container
(`Row { HStack { … } }`), and a legacy element, group or `Component` sits
inside a SwiftUI-vocabulary container: `HStack`, `VStack`, `ZStack`, `Grid`,
`GridRow`, `ProposalScrollView`, `ProposalLayoutContainer` and a
`ProposalLayout`'s `callAsFunction` build their content with
`ProposalContentBuilder`, which passes proposal content through untouched and
adopts anything else as `LegacyContent` — identity- and layout-transparent,
so the legacy element takes the id a proposal element in its position would
and lays out exactly as it does in a `Row`/`Column` (`PE-C`). So a SwiftUI
form ports as written:

```swift
VStack(alignment: .leading) {
    HStack { Text("Name"); TextField("Name", text: $name) }   // the field fills the row
    HStack { Toggle("Enabled", isOn: $on); Spacer(); Button("Apply") { apply() } }
    HStack { Text("Speed"); Slider(value: $speed) }           // the slider fills the row
    Picker("Mode", selection: $mode) { … }.pickerStyle(.menu)
    Divider()
}
.padding(Edges(all: Pixels(16)))
```

Every control keeps its one hitbox, focus and Tab order, keyboard table,
`.disabled` gate, accessibility record, animation and drag preview in either
vocabulary (`PE-I`). You can still convert subtrees one at a time; nothing
forces an order.

**What still takes proposal content only** (a compile error on
`ProposalElementGroup`): the MetalUI-only wrappers `ProposalFrame`,
`Padding`, `Background`, `FixedSize`, and `nativeOverlay` — write the
modifiers instead (`.frame`, `.padding`, `.background`, `.fixedSize`,
`.overlay`; on a legacy element these are its own legacy spellings, or
`PE-F`'s for `.fixedSize`).
`ForEach`'s own builder stays `ElementBuilder`: a `ForEach` of legacy rows is
one adopted expression inside a stack, which works. `aspectRatio`,
`scaledToFit` and `scaledToFill` are not offered on legacy content.

**A legacy item field on content in a SwiftUI-vocabulary container is
reported by name** — `<site>.<field>.unconsumed`, which traps in a production
window (`LR-AQ`, `PE-C` item 4): SwiftUI's stacks have no flex fields, so
nothing reads them, and a silent drop would be an approximation. Re-spell
each in SwiftUI's vocabulary:

| reported field | SwiftUI spelling |
|---|---|
| `.flexGrow(1)` | `.frame(maxWidth: .infinity)` on it (`Pixels.infinity`, `PE-F` item 2), or a `Spacer()` beside it |
| `.flexShrink(0)` | `.fixedSize()` (on the axis: `.fixedSize(horizontal: true, vertical: false)`), or `.layoutPriority(1)` |
| `.flexBasis(…)` | `.frame(width:)`/`.frame(idealWidth:)` |
| `.alignSelf(…)` | the stack's `alignment:`, or `.frame(maxWidth: .infinity, alignment: …)` on the child |
| `.minWidth`/`.maxWidth`/… (deprecated; `minSize`, `maxSize`) | `.frame(minWidth:maxWidth:…)` |
| `.margin(…)` | `.padding(…)` written on the child |

`.layoutPriority`, `.fixedSize` and the four grid-cell modifiers
(`.gridCellColumns`, `.gridCellAnchor`, `.gridColumnAlignment`,
`.gridCellUnsizedAxes`) are spelled on legacy content too (`PE-F` item 1).

**Style modifiers.** `.buttonStyle(_:)` and `.toggleStyle(_:)` are environment modifiers, as in SwiftUI (`BY-A`,
`BY-H`): write them on a container (`Column { … }.buttonStyle(.plain)`) or on the control, before or after a wrapper.
`.pickerStyle(_:)` and `.keyboardShortcut` still return the control itself: write them on the control, before any
wrapper — `Picker(…) {}.pickerStyle(.radioGroup).padding(8)`, not `….padding(8).pickerStyle(.radioGroup)` (which
does not compile, `PE-R`).

### Containers

| legacy | SwiftUI vocabulary | what changes |
|---|---|---|
| `Row { … }` | `HStack { … }` | **spacing**: `Row`'s default gap is **0**, `HStack`'s default is SwiftUI's 8 between adjacent views (divergence 52, kept, `CX-E`) — write `HStack(spacing: 0)` to keep the old look, or accept 8. A `VStack`'s default is 8 **except at a vertical text edge**, where it is the font's own gap (a `VStack` of two `Text`s no longer has 8 between them: 0; a `Text` above a rect 8.151 at 13 pt, below one 4.742; `DS-E`, record 203). Both centre on the cross axis. `Row(gap: g)` → `HStack(spacing: g)` |
| `Column { … }` | `VStack { … }` | as `Row`/`HStack`; a `Grid`'s row gap follows the same text rule |
| `Row`'s `.flexGrow(1)` child | a `Spacer()` beside it, or `.frame(maxWidth: .infinity)` on it | a greedy frame takes the surplus (`CN-B`); equal growers already shared equally |
| `.justifyContent(.spaceBetween)` etc. | `Spacer()`s between the children | the lowering already uses spacers (`LR-AB`) |
| `.alignItems(…)` on a `Row`/`Column` | `HStack(alignment:)`/`VStack(alignment:)` | typed alignment: `VerticalAlignment` for an `HStack` (`.top`, `.center`, `.bottom`, `.firstTextBaseline`, `.lastTextBaseline`), `HorizontalAlignment` for a `VStack` (`CN-I`) |
| `.alignSelf(…)` on one child | `.frame(maxWidth: .infinity, alignment: …)` on that child | SwiftUI has no per-child cross alignment; a frame aligns its content |
| `Stack(alignment:) { … }` | `ZStack(alignment:) { … }` | both now offer each child the proposal (divergence 53 retired, `CX-R`); `ZStack`'s alignment is a `ProposalAlignment` |
| `Box { … }` (one child, a background, padding) | the child with `.padding(…)`, `.background(…)`, `.frame(…)` | a `Box` stretches its children on the cross axis (`EP-8`); the replacement is the modifiers, in SwiftUI's order |
| `Box(decoration: d) { … }` | `.background(token)`, `.border(token, width:)`, `.clipShape(…)` on the content | |
| `ScrollView(.vertical) { … }` | `ProposalScrollView(.vertical) { … }` | the legacy `ScrollView` takes its **parent's** cross size, `ProposalScrollView` its **content's** (divergence 54, kept). Both share one chrome (indicators, clamping) |
| `List(data, rowHeight:) { … }` | `List(data) { … }` for rows of differing heights | `List` stays MetalUI's virtualized list; it needs an enclosing scroll view (divergence 84, kept). `List(data, rowHeight:)` keeps uniform rows (the fast path, `VL-I`); `List(data) { … }`, `List(data, selection:) { … }` and `estimatedRowHeight:` size each row from its content at the list's width, exactly its content's height (no inset or 24-point floor, divergence 145), keeping the row on top in place as rows above it are measured (`VL-G`). A `List` (selectable too) now also works inside a `ProposalScrollView`, windowing against its offset (`PE-V`: the proposal scroller publishes its `ScrollContext` as `ScrollView` does). For a short list, `ProposalScrollView { VStack { ForEach(data) { … } } }` |
| `Text("…")` | `Text("…")` — unchanged | since `PE-G`, `Text` works in a proposal container and lays out exactly as `ProposalText` (the same measurement, with baselines, so `.firstTextBaseline` aligns it). `ProposalText` remains for the proposal modifier spellings (`.background` returning a layer); `text.proposalLayout()` converts one, **dropping** its background, handlers, id and hover/focus colours |
| `margin(…)` | `.padding(…)` written outside the element | a margin was a padding outside the item frame (`LR-AB`); `.auto` was 0 |
| `position(.absolute)` + `inset(…)` inside a `Deferred` | (unchanged) | MetalUI-only: a presentation root against the window (`LR-CH`). Outside a `Deferred` it is refused by name (`LR-FO`) |

### Sizing — the eight deprecated modifiers

`width`, `height`, `minWidth`, `minHeight`, `maxWidth`, `maxHeight`,
`width(fraction:)`, `height(fraction:)` (and the `percent:` renames) are
deprecated toward `.frame` (stage 8, `FR-I`/`LR-ER`; still working, kept
deprecated by `CX-C`). The recipe (`LR-ES`):

1. **One frame per run of adjacent calls**: `.width(100).height(40)` →
   `.frame(width: 100, height: 40)`; `.minWidth(50).maxWidth(200)` →
   `.frame(minWidth: 50, maxWidth: 200)`.
2. **A decoration, handler, accessibility modifier, `hidden()` or `.id()` on
   the sized element moves after the frame**, onto the outer layer
   (`.id()` stays outermost): `.background(.accent).width(100)` →
   `.frame(width: 100).background(.accent)`.
3. **A sized container's frame keeps where its content sat** via
   `alignment:`.
4. **An item field written after the frame** (`.flexGrow`, `.alignSelf`) is
   refused by name; re-spell it in SwiftUI's vocabulary, e.g. a grower on a
   fixed cross axis → `.frame(height: h).frame(maxWidth: .infinity)`.
5. **A fixed axis and a bound on the other axis are two frames**, the
   flexible one inner, both aligned where the content sat.
6. **An absolute box's size is a frame before `.position`/`.inset`.**
7. A structural id path used only to locate state is re-derived (each frame
   is one identity level).
8. An animated size still interpolates.

**There is no automatic minimum to cancel** (`LR-ET`): a growing box that must
answer below its content is `.frame(minHeight: 0, maxHeight: .infinity)` —
the minimum on the greedy frame itself. `width(fraction: 1)` → `.frame(maxWidth:
.infinity)`; a non-full fraction has no SwiftUI spelling and traps by name
under the kernel (`LR-FO`), which is why every `fraction:` spelling is
deprecated. `flexBasis(fraction:)`/`flexBasis(percent:)` likewise: declare a
length or a `.frame` (`CX-C` item 2).

`Component.width`/`.height` are **not** deprecated: they frame each member
(`LR-BG`), where `.frame` on a multi-member `Component` is one layer over a
row of per-member frames (spacing 0), the members aligned by the frame's own
`alignment:` where SwiftUI's `Group` frames each member and lets the parent
lay them out and align them (divergence 56).

### Modifiers

| legacy (`StyledElement`) | SwiftUI vocabulary (proposal content) | note |
|---|---|---|
| `.padding(px)` / `.padding(Edges<Length>)` | `.padding(Edges<Pixels>)` | the proposal `.padding` splits by argument type: there is no proposal `.padding(Pixels)` |
| `.frame(…)` | `.frame(…)` | the same surface on both vocabularies, lowered onto the same kernel frame |
| `.background(token)` | `.background(token)` | both also take a `Color` since colour and colour scheme (`CR-E`): `.background(.red)`, `.background(Color(red: 0.2, green: 0.4, blue: 0.6))` |
| `.cornerRadius(r)` | `.cornerRadius(r)` / `.clipShape(RoundedRectangle(cornerRadius: r))` | the legacy one rounds fill and border and clips nothing; the proposal one clips, as SwiftUI's (divergence 47) |
| `.border(token, width:)` | `.border(token, width:)` | the legacy band follows a corner radius; the proposal band is square (divergence 49) |
| `.clipped()` / `.clipShape(s)` | `.clipped()` / `.clipShape(s)` | |
| `.opacity(x)` | `.opacity(x)` | what is written after it escapes it, on both (`LR-FW`) |
| `.allowsHitTesting(b)` | `.allowsHitTesting(b)` | |
| `.contentShape(…)` | `.contentShape(…)` / on `.onTap`, `.gesture` | |
| `.onClick { }` | `Button { } label: { }`, or `.onTap { }` / `.onTapGesture { }` | `onClick` is press-and-release-on-one-element (Button semantics); `.onTapGesture` is SwiftUI's tap gesture (`IX-B`) |
| `.hoverBackground`, `.focusBackground`, `.focusBorder` | (MetalUI-only) | |
| `.onKey`, `.onAction`, `.keyContext`, `.focusable()` | (MetalUI-only; the keymap) | `.focused(_:)`/`@FocusState` for focus state |
| `.pointerStyle(_:)` | `.pointerStyle(_:)` | SwiftUI's (macOS 15): the innermost style wins, `nil` defers outward; on one legacy element the first written is the inner, so a second `.pointerStyle` does not replace it (`CI-H`, `CI-AH` item 2); a paint-only view does not cover a style (divergence 141) |
| `.onScrollWheel { event in … }` | `.onScrollWheel { event in … }` | MetalUI-only on both (SwiftUI has no per-view wheel hook): return `true` to claim; `event.location` is local; a handler on a `ScrollView` sees nothing over it — put it on the content to veto scrolling (`CI-I`, `CI-AH` item 1) |

### Colours — literals, dynamic colours, an app palette, the colour scheme

Since colour and colour scheme (rulings `CR-A`…`CR-Z`), `Color` is SwiftUI's
value and every site that took a `ColorToken` — `background`, `border`,
`fill`, `stroke`, `strokeBorder`, `shadow(color:)`, `foregroundColor`/
`foregroundStyle`, `Background`, `Rectangle(width:height:color:)`,
`onTap(hoverColor:)`, `hoverBackground`/`focusBackground`/`hoverBorder`/
`focusBorder` — takes a `Color` on both vocabularies. Every `ColorToken`
spelling still compiles: `.background(.surface)` now picks the `Color` static
`Color.surface`, which resolves bit-exactly to the token; a `ColorToken`
variable takes the kept token overload.

| SwiftCrossUI / hand-written paint pass | MetalUI | note |
|---|---|---|
| an RGB colour (`Color(r, g, b)`, `Hsla.rgb(0x…)` in `paint`) | `Color(red: 0.2, green: 0.4, blue: 0.6)`, `Color(.sRGB, red:…)`, `Color(.sRGBLinear, red:…)`, `Color(white: 0.5)`, `Color(hue:saturation:brightness:)`, `Color(Hsla.rgb(0x336699))` | gamma sRGB as SwiftUI (`CR-C`); drawn on an sRGB layer like every MetalUI colour (divergence 1, `LS-A`) |
| SwiftUI's named colours | `.red`, `.blue`, … `.brown`, `.gray`, `.black`, `.white`, `.clear`, `.primary`, `.secondary`, `.accentColor` | hues are the macOS 27 values in light and dark (divergence 117); `primary`/`secondary`/`accentColor` follow the theme (divergence 116) |
| a colour picked per light/dark at the call site | `Color(light: …, dark: …)` | MetalUI-only (SwiftUI has no such initialiser, probe `D1`); resolves against the element's `colorScheme` and never fades on a switch (`CR-H`) |
| an app's palette of named colours (SwiftUI: an asset catalog) | `enum Brand: ThemeColorKey { static var defaultValue: Color { Color(light: …, dark: …) } }`, then `Color(Brand.self)` anywhere a colour goes; override per variant with `app.darkTheme[Brand.self] = …` (or `window.lightTheme`/`darkTheme`, or a `.theme(_:)` scope's `Theme`) | `CR-N`; the built-in tokens are untouched by a palette |
| `.opacity(0.5)` on a colour | `Color.red.opacity(0.5)` | multiplies; on a `Color` view it is now the value method — one fill, no opacity layer (`CR-G`) |
| `@Environment(\.colorScheme)` | the same, readable while building | stamped from the window's appearance (`CR-J`); `.environment(\.colorScheme, .dark)` changes a subtree and selects the window's dark theme variant (`CR-S`) |
| `.preferredColorScheme(.dark)` | the same, window-wide, as SwiftUI | also sets the platform window's appearance (AppKit `NSWindow.appearance`; SDL's decorations stay with the system, `CR-M`); `Window.preferredColorScheme` / `App.preferredColorScheme` set it programmatically (`CR-L`) |
| a theme switch by hand (`window.theme = .dark` on an appearance change) | nothing: the window selects `lightTheme`/`darkTheme` by its scheme | assign `window.lightTheme`/`darkTheme` (or `App`'s) to customise a variant (`CR-K`) |
| a colour read in a custom `paint` | `pass.resolve(color) -> Hsla` | the element's scoped theme and scheme (`CR-H`); `Color.resolve(in: environment)` gives SwiftUI's `Color.Resolved`, clamped (divergence 118) |

### Lifecycle — onAppear, onDisappear, onChange

Since lifecycle modifiers (rulings `LC-A`…`LC-S`), `.onAppear`, `.onDisappear`
and `.onChange(of:initial:_:)` exist on both vocabularies with SwiftUI's
spellings and, where a probe measured it (`swiftui-lifecycle.swift`), SwiftUI's
answers. Five things port differently:

| SwiftUI / SwiftCrossUI | MetalUI | note |
|---|---|---|
| `.task { await … }`, `.task(id:) { … }` | the same spelling (`task(name:priority:file:line:_:)`, `task(id:name:priority:file:line:_:)`, since portable app); write legacy decorations before it, as for every lifecycle modifier | started as an appearance, cancelled as a disappearance, restarted (cancel, then start) on an id change; on macOS 26 and later, Linux and Windows the body runs synchronously until its first `await`, so its write is in the first frame; **on macOS 14–25 it starts one main-queue turn later** and that write is presented one frame late (divergence 137, `PX-F`, `PX-G`). An `.onAppear`/`.onDisappear` pair written for its absence (`LC-L`) keeps working |
| `Text("a").onAppear { … }.onTapGesture { … }`, `.padding()` after it — any order | the same spelling compiles on an element (`Text("a").onAppear { … }.onClick { … }`); every transparent scope takes them after it | a scope over an `Element` is an `Element` forwarding to its content (`ES-A`); `.coordinateSpace`, `.animation(_:value:)`/`.transaction` and `.onGeometryChange` keep a decoration after them in a layer of their own, outside the space, the transaction or the measured geometry as in SwiftUI (`ES-H`, `ES-J`; divergence 120 retired) |
| a chain of actions (an `onAppear` whose write inserts content whose own `onAppear` writes) settles before the first draw | the first level's writes are presented in the same frame (one settle build); each later level's one frame later — never a loop | divergence 121 (`LC-E` item 3) |
| a modifier on a `ForEach` or `Group` | the same — it fires **once for the group**, not per child, and only while the group has content: an empty `ForEach` does not appear; it appears with its first row and disappears with its last | as SwiftUI (`A6`, `A6b`; `LC-P` item 1); write the modifier on the row inside the `ForEach` for per-row callbacks |
| `@State var monitor = Monitor()` started in `onAppear`, stopped in `onDisappear` | nothing: both reach the first instance (it was a different one, divergence 125, retired by `FV-A`); writing the instance in `onAppear` (`@State var monitor: Monitor? = nil`) still defers its construction | a `@State` keeps its default's first evaluation for the element's lifetime (see the `FV-A` row below) |

Order is one rule (changes, then appears, then disappears, each children
first — divergence 122); a disappearance under a removal transition runs when
the fade ends; a `List` row leaving its window disappears, and a `List`'s
first frame appears every row once (divergence 124); closing a window runs
every present `onDisappear` once (`LC-J`).

### Toolbar — `.toolbar`, `.searchable`

Since port gaps (medium) (rulings `MD-I`, `MD-J`, `MD-S`), `.toolbar { ToolbarItem(placement:) { … } }`
and `.searchable(text:prompt:)` exist on both vocabularies with SwiftUI's
spellings. On AppKit they become a real `NSToolbar` of native controls (the
window grows by the toolbar's height; content keeps its size). Two things port
differently:

| SwiftUI / SwiftCrossUI | MetalUI | note |
|---|---|---|
| `.toolbar { … }` on the scene's root view | write it on the root element, or on any element inside the root's first container — every `.toolbar` in the window's tree is merged in tree order, as SwiftUI merges nested toolbars | a toolbar scope over an `Element` is an `Element` (`ES-A`, which ended `MD-S`'s root restriction) |
| any view in a `ToolbarItem` | `Button` (a `Text` or `Image` label), `Toggle`, `Picker` (`.menu` or segmented), `TextField`, `Text` — anything else does not compile | divergence 135 (`MD-I` item 3) |

## Part 2 — breaking and behaviour changes since 2026-09-12

Collected from every ruling's migration note
(`grep -rn -i -E "migration note|\*\*migration" docs/superpowers`) and the
public-API removals the records list. **Source** changes stop compiling;
**behaviour** changes compile and answer differently.

### Removed or narrowed API (source)

| old spelling | new spelling | ruling |
|---|---|---|
| `Binding("cmd-k", A())` (the keymap's alias) | `KeyBinding("cmd-k", A())`; `Binding<Value>` is now SwiftUI's binding | `EV-N`, `DD-D` item 6 |
| `Box(style: Style(), decoration: d) { … }` | `Box(decoration: d) { … }` (`style:` is `package`; outside the package it could only be `Style()`) | `CX-D` |
| `Style` fields (`size`, `padding`, `flexGrow`, …) written directly | the modifiers; `Style` is opaque outside the package | `LR-FM` item 2 |
| `Style.aspectRatio`, `.overflow`, `.border`, `.flexWrap`, `.alignContent`, `Position.relative`, `FlexWrap`, `AlignContent`, `Overflow`, `.flexWrap(_:)`, `.alignContent(_:)` | deleted (no lowering reads them); `.aspectRatio(_:contentMode:)` on proposal content, `.border(_:width:)` | `LR-FM` item 1 |
| `LayoutPass.requestNode`/`requestLeaf` (custom element registrars) | `requestNativeLeaf`, or a `ProposalLayout` in a `ProposalLayoutContainer` | `LR-CT` (deprecated), `LR-FF` (deleted) |
| `computeLayout`, `unbreakableRuns(of:)`, `Shaper.runCallCounter`, `LayoutAuthority`, `Frame.layoutAuthority` | deleted with the CSS engine | `LR-FC`, `LR-FD` |
| `ModifiedContent<ModifiedContent<…>>` nested types | one flat `ModifiedContent<Content, Modifier>`; `ModifiedElement<C>` is a typealias for its legacy arm | `LR-FV` |
| `Rectangle.color` as `ColorToken` | `ColorToken?` (`nil` is the foreground style): a reader writes `rect.color ?? token` | `TE-AQ` item 2 |
| an exhaustive `switch` over `VerticalAlignment` | add `default:` or `.firstTextBaseline`/`.lastTextBaseline` | `TE-K` item 1 |
| a `TextSystem` conformer outside the package | implement `fontMetrics(_:)`, `resolveFont(_:)` and the `options:` overloads | `TE-C` |
| the same conformer, `TextFontMetrics` | the initialiser gained a defaulted `capHeight: Double? = nil` (record 203), so a conformer still compiles; pass the face's cap height (`CTFontGetCapHeight`, `OS/2.sCapHeight`) so a text above a rect gets the SwiftUI gap, or leave `nil` and that gap equals the rect-above-text one | `DS-F` |
| a `PlatformWindow` conformer outside the package | implement `onAccessibilityRequest`, `publishAccessibilityTree(_:)`, `controlActiveState`/`onControlActiveStateChange`, `accessibilityReduceMotion`/`onAccessibilityReduceMotionChange`, and, since drag and drop, `beginExternalDrag(_:at:)` (answer `false` where the platform has no outgoing drag) — none has a default | `AB-R`, `EV-AB`, `AN-AD`, `DN-C` |
| a `PlatformWindow` conformer outside the package (again, C27) | add `var accessibilityReduceTransparency: Bool { get }` (answer `false` where the platform has no query, as SDL does) and `var onAccessibilityReduceTransparencyChange: ((Bool) -> Void)? { get set }` (call it with the new value when the setting changes); neither has a default. `EnvironmentValues.accessibilityReduceTransparency` is then stamped from it and every `Material` draws an opaque grey instead of a blur while it is `true`. A test using `MetalUITesting` opens a window with `HeadlessPlatformWindow.Options(accessibilityReduceTransparency:)` or calls `TestWindow.setReduceTransparency(_:)` | `MT-D`, `MT-E`, `MT-F`, `MT-G` |
| an exhaustive `switch` over `PrimitiveKind` | add a `.surface` arm (an app-owned GPU surface's quad, drawn by the image pipeline over its render target) | `MV-C` item 3 |
| an exhaustive `switch` over `PrimitiveKind` (again) | add a `.backdrop` arm (a material's blurred backdrop plus its tint, one `MUIBackdrop` record in `Scene.backdrops`); a **renderer** outside the package must draw it or fall back to the flat tint rect `c · o · T` (`BB-I`) — `Scene.backdropRegion(_:target:)` is the one region function | `BB-A`, `BB-L` |
| an exhaustive `switch` over `LayoutModifier` (again) | add a `.backgroundMaterial(Material)` arm (or `default:`): a material behind the content, one layer, painted as a backdrop record | `BB-P` |
| an exhaustive `switch` over `LayoutModifier` (once more, Liquid Glass) | add a `.glassEffect(Glass, any Shape)` arm (or `default:`): a glass behind the content, one layer, painted as a backdrop record with a glass tail through `Frame.fillGlass` (or registered with the enclosing `GlassEffectContainer`) | `LG-A`, `LG-I` |
| `MUIBackdrop` (`MetalUIShaderTypes`) readers and a **renderer** outside the package | the record is **256 bytes** (was 96): the nine original fields did not move, a glass tail follows (`glassFlags`, `lensDepth`, `band`, `rimStrength`, `blendK`, `press`, `pressLift`, `glassReserved`, `member0`…`member3`). `MUIBackdrop(bounds:contentMask:maskCornerRadii:cornerRadii:tint:order:shape:sigma:opacity:)` still builds a material (tail zero, `glassFlags == 0` takes the material arithmetic). A renderer that cannot blur draws `MUIBackdrop.flatTintRects` (one flat rect per blob member) in place of `flatTintRect` | `LG-B`, `LG-L`, `LG-S` |
| `ReplayFixture` readers (the `Backends/SDL` library product) | `ReplayFixture.version` is **5** (`backdropStride` 256); version 4's 96-byte records widen with a zero tail on decode, so a v4 fixture replays as materials | `LG-O`, `LG-T` |
| a `ButtonStyle` shown in an exhaustive `switch` over its (internal) kind | none outside the package: `.glass` and `.glassProminent` join `.plain`/`.borderless`/`.bordered`/`.automatic` (since `BY-A` as `GlassButtonStyle`/`GlassProminentButtonStyle`) | `LG-M` |
| `ReplayFixture` (the `Backends/SDL` library product) readers and exhaustive `switch`es over `FixtureRun.Kind` | add a `.backdrop` arm (`rawValue` 3); `ReplayFixture.version` is **4** (a seventh stride, `backdropStride` 96, and a backdrop byte table after the transforms); versions 2 and 3 still load without backdrops, 1 stays refused; fixtures recorded at version 4 do not load in an older reader. `FixtureRun(scene:)` records a `.backdrop` run and still traps on `.surface` | `BB-J`, `BB-T` item 6 |
| a `WindowRenderer` conformer outside the package | no new requirement. A renderer that cannot blur draws each `.backdrop` run's records as `MUIBackdrop.flatTintRect` (the flat tint `c · o · T`, today's pixels); one that does follows `BackdropBlurReference` within three levels and `Scene.backdropRegion(_:target:)` | `BB-I`, `BB-S`, `BB-T` |
| a `WindowRenderer` conformer outside the package implementing `finishFrame(scene:atlas:)` | implement `finishFrame(scene:atlas:surfaces:)` (no default); a renderer with no surface support may ignore `surfaces` and composites nothing for surface runs. **Callers** of `finishFrame(scene:atlas:)` compile unchanged (it forwards `surfaces: []`) | `MV-F` item 1, `MV-K` item 3 |
| a `Platform` conformer outside the package | implement `setApplicationIcon(_ images: [ImageTexture])` (an empty body is honest where the platform has no runtime icon) — no default | `AI-B` |
| code that names the type `ButtonStyle` (`let styles: [ButtonStyle] = [.plain, .bordered]`, `func f(_ s: ButtonStyle)`) | `ButtonStyle` is SwiftUI's protocol now and the built-ins are `PrimitiveButtonStyle`s: write `[any PrimitiveButtonStyle]` or a generic `S: PrimitiveButtonStyle`; every `.buttonStyle(.plain)` call site compiles unchanged. `.buttonStyle` written after a wrapper now compiles (an environment write) | `BY-A` |
| `PasteButton.buttonStyle(_:)` taking the closed `ButtonStyle` | it takes a `PrimitiveButtonStyle` or a `ButtonStyle` | `BY-A` |
| an exhaustive `switch` over `LayoutModifier` | add `.rotationEffect`, `.scaleEffect`, `.offset` and `.shadow` arms (or `default:`) — paths, shadows and transforms | `GX-H`, `GX-J` |
| a `Platform` conformer outside the package with `func setMenuBar(_: PlatformMenuBar) {}` | `func setMenuBar(_: PlatformMenuBar) -> Bool { false }` — `false` when the platform shows no bar itself (MetalUI then draws one in every window of an app declaring `commands`), `true` when it does; still no default, and the `Void` spelling no longer conforms | `SG-A` item 1 |
| an exhaustive `switch` over `ColorToken` | add a `.shadow` arm (black at 0.33 in both themes). A custom `Theme(background:…scrim:)` compiles unchanged: `shadow:` is a trailing defaulted parameter | `GX-J`, `GX-Q` |
| `MUIGlyph(… _reserved: 0)` (the C struct's memberwise initialiser) | `transform: 0` — the word is renamed, still 0 for an untransformed glyph; the bridging `MUIGlyph(bounds:slot:contentMask:…)` initialiser is unchanged | `GX-F` |
| a `PlatformWindow` conformer outside the package (menus) | implement `presentMenu(_:at:) -> Bool` (answer `false` where the platform has no menu API; `Window` then draws the menu) — no default | `MN-C` item 1 |
| an exhaustive `switch` over `InputEvent` | add `.rightMouseDown`, `.rightMouseUp` and `.menuAction` arms (or `default:`) | `MN-B` item 1, `MN-C` item 4 |
| a `Platform` conformer outside the package (menus) | implement `setMenuBar(_ menuBar: PlatformMenuBar)` — no default; **since `SG-A` it answers `Bool`** (see the row above: `false` where the platform shows no bar, so MetalUI draws one) | `MN-I` item 3, `SG-A` item 1 |
| an exhaustive `switch` over `AccessibilityRole` or `AccessibilityRequest` | add `.menu`, `.menuItem`, `.menuItemCheckBox`, `.menuButton`, `.popover` and `.showMenu(_:)` arms (or `default:`) | `MN-R` |
| a stored colour property read **as a `ColorToken`** — `Decoration.background`/`hoverBackground`/`focusBackground`, `BorderStyle.color`, `Background.color`, `Rectangle.color`, `Text`/`ProposalText`/`TextField`/`TextEditor.foregroundColor`, `OnTapModifier.hoverColor` are now `Color`/`Color?` | a write (`x.background = .surface`) and a comparison (`rect.color == .accent`) compile unchanged; a `switch` or `theme[x]` over the value becomes `pass.resolve(x)` in paint, or a comparison against `Color(.token)` | `CR-E` item 3 |
| `LayoutModifier.background`, `.border`, `.shadow` payloads as `ColorToken` | they are `Color`: a leading-dot construction (`.background(.accent)`) compiles unchanged; a `ColorToken` variable in a payload becomes `Color(token)`, and a pattern that uses the bound payload as a token reads it with `pass.resolve(_:)` | `CR-W` item 1 |
| a `PlatformWindow` conformer outside the package (colour scheme) | implement `func setPreferredColorScheme(_ colorScheme: ColorScheme?)` — an empty body, or recording the value, is honest where the platform has no per-window appearance; no default | `CR-M`, `CR-Y` item 6 |
| a `PlatformWindow` conformer outside the package (platform services) | implement `func presentFileDialog(_: PlatformFileDialog) -> Bool { false }`, `func presentAlert(_: PlatformAlert) -> Bool { false }`, `func dismissPresentation(token: Int) {}` and `func setContentSizeLimits(minimum: Size<Pixels>?, maximum: Size<Pixels>?) {}` — each honest where the platform has no dialog, draws alerts in the window, or cannot limit a window; no default (answering `false` makes a file dialog complete with `FileDialogError.unavailable` and an alert draw in the window) | `SV-B` items 1, 5 |
| an exhaustive `switch` over `InputEvent` (platform services) | add `.pointerExited`, `.fileDialogResult(_:)` and `.alertResult(_:)` arms (or `default:`) | `SV-B` item 2 |
| a `PlatformWindow` conformer outside the package (toolbar) | implement `func setToolbar(_: PlatformToolbar?) -> Bool { false }` — honest where the platform has no native toolbar: `Window` then draws the toolbar in the window; answer `true` only if the platform shows it and delivers each control's outcome as `.toolbarAction`; no default | `MD-J` items 2, 5 |
| an exhaustive `switch` over `InputEvent` (toolbar) | add a `.toolbarAction(_:)` arm (or `default:`) | `MD-J` item 6 |
| an exhaustive `switch` over `InputEvent` (input APIs) | add `.rightMouseDragged`, `.otherMouseDown`, `.otherMouseDragged`, `.otherMouseUp`, `.magnify` and `.rotate` arms (or `default:`) | `CI-E` item 5, `CI-J` item 1 |
| a `PlatformWindow` conformer outside the package (input APIs) | implement `func setPointerStyle(_ style: PlatformPointerStyle) {}` — an empty body is honest where the platform cannot change the pointer; no default | `CI-J` item 2 |
| a `PlatformWindow` conformer outside the package (text links) | implement `func openURL(_ url: String) -> Bool` — open the absolute URL with the platform's handler and answer whether the request was made (AppKit `NSWorkspace.shared.open`, SDL `SDL_OpenURL`); `{ false }` is honest where there is no handler; refuse a string with no scheme first, as both in-package conformers do; no default | `LI-D` |
| a `PlatformWindow` conformer outside the package (drop delegates) | implement `func setDropOperation(_ operation: PlatformDropOperation) {}` — it tells the platform what a drag over the window would do (`.none`, `.copy`, `.move`); an empty body is honest where the platform has no drag feedback (SDL); no default | `DE-H` |
| an exhaustive `switch` over `PlatformPointerStyle` (image cursors) | add a `case .image(let image):` arm (or `default:`): `image` is a `PlatformCursorImage` (premultiplied `texture`, `scale`, hot spot in points from the top-left, `pointWidth`/`pointHeight`); a platform that cannot draw it leaves the current cursor. `PlatformWindow` gains no requirement. This is the case `CI-AC` foretold | `IC-A`, `IC-C` item 3 |
| an exhaustive `switch` over `PlatformPointerStyle` (pointer extras) | add three arms (or keep `default:`): `.columnResizeOneWay(towardTrailing:)` and `.rowResizeOneWay(towardDown:)` (the left-right / up-down resize with one arrow; the two-way cursor is an honest fallback) and `.hidden` (draw no pointer; a platform that ignores it leaves the pointer visible, and shows it again on the next style it is sent). `PlatformWindow` gains **no** requirement: `hidden` is a style, and `Window` sends one `.arrow` when the pointer leaves the window while hidden | `PH-D`, `PH-G` |
| a `PlatformWindow` conformer outside the package (app shell) | implement the seven new requirements — `var onCloseRequest: (() -> Bool)?` (ask it before a user's close; `nil` or `true` closes), `func close()` (close without asking, then fire `onClose` exactly once), `func setDocumentEdited(_: Bool) {}`, `func setRepresentedFilePath(_: String?) {}`, `func setTitleBarStyle(_: PlatformTitleBarStyle) -> Bool { false }`, `var titleBarInsets: Edges<Pixels> { Edges(all: Pixels(0)) }` and `func performTitleBarPress(clickCount: Int) -> Bool { false }` — the empty bodies and `false` answers are honest where the platform has no edited marker, represented file, hidden title bar or title-bar drag; no defaults | `AS-H`, `AS-J` |
| a `PlatformWindow` conformer outside the package (title-bar metrics) | implement `func setTitleBarMetrics(height: Float?, controlsLeading: Float?) -> Bool { false }` — the app's band height and window-button inset under the hidden title bar; `false` is honest where the platform cannot place its buttons (the system band stays); no default. `HeadlessPlatformWindow.Options` gains `appliesTitleBarMetrics` | `AS-R` |
| a `Platform` conformer outside the package (app shell) | implement the four new requirements — `var onTerminateRequest: (() -> CloseRequestReply)?` (ask it before ending the application on the platform's own quit; `nil` answers `.now`), `func replyToTerminateRequest(_: Bool)` (end on `true` if a `.later` is pending, else nothing), `func terminate()` (end, asking nobody) and `var onOpenURLs: (([String]) -> Void)?` (call it with the absolute URL strings the system asks to open, parking them until it is set) — no defaults | `AS-H` |
| a `PlatformWindow` conformer outside the package (window drag) | implement `func performWindowDrag() -> Bool { false }` — honest where the platform cannot move the window from a press (SDL: its system title bar drags itself); AppKit answers `true` only while dispatching the mouse-dragged of a held press; no default | `WD-E` |
| a `PlatformWindow` conformer outside the package (subtitle, dismiss) | implement `func setSubtitle(_ subtitle: String) {}` and `func setDismissEnabled(_ enabled: Bool) {}` — AppKit sets `NSWindow.subtitle` and adds or removes `.closable`; a platform without either records the call and shows nothing (`Window` already refuses the user's close while dismissing is disabled); no default | `AE-D` |
| a `PlatformWindow` conformer outside the package (window chrome, SDL custom chrome) | implement the four new requirements, AppKit's answers when the platform draws no chrome of its own — `func setWindowDragRegions(_ regions: [Bounds<Pixels>]) -> Bool { false }` (`true` only if the platform makes a press inside the rects move the window before the app sees it, the rects being disjoint, in window points, at most 64), `func performWindowAction(_ action: PlatformWindowAction) -> Bool { false }` (`.minimize`, `.toggleZoom`), `var hasNativeWindowControls: Bool { true }` (`false` makes `Window` draw close, minimise and zoom buttons under `.hiddenTitleBar`) and `var isZoomed: Bool { false }`; no default for any. A conformer that applies the hidden style (`setTitleBarStyle` answering `true`) on a platform with no window buttons also answers `titleBarInsets` with the band and the cluster's edge. `HeadlessPlatform.Options` gains `usesWindowDragRegions`, `hasNativeWindowControls`, `isZoomed`, `hiddenTitleBarInsets` and the preset `.sdlChrome` | `CW-F`, `CW-D` |
| a `PlatformWindow` conformer outside the package (window activation) | implement `func orderFrontAndMakeKey() {}` (bring the window in front, key, restoring it if minimised; an empty body is honest where the platform cannot) — no default | `WA-A` |
| a `Platform` conformer outside the package (application activation) | implement `func activate() {}` (bring the application to the foreground; an empty body is honest where the platform cannot) — no default | `WA-A` |
| a `PlatformWindow` conformer outside the package (accessibility display settings) | add `var accessibilityDisplaySettings: AccessibilityDisplaySettings { AccessibilityDisplaySettings() }` (answer the standard values where the platform has no query, as SDL does; `AccessibilityDisplaySettings` is in `MetalUICore`, and a platform that has no Auto-Play Animated Images setting answers `playAnimatedImages: true`) and `var onAccessibilityDisplaySettingsChange: ((AccessibilityDisplaySettings) -> Void)?` (call it with the new settings when any changes); neither has a default. `EnvironmentValues.colorSchemeContrast` and its five siblings are then stamped from it. A test using `MetalUITesting` opens a window with `HeadlessPlatformWindow.Options(accessibilityDisplaySettings:)` or calls `TestWindow.setAccessibilityDisplaySettings(_:)` | `AD-C`, `AD-L` |
| an exhaustive `switch` over `AccessibilityRole` (platform services) | add `.popUpButton` and `.alert` arms (or `default:`) | `SV-S` |
| an exhaustive `switch` over `AccessibilityRole` (controls and looks) | add `.progressIndicator`, `.busyIndicator` and `.colorWell` arms (or `default:`); a bridge outside the package maps them (AppKit `.progressIndicator`/`.colorWell`, AccessKit `PROGRESS_INDICATOR` — a busy one without a numeric value — and `COLOR_WELL`) | `LK-G` |
| an exhaustive `switch` over `LayoutModifier` (controls and looks) | add a `.blur(radius:)` arm (or `default:`) | `LK-R` item 3 |
| an exhaustive `switch` over `LayoutModifier` (shadow cache) | add a `.compositingGroup` arm (or `default:`) | `PF-E` item 4 |
| an exhaustive `switch` over `LayoutModifier` (3D render effects) | add `.rotation3DEffect` and `.projectionEffect` arms (or `default:`) | `PJ-H` |
| `Slider.init` as a function reference (`Slider.init(value:in:)` passed unapplied) | both initialisers gained a defaulted `onEditingChanged:` parameter, so the unapplied reference has a different type: annotate it or call it | `LK-B`, `LK-U` |
| a `TextSystem` conformer outside the package (rich text) | implement `measure(_: StyledText, wrappingAt:options:) -> StyledTextMeasurement`, `layOut(_: StyledText, wrappingAt:options:origin:scaleFactor:) -> StyledTextLayout` and `decorationMetrics(_: FontKey) -> TextDecorationMetrics` — no defaults; a one-run `StyledText` must answer what the plain calls answer | `RT-F` item 2 |
| `Text.init` / `ProposalText.init` as a function reference (`strings.map(Text.init)`) | annotate the type: `strings.map { Text($0) }` or `map(Text.init as (String) -> Text)` — `Text(_ string: String)` is now SwiftUI's three, `init(_ key: LocalizedStringKey)`, the disfavoured `init<S: StringProtocol>(_:)` and `init(verbatim:)` | `RT-C` item 2 |
| `Text("…\(image)")` interpolating an `Image` | it compiled, writing the image's description; now it warns (deprecated, "not offered") and **traps**: interpolate a `Text`, or lay the `Image` beside the text | `RT-T` item 1 |
| `.borderWidth(_:)` | `.border(_:width:)` | `OM-M` |
| `width(percent:)`/`height(percent:)` taking a fraction | `.frame` (they were renamed `fraction:` then deprecated) | `CN-O`, `CX-C` |
| `.focusable()` (no arguments, on a `StyledElement`) | compiles unchanged: it is `focusable(_ isFocusable: Bool = true)`'s default; a function reference to `focusable` now names a one-argument function | `KF-F` item 2 |
| proposal content with no keyboard modifiers (`MetalView`, `GPUSurface`, `HStack`, …) | it gains `onKeyPress`, `focusable(_:)`, `focusable(_:interactions:)`, `keyContext(_:_:)`, `focused(_:)`, `focused(_:equals:)` and `hoverKeyRegion(_:)`, each returning `KeyboardModifier<Self>` — a type annotation that named the content's own type after one of them names `KeyboardModifier<…>` | `KF-H` |
| a `for` loop over a helper returning `some …` in a builder (never compiled) | `ForEach(items, id: \.self) { helper($0) }`, a helper returning a concrete type, or the chain inline — a Swift 6.4 builder defect, not a MetalUI API | `KF-M` |

### Deprecated, still working (source, a warning)

| deprecated | use | ruling |
|---|---|---|
| `width`/`height`/`minWidth`/`minHeight`/`maxWidth`/`maxHeight`, `width/height(fraction:)`, `…(percent:)` | `.frame` (recipe above) | `FR-I`, `LR-ER`, `CX-C` |
| `flexBasis(fraction:)`, `flexBasis(percent:)` | a length, or `.frame` | `CX-C` item 2 |
| `.frame()` with no arguments | delete it (a no-op) | `FR-J` |
| `NativeRow`, `NativeColumn`, `NativeOverlay`, `NativeFrame`, `NativePadding`, `NativeBackground`, `NativeFixedSize`, `NativeSpacer`, `NativeRectangle`, `NativeColorFill`, `NativeLayoutModifier`, `NativeModifiedContent`, `NativeOverlayModifier`, `NativeTappable`, `NativeMeasureFunction`, `NativeStackAxis`, `NativeAlignment`; `.nativePadding` … `.nativeOnTap` | the un-prefixed names (`nativeFrame` stays undeprecated, `SA-K`) | `CX-C` item 1 |
| `HStack`/`VStack(spacing:alignment:content:)` | `init(alignment:spacing:content:)` with a typed alignment | `CN-I` |
| `Rectangle(color:)` | `Rectangle().fill(token)` | `TE-AC` |
| `AXNode.actions`, `AXActionKind`, `AXNode(…actions:…)` | `.accessibilityAction(_:)`, `.accessibilityAdjustableAction(_:)` | `IX-Y` item 4 |
| `Color.color` (the `ColorToken` a `Color` view held; now `ColorToken?`, `nil` for a literal) | compare the `Color` (`c == .surface`), or resolve it with `PaintPass.resolve(_:)` | `CR-E`, `CR-D` |
| `Text + Text` | string interpolation: `Text("Total: \(Text("12").bold())")` — SwiftUI's own deprecation and message; an operand carrying a style, decoration, id or handler traps (divergence 155) | `RT-E` item 1 |

### Behaviour changes (compile unchanged, answer differently)

| change | what to do | ruling |
|---|---|---|
| **The layout engine is SwiftUI's** (stage 6b, stage 9): every element lowers onto the propose/measure/place kernel; a root is centred at its own answer | nothing; layouts that relied on CSS shrink weights, percentage sizes or the CSS root rule now answer as SwiftUI (or trap by name where no answer exists) | `LR-DF`, `LR-FC`, `CN-J`, `LR-FO` |
| an `if` with no `else` and a `for` loop each take **one structural slot**; a vanishing `if`'s trailing sibling keeps its own state | code that built a `GlobalElementID` through an `if`/`for` by hand adds the slot level | `ID-B` |
| content an evaluated conditional removes is **reset on return** (state, scroll, selection, `$anim`) | keep values that must survive in data or above the `if` | `ID-C` |
| a `ForEach` whose ids print alike but differ in value (a custom `Hashable` id whose `description` collides, an `AnyHashable(1)` beside `AnyHashable("1")`) now produces **every** such element, each with its own `@State`; before, only the first was produced | nothing; remove any workaround that made ids print distinctly. Equal values are still one element (the later is dropped, as before). A `List` over such ids still aliases them (divergence 255) | `FI-A`, `FI-B`, record §95 |
| a `for`/`ForEach` element that disappears and returns starts fresh | as above | `DD-C` item 4 |
| a name an evaluated position leaves starts fresh when it returns | as above | `ID-R` |
| **focus leaves with its identity and does not come back** | refocus on return from input (`Window.focus(id)`) or by writing the `@FocusState` | `IX-I` |
| a hidden element is out of the keyboard's focus half (a hidden `Button`'s shortcut still fires) | — | `IX-K` item 3 |
| the wheel over a click target inside a scroll view **scrolls the scroll view** | — | `DD-Y` |
| a `List` windows against its own origin: a header above it no longer blanks it | the "only child of its scroller" requirement is gone | `DD-F` |
| **on Linux and Windows a shortcut written without modifiers fires on Ctrl, not Super**: the default of `KeyboardShortcut(_:modifiers:)` and `.keyboardShortcut(_:modifiers:)`, and the standard menu items' shortcuts, is `EventModifiers.primary` — ⌘ on Apple (nothing moves on macOS), Ctrl elsewhere; an explicit `.command` is still the Super/Windows key; the drawn menu names each key ("Ctrl+S", "Super+S" / "Win+S") | write `.command` to keep a Super binding; a portable app's own "primary modifier" constant can become `.primary` or go | `SG-B` items 3–5 |
| **on SDL (Linux, Windows) an app that declares `commands` draws a menu bar** in every window: a 25-point strip across the top, above a drawn toolbar strip, the root laid out below both (divergence 195); a title opens its menu on a click, F10 the first menu; Edit's items reach a focused text field as their keys | drop a workaround toolbar mirroring the menus; an app wanting no bar there declares its `commands` under `#if os(macOS)` | `SG-A` |
| **on SDL an explicit `Window.minSize`/`maxSize` is the content's below the drawn chrome**: the platform receives the height plus `Window.drawnChromeHeight` (the menu bar's 25 and the toolbar strip's 39), as AppKit's `contentMinSize` excludes its toolbar; an infinite maximum stays unbounded | remove a `+ 39` (or `+ 64`) added to a minimum for the drawn strip | `SG-F` items 1–3 |
| **a cross-platform `Package.swift` that conditions `MetalUIPortableText`/`MetalUISystemFonts` on `.linux`/`.windows`** fails `swift build --build-tests` on macOS with the default build system (`unable to resolve module dependency: 'CFreeType'`, a SwiftPM defect, MG-26): `metalui new --cross-platform` and `docs/getting-started.md` now name both products unconditionally (`MetalUISDL` keeps its condition) | drop the `condition:` on those two products; a macOS release build grows by about 2.15 MB | `SG-D` |
| a `Component` whose content is a loop nested in another `Component`'s content (also in an `if`/`else` or `switch` branch) crashed a Windows release build on 6.4.0+Asserts (MG-27, `LK-X`) | nothing: a `Component`'s prepaint record is one heap box, so it compiles; code with its own protocols of that shape still takes `LK-X`'s function remedy (`docs/packaging.md`) | `SG-E` |
| `controlSize` reaches every text's default font and `Button`'s chrome | an explicit `.font` is unaffected | `TE-F`, `DD-R` |
| a whole-value `Window.environment` write resets `displayScale` to 1 (`pixelLength` follows) | — | `EV-AA` |
| the legacy paint-only fields (opacity, border widths and colour) and every proposal `LayoutModifier` **animate** under a transaction | wrap in `withTransaction(Transaction(animation: nil))` or `.transaction { $0.animation = nil }` to snap | `AN-AA`, `AN-AB` |
| a `Component`'s caller modifier animates per member | — | `AN-AC` |
| a press under `allowsHitTesting(false)` is advertised to and run by an accessibility client | — | `IX-Z` |
| **an optional `@State` with a non-`nil` default reads it before its first write** (it read `nil`); the public `withState(_:initial:_:)` over an optional likewise returns `initial` for an absent entry | workarounds that wrote the value first are unaffected | `CX-F`, `CX-Q` item 1 |
| a legacy frame's `idealWidth`/`idealHeight` answer an unspecified axis (they trapped) | — | stage 9, `CX-R` |
| **on AppKit a control-click is a secondary press** (`MetalHostView`, lane 2): it no longer presses a `Button` or runs an `onClick`, tap or drag — it opens a context menu, or does nothing (SwiftUI's right click presses a `Button`, divergence 110). Off Apple a ctrl-click stays a primary press (`List`'s toggle) | bind the action to a context menu item, or test the primary press's modifiers | `MN-AC` item 1, `MN-B` item 4 |
| **an AppKit app has a menu bar** — every `App` installs `NSApp.mainMenu` (About, Hide, Quit; File ▸ Close; Edit; Window), so ⌘Q, ⌘H, ⌥⌘H, ⌘W and ⌘M act when nothing in the window claims them, and Edit ▸ Cut/Copy/Paste/Undo reach a focused `TextField`/`TextEditor` as their keys. On SDL every window of an app declaring `commands` draws the bar itself, 25 points across its top (divergence 195, `SG-A`) | bind the key in the window (a `Button`'s `.keyboardShortcut`, a keymap binding or `onKey` still wins, `MN-J`), or replace a group with `App.commands { CommandGroup(replacing:) { } }` | `MN-I` item 4, `MN-K` |
| **AppKit ⌘-keys arrive through `performKeyEquivalent`** — offered to the window before the main menu, once per event — and reach the same `onInput` pipeline as before | nothing; a ⌘-key is still one `.keyDown` | `MN-J` item 3 |
| **a key an app command binds is claimed by the command stage** (after a `Button`'s shortcut, before Tab traversal): it no longer reaches Tab traversal or the window's `onInput` fallback | bind it in the window to keep it there | `MN-J` item 1 |
| **`Appearance` is `ColorScheme`** (a typealias, not deprecated): `PlatformWindow.appearance`, `Theme.forAppearance(_:)` and every `Appearance` spelling compile unchanged | write `ColorScheme` in new code | `CR-J` item 1 |
| **the window's theme follows its colour scheme through `lightTheme`/`darkTheme`** (defaults `.light`/`.dark`, so an uncustomised window paints as before); a forced `.preferredColorScheme` now also selects the variant | customise `window.lightTheme`/`darkTheme` (or `App`'s) instead of re-assigning `theme` on an appearance change; a direct `window.theme = …` still lasts until the next scheme change | `CR-K`, `CR-Z` item 2 |
| `.opacity(0.5)` written on a `Color` **view** with a literal argument is the value method: one fill at half alpha and **no opacity layer** (it was an opacity layer, one identity level) | nothing — a `Color` holds no state; pass a `Float` to reach the view modifier | `CR-G` |
| design spec §7.9's "never literals" is superseded: literal colours are part of the API | — | `CR-B` |
| a `Shape` conformer that implements **neither** `geometry(in:)` nor `path(in:)` compiles (both are now defaulted, each in terms of the other) and **traps at its first paint naming `GX-D`** — where it failed to compile | implement either; SwiftUI shapes port by writing `path(in:)` (its rect is local, origin (0, 0)) | `GX-D` |
| **⌘↩ (⌃↩ off macOS) in a focused `TextEditor` no longer inserts a line break**: it passes on to `onKey`, a `Button`'s `.keyboardShortcut(.return, modifiers: .command)`, the app's commands and `onInput`; plain Return, ⇧↩ and ⌥↩ still break the line, a `TextField`'s Return still submits. The commit spelling is `.onKeyPress(keys: [.return]) { press in press.modifiers.contains(commitModifier) ? commit() : .ignored }` on the editor, where `commitModifier` is `.command` on macOS and `.control` on Linux and Windows (`#if os(macOS)` in the app; MetalUI exposes no constant) — testing `.command` alone never commits off macOS | to keep a line break on ⌘↩, bind it with `onKeyPress` and insert the break yourself | `KF-Z` item 2 |
| **`.focusable(interactions: .edit)` focuses on a primary press** (SwiftUI's FC3); a plain `.focusable()` did not (divergence 94, narrowed) and now does, see the next row | spell a canvas or viewport that should take focus on a click `.focusable(interactions: .edit)` | `KF-F` |
| **a `.focusable()` box takes focus on a primary press** (`.focusable(_:)` records `.automatic`, SwiftUI's FC1; divergence 94 retired): it registers one non-opaque press region (the hitbox count of a tree of focusables rises by one each, nothing else's hit testing moves), a press on it clears a focused `TextField` and, in a `.hoverKeyRegion()`, focuses instead of clearing, and an `onKey` on it hears keys after a click. `Button`, `Toggle`, `Slider`, `Stepper` and `Picker` still take no click focus | a box that must not take focus on a click: `.focusable(interactions: .activate)` | `FC-A` |
| **the first `.focusable()` (or `.edit` focusable) of a window is focused when the window first draws** (SwiftUI's hosting view; divergence 186 narrowed): not a `TextField`, not a control, not `.activate`, not a `List`'s rows, and nothing after a `List` in tree order (a `ScrollView`'s content is seated, as SwiftUI's); `onKey` and `onKeyPress` on it hear keys at once, a first Tab reaches the second stop, `TestWindow.focusedElement` is set after the first draw, and a `@FocusState` bound to it reads `true` one frame later. A focused `.focusable()` that is removed leaves nothing focused (divergence 217) | a test or app that starts from nothing focused calls `window.focus(nil)` after the first draw (`TestWindow`: `window.window.focus(nil)`); an element that must not take the seat: `.focusable(interactions: .activate)` | `FC-E`, `FC-F`, `FC-G` |
| **a link run in a `Text` is clickable** (Markdown `[a](u)`, a bare URL, `AttributedString.link`; divergence 150 retired): a press and release on the run calls the nearest `\.openURL` action, whose default asks the window's platform to open the URL (`NSWorkspace` on AppKit, `SDL_OpenURL` on SDL), so a window that showed link-styled text before now opens a browser on a click; an accessibility client sees an `AXLink` child under the text; a `Text` with a link adds hitboxes (a click region and a pointing-hand region per piece). `.disabled(true)` makes a link inert, where SwiftUI still opens it (divergence 218) | an app that must not open links installs `.environment(\.openURL, OpenURLAction { _ in .handled })` (or `.discarded`) above the text; a test reads `TestWindow.platformWindow.openedURLs` instead of a browser; a `.equatable()` subtree below an `.environment(\.openURL, _)` is evaluated each frame (the closure is uncomparable) | `LI-A`..`LI-G` |
| **with nothing focused, keys go to the hovered key region** (`.hoverKeyRegion()`), and the `Keymap`'s contexts follow its chain: a binding predicated on a context the region's ancestors contribute fires there, and a `!Panel`-style negation is vetoed while the hovered region sits inside a `Panel` contributor (MetalCreator's viewport `F` over its graph) | bind the key to the region's own context (`"Viewport"`), or contribute `Panel` only on the fields' container | `KF-D`, `KF-E` |
| **a primary press inside a key region clears a focused field's focus** (unless it lands on a text field or a `.edit` focusable inside it); a press anywhere else still changes no focus | — | `KF-E` item 5, `KF-G` |
| **`PaintPass.isHovered` is no longer sticky after the pointer leaves the window**: `.pointerExited` (AppKit's `mouseExited`, SDL's mouse-leave) clears `Window.lastMousePosition`, so the next frame paints nothing hovered (it kept the last in-window position hovered until the next in-window event) | nothing; hover affordances now clear when the pointer leaves | `SV-N` item 7 |
| **a file dialog's or an alert's answer is claimed by the window** (`.fileDialogResult`, `.alertResult` run first after the pointer state and never reach a later stage or the window's `onInput` fallback); `.pointerExited` is claimed by no stage and reaches `onInput` | read outcomes in the modifiers' callbacks or the awaited `FileDialogs` call | `SV-K` item 3 |
| `Handlers` gains a seventeenth member (`hover`, internal): 464 → 472 bytes | nothing | `SV-N` item 1, `SV-AH` |
| **`TextField` and `Slider` answer an infinite proposed width with infinity, `TextEditor` an infinite width or height** (they answered their ideal): SwiftUI's greedy classes (probe `FL3`–`FL6`). A stack serves its least flexible child first, so beside a label a field or slider now takes the rest of the row — in an `HStack` and in a legacy `Row` alike (a `Row { Text("Speed"); Slider(…) }`'s slider was served first and took half). A `nil` proposal still answers the ideal | to keep the old half-row width, give the control a `.frame(width:)` | `PE-D` |
| **SwiftUI-vocabulary containers take legacy content** (`HStack { Button("x") {} }` compiles; it was a compile error): the content builder is `ProposalContentBuilder` | nothing; a container type's `Content` for a legacy child is `LegacyContent<…>` | `PE-B`, `PE-E` |
| a `Component`'s layout record keeps its content and layout in **one heap box** (`ComponentLayout` is 8 bytes): one allocation per `Component` per laid-out frame (+96 bytes), and a shell switching between pane `Component`s no longer costs the sum of the panes' stack | nothing (see [Large trees in a debug build](#large-trees-in-a-debug-build)) | `PE-J` |
| **`Divider` is also an `Element`** (`Divider: Element, ProposalElement`): `Divider()` in an element builder is a 1-point line where it did not compile; in a menu builder it is unchanged | nothing | `SV-O` |
| **`.pickerStyle(.menu)` compiles** — the guard `aMenuPickerStyleIsNotOffered` is replaced by `aMenuPickerStyleCompiles` (`.automatic` stayed segmented until `SR-B`, row below) | nothing for callers | `SV-P` item 1 |
| **A `Picker` with no style is now the pop-up menu** (it was segmented; divergence 81 retired): the title, 8, then a button as wide as the widest option. The published role moves from `radioGroup` with `radioButton` children to `popUpButton`, so per-option identifiers (`SE-A`, `mode.alpha`) are gone and a harness test clicking `.radioButton` fails; arrow keys no longer step (Space and Return open the menu); options are recorded, not laid out, so `@State`, `onAppear` and `.id` inside an option do not run; a non-`Text` option is titled by its tag (128). A toolbar's automatic picker is the pop-up too (probe `TB-A`). MetalFlow (`e9d90ef`) and MetalCreator (`a98ed34`) write `.pickerStyle` on every picker and need no change | write `.pickerStyle(.segmented)` to keep the old look | `SR-B` |
| **A control's string literal title is parsed as inline Markdown** (`Button`, `Toggle`, `Stepper`, `Picker`, `ColorPicker`, `ProgressView`, `Menu`; each has a `LocalizedStringKey` initialiser and a disfavoured `StringProtocol` one, as `Text` does; divergence 154 narrowed): `Button("**b**")` draws a bold `b` and publishes `b`, as SwiftUI does (probe `swiftui-control-titles.swift`). A title containing `*`, `_`, a backtick, `[`, `~`, `\`, `@` or `www.` that was meant literally must be a `String` variable (`Button(name)`) or a `Text(verbatim:)` label. `TextField` placeholders and alert titles are unchanged | nothing for a title without those characters | `SR-C` |
| **The `.switch` toggle's knob slides** (divergence 885 retired): on every change, on a fixed 0.25 s spring that settles by 0.3 s, whatever the transaction; `Transaction.disablesAnimations` snaps it. Under right-to-left layout the knob is now on its track (it was 37 points to the left) | nothing | `SR-D` |
| **A `@State` keeps its default's first evaluation** (divergence 125 retired; `StateTable.mark(_:seeding:)`): the default is evaluated by every build and discarded after the first, so `@State var monitor = Monitor()` starts and stops one instance and `@State var owner = UUID()` is **one UUID for the element's lifetime** (it was re-minted by every build, so a comparison against an owner from an earlier build never matched). **A `@State` seeded from a parameter through `init` or the memberwise initialiser (`_s = State(wrappedValue: v)`; `@State var s: Int` set by the parent) no longer follows the parent**: it holds its first value until it is written, as SwiftUI does (probe `D3`: `s=0` as `v` goes 0, 1, 2). Use the parameter itself, a `Binding`, or an `.onChange(of:)` that writes the state. The `StateTable` now holds one entry per declared `@State` of a live element (it held one per written `@State`), so `sweepThreshold` (256) engages sooner and a `List` row's seed outside its window is reaped after the same two-generation bound as a written value (`TB-AH`). An `AnyElement` whose wrapped type changes at one position keeps the old type's slot, a never-written default included (divergence 210) | write the instance in `onAppear` to defer its construction; none for a parameter-seeded state that must follow | `FV-A`, `FV-B`, `FV-C` |
| **An `AnyElement` whose wrapped type changes is a different element** (divergence 210 retired; `ER-A`): swapping `AnyElement(A)` for `AnyElement(B)` at one position resets state, focus, `.task`, lifecycle keys and memos, fires `onDisappear` for A and `onAppear` for B, and a swap back to A starts fresh; the same wrapped type changes nothing. A hand-built `GlobalElementID` under a group-entered `AnyElement` moves one level (a `$erased` component, keyed by the type; use `AnyElement.contentID(under:)` in this package's tests); an erased element's bounds stay at its position. A toolbar item whose content type changes now resets. A direct `AnyElement.requestLayout(_:pass:)` caller (a custom `Button`/`Toggle` style) still owns its id and gets no level. A legacy decoration returning `Self` is not a type change (211); the swap appears the new content before it disappears the old (212). |
| **The AppKit layer is tagged sRGB, not Display P3** (divergence 1 narrowed; `MetalLayerSurface`): every colour MetalUI draws is a gamma sRGB number, and the compositor now reads it as one, so on a wide-gamut display **every colour is less saturated than before** and matches the same hex in SwiftUI (`#38BDF8` read as P3 was an sRGB colour of about (0, 192, 254); the sRGB reading is (56, 189, 248)). A hand-tuned hex that was nudged to look right on the P3 layer will now look flat: re-take it from the design value. A PNG or JPEG with a Display P3 profile was drawn exactly right by accident and now desaturates like SDL (138). A `MetalView` shader that writes P3-tuned values desaturates; one that writes gamma sRGB becomes right. A window capture or screenshot taken before this change differs on a P3 panel (human check `A1`). Linux and Windows are unchanged (their swapchain was already sRGB) | nothing to change in code; re-check hand-tuned colours by eye | `LS-A` |
| **`TextField` draws SwiftUI's bordered field and is 24 points tall** (at 13 pt; 8 taller and 12 wider at its ideal than before): a `.surface` fill, a `.separator` border, radius 6, the control focus ring while focused, the text inset 6/4 and dimmed to a third when disabled. **`TextEditor` draws an opaque `.surface` background** (size and text placement unchanged) | `.textFieldStyle(.plain)` (on the field or a container) restores the previous field exactly; `.textEditorStyle(.plain)` the previous editor; drop an app-side field-chrome helper | `MD-C`, `MD-F` |
| a linear container outside the package that should orient a `Divider` | not possible from outside (the stack-axis stack is internal); a `Divider` in it is horizontal, as outside any stack | `SV-O` item 2 |
| an in-window (SDL) menu taller than the window less 8 points **scrolls**: clamped to the window, wheel and ↑/↓ scroll it, only visible rows paint and hit-test | nothing | `SV-Q` |
| an alert the platform declines (SDL) is **drawn in the window and modal**: while it is up, pointer, wheel and key events reach nothing beneath, and an open drawn menu closes | nothing; answer it with its buttons, Return/Escape or an accessibility press | `SV-J` items 2–4 |
| **`ImageBitmap(contentsOfFile:)` decodes PNG and JPEG with MetalUI's own decoder on macOS too** (it used ImageIO): a colour-tagged file (`iCCP`, `gAMA`, `cHRM`) is no longer converted — its samples are drawn as sRGB (divergence 138); a truncated or corrupt PNG (a bad CRC on any chunk, a missing `IEND`) and a JPEG with no end marker are `nil` where ImageIO returned a partial image; a JPEG's bytes may move by up to 2 per channel. Other formats (GIF, TIFF, HEIC, …) still go through ImageIO on macOS and are `nil` on Linux/Windows. The initialiser now exists on every platform, beside `init?(data:)` and `init?(resource:withExtension:subdirectory:bundle:)` | convert colour-tagged assets to untagged sRGB PNGs; a hand-written bundle-image cache can become `ImageBitmap(resource:…bundle:)` | `PX-C`, `PX-D`, `PX-E` |
| **`DecodedImage`, `Image.Orientation` and `ImageBitmap.oriented(_:)` are new names; `Image` gains two `orientation:` initialisers** (no default for `orientation`, so every existing `Image(decorative:scale:)` call still resolves to the old init): a third-party `extension Image { enum Orientation }` or a `DecodedImage` of your own now collides. A bitmap from a file tagged with an EXIF orientation still draws its stored pixels, where SwiftUI's `Image(nsImage:)` of the same file draws upright (divergence 435) | read the tag with `DecodedImage` and draw through `Image(_:scale:orientation:label:)`, or call `applyingOrientation()` before `ImageBitmap(_:)`; delete a vendored second copy of stb_image or an EXIF parser | `IB-A`, `IB-F`, `IB-G`, `IB-K` |
| **`ImageInfo` and `DecodedImage.Limits` are new names; `DecodedImage` gains two `limits:` initialisers and one new refusal**: a third-party `ImageInfo` or `DecodedImage.Limits` of your own now collides. `DecodedImage(data:)` and `DecodedImage(contentsOfFile:)` return `nil` when the decoder's size disagrees with the header's (an image the two parsers read differently; none of the repository's fixtures does) | read `ImageInfo` first and apply your own bound, or pass `limits:` and delete a hand-written PNG/JPEG header reader that existed only to bound a decode | `IH-A`, `IH-I`, `IH-J` |
| **`ImageFileFormat` and `ImageInfo.sniffedFormat(of:)`/`(ofFile:)` are new names** (additive, no requirement added): a third-party type called `ImageFileFormat` of your own now collides. The enum is not frozen, so an exhaustive `switch` over it needs a `default` for later cases; `ImageInfo.Format` is unchanged (`png`, `jpeg`) | delete a hand-written table of GIF/TIFF/BMP/WebP/HEIF signature prefixes (MetalCreator's `OtherPictureSignature`): sniff first, then `ImageInfo`: `.png`/`.jpeg` with a `nil` `ImageInfo` is damaged, another case is an unsupported type, `.unknown` is not a picture | `IS-A`, `IS-C`, `IS-D` |
| **`SDLPlatform.Options` gains a last parameter `applicationID: String? = nil`** (source-compatible: every existing `Options(...)` call compiles): an app that called `SDL_SetHint(SDL_HINT_APP_ID, …)` itself before `SDLPlatform` init still works (the code's hint is set at normal priority, and one you set earlier at the same priority is replaced only when `applicationID` is non-nil); an app that launches through `launchingSingleInstance(id:)` now also sets that `id` as the window's application id on Linux | pass `applicationID:` to override the single-instance id, or delete your own `SDL_SetHint(SDL_HINT_APP_ID, …)`; an exported `SDL_APP_ID` still wins | `AP-A`…`AP-D` |
| **a control-drag on AppKit is a secondary drag**: between a control-press (`.rightMouseDown`, `MN-AC` item 1) and its release, motion arrives as `.rightMouseDragged` (it was dropped); on SDL, motion with the right button held is `.rightMouseDragged` (it was `.mouseMoved`), with the middle or an extra button `.otherMouseDragged`, and those buttons' presses `.otherMouseDown`/`.otherMouseUp` (they were dropped) | a platform `onInput` that read right-held motion as a move handles `.rightMouseDragged` | `CI-E` items 3 and 4, `CI-T`, `CI-X` item 1 |
| `ScrollEvent.isMomentum` is computed from the new `momentumPhase` (still assignable); AppKit fills `phase`, `momentumPhase` and `isPrecise`; SDL fills `.none`, `.none`, `false` for a wheel and, since record §155, `isPrecise: true` with synthesized `.began`/`.changed` and an inferred, late `.ended` for a fractional-delta stream (a trackpad, but also a hi-res wheel; divergences 845, 846), `momentumPhase` still `.none`; `SDLPlatform.Options` gains a last parameter `scrollPrecision: SDLScrollPrecision = .automatic` (source-compatible) | read the new fields for gesture phases; an SDL app that must keep a wheel-only reading passes `scrollPrecision: .disabled`; a handler that treated every SDL event as phaseless now sees a stream's `.began` ... `.ended` and the zero-delta `.ended` | `CI-I` items 1 and 6 (item 6 amended by `TP-A`..`TP-K`), `CI-V` item 1 |
| `DragGesture.Value`'s equality compares the new `modifiers` (the keys held at the event that produced the value); every existing construction defaults it to `[]` | nothing, unless a test compares a recorded value with one built without the modifiers it carried | `CI-G`, divergence 140 |
| **`Gesture` gains `Body` and `body`; `_recognizers()` is no longer a requirement** (`GE-A`), `DragGesture.Value` gains `time` and `velocity`, `MouseEvent` gains `timestamp: Double?` | a third-party `Gesture` conformer (impossible before) now compiles with a `body`; a recorded `DragGesture.Value` compares its `time`/`velocity` too (both default to the reference date and zero for a value built without them); a `PlatformWindow` conformer is unaffected, but a platform that builds `MouseEvent`s should pass its event time | `GE-A`, `GE-D`, `GE-F` |
| **a secondary drag defers the context menu**: with a `DragGesture(button: .secondary)` on the pressed chain, a right press opens its menu on the release, at the press point, and only when no such drag reached its minimum; without one the menu opens on the press as before | nothing | `CI-F` item 4 |
| `SpatialTapGesture`, `MagnifyGesture`, `RotateGesture`, `MouseButton`, `CoordinateSpace` and a located `onTapGesture`/`contextMenu` overload exist (they were not offered): an app's own type or method of one of those names is now ambiguous or shadowed | rename the app's own | `CI-B`, `CI-C`, `CI-F`, `CI-R` |
| **a wheel over an element walks a chain** (input APIs): the wheel goes to the topmost opaque target or `.onScrollWheel` region under the pointer and its ancestors on that layer, innermost first — at each a wheel handler (claims with `true`), then a scroller; a click target with no scroller or claiming handler above it still stops the wheel (`DD-Y` unchanged), and a wheel over only a declining handler now reaches `Window.onInput` | nothing for a tree without `.onScrollWheel`; a handler meant to veto a `ScrollView` goes on its content, not on the `ScrollView` (there it is the scroller's parent and sees nothing) | `CI-I` item 4, `CI-AH` item 1 |
| **a scroll's events are latched** (input follow-ups): a `ScrollEvent` with phase `.began` records the element it reached, and the rest of that scroll, momentum included, goes there even if the pointer moves; a scroll cut off by the window resigning key or closing now delivers one synthesized `.cancelled` to the handlers (never to a scroller); `Value.modifiers` on `SpatialTapGesture.Value` and `Value.clickCount` on `DragGesture.Value` are new members (a memberwise `init` call still compiles, both default), and `onCancelled` runs where `onEnded` never did | an `.onScrollWheel` that kept state from `.began` can drop its own tracking; handle `.cancelled` as an end | `IF-B`, `IF-C`, `IF-G`, `IF-H` |
| **a primary press while the last is still down is a lost release** (continuing press cancel): a reported `DragGesture`/`MagnifyGesture`/`RotateGesture` whose release never arrived now gets one `onCancelled` and the press starts a fresh arena (a drag with a `minimumDistance` can begin again), where it was dropped silently and the press started nothing; a real double-click is unchanged | a stopgap that reset gesture state on the next press can go; an `onCancelled` now also runs here | `GC-B`, `GC-C` |
| **the window sends a pointer style**: at the first pointer event, after the pointer re-enters, and whenever the resolved `.pointerStyle` changes, `PlatformWindow.setPointerStyle` is called (`.arrow` when no style is declared) | nothing; a platform window that ignored the cursor sees the calls | `CI-H` item 7, `CI-S` |
| **`AppKitPlatform.run()` installs its own `NSApp.delegate`** (an `NSApplicationDelegate` answering `applicationShouldTerminate(_:)` and `application(_:open:)`), replacing any delegate the app set before `run()`; **`MetalHostView.mouseDownCanMoveWindow` is `false`** — AppKit never drags a window from MetalUI's content on its own (under a hidden title bar `Window` decides) | move app-delegate work into `App.onTerminateRequest`/`App.onOpenURL` (or set the delegate after `run()` starts, at the cost of both) | `AS-C` item 7, `AS-J` item 3 |
| **SDL: `SDL_HINT_QUIT_ON_LAST_WINDOW_CLOSE` is `"0"`** (set by `SDLPlatform`'s initialiser), so SDL itself never sends `SDL_EVENT_QUIT` after the last window's close request; **`SDL_EVENT_QUIT` asks `onTerminateRequest` before stopping** (with none set it stops, as before) and **a window's close request asks `onCloseRequest`** (with none set it closes, as before); a file dropped on the application with no window (SDL's Cocoa `openFile:`) reaches `onOpenURLs` — it reached nobody | nothing for an app with no handlers; an app that relied on SIGINT ending the loop unconditionally sets no `onTerminateRequest` | `AS-B` item 6, `AS-C` item 8, `AS-G` item 5, `AS-L` |
| **Closing one of several windows no longer ends the app on AppKit** (at `c62d6ba` every window's close called `NSApplication.terminate`); the last window's close still does, now through `Platform.terminate()`, and `App.windows` drops a window when it closes | nothing for a one-window app; a multi-window app that relied on any close quitting calls `app.terminate()` from that window's `onCloseRequest` or `onDisappear` | `AS-C` item 5, `AS-K` |
| **⌘Q, a system quit, `SDL_EVENT_QUIT` and `App.terminate()` close every window first**: with no `App.onTerminateRequest`, each window's `Window.onCloseRequest` is asked in turn (a `.cancel` cancels the quit), and each window's `onDisappear` now runs on quit (at `c62d6ba` none ran) | nothing for an app with no handlers; an `onDisappear` that must not run at quit checks its own state; an app whose windows should not be asked sets `App.onTerminateRequest` | `AS-C` items 2–3 |
| **a composition does not survive its field losing focus** (input-method driver): `Window.focusedElement`'s `didSet` drops the marked text of a text field that lost focus (measured red first: the stale marked text came back when the field was refocused); committed text is untouched | none; nothing relied on it | `IM-I` |
| `Window.title`, `isDocumentEdited`, `representedURL`, `windowStyle`, `onCloseRequest`, `isCloseRequestPending`, `replyToCloseRequest(_:)`, `close()`, `performClose()`; `App.onTerminateRequest`, `replyToTerminateRequest(_:)`, `terminate()`, `onOpenURL`, `open(_:)`; `WindowStyle`; `EnvironmentValues.titleBarInsets`; `.navigationTitle(_:)`, `.navigationDocument(_:)`, `.onOpenURL(perform:)`; `openWindow(…, windowStyle:)` exist: an app's own member or method of one of these names on these types is now ambiguous or shadowed | rename the app's own | `AS-B`…`AS-G` |
| `PointerStyle`, `FrameResizePosition`, `FrameResizeDirection`, `.pointerStyle(_:)`, `.onScrollWheel(perform:)`, `PointerStyleModifier` and `ScrollWheelModifier` exist: an app's own type or method of one of those names is now ambiguous or shadowed | rename the app's own | `CI-H`, `CI-I` |
| `HorizontalDirection`, `VerticalDirection` (and their `Set`s) and `.pointerVisibility(_:)` exist: an app's own type or method of one of those names is now ambiguous or shadowed | rename the app's own | `PH-C`, `PH-F` |
| `MemoryLayout<Handlers>.size` is 480 (was 472): one more reference member, `pointer` (internal) | nothing | `CI-Q` |
| **`.task` exists** (it was not offered): a type of the app's own with a `task` method on an element group is now ambiguous or shadowed | rename the app's method | `PX-F` |
| **`metalui new --cross-platform` works without `--local`**: generated manifests name `MetalUISDL` from the MetalUI package with `traits: ["SDL", "AccessKit"]` on Linux/Windows | regenerate, or edit an existing manifest: delete the `Backends/SDL` path dependency and add the traits to the MetalUI dependency ([`getting-started.md`](getting-started.md)) | `PX-H`, `PX-J` |
| **`Backends/SDL` on macOS builds with flags**, not `PKG_CONFIG_PATH`: `swift test $(python3 scripts/fetch-accesskit.py --print-flags)` from `Backends/SDL` | update local scripts | `PX-I` item 6 |
| **a string literal in `Text` and `ProposalText` parses inline Markdown** (it lands on `init(_ key: LocalizedStringKey)`): a literal containing `**`, `_x_`, `` ` ``, `~`, `[…](…)`, a URL, an e-mail address, `&…;` or a backslash now renders styled, linked or decoded. A `String` value is never parsed, nor `Text(verbatim:)`. Every literal under `Sources/` and the suite's rendered ones parse to themselves (spec §0's census) | wrap a literal that must stay literal in `Text(verbatim:)` | `RT-B`, `RT-M` item 3 |
| an interpolated value in a `Text` literal is inserted verbatim in the format's style: `Text("**\(name)**")` is bold; a floating-point value prints its Swift description (`3.5`, where SwiftUI prints `3.500000`, divergence 151); any other value its description with no warning (divergence 156); an interpolated `Text` or `AttributedString` keeps its runs | nothing | `RT-C` items 3–4, `RT-O` items 4–6 |
| on Linux and Windows a code span (`` `x` ``) draws the family registered for the `.monospaced` design (`PortableFontResolver.register(design:family:)`), else the default face | register a monospaced family to see one | `TE-B`, `RT-O` item 12 |
| `Text.bold()` exists (it was withheld): the bold weight over whichever font resolves — SwiftUI's draws semibold on the default font (divergence 158) | write `.fontWeight(.semibold)` to match SwiftUI's default | `RT-R` item 6 |
| **`MetalUITesting` exists** (a library product for test targets): an app's own headless `Platform`/`PlatformWindow`/`WindowRenderer` test fake can be replaced by `HeadlessPlatform`, `HeadlessPlatformWindow` and `HeadlessWindowRenderer`, which implement every requirement and to which MetalUI adds each new platform requirement in the change that introduces it; `metalui new` now generates `Tests/<Name>Tests` over it, and refuses the name `Testing` (such a package fails `swift build --build-tests`) | drop the app's own fake for the harness ([`testing.md`](testing.md)); an existing generated package can add the test target by hand (`getting-started.md`) | `HT-A`, `HT-D`, `HT-O`, `HT-V` |
| **`TestWindow.runUntilIdle()` returns for a closed window** (it threw `.notIdle(rounds: 64)` when an approved close or termination closed the window mid-settle with a frame owed), and **`TestWindow.runUntil(timeout:_:)`** waits for a condition, drawing as it goes; `TestHarnessError` gains `.timedOut(after:)` | an exhaustive `switch` over `TestHarnessError` adds the case; a test that waited for work off the main actor by hand (a yield loop) can call `runUntil` | `HT-Y` |
| **Clock-driven work no longer sets `Window.needsRedraw`**: a scroll indicator's fade raises `hasActiveAnimations` instead, and a held long press or a pending tooltip keeps the display link ticking with `needsRedraw` `false`; so **`TestWindow.runUntilIdle()` returns after a scroll** (it threw `.notIdle(rounds: 64)` until the clock passed the fade) | code that read `needsRedraw` to learn a fade was running reads `hasActiveAnimations`; a test that called `advance(by:)` only to let `runUntilIdle()` return can drop it | `HT-Z` |
| **`List(_:rowContent:)` and its selection twins exist** (content-sized rows; they did not compile). A content-sized list's `style.size.height` is `.auto` — its extent is its layout's answer (measured rows plus estimates), where a uniform list's is `rowHeight × count`; the uniform spelling is unchanged | read a content-sized list's height from layout (`Frame.bounds(of:)`, `Window.lastElementBounds`), not from `List.style` | `VL-A`, `VL-I` |
| **`CoordinateSpace` has a third case, `.named(AnyHashable)`**, and `.coordinateSpace(.named(_:))`, `onContinuousHover(coordinateSpace:)`, `GeometryProxy.frame(in: .named(_))` and a named `DragGesture`/`SpatialTapGesture` exist (MetalUI is built without library evolution, so an outside exhaustive `switch` over `CoordinateSpace` no longer compiles; `CoordinateSpace` and `NamedCoordinateSpace` are `@unchecked Sendable` where SwiftUI's are `~Sendable`; `onContinuousHover(perform:)` gained a defaulted `coordinateSpace:` parameter, so an unapplied reference to the old spelling needs its type written out) | add a `case .named:` arm (or `default:`); a name no ancestor declares reads `.global`, never traps | `CI-AC`, `OV-D`, `OV-E`, `OV-F`, `OV-L` |
| **`.popover` takes `attachmentAnchor:`** (SwiftUI's `PopoverAttachmentAnchor`, `.rect(.bounds)` by default, so every existing call is unchanged; an unapplied reference to the old four-argument overload needs its type written out) and `anchoredOverlay(isPresented:at:in:anchor:content:)`/`(item:…)` exists (MetalUI-only: a chrome-less presentation with its corner at a point, dismissed by any outside press and Escape) | to draw a popover at the pointer with no panel, replace a hand-made `Deferred` + `.position(.absolute)` and an outside-press hack with `anchoredOverlay`; divergence 225 | `OV-A`, `OV-B`, `OV-K` |
| **`EnvironmentValues.windowSize`** (MetalUI-only, read-only): the window's content size, drawn chrome included | replace a size threaded by hand from `Window` into the tree | `OV-G`, `OV-O` |
| **`ShapeStyle`, `AnyShapeStyle`, `ResolvedShapeStyle`, `TintShapeStyle` and `.tint(_:)` exist** (round 3 item R3-9, `SS-A`…`SS-E`): `Color`, the gradients and `Material` conform, every colour-taking modifier gained a `some ShapeStyle` overload beside its concrete ones, so no call site changes. **Source breaks:** a file declaring its own `ShapeStyle`, `AnyShapeStyle`, `ResolvedShapeStyle` or `TintShapeStyle` collides (rename it or delete it for the framework's), as does an extension giving `Color` or a gradient a `ShapeStyle` conformance. **Behaviour:** `Color.accentColor` now follows the nearest `.tint(_:)` and is **no longer equal** to `Color.accent` (the theme token, which never follows a tint); untinted they resolve identically | use `Color.accent` where the theme's accent is meant and `Color.accentColor` where the tint should show; spell a themed control colour `.tint(_:)` instead of rebuilding the control's style |
| **The text modifiers `bold`, `underline`, `strikethrough`, `kerning`, `tracking`, `baselineOffset`, `monospaced` are now `ElementGroup` modifiers too** (round 3 item R3-10 part 1, `TM-A`), and `Text.LineStyle.Pattern` has `.dot`, `.dash`, `.dashDot`, `.dashDotDot`: over any container they write the environment a `Text` below reads (under the `Text`'s own value). **Source:** a file with its own `ElementGroup` extension of one of those names collides; nothing else changes for a call site. **Behaviour:** a `Text` inside a container that now (or an app that already) writes one of them as a SwiftUI would, draws it; `TextField`/`TextEditor` do not read the underline/spacing ones (`TM-H`). A stored property on `EnvironmentValues`/`EnvironmentFingerprint`: `swift package clean` | delete a hand-rolled environment key for the same job; rename a colliding extension | `TM-A`, `TM-B`, `TM-G` |

## Large trees in a debug build

A debug build gives every function a stack frame large enough for **every**
temporary it holds, in every branch, and a builder's element values are large
(a `Column` of twelve three-element `Row`s is ~48 KB). Two rules keep a large
app's tree inside a thread's stack — 8 MB on the macOS and Linux main
threads, **1 MB on Windows**:

1. **A branch that holds a large subtree goes in its own `Component`** (`PE-K`).
   Since `PE-J` a `Component`'s layout record is one heap box, so a shell
   `Component` whose `content` `switch`es over twelve pane `Component`s costs
   4.5 KB more stack than one pane (it cost 508 KB more, and the SMK
   configurator's root overflowed an 8 MB main thread). A `switch` over
   **inline** subtrees in one builder still grows with the sum of its branches
   (measured 1.3 MB for two to 4.3 MB for twelve branches of a pane-sized
   subtree) — a compiler property no MetalUI change can remove.
2. **Build a section in its own function**, not inline in one large builder
   (the demo's rule: `everyProductionTreeBuildsOnAOneMegabyteThread`).

`AnyElement(Box { … })` at each pane keeps working but is no longer needed for
stack depth. No `ElementGroup` eraser is offered (MG-22): a `Component` is the
spelling. MetalUI measures the stack a frame uses internally (`PE-L`, a
debug-only meter), but **does not warn yet**: four of the repository's own
demos measure above the 512 KiB threshold the design chose, so the warning
waits for a threshold chosen against them (`PE-T`).

### Text selection (`SL-`, record §96)

None: additive. `TextSelection` and the `selection:` initialisers are `@available(macOS 15, *)`; no
`PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement is added, so no conformer
changes. A field with no `selection:` runs no new code beyond one `nil` check.

### Incremental invalidation (`IV-`, record §104)

None for the API: additive (`Component.equatable()`, `EquatableComponent`, the `FrameWork` counters
`layoutMemoHits`, `layoutMemoMisses`, `layoutMemoRootHits`, `layoutSignatureNodes`, `contentEvaluations`,
`contentSkips`, `contentRefusals`); no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem`
requirement is added, so no conformer changes. **Behaviour, compiles and answers differently:** the layout memo
is automatic, so a keyed leaf's measure closure (plain `Text`, `Divider`, a built-in shape, the gradient leaf,
`GPUSurface`) is not called again on a frame that repeats its structure and proposal; a test that counted those
calls (`requestNativeLeaf` closures, `NativeLayoutWork`'s measure counts) reads fewer, and `NativeLayoutWork`'s
`==` gained the memo's four fields. A custom `ProposalLayout` that is not `Hashable` is unkeyed and is measured
as before. `METALUI_VERIFY_LAYOUT_MEMO=1` recomputes every hit and traps on a difference (`IV-J`). A component
adopting `.equatable()` owes an honest `==`: the content must be a function of the value, its own `@State`
and the `@Observable` properties it reads (`IV-B`).

### Retained subtrees (`SB-`, record §109)

None for the API: additive (the `FrameWork` counters `elementRequests`, `elementPrepaints`, `elementPaints`,
`retainedHits`, `retainedMisses`, `retainedIneligible`, `retainedSkippedPrepaints`, `retainedSkippedPaints`,
`retainedLedgerSnapshots`, `retainedReplayedOps`); no `PlatformWindow`, `Platform`, `WindowRenderer` or
`TextSystem` requirement is added, so no conformer changes. **Behaviour, compiles and answers differently:** an
`.equatable()` occurrence's **prepaint and paint** are replayed from a record while its value, `@State`, observed
reads, layout, surrounding paint context and the pointer, press and focus are unchanged, so a custom `Element`
under one is not called every frame: a test or an element that counted its `prepaint`/`paint` calls, or relied on
a side effect of one (a global written in `paint`, a clock read, a binding read only there), reads fewer calls or a
stale picture. The contract on `equatable()` is that the subtree's output is a function of the value, its `@State`,
the `@Observable` properties its elements read (in a getter, `prepaint` or `paint`) and the built-in environment.
A subtree that scrolls, edits text, animates, shows a popover or alert, draws a `GPUSurface` or sits under a custom
environment key keeps running as before. `METALUI_VERIFY_RETAINED=1` runs the fresh prepaint and paint beside every
replay and traps on a difference (`SB-W`). A test that must see every frame's prepaint turns replay off with the
package switch `Window.testingRetainedSubtrees = false` (not public API) or leaves `.equatable()` off.

### Retained build skip (`RK-`, record §110)

None for the API: additive (ten `FrameWork` counters: `retainedPrepaintHits`, `retainedPrepaintIneligible`, `retainedRedos`,
`retainedBackoffFrames`, `retainedTranslated`, `retainedTranslationRefused`, `retainedGrafts`, `retainedGraftIneligible`,
`retainedSkippedRequests`, `retainedGraftedNodes`); no platform requirement. **Behaviour, compiles and answers differently:** under an
`.equatable()` occurrence whose value, `@State`, observed reads, layout and pointer, press and focus are unchanged, **the content is no
longer built** and a custom `Element`'s `requestLayout` and `prepaint` are not called either (§109 replayed paint only): a test or an
element that counted those calls, or relied on a side effect of one (a global written in a builder or `prepaint`), reads fewer calls or a
stale value. The contract on `equatable()` is stronger by one clause: the subtree's `StateTable` writes made while building (a conditional,
a loop, a named `.id`) must be a function of the same inputs. A frame whose paint-time ambient (opacity, shadow, blur or composite scope
above the occurrence) changed is built a second time, once, with every replay off (`FrameWork.retainedRedos`); an element that counted
builds sees that frame twice. A store written during a build that is not idempotent owes a `rollbackBuild`
(`AnimationStore.checkpoint`). `METALUI_VERIFY_RETAINED=1` builds every replayed or grafted frame twice and traps on a difference.

### Environment readers under `.equatable()` (`EE-`, record §120)

No API change, no conformer change. **Behaviour, compiles and answers differently:** a component that declares `@Environment` and is
adopted with `.equatable()` was evaluated every frame (divergence 346); it is now skipped while what each declared property reads at
its position is unchanged (an `Equatable` value by `==`, a class or an `@Observable` instance by identity, an `@Observable` object's
read properties by the observation session), and a declared property its getter never reads still counts. A component that relied on
the refusal to stay fresh owes an honest `==` over its stored inputs (a synthesized `==` cannot see an `Environment` property): it is
re-run when an environment value it declares changes, not when its own `==` says so alone. Still refused and counted in
`FrameWork.contentRefusals`: `@FocusState` and a reader of an uncomparable value (a closure, a struct holding one, `\.self`).
(`\.textMeasurer` was in this list until record §127: a reader of it is now skipped while the text system and the two default text
styles it resolves are unchanged, `CF-A`; no API change.) A custom `EnvironmentKey` value that is `Equatable` no longer makes a retained occurrence ineligible; one that holds
a function still does (`uncomparableEnvironmentKey`). A test that counted the `.environment` bracket arm's refusals or node bodies
reads the `.value` arm's counts. The fingerprint now holds provided object **instances**, so a swapped `@Observable` object under a
retained occurrence misses instead of replaying the old paint (`EE-K`).

### Finer retention scopes (`FS-`, record §126)

None for the API beyond one additive `MetalUITesting` field, `FrameWork.retainedTranslationRefusedReasons: [String: Int]` (class M; a stored
property on a public struct with a defaulted initialiser parameter, so `swift package clean` after pulling); no `PlatformWindow`, `Platform`,
`WindowRenderer` or `TextSystem` requirement is added. **Behaviour, compiles and answers differently:** an `.equatable()` occurrence whose layout
origin or scroll offset moved (a row inserted above, a header above that resizes, a scroll) was a miss and is now replayed translated when the
shift is a whole number of device pixels, its content is rect, glyph or image only and no accessibility record, text input or press-only action
sits under it; a `List` row of `.equatable()` content now replays its prepaint and grafts like the same row in a `VStack`. A custom element under
one is called less often; a test that counted such an occurrence's element requests or `retainedPrepaintHits` reads fewer and more.
`METALUI_RETAINED_TRANSLATION=0` restores the miss. A hitbox gains two internal fields (`unclipped`, `clipDepth`).

### Warm and cold frame counters (`CF-`, record §127)

No API change, no conformer change. **Behaviour, compiles and reads differently** (`MetalUITesting`'s `FrameWork`, a test's numbers): on a **redo** frame
(`RK-D`) `contentEvaluations` now includes the content getters the abandoned attempt evaluated (it read 0 before, the redo skipping what the attempt had
made); every other counter is still the redo's own. A subtree restored by the placement memo now keeps its measurement entries alive, so the frame
after the records exist does exactly the work of the one before it: a test that recorded the old 135-against-52 layout spike on that frame (the bracket
node drag's press frame) reads 52. A component that read `@Environment(\.textMeasurer)` under `.equatable()` is skipped, not refused (divergence 346).

### Retained geometry and per-shelf atlas uploads (`RG-`, record §128)

One additive public declaration, `GlyphAtlas.dirtyRects: [(x: Int, y: Int, width: Int, height: Int)]` (class M). **`GlyphAtlas.dirtyRect` is still there and still read-only**, but it is now a computed
property, the bounding union of `dirtyRects`, not a stored value: a reader compiles unchanged, and a renderer that uploaded `dirtyRect` as one region remains correct (it uploads the span). A renderer
that wants the saving uploads each `dirtyRects` entry (Metal: one `replace(region:)` per rect, `bytesPerRow` the atlas width, the pointer offset to the rect's origin); `clearDirtyRect()` clears both. At most
eight rects, then one bounding rect until the clear. **`Backends/SDL` internal C signature:** `mui_renderer_finish` takes `atlas_rects`/`atlas_rect_count` (x, y, w, h `uint32_t` quadruples) in place of
`bool atlas_dirty`; a caller outside the package (none ships) passes the rects of `atlas.dirtyRects`. No `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement is added; no conformer changes.
`MetalUITesting`'s `lastAtlasUploadPixels` is now the sum of the rect areas, not the span's area: a test that read the span for two distant glyphs reads less.
**Behaviour, compiles and reads differently** (`FrameWork`, a test's numbers): an `.equatable()` occurrence holding an `.onGeometryChange` scope is no longer prepaint-ineligible (`retainedPrepaintIneligible`
reasons no longer count `geometryChange`); it replays its prepaint and paint, is never grafted (`graftRefusals["geometryGraft"]`) and refuses a translated replay by name (`geometryTranslated`); its action
fires exactly when a fresh window's would. A shifted subtree restored by the layout memo now counts a `layoutSubtreeHit` where it counted a miss (a custom `ProposalLayout` subtree never does), and
`SubtreePlacementTests` 2.3's moved-origin case reads 1 hit. A shift under a moved render effect counts `retainedTranslationRefusedReasons["effectAndLayoutMoved"]` where it counted nothing.

### Layout and outer effect moved together (`EL-`, record §157)

No API change. `retainedTranslationRefusedReasons["effectAndLayoutMoved"]` is retired (never emitted): a layout or scroll shift under a changed outer effect now replays and grafts, and a hitbox, accessibility record or geometry note made inside an effect the occurrence opened counts the new name `effectAndLayoutInner`. A test that read the old key reads 0.

### Accessibility under an effect-translated replay (`AT-`, record §129)

No API change, no conformer change, no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement. **Behaviour, counters read differently:** an `.equatable()` occurrence under a
render effect (`.offset`, `.scaleEffect`) that moved by a translation now replays its prepaint **with a client reading the accessibility tree** (its frames are recomputed against the current
effect), so a pan grafts instead of redoing the frame: a test that counted `retainedRedos`, `retainedBackoffFrames` or element requests of such a pan reads 0, 0 and far fewer, and
`retainedTranslationRefusedReasons["accessibilityRecords"]` no longer appears for it (layout translation still reports it). A scale or rotation change of the effect now counts
`effectNotTranslation` where it was silent. A custom element under such an occurrence is called less often.

### Retained lifecycle and translation carries (`RL-`, record §131)

No API change, no conformer change, no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement, no new public declaration. **Behaviour, counters read differently:** an `.equatable()` occurrence holding
`onAppear`/`onDisappear`/`onChange`/`.task` or an `onModifierKeysChanged` scope is no longer ineligible: `retainedIneligibleReasons["lifecycle"]`/`["modifierKeys"]` and `graftRefusals["lifecycle"]` read 0 and it grafts, with
every callback delivered exactly as for an unretained window (the actions still run after the build; a closure is the standing one, `.equatable()`'s contract). An observer (`.onGeometryChange`) in an occurrence no longer
refuses a translated replay (`geometryTranslated` is gone; a note is recomputed) and grafts unless a note is not recomputable (`geometryGraft` now only then; new names `geometryUnderEffect`, `geometryNamedSpace`). Layout
translation no longer refuses `accessibilityRecords` (gone; `accessibilityUnderEffect`, `accessibilityClipped` remain by name), and a hitbox opened inside the occurrence's own effect under a non-identity scale is re-derived rather
than counted `hitboxes`. A test pinning any of the old refusals or counts reads the new ones; a custom element under such an occurrence is called less often.

### Retained zoom and `@FocusState` memo (`RZ-`, record §133)

No API change, no conformer change, no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement, no new public declaration. **Behaviour, counters read differently:** an `.equatable()` occurrence under a render effect whose **scale or rotation changed** (a zoom) now replays its paint and prepaint and grafts:
a test that counted `retainedRedos`, `retainedBackoffFrames` or element requests of such a step reads 0, 0 and far fewer (ten nodes: 115 to 5 requests). **`retainedTranslationRefusedReasons["effectNotTranslation"]` is gone** (record §129 introduced it); a refusal now reads one of `effectFlatteningChanged`, `effectClipChanged`,
`effectInverseChanged`, `effectScopeChanged`, `effectCountChanged`, `prepaintContextChanged`, `geometryNamedSpace`, `presentationAnchor`, `contextMenus` or `hitboxes`. An `.equatable()` component declaring `@FocusState` is no longer refused: `FrameWork.contentRefusals` no longer counts it, and its getter is
skipped while focus is unchanged and run when it moves (a test that expected it evaluated every frame reads the memo). A custom element under such an occurrence is called less often.

### Retained read-only state (`RW-`, record §121)

None for the API beyond one additive `MetalUITesting` field, `FrameWork.retainedIneligibleReasons: [String: Int]` (class M; a stored
property on a public struct, so `swift package clean` after pulling); no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem`
requirement is added, so no conformer changes. **Behaviour, compiles and answers differently:** an `.equatable()` occurrence that holds an
unfocused `TextField`/`TextEditor`, a `ScrollView`/`ProposalScrollView`, a `List` or a closed `Picker`/`Menu`/`.popover` declarer was
refused (`stateWrite`, `presentationAnchor`) and rebuilt every frame; it is now replayed and grafted while the state those controls read is
unchanged, so a custom element under one is called less often, as in `SB-`/`RK-` (an `unfocused` field, a settled scroller, a `List` whose
window did not move). A scroll, a wheel, a window change, a selection, a focused field and any typed character still miss; an open popover,
an alert and a `GPUSurface` stay ineligible by name. A test that counted such an occurrence's `retainedIneligible`,
`retainedPrepaintIneligible` or `retainedGraftIneligible` reads 0 where it read 1, and one that counted its element requests reads fewer
(bracket `.panels` node drag: requests 167 to 144; orbit with panels: 115 to 6). **A framework `withState` that re-stores what is there is no
longer a write**: package code that wants the old behaviour calls the plain `withState`, which still bumps the version and taints.

### Window chrome on SDL (`CW-`, item S1, record §112)

Additive API, class M (SwiftUI has no window-control API, probe `swiftui-window-chrome.swift`):
`Window.drawsWindowControls` (default `true`), `Window.minimize()`, `Window.toggleZoom()`, `Window.isZoomed`,
`PlatformWindowAction`, `ChromeHitSnapshot`/`ChromeHit`, `HeadlessPlatform.Options.sdlChrome` and its read-backs
(`TestWindow.windowDragRegions`, `.windowActions`). **Conformers change:** four defaultless `PlatformWindow`
requirements (the table above). **Behaviour, compiles and answers differently:** on SDL (once the backend lands the
borderless window) `.hiddenTitleBar` makes the window borderless, `titleBarInsets` reads the band, 32, and the
drawn buttons' cluster (`right` 138; `left` 70 under macOS) where it read zero, and a window draws a three-button
cluster over the top corner unless `drawsWindowControls = false`: an app that laid its own controls there pads by
the insets and turns the property off. Pointer events inside a drag region are not delivered on SDL (divergence
425), so a hover or a pointer style under the empty band is lost; a control, a tap, a field or a draggable is carved
out and keeps its events. AppKit is unchanged.

### Input-method driver (`IM-`, record §102)

None for the API: additive (`TestWindow.setMarkedText`, `commitMarkedText`, `cancelMarkedText`, `markedText`,
`markedSelection`); no `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement is added, so no
conformer changes. One behaviour change (`IM-I`, a row in the table above): a text field that loses focus while
an input method is composing drops that composition, so a field refocused later no longer shows stale marked text.

### SDL GPU for apps (`GA-`, record §114)

None for existing code: a new library product `MetalUISDLGPU` behind the `SDL` trait (typed `SDLGPUDevice`,
buffers, compute pipelines, passes, fences and a shader library over SDL_GPU, plus the raw `CSDL` module re-exported
by the same import). No `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement is added, so no
conformer changes; `SDLGPUDrawContext` is unchanged. An app that bound SDL3 itself keeps working and may drop its
binding. An app's own shaders are built with `MetalUICompileShaders` (`swift package compile-shaders`, see
`BS-` below) and shipped as `MetalUIAppShaders` (`docs/packaging.md` section 4a).

### Build-time app shaders (`BS-`, record §138)

**`Backends/SDL/scripts/compile-app-shaders.py` is deleted**: one implementation, in Swift, which a plugin can run
where python cannot be found portably. The same inputs and outputs now go to the root package's
`MetalUICompileShaders` executable product or its `CompileShaders` command plugin, and the flags carry over with one
change: `--shadercross PATH` is optional (then `METALUI_SHADERCROSS`, then `PATH`), where the script required it:

```text
python3 compile-app-shaders.py --shadercross /x/shadercross --source shaders --out shaders/compiled
swift package --allow-writing-to-package-directory compile-shaders --shadercross /x/shadercross --source shaders --out shaders/compiled
```

New `--formats spv,msl,dxil,json`, `--no-marker`. The output bytes are the script's (marker included). Source
compatible for code: `SDLGPUShaderLibrary(directory:)` now also accepts a directory with no `SOURCE.sha256` that holds a
`NAME.<vert|frag|comp>.json` (a build product; today's checked-in directories open exactly as before, and the error
still names `SOURCE.sha256`), and `init(directory:verifyingSources:)` is new. No `PlatformWindow`, `Platform`,
`WindowRenderer` or `TextSystem` requirement changes. Nothing is published: a pinned shadercross is documented in
`docs/packaging.md` section 4a, not shipped.

### Lazy containers (`LZ-`, record §134)

Nothing breaking. `LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid` and `GridItem` are new public declarations; no `PlatformWindow`, `Platform`,
`WindowRenderer` or `TextSystem` requirement, no `Handlers` member and no `LayoutTree` kind is added. `FrameWork` gains three public counters
(`lazyUnitsRealized`, `lazyLinesRealized`, `lazyUnbounded`) with defaults in its initialiser, so existing calls are unchanged. A third-party `PlatformWindow` conformer needs nothing.

### Scroll extras and `@Bindable` (`SP-`, record §177)

Nothing breaking. New public declarations: `Section`, `PinnedScrollableViews`, `Bindable`, `ScrollTargetLayout` (and `ElementGroup.scrollTargetLayout(isEnabled:)`), `ScrollView.scrollPosition(id:anchor:)` and
`ProposalScrollView.scrollPosition(id:anchor:)`; `LazyVStack.init` and `LazyHStack.init` gain a defaulted `pinnedViews:` parameter (between `spacing:` and `content:`, as in SwiftUI), so existing calls compile unchanged.
`ScrollState` gains an internal stored property (`swift package clean` once). No `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement, no `Handlers` member and no `LayoutTree` kind changes. A `scrollTo` made
under `withAnimation` now glides where it jumped before. A third-party `PlatformWindow` conformer needs nothing.

### SDL GPU gaps (`GB-`, record §137)

Source compatible for code that builds against `Backends/SDL` (a source-distributed class M layer, `GB-K`), with one
arm owed: **`SDLGPUTextureFormat` gains `case r32Float`**, so a caller's exhaustive `switch` over it (without
`default`) stops compiling until it adds the arm (four bytes a texel, like `r32Uint`; filter it `.nearest`).
`SDLGPUGraphicsPipelineDescription.init` gains a last `writesColor: Bool = true` and `SDLGPUSamplerDescription.init` a
last `maxAnisotropy: Float = 1`, so existing calls are unchanged. `SDLGPURenderPass.setViewport` and `setScissor` are new.
`SDLGPUFence.waitBlocking()`, `SDLGPUDevice.downloadSynchronously(_:region:)`, `compileGraphicsPipeline(_:)`,
`compileComputePipeline(_:)` and `lastPipelineFailure` are new; `makeGraphicsPipeline`, `makeComputePipeline`, `wait()` and
`download` keep their spellings. `SDLGPUError` gains an internal initialiser only.
No `PlatformWindow`, `Platform`, `WindowRenderer` or `TextSystem` requirement is added.

### Clipboard beyond text (`CB-`, record 115)

**Four defaultless `PlatformWindow` requirements** (`CB-E`): a conformer outside this repository adds
`func writeClipboard(_ representations: [ClipboardRepresentation]) -> Bool`, `func clipboardTypeIdentifiers() -> [String]`,
`func readClipboard(identifier: String) -> [UInt8]?` and `func setClipboardCommands(_ commands: ClipboardCommands)`.
A platform with no typed clipboard answers `{ false }`, `{ [] }`, `{ _ in nil }` and `{ _ in }`; the text-only
`readClipboard()` and `writeClipboard(_ text:)` stay and text fields keep using them. `HeadlessPlatformWindow.clipboard`
is now a view of its `public.utf8-plain-text` representation (`clipboardRepresentations` holds all of them).
New API (additive): `copyable(_:)`, `cuttable(for:action:)`, `pasteDestination(for:action:validator:)` in both
vocabularies, `Window.clipboard`/`Clipboard`; a file importing CoreTransferable spells `MetalUI.Transferable`.
Behaviour: a key the Edit menu or the keyboard sends as primary C/X/V now reaches a clipboard handler on the focus
chain before a `Button`'s shortcut or an app command bound to the same key (`CB-B`); with no handler nothing moves.

### Clipboard items and change notification (`CP-`, record 142)

`PlatformWindow` gains **four defaultless requirements** (a conformer adds them or fails to compile):
`func writeClipboard(items: [ClipboardItem]) -> Bool`, `func clipboardItems() -> [[String]]`,
`func readClipboard(item: Int, identifier: String) -> [UInt8]?` and
`func setClipboardChangeHandler(_ handler: (@MainActor () -> Void)?)`. A platform with no typed clipboard answers
`{ false }`, `{ [] }`, `{ _, _ in nil }` and `{ _ in }`. `ClipboardItem`/`ClipboardPayload`/`ClipboardBytes`
(`.now(bytes)` or `.later(closure)`) are the new `MetalUIPlatform` types; the change handler is called on the
main actor whenever the clipboard may have changed (an own write, SDL's `SDL_EVENT_CLIPBOARD_UPDATE`, AppKit's
`changeCount` seen on becoming key and at a press). The four `CB-E` requirements stay and mean item 0.
`HeadlessPlatform.Options` gains `clipboardExportsLazily` (default `true`).

### Matched geometry and custom transitions (`MG-`, record 175)

Additive: `matchedGeometryEffect(id:in:properties:anchor:isSource:)`, `MatchedGeometryProperties`, the `Transition`
protocol, `TransitionPhase`, `TransitionContent`, `AnyTransition(_:)` and `.transition(_:)` over a `Transition`. **Porting
SwiftUI code:** a `matchedGeometryEffect` swap works as written, but a leaver you gave `.transition(.identity)` hands its
frame over to nothing (SwiftUI's rule, probe S2); the move is a paint map (hit testing keeps the laid-out frame, 895; a
size change stretches the content, 896; the leaver moves toward the source as it fades, with the residues of 897, and the newcomer fades in while it flies). A SwiftUI `Transition`'s `body` returns a view;
here it returns `TransitionContent` built with `content.opacity(_:)`, `.scaleEffect(_:anchor:)` and `.offset(x:y:)`, the
only effects a transition has (898): rewrite `content.scaleEffect(phase.isIdentity ? 1 : 0.5)` as is, and drop any other
modifier (a blur, a rotation, a background). `contentTransition`, `.blurReplace` and `.modifier(active:identity:)` do not
compile (`MG-H`).
### Dialog and alert extras (`SV-AO`, record 179)

`PlatformFileDialog` gains a **stored `message: String?`** (an `init` parameter defaulting to `nil`, so existing calls
compile; a conformer or fake that built a `PlatformFileDialog` by member-wise copying needs no change, one that
switches on every field adds it). New API (additive): `.fileDialogConfirmationLabel(_:)`, `.fileDialogMessage(_:)`
(`Text` and string spellings) and `Visibility` (`confirmationDialog(…titleVisibility:…)` gains it as a defaulted
parameter). **Two behaviours change**: a `confirmationDialog` whose actions name no cancel button now shows a
synthesized "Cancel" and no default button (as SwiftUI/AppKit do; an `.alert` is unchanged), and a `Button` with a
non-`Text` label in an alert's actions is now accepted (its first `Text` is the title; one with no `Text` is left out)
instead of failing to compile. A platform conformer shows `message` where its dialog has a field for it
(`NSSavePanel.message`); SDL passes the `prompt` as its accept label and the `message` as its title. Rebuild
dependents with `swift package clean` (a stored property on a public type crossing a module boundary).
### Path operations (`PG-`, record 181)

Additive, with two behaviour changes. New API: `Path.trimmedPath(from:to:)` (arc length across all subpaths, closing edge
counted), `strokedPath(_:)`, `applying(_:)`, `addRelativeArc(center:radius:startAngle:delta:transform:)`, a trailing
`transform: Transform2D = .identity` on `addRect`, `addRects`, `addRoundedRect`, `addEllipse`, `addPath` and both
`addArc`s (a call that passes no `transform` is unchanged), `Shape.trim(from:to:)` (`TrimmedShape`, animatable under
`withAnimation`), `UnevenRoundedRectangle`, `RectangleCornerRadii`, and `Transform2D` (the type SwiftUI spells
`CGAffineTransform`; convert with the six components). A file that already declares its own `Transform2D`,
`TrimmedShape`, `RectangleCornerRadii` or `UnevenRoundedRectangle` now collides; rename it or delete it for the
framework's. **Behaviour:** (1) a built-in shape's outline now starts where SwiftUI's does (a rounded rectangle,
capsule, circle or ellipse on the right edge, a rectangle top-left), not at the top edge, so a **dashed stroke's
pattern starts there** (matching SwiftUI) and `trim` begins there; the filled and solid-stroked pixels are unchanged
(within the rasterizer's rounding); (2) a custom `Shape` overriding `path(in:)` is unaffected. `UnevenRoundedRectangle`
with a radius past half the shorter side draws as a path and was, at record 184, unable to be a `clipShape` (since record 220 it is a path mask).

## The glyph atlas reclaims space (record 184)

- **Removed: `GlyphAtlas.evictUnusedSince(_:)`.** It had no caller in the framework, and evicting never freed atlas pixels. A third-party renderer
  or text sink that called it has nothing to call: the window rebuilds the atlas itself (`GlyphAtlas.reclaim()`, between frames).
- **`GlyphAtlas.width` / `height` are no longer constants.** They change when the atlas grows or is rebuilt at another size; read them again for every
  frame, and treat a new extent as a new texture to be uploaded in full (both bundled renderers do; `Renderer.upload`'s and `mui_renderer_finish`'s
  size comparison). A renderer that cached the extent at creation must stop.
- **A rect is only valid within one `GlyphAtlas.layoutGeneration`.** Code that keeps an `AtlasSlot` or a `MUIGlyph` past a frame (a cache of sprites)
  must key on, or drop at a change of, `layoutGeneration`.
- **`GlyphAtlas(width:height:)` is unchanged and never grows**; pass `maximumExtent:` to opt in. A full atlas still answers `nil`, now also counted in
  `droppedGlyphs`.

### Right-to-left layout direction mirrors layout (`LD-`, record 191)

**Behaviour change; no source change.** `.environment(\.layoutDirection, .rightToLeft)` (or a window root whose environment reads it) used to be
carried and read by nothing (divergence 25). It now mirrors layout as SwiftUI does: stacks run right to left, a `.leading` alignment or frame
puts the child on the right, `padding(.leading:)` pads the right, `ZStack`/overlay/`Grid`/lazy-stack/custom-`ProposalLayout` placements reflect,
`offset(x:)`/`position(x:)` flip inside the writer, `scaleEffect`/`rotationEffect` anchors and sense mirror, a horizontal scroller opens at the
right and its offset is measured from the right, and `multilineTextAlignment(.leading)` aligns right. **If your tree was already right-to-left**
(an app that set the key to try it out, or a test that pinned the old unmirrored figures such as `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`),
its layout changes; wrap the part that should stay left-to-right in `.environment(\.layoutDirection, .leftToRight)`. Not mirrored (divergence 1045):
a shape's own path, a gradient's `.leading`/`.trailing` points, `trim`, `UnevenRoundedRectangle`'s corners; mirror such a shape yourself (an element
that reads `@Environment(\.layoutDirection)` and picks its own path). A custom `ProposalLayout` keeps writing its placements as if left-to-right: the kernel reflects them. Rebuild
dependents with `swift package clean` (a stored property on the public `LayoutTree`).

## Record 203 (round 4 item R4-2 PR B): default spacing at a text edge

`TextFontMetrics` gained `capHeight: Double?` (a defaulted initialiser argument, so no `TextSystem` conformer changes; see the table above; `swift package clean` after pulling, a stored property on a public type). **Behaviour, compiles and answers differently:** a default-spaced `VStack` or `Grid` (no `spacing:`) next to a `Text` now takes the font's own gap where it took 8: text above text `ceil(leading)` of the lower one (**0** for the system font, so a `VStack` of two `Text`s is one line shorter per gap), a rect above a text `descent + ceil((ascent + descent) / 10)` (4.742 at 13 pt), a text above a rect that plus `ascent - capHeight` (8.151 at 13 pt), measured in SwiftUI on macOS 27.2 (probe `swiftui-default-spacing.swift`). Horizontal gaps, `Spacer()`'s minimum, an explicit `spacing:` and every pair with no text are unchanged; a bordered `Button`, a `Toggle`, a `Stepper`, a `Picker`, a `ColorPicker` and a `ProgressView` keep the standard 8; a `.plain`, `.borderless` or `.link` `Button` takes its label's text edges; `LazyVStack`, `LazyHStack` and `LazyVGrid` keep 8 (divergence 51, narrowed). On Linux and Windows the rule runs on that platform's metrics (`hhea`, `OS/2`): MetalUI's ruling, not a measurement. To find what moved, `grep -nE '\b(VStack|Grid)(\(alignment: *[.a-zA-Z]+\))? *\{'` next to `Text`, or read `frame(ofID:)` before and after. Give the gap you want with `spacing:`.

## Record 205 (round 4 item R4-3 PR B1): a removal ghost's position

**Behaviour, compiles and draws differently; no source change.** A `.transition(...)` removal's ghost used to be drawn after the whole window (above every element of the window); it is now the **first thing in its own container's run**, above that container's own fill and below its content, as SwiftUI places a leaver (`XF10`, `XF2zb`, `XF2zc`): `ZStack { blue; if shown { red.transition(.opacity) } }` fades red *under* blue, where it faded over it. **If your tree has a removed view that overlapped a sibling**, that overlap now reads the sibling on top for the fade's length; a leaver that must stay above its siblings goes in a container of its own (a `ZStack` around the conditional, after them), whose run it then leads; MetalUI has no `zIndex`. An annotated removal of content that draws nothing (`Color.clear`, an empty `Box`) now delays its `onDisappear` to the end of the animation, as SwiftUI does (`T1e2`); it used to run at once. The unannotated cross-fade (divergence 98) is not in this record. A retained (`.equatable()`) occurrence that holds a ghost builds and paints fresh each frame for the fade's length (counted as `ghostInRun` in `retainedIneligibleReasons`), then resumes replaying.

## Record 206 (round 4 item R4-3 PR B2): the default fade

**Behaviour, compiles and draws differently; one public-type change.** An `if` under `withAnimation` now fades, and its `onDisappear` waits for the animation: every member of a builder `if`, `if`/`else`/`switch` branch and non-lazy `ForEach` element is inserted at opacity 0 and removed to 0 (linear in the animation's progress, SwiftUI's `+1`/`-1`, `XF0`, `XF3`, `XF4`, `XF6`), where it appeared and vanished at once. **Write `.transition(.identity)` on the content for the old behaviour.** A mixed unit keeps its annotated member's own transition and fades the others (`XF5`). No animation (no `withAnimation`, `.animation(_:value:)` or `.transaction`) and a window's first render fade nothing, a lazy or `List` row does not, an `AnyElement` swap does not (divergence 212), a changed `.id(_:)` does not (SwiftUI fades it: row 98's residue), a `for` loop's iteration does not. A **removed view's `onDisappear` now runs when the fade ends**, not in the removal frame; code that read state in `onDisappear` sees the departed state as before (`LC-I`). An `.equatable()` component whose content changes a conditional under an animation builds, prepaints and paints fresh for the fade's length (counted in `retainedIneligibleReasons`), then resumes replaying. A `matchedGeometryEffect` whose newcomer starts a flight keeps its old look (the leaver draws nothing, the card flies opaque); without a flight the pair cross-fades. **Public type:** `OptionalGroup`'s `GroupLayout` is now `ConditionalLayout<Wrapped.GroupLayout>` and `EitherGroup.Layout`'s cases carry the branch id (`.first(_, unit:)`); an app never spells either (a hand-written `ElementGroup` that wraps an `OptionalGroup` forwards its associated types). `OptionalGroup(_:)`, written by hand, does not fade (framework slots). Rebuild dependents with `swift package clean`.

## Record 208 (round 4 item R4-3 PR D): `Animatable`

**Compiles; one spelling may need a keyword, one set of values differs.** `Shape` is now `Animatable`, as SwiftUI's is, so a custom `Shape` can declare `animatableData` and animate it under `withAnimation` (a shape that declares none snaps, as before). **In Swift 6 write `nonisolated var animatableData`** (divergence 215): SwiftUI's own spelling errors here because MetalUI's `Shape` is main-actor. A third-party `Shape` that declares nothing compiles unchanged; `any Shape` gained an associated type, which no existing member use notices. **A keyframe track's value must be `Animatable`** (SwiftUI's rule): `Double`, `CGFloat`, `Angle`, `Float` (a MetalUI extra) and every SwiftUI conformer are; a type that conforms to `VectorArithmetic` only must add `: Animatable` (its `animatableData` is itself by default). **`TrimmedShape.animatableData`** is the base's data then the two fractions times 128, as SwiftUI's; a read of the data sees the scale. A retarget of an animating shape restarts the whole vector at rest (divergence 216); the `@Animatable` macro is not offered. Write `swift package clean` after pulling (a conformance added to a public protocol and a stored property on `AnimationStore`).

## Record 230 (Alloy gap G3 PRs 0-1): `Image(systemName:)`

**Compiles; `swift package clean` after pulling.** `Image` stores a content enum (a bitmap or a symbol name) instead of an `ImageBitmap`, and `EnvironmentValues` gained `imageScale`, `symbolVariants` (public) and a rendering-mode field (internal), all three in the retained fingerprint: a stale build directory crashes or reads a wrong value. The guard `anImageHasNoSystemNameOrAssetInitialiser` is `anImageHasASystemNameButNoAssetInitialiser`. On Linux and Windows `Image(systemName:)` compiles and draws nothing (a 0 x 0 leaf) until the bundled icons land.

## Record 232 (Alloy gap G3 PR 2): bundled icons

**Compiles; `swift package clean` after pulling** (a new case on `Image`'s content enum and a new target, `MetalUIIconData`, that `MetalUI` depends on). On Linux and Windows `Image(systemName:)` now draws a bundled Lucide icon for the 38 names it maps (divergences 230, 231) instead of nothing; an unmapped name is still an empty 0 x 0 leaf. New MetalUI-only API: `Icon`, `Icon.Layer`, `Icon.bundled(_:)`, `Image(icon:label:)`, `Image(decorative: Icon)`. A binary now carries the Lucide licence: see `THIRD-PARTY-NOTICES.md`.

## See also

- [`api-overview.md`](api-overview.md) — the public surface by area.
- [`testing.md`](testing.md) — testing an app's interface headless.
- [`divergences.md`](divergences.md) — every remaining difference from SwiftUI.
- [`verification/human-checks.md`](verification/human-checks.md) — the looks
  that still need a human.

## Record 209 (round 4 item R4-3 PR E): `Component & Animatable`

**Compiles; a component that already conformed to `Animatable` starts to move.** A `struct Counter: Component, Animatable` used to compile and animate nothing; it now runs its `content` at the interpolated data under a transaction that changes it (SwiftUI's `View & Animatable`, probe `VA5`), so its children are proposed every in-between size and `.equatable()` runs the body in flight and skips it once settled (`VA7`, `VA7s`). **In Swift 6 write `nonisolated var animatableData`** (the same fix as for a `Shape`, divergence 215; SwiftUI's `View` has it too). The setter must not write an `@Observable` or an `@State` (it runs in the layout phase); a setter that replaces `self` (`self = Counter(x: newValue)`) is fine, the state is bound after. A component that is not `Animatable` pays nothing and reads the same as before. `Component` gained one **public, underscored requirement with a default**, `_interpolateAnimatableData(id:pass:)`: never implement or call it (an existing conformer needs no change). Write `swift package clean` after pulling (a protocol requirement added).

## Record 217 (`ViewThatFits`, `Axis`)

**`Element.prepaintGroup` now returns `PrepaintState?`, and an `Element`'s `GroupPrepaint` is `PrepaintState?`.** The group entry answers `nil` for an element inside a `ViewThatFits` candidate that was not chosen (`VF-C`). An `Element` conformer is unaffected (it implements `prepaint(_:bounds:layout:pass:)`, not the group entry); a caller of `element.prepaintGroup(layout:pass:)` that stores the result in a `PrepaintState` gets a type error and unwraps (`prepaintGroup(...)!` is right only outside a `ViewThatFits`), and `paintGroup(layout:prepaint:pass:)` takes an `inout PrepaintState?`. A type that declares `typealias GroupPrepaint = X.PrepaintState` for an `Element` `X` must say `X.PrepaintState?`. Generic wrappers over `Content.GroupPrepaint` (`Pair`, the scopes, `Component`) are unchanged. `ElementGroup` conformers that implement their own `prepaintGroup` are unchanged; one that copies `Element`'s entry (as `AnyElement` does) must skip an element for which `Frame.isElided(node)` holds.

**A module that declares its own `Axis` now sees an ambiguity** wherever it says `Axis` unqualified and imports `MetalUI`: write `MyModule.Axis`, or rename the type. `MetalUI.Axis` is SwiftUI's (`.horizontal`, `.vertical`, `Axis.Set`); `ScrollAxis` is unchanged.

## Record 218 (`PrimitiveKind.group`, group opacity)

**`PrimitiveKind` gains `.group`: an exhaustive `switch` over it outside the package now needs an arm** (as `.surface` in record 71 and `.backdrop` in record 94). A `.group` run is one `MUIImage` quad in `Scene.groups` whose `texture` indexes `Scene.groupScenes`, a finalized `Scene` the renderer draws first into a target of the quad's box (the nested scene's coordinates are the parent's). A custom `WindowRenderer` that draws a `Scene` by hand draws the group scenes first, post-order, and the quads as image runs. `Scene` also gains `groups`, `groupScenes` and `insert(_:group:layer:)`. `ReplayFixture` is version 7 (versions 2-6 still load); `mui_renderer_finish` and `replay_render` take three more arguments (groups, group count, main run count). An opacity written outside `compositingGroup()` now composites the group (divergence 205 retired).

## Record 219 (`Scene.groupFilters`, a filter over a group texture)

**`Scene` gains `groupFilters`, `Scene.GroupFilter`, and `insert(_:group:layer:transform:filter:)`; a `WindowRenderer` that draws groups must run the filter** (a downsample chain, two Gaussians and, for a shadow, a tint pass over the group's target, then sample the result) or its filtered groups draw unfiltered. The new parameters have defaults, so a caller that never filters is unchanged; a group quad's `filter` bits 8...31 now hold a transform index (a filtered group drawn under a projective effect). `ReplayFixture` is version 8 (each group carries `filterKind`, `sigma`, `tint`; versions 2-7 still load), and `ReplayGroup` in `SDLBridge.h` gains three fields: a third-party caller of `mui_renderer_finish` adds them.

## Record 220 (`Scene.groupMasks`, shape clips as masked groups)

**`LayoutModifier.clipShape` gains a payload: `case clipShape(any Shape, style: FillStyle = FillStyle())`.** An external `case let .clipShape(shape)` pattern now binds a tuple; write `case let .clipShape(shape, style)` (or `.clipShape(let shape, _)`). `clipShape(_:style:)` is on the proposal path and the legacy `StyledElement` (`ClipShapeBox` carries the style), the one-argument spelling stays. `clipShape(Ellipse())`, `clipShape` of a `Path` or any shape whose geometry is a path, and two crossing rounded clips no longer trap or fall back to the square box: they paint through a masked group (divergences 91 and 92 retired). **`Scene` gains `groupMasks`, `[Scene?]` parallel to `groupScenes`, and `insert(_:group:layer:transform:filter:mask:)`**; a `WindowRenderer` that draws groups must multiply a masked group's target by the mask scene's alpha (draw the mask into a scratch of the group's size under the group's projection, then a destination-in blend `dst *= mask.a`) after the content and before any filter, or it draws the group unmasked (the bounding clip still cuts). The new parameter is defaulted, so a caller that never masks is unchanged. A mask scene holds only rects and images (a precondition). `ReplayFixture` is version 9 (each group may carry a mask body; versions 2-8 still load unmasked), and `ReplayGroup` in `SDLBridge.h` gains `mask_run_start` and `mask_run_count`: a third-party caller of `mui_renderer_finish` adds them. `UnevenRoundedRectangle` with a radius past half the shorter side, which could not be a `clipShape`, now is (a path mask).

## Headless menu keys (`HT-AA`)

**`TestWindow.typeKey`/`typeText` now deliver nothing while a natively presented menu is open** (`presentedMenu != nil`), as AppKit tracks a menu modally; Escape dismisses it. A test that typed a shortcut with a menu open must `dismissMenu()` or `chooseMenuItem` first. Raw `send(_:)` and drawn menus (`presentsMenusNatively` off) are unchanged.

## Record 221 (a gradient `foregroundStyle` on text)

**`Text.foregroundColor` and `ProposalText.foregroundColor` (public, `Color?`) are computed properties** over an internal `foregroundStorage: ShapeStyleStorage?` (the getter is the style's representative colour, the setter stores `.color(_)` or clears). Source-compatible: every read and write compiles as before; a gradient `foregroundStyle` reads back as its first stop. `EnvironmentValues.foregroundStyle` (internal) is computed the same way over `foregroundStorage`. **A stored field of a public type changed, so run `swift package clean` once** (a stale build crashes with `Undefined symbols … direct field offset` or an impossible value). **A mask scene (`Scene.groupMasks`) may now hold glyphs as well as rects and images** (a gradient text's mask is its glyph run): a `WindowRenderer` that draws a masked group already draws any run kind into the scratch, so none changes; the `Scene.insert(_:group:mask:)` precondition message changed ("rects, glyphs and images"). A mark's `mask` is N primitives: code outside the package that read `GroupMark.mask[0]` (none is public) reads all of it.

## Record 222 (`WindowRenderer.setPresentationObserver(_:)`, `RenderSurface.present(_:in:onPresented:)`)

**`WindowRenderer` gains `setPresentationObserver(_:)` and `RenderSurface` gains `present(_:in:onPresented:)`; both are defaulted, so no conformer changes.** The defaults report nothing: `FrameTimingSample.presented` stays `nil`. A renderer whose platform reports presentation implements the observer (once per finished frame, on the main actor, token = 0-based finished-frame count since installation, time = nanoseconds of `DispatchTime.now().uptimeNanoseconds`'s clock); `MetalWindowRenderer` does, `SDLWindowRenderer` does not (SDL_GPU reports none). Nothing else in the protocol changes (`FP-F`, `docs/frame-timing.md`).

## Record 226 (continuous rounded corners, `CC-`)

**Behaviour, not API.** `.continuous` (the default of `RoundedRectangle` and `Capsule`) now draws SwiftUI's curve, not a circle: every default rounded rectangle, capsule, border, material and shadow changes by up to 0.0138 of its radius (196 px at r 20 in 100×60). `.circular` is unchanged. A `clipShape(RoundedRectangle(...))` or `.cornerRadius` is still circular (divergence 90, carried). **`UnevenRoundedRectangle` fits its radii horizontal sides first** (top, then bottom, then right, then left), as SwiftUI does; a few combinations of large radii on two sides change by that. A conformer of the renderer's shader constants adds `MUIShapeContinuousRect = 2`; `PrimitiveShape` gains `.continuousRoundedRectangle` (a public enum: an exhaustive `switch` adds an arm). The SDL backend adds one pipeline (`continuous.fragment`; thirteen blobs).

## Record 236 (wheel routing, `XS-`)

**Behaviour, not API.** A wheel event now goes whole to one axis (the dominant component of the event, or of the scroll's first event on a trackpad) and to the nearest scroller on the chain that scrolls that axis: a vertical wheel over a horizontal `ScrollView` inside a vertical one now scrolls the outer, a scroller whose content fits or that sits at its end passes the wheel up, and a one-axis scroller ignores the non-dominant component of a diagonal event. **A custom scroller that calls `PrepaintPass.registerScrollRegion(_:id:axis:)` now passes the other axis on** (it used to claim every wheel over it, moving nothing on the wrong axis); it declares both directions open on its axis, so it never passes its own axis up. `.onScrollWheel` handlers are unchanged (the raw event, first); a `TextEditor` takes only the vertical axis.

## Record 237 (the two-axis scroller, `XS-`)

**API addition, one build hazard.** `ScrollView(_ axes: Axis.Set)` and `ProposalScrollView(_ axes: Axis.Set)` (`@_disfavoredOverload`: `ScrollView(.horizontal)` is still `ScrollAxis`). `ScrollView.axes` and `ProposalScrollView.axes` are now the stored property and `axis` a computed one (get: `.horizontal` for exactly `[.horizontal]`, else `.vertical`; set: one axis), so a source that reads or sets `axis` compiles unchanged. These are stored-property changes on public types: run `swift package clean` before trusting an incremental build. A custom `ProposalLayout` or element is unaffected; `ScrollContext` gains internal fields only.

## Record 242 (the caret after an external text change, `selectedOffsets:`, paste destinations, `SL-P`, `SL-Q`, `CB-T`)

**Behaviour change, three parts, one new API.** (1) A focused `TextField`/`TextEditor` with **no selection binding** whose bound text is replaced from code now moves its caret to the end of the new text (SwiftUI's measured rule; identical text keeps it), where it kept the old offset clamped. An app that rewrote the text and relied on the caret staying put (a find-and-replace that keeps the caret, a formatter that re-flows as the user types) must bind a selection (`selection:` or the new `selectedOffsets:`) and write the caret it wants after the text: with a selection binding attached nothing changed. A binding that transforms or rejects each edit (`.constant`, a filter) counts as a replacement too: the caret goes to the end. (2) `TextField(_:text:selectedOffsets:)` and `TextEditor(_:text:selectedOffsets:)` over `Binding<Range<Int>?>` (Character offsets, macOS 14 and later) are added; `TextSelection` stays macOS 15. (3) A focused text field's paste key is offered to the innermost `pasteDestination` on its focus chain first; an app that put a `pasteDestination` on a container of a text field and relied on the field pasting text when the destination also imports `String` now gets the destination instead (return no items from its validator to decline).

**Also (`CB-T`, amends `CB-M`):** because a destination is offered the paste key first, a `pasteDestination` on a text field or its ancestor whose type imports the text type (a `String` destination, a `Transferable` with a text fallback) now takes a text clipboard instead of the field pasting it. Give such a destination a validator that returns `[]` for what the field should keep, or put the destination on a type that does not import text.

