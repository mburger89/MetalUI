# Item C30 — `frame(ofID:)` sees proposal `.id`; retired labels in guides; DG-P dropped

Rulings: [`../2026-10-13-frame-of-id-decisions.md`](../2026-10-13-frame-of-id-decisions.md) (`TW-A`…) and
`DG-W` in `../2026-10-13-guides-followup-decisions.md`. Record: `docs/record/108-frame-of-id.md` (written,
§108). **Status: LANDED.** Branch `fix/frame-of-id` from `d279f34d`. One lane (implementer), files below. SwiftUI claims:
none. `TestWindow.frame(ofID:)` is MetalUI-only (class `M`); the authority is gpui's `debug_bounds` (an element's
laid-out bounds by its id), named in `TestWindow`'s own doc comment. No probe is owed; none is run.

## 1. Cause (isolated by reading, to be confirmed by the red tests)

`frame(ofID:)` filters `Window.testingElementBounds` (`Frame.elementBounds`, `[GlobalElementID: Bounds]`) by
`key.component == .named(ElementID(name))`. Rows are written by `Frame.recordElementBounds` at exactly four
sites: the root, `Element.prepaintGroup` (`ElementGroup.swift:165`), `AnyElement`'s group entry (`:691`) and
`ModifiedContent.prepaintLayer` (`ModifiedContent.swift:312`). Each records **a layout node's own id**.

`.id(_:)` on a non-`StyledElement` group returns `IdentifiedGroup` (`ExplicitIdentity.swift`, `ID-G`). It is
**layout-transparent: it has an identity level (`GlobalElementID.child(of:at:name:)`) but no node**, and its
`prepaintGroup` only forwards to its content. So the id that carries `.named("panel")` is never passed to
`recordElementBounds`; its content's rows are keyed `…/panel/positional(0)`, whose last component is not the name.
A `Text` or `Box` takes its own `StyledElement.id(_:) -> Self`, which names the element's own node: found. A
`Rectangle`, a `GPUSurface` frame and a `ZStack` (proposal content, no `StyledElement`) take the wrapper: missed.
Not a `MetalUITesting` mapping fault: the row does not exist in `elementBounds`, so the fix is in `Sources/MetalUI`.

## 2. Design (fix 1)

`IdentifiedGroup` records its own row. `IdentifiedGroupLayout<ContentLayout>` gains two internal stored fields:
`id: GlobalElementID` and `nodes: [LayoutNodeID]` (the nodes its content contributed, **empty unless
`pass.frame.recordsElementBounds`** at layout time, so a production frame allocates nothing: `requestGroupLayout`
and the typed `requestProposalGroupLayout` both set them; the typed entry converts its `[ProposalNodeID]`
to the underlying `LayoutNodeID`s). `prepaintGroup` calls a new `Frame.recordIdentifiedBounds(_:_:)`
with `id` and the **union of `pass.bounds(of:)` over `nodes`** (nothing for an empty list), before forwarding to the
content.

- The union is of the nodes the content hands its parent. Under `.id()` outermost (`MC-A`) a modifier chain
  contributes its **outermost layer's node**, so the answer is the outermost layer's laid-out rect (padding,
  frame and background included), as the item requires. A multi-node group (a builder pair) answers the union of
  its siblings' rects (`TW-B`).
- `recordIdentifiedBounds` writes `elementBounds` **only**. It does not call `matchScrollRequests` (`TW-C`): a
  `scrollTo` resolves against exactly the rows it did before, so `ScrollViewReader` behaviour cannot move.
- Public API: none. The `package` read-back (`testingElementBounds`) is unchanged; plain-import guards 3.1–3.4 are
  untouched. `IdentifiedGroupLayout` is public but its new fields are internal: **`swift package clean`** before the
  native run (stored property on a public type crossing a module boundary).
- Both vocabularies: `IdentifiedGroup` has the one `prepaintGroup` shared by the legacy parent (`Row`/`Column`
  through `LegacyContent` where it compiles) and the proposal parent (`VStack`, `Component`); both entries set the
  fields. A `StyledElement`'s own `.id` is unchanged (already recorded by its node).
- Identity, hit testing, accessibility, animation, focus, `List`, pixels: untouched (a recording-only change inside
  an existing `recordsElementBounds` gate). Counters that count `elementBounds` rows (differential harness) are
  checked by the full suite; a test that counted rows and now sees one more per `.id` on proposal content is a
  fix of the test's literal, named in the record.
- Docs: `docs/testing.md` states `frame(ofID:)` reads "an element named with `.id`"; add one sentence that a
  group's `.id` answers the union of its nodes' rects (`TW-B`).

## 3. Design (fix 2): the retired-label check

`GuideDocs.retiredDivergenceRows`: every numeric-first-cell row of `docs/divergences.md` **at or after the
`## Retired` heading** (the retired table and the rows C20 and C27 appended below it, 79 and 249; live rows are all
above it). `divergenceRows` (any row) is unchanged. New test `noGuideCitesARetiredDivergence` fails with
`<doc>:<line>: divergence N is retired (<doc of the row>)`. Pin for the parser:
`theRetiredDivergenceRowsAreRead` (`#require` the set holds 2, 79, 85, 249 and none of 1, 325).

## 4. Design (fix 3): drop `DG-P`

C29 (record §106) made `runUntilIdle()` return after a click on every platform (pinned by
`RunUntilIdleAfterClickTests`). Edits (text and mirrors byte-identical, `DG-W`):
- `docs/guides/state-and-identity.md` ~l. 95: the sentence now says a test that writes a model outside input calls
  `try await window.runUntilIdle()` (which draws a dirty window without moving the clock), not `setNeedsRedraw()` +
  `tick()`.
- `docs/testing.md` "The clock and `runUntilIdle`" (~l. 310–314): same; `setNeedsRedraw()` + `tick()` stays
  described only as the way to draw one frame deliberately.
- Mirror `theStateGuideForEachRowsKeepTheirStateWhenTheDataReorders` (`GuideMirrorsLane1.swift` ~l. 446): becomes
  `async throws`, replaces `window.window.setNeedsRedraw(); window.tick()` with `try await window.runUntilIdle()`,
  drops the `DG-P` sentence from its doc comment.
- Grep the other guides and mirrors for `setNeedsRedraw`/`tick()` workarounds written for the same cause
  (`GuideMirrorsLane2.swift`, guide code blocks); change only a use whose purpose is that workaround. The
  guide doc-check's mirror-byte comparison (existing tests) proves the mirrors stay identical.
- Proof: the ROOT package in the `swift:6.4-noble` image (not the `Backends/SDL` package; volume named `metalui-root-build-frame-of-id`, OrbStack left running) running `swift test --filter MetalUITestingTests`, whose summary line is read; the macOS run is not
  evidence (the hop is synchronous there).

## 5. Files (one lane)

`Sources/MetalUI/ExplicitIdentity.swift`, `Sources/MetalUI/Frame.swift` (one method beside `recordElementBounds`),
`Tests/MetalUITestingTests/HarnessLayoutTests.swift` (new tests 1.30–1.37 appended; name the free ones when
writing), `Tests/MetalUITestingTests/GuideDocCheck.swift`, `GuideMirrorsLane1.swift`, `docs/guides/state-and-identity.md`,
`docs/testing.md`. Parallel branch to stay off: `perf/incremental-invalidation` (`Frame`/`Window` hot paths; this
change adds one method and touches no existing line of `Frame.swift`).

## 6. Tests (red before / mutation that must redden)

All in `MetalUITestingTests` unless noted, written red first against `d279f34d` (cause: `noElement`).
1. `frameOfIDFindsAnIDOnARectangle` — `Rectangle().frame(width: 40, height: 20).id("r")` in a `VStack`; the rect is
   `(x, y, 40, 20)` derived by hand. Red now (`noElement`). Mutation: delete the `recordIdentifiedBounds` call.
2. `frameOfIDFindsAnIDOnAGPUSurface` — `GPUSurface` with `.frame` then `.id`. Same mutation.
3. `frameOfIDFindsAnIDOnAZStackInsideAComponent` — the DG-T shape. Same mutation.
4. `frameOfIDAnswersTheOutermostLayerOfAModifiedChain` — `Rectangle().frame(width: 40, height: 20).padding(5)
   .background(…).id("p")` is 50 × 30 (not 40 × 20). Mutation: record `nodes.last` / the innermost instead of the union
   of the contributed nodes (build the list from the content's first node).
5. `frameOfIDAnswersTheUnionOfAGroupsNodes` — `Group`-like builder pair of two sized rects under one `.id`:
   union rect. Mutation: first node only.
6. `frameOfIDStillFindsTextAndBoxIDs` — existing 1.25 stays green; add a `Text` and a legacy `Box` beside a
   `Rectangle` id. Mutation: record the identified row under `layout.content`'s id (key mismatch) reddens 1–5 only.
7. `frameOfIDOnAnEmptyIdentifiedGroupIsNoElement` — `if false { Rectangle() }.id("e")`: `noElement`, no trap.
   Mutation: record `Bounds.zero` for an empty list.
8. `anIDInALegacyParentIsFoundToo` — the same `Rectangle().id` as a child of a legacy `Column` (adopted whole through
   `LegacyContent` if it compiles; otherwise the test records the compile boundary as the finding). Mutation: skip the
   untyped entry's `nodes` assignment.
9. `anIdentifiedGroupIsNotAScrollToTarget` — a `ScrollViewReader` scroll to a `Rectangle().id("t")` row
   produces the same offset before and after the change (measured on `d279f34d` first, literal hand-derived).
   Mutation: call `matchScrollRequests` from `recordIdentifiedBounds` (the test must redden, else it is not a pin).
10. `aWindowNotRecordingLayoutThrowsNotRecorded` — existing 1.27 unchanged; the allocation gate is covered by
    `nodes` being empty when `recordsElementBounds` is false (read through an `@testable` frame test in `MetalUITests`:
    `anIdentifiedGroupKeepsNoNodesWhenTheFrameDoesNotRecord`). Mutation: remove the gate.
11. Fix 2: `noGuideCitesARetiredDivergence`, `theRetiredDivergenceRowsAreRead`. Mutations: cite `divergence 249` in a
    guide (reddens the first); make the parser start at `## Live` (reddens the second and, with the cite, the first).
12. Fix 3: the edited mirror (async, `runUntilIdle`) plus the existing byte-identity checks. Mutation: restore the
    `setNeedsRedraw()`+`tick()` lines changes nothing (both draw) — so the proof is the doc check: re-adding the old
    guide sentence while the mirror holds the new one reddens `everyMirroredBlockMatches…` (name from the run).

Counts: expected +12 tests (tests 1-10 less the unchanged 10's first half, plus 11's two and 12's edit) and 0 guards; re-measure. Test 12's mutation proof is the doc check: edit the guide sentence back and name the reddened mirror-identity test from the run (`TW-E`).

## 7. Demo, pixels, human checks

No demo change, no pixel change (a recording-only change inside a test-only flag); the fourteen images 0 px against
`d279f34d`. No human-check addition (nothing is seen on screen). Divergence: none (range 385–394 unused).

## 8. Deferred

- A scrollable `scrollTo`/`ScrollPosition` by a proposal `.id` — not asked; owner none.
- `elements(id:)` on the accessibility tree is unrelated.
- The oddly placed retired rows 79/249 below the not-offered table in `divergences.md` are read by position and
  left where they are (the file's header settles at the merge).
