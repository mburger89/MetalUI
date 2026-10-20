# Retained subtrees over read-only state — design

Item C14b-3 of the gpui-gap priority list (user request 2026-10-02; not a plan task), carried by record §109 §11 and §110 §9.
Rulings: [`../2026-10-19-retained-withstate-decisions.md`](../2026-10-19-retained-withstate-decisions.md) (`RW-`).
Record: `../../record/121-retained-withstate.md` (Record phase). Branch `perf/retained-withstate` from `f557d339`.
Divergence labels 515–524 reserved: **none taken**. No public declaration but one `MetalUITesting` field (`RW-M`, `RW-N`).

## 1 Measurement (design phase, `f557d339`, 2026-10-19, headless, counts)

Scenario "orbit with panel": the `.panels` arm of `BracketFixture` (1440 x 900 at scale 2; top bar, graph panel with a
`TextField` and a `ScrollView { List }`, glass inspector with Sliders/Toggle, a full-window `.onDemand` `GPUSurface` under all of it),
nothing in the panels changing; each frame is `viewport.token += 1; setNeedsRedraw(); tick()` (what an orbit does), after three
warm frames, retention, prepaint replay and the graft on. Frame 3 of 6:

| counter | value |
|---|---|
| element requests / skipped by the graft | 115 / 683 (sum 798, the retention-off count) |
| element prepaints / paints | 117 / 110 |
| retained hits / misses / ineligible | 34 / 0 / 1 |
| prepaint ineligible / graft ineligible / redos | 2 / 1 / 0 |

Why (`METALUI_TRACE_RETAINED=1`, plus a throw-away call-stack print in `StateTable.withState`, not kept): **three occurrences**
carry all the remaining work.

* **Graph panel** — ineligible at paint, prepaint and graft, reason `stateWrite`: the first untainted `withState` in its window is
  `TextField.paintText`'s read (`PaintPass.withState` -> `TextField.paintText` -> `paintFieldChrome`, 8 of 9 prints), then the
  scroller's and the list's.
* **Top bar** — prepaint-ineligible, reason `presentationAnchor`: its `Picker` and `Menu` call `Frame.recordPresentationAnchor`
  every frame, even closed.
* **Inspector** — ineligible only in the warm-up frames (`animatedColor` first sighting writes its `$anim-color` baseline); steady
  state it hits.

So the 34 hits are the nodes, wires and inspector; the cost is the three panels, 115 requests, not the 798 of a full rebuild.
MetalCreator's measured 20.56 ms window CPU per frame (`e85cb07a`) is the same shape: panels that cannot be retained. A
prediction, not a pin: after the item the orbit frame's ineligible, prepaint-ineligible and graft-ineligible counters read 0 and
requests fall to the few unretained leaves (the window component itself, the `GPUSurface`, the `ZStack`s above the occurrences).
The lane re-takes the literals; the numbers above are the **before** pins.

## 2 Inventory

**`withState` call sites, 34** (`grep -rn "withState(" Sources/MetalUI`, plus the pass wrappers `Passes.swift` 905/915/925):

| class | sites | ruling |
|---|---|---|
| per-frame framework bookkeeping, converted | `ScrollView.swift:249`, `ProposalScrollView.swift:62`, `ScrollChrome.swift:108/135/172`, `List.swift:663/908`, `TextField.swift:279/285/301/350`, `TextEditor.swift:304/310/322/372` (15) | `RW-C`, `RW-H`..`RW-J` |
| input-time or test-hook writes, plain | `Window.swift:526/2274/2320/3203/3208`, `List.swift:1146/1183/1261`, `FocusState.swift:124`, `Frame.swift:311/319`, `TestingHooks.swift:116` (12) | `RW-G` |
| retention slots (focus, `$ax`) | `Frame.swift:1616/2166/3972` (3) | own channels, unchanged |
| `$anim` baselines | `AnimatedStyle.swift:375/519`, `AnimatedColor.swift:580/588` (4) | `RK-F`'s `.liveState`, unchanged |

**`peek` reads that decide layout or paint** (not versioned today): `List.swift:460/1113/1225` (`ListOrigin`), the animation
baselines (`AnimatedColor`, `AnimatedStyle`), `FocusState.swift:74/119/130`, `State.swift:107` (`@State`, covered by `markJournal`),
`Frame.swift:2231/2347` (`$ax`, focus slot).

**Taints this item touches** (`taint(` sites): `stateWrite` (`StateTable.swift` 722/723/730/838-840: the item's), `presentationAnchor`
(`PrepaintAudit.anchors`), and, unchanged, `surface` (`Frame.swift:2964`), `portal` (`:935`), `requestAnotherFrame` (`:86`),
`activeAnimation` (`:369`), `interpolation`, `geometryChange`, `modifierKeys`, `capturingScope`.

**Replay channels** (what a hit must reproduce): paint record = scene ops + `marks` + animation `touches`
(`RetainedSubtree.swift`); prepaint ledger = hitboxes, AX, focus, press-only, context menus, element bounds, tallies
(`RetainedPrepaint.swift`); graft = layout segment + `BuildJournal` events (`RetainedGraft.swift`).

## 3 Mechanism

**Three entry points on `StateTable`** (`RW-C`):

```swift
func readState<S>(_ id: GlobalElementID, initial: @autoclosure () -> S) -> S
func withState<S>(_ id: GlobalElementID, initial: @autoclosure () -> S,
                  unchanged: (S, S) -> Bool, _ body: (inout S) -> Void)
func withState<S>(_ id: GlobalElementID, initial: @autoclosure () -> S, _ body: (inout S) -> Void)   // as today
```

* `readState`: entry present and of type `S` -> return it, `marked.insert(id)`, set `isLive`, append `id` to `stateReads` and to
  the open windows' live lists; **no version, no `writeCount`, no taint**. Absent -> exactly today's `withState` (creation).
* compared `withState`: copy the value out, run `body`, if `unchanged(old, new)` then as `readState`, else exactly today's write
  (version bump, `writeCount`, taints). Types differ or entry absent -> a write.
* `peek`: appends to `stateReads` when `retainsSubtrees` and a window is open (`journal.isRecording || retainLog != nil ||
  prepaintLog != nil`); otherwise unchanged cost.
* `touchLive(id)`: `marked.insert`, `isLive = true` via `storage.index(forKey:)` (`PA-` precedent), no journal event; the replay
  of a ledger's `liveStates`.

**Records.** `markJournal` is sliced by `phase.build.journal` at record time (`RetainedSubtree.swift:600`); `stateReads` is
sliced identically and appended to `record.versions` (deduplicated). `PrepaintLedger` gains `reads: [(id, UInt64)]`,
`liveStates: [id]`, `anchors: [(id, Bounds<Pixels>)]`; `PrepaintLog` gains the same three arrays with `current` marks;
`GraftRecord` gains `reads` from `BuildJournal.Event.stateRead(id, version)` (new) and replays `.liveState`. A hit adds one
loop over `reads` (`retainedVersionsUnchanged`, `RetainedGraft.swift:301`, `RetainedPrepaint.swift:165`).

**Why both halves (`RW-B`).** Take `ScrollChrome.resolvedOffset` today: every frame `withState` rewrites `ScrollState` (bump,
taint). Make it compared and a settled scroller stops bumping. Now a wheel event: `Window.applyScroll` writes (bump) and dirties
the window; with no read set the record's versions list does not hold the `ScrollState` id (it is not an `@State` slot), the
hit validates, the replay paints the old offset. With the read set the version differs: miss, a fresh build, a fresh record. The
mirror: with the read set but without compared writes the entry bumps every frame, so a record made in frame N never validates
in N+1. The orbit pins in §5 test 1 and the stale-replay test 4 are the separating arms.

**Anchors.** `recordPresentationAnchor` appends to `prepaintLog.anchors` when a recorder is open; the ledger replays them through
the same function (window-space, offset already added). `PrepaintAudit.anchors` is counted by the replay too, so a recorder
enclosing a replayed child sees the movement it expects (`RK-E`'s audit discipline).

**Verify mode** (`RW-O`): fresh run's read ids subset of the record's reads (`unrecordedRead`), compared writes that wrote while
the replay skipped (`writeMissed`).

**Counters** (`FrameWork`): `retainedIneligibleReasons: [String: Int]` (public), and internal-read-through counters
`retainedReadChecks` (version comparisons made at hits) and `retainedReadMisses` (hits refused by a read version). `RetainedCounters`
gets the dictionary and `noteIneligible(kind, reason:)`.

**Lane A's realisation** (frame-long read journal, creating reads, one versions list, replays re-noting reads): `RW-R`.

## 4 What stays ineligible (by name, countable)

A focused field/list/editor (`SB-X`); a scroll, drag or wheel in flight (`versions` miss, then fade: `requestAnotherFrame`); a
`scrollTo` or anchor adjustment (`scrollRequest`); an open popover (`popover`), alert, dialog, `presentation*`; a `GPUSurface`
(`surface`, carried `RW-L`), `.continuous` always; first-sighting frames (`RW-F`); every pre-existing reason.

## 5 Tests (each: red before, the mutation that must redden it; the unfiltered suite is run per mutation)

Tests live in `Tests/MetalUITestingTests/RetainedWithState*.swift` (a new orbit helper `bracketOrbitFrames(arm:frames:)` in
`BracketFixture.swift`'s neighbour: a viewport token bump per frame).

1. **`theOrbitWithPanelIsCountedAfterReadOnlyState`** (arms `.value`, `.panels`): the orbit frame's literals (requests,
   skipped, prepaints, paints, hits, the three ineligible counters, `retainedIneligibleReasons` empty) and the **before** literals
   of §1 asserted against a window with `testingRetainedReadState = false` (package switch restoring the plain `withState`).
   *Red before:* ineligible reads 1/2/1 with reason `stateWrite`. *Mutation:* `readState` made to bump -> reddens; the switch
   removed -> the before arm reddens.
2. **`readStateAndAnUnchangedWriteDoNotBumpTheVersion`** (`StateTable` unit): read, equal write, changed write, absent creation,
   type clobber. *Mutation:* always bump; never bump.
3. **`aChangedCompareWriteTaintsEveryOpenWindow`**: taints paint, prepaint and graft windows with `stateWrite`. *Mutation:* skip
   one funnel (three arms, one each).
4. **`aWheelInsideARetainedPanelMissesOnTheScrollStateVersionAndMatchesAFreshWindow`**: wheel the list, compare scene, hitboxes
   and AX with a retention-off twin each frame; the frame after the scroll is a counted miss (`retainedReadMisses == 1`), the
   frame after the fade is a hit again. *Mutation:* `readState`'s read not appended to `stateReads` -> stale scene.
5. **`aListWindowIsAFunctionOfTheStateItReads`**: scroll, data change, resize; built row range and rows' `@State` ageing equal a
   fresh window's (TB-AH), with the graft on. *Mutation:* `peek`'s read dropped (`List.swift:460`'s) -> window stuck.
6. **`anUnfocusedFieldKeepsItsStateAcrossThreeHundredReplays`**: a field with a caret set, `scrollX` set, 300 replayed frames,
   entry still present, value equal. *Mutations (three):* each liveness channel's replay removed -> entry reaped.
7. **`aFocusedFieldInsideARetainedPanelMissesAndTypingWorks`**: focus, type, backspace, IME `setMarkedText`/commit, blur; AX
   value read each step equals the twin; counters: miss while focused, hit after blur. *Mutation:* `SB-X`'s focused test off.
8. **`aSelectionChangeInsideARetainedListMisses`**: click row, shift-click, binding written from code. *Mutation:* ledger's
   key handler captured stale `data`.
9. **`everyIneligibleOccurrenceIsCountedByItsReason`**: open popover (`popover`), alert (`presentation`), `GPUSurface`
   (`surface`), `.continuous` (`activeAnimation`), a plain `withState` write (`stateWrite`), focus (`SB-X` is a miss: asserted
   as such). *Mutation:* funnel records `"?"`.
10. **`aPickerOpensFromAReplayedAnchorWhereAFreshWindowOpensIt`**: replay frames, resize window, open the popover, compare
    frame and anchors with the twin. *Mutation:* ledger drops anchors.
11. **`aScriptedSessionOnThePanelsArmEqualsAFreshWindowEveryFrame`** (differential over orbit, wheel, click, type, slider drag,
    toggle, resize): scene, hitboxes, AX, focus order, state entries equal frame by frame. Instrument for every mutation above.
12. **Verify-mode runs** (not a test): full suite under `METALUI_VERIFY_RETAINED=1` and `METALUI_VERIFY_LAYOUT_MEMO=1`, no trap;
    one mutation: a call site converted wrongly (a compared write whose closure always says equal) must trap `unrecordedRead` or
    `writeMissed`, naming it.
13. **Typecheck guard `RW.1`** (`typecheckFile`, plain import): `readState`, `touchLive`, `stateReads`, `unchanged:` unreachable
    outside the module. *Mutated red once* (made `package`).
14. **`everyStateWriteSiteIsClassified`** (source scan, `Sources/MetalUI/*.swift`): every `withState(` call is spelled plain,
    `unchanged:` or `readState`, count per file equals the §2 table. *Mutation:* add a plain site.
15. **`aRetainedReadSetHoldsNoStrongReference`** (`MemoryReleaseTests`' shape, `IV-R`): window closed, panel models released.
16. Existing pins that **move by ruling** (re-taken, literals edited with `RW-` named in the comment): `.panels` arm of
    `RetainedPrepaintTests` (`prepaintIneligible` 1), `RetainedGraftTests` `afterGraftFrames` (`graftIneligible` 1, requests 167),
    `RetainedSubtreesBaselineTests` (retention-off arm: unmoved), the demo's counters. The fourteen images stay 0 px.

## 6 Lanes (sequential; re-cut by `RW-P` on disjoint files; lane B starts from lane A's commit)

* **Lane A, instruments and core mechanism** — `Sources/MetalUITesting/FrameWork.swift`, `TestApp.swift`, `ContentMemo.swift`
  (`RetainedCounters`), the three increment sites via `noteIneligible`, `StateTable.swift`, `Passes.swift`, the read-set/liveness
  fields of `RetainedSubtree.swift`/`RetainedPrepaint.swift`/`RetainedGraft.swift` (no call site converted yet), `bracketOrbitFrames`
  in `BracketFixture.swift`'s neighbour, tests 1 (before arm), 2, 3, 9, 13, 15, the inventory row, the Prof scenario
  (`docs/probes/retained-withstate/`). Commit with before pins green, after pins red.
* **Lane B, conversions and anchors** — `ScrollChrome`, `ScrollView`, `ProposalScrollView`, `List`, `TextField`, `TextEditor`,
  `Frame.swift` (`recordPresentationAnchor`, `PrepaintAudit`), the ledger's anchor field, `RW-O` verify extension, tests 4–8, 10, 11, 14,
  the demo strip, after pins, record.

Not a lane: Backends/SDL is untouched (no platform requirement, no shader); the Linux image runs the root portable tests once at
the end. `swift package clean` after lane A (a stored property on a public type) and lane B (`ListOrigin`/`TextEditState` unchanged,
but `PrepaintLedger` fields).

## 7 Demo and measurement

`METALUI_RETAINED_DEMO=1` gains a **panel strip** (a `TextField`, a `ScrollView { List }`, a `Picker`, in its own function passed
to the generic composer; added to `DemoStackBudgetTests` / `everyProductionTreeBuildsOnAOneMegabyteThread`) beside the existing
counts strip, which now also shows the reasons. Expectation: dragging a node leaves the strip's occurrence a hit; scrolling its
list or typing in its field shows a counted miss and a visible, correct result; the strip reads 0 ineligible in steady state.
Release ms/frame on orbit-with-panel is **dated, never pinned**: `Prof` copied from `/private/tmp/claude-501/profiling/Prof`, pointed
at the worktree, scenario `bracket-orbit-panel`, base `f557d339` versus the lane head, three alternating runs each, load average
noted.

## 8 Human checks (group RW, **not run — an agent cannot**)

RW1 scroll a retained list in a real window (momentum, indicator fade) and see the same pixels as with retention off
(`METALUI_RETAINED_DEMO` switch); RW2 type, select and IME-compose in a retained field after orbiting; RW3 open a `Picker` from a
retained top bar after resizing the window; RW4 a long idle (minutes) in a retained field keeps its caret and scroll; RW5 MetalCreator
orbit with panels (the owner runs it; no agent touches MetalCreator).

## 9 Carried (named, with reason and owner)

| item | reason | owner |
|---|---|---|
| `GPUSurface` inside a subtree (`onDemand`, unchanged `value:`) | designed in `RW-L`; no orbit win (sibling surface); renderer-side lifetime and SDL image | C14b-4 |
| open popover, alert, dialog under a retained subtree | per-frame presentation root, flips against the live window (`SB-J`, `RW-K`) | C14b-4 |
| equal-value skip for input-time writes | spurious misses are cheap (`RW-G`) | none until measured |
| layout or scroll translation of a retained subtree | float association (`SB-H`) | C14b-4 |
| custom environment keys, finer scopes (`List` row, `ForEach` element) | no equality | C14-c follow-up, C14-d |
| `drawText` | `GT-F` | unchanged |
