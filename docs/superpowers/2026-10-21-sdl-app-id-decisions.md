# SDL application id — decisions

Rulings for item XP-G13 (requested by MetalCreator 2026-10-21). Spec:
[`specs/2026-10-21-sdl-app-id-design.md`](specs/2026-10-21-sdl-app-id-design.md). Record: `../record/132-sdl-app-id.md` (Record phase).
Branch `feat/sdl-app-id` from `05bb9a31`. Divergence labels 615-624 reserved: **none taken** (MetalUI-only, class `M`; SwiftUI has no
runtime app-id API, the id is the bundle identifier; gpui sets `app_id` per window in its window options, recollection, unverified).

Prefix **`AP-`**, lettered. **Next unused: `AP-G`.** (Moves in the commit that appends a ruling.)

**Carried.** `SN-` (`launchingSingleInstance(id:)`, the id MetalCreator already passes), `IC-J` (`Options`, headless launch), `PX-I`/`GA-L`
(`Backends/SDL` outside the census), `CB-H`/`mui_cursor_*` (C recorders written in the production path).

## AP-A - Mechanism: `SDL_HINT_APP_ID`, set at normal priority before `SDL_Init`

**Ruling.** Set `SDL_HINT_APP_ID` ("SDL_APP_ID") with `SDL_SetHint` in `mui_platform_init`, immediately before `SDL_Init`, not
`SDL_SetAppMetadataProperty(…IDENTIFIER_STRING)`. **Evidence.** `SDL_hints.h` (3.4.18): the hint "will override
`SDL_PROP_APP_METADATA_IDENTIFIER_STRING`" and "should be set before SDL is initialized"; probe `docs/probes/sdl-app-id-hint.c`, run on macOS:
A1 the hint set before init reads back after init (`com.example.Probe`); A3 with a metadata identifier set afterwards, SDL's metadata read still
answers the hint's value (so the hint wins over the property); A2 with `SDL_APP_ID=env.id` in the environment `SDL_SetHint` returns `0` and the
read-back is `env.id` (the separating arm). The hint is one call, needs no metadata store, and leaves the metadata properties (name, version,
creator) to the app. **Cost if wrong:** a reading of SDL 3.4 where Wayland takes the identifier only from the property would show a generic icon
again; both spellings feed the same `SDL_GetAppID` per the header, and human check AP1 is the real-desktop proof.

## AP-B - The environment variable stays an override (no `SDL_HINT_OVERRIDE`)

**Ruling.** Normal priority, so a user or packager exporting `SDL_APP_ID` beats the code (probe A2). `docs/packaging.md` keeps the env recipe as
the override note. **Cost if wrong:** a packager cannot correct a wrong built-in id without a rebuild (the opposite choice).

## AP-C - API: `SDLPlatform.Options.applicationID: String?`; defaulted by `launchingSingleInstance(id:)`

**Ruling.** A public field, default `nil`, new defaulted `init` parameter `applicationID:` placed last (source compatible). Effective id:
explicit `applicationID` if usable, else (only through `launchingSingleInstance(id:forwarding:options:)`) that `id`, else nothing is set
(today's behaviour byte for byte, no hint call). The launcher fills a `nil` field before `SDLPlatform(options:)`, so `.unavailable` claims
default too and an explicit option always wins. A `SingleInstance` handed in through `Options.singleInstance` directly carries no id and
defaults nothing. The trait-off stub declares the same names (as `SN-A` item 2). The application id applies to the whole process (SDL's hint
is global), not per window. **Cost if wrong:** an app wanting an id different from its single-instance id sets the option; one wanting
no id sets neither.

## AP-D - Light validation, never a trap; no `SDL_APP_NAME`

**Ruling.** A value that is empty, whitespace-only or holds a NUL byte is **ignored** (nothing set, no log): an empty hint would blank SDL's
default, a NUL would truncate silently in the C string. No reverse-DNS check (SDL does none; the doc says a desktop id should equal the
`.desktop` basename / `StartupWMClass`, e.g. `com.example.MyApp`). `SDL_APP_NAME` is **not** paired: it is a human title for volume mixers and
inhibitor lists, not the grouping key, and defaulting it from a reverse-DNS id would show that id to the user. Deferred, owner none.

## AP-E - Order pinned by a C recorder; macOS and Windows documented

**Ruling.** `mui_platform_init(const char *app_id)` (NULL = untouched) bumps two process-global counters at the call site in order: hint
sequence then init sequence; `mui_app_id_*` read-backs give the last value set, the set count and `hint_seq < init_seq` for the last call. SDL is
refcounted and other tests leave it initialised, so `SDL_GetHint` after init is not proof of "before"; the recorder is. Every path funnels
through `mui_platform_init` (`init(options:)`, the two convenience inits, the SPI one, `.headless`, offscreen), so one call site covers all.
AppKit untouched (bundle id). On macOS and Windows SDL's own platforms do not group by it: macOS uses the bundle, Windows the AppUserModelID
(`SDL_SetWindowsAppUserModelID` is not built, deferred, owner none); the option is accepted and harmless there. **Cost if wrong:** none beyond a no-op on those platforms.

## AP-F - Critic pass: probe header corrected; pins read the recorder, never the hint

**Ruling.** The probe header described A3 as "metadata read when no hint is set", contradicting AP-A (the hint wins); it now states A3 as run and carries
the recorded output (both runs re-executed byte for byte at the critic pass, matching AP-A). Pins 1, 2, 4 compare the recorder's last value (what MetalUI
passed), not `SDL_GetHint`, so a runner exporting `SDL_APP_ID` cannot redden them. Rejected: a Swift-side recorder (the C call site is the only place that
orders hint before init), `SDL_HINT_OVERRIDE` (AP-B). No SwiftUI claim, no shader, no platform requirement, no pixel or demo change: nothing else found.
