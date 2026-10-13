# Developer guides follow-up — decisions

Rulings for item 10c. Spec: [`specs/2026-10-13-guides-followup-design.md`](specs/2026-10-13-guides-followup-design.md).
Record: `../record/107-guides-followup.md`. Continues the namespace of
[`2026-10-12-guides-decisions.md`](2026-10-12-guides-decisions.md) (`DG-A`…`DG-Q`).

Evidence: records §98, §99, §101, §102 and their pinning tests; no SwiftUI probe was run (the guides
make no new SwiftUI claim; the divergence rows carry the items' own probes).

Prefix **`DG-`**. **Next unused: `DG-V`.** (Moves in the commit that appends a ruling.)
Branch `docs/guides-followup` from `b17aee19`. Reserved divergence labels 375–384: none used.

## DG-R — New sections go after the old ones, so no mirror number moves

**Ruling.** Input gains blocks #6 (resign) and #7 (input method) after the selection section; drawing
gains #6 (measurer) and #7 (Reduce Transparency) after the GPU sections, not inside the material section,
whose blocks are #3. **Reasoning.** A block placed in the material section would renumber #4 and #5 and
rewrite their markers for no reader benefit; the material section instead points forward to the last one.
**Cost if wrong.** A reader finds Reduce Transparency three sections from the materials.

## DG-S — The denylist loses two names, not four

**Ruling.** `deniedNames` held `resignsFocusOnPress`, `TextMeasurer`, `PhaseAnimator`. The item's four
APIs are C23, C24, C27 and C28; only two had a name on the list (C27's `tint(in:)` and C28's driver verbs were
never on it). The two are removed; `PhaseAnimator` is not built (`LK-I`) and stays.
**Evidence.** With the guides written and the list unchanged, `noGuideNamesAnApiThatIsNotOnMaster` recorded
two issues; after the removal the filtered `MetalUITestingTests` run passed.

## DG-T — `frame(ofID:)` does not see a proposal element's `.id`; the sizing test reads an accessibility frame

**Ruling.** The measurer test reads the surface through `element(label: "Chart").frame` (the guide labels
the surface for accessibility) and the label through `frame(ofID: "label")`.
**Evidence (measured).** `.id("panel")` on a `Rectangle`, and `.id("surface")`/`.id("stack")` on a
`GPUSurface` frame and a `ZStack` inside a `Component`, each threw `no element matches id` from
`frame(ofID:)`; `Text` and `Box` ids are found. Cause not isolated; a **finding** for the orchestrator:
`docs/testing.md` says `frame(ofID:)` reads "an element named with `.id`" without the legacy-only limit.
**Cost if wrong.** None for the guide.

## DG-U — A stale sentence in guide 5 is replaced

**Ruling.** Guide 5 said "Reduce Transparency is not honoured (divergence 249)". Divergence 249 was retired
by C27 (record §101) and 315 replaced it, so the sentence and its list row are replaced, not appended to.
`everyCitedDivergenceHasARow` did not catch it (a retired label keeps its row): a finding about the checker,
not fixed here (a retired-label check would be a new rule).

## DG-V — Pins are the items' own; the C23 cost test is not cited

**Ruling.** Each claim cites the item's own pin from its record. `theOverlayCostIsLinearAndCounted` is not
cited: its doc comment says it is expected to change when C14 lands, so a guide citing it would pin a number
the next item moves. The guide makes no cost claim.
