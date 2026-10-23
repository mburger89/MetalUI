# 149 - Retained theme pin (C14-n, `TH-`)

Branch `perf/retained-theme-pin` from `63feea05`. Decisions: `docs/superpowers/2026-10-22-retained-theme-pin-decisions.md`. Spec: `docs/superpowers/specs/2026-10-22-retained-theme-pin-design.md`.

## 1. Outcome

**Record 148 section 6's surviving mutation C1 was a pin gap, not a redundant field, and no source change was made.** `EnvironmentFingerprint.theme` is the only conjunct that sees a theme (`TH-A`): with it replaced by `Theme.light`
an `.equatable()` occurrence replays stale colours for a `.theme(_)` change, a `Window.lightTheme` assignment at an unchanged scheme and a palette override (the frame then differs from a retention-off twin, measured below).
The graft's copy of the field (`BuildKey.environment`) is conservative: neutralising it alone reddens nothing (`TH-C`, M3). No public declaration, no divergence (785-794 untouched), no SwiftUI probe (class M, nothing SwiftUI-facing).

## 2. Pins (`Tests/MetalUITestingTests/RetainedThemeTests.swift`, 9 tests, suite 4371 to 4380)

Eight `.equatable()` panels paint a surface token, a text token, a `ThemeColorKey` palette colour, a `Color(light:dark:)` colour and an observed-radius colour. Colours are read from the scene's rects, the frame is compared whole to a retention-off twin.

| Test | Arm | Red under |
|---|---|---|
| `aThemeScopeChangeMissesEveryPanelAndRepaints` | `.theme(_)` flipped between frames, fixed scheme | M1, M2, M4 |
| `aWindowThemeAssignmentAtAnUnchangedSchemeMissesAndRepaints` | `window.lightTheme` assigned at `.light` (the separating arm, `TH-B`) | M1, M2, M4 |
| `aSchemeSwitchWithTwoDifferentThemesMissesNamingBoth` | scheme switch, two themes | M1, M2, M4 |
| `aSchemeSwitchWithTheSameThemeStillMissesOnTheScheme` | scheme switch, one theme: miss is `colorScheme` alone, dynamic colour flips | none by design (EO-E covers `colorScheme`) |
| `anEqualThemeRebuiltEveryFrameHits` | equal theme re-created each frame: h7 m1 per drag frame, no `environment` reason | none (control for M1-style over-keying) |
| `aThemePaletteOverrideChangeMisses` | only `Theme.palette` differs | M1, M2, M4 |
| `aThemeChangeIsNotCoveredByAnotherConjunct` | the paint decision's own reasons name `environment.theme`; no stale surface | M1, M2, M4 |
| `aGraftedOccurrenceUnderAThemeChangeIsRebuiltOrEqual` | frame equals the twin after a theme change | M1, M2 |
| `theVerifySwitchSeesAThemeChange` | arms 1 and 2 in a verify-mode child (exit test, `TH-D`) | M1, M2 (child dies with `SIGTRAP`) |

## 3. Mutations (committed first, restored from `git checkout -- Sources`, full unfiltered native suite, `git status --short` empty after each)

Control: unmutated, 4380 tests in 11 suites passed.

- **M1** `retainedFingerprint`'s `theme:` replaced by `Theme.light` (the checker's C1): 28 issues, reddens `aThemeScopeChangeMissesEveryPanelAndRepaints`, `aWindowThemeAssignmentAtAnUnchangedSchemeMissesAndRepaints`, `aSchemeSwitchWithTwoDifferentThemesMissesNamingBoth`, `aThemePaletteOverrideChangeMisses`, `aThemeChangeIsNotCoveredByAnotherConjunct`, `aGraftedOccurrenceUnderAThemeChangeIsRebuiltOrEqual` and `theVerifySwitchSeesAThemeChange` (child `SIGTRAP`). Survivors: 3b and the equal-rebuild control, as designed. In the failing arms the frame differs from the twin (stale rects) and the old surface colour is still painted, so the replay was a stale one.
- **M2** `retainedAmbientKey()`'s fingerprint with `theme` forced to `.light`, graft key untouched: 28 issues, the same seven tests. The paint decision alone protects a colour, the graft does not cover it.
- **M3** `graftBuildKey()`'s fingerprint with `theme` forced to `.light`, paint key untouched: **survives, 4380 passed.** The graft's theme conjunct is conservative (`TH-C`): a build never reads a theme; kept because the environment is keyed whole (`EE-F`, `RK-`).
- **M4** the `theme` line of `EnvironmentFingerprint.differences(from:)` removed (trace names only; the synthesized `==` is untouched): 6 issues, `everyEnvironmentFingerprintFieldIsNamedWhenItDiffersAlone` (already existing) and the five tests that read the reason name.

## 4. Verification

- Native build 0 `error:`, the only `warning:` SwiftPM's deprecation notice; `FR-J no-argument frame: succeeded=true`.
- `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` whole suite: 4380 passed, 0 issues.
- No `Sources/` change, so the fourteen images, the Linux image and the inventory censuses are unmoved by construction (inventory scripts print nothing).

## 5. Carried

- The verify child's trap text is not captured by the exit test (only `SIGTRAP`), so which channel names a theme under M1 is unread; the pin is the death, not the message.
- A theme changing **inside** a `Deferred` (record 148 section 5) is named, not built; owner C14-m's MetalCreator re-trace, only if a trace shows it.
