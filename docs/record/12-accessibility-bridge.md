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

**Status: design only, no source changed.** The design was revised after one
critic round. Each lane appends its own section below:

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
