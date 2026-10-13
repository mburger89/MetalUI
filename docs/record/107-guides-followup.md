# 107 — Guides follow-up: C23, C24, C27 and C28 in the guides

Branch `docs/guides-followup` from `b17aee19`. **Not a plan task**: item 10c, a follow-up to 10b
(record §103). Spec `docs/superpowers/specs/2026-10-13-guides-followup-design.md`; rulings `DG-R`…`DG-V`
in `docs/superpowers/2026-10-13-guides-followup-decisions.md` (next unused `DG-W`). **No public API, no
`Sources/` or `Backends/SDL` change, no probe (no new SwiftUI claim), no divergence taken (the branch's
reserved labels 375–384 are unused).**

**Status: LANDED.** One lane, red first.

## §1 What landed

Four task-led sections, each with one compiled block mirrored byte for byte:

- `input.md` "How do I end editing when the user clicks empty chrome?" (`.resignsFocusOnPress()`,
  C24, §98; mirror input #6) and "How do I test a field with an input method?" (`setMarkedText`,
  `commitMarkedText()`, `commitMarkedText(_:)`, `cancelMarkedText()`, C28, §102; mirror input #7;
  divergences 325, 326; links `testing.md`, which is unedited).
- `drawing-and-gpu.md` "How do I put a label over a GPU surface?" (`@Environment(\.textMeasurer)`,
  `TextMeasurer`, C23, §99; mirror drawing #6; divergences 295, 296) and "How do I make a material
  respect Reduce Transparency?" (`accessibilityReduceTransparency`, `Material.tint(in:)`, C27, §101;
  mirror drawing #7; divergence 315).
- The guide-5 sentence "Reduce Transparency is not honoured (divergence 249)" was stale since §101 and
  is replaced (`DG-U`). The denylist `deniedNames` lost `resignsFocusOnPress` and `TextMeasurer`
  (`PhaseAnimator` stays, `DG-S`).

## §2 Red first

- Commit 1 (tests): `everyGuideBlockIsCompiledVerbatim` recorded `mirrored.count == blocks.count`
  twice (input and drawing: seven mirrors, five fences).
- With the guides written and the denylist unchanged, `noGuideNamesAnApiThatIsNotOnMaster` recorded two
  issues (`Expectation failed: !document.source.contains(name)`, one per name); after the removal the
  filtered `MetalUITestingTests` run read 172 tests passed.

## §3 Mutations (one full unfiltered run, five disjoint mutations)

Applied to the mirror file at the guide's own spelling, restored from a copy; `git status` clean after.
Run: 3629 tests, 16 issues.

| Mutation | Reddened |
|---|---|
| delete `.resignsFocusOnPress()` in `inputResignRoot` | `theInputGuideAClickOnInertChromeEndsEditing` (2 issues), `everyGuideBlockIsCompiledVerbatim` |
| delete `model.writes.append($0);` in `inputComposeRoot` | `theInputGuideAnInputMethodComposesCommitsAndCancels` (2), the verbatim check |
| `+ 16` to `+ 20` in `DrawingLabelled` | `theDrawingGuideASurfaceIsSizedFromTheMeasuredLabel`, the verbatim check |
| delete `.background(.regularMaterial)` in `DrawingPanel` | `theDrawingGuideAPanelFollowsReduceTransparency`, the verbatim check |
| `tint(in: scheme)` to `tint(in: .light)` in `drawingTintOpacity` | `theDrawingGuideATintOpacityIsTheTable`, the verbatim check |

The five other issues are the `AppKitPresentationTests` sheet issues of a locked screen (baseline).

## §4 Findings (not fixed)

1. `TestWindow.frame(ofID:)` found no `.id` on a proposal `Rectangle`, `GPUSurface` frame or `ZStack`
   (`DG-T`); `docs/testing.md` does not say so.
2. `everyCitedDivergenceHasARow` cannot see that a cited label is retired (`DG-U`).

## §5 Counts

**3629 tests in 3 suites** (3624 + 5), 0 goldens, 229 typecheck guards unmoved. Native run: exactly the five
`AppKitPresentationTests` sheet issues of a locked screen (the lock probe read `CGSSessionScreenIsLocked = 1`,
`displayAsleep main: 1`, so no real-window capture was taken), 0 `error:`, `FR-J no-argument frame: succeeded=true`.
Inventory and undocumented scripts print nothing. The fourteen offscreen images: 0 px, scene identical,
against `b17aee19` (`docs/probes/demo-pixels/compare.sh`, controls as recorded). `swift build --build-tests` 0 warnings. Not run: the Linux image (no `Backends/SDL` change; the guide tests are portable and were
not re-taken there).
