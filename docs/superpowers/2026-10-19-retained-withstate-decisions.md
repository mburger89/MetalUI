# Retained subtrees over read-only state (C14b-3) — decisions

Rulings for item C14b-3 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), carried by record
§109 §11 and §110 §9. Prefix `RW-`. Spec: [`specs/2026-10-19-retained-withstate-design.md`](specs/2026-10-19-retained-withstate-design.md).
Record: `../record/121-retained-withstate.md` (Record phase). Branch `perf/retained-withstate` from `f557d339`. Divergence labels
reserved 515–524: **none taken**. One public declaration (`FrameWork.retainedIneligibleReasons`, `MetalUITesting`, class `M`, `RW-M`/`RW-N`), nothing else. No SwiftUI-facing claim, so no probe is owed (`RW-N`).

**Next unused id: `RW-R`.**

## RW-A — The slice: read-only state, scroll, list, unfocused field, closed-popover anchors; surfaces and open presentations carried

**Question.** The item lists five wants (read-only `withState`; `ScrollView`/`List`; unfocused `TextField`; popovers, alerts,
presentations; `GPUSurface`). What lands?
**Ruling.** Items 1, 2 and 3 land, plus the **anchor** half of item 4 (a closed `Picker`/`Menu`/`.popover` declarer records a
presentation anchor every frame, the one thing that keeps the bracket top bar prepaint-ineligible). An **open** popover, an alert,
a file dialog and any presentation stay ineligible with a named reason (`RW-K`). Item 5 (`GPUSurface` inside a subtree) is **ruled
in design, implementation carried** (`RW-L`).
**Evidence.** Measured at `f557d339` (spec §1): on the `.panels` arm's orbit frame the work left is exactly three occurrences,
the graph panel (`stateWrite`: `TextField.paintText`'s read, then the scroller's and the list's), the top bar (`presentationAnchor`
at prepaint) and nothing else; the GPU surface of the fixture is a **sibling** of the panels, so item 5 moves no orbit number.
**Cost if wrong.** A MetalCreator whose surface sits inside an `.equatable()` window component keeps that component ineligible
(a counted, named reason) until the carried item lands: no wrong pixel, only a missed win.

## RW-B — The mechanism is a versioned read set **and** a value-compared write; neither alone is enough

**Question.** The item offers "a per-entry version bumped only on a value change" or "a read-set recorded by the journal".
**Ruling.** Both, for different failures. (1) **Value-compared idempotent writes**: a framework `withState` whose body
re-stores what is there (`ScrollChrome.resolvedOffset`'s clamp, `viewportExtent`, `ListOrigin.offset`, `TextEditState.scrollX`,
a bound-selection reconcile) compares the body's result with the entry and, when equal, **writes nothing, bumps no version and
taints nothing**. (2) **A read set**: today a retained record is excluded from every non-`@State` entry by the blanket
`stateWrite` taint, so it never needed to name what it read; once a read no longer taints, the record must name it, or an input
that changes the entry (a wheel, a typed character) would leave a hit replaying the old pixels. A record, a prepaint ledger and a
graft record each carry `(id, version)` for every entry read in their window and **hit only while all are unchanged** (`RW-D`).
**Evidence.** (1) alone: a scroll that lands between frames bumps the version (input writes always bump, `RW-G`) but nothing
checks it: stale replay. (2) alone: every `withState` still bumps, so the read set is never stable. Spec §3 walks both failures.
**Cost if wrong.** A read the set misses is a stale replay: caught by `METALUI_VERIFY_RETAINED=1` (`RW-O`) and by the differential
(spec §5 test 11).

## RW-C — Two new `StateTable` entry points; the plain `withState` keeps its taint

**Ruling.** `StateTable.readState(_:initial:) -> S` (no write-back, no version bump; marks live; records a read) and
`withState(_:initial:unchanged:_:)` where `unchanged: (S, S) -> Bool` is the call site's own equality (an `internal` protocol on
`ScrollState`/`ListOrigin` is refused: `ScrollState` is public, a conformance would be too, and a dynamic cast per call is a
`HP-C` cost). The `PaintPass`/`PrepaintPass`/`LayoutPass` public wrappers (`Passes.swift` 905–925) gain the same two spellings
as `package`. **The plain `withState(_:initial:_:)` is unchanged**: it bumps and taints, so a new framework site is conservative
by default and a guard (`everyStateWriteSiteIsClassified`, spec §5 test 14) makes each site pick one of the three. **An absent
entry is a creation, a write** (version bump, `stateWrite` taint, journal-untouched): the first frame of a scroller or field
cannot be retained, every later one can (`RW-F`).
**Evidence.** Call-site census, spec §2: 34 `withState` call sites (plus the three pass wrappers): 15 are per-frame framework
bookkeeping (converted), 12 are input or test-hook writes (stay plain), 3 are the focus and `$ax` retention slots and 4 the
`$anim` baselines, which keep their own channels.
**Cost if wrong.** A call site that picks `unchanged:` with a closure that says equal too often: stale replay, caught by verify
mode and test 11; one that says different too often: a miss, counted.

## RW-D — `peek` records reads while a window is open; three records check them

**Ruling.** `StateTable.peek` appends to a `stateReads` journal **only while a recorder window is open** (one integer test
otherwise, `HP-C`); the reads of `readState` and of a compared write join it. A paint record's `versions` today are the `@State`
slots of `markJournal`; they become `markJournal ∪ stateReads` over the same slice. The prepaint ledger and the `GraftRecord` get
the same list (the graft's from `BuildJournal`'s new `.stateRead(id, version)` events, so a build skipped by the graft is still
guarded by what the skipped build read, notably `List.swift:460`'s `peek(ListOrigin)` and `ScrollView`'s raw offset). A version
mismatch is a **miss** (traced `versions`), never an ineligibility. Entries absent at record time read version 0 as now.
**Evidence.** `StateTable.entryVersion` is already the one comparison (`RetainedSubtree.swift:502`, `RetainedPrepaint.swift:165`,
`RetainedGraft.swift:301`); no new comparison is introduced.
**Cost if wrong.** Cost is the loop: bounded by the entries an occurrence reads (about 10 per scroller, 1 per field), pinned
as a work count (`FrameWork.retainedReadChecks`, spec §4).

## RW-E — Liveness has three channels, one per record; a read-only access still keeps its entry alive

**Question.** `withState` marks its entry live (`marked`); `sweep()` reaps the unmarked. A replayed occurrence runs none of its
`withState`s, so a retained `TextField`'s `TextEditState` would be reaped and reset.
**Ruling.** A read-only or compared access also appends to the open window's live list: the paint record's `marks` (replayed by
`replayPaint`, as `mark`s are), the prepaint ledger's new `liveStates` (replayed by `PrepaintLedger` through
`StateTable.touchLive(_:)`, which sets `marked`/`isLive` and touches no version), and the graft's existing `.liveState(id)` event
(`BuildJournal`, today the animation baseline's). Replaying `touchLive` is idempotent with a fresh frame's access.
**Evidence.** The three record kinds replay independently (a frame may hit paint and miss prepaint), so one channel cannot serve.
**Cost if wrong.** A field's caret, selection or scroll offset silently resets after a long idle: pinned by test 6 over 300
replayed frames, one mutation per channel.

## RW-F — First sighting is a write; the clamp frame is a write

**Ruling.** An occurrence that first creates a `ScrollState`/`TextEditState`/`ListOrigin`, or whose clamp changes the stored
offset, taints that frame (`stateWrite`, as today) and records nothing; the next frame is the first that can hit. A window
resize that moves a scroller's viewport extent is one such frame. No special casing.
**Cost if wrong.** One extra full frame per structural change: counted, not a defect.

## RW-G — Input-time writers always bump; there is no equal-value skip for them

**Ruling.** `Window.applyScroll`, the text-editing input path (`Window.swift` 2274, 3203–3208, 526), `FocusState`'s pending
reset and the list selection handlers keep the plain `withState`/`write`: every write bumps the version, even to an equal value.
**Evidence.** An input write is by definition a user-visible event; an equal-value wheel (scroll at the end) costs one miss.
**Cost if wrong.** Spurious misses on a no-op input: bounded by input rate, and misses are safe.

## RW-H — `ScrollView`, `ProposalScrollView`: converted sites, the indicator, and what still misses

**Ruling.** Converted: the build's raw-offset read (`ScrollView.swift:249`, `ProposalScrollView.swift:62`) to `readState`;
`resolvedOffset`'s prepaint clamp (`ScrollChrome.swift:108`) to the compared write over `(offset, viewportExtent)`; its paint read
(`:135`) and the indicator's `lastScrollTime` read (`:172`) to `readState`. **The fading indicator** needs no new rule: while
`alpha > 0` it calls `requestAnotherFrame()`/`noteActiveAnimation()` and the occurrence is tainted by those (`SB-S`); once
`age >= 1.0` the alpha is 0 for every later timestamp (the clock is monotone) so a record made then stays correct until
`lastScrollTime` changes, which is a version change. **Still misses (by name):** a wheel or drag that scrolls (version), a
`scrollTo` or anchor adjustment (`Frame.swift` 311/319 stay plain writes: `scrollRequest`), a content change, a viewport resize
(rects), the scroller's own first frame (`RW-F`).
**Cost if wrong.** A scroller that replays a stale offset: pinned by test 4 (wheel inside a retained panel: counted miss, scene
equal to a fresh window) and by the verify-mode run.

## RW-I — `List` under the graft: the read set is the windowing input; selection misses through its own channels

**Ruling.** A `List`'s window is a function of `ScrollContext` (the scroller's `ScrollState`, read set), its own `ListOrigin`
(`peek` at `List.swift:460`, `:1113`, `:1225`: read set) and `data` (the occurrence's value). `noteOriginAndStaleness`'s
`offset = origin` (`:663`) and the variable-row path's `entry.offset`/`extents` (`:908`) become compared writes (`extents` compared
by identity, `ListOrigin.lead`/`anchor` by value); a stale window still asks `requestAnotherFrame()` and taints. The existing
`windowedParent` journal event keeps TB-AH exact: a grafted frame re-applies the `produced`/`windowedParent` events a fresh build
makes, so rows out of window age exactly as in a fresh frame (`RK-F`). A selection change writes the caller's `Binding` (a content
or `@State` change: `versions`/observed read misses) and the key handlers run from the replayed ledger's closures, which hold the
record's `data` (equal by `==`). A selectable list keeps focus on click: a focused list is `SB-X`. The variable-height anchor
adjustment `Frame.noteScrollAnchorAdjustment` stays a plain write and taints (`VL-G`). `List` row `@State` stays TB-AH's.
**Evidence.** `listWindowIsAFunctionOfTheStateItReads` (spec §5 test 5) compares the retained window's built row range with a
fresh window's after a scroll, a data change and a resize.
**Cost if wrong.** A window that does not move after a scroll: the version check on `ScrollState` is the single guard and the
test mutates it.

## RW-J — `TextField`/`TextEditor`: eligible unfocused; focused, composing and bound-selection writes miss

**Ruling.** `TextField.prepaint`/`paintText` and `TextEditor`'s four sites use `readState`; the geometry `scrollX` write and the
bound-selection `reconcile` are compared writes (`TextEditState` is already `Equatable`). **The caret does not blink**
(`TextField.swift:19`), so a focused field has no per-frame request; it misses because the focused element is under the
occurrence (`SB-X`) and because every typed character, caret move or IME update is an input write (`RW-G`) that bumps the
version. A composition exists only on a focused field (`IM-I` drops it on blur). A selection binding written from code is a
content change of the occurrence's value or an observed read: miss. The first character after the field loses focus returns it
to eligible one frame later (`RW-F`: none; the entry exists).
**Evidence.** Spec §5 tests 6, 7.
**Cost if wrong.** A focused field that replays: a typed character does not appear. Test 7 types into a retained field and reads
the AX value each step.

## RW-K — Anchors replay; an open popover, an alert, a dialog stay ineligible by name

**Ruling.** `Frame.recordPresentationAnchor` also appends `(id, bounds)` to `PrepaintLog.anchors` while a recorder is open; the
ledger stores them and replays them through the same function (the stored bounds are window-space: the key's `ambient.offset`
and the rects are equal on a hit, so the value is what a fresh prepaint would record). `PrepaintAudit.anchors` no longer moves
for a replayed anchor. **Open** presentations keep their audit channels and reasons: `popover` (`openPopovers`),
`presentationSpace`, `presentation`/`presentationRecords` (graft), alerts and dialogs (`PresentationScope`), with the reason
visible in `FrameWork.retainedIneligibleReasons` (`RW-M`) so a panel that stays ineligible says why. Rejected: journaling an
open popover's per-frame request (its panel is built from the declarer's content at the anchor and flips against the live
window size, `OV-S`; a replay would need the whole `Deferred` presentation root in the record, the very `SB-J` cost).
**Cost if wrong.** A popover that opens at a stale anchor from a replayed declarer: test 10 opens one from a retained `Picker`
after a window resize and compares with a fresh window.

## RW-L — `GPUSurface` inside a subtree: designed, carried (C14b-4)

**Question.** Can an `.onDemand` surface with an unchanged `value:` replay?
**Ruling (design).** Yes, by four things a record would hold: the `.surface` scene op (`insertThroughScopes(.surface(quad,
target:, ...))`, already a recorded op), the `SurfaceDrawRequest` (target, scale, time, policy, `value`, `draw`) appended again
**with the same `value`** so the renderer sees an unchanged value and does no GPU work, the `SurfaceRegistry` occurrence count
(`occurrence(for:)`, a `BuildJournal` event, so ids and `buildActivity` match a fresh frame) and the target-table touch: the
renderer releases a target no request names, so the request, not the quad, is what keeps `SurfaceTargetTable`'s entry (`MV-`).
`.continuous` stays ineligible (`noteActiveAnimation`). The `draw` closure is held by the record, so the record holds it weakly
through the memo entry (`IV-R`). **Not landed here:** it moves no orbit-with-panel number (the fixture's and MetalCreator's
surface is a sibling), it touches `Frame.drawSurface`, `SurfaceRegistry` and both renderers' request handling (a `Backends/SDL`
build and the Linux image), and the draw-closure lifetime needs its own memory test. Owner: **C14b-4**, when a profile shows a
surface inside a retained window component. The reason stays visible: `surface`.
**Cost if wrong.** None now.

## RW-M — Ineligibility is counted by reason

**Ruling.** `FrameWork.retainedIneligibleReasons: [String: Int]` (public, `MetalUITesting`, a stored property on a public
struct: `swift package clean`) sums the three ineligible counters by the taint's name; `RetainedCounters` gains the dictionary
and one funnel `noteIneligible(_ kind:, reason:)` the three existing increment sites call. The Prof harness and the demo strip
read it. Pins read exact reasons.
**Evidence.** The traces of spec §1 already name them (`METALUI_TRACE_RETAINED=1`); a pin needs them without a print.
**Cost if wrong.** An allocation per ineligible occurrence per frame: only on the ineligible path, a small dictionary update.

## RW-N — No public API, no divergence, no SwiftUI probe; gpui noted

**Ruling.** Every addition is `internal`/`package` except `FrameWork`'s one `MetalUITesting` field, which owes a doc comment and
an inventory map row (class `M`). SwiftUI's invalidation is attribute-graph dependency tracking; this item makes no claim about
SwiftUI behaviour, only about MetalUI's own replay equals fresh (`PA-B`'s precedent). gpui's analogue is `AnyView::cached`: a
view's prepaint and paint are reused while its bounds, content mask and text style are equal and its entity was not `notify`'d,
so state a view reads is read-only by construction. That is from memory, not run, and it is not an authority here: MetalUI's
state is a table written by framework passes, hence the read set.
**Cost if wrong.** None: no claim rests on it.

## RW-O — Verify mode learns the read set

**Ruling.** `METALUI_VERIFY_RETAINED=1` (`SB-W`, `RK-N`) already builds a replayed or grafted frame fresh beside the replay and
compares the scene and every channel. It gains one comparison: the fresh run's `stateReads`/`readState` ids must be a subset of
the record's read set, else it traps `unrecordedRead <id>`; and a compared write that wrote in a fresh frame while the replay
skipped it traps `writeMissed`. Both new retained eligibilities (scroll, list, field, anchors) run under it over the whole suite.
**Cost if wrong.** A trap in a verifying run is the finding, not a regression.

## RW-P — Critic review: lanes rebalanced; the `RW-L` carry restated honestly

**Question.** Does the design hide scope, overlap lanes or contain a claim nothing pins?
**Ruling.** (1) The spec's lane B held the whole mechanism, every call-site conversion, anchors, the demo and tests 2–15: too large for
one agent. Lanes are re-cut by **disjoint files** (spec §6): lane A owns the instruments *and the core mechanism* (`StateTable`, `Passes`, the
three records' read sets and liveness, tests 1 before-arm, 2, 3, 9, 13, 15); lane B owns the **conversions** (scroll, list, field/editor
sites, `Frame` anchors with the ledger's anchor field, `RW-O` verify extension, tests 4–8, 10, 11, 14, the demo, the after pins). (2) `RW-L`
overstated its cost: replaying a surface request with an unchanged `value:` needs **no renderer change** (the renderer already draws on a
changed value only); what is owed is `SurfaceRegistry`'s occurrence journal event, the draw closure's weak hold and a target-table touch. It
stays carried because it moves no orbit-with-panel number, not because of a renderer rewrite; the `surface` reason stays counted (test 9).
(3) The "caret does not blink" claim of `RW-J` is the field's own doc comment (`TextField.swift:19`), re-read; the lane re-checks it with a
counted pin (a focused field's frame requests no further frame). (4) The `unchanged:` closure sites (`RW-C`) each owe a mutation that
makes the closure always-true and a test that reddens it (test 11 is the instrument); a site without one is not converted.
**Evidence.** Header contradiction (one public field vs "no public declaration") fixed above; file census re-run (`withState(` counts per
file match spec §2's 34 plus wrappers and definitions).
**Cost if wrong.** A lane that overruns: the orchestrator sees it at lane A's commit and can carry B's tail (anchors, demo) by a ruling.

## RW-Q — Rejected: an `Equatable` protocol on `ScrollState`/`ListOrigin` instead of `unchanged:`

**Ruling.** Rejected, as `RW-C` already says; recorded as a ruling because the critic re-examined it: `ScrollState` is public
(`ScrollView.swift:33`), so a conformance is public API with a divergence-inventory row; a closure keeps the surface `internal`.
