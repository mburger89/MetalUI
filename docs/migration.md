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

### Migrate inside-out

A SwiftUI-vocabulary element can sit inside a legacy container
(`Row { HStack { … } }` works). The reverse does not compile: `HStack`,
`VStack`, `ZStack`, `Grid`, `ForEach` inside a proposal container and every
proposal modifier take `ProposalElementGroup` content, so `HStack { Box() }`
is a compile error (guards `aForEachOfLegacyContentDoesNotCompileInsideAProposalStack`,
`aGridRejectsLegacyContent`). Convert the innermost subtrees first, then their
parents.

### Containers

| legacy | SwiftUI vocabulary | what changes |
|---|---|---|
| `Row { … }` | `HStack { … }` | **spacing**: `Row`'s default gap is **0**, `HStack`'s default is SwiftUI's 8 between adjacent views (divergence 52, kept, `CX-E`) — write `HStack(spacing: 0)` to keep the old look, or accept 8. Both centre on the cross axis. `Row(gap: g)` → `HStack(spacing: g)` |
| `Column { … }` | `VStack { … }` | as `Row`/`HStack` |
| `Row`'s `.flexGrow(1)` child | a `Spacer()` beside it, or `.frame(maxWidth: .infinity)` on it | a greedy frame takes the surplus (`CN-B`); equal growers already shared equally |
| `.justifyContent(.spaceBetween)` etc. | `Spacer()`s between the children | the lowering already uses spacers (`LR-AB`) |
| `.alignItems(…)` on a `Row`/`Column` | `HStack(alignment:)`/`VStack(alignment:)` | typed alignment: `VerticalAlignment` for an `HStack` (`.top`, `.center`, `.bottom`, `.firstTextBaseline`, `.lastTextBaseline`), `HorizontalAlignment` for a `VStack` (`CN-I`) |
| `.alignSelf(…)` on one child | `.frame(maxWidth: .infinity, alignment: …)` on that child | SwiftUI has no per-child cross alignment; a frame aligns its content |
| `Stack(alignment:) { … }` | `ZStack(alignment:) { … }` | both now offer each child the proposal (divergence 53 retired, `CX-R`); `ZStack`'s alignment is a `ProposalAlignment` |
| `Box { … }` (one child, a background, padding) | the child with `.padding(…)`, `.background(…)`, `.frame(…)` | a `Box` stretches its children on the cross axis (`EP-8`); the replacement is the modifiers, in SwiftUI's order |
| `Box(decoration: d) { … }` | `.background(token)`, `.border(token, width:)`, `.clipShape(…)` on the content | |
| `ScrollView(.vertical) { … }` | `ProposalScrollView(.vertical) { … }` | the legacy `ScrollView` takes its **parent's** cross size, `ProposalScrollView` its **content's** (divergence 54, kept). Both share one chrome (indicators, clamping) |
| `List(data, rowHeight:) { … }` | (no SwiftUI-vocabulary `List`) | `List` stays MetalUI's virtualized, uniform-row list; it needs an enclosing scroll view (divergence 84, kept). For a short list, `ProposalScrollView { VStack { ForEach(data) { … } } }` |
| `Text("…")` | `ProposalText("…")` | the same text system, fonts and modifiers (`.font`, `.lineLimit`, …). `text.proposalLayout()` converts one, **dropping** its background, handlers, id and hover/focus colours |
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
| an RGB colour (`Color(r, g, b)`, `Hsla.rgb(0x…)` in `paint`) | `Color(red: 0.2, green: 0.4, blue: 0.6)`, `Color(.sRGB, red:…)`, `Color(.sRGBLinear, red:…)`, `Color(white: 0.5)`, `Color(hue:saturation:brightness:)`, `Color(Hsla.rgb(0x336699))` | gamma sRGB as SwiftUI (`CR-C`); drawn on a Display P3 layer like every MetalUI colour (divergence 1) |
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
| `.task { await … }`, `.task(id:) { … }` | **not offered** — start the async work from `.onAppear` and cancel it from `.onDisappear`: `.onAppear { monitor = Monitor(); monitor?.start() } .onDisappear { monitor?.stop() }` | a main-actor `Task` never runs inside `Backends/SDL`'s loop, which does not drain the main queue (probe `swift-main-actor-task-loop.swift` `B1`, macOS and Linux), so `.task` would start on macOS and silently never on Linux/Windows; owner: the SDL run loop's main-queue drain (`LC-L`) |
| `Text("a").onAppear { … }.onTapGesture { … }`, `.padding()` after it — any order | write `Self`-returning legacy decorations (`.onClick`, `.background(_:)`, `.padding(_:)`, …) **before** the lifecycle modifier: `Text("a").onClick { … }.onAppear { … }`; `.frame`, `.id`, `.overlay` and the typed vocabulary's modifiers may follow it | the scope is a transparent `ElementGroup`, like `.animation(_:value:)` (divergence 120); for the same reason a window's root cannot be one — `openWindow(…) { Column { content.onAppear { … } } }` |
| a chain of actions (an `onAppear` whose write inserts content whose own `onAppear` writes) settles before the first draw | the first level's writes are presented in the same frame (one settle build); each later level's one frame later — never a loop | divergence 121 (`LC-E` item 3) |
| a modifier on a `ForEach` or `Group` | the same — it fires **once for the group**, not per child, and only while the group has content: an empty `ForEach` does not appear; it appears with its first row and disappears with its last | as SwiftUI (`A6`, `A6b`; `LC-P` item 1); write the modifier on the row inside the `ForEach` for per-row callbacks |
| `@State var monitor = Monitor()` started in `onAppear`, stopped in `onDisappear` | write the instance in `onAppear` (`@State var monitor: Monitor? = nil`), or hold it in an `@Observable` model | a never-written `@State` default is re-seeded every build, so the two actions would reach different instances (divergence 125) |

Order is one rule (changes, then appears, then disappears, each children
first — divergence 122); a disappearance under a removal transition runs when
the fade ends; a `List` row leaving its window disappears, and a `List`'s
first frame appears every row once (divergence 124); closing a window runs
every present `onDisappear` once (`LC-J`).

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
| a `PlatformWindow` conformer outside the package | implement `onAccessibilityRequest`, `publishAccessibilityTree(_:)`, `controlActiveState`/`onControlActiveStateChange`, `accessibilityReduceMotion`/`onAccessibilityReduceMotionChange`, and, since drag and drop, `beginExternalDrag(_:at:)` (answer `false` where the platform has no outgoing drag) — none has a default | `AB-R`, `EV-AB`, `AN-AD`, `DN-C` |
| an exhaustive `switch` over `PrimitiveKind` | add a `.surface` arm (an app-owned GPU surface's quad, drawn by the image pipeline over its render target) | `MV-C` item 3 |
| a `WindowRenderer` conformer outside the package implementing `finishFrame(scene:atlas:)` | implement `finishFrame(scene:atlas:surfaces:)` (no default); a renderer with no surface support may ignore `surfaces` and composites nothing for surface runs. **Callers** of `finishFrame(scene:atlas:)` compile unchanged (it forwards `surfaces: []`) | `MV-F` item 1, `MV-K` item 3 |
| a `Platform` conformer outside the package | implement `setApplicationIcon(_ images: [ImageTexture])` (an empty body is honest where the platform has no runtime icon) — no default | `AI-B` |
| an exhaustive `switch` over `LayoutModifier` | add `.rotationEffect`, `.scaleEffect`, `.offset` and `.shadow` arms (or `default:`) — paths, shadows and transforms | `GX-H`, `GX-J` |
| an exhaustive `switch` over `ColorToken` | add a `.shadow` arm (black at 0.33 in both themes). A custom `Theme(background:…scrim:)` compiles unchanged: `shadow:` is a trailing defaulted parameter | `GX-J`, `GX-Q` |
| `MUIGlyph(… _reserved: 0)` (the C struct's memberwise initialiser) | `transform: 0` — the word is renamed, still 0 for an untransformed glyph; the bridging `MUIGlyph(bounds:slot:contentMask:…)` initialiser is unchanged | `GX-F` |
| a `PlatformWindow` conformer outside the package (menus) | implement `presentMenu(_:at:) -> Bool` (answer `false` where the platform has no menu API; `Window` then draws the menu) — no default | `MN-C` item 1 |
| an exhaustive `switch` over `InputEvent` | add `.rightMouseDown`, `.rightMouseUp` and `.menuAction` arms (or `default:`) | `MN-B` item 1, `MN-C` item 4 |
| a `Platform` conformer outside the package (menus) | implement `setMenuBar(_ menuBar: PlatformMenuBar)` (an empty body, or recording it, is honest where the platform has no menu bar) — no default | `MN-I` item 3 |
| an exhaustive `switch` over `AccessibilityRole` or `AccessibilityRequest` | add `.menu`, `.menuItem`, `.menuItemCheckBox`, `.menuButton`, `.popover` and `.showMenu(_:)` arms (or `default:`) | `MN-R` |
| a stored colour property read **as a `ColorToken`** — `Decoration.background`/`hoverBackground`/`focusBackground`, `BorderStyle.color`, `Background.color`, `Rectangle.color`, `Text`/`ProposalText`/`TextField`/`TextEditor.foregroundColor`, `OnTapModifier.hoverColor` are now `Color`/`Color?` | a write (`x.background = .surface`) and a comparison (`rect.color == .accent`) compile unchanged; a `switch` or `theme[x]` over the value becomes `pass.resolve(x)` in paint, or a comparison against `Color(.token)` | `CR-E` item 3 |
| `LayoutModifier.background`, `.border`, `.shadow` payloads as `ColorToken` | they are `Color`: a leading-dot construction (`.background(.accent)`) compiles unchanged; a `ColorToken` variable in a payload becomes `Color(token)`, and a pattern that uses the bound payload as a token reads it with `pass.resolve(_:)` | `CR-W` item 1 |
| a `PlatformWindow` conformer outside the package (colour scheme) | implement `func setPreferredColorScheme(_ colorScheme: ColorScheme?)` — an empty body, or recording the value, is honest where the platform has no per-window appearance; no default | `CR-M`, `CR-Y` item 6 |
| `.borderWidth(_:)` | `.border(_:width:)` | `OM-M` |
| `width(percent:)`/`height(percent:)` taking a fraction | `.frame` (they were renamed `fraction:` then deprecated) | `CN-O`, `CX-C` |

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

### Behaviour changes (compile unchanged, answer differently)

| change | what to do | ruling |
|---|---|---|
| **The layout engine is SwiftUI's** (stage 6b, stage 9): every element lowers onto the propose/measure/place kernel; a root is centred at its own answer | nothing; layouts that relied on CSS shrink weights, percentage sizes or the CSS root rule now answer as SwiftUI (or trap by name where no answer exists) | `LR-DF`, `LR-FC`, `CN-J`, `LR-FO` |
| an `if` with no `else` and a `for` loop each take **one structural slot**; a vanishing `if`'s trailing sibling keeps its own state | code that built a `GlobalElementID` through an `if`/`for` by hand adds the slot level | `ID-B` |
| content an evaluated conditional removes is **reset on return** (state, scroll, selection, `$anim`) | keep values that must survive in data or above the `if` | `ID-C` |
| a `for`/`ForEach` element that disappears and returns starts fresh | as above | `DD-C` item 4 |
| a name an evaluated position leaves starts fresh when it returns | as above | `ID-R` |
| **focus leaves with its identity and does not come back** | refocus on return from input (`Window.focus(id)`) or by writing the `@FocusState` | `IX-I` |
| a hidden element is out of the keyboard's focus half (a hidden `Button`'s shortcut still fires) | — | `IX-K` item 3 |
| the wheel over a click target inside a scroll view **scrolls the scroll view** | — | `DD-Y` |
| a `List` windows against its own origin: a header above it no longer blanks it | the "only child of its scroller" requirement is gone | `DD-F` |
| `controlSize` reaches every text's default font and `Button`'s chrome | an explicit `.font` is unaffected | `TE-F`, `DD-R` |
| a whole-value `Window.environment` write resets `displayScale` to 1 (`pixelLength` follows) | — | `EV-AA` |
| the legacy paint-only fields (opacity, border widths and colour) and every proposal `LayoutModifier` **animate** under a transaction | wrap in `withTransaction(Transaction(animation: nil))` or `.transaction { $0.animation = nil }` to snap | `AN-AA`, `AN-AB` |
| a `Component`'s caller modifier animates per member | — | `AN-AC` |
| a press under `allowsHitTesting(false)` is advertised to and run by an accessibility client | — | `IX-Z` |
| **an optional `@State` with a non-`nil` default reads it before its first write** (it read `nil`); the public `withState(_:initial:_:)` over an optional likewise returns `initial` for an absent entry | workarounds that wrote the value first are unaffected | `CX-F`, `CX-Q` item 1 |
| a legacy frame's `idealWidth`/`idealHeight` answer an unspecified axis (they trapped) | — | stage 9, `CX-R` |
| **on AppKit a control-click is a secondary press** (`MetalHostView`, lane 2): it no longer presses a `Button` or runs an `onClick`, tap or drag — it opens a context menu, or does nothing (SwiftUI's right click presses a `Button`, divergence 110). Off Apple a ctrl-click stays a primary press (`List`'s toggle) | bind the action to a context menu item, or test the primary press's modifiers | `MN-AC` item 1, `MN-B` item 4 |
| **an AppKit app has a menu bar** — every `App` installs `NSApp.mainMenu` (About, Hide, Quit; File ▸ Close; Edit; Window), so ⌘Q, ⌘H, ⌥⌘H, ⌘W and ⌘M act when nothing in the window claims them, and Edit ▸ Cut/Copy/Paste/Undo reach a focused `TextField`/`TextEditor` as their keys. SDL draws no bar | bind the key in the window (a `Button`'s `.keyboardShortcut`, a keymap binding or `onKey` still wins, `MN-J`), or replace a group with `App.commands { CommandGroup(replacing:) { } }` | `MN-I` item 4, `MN-K` |
| **AppKit ⌘-keys arrive through `performKeyEquivalent`** — offered to the window before the main menu, once per event — and reach the same `onInput` pipeline as before | nothing; a ⌘-key is still one `.keyDown` | `MN-J` item 3 |
| **a key an app command binds is claimed by the command stage** (after a `Button`'s shortcut, before Tab traversal): it no longer reaches Tab traversal or the window's `onInput` fallback | bind it in the window to keep it there | `MN-J` item 1 |
| **`Appearance` is `ColorScheme`** (a typealias, not deprecated): `PlatformWindow.appearance`, `Theme.forAppearance(_:)` and every `Appearance` spelling compile unchanged | write `ColorScheme` in new code | `CR-J` item 1 |
| **the window's theme follows its colour scheme through `lightTheme`/`darkTheme`** (defaults `.light`/`.dark`, so an uncustomised window paints as before); a forced `.preferredColorScheme` now also selects the variant | customise `window.lightTheme`/`darkTheme` (or `App`'s) instead of re-assigning `theme` on an appearance change; a direct `window.theme = …` still lasts until the next scheme change | `CR-K`, `CR-Z` item 2 |
| `.opacity(0.5)` written on a `Color` **view** with a literal argument is the value method: one fill at half alpha and **no opacity layer** (it was an opacity layer, one identity level) | nothing — a `Color` holds no state; pass a `Float` to reach the view modifier | `CR-G` |
| design spec §7.9's "never literals" is superseded: literal colours are part of the API | — | `CR-B` |
| a `Shape` conformer that implements **neither** `geometry(in:)` nor `path(in:)` compiles (both are now defaulted, each in terms of the other) and **traps at its first paint naming `GX-D`** — where it failed to compile | implement either; SwiftUI shapes port by writing `path(in:)` (its rect is local, origin (0, 0)) | `GX-D` |

## See also

- [`api-overview.md`](api-overview.md) — the public surface by area.
- [`divergences.md`](divergences.md) — every remaining difference from SwiftUI.
- [`verification/human-checks.md`](verification/human-checks.md) — the looks
  that still need a human.
