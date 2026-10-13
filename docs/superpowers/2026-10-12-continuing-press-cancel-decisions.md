# Continuing press cancel — decisions

Rulings for item C26: a reported drag whose release was lost is dropped by the
next primary press on the same element with neither `onEnded` nor `onCancelled`
(user request 2026-10-02, an item of the gpui-gap priority list; **not a plan
task**). Reported by MetalCreator (developer-0a, 2026-10-12, gap VI-b, found
planning C16's adoption; not blocking — stopgaps in `ViewportModel`/`EditorModel`).
Spec: [`specs/2026-10-12-continuing-press-cancel-design.md`](specs/2026-10-12-continuing-press-cancel-design.md).
Record: `../record/100-continuing-press-cancel.md` (written at the Record phase).

Prefix **`GC-`**, lettered. **Next unused: `GC-H`.** (This line moves in the
commit that appends a ruling; read the last `## GC-` heading.)

Branch `fix/continuing-press-cancel` from `930db4a`. `docs/divergences.md`: this
branch's reserved labels are **305–314**; none is taken by these rulings (`GC-D`);
the header's next-label line is the merge's.

Evidence: [`../probes/swiftui-lost-release.swift`](../probes/swiftui-lost-release.swift)
(arms `L0`…`L3`, recorded in its header; run twice, stdout byte-identical;
macOS 27.0.1, Swift 6.4, screen locked, `NSEvent`s through `NSWindow.sendEvent`).

**Carried items.** `IF-E`, `IF-F` items 1–5 (`onCancelled`, the sites that owe it:
`abandon()`, `cancel()`, a draggable/window-drag winning, a stale button or pinch
arena, a window close); `IX-D` (one arena per press, `continuing`); `CI-AB`;
`WD-C` (a window-drag handle cancels reported neighbours); `IF-C`
(`DragGesture.Value.clickCount`); `CI-AG`.

---

## GC-A — The contract, and what SwiftUI answers

**Finding (probe, SwiftUI).** `DragGesture` has no `onCancelled`; a cancel is
visible only as a `@GestureState(reset:)` closure with no `onEnded`. Control `L0`
(down, drag, up) reads `chg,chg,reset,end`. **`L1`** (down, drag, *release lost*,
down, up on the same view) reads `chg,chg,reset,chg,reset,end`: the second press
**cancels the first drag (reset, no `end`) and starts a new one** that ends
normally; `L2` the same with a drag in the second press. **`L3`** (a `mouseMoved`
with no button after the lost release) reads `chg,chg`: nothing is cancelled. The
`L0`/`L1` pair separates "a cancel" (an extra `reset` before the second `chg`)
from "an end" (`end` appears once).

**Ruling.** A leaf that reported a change owes `onCancelled`, once, **whatever
ends it** unless it ends normally. Two consequences, separate rulings: the arena's
own contract (`GC-B`) and the window's treatment of a press while the previous one
is still down (`GC-C`).

**Reasoning.** `IF-F`'s rule, stated by sites; this states it by cause. SwiftUI
agrees on both halves of `L1`.

**Cost if wrong.** An app's `onCancelled` that resets `@State` runs where today
nothing ran; an app that relied on silence (none known: the callback is C16's,
two days old) sees one more call.

## GC-B — `GestureArena.press(… continuing: true)` cancels what it fails (option a)

**Ruling.** In `press(at:clickCount:continuing:modifiers:)`, the `.drag` arm that
fails a leaf on a continuing press first takes `cancelCallback(leaf)` (nil unless
the leaf reported) and returns it **ahead of** the callbacks `resolve()` produces,
as `abandon()` does. `.click` and `.longPress` have no report to owe
(`cancelCallback` is nil for them; a long press's `pressing(false)` already goes
through `fail`). Magnify/rotate leaves are not failed by a primary press (they are
failed at formation), so they need no arm.

**Reasoning.** The reporter's option (a), and the narrowest edit that makes the
arena honour `GC-A` however it is driven. Reachable from `Window` only when a
reported leaf is still `possible` with `isPressing == false` (a reported leaf
held by an exclusive neighbour); the arena's own unit test drives it directly.

**Cost if wrong.** One extra callback on a path that previously dropped silently.

## GC-C — A primary press while the previous one is still down is a lost release, not a second press (a fresh arena)

**Ruling.** `Window.dispatchGestures`, `.mouseDown`: the continuing branch is taken
only when `!arena.isPressing`. A press that finds the live arena **still pressing**
(no `mouseUp` since its `press`) is the same case as a press elsewhere: `abandon()`
(which cancels every reported leaf, fails the rest, reports `pressing(false)`),
then a **fresh arena** forms at this press with `continuing: false`.

**Reasoning.** (1) A genuine tap-sequence second press always follows a release —
`isPressing` is cleared by it (`release`, line 869) — so the discriminator is
exact where "same element" was not. (2) SwiftUI's `L1`/`L2`: after the cancel the
second press **starts a drag**. With `GC-B` alone the second press would be
swallowed (the drag is failed, so the orbit that the user is now beginning does
not start until the press after) — `buttonPress` already does it this way for the
other buttons (`CI-AB` item 1, `IF-F` item 2: drop, cancel, form anew). (3) The
tap sequence restarts: `baseClickCount` is the new press's, so a lost-release
`clickCount: 2` is not a double-tap.

**Not built: option (b).** Cancelling the primary arena on a plain `.mouseMoved`
(as `IF-F` item 3 does for a button arena) is **rejected for the primary arena**:
SwiftUI cancels nothing on it (`L3`); a test or a platform that delivers a move
between press and a late release exists (`IF-A`'s own note); `GC-C` closes the
reported case at the first press that proves the release was lost. A drag that is
never followed by a press stays live until the next one or a window close —
unchanged (`IF-F` item 5). Owner: none; additive (a `.mouseMoved` arm).

**Cost if wrong.** If a test or platform sends two `mouseDown`s with no `mouseUp`
as a double-click, the second now starts a new sequence and `count: 2` never
completes. The implementer runs the unfiltered suite first; any such test is a
test bug if its fixture is not a platform's event stream, and the fallback ruling
is to narrow the condition to "the arena has a reported `possible` leaf" (the
two never differ for the reported case).

## GC-D — Audit of every `fail(_:)` and no new divergence

**Ruling.** Every call that can fail a leaf which reported (`activated`), with its
verdict (the spec §3 has the test per row):

| site | when | verdict |
|---|---|---|
| `press(continuing:)` drag arm | second press of the live arena | **fixed**, `GC-B` |
| `abandon()` | press elsewhere / `GC-C` | already cancels first (`IF-F` 1) |
| `cancel()` | stale button/pinch arena, close | cancels first |
| `act` `.draggable`, `.windowDrag` winning | a neighbour reported | cancels first (`IF-F` 1, `WD-C`) |
| `act` `.drag` with no `endValue`/not activated | release | not reported, nothing owed |
| `move` tap/long-press fail | slop | taps and long presses do not report a change |
| `release` `.drag` not started | release | not reported |
| `cancelBehindEndedMembers` (line 1304) | an exclusive member ended | a reported leaf is unblocked, hence not behind an ended member; **unreachable**, pinned by an arena test the implementer tries to make red; if it cannot be built the ruling stays and the test is dropped |
| the tap deferral timeout (line 994) | stamp | tap only |

No divergence label is taken: SwiftUI agrees (`GC-A`); `onCancelled` is already
MetalUI-only (`IF-E`).

**Cost if wrong.** A row missed is a silent drop; the table is re-derivable with
`grep -n "fail(" Sources/MetalUI/Gesture.swift`.

## GC-E — Lanes and tests

One lane (`Gesture.swift` arm, `Window.swift` condition, one new test file, probe
and docs). See the spec §§3–5.

---

## GC-F — Critic's rulings: the audit's tests, the mutation of 1.6, and what was rejected

**Audit tests per reachable row** (`GC-D`). Each reachable row has a pin; the
implementer names it in the record rather than writing a duplicate:
`abandon()` is `aDroppedPrimaryDragReportsCancelledOnceAndNotEnded` (and new 1.9);
`cancel()` on a stale button/pinch arena is `aStaleButtonArenaReportsCancelledWhenTheSameButtonPressesAgain`,
`aStalePinchArenaReportsCancelledBeforeASameCentrePinchBegins`; a window close is
`aWindowCloseCancelsLiveArenasBeforeOnDisappear`; a draggable winning is
`aDragStartedByADraggablesPreviewIsCancelled`; a window-drag handle winning is
`WindowDragTests.aHandleOverAGestureViewportDragsTheWindowAndCancelsTheViewport`;
unreported leaves are `aDragThatNeverBeganIsNotCancelled`/`aReleasedDragIsNotCancelledByTheNextPress`.
The continuing-press row is new 1.4 (arena) and 1.1 (window). Line numbers in
`GC-D` are the baseline's; re-grep.

**Test 1.8 is already pinned** by `aPrimaryArenaIsNotCancelledByAMoveWithoutAButton`
(`GestureFollowupTests`); 1.8 is kept only as the lost-release shape (a reported
drag, then `mouseMoved`) and may be folded into that test's neighbour.

**Mutation of 1.6/1.7** is: make the continuing branch unreachable (always
`abandon()` and a fresh arena, ignoring `isPressing`'s release), which must redden
1.6 (`count: 2` never completes) and 1.7 (`clickCount` 1).

**Rejected.** (i) A SwiftUI double-click-beside-drag claim: none is made (spec §0).
(ii) Adding a `.mouseMoved` cancel for the primary arena (`GC-C`; the existing
pin above would redden). (iii) A second lane: the change is two small edits and
one test file. (iv) Dropping `GC-B` as dead code after `GC-C`: it keeps the
arena honest when driven directly (1.4), and costs one line.

**Probe re-run (critic, 2026-10-12, screen state as at the original run).** Arms
`L0`..`L3` reproduced byte for byte against the header.

---

## GC-G — Implementation findings: 1.10 dropped, 1.7 is a pin not a separator, 1.3 re-shaped

**Ruling.** (1) Test 1.10 (`cancelBehindEndedMembers` owing a cancel) is **dropped**:
a leaf that reported was unblocked by `isBlocked`, so every exclusive member ahead of
it has failed; none can end afterwards, and a member behind a reported one is
cancelled by the *reported* leaf ending, which is a normal end. No arena shape
reaches it; `GC-D`'s "unreachable" stands as reasoning, unpinned by a test. (2) The
spec's claim that the always-abandon mutation reddens 1.7 was **measured false**:
after a release the drag leaf has ended, the arena is dead and the next press forms
a fresh arena with its own click count either way. 1.7 stays as a regression pin for
`IF-C` beside `GC-C`; the always-abandon mutation is separated by 1.6 and by the
existing tap-sequence tests (record 100 §3). (3) Test 1.3's arena half was reshaped
after its first mutation (`cancel()` not failing the leaf) reddened nothing: the
continuing-press path had already failed the leaf, so a second `cancel()` was
unreachable there. It now drives `press`, `move`, `cancel()`, `cancel()`,
`abandon()`; test 1.4 gains a trailing `cancel()`/`abandon()` that separates the
`fail(leaf)` in `GC-B`'s arm.

**Cost if wrong.** None to behaviour; only the test inventory differs from the spec's.
