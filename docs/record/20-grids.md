# 20 — Grids (plan task 7, stage G)

Branch `feat/grids` from `cb2e708`. Spec
`docs/superpowers/specs/2026-09-17-grids-design.md`; rulings `GR-A`…`GR-X` in
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

## Lane 1 — the plan and the nil proposal (2026-09-17)

Commits: `432cb3d` (tests, red: does not compile), `82a63fe` (implementation),
then this record with `GR-W` and the spec's amended rows.

### Red first

`432cb3d` after `swift package clean`, native build: the test target does not
compile, 23 errors, all absent API — `value of type 'LayoutTree' has no member
'newNativeGrid'` (`NativeGridTests.swift:101`, `NativeGridWorkTests.swift:47`,
`NativeGridTrapTests.swift:46`, `:59`, `:72`, `:117`,
`NativeDepthGuardTests.swift:152`, `:172`, `NativeBoundaryTrapTests.swift:112`,
`NativeGridTests.swift:756`), `… 'markNativeGridRow'`
(`NativeGridTests.swift:95`, `:594`, `:604`, `:630`, `:751`;
`NativeGridWorkTests.swift:45`, `:46`; `NativeGridTrapTests.swift:87`), `…
'markNativeGridCell'` (`NativeGridTests.swift:83`; `NativeGridTrapTests.swift:31`,
`:101`), `cannot find type 'NativeGridPlan' in scope` and `… 'nativeGridPlan'`
(`NativeGridTests.swift:139`). One test-helper defect was fixed before the
commit: `Arm.grid(_ name: String = "grid", …, _ children:)` bound an unlabeled
children array to `name` (43 conversion errors). The work literals of 1.12
(7 leaf calls, 5 hits, 8 misses) were derived by hand in its doc comment
before the first run and matched it. Every lane-1 test passed on the first
green build.

### As built

- `Sources/MetalUILayout/NativeGrid.swift`: `ProposalAxes`; `NativeGridChild`,
  `NativeGridCell`, `NativeGridEdges`; `NativeGridPlan` (a `final class`);
  `makeNativeGridPlan` (rows, spans, indexes, gaps: one pass per row, one
  interval merge per row boundary); `solveNativeGrid` (nil×nil; any other
  proposal is `preconditionFailure("grids lane 2: …")`); `nativeGridCellRects`;
  `nativeGridZeroSpacingEdges`.
- `LayoutTree.swift`: `gridRowTokens`, `gridRowAlignments`, `gridCellColumns`
  and `nextGridRowToken` after `nativeParents`; three clearing lines at the end
  of `reset`; `case grid(NativeGridPlan)` last; `.grid` arms last in
  `measureNative`, `placeNative`, `markSpacers` (stop), `zeroSpacingEdges`
  (positional over the plan's stored edges); `nativeLayoutPriority` left to its
  `default` (0) for lane 2's explicit arm. One extension at the end:
  `markNativeGridRow`, `markNativeGridCell(_:columns:)`, `newNativeGrid`,
  `nativeGridPlan(_:)` (test observable), `measureGrid`, `placeGrid`. Doc
  comments updated: "eleven built-ins" → twelve, `markSpacers`' and
  `zeroSpacingEdges`' lists gain the grid, `maxDepth`'s table a dated re-take.
- `Sources/MetalUI/Grid.swift`: the three `LayoutPass` registrars.
- Tests: `NativeGridTests.swift` (1.1–1.11, 1.13), `NativeGridWorkTests.swift`
  (1.12), `NativeGridTrapTests.swift` (1.14–1.20, plain import),
  `NativeDepthGuardTests.swift` (1.21, 1.22 appended),
  `everyNativeRegistrarAcceptsNativeChildrenWithoutTrapping` 26 → 29 nodes.

### Suite

`swift package clean`, `swift build --build-system native --build-tests` (0
`error:`, only SwiftPM's deprecation `warning:`), `swift test --build-system
native --no-parallel` unfiltered: **`Test run with 1431 tests in 1 suite passed
after 45.894 seconds`** (1409 + 22, as spec §7). Goldens 97; guards 71 (73
`canTypecheck` hits less the declaration and the comment).

### Depth gate (`GR-W` item 2)

Method: a scratch test (never committed) building N nested nodes over a 10×10
leaf and laying them out on a `Thread` with a 1 MB stack, `maxDepth`
temporarily 100 000, one `swift test --build-system native --skip-build
--filter` per depth, bisected between 50 and 600; each first failing depth
re-run on 4 MB completes. Stack and padding at 400×400, grids at nil×nil.

| build | padding | vertical stack | one-cell grid |
|---|---|---|---|
| `cb2e708` (`git archive` in scratch) | 197 / 198 | **128 / 129** | — |
| first grid: solver measures through `Array.map`, plan bound in the arms | — | 126 / 127 | **110 / 111** (measurement-only 117 after `map` → loop) |
| nil cells measured in `measureGrid`, plan a struct, plan bound in the arms | 192 / 193 | 126 / 127 | 170 / 171 |
| … arms pass the id, plan a struct | 193 / 194 | 127 / 128 | 164 / 165 |
| **as committed**: arms pass the id, plan a class | 194 / 195 | **127 / 128** | **170 / 171** |

Measurement-only and full layout gave the same grid ceiling (170). The gate
(≥ 147) passes. **Finding**: the stack reads 128 at `cb2e708` where the table
(2026-09-14) reads 151, so `SA-L`'s rule gives 72, not 88, before any grid
code; not changed here (owner: `LR-Q`'s stage 6b re-bisection).

### Mutations

Each applied after `82a63fe` from a copy, `git status --short` showing only the
mutated file during and nothing after, then the full native suite
(1431 each). Tests reddened, and the figure where the spec asked for one:

| # | mutation | reddened |
|---|---|---|
| M1.1 | column width from its first single-column cell | 1.1 (GA1 58×58, b at 38), 1.3, 1.6, 1.7, 1.8, 1.9, 1.10, 1.12 |
| M1.2 | group by token equality including nil | 1.2 (GA8 38×20), 1.13 |
| M1.3 | absorb each span in source order among the single-column cells | 1.3 (GX7 a at 8, b at 67), 1.4 |
| M1.4 | spread a shortfall over every spanned column | 1.4 (d at 25, e at 88) |
| M1.5 | always place at the slot | 1.5 (GR1 a 15×15 at (3, 3) rounded), 1.12, 1.22 (a child grid proposed its 10×10 slot reaches lane 2's trap) |
| M1.6 | `platformDefault` before every column ≥ 1 | 1.6 (GS2 = GS3 = [0, 8, 8]: its `#require` stops the test before GS6), 1.3, 1.4, 1.7, 1.10, 1.11 |
| M1.7 | clamp a given spacing at 0 | 1.7 (GS8 70×50) |
| M1.8 | ignore the row alignment | 1.8 (GL3 a at y 5), 1.9 |
| M1.9a | rows by alignment, not token | 1.1, 1.3–1.10, 1.12 (adjacent rows 124×30) |
| M1.9b | keep the inner alignment when the enclosing mark's is nil | 1.9 (GG12 a at y 20) |
| M1.10a | edges from any cell | 1.10 (GE3 68×20, GE24 30×48), 1.11 |
| M1.10b | neither edge | 1.10 (GE1 84×20), 1.11 |
| M1.11 | `markSpacers` walks into a grid | 1.10 (GE25 60×20, GE26 96×20), 1.11 (GE29 68×20, grid 20×20) |
| M1.12 | also measure every cell at its slot | 1.12 (8 calls, 8 hits, 9 misses), 1.5, 1.22 |
| M1.13 | `reset` keeps the row tokens | 1.13 (68×10) |
| M1.14 | drop the negative-columns precondition | 1.14 |
| M1.15 | drop the grid's legacy-child check | 1.15 |
| M1.16 | drop the `horizontalSpacing` check | 1.16 |
| M1.17 | drop the `verticalSpacing` check | 1.17 |
| M1.18 | drop `markNativeGridRow`'s parent check | 1.18 |
| M1.19 | drop `markNativeGridCell`'s parent check | 1.19 |
| M1.20 | skip `recordParent` in `newNativeGrid` | 1.20 |
| M1.21 | `maxDepth` 89 | 1.21, `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` |
| M1.22 | `maxDepth` 87 | 1.22, `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` |

No mutation above left the suite green; the verifier's round (below) found
three that did.

### Demo

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`) in
`git archive`s of `cb2e708` and `82a63fe`: **12 of 12 images 0 differing
pixels, scenes identical.** Controls on the head images: light vs dark f0
1 048 576; vs modal-light 1 030 498; vs animation-light 210 027; f0 vs f3 0;
preview light vs dark 1 048 576 (stage 1's figures). `grep -rn "Grid\b"
Sources/MetalUIDemoContent Sources/MetalUIDemo`: no hits. No real window was
captured (lane 4's).

### For lane 2

- The GE rects of 1.10/1.11 are 2.11's (`GR-W`).
- `solveNativeGrid`'s finite branch puts the solver back on the measurement
  recursion path: keep its frame small and re-bisect against 147.
- `nativeLayoutPriority` has no `.grid` arm yet (its `default` returns 0).

### Verifier round (lane 1)

The verifier re-took the suite (1431), goldens (97, `git diff cb2e708 --
'*.json'` empty), guards (71), the probe, the offscreen demo (0 px in 12) and
the depth table, all matching the above, and ran mutations V1–V16 plus re-runs
of M1.1, M1.5, M1.13, M1.15 and M1.21. Three stayed green:

- **V1, `reset` no longer clears `gridCellColumns` (major, fixed).** A stale
  span on a reused index is read by `newNativeGrid`, and
  `markNativeGridCell(_:columns: nil)` writes nothing over it. New test
  `resetClearsGridCellColumnMarks` (`NativeGridTests.swift`, after 1.13): a
  100×10 leaf at an index marked `columns: 2` before the reset, one-cell row
  over a row of two 30×10 cells, answers 138×28; its control, marked in
  generation 2, answers 100×28, and a `#require` makes the arms disagree first.
  Committed, then V1 applied from a copy (`git status --short` showing only
  `LayoutTree.swift`): full native suite **1432, 1 issue, reddening only
  `resetClearsGridCellColumnMarks`** (at its `#require`, 100×28 on both arms).
  Restored, status clean, **1432 passed**. Clearing `gridRowAlignments` stays
  unpinned and is equivalent: an alignment is read only with a token, and
  every row mark rewrites both.
- **V2 / V2b, `LayoutPass.requestNativeGrid` passes `.center` / `markNativeGridRow`
  passes `alignment: nil` (minor, deferred to lane 4).** No test calls the three
  `LayoutPass` registrars in `Sources/MetalUI/Grid.swift`; see "For lane 4".

### For lane 4

- Pin each `LayoutPass` registrar's forwarding through the element tests (V2,
  V2b): a non-centre grid alignment, a row alignment, and a column span, each
  reached through `LayoutPass`, with a mutation dropping the forwarding.

## Lane 2 — the finite solve (2026-09-17)

Commits: `e4f95ff` (tests 2.1–2.14 and `GridCorpus.swift`, red: does not
compile), `ea0a51b` (a first finite branch in the model's shape; 2.14 red;
GE10/GE19 pinned; probe `swiftui-grid-stack-ties.swift`), `d467058` (indexed
bookkeeping, the `.grid` priority arm), `0196743` (`NativeGridSolver` inverted
for the depth guard), `de0a51e` (2.3's logs, 2.12's substituted mutation), then
this record with `GR-X` and the spec's amended rows.

### Red first

`e4f95ff`, native build: the test target does not compile, 7 errors, all
`value of type 'NativeGridSolution' has no member 'bookkeepingSteps'`
(`NativeGridWorkTests.swift:153:17`, `:153:68`, `:154:17`, `:154:68`, `:155:17`,
`:155:44`, `:156:28`). One test-helper defect was fixed before the commit: three
locals shadowed their helper functions (`let gf12 = gf12(nil)`, `let gs1 = gs1
{ … }`; `cannot call value of non-function type 'Arm'` at
`NativeGridTests.swift:1002:34`, `:1178:15`, `:1182:15`). With 2.14 compiled out
(scratch, not committed), each other new test run alone against lane 1's branch:
2.1, 2.2, 2.3, 2.5–2.13 died with `NativeGrid.swift:217: Fatal error: grids lane 2:
a grid solved at a non-nil proposal ProposedSize(width: Optional(200.0), height:
Optional(200.0))` (the proposal each first reached: 200×200 for 2.1 and 2.12,
200×100 for 2.2, 2.6, 2.7, 2.9, 200 × nil for 2.3, 100×100 for 2.5, 300×100 for
2.8, **∞ × 100** for 2.10 and 2.11 — a stack's flexibility probe — and 300×200 for
2.13); 2.4 recorded `expected exit status ".success", but ".signal(SIGTRAP)" was
reported instead`.

**The scanning branch** (`ea0a51b`, every open count and commit check a scan of
every cell, span targets likewise): suite `Test run with 1446 tests in 1 suite
failed … with 3 issues`, all in 2.14: `two.bookkeepingSteps → 424331` (literal
2203), `one.bookkeepingSteps → 107181` (1103), difference 209969 (≤ 3). Every
other lane-2 test passed on that branch, so two independent ports of the model
(scan and index) agree on 2.1–2.13.

### A finding on arrival: GE10 and GE19 (`GR-X` item 1)

The first green run of 2.10/2.11 read GE10 a (0,0 46×100), c (54,0 38×100), d
(100,45) and GE19 stack 200×112, z 46, a (0,54 152×20): SwiftUI reads a 36 and z
34. Derivation (GE19): the `VStack`'s two children tie at flexibility ∞ (z ∞ − 0,
the grid ∞ − 58), `CN-B` serves z first at (100 − 8)/2 = 46, and the grid answers
58 to 200×46 (group [b, c, d] shares 19, heights 20 and 30; a's share 8, kept at
20). Probe `docs/probes/swiftui-grid-stack-ties.swift` (new; exit 0 twice,
byte-identical): T0 control b 40 / a 52 (order can move); T1 = GE10, a 36; T7
`VStack{z flexible; b height ≥ 58}` with **no grid**, z 34; T2–T5, T8 do not
discriminate. Pinned at the kernel's figures, with a kernel T7 arm in 2.11 (z 46,
stack 112). Not fixed: the stack is shared and not this track's (`GR-O` 8).

### As built

- `NativeGrid.swift`: `NativeGridSolution.bookkeepingSteps`; `solveNativeGrid`'s
  non-nil branch drives `NativeGridSolver` (a `final class`: probes, key sort,
  groups, shares from a level's per-column and per-row counts filled once and
  decremented after each group, step-12 targets from each column's unprocessed
  single-column count, commit checks over the first group's every column and row
  and later groups' own cells, committed widths and heights as running sums).
- `LayoutTree.swift`: `measureGrid` hands a non-nil proposal to
  `measureGrid(_:atAProposal:)`, which feeds the solver from its own loop; an
  explicit `.grid` arm returning 0 in `nativeLayoutPriority` (and its doc list);
  doc comments of `newNativeGrid` and `measureGrid` updated.
- `NativeLayoutRun.swift`: `maxDepth`'s table gains lane 2's re-take (88
  unchanged). `NativeDepthGuardTests.swift`: a stale comment ("the finite branch
  is lane 2's") updated.
- Tests: `NativeGridTests.swift` (2.1–2.11, 2.13, helpers `fw`, `prio`,
  `expectRects`), `NativeGridWorkTests.swift` (2.12, 2.14), `GridCorpus.swift`
  (the corpus file below its own header, verbatim: `diff` of the extracted range
  against `docs/probes/swiftui-grid-corpus.txt` is empty; 120 cases, 18 after
  lane 2's filter, every one passing).

### Suite

`swift package clean`, `swift build --build-system native --build-tests` (0
`error:`, only SwiftPM's deprecation `warning:`), `swift test --build-system
native --no-parallel` unfiltered: **`Test run with 1446 tests in 1 suite passed
after 59.500 seconds`** (1432 + 14). Goldens 97 (`git diff cb2e708 -- '*.json'`
empty); guards 71 (73 `canTypecheck` hits).

### Depth (`GR-X` item 2)

Lane 1's method: a scratch test (never committed) nesting N nodes over a leaf
answering min(proposal, 10), laid out at 400×400 (or nil×nil) on a 1 MB `Thread`,
`maxDepth` temporarily 100 000, one `swift test --skip-build --filter` per depth,
bisected in 50…600; each first failing depth completes on 4 MB.

| build | one-cell grid, 400×400 | one-cell grid, nil×nil | vertical stack | padding |
|---|---|---|---|---|
| lane 1 (record above) | — | 170 / 171 | 127 / 128 | 194 / 195 |
| indexed solver calling its measure closure from the group loop (`d467058`) | **65 / 66** | — | 127 / 128 | 194 / 195 |
| `NativeGridSolver` inverted, loop inline in `measureGrid` | 159 / 160 | 159 / 160 | 127 / 128 | 194 / 195 |
| **as committed** (`0196743`): loop in `measureGrid(_:atAProposal:)` | **155 / 156** (re-taken twice) | **167 / 168** | 127 / 128 | 194 / 195 |

Both grid ceilings clear 147. `maxDepth` restored to 88 and the scratch test
deleted before the suite (`git status --short` clean).

### Mutations

M2.1–M2.15 and the first M2.3 applied at `0196743`; the second M2.3 and M2.12s
at `de0a51e` (which changed only 2.3 and 2.12's doc comment). Each from a copy, `git status --short` showing only
the mutated file during and nothing after, then the full native suite (1446).
Tests reddened:

| # | mutation | reddened |
|---|---|---|
| M2.1 | GZ0's control: every group offered W′/ncols, commits ignored | 2.1 (GP2 a 96×62), 2.2, 2.3, 2.5, 2.6, 2.7 (GS1 s 96×42), 2.8, 2.9, 2.10, 2.11 (GE17 a (104,0 44×62), b at 166), 2.12, 2.13 (**4 of the 18** cases), 2.14 — 157 issues |
| M2.2 | key = the finite sum with ∞ as +∞ (one group for equal sums) | 2.2 (GF10 b 96 wide), 2.11 — 6 issues |
| M2.3 | a nil grid axis proposed as 0 | at `0196743`, before 2.3's logs: **2.13 only**, 4 issues (2.3 green); at `de0a51e`: 2.3 (GP5, GP6 logs), 2.13 — 6 issues |
| M2.4 | `(W′ − committed) / open` on an infinite axis | 2.4 (child `.signal(SIGTRAP)`), then the suite **truncates** (no summary line): 2.10's `HStack` probes a grid at ∞ × 100 after an infinite column committed, `native layout received a NaN proposal … (SA-J)` |
| M2.5 | reserve lower groups' 0×0 widths (as `CN-B`) | 2.5 (GQ2 a and c 27), 2.9, 2.10, 2.13 (1 case) — 27 issues |
| M2.6 | a cell's priority read as 0 (in the plan) | 2.5, 2.6 (GS1 s 152×62, `#require` GS1 ≠ GQ9 fails), 2.7, 2.9, 2.10, 2.11, 2.13 (3 cases) — 52 issues |
| M2.7 | no gaps subtracted from W′ and H′ | 2.1, 2.2, 2.3, 2.5, 2.6, 2.7 (GS1 b (168,15), c (70,58)), 2.8, 2.9, 2.10, 2.11, 2.12, 2.13 (3 cases), 2.14 — 180 issues |
| M2.8a | a span proposed the sum of its columns' shares plus inner gaps (variant 2) | 2.8 (GX10 x 58 wide) — 8 issues |
| M2.8b | step 12 dropped | 2.8 (GX9 b (69,0 231×82), a at 16), 2.9 (GX17 revision 4's b 78 at 66) — 5 issues |
| M2.9 | no span shortfall at a non-nil proposal | 2.8 (GX10 x 58), 2.9 (GS5 a at 53, b 73 wide) — 16 issues |
| M2.10 | `.grid` priority passes a one-cell grid's child's | 2.10 (`#require` GE8 ≠ GE27 fails) — 1 issue |
| M2.12 | (the spec's) re-measure every cell at its slot | 1.5, 1.12, 2.1, 2.9, 2.13 — **not 2.12** (`GR-X` item 5) |
| M2.12s | (substituted) also measure every cell at nil×nil first | 2.1, 2.3, 2.4, 2.12 (GP1 20 calls / 12 hits / 21 misses; GP2 19 / 13 / 20) — 9 issues |
| M2.14 | the commit check also scans every cell (counted) | 2.14 only — 3 issues |
| M2.15 | (shared file, not grid-owned) the stack serves the larger answer at 0 first on an infinite flexibility tie | 2.10 (GE10 a 36, c at 44, d at 90), 2.11 (GE19 z 34, stack 100; T7 z 34) — 12 issues |

No mutation left the lane's named test green except M2.3 before its fix and the
spec's M2.12; both are recorded in `GR-X`.

### Demo

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and `de0a51e`:
**12 of 12 images 0 differing pixels, scenes identical.** Controls on the head
images: light vs dark f0 1 048 576; default vs modal (light) 1 030 498; default vs
animation (light) 210 027; f0 vs f3 0; preview light vs dark 1 048 576 (lane 1's
figures). `grep -rn "Grid\b" Sources/MetalUIDemoContent Sources/MetalUIDemo`: no
hits. No real window was captured (lane 4's, `GR-M`).

### For lane 3

- The corpus filter in 2.13 is the only line to drop; the unsized-axis and
  anchor rules enter `NativeGridSolver.serve` (width/height proposals) and
  `nativeGridCellRects` (factors).
- `NativeGridSolver` must stay inverted: any measurement from inside it puts its
  frame on the recursion path (65 levels). Re-bisect after lane 3's changes.
- A stack's infinite-flexibility tie (`GR-O` 8) will move any corpus or arm with
  a grid beside a flexible sibling; none of lane 3's arms has one.

## Second critic round (2026-09-17, after lane 2, probe revision 6)

The design and lanes 1–2 as built were reviewed a second time, in the worktree
at `cdd9209`. **Fifteen findings, all fifteen applied** (`GR-Y` has the table;
`GR-Z`…`GR-AF` are the new rulings). What was measured, in order.

### What the reviewer verified, and what it left standing

Suite 1446, exit 0, only SwiftPM's deprecation `warning:`; goldens 97 and `git
diff cb2e708 -- '*.json'` empty; 73 `canTypecheck` hits (71 guards). Both probes
re-run twice: `swiftui-grid.swift`'s default run byte-identical run to run and
its `model-arms` block byte-identical to the header's recorded lines 736–841;
`swiftui-grid-stack-ties.swift` byte-identical twice, T7 reproducing `z 34` with
no grid.

### Probe revision 6 (`1844256`)

- **The default run's stdout is committed** (finding 14):
  `docs/probes/swiftui-grid-default-run.txt`, 435 lines of stdout under an
  18-line header, sha256 `5d2030386ae93bba614ff68f203e8d56a1bf284bad9912232f261088172f61ba`
  (`tail -n +19 … | shasum -a 256`), run twice, byte-identical.
- **`divergences`** (finding 3): the same generator, seed 4242 and budget as
  `corpus`, printing the cases that run discards. Output: `65 printed of 185
  generated; 120 agree`, exactly the corpus's own trailer, sha256
  `36021ffc…8c9bdaf8`, twice, byte-identical →
  `docs/probes/swiftui-grid-divergences.txt`.
- **`span-row <n>`, arm GX24** (finding 8): one row of two cells each
  `gridCellColumns(n)`, so a row's **sum** is 2n — the shape ruling `GR-S` traps
  above `Int32.max` and no arm had. Each run alone, `/usr/bin/time -l`:

  | n | row sum | answer | real | max RSS |
  |---|---|---|---|---|
  | 3 | 6 | 71×38 | ~1 s | — |
  | 100_000 | 200_000 | 71×38 | ~1 s | — |
  | 1_000_000 | 2_000_000 | 71×38 | 7.0 s | 1.38 GB |
  | 10_000_000 | 20_000_000 | 71×38 | 31.5 s | 5.95 GB |

  The answer never moves (three real columns, the rest empty), so SwiftUI
  **honours a row sum**, at ≈300 bytes and ≈1.5 µs per column. `Int32.max`
  would be ≈640 GB: SwiftUI's ceiling above 10⁷ is allocation, not a check, and
  cannot be probed — the run cannot be made. Test 3.6 arm (c) ships on that,
  and the allocation ceiling becomes divergence `GR-O` item 10 (`GR-AB`).
- **Additive, checked:** after the edit the default run is byte-identical to
  revision 5's (`cmp` against the pre-edit capture, twice, including after the
  reading's prose fix) and the `corpus` mode's sha256 is still
  `d93bc71a…a886f366`.

### Code (`1b6c698`): suite 1446 → **1449**, goldens 97, guards 71

- **Finding 1, the span clamp.** `Swift.min(span(child), columnCount − column)`
  is unreachable: `columnCount` is the largest row sum of spans, so within a row
  `columnCount − column` ≥ the rest of that row's spans ≥ this cell's. Deleted,
  with the proof in the source (`GR-Z`). No mutation can redden it — that is the
  finding — so the texts that called clamping a probed rule were restated
  instead: spec §4.1, `GR-F`, `GR-S`, `NativeGridCell.span`'s comment, test
  1.3's doc comment, and the probe's own reading (GX6's arm **label** is left
  alone: it is in the recorded stdout).
- **Finding 2, GX13.** A fourth arm in test 1.2: `[a 30×10, b 20×20, e 5×5]`
  with a non-row `x 10×10` marked `columns(1)` is 71×38, x offered the whole 71
  and centred at 30.5, e at 66. Derived from the probe line before running and
  correct first run.
- **Finding 12, the marks.** `markNativeGridRow`/`markNativeGridCell` gained a
  `nativeNodes[index] != nil` precondition, before the parent check, each with
  its own message; two arms in `aLegacyNodeUnderAGridOrCarryingAGridMarkTraps`
  (renamed from `aLegacyNodeRegisteredUnderANativeGridTraps`; no new `@Test`).
- **Finding 10, the registrars.** `Tests/MetalUITests/GridRegistrarTests.swift`,
  three `@Test`s through a real `Frame`, reading cell rects relative to the
  grid's own rect (a native root is placed at its answer, centred, by
  `computeNativeLayout(root:proposal:centredIn:)`). All figures derived by hand
  from §4.1–§4.3 — one-row `[a 30×10, b 20×20]` is 58×20 and `[…] [c 100×10
  span 2]` is 100×38 with columns 51/41 — and all correct on the first run.

### Mutations (each: commit, copy, mutate, `git status --short`, full suite, restore, `git status --short`)

| # | mutation | file | reddens |
|---|---|---|---|
| M3.1 | honour a non-row child's column mark: `isRow ? span(child) : (child.columns.map { Swift.max(1, $0) } ?? columnCount)` | `NativeGrid.swift` | `anEmptyGridOrRowIsNothingAndNonRowChildrenMakeOneColumn` (2 issues: GX13's x rect and x's proposals). GA8, GX3, GX4 unmoved, as intended |
| M3.2 | drop `markNativeGridRow`'s legacy check | `LayoutTree.swift` | `aLegacyNodeUnderAGridOrCarryingAGridMarkTraps` (2: the child exits `EXIT_SUCCESS`, and the stderr fragment) |
| M3.3 | drop `markNativeGridCell`'s legacy check | `LayoutTree.swift` | the same test (2), at arm c |
| M3.4 (V2) | `requestNativeGrid` passes `alignment: .center` always | `Grid.swift` | `requestNativeGridForwardsItsAlignmentToTheKernel` (1) **and** `markNativeGridCellForwardsItsColumnCountToTheKernel` (2), whose arms are `.topLeading`; both controls held |
| M3.5 (V2b) | `markNativeGridRow` passes `alignment: nil` | `Grid.swift` | `markNativeGridRowForwardsItsAlignmentToTheKernel` (1) |
| M3.6 | `markNativeGridCell` passes `columns: nil` | `Grid.swift` | `markNativeGridCellForwardsItsColumnCountToTheKernel` (1: b at the control's 108) |

Every restore was confirmed with `git status --short` (clean), and the suite was
1449 green before and after.

### Scoped to later lanes, not done here

- **Lane 3**: the placement re-bisection (finding 6, `GR-AC` item 4) **first**,
  before any new behaviour; test 3.12, the divergence pin (finding 3); 2.14's
  `ncols` and spanning arms (finding 7); test 3.13, the kernel's per-column cost
  (finding 8); GX13's column-alignment half (finding 2); the no-grid T7 arm's
  move into the stack's own test file (finding 9).
- **Lane 4**: tests 4.9b and 4.9c, identity adoption inside a row and between
  rows (finding 13, `GR-AF`); test 4.21, a `maxDepth − 1` chain per node kind on
  a 1 MB thread (finding 5, `GR-AC`); the preview's grid and CLAUDE.md's open
  human-verification row (finding 4, `GR-AE`).
- **Not this track's**: `SA-L`'s margin (owner `LR-Q`'s stage 6b), `CN-B`'s
  stack tie (owner plan task 6), the model's residual disagreements (owner plan
  task 15's closeout). Each now has a named owner in `GR-N`.

### Demo

Not re-run for this round: no lane-3 or lane-4 source landed, and the code
commit touches only the grid plan, the two mark registrars and tests — none of
which any demo or preview content reaches (`grep -rn "Grid\b"
Sources/MetalUIDemoContent Sources/MetalUIDemo`: no hits, re-checked). Lane 3
takes the next comparison, lane 4 the first non-zero one (`GR-AE`).

## Lane 1 re-verification at `062a114` (2026-09-17)

Lane 1 was re-dispatched after the second critic round and found **already
built, with nothing outstanding**: its own commits (`432cb3d`, `82a63fe`,
`92501ce`, `e015b9d`, `92e3313`) and the critic round's amendments to it
(`1b6c698`, `062a114`) are all in the tree, working tree clean, and no new code
or test was needed. What was re-taken at `062a114`, all matching what is
recorded above:

- `swift build --build-system native --build-tests` up to date, then `swift test
  --build-system native --no-parallel` unfiltered: **`Test run with 1449 tests
  in 1 suite passed after 45.761 seconds`**, 0 `error:`, the only `warning:`
  SwiftPM's deprecation notice.
- Goldens **97** (`find Tests -name "*.json" | wc -l`), `git diff cb2e708 --
  '*.json'` empty. Guards **71** (73 `canTypecheck` hits across the thirteen
  guard files and `Typecheck.swift`, less the declaration and
  `UnitSafetyTests`' comment).
- The three claims the round attributed to lane 1 are in the source, checked one
  by one: the span clamp is gone from `NativeGrid.swift` (only `GR-Z`'s proof
  comment remains at line 126, no `Swift.min(span…)`); test 1.2 carries the
  GX13 arm (`NativeGridTests.swift:244–252`, 71×38, x centred at 30.5, e at 66);
  `Tests/MetalUITests/GridRegistrarTests.swift` holds the three `LayoutPass`
  registrar pins (`GR-AD`), so V2/V2b are closed rather than owed to lane 4.
  `NativeLayoutRun.maxDepth` is unchanged at 88 — lane 1's measured grid ceiling
  of 170 is the gate's headroom, not a stored figure.

### Demo (re-taken, not inherited)

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and `062a114`:
**12 of 12 images 0 differing pixels, scenes identical** — the first comparison
taken against the tree as it stands after the second critic round, which chose
not to re-run one. Controls on the head images, each reproducing lane 1's
recorded figure exactly, so the instrument is live: light vs dark f0
**1 048 576**; default vs modal (light) **1 030 498**; default vs animation
(light) **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**.

### The screen was locked at this hour (for lane 4)

`docs/probes/appkit-screen-lock-state.swift`, compiled `-O` and run
2026-09-17: `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0` (`preflightScreenCaptureAccess: true`, one screen
2056×1329 at scale 2). So **no real window was captured this round either**, on
the CGS reading `FR-V` asks for rather than `IOConsoleLocked`. The first
non-zero real-window comparison is still lane 4's (`GR-AE`, `GR-M`), and
whoever takes it must re-run this probe first: "usually unlocked" was not true
at this hour.

## For the integrator

(Written by lane 4; see spec §6, lane 4.)
