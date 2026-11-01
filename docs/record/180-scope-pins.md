# 180 — Scope pins (`ES-K`, round-3 R3-7)

2026-10-31, branch `test/scope-pins` from master `519a1ebe`. Request: the test pins the scope-decoration work (records 168, 169, 172) left owed.

## What changed

- **ES-J probe.** `docs/probes/swiftui-geometry-decorations.swift` (new; header carries the recorded output, SA-O). It ran on this Mac with the screen **locked**: the hosted window laid out and reported all the same,
  so nothing was lost. D1/D2/D3/D4: a `.padding(8)`, `.background` or `.frame(100 x 100)` AFTER `.onGeometryChange` reports 50 x 50; the same `.padding`/`.frame` BEFORE reports 66 x 66 / 100 x 100 (`.background` before: 50 x 50).
  D5/D5b: an `.offset(x: 10)` after moves the reported global minX (10), before it does not (0). D6/D6b: a `.padding(8)` after moves it in (8), before it does not (0). SwiftUI agrees with `ES-J`'s assumption:
  no fix, no divergence (955-964 untouched).
- **`style`/`elementID` forwards** (mutations 5, 6): observable after all, through the public protocol requirements; pinned for all ten scopes.
- **`.onOpenURL` owner by id**: pinned through an erased named element.
- **A defect**: the seven forwarding scopes answered `Element`'s default `nil` for `elementID` when entered as an element (the `StyledElement`-constrained getter cannot witness the wider `Element` requirement). Found by
  the owner pin; fixed by `public var elementID: ElementID? { content.elementID }` in each `Element` extension (`EnvironmentScope.swift`, `Lifecycle.swift`, `Presentations.swift`, `Toolbar.swift`,
  `ModifierKeysChange.swift`, `GlassContainer.swift`, `TransitionGroup.swift`). The layered three still answer `nil` (carried).
- Docs: `ES-K` in the decisions doc (next `ES-L`), the prefix row, the identity-state shard, rows 5/6 of the mutation table corrected in place, dated correction notes appended to records 168, 169 and 172.

## Tests

`Tests/MetalUITestingTests/ScopeForwardTests.swift` (new): `aStyleWrittenThroughAForwardingScopeReachesTheContent`, `anIdentifierWrittenThroughAForwardingScopeNamesTheContent`,
`aStyleAndAnIdentifierWrittenThroughALayeredScopeReachTheLayer`, `aNamedElementKeepsItsNameThroughAScopeWhenErased`. `Tests/MetalUITests/OpenURLTests.swift`:
`anOnOpenURLOnAnErasedElementIsOwnedByTheScopesOwnId`. `Tests/MetalUITests/GeometryScopeDecorationTests.swift`: `aPaddingAndAFrameAfterOnGeometryChangeAreOutsideTheMeasurement` (pins SwiftUI's numbers; no
scope mutation reddens it, said so in its doc comment).

## Mutations

Rows 31-36 of the decisions doc: every named mutation reddened its named tests (7 of 7 forwarding scopes for rows 31, 32, 34; 3 of 3 layered for row 33).

## Counts

`swift package clean`, `swift build --build-system native --build-tests`, then an unfiltered `swift test --build-system native --no-parallel` (screen locked; the AppKit sheet tests skip by themselves, `TK-A`):
**4671 tests in 12 suites passed**, 0 issues, `FR-J no-argument frame: succeeded=true`. Master's 4635 (CLAUDE.md line, which this record does not edit) plus the six new tests here; the rest is master's own growth since that line was taken. Guards not re-tallied.
Both closeout scripts print nothing.
