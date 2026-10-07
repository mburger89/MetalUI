# A MetalUI app on Linux and Windows — design

User request 2026-10-02 (an item of the gpui-gap priority list; **not a plan
task**). Rulings: [`../2026-10-07-portable-app-decisions.md`](../2026-10-07-portable-app-decisions.md)
(`PX-A`…`PX-V`; the critic pass added `PX-O`…`PX-R`, lane 1 `PX-S`, lane 2 `PX-T`, lane 3 `PX-U`, the Record phase `PX-V`). Record: `../../record/80-portable-app.md`. Branch
`feat/portable-app` from `359444e`.

**Motivation.** The SMK keyboard configurator runs on MetalUI on macOS
(`smk_configurator` branch `feat/metalui-port`); its next step is Linux and
Windows. Three things block it: `ImageBitmap(contentsOfFile:)` is ImageIO-only
(its rail icons are per-scheme PNGs); `.task` is deferred (`LC-L`); and the SDL
backend is a path-only package a URL dependent cannot reach (`SC-C`). The SDL
main-queue drain (`SV-H`) already landed.

**Status: complete (2026-10-07).** Lanes 1–3 landed and the Record phase
discharged §8.3 (record §80 §4); counts 2672 tests, 175 guards, census 2536.
The lanes' amendments are the `PX-S`…`PX-V` rulings; where this text and a
ruling differ, the ruling and the source win.

---

## §0 Baseline (measured at `359444e` by the design session)

- `swift build --build-system native --build-tests`, then `swift test
  --build-system native --no-parallel`, unfiltered: **2630 tests in 3 suites
  passed**; `FR-J no-argument frame: succeeded=true` present; the only
  `warning:` is SwiftPM's `--build-system native` deprecation notice.
- `docs/divergences.md`: 103 live, next label **137**. Human checks A–W.
- `Backends/SDL` (CLAUDE.md): macOS 24 + 78, Linux container 24 + 75
  (record §79 §5) — not re-taken by the design session.
- Every lane re-measures at its own start and end (`swift package clean`,
  native build, unfiltered run; read the summary line, never the exit status).

## §1 API

### §1.1 Images (lane 2; rulings `PX-B`…`PX-E`)

```swift
public struct ImageBitmap: Sendable {
    public init(width: Int, height: Int, rgba: [UInt8])            // unchanged
    /// PNG or JPEG on every platform, bit-identical (PX-C); other formats
    /// through ImageIO on Apple only. nil when missing, unreadable, corrupt,
    /// truncated, or wider/taller than 16384 (PX-D).
    public init?(contentsOfFile path: String)                       // now every platform
    /// The same decode from bytes in memory.
    public init?(data: Data)                                        // NEW
    /// A bundle resource, decoded once per resolved path per process; every
    /// call returns the same texture identity (PX-E item 3). MetalUI-only.
    public init?(resource name: String, withExtension ext: String? = "png",
                 subdirectory: String? = nil, bundle: Bundle)       // NEW
}
```

The decode, in `Sources/MetalUI/ImageDecoding.swift` (internal, one entry
point `decodeImage(_ bytes: UnsafeRawBufferPointer) -> (width: Int, height:
Int, straightRGBA: [UInt8])?`):

0. A buffer of more than `Int32.max` bytes → `nil` (stb's lengths are `int`;
   `PX-O` item 5).
1. Signature sniff (*as landed, `PX-T` item 3*: in `decodeImageTexture(_:)`,
   above `decodeImage`, which answers PNG and JPEG only): PNG → step 2; JPEG → step 3; otherwise → ImageIO under
   `#if canImport(ImageIO)` (the `359444e` body of `contentsOfFile`, moved
   verbatim, data-sourced through `CGImageSourceCreateWithData`), `nil`
   elsewhere.
2. PNG pre-check (`PX-D` item 1), the internal function
   `pngStructureIsIntact(_:) -> Bool` (`PX-O` item 1): chunk walk, every
   length in bounds, CRC-32 of type+data equal to the stored CRC (a 256-entry
   table computed once), `IEND` present. Then `stbi_is_16_bit_from_memory` → 16-bit path
   (`stbi_load_16_from_memory(…, 4)`, each sample `(v * 255 + 32767) / 65535`)
   or 8-bit path (`stbi_load_from_memory(…, 4)`).
3. JPEG pre-check (`PX-D` item 2), the internal function
   `jpegScanIsTerminated(_:) -> Bool` (`PX-O` item 2): walk marker segments
   from `SOI` by their 16-bit lengths to the first `SOS` (never a raw byte
   search — an `APP1` thumbnail holds its own `FF DA … FF D9`), then require an
   `FF D9` after that `SOS` header. Then the 8-bit path.
4. Reject width or height outside `1…16384` (the internal
   `decodedSizeIsAccepted(width:height:)`, `PX-O` item 3) or an overflowing
   byte count;
   `stbi_image_free` on every path.
5. `ImageBitmap` builds `ImageTexture(width:height:straightRGBA:)` from the
   straight samples — the one premultiply (`TE-AR`); ImageIO's branch keeps
   its own premultiplied draw and `init(premultipliedRGBA:)`, as at `359444e`.

`init?(contentsOfFile:)` reads with `FileManager.default.contents(atPath:)`
(a directory or unreadable path → `nil`). `init?(resource:…)` resolves the
URL, then consults `ImageResourceCache` (internal, `NSLock`-guarded
`[String: ImageBitmap?]` keyed by `url.standardizedFileURL.path`).

`ImageBitmap.swift` no longer imports CoreGraphics or ImageIO at file scope
outside the Apple fallback, and imports Foundation unconditionally (`Data`,
`Bundle`; `PX-R`'s rejected item 1); `ImageDecoding.swift` holds `internal import
CStbImage` and the `#if canImport(ImageIO)` fallback.

### §1.2 `.task` (lane 3; rulings `PX-F`, `PX-G`)

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

Implementation (in `Lifecycle.swift` and the new `TaskModifier.swift`):

- `LifecycleWrite` gains `case task(TaskSpec)`; `TaskSpec` holds `id: Any?`,
  `isEqual: ((Any) -> Bool)?` (`{ ($0 as? T) == value }`), `priority`,
  `name` (`name ?? "View.task @ \(file):\(line)"`) and `action: TaskAction`
  (`struct TaskAction: @unchecked Sendable { let run: @isolated(any) () async
  -> Void }` — the shape probe `swift-task-modifier-isolation.swift` compiled
  without a diagnostic).
- `LifecycleStore.Entry` gains `task: TaskSpec?` and `running: RunningTask?`
  (`final class RunningTask { var handle: Task<Void, Never>? }`). In
  `endFrame`, a key present in both builds **carries `previous[key].running`
  into the current entry** before anything else reads it.
- Events (`PX-F` items 3–5), each a `LifecycleEvent` with the scope's order
  and owner, put in the **existing** buckets:
  - appearance (new key, `task != nil`): `{ box.handle = TaskStart.start(spec) }`;
  - change (key in both builds, both `task`s have ids, `!isEqual(old id)`):
    `{ box.handle?.cancel(); box.handle = TaskStart.start(spec) }`;
  - disappearance (key gone): `{ box.handle?.cancel(); box.handle = nil }` —
    parked on a live ghost and cancelled on return exactly like an
    `onDisappear` (`LC-H`), so a re-inserted key keeps its box and runs no
    second start (`X17`). (Amended by `PX-U` item 1: `ParkedGhost` holds the
    parked keys' boxes, and a returning key takes its box back.)
  - a key that **becomes** a task (a ternary over two lifecycle modifiers,
    one type, one key) starts it in the appearance bucket; one that **stops**
    being a task cancels it in the change bucket (`PX-U` item 2, test 3.22).
  - `closeAll()` appends one cancel event per running box, in the same
    reverse order as the `onDisappear`s.
  `currentHasDisappearActions` stays `onDisappear`-only (a task cancel reads
  no departed state, `LC-I`).
- `TaskStart.start(_:) -> Task<Void, Never>`: `if !forcesDeferredStart,
  #available(macOS 26.0, *) { Task.immediate(name: spec.name, priority:
  spec.priority) { await spec.action.run() } } else { Task(priority:
  spec.priority) { await spec.action.run() } }`;
  `nonisolated(unsafe) static var forcesDeferredStart = false` is the
  `@testable` seam (`PX-G` item 3).
- `Window.swift` needs **no change**: `drainLifecycle()` already runs each
  event under `StateDispatch`, and `runDisappearancesForClose()` runs
  `closeAll()`'s events. (If the lane finds otherwise, that is a finding to
  record, and `Window.swift` joins lane 3.)
- Internal observability: `LifecycleStore.runningTaskCount` (boxes with a
  non-cancelled handle) for tests.

### §1.3 The consumable SDL backend (lane 1; rulings `PX-H`…`PX-J`)

Root `Package.swift`, every-platform list (`PC-A`):

```swift
traits: [
    .trait(name: "SDL", description: "The SDL3 backend (MetalUISDL) for Linux and Windows."),
    .trait(name: "AccessKit", description: "The SDL backend's screen-reader bridge (AccessKit).",
           enabledTraits: ["SDL"]),
],
// products += .library(name: "MetalUISDL", targets: ["MetalUISDL"]),
//             .library(name: "SDLBridge", targets: ["SDLBridge"])
.systemLibrary(name: "CSDL", path: "Backends/SDL/Sources/CSDL"),
.systemLibrary(name: "CAccessKit", path: "Backends/SDL/Sources/CAccessKit"),
.target(name: "SDLBridge", dependencies: [.target(name: "CSDL", condition: .when(traits: ["SDL"]))],
        path: "Backends/SDL/Sources/SDLBridge",
        cSettings: [.define("METALUI_SDL", .when(traits: ["SDL"]))],
        linkerSettings: [.linkedLibrary("SDL3", .when(traits: ["SDL"]))]),
.target(name: "MetalUISDL",
        dependencies: ["SDLBridge", "MetalUIPlatform", "MetalUICore", "MetalUIScene",
                       .target(name: "CAccessKit", condition: .when(traits: ["AccessKit"]))],
        path: "Backends/SDL/Sources/MetalUISDL",
        linkerSettings: /* PX-H item 2: accesskit + per-platform libraries, each
                           .when(platforms: […], traits: ["AccessKit"]) */),
.target(name: "CStbImage", exclude: ["LICENSE", "VENDORED.md"]),   // PX-B
// MetalUI's dependencies += "CStbImage"
```

`MetalUISDL` sources: every file `#if SDL … #endif`; `SDLWindowRenderer`'s
shader directory from `shaderDirectoryCandidates(executableDirectory:)` (`PX-P`); the two AccessKit files
and every AccessKit call site in `SDLPlatform.swift` `#if AccessKit`; under
`#if !SDL` the unavailable `SDLPlatform` stub (`PX-H` item 4), with a public
`init(hiddenWindows:) throws` so a call reports the unavailability rather than
an inaccessible implicit initialiser (`PX-S` item 1). No `pkgConfig:`
anywhere (`PX-H` item 3). `Backends/SDL/Package.swift` per `PX-H` item 5.
`fetch-accesskit.py` per `PX-I` item 4. The Dockerfile per `PX-I` item 5.
`metalui new` per `PX-J`.

What a consumer writes (Linux/Windows), and the scaffold generates:

```swift
// swift-tools-version: 6.1
#if os(Linux) || os(Windows)
let metalUITraits: Set<Package.Dependency.Trait> = ["SDL", "AccessKit"]
#else
let metalUITraits: Set<Package.Dependency.Trait> = [.defaults]
#endif
// .package(url: "https://github.com/mburger89/MetalUI", revision: "…", traits: metalUITraits)
// .product(name: "MetalUISDL", package: "MetalUI", condition: .when(platforms: [.linux, .windows]))
```

## §2 Files

New: `Sources/CStbImage/{stb_image.h, CStbImage.c, include/CStbImage.h,
LICENSE, VENDORED.md}`; `Sources/MetalUI/ImageDecoding.swift`;
`Sources/MetalUI/TaskModifier.swift`;
`Tests/MetalUICrossPlatformTests/ImageDecodingTests.swift` and
`ImageFixtures/` (the committed PNGs and JPEG of §4.2);
`Tests/MetalUITests/TaskModifierTests.swift`, `TaskCompileGuards.swift`,
`SDLTraitCompileGuards.swift`;
`Backends/SDL/Tests/MetalUISDLTests/SDLShaderDirectoryTests.swift` (`PX-P`).

Changed: as each lane lists (§3). Moved: nothing (`PX-H` item 1).

## §3 Lanes (ruling `PX-M`; order 1 → 2 → 3; agents run one at a time)

| lane | owns | depends on |
|---|---|---|
| 1 packaging | `Package.swift`; `Sources/CStbImage/**`; `Backends/SDL/Package.swift`; `Backends/SDL/Sources/{CSDL,CAccessKit,SDLBridge,MetalUISDL}/**`; `Backends/SDL/scripts/**`; `Backends/SDL/linux/Dockerfile`; `Backends/SDL/README.md`; `Experiments/SDLGPU/Package.swift`; `.github/workflows/**`; `Sources/MetalUIScaffold/**`; `Tests/MetalUIScaffoldTests/**`; `Tests/MetalUITests/SDLTraitCompileGuards.swift`; `Backends/SDL/Tests/MetalUISDLTests/SDLShaderDirectoryTests.swift`; `docs/getting-started.md`; `docs/packaging.md` | — |
| 2 images | `Sources/MetalUI/ImageBitmap.swift`; `Sources/MetalUI/ImageDecoding.swift`; `Tests/MetalUICrossPlatformTests/ImageDecodingTests.swift`; `Tests/MetalUICrossPlatformTests/ImageFixtures/**`; `Tests/MetalUITests/ImageTests.swift`; `docs/probes/image-decoder-parity/gen-fixtures.py` | lane 1's `CStbImage` target |
| 3 `.task` | `Sources/MetalUI/Lifecycle.swift`; `Sources/MetalUI/TaskModifier.swift`; `Tests/MetalUITests/TaskModifierTests.swift`; `Tests/MetalUITests/TaskCompileGuards.swift`; `Backends/SDL/Sources/MainQueueDrainCheck/main.swift`; `Backends/SDL/Tests/MetalUISDLTests/SDLMainQueueDrainTests.swift`; `docs/divergences.md`; `docs/api-overview.md`; `docs/migration.md`; `docs/verification/human-checks.md`; `docs/probes/closeout-inventory-map.tsv`; `docs/probes/closeout-public-api.tsv` | lane 1's manifest (`MainQueueDrainCheck` deps); lane 2's declarations for the registry rows |

Each lane: commits its work, then its mutations (commit first, restore from a
copy, full unfiltered suite, `git status --short` after each, every reddened
test named, the branch and spelling recorded), appends its findings as a
`PX-` ruling, and records counts. Lane 1 and lane 3 run `Backends/SDL` on
macOS and in the CI image (`docker build -t metalui-portable -f
Backends/SDL/linux/Dockerfile Backends/SDL`, then the flagless container
command); lane 1 also the plain `swift:6.4-noble` root build.

## §4 Tests — by name, red before, and the mutation that must redden each

"Red before" for a new API is "does not compile at `359444e`" unless stated;
the mutation is the separating instrument and is run after the test is green.

### §4.1 Lane 1 — packaging

- **1.1 `crossPlatformNoLongerNeedsALocalCheckout`** (`ScaffoldTests`) —
  `scaffoldFiles(ScaffoldOptions(name: "MyApp", crossPlatform: true))` (the
  pinned remote default) returns files; the manifest contains the `#if
  os(Linux) || os(Windows)` traits block literally, `traits: metalUITraits`,
  `// swift-tools-version: 6.1`, and `.product(name: "MetalUISDL", package:
  "MetalUI", condition: .when(platforms: [.linux, .windows]))`. Red before:
  throws `crossPlatformNeedsLocalCheckout` (replaces
  `crossPlatformWithoutALocalCheckoutIsRefused`, deleted with a migration
  note). Mutation: restore the throw in `scaffoldFiles`.
- **1.2 `theLocalCrossPlatformManifestNamesNoBackendsSDLPackage`** —
  `--local` output has one `.package(path:)` and no `Backends/SDL`. Red
  before: today's output adds it. Mutation: re-add the `sdlDependency` string.
- **1.3 `noAccessKitDropsOnlyTheAccessKitTrait`** — `--no-accesskit` (parsed
  by `parseArguments`, and `ScaffoldOptions.accessKit == false`) generates
  `["SDL"]` and the README's "no screen-reader support" line. Mutation: ignore
  the flag (always `["SDL", "AccessKit"]`).
- **1.4 `theCrossPlatformReadmeSaysWhatAConsumerInstalls`** — the README's
  Linux section contains `PX-I` item 1's instructions as amended by `PX-Q`
  literally (SDL 3.4+ on the default paths or the `-Xcc`/`-Xlinker` flags;
  `swift package resolve` first; `fetch-accesskit.py --prefix /usr` from
  `.build/checkouts/MetalUI/Backends/SDL/scripts/`; on Linux aarch64 a Rust
  toolchain for that step; or drop `AccessKit`) and its packaging line (the
  shader directory beside the executable, `PX-P`) and no "couldn't find pc file" text. Mutation: restore the old
  section.
- **1.5 Refused names** — one arm per name lane 1's measurement refuses
  (`PX-J` item 4), each `#expect(throws:)`, each with the recorded build error
  in its doc comment; a name that builds is not refused and gets an arm
  asserting it generates. Mutation per arm: drop the name from the refusal set.
- **1.6 guard `anSDLPlatformWithoutTheSDLTraitNamesTheTrait`**
  (`SDLTraitCompileGuards.swift`, `typecheckFile`, plain `import MetalUISDL`,
  the root build's module — built without traits): `_ = try SDLPlatform()`
  fails, and the diagnostic contains `enable the trait 'SDL'`. Red before:
  module `MetalUISDL` absent from the root build. Mutation: delete the stub →
  the diagnostic becomes "cannot find 'SDLPlatform' in scope" → red.
- **1.7 `aCrossPlatformPackageBuildsItsSDLAppByURL`** (env-gated
  `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1`, `#if os(Linux)`, counts while
  skipped) — `PX-L` item 3: scratch git repo from the checkout's `Package.swift`,
  `Sources/`, `Tests/` (without any `.build`), `Backends/SDL/{Sources,Shaders}`;
  a generated cross-platform package on `file://<repo>` at its commit;
  `swift build` exits 0 and prints no `warning:` naming a MetalUI path. Run in
  the CI image. Red before: generation throws. Mutation: generate without
  `traits:` → `MetalUISDL` is the stub → the app's `SDLPlatform()` fails.
- **1.8 `aCrossPlatformPackageBuildsWithoutAccessKit`** (same gate) — a
  `--no-accesskit` package built with `-Xcc -I<dir>` holding a poison
  `accesskit.h` (`#error "AccessKit must not be compiled"`). Mutation: guard
  `AccessKitAdapter.swift` with `#if SDL` instead of `#if AccessKit` → red.
- **1.10 `SDLShaderDirectoryTests`** (`Backends/SDL`, portable; macOS and the
  CI image; `PX-P`) — three arms over `shaderDirectoryCandidates` with
  scratch directories: the executable-adjacent `MetalUISDLShaders` wins when
  both hold `SOURCE.sha256`; the `#filePath` directory is used when it alone
  does; neither → the thrown error's description contains both paths.
  Mutations: swap the candidate order (arm 1 red); drop the paths from the
  description (arm 3 red). `Backends/SDL`'s macOS/Linux counts move by these
  arms only.
- **1.9 Existing `Backends/SDL` suites, unchanged in count** — macOS (with
  `PX-I` item 6's flags) and the CI image, flagless. The move is pinned by
  their staying green and by 1.7. Mutation (once, recorded): drop `traits:`
  from `Backends/SDL/Package.swift`'s MetalUI dependency → the SDL test target
  fails to compile.
- Commands, not tests, each recorded: root `swift build --build-tests` 0
  warnings on both build systems on macOS; `swift:6.4-noble` root `swift build
  --build-tests` with no SDL installed, 0 warnings (`L1`'s shape at full
  size); `Experiments/SDLGPU`'s `swift run Replay --portable --record` on macOS
  with Homebrew flags; whether trait requests unify across a graph
  (`Experiments` → `Backends/SDL` → MetalUI with traits, and `Experiments` →
  MetalUI without) — if not, `Experiments` names `["SDL"]` itself.

### §4.2 Lane 2 — images

Fixtures (committed under `Tests/MetalUICrossPlatformTests/ImageFixtures/`,
written by `gen-fixtures.py --tests`, a pure-Python encoder, so expected values
come from the generator, not a decoder): 4×3 `gray1`, `gray4`, `gray8`,
`graya8`, `palette2-trns`, `rgb8`, `rgba8`, `rgba8-adam7`, `rgba16` (samples
including 0, 255, 386, 32896, 65280, 65535), `rgb8-srgb`, `rgb8-p3` (iCCP);
9×7 `rgba8-adam7-9x7` and `rgba8-9x7`; `q90.jpg` (4×3, Pillow); the corrupt
set (`corrupt-idat`, `corrupt-truncated`, `corrupt-ihdr`); `wide-16385x1` and
`wide-16384x1` (valid CRCs, a solid row); `thumb-truncated.jpg` (`q90.jpg`
with an `APP1` holding `FF D8 FF DA 00 02 00 FF D9`, main scan cut in half;
`PX-O` item 2). Loaded by `#filePath` (`FT-G`). The test target depends on
`CStbImage` for arm 2.8b.

- **2.1 `everyFixturePNGDecodesToItsLiteralPixels`** (`ImageDecodingTests`,
  runs on Linux and Windows CI) — each 4×3 PNG's 48 premultiplied bytes as a
  literal array. Red before: `contentsOfFile` does not exist off Apple (and
  on macOS the fixtures directory does not exist). Mutation: swap R and B in
  the copy out of stb.
- **2.2 `sixteenBitSamplesRoundToEightBits`** — `rgba16`'s samples 255 → 1,
  386 → 2, 65280 → 254 (truncation would give 0, 1, 255). Mutation: `v >> 8`.
- **2.3 `straightSamplesArePremultipliedOnce`** — `graya8`/`rgba8` pixels at
  alpha 128 equal `(c × 128 + 127) / 255` of the generator's straight values,
  e.g. straight (200, 100, 50, 128) → (100, 50, 25, 128). Mutations: store
  straight (skip `straightRGBA:`); premultiply twice.
- **2.4 `anAdam7FileDecodesLikeItsPlainTwin`** — 9×7 Adam7 == 9×7 plain,
  byte for byte, and the 4×3 Adam7 (empty passes) == its literal. Mutation:
  the pre-check refuses `interlace == 1` → both arms red.
- **2.5 `aJPEGDecodesToThePinnedPixels`** (*as landed, `PX-T` item 1*:
  `q90.jpg` is a smooth 4:4:4 gradient — a JPEG of `rgb8`'s pixels decodes
  ~200 away) — `q90.jpg`'s 48 bytes literal
  (stb's output, the same on every CI platform) and each within 3 of the
  generator's source pixel. Mutation: the sniff recognises only PNG → the
  JPEG decodes to `nil`.
- **2.6 `everyTruncationIsNilAndNeverTraps`** — every prefix length
  `0..<count` of `rgba8.png` and of `q90.jpg` → `nil`. Mutations: skip the
  chunk-length bound (the prefixes ending inside `IEND`'s CRC then decode —
  measured, `PX-O` item 1; skipping the `IEND` requirement alone **cannot**
  redden this test, stb refuses a missing `IEND` itself); skip the EOI check
  (stb pads the JPEG: 485 of 669 probe-mode prefixes decode).
- **2.6b `thePNGPreCheckRequiresIEND`** — `pngStructureIsIntact` of the
  prefix of `rgba8.png` ending right after IDAT's CRC is `false`, and of the
  whole file `true`. Mutation: skip the `IEND` requirement.
- **2.7 `aCorruptPNGIsNil`** — the three corrupt files → `nil`, and every
  single-bit flip of each byte of `rgba8.png`'s IDAT data → `nil`. Mutation:
  skip the CRC check.
- **2.8 `theDimensionCapIsSixteenThousandThreeHundredEightyFour`** —
  `wide-16385x1` → `nil`, `wide-16384x1` → a 16384×1 bitmap (the separating
  arm); **2.8b** `stbi_load_from_memory` of `wide-16385x1` called directly →
  `NULL`; **2.8c** `decodedSizeIsAccepted(width: 16385, height: 1) == false`,
  `(16384, 1) == true`. Mutations (`PX-O` item 3 — either guard alone keeps
  the first arm green): `STBI_MAX_DIMENSIONS` 16385 (lane 1's file, run by
  lane 2 as a mutation only, restored) → 2.8b red; the Swift bound 16385 →
  2.8c red.
- **2.9 `fileAndDataDecodeIdentically`** — `init?(contentsOfFile:)` and
  `init?(data:)` give the same bytes for every fixture; a missing path, a
  directory and empty data → `nil`; the `rgba8.png` prefix ending inside
  `IEND`'s CRC through `data:` → `nil` (stb alone decodes it, `PX-O` item 6).
  Mutation: `data:` skips the pre-check.
- **2.10 `aBundleResourceDecodesOnceAndSharesItsTexture`** — a scratch flat
  bundle directory (`Bundle(path:)`) holding `icon.png` and `Icons/dark/key.png`:
  two calls return the same `texture` (`===`), the subdirectory resolves, a
  missing name → `nil` (twice; *as landed, `PX-T` item 4*: a missing name
  never reaches the cache, so the cached-`nil` arm is an undecodable resource
  replaced by a valid PNG). Mutation: bypass
  the cache → identity differs. (If `Bundle(path:)` of a flat directory does
  not resolve on Linux, record it and use `Contents/Resources`.)
- **2.11 `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles`**
  (`ImageTests`, macOS) — for every PNG fixture except `rgb8-p3`, the decode
  equals a `CGImageSource` + premultiplied sRGB `CGContext` reference (the
  `359444e` body, in the test); `rgb8-p3` **differs** (the separating arm;
  divergence 138's pin). Mutation: route PNG through the ImageIO fallback →
  the P3 arm reddens.
- **2.12 `aTIFFStillDecodesThroughImageIOOnApple`** (`ImageTests`, macOS) —
  a TIFF written by `CGImageDestination` decodes; and in
  `ImageDecodingTests` under `#if !canImport(ImageIO)` (`PC-B`)
  **`aTIFFIsNilOffApple`**. Mutation: drop the fallback → the macOS arm
  reddens.
- **2.13 `aTruncatedJPEGWithAThumbnailIsNil`** — `thumb-truncated.jpg` →
  `nil`; the same file untruncated decodes. Mutation: the design's raw byte
  scan for `FF DA … FF D9` (measured: it passes the truncated file and stb
  returns a zero-padded image, `PX-O` item 2).
- **Existing 3.11** (`ImageTests`, ImageIO PNG decode) — kept, now through
  the portable path; its doc comment updated. If its PNG is colour-tagged and
  its literal moves, that is a finding: record the bytes, do not loosen.

### §4.3 Lane 3 — `.task`

Harness: `makeFakeWindow`, `drawFrameIfNeeded()`, `async @MainActor` tests;
`pumpMainActor(until:maxYields:)` counts `Task.yield()`s (bound 1000); a
`TaskLog` class records lines; cancellation observed through
`withTaskCancellationHandler { await withCheckedContinuation { … } } onCancel:
{ … }` (no long sleeps).

- **3.1 `aTaskStartsInsideTheFirstFrameAfterAnInnerOnAppear`** (`X1`, `X15`)
  — `.onAppear { log("appear") }.task { log("task"); width = 70; await
  Task.yield(); log("after") }`: after the first `drawFrameIfNeeded()` the log
  is `["appear", "task"]`, the scene holds the 70-wide box,
  `lastDrawBuildCount == 2`; after pumping, `"after"` follows. Mutation: start
  with `Task {}` (not immediate) → red.
- **3.2 `aTaskWrittenInsideOnAppearStartsFirst`** (`X1b`) — `.task{}.onAppear{}`
  → `["task", "appear"]`. Mutation: append starts after all appearances.
- **3.3 `siblingsAndParentsStartInReversePreOrder`** (`X9`) —
  `["task child2", "appear child2", "task child1", "appear child1", "task
  parent", "appear parent"]`. Mutation: sort starts ascending.
- **3.4 `theTaskPriorityDefaultsToUserInitiatedAndPassesThrough`** (`X3`) —
  raw priorities `[25, 17, 25, 9, 25]` for default, `.low`, `.high`,
  `.background`, id-form default. Mutation: omit `priority:` in `start`.
- **3.5 `removalCancelsAtItsPlaceInTheDisappearanceOrder`** (`X4`, `X4b`) —
  `.onAppear{}.task{}.onDisappear{}` → `["cancel", "disappear"]`;
  `.onDisappear{}.task{}` → `["disappear", "cancel"]`; the task resumes with
  `Task.isCancelled`. Mutations: cancel in a pass before all disappearances
  (X4b arm red); never cancel (both red).
- **3.6 `anIDChangeCancelsTheOldTaskThenStartsTheNewOne`** (`X5`) — one draw
  after `k = 1`: `["cancel 0", "start 1"]`, then `k = 2` likewise. Mutation:
  start before cancelling.
- **3.7 `theSameIDOrARebuildRestartsNothing`** (`X6`, `X7`) — writing the same
  id and rebuilding for other state start nothing; after the task finished,
  an id change starts it again. Mutation: `isEqual` always false.
- **3.8 `anIDRestartRunsAtItsPlaceAmongOnChangeActions`** (`X12`, `X12b`) —
  `.onChange{}.task(id:){}` → `["change", "start"]`; reversed modifiers →
  `["start", "change"]`. Mutation: put id restarts in the appearance bucket.
- **3.9 `anIfElseSwapStartsTheNewTaskBeforeCancellingTheOld`** (`X14b`) —
  `["appear then", "start then", "disappear else", "cancel else"]`.
  Mutation: run disappearances before appearances (reddens LC tests too).
- **3.10 `aGroupStartsOneTaskWhileItHasContent`** (`X10`) — `ForEach` 0 → 3
  starts one, 3 → 0 cancels it, `runningTaskCount` 1 then 0. Mutation: note
  the scope when `nodes.isEmpty` (`LC-P` item 1's guard dropped).
- **3.11 `hiddenAndTransparentContentStartsItsTask`** (`X8`) — `.hidden()` and
  `.opacity(0)` content starts. Shares `LC-C`'s instrument; mutation: none
  separate (recorded as such — presence code has no visibility branch).
- **3.12 `aTaskUnderARemovalTransitionIsCancelledWhenTheGhostEnds`** (`X16`)
  — `simulateTick(timestamp:)` through a 0.6 s removal: no cancel at the
  removal frame or mid-way, cancel in the first frame after the ghost ends.
  Mutation: never park task cancellations.
- **3.13 `aTaskReinsertedMidRemovalKeepsRunning`** (`X17`) — re-inserted at
  0.15 s: no cancel, no second start, the same task still running. Mutation:
  drop the carry of `running` across the parked key → a second start.
- **3.14 `closingTheWindowCancelsEveryTask`** (`LC-J`, `X11`) — `App` over
  `FakePlatform`, `onClose`: every running task cancelled once, in reverse
  order with `onDisappear`s; a second close finds nothing. Mutation: `closeAll`
  ignores running boxes.
- **3.15 `aHeadlessRenderFrameStartsNoTask`** (`LC-J` item 4) — mutation: run
  the store's events at the end of `renderFrame`'s render.
- **3.16 `theDeferredStartRunsTheBodyOnALaterTurn`** (`PX-G`, divergence 137)
  — with `forcesDeferredStart = true`: after the first draw the log is
  `["appear"]`, after pumping `["appear", "task"]`, and its write is presented
  by the next `drawFrameIfNeeded()`. Mutation: ignore the seam.
- **3.17 `aTaskCarriesSwiftUIsDefaultName`** (`X13`) — `Task.name ==
  "View.task @ MetalUITests/TaskModifierTests.swift:<line>"`, and a given
  `name:` wins. Mutation: pass `nil` as the name.
- **3.18 `aStateWriteInTheSynchronousPrefixReachesItsOwnOccurrence`** (`ID-F`)
  — one element value placed twice, each `.task` writes its own `@State` in
  its prefix: each occurrence shows its own value. Mutation: run starts
  outside `StateDispatch.dispatching`.
- **3.19 `taskScopesCostWhatLifecycleScopesCost`** (`LC-M`) — K task scopes:
  `lastFrameWork == 3K` steady, 0 with none. Mutation: an extra store visit
  per running box.
- **Guard 3.G1 `theTaskSpellingsTypecheckFromAnExternalModule`**
  (`typecheckFile`, plain `import MetalUI`, `SA-P`) — every spelling, and a
  closure that calls a `@MainActor` model method synchronously and captures a
  non-`Sendable` value. Mutation: remove `@_inheritActorContext` → red.
- **Guard 3.G2 `aLegacyDecorationAfterATaskModifierDoesNotCompile`**
  (negative; divergence 120). Mutation: a temporary `onClick` forwarding
  extension on `LifecycleScope` → the guard reddens.
- **Guard 3.G3 `aTaskIDMustBeEquatable`** (negative). Mutation: drop the
  `Equatable` constraint.
- **SDL 3.20 `aTaskModifierProgressesAndIsCancelledUnderSDLPlatform`**
  (`SDLMainQueueDrainTests`, launches `MainQueueDrainCheck task-modifier`,
  `.enabled(if: windowsPresentFrames, "the offscreen video driver presents no
  window frame")`) — prints `task started=true steps=3 cancelled=true`.
  Mutations: `closeAll`/disappearance cancel removed → `cancelled=false`;
  `Task` instead of `Task.immediate` → recorded (macOS's Cocoa pump may still
  run it; say which).
- **SDL 3.21 `anImmediateMainActorTaskResumesAndSeesItsCancellationUnderTheSDLLoop`**
  (mode `immediate-task`, **ungated**, runs in the Linux container) — prints
  `task started=true steps=3 cancelled=true`. Mutation: delete
  `drainMainQueue()`'s call in `SDLPlatform.run` → the container run prints
  `steps=0` (`SV-H`'s separating run); record the macOS result too.

- **3.22 `aTernaryThatSwapsATaskForAnotherLifecycleModifierStartsAndCancelsIt`**
  (`PX-U` item 2; added by lane 3 after its mutation pass) — `flag ?
  x.task {} : x.onAppear {}`: becoming a task starts it, stopping cancels it.
  Mutations: no start when a key becomes a task (M3.22a); no cancel when it
  stops (M3.22b).

New `MainQueueDrainCheck` helpers that create an `SDLPlatform` arm
`armMainRunLoopExitCheck()` where the test helpers do; every C enum
`rawValue` converted explicitly. (Amended by `PX-U` item 3: the check
executable arms nothing — the `atexit` guard is for a test process and would
fail the executable's intended exit; the launching test creates no
`SDLPlatform`; the new modes use no C enum.)

## §5 CI and commands

1. **`swift.yml`**: unchanged jobs; the root builds without traits everywhere
   (`scene-linux` and `root-windows` keep passing with no SDL installed — the
   separating run for `PX-H` item 3).
2. **`sdl-gpu-linux.yml`**: the `record` job replaces `pkg-config` with
   `-Xcc -I$(brew --prefix)/include -Xlinker -L$(brew --prefix)/lib` on
   `swift run Replay`; the Linux job's container command stays flagless (the
   image's new layout) and **adds** `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1 swift
   test --filter aCrossPlatformPackage --scratch-path /tmp/root` from `/work`
   (`git config --global --add safe.directory '*'` first); the Windows job's
   `-Xcc`/`-Xswiftc` flags keep their shape, AccessKit's from
   `fetch-accesskit.py --print-flags`. The `paths:` filters gain
   `Package.swift` and `Sources/CStbImage/**`.
3. Local container runs: `docker build -t metalui-portable -f
   Backends/SDL/linux/Dockerfile Backends/SDL`, then the task's flagless
   `docker run … -w /work/Backends/SDL metalui-portable bash -c 'swift build
   --build-tests --scratch-path /tmp/build && swift test --skip-build
   --scratch-path /tmp/build'`; from a worktree, also mount the repository's
   common git directory at its own absolute path if a step needs git.

## §6 Demo expectation

No demo change (`PX-N`): `docs/probes/demo-pixels/compare.sh <scratch> 359444e
HEAD` reads **0 differing pixels in all fourteen images** after every lane;
`Expected.swift` unedited (Linux/Windows CI confirm on push).

## §7 Human checks — group X (lane 3 writes it; an agent cannot run it)

- **X1** On a Linux desktop (Ubuntu 25.10 or a distribution with SDL 3.4+):
  `metalui new Hello --cross-platform` (URL default), install per the README,
  `swift run Hello` — a window opens and draws; text is legible; resizing
  works.
- **X2** In that app, a `Text("\(n)")` with `.task { while !Task.isCancelled
  { n += 1; try? await Task.sleep(for: .seconds(1)) } }` counts once a second
  in a real SDL window on Linux and on Windows, and stops when a toggle
  removes it (and restarts from 0 when it returns).
- **X3** Orca reads the window's controls with the `AccessKit` trait; with
  `--no-accesskit` the app runs and Orca sees an unlabelled window.
- **X4** The same generated app built on Windows per its README.
- **X5** The configurator's icons (light and dark) on Linux look as on macOS.

## §8 Migration notes and records owed

### §8.1 Migration (lane 3 writes `docs/migration.md`; the Record phase, CLAUDE.md)

- `ImageBitmap(contentsOfFile:)` decodes PNG and JPEG with MetalUI's own
  decoder on macOS too: colour-tagged files are no longer converted
  (divergence 138), a truncated or corrupt PNG is `nil` where ImageIO returned
  a partial image, JPEG bytes may move by up to 2. Other formats still go
  through ImageIO on macOS.
- `metalui new --cross-platform` works without `--local`; generated
  manifests name `MetalUISDL` from the MetalUI package with
  `traits: ["SDL", "AccessKit"]` on Linux/Windows; regenerate or edit an
  existing one (delete the `Backends/SDL` path dependency).
- `Backends/SDL` on macOS builds with flags (`fetch-accesskit.py
  --print-flags`), not `PKG_CONFIG_PATH`; CLAUDE.md's build line changes.
- `.task` exists (divergence 137 on macOS 14–25).

### §8.2 Registry rows lane 3 writes for lane 2 (text owed)

- Map rows (`closeout-inventory-map.tsv`, class `M`): `ImageBitmap.init?(data:)`
  — "MetalUI-only: SwiftUI's images come from CGImage/NSImage/asset
  catalogs; PX-E"; `ImageBitmap.init?(resource:withExtension:subdirectory:
  bundle:)` — "MetalUI-only; SwiftUI's Image(_:bundle:) reads asset catalogs,
  not loose files (probe swiftui-bundle-image B0–B6); PX-E". `task` (both,
  class `A`): "SwiftUI's View.task, name/priority/file/line; PX-F;
  divergence 137".
- Divergence **137** — "`.task` on macOS 14–25 starts its body on the next
  main-queue turn (no `Task.immediate` before macOS 26): a write before its
  first `await` is presented one frame late. SwiftUI on macOS 27 starts it
  synchronously (probe swiftui-task X1, X15); SwiftUI on macOS 14–26.3 (its
  pre-26.4 `_TaskModifier`) was not measured (`PX-R` item 3). Pinned by
  `theDeferredStartRunsTheBodyOnALaterTurn`. Ruling PX-G."
- Divergence **138** — "Image decoding ignores colour profiles (iCCP, gAMA,
  cHRM): samples are drawn as sRGB, identically on every platform; SwiftUI
  draws what ImageIO decodes, colour-managed (probe image-decoder-parity: P3
  max 87, gAMA max 19; JPEG max 2). Pinned by
  `thePortableDecoderMatchesImageIOOnUntaggedAndSRGBFiles` (its P3 arm).
  Ruling PX-C."
- Not offered: `Image(_:bundle:)` / `Image(decorative:bundle:)` — "asset
  catalogs; use `ImageBitmap(resource:…)` with `Image(_:scale:label:)`;
  PX-E"; `.task(name:executorPreference:priority:…)` — "PX-A".

### §8.3 Owed to the Record phase (files this branch's lanes may not edit)

- CLAUDE.md/AGENTS.md: the `Backends/SDL` build line (`PX-I` item 6), the
  `PX-` prefix row, a rule sentence each for images, `.task` and the traits,
  `LC-L`'s line in the Lifecycle paragraph ("`.task` is deferred" → built),
  counts.
- **Refuted claim, fix everywhere it was copied**: "`.task(id:)` starts the
  new task, then cancels the old" — `LC-L` (lifecycle decisions),
  `swiftui-lifecycle.swift`'s K1/K2 reading note, record §76 wherever it
  quotes it. `X5` shows cancel-then-start (`PX-F`).
- Record §80; `docs/record/README.md` row; record §04 sections for 137 and
  138; the plan is untouched (not a plan task).

## §9 Deferred (each with reason and owner; `PX-A`)

| item | reason | owner |
|---|---|---|
| Colour management (iCCP/gAMA/cHRM) | needs a vendored ICC engine; divergence 138 | none |
| `Image(_:bundle:)`, asset catalogs, `@Nx` variants, template tint | SwiftUI's spelling means an asset catalog (`PX-E`); MG-10's second half | none |
| `.task(…executorPreference:…)` | macOS 26.4 `TaskExecutor` variants; no demand | none |
| Frames under SDL's offscreen driver | needs an offscreen renderer per window; would ungate 10.2/10.3/3.20 — until then 3.20 runs in **no CI job** (macOS CI skips `Backends/SDL`); lanes record its macOS line in record §80 (`PX-R` item 4) | none |
| `MetalUISDL` in the public-API census | backend plumbing (`PX-K`) | none |
| A generated app built on Windows in CI | the backend builds and tests there; human check X4 | none |
| GIF/WebP/TIFF/HEIC/BMP off Apple | no demand; ImageIO keeps them on macOS | none |

## §10 Must not move (checked by every lane)

Identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`,
`MC-A`/`MC-C`/`MC-P`, `.id()` outermost), hit testing, accessibility (with the
`AccessKit` trait on, every AccessKit test unchanged), animation, focus,
`List` windowing and `TB-AH`, `Deferred`, text input; 0 px in all fourteen
images; `Expected.swift` unedited; 0 `warning:` on both build systems;
`MetalUILayout` imports only `MetalUICore`; `MetalUIScene` imports only
`MetalUIShaderTypes`; `Backends/SDL` and a `swift:6.4-noble` container build;
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green; no shader change.
