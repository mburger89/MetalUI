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
> negative of AppKit's `NSEvent.rotation` (probe `Q1`). **One addition (the
> critic, `CI-R`):** the right-click face menu's click point — `.contextMenu {
> (location: Point<Pixels>?) in … }`, the menu builder handed the press point in
> the element's local space (`nil` for a keyboard or accessibility open);
> SwiftUI has no located context menu, so this is MetalUI-only.

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

Prefix **`CI-`**, lettered. **Next unused: `CI-AJ`.** (This line moves in the
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
  (MetalUI's own controls declare no style yet; what SwiftUI shows there is
  unprobed — `CI-U` item 2) — text
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
is additive over a spelling built here, except `CoordinateSpace.named(_:)` and
an image cursor, each of which adds an enum case (`CI-AC`).

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
   where the content-space point is (60, 40) (probe `T2`): a 32-point offset
   (title bar or hosting inset — not separated; narrowed by `CI-U` item 1);
   MetalUI's `.global` is the content view's space (a window's content is its
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
   element. MetalUI's rule (`CI-U` item 3), not a measured AppKit behaviour.
7. **When**: recomputed where hover is (`Window.updateHover`'s call sites —
   every pointer event and after every adopted frame), and the platform is
   called **only on a change**. While an in-window menu or a drawn alert is up
   the style is `.default` (`SV-N` item 6's rule). `.pointerExited` forgets
   the last-sent style, so the first pointer event after it re-sends (`CI-S`
   supersedes this item's earlier "no call owed").
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
   `momentumPhase != .none` (with a setter, `CI-V` item 1); the existing initialiser keeps its spelling
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
   scrolling and can veto it. **Amended by `CI-AH` item 1**: no spelling gives
   a handler the scroller's id — a handler on or around a `ScrollView` sees
   nothing over it; a handler on its **content** runs first and can veto.
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

## CI-O — Lanes (three, disjoint files, order 1 → 2 → 3) — re-cut by `CI-W`

**Ruling.** Lane 1 — the seam and both platforms (`MetalUIPlatform`,
`MetalUIAppKit`, `Backends/SDL`, the test fakes and guard conformer
templates). Lane 2 — the gesture surface and the arena (`Gesture.swift`,
`GestureModifiers.swift`, a new `SpatialGestures.swift`), tested pure. Lane 3 —
`Window` integration, registration, wheel, pointer style, menus and the demo
(`Window.swift`, `Frame.swift`, `Handlers.swift`, `Hover.swift`,
`MenuSession.swift`, `Popover.swift`, `Tooltip.swift`, new `PointerStyle.swift`
and `ScrollWheel.swift`, the canvas demo), plus the docs registry rows and
human checks group Y. Files per lane: spec §2–§3.

---

The rulings below are the **critic's** (2026-10-07, after `f39e14d`). Each
corrects or extends one above; where they disagree, the later ruling wins and
the spec carries the amendment.

## CI-P — The probe re-run, and the cursor mappings it had not measured

**Ruling.**

1. **Re-run**: the probe's 50 recorded lines re-read **byte for byte**, twice,
   on the same machine and toolchain with the screen **unlocked** (recorded
   locked) — every `T`, `R`, `M`, `Q`, `P`, `C` answer above stands.
2. `CI-H` item 8 named AppKit mappings P1–P10 never measured. New arms
   **P15–P19** (appended; read through a separate `cursorNameWide` so no earlier
   line can move; 61 lines, twice byte-identical): `verticalText` →
   `iBeamCursorForVerticalLayout`, `zoomOut` → `zoomOut`, and every
   `frameResize(position:)` reads the natural AppKit position (`leading` →
   `.left`, `topLeading` → `.topLeft`, …). **But `NSCursor ==` compares images**:
   with `.all` a position equals its opposite (`top` == `bottom`, `topLeft` ==
   `bottomRight`), and `(trailing, .inward)` == `(leading, .outward)`.
3. Therefore **test 1.8 pins the frame-resize table as values**, not cursors:
   the AppKit side exposes a pure `AppKitCursor.frameResize(for:) ->
   (NSCursor.FrameResizePosition, NSCursor.FrameResizeDirection.Set)` that
   `setPointerStyle` uses, and 1.8 compares those values for all eight edges
   and the three direction sets; the other kinds are still compared as cursors
   (each distinct). Mutation (added): swap `top`/`bottom` in the table → 1.8
   red (a cursor comparison would stay green — that is the defect this item
   fixes).

**Evidence.** Probe header "RE-RUN 2026-10-07" and arms P15–P19.

## CI-Q — `Handlers` has seventeen members and a size pin; one box, not two members

**Ruling.** Spec §1.3's "sixteen → eighteen, two members" is wrong twice:
`Handlers` already has **seventeen** members (`hover`, `SV-AH` corrected
`SV-N`'s "sixteen"; CLAUDE.md's "sixteen" is stale and the Record phase fixes
it), and `MemoryLayout<Handlers>.size` is pinned at **472** by
`handlersGainsOneReferenceMember` (`ContextMenuTests`, exact) and
`theNewDeclarationsCostHandlersAtMostOnePointer` (`AccessibilityModifierTests`,
`<= 440 + 8 + 8 + 8 + 8`) for `IX-N`'s Windows stack budget — an inline closure
(16 bytes) plus an optional `PointerStyle` would break both.

So the wheel handler and the style ride **one class box**,
`PointerAttachment` (`final class`, `let scrollWheel: (@MainActor
(ScrollEvent) -> Bool)?`, `let style: PointerStyle?`; a later `.onScrollWheel`
or `.pointerStyle` replaces its own field and keeps the other, as
`ContextualAttachment` does — **amended by `CI-AH` item 2**: a later
`.pointerStyle` keeps an existing style, the first written being the inner), the **eighteenth** member `pointer:
PointerAttachment?`. Size **472 → 480**: lane 3 edits both pins (`== 480` and
`<= 440 + 8 × 5`) with a doc line naming this ruling, and their mutation becomes
"store the closure inline". `HandlerShape` and `HandlerFingerprint` each gain
**one** field.

**Cost if wrong.** None to callers (internal storage).

## CI-R — A located context menu (MetalCreator's face menu)

**Ruling.**

1. MetalCreator's C7 item 4 needs "the click point in local coordinates" for
   **the right-click face menu**. The design had no way to read it: a
   `DragGesture(minimumDistance: 0, button: .secondary)` activates on the press
   and so cancels the pending menu (`CI-F` item 4), and `.contextMenu`'s builder
   takes no argument.
2. **`.contextMenu(menuItems: @escaping @MainActor (Point<Pixels>?) -> M)`**
   (`@MenuContentBuilder`), on both vocabularies beside the existing overload,
   selected by the closure's arity (guard 2.25). **MetalUI-only**: SwiftUI's
   macOS interface has seven `contextMenu` signatures and none passes a
   location (census re-taken by the critic, recorded in the probe header).
3. The point is the **secondary press's** position in the contextual region's
   local space (`Hitbox.localPoint`, so render effects are undone), whether the
   menu opens on the press or, deferred, on the release (`CI-F` item 4 — the
   press point, not the release). **`nil`** when the menu opens from the
   keyboard (`MN-G`) or an accessibility show-menu (C11): there is no pointer.
4. Storage: `ContextualAttachment.menu` becomes `(@MainActor (Point<Pixels>?)
   -> MenuItems)?`; the location-less overload ignores its argument. No new
   `Handlers` member, no size change.
5. Lane 2 owns it (`ContextMenu.swift`, `MenuSession.swift`; `CI-W`). Tests
   2.21–2.25 (spec §4.2).

**Cost if wrong.** If SwiftUI grows a located menu, MetalUI adds its spelling
beside this one.

## CI-S — A pointer exit forgets the style it sent

**Ruling.** `CI-H` item 7 reset the resolved style to `.default` on
`.pointerExited` "without a platform call owed afterwards". On SDL the cursor
is **process-global** (`SDL_SetCursor`): it survives leaving the window and
comes back on re-entry, so after an exit over a `.rectSelection` region and a
re-entry over a default region the window would compute `.default` == the
recorded `.default` and send nothing — the crosshair would stick (and with two
SDL windows, one window's style would show over the other). **So an exit sets
the last-sent style to unknown (`nil`), and the first pointer event after it
sends the resolved style unconditionally** — one platform call per entry, on
every platform. Test 3.23 becomes
`aPointerReEntryResendsTheStyleEvenWhenItIsDefault`: crosshair region, exit,
re-enter over a default region → the fake records `.arrow` again. Mutation: on
exit set the last-sent style to `.default` → red.

## CI-T — The AppKit control-drag test changes on purpose

**Ruling.** `CI-E` item 3 turns a control-press's drag into
`.rightMouseDragged`. The existing `aRightMouseDownAndAControlClickReachOnInputAsRightMouseDown`
(`AppKitMenuTests` 2.4, `MN-AC` item 1) pins that drag **dropped**; lane 1
edits it (its log gains the control-drag as a secondary drag, its doc names
this ruling), and `Tests/MetalUITests/AppKitMenuTests.swift` joins lane 1's
files. A reddening there under lane 1's change is the migration, not a
regression — the lane records it.

## CI-U — Claims the probe did not make, struck or narrowed

**Ruling.**

1. **Divergence 139** (`CI-B` item 4) says SwiftUI's `.global` "includes the
   title bar". The probe measured only that `.global` read **32 points lower**
   than the content-view point (T2 (60, 72) vs (60, 40)); whether the offset is
   the title bar or the hosting view's top inset was not separated. The row
   states the measured offset and nothing more.
2. `CI-A`'s deferral says SwiftUI **shows an I-beam over `TextField`** and **a
   pointing hand over `Link`**. Unprobed: struck. The deferral stands as
   MetalUI's (its controls declare no style on this branch), and lane 3 adds a
   **"Not offered — documented absences"** row in `docs/divergences.md` for it
   and for the other `CI-A` deferrals that are SwiftUI API
   (`PointerStyle.image`/`.shape`/`columnResize(directions:)`/`rowResize(directions:)`,
   `onModifierKeysChanged`, `CoordinateSpace.named`/`.coordinateSpace(_:)`,
   gesture `time`/`velocity`/`predictedEnd*`, `inputKinds:`).
3. `CI-H` item 6 justifies holding the pressed target's style by "AppKit's
   behaviour of not running cursor updates during a mouse drag". Unmeasured:
   it is **MetalUI's rule**, kept for MetalCreator's fast pan; human check Y5
   looks.

## CI-V — Smaller spec corrections

**Ruling.**

1. **`ScrollEvent.isMomentum` keeps a setter** (computed `get` = `momentumPhase
   != .none`; `set` true → `.changed` unless already non-`.none`, false →
   `.none`), so assigning it still compiles; migration note §8.1 item 5 is
   struck. Test 1.3 gains the setter arm.
2. **A proposal `.onScrollWheel` on a `ScrollView`** wraps it in its own
   identity level, the scroller's **parent**, so in `CI-I` item 4's chain it
   runs **after** the scroller, which always claims: it sees nothing. Only the
   legacy (same-id) spelling can veto scrolling (test 3.6). The modifier's doc
   says so and test 3.5 gains that arm (mutation: consult a wrapper's handler
   before its child's scroll region → the arm reddens).
3. **The demo drops "`.grabIdle` while ⌥ is held"**: with no modifier-change
   hook (`onModifierKeysChanged` deferred), a ⌥ press without a pointer move
   cannot change a style. `.grabIdle` shows over the canvas's pan strip instead.
4. **A pinch event of phase `.ended`/`.cancelled` with no live pinch arena is
   dropped** (`CI-D` item 1 formed an arena on "any phase").

## CI-W — Lanes re-cut (amends `CI-O`)

**Ruling.** `CI-O`'s lane 3 held 36 tests, both arenas' window integration,
the wheel, the pointer style, the menus, the demo and every registry — too
large for one agent, while lane 2 was pure. Re-cut, still **1 → 2 → 3**, one
agent at a time in one worktree:

- **Lane 1 — seam and platforms**: unchanged, plus `AppKitMenuTests.swift`
  (`CI-T`) and the frame-resize value table (`CI-P`).
- **Lane 2 — gestures end to end**: the surface and the arena (old 2.x), **and
  their `Window` integration** — tap location on both vocabularies, the pinch
  arena, the button arena, the context menu's deferral and the located menu
  (`CI-R`), the menu/popover/tooltip handling of the new events: old tests 3.1,
  3.26–3.34 move here (ids kept) with 2.21–2.25.
- **Lane 3 — wheel, pointer style, demo, registries**: `CI-I`, `CI-H`, `CI-Q`,
  `CI-S`, the canvas demo, divergences 139–141 and the Not-offered rows, the
  inventory and census, human checks Y.

`Window.swift` is named in lanes 2 and 3: lane 2 edits the press, pinch and
menu stages, lane 3 the wheel stage and the hover/style recompute, on top of
lane 2's commit. Sequential lanes make the overlap safe; no lane runs beside
another.

## CI-X — Lane 1's implementation choices (the seam and both platforms)

**Ruling.**

1. **The SDL right-drag changes an existing SDL test on purpose.** `CI-E` item
   4 makes motion with only the right button held `.rightMouseDragged`; the
   existing `aRightButtonEventBecomesARightMouseDownAndUp`
   (`Backends/SDL/Tests/MetalUISDLTests/SDLMenuInputTests.swift`, S3.1, `MN-B`
   item 3) pinned it as `.mouseMoved`. Lane 1 edits it (`rdrag(35,45)`, its doc
   names this item) — `CI-T`'s shape for SDL; the file joins lane 1's list.
   **Owed to lane 2** (`CI-E` item 2): `Window`'s switches send the six new
   cases to `default:`, so until lane 2 a right- or other-button drag does not
   recompute hover (on SDL a right-held move did before this branch). No test
   pins hover during a right drag; lane 2's button arena adds the hover
   recompute for the new drag cases.
2. **macOS 14 fallbacks.** The package's minimum is macOS 14; `NSCursor`'s
   `columnResize`, `rowResize`, `zoomIn`, `zoomOut` and
   `frameResize(position:directions:)` are macOS 15. On 14 `AppKitCursor`
   answers `resizeLeftRight`/`resizeUpDown` for the column and row resizes and
   for the four edges (a one-way `resizeLeft`…`resizeDown` when one direction
   is asked), and the arrow for the zooms and the four corners.
   `AppKitCursor.frameResize(for:inward:outward:)` (`CI-P` item 3's value
   table) is `@available(macOS 15, *)`; test 1.8 runs on 15 and later (the
   development machine is macOS 27; a 14 runner returns from it).
3. **A frame resize with neither direction** (`inward: false, outward:
   false`) is both, `.all` — SwiftUI's empty `FrameResizeDirection.Set` has no
   cursor of its own and lane 3 never sends one.
4. **The SDL cursor cache lives in the bridge**: `mui_set_system_cursor(int32_t)`
   takes a bridge-defined `MUI_CURSOR_*` (MetalUI's names, mapped to
   `SDL_SystemCursor` in C), creates each kind once and keeps it for the
   process; `SDLSystemCursor.bridgeValue` converts each constant with
   `Int32(…)` explicitly, so Swift never spells an SDL enum's `rawValue`.
   `SDLPinch`, `SDLSystemCursor` and `SDLCursorTable` are **internal** (no
   public surface beyond `SDLWindow.setPointerStyle`).
5. **Test 1.13's driver.** On macOS the SDL tests run under `cocoa`, a ratio
   driver, so the test first requires the platform read the real driver as
   `SDLPinch.isCumulative(driver:)` says, then sets the platform's reading
   (`SDLPlatform.pinchIsCumulative`, internal) to the offscreen driver's; in
   CI's Linux image the driver is `offscreen` and the override is a no-op. A
   pinch's BEGIN and END carry magnification 0 (AppKit's began/ended events
   do, probe `M0`), and the window's last pointer position is updated by every
   motion, button and wheel event it receives.
6. **The pinch's keyboard-focus fallback** (`CI-K` item 2) is the platform's
   tracked focus (`EV-AF`), not `SDL_GetKeyboardFocus`, which a pushed focus
   event does not update.

**Cost if wrong.** Item 1: a hover that lags a right drag on SDL until lane 2
lands (no released build carries the gap). Item 2: a macOS 14 user sees an
arrow where a zoom or corner cursor was asked.

## CI-Y — Lane 1's verification: every mutation of spec §4.1 reddens its named test

**Ruling.** Lane 1 (commits `77a7b90` red, `04e6be1` implementation) is
verified as follows; nothing in the design changed.

1. **Red** (`77a7b90`): the root test targets did not compile — `ScrollEvent`
   had no `momentumPhase`/`phase`/`isPrecise`/`location`, `MouseEvent` no
   `buttonNumber`, no `rightMouseDragged`/`otherMouseDown`/`magnify`/`rotate`
   cases, no `AppKitCursor`, `PlatformPointerStyle`, `PlatformResizeEdge`,
   `setPointerStyle`; `Backends/SDL`'s `SDLMenuInputTests`: "type
   'InputEvent' has no member 'rightMouseDragged'".
2. **Counts** after `swift package clean`, native build, unfiltered
   `--no-parallel`: **2683 tests in 3 suites passed** (2672 + 11: tests
   1.3–1.10, 1.19, guards 1.1, 1.2), `FR-J no-argument frame:
   succeeded=true`, 0 `error:`, the only `warning:` SwiftPM's deprecation
   notice; both guards ran (their `CI-E six cases:`/`CI-J member required:`
   lines printed). `swift build --build-tests` (default build system): 0
   warnings. `Backends/SDL` on macOS (`--print-flags`): **24 + 91** (83 + 8);
   in CI's Linux image (`offscreen`): **24 + 88** (80 + 8), every lane 1 SDL
   test running; warnings unchanged (Homebrew's `ld` deployment target, the
   pre-existing unnecessary `try` at `AccessKitControlsParityTests.swift:83`).
   `swift:6.4-noble` root `swift build --build-tests`: complete, 0 warnings;
   its portable tests 199 + 22 + 35 + 49 + 18 + 6 passed.
3. **Demo pixels** (`compare.sh <scratch> 70ed000 HEAD` at `04e6be1`): **0
   differing pixels, scene identical, in all fourteen images**; controls as
   recorded (default vs modal 1031003, default vs animation 454895, as at
   `70ed000`'s own run). `MetalUIScene`, `MetalUILayout`, both shaders and
   `Expected.swift` untouched.
4. **Mutations**, each on `04e6be1`'s spelling, one full unfiltered suite
   each (root: native `--no-parallel`; SDL: `swift test $(… --print-flags)`),
   `git status --short` clean after each:

   | # | Mutation (spelling) | Reddened |
   | --- | --- | --- |
   | G1.1 | delete `case otherMouseDragged(MouseEvent)` from `InputEvent` | `anExhaustiveInputEventSwitchWithoutTheInputAPICasesDoesNotCompile` ("with" arm: "type 'InputEvent' has no member 'otherMouseDragged'") |
   | G1.2 | `extension PlatformWindow { public func setPointerStyle(_ style: PlatformPointerStyle) {} }` above the protocol | `aPlatformWindowWithoutSetPointerStyleDoesNotCompile` |
   | 1.3a | the old init passes `momentumPhase: .none` | `theOldScrollEventInitialiserKeepsItsMeaning` |
   | 1.3b | the `isMomentum` setter ignores `false` | `theOldScrollEventInitialiserKeepsItsMeaning` |
   | 1.4 | `momentumPhase: Self.inputPhase(event.phase)` | `appKitScrollWheelCarriesPhaseMomentumAndPrecision` |
   | 1.5 | `rotation: Double(event.rotation)` (no negation) | `appKitMagnifyAndRotateReachOnInputWithDeltasAndPhases` |
   | 1.6 | `otherMouseDragged(with:)` calls `super` | `appKitOtherButtonsAndRightDragReachOnInput` |
   | 1.7 | the control-drag branch only `return`s | `aControlDragOnAppKitIsASecondaryDrag`, `aRightMouseDownAndAControlClickReachOnInputAsRightMouseDown` (2.4) |
   | 1.8a | `openHand`/`closedHand` swapped | `appKitPointerStylesMapAsTheProbeMeasured`, `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt` |
   | 1.8b | `.top`/`.bottom` swapped in `frameResize(for:)` | `appKitPointerStylesMapAsTheProbeMeasured` |
   | 1.9 | `cursorUpdate(with:)` sets `NSCursor.arrow` | `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt` |
   | 1.10 | `.cursorUpdate` dropped from the tracking options | `theHostViewsTrackingAreaRequestsCursorUpdates` |
   | 1.19 | the fake's `scroll.location = scroll.position` deleted | `theFakeWindowRecordsPointerStylesAndStampsScrollLocation` |
   | 1.11 | X1 → 4 in `SDLButtons.appKitNumber` | `sdlMiddleAndExtraButtonsBecomeOtherMouseEventsWithAppKitNumbers`, `sdlMotionWithRightOrMiddleHeldIsARightOrOtherDrag` |
   | 1.12 | `SDL_BUTTON_RMASK` tested before `LMASK` (`SDLBridge.c`) | `sdlMotionWithRightOrMiddleHeldIsARightOrOtherDrag` |
   | 1.13 | `SDLPinch.delta` always `scale - 1` | `sdlPinchBecomesMagnifyAtTheLastPointerPosition`, `sdlPinchDeltaIsARatioOnCocoaAndCumulativeElsewhere` |
   | 1.14 | the two branches of `SDLPinch.delta` swapped | the same two |
   | 1.15 | `SDLPinch.route` prefers the keyboard focus | `aPinchWithNoWindowGoesToTheMouseFocusThenTheKeyboardFocus` |
   | 1.16 | the SDL wheel `isPrecise: true` | `sdlWheelHasNoPhaseMomentumOrPrecision` |
   | 1.17 | `openHand` → `.default` | `sdlPointerStylesMapToSystemCursorsAndAreRecorded` |
   | 1.18 | `MUI_EVENT_PINCH` moved before `MUI_EVENT_DIALOG` | `theNewBridgeKindsAreAppendedAfterMouseLeave` |

5. **The guard 1.1 instrument.** Deleting the case breaks the package's own
   producers (`AppKitPlatform`, the tests), so G1.1 rebuilt only the
   `MetalUIPlatform` target (`swift build --build-system native --target
   MetalUIPlatform`) and ran the full suite with `--skip-build`: the guard
   typechecks against the freshly built module, every other test against the
   unmutated binary. The first G1.2 spelling, inserted between `@MainActor`
   and `public protocol PlatformWindow`, stripped the protocol's isolation and
   failed to build ("conformance … crosses into main actor-isolated code") —
   an instrument error, re-run with the extension above the attribute.

**Cost if wrong.** None in shipped behaviour: this ruling records evidence.
A Record phase that copies these counts re-takes them after lanes 2 and 3.


## CI-Z — The drawn menu and the tooltip take the new drags now; five pins (amends `CI-X` item 1)

**Ruling.** Lane 1's review found that `CI-E` item 4 (SDL motion with only the
right button held is `.rightMouseDragged`, no longer `.mouseMoved`) broke a
shipped path `CI-X` item 1 did not name, and that five documented seam
behaviours had no pin. Fixed in lane 1, red first:

1. **The drawn menu's press-drag-release (`MN-F` item 3) on SDL.**
   `Window.dispatchMenuSession` handled only `.mouseMoved`/`.mouseDragged` as a
   move, so on SDL the right press that opened the menu, dragged to a row and
   released there highlighted nothing, never set `openingPress.moved`, and the
   release counted as "the opening release with no move": nothing chosen, the
   menu left open (measured by the reviewer at `c90e59f`; the existing pin
   `aClickOrAPressDragReleaseOnAnItemChoosesIt` feeds `.mouseMoved`, which SDL
   no longer sends during a right drag). The menu stage's move arm now takes
   `.rightMouseDragged` and `.otherMouseDragged` too (it already took every
   pointer event while open, `MN-F` item 3). Pin:
   `aPressRightDragReleaseOnAnItemChoosesItAndAnOtherDragHighlights`
   (`ContextMenuTests`). `CI-X` item 1's "owed to lane 2" is amended: the
   hover recompute for the new drags is still lane 2's; **the menu's move arm
   is no longer owed**. Lane 3 still owes the rest of spec §1.4 item 3
   (`.otherMouseDown` outside dismissing, `.otherMouseUp`, `.magnify`,
   `.rotate` taken; test 3.31).
2. **The tooltip** (`MN-P` item 2) tracked only `.mouseMoved`/`.mouseDragged`:
   a right drag out of a `.help` region went unseen (on SDL it was seen before
   `CI-E`), so the region stayed spent and the tooltip never returned.
   `trackTooltip` now tracks `.rightMouseDragged`/`.otherMouseDragged` as
   moves and hides on `.otherMouseDown` (spec §1.4 item 2's first clause,
   landed here because the same test covers it). Pin:
   `aRightOrOtherDragOutOfTheRegionLetsTheTooltipReturn` (both buttons).
   Hiding on `.magnify`/`.rotate` stays lane 3's.
3. **SDL's mouse focus is substitutable.** A pushed SDL event cannot move SDL's
   own mouse focus, so the pinch dispatcher's routing (`CI-K` item 2) was
   pinned only through the pure `SDLPinch.route`. `SDLPlatform` gains an
   internal `mouseFocusWindowID: () -> UInt32` (default
   `mui_mouse_focus_window_id()`), read where a pinch names no window. No
   public surface, no requirement.
4. **The five pins.** Each was a mutation that left the full suite green in
   review (R2a, R2b, R3, S1, S2); each now reddens a named test (item 5):
   - R3: `appKitBackAndForwardButtonsCarryTheirButtonNumbers` — CG-made back
     and forward `otherMouseDown/Up` (button numbers 3, 4, required on the
     `NSEvent`s) carry 3 and 4.
   - R2a/R2b: `appKitScrollPhasesCancelledStationaryAndMayBeginMap`
     (`PlatformTests`) — real scroll `CGEvent`s with `CGScrollPhase` 8 and 128
     arrive `.cancelled` and `.mayBegin`; `.stationary`, which CG cannot set
     on a scroll event, is pinned through the pure
     `MetalHostView.inputPhase` table (a `.changed` step).
   - S1: `sdlPinchPreviousScaleResetsAtEveryGestureEdge` — an update after
     an END and a BEGIN with no END between are each measured from 1.
   - S2: `aPinchNamingNoWindowReachesTheMouseFocusWindowThroughTheDispatcher`
     — two windows; a window-0 pinch reaches whichever has mouse focus.
5. **R1 is unpinned, by name.** `AppKitWindow.setPointerStyle` setting the
   cursor at once while the pointer is inside the view needs a real pointer
   inside a real window — no agent can drive it. It joins the human checks
   as **Y12** (spec §7): with the pointer resting over the demo canvas, a
   keyboard-driven style change (no pointer motion) shows the new cursor at
   once. The Record phase copies Y12 into `docs/verification/human-checks.md`
   with Y1–Y11.

6. **Red and mutations.** Red at the test commit's working tree (before the
   fix): the menu pin failed four expectations (nothing chosen, the menu open,
   the other drag not taken, nothing highlighted); the tooltip pin failed on
   both arguments (right: never returned; other: the press did not hide it).
   The five pins of item 4 are green on arrival by design (they pin shipped
   behaviour) and were proved by mutation. Each mutation was applied to
   `7157e67`'s spelling, one full unfiltered suite each (root: native
   `--no-parallel`, every run 2687 tests; SDL: `swift test $(…
   --print-flags)`, 24 + 93), the source restored from a copy, `git status
   --short` clean after each:

   | # | Mutation (spelling) | Reddened |
   | --- | --- | --- |
   | MZ1 | the menu stage's move arm back to `.mouseMoved`/`.mouseDragged` only | `aPressRightDragReleaseOnAnItemChoosesItAndAnOtherDragHighlights` |
   | MZ2a | `trackTooltip`'s move arm without the two drags | `aRightOrOtherDragOutOfTheRegionLetsTheTooltipReturn` |
   | MZ2b | `.otherMouseDown` dropped from `trackTooltip`'s hide arm | `aRightOrOtherDragOutOfTheRegionLetsTheTooltipReturn` |
   | R3 | `otherMouseDown(with:)` passes `button: 2` | `appKitBackAndForwardButtonsCarryTheirButtonNumbers` |
   | R2a | the `.cancelled` line deleted from `inputPhase` | `appKitScrollPhasesCancelledStationaryAndMayBeginMap` |
   | R2b | `\|\| phase.contains(.stationary)` deleted | `appKitScrollPhasesCancelledStationaryAndMayBeginMap` |
   | R2c | `.mayBegin` answers `.none` | `appKitScrollPhasesCancelledStationaryAndMayBeginMap` |
   | S1a | the END arm's `pinchPreviousScale = 1` deleted | `sdlPinchPreviousScaleResetsAtEveryGestureEdge` |
   | S1b | the BEGIN arm's `pinchPreviousScale = 1` deleted | `sdlPinchPreviousScaleResetsAtEveryGestureEdge` |
   | S2 | the dispatcher passes `mouseFocus: 0` | `aPinchNamingNoWindowReachesTheMouseFocusWindowThroughTheDispatcher` |

   (S1a, S1b and S2 ran on the uncommitted tree that became `7157e67`, before
   the menu/tooltip fix, which `Backends/SDL`'s tests do not reach.)
7. **Counts** at `7157e67` (unmutated): root native unfiltered
   `--no-parallel` **2687 tests in 3 suites passed** (2683 + 4), `FR-J
   no-argument frame: succeeded=true`, 0 `error:`, the only `warning:`
   SwiftPM's deprecation notice; `swift build --build-tests` 0 warnings;
   `Backends/SDL` on macOS **24 + 93** (91 + 2); CI's Linux image
   (`offscreen`) **24 + 90** (88 + 2), both new SDL tests running there,
   warnings unchanged (the pre-existing `AccessKitControlsParityTests.swift:83`).

**Cost if wrong.** Item 1: a drawn menu on SDL that cannot be chosen from by
press-drag-release — the regression this closes. Item 3: none in shipped
behaviour (the default is the old call).

## CI-AA — Lane 2's implementation choices (gestures end to end)

**Ruling.** Lane 2 (commits `179c65a` red, and the implementation after it)
built spec §1.2, the located menu (`CI-R`) and the press, pinch,
button-arena and context-menu stages of §1.4 as designed, with these
choices, none of which renames a provisional name (**MetalCreator: every
name in the header stands**):

1. **A press arena with no live gesture leaf is no arena.** `GestureArena.init?`
   answers `nil` when, after the mode's formation failures, no gesture leaf is
   live — for `.press` too, so a press on an element carrying only a
   `MagnifyGesture` (and perhaps an `onClick`) is `dispatchClick`'s exactly.
   For every tree that existed before this branch the condition is the old
   one ("no member"), since no leaf was failed at formation.
2. **The pinch arena's order is per kind.** A pinch leaf is held off only by a
   leaf **of its own kind** ahead of it that has not failed, and an exclusive
   member that ended cancels only leaves of the kinds that ended in it — so an
   inner magnify that ends cancels no outer rotate (test 2.17's second arm).
   A `.began` re-begins its kind's still-possible leaves (start point, anchor
   and Σ reset); an `.ended`/`.cancelled` of a kind that is not active is
   ignored; the arena dies when every begun kind has ended. A leaf that
   ended stays ended: a second magnify begun in the same arena while a rotate
   is still alive reaches only magnify leaves that never ended (corner, no
   pin; human check Y4 looks at nested pinches).
3. **`startAnchor` divides by the registered hit region's size** — the
   hitbox's bounds, clipped and content-shape-inset, as every hit region is —
   and is 0 on an empty axis.
4. **The button arena** is one at a time: a second button pressed while one
   button's arena is alive is ignored (not claimed, it passes on), and only
   the arena's own button's drags and release reach it. `activatedAnyDrag` is
   "some drag leaf reached its minimum" (`started`), whether or not it has
   reported yet — a secondary drag held off by an exclusive member ahead still
   cancels the pending menu. The context-menu stage's deferral check forms the
   button arena once more (`secondaryDragIsDeclared(at:)`, one extra formation
   per right press over a menu); the deferred menu opens through
   `openPendingContextMenu` with `openingPress: false` (its release has
   happened, so press-drag-release does not apply). A `minimumDistance: 0`
   secondary drag activates at the press, so the menu never opens (`CI-R`
   item 1).
5. **Owed items taken here.** The hover recompute for `.rightMouseDragged` and
   the three other-button events (`CI-X` item 1, `CI-Z` item 1) and their
   `lastMousePosition` update (`updatePointerState`; `active` never moves) land
   in lane 2; `.magnify`/`.rotate` move neither and their hover/style recompute
   stays lane 3's (the style stage). **The tooltip's hide on `.magnify` and
   `.rotate`** (`CI-Z` item 2 left it to lane 3) lands here, `Tooltip.swift`
   being lane 2's file, with a pin of its own: test **3.31b**
   `aMagnifyOrARotateHidesTheTooltip` (one more test than spec §4's list).
6. **The in-window menu's other button.** An `.otherMouseDown` the open drawn
   menu takes sets `Window.menuClaimsOtherRelease`, so its release is claimed
   too, also after an outside press dismissed the menu; `.magnify`/`.rotate`
   are taken while it is open. A popover's outside other press dismisses and
   **always passes on** — an other press clicks nothing, so an anchor has no
   release to consume (`MN-Y` item 2 is the primary and secondary buttons').
7. **Placement.** The pinch and button stages run directly after
   `applyScroll` (lane 3 replaces that call with the wheel chain; the two
   stages stay after it) and before text input — so the primary-only stages
   below never see the new events.
8. **Storage.** `ContextualAttachment`'s designated initialiser is
   `init(locatedMenu:help:)`; a convenience `init(menu:help:)` wraps a
   location-less builder, so `PullDownMenu.swift` needs no edit (a nil
   argument would make two same-labelled initialisers ambiguous, hence the
   label).
9. **Inventory.** Two families until lane 3: `input-apis-gestures` (class A,
   probe arm `T1`, test 2.3: the three gestures, `CoordinateSpace`, the located
   `onTapGesture`) and `input-apis-gestures-metalui` (class M: `MouseButton`,
   `DragGesture`'s `button`/`coordinateSpace`/new initialiser,
   `DragGesture.Value.modifiers` and its initialiser, the located
   `contextMenu`). **Lane 3 moves `CoordinateSpace.global` and
   `Value.modifiers` to class-D families when it writes divergences 139 and
   140** — a D family naming a label `docs/divergences.md` does not list yet
   fails the check's `LIVE` rule, so lane 2 cannot.
10. **A fixture note.** A context-menu-only element has no opaque hitbox (its
    region is non-opaque, `MN-Q`), so 2.21 requires the contextual region's
    bounds rather than an opaque target's.

**Cost if wrong.** Item 2: if SwiftUI lets an ended magnify cancel an outer
rotate, MetalUI's outer rotate keeps reporting after the inner magnify ends
(Y4 looks). Item 4: a two-button chord drags with the first button only.


## CI-AB — A stale button or pinch arena is replaced, not fed (amends `CI-AA` items 2 and 4)

**Finding (the second critic, reading lane 2's `Window.buttonPress` and
`GestureArena.pinch`).** Both arenas live until their own end event. When that
event is lost — the release of a middle drag while a modal panel or a native
menu takes the pointer, or the app deactivates mid-drag; a pinch's `.ended`
when the window resigns key mid-gesture — the arena never dies:

- `buttonPress` is guarded by `buttonArena == nil`, so the **next press of the
  same button is ignored**; its drags feed the stale arena (same button
  number) with the old start location, so MetalCreator's next middle-drag pan
  jumps by the distance between the two presses, and its release ends the
  stale drag. A deferred context menu parked by that press
  (`pendingContextMenu`) is then opened or dropped by the stale arena's
  `activatedAnyDrag`, not its own.
- `pinch(_:delta:phase:at:)` treats a `.began` of a kind already active as a
  re-begin of **the old arena's** leaves, so the next pinch, made over another
  element, zooms the element the lost pinch began on.

The primary arena has no such hole: a non-continuing `.mouseDown` sets
`gestureArena = nil` and forms anew.

**Ruling.**

1. **A press of the button arena's own button while that arena is alive means
   its release was lost**: the stale arena is dropped **silently** (no
   `onEnded`, as the primary press's re-formation drops one) and the press
   forms a new arena from the one ranking. A press of a **different** button
   while an arena is alive is still ignored (`CI-AA` item 4 unchanged).
2. **A `.began` of a pinch kind the pinch arena already holds active means its
   end was lost**: the stale arena is dropped silently and the event forms a
   new pinch arena at **its own** position (`CI-D`). A `.began` of a kind not
   active in the arena (a rotate beginning beside a live magnify) keeps
   `CI-AA` item 2's behaviour. A `.changed` with no arena still forms one, as
   now (`CI-V` item 4).
3. **Pins (lane A, red first):**
   - **2.26** `aSecondPressOfTheArenasOwnButtonReplacesAStaleArena`: two
     sibling elements each with `DragGesture(minimumDistance: 0, button:
     .middle)`; middle press and drag on A, **no release**; middle press and
     drag on B → B's `onChanged` reports B-local translation from B's press,
     A reports nothing more and no `onEnded`. Mutation: restore the `guard
     buttonArena == nil` → red.
   - **2.27** `aBeganOfAnActivePinchKindReformsTheArenaUnderTheEvent`: A and B
     each with `MagnifyGesture`; `.began`/`.changed` over A, **no end**;
     `.began`/`.changed` over B → B reports, A reports nothing more.
     Mutation: re-begin the old arena's leaves on `.began` → red.
   - **2.28** `aPressOfAnotherButtonWhileAnArenaIsAliveIsIgnored` and **2.29**
     `aBeganOfAPinchKindTheArenaDoesNotHoldFeedsTheArena` pin the other
     halves of items 1 and 2 (a different button is ignored; a kind not held
     active feeds the arena) — added by `CI-AG`.
   - The `pendingContextMenu` of 2.26's secondary analogue rides item 1: a
     right press that replaces a stale secondary arena parks its own menu,
     judged by its own arena — covered by 3.28 staying green.

**Cost if wrong.** A platform that sends a second `.began` within one live
gesture of the same kind (none known: AppKit's phases and SDL's
`PINCH_BEGIN` are once per gesture) restarts that gesture's Σ at its own
position — the value resets, nothing else moves.

## CI-AC — Two deferrals are not additive; `CI-A`'s reasoning narrowed

**Finding.** `CI-A` says "each deferral is additive over a spelling built
here". Two are not, because MetalUI is built without library evolution, so an
outside exhaustive `switch` over a public enum compiles without `default:`
and breaks when a case is added:

1. **`CoordinateSpace.named(_:)`** — `CoordinateSpace` is a public `enum`
   with `.local` and `.global` (SwiftUI's shape: SwiftUI's is an enum too,
   but resilient, so SwiftUI's clients already write `@unknown default`).
2. **`PointerStyle.image(_:hotSpot:)`/`.shape(...)`** — `PointerStyle` is a
   struct (additive), but the seam's `PlatformPointerStyle` is an enum an
   outside `PlatformWindow` conformer switches over in `setPointerStyle`.

**Ruling.** Keep both enums (SwiftUI's shape for `CoordinateSpace`; the
seam's closed cursor list for `PlatformPointerStyle`). `CI-A`'s reasoning
line reads **"each deferral is additive over a spelling built here, except
`CoordinateSpace.named(_:)` and an image cursor, each of which adds an enum
case: an outside exhaustive switch then owes a case or `default:` (a
migration note in the change that adds it)"**. Lane C writes that sentence
into `CoordinateSpace`'s and `PlatformPointerStyle`'s doc comments and spec
§9.

**Rejected:** turning `CoordinateSpace` into a struct with `static let local`,
`global` — it would keep every call-site spelling but lose pattern matching
SwiftUI code writes, and lane 2's committed type and guards would move for a
case no one has asked for.

**Cost if wrong.** None now; the cost is stated where it falls.

## CI-AD — No wheel latching (stated, not built)

**Finding.** `CI-I` item 4 dispatches every wheel event by the pointer's
position at that event. A trackpad scroll's events, momentum included, can
therefore change target mid-gesture when content moves under a still pointer
or the pointer drifts off a canvas while it glides. Whether AppKit latches a
scroll gesture's events to the view under its `.began` is **not probed** —
no claim is made here either way.

**Ruling.** Not built on this branch: the wheel chain keeps `applyScroll`'s
existing per-event lookup (no state on `Window`, `DD-Y` unchanged). Spec §9
gains the row (owner none: a probe arm with phased `CGEvent` scrolls across
two views, then a latch keyed by `phase == .began` on AppKit; SDL has no
phase, so it cannot latch). Human check **Y13** (lane C writes it): flick the
demo canvas so it glides, move the pointer onto the style strip mid-glide,
and note whether the glide stops (MetalUI today) — the answer is the probe's
input.

**Cost if wrong.** A gliding canvas pan stops when the pointer leaves the
canvas mid-glide; the next flick restarts it.

## CI-AE — Remaining lanes re-cut (amends `CI-W`); the probe re-run

**Ruling.**

1. **The probe re-run.** `swiftui-input-apis.swift` compiled and run twice
   on 2026-10-08 (same machine and toolchain, screen locked): all 61 lines
   byte-identical to the recorded output, exit 0, stderr empty both times.
   No SwiftUI claim of this branch rests on an unrun arm.
   **The suite at `164d241`** (native build, unfiltered `--no-parallel`, screen
   locked): **2723 tests in 3 suites** (2687 after lane 1's review + lane 2's
   36: 18 arena tests, 3 guards, 15 window tests), the `FR-J` line present,
   **5 issues, all in `AppKitPresentationTests`** (`appKitOpenDialogIsASheet…`,
   `appKitSaveDialogCarries…`, `appKitCancelledDialogArrives…`,
   `appKitDismissPresentationEnds…`, `appKitSecondDialogWhileASheet…`: each
   `turn { nsWindow.attachedSheet != nil }` timed out at 61 s). That file is
   untouched by the branch, but `AppKitPlatform.swift` is not (lane 1's
   tracking-area and cursor changes), so **lane A owes the answer before its
   mutations**: re-take those five with the screen unlocked (lock probe), and
   if they still fail, bisect lane 1's `AppKitPlatform.swift` hunks; a
   locked-screen-only failure is recorded as environmental with both runs.
2. **State at the critic's start.** Lanes 1 (with its review, `CI-Y`/`CI-Z`)
   and 2's implementation (`164d241`) are committed; **lane 2 has no
   verification commit** — none of spec §4.2's mutations nor the lane-2
   rows of §4.3 has been run, and guards 2.1/2.2/2.25 have not been mutated
   red. Lane 3 is untouched.
3. **Three lanes remain, sequential (A → B → C), one agent at a time:**
   - **Lane A — lane 2's verification and `CI-AB`.** Lane 2's files only
     (`Gesture.swift`, `SpatialGestures.swift`, `Window.swift`'s press, pinch,
     button and menu stages, the three `InputAPIGesture*` test files). Pins
     2.26/2.27 red first, the fix, then every lane-2 mutation of spec §4.2
     and the lane-2 rows of §4.3 (3.1, 3.26–3.34, 3.31b, 2.26, 2.27), the
     three guards mutated red once, counts, 14 images 0 px; ruling and spec
     amendments.
   - **Lane B — wheel and pointer style.** Old lane 3 minus the demo,
     divergences, census, human checks and record: spec §1.3, §1.4's wheel
     and style stages, `CI-Q`, `CI-S`, tests 3.2–3.25 and 3.37, the inventory
     rows (class A/M) and doc comments for its own declarations (the check
     scripts print nothing at its end), `docs/migration.md` API notes, every
     mutation of its rows. No `Backends/SDL` change (lane 1 built the SDL
     cursor side).
   - **Lane C — demo, registries, Record.** The canvas demo (§6, tests 3.35,
     3.36), the SDL demo's env switch (so the `Backends/SDL` build and the
     Linux image run), divergences 139–141 and the Not-offered rows, the
     class-D family moves (`CI-AA` item 9), `CI-AC`'s doc sentences, the
     census re-recorded, `docs/api-overview.md`, human checks group Y (Y1–Y13),
     the demo-pixel compare, then the Record phase (§8.3, record 81).
4. Lane B and lane C both touch `docs/migration.md` and the inventory map;
   C edits on top of B's commit (sequential, as `CI-W`).


## CI-AF — Lane A: the sheet issues are environmental; `CI-AB` built; every lane-2 mutation reddens its named test

**Ruling.** Lane A (commits `3b14cf3` red, `c33e7de` fix) answers `CI-AE`
item 1, builds `CI-AB` and verifies lane 2. Nothing in it renames a
provisional name (**MetalCreator: every name in the header stands**).

1. **The five `AppKitPresentationTests` sheet issues are environmental — a
   locked screen plus the number of AppKit windows opened before them — not
   lane 1's `AppKitPlatform.swift`.** Measured, screen locked throughout
   unless said otherwise:
   - At `70ed000` the unfiltered native suite passes, **2672 tests in 3
     suites** (165 s); at `7157e67` (lane 1 after its review, recorded green
     as 2687 in `CI-Z` item 7) it fails with **the same 5 issues** (2687
     tests, 458 s) — so lane 2 did not cause them, and `CI-Z`'s green run was
     taken unlocked.
   - Filtered alone (`--filter AppKitPresentationTests`) all nine pass on the
     branch, as at `70ed000`.
   - The 728 tests that run before `appKitOpenDialogIsASheetWithTheDeclaredTypes`
     in the unfiltered order, plus it, reproduce the failure under a filter.
     Halving does not (neither half alone fails). The 717 of them that exist
     at `70ed000` plus it pass; with lane 1's eleven new tests added, it
     fails; a one-at-a-time removal leaves five of them needed together
     (`appKitOtherButtonsAndRightDragReachOnInput`,
     `appKitBackAndForwardButtonsCarryTheirButtonNumbers`,
     `aControlDragOnAppKitIsASecondaryDrag`,
     `appKitSetPointerStyleSetsTheCursorAndCursorUpdateKeepsIt`,
     `theHostViewsTrackingAreaRequestsCursorUpdates` — each opens and closes
     one AppKit window, no shared behaviour), and with those five kept,
     removing **any five** of the old window-opening tests instead (two
     disjoint sets tried: five drag-and-drop tests, five menu tests) makes it
     pass again. A count, not a hunk: there is no `AppKitPlatform.swift` hunk
     to bisect to.
   - **Unlocked, the five pass in the unfiltered suite**: the full run under
     mutation G2.25 (a guard-only access change, below) started 08:34 with
     the screen unlocked (lock probe at 08:39: no `CGSSessionScreenIsLocked`,
     `displayAsleep main: 0`) and finished with **1 issue** — the guard it
     targeted — every sheet test passing (`appKitOpenDialogIsASheet…` in
     1.2 s). The screen locked again at 08:41, so the unmutated re-take below
     is a locked run.
   Recorded as environmental. **The owed unlocked run is taken** (`CI-AG`
   item 3): at `6b09c13`, screen unlocked, the unmutated unfiltered suite
   passed, 2725 tests, **0 issues**. Not
   fixed here (lane 1's and `AppKitPresentationTests`' files are outside lane
   A); if it recurs unlocked, the window teardown of the AppKit test helpers
   is the place to look.
2. **`CI-AB` built as ruled.** `Window.buttonPress` drops a live arena of the
   same button number before forming (`if buttonArena != nil,
   buttonArenaButton == button { buttonArena = nil }`, silently, no
   `onEnded`); `Window.dispatchPinch` drops the pinch arena when a `.began`
   names a kind it holds active (`GestureArena.holdsActivePinch(of:)`,
   internal) and forms the new one at the event's position. A different
   button's press while an arena is alive is still ignored.
   - **Red at `3b14cf3`**: 2.26 — `platform.simulateInput(odown(200, 100)) →
     false` and the second drag fed A: `["A 105,0 @50,50", "A end"]`; 2.27 —
     `["A 110 @50,50", "A 120 @170,70", "A end"]` (A re-begun at B's point).
     Suite 2725 tests, 9 issues (these 4 expectations + the 5 sheet issues).
   - **Green at `c33e7de`**: both pass.
3. **Mutations** — each applied once to `c33e7de`, restored from a copy,
   native build, full unfiltered `--no-parallel` suite (every run 2725 tests;
   the 5 locked-screen sheet issues are in each run's count but are not
   listed), `git status --short` clean after each, no hang (the longest run
   532 s; the hang threshold was 14 min because the locked-screen sheet
   timeouts add five minutes to a normal run). Every one reddens the test
   spec §4 names for it. Spellings, where §4's words leave a choice:

   | # | Spelling (file) | Reddened |
   | --- | --- | --- |
   | 2.3 | spatial tap records `leaf.pressPoint` (`Gesture.swift` release) | `aSpatialTapReportsItsReleasePointInLocalSpace`, `aSpatialTapInGlobalSpaceReportsTheWindowPoint`, `aSpatialDoubleTapReportsTheSecondRelease` |
   | 2.4 | spatial tap point taken `in: .local` | `aSpatialTapInGlobalSpaceReportsTheWindowPoint` |
   | 2.5 | the first release of a multi-tap records the location, later ones keep it | `aSpatialDoubleTapReportsTheSecondRelease` |
   | 2.6 | `ArenaLeaf.local` skips `region.localPoint` | `aSpatialTapThroughARotationReportsWhereOnItselfItWasTapped`, `pointConsumersReadTheDeclarersLocalPoint` |
   | 2.7 | move's and release's `Value` carry `modifiers: []` (the press's in the test) | `aDragValueCarriesTheModifiersOfItsEvent` |
   | 2.8 | move's `Value` taken `in: .local` | `aGlobalDragReportsWindowPoints` |
   | 2.9 | `isLive`: `.magnify, .rotate` answer `true` | `aPressArenaFailsPinchLeavesAndNonPrimaryDrags` |
   | 2.10 | the click is live, and appended, in every mode but `.pinch` | `aButtonArenaHasOnlyItsButtonsDragLeaves`, `aMiddleDragReachesOnlyAMiddleButtonDragGesture` |
   | 2.11 | `distance > minimum` | `aSecondaryDragActivatesAtItsMinimumDistance`, `aDragChangesFromExactlyItsMinimumDistanceInLocalYDownSpace`, `aDragOnAContentShapeInsetElementReadsTheElementsOwnSpace`, `aProposalGestureModifierRecognizesAsTheLegacyOneDoes` |
   | 2.12 | `pinchAmount = (1 + Σ)(1 + δ) − 1` | `magnificationIsCumulativeAndAdditiveFromOne`, `aMagnifyActivatesOnlyAtItsMinimumScaleDelta`, `aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther`, `rotationIsCumulativeFromTheSeamsClockwiseDeltas` |
   | 2.13 | a pinch leaf starts on its first event | `aMagnifyActivatesOnlyAtItsMinimumScaleDelta` and ten more (`aBeganOfAnActivePinchKindReformsTheArenaUnderTheEvent`, `aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther`, `aMagnifyThatNeverActivatedEndsWithNoCallback`, `aPinchArenaRunsNoTapDragOrClick`, `aPinchIsWithdrawnByDisabledAndAllowsHitTesting`, `aSimultaneousMagnifyAndRotateCompositionReportsBoth`, `magnificationIsCumulativeAndAdditiveFromOne`, `rotationIsCumulativeFromTheSeamsClockwiseDeltas`, `startLocationAndAnchorAreTheFirstEventsLocalPoint`, `theInnermostMagnifyWinsUnlessAnOuterOneIsHighPriority`) |
   | 2.14 | an unstarted pinch leaf becomes ready at the end and is marked activated (both halves: `pinch` and the resolve guard) | `aMagnifyThatNeverActivatedEndsWithNoCallback` |
   | 2.15 | `rotate` passes `-event.rotation` | `rotationIsCumulativeFromTheSeamsClockwiseDeltas`, `aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther` |
   | 2.16 | start point and anchor recomputed after every delta | `startLocationAndAnchorAreTheFirstEventsLocalPoint` |
   | 2.17 | a pinch leaf is held off by any unfailed leaf ahead | `aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther`, `startLocationAndAnchorAreTheFirstEventsLocalPoint` |
   | 2.18 | normal members sorted outermost first | `theInnermostMagnifyWinsUnlessAnOuterOneIsHighPriority`, `anInnerGestureBeatsAnOuterNormalOneOnAChildOrOneElement`, `aFailedHigherGestureHandsThePressToTheNextOne`, `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren`, `aDragGestureThatOutranksADraggableWinsAndAnOuterOneLoses` |
   | 2.19 | `visit`'s `.simultaneous` passes earlier siblings as `ahead` in pinch mode | `aSimultaneousMagnifyAndRotateCompositionReportsBoth` |
   | 2.20 | the click is live, and appended, in every mode | `aPinchArenaRunsNoTapDragOrClick`, `aButtonArenaHasOnlyItsButtonsDragLeaves`, `aMiddleDragReachesOnlyAMiddleButtonDragGesture` |
   | 2.21 | `dispatchContextMenu`'s `location = mouse.position` (`MenuSession.swift`) | `aLocatedContextMenuReceivesThePressPointInLocalSpace`, `aDeferredLocatedMenuReceivesThePressPointNotTheRelease`, `aLocatedMenuThroughARotationReportsWhereOnItselfItWasPressed` |
   | 2.22 | `buttonRelease` opens the pending menu with its location moved by release − press | `aDeferredLocatedMenuReceivesThePressPointNotTheRelease` |
   | 2.23 | `openContextMenu(of:)` passes `location: (0, 0)` (the region's origin) | `aKeyboardOrAccessibilityOpenPassesNoLocation` |
   | 2.24 | `inRegion = mouse.position` (no `localPoint`) | `aLocatedMenuThroughARotationReportsWhereOnItselfItWasPressed` |
   | 2.26 | the `CI-AB` line in `buttonPress` deleted (the `guard buttonArena == nil` alone) | `aSecondPressOfTheArenasOwnButtonReplacesAStaleArena` |
   | 2.27 | the `CI-AB` line in `dispatchPinch` deleted (the old leaves re-begin) | `aBeganOfAnActivePinchKindReformsTheArenaUnderTheEvent` |
   | 3.1 | the proposal `onTapGesture` overload passes `.global` (`GestureModifiers.swift`) | `onTapGestureWithALocationRunsOnBothVocabulariesInLocalSpace` |
   | 3.26 | `buttonPress` forms `.press` for every button but 1 | `aMiddleDragReachesOnlyAMiddleButtonDragGesture`, `aMiddleDragDuringAPendingPrimaryTapSequenceDisturbsNeither`, `aSecondPressOfTheArenasOwnButtonReplacesAStaleArena`, `anOtherPressDismissesAPopoverAndAnOpenInWindowMenuTakesItAndPinches` |
   | 3.27 | `if false && secondaryDragIsDeclared(…)` | `aSecondaryDragOpensNoContextMenu`, `aSecondaryClickWithASecondaryDragDeclaredOpensTheMenuOnRelease`, `aDeferredLocatedMenuReceivesThePressPointNotTheRelease` |
   | 3.28 | `buttonRelease` never opens the pending menu | `aSecondaryClickWithASecondaryDragDeclaredOpensTheMenuOnRelease`, `aDeferredLocatedMenuReceivesThePressPointNotTheRelease` |
   | 3.29 | `if true \|\| secondaryDragIsDeclared(…)` | `withoutASecondaryDragTheMenuStillOpensOnThePress` and 38 more context-menu, drawn-menu and presentation tests (every right-press-opens test: `theInnermostContextMenuOpens`, `aRightPressOverAContextMenuPresentsItsItemsToThePlatform`, `aPresentationOnAHigherLayerBlocksAContextMenuBeneath`, …) |
   | 3.30 | `.button(n)` also admits `.primary` drags | `secondaryAndOtherPressesStillNeverPressTapOrDragPrimaryGestures`, `aButtonArenaHasOnlyItsButtonsDragLeaves`, `aMiddleDragReachesOnlyAMiddleButtonDragGesture`, `withoutASecondaryDragTheMenuStillOpensOnThePress` |
   | 3.31 | `dispatchMenuSession` answers `false` for `.otherMouseDown`, `.otherMouseUp`, `.magnify`, `.rotate` | `anOtherPressDismissesAPopoverAndAnOpenInWindowMenuTakesItAndPinches` |
   | 3.31b | `.magnify, .rotate` dropped from `trackTooltip`'s hide arm (`Tooltip.swift`) | `aMagnifyOrARotateHidesTheTooltip` |
   | 3.32 | a button press also clears `gestureArena` (one slot's effect) | `aMiddleDragDuringAPendingPrimaryTapSequenceDisturbsNeither` |
   | 3.33 | the pinch arena forms at `lastMousePosition ?? position` | `aMagnifyEventReachesTheMagnifyGestureUnderThePointer` |
   | 3.34 | `Frame.registerHandlers`' pointer hitbox registered without `enabled` | `aPinchIsWithdrawnByDisabledAndAllowsHitTesting` and 25 more disabled-gate pins (`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`, `theGateReadsTheEnvironmentValueNotTheModifier`, …) |

4. **The three guards, mutated red once** (same procedure): **G2.1**
   `MouseButton.other` internal → `anOutsideModuleCanSpellTheInputAPIGestures`;
   **G2.2** `StyledElement.onTapGesture(count:coordinateSpace:perform:)`
   internal (the plain-import spelling of "remove the overload": the
   `@testable` tests still compile) → `onTapGestureResolvesByClosureArity`;
   **G2.25** `StyledElement.contextMenu`'s located overload internal →
   `contextMenuResolvesByClosureArity`. Each reddened only its guard.
5. **Counts** at `c33e7de` after `swift package clean`, native build, unfiltered
   `--no-parallel` (screen locked): **2725 tests in 3 suites** (2723 + 2.26,
   2.27), `FR-J no-argument frame: succeeded=true`, 0 `error:`, the only
   `warning:` SwiftPM's deprecation notice, **5 issues — the locked-screen
   sheet issues of item 1, nothing else**. `swift build --build-tests`
   (default build system): 0 warnings. `closeout-inventory-check.sh` and
   `closeout-undocumented.sh` print nothing; the live census reads 2602 rows
   (the recorded `closeout-public-api.tsv` is still `70ed000`'s — lane C
   re-records it, `CI-AE`). **Demo pixels** (`compare.sh`, offscreen,
   `70ed000` → `c33e7de`): all fourteen images **0 differing**, scene dumps
   identical, every control at its recorded value. No `Backends/SDL` change,
   so no SDL or Linux-image run is owed by this lane.

**Cost if wrong.** Item 1: closed by `CI-AG` item 3 (the unlocked re-take read
0 issues). If the five issues ever appear in an unlocked run, the hunt starts
at the AppKit test helpers' window teardown.

## CI-AG — `CI-AB`'s other halves pinned; the unlocked re-take closes `CI-AF` item 1

**Finding (lane A's verifier).** `CI-AB` pinned only the replacing half of
each item. Two mutations went green against the full suite: **M3**, dropping
`buttonArenaButton == button` from `buttonPress`'s replacement check, so any
press ends a live arena; and **M4**, `holdsActivePinch(of:)` answering for any
active kind, so a rotate `.began` during a magnify drops the live arena.
`aSimultaneousMagnifyAndRotateCompositionReportsBoth` and
`aMagnifyAndARotateOnNestedElementsDoNotBlockEachOther` are arena-level tests
that never pass through `Window.dispatchPinch`, so neither can see M4.

**Ruling.** No behaviour changes. `CI-AB` items 1 and 2 stand as written.

1. **2.28** `aPressOfAnotherButtonWhileAnArenaIsAliveIsIgnored`
   (`InputAPIGestureWindowTests.swift`): a middle drag on A is live. A right
   press on B, which declares a `.secondary` drag, is **not claimed**. B
   reports nothing through its drag and release. A's next middle drag and
   release report from A's own press (`A 20 @50,50`, then a single `A end`).
   **M3 reddens it** (4 expectations: the press answered `true`, and the log
   read `["A 0 @50,50", "A 10 @50,50", "B changed", "B changed", "B end"]`).
2. **2.29** `aBeganOfAPinchKindTheArenaDoesNotHoldFeedsTheArena`: one element
   carries `MagnifyGesture().simultaneously(with: RotateGesture())`. The test
   sends magnify `.began`/`.changed 0.1`, rotate `.began`/`.changed 10`,
   magnify `.changed 0.1`, rotate `.ended`, magnify `.ended`. The magnify
   reads 1.1 and then 1.2, its `onEnded` runs once at 1.2, and the rotate
   reports 10. **M4 reddens it** (2 expectations: the log read
   `["m 110", "r 10", "m 110", "r end", "m end 110"]`, so the magnify
   restarted from 1).
3. **The unlocked re-take `CI-AF` item 1 owed** (the verifier's reading): at
   `6b09c13`, screen unlocked (lock probe at 10:01: no
   `CGSSessionScreenIsLocked` line, `displayAsleep main: 0`), native build,
   full unfiltered `--no-parallel`: **2725 tests in 3 suites passed, 0
   issues** (163.9 s), FR-J line present. The verifier's M7 and M8 runs were
   also unlocked and each read exactly 1 issue, its target. All five sheet
   tests passed in both. This fits the window-count explanation: the five
   issues appear only under a locked screen. Item 1's deferral is closed.
4. **Procedure.** Tests committed at `f23c922`. Each mutation was applied once
   to that commit and restored from a copy. Each run used a native build and
   the full unfiltered `--no-parallel` suite with the screen **locked**: M3
   read 2727 tests with 9 issues (2.28's 4 plus the 5 locked-screen sheet
   issues), and M4 read 2727 tests with 7 issues (2.29's 2 plus the 5).
   `git status --short` was clean after each. No hang (each run about 480 s).
   No other test reddened. **Unmutated at `f23c922`** (native build,
   unfiltered, screen locked): 2727 tests in 3 suites, FR-J line present, 0
   `error:`, the only `warning:` SwiftPM's deprecation notice, **5 issues, all
   of them the locked-screen sheet issues**. `swift build --build-tests`: 0
   warnings. No public declaration and no `Backends/SDL` change.

**Cost if wrong.** These are pins only. If a platform did need a different
button's press to replace an arena, 2.28 is the test to re-rule.

## CI-AH — Lane B: a handler around a scroller sees nothing; the first legacy style is the inner; every lane-B mutation reddens its named test

**Findings (lane B, while building spec §1.3/§1.4's wheel and style stages).**
Two sentences of the design could not be built as written.

1. `CI-I` item 4 ends "a legacy `.onScrollWheel` on a `ScrollView` itself
   (same id) runs **before** its scrolling and can veto it". No spelling
   gives a handler the scroller's own id. Legacy `ScrollView` is a plain
   `Element`, not a `StyledElement`, so `.onScrollWheel` reaches it only
   through a `ModifiedContent` layer (`.frame(…).onScrollWheel`). That layer
   is the scroller's **parent** (`MC-A`). The proposal `.onScrollWheel` on a
   `ProposalScrollView` is a `ScrollWheelModifier`, which is also the parent
   (`CI-V` item 2). No two elements share an id.
2. `PointerAttachment` is one box per element, so two `.pointerStyle` calls
   on one legacy element (`StyledElement` → `Self`) write the same field. The
   design said "a later `.pointerStyle` replaces its own field" (`CI-Q`).
   That would make the **outer** call win on a legacy element, while nested
   views and the proposal wrapper make the inner one win (`P11`).

**Ruling.**

1. **A wheel handler on or around a scroller sees nothing over it.** The
   scroller is reached first on the chain and always claims (`DD-Y`). **To
   veto scrolling, put the handler on the scroller's content.** The content
   is a descendant, so its handler runs first, and it may claim (no scroll)
   or decline (the scroller scrolls). This amends `CI-I` item 4's last
   clause. Test 3.6 is renamed
   `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt`
   and pins both halves: the content's claim vetoes, the content's decline
   scrolls, and a wrapper layer on the `ScrollView` sees nothing. The
   `onScrollWheel` doc comments, `applyScroll`'s doc and `docs/migration.md`
   say so. Spec §4.3's mutation for 3.6, "scroll region before the same-id
   handler", reaches no test because no handler shares a scroller's id. It is
   **green, and that is the measurement** (item 3). 3.6's pin is reddened by
   the outermost-first pre-walk spelling (3.3's).
2. **On one legacy element, the first `.pointerStyle` written is the inner
   one, and it wins.** A later `.pointerStyle` keeps an existing style.
   `.onScrollWheel` still replaces its own field and keeps the style, as
   `CI-Q` says. This matches SwiftUI's innermost-wins (`P11`). In
   `square().pointerStyle(.rectSelection).pointerStyle(.link)`,
   `.rectSelection` is written closer to the content. `nil` still attaches
   nothing (`CI-H` item 2). This amends `CI-Q`'s "replaces its own field" for
   the style. Pinned by `theInnermostPointerStyleWinsAndNilDefers`'s fifth
   arm. Mutation 3.16b (a later style replaces) reddens it.
3. **Every lane-B mutation, run against the full suite.** Each mutation was
   applied once to `e93ddbe`'s spelling (the files named) and restored from a
   copy. Each run was a native build and the full unfiltered `--no-parallel`
   suite, with the screen **locked**. Every run read **2751 tests in 3
   suites**. Every issue count includes the five locked-screen
   `AppKitPresentationTests` sheet issues (`CI-AF`), and those five are left
   out of the lists below. There was no hang (about 455–570 s each, with
   other worktrees' suites running beside it), and `git status --short` was
   clean after each run.

   | Row | Mutation (spelling) | Issues | Reddened (besides the five) |
   | --- | --- | --- | --- |
   | 3.2 | `applyScroll` passes `position` as `location` | 9 | `onScrollWheelReceivesTheEventInLocalSpaceUnderStateDispatch`, `aWheelThroughAScaleEffectReportsALocalLocationAndARawDelta`, `aGPUSurfaceViewportReceivesWheelPinchButtonDragsAndStyle` |
   | 3.3 (and 3.6) | before the chain walk, scroll the outermost scroller the cover descends from | 20 | `aWheelHandlerThatClaimsStopsAnEnclosingScrollView`, `aWheelHandlerThatDeclinesPassesToTheEnclosingScrollView`, `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt`, `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove`, `aClickTargetInsideNestedScrollViewsPassesTheWheelToTheNearest`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints` |
   | 3.6 (spec's spelling) | at each id, the scroll region before the same-id handlers | 5 | **none: green**, the measurement of item 1 |
   | 3.4 | a handler's `false` claims | 10 | `aWheelHandlerThatDeclinesPassesToTheEnclosingScrollView`, `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt`, `anUnclaimedWheelOverOnlyANonOpaqueHandlerReachesTheWindowsOnInput` |
   | 3.5 | the scroller no longer ends the walk, so every handler up the chain runs | 11 | `aWheelHandlerOutsideAScrollViewSeesNothingTheScrollerClaimed`, `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt`, `theTopmostOverlappingRegionWinsAndTheOtherDoesNotMove`, `aClickTargetInsideNestedScrollViewsPassesTheWheelToTheNearest`, `aNestedScrollViewInsideAScrolledOneReceivesTheWheelWhereItPaints` |
   | 3.5b | the **parent** id's handler joins each id's step | 7 | `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt` only. 3.5's proposal arm stays green, because `.frame` puts a layer between the wrapper and the scroller, so the wrapper is the grandparent |
   | 3.5c | before a scroller scrolls, every ancestor's handler runs | 11 | `aWheelHandlerOutsideAScrollViewSeesNothingTheScrollerClaimed` (both arms: lines 267–268 legacy, 273–274 proposal), `aWheelHandlerOnAScrollViewsContentRunsBeforeItsScrollingAndCanVetoIt` |
   | 3.7 | the walk stops at an opaque cover | 13 | `aWheelOverAClickTargetInsideACanvasReachesTheCanvasHandler`, `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`, `aClickTargetInsideNestedScrollViewsPassesTheWheelToTheNearest`, `aSingleLineTextFieldInsideAScrollViewPassesTheWheelToItsScroller`, `aSelectableListScrollsUnderTheWheelOverARow`, `aContentShapeInsideAScrolledScrollerFollowsTheScroll`, `anEffectInAScrolledScrollerTurnsAboutItsScrolledAnchor`, `aPullDownMenuInsideAScrolledScrollerOpensBelowItsScrolledFrame` |
   | 3.8 | at the root step, every containing region joins (no ancestry) | 11 | `anOverlaidSiblingClickTargetStopsTheCanvasWheel`, `aClickTargetOverlaidOnAScrollViewButNotInsideItStillSwallowsTheWheel`, `aWheelHandlerThatDeclinesPassesToTheEnclosingScrollView`, `hoverActiveAndTheGestureArenaFollowTheContentShape` |
   | 3.9 | the pointer region registers outside the `allowsHitTesting` gate | 9 | `aWheelRegionIsWithdrawnByDisabledAllowsHitTestingAndHidden`, `pointerStyleIsWithdrawnByDisabledAllowsHitTestingAndHidden` |
   | 3.10 | the wheel chain drops its layer clause | 9 | `aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags`, `aDeferredScrimDeclaredInsideAScrollViewStillSwallowsTheWheel`, `theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel` |
   | 3.12 | the delta goes through the region's inverse transform | 6 | `aWheelThroughAScaleEffectReportsALocalLocationAndARawDelta` |
   | 3.13 | a wheel claims whenever a handler ran | 8 | `anUnclaimedWheelOverOnlyANonOpaqueHandlerReachesTheWindowsOnInput` |
   | 3.14 | every gated element registers a pointer region | 132 | `aFrameWithNoWheelOrStyleRegionRegistersNoExtraHitbox` and 77 more tests (78 in all, 127 issues; an extra region on every gated element moves hitbox lists), e.g. `onlyABoxWithAHandlerRegistersAHitbox`, `aTreeWithoutHoverRegistersNoRegionAndDoesNoHoverWork` and `everyHandlerRegisteringSiteHonoursAllowsHitTesting` |
   | 3.15 | `updatePointerStyle` drops the dedupe | 9 | `pointerStyleReachesThePlatformOnlyOnAChange`, `aFrameWithNoStyleRegionDoesNoPointerStyleWork`, `aGPUSurfaceViewportReceivesWheelPinchButtonDragsAndStyle` |
   | 3.16 | the first (outermost) style region wins | 7 | `theInnermostPointerStyleWinsAndNilDefers` |
   | 3.16b | a later legacy `.pointerStyle` replaces the earlier one (item 2) | 6 | `theInnermostPointerStyleWinsAndNilDefers` |
   | 3.17 | the style cover's eligibility drops `opaque` | 7 | `anOpaqueTargetAboveCoversAPointerStyleBeneath`, `aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags` |
   | 3.18 | — (divergence 141's pin; a fix reddens it) | — | — |
   | 3.19 | the pointer region registers outside the disabled gate | 9 | `pointerStyleIsWithdrawnByDisabledAllowsHitTestingAndHidden`, `aWheelRegionIsWithdrawnByDisabledAllowsHitTestingAndHidden` |
   | 3.20 | the press-hold arm never applies | 6 | `aPressHoldsThePressedTargetsStyleWhileThePointerLeaves` |
   | 3.21 | the style is recomputed only from pointer events (`reportsMoves`) | 9 | `contentMovingUnderAStillPointerChangesTheStyleAfterTheFrame`, `anInWindowMenuOrDrawnAlertResetsTheStyleToDefault`, `aPressHoldsThePressedTargetsStyleWhileThePointerLeaves` |
   | 3.22 | the style ignores `hoverIsSuppressed` | 7 | `anInWindowMenuOrDrawnAlertResetsTheStyleToDefault` |
   | 3.23 | an exit sets the last-sent style to `.default` | 17 | `aPointerReEntryResendsTheStyleEvenWhenItIsDefault`, `aFrameWithNoStyleRegionDoesNoPointerStyleWork`, `anOpaqueTargetAboveCoversAPointerStyleBeneath`, `aPopoverAboveACanvasTakesItsWheelPinchStyleAndButtonDrags`, `contentMovingUnderAStillPointerChangesTheStyleAfterTheFrame`, `pointerStyleIsWithdrawnByDisabledAllowsHitTestingAndHidden` |
   | 3.24 | style containment uses the untransformed `bounds` | 6 | `aPointerStyleThroughARotationFollowsTheDrawing` |
   | 3.25 | the no-style-region early return is removed | 6 | `aFrameWithNoStyleRegionDoesNoPointerStyleWork` |
   | 3.37 | the wheel closure is also stored inline in `Handlers` | 7 | `handlersGainsOneReferenceMember`, `theNewDeclarationsCostHandlersAtMostOnePointer` |

   3.11 (`aGPUSurfaceViewportReceivesWheelPinchButtonDragsAndStyle`) is a
   coverage pin. It reddens under 3.2 and 3.15, as spec §4.3 says it should.
4. **The unmutated suite at `e93ddbe`**: native build, unfiltered
   `--no-parallel`, screen locked. It read **2751 tests in 3 suites** (`f23c922`'s
   2727 + `InputAPIWindowTests`' 24, 3.2–3.25; 3.37 edits two existing pins), with the `FR-J` line present, 0
   `error:` and **5 issues, all of them the locked-screen sheet issues**
   (`CI-AF`). `swift build --build-tests` (default build system, after touching every
   source and test file the branch changed): **0 warnings**.
   Both closeout scripts (`closeout-inventory-check.sh`,
   `closeout-undocumented.sh`) print nothing. **Demo pixels** (`compare.sh`,
   offscreen, `70ed000` → `e93ddbe`): all fourteen images **0 differing**, scene
   dumps identical, every control at its recorded value (default vs modal
   1031003, default vs animation 454895, as recorded at `70ed000`). No `Backends/SDL` change
   and no shader change.

**Cost if wrong.** Item 1: suppose a caller needs a handler that sees a wheel
over a scroller *before* the scroller, without owning its content. That
would need a new scroller hook (none is designed); it would be additive.
Item 2: if SwiftUI is ever probed with two `.pointerStyle` calls on one view
and the outer one wins, item 2 flips and 3.16b's arm is the pin to edit.

## CI-AI — Lane C: the canvas demo's shape and arithmetic; its tree builds in its own frame; registries and the platform runs

**Ruling.** Lane C (commits `ef139f4` red, `28c266a` implementation,
`6678e60` the stack fix) built spec §6's demo, the registries `CI-AE` item 3
names and the platform runs. Nothing in it renames a provisional name
(**MetalCreator: every name in the header stands**).

1. **The demo's shape** (`Sources/MetalUIDemoContent/CanvasDemo.swift`,
   `METALUI_CANVAS_DEMO=1` in `MetalUIDemo` and `MetalUISDLDemo`). One
   `@Observable` `CanvasDemoModel` (`canvasDemoModel`), written only from
   input. Each part (`canvasHeader`, `canvasSurface`, `canvasStyleStrip`,
   `canvasStatus`) is its own function passed to the generic `canvasRoot`.
   Middle and right drags pan anywhere on the canvas (the demo has no 3D
   viewport, so right-drag pans rather than orbits). A primary drag pans only
   on the strip along the top, which shows `.grabIdle` and `.grabActive`
   while any pan drags (`CI-V` item 3). Two-finger scroll pans and honours
   momentum. **⌘- and ⌃-scroll** zoom about the wheel's `location`. ⌃ is
   added because a Windows precision touchpad's pinch arrives as
   control+wheel (`CI-C` item 5, Y10). Pinch zooms about `startLocation`.
   Zoom is clamped to 0.25…4. A `SpatialTapGesture` picks. A right-click on a
   node opens a located menu, on the release. The pointer is `.rectSelection`
   over empty canvas and `.link` over a node. **C** toggles the crosshair with
   no pointer motion (Y12). "Revolve" carries a `RotateGesture` inside the
   canvas's `MagnifyGesture` (Y4). Below the canvas are a style strip and a
   status line. No existing demo tree changes.
2. **The arithmetic, derived before the run** (test 3.35's header). A canvas
   point `c` is drawn at the canvas-local point `pan + c × zoom`. A zoom by
   `f` about the local point `p` keeps the canvas point under `p`, so
   `pan' = p − (p − pan) × f`. A ⌘-wheel zooms by `2^(Δy / 100)`. A plain
   wheel pans by its delta. A pinch applies its cumulative magnification to
   the view it began on.
3. **The canvas tree builds in its own frame on the 1 MB thread** (test
   3.36). Lane C first added `_ = canvasDemoContent()` inline to
   `buildEveryProductionTree()`. On macOS arm64 that passed. In the
   `swift:6.4-noble` container the cross-platform target died with
   `.signal(SIGSEGV)`: the composer's frame plus the canvas tree overflowed
   the 1 MB thread. The test now calls an `@inline(never)`
   `buildTheCanvasDemo()`, for the same reason as `buildTheServicesDemo()`
   (`SV-T`). Production is unaffected: both demo mains pass
   `canvasDemoContent` to `openWindow` as the window's content. **This is 3.36's
   measurement.** Spec §4.3's mutation for 3.36, "inline the demo's body into
   the composer", is the spelling that overflowed. It overflows only off
   macOS, which is why the arm runs in the Linux and Windows CI jobs.
4. **Registries.** Divergences 139–141 were written, and six Not-offered
   rows for spec §9's deferrals (`docs/divergences.md`: **108 live, next
   label 142**). `CoordinateSpace` moved to the class-D family
   `input-apis-global-space` (139), and `DragGesture.Value.modifiers` to
   `input-apis-drag-modifiers` (140). `pointerStyle(_:)` got its own D family,
   `input-apis-pointer-style-modifier` (141), as spec §8.2 marks it. That makes
   three class-D families (`CI-AA` item 9). `CI-AC`'s sentence is in
   `CoordinateSpace`'s and `PlatformPointerStyle`'s doc comments. The census
   was re-recorded: 2639 at `28c266a`, which missed the 18 public
   `MetalUIDemoContent` declarations of `CanvasDemo.swift`. The close
   re-ran `closeout-public-api.sh`, and the diff was exactly those 18 lines,
   so the census is **2657**. The map's `demo-content` rule already classifies
   them, and both check scripts print nothing. `docs/api-overview.md` gained the section, and
   `docs/verification/human-checks.md` gained group Y (Y1–Y13, none run: an
   agent cannot).
5. **Verification** (the numbers in record §81 §4):
   - Red at `ef139f4`: the build failed with `CanvasDemoTests.swift:25:5
     cannot find 'canvasDemoModel' in scope`, `:27:78 cannot find
     'canvasDemoContent' in scope`, and `DemoStackBudgetTests.swift:36:9
     cannot find 'canvasDemoContent' in scope`.
   - Mutation **3.35** ("zoom about the canvas origin": `zoom(to:aboutX:y:from:)`
     sets `pan = start.pan × factor`) was applied to `6678e60`'s spelling and
     restored from a copy. One native build and the full unfiltered
     `--no-parallel` suite, with the screen unlocked. It read **2752 tests in 3 suites, 3 issues**, all in
     `theCanvasDemoPansZoomsAboutThePointerPicksAndShowsACrosshair`
     (`CanvasDemoTests.swift:77`, `:85`, `:89`: the pinch, ⌘-wheel and wheel
     pans). No other test reddened. There was no locked-screen sheet issue
     (the screen was unlocked). `git status --short` was clean of source after
     the restore.
   - Demo pixels (`compare.sh`, `70ed000` → `6678e60`): **all fourteen images
     0 differing, scene identical**. Every control is at its recorded value
     (default vs modal 1031003, default vs animation 454895).
   - `Backends/SDL` on macOS: **24 + 93**, the same as `CI-Z` item 7 (lanes
     A–C added no SDL test). CI's Linux image (`offscreen`): **24 + 90**,
     three lifecycle tests skipped by `windowsPresentFrames`. The only
     warning is the pre-existing `AccessKitControlsParityTests.swift:83`.
   - `swift:6.4-noble`, on a `git archive` of `6678e60`: root `swift build
     --build-tests` completed with 0 warnings. Its portable tests passed:
     6 + 35 + 18 + 199 + 49 + 22, with the cross-platform target's 49
     unchanged (3.36 is an arm of an existing test).

**Cost if wrong.** Item 3: a later demo section built inline in the
composer passes on macOS and overflows only in CI. The test's doc comment
names the rule, and so does CLAUDE.md's 1 MB bullet.
