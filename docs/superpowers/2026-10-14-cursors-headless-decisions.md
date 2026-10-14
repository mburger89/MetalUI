# Image cursors and a headless SDL launch — decisions

Rulings for items S4 (image cursors) and S8 (supported headless launch), MetalCreator's SDL-port gap 8
and XP-G9. Spec: [`specs/2026-10-14-cursors-headless-design.md`](specs/2026-10-14-cursors-headless-design.md).
Record: `../record/116-cursors-headless.md`. Probe: `docs/probes/swiftui-image-cursor.swift` (arms `I0`-`I7`,
output in its header).

Prefix **`IC-`**, lettered. **Next unused: `IC-R`.** (Moves in the commit that appends a ruling.)
Branch `feat/image-cursors-headless` from `fb9a7e42`. Reserved divergence labels 465-474: 465 used
(`IC-C`), 466-474 unused.

**Carried items.** `CI-A`, `CI-AC` (the image cursor adds an enum case: migration note owed), `CI-H` item 8
(SDL's system cursors), `CI-J` (send on change only), `CI-S` (re-send on re-entry), `AI-E`/`AI-F` (the alpha
rule), `TF-C`/`TF-E` (`offscreenRenderers`), `WS-B` (hidden windows), `HT-X` 1 (a new requirement owes the
headless platform an honest answer), `DG-C`/`DG-L` (guides).

## IC-A - The seam gains one case, `PlatformPointerStyle.image(PlatformCursorImage)`

**Finding.** `PlatformPointerStyle` is a closed public enum; `CI-AC` ruled that an image cursor adds a case.
`MetalUIPlatform` may import `MetalUICore` and `MetalUIScene`, and `ImageTexture` (a final `Sendable` class)
lives in `MetalUIScene`, so the seam can carry the texture itself and no renderer or backend invents a second
copy of the pixels.

**Ruling.**
1. `case image(PlatformCursorImage)`. `PlatformCursorImage` is a public `Sendable, Hashable` struct:
   `texture: ImageTexture`, `scale: Float`, `hotSpot: (x: Float, y: Float)` in **points from the top-left**
   (already resolved and clamped by `Window`'s side, `IC-C`), read-backs `pixelWidth`, `pixelHeight`,
   `pointWidth`, `pointHeight`. A **public** initialiser (a third-party conformer's tests build one; the
   `Backends/SDL` package cannot reach `package` API). Doc comments owe the `CI-AC` sentence.
2. **Equality and hash are the texture's identity** (`ObjectIdentifier`, the struct holds the texture, so
   the id cannot be reused while a value lives), `scale` and the hot spot - never the bytes. Two bitmaps with
   equal pixels are two cursors; one bitmap rebuilt every frame is one (`IC-F`).
3. Migration note (`docs/migration.md`): an outside `PlatformWindow` conformer's exhaustive `switch` over
   `PlatformPointerStyle` owes `.image` or `default:`; `PlatformWindow` and `Platform` gain no requirement.

**Rejected.** A second seam call `setCursorImage(_:)` (a conformer that forgets it silently shows the arrow;
a case fails to compile where a `switch` is exhaustive); carrying `ImageBitmap` (it is in `MetalUI`, which the
platform module cannot import); a byte-hashed key (hashing 64 KB per resolve to avoid a cache miss).

**Cost if wrong.** An outside conformer edits one `switch`.

## IC-B - The source is an `Image`, SwiftUI's spelling

**Ruling.** `public static func image(_ image: Image, hotSpot: UnitPoint) -> PointerStyle`, SwiftUI's two-argument
spelling (probe arms `I1`-`I7` compile it), `hotSpot` required.
MetalUI's `Image` wraps exactly one `ImageBitmap` (`Image(decorative:scale:)`, `Image(_:scale:label:)`; no
asset names, no `systemName`, `Image.swift`), so **there is no other Image kind to refuse**: every `Image` is
accepted. `resizable()`, `interpolation`, `scaledToFit` and an accessibility label are ignored - the cursor is
the bitmap at its own size (probe `I5`: SwiftUI's `.resizable()` changes nothing). The style stores a
`Sendable, Hashable` value built from the `Image` (texture identity, scale, `UnitPoint`), not the `Image`
(which is not `Hashable`). A guard (`anImageHasNoSystemNameOrAssetInitialiser` already exists) keeps the claim
honest: a future non-bitmap `Image` kind must revisit this ruling (it would add a rasterize-first path).

**Cost if wrong.** A new `Image` kind compiles into `.image` and the lowering traps on a missing bitmap; the
guard above is the tripwire.

## IC-C - Size, scale and hot spot (probe-measured), clamping is a divergence

**Evidence** (`swiftui-image-cursor.swift`, positive control `I0`): the cursor's **point size is
`pixels / scale`** (`I1` 16 px scale 1 and `I4` 32 px scale 2 both 16 pt); the hot spot is **`UnitPoint x
point size`, top-left origin** (`I1` (0,0), `I2` (8,8), `I3` (16,16)); `.resizable()` is inert (`I5`).

**Ruling.**
1. `PlatformCursorImage.pointWidth = pixelWidth / scale` (and height); `hotSpot = unit x point size`.
   `scale` is `Image.scale` (`Float`, finite and positive, `SA-J`).
2. **A hot spot outside `[0, 1]` clamps per axis** to the image (an SDL cursor whose hot spot lies outside its
   surface is refused by `SDL_CreateColorCursor`; AppKit accepts it). SwiftUI's own answer for `(2, -1)` read
   `(32, 16)` (`I6`): x unclamped, y not understood; MetalUI does not copy a reading it cannot explain.
   **Divergence 465** (class: platform-safety clamp; pinned by `anImageCursorHotSpotOutsideTheUnitSquareClamps`).
3. A bitmap larger than 256 px on a side is passed to the platform unchanged; **a platform that cannot make
   it leaves the current cursor** (SDL: `SDL_CreateColorCursor` fails on the offscreen driver and on
   backends with a size limit, like `mui_set_system_cursor`'s failure today). `Window` never refuses.
4. Hi-DPI: the point size is what the app asked; the pixels are the app's. Supplying a 2x bitmap with
   `scale: 2` is the 2x-display recipe (`IC-H`).

**Cost if wrong.** An app that relied on SwiftUI's out-of-range hot spot reads a clamped one: documented.

## IC-D - AppKit: an `NSCursor` from the premultiplied bitmap

**Ruling.** `AppKitCursor.cursor(for:)` gains the `.image` arm: an `NSImage` of size
`(pointWidth, pointHeight)` holding **one `NSBitmapImageRep` of the texture's pixels wrapped as stored**
(premultiplied, never re-premultiplied: `AI-E`), `NSCursor(image:hotSpot:)` with the hot spot in AppKit's
top-left image coordinates (what the probe's `NSCursor.hotSpot` printed). AppKit scales for 2x displays from
the rep's pixel size. A per-window `[PlatformCursorImage: NSCursor]` dictionary caches the result, bounded at
**16 entries, least recently used out** (an `NSCursor` needs no destroy; the bound keeps a long-running app
that makes a cursor per frame from growing; an entry the host view currently holds is never the one evicted).
`setPointerStyle` is unchanged (`pointerCursor`, `cursorUpdate`).

**Cost if wrong.** A flipped hot spot lands a cursor one image-height off: pinned by a pixel-and-hot-spot read
back from `NSCursor`.

## IC-E - SDL: `SDL_CreateColorCursor`, un-premultiplied, cached, destroyed

**Ruling.**
1. **Pixels**: `SDLIcon.straightRGBA(texture)` (the one un-premultiply, `AI-F`; reused, never re-inlined) into
   an `SDL_PIXELFORMAT_RGBA32` surface, `SDL_CreateColorCursor(surface, hotX, hotY)` with the hot spot in
   **surface pixels** (`hotSpot x scale`, rounded, clamped to the surface).
2. **Hi-DPI**: when `scale` is an integer >= 2 the primary surface is the bitmap box-downsampled by `scale`
   (the point-size image) and the bitmap is added as an alternate (`SDL_AddSurfaceAlternateImage`, as the
   icon's alternates, `AI-B`), so SDL picks by display scale; any other scale uses the bitmap as the one
   surface. (SDL3 cursors are in 1x pixels; without this a 2x bitmap would draw twice its point size.)
3. **Cache**: `SDLWindow`/`SDLPlatform` own one table `PlatformCursorImage -> cursor handle`, **bounded at 8
   entries, least recently used out**; a cursor is destroyed (`SDL_DestroyCursor`) when it leaves the table
   **unless it is the one SDL currently shows** (destroying the current cursor makes SDL fall back; it is
   destroyed at its next replacement). The cursor is process-global (`CI-S`), so the table is the
   **platform's**, not a window's. **All entries are destroyed when the last window closes and on platform
   deinit.**
4. **Set only on a change** is `Window`'s (`IC-F`); the SDL side also skips `SDL_SetCursor` for the cursor it
   already shows.
5. **Recorder** (a test cannot see the pointer): the C bridge exports counters read by the tests -
   `mui_cursor_created_count()`, `mui_cursor_destroyed_count()`, `mui_cursor_live_count()`, and the last
   creation's `mui_cursor_last_width/height/hot_x/hot_y/alternate_count` plus `mui_cursor_last_pixel(index)`.
   They record in the production path (no test-only branch). System cursors keep `mui_set_system_cursor`.

**Cost if wrong.** A leaked cursor is a few KB per bitmap; the bound and the counters pin it.

## IC-F - Sent on a change; identity decides

**Ruling.** `Window` already resolves a `PointerStyle` through the one ranking and sends only when it
changes (`CI-H` item 7, `CI-J`). `PointerStyle.Kind` gains `.image(ImageCursorSpec)`; because
`PlatformCursorImage` compares by texture identity, **an `Image` rebuilt from the same `ImageBitmap` every
frame is the same style** and sends once; a different bitmap sends once. `CI-S`'s re-send on re-entry is
unchanged and carries the same value, so the platform caches serve it.

## IC-G - `.shape(_:eoFill:size:)` is carried, not built

**Finding.** Cheap in outline (rasterize through `MetalUIPath` into an `ImageBitmap` at the display scale),
but three things are unprobed: SwiftUI's `size:` default and whether it is points or a proposal, which
colour the filled shape takes (`.shape` has no colour parameter), and how the hot spot is placed. A probe arm
with a separating arm for each is a half-day of its own, and `MetalUIPath` is `package` API with
device-pixel coverage that needs the display scale at the seam.

**Ruling.** Not built. **Carried** (spec 9, owner: a follow-up item after the image cursor lands, when an app
asks): an app that needs a shape rasterizes it to an `ImageBitmap` and passes `.image`. The doc comment on
`PointerStyle` keeps `shape` in the "not offered" sentence (`CI-A`). Adding it later is additive (a new static
over the same `.image` case: no new enum case).

## IC-H - SDL's hand and zoom cursors are the app's to supply

**Ruling.** `CI-H` item 8 stands (system cursors only for the statics: grab -> move, zoom -> arrow). **No
art is bundled** (a licensed 32 px hand and magnifier are a design asset and the licences list,
`THIRD-PARTY-NOTICES.md`, would grow for two icons). The recipe, documented in `PointerStyle`'s doc comment,
`docs/api-overview.md` and `docs/guides/input.md` (a compiled mirror, `DG-C`), is:
`#if` the platform or branch on `SDLPlatform` presence, and give `.pointerStyle(.image(handImage, hotSpot:))`
a 1x and a 2x bitmap (`scale: 2`) for the cases where SDL's move cursor is wrong. Human check **IC1**.

## IC-I - The headless platform records the image honestly (`HT-X` 1)

**Ruling.** `HeadlessPlatformWindow.setPointerStyle` already appends every `PlatformPointerStyle`; the new
case is recorded as the value `Window` sent, and `TestWindow.pointerStyle` (the last) returns it. Its
read-backs (`pixelWidth`, `pointWidth`, `hotSpot`, `texture` identity) are the `PlatformCursorImage` ones; no
new `TestWindow` API. The headless platform draws no pixels, so "honest" is the record.

## IC-J - S8: an explicit public option type, `SDLPlatform.Options`

**Finding.** The only route is `@_spi(Checks) SDLPlatform(hiddenWindows:offscreenRenderers:)` (`TF-E`, `WS-B`).
`hiddenWindows` is public already. `offscreenRenderers` is the jargon: it means "render every window into an
offscreen target instead of a swapchain, so frames build with no presented frame".

**Ruling.** `public struct SDLPlatform.Options: Sendable, Hashable` with `hidesWindows: Bool` and
`rendersOffscreen: Bool` (named for what they do), statics `.default` (both false) and **`.headless` (both
true)**, and **`public convenience init(options: Options) throws`**. `init(hiddenWindows:)` stays and equals
`Options(hidesWindows:)`. The trait-off unavailable stub gains the same `Options` and `init(options:)`
(guard 1.6's reason). No video-driver is chosen: the driver is the environment's (`SDL_VIDEO_DRIVER=offscreen`
in the Linux image, Mesa llvmpipe or WARP on a runner with a software adapter); `.headless` is the part MetalUI
owns: no shown window, no swapchain.

**Rejected.** Making the SPI init public as is (jargon, and a Bool pair spelling that cannot grow); an
environment variable *alone* (an implicit mode that a test cannot construct and the docs cannot link to).

**Cost if wrong.** A third option needs a field with a default: `Options` is a struct, additive.

## IC-K - The environment variable is a named convenience on `Options`

**Ruling.** `SDLPlatform.Options.headlessIfRequested(environment: [String: String] = ProcessInfo...)` returns
`.headless` when `METALUI_SDL_HEADLESS` is **exactly `"1"`** (the project's convention) and `.default`
otherwise. It is not read by `SDLPlatform.init`: the app opts in by writing
`SDLPlatform(options: .headlessIfRequested())`, so one binary serves a developer and CI, and a library user
never has a window hidden by an inherited variable. The `environment:` parameter makes it a pure function a
test calls with a dictionary.

## IC-L - The SPI initialiser stays, forwarding, not deprecated

**Ruling.** `@_spi(Checks) init(hiddenWindows:offscreenRenderers:)` forwards to `init(options:)`. It is
SPI: its callers are this repository's checks and MetalCreator's pre-ruling smoke test, and an SPI cannot
carry a useful `@available(deprecated)` warning for them (an `@_spi` import already signals "unsupported").
It keeps working so nothing breaks; `MainQueueDrainCheck` keeps calling it as the compile guard that it does.
A new check uses `Options`.

## IC-M - The headless smoke-test recipe and its test

**Ruling.** `docs/testing.md` gains "A CI smoke test of the real window" and `docs/packaging.md`'s CI section
links it: `SDLPlatform(options: .headless)`, `App(platform:textSystem:)`, a `.task` that records and calls
`app.terminate()` (or `platform.stop()`), exit 0; on Linux `SDL_VIDEO_DRIVER=offscreen` (Xvfb also works), on
Windows WARP on the runner. A new check executable **`HeadlessLaunchCheck`** in `Backends/SDL` is that recipe
verbatim, written against public API with a **plain import** (the compile is the guard that `Options` is
reachable without SPI), and is run by a test that launches it in a process and reads `task ran=true`. It runs
ungated in the Linux image.

## IC-N - Guides

**Ruling.** `docs/guides/input.md` gains the image-cursor block and `docs/guides/cross-platform.md` the
headless block. The cursor block is Swift and compiled (`GuideMirrors*.swift`, `DG-C`: it builds an `Image`
from a generated `ImageBitmap` and reads `TestWindow.pointerStyle`); the SDL launch block is a `text` fence
(`DG-L`).

## IC-O - The cursor table is pure Swift, so its pins run on every driver

**Finding (critic).** Tests 13-15 (reuse, LRU bound, destroy on last close) were gated on a driver that creates
a cursor; the Linux image sets `SDL_VIDEO_DRIVER=offscreen`, where creation may fail, so the pins would be
skipped exactly where they must run and a skipped test cannot be red.

**Ruling.** The bounded LRU table (`IC-E` 3) is `SDLCursorTable<Handle>` in `MetalUISDL`: generic, with
`create`/`destroy` closures, the "currently shown" exemption and `removeAll()` passed in. `SDLPlatform` instantiates
it with the C bridge; tests 13-15 instantiate it with a counting fake and are **ungated**. The C recorder is
read only by tests 11, 12, 17. Same shape as `SurfaceTargetTable` (`MV-`).

## IC-P - The headless check is bounded by iterations, the test by a child-process deadline

**Ruling.** `HeadlessLaunchCheck` loops a fixed number of run-loop iterations (never a clock) and prints
`task ran=<bool>`; the launching test owns the child `Process`, waits on it, and on a generous deadline
terminates **that child only** and fails. A mutant that never runs the task therefore reddens (`task ran=false`)
rather than hanging the suite (the 12-minute hang rule).

## IC-Q - The recipe stops from the display-link tick; the check is declared in `Backends/SDL` only

**Finding (lane A).** A `.task` can run in the first frame, which on macOS is before `platform.run()` starts;
`platform.stop()` from the task then sets `running = false` and `run()` sets it true again, so the first build
of `HeadlessLaunchCheck` ran to its 200000-iteration bound (`task ran=true iterations=200000`). The root
manifest declares no `MainQueueDrainCheck` either, so the spec's "declared in both manifests" is only
`Backends/SDL/Package.swift`: its executables are another package's, which is why `Options` had to be public.

**Ruling.** The recipe and the check set a flag in the task and call `stop()` from `startDisplayLink`'s tick
(also the iteration bound, `IC-P`): `iterations=1` on macOS. `docs/testing.md` says why.
