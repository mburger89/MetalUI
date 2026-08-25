# MetalUI

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) but written as
idiomatic Swift. macOS and iOS.

## Start here

- **Design spec (binding authority):** `docs/superpowers/specs/2026-08-24-metalui-design.md`
- **Decisions taken during execution:** `docs/superpowers/2026-08-25-m0-decisions.md`,
  `docs/superpowers/2026-08-25-m1a-decisions.md` — each ruling with its reasoning
  and what it costs if wrong. Read the "Carried to..." sections before starting new work.

## Practices

**`docs/practices/verifying-tests-can-fail.md` — read this before writing tests.**

Across two milestones, every defect found during execution was in the plan or the
spec, none in an implementation — and all of them were found by **mutation, not
inspection**. That document catalogues eight shapes of test that cannot fail, all
observed in this repo, plus the method for finding them and the cases where adding
a test is the wrong answer.

## Build

`swift build` · `swift test` — 79 tests, warning-free. Six non-test targets with
strictly one-way dependencies (`docs/superpowers/specs/…` §3.1).

Two constraints that are easy to violate silently:

- **`MetalUILayout` must import only `MetalUICore`.** Verify with an anchored
  pattern — an unanchored `Metal` also matches the legitimate `import MetalUICore`.
- **Pixel format is `bgra8Unorm`, never `_sRGB`.** An `_sRGB` target makes the
  hardware blend in linear space; this framework composites in gamma-encoded sRGB
  by design (§7.8). It would look fine now and make text rendering wrong later.

**After editing `Sources/MetalUIRender/Shaders/MetalUIShaderTypes.h`, run
`swift package clean`.** The header reaches its C target through a symlink SwiftPM
does not track, so Swift's view goes stale while Metal's refreshes — the symptom is
a vanished rect that looks exactly like a shader bug.

## When CI lands

Two guarantees silently lapse under plausible configurations and must be required,
non-gateable jobs. Both are detailed in the decisions docs:

1. The ABI probe **skips** without a Metal device.
2. `committedGoldensMatchTheBrowser` is the only live-WebKit consumer.
