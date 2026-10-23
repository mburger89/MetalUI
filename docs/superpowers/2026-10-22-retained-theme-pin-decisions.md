# Retained theme pin - decisions

Rulings for item C14-n. Spec: [`specs/2026-10-22-retained-theme-pin-design.md`](specs/2026-10-22-retained-theme-pin-design.md). Record: `../record/149-retained-theme-pin.md`.
Branch `perf/retained-theme-pin` from `63feea05`. Reserved divergence labels 785-794: none taken.

Prefix **`TH-`**, lettered. **Next unused: `TH-D`.** (Moves in the commit that appends a ruling.)

**Carried.** `EO-E`, `EE-F`, `SB-AA`, `RK-`, `CR-` (`PaintPass.resolve`), `EV-G`, `AM-D`.
No SwiftUI probe, no gpui comparison: `Theme` has no SwiftUI counterpart and nothing observable moves.

## TH-A - The fingerprint's theme field is the only conjunct that sees a theme; C1's survival is a pin gap

**Question.** Did C1 survive because another conjunct covers a theme change (the field is redundant) or because no test looks?
**Ruling.** No test looks. Every read of `Theme` is at paint or colour resolution; the only value carrying it into a retained decision is `EnvironmentFingerprint.theme`
(consumed by `retainedAmbientKey()` and `graftBuildKey()`). Deleting the field would replay stale colours for a `.theme(_)` change or a `lightTheme`
assignment at an unchanged scheme. The fix is tests, not source; the field stays.
**Evidence.** `grep '\.theme\b' Sources/MetalUI` (paint and `Color.swift` sites only); `Frame.swift` 635-681 (the three writers); record 148 section 6 C1. The tests of the spec
section 2 turn this reading into a measurement, with M1-M4.
**Cost if wrong.** If a test shows another conjunct covers it, M1 survives alone and the field is redundant but harmless; `TH-B` then pins the covering conjunct instead.

## TH-B - Arm (2), a window theme assignment at an unchanged scheme, is the separating arm

**Question.** A scheme switch changes `colorScheme` and `theme` together; which arm isolates the theme?
**Ruling.** Assigning `window.lightTheme` at `.light` (and a `.theme(_)` flip under a fixed scheme) changes `theme` alone, so only the theme field can cause the miss.
A scheme-switch arm is kept (3, 3b) for the two-field case and the same-theme case, but is never counted as the pin.
**Evidence.** `Window.lightTheme.didSet` (`guard lightTheme != oldValue, colorScheme == .light`; sets `theme`); EO-E covers `colorScheme` alone.
**Cost if wrong.** A pin that a scheme change satisfies would leave M1 alive; the red-before column names the arm that alone reddens it.

## TH-C - The graft's theme conjunct is conservative; pinned by equality with the retention-off twin, not by a miss count

**Question.** A build never reads a theme, so is `BuildKey.environment`'s theme field load-bearing?
**Ruling.** Expected no: a graft that survives a theme change replays layout and state events that do not depend on it, while the paint decision (M2) still misses. The field stays (the
environment is keyed whole, `RK-`, `EE-F`); the test asserts soundness (frame equals the twin), and M3 is recorded as a survivor if it survives, named, not hidden.
**Evidence.** Spec section 1 (no build or layout read). Record 149 states the measured outcome.
**Cost if wrong.** If M3 reddens something, a build does read a theme through a path the grep missed, and the field is load-bearing; the test names it.
