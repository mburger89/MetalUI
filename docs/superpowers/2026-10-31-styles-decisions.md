# Button, toggle and picker styles — decisions (prefix `BY-`)

Rulings for round 3, item R3-1: `ButtonStyle` and `PrimitiveButtonStyle` as open protocols, `.borderedProminent`,
`.link`, `toggleStyle(_:)` with an open `ToggleStyle`, and `.pickerStyle(.inline)`. Branch `feat/button-styles`. Code:
`Sources/MetalUI/ButtonStyle.swift`, `ToggleStyle.swift`, `Button.swift`, `Toggle.swift`, `PasteButton.swift`,
`Picker.swift`, `Frame.pointerOwner` (stamped in `Window.swift`). Tests: `ButtonStyleTests.swift`, `ToggleStyleTests.swift`,
`StyleCompileGuards.swift`. **Next unused: `BY-L`.** Divergence 885 (reserved 885–894; 886–894 unused). Supersedes `IX-E` item 2
(the closed `ButtonStyle` struct) and `DD-AB` item 7 / `IX-M` (the absent toggle styles and `.inline`).
**None of the looks is measured** (the probe capture draws no text and SwiftUI's chrome for these styles was not probed
in this round): sizes, fills and the pressed looks are MetalUI's, human check group BY.

## BY-A: `ButtonStyle` is SwiftUI's protocol, applied through the environment

`public protocol ButtonStyle { associatedtype Body: ElementGroup; @MainActor @ElementBuilder func makeBody(configuration:) -> Body }`
with `ButtonStyleConfiguration { role, label, isPressed }` (initialiser internal). `.buttonStyle(_:)` is an
`ElementGroup` modifier returning `EnvironmentScope<Self>` (the shape of `.controlSize`): it reaches every `Button` below,
the nearest writer wins, and it is available after a wrapper (`Button(..).padding(8).buttonStyle(.plain)` now compiles,
as in SwiftUI; `PE-R`'s separating arm moved to `.keyboardShortcut`). `Button` also has its own `.buttonStyle(_:)` returning
`Self` (a stored `ownStyle`, nearer than the environment), so `Button(..).buttonStyle(.plain).keyboardShortcut(..)` keeps compiling.
The style is stored in `EnvironmentValues` through a **custom key** (`ButtonStyleKey`), so it needs no fingerprint field:
the reading is the built-in look, or `EnvironmentReading.of(style)` for a custom style (a style that is `Equatable`
compares by `==`, one holding a closure is uncomparable and makes a retained subtree ineligible, `EE-F`).
**The old closed struct `ButtonStyle` is gone** and its call sites (`.plain`, `.bordered`, `.borderless`, `.automatic`,
`.glass`, `.glassProminent`) keep compiling; only code that named the type changes (`[ButtonStyle]` becomes
`[any PrimitiveButtonStyle]`, `docs/migration.md`). The built-ins are public structs — `DefaultButtonStyle`,
`BorderedButtonStyle`, `BorderedProminentButtonStyle`, `BorderlessButtonStyle`, `PlainButtonStyle`, `LinkButtonStyle`,
`GlassButtonStyle`, `GlassProminentButtonStyle` — all `PrimitiveButtonStyle`s with statics on
`PrimitiveButtonStyle where Self == …`, SwiftUI's shape. `Button` recognises them by an internal marker and draws its own
chrome (`ButtonLook`, the old `Kind`); their `makeBody` returns the bare label (delegating to one from a custom style draws the label alone).
A custom body is built **at layout**, every frame the button is laid out, as `ProgressView` builds its body (`ProgressViewStyle`
is the precedent), erased with `AnyElement` and laid out under the button's own id inside one `Box` that carries the
button's handlers, focus ring and (chrome-dropped) decoration. `Button.Layout`/`PrepaintState` are enums
(`Picker`'s precedent): the chrome arm is today's box byte for byte, so every existing `Button` test stands.

## BY-B: `PrimitiveButtonStyle` and `trigger()`

`PrimitiveButtonStyleConfiguration { role, label, trigger() }`. A primitive style owns the click: `Button` registers **no**
`onClick`, so `configuration.label.onClick { configuration.trigger() }` is the usual body and a style that never triggers
runs nothing on a click. `trigger()` runs the action (or a caller's `.onClick`, `DD-R` item 1's replacement rule). It can be
called any number of times. SwiftUI's behaviour for a never-triggering style, and for the accessibility action, is
**unprobed**; the choice here follows from the type (the style gets the interaction).

## BY-C: what `Button` keeps under a custom style

Focusable (Tab reaches it), a focused Space runs the action (`ControlKeys.activatesButton`; Return only off macOS, as before),
the keyboard shortcut, the `.disabled` gate in `registerHandlers`, the 0.5 disabled scope and the 2-point focus ring — all
unchanged, all on the outer `Box`. A `ButtonStyle` (not primitive) also keeps the click and the accessibility press, because
the outer box carries `onClick` (a clickable generic node is a button, `AB-G`). **A primitive style's accessibility press
comes from whatever clickable element its body declares** (its own `onClick`); the outer node is focusable and keyed but
has no `onClick`, so a primitive style that attaches none has no accessibility press (a documented limit, carried to
the human check BY with VoiceOver).

## BY-D: `isPressed` is a layout-time answer from the previous frame's hitboxes

SwiftUI's `isPressed` is true while the pointer is pressed on the button **and** over it (probe `B0`–`B2`). MetalUI resolves
hover only after prepaint (`Frame.resolveHover`), but a style's body is built at layout. `Window` therefore stamps
`Frame.pointerOwner` — the topmost opaque hitbox owner under the **current** pointer position in the **previous** frame's
captured hitboxes (`topmostHitboxOwner`) — and a custom button reads `activeElement == id && pointerOwner == id`. This is exact
while the layout under the pointer did not move; when it did, `paint` compares its own resolved `isActive && isHovered` with the
value the body was built with and calls `requestAnotherFrame()` (a correction frame, not an animation). A bare `Frame`
(no window, no pointer) is never pressed. The built-in chrome keeps its paint-time wash (`IX-E` item 3), unchanged.
`.equatable()` subtrees do not replay under a pressed element (`SB-X`), so a custom pressed look inside one still updates.

## BY-E: `StyleLabel`

`configuration.label` is a `StyleLabel`: a public, MetalUI-only styled element (`StyledElement`, so `.padding`, `.background`,
`.onClick`, `.frame(width:)`… apply as to a `Box`) that holds the button's or toggle's label content erased in an `AnyElement`
built at layout inside one `Box` (so the label is one extra flex node). `ButtonStyleConfiguration.Label` and the other two
configurations' `Label` are typealiases of it, so SwiftUI's `Configuration.Label` spelling compiles. It exists as a named public
type because the configurations are public and `Element` conformances cannot be opaque here.

## BY-F: `ToggleStyleConfiguration` and `isMixed`

`ToggleStyleConfiguration { label, @Binding isOn, @Binding isMixed }`, SwiftUI's shape (`@Binding` is a property wrapper here
too, so `configuration.isOn`, `configuration.isOn.toggle()` and `configuration.$isOn` all work). `isMixed` is `Binding.constant(false)`:
`Toggle(sources:isOn:)` is not built, so a toggle is never mixed. The initialiser is internal.

## BY-G: `.borderedProminent` and `.link`

`.borderedProminent`: the bordered metrics (padding and strut by `controlSize`), the fill `controlAccent` (accent in the key
window, the separator colour out of it, `IX-H`), no border, and a **white** label — the label's `foregroundStyle` is set in a
`withEnvironment` around the box in all three phases (as `EnvironmentScope` does), so a `Text` naming its own colour keeps it.
Pressed it takes the bordered style's `.textPrimary` 12 % wash. `.link`: the plain look (label alone at its own size, 60 % while
pressed) with the label in the accent colour. SwiftUI's pointing-hand cursor and hover underline for links are **not**
drawn (carried: `.pointerStyle(.link)` exists, `CI-J`, but wiring a built-in style to it was not asked and not measured).

## BY-H: `ToggleStyle` is SwiftUI's protocol, applied through the environment

As `BY-A`, with a custom key `ToggleStyleKey`, `.toggleStyle(_:)` on every `ElementGroup` (`EnvironmentScope<Self>`) and on `Toggle`
(`Self`, stored `ownStyle`). Built-ins: `DefaultToggleStyle` (`.automatic`, the checkbox on macOS), `CheckboxToggleStyle`,
`SwitchToggleStyle`, `ButtonToggleStyle`, statics on `ToggleStyle where Self == …`. **`.checkbox` is the unstyled `Toggle` byte for
byte.** A custom body keeps the toggle's behaviour: a click, a focused Space and an accessibility press write `!isOn` once
(`DD-S`), the node is published as a `.checkBox` with value `"1"`/`"0"`, the focus ring and disabled scope surround the body.
A style that writes `configuration.isOn` from an `onClick` of its own also works: that element is the topmost hitbox, so
the press reaches it and not the toggle's outer `onClick` (one write, `theConfigurationReportsNotMixedAndItsBindingWrites`).

## BY-I: the `.switch` and `.button` looks

`.switch`: a 38×22 capsule track (accent when on, `.surfaceSecondary` with a 1-point separator border off), an 18-point white
knob inset 2, at the leading end off and the trailing end on, the label 7 after the track. The track is the row's indicator
`Box`; the knob is a `PaintPass.fill` in `paint` positioned from the row's bounds (the track is vertically centred), so it **snaps**
(divergence 885) and no layout id changes: the indicator stays id `[0, 0, 0]` and the label `[0, 0, 1]` in every style.
`.button`: the bordered button's metrics (the indicator is a zero-wide strut of the metrics' height, gap 0), fill `.surfaceSecondary`
with the separator border off and the accent fill with a white label on. No pressed look, no animation of the fill beyond what
the decoration already animates. All metrics are MetalUI's.

## BY-J: `.pickerStyle(.inline)`; `PickerStyle` stays a struct

`PickerStyle.inline` is offered and is `radioGroup`'s kind: on macOS SwiftUI draws `.inline` as the radio-group column, and so
does MetalUI, byte for byte (`anInlinePickerDrawsAsTheRadioGroup`, with the segmented look as the separating arm). The *protocol*
form of `PickerStyle` (a custom picker style) is **carried**, not built: a custom picker style needs the option-scope machinery
(`DD-V` item 2) exposed as a configuration, which is a second design and was not asked. It stays in "Not offered" in
`docs/divergences.md`, with `ProgressViewStyle`/`TextFieldStyle`'s closed forms.

## BY-K: a style struct's `@State` and `@Environment` are bound

A style is not an element, but SwiftUI styles may hold `@Environment` (the common `@Environment(\.isEnabled)`) and `@State`. `Button` and
`Toggle` run `StateBinder.bind(style, in: frame, id: buttonID)` before `makeBody`, the call `AnyElementBox` makes for an
erased element, so a style's `@Environment` reads the button's environment (a `.controlSize(.large)` scope reaches it) and its
`@State` slots are the button's `$state<n>` entries (the button declares none of its own). Pinned by
`aStyleStructsEnvironmentPropertiesAreBound`. No divergence label.

## Carried

- A custom `PickerStyle` protocol, and `ProgressViewStyle`/`TextFieldStyle`/`LabeledContentStyle` as protocols.
- A pressed look for `.button` toggles and for `.link`'s hover cursor; a sliding switch knob (885).
- `ToggleStyleConfiguration.isMixed` ever being true (`Toggle(sources:)`).
