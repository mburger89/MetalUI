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

### 1.4 Critic round

One agent attacked the committed design (`0abcfcf`) and revised it in the same
commit; rulings `TE-Q`…`TE-S` (next unused `TE-T`).

- **The probe reproduces.** `swiftui-text-semantics.swift` compiled and run by
  the critic: all 294 lines byte-identical to the header (exit 0, stderr
  empty).
- **F8's render field was a broken instrument** — `ImageRenderer` ignores
  `controlSize` (new probe `swiftui-controlsize-text-render.swift`, R1: 13 pt
  at every size against a 2404 px 9-vs-13 control), while layout identifies
  9 / 11 / 13 uniquely (R2). `TE-F` stands on layout; the drawn font joins the
  owed real-window capture (`TE-Q`). An `NSHostingView.cacheDisplay`
  instrument drew blank with the screen locked and was dropped.
- **`TE-H` makes wrapping text vertically flexible in stacks**, which the
  design's 0 px claim had not considered. New probe
  `swiftui-text-in-stacks.swift` (K0–K4): SwiftUI serves the text its equal
  share before a spacer and keeps only the lines that share holds (one line at
  60 beside a `Spacer`, three at 100, six at 200). Adopted as SwiftUI's
  answer; lane 3 takes a height census before implementing and a ruling names
  any moved image; pin 3.23 (`TE-R`).
- **Amended** (`TE-S`): lanes rebalanced (font selection to lane 2, so the two
  oracle-heavy pieces are in different lanes); `TE-L`'s `display: .stack`
  branch ruled a permanent refusal, and the report table keeps 265 entries
  with 16 owners flipping to `nil` (the design read 265 → 260); divergence
  60's pin gains an 11 pt arm that separates at the stored rect; divergence
  86's "not a function" softened to the fits tried; `VerticalAlignment`'s new
  cases carry a source-break migration note; the truncation token is shaped
  through `shapeCascading`, and an unmatched oracle case stops the lane for a
  ruling; the Windows stack budget is measured before and after.
- **Rejected** attacks are listed in `TE-S` (baseline `Alignment`s
  unreachable, no `foregroundColor` collision, no out-of-tree conformer,
  `FontKey` reads variations, no part-2 creep, `SA-M` unmoved by
  construction).

Expected suite after the three lanes: ≈ 1690 (spec §9).
