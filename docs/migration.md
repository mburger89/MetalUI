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
| `.background(token)` | `.background(token)` | |
| `.cornerRadius(r)` | `.cornerRadius(r)` / `.clipShape(RoundedRectangle(cornerRadius: r))` | the legacy one rounds fill and border and clips nothing; the proposal one clips, as SwiftUI's (divergence 47) |
| `.border(token, width:)` | `.border(token, width:)` | the legacy band follows a corner radius; the proposal band is square (divergence 49) |
| `.clipped()` / `.clipShape(s)` | `.clipped()` / `.clipShape(s)` | |
| `.opacity(x)` | `.opacity(x)` | what is written after it escapes it, on both (`LR-FW`) |
| `.allowsHitTesting(b)` | `.allowsHitTesting(b)` | |
| `.contentShape(…)` | `.contentShape(…)` / on `.onTap`, `.gesture` | |
| `.onClick { }` | `Button { } label: { }`, or `.onTap { }` / `.onTapGesture { }` | `onClick` is press-and-release-on-one-element (Button semantics); `.onTapGesture` is SwiftUI's tap gesture (`IX-B`) |
| `.hoverBackground`, `.focusBackground`, `.focusBorder` | (MetalUI-only) | |
| `.onKey`, `.onAction`, `.keyContext`, `.focusable()` | (MetalUI-only; the keymap) | `.focused(_:)`/`@FocusState` for focus state |

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
| a `Shape` conformer that implements **neither** `geometry(in:)` nor `path(in:)` compiles (both are now defaulted, each in terms of the other) and **traps at its first paint naming `GX-D`** — where it failed to compile | implement either; SwiftUI shapes port by writing `path(in:)` (its rect is local, origin (0, 0)) | `GX-D` |

## See also

- [`api-overview.md`](api-overview.md) — the public surface by area.
- [`divergences.md`](divergences.md) — every remaining difference from SwiftUI.
- [`verification/human-checks.md`](verification/human-checks.md) — the looks
  that still need a human.
