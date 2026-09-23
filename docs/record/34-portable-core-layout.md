# 34 — Core and layout off macOS, 2026-09-23

Branch `feat/portable-core-layout`, from `feat/portable-font-resolver` (PR
#15, record §33). Spec: `docs/superpowers/specs/2026-09-23-portable-core-layout-design.md`,
rulings `PC-A`…`PC-C` (next `PC-D`). Roadmap item 5.

## What changed

- `Package.swift`: portable targets declared everywhere, Apple-bound ones
  under `#if os(macOS)` (`PC-A`).
- `MetalUILayoutTests`: WebKit and `malloc_logger` pieces compiled out off
  Apple platforms per declaration; the fixture listing moved to
  `FileManager` (`PC-B`).
- `MetalUITestSupport.modulesDirectory`: this platform's triple only
  (`PC-C`).
- CI: `scene-linux` builds and tests the whole root package; `root-windows`
  added.

## Measured

| Step | Result |
|---|---|
| first Linux run (`swift:6.4-noble`, aarch64, macOS worktree mounted) | `GeneratorTests.swift:306` did not compile (`URL?` elements); `UnitSafetyTests`' guards found the macOS `.build` and failed |
| `compactMap` to `URL?` | Linux Foundation's element is `NSURL` — a second compile error |
| `FileManager` listing; host-triple filter | **486 + 22 tests pass**, no warnings |
| mutation: `import CoreText` in `MetalUILayout` | Linux build fails: `no such module 'CoreText'` |

**Windows CI's first run** failed to compile 13 call sites of `usleep(1000)`
— a poll while a large-stack `Thread` finishes, in `LayoutContextTests` and
`NativeDepthGuardTests` — because Windows has no `usleep`. They now call
`waitUntilFinished(_:)`, a synchronous `Thread.sleep` loop (synchronous
because `Thread.sleep` is unavailable in the async exit-test bodies that
call it, and a direct call there warns).

The macOS suite is unchanged (1681; the guards compiled out are
`canImport`-true on macOS). Windows is measured by CI only.

## Counts

macOS: **1681** (unchanged), 97 goldens, 77 guards. Linux: 486 + 22.
