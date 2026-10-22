# Small items (IH-K, SN-L, P3c) — decisions

Rulings for round 2 item 9 of the gpui-gap list (user request 2026-10-21; **not a plan task**). Prefix `SM-`. **Next unused: `SM-E`.**
Spec: [`specs/2026-10-22-small-items-design.md`](specs/2026-10-22-small-items-design.md). Record: `../record/147-small-items.md`.
Branch `feat/small-items` from `1c53976d`. Divergence labels reserved 765-774: none taken. Public API: none. Lanes: none.

Sources of truth. SwiftUI: none of the three carries a SwiftUI-facing claim (no cancellable image decode, no activation API, no renderer
detail), so no SwiftUI probe; gpui consulted for none. Local: stb_image 2.30 as compiled by `Sources/CStbImage/CStbImage.c`, SDL
`release-3.4.16` (the Linux image's tag) source, the repo's records §117, §118, §122. All three items are ruled **carried, each with a
measurement**; the outcome the brief allows.

## SM-A — Image decode cancellation (IH-K) stays carried: the callback can only cancel the read phase, and a JPEG returns a partial image

**Question.** Can `stbi_load_from_callbacks` with a read callback that reports EOF after a cancel flag give `DecodedImage` a useful
cancellation (nil, no partial image, no further reads, uncancelled decode byte-identical)?

**Measured** (`docs/probes/stb-callback-eof.c`, `stb-phase-split.c`; 2048x2048 RGBA, stb with CStbImage's defines):
1. *Premature EOF.* PNG: `NULL` at every cut point in the IDAT stream (reads stop at the cut). **JPEG: a full-size image built from zeros once
   the header is read** (cut after 3 reads of 128 bytes: `IMAGE`, 384 of 1,362,069 bytes read). The truncation rule ("a truncated decode is nil,
   never a partial image") is therefore held by stb for PNG only; a callback design would have to check the flag after the call and free
   the result — buildable.
2. *Never cancelled:* the callback path is byte-identical to `stbi_load_from_memory` on both formats (the separating arm).
3. *Where the time is.* In-memory source, 2048²: read 0.57 ms vs decode 20.63 ms (PNG, 2.7 %), read 0.27 ms vs 33.23 ms (JPEG, 0.8 %). A
   cancel lands only in the read callback; inflate, IDCT, colour conversion and the output allocation (the 450 MB case) are one uninterruptible
   stb call. For PNG all IDAT is read before inflating, so a cancel after the last read saves nothing.

**Ruling.** Not built; `IH-K` stands, now with its measurement. The only lead (`IH-K`'s) is measured: it saves at most 3 % of a decode of
bytes already in memory, which is the only source `DecodedImage` has (`init(contentsOfFile:)` reads the whole file first, `IH-M`). The real
bound on a decode remains `Limits` (`IH-N`, refuses from the header before stb allocates). **Cost if wrong.** An app that decodes huge
in-range images cannot stop one; the owner is an app that asks, and the shape then is a chunked file reader checking `Task.isCancelled`
between 1 MiB reads plus a before/after check (a Swift-side async wrapper, additive, class `M`), not stb's callback; or a vendored-C change
(a progress hook in `stbi__parse_entropy_coded_data` and the inflate loop), which touches vendored code and `VENDORED.md`.

## SM-B — Forwarding an activation token (SN-L) is not buildable: SDL's raise ignores the environment

**Question.** Can the second instance's `XDG_ACTIVATION_TOKEN` travel in the message and let the primary raise under Wayland's focus-stealing
prevention?

**Measured** (`docs/probes/sdl-activation-token.sh`, SDL 3.4.16 source). `XDG_ACTIVATION_TOKEN` is read in **three** places: a new window's
initial show, `Wayland_GetActivationTokenForExport` and `SDL_OpenURL`'s child environment. **`Wayland_RaiseWindow` does not read it**: it calls
`Wayland_activate_window`, which requests a *new* token from the compositor with the last input serial of a seat (`SDL_waylandwindow.c:2331-2377`).
X11 references neither the variable nor `DESKTOP_STARTUP_ID`. SDL exposes no API to hand a token to an existing window; the
`xdg_activation_v1` manager is internal to SDL (`d->activation_manager`), so applying a token to the primary's surface would need our own
Wayland registry binding (a `libwayland-client` dependency, the Linux image builds SDL with `-DSDL_WAYLAND=OFF`, no compositor to test).

**Ruling.** Carried. A wire field with no consumer would be an untestable promise (`SN-L` already carried it to check SI4); the message
format stays version-less (magic, count, strings: unchanged) so no old/new split is introduced for nothing. `SN-H`'s statement ("SDL3 honours the
token in its own environment only") is **refined**: its own environment at an initial show or export, never at a raise. **Cost if wrong.**
On Wayland a second launch flashes the primary's taskbar entry (`SDL_FlashWindow`, `SN-H`) instead of raising; X11, Windows and macOS are
unaffected. **Owner.** Check SI4 on a real Wayland session, then either an SDL patch (upstream: `Wayland_RaiseWindow` should consume the
env token as the initial show does) or a Wayland binding of our own. The cheapest unblocked step is that upstream request.

## SM-C — D-Bus activation (`org.freedesktop.Application`) stays carried

**Ruling.** Not built. `Activate`/`Open` on the session bus needs a D-Bus client in the primary (SDL's internal `SDL_DBus_*` is not public API;
libdbus or sd-bus is a new system dependency that CI images and apps would carry), a `DBusActivatable=true` `.desktop` entry (packaging, outside
the library, `docs/packaging.md`) and a bus-name election duplicating the flock election (`SN-A` rejects two truths). The `flock` + socket
path already handles every launch that reaches the executable; D-Bus activation only adds launch from a desktop file by the shell without
exec'ing a second process, which the second-launch forwarder already emulates. **Cost if wrong.** A Linux shell that activates through D-Bus
only (rare for apps with a normal `Exec=`) starts a second process, which then forwards over the socket: same result, one process spawn.
**Owner.** None until an app ships a `DBusActivatable` desktop file.

## SM-D — R8 coverage with a shader tint (P3c) stays carried: record §118's reading holds and the shader toolchain is absent here

**Measured / cited.** Record §118 §7 (`34491ff4`, bracket pan, debug): tinted pixels are **6 %** of rasterized pixels (5,361 of 87,450 per drawn
frame); "what remains is `CoverageRasterizer` itself, which R8 does not reduce"; R8 would quarter texture bytes (RGBA 4 B to 1 B per pixel) and
drop 450 K tinted pixels per 84 frames, i.e. about 5.4 K pixels (21 KB RGBA) per frame on the fixture whose steady-state pan costs 0 raster
work (`PN-B`). `RasterCache.lastTexturesMade` is 0-2 per frame in the pan and shadow-drag fixtures (`PF-G`). Nothing in the fourteen images
changed since. **Re-taken here: not**, because the build precondition fails: this machine has no `shadercross` or `dxc` (`which` finds
neither, `METALUI_SHADERCROSS` unset), and `Backends/SDL/Shaders/compiled/*.{spv,msl,dxil,json}` are checked-in blobs built from `replay.hlsl`
(`docs/packaging.md` 4a); a new `MUIImage` sampling mode needs `shaders.metal` and `replay.hlsl` edited identically (`TE-AD`), blobs
regenerated and the SDL replay-parity harness re-run on Metal, Vulkan (lavapipe) and D3D12 (Windows, CI only).

**Ruling.** Carried. Build only when a profile names tint or texture bytes: today the win is under 6 % of raster work and a quarter of a
few KB per frame, against a two-renderer shader change that cannot be regenerated or verified locally. **Cost if wrong.** A path/shadow-heavy
scene keeps 4x texture memory for CPU rasters (a 1024² overscan raster: 4 MiB vs 1 MiB). **Owner.** `PN-D`'s note; first step a bytes-per-frame
counter (`RasterCache.lastTintedPixels` times 3 B already gives the saving) on a real scene before any shader work.
