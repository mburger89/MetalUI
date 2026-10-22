# Windows release-build compiler crash - design (XP-G21)

Item XP-G21 (MetalCreator, 2026-10-21, blocking its xp-2 Windows zip; not a plan task). Branch `fix/windows-release-crash` from `68975774`;
labels 685-694 reserved, **none taken** (no public API, value-identical). Decisions `docs/superpowers/2026-10-21-windows-release-crash-decisions.md`
(`WR-`). Record `docs/record/139-windows-release-crash.md` (Record phase). Lanes: **one**, disjoint from `perf/retained-zoom`.

**Status: landed (record §139, 2026-10-21).** Windows proof is the first `root-windows` CI run (human checks WR1, WR2).

## 1. Problem and reproduction

`swift build -c release` on Windows (6.4.0+Asserts) aborts in SIL verification of `PaintPass.withRenderEffects(_:bounds:id:_:)`
(`RenderEffects.swift:262`), a clone made by the closure specialiser for the `paintDecoration` closure. **Reproduced locally** (WR-A):
`zsh docs/probes/windows-release-crash/repro.sh` at `68975774` fails with "return with stack allocs that haven't been deallocated"
(a `partial_apply [on_stack]` of the `body` closure is live at a `return` of the specialised clone). The cause is a stack-nesting
defect in the optimiser around a recursive function that forwards a non-escaping `body` through a locally formed closure (`inner`)
into four scope helpers. Same family as `LK-X`/`SG-E` (an asserts-only verifier), no source bug.

## 2. Inventory

`RenderEffects.swift:262` `PaintPass.withRenderEffects` (two callers: `AnimatedColor.swift:447` `paintDecoration`; `DecorationScope.swift:74`
is the *prepaint* twin on `Frame`, a different, non-crashing function). `withShadow`/`withBlur`/`withCompositingGroup`/`withRenderEffect` are
unchanged. `legacyShadowColourKey(for:index:)` keys by `effects.count - 1` of the *current* (shrinking) slice: the index form must pass
`count - 1`, never the original count.

## 3. Change (WR-B, WR-C)

`docs/probes/windows-release-crash/candidate-b.patch` is the measured fix: `withRenderEffects` becomes a one-line `@_optimize(none)` entry
that forwards to a `private` index-based `openingRenderEffects(_:upTo:bounds:id:_:)` (no `Array(dropLast())`; the entry has **no**
`isEmpty` guard, since an inlined guard re-creates the crash in the caller, variant A). Output identical: same scopes in the same order,
same shadow colour track index (`count - 1` at each depth). No public API, no census change, no new divergence.

## 4. Tests and guards (all by name)

1. **`theComponentSwitchShapeAgainstAnAssertsCompiler`** (existing 3.2, env-gated) gains a fourth fixture `Effects` that imports MetalUI and
   uses `.shadow`, `.blur`, `.compositingGroup()` and a legacy `Box` with two effects in release. Red before: at `68975774` it must fail with
   the marker `SIL verification failed` (the arm's assertion string grows that marker beside `verifyLexicalLowering`); first, the lane runs
   the *unmodified* 3.2 at `68975774` and records whether its existing `--target LKX` release builds already redden (they build MetalUI in
   release: if they do, this crash is already pinned and the new arm only names it). Mutation: restore the old function body; the arm reddens.
2. **`everyLegacyRenderEffectOpensItsScopeAtItsIndex`** (new, ordinary suite, `RenderEffectsTests`): a legacy element with `[.shadow(a), .blur, .shadow(b)]` and
   an id records shadow colour tracks `legacyShadowColourKey(index: 2)` and `(index: 0)` (the two shadows), scope order outermost-last. Red
   before: none (value-identical); pin for the index translation. Mutation: pass `count` for `count - 1` in the shadow arm; this test reddens.
3. Existing paint/effect tests and the fourteen images unchanged (0 px against `68975774`).
4. **CI**: add `swift build -c release --product MetalUI` (or the smallest product that compiles the MetalUI target) to `root-windows` in
   `.github/workflows/swift.yml` **if the lane's measured Windows cost is under ~10 minutes** (UTM x64 build, `--triple`, native build system;
   else ruled carried with the figure, WR-D). Windows proof is CI's; this Mac cannot give it.

## 5. Not built, carried

An upstream report to swiftlang (reduction of the stack-nesting defect without MetalUI): owner the next asserts-toolchain bump; the
optnone entry may go then (WR-E). Other recursive non-escaping-closure functions (`Frame.paintWith*`) did not crash and are untouched.

## 6. Demo and human checks

No demo change. Human check group `WR`: build and run MetalCreator's xp-2 Windows release zip on Windows (WR1).
