# 409: the cost of a translated `.equatable()` occurrence (`FS-U`, G47, Alloy)

Class `M` (package counters and internal types; no public API), no divergence (labels unchanged). Branch `perf/g47-retained-translate-cost`, base master `8647b80b`. **Numbering:** 404 is unused after a dropped PR, 406 is on master, 407 and 408 are in flight.

## The problem

Alloy scrolls a 1M-row `Table` whose cells are `.equatable()`; `Frame.retainedPrepaintDecision` cost about 1.4 ms a frame with about 400 translated cells (about 6.5 microseconds each) against about 0.1 ms for plain cells. `GlobalElementID` interning stays rejected (memory).

## Profile (release, `sample` on `G47Probe scrollcells eq nest`, 12 s, one frame 5960 samples)

| Where | Samples | Share of the frame |
|---|---|---|
| `retainedPrepaintDecision` | 1296 | 22% |
| of which `paintTranslation` (`movedPaintRecord`: real work, memoised for the paint) | 596 | 10% |
| of which `PrepaintKey.shift(to:)` | 365 | 6% (`AmbientKey ==` 324, `EnvironmentFingerprint ==` 379 in all) |
| `PrepaintLedger.rebased` plus its deinit | 34 + 49 | 1.4% |
| `retainedPaintDecision` (of which `ReplayKey.shiftAndEffects` 114) | 582 | 10% |
| `closeGraftWindow` (`captureSegment` 170, copies of `BuildKey` 142) | 567 | 10% (the graft-backoff PR's ground) |

The derived `AmbientKey ==` is dominated by the 36-field `EnvironmentFingerprint` (`Locale ==`, two dictionaries, `Font?`, `ShapeStyleStorage?`), compared once per cell, and `shift(to:)` made it worse by copying the key (seven retains), replacing the offset and comparing.

## Changes

- `SharedFingerprint` (`EnvironmentValues.swift`): an immutable class box around `EnvironmentFingerprint`; the same box is equal by identity, distinct boxes by value. `AmbientKey.shared` and `BuildKey.shared` hold it; `environment` stays as a computed accessor and an `init(environment:)`, so no reader and no test changed.
- `Frame.sharedEnvironmentFingerprint()`: cached per environment top (`topFingerprint`, cleared by the `environmentTop` observer, put back by `withEnvironment`'s restore); `ContentMemoStore.canonicalFingerprint(_:)` finds an equal box among **at most 8** kept (most recent first, a fingerprint that equals nothing never kept), so a frame's tops share the box the previous frame's records hold. One fingerprint construction and one compare per top per frame, where it was one construction per key.
- `AmbientKey.equalsIgnoringOffset(_:)` in `ReplayKey.shift(from:)` and `PrepaintKey.shift(to:)`: no copy.
- `PrepaintLedger.rebase(to:_:)`: the hit arm of the decision rebases the record's own ledger in place (`key` is `var`); no `PrepaintLedger` per translated cell per frame. The combined effect-and-layout arm still copies (`EL-B`, rare).
- The decision computed `ledger.key.shift(to: key)` twice (once for the trace note); once now.

## Dropped or left

- Ordering the checks in `retainedPrepaintDecisionInner` (candidate 3): after the changes the decision outside `paintTranslation` is about 110 of 4035 samples (2.7%); the refusals are not where the time is, and `paintTranslation` is asked once and memoised for the paint.
- `movedPaintRecord` (12% of the frame, `movedLeaf` 272 of 4035 plus array growth 100) is the translation itself; it also moves `finalScene` a second time when the key has no scopes. Not touched; a candidate for a later item.
- `closeGraftWindow`: the graft-capture backoff of PR #420.

## Measurement (release, `G47Probe`, base vs branch interleaved, 7 repeats, the machine loaded by other sessions' builds)

| Mode | CPU ms median of medians (base, branch) | min of mins | paired delta ms (median, min, max) | `phys_footprint` | live blocks |
|---|---|---|---|---|---|
| `scrollcells eq nest` | 9.46, 8.30 | 9.22, 7.85 | -1.14, -1.22, -0.57 | exit 50.1 to 47.6 MB; mid-run `vmmap` 54-55 to 51-52 MB | 72283 to 69976 |
| `scrollcells` | 8.61, 7.44 | 8.08, 7.14 | -1.20, -1.81, -0.99 | exit 16.0 to 37.8 MB, **mid-run `vmmap` 42.1 to 42.0 MB** | 6785 to 6514 |
| `chat eq` | 3.30, 3.25 | 3.04, 3.10 | -0.04, -0.08, +0.13 | 26.1 to 26.0 MB | 14860 to 15090 |

The exit-time footprint of plain `scrollcells` is allocator timing (dirty malloc pages not yet reclaimed when the process ends; the heap in use is 1.1 MB in both, a 2500-step run read 42 MB for both under `vmmap -summary`). Per candidate, measured one at a time: the shared fingerprint with `equalsIgnoringOffset` (c1) took `scrollcells eq nest` from 9.96 to 8.98 ms (footprint 50.0 to 47.3, blocks 71957 to 69869); the in-place ledger rebase and the single shift (c2) added about 0.1 ms (inside the noise) and removes one ledger and its twenty arrays' retains per translated cell per frame, pinned by the counter. A steady frame allocates 3 blocks fewer (`aNonAnimatableComponentAllocatesWhatItDid` 397 to 394).

## Tests (4 new, 2 pins moved)

`RetainedTranslateCostTests`: `aTranslatedFrameConstructsNoLedgerAndNoFingerprintBox` (24 ledgers moved, 0 constructed, 24 rebased in place, 0 boxes made, the settle frame the same), `theFingerprintSlotsAreBoundedAndExact`, `aSharedFingerprintEqualsExactlyWhatTheFingerprintEquals`, `everyAmbientFieldButTheOffsetSeparates`. Mutations, each reddening: the old `old.prepaint = ledger.rebased(...)` (3 issues), a slot search that never matches (2 tests), `atlasGeneration` dropped from `equalsIgnoringOffset` (2 issues), a value compare of two fields only for distinct boxes, the eviction removed (2 issues). Moved: `everyFrameChannelIsClassified` gained a row for `topFingerprint` (`.frameLocal`), and the steady-frame pin `aNonAnimatableComponentAllocatesWhatItDid` 397 to 394 (an improvement). Every other test is unchanged.

## Counts

Root 7330 tests in 79 suites (+4 over record 406's 7326), full run green (`--build-system native`, `--no-parallel`).
