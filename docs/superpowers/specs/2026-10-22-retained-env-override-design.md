# Retained environment override (C14-m) - design

Item C14-m: "an unchanged `.environment(\.colorScheme, same)` override re-keys every retained pass". Branch `perf/retained-env-override` from `58843cca`.
Decisions: [`../2026-10-22-retained-env-override-decisions.md`](../2026-10-22-retained-env-override-decisions.md) (prefix `EO-`). Record: `docs/record/148-retained-env-override.md`.
Divergences 775-784: none taken. No public API, no SwiftUI probe (no observable behaviour moves), no gpui comparison.

## 1. Finding: the defect as stated does not reproduce

1. **The key compares the environment by value.** `AmbientKey.environment` is `EnvironmentValues.retainedFingerprint`, an `Equatable` struct whose `colorScheme`
   is a `ColorScheme` and whose `theme` is a `Hashable` `Theme` of `Hsla` values; `displayScale`, `controlActiveState`, `accessibilityReduceMotion/Transparency`
   are plain values. An `EnvironmentScope` computes its `values` once at layout (`scopedValues(applying:)`, `EV-V`) and layout/prepaint/paint push those
   same values. There is no identity, epoch or write count in the fingerprint for these fields (hypotheses b and c refuted by reading).
2. **Fixture** (`Tests/MetalUITestingTests/EnvOverrideFixture.swift`): eight `.equatable()` panels under a `DragGesture` writing one panel's observed
   radius, arms `none`, `insideScheme` (`.environment(\.colorScheme, s)` around the panel content, as MetalCreator's `materialLayer`), `outsideScheme` (around
   the `.equatable()` call, so the override is inside the *key*), each at `s = .light` (the inherited value) and `.dark` (a real difference from the window).
   Measured on `58843cca`, per drag frame: **h7 m1 for all six arms**, last (settle) frame h8 m0; the one miss is reason `serial` (the written panel); no
   `environment` reason on any frame. An equal override and a constant different override are free (hypothesis a refuted by measurement).
3. **MetalCreator's log** (`fillet-trace.log`, read only): `key.ambient.environment.colorScheme` (189 paint lines) and `ledgerKey...colorScheme` (187
   prepaint lines) occur in **exactly two contiguous blocks** (lines 642-828 prepaint, 832-1020 paint) of a 3200-line log: one frame's prepaint and paint, just
   after a block of `first-or-dropped` lines. That is the first-frame-to-second-frame transition of a window (the platform appearance is stamped after
   the first build: `CR-Q`/`CR-Z`), a real scheme change that must miss. No colorScheme line appears among the warm drag frames; the warm 9/14 misses
   are the `observed`, `serial`, `key.interior`, `versions` and `noRecord` lines (the 301/300/249/150/148 counts), which `AM-`/`DM-` own.
   The item's premise ("same 187 occurrences per pass miss every frame") reads two single-frame bursts as per-frame.

## 2. Scope

No source change. One lane, tests only, disjoint from everything else:

- `Tests/MetalUITestingTests/EnvOverrideFixture.swift` (written in the design phase, green on arrival: there is nothing to fix).

Deferred (named, owner): the remaining warm misses in MetalCreator's fillet drag (`observed`/`serial` on occurrences whose observed property is the
dragged one, `noRecord`, `versions`) are a MetalCreator re-trace after PR #126 merges, owner C14-n if a reason survives on a fixture; this item does not
chase them (no separating arm exists on the fixtures).

## 3. Tests (all in `EnvOverrideFixture.swift`; red-before is N/A, green on arrival, each with the mutation that must redden it)

| # | Test | Asserts | Mutation that must redden it |
|---|------|---------|------------------------------|
| 1 | `anEqualOverrideDoesNotMissAnOccurrence(arm:scheme:)`, 6 arms | every drag frame h7 m1, no `environment` reason in the trace | `retainedFingerprint.colorScheme` made to depend on a per-frame value (frame-counter parity): the `outsideScheme` arms redden |
| 2 | `aRealSchemeChangeStillMissesAndRepaints` (to write) | flip `Window` preferred scheme (or `TestWindow` appearance) mid-script: every panel misses once naming `colorScheme`, scene/hitboxes/AX equal a retention-off twin (`RPSnapshot`) | drop `colorScheme` from `retainedFingerprint`/`differences`: reddens (the fixture paints a scheme-dependent token) |
| 3 | `anOverrideOfEveryStampedKeyIsFreeWhenEqual` (to write) | arms writing `displayScale`, `controlActiveState`, `accessibilityReduceMotion`, `accessibilityReduceTransparency`, `theme` equal to the inherited value: drag frames h7 m1 | as 1 for each field |
| 4 | the verify switch | tests 1-3 pass under `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` (they skip the work-count asserts there, as `rsVerifying` pins do) | n/a |

Mutations run committed, unfiltered, restored from a copy, `git status --short` after each, reddened tests named. Tests 2 and 3 are the implementer's lane
work (test 2 mandatory, EO-E); test 1 is written and green. Lane also adds the `insideMaterial` arm in `.background { }` attachment shape and a `.background(tint)` sibling (EO-D); a red arm is the defect and gets fixed under its own ruling.

## 4. Demo and human checks

No demo change, no human-check group (no look moves).

## 5. Verification (implementer)

Unfiltered native suite after `swift package clean` (4359 + new tests), the verify-switch run, 0 warnings both build systems, inventory scripts print
nothing (no public declaration), the fourteen images 0 px against `58843cca` (no `Sources/` change: expected trivially), Linux image `MetalUITestingTests`.
Before/after misses per frame on the AM- drag fixture, bracket and zoom fixtures: unchanged by construction (no source change); the new fixture reads
h7 m1 on every arm.
