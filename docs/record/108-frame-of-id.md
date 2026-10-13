# 108 — `frame(ofID:)` on proposal `.id`, retired labels in guides, `DG-P` dropped

Branch `fix/frame-of-id` from `d279f34d`. **Not a plan task**: item C30 of the gpui-gap list (found by 10b and 10c,
records §103 and §107 `DG-T`, `DG-U`, `DG-P`). Spec `docs/superpowers/specs/2026-10-13-frame-of-id-design.md`;
rulings `TW-A`…`TW-F` in `docs/superpowers/2026-10-13-frame-of-id-decisions.md` (next unused `TW-G`) and `DG-W` in
`docs/superpowers/2026-10-13-guides-followup-decisions.md`. **No public declaration, no divergence taken (385–394
unused), no probe (MetalUI-only; gpui's `debug_bounds` is the authority), no shader or `Backends/SDL` change.**

**Status: LANDED.** One lane, red first.

## §1 Cause and fix

`.id(_:)` on a non-`StyledElement` group is an `IdentifiedGroup` (`ID-G`): an identity level and **no layout node**,
so no `recordElementBounds` site ever saw its id; its content's rows are `…/name/positional(0)`. `Text`/`Box` take
their own `id` and a `ModifiedContent` chain names its outermost layer (`MC-A`); a `Rectangle().frame(…)`, a
`GPUSurface` frame, a `ZStack` and a `Component`'s content do not. Fix (`TW-A`…`TW-C`): `IdentifiedGroupLayout`
gains internal `id` and `nodes` (the nodes its content handed the parent, **kept only while
`recordsElementBounds`**, both entries); `IdentifiedGroup.prepaintGroup` calls the new
`Frame.recordIdentifiedBounds(_:nodes:)`, which writes `elementBounds` with the union of the nodes' rects, writes
nothing for no node, and never calls `matchScrollRequests`. `swift package clean` was run first (stored property on a
public type). `testing.md` states the group rule.

## §2 Red first, against `d279f34d`

`noElement` (`no element matches id`) for `frameOfIDFindsAnIDOnARectangle` ("r"), `…OnAGPUSurface` ("surface"),
`…OnAZStackInsideAComponent` ("stack"), `frameOfIDAnswersTheUnionOfAGroupsNodes` ("pair"),
`frameOfIDStillFindsTextAndBoxIDs` ("rect"); `anIDInALegacyParentIsFoundToo` was added in the second red commit.
`frameOfIDAnswersTheOutermostLayerOfAModifiedChain` and `frameOfIDOnAnEmptyIdentifiedGroupIsNoElement` were
green before (pins; `TW-F` 1). The two retired-label tests pass on the unmutated tree and are mutation-pinned.

## §3 Mutations (a build with an env-switched mutant, restored from copies, `git status` clean after)

Filtered to the 29 tests of the sites (the full suite was run unmutated, §4).
- **M1** (delete the call): reddens `frameOfIDFindsAnIDOnARectangle`, `…OnAGPUSurface`, `…OnAZStackInsideAComponent`,
  `…UnionOfAGroupsNodes`, `frameOfIDStillFindsTextAndBoxIDs`, `anIDInALegacyParentIsFoundToo`,
  `anIDOnAGroupIsLayoutTransparent`.
- **M2** (first node only) and **M3** (last node only): `frameOfIDAnswersTheUnionOfAGroupsNodes`. M3 does not redden
  the chain test (`TW-F` 1).
- **M4** (record a zero rect for no node): `frameOfIDOnAnEmptyIdentifiedGroupIsNoElement`.
- **M5** (untyped entry keeps no nodes): `…OnAZStackInsideAComponent`, `…UnionOfAGroupsNodes`,
  `anIDInALegacyParentIsFoundToo`, `anIdentifiedGroupKeepsNoNodesWhenTheFrameDoesNotRecord`.
- **M6** (`matchScrollRequests` from `recordIdentifiedBounds`): `anIdentifiedGroupIsNotAScrollToTarget` (first run
  green: the window did not record, `TW-F` 2; fixed, then red, offset 140 not 110).
- **M7** (gate removed): `anIdentifiedGroupKeepsNoNodesWhenTheFrameDoesNotRecord`.
- Parser started at the top of the file: `theRetiredDivergenceRowsAreRead` and `noGuideCitesARetiredDivergence`
  (126 issues). `divergence 249` cited in guide 5 alone: `noGuideCitesARetiredDivergence` (`state-and-identity:197`).
- **Not measured**: re-adding the old `DG-P` sentence reddens nothing (it is prose, not a mirrored fence); the edited
  mirror is the proof, below.

## §4 Fix 3 and the Linux proof

`DG-W`: `state-and-identity.md` and `testing.md` say `try await window.runUntilIdle()` for a model written outside
input; `theStateGuideForEachRowsKeepTheirStateWhenTheDataReorders` is `async` and calls it (the other `tick()` uses
draw a frame deliberately and stay). In the `metalui-portable` image (root package, volume
`metalui-root-build-frame-of-id`, `swift test --filter MetalUITestingTests`): 184 tests passed, the edited mirror,
the seven harness tests and the two retired-label tests among them.

## §5 Counts

**3643 tests** (3631 + 12: seven harness tests, `anIdentifiedGroupKeepsNoNodesWhenTheFrameDoesNotRecord`,
`anIdentifiedGroupIsNotAScrollToTarget`, the two retired-label tests, `anIDInALegacyParentIsFoundToo`; the mirror
edit adds none), 0 goldens, 229 guards (none added). Native run after `swift package clean`: 0 `error:`, the only
`warning:` SwiftPM's deprecation notice, `FR-J no-argument frame: succeeded=true`, on a locked screen exactly the five
`AppKitPresentationTests` sheet issues. One literal fixed: E3.5 `anIDOnAGroupIsLayoutTransparent` counts the group's
own row (`TW-F` 3). Inventory and undocumented scripts print nothing.

## §6 Deferred

`scrollTo` by a proposal group's id as a recorded target (`TW-C`); the retired rows 79/249 sit below the not-offered
table and are read by position.
