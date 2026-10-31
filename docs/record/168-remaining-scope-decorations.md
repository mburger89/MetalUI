# 168 — Decorations after the remaining scopes (`ES-D`…`ES-G`)

2026-10-31, branch `fix/remaining-scope-decorations` from master `c686d1ef`. Follow-up to record 167: "convert the remaining scopes too". The single-content modifier scopes record 167 left (`TransactionScope`,
`TransitionGroup`, `ModifierKeysScope`, `CoordinateSpaceScope`, `GlassTagScope`) are each ruled, by measuring a decoration written after the scope against the same decoration written before it.

## What changed

- `ES-D`: `ModifierKeysScope` (`.onModifierKeysChanged`) and `GlassTagScope` (`.glassEffectID`, `.glassEffectUnion`) take ES-A's `Element`/`StyledElement` conformances and ES-C's `id(_:) -> IdentifiedGroup<Self>`.
  Neither reads its content's geometry or decoration (the glass tag is read only by the typed `glassEffect`'s container registration, which a legacy decoration never makes, `LG-U`).
- `ES-E`: `TransitionGroup` (`.transition`) the same. Measured: a background after `.transition(.opacity)` fades in at alpha ½ half-way, as the background before does. Inert on the `Element` path (no conditional
  inserts a window root).
- `ES-F`: `CoordinateSpaceScope` refused. Measured with a temporary conformance: `.coordinateSpace(.named("outer")).offset(x: 7, y: 9)` on a legacy `Box` read its leaf at (7, 9) in the space, the same as the
  offset written before; SwiftUI's G3 reads (0, 0).
- `ES-G`: `TransactionScope` refused. Measured with a temporary conformance: a `.background` after `.animation(linear(1), value:)` painted the mid colour half-way, the same as the background written before;
  SwiftUI's T3b snaps the modifier written after.
- Divergence 120 re-scoped: it now names `.onGeometryChange`, `.coordinateSpace` and `.animation(_:value:)`/`.transaction` (178 live, unchanged). Shard rule, prefix row (`ES-H` next), migration row updated.

Rulings, measurements and mutations are in `docs/superpowers/2026-10-31-scope-decorations-decisions.md`.

## Tests

- `Tests/MetalUITests/ScopeDecorationCompileGuards.swift`: `decorationsChainAfterTheRemainingForwardingScopes` (positives, roots, an unannotated `.id` assigned to `IdentifiedGroup`), `aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile`
  (three negatives with a before-spelling control).
- `Tests/MetalUITests/RemainingScopeDecorationTests.swift`: `aBackgroundAfterATransitionTransitionsWithTheContent`, `aTransitionAtTheRootIsInertAndKeepsItsDecoration`, `aGlassUnionTagKeepsTaggingWithADecorationAfterIt`.
- `Tests/MetalUITestingTests/ScopeDecorationTests.swift`: `aModifierKeysScopeTakesAnIdentifierAndAClickAfterIt`, `aModifierKeysScopeAtTheRootStillReports`, `aTransitionTakesAnIdentifierAndAClickAfterIt`.

## Counts

Native build (incremental, not after `swift package clean`), `swift test --build-system native --no-parallel --skip AppKitPresentationTests` (the screen lock could not be read: `Quartz` is not importable
here, so the presentation tests were skipped as in record 167): **4609 tests passed** (4601 + the 8 new), `FR-J no-argument frame: succeeded=true`. Guards 285 (283 + the two new in
`ScopeDecorationCompileGuards.swift`, from the diff). The full run found no `ES-C`-type twin for the three new forwarding scopes (no test reddened). The guard's `.id` arm was respelled after that run (mutation 8)
and re-run alone, green. Both closeout scripts print nothing.

## Mutations

Rows 7-15 of the decisions doc's table; every one reddened its named test once row 8's arm was respelled (its first spelling reddened nothing).
