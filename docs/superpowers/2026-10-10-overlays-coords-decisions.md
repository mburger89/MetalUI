# Overlays and coordinates — decisions

Rulings for item C15 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**), requested by MetalCreator (gaps EP-a and EP-b in its
`docs/metalui-gaps.md`, checked on `c62d6ba`). Prefix `OV-`. Spec:
[`specs/2026-10-10-overlays-coords-design.md`](specs/2026-10-10-overlays-coords-design.md).
Record: `../record/92-overlays-coords.md`. Branch `feat/overlays-coords` from
`ebcf3c7`. Divergence labels reserved for this branch: 225–234.

SwiftUI's side: `docs/probes/swiftui-overlays-coords.swift` (arms A, B, G, W;
run twice, byte-identical) and `docs/probes/swiftui-overlays-coords-typecheck.sh`
(arms T0–T16). gpui's side, where SwiftUI has nothing: `crates/gpui/src/elements/anchored.rs`
(`anchored()`, `Anchor::TopLeft`, `AnchoredFitMode::SwitchAnchor` by default,
`position` in window coordinates) and `on_mouse_down_out`.

**Next unused id: `OV-U`.**

## The final spellings (what an app writes)

```swift
// EP-b — MetalUI-only, gpui's `anchored` + `on_mouse_down_out` (OV-A, OV-K)
canvas.anchoredOverlay(isPresented: $paletteShown, at: pointer)              // .local, .topLeading
canvas.anchoredOverlay(isPresented: $shown, at: p, in: .named("canvas"), anchor: .topLeading) { Palette() }
canvas.anchoredOverlay(item: $request, at: p) { request in Palette(request) }

// SwiftUI's point anchor on .popover (OV-B)
.popover(isPresented: $shown, attachmentAnchor: .point(.topLeading), arrowEdge: .bottom) { … }
.popover(item: $item, attachmentAnchor: .rect(.rect(Bounds(...)))) { item in … }

// EP-a — SwiftUI's spellings (OV-D, OV-E, OV-F, OV-H)
.coordinateSpace(.named("canvas"))
.onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .named("canvas")) }) { … }
.onContinuousHover(coordinateSpace: .named("canvas")) { phase in … }
DragGesture(coordinateSpace: .named("canvas"))
// MetalUI-only (OV-G)
@Environment(\.windowSize) var windowSize
```

## OV-A — EP-b is a MetalUI-only `anchoredOverlay`, not a popover style

**Question.** EP-b wants a popover anchored at a point with its top-leading
corner there, no panel, border or shadow, flipped inside the window at the
right and bottom edges, dismissed by an outside press of any button and by
Escape, swallowing presses and wheel on itself, keys reaching a field inside.
Can a SwiftUI-shaped spelling carry it?

**Evidence.**
1. Placement (arms A0–A7): SwiftUI's popover is always **centred on its anchor
   along the axis across `arrowEdge`**; a point anchor is a zero-size rect
   (A1 is A7 moved by the point exactly). No arm puts a corner at the point.
2. Chrome (arms B0–B2, T15): `.presentationBackground(.red)` reaches the
   chrome, but `.clear` leaves the `NSPopoverFrame`/`NSGlassView`, the window
   shadow and every sampled pixel equal to the control's. SwiftUI on macOS has
   no chrome-less popover and no `popoverStyle`.
3. gpui models exactly EP-b: `deferred(anchored().position(p).child(…))`,
   `anchor` defaulting to the top-left corner, `SwitchAnchor` fitting (per
   axis, keep the opposite corner only if it then fits), and
   `on_mouse_down_out` for any button.
4. MetalUI's popover stage already sees every press of every button
   **before** the stages EP-b names (the context menu, text input, the value
   track): `Window`'s input hook runs `dispatchPopovers` ahead of all three, and an outside press passes on (`MN-Y` item 1). EP-b's stopgap missed
   those presses only because it read `Window.onInput`, the last stage.

**Ruling.** A MetalUI-only modifier on both vocabularies,
`anchoredOverlay(isPresented:at:in:anchor:content:)` and
`anchoredOverlay(item:at:in:anchor:content:)`, returning the existing
`PopoverModifier<Self, P>` (one wrapper type; one identity level for its caller
only, slot cursor 1, `MN-L`'s numbering), drawn through the existing
`AnchoredPresentation` with:

1. **No chrome**: no panel, border, shadow or padding; the content's own box is
   the overlay's box (still wrapped in the chrome `Box`, padding 0, so it
   publishes the `.popover` node of `MN-O` and the content's `@State` starts
   fresh per presentation, `ID-C`).
2. **Placement** (`OverlayPlacement.origin`, a pure function): the content's
   `anchor` unit point at the window point; per axis, if the content leaves
   the window, the mirrored unit point (`1 − x` / `1 − y`) is kept when the
   content then fits (gpui's `SwitchAnchor`); then clamped inside the window.
   **Margin 0** (gpui's `SwitchAnchor` has none; the overlay has no chrome to
   keep off the edge — the content pads itself). Measured at a nil proposal,
   capped at the window like `PopoverPlacement`.
3. **Dismissal** is the popover stage, unchanged: an outside press of any
   button dismisses (topmost first) and passes on; Escape with no modifiers
   dismisses the topmost; open popovers and overlays share one stack. **A
   press on the declarer is never consumed** (unlike `MN-Y` item 2): the
   declarer of a pointer-placed overlay is typically the canvas under it, and a
   canvas press must close the palette *and* reach the canvas (gpui's
   `on_mouse_down_out` does not stop propagation). `OpenPopover` gains
   `consumesAnchorPress: Bool` (false for an overlay).
4. **Swallowing**: `MN-Z`'s raw opaque hitbox at the content's bounds, unchanged
   — a press, wheel or drop on the overlay never reaches beneath; a pinch over
   it ranks the raw hitbox, which takes no pinch (EP-b's observation stands and
   is right: nothing beneath should zoom).
5. **Keys**: nothing new — the popover stage claims only Escape, so a field
   inside the overlay focused by a click (`TI-`, a field focuses on click)
   receives keys; Escape dismisses even while that field is focused (the
   popover stage runs before every key stage), and focus leaves with the
   field's identity (`IX-I`).

**Rejected.** (a) `.popover(…).presentationBackground(.clear)` plus a point
anchor: SwiftUI's own answer keeps the chrome (B1) and centres (A1), so MetalUI
would be giving a SwiftUI spelling a meaning SwiftUI does not have, and the
corner placement would still need a MetalUI-only parameter. (b) An
outside-press callback (`onPressOutside`) for an ordinary `.overlay`: the
overlay would still be clipped by and laid out in its parent, could not leave
a scroller, and every press-swallowing and Escape rule would be the app's
again — the stopgap EP-b is retiring. (c) A `popoverStyle(.plain)`: no such
SwiftUI API exists (T15), and the placement rule differs, so a "style" would
change geometry, not looks.

**Cost if wrong.** A later SwiftUI chrome-less popover would be a second
spelling beside this one; `anchoredOverlay` stays as the gpui-shaped tool and
the new one maps onto `.popover`. No existing behaviour moves.

## OV-B — `.popover` takes SwiftUI's `attachmentAnchor:`

**Evidence.** T11–T13 (the spellings compile, both `isPresented:` and `item:`;
`.rect(.rect(CGRect))`); A1–A7 (a point is a zero-size rect at the unit point
of the anchor's bounds; `.rect(.rect(r))` is `r` in the **anchor's own
space**: A7's popover is A1's moved by (10, 10)).

**Ruling.** The four `.popover` overloads gain
`attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds)` between the
presentation argument and `arrowEdge:`. `PopoverAttachmentAnchor` is SwiftUI's
enum, `case rect(Source)` and `case point(UnitPoint)`; `Source` is a nested
struct with `static var bounds` and `static func rect(_: Bounds<Pixels>)`, so
`.rect(.bounds)` and `.rect(.rect(r))` spell as in SwiftUI — **divergence
225**: SwiftUI's source is `Anchor<CGRect>.Source` (MetalUI has no `Anchor`
type) and the rect is `Bounds<Pixels>`. The resolved anchor rect (a zero-size
rect for a point) feeds the unchanged `PopoverPlacement.origin` — 8 pt gap, no
arrow (divergence 112), flip then clamp (divergence 111). A press on the
declarer keeps `MN-Y` item 2's consumption over the declarer's **whole**
bounds (a toggling anchor still closes), whatever the attachment anchor.

**Cost if wrong.** Small: the argument is defaulted, every existing call
compiles unchanged and places identically (pinned by the existing
`PopoverTests` staying green).

## OV-C — `presentationBackground(_:)` is not built (deferred) — **built by `BG-A`…`BG-F`, `BG-P`** (`../2026-10-22-presentation-extras-decisions.md`)

B1 shows SwiftUI's `.clear` keeps the macOS popover's chrome, so the modifier
cannot carry EP-b; B2 shows it does recolour the fill. Building it means a
value flowing from the popover's content up to `AnchoredPresentation`'s paint
(a preference-shaped channel the popover does not have). **Deferred, no owner,
until an app asks**; additive when built (a new modifier, the fill only, the
border and shadow kept as SwiftUI keeps its frame). Inventory class R.

## OV-D — `CoordinateSpace.named(AnyHashable)`; `coordinateSpace(_:)`

**Question** (`CI-AC` item 1): adding the case breaks an outside exhaustive
`switch` (MetalUI is built without library evolution).

**Evidence.** T9/T10: SwiftUI's `CoordinateSpace` has exactly `local`,
`global`, `named` (a switch over the three compiles exhaustively; over two it
refuses). T4/T16/T3/T2: `.coordinateSpace(.named("x"))`,
`frame(in: .named("x"))`, `onContinuousHover(coordinateSpace:)` all exist.

**Ruling.** Add `case named(AnyHashable)` — SwiftUI's case set exactly
(the enum's `Sendable` footing: `OV-L`).
**Migration note** (docs/migration.md, the case's doc comment, `CI-AC`'s
sentence): an outside exhaustive `switch` over `CoordinateSpace` owes a
`.named` case or `default:`. Add `NamedCoordinateSpace` (a struct;
`static func named(_ name: some Hashable) -> NamedCoordinateSpace`) and
`coordinateSpace(_ space: NamedCoordinateSpace)` on both vocabularies, so
`.coordinateSpace(.local)` does not compile (guard). **Not offered**:
SwiftUI's deprecated `coordinateSpace(name:)`, `CoordinateSpaceProtocol` and
`.scrollView` (inventory R; `.named` covers EP-a).

**Rejected:** a struct `CoordinateSpace` (`CI-AC`'s own rejection stands: it
loses SwiftUI's pattern matching).

**Cost if wrong.** One migration-noted source break for outside switches; no
in-tree switch exists outside `GeometryProxy.frame(in:)`,
`ArenaLeaf.point(_:in:)` and the hover conversion, each owed a `.named` arm.

## OV-E — What a named space means, and how it is resolved

**Evidence** (arms G1–G5). `frame(in: .named(n))` is relative to the
**nearest ancestor** declaring `n` (G2); a name no ancestor declares falls back
to `.global` (G1's `missing`; G5, a sibling's name); the named space moves
**with its container, transform and all**: an `.offset` (G3) or a
`.rotationEffect` (G4) on the container moves `.global` but not the named
frame (G4: global is the rotated 20 × 40 bounding box, named stays 40 × 20).

**Ruling.**
1. `coordinateSpace(_:)` returns a **transparent** `CoordinateSpaceScope`
   (`GeometryChangeScope`'s shape: no node, no identity level, no `StateTable`
   slot; a `Self`-returning legacy decoration after it does not compile —
   divergence 120's footing, as `KF-V` item 1).
2. In **prepaint**, the scope computes its content's frame exactly as
   `noteGeometry` does (union of the nodes, `scrolled`, under the innermost
   open effect's composed map) and pushes a `NamedSpace` — the name and the
   map **window point → space point**: the inverse of the composed map in
   force, then minus the scrolled union's origin — on `Frame.namedSpaces` for
   its content's prepaint, popping after. Effects written after the scope are
   open ancestors at that moment, so they are in the map (G3, G4).
   A degenerate map (a zero scale) pushes an entry that resolves as missing
   (falls back to `.global`) — SwiftUI unmeasured there.
3. **Resolution is innermost-first by name** over that stack:
   `Frame.namedSpace(_:)` in prepaint (geometry, the overlay), and for input
   (hover, gestures) a snapshot taken at registration: while the stack is
   non-empty, `registerHandlers` records the stack under the new hitbox's
   index in `Frame.hitboxNamedSpaces` (empty, and no work, when no scope is
   open — pinned by a work counter); `Window` keeps the last frame's table
   beside `lastHitboxes`. Hit testing does not read it.
4. `GeometryProxy.frame(in: .named(n))` — **amended by `OV-M`**: the
   element's scrolled union mapped through **one** affine (the element's
   composed map, then the space's window → space map), *then* the bounding box;
   never the bounding box of the already-boxed global frame mapped back (G6).

**Cost if wrong.** Under an effect *between* the named container and the
element, MetalUI reports the bounding box in the space — probed since (G7,
`OV-M`): SwiftUI does the same.

## OV-F — `onContinuousHover(coordinateSpace:perform:)`

SwiftUI's spelling (T2, T3) on both vocabularies, default `.local`.
SwiftUI's hover is a recorded broken instrument (probe
`swiftui-platform-services.swift` H1–H11), so the semantics follow the
measured geometry rule: `.local` unchanged (the region's local point, effects
undone); `.global` the window point (content space, divergence 139); `.named`
the window point through OV-E's map from the hitbox's snapshot, `.global` when
the name is missing. `HoverAttachment` gains the space; `.ended` unchanged;
`HoverPhase`'s "only `.local` is offered" sentence goes. A later `.onHover`
keeps the continuous callback **and its space**.

## OV-G — The window's size in the environment: MetalUI-only `windowSize` (clarified by `OV-O`)

**Evidence.** W1: no environment key in a hosted SwiftUI view mentions a size,
window frame or bounds; T5–T8 refuse `windowSize`, `windowFrame`,
`containerSize`, `windowBounds`. SwiftUI's idiom is a `GeometryReader` (or
`onGeometryChange`) on a greedy root.

**Ruling.** `EnvironmentValues.windowSize: Size<Pixels>`, `public
internal(set)`, MetalUI-only (inventory M), zero in a bare value, stamped by
`Window` into the root environment at each build from
`platformWindow.contentSize` (`titleBarInsets`' stamp, never a
`Window.environment` write, which would dirty every draw — pinned by a build
count). Under `.hiddenTitleBar` it is the whole content, band included (the
root is laid out under the bar, divergence 175). A resize already rebuilds, so
the read costs nothing extra.

**Rejected:** documenting `onGeometryChange` on a greedy root as the answer — it
works since C9 (`KF-J`) but needs the root to fill and costs the app a model
write per resize; EP-a asks for the environment and the stamp is a line.

## OV-H — Gestures in a named space

Adding the case would make `ArenaLeaf.point(_:in:)`'s `space == .local ? … :
point` treat `.named` as `.global` **silently**. Ruling: that function becomes
an exhaustive `switch`; `.named(n)` maps the window point through the
hitbox's snapshot (OV-E item 3), `.global` when missing. `DragGesture`,
`SpatialTapGesture` and `onTapGesture(coordinateSpace:)` follow; `startLocation`
and `location` in the same space; `translation` is unchanged (a difference of
two points, `.named` under a rotation rotates it — SwiftUI unmeasured, noted).

## OV-I — EP-a's `.global` frame is already built

`onGeometryChange` with `frame(in: .global)` landed in C9 (`KF-J`, record §88;
`frameInGlobalIncludesAnEnclosingOffsetAndScroll`). C15 adds `.named` only.
MetalCreator's EP-a "element frame in window coordinates" is answered by C9;
the record says so.

## OV-J — Two lanes, coordinates first (amended by `OV-P`)

Lane A (coordinates: OV-D…OV-H) lands first: it owns `Frame.swift` and
`Window.swift` and provides what lane B reads — `Frame.namedSpace(_:)`, the
`NamedSpace` map, and the per-declarer table `Frame.presentationSpaces` /
`Window.lastPresentationSpaces` (OV-K). Lane B (presentation: OV-A, OV-B, OV-K)
owns `Popover.swift`, `AnchoredPresentation.swift`, the new
`AnchoredOverlay.swift` and the demo. Files are disjoint (spec §6).

## OV-K — An overlay's point is placed at layout, in the first frame

**Question.** `.popover` places against the anchor's bounds from the **last**
frame and asks for one more frame when they move (`MN-M` item 2). EP-b opens
the palette at the pointer with the point and the binding written in one input
event: placing from last frame's point would draw one frame at the old point.

**Ruling.** The overlay's **point** is read fresh at layout (it is a value in
the modifier, not geometry); only the mapping from its space to the window
comes from the last frame: `.local` maps through the declarer's own space
recorded in its last prepaint (**amended by `OV-N`**; the bounds-origin
shortcut ignored render effects), `.global` is
the point itself, `.named(n)` maps through the space recorded for the declarer
in its last prepaint (`Frame.presentationSpaces[id]`, resolved by OV-E; the
overlay's own entry is `.global` when missing). So a point written with the
binding appears there in the first presented frame, and a point moved while
open moves the overlay in the frame presenting the move. Only a moving
**declarer** costs the one extra frame `.popover` already pays. A window
resize re-places the overlay (re-flipped) in the frame presenting it — EP-a's
"left where it opened" limit goes.

## OV-L — `CoordinateSpace` keeps `Sendable` through `@unchecked Sendable`; `named(_:)` takes `some Hashable`

**Question.** The spec left open (§2.2) how `case named(AnyHashable)` fits a
`Sendable` enum, and it spelled `NamedCoordinateSpace.named(_ name: some Hashable
& Sendable)` while `OV-D` spelled `some Hashable` — a public spelling unsettled.

**Evidence.** Measured (critic, 2026-10-10, `xcrun swiftc -swift-version 6
-typecheck`): `public enum CS: Sendable, Hashable { case named(AnyHashable) }`
refuses — "associated value 'named' of 'Sendable'-conforming enum 'CS' has
non-Sendable type 'AnyHashable'"; the same for a `Sendable` struct storing one.
SwiftUI's interface (macOS 27.0 SDK, `SwiftUICore.swiftinterface`):
`public enum CoordinateSpace : ~Swift::Sendable { … case named(Swift::AnyHashable) }`,
`public struct NamedCoordinateSpace : CoordinateSpaceProtocol, Equatable, ~Sendable`,
`public static func named(_ name: some Hashable) -> NamedCoordinateSpace`;
`PopoverAttachmentAnchor : ~Swift.Sendable`.

**Ruling.** The payload is SwiftUI's, `AnyHashable`; `CoordinateSpace` is
declared `@unchecked Sendable, Hashable` (MetalUI's existing conformance kept:
dropping it is a source break for an outside `Sendable` type storing a space,
and no MetalUI site reads a name off the main actor — every resolution runs in
prepaint or input dispatch). `NamedCoordinateSpace` is `@unchecked Sendable,
Hashable` and its factory is SwiftUI's exactly, `named(_ name: some Hashable)` —
**no `& Sendable`**. The hole (a reference-typed, non-`Sendable` name moved
across actors by app code) is named in both doc comments. Extra conformances
over SwiftUI's (`Sendable`, `Hashable`, on `PopoverAttachmentAnchor` too, whose
payloads are all `Sendable` values) are additive: code written for SwiftUI
compiles unchanged, so no divergence label. Guard **GA3** gains
`.coordinateSpace(.named(NonSendableName()))` under Swift 6 with a plain import
(red: the factory constrained `& Sendable`).

**Rejected.** (a) Dropping `Sendable` to match SwiftUI's `~Sendable`: a
migration-noted break for nothing MetalUI needs. (b) `named(String)`: loses
SwiftUI's `.named(MyEnum.canvas)` spellings.

## OV-M — A named frame composes the maps before boxing (amends `OV-E` item 4); presentations inherit the stack

**Evidence.** New probe arms (critic, 2026-10-10; run twice, byte-identical,
100 lines; the 90 recorded lines reproduced byte for byte): **G6**, the named
container rotated 30°: global (77.7,93.3,44.6x37.3), **named exactly
(30,30,40x20)** — the bounding box of the global frame mapped back through
−30° would be ≈ 57 × 51, so `OV-E` item 4's literal wording was wrong (at G4's
90° the two rules coincide, so G4 could not separate them). **G7**, the same
30° on the leaf inside the container: the same global, named
(27.7,21.3,44.6x37.3) — the bounding box in the space.

**Ruling.**
1. `frame(in: .named(n))` maps the element's scrolled union through
   `space.toSpace ∘ composed` (one affine) and takes the bounding box once —
   exact for an effect on the container at any angle (G6), the box for an
   effect between (G7). `noteGeometry` therefore hands `GeometryProxy` the
   scrolled union and the composed map (or the named frames it needs), not only
   the boxed `globalFrame`. Test **A4** runs at **30°** (G6's literals; its
   mutation, "box the global frame, then map it", is now separating), and new
   test **A4b** `anEffectBetweenTheSpaceAndTheElementReportsItsBoxInTheSpace`
   pins G7 (mutation: the element's own effect dropped from the composed map).
   The spec's deferral of the "effect between" case is withdrawn.
2. A presentation's content (`.popover`, `anchoredOverlay`, `Deferred`)
   **inherits the named-space stack in force at its declarer** — it is a
   descendant; `PrepaintPass.deferred` resets clip, scroll and render effects,
   not the stack — and resolves against its real window position, so a
   palette's `frame(in: .named("canvas"))` is relative to the canvas. SwiftUI's
   popover content is a separate window (unmeasurable here); MetalUI-only
   semantics, no label (a named space in a presentation is MetalUI's own
   composition). New test **A17**
   `aPresentationsContentResolvesItsDeclarersNamedSpace` (mutation:
   `deferred` clears the stack — it then falls back to `.global`).

## OV-N — An overlay's `.local` point is the declarer's own space, effects included (amends `OV-K`)

**Question.** `OV-K` placed `.local` as "the point plus the declarer's
last-frame bounds' origin" (`previousPresentationAnchors`). Those anchors are
recorded by `Frame.recordPresentationAnchor` with the scroll offset only — **no
render effect**. Under a `.scaleEffect(2)` on the canvas, the pointer
`onContinuousHover` reports in `.local` (effects undone, `Hitbox.localPoint`)
would be placed at half its distance from the origin: the palette would open
away from the pointer, the exact use EP-b names.

**Ruling.** `.local` is the declarer's own space with its effects, the same
meaning hover, gestures and `GeometryProxy` give `.local`: in its prepaint the
declarer records, for an overlay, a `NamedSpace` built from its **own** frame
and composed map (lane A's `Frame.localSpace(of: nodes)`, the scope's
computation factored once) under `Frame.presentationSpaces[id]`; `.named(n)`
records `Frame.namedSpace(n)`; `.global` records nothing. `NamedSpace` stores
both directions (`toSpace` and `toWindow`); placement maps the point through
`toWindow`; a degenerate space places as `.global`. Test **B18** gains a
`.local`-under-`.scaleEffect(2)` arm (mutation: `.local` resolved as bounds
origin + point). `.popover`'s anchor is unchanged (`MN-M`).

## OV-O — `windowSize` is the frame's `contentSize`, drawn chrome included (clarifies `OV-G`)

The stamp is the same `platformWindow.contentSize` the `Frame` is built with
(never a second read that could disagree). It includes everything drawn inside
the content: the `.hiddenTitleBar` band (divergence 175), SDL's 39-point drawn
toolbar strip (`MD-K`), and — when `fix/smk-port-gaps` merges — its drawn menu
bar; an app that wants the area below drawn chrome subtracts
`titleBarInsets`/its own chrome. The merge owes a sentence if C12 rules a
chrome-height environment value. A14 asserts the size equals `contentSize`
under SDL-style toolbar fallback too (a fake answering `setToolbar` `false`).

## OV-P — Lane B owns no `Frame`/`Window` edit; lane A provides the presentation hooks

Lane B needs from `Frame`: `namedSpace(_:)`, `localSpace(of:)`,
`recordPresentationSpace(_:for:)` and `previousPresentationSpaces`; lane A adds
all four (and `Window.lastPresentationSpaces`) with a unit test each in
`CoordinateSpaceTests` (A18 `presentationSpacesAreCarriedToTheNextFrame`;
mutation: not carried). `PopoverModifier`'s stored properties change (lane B):
`swift package clean` before the native build that follows, per CLAUDE.md.

## OV-Q — Lane A's spellings of the hooks (refines `OV-E` item 3, `OV-H`, `OV-N`, `OV-P`; item 2 amended by `OV-R`)

**Question.** The spec named the hooks; three spellings were left to lane A.

**Ruling.**
1. `Frame.localSpace` has two overloads: `localSpace(of bounds: Bounds<Pixels>, name:)
   -> NamedSpace` (an element with its own `bounds` in hand — lane B's
   `PopoverModifier.prepaint`) and `localSpace(of nodes: [LayoutNodeID], name:) ->
   NamedSpace?` (`nil` for no node — the scope). Both take the bounds unscrolled,
   in the current offset, and map through `scrolled` and the innermost open
   effect's composed map. A degenerate map gives a `NamedSpace` whose `toSpace` is
   `nil`; `NamedSpace.resolve` and `Frame.namedSpace(_:)` treat it as missing
   without falling through to an outer space of the same name. `noteGeometry`
   shares the union computation (`Frame.union(of:)`), not `localSpace`.
2. A gesture arena takes its members' snapshots **by owner id**
   (`GestureArena.init(…, namedSpaces: [GlobalElementID: [NamedSpace]])`, built by
   `Window.makeGestureArena` from `lastHitboxNamedSpaces` at the target's, the
   draggable's and each joining ancestor's index): the stack in force at an
   element's registrations is fixed by its ancestors, so every hitbox of one id
   carries the same snapshot. Hover keeps it per region (`HoveredRegion.namedSpaces`).
3. Two mutation sites in the spec's table were re-spelled to sites that exist:
   A8's "each entry's push dropped" is "each entry's node record emptied" (the
   push is in the shared `prepaintGroup`, so only the record separates the
   entries, `GeometryChangeScope` B14's shape); A16's "named value excluded from
   `isEqual`" has no such site (the store compares the transform's value) and is
   "the entry built without the composed map" (a container move then changes the
   value and re-reports). A3, A16 and A18's second arm share that mutation.

**Cost if wrong.** Internal only; no public spelling.

## OV-R — Lane A review: no draggable snapshot; the headless frame stamps `windowSize` (amends `OV-Q` item 2, clarifies `OV-G`)

**Question.** The lane-A review found three lines no test reddened and one
unstamped path: (X1) the joining ancestor's snapshot in
`Window.makeGestureArena`; (X2) the draggable-above snapshot there; (X3) the
rule that a degenerate innermost space never falls through to an outer one of
the same name; and the headless `renderFrame`, which never stamped
`windowSize` although it renders "exactly as one frame of a window of `size`
would" (`XP-C`).

**Ruling.**
1. X1 and X3 are pinned: A19
   (`anAncestorsGestureResolvesItsNamedSpaceWhenAChildIsPressed`, MetalCreator's
   tile inside a `.named("canvas")` pan) and A20
   (`aDegenerateInnermostSpaceReadsGlobalAndNeverFallsThrough`). The rules stand.
   Measured on `d709a34`, full unfiltered native suite (3229 tests, clean 270.0 s):
   X1 reddens exactly A19 (3 issues, 272.0 s); X3 exactly A20 (1 issue, 213.1 s);
   dropping `renderFrame`'s stamp exactly A21 (2 issues, 235.6 s). For the record
   (§92, Record phase).
2. **The arena takes no snapshot for the draggable above the target.** A
   non-opaque draggable region is registered only for an element that is not a
   pointer target (`Frame.registerHandlers`, `!handlers.isPointerTarget`), so
   every gesture it carries is a `.draggable`, and a draggable leaf never
   resolves a coordinate space (`press`/`move`/`release` read only its
   `pressPoint`). An element with a `.draggable` and a `.named` `DragGesture` is
   a pointer target: its opaque hitbox is the target itself (A12's case). The
   line was dead, so it is removed rather than pinned; `OV-Q` item 2's "the
   draggable's" index is struck. A future draggable that reads a space restores
   it with a test.
3. **`renderFrame` stamps `windowSize = size`**, as a `Window` stamps its
   `contentSize` (`OV-O`): a tree sized from `@Environment(\.windowSize)` renders
   the same headless. Pinned by A21 (`renderFrameStampsWindowSize`; red before,
   0 wide). The `windowSize` doc comment says so.

**Cost if wrong.** Item 2: a draggable gaining a space-reading recognizer
reports window points until the snapshot returns. Item 3: none for existing
callers — no production tree read `windowSize` before this branch.


## OV-S — A `.local` or `.named` overlay waits one frame for its declarer's space (refines `OV-K`)

**Question.** `OV-K` maps a `.local`/`.named` point through the space the
declarer recorded in its **last** prepaint, "`.global` when absent". On the
first frame a declarer is laid out there is no last prepaint, so "absent" means
two things: no space yet, or a name no ancestor declares.

**Ruling.** The two are told apart by the anchor map every `PopoverModifier`
already records (`previousPresentationAnchors`, `MN-M` item 2): with no last
anchor, a `.local`/`.named` overlay is not produced and the frame asks for one
more (`.popover`'s own rule, test 3.14's shape), so it never draws one frame at
the raw point; with a last anchor and no recorded space (a missing name) or a
degenerate one, it places as `.global` (`OV-E`). A `.global` overlay needs
nothing from the last frame and presents in its first. The space is recorded in
every prepaint, presented or not, so the usual case — the canvas laid out long
before the click — places the point written with the binding in the frame
presenting it (B17). A presented overlay whose recorded space changed asks for
one more frame, as a moved anchor does. Pinned by B22 (frame 0 empty, frame 1
placed) and B17.

**Cost if wrong.** An overlay presented from the very first frame of a window
appears on the second (as `.popover` does today).

## OV-T — Guard G3.2 is re-spelled: `.popover` takes `attachmentAnchor:` (supersedes `MN-L` item 3)

`MN-L` item 3 ruled that `.popover` takes no `attachmentAnchor:`, pinned by
guard G3.2 `aPopoverHasNoAttachmentAnchorParameter` (an `attachmentAnchor: 0`
call refused). `OV-B` adds SwiftUI's argument, so that guard's claim is false.
The spec's "every `PopoverCompileGuards` test unchanged" was wrong for G3.2.
**Ruling**: G3.2 becomes `aPopoversAttachmentAnchorTakesOnlyAPopoverAttachmentAnchor`
— an `Int` anchor is still refused, now naming `PopoverAttachmentAnchor`, and
`.point(.center)`/`.rect(.bounds)` compile (positive control); its mutation
MG3.2 is unchanged (an `attachmentAnchor: Int = 0` overload makes the negative
compile). The guard count does not move. The menus decisions doc's `MN-L`
item 3 and the inventory map's `popovers` row are owed a "superseded by
`OV-B`" note in the Record phase.
