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

Native, unfiltered, `--no-parallel` after `swift package clean`: `Test run with 5660 tests in 26 suites passed` (also under `METALUI_VERIFY_RETAINED=1`), `FR-J no-argument frame: succeeded=true`; closeout scripts print nothing. Portable container (`git archive HEAD` over stdin to `docker run --rm -i metalui-portable bash -c ...`): `swift build --build-tests` complete (39.54 s); `MetalUITestingTests` 948 tests in 11 suites passed, then 9, 16, 73, 68, 53, 25, `MetalUILayoutTests` 290, 165, 24 and 45, all passed. The first native run failed `everyStateWriteSiteIsClassified` only (reclassified). Mutations (applied in place after committing, restored with `git checkout`): the both-axes arm proposing like a vertical viewport reddens X1 (and Z7, whose content width goes wrong); `neither` proposing `nil x nil` reddens X1b; the `both` signature tag equal to the vertical one reddens the signature test; the `Axis.Set` init storing both for a one-axis set reddens X2; the cross write-back dropped (`resolveSlot` on a copy) reddens X3, Z2, Z5, Z6; the translation without x reddens X4 and X6; no horizontal thumb and the corner inset 0 each redden X5; `crossMirrored` false reddens X6; the two-axis room taken from the primary slot reddens X8; `scrollAxes` ignored in the chain reddens X3, X4, X6, X8, Z6, Z7, Z9; `along(.vertical)` answering the cross slot reddens Z1; `along(.horizontal)` nil on the context reddens Z2 and on the frame Z2 and Z4; the context publishing x as the primary offset reddens Z3; the cross resolution of `scrollTo` dropped, and its landing dropped, each redden Z4; the cross `resolveSlot` dropped reddens Z5, Z2, X3, Z6; a shared anchor memory reddens Z6; `didScroll` for the cross slot reddens Z7; index 10 not zeroed reddens Z8 (after its first form, which used a context-menu card and a wheel off the scroller, reddened nothing: the wheel missed the viewport and a card with a menu refuses translation under any scroller, one-axis too; `XSCard` and the wheel's own frame fixed both); the lock dropped reddens Z9. **Removing `@_disfavoredOverload` breaks the BUILD** (`DemoContent.swift:845: ambiguous use of 'vertical'`), so X7 never gets to run: stop condition 3 would fire exactly as the plan said. **`sameScrollState` without `cross` reddens nothing**: the compared write still stores the value and only the version differs; not pinned.

Not pinned: the cross flag of `noteScrollAnchorAdjustment` (a `LazyHStack` of variable columns in a two-axis scroller).

Human checks: group `XS`, XS6-XS11.
