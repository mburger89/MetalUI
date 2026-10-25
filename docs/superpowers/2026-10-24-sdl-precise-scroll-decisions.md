# SDL precise scroll for MetalCreator (XP-G28) — decisions

Rulings for item XP-G28 of the gpui-gap priority list (MetalCreator request 2026-10-24, `docs/metalui-gaps.md` XP-G28; **not a plan task**). Prefix `TP-`.
**Next unused: `TP-R`.** Spec: [`specs/2026-10-24-sdl-precise-scroll-design.md`](specs/2026-10-24-sdl-precise-scroll-design.md). Record: `../record/155-sdl-precise-scroll.md`.
Branch `feat/sdl-precise-scroll` from `935d0096`. Amends `CI-I` item 6 (SDL fills `.none/.none/false`) and builds on `IF-G`/`IF-H` (record 93). Divergence labels reserved 845-854: **845, 846 taken** (spec section 7).

Sources of truth. Facts about SDL come from the SDL 3.4.16 source tree (`fa2c02bb`, the Dockerfile's pin; `src/events/SDL_mouse.c`, `src/video/{wayland,x11,windows,cocoa}`, headers
`SDL_events.h`, `SDL_mouse.h`, `SDL_touch.h`) read on this machine; quoted lines are cited by file and function. **No real trackpad exists in this environment: every statement
about what a given desktop sends is a reading of SDL's source, not a measurement**; the measurements are human checks group `TP`. SwiftUI: probe
`docs/probes/swiftui-scroll-precision.swift` (positive control plus two separating arms, output in its header): SwiftUI shows a view a `ScrollView`'s phases
(`onScrollPhaseChange`) and never the device class, and has no per-view wheel hook, so **no SwiftUI claim is made** (`CI-I` item 2 already ruled `onScrollWheel` MetalUI-only).
gpui (`ScrollWheelEvent`, `ScrollDelta::{Pixels, Lines}`, `TouchPhase`) is the comparison, recalled and unverified here.

## TP-A — SDL forwards no device class and no phase; the evidence

**Evidence (SDL 3.4.16).**
- `SDL_MouseWheelEvent` has `x`,`y` (float, per event), `integer_x`,`integer_y` (**accumulated** whole ticks, added 3.2.12), `direction` (NORMAL/FLIPPED = the user's natural-scroll setting, not a device class)
  and `which`. `SDL_SendMouseWheel` (`SDL_mouse.c`) overwrites `which` with `SDL_GLOBAL_MOUSE_ID` unless the mouse is in relative mode, so **no per-device identity reaches an app** (X11 passes the XI2 `sourceid`, Windows
  raw input a device handle, Wayland the seat's id; all discarded there).
- Wayland (`SDL_waylandevents.c`): `pointer_handle_axis_source` and `pointer_handle_axis_stop` bodies are the literal comment `// unimplemented`. `axis` (continuous, finger or wheel alike) arrives as `value / 10`;
  `axis_discrete` as the integer; `axis_value120` (hi-res wheels) as `value / 120`, so a 1/4-notch step is `0.25`.
- X11 (`SDL_x11xinput2.c`, `xinput2_parse_scrollable_valuators`): XI2 smooth scrolling gives `delta = (prev - current) / increment`, a double, a fraction; the first event of a baseline is dropped; **no stop, no source**.
  Classic buttons 4-7 (`X11_HandleButtonPress`) give whole ticks.
- Windows (`SDL_windowsevents.c`): `fAmount = amount / WHEEL_DELTA`, a notch is exactly `1.0`; a precision touchpad's small `WM_MOUSEWHEEL` amounts are fractions; **inertia after the fingers lift is the same message stream**; no phase.
- macOS under SDL (`SDL_cocoamouse.m`): a precise event is `scrollingDelta * 0.1` (fractional), a wheel is `ceil/floor` whole; no phase, `isDirectionInvertedFromDevice` becomes `direction`.
- Touch devices: `SDL_AddTouch` is called by Wayland for a **touchscreen** (`SDL_TOUCH_DEVICE_DIRECT`) only, never for the pointer's gestures; Windows none; cocoa for its trackpad's touch events; X11 only with XI2 multitouch.
  `SDL_GetTouchDevices` therefore cannot say "a trackpad is scrolling", and could not be joined to a wheel event anyway (no `which`).

**Ruling.** The only per-event signal SDL gives on every platform is the **granularity of `x`/`y`**. Device names, touch-device lists, `which`, `direction`, `integer_x/y` and hints are rejected (TP-B, TP-E).
**Cost if wrong.** If a future SDL forwards `axis_source`/`axis_stop`, the heuristic is replaced behind the same `ScrollEvent` fields; no seam change (TP-J).

## TP-B — `isPrecise` is "the event's `x` or `y` is not a whole number", per event, then held for a stream (TP-C)

**Ruling.** An event is **fractional** when `|v - v.rounded()| > 1e-4` on either axis (finite values only; a non-finite delta is not fractional, no trap). `1e-4` sits two orders below SDL's finest real step (`1/120 = 0.0083`) and
above float noise on `/ 10` and `* 0.1` arithmetic. The bridge already carries `dx`,`dy` as SDL's `x`,`y` (`SDLBridge.c` `MUI_EVENT_WHEEL`); **no C change**. `integer_x/y` are not read: they are residual-accumulated, so an event of `0.4` reads `0` then
`0` then `1` and cannot classify a single event. `ScrollEvent.delta` is **unchanged** (lines times 10, `pointsPerScrollLine`): `isPrecise` only labels it, as AppKit's flag does (`CI-I` item 1).
**Cost if wrong.** Two misclassifications, both named: a hi-res wheel is fractional and reads precise (TP-D); a trackpad event that happens to be integral and opens no stream reads as a wheel (TP-C). The first costs MetalCreator a pan where
the user wanted a zoom on that wheel, the second one wheel-like event at the start of a stream.

## TP-C — a stream: precise is sticky for 0.15 s between events; the first fractional event opens it

**Ruling.** `SDLScrollClassifier` (pure, `MetalUISDL`, internal) keeps `lastPreciseTime`. An event is precise iff it is fractional **or** a stream is open (`now - lastPreciseTime <= 0.15`); a precise event refreshes
`lastPreciseTime`. An integral event with no open stream is a wheel and refreshes nothing, so a wheel is never promoted by a neighbouring wheel. The interval `quietInterval = 0.15` s is a named constant, **a ruling, unmeasured**:
a precision touchpad's events arrive every 8-16 ms and libinput's every frame, so 150 ms is ten missed frames; check TP-measure records the real gaps (human checks `TP1`-`TP3`).
**Why sticky.** Windows and X11 trackpad deltas are integral by accident often enough (a fast two-finger flick on a precision touchpad sends whole multiples of `WHEEL_DELTA`); without stickiness a stream flickers precise/wheel, and the
consumer's pan flips to zoom mid-gesture, the exact failure the request names.
**Cost if wrong.** A wheel notch within 150 ms after a trackpad stream reads precise (rare: a hand changes device). Too short an interval splits a gesture; too long delays `.ended` (TP-F).

## TP-D — a hi-res wheel reads precise; `SDLPlatform.Options.scrollPrecision` turns the detection off

**Evidence.** Wayland `axis_value120` and Windows hi-res wheels (`amount < WHEEL_DELTA`) produce fractions with no flag to tell them from a finger (TP-A). libinput's `axis_source` would (wheel vs finger) and SDL drops it.
**Ruling.** Say so (divergence 845) and give the app the escape: `SDLPlatform.Options.scrollPrecision: SDLScrollPrecision`, `.automatic` (default) or `.disabled` (today's behaviour byte for byte: `false`, `.none`, no synthesized event). MetalUI-only, class `M`,
`Backends/SDL` so outside the census. **Not built:** per-event device allow-lists (no device identity, TP-A); an environment variable (an app decides, not a shell).
**Cost if wrong.** An app with hi-res wheel users sets `.disabled` or accepts pan-on-wheel; AppKit has no such hole because the OS flags the event.

## TP-E — touch devices, mouse names and platform hints are rejected, with the cost of each

**Ruling.** Rejected: (1) **`SDL_GetTouchDevices` / `SDL_GetTouchDeviceType`**: a touchpad is not registered on Wayland or Windows and, where registered, not joinable to a wheel event (`which` is global); using "an indirect device
exists" would mark a desktop with a laptop touchpad *and* a mouse precise for the mouse. Cost if wrong: every wheel on a laptop reads precise. (2) **Mouse names** (`SDL_GetMice`, `SDL_GetMouseNameForID`): enumerable, but no event carries the id, and names are unstable strings. (3) **`direction`**:
the natural-scroll setting; a notched wheel on a natural-scroll desktop is `FLIPPED` too. (4) **Hints**: `SDL_HINT_MOUSE_INTEGER_MODE` makes SDL round for the app; if an app sets it, every delta is integral and detection reads wheel (documented, not worked around).
Per platform, detectable by ruling: Wayland, X11, Windows and macOS-under-SDL all by granularity; none by device.

## TP-F — phases are synthesized for a precise stream: `.began`, `.changed`, and an inferred `.ended`

**Ruling.** Where SDL gives no phase (TP-A) MetalUI **synthesizes** one, only for a precise stream: the first precise event after no open stream is `phase: .began`, later ones `.changed`, and when no precise event has arrived for
`quietInterval` the platform delivers **one more `ScrollEvent`: delta zero, `phase: .ended`, the last event's position, modifiers and `isPrecise: true`** (the shape AppKit's terminal event has, and `IF-H`'s synthesized one). A wheel event (not precise)
stays `.none/.none`. The `.began` event carries its own delta (AppKit's does too). `.mayBegin` and `.cancelled` are never synthesized by the platform (`Window` still synthesizes `.cancelled` on key loss or close, `IF-H`); on focus loss or close the classifier drops its stream and **emits nothing**,
so a window cannot receive `.ended` after `IF-H`'s `.cancelled`.
**Honest limits (divergence 846).** `.began` is exact, `.ended` is **late by up to `quietInterval` plus one loop wake** and **inferred**: a pause longer than 0.15 s inside one physical gesture splits it into two. This is stated in `ScrollEvent`'s and `SDLPlatform`'s docs.
Why synthesize at all: `IF-G`'s latch (a handler sees one gesture's events at one cover, wheel veto, `.ended` cleanup) is the feature consumers expect on a trackpad; with `.none` it never engages. **Why not only `isPrecise`:** the request accepts it, but
without `.began` the latch is dead on SDL, and the handlers' "gesture over" (e.g. committing a pan) has no signal. Synthesis costs one timer, built as the loop wake (TP-I).
**Cost if wrong.** A consumer that treats `.ended` as "fingers left" may commit 150 ms late; one that sees a split gesture sees two. `.disabled` removes it all.

## TP-G — momentum stays `.none` on SDL, by evidence

**Evidence.** libinput delivers no kinetic scrolling (clients implement it: GTK does, in the toolkit, and SDL does not); Wayland has `axis_stop` only; Windows inertia is the same `WM_MOUSEWHEEL` stream as the fingers; X11 has no inertia.
**Ruling.** `momentumPhase` is never set by SDL, `isMomentum` is false. On Windows the OS's inertia events arrive as ordinary precise `.changed` events; a consumer that ignores momentum (MetalCreator's viewport) will see them as the user's motion: documented, divergence 846.
A synthesized momentum would be a fiction. **Cost if wrong.** None built; a consumer wanting momentum applies its own.

## TP-H — the latch (`IF-G`), `DD-Y` and `onScrollWheel` dispatch are untouched; pinned, not edited

**Ruling.** No `Window` source change. A synthesized `.began` latches the cover as AppKit's does; `.changed`/`.ended` dispatch to the latched chain; **a phaseless wheel event still ends a latch** (`Window.applyScroll`'s first line, `IF-G` item 3). SDL cannot produce that inside an open stream (TP-C keeps an integral event precise), so W2 pins the `Window` rule through a hand-built phaseless event, not an SDL one; a notch after the quiet interval ends the latch and is dispatched fresh; the `.ended` that follows is a gesture event with no latch, so it dispatches normally by the pointer (a harmless zero-delta). `ScrollView`s scroll by `delta` exactly as before (a zero-delta `.ended` scrolls nothing).
**Evidence to take before relying on it:** pins W1-W4 (spec section 4) run SDL-shaped streams through a real `Window`.
**Cost if wrong.** A latched cover that is removed mid-stream is dropped by `latchedScrollCover` (existing); nothing new.

## TP-I — the loop wakes for the quiet interval; time is injected, never slept

**Ruling.** `SDLWindow` owns the classifier (the stream is per window: `.ended` goes to that window's `onInput`). `SDLPlatform.run` waits `min(250, remainingMs)` when any window has an open stream (`scrollWaitTimeoutMilliseconds`, pure), and every pass calls
`expireScrollStreams(now: mui_now())`, which asks each window to close a stream past its deadline. `mui_now()` and the event's `timestamp` are the same clock (`SDL_GetTicksNS() / 1e9`, `SDLBridge.c`), so a stream's deadline compares directly. Tests call the internal
`handleWheel(dx:dy:timestamp:modifiers:position:)` and `expireScrollStreams(now:)` with chosen times; **no test sleeps**.
**Cost if wrong.** A paused display link leaves `.ended` waiting for the next wake: bounded by the wait ruling.

## TP-J — no seam change

**Ruling.** `ScrollEvent`, `InputPhase`, `PlatformWindow`, `Platform` and `WindowRenderer` are unchanged: no defaultless requirement, no migration note, no census row, no `Handlers` change. Doc comments on `ScrollEvent.phase/momentumPhase/isPrecise` and on `SDLPlatform` change (they say "always on SDL");
the AppKit conformer's behaviour is untouched (values pinned by `PlatformTests`, `AppKit`).
**Cost if wrong.** None; the documented fields were designed for this (`CI-I`).

## TP-K — what is a divergence

**Ruling.** SwiftUI has no `isPrecise` and no per-view wheel hook (probe), so the fields are MetalUI's own and no SwiftUI row applies. **Two divergence rows from AppKit's meaning, class M**: **845** `isPrecise` on SDL is a heuristic over delta granularity with a 0.15 s hold, not a device flag
(a hi-res wheel reads precise); **846** SDL's phases are synthesized, `.ended` is inferred and late, no momentum, no `.mayBegin`. Pinned by the characterization tests T9 and P2.

## TP-L — what is deferred, with owner

**Ruling.** Deferred, by name: (1) real libinput `axis_source`/`axis_stop` and XI2 scroll flags, needs SDL to forward them or a private Wayland listener (owner: a later `TP-` item, trigger: an SDL release that forwards, or MetalCreator evidence the heuristic mis-reads real hardware, human checks `TP`);
(2) momentum (TP-G); (3) a `quietInterval` option (made configurable only if `TP` measurements disagree); (4) Windows precision-touchpad `WM_POINTER` gestures (SDL's loop does not expose them; `CI-K` item 1 already records Windows' control+wheel pinch).

## TP-M — a stale stream is closed by ANY later event; the finite guard and T11 (critic, amends TP-C, TP-F)

**Ruling.** `closedStale` is set for any event arriving after the open stream's deadline, precise or not, so `.ended` always precedes a later wheel notch and the order a window sees is `.ended` then the notch (the spec's draft closed it only for a precise event, leaving a late `.ended` after the notch). T11 is a characterization pin: a NaN or infinite delta compares false against the tolerance with no guard, so no `isFinite` guard is written and no mutation is claimed for it. T5's mutation is the interval, not a comparison.
**Cost if wrong.** Ordering only.

## TP-N — `Options.scrollPrecision` lives in both `Options` declarations (critic)

**Ruling.** `SDLPlatformOptions.swift` and the trait-off stub in `SDLPlatform.swift` each gain the field and a defaulted `init` parameter (placed last; existing call sites unchanged); a stored property on a public type crossing a module boundary owes `swift package clean` before the suite. Rejected: reading the setting from the environment (TP-D).

## TP-O — critic's rejections

**Ruling.** Rejected: making `.ended` carry `momentumPhase` (TP-G); synthesizing `.mayBegin` (no signal precedes the first event); a SwiftUI claim (probe re-run byte for byte by the critic on 2026-10-24: control exit 0, ARM_1 `no member 'isPrecise'`, ARM_2 `no member 'onScrollWheel'`, as recorded). Accepted limits: lanes are disjoint (lane 1 `Backends/SDL`, lane 2 root tests and a doc comment); no shader, seam, census, pixel or demo change, so the fourteen images and `DemoFrameDeterminismTests` cannot move.

## TP-P — the deadline is inclusive at both ends; the idle wait ignores clock-sum noise (implementer, amends TP-C)

**Ruling.** A stream ends when `now >= deadline`: `expire(at:)` and the stale test in `classify` use the same comparison, so an event arriving exactly at the deadline is not precise-by-stickiness and reports the old stream closed, and `expire` at the deadline ends it. (The draft's "`now - lastPreciseTime <= 0.15` is open" differed from `expire`'s boundary by one tick; one boundary is simpler to pin, T7.) `scrollWaitTimeoutMilliseconds` rounds `remaining * 1000` up after subtracting `1e-6`, because `(t + 0.15) - t` is `0.15000000000000568` in doubles and a plain `ceil` added a millisecond (P5 caught it).
`mui_push_event` leaves `common.timestamp` zero and `SDL_PushEvent` stamps `SDL_GetTicksNS()`, the clock of `mui_now`, so P1's pushed events and the loop's `expireScrollStreams(now: mui_now())` compare directly; P2-P6 inject times regardless.
**Cost if wrong.** One tick of boundary; a millisecond of wait.

## TP-Q — a phase `.ended` does not clear the latch; the next SDL event ends or replaces it (implementer lane 2, amends TP-H and spec section 4 W1)

**Ruling.** `ScrollLatch.advance` leaves the latch alive after a finger `.ended` with no momentum (AppKit's latch lives to the momentum's end); SDL never sends momentum (`TP-G`), so the latch outlives a synthesized `.ended` until the next event, which is either phaseless (a notch: `applyScroll`'s first line clears it, `IF-G` item 3) or a `.began` (replaces it); a `.changed` cannot follow an `.ended` from SDL. So no stale latch is reachable, and **`Window` is not edited**. The spec's W1 "`.ended` clears it" and its mutation "latch not cleared on `.ended`" were inexact: there is no such clear to mutate, and `advance` returning `true` on `.ended` is unobservable from SDL. W1 is renamed `aSyntheticBeganLatchesTheCoverAndTheNextEventEndsOrReplacesIt` and pins the real rule. W3's "requests no extra frame" is dropped: a zero-delta `scroll(_:by:)` still writes the offset and the stamp (a state write, as any wheel event), so the claim was not true of `Window`; the pin is the offset.
**Cost if wrong.** A latched cover surviving an `.ended` is dispatched to only by a gesture-phase event, which SDL cannot send before a `.began`.
