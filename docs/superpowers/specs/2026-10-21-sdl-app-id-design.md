# SDL application id - design (XP-G13)

Item XP-G13 (MetalCreator, 2026-10-21; not a plan task). Branch `feat/sdl-app-id` from `05bb9a31`; labels 615-624 reserved, none taken;
decisions `docs/superpowers/2026-10-21-sdl-app-id-decisions.md` (`AP-`). Record `docs/record/132-sdl-app-id.md` (Record phase).
Lanes: **one** (Backends/SDL only, a few dozen lines).

## 1. Problem

Linux shells match a window to its `.desktop` entry by Wayland `app_id` / X11 `WM_CLASS`. SDL3 reads `SDL_HINT_APP_ID` (set before init).
MetalUI sets none (`docs/packaging.md` section 3), so MetalCreator's window shows a generic icon and groups by executable name. Gap, not
a SwiftUI feature: no SwiftUI claim, no SwiftUI probe; the SDL probe is `docs/probes/sdl-app-id-hint.c` (AP-A).

## 2. Inventory

- `SDLBridge.c:1231 mui_platform_init` (hint `QUIT_ON_LAST_WINDOW_CLOSE`, then `SDL_Init`); `SDLBridge.h:201`; sole caller `SDLPlatform.swift:59`
  (`init(options:)`, which every other init forwards to).
- `SDLPlatformOptions.swift` `Options` and its trait-off stub (`SDLPlatform.swift` ~1492, with the stub `launchingSingleInstance`).
- `SingleInstance*.swift:251 launchingSingleInstance` (fills the option).
- Other `SDL_InitSubSystem` sites (`SDLBridge.c:203` replay harness, `SDLGPUDevice.swift:93`) are not platform launches: untouched.

## 3. API (`MetalUISDL`, trait `SDL`, class M, outside the census)

`Options.applicationID: String?` + `init(..., applicationID: String? = nil)` (last); doc comment on the `.desktop`/`StartupWMClass`
match, env override, macOS/Windows no-op. `launchingSingleInstance` fills a `nil` field with `id`. Stub mirrors both. Inventory: none
(Backends/SDL outside it, `GA-L`); `closeout-inventory-check.sh`/`closeout-undocumented.sh` must still print nothing.

## 4. Implementation

`mui_platform_init(const char *app_id)`: if non-NULL and usable (AP-D, validated in Swift: `Options.usableApplicationID`, internal), `SDL_SetHint(SDL_HINT_APP_ID, id)`
then record; then the existing hint and `SDL_Init`. Swift passes `withCString`. C recorders `mui_app_id_set_count`, `mui_app_id_last`,
`mui_app_id_hint_precedes_init` (written in the production path, `mui_cursor_*` style, AP-E).

## 5. Tests (Backends/SDL `SDLAppIDTests`, one `.serialized` suite; each `SDLPlatform` creation arms `armMainRunLoopExitCheck()`; deltas, never absolutes)

Each is red on arrival (the field does not exist; written first against a stub that records nothing).

1. `explicitOptionIsSetBeforeInit`: `Options(hidesWindows: true, applicationID: "com.example.A")`: set-count +1, last == value, `hint_precedes_init`.
   Mutation: move the `SDL_SetHint` after `SDL_Init` (reddens 1, 2, 4); drop the set (all of 1, 2, 4).
2. `singleInstanceIdDefaultsTheApplicationID`: `launchingSingleInstance(id:forwarding:[], options: .headless)` with a unique id: last == id.
   Mutation: remove the launcher's fill (reddens 2 only).
3. `neitherLeavesTheHintUntouched`: `.headless`: set-count delta 0. Mutation: always set (e.g. to ""): reddens 3.
4. `explicitOptionBeatsTheSingleInstanceId`: launcher with `options.applicationID = "X"`, `id = "Y"`: last == "X". Mutation: launcher overwrites
   unconditionally (reddens 4 only).
5. `unusableValuesAreIgnored` (arguments: "", "  ", "a\u{0}b"): delta 0, no trap. Mutation: drop the validation (reddens 5).
6. `anEnvironmentOverrideWins` is NOT a pin (the process environment is the runner's); covered by probe arm A2 and the doc.
7. Plain-import typecheck guard `AP.1` in Backends/SDL tests is not needed (public field, no hidden init); trait-off stub compiles: guard `1.6b`'s
   style fixture gains `Options(applicationID:)` and `launchingSingleInstance` unchanged; mutation: remove the stub field, the guard reddens.

Expected counts: Backends/SDL +5 tests (macOS and Linux image), root suite +1 guard fixture line only (4092 unchanged tests, guard count
unmoved if the line extends 1.6b; the lane re-measures).

## 6. Demo, docs, human checks

No demo. `docs/packaging.md` section 3: drop "does not set one", show `Options(applicationID:)`, the launcher default and the `SDL_APP_ID`
override note (retitle: no longer "unverified" for the setting, still for the shell). Mention in `docs/testing.md` only if it lists `Options`
(it does not today: checked with grep at the lane). Human check **AP1** in `docs/verification/human-checks.md`: GNOME Wayland and an X11
session, window shows the desktop entry's icon and groups under the entry (also `SDL_APP_ID=...` override and no id set = old behaviour).

## 7. Deferred

`SDL_APP_NAME` pairing (AP-D, owner none); Windows AppUserModelID (AP-E, owner none); per-window ids (SDL's hint is process-wide); defaulting from
a `SingleInstance` passed directly (carries no id; AP-C).
