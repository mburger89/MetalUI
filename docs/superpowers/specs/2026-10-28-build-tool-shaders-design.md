# App shaders on `swift build` (BS-D) - design

**Status:** designed, not built. Rulings: [`../2026-10-28-build-tool-shaders-decisions.md`](../2026-10-28-build-tool-shaders-decisions.md) (`BT-A`...`BT-M`). Record: `../../record/161-build-tool-shaders.md` (Record phase).
Branch `feat/build-tool-shaders` from master `abc2bf46`. Item `BS-D` (carried by record 138; user said go, 2026-10-28). **Supersedes `BS-D`.**
Class `M`, MetalUI-only (no SwiftUI claim, no probe). Divergence labels 895-904 reserved, **none taken**. **Nothing published** (`BS-H`; user decision: no published shadercross).
No `Sources/` change outside the plugin; no `Handlers`, seam, shader, `Window`, `PlatformWindow`, scaffold or Jotter change.

## 1. Behaviour

An app target that applies `CompileShadersOnBuild` gets its `Shaders/*.hlsl` compiled on plain `swift build` into a `MetalUIAppShaders`
directory inside the target's resource bundle (`Bundle.module`), found at run time by
`SDLGPUShaderLibrary.locate(resourceBundle: .module)`:

```swift
// Package.swift of the app
.executableTarget(name: "App",
                  dependencies: [.product(name: "MetalUISDLGPU", package: "MetalUI")],
                  plugins: [.plugin(name: "CompileShadersOnBuild", package: "MetalUI")])
// Sources/App/Shaders/blur.comp.hlsl, Sources/App/Shaders/compiled/ (optional, checked in)
let shaders = try SDLGPUShaderLibrary.locate(resourceBundle: .module)
```

| shadercross (`METALUI_SHADERCROSS`, else `PATH`) | `Shaders/compiled/` | Result |
|---|---|---|
| found | any | compile all four formats + marker into the bundle; warn if a checked-in marker is stale |
| variable names a missing file | any | **build fails** (`BS-C`) |
| not found | marker matches, each source has `.json` + `.spv` | copy those blobs + marker into the bundle |
| not found | stale or missing marker, missing blob, no directory | **build fails** naming the problems, the pin, and both fixes |

A target applying the plugin with no `Shaders/` or no source: no command, one plan-time warning, build succeeds. A target not applying it: untouched.

## 2. Files

### 2.1 `Plugins/CompileShadersOnBuild/Plugin.swift` (new)

`@main struct CompileShadersOnBuild: BuildToolPlugin`. `createBuildCommands(context:target:)`:

- `guard let target = target as? SourceModuleTarget` else `[]`.
- `shaders = target.directoryURL/Shaders`; list it with `FileManager` (not `sourceFiles`, so the rule holds whether or not the app excludes the
  directory). Sources = names that look like `NAME.<vert|frag|comp>.hlsl` (re-checked by the tool; the plugin only needs inputs). None ->
  `Diagnostics.warning("CompileShadersOnBuild: no NAME.<vert|frag|comp>.hlsl in <path>; nothing to compile")`, return `[]`.
- `compiled = shaders/compiled`; its regular files (if any) are inputs too (`BT-E`).
- Environment: `METALUI_SHADERCROSS` (or `""`), `PATH` looked up **case-insensitively** (or `""`).
- `out = context.pluginWorkDirectoryURL/MetalUIAppShaders`.
- One `.buildCommand(displayName: "Compiling or verifying N app shader(s) for <target.name>", executable: context.tool(named: "MetalUICompileShaders").url,
  arguments: ["--on-build", "--source", shaders.path, "--checked-in", compiled.path, "--out", out.path, "--environment-shadercross", v1,
  "--environment-path", v2, "--display-source", <shaders path relative to the package, e.g. Sources/App/Shaders>],
  inputFiles: sources + compiled files, outputFiles: [out])`.

`--display-source` only feeds the error and warning text (so the fix names a path the user can paste; `context.package.directoryURL` is the base).

### 2.2 `Package.swift`

Product `.plugin(name: "CompileShadersOnBuild", targets: ["CompileShadersOnBuild"])` beside `CompileShaders` (portable list, `PC-A`); target
`.plugin(name: "CompileShadersOnBuild", capability: .buildTool(), dependencies: ["MetalUICompileShaders"], path: "Plugins/CompileShadersOnBuild")`.
`Backends/SDL/Package.swift` is untouched (it declares neither plugin).

### 2.3 `MetalUIShaderCompile` (all `package`)

- `CompileArguments`: a `mode` (`.compile`, the default and today's behaviour byte for byte; `.onBuild`), `checkedIn: String?`,
  `environmentShadercross: String?`, `environmentPath: String?`, `displaySource: String?`. `--on-build` requires `--checked-in` and both
  `--environment-*` flags (empty string allowed); `--on-build` with `--shadercross`, `--formats` or `--no-marker` is a usage error (the build arm is
  fixed: all formats, marker written). Usage text gains the second form.
- `ShadercrossPin.commit = "1ff05bec573988a98ef9e0260b4da44f512b8367"` (new file).
- `BuildDecision` (new file, pure):
  ```swift
  package enum BuildDecision: Equatable {
      case compile(shadercross: String, staleCheckedIn: [String])      // problems for the warning, empty when none or no marker
      case copy(files: [String])                                       // names inside compiled/, marker included, sorted bytewise
      case fail(lines: [String])                                       // each printed as "error: <line>"
  }
  package static func decide(located: Result<String, ShaderCompileError>?,   // nil = not found anywhere
                             sources: [(name: String, bytes: [UInt8])],
                             checkedIn: [String]?,                           // nil = no compiled/ directory
                             marker: String?, displaySource: String) -> BuildDecision
  ```
  `located` is built by the runner: `ShadercrossLocator.locate(flag: nil, environment: ["METALUI_SHADERCROSS": v1, "PATH": v2], ...)`;
  "not found" (the locator's `shadercross not found` error when the variable is empty) maps to `nil`, **a variable naming a missing file stays
  `.failure`** and decides `.fail` with the locator's message. The fail text is `BT-F` 4's, with `displaySource` substituted and one line per
  `SourceMarker.problems` entry or completeness problem (`<stem>.json is missing in compiled/`).
- `ShaderCompiler.runOnBuild(_:environment-free, fileExists:runner:log:)`: removes and recreates `out`, computes the decision, then `.compile` ->
  existing `run` with `formats` all and marker on (plus the warning line on stderr when `staleCheckedIn` is non-empty), `.copy` -> copies the
  files and logs `Verified N checked-in shader(s) against SOURCE.sha256 (no shadercross): <out>`, `.fail` -> throws a `ShaderCompileError` whose
  description is the lines joined by `"\nerror: "`.
- `main.swift`: dispatches on the mode; error printing is unchanged (`error: ` prefix, exit 1).

### 2.4 `Backends/SDL/Sources/MetalUISDLGPU/SDLGPUShaderLibrary.swift`

- New `public static func locate(directoryName: String = "MetalUIAppShaders", resourceBundle: @autoclosure () -> Bundle?, sourceTree: URL? = nil) throws -> SDLGPUShaderLibrary`, doc comment per `BT-H` (order, laziness, why).
- Internal: `candidates` returns lazy candidates `[() -> URL?]` (beside the executable; the bundle's `url(forResource:withExtension: nil)` else
  `resourceURL` + name; source tree); `locate(from:)` evaluates in order and names every directory it **evaluated** in the error (a bundle never
  evaluated is not named). The existing public `locate(directoryName:sourceTree:)` forwards with no bundle: behaviour and error text unchanged.
- The type's doc comment names the build-tool plugin beside the command plugin.

### 2.5 Docs (implementation lane)

- `docs/packaging.md` 4a: replace the "not offered (`BS-D`)" paragraph with the build-tool recipe (manifest line, `Shaders/` layout, the table of
  section 1, `locate(resourceBundle: .module)`, shipping: copy `MetalUIAppShaders` from the bundle beside the executable, or ship the resource
  bundle as the root's `MetalUI_MetalUIRender.bundle` is shipped; the same-path shadercross limit), and the Verified/Unverified lines.
- `docs/getting-started.md`: one paragraph pointing at 4a (no `swift` block unless it is mirrored; `DG-` rules apply only to `docs/guides`).
- `docs/guides/drawing-and-gpu.md` / `cross-platform.md`: one prose sentence if they describe the command plugin as the only path (no `swift`
  block change; run `GuideDocCheck`).
- `docs/verification/human-checks.md`: group `BT`: `BT1` a Windows consumer build, both arms (PATH spelling, DLLs, CRLF); `BT2` a dependency **by
  URL** applying the plugin; `BT3` a shipped macOS `.app` finding the directory in its resource bundle.
- `docs/superpowers/2026-10-21-build-shaders-decisions.md`: `BS-D` marked superseded (done in this design commit).
- Record 161, the `BT-` rule in `CLAUDE.md` (+ `cp CLAUDE.md AGENTS.md`), the prefix row and the env-gated count: Record phase.

## 3. Tests

As `BT-L` 1-13. The always-run ten are in `MetalUIShaderCompileTests` (root, every platform: they run on Linux and Windows CI). 11-12 are in
`Backends/SDL` (macOS run by the lane and the Linux image; macOS CI does not run them). 13 is env-gated (`METALUI_RUN_BUILD_PLUGIN_TEST=1`; a cold
build of the tool, minutes) and **counts while skipped**: the env-gated tally in `CLAUDE.md` grows by one at the Record phase. Each mutation is
applied in an isolated worktree when another agent is live, the reddened tests named in the record, with the spelling it was applied to.

Expected count: root +11 (ten always-run, one gated), `Backends/SDL` +2 (re-measure per the counting rules; never trust this line).

## 4. Out of scope

`BT-K`: fetching or building shadercross from the plugin, a CI shadercross job, per-app formats on build, rerunning on an in-place shadercross
update, Windows verification.
