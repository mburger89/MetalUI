# 20 — Grids (plan task 7, stage G)

Branch `feat/grids` from `cb2e708`. Spec
`docs/superpowers/specs/2026-09-17-grids-design.md`; rulings `GR-A`…`GR-V` in
`docs/superpowers/2026-09-17-grids-decisions.md`; probes
`docs/probes/swiftui-grid.swift` (revision 5), `docs/probes/swiftui-grid-corpus.txt`,
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
   | 12 | (critic round, revision 5, bare Spacers) at a non-nil proposal a span's shortfall goes first to the spanned columns still holding an unprocessed single-column cell | GZ5 476 → 482, GZ6 374 → 376, GZ8 657 → 662, arms 92 → 93 of 97 (GX9 now agrees); GZ1–GZ4 equal |

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

Computed by running the probe's `ModelGrid` and `Grid` on the same leaves (in
scratch at revision 4; GS4, GS5 and GX17's revision-5 rects by the committed
`model-arms` mode), at the arm's proposal:

| arm | model (the kernel's expected) | SwiftUI |
|---|---|---|
| GX17 at 200×100 | revision 5 (step 12): 200×100: a (0,36 30×10), b (38,0 134×82), c (180,31 20×20), x (25,90 150×10); revision 4 read a (14,36), b (66,0 78×82), c (166,31) | 284×100: a (0,36), b (38,0 218×82), c (264,31), x (67,90) |
| GS4 at 60×60 (revision 5, `model-arms`) | 45×40: a (0,0 15×10), c (15,15 30×20), s (0,10 15×30) | 90×40: a (0,0 30×10), c (30,15 60×20), s (0,10 30×30) |
| GS5 at 300×200 (revision 5, `model-arms`) | 164×136: a (48,0 40×40), b (34,63 68×10), c (144,48 20×40), d (53,96 30×40) | 76.67×136: a (4.33,0), b (12.17,63 24.33×10), c (56.67,48), d (9.33,96) |
| GX18 at 200×100 | 200×100: a (0,0 104×82), b (112,36 30×10), c (150,36 50×10), x (70,90 60×10) | 231.33×100: a (0,0 135.33×82), b (143.33,36), c (181.33,36), x (85.67,90) |
| GX19 at 200×100 (control) | 200×100: a (0,0 104×82), b (112,36), c (150,36), x (80,90 40×10) | identical |
| GX14 with `columns(0)` read as 1, at nil | 58×38: a (0,5 30×10), b (38,0 20×20), c (10,28 10×10), d (45.5,30.5 5×5) — also SwiftUI's answer for `columns(1)` | with `columns(0)`: c (0,28 10×10), d (12.5,30.5 5×5) |

### Probe runs

| probe | revision | commit | runs | result |
|---|---|---|---|---|
| `swiftui-grid.swift` | 1 | `ed3471e` | default ×2, `corpus` ×2, `trap-negative-columns` ×1 (a second run at revision 3) | byte-identical; exit 0, 0, 133 |
| `swiftui-grid.swift` | 2 (GS12–GS18) | `c1f793d` | default ×2 | byte-identical; every revision-1 line identical |
| `swiftui-grid.swift` | 3 (GP9–GP11, ∞ share in the model) | `01a3462` | default ×2, `corpus` ×1 | byte-identical; revision-2 lines identical; corpus sha256 unchanged |
| `swiftui-grid.swift` | 4 (GF14–GF18: a greedy frame and a Color as cells) | `ce84b8b` | default ×2 | byte-identical; revision-3 lines identical; corpus sha256 unchanged |
| `swiftui-grid.swift` | 5 (critic round: bare Spacers, step 12, GE, GN, GG10–GG16, GQ9–GQ10, GX20–GX23, GZ9–GZ12, three modes) | `beb4242`, `c0c499b`, `ea591cd` | default ×2 after each of the three commits' edits; `model-arms`, `classify-spans`, `corpus` ×2; `huge-columns` ×2; `trap-negative-columns` ×2 | byte-identical; exit 0 (default, three modes), 133 (`huge-columns`, `trap-negative-columns`); arm lines through GF18 identical to revision 4; corpus sha256 now `d93bc71a…a886f366` |
| `swiftui-lazy-grid-scope.swift` | 1 | `ed3471e` | ×2 | byte-identical |

All under `/usr/bin/swift` (Apple Swift 6.4, swiftlang-6.4.0.33.1), macOS 27.0
(26A428). Revisions 1–4's corpus stdout had sha256
`88e4e1ec9a545ce071418ac4381181f1e55f34d9831895bc23d746e1ca42ae78` (a 17-line
header); revision 5's is
`d93bc71acd09a1c745691e65460401d214f6c701bf70c7d0b2e52e2da886f366`, and the
committed file is a 22-line comment header followed by that stdout.

### Not done in the design round

No prototype of the kernel was written, so the spec's lane-1 depth gate, the
work literals' hits and misses, and every "existing tests that change" line are
predictions for the lanes to re-take. No demo images or real-window captures
were taken: the design changed no source file.

## Critic round (2026-09-17, design revision 2, probe revision 5)

A critic reviewed the design before any lane ran and returned fourteen findings;
`GR-Q` lists each and its disposition (all applied). What was measured:

### Bare Spacers (finding 1)

- The subview proxy's `priority` (probe GQ10): `Spacer()` −inf,
  `Spacer().layoutPriority(0)` 0.0, `.layoutPriority(1)` 1.0,
  `Spacer().background(Color)` −inf, `Spacer().gridCellColumns(1)` −inf, a
  `Color` 0.0. GS1 with `.layoutPriority(0)` on the Spacer (GQ9): 200×100, s
  152×62, against GS1's 190×80, s 142×42.
- The probe's generated cells now carry an attribute only where written
  (`WrittenAttributes`). Scratch, with bare Spacers and before step 12: GZ1
  1000, GZ2 988, GZ3 **469** (479 before), GZ4 441, GZ5 476, GZ6 374, GZ8 657;
  arms (`model-arms`, then 97 entries including GA5/GA6, which read nothing on
  both sides) 92 of 97. So the model agrees **less** with SwiftUI once
  its Spacers are bare.
- Corpus regenerated: 120 kept of 185 generated (65 skipped; revision 4: 120 of
  193, 73). 34 cases hold a Spacer, 5 of them with a written priority. 18 cases
  have no anchor, column alignment or unsized axis (revision 4's filter read
  19); one of them is at nil×nil.

### The model on the arms (finding 7)

`model-arms` transcribes 95 arms as `Case`s (GA5/GA6 dropped: an empty grid has
no subview to lay out, so the harness reads nothing), checks each SwiftUI answer
against the arm's recorded line (0 mismatches) and compares the model. Before
step 12: 92 agree; GS4, GS5, GX9, GX17, GX18 differ. The spec at `3981a4e` named
GS4, GS5 and GX9 as agreement arms (its tests 1.12, 1.14). Scratch sequence logs:

- GS4: SwiftUI proposes c 60×60 and then a 60×100 (the model: c 30×30, a
  30×40). With the Spacer replaced by a `.layoutPriority(-1)` flexible leaf
  (GS4d) SwiftUI proposes c 52×52 and a 52×84, so a column whose other cell has
  a lower priority does not count as open for c's group; with a 0×0 fixed leaf
  instead (GS4b) the shares are the model's (26). A (−1)-priority cell's row
  and column arithmetic for a (52×84) was not explained; no rule was tried
  against GZ3/GZ4, and none adopted.
- GS5: SwiftUI shares 292 over all three columns (97.33) in every group,
  although columns 1 and 2 hold only a span; the model opens only column 0.
  Variant 6 (such columns always open, never committed) fixes it and GZ6 (374 →
  410) but lowers GZ8 (657 → 646); not adopted.
- GX9: SwiftUI's b is proposed 262 because x's shortfall went to b's open
  column; step 12 (above) adopted. Variants measured in one scratch run (bare
  Spacers): variant 5 (step 12) GZ1 1000, GZ2 988, GZ3 469, GZ4 441, GZ5 482,
  GZ6 376, GZ8 662, arms 93; variant 6 GZ5 476, GZ6 410, GZ8 646, arms 93;
  both together crashed the probe in GZ2 (not investigated, not adopted).

After step 12: 91 of 95 agree (GS4, GS5, GX17, GX18 differ).

### Spans (finding 4)

`classify-spans`, GZ6's seed at revision 5, 124 disagreements: overflow symptom
(SwiftUI wider than a finite proposal, the model within) 3; the model wider 64
(nil×nil 1, nil width 1, nil height 12, finite 50); SwiftUI wider without the
overflow 31 (nil height 7, finite 24); equal sizes, different rects 26 (nil
width 1, nil height 8, finite 17). Agreeing under variant 4 alone 18, variant 6
alone 16, either 26, variant 1 1, none 63.

### A grid in a stack (finding 3)

GE1–GE30 and GZ9–GZ12, read in `GR-R`. The scratch reading that drove GE29/GE30:
with the plan built at the grid's registration, an enclosing stack's marks
cannot change the grid's own gaps (GE12–GE15 are equal to their controls by
construction), so the only observable of `markSpacers` stopping is a grid's
Spacer edge seen through a stack across the outer one.

### Column counts (finding 13)

`huge-columns`: GX21 (100_000) clamps, GX22 (1 << 40) reads as `columns(0)`,
GX20 (Int.max) traps. Scratch, one process per value: `Int.max / 2` exit 133,
`Int.max − 1` exit 133, `1 << 40` laid out, `100_000` laid out. Scratch H1–H5
(H1 committed as GX23): `[a, b] [x 100×10 span 3]` answers 100×38 with a at 0
and b at 38 — the third column takes the shortfall — where span 2 (H3) gives
51/41; span 100_000 (H2) lays out as H1; at 300×100 (H5) b is proposed 97.33
(292 / 3 columns), GS5's reading again.

### Nested rows, row attributes, Text (findings 8, 13)

GG10–GG16 and GN1–GN10, read in `GR-T` and `GR-V`.

### Not done in the critic round

No source, test or demo image changed; the lanes' counts, work literals, the
bookkeeping literal of `GR-U` and the depth ceiling are still predictions.

## For the integrator

(Written by lane 4; see spec §6, lane 4.)
