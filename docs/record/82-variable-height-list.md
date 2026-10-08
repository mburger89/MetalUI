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
