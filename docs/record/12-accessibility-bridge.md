## Accessibility bridge (plan task 12, bridge half) — 2026-09-15 …

**This is the track's record, on `feat/ax-bridge` from `f64e58a`.**

- Spec: `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`.
- Rulings: `AB-A`…`AB-AG` in
  `docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`.
- Probes:
  - `docs/probes/swiftui-accessibility-bridge.swift`;
  - `docs/probes/swiftui-accessibility-bridge-rules.swift`;
  - `docs/probes/swiftui-accessibility-bridge-critic2.swift`;
  - `docs/probes/appkit-accessibility-overrides-typecheck.swift`;
  - `docs/probes/appkit-voiceover-signal-isolation.swift`;
  - `docs/probes/appkit-accessibility-activation-clients.swift`;
  - `docs/probes/appkit-accessibility-override-isolation.swift` and
    `appkit-accessibility-override-isolation-typecheck.swift` (lane 2).

The integration step, not this track, links this file from
`docs/record/README.md` and CLAUDE.md.

**Status: lanes 1 (tree and seam), 2 (AppKit bridge) and 3 (defaults,
modifiers, `List`) implemented; the human VoiceOver look is open.** The
design was revised after one critic round, and again after a second critic
round that followed lane 1 (its section is after lane 1's). Each lane appends
its own section below:

- the red run;
- the green run;
- counts re-taken from an unfiltered `swift test --no-parallel`;
- the named tests each mutation reddens.

### Design session (2026-09-15)

**First probe.** Run with `/usr/bin/swift` (Apple Swift 6.4); its output is
recorded in its header. What it established, arm by arm, is cited from the
decisions doc and not restated here. Two method findings are worth keeping
apart from the rulings:

- **Activation is needed to see anything.** An in-process SwiftUI host exposes
  **no** accessibility children until the process sets
  `AXEnhancedUserInterface` on `NSApp` (arms 1, 2). A probe without that line
  concludes that SwiftUI exposes nothing.
- **Only KVC reads SwiftUI's nodes.** They are invisible to
  `as? NSAccessibilityProtocol`, and they answer `nil` to the informal
  `accessibilityAttributeValue(_:)` API. KVC on the modern selectors reads them.
  `responds(to:)` is true for everything and proves nothing (`AB-S`).

**Typecheck of the AppKit override spellings.** The first session checked them
in a scratch file, which could not be re-run. The critic round committed it as
`docs/probes/appkit-accessibility-overrides-typecheck.swift`:

- as committed, with
  `xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors`: exit 0;
- with the negative control uncommented (`accessibilityFocusedUIElement`
  spelled as a method): `:41:19: error: method does not override any method
  from its superclass`.

`accessibilityFocusedUIElement` is a property on `NSView`.

**By reading, not yet measured.** `Frame.emitAXNode` stores untranslated
bounds, so a node inside a scrolled `ScrollView` reports its content-space rect
(`AB-E`). Lane 1's `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` is
the first measurement. It is written first as a Frame-only test that compiles
on `f64e58a`, and it is expected to read 100.

### Critic round (2026-09-15)

The critic raised fourteen findings. The decisions doc's last section maps each
to a ruling. What is worth keeping here is method.

**The critic's arms reproduced exactly.** R0–R7 and Q were re-run from the
critic's scratch probe before any of them was believed, and each read what the
critic reported. They are committed in `swiftui-accessibility-bridge-rules.swift`,
together with the session's R8–R18.

**A KVC read can crash the probe.** The first run of the rules probe died with
`NSUnknownKeyException`: `accessibilityRows` is not KVC-compliant on SwiftUI's
`AccessibilityNode`. That is the opposite hazard to `AB-S`'s "`responds(to:)`
is true for everything". The first probe got away with it only because its
arms never asked a SwiftUI node for rows. The rules probe asks only
`NSTableView` for rows.

**What changed shape, and why it matters to an implementer:**

- **Records, not emissions (`AB-U`).** Synthesized nodes never write
  `Frame.axNodes` or `StateTable`. The first design routed them through
  `emitAXNode`, whose `$ax` write would have made `@State` retention depend on
  whether VoiceOver was running.
- **Resolution moved into the builder.** SwiftUI distributes a label through
  containers and wrappers before the text rules apply (`AB-T`; arms R3, R4, R8,
  R15). So the label-to-value move must see the undistributed declaration, and
  cannot happen at `registerHandlers` time.
- **Geometry split from structure (`AB-K`).** Every animation tick changes
  frames. With frames inside the structure's `Equatable`, the bridge would have
  rebuilt its element map every tick.
- **Elements are lazy (`AB-X`).** The first design created elements eagerly,
  which together with `MP-I`'s unbounded first frame would have made about 200k
  objects and posts for a 100k-row list opened under VoiceOver.
- **The zero-area filter is gone (`AB-O`).** Arm R6 shows SwiftUI publishes a
  zero-height labelled view. The filter had also been hiding unsized
  (`EP-8` 0×0) fixtures in the first spec's tests. The real target was
  `display: none`, and arm R9 confirms SwiftUI hides it.

**Two critic requirements rejected, with reasons (`AB-Y`).**

- The demo's row string is not changed, because the modifier-composition track
  requires its demo capture unchanged.
- The modal panel is not labelled, because a label would hide the modal's text.

The script below compensates for both.

### Lane 1 — tree and seam (2026-09-15)

Commits on `feat/ax-bridge`: `bc3fbdc` (tests, red, with a compiling
skeleton), `78bc8ea` (implementation), `f7555e1` and `c6922f7` (tests added or
strengthened under `AB-AA`). `swift package clean` ran before the
first build, as the spec requires.

**First red, before any skeleton.** `f64e58a` plus the Frame-only half of
`aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame`, run alone:
`Expectation failed: (target2.frame.origin.y → Pixels(value: 100.0)) == (60 → Pixels(value: 60.0))`.
The design session's "by reading, expected to read 100" is now a measurement.
The whole suite on that tree: `Test run with 1085 tests in 1 suite failed …
with 1 issue` (1084 at `f64e58a`, plus this test).

**Red run on the skeleton commit** (`swift test --build-system native
--skip-build --no-parallel --filter AccessibilityTreeTests`):
`Test run with 14 tests in 0 suites failed … with 16 issues`.

| test | red line |
|---|---|
| `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot` | `(activeFrame.axEmissions.count → 0) == 1` |
| `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes` | `.activate` answered `false`; `needsRedraw → false`; `(publishedAccessibilityTrees.count → 0) == 1` |
| `childrenFollowDeclarationOrderWhereIDsAloneCannot` | `id(labelled: "c") → nil` |
| `aNodesParentIsItsNearestEmittingAncestor` | `id(labelled: "outer") → nil` |
| `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` | `id(labelled: "B") → nil` |
| `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` | `origin.y → 100 == 60`; `id(labelled: "target") → nil` |
| `aPressRequestRunsOnClickThroughTheLastFramesHitboxes`, `aPressIsRefusedWhereHitTestingIsDisabled`, `anIncrementRequestRunsTheAdjustmentHandler`, `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt` | `publishedAccessibilityTrees.last → nil` |
| `anUnchangedFrameIsNotRepublished` | `(buildsAfterFirst → 0) >= 1` |
| `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce` | `id(labelled: "divider") → nil` |
| `aLabelledListIsStillATable` | `id(labelled: "Contacts") → nil` |
| `anInactiveWindowBuildsAndPublishesNothing` | **green**, as it must be: nothing collected before lane 1 either. Its evidence is M01, M03, M04 |

`declaredRolesLabelsValuesAndTraitsReachThePublishedNode` was added after the
builder and was green on arrival; its evidence is M15, M24, M26–M29, M35.

**Green.** After the implementation, native build system: `Test run with 1098
tests in 1 suite passed`. At lane 1's last commit, **default build system**
(`swift test --no-parallel`, full build): **`Test run with 1099 tests in 1
suite passed`, 0 `error:`, 0 `warning:`**. Goldens: 97, unchanged against
`f64e58a`. Typecheck guards: none added.

**Mutations.** 35, each applied to committed source, built, run against the
**unfiltered** suite (native build system), and restored with `git checkout`
(clean `git status` checked after each). No other agent was live in this
worktree. "Reddens" lists every failing test; counts are at 1099 tests
(M08, M30, M33 re-taken after `c6922f7`; the rest at `f7555e1`, before
`hiddenContentIsNotPublished…` gained its focus arm. That arm only adds
assertions, so a row it already reddened stays red; a row that did not name it
was not re-taken).

| # | mutation | reddens |
|---|---|---|
| M01 | record regardless of `collectsAccessibility` | `aFrameThatDoesNotCollect…`, `anInactiveWindowBuildsAndPublishesNothing` |
| M02 | also route a synthesized record through `emitAXNode` | `aFrameThatDoesNotCollect…` |
| M03 | `Window` builds every frame with `collectsAccessibility: true` | `anInactiveWindowBuildsAndPublishesNothing` (`lastEmissionCount`) |
| M04 | drop the `isActive` guard in `frameDidRender` | `anInactiveWindowBuildsAndPublishesNothing` |
| M05 | `.activate` does not dirty | `anActivationRequestDirties…` |
| M06 | `activate()` answers `true` every time | `anActivationRequestDirties…` (the second activation dirties) |
| M07 | reverse record order in the parent pass | `childrenFollowDeclarationOrder…`, `hiddenContentIsNotPublished…`, `portalContentIsARoot…` |
| M08 | parent pass iterates the record dictionary's keys | `portalContentIsARoot…` only, in both runs. **`childrenFollowDeclarationOrder…` survived it twice**: iteration order over three keys happened to match declaration order in both arms. Not a clean mutant; M07 is that test's killing mutation |
| M09 | parent is `id.parent` or nothing, no walk | `aNodesParentIsItsNearestEmittingAncestor`, `childrenFollowDeclarationOrder…` |
| M10 | parent walk ignores portals | `portalContentIsARoot…` |
| M11 | `emitAXNode` stores untranslated bounds | `aNodeInsideAScrolledScrollView…` |
| M12 | `visibleFrame` is the unclipped frame | `aNodeInsideAScrolledScrollView…` |
| M13 | `hasSameStructure` also compares geometry | `aNodeInsideAScrolledScrollView…` |
| M14 | `.press` answers `true` without running `onClick` | `aPressRequestRuns…`, `aPressIsRefused…`, `anUnchangedFrameIsNotRepublished` |
| M15 | advertise `.press` on every node | `aPressRequestRuns…`, `aPressIsRefused…`, `anIncrementRequest…`, `declaredRolesLabelsValuesAndTraits…` |
| M16 | derive `.press` from `record.isClickable`, not hitboxes | `aPressIsRefusedWhereHitTestingIsDisabled` |
| M17 | build `focused` from the handed-in focus | `publishedFocusIs…` (its last arm, added under `AB-AA`) |
| M18 | `.focus` skips the `isFocusable` check | `publishedFocusIs…` |
| M19 | publish without the `!=` check | `anUnchangedFrameIsNotRepublished` |
| M20 | no `display: none` suppression | `hiddenContentIsNotPublished…` |
| M21 | drop zero-area records | `hiddenContentIsNotPublished…` |
| M22 | no seen-set (one entry per record) | `hiddenContentIsNotPublished…` |
| M23 | swap increment and decrement | `anIncrementRequest…` |
| M24 | advertise adjustment on every node | `anIncrementRequest…`, `aPressRequestRuns…`, `aPressIsRefused…`, `declaredRolesLabelsValuesAndTraits…` |
| M25 | `.table` only from a `container` with `logicalCount` | `aLabelledListIsStillATable` |
| M26 | `.text` maps to `.group` | `declaredRolesLabelsValuesAndTraits…` |
| M27 | ignore `.disabled` | `declaredRolesLabelsValuesAndTraits…` |
| M28 | ignore `.selected` | `declaredRolesLabelsValuesAndTraits…` |
| M29 | a clickable `container` becomes `.button` | `declaredRolesLabelsValuesAndTraits…` |
| M30 | publish `focused` even when that id published nothing | **green at first (1099 passed)**; after `AB-AA`'s hidden-focus arm: `hiddenContentIsNotPublished…` |
| M31 | `isFocusable` always `false` | `publishedFocusIs…` |
| M32 | `hasSameStructure` ignores `nodes` | `aNodeInsideAScrolledScrollView…` |
| M33 | suppression ignores the scope's exception | **green (1099 passed)** — no lane-1 caller passes one; owned by lane 3 (`AB-AA`) |
| M34 | never increment the portal ordinal (every portal is 0) | `portalContentIsARoot…` |
| M35 | `value` copies `label` | `declaredRolesLabelsValuesAndTraits…` |

**Performance, by count.** With no client, lane 1 adds one `Bool` read per
`registerHandlers` call, one per `Element.prepaintGroup`, and one `Int` store
per drawn frame; `anInactiveWindowBuildsAndPublishesNothing` pins
`buildCount == 0` and `lastEmissionCount == 0` over three frames of a `List`
and a click target (M01, M03, M04 redden it). `aFrameThatDoesNotCollect…` pins
equal `StateTable.count` with and without collection (M02). No allocation
instrument was used (`AB-M`).

**Deferred from lane 1** (`AB-AA`): the suppression exception (lane 3's first
reader), distinct ordinals for nested portals, a hidden root element, and the
`logicalIndex` strip and `.row` role (lane 3). `AppKitWindow` only stores the
published tree; lane 2 forwards it. No human look is owed by lane 1.

### Second critic round (2026-09-15, after lane 1)

The critic raised fifteen findings against the design and lane 1 as recorded
above. The decisions doc's "Second critic round" section maps each to what was
done; nothing was rejected outright, and four were settled by recording a
divergence or a hazard instead of changing behaviour (findings 3, 4, 13, and
the machine dependency in 6). What is worth keeping here is method.

**The critic's arms reproduced exactly, and three were added.** C0–C5, P0–P2
and E0–E2 were re-run from the critic's scratch files before any was believed,
committed as `swiftui-accessibility-bridge-critic2.swift`, and read what the
critic reported. The session added:

- **C5i**, which settled finding 4's weight: SwiftUI does not just move the
  label off an adjustable container, it copies the **adjustable action** onto
  each child (increment on either child runs the one closure). A MetalUI
  "fix" that distributed only the label would have matched SwiftUI's
  `AXStaticText` lines and silently lost the action.
- **C6 and C7**, which turned finding 12's "propagate the value" into a rule:
  two values join with `", "`, and the value follows the text carrying it, not
  the first position.

**An exit status that could not fail (finding 5).** The critic found that the
signal's first spelling warns and that `-warnings-as-errors` still exits 0 on
that diagnostic group. Reproduced, and the probe now shows both halves side by
side: `-D SPEC_SHAPE` prints the `#ActorIsolatedCall` warning with exit 0,
while `-D UNUSED_CONTROL` turns an ordinary unused-variable warning into an
error with exit 1. So the committed overrides probe's "exit 0" was never
evidence about isolation, and the new probe is read by `grep -c 'warning:'`.

**The two-process probe's first harness could not see anything.** Its first
run read `[]` in every phase, which would have read as "no client reaches the
host view". Every client request had failed with `-25204`
(`kAXErrorCannotComplete`): a script-hosted `NSApplication` that never called
`finishLaunching()` is not registered with the accessibility server. With that
line, the passive phase and a window listing still read `[]`, while a
focused-element query and a position query reach the spy. The tree-walk phases
never reached the spy (the script process could not make its window key, and
the client's elements resolved to `AXApplication`); the probe's header records
that limit rather than a positive control it did not get.

**Uncommitted lane-1 test changes (finding 10).** The worktree held an
uncommitted rewrite of `AccessibilityTreeTests.swift`, made after lane 1's last
commit: a new `eachLiveHandlerAloneMakesAnUndeclaredElementRecord` against
hunting mutants H05 and H06, a duplicated-id press arm (H02), a clickable
hidden box (H14), a six-child order fixture (M08), a popLayer arm, root order
and focus as structure, and the adjustment's dirtying. No build or test process
was running. It was run unfiltered as found (native build system:
`Test run with 1100 tests in 1 suite passed`), committed as `71805eb`, and the
**whole** mutation table below was re-taken against it rather than the rows it
touched.

**Hidden root (finding 14), red then green.** `aHiddenRootPublishesNothing`
on `71805eb` plus the test (native build system, filtered for the red line
only):

```
Expectation failed: (hiddenFrame.axEmissions → [2 records: the root 20×20 and "in" 10×10]).isEmpty → false
Expectation failed: (hidden.nodes.isEmpty → false) && (hidden.roots.isEmpty → <not evaluated>)
```

(The first line's record dump is abbreviated here; it printed both
`AXEmission`s in full.) `AB-AA`'s "unreachable, a hidden root draws nothing"
was wrong on its own terms: the root prepaints at 20×20. Fixed in
`Frame.render`, `6bd208c`. `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`
was green on arrival, as designed; M20 below proves it is not vacuous here.

**A mutation-runner hazard, hit once.** The runner restores each mutated file
with `git checkout -- <file>`. Run once while `Frame.swift` held the
**uncommitted** AB-AD fix, it restored `Frame.swift` to `HEAD` and silently
deleted the fix; the next commit then carried only the tests, and a second
batch ran without the fix (every row it produced named
`aHiddenRootPublishesNothing`, which gave it away). That commit was amended to
include the fix, and the batch discarded and re-taken. **Commit before running
a `git checkout`-restoring mutation runner**, or restore from a copy, as the
environment track's spec says.

#### Lane 1 mutations, re-taken (second critic round)

Each applied by a script as an exact text replacement to committed source
(`71805eb` for M01–M39, H02–H14; `6bd208c` for M40 and the M20/M08 repeats),
built with `swift build --build-system native --build-tests`, run as the
**unfiltered** suite with `swift test --build-system native --skip-build
--no-parallel`, the failing test names parsed from the log, and restored with
`git checkout`, with `git status --porcelain -- Sources Tests Package.swift`
checked clean after each. No other agent was live in this worktree; other
tracks' builds were running elsewhere on the machine, which affects no count
here. Every build succeeded, and every run printed its summary line (1100
tests, or 1102 at `6bd208c`).

| # | mutation | reddens |
|---|---|---|
| M01 | record regardless of `collectsAccessibility` | `aFrameThatDoesNotCollect…`, `anInactiveWindowBuildsAndPublishesNothing` |
| M02 | also route a synthesized record through `emitAXNode` | `aFrameThatDoesNotCollect…`, `eachLiveHandlerAlone…` |
| M03 | `Window` builds every frame with `collectsAccessibility: true` | `anInactiveWindowBuildsAndPublishesNothing` |
| M04 | drop the `isActive` guard in `frameDidRender` | `anInactiveWindowBuildsAndPublishesNothing` |
| M05 | `.activate` does not dirty | `anActivationRequestDirties…` |
| M06 | `activate()` answers `true` every time | `anActivationRequestDirties…` |
| M07 | reverse record order in the parent pass | `childrenFollowDeclarationOrder…`, `hiddenContentIsNotPublished…`, `portalContentIsARoot…` |
| M08 | parent pass iterates the record dictionary's keys | `childrenFollowDeclarationOrder…`, `portalContentIsARoot…`. **Repeated twice at `6bd208c`** (dictionary order is per process): `childrenFollowDeclarationOrder…` alone; then `childrenFollowDeclarationOrder…`, `hiddenContentIsNotPublished…`, `portalContentIsARoot…`. The six-child test reddened in **3 of 3** runs, where the two-child fixture had survived 2 of 2 |
| M09 | parent is `id.parent` or nothing, no walk | `aNodesParentIsItsNearestEmittingAncestor`, `childrenFollowDeclarationOrder…` |
| M10 | parent walk ignores portals | `portalContentIsARoot…` |
| M11 | `emitAXNode` stores untranslated bounds | `aNodeInsideAScrolledScrollView…` |
| M12 | `visibleFrame` is the unclipped frame | `aNodeInsideAScrolledScrollView…` |
| M13 | `hasSameStructure` also compares geometry | `aNodeInsideAScrolledScrollView…` |
| M14 | `.press` answers `true` without running `onClick` | `aPressIsRefused…`, `aPressRequestRuns…`, `anUnchangedFrameIsNotRepublished` |
| M15 | advertise `.press` on every node | `aPressIsRefused…`, `aPressRequestRuns…`, `anIncrementRequest…`, `declaredRolesLabelsValuesAndTraits…`, `eachLiveHandlerAlone…` |
| M16 | derive `.press` from `record.isClickable`, not hitboxes | `aPressIsRefusedWhereHitTestingIsDisabled`. **SwiftUI's side of `AB-H`'s recorded divergence (arm P1)**: that test is a divergence pin |
| M17 | build `focused` from the handed-in focus | `publishedFocusIs…` |
| M18 | `.focus` skips the `isFocusable` check | `publishedFocusIs…` |
| M19 | publish without the `!=` check | `anUnchangedFrameIsNotRepublished` |
| M20 | no `display: none` suppression in `prepaintGroup` | `hiddenContentIsNotPublished…`. **Re-run at `6bd208c`:** also `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, so the merge's check is live on this branch |
| M21 | drop zero-area records | `hiddenContentIsNotPublished…` |
| M22 | no seen-set (one entry per record) | `hiddenContentIsNotPublished…` |
| M23 | swap increment and decrement | `anIncrementRequest…` |
| M24 | advertise adjustment on every node | `aPressIsRefused…`, `aPressRequestRuns…`, `anIncrementRequest…`, `declaredRolesLabelsValuesAndTraits…` |
| M25 | `.table` only from a `container` with `logicalCount` | `aLabelledListIsStillATable` |
| M26 | `.text` maps to `.group` | `declaredRolesLabelsValuesAndTraits…` |
| M27 | ignore `.disabled` | `declaredRolesLabelsValuesAndTraits…` |
| M28 | ignore `.selected` | `declaredRolesLabelsValuesAndTraits…` |
| M29 | a clickable `container` becomes `.button` | `declaredRolesLabelsValuesAndTraits…` |
| M30 | publish `focused` even when that id published nothing | `hiddenContentIsNotPublished…` |
| M31 | `isFocusable` always `false` | `eachLiveHandlerAlone…`, `publishedFocusIs…` |
| M32 | `hasSameStructure` ignores `nodes` | `aNodeInsideAScrolledScrollView…` |
| M33 | suppression ignores the scope's exception (always suppressed) | **green (1100 passed)**, still. No lane-1 caller passes a non-nil exception; lane 3's `activatingBeforeTheFirstFrame…` owns it (`AB-AA`) |
| M34 | never increment the portal ordinal (every portal is 0) | `portalContentIsARoot…` |
| M35 | `value` copies `label` | `declaredRolesLabelsValuesAndTraits…` |
| H02 | a press runs the **first** hitbox for the id | `aPressRequestRuns…` |
| H05 | drop `isFocusable` from the synthesis condition | `eachLiveHandlerAlone…` |
| H06 | drop the adjustment term from the synthesis condition | `eachLiveHandlerAlone…` |
| H14 | `prepaintGroup` excepts the hidden element itself (`except: layout.id`) | `hiddenContentIsNotPublished…` |
| M36 | `hasSameStructure` ignores `roots` | `aNodeInsideAScrolledScrollView…` |
| M37 | `hasSameStructure` ignores `focused` | `aNodeInsideAScrolledScrollView…` |
| M38 | `popLayer` never pops the portal stack | `portalContentIsARoot…` |
| M39 | an adjustment does not dirty the window | `anIncrementRequest…` |
| M40 | no `display: none` check at `Frame.render`'s root (at `6bd208c`) | `aHiddenRootPublishesNothing` |

**Against the first table.** Rows that changed: M02, M15 and M31 also redden
the new `eachLiveHandlerAlone…`; M08 is now a clean kill; M30 reddens on its
own rather than only after `AB-AA`; M20 reddens the merge check. Every
first-table row still reddens at least what it named. H02, H05, H06 and H14
are the hunting mutants the uncommitted tests were written against, each named
in a test comment and each now killed. M33 is the only survivor.

**Green, and counts, at `6bd208c`.**

- Default build system (`swift test --no-parallel`, unfiltered):
  `Test run with 1102 tests in 1 suite passed after 23.273 seconds`,
  0 `error:`, 0 `warning:`.
- Native build system, unfiltered: `Test run with 1102 tests in 1 suite
  passed`, 0 `error:`, 0 `warning:`.
- 1102 = 1099 at lane 1's record, + `eachLiveHandlerAlone…` (`71805eb`),
  + `aHiddenRootPublishesNothing` and
  `aHiddenInnerModifierLayerSuppressesEverythingInsideIt` (`6bd208c`).
- Goldens: `find Tests -name "*.json" | wc -l` reads 97, and
  `git diff --stat f64e58a -- '*.json'` is empty.
- Typecheck guards: none added.

**Owed to the integration step, from this round** (it owns CLAUDE.md and record
§05):

- **An inert-table row if lane 2 slips.** On lane 1 alone the bridge is inert in
  production: `AppKitWindow.publishAccessibilityTree` only stores the tree,
  nothing in AppKit sends `.activate`, and `AccessibilityAdjustment` has no
  AppKit effect. Row: "`PlatformWindow.publishAccessibilityTree` /
  `onAccessibilityRequest` on `AppKitWindow` — stores the tree, sends nothing;
  no client can activate a window until lane 2's host-view overrides land".
  Delete it when lane 2 merges.
- **`AXNode.actions`** stays a declared-but-inert field (`AB-H`).
- **Demo `StateTable` figures.** Lane 3's demo labels are declared nodes and
  write `$ax` slots, so CLAUDE.md's warm resident counts (165 at 40 rows, 63 at
  500) go stale when lane 3 lands; re-take them from record §07's harness.

### Lane 2 — AppKit bridge (2026-09-15)

Commits on `feat/ax-bridge`: `b7474f9` (tests, red, with a compiling
skeleton), `7dfdc6d` (implementation, `AB-AE`), `dbfa314` (three tests
strengthened against surviving mutants). Rulings added: `AB-AE` (the overrides
are nonisolated), `AB-AF` (lane 2 as built). No other agent was live in this
worktree.

**What landed.** `Sources/MetalUIPlatform/AccessibilityTreeChanges.swift` (the
neutral structural diff) and `Sources/MetalUIPlatform/AppKit/AppKitAccessibility.swift`
(the poster and signal seams, `VoiceOverSignal`, `AppKitAccessibilityBridge`,
`AppKitAccessibilityElement`, the `MetalHostView` overrides, and
`mainActorAnswer`). Shared-file edits: `AccessibilityGeometry` gains `layer`
and `order` (`AccessibilityTree.swift`); `Frame.accessibilityGeometry` fills
`layer` (one argument); `AccessibilityTreeBuilder` fills `order` (four lines);
`AppKitPlatform.swift` gains the host view's stored bridge, `AppKitWindow`'s
bridge and forwards, `hostView` made internal, and the internal
`AppKitPlatform(device:accessibilitySignal:)`. `Platform.swift`, `Window.swift`,
`Passes.swift`, `ElementGroup.swift`, `Handlers.swift` and `Fakes.swift` are
untouched by lane 2.

**Red run on the skeleton commit** (`swift test --skip-build --no-parallel
--filter` over the 20 lane-2 tests and the two lane-1 tests that gained
`layer`/`order` pins): `Test run with 22 tests in 0 suites failed after 0.335
seconds with 40 issues`. One line per test (the first issue; all were
recorded):

| test | red line |
|---|---|
| `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` | `(h.host → MetalHostView).isAccessibilityElement()` false; `accessibilityRole() → "AXUnknown"`; `(children.count → 0) == 6` |
| `rolesLabelsValuesAndTraitsMapOneToOne` | `(top.count → 0) == 5` |
| `elementsAreCreatedOnlyWhenAClientReadsThem` | `h.bridge.isActive → false` |
| `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes` | `(first.count → 0) == 2` |
| `anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime` | `elements(h.host.accessibilityChildren()) → []).first → nil` |
| `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest` | `(top.count → 0) == 3` |
| `focusIsReportedFromTheTreeAndAFocusRequestIsSent` | `(top.count → 0) == 2` |
| `aTableReportsItsRowCountAndItsRowsTheirIndices` | `…accessibilityChildren()) → []).first → nil` |
| `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` | seven issues; e.g. `hitTest(screenPoint(5, 15)) → nil == "header"`, and the outside point answered **`<NSWindow>`**, not the host: a plain `NSView` is not an element, so it forwards to its window |
| `aHostQueryActivatesExactlyOnce` | `(h.log.requests → []) == [.activate]` |
| `aFocusedElementQueryDoesNotActivate` | `accessibilityFocusedUIElement → <NSWindow> === h.host` (three reads), and the control's `[] == [.activate]` |
| `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` | `appKit.accessibilityBridge.isActive → false`; `(delivered → []) == [.activate]` |
| `nothingIsPostedBeforeActivation` | `(h.poster.count(.layoutChanged) → 0) == 1` (the control half) |
| `aGeometryOnlyChangeTouchesNoElementAndPostsNothing` | `…accessibilityChildren()) → []).first → nil` |
| `destroyedIsPostedOnlyForElementsAClientWasHanded` | `(roots.count → 0) == 3` |
| `layoutChangedIsPostedOncePerClientRead` | the `#require` on the first root read → `nil` |
| `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` | `(top.count → 0) == 5` |
| `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick` | `window.accessibility.isActive → false`; `(children.count → 0) == 1` |
| `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient` | **green**, as the spec says it must be: arm Q's AppKit answer. Its evidence is L43 and L44 below |
| `aHeldElementWhoseIDIsAdoptedPressesTheAdopter` | `(before.count → 0) == 2` |
| `childrenFollowDeclarationOrderWhereIDsAloneCannot` (lane-1 pin) | `(orders → [0, 0, 0, 0, 0, 0, 0]) == Array(0..<7)`, both arms |
| `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` (lane-1 pin) | `try #require(tree.geometry[tip]).layer == Frame.rootLayer` |

**The first green build was not green: every override is nonisolated
(`AB-AE`).** The implementation's first build printed dozens of
`warning: main actor-isolated property … can not be referenced from a
nonisolated context`, on the element and on `MetalHostView` alike: AppKit's
`NSAccessibility` protocol and `NSAccessibilityElement` carry no main-actor
annotation, and the design's overrides probe had typechecked constant bodies.
The obvious helper, a `@MainActor () -> T` closure run under
`MainActor.assumeIsolated`, failed twice more: `T` must be `Sendable`
(`[Any]?` is not), and a closure capturing `self` is rejected with
`sending 'self' risks causing data races` — **a SIL diagnostic that
`-typecheck` does not print**, so the new typecheck probe is compiled with
`-emit-sil`, where its `CAPTURE` control reads 2 diagnostics and under
`-typecheck` reads 0. The adopted `mainActorAnswer(_:fallback:_:)` takes the
object as a parameter, boxes it and the answer, and returns the fallback off
the main thread. A two-process run (client trusted, three runs) saw an
out-of-process hit test arrive on the main thread; the fallback stays because
one entry point is not all of them. The 18th platform test,
`anOffMainThreadQueryAnswersNothingAndDoesNotTrap`, is an exit test, added
with the helper; its red evidence is L47.

**Two more things the first build found (`AB-AF`).**

- `'AccessibilityRequest' is ambiguous for type lookup in this context` in both
  new test files: `Accessibility.framework` exports `AXRequest` under that Swift
  name, and `AppKit` imports it. Any client file importing `AppKit` and `MetalUI`
  hits it on the bare name. Tests use a typealias; the rename is the
  integration step's.
- Making `AppKitWindow.onAccessibilityRequest` computed left the incremental
  link failing with `Undefined symbols … direct field offset for
  MetalUIPlatform.AppKitWindow.onAccessibilityRequest`; `swift package clean`
  fixed it (CLAUDE.md's Build-section hazard).

**Green, at `7dfdc6d`** (default build system, unfiltered, after a clean):
`Test run with 1123 tests in 1 suite passed after 24.191 seconds`, 0 `error:`,
0 `warning:`. 1123 = 1102 at lane 1's last record + 18 platform + 3
end-to-end. **Re-taken at `dbfa314`** (the strengthened tests; default build
system, unfiltered): `Test run with 1123 tests in 1 suite passed after 25.973
seconds`, 0 `error:`, 0 `warning:`. Goldens: `find Tests -name "*.json" | wc -l`
reads 97 and `git diff --stat f64e58a -- '*.json'` is empty. Typecheck guards:
none added (the new probe is a `docs/probes` file, not a suite guard).

**Mutations.** Each applied by a script as an exact text replacement to
committed source, built with `swift build --build-tests`, run as the
**unfiltered** suite with `swift test --skip-build --no-parallel`, the failing
test names parsed from the log, and restored with `git checkout`, with
`git status --porcelain -- Sources Tests Package.swift` checked clean after
each. Every build succeeded and every run printed its summary line (1123
tests).

**First round, at `7dfdc6d`**: 51 mutations (L01–L51). **Three survived** — L44 (`mouseDown` activates), L49 (`AccessibilityTreeChanges` ignores children), L50 (it ignores roles) — each confirmed a real behaviour change before it was banked: L44's mutant activates on any view `mouseDown`, yet the arm-Q test's control, added to find out, showed its mouse events had **never reached the view** (`inputs → ["key"]`: in the test process the app is inactive and the window not key, so `sendEvent` spent the click on activation); L49 and L50 change what posts `.layoutChanged`, and no arm changed only children order or only a role. Tests strengthened in `dbfa314` (the arm-Q test routes mouse events to the view after `sendEvent`, with a control; `layoutChangedIsPostedOncePerClientRead` gains reorder-only and role-only arms; the table test pins `AB-AF` item 5 and gains L52). Every other first-round row reddened at least what the re-take below names. **Hazard hit:** this round's runner was written into a scratchpad directory holding an earlier session's lane-1 runner, and overwrote its `run.py`, `defs.py` and `muts.json` (their logs survive; lane 1's table above was already recorded from them). The re-take ran from a directory of its own.

**Re-take, whole table, at `dbfa314`** (all 52, including every row the first round had already killed — practices doc, record failure 3). **No survivor.** Counts at 1123 tests throughout.

| # | mutation | reddens |
|---|---|---|
| L01 | host roots in dictionary order | `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `focusIsReportedFromTheTreeAndAFocusRequestIsSent`, `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged`, `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest`, `rolesLabelsValuesAndTraitsMapOneToOne`, `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` (dictionary order is per process: the first round also reddened `aHeldElementWhose…`; this run did not) |
| L02 | a root answers nil for its parent | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` |
| L03 | swap label and value | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aTableReportsItsRowCountAndItsRowsTheirIndices`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`, `hitTestingUsesVisibleFramesSoAClippedRowNeverWins`, `rolesLabelsValuesAndTraitsMapOneToOne`, `theHostViewIsAGroupWhoseChildrenAreThePublishedRoots` |
| L04 | staticText maps to group | `rolesLabelsValuesAndTraitsMapOneToOne` |
| L05 | ignore isEnabled | `rolesLabelsValuesAndTraitsMapOneToOne` |
| L06 | create elements in publish | `destroyedIsPostedOnlyForElementsAClientWasHanded`, `elementsAreCreatedOnlyWhenAClientReadsThem`, `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L07 | recreate every element on publish | `aGeometryOnlyChangeTouchesNoElementAndPostsNothing`, `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `destroyedIsPostedOnlyForElementsAClientWasHanded`, `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L08 | detach does not mark detached | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`. The spec named this "skip `isDetached` (the parent stays the host)" |
| L09 | a detached frame is .zero while the host is alive | `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes` |
| L10 | drop the flip (minY + y) | `aGeometryOnlyChangeTouchesNoElementAndPostsNothing`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime` |
| L11 | cache the screen rect on first read | `anElementsFrameIsItsHostRectInScreenCoordinatesReadAtQueryTime` |
| L12 | allow every action | `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest` |
| L13 | perform returns true regardless of the closure | `onlyAdvertisedActionsAreAllowedAndPerformingSendsTheRequest` |
| L14 | with nothing focused, report the first focusable node | `focusIsReportedFromTheTreeAndAFocusRequestIsSent` |
| L15 | the focus setter sends nothing | `focusIsReportedFromTheTreeAndAFocusRequestIsSent` |
| L16 | row count is children.count | `aTableReportsItsRowCountAndItsRowsTheirIndices` |
| L17 | row index is the position among its siblings | `aTableReportsItsRowCountAndItsRowsTheirIndices` |
| L18 | every row is visible | `aTableReportsItsRowCountAndItsRowsTheirIndices` |
| L19 | hit-test on the unclipped frame | `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` |
| L20 | hit test returns the first match | `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` |
| L21 | hit test considers roots only | `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` |
| L22 | hit test ranks by order alone | `hitTestingUsesVisibleFramesSoAClippedRowNeverWins` |
| L23 | drop the sticky activation flag | `aHostQueryActivatesExactlyOnce`, `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` |
| L24 | the focused-element query activates | `aFocusedElementQueryDoesNotActivate` |
| L25 | ignore the signal | `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery`, `elementsAreCreatedOnlyWhenAClientReadsThem` |
| L26 | send .activate on every true | `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` |
| L27 | deliver the signal through a Task | `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery`, `elementsAreCreatedOnlyWhenAClientReadsThem` |
| L28 | drop the pending send at onRequest assignment | `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` |
| L29 | post regardless of isActive | `aFocusedElementQueryDoesNotActivate`, `nothingIsPostedBeforeActivation` |
| L30 | geometry is structure | `aGeometryOnlyChangeTouchesNoElementAndPostsNothing` |
| L31 | frames come from the geometry at element creation | `aGeometryOnlyChangeTouchesNoElementAndPostsNothing` |
| L32 | post destroyed per removed id, on a fresh object | `destroyedIsPostedOnlyForElementsAClientWasHanded` |
| L33 | post destroyed per removed id, vending it | `destroyedIsPostedOnlyForElementsAClientWasHanded` |
| L34 | layoutChanged on every structural publish | `layoutChangedIsPostedOncePerClientRead` |
| L35 | never reset the read flag | `layoutChangedIsPostedOncePerClientRead`: 11 posts after the ten unread publishes. **The spec's parenthetical for its "never reset the read flag", "the third step posts 0", describes L36, not this** |
| L36 | an element children read does not re-arm | `layoutChangedIsPostedOncePerClientRead`: the third step posts 0 more, the spec's parenthetical |
| L37 | label changes post valueChanged | `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L38 | focus posts on the old element | `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L39 | label changes post for unvended ids | `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L40 | Frame fills layer with 0 | `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| L41 | the builder fills order with 0 | `childrenFollowDeclarationOrderWhereIDsAloneCannot` |
| L42 | AppKitWindow stores rather than forwards the tree | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick` |
| L43 | AppKitWindow drops the request handler | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aRunningScreenReaderActivatesTheWindowBeforeAnyQuery` |
| L44 | mouseDown activates | `aKeyWindowReceivingEventsIsNeverActivatedWithoutAClient`. **Survived the first round** (`inputs` never saw the mouse events: AppKit spent the click activating the inactive test app); killed after the test routes them to the view, with a control |
| L45 | detach an element whose label changed | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`, `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L46 | skip detaching (dropped from the map only) | `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aVendedElementKeepsItsIdentityAndIsDetachedWhenItsIDGoes`. The element is dropped from the map but not detached. **The spec expected arm 2's press to run `second`; it cannot**: `Window` finds no hitbox for the vanished id and refuses. Arm 2 reddens on `accessibilityParent() == nil` (`AB-AF` item 6) |
| L47 | no thread check before assumeIsolated | `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`: the child process traps, and the exit test reports it |
| L48 | removed ids in dictionary order | `destroyedIsPostedOnlyForElementsAClientWasHanded` |
| L49 | structureChanged ignores children | `layoutChangedIsPostedOncePerClientRead`. **Survived the first round**; killed by the reorder-only arm added in `dbfa314` |
| L50 | structureChanged ignores roles | `layoutChangedIsPostedOncePerClientRead`. **Survived the first round**; killed by the role-only arm added in `dbfa314` |
| L51 | rowCount changes are not diffed | `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged` |
| L52 | row selectors allowed on every role | `aTableReportsItsRowCountAndItsRowsTheirIndices`. Added with the selector-gate pin in `dbfa314`; not in the first round |


**Performance, by count.** Lane 2 adds nothing to an inactive window's frame:
`Window` publishes only while active (lane 1's `anInactiveWindowBuildsAndPublishesNothing`),
and the bridge's work is bounded by what a client read. Pinned counts:
`createdElementCount` 0 after publishing 1,001 nodes, 1 after the host read,
1,001 after the table read and unchanged on a second read
(`elementsAreCreatedOnlyWhenAClientReadsThem`, L06); 0 posts, 0 structural
publishes and 2 geometry publishes across a moved-then-repeated tree, with the
same element objects (`aGeometryOnlyChange…`, L30, L31); exactly 10 destroyed
posts for 10 vended of 30 removed (`destroyedIsPosted…`, L32, L33, L48); one
`.layoutChanged` across 10 unread structural publishes (`layoutChangedIsPosted…`,
L34–L36). No allocation instrument was used (`AB-M`).

**Deferred from lane 2, with owners.**

- **The `AccessibilityRequest` rename** (`AB-AF` item 1): the integration step.
- **The inert-table row "lane 1 alone is inert"** (second critic round, above)
  can be deleted when this lane merges: `AppKitWindow` now forwards both seam
  requirements and the host view activates.
- **Not wired or not measured here:** VoiceOver itself (the human script
  below, still open); the real `VoiceOverSignal`'s KVO flip (script item 1);
  whether every AppKit accessibility entry point arrives on the main thread
  (`AB-AE`: one observed); lane 3's defaults, so on this branch only declared
  nodes, `List` and live-handler synthesis publish, and a `Text` is silent.
- **The design's arm Q probe never confirmed its mouse events arrived** (its
  spy's `mouseDown` records nothing). Lane 2's end-to-end version found that in
  the test process they do not, and routes them to the view directly (L44).

### Verifier round on lane 2 (2026-09-15, at `b9e258e`)

A verifier re-ran the suite (1123 passed), all 52 L-rows (all killed; L01's
extra test is dictionary order, as above), and 18 hunting mutations of its own,
H01–H18. H05, H17 and H18 reddened; **fifteen left the suite green**
(fourteen pinned below; H14 deliberately not, see the end of this section). Its
issues were two majors (nested parents; unclipped versus visible frames) and
four minors. Every one was fixed with tests only — **no source line changed**
— in `9901f15`. The mutations below are the verifier's, re-spelled from its
descriptions, **renumbered V** because lane 1's table already uses H02–H14.
V-numbers match the verifier's H-numbers; V08b is added. Each ran on the whole
unfiltered suite with the runner described above (a new scratchpad directory,
so no earlier runner was overwritten), at `9901f15`, **1125 tests**.

**Test changes, by issue.**

1. *Nested parents (major).* `hitTestingUsesVisibleFramesSoAClippedRowNeverWins`
   walks host → table → row → row child and asserts each `accessibilityParent`
   `===` the element above it (two depths below a root), and that the hit test
   returns that same row-child object. `aTableReportsItsRowCount…` asserts
   every table child's parent is the table. New
   `aTreePublishedBeforeActivationAnswersItsParentsAfterIt` publishes a
   three-deep tree while inactive, activates with a children read, and reads
   the parents with no publish in between (`AB-AF` item 4).
2. *Unclipped frame (major).* `aTableReportsItsRowCount…` reads the overscan
   row's `accessibilityFrame` (frame y −8 height 28, visible height 0) and the
   table's (14,000pt tall, visible 100pt).
3. *Notifications (minor).* `labelValueRowCountAndFocusChanges…` gains a
   focus-clears arm (one post, on the host) and changes the unread node's value
   and row count, each alone in its publish, beside its label.
   `layoutChangedIsPostedOncePerClientRead` gains a hit-test arm and a
   focused-element arm, each preceded by an unread structural publish with a
   `#require` that the flag is clear.
4. *Detached state (minor).* In `aVendedElementKeeps…`, `b` has a child `bc`
   that is re-published as a root when `b` goes, and `b` is renamed `b2`
   while vended; the detached `b` must read `b2` and no children while `bc` is
   still published.
5. *Gates and filters (minor).* The table fixture gains a `.button` child
   (`sort`), which is a child and not a row, and refuses the index, row-count
   and rows selectors. The hit test gains two half-open edge points and a
   just-inside control: (10, 48) on the row's max-y edge answers `table`,
   (10, 47) answers `row`, and (200, 40) on every frame's max-x edge answers
   the host. New `theVoiceOverSignalDeliversTheCurrentValueSynchronouslyOnce`
   compares one synchronous delivery against `NSWorkspace.shared.isVoiceOverEnabled`
   as read on the machine, so it holds with VoiceOver on or off. The KVO flip
   stays unmeasured. The hit test keeps its own inline comparisons rather than
   calling `Bounds.contains`; the edge points pin the half-open rule instead.
6. *Arm Q's second environment dependency (minor).* The test now calls
   `mouseDown`/`mouseUp` directly **only when `sendEvent` did not deliver**
   (`inputs` unchanged), so an environment where AppKit delivers the click sees
   each event once, and the exact-sequence `#require` stays. The doc names this
   dependency beside the AX-client one. **Not measured in an environment that
   delivers**: in this process AppKit still swallows both clicks, so only the
   fallback branch ran. A mutation forcing the direct call cannot behave
   differently in a process where AppKit delivers nothing, so it was not run
   and nothing is banked for this change.

The verifier's H05, H17 and H18 had already reddened tests and were not re-run;
there is no V05, V14, V17 or V18.

| # | mutation | reddens |
|---|---|---|
| V01 | a non-root answers the host view (`_ = bridge.parents[id]; return bridge.hostView`) | `aTableReportsItsRowCount…`, `aTreePublishedBeforeActivation…`, `aVendedElementKeeps…`, `hitTestingUsesVisibleFrames…` |
| V02 | `publish` never calls `rebuildParents()` | the same four |
| V03 | `rebuildParents()` only after the `isActive` guard | `aTreePublishedBeforeActivation…` |
| V04 | hit test closed on both max edges (`<=`) | `hitTestingUsesVisibleFrames…` (2 issues) |
| V06 | a detached element's children read from `bridge`, not `liveBridge` | `aVendedElementKeeps…` |
| V07 | `detach` does not replace `lastNode` | `aVendedElementKeeps…` |
| V08 | `.valueChanged` vends and posts for unread ids | `labelValueRowCountAndFocusChanges…` |
| V08b | `.rowCountChanged` vends and posts for unread ids | `labelValueRowCountAndFocusChanges…` |
| V09 | focus clearing posts nothing | `labelValueRowCountAndFocusChanges…` |
| V10 | an attached element's frame converts `visibleFrame` | `aTableReportsItsRowCount…` |
| V11 | the host's hit test does not note a read | `layoutChangedIsPostedOncePerClientRead` |
| V12 | the host's focused-element query does not note a read | `layoutChangedIsPostedOncePerClientRead` |
| V13 | `accessibilityRows` keeps non-row children | `aTableReportsItsRowCount…` |
| V15 | `VoiceOverSignal` never delivers its initial value | `theVoiceOverSignalDelivers…` |
| V16 | the index selector allowed on every non-table role | `aTableReportsItsRowCount…` |

**Deliberately unpinned: the verifier's H14** (the host's hit test before
activation answers from the stored tree instead of the host view). In
production `Window` publishes only while active, so before activation the
stored tree is empty and both answers are the host view; the difference is
reachable only by a hand-published tree, which is a test harness shape.

**The 52 L-rows, re-taken at `9901f15`** (every fixture they read changed
shape; same runner, same directory, logs `L01.log`…`L52.log`, the V-rows'
logs keep the verifier's `H` names): **all 52 killed, no survivor**, every run
printing `Test run with 1125 tests`. Against the `dbfa314` table above, 48 rows
redden exactly the tests it names. The four that differ each redden a
superset, bar L01, which is dictionary order again:

- L01 reddens `aHeldElementWhose…`, `labelValueRowCount…`, `rolesLabels…` and
  `theHostViewIsAGroup…` — gaining `aHeldElementWhose…` and losing
  `aVendedElementKeeps…`, `focusIsReported…` and `onlyAdvertisedActions…`. A
  per-process hash seed decides which fixtures happen to publish more than one
  root in an order that disagrees with declaration.
- L02 (a root answers nil for its parent) also reddens
  `aTreePublishedBeforeActivation…` and `hitTestingUsesVisibleFrames…` — the
  parent walks added for V01.
- L03 (swap label and value) also reddens `aTreePublishedBeforeActivation…`,
  which identifies its elements by label.
- L10 (drop the flip) also reddens `aTableReportsItsRowCount…`, which now reads
  unclipped frames (V10).

**Green at `9901f15`**, after `swift package clean` (default build system,
unfiltered): `swift build --build-tests` printed 0 `error:` and 0 `warning:`;
`Test run with 1125 tests in 1 suite passed after 24.148 seconds`, 0 `error:`,
0 `warning:` in the test log. 1125 = 1123 + the verifier round's two new
platform tests. Goldens: 97, and `git diff --stat f64e58a -- '*.json'` is
empty.

### Lane 3 — defaults, modifiers, `List` (2026-09-15)

Commits on `feat/ax-bridge`: `2e5ca0a` (15 tests, red, with an inert modifier
skeleton), `aa5d055` (implementation, demo labels, and lane 1's portal fixture),
`15f0dd2` and `ecb0504` (tests strengthened against the first and second
mutation rounds), and the docs commit that follows them (this section,
`AB-AG`, the spec's "Lane 3 as built", two source doc comments). Ruling added: `AB-AG`. `swift package clean` ran before the first
build, as the spec requires. No other agent was live in this worktree.

**What landed.** `AXNode.logicalIndex` (internal) and its strip in
`Frame.registerHandlers`; `Frame.requestAccessibilityRetry()` and
`wantsAccessibilityRetry`; `WindowAccessibility.frameDidRender(…retry:…) -> Bool`
and `Window`'s dirtying on it; `Text.prepaint` passing its non-empty string;
`OnTapModifier.prepaint` passing `synthesizesAccessibility: false`; the
builder's steps A (distribution), B (text resolution) and C (combination) and
the `.row` role; `List`'s row indices, unbounded-window suppression and retry;
`Sources/MetalUI/AccessibilityModifiers.swift`; the demo's three labels.
Shared-file edits: `Frame.swift` (the strip, the retry, two doc lines),
`Window.swift` (the retry's `if`), `Passes.swift` (one doc line), `Text.swift`,
`NativeTappable.swift`, `List.swift`, `AXNode.swift`, the demo's `main.swift`;
`ElementGroup.swift`, `Handlers.swift`, `Platform.swift` and `Fakes.swift` are
untouched.

**Red run on the skeleton commit** (`swift test --skip-build --no-parallel
--filter AccessibilityDefaultsTests`, after a clean build):
`Test run with 15 tests in 0 suites failed after 14.804 seconds with 26 issues`.
**Every test was red**, including `aClientDoesNotChangeStateRetention`, which
the spec expected green; the tests the spec expected not to compile compiled
against the skeleton and failed on behaviour:

| test | red line (first issue; all 26 recorded in the run log) |
|---|---|
| `aTextIsPublishedAsStaticTextWhoseValueIsItsString` | `(tree.roots.count → 0) == 2` |
| `labelAndValueFollowSwiftUIsStaticTextRules` | `(labelled.rootNodes → []).first → nil` |
| `aClickableTextIsAButtonLabelledByItsString` | `(go.label == "Go" → false)`: the button published with no label |
| `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` | `(container.nodes.count → 0) == 2` |
| `aClickableContainerCombinesItsTextsIntoOneButtonLabel` | `(combined.label == "A, B" → false)`; `(interactive.nodes[kept]?.children.count → 1) == 3`; each of C3, C7, C6, C4's label check `→ false` (six issues) |
| `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel` | `(tree.roots.count → 1) == 2` |
| `theAdjustableActionModifierRegistersTheAdjustmentHandler` | `(platform.publishedAccessibilityTrees → []).last → nil` (the skeleton modifier registered nothing, so nothing recorded) |
| `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` | `(rows.count → 0) == 12` |
| `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` | `window.needsRedraw → false` after frame 0; `(window.framesDrawn → 1) == 2`; `(table1.children.count → 0) == 10`; cap arm `capped.needsRedraw → false`, `(capped.framesDrawn → 1) == 2` (five issues). **Frame 0's `lastEmissionCount <= 3` held**: before lane 3 rows recorded nothing at all |
| `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` | `(vended.count → 0) == 10` |
| `anAnimationWithAClientActivePostsNothingAndTouchesNoElement` | `feed.bridge.rootElements().first → nil`: the skeleton's label recorded nothing, so nothing published |
| `aClientDoesNotChangeStateRetention` | `(active.accessibility.lastEmissionCount → 11) >= 140`: the ten click targets and the list, no text. **The spec's "green before" was wrong for this fixture**: its shape-15 `#require` is what reddens, because texts did not record before lane 3 |
| `synthesizedNodesCostNothingWhileNoClientIsActive` | `!((tree.all(.row) → []).isEmpty)`: the bounded-list control |
| `anOnTapModifierPublishesNothingButItsHitboxStillPresses` | `(window.accessibility.lastEmissionCount → 1) == 0`; `lastPublished.nodes` held one `.button` with `label: nil`, `actions` press — the unlabelled button `AB-Y` predicted |
| `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` | `(hidden.rootNodes.map(\.value) → []) == ["shown"]`: its text did not record. Its hidden-list assertion held; the rule it guards is live only once `List` opens its own scope (its evidence is N29) |

**The first green run was not green: one lane-1 test** (`AB-AG` item 3). The
filtered accessibility run (56 tests) failed once, in
`portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`:
`tree.id(labelled: "after") → nil`, the tree dump showing the declared button
`"B"` with `children: []`. Step C had folded the declared sibling into the
button, as `AB-G` says it must. The fixture's `after` became focusable, and the
run read `Test run with 56 tests in 0 suites passed`.

**Green at `aa5d055`** (default build system, unfiltered, after the clean):
`swift build --build-tests` printed 0 `error:` and 0 `warning:`;
`Test run with 1140 tests in 1 suite passed after 30.542 seconds`, 0 `error:`,
0 `warning:` in the test log. 1140 = 1125 at lane 2's verifier round + 15.
**Green at `ecb0504` plus this lane's source doc-comment edits** (default
build system, unfiltered): `swift build --build-tests` printed 0 `error:` and
0 `warning:`; `Test run with 1140 tests in 1 suite passed after 25.802
seconds`, 0 `error:`, 0 `warning:` in the test log. The strengthening added arms
to existing tests, not tests. Goldens: `find Tests -name "*.json" | wc -l` reads
97, and `git diff --stat f64e58a -- '*.json'` is empty. Typecheck guards: none
added.

**Mutations.** Applied by a script (a scratchpad directory of its own) as exact
text replacements to committed source, each target checked unique first, built
with `swift build --build-tests`, run as the **unfiltered** suite with
`swift test --skip-build --no-parallel`, the failing test names parsed from the
log, and restored with `git checkout`, with
`git status --porcelain -- Sources Tests Package.swift` checked clean after
each. Every run that built printed its summary line (1140 tests).

**First round, at `aa5d055`: 46 rows.** N19 did not build (`contextual type for
closure argument list expects 1 argument`: the spelling `{ handler(.increment) }`
dropped the closure's parameter) and was re-spelled for the re-take. **Two
survived**: N46 (combination looking only at direct children) and N49 (a
clickable text's string overriding its declared label); the suite read
`Test run with 1140 tests in 1 suite passed` under each. Each changes a
published value on an input no fixture had — shown, not assumed, by the arms
added for them reddening under each in the second round. A third gap was found
by reading the same round's rows: N09v (a distributed value not overwriting a
child's own) is identical to the implementation on arm 6's fixture, whose texts
declared no value, so the condition it adds is true for every child there. All
three were closed by arms added in `15f0dd2` (`AB-AG` item 4). Every other
first-round row reddened at least one test; its test names are superseded by
the re-takes below.

**Second round, the whole table re-taken at `15f0dd2`: 52 rows** (every
first-round row, N19 re-spelled as `{ _ = $0; handler(.increment) }`, plus
N09v, lane 1's M38 against the changed portal fixture, and hunting mutants N52,
N57, N59, N60). N46, N49 and N09v reddened the arms added for them. **Two
survived**, each shown to change a published value first: N60 (only
focusability makes a descendant interactive — the one clickable descendant
under a button in any fixture, in lane 1's `aHiddenRootPublishesNothing`, folds
into a root button labelled `"in"`, which that test's `id(labelled: "in")`
still finds) and N52 (a list with no scroll context asks for a retry — no
active window held one). Both read `Test run with 1140 tests in 1 suite
passed`. Arms added in `ecb0504`: a clickable text inside a click target, and
an active scroller-less list that must go clean after frame 0.

**Third round, the whole table re-taken at `ecb0504`: 57 rows** (the second
round's 52, plus N64, N65, N67, N69, N70). **No survivor among those 57**, which
is not the same as covering step C and the window guard: the verifier round
below found three hunting mutants (V01, V02, V05) that this table did not
contain and that all survived. Every run built and
printed `Test run with 1140 tests`. Against the second round, 49 rows redden
exactly the same tests; N52 and N60 are now killed; N07 (a clickable text
keeps role `.text`) also reddens `aClickableContainerCombinesItsTextsIntoOneButtonLabel`,
whose new arm holds a clickable text. The table, with every test each row
reddens (test names in full; lane 1's and lane 2's tests appear where a lane-3
mutation reaches them):

| # | mutation | reddens |
|---|---|---|
| N01 | a static text's string goes to the label, not the value | `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aTextIsPublishedAsStaticTextWhoseValueIsItsString`, `labelAndValueFollowSwiftUIsStaticTextRules` |
| N02 | every registerHandlers call synthesizes (a Column gains a node) | `aClickableTextIsAButtonLabelledByItsString`, `aHeldElementWhoseIDIsAdoptedPressesTheAdopter`, `aHiddenInnerModifierLayerSuppressesEverythingInsideIt`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `aNodesParentIsItsNearestEmittingAncestor`, `aRealAppKitWindowPublishesItsFrameAndAPressRunsOnClick`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `aTextIsPublishedAsStaticTextWhoseValueIsItsString`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `eachLiveHandlerAloneMakesAnUndeclaredElementRecord`, `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`, `labelAndValueFollowSwiftUIsStaticTextRules`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `theAdjustableActionModifierRegistersTheAdjustmentHandler` |
| N03 | Text passes its string even when empty | `aTextIsPublishedAsStaticTextWhoseValueIsItsString` |
| N04 | delete the value-present branch's label = label ?? text | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `labelAndValueFollowSwiftUIsStaticTextRules` |
| N05 | skip the label-to-value move (value = text, label kept) | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `labelAndValueFollowSwiftUIsStaticTextRules` |
| N06 | apply the label-to-value move even when a value is present | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `labelAndValueFollowSwiftUIsStaticTextRules` |
| N07 | a clickable text keeps role .text | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aClickableTextIsAButtonLabelledByItsString`, `labelAndValueFollowSwiftUIsStaticTextRules` |
| N08 | no distribution (the label stays on the wrapper) | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N09 | the inner label wins over a distributed one | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N10 | distribute from a focusable node | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N10b | distribute from an adjustable node | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N11 | a labelled node with no kept child distributes (to nothing) | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `aNodesParentIsItsNearestEmittingAncestor`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement`, `anIncrementRequestRunsTheAdjustmentHandler`, `childrenFollowDeclarationOrderWhereIDsAloneCannot`, `declaredRolesLabelsValuesAndTraitsReachThePublishedNode`, `hiddenContentIsNotPublishedButAZeroHeightNodeIsAndADuplicatedIDIsPublishedOnce`, `labelAndValueFollowSwiftUIsStaticTextRules`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor`, `publishedFocusIsTheWindowsFocusAndAFocusRequestMovesIt` |
| N12 | combined labels join with a space | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N13 | a combining button keeps its children | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N14 | combine across an interactive descendant | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| N15 | drop the combined value half | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N16 | a plain text's value goes into the button's value | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N17 | the parent walk ignores portals | `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| N18 | the adjustable modifier registers under a different Action type | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `theAdjustableActionModifierRegistersTheAdjustmentHandler` |
| N19 | the adjustable modifier passes a constant direction | `theAdjustableActionModifierRegistersTheAdjustmentHandler` |
| N20 | logicalIndex = offset (no lowerBound) | `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` |
| N21 | drop rowCount | `aLabelledListIsStillATable`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| N22 | distribute a list's label (logicalCount does not exclude) | `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` |
| N23 | drop the unbounded suppression | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N24 | the bridge creates elements eagerly in publish | `aFocusedElementQueryDoesNotActivate`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `destroyedIsPostedOnlyForElementsAClientWasHanded`, `elementsAreCreatedOnlyWhenAClientReadsThem`, `labelValueRowCountAndFocusChangesPostOnlyForTheElementThatChanged`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N25 | drop the retry request | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N26 | uncap the retry | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| N27 | retry while not collecting | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| M33 | suppression ignores the scope's exception (always suppressed) | `aLabelledListIsStillATable`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| N29 | the innermost scope's exception decides | `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame` |
| N30 | forget the logicalIndex strip | `aClientDoesNotChangeStateRetention`, `synthesizedNodesCostNothingWhileNoClientIsActive` |
| N31 | write a $ax slot for every record | `aClientDoesNotChangeStateRetention`, `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot` |
| N32 | record regardless of collectsAccessibility | `aFrameThatDoesNotCollectRecordsNothingAndSynthesisWritesNoRetentionSlot`, `anInactiveWindowBuildsAndPublishesNothing`, `synthesizedNodesCostNothingWhileNoClientIsActive` |
| N33 | OnTapModifier synthesizes | `anOnTapModifierPublishesNothingButItsHitboxStillPresses` |
| N34 | post .layoutChanged on every structural publish | `layoutChangedIsPostedOncePerClientRead`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N35 | post destroyed per removed id, on a fresh object | `destroyedIsPostedOnlyForElementsAClientWasHanded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N36 | geometry is structure | `aGeometryOnlyChangeTouchesNoElementAndPostsNothing`, `anAnimationWithAClientActivePostsNothingAndTouchesNoElement` |
| N38 | logicalIndex does not make a row | `aClientDoesNotChangeStateRetention`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `synthesizedNodesCostNothingWhileNoClientIsActive` |
| N39 | rowIndex is not published | `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices` |
| N42 | a zero viewport counts as bounded | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame` |
| N44 | a distributor's value is not applied | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N45 | a combining button overwrites its own label | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N46 | combination looks at direct children only | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N49 | a clickable text's string overrides its declared label | `aClickableTextIsAButtonLabelledByItsString` |
| N50 | the value-present branch overrides a declared label | `labelAndValueFollowSwiftUIsStaticTextRules` |
| N09v | the inner value wins over a distributed one | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| M38 | popLayer never pops the portal stack (lane 1, against lane 3's portal fixture) | `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| N52 | a list with no scroll context also asks for a retry | `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| N57 | a declared non-generic role distributes | `aNodesParentIsItsNearestEmittingAncestor`, `childrenFollowDeclarationOrderWhereIDsAloneCannot`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| N59 | a focusable descendant is not interactive | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `portalContentIsARootEvenWhenDeclaredInsideAnEmittingAncestor` |
| N60 | an actionable descendant is not interactive | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N64 | a clickable labelled node distributes | `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren` |
| N65 | a clickable generic node that is not text stays generic | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `aDeferredInsideAClickableBoxIsNotFoldedIntoItsLabel`, `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`, `anActivationRequestDirtiesACleanWindowAndItsNextFramePublishes`, `declaredRolesLabelsValuesAndTraitsReachThePublishedNode` |
| N67 | combined values join with a space | `aClickableContainerCombinesItsTextsIntoOneButtonLabel` |
| N69 | an unbounded list excepts nothing from its suppression | `aLabelledListIsStillATable`, `aListInsideHiddenContentIsNotPublishedEvenOnItsUnboundedFrame`, `activatingBeforeTheFirstFramePublishesNoRowsUntilTheWindowIsBounded` |
| N70 | a row hint alone does not record | `aClientDoesNotChangeStateRetention`, `aScrolledListPublishesItsLogicalCountAndItsRealizedRowsWithTheirIndices`, `scrollingAListPostsBoundedNotificationsAndBuildsOncePerFrame`, `synthesizedNodesCostNothingWhileNoClientIsActive` |
| N51 | a folded button with no contributions gets an empty label | `eachLiveHandlerAloneMakesAnUndeclaredElementRecord` |

**Verifier round, at `4d97ba6`: three survivors in step C and the window
guard.** Lane 3's verifier re-took N23, N26, N29, N30, N46, N52, N60 and N69
(each reddened the tests above) and ran hunting mutants of its own, all on
the unfiltered suite, each shown to change a published value by a probe before
being banked as a gap. Three survived at `Test run with 1140 tests in 1 suite
passed`:

- **V01**: step C does not recurse below a node that is not a folding button.
  No fixture had a combining button whose parent is a published node, which is
  the demo's own `CounterPanel` shape. On
  `Row { Box{Text("-")}.onClick{}.accessibilityLabel("Decrement"); Box{Text("go")}.onClick{} }.focusable()`
  the mutant publishes `button label=nil` holding `staticText "go"` where the
  implementation publishes `button label="go"` with no children.
- **V02**: step C gates on `record.isClickable` rather than the published role.
  A clickable `List` then folds every row into its label
  (`table label="Row 0, Row 1, … Row 9" kids=0`, against `table kids=10`).
- **V05**: `windowIsBounded` drops `&& rowHeight.value > 0`. A 50-row list at
  `rowHeight` 0 in a measured 200pt scroller then publishes 50 rows and 50 texts
  on its second frame, where the implementation publishes none: `AB-X`'s
  frame-0 flood, on every frame.

The verifier's V07 (distribution not overwriting a clickable child's label)
reddened `aLabelOrValueOnAPlainContainerOrWrapperIsDistributedToItsChildren`.

**Fixed by the implementer's verifier-fix pass.** An arm in
`aClickableContainerCombinesItsTextsIntoOneButtonLabel` (a focusable `Row`
holding a labelled and an unlabelled click target over texts: a group with two
buttons labelled `"Decrement"` and `"go"`, no children, no static text), and a
sixteenth test, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows`,
with three arms, each on the second frame over one state table, behind a
`#require` that the scroller measured 200pt: click targets inside a bounded
list's rows (each row's one child is a button labelled `"Row N"` with no
children, rows 0..<10), a clickable list (still a table, `actions == [.press]`
as the control, `label nil`, 10 rows with their texts), and `rowHeight` 0
(table with `rowCount 50` as the control, no rows, no static text).
`scrolledList` gained `rowHeight`, `clickableRows` and `clickableList`
parameters, defaulted to the old fixture. The mutants were applied by a script
as text replacements (V05's target checked to leave `visibleRange`'s own
`rowHeight.value > 0` guard, the one remaining occurrence), each run as the
unfiltered suite and restored from a copy:

| # | mutation | reddens |
|---|---|---|
| V01 | step C does not recurse below a non-folding node | `aClickableContainerCombinesItsTextsIntoOneButtonLabel`, `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` |
| V02 | step C gates on `isClickable`, not the role | `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` (`list.label → "Row 0, …, Row 9"`, `listRowIDs.count → 0`) |
| V05 | `windowIsBounded` ignores `rowHeight` | `combinationReachesButtonsInsideAListAndAClickableListKeepsItsRows` (`zero.children` → 50 ids, texts published) |

Pristine before the mutants and again after: `Test run with 1141 tests in 1
suite passed` (1140 + the new test), 0 `error:`, 0 `warning:` in each log.
Only V01, V02 and V05 were re-run in this pass; the 57-row table above was not
re-taken, since no source line changed beyond `Resolving.isInteractive`'s doc
comment (which said the opposite of what the property returns, and now reads
"has a derived action or is focusable: what stops a button folding its
descendants").

**The retry cap can starve a list that appears later** (verifier finding,
re-measured here). `WindowAccessibility`'s cap is one `Bool` for the whole
window: a list whose scroller never measures a viewport (height 0, as a
collapsed section) asks on every frame, so no later frame's retry is ever
honoured. A second list shown afterwards publishes its table with no rows,
and the window goes clean until unrelated input dirties it; the next frame
drawn for any reason publishes the rows, since the new scroller measured its
viewport on the frame that showed it. Measured with a temporary test (not
committed) through `makeFakeWindow`, activated, drawn until clean, then an
`@Observable` toggle showing a 50-row list in a 200pt scroller, drawn until
clean again: **without** a zero-height list beside it, 2 frames after the
toggle, 10 rows, `needsRedraw false` (the control); **with** a 20-row list in a
zero-height scroller beside it, 1 frame, **0 rows**, `needsRedraw false`. Left
as a known limitation (`AB-AG` hazard). The named fix is to key the cap per
list id: dirty when the set of asking ids gains a member that did not ask on
the previous frame.

**Performance, by count.** With no client, lane 3 adds, by reading (`AB-AG`
item 5; no instrument measured it), one `Bool` store per drawn frame (`WindowAccessibility`'s retry flag), one `Bool` read per `List`
`prepaint`, two `Bool` stores per `List` `requestLayout`, and the `logicalIndex`
strip's copy of `handlers.axNode` per `registerHandlers` call; a row is indexed
only while collecting. Pinned counts: frame 0 of a 5,000-row list activated
before its first draw records **at most 3** (`lastEmissionCount`), publishes a
table with `rowCount 5000` and **0** rows, and frame 1 publishes **10**, with
`createdElementCount == 0` and **0** destroyed posts across both
(`activatingBefore…`, N23, N24, N25); a zero-height scroller retries **once**
(N26); an inactive window never retries (N27). Scrolling a read 500-row list 60
frames by 20pt: **60** builds, **1** `.layoutChanged`, **10** destroyed posts
for the 10 vended rows, **0** title or value posts, no element created
(`scrollingAList…`, N34, N35). A 30-tick width animation: **0** posts, 0
structural publishes, every publish geometry-only (`anAnimation…`, N36). Equal
`StateTable.count` active against inactive over 130 texts, 10 click targets and
a bounded list (`aClientDoesNotChangeStateRetention`, N30, N31). No allocation
instrument was used (`AB-M`).

**Deferred and owed, from lane 3.**

- **CLAUDE.md's demo `StateTable` figures need a re-take** (`AB-AG`): the
  demo's `"Decrement"`, `"Increment"` and `"Close modal"` labels are declared
  nodes and write a `$ax` slot every frame whether or not a client is active,
  so the warm resident counts (165 at 40 rows, 63 at 500) are stale. Re-take
  them from record §07's harness. Not measured here.
- **Record §05** (`AB-AG`): `AXNode.logicalCount` now has a reader; the new
  internal `AXNode.logicalIndex` has one writer and one reader; `AXNode.children`
  and `Frame.axNodes` are unchanged in the inert table.
- **Distribution reads the gated registries** (`AB-AG` hazard): after the
  environment merge a disabled focusable or adjustable labelled container
  distributes. Unpinned.
- **The retry cap starves a list shown beside one that always asks** (`AB-AG`
  hazard, measured above): 0 rows until unrelated input. Unfixed and unpinned;
  the per-id cap is the named fix.
- **Unpinned by construction:** setting `logicalIndex` while not collecting,
  or on an unbounded window (neither records nor emits, so no input can tell
  the spellings apart), and `Frame.requestAccessibilityRetry`'s own guard alone
  (its one caller calls it only while collecting). None was run as a mutation.
- **Proposal-path emission, scroll areas, `Stack` order, modal isolation, task
  9's button half, system settings, iOS**: `AB-Q`, unchanged.
- **The human VoiceOver look** below stays open: items 1–9 for a person to run.

### Human VoiceOver look — script (open)

Nothing in the suite hears VoiceOver.

**Run conditions.** Run on a **release** build of `feat/ax-bridge` at or after
lane 3's last commit (lane 3 has landed; nobody has run this script yet), on a
machine with VoiceOver available (⌘F5 toggles it). Report each item's
observation verbatim; "works" is not a report. Xcode's **Accessibility
Inspector** (Xcode → Open Developer Tool) is used in items 4 and 7 to read
attributes directly. Its own presence can activate a window (`AB-B`), so run
item 1 before opening it.

**Setup.**

1. `swift run -c release MetalUIDemo`.
2. Click the demo window once, so that it is key.
3. VO = Control-Option.

**Expected nodes that are NOT defects.** Report them only if they are
**absent**.

- **Modal panel** (after pressing **M**). A button whose label is the modal's
  text: "Modal, Declared inside the list…". VO-Space on it does nothing. That is
  the panel's click-absorbing `onClick {}` (`AB-Y`).
- **Modal scrim.** A button labelled "Close modal", containing the panel.
- **Counter panel.** An unlabelled group (the panel is focusable, and a
  focusable container keeps its node, `AB-T`) holding the "Decrement" button,
  the "Count N" text and the "Increment" button, in that order.
- **Preview toggle** (the proposal-path rectangles). **Nothing is announced**,
  and neither is the dimmed inert rectangle beside it. `onTap` content publishes
  nothing (`AB-Y`, `AB-Q`).
- **List rows.** Each row's own text is "Row N of 500 — a scrollable list
  item". Hearing "Row 41 of 500" is the text, **not** evidence that
  `AXIndex`/`AXRowCount` work (item 4).

**Items.**

1. **Activation (`AB-B`).** **First, before anything else:** list every
   running app that uses the Accessibility permission (System Settings →
   Privacy & Security → Accessibility shows the ones allowed; report which of
   them are running), and quit them all: window managers, text expanders,
   grammar and dictation tools, clipboard and launcher utilities. A utility
   with the pointer over the demo window activates it through the hit-test
   trigger (measured, `AB-B`), which would confound both orders below. Report
   the list and that they were quit. Then there are two orders.
   - **(a) Demo first.** With the demo already open and idle, start VoiceOver.
     Within two seconds, does VoiceOver announce content inside the window, not
     just its title?
   - **(b) VoiceOver first.** Quit VoiceOver and the demo. Start VoiceOver
     first, then launch the demo. Same question.

   Report what is spoken first in each order, and any silence longer than a
   second. Order (b) exercises the `isVoiceOverEnabled` trigger. Order (a)
   exercises either trigger, depending on whether the KVO flip arrives before
   VoiceOver's first query.
2. **Static text (`AB-F`).** VO-Right through the sidebar. Is each text read
   once, as its string, with no "group" before it? Report the first five
   utterances.
3. **Buttons (`AB-G`).** Reach the counter panel's **-** and **+** squares,
   labelled "Decrement" and "Increment". Is each announced as a button with its
   label? Press VO-Space on each: does "Count N" change by one per press, and is
   anything spoken after the press? Report the utterance after each press.
4. **The list (`AB-L`).**
   - **By ear.** VO-Right into the 500-row list. What is announced on entering
     it: does VoiceOver say a table or list, and a count? Move to the third
     visible row. Report the **whole** utterance, and whether any position
     phrase is spoken **apart from** the row's own text (for example a
     trailing "row 3 of 500" or "3 of 12").
   - **By Inspector.** With VoiceOver off, point Accessibility Inspector at the
     same row, and report its `AXRole`, `AXIndex` and the table's
     `AXRowCount`.
   - **Expected gap, not a defect.** VoiceOver cannot move past the last
     realized row, because rows outside the window are not elements (`AB-Q`
     item 2). Report the row number where movement stops.
5. **Focus (`AB-J`).**
   - Press **Escape** to clear focus. Where is VoiceOver's cursor? MetalUI
     reports the window itself as focused when nothing is (a recorded
     divergence from SwiftUI).
   - Press **F** to focus the counter panel. Is anything announced, and does
     the VoiceOver cursor move to the panel?
   - Press **Escape**, move the VoiceOver cursor to the panel yourself, and
     press VO-Shift-F4 (move keyboard focus to the VoiceOver cursor). Do **=**
     and **-** now change the count?
6. **Frames and scrolling (`AB-E`, `AB-K`, `AB-W`).** With VoiceOver's cursor
   outline visible, on a list row, scroll the list with the trackpad.
   - Does the outline stay on the row it names?
   - When that row scrolls out of the window, where does the cursor go?
   - After a long fling, does VO-Right continue from what is now on screen, or
     from where the list was before the scroll? The second answer means the
     window-wide `.layoutChanged` coalescing is too coarse, and the named fix is
     per-container coalescing.
   - Also move the mouse with VoiceOver's "cursor follows mouse" on, over the
     sidebar just above the list: is anything below the list's visible area
     announced? The expected answer is no (`AB-W`).
7. **Theme and modal.**
   - Press **Space** (theme): is anything re-announced?
   - Press **M** (modal): are the scrim and panel reachable, as listed under
     "expected nodes" above? **Expected gap:** is the background still
     reachable underneath it (`AB-Q` item 4)? With Inspector, confirm the modal
     nodes are children of the window, not of a list row (`AB-V`).
8. **Noise (`AB-K`).** Press **A** (the animation look) while VoiceOver's
   cursor is in the sidebar. Does VoiceOver repeat anything during the 0.6 s
   spring? Silence is the expected answer.

9. **Identity adoption (`AB-H`'s recorded hazard).** This needs a tree whose
   `if` hides a clickable element **before** an unnamed clickable sibling; the
   demo has none, so run it only if a later task adds one, and otherwise
   report "not exercisable in the demo". With VoiceOver on the trailing
   element's predecessor (the one the `if` hides), make the `if` false, then
   press VO-Space without moving. **Expected, and not a defect:** the element
   VoiceOver holds now reads the trailing element's label, and the press runs
   the trailing element's action. Report what is spoken after the change and
   what the press did.

**Also report:** macOS version, VoiceOver verbosity setting if changed, and
whether the build was release.
