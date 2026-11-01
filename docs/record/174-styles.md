# 174 — Button, toggle and picker styles: open protocols, `.borderedProminent`, `.link`, `.switch`, `.button`, `.inline` (`BY-`)

2026-10-31, branch `feat/button-styles` from master `7d3d1b80`, round 3 item R3-1. Rulings `BY-A`–`BY-K` in
`docs/superpowers/2026-10-31-styles-decisions.md` (prefix row in `docs/rules/decision-prefixes.md`); divergence 885 from the
reserved range 885–894 (179 live; next label 210 unchanged); human check group `BY`. Supersedes `IX-E` item 2 (the closed
`ButtonStyle` struct), `DD-AB` item 7 and the "Not offered" row for `ButtonStyle`/`PrimitiveButtonStyle`/`.toggleStyle`/`.link`/`.pickerStyle(.inline)`.

## What was asked, and what was built

1. `ButtonStyle` as an open protocol with `ButtonStyleConfiguration { role, label, isPressed }`, applied with `.buttonStyle(_:)` and inherited through
   the environment (`BY-A`). Built.
2. `PrimitiveButtonStyle` with `configuration.trigger()` (`BY-B`). Built.
3. The existing built-ins keep their call sites; `.borderedProminent` (accent fill, white label) and `.link` (accent label) added (`BY-G`). Built.
4. `.toggleStyle(_:)` with `.checkbox` (macOS default, byte-identical to the bare `Toggle`), `.switch`, `.button` and the open `ToggleStyle` with
   `ToggleStyleConfiguration { label, @Binding isOn, @Binding isMixed }` (`BY-H`, `BY-I`, `BY-F`). Built.
5. `.pickerStyle(.inline)` (`BY-J`): offered, the radio group's look. `PickerStyle` itself stays a closed struct (carried).

## The design, in the order it was decided

- **Where the style lives.** A custom `EnvironmentKey` (`ButtonStyleKey`, `ToggleStyleKey`), not a new `EnvironmentValues` field, so the retained
  fingerprint (`everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant`) needed no row: the key's reading is the built-in look, or
  `EnvironmentReading.of(style)` for a custom style (an `Equatable` style compares by `==`; one holding a closure is uncomparable and a retained subtree
  holding it is ineligible, `EE-F`). A new internal `EnvironmentValues.setCustom(_:_:reading:)` lets the writer name the reading.
- **How a body is rendered.** `Button` and `Toggle` already had a fixed `Box<…>` layout type, so `Layout`/`PrepaintState` became two-arm enums (the
  precedent is `Picker`'s `Inner`): the chrome arm is today's box byte for byte (every existing button and toggle test stood unchanged), the custom arm is an
  `AnyElement` over one `Box` that carries the control's composed handlers, focus ring and decoration around the style's body, laid out under the control's
  own id with `AnyElement.requestLayout(id, …)`. The body is built at layout every frame (`ProgressView`'s precedent). `StateBinder.bind(style, …)` runs first,
  so a style's `@Environment` and `@State` are bound (`BY-K`); a third-party `struct S: ButtonStyle { @Environment(\.x) var x }` needs the protocols to be
  `@MainActor` (they are, as SwiftUI's), which also required `BuiltInButtonStyle` to be.
- **`isPressed` needed a new channel.** Hover is resolved after prepaint, but a style's body is built at layout. `Window` stamps `Frame.pointerOwner`
  from its captured hitboxes at the current pointer (`topmostHitboxOwner`, widened from `private`) and `paint` calls `requestAnotherFrame()` when its own
  resolved `isActive && isHovered` disagrees with what the body was built with (`BY-D`). `everyFrameChannelIsClassified` owed a row (`pointerOwner: .keyed`:
  a press already refuses a retained replay under it, `SB-X`). The first pressed frame is the corrected one — `window.needsRedraw` is false after it
  (`isPressedIsTrueWhilePressedAndOverTheButton`).
- **The label.** `StyleLabel`, a public MetalUI-only `StyledElement` holding the label erased inside one `Box`; the three configurations' `Label` are
  typealiases of it (`BY-E`). Element modifiers (`.padding`, `.background`, `.onClick`) apply to it.
- **The foreground of a prominent button.** The label's `foregroundStyle` is written in a `withEnvironment` around the box in all three phases (what
  `EnvironmentScope` does), stored in the layout, so no label type changed and no id moved.
- **The switch knob** is painted in `paint` from the row's bounds (the track is a fixed-size `Box` and the row centres it), not a nested `Box`: the checkbox's
  ids (`[…, 0]` indicator, `[…, 1]` label, and the `$anim-color` slot) stay identical in every style, at the price that the knob snaps (divergence 885).

## Tests (new files; existing tests adapted)

`ButtonStyleTests.swift` (12), `ToggleStyleTests.swift` (7), `StyleCompileGuards.swift` (1, a plain-import `typecheckFile`: a third-party module declares a
`ButtonStyle`, a `PrimitiveButtonStyle` and a `ToggleStyle` and uses every built-in spelling; negative arms: a `Body` that is no `ElementGroup`, a
configuration forged outside the module, `.buttonStyle(42)`). Adapted: `ButtonCompileGuards` (the `.link` negative arm became `.bogus`),
`ControlsCompileGuards` (`aMenuPickerStyleCompiles`' separating arm was `.pickerStyle(.inline)`), `ProposalControlsCompileGuards` (`PE-R`'s
separating arm was `.padding(8).buttonStyle(.plain)`, which compiles now; it is `.keyboardShortcut` after a wrapper), `GlassTests`/`GlassCompileGuards`/
`ButtonSemanticsTests` (they named the old struct: `ButtonLook`, `[any PrimitiveButtonStyle]`), `RetainedSubtreeInternalTests` (the `pointerOwner` row).
Written before the implementation and run red: the new test files did not compile against master (`ButtonStyle` was a struct: "inheritance from non-protocol
type"), which is red by compile failure, not by assertion; the assertion-level red is the mutation table below.

## Mutations (each applied alone to the spelling named, built, the style tests run, reverted)

Run with `swift build --build-system native --build-tests`, then the 19 style tests plus the three adapted guards named in the table's filter; the
tests listed are the ones that turned red (a mutation that reddened nothing is called out).

| # | Mutation | Reddened |
|---|---|---|
| `BY-M1` | `Button.requestLayout`: the custom `ButtonStyle` arm draws the bordered chrome | `aCustomButtonStyleReplacesTheChrome`, `isPressedIsTrueWhilePressedAndOverTheButton`, `theConfigurationCarriesTheRoleAndIsNotPressedAtRest`, `aButtonStyleIsInheritedThroughTheEnvironmentNearestWriterWinning`, `aStyleWrittenOnAnOuterGroupReachesAWrappedButton`, `aStyleStructsEnvironmentPropertiesAreBound` |
| `BY-M2` | `requestCustomLayout`: `isPressed = activeElement == id` (the pointer-over half dropped) | `isPressedIsTrueWhilePressedAndOverTheButton` (the dragged-out arm) |
| `BY-M3` | `layOutCustom`: the outer box registers the caller's handlers only, not `composedHandlers` | `aCustomStyledButtonStaysClickableFocusableAndAccessible`, `aPrimitiveStyledButtonIsFocusableAndActivatesFromTheKeyboard`, `isPressedIsTrueWhilePressedAndOverTheButton` |
| `BY-M4` | the `PrimitiveButtonStyle` overload of `ElementGroup.buttonStyle` writes only when nothing above wrote (outermost wins) | `aStyleWrittenOnAnOuterGroupReachesAWrappedButton` (the nested-writers arm). **First spelling failed to build** (`$0.buttonStyle.storage` on a value that is already the style); re-run as `$0.storage` |
| `BY-M5` | `PrimitiveButtonStyleConfiguration.trigger()` is a no-op | `aPrimitiveStyleRunsTheActionOnlyThroughTrigger` |
| `BY-M6` | `ResolvedToggleStyle.automatic` is the switch | `checkboxIsTheDefaultToggleStyle`, `aToggleStyleIsInheritedNearestWriterWinning` |
| `BY-M7` | `Toggle.requestCustomLayout`: the outer box registers the caller's handlers only | `aCustomToggleStyleDrawsFromIsOnAndKeepsTheTogglesBehaviour` |
| `BY-M8` | `requestCustomLayout`: no `StateBinder.bind` of the style struct | `aStyleStructsEnvironmentPropertiesAreBound` |
| `BY-M9` | `ButtonLook.labelColor`: `.borderedProminent` forces no colour | `borderedProminentIsAnAccentFillWithAWhiteLabel` |
| `BY-M10` | `PickerStyle.inline` is the segmented kind | `anInlinePickerDrawsAsTheRadioGroup` |
| `BY-M11` | `paintKnob`: the knob's x is swapped between on and off | `switchIsACapsuleTrackWithAKnobAtTheOnEnd` |
| `BY-M12` | `requestCustomLayout` for a `PrimitiveButtonStyle` passes `primitive: false` (the button also registers its click) | `aPrimitiveStyleRunsTheActionOnlyThroughTrigger` (the never-triggers arm) |
| `BY-M13` | `paint`: the correction `requestAnotherFrame()` removed | **nothing at first** (`BY-D`'s correction was untested: every scenario stamped the right owner); `aStalePointerOwnerAsksForOneCorrectionFrame` was added, a frame with the button active, the pointer over it and `pointerOwner = nil`, and reddens |

`BY-M1` and `BY-M3` also redden `isPressedIsTrueWhilePressedAndOverTheButton` because a button without the custom path or its handlers has nothing to
press. The `typecheckFile` guard `aThirdPartyModuleCanDeclareButtonAndToggleStyles` was mutated once: `ButtonStyleConfiguration.init` made `public`
(`BY-M14`) — the "forged configuration" arm then compiled, the arms no longer disagreed and the guard went red at its `#require` (`positive.succeeded !=
forged.succeeded`). Its positive arm is the third-party declarations themselves (a `ButtonStyle`, a `PrimitiveButtonStyle`, a `ToggleStyle`).

A scratchpad accident to report: the session scratchpad turned out to be shared with sibling agents, and a first `mutate.py` of this lane was
overwritten by another lane's (`matched-geometry`) before it ran, so one run of that lane's mutation list executed against its worktree concurrently with
its own. Its worktree was clean afterwards; its mutation results from about 15:59–16:05 may be contaminated. This lane's scripts live in a private subdirectory.

## Counts

2026-10-31, `feat/button-styles` at the commit after `55ee5ccf` (docs only after it), `swift package clean`, then `swift build --build-system native --build-tests`
and `swift test --build-system native --no-parallel --skip AppKitPresentationTests` (screen possibly locked): **4656 tests in 12 suites passed** (master's
4635 of record 173 + 12 `ButtonStyleTests` + 1 stale-owner test + 7 `ToggleStyleTests` + 1 `StyleCompileGuards`), 0 failures; `FR-J no-argument frame:
succeeded=true` printed, so the guards ran; the new guard prints `STYLE GUARD G-BY1 positive: succeeded=true` and `negatives: badBody=false forged=false
notAStyle=false`. The guard tally (285 at record 173) is one more by construction and was not re-counted by grep. The CLAUDE.md counts line is not edited. The
two failures the first full run found (before the clean run) were mine to fix: `aMenuPickerStyleCompiles` used `.pickerStyle(.inline)` as its not-offered
arm, and `everyFrameChannelIsClassified` owed a row for `Frame.pointerOwner`. `Backends/SDL`: `swift build $(python3 scripts/fetch-accesskit.py --print-flags)`
completes with no errors. `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing (a `styles` family, class D, and rules for
`ButtonStyle.swift`, `ToggleStyle.swift`, `Toggle.toggleStyle` and `PickerStyle.inline`).

## Not done / carried

See `BY-J` and the "Carried" section of the decisions document: a custom `PickerStyle` protocol, `ProgressViewStyle`/`TextFieldStyle` protocols, a
pressed look for `.button` toggles, `.link`'s hover cursor, a sliding switch knob, `isMixed` ever true. The looks are all unmeasured (human check `BY`).
