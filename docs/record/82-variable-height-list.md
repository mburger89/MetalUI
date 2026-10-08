# 82 — Variable-height `List`

Branch `feat/variable-height-list` from `70ed000`. User request 2026-10-02,
item 7 of the gpui-gap priority list (not a plan task). Spec
`docs/superpowers/specs/2026-10-08-variable-height-list-design.md`; rulings
`docs/superpowers/2026-10-08-variable-height-list-decisions.md` (`VL-`).
Divergence labels reserved for this branch: 145–149.

## §1 Design session (2026-10-08)

- **Probe** `docs/probes/swiftui-variable-height-list.swift` (new), run in both
  SA-O forms, byte-identical 23 lines, screen unlocked. SwiftUI's `List` sizes
  a row from its content at the list's width plus 8 points of insets, floored
  at 24 (`V0`…`V3b`); estimates unrealised rows at the constant 24 (`R2`);
  lands `scrollTo` onto an unrealised row exactly (`T`); ignores an off-screen
  row's content change (`A1`/`A2`/`A4`); does not anchor an insertion above
  the top (`A3`, 24 points); a non-lazy `ScrollView` does not anchor (`A6s`,
  the separating arm); `List(_:rowContent:)` and both selection overloads
  compile (`S1`).
- **gpui** `crates/gpui/src/elements/list.rs` read from upstream (not run):
  `SumTree<ListItem>` of `Unmeasured`/`Measured`, `ListOffset { item_ix,
  offset_in_item }`, `splice`/`reset`, `overdraw` — `VL-G`'s anchoring idea.
- **Rulings** `VL-A`…`VL-M` (next unused `VL-N`); divergences 145, 146, 147
  proposed (rows land in lane 3); divergence 84 to be amended.
- **Baseline** at `70ed000`: native build clean; **2672 tests in 3 suites**
  passed, `FR-J no-argument frame: succeeded=true` (spec §0.1).

## §2 Critic pass (2026-10-08)

- **Probe re-taken** in both `SA-O` forms, screen unlocked: byte-identical
  between the forms and to the recorded 23 lines, exit 0. Two labels
  corrected in its header (output unchanged): `A2`'s row 98 was **not**
  realised (98:24 where a measured row reads 88), and `A6s` reads only the
  clip — `A3` is the arm that reads a row move. What SwiftUI does when a
  *realised* row above the viewport changes height is unprobed: no divergence
  is claimed for `VL-G` items 1–2 (`VL-N`).
- **Defects fixed** (rulings `VL-O`…`VL-R`, folded into the spec): the
  anchor row removed by a data change had no rule (`VL-O`, test 2.7b, two
  arms); `forgetMeasurements` keeps ids (`VL-O`); the carried `scrollTo`
  refinement could not learn its request's scope or anchor — lane 1 widens
  `Frame.unresolvedScrollRequests(enclosing:)`, `ListLeadReveal` gains only
  `refined` (`VL-P`, test 1.15); `ListRows.swift` and `VariableRowsLayout`
  move to lane 1 with three direct layout tests (`VL-Q`, 1.16–1.18); four
  mutations that could not redden or would truncate the run replaced, exact
  frame counts, divergence 147 pinned at the list level, index work pinned in
  the non-gated performance test, an animation pin (2.7c), lane 2 runs the
  demo-pixel comparison and the env-gated 100k tests (`VL-R`).
- **Rejected** (`VL-S`, and `VL-Q`'s last paragraph): off-screen
  invalidation on a datum change, an `A` inventory row, a splice API now,
  parallel lanes inside this worktree.
- Next unused id `VL-T`.
