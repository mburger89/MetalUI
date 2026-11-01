# Layout

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Legacy containers.** `Column`/`Row` centre the cross axis, `Box` stretches
(EP-8). **Modifier order decides which box a modifier reaches**: container and
item modifiers (`.alignItems`, `.gap`, `.flexGrow`, `.margin`) **before**
`.padding`; `.frame`, background, corner radius **after**. All wrong orders
compile. `Row`/`Column` gap is 0 vs `HStack`/`VStack`'s 8 (divergence 52) —
porting `Row {}` → `HStack {}` changes layout silently.

**Legacy `.frame`** has SwiftUI's full surface and lowers to one `Style` in
`FrameLayer.swift` `FrameSpec.style()` (`FR-C`); fixed axes via `size` +
`minSize` (never `flexShrink = 0`, `FR-P`); fill only when both maximums are
infinite (`FR-O`). `ElementGroup` keeps exactly **one** fixed `frame`
overload (`FR-S`). The two `frameStyle` oracles in `ModifiedElementTests`/
`ModifierCompositionProofTests` must change with the lowering. A greedy
frame's lower bound is its content: `.frame(minHeight: 0, maxHeight: .infinity)`
to answer below it (`LR-ET`).

**Sizing modifiers** (`width`, `height`, `min/max…`, `fraction:`) are
deprecated toward `.frame` (`FR-I`); the conversion recipe R1–R8 is `LR-ES`.
A test that needs a raw `Style` size write uses `Tests/MetalUITests/CSSSizing.swift`;
a new test that sizes a box writes `.frame`. `Component.width`/`height` are
**not** deprecated (one frame per member, `LR-BG`).

**`List`** is a windowed `Box`: `Identifiable` data, uniform `rowHeight`,
inside an enclosing `ScrollView`; windows against its own measured origin
(`DD-F`) and asks for one more frame when the window would grow. Height
answer is `rowHeight × count`, not SwiftUI's greedy one. Rows out of window
>2 generations lose `@State` once the table exceeds 256 entries (TB-AH) — keep
durable values in data. `List(selection:)` (`DD-Z`): reads the binding fresh
every frame, never prunes; click selects and focuses the list; ⌘/ctrl
toggles, ⇧ ranges; selection logic runs in input handlers so a warm frame
stays O(window). **`List(_:rowContent:)` sizes rows from content** (`VL-`,
record §82): each row exactly its content's height at the list's width (divergence 145),
the extent measured rows plus an estimate (divergence 147) through a per-list
`RowExtentIndex` (Fenwick prefix offsets, heights by id) in `ListOrigin`, the
row on top anchored across measurements and data changes by
`Frame.noteScrollAnchorAdjustment` after paint (`VL-G`, divergence 146); the
`rowHeight:` spelling is the untouched fast path (`VL-I`) — a change to one
branch must leave the other's pins and work literals unmoved.

**Controls in SwiftUI stacks (`PE-`, record §78).** The SwiftUI-named
containers (`HStack`, `VStack`, `ZStack`, `Grid`, `GridRow`, `ProposalScrollView`,
`ProposalLayoutContainer`, a `ProposalLayout`'s `callAsFunction`) build their
content with `ProposalContentBuilder`: proposal content passes through with its
type, **any other element, group or `Component` is wrapped in `LegacyContent`**,
which is identity- and layout-transparent (caller's parent and cursor, no level),
drops presentations, registers nothing, and **consumes no record — a legacy item
field (`.flexGrow`, `.margin`) there is reported by name and traps in
production** (`PE-C`; a window test over a tree that holds one pre-flights in
diagnostics mode, `PE-Z`). `ProposalFrame`, `Padding`, `Background`,
`FixedSize` and `nativeOverlay` do not take legacy content (they are the
guards' separating controls, `PE-E`, `PE-H`); `ForEach` keeps `ElementBuilder`,
so a `ForEach` of legacy rows in a stack is adopted whole (`PE-E`). `TextField`/`Slider` answer an
infinite width, `TextEditor` either axis, with infinity (`PE-D`; legacy `Row`s
too); `List` keeps divergence 84; style modifiers go on the control before any
wrapper (`PE-R`). A `ProposalScrollView` publishes its `ScrollContext` so a
`List` windows in it (`PE-V`). **`ComponentLayout` keeps its content and layout
in one heap box** (`PE-J`; `withPayload` mutates in place — a copy traps): a
`switch` over `Component` panes does not grow a debug stack with their sum, but an
inline `switch` in one builder still does, so **a branch holding a large subtree
goes in its own `Component`** (`PE-K`). `StackMeter` (debug, internal) is the
instrument; **its `Window` warning is suspended** (`PE-T`: four production trees
exceed the 512 KiB threshold, owner a `PE-L` re-take).

**Lazy containers (`LZ-`, record §134).** `LazyVStack`/`LazyHStack`/`LazyVGrid`/`LazyHGrid`/`GridItem` are SwiftUI's spellings (class A; probe `swiftui-lazy-containers.swift`)
over non-`Hashable` `ProposalLayout`s (`LazyStackLayout`, `LazyGridLayout`) that taint exactly their ancestors (`LZ-F`, `IV-`). A container's content is read as **units**
(`LazyUnits.swift`: a `ForEach` element, a static leaf or component, legacy rows through `LegacyContent`); an `if`/`switch`/`for` member makes it **eager and counted**
(`FrameWork.lazyUnbounded`, divergence 636). **One window, never forked:** `LazyLinePlanner` runs `List`'s variable-row window over lines (a stack's child, a grid's row) on the
**unchanged `RowExtentIndex`** (`LZ-C`); the viewport plus two lines each side are realised (divergence 637), a cold slice is 32 lines, unrealised lines count as the measured mean,
the anchor holds across measurements (`VL-G`), and outside a scroller everything is realised. A scrolled-out child keeps `@State` the `List` way (`TB-AH`); accessibility exposes
realised children only and no list position (`LZ-J`). A stack's cross size is the proposal else the **first** child's (the "widest realised child" premise was refuted). Grid tracks
come from `GridTrackSolver` (`MetalUILayout`, `package`, pure); `GridItem.alignment` is `ProposalAlignment?` (nil takes the grid's); an adaptive item's count is decided at build time
from the previous frame's width and corrected by one more frame (divergence 638, `LZ-L`, `LZ-Y`); a `ForEach` element producing several views is one cell (635). `pinnedViews:` over `Section` pins the current section's header/footer **by the stack's own placement** (a real node at its pinned place, painted last, extra units realised outside the window) in a
windowed stack only; a `ForEach` of sections is read as units, O(sections) per frame, grids are carried (`SP-G`…`SP-J`, divergence 915). `scrollPosition(id:)` targets are `ForEach` elements under `scrollTargetLayout()`, noted from prepaint and written to the binding from the wheel or after the frame, never from a phase (`SP-A`…`SP-C`). A new framework state write in these files is classified in `everyStateWriteSiteIsClassified`. Pins count work (`lazyUnitsRealized`, `lazyLinesRealized`). Demo `METALUI_LAZY_DEMO=1`.

**Layout and build allocations (`PA-`, record §119).** Value-identical, no public API, no divergence (labels 495–504 untouched). Hot
loops of the kernel and build do not allocate per node: `roundedRect(_:)` is the scalar `roundLayout` forwards to, `graft` reserves
**geometrically** (`reserveCapacity` is exact in Swift: never `base + n` per call, `PA-C`), a leaf key's signature words are a
`LeafKey` computed at registration and mixed in the old order so every signature is unchanged (`PA-D`), `NativeMeasurementKey`/
`MeasureKey` hash one folded word with `==` complete (`PA-K`, `PA-N`), `StateTable.mark` writes through `index(forKey:)`. The
`measureNative` order and arguments, the four layout counters and `ForEach`'s `FI-B`/`FI-K` names are untouched. **An allocation pin
is thread-filtered (`countAllocations`, Darwin only), differential and floor-corrected**: a debug build logs several events per
`malloc` and allocates per `for-in` turn (`PA-J`, `PA-O`, `PA-Q`); release allocation figures are dated measurements, not pins.
Deferred: `AmbientKey` reshape (C14-c), array-indexed measure cache (P3); the isolation-site share is unre-measured after the loops.

## The proposal layout path

The CSS engine is gone (stage 9); every element lays out through the
propose/measure/place kernel (`NativeNode` in `LayoutTree.swift`, twelve
cases + `custom(any ProposalLayout)`; a new case must choose its zero-spacing
edges). A root is placed centred at its own answer (`CN-J`).

- **Legacy elements lower** (content → padding → fixed frame, from the
  **animated** style, structure from the **declared**). An unlowerable field
  traps naming `<site>.<field>`, or reports with `reportsUnlowerableFields`
  (tests only). Every report is a permanent refusal (`owner: nil`). **A new
  legacy registration site gains its own check and an arm in
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`.**
- **Item fields are lowered by the parent** (`LR-AB`…): a lowered container
  consumes its children's `LoweredItem` records; **a record nobody consumes is
  reported by name** (`LR-AQ`) and, in production, traps — a new lowering site
  that receives children consumes or marks them. A `ScrollView`'s content
  record is left unconsumed, so a later field belongs on the declared content
  style.
- **Differential harness**: `LayoutDifferential.compare` under
  `DifferentialRoot`, asserting hand-derived literals; never a wrapping `Text`
  or greedy child directly under the root; a diagnostics-mode test
  pre-flights with `try #require` on an empty report. **A window test in a
  mode that traps pre-flights in a mode that reports.**
- **`ProposalLayout`**: `sizeThatFits` + `placeSubviews`, no cache;
  measurement cannot place; unplaced is centred. Migration: leaf →
  `requestNativeLeaf`; algorithm → `ProposalLayout`; container with
  paint/input → `requestGroupLayout` + `requestNativeLayout`.
- **Stacks are SwiftUI's** (`CN-B`…`CN-I`, probe `swiftui-stack-algorithms.swift`).
  Flexible frame is greedy (`FR-A`, `FR-M`).
- `ProposalElementGroup` has one requirement returning `[ProposalNodeID]`
  (init internal, `MC-G`). One id under two parents traps (`CN-L`). **A copy
  of a pinned entry is unpinned**: each builder-group/`EnvironmentScope` copy
  has its own pin; a new group gets its own.
- **Invalidation**: the cache lives for one call; `setLayout` traps during
  measurement; **one `isLayingOut` flag — do not split it.**
- **Validation**: reject a parameter only if SwiftUI does or it would make a
  node non-finite at a finite proposal. Stored rects finite, nothing NaN.
  Trap → clamp later is additive; the reverse breaks callers.
- **Depth guard** `NativeLayoutRun.maxDepth` = **72**; raise only after
  re-bisecting all four node kinds in **both** debug and release
  (`docs/probes/native-depth-ceiling/`). Demo deepest level ~30.
- **Work counters** `LayoutTree.lastNativeLayoutWork` (`SA-M`): branching
  tree, literals derived before the run.
- **`Grid`/`GridRow`** (`GR-`) is a kernel case, not a `ProposalLayout`. A
  `GridRow` has its own identity level; cell modifiers are transparent. The
  outermost row mark wins; the innermost cell attribute wins;
  `gridCellColumns` sums. Spacing `nil` is per-boundary (`GR-D`). A grid
  consumes no `LoweredItem`. Lazy grids are built outside the kernel (`LZ-`, record §134).
- **Registrars**: 13 on `LayoutPass` and on `LayoutTree` — count by type, not
  by file (`requestNativeGrid` lives in `Grid.swift`).
- **`ScrollView` and `ProposalScrollView` share one `ScrollChrome`** (computed,
  never stored). A byte-identical re-inline reddens nothing — don't.
- `SA-N`'s "probed, and the kernel disagrees" list is empty. Do not re-add a
  row without a probe run.

**`HSplitView`/`VSplitView` (`HS-`, record §165, divergence 206).** One engine on two axes. A split view's pane sizes are written only by its divider drag handler (a `DragGesture` whose press-time snapshot plus the total translation is clamped on the two neighbours, never accumulated); `SplitLayout` is not `Hashable`, so it taints its ancestors for the layout memo. Autosave is per split view (`splitViewAutosaveName`), not environment-propagated, and written at drag end only.

**Padding spellings (`DX-B`, record §166, divergence 208).** SwiftUI's `padding(_: Pixels)`, `(_: Edge.Set, _: Pixels)` and `(_: EdgeInsets)` exist on both vocabularies and lower to the vocabulary's one existing padding; the default-amount spellings stay absent. A new `ProposalElementGroup` modifier must be checked against `Component where Self: ProposalElementGroup` for an ambiguity.

**`labelsHidden()` (`LB-`, record §189).** An internal `Bool` environment key (`LabelsHidden.swift`, a custom key, so a retained subtree's fingerprint sees it). A control that shows its title as a separate label puts it in an `OptionalGroup` slot and passes `nil` when `environment.labelsHidden` — **removed from layout, slot reserved, gap gone** — never a zero-size `Text`; an empty title without the modifier keeps its gap. The hidden title moves to the control's `axNode.label` (a string title, or a closure label that is a `Text`, `labelPlainText`); a new labelled control owes the same arm in `LabelsHiddenTests`.
