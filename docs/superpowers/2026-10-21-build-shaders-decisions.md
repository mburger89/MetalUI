# Build-time app shaders (S12) — decisions

Rulings for item S12 of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), requested by MetalCreator
(developer session, 2026-10-21) as XP-G20 (wanted, not blocking). Prefix `BS-`. **Next unused: `BS-M`.**
Spec: [`specs/2026-10-21-build-shaders-design.md`](specs/2026-10-21-build-shaders-design.md). Record: `../record/138-build-shaders.md`.
Branch `feat/build-shaders` from `11dca65e`. Continues `GA-F`/`GA-Q` (record 114) and `GB-` (record 137).
Divergence labels reserved 675–684: **none taken** (`BS-A`). **Nothing is published** by this item (`BS-H`).

Sources of truth. SwiftUI has no GPU or shader-build API, so no SwiftUI claim is made and no probe is owed; gpui compiles its
Metal shaders in a `build.rs`, a build-time step of the crate itself (recalled; the source is not on this machine), which is
the shape MetalCreator asks for, context only. Plugin facts below were **measured on this Mac** (Swift 6.4, SwiftPM 6.4,
2026-10-21, a scratch package under the session scratchpad: a build-tool plugin and a command plugin both running `/usr/bin/python3`).

## BS-A — class M, no divergence, no census row

**Ruling.** The plugin product, the tool and every new library member are MetalUI-only (class M). `Backends/SDL` is outside the
census (`GA-L`); the root-package plugin product is checked against the inventory tooling by the lane (a plugin is not a
`public` Swift declaration, so none is expected). **Cost if wrong.** A map row.

## BS-B — a command plugin over one Swift tool; no python in the path

**Question.** Build-tool plugin, command plugin, or both; and can either run the existing `compile-app-shaders.py`?
**Measured.**
1. `context.tool(named: "python3")` **failed** ("Plugin does not have access to a tool named 'python3'") although
   `/usr/bin/python3` and Homebrew's are on `PATH`; an absolute `/usr/bin/python3` ran. So a plugin cannot find python the
   portable way, and Windows has no `python3` name at all (`python`/`py`).
2. A build-tool plugin's process **does** see the build's environment (`PATH`, and a caller-set `SHADERCROSS=/x`).
3. The macOS sandbox **denies** a write outside the plugin work directory and the temp directories
   (`PermissionError: Operation not permitted` writing under `$HOME`); a prebuild command's outputs landed in
   `.build/plugins/outputs/<pkg>/<target>/destination/<Plugin>/out/`, **not beside the executable**, which is where `GA-F`'s
   `locate` looks first. They reach an app only as a resource bundle (`<Package>_<Target>.bundle`), a place `locate` does not look.
4. A command plugin run as `swift package compile-shaders` is refused without `--allow-writing-to-package-directory` and with it
   writes into the source tree (`written` appeared); no sandbox surprise.
**Ruling.** (a) **One implementation, in Swift**: an executable target `MetalUICompileShaders` over a portable library
`MetalUIShaderCompile` (Foundation only, no Apple framework: the plan, the shadercross lookup, the marker, the arguments), declared
in the root manifest by path into `Backends/SDL/Sources/`, **outside the `SDL` trait** (it needs no SDL to compile shaders) and
in the portable list (`PC-A`). A plugin cannot run python portably (1), so the script's logic is **ported, and
`compile-app-shaders.py` is deleted** (one implementation, as asked); the checked-in `SOURCE.sha256` of
`Backends/SDL/Tests/AppShaders/compiled` is the parity oracle (test 4). (b) A **command plugin** `CompileShaders`
(verb `compile-shaders`, product `CompileShaders` exported by the root package) resolves the tool with `context.tool(named:)`
(an executable target, found by SwiftPM, not by PATH) and passes `--source`/`--out`/`--shadercross` through; `--out` is required (no default location is guessed). Whether
SwiftPM lets a package that depends on MetalUI by URL or path invoke the dependency's command plugin (`swift package
compile-shaders`) is **unmeasured**; the lane measures it and records the answer, the documented fallback that is certain being
`swift run --package-path <checkout> MetalUICompileShaders …`. **Cost if wrong.** The tool alone serves.

## BS-C — shadercross is found by flag, then `METALUI_SHADERCROSS`, then `PATH`; its `lib` joins the loader path

**Ruling.** Order: `--shadercross`, the `METALUI_SHADERCROSS` variable, then a `PATH` search for `shadercross`
(`shadercross.exe` on Windows). A missing one is an error naming all three. The archive's `lib` directory beside `bin` joins the
loader path for the child (`DYLD_LIBRARY_PATH`/`LD_LIBRARY_PATH`; Windows finds DLLs beside the exe), as the script did.
`METALUI_SHADERCROSS` is a new variable named in `docs/packaging.md`. **Cost if wrong.** A flag spelling.

## BS-D — a build-tool plugin is carried

**Ruling.** Not built now. Reasons from the measurements: its outputs land in the plugin work directory and a resource bundle
(3), so `locate` would need a third candidate and the app a `Bundle` lookup; a build-tool plugin that needs an external
shadercross **fails every `swift build` of every consumer that lacks it** unless it degrades silently, which hides a stale
shader; and the repository publishes no pinned shadercross (`BS-H`), so the tool is not reachable the way a binaryTarget needs.
Owner: the follow-up after the user decides on publishing a pinned artifact. **Cost if wrong.** An app runs one command
(`swift package compile-shaders`, or a build-phase script) instead of getting it from `swift build`.

## BS-E — a marker-free build product is accepted; a marker, where present and given sources, still catches a stale blob

**Question.** `SDLGPUShaderLibrary(directory:)` requires `SOURCE.sha256` (`GA-Q`'s staleness detector for checked-in blobs);
a build product built on the spot is never stale. What is the rule?
**Ruling.** A directory counts when it holds `SOURCE.sha256` **or** at least one `NAME.<vert|frag|comp>.json` reflection file
(what the compiler writes last for a stage); today's checked-in directory is accepted exactly as before and the error still
names `SOURCE.sha256`. A new `init(directory:verifyingSources:)` takes the source directory: **with a marker present it throws a
named error on any source whose SHA-256 differs from its line, or that has no line, or a line with no source**; without a
marker the check is skipped (nothing to compare), without `verifyingSources` nothing is read. The tool still writes the marker
by default (`--no-marker` omits it), so an app that keeps both gets the check for free. **Cost if wrong.** An empty directory with
a stray `.json` would be accepted; a stage lookup then fails by name (`… is missing`), as today.

## BS-F — the pin is documented, not published

**Ruling.** `docs/packaging.md` §4a names the pin MetalCreator uses, **SDL_shadercross at commit
`1ff05bec573988a98ef9e0260b4da44f512b8367`** (upstream has no release or tag, checked 2026-10-21 by the requester), and says
how to build it on macOS, Linux x86_64, Linux aarch64 and Windows. Its dependencies (SDL3, DirectXShaderCompiler for DXIL,
SPIRV-Cross, SPIRV-Tools/Headers via submodules) are **recalled, not verified**: the lane reads the pin's `.gitmodules` and
CMake and corrects the text. **DXC ships for Linux x86_64 and Windows only**, so on aarch64 Linux the working path is
SPIR-V and MSL without DXIL (the tool then must not require `.dxil`: it takes `--formats spv,msl,dxil,json`, default all; a
Vulkan/Metal app needs no DXIL) or the amd64 image under emulation, which the requester runs; the lane measures which of
these works in the `metalui-portable` image if a build fits in reasonable time, else records it **unmeasured**.
`SDLGPUShaderLibrary` already needs only the blob of the driver asked for, so a library without `.dxil` works on Metal and
Vulkan (pinned, test 12). **Cost if wrong.** A doc correction.

## BS-G — no CI job that builds shadercross

**Ruling.** Carried. Building the pin means SDL3, DXC (hundreds of MB) and SPIRV-Cross, minutes of CPU per job and a cache
to maintain, to prove what an env-gated test already proves wherever a shadercross exists. If the lane measures a Linux build under
ten minutes with a cache it **may** add a job that builds the pin and compiles `Backends/SDL/Tests/AppShaders`, publishing
nothing and uploading no artifact; otherwise it records the time and leaves it. Owner: the publish decision. **Cost if wrong.** A
shadercross regression is seen by an app, not CI.

## BS-H — publish nothing

**Ruling.** No release, tag, package, image or registry push, no CI that publishes. A pinned prebuilt shadercross is the user's
decision, to be asked after this item. **Cost if wrong.** None; it only defers.

## BS-I — SHA-256 is one pure-Swift function in `MetalUIShaderCompile`, shared by the tool and the library

**Question (critic finding).** The spec's marker (tool) and `verifyingSources` (library) both need SHA-256, but Foundation has none
off Apple (CryptoKit is Apple-only), `MetalUIShaderCompile` imports only Foundation, and no Swift SHA-256 exists in the tree (checked:
the only hits are the C single-instance file and test strings). **Ruling.** A small FIPS 180-4 implementation `SHA256.hexDigest(of:)`
lives in `MetalUIShaderCompile` (no dependency, no CryptoKit, no swift-crypto package); `MetalUISDLGPU` imports that module (an edge
added in **both** manifests, root and `Backends/SDL`, since the root declares the target by path). Pins: `sha256MatchesTheNISTVectors`
(empty, "abc", the 56-byte two-block message, 55/56/63/64/65-byte padding boundaries, one million "a") plus test 4 against the python
script's checked-in output; mutations: wrong rotation constant, no length padding byte, endianness of the length. Ordering of marker lines
is **bytewise on the file name** (the script's `sorted(Path)`; Swift's `<` on String is Unicode-aware), pinned by test 4 with a
non-ASCII-sensitive pair added to the fixture list in test 2. **Cost if wrong.** A hash helper moves.

## BS-J — documentation sweep (critic finding)

Deleting `compile-app-shaders.py` also owes edits to every live reference, not only packaging/migration/READMEs:
`docs/guides/cross-platform.md:191`, `docs/guides/drawing-and-gpu.md:183` (prose lines; any `swift` block stays byte-identical so no mirror
moves, `GuideDocCheck` run), `Backends/SDL/Tests/MetalUISDLTests/SDLGPUTestSupport.swift:10` and `SDLGPUShaderLibrary.swift` doc comments.
Frozen record files and older specs keep the old name (history). CLAUDE.md/AGENTS.md change at the Record phase only.

## BS-K — what the lane measured and corrected (2026-10-21)

**Measured on this Mac** (Swift 6.4, SwiftPM 6.4).
1. **A package that depends on this checkout by path reaches the command plugin**: `swift package compile-shaders` ran from a fixture
   package, was refused without `--allow-writing-to-package-directory`, and with it wrote blobs and the marker into the fixture
   (`theCompileShadersPluginRunsOnAFixturePackage`, with a stub shadercross). Whether a dependency **by URL** is reached the same way is
   still unmeasured (it uses the same SwiftPM graph; human check BS3); the tool (`swift run --package-path .build/checkouts/MetalUI
   MetalUICompileShaders`) is the documented certain fallback.
2. **The plugin passes `--base <package directory>`** so relative `--source`/`--out` resolve against the package, not SwiftPM's
   working directory; `--base` is a pure field of `CompileArguments` (`noMarkerIsParsed`).
3. **Corrections to `BS-I` and the spec.** (a) `MetalUIShaderCompile`'s declarations are **`package`**, so no library product is exported and
   `Backends/SDL/Package.swift` needs **no** edge: `MetalUISDLGPU` is declared by the root manifest, where the edge (`"MetalUIShaderCompile"`)
   was added; the SDL package's test target reaches the library only through `MetalUISDLGPU`. (b) **Swift's `<` on `String` equals the
   UTF-8 byte order for every pair except canonical equivalents**: U+00E9 against `z` does not separate the two orders, U+212B (canonically
   U+00C5) against U+00C6 does; test 4 uses that pair and mutation 4d (a Unicode-aware sort) reddens it, which the first fixture did not.
4. **Out of scope of the spec, kept:** a source needs a non-empty stem (`.vert.hlsl` is not a source); `--help`; exit 2 for a usage error.

## BS-L — shadercross at the pin, built and run (macOS arm64, 2026-10-21)

**Measured.** SDL_shadercross `1ff05bec573988a98ef9e0260b4da44f512b8367` (committed 2026-09-03) builds on this Mac with
`cmake -G Ninja -DSDLSHADERCROSS_VENDORED=ON` against Homebrew's SDL3: a full build **including DirectXShaderCompiler** (the
libsdl-org fork, branch `1.8.2502-SDL`, 1303 ninja steps) took **8 min 30 s of wall clock at -j8 on a loaded 10-core machine**, far
below the "hours" the spec recalled (`BS-F`'s guess is corrected in `docs/packaging.md`). The submodules need `git submodule update --init
--depth 1` for SPIRV-Cross, SPIRV-Headers, SPIRV-Tools **and** DirectXShaderCompiler (and DXC's own nested ones): **the configure step requires the
DXC checkout even with `-DSDLSHADERCROSS_DXC=OFF`** (the check precedes the option), and with it off the CLI cannot compile HLSL at all,
but SPIR-V to MSL and JSON works: the CLI built that way in **14 s of build time** and reproduced the checked-in `.msl` and `.json` of
`tri.vert`, `tri.frag` and `append.comp` byte for byte from the checked-in `.spv`. `cmake --install` places `bin/shadercross` and
`lib/libdxcompiler.dylib`, `libdxil.dylib`, `libspirv-cross-c-shared.dylib` beside it: the layout `BS-C`'s loader-path rule expects.
**End to end:** `MetalUICompileShaders --source Backends/SDL/Tests/AppShaders --out <dir>` with that shadercross (`METALUI_SHADERCROSS`) wrote
**41 files byte-identical to the checked-in `compiled` directory** (`diff -r` empty: SPIR-V, MSL, **DXIL**, JSON and `SOURCE.sha256` for all ten
sources), 3 s, and `anEnvGatedRunCompilesAFixture` passed. So the python script's outputs are reproduced exactly by the Swift port at the pin.
**Cost if wrong.** None; a measurement.

## BS-G amended — the CI job stays carried

The lane measured a Mac build at 8.5 minutes with every dependency, uncached, which is inside "reasonable" for a manual run and over what
a per-push job should pay (no cache exists to restore, and a cache is a publishing-adjacent artifact store). **Ruling stands: no CI job**
(`BS-G`); the recipe in `docs/packaging.md` is the supported path and `METALUI_SHADERCROSS` gates the one test that needs it. Owner: the publish decision.
