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

**Next unused id: `OV-L`.**

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

## OV-C — `presentationBackground(_:)` is not built (deferred)

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

**Ruling.** Add `case named(AnyHashable)` — SwiftUI's case set exactly.
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
4. `GeometryProxy.frame(in: .named(n))` = the bounding box of the element's
   global frame mapped through the space's map (exact under translation; under
   a rotation of the container itself the element's own composed map includes
   it and the inverse undoes it, G4).

**Cost if wrong.** Under an effect *between* the named container and the
element (not probed), MetalUI reports the bounding box in the space — the same
choice `.global` already makes (`KF-J`, G4a). A probe arm can refine it later.

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

## OV-G — The window's size in the environment: MetalUI-only `windowSize`

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

## OV-J — Two lanes, coordinates first

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
comes from the last frame: `.local` adds the declarer's last-frame bounds'
origin (`previousPresentationAnchors`, as `.popover`'s anchor), `.global` is
the point itself, `.named(n)` maps through the space recorded for the declarer
in its last prepaint (`Frame.presentationSpaces[id]`, resolved by OV-E; the
overlay's own entry is `.global` when missing). So a point written with the
binding appears there in the first presented frame, and a point moved while
open moves the overlay in the frame presenting the move. Only a moving
**declarer** costs the one extra frame `.popover` already pays. A window
resize re-places the overlay (re-flipped) in the frame presenting it — EP-a's
"left where it opened" limit goes.
