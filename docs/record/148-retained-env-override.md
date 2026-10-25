# 148 - Retained environment override (C14-m, `EO-`)

Branch `perf/retained-env-override` from `58843cca`. Decisions: `docs/superpowers/2026-10-22-retained-env-override-decisions.md`. Spec: `docs/superpowers/specs/2026-10-22-retained-env-override-design.md`.

## 1. Outcome

**The reported defect does not reproduce, and no source change was made.** An `.environment(\.colorScheme, same)` override (and one of every other stamped key) inside an `.equatable()` occurrence is an equal retained key frame to frame: `retainedFingerprint` compares every field by value and `scopedValues` runs once at layout. Every drag frame on every arm below is **h7 m1** (the single miss is the dragged panel's own observed write, reason `serial`), with no `environment` reason in the trace. Before and after are identical because `Sources/` is untouched: new fixture h7 m1 (before and after), the AM- drag, bracket and zoom fixtures unchanged (their suites pass in the same full run with the same counts).

MetalCreator's 187 `colorScheme` lines are one window-start transition frame, not a per-frame cost (`EO-B`; confirmed by MetalCreator on 2026-10-22 from the `58843cca` log by position: all 374 `colorScheme` lines (187 paint, 187 prepaint) are one contiguous block, lines 642-1020, before the first `retained session fired` line (1022) and outside the drag's 375 build-cause lines (1390-3181); the 9/14 per-frame misses never contained them, and the remaining drag misses are `observed`/`serial`/`interior`, the fillet's real changes).

## 2. Pins (Tests/MetalUITestingTests/EnvOverrideFixture.swift)

All green on arrival (a refutation, so the separating arm and the mutations below carry the proof).

| Test | Arms | Expectation |
|---|---|---|
| `anEqualOverrideDoesNotMissAnOccurrence` | none, insideScheme, outsideScheme x light/dark | h7 m1 each drag frame, no `environment` reason |
| `aBackgroundAttachmentWithAnOverrideDoesNotMiss` | `.background { RoundedRectangle.fill(Material.thinMaterial).environment(\.colorScheme, s) }` at the inherited and the opposite scheme, and `.background(tint)` | h7 m1, no `environment` reason (MetalCreator's `glassBackground` shape, `EO-D`) |
| `aRealSchemeChangeStillMissesAndRepaints` | window flipped to dark | a miss naming `colorScheme`, at least 8 misses, scene, hitboxes and accessibility equal a retention-off twin, settled to h8 m0 within three frames |
| `anOverrideOfEveryStampedKeyIsFreeWhenEqual` | displayScale, controlActiveState, accessibilityReduceMotion, accessibilityReduceTransparency, theme | h7 m1, no `environment` reason |

## 3. Mutations (each from a committed state, restored from a copy, full unfiltered native suite, `git status --short` empty after)

- **M1** `retainedFingerprint.colorScheme` replaced by `.light` (4363 tests, 1 issue): reddens `aRealSchemeChangeStillMissesAndRepaints` alone (`reasons.contains colorScheme`).
- **M2** `colorScheme` a pseudo-random bit per call (4363 tests, 956 issues): reddens `anEqualOverrideDoesNotMissAnOccurrence` (all 6 cases), `aBackgroundAttachmentWithAnOverrideDoesNotMiss` (3), `anOverrideOfEveryStampedKeyIsFreeWhenEqual` (5) and `aRealSchemeChangeStillMissesAndRepaints`, plus the retained suites. A first attempt with a call-count parity bit reddened none of the drag arms: eight panels times an even number of calls per frame gave every occurrence the same parity every frame, a broken instrument, replaced by the pseudo-random bit.
- **M3** all five other stamped fields random at once (full suite, 1028 issues) and each alone (filtered to `EnvOverrideTests`, 29 issues each): every one reddens the same four tests. **Limit:** the fingerprint is shared, so the stamped-key arms separate "a field became unstable" from "stable" but do not tell the five fields apart by which arm reddens; the per-field filtered runs name the field.
- Control: an unmutated full run reads 4363 tests passed; `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` the same 4363 passed.

## 4. Verification

Native unfiltered 4363 tests passed (4359 at `58843cca` + 4 new test functions, 9 arm cases); verify switches 4363 passed. Linux image (`metalui-portable`, `MetalUITestingTests`, 564 tests): the new tests pass; `aTaskCompletesUnderRunUntilIdle` (`HarnessClockTests.swift:67`) failed in two of three runs under load with other workflows live and passed once, a Task-timing test no file of this branch touches, not investigated.

## 5. Carried

MetalCreator re-trace after #126 (`EO-B`): answered, see the summary (the burst precedes the drag). If a real per-frame `colorScheme` miss reappears there it lives in a shape the fixture lacks (an override inside a `Deferred`, a theme-derived scheme changing source); build the separating arm first.

## 6. Branch checker (58843cca..9beb7d86)

Clean native build and unfiltered run after `swift package clean`: `Test run with 4371 tests in 10 suites passed after 464.703 seconds`, `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice; inventory and undocumented scripts print nothing; `cmp CLAUDE.md AGENTS.md` identical. `git diff ff0db06e HEAD` touches no `Sources/`, `Backends/` or `Package.swift` (only the fixture file and docs), so pixels, `Backends/SDL` and the Linux image are unchanged by construction and were not re-taken.
Checker mutations (each from a clean tree, restored from a copy, full unfiltered suite, `git status --short` empty after):
- **C1** `retainedFingerprint` `theme:` replaced by `Theme.light`: **survived** (4371 passed). No test reads a theme change through the retained fingerprint; the `theme` equal-override arm cannot see it either. Not a defect of this branch (a pin gap, carried: a real `.theme(_)` change under an `.equatable()` occurrence needs a separating arm, or proof that `AmbientKey`'s paint-side theme read covers it).
- **C2** `retainedFingerprint` `isEnabled: isEnabled && Int.random(in: 0..<8) != 0` (an unlisted field made unstable): 828 issues, reddens `anEqualOverrideDoesNotMissAnOccurrence` (6 cases), `aBackgroundAttachmentWithAnOverrideDoesNotMiss` (3), `anOverrideOfEveryStampedKeyIsFreeWhenEqual` (5) and `aRealSchemeChangeStillMissesAndRepaints`, plus the retained suites.
