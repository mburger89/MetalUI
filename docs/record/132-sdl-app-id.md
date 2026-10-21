# 132 - SDL application id (XP-G13: `SDLPlatform.Options.applicationID`)

Branch `feat/sdl-app-id` from `05bb9a31`. Not a plan task: item XP-G13 of the gpui-gap list, requested by MetalCreator 2026-10-21. Spec
`docs/superpowers/specs/2026-10-21-sdl-app-id-design.md`; rulings `AP-A`...`AP-F` in `docs/superpowers/2026-10-21-sdl-app-id-decisions.md`.
Divergence labels 615-624 reserved: **none taken** (class `M`, `Backends/SDL`, outside the census; no SwiftUI claim, no SwiftUI probe). The SDL probe is
`docs/probes/sdl-app-id-hint.c`. One lane, `Backends/SDL` only. Demo: none. Human check: group `AP`, `AP1`.

## 1 The defect

Linux shells match a window to its `.desktop` entry by Wayland `app_id` / X11 `WM_CLASS`. SDL3 takes it from `SDL_HINT_APP_ID`, which must be set before `SDL_Init`;
MetalUI set none, so MetalCreator's window showed a generic icon and grouped by executable name.

## 2 What landed

`SDLPlatform.Options.applicationID: String?` (new last `init` parameter, default `nil`). `mui_platform_init(const char *app_id)` calls `SDL_SetHint(SDL_HINT_APP_ID, id)`
at normal priority immediately before `SDL_Init` (`AP-A`; the `SDL_APP_ID` environment variable still overrides, `AP-B`, probe arm A2). `launchingSingleInstance(id:)` fills a `nil`
field with its `id`, so an explicit option wins (`AP-C`); a `SingleInstance` passed straight through `Options` defaults nothing. `Options.usableApplicationID` ignores an empty,
whitespace-only or NUL-bearing value, never a trap (`AP-D`); no `SDL_APP_NAME`. The trait-off stub mirrors the field (guard `1.6b`'s fixture gained `applicationID`).
C recorders `mui_app_id_set_count/last/hint_precedes_init` are written in the production path and order the hint before `SDL_Init` by sequence number (`AP-E`), because SDL is
refcounted and a read-back after init cannot prove "before". macOS and Windows: accepted, no visible effect (bundle, AppUserModelID). `docs/packaging.md` section 3 rewritten.

## 3 Pins and mutations (`SDLAppIDTests`, 5 tests, 7 cases, one serialized suite, `armMainRunLoopExitCheck()` armed)

Red on arrival (field and recorders stubbed, the hint not set): tests 1, 2 and 4 failed (8 issues); tests 3 and 5 are negative pins that pass on a stub by construction and were
proven by mutation only. Mutations, each on the committed tree, restored from a copy, full `Backends/SDL` run:

- Hint call moved after `SDL_Init` (C): reddened `explicitOptionIsSetBeforeInit`, `singleInstanceIdDefaultsTheApplicationID` (spec also predicted 4: it does not read the order, corrected).
- Launcher fill removed: `singleInstanceIdDefaultsTheApplicationID` only (3 issues).
- Launcher overwrites unconditionally: `explicitOptionBeatsTheSingleInstanceId` only.
- No id set but a fallback passed: `neitherLeavesTheHintUntouched` and the three `unusableValuesAreIgnored` cases.
- `usableApplicationID` validation dropped (Swift): two `unusableValuesAreIgnored` cases (`"  "`, `"a\0b"`; the C side already drops `""`).

## 4 Deferred

`SDL_APP_NAME` (`AP-D`), Windows AppUserModelID (`AP-E`), per-window ids, defaulting from a bare `SingleInstance` (`AP-C`), the shell's real behaviour (`AP1`, `O3`).
