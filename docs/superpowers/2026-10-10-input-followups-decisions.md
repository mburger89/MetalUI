# Input follow-ups — decisions

Rulings for the follow-ups to the input APIs (`CI-`, record §81): modifiers on a
tap and on a still hover, a click count on a drag's value, wheel latching,
gesture cancellation and a guaranteed terminal scroll phase (item C16, user
request 2026-10-02, an item of the gpui-gap priority list; **not a plan task**).
Reported by MetalCreator (`docs/metalui-gaps.md` there: **GI-a, GI-b, S5-a, S5-b,
VI-a**; read, never edited).
Spec: [`specs/2026-10-10-input-followups-design.md`](specs/2026-10-10-input-followups-design.md).
Record: `../record/93-input-followups.md` (written at the Record phase).

Evidence:

- [`../probes/swiftui-input-followups.swift`](../probes/swiftui-input-followups.swift)
  (arms `D1`…`D4`, `C1`…`C5`, `M0`…`M6`; run twice, byte-identical, 20 lines;
  macOS 27.0.1, Swift 6.4, screen unlocked) plus an interface census of
  `SwiftUI.swiftinterface`. **The `M` arms are not an answer**: every one reads
  "-", `M0` (`initial: true`, which must report at appearance) and `M6` (the
  delivery control) included, so the instrument cannot drive
  `onModifierKeysChanged` and nothing below rests on its timing (`IF-D`).
- gpui is **not read** for this item; where a ruling is MetalUI's own design
  (`IF-F`, `IF-G`, `IF-H`) it says so.

Prefix **`IF-`**, lettered. **Next unused: `IF-M`.** (This line moves in the
commit that appends a ruling; read the last `## IF-` heading.)

Branch `feat/input-followups` from `f2fe54a`. `docs/divergences.md`: this
branch's reserved labels are **235–244**; `IF-B`/`IF-E` use 235 and 236, the
header's next-label line is the merge's. Human checks: group **IF** (provisional,
in the manner of `RT`/`KF`/`SG`).

**Carried items.** `IX-B`, `IX-C`, `IX-D` (the closed `Gesture` protocol, tap
slop 5 and sequence deferral 0.33 s, one arena per press); `CI-AB` (a stale
button or pinch arena is dropped silently — `IF-E` amends the silence);
`CI-AA` item 4, `CI-AG` pin `aPressOfAnotherButtonWhileAnArenaIsAliveIsIgnored`
(kept); `CI-AD` (no latch — `IF-G` builds it); `CI-G`, divergence 140 (a drag
value's modifiers); `CI-I`, `CI-AH`, `CI-AL` (the wheel chain); `KF-J`
(`GeometryChangeScope`, the shape `IF-D` copies); `LC-` (the lifecycle drain);
`CR-M` (a platform seam that is set, not required).

---

## IF-A — Scope: what this branch builds, what it defers

**Ruling.** Build, in three lanes (`IF-J`), on AppKit and SDL:

1. `SpatialTapGesture.Value.modifiers` (`IF-B`) and `DragGesture.Value.clickCount`
   (`IF-C`).
2. `onModifierKeysChanged(mask:initial:_:)` (`IF-D`), with the platform's two
   small additions of `IF-I`.
3. `.onCancelled(_:)` on `DragGesture`, `MagnifyGesture`, `RotateGesture`
   (`IF-E`), delivered from the sites of `IF-F`.
4. Wheel latching (`IF-G`) and a guaranteed terminal scroll phase (`IF-H`).

**Deferred, each with a reason and an owner:**

- **`@GestureState` / `updating(_:body:)`** (VI-a's alternative): a
  `GestureState` is a third kind of property `StateReflection` would have to
  bind (a new arm in its per-type cache) over storage that is neither a
  `StateTable` slot (the seven are closed) nor an `AnimationStore` key with an
  owner; the cancellation callback gives an owner the same information
  (`@State` reset in `onCancelled`) without touching identity. Owner: none
  (additive; `Gesture.swift`'s "Not offered" list keeps the entry).
- **A drag per button at once** (`CI-AA` item 4: a press of another button while
  an arena is alive is ignored): needs one arena per button, changes the
  `CI-AG` pin on purpose and `MN-B`'s context-menu deferral; what MetalCreator
  hit was the *lost release*, which `IF-F` item 3 closes. Owner: none.
- **Lost-release detection for the primary arena** (a `.mouseMoved` while the
  primary arena is pressing): measured-first, see `IF-F` item 3; not built
  because a test that presses and moves without a release may exist. Owner:
  none.
- **`modifiers` on `TapGesture`/`onTapGesture`/`LongPressGesture`**: no caller
  asked; `SpatialTapGesture` is the tap that carries a value. Owner: none.
- **A probe of AppKit's wheel latching and of `onModifierKeysChanged`'s timing**:
  the instrument cannot deliver them (`IF-D`, `IF-G`). Owner: a session whose
  process may post events (Accessibility permission), human check IF1/IF4.
- **Per-button latching, scroll chaining.** Owner: none.

**Cost if wrong.** Every deferral is additive over a spelling built here.

## IF-B — `modifiers` on `SpatialTapGesture.Value`: the last press's

**Finding.** SwiftUI's value has `location` only (interface census), so the
field is **MetalUI-only**, as `DragGesture.Value.modifiers` is (divergence 140).

**Ruling.** `public var modifiers: EventModifiers`, the modifier keys of **the
last press of the sequence** — for `count: 2` the second press — not the
release's. `Value` stays `Equatable, Sendable`; it gains an `init(location:
modifiers:)` with `modifiers` defaulting to `[]`. Divergence **235** records
this and `IF-C`'s field together.

**Reasoning.** GI-a's need is "whether ⇧ was held *at the press*": shift-click
extends a selection, and a user who lets ⇧ go a moment before the button
should still extend. The arena already receives each press's modifiers
(`press(at:clickCount:continuing:modifiers:)`); storing them on the leaf at each
press is one assignment. `DragGesture`'s `onEnded` uses the release's
(`CI-G`) because its value *is* the release; a tap's value is the sequence
completing, and its press is the intent.

**Rejected:** the release's modifiers (a ⇧ lifted early loses the extend); both
(two fields, no caller).

**Cost if wrong.** An app wanting the release's modifiers reads
`onModifierKeysChanged`'s last value.

## IF-C — `clickCount` on `DragGesture.Value`; the tap sequence window is SwiftUI's

**Finding (probe `D1`–`D4`).** SwiftUI's `SpatialTapGesture(count: 2)` **times
the clicks itself**: two clicks both carrying `clickCount` 1, 50 ms apart,
recognise (`D3`); `clickCount` 1 then 2 at 0.4 s do **not** (`D4`, though the
system interval, `NSEvent.doubleClickInterval`, is 0.5 s) nor at 0.8 s
(`D2`). So SwiftUI reads neither the event's count nor the user's interval, and
MetalUI's fixed 0.33 s (`tapSequenceDeferral`, `IX-C`) is SwiftUI's shape.

**Ruling.**

1. `DragGesture.Value.clickCount: Int` — the press's `MouseEvent.clickCount`
   (AppKit's `NSEvent.clickCount`, which honours the user's double-click speed;
   SDL's `clicks`), constant for the drag's life (every `onChanged` and the
   `onEnded` carry the same number), `1` for a value built without one. For a
   `button:` drag the pressing button's. **MetalUI-only** (SwiftUI's value has
   none; divergence 235).
2. `tapSequenceDeferral` is **not** changed and the system interval is **not**
   read for taps: a divergence from SwiftUI with no caller asking for it.
   A canvas that wants the user's speed reads `clickCount`.
3. `Value.init(startLocation:location:modifiers:clickCount:)` — `clickCount`
   defaulted to 1 so the 2- and 3-argument spellings keep compiling (a plain-
   import guard pins it).

**Cost if wrong.** A platform whose press count is wrong (SDL on X11 without
repeat) hands a canvas 1 for a double click; the app's own pairing remains.

## IF-D — `onModifierKeysChanged(mask:initial:_:)`: a transparent scope, the action after the build

**Finding.** The interface is `onModifierKeysChanged(mask: EventModifiers =
.all, initial: Bool = true, _ action: (old, new) -> Void)`, macOS 15. Its
**timing, masking and key-window behaviour were not measured** (the `M` arms
read "-" including their controls). The contract below is MetalUI's, labelled
so; it claims nothing about SwiftUI beyond the signature and defaults.

**Ruling.**

1. **One transparent `ModifierKeysScope`** on every `ElementGroup` and the
   proposal vocabulary, the shape of `GeometryChangeScope` (`KF-J`): no node, no
   id level, no `Element` hook, `Handlers` unchanged (nineteen), a position key
   `.named("$modkeys<depth>")` in the window's `LifecycleStore` — never a
   `StateTable` slot (the seven unmoved).
2. **The window owns the modifiers.** `Window.currentModifiers` is set from
   `.modifiersChanged` and from the `modifiers` of every key, pointer and scroll
   event (SDL sends no flags-changed event; a modifier key's own key event
   carries the new state), stamped onto the `Frame` like `controlActiveState`
   (never a `Window.environment` write). A change dirties the window **only if
   the last frame had a scope** (`hasModifierObservers`), so an app with none
   pays nothing.
3. **The action runs in the lifecycle drain** (`Window.drainLifecycle`, after
   the build, outside every phase, under `StateDispatch` to the scope's
   position) with `(old, new)`, both **masked** (`value & mask`), only when the
   masked value differs from the one the store holds. `initial: true` (the
   default) reports `([], current & mask)` at the scope's first presented frame
   when `current & mask` is not empty — an empty first report is not made
   (SwiftUI's is unprobed; `IF1`). `initial: false` stores the current value
   silently. A write from the action dirties the window and costs one settle
   build, so a hover that reads the write is correct in the next frame.
4. **Key loss and gain.** On leaving `.key` the window sets its modifiers to `[]`
   (a window does not see flags while not key) — reported as a change; the
   platform sends `.modifiersChanged(current)` on becoming key (`IF-I`).
5. A headless `renderFrame` runs nothing (as `LC-`/`KF-J`).

**Reasoning.** The sketch editor's need is a ⌘ toggle while the pointer is still:
the app stores the modifiers in its model from the action and its hover reads
them. A scope reuses the one drain that already orders "values noted in
prepaint, actions after the build", so no new handler member, hit-test or
identity rule exists. The cost is one frame between the key and the action (it
cannot be earlier without running app code from input, which `Handlers` do not
do for scopes).

**Rejected:** a `Handlers` member (the 1 MB-stack and size pins move; hit-test
adjacency is meaningless for a window-wide fact); running the action from the
input hook (breaks "write from input" ordering with an in-flight build).

**Cost if wrong.** SwiftUI's report is one event earlier or masks differently:
a human check (`IF1`) compares the demo against a SwiftUI sample; the fix is the
masking line.

## IF-E — Gesture cancellation: `onCancelled`, once, only for a gesture that began

**Finding (probe `C1`–`C5`).** SwiftUI **never calls `onEnded` for a cancelled
gesture** and resets its `@GestureState` to the initial value (`C2` the gesture
disabled mid-drag, `C3` its view removed: `updating | changed … ended` absent,
state back to 0 at the next event). A window resigning key mid-drag is **not** a
cancellation (`C4`: the release still ends it). A second press without a
release does not end the gesture and the one release ends it once (`C5`; its
`GestureState` reads 0 then 1 across the second press, so "does not restart" is
not claimed). SwiftUI therefore tells its owner
only through `@GestureState`, which `IF-A` defers.

**Ruling.** `DragGesture.onCancelled(_ action: @escaping @MainActor () -> Void)`,
and the same on `MagnifyGesture` and `RotateGesture` (value-less: the last
`onChanged` already carried the value). **MetalUI-only** (divergence 236).

1. It runs **exactly once** for a leaf that had reported at least one
   `onChanged` and whose arena is then ended **without** that leaf's `onEnded`
   (the sites of `IF-F`). Never after `onEnded`; never for a leaf that never
   began (a drag short of `minimumDistance`, an exclusive loser).
2. It runs under the leaf's owner (`StateDispatch`), in the callback list of the
   event that dropped the arena, **before** any callback of the arena that
   replaces it.
3. A composed gesture's leaves each decide for themselves.

**Reasoning.** `onEnded` for a dropped arena was considered and rejected: apps
read `onEnded` as "the user finished" (commit an edit); a cancellation must be
distinguishable, and SwiftUI's own contract is that `onEnded` is skipped.

**Cost if wrong.** A caller who wanted `onEnded` writes the same closure into
both.

## IF-F — Where a cancellation comes from

**Ruling.** An arena is cancelled (`GestureArena.cancel()`: every leaf of
item 1's kind owes `onCancelled`, then fails) at:

1. **A dropped primary arena**: `Window.dispatchGestures`' `.mouseDown` branch
   (`arena.abandon()` today) and `endPressForDrag`'s drop when a leaf had
   reported (the preview begins on a draggable's first move; a `DragGesture`
   beside it that had reported is cancelled).
2. **A replaced stale button or pinch arena** (`CI-AB` items 1 and 2): the
   silent drop becomes a cancel. This is the same-centre pinch: the stale
   start is closed by `onCancelled` before the new pinch's first change.
3. **A `.mouseMoved` while a button arena is alive** (secondary/middle/other
   buttons only): AppKit and SDL send moves without a button only when no
   button is down, so the release was lost (a modal panel or a native menu took
   it). The arena is cancelled, a pending context menu is dropped, hover and the
   pointer style resume. The primary arena is **not** treated so (deferred,
   `IF-A`); if the lane finds an existing test that presses and moves without a
   release on a button arena, it restricts nothing but updates that test and
   says so in the record.
4. **The window leaves `.key`**: the **pinch** arena is cancelled (gesture
   events go to the key window, so its end is lost for certain). The primary and
   button arenas are **not** (SwiftUI `C4`; the pointer grab continues and the
   release arrives).
5. **A window close**: every live arena is cancelled, before `onDisappear`s.

**Cost if wrong.** Item 3 cancelling a drag a platform delivers `.mouseMoved`
during: the drag ends early; one pin (1.11) and the human check `IF5` hold it.

## IF-G — Wheel latching: a scroll's events go where its `.began` went

**Finding.** `CI-AD` left it unbuilt and unprobed. It is **still unprobed**:
`NSWindow.sendEvent` skips the window server's routing, and `M6` shows a posted
CGEvent never reaches the process. This is MetalUI's own design, said so;
`.onScrollWheel` is MetalUI-only, so there is no SwiftUI behaviour to diverge
from.

**Ruling.**

1. A `ScrollEvent` with `phase == .began` latches: `Window` records the cover of
   the existing lookup (`applyScroll`'s `cover` id and its hit layer) in
   `ScrollLatch` (a struct in its own file, one stored property on `Window`).
   `.mayBegin` latches nothing.
2. While latched, an event with `phase` `.changed`/`.ended`/`.cancelled`, or
   with a non-`.none` `momentumPhase`, is dispatched through the **latched
   cover's chain** (handlers and scrollers, innermost first, same layer) **without
   the `contains(point)` test**; `location` is the pointer in each region's space
   (it may lie outside). Hover, the cursor and every other consumer of the pointer
   are untouched.
3. The latch ends at `momentumPhase` `.ended`/`.cancelled`, at a later `.began`
   (replaced), at an event with `phase == .none && momentumPhase == .none` (a
   wheel mouse, and every SDL event: SDL has no phases, so it never latches), at
   losing key, and when the latched id is no longer in the last frame's hitboxes
   (fall back to the pointer for that event). A gesture that ends with no momentum
   leaves a harmless stale latch: nothing but a gesture event consults it.
4. A latched dispatch claims exactly as a pointer one does; a latched cover with
   no claiming region returns what `applyScroll` returns today for that cover.

**Cost if wrong.** A glide keeps scrolling the latched element after the pointer
left it (the request). A latched element removed mid-glide falls back at once.

## IF-H — A guaranteed terminal scroll phase

**Ruling.** `Window` tracks the in-flight scroll of the latch: from `.began` until
`phase` `.ended`/`.cancelled`, then, if a `momentumPhase` was seen, until
`.ended`/`.cancelled`. On leaving `.key` and on a window close with one in flight,
the window **synthesizes one terminal event** to the latched cover's chain:
`ScrollEvent(delta: 0, phase: .cancelled, momentumPhase: .none)` while the finger
stage is in flight, `(phase: .none, momentumPhase: .cancelled)` while the momentum
stage is. It reaches the wheel **handlers** only (the `Bool` is ignored, no
scroller moves, the scroll offset and its indicator are untouched), then the
latch clears. No event synthesized when none is in flight, so SDL (always `.none`)
never synthesizes: "SDL too" holds because the window, not the platform, does it.

**Reasoning.** AppKit's `NSEvent.phase` ends in `.ended`/`.cancelled`; a window
resigning key mid-scroll is the one way MetalUI's stream loses it, and MetalCreator's
camera is left unsettled until a later scroll ends.

**Cost if wrong.** A handler that treats `.cancelled` as a commit sees a zero delta:
`delta` is zero, so a sum is unaffected.

## IF-I — The platform's two additions: no new requirement

**Ruling.** No `PlatformWindow`/`Platform` requirement is added (`.modifiersChanged`
exists since the AppKit host view). **AppKit**: the window's `didBecomeKey`
(`refreshControlActiveState`) also sends `.modifiersChanged(NSEvent.modifierFlags)`.
**SDL**: the bridge's focus-gained event carries `mods(SDL_GetModState())` in its
`modifiers` field (`SDLBridge.c`), and `SDLPlatform` forwards `.modifiersChanged`
from it. A fake needs nothing. A third-party conformer may ignore both: the window
then learns the modifiers from the next event that carries them.

**Cost if wrong.** A modifier pressed while another window was key is reported at
the first event after focus; one human check (`IF1`).

## IF-J — Lanes: three, run in order in one worktree

**Ruling.** Agents run one at a time here, so the lanes share `Window.swift` in
**disjoint regions** and every new stored property of `Window` is one line
pointing at a struct in the lane's own file.

- **Lane 1 — gesture values and cancellation** (`IF-B`, `IF-C`, `IF-E`, `IF-F`):
  `Gesture.swift`, `SpatialGestures.swift`, `Window.swift` (the gesture and
  button/pinch-arena region), `Tests/MetalUITests/GestureFollowupTests.swift`,
  `GestureFollowupCompileGuards.swift`.
- **Lane 2 — wheel** (`IF-G`, `IF-H`): `ScrollWheel.swift`, new `ScrollLatch.swift`,
  `Window.swift` (`applyScroll` and the key-loss hook), `ScrollLatchTests.swift`.
  Needs lane 1's `cancelOnKeyLoss` hook only for the shared control-state line:
  lane 2 adds its call beside lane 1's.
- **Lane 3 — modifier keys** (`IF-D`, `IF-I`): new `ModifierKeysChange.swift`,
  `Lifecycle.swift`/`Frame.swift` (the store entry and the stamp), `Window.swift`
  (input front), `AppKitPlatform.swift`, `Backends/SDL` (bridge, platform, tests),
  the canvas demo section, human checks, the inventory, the Linux image run.

**Cost if wrong.** A merge conflict in `Window.swift`; regions are far apart.

## IF-K — Critic's rulings: lanes rebalanced, demo file, removed/disabled owners

**Re-run.** The probe was re-run by the critic (compiled form, screen unlocked):
20 lines, byte-identical to the header's recorded arms (`D1`–`D4`, `C1`–`C5`; the
`M` arms still read "-", so `IF-D` stands as MetalUI's own contract). Two
overclaims were corrected in `IF-C` and `IF-E` (the 0.33 s equality; `C5`'s
"does not restart").

**Rulings.**

1. **Lanes rebalanced (supersedes `IF-J`'s split, not its order).** Lane 3 held the
   scope, the store, two platforms, the SDL tests, the demo and the Linux image;
   lane 2 held only the wheel. Lane 2 now also takes `IF-I` (the AppKit
   `didBecomeKey` send, the SDL bridge focus-gained modifiers, tests 4.1–4.3 and the
   `Backends/SDL` + Linux image runs): it touches no file lane 3 does, and the
   platform sends an event the window already accepts. Lane 3 keeps `IF-D`, the demo
   and the human checks.
2. **The demo section lives in a new file** `Sources/MetalUIDemoContent/
   InputFollowupsDemo.swift`, in its own function, hooked by one line in
   `CanvasDemo.swift` (not edited otherwise): `feat/overlays-coords` is likely to
   edit the canvas demo, and the one-line hook is the whole conflict surface.
3. **A drag whose gesture is disabled or whose owner is removed mid-drag gets no
   `onCancelled`** (SwiftUI's `C2`/`C3` reset the `@GestureState`; MetalUI has no
   such storage and a removed owner has nothing to be told). Considered: cancel when
   the leaf's id is absent from the next frame. Rejected because `onCancelled`'s
   closure belongs to the removed element, its `@State` is reset (`ID-C`) and
   running it would write to dead state. Said in the `onCancelled` doc comment.
4. **`IF-F` item 3 is gated by the platform's own event kinds**: AppKit and SDL send
   `.rightMouseDragged`/`.otherMouseDragged` while a button is held (SDL
   `MUI_EVENT_RIGHT_DRAG`/`OTHER_DRAG`, checked in `SDLPlatform`), so `.mouseMoved`
   with a live button arena is a lost release by construction. Lane 1 owes a test on
   each fake sequence (drag events keep the arena; moved cancels).
5. **`onModifierKeysChanged`'s unprobed behaviours** (empty first report, mask
   timing) are listed under human check `IF1`; no divergence label is spent on an
   unmeasured difference. If `IF1` shows one, it takes label 237.


## IF-L — Lane 1 as built: what the arena cancels, and the sites

**Finding.** Built as `IF-E`/`IF-F`, with these particulars of the code:

1. `GestureArena.cancel(includingReady:)` appends, for each undecided leaf that
   has **activated** (reported a change: `ArenaLeaf.activated`, the drag's and the
   pinch's own flag) and whose gesture has an `onCancelled`, one callback, then
   fails the leaf. `abandon()` calls it with `includingReady: false` first — a
   leaf only waiting to be allowed to end still ends — and returns the cancels
   ahead of the callbacks its `resolve()` frees. Every other site drops the
   whole arena and uses the default (ready leaves included).
2. The draggable's win (`act`'s `.draggable` arm) is where `IF-F` item 1's
   preview case is reachable: the other members fail there, so it appends their
   cancels **before** the `.beginDrag` callback. `endPressForDrag` is not given a
   second cancel (it finds only ended or failed leaves; dead code is untestable).
3. `ArenaLeaf` gains `pressModifiers` and `pressClickCount`, set for every
   undecided leaf at **each** press (a continuing press overwrites: the last
   press, `IF-B`). A `DragGesture.Value` carries the leaf's count from the
   press, never the move or release event's (test 1.3 sends 1 on the moves).
4. `DragGesture.Value.init(startLocation:location:modifiers:clickCount:)` has
   `clickCount` defaulted; the 2-argument spelling stays. `SpatialTapGesture.Value`
   gains a public `init(location:modifiers:)`.
5. `.mouseMoved` with a live button arena cancels it, clears `pendingContextMenu`
   and **does not claim the move**, so hover, tooltip and the pointer style run on
   it as before. The pointer style of the cancelled press is recomputed by the next
   move (one event later). The platform event kinds are pinned by existing tests,
   not new ones: `sdlMotionWithRightOrMiddleHeldIsARightOrOtherDrag` (SDL),
   `appKitOtherButtonsAndRightDragReachOnInput` and `aControlDragOnAppKitIsASecondaryDrag`
   (AppKit) — a held button is always a `*Dragged`, so the window tests 1.10/1.10b
   drive the same sequences through the fake.
6. Window sites: `onControlActiveStateChange` (`state != .key`) calls
   `cancelPinchArena()`; `runDisappearancesForClose` begins with `cancelLiveArenas()`
   (primary, button, pinch); `dispatchPinch` and `buttonPress` cancel the stale arena
   before forming the new one.

**Cost if wrong.** A `DragGesture` with no `onChanged` closure still counts as
having activated, so a lone `onCancelled` runs: intended (the owner learns the drag
began without being told each move).
