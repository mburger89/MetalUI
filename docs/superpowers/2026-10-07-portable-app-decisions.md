# A MetalUI app on Linux and Windows — decisions

Rulings for portable image decoding, `.task`, and a consumable SDL backend
(user request 2026-10-02, an item of the gpui-gap priority list; **not a plan
task**; motivated by the SMK configurator's next port step, Linux and Windows).
Spec: [`specs/2026-10-07-portable-app-design.md`](specs/2026-10-07-portable-app-design.md).
Record: `../record/80-portable-app.md`.

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-task.swift`](../probes/swiftui-task.swift) (**new**; arms
  `X0`…`X17`, run three times, byte-identical) — SwiftUI's `.task`.
- [`../probes/swiftui-bundle-image.swift`](../probes/swiftui-bundle-image.swift)
  (**new**; arms `I0`…`I2`, `B0`…`B9`; `B9`, an asset-catalog entry in the
  same bundle, is the positive control `PX-R` added) — SwiftUI's
  `Image(_:bundle:)` over loose PNG resources.
- [`../probes/image-decoder-parity/`](../probes/image-decoder-parity/) (**new**;
  `compare.py`'s header) — the portable decoder against ImageIO and against
  what SwiftUI draws, on 22 generated files and the configurator's 66 icons.
- [`../probes/swiftpm-traits-sdl/run.sh`](../probes/swiftpm-traits-sdl/run.sh)
  (**new**; arms `M1p`…`L5`, `N1`) — SwiftPM: a backend behind package traits,
  with and without `pkgConfig:`, on macOS and in two Linux images.
- [`../probes/swift-task-modifier-isolation.swift`](../probes/swift-task-modifier-isolation.swift)
  (**new**) — SwiftUI's closure type stored in a scope and started with
  `Task.immediate`, at Swift 6 language mode.
- The lifecycle probe [`../probes/swiftui-lifecycle.swift`](../probes/swiftui-lifecycle.swift)
  (`K1`, `K2`; `A1`…`A6`, `T1`, `T4`) and the runtime probes behind `LC-L` and
  `SV-H` ([`../probes/swift-main-actor-task-loop.swift`](../probes/swift-main-actor-task-loop.swift),
  [`../probes/swift-main-queue-drain-nested.swift`](../probes/swift-main-queue-drain-nested.swift)).

Where SwiftUI has no answer (decoding bit-identity across platforms, how a
package ships a backend, a C library with no pkg-config) the ruling says so;
gpui is named as a comparison where it has one, never as evidence.

Prefix **`PX-`**, lettered. **Next unused: `PX-W`.** (This line moves in the
commit that appends a ruling; read the last `## PX-` heading.)

Branch `feat/portable-app` from `359444e` (master: port gaps, medium, merged,
PR #50). Baseline at `359444e`, measured by this design session: `swift build
--build-system native --build-tests` then `swift test --build-system native
--no-parallel`, unfiltered: **2630 tests in 3 suites**, the `FR-J no-argument
frame: succeeded=true` line present, the only `warning:` SwiftPM's
`--build-system native` deprecation notice. `docs/divergences.md`: **103 live,
next label 137**. Human checks: groups A–W (next X).

**Carried items.** `LC-L` (the deferral this branch ends) and its owner trail:
`SV-H` (the SDL main-queue drain landed; item 5 left `.task` ownerless).
`LC-B`…`LC-J` and `LC-V` (the lifecycle machinery `.task` is built on: one
transparent `LifecycleScope`, presence by membership, events after the build
under `StateDispatch`, three buckets in reverse pre-order, ghost parking,
window close, headless frames run nothing). Divergence 120 (a legacy
decoration after a lifecycle modifier does not compile) — `.task` inherits it.
`TE-AL`/`TE-AR` (`ImageBitmap` is MetalUI's `CGImage`; the premultiply lives
once, in `ImageTexture(width:height:straightRGBA:)`), `AI-E` (the alpha rule:
`ImageTexture` is premultiplied sRGB, never re-premultiplied), `TE-AF` (image
textures cached per identity). `PC-A`/`PC-B` (the manifest's two lists),
`XP-A`/`XP-C` (the framework and its frame on every platform), `RS-D`
(`SDLWindowRenderer`), `AX-A` (AccessKit fetched, not vendored), `SC-C`
(`--cross-platform` needs `--local` — this branch removes the need), `SC-H`
(a refused scaffold name is a measured build failure), `SC-I` (the pinned
default dependency). No decisions doc's "Carried…" section names image
decoding off Apple; spec §9 of the plan task 11 image work named "no decoder
is vendored off Apple" as its deferral, with no owner.

---

## PX-A — Scope: what this branch builds, what it defers

**Ruling.** Build, in three lanes (`PX-M`):

1. **Portable image decoding** (`PX-B`…`PX-E`): PNG and JPEG decoded by one
   vendored C decoder on every platform, bit-identical, premultiplied sRGB;
   `ImageBitmap(contentsOfFile:)` on every platform, `ImageBitmap(data:)`,
   and a bundle-resource initialiser (the configurator's `MG-10`, first half).
2. **`.task(name:priority:file:line:_:)` and
   `.task(id:name:priority:file:line:_:)`** (`PX-F`, `PX-G`) on every
   `ElementGroup`, built on the lifecycle machinery, proved under the test
   harness and under `SDLPlatform`.
3. **A consumable SDL backend** (`PX-H`…`PX-J`): the backend's library targets
   declared by the root package behind two package traits, so a package that
   depends on MetalUI **by URL** builds an SDL app on Linux and Windows;
   `metalui new --cross-platform` without `--local`; docs that say exactly
   what a consumer installs.

**Deferred, each named in spec §9 with a reason and an owner:**

- Colour management of tagged images (gAMA, iCCP, cHRM): samples are taken as
  sRGB (divergence **138**, `PX-C`). Owner: none — needs a portable ICC
  engine (lcms2 or equivalent) vendored the same way.
- `Image(_ name:bundle:)` / asset catalogs, `@2x`/`@3x` variant selection,
  `.renderingMode(.template)` and tinting (the second half of `MG-10`).
  Owner: none (`PX-E` says why the SwiftUI spelling is not offered).
- `.task(name:executorPreference:priority:…)` (SwiftUI's macOS 26.4 variants
  taking a `TaskExecutor`). Owner: none.
- Frames under SDL's offscreen video driver (an offscreen renderer per window
  when `SDL_VIDEO_DRIVER=offscreen`), which would ungate the SDL lifecycle
  tests 10.2/10.3 and this branch's modifier-level SDL `.task` check (`PX-L`).
  Owner: none.
- The SDL backend's public declarations in the public-API census (`PX-K`).
  Owner: none.
- Building a generated cross-platform app on **Windows** in CI (the backend
  itself keeps building and testing there). Owner: none; human check X4.
- GIF, WebP, TIFF, HEIC and BMP off Apple (`PX-C` item 5). Owner: none.

**Reasoning.** The configurator needs exactly: its per-scheme icon PNGs on
Linux and Windows, one cancellable background loop per pane (a device
monitor), and a manifest that names MetalUI by URL and still gets an SDL
window. Everything deferred is additive over what is built.

**Cost if wrong.** Each deferral is additive; none changes a spelling built
here.

## PX-B — The decoder: stb_image 2.30, vendored as `CStbImage`

**Ruling.**

1. **stb_image v2.30** (`stb_image.h`, sha256
   `594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3`,
   fetched 2026-10-07 from `nothings/stb` master) is vendored as a C target
   **`CStbImage`** in the manifest's **every-platform list** (`PC-A`: it
   imports nothing; no system dependency; C99). Licence: the file's own dual
   licence, **MIT or public domain (Unlicense)** — recorded in
   `Sources/CStbImage/LICENSE` (the text from the end of `stb_image.h`) and
   `VENDORED.md` (version, URL, hash, the defines below, the date).
2. Compiled once, in `Sources/CStbImage/CStbImage.c`, with
   `STB_IMAGE_IMPLEMENTATION`, `STBI_ONLY_PNG`, `STBI_ONLY_JPEG`,
   `STBI_NO_STDIO` (MetalUI reads the bytes), `STBI_NO_LINEAR`,
   `STBI_NO_HDR`, `STBI_NO_FAILURE_STRINGS`, **`STBI_NO_SIMD`** (`PX-O`
   item 4) and **`STBI_MAX_DIMENSIONS 16384`** (the largest texture side both renderers guarantee; a file
   claiming more is refused before any allocation). Its public header
   `include/CStbImage.h` declares only what MetalUI calls:
   `stbi_load_from_memory`, `stbi_load_16_from_memory`,
   `stbi_is_16_bit_from_memory`, `stbi_info_from_memory`,
   `stbi_image_free`. **No `unsafeFlags`** (SwiftPM refuses them in a URL
   dependency); a warning the default build system raises is silenced inside
   `CStbImage.c` with `#pragma clang diagnostic` (`CFreeType`'s precedent),
   so `swift build --build-tests` stays at 0 warnings on both build systems.
3. `MetalUI` depends on it and imports it **`internal import CStbImage`** —
   no C type crosses the public surface.

**Alternatives measured or weighed.** lodepng (zlib licence, C++, PNG only —
JPEG would be a second library); libspng (BSD-2, needs zlib — a second
vendored library); Wuffs (Apache-2.0, memory-safe by construction, but a
multi-megabyte generated file and a heavier API for two formats); a Swift
decoder (inflate, Adam7, palette and 16-bit are cheap; baseline and
progressive JPEG are not). stb_image is one header for both formats and the
parity table (`PX-C`) was measured with it.

**Cost if wrong.** stb_image is **not hardened against malicious input**
(its README says so; past CVEs are heap overreads on crafted files). `PX-D`'s
pre-checks (CRC, IEND, EOI, the dimension cap) and its truncation and
bit-flip tests shrink the surface but do not remove it. If a crafted file
crashes it, the replacement is Wuffs behind the same Swift function
(`decodeImage(_:)` in `ImageDecoding.swift`) and the same tests — one target
and one file.

## PX-C — The rule: one decoder on every platform, bit-identical, sRGB samples

**Ruling.**

1. **PNG and JPEG decode through `CStbImage` on every platform, macOS
   included.** The bytes an `ImageBitmap` holds for a given file are the same
   on macOS, Linux and Windows (pinned by literal pixels in
   `MetalUICrossPlatformTests`, which Linux and Windows CI run).
2. **16-bit samples are rounded to 8 bits**, `(v × 255 + 32767) / 65535`,
   after decoding at 16 bits (`stbi_load_16_from_memory`). stb's own 8-bit
   path truncates (`v >> 8`) and differs from ImageIO by up to 2
   (rgba16: 29 of 252 bytes); rounding matches ImageIO exactly (rgba16 and a
   64×64 random 16-bit RGBA: 0 of 16384 bytes differ).
3. **Straight-alpha samples are premultiplied by `ImageTexture(width:height:
   straightRGBA:)`** (`TE-AR`: the one premultiply), so the `AI-E` alpha
   rule holds by construction. Measured: ImageIO's premultiply equals it on
   every alpha (64×64 random RGBA: 0 of 16384 bytes differ).
4. **Colour profiles are ignored**: iCCP, gAMA, cHRM and sRGB chunks and JPEG
   ICC markers do not change a sample; every sample is taken as sRGB.
   Measured differences from ImageIO — **which is exactly what SwiftUI draws**
   (`Image(nsImage:)` via `ImageRenderer`: 0 bytes differ from ImageIO on all
   22 files): a gAMA 1/1.8 PNG, max 19; a Display P3 iCCP PNG, max 87; JPEG
   (IDCT and chroma upsampling are a decoder's own), max 2. **Divergence
   138.** Every untagged or sRGB-tagged 8-bit PNG (RGBA, RGB, gray 1/4/8,
   gray+alpha, palette+tRNS, Adam7) and every 16-bit PNG measured: 0 bytes
   differ — including all 66 configurator icons (44 untagged, 22 sRGB-tagged).
5. **Other formats on Apple only**: a file whose signature is neither PNG
   (`89 50 4E 47 0D 0A 1A 0A`) nor JPEG (`FF D8 FF`) is handed to ImageIO
   when `canImport(ImageIO)` (the decode `ImageBitmap(contentsOfFile:)` did
   at `359444e`, colour-managed), and is `nil` elsewhere. This keeps a macOS
   app that loads a TIFF, GIF or HEIC working; it is documented as
   platform-dependent in the initialiser's doc comment.

**Reasoning.** MetalUI pins its frame byte-for-byte across platforms
(`XP-C`); an image whose bytes depend on the platform would be the first
platform-dependent input to that frame. Keeping ImageIO for PNG/JPEG on macOS
would buy colour management on macOS only, and make the same app's icons
differ between its macOS and Linux builds. The measured cost of the portable
rule is confined to colour-managed files and JPEG's last bit.

**Cost if wrong.** An app with Display P3 or gamma-tagged PNGs sees shifted
colours on macOS (they were converted at `359444e`). The fix is the deferred
colour management (`PX-A`), additive; the workaround is to export assets as
sRGB, which is what every asset pipeline the configurator uses does.

## PX-D — Corrupt input: `nil`, never a trap

*(Amended by `PX-O`: the pre-checks are internal functions tested directly; the JPEG check walks segments; `STBI_NO_SIMD`; an `Int32.max` bound.)*

**Ruling.** Before stb sees the bytes, MetalUI checks, in Swift
(`ImageDecoding.swift`):

1. **PNG**: the signature, then every chunk's length fits the buffer and its
   **CRC-32 matches**, and an `IEND` chunk is present. Any failure → `nil`.
   (libpng — so ImageIO — tolerates a bad CRC on an ancillary chunk; MetalUI
   refuses any. Measured: ImageIO returns a **partial image** for a file cut
   in half and for a flipped bit inside `IDAT`; stb alone already returns
   `nil` for both; the CRC check makes the second independent of what the
   flipped bit does to the inflate stream.)
2. **JPEG**: an EOI marker (`FF D9`) follows the first SOS marker (`FF DA`);
   bytes after EOI are allowed. A truncated JPEG has no EOI → `nil` (stb
   alone pads a truncated entropy stream with zeros and returns an image).
   A JPEG has no checksum: a flipped bit inside its entropy-coded data may
   decode to wrong pixels — as in every JPEG decoder; documented.
3. Then stb: a `NULL` result, a width or height of 0 or above 16384, or a
   size whose `width × height × 4` overflows `Int` → `nil`.
4. A missing file, a directory, an unreadable file or empty data → `nil`.

`ImageBitmap(width:height:rgba:)` keeps its traps (a wrong byte count is a
programming error, not input).

**Cost if wrong.** A file ImageIO used to show partially now shows nothing —
a migration note (`ImageBitmap(contentsOfFile:)` on macOS), not a
divergence: SwiftUI has no file initialiser to diverge from.

## PX-E — API: three failable initialisers on `ImageBitmap`

**Ruling.**

1. `public init?(contentsOfFile path: String)` — now on **every platform**,
   PNG and JPEG through `PX-C`, other formats per `PX-C` item 5. Doc comment
   rewritten (no "macOS only", no "colours converted to sRGB").
2. `public init?(data: Data)` — the same decode from bytes in memory (a
   downloaded or embedded image). `Data` because `MetalUI` already traffics
   in it (`Transferable`).
3. **`public init?(resource name: String, withExtension ext: String? = "png",
   subdirectory: String? = nil, bundle: Bundle)`** — resolves
   `bundle.url(forResource:withExtension:subdirectory:)` and decodes it,
   **once per resolved path per process**: a lock-protected cache keyed by
   the resolved file path holds the decoded bitmap (or the `nil`), so every
   frame that asks gets the **same `ImageTexture` identity** and a renderer
   uploads it once (`TE-AF`). Bundle resources are immutable while the
   process runs; the cache is never evicted (a bounded set of resources).
   MetalUI-only (map class `M`).
4. **`Image(_ name: String, bundle: Bundle?)` is not offered.** Probe
   `swiftui-bundle-image.swift`: SwiftUI's `Image(_:bundle:)` does **not**
   read loose PNG files in a bundle — `B0` (an 8×6 px `plain.png`), `B2`
   (`@2x`/`@3x` siblings), `B4` (the extension written), `B5`/`B6` (a
   subdirectory) all size 0×0, while the instrument control `I0`
   (`Image(nsImage:)` of the same file) sizes 8×6 and AppKit's own
   `bundle.image(forResource:)` finds the file and all three reps (`I1`).
   The positive control `B9` (an 8×6 image set compiled by `actool` into an
   `Assets.car` in the same Resources directory) sizes 8×6 — the named lookup
   works in this harness, so `B0`–`B7` are the lookup refusing loose files.
   SwiftUI's spelling means "an asset catalog entry"; a MetalUI `Image(_:
   bundle:)` reading loose files would be the same words with a different
   meaning. A "Not offered" row names it and points at `ImageBitmap(resource:
   …)` plus `Image(_:scale:label:)`.

**Reasoning.** The configurator's `IconLoader` is exactly
`Bundle.module.url(forResource:withExtension:subdirectory:)` plus a
hand-written decode cache (`MG-10`'s workaround); item 3 is that, in the
framework, with the texture-identity benefit its hand-written cache also got.

**Cost if wrong.** If an app needs eviction (resources replaced at run time),
it uses `init?(contentsOfFile:)`, which never caches.

## PX-F — `.task`: SwiftUI's semantics on the lifecycle machinery

**Ruling.**

1. **Spelling** (SwiftUI's current one; the SDK's `View.task` declarations):
   ```swift
   extension ElementGroup {
       public func task(name: String? = nil, priority: TaskPriority = .userInitiated,
                        file: String = #fileID, line: Int = #line,
                        @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void)
           -> LifecycleScope<Self>
       public func task<T: Equatable>(id value: T, name: String? = nil,
                                      priority: TaskPriority = .userInitiated,
                                      file: String = #fileID, line: Int = #line,
                                      @_inheritActorContext _ action: sending @escaping @isolated(any) () async -> Void)
           -> LifecycleScope<Self>
   }
   ```
   A closure written in an element is **main-actor isolated** (`X2`: on the
   main thread before and after every suspension) and may call a
   `@MainActor` model synchronously; a closure formed in a nonisolated
   context runs where its isolation says (`@isolated(any)`). Measured
   feasible at Swift 6 language mode: a closure capturing a non-`Sendable`
   value and calling a `@MainActor` method, stored in a scope through an
   `@unchecked Sendable` box and started with `Task.immediate(name:priority:)
   { await box.run() }`, compiles without a diagnostic and runs its prefix
   synchronously (probe `swift-task-modifier-isolation.swift`).
2. **The scope is a `LifecycleScope`** (`LC-B`): one more `LifecycleWrite`
   case, layout- and identity-transparent, no `Element` hook, `Handlers`
   unchanged, `MC-A`/`MC-C`/`MC-P` untouched; divergence 120 applies to it.
3. **Start is an appearance event.** In the appearances bucket, at the scope's
   place in reverse pre-order (`X1`: an inner `onAppear` first; `X1b`: an inner
   task first; `X9`: children before parents, interleaved with `onAppear` by
   modifier order), the body **starts synchronously and runs until its first
   suspension inside the drain** (`X15`: inside `layoutSubtreeIfNeeded`;
   `X1`: its pre-`await` write is in the **first** draw). A write the prefix
   makes is presented in the first frame by `LC-E`'s settle build, exactly
   like an `onAppear` write. The prefix runs under
   `StateDispatch.dispatching(to: owner)`; everything after the first
   suspension runs as an ordinary main-actor job (outside dispatch; a
   `@State` write there resolves as any async write does, divergence 71).
4. **Cancel is a disappearance event** at the scope's place (`X4`: task inner,
   cancel before the outer `onDisappear`; `X4b`: task outer, after it), so an
   if/else swap starts the new branch's task before cancelling the old one
   (`X14b`). Cancellation never waits for the task to finish.
5. **An id change is a change event** at the scope's place among `onChange`
   actions (`X12`/`X12b`): **cancel the old task, then start the new one**,
   in one step (`X5`, with `withTaskCancellationHandler`'s `onCancel` as the
   instrument). The id is compared by `==` once per build (`X6`: the same
   value restarts nothing; `X7`: a rebuild with the id unchanged restarts
   nothing, and a change after the task finished starts it again).
6. **Presence is the lifecycle's** (`LC-C`): hidden and transparent content
   starts its task (`X8`); a modifier on a group starts once while the group
   has content and is cancelled when it empties (`X10`).
7. **Under a removal transition the cancel is parked until the ghost ends**
   (`X16`), and content re-inserted mid-removal **keeps its task** — neither
   cancelled nor restarted (`X17`) — `LC-H` unchanged.
8. **Window close cancels every running task**, with the `onDisappear`s, in
   reverse pre-order (`LC-J` item 1; `X11`: the hosting view leaving its
   window cancels, `close()` with the host retained does not — MetalUI's close
   is `X11`'s second case). **App quit cancels nothing** (`LC-J` item 3).
   **A headless `renderFrame` starts nothing** (`LC-J` item 4).
9. **Priority** passes through; the default is `.userInitiated` (`X3`: raw
   25; `.low` 17, `.high` 25, `.background` 9; the id form likewise).
   **Name**: `name ?? "View.task @ \(file):\(line)"` — SwiftUI's default
   string (`X13`), passed where the runtime offers named tasks (`PX-G`).
10. **The store** (`LC-D`): the running task lives in the entry's box, which
    a build that keeps the key carries forward; it is not a `StateTable`
    entry or slot (the seven reserved names unmoved). Work stays `LC-M`'s
    `3K` for K scopes, 0 with none.

**Refuted and corrected.** The lifecycle probe's reading of `K2` ("`.task(id:)`
starts the new task, then cancels the old one", copied into `LC-L`) rested on
the **resumption** log line of the old task, which runs later; `X5`'s
`onCancel` instrument shows the cancel call **precedes** the new start. The
Record phase corrects `LC-L`, the lifecycle probe's reading note and record
§76 where they copy it (spec §8.3).

**Reasoning.** Every ordering answer the probe gave is the existing lifecycle
order applied to one more event kind; building `.task` as a `LifecycleWrite`
case makes that true by construction instead of by a second ordering.
gpui's comparison (not evidence): `cx.spawn` tasks are owned by the entity and
dropped (cancelled) with it — the same "owned by presence" shape.

**Cost if wrong.** If a probe arm was misread, the fix is a bucket move inside
`LifecycleStore.endFrame` — one place, pinned by tests 3.1–3.13.

## PX-G — Start strategy: `Task.immediate` where the runtime has it

**Ruling.**

1. The start helper uses **`Task.immediate(name:priority:operation:)`**
   when `#available(macOS 26.0, *)` — always true off Apple — so the prefix
   runs synchronously (`PX-F` item 3).
2. **On macOS 14–25** (MetalUI's floor is 14) it falls back to
   `Task(priority:operation:)`, unnamed: the body starts on the next turn of
   the main queue, **after** the frame that made the scope present. Its
   pre-`await` write is presented one frame late. **Divergence 137.**
3. An internal test seam (`TaskStart.forcesDeferredStart`, `@testable`
   only) selects the fallback so both branches are pinned on the macOS 27
   machine this repo is tested on (tests 3.1 and 3.16).

**Cost if wrong.** On macOS 14–25 a task that writes before its first `await`
shows one frame of the pre-write state. No macOS 26+ or Linux/Windows build
is affected.

## PX-H — The consumable SDL backend: root targets behind two package traits

**Ruling.**

1. **The backend's four library targets are declared by the root package**,
   in the every-platform list (`PC-A`: they import no Apple framework except
   `SDLPlatform+AppKit.swift`'s `#if canImport(AppKit)`), **with their sources
   left where they are**, by `path:`: `CSDL` (`Backends/SDL/Sources/CSDL`),
   `CAccessKit` (`…/CAccessKit`), `SDLBridge` (`…/SDLBridge`), `MetalUISDL`
   (`…/MetalUISDL`). Root products: **`MetalUISDL`** and **`SDLBridge`** (the
   C API Backends/SDL's replay tools and tests call). Measured (`N1`): a root
   target whose `path:` lies inside a nested package directory builds on both
   build systems with 0 warnings, and the nested package can depend on the
   root by path and use the product. `SDLWindowRenderer.bundledShaderDirectory`
   (found by `#filePath`) is unchanged: the file did not move, and a URL
   consumer's checkout holds `Backends/SDL/Shaders/compiled`. (Amended by
   `PX-P`: an executable-adjacent `MetalUISDLShaders` is tried first, so a
   built app can be moved.)
2. **Two package traits**, neither enabled by default:
   - **`SDL`** — the SDL3 backend: enables `SDLBridge`'s `CSDL` dependency,
     its `METALUI_SDL` C define and its `SDL3` link; `MetalUISDL`'s Swift code
     is `#if SDL`.
   - **`AccessKit`** (`enabledTraits: ["SDL"]`) — the screen-reader bridge
     (`AX-A`): enables `MetalUISDL`'s `CAccessKit` dependency and AccessKit's
     link libraries, encoded in the manifest per platform (macOS: `accesskit`,
     frameworks AppKit, Foundation, CoreFoundation, `objc`, `c++`; Linux:
     `accesskit`, `m`; Windows: `accesskit` and the eleven system libraries
     today's manifest lists). `AccessKitAdapter.swift`/`AccessKitTree.swift`
     are `#if AccessKit`; under `SDL` alone `SDLPlatform`'s accessibility
     requirements are honest no-bridge implementations (the tree is accepted
     and dropped; `onAccessibilityRequest` never fires).
   Measured (`M5`, `L5`): target-dependency conditions, cSettings defines and
   linker settings all take `.when(traits:)`, and a trait is a Swift
   compilation condition in the declaring package.
3. **No `pkgConfig:` on either system library.** Measured (`M1p`, `M2p`): the
   default build system asks pkg-config about **every** `.systemLibrary
   (pkgConfig:)` in the graph whether or not anything uses it, warning in the
   declaring package **and in every consumer** ("couldn't find pc file for
   accesskit", Homebrew's "prohibited flag(s): -Wl,-rpath"). Without it: 0
   warnings on macOS (both build systems), in a consumer, and in a plain
   `swift:6.4-noble` with no SDL installed (`M1`–`M3`, `L1`). The module maps
   keep `link "SDL3"` / `link "accesskit"`; headers and libraries come from
   the compiler's default paths or from `-Xcc -I… -Xlinker -L…` (`PX-I`).
4. **Without the trait the product is not silent**: `MetalUISDL` declares,
   under `#if !SDL`, `@available(*, unavailable, message: "enable the trait
   'SDL' on the MetalUI dependency: .package(url: …, traits: [\"SDL\",
   \"AccessKit\"]) — docs/getting-started.md") public final class SDLPlatform
   {}`, so a consumer that forgot the trait reads the remedy in the error
   (guard 1.6). `SDLBridge.c` is `#ifdef METALUI_SDL` around its body with a
   one-line stub outside it (an empty translation unit is not relied on).
5. **`Backends/SDL` becomes the backend's first consumer**: its manifest drops
   those four targets and depends on `.package(name: "MetalUI", path: "../..",
   traits: ["SDL", "AccessKit"])`, keeping `ReplayFixture`, `SDLReplay`,
   `PortableReplay`, `DemoCapture`, `MetalUISDLDemo`, `MainQueueDrainCheck`
   and both test targets. Its own product list keeps `ReplayFixture`,
   `SDLReplay` and the executables; `Experiments/SDLGPU` keeps depending on it
   by path. Linux/Windows test counts are unchanged by the move (the same test
   files, the same sources).

**Reasoning.** SwiftPM cannot depend on a subdirectory package by URL, and a
URL-fetched package may not have local path dependencies; the only package a
URL consumer can reach is the root. Traits are SwiftPM's compile-time switch
(SE-0450, tools 6.1); they keep the root's own build, every macOS consumer
and the Linux root CI job free of SDL, and make "I want the backend" one
word in the consumer's manifest. Leaving the sources in place keeps every
citation of `Backends/SDL/Sources/…` and the shader path valid.

**Cost if wrong.** If a later SwiftPM stops honouring `.when(traits:)` on a
setting, the backend compiles in (and fails on a machine without SDL) — the
root Linux CI job, which has no SDL, is the separating run (`L1`). If trait
unification across a graph differs from what lane 1 measures for
`Experiments/SDLGPU` (spec §5.1 item 3), that package names the trait itself.

## PX-I — What a consumer installs (and what the CI image now looks like)

*(Amended by `PX-Q`: `swift package resolve` first, cargo on Linux aarch64, `--prefix` staging; the flagless claim is measured by test 1.7.)*

**Ruling.**

1. **Linux**: SDL **3.4 or later** whose headers and `libSDL3` are on the
   compiler's default paths — a distribution's `libsdl3-dev` where it ships
   3.4+, or a source build installed with `-DCMAKE_INSTALL_PREFIX=/usr` — or
   anywhere else plus `-Xcc -I<prefix>/include -Xlinker -L<prefix>/lib`
   (measured `L4`/`L5`: gold does not search `/usr/local/lib`; the Swift
   importer ignores `CPATH`, `L3b`). **AccessKit**, once:
   `python3 .build/checkouts/MetalUI/Backends/SDL/scripts/fetch-accesskit.py
   --prefix /usr` (as root; copies `accesskit.h` and the static library onto
   the default paths), or `--print-flags` to keep it elsewhere and pass the
   flags it prints; or leave the `AccessKit` trait out (no screen-reader
   support). With both on the default paths the build is plain `swift build`.
2. **Windows**: no pkg-config, as today — SDL3's VC package and AccessKit's
   fetched files, passed as `-Xcc -I… -Xlinker -L…` (`fetch-accesskit.py
   --print-flags` prints AccessKit's half); `SDL3.dll` beside the executable
   at run time.
3. **macOS** (only for an app that chooses SDL there; the default is AppKit):
   `brew install sdl3`, and `-Xcc -I$(brew --prefix)/include -Xlinker
   -L$(brew --prefix)/lib` plus AccessKit's flags. A Homebrew SDL3 links with
   one `ld` deployment-target warning (`M5`) — Homebrew's dylib, not
   MetalUI's manifest.
4. **The script**: `fetch-accesskit.py` gains `--prefix DIR` and
   `--print-flags` (and keeps `ACCESSKIT_DIR`); it no longer writes
   `accesskit.pc`.
5. **The CI image** (`Backends/SDL/linux/Dockerfile`) installs SDL3 with
   `-DCMAKE_INSTALL_PREFIX=/usr` and AccessKit with `--prefix /usr` and drops
   `PKG_CONFIG_PATH`, so the container command in the harness and in
   `sdl-gpu-linux.yml` stays flagless — and so it is the layout item 1
   documents as "the default paths".
6. **This repository's own macOS work on `Backends/SDL`** passes the flags
   item 3 names (the script prints all of them on macOS) instead of
   `PKG_CONFIG_PATH=$PWD/.accesskit`; the Record phase changes CLAUDE.md's
   build line (spec §8.1).

**Cost if wrong.** A distribution that installs SDL3 off the default paths
needs the flags — the docs say so in the same paragraph.

## PX-J — `metalui new --cross-platform` by URL

**Ruling.**

1. `--cross-platform` **no longer requires `--local`** (`SC-C` amended): the
   generated manifest depends on MetalUI once (URL+revision per `SC-I`, or
   `--branch`, or `--local` path) with
   ```swift
   #if os(Linux) || os(Windows)
   let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
   #else
   let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
   #endif
   ```
   passed as `traits: metalUITraits`, and names `MetalUISDL`,
   `MetalUIPortableText` and `MetalUISystemFonts` from the **MetalUI** package
   conditioned on Linux and Windows. The `Backends/SDL` path dependency is
   gone from `--local` output too. Tools version **6.1** for a cross-platform
   manifest (traits); 6.0 otherwise, unchanged.
2. **`--no-accesskit`** generates `["SDL"]` and a README line saying the app
   has no screen-reader support on Linux and Windows.
3. The generated README's Linux/Windows/macOS sections say exactly `PX-I`'s
   steps; the two "harmless warnings" paragraph is deleted (`M3`: there are
   none now).
4. **Refused names** (`SC-H`): lane 1 generates and builds a package named
   after each new root target (`CStbImage`, `CSDL`, `CAccessKit`,
   `SDLBridge`, `MetalUISDL`) and refuses exactly those that fail, recording
   the error text; none is refused unmeasured.

## PX-K — The public-API census stays the framework's

**Ruling.** `MetalUISDL` joins the root's library products but **not**
`closeout-public-api.sh`'s `TARGETS`: its 97 public declarations
(`SDLPlatform`, `SDLWindow`, `SDLWindowRenderer`, `AccessKitSnapshot`, test
hooks) are a backend's plumbing an app touches in one line (`SDLPlatform()`),
never classified against SwiftUI, and outside the census since `RS-D`. New
public declarations in `Sources/` owe a doc comment and a map row as always
(`ImageBitmap.init?(data:)`, `ImageBitmap.init?(resource:withExtension:
subdirectory:bundle:)`, the two `task` methods); the unavailable stub (`PX-H`
item 4) carries a doc comment.

**Cost if wrong.** If a reviewer wants the backend censused, it is a
mechanical pass over one target with every row class `M`.

## PX-L — Headless driving and the SDL proofs

**Ruling.**

1. **Harness tests** drive `.task` through `makeFakeWindow` and
   `drawFrameIfNeeded()` (`LC-K`), in `async` `@MainActor` tests. A task's
   progress is awaited by **counting `Task.yield()`s** up to a bound
   (`pumpMainActor(until:maxYields:)`), never by wall clock; a task meant to
   be cancelled waits on `withTaskCancellationHandler` + a continuation its
   `onCancel` resumes — never on a long `Task.sleep` a broken cancel would
   leave hanging.
2. **SDL, two checks in `MainQueueDrainCheck`** (a process of its own: a
   Swift Testing test is a main-actor job, inside which no drain runs, `J1`):
   - mode `task-modifier` — an `App` over `SDLPlatform(hiddenWindows: true)`
     whose root's `.task` yields three times, removes its own content, and
     awaits cancellation; prints `task started=… steps=… cancelled=…`. It
     needs a built frame, which **SDL's offscreen driver never produces**
     (`beginFrame()` gets no swapchain texture; the precedent gating 10.2 and
     10.3), so its test is `.enabled(if: windowsPresentFrames)`: it runs on
     macOS, not in the Linux container. Honestly gated, not skipped silently.
   - mode `immediate-task` — top-level code starts
     `Task.immediate { @MainActor in … }` (what the modifier's start does)
     before `platform.run()`, yields three times, then awaits cancellation
     that a later display-link tick issues; prints the same line. **Needs no
     frame, so it runs in the Linux container**, where the drain is the
     separating mechanism (`SV-H`'s mutation).
3. **The URL consumer** is built by an env-gated test in
   `MetalUIScaffoldTests` (`METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1`, Linux, in
   the CI image): it copies the checkout's manifest and source directories
   into a scratch git repository (no reliance on the checkout's own `.git`,
   which a worktree mounted in a container cannot read), generates a
   cross-platform package depending on `file://<scratch>` at that commit, and
   runs `swift build`. Its separating arm builds a `--no-accesskit` package
   with `-Xcc -I<dir>` naming a **poison `accesskit.h`** (`#error`), so any
   AccessKit import under `SDL` alone fails the build.

## PX-M — Lanes: three, disjoint files, in order 1 → 2 → 3

**Ruling.** Agents run one at a time, in this order; each owns its files
(spec §3 lists them):

1. **Lane 1 — packaging** (first, because every manifest edit is its):
   root `Package.swift` (the four SDL targets, both traits, `CStbImage`, the
   `MetalUI → CStbImage` edge), `Sources/CStbImage/**` (vendored),
   `Backends/SDL/Package.swift`, the four moved targets' sources (trait
   wrapping only), `Backends/SDL/scripts/**`, `Backends/SDL/linux/Dockerfile`,
   `Backends/SDL/README.md`, `Experiments/SDLGPU/Package.swift`,
   `.github/workflows/**`, `Sources/MetalUIScaffold/**`,
   `Tests/MetalUIScaffoldTests/**`, `Tests/MetalUITests/SDLTraitCompileGuards.swift`,
   `docs/getting-started.md`, `docs/packaging.md`. It also adds, unused until
   lane 3, `MainQueueDrainCheck`'s dependencies on `MetalUI` and
   `MetalUIPortableText`.
2. **Lane 2 — images**: `Sources/MetalUI/ImageBitmap.swift`,
   `Sources/MetalUI/ImageDecoding.swift` (new),
   `Tests/MetalUICrossPlatformTests/ImageDecodingTests.swift` (new),
   `Tests/MetalUICrossPlatformTests/ImageFixtures/**` (new),
   `Tests/MetalUITests/ImageTests.swift`,
   `docs/probes/image-decoder-parity/gen-fixtures.py` (its `--tests` mode).
3. **Lane 3 — `.task`** (last, so it also writes the shared registries):
   `Sources/MetalUI/Lifecycle.swift`, `Sources/MetalUI/TaskModifier.swift`
   (new), `Tests/MetalUITests/TaskModifierTests.swift` (new),
   `Tests/MetalUITests/TaskCompileGuards.swift` (new),
   `Backends/SDL/Sources/MainQueueDrainCheck/main.swift`,
   `Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift`, and the
   registries: `docs/divergences.md` (137 and 138), `docs/api-overview.md`,
   `docs/migration.md`, `docs/verification/human-checks.md` (group X),
   `docs/probes/closeout-inventory-map.tsv`, `docs/probes/closeout-public-api.tsv`
   — writing lane 2's rows from spec §8.2's text.

Two lanes with one touching every file a third needs is why packaging goes
first; `Window.swift` is in no lane (spec §1.2: `drainLifecycle` and
`runDisappearancesForClose` need no change).

## PX-N — Demo and human checks

**Ruling.** **No demo change**: no new section, no edited section — the
fourteen offscreen images stay at 0 differing pixels against `359444e` and
`DemoFrameDeterminismTests`' `Expected.swift` is not edited (`ImageBitmap`'s
demo uses go through `init(width:height:rgba:)`, untouched). Human checks
gain **group X** (spec §7): a generated cross-platform app by URL on a Linux
desktop (X1), a `.task` counter in a real SDL window on Linux and Windows
(X2), Orca with and without the `AccessKit` trait (X3), the same app built on
Windows (X4), and the configurator's icons on Linux (X5). **An agent cannot
run them.**

## PX-O — Critic pass: the decoder's pre-checks, made pinnable and closed

**Ruling.** The design's `PX-D` pre-checks and `PX-B` build are amended; spec
§1.1 and §4.2 carry the amended steps and tests.

1. **The PNG pre-check is its own internal function**,
   `pngStructureIsIntact(_ bytes: UnsafeRawBufferPointer) -> Bool` (signature,
   every chunk length in bounds, every CRC-32, an `IEND`), tested **directly**
   as well as through `ImageBitmap`. Measured by the critic pass (stb_image
   2.30, the 9×7 `rgba8.png` of `gen-fixtures.py`'s probe mode, 319 bytes:
   IHDR ends at 33, IDAT at 307, IEND at 319): of the 319 truncated prefixes
   stb **alone** decodes exactly four, lengths 315–318 (the `IEND` type read,
   its CRC missing — stb checks no CRC), and returns `NULL` for the prefix that
   ends right after IDAT's CRC (307: it reads a zero chunk type past the end,
   an unknown critical chunk). So spec test 2.6's mutation "skip the `IEND`
   requirement" **could not redden** through `ImageBitmap` (307 is refused by
   stb; 315–318 by the length check). The `IEND` requirement stays
   (defence in depth against a later stb) and is pinned by the direct arm
   **2.6b** (`pngStructureIsIntact` of the prefix ending right after IDAT's
   CRC is `false`; the 4×3 test fixture's offsets differ, the shape does not;
   measured on the 9×7 file, 2 096 single-bit IDAT flips: stb alone decodes
   1 186, so 2.7's CRC mutation does redden); 2.6's
   own PNG mutation becomes "skip the chunk-length bound" (the prefixes that
   end inside `IEND`'s CRC then decode).
2. **The JPEG pre-check walks marker segments**, not raw bytes:
   `jpegScanIsTerminated(_:)` steps from `SOI` by each segment's 16-bit length
   to the first `SOS`, then requires an `FF D9` after that `SOS`'s header.
   The design's raw scan ("an `FF D9` after the first `FF DA`") is **defeated
   by an embedded thumbnail**: measured, `q90.jpg` with an `APP1` payload
   holding `FF D8 FF DA 00 02 00 FF D9` and its main scan cut in half passes
   the raw scan and stb decodes it (9×7, zero-padded) — a partial image, the
   very thing `PX-D` item 2 refuses. New fixture `thumb-truncated.jpg`
   (written by `gen-fixtures.py --tests`) and test **2.13**; its mutation is
   the raw scan.
3. **The dimension cap has two independent guards, each pinned on its own.**
   `STBI_MAX_DIMENSIONS` and the Swift bound (spec §1.1 step 4) each refuse a
   16385-wide file, so the design's single mutation (the define to 16385)
   would leave 2.8 green. 2.8 gains arm **2.8b** — `stbi_load_from_memory` of
   `wide-16385x1` called directly (the test target depends on `CStbImage`)
   returns `NULL` — reddened by the define mutation, and arm **2.8c** —
   `decodedSizeIsAccepted(width: 16385, height: 1)` is `false` and `(16384,
   1)` is `true` — reddened by moving the Swift bound.
4. **`STBI_NO_SIMD`**: the parity table and the literal JPEG pixels were
   measured on Apple silicon, where stb takes its scalar paths (NEON only
   with an explicit `STBI_NEON`); Linux and Windows CI are x86-64, where stb
   enables SSE2 IDCT and colour conversion by default. stb's comments claim
   the SIMD paths are bit-identical to the scalar ones; that is a claim, not a
   measurement here. Compiling the scalar paths everywhere makes the measured
   code the shipped code on every platform (`PX-C` item 1); the cost is JPEG
   decode speed, irrelevant for icon-sized assets.
5. **A buffer longer than `Int32.max` bytes is `nil`** before stb is called
   (its lengths are `int`; an unchecked `Int32(count)` would trap — `PX-D`
   says never). Not tested with a 2 GiB buffer; the bound is one comparison
   in `decodeImage` with a doc comment naming it.
6. **Test 2.9's mutation could not redden**: "`data:` skips the pre-check" on
   valid fixtures and on empty data changes nothing. 2.9 also decodes the
   prefix of `rgba8.png` that ends inside `IEND`'s CRC through `init?(data:)`
   and expects `nil` (stb alone decodes it).

**Cost if wrong.** Each item is a test arm or a define; none changes the
public surface.

## PX-P — SDL shaders: found beside the executable, then by `#filePath`

**Ruling.** `SDLWindowRenderer` loads its compiled shaders from
`bundledShaderDirectory`, which is `#filePath`-relative
(`Backends/SDL/Shaders/compiled` in the build machine's checkout) and is the
only directory `SDLPlatform` can use: `SDLPlatform.init` takes no shader
directory. A URL consumer's `swift run` works; **the same binary copied
anywhere else fails** at its first window (`SDL GPU device`). A consumable
backend owes a way to ship it:

1. `SDLWindowRenderer.shaderDirectoryCandidates(executableDirectory:) ->
   [String]` returns `<executableDirectory>/MetalUISDLShaders`, then
   `bundledShaderDirectory`; the first that holds `SOURCE.sha256` is used
   (`Bundle.main.executableURL`'s directory in production). None → the
   renderer throws an error **naming every directory tried** (`AI-N`'s
   precedent for `ShaderLibrary`).
2. `docs/packaging.md` (Linux and Windows sections) says: copy
   `.build/checkouts/MetalUI/Backends/SDL/Shaders/compiled` beside the
   executable as `MetalUISDLShaders` (and, on Windows, `SDL3.dll`).
3. Test 1.10 (`SDLShaderDirectoryTests`, `Backends/SDL`, portable, runs in the
   Linux container): the executable-adjacent directory wins when both exist;
   the `#filePath` one is used when it alone exists; neither → the error's
   description contains both paths. Mutations: swap the candidate order (arm
   1 red); drop the paths from the description (arm 3 red).

No public `SDLPlatform` initialiser changes (the candidate list is the
mechanism); `MetalUISDL` stays outside the census (`PX-K`).

**Cost if wrong.** If a packager wants another layout, an
`SDLPlatform(shaderDirectory:)` parameter is additive.

## PX-Q — What a consumer installs: three omissions corrected

**Ruling.** `PX-I` item 1 is amended; the generated README (test 1.4's
literals) and `docs/getting-started.md` say all three:

1. **`swift package resolve` first.** The fetch script lives in
   `.build/checkouts/MetalUI/…`, which exists only after resolution.
2. **Linux aarch64 needs a Rust toolchain (`cargo`)** for the `AccessKit`
   trait: accesskit-c 0.23.0 ships prebuilt static libraries for macOS, Linux
   x86_64 and Windows x64 only, and `fetch-accesskit.py` builds from source
   with cargo elsewhere (its docstring and its `cargo build --release
   --locked`). The alternative is dropping the trait.
3. **With `--prefix DIR`, the script stages its download and unpacking in a
   temporary directory** (or `$ACCESSKIT_DIR`) and copies only `accesskit.h`
   and the static library under `DIR` — it writes nothing into the SwiftPM
   checkout it was run from.

And one claim made honest: "with SDL3 and AccessKit on the default paths the
build is plain `swift build`" was **not measured** by the design (`L5` passed
flags; the probe's image installed SDL3 under `/usr/local`). It is measured by
lane 1's test 1.7 in the re-laid CI image (`PX-I` item 5); if gold or the
importer misses a default directory there, lane 1 records it and the docs
name the flag.

## PX-R — Critic pass: evidence corrections

**Ruling.**

1. **The bundle-image probe had no separating arm**: `B0` (loose `plain.png`)
   and `B1` (`missing`) both size 0×0, so `B0`–`B7` could have been a harness
   that sees no named image at all. The critic pass added **`B9`** — an 8×6
   image set compiled by `xcrun actool` into an `Assets.car` in the same
   bundle — which sizes **8×6**; three runs byte-identical, `I0`–`B8`
   unchanged. `PX-E` item 4 now rests on `B9` against `B0`.
2. **The task probe's recorded `X13` line** read `:232`, the line in a draft
   without the header; the committed file prints `:493`. Re-run once in full
   by the critic pass: every other arm byte-identical to the recorded block.
   Corrected in the block (no line above it moved; the note is appended at the
   end of the file).
3. **Divergence 137 overclaimed.** SwiftUI was measured on macOS 27 only,
   where `View.task` uses `_TaskModifier2` (its inlinable body in the SDK
   interface branches on `#available(macOS 26.4, *)`); what SwiftUI's older
   `_TaskModifier` does on macOS 14–26.3 is **unmeasured**. The row's text
   (spec §8.2) says "SwiftUI on macOS 27 starts it synchronously (X1, X15);
   SwiftUI on macOS 14–26.3 was not measured".
4. **Test 3.20 runs in no CI job**: macOS CI does not run `Backends/SDL`
   tests, and the Linux image's offscreen driver presents no frame
   (`Window.drawFrameIfNeeded` returns at `renderer.beginFrame()` before
   building, so no lifecycle event can run there — read in the source by the
   critic pass). The gate is honest; the lanes run 3.20 on macOS and record
   its printed line in record §80, and 3.21 is the CI proof of the mechanism
   (a main-actor immediate task progressing and seeing its cancellation under
   the SDL loop). Owner of a CI run: the deferred offscreen renderer (spec §9).

**Rejected (recorded so they are not re-raised).**

- *`ImageBitmap(data:)`/`(resource:…bundle:)` put Foundation types in a
  portable surface.* `Data` and `Bundle` are Foundation, which MetalUI already
  imports unconditionally on every platform (`Animation.swift`,
  `Color.swift`) and which swift-corelibs-foundation provides on Linux and
  Windows; no Apple framework crosses the surface. `ImageBitmap.swift` gains an
  unconditional `import Foundation` (today it imports it only under
  `canImport(ImageIO)`).
- *The `.task` spelling differs from SwiftUI's.* Checked against the macOS 27
  SDK's `SwiftUI.swiftinterface`: `task(name:priority:file:line:_:)` and
  `task(id:name:priority:file:line:_:)` with `@_inheritActorContext _ action:
  sending @escaping @isolated(any) () async -> Void` — the same. The
  `executorPreference:` overloads are `PX-A`'s deferral.
- *`Task.immediate(name:…)` needs macOS 26.4 like `Task.name`.* The SDK's
  `_Concurrency` interface marks `Task.immediate(name:priority:executorPreference:operation:)`
  `@available(anyAppleOS 26.0, *)`; only reading `Task.name` (test 3.17) needs
  26.4, and that test runs on macOS 27.
- *X11 contradicts `PX-F` item 8.* SwiftUI cancels when the hosting view
  leaves its window, not on `close()` with the host retained; MetalUI's close
  releases the window's tree (`LC-J`), which is the first case. Not a new
  divergence.
- *Lane 1 is too large; split it.* Its files are disjoint from lanes 2 and 3,
  and everything in it is one manifest's consequences (the SDL targets, the
  traits, the CI image the traits require, the scaffold that emits the
  traits). Splitting the scaffold out would put the CI step for test 1.7 and
  the test itself in different lanes. Kept; `PX-P` adds one small file pair to
  it.

## PX-S — Lane 1 as landed: what the packaging measured

**Ruling.** Lane 1 (packaging) landed as `PX-H`…`PX-J`, `PX-P` and `PX-Q`
say, with these findings, each measured on 2026-10-07 (macOS 27, Apple Swift
6.4; OrbStack, `metalui-portable` rebuilt from this branch's Dockerfile,
aarch64; `swift:6.4-noble`):

1. **The stub needs a public initialiser (amends `PX-H` item 4).** Guard 1.6
   reddened against the design's `public final class SDLPlatform {}`: the
   diagnostic was "'SDLPlatform' initializer is inaccessible due to 'internal'
   protection level" — the implicit `init()` is internal, and Swift reports
   that before the class's unavailability. The stub declares
   `public init(hiddenWindows: Bool = false) throws {}` (the real spelling);
   the diagnostic is then "'SDLPlatform' is unavailable: enable the trait
   'SDL' on the MetalUI dependency: … — docs/getting-started.md".
2. **Inside `App(platform:)` the remedy is not what a consumer reads.**
   Mutation M1.7 (the generated manifest without `traits:`) failed the
   consumer build, as 1.7 requires, but with "argument type 'SDLPlatform' does
   not conform to expected type 'Platform'" at `App(platform: try
   SDLPlatform(), …)` — the conformance is diagnosed before the
   unavailability. Making the stub conform to `Platform` would mean mirroring
   every defaultless requirement in an unavailable class; not done.
   `docs/getting-started.md` quotes both messages. Cost if wrong: a consumer
   searches the conformance error; the docs name it.
3. **Refused names, measured (`PX-J` item 4, `SC-H`).** A `--cross-platform
   --local` package renamed to each name, built on macOS (no traits) and in the
   CI image (both traits): `CStbImage`, `CSDL`, `CAccessKit`, `SDLBridge` fail
   identically on both at graph load — "multiple packages ('cstbimage',
   'portable-app') declare targets with a conflicting name: 'CStbImage';
   target names need to be unique across the package graph" (a trait-disabled
   target still counts). Refused (test 1.5). `ReplayFixture`, `SDLReplay`,
   `PortableReplay`, `DemoCapture` (refused since `SC-H` because
   `--cross-platform` added `Backends/SDL`) and `SDL` (refused as that
   package's identity) **built** on both, exit 0, so they are accepted now
   (`aNameOnlyBackendsSDLDeclaresGenerates`,
   `aNameThatIsADependencysPackageIdentityIsRefused`, whose name no longer
   describes it — kept so the record's citations resolve). The control
   package `Smoke` built on both: the full generated app, traits on, linked
   flagless in the image.
4. **Trait requests unify across the graph** (spec §4.1's open question).
   `Experiments/SDLGPU` depends on MetalUI by path **without** traits and on
   `Backends/SDL`, which asks for `SDL` and `AccessKit`; it builds and `swift
   run Replay --portable --record` passes on macOS (frames 0–7 at 0 differing
   pixels, the draw-order mutation detected) — `SDLBridge` was compiled with
   `METALUI_SDL`, or its `replay_*` symbols would not link. So
   `Experiments/SDLGPU/Package.swift` is unchanged.
5. **A test target may import a trait-gated C module it does not name.**
   `Backends/SDL`'s five AccessKit test files `import CAccessKit`, which is no
   product of the root; it resolves through `MetalUISDL`'s dependency (both
   build systems' module search paths carry transitive C modules). No
   `CAccessKit` product was added.
6. **The flagless claim holds in the re-laid image (`PX-Q`'s last
   paragraph).** cmake with `-DCMAKE_INSTALL_PREFIX=/usr` puts `libSDL3.so` in
   `/usr/lib/aarch64-linux-gnu` and `fetch-accesskit.py --prefix /usr` puts
   `libaccesskit.a` in `/usr/lib`; gold searches both. `Backends/SDL` builds
   and tests flagless (24 + 78 in the image), and tests 1.7 and 1.8 build their
   generated packages with plain `swift build` (1.8 adding only the poison
   `-Xcc -I`). Each consumer test asserts the linked executable exists, not
   only the exit status.
7. **The poison header is not what reddens 1.8.** Mutation M1.8
   (`AccessKitAdapter.swift` under `#if SDL`) fails the build with "no such
   module 'CAccessKit'": the module's `.when(traits:)` dependency is the gate,
   and the poison `accesskit.h` would fire only if the module were reachable
   without the trait. Both stay; 1.7 stays green under M1.8 (the separating
   arm).
8. **`fetch-accesskit.py --print-flags` prints one flag per line** (so a path
   with a space survives PowerShell's line splitting), progress on standard
   error, and on macOS Homebrew's `-Xcc -I…/include -Xlinker -L…/lib` first
   (`PX-I` item 6: `swift test $(python3 scripts/fetch-accesskit.py
   --print-flags)`); no argument means `--print-flags`. The Windows CI job
   writes them to a file and appends them to SDL3's flags.
9. **`--no-accesskit` without `--cross-platform` is a usage error** (it would
   mean nothing).
10. **`SDLWindowRenderer`'s initialisers take `shaderDirectory: String? =
    nil`** (`nil` = `defaultShaderDirectory()`, the first of
    `shaderDirectoryCandidates(executableDirectory:)` for
    `Bundle.main.executableURL`) — source-compatible for every caller passing a
    `String`. `SDLShaderDirectoryError` is public, in `MetalUISDL` (outside the
    census, `PX-K`).

**Mutations** (each applied to the committed tree `105c15a`, restored from a
copy, `git status --short` clean after each; macOS: native build, unfiltered
`swift test --build-system native --no-parallel`; image: unfiltered
`METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1 swift test`; `Backends/SDL`: its whole
suite):

| id | where (spelling) | reddened |
|---|---|---|
| M1.1 | `scaffoldFiles`: `if options.crossPlatform, case .remote = options.source { throw … }` restored | `crossPlatformNoLongerNeedsALocalCheckout`, `noAccessKitDropsOnlyTheAccessKitTrait`, `theCrossPlatformReadmeSaysWhatAConsumerInstalls`, `aNameOnlyBackendsSDLDeclaresGenerates` (macOS, 2635 run, 7 issues) |
| M1.2 | `manifest`: `.package(path: "<checkout>/Backends/SDL")` re-added under `--local --cross-platform` | `theLocalCrossPlatformManifestNamesNoBackendsSDLPackage` |
| M1.3 | `manifest`: `enabled` always `["SDL", "AccessKit"]` | `noAccessKitDropsOnlyTheAccessKitTrait` |
| M1.4 | the README's Linux section restored to `359444e`'s (pkg-config, `PKG_CONFIG_PATH`) | `theCrossPlatformReadmeSaysWhatAConsumerInstalls`, `noAccessKitDropsOnlyTheAccessKitTrait` |
| M1.5 ×4 | `clashingModuleNames` without `CStbImage` / `CSDL` / `SDLBridge` / `CAccessKit`, one run each | `aNameOfARootTargetThatFailedTheBuildIsRefused`, only the arm of the dropped name each time |
| M1.6 | the `#if !SDL` stub deleted | guard `anSDLPlatformWithoutTheSDLTraitNamesTheTrait` ("cannot find 'SDLPlatform' in scope"); before item 1's fix the guard was red too, on the inaccessible implicit initialiser |
| M1.7 | `manifest`: `traits` always `""` (image, unfiltered) | `aCrossPlatformPackageBuildsItsSDLAppByURL`, `aCrossPlatformPackageBuildsWithoutAccessKit` (both: "argument type 'SDLPlatform' does not conform to expected type 'Platform'"), `crossPlatformNoLongerNeedsALocalCheckout`, `theLocalCrossPlatformManifestNamesNoBackendsSDLPackage` |
| M1.8 | `AccessKitAdapter.swift` under `#if SDL` (image, unfiltered) | `aCrossPlatformPackageBuildsWithoutAccessKit` only ("no such module 'CAccessKit'") |
| M1.9 | `Backends/SDL/Package.swift`: the MetalUI dependency without `traits:` | the build: `MetalUISDLTests` "unable to resolve module dependency: 'CAccessKit'", `PortableReplay` fails to link (`SDLBridge` without `METALUI_SDL`) |
| M1.10a | `shaderDirectoryCandidates`: order swapped (`Backends/SDL`, macOS) | `theShaderDirectoryBesideTheExecutableWins` |
| M1.10b | `SDLShaderDirectoryError.description`: the count instead of the paths | `noShaderDirectoryIsAnErrorNamingEveryDirectoryTried` |

**Cost if wrong.** Items 1–2 are the only behaviour a consumer sees; the rest
are measurements a later SwiftPM could change, each with the run that would
show it (guard 1.6, tests 1.5/1.7/1.8, the `Replay` record step in CI).

## PX-T — Lane 2 as landed: what the images measured

**Ruling.** Lane 2 (portable images) landed as `PX-B`…`PX-E` and `PX-O` say
(`Sources/MetalUI/ImageDecoding.swift`, `ImageBitmap.swift`), with these
findings and amendments, each measured on 2026-10-07 (macOS 27, Apple Swift
6.4; `swift:6.4-noble` under OrbStack, aarch64 and — through Rosetta —
x86_64):

1. **The JPEG fixture is a smooth 4:4:4 image (amends spec §4.2, test 2.5).**
   A quality-90 JPEG of `rgb8.png`'s pixels at Pillow's default 4:2:0
   decodes up to ~200 away from them (red → (69, 82, 39): chroma is averaged
   over 2×2 on a 4×3 image of saturated neighbours), so "each within 3 of the
   generator's source pixel" was unsatisfiable. Measured with stb on a 4×3
   gradient at 4:4:4, steps 2/3/4/6/8 → max 1/2/3/3/3; `q90.jpg` is the step-6
   gradient (`gen-fixtures.py --tests` prints its source), max 3.
2. **The fixture set gains three files** beyond spec §4.2's list:
   `thumb.jpg` (the untruncated twin of `thumb-truncated.jpg`, 2.13's
   "the same file untruncated decodes" arm), `rgb8.tiff` (Pillow; the
   off-Apple arm `aTIFFIsNilOffApple`), and the generator prints every 4×3
   PNG's expected premultiplied bytes, which the tests carry as literals.
3. **One sniffing entry above `decodeImage` (amends spec §1.1 step 1).**
   `decodeImage(_:)` returns straight samples for PNG and JPEG only (`nil`
   otherwise); `decodeImageTexture(_:)` sniffs, premultiplies a portable
   decode through `ImageTexture(width:height:straightRGBA:)` and hands any
   other signature to the ImageIO fallback, which returns its own
   premultiplied texture (the two cannot share a straight-sample return).
   `init?(contentsOfFile:)` reads with `FileManager.default.contents(atPath:)`
   and delegates to `init?(data:)` — so a file and its bytes cannot decode
   differently by construction, and 2.9's mutation "`data:` skips the
   pre-check" is spelled as the PNG pre-check removed from `decodeImage`.
4. **A missing resource never reaches the cache** (amends 2.10's "the second
   from the cache"): `bundle.url(forResource:…)` answers `nil` before the
   cache is consulted. The cached-`nil` arm is a resource that exists and
   does not decode (`broken.png`, four bytes), still `nil` after its file is
   replaced by a valid PNG; the cached-bitmap arm likewise keeps its pixels
   after `icon.png` is replaced. `Bundle(path:)` of a flat directory resolves
   both a root resource and `Icons/dark/key.png` on macOS and Linux (2.10 runs
   green in the aarch64 and x86_64 containers) — `Contents/Resources` was not
   needed.
5. **Parity confirmed before the change.** With the decoding tests set aside,
   2.11 run on `359444e`'s ImageIO decode was red at its P3 arm only: every
   untagged and sRGB-tagged fixture (gray 1/4/8, gray + alpha, palette +
   `tRNS`, RGB, RGBA, Adam7 4×3 and 9×7, 16-bit RGBA) already equal to the
   portable decode. Existing test 3.11 (a PNG ImageIO writes) passes unchanged
   on the portable path; its literal did not move.
6. **The pixels are platform-independent as far as measured**: the thirteen
   portable tests (2.1–2.10, 2.6b, 2.13, `aTIFFIsNilOffApple`) pass with the
   same literals on macOS arm64, Linux aarch64 and Linux x86_64 (Rosetta) —
   the last the first run of `STBI_NO_SIMD`'s scalar JPEG path on x86-64
   (`PX-O` item 4). Windows is CI's.
7. **Counts of what the pre-checks stop** (from the mutation runs below): the
   CRC check alone stops 288 of 424 single-bit IDAT flips of the 4×3
   `rgba8.png` and 1 186 of 2 096 of the 9×7 one (the critic's number,
   reproduced); the length bound alone stops the four `rgba8.png` prefixes
   106–109 (inside `IEND`'s CRC); the EOI check alone stops 19 `q90.jpg`
   prefixes (623–641) — fewer than the critic's 485 of 669 on the 9×7 probe
   file, because a 4×3 4:4:4 scan is a few dozen bytes.
8. **The manifest** (lane 1's file, spec §4.2's "the test target depends on
   `CStbImage`"): `MetalUICrossPlatformTests` gains `CStbImage` and
   `exclude: ["ImageFixtures"]` (read by `#filePath`, not bundled; without the
   exclude SwiftPM warns about unhandled files).

**Mutations** (each applied to the committed tree `25f387f`, restored from a
copy, `git status --short` clean after each; native build, unfiltered `swift
test --build-system native --no-parallel`, 2649 tests each run, no hang):

| id | where (spelling) | reddened |
|---|---|---|
| M2.1 | 8-bit copy out of stb: R and B swapped | `everyFixturePNGDecodesToItsLiteralPixels`, `straightSamplesArePremultipliedOnce`, `anAdam7FileDecodesLikeItsPlainTwin`, `aJPEGDecodesToThePinnedPixels`, `aTruncatedJPEGWithAThumbnailIsNil`, `theDimensionCapIsSixteenThousandThreeHundredEightyFour`, `aBundleResourceDecodesOnceAndSharesItsTexture`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`, `anImageBitmapDecodesAPNGThroughImageIO` |
| M2.2 | 16-bit samples `v >> 8` | `sixteenBitSamplesRoundToEightBits`, `everyFixturePNGDecodesToItsLiteralPixels`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` |
| M2.3a | straight samples stored as premultiplied | `straightSamplesArePremultipliedOnce`, `everyFixturePNGDecodesToItsLiteralPixels`, `anAdam7FileDecodesLikeItsPlainTwin`, `aBundleResourceDecodesOnceAndSharesItsTexture`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`, `anImageBitmapDecodesAPNGThroughImageIO` |
| M2.3b | premultiplied twice | `straightSamplesArePremultipliedOnce`, `everyFixturePNGDecodesToItsLiteralPixels`, `anAdam7FileDecodesLikeItsPlainTwin`, `aBundleResourceDecodesOnceAndSharesItsTexture`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` |
| M2.4 | the PNG pre-check refuses IHDR interlace byte 1 | `anAdam7FileDecodesLikeItsPlainTwin` (9×7 arm and, through 2.1, the 4×3), `everyFixturePNGDecodesToItsLiteralPixels`, `fileAndDataDecodeIdentically`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` |
| M2.5 | `isJPEG` always false (on macOS the JPEG reaches ImageIO) | `aJPEGDecodesToThePinnedPixels`, `everyTruncationIsNilAndNeverTraps` (ImageIO decodes truncated JPEGs), `aTruncatedJPEGWithAThumbnailIsNil` |
| M2.6a | the chunk-length bound answers "is this `IEND`" instead of `false` | `everyTruncationIsNilAndNeverTraps` (prefixes 106–109), `fileAndDataDecodeIdentically` (the `IEND`-CRC arm) |
| M2.6b | `jpegScanIsTerminated` answers `true` with no EOI | `everyTruncationIsNilAndNeverTraps` (19 prefixes), `aTruncatedJPEGWithAThumbnailIsNil` |
| M2.6c | the walk that runs out after a whole chunk passes (no `IEND` needed) | `thePNGPreCheckRequiresIEND` only |
| M2.7 | the CRC comparison always passes | `aCorruptPNGIsNil` (both flip arms; the three corrupt fixtures stay `nil` — stb refuses them alone) |
| M2.8b | `STBI_MAX_DIMENSIONS 16385` (lane 1's `CStbImage.c`, restored) | `theDimensionCapIsSixteenThousandThreeHundredEightyFour` — the 2.8b arm only |
| M2.8c | the Swift bound `1...16385` | `theDimensionCapIsSixteenThousandThreeHundredEightyFour` — the two 2.8c 16385 arms only |
| M2.9 | the PNG pre-check removed (`data:` is the only path, item 3) | `fileAndDataDecodeIdentically`, `everyTruncationIsNilAndNeverTraps`, `aCorruptPNGIsNil` |
| M2.10 | the cache bypassed | `aBundleResourceDecodesOnceAndSharesItsTexture` (identity, cached `nil`, cached bitmap) |
| M2.11 | PNG routed through the ImageIO fallback | `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` (P3 arms), `everyFixturePNGDecodesToItsLiteralPixels` (`rgb8-p3.png`), `everyTruncationIsNilAndNeverTraps`, `aCorruptPNGIsNil`, `fileAndDataDecodeIdentically`, `theDimensionCapIsSixteenThousandThreeHundredEightyFour` (ImageIO accepts the 16385-wide file) |
| M2.12 | the ImageIO fallback dropped (`#if false`) | `aTIFFStillDecodesThroughImageIOOnApple` only |
| M2.13 | the design's raw scan (first `FF DA` anywhere, then any `FF D9`) | `aTruncatedJPEGWithAThumbnailIsNil` only |

**Cost if wrong.** Items 1–2 and 8 are test-side; item 3 is internal; item 4
is the cache's observable rule, stated in the initialiser's doc comment. None
changes the public surface beyond `PX-E`.

## PX-U — Lane 3 as landed: what `.task` measured

**Ruling.** Lane 3 (`.task` and the registries) landed as `PX-F`, `PX-G` and
`PX-L` say (`Sources/MetalUI/TaskModifier.swift`, `Lifecycle.swift`;
`Window.swift` unchanged — `drainLifecycle()` and
`runDisappearancesForClose()` run the new events as they are, as spec §1.2
expected), with these findings and amendments, each measured on 2026-10-07
(macOS 27, Apple Swift 6.4; the CI image and `swift:6.4-noble` under
OrbStack, aarch64):

1. **The running box is carried across a parked ghost too (amends spec
   §1.2).** `ParkedGhost` gains `running: [Key: RunningTask]`: a task key
   that leaves under a live removal ghost parks its box beside its cancel, and
   a key that returns before the ghost ends takes the box back into its new
   entry, so the next build sees it in both builds with a task already running
   — no cancel, no second start (`X17`, test 3.13). The mutation "drop the
   carry" (M3.13) shows as a second start **in the build after** the return,
   not in the return build (the returning appearance is cancelled with the
   parked event, `LC-H`; the following build finds the key in both builds
   with no running task and starts one).
2. **A key can change between a task and another lifecycle action.** A
   ternary over two lifecycle modifiers — `flag ? x.task { … } : x.onAppear
   { … }` — has one type (`LifecycleScope<X>`) and so one store key, and
   the write switches under it. Ruled: becoming a task starts it in the
   **appearance** bucket at the scope's place; stopping being one cancels it
   in the **change** bucket at the scope's place (the key stays present, so
   the disappearance bucket never sees it; no `onAppear` re-fires). SwiftUI
   has no counterpart (its two modifiers are two types, so the ternary does
   not compile), so this is MetalUI-only, not a divergence. Pinned by test
   **3.22** `aTernaryThatSwapsATaskForAnotherLifecycleModifierStartsAndCancelsIt`
   (added by this lane after the mutation pass found the two branches
   unpinned; M3.22a, M3.22b).
3. **`MainQueueDrainCheck` arms no `armMainRunLoopExitCheck()` (amends spec
   §4.3's last paragraph).** That check is an `atexit` guard for a **test**
   process whose outermost loop must never return (record §61 §9): it turns
   an exit after the main run loop returned into `_exit(1)`. The check
   executable is meant to exit when `platform.run()` returns, so arming it
   there would fail every run; the test process that launches it
   (`runDrainCheck`) creates no `SDLPlatform`. The new modes use no C enum,
   so the explicit-`rawValue` rule had nothing to convert. The
   `task-modifier` mode draws with the portable text system over the
   repository's Noto Sans (found by `#filePath`), since `App` needs a
   `TextSystem` off Apple (`XP-B`).
4. **The SDL lines (record §80 §3).** macOS: 3.20 `task started=true steps=3
   cancelled=true` (4–7 display-link passes over five runs), 3.21 the same
   line (4–12 passes); the CI image: 3.21 the same line after 58 passes, 3.20
   skipped by its gate (`PX-R` item 4). Mutations: removing the cancel from
   the disappearance event (M3.20a) prints `cancelled=false` after the
   200 000-pass bound and reddens 3.20 on macOS; `Task` for `Task.immediate`
   (M3.20b) is **green on macOS** — SDL's Cocoa pump runs the deferred body
   on a later pass — so 3.20 does not separate the start strategy and 3.1
   (headless) is its pin; deleting both `drainMainQueue()` calls in
   `SDLPlatform.run` (M3.21) prints `task started=true steps=0
   cancelled=false` in the CI image (the immediate prefix ran; nothing after
   the first `await` did) and reddens 3.21 with `SV-H`'s 1.18 and 1.19, and
   is green on macOS, as `SV-H`'s M1.18 recorded.
5. **Guard 3.G1's mutation reddens the build first.** Removing
   `@_inheritActorContext` from both overloads (MG3.1) makes
   `TaskModifierTests.swift` itself fail to compile ("main actor-isolated
   instance method 'add' cannot be called from outside of the actor",
   "main actor-isolated property 'width' can not be mutated from a
   nonisolated context") — a lost inheritance cannot ship with this suite.
   With that file compiled out (MG3.1b, 2652 tests), the guard alone reddens:
   "main actor-isolated instance method 'start()' cannot be called from
   outside of the actor".
6. **Spelling notes.** MG3.2's forwarding `onClick` on `LifecycleScope` also
   reddens the lifecycle guard 9.3 (one type carries both). MG3.3 drops the
   `Equatable` constraint with `isEqual: { _ in true }` (an unconstrained
   `T` has no `==`), so it also reddens the id-restart tests. Test 3.11 has
   no separate mutation (presence has no visibility branch); it reddened
   under M3.1 and M3.3. Tests carry arms beyond spec §4.3's text: 3.7 a
   rebuild after the task finished; 3.13 a later plain removal cancelling the
   kept task; 3.19 counts 15 for five task scopes and 0 with the toggle off,
   in one window; 3.17 returns early below macOS 26.4 (`Task.name`).

**Mutations** (each applied to the committed tree — `5ccf3e7` for the
TaskModifierTests/guard runs, `03d5868` for M3.22a/b — restored from a copy,
`git status --short` clean after each; native build, unfiltered `swift test
--build-system native --no-parallel`, 2671 tests each run (2672 for M3.22,
2652 for MG3.1b), no hang; the SDL mutations on a `git archive` of `5ccf3e7`,
the `Backends/SDL` suite in full):

| id | where (spelling) | reddened |
|---|---|---|
| M3.1 | `TaskStart.start` always `Task(priority:)` | `aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear`, `aTaskWrittenInsideOnAppearStartsFirst`, `siblingsAndParentsStartInReversePreOrder`, `theTaskPriorityDefaultsToUserInitiatedAndPassesThrough`, `removalCancelsAtItsPlaceInTheDisappearanceOrder`, `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`, `theSameIDOrARebuildRestartsNothing`, `anIDRestartRunsAtItsPlaceAmongOnChangeActions`, `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld`, `aGroupStartsOneTaskWhileItHasContent`, `hiddenAndTransparentContentStartsItsTask`, `aTaskUnderARemovalTransitionIsCancelledWhenTheGhostEnds`, `aTaskReinsertedMidRemovalKeepsRunning`, `closingTheWindowCancelsEveryTask`, `aTaskCarriesSwiftUIsDefaultName`, `aStateWriteInTheSynchronousPrefixReachesItsOwnOccurrence` |
| M3.2 | starts in a bucket of their own after all appearances | `aTaskWrittenInsideOnAppearStartsFirst`, `siblingsAndParentsStartInReversePreOrder` |
| M3.3 | the appearance bucket sorted ascending | `siblingsAndParentsStartInReversePreOrder`, `aTaskWrittenInsideOnAppearStartsFirst`, `aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear`, `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld`, `hiddenAndTransparentContentStartsItsTask`, `aTaskCarriesSwiftUIsDefaultName`; `LC-` `insertionRunsChildrenBeforeParentsAndLaterSiblingsFirst`, `initialTrueFiresWithAppearInModifierOrder`, `stackedLifecycleModifiersKeepSeparateEntriesInnerFirst`, `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState` |
| M3.4 | `Task.immediate(name:)` without `priority:` | `theTaskPriorityDefaultsToUserInitiatedAndPassesThrough` |
| M3.5a | task cancels appended before the other disappearances | `removalCancelsAtItsPlaceInTheDisappearanceOrder` (the `X4b` arm only), `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld` |
| M3.5b | the cancel event never calls `cancel()` | `removalCancelsAtItsPlaceInTheDisappearanceOrder` (both arms and the resumption), `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld`, `aGroupStartsOneTaskWhileItHasContent`, `aTaskUnderARemovalTransitionIsCancelledWhenTheGhostEnds`, `aTaskReinsertedMidRemovalKeepsRunning`, `closingTheWindowCancelsEveryTask` |
| M3.6 | the id restart starts, then cancels the old | `anIDChangeCancelsTheOldTaskThenStartsTheNewOne` |
| M3.7 | `isEqual` always `false` | `theSameIDOrARebuildRestartsNothing` |
| M3.8 | id restarts in the appearance bucket | `anIDRestartRunsAtItsPlaceAmongOnChangeActions` (the `X12b` arm) |
| M3.9 | appearances appended after the disappearances | `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld`; `LC-` `aChangedIdRunsTheNewAppearBeforeTheOldDisappear`, `changesRunBeforeAppearsAndAppearsBeforeDisappears` |
| M3.10 | the untyped scope notes with no content (`if true`) | `aGroupStartsOneTaskWhileItHasContent`; `LC-` `aGroupModifierFiresOncePerGroupAndOnlyWhileItHasContent` |
| M3.12 | a task's cancel never parked | `aTaskUnderARemovalTransitionIsCancelledWhenTheGhostEnds`, `aTaskReinsertedMidRemovalKeepsRunning` |
| M3.13 | the returning key does not take its box back | `aTaskReinsertedMidRemovalKeepsRunning` (item 1) |
| M3.14 | `closeAll` ignores running boxes | `closingTheWindowCancelsEveryTask` |
| M3.15 | `renderFrame` runs the store's events after its render | `aHeadlessRenderFrameStartsNoTask`; `LC-` `aHeadlessRenderFrameRunsNoAction` |
| M3.16 | the `forcesDeferredStart` seam ignored | `theDeferredStartRunsTheBodyOnALaterTurn` |
| M3.17 | `Task.immediate(name: nil, …)` | `aTaskCarriesSwiftUIsDefaultName` |
| M3.18 | the start event under `StateDispatch.outsideDispatch` | `aStateWriteInTheSynchronousPrefixReachesItsOwnOccurrence` |
| M3.19 | one extra work unit per carried box | `taskScopesCostWhatLifecycleScopesCost` |
| M3.22a | no start when a key becomes a task | `aTernaryThatSwapsATaskForAnotherLifecycleModifierStartsAndCancelsIt` |
| M3.22b | no cancel when a key stops being a task | `aTernaryThatSwapsATaskForAnotherLifecycleModifierStartsAndCancelsIt` |
| MG3.1 | `@_inheritActorContext` removed from both overloads | the test target does not compile (item 5) |
| MG3.1b | MG3.1 with `TaskModifierTests.swift` compiled out | `theTaskSpellingsTypecheckFromAnExternalModule` only |
| MG3.2 | a forwarding `onClick` extension on `LifecycleScope` | `aLegacyDecorationAfterATaskModifierDoesNotCompile`; `LC-` `aLegacyDecorationAfterALifecycleModifierDoesNotCompile` |
| MG3.3 | `task<T>(id:)` unconstrained, `isEqual: { _ in true }` | `aTaskIDMustBeEquatable`, `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`, `theSameIDOrARebuildRestartsNothing`, `anIDRestartRunsAtItsPlaceAmongOnChangeActions` |
| M3.20a | (SDL, macOS) the cancel event never calls `cancel()` | `aTaskModifierProgressesAndIsCancelledUnderSDLPlatform` |
| M3.20b | (SDL, macOS) `Task` for `Task.immediate` | nothing (item 4) |
| M3.21 | (SDL) both `drainMainQueue()` calls deleted | CI image: `anImmediateMainActorTaskResumesAndSeesItsCancellationUnderTheSDLLoop`, `theSDLLoopRunsAMainActorTaskStartedFromTopLevelCode`, `aDialogAnsweredOnAnotherThreadResumesAnAwaitingTask`; macOS: nothing |

**Cost if wrong.** Item 2's bucket choice is MetalUI's own and pinned; a
later ruling may move the cancel to the disappearance bucket in one line.
Items 1, 3–6 are internal or test-side.

## PX-V — The Record phase: three verifier findings ruled or recorded

**Ruling.** The three lane verdicts (all `ok: true`) left five minor findings;
two are corrected in the Record phase's commit, three are ruled here.

1. **A task key that returns from a parked removal ghost with a different
   `task(id:)` value keeps running under its old id.** `Lifecycle.swift`
   compares ids only inside `if let old = previous[key]`; a ghost-returned key
   has no previous entry (the box was taken back by `PX-U` item 1) and is
   skipped by the start branch, and no later build compares again, because
   from then on previous and current agree on the new id's entry. Read from
   the source and the verifier's trace; **not pinned and not probed against
   SwiftUI** (`X17` returns with the same id). Ruled: left as is. The case
   needs an id that changes in the same frames as a removal transition
   reverses, and the cost of being wrong is a task that finishes on a stale
   id until the next change. Owner: none until an app demands it; the fix, if
   one is ever wanted, is to compare at return and restart in the change
   bucket (`PX-U` item 2's bucket), pinned by a test that first reddens.
2. **Test 1.7's warning filter cannot fail as written.**
   `aCrossPlatformPackageBuildsItsSDLAppByURL` keeps lines containing
   `warning:` and `repository.path` (the source repository), but the consumer
   compiles MetalUI from `<root>/Consumer/.build/checkouts/MetalUI`, a path
   that never contains it; under mutation V6 the consumer's diagnostics named
   the consumer's paths only. What the test does prove is the link (status 0,
   the executable present) and, in the CI image, the build log it prints. The
   claim "0 warnings in a URL consumer" rests on lane 1's measurement of the
   printed log (record §80 §1.3), not on that `#expect`; **no document may
   cite the filter as a pin.** The repair is one substring
   (`.build/checkouts/MetalUI`) plus a mutation that adds a warning to
   MetalUI; deferred, owner a follow-up that can run the Linux consumer test
   (OrbStack).
3. **`aNameThatIsADependencysPackageIdentityIsRefused` now asserts an
   acceptance for `SDL`/`sdl`/`Sdl` when cross-platform** (`PX-S` item 3 kept
   the name so the record's citations resolve). Left; the test's doc comment
   says so.
4. **Corrected in this commit:** `Backends/SDL/Sources/CAccessKit/shim.h`'s
   first comment named pkg-config, which `PX-H` and `PX-I` removed (reworded
   to the compiler's default paths or `-Xcc -I`); `CLAUDE.md`'s `Backends/SDL`
   build line named `PKG_CONFIG_PATH` (now `--print-flags`, `PX-I` item 6).
5. **The `K2` reading is corrected everywhere it was copied** (spec §8.3):
   `LC-L`, record §76, `swiftui-lifecycle.swift`'s K1/K2 note. `swiftui-task.swift`
   `X5` (the `onCancel` instrument) shows SwiftUI cancels the old `.task(id:)`
   body **before** the new one starts; the lifecycle probe's `K2` printed the
   old task's resumption, which comes after.

**Cost if wrong.** Item 1 is a stale id in a corner. Item 2 is a
test that would stay green if a warning appeared. Nothing else moves.
