# Warm settle (C14-e) — decisions

Rulings for item C14-e (MetalCreator's counter bisect, 2026-10-20). Spec: [`specs/2026-10-20-warm-settle-design.md`](specs/2026-10-20-warm-settle-design.md).
Record: `../record/127-warm-settle.md` (at the Record phase). Branch `perf/warm-settle` from `679f5d7d`; divergence labels reserved
565–574 (none taken; 346 is amended, not relabelled).

**Next unused id: `CF-I`.** (Moves in the commit that appends a ruling; read the last `## CF-` heading if they disagree.)

Evidence: the code at `679f5d7d` (`EnvironmentReading.swift`, `EnvironmentProperty.swift`, `TextMeasurer.swift`, `Frame.swift:2514`,
`ContentMemo.swift`, `RetainedPrepaint.swift` `noteRedo`, `Window.swift` `buildAndAdoptFrame`, `LayoutMemo.swift`, `TestingHooks.swift`
`testingOnFrameAdopted`), record §110, §120, §121, §123, one probe-shaped scratch run at the designer step (below, `CF-E`). **No
SwiftUI-facing claim is made** — `textMeasurer` is MetalUI-only (divergence 296, SwiftUI's `GraphicsContext.resolve(_:)` has no
environment carrier) and the counters are MetalUITesting's — so no SwiftUI probe is owed (as `OS-J`), and no gpui claim is made.

## CF-A — A `\.textMeasurer` reading is the text system's identity plus the text-style environment it resolves against

**Ruling.** `EnvironmentReading.of` gains a first arm: a `TextMeasurer` value reads as `.value(TextMeasurerReading)`, an internal
`Equatable` struct holding (1) `ObjectIdentifier` of the **text system instance** (`box.system`, a class: `TextSystem: AnyObject`),
`nil` for a measurer with no box, and (2) the two `ResolvedTextStyle`s `resolveTextStyle` gives a default `.inherit` request and a
`.defaultFont` request in the measurer's environment. No new `EnvironmentReading` case, no public declaration, `TextMeasurer` itself is
not made `Equatable`. **Why not the box's identity (the item's wording).** `Frame.init` allocates a fresh `TextSystemBox` every
frame (`Frame.swift:2514`), so box identity differs on every frame and the component would be *evaluated* every frame instead of
refused: the pin would stay red and the counter would lie. The window's system instance is stable for the window's life. **Why the
style half.** The measurer captures the whole `EnvironmentValues` at the reading element and `resolve(_:)` reads font, weight, italic,
`controlSize`, `foregroundStyle`, line limit, truncation and alignment from it (and only those: `resolveRichText` reaches the
environment only through `resolveTextStyle`, checked in `TextRuns.swift`). System identity alone would skip a component whose
measured size changed after a `.font(_:)` above it (a stale size, the worst failure). The two resolved styles are a function of exactly
those reads, so equal styles give equal answers for every `Text` (the explicit-font, weight and italic overrides of a `Text` itself are
the text's, not the environment's). **Evidence to take.** T1–T6 of the spec; the mutation that drops the style half reddens the font and
controlSize arms. **Cost if wrong.** A field the style misses means a stale measured size under a changed environment: the per-field
arms (T3) are the net; the cost of the identity half being too coarse is nil (one system per window).

## CF-B — A measurer over a text system that is not a class instance cannot occur, and a missing box compares equal to itself

**Ruling.** `TextSystem` is `AnyObject`, so the identity always exists; a measurer with no stamped box (a bare `EnvironmentValues`)
reads `(nil, styles)` and equals another such reading. **Why.** It traps only when it resolves, and a component that reads it and
resolves is never under a bare environment. **Cost if wrong.** None observable.

## CF-C — A redo frame reports the redo's work, plus the content getters the abandoned attempt evaluated

**Ruling.** `FrameWork` on a redo frame (`RK-D`) is the **redo's** counters (layout, element requests/prepaints/paints, retained, skips,
refusals — what the presented frame cost to produce), and `contentEvaluations` additionally carries the abandoned attempt's
evaluations. **Why.** `noteRedo` restarts the counters because the attempt's work was thrown away, which is true of everything the
redo repeats. A content getter is different: the evaluation is cached on the entry (the memo's `pristine`, `StateTable` entries are not
rolled back), the redo **skips** it, and so the frame's only evaluation is lost — MetalCreator read `contentEvaluations == 0` on the
frame whose pan began, with the component's text visibly updated. Summing everything instead (the other candidate) would double-count
layout, paint and the retained counters that the redo performs again and would move every `retainedRedos` pin; carrying only the
getters is the one loss with no repeat. No dedupe is needed: a refused component counts a refusal, not an evaluation, and an entry
evaluated in the attempt is a skip in the redo. `builds` stays 1 (it counts adopted frames; `retainedRedos` marks the second build).
Implementation: `noteRedo` keeps `evaluations` across `resetBuildCounters()` (a `carriedEvaluations` field read back at the redo's
`endFrame`). **Cost if wrong.** A pin that expected a redo frame's evaluations to be the redo's own moves by the carried count (named
and re-baselined in lane 1); verify mode (`RK-N`) reports the replayed attempt's counters through `reportLast` and is untouched.

## CF-D — The abandoned attempt's layout and element work stays unreported

**Ruling.** Not reported, not counted anywhere new. **Why.** `FrameWork` is "the work the presented frame did" (`HT-I`); a redo is
the framework's own retry, visible as `retainedRedos` and, for the cost, in the `RK-D` quarantine counters. A second set of
`abandoned*` fields is public API (`MetalUITesting`) and a label for nothing a consumer acts on. **Cost if wrong.** A benchmark
under-reads a redo frame's CPU by the abandoned attempt; the record says so, and `retainedRedos > 0` identifies the frame.

## CF-E — (e) is not reproduced at 679f5d7d by the shape the item names; lane 2 reproduces before it fixes anything

**Ruling.** At the designer step a persistent `TestWindow` (`recordsLayout: false`) over two `.equatable()` components, two
`onGeometryChange` scopes outside them, a `ScrollView`/`ForEach`, plain text and two unkeyed (custom `Shape`) leaves, drawn 0, 1, 2, 3,
5 and 9 frames before `resetFrameWork()` then seven `redraw()`s, read **identically on every frame**: `layoutMeasureCalls` 2 (the two
unkeyed leaves — MetalCreator's steady "2"), `layoutMemoHits` 56, `layoutMemoMisses` 0, grafts 2, retained hits 2, no redo. So the
spike (80 once) needs something the fixture lacks. The suspects the item lists are narrowed by this: not RW-S, not the settle build,
not a generic two-generation sweep of the memo for a tree this shape (an `endFrame` rotation every frame refreshed every used
entry). What it can still be, in order of cost to test: (1) a **subtree never looked up in the memo for two frames** — a grafted or
placement-restored `.equatable()` subtree does not refresh its descendants' `LayoutMemo` entries, so they age out of both generations and
the next frame that must measure them (the first after the root key changes, e.g. the first frame a `List`/overlay/`resignsFocusOnPress`
layer or the unkeyed-leaf ancestor re-lays out) pays 80 once; (2) the **GraphPanel being non-`.equatable()`** and alternating (MetalCreator
`b959428`); (3) a shape the fixture lacks: `Spacer().frame(max…).overlay { ZStack { … } }`, `.resignsFocusOnPress()`, `.theme`/
`.environment(model.themes)`, a `List`, a refused `\.textMeasurer` reader, scale 2, dark scheme. **Procedure (lane 2 step 0, time-boxed):**
copy MetalCreator (read-only source, **a scratch copy**, never edit the repository) to the scratch directory, `swift package edit`
MetalUI onto this worktree, run its `WarmFrameTests`, log per-frame all `FrameWork` fields and the memo's `entryCount` per frame; then
cut the app tree down until the spike survives in a MetalUITesting-only fixture. The pin is written on that fixture. **Ruling on the
outcome** (a later `CF-` ruling at lane time): if the cause is (1), fix by touching the entries a graft/placement restore stands for
(`LayoutMemo` `touch`, in `MetalUILayout`, value-identical; counters `layoutMemoHits` may rise by the touches, named) so warm[0] equals
warm[n]; if it is genuinely inherent (e.g. a one-time cache fill the first frames cannot do), rule it so, name the frame from which
`warm[n] == warm[n+1]` holds, and pin from there. **Cost if wrong (this ruling).** A fixture that cannot show the spike means the
pin is not red-on-arrival; the spec then ships the pin from the first frame the runs prove stable, labelled as such, and the item stays
open for MetalCreator's tree rather than closed by a green test that never saw it.

## CF-F — (b) is a dated measurement; no pin, and a fix only outside the C14-d files

**Ruling.** The cold-frame attribution (ledger snapshots, memo-miss handling, overscan raster, per-record cost) is taken with the
release perf harness (`docs/probes/perf-baselines.sh`, `perf-harness`) and `xctrace` Time Profiler on the bracket fixture's first frame
and an orbit-shaped tree, recorded dated in record §127 with the machine busy-ness stated (other workflows share this Mac: three
repeats, medians, `retained*`/memo counters beside the times). **A fix lands only if (i) a measured cold-frame win exists, (ii) it is
value-identical (the fourteen images 0 px, every other counter equal) and (iii) it is outside `RetainedSubtree.swift`, `RetainedGraft.swift`,
`PrepaintLedger` and `List`/`ForEach` retention** (C14-d's, in flight). The named candidate — not taking the pre-paint ledger snapshot on
a first sighting that cannot hit (`RetainedSubtree.swift:534,543`) — is **in C14-d's file**: if the profile supports it, the record
carries the exact change and the merge order (after C14-d), and `retainedLedgerSnapshots` pins re-baselined then. **Why.** The brief
forbids pins on time, and a counter-moving change inside a file being rewritten in parallel is a guaranteed conflict. **Cost if wrong.**
The item's 25 % stays unaddressed this branch; the attribution says where it goes.

## CF-G — The warm pin is `warm[n] == warm[n+1]` over the whole `FrameWork`, gated off Darwin only where the observation hop is

**Ruling.** The warm pin compares the full `FrameWork` value (Equatable) and, separately, asserts `atlasUploadPixels == 0 &&
rasterizedPixels == 0 && newTextures == 0`. It uses `setNeedsRedraw()` + `tick()` (the `eeRedraw` form, no `@Observable` write), so it
holds off Darwin; a session-count assertion would be Darwin-only (`IV-Q`) and is not in it. **Cost if wrong.** A Linux-only
difference would show in the Linux image run and be gated with the stated reason.

## CF-H — Critic pass: T6 dropped, the rest of the design stands

**Ruling.** Spec test T6 (two windows, two text systems) is dropped: it asserted nothing a mutation could redden, and T4 already separates
system identity from box identity. Checked and kept at `679f5d7d`: the per-frame `TextSystemBox` (`Frame.swift:2514`), `TextSystem: AnyObject`,
`noteRedo` calling `resetBuildCounters()` (`RetainedPrepaint.swift:298`). No SwiftUI claim, public API, renderer primitive, platform requirement or
C enum is touched, so no probe or fake is owed; lanes are file-disjoint and (b)'s C14-d-file fix stays deferred (`CF-F`). **Cost if wrong.** None.
