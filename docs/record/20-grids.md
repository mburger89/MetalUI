# 20 — Grids (plan task 7, stage G)

Branch `feat/grids` from `cb2e708`. Spec
`docs/superpowers/specs/2026-09-17-grids-design.md`; rulings `GR-A`…`GR-P` in
`docs/superpowers/2026-09-17-grids-decisions.md`; probes
`docs/probes/swiftui-grid.swift` (revision 4), `docs/probes/swiftui-grid-corpus.txt`,
`docs/probes/swiftui-lazy-grid-scope.swift`. The lanes append their sections
below the design round.

## Design round (2026-09-17)

### Baseline

At `cb2e708` in this worktree: `swift build --build-system native
--build-tests` (27.35 s), `swift test --build-system native --no-parallel` →
`Test run with 1409 tests in 1 suite passed after 42.821 seconds`; 0 `error:`;
the only `warning:` is SwiftPM's deprecation notice. Guards: 73 `canTypecheck`
hits across the thirteen guard files and `Typecheck.swift`, less the
declaration and `UnitSafetyTests`' comment = 71. Goldens 97. No `Sources/` or
`Tests/` file was changed by the design round.

### How the probe was built

1. **Exploration** (scratch, not committed): a copy of the containers probe's
   harness with grid arms E1–E19, then a sequence-logging leaf (every
   measurement in order) on the arms whose answers a column-by-column stack
   model could not explain (E10b, E11, E13, V1–V14, F1–F18, S1–S9, P1–P4,
   U1–U6, A1–A9, I1–I10, J1–J10). The committed probe re-spells the arms the
   rulings rest on under GA–GG ids.
2. **A reference model fitted against generated grids.** A SwiftUI `Layout`
   over the same leaves, compared rect for rect with `Grid`. Each refinement
   was kept only if the group it aimed at rose; the plain group was re-run
   after steps 3–10 and stayed at 300/300 or 1000/1000:

   | step | change | measured |
   |---|---|---|
   | 1 | cells measured at 0×0/∞×∞, groups by summed flexibility, shares over uncommitted columns, placement-proposal reuse | plain 258/300 |
   | 2 | flexibility over proposal-finite axes only, clamped to the proposal | plain 287/300 |
   | 3 | key = (infinite-axis count, finite sum), unclamped | plain 300/300, then 1000/1000 on a second seed; fulls 473/500; spans 349/500; prios 351/500 |
   | 4 | spanning cells do not block a column's commit | fulls 484/500 |
   | 5 | a span is proposed W′ minus the outside columns | fulls 491/500 |
   | 6 | priority levels: open counts per level, commits over priority ≥ level | prios 391/500, then 407/500 once a lower-priority column outside a span counts at its current width |
   | 7 | a span-1 cell keeps `max(share, current width)`; only spans use W′ − outside | prios 445/500 |
   | 8 | a gap exists only where a cell starts; span shortfall to columns with no single-column cell first | spans 370/500 (nil proposals 296/300) |
   | 9 | per-boundary pair spacing, 0 beside a Spacer | spacers 347 → 479/500 |
   | 10 | unsized-axis variants (seed 31, 400 grids with attributes): axis excluded from the key 374 (either grouping); included but unsized sorted after sized 398; **included, same group 400** | adopted the last (`GR-H`) |
   | 11 | ∞ share on an infinite proposal axis (GP9–GP11) | GZ7 unchanged at 222/300; every other output line identical |

   The committed probe's GZ group re-runs the final model on fresh seeds
   (101–109), which is what `GR-B` cites.
3. **The span overflow** (`GR-F`), measured before it was ruled out. Grid
   `[a flexible, b width 10…30, c width 20…50]` plus a fixed non-row child of
   width F, at 200×100 (scratch arms); the proposal SwiftUI gave c, then a:

   | F | c | a | answer |
   |---|---|---|---|
   | 0…46 | 77 | 104 | 200 |
   | 50…76 | 92.67 | 135.33 | 231.33 |
   | 78 | 93 | 136 | 232 |
   | 80 | 94 | 138 | 234 |
   | 100 | 104 | 158 | 254 |
   | 184 | 146 | 242 | 338 |

   With b's high 60 (b then served after c): F ≤ 60 no change; F = 80, 100,
   140, 184 put +7, +17, +37, +59 on b and twice that on a. Above the plateau
   the extra on the next column is half of (F − 16 − the first committed
   column's width), and the last column gets it twice: the shortfall is not
   reduced when the second spanned column commits. The 50…76 plateau in the
   first series has no counterpart in the second. No rule was found that fits
   both series without a double count, and the grid answers wider than its
   proposal for content that fits. Not ported.
4. **Validation.** Negative spacing −10/−5 answered 60×45; +∞ spacing inf;
   nan spacing nan; `gridCellColumns(0)` laid out (GX14); `gridCellColumns(-1)`
   killed the process (exit 133, `swift-frontend` stack dump), which is why GT1
   runs only under its own argument.
5. **Lazy grids** (`GR-L`): LZ0–LZ7, one run pair.

### Model answers the spec pins where SwiftUI's differ

Computed by running the probe's `ModelGrid` and `Grid` on the same leaves in
scratch (the probe's `host`, `modelGrid`, `realGrid`), at the arm's proposal:

| arm | model (the kernel's expected) | SwiftUI |
|---|---|---|
| GX17 at 200×100 | 200×100: a (14,36 30×10), b (66,0 78×82), c (166,31 20×20), x (25,90 150×10) | 284×100: a (0,36), b (38,0 218×82), c (264,31), x (67,90) |
| GX18 at 200×100 | 200×100: a (0,0 104×82), b (112,36 30×10), c (150,36 50×10), x (70,90 60×10) | 231.33×100: a (0,0 135.33×82), b (143.33,36), c (181.33,36), x (85.67,90) |
| GX19 at 200×100 (control) | 200×100: a (0,0 104×82), b (112,36), c (150,36), x (80,90 40×10) | identical |
| GX14 with `columns(0)` read as 1, at nil | 58×38: a (0,5 30×10), b (38,0 20×20), c (10,28 10×10), d (45.5,30.5 5×5) — also SwiftUI's answer for `columns(1)` | with `columns(0)`: c (0,28 10×10), d (12.5,30.5 5×5) |

### Probe runs

| probe | revision | commit | runs | result |
|---|---|---|---|---|
| `swiftui-grid.swift` | 1 | `ed3471e` | default ×2, `corpus` ×2, `trap-negative-columns` ×1 (a second run at revision 3) | byte-identical; exit 0, 0, 133 |
| `swiftui-grid.swift` | 2 (GS12–GS18) | `c1f793d` | default ×2 | byte-identical; every revision-1 line identical |
| `swiftui-grid.swift` | 3 (GP9–GP11, ∞ share in the model) | `01a3462` | default ×2, `corpus` ×1 | byte-identical; revision-2 lines identical; corpus sha256 unchanged |
| `swiftui-grid.swift` | 4 (GF14–GF18: a greedy frame and a Color as cells) | the commit after `88d0472` | default ×2 | byte-identical; revision-3 lines identical; corpus sha256 unchanged |
| `swiftui-lazy-grid-scope.swift` | 1 | `ed3471e` | ×2 | byte-identical |

All under `/usr/bin/swift` (Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0
(26A428). The corpus stdout's sha256 is
`88e4e1ec9a545ce071418ac4381181f1e55f34d9831895bc23d746e1ca42ae78`; the committed
file is a 17-line comment header followed by that stdout.

### Not done in the design round

No prototype of the kernel was written, so the spec's lane-1 depth gate, the
work literals' hits and misses, and every "existing tests that change" line are
predictions for the lanes to re-take. No demo images or real-window captures
were taken: the design changed no source file.

## For the integrator

(Written by lane 4; see spec §6, lane 4.)
