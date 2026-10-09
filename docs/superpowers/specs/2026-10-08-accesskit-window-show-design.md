# AccessKit before the first show — design

Item C11 of the gpui-gap priority list (user request 2026-10-02; **urgent bug,
not a plan task**): every MetalUI SDL app with the `AccessKit` trait panics at
launch on Windows. Branch `fix/accesskit-window-show` from `cd84b0c`. Rulings:
[`../2026-10-08-accesskit-window-show-decisions.md`](../2026-10-08-accesskit-window-show-decisions.md)
(`WS-A`…`WS-H`). Record: `docs/record/86-accesskit-window-show.md`. Probe:
[`docs/probes/accesskit-window-show/`](../../probes/accesskit-window-show/README.md).

**Status: implemented and recorded (2026-10-08)** — red `a407cfb`, fix `91b145d`, record §86.

## 1. Scope

| # | What | Answer | Ruling |
|---|---|---|---|
| 1 | AccessKit's Windows adapter is created on an already-visible HWND and panics | **Fixed**: every SDL window is created hidden; the adapter, then `SDL_ShowWindow` (unless `hiddenWindows`), then the renderer — one order on every platform | `WS-A`, `WS-B` |
| 2 | A failed `SDL_ShowWindow` | throws; the window is destroyed once, by `SDLWindow`'s `deinit` (the `catch`'s second destroy goes) | `WS-C`, `WS-G` |
| 3 | No test sees the order | an internal opening log (SDL's flag) and an injectable show; four tests | `WS-D` |
| 4 | Windows CI never launches an AccessKit window | a non-hidden-window test that aborts pre-fix on the runner, and a demo launch step in the `windows` job | `WS-E` |

No public API is added or changed (no inventory row, census unmoved). No
divergence (reserved labels 175–176 unused). No `PlatformWindow`/`Platform`/
`WindowRenderer` requirement. No shader, renderer, pixel, demo-content or
root-package source change. Nothing SwiftUI-facing, so no SwiftUI probe; gpui
has no AccessKit integration, so the reference is AccessKit's own contract
(`accesskit_winit`, accesskit-c's SDL example — probe README "Sources read").

## 2. Evidence

The probe (`probe.c`, arms `V` positive control, `H` fix, `S` separating, `N`
hidden), recorded in its README:

- **macOS**: all four arms exit 0 — `accesskit_macos` documents "before shown
  or focused" but never checks (arms `V`, `S` make an adapter on a visible
  window).
- **Windows VM over SSH**: all four exit 0 and `IsWindowVisible` stays 0 even
  after `SDL_ShowWindow` — session 0 never makes a window visible, so the
  positive control **cannot fire there**. SDL's flag still tracks the order.
- **GitHub windows-latest** (interactive): the panic, measured in
  smk_configurator run 37829232106.
- **Linux**: `accesskit_unix` takes no window — nothing to probe.

Source facts (SDL 3.4.16): `SDL_CreateWindow` without `SDL_WINDOW_HIDDEN` calls
`SDL_ShowWindow` itself at the end (`SDL_video.c:2318–2320`), so the fix moves
that one call past the adapter; `SDL_ShowWindow` fails only on an invalid
window and clears the flag on every driver, offscreen included.

## 3. Design — one lane, `Backends/SDL` only

### 3.1 `Backends/SDL/Sources/SDLBridge/` (`SDLBridge.c`, `include/SDLBridge.h`)

Two new functions, declared next to `mui_window_show` (header line ~244; the
parallel `feat/input-apis` adds lines at 120–230 and 827–1050 of these files —
stay away from them):

```c
// Whether SDL considers the window shown: !(SDL_GetWindowFlags & SDL_WINDOW_HIDDEN)
// (ruling WS-D) — the order seam's reading, valid on every driver.
bool mui_window_is_shown(void *window);
// SDL_GetWindowFromID(id) != NULL (ruling WS-G) — T4's reading that a failed
// opening destroyed its window.
bool mui_window_id_is_open(uint32_t id);
```

`mui_window_create` is **unchanged** (its `hidden` parameter stays; Swift
passes `true`).

### 3.2 `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift` — local to window creation

```swift
/// One step of opening an SDL window, in the order it ran (ruling WS-B),
/// recorded for tests (WS-D). `shown` is SDL's flag (`mui_window_is_shown`).
enum SDLWindowOpeningStep: Equatable {
    case created(shown: Bool)
    case accessKitAdapter(windowShown: Bool)   // read just before the adapter is made
    case shown
    case renderer(windowShown: Bool)
}
```

`SDLPlatform`:

- `var showWindow: @MainActor (UnsafeMutableRawPointer) -> Bool = { mui_window_show($0) }`
  — internal, the test seam (`WS-D`).
- `openSDLWindow`: `mui_window_create(title, w, h, true)` always; then
  `SDLWindow(handle:offscreen:show:)` with `show: hidden ? nil : { [showWindow] in showWindow(raw) }`;
  on a throw, **no** `mui_window_destroy` (ruling `WS-G`: `SDLWindow.init`
  throws only after full initialisation, so its `deinit` has already destroyed
  the window — probe `swift-class-init-throw-deinit.swift`); rethrow. Registration, `applyIcon`, the
  `mui_window_has_input_focus` seed and control-active publishing stay after it,
  in their current order.

`SDLWindow.init(handle:offscreen:show:)` — `show: (() -> Bool)? = nil`:

```
id = …
openingSteps = [.created(shown: mui_window_is_shown(raw))]
#if AccessKit
openingSteps.append(.accessKitAdapter(windowShown: mui_window_is_shown(raw)))
accessKit = AccessKitAdapter(windowID: id, title: …, nativeWindow: mui_window_native_handle(raw))
#endif
if let show {
    guard show() else { throw SDLPlatformError("SDL_ShowWindow") }   // WS-C
    openingSteps.append(.shown)
}
windowRenderer = offscreen ? SDLWindowRenderer(offscreenWidth: …) : SDLWindowRenderer(window: handle)
openingSteps.append(.renderer(windowShown: mui_window_is_shown(raw)))
updateAccessibilityWindowBounds()
```

`private(set) var openingSteps: [SDLWindowOpeningStep]` (internal). The
adapter moves from after the renderer to before it; a renderer throw after the
show leaves a shown window that `SDLWindow`'s `deinit` destroys — the same flash a
renderer failure had at `cd84b0c`, when the window was visible from creation.
`SDLWindow.show()` is unchanged (still "shows a window opened hidden"; it now
always meets an adapter already made). Doc comments: `init(hiddenWindows:)`
gains one sentence ("every window is created hidden and shown after its
AccessKit adapter, ruling `WS-B`; with `hiddenWindows` it is never shown").

### 3.3 `.github/workflows/sdl-gpu-linux.yml` — job `windows`

After "Build, test and replay", a new step:

```yaml
      - name: Launch the SDL demo (ruling WS-E)
        # The visible window with AccessKit that panicked (C11): it must still be
        # running after 8 s. A launch smoke, not a test.
        working-directory: Backends/SDL
        run: |
          $flags = @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB") +
                   @(Get-Content "$env:RUNNER_TEMP\accesskit-flags.txt")
          $bin = (swift build @flags --show-bin-path)
          $p = Start-Process "$bin\MetalUISDLDemo.exe" -PassThru `
                 -RedirectStandardError "$env:RUNNER_TEMP\demo.err" -RedirectStandardOutput "$env:RUNNER_TEMP\demo.out"
          Start-Sleep -Seconds 8
          if ($p.HasExited) {
            Get-Content "$env:RUNNER_TEMP\demo.err"
            Write-Error ("MetalUISDLDemo exited after launch with {0} (0x{0:X8})" -f $p.ExitCode)
            exit 1
          }
          Stop-Process -Id $p.Id
```

The implementer confirms `MetalUISDLDemo.exe` is in the bin path the earlier
`swift build @flags` produced, and that its shaders and `Tests/Fonts` resolve on
the runner (it reads fonts through `#filePath`, which is the checkout there).

## 4. Lanes

**One lane** (Opus): §3.1, §3.2, §3.3, the tests (§5), human checks (§7),
then the record. Files: `SDLBridge.c`, `SDLBridge.h`, `SDLPlatform.swift`,
new `Tests/MetalUISDLTests/SDLWindowShowOrderTests.swift`,
`.github/workflows/sdl-gpu-linux.yml`, `docs/verification/human-checks.md`,
this spec, the decisions doc, `docs/record/86-accesskit-window-show.md`, and in
the Record phase CLAUDE.md/AGENTS.md (one sentence, `WS-B`) and
`docs/record/README.md`. **Off limits** (parallel branches): `MetalUISDLDemo/
main.swift`, `AccessKitAdapter.swift`, `AccessKitTree.swift`,
`MainQueueDrainCheck`, `SDLMainQueueDrainTests.swift`, `SDLMenuInputTests.swift`,
and `SDLPlatform.swift` outside `openSDLWindow` (including its `catch`,
`WS-G`), `SDLWindow.init` and the new enum (`deinit` is read and mutated for
M6, never changed). `feat/input-apis` also edits `SDLWindow.init` (its hunk at `cd84b0c`
lines 257–277): a textual conflict at merge is expected and is the merger's to
resolve keeping `WS-B`'s order.

## 5. Tests — `Backends/SDL/Tests/MetalUISDLTests/SDLWindowShowOrderTests.swift` (new)

`@_spi(Checks) @testable import MetalUISDL`. One helper,
`platform(hidden:)`, arms `armMainRunLoopExitCheck()` on macOS and returns
`SDLPlatform(hiddenWindows: hidden, offscreenRenderers: true)` (offscreen: no
swapchain, so the tests also run over SSH on the VM and under the image's
offscreen driver). Every expected array is a literal written before the run.

**Red-first protocol.** Commit A adds the seam (§3.1, the enum, `openingSteps`,
`showWindow`) recording the **`cd84b0c` order** (create with `hidden`, renderer,
adapter, SDL's implicit show) plus these tests — run them and record the red
ones by name (commit A creates T1/T2's window visible, as `cd84b0c` does: on macOS it
flashes on screen during that one run); commit B applies `WS-B`/`WS-C`.

| # | Test | Asserts | Red before (commit A) | Mutation that must redden it (on commit B) |
|---|---|---|---|---|
| T1 | `aWindowIsCreatedHiddenAndItsAdapterPrecedesTheShow` | `showWindow` stubbed (records its call, returns `true`, shows nothing); `openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false), .shown, .renderer(windowShown: false)]`; stub called once; `isAccessibilityConnected` | **red**: `.created(shown: true)`, adapter after renderer, no `.shown` | M1 (pass `hidden` to `mui_window_create`), M2 (adapter after the show), M4 (renderer before the show) |
| T2 | `aShownWindowBecomesVisibleOnlyAfterItsAccessKitAdapter` | real show; `openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false), .shown, .renderer(windowShown: true)]`; `mui_window_is_shown` true after open; `isAccessibilityConnected`. `.enabled(if: !macOS \|\| env METALUI_RUN_VISIBLE_SDL_WINDOW_TEST == "1")` | **red** on Linux image and macOS-with-env (order); on the Windows runner the process **aborts** (the C11 panic) | M1, M2 |
| T3 | `aHiddenWindowsPlatformNeverShowsItsWindow` | `hiddenWindows: true`; `showWindow` stub `Issue.record`s if called; `openingSteps == [.created(shown: false), .accessKitAdapter(windowShown: false), .renderer(windowShown: false)]`; `mui_window_is_shown` false | **red** only on ordering (adapter after renderer) — the hidden contract itself was already kept | M3 (show regardless of `hiddenWindows`) |
| T4 | `aWindowWhoseShowFailsIsDestroyedAndNotOpened` | stub captures `mui_window_id(raw)` then returns `false`; `openSDLWindow` throws an `SDLPlatformError` whose description starts `SDL_ShowWindow`; `!mui_window_id_is_open(captured)` and `openWindowCount == 0`; with the stub replaced by one answering `true`, a second `openSDLWindow` succeeds and `openWindowCount == 1` | **red**: commit A never calls the stub, so nothing throws | M5 (ignore `show()`'s answer), M6 (`deinit` without `mui_window_destroy`) |

Mutations (each on commit B, from a copy, full `Backends/SDL` suite, then
`git status --short`; name every test reddened):

- **M1** `mui_window_create(…, hidden)` again instead of `true` → T1, T2 (and on
  the Windows runner/console, T2 aborts).
- **M2** move the `#if AccessKit` adapter block after the show → T1, T2.
- **M3** `show:` passed regardless of `hidden` → T3 (T1/T2 unaffected).
- **M4** renderer before the show → T1, T2.
- **M5** `_ = show()` without the guard → T4.
- **M6** `SDLWindow`'s `deinit` without `mui_window_destroy` → T4 (`WS-G`).

M1, M2 and M4 run with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1` on macOS so T2
can redden there, and T2's reddening is also read from the Linux image; each
named reddening says which platform it was read on (`WS-H` item 1).

Also run on commit B: the whole `Backends/SDL` suite on macOS (expect **24 + 88**
from 24 + 84; T2 counts while skipped) and in the Linux image (**24 + 85** from
24 + 81, T2 enabled there); the root suite unfiltered (**2723**, unchanged;
`FR-J no-argument frame: succeeded=` present); `swift build --build-tests` 0
warnings; the fourteen offscreen images 0 px (`compare.sh <scratch> cd84b0c
HEAD`); the existing `SDLPlatformTests`/`AccessKitTests`/`SDLLifecycleTests`
green (they all open hidden windows and now meet the new order).

**Windows.** On the VM over SSH (x64 per CLAUDE.md and ARM64): `Backends/SDL`
`swift test` — T1, T3, T4 red→green; T2 runs but is **blind to the panic in
session 0** (probe `V`), so it proves only the order there. Re-check `query
user`: if a console user is logged on, run `MetalUISDLDemo.exe` and T2 through
the interactive scheduled task at commit A (expect the panic, `0xC0000409`) and
commit B (expect a live window), then unregister the task. Otherwise record
that and rely on the CI step and T2 on the runner (push the branch's CI only
through the orchestrator; this lane does not push).

## 6. Verification checklist

Root: native build + unfiltered `--no-parallel` (2723 in 3 suites, guards
line), default `swift build --build-tests` 0 warnings,
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green, import rules
unmoved, `DemoFrameDeterminismTests` Expected.swift unedited, 0 px images.
`Backends/SDL`: macOS and the `metalui-portable` image (volume
`metalui-sdl-build-accesskit-window-show`). Probe re-run unnecessary unless the
adapter versions change.

## 7. Demo and human checks

**Demo:** no content change. `swift run MetalUISDLDemo` from `Backends/SDL`
opens as before on macOS (visible, key, first frame on the next tick) — the
show now follows the adapter; nothing else is expected to differ.

**Human checks** — new group `WS` in `docs/verification/human-checks.md`
(after `VL`):

- **WS1 (Windows, interactive desktop)**: `MetalUISDLDemo.exe` (AccessKit on)
  opens without a panic; the window appears at 920 × 560, focused, its title
  in the taskbar; Narrator announces the window and reads a button.
- **WS2 (Linux, X11 and Wayland desktop)**: the demo window appears focused at
  its size and draws its first frame; Orca reads the window title.
- **WS3 (macOS, SDL demo)**: the window appears key; VoiceOver (⌘F5) reads
  the window through AccessKit's macOS adapter, now made before the show.
- **WS4 (smk_configurator, after its pin bump)**: the packaged Windows app's
  "Launch the packaged app" CI step passes.

## 8. Deferred (named, with reason and owner)

1. **Show after the first frame** — removes the blank first paint, but changes
   presentation timing on every platform and needs a platform signal. Owner: a
   later SDL-polish item (`WS-F` 1).
2. **Interactive VM run** — no console user on 2026-10-08. Owner: the
   implementer at branch end, else human check WS1 (`WS-F` 2).
3. **Real X11/Wayland desktop** — the image presents nothing. Owner: WS2
   (`WS-F` 3).
4. **The configurator's pin bump** — not edited here. Owner: smk_configurator
   (`WS-F` 4, WS4).
5. **A Linux CI launch** — not added: the image's offscreen driver shows
   nothing natively and Linux's adapter has no order requirement (`WS-A`).
