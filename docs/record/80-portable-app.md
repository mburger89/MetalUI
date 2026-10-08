# 80 — A MetalUI app on Linux and Windows: portable images, `.task`, a consumable SDL backend (complete)

Branch `feat/portable-app` from `359444e` (master: port gaps, medium, merged,
PR #50). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — what the SMK configurator needs to run on Linux and Windows.
Spec `docs/superpowers/specs/2026-10-07-portable-app-design.md`; rulings
`PX-A`…`PX-V` in `docs/superpowers/2026-10-07-portable-app-decisions.md`
(next unused `PX-W`); probes `docs/probes/swiftui-task.swift`,
`swiftui-bundle-image.swift`, `swift-task-modifier-isolation.swift`,
`image-decoder-parity/`, `swiftpm-traits-sdl/`.

**Status: complete (2026-10-07).** Lanes 1 (packaging), 2 (images) and 3
(`.task`) landed in that order (§1–§3); the Record phase's close is §4. No
renumbering: `origin/master` was still `359444e` at the close and no other
record numbered 80 exists. The spec's §8.3 is discharged here (§4.5).

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


## 3. Lane 3 — `.task` and the registries (2026-10-07)

Commits: `0193ff1` (red), `5ccf3e7` (implementation and registries),
`03d5868` (test 3.22), and this section's commit (ruling `PX-U`, spec
amendments). Rulings as landed: `PX-F`, `PX-G`, `PX-L`, amended by `PX-U`
(findings and the mutation table M3.1–M3.22b, MG3.1–MG3.3, M3.20a/b, M3.21).

### 3.1 Red

- `MetalUITests` did not compile: "value of type 'some StyledElement' has no
  member 'task'" (`TaskModifierTests.swift:129`, `:144`, `:164`, `:219`, …),
  "value of type 'Column<Content>' has no member 'task'" (`:147`), "value of
  type 'ForEach<Range<Int>, Int, some StyledElement>' has no member 'task'"
  (`:334`), "cannot find 'TaskStart' in scope" (`:472`, `:473`).
- With `TaskModifierTests.swift` set aside, the three guards ran and failed:
  "PX-F spellings: succeeded=false messages=[value of type 'Text' has no
  member 'task']" (3.G1, "Expectation failed: result.succeeded"); 3.G2 and
  3.G3 at their `#require` (the positive control did not compile either).
- `Backends/SDL` did not compile: `MainQueueDrainCheck/main.swift:107`
  "value of type 'ModifiedContent<Box<EmptyGroup>, ModifierLayer>' has no
  member 'task'" (the `task-modifier` mode).
- Test 3.22 was written after the implementation (`PX-U` item 2); its red is
  M3.22a and M3.22b.

### 3.2 Landed

- `Sources/MetalUI/TaskModifier.swift` (new): `task(name:priority:file:line:_:)`
  and `task(id:name:priority:file:line:_:)` with SwiftUI's closure type;
  `TaskAction`, `TaskSpec`, `RunningTask`, `TaskStart` (`Task.immediate` on
  macOS 26+ and off Apple, `Task` otherwise; `forcesDeferredStart`).
- `Lifecycle.swift`: `LifecycleWrite.task`; `Entry.task`/`running`;
  `ParkedGhost.running`; starts in the appearance bucket, id restarts
  (cancel, then start) in the change bucket, cancels in the disappearance
  bucket (parked under a ghost), the ternary case (`PX-U` item 2);
  `closeAll` cancels; `runningTaskCount`. `Window.swift` unchanged.
- `MainQueueDrainCheck` modes `task-modifier` and `immediate-task`;
  `SDLMainQueueDrainTests` 3.20 (gated off the offscreen driver) and 3.21.
- Registries: divergences **137** and **138** (105 live, next label 139);
  "Not offered" rows for `Image(_:bundle:)` and the `executorPreference:`
  overloads, the old `.task` row removed; `api-overview.md` (images,
  `.task`, platforms, census); `migration.md` (the lifecycle `.task` row and
  four behaviour rows: decoding on macOS, `.task` exists, `metalui new
  --cross-platform` by URL, `Backends/SDL`'s flags); human checks group
  **X** (X1–X5); inventory families `image-decoding` (M) and `task` (A,
  `swiftui-task.swift` `X5`); the census re-recorded: **2536 declarations in
  138 families** (2532 + the two decoding initialisers + the two `task`s).

### 3.3 Counts and commands

- Root, after `swift package clean`, native build, unfiltered
  `--no-parallel`: **2672 tests in 3 suites** passed (2649 + 23: TaskModifierTests 3.1–3.19
  and 3.22, guards 3.G1–3.G3); `FR-J no-argument frame: succeeded=true`;
  0 `error:`; the only `warning:` SwiftPM's deprecation notice. `swift build
  --build-tests` (default build system): 0 warnings. The three guards ran
  (`PX-F spellings: succeeded=true`, `PX-F decoration order: positive
  succeeded=true; negative succeeded=false`, `PX-F equatable id: positive
  succeeded=true; negative succeeded=false`).
- `Backends/SDL` macOS (`swift test $(python3 scripts/fetch-accesskit.py
  --print-flags)`): **24 + 83** (81 + 3.20, 3.21). 3.20's line: `task
  started=true steps=3 cancelled=true iterations=4`; 3.21's: `task
  started=true steps=3 cancelled=true iterations=4`. In the CI image
  (`metalui-portable`, flagless, on a `git archive` of `5ccf3e7`): **24 +
  80** passed, 3.20 skipped ("the offscreen video driver presents no window
  frame"), 3.21 `task started=true steps=3 cancelled=true iterations=58`.
  Warnings unchanged (Homebrew's `ld` deployment-target warning; the
  pre-existing unnecessary-`try` at `AccessKitControlsParityTests.swift:83`,
  present at `359444e`, not this lane's file).
- `swift:6.4-noble` (aarch64), root `swift build --build-tests` then `swift
  test --skip-build` on the same archive: build complete, no warning; 6 + 35
  + 18 + 199 + 49 + 22 passed (unchanged: `.task`'s tests are macOS-only, in
  `MetalUITests`).
- Demo pixels, `compare.sh <scratch> 359444e HEAD` at `5ccf3e7`: **0
  differing pixels, scene identical, in all fourteen images**; controls as
  before (light vs dark 1048576, default vs modal 1031003, default vs
  animation 454895, f0 vs f3 0).
- `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
- Mutations (`PX-U`'s table): each named test reddened; MG3.1 reddens the
  test target's build, MG3.1b the guard alone; M3.20b (SDL, macOS) and M3.21
  on macOS redden nothing, as `PX-U` item 4 records; no hang; `git status
  --short` clean after each.

### 3.4 Deferred

Nothing new beyond spec §9. 3.20 still runs in no CI job (`PX-R` item 4; its
macOS line is above). The Record phase owes spec §8.3 (CLAUDE.md/AGENTS.md,
the `LC-L`/`K2` correction, the record README row, record §04 sections for
137 and 138).

## 4. Record phase — the close

### 4.1 Suite, guards, census

Tree: `1bfe0c1` plus this phase's docs. `swift package clean`, `swift build
--build-system native --build-tests` (0 `error:`, the only `warning:` SwiftPM's
`--build-system native` deprecation notice), `swift test --build-system native
--no-parallel`, unfiltered: **`Test run with 2672 tests in 3 suites passed`**
(157.6 s; 2630 + 42), the `FR-J no-argument frame: succeeded=true` line present.

| Count | At `359444e` | Now | By |
|---|---|---|---|
| Tests | 2630 | **2672** | lane 1 +5 (2635), lane 2 +14 (2649), lane 3 +23 (2672) |
| Typecheck guards | 171 | **175** | +4 `canTypecheck`-gated declarations (`git grep "enabled(if: canTypecheck"`, 170 → 174): 1.6 (lane 1), 3.G1–3.G3 (lane 3), each mutated red once (§1, §3) |
| Goldens | 0 | 0 | `find Tests/MetalUILayoutTests -name "*.json"` reads 0 |
| Public census | 2532 | **2536** (+4) | `closeout-public-api.sh`; the recorded TSV re-taken; 138 inventory families (+2: `image-decoding`, `task`) |
| Live divergences | 103 | **105** | 137 and 138 added; next label **139** |
| `Backends/SDL` | 24 + 78 (macOS), 24 + 75 (Linux image) | **24 + 83**, **24 + 80** | lane 1 +3 (test 1.10), lane 3 +2 on macOS (3.20, 3.21), +2 in the image (3.21; 3.20 is gated off) |
| Linux container, root | 199 + 22 + 36 + 31 + 18 + 6 | 6 + 35 + 18 + 199 + 49 + 22 | the cross-platform target 36 → 49 (thirteen image tests); the other targets as measured (`swift:6.4-noble`, record §3.3) |

`closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing.
`swift build --build-tests` (default build system): 0 `warning:` (lane 3's
reading; no source changed since).

### 4.2 Not re-taken by this phase

- `Backends/SDL` on macOS and in the Linux image, and the demo pixels
  (**0 differing, scene identical, in all fourteen images** against `359444e`,
  taken by each lane's verifier at its own tip): this phase touched docs and
  one header comment (`CAccessKit/shim.h`), no source. `DemoFrameDeterminismTests`'
  `Expected.swift` unedited (Linux/Windows CI confirm on push). No shader
  change.
- Real-window captures and every group X look: not taken (an agent cannot).
- Windows: nothing built or run here; the new targets are portable and the
  CI jobs (`swift.yml`, `sdl-gpu-linux.yml`) were edited for the traits
  (§1.2), unexercised until a push.

### 4.3 Hazards

- **`ImageBitmap(contentsOfFile:)` on macOS changes** (divergence 138,
  `docs/migration.md`): colour-tagged PNG/JPEG are no longer converted, a PNG
  with any bad chunk CRC or no `IEND` and a JPEG with no end marker are `nil`
  where ImageIO returned something, JPEG bytes move by up to 2. Untagged and
  sRGB PNGs are byte-identical (22 files measured); the fourteen demo images
  read 0 px.
- **`.task` on macOS 14–25 starts one main-queue turn late** (divergence 137).
  **No CI job runs `.task` itself on Linux or Windows**: the root jobs do not
  run `MetalUITests`, and SDL test 3.20 is gated off the offscreen driver
  (`PX-R` item 4); what runs in the Linux image is 3.21, a hand-written
  `Task.immediate`, not the modifier's lifecycle path. A headless portable pin
  of the modifier is a follow-up.
- **`Backends/SDL` on macOS builds with flags**, not `PKG_CONFIG_PATH`
  (`swift test $(python3 scripts/fetch-accesskit.py --print-flags)`); the old
  command fails with "'SDL3/SDL.h' file not found". `CLAUDE.md` now says so.
- **`App(platform: SDLPlatform())` without the `SDL` trait** reads as a
  conformance error naming the stub's availability message (`PX-S` item 2);
  documented in `docs/getting-started.md`, not fixed.
- A consumer enabling the traits must have SDL3 (and AccessKit) installed;
  `docs/getting-started.md` lists exactly what, per platform.
- A recorded mutation hang or trap: none in any lane.

### 4.4 The verifiers' mutation tables (summary; the full tables are `PX-S`, `PX-T`, `PX-U`)

Each applied once from a clean tree, restored from a copy, `git status --short`
clean after each; the names are the tests reddened.

| Lane | Mutation | Reddened |
|---|---|---|
| 1 | `"DemoCapture"` added to the refused SDL-backend module names (`Scaffold.swift`) | `aNameOnlyBackendsSDLDeclaresGenerates` (that arm) |
| 1 | the manifest's `#if os(Linux) \|\| os(Windows)` traits block → `#if os(Windows)` (CI image) | `aCrossPlatformPackageBuildsItsSDLAppByURL`, `aCrossPlatformPackageBuildsWithoutAccessKit`, `crossPlatformNoLongerNeedsALocalCheckout` |
| 1 | the stub's `@available` message reworded | `anSDLPlatformWithoutTheSDLTraitNamesTheTrait` |
| 1 | the `SOURCE.sha256` check replaced by a directory-exists check | `theSourceTreesShaderDirectoryIsUsedWhenItAloneExists` |
| 2 | `pngStructureIsIntact` CRC always passes | `aCorruptPNGIsNil` (288 of 424 flips decode; 1186 of 2096 on the 9×7 file) |
| 2 | `ImageResourceCache` lookup bypassed | `aBundleResourceDecodesOnceAndSharesItsTexture` |
| 2 | a chunk walk ending at the buffer end passes without `IEND` | `thePNGPreCheckRequiresIEND` |
| 2 | `jpegScanIsTerminated` searches from offset 2 | `aTruncatedJPEGWithAThumbnailIsNil` |
| 2 | 16-bit samples truncated, not rounded | `sixteenBitSamplesRoundToEightBits`, `everyFixturePNGDecodesToItsLiteralPixels`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` |
| 2 | ImageIO fallback compiled out | `aTIFFStillDecodesThroughImageIOOnApple` |
| 2 | straight samples handed to the premultiplied initialiser | `straightSamplesArePremultipliedOnce` and five more (`everyFixturePNGDecodesToItsLiteralPixels`, `anAdam7FileDecodesLikeItsPlainTwin`, `aBundleResourceDecodesOnceAndSharesItsTexture`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`, `anImageBitmapDecodesAPNGThroughImageIO`) |
| 3 | plain `Task` for `Task.immediate` (V1) | seventeen `TaskModifierTests`, among them `aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear`, `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`, `closingTheWindowCancelsEveryTask` |
| 3 | `priority:` dropped; `name: nil`; `isEqual` always false; new task started before the old is cancelled; id restart in the appearance bucket | `theTaskPriorityDefaultsToUserInitiatedAndPassesThrough`; `aTaskCarriesSwiftUIsDefaultName`; `theSameIDOrARebuildRestartsNothing`; `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`; `anIDRestartRunsAtItsPlaceAmongOnChangeActions` |
| 3 | disappearance never yields the running cancel | five `TaskModifierTests` (`removalCancelsAtItsPlaceInTheDisappearanceOrder`, …) and, under SDL on macOS, `aTaskModifierProgressesAndIsCancelledUnderSDLPlatform` |
| 3 | `closeAll` ignores running boxes; the ghost-return box not taken back; boxes never written back; no cancel when a key stops being a task; `forcesDeferredStart` ignored | `closingTheWindowCancelsEveryTask`; `aTaskReinsertedMidRemovalKeepsRunning`; twelve tests; `aTernaryThatSwapsATaskForAnotherLifecycleModifierStartsAndCancelsIt`; `theDeferredStartRunsTheBodyOnALaterTurn` |
| 3 | a public `onClick` forwarding extension on `LifecycleScope` (guard 3.G2) | `aLegacyDecorationAfterATaskModifierDoesNotCompile`, `aLegacyDecorationAfterALifecycleModifierDoesNotCompile` |

### 4.5 Corrections made by this phase

- **The refuted `K2` reading** ("`.task(id:)` starts the new task, then cancels
  the old") struck in `LC-L` (lifecycle decisions), record §76 and the K1/K2
  note in `swiftui-lifecycle.swift`; `PX-V` item 5. `LC-L`'s blocker is gone
  and the modifier is built (`CLAUDE.md`'s Lifecycle paragraph, `docs/migration.md`).
- `CAccessKit/shim.h` no longer says pkg-config (`PX-V` item 4).
- `CLAUDE.md`/`AGENTS.md`: the `Backends/SDL` build line, `SC-C`'s "requires
  `--local`" (now by URL, `PX-J`), the `PX-` prefix, the Lifecycle paragraph,
  counts.
- Record §03 (group X owed), record §04 (137, 138), the record README row, the
  README.

### 4.6 Deferred, with owners

Spec §9 stands unchanged: colour management (none), asset catalogs and
`Image(_:bundle:)` (none), `.task(…executorPreference:…)` (none), frames under
SDL's offscreen driver (none; until then 3.20 runs in no CI job), `MetalUISDL`
in the census (none), a generated app built on Windows in CI (human check X4),
GIF/WebP/TIFF/HEIC/BMP off Apple (none). Added by `PX-V`: a task key
returning from a parked ghost with a changed `task(id:)` value keeps its old
id (unpinned); test 1.7's warning filter cannot fail (repair: match
`.build/checkouts/MetalUI`); both owned by a follow-up that can run the Linux
consumer test. Human checks X1–X5, unrun.

## 5. Adversarial branch check (2026-10-07, `359444e..3e196bd`)

- **Suite:** `swift package clean`, native build, unfiltered `--no-parallel`:
  `Test run with 2672 tests in 3 suites passed after 154.441 seconds.`
  `FR-J no-argument frame: succeeded=true`; 0 `error:`; the only `warning:`
  SwiftPM's `--build-system native` notice. `swift build --build-tests`
  (default build system): 0 warnings. 174 `canTypecheck`-gated declarations
  (170 at `359444e`). `cmp CLAUDE.md AGENTS.md` clean. Inventory and
  undocumented checks print nothing.
- **Demo pixels** (`compare.sh <scratch> 359444e HEAD`): all fourteen images
  `differing=0`, every scene identical; controls non-zero where required.
  `DemoFrameDeterminismTests`' `Expected.swift` unedited.
- **`Backends/SDL`, macOS** (flags from `fetch-accesskit.py --print-flags`):
  24 + 83, including 3.20 `aTaskModifierProgressesAndIsCancelledUnderSDLPlatform`,
  3.21 and 1.10. **Linux image** (rebuilt): `Backends/SDL` 24 + 80, 0
  warnings; root package 6 + 35 + 18 + 199 + 49 + 22, 0 warnings;
  `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1 --filter aCrossPlatformPackage`: 2
  tests passed (1.7 by URL, 1.8 without AccessKit). Hazard: in a *worktree*
  mounted at `/work`, CI's `git config --global` line fails ("not a git
  repository", the worktree's `.git` file names a host path) — run it from
  `/`; CI's real checkout is unaffected.
- **Two mutations of this check's own design** (each on `3e196bd`, restored
  from a copy, full unfiltered suite, `git status --short` clean after):
  - **A** — `Lifecycle.swift`, the carried box: `let box = old.running ??
    RunningTask()` → `let box = RunningTask()` and `if old.running == nil` →
    `if box.handle == nil` (every rebuild starts a new task and never cancels
    the old): 11 issues in `aGroupStartsOneTaskWhileItHasContent`,
    `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`,
    `anIDRestartRunsAtItsPlaceAmongOnChangeActions`,
    `aTaskReinsertedMidRemovalKeepsRunning`,
    `aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear`,
    `theSameIDOrARebuildRestartsNothing`.
  - **B** — `ImageDecoding.swift` `pngStructureIsIntact`, the chunk bound
    `offset + 12 + length <= bytes.count` → `<` (a PNG ending exactly at
    `IEND` refused): 11 issues in `aBundleResourceDecodesOnceAndSharesItsTexture`,
    `anAdam7FileDecodesLikeItsPlainTwin`, `anImageBitmapDecodesAPNGThroughImageIO`,
    `everyFixturePNGDecodesToItsLiteralPixels`, `everyTruncationIsNilAndNeverTraps`,
    `fileAndDataDecodeIdentically`, `sixteenBitSamplesRoundToEightBits`,
    `straightSamplesArePremultipliedOnce`,
    `theDimensionCapIsSixteenThousandThreeHundredEightyFour`,
    `thePNGPreCheckRequiresIEND`, `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`.
- **Unmoved** (no source under identity, hit testing, accessibility,
  animation, focus, `List`, `Deferred` or text input changed; the suite above
  is green): `theSevenRetentionSlotsAreMutuallyDistinct`,
  `everyNamingSiteStartsAReturningNameFresh`,
  `everyRegisteringSiteAnimatesItsLoweredRectUnderTheProposalAuthority`,
  `everyBackgroundPaintingSiteAnimatesItsColour`,
  `everyLegacySiteIsReportedByNameWhenDiagnosticsAreOn`,
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`.
- **Citations:** every ruling id cited in a changed file resolves to a heading
  (the unresolved ones are "next unused" lines or pre-existing non-heading
  definitions); every backticked test name added to a doc exists.
- **Doc defect fixed:** `docs/packaging.md` Linux §4 cites human check X1 for
  "a moved application opening its window", which X1 did not hold; X1
  (`human-checks.md`, spec §7, record §03) now ships the copy with
  `MetalUISDLShaders` and runs it with the checkout's `.build` moved away.
- **Open (unchanged, `PX-V`):** the ghost-return id case, test 1.7's warning
  filter, no CI job running `.task` itself. Windows builds (`CStbImage`, the
  `SDLBridge` stub) are confirmed only by CI on push.
