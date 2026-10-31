# 172 — Decorations after `.onGeometryChange` (`ES-J`); divergence 120 retired

2026-10-31, branch `fix/lift-es-b` stacked on `fix/lift-es-f-g` at `7462b8cd` (record 169, PR #156). Request: "lift ES-B too". Records 170 and 171 are claimed by other in-flight branches.

## What changed

- `ES-J`: `GeometryChangeScope` takes `ES-H`'s mechanism — a `StyledElement` over a `StyledElement` whose accessors configure a `.padding(0)` `ModifierLayer` of its own, a decorated scope running as
  `ModifiedElement<Self>` over itself without the layer; an `Element` over an `Element` (window root, `Deferred`, `List` row) noting the element's node, owned by the element's id; ES-C's `id` member. The
  layer's effects are open when the scope notes and the size noted is the content's, so a decoration after it is outside the measurement.
- `ES-B`'s premise was half wrong: a `.padding` after the scope is an `ElementGroup` wrapper and was outside under forwarding too; what forwarding gets wrong is an `.offset` after the scope, which opened
  inside the content after the note, so the reported global frame did not move where SwiftUI's G4a moves it.
- Divergence 120 retired (177 live, next label 209). Stale "divergence 120" sentences fixed in `docs/rules/app-shell.md`, `identity-state.md` (lifecycle paragraph), `input-focus.md`, and the doc comments of
  `View.toolbar` (`Toolbar.swift`) and `WindowPreferences.swift`. Shard rule, prefix row (`ES-K` next), migration row updated.

## Measurements

SwiftUI side: G4a (`docs/probes/swiftui-key-focus.swift`) — `.offset(x: 10)` after `.onGeometryChange` moves `frame(in: .global).minX` 0 → 10. No arm separates a `.padding`/`.background` after the scope
from one before; that it is outside the measured size is recorded as an assumption (`ES-J`). MetalUI: a 50 x 50 tile, one per window — offset after reads the plain frame + 10, offset before reads the plain
frame, both 50 x 50; padding(8) and a background after report 50 x 50, padding(8) before 66 x 66; at a window root the plain scope reports and an offset after moves the report by 10. Naive forwarding
(mutation 26) reddens the two offset pins.

## Tests

- `Tests/MetalUITests/GeometryScopeDecorationTests.swift`: `anOffsetAfterOnGeometryChangeMovesTheReportedFrame`, `aDecorationAfterOnGeometryChangeDoesNotChangeTheReportedSize`,
  `onGeometryChangeAtTheRootReportsAndTakesAnOffsetAfterIt`.
- `Tests/MetalUITestingTests/ScopeDecorationTests.swift`: `anIdentifierAndAClickAfterOnGeometryChangeLand`.
- `Tests/MetalUITests/ScopeDecorationCompileGuards.swift`: `aDecorationAfterOnGeometryChangeStillDoesNotCompile` replaced by the positive `decorationsChainAfterOnGeometryChange` (decorations, a root,
  unannotated `.id` assigned to `IdentifiedGroup`); `GeometryTimelineCompileGuards.swift`'s divergence-120 negative arm became a positive line.

## Counts

`swift package clean`, native build, `swift test --build-system native --no-parallel --skip AppKitPresentationTests` (screen possibly locked; skipped as in records 167–169): **4618 tests passed**
(4614 + 4 new tests; the retired negative guard replaced by one positive), `FR-J no-argument frame: succeeded=true`. Guards 285 (from the diff). Both closeout scripts print nothing (the inventory map's
`geometry-change`, `lifecycle`, `presentation-scope` and `toolbar` families dropped label 120; `presentation-scope`, left with no label, is reclassed D → M). Two source doc comments
(`Toolbar.swift`, `WindowPreferences.swift`) were edited mid-build; the counted run built after the edit.

## Mutations

Rows 26–30 of the decisions doc's table.
