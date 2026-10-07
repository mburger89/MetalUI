# 80 — A MetalUI app on Linux and Windows: portable images, `.task`, a consumable SDL backend (design)

Branch `feat/portable-app` from `359444e` (master: port gaps, medium, merged,
PR #50). **Not a plan task**: user request 2026-10-02, an item of the gpui-gap
priority list — what the SMK configurator needs to run on Linux and Windows.
Spec `docs/superpowers/specs/2026-10-07-portable-app-design.md`; rulings
`PX-A`…`PX-N` in `docs/superpowers/2026-10-07-portable-app-decisions.md`
(next unused `PX-O`); probes `docs/probes/swiftui-task.swift`,
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
