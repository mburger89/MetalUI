# Port gaps, medium — field chrome, `layoutPriority`, environment objects, window toolbar — design

**Status: DESIGNED (2026-10-06), critic-revised (`MD-R`…`MD-U`); lane 1 BUILT (2026-10-07, `MD-V`, record §79 §1), lanes 2 and 3 not built.**
Three lanes (§8, re-cut by `MD-R`), run in order.

User request 2026-10-02, an item of the gpui-gap priority list (**not a plan
task**): the SMK configurator port's four medium gaps — **MG-20** (`TextField`/
`TextEditor` draw no field chrome; no `.textFieldStyle`), **MG-14** (no
`layoutPriority` on the legacy stacks), **MG-2** (no `@Environment(Type.self)`
/ `.environment(object)`), **MG-3** (no window toolbar) — written up, with
where each bites and the app's workaround, in
`~/Developer/worktrees/smk_configurator/metalui-port/docs/superpowers/2026-10-06-metalui-gaps.md`.

Rulings: [`../2026-10-07-port-gaps-medium-decisions.md`](../2026-10-07-port-gaps-medium-decisions.md)
(`MD-A`…`MD-U`). Probes (each header holds its output and READING, the
authority for every SwiftUI claim here):
[`swiftui-field-chrome.swift`](../../probes/swiftui-field-chrome.swift),
[`swiftui-environment-object.swift`](../../probes/swiftui-environment-object.swift),
[`swiftui-toolbar.swift`](../../probes/swiftui-toolbar.swift),
[`swiftui-toolbar-nested.swift`](../../probes/swiftui-toolbar-nested.swift) (`MD-S`). Record (Record
phase): `docs/record/79-port-gaps-medium.md`.

**In one paragraph.** `TextField` gains SwiftUI's bordered field as its
default — 6/4 insets, a `.surface` fill, a `.separator` border, radius 6, the
control focus ring, a measured disabled dim — and `.textFieldStyle(_:)` with
SwiftUI's four styles, on the field and on a container; `TextEditor` gains an
opaque fill and `.textEditorStyle(_:)`. A legacy container learns to see
through a `layoutPriority` layer, so a prioritised child keeps its item fields
and its stretch (MG-14's own reproduction already works since `PE-F`). An
`@Observable` object can be provided with `.environment(_:)` and read with
`@Environment(Type.self)`, keyed by static type, trapping with SwiftUI's
message when missing. `.toolbar { ToolbarItem(placement:) { … } }` collects a
closed set of controls window-wide and hands the platform one neutral
description: AppKit builds a real `NSToolbar` of native controls; SDL answers
`false` and the window draws a 39-point strip of the same MetalUI controls
above the root.

---

## 0. Baseline (re-taken by the design session at `d48b26d`)

| measure | value |
|---|---|
| `swift build --build-system native --build-tests` | 0 `error:`; the only `warning:` SwiftPM's deprecation notice |
| `swift test --build-system native --no-parallel`, unfiltered | **2579 tests in 3 suites** passed; `FR-J no-argument frame: succeeded=true` present |
| `swift build --build-tests` (default build system) | 0 `warning:`, 0 `error:` |
| `docs/divergences.md` | 98 live, next label **132** |
| probes | field chrome 3 runs, 280 lines byte-identical; environment object 3 runs, 29 lines byte-identical; toolbar 3 runs, 68 lines identical modulo per-run item UUIDs |

---

## 1. What MetalUI has, and what SwiftUI does

### 1.1 Inventory

- **Fields.** `TextField` (`Sources/MetalUI/TextField.swift`) is one legacy
  `StyledElement` used by both vocabularies (a proposal container adopts it as
  `LegacyContent`, `PE-C`). `requestLayout` (~line 140) lowers a leaf answering
  `proposal.width ?? naturalWidth` × `lineHeight` (`naturalWidth` = widest of
  text/placeholder + 1). `geometry(bounds:…)` places the line, caret,
  selection and scroll from the **element bounds**; `prepaint` builds the
  `TextInputTarget` from it; `paintContent` clips to the bounds and draws
  selection, glyphs (placeholder at alpha × 0.45), marked-text underline and
  caret — **no background, border or ring**. `TextEditor`
  (`TextEditor.swift`, `paintContent` ~278) likewise. `ControlLook.swift`
  holds `controlAccent`, `controlRing` and `paintControl` (whose comment says
  fields do not take it). `ButtonStyle`/`PickerStyle` are closed structs
  written on the control (`IX-E`, `DD-V`, `PE-R`).
- **Priority.** The kernel's `nativeLayoutPriority` (`LayoutTree.swift`
  ~1421) reads a stack child's `layoutPriority` node; a frame or padding hides
  it. `ElementGroup.layoutPriority` (`LegacyProposalModifiers.swift:22`,
  `PE-F`) wraps legacy content in a proposal layer; the layer lowers in
  `ModifiedContent.swift` (~640, `case let .layoutPriority`). A legacy container
  (`LegacyLowering.swift` `lowerShownLegacyNode` ~97) consumes each child's
  `LoweredItem` (`LoweringState.consume` ~104), plans wrappers
  (`planLegacyItems` ~943; a `nil` record plans nothing) and registers them
  (`registerLegacyItems` ~1144: fixedSize, item frame + alias, alignment
  frame, margin). Unconsumed records report at the end
  (`reportUnconsumedLoweredItems`, `LoweringState.swift` ~155).
- **Environment.** `Environment<Value>` (`EnvironmentProperty.swift`) stores a
  `KeyPath<EnvironmentValues, Value>` and a reflection-bound box;
  `EnvironmentValues` (`EnvironmentValues.swift`) has typed fields and a
  private `custom: [ObjectIdentifier: Any]` for `EnvironmentKey`s;
  `EnvironmentScope` (`EnvironmentScope.swift`) runs one write per frame in
  layout and is transparent. No object API.
- **Window and platform.** `App.openWindow` (`App.swift:109`) takes an
  `Element` root; `Window.init` (`Window.swift` ~740) wraps it in
  `renderRoot`; `Frame.render` (`Frame.swift` ~3008) lays out the root from
  id `child(of: nil, at: 0)`. `PlatformWindow` (`MetalUIPlatform/Platform.swift`)
  has defaultless requirements (`presentMenu(_:at:) -> Bool` is the "native or
  drawn" precedent, `MN-F`); `InputEvent` carries `.menuAction`. AppKit opens a
  plain titled window (`AppKitPlatform.swift` ~589, no `fullSizeContentView`);
  SDL's `presentMenu` answers `false` (`SDLPlatform.swift` ~442). Conformers:
  `AppKitPlatform.swift`, `SDLPlatform.swift`, `Tests/MetalUITests/Fakes.swift`
  (`FakePlatformWindow` ~108) and the fixtures in `TransactionCompileGuards`,
  `ControlStateCompileGuards`, `MenuCompileGuards`, `ColorSchemeCompileGuards`,
  `DragAndDropCompileGuards`, `PlatformServicesCompileGuards` (and whatever
  `grep -rln "func presentMenu" Sources Tests Backends` lists at lane time).
  Window-wide collection during the walk: `.preferredColorScheme`
  (`Frame.withColorSchemePreference` ~558, `CR-L`), with the second build of
  `CR-Q`.
- **Demo.** No `TextField` or `TextEditor` in `demoContent()`,
  `nativeLayoutPreviewContent()` or `CounterPanel` — only in
  `textInputDemoContent()`, `controlsDemoContent()` and `menusDemoContent()`
  (`grep -n "TextField\|TextEditor" Sources/MetalUIDemoContent/*.swift`).

### 1.2 Measured in MetalUI at `d48b26d` (scratch test, not committed)

| tree (`LayoutDifferential.report`, diagnostics on) | result |
|---|---|
| `Column(gap: 16) { R.frame(minHeight: 240, maxHeight: .infinity); R.frame(minHeight: 260, maxHeight: 530).layoutPriority(1) }`, 300×800 | drawer **530**, greedy 254; no priority: 392 / 392 |
| `Box { Text("hi").layoutPriority(1); Text("other") }.width(300).height(100)` | `hi` **11×16**; no priority **11×100** (stretch lost silently) |
| `Row { Text("a").flexGrow(1).layoutPriority(1); Text("b") }` | **`text.flexGrow.unconsumed`** |

### 1.3 SwiftUI's answers (probe READINGs)

- **Field sizes** (`SZ`, `CS`): default = `.automatic` = `.roundedBorder` =
  `.squareBorder`: ideal = text + 12 wide, 24 tall; greedy width, `inf →
  inf×24`. `.plain`: text + ~4, 16 tall. Small 21/22, mini 19, large 24.
- **Field looks** (`NS`, `PX`, `TX`): the three bordered styles draw
  identically: radius ~6, fill at the frame's edge, a faint edge outside it;
  `.plain` no background, no focus ring. Disabled: chrome unchanged, text to
  about a third. Focus ring not measurable offscreen. A container's style
  reaches its fields; the innermost wins.
- **TextEditor** (`ED`, `ED2`): opaque text background, square, no border;
  `.textEditorStyle(.plain)` none; padding 5, font 12; sizes unchanged.
- **Environment objects** (`N`, `O`, `K`, `W`, `R`, `T`): nearest writer;
  optional form nil; keyed by static type; `nil` clears; observation per read
  property; a missing object traps with "No Observable object of type T
  found…".
- **Nested toolbars** (`NT`, `IF`, `PO`, `MD-S`): a `.toolbar` below the root
  reaches the window; several merge in pre-order, outer first; one inside a
  presented popover reaches no toolbar.
- **Toolbar** (`TB`, `UP`, `SR`, `GEO`): a real `NSToolbar` (style automatic,
  icon only, no customization), one item per `ToolbarItem`, placed
  navigation-leading / principal+status centred / the rest trailing after a
  flexible space, search last; updated in place; the window grows 20 points
  and the content keeps its size.
- **gpui** (no SwiftUI-free question here except the drawn strip's
  precedent): `WindowOptions.titlebar: Option<TitlebarOptions>` (`title`,
  `appears_transparent`, `traffic_light_position`), no toolbar API; Zed draws
  its own title bar in-window.

---

## 2. Public API

```swift
// Lane 1 — MetalUI
public struct TextFieldStyle: Equatable, Sendable {          // closed (MD-B)
    public static let automatic, roundedBorder, squareBorder, plain: TextFieldStyle
}
extension TextField { public func textFieldStyle(_ style: TextFieldStyle) -> TextField }
extension ElementGroup { public func textFieldStyle(_ style: TextFieldStyle) -> EnvironmentScope<Self> }

public struct TextEditorStyle: Equatable, Sendable {         // closed (MD-F)
    public static let automatic, plain: TextEditorStyle
}
extension TextEditor { public func textEditorStyle(_ style: TextEditorStyle) -> TextEditor }
extension ElementGroup { public func textEditorStyle(_ style: TextEditorStyle) -> EnvironmentScope<Self> }

// Lane 1, parts 2–3 — MetalUI (layoutPriority: no new API; MD-G is lowering only)
extension Environment {
    public init(_ objectType: Value.Type) where Value: AnyObject & Observable
    public init<T: AnyObject & Observable>(_ objectType: T.Type) where Value == T?
}
extension ElementGroup {
    public func environment<T: AnyObject & Observable>(_ object: T?) -> EnvironmentScope<Self>
}

// Lane 2 — MetalUI (ToolbarScope is not an Element: a window root cannot carry it, MD-S)
extension ElementGroup {
    public func toolbar<C: ToolbarContent>(@ToolbarContentBuilder content: () -> C) -> ToolbarScope<Self>
    public func searchable(text: Binding<String>, prompt: String = "Search") -> ToolbarScope<Self>
}
public struct ToolbarScope<Content: ElementGroup>: ElementGroup            // + ProposalElementGroup when Content is
public protocol ToolbarContent { /* SPI requirement, closed (MN-D) */ }
public struct ToolbarItem<Content: ToolbarItemContent>: ToolbarContent {
    public init(id: String? = nil, placement: ToolbarItemPlacement = .automatic,
                @ToolbarItemContentBuilder content: () -> Content)
}
public struct ToolbarItemGroup<Content: ToolbarItemContent>: ToolbarContent {
    public init(placement: ToolbarItemPlacement = .automatic, @ToolbarItemContentBuilder content: () -> Content)
}
public struct ToolbarItemPlacement: Equatable, Sendable {
    public static let automatic, navigation, principal, primaryAction, status: ToolbarItemPlacement
}
@resultBuilder public enum ToolbarContentBuilder { … }       // block, if, if/else, switch, for
@resultBuilder public enum ToolbarItemContentBuilder { … }
public protocol ToolbarItemContent { /* SPI, closed */ }
// conformers: Button where Label == Text, Button where Label == Image,
// Toggle where Label == Text, Picker (menu/segmented), TextField, Text

// Lane 2 — MetalUIPlatform (PlatformToolbarControl writes its own ==, images by identity, MD-U 1)
public struct PlatformToolbar: Equatable { public var items: [PlatformToolbarItem] }
public struct PlatformToolbarItem: Equatable {
    public var id: String
    public var placement: PlatformToolbarPlacement   // .navigation .principal .primaryAction .automatic .status .search
    public var control: PlatformToolbarControl       // .button(title:image:) .toggle(title:isOn:)
                                                     // .picker(title:options:selected:style:) .textField(placeholder:text:)
                                                     // .search(prompt:text:) .label(text:)
    public var isEnabled: Bool
    public var help: String?
}
public struct ToolbarActionEvent: Sendable, Equatable {
    public var item: String
    public var action: Action                        // .press .toggle(Bool) .select(Int) .text(String)
}
extension InputEvent { case toolbarAction(ToolbarActionEvent) }      // new case
protocol PlatformWindow { func setToolbar(_ toolbar: PlatformToolbar?) -> Bool }   // defaultless
```

Exact shapes inside the SPI requirements, the image field's type
(`ImageTexture`, as `setApplicationIcon` takes) and `Equatable` on it are the
lane's, within the rulings.

---

## 3. Implementation

### 3.1 Lane 1 — field chrome (`MD-B`…`MD-F`)

1. `TextFieldStyle.swift` (new): the struct, its kinds, the internal
   environment key (`EnvironmentValues.textFieldStyle`, internal, default
   `.automatic`) and the `ElementGroup` spelling; the same for
   `TextEditorStyle`.
2. `TextField.swift`: a stored `style: TextFieldStyle?` (nil = read the
   environment); `resolvedStyle(in:)`; `requestLayout` adds the chrome insets
   (`MD-D`) to the ideal and to the height (an offered width stays whole);
   `geometry` takes the **content rect** (bounds inset by the chrome);
   `prepaint` builds the `TextInputTarget` from it (unchanged code, new rect);
   `paintContent` draws the chrome (fill, border, radius 6), the ring when
   focused and not plain, and the text dim when `!pass.environment.isEnabled`.
3. `TextEditor.swift`: `TextEditorStyle`; the fill (and ring) in
   `paintContent`; no layout or geometry change.
4. `ControlLook.swift`: one helper `paintFieldChrome(_:bounds:focused:radius:pass:)`
   (fill, inner border, ring) and the constants (radius 6, insets table,
   disabled factor 0.33), with the evidence in its doc comment; the
   `paintControl` comment gains the reason fields do not take it.
5. Test literal churn (`MD-C` item 2): run the unfiltered suite after the
   default flips; for each reddened test apply the rule and name it in the
   lane's record section with which half of the rule it took.
6. `docs/migration.md` note; divergences 132, 133; inventory rows.

### 3.2 Lane 1, parts 2 and 3 — priority (`MD-G`) and environment objects (`MD-H`)

1. `LoweringState.swift`: `forward(_ from: LayoutNodeID, to: LayoutNodeID)`
   moves a record and stores its origin; `consume` returns the origin with it
   (or a `LoweredItem.origin` field — the lane's choice); the unconsumed report
   reads a forwarded record at its original site and name.
2. `ModifiedContent.swift`, the `.layoutPriority` case only: after
   `requestNativeLayoutPriority`, forward the child's record to the new node.
3. `LegacyLowering.swift` `registerLegacyItems`: alias the origin; when a
   plan registered any wrapper and the record was forwarded through a priority
   layer, register `requestNativeLayoutPriority(child: outermost, priority:)`
   last (outside the margin too).
4. `EnvironmentValues.swift`: the internal object table and its accessors;
   `EnvironmentProperty.swift`: the reader closure, the two initialisers,
   the trap (`MD-H` item 4); `EnvironmentScope.swift`: the `environment(_
   object:)` spelling. `swift package clean` before the suite.
5. divergence 134 and two "Not offered" rows; inventory rows.
6. Lane 1 also amends divergence 131 (`MD-T`).

### 3.3 Lanes 2 and 3 — toolbar (`MD-I`…`MD-N`, `MD-S`, `MD-U`) and the demo (`MD-M`)

Lane 2 builds items 1–3, 5, 6 and the window's diff and dispatch half of item
2; lane 3 builds item 4 (the strip run), `ToolbarStrip.swift`, item 7 and the
human checks of item 8 (`MD-R`).

1. `MetalUIPlatform`: `Toolbar.swift` (new) with the neutral types and
   `ToolbarActionEvent`; `InputEvent.toolbarAction`; the requirement in
   `Platform.swift` with its doc (the "conformer adds" line).
2. `MetalUI`: `Toolbar.swift` (new) — the API, the SPI evaluation into
   `ToolbarNode`s (title, control, run closures) and the conversion to
   `PlatformToolbarItem`s; `ToolbarScope` reports its evaluated content to the
   frame in layout (main tree only, `MD-I` item 5); `Frame.swift` gains the
   collection list and the strip run (§3.3 item 4); `Window.swift` diffs and
   sends, owns `toolbarIsDrawn`, routes `.toolbarAction`, runs the extra build;
   `ToolbarStrip.swift` (new) builds the strip element from the nodes'
   elements.
3. `MetalUIAppKit/AppKitToolbar.swift` (new): the `NSToolbarDelegate`
   controller, native controls, in-place update, actions → `onInput`;
   `AppKitPlatform.swift`: `setToolbar` forwarding to it (returns `true`).
4. **The strip run** (`MD-K`): when the window's last `setToolbar` answered
   `false` and a toolbar exists, `Frame.render` is handed the strip element;
   it lays out the root in the rect below 39 points, then the strip in its own
   run under the named root `$toolbar`, prepaints and paints the strip after
   the root and before presentation roots, and publishes its records after the
   root's. With no strip, `Frame.render` is today's code path.
5. `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`: `setToolbar` records
   and returns `false`; every exhaustive `InputEvent` switch gains the case.
6. `Tests/MetalUITests/Fakes.swift` (`toolbarIsNative`, `toolbars`) and every
   compile-guard fixture conforming to `PlatformWindow`.
7. Demo (`MD-M`): `Sources/MetalUIDemoContent/ControlsDemo.swift` gains
   `portGapsDemoSection()` and the root's `.toolbar`; the section's model is
   a `@MainActor` global (as `demoModel`), never a never-written `@State`.
8. divergences 135, 136 and the amendment of 120 (`MD-S`); inventory rows;
   human checks group W; migration notes (the requirement, `.toolbar` written
   inside the root's first container).

---

## 4. Tests

Every test asserts hand-derived literals; window tests pre-flight through
`LayoutDifferential.render` in diagnostics mode (`makeLoweredWindow`'s
pattern). "Red before" is what the test reads at `d48b26d` (or "does not
compile"); every **M** mutation is applied after the lane's commit, restored
from a copy, run with the full unfiltered suite, and every reddened test named.

### 4.1 Lane 1 — `Tests/MetalUITests/TextFieldChromeTests.swift` (new)

| # | test | asserts | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `theDefaultFieldIsTheBorderedOneAndSizesAsSwiftUI` | `VStack { TextField("Name", …).fixedSize() }`: width = MetalUI's plain ideal + 12, height = line + 8 (24 at 13 pt); `.roundedBorder`, `.squareBorder`, `.automatic` equal the default; `.plain` = the plain ideal × line (today's numbers, measured in the same test from a plain field and asserted as literals) | does not compile | M1.1 the inset table → 0 |
| 1.2 | `aContainerTextFieldStyleReachesItsFieldsAndTheInnermostWins` | `ENV1`–`ENV3`: `VStack { f }.textFieldStyle(.plain)` → plain size; `.roundedBorder` on `f` inside a plain container → bordered; `.plain` on `f` inside a bordered container → plain | does not compile | M1.2 the field ignores the environment style |
| 1.3 | `theBorderedChromePaintsTheThemesFillBorderAndRadius` | the scene's rect at the field's bounds: fill = `theme.surface`, border 1 = `theme.separator`, radius 6, light and dark; `.plain` paints no such rect | does not compile | M1.3 radius 6 → 5 |
| 1.4 | `aFocusedBorderedFieldDrawsTheControlRingAndAPlainOneDoesNot` | fake window, click focuses: a 2-point accent border, radius 6; `controlActiveState = .inactive` → `.separator`; a focused `.plain` field draws none | does not compile | M1.4 the ring drawn for `.plain` |
| 1.5 | `aDisabledFieldKeepsItsChromeAndDimsItsText` | under `.disabled(true)`: the chrome rect equal to the enabled one; glyph colour alpha = enabled × 0.33; placeholder likewise | does not compile | M1.5 the factor → 1 |
| 1.6 | `theTextAndCaretSitInsideTheChrome` | focused default field with "Hello", caret at end: `TextInputTarget.originX` = bounds.x + 6 − scroll, the caret rect's x = originX + `caretOffsets("Hello").last`, its y = bounds.y + 4 + (content height − line)/2; `.plain` → +0 | does not compile | M1.6 `geometry` handed the outer bounds |
| 1.7 | `theChromeFollowsControlSize` | `.controlSize(.small)`: height = line(11 pt) + 7; `.mini`: line(9 pt) + 8; `.large`: line(13 pt) + 8 | does not compile | M1.7 small's inset 3.5 → 4 |
| 1.8 | `aBorderedFieldIsStillGreedy` | in `HStack` at 200: width 200, height 24; under an infinite width answers infinity (the `Ask`-style `ProposalLayout` instrument of `GreedyControlSizingTests`) | does not compile | M1.8 the chrome adds 12 to an offered width |
| 1.9 | `theTextEditorDrawsAnOpaqueFillAndPlainDrawsNone` | `TextEditor` default: one `.surface` rect at its bounds, radius 0, no border; `.textEditorStyle(.plain)`: none; glyph origins identical in both (placement unchanged, `MD-F` 3) | does not compile | M1.9 the fill skipped |
| 1.10 | `aTextFieldStyleIsWrittenOnTheFieldAndCannotBeMintedOutside` (guard, `typecheckFile`, plain import) | compiles: `TextField("x", text: .constant("")).textFieldStyle(.plain).background(.surface).onSubmit {}` and `VStack { … }.textFieldStyle(.roundedBorder)`; control fails: `TextFieldStyle(kind: .plain)` | fails | M1.10 the initialiser made public → the control compiles (mutate red once) |

Also lane 1: every existing test reddened by the default flip, handled by
`MD-C` item 2 and listed by name (with which half of the rule) in the record.

### 4.2 Lane 1 (parts 2, 3) — `LegacyPriorityTests.swift` and `EnvironmentObjectTests.swift` (new)

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 2.1 | `aPrioritisedLegacyChildKeepsItsParentsStretch` | §1.2 row 2: `hi` 11×100 with the priority (element bounds through the alias), `unlowerable` empty | **11×16** (measured) | M2.1a no forwarding; M2.1b alias the layer node instead of the origin (`hi` back to 11×16) |
| 2.2 | `aLegacyItemFieldUnderALayoutPriorityIsLoweredNotReported` | §1.2 row 3 at width 300: report empty; `a`'s width = 300 − `b`'s width (both measured in-test from `Text` widths, asserted against hand-derived sums) | **`text.flexGrow.unconsumed`** (measured) | M2.1a |
| 2.3 | `thePriorityIsLiftedAboveTheItemWrappers` | `Column` 800 tall, gap 16: child A `.frame(minHeight: 240, maxHeight: .infinity)`; child B a `Box` with `.flexGrow(1)` (an item frame wraps it) and `.layoutPriority(1)` and a 530 maximum written through `CSSSizing`: B served first (530), A 254; without the lift B and A split (392/392) | B 392 — lane measures first (if it reads 530 the lift is unneeded and the lane says so) | M2.3 the lift not registered |
| 2.4 | `theMG14DrawerReachesItsMaximum` | §1.2 row 1: drawer 530, greedy 254 | **green before** (a pin of the port's scenario, stated) | `PE-F`'s M1.20 (the layer dropped) → 392 |
| 2.5 | `aPriorityLayerInAProposalStackStillReportsItsContentsItemField` | `HStack { Text("a").flexGrow(1).layoutPriority(1) }` → `text.flexGrow.unconsumed`, once | green before (`PE-C` item 4) | M2.5 a forwarded record marked consumed on forwarding |
| 2.6 | `anEnvironmentObjectIsReadAtItsPositionAndTheNearestWriterWins` | `N0`–`N3` in MetalUI: an `Element` reader and a `Component` reader; `a` outside `b` reads `b`; two types; an optional sibling outside reads nil; `O1`/`O2` | does not compile | M2.6 the scope's write keeps an existing entry |
| 2.7 | `anObjectIsKeyedByTheTypeItWasWrittenAs` | `K1`, `K1b`, `K2`, `K2b` | does not compile | M2.7 key by `type(of: object)` |
| 2.8 | `writingNilClearsAnObject` | `W1` | does not compile | M2.8 a nil write is a no-op |
| 2.9 | `aMissingObjectTrapsWithItsTypeInTheMessage` (exit tests) | a non-optional read with no writer, and an unbound wrapper read, each exit with failure and stderr containing `No Observable object of type ` + the type's name + ` found. An .environment(_:) for` | does not compile | M2.9 the message's type name dropped |
| 2.10 | `anEnvironmentObjectsReadPropertyDirtiesTheWindowAndAnUnreadOneDoesNot` | fake window, a `Component` reading `model.count`: write `model.other` → no redraw requested; write `model.count` → redraw, next frame's text reads the new count (`R`) | does not compile | M2.10 the reader reads the object's property outside the phase (cached at bind) → the new count never shows |
| 2.11 | `anEnvironmentObjectReachesComponentAnyElementDeferredAndPopoverContent` | readers inside a `Component`, `AnyElement`, a `Deferred` presentation and a presented `.popover` each read the declaring scope's object | does not compile | M2.11 the lane names one spelling that reddens one arm by name (e.g. `Component`'s bind moved before the scope's push) |
| 2.12 | `onlyAnObservableClassIsAnEnvironmentObject` (guard, `typecheckFile`, plain import) | compiles: `@Observable final class M {}` with `@Environment(M.self) var m`, `@Environment(M.self) var o: M?`, `.environment(M())`; control fails: a non-`Observable` class and a struct | fails | M2.12 the `Observable` constraint dropped (mutate red once) |

### 4.3 Lanes 2 and 3 — `ToolbarTests.swift`, `AppKitToolbarTests.swift` (new), SDL, guards

Lane 2: 3.1–3.5, 3.11–3.15, 3.17, 3.18. Lane 3: 3.6–3.10, 3.16 (`MD-R`).

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 3.1 | `aToolbarReachesThePlatformAsOneNeutralDescription` | fake (native): `.toolbar { navigation Button("Nav"); principal segmented Picker; primaryAction Button { Image }; Toggle("Advanced"); TextField("Filter"); status Text("Ready") }.searchable(…)` → `fake.toolbars.last` equals a literal `PlatformToolbar` (ids, placements, controls, states, order) | does not compile | M3.1 placement of `.status` mapped to `.automatic` |
| 3.2 | `theToolbarIsSentOnlyWhenItChanges` | two unchanged frames → one call; Toggle's binding written → one more call with `isOn: true`; the `.toolbar` removed → `setToolbar(nil)` once | does not compile | M3.2 sent every frame |
| 3.3 | `aToolbarActionRunsItsItemUnderStateDispatch` | queued `.toolbarAction`: `.press` runs the Button (its `@State` write shows next frame); `.toggle(true)`, `.select(1)`, `.text("q")` write their bindings; an unknown id changes nothing | does not compile | M3.3 run outside `StateDispatch` (the `@State` arm) |
| 3.4 | `toolbarsMergeInTreeOrderAndIgnorePresentationRoots` | two `.toolbar`s → items in pre-order; one inside a presented popover and one inside a `Deferred` presentation → absent | does not compile | M3.4 presentation contributions kept |
| 3.5 | `aToolbarScopeIsTransparentToLayoutAndIdentity` | ids, bounds and `@State` of a tree with and without `.toolbar` identical (native mode) | does not compile | M3.5 the scope consumes a cursor index |
| 3.6 | `aDrawnToolbarStripSitsAboveTheRootAndKeepsItsIds` | fake `toolbarIsNative = false`, window 400: strip elements within y 0…39; root content's bounds start at y ≥ 39, height ≤ 361, centred in that rect; every root-tree id equal to the no-toolbar window's | does not compile | M3.6 strip height 0 |
| 3.7 | `aDrawnToolbarIsInTheFirstPresentedFrame` | the fake's first presented frame already shows the strip; a later change shows in the same presented frame | does not compile | M3.7 no extra build |
| 3.8 | `aDrawnToolbarControlIsAnOrdinaryControl` | a click at the strip `Button`'s centre runs it directly; Tab reaches the strip's controls after the root's; typing into the strip `TextField` writes its binding; its edit state survives frames | does not compile | M3.8 the strip not prepainted (no hitboxes) |
| 3.9 | arm in `everyNamingSiteStartsAReturningNameFresh` | the `$toolbar` naming site starts a returning name fresh | the arm is new | M3.9 the `noteNamed` call removed |
| 3.10 | `aWindowWithoutAToolbarIsUnchanged` | no `setToolbar` call is made with a toolbar, no extra build (build count), identical scene to `d48b26d`'s for the same tree (a literal rect list) | green before (pin) | M3.10 an unconditional extra build |
| 3.11 | `theAppKitToolbarBuildsNativeItemsAndUpdatesThemInPlace` (AppKit, no screen needed) | `setToolbar` → `window.toolbar` exists, style `.automatic`, icon-only, no customization; item classes and controls (`NSButton`, `NSSegmentedControl`, `NSSearchToolbarItem`, …); navigation `isNavigational`; principal+status centred; a changed `isOn` keeps the same item objects; a changed id list rebuilds; returns `true` | does not compile | M3.11 rebuild on every call (the same-object arm) |
| 3.12 | `anAppKitToolbarControlSendsItsActionAsAnInputEvent` | `performClick` on the button → `.toolbarAction(press)`; segmented select → `.select(1)`; a search edit → `.text`; the checkbox → `.toggle(true)` | does not compile | M3.12 the checkbox sends `.press` |
| 3.13 | `onlyTheClosedSetIsToolbarContent` (guard, `typecheckFile`, plain import) | compiles: the 3.1 tree; controls fail: `ToolbarItem { Rectangle(…) }` and an outside type conforming to `ToolbarItemContent` / `ToolbarContent` | fails | M3.13 the SPI requirement made public (mutate red once) |
| 3.14 | `setToolbarHasNoDefault` (guard) | a `PlatformWindow` conformer without `setToolbar` fails to compile | fails | M3.14 a default added in an extension (mutate red once) |
| 3.15 | `SDLToolbarTests.theSDLWindowAsksTheFrameworkToDrawItsToolbar` (`Backends/SDL`, arms `armMainRunLoopExitCheck()`) | `setToolbar` returns `false` and records the toolbar; `nil` clears the record | does not compile | M3.15 returns `true` |
| 3.16 | `theControlsDemoShowsThePortGapsSection` | fake window over `controlsDemoContent()`: the field-style row's heights (24, 24, 24, line, 24-disabled), the priority `Row`'s widths, the environment object's text, the toolbar's item count | does not compile | M3.16 the section's `.environment(_:)` removed (traps → pre-flight reports; the lane names the spelling that reddens by name without a trap) |

| 3.17 | `aToolbarOnAWindowRootNeedsAContainer` (guard, `typecheckFile`, plain import; `MD-S`) | fails: `openWindow(…) { Text("x").toolbar { … } }`; compiles: the same inside a `Column` | fails | M3.17 `ToolbarScope` given a conditional `Element` conformance (mutate red once) |
| 3.18 | `aNativeToolbarFieldTakingFirstResponderLeavesMetalUIFocusAlone` (AppKit, no screen; `MD-U` 3) | a focused MetalUI `TextField`; `makeFirstResponder` on the toolbar search field → the window's focused id unchanged; a typed edit reaches the search binding through `.text` | does not compile | M3.18 the controller clears MetalUI focus on begin-editing |

`everyProductionTreeBuildsOnAOneMegabyteThread` must stay green with the new
section (`MD-M`).

---

## 5. Verification per lane (each lane, before its commit)

- `swift package clean` (lane 1's environment part and lane 2 change public
  stored properties / an enum case), native build, unfiltered `--no-parallel` run: read the one
  summary line and the `FR-J` line; 0 `error:`; the only `warning:` SwiftPM's;
  `swift build --build-tests` 0 warnings.
- `zsh docs/probes/closeout-inventory-check.sh` and
  `zsh docs/probes/closeout-undocumented.sh` print nothing; census re-recorded.
- Import rules: `MetalUILayout` imports only `MetalUICore`; `MetalUIScene`
  only `MetalUIShaderTypes` (no lane touches either).
- Lanes 2 and 3: `Backends/SDL` build and test (`PKG_CONFIG_PATH=$PWD/.accesskit`)
  and the `swift:6.4-noble` Linux image (`MD-N`); new SDL helpers arm
  `armMainRunLoopExitCheck()`; C enum `rawValue`s converted explicitly.
- Every lane: `docs/probes/demo-pixels/compare.sh <scratch> d48b26d HEAD` reads
  **0** in all fourteen images; `Tests/MetalUICrossPlatformTests/Expected.swift`
  unedited; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
- Mutations: the table's M-rows, each on a committed tree, restored from a
  copy, `git status --short` after each, every reddened test named; a hang
  (no summary line after 6 minutes) is recorded as such.

---

## 6. Demo

`controlsDemoContent()` (`METALUI_CONTROLS_DEMO=1`) gains
`portGapsDemoSection()` (own function): a column of fields — default,
`.roundedBorder`, `.squareBorder`, `.plain`, disabled — and a 60-tall
`TextEditor`; a 360-wide legacy `Row` of two `Text`s on `.surfaceSecondary`
whose second carries `.flexGrow(1).layoutPriority(1)`; a `Component` reading
`@Environment(DemoCounter.self)` (a `@MainActor` global `@Observable`) with a
button incrementing it. `ControlsDemo()`, inside the function's `Column` (a `.toolbar` cannot be the
window root, `MD-S`), gains `.toolbar` (navigation
`Button("Back")`, principal segmented `Picker`, a `Toggle("Advanced")`, a
primary `Button` with an `Image` label) and `.searchable`. Not in any of the
fourteen images (0 px); `ControlsDemoSwiftUISectionTests`,
`AccessibilityAuditTests` and `ListSelectionTests`' controls-demo arms are
re-checked by lane 3 and any moved literal is re-derived and named.

---

## 7. Human checks — group W (added to `docs/verification/human-checks.md` by lane 3)

- **W1** Field chrome (light, dark): the controls demo's five fields read as
  macOS text fields; the bordered three identical; `.plain` bare; the disabled
  one's text dimmed, its box unchanged; focusing one (click) draws the accent
  ring, and the ring greys when another app is active.
- **W2** `TextEditor`'s fill reads as an editor's background in both schemes.
- **W3** Toolbar, AppKit: a unified toolbar under the traffic lights holds
  Back (leading), the segmented picker (centred), Advanced, the image button
  and a search field (trailing); clicking each acts once; the window opened
  20 points taller with the content unchanged; the overflow chevron appears
  when narrowed; with a MetalUI field focused, clicking the search field
  leaves one caret blinking where you type, and clicking back types into the
  MetalUI field again (`MD-U` 3).
- **W4** Toolbar, SDL (Linux or Windows): the drawn strip shows the same
  controls above the content, and they work by mouse and keyboard.
- **W5** VoiceOver (AppKit): the toolbar's native items are announced
  (an agent cannot run this — `IX-AE`).

---

## 8. Lanes and files (re-cut by `MD-R`)

Lanes run in order; files are owned by one lane. A shared file listed under
"serialized" is edited by the later lane on top of the earlier lane's commit.

**Lane 1 — field chrome, legacy priority, environment objects** (three parts,
each committed and mutated on its own, in this order).
Part 1: `Sources/MetalUI/TextField.swift`, `TextEditor.swift`,
`ControlLook.swift`, `TextFieldStyle.swift` (new);
`Tests/MetalUITests/TextFieldChromeTests.swift`,
`TextFieldStyleCompileGuards.swift` (new), and the existing test files whose
literals the default moves (named in the record; expected from the grep:
`TextFieldTests`, `TextEditorTests`, `ProposalControlsTests`,
`GreedyControlSizingTests`, `FocusTraversalTests`, `BindingTests`, `FontTests`,
`AccessibilityAuditTests`, `ControlsDemoSwiftUISectionTests`, …); divergence
131 amended (`MD-T`). Part 2: `LoweringState.swift`, `LegacyLowering.swift`,
`ModifiedContent.swift` (the `.layoutPriority` case only);
`LegacyPriorityTests.swift` (new). Part 3: `EnvironmentProperty.swift`,
`EnvironmentValues.swift`, `EnvironmentScope.swift`;
`EnvironmentObjectTests.swift`, `EnvironmentObjectCompileGuards.swift` (new).

**Lane 2 — the toolbar, native.** `Sources/MetalUIPlatform/Platform.swift`,
`InputEvent.swift`, `Toolbar.swift` (new); `Sources/MetalUI/Toolbar.swift`
(new), `Window.swift` (diff, send, dispatch); `Sources/MetalUIAppKit/AppKitToolbar.swift`
(new), `AppKitPlatform.swift`; `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`
(+ any `InputEvent` switch there), `Backends/SDL/Tests/…/SDLToolbarTests.swift`
(new); `Tests/MetalUITests/ToolbarTests.swift`, `AppKitToolbarTests.swift`,
`ToolbarCompileGuards.swift` (new), `Fakes.swift`, the compile-guard files
with `PlatformWindow` fixtures; divergence 135 and the amendment of 120.

**Lane 3 — the drawn strip and the demo.** `Sources/MetalUI/ToolbarStrip.swift`
(new), `Frame.swift`, `Window.swift` (the strip's extra build, on lane 2's
commit); `Sources/MetalUIDemoContent/ControlsDemo.swift`;
`Tests/MetalUITests/ToolbarStripTests.swift` (new: 3.6–3.10, 3.16),
`ExplicitIdentityTests.swift` (one arm); divergence 136; human checks group W;
`Backends/SDL` and the Linux image re-run.

**Serialized (lane order).** `docs/divergences.md` (labels per `MD-P`),
`docs/migration.md`, `docs/probes/closeout-inventory-map.tsv`,
`closeout-public-api.tsv`, `docs/api-overview.md`, `Window.swift` (lanes 2,
3); the demo-tree tests (`ControlsDemoSwiftUISectionTests`,
`AccessibilityAuditTests`, `ListSelectionTests`, `TextFieldTests`'
text-input-demo arm): lane 1 for the field default, lane 3 for the demo
section.

Not touched until the Record phase: `CLAUDE.md`, `AGENTS.md`, `README.md`,
the plan, `docs/record/README.md`, existing record files.

---

## 9. Deferred (`MD-L`)

| item | reason | owner |
|---|---|---|
| toolbar customization, `.toolbarRole`, `.toolbar(removing:)`, `.windowToolbarStyle`, `ToolbarSpacer` | not needed by the port; each its own probe | gpui-gap list |
| `.searchable` suggestions, scopes, tokens, `placement:` (`MD-U` 2) | same | gpui-gap list |
| a toolbar in a popover or sheet | MetalUI has no sheet; popovers ignored (`MD-I` 5) | none |
| MetalUI-drawn content inside a native `NSToolbarItem` | a Metal layer per item | none |
| `@Bindable` | a property wrapper of its own; Binding(get:set:) works | gpui-gap list |
| `ObservableObject`, `@EnvironmentObject`, `.environmentObject` | Combine | none |
| `TextEditor`'s 5-point padding and 12-point font | moves every editor literal; divergence 133 | none |
| field focus-ring glow as AppKit draws it | unmeasurable offscreen | human check W1 |

---

## 10. Acceptance (the branch)

Suite count = 2579 + the new tests (each lane states its delta); 0 px in all
fourteen images; `Expected.swift` unedited; 0 warnings on both build systems;
`Backends/SDL` and the Linux container build and pass; the closeout scripts
print nothing; every M-row reddened what it names; divergences 132–136 live,
120 and 131 amended (`MD-S`, `MD-T`), next label 137; human checks W1–W5
written, not run.
