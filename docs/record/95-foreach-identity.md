# 95 — ForEach identity by Hashable value (`FI-`)

Branch `fix/foreach-identity` from `280d706`. **Not a plan task**: item C20 of
the gpui-gap list (user request 2026-10-02), requested by MetalCreator
(`metalui-gaps.md` M7-a). Spec
`docs/superpowers/specs/2026-10-10-foreach-identity-design.md`; rulings `FI-A`…`FI-K`
in `docs/superpowers/2026-10-10-foreach-identity-decisions.md` (next unused
`FI-L`); probe `docs/probes/swiftui-foreach-hashable-identity.swift`.

**Status: LANDED.** Two ids that print alike and differ in value are two
elements with separate `@State`, as SwiftUI. **Divergence 79 is retired**
(label never reused); the `List` residue is the new divergence **255** (`FI-I`,
deferred by name: `List` windowing, `TB-AH` and `RowExtentIndex` are on the
must-not-move list).

## §1 What changed

* `ElementID` gains an internal `key: IdentityKey?` (a final class forwarding
  `==`/`hash` to an `AnyHashable`, short-circuiting on identity, `FI-J`) and an
  internal `init(name:key:)`; the public `init(_:)` is unchanged. Synthesized
  `==`/`hash` compare name and key. `GlobalElementID.==` and `cachedHash` are
  untouched (`FI-C`).
* `ForEach` mints a key for every element **iff** its id type is not a
  `DescriptionInjectiveID` (Int family, String, Substring, Character, Bool, UUID,
  Double, Float): one metatype test per build (`FI-B`). Keying only colliding
  elements would move the first twin's path when a second appears (`ID-C`).
  The per-build name dedupe is gone, except for `BinaryFloatingPoint` ids, where a
  NaN (unequal to itself) would otherwise mint one path for every element (`FI-K`).
  Equal values are still one element (F7). `.id(_:)`, `ScrollViewReader` keys
  (`noteScrollKey` is fed the value, as before) and `noteNamed` are unchanged.
* `Frame.forEachIdentityWork` (`elements`, `keyed`) is the work counter.
* `DescriptionInjectiveID.swift` is new; `List` rows are not changed.

## §2 Counts

* Baseline `280d706`: 3312 tests, 0 goldens, 208 typecheck guards.
* This branch: **3325 tests (3415 after the merge with master a720fba, 216 guards) in 3 suites** (3312 + 13 new tests, among them the
  typecheck guard G1; 1.16 is flipped in place and the twin arm lives inside the
  existing `everyNamingSiteStartsAReturningNameFresh`). The native
  `--build-system native` run read `FR-J no-argument frame: succeeded=true`, 0
  `error:`; the only `warning:` is SwiftPM's `--build-system native` deprecation
  notice. The screen was locked: the run read exactly the five
  `AppKitPresentationTests` sheet issues (`CI-AF`) and nothing else.
* Census 3361 lines, unchanged in count (line numbers moved); inventory check and
  undocumented check print nothing. The inventory map row for `foreach` now names
  divergence 255 (79 is retired).

## §3 FI-G sizes (measured, test 2.12)

`MemoryLayout<ElementID>` size/stride **24/24** (was 16); `PathComponent`
size/stride **25/32**; `malloc_size` of a `GlobalElementID` **64 plain, 64 keyed**
(same bucket on Darwin), so the heap cost of a path node is unchanged. Custom-id
`ForEach`es pay one `IdentityKey` allocation and one `AnyHashable` box per element
per frame (counted: `keyed == elements`; Int/String/UUID ids count `keyed == 0`).

## §4 Mutation table

Each mutation applied to the spelling named, on a clean tree (`git status --short`
read empty after each), full unfiltered native suite; the five `AppKitPresentationTests`
sheet issues (locked screen) are in every count and not listed.

| # | mutation | reddened |
|---|---|---|
| M1 | `needsKey` forced `false` (`ForEach.swift`) | `aForEachWhoseIDsCollideInDescriptionProducesBoth` (1.16), `idsEqualInDescriptionButNotInValueKeepSeparateState`, `eachTwinsStateFollowsItsIDThroughAReorder`, `fastPathIDsMintNoKey`, `aWarmForEachCountsItsIdentityWorkNotItsTime`, `scrollToReachesATwinByValue`, `aTwinThatLeavesAndReturnsStartsFreshAndItsSiblingKeepsItsState`, `aForEachInATestWindowShowsBothTwins`, `everyNamingSiteStartsAReturningNameFresh` |
| M2 | key built from the index (`AnyHashable(offset)`) | `eachTwinsStateFollowsItsIDThroughAReorder`, `fastPathIDsMintNoKey`, `everyNamingSiteStartsAReturningNameFresh` |
| M3 | `Set<ID>` dedupe removed | `equalValuesStillProduceOnlyTheFirst`, `aForEachDuplicateIDProducesOnlyTheFirstElement` |
| M4 | `needsKey` forced `true` | `fastPathIDsMintNoKey`, `aWarmForEachCountsItsIdentityWorkNotItsTime`, plus the state-retention tests that compare plain names: `aForEachKeepsEachElementsStateThroughAReorder`, `aForEachOverARangeResetsItsDroppedTail`, `theKeyDecidesWhetherStateFollowsTheValueOrThePosition`, `anElementMovedToAnotherForEachStartsFresh`, `aForEachElementOfTwoMembersResetsBothOnReturn`, `aForEachInsideAProposalStackPlacesEveryElementAndResetsItsDroppedTail`, `aSurvivingForEachElementsListKeepsItsWindowedRowsState`, `theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary` |
| M5 | `keyed` counted twice per element | `aWarmForEachCountsItsIdentityWorkNotItsTime` |
| M6 | `noteScrollKey` fed the description | `scrollToReachesATwinByValue`, `scrollToTargetsTheFirstMemberOfAForEachElement`, `scrollToWorksHorizontallyAndInAProposalScrollView`, `scrollToComparesKeysByValue` |
| M7 | `noteNamed` skipped for keyed scopes | `aTwinThatLeavesAndReturnsStartsFreshAndItsSiblingKeepsItsState`, `everyNamingSiteStartsAReturningNameFresh` |
| M8 | `ElementID.==`/`hash` compare the name only | `anElementIDWithAKeyIsNotEqualToAPlainOneOrToAnotherKey`, `aForEachWhoseIDsCollideInDescriptionProducesBoth`, `idsEqualInDescriptionButNotInValueKeepSeparateState`, `eachTwinsStateFollowsItsIDThroughAReorder`, `fastPathIDsMintNoKey`, `scrollToReachesATwinByValue`, `aTwinThatLeavesAndReturnsStartsFreshAndItsSiblingKeepsItsState`, `aForEachInATestWindowShowsBothTwins`, `everyNamingSiteStartsAReturningNameFresh` |
| M9 | a `public init(name:key:)` overload (the original spelling cannot be made public without a public `IdentityKey`, which fails to compile) | `theKeyedElementIDInitialiserIsNotPublic` (G1, init arm: `succeeded=true`) |
| M10 | the floating-point name dedupe removed | `aNaNIDIsStillProducedOnce` |

M2's first run was killed by an outside `SIGTERM` mid-suite and was re-run; the
table reads the re-run. M9's first spelling (`public init` on the existing
signature) did not compile (9 errors) and proves nothing; the overload above did.
Red-first: commit `16355ad` recorded 1.16, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.9
and the naming-site twin arm red against the unchanged `ForEach`; 2.8, 2.10,
2.11 and G1 were green controls.

## §5 Pixels

`docs/probes/demo-pixels/compare.sh <scratch> 280d706 HEAD` (HEAD `537a3bd`, before the
record commit; sources unchanged since): controls as recorded (light vs dark 1048576,
default vs modal 1031003, default vs animation 454895, f0 vs f3 0, chrome legacy vs
proposal 0, prod default vs modal 491221), then **0 differing pixels and an identical scene
dump in all fourteen images**. No demo `ForEach` has a custom id, so none is keyed.

## §6 Not done, owed

* `List` rows keep the description name (divergence 255, `FI-I`; owner: a "List
  row identity by value" item that reuses `ElementID(name:key:)` and re-takes the
  100k work count).
* No human check is owed (`FI-H`): no look and no input path changed.
* Linux image / `Backends/SDL` builds: `swift:6.4-noble` root build with tests 0 `warning:`/`error:`; 199 + 22 + 78 +
  75 (`MetalUITestingTests`) portable tests passed; `Backends/SDL` (macOS) builds with its tests, 0
  `warning:` from MetalUI (one linker notice about the Homebrew SDL3 deployment target, pre-existing);
  `swift build --build-tests` (default build system) 0 `warning:`. `Backends/SDL` itself is untouched, so
  its suites and the Linux SDL image were not re-run.
