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

## 2 Counts and gates (`feat/resign-on-press` at `0cc71336`, native build system)

* **3435 tests in 3 suites** (3415 at `5f35df6` + 20), 0 goldens; every
  `FR-J no-argument frame: succeeded=` line present; 0 `error:`; the only
  `warning:` is SwiftPM's `--build-system native` deprecation notice;
  `swift build --build-tests` (default build system) 0 warnings.
* `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
* Pixels: **0 differing pixels in all fourteen offscreen images**
  (`compare.sh <scratch> 5f35df6 HEAD`: every row `scene identical`; the
  controls read as recorded: light/dark 1048576, default/modal 1031003,
  default/animation 454895, distinct 544/216/529).
* The Linux image (`swift:6.4-noble`, root package: `swift build --build-tests` complete (no error),
`swift test --skip-build` passes 9 + 40 + 21 + 199 + 79 + 22 (the last
`MetalUICrossPlatformTests` suite 78 -> 79: `aResignRegionClearsFocusOnEveryPlatform`).

## 6 Not done

* A per-subtree opt-out and a window option (spec section 7); M6b's cause; a real
  mouse (`RF-1`…`RF-3`); Windows (the portable test is in
  `MetalUICrossPlatformTests`, which the Windows job runs on push).
* `CLAUDE.md`, `AGENTS.md`, `README.md`, the record index and the divergence
  header are the Record phase's; this change adds no divergence.
