# 341 - Terminal OSC and the snapshot source (`TRM-AE`..`TRM-AH`)

Renumbered from 340 because #343 (`340-closed-popover-free`) merged first.

Branch `feat/terminal-osc-source` from master `0dfd9f13`; Phase 1.4 of `docs/superpowers/plans/2026-11-16-terminal.md`. Class M, no divergence label. Ids `TRM-AE`..`TRM-AH` only; the decisions doc's "next unused" line (now `TRM-AI`) and the record number will conflict with `feat/terminal-encoders` (Phase 1.7) on merge: rename and reconcile then.

**What landed.** `TerminalEmulator` runs OSC 0/2 (`.title`, 256 characters), OSC 7 (`.workingDirectory`, `file` URLs on an empty, `localhost` or own host only), OSC 8 (hyperlinks: the id lives in the pen so cells carry it through the attribute spans, `id=` plus target reuses the numeric id, SGR 0 keeps the link, `TerminalSnapshot.links` is the table, `.hyperlink` once per new link) and OSC 10/11 queries (replied to only when the owner sets `package var queryColors`; the emulator has no theme of its own, so the default is no answer, `TRM-AF`). OSC 52 and every other number are dropped. `TerminalSnapshotSource` is the frozen hand-off: `feed` (on the queue: feed, publish, merge), `resize` (newest pending wins), `onReply` (on the queue, in order), `onEvents` (main actor, one batch per hop), `perform`. Phase 5 attaches through `package var onWake` and `package func takeSnapshot()`; nothing public beyond the frozen signatures.

**Skipped / seams.** `resize` applies through `package var resizeHandler`, which does nothing until Phase 1.5 adds `TerminalEmulator.resize(cols:rows:)` (reflow). OSC colour setting, DCS and APC remain parsed and dropped. A reply to OSC 10/11 always ends in ST.

**Judgement calls.** The merge happens per feed (a publish is O(damaged rows)), the view's take is the single hand-off: "one merge per take" is counted as N publishes, one wake, one take. Titles count characters, not bytes. The link table is bounded at 65 536.

**Tests.** `MetalUITerminalTests`: 141 on macOS (`--build-system native`, `--no-parallel`), 142 on Linux `swift:6.4-noble`. New: fixtures 41-45 (title with BEL and ST, working directory, hyperlinks, id reuse, SGR 0), `OSCTests` (title cap in characters, payload cap boundary, dropped clipboard, host rules, link table, version bump, link bound, colour queries, row sharing by storage address, full frame after an alternate switch), `SnapshotSourceTests` (a 10 MB flood: 160 publishes, 1 wake, 1 take; merged damage; full frame kept; storage identity across takes; replies to `onReply` on the queue and absent from `onEvents`; 100 events in one delivery; newest resize replaces a pending one; `perform`), two OSC streams in the chunk-split corpus. The fixture format gained `title:`, `cwd:`, `link:ID:URI` events and `link=N` in `attr`. Every wait is `queue.sync {}` or a bounded semaphore.

**Mutations, each red** (a line changed, the filtered suite run, the file restored from a copy): wake on every feed; merge keeping the first row; replies routed to `onEvents`; SGR 0 dropping the link; id reuse broken; title cap removed; host check removed; event hop scheduled per batch member (coalescing off).

**Linux.** 142 tests green in `swift:6.4-noble`, from a scratch package of the target and tests; container and scratch directory removed.
