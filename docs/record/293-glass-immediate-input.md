# 293 - Glass and immediate input: a diagnostic (`FP-Q`)

Branch `fix/glass-immediate-input` from master `eb8d4b8c`. Class M, no divergence label. Ruling `FP-Q` in
`docs/superpowers/2026-11-07-frame-timing-decisions.md`.

**Report.** Alloy (GUI benchmark, `METALUI_LATENCY_TRACE`, two glass controls over `.thickMaterial`, nothing animating,
pointer elsewhere): typed keys alternate an immediate `text 1` frame and a paced `text 2`; without glass most keys are
immediate. Typing p50 22-30 ms with glass, 15-21 without. Summary lines `written=204 dropped=1000 settledClean=100`
(glass) against `written=176 dropped=400 settledClean=128`. Seen before and after `BB-U`.

**What was tried, none of it reproduced the alternation.**
1. `TestWindow` with immediate input and a hand clock: a `TextField` with two `.glassEffect(.regular)` controls over
   `.thickMaterial`, keys 1.5 intervals apart: 20 of 20 immediate with and without glass; the release leaves the window
   clean; no extra frame.
2. The real Metal renderer behind the fake platform window (`makeFakeWindowOnDefaultDevice`): wall clock, 60 Hz
   simulated ticks, Alloy's `GlassBackdrop` shape, glass over the text: 40 of 40 immediate in every arm, one frame per
   key.
3. Alloy's own UI (`alloyWindow`, build 33348b4 against this tree), `ALLOY_GLASS=0` and `1`: one frame per key, no
   trailing frames; on a vsync/key timeline (ticks every interval, keys every 1.5) 55 of 60 and 53 of 60 immediate.
   Both arms saw the same `@Observable`-driven dirtying about once per key.

**Reading of the trace.** `idx` is `framesRecorded`, every drawn frame; frames no input caused are never written and, as
macOS reports `presentedTime` 0, land in `dropped`. The index advances by 2 per key without glass (one logged input
frame and one follow-up frame no one logs) and by about 3.5-4.5 with glass. A follow-up frame commits at a tick, which
sets `lastCommitForPacing`; a key less than one interval after it is paced. Code reading found nothing in
`Glass*.swift`, `Material.swift`, `BackdropBlurPipeline.swift`, `MetalWindowRenderer` or the platform that dirties the
window, animates or adds a timer.

**What landed.** The instrument that names the blocker: `why=` (`drawing`, `needsRedraw`, `animations`, `timer`,
`pacing(<ms>ms)`) on a paced input frame, `dirty=<source>/<count>` on every frame, and `METALUI_LATENCY_TRACE_ALL=1`
for the frames no input caused (kind `tick` or `frame`). Zero work with the trace off. Tests: `FrameTimingWhyTests`
(11), each reason and tag pinned and mutated (reason checks removed, observation untagged, input context unset, default
tag changed, the `traceSink` guard removed, the sub-switch ignored).

**Not done, to decide after an Alloy run with `METALUI_LATENCY_TRACE_ALL=1`:** stamp the pacing clock only for immediate
frames (a follow-up tick frame would stop delaying the next key); let a key draw at a window dirty only from earlier
non-input changes.
