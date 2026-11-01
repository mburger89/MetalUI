# 185 - shape styles and the tint (`SS-A`..`SS-G`)

**Renumbered 183→185 on the 2026-11-01 rebase onto `423088fb`**: `183-x11-window-icon.md` (PR #175) was published first and `184` is held by the open glyph-atlas PR #177 (the precedent: record §38 and §48 headers).

2026-11-01, branch `feat/shape-styles` from master `3a2c5715`; round-3 item R3-9. Rulings:
`docs/superpowers/2026-11-01-shape-styles-decisions.md`. Rule: `docs/rules/drawing.md` ("Shape styles and the tint").

## 1. What was there

No `ShapeStyle`: every colour-taking site had a `Color` overload, a `ColorToken` twin and (since controls and looks, `LK-R`) a gradient and a
`Material` overload; `.foregroundStyle` took a `Color` (divergence 119); controls painted `theme[.accent]` through
`controlAccent(_:)` (a `ColorToken`, `.accent` when key, else `.separator`), and `Color.accentColor` was the `.accent` token. There was no
closed `Fill` enum to keep: the resolved form is the pair a `ShapeView.Layer` already held (colour, `GradientFill`, `Material`).

## 2. Design

`ShapeStyle` (SwiftUI's shape: `Resolved`, `resolve(in:)`) with `Color`, the two gradients, `Material`, `TintShapeStyle` and `AnyShapeStyle`
conforming; the internal `ShapeStyleStorage` is the resolved form; third parties conform by composition only (`SS-B`). Each colour-taking
modifier keeps its concrete overloads and gains a generic one, so overload resolution leaves every existing call alone. Paint-time sinks
(`ShapeView` layers, `background(_:in:)`, a group's `foregroundStyle`/`tint`) resolve in the position's environment; build-time sinks
(`Box.background`, `Text.foregroundStyle`) lower primitives exactly and resolve a custom composition in a bare environment (divergence 976).

## 3. The tint

`EnvironmentValues.tint` (fingerprint field), `.tint(_:)`, `Color.accentColor` as a provider that reads it (the tint resolves with no tint
of its own: `.tint(.accentColor)` is the theme accent), `controlAccent(_:)` returning a `Color` (`environment.tint ?? Color(.accent)` when
key, so an untinted control is the same colour value as before). Readers: `.borderedProminent`, `Toggle` (three looks), `Slider`,
`ProgressView` (bar, sweep, ring), the radio `Picker`, every focus ring, a `List`'s selected row, field selection, link runs, `.link` and
`.glassProminent`. Theme-only surfaces keep the theme accent (divergence 977).

## 4. Source breaks

None for a call site (the full tree, demos and examples build unchanged). A file declaring its own `ShapeStyle`, `AnyShapeStyle`,
`ResolvedShapeStyle` or `TintShapeStyle` collides, and `Color.accentColor == Color.accent` is no longer true (`docs/migration.md`). A stored
property on `EnvironmentValues`/`EnvironmentFingerprint`: `swift package clean`.

## 5. Tests

`ShapeStyleTests.swift` (13), `ShapeStyleCompileGuards.swift` (G-SS1, plain-import `typecheckFile`: use, compose, erase; three negative arms),
`RetainedShapeStyleTests.swift` (3; `METALUI_VERIFY_RETAINED=1` skips them as the other retained-hit tests do). Updated: the fingerprint field
count 26 -> 27 (`RetainedAmbientMissTests`), `RetainedSubtreeInternalTests`'s field table, and `ReduceTransparencyTests`' scan forced the stroke
fallback to read the flat tint through `ShapeStyleStorage.representativeColor` rather than `material.color`.

**Counts** (2026-11-01, `feat/shape-styles` after `swift package clean`, a `--build-system native --build-tests` build and an unfiltered
`--no-parallel` run): **4804 tests in 13 suites passed, 0 issues**; `FR-J no-argument frame: succeeded=true` printed; guard G-SS1 printed
`positive: succeeded=true`, `negatives: badResolved=false forged=false notAStyle=false`. The first unfiltered run (before the two fixes above)
read 4804 tests and 2 issues. `Backends/SDL` builds (`swift build $(python3 scripts/fetch-accesskit.py --print-flags)`).

## 6. Mutations

Each applied to the declaration named, built and run against `ShapeStyle|RetainedAmbientMiss|everyEnvironmentField`; the tree was restored after each.

| Mutation | Reddened |
|---|---|
| `controlAccent` ignoring `environment.tint` | `aTintReachesEveryControlsAccent`, `theNearestTintWinsAndNilRemovesAnOuterOne`, `aTintDoesNotRevealAnInactiveWindowsAccent` |
| the `.accentColor` provider resolving `theme[.accent]` only | `accentColorFollowsTheTintButTheAccentTokenDoesNot`, `aLinkRunDrawsInTheTint`, `theTintStyleFillsAndColoursTextInTheScopesTint`, `aBoxTakesAStyleForItsBackgroundAndBorder`, `aTintChangeMissesEveryPanelAndRepaints` |
| `retainedFingerprint` with `tint: nil` | `aTintChangeMissesEveryPanelAndRepaints`, `removingTheTintMissesAndFallsBackToTheAccent`, `theTintIsPartOfTheEnvironmentFingerprint` |
| `AnyShapeStyle.init` re-wrapping an `AnyShapeStyle` | `anAnyShapeStyleRoundTripsAndComparesByWhatItWraps` |
| `CustomBox.equals` always true | `anAnyShapeStyleRoundTripsAndComparesByWhatItWraps` |
| `paintStyleFill` dropping the gradient case | `aColourGradientAndMaterialPaintThroughSomeShapeStyleAsTheConcreteOverloadsDo` |
| `shapeStyleStorage` resolving in a bare environment | `aCustomStyleResolvesAgainstTheEnvironmentItIsPaintedIn`, `anAnyShapeStyleRoundTripsAndComparesByWhatItWraps` |
| `TintShapeStyle.storage` a fixed red | `theTintStyleFillsAndColoursTextInTheScopesTint`, `aBoxTakesAStyleForItsBackgroundAndBorder`, `aTintChangeMissesEveryPanelAndRepaints`, `removingTheTintMissesAndFallsBackToTheAccent` |
| `tint(_ color:)` writing only a non-nil colour | `theNearestTintWinsAndNilRemovesAnOuterOne` |
| the gradient arm of `paintStyleStroke` drawing nothing | `strokesAndBackgroundsTakeAnyShapeStyle` |
| `StyledElement.background<S>` dropping the linear-gradient case | `aBoxTakesAStyleForItsBackgroundAndBorder` |
| `Slider` / `Toggle` (checkbox) / `Button` (`.borderedProminent`) / `ProgressView` / radio `Picker` each ignoring the tint | `aTintReachesEveryControlsAccent` (Slider also `theNearestTintWinsAndNilRemovesAnOuterOne`) |
| `Color.accentColor` the `.accent` token again | the second row's five tests |
| `foregroundStyle<S>` resolving in a bare environment | `aCustomStyleResolvesAgainstTheEnvironmentItIsPaintedIn` |

The plain-import guard G-SS1 was not mutated (it reads the built module directory; its negative arms disagree with the positive one by construction). The
tests were written after the implementation in this lane, so "red before" is shown by these mutations rather than by a failing first run.

## 7. Carried

`HierarchicalShapeStyle` and `foregroundStyle(_:_:)`/`(_:_:_:)` (divergence 119 stays), `ForegroundStyle`, `ImagePaint`, the
`ShapeStyle where Self == Color` statics, a tint on the theme-only surfaces, `AngularGradient`/`EllipticalGradient`, `Text` gradient fills.
Human check group SS (unrun). The progress ring's accent colour is covered by shape only through its sibling bar (the ring paints a path image).
