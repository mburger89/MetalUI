# Retained zoom, the fillet-drag profile and `@FocusState` under `.equatable()` - design

Item C14-i (round 2, user request 2026-10-21). Branch `perf/retained-zoom` from `1bdead8d`. Rulings `RZ-A`...: [`../2026-10-21-retained-zoom-decisions.md`](../2026-10-21-retained-zoom-decisions.md).
Record `docs/record/133-retained-zoom.md`. Reserved divergence labels 625-634: **none expected** (346 is amended in place). Class: value-identical, no public API.

## 0. What is measured and what is claimed

MetalCreator's warm zoom of 50 nodes under a canvas `.scaleEffect` + `.offset` reads 1857 element requests a frame and 0/2 grafts. Cause (read from the source, to be re-confirmed
with `METALUI_TRACE_RETAINED=1` on the fixture at the red run): a scale change makes `PrepaintKey.differsOnlyByEffectTranslation` hold but `PrepaintExtras.translation(from:)` return
`nil` (linear part moved), so the prepaint decision counts `effectNotTranslation` and runs; a grafted occurrence then has no element to prepaint, so the frame is redone and prepaint
replay backs off. The paint decision refuses the same way (`ReplayKey.differsOnlyByEffectTranslation` zeroes only `tx`, `ty` of the scope vector).

No SwiftUI-facing claim is made or moved (no API, no observable difference: the oracle is a window with retention off, and `METALUI_VERIFY_RETAINED=1`), so **no new probe**. The SwiftUI
facts the work leans on are already probed and pinned: effects are layout-transparent, hitboxes follow the transform, text and images are resampled under a scale (divergence 106,
`GX-`). gpui has no analogue (it reuses a cached view's prepaint and paint only for equal bounds and mask, never across a transform; recalled, not run). `@FocusState`: divergence 346
records the exclusion as "a MetalUI ruling with no SwiftUI claim", so lifting it needs no probe either.

## 1. Lane 1 - zoom (files: lane 1 owns these)

Owns: `Sources/MetalUI/RetainedSubtree.swift` (`ReplayKey` relation, `retainedPaintDecision`), `RetainedPrepaint.swift` (`PrepaintKey` relation, `retainedPrepaintDecision`),
`RetainedTranslationCarries.swift` (geometry notes), the `PrepaintExtras` extension and `translatedHitboxes` in `Frame.swift`, new `Tests/MetalUITestingTests/ZoomFixture.swift` and
`RetainedZoomTests.swift`, the demo strip in its own function in `MetalUIDemoContent`'s retained demo, the probe-less record notes.

### 1.1 Mechanism (no CPU re-pointing is needed; `RZ-A`)

The paint record's leaves are the primitives **before** any outer scope applies (`RetainedRecord.scene`, `boundary`); `replayPaint(translated: true)` already feeds them through
`processScopes` under the **live** scopes, so a changed outer effect is applied by the same arithmetic a fresh paint uses (`effect.apply(to:flattens:outer:)`, then
`cutToEntryClip`, then `insertIntoScene`). Paths, gradients, shadows and blurs are vectors until `insertIntoScene` (they carry `local` + a `PrimitiveTransform`), so the device-pixel raster
is made then, keyed by `RasterAnchor`, and a new scale is simply a new key: **re-raster, work equal to a fresh frame, not a refusal** (`RZ-C`). The fix is therefore the **key relations**:

- `ReplayKey.differsOnlyByEffectAffine(from:)` (new, beside the translation one): same `rects`, `interior`, `nodeCount`; same scope count; every scope that differs is an
  `.effect` scope of the same `flattens`, `alpha`, `entryClipDepth`, outer clip (present or absent, bounds, radii, depth) with no shadow or blur, differing only in the six affine
  numbers (indices 4...9). Anything else is a miss, **counted by name** (`effectFlatteningChanged`, `effectClipChanged`, `effectScopeChanged`).
- `PrepaintExtras.change(from:) -> EffectChange?` (new): `.translation(dx, dy)` exactly as `translation(from:)` today (kept, byte for byte, for a pure pan), else `.affine` when the effect
  count is equal, everything but `effects` is equal, and per effect the outer clip, `hasInverse`, saved clip base are equal and only `a b c d tx ty` and the inverse's six differ. Else
  a named refusal (`effectClipChanged`, `effectInverseChanged`, `effectCountChanged`).
- Hitboxes (`RZ-D`): `translatedHitboxes(of:by:)` takes `delta` as optional; the `.affine` case passes `nil`, so the two arms that re-derive from the **current** effect (the ambient
  `inverse == recorded` swap, `AT-F`; the registered-inside step walk, `RL-I`) run and the last arm (a delta applied to an inner effect's inverse, valid only for an identity linear
  part) refuses `hitboxes`. After moving, the pointer is read against the **moved** hitboxes (`FS-P`'s rule): a point the zoom carried onto a hitbox runs the prepaint.
- Accessibility (`RZ-E`): `translatedAccessibility(of:)` already recomputes every frame from the recorded pre-effect rects and the effect chain at **any** linear part (`AT-A`, `AT-G`):
  unchanged. Geometry notes: `translatedGeometryNotes` re-runs the transform on a rebuilt proxy; a note holding **named spaces** moves them by a translation only, so under a changed
  linear part it refuses `geometryNamedSpace`.
- `ledger.anchors` and `ledger.contextMenus` hold window-space rects: for an `.affine` change they refuse (`presentationAnchor`, `contextMenus`) until a pin proves them
  recomputable (`RZ-F`; the same pin audits the translation arm, which replays them unmoved: if red, the finding is recorded and the translation arm gains the same refusal in this lane).
- Layout moved and an effect changed at once stays `effectAndLayoutMoved` (`FS-O`), counted, deferred (`RZ-K`).
- Graft: no code. A grafted occurrence needs prepaint and paint to replay; with both accepting, the frame is not redone and `retainedGrafts` rises. `phase.grafted`'s `nil` recorder
  already is the no-redo path when a refusal is a *run*; the refusal list above is what keeps a graft safe (a refusal under a graft is a redo, as today).
- `translated` counter: a zoom hit counts under `retainedTranslated` (paint) and `retainedPrepaintHits`; **no new public `FrameWork` field** (`RZ-G`). Refusals reach
  `retainedTranslationRefusedReasons` by name.

### 1.2 Pins (new file `RetainedZoomTests.swift`; fixture `ZoomFixture.swift`, built on `RPPair`)

Fixture `ZoomRoot`: ten `.equatable()` nodes in a row, each a `Component` with text, a filled rounded rect, a stroked `Path` (a `Canvas`-free `Shape`), a `Button` with an
`.accessibilityLabel`, under `.scaleEffect(s, anchor: .topLeading)` then a fixed `.offset(x: 40, y: 24)` (never identity), in a clipped frame; `inputs.scale` steps 1.0, 1.1, 1.21 (and
0.8, 2 for the non-dyadic arms). "Red at 1bdead8d" is measured on this fixture before any source change and recorded in the test's doc comment.

| # | Test | Red before | Mutation that must redden it |
|---|---|---|---|
| Z1 | `aZoomStepGraftsWithoutARedo`: grafts > 0, redos 0, backoff 0, `elementRequests <= 0.15 x` the unretained side's, `retainedTranslationRefusedReasons` has no `effectNotTranslation`, scene and published tree equal to the unretained window at every step | `effectNotTranslation`, redo, backoff | (i) `differsOnlyByEffectAffine` returns false (Z1-Z6 redden); (ii) `PrepaintExtras.change` returns `nil` for `.affine` (Z1, Z2, Z3, Z6 redden) |
| Z2 | `aZoomPublishesTheFreshAccessibilityTree(arm:)` at scales 1.1, 0.8, 2, 1.21 (`atPair`-style compare of nodes, `frame`, `visibleFrame`) | the arms refuse | the ledger's frames replayed unrecomputed; the frames shifted instead of recomputed (the 1.1 and 0.8 arms) |
| Z3 | `aZoomedNodeIsHitWhereItIsDrawn`: after each step a click on a node's drawn centre fires **that** node's action and one at the pre-zoom centre of another does not, equal to the unretained window | red only through Z1's refusals (no divergence at the old SHA: it ran fresh); the pin is the new path's oracle | `translatedHitboxes` keeps the recorded inverse (`out[index].transform` untouched) |
| Z4 | `aStrokedPathUnderAZoomIsRerasteredNotStale`: scene primitives and image identity equal to fresh; `RasterCache.lastTexturesMade` of the retaining side equals the unretained side's on the step (**work equal, no refusal**); a 1/16-pixel step (inexact) equal too | n/a (refused before) | the path leaf replayed from `finalScene` (the old stream) instead of through the live scopes: reddens by pixels |
| Z5 | `anEffectChangeThatIsNotAnAffineMoveIsRefusedByName(arm:)`: arms `flattensChanged` (`.scaleEffect(x:y:)` non-uniform vs uniform), `outerClipChanged` (a `.clipped()` inside the effect), `namedSpaceNote` (`onGeometryChange` with `coordinateSpace: .named` under the effect), `anchor` (`.popover` declarer under it): the named reason is the only refusal for it, the frame equals fresh | miss under `effectNotTranslation` | dropping the `flattens` equality, the outer-clip equality, the named-space guard, the anchor guard (one mutation per arm, each arm reddens) |
| Z6 | `aRotationStepIsReplayedExactly`: `.rotationEffect` 0 to 4 degrees and a scale step together: scene, tree, hits equal fresh | `effectNotTranslation` | as Z1 (i) |
| Z7 | `aHitboxInsideAnEffectTheOccurrenceOpenedFollowsTheZoom`: a node with its own inner `.scaleEffect`, a click at its inner button after each outer step | n/a | the `RL-I` chain walk replaced by the recorded transform |
| Z8 | `aZoomThatCarriesTheContentUnderAStationaryPointerRunsThePrepaint`: pointer fixed, zoom moves a node under it; `isHovered` paint equals fresh | n/a | skip the moved-hitbox pointer read |
| Z9 | `aZoomBeforeAndAfterOnTheBracketFixtureIsReported` (report, no threshold): printed table of `elementRequests`, grafts, redos, prepaints, paints for the zoom fixture and the bracket fixture's pan | - | - |
| Z10 | `aPurePanStillTakesTheTranslationArm`: the old pan pins stay green; a pan reports `translation`, never `.affine` (a counter-by-reason would be a new field, so the pin is `AXTranslatedReplayTests` and `TranslatedReplayTests` unedited) | - | `change(from:)` classifying a pan as `.affine` reddens `aPanUnderAnEffectPublishesTheFreshTree` at scale 0.8 |

Pins use `rsVerifying` skips the same way the AT pins do. `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` must run the whole suite silent (verify mode compares a fresh paint beside
every replay and traps naming the channel: it is the pixel oracle for Z4).

### 1.3 As built (lane 1, rulings `RZ-M`...`RZ-R`)

The mechanism of 1.1 held as written: no leaf is re-pointed, the live scopes are re-entered, paths and the other rasters re-key through the ordinary cache (Z4: raster work equal to a fresh frame). Differences from the design, each a ruling:
- the prepaint effect vector gains a **flattens** bit (index 18) so a class change refuses at prepaint, not as a paint miss after a replayed prepaint (`RZ-M`); with the guard dropped the frame still equals a fresh one, so the refusal is conservative;
- `effectNotTranslation` is retired; every refusal has a name, including `prepaintContextChanged` for a difference that is not in the effects at all (`RZ-N`);
- the pointer is read against the moved hitboxes in **both** effect arms, which keeps a carried, un-grafted node from costing a redo (`RZ-O`);
- the anchor and context-menu refusals are kept but the audit found them unnecessary for exactness (`RZ-P`); the named-space refusal is needed (`geometryNamedSpace`, Z5, dyadic scales);
- four existing pins that asserted the removed refusal were rewritten (`RZ-Q`);
- Z10 pans with a context menu on every node (the affine arm refuses it, the translation arm does not), which is what tells the two arms apart; a pan classified as affine is not otherwise visible in a differential.
Measured: ten nodes, one zoom step, element requests 115 to 5, grafts 0 to 10, redos 1 to 0 (`RZ-R`).

## 2. Lane 2 - fillet drag and `@FocusState` (files: lane 2 owns these)

Owns: `Sources/MetalUI/EquatableComponent.swift`, `ContentMemo.swift`, `StateReflection.swift`, the `@FocusState` code in `FocusState.swift` and `StateTable.swift`, `Window.swift`'s
`reconcileFocusStates`, new `Tests/MetalUITestingTests/FilletDragFixture.swift`, `FilletDragProfileTests.swift`, `FocusStateMemoTests.swift`. **Never `RetainedSubtree`, `RetainedPrepaint`,
`RetainedTranslation*`, `RetainedGraft` (lane 1's)**: a fix the profile finds there is written up as a ruling and applied by a follow-up agent after lane 1 lands (`RZ-H`).

### 2.1 (a) Fillet drag: profile first

MetalCreator's fillet drag reads 888 element requests a frame (orbit panel 199), warm. The stand-in `FilletDragFixture`: a `Slider`/drag-driven `@Observable` model value feeding **one**
panel among six `.equatable()` panels (text, rects, a stroked path, a list of rows each), plus a readout `Text` outside every panel that changes every frame; the drag is
`TestWindow.drag`. The profile (test `theFilletDragReasonsAreProfiled`, a report with a pin on the *total* after the fixes) records per drag frame: `elementRequests`, `elementPrepaints`,
`elementPaints`, grafts, redos, `retainedIneligibleReasons`, `retainedTranslationRefusedReasons`, `graftRefusals`, `contentRefusals`, and the `METALUI_TRACE_RETAINED=1` miss lines
(`traceMiss`). Candidate causes **to be confirmed or discarded by that table, not assumed**:
1. the panel holding the pressed slider (`retainedSubtreeHasPointerPressOrFocus`, `activeElement` under it) - by design, ruled so if it is the top cost;
2. `valueTrack` hitboxes in a ledger (`hitboxHandlers` refuses a layout shift, not a replay): check;
3. a panel reading the model through a computed value the memo cannot see (observed read changes every frame): by design, `.equatable()`'s contract;
4. the readout's ancestors: a container that is **not** `.equatable()` rebuilds its children whatever they replay (build recursion runs): by design, the guide's advice;
5. environment readings that are uncomparable (`uncomparableEnvironmentKey`) or an `.equatable()` over a `Binding` input.
Each fix the table justifies is a named ruling `RZ-` with before/after table rows; each cause ruled by design gets its ruling and a line in `docs/guides` is **not** edited here (record only).
If the table shows the fix lives in a lane-1 file, it is **carried** with its measurement (`RZ-H`), not attempted.

### 2.2 (b) `@FocusState` under `.equatable()` (C14-c2; `RZ-I`)

A `FocusState`'s slot is an ordinary `$state<n>` sibling written by `Window.reconcileFocusStates` through `table.write` after a frame (a dirtying write that **bumps the slot's
`entryVersion`**) and by input with `pending: true`. So the focus reading **is** a `@State` slot version: the memo's existing "own `@State` unwritten" condition already covers a change
if the slot is among the entry's bound versions. What a skipped getter loses is the **bind**: `noteFocusState` runs inside `StateBinder.bind`, and the window reconciles only
`lastFocusStates` (those bound during the frame), so a skipped component would never get its pending write applied or its value written back. Design:
- `ContentMemoStore.Entry` records the focus states a getter evaluation bound (`[(GlobalElementID, any FocusStateReconciling)]`, the `.focusState` journal events already name them);
  a **memo skip re-notes them** through `StateTable.noteFocusState` (the call a graft's `reapply` already makes), so `lastFocusStates` is the same set a build would give.
- `shape.refused`'s `hasFocusState` conjunct goes (`StateReflection`); `contentRefusals` no longer counts it.
- Slot versions enter the entry's versions (they are bound `$state<n>` slots) so a paint record's `old.versions` and a graft's `stateReads` change on a focus write: a focus move
  re-evaluates the reader and misses its record, and nothing else.
- **Soundness gate (measured before the ruling is final):** F3-F5 below pass and `METALUI_VERIFY_RETAINED=1` stays silent. If the entry's bound ordinals do not include the focus slot,
  or a skipped component's re-note cannot reproduce `lastFocusStates` exactly, the item is **re-carried** with the measured reason and divergence 346 keeps the clause.
Divergence 346 is **narrowed in place** (the `@FocusState` clause removed, `aFocusStateComponentStaysRefused` replaced); no new label.

### 2.3 Pins

| # | Test | Red before | Mutation |
|---|---|---|---|
| F1 | `theFilletDragReasonsAreProfiled`: report table before/after, plus a pin that the fixture's warm drag frame costs at most the by-design set (the number comes from the profile) | the table's refusal rows | undo each landed fix (one per ruling) |
| F2 | `aFocusStateComponentIsSkippedWhileFocusIsUnchanged` (replaces `aFocusStateComponentStaysRefused`): `contentRefusals == 0`, skips > 0 over idle frames | `contentRefusals > 0` | restore the `hasFocusState` refusal |
| F3 | `aFocusMoveReEvaluatesExactlyTheReadersOfTheMovedState`: two `.equatable()` components reading `$field == .a/.b`, Tab twice; each frame's tree equals an unretained window's; only readers whose reading changed evaluate | n/a | the slot version not entering the entry's versions |
| F4 | `aPendingFocusWriteAppliesToAComponentThatWasSkipped`: `field = .email` from a click while the declaring component's getter was skipped the frame before moves focus | n/a (was never skipped) | skip the re-note on memo skip |
| F5 | `aSkippedFocusStateIsStillReconciled`: focus moved by Tab into a bound field inside a skipped component writes its value back | n/a | as F4 |
| F6 | `aGraftedFocusStateComponentReconciles`: same under a graft (the `.focusState` journal event) and under `METALUI_VERIFY_RETAINED=1` | n/a | remove the journal event arm |
| F7 | `aFocusReaderUnderRetentionRepaintsWhenFocusLeaves`: focus ring / value-dependent colour replays correctly across focus in and out (paint record versions) | n/a | drop the slot from `old.versions` |

## 3. Cross-cutting

- **Counts:** 4117 at `1bdead8d`; expected +10 (lane 1) and +7..9 (lane 2); the one `FR-J` line; 0 `error:`; the only `warning:` SwiftPM's deprecation notice; `swift build --build-tests` 0 warnings.
- **No typecheck guard:** nothing becomes unreachable or reachable (no public declaration). If one is added, mutate it red once.
- **Pixels:** the fourteen offscreen images 0 px against `1bdead8d` (`docs/probes/demo-pixels/compare.sh`); `DemoFrameDeterminismTests` `Expected.swift` unedited.
- **Backends/SDL, shaders:** untouched (no shader change: `TE-AD` not engaged). The Linux image runs `MetalUITestingTests` (the zoom and focus pins are portable) and the portable tests.
- **Demo:** `METALUI_RETAINED_DEMO=1` gains a zoom strip in its own function (Windows 1 MB stack): a slider-driven `.scaleEffect` over the ten-node row with the counters line (grafts, redos,
  requests); expectation: after the first frames requests are O(changed nodes), grafts rise, redos 0, picture identical with "Retain" off. A demo section needs no test beyond
  `everyProductionTreeBuildsOnAOneMegabyteThread` staying green.
- **Human checks (group `RZ`, not run by an agent):** RZ1 zoom a real canvas by trackpad pinch and slider, retained on and off, edges and text look identical; RZ2 hover and click on a node while zooming; RZ3 a stroked path stays crisp at each step; RZ4 VoiceOver frames after a zoom
  (cannot be claimed by an agent, `IX-AE`); RZ5 focus ring and field focus on a retained form while tabbing.
- **Record phase** (later, not this spec's commit): CLAUDE.md paragraph (one short rule), `docs/record/133-retained-zoom.md`, `docs/divergences.md` row 346 narrowed, `docs/verification/human-checks.md` group RZ, record README row, AGENTS.md copy, census re-record if a public field appears (none planned).

## 4. Deferred, with reasons and owners

| Deferred | Reason | Owner |
|---|---|---|
| layout move **and** effect change together (`effectAndLayoutMoved`) | two translations are not combined (`FS-O`); a zoom that also moves nodes is a different workload | next C14 round (`RZ-K`) |
| crossing the identity effect (scale exactly 1 with no offset: the scope or effect entry may vanish and the count differ) | the fixture never crosses it; counted by name if met | `RZ-K`, C14 follow-up |
| a graft under a changed **clip** inside the effect | refuses `effectClipChanged` | C14-d residue |
| fillet-drag fixes whose site is in lane 1's files | disjoint-files rule | follow-up agent after lane 1 (`RZ-H`) |
| `drawText` | unchanged, `GT-F` | C14 close-out |
