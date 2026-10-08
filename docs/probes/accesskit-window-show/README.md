# Probe: AccessKit's subclassing adapters against an already-visible SDL window

Evidence for rulings `WS-A`, `WS-B` and `WS-D`
(`docs/superpowers/2026-10-08-accesskit-window-show-decisions.md`, record §86).

`probe.c` opens one SDL 3.4.16 window per process and creates AccessKit's
(accesskit-c 0.23.0) platform adapter on it, in one of four orders:

| arm | order | role |
|-----|-------|------|
| `V` | created **visible**, then the adapter | positive control — `SDLPlatform` at `cd84b0c` |
| `H` | created hidden, adapter, `SDL_ShowWindow` | the fix's order |
| `S` | created hidden, `SDL_ShowWindow`, adapter | separating arm — visibility *at adapter time* decides, not the creation flag |
| `N` | created hidden, adapter, never shown | `SDLPlatform(hiddenWindows: true)` |

`visible_*` is the native predicate (Windows: `IsWindowVisible`, the one
`accesskit_windows-0.35.0/src/subclass.rs:168` panics on; elsewhere SDL's
flag); `sdl_shown_*` is `!(SDL_GetWindowFlags & SDL_WINDOW_HIDDEN)`.

Run: `zsh docs/probes/accesskit-window-show/run.sh` (macOS, repository root,
after `python3 Backends/SDL/scripts/fetch-accesskit.py`); on Windows copy
`probe.c` and `run.ps1` to one directory and run
`powershell -ExecutionPolicy Bypass -File run.ps1` (UTM VM paths by default).

## Recorded output (2026-10-08)

### Windows 11 ARM64 UTM VM, over SSH (session 0, no console user logged on)

```
arm V: exit 0 (0x00000000)
  stdout: arm=V visible_at_adapter=0 sdl_shown_at_adapter=1 adapter=yes visible_after=0 sdl_shown_after=1
arm H: exit 0 (0x00000000)
  stdout: arm=H visible_at_adapter=0 sdl_shown_at_adapter=0 adapter=yes visible_after=0 sdl_shown_after=1
arm S: exit 0 (0x00000000)
  stdout: arm=S visible_at_adapter=0 sdl_shown_at_adapter=1 adapter=yes visible_after=0 sdl_shown_after=1
arm N: exit 0 (0x00000000)
  stdout: arm=N visible_at_adapter=0 sdl_shown_at_adapter=0 adapter=yes visible_after=0 sdl_shown_after=0
```

**The positive control does not fire here**: in session 0 a window never
becomes natively visible (`IsWindowVisible` reads 0 even after
`SDL_ShowWindow`), so AccessKit's check never trips. The instrument is blind
over SSH; SDL's own flag (`sdl_shown_*`) still records the order. This is why
the order tests read SDL's flag (`WS-D`) and why the Windows check that can
see the panic is GitHub's runner (an interactive session — the panic below was
measured there) or the VM's console route, which needs a logged-on user (`query
user` printed "No User exists for *" on 2026-10-08).

### GitHub Actions windows-latest (x64), the measured failure (not this probe)

smk_configurator PR #10, run 37829232106, step "Launch the packaged app":

```
thread '<unnamed>' panicked at accesskit_windows-0.35.0/src/subclass.rs:168:13:
The AccessKit Windows subclassing adapter must be created before the window is shown (made visible) for the first time.
```

then exit `-1073740791` (`0xC0000409`, the fail-fast a panic across the C ABI
aborts with). That app opens its window through `SDLPlatform()` (not hidden).

### macOS 27 (arm64), Homebrew SDL3, screen locked

```
arm V: exit 0
  stdout: arm=V visible_at_adapter=1 sdl_shown_at_adapter=1 adapter=yes visible_after=1 sdl_shown_after=1
arm H: exit 0
  stdout: arm=H visible_at_adapter=0 sdl_shown_at_adapter=0 adapter=yes visible_after=1 sdl_shown_after=1
arm S: exit 0
  stdout: arm=S visible_at_adapter=1 sdl_shown_at_adapter=1 adapter=yes visible_after=1 sdl_shown_after=1
arm N: exit 0
  stdout: arm=N visible_at_adapter=0 sdl_shown_at_adapter=0 adapter=yes visible_after=0 sdl_shown_after=0
```

macOS's subclassing adapter **accepts a visible window** (arms V and S): its
"before the view is shown or focused for the first time" is documented
(`accesskit_macos-0.27.0/src/subclass.rs:126`) but not checked — so macOS, where
MetalUI's SDL backend is developed, could never have shown the bug.

### Linux

Not run: `accesskit_unix::Adapter::new` takes no window at all
(`accesskit_unix-0.23.0/src/adapter.rs:133`), so there is no order to probe.

## Sources read (not run)

- `accesskit_windows-0.35.0/src/subclass.rs:150–170` — `SubclassingAdapter::new`
  panics `if IsWindowVisible(hwnd)`; doc: "This must be done before the window
  is shown or focused for the first time."
- `accesskit_winit-0.29.0/src/lib.rs:134,197` — "use `with_visible` to make the
  window initially invisible, then create the adapter, then show the window";
  panics if visible. Examples `simple.rs:161–166` do exactly that.
- `accesskit-c-0.23.0/examples/sdl/hello_world.c:396–410` — AccessKit's own SDL
  example: `SDL_CreateWindow(..., SDL_WINDOW_HIDDEN)`, the adapter, then
  `SDL_ShowWindow`.
- SDL `release-3.4.16` `src/video/SDL_video.c:2310–2321` —
  `SDL_FinishWindowCreation` calls `SDL_ShowWindow(window)` itself when
  `SDL_WINDOW_HIDDEN` is absent: creating hidden and showing explicitly is the
  same call, moved later. `:3405–3435` — `SDL_ShowWindow` returns `false` only
  for an invalid window, and clears `SDL_WINDOW_HIDDEN` through
  `SDL_EVENT_WINDOW_SHOWN` on every driver, offscreen included
  (`src/events/SDL_windowevents.c:83–88`).
