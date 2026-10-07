# Port gaps, medium — decisions

Rulings for four medium gaps the SMK configurator port logged (user request
2026-10-02, an item of the gpui-gap priority list — **MG-20** field chrome,
**MG-14** `layoutPriority` on the legacy stacks, **MG-2** environment objects,
**MG-3** window toolbar; **not a plan task**), written up in
`~/Developer/worktrees/smk_configurator/metalui-port/docs/superpowers/2026-10-06-metalui-gaps.md`.
Spec: [`specs/2026-10-07-port-gaps-medium-design.md`](specs/2026-10-07-port-gaps-medium-design.md).
Record: `../record/79-port-gaps-medium.md`. Evidence:

- [`../probes/swiftui-field-chrome.swift`](../probes/swiftui-field-chrome.swift)
  (arms `AC0`, `SZ0`–`SZ6b`, `CS1`–`CS3`, `ED1`/`ED2`, `NS` per style and
  `ENV1`–`ENV3`, `PX0` and `PX` light/dark per style, `ED`, `ED2`, `TX`).
- [`../probes/swiftui-environment-object.swift`](../probes/swiftui-environment-object.swift)
  (arms `N0`–`N3`, `O1`/`O2`, `K1`–`K2b`, `W1`, `R`, `T`).
- [`../probes/swiftui-toolbar.swift`](../probes/swiftui-toolbar.swift)
  (arms `TB0`, `TB1`, `UP`, `SR`, `GEO`).
- The design session's MetalUI measurements at `d48b26d` (a scratch test, not
  committed; outputs quoted in `MD-G`).
- gpui (where SwiftUI is not the comparison): `crates/gpui/src/platform.rs`
  on zed `main`, read 2026-10-06 — `WindowOptions.titlebar:
  Option<TitlebarOptions>` with `TitlebarOptions { title,
  appears_transparent, traffic_light_position }`, and no toolbar API; Zed
  draws its own title bar inside the window.

Every probe header carries its recorded output and how to run it (`SA-O`).

Prefix **`MD-`**, lettered. **Next unused: `MD-R`.** (This line moves in the
commit that appends a ruling; read the last `## MD-` heading.)

Branch `feat/port-gaps-medium` from `d48b26d` (master: proposal controls
merged, PR #49). Baseline re-taken by the design session at `d48b26d` — see
the spec §0.

**Carried items.** `PE-C` item 4 (a legacy item field in a proposal container
is reported `<site>.<field>.unconsumed`), `PE-D` (greedy field width), `PE-F`
(`layoutPriority` on legacy content), `PE-R` (style modifiers written on the
control), `IX-G`/`IX-H` (`ControlLook.swift`), `EV-A`/`EV-B`/`EV-V`/`EV-X`
(scopes), `RX-K` (the build is tracked), `MN-D`/`MN-F` (closed menu content,
the drawn fallback), `CR-L`/`CR-Q`/`CR-T` (window-wide collection, the second
build, the main tree wins), `LR-AB`…`LR-AQ` (item records), `LR-CH`
(presentation roots), `AI-E` (premultiplied textures to AppKit), `TI-E`
(caret positions only from `caretOffsets`).

---

## MD-A — Scope, lanes, and what is already done

**Found.** Measured at `d48b26d` (spec §1.2): MG-14's own reproduction
already works — `PE-F` (PR #49, after the gap list's pin `e54c3f6`) gave
`.layoutPriority` to legacy content, and a legacy `Column` serves the drawer
first (530 of 800, the board 254). What does **not** work is a prioritised
child that also carries a legacy item field or relies on its parent's
stretch: the field traps as `text.flexGrow.unconsumed`, and a `Box`'s stretch
is silently lost (11×16 where the unprioritised child is 11×100).

**Ruling.** Four parts, three lanes, run in order:

1. **Lane 1 — field chrome** (MG-20): `TextFieldStyle`, `TextEditorStyle`,
   the chrome and its default (`MD-B`…`MD-F`).
2. **Lane 2 — layout priority and environment objects** (MG-14's remainder,
   MG-2): `MD-G`, `MD-H`. Two small parts sharing a lane because neither
   touches the other's files.
3. **Lane 3 — window toolbar** (MG-3), far the biggest, alone, plus the demo
   (`MD-I`…`MD-N`).

File ownership is disjoint by lane (spec §8). Files two lanes must both touch
(`docs/divergences.md`, the inventory map, the census, demo-tree tests) are
**serialized**: the earlier lane commits first, the later lane edits on top;
divergence labels are pre-allocated (`MD-P`).

**Cost if wrong.** A lane that finds its part already done builds nothing;
the scratch measurement is in the spec so a lane re-takes it first.

---

## MD-B — `TextFieldStyle`: SwiftUI's four, spelled on the field and on a container

**Evidence.** `NS` arms: SwiftUI's default (`none`) and `.automatic` host the
same bezeled `NSTextField` (`bezeled=true bezelStyle=0`, 120×24), as does
`.squareBorder`; `.roundedBorder` is `bezelStyle=1`; `.plain` is unbezeled,
no background, no focus ring (`focusRing=1`, `.none`). `ENV1`: a
`.textFieldStyle(.plain)` on a `VStack` reaches the field inside it; `ENV2`/
`ENV3`: the innermost style wins.

**Ruling.**

1. `public struct TextFieldStyle: Equatable, Sendable` — a **closed** struct
   with an internal initialiser and four statics: `.automatic`,
   `.roundedBorder`, `.squareBorder`, `.plain` — `ButtonStyle`'s shape
   (`IX-E` item 2) and its correction (`IX-O` 7): SwiftUI's is a protocol;
   every call site spells identically; custom styles are not offered.
2. **Two spellings.** `TextField.textFieldStyle(_:) -> TextField` (a value
   modifier, so `.background`, `.frame`, `.onSubmit` still chain — `PE-R`)
   and `ElementGroup.textFieldStyle(_:) -> EnvironmentScope<Self>` (an
   internal environment value, so a container's style reaches every field
   below — `ENV1`). A field's own style wins over the environment's; the
   environment's nearest writer wins (`EV-A`) — together SwiftUI's
   innermost-wins (`ENV2`, `ENV3`). The environment key is internal (SwiftUI
   has no public `textFieldStyle` key).
3. `TextEditor` reads no `TextFieldStyle` (SwiftUI's `TextEditor` has its own,
   `MD-F`).

**Cost if wrong.** A container form that did not propagate would make the
port write the style on every field; a missing value form would make
`.textFieldStyle(.plain).background(…)` fail to compile.

---

## MD-C — The default is the bordered field, for both vocabularies

**Evidence.** `SZ1`, `SZ2`, `SZ3`: no style, `.automatic` and
`.roundedBorder` answer identically (ideal 47.50×24 for the placeholder
"Name", `inf → inf×24`); `NS none` = `NS automatic`. `PX`: the three bordered
styles draw byte-identical pixels, light and dark. **No demo image holds a
`TextField`**: `grep -n "TextField\|TextEditor" Sources/MetalUIDemoContent/*.swift`
finds them only in `textInputDemoContent()`, `controlsDemoContent()` and
`menusDemoContent()` — none of the fourteen `compare.sh` images
(`demoContent()`, `nativeLayoutPreviewContent()`, `CounterPanel`) and not
`DemoFrameDeterminismTests`' tree (`demoContent()`).

**Ruling.** `.automatic` resolves to the bordered chrome on every platform,
and it is every field's default — **the legacy `TextField`'s default changes**
(there is one `TextField` type; the proposal path adopts it through
`LegacyContent`, so "keep the legacy default and give the proposal path
SwiftUI's" is not expressible without two types). Consequences, each named:

1. **Pixels:** none of the fourteen images moves (no field in any); the
   demo-pixel run must read 0, and `Expected.swift` stays unedited.
2. **Sizes:** a default field is 8 points taller and 12 points wider at its
   ideal (`MD-D`). Every test whose literal moves is named by lane 1 in its
   record section and handled by one rule: a test **whose subject is text
   input, focus, binding, identity or accessibility** (its literal is a text
   coordinate or a size it does not test) gains `.textFieldStyle(.plain)` —
   the old field exactly — so its subject is unchanged; a test **whose subject
   is a field's size or a layout containing one** takes the new literal, derived
   by hand from `MD-D`. No test is deleted.
3. **Migration note** (`docs/migration.md`, lane 1): "`TextField` now draws
   SwiftUI's bordered field and is 24 points tall; `.textFieldStyle(.plain)`
   restores the previous field; drop an app-side field-chrome helper."

**Cost if wrong.** Keeping the chrome-less default would leave every port
writing a helper (MG-20's whole complaint); the cost of this ruling is the
literal churn in item 2, bounded and named.

---

## MD-D — Chrome geometry: insets from the probe, MetalUI's own ideal kept

**Evidence.** `NS roundedBorder`: frame 120×24, the cell's drawing rect
(4, 4, 112, 16); `NS plain`: the AppKit field is 2 points wider on each side
than SwiftUI's frame (−2, 0, 124, 16), its text starting at SwiftUI's edge.
`SZ`: bordered ideal = `Text` width + 12 (47.50 = 35.50 + 12; 43 = 31 + 12;
empty 12); plain ideal ≈ text + 4 (39.25, 34.95; empty 4); bordered height 24
= 16 + 8, plain 16. `CS1` small: 21 tall at an offered width (22 ideal),
font 11, drawing rect inset 3.5 vertically; `CS3` mini 19; `CS2` large 24
(macOS 27: large = regular).

**Ruling.**

1. Bordered (`.automatic`, `.roundedBorder`, `.squareBorder`): content insets
   **6 leading and trailing** (the drawing rect's 4 + AppKit's 2-point line
   fragment padding, matching the +12) and **4 top and bottom**, except
   `.small`, 3.5 (`CS1`). Ideal width = MetalUI's own ideal (text or
   placeholder + 1 for the caret, divergence 131 unchanged) + 12; height =
   one line + 2 × the vertical inset. An offered width is still taken whole
   and an infinite one answers infinity (`PE-D` unchanged): the chrome is
   inside the offered width.
2. `.plain`: exactly today's field — no inset, today's ideal and height. (The
   probe's plain +4 is AppKit's line fragment padding outside SwiftUI's frame;
   MetalUI's +1 caret allowance stays, divergence 131.)
3. Text, caret, selection and marked text are laid out in the **inset**
   rect: `geometry(bounds:…)` receives the content rect, so `TextInputTarget`
   (origin, caret rect) and the clip follow it. **No text-input logic
   changes** — caret offsets still come only from `caretOffsets` (`TI-E`);
   the scroll-to-caret width is the content width.
4. `controlSize` keeps reaching the field's font (`TE-F`); the inset table is
   by control size (regular/large/extraLarge 4, small 3.5, mini 4).

**Cost if wrong.** A wrong inset is a few points of layout per field and a
caret drawn off its glyph by the same amount — the test in spec 1.6 reads
both.

---

## MD-E — Chrome look: theme tokens, the control focus ring, the measured disabled look

**Evidence.** `PX` corner grids: the bordered field's corner curve spans ~12
device pixels at 2× — a radius of about **6 points**; the fill starts at the
frame's edge; a faint 1-pixel edge lies just *outside* the frame (light:
black at 15 %; dark: white at 9 %); the fill is near-white at 97.6 % (light)
and ≈ #171717 at 97.6 % (dark). `PX disabled` reads byte-identical to
`PX default` (empty field): the chrome does not change when disabled. `TX`:
a field holding "WWWW" draws its darkest pixel #212121 enabled and #B5B5B5
disabled — the text dims to about a third. The focus ring is **not
measured**: `cacheDisplay` draws none (`PX focus` reads the unfocused runs).

**Ruling.**

1. Bordered chrome: a fill in `.surface`, a **1-point `.separator` border
   inside the bounds**, corner radius **6** — the same three draw identically
   (`PX`), so `.squareBorder` is rounded too, as SwiftUI draws it on macOS 27.
   Drawn inside `paintDecoration`'s content closure (`DN-X`/`OM-AI` unchanged),
   so a caller's `.background` paints beneath it and a caller's `.border`
   over it.
2. Focus ring (bordered only — `.plain` is `focusRing=.none` in `NS plain`):
   `controlRing(_:)`'s 2-point border in `controlAccent(_:)` (accent when the
   window is key, `.separator` otherwise — `IX-H`), at radius 6, drawn while
   `pass.isFocused(id)`. A caller's `focusBorder` still wins (`IX-H` item 2).
3. Disabled (`isEnabled == false`): chrome unchanged (`PX disabled`); the
   text, placeholder and caret colour alpha × **0.33** (`TX`: ≈ 0.29/0.87).
   Not `paintControl`'s whole-subtree fade (`ControlLook.swift`'s comment
   "`TextField`/`TextEditor` do not take it" stays true and gains the reason).
4. The look's colours are MetalUI's tokens, not AppKit's bezel (the outside
   edge, the 97.6 % fill, the unmeasured outer focus glow): **divergence
   132**.

**Cost if wrong.** A look difference only; the human check `W1` is where it is
judged.

---

## MD-F — `TextEditor`: SwiftUI's opaque text background, nothing else

**Evidence.** `ED`: SwiftUI's `TextEditor` is an `NSScrollView` with no
border (`borderType=0`) over an `NSTextView` drawing `textBackgroundColor`
(`PX TextEditor`: opaque white / #1E1E1E, square corners); text container
inset 0, line fragment padding 5, font 12. `ED2`: `.textEditorStyle(.plain)`
draws no background. `ED1`: sizes unchanged by any of this (ideal 0×12, greedy
both axes).

**Ruling.**

1. `public struct TextEditorStyle: Equatable, Sendable`, closed, statics
   `.automatic` and `.plain` (SwiftUI's macOS 14 pair), with
   `TextEditor.textEditorStyle(_:) -> TextEditor` and
   `ElementGroup.textEditorStyle(_:) -> EnvironmentScope<Self>` (`MD-B`'s
   precedence).
2. `.automatic` (the default): a `.surface` fill over the bounds, square, no
   border; and, while focused, the control focus ring (`MD-E` item 2) at
   radius 0 — MetalUI's choice (the ring is unmeasured). `.plain`: neither.
3. **No size and no text placement change**: SwiftUI's 5-point line fragment
   padding and 12-point font are not adopted — divergence **133** — so every
   `TextEditor` test literal stands.

**Cost if wrong.** A look difference; human check `W2`.

---

## MD-G — A legacy container sees through a `layoutPriority` layer

**Evidence.** The design session's scratch test at `d48b26d`
(`LayoutDifferential.report`, diagnostics on):

- `Column(gap: 16) { greedy.frame(minHeight: 240, maxHeight: .infinity);
  drawer.frame(minHeight: 260, maxHeight: 530).layoutPriority(1) }` at
  300×800: drawer 530, greedy 254 (without the priority: 392 and 392). MG-14's
  reproduction is already served.
- `Box { Text("hi").layoutPriority(1); Text("other") }` at 300 wide, 100 tall
  (a row; `Box` stretches, `EP-8`): `hi` is **11×16**; without the priority
  **11×100**. The layer has no `LoweredItem` record, so the box plans nothing
  for it — the stretch is lost silently.
- `Row { Text("a").flexGrow(1).layoutPriority(1); Text("b") }`: reports
  `text.flexGrow.unconsumed` (a production trap) — the inner record is never
  consumed.

SwiftUI has no item fields; the question is MetalUI's own consistency
(`LR-AB`: item fields are lowered by the parent).

**Ruling.**

1. **Forwarding.** The `layoutPriority` layer, when its content's node carries
   a `LoweredItem` record, moves that record to the layer's own node,
   remembering the content's node as its **origin** (a new
   `LoweringState.forward(_:to:)`). Only `layoutPriority` forwards:
   `fixedSize` and the grid-cell modifiers change the child's proposal or its
   cell, and a legacy item field under them keeps reporting (unchanged).
2. **Planning.** A legacy container consumes the forwarded record exactly as
   it would the original — its fields plan the item frame, stretch,
   `fixedSize`, alignment frame and margin as for the unwrapped child — and
   `registerLegacyItems` wraps the layer's node.
3. **The lift.** Because a frame or padding hides a priority (`L2`; the
   kernel's `nativeLayoutPriority` reads only the stack's direct child), a
   child whose plan registered any wrapper and whose record came through a
   priority layer gets **one more node, outermost**: `layoutPriority(p)` with
   the outermost layer's value. The inner layer node stays (harmless inside a
   frame). No identity level is added: nodes are not ids (`MC-A`/`MC-C`
   unchanged).
4. **Alias.** An item frame aliases the **origin** element node (`LR-AB` item
   3), not the layer: the stretched `Text` paints, hits and wraps at the item
   frame's size.
5. **In a proposal container** the forwarded record is not consumed and is
   reported at its original site under its original name — `PE-C` item 4
   exactly (`HStack { Text("a").flexGrow(1).layoutPriority(1) }` still reports
   `text.flexGrow.unconsumed`).
6. No new `Style` read: the priority is not a `Style` field, so no animated
   arm is owed (`LR-AS`); the lowering's structure reads nothing new.

**Cost if wrong.** A forwarded record nobody consumes would silently lose a
field — item 5's test pins that it still reports; a missing lift would make
the priority inert exactly when the child has a field.

---

## MD-H — `@Environment(Type.self)` and `.environment(_ object:)`

**Evidence.** `N0`–`N3`: nearest writer wins, two types coexist, a sibling
outside the writer reads none. `O1`/`O2`: the optional form reads nil without
a writer. `K1`/`K1b`/`K2`/`K2b`: an object is found by the **static type it was
written as** — written as `Sub`, read as `Base?` → nil; written `as Base`,
read as `Sub?` → nil. `W1`: `.environment(nil as Base?)` below a writer
clears it. `R`: a body re-runs on a write to a property it read (1) and not to
one it did not (0). `T`: a non-optional read with no writer traps (signal,
status 5) with `Fatal error: No Observable object of type Base found. A
View.environmentObject(_:) for Base may be missing as an ancestor of this
view.`

**Ruling.**

1. **API (SwiftUI's).** `Environment.init(_ objectType: Value.Type) where
   Value: AnyObject & Observable` and `Environment.init<T: AnyObject &
   Observable>(_ objectType: T.Type) where Value == T?`;
   `ElementGroup.environment<T: AnyObject & Observable>(_ object: T?) ->
   EnvironmentScope<Self>`.
2. **Storage.** `EnvironmentValues` gains an internal object table keyed by
   `ObjectIdentifier(T.self)` — the static type (`K`); a `nil` write removes
   the entry (`W1`). `Environment` stores a reader closure in place of its
   key path (`init(_ keyPath:)` builds one; public behaviour unchanged) —
   `swift package clean` after the change (a stored property of a public
   type crossing a module boundary).
3. **Binding is `@Environment`'s** (`EV-M`, `EV-O`, `ID-E`, `ID-F`): the same
   reflection bind, so a `Component` (bound once in layout), an `Element`
   (per phase), `AnyElement`, `Deferred` and popover content (which inherit
   their declaring scope, `EV-G`) all read their position's object. The
   window root's restriction stands (`EV-B`): write the scope inside the
   root's first container, as the port's `rootView` already does.
4. **Missing object.** A non-optional read with no writer — or an unbound
   wrapper read outside a frame — traps with `No Observable object of type
   <T> found. An .environment(_:) for <T> may be missing as an ancestor of
   this element.` SwiftUI's sentence with MetalUI's modifier and noun:
   divergence **134**. The optional form reads `nil` in both cases.
5. **Observation** needs nothing new: the frame build is tracked (`RX-K`), so a
   property read through the object inside a phase dirties the window on a
   write, and an unread property does not (`R`). `Window.environment` gains no
   object API (SwiftUI has none).
6. Not offered: `@Bindable` (owner: the gpui-gap list) and
   `ObservableObject`/`@EnvironmentObject`/`.environmentObject` (Combine;
   owner none) — rows in `docs/divergences.md`'s "Not offered".

**Cost if wrong.** Keying by the dynamic type would find an object SwiftUI
does not (`K1`); a silent default instead of a trap would hide a missing
writer.

---

## MD-I — `.toolbar { … }`: SwiftUI's spelling, a closed item set, collected window-wide

**Evidence.** `TB1`: a `.toolbar` on the root view of a hosting controller
bridged to its window produces a real `NSToolbar` with one item per
`ToolbarItem`; its items host SwiftUI's own views (`ToolbarItemHostingView`,
AppKit-backed for the segmented picker and the text field). `SR`:
`.searchable(text:)` adds `com.apple.SwiftUI.search` (an
`NSSearchToolbarItem` subclass) at the trailing end.

**Ruling.**

1. `ElementGroup.toolbar<C: ToolbarContent>(@ToolbarContentBuilder content:
   () -> C) -> ToolbarScope<Self>` — a transparent scope (no node, no id
   level, no `Element` hook, `Handlers` unchanged — `LifecycleScope`'s shape,
   `LC-`), on both vocabularies (proposal content stays proposal content).
2. `ToolbarContent` is **closed** (`MN-D`'s SPI requirement):
   `ToolbarItem(id:placement:content:)`, `ToolbarItemGroup(placement:content:)`,
   `if`/`switch`/`for` through `@ToolbarContentBuilder`. Placements
   (`ToolbarItemPlacement`): `.automatic`, `.navigation`, `.principal`,
   `.primaryAction`, `.status` — the five the probe placed.
3. Item content is **closed** (`ToolbarItemContent`, SPI): `Button` with a
   `Text` or `Image` label, `Toggle` with a `Text` label, `Picker` in
   `.menu` or `.segmented` style, `TextField`, and `Text` (a label, `.status`'s
   usual content). SwiftUI takes any view: **divergence 135**.
4. `ElementGroup.searchable(text: Binding<String>, prompt: String = "Search")`
   adds one search item, trailing, last.
5. **Evaluation.** The closure runs once per build, in layout (`EV-V`'s
   precedent), reading bindings fresh; contributions are collected
   window-wide in build pre-order and merged in that order. A `.toolbar`
   inside a `Deferred` presentation root or a popover is **ignored** (the
   `CR-T` mechanism; MetalUI's choice — not probed).
6. **Item ids.** `ToolbarItem(id:)` when given; otherwise the placement and
   the item's index among the merged items (`"principal.1"`); a group's
   controls `"<group id>.<n>"`. Stable while the declaration is.

**Cost if wrong.** An item kind outside the set is a compile error, not a
silent drop.

---

## MD-J — The platform seam: `setToolbar(_:) -> Bool`, native on AppKit

**Evidence.** `TB0`/`TB1`: the toolbar adds 20 points (titlebar 32 → 52) and
the window **grows** — `contentLayoutRect` stays 600×300; `toolbarStyle`
`.automatic`, `displayMode` `.iconOnly`, `allowsUserCustomization` false;
navigation items `isNavigational`, principal and status in
`centeredItemIdentifiers`, then a flexible space, then primary/automatic in
declaration order; `UP`: a state change updates the items **in place** (same
`NSToolbar`, same item objects). gpui has no toolbar (`TitlebarOptions`
only).

**Ruling.**

1. `MetalUIPlatform` gains neutral, `Equatable` `PlatformToolbar` /
   `PlatformToolbarItem` (id, placement, control — `.button(title:image:)`,
   `.toggle(title:isOn:)`, `.picker(title:options:selected:style:)`,
   `.textField(placeholder:text:)`, `.search(prompt:text:)`, `.label(text:)` —
   `isEnabled`, `help`), the image an `ImageTexture` (premultiplied, `AI-E`).
2. **`PlatformWindow.setToolbar(_ toolbar: PlatformToolbar?) -> Bool`,
   defaultless** (`CR-M`'s rule): `true` = the platform shows it; `false` =
   the window draws it (`MD-K`). The window calls it only when the evaluated
   toolbar differs from the last one sent (and with `nil` once when the last
   `.toolbar` leaves).
3. **AppKit: native.** An `NSToolbar` (style `.automatic`, icon-only, no
   customization) whose delegate vends one `NSToolbarItem` per item, holding
   **native controls**: toolbar-bezel `NSButton` (title, or the `NSImage` made
   from the texture), checkbox `NSButton` (Toggle), `NSSegmentedControl` /
   `NSPopUpButton` (Picker), rounded-bezel `NSTextField` (TextField), an
   `NSSearchToolbarItem` (search), a label `NSTextField` (Text). Placement as
   `TB1`. A changed toolbar with the same id list and kinds updates the items
   in place (`UP`); otherwise the item list is rebuilt. Returns `true`. The
   window grows to keep its content size (AppKit's own behaviour, `TB1`), so
   MetalUI's layout sees no change.
4. **Actions** return as a queued `InputEvent.toolbarAction(ToolbarActionEvent)`
   (`item: String`, `action: .press | .toggle(Bool) | .select(Int) |
   .text(String)`), run by the window under `StateDispatch` against the latest
   evaluated items (`MN-D`'s menu-action precedent); an unknown id is dropped.
   A text item writes its binding on every edit (controlled, like
   `TextField`); the platform field is updated only when the bound value
   differs from what it shows (the caret survives).
5. **SDL** returns `false` and records the toolbar (for tests); the window
   draws it. **Every test fake** implements it (`FakePlatformWindow`:
   `toolbarIsNative`, default `true`, so no existing window draws a strip;
   `toolbars: [PlatformToolbar?]` records), and every compile-guard fixture
   conforming to `PlatformWindow` gains it. Migration note: a third-party
   conformer adds `func setToolbar(_: PlatformToolbar?) -> Bool { false }`.
6. Adding `InputEvent.toolbarAction` and stored properties on public types:
   `swift package clean`; every exhaustive switch over `InputEvent` in
   `Backends/SDL` gains the case.

**Cost if wrong.** A drawn toolbar on AppKit would look unlike every other Mac
app; a native toolbar on SDL is not available — hence the `Bool`.

---

## MD-K — The drawn strip (SDL, and any platform answering `false`)

**Ruling.**

1. **Geometry.** A strip across the window's top, **39 points**: 7 + the
   regular control height 24 (`Button.swift`'s strut) + 7, plus a 1-point
   `.separator` line at its bottom; fill `.surface`. Items are the declared
   elements themselves (the `Button`, `Toggle`, `Picker`, `TextField`, `Text`
   values; search a `TextField` 160 wide with the prompt as placeholder), in an
   `HStack(spacing: 8)` padded 8 horizontally: navigation items leading, a
   `Spacer`, then primary/automatic items and the search field trailing;
   principal and status items centred in the strip in an overlay.
2. **The root** lays out in the rect below the strip (window width × window
   height − 39), placed centred there (`CN-J` applied to that rect). The
   window is **not** resized — on AppKit the window grows instead (`TB1`):
   **divergence 136**. Presentation roots keep the whole window as their
   containing block (`LR-CH`): a popover may cover the strip.
3. **Identity.** The root's id and every id below it are unchanged by the
   strip. The strip's elements live under a window-owned named root
   **`$toolbar`** — an element name, not a `StateTable` slot (the seven slots
   unmoved); the new naming site calls `StateTable.noteNamed` and gains an arm
   in `everyNamingSiteStartsAReturningNameFresh` (`ID-R`).
4. **Order.** Laid out in its own run after the root's; prepainted and painted
   **after** the root (topmost in the one hit ranking and in paint), before
   presentation roots; accessibility records after the root's (`MN-F` item 4's
   order). Strip controls are ordinary controls: Tab reaches them after the
   root's, a click runs them directly (no queue).
5. **Timing.** A strip that appears, disappears or changes height takes effect
   in the same presented frame through one extra build (`CR-Q`'s precedent).
6. A window without a `.toolbar` is byte-for-byte today's: no strip node, no
   extra build.

**Cost if wrong.** A strip that shifted the root's ids would reset its state on
toolbar changes (spec 3.6 pins the ids).

---

## MD-L — Deferred and not offered

**Ruling.** Not built, each with an owner: `ToolbarItem` customization and
`.toolbarRole`, `.toolbar(removing:)`, `.windowToolbarStyle`, `ToolbarSpacer`,
`.searchable` suggestions/scopes/tokens (owner: the gpui-gap list); a toolbar
in a popover or sheet (owner none); MetalUI-drawn content inside a native
`NSToolbarItem` (owner none — would need a Metal layer per item); `@Bindable`
and `ObservableObject` (`MD-H` item 6); TextEditor's 5-point padding (`MD-F`).

---

## MD-M — The demo and the human checks

**Ruling.** The controls demo (`METALUI_CONTROLS_DEMO=1`,
`controlsDemoContent()`) gains one section in its own function
(`portGapsDemoSection()`, Windows' 1 MB stack): the four field styles plus a
disabled field and a `TextEditor`, a legacy `Row` whose second child carries
`.flexGrow(1).layoutPriority(1)`, an `@Observable` model provided with
`.environment(_:)` and read by a `Component` with `@Environment(Model.self)`,
and a `.toolbar` on the demo's root content (a `Button`, a `Toggle`, a
segmented `Picker`, `.searchable`). The fourteen `compare.sh` images do not
contain the controls demo, so they must read 0 differing pixels. Human checks:
group **W** (spec §7).

---

## MD-N — Tests drive the toolbar headless through the fake and the AppKit controller

**Ruling.** The neutral description, diffing, action dispatch and the drawn
strip are tested through `FakePlatformWindow` (`toolbarIsNative` toggled). The
AppKit controller is tested without a screen: an `NSWindow` need not be
visible for its `NSToolbar` items and controls to be inspected and
`performClick`ed. SDL's `setToolbar` is tested in `Backends/SDL` (no
presented frame needed, so not gated on the offscreen driver), arming
`armMainRunLoopExitCheck()`.

---

## MD-O — Inventory

**Ruling.** Every new public declaration gets a doc comment and a
`closeout-inventory-map.tsv` row: `TextFieldStyle`, `TextEditorStyle` and
their modifiers, the two `Environment` initialisers and
`environment(_ object:)`, `toolbar`, `searchable`, `ToolbarContent`,
`ToolbarItem`, `ToolbarItemGroup`, `ToolbarItemPlacement`,
`ToolbarContentBuilder`, `ToolbarItemContent`, `ToolbarScope` — **A** where
SwiftUI-aligned, **D** where a divergence (135, 136) qualifies them — and the
platform types `PlatformToolbar*`, `ToolbarActionEvent`,
`setToolbar(_:)` (**M**). The census is re-recorded by each lane that adds
declarations.

---

## MD-P — Divergence labels, pre-allocated

**Ruling.** `docs/divergences.md` reads 98 live, next label 132 at `d48b26d`.
Lane 1: **132** (field chrome look), **133** (TextEditor padding/font).
Lane 2: **134** (missing-object message). Lane 3: **135** (closed toolbar item
set), **136** (the drawn strip takes the content's height). Next label after
the branch: **137**. A lane that finds one of its labels unneeded retires
nothing — it leaves the number unused and says so in the record.

---

## MD-Q — Must-not-move, restated with the rulings that name a move

**Ruling.** Identity and state retention, hit testing, accessibility,
animation, focus, `List`, `Deferred` and text input do not move, **except**:
`MD-C`/`MD-D` move a default `TextField`'s size and its text's position inside
its bounds (text-input logic unchanged); `MD-E` adds a focus ring and a
disabled text dim to fields; `MD-K` adds the strip's elements, hitboxes,
focus stops and accessibility records **only in a window with a drawn
toolbar**. Pixels: 0 in all fourteen images; `Expected.swift` unedited.
