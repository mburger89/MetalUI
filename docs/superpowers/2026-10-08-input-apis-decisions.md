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

Prefix **`CI-`**, lettered. **Next unused: `CI-AA`.** (This line moves in the
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
`ContextualAttachment` does), the **eighteenth** member `pointer:
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

Mutations for items 1–4: see the table below (filled when run).

**Cost if wrong.** Item 1: a drawn menu on SDL that cannot be chosen from by
press-drag-release — the regression this closes. Item 3: none in shipped
behaviour (the default is the old call).
