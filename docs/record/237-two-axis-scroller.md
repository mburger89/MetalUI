# Record 237: the two-axis scroller (Alloy gap G5 PRs 2-3, no divergence, `XS-A`..`XS-D`, `XS-H`..`XS-M`, `XS-P`..`XS-U`)

Branch `feat/two-axis-scroll` on `feat/scroll-axis-routing` (record 236). Decisions `docs/superpowers/2026-11-07-two-axis-scroll-decisions.md` (next `XS-V`). Class `A`; **no divergence added**; the "two-axis scrolling" entry left the "Not offered" row of `docs/divergences.md` (live 213, next label 232, unchanged).

## 1. What was built

`ScrollView(_ axes: Axis.Set)` / `ProposalScrollView(_ axes:)` (`@_disfavoredOverload`), stored `axes` with a computed `axis`; the kernel `both`/`neither` viewport; `ScrollState.cross` and one `ScrollChrome.resolveSlot` core for both slots; a thumb per axis with an 8-point corner inset; `Hitbox` axes/takes/room for a two-axis region that swallows at its edge; `ScrollContext`/`ScrollerFrame` `cross` and `along(_:)` for lazy containers; `scrollTo`, `defaultScrollAnchor` and the glide per slot; `scrollPosition(id:)` on the primary axis; `PrepaintExtras.scroller` indices 10/11; a "both axes" pane in the lazy containers demo.

## 2. The re-measurement (small content)

Probe arms `L1e`-`L1g` (added to `docs/probes/swiftui-two-axis-scroll.swift`, one run): a 50x30 child in a two-axis scroller of 100x100 reads content (0, 0) in the scroll view's space and in the window, and the AppKit document view sits at the viewport's top-left corner; single-axis controls read (25, 0) and (0, 35) because the viewport is narrower than its frame. `SCG2`'s (25, 35) came from the layout harness; ruled (0, 0), `XS-P`.

## 3. Rulings against the plan and the probe

Whole-to-dominant routing (PR 1), a two-axis scroller swallows at its edge, `scrollTo` into a nested scroller moves the nearest only, `.top` centres x, the pin releases per axis, `scrollPosition(id:)` tracks y and ignores dx: all built as PR 1's record ordered. Assumptions with human checks: the lock through momentum (`XS-R`), one stamp for both thumbs (`XS-S`), and that `ScrollView([])` passes the wheel on (`XS-Q`).

## 4. Tests and pins

`TwoAxisViewportTests` (X1, X1b, signatures; `MetalUILayoutTests`), `TwoAxisScrollTests` (X2-X5, X8), `TwoAxisScrollGuards` (X7, plain import), `TwoAxisScrollWindowTests` (X6), `TwoAxisIntegrationTests` (Z1-Z7, Z9), `TwoAxisRetainedTests` (Z8). **No existing pin moved.** The mutation table and verification are in the summary below.

## 5. Verification

See the `CLAUDE.md` counts line. Mutations (applied in place after committing, restored with `git checkout`): MUTATIONS_PLACEHOLDER

Not pinned: the cross flag of `noteScrollAnchorAdjustment` (a `LazyHStack` of variable columns in a two-axis scroller).

Human checks: group `XS`, XS6-XS11.
