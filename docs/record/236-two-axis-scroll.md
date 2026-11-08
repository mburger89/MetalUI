# Record 236: wheel routing per axis (Alloy gap G5, PR 0 and PR 1)

Branch `feat/scroll-axis-routing` (master `c6779ba4`, merged with `dc20b918`). Rulings `XS-E`..`XS-G`, `XS-O` in `docs/superpowers/2026-11-07-two-axis-scroll-decisions.md` (new prefix; next `XS-P`). Class `A`; no divergence added. **Scope: the probe and the routing fix on one-axis scrollers. The two-axis scroller itself (PR 2: `XS-A`..`XS-D`) and the integration (PR 3: `XS-H`..`XS-M`) are not built.**

## 1. The bug

`Window.dispatchScrollChain` stopped at the first scroll region on the cover's chain and read only that region's axis, so a horizontal scroller inside a vertical one swallowed a vertical wheel (record 235 pinned it as the carried limitation of `BM-H`), and a `TextEditor` inside a horizontal scroller swallowed `dx`.

## 2. The probe (PR 0)

`docs/probes/swiftui-two-axis-scroll.swift`, run twice (byte-identical), arms D0, A, L, N, T, S, P, R; the whole stdout is in its header. Delivery is `NSWindow.sendEvent` of `CGEvent` scroll events, the window at the screen origin (D0 shows `sendEvent` and `hitTest` agree). What it found, against the plan's expectations:

- **Dominant axis, whole, even phaseless** (A3, A3b, A3c, N3): the plan expected a per-axis split for N3 (inner x, outer y). It is not: SwiftUI's scrollers are `NSScrollView`s with predominant-axis scrolling.
- **The lock applies to one-axis scrollers** (A8, A8b, A8c) and holds through a gesture whose later events point the other way (A4c, A5).
- **Capability, not type** (N1-N7): a scroller whose content fits passes the wheel up, same-axis or not (N6, N6b).
- **Edge chaining** (N8, N8b, N8c, N8d, N8h): a one-axis scroller at its end passes the wheel up, mid-gesture too (stop condition 2 asked whether building this moves more than the two named pins: it did not).
- **A two-axis inner does not chain** (N9c-N9f), carried to PR 2.
- `scrollTo` into a nested inner moves only the inner (T7); the `defaultScrollAnchor` pin releases per axis (S5); `scrollPosition(id:)` ignores a dx-only wheel (P1); a right-to-left two-axis scroller opens at the right edge (R1); the `.top` anchor centres x (T3).
- Not readable here: momentum (M0, A6, N10), the thumbs (A9, legacy scrollers), small-content centring in a two-axis viewport (L1b disagrees with SCG2: (0,0) against (25,35); PR 2 re-measures).

## 3. The fix (PR 1)

`Hitbox.scrollAxes`/`scrollTakes`/`scrollRoom` (set from the resolved offset in prepaint; in the fingerprint), `ScrollLatch.lock` and `dominantAxis(of:)`, and a rewritten `dispatchScrollChain(_:cover:candidates:lock:)`: handlers raw, the editor vertical-only, the nearest scroller that declares the axis, has content past its viewport and room in the direction, else on up the chain, else the innermost without room. The public `registerScrollRegion` declares both directions open (a custom scroller passes the other axis on: `docs/migration.md`).

## 4. Tests and pins

`Tests/MetalUITests/ScrollAxisRoutingTests.swift`, R1-R13, each with its mutation (the table in the summary of PR 1; all reddened the named tests and were restored with `git checkout`). The BM2 pin `aHorizontalCodeScrollerSwallowsTheVerticalWheelSoTheDefaultHasNone` is renamed `aHorizontalCodeScrollerPassesTheVerticalWheelToTheTranscript` and reads `moved == -30` in both arms (moved by the cause above); `MarkdownTheme`'s doc comments no longer say the scroller takes the wheel. Defaults unchanged.

## 5. What PR 2 and PR 3 must do differently from the plan

Whole-to-dominant (no split, no `remaining` set); a two-axis scroller swallows at its edge while a one-axis one chains; `scrollTo` into a nested inner moves the nearest only; small-content centring to be re-measured; the lock through momentum is an assumption.

## 6. Verification

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5640 tests in 26 suites passed` (0 failures; the same under `METALUI_VERIFY_RETAINED=1`), `FR-J no-argument frame: succeeded=true`. Portable container (`git archive HEAD` over stdin to `docker run --rm -i metalui-portable`): `swift build --build-tests` complete; `MetalUITestingTests` 946 tests in 11 suites, then 286, 165 and 24, all passed (the moved BM2 pin among them). Closeout scripts print nothing. A first native run printed 17 issues in the bracket-node-drag and `aClipInsideNestedFlatteningEffects` tests and the next run of the same tree passed: unexplained, recorded as a flake.

Mutations (`ScrollAxisRoutingTests`, applied to `Window.swift`/`ScrollLatch.swift`, restored with `git checkout`): a scroller claiming whatever its axis reddens R1, R2, R4, R7, R8, R11, R12 and R5; `dominantAxis` zero->vertical reddens R10; always vertical reddens R2, R3, R4, R7, R9; nil for non-zero reddens R1, R2, R4, R5, R7, R8, R9, R11, R12; dropping the lock reddens R5; zeroing dx before handlers reddens R6; ignoring `scrollMirrored` reddens R7; ignoring a handler's claim reddens R8; the editor claiming every axis reddens R9; ignoring the room reddens R12; dropping the fallback reddens R13. **Swapping `scrollTakes` for `scrollAxes` alone leaves everything green** (a fitting scroller has no room either); with the room ignored as well, R11 and R12 redden.

Human checks: group `XS`. Counts: see the `CLAUDE.md` line.
