# Environment epoch (C14-c) — design

Item C14-c of the gpui-gap priority list (user request 2026-10-02; not a plan task), carried from C14 (record §104
`IV-D`, `IV-H`), C14b (§109) and C14b-2 (§110). Rulings: [`../2026-10-14-environment-epoch-decisions.md`](../2026-10-14-environment-epoch-decisions.md)
(`EE-`). Record: `../../record/120-environment-epoch.md` (Record phase). Branch `perf/environment-epoch` from `6273e3a4`.
Divergence labels reserved 505–514: **none taken**; 346 is amended.

**Status: DESIGNED. Two lanes. No public API.**

## 1 What exists and what is missing

`Component.equatable()` (`EquatableComponent`) skips a component's `content` getter while `==` holds, its own `@State`
versions are unchanged (`StateTable.entryVersion`) and its observed reads unchanged (`ContentMemoStore`, one observation
session over the getter). A component declaring `@Environment` or `@FocusState` is **refused** by
`StateBinder.memoShape(of:)` (`refused = hasEnvironment || hasFocusState`): `EquatableComponent.requestGroupLayout` takes the
`else` branch, `store.noteRefusal()`, evaluates `component.content`, and — having no `ContentMemoStore.Entry` — also takes no
part in retention (`guard let window, let entry else { … }`). The cost is measured: the bracket fixture's `.environment` arm
(one reader of `@Environment(\.colorScheme)` per node) is 8.3–8.9 ms per drag frame against 6.6 for `.value` (profile
2026-10-13), 231 node bodies against 20 over the drag (`baselineArms`: evaluations 2, skips 19, refusals 11).

Retention (`SB-`, `RK-`) keys every record by `environmentTop.retainedFingerprint` (replay key `retainedAmbientKey()`,
graft key `graftBuildKey()`). The fingerprint covers every built-in field, the **types** of provided objects (not the
instances: `EE-K`) and a **count** of custom keys; any custom value makes the occurrence ineligible
(`customEnvironmentKey`, three sites).

`EnvironmentValues` stores custom keys as `[ObjectIdentifier: Any]`; the whole-environment compare is impossible, which is
why `Window.environment` writes always dirty. That stays: **a build still runs on an environment write**; this item only
lets an `.equatable()` component skip its getter (and keep its retention entry) when what it read is unchanged.

SwiftUI: probe `swiftui-environment-epoch.swift` (per-key-read granularity, value compare, identity for classes and object
instances, closures unreliable) and `swiftui-incremental-invalidation.swift` `E-env`. gpui: no environment; not consulted.

## 2 Design (rulings EE-A…EE-K)

**No epoch counter.** The decision compares *readings*.

```swift
/// What one declared `@Environment` read at a position (internal).
enum EnvironmentReading: Equatable {
    case value(any Equatable)          // == after an opened-existential type match; Optional by its wrapped value
    case object(ObjectIdentifier?)     // a class value that is not Equatable, or an @Observable object instance
    case uncomparable                  // a function, a struct holding one, \.self, \.textMeasurer: equals nothing
    static func of<T>(_ value: T) -> EnvironmentReading
}
```

1. **`Environment`** (`EnvironmentProperty.swift`) stores `let probe: (EnvironmentValues) -> EnvironmentReading` beside
   `read`, non-optional, so a new initialiser cannot forget it. Key-path init: `{ .of($0[keyPath: kp]) }`. Object init:
   `{ .object($0.object(T.self).map(ObjectIdentifier.init)) }` — **never** the trapping `read` (EE-D). `Environment.Box`
   keeps its shape.
2. **`StateBinder`** (`StateReflection.swift`): `Shape` keeps `hasEnvironment`; `memoShape` returns `refused = hasFocusState`
   only (EE-E). `StateBinder.bind` appends `readings` for the type's `BindableEnvironment` children, **in the same Mirror
   pass** (no second walk), into a collector the caller armed: `Frame.environmentReadings: [EnvironmentReading]?` (nil =
   no collection; `EquatableComponent` sets it to `[]` around `enterComponent`, takes it, and clears it). A cache-miss
   bind collects too (it binds in the same pass).
3. **`ContentMemoStore.Entry`** gains `readings: [EnvironmentReading]`; `materialize(…, readings:)` skips only when
   `entry.readings == readings` joined to the existing conditions. A readings array containing `.uncomparable` never reaches
   `materialize`: `EquatableComponent` calls `store.noteRefusal()` and evaluates the getter exactly as the refused path does
   today (no entry, so no retention): divergence 346's remainder. An evaluated component stores the readings it was evaluated
   under (`entry.readings = readings`, next to `versions`).
4. **`EnvironmentValues`** (`EnvironmentValues.swift`): `custom` becomes `[ObjectIdentifier: CustomValue]`
   (`value: Any`, `reading: EnvironmentReading`), the subscript setter computes the reading once; `customKeyCount` is replaced
   by `uncomparableCustomCount`. `EnvironmentFingerprint.customKeyCount` becomes `custom: [ObjectIdentifier: EnvironmentReading]`
   and `objects` becomes `[ObjectIdentifier: ObjectIdentifier]` (type → instance, `EE-K`). The mirror guard's `"custom"` row
   text changes.
5. **Retention sites** (`RetainedSubtree.swift` `retainedEntryRefusal`, `RetainedPrepaint.swift`, `RetainedGraft.swift`
   `graftReplay` guard): each `environmentTop.customKeyCount` test becomes `uncomparableCustomCount`, reason
   `uncomparableEnvironmentKey`. **P2 (perf/layout-allocations) edits isolation-check loops in `Frame.swift` and
   `RetainedSubtree.swift`: these three are one-line edits; do not reformat either file.** `Frame.swift` gains one stored
   property (`environmentReadings`) next to `environmentTop`.
6. **Docs**: `Component.equatable()`'s doc comment and `EquatableComponent`'s say an `@Environment` reader is memoized by
   its readings, that the author writes `==` over the stored inputs (a synthesized one cannot see an `Environment`
   property), and what stays refused (EE-B, EE-E). `docs/divergences.md` row 346 is rewritten (EE-H);
   `docs/api-overview.md`/`docs/guides` only where they say "refused" (a grep, `GuideDocCheck` red tells).

Rejected: a per-scope epoch (EE-A); an opt-in `EnvironmentKey` protocol (EE-C); a read recorder on `wrappedValue` (EE-A);
narrowing the replay key to a read set (EE-F, deferred); a `FrameWork.contentEnvironmentMisses` field (EE-I); making
`Environment` or `TextMeasurer` Equatable (EE-G).

## 3 Files and lanes (two, disjoint)

**Lane 1 — core** (`Sources/MetalUI/EnvironmentProperty.swift`, `EnvironmentValues.swift`, `StateReflection.swift`,
`ContentMemo.swift`, `EquatableComponent.swift`, `Frame.swift` (one property), `RetainedSubtree.swift`, `RetainedPrepaint.swift`,
`RetainedGraft.swift` (three one-line sites), `Component.swift` doc comment; tests: `Tests/MetalUITests/EnvironmentReadingTests.swift`
(new), `EnvironmentCompileGuards.swift` (G1), `RetainedSubtreeInternalTests.swift` (the `"custom"` row text only)).
Step 0 (before any design is built on it): a 30-line measurement that `value as? any Equatable` succeeds for a built-in
(`ColorScheme`, `Locale`, `Font?`), a user struct, an `@MainActor`-isolated-conformance struct and a class, and what a release
loop of 1e6 casts costs; record it in the lane's note, and amend `EE-C` if the isolated case differs from "uncomparable".
Step 1: the unit tests red (they do not compile before `EnvironmentReading` exists: red by absence, then by the stub
returning `.uncomparable`). Then the implementation.

**Lane 2 — fixtures, window tests, demo, docs** (`Tests/MetalUITestingTests/BracketFixture.swift`,
`RetainedSubtreesBaselineTests.swift`, `ContentMemoWindowTests.swift`, `RetainedVerifyTests.swift`, new
`EnvironmentEpochWindowTests.swift`, `EnvironmentEpochRetentionTests.swift`; `Sources/MetalUIDemoContent/InvalidationDemo.swift`
(a new section in its own function) and `Sources/MetalUIDemo/main.swift` only if the section needs a registration;
`docs/divergences.md` row 346; `docs/verification/human-checks.md`; `docs/probes/perf-baselines.sh` only if the arm needs
a switch). Lane 2 writes its tests **first, against 6273e3a4, red on arrival** (the refusal behaviour), and commits that;
lane 1's merge turns them green. It owns the before/after wall measurement (below).

Neither lane touches `Sources/MetalUILayout`, `LayoutMemo`, `Rounding`, `ForEach.swift`, MetalCreator, `CLAUDE.md`,
`AGENTS.md`, README, the plan, the record (Record phase).

## 4 Tests (name — what it pins — red before — the mutation that must redden it)

Mutations: commit first, copy, edit, full unfiltered `swift test --build-system native --no-parallel`, restore, `git status
--short`; name every test reddened; the spelling and branch go in the record.

Lane 1, `EnvironmentReadingTests` (MetalUITests):
- **U1 `anEquatableValueReadsEqualOnlyWhenEqual`** — `of(3) == of(3)`, `of(3) != of(4)`, a nil optional equals a nil optional,
  a `Font?` by its wrapped value. Red: no `EnvironmentReading`. Mutation: `.value` case compares always true.
- **U2 `aReferenceValueReadsByIdentity`** — same instance equal, a new instance of equal content unequal, a non-Equatable class
  never `.uncomparable`. Mutation: `.object` compares always true.
- **U3 `aFunctionOrAFunctionHoldingStructReadsUncomparable`** — `.uncomparable != .uncomparable`; a struct with a closure
  and `\.self`'s `EnvironmentValues`. Mutation: `.uncomparable` made equal to itself.
- **U4 `aCustomKeyWriteStoresItsReadingAndCountsTheUncomparable`** — `uncomparableCustomCount` 0 for an Int key, 1 for a
  closure key, back to 0 when the closure key is overwritten with an Int-valued key's… (a second closure key counts 2). Mutation:
  the setter never counts.
- **U5 `anIsolatedConformanceValueReadsAsMeasured`** — pins the step-0 answer (comparable or uncomparable), never a crash.
  Mutation: flip the cast to `as? any Equatable & Sendable`.
- **U6 `theFingerprintDistinguishesTwoInstancesProvidedAsOneType`** (`EE-K`) — red before: equal fingerprints. Mutation: the
  fingerprint's `objects` back to type ids.
- **U7 `theFingerprintDistinguishesCustomValuesAndNotEqualOnes`** — two different Int values unequal, equal values equal. Red
  before: the count made them equal. Mutation: drop `custom` from the fingerprint.
- **G1 `anEnvironmentProbeCannotBeReadOutsideTheModule`** (typecheck guard, plain import, `typecheckFile`) — `Environment(\.colorScheme)`
  has no spellable `probe` and `EnvironmentReading` is not visible. Red once: make `probe` `public`; restore.
- Existing: `everyEnvironmentFieldIsInTheFingerprintOrDeclaredIrrelevant`'s `"custom"` row text only.

Lane 2, window tests (`TestApp`/`TestWindow`, `FrameWork`; the rows say who changes and who must not evaluate):
- **W1 `aReaderOfAnUnchangedEnvironmentValueIsSkipped`** — `@Environment(\.colorScheme)` equatable component, parent ticks:
  `contentEvaluations 0`, `contentSkips 1`, `contentRefusals 0`. Red: refusals 1, evaluations 1. Mutation: `memoShape` refuses
  on `hasEnvironment` again.
- **W2 `aReaderIsEvaluatedAgainWhenTheValueItReadChanges`** — the scheme changes (`preferredColorScheme`/an `.environment`
  write): evaluations 1, the new value shows (accessibility label and scene), memo-off differential equal. Mutation:
  `entry.readings == readings` replaced by `true` (reddens W2, W4's custom arm, W7 d).
- **W3 `aReaderOfAnotherKeyIsSkippedWhenAnUnreadKeyChanges`** — two components, one reads `\.intKey` (custom), one
  `\.colorScheme`; changing `intKey` evaluates the first only, and conversely (probe B1). Mutation: compare the whole
  fingerprint instead of the readings.
- **W4 `aCustomEquatableKeyRewrittenEqualIsSkipped`** — a parent write of the same Int each tick: skip; a changed Int:
  evaluate. Red before: refusal. Mutation: the setter stores `.uncomparable` for all.
- **W5 `aReaderOfAFunctionKeyIsRefusedAndStillEvaluates`** — closure key: `contentRefusals 1`, evaluated every frame, current
  value shown (the narrowed 346). Replaces the environment half of `aComponentWithAnEnvironmentOrFocusStateIsRefusedAndStillEvaluates`.
  Mutation: treat `.uncomparable` as equal (then the shown value goes stale: reddens).
- **W6 `aReferenceKeyIsComparedByIdentity`** — same instance skip, new instance evaluate (probe K2). Mutation: `.object`
  case compared as always equal.
- **W7 `anObjectReaderFollowsItsInstanceAndItsReadProperties`** — (a) tick: skip; (b) a read `@Observable` property written
  from input: evaluate; (c) an unread property written: skip; (d) the provided instance swapped: evaluate and show the new
  object. (b), (c) pin the session count only on Darwin (`IV-Q`); elsewhere through scene equality. Mutation: reading
  `.object(nil)` always (reddens d).
- **W8 `aFocusStateComponentStaysRefused`** — `contentRefusals 1` (the focus half of the old test). Mutation: `refused =
  false`.
- **W9 `aDeclaredButUnreadMissingObjectDoesNotTrapInTheProbe`** (exit test, `.success`) — non-optional
  `@Environment(Model.self)` declared, unprovided, getter never reads it. Mutation: probe through the trapping `read`
  (the exit test fails with the trap message).

Lane 2, retention (`EnvironmentEpochRetentionTests`, every one also under `METALUI_VERIFY_RETAINED=1`, `RetainedVerifyTests`'
scenario list gains R1 and R3):
- **R1 `aReplayMissesWhenAnEnvironmentValueItReadChanges`** — `.environment` bracket occurrence: scheme changes, `retainedMisses`
  1, hits 0 for it, the scene equals a no-retention build. Red before: no entry, `retainedIneligible`/no hit at all. Mutation:
  drop `colorScheme` from `retainedFingerprint`.
- **R2 `aReplayHitsWhenAScopeNotOnItsPathChanges`** — a sibling's `.environment(\.intKey, …)` changes, the occurrence's
  `retainedHits` stays and `contentSkips` +1. Mutation: fingerprint built from the root environment instead of the position's.
- **R3 `anUnreadValueAtItsPositionSkipsTheGetterButMissesTheReplay`** (EE-F honest pin) — an unread custom key changes at the
  position: `contentSkips 1`, `retainedMisses 1`. Mutation: custom dropped from the fingerprint (reddens: hit, stale).
- **R4 `anEquatableCustomKeyNoLongerMakesAnOccurrenceIneligible`** and **R4b `anUncomparableCustomKeyStillDoes`**
  (`retainedIneligible`, reason `uncomparableEnvironmentKey` via `lastGraftRefusals`). Mutation: each `customKeyCount` site
  restored (one at a time, three sites, three runs).
- **R5 `aGraftMissesWhenACustomKeyChanges`** — `BuildKey` carries the fingerprint: `grafts 0` after a change, `1` before.
  Mutation: the graft's key without `custom`.
- **R6 `anObjectSwapMissesAReplayAndAGraft`** (EE-K under retention). Mutation: type-id `objects`.

Fixture pins:
- **B1 `theEnvironmentArmCostsWhatTheValueArmCosts`** — in the retention-off and the retained configurations, the
  `.environment` arm's `contentRefusals`, `elementRequests`, `elementPrepaints`, `elementPaints`, `retainedHits`,
  `retainedMisses` equal the `.value` arm's. Red on arrival: refusals 11 against 0, element counts apart. Mutation: the
  W1 mutation (refuse `hasEnvironment`).
- **B2** the re-counted `baselineArms` `.environment` row (retention off: refusals 0, nodeBodies 20) and **B3
  `theEnvironmentObjectArmCostsWhatTheValueArmCosts`** for the new `.environmentObject` arm. The only edited existing
  literals: that row.
- Existing tests that must stay green unedited: the whole suite except the three named (the `"custom"` row text, the split
  of the 346 pin, the `.environment` baseline row). A fourth edit is a finding.

## 5 Measurement (lane 2)

Release ms per drag frame for the bracket `.environment` arm **before** (at `6273e3a4`, lane 2's first step) and **after**:
`zsh docs/probes/perf-baselines.sh release bracketab` extended to `.value`/`.environment`/`.environmentObject` alternating
in one process, median and minimum, wall and thread-CPU, **dated** and with the load average (the Mac is shared; the
ratio to `.value` is the reading). Expectation: `.environment` falls from ≈8.3–8.9 to within the `.value` arm (≈6.6). Not
pinned (`BL-`). The fourteen images read 0 px against `6273e3a4` (`docs/probes/demo-pixels/compare.sh <scratch> 6273e3a4 HEAD`);
`DemoFrameDeterminismTests` `Expected.swift` unedited.

## 6 Demo and human checks

`METALUI_INVALIDATION_DEMO=1` gains an "Environment" section in its own function (Windows 1 MB stack;
`everyProductionTreeBuildsOnAOneMegabyteThread` covers it): one `.equatable()` component reading a custom Int key and
`\.colorScheme`, a button writing the key, a button writing an unrelated key, and a label showing the component's body
count. Expectation: the first button moves the count by 1 and the shown value; the second by 0; flipping the scheme moves it
by 1 and the colours are right at once. Human check **EE1** (`docs/verification/human-checks.md`, group EE, not run — an agent
cannot): the three presses, then a window drag across displays of two scales (`displayScale` reader) and a Light/Dark switch
in System Settings with the component retained, looking for a stale colour. The real-window capture runs only when the lock
probe allows (it read locked at design time).

## 7 Deferred, named

- **C14-c2** `@FocusState` memo: a window focus version (`EE-E`).
- **C14-c3** replay/graft keys narrowed to a subtree's read set, so an unread value at the position stops missing (`EE-F`).
- A per-read recorder instead of the declared set (`EE-A`): only if a measured case needs it.
- `\.textMeasurer` readers stay refused (`EE-G`); an Equatable measurer view is a separate design.
- `drawText` stays deferred (`GT-F`, `IV-O`).

## 8 Must not move

Identity and state retention (`theSevenRetentionSlotsAreMutuallyDistinct`, MC-A/C/P), hit testing, accessibility, animation,
focus, `List` windowing and TB-AH, `Deferred`, text input, every pixel; no new public declaration (`closeout-inventory-check.sh`,
`closeout-undocumented.sh` print nothing; census unmoved); `MetalUILayout` imports only `MetalUICore`; `MetalUIScene` only
`MetalUIShaderTypes`; `Backends/SDL` untouched (the Linux image still builds it, since `MetalUI` is shared); 0 `warning:`
on both build systems. `swift package clean` after the stored-property changes (`Frame`, `EnvironmentValues`,
`Environment`).
