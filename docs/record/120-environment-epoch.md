# 120 — Environment epoch (C14-c)

Branch `perf/environment-epoch` from `6273e3a4`. Not a plan task: item C14-c of the gpui-gap list (user request 2026-10-02), the carried
half of §104 (`IV-D`, `IV-H`) and of §109/§110 (`SB-`, `RK-`). Spec `docs/superpowers/specs/2026-10-14-environment-epoch-design.md`;
rulings `EE-A`…`EE-O` in `docs/superpowers/2026-10-14-environment-epoch-decisions.md` (next unused `EE-P`). Probe
`docs/probes/swiftui-environment-epoch.swift` (output in its header, run twice, identical). Divergence labels reserved 505–514: **none
taken**, 346 is narrowed in place. No public declaration (inventory and undocumented scripts print nothing, census unmoved).

**Status: LANDED (both lanes verified `ok`; Record phase merged master `298c23d4` (§118 pan rasters) cleanly; master's last record was 118, so
120 stands).**

## §1 What changed

- **No epoch counter** (`EE-A`). A per-scope version would need a bump at every write site and could not say which key moved; SwiftUI is per
  key read (probe `B1`). `Environment` gains an internal `probe` beside `read`; `StateBinder.bind` collects the readings of the declared
  `@Environment` children in its one Mirror pass into `Frame.environmentReadings` (armed by `EquatableComponent`); `ContentMemoStore.Entry`
  stores them and `materialize` skips only while `entry.readings == readings` joined to the old conditions.
- **`EnvironmentReading`** (internal enum, `EnvironmentReading.swift`): `.value(any Equatable)` by `==` after an opened-existential type match,
  `.object(ObjectIdentifier?)` for a class value that is not `Equatable` or an `@Observable` instance, `.uncomparable` (equals nothing). The
  reading is made **once per write** by `value as? any Equatable` (no public API, no opt-in protocol, `EE-B`, `EE-C`); a custom key's storage
  is `CustomValue` (value plus reading) and `uncomparableCustomCount` replaces `customKeyCount`.
- **Objects** (`EE-D`): the probe reads `values.object(T.self)` directly, never the trapping `read`; property reads stay the observation
  session's over the getter.
- **Refusals that remain** (`EE-E`, `EE-G`, divergence 346 narrowed): `@FocusState`, and any reader of an uncomparable reading (a closure,
  a struct holding one, `\.self`, `\.textMeasurer`): evaluated every frame, no entry, `contentRefusals`.
- **Retention** (`EE-F`, `EE-K`): the fingerprint gains `custom: [ObjectIdentifier: EnvironmentReading]` and its `objects` become type →
  **instance** (before, a swapped provided object had an equal fingerprint: a latent `SB-G` gap, pinned red on arrival). The three
  `customKeyCount` sites (`retainedEntryRefusal`, the prepaint refusal, the graft guard) test `uncomparableCustomCount`, reason
  `uncomparableEnvironmentKey`, so an `Equatable` custom key no longer makes an occurrence ineligible. Replay and graft keys stay
  whole-position: an unread change at the position skips the getter and misses the replay (carried C14-c3).
- **Fixture and demo**: the bracket fixture gains a `.environmentObject` arm (an `@Observable` store through `@Environment(Store.self)`,
  MetalCreator's shape); `METALUI_INVALIDATION_DEMO=1` gains an Environment block in its own function (`invalidationEnvironmentSection`).
- Docs: `Component.equatable()`'s and `EquatableComponent`'s comments, divergence 346's row, `docs/migration.md`, `docs/api-overview.md`,
  `README.md`, human-checks group EE.

## §2 Tests and guards, per file

Lane 1 (`Tests/MetalUITests`): `EnvironmentReadingTests` — U1 `anEquatableValueReadsEqualOnlyWhenEqual`, U2 `aReferenceValueReadsByIdentity`, U3
`aFunctionOrAFunctionHoldingStructReadsUncomparable`, U4 `aCustomKeyWriteStoresItsReadingAndCountsTheUncomparable`, U5
`anIsolatedConformanceValueReadsAsMeasured`, U6 `theFingerprintDistinguishesTwoInstancesProvidedAsOneType`, U7
`theFingerprintDistinguishesCustomValuesAndNotEqualOnes`; `EnvironmentCompileGuards` — **one new typecheck guard** G1
`anEnvironmentProbeCannotBeReadOutsideTheModule` (plain import, `probe` and `EnvironmentReading` unspellable; mutated red once, `probe` made
`public`). Edited: `RetainedSubtreeInternalTests`' `"custom"` row text; `everyFrameChannelIsClassified` gains `environmentReadings`
(`.buildOnly`); `everyLedgerChannelMakesTheSubtreeIneligible`'s custom-key arm now writes a function-holding key (`EE-M`).

Lane 2 (`Tests/MetalUITestingTests`): `EnvironmentEpochWindowTests` — W1 `aReaderOfAnUnchangedEnvironmentValueIsSkipped`, W2
`aReaderIsEvaluatedAgainWhenTheValueItReadChanges`, W3 `aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges`, W4
`aCustomEquatableKeyRewrittenEqualIsSkipped`, W5 `aReaderOfAFunctionKeyIsRefusedAndStillEvaluates`, W6 `aReferenceKeyIsComparedByIdentity`,
W7 `anObjectReaderFollowsItsInstanceAndItsReadProperties`, W8 `aFocusStateComponentStaysRefused`, W9
`aDeclaredButUnreadMissingObjectDoesNotTrapInTheProbe` (exit test); `EnvironmentEpochRetentionTests` — R1
`aReplayMissesWhenAnEnvironmentValueItReadChanges`, R1b `aReplayMissesWhenTheSchemeFlipsUnderAReaderOfAnotherKey`, R2
`aReplayHitsWhenAScopeNotOnItsPathChanges`, R3 `anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay`, R4
`anEquatableCustomKeyNoLongerMakesAnOccurrenceIneligible`, R4b `anUncomparableCustomKeyStillDoes`, R5 `aGraftMissesWhenACustomKeyChanges`, R6
`anObjectSwapMissesAReplayAndAGraft`; `EnvironmentEpochBracketTests` — B1 `theEnvironmentArmCostsWhatTheValueArmCosts` (three
configurations), B3 `theEnvironmentObjectArmCostsWhatTheValueArmCosts`; `RetainedVerifyTests` gains
`theEnvironmentScenariosDrawNormallyUnderVerifyMode` (the scenarios run under `METALUI_VERIFY_RETAINED=1`).
Edited existing literals (the spec's "fourth edit is a finding", named in advance by `EE-M`): the `.environment` row of five bracket families
(`RetainedSubtreesBaselineTests`, `theBracketNodeDragIsCountedAtFb9a7e42`, `…AfterPrepaintReplay`, `…AfterTheGraft`,
`theBracketNodeDragReplaysEveryUnchangedSubtree`/`…RebuildsTheWholeWindow`) now equal the `.value` row's, and the old
`aComponentWithAnEnvironmentOrFocusStateIsRefusedAndStillEvaluates` is split into W5 and W8.

## §3 Red first

Lane 2's tests were written first and could not run against `6273e3a4`'s `Sources` (a path checkout was refused); the arrival reading is
that behaviour reproduced in the tree (`StateBinder.memoShape` returning `hasEnvironment || hasFocusState`). Under it red: W1, W2, W3, W4,
W6, W7, R1…R6, B1 (three configurations, 9 issues), B3 (three, 11); W5, W8, W9 and the verify scenarios stayed green (they pin what stays
refused). Lane 1's unit tests were red by absence, then by a stub returning `.uncomparable`. Commits `ceba027d` (tests), `96c1bacc` (`EE-M`).

## §4 Mutations

Lane 1 ran eight unit-level mutations on filtered sets (the lane note's table, accepted by verifier 1, not re-listed here); lane 2's, each
restored from a copy with `git status` clean after, in `EE-N`: `entry.readings == readings` to `true` (W2, W3, W4, W6, W7, R1, R2, R6);
`.object` compared always equal (W6, W7, R6, U2); `.value` compared always equal (W2, W3, W4, R1, R2, R3, R5, U1, U5); `isUncomparable`
skipped (W5); `refused = false` for `@FocusState` (W8); the object probe through the trapping `read` (W9); `custom` dropped from the
fingerprint (R3, R5, U7); `objects` back to type ids (R6, U6); each of the three `uncomparableCustomCount` sites restored to counting every key
(R4 per site); the record and prepaint sites loosened (R4b each); a window-wide write counter in the fingerprint (R2, R3, R4, R5).

Verifiers re-ran on the **full unfiltered suite** (verifier 1 ran before lane 2 landed, on a 71-issue baseline of stale expectations):

| Mutation | Reddened |
|---|---|
| V1 `entry.readings == readings` removed (`ContentMemo.materialize`) | the stale old refusal test (a third issue, "no element matches label dark") |
| V1 `uncomparableCustomCount` always 0 | U4, `everyLedgerChannelMakesTheSubtreeIneligible` (the function-key arm, 2 issues) |
| V1 readings collection removed in the cached `bindOrdinals` path | the stale old refusal test (a third issue) |
| V2 `entry.readings == readings` replaced by `true` | `aCustomEquatableKeyRewrittenEqualIsSkipped`, `anObjectReaderFollowsItsInstanceAndItsReadProperties`, `anObjectSwapMissesAReplayAndAGraft`, `aReaderIsEvaluatedAgainWhenTheValueItReadChanges`, `aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges`, `aReferenceKeyIsComparedByIdentity`, `aReplayHitsWhenAScopeNotOnItsPathChanges`, `aReplayMissesWhenAnEnvironmentValueItReadChanges` |
| V2 both `return a == b` sites of `EnvironmentReading` forced true | `aCustomEquatableKeyRewrittenEqualIsSkipped`, `aGraftMissesWhenACustomKeyChanges`, `anEquatableValueReadsEqualOnlyWhenEqual`, `anIsolatedConformanceValueReadsAsMeasured`, `anObjectReaderFollowsItsInstanceAndItsReadProperties`, `anObjectSwapMissesAReplayAndAGraft`, `anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay`, `aReaderIsEvaluatedAgainWhenTheValueItReadChanges`, `aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges`, `aReferenceKeyIsComparedByIdentity`, `aReferenceValueReadsByIdentity`, `aReplayHitsWhenAScopeNotOnItsPathChanges`, `aReplayMissesWhenAnEnvironmentValueItReadChanges`, `theFingerprintDistinguishesCustomValuesAndNotEqualOnes` |
| V2 `retainedFingerprint`'s `custom` dropped | `aGraftMissesWhenACustomKeyChanges`, `anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay`, `theFingerprintDistinguishesCustomValuesAndNotEqualOnes` (and one unrelated `TaskModifierTests` ordering flake under load, green alone) |

**Not separated, carried** (`EE-O`, C14-c4): the graft guard's `uncomparableCustomCount == 0` site, dominated by the record and prepaint
refusals; `retainedFingerprint`'s `colorScheme` field alone is redundant with `theme` (dropping both reddens R1b and the verify scenario;
the design's R1 mutation line is amended in `EE-N`).

## §5 SwiftUI probe

`docs/probes/swiftui-environment-epoch.swift` (arms `P0` positive control, `K1-equal`, `K1-equal-2`, `K1-changed` separating, `K2-new`,
`K2-same`, `K2-fn`, `K2-fn-again`, `O2`, `O2-unread`, `O1`, `B1`): SwiftUI is per key read, compares an `Equatable` value by `==` (a value
rewritten equal re-runs nothing), a class by identity, an object by instance and by the properties read; a closure re-runs a reader whenever
the environment was otherwise re-diffed (MetalUI cannot reproduce that timing: refused). Re-run by the critic (`EE-L`), identical.

## §6 Measurement (dated 2026-10-15 UTC, release, never pins)

`zsh docs/probes/perf-baselines.sh release bracketenv`, arms alternating in one process, 8 rounds of 14 drags of 20 steps, 5 warm frames; the
Mac shared (load average 124–168), so the ratio to `.value` is the reading. Thread-CPU ms per drag frame, median / minimum:

| arm | before (`6273e3a4`) | after (`7d87822c`) |
|---|---|---|
| `.value` | 5.545 / 4.713 | 5.377 / 4.713 |
| `.environment` | **8.691** / 7.476 | **5.413** / 4.787 |
| `.environmentObject` | 8.597 / 7.464 | 5.538 / 4.811 |

The environment arms' last-frame work equals `.value`'s (156 requests, 160 prepaints, 178 paints, 32 hits, 32 grafts). The release ratio
`.environment`/`.value` went 1.57 to 1.01.

## §7 Pixels and the other gates

The fourteen offscreen images read 0 px and scene identical against `6273e3a4` (`docs/probes/demo-pixels/compare.sh`, controls intact), at
both lanes. `DemoFrameDeterminismTests` `Expected.swift` unedited. The Linux image ran 340 tests of `MetalUITestingTests` and
`EnvironmentReadingTests`, all passed. `Backends/SDL` untouched (`git diff --stat 6273e3a4 HEAD -- Backends` empty), so its package and the
SDL tests were not re-run. `swift build --build-tests` on the default build system 0 `warning:`.

## §8 Hazards

- A reader of `\.textMeasurer` stays refused by design (its box is new each frame, `GT-D`); `Text` overlays already pay.
- An `Equatable` value with a lax `==` reads unchanged and shows stale content: the author's `==` decides, as for the component's own `==`;
  a mutable class that is not `@Observable` and changes in place is not seen (SwiftUI agrees, probe `K2-same`).
- A value whose `Equatable` conformance is `@MainActor`-isolated casts only on the main thread (measured, `EE-M`): every write and bind is
  there; off it the reading is `.uncomparable`, never a crash (U5).
- A declared but unread, unprovided `@Environment(Model.self)` must not trap in the probe (W9).
- Off macOS a tracked-session count pin is Darwin-only (`IV-Q`); W7's property arms read scene equality there.
- A full suite on a locked screen hangs in `AppKitPresentationTests` (`NSOpenPanel.init()`): `--skip AppKitPresentationTests`.

## §9 Carried

C14-c2 `@FocusState` memo (a window focus version in `FocusRegistry`); C14-c3 replay and graft keys narrowed to a subtree's read set so an
unread value at the position stops missing; C14-c4 a case where only the graft site's `uncomparableCustomCount` test can refuse; a per-read
recorder instead of the declared set (only if a measured case needs it); an `Equatable` measurer view; `drawText` stays deferred (`GT-F`,
`IV-O`).

## §10 Record phase

Merged master `298c23d4` (clean). `swift package clean`, native build and the unfiltered suite on the merged tree: **3944 tests in 3 suites passed** (`--skip AppKitPresentationTests`, 9 tests, locked screen; unlocked expected 3953 = master's 3926 + the branch's 27: lane 1's 7 unit tests and guard G1, lane 2's 19 window, retention and bracket cases and the verify scenario run once per scenario), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation notice, 247 typecheck guards (master's 246 + G1; not re-counted by a guard-by-guard run). `swift build --build-tests` on the default build system was 0 `warning:` at the lanes and not re-taken after the merge (master's §118 changed `RasterCache`/`RasterAnchor` only); inventory and undocumented scripts print nothing; the unlocked re-take is owed.
Docs: `CLAUDE.md`/`AGENTS.md` (the `EE-` prefix, one paragraph, the counts bullet), `docs/divergences.md` (346 narrowed by lane 2; header's
next label untouched for the merge), `docs/record/04-divergences.md` (346 amended), `docs/record/03-verified-on-real-hardware.md` (EE1),
`docs/record/README.md`, `docs/migration.md`, `docs/api-overview.md`, `README.md`, `docs/verification/human-checks.md` (group EE, lane 2),
the decisions doc (`EE-O`) and the spec's status. No new public declaration, so no inventory map row and the census is unmoved.
