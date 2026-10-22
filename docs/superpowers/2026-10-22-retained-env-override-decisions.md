# Retained environment override - decisions

Rulings for item C14-m. Spec: [`specs/2026-10-22-retained-env-override-design.md`](specs/2026-10-22-retained-env-override-design.md). Record: `../record/148-retained-env-override.md`.
Branch `perf/retained-env-override` from `58843cca`. Reserved divergence labels 775-784: none taken.

Prefix **`EO-`**, lettered. **Next unused: `EO-D`.** (Moves in the commit that appends a ruling.)

**Carried.** `AM-D`, `AM-E`, `EE-F`, `EE-K`, `SB-G`, `CR-K`, `CR-Q`, `CR-Z`, `EV-V`, `DM-F`.
No SwiftUI probe, no gpui comparison: no observable behaviour moves.

## EO-A - An override equal to the previous frame's value does not miss; no fix is owed

**Question.** Does `.environment(\.colorScheme, same)` re-key a retained pass every frame?
**Ruling.** No. `retainedFingerprint` compares every stamped field by value and `scopedValues` runs once at layout (`EV-V`), so an equal override is an equal key.
Measured on the C14-m fixture at `58843cca`: every drag frame h7 m1 on six arms (no override, inside, outside; light = inherited, dark = a real difference), the
single miss `serial`, no `environment` reason. No source change is made; the fixture stays as a pin.
**Evidence.** Spec section 1.2; probe output `EOPROBE ... ["h7 m1" x6, "h8 m0"] reasons ["serial"]` for all six arms (run on `58843cca`, test `EnvOverrideTests`).
**Cost if wrong.** A real per-frame colorScheme miss exists in a shape the fixture lacks (an override inside a `Deferred`, a material fill inside a graft, a scheme written from a changing source): MetalCreator's re-trace after #126 would show `colorScheme` lines in warm frames; then a separating arm is built first.

## EO-B - MetalCreator's 187 colorScheme lines are one frame, not a per-frame cost

**Question.** Why does `fillet-trace.log` show 187 occurrences missing on `colorScheme`?
**Ruling.** They are a single frame's prepaint (lines 642-828) and paint (832-1020) following `first-or-dropped` lines: the window's first-to-second-frame scheme transition (`CR-Q`), a real change. The warm medians (m 9 / max 14) come from `observed`, `serial`, `key.interior`, `versions` and `noRecord` reasons, none from the environment.
**Evidence.** `awk` over the log: colorScheme lines are two contiguous runs and nowhere else; reason histogram in spec 1.3. The log does not name the test that produced the transition; the claim "setup frame" is inferred from the `first-or-dropped` neighbours, not from the bench source.
**Cost if wrong.** If those frames are inside the timed region, one miss-all frame per scheme change is the correct behaviour anyway (a real change must repaint).

## EO-C - Stamped keys written by an override: pinned, not fixed

**Question.** Do `displayScale`, `controlActiveState`, `accessibilityReduceMotion/Transparency`, `theme` share the defect when written by an override?
**Ruling.** By reading they cannot: all are plain value fields of the fingerprint. The lane pins each with an equal-override arm (spec test 3) instead of changing code; a red arm is a finding.
**Cost if wrong.** A field with identity semantics is found by test 3 and fixed then, with its own ruling.
