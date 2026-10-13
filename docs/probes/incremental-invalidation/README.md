# C14 incremental invalidation: instruments and readings

`phase-timing.patch` (against f6f865c1 plus the baseline test of commit
"test(IV): counted baseline ...") adds `ivPhase`, per-phase wall seconds inside
`Frame.renderOutsideDispatch` and `Component.requestGroupLayout`'s content getter,
and a `ivPhaseTiming(levels:)` test that prints them per frame. **Wall clock is
used here only as an instrument; no pin in the suite may read it.**

Run (release, macOS arm64, Apple silicon, other workflows running, so read the
shares, not the milliseconds):

    git apply docs/probes/incremental-invalidation/phase-timing.patch
    swift build --build-system native --build-tests -c release -Xswiftc -enable-testing --scratch-path .build-rel
    swift test --build-system native -c release -Xswiftc -enable-testing --scratch-path .build-rel --skip-build --no-parallel --filter ivPhaseTiming
    git checkout Sources Tests

## Recorded (2026-10-13, `f6f865c1`, one `@Observable` leaf written per frame, 200 frames)

A 3-ary tree of `Component`s (`IVBranch`, `IVLeaf`), one `Text` per leaf; a branch is a
`VStack` over a `ForEach` of its children; nodes = leaf frame + text, branch stacks.

| leaves | layout nodes | build (`requestLayout`) | layout kernel | prepaint | paint | end sweeps | render | `tick` |
|---|---|---|---|---|---|---|---|---|
| 9 | ~22 | 0.110 ms | 0.054 | 0.023 | 0.037 | 0.012 | 0.238 | 0.297 |
| 27 | ~67 | 0.329 | 0.151 | 0.066 | 0.091 | 0.034 | 0.675 | 0.830 |
| 81 | ~202 | 1.006 | 0.363 | 0.201 | 0.265 | 0.113 | 1.955 | 2.463 |

Shares of `render` at 81 leaves: build 51%, layout kernel 19%, prepaint 10%, paint 14%, sweeps 6%.
`tick` adds about 0.5 ms for the headless platform, scene finalisation and the frame record.
Inside build, the `Component` content getters are 0.211 ms of the 1.006 (21%): the other 79% is the
recursion that registers nodes, ids, state marks and bindings. Per node: about 10 microseconds
in release here, 50 times less than MetalCreator's bracket graph (0.5 ms), whose nodes carry
shadows, strokes, text, keyframes and an environment object.

A release `sample` of 6000 frames (L=4) shows no single hot spot: `swift_release`/`swift_retain`,
`__RawDictionaryStorage.find` and `GlobalElementID.==` (the state table's and the id
chain's lookups), `Hasher`, generic-metadata lookups (`_swift_getGenericMetadata`) and exclusivity
checks (`swift_beginAccess`), spread over the whole build. MetalCreator's own profile (docs/metalui-gaps.md,
PERF-b) reads the same. So **no micro-optimisation moves the cost; only doing less work does.**
