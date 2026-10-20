# 127 — Warm and cold frame gaps (C14-e: comparable `textMeasurer`, redo counters, the second-frame layout spike, the cold-frame profile)

Branch `perf/warm-settle` from `679f5d7d`. Not a plan task: item C14-e of the gpui-gap list (user request 2026-10-02), from MetalCreator's counter
bisect of 2026-10-20. Spec `docs/superpowers/specs/2026-10-20-warm-settle-design.md`; rulings `CF-A`…`CF-K` in
`docs/superpowers/2026-10-20-warm-settle-decisions.md` (next unused `CF-L`). Divergence labels 565–574 reserved: none taken (346 is amended). Part (c) of the
original item (`onGeometryChange` replay inside a retained subtree, `RK-E`) is excluded and runs after C14-d. No public declaration. §1–§2 are lane 1 ((a), (d));
§3–§6 are lane 2 ((e), (b)).

## §1 (a) `@Environment(\.textMeasurer)` is a comparable reading (`CF-A`, `CF-B`, `CF-I`)

`EnvironmentReading.of` gains a first arm: a `TextMeasurer` reads as `.value(TextMeasurerReading)`, an internal `Equatable` struct of the **text system instance**
(`ObjectIdentifier(box.system)`, not the box: `Frame.init` allocates a fresh `TextSystemBox` every frame, so box identity would refuse and evaluate every frame) and the two
`ResolvedTextStyle`s `resolveTextStyle` gives a default request and a `.defaultFont` request in the measurer's environment (a font, weight, italic, `controlSize` or
foreground change above the reader must re-evaluate it). An `.equatable()` component reading it is skipped while both are equal; before, it was refused every frame
(divergence 346, narrowed again: `\.textMeasurer` leaves the uncomparable list). Pins `TextMeasurerReadingTests` (unit, T3 per field, T3b a field the measurer never
resolves, T4 system against box) and `TextMeasurerEpochTests` (window, T1 skip, T2 font change, T5 retained replay); red at `679f5d7d`, recorded in lane 1's commit `8586ba14`.

## §2 (d) A redo frame reports the abandoned attempt's content evaluations (`CF-C`, `CF-D`)

A redo (`RK-D`: abandoned after paint, rebuilt once with every replay off) restarted every counter, and the redo **skips** the content getter the attempt evaluated (the
entry holds the result), so MetalCreator read `contentEvaluations == 0` on the frame whose pan began. `noteRedo` keeps `evaluations` across `resetBuildCounters()`
(`ContentMemoStore.carriedEvaluations`), added back at the redo's `endFrame` and cleared there. Every other counter is the redo's own (the abandoned attempt's layout and
element work stays unreported, `CF-D`). Pins `RedoCounterTests` R1–R4 (`8586ba14`).

## §3 (e) The second-frame layout spike: reproduced, cause found, fixed (`CF-E`, `CF-J`)

**Reproduction** (step 0 of `CF-E`). MetalCreator at `17a19dd` copied to the scratchpad (read-only source, its `Package.swift` pointed at this worktree through a symlink named
`MetalUI`), a probe printing every `FrameWork` field of seven `redraw()`s after `resetFrameWork()`: frame 0 `layoutMeasureCalls` 2, `retainedMisses` 3, `retainedHits` 7,
`layoutSubtreeHits` 5; **frame 1 80 (220 memo misses, `layoutSubtreeHits` 1, `retainedHits` 2)**; frames 2–6 2, identical. Then in MetalUITesting only: the bracket fixture's
`.panels` arm (`.equatable()` panels over a `List`, a canvas and text), a persistent `TestWindow(recordsLayout: false)`: with no frame before the reset the measure calls read
52, **135**, 52…; with one frame before it **135**, 52…; with two or more 52 throughout; the `.value` arm never spikes. The designer-step fixture of `CF-E` (two `.equatable()`
components, two `onGeometryChange`, a `ScrollView`, text, two unkeyed leaves) had not spiked: the spike needs a retained occurrence whose layout the placement memo restored.

**Cause.** The frame that makes an occurrence's retained records also has its layout restored by the subtree placement memo (`SB-AD`, 11 `layoutSubtreeHits`). A restore
places nothing and so looks nothing up: the measurement entries below it (keyed `(signature, proposal)`) were in neither generation of `LayoutMemo` one frame later. The next
frame is the first that grafts the occurrence (`RK-B`; its nodes carry no placement mark), so it places the subtree for itself, misses 249 entries and measures 83 leaves
more. Suspects ruled out by the counters: RW-S (`retainedMisses` is 0 on the spike frame), the settle build (`builds` is 1), the unkeyed leaves (their 2 calls are in every
frame). `RetainedSubtreeWindowTests` had recorded the effect as expected ("135 against 52 on the press frame, `SB-AD`"): it was a documented cost, now removed.

**Fix** (`LayoutMemo.swift`, `LayoutTree.swift`, `NativeLayoutRun.swift`; `MetalUILayout` only, `package`, value-identical). A stored placement carries a `Footprint`: the
`MeasureKey`s a recording looked up or stored below its root (a run-cache hit included, so a measurement made in the measure pass is named too) and the `PlacementKey`s of the
marked roots inside it. A restore calls `LayoutMemo.touch(_:)`, which moves each footprint key still in the previous generation into the current one, exactly as a lookup
would, adding nothing and counting nothing. Recordings nest by `footprintDepth` on the run; the log is deduplicated once, at the record, which only a miss frame pays.
**Not covered:** the root placement (`IV-E` (P), `placeFromMemo`) has the same shape, but its footprint is the whole run and would put a log append into every lookup of every
frame for a miss nobody has measured (`layoutMemoRootHits` is 0 in MetalCreator's counters); a named residue.

**Result.** Bracket `.panels`: 52, 52, 52… from the frame after the records exist (`warm[n] == warm[n+1]` over the whole `FrameWork`, zero raster, atlas and texture work),
with the records made inside the measured window frame 0 alone differing (it counts its misses and ledger snapshots, legitimately). MetalCreator's
`unchangedFramesAfterSettlingDoExactlyTheSameWork` can compare from index 1 and drop the settle skip (hand-off; its frame 0 is the record frame).

## §4 Red first and the pins

Commit `ad269e91`, against `679f5d7d` plus lane 1: `aRestoredSubtreeKeepsItsMeasurementsAlive` (F1) misses 10 against the control's 4 (9 measure calls against 3); `aRestoredSubtreeKeepsAnInnerPlacementAlive` (F2)
`memoSubtreeHits` 0, misses 16, measures 12; `aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst` (W1) frames 1–6 differ from frame 0 (with `warm: 1` frame 0 reads 135 measures
against 52); `theFrameAfterTheRecordsAreMadeIsAlreadySettled` (W2) frame 1 differs; `aTouchAddsNoEntryAndCountsNoLookup` (F3) is a green control by design. All five green after
`9db8e7be`. One existing pin moved by design (`CF-J`): `theBracketNodeDragReplaysEveryUnchangedSubtree` frame 0 reads 52 in every arm, not 135 for the arms that retain nodes
(re-baselined, comment names the cause).

## §5 Suite and verification

- Native, unfiltered (screen locked): **4030 tests in 5 suites**; read first with 8 issues: the five `AppKitPresentationTests` sheet issues of `CI-AF` (locked screen) and the three
  `theBracketNodeDragReplaysEveryUnchangedSubtree` arms (the re-baseline above); after it only the five remain. `FR-J no-argument frame: succeeded=true`. 4030 = 4015 + lane 1's 10
  + F1, F2, F3, W1, W2.
- `METALUI_VERIFY_RETAINED=1 METALUI_VERIFY_LAYOUT_MEMO=1`, `--skip AppKitPresentationTests`: **4021 passed**, no trap (a touch changes only what lives, never a value).
- Default build system `swift build --build-tests`: 0 `warning:`. Inventory and undocumented scripts print nothing (no public declaration).
- Fourteen images against `679f5d7d`: **0 px, scene identical in all fourteen** (`docs/probes/demo-pixels/compare.sh`, controls as recorded).
- Linux image `metalui-portable` (OrbStack, volume `metalui-warm-settle-build`): `MetalUITestingTests` 382, `MetalUILayoutTests` 229, `MetalUICoreTests` 128 and the cross-platform 22 passed
  (the warm pins use `setNeedsRedraw()` + `tick()`, no observation hop, `IV-Q`). `Backends/SDL` untouched.

## §6 Mutations

Committed tree, each restored from a copy, `git status --short` clean after each. M1 (the `memo.touch` removed from `subtreePlacement`), full unfiltered with `AppKitPresentationTests`
skipped: reddened exactly `aRestoredSubtreeKeepsItsMeasurementsAlive`, `aRestoredSubtreeKeepsAnInnerPlacementAlive`, `theBracketNodeDragReplaysEveryUnchangedSubtree` (3 arms),
`aSecondUnchangedFrameDoesExactlyTheWorkOfTheFirst`, `theFrameAfterTheRecordsAreMadeIsAlreadySettled` (18 issues), nothing else. M2 (the inner placement key not appended to the enclosing
footprint) and M3 (the run-cache-hit logging removed), filtered to 101 layout, retained, placement and bracket tests: M2 reddened `aRestoredSubtreeKeepsAnInnerPlacementAlive` (the hit arm),
M3 reddened all five of M1's tests (the measure pass's entries are named only through the cache-hit branch). Filtered, not unfiltered: a test outside the set that M2 or M3 reddens is not listed.

## §7 (b) The cold-frame profile (`CF-F`, `CF-K`)

Notes and tables: `docs/probes/warm-settle/cold-profile.md` (instrument `cold-profile.sh`, `cold-harness`). Release, thread-CPU, three runs a commit, load 4.5–34. On the bracket first frame the
cold frame rose about 10 % once, at C14b (`a595b0d7` 12.7–13.0 ms to `fb9a7e42` 14.3–15.6 ms), and is flat since (`6273e3a4` 14.3–15.1, `679f5d7d` 13.6–14.4, head 14.0–15.4); its counted work
(memo misses 639 to 864, 70 ledger snapshots, 32 retained misses) did not move after `fb9a7e42`; P4 doubles the cold raster (124 852 to 255 208 px) for less than the spread. Time Profiler
attribution: layout 26.5 %, build 24.5 %, paint 30.9 %, prepaint 9.5 %, memo-miss handling 2.5 %, retained bookkeeping 1.7 %, content memo 2.4 %, rasters 7 %. **A ledger snapshot is five loads**
and invisible to the profiler; the named candidate is withdrawn (that record is what hits next frame and the snapshot taints it). **No cold-frame fix lands** (`CF-F` (i) unmet);
MetalCreator's +25 % is not reproduced here and needs a measurement on its own tree.

## §8 Looks, deferred, with owner

- **Looks owed: none.** Nothing here changes a pixel (fourteen images 0 px); no human-checks group, no record §03 entry.

- `onGeometryChange` replay in a retained subtree (`RK-E`): after C14-d, owner C14-f.
- A footprint for the root placement (`IV-E` (P)): same hazard, unmeasured; owner whoever sees `layoutMemoRootHits > 0` followed by a spike.
- MetalCreator's own-tree cold measurement and its `WarmFrameTests` comparison moved to index 1: MetalCreator's session (hand-off, not edited here).
- `@FocusState` readings and the remaining uncomparable readings: divergence 346's residue.
- C14-d merge: this branch edits `ContentMemo.swift` (+8 lines) and `RetainedPrepaint.swift` (+2) in lane 1 and none of `RetainedSubtree.swift`, `RetainedGraft.swift`, the prepaint ledger or `List`/`ForEach` retention.
