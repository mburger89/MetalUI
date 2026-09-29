# 60 — Shapes and rendering (plan task 11, part 2)

Branch `feat/shapes-and-rendering` from `ff2ae92` (part 1's tip, record §59).
Spec `docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md`;
rulings `TE-AC` onward in `docs/superpowers/2026-09-28-text-semantics-decisions.md`
(part 1's doc, same prefix); probe `docs/probes/swiftui-shapes-and-rendering.swift`.

## §1 Design (2026-09-29)

**Baseline re-taken at `ff2ae92`** in this worktree: `swift build
--build-system native --build-tests` 0 `error:`, the one SwiftPM deprecation
`warning:`; unfiltered `swift test --build-system native --no-parallel` →
`Test run with 1706 tests in 3 suites passed after 113.595 seconds`, the
`FR-J no-argument frame: succeeded=` line present. 105 guards, 0 goldens, 65
live divergences, next label 90.

**Probe.** `swiftui-shapes-and-rendering.swift`: revision 1 (68 lines, groups
P, S, F, K, C, O, I) was written by an interrupted first design pass and found
uncommitted; this pass re-ran it (stdout byte-identical to its header), then
added revision 2's separating arms — A1–A4 (`aspectRatio(nil)` on a
non-image), C8 (`clipShape` and layout), I11 (`.medium`), I12 (premultiplied
compositing), K11/K12 (a stroke wider than twice the radius) — and re-ran the
whole: compiled twice, interpreted once, byte-identical, 77 lines, screen
locked (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`). Readings
that decided rulings: K8 (an ellipse's `strokeBorder` is the inset ellipse's
stroke, 518 px from a concentric hole → exact distance in the shader, `TE-AE`);
K11/K12 (the outer corner rule, `TE-AI`); S3/C4 (continuous is the default and
differs from circular by 196 px → divergence 90); I8/I11 (only `.high` differs
from bilinear → divergence 93); A1–A4 (the nil ratio is the child's nil×nil
answer, `TE-AM`).

**Renderer inventory** (spec §2): `MUIRect` (circular rounded-rect SDF,
inside border, rounded mask, an unused `_reserved` word), `MUIGlyph` (R8
sprite); the SDL renderer draws the same bytes through `replay.hlsl`, its
compiled stages checked in and hash-checked in CI; parity is
`Experiments/SDLGPU`'s `Replay --portable --record` (Metal vs SDL-Metal live)
plus `PortableReplay --expect 6` and `DemoCapture` on Linux/Windows. Decided:
an ellipse kind in `_reserved` (stride unchanged) and an image primitive with
textures carried by the `Scene` (`WindowRenderer`'s signature unchanged),
frame 6 added to the parity set; every other effect a documented constraint
(`TE-AD`, spec §9).

**Collection** (`TE-AC`): `TE-O`'s table plus a re-grep; dispositions in spec
§3. Divergences planned: **90–93 added** (continuous corners drawn circular;
an ellipse clip traps; crossing rounded clips intersect as the square box;
`.high` drawn bilinear), **64 retired** (`UnitPoint` grid anchor), **47 kept**
(legacy `.cornerRadius` stays paint-only: making it clip would move hit
testing). Live count 65 → 68 if every lane lands.

**Lanes** (spec §8): 1 renderer (both), 2 shapes/fill/stroke/clip/backgrounds,
3 image/`aspectRatio(nil)`/grid anchor; run in order. Lock probe at design
time: locked, so the real-window capture is owed.
