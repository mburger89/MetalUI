# 98 — Resign on press (`RF-`)

Branch `feat/resign-on-press` from `5f35df6`. **Not a plan task**: item C24 of
the gpui-gap list (user request 2026-10-02), requested by MetalCreator
(`metalui-gaps.md` CT-a). Spec
`docs/superpowers/specs/2026-10-12-resign-on-press-design.md`; rulings `RF-A`…`RF-I`
in `docs/superpowers/2026-10-12-resign-on-press-decisions.md` (next unused
`RF-J`); probe `docs/probes/swiftui-resign-on-press.swift` (arms `RP0`–`RP12`,
output in its header).

**Status: LANDED on the branch.** `.resignsFocusOnPress(_ isEnabled: Bool = true)`
is an opt-in container modifier: a primary press inside it resigns a focused
field and routes **no** key by hover. MetalUI-only by ruling (class `M`,
`RF-A`): SwiftUI has no such modifier (`RP1`–`RP4`: a press on plain content, a
`.focusable(false)` view and a `.focusEffectDisabled()` view leave a field
focused), and the tap-handler idiom has a trap (`RP8`). No divergence label is
used (`KF-G`'s default is unchanged). The rejected spelling
`hoverKeyRegion(routesKeys:)` is `RF-B`.

## 1 What changed

* `KeyboardAttachment` gains `resignsOnPress`; **all five factories** carry all four
  fields (`RF-C` 1). `Handlers` keeps nineteen members.
* `Frame.registerHandlers` registers its existing non-opaque region for
  `isKeyRegion || resignsOnPress || focusesOnPress` inside the same disabled,
  `allowsHitTesting` and `hidden()` gates and counts `resignRegionCount`
  (a resign-only region is not a key region: `keyRegionCount`, `hoveredKeyRegion()`,
  `keyChain`, the Keymap contexts and `onKeyPress` routing are untouched, `KF-U`).
* `Window.focusOnPress` widens only its region predicate and its count guard; the
  ladder is `KF-E` item 5 verbatim; the one ranking `topmostHitbox` is the only
  lookup (`RF-C` 4).
* Public: `StyledElement`, `ProposalElementGroup` and `KeyboardModifier` gain one
  overload each (inventory family `resigns-focus-on-press`, class `M`).
* Lane 2: `KeyFocusDemo`'s root (its own function, the Windows 1 MB rule) carries
  the modifier and the header line says "click the canvas or blank space to leave a
  field"; `docs/verification/human-checks.md` group **RF** (RF-1…RF-3, not run);
  `docs/api-overview.md` beside the `hoverKeyRegion` paragraph; `docs/testing.md`
  recipe note (no change to the compiled recipe).

## 2 Counts and gates (`b8437281`, `feat/resign-on-press` merged with master `ff8a1ea4`, native build system)

* **3533 tests in 3 suites passed** (master `ff8a1ea4`: 3513 + this branch's 20); 0 goldens (master `5f35df6`: 3415; the branch alone at
  `09bcb2b1`: 3435 = 3415 + 20: 16 in `ResignOnPressTests`, 2 typecheck guards in
  `ResignOnPressCompileGuards`, 1 in `MetalUITestingTests` and 1 in
  `MetalUICrossPlatformTests`); 223 typecheck guards (master's 221 + this branch's 2, taken as the sum; `FR-J no-argument frame: succeeded=true` present); 0 `error:`; the only `warning:` is
  SwiftPM's `--build-system native` deprecation notice. The five
  `AppKitPresentationTests` sheet issues of `CI-AF` appear only on a locked screen (this run, after `swift package clean`: 0 issues recorded, passed in 414 s).
  `swift build --build-tests` (default build system) 0 warnings.
* `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing; the
  census is re-recorded (one family, `resigns-focus-on-press`, three functions).
* Pixels: **0 differing pixels in all fourteen offscreen images**
  (`compare.sh <scratch> 5f35df6 HEAD` at `09bcb2b1`: every row `scene identical`; the
  controls read as recorded: light/dark 1048576, default/modal 1031003,
  default/animation 454895, distinct 544/216/529).
* The Linux image (`swift:6.4-noble`, root package): `swift build --build-tests`
  complete, `swift test --skip-build` passes 9 + 40 + 21 + 199 + 79 + 22 (the
  `MetalUICrossPlatformTests` suite 78 -> 79: `aResignRegionClearsFocusOnEveryPlatform`).
  `Backends/SDL` is untouched by this branch.
* **The merge** with master `ff8a1ea4` (C21, C22, C25, C26 landed first): auto-merged
  `Frame.swift`, `Window.swift` and the inventory files; the one conflict was
  `docs/verification/human-checks.md`, resolved by keeping both sides (group `RF` now
  follows `GC`). C25 (text selection) did not touch `focusOnPress`'s text-field early
  return, so the additive widening stands.

## 3 Probe

`docs/probes/swiftui-resign-on-press.swift`, arms `RP0`-`RP12` (output in its header,
taken three times byte-identical, on a locked screen; the controls `RP0` and `RP1`
reproduce the key-focus arms `RS0`/`RS1`, which is the check that the lock did not move
the instrument). Findings: a press on a plain colour (`RP1`), a `.focusable(false)` view
(`RP3`) and a `.focusEffectDisabled()` view (`RP4`) leave a field focused; only code in
a tap handler resigns (`RP2`); A to B is direct (`RP5`); a container tap does not fire for
a field's press (`RP7`) but a `simultaneousGesture` tap fires after focus moved
(`RP8`); `.disabled`, `.allowsHitTesting(false)` and `.hidden()` stop the tap
(`RP10`-`RP12`). `RP9` (a secondary press fires `onTapGesture`) is read as the
instrument's and no ruling rests on it. Ruling `RF-A`.

## 4 Mutation tables (each: committed first, restored from a copy, `git status --short` after)

Lane 1 (filtered over the resign tests, 20 to 51 tests per run; lane 2 re-took M6b, M7
unfiltered):

| Mutation (spelling) | Reddened | Reading |
|---|---|---|
| M2b `coversKeys` admits a resign region with `withPressRegions: false` | `aResignRegionOverAKeyRegionLeavesTheKeyRegionRouted` | pinned (test 2 alone cannot see it, `RF-H` 1) |
| M3b ladder: `region != nil` tested before the click-focusable | `aPressOnAClickFocusableInsideFocusesItNotNil` | test 4 is the ladder pin; test 3 stays green (`RF-H` 2) |
| M6c drop `keyboardHiddenDepth == 0` from the registration gate | none | **equivalent**: hidden raises both depths in one step (`RF-H` 4) |
| M7 (last occurrence, in `focusOnPress`) drop `box.layer == cover.layer` | `aDeferredPresentationPressDoesNotResignThroughARegionBelow`, `aPressOnAKeyRegionsOwnPopoverChangesNoFocus` | pinned |
| M8 (last occurrence) drop `cover.id.isOrDescends(from: box.id)` | `aPressOnAnOpaqueSiblingAboveTheRegionChangesNoFocus` | pinned (`RF-I` 1) |
| M6b drop `hitTestingDisabledDepth == 0` from the registration gate, **full unfiltered suite** | `disabledHiddenAndAllowsHitTestingWithdrawTheResignRegion` (test 6), `disabledHiddenAndAllowsHitTestingWithdrawThePressAndKeyRegions`, `everyHandlerRegisteringSiteHonoursAllowsHitTesting`, `everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` | pinned. An earlier **filtered** run read green; that was a filtered-run artefact, not a missing pin (corrected in `RF-I`) |
| R1 additive `enabled:` overload; R2 | R1 reddens the negative compile guard; R2 has no additive mutation (any change breaks the test target's compile), unmutated | `RF-I` 4 |

Not re-run: M3a (delete the text-field early return; test 3 is green under it, `RF-G` 2,
`RF-H` 2) and M11 (`Window.focus`'s no-change guard; `RF-H` 3, no mutation claimed).
A scripted M7/M8 that replaced the **first** occurrence of its line hit
`hoveredKeyRegion` rather than `focusOnPress` and reddened only
`aKeyRegionUnderAnOpaqueSiblingOrAPresentationIsNotHovered`; the table's rows are the
re-applied ones (`RF-I` 1). Hangs: none.

## 5 Hazards

* The filtered-run trap: a mutation run with `--filter` can read green where the full
  suite is red (M6b). Practice: mutations are taken unfiltered; the table above names
  the full-suite reds.
* A scripted `replace(old, new)` mutation replaces the first occurrence: when a line is
  duplicated between `hoveredKeyRegion` and `focusOnPress`, name the occurrence.
* `resignsFocusOnPress(false)` on a layer that is also a key region does not switch the
  key region's clear off (`RF-F`); a reader of the call site may expect it to.
* The spec's mutation for test 3 (delete the early return) does not redden; "no nil
  between" is pinned by end state only, `Window.focus` having no intra-event hook.

## 6 Not done

* A per-subtree opt-out and a window option (spec section 7): not built, no request,
  owner none. A real mouse (`RF-1`...`RF-3`, human). Windows (the portable test runs in
  `MetalUICrossPlatformTests`, which the Windows job runs on push). `RP9`'s secondary-press
  reading, owner `RF-3`.
* This change adds no divergence (`KF-G`'s default is unchanged); the reserved range
  285-294 stays unused.
