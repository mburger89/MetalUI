# 86 — AccessKit before the first show: every SDL window created hidden (item C11)

Branch `fix/accesskit-window-show` from `cd84b0c` (master: variable-height
`List` merged, PR #53). **Not a plan task**: item C11 of the gpui-gap priority
list (user request 2026-10-02), an **urgent bug** — every MetalUI SDL app with
the `AccessKit` trait panicked at launch on Windows. Spec
`docs/superpowers/specs/2026-10-08-accesskit-window-show-design.md`; rulings
`WS-A`…`WS-H` in `docs/superpowers/2026-10-08-accesskit-window-show-decisions.md`
(next unused `WS-I`); probes `docs/probes/accesskit-window-show/` (arms `V`,
`H`, `S`, `N`) and `docs/probes/swift-class-init-throw-deinit.swift` (arms
`A`, `B`). Parallel branches at the time: `feat/input-apis` (§81, also edits
`SDLWindow.init` — a textual conflict at merge is expected, keep `WS-B`'s
order), `feat/rich-text` (§83), `feat/controls-looks` (§85).

**Status: implemented and recorded (2026-10-08)** — one lane (design, critic,
implementation, record).

## 0. The failure and its cause (`WS-A`)

Measured on GitHub's `windows-latest` runner (smk_configurator PR #10, run
37829232106, step "Launch the packaged app"): `panicked at
accesskit_windows-0.35.0/src/subclass.rs:168:13: The AccessKit Windows
subclassing adapter must be created before the window is shown (made visible)
for the first time.`, exit `-1073740791` (`0xC0000409`).

At `cd84b0c`, `SDLPlatform.openSDLWindow` passed `hidden` (the platform's
`hiddenWindows`) to `mui_window_create`; without `SDL_WINDOW_HIDDEN`,
`SDL_CreateWindow` shows the window before returning. `SDLWindow.init` then
claimed the renderer and only afterwards made `AccessKitAdapter`, whose Windows
arm calls `accesskit_windows_subclassing_adapter_new` on a visible HWND. The
commit-A seam (§1) reads exactly this on SDL's own flag: `[created(shown:
true), renderer(windowShown: true), accessKitAdapter(windowShown: true)]`.
macOS's adapter documents the same precondition without checking it; Linux's
takes no window.

## 1. Red (`a407cfb`)

The seam, recording `cd84b0c`'s order: `mui_window_is_shown`,
`mui_window_id_is_open` (`SDLBridge`), `SDLWindowOpeningStep`,
`SDLWindow.openingSteps`, `SDLPlatform.showWindow` (unused until the fix);
tests in `Backends/SDL/Tests/MetalUISDLTests/SDLWindowShowOrderTests.swift`
(every window offscreen-rendered, `armMainRunLoopExitCheck()` armed on macOS).

| Test | macOS failure line | Linux image |
|---|---|---|
| T1 `aWindowIsCreatedHiddenAndItsAdapterPrecedesTheShow` | `:58` `openingSteps → [created(shown: true), renderer(windowShown: true), accessKitAdapter(windowShown: true)]`; `:60` `calls.windowIDs == [window.id]` (the show never asked for) | red, same line |
| T2 `aShownWindowBecomesVisibleOnlyAfterItsAccessKitAdapter` | skipped without the env; with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1`: `:74`, the same steps as T1 | red (enabled unconditionally off macOS) |
| T3 `aHiddenWindowsPlatformNeverShowsItsWindow` | `:91` `openingSteps → [created(shown: false), renderer(windowShown: false), accessKitAdapter(windowShown: false)]` (the hidden contract held; only the order was wrong) | red |
| T4 `aWindowWhoseShowFailsIsDestroyedAndNotOpened` | `:114` `thrown as? SDLPlatformError` (nothing thrown) | red |

Linux image at `a407cfb`: `Test run with 85 tests … failed … with 5 issues`
(T1–T4).

## 2. Fix (`91b145d`)

`Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift` only, local to window
creation:

- `openSDLWindow` passes `true` to `mui_window_create` on every platform
  (`WS-B` step 1) and hands `SDLWindow.init` a `show:` closure over
  `showWindow` unless `hiddenWindows`; its `catch { mui_window_destroy }` is
  gone (`WS-G`: every throw in `SDLWindow.init` comes after full
  initialisation, so `deinit` has already destroyed the window).
- `SDLWindow.init(handle:offscreen:show:)`: the AccessKit adapter, then
  `show()` (a `false` answer throws `SDLPlatformError("SDL_ShowWindow")`,
  `WS-C`), then the renderer — the show sits where SDL's own implicit show
  was relative to the renderer, moved past the adapter and nothing else.
- `init(hiddenWindows:)`'s doc comment says every window is created hidden and
  shown after its adapter.
- `.github/workflows/sdl-gpu-linux.yml`, job `windows`: step **"Launch the SDL
  demo (ruling WS-E)"** — starts `MetalUISDLDemo.exe` (AccessKit on, a visible
  window), fails with its exit code and output if it has exited after 8 s,
  else stops it. The bin path is the one the job's `swift build @flags`
  already produced; shaders resolve through `bundledShaderDirectory` and fonts
  through `#filePath`, both the runner's checkout (as `DemoCapture` does).
- `docs/verification/human-checks.md`: group **WS** (WS1–WS4).

No public API (census unmoved, no inventory row), no divergence (reserved
labels 175–176 unused), no `PlatformWindow`/`Platform`/`WindowRenderer`
requirement, no shader, renderer, pixel or demo-content change, no root-package
source change. `SDLWindow.show()` is unchanged and still meets an adapter made
while hidden.

## 3. Mutations (on `91b145d`, `SDLPlatform.swift` restored from a copy after each; `git status --short` empty after each)

Every macOS run is the whole `Backends/SDL` suite with
`METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1` (so T2 runs, `WS-H` item 1); M1, M2 and
M4 also ran the whole suite in CI's Linux image.

| # | Mutation (spelling) | Reddened on macOS | Reddened in the Linux image |
|---|---|---|---|
| M1 | `mui_window_create(…, hidden)` instead of `true` | T1, T2 | T1, T2 |
| M2 | the `#if AccessKit` adapter block moved after the `if let show` block | T1, T2 | T1, T2 |
| M3 | `show: { showWindow(handle) }` regardless of `hidden` | T3 (`:87` the stub's `Issue.record`, `:91` the steps) | — |
| M4 | the `if let show` block moved after the renderer's step | T1, T2 | T1, T2 |
| M5 | `_ = show()` without the guard | T4 (`:114`) | — |
| M6 | `SDLWindow`'s `deinit` without `mui_window_destroy` | T4 (`:118` `!mui_window_id_is_open(captured)`) | — |

No other test reddened under any mutation (each run's only failures are the
named ones).

## 4. Verification (at `91b145d`)

- Root, native build, unfiltered `--no-parallel`: **`Test run with 2723 tests
  in 3 suites passed`** (unchanged from `cd84b0c`); `FR-J no-argument frame:
  succeeded=true` present; 0 `error:`; the only `warning:` SwiftPM's
  `--build-system native` deprecation notice;
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green.
- Root default `swift build --build-tests`: 0 `warning:`.
- `Backends/SDL` on macOS: **24 + 88** (from 24 + 84; T2 counts while
  skipped), all passing; T1–T4 with the env: 4 passed.
- `Backends/SDL` in CI's Linux image (`metalui-portable`, offscreen driver,
  volume `metalui-sdl-build-accesskit-window-show`): **24 + 85** (from
  24 + 81), all passing, T2 enabled and green.
- Pixels: `compare.sh <scratch> cd84b0c HEAD` — controls as recorded, **all
  fourteen images `differing=0`, scene identical**.
- `DemoFrameDeterminismTests` `Expected.swift` unedited; import rules unmoved
  (no root source touched).
- Warnings in the `Backends/SDL` build are pre-existing and outside this
  branch's files: `AccessKitControlsParityTests.swift:83` (unnecessary `try`)
  and `ld`'s Homebrew SDL dylib deployment-target notice.
- Demo on macOS: **not launched** — the lock probe read
  `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`. Human check WS3.

## 5. Windows (`WS-E`)

**Why CI never saw it** (`WS-E`): every SDL test opens `hiddenWindows: true`;
the Windows job's `PortableReplay` and `DemoCapture` never open an
`SDLPlatform` window; `MetalUISDLDemo` was built but never launched; the VM
runs over SSH (session 0), where the probe showed the panic cannot fire; macOS
and Linux adapters check nothing. The `metalui new --cross-platform` starter
creates a visible window too, so every generated cross-platform app had the bug.

**The VM** (`ssh metalui-win`, ARM64): `query user` → "No User exists for *"
(re-checked at the branch end), so the console route (interactive scheduled
task) was not available and neither the demo nor T2's native outcome was run
interactively. Over SSH: the `Backends/SDL` suite at `a407cfb` and `91b145d`
(ARM64, a detached S4U scheduled task after an SSH session dropped
mid-build) — §5a.

### 5a. The VM over SSH (session 0, ARM64; scheduled task `ws-check`, unregistered after)

| Commit | Summary lines | T1–T4 |
|---|---|---|
| `a407cfb` | `Test run with 24 tests … passed`; `Test run with 85 tests in 0 suites failed … with 48 issues` | all four red at the macOS lines: T1 `:58` (`openingSteps`) and `:60` (`calls.windowIDs`), T2 `:74`, T3 `:91`, T4 `:114:21` `thrown as? SDLPlatformError` |
| `91b145d` | `Test run with 24 tests … passed`; `Test run with 85 tests in 0 suites failed … with 43 issues` | all four passed |

The 43 issues common to both runs are the session-0 swapchain failures
CLAUDE.md names (`claiming the window: Could not create swapchain! …
(0x887A0022)` in every test that claims a window renderer, some as
top-level fatal errors in a test's child process); `48 − 43 = 5` is exactly
T1's two issues plus T2, T3 and T4. T2 runs unconditionally off macOS and is
read from SDL's flag (`WS-D`), so it saw the order but not native visibility
— session 0 cannot make a window visible, which is also why the panic cannot
fire there. The VM went unreachable for several minutes mid-run (vmnet, no
route to host) and the `91b145d` build took 1,398 s; both runs completed.

**Owed**: the CI step and T2 on GitHub's interactive runner are the checks
that see the panic; they run on the branch's first push (the orchestrator's).
Human check WS1.

## 6. Deferred (with owner)

1. Show after the first frame (`WS-F` 1) — a later SDL-polish item.
2. The interactive VM run (`WS-F` 2) — no console user on 2026-10-08; human
   check WS1.
3. Real X11/Wayland desktop (`WS-F` 3) — human check WS2.
4. smk_configurator's pin bump (`WS-F` 4) — its owner; human check WS4.
5. A Linux CI launch — not added (`WS-A`, `WS-H`).

## 7. Record phase

CLAUDE.md/AGENTS.md: one sentence in the `PX-` paragraph (`WS-B`).
`docs/record/README.md`: row 86.

## 8. Branch check (adversarial checker, on `3f8c82e`)

- Root after `swift package clean`, native build, unfiltered `--no-parallel`:
  **`Test run with 2723 tests in 3 suites passed`**; `FR-J no-argument frame:
  succeeded=true`; 0 `error:`; the only `warning:` the native deprecation
  notice; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` passed. No file
  under `Sources/`, `Tests/` or `Package.swift` differs from `cd84b0c`, so
  identity, hit testing, accessibility, animation, focus, `List` and text input
  are untouched by construction (the root suite is the same 2723 tests, green).
- `Backends/SDL` on macOS: **24 + 88** passed. CI's Linux image (rebuilt,
  cached): **24 + 85** passed, T2 enabled.
- Root default `swift build --build-tests`: 0 `warning:`. Pixels re-taken
  (`compare.sh <scratch> cd84b0c HEAD`): controls as recorded, all fourteen
  images `differing=0`, scene identical.
- Inventory and undocumented checks print nothing; `MetalUILayout` imports
  only `MetalUICore`, `MetalUIScene` only `MetalUIShaderTypes`; `cmp CLAUDE.md
  AGENTS.md` clean; every ruling id and test name cited in the branch's docs
  resolves.
- Doc fix: `WS-E` item 1 counted 17 `hiddenWindows: true` sites at `cd84b0c`;
  `git grep` reads 16 (15 in `Tests/MetalUISDLTests`, one in
  `MainQueueDrainCheck`; the 17th match is a comment) — corrected.
- Checker mutations, `SDLPlatform.swift`, whole `Backends/SDL` suite on macOS
  with `METALUI_RUN_VISIBLE_SDL_WINDOW_TEST=1`, restored from a copy,
  `git status --short` empty after each:

| # | Mutation (spelling) | Reddened |
|---|---|---|
| X1 | `openSDLWindow` passes `show: nil` always (a non-hidden window is never shown) | T1 (`:58`, `:60`), T2 (`:74`, `:76`), T4 (`:114`) |
| X2 | `accessKit = AccessKitAdapter(…)` moved after the `if let show` block, its `openingSteps` append left before it | **nothing** (24 + 88 passed) |

  **X2 survives**: the `.accessKitAdapter` step is appended on its own line,
  so the C11 order itself — the adapter made on a shown window — can return
  with the recorded order intact. Only Windows sees it: T2 aborting on GitHub's
  interactive runner and the `WS-E` launch step. Tightening (not done here, a
  code change): append the step inside the one function that makes the
  adapter, so moving the construction moves the record with it.
