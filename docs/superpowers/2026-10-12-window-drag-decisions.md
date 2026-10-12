# Window drag — decisions

Rulings for item C22: a window-drag region that wins over the gestures beneath
it (user request 2026-10-02, an item of the gpui-gap priority list; **not a plan
task**). Reported by MetalCreator (`docs/metalui-gaps.md` there, gap **C8-a**,
human check AS-5; read, never edited).
Spec: [`specs/2026-10-12-window-drag-design.md`](specs/2026-10-12-window-drag-design.md).
Record: `../record/97-window-drag.md` (written at the Record phase).

Evidence:

- [`../probes/swiftui-window-drag.swift`](../probes/swiftui-window-drag.swift)
  (arms `W0`…`W11`; run twice and under two deliveries, stdout byte-identical,
  58 lines; macOS 27.0.1, Swift 6.4, screen locked) plus an interface census of
  `SwiftUI.swiftinterface`. **The instrument sees a window move only through
  AppKit's stderr diagnostic** ("Window move completed without beginning"):
  `performDrag(with:)` is never called by SwiftUI's gesture, and the positive
  control `W1` reads it while the no-gesture controls do not. What a *real*
  drag does to the other gestures once the system's tracking loop runs is not
  measured (human check `WD-1`).
- gpui is **not read** for this item; SwiftUI has the answer (`WindowDragGesture`).

Prefix **`WD-`**, lettered. **Next unused: `WD-L`.** (This line moves in the
commit that appends a ruling; read the last `## WD-` heading.)

Branch `feat/window-drag` from `a720fba`. `docs/divergences.md`: this branch's
reserved labels are **275–284**; `WD-C` uses 275, `WD-F` uses 276; the header's
next-label line is the merge's. Human checks: group **WD** (provisional, in the
manner of `IF`/`SG`).

**Carried items.** `AS-J` (the band press: unclaimed only; **unchanged**);
`AS-E` item 6 (SDL keeps its system decoration); `IX-B`/`IX-D` (the closed
`Gesture` protocol, one arena per press from the one ranking); `DN-D`
(the draggable leaf this one is modelled on); `DN-K`/`endPressForDrag` (a press
handed to the platform); `IF-E`/`IF-F` (`onCancelled`, which a cut-off member now
runs); `IX-D` item 5 (a gesture rides its element's hitbox); divergence 23
(a disabled target registers no hitbox); `TE-AD` (no renderer change here).

## WD-A — Scope: what this branch builds, what it defers

**Builds.** `WindowDragGesture` (SwiftUI's spelling, macOS-15 API), attached
with `.gesture(_:)`/`.highPriorityGesture(_:)`/`.simultaneousGesture(_:)`; one
new arena leaf kind; one new defaultless `PlatformWindow` requirement,
`performWindowDrag() -> Bool`; AppKit's real answer, SDL's and the headless
window's honest ones; tests; the app-shell demo section's handle; human checks
`WD`.

**Defers, each named.**

- `Scene.windowBackgroundDragBehavior(_:)`: a *Scene* modifier (census), and
  MetalUI has no `Scene`; its effect (every unclaimed press drags) is `AS-J`'s
  rule with its band condition removed. Owner: none; additive (a `Window`
  property), would need its own probe of what a press on a control does.
- `.windowDragArea()`: **not built**: SwiftUI's spelling fits the arena (`WD-B`).
- A double click in a handle running the title bar's double-click action
  (zoom/minimise): the probe does not show SwiftUI doing it (`W6`, weak
  evidence), and a handle over the band removes `AS-J`'s double-click zoom there.
  Owner: none until MetalCreator reports it (its adoption note should say so).
- `onChanged`/`onEnded`/`updating` on the gesture: `Value` has no members
  (census); MetalUI's `Gesture` protocol is closed and per-type. Owner: none.
- SDL moving a window from a region (`WD-F`). Owner: client-side decorations
  (`AS-E` item 6).
- `allowsWindowActivationEvents`: not a drag API (census).

## WD-B — SwiftUI's spelling fits; no `.windowDragArea()`

**Ruling.** `public struct WindowDragGesture: Gesture` with
`public struct Value: Equatable, Sendable {}` and `public init()`, exactly
SwiftUI's surface (macOS only in SwiftUI; MetalUI offers it on every platform,
`WD-F`). It registers like any non-draggable gesture: it makes its element a
**pointer target with an opaque hitbox** (`Handlers.isPointerTarget`, `IX-D` item
5), at the element's bounds or its `contentShape`.

**Reasoning / evidence.** Probe `W2`: a region carrying the gesture, overlaid on
a base with a `DragGesture`, takes the press (window moves, the base reads
nothing); `W9` is the separating arm. That is MetalCreator's case: the top bar's
glass carries `.gesture(WindowDragGesture())`, sits above the viewport, and the
**one ranking** (`topmostOpaqueHitbox`) already makes it the arena's target, so
the sibling viewport's `SpatialTapGesture`, three `DragGesture`s and
`MagnifyGesture` never join (they are not its ancestors). Where the handle is
*inside* the gesture-carrying view (`W11`), it is the innermost arena member
(`WD-C`). No second lookup, no new hitbox kind, no `Handlers` member (the
count stays nineteen), no `Frame.registerHandlers` arm.

**Cost if wrong.** A `.windowDragArea()` spelling would be a MetalUI-only
modifier on the same leaf: additive, one `Element` hook mirrored per layer
(`MC-B`). The leaf and the seam would not change.

## WD-C — Arena semantics: modelled on the draggable, ends at a slop, cuts the rest

**Ruling.** A new `GestureLeaf.Kind.windowDrag`, live in a **press** arena only
(failed at formation in a button or pinch arena, so a secondary press drags
nothing, probe `W7`). It is **ready at the first move of at least `tapSlop`
(5 points) from the press** — one threshold, so a press is a tap (or a click) or
a window drag, never both — and is blocked exactly as a draggable is
(`isBlocked`'s `DN-D` exception, generalised from `isDraggable` to a
`startsHandoff` predicate over both kinds): an undecided member *ahead* of it
that is a tap, a long press or a click does not hold it off; an undecided
`DragGesture` (or any other non-yielding member) ahead of it does, and an
*ended* member ahead blocks. Members ahead are as always the innermost normal
members first, with high-priority ones before them (`IX-D` item 3), so:

- a `DragGesture` *inside* the handle outranks it (probe `W3`, no move);
- a high-priority `DragGesture` on an ancestor outranks it (probe `W11b`);
- a handle inside a gesture-carrying viewport outranks the viewport's normal
  gestures behind it (they are cancelled, see below);
- a `highPriorityGesture(WindowDragGesture())` outranks everything (as `W4`'s
  window still moves).

When it acts, it ends and a callback `.beginWindowDrag(owner:)` is emitted **after
the cancellations of the members that had reported** (`IF-F` item 1, their
`onCancelled`), then every other undecided member fails without an end —
`.draggable`'s `act` arm, line for line.

**Divergence 275** (narrow, measured only in a synthetic delivery). SwiftUI
runs the window gesture *alongside* the others: probe `W3b`, `W4`, `W4b` and
`W11` move the window **and** fire the other gesture's callbacks (`W11d`: a plain
child `DragGesture` excludes its parent, so the difference is this gesture's).
MetalUI cuts the others off. Reason: in a live session the system's tracking
loop consumes the rest of the press, so the other gesture would see a begin and
nothing more — an `onChanged` with no `onEnded` — and MetalCreator's wanted
behaviour ("wins over the gestures beneath it") is exactly that nothing else
reacts; `onCancelled` gives the owner its reset. What SwiftUI's own gestures
report in a real drag is human check `WD-1`.

**Cost if wrong.** If a real SwiftUI drag leaves the neighbour's gesture running
to completion and an app relies on it, the fix is the `simultaneous` placement of
the leaf (the arena already supports it): the leaf runs and the others are not
failed. One arm of `act`.

## WD-D — The drag begins at the slop, not at the press

**Ruling.** `Window` handles `.beginWindowDrag` like `.beginDrag`: it calls
`platformWindow.performWindowDrag()`, then `endPressForDrag()` (the arena is
dropped, `active` cleared: nothing draws pressed, and the release — which the
platform's tracking loop consumes — is no click). It does so **whatever the
platform answers** (`WD-F`): the members are already cut, and a press that was
handed off must not complete a click later.

**Reasoning.** `AS-J` starts the platform drag at the mouse-down because nothing
else can claim a band press. A handle carries buttons, taps and double-clicks
(`W5c`): beginning at the press would swallow every click in it (AppKit's drag
runs a nested loop to the mouse-up). Taps that yield (`WD-C`) and a
5-point slop is the one rule that lets a `Button` in a drag handle still be a
button.

**Cost if wrong.** AppKit must accept `performDrag(with:)` called from a
mouse-*dragged* dispatch with the press's *mouse-down* event (the documented
argument). The pattern is common but **not run here** (a synthetic event cannot
enter the system tracking loop; human check `WD-1`). The fallback is a one-site
change: `windowDrag` ready at the press (slop 0), losing taps in the handle;
`AppKitWindow.performWindowDrag` and the arena's `ready` condition are the only
sites.

## WD-E — The platform seam: a new defaultless `performWindowDrag() -> Bool`

**Ruling.** `PlatformWindow.performWindowDrag() -> Bool`, **no default** (the
`MD-J`/`CR-M`/`AS-H` rule), answering whether the platform moved the window.
`Window` calls it only from inside its `onInput` handling of a mouse-dragged
whose press formed the arena that emitted `.beginWindowDrag`. AppKit: the host
view keeps the **primary mouse-down `NSEvent` of the press** from its dispatch
until the matching mouse-up (cleared at the up, at `resignKey`/`close`, and when
a second down replaces it) and, **only while it is dispatching that press's
mouse-dragged**, calls `NSWindow.performDrag(with:)` with it and answers `true`;
at any other time `false`. SDL records and answers `false` (`WD-F`). The
headless window records (`windowDrags`) and answers
`Options.performsWindowDrag` (default `true`, AppKit's answer during a drag).
Every test fake implements it; the migration note (`docs/migration.md`, with
`PlatformWindow`'s doc comment) says: a conformer adds
`func performWindowDrag() -> Bool { false }`.

**Why not reuse `performTitleBarPress(clickCount: 1)`.** It is the band's
rule — acts only in a mouse-*down*, pinned by
`appKitTitleBarPressDragsOnlyDuringAMouseDown` — and its record
(`titleBarPresses`) could not tell a band drag from a handle drag in a test.
Two requests with two meanings cost one more line per fake; reuse would change
a pinned contract.

**Cost if wrong.** Folding it into `performTitleBarPress` later is mechanical
(the call site, the conformers' one line); the new requirement is the more
expensive direction to *add* after release, so it is added now.

## WD-F — SDL: the honest constraint, not a hit-test region list

**Ruling.** On SDL `performWindowDrag()` records and answers `false`. The
gesture still ends and cuts the other members (`WD-C`): the semantics are the
same on every platform, only the move is not. **Divergence 276**: the handle
moves a window on AppKit only.

**Why not `SDL_SetWindowHitTest` with a per-frame region list** (the task's
alternative). (1) The callback is synchronous in the OS event path and a
`SDL_HITTEST_DRAGGABLE` area *removes every pointer event inside it from the
app*: a `Button` or tap in a handle would stop working, contradicting `WD-C`/`WD-D`;
(2) an SDL window keeps its **system decoration** (`AS-E` item 6, `setTitleBarStyle`
answers `false`), which already drags, so the band has no hole to fill; (3) the
list would be a second defaultless requirement (`setWindowDragRegions`) with a
per-frame publish and a cache-invalidation story for what is, today, a no-op
need. All three go away only with client-side decorations, which is where it is
owned.

**Cost if wrong.** A Linux/Windows app with a borderless window cannot drag it
by a handle. Borderless SDL windows are not offered by MetalUI (`windowStyle`
has no borderless case), so there is no such app today.

## WD-G — Gates: allowsHitTesting, `.disabled`, `.hidden()` — the gesture rule, pinned

**Ruling.** The gesture rides its element's hitbox (`IX-D` item 5), so the three
gates remove it exactly as they remove any gesture, with no new arm:
`.allowsHitTesting(false)` (`OM-AK`) and `.hidden()` register no hitbox — the
press reaches what is beneath, as probe `W8a`/`W8d`; `.disabled` registers none
either (divergence 23), where SwiftUI's disabled region still swallows the press
without dragging (`W8b`) — the existing divergence, not a new one. `.opacity(0)`
does not gate a hitbox in MetalUI (as for every gesture), where SwiftUI's is
inert (`W8c`): **not an existing divergence row** (checked by grep of
`docs/divergences.md`, critic pass) — it is divergence 277 (`WD-J`). A frame with no
`WindowDragGesture` registers exactly the hitboxes it does today.

**Cost if wrong.** A gate that must differ (a disabled handle still blocking
the viewport) would be a new non-opaque region, as `DN-E`'s.

## WD-H — Press kinds and clicks

**Ruling.** Primary press only (`WD-C`). A secondary press in a handle drags
nothing and opens a context menu as ever (`MN-B`: it reaches only the menu
stage). A double-click press is an ordinary press with `clickCount` 2: no zoom
(`WD-A`). `AS-J` is unchanged: a band press that forms no arena still drags
(`titleBarPresses` records it); a band press that does form one (the report)
is now answered by a handle, or by nothing if the app declares none.

## WD-I — Lanes and tests

See the spec (§§4–6): two lanes, disjoint files, lane 1 (core, seam, headless,
tests, demo) then lane 2 (AppKit, SDL, Linux image, human checks); every test
named with its red-before and mutation.

## WD-J — Critic pass: an invisible handle still captures (divergence 277)

**Ruling.** Probe `W8c` (re-run byte for byte by the critic, md5
`2cbb77aa2cfe92ee3ec16b5463de18c4`, 58 stdout lines as recorded; `W8f` is the
positive control, `W8c`/`W8d` the separating arms) shows an `.opacity(0)`
handle inert and the base receiving the press. MetalUI gates no hitbox on
opacity, for any gesture, and `WD-G` wrongly called that an existing divergence:
no row covers it. **Divergence 277** (label from this branch's range): a
`.opacity(0)` handle still captures the press and drags. Pinned wrong on
purpose by a fourth arm of test 1.11 (`anOpacityZeroHandleStillCapturesTheWayEveryGestureDoes`);
`.hidden()` is the way to remove it. Not fixed here: gating on opacity would
move hit testing for every gesture (MUST NOT MOVE).

**Also recorded (rejections).** (1) The critic re-checked that `Value` is
`Equatable, Sendable` where the census lists `Equatable` only: `Sendable` is
implied for an empty struct and a divergence row would be noise. (2) The lanes
overlap on the SDL and AppKit stub lines by design (lane 1 adds the stub so the
tree builds, lane 2 replaces it); they run one after the other, and lane 2 owns
the Linux image run for both. (3) Folding the seam into `performTitleBarPress`
stays rejected (`WD-E`).

## WD-K — Lane 1 build: what the implementation changed against the spec

**Rulings.** (1) `AppKitWindow` already had a stored injectable closure named
`performWindowDrag` (the `AS-J` band drag's `NSWindow.performDrag(with:)`
recorder), which cannot share a base name with the new requirement
`performWindowDrag()`. The closure is renamed `performTitleBarDrag` (one source
site, one line of `appKitTitleBarPressDragsOnlyDuringAMouseDown`'s injection);
nothing else of `AS-J` moved. Lane 2's AppKit answer injects its own
`performDrag(with:)` closure under another name. (2) Tests 1.1–1.17 run over
`FakePlatformWindow` in `MetalUITests` (it gains `windowDrags` and
`performsWindowDrag`), not `TestApp`: `MetalUITests` does not depend on
`MetalUITesting`, and the fake records `titleBarPresses` beside `windowDrags`,
which 1.1 needs. `MetalUITesting`'s own two tests (2.1, 2.2) drive `TestWindow`.
(3) Test 1.5: the viewport drag is a `simultaneousGesture` of minimum distance 0
and reports at the press **and** at the slop move before the handle acts, so
the assertion is `changed >= 1`, `cancelled == 1`, `ended == 0` (the spec said
"once"). (4) Test 1.11's `.hidden()` arm uses the legacy `Box`: the proposal
vocabulary has no `.hidden()`. (5) Demo: the handle is a legacy `Box` strip
inside a `Column` carrying a simultaneous `DragGesture` canvas (the 1.5 shape),
in `appShellDragHandleSectionBody()`; the model counts finished and cut-off
canvas drags. (6) Guard 3.1 is a row of `AppShellSeamCompileGuards`' window
table; 3.2 is `WindowDragCompileGuards.swift`.

