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
| `swiftui-grid-gap-order.swift` | 1 (`GR-D`'s "largest": H1, V1, controls GA1 and GQ6) | `40c2fe9` | ×2 | byte-identical; exit 0 |

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
- The span-target rule exists **twice**, once per branch (`GR-AG`, added by the
  lane-2 re-verification). Lane 3's unsized axes and anchors touch both
  `NativeGridSolver.serve` and the nil branch: an edit to one branch's target
  chain is caught only by that branch's arms — GX11 for the nil one, GX9 / GX8 /
  S1 / S2 for the finite one — so change them together or the suite will not
  say.

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

## Lane 1, the verifier's three findings applied (`40c2fe9`, 2026-09-17)

The lane-1 verifier re-ran the round at `062a114` and, against the report's
"complete, nothing outstanding", found **three claims that nothing in the suite
could see** — one major, two minors. All three are now pinned. No `Sources/`
line changed: `git diff 0453d2f -- Sources/` is empty, and the whole round is
two test files, one new probe and three docs.

### The major: `GR-D`'s "the largest pair", unpinned on BOTH axes

Every committed gap arm and all 120 corpus cases put the larger pair in the
LATER row or column, so `Swift.max` and "the last pair seen" answer the same
everywhere the suite looks. Mutating both reductions in
`makeNativeGridPlan` — `hgapValues[column] = value` and `best = value` — left
`Test run with 1449 tests in 1 suite passed`. The mutant is not equivalent: it
reads 50×58 and 58×50 on the two arms below.

A companion probe, **`docs/probes/swiftui-grid-gap-order.swift`**, was written
and run for it (the arms in `swiftui-grid.swift` cannot discriminate: GS1's
larger pair is in the later row, GS4/GS5 have one pair per boundary). Four
arms, two of them positive controls already recorded in `swiftui-grid.swift`
(GA1 78×58, GQ6 58×58, both reproduced), and one discriminator per axis:

| arm | grid | SwiftUI | "last pair wins" would give |
|---|---|---|---|
| H1 | `[c 10x30, d 40x10] [Spacer, b 20x20]` (the Spacer row FIRST) | **58**×58 | 50×58 |
| V1 | `[b 20x20, Spacer] [d 40x10, c 10x30]` (the Spacer column LAST) | 58×**58** | 58×50 |

So SwiftUI takes the largest and the kernel was right all along; the defect was
purely that the claim had no discriminating arm. Exit 0, run twice,
byte-identical stdout, macOS 27.0 (26A428), `/usr/bin/swift` Apple Swift 6.4
(swiftlang-6.4.0.33.1); the reading and the stdout are in its header.

`eachGapIsTheLargestPairSpacingMeetingThere` gains GD-H1 and GD-V1, each as a
plan assertion (`hgap`/`vgap` both `[0, 8]`) **and** laid out with its cells'
rects, and the doc comment names the mutation.

### Minor 1: the grid's bounds origin (spec §4.3)

"The cells start at `bounds`' origin whatever its size (as ZStack's union does,
`CN-E`)" was unpinned — every arm lays a grid out in bounds of its own answer at
the origin, via `Arm.run`, and every in-tree container places a child at the
child's own answer, so only the `computeNativeLayout(root:proposal:in:)` entry
reaches it. `gridAndRowAlignmentPlaceCellsInTheirSlots` gains **GL-B1**: GL1
laid out in `(7, 11, 200×200)` through a new `Arm.run(_:_:_:in:)`, the grid's
own rect asserted as those bounds and each cell at the GL1 rect plus (7, 11).

### Minor 2: `requestNativeGrid`'s spacing (amends `GR-AD`)

The second critic round's registrar pins covered `alignment`, the row alignment
and `columns`, but not `horizontalSpacing`/`verticalSpacing`: forwarding
`nil, nil` whatever it was given left the suite green, which is the same V2/V2b
class the round set out to close. `Tests/MetalUITests/GridRegistrarTests.swift`
gains a fourth test, `requestNativeGridForwardsItsSpacingToTheKernel`, at GA3's
3/5 against the default-spacing control (b at 33 and c at 25, where the control
reads 38 and 28), both control figures `#require`d first. `GridUnderTest` gains
the two spacing fields. `LayoutPass.requestNativeGrid` still has no production
caller (`grep -rn requestNativeGrid Sources/`: only its own declaration), so
every one of its parameters is now pinned by tests alone.

### Mutations (committed first at `40c2fe9`, restored from copies; `git status --short` empty after each)

| # | mutation | file | reddened |
|---|---|---|---|
| H2/H3 | both gap reductions take the LAST pair (`hgapValues[column] = value`, `best = value`) | `NativeGrid.swift` | `eachGapIsTheLargestPairSpacingMeetingThere` (8 issues) — and nothing else, as before the arms |
| H9 | `placeGrid` centres the cells in `bounds` instead of starting at its origin | `LayoutTree.swift` | `gridAndRowAlignmentPlaceCellsInTheirSlots` (4 issues: GL-B1's four cells; its grid rect is `bounds` either way) |
| H1 | `requestNativeGrid` forwards `horizontalSpacing: nil, verticalSpacing: nil` | `Sources/MetalUI/Grid.swift` | `requestNativeGridForwardsItsSpacingToTheKernel` (3 issues: b, c, d; a is (0, 0) under both) |

Each was the verifier's own green mutation; each now reddens exactly the arm
written for it and nothing else.

### Re-taken at `40c2fe9`

- `swift build --build-system native --build-tests`, then `swift test
  --build-system native --no-parallel` unfiltered: **`Test run with 1450 tests
  in 1 suite passed after 61.370 seconds`** (**+1**, the fourth registrar test;
  the three new grid arms are arms of existing tests). 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice.
- Goldens **97**, `git diff cb2e708 -- '*.json'` empty. Guards **71**
  (73 `canTypecheck` hits less `Typecheck.swift`'s declaration and
  `UnitSafetyTests`' comment) — no guard added or removed.

### Demo and the real window

**Not re-run, and it cannot move:** `git diff 0453d2f -- Sources/` is empty, so
the tree's rendering is byte-for-byte `062a114`'s, whose `CN-R` comparison
against `cb2e708` read **12 of 12 images at 0 differing pixels** with live
controls (recorded in the previous section). Re-running the harness here could
only reproduce those twelve zeros.

The screen was **locked** at this hour too:
`docs/probes/appkit-screen-lock-state.swift` compiled `-O` and run 2026-09-17
reads `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0`. So no real-window capture this round either; it is
still lane 4's (`GR-AE`, `GR-M`), and whoever takes it re-runs this probe first.

## Lane 2 re-verification at `d6ad9ff` (2026-09-17)

Lane 2 was re-dispatched after the second critic round and after lane 1's
verifier round, with its own round's content — re-owning divergence `GR-O` 8 to
plan task 6 and queueing lane 3's three amendments — **already applied** by
`062a114`. Its code (`cdd9209` plus the critic round's `1b6c698`) is in the
tree, the working tree was clean on arrival, and no lane-2 behaviour changed.
What was re-taken, and the one thing that was not already true:

### Re-taken at `d6ad9ff`

- `swift build --build-system native --build-tests`, then `swift test
  --build-system native --no-parallel` unfiltered: **`Test run with 1450 tests
  in 1 suite passed after 44.477 seconds`**, 0 `error:`, the only `warning:`
  SwiftPM's deprecation notice. (Lane 2's own record reads 1446; the four since
  are the critic round's three and lane 1's verifier's one.)
- Goldens **97** (`find Tests -name "*.json" | wc -l`), `git diff cb2e708 --
  '*.json'` empty. Guards **71** (73 `canTypecheck` hits across the fourteen
  files, less `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment).
- `GR-X`'s claims, checked one by one in the source: `NativeGridSolver` is still
  inverted (`request` / `provide`, the loop in
  `LayoutTree.measureGrid(_:atAProposal:)`); `NativeGridSolution.bookkeepingSteps`
  and test 2.14's literals 2203 / 1103 / ≤ 3 are unchanged; tests 2.10 and 2.11
  still pin GE10 at a 46 and GE19 at z 46, and 2.11 still carries the no-grid T7
  arm that lane 3 moves out. `GR-O` item 8's owner row (plan task 6) and
  `GR-U`'s uncounted-sites list are in the decisions doc.

### Mutations (from a copy, `git status --short` after each, full native suite)

Four mutations of the finite solver, chosen where a claim looked unpinned:

| # | mutation | reddened |
|---|---|---|
| R1 | `sortByKey`'s last tiebreak reversed (`x > y`): within a group, later declarations served first | 2.1 `aFiniteProposalServesGroupsWithSharesAndCommits` — 1 issue |
| R2 | the probe's two `proposal.width != nil` / `proposal.height != nil` guards dropped, so a nil axis counts toward the flexibility key | 2.2 `theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis`, 2.11 — 9 issues |
| R3 | `commitColumn`'s `levelInColumn[column] == 0` dropped: a column commits with cells still open | 2.1, 2.3, 2.5, 2.6, 2.7, 2.8, 2.9, 2.11, 2.12 — 107 issues |
| **R4** | `finishGroup`'s **middle** span-target step deleted (`targets = columns.filter { plan.columnSingleCells[$0].isEmpty }`) | **nothing: `Test run with 1450 tests in 1 suite passed`** |

### The finding: `GR-AG`, step (2) of the span-target rule

R4's mutant is not equivalent — it moves any cell sharing a column with a span
whose other spanned columns hold no single-column cell. The committed arms
reach step (1) (GX9) and step (3) (GX8) at a finite proposal, and step (2) only
at nil×nil (GX11), which runs the other solve.

A companion probe, **`docs/probes/swiftui-grid-span-targets.swift`**, was written
and run for it. Four arms, two positive controls already recorded in
`swiftui-grid.swift` (C0 = GX8 at 300×100, 100×38 with a (10.50,23), b
(69.50,18), x (0,0); C1 = GX11 at nil×nil, 156×58 with all six rects), both
reproduced rect for rect, and one discriminator per shape, each also run at
nil×nil:

| arm | grid | at | SwiftUI | "all spanned columns" |
|---|---|---|---|---|
| S1 | `[a 20x20] [x 60x20 span 2]` | 200×200 and nil | 60×48, **a (0,0 20×20)**, x (0,28 60×20) | a at 10 |
| S2 | `[a 20x20, b 30x20] [d 10x20, x 90x20 span 2]` | 300×200 and nil | 118×48, **b (28,0 30×20)**, a (0,0), d (5,28), x (28,28 90×20) | b at 43 |

So SwiftUI puts the whole shortfall in the spanned column with no single-column
cell at a finite proposal exactly as at nil, the kernel was right on both
branches, and the defect was that the arm was missing — the lane-1 verifier's
`GR-D` finding one branch over. The sizes also confirm `GR-D`'s pairless column
boundary contributes 0 and not the 8pt default (60 and 118, not 68 and 126).
Exit 0, run twice, byte-identical stdout, macOS 27.0 (26A428), `/usr/bin/swift`
Apple Swift 6.4 (swiftlang-6.4.0.33.1); the reading and the stdout are in its
header.

`aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndWidensItsOpenColumnsFirst`
gains the S1 and S2 arms and names the mutation (`7986252`). Committed first,
then R4 re-applied from a copy: it reddens **that test and nothing else**, 2
issues, `S1 a: LayoutRect(x: 10.0, …)` and `S2 b: LayoutRect(x: 43.0, …)` —
the two figures derived by hand before the run. `git status --short` empty after
the restore. Suite still **1450**: the arms are arms, not new tests.

### Demo and the real window

`git diff 062a114 -- Sources/` is empty, and this round's only `Sources/` change
is two doc comments in `NativeGrid.swift` (the stale
`solveNativeGridAtAProposal` name, and the three-step target rule's per-branch
arms), so the tree's rendering is byte-for-byte the one already compared. It was
nevertheless re-taken rather than inherited:
`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and `d6ad9ff`:
**12 of 12 images 0 differing pixels, scenes identical**, and **re-taken at this
round's own head `5e787c7`** against the same `cb2e708` archive: 12 of 12 at 0
again, with the five controls reading the same five figures on those images too
(only this section's closing note is later, and it touches no source). Controls
on the head images, each reproducing lane 1's recorded figure exactly: light vs
dark f0
**1 048 576**; default vs modal (light) **1 030 498**; default vs animation
(light) **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**; 544
distinct pixel values in `default-light-f0`.

The screen was **locked at this hour too** — the third round in a row:
`docs/probes/appkit-screen-lock-state.swift` compiled `-O` and run 2026-09-17
reads `session CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`,
`displayActive main: 0` (`preflightScreenCaptureAccess: true`, one screen
2056×1329 at scale 2). So no real-window capture; it is still lane 4's
(`GR-AE`, `GR-M`), and whoever takes it re-runs this probe first, on the CGS
reading `FR-V` asks for rather than `IOConsoleLocked`.

## Lane 1 re-verification at `723f26e` (2026-09-21)

Lane 1 was re-dispatched a third time, after lane 2's re-verification, with an
implementer report describing the round at `0453d2f`. The tree had moved on:
HEAD was `723f26e`, holding lane 1's own follow-up (`40c2fe9`, `d6ad9ff`) and
lane 2's (`7986252`, `5e787c7`, `723f26e`). **The worktree was not clean**: it
held one untracked file, `docs/probes/swiftui-grid-finite-shares.swift`, an
interrupted round's work. Continuing it is most of this round.

### Re-taken at `723f26e`

- `swift build --build-system native --build-tests` (incremental, no stored
  property changed, so no `swift package clean`), then `swift test
  --build-system native --no-parallel` unfiltered: **`Test run with 1450 tests
  in 1 suite passed after 48.982 seconds`**, 0 `error:`, the only `warning:`
  SwiftPM's deprecation notice.
- Goldens **97**, `git diff cb2e708 -- '*.json'` empty. Guards **71** (73
  `canTypecheck` hits across the fourteen files, less `Typecheck.swift`'s
  declaration and `UnitSafetyTests`' comment).
- **Red first, checked rather than assumed**: `git show --stat 432cb3d` is five
  test files and no `Sources/` file; `git show --stat 82a63fe` is four
  `Sources/` files and no test. `git grep` at `cb2e708` for `func newNativeGrid`,
  `func markNativeGridRow`, `func markNativeGridCell` and `NativeGridPlan`
  returns nothing, and the test commit spells them twelve times in
  `NativeGridTests.swift` alone — so it could not have compiled.
- **Probe re-run**: `docs/probes/swiftui-grid-gap-order.swift` (lane 1's own,
  from `40c2fe9`) exits 0 and its four lines diff **empty** against the header's
  recorded stdout.

### Mutations (from a copy; `git status --short` shown during and after each; full native suite)

| # | mutation | file | reddened |
|---|---|---|---|
| GV-1 | `nativeGridCellRects` always places at the recorded proposal (the inverse of M1.5) | `NativeGrid.swift` | 14 tests, 29 issues (`aCellWhoseSlotEqualsItsAnswerIsPlacedAtTheProposalItWasMeasuredAt`, `theGridProbeCorpusAgreesCaseByCase`, …) |
| GV-2 | the slot width drops `innerGaps` | `NativeGrid.swift` | 6 tests, 20 issues |
| GV-3 | the vgap interval merge always advances the upper row (`i += 1`) | `NativeGrid.swift` | 5 tests, 28 issues |
| **GV-4** | the trailing edge predicate is `$0.column == plan.columnCount - 1` | `NativeGrid.swift` | **nothing: `Test run with 1450 tests in 1 suite passed`** |
| GV-5 | an empty grid has neither zero-spacing edge | `NativeGrid.swift` | 2 tests, 3 issues |
| GV-6 | at nil a spanning cell does not raise its row's height | `NativeGrid.swift` | 7 tests, 39 issues |
| **GV-F** | `serve` drops the span proposal's floor, `Swift.max(…, spanWidth(cell))` (the `spanWidth` call kept, so `bookkeepingSteps` does not move) | `NativeGrid.swift` | **nothing: 1450 passed** |
| **GV-O** | `serve`'s `outside +=` is always `widths[column]` | `NativeGrid.swift` | **nothing: 1450 passed** |
| **GV-R** | `widen` lets the committed-width sum go stale | `NativeGrid.swift` | **nothing: 1450 passed** |

Four green. None is equivalent — each was re-run against a scratch test (never
committed) that measures the three grids through `LayoutTree`'s `.grid` node:

| arm | kernel as written | under its mutation | SwiftUI |
|---|---|---|---|
| F1 | 218×58 | **218×38** | 218×58 |
| O1 | 106×100 | **298×100** | **245.33×100** |
| R1 | 290×28 | **440×28** | 290×28 |

All four are now pinned; see `GR-AH`. Each was re-applied after its arm landed
and reddens exactly the test written for it and nothing else:

| # | after | reddened |
|---|---|---|
| GV-4b | `a2c1216` | `aGridSeenFromAStackHasPositionalZeroSpacingEdges` — 1 issue (T1's `#require` stops it) |
| GV-Fb | `aea2b04` | `aSpanAtAFiniteProposalIsOfferedTheWidthOutsideItAndWidensItsOpenColumnsFirst` — 3 issues |
| GV-Ob | `aea2b04` | `theModelsDisagreementsWithSwiftUIArePinned` — 7 issues |
| GV-Rb | `aea2b04` | `aFiniteProposalServesGroupsWithSharesAndCommits` — 4 issues |

### The uncommitted probe, and why its header could not be used

`docs/probes/swiftui-grid-finite-shares.swift` arrived untracked, with arms F1,
O1 and R1 aimed at exactly the three green solver clauses above and a header
claiming "RECORDED 2026-09-17 … Exit 0, run twice, byte-identical stdout". Run
here, twice, byte-identical: **it does not reproduce its own header.** All five
arms' measurement sequences differ, and O1's answer differs outright, 106×100
recorded against 245.33×100 measured. The harness is byte-identical to
`swiftui-grid.swift`'s and `swiftui-grid-span-targets.swift`'s, and the C0/C1
controls' real output matches `swiftui-grid-default-run.txt`'s GX8 and GX12 line
for line, sequences included — while the header's C0/C1 lines do not. The header
records, on every arm, **the kernel's answers as SwiftUI's**.

Two of the three readings survive that anyway (F1 and R1: SwiftUI agrees with
the kernel), which is why only O1 exposed it. Had the three arms been written
from the header as the draft intended, the suite would have pinned "SwiftUI
answers O1 106×100" as a confirmation of a rule SwiftUI does not follow.

The file is committed at `aea2b04` with its arms unchanged, its true stdout, a
PROVENANCE paragraph and a corrected reading. The O1 finding is `GR-AH` item 4:
`swiftui-grid.swift`'s own `model-arms` mode, with an O1 case added in a scratch
copy, reads the reference model at 106×100 **rect for rect** with the kernel, so
the kernel follows the model exactly as `GR-B` says and O1 is a fifth
model-vs-SwiftUI disagreement, now an arm of test 2.9 (pinned wrong on purpose)
and a named arm under divergence `GR-O` 2. Owner: plan task 15.

### New probe: `docs/probes/swiftui-grid-span-edges.swift`

For GV-4. Four arms at nil×nil, the GE instrument unchanged (the grid between a
30×10 and a 10×10 leaf in an `HStack`, the stack's answer carrying the gaps):
C0 = GE25 (60×28) and C1 = GE26 (96×28) as positive controls, both reproduced;
T1 a non-row Spacer over a two-cell row, T2 a row Spacer with
`gridCellColumns(2)`. **SwiftUI answers 88×28 for both** — the cell that ENDS at
the last column carries the trailing edge whatever its span, and 96 (the wrong
spelling's answer) is C1's own recorded width, so the two readings are not a
rounding apart. Exit 0, run twice, byte-identical stdout; the header's STDOUT
block diffs empty against the run.

### Commits

`a2c1216` (the span-edges probe and T1/T2), `aea2b04`
(`swiftui-grid-finite-shares.swift` and arms F1, R1, O1), and this record with
`GR-AH`. `git diff 723f26e -- Sources/` is **empty**: no source line changed
this round, so nothing for the integration to merge in a shared file.

### Demo (re-taken, not inherited)

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and `a2c1216`:
**12 of 12 images 0 differing pixels, scenes identical.** Controls on the head
images, each reproducing the figure every earlier round recorded: light vs dark
f0 **1 048 576**; default vs modal (light) **1 030 498**; default vs animation
(light) **210 027**; f0 vs f3 **0**; preview light vs dark **1 048 576**; 544
distinct pixel values in `default-light-f0`.

### The real window, at last — the first non-zero capture this track has taken

`docs/probes/appkit-screen-lock-state.swift`, compiled `-O` and run
2026-09-21, prints **no `CGSSessionScreenIsLocked` line** and `displayAsleep
main: 0` / `displayActive main: 1` (`kCGSSessionOnConsoleKey = 1`,
`preflightScreenCaptureAccess: true`, one screen 2056×1329 at scale 2). The
three earlier rounds all read `CGSSessionScreenIsLocked = 1`; this is the first
time the gate `FR-V` asks for was met. `docs/probes/window-capture/capture.sh`
was run for `cb2e708` and `a2c1216` (release builds from `git archive`,
window-id captures with `-o`, no input, no pointer movement):

| capture | result |
|---|---|
| `cb2e708` default, a vs b | 1840×1176 differing=**0** (the window is settled) |
| `cb2e708` preview, a vs b | 1840×1176 differing=**0** |
| `a2c1216` default, a vs b | 1840×1176 differing=**0** |
| `a2c1216` preview, a vs b | 1840×1176 differing=**0** |
| **`cb2e708` → `a2c1216` default** | 1840×1176 differing=**0** |
| **`cb2e708` → `a2c1216` preview** | 1840×1176 differing=**0** |
| control, default vs preview at `a2c1216` | 1840×1176 differing=**890 803**, bbox (0,15)–(1839,1175) |

So the real release window is pixel-identical to `cb2e708`'s on both the default
demo and the proposal preview, with a live instrument. This closes the capture
`GR-AE`/`GR-M` had left to lane 4; what remains there is the *human look* at the
preview's grid, which no capture can supply.

### For lane 3 and lane 4

- `GR-AH` items 2–4 are lane 2's code. Their arms are written and green here, but
  **lane 3 owns keeping both branches of the span-target and share rules in
  step** — `GR-AG`'s warning now applies to four clauses, not one.
- O1 is a divergence, not a defect (`GR-O` 2, owner plan task 15). Do not
  "fix" the `outside` term toward SwiftUI without re-deriving the model: the
  model is what the other 65 divergence cases are pinned against.
- Lane 4 no longer owes the real-window capture (above); it still owes the
  preview's grid, `GR-AE`'s human-verification row, tests 4.9b/4.9c, test 4.21
  and CLAUDE.md's row.

## Lane 2 re-verification at `f6ed8a0` (2026-09-21)

Lane 2's third round. The tree was clean at `f6ed8a0`, holding lane 1's verifier
round (`a2c1216`, `aea2b04`, `f6ed8a0`), which had written five arms into lane
2's own tests — F1, O1 and R1 into 2.1/2.8/2.9, T1 and T2 into 1.10 (`GR-AH`).
The lane's dispatch text was stale in two places, checked before acting: its
"suite 1446 → 1449" is now 1450, and the two things it asked the lane to re-own
were already applied — `GR-O` item 8's owner is plan task 6 (`GR-N`'s table),
and lane 3's three amendments (2.14's `ncols` and spanning arms, the no-grid T7
arm moving to the stack's own file) are in the spec's lane-3 section.

### Re-taken at `f6ed8a0`

- `swift build --build-system native --build-tests` (incremental; no stored
  property changed, so no `swift package clean`), then `swift test
  --build-system native --no-parallel` unfiltered: **`Test run with 1450 tests
  in 1 suite passed after 50.585 seconds`**, 0 `error:`, the only `warning:`
  SwiftPM's deprecation notice.
- Goldens **97**; `git diff cb2e708 --stat -- '*.json'` empty. Guards **71**
  (73 `canTypecheck` hits across fourteen files, less `Typecheck.swift`'s
  declaration and `UnitSafetyTests`' comment).

### Depth re-bisected at the head, not argued

`GR-X` item 2's ceilings were taken at `0196743`. Since then `1b6c698` removed
the span clamp in `makeNativeGridPlan` and added two `SA-G` preconditions to the
mark registrars — `git diff 0196743..HEAD -- Sources/`, with comment lines
filtered out, is exactly those three lines, all at registration time and none on
the measurement recursion. That is an argument, so the boundary was measured
instead: scratch test (never committed), N nested one-cell grids over a leaf
answering `min(proposal, 10)`, `maxDepth` temporarily `100_000`, one
`swift test --skip-build --filter` per depth.

| chain | 1 MB debug | first failing depth on 4 MB |
|---|---|---|
| one-cell grid at 400×400 | **155 completes / 156 dies** | 156 completes |
| one-cell grid at nil×nil | **167 completes / 168 dies** | — |

Identical to lane 2's own figures; `NativeLayoutRun.maxDepth`'s table needs no
edit, and both clear `GR-M`'s gate of 147. `maxDepth` restored and the scratch
file deleted before the suite (`git status --short` empty).

### The differential instrument (scratch, never committed)

`Tests/MetalUILayoutTests/ScratchGridDifferential.swift`: 4 000 generated grids
(1–4 rows, 1–4 cells each, one row in five a non-row child, one cell in four
spanning 2–3, four priority levels, six leaf kinds from fixed through
proposal-following) × five proposals (200×100, 60×300, 300 × nil, nil × 120,
∞ × 100) = **20 000 solves**, every column width, row height, cell answer and
recorded proposal folded into one FNV digest, through `solveNativeGrid`
directly. Baseline digest `c69d82acf7cc6f30`.

**Calibrated before it was believed**: mutation M1 (`serve` dropping the
single-column floor) moves it to `7c9c6776323b429f`, and four of the six
mutations it was used to filter moved it too. A digest that does not move is a
claim of *equivalence*, never of coverage.

### Mutations (committed first; from a copy; `git status --short` during and after each; full native suite)

Twelve run straight against the suite, six (A–F) filtered through the digest
first. **None was green.**

| # | mutation (`NativeGrid.swift`, `NativeGridSolver` unless noted) | reddened |
|---|---|---|
| H | `heighten` drops the running committed-height sum (the height twin of `GR-AH`'s R) | 2.1 — 1 issue |
| M1 | `serve` drops the single-column width floor, `Swift.max(shareW, widths[column])` | **this row did not reproduce; re-taken below** — as written it recorded "2.1, 2.4 — 2 issues", which neither reading of the mutant gives |
| M2 | `serve` drops the row-height floor, `Swift.max(shareH, heights[row])` | 2.4 — 1 issue |
| M3 | a served cell **sets** its row height instead of raising it | 11 tests — 119 issues |
| M4 | the level counters are refilled at every group, not at every level | 2.2, 2.9, 2.11, 2.13, 2.14 — 29 issues |
| **M5** | **`finishGroup`'s `isFirstGroup` split deleted: every group sweeps every column and row** | **2.14 only — 2 issues** (digest unchanged: see below) |
| M6 | the span shortfall guard admits negatives (`> 0` → `!= 0`) | 2.8 — 4 issues |
| M9 | `commitRow` drops its open-cell guard (the row twin of the `d6ad9ff` round's R3) | 9 tests — 127 issues |
| M11 | `spanWidth` drops its inner gaps | 2.8, 2.9, `markNativeGridCellForwardsItsColumnCountToTheKernel` — 20 issues |
| M12 | the finite span proposal drops its inner gaps | 2.8 — 9 issues |
| M13 | the shortfall goes entirely to the first target instead of splitting equally | 2.8, `markNativeGridCell…` — 7 issues |
| M14 | a span also widens its first column by its whole answer | 2.8, 2.9, `markNativeGridCell…` — 25 issues |
| **A** | `Double(Swift.max(openColumns, 1))` → `Double(openColumns)` (division by zero) | **digest unchanged; not run against the suite in THIS round** — run in the next one (`f7aec53`), where it and its never-before-mutated `openRows` twin each pass 1450/1450; green and equivalent, see below |
| B | the priority key sorts ascending | 8 tests — 81 issues |
| C | every cell is its own group (`sameKey` never extends one) | 2.1, 2.8, 2.14 — 7 issues |
| D | `unprocessedSingles` never decrements (step 12 always finds targets) | 2.8, 2.9 — 7 issues |
| E | a column may be committed twice (`!committedColumn` dropped) | 2.1, 2.14 — 5 issues |
| F | the group key ignores flexibility | 7 tests — 38 issues |

### The two clauses no test can hold (`GR-AI`)

**M5 — the commit sweep's shape is a COST rule.** Deleting the
first-group/later-group split reddens only `theSolversBookkeepingIsLinearInTheCells`
(2.14), and the digest is **byte-identical over 20 000 solves**. Structurally it
must be: `commitColumn` guards on `!committedColumn[column] && levelInColumn[column] == 0`,
and a column's level count reaches 0 only in the group that serves its last cell
at that level, so the sweep's extra visits are no-ops; a column whose cells all
sit at a later level is committed early at width 0, adding 0 to `committedWidth`,
and `widen` keeps the sum in step from then on. So 2.14's counter is the split's
whole defence — which makes lane 3's promised `ncols` arm (`GR-Y` finding 9)
load-bearing rather than a nicety, and 3.13 mutates the very same line.

**A — `startGroup`'s two `Swift.max(…, 1)` clamps are unreachable.** `openRows`
is at least 1 at every `startGroup` (every cell of the level raised its row's
count at the refill; a later group's have not been decremented). `openColumns`
is 0 only when the level holds no single-column cell, and then `shareW` is never
read: the span branch charges `widths[column]` on every outside column, since
`levelInColumn` is 0 everywhere, and proposes `wPrime − outside`. Dividing by
zero leaves the digest byte-identical. Both stay as written, `startGroup`'s doc
comment says why, and **no test should be written for them** — it could not
fail.

### Source

`git diff f6ed8a0 -- Sources/` is **doc comments only**: the file header (the
model is unchanged since probe revision 5, the file is at revision 6),
`startGroup`'s clamp note and `finishGroup`'s cost note. Nothing executable
moved, so there is nothing for the integration to merge in a shared file.
`NativeGridWorkTests.swift`'s 2.14 gains the second mutation it alone catches.

### Demo

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and this round's
source commit `ceef0dc`: **12 of 12 images 0 differing pixels, scenes
identical.** Controls taken on the head images first, each reproducing the
figure every earlier round recorded: light vs dark f0 **1 048 576**; default vs
modal (light) **1 030 498**; default vs animation (light) **210 027**; f0 vs f3
**0**; preview light vs dark **1 048 576**; 544 distinct pixel values in
`default-light-f0`.

### The real window: not taken, and why it does not need to be

`docs/probes/appkit-screen-lock-state.swift`, compiled `-O` and run at the end
of this round, prints **`CGSSessionScreenIsLocked = 1`** and `displayAsleep
main: 1` / `displayActive main: 0`, so `FR-V`'s gate is shut and no capture was
attempted. Lane 1's round took the track's first live capture at `a2c1216`
(default and preview, `cb2e708` → `a2c1216`, 0 differing pixels on both, with a
890 803-pixel control). `git diff a2c1216..HEAD -- Sources/`, with comment lines
filtered out, is **empty** — this round changed no executable line — so that
capture still describes this head.

### For lane 3

- **2.14's `ncols` arm is the only defence the commit sweep has** (`GR-AI`).
  Write it before touching `finishGroup`, and note that 3.13's named mutation —
  "make the first group's commit sweep visit only its own cells' columns" — is
  that same line, so the two rows must agree on the literal.
- Do **not** write a test for `startGroup`'s `Swift.max(…, 1)` clamps. It could
  not fail; the source says why.
- Unchanged from the previous round: the span-target rule exists once per
  branch (`GR-AG`), and `GR-AH` items 2–4 add three more clauses whose two
  branches must move together; `NativeGridSolver` must stay inverted, and lane 3
  re-bisects the PLACEMENT path, which this round did not touch.
- Lane 3's expected count baseline in the spec was 1449 and is **1450**;
  measure it rather than trust it.

### Deferrals

Nothing new. `GR-O` item 8 (the stack's infinite-flexibility tie, GE10/GE19/T7)
stays owned by plan task 6, and `GR-O` item 2 (the model-vs-SwiftUI divergence
corpus, now with `GR-AH`'s O1 in it) by plan task 15.

## Lane 2, implementer round at `5c6c5ff` → `f7aec53` (2026-09-21)

The lane-2 verifier's fourth round returned one blocker and two minors. Nothing
in `Sources/` changed; the round is one probe, two test arms and three
corrections to what earlier rounds claimed.

### The blocker: a per-axis clause is two copies (`GR-AJ`)

`GR-E` step 2's "a nil proposal axis counts for neither" is two sibling `if`s in
`NativeGridSolver.provide`, one per axis. Deleting the **height** guard reddens
two tests; deleting the **width** guard left the whole 1450-test suite green.
`GR-AI`'s eighteen mutations never separated them — the `d6ad9ff` round's R2
dropped both in one mutant, so its red came entirely from the height half — and
every arm of test 2.2 ran at a finite width (200, 200, 150, 150), varying only
the height.

**The witness, hand-derived from the reference model before any run.** Two rows
of one cell: `a` = `fw(20)` (width `proposal ?? 10`, height a fixed 20), `b` =
`cb(10, 80)` (clamp on both axes). At nil × 100 the plan is one column, two
rows, `vgap = [0, 8]`, so H′ = 92.

| | key as written (height axis only) | key with the nil width counted |
|---|---|---|
| a | infinite axes 0, flexibility 20 − 20 = 0 | infinite axes **1** (∞ answer is infinitely wide), flexibility 0 |
| b | infinite axes 0, flexibility 80 − 10 = 70 | infinite axes 0, flexibility 70 + (80 − 10) = 140 |
| order | a, then b | **b, then a** (fewer infinite axes first) |
| serve | a at 92/2 = 46 → 10×20; b at (92 − 20)/1 = 72 → 10×72 | b at 46 → 10×46; a at (92 − 46)/1 = 46 → 10×20 |
| answer | **10×100**, a (0,0 10×20), b (0,28 10×72) | 10×74, b (0,28 10×46) |

Test 2.2 gains that grid as **GF19** (GF14–GF18 are test 2.1's; `f7aec53`'s
commit subject still names the pre-rename ids, the code and every doc use
GF19/GF20), with **GF20**,
the same grid at 100×100, as the control that reaches the mutant's order
honestly through a finite width: 100×74, a (0,0 100×20), b (10,28 80×46). The
two are `#require`d to differ.

**Probe.** `docs/probes/swiftui-grid-nil-width-key.swift`, N1 = GF19,
N0 = GF20, `/usr/bin/swift` Apple Swift 6.4 (swiftlang-6.4.0.33.1), macOS 27.0
(26A428), exit 0, run twice, `diff` empty. Both arms landed **exactly** on the
hand-derived figures above, so SwiftUI counts the nil axis for neither term, and
its measurement log reads the order directly: `a nilx46` before `b nilx72` at
nil × 100, `b 100x46` before `a 100x46` at 100×100.

**Mutation** (committed first at `f7aec53`, from a copy, `git status --short`
showing only `NativeGrid.swift` during and nothing after, full unfiltered native
suite): `if proposal.width != nil` → `if true` fails
`theFlexibilityKeyCountsInfiniteAxesFirstAndIgnoresANilAxis` alone, **2
issues** — `NativeGridTests.swift:1159` (`gf19Size == size(10, 100)`) and
`:1160` (GF19's b rect) — out of 1450.

### The two clamps, run against the suite at last

`GR-AI` reported eighteen mutations "every one reddened" while its own table
said A was never run. Both clamps have now been run, **each on its own**, from a
copy, full unfiltered native suite at `f7aec53`:

| mutation | suite |
|---|---|
| `Double(Swift.max(openColumns, 1))` → `Double(openColumns)` | `Test run with 1450 tests in 1 suite passed after 47.622 seconds` |
| `Double(Swift.max(openRows, 1))` → `Double(openRows)` (never mutated before, by digest or by suite) | `Test run with 1450 tests in 1 suite passed after 47.713 seconds` |

So both are **green and equivalent**, as `GR-AI`'s structural argument and the
verifier's independent 20 000-solve digest say — not "reddened". `GR-AI` and the
spec's lane-2 paragraph are amended to say so; the instruction not to write a
test for them stands, because it could not fail.

### M1 re-taken, with the mutant quoted

The `f6ed8a0` table's M1 row read "2.1, 2.4 — 2 issues" and reproduces under
neither reading of "drops the single-column width floor". Both were re-run at
`f7aec53`, from a copy, full unfiltered suite each time:

| mutant, exactly | reddened |
|---|---|
| `width = Swift.max(shareW, widths[cell.column])` → `width = shareW` | `aFiniteProposalServesGroupsWithSharesAndCommits` alone — **1 issue** (GF7's d, `NativeGridTests.swift:1036`) |
| the same line → `width = widths[cell.column]` | **14 tests, 216 issues** — every one of tests 2.1–2.14 |

(The verifier read 213 issues for the second at `5c6c5ff`; the extra three are
GF19/GF20's, which the same mutant also moves.) The first reading is the one
`GR-AI`'s digest calibration used, and it is the honest M1: **one** test, not
two. A future regression can now be told apart from a coverage change by the
issue count.

### Suite, goldens, guards

`swift build --build-system native --build-tests` then `swift test
--build-system native --no-parallel`, unfiltered, at `f7aec53`: `Test run with
1450 tests in 1 suite passed`, 0 `error:`, the only `warning:` SwiftPM's own
deprecation notice. No test was added or removed — GF19/GF20 are arms of an
existing test — so the count is unchanged from `5c6c5ff`. Goldens 97, `git diff
cb2e708 -- '*.json'` empty. Guards 71, unchanged; the round adds no typecheck
guard.

### The real window and the demo

`git diff f6ed8a0..HEAD -- Sources/`, with comment lines filtered out, is
**empty** — the only source change since lane 2's last round is `ceef0dc`'s
24 lines of doc comment — so lane 2's 12-of-12 0-pixel demo comparison at
`ceef0dc` and lane 1's live capture at `a2c1216` both still describe this head,
and neither was re-taken. The screen lock was not probed, because with no
executable line moved there is nothing for a capture to see.

### For lane 3, added by this round

- **Mutate each per-axis twin on its own**, at a proposal where that axis is the
  nil one (`GR-AJ`). The solver's twins are the two `provide` guards,
  `wPrime`/`hPrime`, `shareW`/`shareH`, `widen`/`heighten` and
  `commitColumn`/`commitRow`; lane 3's anchors and unsized axes add more.
- Arm ids `GF14`–`GF18` belong to test 2.1 and `GF19`/`GF20` to test 2.2; the
  next free `GF` is **GF21**.


## Lane 3 — cell attributes and the modifier-chain walk (2026-09-21)

Base `d7a785f` (lane 2's implementer round), suite **1450**. Rulings delivered:
`GR-F`'s column sum and `columns(0)`, `GR-G` (anchors, column alignment,
inner-wins), `GR-H` (`gridCellUnsizedAxes`), `GR-I` (the walk) and `GR-S` (the
`Int32.max` ceiling), plus the dispositions `GR-AK` (the placement
re-bisection), `GR-AL` (what the spec's rows became) and `GR-AM` (four clauses
the lane's own arms could not hold).

### First: the placement path, re-bisected before any new behaviour

`GR-AC` item 4 required this ahead of the lane's own work; `GR-AK` holds it in
full. Lanes 1 and 2 bisected chains of ONE-cell grids, whose slot always equals
the cell's answer, so `nativeGridCellRects`' fresh-measurement branch — the one
that recurses from inside an `Array.map` closure — was never on the measured
stack. Method as before: a scratch test (never committed), `maxDepth`
temporarily `100_000`, one `swift test --build-system native --skip-build
--filter` per depth on a `Thread` with a 1 MB stack.

| chain | 1 MB debug | note |
|---|---|---|
| two-cell rows, slot ≠ answer at EVERY level (placement) | **154 / 155** | 155 completes on 4 MB, so it is a stack ceiling |
| the same chain, measurement only, at nil×nil | 167 / 168 | the 13 levels lost are placement's |
| one-cell grid, nil×nil | 167 / 168 | unchanged from lane 2 |
| one-cell grid, 400×400 (the finite solve) | **154 / 155** | 155 / 156 in lane 2: one level for lane 3's locals |
| one-child vertical `linearStack` | 127 / 128 | unchanged |
| padding | 194 / 195 | unchanged |

The placement figure was taken twice, before lane 3's code and after it, and
read 154 / 155 both times. 154 ≥ `GR-M`'s gate of 147, so `placeGrid` keeps its
shape and `nativeGridCellRects` keeps measuring inside its `map`;
`NativeLayoutRun.maxDepth`'s table carries the paragraph. `maxDepth` restored
and the scratch file deleted before the suite (`git status --short` empty).

### Red first (`5ceea23`)

The lane's tests were committed against lane 2's source, where they do not
compile. `swift build --build-system native --build-tests` reported ten distinct
errors and their "cannot infer contextual base" follow-ons, no others:
`markNativeGridCell` had no `anchor:`, `columnAlignment:` or `unsizedAxes:`
(three sites), `NativeGridCell` no `anchor` or `unsizedAxes`, `NativeGridPlan`
no `columnAlignments`, and `GridCorpus`' builder passed three arguments the
registrar did not take. The commit message lists them with line numbers.

### Source (`f3885a7`)

- `markNativeGridCell(_:columns:anchor:columnAlignment:unsizedAxes:)`: columns
  **sum above 1**, anchor and column alignment **keep the first value written**
  (the inner modifier marks first), unsized axes **union**; a single count or a
  node's sum above `Int32.max` traps naming `columns`.
- `LayoutTree.gridChildMarks(_:)`, the walk of `GR-I`: through `frame`,
  `padding`, `fixedSize`, `aspectRatio`, `layoutPriority` and an overlay
  attachment's child 0, stopping at a linear stack, a `ZStack`, the overlay
  content side, a scroll viewport, a custom layout, a nested grid, a spacer or a
  leaf. The row token (with its alignment) from the **outermost** mark, the
  anchor and column alignment from the **innermost**, columns summed, unsized
  axes unioned, and the chain's sum checked against `Int32.max`.
- `makeNativeGridPlan`: each row's sum of spans checked **as it grows** (so a
  row of several huge spans cannot overflow before the check sees it), the
  message naming `gridCellColumns`; `columnAlignments` per column, the first
  declaration by a **row** cell in row then cell order.
- `NativeGridSolver.serve`: an unsized axis is proposed `spanWidth(cell)` or
  `heights[cell.row]` instead of a share — only where that axis's proposal is
  non-nil, so nil×nil is untouched (GU4).
- `nativeGridCellRects`: `fx` = anchor ?? (span == 1 ? the column's : nil) ?? the
  grid's; `fy` = anchor ?? the row's ?? the grid's.

`swift package clean` before the suite (three new stored dictionaries on
`LayoutTree`, a public class read across a module boundary):
**`Test run with 1463 tests in 1 suite passed after 48.790 seconds`** (1450 +
13, spec §6's estimate exactly; §7's table said 1462 and was an arithmetic
slip). Goldens 97, unmoved (`git diff cb2e708 -- '*.json'` empty); guards **71**
(73 `canTypecheck` hits across fourteen files less `Typecheck.swift`'s
declaration and `UnitSafetyTests`' comment).

### Mutations

Committed first; each applied from a copy, `git status --short` showing exactly
one modified file during and nothing after (checked on all 42 runs); full native
suite each time. "Reddened" lists the tests and their issue counts.

| # | mutation | reddened |
|---|---|---|
| M3.1 | the LAST column-alignment declaration wins | 3.1 (4), 2.13 (3 corpus cases) |
| M3.1b | a non-row child declares a column alignment too | 3.1 (1: GX13c) |
| M3.2 | a span is aligned by its first column's alignment | 3.2 (1), 2.13 (4) |
| M3.2b | a span declares for its LAST column | 3.2 (1) |
| M3.3 | the column alignment read before the anchor in `fx` | 3.3 (1), 2.13 (2) |
| M3.4 | a later mark on one node overwrites an earlier one | 3.4 (2: GL15, GL16) |
| M3.4b | the walk takes the OUTERMOST anchor and column alignment | 3.4 (2: GWI3, GWI4) |
| M3.5 | the largest per-node mark instead of the sum | 3.5 (6) |
| M3.5b | the CHAIN's `columns +=` becomes a `max` | **green before the fix**; after: 3.5 (1: W2/W3), 3.6 (2: arm d) |
| M3.5c | `columns > 1` relaxed to `columns >= 1` | 3.5 (11) |
| M3.6a | drop the single-count `Int32.max` check | **green before the fix**; after: 3.6 (1: arm a) |
| M3.6b | drop the per-node sum check | 3.6 (2) |
| M3.6c | drop the row-sum check, spans clamped to 2 | 3.6 (2), 3.5 (9), 3.13 (1), 2.9 (1), 2.14 (1) |
| M3.6d | drop the walk's sum check, the walk's answer clamped to 4 | 3.6 (4), 3.5 (4), 3.13 (1) |
| M3.7 | do not absorb an unsized cell's answer, either axis | 3.7 (8), 2.13 (119) |
| M3.7h | the same, WIDTH only | 3.7 (5), 2.13 (70) |
| M3.7v | the same, HEIGHT only | 3.7 (3), 2.13 (55), 3.12 (3) |
| M3.8 | ignore unsized axes on a non-row cell | 3.8 (1), 2.13 (4) |
| M3.9 | a later unsized mark on one node replaces the axes | 3.9 (3) |
| M3.9b | the walk's union becomes "the innermost replaces" | 3.9 (5: GWI5) |
| M3.10 | stop the chain at `padding` | 3.10 (10), 3.5 (5), 3.4 (2), 3.9 (3) |
| M3.11 | `columns(0)` treated as 2 | 3.11 (3) |
| M3.12a | GZ0's control: every group offered W′/ncols, commits ignored | **416 issues** across 17 tests, 2.13's 46 corpus cases and 3.12's divergences 11, 33, 36, 54 |
| M3.12b | model variant 4 (a span keeps its columns open) | 2.13 (3), 2.9 (7); **none of 3.12's five** |
| M3.12c | model variant 6 (a column with no single-column cell is always open) | 2.13 (7), 2.9 (5), 3.12 (2: divergence 22) |
| M3.13 | the first group's commit sweep visits only its own cells' columns | 3.13 (2), 2.14 (5), 2.13 (11), 2.9 (5), 3.12 (2) |
| M3.AX | `fx` ignores the anchor | 3.3 (3), 3.4 (2), 2.13 (8) |
| M3.AY | `fy` ignores the anchor | 3.3 (2), 3.4 (2), 2.13 (15) |
| M3.RT | the walk takes the INNERMOST row token | **green before the fix**; after: 3.10 (1: R2) |
| M3.UH | drop the unsized WIDTH branch in `serve` | 3.7 (1), 3.8 (1), 3.9 (15), 2.13 (34) |
| M3.UV | drop the unsized HEIGHT branch in `serve` | 3.7 (4), 3.9 (6), 2.13 (35) |
| M3.UW | the unsized width reads `widths[cell.column]`, not `spanWidth` | **green before the fix**; after: 3.7 (3: U0/U1) |
| M2.14b | delete `finishGroup`'s `isFirstGroup` branch | 2.14 only (**4** issues, where lane 2 read 2 — the two new arms) |
| MT7 | break an infinite-flexibility tie by the answer at main 0 | `aStackServesItsLeastFlexibleChildFirst` (3: T7), 2.10 (3), 2.11 (6), two native work tests (2) |

(Test numbers are spec §6's; 2.9 is `theModelsDisagreementsWithSwiftUIArePinned`,
2.10 `aGridPassesNoPriorityToAnEnclosingStack`, 2.11
`aGridInAStackLaysOutAsTheModelInAStack`, 2.13
`theGridProbeCorpusAgreesCaseByCase`, 2.14
`theSolversBookkeepingIsLinearInTheCells`.)

**Two mutants are not runnable as bare deletions**, and that is itself the
finding: dropping the row-sum check (M3.6c) or the walk's check (M3.6d) leaves
the child asking for 2 × `Int32.max` or 2³⁰ columns, and the run **hangs** —
observed on the first attempt at M3.6c, which had to be killed after the suite
sat on the trap test with no progress. A first stand-in that clamped
`columnCount` to 4 crashed instead ("Index out of range": a cell's column then
exceeds the column count). The mutants recorded above clamp the **span** (M3.6c)
and the walk's answer (M3.6d), which keeps the plan self-consistent, so the
child registers and exits `.success` — the discrimination the arms were written
for. Both substitutions are `GR-AL`'s item 3.

### Four green mutations, four holes (`GR-AM`), and the probe that closed them

`M3.5b`, `M3.6a`, `M3.RT` and `M3.UW` each left all 1463 tests green. None was
a broken instrument: each names a clause whose only arms could not tell the two
rules apart.

- **The chain's column sum.** GWI1 and GWI2 write 2 and 1; 1 is not above 1, so
  "sum the marks above 1" and "take the largest" both answer 2.
- **The chain's row token.** Every row arm writes one token per chain.
- **The unsized SPAN's proposal.** GU3's leaf follows its proposal, so a wrong
  proposal is re-measured away at placement and no rect moves.
- **The single-count `Int32.max` check.** Redundant in effect with the per-node
  sum check, whose message differs only in its tail, which arm (a) did not
  assert.

New probe `docs/probes/swiftui-grid-lane3-discriminators.swift`: ten arms
(W0–W3, R0–R3, U0–U1), every one hand-derived from the reference model **before**
the run and every one exactly as predicted; `/usr/bin/swift` = Apple Swift 6.4
(swiftlang-6.4.0.33.1), macOS 27.0 (26A428), exit 0, run twice byte-identical,
and the committed file re-run reproduces the stdout in its own header. Its
readings: SwiftUI ADDS two `gridCellColumns` written on opposite sides of a
`.padding()` (W2, W3); it flattens a nested `GridRow` through a `.padding()`
into the enclosing row, so the OUTERMOST row mark wins (R2 at 60×20, against
R3's 30×38 for two real rows); and an unsized span is proposed its spanned
columns' widths plus their inner gap, `c 58x172` in U1's measurement log, not
its first column's 30. Pinned by tests 3.5 (W0–W3), 3.10 (R2) and 3.7 (U0/U1),
and by test 3.6's sharpened arms (a)/(b) plus its new arm (d) (`c49fada`).

### Demo

`CN-R`'s harness (`scratchpad/harness/gen-lib.py`, `DEMO_PIXELS_SMALL=1`,
default build system) in fresh `git archive`s of `cb2e708` and the lane's head:
**12 of 12 images 0 differing pixels, scenes identical.** Controls on the head
images, all non-zero where they must be: light vs dark f0 1 048 576; default vs
modal (light) 1 030 498; default vs animation (light) 210 027; preview light vs
dark 1 048 576; f0 vs f3 0 (the demo is static after frame 0, as in lanes 1 and
2); 544 distinct pixel values in `default-light-f0`.
`grep -rn "Grid\b" Sources/MetalUIDemoContent Sources/MetalUIDemo`: no hits — no
grid reaches the demo until lane 4 (`GR-AE`).

### The real window, and a harness limit this lane found

The screen was **unlocked** (`docs/probes/appkit-screen-lock-state.swift`: no
`CGSSessionScreenIsLocked` line, `displayAsleep main: 0`,
`preflightScreenCaptureAccess: true`), so
`docs/probes/window-capture/capture.sh <dir> cb2e708 c49fada` was run — twice,
because the first table was not believable.

| pair | run 1 | run 2 |
|---|---|---|
| each window against itself, 1.5 s apart (the harness's own precondition) | 0 in all four | 0 in all four |
| `cb2e708` → head, default window | **0** | 102 614, bbox (0,0)–(1839,55) |
| `cb2e708` → head, preview window | 102 614, bbox (0,0)–(1839,55) | 102 614, same bbox |
| control, default vs preview at head | — | 890 803, bbox (0,15)–(1839,1175) |

**That table says nothing about the commits, and the control that proves it is
the same commit at two launches**: `cb2e708`'s own default window from run 1
against `cb2e708`'s own default window from run 2 reads **102 614 in the same
bbox**, while `cb2e708` (run 1) against the head (run 2) reads **0**. The
delta is a per-launch coin flip, not a commit difference.

What it is, as far as it was chased: every differing pixel in every pair lies in
the **same 56 buffer rows**, which are the window's **bottom 28 points** (the
rounded-corner, partly transparent band — `pixdiff` draws through a `CGContext`
whose origin is bottom-left, so its row 0 is the image's bottom). The band's
mean colour is identical to the integer in every image, (14, 21, 38, 253); the
content is not shifted (aligning the images at offsets 1…6 rows only makes the
count worse, 167 871 at 1 row against 102 614 at 0); and the two bands are
indistinguishable by eye. So: **outside that band, every pair reads 0**, which
is the reading the capture was taken for.

**For the harness** (`GR-M`): its stated precondition — capture each window
twice 1.5 s apart and require 0 — holds within a launch and does **not** cover
this. A future capture should either compare the same commit across two launches
as a control, as this lane did, or mask the bottom 28 points. Reported, not
fixed: `capture.sh` is shared with the other tracks.

### For lane 4

- **The placement path's ceiling is 154, seven levels above the gate**
  (`GR-AK`). Lane 4's test 4.21 builds a chain of ONE-cell grids, which measures
  167 and says nothing about placement; use `GR-AK`'s two-cell chain if the
  placement half is to be covered, and do not raise `maxDepth`.
- **`markNativeGridCell` takes four attributes in one call and writes only what
  it is given**, so `GridCellModifier` must make ONE call per modifier: a merged
  call would silently reverse the "inner declaration wins" rule, which is "the
  first mark on a node stands".
- **`LayoutPass.markNativeGridCell` still forwards `columns:` alone**
  (`Sources/MetalUI/Grid.swift`). Lane 3 deliberately did not widen it: an
  exported parameter with no caller is what `GR-AD` was written about. Lane 4
  adds `anchor:`, `columnAlignment:` and `unsizedAxes:` there **in the same
  change as `GridCellModifier`**, with a `GridRegistrarTests` arm per argument.
- **A `GridRow`'s cell attributes must mark AFTER its content has registered**
  (`GR-T`; lane 4's test 4.5 mutation (b)), so a cell's own modifier has already
  marked and wins the anchor and the column alignment, while spans add and
  unsized axes union.
- **`ProposalAxes` is no longer inert** — `GR-O`'s inert list loses that item,
  which says so itself.
- Arm ids: `GW`/`GL`/`GU`/`GX` are the main probe's; lane 3 added **GX13c** (a
  non-row child's column alignment, kernel-authored and corpus-backed) and
  **W0–W3 / R0–R3 / U0–U1** from the lane-3 discriminator probe. The next free
  `GF` is still GF21.
- **Mutate each per-axis twin on its own** (`GR-AJ`, carried): lane 3 added two
  pairs — `serve`'s width and height unsized branches, and the two absorb sites
  in `provide` — and mutated each singly (M3.UH, M3.UV, M3.7h, M3.7v). Both
  halves of each pair reddened, so neither is a copy the suite reaches only once.
- **A check whose job is to prevent an allocation cannot be mutated by deleting
  it**: the mutant hangs. Clamp as well as delete, and keep the plan
  self-consistent while doing so (`GR-AL` item 3).
- **The real-window harness needs a same-commit cross-launch control** before
  its cross-commit table means anything (above); lane 4 owes real-window
  captures by `GR-M` and will meet the same band.

### Deferrals

Nothing new. `GR-O` item 8 (the stack's infinite-flexibility tie, now pinned by
`aStackServesItsLeastFlexibleChildFirst`'s T7 arm as well as GE10 and GE19)
stays owned by plan task 6; `GR-O` item 2 (the divergence corpus, now with test
3.12's five cases in it) by plan task 15.

### Verifier round (lane 3)

Re-taken at `1630443` on a `swift package clean` build: **`Test run with 1463
tests in 1 suite passed after 48.618 seconds`** (**1464** at the verifier's own
head, one test added by `GR-AO`), 0 `error:`, no `warning:` but
SwiftPM's deprecation notice, goldens **97** (`git diff cb2e708 -- '*.json'`
empty), guards **71** (73 `canTypecheck` hits less `Typecheck.swift`'s
declaration and `UnitSafetyTests`' comment). Lane 3 adds no typecheck guard, so
there was none to mutate.

**Red first, re-run.** `Sources/` at `d7a785f` with `Tests/` at `5ceea23`
compiles with exactly the ten errors the commit message lists, at the same line
numbers (97:47, 103:56, 109:52, 1868:36, 2360:53, 2365:35, 2371:62, 2376:26,
2383:58, 2388:35), plus their "cannot infer contextual base" follow-ons and
nothing else. Restored, `git status --short` empty.

**The probe re-run.** `/usr/bin/swift
docs/probes/swiftui-grid-lane3-discriminators.swift` exits 0 and its twenty
stdout lines match its header byte for byte.

**Mutations: nineteen, each from a copy of the committed file, `git status
--short` showing exactly one modified file during and nothing after, full native
suite each time.** Eleven re-take the implementer's and read the same tests;
four are the verifier's own.

| # | mutation | reddened |
|---|---|---|
| V1 | the chain's `columns +=` becomes a `max` (`M3.5b`) | 3.5 (1), 3.6 (2) |
| V2 | the walk takes the INNERMOST row token (`M3.RT`) | 3.10 (1) |
| V3 | the unsized width reads `widths[cell.column]` (`M3.UW`) | 3.7 (3) |
| V4 | drop the single-count `Int32.max` check (`M3.6a`) | 3.6 (1) |
| V5 | `fx` ignores the anchor (`M3.AX`) | 3.3 (3), 3.4 (2), 2.13 (8) |
| V6 | the LAST column-alignment declaration wins (`M3.1`) | 3.1 (4), 2.13 (3) |
| V7 | a span is aligned by its first column's alignment (`M3.2`) | 3.2 (1), 2.13 (4) |
| V8 | the walk's unsized union becomes "the innermost replaces" (`M3.9b`) | 3.9 (5) |
| V9 | `columns > 1` relaxed to `columns >= 1` (`M3.5c`) | 3.5 (11) |
| V10 | stop the chain at `padding` (`M3.10`) | 3.10 (10), 3.5 (16), 3.4 (2), 3.9 (3), 3.6 (2) |
| V13 | drop the unsized HEIGHT branch in `serve` (`M3.UV`) | 3.7 (4), 3.9 (6), 2.13 (35) |
| V11 | **verifier's own**: `fx` falls back to the ROW's horizontal factor before the grid's | 3.3 (1), 2.13 (9), 3.12 (1) |
| V15 | **verifier's own**: the unsized-horizontal branch applies at a NIL width proposal too | 2.13 (4) |
| V12 | **verifier's own**: the token from the outermost mark, the ALIGNMENT from the innermost | **green** — `GR-AN` |
| V12b | the same after the fix | 3.10 (4: R4a, R4b) |
| V16 | **verifier's own**: `reset(generation:)` clears none of the three new mark tables | **green** — `GR-AO` |
| V16b/c/d | each of the three `removeAll` calls on its own, after the fix | `resetClearsGridCellAttributeMarks` (1 each); all three together, 3 |

V10 reddens more than `M3.10` recorded because the implementer's table was taken
before `c49fada` added 3.5's W arms and 3.6's arm (d); the tests named still
redden. V15 shows that "an unsized axis only bites where that axis's proposal is
non-nil" is held by the corpus (2.13) rather than by a named GU arm.

**The one green mutation is `GR-AN`**: `gridChildMarks` claims "the row token
**with its alignment** from the outermost mark", and only the token half was
pinned — R2, the one arm that marks a row at both ends of a chain, writes a nil
alignment at both ends. Proved non-equivalent with a scratch test (never
committed): the mutant moves the padded cell from y = 1 to y = 29. Probed with a
new five-arm probe
`docs/probes/swiftui-grid-row-alignment-inheritance.swift` (A0–A4, all
hand-derived before the run, all exactly as predicted, run twice
byte-identical): SwiftUI gives a flattened nested row's cells the **enclosing**
row's alignment, with a wrapper (A3 a (1,1), A4 a (1,29)) and without one (A2),
so the kernel was right and the coverage was missing. Pinned by arm **R4** of
test 3.10 (`c3868d9`); the suite stays at 1463.

**The second green mutation is `GR-AO`**: lane 3's three new mark dictionaries
on `LayoutTree` are cleared by `reset(generation:)`, and nothing read that.
`reset` reuses node indexes and `markNativeGridCell` writes only what it is
given, so a stale anchor, column alignment or unsized-axes mark is picked up by
the next generation's `newNativeGrid` — the shape `resetClearsGridCellColumnMarks`
and `resetClearsGridRowMarks` already pin for the span and the row token. Pinned
by `resetClearsGridCellAttributeMarks` (`68ff523`), three attributes each with a
stale arm and a `#require`d control; the suite goes to **1464**.

**Two citations that could not be followed, fixed in the same pass**: `GR-AM`
named a probe `swiftui-grid-chain-span-sum.swift` that does not exist (its arms
are the W group of `swiftui-grid-lane3-discriminators.swift`), and test 3.10's
header named a walk `gridAttributes(of:)` that does not exist (it is
`LayoutTree.gridChildMarks(_:)`).

**Demo, re-taken by the verifier.** `Sources/` is unchanged from `1630443` to
the verifier's head (both new commits are tests and docs), so this is the head's
comparison. `CN-R`'s harness (`gen-lib.py`,
`DEMO_PIXELS_SMALL=1`, default build system) in fresh `git archive`s of
`cb2e708` and `1630443`: **12 of 12 images 0 differing pixels, every scene dump
identical.** Controls on the head images, each reproducing the implementer's
figure: light vs dark f0 1 048 576; default vs modal (light) 1 030 498; default
vs animation (light) 210 027; preview light vs dark 1 048 576; f0 vs f3 0.
`grep -rn Grid Sources/MetalUIDemoContent Sources/MetalUIDemo`: no hits.

**Arm ids.** This round added **A0–A4** (the new probe) and test 3.10's **R4**;
`GR-` reaches **GR-AO**, so the next free ruling is `GR-AP`. The next free `GF`
is still GF21.

**No real window.** `docs/probes/appkit-screen-lock-state.swift` read
`CGSSessionScreenIsLocked = 1` and `displayAsleep main: 1` at the verifier
round, so `capture.sh` was not run; the only real-window reading for this lane
is the implementer's, above, including its launch-noise finding.

## Lane 4 — elements, identity and the pipeline (2026-09-21)

Base `920e2d6` (lane 3's verifier round), suite **1464**. Rulings delivered:
`GR-J`, `GR-K`, `GR-T`'s element half, `GR-V`, `GR-AD`'s three remaining
parameters, `GR-AE` (a grid in the preview) and `GR-AF` (identity, pinned wrong
on purpose), plus the dispositions `GR-AP` (eight departures from the spec's
table), `GR-AQ` (`GR-AC` item 3's mutation measured wrong), `GR-AR` (the preview
delta) and `GR-AS` (how a "marks after its content" clause must be mutated).

### Red first (`cdfdf54`)

The lane's tests were committed against lane 3's source, where they do not
compile. `swift build --build-system native --build-tests` reported **223
errors of eight distinct kinds** and no others:

| error | where |
|---|---|
| `cannot find 'Grid' in scope` | 34 in `GridElementTests`, 5 in `GridPipelineTests`, 4 in `GridTrapTests` |
| `cannot find 'GridRow' in scope` | 82, 7, 4 |
| `value of type 'Cell' has no member 'gridCellColumns'` | 19 |
| … `gridCellAnchor` / `gridColumnAlignment` / `gridCellUnsizedAxes` | 19 each |
| `extra argument 'anchor' in call` | `GridRegistrarTests.swift:61:92` |
| `extra argument 'columnAlignment' in call` | `:63:68` |
| `extra argument 'unsizedAxes' in call` | `:66:64` |
| `generic parameter 'some StringProtocol' could not be inferred` | 8, cascading on `#require` messages whose subexpressions did not typecheck |

**The four typecheck guards have no red-first reading at `cdfdf54`, and the
first version of this paragraph claimed one it could not have taken.** It said
the guards "are red at run time"; at `cdfdf54` the test target does not link at
all (the 223 errors above, independently rebuilt from a `git archive` by the
verifier), so no `@Test` in the target ran. What is true is only that their
FIXTURES are strings, which is why they contributed no compile error of their
own. Their red evidence is the head-side mutations **G1M–G4M** in the table
below, each of which the verifier re-ran on its own (G1 2 issues, G2 2 plus
`aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks` 2, G3 2, G4 2),
together with the `GRID GUARD 1..4` prints that say all four actually run rather
than skipping (`CI — what lapses silently`).

### Source (`f0e72b1`)

`Sources/MetalUI/Grid.swift`, appended below the lane-1 registrars:

- **`Grid<Content: ProposalElementGroup>: ProposalElement`** — SwiftUI's argument
  order, content numbered from 0 under its own id with a fresh cursor, one
  `requestNativeGrid` with both spacings mapped to `Double`; `prepaint` and
  `paint` forward once each and register and paint nothing of their own.
- **`GridRow<Content>: ProposalElementGroup`** — a group with its OWN identity
  level: `GlobalElementID.enteringGroupMember` for one cursor index and the
  `@State` bind (`MC-H`'s shared helper), a fresh inner cursor for the cells, and
  `markNativeGridRow` **after** the content registers so an enclosing row's mark
  overwrites an inner one (`GR-T`). Its untyped `requestGroupLayout` unwraps the
  typed entry's ids — not a copy, so there is nothing to pin separately. It has
  no node and records no bounds (`GR-K`).
- **`GridCellModifier<Content>` and `GridCellAttribute`** — layout- and
  identity-transparent (`EnvironmentScope`'s shape: no node, no index, `parent`
  and `cursor` forwarded), marking **every** node its content returns after it
  registers, with **one `markNativeGridCell` call per modifier**: a merged call
  would silently reverse the kernel's "the first mark on a node stands".
- `.gridCellColumns`, `.gridCellAnchor`, `.gridColumnAlignment` and
  `.gridCellUnsizedAxes` on `extension ProposalElementGroup`.
- `LayoutPass.markNativeGridCell` gains `anchor:`, `columnAlignment:` and
  `unsizedAxes:` (`GR-AD`'s note to lane 4), in the same change as
  `GridCellModifier` and with a `GridRegistrarTests` test per argument.

`Sources/MetalUIDemoContent/DemoContent.swift`: a two-row, two-column grid of
80×24 `Rectangle`s, its last cell a tappable `GridPreviewCell` component,
**appended to the preview's bottom `HStack`** (`GR-AR` says why, and why not the
`VStack`).

No `swift package clean` was needed (new types only, no stored property crossing
a module boundary), and none was taken; the build and suite were clean without
one.

**Suite: `Test run with 1492 tests in 1 suite passed after 50.747 seconds`**
(1464 + 27 lane tests + the registrar test), 0 `error:`, no `warning:` but
SwiftPM's `--build-system native` deprecation notice. Goldens **97**, `git diff
cb2e708 -- '*.json'` empty. Guards **75** (77 `canTypecheck` hits across fifteen
files, less `Typecheck.swift`'s declaration and `UnitSafetyTests`' comment);
`GridCompileGuards.swift` holds four.

A fourth commit (`12d4b28`) added the three arms spec §6 asks of
`everyModifierWrapperDelegatesEachPhaseExactlyOnce` — a `Grid`, a `GridRow`
outside a grid, a `GridCellModifier` — with no new `@Test`; the suite stays at
1492.

### How an arm is read (the element tests' convention)

A nil-proposal arm is wrapped in **`.fixedSize()`**, which proposes nil×nil to
the grid: a window root is proposed the content size, so without it every arm
would be the finite solve. An arm probed at a concrete proposal is the window
root at exactly that size. The window is the arm's answer **plus 20 on each
axis**, so `CN-J`'s centring offset is the integer 10 and a rect rounded
absolutely equals the probe's rect rounded relatively — which is why the
expected values are `roundLayout` of the probe's figures, `NativeGridTests`' `r`.
Cell rects come from each leaf's own `prepaint` bounds with the ROOT element's
origin subtracted; `.fixedSize()` adds no geometry, so the root's rect is the
grid's.

### Mutations

Committed first; each applied from a copy of the committed file, `git status
--short` showing exactly one modified file during and nothing after (checked on
all 25 runs); full unfiltered native suite each time. "Reddened" lists the tests
and their issue counts.

| # | mutation | reddened |
|---|---|---|
| M1 | `Grid` passes `horizontalSpacing` as `verticalSpacing` and back | 4.1 (4) |
| M2 | `GridCellModifier` drops its `.columnAlignment` case | 4.2 (15), 4.5 (1), 4.1 (1) |
| M3 | … drops `.anchor` | 4.2 (15), 4.5 (3), 4.1 (1) |
| M4 | … drops `.unsizedAxes` | 4.2 (15), 4.5 (3), 4.1 (4) |
| M5 | … drops `.columns` | 4.2 (15), 4.5 (4), 4.1 (3) |
| M6 | `GridCellModifier` marks only the FIRST node its content returns | 4.5 (3) |
| M7 | … marks a throwaway early registration as well as the real one | 4.2 (60), 4.5 (11), 4.1 (9), 4.10 (2) |
| M8 | … consumes a cursor index | 4.10 (1) |
| M9 | `GridRow` marks early **as well as** late | 4.10 (1), 4.9 (1), 4.9b (1), 4.9c (1) — **and NOT 4.4**: `GR-AS` |
| M9c | (verifier round) the KERNEL keeps the first row token and alignment instead of overwriting | 4.4 (8), lane 3's `consecutiveCellsOfOneRowTokenAreOneRowAndTheOutermostRowMarkWins` (9) — see the verifier round below and the amended `GR-AS` |
| M9b | `GridRow` marks early **instead of** late | 4.4 (12), 4.1 (44), 4.2 (45), 4.5 (17), 4.6 (10), 4.17 (3), 4.11 (2), 4.12 (1), 4.15 (1), 4.20 (1), 4.10 (1), 4.9/4.9b/4.9c (1 each) |
| M10 | `GridRow` forwards `parent` and `cursor` to its content | 4.8 (4), 4.20 (2), 4.9 (2), 4.10 (1) |
| M11 | `GridRow` registers a one-node `HStack` over its cells | 4.2 (75), 4.1 (24), 4.5 (9), 4.13 (6), 4.6 (4), 4.3 (3), 4.17 (3), 4.4 (2), 4.7 (2), 4.20 (1) |
| M12 | an empty `GridRow` registers an empty `ZStack` as its cell | 4.7 (2) |
| M13 | `Grid.prepaint` delegates twice | `everyModifierWrapperDelegatesEachPhaseExactlyOnce` (2), 4.19 (1) |
| M14 | `Grid.paint` delegates twice | 4.18 (1), the delegation test (2) |
| M15 | `GridRow.prepaintGroup` records bounds of its own | 4.20 (2) |
| M16 | `LayoutPass.markNativeGridCell` forwards `anchor: nil` | the registrar test (1), 4.2 (15), 4.5 (3), 4.1 (1) |
| M17 | … `columnAlignment: nil` | the registrar test (1), 4.2 (15), 4.5 (1), 4.1 (1) |
| M18 | … `unsizedAxes: []` | the registrar test (1), 4.2 (15), 4.5 (3), 4.1 (4) |
| M19 | `markNativeGridRow` reuses one token for every row | 800 issues across 43 tests, 4.6 among them (5) |
| M20 | `NativeLayoutRun.maxDepth` 200 (+112) | **4.21 (5, one per kind)**, `aChainOf88GridsTraps` (2), `aLoweredChainOneLevelPastTheNativeDepthLimitTraps` (2) |
| M21 | `NativeLayoutRun.maxDepth` 128 (+40), the spec's own mutation | `aChainOf88GridsTraps` (2), `aLoweredChain…` (2) — **4.21 stays green**: `GR-AQ` |
| M22 | `nativeGridCellRects` places every cell at its SLOT | 517 issues across 40 tests, 4.14 among them (1), 4.18 (1), 4.17 (1) |
| M23 | the disabled gate dropped (`Frame.registerHandlers`' `enabled`, shared file) | 64 issues across 19 tests, 4.19 among them (1) |
| M24 | `ModifiedContent.nativeWrapperNode`'s `count == 1` relaxed to `>= 1` (shared file) | 4.13 (4) |
| M25 | `OnTapModifier`'s the same (shared file) | 4.13 (2) |
| G1M | a legacy `Grid` init overload `where Content == Rectangle` | guard G1 (2) |
| G2M | a `leading` case on `VerticalAlignment` | guard G2 (2), `aHorizontalCaseIsNotAnHStackAlignmentNorAVerticalCaseAVStacks` (2) |
| G3M | `gridColumnAlignment` takes a `ProposalAlignment` | guard G3 (2) |
| G4M | a public `UnitPoint` and a `gridCellAnchor(_: UnitPoint)` overload | guard G4 (2) |

(Test numbers are spec §6's lane-4 table; "the registrar test" is
`markNativeGridCellForwardsItsOtherAttributesToTheKernel`.)

**No mutation left the suite green**, and two are findings rather than
confirmations:

- **M9 vs M9b** (`GR-AS`, amended by the verifier round below): marking early
  *and* late does not move the ordering rule at all — the late mark still
  overwrites — so the four tests it reddens are reddened by the double
  registration, not by the order. Only replacing the late mark discriminates on
  the ELEMENT side, and it does so broadly. **M9c shows the rule itself is
  narrowly mutable from the KERNEL side**, so the round's conclusion that such a
  clause is "only mutable by MOVING the mark" was too strong.
- **M21** (`GR-AQ`): `GR-AC` item 3's stated mutation, `maxDepth + 40`, reddens
  **nothing in 4.21**. At 128 the chains are 127 nodes and 127 is exactly the
  one-child vertical stack's 1 MB ceiling — the binding kind survives by one
  level and every other kind by 27 or more. The effective mutation is `maxDepth
  = 200`, above the largest ceiling (padding's 194).

**M7 and M9b are stand-ins, and that is itself a finding.** "Mark before the
content registers" cannot be written straight: the marks need the nodes, which
only the content's registration produces. Both mutants register the content a
second time into a throwaway and mark that, which also duplicates `@State` binds
and nodes — so their issue counts are wider than the clause they test. Lane 3
met the same shape with its `Int32.max` clamps (`GR-AL` item 3).

### Demo

`CN-R`'s harness rebuilt in scratch (the scratchpad `gen-lib.py` of lanes 1–3 is
not in the tree; this is a fresh `ZZDemoPixels.swift` generated into a `git
archive` of each commit, `@testable import MetalUIDemoContent`, a real `Window`
over `FakePlatformWindow`, raw RGBA plus a scene dump, twelve images). **Its
controls reproduce §18's figures exactly**, which is what says it is the same
instrument: light vs dark f0 **1 048 576**, default vs modal light **1 030 498**,
default vs animation light **210 027**, preview light vs dark **1 048 576**, f0
vs f3 **0**, and `default-light-f0` has **544** distinct pixel values.

`git archive`s of `cb2e708` and `12d4b28`. (`12d4b28` is the last commit that
changes rendering: the docs commit after it touches only two source DOC
COMMENTS and the three track documents, so this is the head's comparison.)

| image | differing pixels | bbox | scene |
|---|---|---|---|
| the eight legacy 1024 images (default/modal/animation × light/dark, default also at f3) | **0** | — | identical |
| `small560-default-light` | **0** | — | identical |
| `preview-light`, `preview-dark` | **7 680** each | (624, 865)–(795, 920) | +4 rects |
| `small560-preview-light` | 52 033 | (0, 63)–(559, 497) | see below |

**The 1024 preview delta is exactly the grid** (`GR-AE`'s requirement): the box
is 172 × 56, the grid's own answer; 7 680 = 4 × 80 × 24, its four cells; the
scene dump gains exactly four rects — (624, 865), (716, 865), (624, 897),
(716, 897), each 80 × 24 — **and no existing rect moves**.

**The 560 preview moves wholesale, and the scene dump explains all of it**
(`GR-AR`): at 560 the preview root already overflows (696 × 604 in a 560² window)
and a native root is centred (`CN-J`), so widening it by 184 shifts everything
left by 92. Every base rect has a head counterpart at exactly `x − 92` except
five — the three backgrounds that widen with the root, the trailing
`PriorityPreviewPanel` (flexible, 36 → 220 wide) and the final overlay — plus the
four new cells. Nothing unexplained.

### The real window

The screen was **unlocked**: `docs/probes/appkit-screen-lock-state.swift` printed
no `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`,
`preflightScreenCaptureAccess: true`. `docs/probes/window-capture/capture.sh
<dir> cb2e708 12d4b28`:

| pair | reading |
|---|---|
| `cb2e708` default, twice 1.5 s apart | 0 |
| `cb2e708` preview, twice | 0 |
| head default, twice | 102 614, bbox (0, 0)–(1839, 55) — lane 3's launch-noise band |
| head preview, twice | 0 |
| **`cb2e708` → head, default window** | **0** |
| **`cb2e708` → head, preview window** | **30 720, bbox (1248, 900)–(1591, 1011)** |
| control, default vs preview at head | 921 071, bbox (0, 15)–(1839, 1175) |

The preview box is 344 × 112 device pixels at scale 2 = **172 × 56 points**, the
grid's answer, and 30 720 = 4 × 160 × 48 = its four cells at scale 2. The
offscreen harness and the real window agree to the pixel on what moved.

The head's default window failed the harness's own precondition once (102 614 in
the bottom 28 points), which is exactly the per-launch band lane 3 chased and
reported; the cross-commit reading for that same window is 0, so the band did not
enter it.

### For the integrator

Lane 4 does not edit CLAUDE.md, AGENTS.md, the plan or `docs/record/README.md`.
What this stage owes them:

1. **CLAUDE.md's vocabulary** (the proposal-path section): the proposal types
   gain **`Grid(alignment:horizontalSpacing:verticalSpacing:)`**,
   **`GridRow(alignment:)`** and the four cell modifiers
   `.gridCellColumns(_:)`, `.gridCellAnchor(_:)`, `.gridColumnAlignment(_:)`,
   `.gridCellUnsizedAxes(_:)`; the kernel types gain **`ProposalAxes`**. A
   `GridRow` is the one proposal GROUP with an identity level of its own (one
   cursor index, cells numbered under it); a `GridCellModifier` is transparent
   like `EnvironmentScope`.
2. **The registrar counts**: `LayoutPass` and `LayoutTree` each have **13**
   `requestNative*` / `newNative*` registrars, plus **two mark functions each**
   (`markNativeGridRow`, `markNativeGridCell`).
3. **The divergence table** gains `GR-O`'s items — SwiftUI's span overflow not
   ported (2.9), the model's residual disagreements (2.9, 3.12),
   `gridCellColumns(0)` as 1 (3.11), nine-point anchors (guard G4), `Text` rows
   at 8 rather than 0 (4.12), every proposal modifier on a multi-cell `GridRow`
   trapping (4.13), a column count above `Int32.max` trapping (3.6), the stack's
   infinite-flexibility tie (NOT grid-specific, task 6's), **a vanishing `if`
   inside a grid moving the cells after it** (4.9b, 4.9c) and a runnable column
   count still being unallocatable (3.13).
4. **The inert table** gains `markNativeGridRow(alignment:)`'s horizontal factor
   and `markNativeGridCell(columnAlignment:)`'s vertical factor; grid marks on a
   node that never sits under a grid, and a `GridRow`'s alignment or a
   `GridCellModifier` written outside a `Grid`; and
   `NativeGridSolution`'s bookkeeping counter. **`ProposalAxes` is NOT inert** —
   lane 3 gave it both a writer and a reader (`GR-O` says so itself).
5. **CLAUDE.md's human-verification table gains an OPEN row** (`GR-AE`, owned by
   plan task 15's closeout, `GR-N`), worded:

   > the proposal preview's grid (`METALUI_NATIVE_LAYOUT_PREVIEW=1`): two rows
   > and two columns of 80×24 cells at the right of the bottom row, the last
   > cell changes colour on click and lights on hover, and nothing else on the
   > preview moved | **open, nobody has looked at a grid on screen.** The
   > offscreen and real-window captures both read the delta as exactly those
   > four cells (record §20, lane 4), which is not a look.

6. **Design §4.1 row G** should be marked built, and `GR-L`'s proposed **stage
   G2 — lazy grids** (after stage 4) added to that table and to the plan's task 7
   note.
7. **`swift package clean` before the merged suite** (`GR-A`): both tracks add
   stored properties to public classes that cross a module boundary.
8. **Counts to re-take after that clean**: this track alone reads 1493 tests, 97
   goldens, 75 guards (1492 at `12d4b28`, plus the verifier round's test 4.10b).

### Deferrals

Nothing new from lane 4. Carried: `GR-N`'s table in full — lazy grids to stage
G2, `UnitPoint` anchors and SwiftUI's font-derived 0 between `Text` rows to task
11, a modifier distributing over a multi-cell `GridRow` and `.id()` on
`Grid`/`GridRow` to task 8, proposal-path accessibility to task 12, the model's
residual disagreements to task 15, `CN-B`'s stack tie to task 6, `SA-L`'s 0.60
margin to `LR-Q`'s stage 6b re-bisection, and the human look at a grid to task
15's closeout.

**One thing lane 4 measured and did not fix**: how little room `GR-AC` item 2's
breach leaves. `SA-L` wants `maxDepth` ≤ 0.60 × the smallest 1 MB debug ceiling;
the smallest is the one-child vertical stack's **127**, so the rule gives 72 and
`maxDepth` is 88 — a ratio of 0.693. M21 measures the practical consequence:
raise `maxDepth` to 128 and 4.21's stack arm survives by exactly one level (127
completes, 128 dies), so the headroom between "the guard admits the tree" and
"the stack overflows" is **40 levels**, not the 0.60 rule's ~46%. Owner unchanged
(`LR-Q`'s stage 6b re-bisection, `GR-N`).

### Verifier round (lane 4)

The verifier re-took the whole of lane 4 at `687f074` and found the suite, the
goldens, the guard count, the red-first reading, the probe re-run, the offscreen
demo comparison and the real-window capture all reproducible — including `GR-AR`'s
560 explanation term for term and `GR-AQ`'s M21 finding. It raised **one major
and three minors**, and ran **five mutations of its own** (V1–V5). Three of those
were green, which is what the major and the first minor are.

| verifier mutation | suite | disposition |
|---|---|---|
| **V1** — `Grid.requestProposalLayout` passes `.center` instead of its own `alignment` | **green** | the major: fixed below |
| **V2** — `Grid` numbers its content from cursor 1 | 4.8 (4), 4.10 (1) | already pinned |
| **V3** — `GridRow`'s UNTYPED `requestGroupLayout` returns no nodes | **green** | minor 1: fixed below |
| **V4** — `GridCellModifier`'s the same | **green** | minor 1: fixed below |
| **V5** — `GridRow` marks with `alignment: nil` | 4.4 (2), 4.1 (1) | already pinned (and the sibling hop V1 was not, which is what found the major) |
| **M9c** — the KERNEL's `markNativeGridRow` keeps the FIRST token and alignment written on a node | 4.4 (8), lane 3's row-token test (9) | the finding behind minor 3 |

#### The major: the `Grid` element's own `alignment` was unpinned (fixed)

`requestNativeGridForwardsItsAlignmentToTheKernel` pins the `LayoutPass` →
kernel hop and `GridRow`'s element → `LayoutPass` hop is pinned by V5, but
nothing reached `Grid`'s. Every arm of test 4.1 used the default `.center`, and
`grep -n "Grid(" Tests/MetalUITests/Grid*.swift` found exactly one non-default
construction in the tree — GA3's spacings. This is the obligation lane 1's
verifier handed to lane 4 ("For lane 4", item: *a non-centre grid alignment … each
reached through `LayoutPass`, with a mutation dropping the forwarding*); it was
neither delivered nor listed among `GR-AP`'s departures.

**Fix** (`ddf66ec`): test 4.1 gains probe arm **GL1** —
`Grid(alignment: .topLeading)` over GA1's four leaves in GA1's own window —
whose expected rects are the probe's, `size 78x58 | a (0,0 30x10) |
b (38,0 20x20) | c (0,28 10x30) | d (38,28 40x10)`. **GA1 is its discriminating
control**: the same leaves under `.center` put `a` at y 5 and `b` at x 48, so the
two arms disagree on both axes.

Re-taking **V1** against it: `Test run with 1493 tests in 1 suite failed … with 4
issues`, all four `gridAndGridRowLayOutAsTheProbeReadsThroughTheElementAPI`, at
`GridElementTests.swift:169–172` — GL1's four rects and nothing else.

#### Minor 1: both untyped group entries were unpinned (fixed)

`GridRow`'s and `GridCellModifier`'s untyped `requestGroupLayout` shims each
return `nodes.map(\.layoutNodeID)` over the typed entry. The lane recorded of the
first that it is "not a copy — there is nothing here to pin separately (`MC-H`)",
which is true of DRIFT and says nothing about REACHABILITY: `ProposalElementGroup`
refines `ElementGroup`, so a legacy builder group calls them, and V3/V4 showed
either can return `[]` with all 1492 tests green.

**Fix** (`ddf66ec`): test **4.10b**,
`theUntypedGroupEntriesOfARowAndACellModifierForwardEveryCellNode`, calls each
untyped entry directly, `try #require`s the node count (shape 13 — so a dropping
shim fails there rather than trapping later inside `requestNativeGrid` and
truncating the run) and reads the marks those ids carry through a grid built from
them: arm 1 both cells `isRowCell`, arm 2 both spans 2 through
`.gridCellColumns(2)` on the row.

Re-taking **V3** and **V4** against it: each gives `1 issue`, the new test's
`nodes.count == 2` at `GridElementTests.swift:1072`, and nothing else.

#### Minor 2: the red-first paragraph claimed a reading it could not have taken

Corrected in place above: at `cdfdf54` the test target does not link, so the
guards' red evidence is G1M–G4M at the head, not a run-time reading.

#### Minor 3: `GR-AS` was stronger than what was measured

`GR-AS` concluded that a "marks after its content" clause is *only* mutable by
moving the mark. The verifier's **M9c** mutates the kernel instead —
`markNativeGridRow` keeps the first token and alignment written on a node rather
than overwriting, reversing `GR-T`'s "the outermost row wins" with **no double
registration** — and gets a narrow 17 issues in exactly two tests. Re-taken here:
`Test run with 1493 tests in 1 suite failed … with 17 issues`,
`aGridRowInsideAGridRowFlattensWithTheOutermostAlignment` (8) and
`consecutiveCellsOfOneRowTokenAreOneRowAndTheOutermostRowMarkWins` (9) — no
collateral, against M9b's twelve-test spread. `GR-AS` is amended accordingly: the
ordering RULE is narrowly pinned; what cannot be mutated in isolation is the
ELEMENT-side placement of the call.

#### Suite, goldens, guards, demo

`Test run with 1493 tests in 1 suite passed after 50.054 seconds` (1492 + test
4.10b; GL1 is an arm, not a `@Test`), 0 `error:`, no `warning:` but SwiftPM's
deprecation notice. Goldens **97**, `git diff cb2e708 -- '*.json'` empty. Guards
**75**, unchanged — this round adds no typecheck guard. `git status --short` was
empty before and after each of the four mutation runs.

**No demo comparison was re-taken, and none is owed**: `git diff 687f074 -- Sources/`
is empty, so every rendered pixel is the one `12d4b28`'s comparison and the
`cb2e708 → 12d4b28` real-window capture above already read. This round changes
`Tests/` and the three track documents only.
