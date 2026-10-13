# Resign on press — decisions

Rulings for item C24 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**), requested by MetalCreator (gap CT-a in its
`docs/metalui-gaps.md`, checked against `feat/key-focus`). Prefix `RF-`.
Spec: [`specs/2026-10-12-resign-on-press-design.md`](specs/2026-10-12-resign-on-press-design.md).
Probe: `docs/probes/swiftui-resign-on-press.swift` (arms `RP0`–`RP12`, output in
its header). Record: `../record/98-resign-on-press.md`. Branch
`feat/resign-on-press` from `5f35df6`.

**Next unused id: `RF-J`.**

## Carried

`KF-G` (a press elsewhere resigns nothing; SwiftUI's answer, RS1–RS5) **stands
as the default**; `KF-E` item 5 (a press in a key region clears focus, text
fields and click-focusable elements exempt, one change and no intermediate
`nil`); `KF-F` (the non-claiming `focusOnPress` stage); `KF-U` (key routing by
hover feeds the Keymap and `onKeyPress` only); `MN-B` (a secondary or other
press never focuses); `IX-Q` (a `Deferred` presentation's press is its own
layer); `KF-I` (`Handlers` keeps nineteen members).

## The final spelling (what an app writes)

```swift
// MetalUI-only (class M). Opt-in; resigns focus on a primary press inside the
// element, routes no key by hover.
VStack { ... }.resignsFocusOnPress()          // proposal content: the KeyboardModifier layer
Box { ... }.resignsFocusOnPress()             // StyledElement: returns Self
.resignsFocusOnPress(false)                   // off (the default)
```

## RF-A — SwiftUI has no such modifier; MetalUI-only by ruling, no divergence

**Ruling.** Probe `RP0`–`RP12` (macOS 27.0.1): a press on a plain colour
(`RP1`), a `.focusable(false)` view (`RP3`) and a `.focusEffectDisabled()` view
(`RP4`) leave a focused `TextField` focused; the only SwiftUI way to resign on
a press is code in a tap handler (`RP2`), and the idiom has a trap: a
`simultaneousGesture` tap on a container fires **after** a press on a field
moved focus there (`RP8`: `focus=b,tap`), so `focus = nil` in it clears the
field just focused. A press from field A on field B moves focus directly with
no `nil` between (`RP5`). gpui has no equivalent either (its `window.blur()`
is a call, and a click on non-focusable content blurs nothing by itself). So
the modifier is MetalUI-only (inventory class `M`) and **`KF-G` stays the
default: no divergence is added** (the default behaviour is unchanged, the new
API is an addition). `RP9` (a synthesized secondary press fires `onTapGesture`)
is read as the instrument's and no ruling rests on it.

**Cost if wrong.** If SwiftUI later ships a resign modifier, ours becomes a
differently-spelled duplicate; the probe is the re-check.

## RF-B — Spelling: `resignsFocusOnPress(_ isEnabled: Bool = true)`, not `hoverKeyRegion(routesKeys:)`

**Ruling.** A new modifier on `StyledElement` (returns `Self`) and on proposal
content (merges into the one `KeyboardModifier` layer, `KF-H`: no new layer,
no identity level), the shape of `hoverKeyRegion(_:)`. **Rejected:
`hoverKeyRegion(routesKeys:)`**: it changes a shipped public signature (every
caller and the inventory row), makes a name that says "hover key" resign a
press that has nothing to do with keys, and `hoverKeyRegion(false)` already
means "off" — a second boolean would have three states. A modifier whose name
is the behaviour reads at the call site in MetalCreator's root.

**Cost if wrong.** A rename is source-breaking only for an app that adopted it.

## RF-C — It rides `focusOnPress`; one more flag on `KeyboardAttachment`, no `Handlers` member

**Ruling.**

1. `KeyboardAttachment` gains `resignsOnPress: Bool` (default `false`);
   **every static factory (`make`, `adding`, `interactions`, `keyRegion`, the new
   `resigning`) carries every field** — a factory that drops it is a silent
   un-resign (test `everyKeyboardModifierOrderKeepsTheResignFlag`).
   `Handlers` keeps **nineteen** members (`KF-I`).
2. `Frame.registerHandlers` registers its existing one non-opaque region for
   `keyboard.isKeyRegion || keyboard.resignsOnPress || focusesOnPress`, inside
   the same disabled, `allowsHitTesting` and `hidden()` gates, and counts a
   **third** counter `resignRegionCount` (a resign-only region is **not** a key
   region: `keyRegionCount` and so `hoveredKeyRegion()`, `keyChain`, the
   Keymap contexts and `onKeyPress` routing are untouched, `KF-U`).
3. `focusOnPress` (`HoverKeyRegion.swift`) widens only its *region* predicate:
   `region` is the innermost box with `isKeyRegion || resignsOnPress`; the
   rest of its ladder is `KF-E` item 5 verbatim (text field → nothing here;
   click-focusable `F` inside the region or no region → focus `F`; else a
   region → `focus(nil)`; else nothing). It runs only when
   `lastKeyRegionCount + lastResignRegionCount + lastFocusOnPressCount > 0`
   (a window with none does no lookup, `keyRegionLookups` stays 0).
   `coversKeys(_, withPressRegions: true)` admits a resign region as a cover;
   `withPressRegions: false` (the hover lookup) does not.
4. **The one ranking, no second lookup**: `topmostHitbox(in:at:where:)`,
   membership by `box.layer == cover.layer`, `contains`, and the cover being or
   descending from the region.

**Cost if wrong.** A second `Handlers` member would break `HandlerShape` /
`HandlerFingerprint`; item 1 avoids it. If the cover predicate admitted the
region in the hover lookup, hovering a resign-only region would route keys (the
exact thing asked not to happen) — test 2 pins it.

## RF-D — The gates

**Ruling.** Same as a key region, pinned per gate: `.disabled(true)`,
`.hidden()` and `.allowsHitTesting(false)` on the element or an ancestor
withdraw it; a **`Deferred` presentation's press** is on its own layer and
does not reach a region below (`IX-Q`); an **opaque sibling drawn above** (not
inside the region) covers it and changes no focus; **a secondary or other
press never resigns** (`MN-B`: they are not `.mouseDown`, `focusOnPress` never
sees them); a press the modal/menu/popover/alert stages claim never reaches
the stage. The region is non-opaque: it blocks no click, hover, wheel, drop or
gesture, and a tap on the same element still runs (the press goes on).

**Cost if wrong.** A gate missed would resign on a press the user aimed at a
disabled or hidden control; the per-gate arms of test 6 name each.

## RF-E — Exemptions, and what a press on a control inside does

**Ruling.** A press on a **text field** or **click-focusable** element
(`.focusable(interactions: .edit)`) inside the region focuses it directly: A→B
is one `@FocusState` change, never `nil` between (`RP5`; `KF-E` item 5). A press
on a `Button`, a tap target or a plain element inside the region **does resign**
— the opt-in's whole point (MetalCreator puts it on the app root; SwiftUI's
`RS3` button-keeps-focus is the default this modifier is asked to override). The
press still goes on to the text stage, arena and click dispatch, so the
`Button` still fires.

**Cost if wrong.** An app wanting a button not to resign nests nothing: it
moves the modifier off the root onto the chrome. A per-subtree opt-out is
not built (spec §7).

## RF-F — Composition with `hoverKeyRegion`, `focusable`, `onKeyPress`

**Ruling.** A layer that is both a key region and a resign region is a key
region (`resignsFocusOnPress(false)` does **not** switch a key region's clear
off: it only withholds the flag; `KF-E` item 5 is the key region's own).
Modifiers on one proposal chain merge into one `KeyboardModifier` layer in any
order (`KF-H`); toggling `isEnabled` changes a value, never a layer count, so
the wrapped element's `@State` is kept (`MC-A`). With the region on the app
root and nothing focused after a resign, **no key is routed** (the Keymap's
global contexts and `onKey` see what they always saw; `onKeyPress` needs focus
or a key region).

**Cost if wrong.** If apps want "resign off" to override a key region, the
flag becomes a tri-state; nobody has asked.

## RF-G — Critic review: probe re-taken, one mutation re-aimed, rejections

**Ruling.** (1) The probe's `RP0`, `RP1`, `RP5`, `RP8` were re-run byte for
byte by the critic (screen still locked; same four lines as the header).
(2) Test 3's stated mutation (delete the text-field early return) may not
redden: if a text field is itself `focusesOnPress`, the ladder still focuses it
and A to B stays direct. Test 3 therefore carries two mutations, both run: the
early-return deletion, and, if that stays green, "ladder step 3 before step 2"
(`else if region` tested before `focusable`); record which reddened and on
which spelling, and record a mutation that reddens nothing as such.
(3) Rejected: a per-subtree opt-out and a window option (spec section 7),
`hoverKeyRegion(routesKeys:)` (RF-B). (4) A resign-only region never joins
`hoveredKeyRegion` (that lookup is untouched); the guard is test 2.

**Cost if wrong.** A green mutant hides an untested exemption; the second
mutation bounds it.

## RF-H — Lane 1 review: accepted equivalences and the overlay pin

**Ruling.** (1) Mutation M2b (admit a resign region in `coversKeys(withPressRegions:
false)`) is **not** equivalent: with a non-descendant resign region over a key
region the cover becomes the resign region and `hoveredKeyRegion()` returns `nil`.
Test 2 (lone region) cannot see it; test 2b
`aResignRegionOverAKeyRegionLeavesTheKeyRegionRouted` pins it (re-run on the committed test: M2b reddened exactly `aResignRegionOverAKeyRegionLeavesTheKeyRegionRouted`, 1 issue, unmutated 3435 pass; assert on
`hoveredKeyRegion()`, since a key does not reach `onKeyPress` through a `ZStack`
overlay even unmutated). (2) Test 3 is green under both M3a (early-return
deletion) and M3b (ladder reorder); "no nil between" is pinned only by end state
(`Window.focus` exposes no intra-event hook, `KX`) and **test 4 is the ladder
pin** (reddens under M3b). No stronger claim is made. (3) Test 11 does not pin
`Window.focus`'s no-change guard: a click redraws in both arms, so a redundant
`setNeedsRedraw` is invisible; only an existing test sees the guard's removal.
No mutation is claimed for it. (4) M6c (drop `keyboardHiddenDepth == 0`) is
**equivalent**: `Frame.disablingHitTestingIfHidden` raises `keyboardHiddenDepth`
and `hitTestingDisabledDepth` in the same step, so `hitTestingDisabledDepth == 0`
already excludes every hidden case (the existing hover gate has the same shape).

**Cost if wrong.** A future change that separates the two depths makes M6c
non-equivalent; the hidden-gate test would then redden.

## RF-I — Lane 2 mutation re-take: two scripted mutations hit the wrong site; M6b corrected

**Ruling.** The lane 2 re-take (record 98 section 4) found: (1) the first scripted
M7 and M8 replaced the **first** occurrence of their line, which is in
`hoveredKeyRegion`, not `focusOnPress`; they reddened only the existing
`aKeyRegionUnderAnOpaqueSiblingOrAPresentationIsNotHovered`. Re-applied to the
last occurrence (`focusOnPress`), M7 reddens
`aDeferredPresentationPressDoesNotResignThroughARegionBelow` and M8
`aPressOnAnOpaqueSiblingAboveTheRegionChangesNoFocus`, as the spec says.
(2) **M6b (drop `hitTestingDisabledDepth == 0` from the registration condition)
is pinned.** The lane's first reading was green, from a filtered run; the full
unfiltered suite reddens `disabledHiddenAndAllowsHitTestingWithdrawTheResignRegion`
(test 6, both its `Box` and its proposal-content `allowsHitTesting` arms),
`disabledHiddenAndAllowsHitTestingWithdrawThePressAndKeyRegions`,
`everyHandlerRegisteringSiteHonoursAllowsHitTesting` and
`everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload`. The record
phase corrected this: mutations are taken unfiltered. (3) The spec's M11 (unconditional `focus(nil)` write) was not run:
`Window.focus` guards a no-change, `RF-H` 3 already claims no mutation for it.
(4) The guards were mutated additively (R1: an extra `enabled:` overload makes
the negative compile; R2 has no additive mutation, any change to its return
type breaks the test target's compile, so it is unmutated).

**Cost if wrong.** None known: the clause is pinned by test 6 and three existing
guards.

## What does not move (RF-A…F's frame)

`KF-G`'s default, hit testing (the region is the existing non-opaque
registration), accessibility (nothing emitted), pixels (no draw; 0 px in the
fourteen images), animation, `Deferred`, text input, `IF-D`'s
`onModifierKeysChanged` (a modifier event is not a press) and the C16
cancellation paths (a resign neither begins nor cancels an arena).
