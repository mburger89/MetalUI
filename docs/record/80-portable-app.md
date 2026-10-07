# 80 — A MetalUI app on Linux and Windows: portable images, `.task`, a consumable SDL backend (design)

Branch `feat/portable-app` from `359444e` (master: port gaps, medium, merged,
PR #50). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — what the SMK configurator needs to run on Linux and Windows.
Spec `docs/superpowers/specs/2026-10-07-portable-app-design.md`; rulings
`PX-A`…`PX-T` in `docs/superpowers/2026-10-07-portable-app-decisions.md`
(next unused `PX-U`); probes `docs/probes/swiftui-task.swift`,
`swiftui-bundle-image.swift`, `swift-task-modifier-isolation.swift`,
`image-decoder-parity/`, `swiftpm-traits-sdl/`.

**Status: designed (2026-10-07).** Lanes 1 (packaging), 2 (images) and 3
(`.task`) to land in that order; each appends its section here.

## 0. Design

### 0.1 Baseline

`359444e`, native build, unfiltered `--no-parallel`: **2630 tests in 3
suites** passed; `FR-J no-argument frame: succeeded=true`; the only `warning:`
SwiftPM's deprecation notice. Divergences 103 live, next label 137.

### 0.2 What was measured, and what it decided

- **SwiftUI's `.task`** (`swiftui-task.swift`, 3 runs, byte-identical, screen
  locked): the body starts **synchronously** at its modifier's place in the
  `onAppear` order (inside `layoutSubtreeIfNeeded`; its pre-`await` write is
  in the first draw); removal cancels at its place in the `onDisappear` order;
  an id change cancels the old task, **then** starts the new one, at its place
  among `onChange` actions; a removal transition parks the cancel; a
  re-insertion mid-removal keeps the task; default priority `.userInitiated`;
  default name `View.task @ <fileID>:<line>`. Every answer is the lifecycle
  order applied to one more event kind → `.task` is one more `LifecycleWrite`
  (`PX-F`). Started with `Task.immediate` (macOS 26+, Linux, Windows);
  `Task` on macOS 14–25, one frame late (divergence 137, `PX-G`).
- **A refuted claim**: the lifecycle probe's `K2` reading ("starts the new
  task, then cancels the old") read the old task's resumption, not its
  cancel; `X5`'s `onCancel` instrument shows the reverse. Correction owed in
  the Record phase (spec §8.3).
- **Decoding** (`image-decoder-parity/`): SwiftUI draws exactly ImageIO's
  decode (22 files, 0 bytes differ). stb_image 2.30 with 16-bit samples
  rounded (not truncated) and ImageTexture's premultiply equals ImageIO byte
  for byte on every untagged or sRGB-tagged PNG measured, 8- and 16-bit, all
  colour types, Adam7, and all 66 configurator icons; it differs on
  colour-managed PNGs (gAMA max 19, Display P3 max 87) and JPEG (max 2) →
  one decoder on every platform, profiles ignored (divergence 138, `PX-C`).
  ImageIO returns partial images for truncated/corrupt PNGs; MetalUI returns
  `nil` (`PX-D`).
- **SwiftUI's `Image(_:bundle:)`** (`swiftui-bundle-image.swift`) does not read
  loose PNGs in a bundle (0×0 against an 8×6 instrument control) → not offered;
  `ImageBitmap(resource:withExtension:subdirectory:bundle:)` instead (`PX-E`).
- **SwiftPM traits** (`swiftpm-traits-sdl/run.sh`): `.systemLibrary(pkgConfig:)`
  makes the default build system warn in the declaring package and in every
  consumer even when unused; without `pkgConfig:` and behind `.when(traits:)`,
  0 warnings on macOS (both build systems), in a consumer, and in a plain
  Linux image without SDL; a URL consumer enabling the traits builds and links
  against SDL3 and AccessKit (`-Xcc`/`-Xlinker` when off the default paths; the
  Swift importer ignores `CPATH`; gold does not search `/usr/local/lib`). A
  root target may point into the nested `Backends/SDL/` directory by `path:`
  → the backend's library targets move into the root manifest without moving
  a file (`PX-H`, `PX-I`).

### 0.3 Lanes

`PX-M`: 1 packaging → 2 images → 3 `.task` (lane 3 also writes the shared
registries). Tests by name, with red-before and the mutation each must
survive, are spec §4.

### 0.4 Critic pass (same day, before lane 1)

Attacked the committed design; fixed in the spec and rulings `PX-O`…`PX-R`:

- **Mutations that could not redden** (measured with stb_image 2.30 on the
  probe fixtures): 2.6's "skip `IEND`" (stb alone refuses the prefix that
  ends after IDAT and decodes only the four ending inside `IEND`'s CRC, which
  the length bound refuses) → direct arm 2.6b on `pngStructureIsIntact`;
  2.8's single define mutation (two independent guards) → arms 2.8b/2.8c;
  2.9's "`data:` skips the pre-check" (only valid and empty inputs) → a
  pre-check-only prefix through `data:`. 2.7's CRC mutation does redden
  (stb alone decodes 1 186 of 2 096 single-bit IDAT flips).
- **A hole**: the raw `FF DA … FF D9` JPEG scan passes a truncated JPEG whose
  `APP1` thumbnail holds both markers, and stb returns a padded image → a
  segment walk and test 2.13 (`PX-O` item 2). `STBI_NO_SIMD` so the measured
  scalar paths ship on x86-64 CI too; an `Int32.max` length bound.
- **Consumability**: SDL shaders were found only by `#filePath`, so a built
  SDL app could not be moved → an executable-adjacent candidate and test 1.10
  (`PX-P`). Consumer text gained `swift package resolve`, cargo on Linux
  aarch64, and a staging rule for `--prefix`; the flagless default-path build
  is marked unmeasured until test 1.7 (`PX-Q`).
- **Evidence**: the bundle-image probe gained its missing positive control
  `B9` (an `Assets.car` entry sizes 8×6; loose files 0×0); the task probe's
  `X13` recorded line corrected to the committed file's `:493` after a full
  re-run (every other arm byte-identical); divergence 137's text limited to
  what was measured (macOS 27); test 3.20's absence from CI stated (`PX-R`).
- Rejected with reasons in `PX-R`: Foundation types in the image API, the
  `.task` spelling (matches the SDK interface), `Task.immediate`'s
  availability (26.0), X11 against `PX-F` item 8, splitting lane 1.

## 1. Lane 1 — packaging (2026-10-07)

Commits: `9f436c2` (red), `105c15a` (implementation), and this section's
commit (ruling `PX-S`, docs). Rulings as landed: `PX-H`…`PX-J`, `PX-P`,
`PX-Q`, amended by `PX-S` (findings and the mutation table).

### 1.1 Red

- `MetalUIScaffoldTests` did not compile: "value of type 'ScaffoldOptions'
  has no member 'accessKit'" (`ScaffoldTests.swift:214`, `:223`), "extra
  argument 'accessKit' in call" (`:651`).
- Guard 1.6, run with `359444e`'s `ScaffoldTests.swift`: "Expectation failed:
  canTypecheck(module: "MetalUISDL") — MetalUISDL is not among the root
  build's modules (PX-H item 1)". After the implementation it was red once
  more, on the design's stub: "'SDLPlatform' initializer is inaccessible due
  to 'internal' protection level" → `PX-S` item 1.
- `Backends/SDL` tests did not compile: "type 'SDLWindowRenderer' has no
  member 'shaderDirectoryCandidates'" / "… 'shaderDirectory'".

### 1.2 Landed

- Root `Package.swift`: `CStbImage` (stb_image 2.30, sha256 `594c2fe3…`,
  `MetalUI` depends on it); `CSDL`, `CAccessKit`, `SDLBridge`, `MetalUISDL` by
  `path:` into `Backends/SDL/Sources`; products `MetalUISDL`, `SDLBridge`;
  traits `SDL` and `AccessKit` (enables `SDL`); AccessKit's per-platform link
  libraries under `.when(platforms:traits:)`; no `pkgConfig:`.
- `MetalUISDL`: `#if SDL` / `#if AccessKit`; the unavailable stub;
  `SDLBridge.c` `#ifdef METALUI_SDL`; `SDLWindowRenderer`'s shader lookup
  (`MetalUISDLShaders` beside the executable, then `#filePath`).
- `Backends/SDL/Package.swift` a path consumer with both traits;
  `fetch-accesskit.py --prefix/--print-flags`; the Dockerfile installs SDL3
  and AccessKit to `/usr`; `sdl-gpu-linux.yml` (Homebrew flags for `Replay`,
  the consumer step, Windows flags from `--print-flags`, path filters);
  `Experiments/SDLGPU/Package.swift` unchanged (traits unify, `PX-S` item 4).
- `metalui new --cross-platform` from any source, `--no-accesskit`; the
  README, `docs/getting-started.md`, `docs/packaging.md`,
  `Backends/SDL/README.md`.

### 1.3 Counts and commands

- Root, native build, unfiltered `--no-parallel`: **2635 tests in 3 suites**
  passed (2630 + 5: tests 1.1–1.4 replace four scaffold tests, + 1.5's two,
  + 1.7, 1.8, + guard 1.6); `FR-J no-argument frame: succeeded=true`; the only
  `warning:` SwiftPM's deprecation notice. `swift build --build-tests`
  (default build system): 0 warnings.
- `Backends/SDL` macOS (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)`): **24 + 81** (78 + test 1.10's three arms); in the CI
  image, flagless: **24 + 78** (75 + 3). Warnings unchanged from `359444e`
  (Homebrew's `ld` deployment-target warning, one pre-existing
  unnecessary-`try` in `AccessKitControlsParityTests.swift:83`); the old
  "prohibited flag(s): -Wl,-rpath" is gone.
- Tests 1.7 and 1.8 in the CI image (`METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1
  swift test --filter aCrossPlatformPackage`): both pass; each consumer's
  executable is linked.
- `swift:6.4-noble`, no SDL installed: root `swift build --build-tests`
  complete, 0 warnings.
- `Experiments/SDLGPU` `swift run Replay --portable --record` (macOS,
  Homebrew flags): PASS, frames 0–7 0 differing pixels, the draw-order
  mutation detected.
- Demo pixels, `compare.sh <scratch> 359444e HEAD` at `105c15a`: **0
  differing pixels, scene identical, in all fourteen images**; controls as
  before.

### 1.4 Deferred

Nothing new beyond spec §9. The consumer-facing remedy inside
`App(platform:)` reads as a conformance error (`PX-S` item 2) — documented,
not fixed.

## 2. Lane 2 — portable images (2026-10-07)

Commits: `4aab939` (red), `25f387f` (implementation), and this section's
commit (ruling `PX-T`, spec amendments). Rulings as landed: `PX-B`…`PX-E`,
`PX-O`, amended by `PX-T` (findings and the mutation table M2.1–M2.13).

### 2.1 Red

- `MetalUICrossPlatformTests` did not compile: "incorrect argument label in
  call (have 'data:', expected 'contentsOfFile:')"
  (`ImageDecodingTests.swift:35`, `:295`), "cannot find
  'pngStructureIsIntact' in scope" (`:211`, `:212`), "cannot find
  'decodedSizeIsAccepted' in scope" (`:272`–`:276`), "missing argument for
  parameter 'contentsOfFile' in call" (the `resource:` calls, `:331`–`:348`),
  "cannot find 'jpegScanIsTerminated' in scope" (`:370`, `:371`).
- With that file set aside and 2.12's `data:` arm removed, on `359444e`'s
  ImageIO decode: `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`
  red at its P3 arms only ("Expectation failed: portable.texture.pixels !=
  reference", "… == plain.texture.pixels"); 2.12 and 3.11 green (`PX-T`
  item 5).

### 2.2 Landed

- `Sources/MetalUI/ImageDecoding.swift` (new): `decodeImageTexture` (the
  sniff), `decodeImage` (`Int32.max` bound, pre-checks, 16-bit rounding,
  `stbi_image_free` by `defer`), `pngStructureIsIntact`,
  `jpegScanIsTerminated`, `decodedSizeIsAccepted`, the ImageIO fallback
  under `#if canImport(ImageIO)`; `internal import CStbImage`.
- `ImageBitmap`: `init?(contentsOfFile:)` on every platform (reads the file,
  delegates to `init?(data:)`), `init?(data:)`,
  `init?(resource:withExtension:subdirectory:bundle:)` over
  `ImageResourceCache` (`NSLock`, keyed by the standardized path, `nil`
  cached); `import Foundation` unconditional; no CoreGraphics/ImageIO import.
- Fixtures (24 files, 7.4 KB, `gen-fixtures.py --tests`) under
  `Tests/MetalUICrossPlatformTests/ImageFixtures/`; tests 2.1–2.10, 2.6b,
  2.8b/c (arms of 2.8), 2.13, `aTIFFIsNilOffApple` (off Apple) in
  `ImageDecodingTests`; 2.11, 2.12 in `ImageTests`; 3.11 kept, doc comment
  updated, literal unmoved.
- The registry rows (map rows for the two new initialisers, divergence 138)
  are lane 3's (spec §8.2).

### 2.3 Counts and commands

- Root, native build, unfiltered `--no-parallel`: **2649 tests in 3 suites**
  passed (2635 + 14: twelve in `ImageDecodingTests` on macOS, two in
  `ImageTests`); `FR-J no-argument frame: succeeded=true`; 0 `error:`; the
  only `warning:` SwiftPM's deprecation notice. `swift build --build-tests`
  (default build system): 0 warnings.
- `swift:6.4-noble` (aarch64), `swift build --build-tests` then `swift test
  --skip-build` on an archive of `25f387f`: build complete, no warning;
  6 + 35 + 18 + 199 + 49 + 22 passed (the cross-platform target 36 → 49:
  thirteen image tests, `aTIFFIsNilOffApple` among them). The same image
  under `--platform linux/amd64` (Rosetta), filtered to the image tests:
  13 passed, the same literals (`PX-T` item 6).
- Demo pixels, `compare.sh <scratch> 359444e HEAD` at `25f387f`: **0
  differing pixels, scene identical, in all fourteen images**; controls as
  before (light vs dark 1048576, default vs modal 1031003, …).
- Mutations M2.1–M2.13 (seventeen runs): each reddened a named test
  (`PX-T`'s table); no hang; `git status --short` clean after each.

### 2.4 Deferred

Nothing new beyond spec §9. `Backends/SDL` was not touched by this lane and
not re-run.

