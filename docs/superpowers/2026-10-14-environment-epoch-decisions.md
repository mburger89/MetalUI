# Environment epoch — decisions

Rulings for item C14-c of the gpui-gap priority list (user request 2026-10-02; **not a plan task**), carried from
C14 (record §104, `IV-D`, `IV-H`) and C14b/C14b-2 (records §109 `SB-`, §110 `RK-`). Prefix `EE-`. Spec:
[`specs/2026-10-14-environment-epoch-design.md`](specs/2026-10-14-environment-epoch-design.md). Record:
`../record/120-environment-epoch.md` (Record phase). Branch `perf/environment-epoch` from `6273e3a4`.
Divergence labels reserved for this branch: 505–514 (**none taken**: 346 is amended in place).

SwiftUI's side: `docs/probes/swiftui-environment-epoch.swift` (arms P0, K0-tick, K1-equal-2, K1-equal, K1-changed,
K2-new, K2-same, K2-fn, K2-fn-again, O2, O2-unread, O1, B1; output in its header, run twice, identical) and the older
`swiftui-incremental-invalidation.swift` `E-env`, `E-env2`, `EnvQuiet`. gpui has no environment (state is entities;
`cx.notify()` re-renders a view, there is no ambient value to version): nothing to borrow.

**Next unused id: `EE-P`.**

## EE-A — No epoch counter: compare what each declared `@Environment` read, per key

**Question.** The request wants a "cheap per-scope version". Which granularity, and does a version exist at all?

**Evidence.** Probe B1: changing `colorScheme` re-runs the reader of `\.colorScheme` only; readers of two custom keys and
an object do not (and K1-changed: only the `intKey` readers). SwiftUI is per key read. MetalUI's environment is a value
stack (`Frame.environmentTop`, pushed by `EnvironmentScope`, one `scopedValues(applying:)` per scope per frame); a version
per scope needs a bump at every write site (`.environment`, `.transformEnvironment`, `.theme`, `.disabled`, the
window's three stamped fields, the frame's `displayScale`/`theme` stamp, `\.self` resets) and a composition along the path
that still cannot tell *which* key moved. `bind` already takes the snapshot (`environmentSnapshot()`, EV-O) for a type
that declares `@Environment`, so its values are in hand at the memo's decision point.

**Ruling.** There is **no epoch**. `Environment` gains an internal **probe** next to its `read` closure; a memoized
component's decision compares the **readings** of its declared `@Environment` properties (at the position's snapshot)
with the readings stored with the memo entry. Granularity is the **declared property**: a declared property the getter
never reads still counts (a superset, never stale; the probe cannot see reads, and a getter skipped by the memo has no read
set to replay). The name "epoch" survives only as the item's name.

**Cost if wrong.** An unread declared property causes an evaluation the memo could have skipped: the author deletes the
property. A per-read recorder (`wrappedValue` appends to a session) would be exact; it costs a global recorder on every
read and buys nothing the declared set does not for the measured case.

## EE-B — A reading is `==` for Equatable values, identity for classes, and nothing for the rest

**Question.** `EnvironmentKey.Value` is unconstrained; how is "unchanged" decided?

**Evidence.** Probe K1-equal/-2: a value rewritten equal re-runs nothing; K1-changed: re-runs. K2-same (same instance
rewritten) nothing, K2-new (new instance of a non-Equatable class) re-runs: classes compare by identity. K2-fn: a closure
with a different capture re-runs; K2-fn-again: a fresh closure with the same capture does not; EqFn also re-runs in
K1-changed, K2-new, O1 and B1 (any re-diff of the environment): SwiftUI treats a closure as changed whenever the environment
was otherwise re-diffed. MetalUI cannot reproduce that timing.

**Ruling.** `EnvironmentReading` (internal enum): `.value(any Equatable)` (compared by `==` after an opened-existential
type match), `.object(ObjectIdentifier?)` for a reference-type value that is not Equatable or an
`@Observable` object, `.uncomparable` (a function, a struct holding one, an `EnvironmentValues`, `\.textMeasurer`: it equals
nothing, not even itself). An optional compares as its wrapped Equatable (`nil` reads equal to `nil`). A component
with any `.uncomparable` reading is **refused**: evaluated every frame, no entry, `contentRefusals` counts it (divergence
346, narrowed). A same-instance mutable class value that is not `@Observable` and changed in place is **not** seen (SwiftUI
agrees, K2-same).

**Cost if wrong.** Treating an Equatable value with a lax `==` as unchanged shows stale content: the author's `==`
decides, as for the component's own `==`. A class with identity-only semantics that the app mutates in place needs
`@Observable`.

## EE-C — Equatable is found by a dynamic cast; there is no public API and no opt-in protocol

**Question.** Detect Equatable at the write site or require a protocol?

**Evidence.** The subscript is `subscript<K: EnvironmentKey>(key: K.Type) -> K.Value`, SwiftUI's shape, unconstrained;
SwiftUI compares without asking for conformance (K1-equal). An opt-in protocol on `EnvironmentKey` would be a MetalUI-only
spelling every migrating key must adopt to get a speed-up.

**Ruling.** The reading is made once **per write** (the custom storage keeps `value` and `reading` together, so a
fingerprint or a probe never casts) by `value as? any Equatable` on the stored `K.Value`; the same function makes a probe's
reading for a key path. **No new public declaration**, no inventory row; `Component.equatable()`'s doc comment is the one
public text that changes. Measure first (lane 1 step 0): a value whose `Equatable` conformance is `@MainActor`-isolated
(Swift 6.4 isolated conformances, used by this repo's fixtures) may not cast from the nonisolated storage; the answer is
`.uncomparable` (safe, counted), pinned by whichever the measurement says, never a crash.

**Cost if wrong.** A cast per write per frame per scope (`transformEnvironment` runs once per frame in layout): measured at
lane 1 in release before the ruling stands; the fallback is a per-`K.Value` metatype cache.

## EE-D — `@Environment(Type.self)`: the instance's identity, and the observation session for what it read

**Question.** An object read is a reference plus `@Observable` property reads.

**Evidence.** Probe O2: a read property changing re-runs the reader; O2-unread: not; O1: swapping the provided instance for
another of the same type re-runs. MetalUI's memo already wraps the getter in one observation session (`IV-D`), so a property
read through the wrapper is tracked with no new code. The fingerprint holds `objects: [ObjectIdentifier]` of the **types**
only, so a swapped instance equals the old one (see `EE-K`).

**Ruling.** The object's reading is `.object(ObjectIdentifier(instance))` (or `nil` for the optional spelling's absence);
property reads stay the observation session's. **The probe never traps**: it reads `values.object(T.self)` directly, not the
non-optional `read` closure, so a declared-but-unread, unprovided object does not trap where the getter would not (test W9,
an exit test).

**Cost if wrong.** A probe that trapped would crash an app whose component declares an object it reads only in a branch.

## EE-E — `@FocusState` stays refused

**Question.** Is it trivially coverable?

**Evidence.** A `@FocusState` value is the window's focus projected through a binding: it changes from input
(`applyPendingFocusStateWrites`, Tab traversal, a click on a field, a resign) with no per-component version, and writes
name `$focus` slots that sit outside the memo's `StateTable` entry versions (`IV-D`). A cover needs a window-wide focus
version bumped by the registry plus the `$focus` writes: a design of its own, and no MetalCreator component needs it.

**Ruling.** Refused as today (`shape.refused` is `hasFocusState`), counted, divergence 346 narrowed to it. Carried as
**C14-c2** (owner: the next C14 follow-up; a focus version in `FocusRegistry`).

**Cost if wrong.** A focus-reading component loses the memo; the counter says why.

## EE-F — Retention keeps its whole-fingerprint ambient; the fingerprint learns custom values and object instances

**Question.** Item 5: a retained occurrence's ambient must include what the memo covers, or replay draws a stale
environment. And "a replay must hit when an unread value changes."

**Evidence.** `retainedAmbientKey()` and `graftBuildKey()` both carry `environmentTop.retainedFingerprint`: every built-in
field at the occurrence's position. Custom keys enter only as a count and **any** custom value makes the occurrence
ineligible (`customEnvironmentKey`, three sites: `retainedEntryRefusal`, the prepaint refusal, the graft guard). The
descendants of a skipped or replayed occurrence are not re-bound, so what they read of the environment is the occurrence
position's.

**Ruling.** (1) The fingerprint gains `custom: [ObjectIdentifier: EnvironmentReading]` (the stored readings, no cast);
an uncomparable custom value keeps the occurrence ineligible, the reason renamed `uncomparableEnvironmentKey`
(`customKeyCount` becomes `uncomparableCustomCount`). (2) Replay and graft keys **stay whole-position**: any value at
the occurrence's position that differs misses, read or not; narrowing a replay key to a subtree's read set needs the
descendants' reads, which the probe cannot give (carried as **C14-c3**, owner: a retained-subtree follow-up). (3) The
unread-value-hits pin is therefore two: the **getter memo** hits when an unread key changes (`contentSkips` +1) while the
retained record misses (pinned, honest); and the occurrence **hits both** when the change is in a scope not on its path.
`METALUI_VERIFY_RETAINED=1` runs every new retained test (`RetainedVerifyTests`' scenario list gains the two env
scenarios).

**Cost if wrong.** A custom value omitted from the fingerprint draws stale; the guard U7 and the mutation say so before a
merge. Whole-position keys cost a miss on an unread change at the position; the counter shows it.

## EE-G — Built-in stamped values participate as any key; four are named

**Ruling.** `colorScheme`, `displayScale`, `controlActiveState`, `accessibilityReduceMotion`/`Transparency`, `windowSize`,
`titleBarInsets`, `isEnabled`, `locale`… compare by `==` through the key path (their types are Equatable; Optional
`font`/`foregroundStyle` through the wrapped value). `theme` is `internal` (no key path outside the module, so no reading
exists; it stays covered by the fingerprint). `\.textMeasurer` is **uncomparable on purpose**: its box is new each frame
(`GT-D`), so an Equatable-by-box would change every frame, and making it equal by system would hide a layout change; a
component reading it is refused, as `Text` overlays already pay (`GT-A`). `\.self` is uncomparable.

**Cost if wrong.** A reader of `\.textMeasurer` stays refused: documented in divergence 346's row.

## EE-H — Divergence 346 is amended, not retired, and takes no new label

**Ruling.** 346 stays, naming the remainder: `@FocusState`, and `@Environment` of an uncomparable value (a closure, a
non-Equatable struct, `\.self`, `\.textMeasurer`). SwiftUI's side per probe K2-fn: a closure re-runs a reader only when the
environment is otherwise re-diffed; MetalUI re-runs it every frame. Pin: the existing
`aComponentWithAnEnvironmentOrFocusStateIsRefusedAndStillEvaluates` is **split** (W5 uncomparable, W8 focus). Labels
505–514 stay unused.

## EE-I — No new `FrameWork` field

**Ruling.** The pins read `contentEvaluations`, `contentSkips`, `contentRefusals`, the element counters and the retained
counters; a new public field would owe an inventory row for a count the existing ones separate (a changed read shows as an
evaluation, an unchanged one as a skip). Rejected: `contentEnvironmentMisses`.

## EE-J — The fixture's `.environment` arm becomes the red-on-arrival pin

**Ruling.** `BracketEnvNodeView` already reads `@Environment(\.colorScheme)`. The `.environment` row of
`baselineArms` (retention off: evaluations 2, skips 19, refusals 11, nodeBodies 231) and the retained arm's counts are
expected to move to the `.value` arm's (refusals 0, nodeBodies 20): the new pin `theEnvironmentArmCostsWhatTheValueArmCosts`
states the **relation** (equal content, element and retained counters) so it survives a later `.value` re-count, and the old
literals are re-counted in the same change. A second arm `.environmentObject` (an `@Observable` palette store read through
`@Environment(ThemeStore.self)`, MetalCreator's shape) is added to the fixture.

## EE-K — The objects in the fingerprint were types, not instances (a latent `SB-G` gap)

**Question.** `EnvironmentFingerprint.objects` is documented "compare by identity" and is
`objects.keys.sorted`: the **type** ids.

**Evidence.** `setObject(_:as:)` keys by the static type; two different instances provided as the same type have equal
fingerprints. A retained occurrence replayed or grafted across a swap of the provided object (a `ThemeStore` replaced) would
show the old object's paint and the old graft: unmeasured so far, pinned red-on-arrival by U6 and by the window test
W7 (d) under retention.

**Ruling.** The fingerprint holds `[ObjectIdentifier: ObjectIdentifier]` (type → instance). Not a behaviour of the
item's feature, but a precondition of it: allowing `@Environment(Type.self)` components into retention makes the
swap reachable.

**Cost if wrong.** A swapped object under a retained occurrence paints stale.

## EE-L — Critic pass: probe re-run, one test text repaired, no design change

**Evidence.** The probe was recompiled and re-run on 2026-10-14 (macOS 27): P0, K1-equal, K1-changed, K2-new, K2-same, K2-fn,
K2-fn-again, O2, O2-unread, O1 and B1 read byte for byte as the header records (EqFn's extra re-runs included).
**Ruling.** The design stands. U4's text was garbled (an Int cannot overwrite a closure key) and is rewritten as a key count that
survives overwriting. Lanes stay two and sequential; lane 2's red-on-arrival tests read only counters that exist at 6273e3a4.
**Cost if wrong.** None beyond the test text.

## EE-M — Lane 1 measurements: the cast, the isolated conformance, and two test edits the design did not name

**Evidence (step 0, 2026-10-14, Swift 6.4, macOS 27, `-O`, a scratch executable).** `value as? any Equatable` succeeds for
`Int`, `Locale`, a plain enum, `Optional<Int>` (some and none), a user struct and a `@MainActor`-isolated-conformance struct
(`struct S: @MainActor Equatable`) **on the main thread**, and fails for a class, a closure-holding struct. A cast of the
isolated-conformance struct from a nonisolated function **off the main thread fails** (`false`); the same call on the main
thread, nonisolated function included, succeeds, and an opened `==` of two such values is true. A success costs about
56–60 ns, a failure (a class) about 125–140 ns, with the optimiser prevented from folding the loop (`@_optimize(none)`):
one cast per custom-key write is negligible next to a frame.
**Ruling.** EE-C stands as written: an isolated-conformance value is **comparable on the main actor** (every write and bind
happens there) and reads `.uncomparable` anywhere else, never a crash (test U5 pins both). `any Equatable & Sendable` cannot be
the cast's spelling (a marker protocol is refused in a conditional cast), so U5's mutation is the cast to `any Hashable`.
**Two edits the design's "three" did not count.** (1) `everyFrameChannelIsClassified` gains the row `environmentReadings`
(`.buildOnly`): `Frame` gained a stored property. (2) `everyLedgerChannelMakesTheSubtreeIneligible`'s `.customEnvironmentKey`
arm wrote an **Int** key, which is now comparable and so no longer makes an occurrence ineligible (the point of EE-F); the arm's
key now holds a function (`RSChannelValue`), the case that still does. The five bracket families that pin the `.environment`
arm's old literals (`RetainedSubtreesBaselineTests`, `theBracketNodeDragIsCountedAtFb9a7e42`, `…AfterPrepaintReplay`,
`…AfterTheGraft`, `theBracketNodeDragReplaysEveryUnchangedSubtree`, `…RebuildsTheWholeWindow`) move with the feature and are
lane 2's re-count (B1–B3), not an edit of lane 1.
**Cost if wrong.** None: the first is a table row, the second restores the arm's meaning.

## EE-N — Lane 2 findings: red on arrival by the refusal mutation, an evaluated occurrence, the fingerprint's scheme, and the measurement

**Red on arrival.** Lane 1 had merged before lane 2 began, so the tests could not be run against `6273e3a4` itself (a path checkout
of the old `Sources` was refused by the permission layer). The arrival reading is the 6273e3a4 behaviour reproduced in the working
tree: `StateBinder.memoShape` returning `hasEnvironment || hasFocusState` (the old refusal), everything else of lane 1 kept. Under it
(commit `ceba027d`) these were red: W1, W2, W3, W4, W6, W7; R1, R2, R3, R4, R5, R6; B1 (three configurations, 9 issues) and B3 (three
configurations, 11 issues). W5, W8, W9 and the verify-mode scenarios stayed green: they pin what stays refused or is a control.

**The counters, as measured.** (1) An occurrence whose getter was **evaluated** in a frame counts `retainedIneligible` that frame, never a
miss or a hit; the frame after (getter skipped, record stale) is the miss that re-records, then the hits resume. R1, R2 are written to
that (the design's "one miss" text was a prediction). (2) The graft guard's `uncomparableCustomCount` test declines silently, with no
counter and no `testingGraftRefusals` line, and is dominated by the paint and prepaint refusals: R4b pins those two; the graft site is
pinned only in the restore direction by R4 (an Int key must graft). Mutating the graft site to `>= 0` (never refuse) reddened nothing:
**unseparated, carried**. (3) `retainedFingerprint`'s `colorScheme` field is **redundant with its `theme` field** (the window selects
`lightTheme`/`darkTheme` by scheme): dropping `colorScheme` alone reddens nothing (R1 and the new R1b both survive), dropping both reddens
R1b and the verify scenario. R1b is the pin (a skipped-getter reader under a scheme flip must miss; the `.accent` token resolves
through the theme). The design's R1 mutation line (`colorScheme` dropped) is amended to "`colorScheme` and `theme` dropped, red:
R1b, `theEnvironmentScenariosDrawNormallyUnderVerifyMode`".

**The re-counts the five bracket families owed (EE-M).** With `.environment` memoized it counts what `.value` counts in every table:
`RetainedSubtreesBaselineTests` 3 / 29 / 0, 20 node bodies (retention off); `theBracketNodeDragIsCountedAtFb9a7e42` paints 252,
hits 29, misses 3, skipped paints 832, memo hits 362, subtree hits 11; `…AfterPrepaintReplay` prepaints 219, skipped 667, hits 29;
`…AfterTheGraft` requests 208, skipped 590, grafts 29, grafted nodes 590; `theBracketNodeDragReplaysEveryUnchangedSubtree` 29 / 3 /
0 with nodes retained. The old combined test 2.5 is split into W5 and W8 (its two private readers removed).

**Fixture.** The `.environmentObject` arm provides `BracketThemeStore` per node through `.environment(model.theme)`; with retention
off and in both replay configurations it evaluates, skips and replays as `.value` does (B3 pins evaluations, skips, hits, misses,
ineligible and 20 node bodies; its element counters were equal to `.value`'s in B1's three configurations too and are not pinned).

**Mutations** (spelling, each run on the filtered set of every new test and lane 1's, restored from a copy, `git status` clean after):
`entry.readings == readings` to `true` (W2, W3, W4, W6, W7, R1, R2, R6); `.object` compared always equal (W6, W7, R6, U2); `.value`
compared always equal (W2, W3, W4, R1, R2, R3, R5, U1, U5); `isUncomparable` skipped in `EquatableComponent` (W5); `refused = false`
for `@FocusState` (W8); the object probe through the trapping read (W9); `custom` dropped from the fingerprint (R3, R5, U7);
`objects` back to type ids (R6, U6); the three `uncomparableCustomCount` sites restored to counting every key (R4 for each; the
record site also R3, R5, R2); the record and prepaint sites loosened to `> 99` (R4b each); a window-wide write counter in the
fingerprint (R2, R3, R4, R5). Not reddened: the graft site loosened (above), `colorScheme` alone (above).

**Measurement (2026-10-15 UTC, release, `zsh docs/probes/perf-baselines.sh release bracketenv`, arms alternating in one process, 8
rounds of 14 drags of 20 steps, 5 warm frames; the Mac shared with other workflows, so the ratio to `.value` is the reading).**
Before (`git archive` of `6273e3a4` with the new fixture and harness copied in, load average 167.8 / 151.3 / 154.0): thread-CPU
ms per drag frame, median / minimum: `.value` 5.545 / 4.713, `.environment` 8.691 / 7.476, `.environmentObject` 8.597 / 7.464 (wall
medians 10.2 / 15.8 / 19.1, load-dominated). After (`7d87822c`, load 123.7 / 135.0 / 146.4): `.value` 5.377 / 4.713,
`.environment` 5.413 / 4.787, `.environmentObject` 5.538 / 4.811 (wall medians 12.4 / 14.5 / 14.7). The environment arms' last-frame
work equals `.value`'s (156 requests, 160 prepaints, 178 paints, 32 hits, 32 grafts). Not pinned (`BL-`).

**Elsewhere.** The fourteen offscreen images read 0 px against `6273e3a4` (`compare.sh`, controls as recorded); the Linux image ran
340 tests of `MetalUITestingTests` and `EnvironmentReadingTests`, all passed; the inventory and undocumented scripts print nothing.
