# Retained move miss - decisions

Rulings for items C14-k and C14-l. Spec: [`specs/2026-10-22-retained-move-miss-design.md`](specs/2026-10-22-retained-move-miss-design.md). Record: `../record/146-retained-move-miss.md`.
Branch `perf/retained-move-miss` from `b1c1269f`. Reserved divergence labels 755-764: none taken.

Prefix **`AM-`**, lettered. **Next unused: `AM-J`.** (Moves in the commit that appends a ruling.)

**Carried.** `DM-B`, `DM-C`, `DM-D`, `DM-E`, `DM-L`, `DM-O`, `SB-V`, `SB-AA`, `RW-S`, `RK-C`, `FS-M`, `EE-F`, `GS-`, `AN-Y`, `PA-J`, `MO-A`.
No SwiftUI probe, no gpui comparison: no observable behaviour moves (`AM-H`).

## AM-A - Prepaint half of a key-only miss: a geometry predictor at prepaint

**Question.** The key is known at paint; the prepaint window opens before it. How can the record a key-only miss makes cover the prepaint?
**Ruling.** The occurrence's geometry is already read at prepaint (`readRetainedGeometry`). `prepaintObserved` is `needsObservation || (record exists && rects/interior/shapeInterior differ from record.key)`. Over-observing is sound; an unpredicted miss (an ambient difference) keeps today's second miss.
**Evidence.** `retainedPrepaintPhase` calls `readRetainedGeometry` immediately after building the phase; record 140 sections 3 and 5 (`DM-D2`: "the prepaint half needs its own window on the key-only path").
**Cost if wrong.** A predictor that says "same" when paint says "moved" costs one extra frame of misses (the status quo). One that says "moved" wrongly opens a session in a hit frame: pinned by `aSteadyFrameOpensNoMoveWindow`.

## AM-B - Build half of a key-only miss: inherited from the standing record, geometry-only

**Question.** The build window closed before anything could know the key would differ. Can its coverage be claimed?
**Ruling.** Yes, only when the window was closed *because* the standing record was complete and clean (`closedOnRecord`), every other conjunct held, and the key difference is confined to `rects`, `interior`, `shapeInterior`. The record's own build session is still armed (no fire: `observedChange` false; serial equal), so the reads of an equal-valued rebuild under an equal ambient and environment are the reads that session already covers. An ambient or `nodeCount` difference does not inherit (a different environment may read different observables).
**Evidence.** `DM-L` already claims `observed || descendantRan` on the same argument; record 140 m9 (`observed: true`) was equivalent on every fixture, so the claim is sound where measured; the build never reads layout.
**Cost if wrong.** A stale replay of a plain child's observable read after a moved frame. Verify mode traps, `aWriteAfterAMovedMissIsStillSeen` and `anAmbientMissDoesNotInheritBuildCoverage` pin both sides (m3).

## AM-C - The 179/178 `coverage` lines are two different second frames

**Question.** Is MetalCreator's `[coverage.build, coverage.prepaint]` after a change the same cost as the `.moved` arm?
**Ruling.** Partly. After a *geometry* move it is (`AM-A`, `AM-B`). The paint lines `[coverage.build, coverage.prepaint, key.ambient.disablesAnimations]` (178) carry the ambient difference in the same line: they are the frame after an ambient miss, which lane 1 cannot cover (paint-only ambient, `SB-AA`) and `AM-D`/`AM-E` remove by removing the first miss. Lane 1 measures which lines remain on the fixtures and says so; it builds nothing for ambient.
**Evidence.** `fillet-only.log` (read-only): the 179 and 178 counts match the 187 ambient lines' neighbours and share their paths; the same two root-near occurrences (paths of nine `positional(0)`) recur 20-21 times each.
**Cost if wrong.** A remaining `coverage` line after both lanes is a finding recorded with its reasons, not a silent pass.

## AM-D - `disablesAnimations` and `snappingTransaction` leave the key of a record with no animation touches

**Question.** A `GestureState.updating` body (or `withTransaction`) sets `disablesAnimations` for one build; the next build's root transaction differs. Must every retained occurrence miss?
**Ruling.** No. Both fields only decide whether an animation *starts*, which needs a changed value; a valid record has none (a changed value moves the serial, fires an observer, or moves a keyed geometry/ambient field). They are zeroed in `retainedKey` and `retainedPrepaintKey` when the standing record holds no animation touches (`touches.isEmpty`); a record with touches keeps both. A new record made under an insensitive old one carries a normalised key and misses once if it turns out sensitive. The lane searches for a separating arm (`.animation(_:value:)`, a transition, a mid-flight `withAnimation`); if the mutation "normalise unconditionally" stays green it is recorded as an equivalent mutant (as `DM-O`), and the `touches` guard stays as belt and braces.
**Evidence.** `scopedTransaction`: `changed && !disablesAnimations` is the only read; `AnimationStore` tracks are touched into records (`r.touches`); `GestureState.swift` parks a transaction only when `animation != nil || disablesAnimations`. MetalCreator's two occurrences flip `disablesAnimations` on the drag-write frames.
**Cost if wrong.** A replay that should have started an animation snaps: caught by the twin differential (`aSteadyDragCostsExactlyTheChangedPanelsMisses` compares scene) and verify mode. Unconditional normalisation is the larger bet and is not taken.

## AM-E - The environment half is measured first and named; no read-set tracking

**Question.** `key.ambient.environment` differs together with `disablesAnimations` on the same frames. Key the occurrence on only the fields it reads?
**Ruling.** Not built: environment reads are plain struct property reads (framework and `@Environment`), there is nothing to hook, and `EE-F` keeps whole-position ambient by design. The trace first names the differing field (`key.ambient.environment.<field>`, guard-owed rows). Then: a field that is a function of another keyed field leaves the comparison; a field an occurrence legitimately reads stays (a miss is correct); anything else is carried as C14-m with the named field as evidence, and the drag pin is stated for the `disablesAnimations` half.
**Evidence.** `EnvironmentFingerprint` is a struct of 27 fields plus `objects`/`custom`; `Environment.probe` is the only read hook and covers declared `@Environment` properties of `.equatable()` components only (`EE-A`).
**Cost if wrong.** The headline MetalCreator miss may survive on the environment half; the spec says so up front and the lane reports the field.

## AM-F - The trace path is cut at a `/` boundary with a `…/` prefix

**Question.** `suffix(120)` starts mid component (`ional(0)/positional(1)`). What reads better and still bounds the line?
**Ruling.** The longest run of whole trailing components such that `"…/" + run` fits in `length`; a fitting path is unchanged; an over-long last component prints `"…" + its last (length-1)` characters. `pathLength` keeps its meaning (a bound).
**Evidence.** The log's 120-character tails begin `ional(0)`, `sitional(0)`, `tional(0)`.
**Cost if wrong.** None to behaviour; the existing four `tail(of:)` expectations (`RetainedTraceTests` lines 143-146) are rewritten in the same commit.

## AM-G - The fire cause survives release as the writer's frame, else `release-inlined`

**Question.** `cause: ?` in release because the setter is inlined (`DM-E`). Is a key path available?
**Ruling.** No: `ObservationRegistrar` and `withObservationTracking`'s `onChange` carry none (probe `observation-fire-cause.swift`), and macOS 27's `Event.matches(_:)` only tests a candidate key path, cannot enumerate, and is `anyAppleOS 27.0` only. The rule becomes a pure function over the stack symbols: the `.setter` frame (debug); else the nearest non-machinery frame above `ObservationRegistrar`/`withObservationTracking`/the retained session (the inlined setter's *caller*), printed `via <function>`; `release-inlined` when there is none; `?` only where stack symbols carry no names (Windows). A release `-O` probe records the real frames first.
**Evidence.** `DM-E`; the interface of `Observation` in the macOS 27 SDK (`Event.kind`, `matches`, `cancel` only).
**Cost if wrong.** A trace word, never a decision: nothing reads the cause but the trace (autoclosure, off costs nothing).

## AM-H - Value-identical, no public API, no divergence

**Question.** Does either change move an observable?
**Ruling.** No: a replay is accepted only where the output equals a fresh frame (twin differentials, `METALUI_VERIFY_RETAINED=1`, the fourteen images 0 px). Labels 755-764 untouched; no inventory row; pins count work, never time.
**Evidence.** The retained-subtree stack (`SB-W`, `RK-N`) and `DM-H`.
**Cost if wrong.** A replay differing from a fresh frame is a trap in verify mode and a failing twin arm.

## AM-I - Two lanes on disjoint files; the shared file is split by function

**Question.** One lane or two, and where do they meet?
**Ruling.** Two. Lane 1 (C14-k): `RetainedPhase`, `retainedPrepaintPhase`, the decision's miss branch and `finishRetainedPaint`, `EquatableComponent.swift`, its fixture arms and tests. Lane 2 (C14-l): `RetainedTrace.swift`, `RetainedPrepaint.swift`'s key, `EnvironmentValues.swift`, the new `RetainedTransactionKey.swift`, the one-line region of `retainedKey(_:)`, its own fixture and tests, the probes. Both edit `RetainedSubtree.swift` in different functions; they merge by hunk in either order.
**Evidence.** Section 2 and 3 of the spec: no function is in both lists.
**Cost if wrong.** A hunk conflict in `RetainedSubtree.swift`, resolved by the orchestrator at the merge.
