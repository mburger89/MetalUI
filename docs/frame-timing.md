# Frame timing and signposts

Opt-in instrumentation for a benchmark harness or a profiling session: when did the input arrive, how long did layout, prepaint and paint take, when was the frame committed, and (on macOS) when did it reach the screen. MetalUI-only (SwiftUI has no equivalent); rulings `FP-A`..`FP-H` in [`superpowers/2026-11-07-frame-timing-decisions.md`](superpowers/2026-11-07-frame-timing-decisions.md). Off by default and free when off: one optional check per input event and per frame, no clock read, no allocation.

## Turn it on

```text
window.frameTiming = FrameTiming()                         // record, no signposts
window.frameTiming = FrameTiming(capacity: 2048, emitsSignposts: true)
METALUI_LATENCY_TRACE=1 swift run MyApp                    // per-stage input-to-screen lines on stderr (or =<path>), see FP-I; applies to any FrameTiming, also one you assign (FP-J)
frameTiming.enableTrace(destination: "/tmp/latency.txt")    // or turn the trace on from code (FP-J)
frameTiming.writeTraceSummary()                            // write the summary line now (FP-K); also every 100 presentation reports
METALUI_SIGNPOSTS=1 swift run MyApp                        // every window: record + signposts
window.frameTiming = nil                                   // stop
```

`Window` is the one `App.openWindow` returned (or `TestWindow.window` in a test). The ring keeps the last `capacity` frames (default 512).

## Read it

```text
let timing = FrameTiming()
window.frameTiming = timing
// ... drive the app ...
for s in timing.samples {                  // oldest first
    if let latency = s.inputToCommit { record(s.inputKind, latency, s.frameDuration) }
}
timing.onFrame = { sample in ... }         // after each frame, outside every phase
timing.onPresented = { sample in ... }     // when the platform reports presentation (macOS)
```

`samples` allocates its array; `last`, `framesRecorded` and `removeAll()` do not. A callback may write state: it schedules the next frame like input does, it is never "stale".

## What each time means

All values are `UInt64` nanoseconds on `FrameTiming.now()`: the system's monotonic uptime (`mach_absolute_time` on Apple platforms, `CLOCK_MONOTONIC` elsewhere). On Apple platforms that is also the clock of `NSEvent.timestamp`, `CACurrentMediaTime()` and `MTLDrawable.presentedTime`, so they compare directly.

| Field | Meaning |
| --- | --- |
| `frameIndex` | 0 for the first frame the timing recorded; consecutive. |
| `inputKind` | `.key`, `.text`, `.pointer`, `.wheel` or `.other` for the earliest input that dirtied the window since the previous frame; `nil` for a frame no input caused (animation, timer, a task's write). |
| `inputTimestamp` | When that event occurred: the platform's own timestamp if it is on our clock (AppKit), else `inputReceived`. |
| `inputReceived` | When `Window` received it. Always on our clock. |
| `inputCount` | How many dirtying inputs this frame covers. |
| `buildStart` | Start of the frame function, before the drawable is acquired. |
| `layoutEnd`, `prepaintEnd`, `paintEnd` | End of each phase. A frame that builds more than once keeps the last build's. |
| `commit` | `finishFrame` returned: Metal's command buffer is committed, SDL's frame submitted. Not the time pixels changed. |
| `presented` | Metal: the drawable's `presentedTime`, delivered later into the same ring slot, `nil` if the frame was dropped. SDL: always `nil` (SDL_GPU reports none). Headless: `nil` unless a test scripts it. |

Derived: `inputToCommit` (keystroke to submit), `inputToPresented` (keystroke to screen, where reported), `frameDuration` (`buildStart` to `commit`).

To split a latency between the app and MetalUI: `inputReceived - inputTimestamp` is the event queue; time the app's own handler with your own clock (the `Input→Frame` interval begins after the handler returns, so the handler is the gap before it); `buildStart...paintEnd` is MetalUI plus the app's `body`/`content` evaluation (they run inside layout), `commit - paintEnd` is encoding and submission.

## Signposts (macOS)

With `emitsSignposts: true` or `METALUI_SIGNPOSTS=1`, subsystem `com.metalui`, category `Frame`:

| Name | Kind | Spans |
| --- | --- | --- |
| `Input→Frame` | interval | an input event that dirtied the window is settled, to the commit of the frame that draws it (message: the kind) |
| `Frame` | interval | frame start to commit (message: the frame index) |
| `Layout`, `Prepaint`, `Paint` | event | the end of that phase, inside `Frame` |
| `Present` | event | the platform reported the frame on screen |

```sh
xctrace record --template 'Time Profiler' --instrument 'os_signpost' --launch -- ./MyApp
xctrace export --input trace.trace --xpath '/trace-toc/run/data/table[@schema="os-signpost"]' | grep com.metalui
log stream --predicate 'subsystem == "com.metalui"' --signpost   # live
```

In Instruments add the Points of Interest or os_signpost instrument and filter on `com.metalui`.

## Limits

- `inputTimestamp` is the event's creation on AppKit; SDL and simulated events carry timestamps on other clocks, so there it equals `inputReceived`.
- Only an event that left the window dirty is an input: a hover over nothing never becomes a later frame's cause.
- `commit` is submission. For display latency use `presented` (macOS) or an external camera/probe.
- `presented` arrives a frame or two after the frame and fills the sample in place; read it after the fact, or in `onPresented`. A ring that wrapped meanwhile drops it.
- A timing belongs to one window.
- Recording is a few clock reads per frame (about 40 ns each); signposts add the OS's own cost, so do not leave them on when measuring the last microsecond.

## The trace summary (`FP-K`)

While a trace is on, a line `metalui-latency-summary written=N presentedNoInput=N dropped=N settledClean=N` is written on `writeTraceSummary()` and after every 100 presentation reports, so a run explains itself. The field order is stable; new fields are appended. `written` data lines so far; `presentedNoInput` presented frames no input caused; `dropped` frames the platform reported with no presentation time (never shown, or on macOS every frame; their input lines are written and counted in `written` too); `settledClean` inputs whose handler left the window clean (dropped: they caused no frame). `written=0` with no summary line means no presentation report reached the timing.

## Immediate input (`FP-M`)

A key, text (IME composition included) or button event arriving at an idle window draws its frame at the end of its handler instead of at the next display-link tick. Measured on the Alloy editor (release, 60 Hz, screen-capture keystroke to visible): median 37.6-39.0 ms without it, 16.2-16.4 ms with it (p95 48-51 ms to 23.7-23.8 ms). It is the default on macOS (AppKit); on SDL it is off until measured there. `METALUI_IMMEDIATE_INPUT=1` forces it on, `METALUI_IMMEDIATE_INPUT=0` forces it off; the trace header ends `immediate=default|on|off`.

Quality rules: at most one immediate frame per refresh interval (an event inside the interval waits for the tick, which draws a burst as one frame); never inside a frame; never for a move, drag or scroll; not while an animation or a gesture or tooltip timer is pending; no double draw (the tick after an immediate frame finds the window clean and pauses the link); no new timers. Such a frame has no `tickStart` (`recv>tick` is `-`). The harness (`TestWindow`) stays tick-driven. The drawable-count, late-drawable and transaction experiments of `FP-L` gave no gain (within 1-2 ms of baseline) and were removed.

`est>screen` (a trace column) is MetalUI's own estimate, commit to the first vsync at or after it, from the display link's tick targets; it is `-` without a known refresh interval and is never mixed into `commit>screen`, which is the platform's `presentedTime`. On a window where the platform reports `presentedTime` 0 for every frame (seen on macOS in a real window, cause unconfirmed), each input frame still gets a line (`FP-M`): `commit>screen` and `total` are `-`, `est>screen` is filled, and the summary shows `dropped` equal to the frames drawn and `written` counting those lines too; use `est>screen` and an external probe.

