## Accessibility bridge (plan task 12, bridge half) — 2026-09-15 …

**This track's record, on `feat/ax-bridge` from `f64e58a`.** Spec
`docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`; rulings
`AB-A`…`AB-S` in `docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`;
probe `docs/probes/swiftui-accessibility-bridge.swift`. The integration step,
not this track, links this file from `docs/record/README.md` and CLAUDE.md.

**Status at the design commit: design only, no source changed.** Each lane
appends its section below: red run, green run, counts re-taken from an
unfiltered `swift test --no-parallel`, and the named tests each mutation
reddens.

### Design session (2026-09-15)

**Probe.** Run with `/usr/bin/swift` (Apple Swift 6.4); output recorded in its
header. What it established, arm by arm, is cited from the decisions doc and
not restated here. Two method findings worth keeping apart from the rulings:

- An in-process SwiftUI host exposes **no** accessibility children until the
  process sets `AXEnhancedUserInterface` on `NSApp` (arms 1, 2). A probe
  without that line concludes SwiftUI exposes nothing.
- SwiftUI's nodes are invisible to `as? NSAccessibilityProtocol` and answer
  `nil` to the informal `accessibilityAttributeValue(_:)` API; KVC on the
  modern selectors reads them. `responds(to:)` is true for everything and
  proves nothing (`AB-S`).

**Typecheck of the AppKit override spellings.** Every override the spec lists,
on an `NSView` subclass extension and an `NSAccessibilityElement` subclass,
plus six `NSAccessibility.post` notification names, compiled with
`xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors`: 0 diagnostics.
`accessibilityFocusedUIElement` is a property on `NSView`; the first spelling
tried, a method, failed with "method does not override any method from its
superclass".

**By reading, not yet measured:** `Frame.emitAXNode` stores untranslated
bounds, so a node inside a scrolled `ScrollView` reports its content-space rect
(`AB-E`; lane 1's `aNodeInsideAScrolledScrollViewReportsItsOnScreenFrame` is the
first measurement).

### Human VoiceOver look — script (open)

Nothing in the suite hears VoiceOver. Run on a **release** build after lane 3
lands, on a machine with VoiceOver available (⌘F5 toggles it). Report each
item's observation verbatim; "works" is not a report.

**Setup.** `swift run -c release MetalUIDemo`. Click the demo window once so it
is key. Start VoiceOver (⌘F5). VO = Control-Option.

1. **Activation (`AB-B`).** Within two seconds of starting VoiceOver with the
   demo already open and idle, does VoiceOver announce content inside the
   window (not just its title)? Then quit VoiceOver, quit the demo, start
   VoiceOver first and launch the demo: same question. Report what is spoken
   first in each order, and any silence longer than a second.
2. **Static text (`AB-F`).** VO-Right through the sidebar. Is each text read
   once, as its string, with no "group" before it? Report the first five
   utterances.
3. **Buttons (`AB-G`).** Reach the counter panel's **-** and **+** squares
   (`CounterPanel.button` in `main.swift`; lane 3 labels them "Decrement" and
   "Increment"). Is each announced as a button with its label? Press VO-Space
   on each: does "Count N" change by one per press, and is anything spoken
   after the press? Report the utterance after each press.
4. **The list (`AB-L`).** VO-Right into the 500-row list. What is announced on
   entering it (does it say a table/list and a count)? Move to the third
   visible row: does VoiceOver say "row N of 500", "N of 17", or no position?
   Report the exact phrase. **Expected gap, not a defect:** VoiceOver cannot
   move past the last realized row, because rows outside the window are not
   elements (`AB-Q` item 2). Report the row number where movement stops.
5. **Focus (`AB-J`).** Press **Escape** to clear focus, then **F** to focus
   the counter panel. Is anything announced, and does the VoiceOver cursor
   move to the panel? Then press **Escape**, move the VoiceOver cursor to the
   panel yourself, and press VO-Shift-F4 (move keyboard focus to the VoiceOver
   cursor): do **=** and **-** now change the count?
6. **Frames (`AB-E`).** With VoiceOver's cursor outline visible, scroll the
   list with the trackpad. Does the outline stay on the row it names, and when
   a row scrolls out of the window, where does the cursor go?
7. **Theme and modal.** Press **Space** (theme): is anything re-announced?
   Press **M** (modal): is the modal's content reachable, and — **expected
   gap** — is the background still reachable underneath it (`AB-Q` item 4)?
8. **Noise (`AB-K`).** Press **A** (the animation look) while VoiceOver's
   cursor is in the sidebar. Does VoiceOver repeat anything during the 0.6 s
   spring? Silence is the expected answer.

**Also report:** macOS version, VoiceOver verbosity setting if changed, and
whether the build was release.
