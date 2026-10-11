# ForEach identity by Hashable equality (C20) — design

Item C20 of the gpui-gap list (user request 2026-10-02; not a plan task).
Requested by MetalCreator, gap **M7-a** (`/Users/maxburger/Developer/MetalCreator/docs/metalui-gaps.md`,
read-only): a `NodeID` prints 8 hex digits, so two nodes whose UUIDs began alike
collapsed into one identity and the second was dropped silently (divergence 79,
`DD-L`). Rulings: `docs/superpowers/2026-10-10-foreach-identity-decisions.md`
(`FI-`). Record: `docs/record/95-foreach-identity.md`. Branch
`fix/foreach-identity` from `280d706`. Parallel branches, off limits:
C15 (`OV-`, §92), C16 (`IF-`, §93), C21 (`BB-`, §94).

## 1. Evidence (SwiftUI; gpui has no analogue)

gpui keys elements by `ElementId` values the caller supplies (a typed
`ElementId`, not a string of a description), so it is no evidence; SwiftUI is
the authority (EP-5).

* `docs/probes/swiftui-scrollviewreader-scope.swift` S6/S7 (recorded 2026-09-25):
  ids `AnyHashable(1)`/`AnyHashable("1")` are **two** elements evaluated; equal
  values one.
* **New** `docs/probes/swiftui-foreach-hashable-identity.swift` (recorded
  2026-10-10, output in its header): H1 two ids equal in description, unequal in
  value keep **separate `@State`**; H2 (separating arm) each state follows its
  id's value through a reorder; H3 (control) equal values are one element.

So SwiftUI's identity is Hashable equality alone, and divergence 79 is retirable
if MetalUI can carry a value in a path component.

## 2. Inventory (what the code does today)

* `ForEach.produceElements` (`Sources/MetalUI/ForEach.swift`) dedupes by
  `Set<ID>` (value, F7) **and** `Set<String>` (the minted name, `DD-L`), names
  the scope `ElementID(String(describing: key))`, calls `noteNamed` (`ID-R`),
  `transitions.noteLoopElement`, and (only while a `scrollTo` is pending)
  `noteScrollKey(scope, AnyHashable(key))`. Both entries (legacy
  `requestGroupLayout`, typed `requestProposalGroupLayout`) share it.
* `ElementID` (`ElementID.swift`) is `public struct { let name: String }`,
  Hashable + Sendable; `PathComponent.named(ElementID)`;
  `GlobalElementID.cachedHash`/`==` (chain walk; **not touched**).
* Readers of a named component's `name`: `Frame.scrollKey(of:)` (fallback only,
  when no typed key was noted), `TestWindow.frames(ofID:)` (compares
  `.named(ElementID(name))` — an `.id("x")` lookup, unaffected), StateTable's
  `noteNamed` (pattern-matches `.named`, name-blind).
* `.id(_ name: String)` (`IdentifiedGroup`, `ID-G`) takes a `String`: it has no
  description problem (the caller supplies the string); unchanged.
* **`List` rows** mint `ElementID(String(describing: datum.id))` at
  `List.swift` (rows, ~515/531), the selection map (~1168) and a test
  (`DisabledTests` 843). Same collision, silently **aliasing state** (type doc,
  "a real, unguarded gap"). **Deferred** (§7).

## 3. Design

**3.1 A discriminator in `ElementID`.** `ElementID` gains one internal stored
property `key: IdentityKey?` (nil = today), where
`struct IdentityKey: Hashable, @unchecked Sendable { let value: AnyHashable }`
(`@unchecked`: an id's value is a main-actor value in practice; the existing
`GlobalElementID` is already a class that crosses no actor). Synthesized
`==`/`hash` therefore compare **name and key**: the path component of an
element with `key` is unequal to a plain `.id("1")`, and to any other key, with
no change to `GlobalElementID.==` or `cachedHash` (the chain walk and the
parent-in-hash stay; FI-C). The public surface (`init(_ name:)`, `name`) is
**unchanged**: the new initialiser `init(name:key:)` is internal, so the
inventory has no new public row (a plain-import typecheck guard pins it).

**3.2 `ForEach` mints keys only where its description is not injective.**
A static `DescriptionInjectiveID` marker (internal protocol, empty) is adopted
by `Int`, `Int8…Int64`, `UInt…UInt64`, `String`, `Substring`, `Character`,
`Bool`, `UUID`, `Double`, `Float`. Once per `ForEach` build
`needsKey = !(ID.self is DescriptionInjectiveID.Type)`. Then per element:
`name = String(describing: key)` as today; `ElementID(name:key:)` with
`key = needsKey ? IdentityKey(AnyHashable(id)) : nil`. A homogeneous
`ForEach` over those types cannot collide in description between unequal
values, so its paths are **byte-identical to today's** (same `String`, `key`
nil): state, hashing, pixels and work do not move for the common ids.
Everything else — a custom id struct (`NodeID`), an enum, a tuple, an
`AnyHashable` — always carries its value, so identity does not depend on what
the *other* elements happen to be (a design where only colliding classes were
keyed would reset the first twin's state when a second appeared: FI-B).

**3.3 Dedupe.** The name half of the dedupe (`seenNames`) is **removed**; the
value half (`Set<ID>`, F7) stays: equal values are one element, as SwiftUI
(H3). Equal descriptions of unequal values are now both produced.

**3.4 Consistency of the other id users.**
* `ID-R` / `noteNamed`: the scope is a `.named` GlobalElementID as before; its
  own copy keeps working because the key is part of the component. The arm in
  `everyNamingSiteStartsAReturningNameFresh` gains a colliding-twin id (FI-D).
* `scrollTo`: the typed key `AnyHashable(id)` is already noted per scope;
  value-compared (`DD-K`), so a twin is reached by its own value. The
  `Frame.scrollKey` string fallback applies only to `.id("…")` and is unchanged.
* `.id(_:)` stays `String` (FI-E): no `Hashable` overload is added (SwiftUI's
  `.id(_:)` takes a `Hashable`, a separate, additive question; not asked for).
* `List(selection:)`, windowing, `RowExtentIndex`, TB-AH: **untouched**.

**3.5 Warning fallback is not built** (feasibility proven): there is no
"drop" left to warn about except equal values, which SwiftUI also drops (its
own warning; MetalUI stays silent as today — FI-F).

**3.6 Cost.** For fast-path ids: one metatype cast per `ForEach` build, one
fewer `Set<String>` insert per element (**less** work). For custom ids: one
`AnyHashable` box per element per frame, one more hash of `id` when the
component hashes (`GlobalElementID.init`) and one `AnyHashable ==` per path
comparison that reaches this component. Counted, never timed:
`Frame.forEachIdentityWork` (internal; `elements`, `keyed`) read by tests.
`MemoryLayout<ElementID>` grows 16 → 24 bytes; `GlobalElementID` is a class, so
its heap size is the measured question (expected the same 64-byte malloc
bucket; measured and recorded, FI-G).

## 4. Files and lanes (at most two, disjoint)

**Lane 1 — source and tests.**
* `Sources/MetalUI/ElementID.swift` (property, internal init, `IdentityKey`),
  `Sources/MetalUI/ForEach.swift` (`needsKey`, dedupe, doc comment: the
  divergence-79 paragraph rewritten), `Sources/MetalUI/Frame.swift` (the work
  counter only), a new `Sources/MetalUI/DescriptionInjectiveID.swift`.
* Tests: `Tests/MetalUITests/ForEachTests.swift` (1.16 flips),
  new `Tests/MetalUITests/ForEachIdentityTests.swift`,
  `ExplicitIdentityTests.swift` (the one arm), new guard in
  `Tests/MetalUITests/ForEachCompileGuards.swift`. `swift package clean` after
  the stored property.
* The Linux/noble build of the root package (MetalUI changed) and `Backends/SDL`
  build (no change expected, built to prove it).

**Lane 2 — docs and measurement** (disjoint files; starts after lane 1 lands
its names): `docs/divergences.md` (row 79 → retired with the record ref; new
row **255** for the List residue, §7), `docs/migration.md`,
`docs/api-overview.md` (ForEach paragraph), `docs/verification/human-checks.md`
(§6), `docs/probes/closeout-public-api.sh` census re-record (expected: no
change), the 14-image compare, the mutation table and counts. CLAUDE.md /
AGENTS.md / README / record index only in the Record phase.

## 5. Tests (names; red before; mutation that must redden)

New file unless stated; all `@MainActor @Test`, no sleeps.

| # | name | red before | mutation (must redden) |
|---|---|---|---|
| 1.16 | `aForEachWhoseIDsCollideInDescriptionProducesBoth` (flips the divergence-79 pin; `AnyHashable(1)`/`("1")`: both read, 3 nodes) | yes: "string" never read | **M1** `needsKey` forced false (plain names) → 1.16, 2.1, 2.2, 2.6 red |
| 2.1 | `idsEqualInDescriptionButNotInValueKeepSeparateState` (custom `Twin: Hashable` printing "twin"; a counter `@State` in each element incremented from input) | yes | M1 |
| 2.2 | `eachTwinsStateFollowsItsIDThroughAReorder` (probe H2) | yes | M1; **M2** key built from the *index* instead of the id → red (state stays with position) |
| 2.3 | `equalValuesStillProduceOnlyTheFirst` (existing 1.8 stays; a Twin arm added) | green | **M3** `Set<ID>` dedupe removed → 1.8 + this red (ID-F aliasing counter) |
| 2.4 | `fastPathIDsMintNoKey` (Int, String, UUID ids: the scope component `== .named(ElementID(String(describing:id)))`; pins "paths byte-identical") | green (regression pin) | **M4** `needsKey` forced true → red; also 2.5 |
| 2.5 | `aWarmForEachCountsItsIdentityWorkNotItsTime` (500 Int elements: `keyed == 0`, `elements == 500`; 500 Twin: `keyed == 500`; second warm frame identical) | compile-red (counter absent) | M4; **M5** counter incremented per hash instead of per element → red |
| 2.6 | `scrollToReachesATwinByValue` (`DD-K` shape: `scrollTo(Twin(2))` moves to the second) | yes (no second) | M1; **M6** `noteScrollKey` fed the description → red |
| 2.7 | `aTwinThatLeavesAndReturnsStartsFreshAndItsSiblingKeepsItsState` (`ID-R`/`DD-C`) | yes | M1; **M7** `noteNamed` skipped for keyed scopes → red; `everyNamingSiteStartsAReturningNameFresh` gains the Twin arm |
| 2.8 | `anElementIDWithAKeyIsNotEqualToAPlainOneOrToAnotherKey` (+ `GlobalElementID` paths differing only in a key are unequal and hash apart) | compile-red | **M8** synthesized `==` replaced by name-only → red; this does **not** touch `GlobalElementID.==` (FI-C) |
| 2.9 | `aForEachInATestWindowShowsBothTwins` (MetalUITesting `TestWindow`: two `Text`s found) | yes | M1 |
| G1 | typecheck guard `theKeyedElementIDInitialiserIsNotPublic` (`typecheckFile`, plain import: `ElementID(name:key:)` and `.key` do not compile; `ElementID("x")` does) | n/a | **M9** make the init `public` → guard red (run natively; the guard skips otherwise, `CX-J`) |
| 2.10 | `aListRowsCollisionIsStillDivergence255` (pins the deferred residue: `AnyHashable(1)`/`("1")` rows share one entry) | green | the List fix would redden it — it is the pin for §7 |

Existing tests that must stay green unedited: every `ForEachTests`,
`ForEachBindingTests`, `ScrollToTests`, `TransitionTests` row, the
`theSevenRetentionSlotsAreMutuallyDistinct` pin, `ExplicitIdentityTests`,
`DemoFrameDeterminismTests` (Expected unedited). `DisabledTests` 843 builds a
`List` row id by hand: unchanged because Lists are not changed. A grep of
`Tests` for a hand-built `ElementID(String(describing:` over a `ForEach` of
non-injective ids is part of lane 1 (only the List one exists today).

## 6. Demo, pixels, human checks

* Demo: **no demo section changes** (every demo `ForEach` is Int/String/UUID or
  range-keyed — lane 1 greps and records it). Pixels **0 px** in all fourteen
  images (`docs/probes/demo-pixels/compare.sh <scratch> 280d706 HEAD`).
* Human checks: **none owed** — this is identity, with no look (FI-H records
  why, so a reviewer does not look for one).

## 7. Scoped out (named, with reason and owner)

* **`List` rows** keep the description-based name (same silent aliasing). Reason:
  the ruling brief puts `List` windowing, TB-AH, `RowExtentIndex` and the
  100k work literals under MUST-NOT-MOVE; the rows' name feeds `ListRows`,
  the selection map and `Frame` hit/scroll lookups at three sites plus a
  100k-row work count. New **divergence 255** (List rows whose ids collide in
  description share one state entry; SwiftUI keeps them apart). Owner: a
  follow-up item "List row identity by value" (FI-I) that reuses
  `ElementID(name:key:)` unchanged — it needs only the three sites and the
  work-count re-take.
* `.id(_:)` taking `Hashable` (additive, not requested).
* A debug warning for equal-value duplicates (SwiftUI warns; MetalUI silent
  today, F7) — not requested once M7-a is solved.
