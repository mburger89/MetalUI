# AccessKit before the first show — decisions

Rulings for item C11 of the gpui-gap priority list (user request 2026-10-02;
**urgent bug, not a plan task**): every MetalUI SDL app built with the
`AccessKit` trait panics at launch on Windows. Branch
`fix/accesskit-window-show` from `cd84b0c`.
Spec: [`specs/2026-10-08-accesskit-window-show-design.md`](specs/2026-10-08-accesskit-window-show-design.md).
Record: `../record/86-accesskit-window-show.md`.

**Next unused id: `WS-I`.** (Read the last `## WS-` heading, not this line.)

Evidence:

- [`../probes/accesskit-window-show/`](../probes/accesskit-window-show/README.md)
  (**new**; `probe.c`, `run.ps1`, `run.sh`; arms `V` positive control, `H` the
  fix, `S` separating, `N` hidden) — AccessKit's adapters against a visible SDL
  window, run on the Windows VM over SSH and on macOS; recorded output and the
  upstream sources read are in its README.
- The measured failure: smk_configurator PR #10, GitHub Actions run
  37829232106, step "Launch the packaged app" (windows-latest, x64):
  `panicked at accesskit_windows-0.35.0/src/subclass.rs:168:13: The AccessKit
  Windows subclassing adapter must be created before the window is shown (made
  visible) for the first time.`, exit `-1073740791`.

No SwiftUI probe: nothing here is SwiftUI-facing. No public API is added or
changed, no divergence is opened (the reserved labels 175–176 stay unused), and
no `PlatformWindow`/`Platform`/`WindowRenderer` requirement moves. gpui is not a
reference here: it has no AccessKit integration. The reference is AccessKit's
own documented contract (`accesskit_winit`, and accesskit-c's SDL example).

## WS-A — Cause, and what each platform's adapter requires

**Ruling.** The cause is confirmed from source and the measured log:
`SDLPlatform.openSDLWindow` (`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`
at `cd84b0c`, line 60) calls `mui_window_create(..., hidden)`, which adds
`SDL_WINDOW_HIDDEN` only when the platform was made with `hiddenWindows: true`
(`SDLBridge.c:1216–1219`). Without it `SDL_CreateWindow` shows the window
before returning (SDL `SDL_video.c:2318–2320`, `SDL_FinishWindowCreation`).
`SDLWindow.init` then claims the renderer and only afterwards builds
`AccessKitAdapter` (line 277), whose Windows arm calls
`accesskit_windows_subclassing_adapter_new` on an HWND that is already visible.
`SubclassingAdapter::new` panics when `IsWindowVisible(hwnd)`
(`accesskit_windows-0.35.0/src/subclass.rs:163–168`); the panic crosses the C
ABI and aborts with `0xC0000409`.

Per platform (accesskit-c 0.23.0's dependencies):

| Platform | Adapter | Requirement | Checked? |
|---|---|---|---|
| Windows | `accesskit_windows` 0.35.0 `SubclassingAdapter::new` | before the window is shown **or focused** for the first time | **panics** if `IsWindowVisible` |
| macOS | `accesskit_macos` 0.27.0 `SubclassingAdapter::for_window` | "before the view is shown or focused for the first time" (`subclass.rs:126`) | not checked — probe arms `V`, `S` exit 0 on macOS |
| Linux | `accesskit_unix` 0.23.0 `Adapter::new` | none: takes no window (`adapter.rs:133`) | — |

**Cost if wrong.** If the panic had another cause, the fix would leave
Windows apps crashing; the order test would still be green. The CI launch step
(`WS-E`) is the check that sees the real outcome on Windows.

## WS-B — One ordering on every platform: hidden, adapter, show, renderer

**Ruling.** `SDLPlatform` always creates its window hidden, and opening a
window runs, on every platform and under both traits, in this order:

1. `SDL_CreateWindow` with `SDL_WINDOW_HIDDEN` (Swift passes `true` to the
   bridge's `hidden` parameter unconditionally; the bridge is unchanged);
2. the AccessKit adapter (under the `AccessKit` trait) — **the one thing that
   must precede the first show**;
3. `SDL_ShowWindow`, **unless** the platform was made with `hiddenWindows:
   true` (those windows stay hidden, as before; `SDLWindow.show()` remains
   their way to be shown, and still meets an adapter made while hidden);
4. the renderer (`SDLWindowRenderer(window:)`, or the offscreen target under
   the SPI `offscreenRenderers` option, `TF-E`);
5. as before, in `openSDLWindow`: registration, the application icon, the
   focus seed from `SDL_WINDOW_INPUT_FOCUS`, control-active state.

**Why the show sits before the renderer.** SDL's own visible creation is
`SDL_ShowWindow` called at the end of `SDL_CreateWindow`
(`SDL_FinishWindowCreation`), so steps 1–3 are exactly the call SDL made
before, moved past the adapter and nothing else. The GPU swapchain is then
still claimed on a shown window, as at `cd84b0c`: no change for production
renderers on any driver. (Claiming on a hidden window is already what every
`hiddenWindows: true` test does on Metal and D3D12; on a real X11/Wayland
desktop it is unmeasured, which is a reason not to move it.) The focus seed and
icon stay after the show, as they were after the visible creation.

**One ordering, not a Windows branch**: macOS's adapter documents the same
requirement without checking it, and AccessKit's own SDL example
(`accesskit-c-0.23.0/examples/sdl/hello_world.c:396–410`) and
`accesskit_winit` (`lib.rs:134`, examples) use exactly this order everywhere.
A platform branch would leave macOS violating a documented precondition and
make the order test platform-specific.

**Rule for CLAUDE.md (Record phase, the `Backends/SDL`/`PX-` paragraph):**
*an SDL window is created hidden; everything that must precede its first show
(the AccessKit adapter) runs before `SDL_ShowWindow`, on every platform.*

**Cost if wrong.** If some driver needed the renderer before the first show,
the first frame would appear late (one display-link tick) — a look, human
checks WS1–WS3. If `hiddenWindows` windows were shown, every test would put a
window on screen: pinned by `aHiddenWindowsPlatformNeverShowsItsWindow`.

## WS-C — A failed show throws

**Ruling.** `openSDLWindow` throws `SDLPlatformError("SDL_ShowWindow")` and
destroys the window (as it does when the renderer throws) when
`SDL_ShowWindow` answers `false`. SDL answers `false` only for an invalid
window (`SDL_video.c:3405–3435`), so this never fires in practice; at
`cd84b0c` SDL ignored the result inside `SDL_CreateWindow`. Throwing makes the
moved call no less strict than an explicit one should be, and costs nothing.

**Cost if wrong.** A driver answering `false` for a window it did show would
refuse to open — SDL 3.4.16 has no such path.

*Amended by `WS-G`*: "destroys the window" is `SDLWindow`'s `deinit`, once —
`openSDLWindow`'s `catch` no longer destroys it a second time.

## WS-D — The test seam: an opening log read from SDL's flag, and an injectable show

**Ruling.** Two internal (not public, no inventory row) seams in
`SDLPlatform.swift`:

- `SDLWindow.openingSteps: [SDLWindowOpeningStep]`, appended as the steps of
  `WS-B` run: `.created(shown:)`, `.accessKitAdapter(windowShown:)` (read
  immediately before the adapter is made), `.shown`, `.renderer(windowShown:)`.
  `shown` is SDL's flag, `!(SDL_GetWindowFlags & SDL_WINDOW_HIDDEN)`, through a
  new bridge function `mui_window_is_shown`.
- `SDLPlatform.showWindow: @MainActor (UnsafeMutableRawPointer) -> Bool`,
  defaulting to `mui_window_show`, so a test can see the show's place in the
  order without putting a window on a developer's screen.

**Why SDL's flag and not native visibility.** The probe measured that over SSH
(session 0) `IsWindowVisible` stays 0 after `SDL_ShowWindow` — the positive
control `V` does not panic there. A test reading native visibility would be
blind on the VM; SDL's flag records what the order controls on every driver,
offscreen included (`SDL_windowevents.c:83–88`). The native outcome is checked
where it exists — on GitHub's interactive Windows runner (`WS-E`).

**Cost if wrong.** If SDL's flag and native visibility disagreed in an
interactive session, the order test could pass while Windows still panics; the
CI launch step and the unstubbed visible-window test on the Windows runner
(where the pre-fix order aborts the process) would catch it.

## WS-E — Why CI never saw it, and the check that now can

**Ruling — why it was not caught:**

1. Every SDL test opens `SDLPlatform(hiddenWindows: true)` (17 sites at
   `cd84b0c`: 16 in `Tests/MetalUISDLTests`, one in `MainQueueDrainCheck`), so
   the adapter always met a hidden window. The visible `SDLPlatform()` is
   written only in `MetalUISDLDemo`, the `metalui new --cross-platform`
   starter (`Scaffold.swift:298`) and docs — so every generated cross-platform
   app had the bug; the scaffold's CI test builds that app but never runs it.
2. MetalUI's Windows CI (`sdl-gpu-linux.yml` job `windows`) runs `swift test`,
   `PortableReplay` and `DemoCapture` — the replayer and capture drive SDL's GPU
   directly and never open an `SDLPlatform` window. `MetalUISDLDemo`, the one
   entry point that opens a visible window, is built but never launched.
   `swift.yml`'s Windows jobs build the root without the `SDL` trait.
3. The VM baseline (CLAUDE.md "Windows locally") runs tests over SSH, where
   the probe shows the panic cannot fire; the console route needs a logged-on
   user, and on 2026-10-08 there is none (`query user`: "No User exists").
4. macOS, where the backend is developed, has no check (probe arms `V`, `S`),
   and Linux has no window to check.

**Ruling — the checks added:**

- `aShownWindowBecomesVisibleOnlyAfterItsAccessKitAdapter` opens a
  **non-hidden** window through the real `SDL_ShowWindow` (offscreen
  renderer, so it runs without a swapchain). On the Windows runner the pre-fix
  order aborts the test process — the measured panic, in `swift test`. It runs
  unconditionally off macOS (Linux image: SDL's flag under the offscreen
  driver; Windows); on macOS only with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1`,
  since it puts a window on screen and macOS's adapter checks nothing.
- A new step in the `windows` job, **"Launch the SDL demo (ruling WS-E)"**:
  start `MetalUISDLDemo.exe` (AccessKit on, the configuration that panicked),
  wait 8 s, fail with its exit code and stderr if it has exited, else stop it.
  A launch smoke, not a test (the no-sleep rule is for tests): a slow start can
  only make it pass falsely, never fail falsely; the deterministic check is the
  test above.

**Cost if wrong.** If GitHub's runner stopped running steps in an interactive
session, both checks would go blind on Windows the way the VM over SSH is; the
order test would still pin the order.

## WS-F — Scope and deferrals

**Built:** `WS-B`'s order, `WS-C`, the `WS-D` seams, four tests, the CI step,
human checks WS1–WS4, the probe. **No** public API, divergence, shader,
renderer, pixel or demo-content change.

**Deferred, each with reason and owner:**

1. *Show the window after its first frame* (no blank first paint). A real
   improvement, but it changes when content appears on every platform and
   needs a `PlatformWindow` signal; out of an urgent fix's scope. Owner: a
   later SDL-polish item of the gpui-gap list.
2. *An interactive run on the UTM VM.* No console user was logged on
   (2026-10-08). Owner: the implementer re-checks `query user` at the end of
   the branch and runs the console route if someone is logged on; otherwise
   human check WS1.
3. *Linux on a real X11/Wayland desktop* (window placement, focus, the
   swapchain claimed after the show as before). The image's offscreen driver
   presents nothing. Owner: human check WS2.
4. *The configurator's pin bump.* After merge, smk_configurator bumps its
   MetalUI pin and re-runs its "Launch the packaged app" step (its owner; not
   edited here).

## WS-G — A failed opening destroys its window once, in `SDLWindow`'s `deinit` (critic)

**Ruling.** `openSDLWindow`'s `catch` drops its `mui_window_destroy(handle)`:
the window an `SDLWindow.init` throw abandons is destroyed by that instance's
`deinit`, and only there. T4 pins the destruction, not just the throw.

**Why.** `SDLWindow.init` assigns `handle` and `id` first and every other
stored property has a default, so every throw inside it (the renderer at
`cd84b0c`, the show under `WS-C`) comes after the instance is fully
initialised — and Swift then runs `deinit`, which calls `mui_window_destroy`,
**before** the caller's `catch` destroys the same handle again. Measured:
[`docs/probes/swift-class-init-throw-deinit.swift`](../probes/swift-class-init-throw-deinit.swift)
(arm A, the positive control and `SDLWindow`'s shape: `deinit` runs, then the
`catch`; arm B, a defaultless property unset at the throw: no `deinit`; both
`-Onone` and `-O`, output in its header). The second call is harmless today
only because SDL 3.4.16 validates a window through its object table
(`SDL_ObjectValid`, no dereference) and answers "Invalid window" — it
overwrites SDL's error string and is one pointer reuse away from destroying
another window. `WS-C` makes this path a tested one (T4), so the double
ownership is fixed here rather than exercised every run.

**The check.** A new bridge function `bool mui_window_id_is_open(uint32_t id)`
(`SDL_GetWindowFromID(id) != NULL`) beside `mui_window_is_shown`. T4's
`showWindow` stub captures `mui_window_id(raw)` before answering `false`; after
the throw T4 asserts `!mui_window_id_is_open(captured)` and
`openWindowCount == 0`, then opens a second window (count 1). Mutation **M6**:
remove `mui_window_destroy` from `deinit` → T4 red (the window outlives its
failed opening). If a later change makes a stored property defaultless and
assigns it after a throw point, `deinit` stops running for that throw and T4
reddens the same way.

**Cost if wrong.** If `deinit` did not run on some toolchain, the abandoned
window would leak (visible on screen when not hidden) — T4 on every CI
platform's `swift test` sees it.

## WS-H — Critic's amendments to the test plan

**Ruling.**

1. **Mutations M1, M2, M4 run with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1`** on
   macOS (T2 is skipped there otherwise, so "T1, T2 reddened" could not be
   observed); T2's reddening is also read from the Linux image, where it runs
   unconditionally. Name the platform each reddening was read on.
2. T4's window count is the existing internal `SDLPlatform.openWindowCount`
   (no new counter).
3. The lane may edit `SDLWindow`'s `deinit` only to read it (no change);
   `WS-G` changes `openSDLWindow`'s `catch`, which is already in the lane's
   region.

Rejected on review (no change): a Linux CI launch step (Linux's adapter takes
no window, `WS-A`); a native-visibility (`IsWindowVisible`) assertion in the
tests (blind in session 0, `WS-D`); a Windows-only branch of the order
(`WS-B`). The `WS-E` CI step's `Start-Sleep` is in a workflow, not a test.

