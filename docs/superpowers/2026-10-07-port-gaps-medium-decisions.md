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
- [`../probes/swiftui-toolbar-nested.swift`](../probes/swiftui-toolbar-nested.swift)
  (arms `NT0`–`NT2`, `IF0`/`IF1`, `PO`; added by the critic, `MD-S`).
- The design session's MetalUI measurements at `d48b26d` (a scratch test, not
  committed; outputs quoted in `MD-G`).
- gpui (where SwiftUI is not the comparison): `crates/gpui/src/platform.rs`
  on zed `main`, read 2026-10-06 — `WindowOptions.titlebar:
  Option<TitlebarOptions>` with `TitlebarOptions { title,
  appears_transparent, traffic_light_position }`, and no toolbar API; Zed
  draws its own title bar inside the window.

Every probe header carries its recorded output and how to run it (`SA-O`).

Prefix **`MD-`**, lettered. **Next unused: `MD-Y`.** (This line moves in the
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

**Ruling.** (Lanes re-cut by `MD-R`; the list below is the design's
original cut.) Four parts, three lanes, run in order:

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
   placeholder + 1 for the caret) + 12 — divergence 131 is **amended**, `MD-T`; height =
   one line + 2 × the vertical inset. An offered width is still taken whole
   and an infinite one answers infinity (`PE-D` unchanged): the chrome is
   inside the offered width.
2. `.plain`: exactly today's field — no inset, today's ideal and height. (The
   probe's plain +4 is AppKit's line fragment padding outside SwiftUI's frame;
   MetalUI's +1 caret allowance stays — the residue of divergence 131 as
   amended by `MD-T`.)
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
   text, placeholder and caret colour alpha × **0.33** (`TX`: ≈ 0.29/0.87) —
   for a bordered style only; a disabled `.plain` field is the previous field
   (`MD-W` item 1).
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
   `CR-T` mechanism). Probed after the fact by `MD-S` (`NT1` pre-order, outer
   first; `PO` a popover's toolbar ignored); a window-root `.toolbar` does not
   compile (`MD-S`).
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
`.searchable` suggestions/scopes/tokens and its `placement:` (`MD-U` item 2)
(owner: the gpui-gap list); a toolbar
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

---

## MD-R — The lanes re-cut: the toolbar was a lane too large; the three small parts share one

**Found (critic, 2026-10-06).** `MD-A`'s lane 3 carried the whole toolbar —
about a dozen public types and two result builders, the platform seam and an
`InputEvent` case, the AppKit `NSToolbar` controller, SDL with the Linux image,
the `Frame.render` strip run under a new named root, the window's diff,
dispatch and extra build, and the demo: sixteen tests and the two riskiest
changes of the branch (a new `PlatformWindow` requirement and a second layout
run in `Frame.render`) in one agent. Lanes 1 and 2 were each small (field
chrome; priority plus environment objects), and their files are disjoint.

**Ruling.** Three lanes, run in order, files owned by one lane (the
serialized list of spec §8 unchanged):

1. **Lane 1 — field chrome, legacy priority, environment objects** (`MD-B`…
   `MD-H`, `MD-T`): the old lanes 1 and 2 together. Three parts in disjoint
   files (`TextField`/`TextEditor`/`ControlLook`/`TextFieldStyle`;
   `LoweringState`/`LegacyLowering`/`ModifiedContent`'s `.layoutPriority`
   case; `EnvironmentProperty`/`EnvironmentValues`/`EnvironmentScope`), each
   committed on its own with its own mutations, in that order.
2. **Lane 2 — the toolbar, native** (`MD-I`, `MD-J`, `MD-N`, `MD-S`,
   `MD-U` items 1–3): the public API, the SPI evaluation and window-wide
   collection, the neutral `MetalUIPlatform` types, `InputEvent.toolbarAction`,
   the defaultless `setToolbar(_:) -> Bool` on AppKit (the real `NSToolbar`
   controller), SDL (records, answers `false`) and every fake and fixture,
   the window's diff and dispatch, `Backends/SDL` and the Linux image. Tests
   3.1–3.5, 3.11–3.15, 3.17, 3.18.
3. **Lane 3 — the drawn strip and the demo** (`MD-K`, `MD-M`): `Frame.render`'s
   strip run under `$toolbar`, `ToolbarStrip.swift`, the extra build when the
   strip's presence changes, the `everyNamingSiteStartsAReturningNameFresh`
   arm, the demo section and human checks group W. Tests 3.6–3.10, 3.16.
   `Backends/SDL` is re-run (its window now draws the strip) in the Linux
   image too.

**Interim state, stated.** Between lanes 2 and 3 an SDL window (and a fake
with `toolbarIsNative = false`) answers `false` and draws nothing: the branch
is not merged in that state, and lane 2's record says so.

**Cost if wrong.** Lane 1 grows to about twenty-two tests, but over three
mechanically independent parts; the alternative left one agent holding both
platform-seam and `Frame.render` risk with no checkpoint between them.

---

## MD-S — `.toolbar` cannot be a window root: write it on a nested element, as SwiftUI merges nested toolbars

**Found.** `MD-I` item 1 makes `ToolbarScope` a transparent `ElementGroup`
(`LifecycleScope`'s shape), and `App.openWindow` takes an `Element`: so
`openWindow(…) { Root().toolbar { … } }` does not compile — divergence 120's
rule — while the spec's demo (§6, "the demo root gains `.toolbar`") and the
task's "on the window root view, SwiftUI's" assumed it would. Whether a
`.toolbar` *below* the root reaches the window was not probed (the toolbar
probe's `TB1` writes it on the root only), so `MD-I` item 5's window-wide
pre-order merge was a claim without a run.

**Evidence.** [`../probes/swiftui-toolbar-nested.swift`](../probes/swiftui-toolbar-nested.swift),
three runs byte-identical: `NT0` (control) root toolbar → `["A"]`; `NT1` an
outer `.toolbar` on a `VStack` and one on each of two children → `["A", "B",
"C"]` (pre-order, outer first); `NT2` nested only → `["B", "C"]`; `IF0`/`IF1`
(separating arm) a nested toolbar under `if true` contributes, under
`if false` there is no toolbar; `PO` a presented popover's `.toolbar` reaches
neither the main window's toolbar nor the popover's window.

**Ruling.**

1. `ToolbarScope` stays a transparent `ElementGroup` and is **not** an
   `Element`: a `.toolbar` on a window's root does not compile; write it on
   any element inside the root's first container
   (`openWindow(…) { Column { content.toolbar { … } } }`). SwiftUI merges a
   nested view's toolbar into the window (`NT1`, `NT2`), so the nested
   spelling has SwiftUI's meaning. **Divergence 120 is amended** (not a new
   label) to name `ToolbarScope` beside `LifecycleScope`/`PresentationScope`;
   `.searchable` returns the same scope and is covered by the same words.
2. `MD-I` item 5 now rests on `NT1` (pre-order merge, outer first) and `PO`
   (a popover's toolbar ignored — SwiftUI's answer, no longer "MetalUI's
   choice"). A `Deferred` presentation root's toolbar is ignored too
   (MetalUI's choice: SwiftUI has no `Deferred`; the nearest shape is `PO`).
3. A guard, `aToolbarOnAWindowRootNeedsAContainer` (lane 2, test 3.17,
   `typecheckFile`, plain import): `openWindow(…) { Text("x").toolbar { … } }`
   fails to compile and `openWindow(…) { Column { Text("x").toolbar { … } } }`
   compiles. Mutated red once by giving `ToolbarScope` a conditional `Element`
   conformance.
4. The demo writes `.toolbar` and `.searchable` on `ControlsDemo()` inside
   `controlsDemoContent()`'s `Column`, not on the function's result (spec §6
   corrected).

**Cost if wrong.** A port that writes `.toolbar` on its root gets a compile
error naming the container rule (divergence 120's row says what to write);
nothing is silently dropped.

---

## MD-T — Divergence 131 is amended by the field chrome, not left "unchanged"

**Found.** `MD-D` items 1 and 2 say "divergence 131 unchanged", but row 131
(`PE-N`) reads "`TextField` is one line tall (16) with an ideal of its text or
placeholder + 1 (36.25)" and names **MG-20** as its owner. After `MD-C`/`MD-D`
the default field is 24 tall (SwiftUI's `SZ1`) and its ideal is text + 1 + 12
(48.25 for "Name" against SwiftUI's 47.50): the row would be stale the moment
lane 1 lands, and its pinning test
`everyControlAnswersInSwiftUIsClassInsideAProposalContainer` (1.1, `ideal`
arms) reddens on the flip.

**Ruling.** Lane 1 **amends** row 131: the `TextField` half now reads "24
tall; ideal text or placeholder + 1 + 12 (48.25 for "Name") — the residual
+1 is the caret allowance"; the menu `Picker`, `Menu` and `Toggle` halves are
unchanged; the owner column drops MG-20 (discharged) and keeps none for the
residue. The pinning test takes the new literals under `MD-C` item 2's "a
size or a layout" half and is named in the record. The divergences header
line records "port gaps (medium) amended 131 and 120 and added 132–136".

**Cost if wrong.** A divergence row that contradicts the code is exactly what
the public `docs/divergences.md` must not carry.

---

## MD-U — Smaller corrections

1. **Image equality without a new conformance.** `ImageTexture` is a `final
   class` in `MetalUIScene` with no `Equatable`. `PlatformToolbarControl`
   writes its own `==`, comparing an image by identity (`===`); no conformance
   is added to `ImageTexture` (no public change to `MetalUIScene`, whose import
   rule stands). The window converts an `Image` label's `ImageBitmap` to one
   `ImageTexture` per bitmap identity and reuses it, so an unchanged toolbar
   compares equal and is not re-sent (test 3.2 holds).
2. **`.searchable`'s spelling.** SwiftUI's is
   `searchable(text:placement:prompt:)` with `prompt: Text?` (and
   `LocalizedStringKey` / `StringProtocol` overloads), default `nil` drawing
   "Search" (`SR`: label "Search"). MetalUI's `prompt: String = "Search"`
   spells every literal call identically; `placement:` (`SearchFieldPlacement`)
   is **not offered** and joins `MD-L`'s list (owner: the gpui-gap list).
3. **A native toolbar field and MetalUI's focus.** On AppKit a toolbar
   `NSTextField`/`NSSearchField` takes the window's first responder from
   MetalUI's content view. MetalUI's focus does **not** move (`MD-Q`): the
   focused element keeps its focus and receives no key until the content view
   is first responder again (a click in it); the window's shortcut pipeline
   still runs for ⌘/⌃-keys the native field does not claim (`MN-J`). Test 3.18
   (lane 2, `AppKitToolbarTests`, no screen):
   `aNativeToolbarFieldTakingFirstResponderLeavesMetalUIFocusAlone` — a
   focused MetalUI `TextField`, then `makeFirstResponder` on the toolbar's
   search field: the window's focused id is unchanged; typed text reaches the
   search item's binding through `.text`, not the MetalUI field. Mutation: the
   controller clears MetalUI focus on `controlTextDidBeginEditing` — the
   focused-id arm reddens. Human check W3 gains "with a MetalUI field focused,
   click the search field: only one caret blinks where you type; click back
   and the MetalUI field types again" (the doubled caret is a look an agent
   cannot judge).
4. **The lift is not a new legacy registration site.** `MD-G` item 3's outer
   `layoutPriority` node is registered inside `registerLegacyItems` for a
   child that its own site already checked, so it owes no arm in
   `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`; it registers no rect,
   so no arm in `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`.
5. **Presentations' environment.** `MD-H` item 3's "Deferred and popover
   content inherit their declaring scope" rests on `LR-CS` (a presentation
   root's `requestLayout` runs under its declaring scope's environment) as well
   as `EV-G` (paint); test 2.11 pins both phases for an object read.

---

## MD-V — Divergence 76 is amended too: the bordered field's inset follows `controlSize`

**Found (lane 1, part 1).** `MD-D` item 4 makes the bordered field's vertical
inset 3.5 at `.small` (probe `CS1`), so the field's chrome now reads
`controlSize`. Divergence 76 said "`TextField`'s padding … read[s] nothing",
pinned by `controlSizeReachesTheDefaultFontButNoControlsChrome`, whose field arm
("the field is its font's line, no padding") reddened at `.small` on the
default flip (the only arm of the suite's nine reddened tests the spec did not
foresee).

**Ruling.** Row 76 is amended: `controlSize` reaches every text's default font,
`Button`'s chrome and the bordered `TextField`'s vertical inset; `Toggle`,
`Picker`, `Slider`, `Stepper` still read nothing (owner none). The pinning
test keeps its name and its font arm on a `.plain` field (`MD-C` item 2's
"subject unchanged" half) and gains a chrome arm: bordered = line + 7 at
`.small`, + 8 otherwise, at every size. Recorded in the divergences header
beside 131.

**Cost if wrong.** A public row contradicting the code (`MD-T`'s argument).

---

## MD-W — Lane 1 review: a disabled `.plain` field takes no dim; a `Deferred`'s priority layer stays in flow

**Found (lane 1 review).** (1) `MD-E` item 3 dimmed every disabled field's
text, `.plain` included, while `MD-C` item 2 and the migration row say
`.textFieldStyle(.plain)` restores the previous field **exactly** — and the
previous `TextField` took no disabled look. The probe's `TX` arm measures the
default (bordered) field only; nothing measures a disabled `.plain` field. (2)
`LoweringState.forward` refuses a presentation placeholder's record, and
nothing pinned why: a forwarded placeholder record would make
`droppingPresentations` drop the `layoutPriority` **layer** from its legacy
container's flow, where `d48b26d` (no forwarding) kept the layer, a 0 × 0
child, in flow.

**Ruling.**

1. The disabled dim applies to the bordered styles only. A disabled `.plain`
   field draws as before this branch — the migration row and `MD-C` item 2's
   "exactly" hold. Pinned by test 1.5's `.plain` arm.
2. A `layoutPriority` written on a `Deferred` keeps `d48b26d`'s answer: the
   placeholder's record stays at the placeholder, the container drops only the
   placeholder (`LR-CK`), and the layer stays in flow as a 0 × 0 child taking
   its gaps; the presentation is laid out against the window as before. Not
   ruled here whether that layer should leave flow (a `Deferred` change this
   lane does not make; `MD-Q`). Pinned by test 2.13.
3. Review pins with no ruling change: the editor's container style (test
   1.11), the editor's ring (1.12), the caller-`focusBorder` precedence for the
   bordered field (1.4's new arm) and the text clip's vertical extent (1.13).

**Cost if wrong.** (1) A look difference on a disabled plain field only. (2) A
zero-size child's gap in a gapped legacy container under a prioritised
`Deferred` — a spelling with no use.

---

## MD-X — Lane 2, as built: a closed button-label protocol, the content size held explicitly, generated ids, no `performClick`

**Found (lane 2, implementing `MD-I`/`MD-J`).**

1. Spec §2 lists `Button where Label == Text` and `Button where Label == Image`
   as two `ToolbarItemContent` conformers. Swift admits **one** conditional
   conformance of a type to a protocol, so the two cannot both be written.
2. `MD-J` item 3 says the window grows to keep its content size "(AppKit's own
   behaviour, `TB1`)". Measured on an `AppKitWindow` (test 3.11's first
   build): a 900 × 200 content read **900 × 232** after `window.toolbar` was
   set, the frame 52 points taller (284) — AppKit alone did not hold the
   content size for a window built by `AppKitWindow.init` (`TB1`'s window was
   SwiftUI's).
3. `MD-I` item 6 left "the item's index among the merged items" and an item
   holding several controls unstated in detail.
4. `NSButtonCell.performClick(_:)` spins a nested event loop for its highlight
   delay. Measured: test 3.12 written with `performClick` ran a `CFRunLoopStop`
   that an earlier test's spin had queued (lldb, breakpoint on
   `CFRunLoopStop`, frame `-[NSButtonCell performClick:]` ←
   `anAppKitToolbarControlSendsItsActionAsAnInputEvent`); the async main's run
   loop later returned and the process **exited 0 with no summary line** —
   twice, unfiltered, at the same place (after 1091 started tests), and with
   `--filter 'ObservationTests|AppKitToolbarTests|FileDialogTests'` (and with
   `AppKitPresentationTests` in place of `ObservationTests`).

**Ruling.**

1. A closed public protocol **`ToolbarButtonLabel: ElementGroup`** (SPI
   requirement `_toolbarLabel() -> (title: String, image: ImageTexture?)`),
   conformed by `Text` and `Image` only; `Button: ToolbarItemContent where
   Label: ToolbarButtonLabel`. The spelling a caller writes is unchanged; an
   outside label type cannot conform (the same SPI mechanism as `MD-I` item
   3). Inventory family `toolbar` (class D, 135).
2. `AppKitWindow.setToolbar` reads `contentLayoutRect.size` before applying
   and, if it moved, calls `setContentSize` with it — for a set, an update and
   a removal. `MD-J` item 3's outcome (content unchanged, window grows) holds;
   its "AppKit's own behaviour" is corrected to "restored explicitly". Pinned
   by test 3.11's content-size arm.
3. **Ids.** The non-search entries are numbered in merged order: entry `k`
   (0-based, across the window, counting `ToolbarItem`s and
   `ToolbarItemGroup`s alike) is `id` when given, else `"<placement>.<k>"`
   (`navigation`, `principal`, `primaryAction`, `automatic`, `status`). A
   group's controls are `"<base>.<n>"`; so are an item's when it holds more
   than one control (an item of one control keeps the bare base). Search
   fields come last, `"search"`, then `"search.1"`, …. A picker in any style
   but `.menu` is segmented. Duplicate caller ids are not diagnosed (owner
   none).
4. AppKit tests fire a control as a click does — set the state a click sets,
   then `sendAction(_:to:)` — and never call `performClick(_:)`. Recorded as a
   CI hazard for the record (a nested event loop in a test runs other tests'
   queued run-loop blocks).

**Cost if wrong.** (1) None for callers; one more public name. (2) Without
it, every native toolbar change would resize MetalUI's content and relayout.
(4) A suite that ends with no summary line.
