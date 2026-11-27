# 439: a row that holds a horizontal scroller moves its ledger exactly (`FS-AA`; class M, no divergence)

Branch `perf/fence-translation`, base master `9aec1177`. No public API, no divergence (242 live, next label 250). `FS-Z` is reserved by `perf/canonical-crossing-record` and is not on master; this ruling is `FS-AA` and the next id is `FS-AB`.

**Why.** Alloy's markdown code fences and tables are horizontal `ProposalScrollView`s inside retained `.equatable()` rows. A trace of its stream and chat scroll named `hitboxScrolls` 23 times as the reason a moved row's ledger was refused. `movedHitbox` refused any hitbox with a `scroll` payload, for the reason `FS-F` gave for text inputs and value tracks ("their closures or geometry hold positions"). For a scroller that reason is false: its `handlers` are empty, `Hitbox.scroll` is a bare `ScrollAxis`, and the `XS-E` payload (`scrollMirrored`, `scrollAxes`, `scrollTakes`, `scrollRoom`) holds no window position.

**A latent bug first.** `Hitbox.moved` rebuilt the hitbox through `init` and copied back `contextualEnabled`, `unclipped` and `clipDepth`; it dropped the four `XS-E` fields. Lifting the refusal alone would have made a moved fence pass the wheel on (`Window.applyScroll` reads `scrollTakes` and `scrollRoom`), and verify mode would have trapped on `Hitbox.fingerprint`. `moved` is now a copy of `self` with `bounds`, `origin` and `unclipped` replaced (`Hitbox.origin` is a `var`), so a field added later is carried by default.

**What.** The `hitboxScrolls` refusal is deleted. A moved scroller is recomputed by `insertHitbox`'s own arithmetic, like every other hitbox: `unclipped + shift`, `bounds = clip ∩ unclipped'`, `origin + shift`. The payload needs no recomputation: the extents are sizes of nodes inside the occurrence (equal under every shift the shape accepts), the offset is the scroller's own compared `withState` read (in the ledger's `reads` and the record's `versions`, so a changed offset misses), the scale is in `AmbientKey`, the mirror flag in the environment fingerprint. `scrollTo`, `scrollPosition`, a glide and `ScrollerFrame` were checked and need nothing (`FS-AA`).

## Measured (`AlloyTranscriptFixture`: 50 `MarkdownView` rows, a swift fence every 5th and a table every 7th, scrolling sideways, the last row streaming 12 characters a step, a composer below; 420 x 600 at scale 2, no accessibility client, redo backoff off; 20 stream deltas, then 10 wheel steps of 24; allocations by `countAllocations` around each frame)

| | before (master `9aec1177`) | after |
|---|---|---|
| graft off, stream: `hitboxScrolls` / redos / element requests / allocations / ledgers translated / misses | 61 / 0 / 2635 / 1,260,887 / 78 / 85 | 0 / 0 / 2635 / 1,213,308 / 67 / 60 |
| graft off, wheel: same | 53 / 0 / 1160 / 466,111 / 78 / 13 | 0 / 0 / 1160 / 431,210 / 72 / 0 |
| graft on, stream | 0 / 2 / 1579 / 1,443,823 / 91 / 114 | 0 / 0 / 220 / 1,254,962 / 67 / 60 |
| graft on, wheel | 0 / 1 / 844 / 515,870 / 69 / 10 | 0 / 0 / 60 / 433,917 / 72 / 0 |

With the composer focused (click, then the pointer leaves), recorded for the focus work and **not changed here**: graft off stream 61 / 0 / 2635 / 1,269,632 / 78 / 125 before, 0 / 0 / 2635 / 1,221,613 / 67 / 100 after; wheel 53 / 0 / 1160 / 472,430 / 78 / 33 before, 0 / 0 / 1160 / 437,216 / 72 / 20 after; graft on stream 0 / 2 / 1699 / 1,440,129 / 91 / 154 before, 0 / 0 / 340 / 1,249,911 / 67 / 100 after; wheel 0 / 1 / 904 / 526,542 / 69 / 30 before, 0 / 0 / 120 / 443,996 / 72 / 20 after. The extra 40 stream misses and 20 wheel misses under focus are the `SB-X` focus clause, untouched.

The fixture's redos with the graft off were already 0 (a refused ledger was a miss and the prepaint ran); the redo Alloy saw is the graft's (a grafted occurrence cannot run a prepaint), and the graft-on rows show it: 2 redos in the stream and 1 in the wheel before, 0 after, with the element requests 1579 to 220 and 844 to 60. `hitboxScrolls` reads 0 where it read 61 and 53.

## Pins (none moved)

`aNonAnimatableComponentAllocatesWhatItDid` 319; `CF` idle 7115 allocations / 67 requests; `ScrollOffsetPixelSnapTests` idle 1562 / 43; the chrome transcript at most 547 requests and 2 redos; the G51 and G52 ceilings; `ReleaseTreeStackTests` 87 requests and at most 19,968 allocations. Every one of those fixtures keeps its scrollers outside its occurrences, and an idle frame takes `ledger.key == key` first.

## Tests

`AlloyTranscriptFixture.swift` (shared with the focus work): `ATSession` over a transcript of `ATRow`s and an `ATComposer`, `atPair(focused:graft:)`, `atStream`, `atWheel`, `atFenceWheel`. `FenceTranslationTests`: `aFenceRowMovedByAWheelReplaysItsLedgerMoved`, `aMovedScrollerHitboxEqualsAFreshOne` (four arms: `ProposalScrollView`, legacy `ScrollView`, two axes, right-to-left), `aWheelOverAMovedFenceScrollsTheFence`, `aFenceRowsOwnHorizontalScrollStillMisses`, `aFenceCutByTheViewportEdgeMovesItsHitboxExactly`, `aStreamedReplyWithFencesAndATableCostsNoScrollerRedo` (graft off and on), `theAlloyTranscriptEqualsAFreshWindowAtEveryStep` (focused and not, graft off and on; runs under verify mode), and `printTheFenceBaselines` (prints under `METALUI_PRINT_FENCE_BASELINES=1`, asserts nothing).

**Mutations (each reddened tests of `FenceTranslationTests`, restored from git):** M1 `moved` back to the `init` body: every test but the cost-free ones (the differential `compare` names the hitbox fingerprint); M2 the refusal restored: `aFenceRowMovedByAWheelReplaysItsLedgerMoved`, `aFenceCutByTheViewportEdgeMovesItsHitboxExactly`, `aStreamedReply...`; M3 `unclipped` not moved: `aMovedScrollerHitboxEqualsAFreshOne`, `aWheelOverAMovedFenceScrollsTheFence`, `aFenceCutByTheViewportEdgeMovesItsHitboxExactly`, and the rest of the differentials; M4 `scrollRoom` alone dropped: `aMovedScrollerHitboxEqualsAFreshOne` and the differentials.

**Verify mode** (`METALUI_VERIFY_RETAINED=1`, the whole suite): no trap; the new differentials pass. The retained, translation, scoped-redo, redo-attribution, movable-mask, clipped-entry, G51 and G52 suites show only the five known issues of master (`aFocusChangeLeavesAnUnconcernedViewRetained` and four `TableRetained` "beside a redrawing sibling" tests); the other failures of the whole-suite run are count pins outside those suites that verify mode doubles.

**Carried.** The graft-off redos were already 0, so the 23 redos Alloy reported are the graft's; the focus clause (`SB-X`) still costs the focused composer's ancestors a miss a frame (record 440 plan).
