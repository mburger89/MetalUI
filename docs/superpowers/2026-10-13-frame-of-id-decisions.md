# `frame(ofID:)` on proposal content — decisions

Rulings for item C30. Spec: [`specs/2026-10-13-frame-of-id-design.md`](specs/2026-10-13-frame-of-id-design.md).
Record: `../record/108-frame-of-id.md`. Evidence: reading of `ExplicitIdentity.swift`, `Frame.recordElementBounds`
and its four call sites, `TestWindow.frames(ofID:)`, and record §107's `DG-T` measurement; red tests owed to the
implementer. No SwiftUI probe: `frame(ofID:)` is MetalUI-only and gpui's `debug_bounds` is the authority.

Prefix **`TW-`**. **Next unused: `TW-E`.** (Moves in the commit that appends a ruling.)
Branch `fix/frame-of-id` from `d279f34d`. Reserved divergence labels 385–394: none used.

## TW-A — The fix is `IdentifiedGroup` recording its own row, not a wider lookup in the harness

**Ruling.** `IdentifiedGroup` (layout-transparent, an identity level and no node) records
`elementBounds[its id]` in `prepaintGroup`; `MetalUITesting`'s `frames(ofID:)` is unchanged.
**Reasoning.** The row for the wrapper's id does not exist; the content's rows are `…/name/positional(0)`. A
harness lookup that matched "a name anywhere in the path" would find the wrong element (a named parent of every
descendant) and answer many rects for one name. **Cost if wrong.** One more dictionary write per `.id` on
proposal content in a recording frame only.

## TW-B — The answer is the union of the nodes the content hands its parent

**Ruling.** One node (the usual case, and a modifier chain's outermost layer under `.id()` outermost): that node's
rect. Several (a builder pair): their union. None: no row, `noElement`. **Reasoning.** "The laid-out rect of the
element the id names, i.e. the outermost layer": a group has no rect of its own, and its parent places exactly these
nodes. **Cost if wrong.** A test over a multi-node group reads a box that covers gaps between siblings; it can use
`.id` on each child.

## TW-C — The new row is not a `scrollTo` target

**Ruling.** `recordIdentifiedBounds` writes `elementBounds` only and never calls `matchScrollRequests`.
**Reasoning.** `DD-G`: a pending request resolves against the first match among the rows recorded; adding rows
there could change which element a scroll finds. The harness read-back needs the row, scrolling does not.
**Cost if wrong.** `scrollTo` by a proposal group's id keeps its present behaviour (pinned by test 9).

## TW-D — A retired label is every numeric row at or after `## Retired`

**Ruling.** The guide doc-check treats a divergence label as retired when its row is at or after the `## Retired`
heading of `docs/divergences.md` (this includes 79 and 249, rows appended below the not-offered table), and fails
a guide citing one. **Reasoning.** DG-U: a retired label keeps its row, so `everyCitedDivergenceHasARow` cannot
see it. Position, not a "retired" column parse, because the appended rows differ in layout.
**Cost if wrong.** A live row moved below the heading would be refused; the parser pin names the set.
