# Input APIs for viewports and canvases — decisions

Rulings for the scroll wheel on an element, magnify and rotate gestures, the
middle and other buttons and right-drag, tap location, the pointer style and
modifiers during a drag (user request 2026-10-02, an item of the gpui-gap
priority list; **not a plan task**; motivated by MetalCreator, a node-based CAD
app on MetalUI: a 3D viewport inside `GPUSurface`/`MetalView` and a pannable,
zoomable node-graph canvas — its `docs/metalui-gaps.md`, sections "Reported
2026-10-07 (C7)" and "C7 status and provisional API names").
Spec: [`specs/2026-10-08-input-apis-design.md`](specs/2026-10-08-input-apis-design.md).
Record: `../record/81-input-apis.md`.

> **For MetalCreator — names.** Every provisional name in its C7 list is kept:
> `SpatialTapGesture` (`.location`), `.onTapGesture(count:coordinateSpace:perform:)`,
> `MagnifyGesture` (`.magnification`, `.startLocation`, `.startAnchor`),
> `RotateGesture` (`.rotation`, `.startAnchor`), `.pointerStyle(_:)` with
> `.grabIdle`, `.grabActive`, `.rectSelection` (**the crosshair is
> `.rectSelection`** — SwiftUI has no `.crosshair`; probe `P2`), `.onScrollWheel`
> handing a `ScrollEvent`, `DragGesture(…, button: .secondary / .middle)` and
> `DragGesture.Value.modifiers`. **Three refinements to watch for:** (1)
> `.onScrollWheel`'s closure **returns `Bool`** — `true` claims the event, `false`
> passes it on (`CI-I` item 2); (2) the pointer location on `ScrollEvent` is
> **`location`** (local), beside the existing window-space `position` (`CI-I`
> item 1); (3) `RotateGesture.Value.rotation` is **positive clockwise** — the
> negative of AppKit's `NSEvent.rotation` (probe `Q1`).

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-input-apis.swift`](../probes/swiftui-input-apis.swift)
  (**new**; arms `T0`…`T4`, `R0`…`R4`, `M0`…`M3`, `Q0`/`Q1`, `P00`…`P14`,
  `C0`…`C2`, plus an interface census of SwiftUI's `.swiftinterface`; run twice,
  byte-identical, 50 lines) — SwiftUI's and AppKit's answers.
- gpui's event model, **as a comparison where SwiftUI has no API, never as
  evidence**: `crates/gpui/src/interactive.rs` at zed `cb73ee1d`
  (`ScrollWheelEvent { position, delta: ScrollDelta::{Pixels, Lines},
  modifiers, touch_phase: TouchPhase::{Started, Moved, Ended, Cancelled} }`,
  `MouseButton::{Left, Right, Middle, Navigate(Back|Forward)}`,
  `MouseMoveEvent.pressed_button`, `PinchEvent { position, delta, modifiers,
  phase }`).
- SDL 3.4.16 (the Linux image's `SDL_TAG`) source, read for what each video
  driver emits: `src/video/cocoa/SDL_cocoawindow.m` `magnifyWithEvent:` (pinch,
  `scale = 1 + magnification` per event, window `NULL`),
  `src/video/wayland/SDL_waylandevents.c` `handle_pinch_update` and
  `src/video/x11/SDL_x11xinput2.c` `XI_GesturePinchUpdate` (pinch, `scale` the
  protocol's **cumulative** scale since the gesture began), no pinch in
  `src/video/windows/SDL_windowsevents.c`; no rotate event anywhere;
  `SDL_MouseWheelEvent` has no phase, momentum or precision field; SDL's system
  cursors have no open/closed hand and no zoom (`SDL_mouse.h`, 3.4.18 on this
  Mac).

Prefix **`CI-`**, lettered. **Next unused: `CI-P`.** (This line moves in the
commit that appends a ruling; read the last `## CI-` heading.)

Branch `feat/input-apis` from `70ed000` (master: portable app merged, PR #51).
Baseline at `70ed000`: see spec §0 (measured by this design session).
`docs/divergences.md`: **next label 139**. Human checks: groups A–X (next
**Y**).

**Carried items.** `IX-B`…`IX-D`, `IX-Q` (the closed `Gesture` protocol, one
arena per press from the one ranking plus the target's ancestors **in its own
hit layer**, callbacks under `StateDispatch`); `IX-C` (tap slop 5, sequence
deferral 0.33 s); `DN-D`/`DN-E` (a draggable is a non-opaque arena member);
`MN-B`, `MN-AC` (a secondary press is its own event and never presses, taps,
drags or focuses; AppKit's control-click is a secondary press), `MN-E` (the
context-menu stage, on the press), `MN-F` (an open in-window menu takes every
pointer, wheel and key event); `DD-Y` (a wheel over a non-scrolling opaque
target passes to its nearest same-layer ancestor scroller, else stops there);
`TI-H` (a multi-line editor scrolls itself); `SV-N`, `SV-Z`, `SV-U` (hover:
non-opaque regions, the hovered set from `topmostHitbox` with "opaque or
hover" eligibility, callbacks from input and after the frame); `GX-I`, `GX-P`
(hitboxes and local points follow render effects); `OM-AK` (`allowsHitTesting`
gates the pointer hitbox per layer); `MV-` (a `GPUSurface` is an ordinary leaf:
its modifiers' hitboxes are the leaf's). The `IX-B` "Not offered" list in
`Gesture.swift`'s doc names `SpatialTapGesture`, `MagnifyGesture`,
`RotateGesture`, a tap with a location and `coordinateSpace:` — this branch
offers all five.

---

## CI-A — Scope: what this branch builds, what it defers

**Ruling.** Build, in three lanes (`CI-O`), on AppKit **and** SDL:

1. **Tap location** (`CI-B`): `SpatialTapGesture(count:coordinateSpace:)`,
   `.onTapGesture(count:coordinateSpace:perform:)` with a `Point<Pixels>`, a
   `CoordinateSpace` of `.local` and `.global`, and `coordinateSpace:` on
   `DragGesture`.
2. **Magnify and rotate** (`CI-C`, `CI-D`, `CI-K`): `MagnifyGesture`,
   `RotateGesture` in a pinch arena formed from the one ranking; platform
   events `.magnify`/`.rotate` from AppKit's `magnify(with:)`/`rotate(with:)`
   and SDL's `SDL_EVENT_PINCH_*`.
3. **Other buttons and right-drag** (`CI-E`, `CI-F`): `.rightMouseDragged`,
   `.otherMouseDown/Dragged/Up` input events, `DragGesture(…, button:)` with a
   `MouseButton`, and a context menu that waits for the release when a
   secondary drag is declared on the press's chain.
4. **Modifiers during a drag** (`CI-G`): `DragGesture.Value.modifiers`.
5. **The pointer style** (`CI-H`): `PointerStyle` and `.pointerStyle(_:)`,
   resolved through the hover machinery's ranking, reaching the platform
   through a new defaultless `PlatformWindow.setPointerStyle(_:)`.
6. **The scroll wheel on an element** (`CI-I`): `.onScrollWheel(perform:)`
   handing an extended `ScrollEvent` (phase, momentum phase, precision, local
   location), dispatched innermost-first through the press target's chain,
   interleaved with `ScrollView`'s own scrolling.
7. A **canvas demo** (`METALUI_CANVAS_DEMO=1`, its own function) and human
   checks group **Y** for trackpad feel.

**Deferred, each named in spec §9 with a reason and an owner:**

- `MagnifyGesture.Value`/`RotateGesture.Value` `time` and `velocity`, and
  `DragGesture.Value` `time`, `velocity`, `predictedEnd*` — MetalUI has no
  `Date` in the gesture layer and no velocity estimator. Owner: none
  (additive).
- `PointerStyle.image(_:hotSpot:)`, `.shape(_:eoFill:size:)`,
  `.columnResize(directions:)`, `.rowResize(directions:)` — a custom cursor
  image needs a platform image-cursor path on both backends. Owner: none.
- SwiftUI's `onModifierKeysChanged(mask:initial:_:)` (macOS 15) — `CI-G` gives
  the drag case MetalCreator asked for. Owner: none.
- `CoordinateSpace.named(_:)` and `.coordinateSpace(_:)`. Owner: none.
- The I-beam over `TextField`/`TextEditor` and the pointing hand over `Link`
  (SwiftUI shows them; MetalUI's own controls declare no style yet) — text
  input must not move on this branch. Owner: none (one `pointerStyle` line per
  control later).
- `RotateGesture` on SDL (no SDL rotate event; `CI-K`), magnify on Windows
  (SDL 3.4.16 emits no pinch there), scroll phase/momentum/precision on SDL
  (`SDL_MouseWheelEvent` carries none). Owner: none — each waits on SDL.
- `GestureInputKinds` / `inputKinds:` (macOS 27): MetalUI has one input kind,
  the pointer. Owner: none.
- Scroll chaining (a scroller at its limit passing the rest of a delta on) —
  still `applyScroll`'s recorded non-goal. Owner: none.

**Reasoning.** MetalCreator's five gaps are exactly items 1–6; each deferral
is additive over a spelling built here.

**Cost if wrong.** A deferral turns out needed: each is an addition, none
renames anything.

## CI-B — Tap location: SwiftUI's spelling, local by default

**Ruling.**

1. **`SpatialTapGesture: Gesture`**, `Value` a struct with `location:
   Point<Pixels>`; `init(count: Int = 1, coordinateSpace: CoordinateSpace =
   .local)`; `onEnded(_:)` taking `(Value) -> Void`. Recognized exactly as
   `TapGesture` (`IX-C`: slop 5, sequence deferral, counted from the arena's
   first press) — it is a tap leaf that also records a point. **The location
   is the release that ends the tap** (MetalUI's choice: the probe pressed and
   released at one point, `T1`/`T4`; within the 5-point slop the two cannot
   differ by more than 5).
2. **`.onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace = .local,
   perform: @escaping @MainActor (Point<Pixels>) -> Void)`** on both
   vocabularies (`StyledElement` → `Self`; `ProposalElementGroup` →
   `GestureModifier<Self>`), beside the existing location-less overload; the
   closure's arity selects the overload, as in SwiftUI (`T0`, `T3`). If Swift
   finds `{ … }` ambiguous, the location overload takes `@_disfavoredOverload`
   (SwiftUI marks one of its own two so); the guard
   `onTapGestureResolvesByClosureArity` pins both resolutions (spec §4).
3. **`CoordinateSpace`** — a MetalUI enum with **`.local`** (the gesture
   element's own space, top-leading origin, render effects undone through
   `Hitbox.localPoint`, as `HoverPhase` and `DragGesture.Value` already are)
   and **`.global`** (the window's content space, the point `MouseEvent`
   carries). `DragGesture(minimumDistance:coordinateSpace:button:)` takes it
   too; its values in `.global` are window points.
4. **Divergence 139**: SwiftUI's `.global` in a titled window reads (60, 72)
   where the content-space point is (60, 40) (probe `T2`): its global space
   includes the window's title bar; MetalUI's `.global` is the content view's
   space (MetalUI has no title-bar-inclusive space; a window's content is its
   whole world).
5. `Gesture.swift`'s "Not offered" list loses `SpatialTapGesture`, "a tap with
   a location" and `coordinateSpace:`; it gains `CoordinateSpace.named`.

**Evidence.** Probe `T0`–`T4`: local (20,10) → `loc (20.000, 10.000)`; `.global`
→ (60, 72); `onTapGesture(count:coordinateSpace:perform:)` (70,55) → (70, 55);
a double tap reports its location. Census: `SpatialTapGesture.Value.location`,
`init(count: = 1, coordinateSpace: = .local)`.

**Cost if wrong.** If SwiftUI reports the press point rather than the release,
a tap location differs by under 5 points — invisible to picking.

## CI-C — `MagnifyGesture` and `RotateGesture`: values as SwiftUI measures them

**Ruling.**

1. **`MagnifyGesture(minimumScaleDelta: Double = 0.01)`**, `Value { magnification:
   Double; startLocation: Point<Pixels>; startAnchor: UnitPoint }`, `onChanged`,
   `onEnded`. **`magnification` is cumulative and additive from 1**: `1 + Σ` of
   the platform's per-event deltas (AppKit +0.1, +0.1 → 1.1, 1.2, not 1.21;
   −0.2 → 0.8 — probe `M1`, `M2`).
2. **`RotateGesture(minimumAngleDelta: Angle = .degrees(1))`**, `Value { rotation:
   Angle; startLocation; startAnchor }`. **`rotation` is cumulative and
   positive clockwise on screen** (y down): the negative of AppKit's
   `NSEvent.rotation` (AppKit +10°, +10° → −10°, −20°, probe `Q1`). The AppKit
   platform negates once at the seam (`RotateEvent.rotation` is already
   clockwise-positive degrees), so `Window` adds.
3. **`startLocation`** is the pointer at the gesture's first event, in the
   declaring element's local space; **`startAnchor`** is that point as a
   fraction of the element's hit region size (`(20,20)` in 100×100 → `(0.2,
   0.2)`, probe `M1`). Both are fixed for the gesture. **The current pointer is
   not reported** (SwiftUI's value has no current location); MetalCreator's
   "zoom about the pinch centre" reads `startLocation` (trackpad pinches do not
   move the pointer).
4. **Activation**: a leaf reports its first `onChanged` once |magnification −
   1| ≥ `minimumScaleDelta` (|rotation| ≥ `minimumAngleDelta`), then on every
   event; `onEnded` at the platform's ended/cancelled phase **only if it
   activated**. MetalUI's choice (the probe measured `minimumScaleDelta: 0`,
   `minimumAngleDelta: .zero`); mirrors `DragGesture`'s minimum (`IX-C` item 5).
5. **No `time`, no `velocity`** (`CI-A` deferred). **No pinch from
   control+scroll**: SwiftUI synthesizes none (probe `M3`: "-"), so MetalUI
   synthesizes none on any platform; a control/⌘-wheel reaches
   `.onScrollWheel` with its modifiers (`CI-I`), which is how MetalCreator's
   "⌘-scroll zooms" is written and how a Windows precision touchpad's pinch
   (sent to legacy apps as control+wheel) reaches an app.

**Evidence.** Probe `M0` (AppKit control: the instrument delivers real
`.magnify` events, 0.1 each), `M1`–`M3`, `Q0`, `Q1`; census
(`MagnifyGesture.Value` and `RotateGesture.Value` fields and initialisers).

**Cost if wrong.** A multiplicative reading would make long pinches drift by a
few percent; the probe rules it out on macOS 27.

## CI-D — The pinch arena

**Ruling.**

1. **A pinch forms its own arena**, not a press's: on a `.magnify` or `.rotate`
   event with phase `.began` (or any phase, when no pinch arena is alive), the
   window finds the target through the **one ranking** —
   `topmostOpaqueHitbox(in:at:)` at the event's position, as a press does —
   plus the target's gesture-carrying ancestors **in its own hit layer**
   containing the point (`IX-Q`), and builds a `GestureArena` from their
   attachments in **pinch mode**: only `.magnify` and `.rotate` leaves are
   live; every other leaf (tap, long press, drag, draggable, the target's
   `onClick`) is **failed at formation**, so it neither acts nor blocks.
2. **Press arenas fail pinch leaves at formation** the same way, so a
   `DragGesture().exclusively(before: MagnifyGesture())` drags on a press and
   magnifies on a pinch.
3. **Ordering is the press arena's** (`IX-D` item 3): high-priority outermost
   first, normal innermost first, simultaneous members beside. **A magnify leaf
   and a rotate leaf never block each other** (AppKit delivers the two as
   independent event streams, and a two-finger gesture commonly carries both);
   among leaves of the same kind the exclusive order holds — the first
   unblocked leaf to activate wins and the same-kind leaves behind it are
   cancelled.
4. **Lifetime**: the arena lives while any begun kind has not ended; a kind
   that begins while the arena is alive joins it (its leaves were built at
   formation); it ends when every begun kind has ended or been cancelled. A
   press while a pinch arena is alive does not touch it (independent).
5. **Callbacks run under `StateDispatch.dispatching(to:)` their owner**, from
   input, exactly as `runGestureCallbacks` runs a press's.
6. **Gates and layers**: gestures ride the pointer hitbox, which is inside the
   disabled and `allowsHitTesting` gates (`OM-AK`); a presentation layer above
   is the ranking's target and joins no ancestor below it (`IX-Q`); an open
   in-window menu or a drawn alert takes the event first (`MN-F`, `SV-J`).

**Reasoning.** gpui delivers `PinchEvent` to the hitbox under the pointer;
SwiftUI composes `MagnifyGesture` in the ordinary gesture system. Building it
into the existing arena keeps one ranking, one ordering and one dispatch
footing, and costs only a mode flag on formation.

**Cost if wrong.** If SwiftUI lets magnify and rotate on nested views block
each other, a nested magnify + rotate pair would both run here; unmeasured,
human check Y4 looks.

## CI-E — Other buttons and right-drag at the seam

**Ruling.**

1. **New `InputEvent` cases**: `.rightMouseDragged(MouseEvent)` (motion with the
   secondary button held), `.otherMouseDown(MouseEvent)`,
   `.otherMouseDragged(MouseEvent)`, `.otherMouseUp(MouseEvent)` (any button
   but the primary and the secondary). **`MouseEvent` gains `buttonNumber:
   Int`** (AppKit's numbering: 0 primary, 1 secondary, 2 middle, 3 back, 4
   forward, …; `init(position:modifiers:clickCount:buttonNumber: = 0)`). The
   primary and secondary cases carry 0 and 1 by construction on both
   platforms; `Window` reads `buttonNumber` only on the `other…` cases.
2. **`MN-B` holds for everything that was primary-only**: no secondary or other
   press presses a `Button`, runs an `onClick`, a tap, a long press, a primary
   `DragGesture`, a draggable, a slider track, a text field, or moves focus or
   `active`. **They reach only** the context-menu stage (secondary press, as
   today), the popovers' outside-press dismissal (other press too, `MN-Y`), the
   tooltip's hide, the hover recompute, and **a `DragGesture` whose `button:`
   names them** (`CI-F`).
3. **AppKit**: `otherMouseDown/Dragged/Up(with:)` and `rightMouseDragged(with:)`
   are overridden (no `super`); a **control-press's drag now goes out as
   `.rightMouseDragged`** (it was dropped, `MN-AC` item 1 — **migration**: a
   control-drag is a secondary drag).
4. **SDL**: `SDL_BUTTON_MIDDLE` → buttonNumber 2, `SDL_BUTTON_X1` → 3,
   `SDL_BUTTON_X2` → 4, each as `.otherMouse…`; motion with `SDL_BUTTON_LMASK`
   stays `.mouseDragged`, else with `RMASK` → `.rightMouseDragged`, else with
   `MMASK`/`X1MASK`/`X2MASK` → `.otherMouseDragged` (the lowest held button
   number). New bridge kinds `MUI_EVENT_OTHER_DOWN`, `MUI_EVENT_OTHER_UP`,
   `MUI_EVENT_RIGHT_DRAG`, `MUI_EVENT_OTHER_DRAG` are **appended** after
   `MUI_EVENT_MOUSE_LEAVE` and the flattened struct gains `int32_t button` at
   its end (no earlier kind or field moves). A ctrl-click stays primary on SDL
   (`MN-AC`).
5. **Migration** (`docs/migration.md`): an exhaustive `switch` over
   `InputEvent` outside the package adds the new cases (this ruling's four and
   `CI-J`'s two) or a `default:`.

**Evidence.** gpui's `MouseButton::{Left, Right, Middle, Navigate}` and
`pressed_button` on moves (comparison); AppKit's `NSEvent.buttonNumber`; probe
`R2`/`R4` (SwiftUI gives these buttons nothing).

**Cost if wrong.** A test fake or an outside switch that missed a case fails
to compile — the intended migration.

## CI-F — Dragging with the secondary and middle buttons

**Ruling.**

1. **`DragGesture(minimumDistance: Pixels = 10, coordinateSpace: CoordinateSpace
   = .local, button: MouseButton = .primary)`** — the `button:` parameter is
   **MetalUI-only**: SwiftUI's `DragGesture` follows the primary button alone
   (probe `R4`: a real right press, buttonNumber 1, reports nothing; `R2`: a
   middle press reports nothing; `R3`: the primary through the same path
   does) and has no button parameter on any gesture (census). `R1` read a
   drag for an `NSEvent.mouseEvent(.rightMouseDown…)` whose `buttonNumber` is
   0 — an instrument artefact, recorded in the probe.
2. **`MouseButton`** — a struct over AppKit's `buttonNumber` with
   `.primary` (0), `.secondary` (1), `.middle` (2) and
   `.other(_ buttonNumber: Int)`; `Hashable`, `Sendable`.
3. **A secondary or other press forms a button arena**: the same
   `GestureArena`, formed from the same ranking (`topmostOpaqueHitbox`, the
   target's gesture-carrying ancestors in its hit layer) in **button mode for
   button N**: only `.drag` leaves whose button is N are live; every other leaf
   and the target's `onClick` are failed at formation. With no live leaf there
   is no arena (exactly today's behaviour). It is a separate arena from the
   primary one (`Window.buttonArena`), so a middle-drag during a pending
   primary tap sequence disturbs neither. The release of button N ends it.
   **A primary `DragGesture` (the default) never joins a button arena**, so
   every existing drag keeps `MN-B`.
4. **The context menu and a right-drag** (MetalCreator: right-drag orbits;
   the right-click face menu): AppKit and SwiftUI open a context menu **on the
   press** (probe `C0`, `C2`: tracking began during `rightMouseDown`), so there
   is no native rule for a press that may become a drag. **MetalUI's rule: when
   the secondary press's button arena has a live leaf, the context-menu stage
   does not open on the press; it opens on the release, at the press point, if
   no leaf of that arena activated (reached its `minimumDistance`)**; a leaf
   that activates cancels the pending menu. With no secondary `DragGesture` on
   the chain, the menu opens on the press, exactly as today. The threshold is
   therefore the drag's own `minimumDistance` (default 10 points).
5. **Values**: `startLocation`/`location`/`translation` in the declared
   coordinate space, as a primary drag's; `modifiers` per `CI-G`.

**Reasoning.** gpui gives every element raw `on_mouse_down(MouseButton::Middle,
…)`; MetalUI's surface is SwiftUI's gestures, so a button selection on the one
drag recognizer is the smallest MetalUI-only addition, and the arena keeps
ordering, layers and `StateDispatch`.

**Cost if wrong.** If SwiftUI later grows a button parameter with another
spelling, MetalUI adds it beside this one.

## CI-G — Modifiers during a drag

**Ruling.** **`DragGesture.Value.modifiers: EventModifiers`** (MetalUI's
`EventModifiers` is `Modifiers`): the modifier keys held at the event that
produced the value — the press for a `minimumDistance: 0` first change, each
drag event, the release for `onEnded`. A modifier pressed or released without
a pointer move produces no `onChanged` (SwiftUI's `DragGesture` reports only
on motion). `Value.init(startLocation:location:)` keeps its spelling with
`modifiers` defaulting to `[]`; a new `init(startLocation:location:modifiers:)`
is added. **Divergence 140**: SwiftUI's `DragGesture.Value` has no modifiers
(census); a SwiftUI app reads `NSEvent.modifierFlags` or
`onModifierKeysChanged`.

**Reasoning.** MetalCreator's "⌥ held mid-drag duplicates" needs the state at
the drag's events; MetalUI has no global modifier read and every `MouseEvent`
already carries modifiers.

**Cost if wrong.** None to existing code: `Value` gains a field (equality now
compares it; every existing construction defaults it to `[]`).

## CI-H — The pointer style

**Ruling.**

1. **`PointerStyle`** (SwiftUI's struct, `Sendable`, `Hashable`) with the
   statics `.default`, `.horizontalText`, `.verticalText`, `.rectSelection`,
   `.grabIdle`, `.grabActive`, `.link`, `.zoomIn`, `.zoomOut`, `.columnResize`,
   `.rowResize`, and `.frameResize(position: FrameResizePosition, directions:
   FrameResizeDirection.Set = .all)` with SwiftUI's `FrameResizePosition`
   (eight edges and corners) and `FrameResizeDirection.Set` (`.inward`,
   `.outward`, `.all`). Deferred statics in `CI-A`.
2. **`.pointerStyle(_ style: PointerStyle?)`** on both vocabularies:
   `StyledElement` → `Self` (a `Handlers` member, no identity level, `MN-Q`'s
   shape); `ProposalElementGroup` → `PointerStyleModifier<Self>`
   (`HoverModifier`'s recipe: one identity level, no layout node). **`nil`
   attaches nothing** (probe `P12`: an inner `nil` lets the outer style apply).
3. **Registration**: a **non-opaque pointer-style region** at the element's hit
   region (content shape applied), **inside the disabled, `allowsHitTesting`
   and `hidden()` gates**, exactly as the hover region (`SV-N` item 2). A frame
   with no style registers nothing (the hitbox list is unchanged).
4. **Resolution — the hover machinery's ranking, never a second lookup**: the
   cover is `topmostHitbox(in:at:where:)` with "opaque, or carries a hover
   attachment, or carries a pointer style" as eligibility; the candidates are
   the style regions on the cover's layer that contain the point and whose id
   the cover is or descends from; **the innermost (last registered) wins**
   (probe `P11`: the inner `.rectSelection` over the outer `.link`; `P11c`:
   off the inner, the outer). An opaque target above covers a style beneath it
   (`P13`/`P13c`). With no candidate the style is `.default`.
5. **Divergence 141**: SwiftUI hides a style beneath **any** view drawn above
   at the pointer, a view that only paints included (`P14`); MetalUI registers
   no hitbox for a view that only paints, so a painted-only overlay does not
   cover a style (nor a hover — `SV-N`'s rule, the same reason). Wrap it in
   `.contentShape` with a handler, or give it `.pointerStyle(.default)`.
6. **During a press** (the primary arena pressing, or a button arena alive),
   the style resolves against the **pressed target's chain** — the innermost
   style region on the target's layer whose id the target is or descends from
   — whether or not the pointer is still over it, so a `.grabActive` switched
   on by `@State` at the drag's start stays while a fast pan leaves the
   element. This follows AppKit's behaviour of not running cursor updates
   during a mouse drag (no `.enabledDuringMouseDrag`).
7. **When**: recomputed where hover is (`Window.updateHover`'s call sites —
   every pointer event and after every adopted frame), and the platform is
   called **only on a change**. While an in-window menu or a drawn alert is up
   the style is `.default` (`SV-N` item 6's rule). `.pointerExited` sets
   `.default` without a platform call being owed afterwards (the platform owns
   the cursor outside the window; the next entry recomputes).
8. **Platform**: **`PlatformWindow.setPointerStyle(_ style:
   PlatformPointerStyle)`, defaultless** (`EV-AB`'s reason) with
   `PlatformPointerStyle` in `MetalUIPlatform` (the cursor kinds below; no
   SwiftUI type crosses the seam). **AppKit** maps as the probe measured
   (`P1`–`P10`): default → `arrow`, rectSelection → `crosshair`, grabIdle →
   `openHand`, grabActive → `closedHand`, link → `pointingHand`, columnResize →
   `columnResize` (== `resizeLeftRight`), rowResize → `rowResize` (==
   `resizeUpDown`), horizontalText → `IBeam`, verticalText →
   `iBeamCursorForVerticalLayout`, frameResize(position:directions:) →
   `NSCursor.frameResize(position:directions:)` (macOS 15; `.trailing` →
   `.right`), zoomIn/zoomOut → `NSCursor.zoomIn`/`zoomOut`; the host view
   installs `.cursorUpdate` on its tracking area and answers `cursorUpdate(with:)`
   with the current cursor, and `setPointerStyle` sets it at once while the
   pointer is inside. **SDL** maps to `SDL_CreateSystemCursor` (cached per
   kind, `SDL_SetCursor`): default → `DEFAULT`, rectSelection → `CROSSHAIR`,
   link → `POINTER`, horizontal/verticalText → `TEXT`, columnResize →
   `EW_RESIZE`, rowResize → `NS_RESIZE`, frameResize → the matching
   `N/S/E/W/NE/NW/SE/SW_RESIZE`; **grabIdle and grabActive → `MOVE`, zoomIn and
   zoomOut → `DEFAULT`** (SDL has no hand or zoom cursor: a documented platform
   constraint, not a silent approximation — `SDLPlatform`'s doc comment and
   human check Y6 name it). The SDL window **records** every requested style
   (`pointerStyles`), so a test under the offscreen driver (where cursor
   creation may fail) still sees the request.

**Evidence.** Probe `P00`–`P14` (control `P0`: an `NSView`'s `cursorUpdate`
reads back `crosshair`; the instrument's history is in its header), census
(`PointerStyle`'s statics, `pointerStyle(_ style: PointerStyle?)`); gpui
(`cursor_style` on an element, the topmost hitbox's style wins — comparison).

**Cost if wrong.** A misread mapping shows the wrong cursor — human check Y5
looks at every style on AppKit.

## CI-I — The scroll wheel on an element

**Ruling.**

1. **`ScrollEvent` (the seam's existing public struct) gains** `phase:
   InputPhase`, `momentumPhase: InputPhase`, `isPrecise: Bool` and `location:
   Point<Pixels>`. `InputPhase` (new, `MetalUIPlatform`): `.none`, `.mayBegin`,
   `.began`, `.changed`, `.ended`, `.cancelled` (AppKit's `NSEvent.Phase`;
   gpui's `TouchPhase` is the comparison). `isMomentum` becomes a computed
   `momentumPhase != .none`; the existing initialiser keeps its spelling
   (`isMomentum: true` sets `momentumPhase = .changed`), and a full initialiser
   `init(position:delta:modifiers:phase:momentumPhase:isPrecise:timestamp:)`
   is added. **`delta` stays points** (a non-precise device's lines × 10, as
   today on both platforms); `isPrecise` says which. **`location` is the
   pointer in the receiving element's local space** (render effects undone);
   at the seam and in `Window.onInput` it equals `position`. **Deltas are not
   transformed** by render effects (gpui's choice too): they are the device's
   motion.
2. **`.onScrollWheel(perform: @escaping @MainActor (ScrollEvent) -> Bool)`** on
   both vocabularies (`StyledElement` → `Self`, a `Handlers` member;
   `ProposalElementGroup` → `ScrollWheelModifier<Self>`). **MetalUI-only**:
   SwiftUI on macOS has no per-view wheel hook (census: `onScrollWheel` 0;
   what exists, `onScrollPhaseChange`/`onScrollGeometryChange`, observes a
   `ScrollView`). **`true` claims** the event; `false` passes it on. (The task
   text's `Bool?` is not taken: `nil` would mean nothing `false` does not.)
3. **Registration**: a non-opaque wheel region at the element's hit region,
   inside the disabled, `allowsHitTesting` and `hidden()` gates (an interaction
   handler, like `onClick` — unlike a `ScrollView`'s region, which stays
   outside the gates).
4. **Dispatch — one ranking, innermost first** (replacing `applyScroll`'s first
   lines, `DD-Y` preserved): the cover is `topmostHitbox(in:at:where:)` with
   "opaque, or carries a wheel handler" as eligibility. The chain is the
   cover's id and its ancestors (by `GlobalElementID.parent`); at each id,
   **innermost first**, the regions on the cover's layer containing the point
   with that id are consulted: **a wheel handler first** (called under
   `StateDispatch.dispatching(to:)` its element, with `location` made local to
   its region; claimed when it returns `true`), then that id's **scroll
   region** (scrolls, claimed — `DD-Y`), and at the cover only, a **multi-line
   text editor** (`TI-H`, claimed). Unclaimed after the chain: claimed if the
   cover was opaque (today's "stops here"), else not claimed (the window's
   `onInput` sees it). So an inner handler that claims stops an outer
   `ScrollView`; a handler outside a `ScrollView` sees only what the scroller
   left — which is nothing, since a scroller always claims (`DD-Y`); a legacy
   `.onScrollWheel` on a `ScrollView` itself (same id) runs **before** its
   scrolling and can veto it.
5. **Where**: still before the window's general `onInput` and after the menu,
   popover and context-menu stages; an open in-window menu takes the wheel
   (`MN-F`); a drawn alert takes it (`SV-J`).
6. **AppKit** fills `phase` from `NSEvent.phase`, `momentumPhase` from
   `NSEvent.momentumPhase`, `isPrecise` from `hasPreciseScrollingDeltas`.
   **SDL** fills `.none`, `.none`, `false` (SDL 3.4 has none of the three; the
   `SDLPlatform` doc comment and the divergence-free platform note say so).

**Evidence.** Census; gpui `ScrollWheelEvent`/`on_scroll_wheel` (comparison);
MetalCreator's use cases (viewport: zoom toward the cursor, momentum ignored —
`momentumPhase != .none` skips; canvas: pan with momentum, ⌘-scroll zooms —
`modifiers.contains(.command)`).

**Cost if wrong.** A handler outside a `ScrollView` that expected first look
gets none — the rule is stated in the modifier's doc and pinned (spec §4).

## CI-J — The seam: new events, one new requirement

**Ruling.**

1. **`InputEvent` gains** `.magnify(MagnifyEvent)` and `.rotate(RotateEvent)`
   beside `CI-E`'s four. `MagnifyEvent { position: Point<Pixels>;
   magnification: Double /* this event's additive delta */; phase: InputPhase;
   modifiers; timestamp: Double }`; `RotateEvent { position; rotation: Double
   /* this event's delta, degrees, clockwise-positive */; phase; modifiers;
   timestamp }`.
2. **`PlatformWindow.setPointerStyle(_:)`** is the one new requirement, with
   **no default**; `AppKitWindow`, `SDLWindow`, `FakePlatformWindow` and every
   compile-guard conformer template implement it; the migration note's spelling
   for an outside conformer is `func setPointerStyle(_ style:
   PlatformPointerStyle) {}`.
3. `MouseEvent.buttonNumber` and `ScrollEvent`'s four fields are **stored
   properties added to public types crossing a module boundary**: every lane
   runs `swift package clean` after the change lands (CLAUDE.md).
4. The fake's `simulateInput` keeps stamping a zero `ScrollEvent.timestamp`;
   it also sets `location = position` (as the platforms do).

**Cost if wrong.** An outside conformer fails to compile until it adds one
method — the migration note names it.

## CI-K — SDL: pinch, no rotate, cursors

**Ruling.**

1. **`SDL_EVENT_PINCH_BEGIN/UPDATE/END` → `.magnify`** with phase
   `.began`/`.changed`/`.ended`, flattened as a new appended kind
   `MUI_EVENT_PINCH` (the struct gains `float scale` and `int32_t phase` at its
   end). **The scale's meaning depends on the video driver** (read in SDL
   3.4.16's source, not measured on hardware): `cocoa` sends a per-event ratio
   (`1 + magnification`), so the delta is `scale − 1`; `x11` and `wayland` send
   the protocol's cumulative scale since the gesture began, so the delta is
   `scale − previous` (the previous starting at 1 on `BEGIN`). The rule lives
   once in a pure `SDLPinch.delta(scale:previous:cumulative:)` and the driver
   is read once per platform (`SDL_GetCurrentVideoDriver`). **Every other
   driver**, the offscreen one included, is taken as **cumulative** (SDL's
   documentation says "change since the last update"; its x11/wayland sources
   do otherwise — the cost line says what a wrong reading does).
2. **A pinch has no position in SDL**: the window uses its last pointer position
   (the last motion, button or wheel event it delivered); **a pinch with window
   id 0** (cocoa sends none) goes to the window with mouse focus
   (`SDL_GetMouseFocus`), else the keyboard-focused window, else is dropped.
3. **No rotate**: SDL 3.4 has no rotate event; `RotateGesture` never fires on
   SDL. **No pinch on Windows** (SDL 3.4.16's Windows driver sends none; a
   precision touchpad's pinch arrives as control+wheel — `CI-C` item 5).
4. **Cursors** as `CI-H` item 8; every SDL C enum `rawValue` is converted
   explicitly (`Int32` on Windows, `UInt32` on Apple); SDL test helpers creating
   an `SDLPlatform` arm `armMainRunLoopExitCheck()`; tests that need a
   presented window frame are gated on the offscreen driver as
   `SDLLifecycleTests.windowsPresentFrames` is (none of this branch's SDL tests
   needs a presented frame: they push events and read `onInput`).

**Cost if wrong.** A wrong cumulative/ratio reading on Linux makes a pinch
zoom far too fast or too slow — human check Y7 (Wayland or X11 trackpad).

## CI-L — Transforms, gates, presentations, viewports

**Ruling.** Every new path uses only `Hitbox.contains` and `Hitbox.localPoint`
(`GX-I`, `GX-P`): a rotated or scaled element's tap location, wheel location,
pinch start and pointer-style region follow its drawing. Every new region is
inside the disabled and `allowsHitTesting` gates and `hidden()`; a
presentation layer above wins the ranking and joins no ancestor below it
(`IX-Q`), so a popover blocks a canvas's wheel, pinch, style and button drags.
**`GPUSurface`/`MetalView` need nothing special**: they are proposal leaves,
and each new modifier wraps them as any `ProposalElementGroup` (the viewport
case; pinned in spec §4).

## CI-M — What does not move

**Ruling.** No `StateTable` slot (the seven reserved names unmoved: the arenas,
the pending context menu and the resolved style live on `Window`); no identity
change for existing trees (`.pointerStyle`/`.onScrollWheel` on `StyledElement`
return `Self`; their proposal wrappers add one level only where written); no
change to accessibility, focus, animation, `List` windowing, `Deferred`, text
input, or the primary press's dispatch; no shader change; the fourteen
offscreen demo images 0 px against `70ed000` (the canvas demo is a new
env-gated tree, in none of them); `DemoFrameDeterminismTests`' `Expected.swift`
unedited.

## CI-N — Tests and the headless harness

**Ruling.** `Window`-level tests drive `FakePlatformWindow.simulateInput` with
the new events against a rendered frame (no display, no sleeping; timers by
`simulateTick`); the arena's new modes are tested pure (`GestureArena` knows
only hitboxes and points); AppKit's overrides are driven with real `NSEvent`s
(the probe's CG gesture-field recipe for magnify/rotate, `NSEvent.mouseEvent`
and CG-made `otherMouse…` events, real scroll `CGEvent`s with phase fields) to
the host view; SDL's translation by pushing raw SDL events through the bridge
(`mui_push_raw_mouse_event` extended, a new `mui_push_pinch_event`) and reading
`onInput`. Every new typecheck guard is mutated red once. Performance: a frame
with no style or wheel region registers no extra hitbox and the pointer-style
recompute does no work (`pointerStyleVisits` 0), counted, never timed.

## CI-O — Lanes (three, disjoint files, order 1 → 2 → 3)

**Ruling.** Lane 1 — the seam and both platforms (`MetalUIPlatform`,
`MetalUIAppKit`, `Backends/SDL`, the test fakes and guard conformer
templates). Lane 2 — the gesture surface and the arena (`Gesture.swift`,
`GestureModifiers.swift`, a new `SpatialGestures.swift`), tested pure. Lane 3 —
`Window` integration, registration, wheel, pointer style, menus and the demo
(`Window.swift`, `Frame.swift`, `Handlers.swift`, `Hover.swift`,
`MenuSession.swift`, `Popover.swift`, `Tooltip.swift`, new `PointerStyle.swift`
and `ScrollWheel.swift`, the canvas demo), plus the docs registry rows and
human checks group Y. Files per lane: spec §2–§3.
