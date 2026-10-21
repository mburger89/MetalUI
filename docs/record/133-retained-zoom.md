# 133 - Retained zoom (C14-i), fillet-drag profile and `@FocusState` under `.equatable()`

Branch `perf/retained-zoom` from `1bdead8d`. Rulings `RZ-` in `docs/superpowers/2026-10-21-retained-zoom-decisions.md`; spec `docs/superpowers/specs/2026-10-21-retained-zoom-design.md`.
Lane 1 (zoom) has its own section, written by its owner. **This section is lane 2.**

## Lane 2 - fillet-drag profile and `@FocusState` (RZ-H, RZ-I, RZ-S, RZ-T)

### (a) Fillet drag: no framework cause, no source change

`FilletDragFixture` (six `.equatable()` panels of text, rect, stroked path and six rows; a slider; a readout `Text` outside every panel that changes every frame; scale 2, an 8-step drag, 9 frames) in five arms.
Per frame, retained against retention off (counts, debug build):

| arm | requests | getters | misses | grafts | redo / refusals |
|---|---|---|---|---|---|
| sliderOutside | 40 (+189 skipped) of 229 | 0.9 | 0.9 | 5.1 | 0 / none |
| sliderInside (pressed panel) | 44 of 229 | 0.9 | 1.0 | 5.0 | 0 / none |
| observedRead | 40 of 229 | 0.9 | 0.9 | 5.1 | 0 / none |
| sliderEverywhereObjects (one `@Observable` per panel) | 44 of 239 | 0.9 | 1.0 | 5.0 | 0 / none |
| sliderEverywhere (one array property) | **217 of 239** | 0.9 | **5.4** | 0.6 | 0 / none |

The reasons tables (`retainedIneligibleReasons`, `retainedTranslationRefusedReasons`, `contentRefusals`) are empty in every arm; the trace names the one dragged panel's miss (`serial`, `interior`, `versions`; with a slider inside it also `observed`, `pointer/press/focus`: by design). The only arm that costs what MetalCreator's 888 suggests is a
shared observable collection: a write to one element is an observed change of every panel whose binding read the array (`observed` on each, `RZ-S`). **By design**, `.equatable()` observation is per property; the lead for MetalCreator is to give each node's parameters its own object. **MetalCreator's own 888 is not reproduced here.** Pins F1: `theFilletDragReasonsAreProfiled` (5 arms) and
`theFilletDragFrameEqualsAnUnretainedOne` (5 arms), characterizations (nothing moved, so none can be red at the merge base).

### (b) `@FocusState` is memoized by its slot's version (C14-c2)

`StateBinder` puts a `@FocusState` ordinal among the memo's slots; `memoShape` no longer refuses. The `$state<n>` slot is written with a version bump by `reconcile` on every focus change the window applies, which is the changed reading. **The planned re-note on a memo skip is not built** (`RZ-T`): `enterComponent` binds (and notes the focus state) before the memo decides, and a graft's journal arm covers a **nested** component's state.
Red at `f2ba9def` (the commit before): F2, F3, F4 (evaluations), F6, F7 reddened on `contentRefusals` and every-frame evaluation; F5 was green (refused components are trivially right). Pins `FocusStateMemoTests`: F2 `aFocusStateComponentIsSkippedWhileFocusIsUnchanged`, F3 `aFocusMoveReEvaluatesExactlyTheReadersOfTheMovedState`, F4 `aPendingFocusWriteAppliesToAComponentThatWasSkipped`,
F5 `aSkippedFocusStateIsStillReconciled`, F6 `aGraftedFocusStateComponentReconciles`, F6b `aPendingWriteWhileGraftedIsApplied`, F7 `aFocusReaderUnderRetentionRepaintsWhenFocusLeaves`; the replaced `aFocusStateComponentStaysRefused` is gone. Each compares a retaining window with a twin of the same tree (memo and retention off) on scene, accessibility tree, hitboxes, tab order and bounds.

**Mutations (filtered to the set named, each restored from git, `git status` clean after):**
- M1 `if false, let stateOrdinals = memoShape` (everything refused): F2, F3, F4, F6, F7 red.
- M2 focus ordinals left out of the entry's slots: F3, F4, F5, F6, F7 red.
- M3 `table.noteFocusState` removed from `FocusState.bind`: F3, F5, F6 red (F4 stays green: a click's own frame binds).
- M4 the `.focusState` arm of `RetainedGraft`'s journal replay removed: F6b red (it needs a nested component: with the state on the grafted occurrence itself `enterComponent` binds first, and the mutation is invisible, found by measurement and fixed in the pin).
- M5 `FDPanel.==` ignoring its value: `theFilletDragReasonsAreProfiled` red (the twin carries the same `==`, so the equality pin cannot see it).
- M6 `Entry.observedChange` forced `false`: `theFilletDragReasonsAreProfiled` red (the array arm's misses vanish).

**Divergence 346** narrowed in place (the `@FocusState` clause removed, pins renamed). No label taken, no public API, no census change (`FrameWork.contentRefusals`'s doc comment amended).

### Verification (lane 2 tree, debug)

Native unfiltered run on a locked screen: **4134 tests in 5 suites, exactly the five `AppKitPresentationTests` sheet issues of `CI-AF`, nothing else**, `FR-J no-argument frame: succeeded=true`, 0 `error:`. With `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1` and `AppKitPresentationTests` skipped: 4125 passed, 0 issues.
Test arithmetic: lane 1's tree + 6 focus tests (F2-F7) + F6b - the replaced W8 + 10 fillet cases.
