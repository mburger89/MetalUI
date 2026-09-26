# 57 — Data and scrolling (plan task 10, part 1)

Branch `feat/data-and-scrolling` from `e7bc2e7`. Spec
`docs/superpowers/specs/2026-09-25-data-and-scrolling-design.md`; decisions
`docs/superpowers/2026-09-25-data-and-scrolling-decisions.md` (`DD-A`…`DD-P`,
next unused `DD-Q`); probes `docs/probes/swiftui-data-and-scrolling.swift`
(new) and `docs/probes/swiftui-scrollviewreader-scope.swift` (new, critic
round). §1 is the baseline and scope; §2–§4 are lanes 1–3's own sections,
written so their measurements were not lost before this Record phase; §5 is
this phase's independent close; §6–§9 are the reference-table updates; §10
is the part-2 hand-off.

Plan task 10 is split in two by the workflow that runs it. **This is part 1**:
`ForEach`/identified-data semantics, a SwiftUI `Binding` (the `KeyBinding`
alias deleted in the same change), the `List`/`ScrollView` limitations that
blanked or staled an ordinary layout, and programmatic scrolling/indicators.
Part 2 (common controls and selection, and every item `DD-J` re-owns to it)
is the next run; **the plan's task 10 box stays unticked**.

## 1. Baseline and scope

`e7bc2e7`, worktree with its own `.build`: `swift build --build-system native
--build-tests`, then unfiltered `swift test --build-system native
--no-parallel` → **`Test run with 1506 tests in 3 suites passed`**; the log
carries `FR-J no-argument frame: succeeded=` (guards ran); the one `warning:`
SwiftPM's deprecation notice; 0 goldens (stage 7a); 90 typecheck guards.

`DD-A` collects every item addressed to plan task 10 (grep over
`docs/record/` and `docs/superpowers/*.md`/`specs/`) into the spec's §2 audit
table and three disjoint-file lanes, run in order because lane 3's test 3.10
needs lane 1's `ForEach` and lane 3 edits files lane 2's commit introduces
(`DD-A`'s critic-round amendment moved `DD-F`, the `List` origin, from lane 3
to lane 2 for exactly this reason — a lane that needs another's file
serialises the two and a red cannot be attributed to one lane otherwise).
Lanes 1 and 2 still share no file.

## 2. Lane 1 — `ForEach` and loop identity (`DD-B`, `DD-C`, `DD-L`)

Commit `b949ac2` (tests + implementation together — new API, so per the
spec's rule there is no red-before run for 1.1–1.10/1.12–1.16: the mutation
each names is the proof); `34dd123` (1.14b, `DD-C` item 3's windowed-row pin);
`845af64` (guard mutation readings recorded, no new tests). C2.4b's own arm
(`aShrinkingForLoopLeavesTheTrailingSiblingsStateAlone`) is a genuine
red-before: it read **2** at `e7bc2e7` (the retained divergence-74 answer)
and is inverted to assert **1**.

**What landed.** `ForEach<Data, ID, Content>` with SwiftUI's three
initialisers (`id:` keypath, `Identifiable` data, a `Range<Int>`) and the
typed `ProposalElementGroup` copy, sharing one production body (`DD-B`).
One structural slot per `ForEach` in its container's cursor space; one
identity level per element, named `GlobalElementID.child(of: slot, at:
offset, name: ElementID(String(describing: key)))`, under which the
element's content numbers from 0. A duplicate id (by value or by the minted
name, `DD-L`) is not produced a second time — divergence 79, added: SwiftUI
evaluates both (probe S6), MetalUI only the first, because two members at
one `GlobalElementID` is exactly what `ID-F`'s aliasing exists to repair.

`StateTable.noteLoop(_ slot:, extent:)`, called from all four minting copies
(`ArrayGroup`'s untyped and typed `requestGroupLayout`, `ForEach`'s untyped
and typed entries — each pinned on its own, M1b/M1f/M1g/M1i below). At
`sweep()`, for every slot noted **this** frame: a positional child at or past
this frame's extent and below last frame's is reset (a `for` loop's dropped
tail), and a named child the slot held last frame that this frame produced
**nowhere** is reset too (a `ForEach` element, or a `for` iteration carrying
`.id()`, dropped anywhere) — one reset pass, `$focus`/`$ax` exempted, the
same pass `ID-R` built. **Divergence 74 retires**: an element a loop stops
producing now starts fresh if it comes back, for `ForEach` and a bare `for`
alike, matching SwiftUI (probes F2, F3, F8; K2 — SwiftUI rejects `for` in a
builder outright, so `ForEach(0..<n)` is its nearest spelling and it resets,
F3). Only an *evaluated* loop resets (`sweep()` clears `loopExtents` after
the swap, so a loop noted in an earlier frame never reads as evaluated in
this one) — a `List`'s own rows are not a loop's children (`TB-AH`
unaffected).

### 2.1 Mutations

Each committed first (`b949ac2`/`34dd123`/`845af64`), the file restored from
a copy, the full unfiltered suite run, `git status --short` clean after each.

| # | mutation | reddens | 
|---|---|---|
| M1a | element scope minted `.positional(offset)` instead of the key's name | 1.1, 1.4 (first arm) |
| M1b | `ForEach`'s untyped `noteLoop` call removed | 1.2, 1.3, 1.9 |
| M1c | the element scope's `noteNamed` call removed | 1.2, 1.5, 1.7 |
| M1d | `ForEach` consumes no slot of its own | 1.6 |
| M1e | the per-frame duplicate-id dedupe removed (both halves) | 1.8 |
| M1f | the typed copy's `noteLoop` removed | 1.10 (alone) |
| M1g | `ArrayGroup`'s untyped `noteLoop` removed | 1.11 (C2.4b, inverted) |
| M1h | the sweep's named-children half removed (positional half kept) | 1.12 |
| M1i | the typed `ArrayGroup` copy's `noteLoop` removed | 1.13 (alone) |
| M1j | the loop rule resets every unmarked entry under the slot, not only departed direct children | 1.14 |
| V11 | `sweep()`'s `loopExtents.removeAll(keepingCapacity: true)` after the swap removed | 1.14b (row4-x/row4-y read 1, not 4) |
| M1k | the positional rule's `previous > extent` written `previous >= extent` | 1.15 (work counters move off 0) |
| M1l | the dedupe's name half removed | 1.16 alone (1.8 stays green on the value half) |
| G1.1 | `ForEach`'s `Range<Int>` initialiser made `internal` | `anExternalModuleCanWriteForEachOverIdentifiableKeyPathAndRangeData` |
| G1.2 | `ProposalElementGroup` conformance made unconditional, trapping body | `aForEachOfLegacyContentDoesNotCompileInsideAProposalStack` (filtered run, the trapping body would cut a full run short) |

V11 was re-verified at `845af64` (this Record phase's re-run, below);
G1.1/G1.2 were re-verified with the two guards' arms now discriminating
separately (G1.1's positive arm fails alone; G1.2's legacy arm succeeds
alone).

### 2.2 A second changed answer the design did not list (`DD-N`)

`DD-C`'s loop reset changes one more existing test than the design named:
`AnimationTests.swift`'s `aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop`,
whose loop arm — an animating subject inside `for _ in 0..<(show ? 1 : 0)`,
vanishing and returning — pinned divergence 74's **tombstone resumption**
(the `$anim` baseline survived; red before: **175**). Under `DD-C` the loop
resets the dropped iteration, `$anim` included, so the return frame snaps to
the declared **200**, exactly as the `if` arm already did. **The test is
renamed**, not retired: `aReturningAnimatingElementSnapsInsideAnIfAndInsideALoop`
(the old name states the retired behaviour), same assertion count, one value
inverted by ruling. The design missed it because it grepped for divergence
74's pin (C2.4b) and the source comments citing it, and this test's citation
("divergence 74, owner plan task 10") sits in a doc comment the grep did not
reach.

### 2.3 Exit

`git status --short` empty; final `845af64`: **1524 tests** (1506 + 18: the
design's 15 tests + 2 guards, plus 1.14b). Guards: `ForEachCompileGuards` 2
(new). No retirement row (1.11 is an existing test whose assertion changes
by ruling — a changed answer, not a removal).

## 3. Lane 2 — `Binding`, and the `List` origin (`DD-D`, `DD-E`, `DD-F`, `DD-O`)

Commit `107601e` (`Binding`, `$state`, `TextField`/`TextEditor` binding
initialisers, `KeyBinding` alias deleted — tests 2.1–2.10 + guards G2.1–G2.3,
new API, mutations M2a–M2j are the proof, "Suite: 1523" reported in the
commit is lane 1's own head, not yet re-measured with lane 2's tests — see
below); `8f624d7` (red-first, `DD-F`'s 3.1–3.5, genuine red-before since
`List.swift` already exists): `aListBelowAHeaderWindowsTheRowsOnScreen` built
`{8...16}` (DD14); `aListWhoseOriginChangesIsReWindowedOnTheNextFrame` left
`needsRedraw` false with the next frame never drawn; `aGrownViewportIsFilledOnTheNextFrameWithoutInput`
read `needsRedraw` false, 0 rows (DD13). `ccb78d3` (implementation: "Suite:
1540 tests" = 1524 + 16); `905fa34`, `25edf06` (guard mutation readings);
`03f714c` (the verifier round's 3.6, 2.3b, and the optional-binding init's
last-value pin — final "Full suite: 1542"); `e62ec89` (docs only, names V3/
V5/V6).

**What landed.** `Binding<Value>` — SwiftUI's `@propertyWrapper
@dynamicMemberLookup` surface (`init(get:set:)`, `.constant`, `wrappedValue`,
`projectedValue`, the dynamic-member subscript, the two optional
initialisers) — **`@MainActor`, unlike SwiftUI's nonisolated one**
(divergence 78, added: `Binding` cannot be created or read off the main
actor, since `State` already is and a binding's whole job is to reach it).
`State.projectedValue` now returns `Binding<Value>` through the box, so a
write resolves the slot at call time. **The deprecated `typealias Binding =
KeyBinding` is deleted in the same change** (`EV-N`'s announced break):
`Binding("cmd-k", A())` no longer typechecks (G2.1). `TextField`/`TextEditor`
gain `Binding<String>` initialisers forwarding to the controlled ones
(`text: binding.wrappedValue`, `onChange: { binding.wrappedValue = $0 }`);
nothing controlled moves.

**`DD-F`: divergence 14 retires.** In `prepaint`, a `List` inside a scroller
now stores its own origin within the scroller's content (`ScrollView` and
`ProposalScrollView` push an internal `ScrollerFrame` around their content's
prepaint; `PrepaintPass.deferred` resets the stack, so a `List` in a portal
sees none) at its own id through `withState` — **never** `write`, so this
cannot keep the display link awake (pinned by 3.4: an unbounded first frame
asks for nothing). `visibleRange` windows against `[offset − origin, offset
− origin + viewport)`. **Divergence 13 is amended, kept**: the first frame
after a resize still windows against last frame's extent, but the list now
calls `requestAnotherFrame()` exactly once when the fresh window is not
contained in the one it built, so the *next* frame is drawn correct — closing
divergence 13's *effect* (a grown viewport staying blank with no input,
DD13) without touching the two-row overscan divergence 13 itself still
names.

### 3.1 Mutations

| # | mutation | reddens |
|---|---|---|
| M2a | `State.projectedValue`'s setter a no-op | 2.1 |
| M2b | `.constant` stores into a box and reads it back | 2.2 |
| M2c | the dynamic-member setter drops the write | 2.3 |
| M2d | `wrappedValue`'s setter calls `set` twice | 2.4 |
| M2e | `init?` returns a binding over nil (a default) | 2.5 |
| M2f | `projectedValue` snapshots the value at creation | 2.6 |
| M2g | the projection writes `box.slotID` instead of `resolvedSlot` | 2.7 |
| M2h | the `TextField` binding initialiser's `onChange` ignores the edit | 2.8 |
| M2i | `TextEditor`'s twin of M2h | 2.9 |
| M2j | the binding initialiser passes `""` as the placeholder | 2.10 |
| G2.1 | a public `init(_: String, _: some Action)` added to `Binding` | `theKeyBindingAliasIsGoneSoBindingNamesTheValueBinding` (the guard's real negative arm turned out to be the bare `Binding("cmd-k", A())` inside a whole-file `@MainActor` function — a `Keymap`-wrapped spelling stays an error under this mutation too, so `M-G2.1` is the un-wrapped fixture) |
| M-G2.2b | `TextField`'s binding initialiser made `internal` (the design's `State.projectedValue → internal` does not compile: the compiler requires a wrapper's projection at the wrapper's own access level) | G2.2 |
| G2.3 | `@MainActor` removed from `Binding` (closures made `@Sendable`) | `aBindingIsMainActorIsolated` (divergence 78's pin) |
| M3a | `visibleRange` ignores the stored origin | 3.1 (red before: `{8...16}`) |
| M3b | `requestAnotherFrame()` removed from `List.prepaint` | 3.2, 3.3 (with M3c) |
| M3c | the containment test inverted | 3.3 |
| M3d | request whenever the fresh window differs (containment dropped) | 3.4 |
| M3e | `PrepaintPass.deferred` does not reset the scroller stack | 3.5 |
| V3 | the origin's subtraction dropped (`bounds.origin.y.value` alone) | 3.6 only (full run, 1542 tests, 2 issues — built `[5...13]`, row 14 on screen and blank) |
| V5 | the optional binding's getter never caches the last-read value | 2.5 only (1542, 2 issues) |
| V5b | the getter reads but never caches (only the last write remembered) | 2.5 only (1542, 1 issue) |
| V6 | the key-path subscript snapshots the base at creation | 2.3b only (1542, 1 issue: the second write reverted the first field) |

### 3.2 Two changed answers and a kept clamp the design did not list (`DD-O`)

1. **`ListLoweringTests.aLoweredListLaysOutEveryWindowedShape` arm B4** — a
   `List` under a 10pt padding layer in a scroller at offset 50 — built
   `3...16` ignoring the list's own origin; the list-local band is now
   40…140 (10pt down its content), so the window is `2...15`. Divergence 14's
   retirement measured on a second shape, not a new behaviour.
2. **`MeasurePerformanceTests.theResidentEntrySetStaysBoundedWhileScrolling10kRows`**:
   the cold frame's `StateTable` count moves `2n + 5` → `2n + 6` (one
   `ListOrigin` entry per scrolled `List`, at the list's own id — no new
   reserved name). `TB-AH`'s rule is unchanged; a table holding a scrolled
   `List` reaches the 256-entry bound one entry sooner.
3. **The window keeps its pre-`DD-F` clamp** on the list-local top (into
   `0…max(0, count × rowHeight − viewport)`) before rows are counted — at
   origin 0 this is the old window bit for bit, and with an origin it makes
   the window a superset of "intersecting" rows whenever the list is only
   partly inside the viewport, never an empty window that would draw one
   blank frame under a stale offset.

### 3.3 Exit

Final (`03f714c`): **1542 tests** (1524 + 18: the design's 15 tests + 3
guards − 1 deleted guard − 1 retired test, plus 2 tests the verifier round
added, 3.6 and 2.3b). Guards: `BindingCompileGuards` 3 (new),
`EnvironmentCompileGuards` 8 → 7 (`EV-N`'s alias guard deleted). Retirement
rows: `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`
(`EnvironmentCompileGuards`, deleted because the alias is — its fact is
inverted by G2.1); `aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`
(`ListTests.swift`, replaced by 3.1 — its synthetic `ScrollContext` harness
had no scroller, so it could never see a measured origin and would have
stayed green asserting the retired wrong answer).

## 4. Lane 3 — the scroll APIs and indicators (`DD-G`…`DD-I`, `DD-K`, `DD-P`)

Commit `f656270` (red-first, `ScrollViewReader`/`ScrollViewProxy` with a
no-op `scrollTo`, `UnitPoint`, `.visible`/`.never` with no behaviour): the
commit message reads "12 of 13 tests fail"; **the actual unfiltered run at
this commit read 10 of 13 failing with 25 issues** (3.6–3.13, 3.15, 3.16;
3.14 and both guards passed over the skeleton) — `DD-P` item 5 records the
discrepancy and leaves the wrong commit-message figure unamended, per this
file's own citation rule (state which reading survives). `6b82cd5`
(implementation, "Full suite: 1555" = 1542 + 13); `1b0063e` (3.14 gains the
typed entry's arm); `71251e4` (3.13b, the fix round's separating arm for the
`List`-path copy of the scope check — "Full suite: 1556").

**What landed.** `ScrollViewReader` — one slot with its own identity level,
content numbering from 0 under it — and `ScrollViewProxy.scrollTo(_:anchor:)`
(no public initialiser, G3.2). A `scrollTo` request carries `AnyHashable(id)`
and is enqueued on a window-owned queue; the next frame's prepaint resolves
it: `Frame.recordElementBounds`'s ancestor walk matches a pending key against
a `ForEach` element scope's typed key or a `List` row's `datum.id` **first**
(noted only while a request is pending, `DD-K` — steady frames pay one flag
read per loop), falling back to the `.id(_:)` name; the target is the first
element recorded at or under a matching name within the reader's scope. With
an anchor the target lands at `minY − anchor.y × (viewport − height)`; with
none, the least distance. Only the nearest enclosing scroller moves.
`ScrollIndicatorVisibility` gains `.visible` (behaves as `.automatic`) and
`.never` (behaves as `.hidden`) — SwiftUI's own measured macOS behaviour
(I1–I5), not stored-but-unread state; the enum's old `EP-5` doc comment
("a third case would be inert") is superseded, not merely amended.

**`DD-K` (critic round): keys compare by value, not description.** SwiftUI
distinguishes `AnyHashable(10)` from `AnyHashable("10")` (probes S3–S5); the
design's original "keys are described into the name" rule would have made
`scrollTo("10")` reach `.id(10)`, a divergence never measured before being
shipped. Superseded before landing.

### 4.1 Mutations (`DD-P`'s table)

| # | mutation | reddens | taken by |
|---|---|---|---|
| M3f | `scrollTo`'s formula reads the target's `maxY` | 3.6 | implementer |
| M3g | a nil anchor treated as `.top` | 3.7 (first two arms) | implementer |
| M3h | unresolved requests kept pending | 3.8 (second arm) | implementer |
| M3h-clamp | the clamp in `Frame.scrollOffset(bringing:into:anchor:)` removed | **nothing** — redundant: `ScrollChrome.resolvedOffset` re-clamps and writes back on its next read | verifier |
| M3i | `List`'s pending-request scan removed | 3.9 | implementer |
| M3j | the target is the union of a `ForEach` element's members | 3.10 | implementer |
| M3k | resolved against the outermost scroller frame | 3.11 | implementer |
| M3l | `ProposalScrollView` pushes no scroller frame | 3.12 (second arm) | implementer |
| M3m | the scope check dropped from `Frame.matchScrollRequests` | 3.13's S2 arm | implementer, verifier |
| V-ListScope | the same check dropped from `Frame.unresolvedScrollRequests(enclosing:)` (a *second*, unpinned copy — before the fix round: nothing, 1555 passed; after 3.13b: reddens its separating arm alone) | 3.13b | verifier, fix |
| M3n | the reader takes no slot (both entries share `proxy(under:at:pass:)`) | 3.14, both arms | verifier |
| M3n′ | the same, typed entry only | 3.14, typed arm only | implementer |
| M3o | `.never` falls through to the automatic path | 3.15 | implementer |
| M3p | keys matched by `String(describing:)` | 3.16's negative arms | implementer |
| M3q | typed keys noted with no request pending | 3.16's counter arm | implementer |
| MG4 | a plain `gridCellAnchor(_: UnitPoint)` overload | build failure — every leading-dot call site ambiguous against `UnitPoint`'s statics | verifier |
| MG4c | the same overload, `@_disfavoredOverload` | `aGridCellAnchorIsNinePoint` | verifier |

**The scope check existed twice, and only one copy had a pin** — the
copy-of-a-pinned-implementation shape: `.id` elements are matched in
`Frame.matchScrollRequests`, `List` rows through
`Frame.unresolvedScrollRequests(enclosing:)`, which carries its own
`isStrictDescendant` clause that 3.13's S2 arm (built from `.id` elements
only) never exercised. 3.13b — S2's shape over two readers each holding a
`ScrollView { List }` — is the second pin: reader B's own proxy moves B's
row to 1500 (control), reader A's proxy moves neither (the mutation's
separating arm).

### 4.2 Exit

Final (`71251e4`): **1556 tests** (1542 + 14: the design's 11 tests + 2
guards, plus 3.13b). Guards: `ScrollCompileGuards` 2 (new). No retirement
rows (the divergence-14 pin retired in lane 2).

## 5. This phase's independent close

Re-took, at `71251e4` (HEAD), everything the lanes measured, from a clean
tree (`swift package clean` first):

- **Build**: `swift build --build-system native --build-tests` — 0 `error:`,
  the one `warning:` SwiftPM's deprecation notice.
- **Suite**: unfiltered `swift test --build-system native --no-parallel` →
  **`Test run with 1556 tests in 3 suites passed`** (89.3s). The log carries
  `FR-J no-argument frame: succeeded=`; `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
  `theSevenRetentionSlotsAreMutuallyDistinct` all passed in this run.
- **Guards**: 90 → **96** (`grep -c canTypecheck` per file, one `typecheck`/
  `typecheckFile` call per hit, `UnitSafetyTests` read as 2 real guards, one
  grep hit a comment): `ForEachCompileGuards` +2, `BindingCompileGuards` +3,
  `EnvironmentCompileGuards` −1 (8 → 7), `ScrollCompileGuards` +2 — every
  other guard file's count unmoved from `e7bc2e7` (verified by diffing each
  file against `e7bc2e7`; only these four changed).
- **Goldens**: 0 (unmoved — stage 7a).
- **100 000-row list**: `METALUI_RUN_100K_LIST_TEST=1 swift test --filter
  aListsWorkIsTheSameFor100kRowsAsFor500` passed (27.5s; the figure is
  work/allocation-shaped, not a performance goal).
- **`MetalUILayout` imports only `MetalUICore`**: `grep -rh '^import '
  Sources/MetalUILayout/*.swift | sort -u` reads exactly `import MetalUICore`.
- **Pixels**: `docs/probes/demo-pixels/compare.sh <scratch> e7bc2e7 HEAD` —
  controls non-zero as recorded (default vs modal light 1031003, default vs
  animation light 454895, prod default vs modal 491221, distinct
  prod-default-light 529, f0 vs f3 and chrome-legacy-vs-proposal 0, no
  indicator rects) — **all fourteen images `differing=0`, scene identical**.
  No demo source changes: `ForEach`, `Binding`, `ScrollViewReader` and the
  `List`/indicator fixes touch no tree the demo builds.
  `Tests/MetalUICrossPlatformTests/Expected.swift` unedited.
- **`Backends/SDL`** (`PKG_CONFIG_PATH=$PWD/.accesskit swift test`, macOS):
  `ReplayFixtureTests` 21, `MetalUISDLTests` 22 — unmoved, as expected (no
  source in `Backends/SDL` touched by this branch).
- **`swift:6.4-noble` container** (root package, `--scratch-path` inside the
  container, source mounted read-only): `swift build` — 0 `error:`, 0
  `warning:` — confirms the portable targets (`MetalUI`, `MetalUIDemoContent`,
  `MetalUILayout`, …) still build off Apple with `ForEach`/`Binding`/
  `ScrollViewReader` added (none of the three source files added anything
  Apple-only — `ForEach.swift`/`Binding.swift`/`ScrollViewReader.swift` sit in
  `MetalUI`, which is already declared on every platform since `XP-A`).
- **`metalui-portable-ax` container** (Linux aarch64, `Backends/SDL`):
  `ReplayFixtureTests` 21, `MetalUISDLTests` 21 — unmoved.

Nothing above moved from the lanes' own readings; this phase found no new
issue.

## 6. Divergences (record §04): 74 and 14 retire; 13 amended; 78 and 79 added

**74 retires** (`DD-C`): an element a `for` loop stops producing no longer
keeps its state and gets it back if the loop regrows — it starts fresh, as
`ForEach` does and as SwiftUI's nearest spelling (`ForEach` over a range)
does. The label joins the never-reused list. **78 is added** (kept, pinned
wrong on purpose, `DD-D` item 4): `Binding` is `@MainActor`, where SwiftUI's
is nonisolated and `Sendable` — `Binding` cannot be created or read off the
main actor, pinned by `aBindingIsMainActorIsolated` (guard G2.3). **79 is
added** (kept, pinned wrong on purpose, `DD-L`): a `ForEach` whose ids
collide in description (`AnyHashable(1)` vs `AnyHashable("1")`) produces only
the first of them, where SwiftUI evaluates both (probe S6) — MetalUI cannot
give the two identities without risking the same aliasing `ID-F` exists to
repair. **14 retires and 13 is amended** (`DD-F`, section 3 above; record
§04's section carries both). Live count **56 → 56**: two retire, two are
added. (The first write-up of this section read "56 → 57" and left 14 out of
the arithmetic and out of record §04's section; corrected by the branch
checker.)

## 7. Declared but inert (record §05): no row added or deleted

`ScrollIndicatorVisibility`'s two new cases are SwiftUI's spellings with
SwiftUI's measured macOS behaviour (`DD-H`), not stored-but-unread state, so
no row is owed for them (the design's own `DD-M` rejects the reading that
they would be). `KeyBinding`'s deprecated alias is **deleted**, not merely
inert, and was never a row in this table. Nothing else this task touches was
declared-but-inert before.

## 8. Human verification (record §03): wheel-under-`.disabled` look owed

The wheel-under-`.disabled` question (`EV-Q`'s item for this task, `DD-I`
item 3) could not be measured: the screen was locked at design time and
again at the critic round (`CGSSessionScreenIsLocked = 1`, `displayAsleep
main: 1`), so `swiftui-data-and-scrolling.swift`'s W0 positive control never
passed and W1/W2 mean nothing. MetalUI's disabled `ScrollView` still scrolls
(`aDisabledScrollViewStillScrollsOnTheWheel`, unchanged, `EV-E`'s rule —
scroll regions are outside the disabled gate); whether SwiftUI agrees is
**a new look owed**, alongside the still-open real-window capture debt (the
lock probe read locked at every check across all three lanes and this
phase's own close — no new reading). If SwiftUI's disabled scroll view does
not scroll once someone can look, the fix is one line (`registerScrollRegion`
moved inside the gate) with a pinned test to invert.

## 9. Deferrals to part 2 (`DD-J`)

Re-owned to plan task 10's own part 2, or elsewhere, with reasons:

| item | owner |
|---|---|
| common controls, `controlSize`'s consumers (divergence 76), a `Button` control's existence | part 2 |
| selection (`List(selection:)`, controls' selection) | part 2 |
| `List` scrolling itself and answering greedily (K6), non-uniform rows, `List { ForEach }` | part 2 |
| divergence 32 (`List` publishes a table whatever its role), accessibility scrolling to unrealised rows | part 2 |
| two-axis scrolling (`CN-M`), divergence 54 (the cross axis) | part 2 |
| `scrollPosition(id:)` | part 2 (needs `Binding` + a topmost-element query) |
| `ForEach(_: Binding<C>)` | part 2 (crosses lanes 1/2; its consumer is a row of controls) |
| `Binding.transaction`/`animation(_:)`, animated `scrollTo` | plan task 13 |
| a layout-time `ScrollContext` from `ProposalScrollView` | the lazy stacks (`GR-L`'s G2); unscheduled |
| a `Hashable` `.id(_:)` overload | additive; none |
| `.visible` vs `.automatic` under "always show scroll bars" | unmeasured, no setting read; none |

## 10. Status

Spec `docs/superpowers/specs/2026-09-25-data-and-scrolling-design.md`:
**DELIVERED (part 1)**. Decisions doc: **DESIGNED, CRITICISED, REVISED, AND
DELIVERED**; next unused ruling id **`DD-Q`**. Plan task 10's checkbox stays
unticked — see the plan's own dated progress note.

## 11. Branch checker (adversarial, `e7bc2e7..054d755`)

- **Clean build and full suite, re-taken**: `swift package clean`, `swift
  build --build-system native --build-tests` (0 `error:`, the one `warning:`
  SwiftPM's deprecation notice), unfiltered `swift test --build-system native
  --no-parallel` → `Test run with 1556 tests in 3 suites passed`; the log
  carries `FR-J no-argument frame: succeeded=`. Guards 96 (`grep -c
  canTypecheck`, 94 in `Tests/MetalUITests` plus `UnitSafetyTests`' 2 of 3
  hits). `cmp CLAUDE.md AGENTS.md` clean. Every `DD-` id cited in a changed
  doc resolves to a heading; every test name cited in an added line resolves
  to a `func`, except three cited as retired or renamed
  (`aListNotAtTheScrollersContentOriginWindowsAgainstTheWrongRows`,
  `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`,
  `aReturningAnimatingElementSnapsInsideAnIfAndResumesInsideALoop`).
- **Two mutations of the checker's own**, each a full unfiltered run with the
  source restored from a copy and `git status --short` empty after:
  - **MA** — `StateTable.queueLoopResets`' named half keyed on
    `previousLoopExtents[parent] != nil` instead of `loopExtents[parent] != nil`
    (a loop's dropped names reset even when the loop was not evaluated this
    frame; `DD-C` item 3): 1556 tests, **2 issues, both in
    `aLoopInsideAWindowedListRowKeepsItsStateWhileTheRowIsOut`** (`row4-x`
    and `row4-y` not 4). Nothing else reddens.
  - **MB** — `Frame.applyScrollResolutions`' `requestAnotherFrame()` removed
    (a resolved `scrollTo` writes the offset but asks for no frame to show
    it): 1556 tests, **1 issue, in `scrollToReachesAnUnrealisedListRow`**
    (`log.indices.contains(150)`). Every other `scrollTo` test drives its
    frames explicitly, so this one test is the whole pin for "and asks for
    that next frame".
- **Offscreen demo comparison re-taken** (`docs/probes/demo-pixels/compare.sh`,
  `e7bc2e7` → `054d755`): 0 differing, scene identical, in all fourteen
  images; controls non-zero as the script requires. **Real-window capture not
  taken**: the lock probe read `CGSSessionScreenIsLocked = 1` and
  `displayAsleep main: 1`.
- **The 100 000-row test** (`METALUI_RUN_100K_LIST_TEST=1`) passed;
  `everyProductionTreeBuildsOnAOneMegabyteThread`,
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` and
  `theSevenRetentionSlotsAreMutuallyDistinct` green in the full run.
  `MetalUILayout` imports only `MetalUICore`. `Backends/SDL` on macOS: 21 +
  22. A fresh `swift:6.4-noble` container: the root package's `swift build
  --build-tests` prints 0 `error:`/`warning:`, and `MetalUICrossPlatformTests`
  (10, `theDemoFrameMatchesTheValuesRecordedOnMacOS` among them) pass;
  `Expected.swift` is unedited.
- **Doc defect fixed**: the live divergence count. §6 and record §04's
  section read "56 → 57, one retires, two are added" and record §04's section
  omitted 14's retirement (and 13's amendment) that `DD-F`, §3, `CLAUDE.md`'s
  retired-label list and the README's all record. Two retire (74, 14), two are
  added (78, 79): **56 live**. Corrected in `CLAUDE.md`/`AGENTS.md` (the
  counts paragraph, the reference table's count and its task-10 sentence),
  record §04 (header, count, and new 14 and 13 bullets), §6 above, record
  `README.md` and the top-level `README.md`. The decisions doc's status line
  now says DELIVERED.
