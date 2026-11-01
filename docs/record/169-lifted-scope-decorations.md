# 169 — Decorations after `.coordinateSpace` and `.animation(_:value:)`/`.transaction` (`ES-H`, `ES-I`)

2026-10-31, branch `fix/lift-es-f-g` from master `d2797c5d`. Request: "lift ES-F and ES-G too" — the two scopes record 168 measured and refused, because forwarding a decoration onto their content put it
inside the space or the transaction, where SwiftUI's modifier written after them is outside.

## What changed

- `ES-H`: `CoordinateSpaceScope` and `TransactionScope` are `StyledElement where Content: StyledElement`, but their accessors configure a `.padding(0)` `ModifierLayer` of the scope's own (`outer`), created
  by the first decoration written after the scope. A scope holding one runs every phase as `ModifiedElement<Self>` over itself without the layer, i.e. exactly `.coordinateSpace(s).padding(0).offset(…)`,
  which already wrapped the scope. The layer's effects are open when the space is built (the space moves with an `.offset` after it, G3), and its style and colours resolve outside the scope's transaction
  (a `.background` after `.animation(_:value:)` snaps, T3b). Undecorated scopes are unchanged. Each keeps `ES-C`'s `id(_:) -> IdentifiedGroup<Self>`.
- `ES-I`: both scopes are `Element where Content: Element` (window root, `Deferred`, `List` row) with `ScopeLayerState` element states; a decorated scope's typed entry takes the untyped layer path
  (unreachable today: no proposal content is a `StyledElement`). An undecorated `.coordinateSpace` at a window root equals `.global` and its push is unobservable (mutation 20).
- Divergence 120 narrowed back to `.onGeometryChange` alone (178 live, unchanged); `ES-F`, `ES-G` marked lifted; shard rule, prefix row (`ES-J` next), migration row updated.

Rulings, measurements and mutations 16–25 are in `docs/superpowers/2026-10-31-scope-decorations-decisions.md`.

## Measurements

The leaf (40 x 20) in a legacy `Box`: `.coordinateSpace(.named("outer")).offset(x: 7, y: 9)` reads (0, 0) in the space, the offset before reads (7, 9), the global frame moves (7, 9) against the undecorated
twin, in a column and as the root. A 60 x 30 tile whose own background and an after-background both go surface to accent: half-way through `linear(1)` the outer rect is exactly accent and the inner neither
colour, under `.animation(_:value:)` (column and root) and `.transaction` (column). Under the naive forwarding (record 168's temporary conformance, mutations 16, 17) the space arms read (7, 9) and the
transaction arms paint one mid-way rect.

## Tests

- `Tests/MetalUITests/LayeredScopeDecorationTests.swift`: `anOffsetAfterACoordinateSpaceMovesTheSpaceWithTheView`, `aBackgroundAfterAnAnimationSnapsWhileTheContentAnimates`,
  `aBackgroundAfterATransactionIsOutsideIt`, `anAnimationScopeAtTheRootStillAnimates`.
- `Tests/MetalUITestingTests/ScopeDecorationTests.swift`: `identifiersAndClicksAfterACoordinateSpaceAndATransactionLand`.
- `Tests/MetalUITests/ScopeDecorationCompileGuards.swift`: the negative `aDecorationAfterACoordinateSpaceOrATransactionStillDoesNotCompile` replaced by the positive
  `decorationsChainAfterACoordinateSpaceAndATransaction` (decorations, roots, unannotated `.id` assigned to `IdentifiedGroup`); `ES-B`'s `.onGeometryChange` negative untouched.

## Counts

`swift package clean`, native build, `swift test --build-system native --no-parallel --skip AppKitPresentationTests` (screen possibly locked; skipped as in records 167, 168): **4614 tests passed**
(4609 + 6 new − the retired negative guard), `FR-J no-argument frame: succeeded=true`. Guards 285 (one negative replaced by one positive, from the diff). Both closeout scripts print nothing.

## Correction, 2026-10-31 (record 180, `ES-K`)

Mutations 5 and 6 (the `style` and `elementID` forwards) were recorded as reddening nothing and "unobservable". That was wrong: `StyledElement.style` and `.elementID` are public requirements, and writing them through a scope in a stack
sizes and names its content. They are pinned for all ten scopes (`ScopeForwardTests`), and rows 5 and 6 of the decisions doc are corrected in place. The same work found that a scope entered as an element lost its content's
name (`Element`'s default `nil` answered), fixed for the seven forwarding scopes.
