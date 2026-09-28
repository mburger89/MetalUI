# 59 — Text semantics (plan task 11, part 1)

Branch `feat/text-semantics` from `169d166`. Spec
`docs/superpowers/specs/2026-09-28-text-semantics-design.md`; rulings
`TE-A`…`TE-P` in `docs/superpowers/2026-09-28-text-semantics-decisions.md`;
probe `docs/probes/swiftui-text-semantics.swift`. Written by the design
session, the lanes and the Record phase.

## 1. Design

### 1.1 Baseline

At `169d166`, in this worktree's own `.build`: `swift build --build-system
native --build-tests` — 0 `error:`, one `warning:` (SwiftPM's deprecation
notice); unfiltered `swift test --build-system native --no-parallel` —
`Test run with 1644 tests in 3 suites passed after 95.662 seconds`, one
`FR-J no-argument frame: succeeded=` line (guards ran).

### 1.2 The probe

`docs/probes/swiftui-text-semantics.swift`, new: 294 recorded lines, compiled
form run twice and interpreted form once, all byte-identical; the screen was
locked (lock probe `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`),
which no arm depends on — every measurement is a custom `Layout` inside an
`NSHostingView`'s `fittingSize` or an `ImageRenderer` render. The first run
(G0–C9) raised questions the same session answered with the X arms (X1–X13),
appended to the same file and re-recorded whole.

Findings that changed the design while it was being written:

- **The height proposal limits a text's lines** (L5, X9), refuting the
  unprobed sentence in `ProposalText.swift`'s doc comment ("the height
  proposal does not truncate or scale text, matching the measured SwiftUI
  custom-Layout behavior"). `TE-H` item 2.
- **`Text.bold()` fits no rule** (X1, X1b, F2e, X12), so it is not offered
  (`TE-B` item 4).
- **SwiftUI's line height is not a function of CoreText's metrics** (X13), so
  MetalUI's `ceil(ascent + descent + leading)` stays and the difference is
  divergence 86 (`TE-G`).
- **Truncation is CoreText's truncated line** except one middle arm (X5),
  divergence 87 (`TE-I`).
- **A `GridRow`'s baseline alignment overflows its cells** (X11), which the
  stack rule (B2) does not produce; it traps, divergence 88 (`TE-K`).

### 1.3 Plan

Three lanes in order: 1 the seam and both text systems, 2 the kernel's
baselines and the legacy `baseline` fields, 3 the element surface (spec §8).
Expected demo change: none (spec §7).
