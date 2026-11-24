# 403: a write read only by a replayed descendant's prepaint redraws (Alloy, `SB-AF`)

Class `M` (no public declaration, no divergence). Branch `fix/retained-prepaint-observation`, base master `a306e124`. Record number: open PRs hold 398, 399, 400 and 401 (two of them), 402 was left free for another; this is the next above all of them.

## Report

Alloy: `setLineDecorations`, `setVirtualRows` or `setHighlights` after the window went idle sometimes dirtied nothing under `.equatable()` occurrences with retained prepaint. `needsRedraw` false, `observationDirtyings` unmoved, a repeated write no better, only a resize recovering; 4 runs in 6 without Alloy's one-point resize nudge, 6 of 6 green with `METALUI_RETAINED_PREPAINT=0`. Alloy suspected a record made in an unarmed interval (`RX-S`).

## Root cause (not the unarmed interval)

Reproduced from Alloy's `PluginDecorationTests` in a copy (nudge disabled, MetalUI pointed at the worktree), with temporary logging of every retained session run, fire, prepaint decision and record. `decorations.revision` was read inside armed sessions at every step. The sequence: frame 1 records `A` (outer), `B` (holds the panel) and `C` (panel) with all windows observed, the read merging up into all three prepaint sessions. Frame 2: an unrelated observed read (`FileTreeModel.snapshot`) fires `A`'s build session; `A` misses, retires its prepaint session and runs a new one while `B`, unchanged, replays its prepaint and paint, so `C`'s read is not in `A`'s new session; `A` records `coveragePrepaint = true`. Frame 3 replays `A` whole. The write fires `B`'s and `C`'s sessions only (`RetainedHandle.fire`, `live=true`), their flags set, the window dirtied; the next frame replays `A` (`PREPAINT ... observed=false replay=true obsChange=false`), never reaching `B` or `C`. Their sessions are spent, so a second write finds none armed. Retained prepaint off removes the frame-3 replay, hence the control. `Window.swift`'s unarmed interval is not involved. This is `SB-AC`'s twin: that rule covers a descendant's content running, this one a descendant's prepaint, paint and build windows.

## Fix (`SB-AF`)

`RetainedHandle.bookkeep` queues the fired occurrence's identity on `ContentMemoStore` (`noteRetainedFire`; `Entry.id` is new); `entry(for:)` flags every entry whose identity encloses a queued one (`flagAncestorsOfFires`, one `GlobalElementID.parent` walk per queued identity, then one pass over the entries) with `MemoFlags.fireRetained`. The ancestor misses on `observedChange` everywhere that flag is read (build, prepaint, paint, graft), descends, and the descendant runs. Generic: any `@Observable` read in a replayed descendant's build, prepaint or paint window, not `CodeView` only.

## Tests and mutations

- `RetainedObservedDecorationsTests.aDecorationWriteAfterTheGroupRebuiltRedrawsUnderEquatableOccurrences` (MetalUITestingTests, 4 cases): a `CodeView` in two nested `.equatable()` components, the outer's getter reading a gate; 0 to 4 gate writes, focus cleared (a focused view is never replayed), a decoration write, then a second one: needsRedraw and the painted gutter bars (1, then 2). Mutation (`flagAncestorsOfFires` returning at once): the cases with a gate write fail at the first bar count, at `needsRedraw` after the second write and at the second bar count, exactly Alloy's symptom; the case without a gate write passes (the control).
- `RetainedAncestorObservationTests.aWriteReadOnlyByAReplayedDescendantsPrepaintRedraws` (MetalUITests, 3 cases): a custom element reading an `@Observable` only in `prepaint`, two nested `.equatable()` occurrences, the outer re-armed by a gate write; the colour after the write. Same mutation red for 1 and 3 gate writes, green for 0.

## Cost

No cost pin moved (steady frames take one array-emptiness check per `entry(for:)`; retained hits, windows opened and allocation ceilings are the suite's, unchanged).
