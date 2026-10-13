# Resign on press — design (C24)

**Status: IMPLEMENTED 2026-10-12** on `feat/resign-on-press` from `5f35df6` (designed the same day; record 98; the mutation table is record 98 section 4, which supersedes this spec's per-test mutation list where they differ).
Rulings: [`../2026-10-12-resign-on-press-decisions.md`](../2026-10-12-resign-on-press-decisions.md)
(`RF-A`…`RF-I`, next `RF-J`). Probe: `docs/probes/swiftui-resign-on-press.swift`.
Requested by MetalCreator (CT-a): a press on inert chrome (glass padding, header
gaps, an empty inspector) must end in-place editing without taking over key
routing. Today a press outside every key region resigns nothing (`KF-G`), and
`.hoverKeyRegion()` clears focus **and** routes keys by hover (`KF-U`).

## 1. API (class M, MetalUI-only; no divergence label used)

```swift
extension StyledElement { public func resignsFocusOnPress(_ isEnabled: Bool = true) -> Self }
extension ProposalElementGroup /* where hoverKeyRegion is offered */ {
    public func resignsFocusOnPress(_ isEnabled: Bool = true) -> KeyboardModifier<Self>
}
extension KeyboardModifier { public func resignsFocusOnPress(_ isEnabled: Bool = true) -> Self }
```

Exactly the three places `hoverKeyRegion` lives (`HoverKeyRegion.swift`,
`KeyboardModifier.swift` lines ~95 and ~218). Each owes a doc comment and an
inventory row (extend row 115/116 `hover-key-region`/`keyboard-modifier`'s
siblings with `resigns-focus-on-press`, class `M`, rulings `RF-A RF-B RF-C`);
re-record the census with `closeout-public-api.sh`.

## 2. Implementation (portable, every platform; no platform seam)

All in `Sources/MetalUI` (no AppKit, no SDL, no renderer, no shader): the
press path is the portable `Window.focusOnPress`. No `PlatformWindow`/`Platform`
requirement, so no migration note and no SDL change.

1. `KeyPress.swift`: `KeyboardAttachment.resignsOnPress` + the factory
   `resigning(_:over:)`; **all five factories carry all four fields** (`RF-C` 1).
2. `Frame.swift` (~1683): the region condition adds `keyboard.resignsOnPress`;
   a `resignRegionCount` beside `keyRegionCount`/`focusOnPressCount`.
3. `Window.swift`: `lastResignRegionCount` (set beside line ~1809).
4. `HoverKeyRegion.swift`: `coversKeys` (`withPressRegions: true` admits a
   resign region), `focusOnPress` guard and `region` predicate (`RF-C` 3). The
   hover lookup (`hoveredKeyRegion`, `keyChain`) is **not** edited — that is
   the pin of test 2. (C25 `feat/text-selection` may touch the same stage for
   fields; this change edits three lines of `focusOnPress` additively and
   leaves its text-field early return alone.)
5. `Handlers` unchanged (nineteen members, `HandlerShape`/`HandlerFingerprint`
   untouched). No `StateTable` slot, no `noteNamed`, no identity level.

No `swift package clean` hazard: only an internal class gains a stored property.

## 3. Lanes (two, disjoint files)

- **Lane 1 (source + tests):** items 1–4 above; `Tests/MetalUITests/ResignOnPressTests.swift`,
  `Tests/MetalUITests/ResignOnPressCompileGuards.swift`,
  `Tests/MetalUITestingTests/ResignOnPressHarnessTests.swift`,
  `Tests/MetalUICrossPlatformTests/ResignOnPressPortableTests.swift`; the inventory
  row and census (`docs/probes/closeout-inventory-map.tsv`, `closeout-public-api.tsv`).
- **Lane 2 (demo + docs):** `Sources/MetalUIDemoContent/KeyFocusDemo.swift`;
  `docs/verification/human-checks.md` (group RF, §5); `docs/api-overview.md`
  (beside the `hoverKeyRegion` paragraph, line ~385), `docs/testing.md`'s
  recipe note (mention, no code change to the compiled recipe). Lane 2 starts
  after lane 1's modifier compiles (it uses it).

CLAUDE.md/AGENTS.md/README/record index/record 98 belong to the Record phase.

## 4. Tests (name, red-before, mutation that must redden)

"Red before" = fails to compile (modifier absent) in lane 1's first commit
unless noted; the mutations are applied one at a time to the spelling named,
full unfiltered suite, `git status --short` after each.

All in `ResignOnPressTests.swift` over a `Window` (`simulateInput`) unless noted:

1. `aPressOnInertChromeResignsAFocusedField` — field focused, press on a plain
   box in the region: `focusedElement == nil`. *Mutation:* drop
   `|| resignsOnPress` from `focusOnPress`'s `region` predicate.
2. `aResignRegionRoutesNoKeysByHover` — nothing focused, pointer over the
   region: an `onKeyPress` and a `keyContext` on it hear/contribute nothing
   (`keyChain` empty); the same tree with `hoverKeyRegion()` hears them (the
   separating arm). *Mutation:* count a resign region in `keyRegionCount` /
   admit it in `coversKeys(withPressRegions: false)`.
3. `aPressFromOneFieldToAnotherMovesFocusDirectly` — a `@FocusState<Field?>`
   observer logs `[a, b]`, never `nil` between. *Mutations (RF-G 2):* delete the
   text-field early return in `focusOnPress`; if green, swap ladder steps 2 and 3.
4. `aPressOnAClickFocusableInsideFocusesItNotNil` — `.focusable(interactions:
   .edit)` inside: focus moves to it (one change). *Mutation:* swap the ladder
   (`else if region != nil` tested before `focusable`).
5. `aSecondaryAndOtherPressResignNothing` — right and other press: focus held
   (`MN-B`). *Mutation:* route secondary events into `focusOnPress`.
6. `disabledHiddenAndAllowsHitTestingWithdrawTheResignRegion` — three arms.
   *Mutations:* drop `enabled`, `hitTestingDisabledDepth == 0`,
   `keyboardHiddenDepth == 0` from the registration condition (one each).
7. `aDeferredPresentationPressDoesNotResignThroughARegionBelow` (popover over a
   region). *Mutation:* drop `box.layer == cover.layer`.
8. `aPressOnAnOpaqueSiblingAboveTheRegionChangesNoFocus`. *Mutation:* drop
   `cover.id.isOrDescends(from: box.id)` (a second lookup in effect).
9. `aWindowWithNoRegionDoesNoPressLookup` — `keyRegionLookups == 0` after
   presses with none; one lookup per press with one. *Mutation:* remove the
   count guard.
10. `aResignRegionIsNonOpaqueAndABeneathTapStillRuns` — click, hover and tap
    beneath work; a `Button` inside fires **and** resigns (`RF-E`). *Mutation:*
    register the region `opaque: true`.
11. `aResignIsOneFocusStateWriteAndNothingWhenNothingIsFocused` — one `nil`
    write when focused, zero when not. *Mutation:* call `focus(nil)` before
    the focused-element check is honoured (unconditional `focusState` write).
12. `everyKeyboardModifierOrderKeepsTheResignFlag` — all orderings of
    `resignsFocusOnPress`, `onKeyPress`, `focusable(interactions:)`,
    `hoverKeyRegion` on both vocabularies keep every field. *Mutation:* make
    `adding` (then `interactions`, then `keyRegion`) omit `resignsOnPress`.
13. `aKeyRegionWithResignFalseStillClears` (`RF-F`). *Mutation:* make
    `isKeyRegion` regions require the resign flag.
14. `togglingIsEnabledKeepsTheWrappedState` — `@State` under the layer survives
    `true→false` (`MC-A`). *Mutation:* wrap in a conditional layer.
15. `aResignOnTheRootStillLeavesAKeymapGlobalShortcutWorking` — a plain keymap
    binding fires after a resign (no key routing change).

`ResignOnPressCompileGuards.swift` (typecheck guards, each mutated red once by
deleting the overload): `resignsFocusOnPressCompilesOnAnElementAndOnProposalContent`,
`resignsFocusOnPressOnProposalContentReturnsTheKeyboardLayer`.

`ResignOnPressHarnessTests.swift` (`MetalUITesting`, `HT-`):
`aClickOnInertChromeEndsInPlaceEditingAndTheCommitSeesTheText` — the
MetalCreator shape: modifier on the app root, a field, an inert canvas;
`typeText`, `click` the chrome, `focusedElement == nil`, a later `typeText`
changes nothing. *Mutation:* remove the modifier from the root (red).
`ResignOnPressPortableTests.swift` (cross-platform, runs on Linux/Windows CI):
`aResignRegionClearsFocusOnEveryPlatform`. *Mutation:* as test 1.

Count target: +15 +1 +1 tests, +2 guards (record the measured sums at merge).
Pixels 0 px (`compare.sh <scratch> 5f35df6 HEAD`); the demo is env-gated and
outside the fourteen images.

## 5. Demo and human checks (lane 2)

Demo: `KeyFocusDemo` (`METALUI_KEY_FOCUS_DEMO`'s section — keep it in its own
function, 1 MB stack) puts `.resignsFocusOnPress()` on the root column and the
header line gains "click blank space to leave a field". Expectation: a press on
the padding or gap ends editing in the Name field (caret gone, status line
shows no focus); Tab over the canvas still opens the palette only while
hovering it with nothing focused (the key region is unchanged).

Human checks, group **RF** (not run — an agent cannot): RF-1 with a real mouse,
click the Name field then the blank padding: focus leaves, typing goes
nowhere; RF-2 click Name then the Depth field: one move, no flicker of the
caret to nothing; RF-3 right-click the padding with a field focused: the
context menu (if any) opens and the field stays focused.

## 6. SwiftUI / gpui claims and evidence

Every SwiftUI-facing claim is `RP0`–`RP12` (header of the probe; controls
`RP0`/`RP1`, separating arms `RP2`, `RP3`, `RP4`, `RP7`/`RP8`,
`RP10`–`RP12`). The run was taken with the screen **locked**; `RP0`/`RP1`
reproduce `RS0`/`RS1` of the unlocked 2026-10-08 recording, and RF-1 is the
human re-take. gpui has no equivalent (`RF-A`).

## 7. Not in scope (owners)

- A per-subtree opt-out (`resignsFocusOnPress(false)` nested to exempt chrome
  inside an enabled region): not built — no request; the workaround is to move
  the modifier. Owner: none.
- A window-wide option (`Window.resignsFocusOnAnyPress`): not built — the root
  modifier is the same thing with a visible scope. Owner: none.
- Making `KF-G`'s default resign: refused (SwiftUI keeps focus, `RS1`–`RS5`, `RP1`).
- `RP9`'s secondary-press reading: instrument question, not ruled. Owner: RF-3
  (human).
