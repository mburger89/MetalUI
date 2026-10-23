# Retained theme pin (C14-n) - design

Status: designed 2026-10-22, branch `perf/retained-theme-pin` from `63feea05`. Prefix `TH-`; decisions
[`../2026-10-22-retained-theme-pin-decisions.md`](../2026-10-22-retained-theme-pin-decisions.md); record `149-retained-theme-pin.md`
(written at the Record phase). Divergence labels 785-794: none expected, none taken.

## 1. The gap

Record 148 section 6, checker mutation C1: `retainedFingerprint`'s `theme:` replaced by `Theme.light` survived 4371 tests. Inventory:

- `Theme` is read at paint only (`Frame.theme`/`PaintPass.theme` = `environmentTop.theme`; `Color.resolved(theme:scheme:)`, `ColorContext`,
  `frame.theme[.surface]` in controls). Layout, build, prepaint and accessibility never read it (grep of `Sources/MetalUI`: every `.theme` read is a
  paint or colour-resolution site).
- It reaches a retained decision through exactly one value: `EnvironmentFingerprint.theme`, inside `EnvironmentValues.retainedFingerprint`. That
  fingerprint is consumed at two sites: `retainedAmbientKey()` (`AmbientKey.environment`, the paint `ReplayKey`, and so the prepaint key's ambient)
  and `graftBuildKey()` (`BuildKey.environment`). Nothing else compares a theme.
- Sources of a theme at an occurrence's position: the window's `theme` (`Window.theme`, set from `lightTheme`/`darkTheme` on a scheme change or an
  assignment) stamped at the root (`Frame.rootTheme`); `.theme(_)` (`EnvironmentWrite.theme`); `.colorScheme` writes re-select it
  (`Frame.swift` 670-681).
- `ContentMemoStore`'s getter skip does not read it: `theme` is not `@Environment`-readable (`EV-G`), and a getter's output holds tokens, resolved
  at paint.

Hypothesis (a), proven by reading and to be proven by test: the fingerprint field is the **only** conjunct, so a deleted field replays stale colours
under an `.equatable()` occurrence; the survival is a pin gap, not redundancy. Expected: no source defect, no `Sources/` change.

## 2. Tests (`Tests/MetalUITestingTests/RetainedThemeTests.swift`, new, `@Suite(.serialized) @MainActor`)

Fixture: `THNode: Component, Equatable`, `.equatable()`, painting four colours: `Color(.surface)`-token fill, `Color(.textPrimary)` fill, a
`ThemeColorKey` palette colour (`ThemeKey.accent`, defined in the test), and a `Color(light:dark:)` dynamic colour. Eight panels, a `DragGesture`
strip writing one panel's observed radius (the `EnvOverrideFixture` shape, reuse its `DMModel`, `dragFrames`, `collectTrace`, `RPSnapshot`).
`thWindow(arm:, retain:)` builds a `TestWindow` at 900x160, scale 2, with `testingRetainedGraft = true`. The painted colours are read from
`TestWindow.scene` rect colours per panel (never pixels), and the whole frame is compared to a retention-off twin by `RPSnapshot.differences`.
Every change arm asserts: reasons contain `environment.theme` (the trace name `key.ambient.environment.theme`), misses >= 8, scene colours equal
the new theme's expected values (literal, derived from the two test themes), snapshot equals the twin, and a settled `h8 m0` within 3 frames.

| Test | Arm | Red before (mutation that must redden) |
|---|---|---|
| `aThemeScopeChangeMissesEveryPanelAndRepaints` | (1) `.theme(a)` outside the occurrence, flipped to `.theme(b)` between frames at a fixed scheme | C1 |
| `aWindowThemeAssignmentAtAnUnchangedSchemeMissesAndRepaints` | (2) `window.lightTheme = b` at `.light` (the scheme does not move, so `colorScheme` cannot cover) | C1 |
| `aSchemeSwitchWithTwoDifferentThemesMissesNamingBoth` | (3) `setAppearance(.dark)`, `lightTheme != darkTheme`; reasons name `colorScheme` and `theme` | C1 |
| `aSchemeSwitchWithTheSameThemeStillMissesOnTheScheme` | (3b) both variants one theme: the miss is `colorScheme` alone, scene dynamic colour flips | field `colorScheme` of the fingerprint replaced (survival expected unless pinned; EO-E covers it) |
| `anEqualThemeRebuiltEveryFrameHits` | (4) `.theme(Theme.light)` re-created every frame, equal by value: drag frames h7 m1, no `environment` reason | mutation `theme != other.theme` -> `true` in the reason/equality path (`EnvironmentFingerprint.==`) |
| `aThemePaletteOverrideChangeMisses` | (5) `lightTheme[AccentKey.self] = c`, only the palette differs (`Theme` equality includes it, `CR-`) | C1 |
| `aThemeChangeIsNotCoveredByAnotherConjunct` | (6) the same as (2) with the fingerprint's theme neutralised **in the paint key only** (M2) and the graft key untouched: asserts the paint decision, not the graft, is what protects | M2 |
| `aGraftedOccurrenceUnderAThemeChangeIsRebuiltOrEqual` | (7) graft site: after (2), element requests equal the retention-off twin's whenever the paint missed (a graft that survives a theme change is sound, a build never reads a theme) | M3 (expected survivor, see `TH-C`) |
| `theVerifySwitchSeesAThemeChange` | (8) arms (1)-(2) run in a verify-mode child, the `#expect(processExitsWith:)` shape of `RetainedVerifyTests` 14c (there is no in-process `Window.verifyRetained` seam; env `METALUI_VERIFY_RETAINED=1` is read in the child): exit 0 with the fingerprint intact; with M1 the child traps naming the paint channel (verified by running the child once under M1 by hand, since a mutated build cannot be an in-suite arm), `TH-D` | M1 under the env switch |

Mutations, applied one at a time, committed first, restored from a copy, full unfiltered suite each, `git status --short` after:
M1 = C1 (`retainedFingerprint` `theme: Theme.light`); M2 = `retainedAmbientKey()` builds its fingerprint with `theme` forced to `.light` (graft
untouched); M3 = same in `graftBuildKey()` only; M4 = `EnvironmentFingerprint.==`/`differences` ignoring theme. Reddened tests are named in
record 149. If M1 reddens only by the new tests, `TH-A` stands. If M3 survives, `TH-C` records that the graft's theme conjunct is conservative.

## 3. Files, lanes

One lane (one new test file, disjoint from everything): `Tests/MetalUITestingTests/RetainedThemeTests.swift`. Expected `Sources/` change: none. If a test
finds a stale colour, the fix is in `retainedFingerprint`/the decision it feeds, value-identical otherwise, and the fourteen images, the Linux
image `MetalUITestingTests` and the full verification list then apply; with no `Sources/` change they are not owed (only the root native suite,
the verify-switch run, default-build warnings 0, inventory scripts).

## 4. Out of scope

- No SwiftUI probe: `Theme` and token colours have no SwiftUI counterpart (class M, `CR-`, `EV-G`); no gpui comparison needed (gpui re-renders
  views, no retention). Nothing here is a SwiftUI-facing claim.
- Public API, divergence, shader, platform requirement, demo, human check: none (nothing a person can see differs; scene colours are read from the scene).
- A theme changing **inside** an occurrence at an unchanged value of the component: not reachable (the theme enters from outside or from the window).
  The `theme change inside a Deferred` shape of record 148 section 5 is named but not built (owner: C14-m's MetalCreator re-trace, only if a trace shows it).
