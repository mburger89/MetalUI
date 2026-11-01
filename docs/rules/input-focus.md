# Input, focus, hit testing, controls

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Controls** (`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, selectable
`List`) sit on `Binding` and the existing handler machinery: one hitbox each,
all focusable (Tab reaches them; **a click does not focus them**, divergence
94), one keyboard table `ControlKeys.swift` running after a caller's `onKey`
declines, the `.disabled` gate in `Frame.registerHandlers`. Accents and focus
rings read `controlActiveState` (`ControlLook.swift`). `Button` has `role:`,
`.buttonStyle` (`.plain`/`.borderless` drop chrome by value), a pressed wash
and `.keyboardShortcut` (fires even when hidden; gated by `isEnabled` only).
**Styles are open protocols applied through the environment** (`BY-`, record 174): `ButtonStyle`,
`PrimitiveButtonStyle` (the style owns the click via `trigger()`, `Button` registers no `onClick`) and `ToggleStyle`
are built at layout into one erased `Box` that keeps the control's handlers, focus ring and disabled scope; a custom
button's `isPressed` is read from `Frame.pointerOwner` (the previous frame's hitboxes) and corrected by one frame; the
built-ins are `PrimitiveButtonStyle`/`ToggleStyle` structs `Button`/`Toggle` draw themselves, a new built-in look goes in
`ButtonLook`/`ToggleLook`, and a new style writer uses a **custom environment key** (`setCustom`, never a new
`EnvironmentValues` field).

**`ScrollViewReader`/`scrollTo`** (`DD-G`…`DD-K`): one identity slot; a proxy
reaches only its own subtree; keys compared by value (`AnyHashable`); resolved
next frame against the first match; only the nearest scroller moves.

**Hit testing.** One hitbox list, one ranking: `topmostHitbox(in:at:where:)`
(`topmostOpaqueHitbox` is its specialization; drag-and-drop uses it too) —
**never a second lookup**. `onClick`, `textInput`, `valueTrack` make an opaque
target; the keyboard gate is separate. A wheel over a non-scrolling target
passes to its nearest same-layer ancestor scroller (`DD-Y`).
`allowsHitTesting(false)` gates only `registerHandlers`' pointer hitbox
(`OM-AK`), per layer; an accessibility press still runs (`IX-Z`).
`contentShape` takes any `Shape` (`IX-L`). Handlers outlive the frame:
`.onClick { window.x() }` is a retain cycle.

**Gestures** (`IX-B`…): `TapGesture`/`LongPressGesture`/`DragGesture` and
composition, beside (not replacing) `onClick`. One arena per press from the
one ranking plus the target's ancestors **in its own hit layer** — a
`Deferred` presentation's press does not reach a declaring ancestor's gesture
(`IX-Q`). Callbacks run under `StateDispatch`.

**Drag and drop** (`DN-`, record §68): MetalUI's own synchronous
`Transferable`/`ContentType`. A draggable is a **non-opaque** gesture-arena
member that begins on the first move. The destination is found by the one
ranking (`DN-F`); destinations register inside the disabled gate and outside
`allowsHitTesting`. **A new `StyledElement` site must paint through
`paintDecoration`** or it drags with no preview (`DN-X`). An SDL test takes
`SDL_EVENT_DROP_*` from C-exported constants and arms
`armMainRunLoopExitCheck()`.

**Accessibility (`AB-`, `IX-U`…).** Nothing recorded until a client activates
the window (sticky). Synthesized nodes are records (`Frame.axEmissions`),
never `axNodes` or `$ax` (`AB-U`). Every `NSAccessibility` override answers
through `mainActorAnswer(_:fallback:_:)`, never a bare `assumeIsolated`
(`AB-AE`). A hidden layer suppresses everything inside
(`Frame.suppressingAccessibilityIfHidden`). A text-painting conformer passes
`accessibleText:`. Both bridges translate every neutral field — enforced by a
`Mirror` count; a new `AccessibilityNode` field needs a row on both bridges.
Qualify `MetalUIPlatform.AccessibilityRequest` in files importing AppKit.
`AXNode.actions`/`AXActionKind` are deprecated. **An agent cannot run
VoiceOver or claim the validation** (`IX-AE`).

**Focus.** Clicking does not focus, except `TextField`/`TextEditor`, a
selectable `List` and `.focusable(interactions: .edit)` (`KF-F`). Focus leaves with its identity and does not return
(`IX-I`); a `List` row out of window keeps it. `@FocusState` writes apply from
input, before the next frame. `.hidden()` removes focus/Tab/keys but not a
keyboard shortcut. Keys go Keymap → `onKeyPress` (outermost first, `KF-C`) →
focused field's editing keys → bubbling `onKey` (controls' `ControlKeys` there) → unclaimed Tab traverses
(`FocusRegistry.tabOrder`). With nothing focused `onKey` sees nothing.

**Input follow-ups (`IF-`, record §93).** `SpatialTapGesture.Value.modifiers` (the last
press's), `SpatialTapGesture.Value.clickCount` (its platform click count, `IF-O`) and `DragGesture.Value.clickCount` (the press's, never the move's) are MetalUI-only
values (divergence 235); `onCancelled` on drag, magnify and rotate runs **once, only for a
leaf that had reported**, from a dropped primary arena, a replaced stale button or pinch arena,
a `.mouseMoved` while a button arena is live (a lost release), key loss and window close —
never for a disabled gesture or a removed owner (`IF-E`, `IF-K` 3; divergence 236; the
reset is `@GestureState`, `GS-`). A wheel scroll **latches** to the cover of its `.began` through its momentum
(`ScrollLatch`, `IF-G`) and ends with a synthesized `.cancelled` to the latched handlers on key
loss or close (`IF-H`); the platforms send `.modifiersChanged` on becoming key (`IF-I`).
`onModifierKeysChanged(mask:initial:_:)` is one transparent `ModifierKeysScope` (the shape of
`GeometryChangeScope`; `$modkeys<depth>` a `LifecycleStore` key, never a `StateTable` slot):
`Window.currentModifiers` comes from every key, pointer and scroll event and the flags report,
drops to `[]` on leaving key, dirties the window **only when the last build held a scope**, and
the action runs in the lifecycle drain after the build; SwiftUI's timing is **unprobed**
(human check IF1, `IF-D`). A `.modifiersChanged` event returns before the hook's blanket
`setNeedsRedraw()` unless the app's `onInput` claims it (`IF-N` item 3).

**Window drag (`WD-`, record §97).** `WindowDragGesture` is SwiftUI's spelling (no
`.windowDragArea()`): one arena leaf, live in a **press** arena only, an opaque pointer target on
its element's hitbox, **ready at a `tapSlop` move** and blocked as a draggable is (a tap, long
press or click ahead yields, an undecided `DragGesture` ahead wins). When it acts it ends,
runs the `onCancelled` of members that had reported, fails the rest (divergence 275) and
`Window` calls the defaultless `PlatformWindow.performWindowDrag() -> Bool` then
`endPressForDrag()` **whatever the answer**. AppKit answers `true` only while dispatching the
mouse-dragged of a held primary press (`performDrag(with:)` with its mouse-down, the unproven
call, check WD1); SDL answers `false` (divergence 276: its drag is a hit-test region, `CW-E`; before `CW-` no region list:
`WD-F`). `AS-J`'s band drag is unchanged (unclaimed presses only); the three gates are the
gesture rule and `.opacity(0)` does not disable it (divergence 277). Not built:
`windowBackgroundDragBehavior` (a Scene modifier), a double-click zoom in a handle.

**Continuing press cancel (`GC-`, record §100).** A reported leaf owes `onCancelled` whatever
ends it. `GestureArena.press(… continuing: true)` takes `cancelCallback(leaf)` before it fails an
undecided drag (`GC-B`), and `Window`'s `.mouseDown` treats a press that finds the arena **still
pressing** as a lost release, not a tap sequence's second press: `abandon()` and a fresh arena
form, as for a press on another element (`GC-C`; SwiftUI agrees, probe `swiftui-lost-release.swift`).
A real double-click (arena released) still continues. A bare `.mouseMoved` does not cancel the
primary arena (rejected, `GC-C`). No public API, no divergence.

**Resign on press (`RF-`, record §98).** `.resignsFocusOnPress(_ isEnabled: Bool = true)`
(`StyledElement` returns `Self`; proposal content merges into the one `KeyboardModifier` layer,
`KF-H`) is an opt-in container modifier: a primary press inside it resigns a focused field and
**routes no key by hover**. It is `KeyboardAttachment.resignsOnPress` (every factory carries all four
fields; `Handlers` keeps nineteen members) registered by the same non-opaque region and gates as a
key region and counted apart (`resignRegionCount`, never `keyRegionCount`: `hoveredKeyRegion`,
`keyChain`, `coversKeys(withPressRegions: false)` and `onKeyPress` routing are untouched, `KF-U`,
test 2b); it widens only `focusOnPress`'s region predicate, so `KF-E` item 5's ladder holds (a text
field or click-focusable inside focuses directly, one change and no `nil` between) and the one
ranking is the only lookup. A secondary or other press never resigns (`MN-B`), a `Deferred`
presentation's press does not reach a region below (`IX-Q`), a `Button` inside fires **and**
resigns. MetalUI-only (class `M`, no divergence): SwiftUI has no such modifier (probe
`swiftui-resign-on-press.swift`); `KF-G`'s default stands. Rejected: `hoverKeyRegion(routesKeys:)`
(`RF-B`); not built: a per-subtree opt-out, a window option.

**Input APIs (`CI-`, record §81).** `SpatialTapGesture`, `MagnifyGesture`,
`RotateGesture` and `DragGesture(minimumDistance:coordinateSpace:button:)` live
in the one arena (`IX-B`), which has three modes: a **press** arena fails pinch
leaves; a **pinch** arena (formed from the one ranking at a `.magnify`/`.rotate`
event) runs only pinch leaves, ordered per kind; a **button** arena (a secondary
or other press) runs only that button's drags. A press of the arena's own button
or a `.began` of an active pinch kind replaces a stale arena (`CI-AB`).
Locations are local (`Hitbox.localPoint`); `.global` is the content space
(divergence 139); magnification is additive from 1, rotation clockwise-positive.
**`MN-B` holds**: a secondary or other press reaches only the menu stage,
outside-dismissal, the tooltip, hover and a drag naming its button; a context
menu waits for the release only when a secondary drag is declared on the chain
(`CI-F` item 4). **`.onScrollWheel` (`-> Bool`, `true` claims) dispatches
innermost first along the cover's chain from `topmostHitbox`**: each id's
handler before its scroll region, so a handler on a scroller's *content* can
veto it and one on or around the scroller sees nothing (`CI-AH`; `DD-Y` kept); a
declining handler falls through to its own element's opaque hitbox and `TI-H`
scroll, and a pinch recomputes hover and the pointer style (`CI-AL`).
**`.pointerStyle(_:)` resolves with hover through the one ranking** (innermost
wins, a press holds the pressed chain's style, sent only on a change, forgotten
on exit) through the defaultless `PlatformWindow.setPointerStyle(_:)`; SDL has
no hand or zoom cursor (`MOVE`/arrow, `CI-H` item 8), no rotate, no pinch on
Windows and no wheel phase. Both new regions sit inside the disabled,
`allowsHitTesting` and `hidden()` gates. `CoordinateSpace.named` is built (`OV-D`, below); the image
cursor is built (`IC-`, below), and `shape(_:eoFill:size:)` is carried (`IC-G`).

**Key and focus scoping (`KF-`, record §88).** `onKeyPress` (SwiftUI's five spellings,
`KeyPress`, `FocusInteractions`) runs **after the Keymap and before a focused field's editing
keys, outermost handler first** (the opposite of `onKey`'s bubble); a command's ⌘-key is declined
by it and runs the command, a `Button`'s ⌘-key and every native-only menu item stay after it
(`KX`, divergence 188); a typed character on a focused field is offered once as `.down`, one
grapheme, never during composition (`KF-Q`, divergence 187). **The key chain** is the focus chain,
else the innermost `.hoverKeyRegion()`'s (the one ranking, found on demand at a key or press, never
per pointer move) and feeds the Keymap's contexts, actions and `onKeyPress` **only** — `onKey` and
every control's keys still need focus (`KF-U`). `.focusable(interactions: .edit)` focuses on a
primary press in the non-claiming `focusOnPress` stage; plain `.focusable()` does not (divergence
94, narrowed); a press elsewhere does not resign a focused field (SwiftUI, `KF-G`). Proposal
content (`MetalView`, `GPUSurface`) takes the keyboard modifiers as **one `KeyboardModifier`
layer** that every further keyboard modifier merges into (`KF-H`, divergence 185), registered
inside `sharingRegistrationsWithEffects`. A Return with the platform's shortcut modifier is not a
`TextEditor` editing key (`KF-Z`). `.onGeometryChange` is a transparent `GeometryChangeScope` (no
node, `$geometry<depth>` a `LifecycleStore` key, never a `StateTable` slot): the value is noted in
prepaint and the action runs in the lifecycle drain, so the first presented frame carries what it
wrote (`KF-J`); a decoration after it is a layer of its own outside the measurement (`ES-J`, divergence 120 retired). `TimelineView(.animation)` calls `noteActiveAnimation()`, never
`requestAnotherFrame()`; other schedules wake the window once through `TimelineStore`
(`$timeline<depth>`, `AnimationStore`; `KF-K`). **`for` over an opaque-returning helper in a
builder is a Swift 6.4 defect, not fixable in the builder** (`KF-M`, guard C1): use `ForEach` or a
concrete helper.

**Overlays and coordinates (`OV-`, record §92).** `CoordinateSpace.named` and `.coordinateSpace(_:)` (a
transparent `CoordinateSpaceScope`: no node, no id level) resolve against the **nearest ancestor so
named**, moving with scrolls and effects; a missing or degenerate space reads `.global`, never an
outer one of the same name; a frame composes the maps **before** boxing (`OV-M`); hitboxes snapshot
the named stack only while a scope is open, and a gesture arena takes the snapshot of each member
and joining ancestor (`OV-H`, `OV-Q`). `onContinuousHover(coordinateSpace:)`, named
`onGeometryChange`/`DragGesture`/`SpatialTapGesture` and the MetalUI-only
`EnvironmentValues.windowSize` (the frame's `contentSize`, chrome included; `renderFrame` stamps it
too) belong to it. **`anchoredOverlay(at:in:anchor:)`** (MetalUI-only, both vocabularies) is a
`PopoverModifier` of kind `.overlay`: no panel, border, shadow or padding; the point is resolved
**at layout**, a `.local`/`.named` one through the declarer's recorded space one frame later
(`OV-K`, `OV-S`); flipped per axis then clamped; dismissed by an outside press of any button that
**still lands** (the popover stage runs before the menu, text-input and value-track stages) and by
Escape, never claiming a key; a press on the declarer dismisses and reaches it. `.popover` takes
SwiftUI's `attachmentAnchor:` (divergence 225). `presentationBackground(_:)` is not built (`OV-C`).

**Controls and looks (`LK-`, record §85).** `Slider(onEditingChanged:)` runs
`true` at a press or an edit's first key and `false` once at its end, one pair per
gesture: the end runs at the top of `Window`'s input hook for `.mouseUp` **and**
`.mouseDown`, and on close; `ValueTrackTarget.edit` is the one closure, so
`Handlers` keeps its size (`LK-Q`, `LK-U`). `ColorPicker` is a drawn well and a
drawn popover panel on every platform (divergence 165; edits write gamma-sRGB
literals; `LK-C`, `LK-D`); the well's and `ProgressView`'s roles reach the
element side as `AXNode.colorWellHint`/`progressHint` (internal, stripped in
`registerHandlers`, `LK-G`), and a new `AccessibilityRole` owes a row on both
bridges. The spinner steps by the frame clock only while visibly painted
(`LK-F`); keyframes are a transparent scope whose records live in
`AnimationStore` (`$keyframes<depth>`, never a `StateTable` slot; `LK-I`);
`phaseAnimator` is built (`GS-H`). **A gradient is rasterized on the CPU through the
image path** (Oklab table; a one-texel strip when linear along one axis, else a
full raster in `RasterCache`; no shader change; `LK-J`); `.blur(radius:)` is per
leaf with sigma = radius, the shadow pipeline in colour keyed by
`Frame.keyLeaf(…colours:)` (a GPU surface leaf draws unblurred, divergence 167;
`LK-K`); a `Material` is a tint over a **real backdrop blur** (`BB-`, below;
divergence 166; `LK-L`). **A new stored property on `Decoration` goes in
`DecorationExtras`** (the 1 MB thread, `LK-W` item 10); a new
`CapturedPrimitive` or `LayoutModifier` kind owes its arm in both fade
flattenings (`multiplyAlpha`, `RenderEffect.apply`).

**Menu anchor under render effects (`MA-`, record §156).** Class `A` by MetalCreator's expectation (unprobed, `MA-E`), no public API, no seam, no platform edit, no divergence (855-864 untouched). **A presentation anchor (`Menu`, `Picker(.menu)`, `.popover`/`anchoredOverlay`) and a context-menu record are the label's drawn window bounds**: one function, `Frame.presentationWindowBounds(_:ownEffects:)` = `effectBoundingBox(of: scrolled(bounds))`, never private `activeOffset` arithmetic at a new site (`MA-B`; a legacy element passes its own effects, `MA-G`); a pure-translation retained replay shifts replayed anchors by its own delta (`windowShift`, `MA-H`), the affine and layout-shift arms still refuse `presentationAnchor`/`contextMenus` (`MA-D`). Pins count the point (`MenuAnchorTests`); a real pop-up is group `MA`.

**Picker option identifiers (`SE-`, record §165).** A segmented `Picker` option's accessibility identifier is the content's own, else `<picker id>.<tag>`; the fold applies to the `.radioButton` role only. Put `.accessibilityIdentifier` on the content before `.tag(_:)` (`TaggedElement` is not a `StyledElement`); menu-style pickers record options without nodes (`SV-P`). A split view's divider drag is covered under `HS-` in `layout.md`.

**Identifiers on containers (`DA-`, record §166).** An `accessibilityIdentifier` on a plain container is distributed over its descendants, overwriting theirs, as SwiftUI does; to identify a container and keep the children's identifiers write `.accessibilityElement(children: .contain)`. A control that fills its own node (`TextField`, `TextEditor`) uses `AXNode.fillControl` so a declaration never costs it its role or text; a `SecureField`, if added, must pass `value: nil`.
