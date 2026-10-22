# Retained single miss - decisions

Rulings for item C14-j. Spec: [`specs/2026-10-21-retained-single-miss-design.md`](specs/2026-10-21-retained-single-miss-design.md). Record: `../record/140-retained-single-miss.md`.
Branch `perf/retained-single-miss` from `195ff2c8`. Reserved divergence labels 695-704: none taken.

Prefix **`DM-`**, lettered. **Next unused: `DM-K`.** (Moves in the commit that appends a ruling.)

**Carried.** `SB-V`, `SB-X`, `SB-AA`, `RW-S`, `RK-C`, `RK-D`, `FS-N`, `MO-A`, `MO-F`, `IV-S`, `PA-J`.
No SwiftUI probe, no gpui comparison: no observable behaviour moves (`DM-H`).

## DM-A - Two lanes: the trace first, then the fix, because the fix is measured with the trace

**Question.** One lane or two, and in what order?
**Ruling.** Two, sequential in effect. Lane 1 owns the new `RetainedTrace.swift` and every trace line; lane 2 owns the decision, the observation predicate and the fixture. Both touch `RetainedSubtree.swift` in different functions (lane 1 only the call sites and `traceMiss`'s replacement; lane 2 `retainedPaintDecision`'s `valid` and `finishRetainedPaint`); lane 1 lands first so lane 2's step 0 reads the real second-miss reasons instead of assuming them.
**Evidence.** The log's empty lists are the trace's own gap; a fix chosen from code reading alone is a hypothesis (`DM-B`).
**Cost if wrong.** If lane 2's step 0 contradicts `DM-B`, the change in `DM-C` is dropped and the ruling superseded before code moves.

## DM-B - The double miss is the unobserved build and prepaint of a certain-miss frame

**Question.** Why does every changed occurrence miss on the frame after its change with no reason named?
**Ruling.** `needsObservation` is `record == nil || record.coverageComplete == false` (`SB-V`): with a complete record standing, the occurrence's build and prepaint run **unobserved** because the previous frame's sessions are assumed armed. When the occurrence changed (`serial` moved or `observedChange` is set) the paint decision is certain to miss (`valid` needs `contentSerial == serial && !observedChange`) and the record it then makes has `coverageComplete = build.observed && prepaintObserved = false`. The next frame observes, but `valid`'s `coverageComplete` conjunct fails: a second miss whose reasons `traceMiss` cannot name. The third frame hits. Changed work costs two paints.
**Evidence.** `fillet-trace.log`: 2768 misses, 1124 empty (`[]`), in pairs of consecutive frames over the same 16 occurrences (lines 2909-2947: frame A `["observed","serial"]`, `["observed","interior"]`...; frame A+1 `[]` x15 and `["versions"]` x1). Code: `EquatableComponent.buildGroup` (`let observed = entry.needsObservation`), `retainedPaintDecision` (`valid`), `finishRetainedPaint` (`record.coverageComplete = phase.build.observed && phase.prepaintObserved`). **Not yet run on a fixture**: lane 2's step 0 does (the fixture's expected figure is 2 misses per change today).
**Cost if wrong.** Small: a pin that expects 1 and measures 2 on an arm names which cause remains (`RW-S`, key-only), and that arm is carried by name (`DM-D`).

## DM-C - Observe the frame of a change; the trace and the observation predicate share one definition of "certain miss"

**Question.** How does the record made by a change frame become complete without making steady frames pay for a session?
**Ruling.** `needsObservation` gains `|| record.contentSerial != serial || observedChange`, evaluated at build and again at prepaint (the entry's record and flags are unchanged between the two; `finishRetainedPaint` clears `observedChange` only afterwards, `MO-F`). A certain-miss frame opens the build and prepaint windows; the occurrence misses anyway, so the sessions cost nothing the frame was not already paying (a changed occurrence runs its getter, build, prepaint and paint). A steady frame, or one that misses only on a key difference, is unchanged. Soundness is the old rule's: the record's coverage is true only if all three windows were open when its reads happened; the pin `aStaleSessionStillFiresAfterTheSameFrameRecord` is the proof it is not simply declared.
**Evidence.** `DM-B`; `RK-D`/`SB-V` for the window rules.
**Cost if wrong.** A record marked complete whose reads were not observed replays a stale scene: verify mode builds it twice and traps; a retention-off twin differential and the soundness pin catch it before merge.

## DM-D - Key-only misses are measured, not assumed; carried unless the evidence is clean

**Question.** A key difference (an origin, an interior) with an equal value also records with an unobserved build. Fix it?
**Ruling.** Measure on the `.moved` arm. The candidate (`DM-D2`) is to let the new record inherit the build half of coverage from the standing record when `old.contentSerial == entry.serial && !observedChange` (the build recursion precedes layout, so its reads do not depend on this occurrence's rects; the standing build session was not retired, no `run` happened) and to observe the prepaint when it runs. It lands only if the whole suite is green under `METALUI_VERIFY_RETAINED=1` and the twin differential holds on the `.moved` arm; otherwise it is carried to C14-k and the arm's pin states 2 misses with the ruling id. The `ReplayKey` difference printer is complete (a Mirror-count guard) either way.
**Evidence.** In the log the key-only lists are rare (`["interior"]` alone does not appear in the top rows); the trace of lane 1 will say how rare on the fixture.
**Cost if wrong.** Landing it unsound is the verify-mode trap; carrying it costs one extra paint per moved occurrence, today's cost.

## DM-E - A key path is not available from `withObservationTracking`; the trace names the writer's symbol

**Question.** The trace must say which property fired `observed`.
**Ruling.** `onChange` is `@Sendable () -> Void` with no key path and no object; the registrar's access list is not public API. Probe `docs/probes/observation-fire-cause.swift` (positive control: a write fires `onChange`; separating arm: the closure's arguments and the observed model give no property name; third arm: the writer's frames contain `Model.radius.setter`) fixes this before lane 1 relies on it. Behind `RetainedTrace.active`, the fire records the demangled writer frames (`<Type>.<property>.setter`, `withMutation(of:keyPath:_:)`), stored on the entry, printed after `observed`; a release build with the setter inlined may show only the type, which is stated in the line (`cause: ?`). No decision reads it; no cost when off. If the probe finds a better public hook the ruling is superseded by number before code.
**Evidence.** Observation's public surface (`withObservationTracking(_:onChange:)`); none of the repository's sessions needs more (`RetainedHandle`, `ContentMemoHandle`).
**Cost if wrong.** A cause string that is blank on some build; the pin runs in debug on Darwin and Linux only.

## DM-F - The trace says paint or prepaint, prints 120 characters of path, and is a sink

**Question.** Format and plumbing.
**Ruling.** Every line is `retained <paint|prepaint> <kind> <path tail> <details>`; path tail 120 by default, `METALUI_TRACE_RETAINED_PATH=<n>` (read once) overrides; output goes through `RetainedTrace.emit`, whose destination is `print` unless a package `sink` is installed (tests install it and restore it). A miss line never has an empty list: an unclassified miss prints `unclassified` and counts in `RetainedTrace.unclassified`, which the tests assert zero. The strings are built inside `if RetainedTrace.active`, so off means no allocation (pinned differentially, `PA-J`, Darwin).
**Evidence.** The log's two ambiguities: 60 characters of a positional path do not identify an occurrence (`l(0)/positional(0)/...`), and a decision's phase was not on the line.
**Cost if wrong.** A tool grepping `retained miss` finds `retained paint miss`; none in the repository does (checked: only record text mentions the print).

## DM-G - The `RW-S` second miss is attempted by adoption, behind the verify oracle

**Question.** `RW-S` ("a record made then gains its ledger one counted miss later") is a second miss by design. Remove it?
**Ruling.** Try: a paint hit whose old record has no ledger and whose frame ran a prepaint that made one adopts the ledger when each read of it is in the record's versions or unchanged since the record's own frame (the `FS-N` rule extended), and counts a hit. If a case fails verify mode or the twin differential, `RW-S` stands for that case and its amendment records the measured reason; the negative control keeps the miss for a ledger the record cannot vouch for. `RW-S` is amended by ruling with what was measured either way.
**Evidence.** Record §121 §RW-S (the creating frame is a write, its prepaint refused, the record holds `prepaint == nil`); `refreshLedger` (`FS-N`) already adopts a fresh ledger under a subset rule.
**Cost if wrong.** Adopting a ledger the record's paint did not depend on is harmless; adopting one it did and was not versioned replays a stale scene: verify mode.

## DM-H - No SwiftUI probe and no gpui comparison

**Question.** The task asks for probes of every SwiftUI-facing claim.
**Ruling.** There is none: retention is invisible to a program (scene, hitboxes and accessibility equal a retention-off twin, pinned), SwiftUI has no `.equatable()` retained paint, and gpui's `cx.notify`/`View` caching has no per-occurrence observation windows to compare. The only probe is `DM-E`'s, about Swift's Observation, not SwiftUI.
**Cost if wrong.** None observable; a reviewer who wants a probe finds the oracle is the twin.

## DM-I - Pins that move are moved by ruling, with numbers

**Question.** Existing miss counts (`theFilletDragReasonsAreProfiled`'s `<= frames`, the bracket `.panels` literals of `RW-S`, the zoom and graft pins) may drop.
**Ruling.** A pin reading `retainedMisses` or `retainedHits` that moves because a changed occurrence misses once is rewritten to the new exact figure in the lane's commit, with the old and new numbers in the commit message and record §140; none is loosened to an inequality. Element-work counters of unchanged paths are untouched.
**Evidence.** `RW-S` §121: the same discipline moved the panels arm.
**Cost if wrong.** A literal that was a floor now equals it: a regression of one miss is still red.

## DM-J - The certain-miss predicate is read after the value decision, not at the top of the build

**Question.** `DM-C` reads `record.contentSerial != serial` at build, but on a value change the serial moves only when the getter re-runs, after `needsObservation` is first read; the predicate would be false exactly on the frame it exists for.
**Ruling.** The predicate takes the memo's own `==` decision as an input: `certainMiss = observedChange || valueDiffers || record.contentSerial != serial`, where `valueDiffers` is the result of the comparison `EquatableComponent.buildGroup` already makes before deciding to run the getter (no second `==`). The build window opens after that decision and before the getter's children are built; the prepaint window re-reads the same stored decision (never recomputes `==`, which may be non-pure). Lane 2 step 0 prints the order of `needsObservation`, the `==` and the serial bump on the fixture before code moves. A `.value` arm that still measures 2 after the change means this ordering was wrong, not that `DM-B` is.
**Cost if wrong.** The pin `aChangedOccurrenceCostsOneMissAndTheNextFrameHits` stays red on `.value`; no unsound state, since a window opened late leaves coverage false.
