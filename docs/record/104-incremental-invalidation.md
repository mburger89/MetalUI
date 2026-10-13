# 104 — Incremental invalidation (C14)

Branch `perf/incremental-invalidation` from `f6f865c1`. Not a plan task: item C14
of the gpui-gap priority list (user request 2026-10-02), requested by MetalCreator
(gap PERF-b). Spec `docs/superpowers/specs/2026-10-13-incremental-invalidation-design.md`;
rulings `IV-A`…`IV-M` (`IV-L`, `IV-M` are the critic's) in `docs/superpowers/2026-10-13-incremental-invalidation-decisions.md`
(next unused `IV-N`); probes `docs/probes/swiftui-incremental-invalidation.swift`,
`docs/probes/swift-observation-nested-scopes.swift`, `docs/probes/incremental-invalidation/`.
Divergence labels reserved: 345–354 (346 planned; 345 refuted and unused, `IV-L`).

**Status: DESIGNED (lane 0). No source change yet beyond the committed counted
baseline test.** Two lanes follow, sequential: lane 1 the layout memo, lane 2 the
`.equatable()` content memo (spec §6). The Record phase appends §3 onward.

## §1 The measurement (design phase, `f6f865c1`)

`Tests/MetalUITestingTests/IncrementalInvalidationBaselineTests.swift`,
`oneObservedLeafChangeRebuildsTheWholeWindow(levels:)` (2, 3, 4): a 3-ary tree of
`Component`s, one observed leaf written per frame, 2 warm frames then 4 counted.
Per frame, at 81 leaves: 1 build, **81 leaf and 40 branch bodies**, 81 leaf measures,
832 layout-cache hits, 337 misses, 162 text-system measures, 81 `placeGlyphs`, atlas
upload only for the new digit's glyph. At 27: 27/13 bodies; at 9: 9/4.

Re-taking it: `swift test --build-system native --no-parallel --filter
oneObservedLeafChangeRebuildsTheWholeWindow` prints `IV baseline L=…` lines; after
lane 2 the same tree with `.equatable()` is test 2.1. The phase-timing instrument is
`docs/probes/incremental-invalidation/phase-timing.patch` (README there has the
table and the sample's reading): at 81 leaves build 51%, layout kernel 19%, prepaint
10%, paint 14%, sweeps 6%; content getters 21% of build; no hot spot.

Counts at the design commit: `swift test --build-system native --no-parallel` unfiltered
reads **3567 tests in 3 suites** (3566 + the baseline test), all passed, `FR-J no-argument
frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice.

## §2 The probes

`swiftui-incremental-invalidation.swift` (hosted `NSHostingView`, macOS 27, three
runs identical except one arm noted unexplained in its header): bodies re-run exactly
for readers (R, T, O, ES); equal plain-value or same-instance inputs skip (S, U, V);
`.equatable()` with a custom `==` skipped the plain-value view and not a closure or
fresh-class-instance view on the first bump only (S2/S3 refute a divergence, `IV-L`); a custom `Layout` re-measures every
sibling on a colour change (L-colour). `swift-observation-nested-scopes.swift`
(Swift 6.4): access lists merge upward; the per-scope token gives one live session.

## §3 Design (summary; the spec is the document)

Slice 1 = layout memo by structural signature (automatic) + `.equatable()` content
memo (opt-in) with a per-memo getter session; both leave every phase and channel
running on an equal value, so no existing behaviour moves. Retained subtrees (the
build recursion, prepaint, paint) are carried as C14-b with the design ruled
(`IV-H`). GT-F: `drawText` stays deferred (`IV-I`), re-taken at C14-b.

## §4 Lanes

(To be filled by the lanes: red-first runs, mutation tables with the spelling
applied, counts, the fourteen images, the Linux image, the verify-mode suite run.)
