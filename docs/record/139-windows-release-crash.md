# 139. Windows release-build compiler crash (XP-G21)

Item XP-G21 (MetalCreator, 2026-10-21, blocking its xp-2 Windows release zip; not a plan task). Branch `fix/windows-release-crash` from `68975774`, one lane.
Spec `docs/superpowers/specs/2026-10-21-windows-release-crash-design.md`; rulings `docs/superpowers/2026-10-21-windows-release-crash-decisions.md` (`WR-A`...`WR-G`).
Probes `docs/probes/windows-release-crash/` (`repro.sh`, `candidate-b.patch`).

## 1. Defect and reproduction

`swift build -c release` with a compiler built with assertions (Windows CI 6.4.0+Asserts) aborted in SIL verification of a closure-specialised
`PaintPass.withRenderEffects` (suffix `Tf1nnncn_n`): "return with stack allocs that haven't been deallocated". Debug builds are green. It reproduces on macOS with
`swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a` (`WR-A`). Same family as `LK-X`/`SG-E`: an asserts-only verifier, no source bug.

## 2. Fix (WR-B, WR-C)

`withRenderEffects` is `@_optimize(none)` and forwards, with no guard, to `private openingRenderEffects(_:upTo:bounds:id:_:)`, which recurses by index (no
`Array(dropLast())`) and passes `count - 1` to `legacyShadowColourKey`. Measured variants on the same toolchain: optnone alone crashes identically; an `isEmpty` guard in
the entry crashes in the caller (`closure #1 in paintDecoration`); optnone entry, unguarded, over the optimised helper builds. Scope order and every shadow colour track key are unchanged.

## 3. Verification

- **Red first** (`68975774`, tests only): the env-gated `theComponentSwitchShapeAgainstAnAssertsCompiler` with its new `Effects` fixture, all four release arms (`LKX`, `MG27`, `Workaround`, `Effects`) failed with
  "SIL verification failed: return with stack allocs that haven't been deallocated" (254.9 s, 4 issues); debug arms green; the `Standalone` positive control asserted. After the fix: passed (103 s, with `everyLegacyRenderEffectOpensItsScopeAtItsIndex`).
  The unmodified arms were already red because they all build MetalUI in release; the `Effects` arm names this crash (`WR-G`). The restore-the-old-function mutation is the red-first run itself (same code).
- **`everyLegacyRenderEffectOpensItsScopeAtItsIndex`** passes at `68975774` and after (value-identical). Mutation: `count` for `count - 1` in the shadow arm: reddened that test alone in a filtered run (tracks at 1 and 3, not 0 and 2); restored, `git status` clean.
- **Suite**: `swift package clean`, native build 0 `error:`, only SwiftPM's deprecation `warning:`; native unfiltered **4229 tests in 5 suites** (4228 + 1), the only issues the five locked-screen `AppKitPresentationTests` sheet issues of `CI-AF`;
  `FR-J no-argument frame: succeeded=true`. Inventory and undocumented scripts print nothing (no public declaration). The fourteen offscreen images 0 px against `68975774` (`docs/probes/demo-pixels/compare.sh`, all scene identical).
- **CI**: `root-windows` gains `swift build -c release --product MetalUI`; its Windows cost is unmeasured (human check WR2).

## 4. Carried

An upstream reduction (no MetalUI) for swiftlang; the optnone entry goes with the next asserts-toolchain bump that passes `repro.sh` unmodified (`WR-E`). Human checks group `WR`.
