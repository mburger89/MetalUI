# Windows release crash - decisions

Rulings for item XP-G21. Spec: [`specs/2026-10-21-windows-release-crash-design.md`](specs/2026-10-21-windows-release-crash-design.md).
Record: `../record/139-windows-release-crash.md` (Record phase). Branch `fix/windows-release-crash` from `68975774`. Divergence labels
685-694 reserved: **none taken** (no SwiftUI-facing claim, no probe of SwiftUI; the evidence is compiler runs).

Prefix **`WR-`**, lettered. **Next unused: `WR-G`.** (Moves in the commit that appends a ruling.)

**Carried.** `LK-X`/`SG-E` (asserts-only SIL verifier, env-gated `AssertsCompilerTests`), `PE-K`/Windows CI hazards.

## WR-A - The crash reproduces on macOS with the asserts snapshot, in release only

**Ruling.** Treat `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a` as the Windows stand-in. **Evidence.** `docs/probes/windows-release-crash/repro.sh`
(header carries the output): `swift build -c release --product MetalUIDemo` at `68975774` dies with "SIL verification failed: return with stack
allocs that haven't been deallocated" in the specialised `PaintPass.withRenderEffects`; the debug build is green. **Cost if wrong:** Windows'
6.4.0+Asserts could hit a different clone; the CI step (WR-D) is the proof.

## WR-B - Fix: an optnone entry over an index-based helper (variant B)

**Ruling.** `withRenderEffects` becomes `@_optimize(none)` and forwards, unguarded, to a private `openingRenderEffects(_:upTo:...)`
recursing by index. **Evidence (four variants, same toolchain):** C `@_optimize(none)` on the original alone fails identically; A optnone on both
with an `isEmpty` guard in the entry fails in `closure #1 in paintDecoration` ("inconsistent stack states", the guard inlined into the caller);
B (entry optnone, no guard, helper optimised) builds (73.6 s). The entry blocks inlining and closure specialisation into callers; the index form
removes the `Array(dropLast())` copies. **Cost if wrong:** the entry is an unoptimised trampoline on every decorated paint (one call, no
allocation beyond the closure context that was already formed); the empty-effects path now forms the helper call instead of returning `body()` inline.
Perf pins count work, not time (CLAUDE.md), so none moves; the lane re-takes the demo scene counters.

## WR-C - Value identity

**Ruling.** Index form passes `count - 1` where the original used `effects.count - 1` of the shrunken slice, so each shadow keeps its
`legacyShadowColourKey` index, and scope order is unchanged. Pinned by spec 4.2. **Cost if wrong:** an animated shadow colour would restart or swap tracks; the fourteen images would not see it, hence the pin.

## WR-D - Guard: asserts-toolchain release arm plus a Windows CI step gated on cost

**Ruling.** Extend the env-gated asserts test with an effects fixture (spec 4.1); add `swift build -c release --product MetalUI` to `root-windows`
only if the measured cost is under about 10 minutes, else carry it with the figure. **Cost if wrong:** a cheap step omitted lets the next
release-only crash reach MetalCreator again; a costly one slows every PR.

## WR-E - Not an upstream-fix wait

**Ruling.** Ship the workaround now (MetalCreator is blocked); remove it when a toolchain bump makes `repro.sh` pass on the unmodified function.

## WR-F - Critic review: rejected and tightened points

**Ruling.** Reviewed with no SwiftUI claim, public spelling, platform requirement, shader primitive, C enum or demo change in scope (none arise).
Two points tightened. (1) The repro crashed in the **demo** product while the guard builds the **MetalUI** target: the lane must show the
guard red at `68975774` (the specialisation needs a `paintDecoration` caller inside MetalUI, which `AnimatedColor.swift:447` is); if the MetalUI-only
release build does not redden, the guard's fixture builds `MetalUIDemo`-free but the CI step uses the product that did, and the figure is recorded.
(2) Test 4.2's index pin must be a real mutation: it is run with `count` for `count - 1` and the reddened test named; if no seam reads the
recorded track keys, the pin reads `AnimationStore` state through the existing testing hook rather than being dropped. **Rejected:** guarding the
entry with `isEmpty` (variant A, measured crash); removing optnone (variant B needs it, measured); waiting for upstream (WR-E).
