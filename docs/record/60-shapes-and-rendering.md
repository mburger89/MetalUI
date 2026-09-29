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

## §2 Critic round (2026-09-29)

Attacked the committed design (`08499e0`); ruling `TE-AQ`, next unused
`TE-AR`. **Re-runs**: the probe's revision 2 compiled and run unchanged, all
77 lines byte-identical to its header; `swiftui-grid.swift` compiled `-O`,
GL14's line byte-identical (the design had only re-read it). **O4 was not
separating** (white on white): revision 3 adds O6 over a red canvas with a
blue control — `background(in:)` paints (white, 5968 px), so `TE-AK`'s token
fill stands and its evidence is amended as an erratum; revision 3 re-ran
compiled twice and interpreted once, byte-identical, 78 lines. Lock probe
00:31 PDT: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` — the
real-window capture stays owed.

**Fixed in the spec** (`TE-AQ` items 1–12): `Shape` refines
`ProposalElement, Sendable` with default phase implementations (a
`Shape: Element` outside conformer could neither compile from `geometry(in:)`
alone nor sit in an `HStack`); `Rectangle.color` becomes `ColorToken?`, a
ruled public break with its migration; the legacy `clipShape` is
`<S: Shape & Hashable>` because `Decoration` is `Sendable, Hashable`; a clip's
hitbox clipping is stated as MetalUI's rule (square, `activeClip`), owner
plan task 12, no number (unmeasured); the ellipse distance is the trig-free
three-iteration method on both shader languages (loose transcendental
precision on Vulkan/D3D); the `MUIRect._reserved` rename's memberwise call
sites are listed for lane 1; `Image`'s `scale: Float` and missing
`orientation:` ruled; three stale "task 11" source comments assigned to lanes
2 and 3; 3.10/2.20 are single `@Test`s; the new `intersect` case runs after
the existing two. **Rejected**: splitting lane 1, replacing `intersect`'s
case 2, numbering an unmeasured hit-testing divergence (reasons in `TE-AQ`).
