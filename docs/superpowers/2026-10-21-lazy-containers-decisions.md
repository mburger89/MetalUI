# Lazy containers - decisions

Rulings for item L1 (`LazyVStack`, `LazyHStack`, `LazyVGrid`, `LazyHGrid`, `GridItem`; user request 2026-10-02, round 2 2026-10-21).
Spec: [`specs/2026-10-21-lazy-containers-design.md`](specs/2026-10-21-lazy-containers-design.md). Record: `../record/134-lazy-containers.md`
(not yet written). Branch `feat/lazy-containers` from `1bdead8d`. Reserved divergence labels 635-644: **635, 636, 637 taken by this
design**, 638-644 unused. Probe: `../probes/swiftui-lazy-containers.swift` (output in its header; a SwiftUI claim below cites its arm).

Prefix **`LZ-`**, lettered. **Next unused: `LZ-S`.** (Moves in the commit that appends a ruling.)

**Carried.** `DD-F` (window against the scroller), `VL-B`..`VL-Q` (variable rows, `RowExtentIndex`, the anchor), `TB-AH` (bounded
retention), `FI-A`/`FI-B` (ForEach identity), `ID-R`, `PE-V` (a `ProposalScrollView` publishes `ScrollContext`), `GR-L` (lazy grids
deferred to this stage), `CN-H` and divergence 51 (default spacing), `RW-I`, `IV-` (a non-`Hashable` custom layout taints its ancestors).

## LZ-A - SwiftUI's spellings; `pinnedViews:` and `Section` are not offered

**Ruling.** The four containers and `GridItem` take SwiftUI's signatures with MetalUI's `Pixels` lengths and the proposal alignments
`VStack`/`HStack`/`ZStack` use (spec section 2). They are proposal `Element`s (`ProposalElement`), content is
`@ProposalContentBuilder`, and a legacy `Row`/`Column` child is adopted as `LegacyContent` (and makes the container eager, LZ-B).
**Evidence.** The existing proposal containers' shape (`VStack.init`, `NativeElements.swift` 100); probe arms A1-A9, C1-C17.
**Cost if wrong.** A call site written `LazyVStack(pinnedViews:)` does not compile (the typecheck guard G.1 pins that, so adding it
later is additive). A different alignment type would be a source break for every call site.

## LZ-B - A lazy container's unit is a ForEach element or a static leaf; anything else is eager (divergence 636)

**Ruling.** Content is read as a list of **units**: a `ForEach` over proposal content contributes one per element, a `ProposalElement`
leaf one, `Pair` concatenates, `EmptyGroup` none; units are realised on demand through the package protocol `LazyUnitSource`, implemented by
extensions in the new `LazyUnits.swift` (the existing files are not edited). A member that is not one of those (`if`, `switch`, `for`,
a `LegacyContent`, a legacy-row `ForEach`) makes the **container eager**: every unit every frame, laid out as a `VStack`/`Grid` would,
counted in `lazyUnbounded`. A unit that registers 0 nodes adds no extent and no spacing (probe A9); more than one is laid out in
sequence in a stack (A8) and is **one cell** in a grid (divergence 635: SwiftUI makes each view a cell, C14).
**Evidence.** A8, A9, C14. The cursor index a static leaf takes must be known without realising its neighbours, which is why the
member kinds are enumerated (a `ProposalElement` consumes exactly one index through `enteringGroupMember`; an `if` takes one slot and
owes `noteAbsent`/`noteProduced` and animation notes every frame, an `either` two, a `for` one plus `noteLoop`).
**Cost if wrong.** A lazy stack that contains a conditional is eager: correct but unwindowed (observable by `onAppear` counts, so
divergence 636, and by `lazyUnbounded`). `if loading { ProgressView() }` beside a `ForEach` is the common shape this hurts; L1b
(windowing conditional members) is the named follow-up. The grid's one-cell rule differs from SwiftUI only for an element producing
several views.

## LZ-C - Windowing reuses `RowExtentIndex`; the planner glue is mirrored, not extracted from `List`

**Ruling.** The lazy containers use `RowExtentIndex<AnyHashable>` itself (class, Fenwick trees, `forgetMeasurements`, `rebuild(ids:)`,
estimate rules `VL-C`) unchanged. The glue that `List` keeps in `variableWindow`, `rebuildKeepingAnchor` and `prepaintVariableRows`
is **rewritten once over lines** in `LazyCore.swift` (`LazyLinePlanner`), following the same steps in the same order, and `List.swift` is
**not edited**: `List` windowing, `TB-AH` and the `VL-` pins must not move in this item.
**Evidence.** The glue is `List`-typed (`Data.Element.ID`, `ListOrigin`, `builtIDs`); extracting it means touching 1274 lines of a
file whose pins this item must leave green and whose retained replay (`RW-`) is carried by `ListOrigin.sameEntry`.
**Cost if wrong.** Two copies of the anchor arithmetic: a future fix to one must be made in the other. Mitigation: the planner cites
`VL-E`..`VL-H` in its header, mirrors their test shapes (2.6, 2.8), and the follow-up "extract the planner" is named in the spec.
If the item's intent was a literal shared code path, lane 1's first commit can extract it behind `List`'s existing pins instead;
that is a larger, riskier first step, not a different design.

## LZ-D - Size and spacing are the probe's, not "widest realised child"

**Ruling.** A lazy stack answers the **proposal** on its cross axis when there is one and the **first unit's first node's** answer at
`(nil, nil)` when there is not; its main axis is its content (the anchor-relative sum, never greedy). Spacing `nil` is
`ProposalSpacing.platformDefault` (8) between units that each contribute a node, uniformly (no per-pair zero-spacing edge: a `Spacer`
or a `Text` neighbour is divergence 51's territory, unchanged). Children align across by `alignment` and overflow centred.
**Evidence.** A1, A3, A3b, A3d, A5, A6, A7 (the premise "widest realised child" is refuted: first), A2/A2c, A10.
**Cost if wrong.** A nil-cross lazy stack (inside a horizontal scroller, which is not windowed on that axis anyway, R5) answers a
different width than SwiftUI if the first-child rule is only the probe's special case; the three-arm separation (first, widest,
smallest) makes that unlikely.

## LZ-E - The window: viewport plus two, a bounded cold slice, and unbounded where SwiftUI is

**Ruling.** Bounded = a scroll context on the container's own axis with a known viewport. Window = anchor - 2 ..< bottom-line + 1 + 2
(`List.overscan`, 2) - divergence **637**: SwiftUI realises exactly the on-screen views (R1: 10 of 1000), MetalUI realises and
`onAppear`s up to 4 more, because the viewport is one frame stale (`DD-F` item 3) and no margin would flash on a fast wheel. Cold
(viewport 0): the first **32 lines**, then one more frame - not every line as `List` does (`MP-I`), because a 10 000-child first frame
must stay O(viewport) (`LazyWindow.coldLines`). Unbounded (no scroller, the other axis, `Deferred`, eager fallback): every line,
measured, counted - SwiftUI does the same in a scroller of the other axis (R5) and outside any scroller (A-arms).
**Evidence.** R1, R2, R5; `DD-F`; `MP-I`. **Cost if wrong.** A first-frame flash of 32 lines of estimate-sized placeholders on a
very tall first viewport (a 32-line cold slice is shorter than the viewport when lines are under viewport/32 tall): the next
frame fixes it (human check LZ1); raising the constant costs cold-frame work linearly.

## LZ-F - `LazyStackLayout` is a custom `ProposalLayout` that taints, with no kernel change

**Ruling.** The realised nodes are registered under one `requestNativeLayout(LazyStackLayout(...))`; the layout is **not** `Hashable`,
so it taints exactly its ancestors for the layout memo (`IV-`, as `VariableRowsLayout`). No registrar parameter, no `LayoutTree`
node kind, no signature line, no `Handlers` member, no `PlatformWindow` requirement.
**Evidence.** `ProposalLayoutContainer` (`requestNativeLayout`) and `VariableRowsLayout`; `everyRegistrarParameterIsInItsSignature`
is not engaged. **Cost if wrong.** A `ScrollView` above a lazy stack loses the layout memo's whole-placement hit (the keyed subtree
placement memo `SB-AD` still serves units inside). A `Hashable` layout keyed by the window would regain it per window at the cost of a
signature change in `MetalUILayout` (a shared file); not worth it before it is measured.

## LZ-G - The anchor, rebuilds by id, and window-local duplicate dedupe

**Ruling.** Prepaint corrects the scroll offset by `D = index.offset(of: anchor) - anchorY` through `noteScrollAnchorAdjustment`
(`VL-G`); a count change or a realised id that differs from the recorded one rebuilds the index by id and keeps the anchor by id
(`VL-E` item 3, `VL-O`); the index is `O(n)` to rebuild and that cost is counted (`rebuilds`), never per frame. Duplicate ids dedupe
**within the realised window** (first wins): a whole-data `Set<ID>` is `O(n)` per frame and would defeat the 10 000-child pin's point.
**Evidence.** `VL-` pins; `ForEach.produceElements` dedupes all data (`FI-A`) because it realises all data.
**Cost if wrong.** Two equal ids far apart both realise (aliased `@State`, a doubled accessibility id); the same limitation as
`List`, which never dedupes (divergence 255).

## LZ-H - A scrolled-out child keeps its state the `List` way: `TB-AH`, no `noteLoop`

**Ruling.** The lazy `ForEach`'s slot calls `noteWindowedParent(slot)` (the element scopes' `noteNamed` is then a no-op) and **never
calls `noteLoop`** (`DD-C`'s reset is exactly what a moving window must not trigger); a removed datum's state lingers until the
table's own sweep, as a `List` row's does. Out-of-window children keep `@State` while the table is within `TB-AH`'s bound (>256
entries and more than two generations out: lost). The lazy unit scope mints a named id, so it owes a `noteNamed` call and an arm in
`everyNamingSiteStartsAReturningNameFresh`. No transition ghosts for a removed lazy child (a lazy child that leaves the window is not
removed).
**Evidence.** S1 (SwiftUI retains across a round trip, S2 control); `TB-AH`; `ID-R`. **Cost if wrong.** State of a child left far away
is lost once the table is large (bounded, documented: "keep durable values in data"); SwiftUI's retention looked unbounded in the
one arm run, so this is the existing `TB-AH` divergence family, no new label.

## LZ-I - Work counters: `lazyUnitsRealized`, `lazyLinesRealized`, `lazyUnbounded`

**Ruling.** `Frame.lazyWork` (build-summed, classified `.buildOnly`) counts units realised, lines realised and unbounded fallbacks;
`FrameWork` exposes the three (class M, one public declaration each, doc comments, inventory rows). A pin compares against an eager
`VStack`/`Grid` stand-in of the same data, so "O(viewport)" is a ratio of work, never a time.
**Evidence.** `forEachIdentityWork`'s shape; practices ("performance tests count work"). **Cost if wrong.** A renamed or extra field is
a public-API change of `MetalUITesting` (class M, additive).

## LZ-J - Accessibility exposes realised children only, with no list position

**Ruling.** An off-screen lazy child has no node and no accessibility record, as an out-of-window `List` row; a realised child's
record is its element's own. `AccessibilityNode.logicalIndex` (the `List` row hint, `AB-L`) is **not** published for lazy units (a
position among 10 000 needs an accessibility set-size field both bridges would have to translate). VoiceOver is a human check
(`LZ3`), never claimed (`IX-AE`).
**Evidence.** `List`'s windowed rows (`AB-X`); both bridges translate every neutral field (the `Mirror` count), so a new field is a
shared-bridge change. **Cost if wrong.** A screen-reader user hears no "row 4 of 10 000"; carried to an accessibility follow-up.

## LZ-K - `GridItem` tracks: one pure solver, in `MetalUILayout`

**Ruling.** `GridTrackSolver.resolve(items, available, defaultSpacing: 8) -> (tracks, gaps, origin)` implements the probe's reading:
fixed exact; a flexible item whose minimum exceeds the equal share takes its minimum, the rest share what is left equally, clamped to
each maximum **without giving the excess back** (C4, C6, C15); an adaptive item takes `n = max(1, floor((rest + s)/(min + s)))` columns of
`(rest - (n-1)s)/n` clamped to its maximum, `rest` = available minus the fixed items and the gaps around them (C1-C3, C16, C17); the
gap after a track is its item's `spacing` (C7), the last item's ignored; tracks together are placed by the grid's alignment inside
`available` (C8) and the grid is `max(available, tracks)` wide with the origin at 0 on overflow (C5). At a nil available extent a
track is the widest of the **first line's** cells' answers and an adaptive item is one track (LZ4, C12). **Two adaptive items, or an
adaptive item beside a flexible one** are unprobed: the remainder is shared equally between them, MetalUI's own ruling, pinned as such
and claiming no divergence.
**Evidence.** C1-C17. **Cost if wrong.** A grid mixing adaptive and flexible items lays out differently from SwiftUI; pure and Linux-tested
so a later probe changes one function.

## LZ-L - The grid's column count is built from last frame's width; a mismatch asks for one more frame

**Ruling.** The cells a row holds are decided at build time, before layout knows the width, so `LazyGrid` builds with `columnCount`
= the solver's count for the width stored in `LazyOrigin.crossExtent` by last frame's prepaint (always right with fixed/flexible
items, whose count is static). With an adaptive item and no stored width (the first frame) it builds **one** column of the cold slice;
`LazyGridLayout` resolves real tracks from its bounds and, when the resolved count differs, prepaint calls `requestAnotherFrame()`
(divergence-13's mechanism). The layout of the mismatched frame is the built count's, never a crash.
**Evidence.** `DD-F`, divergence 13 (the same one-frame stale rule for a `List`'s viewport). **Cost if wrong.** An adaptive grid shows
one frame of the wrong column count on its first frame and on a width change (human check LZ2); a fix would publish the cross extent to
`ScrollContext` (a shared type), declined here.

## LZ-M - A grid line is a row; its extent is its tallest realised cell

**Ruling.** A `LazyVGrid`'s lines are rows of `columnCount` cells (a `LazyHGrid`'s columns of `rowCount`); the same `RowExtentIndex`
holds line extents (`extent + line spacing`); a line's extent is the tallest realised cell in it (C10, C11) and unrealised lines
count as the running mean (G2). The grid's row spacing is `spacing:` (default 8).
**Evidence.** C10, C11, G1, G2. **Cost if wrong.** A tall cell realised late shifts later lines by its excess (anchor-corrected).

## LZ-N - Not built: `pinnedViews:`, `Section`, windowed conditional members

**Ruling.** Neither is cheap: `Section` does not exist in MetalUI, and pinning one realised unit to the viewport edge means paint-time
translation with hitboxes, accessibility frames and the anchor correction following it (`GX-U`'s share-floor territory). The probe's
pinned arm (H1) read minY 0 at offset 300 but its control (H0) never reported a frame, so SwiftUI's pinned behaviour is **unproven
here**: no divergence claimed, the absence is listed under "not offered". Windowed `if`/`switch`/`for` members: LZ-B.
**Evidence.** H0/H1. **Cost if wrong.** A sticky-header list is not expressible with lazy stacks (use a `List` or an overlay) until L2.

## LZ-O - `scrollTo` reaches an unrealised ForEach element through the index

**Ruling.** A `ScrollViewReader.scrollTo(id)` whose key is a ForEach id of an **unrealised** unit resolves against
`RowExtentIndex.offset(of:)` with at most one refinement carried into the next frame (`VL-H`, `VL-P`), exactly as a variable `List`
row; keys are noted only while a `scrollTo` is pending (`DD-K`, `notesScrollKeys`), so `O(n)` ids are walked only then. A static
unit is a `scrollTo` target only while realised.
**Evidence.** T10 (`swiftui-data-and-scrolling.swift`: an unrealised lazy row is reachable, 4500). **Cost if wrong.** If the carry
cannot be reproduced for grids lane 2 may defer grid `scrollTo` (named in the record), never ship a target that lands wrong.

## LZ-P - A lazy child is an ordinary occurrence; the container's own state is compared, never plain

**Ruling.** Each realised unit runs the same `requestProposalGroupLayout` / `prepaintGroup` / `paintGroup` an element in a
`VStack` runs, so `.equatable()` skips, retained paint and prepaint replay and the graft apply per unit unchanged (test 2.13, run
under `METALUI_VERIFY_RETAINED=1`). The container's `LazyOrigin` is written only through the compared
`withState(_:initial:unchanged:)` (`RW-I`) so a settled lazy container does not bump a version: no new retained-subtree code (C14-i's
files are not touched); a lazy container that fails to replay is a counted miss, not a trap.
**Evidence.** `RW-G`, `RW-I`, `RW-S`. **Cost if wrong.** A lazy container above a retained subtree misses where `List` hits; the
`everyStateWriteSiteIsClassified` test gains a row per new file so a plain write is caught.

## LZ-Q - Verification, demo and guide

**Ruling.** The demo is `METALUI_LAZY_DEMO=1` (each section its own function; `everyProductionTreeBuildsOnAOneMegabyteThread` gains
it), the guide section and its hand-copied mirrors are `DG-C`/`DG-D`, the human-checks group is `LZ` (not run). The fourteen images stay
0 px (the demo is behind a switch; the containers add no pixel path) and `Expected.swift` is not edited. The Linux image runs
`MetalUILayoutTests` (the solver), `MetalUITestingTests` and the portable tests; `Backends/SDL` is untouched.
**Evidence.** The item's invariants. **Cost if wrong.** None beyond the verification list.

## LZ-R - Critic's pass: the taint is pinned for both layouts; two rejections recorded

**Ruling.** Both `LazyStackLayout` and `LazyGridLayout` are non-`Hashable` and so taint exactly their ancestors in the layout memo
(LZ-F, `IV-`); the spec had pinned this for no test, so tests 2.16 and 3.11 are added (a window or column-count change under a lazy
container must never be served from `LayoutMemo`; mutation: make the layout `Hashable` over a subset). Test 2.4's literal is derived
(ids 98...112). **Rejected:** (a) matching SwiftUI's no-margin realisation - the two-line overscan is kept for scroll continuity of
variable rows and is divergence 637 with a pin; (b) a `Hashable` layout keyed by the window - its key would have to hold every
measured extent, so a hit would be a stale-layout risk for no gain; (c) the probe's A3b arm does not separate first from widest (first
is widest there); A3d and A3 do (50 vs 100, 30 vs 100), so the first-child ruling stands, re-run byte for byte (62 lines identical).
**Evidence.** Probe re-run 2026-10-21 (A3d, C15, R4, S1 identical to the header). **Cost if wrong.** Two extra tests.
