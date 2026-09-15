## Accessibility bridge (plan task 12, bridge half) — 2026-09-15 …

**This is the track's record, on `feat/ax-bridge` from `f64e58a`.**

- Spec: `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`.
- Rulings: `AB-A`…`AB-Z` in
  `docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`.
- Probes:
  - `docs/probes/swiftui-accessibility-bridge.swift`;
  - `docs/probes/swiftui-accessibility-bridge-rules.swift`;
  - `docs/probes/appkit-accessibility-overrides-typecheck.swift`.

The integration step, not this track, links this file from
`docs/record/README.md` and CLAUDE.md.

**Status: lane 1 (tree and seam) implemented; lanes 2 and 3 designed.** The
design was revised after one critic round. Each lane appends its own section below:

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

### Human VoiceOver look — script (open)

Nothing in the suite hears VoiceOver.

**Run conditions.** Run on a **release** build, after lane 3 lands, on a
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
- **Preview toggle** (the proposal-path rectangles). **Nothing is announced**,
  and neither is the dimmed inert rectangle beside it. `onTap` content publishes
  nothing (`AB-Y`, `AB-Q`).
- **List rows.** Each row's own text is "Row N of 500 — a scrollable list
  item". Hearing "Row 41 of 500" is the text, **not** evidence that
  `AXIndex`/`AXRowCount` work (item 4).

**Items.**

1. **Activation (`AB-B`).** There are two orders.
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

**Also report:** macOS version, VoiceOver verbosity setting if changed, and
whether the build was release.
