# Controls and selection — design (plan task 10, part 2)

Branch `feat/controls-and-selection` from `27b2fcc` (part 1's tip). Rulings
`DD-Q`…`DD-AC` are appended to part 1's decisions doc,
[`../2026-09-25-data-and-scrolling-decisions.md`](../2026-09-25-data-and-scrolling-decisions.md)
(next unused after the critic round: **`DD-AD`**). Evidence:
`docs/probes/swiftui-controls-and-selection.swift` (**new**, this design; arm
ids cited as `BT0`, `SA3`, `KY6c` …, its header carries the recorded output
and the reading). Record: `docs/record/58-controls-and-selection.md` (written
by the lanes and the Record phase). Part 1 is record §57 and spec
`2026-09-25-data-and-scrolling-design.md`.

**Status: DESIGNED, then CRITICISED AND REVISED** (`DD-AC`: ten fixes, each
amending the ruling it names and the section below that carries it; eight
attacks rejected with reasons; the probe re-run unlocked, byte-identical,
and extended with PK2/PK3).

## 1. Baseline

`27b2fcc`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation
notice), then unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1556 tests in 3 suites passed`**; the log carries `FR-J
no-argument frame: succeeded=` (guards ran). 96 typecheck guards, 0 goldens,
56 live divergences (next label **80**; 75 stays unused). Re-taken by this
design session.

The probe ran with the screen **locked** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): layout sizes,
accessibility trees, accessibility actions and key events are measured; the
**click** and **wheel** arms have failed positive controls (CK0, WH0) and
measure nothing — every pointer rule below is MetalUI's own and says so.

## 2. Scope — the items addressed to part 2, and their disposition

`DD-Q` collects them (grep for "task 10" and "part 2" over `docs/record/`,
`docs/superpowers/*.md` and `specs/`, and part 1's `DD-J` table); `DD-AB`
disposes of every item this run does not build.

| item | source | disposition |
|---|---|---|
| common controls: `Button`, `Toggle`, `Slider`, `Stepper`, `Picker` | plan task 10 text; `DD-J` | **this run** — `DD-R`, `DD-S`, `DD-V`, `DD-W`, `DD-X` |
| a `Button` control's existence, and its relation to `onClick` | `EV-AE`/`EV-AF`; `AB-` doc's "no `Button` until task 10" | **this run**, `DD-R` |
| keyboard activation, focusability, disabled, accessibility of each control | the brief | **this run**, `DD-T`, `DD-U` |
| `controlSize`'s consumers (divergence 76) | `EV-AC`, `EV-AE`; record §05, §56 | **`Button`'s chrome reads it** (`DD-R` item 4); divergence 76 **amended, kept** — a `Text`'s default font, `TextField`/`TextEditor` (height follows the font) and the other controls' metrics → **plan task 11** (`DD-AB`) |
| `controlActiveState`'s consumers | `EV-AE` | **plan task 12**, unchanged (an inactive-window look) |
| selection: `List(selection:)` single and multi, keyboard, pointer, accessibility | plan task 10 text; `DD-J` | **this run**, `DD-Z` |
| the controls' selection (`Picker(selection:)`) | `DD-J` | **this run**, `DD-V` |
| divergence 16 (a click target inside a `ScrollView` swallows its wheel) | record §04 | **retires**, `DD-Y` — a selectable `List` is rows of click targets |
| `ForEach(_: Binding<C>)` | `DD-J` | **this run**, `DD-AA` |
| `TextField`/`TextEditor` binding initialisers | the brief | **already delivered** by part 1 (`DD-E`); nothing to do |
| `List` scrolling itself and answering greedily (L0/L1, K6), non-uniform rows, `List { … }` content | `DD-J`, `CN-Q` | **kept, documented**: divergence **84**, owner none (`DD-AB`) |
| divergence 32 (`List` publishes a table whatever its role); accessibility scrolling to unrealised rows | `DD-J`, `AB-Q` | **plan task 12** (the VoiceOver half) (`DD-AB`) |
| two-axis scrolling (`CN-M`), divergence 54 | `DD-J`, `LR-BJ`, record §54 | **kept, documented**, owner none (`DD-AB`) |
| `scrollPosition(id:)` | `DD-J` | **not built**, additive, owner none (`DD-AB`) |
| `ButtonStyle`/`ToggleStyle`/`PickerStyle` protocols, other styles (`.plain`, `.switch`, `.menu`), `Button(role:)`, `.keyboardShortcut` | the brief ("only if cheap") | **plan task 12** (`DD-AB`) |
| a disabled look, focus ring policy, gesture composition, full keyboard navigation | the brief | **plan task 12**, unchanged |

**Plan task 10 is ticked in the Record phase only if every lane is verified**
(`DD-AB` item 1): with this run the text's four clauses — identified data,
bindings, common controls and selection; the `List`/`ScrollView`
limitations that blank or destroy state; scroll position, indicators and
programmatic scrolling — are all closed; every item above that is not built
is either not a clause of the text or is re-owned by name.

## 3. The public API (ruled against SwiftUI's spelling; public API is permanent)

```swift
// Button.swift  (lane 1)
public struct Button<Label: ElementGroup>: Element, StyledElement {
    public init(action: @escaping @MainActor () -> Void,
                @ElementBuilder label: () -> Label)
}
extension Button where Label == Text {
    public init(_ title: String, action: @escaping @MainActor () -> Void)
}

// Toggle.swift  (lane 1)
public struct Toggle<Label: ElementGroup>: Element, StyledElement {
    public init(isOn: Binding<Bool>, @ElementBuilder label: () -> Label)
}
extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>)
}

// Picker.swift  (lane 1)
public struct Picker<SelectionValue: Hashable, Content: ElementGroup>: Element, StyledElement {
    public init(_ title: String, selection: Binding<SelectionValue>,
                @ElementBuilder content: () -> Content)
    public func pickerStyle(_ style: PickerStyle) -> Picker
}
public struct PickerStyle: Sendable, Hashable {        // a closed set today (DD-V item 4)
    public static let automatic: PickerStyle            // = segmented (divergence 81)
    public static let segmented: PickerStyle
    public static let radioGroup: PickerStyle
}
public struct TaggedElement<Content: Element>: Element  // what `.tag` returns; init internal;
                                                        // forwards EVERY Element requirement (DD-AC 5)
extension Element {
    public func tag<V: Hashable>(_ value: V) -> TaggedElement<Self>
}

// Slider.swift  (lane 2)
public struct Slider: Element, StyledElement {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1)
        where V.Stride: BinaryFloatingPoint
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride)
        where V.Stride: BinaryFloatingPoint
}

// Stepper.swift  (lane 2)
public struct Stepper: Element, StyledElement {
    public init<V: Strideable>(_ title: String, value: Binding<V>, in bounds: ClosedRange<V>,
                               step: V.Stride = 1)
    public init<V: Strideable>(_ title: String, value: Binding<V>, step: V.Stride = 1)
    public init(_ title: String, onIncrement: (@MainActor () -> Void)?,
                onDecrement: (@MainActor () -> Void)?)
}

// List.swift  (lane 3) — beside the existing List(_:rowHeight:row:)
extension List {
    public init(_ data: Data, selection: Binding<Data.Element.ID?>, rowHeight: Pixels,
                @ElementBuilder row: @escaping (Data.Element) -> Row)
    public init(_ data: Data, selection: Binding<Set<Data.Element.ID>>, rowHeight: Pixels,
                @ElementBuilder row: @escaping (Data.Element) -> Row)
}

// ForEach.swift  (lane 3)
extension ForEach {
    public init<C: MutableCollection & RandomAccessCollection>(
        _ data: Binding<C>, @ElementBuilder content: @escaping (Binding<C.Element>) -> Content)
        where C.Element: Identifiable, ID == C.Element.ID, Data == [ForEachBindingSlot<C>]
}
public struct ForEachBindingSlot<C: MutableCollection & RandomAccessCollection>  // index + id; opaque
```

`Stepper`'s `V: Strideable` initialisers also require `V: CustomStringConvertible`
only through the accessibility value (`"\(value)"`), which every `Strideable`
standard type satisfies; the implementer may drop the constraint if
`String(describing:)` serves. **Not offered** (each re-owned in `DD-AB`):
`Button(role:)`, `.buttonStyle`, `.toggleStyle`, `.pickerStyle(.menu)`,
`Slider`'s label and `onEditingChanged` parameters, `Stepper`'s label-builder
initialisers, `.tag(_:includeOptional:)`, `List { … }`, `scrollPosition(id:)`.

## 4. Element structure, per control

Every control is a `StyledElement` (so `.accessibilityLabel`, `.disabled`,
`.id`, `.padding`, `.frame`, `.background`, `.onKey` all work) that builds an
**internal legacy element tree** — `Box`es and the caller's label — in
`requestLayout`, stored and forwarded through `prepaint`/`paint` as `List`
does with its `box` (the pattern `Column`/`Row` use for a fixed `Box`). No
control uses an item field (`minSize`, `flexGrow`, `margin`, …) on an
internal node: a record of one inside a proposal container would be reported
`…unconsumed` and trap in production (`LR-AQ`); heights come from **declared
sizes** and **struts** instead. The caller's own `style`/`decoration`/
`handlers` are the outer node's; the control composes its own handlers onto
them in `prepaint` (a caller's `onKey` runs **first**, the control's keys
only if it declined; a caller's `.onClick` replaces a `Button`'s action — the
field-per-modifier rule). **No id path of any existing element moves**: every
control is new, and its internal nodes number from 0 under its own id.

- **`Button`** (`DD-R`): an outer `Box` (flex row, `alignItems: .center`,
  `justifyContent: .center`, horizontal `Style.padding` from the
  `controlSize` table, `cornerRadius` 5, background `.surfaceSecondary`,
  border `.separator` 1) over the label and a zero-width **strut** `Box`
  whose declared height is the table's (13/20/24/28/36). Handlers:
  `onClick = action`, `isFocusable = true`, activation keys (§5). No declared
  `AXNode`: a clickable generic node is already a button that folds its
  label (`AB-G`, BA0/BA2).
- **`Toggle`** (`DD-S`): an outer `Box` row, gap 7, `alignItems: .center`:
  a 14×14 indicator `Box` (declared size, `cornerRadius` 3, background
  `.accent` when on / `.surface` when off, border `.separator` 1 off) and the
  label. Handlers: `onClick` writes `!isOn`, `isFocusable`, Space;
  `axNode = AXNode(role: .checkBox, value: isOn ? "1" : "0")`.
- **`Picker`** (`DD-V`): an outer `Box` row, gap 8, `alignItems: .center`:
  `Text(title)` and the options container — `.segmented`: an internal
  `SegmentRow` group that consumes and plans its options' records (as
  `ListRows` does, `ListRows.swift`'s `consume` + `planLegacyItems`) and
  places them with an internal `EqualWidthRow: ProposalLayout` (every
  segment as wide as the widest, PA1), inside a `Box` with background
  `.surfaceSecondary`, `cornerRadius` 6; `.radioGroup`: a `Box` column, gap 6,
  `alignItems: .flexStart`. The outer node is focusable, takes the arrows
  (§5), and declares `AXNode(role: .radioGroup)`. **Options**: `.tag(v)`
  wraps an element in `TaggedElement`, which reads the innermost **picker
  scope** — a `@MainActor` static stack in `Picker.swift`, pushed by `Picker`
  around each phase of its content and balanced by `defer` — and, inside a
  picker, builds its chrome: a segment `Box` (horizontal padding 12, 24 tall
  by strut, background `.surface` when selected) or a radio row (a 14×14
  circle `Box`, `cornerRadius` 7, `.accent` when selected / `.surface` with a
  `.separator` border, gap **7** (a row is `textW + 21`, PK2/PK3; `DD-AC`
  item 8), then the content). Each option's handlers:
  `onClick` writes its tag; `axNode = AXNode(role: .radioButton, value:
  selected ? "1" : "0", traits: selected ? [.selected] : [])`. Outside a
  picker scope a `TaggedElement` forwards its content's phases unchanged, at
  the content's own id — transparent (record §05 row, `DD-V` item 6).
- **`Slider`** (`DD-W`): a **leaf** — `pass.lowerLegacyLeaf(style, declared:
  style, site: .slider) { pass.frame.requestNativeLeaf { … } }`, `TextField`'s
  shape — greedy on the width (the finite proposed width, else 30), 16 tall.
  `paint` draws a 4-pt track (`.separator`, radius 2) inset by half the
  thumb, its filled part to the thumb's centre (`.accent`), and a 20×16
  capsule thumb (`.surface`, border `.separator`) at `minX + f·(W − 20)`,
  `f` the clamped fraction. Handlers: the internal `valueTrack` target (§6),
  `isFocusable`, arrows, `onAction(AccessibilityAdjustment.self)`;
  `axNode = AXNode(role: .slider, value: <value>)`, value printed without a
  trailing `.0` (SA0 reads `5`).
- **`Stepper`** (`DD-X`): an outer `Box` row, gap 8, `alignItems: .center`:
  `Text(title)` and a 20×24 column `Box` of two 20×12 halves (background
  `.surfaceSecondary`, the column `cornerRadius` 5, a `.separator` hairline
  between), each half an `onClick` target holding a glyph-free mark (a 7×1.5
  bar, and for increment a crossing 1.5×7 bar, as `Box`es). The outer node:
  `isFocusable`, up/down arrows, `onAction(AccessibilityAdjustment.self)`,
  `axNode = AXNode(role: .incrementor, value: <clamped value>)` (nil value
  for the closure initialiser).

## 5. Keyboard (`DD-T`)

Every control is **focusable** (`Handlers.isFocusable`), so `Window.focus(_:)`
and an accessibility focus request reach it; **a click focuses none of them**
(the focus rule stands) **except a selectable `List`** (`DD-Z` item 5). Keys
reach a focused control through its `onKey` after the `Keymap` and a caller's
own `onKey` (§4). One internal table, `ControlKeys.swift` (lane 1, read by
lanes 2 and 3, edited by nobody else), keyed on `TextEditing.platform`:

| control | keys (no modifiers) | Apple | elsewhere |
|---|---|---|---|
| `Button` | activate | Space | Space, Return |
| `Toggle` | toggle | Space | Space |
| `Slider` | adjust (the accessibility step) | ←/↓ decrement, →/↑ increment | same |
| `Stepper` | step | ↓ decrement, ↑ increment | same |
| `Picker` | previous/next option, no wrap | ←/↑, →/↓ | same |
| `List(selection:)` | `DD-Z` item 6 (KY6, KY8) | ↑/↓, ⇧↑/⇧↓ | same |

SwiftUI's own controls ignore all of these here, because Full Keyboard Access
is off (`NSApp.isFullKeyboardAccessEnabled = false`; KY1, KY4, KY5, KY7 read
nothing while KY0's control passes) — **divergence 80, added** (`DD-T`).

## 6. Pointer and wheel infrastructure (lane 2)

- **`Handlers.valueTrack: ValueTrackTarget?`** — internal, the tenth member,
  set only by `Slider` (`TI-B`'s `textInput` precedent): the track's window
  x-range and thumb width, the bounds, the step and the write. It makes the
  element a pointer target (`isPointerTarget`), so the disabled gate and
  `allowsHitTesting(false)` remove it with the hitbox. `Window` dispatches it
  ahead of click dispatch, beside `dispatchTextInput`: a `mouseDown` whose
  topmost opaque hitbox carries one writes the value under the pointer; a
  `mouseDragged` while `active` is that id writes again. It does not focus.
  `HandlerShape` (`ModifierTests`) and `HandlerFingerprint`
  (`OuterModifierMatrixTests`) each gain the field.
- **Divergence 16 retires** (`DD-Y`): `Window.applyScroll` — when the topmost
  opaque hitbox under the pointer is **not** a scroller, the wheel goes to
  the **nearest ancestor** (by `GlobalElementID.parent`) that registered a
  scroll region containing the point **on the same layer**; with none, the
  event stops as today. The multi-line text editor's own branch stays first.
  **A single-line `TextField` is such a click target** (`isPointerTarget`
  includes `textInput`), so its wheel now reaches its scroller too — a
  changed `TextField` answer, ruled by `DD-AC` item 3 and pinned by 2.24.
  Comments that cite divergence 16 as live are updated in the same lane
  (`Box.swift`, `Passes.swift`, `Handlers.swift`, `Window.swift`,
  `FocusTests.swift` ×2, `DemoContent.swift` ×3 — comment-only, 0 px).
- **`ClickDispatch`** (new, internal, `ClickDispatch.swift`): while
  `Window.dispatchClick` runs an `onClick`, `ClickDispatch.modifiers` holds
  the completing mouse event's modifiers (`[]` otherwise, and `[]` for an
  accessibility press); a handler may set `ClickDispatch.focusRequest` to an
  id, which `Window` passes to `focus(_:)` after the handler returns (and
  clears). Its only consumer is lane 3's selectable `List`.

## 7. Selection (`DD-Z`, lane 3)

`List(selection:)` stores a type-erased selection model beside its data —
none / single (`Binding<ID?>`) / multi (`Binding<Set<ID>>`). **The selection
is the binding's**: the list never prunes it (LA5 — a removed datum's id is
kept and its row reselects on return), and reads it fresh each frame. The
lead and anchor rows live in `ListOrigin` (the list's one `StateTable` entry
since `DD-F`, keyed by id alone — a second type at that id would overwrite
it), written through `withState` from input only. Each realised row's `Box`
gains, only when the list has a selection model: `onClick` (pointer rules,
`DD-Z` item 4), background `.accent` when selected, and the internal
`AXNode.selectionHint` (lane 1) when selected — a hint stripped with
`logicalIndex` in `Frame.registerHandlers`, so a selected row records
`isSelected` and writes neither `axNodes` nor a `$ax` slot. **The background
does write one `$anim-color` slot per selected realised row** at its first
paint (`animatedColor`'s baseline), so `TB-AH`'s crossing for a selectable
list is `2n + 6 + s`; a list without `selection:`, or with nothing selected,
adds nothing (`DD-AC` item 1). The list's own handlers gain `isFocusable`
and the arrow keys. A keyboard move enqueues on the `DD-G` queue a request
scoped to the list's parent whose key is the internal
`ListLeadReveal(list:row:)`, which only this list matches (anchor `nil`;
`DD-AC` item 2). **Per frame the list touches only its realised rows**; the
lead's index, its re-derivation and every range are computed in the
handlers (`DD-AC` item 4). **While the window is unbounded** a selectable
row has no `logicalIndex` and publishes as a button labelled by its content,
with `.press` and `isSelected`; bounded, a `.row` (`DD-AC` item 6).

## 8. Accessibility (`DD-U`, lane 1)

- `AXRole` gains `.checkBox`, `.radioButton`, `.radioGroup`, `.slider`,
  `.incrementor`; `MetalUIPlatform.AccessibilityRole` the same five; AppKit
  maps them to `.checkBox`, `.radioButton`, `.radioGroup`, `.slider`,
  `.incrementor` and answers `accessibilityValue` with an `NSNumber` when the
  role is one of `checkBox`/`radioButton`/`slider`/`incrementor` and the
  string parses as a number (TA0 value 0/1, SA0 5, STA0 1); AccessKit
  (`Backends/SDL`) maps them to check box, radio button, radio group, slider
  and spin button, setting the toggled state from `"1"`/`"0"` and a numeric
  value from a number.
- `AB-G`'s combination (`AccessibilityTreeBuilder.combine`) folds a
  `.checkBox` and a `.radioButton` exactly as a `.button` (full fold, TA0,
  PA1/PA2 — kids=0), and **partially folds** an `.incrementor` and a
  `.radioGroup`: their non-interactive descendants' text becomes the label
  (when none is declared) and is not published; their interactive
  descendants stay as children — so the title is the control's own label
  (**divergence 82, added**: SwiftUI publishes it as a sibling static text
  beside an unlabelled control, STA0/PA0–PA2).
- `AXNode.selectionHint` (internal) → `AccessibilityNode.isSelected`, stripped
  before the emptiness test as `logicalIndex` is (`AB-L`, `AB-U`).
- Actions stay derived from live handlers (`AB-H`): press from the hitbox,
  increment/decrement from the `AccessibilityAdjustment` handler.

## 9. Files, and three lanes

Lanes run **in order 1, 2, 3**, one at a time. **Source files are disjoint**;
the only overlap is **append-only arms in shared registry tests**
(`DisabledTests`' D2 guard, `InputDispatchTests`' per-conformer click list,
`LayoutAuthorityTests`' legacy-site list), each arm added by the lane that
adds its site — sequential lanes attribute a red by commit, the reason
`DD-A`'s critic-round amendment accepted for part 1.

1. **Lane 1 — `Button`, `Toggle`, `Picker`; accessibility roles** (`DD-R`,
   `DD-S`, `DD-T`, `DD-U`, `DD-V`). New: `Sources/MetalUI/Button.swift`,
   `Toggle.swift`, `Picker.swift`, `ControlKeys.swift`. Edits:
   `Sources/MetalUI/AXNode.swift` (roles, `selectionHint`),
   `AccessibilityTreeBuilder.swift` (roles, folds, hint),
   `Frame.swift` (the hint strip only), `Sources/MetalUIPlatform/AccessibilityTree.swift`,
   `Sources/MetalUIAppKit/AppKitAccessibility.swift`,
   `Backends/SDL/Sources/MetalUISDL/AccessKitTree.swift`,
   `AccessKitAdapter.swift`. Tests: `ButtonTests.swift`, `ToggleTests.swift`,
   `PickerTests.swift`, `ControlAccessibilityTests.swift`,
   `ControlsCompileGuards.swift` (new); `Backends/SDL/Tests/MetalUISDLTests/AccessKitTests.swift`
   (+1); registry arms.
2. **Lane 2 — `Slider`, `Stepper`; pointer, wheel, click dispatch** (`DD-W`,
   `DD-X`, `DD-Y`, `DD-Z`'s dispatch half). New: `Sources/MetalUI/Slider.swift`,
   `Stepper.swift`, `ValueStepping.swift` (pure: the slider's adjustment and
   grid, the stepper's clamp), `ClickDispatch.swift`. Edits:
   `Handlers.swift` (`valueTrack`, `isPointerTarget`), `Window.swift`
   (`valueTrack` dispatch, `applyScroll`, `ClickDispatch` in `dispatchClick`
   and the accessibility press), `LayoutAuthority.swift`
   (`LoweringSite.slider`). Tests: `SliderTests.swift`, `StepperTests.swift`,
   `WheelAndClickDispatchTests.swift`, `SliderStepperCompileGuards.swift`
   (new); `InputDispatchTests.swift` (the renamed divergence-16 test),
   `FocusTests.swift` (its two comments citing the old name), comment-only
   edits in `Box.swift`, `Passes.swift` and
   `Sources/MetalUIDemoContent/DemoContent.swift` (`DD-AC` item 3), `ModifierTests.swift`
   and `OuterModifierMatrixTests.swift` (the field); registry arms.
3. **Lane 3 — `List(selection:)`, `ForEach(_: Binding<C>)`, the controls
   demo** (`DD-Z`, `DD-AA`). Edits: `Sources/MetalUI/List.swift`,
   `ForEach.swift`; new `Sources/MetalUIDemoContent/ControlsDemo.swift`;
   edit `Sources/MetalUIDemo/main.swift` (`METALUI_CONTROLS_DEMO=1`). Tests:
   `ListSelectionTests.swift`, `ForEachBindingTests.swift`,
   `SelectionCompileGuards.swift` (new);
   `Tests/MetalUICrossPlatformTests/DemoStackBudgetTests.swift` (the new tree
   in `buildEveryProductionTree`). Lane 3 records each control's deepest
   native level and the controls demo's through a real `Window` (at most 40,
   against `maxDepth` 72; `DD-AC` item 10) and runs the gated 100k test.

`Tests/MetalUITests/FocusTests.swift` declares a file-private `final class
Toggle`, which shadows `MetalUI.Toggle` inside that file only — harmless, and
not renamed.

`swift package clean` before each lane's count: `Handlers`, `AXNode` and
`List` (public types used across the test module) gain stored properties, and
`AXRole`/`AccessibilityRole` gain cases.

## 10. Tests, by lane — each with its red-before and the mutation that must redden it

"Red before" for a new public type is **does not compile at `27b2fcc`**;
each such test is additionally shown to discriminate by its named mutation,
run in an isolated worktree, commit first, restore from a copy, full
unfiltered suite, `git status --short` after, every reddened test named.
Literals are derived before the run from MetalUI's own measured `Text`
sizes (`textW`, `textH` of the label in the test's text system), never from
SwiftUI's points, except where the arm's number is structural (padding,
strut height, gap).

### Lane 1 (24 tests + 2 guards; `Backends/SDL` +1)

| # | test | asserts | red before | mutation that must redden it |
|---|---|---|---|---|
| 1.1 | `aButtonIsItsLabelPaddedTwelveASideAndTwentyFourTall` | `Button("Go")` is `(textW + 24) × max(textH, 24)` (BT0) | no type | M1a: padding 12 → 11 |
| 1.2 | `aButtonReadsControlSizeForItsChromeButNotItsLabelsFont` | per size, width `textW + 2·{8,10,12,14,18}`, height `max(textH, {13,20,24,28,36})`, the label's own size identical across sizes (BT4, BT5; divergence 76 amended) | no type | M1b: the chrome reads `.regular` whatever the environment |
| 1.3 | `aButtonRunsItsActionOncePerClickAndNotOnAPressReleasedOutside` | click → 1; press in, release out → 0 | no type | M1c: `Button` leaves `onClick` unset (also reddens 1.4, 1.7) |
| 1.4 | `aFocusedButtonActivatesOnSpaceAndOnReturnOnlyOffApple` | `ControlKeys.activatesButton(_:platform:)` for both platforms; through a `Window` on the host platform, Space → 1, Return → 0 on Apple | no type | M1d: Return activates on Apple |
| 1.5 | `aButtonIsFocusableButAClickDoesNotFocusIt` | `lastFocusRegistry.isFocusable(id)`; after a click `focusedElement == nil` | no type | M1e: `isFocusable` false (also reddens 1.4) |
| 1.6 | `aCallersOnKeyRunsBeforeTheButtonsActivation` | a caller `onKey` claiming Space suppresses the action; one declining lets it run | no type | M1f: the activation replaces the caller's `onKey` |
| 1.7 | `aButtonPublishesOneAXButtonLabelledByItsLabel` | one `.button` node, label `"Go"`, no children, `.press`; `.press` request runs the action once (BA0, BA2) | no type | M1c |
| 1.8 | `aDisabledButtonRunsNothingAndPublishesDisabled` | click, focused Space and `.press` all 0; `isEnabled == false` (BA1) | no type | M1g: the `enabled` conjunct removed from `Frame.registerHandlers`' hitbox insert and focus registration (the central gate; must also redden the existing D2 guard) |
| 1.9 | `aToggleIsAFourteenPointCheckboxSevenPointsBeforeItsLabel` | `(14 + 7 + textW) × max(14, textH)` (TG0) | no type | M1h: gap 7 → 8 |
| 1.10 | `aToggleClickSpaceAndPressEachWriteTheNegationOnce` | click → `true`, focused Space → `false`, `.press` → `true`; one binding write each (TA0) | no type | M1i: the write is `isOn`, not `!isOn` |
| 1.11 | `aTogglePublishesALabelledCheckboxWithItsValue` | `.checkBox`, label `"Wi-Fi"`, value `"0"` then `"1"`, no children (TA0) | no type | M1j: `.checkBox` left out of the full fold |
| 1.12 | `aDisabledToggleWritesNothingAndPublishesDisabled` | TA3 | no type | M1g, re-run on this arm |
| 1.13 | `aTogglesIndicatorColourAnimatesUnderWithAnimation` | mid-flight (`simulateTick`) the indicator's fill lies strictly between `.surface` and `.accent` | no type | M1k: the indicator painted by `Toggle.paint` with `pass.fill`, not a `Box` |
| 1.14 | `aSegmentedPickerMakesEverySegmentAsWideAsTheWidest` | three labels of different `textW`; every segment `max(textW) + 24` wide, the row `3×` that, the whole `titleW + 8 + row` (PK1, PA1) | no type | M1l: `EqualWidthRow` places each at its own ideal width |
| 1.15 | `pressingAnOptionWritesItsTag` | enum tags (not indices): a click on the third segment writes `.gamma`; a `.press` on the first writes `.alpha` (PA1, PA2) | no type | M1m: the option writes its position |
| 1.16 | `aSelectionMatchingNoTagSelectsNothingAndWritesNothing` | no option `.selected`, no write over two frames (PA3) | no type | M1n′: an unmatched selection writes the first tag |
| 1.17 | `aPickerPublishesARadioGroupTitledByItsTitle` | `.radioGroup` label `"Flavor"`, three `.radioButton` children labelled by option, value `"1"` + `.selected` on the chosen one only (PA1, PA2; divergence 82) | no type | M1n: the partial fold removed (also reddens 1.22) |
| 1.18 | `aRadioGroupPickerStacksItsOptionsSixPointsApart` | column of rows `14 + 7 + textW_i`, gap 6, leading-aligned (PK1, PK2/PK3; `DD-AC` item 8) | no type | M1o: gap 6 → 8; M1o′: the row's indicator gap 7 → 6 |
| 1.19 | `aFocusedPickerMovesItsSelectionWithTheArrowsAndDoesNotWrap` | → from the last writes nothing, ← from the first nothing, → from the first writes the second | no type | M1p: wrap-around |
| 1.20 | `aTagOutsideAPickerChangesNothing` | `Text("A").tag(1)` in a `Row` gives the scene, bounds and `StateTable` ids of `Text("A")`; **and** `Box().flexGrow(1).tag(1)` beside a fixed box in a `Row` keeps its grown width (`DD-AC` item 5) | no type | M1q: `TaggedElement` builds its segment chrome with no scope; M1q′: it forwards only the three phases (the container arm) |
| 1.21 | `theFiveControlRolesReachTheAppKitBridge` | roles `AXCheckBox`, `AXRadioButton`, `AXRadioGroup`, `AXSlider`, `AXIncrementor`; `accessibilityValue` an `NSNumber` for the four valued roles | no case | M1r: `.checkBox` mapped to `.button` in AppKit |
| 1.22 | `aPartialFoldKeepsInteractiveChildrenAndTakesTheRestAsTheLabel` | a `Box` declaring `.incrementor` over a `Text` and two clickable `Box`es: label = the text, two children | no case | M1n |
| 1.23 | `aSelectionHintPublishesSelectedAndWritesNoAXSlot` | a `Box` with `selectionHint`: `isSelected` true; no `axNodes` entry, no `$ax` id in `StateTable` | no field | M1s: the hint not stripped before the emptiness test |
| 1.24 | `aDisabledPickerWritesNothingAndPublishesDisabled` | a segment click, focused arrows and a `.press` write nothing; the group and every radio button publish disabled (PA4; `DD-AC` item 7) | no type | M1g, re-run on this arm |
| G1.1 | `theControlsSwiftUISpellingsCompileFromOutsideTheModule` (plain import, `typecheckFile`) | §3's lane-1 spellings with a `@State` projection | — | MG1.1: `Toggle.init(_:isOn:)` made internal |
| G1.2 | `aMenuPickerStyleIsNotOffered` | `.pickerStyle(.menu)` fails to typecheck | — | MG1.2: `static let menu` added |
| SDL | `theFiveControlRolesMapToAccessKitWithToggledAndNumericValues` | role codes; toggled from `"1"`/`"0"`; numeric value | no case | MS1: toggled dropped |

Registry arms: `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`
(`Button`, `Toggle`, a segment); `onClickIsLiveOnEveryConformerThatCanRegisterOne`
(`Button`).

### Lane 2 (23 new tests + 1 renamed + 1 guard)

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 2.1 | `aSliderIsGreedyOnTheWidthAndSixteenTall` | 300×16 under a 300 proposal; 30 wide at a nil width (SL0) | no type | M2a: height 20 |
| 2.2 | `anUnsteppedAdjustmentMovesTenPercentOfTheSpan` | 5 → 6 on 0…10, 5 → 25 on 0…200 (SA1, SA7) | no type | M2b: 5% |
| 2.3 | `aSteppedAdjustmentLandsOnTheGridRoundingHalfUpAndNeverPastTheLastPoint` | 5 +2 → 8 → 10, −2 → 8 (SA3); 9 +3 → 9 on 0…10 (SA4) | no type | M2c: round half down; M2c′: no last-grid-point clamp |
| 2.4 | `anOutOfRangeValueIsDrawnClampedAndWrittenOnlyWhenAdjusted` | 15 on 0…10: thumb at the maximum, no write over two frames, − → 9 (SA5, SA6) | no type | M2d: the clamp written back in `prepaint` |
| 2.5 | `anAdjustmentAtTheMaximumStillWrites` | one write of 10 (SA2) | no type | M2e: an unchanged value not written |
| 2.6 | `aPressOnTheSliderSetsTheValueUnderThePointerAndADragFollows` | press at a derived x → derived value (stepped); drag → second value; the drag past the end → the bound | no type | M2f: `mouseDragged` not dispatched to `valueTrack` |
| 2.7 | `aFocusedSliderAdjustsByTheAccessibilityStepOnTheArrows` | → and ↑ +, ← and ↓ − | no type | M2g: ↑/↓ unhandled |
| 2.8 | `aSliderPublishesAnAdjustableSliderWithItsValue` | `.slider`, value `"5"`, label nil, `.increment`/`.decrement` (SA0) | no type | M2h: the adjustment handler not registered |
| 2.9 | `aDisabledSliderNeitherTracksNorAdjustsAndPublishesDisabled` | press, drag, arrows, adjust: no write (SA9) | no type | M2i: the track's hitbox registered through `pass.insertHitbox` directly (as a scroll region is) rather than `registerHandlers` — bypassing the gate |
| 2.10 | `aSliderTrapsOnANonPositiveStepOrNonFiniteBounds` | exit test (`#expect(processExitsWith: .failure)`) for step 0, step −1, bounds `0...Double.infinity` | no type | M2j: the precondition removed |
| 2.11 | `aStepperIsItsTitleEightPointsAndATwentyByTwentyFourControl` | `(textW + 8 + 20) × max(textH, 24)`; empty title 28 × 24 (ST0) | no type | M2k: gap 6 |
| 2.12 | `aStepperClampsIntoItsRangeAndWritesNothingWhenTheValueWouldNotMove` | STA1, STA2, STA3 through half clicks and adjust requests | no type | M2l: an unchanged value written |
| 2.13 | `anOutOfRangeStepperStepsFromItsClampedValue` | 5 on 0…3: shows 3; + writes 3; − writes 2 (STA4) | no type | M2m: stepping from the raw value |
| 2.14 | `anUnboundedStepperDoesNotClamp` | 1 → 2 → 1 → 0 → −1 (STA5) | no type | M2n: an unbounded stepper clamped at 0 |
| 2.15 | `aClosureStepperRunsItsClosuresAndANilOneDisablesItsDirection` | STA6 | no type | M2o: a nil `onDecrement` falls back to `onIncrement` |
| 2.16 | `aStepperPublishesALabelledIncrementorWithTwoArrowButtons` | `.incrementor`, label `"Qty"`, value `"1"`, two `.button` children (STA0; divergence 82) | no type | lane 1's M1n, re-run on this lane's head |
| 2.17 | `aFocusedStepperStepsOnTheUpAndDownArrows` | ↑ +1, ↓ −1 | no type | M2p: ↑/↓ swapped |
| 2.18 | `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller` (**renamed** from `aClickTargetInsideAScrollViewSwallowsTheWheel`, first arm inverted 0 → 37) | the wheel over the button moves the scroller | red: reads 0 at `27b2fcc` | M2q: the rule reverted |
| 2.19 | `aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel` | a `Stack` sibling covering a `ScrollView`: 0 | green at base (pins the ancestry clause) | M2r: ancestry dropped (layer only) |
| 2.20 | `aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel` | a scrim declared inside the scroller's content: 0 | green at base (pins the layer clause) | M2s: the layer clause dropped |
| 2.21 | `aClickHandlerSeesItsClicksModifiersAndOnlyDuringTheClick` | ⌘ on the mouse-up read inside the handler; `[]` after; `[]` for a `.press` | no type | M2t: `modifiers` not reset |
| 2.22 | `aClickHandlersFocusRequestIsHonouredAfterItReturns` | `focusedElement == id` after the click; a non-focusable id is cleared at the frame boundary | no type | M2u: the request ignored |
| 2.23 | `aDisabledStepperStepsNothingAndPublishesDisabled` | half clicks, focused ↑/↓ and increment/decrement requests write nothing; the incrementor publishes disabled (STA7; `DD-AC` item 7) | no type | M1g, re-run on this arm |
| 2.24 | `aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller` | a wheel over the field moves the scroller; a press still focuses it (`DD-AC` item 3) | red: reads 0 at `27b2fcc` | M2q (the rule reverted); M2v: the `textInput` target excluded from the ancestor walk |
| G2.1 | `theSliderAndStepperSpellingsCompileFromOutsideTheModule` | §3's lane-2 spellings | — | MG2.1: `Slider.init(value:in:step:)` internal |

Registry arms: D2 (`Slider`, a `Stepper` half), `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`
(`.slider`), `HandlerShape`/`HandlerFingerprint` (`valueTrack`).
**2.18 is a changed answer, not a retirement**: its second arm (off the
button, 37) is unchanged; the record's retirement table lists it.

### Lane 3 (21 tests + 1 guard)

| # | test | asserts | red before | mutation |
|---|---|---|---|---|
| 3.1 | `aPlainClickSelectsExactlyTheClickedRow` | single `nil` → `2`; multi `[1, 3]` → `[2]` (LB3's replace) | no init | M3a: a multi click inserts |
| 3.2 | `aShortcutClickTogglesARowInAMultiSelectionList` | ⌘ (Apple) / ctrl (elsewhere, via the table) toggles in and out | no init | M3b: the toggle replaces |
| 3.3 | `aShiftClickSelectsTheRangeFromTheAnchor` | anchor 1, ⇧-click 3 → `[1, 2, 3]` | no init | M3c: the range excludes the anchor |
| 3.4 | `aSingleSelectionListSelectsTheClickedRowWhateverTheModifiers` | ⌘/⇧ click → that row | no init | M3d: ⌘ deselects in single mode |
| 3.5 | `aPressOnARowFocusesItsList` | `focusedElement == list` after a row click | no init | M3e: no `focusRequest` |
| 3.6 | `theArrowsMoveASingleSelectionAndStopAtTheEnds` | KY6, KY6b, KY6c, KY6d, KY6e, KY6f, write counts included | no init | M3f: wrap at the ends |
| 3.7 | `aPlainArrowCollapsesAMultiSelectionAndShiftExtendsFromTheAnchor` | KY8, KY8b, KY8e, KY8f, KY8g | no init | M3g: shift extends from the lead, not the anchor |
| 3.8 | `neitherCommandANorSpaceChangesASelection` | KY8c, KY8d | no init | M3h: ⌘A selects all |
| 3.9 | `aSelectedRowPublishesSelectedAndAnUnselectedOneDoesNot` | `isSelected` per row (LA1, LB1) | no init | M3i: the hint never set |
| 3.10 | `aSelectionNamingARemovedRowIsKeptAndReselectsItOnReturn` | no write; the row selected again (LA5) | no init | M3j: stale ids pruned |
| 3.11 | `aDisabledListShowsItsSelectionAndChangesNothing` | LD0; clicks and arrows write nothing | no init | M1g, re-run on this lane's head |
| 3.12 | `anArrowPastTheWindowScrollsTheNewLeadIntoView` | 100 rows, lead at the last visible row, ↓ → offset moved just enough, the row realised; arm 3.12b: a sibling above the list whose `.id` equals the lead's id does not take the scroll (`DD-AC` item 2) | no init | M3k: no reveal request; M3k′: the request keyed by the bare `datum.id` (reddens 3.12b) |
| 3.13 | `aSelectableListScrollsUnderTheWheelOverARow` | the joint test with `DD-Y` | red at base: rows are click targets that swallow | lane 2's M2q, re-run on this lane's head |
| 3.14 | `aSelectedRowPaintsTheAccentBackground` | the row's fill is `theme.accent`; unselected none | no init | M3l: no background |
| 3.15 | `aSelectableListAddsOneColourSlotPerSelectedRowAndNoAXSlot` (renamed by `DD-AC` item 1: the design's "no entry" was red by construction) | over two frames: nothing selected → the same entry count as without `selection:`; `s` selected realised rows → exactly `s` more, each an `$anim-color` slot, no `$ax` id | no init | M3m: `.selected` declared as a trait (writes `$ax`) |
| 3.16 | `anAccessibilityClientSelectsARowByPressingItAndCannotSetSelectedDirectly` | `.press` on a row replaces the selection; the AppKit element's `setAccessibilitySelected(true)` changes nothing (divergence 83) | no init | M3n: rows' press not wired (no `onClick` under `.press`) |
| 3.17 | `aForEachOverABindingHandsEachElementItsOwnBinding` | toggling row 1 writes `items[1].done` only | no init | M3o: every slot bound to index 0 |
| 3.18 | `aStaleElementBindingDropsItsWriteAndKeepsItsLastRead` | a handler captured before its item was removed: no write, no trap, last read returned | no init | M3p: the id check removed (writes the item now at that index) |
| 3.19 | `theControlsDemoPublishesEveryControlsRole` | `controlsDemoContent()` through a real `Window`, a client active: a button, a check box, a slider, an incrementor, a radio group, a table with one selected row | no tree | M3q: the demo's list built without `selection:` |
| 3.20 | `anUnboundedSelectableListPublishesButtonRowsAndABoundedOneTableRows` | no scroller: each row a `.button` labelled by its text with `.press`, the selected one `isSelected`; inside a scroller after its first frame: `.row`s with index, `.press`, `isSelected` (`DD-AC` item 6) | no init | M3s: `logicalIndex` set on unbounded rows too (reddens the first arm) |
| 3.21 | `aSelectableListsWarmFrameTouchesOnlyItsRealisedRows` | a counting `RandomAccessCollection`: a warm frame's element accesses equal at 500 and 5 000 rows with a selection whose lead is absent (`DD-AC` item 4) | no init | M3r: the lead re-derived by a data scan in `requestLayout` |
| G3.1 | `theSelectionAndBindingForEachSpellingsCompileFromOutsideTheModule` | §3's lane-3 spellings | — | MG3.1: the `Set` initialiser internal |

`everyProductionTreeBuildsOnAOneMegabyteThread` builds `controlsDemoContent()`
too (edited, not new).

**Expected totals** (critic round, `DD-AC`): **1556 + 26 + 24 + 22 = 1628
tests** (lane 2's rename adds none), guards **96 + 4 = 100**, `Backends/SDL`
`MetalUISDLTests` 22 → 23 on macOS.

## 11. Must not move, and the demo expectation

- **Pixels**: the default demo builds no control and no selectable list, and
  divergence 16's rule is input-only, so **all fourteen offscreen images read
  0 px against `27b2fcc`** (`docs/probes/demo-pixels/compare.sh`), and
  `Tests/MetalUICrossPlatformTests/Expected.swift` is **unedited**. The
  controls demo is reached only with `METALUI_CONTROLS_DEMO=1` and owes a
  human look (record §03): every control, the selectable list, keyboard use,
  the wheel over a row.
- **State retention**: no id path of an existing element moves;
  `theSevenRetentionSlotsAreMutuallyDistinct` unmoved (no new reserved name —
  the lead/anchor ride `ListOrigin`); `TB-AH` unmoved for every list without
  `selection:`, and for one with it moved by exactly its selected realised
  rows' colour slots (`2n + 6 + s`, 3.15, `DD-AC` item 1).
- Hit testing moves exactly by `DD-Y` (divergence 16, including the
  single-line `TextField`, `DD-AC` item 3) and `valueTrack`; focus
  moves exactly by `DD-Z` item 5; accessibility moves by the five roles, the
  folds and the hint; animation, the scrim, `Deferred`, `List` windowing,
  `TextField`/`TextEditor` do not move.
- `everyProductionTreeBuildsOnAOneMegabyteThread` green (with the new tree);
  0 `warning:` on both build systems; `MetalUILayout` imports only
  `MetalUICore`; `Backends/SDL` builds and tests on macOS and in a
  `swift:6.4-noble` container; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
  green. Real-window capture per the lock probe.

## 12. Divergences and records

- **16 retires** (`DD-Y`); **76 amended, kept** (`DD-R` item 4; its
  control-metrics remainder also names the empty-label toggle's 19-pt
  height, TG0, `DD-S` critic round).
- **80 added** — controls take keyboard focus and keys whatever the system's
  Full Keyboard Access setting (`DD-T`); pinned by 1.4/1.5.
- **81 added** — `Picker`'s automatic style is segmented, where SwiftUI's
  is a pop-up menu (PK0, PA0); `.menu` not offered (`DD-V`); also named
  (critic round): SwiftUI's segmented control is `n·w + 1` wide (PK1, PK3)
  and its radio rows 6.5 apart in PK1, MetalUI's `n·w` and 6; pinned by G1.2,
  1.14 and 1.18.
- **82 added** — a titled control (`Stepper`, `Picker`) publishes its title
  as its own label, where SwiftUI publishes a sibling static text beside an
  unlabelled control (STA0, PA0–PA2) (`DD-U`); also named (critic round):
  MetalUI publishes no slider `AXValueIndicator` child (SA0) and enables a
  stepper's arrow buttons that AppKit publishes DISABLED (STA0); pinned by
  1.17, 2.8 and 2.16.
- **83 added** — an accessibility client selects a `List` row by pressing
  it; `AXSelected`/`AXSelectedRows` writes change nothing, where SwiftUI's
  accept both (LA2–LA4, LB2, LB3) (`DD-Z` item 8); and a selectable list
  whose window is unbounded publishes its rows as buttons, where SwiftUI's
  are always `AXRow`s (LA0; `DD-AC` item 6); owner **plan task 12**; pinned
  by 3.16 and 3.20.
- **84 added** — a `List` answers its content height and needs an enclosing
  `ScrollView`, its rows share one declared `rowHeight`, and it is
  data-driven only, where SwiftUI's is greedy and scrolls itself (L0, L1, K6)
  and takes any rows (`DD-AB` item 3); owner none; pinned by the existing
  `List` layout tests.
- Live count **56 → 60** (one retires, five are added).
- Record §05: **one row added** — `.tag(_:)` outside a `Picker` (`DD-V`
  item 6). Record §03: the controls demo look and the pointer rules
  (unmeasured in SwiftUI: CK0, WH0 failed).
