# Retained environment override - decisions

Rulings for item C14-m. Spec: [`specs/2026-10-22-retained-env-override-design.md`](specs/2026-10-22-retained-env-override-design.md). Record: `../record/148-retained-env-override.md`.
Branch `perf/retained-env-override` from `58843cca`. Reserved divergence labels 775-784: none taken.

Prefix **`EO-`**, lettered. **Next unused: `EO-I`.** (Moves in the commit that appends a ruling.)

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

## EO-D - Critic: the fixture must hold MetalCreator's real shape before "no fix" stands

**Question.** Is EO-A's refutation measured on the defect's shape?
**Ruling.** Not yet. `glassBackground` writes the override as `.background { shape.fill(material).environment(\.colorScheme, themeScheme) }`: a **background attachment** (`.child(of:at:-1)`, MC-P) holding a **material** fill, with the scheme being the *theme's* (which may differ from the window's), inside an `.equatable()` occurrence. The fixture's declared `insideMaterial` arm is unused and no arm uses `.background`. The lane adds `insideMaterial` as `.background { RoundedRectangle.fill(Material.thin).environment(\.colorScheme, s) }` at s = inherited and the opposite, and a `.background(tint)` sibling, all at h7 m1. EO-A stands only if these are green; a red arm is the defect and is fixed (fingerprint or the point where the attachment's scope is keyed), with its own ruling.
**Cost if wrong.** The defect lives in the attachment/material path and "no fix" ships a false closure.

## EO-E - Critic: a green-on-arrival pin needs a separating arm

**Ruling.** Test 2 (`aRealSchemeChangeStillMissesAndRepaints`) is mandatory, not "to write": it is the separating arm of test 1 and is red under the named mutation (drop `colorScheme` from the fingerprint). Test 1's mutation is restated without invented symbols: make `retainedFingerprint.colorScheme` depend on a per-frame value (a frame counter parity); the `outsideScheme` and `insideMaterial` arms must redden. Mutation results are named in the record, not asserted here.

## EO-F - Critic: evidence for EO-A/EO-B is recorded, and EO-B stays a hypothesis

**Ruling.** The `EOPROBE` numbers are copied into the record (§148) from a re-run at the lane head, not cited from memory. EO-B (the 187 lines are one startup frame) was re-checked against `fillet-trace.log`: the two blocks are 187 lines each, preceded by `first-or-dropped`, and the 376 colorScheme lines occur nowhere else; MetalCreator confirmed it on 2026-10-22 by line position in the same log (one block, lines 642-1020, ahead of the first observation fire at 1022 and of every drag build line, 1390-3181), so it is no longer an inference. The theme-scheme-differs-from-window case is the one place a startup transition could recur per scheme change; test 2 covers it.

## EO-G - Closure: all EO-D/EO-E arms green on arrival, mutations named, no source change

**Ruling.** The `insideMaterial` background-attachment arms (inherited and opposite scheme), the `.background(tint)` sibling, the real-change arm and the five stamped-key arms are green on `58843cca`; the fixture stays as pins and `Sources/` is unchanged. The pins are proved red by mutation (record 148 section 3): dropping `colorScheme` from the fingerprint reddens the real-change arm alone, an unstable (pseudo-random) `colorScheme` or any one other stamped field reddens every equal-override arm. A call-count parity mutation is not an instrument here (even calls per frame), recorded as such.
**Evidence.** Record 148 sections 2-3; verify-switch run 4363 passed.
**Cost if wrong.** As `EO-A`: the defect is in a shape the fixture lacks; a MetalCreator re-trace decides.

## EO-H - A flaky Linux-image test is recorded, not investigated

**Ruling.** `HarnessClockTests.aTaskCompletesUnderRunUntilIdle` (`HarnessClockTests.swift:67`) failed in two of three `MetalUITestingTests` runs in the Linux image under load (other workflows live) and passed once; no file of this branch touches it or the harness clock, and the native macOS suite is green. It is unrelated to this item and left as an observed flake.
**Cost if wrong.** A real harness timing defect off Darwin goes unowned; the next Linux-image run on a quiet machine decides.
