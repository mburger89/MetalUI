# Incremental invalidation and retained subtrees

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Incremental invalidation (`IV-`, record §104).** Slice 1 of C14, two parts, both leaving every phase
and channel running on an equal value. **The layout memo** is automatic: `LayoutMemo` (`AnimationStore`'s,
`MetalUILayout`, `package`) keys a measurement and a root placement by a 128-bit **structural signature**
(`LayoutTree.nodeSignature`, one pre-order pass at the start of every `computeNativeLayout`/
`measureNativeLayout`; no node id enters, grid tokens are normalised); only plain `Text`/`ProposalText`,
`Divider`, the built-in shapes, the gradient leaf and `GPUSurface` carry a key (`LayoutLeafKeys.swift`) and any other
leaf, or a non-`Hashable` custom layout, taints exactly its ancestors. **A new registrar parameter owes a
line in the signature** (`everyRegistrarParameterIsInItsSignature`); a new keyed leaf owes a key that covers
its closure and a covering test; `METALUI_VERIFY_LAYOUT_MEMO=1` recomputes every hit and traps (`IV-J`).
**`Component.equatable()`** (`where Self: Equatable`; `EquatableComponent`, opt-in, no identity level or cursor
index) skips the `content` getter while the value is `==`, its own `@State` unwritten (`StateTable.entryVersion`)
and its observed reads unchanged (one observation session per memo over the getter only, `ContentMemoStore` on
`StateTable`, swept last); `==` decides; an `@Environment` component with an uncomparable reading is refused, evaluated every
frame and counted (divergence 346; `@FocusState` is memoized, `RZ-T`). Build recursion, prepaint and paint stay whole, so the win is **counted, not
timed** (`FrameWork` memo and content counters; pins count work). Retained subtrees are built as paint replay and the placement memo (`SB-`, below); carried:
an environment epoch (C14-c), per-row `List` scopes (C14-d). `drawText` was deferred here (`IV-O`) and is built since `DT-`.
A main-actor test off macOS does not idle after a tracked frame (the observation hop), so a session-count pin
is Darwin-only (`IV-Q`). **A memo or retained observation handle holds its entry and store weakly** (`IV-R`): its `onChange` lives in the observed model's registrar and the entry's pristine content holds the model, so a strong hold is a cycle that outlives the window (`MemoryReleaseTests`). The demo is `METALUI_INVALIDATION_DEMO=1`.

**Retained subtrees (`SB-`, record §109).** C14b, two lanes, no public API beyond `FrameWork`'s ten counters, no divergence.
**Lane 1 replays an `.equatable()` occurrence's paint, not prepaint** (`SB-AA`: the paint-only ambient — opacity stack, shadow, blur and
composite scopes — is pushed by ancestors' `paint` after every prepaint, so a prepaint decision cannot see it): the decision, the
`ReplayKey` and the recorder are in `paintGroup`; build, layout and prepaint still run. A record hangs off the `ContentMemoStore` entry
(swept with it) and hits only while the value, bound `@State` versions, observed reads, layout, the ambient at paint and the whole
environment are equal and the hovered, pressed or focused element is not under it (`SB-X`); a descendant whose content ran kills its
ancestors' records (`SB-AC`); a subtree that scrolls, edits text, animates, shows a popover/alert or draws a surface, or sits under a
custom environment key, is ineligible (a settled scroller, an unfocused field, a `List` and a closed popover declarer are not, since `RW-`, record §121). **Scene output equals a fresh frame:** `METALUI_VERIFY_RETAINED=1` runs the fresh paint beside
every replay and traps (`SB-W`); a test that must see every prepaint sets package `Window.testingRetainedSubtrees = false`. **Lane 2 is
the subtree placement memo alone** (`SB-AD`): `LayoutTree.markPlacementRoot` roots restore their unrounded pre-order rects from
`LayoutMemo` under `PlacementKey(signature, proposal, bounds)`, origin included, no translation; `Color` and empty containers are keyed
leaves; `METALUI_VERIFY_LAYOUT_MEMO=1` covers it. Carried together (`SB-AE`): the graft, the `StateTable` journal, the counted redo,
prepaint replay and the build skip. Measured on the bracket fixture (`BracketFixture.swift`, node drag): element paints 1084 -> 178 per
frame, release median -18 %, debug -14 %; **pins count work, never time**. A new `Frame` site that pushes paint-only ambient owes a
field in `AmbientKey`. The demo is `METALUI_RETAINED_DEMO=1`.

**Retained build skip (`RK-`, record §110).** C14b-2, no public API beyond ten more `FrameWork` counters, no divergence (405–414 unused),
`Backends/SDL` untouched. **Prepaint replay:** an `.equatable()` occurrence's prepaint registers into a `PrepaintLedger` (hitboxes in
the one ranking's order, focus, accessibility records and nodes, press-only actions, context menus, element bounds, tallies) replayed
while its key is equal; **a paint-time ambient (SB-AA) that differs for a replayed prepaint abandons the frame after paint and
`Window.buildAndAdoptFrame` builds it again once with every replay off** (the redo; `AnimationStore.checkpoint`/`rollbackBuild`, 8
builds of window backoff, a per-entry doubling quarantine): **a store a build mutates non-idempotently owes a `rollbackBuild`**. A
render-effect translation replays through the live scopes (translated replay; a hitbox clip that depended on it refuses, `RK-G`, `RK-S`).
**The graft:** an unchanged occurrence skips its build recursion (`RetainedGraft`): its layout rows come from a recorded
`LayoutSegment` (`LayoutTree.graft`, every table restamped), the `StateTable` events its build made are applied again through the
table's own funnels (`BuildJournal`, `Frame.reapply`: ID-C/ID-R sweeps, `noteNamed`, `entryVersion`), a grafted `ComponentLayout` has
no payload, a pointer, press, focus or hover under it grafts nothing, and a wrong decision is the same redo; a refusal is counted by
name. **A new `StateTable` write site owes a journal event**. `METALUI_VERIFY_RETAINED=1` builds every replayed or grafted frame twice
and traps naming the channel (`RK-N`, `RK-V`, `RK-AA`). Measured on the bracket node drag: element requests 798 -> 208 (`.value`) and 167 (`.panels`),
prepaints 886 -> 219 and 176, release thread-CPU -23 % to -26 % (dated, a shared Mac); **pins count work, never time**. `drawText`
stays deferred (`RK-I`). Carried: layout or scroll translation, popovers and surfaces inside a subtree (C14b-3), an environment epoch
(C14-c), finer scopes (C14-d). The demo's switches are in `METALUI_RETAINED_DEMO=1`.

**Environment epoch (`EE-`, record §120).** No epoch counter: an `.equatable()` component that declares `@Environment` is skipped
while the **readings** of its declared properties are unchanged (`Environment.probe`, collected by `StateBinder.bind` into
`Frame.environmentReadings`, stored in `ContentMemoStore.Entry.readings`): an `Equatable` value by `==` (one `as? any Equatable` per custom-key
write; an isolated conformance compares on the main actor only), a class or `@Observable` instance by identity (the probe reads
`values.object(_:)`, **never the trapping `read`**), read properties by the one observation session; a declared property the getter never
reads still counts (`EE-A`…`EE-D`). **Still refused and counted** (divergence 346, narrowed; `@FocusState` is memoized since `RZ-`, below): any uncomparable reading
(a closure, a struct holding one, `\.self`, `\.textMeasurer`). Retention keeps its whole-position ambient (`EE-F`): the fingerprint gains
`custom` readings and provided object **instances** (`EE-K`), an unread change at the position skips the getter but misses the replay
(C14-c3), and `uncomparableCustomCount` replaces `customKeyCount` at the three retention sites (the graft site is unseparated, C14-c4).
No public declaration. Pins count work (`EnvironmentReadingTests`, `EnvironmentEpoch*Tests`).

**Retained read-only state (`RW-`, record §121).** C14b-3: a framework **read of `StateTable` is not a write**. `readState` (no version
bump, no taint, marks the entry live, records a read) and the compared `withState(_:initial:unchanged:_:)` (an equal result is a read, a changed
one today's write) sit beside the **plain `withState`, which keeps bumping and tainting**: a new framework site picks one of the three and
`everyStateWriteSiteIsClassified` counts them per file; input-time writers stay plain and always bump (`RW-G`); `unchanged:` is a call-site
closure, never a protocol on `ScrollState`/`ListOrigin` (public, `RW-Q`). **A frame-long read journal** (`StateTable.readJournal`, appended
while retaining, `peek` included; a slot with its own channel (`$ax`, `$focus`, `$anim`) is not a read) gives the paint record, the prepaint
ledger and the graft record a read set of `(id, version)` that must be unchanged for a hit, a mismatch being a counted **miss**; liveness
runs in three channels (the record's `marks`, the ledger's `liveStates` through `touchLive`, the graft's `.liveState`) so a replayed field's
`TextEditState` is not swept (`RW-E`); a replay re-notes what it stands for. A creating read, a clamp that changes the offset and a first
sighting are writes (`RW-F`); a record made then gains its ledger one counted miss later (`RW-S`). **Eligible now:** an unfocused
`TextField`/`TextEditor`, a settled `ScrollView`/`ProposalScrollView`, a `List` whose window did not move, a closed `Picker`/`Menu`/`.popover`
declarer (its anchor replays from the ledger, `RW-K`). **Still miss or refuse, by name:** a focused field, a typed character, a wheel or drag, a
selection change, `scrollTo`, an open popover, alert or dialog, a `GPUSurface` (`surface`, carried `RW-L`), `.continuous` always.
`FrameWork.retainedIneligibleReasons` counts the three ineligible counters by channel name (`RW-M`); `METALUI_VERIFY_RETAINED=1` also traps
`unrecordedRead` and `writeMissed` (`RW-O`). **A read a record does not name is a stale replay**: a new framework read of state goes through
`readState`/`peek`, never a private store. Orbit with panels: element requests 115 to 6, prepaints 117 to 7, ineligible 1/2/1 to 0/0/0. One
public `MetalUITesting` field, no divergence (labels 515–524 untouched), no SwiftUI probe. The demo's panel strip is `METALUI_RETAINED_DEMO=1`.

**Observation off the main thread (`RU-`, record §106).** `Window.markDirtyFromObservation` recognises
the flush's own sentinel `onChange` by **thread** (`Window.flushingThread`, set around the sentinel
write), never by `Thread.isMainThread`: Swift Testing runs the main actor on a pool thread, so the old
test hopped and dirtied the window for ever (`runUntilIdle()` threw `notIdle` after a click on Linux,
item C29; macOS value-identical). A write from another thread still hops. No public API.

**Memo observation off the main thread (`MO-`, record §123).** An `.equatable()` occurrence's decision flags (`stale`, `observedChange`, the
serials a handler compares, a monotonic `changes`) live in one **locked** `MemoFlags` per entry (and per `RetainedSession` for its serial) and
are set **synchronously by whichever thread the observation `onChange` fires on**, never behind a `Thread.isMainThread` hop: off Darwin Swift
Testing's main actor is a pool thread, so the old flag arrived after the next frame's skip, replay or graft decision (`MO-A`; the same fact as
`RU-A`). `Entry.stale`/`observedChange`/`serial` are forwarding properties — a stored `var` of those names reopens the bug. The handle holds the
`MemoFlags` strongly and the entry, store and session weakly (`MO-B`, `IV-R`); `armed` and `markDirty` stay behind the old branch and decide
nothing (`MO-C`; `armedSessions` lags off Darwin). `materialize` clears `stale` in the locked step that bumps the serial, before the getter
(`MO-D`); a record's clear is a no-op when a fire landed since its phase opened (`MO-F`). No public API, no divergence. **Pins:** both red on macOS: a real `Thread`
writing a retained-only model (`MO-G`) and `MO-F` through the `package` seam `RetainedTestingHooks.beforeRecordClear` (record §123 §6).

**Finer retention scopes (`FS-`, record §126).** No implicit element, row or modifier scope: the retention unit stays an `.equatable()` `Component`, whose
changed row already misses alone (`FS-A`, `FS-B`). **A `List` row replays its prepaint and grafts** because a paint **hit** whose prepaint ran refreshes the standing
record's stale ledger (`RetainedSubtree.refreshLedger`, only when `ledger.reads` is a subset of `record.versions`, `FS-N`); the graft site's `uncomparableCustomCount`
conjunct is gone, `BuildKey.environment` refuses (`FS-H`). **A row that moved by layout (K1) or scroll offset (K2) replays translated** (`RetainedShape.shift`,
`ReplayKey`/`PrepaintKey.shapeInterior`, `Frame.movedPaintRecord`/`movedPrepaintLedger`, `RetainedTranslation.swift`; extends `RK-G`/`RK-S`, never forks it): accepted only for
a **whole-device-pixel** delta on exact (1/16, below 2^19) numbers (`FS-M`), leaves rect, glyph, image (path, gradient, surface, shadow, blur, backdrop, an inner paint scope, a
transformed primitive refuse by name), a mask moved only when strictly inside the entry clip; hitboxes keep their uncut rect and clip depth (`Hitbox.unclipped`) so a scroller's cut
is recomputed, and the pointer is read against the moved hitboxes (`FS-P`); accessibility records, press-only actions, menus and handler hitboxes refuse; a hit rebases record and
ledger. `METALUI_RETAINED_TRANSLATION=0` / `Window.testingRetainedTranslation` is the A/B. One public field, `FrameWork.retainedTranslationRefusedReasons` (class M); no
divergence (labels 555-564 untouched). Shifted frame 171 / 172 / 244 -> 3 / 4 / 4 with the graft; pins count work. Carried then, built or pinned in record §128 (`RG-`): placement-memo translation (`FS-G`), the unpinned
`hitboxClipped`, a shift under a moved render effect. Demo: `METALUI_RETAINED_DEMO=1`'s shift-and-scroll strip.

**Warm and cold frames (`CF-`, record §127).** Value-identical, no public API, no divergence label (565–574 untouched; 346 narrowed). `@Environment(\.textMeasurer)` is a
comparable `EnvironmentReading`: the text system **instance** (never the per-frame `TextSystemBox`) plus the two default `ResolvedTextStyle`s it resolves, so an
`.equatable()` reader is skipped, not refused (`CF-A`). A redo frame's `contentEvaluations` carries the abandoned attempt's getters; every other counter is the redo's own
(`CF-C`, `CF-D`). **A subtree placement restored from `LayoutMemo` touches its `Footprint`** (the `MeasureKey`s and inner `PlacementKey`s its recording looked up, run-cache hits
included), so the next frame's grafted occurrence still finds its measurements and `warm[n] == warm[n+1]` holds over the whole `FrameWork` from the frame after the records
exist (`CF-E`, `CF-J`); the root placement has no footprint, a named residue. The cold-frame profile found no ledger-snapshot cost and landed no fix (`CF-K`). Pins count work.

**Retained geometry (`RG-`, record §128).** An `.onGeometryChange` scope in an `.equatable()` occurrence no longer taints its prepaint ledger (`RK-E` is replaced): `Frame.noteGeometry` records a
`GeometryNoteRecord` and an equal-key replay **re-notes it in order into the lifecycle store** (a skipped note is a G7 re-report of `initial`, since `closeGeometry` drops an un-noted key); `KF-J`'s
delivery is unchanged (`RG-A`, `RG-B`). A translated replay of a ledger with a note refused `geometryTranslated` (`RG-C`) and such a ledger was never grafted (`RG-J`); `onModifierKeysChanged` stayed a taint (`RG-D`): **all three superseded by `RL-` (above)**. **A subtree placement restored from `LayoutMemo` at another origin is translated**
(`translatedPlacements`, origin-free key `(signature, proposal, width, height)`, per axis a bit-equal or exact-sixteenth origin against an exact record, never a subtree holding a `.custom` layout, checked by
`METALUI_VERIFY_LAYOUT_MEMO=1`; it carries the `CF-E` footprint, `RG-L`, `RG-P`); a card in a plain stack misses (the proposal moves). `hitboxClipped` is pinned (reachable only where the clipped region paints
nothing, `RG-M`) and a shift under a moved render effect still refused, counted `effectAndLayoutMoved` (`RG-N`; built since `EL-`). **`GlyphAtlas.dirtyRects`** is a list (same-shelf x-adjacent slots merge, cap 8, then one
sticky bounding rect until `clearDirtyRect()`), `dirtyRect` its computed union: Metal `replace`s per rect, SDL packs one transfer and copies per rect (`mui_renderer_finish` takes rects), the headless counter is the
sum of areas (`RG-H`, `RG-I`, `RG-O`). One public declaration (`dirtyRects`, class M), no divergence (575-584 untouched), no shader change. Pins count work.

**Accessibility under an effect-translated replay (`AT-`, record §129).** Value-identical, no public API, no divergence (labels 585-594 untouched). An effect-translated prepaint replay
(`RK-G`, `RK-S`) **carries accessibility records**: a record made under a render effect keeps the operands of its frame (`AXEmission.local`, `PrepaintLedger.axNodeLocals`: the pre-effect rect, the
clipped rect, the effect steps as `AXEffectChain`) and the replay **recomputes** the frame and visible frame against the current effect with `prepaintWithRenderEffect`'s own arithmetic, never shifts a
bounding box (a shifted box rounds twice; `AT-A`, `AT-G`). `translation(from:)` and `translatedHitboxes` no longer assume an identity linear part: a hitbox carrying the ledger's ambient inverse takes the current
effect's (`AT-F`). A scale or rotation change replays since `RZ-` (below; `effectNotTranslation` is retired). **A new record made under an effect owes its local rects** (else `accessibilityUnrecorded`, a counted miss). Layout translation's `accessibilityRecords` refusal and a hitbox opened inside the occurrence's own effect under a non-identity scale (`hitboxes`) were carried here and are built in `RL-` (above). Pins count work
(`AXTranslatedReplayTests`).

**Retained lifecycle (`RL-`, record §131).** Value-identical, no public API, no divergence (labels 605-614 untouched). **A replay or graft re-notes presence into the store and never computes a delivery** (`RL-A`): `LifecycleStore` forgets any key a build did
not note, so `onAppear`/`onDisappear`/`onChange`/`.task` inside an `.equatable()` occurrence no longer refuse the graft: their notes are build-journal events with relative orders re-noted by `Frame.reapply` (`RL-C`, `GraftRecord.lifecycleOrders`; not a `StateTable`
write site), `onModifierKeysChanged` is a ledger `ModifierNoteRecord` holding no value (`RL-B`, amends `RG-D`), and the store's diff decides every delivery in `drainLifecycle`, outside every phase (LC-F, LC-H, TF-A, PX-F). A replayed closure is the standing one (`RL-L`).
`BuildAudit.lifecycle` is now a tripwire for a registration that bypassed the journal (**a new lifecycle-registering site goes through the journal**, `RL-D`); verify mode gains channel `lifecycleStore`. **Translation carries:** a layout, scroll or effect translated replay
**recomputes** a geometry note (proxy rebuilt, `transform` run again; a named space declared inside moves with it only for a linear part of multiples of 1/16, else `geometryNamedSpace`; a note under the occurrence's own effect refuses a layout shift `geometryUnderEffect`; an outer
named space never reaches a note, `RL-E`, `RL-O`) and `RG-J` narrows to a note a translation cannot recompute (`RL-G`, `RL-Q`: a grafted observer costs 0 redos across a shift); layout translation moves accessibility records by the hitbox rule (`AXEmission.clipDepth`,
`accessibilityClipped`, `accessibilityUnderEffect`, `RL-H`, amends `AT-C`); a hitbox inside the occurrence's own effect is re-derived from a **validated** step chain (`Frame.hitboxChains`, `RL-I`, closes `AT-G`). **`surface` stays refused** (`RW-L`, `RL-M`: one paint per
frame, a replay would owe the registry touch and the standing draw closure). Carried: a note under an effect on a layout shift, a non-dyadic named space, `FS-G`. The `rebased` modifier copy and `movedAccessibility`'s `clipDepth` arm are pinned (`aRebasedLedgerCarriesItsModifierNote`, `aLayoutShiftMovesARecordCutByAClipInsideTheOccurrence`, record §131 §8). Pins count work.

**Retained zoom (`RZ-`, record §133).** Value-identical, no public API, no divergence label (625-634 untouched; 346 narrowed). **An affine change of an outer render effect (scale, rotation, translation) replays and grafts** instead of refusing: a replayed record re-enters the **live**
scopes through `processScopes`, so nothing is re-pointed (`RZ-A`), text and images are resampled under a scale (divergence 106) and a vector raster (path, gradient, shadow, blur) re-keys through `RasterAnchor` at insert, work equal to a fresh frame (`RZ-C`). The key relation admits a change confined to the
six affine numbers (and the inverse's) of `.effect` scopes with equal flattens class, alpha, outer clip, entry depth and counts (`ReplayKey.differsOnlyByEffectAffine`, `PrepaintExtras.change(from:)`, `RZ-B`); the prepaint effect vector gains index 18, `effectFlattens`, **appended: a new entry appends, indices 0...17 are read by number** (`RZ-M`);
hitboxes re-derive with no delta (`AT-F`, `RL-I`), accessibility through `AT-A`, geometry notes through `RL-E`, and the pointer is read against the **moved** hitboxes in both effect arms (`RZ-D`, `RZ-O`). **`effectNotTranslation` is retired; every refusal is named** in `retainedTranslationRefusedReasons`: `effectFlatteningChanged`, `effectClipChanged`,
`effectInverseChanged`, `effectScopeChanged`, `effectCountChanged`, `prepaintContextChanged`, `geometryNamedSpace`, `presentationAnchor`, `contextMenus` (the last three and the flattens class are conservative: the frame stays equal to a fresh one without them, `RZ-M`, `RZ-P`; a lift cites that evidence). Ten nodes, one zoom step: element requests 115 to 5, grafts 0 to 10, redos 1 to 0.
**`@FocusState` is memoized** (`RZ-T`, C14-c2): its `$state<n>` slot is a memo slot (`stateOrdinals`) and `FocusState.Box.reconcile`'s version bump is the changed reading, so an `.equatable()` focus reader is skipped while focus is unchanged and evaluated when it moves; a graft's journal `.focusState` arm re-notes it. **Fillet drag** (`RZ-S`): no framework refusal found; a panel set bound to **one `@Observable` array property** misses on every panel (observation is per property), by design: give each panel its own object. Carried: layout move plus effect change together (`effectAndLayoutMoved`, `FS-O`), a named space under a zoom, lifting the conservative refusals.

**One miss per changed occurrence (`DM-`, record §140).** Value-identical, no public API, no divergence label (695-704 untouched). A change frame's retained build and prepaint **observe whenever the frame is a certain
miss** (`ContentMemoStore.Entry.needsObservation` also reads `record.contentSerial != serial || observedChange`; `EquatableComponent.buildGroup` hands the window `observed || descendantRan`), so the record the miss makes is
`coverageComplete` and the next unchanged frame hits: a changed occurrence costs one miss, not two (`RW-S` amended: it still held only for a key-only miss until `AM-`, record §146). The two coverage halves
(`coverageBuild`, `coveragePrepaint`) are kept apart. **`METALUI_TRACE_RETAINED=1` (or `RetainedTrace.sink`, package) names every failing conjunct of the paint and prepaint decisions** (`PaintInvalidation`/
`PrepaintInvalidation`, which the decisions themselves read, so the trace cannot drift), prints 120 characters of path (`METALUI_TRACE_RETAINED_PATH`) and the writer behind an `observed` fire; an empty reason list prints
`unclassified` and a test asserts zero; off it costs nothing (autoclosure behind one switch). **A soundness pin needs an arm whose read only the retained windows see** (`DMArm.plain`): `.observed` is covered by the memo session.

**Retained move miss and the drag ambient miss (`AM-`, record §146).** Value-identical, no public API, no divergence (755-764 untouched); amends `DM-`. **A key-only miss (a fractional move, `.moved`) leaves a record that hits the next frame**: the prepaint predicts the miss from the standing record's `rects`/`interior`/`shapeInterior` against the geometry just read and opens the observation window (`RetainedPhase.prepaintObserved`, `AM-A`), and the paint miss branch inherits build coverage only when the record is valid, `closedOnRecord`, `ambient` and `nodeCount` equal (`RetainedPhase.inheritsBuildCoverage`, `AM-B`; inheriting on every miss is a soundness hole, pinned). Moved occurrence: change frame h4 m4, settle frame h4 m4 to h8 m0. **`snappingTransaction` and `disablesAnimations` are not part of a retained key** (`RetainedTransactionKey.swift`, `transactionNormalised` on `AmbientKey`/`ReplayKey`/`PrepaintKey`, applied at the paint and prepaint decisions, `AM-D`, `AM-L`): an animation starts only on a changed value, already a miss on its own conjunct; a `DragGesture`'s parked transaction (`AN-Y`) no longer misses every panel twice (`h0 m8, h0 m8` to `h7 m1`), and the `[coverage.build, coverage.prepaint]` lines after a change were its second frame (`AM-J`). The graft's `BuildKey` still keys both (a flip frame builds, no miss). The trace names `key.ambient.environment.<field>`, cuts a path at a `/` with a `…/` prefix, and a fire's cause is the frame after the observation machinery, `release-inlined` when none (`?` only unsymbolicated, Windows; `AM-N`; probe `observation-fire-cause-release.swift`). **Carried, C14-m:** the `key.ambient.environment` half of MetalCreator's lines did not reproduce (`AM-M`), `[noRecord]`/`first-or-dropped`. Pins count work (`RetainedMoveMissTests`, `RetainedAmbientMissTests`, `RetainedTraceTests`).

**Retained environment override (`EO-`, record §148).** No source change, no public API, no divergence (775-784 untouched). **An `.environment(\.colorScheme, same)` override (and one of every other stamped key: `displayScale`, `controlActiveState`, `accessibilityReduceMotion/Transparency`, `theme`) is an equal retained key frame to frame**: `retainedFingerprint` compares every field by value and `scopedValues` runs once at layout, so MetalCreator's 187 `colorScheme` misses are one window-start scheme transition (`CR-Q`; an inference from the trace's neighbours, a re-trace after #126 is owed, `EO-B`). The pins (`EnvOverrideFixture.swift`, incl. a `.background { shape.fill(material).environment(...) }` attachment and the real-change separating arm) were green on arrival and are proved by mutation; a real scheme change still misses naming `colorScheme` and repaints. If a per-frame `colorScheme` miss reappears, it lives in a shape the fixture lacks (an override inside a `Deferred`, a theme-derived scheme): build the separating arm first.

**Retained theme pin (`TH-`, record §149).** No source change, no public API, no divergence (785-794 untouched). **`EnvironmentFingerprint.theme` is the only conjunct that sees a theme** (`Theme` is read at paint only): the paint key (`retainedAmbientKey()`) alone protects a `.theme(_)` change, a `Window.lightTheme` assignment at an unchanged scheme and a palette override from a stale replay (M2 reddens seven pins, record §149); the graft key's copy is conservative and survives its own mutation (`TH-C`, M3), kept because the environment is keyed whole. Record 148's surviving C1 was a pin gap: `RetainedThemeTests` closes it. **A theme-bearing test separates the field from `colorScheme` by assigning the window's theme at an unchanged scheme** (`TH-B`).

**Layout and outer effect moved together (`EL-`, record §157).** Value-identical, no public API, no divergence (865-874 untouched). `shiftAndEffects` (`ReplayKey`, `PrepaintKey`) accepts a key whose rects/scroll offset moved **and** whose outer effect scopes differ in the affine numbers only, delegating to `shift` when the effects are equal (the layout arm cannot move) and to the effect arm when the rects are equal: replay is `effect_now(local + delta)`, the whole-device-pixel delta added in the occurrence's own pre-effect space (leaves, hitbox `bounds`, accessibility locals, geometry `moved`, element bounds), the effect applied second by the live scopes or by re-derivation (`Frame.rederived`, `movedCombinedLedger`, `shiftedLocals`); a ledger and a record rebase to the **whole new key** with the moved locals (`EL-G`, `EL-L`). **Refuses by name:** the `RZ-` effect refusals, `presentationAnchor`, `contextMenus`, `pressOnly`, the hitbox shape gates, `geometryNamedSpace`, and the new `effectAndLayoutInner` (anything registered inside an effect the occurrence opened); **`effectAndLayoutMoved` is retired**. The graft is untouched. Header over a six-card zoom: requests 69 to 9, prepaints 71 to 11, redos 1 to 0, grafts 0 to 6. Demo strip in `METALUI_RETAINED_DEMO=1` (the demo test's window is 820 high to hold it). Pins count work.
