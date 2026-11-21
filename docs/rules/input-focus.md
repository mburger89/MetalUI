# Input, focus, hit testing, controls

Sharded from `CLAUDE.md` on 2026-10-29; paragraphs are verbatim. "(above)"/"(below)" refer to the
old single-file order: find a prefix with `grep -n '<PREFIX>-' docs/rules/*.md`. Detail, pinning tests and
history for each paragraph: record §69 (same heading), §19, §01; newer ones cite their own record.

**Controls** (`Button`, `Toggle`, `Slider`, `Stepper`, `Picker`, selectable
`List`) sit on `Binding` and the existing handler machinery: one hitbox each,
all focusable (Tab reaches them; **a click does not focus them**, as SwiftUI's with Full Keyboard Access off:
a control records no focus interactions, so `focusesOnPress` leaves it out, `FC-A`), one keyboard table `ControlKeys.swift` running after a caller's `onKey`
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
`EnvironmentValues` field). **The automatic `Picker` is the pop-up** (`SR-B`; `.pickerStyle(.segmented)` is the old look), and **the `.switch` knob slides on a fixed spring the transaction does not drive** (`SR-D`: `animatedNumbers`, `disablesAnimations` snaps, reflected with its track under right-to-left).

**`ScrollViewReader`/`scrollTo`** (`DD-G`…`DD-K`): one identity slot; a proxy
reaches only its own subtree; keys compared by value (`AnyHashable`); resolved
next frame against the first match; only the nearest scroller moves. `scrollTo` under `withAnimation` glides: `ScrollState.glide` is read by every phase through `ScrollChrome.currentOffset` on the frame's timestamp and keeps the link with `noteActiveAnimation`; a wheel ends it (`SP-F`).

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

**Gesture composition (`GE-`, record 178).** `sequenced(before:)` gates the second member behind the first (`ArenaLeaf.isGated`): it records and acts on nothing until the first ended, a failed
first fails the sequence, and a drag in the second starts at the **first pointer event after the gate** (the gate-opening move or release is replayed to it). A custom `Gesture` is a `body`; a MetalUI
recognizer is an internal `PrimitiveGesture` and `_recognizers()` is not a protocol requirement. A composite is `.hooked(node, CompositeHooks)` and reports once per event (the arena's `flush`
after the event's leaf callbacks), resetting its `updating` states before `onEnded`; a **new composite gesture builds its node hooked, taps its members, and must settle (reset) on end, failure and cancel**.
`DragGesture.Value.velocity` is a 3:1 blend of the last two sampled intervals over **event timestamps** (`MouseEvent.timestamp`; tests stamp `now`, never sleep); a nil stamp falls back to the last tick.
`GestureMask` is not built (`GE-H`).

**Drag and drop** (`DN-`, record §68): MetalUI's own synchronous
`Transferable`/`ContentType`. A draggable is a **non-opaque** gesture-arena
member that begins on the first move. The destination is found by the one
ranking (`DN-F`); destinations register inside the disabled gate and outside
`allowsHitTesting`. **A new `StyledElement` site must paint through
`paintDecoration`** or it drags with no preview (`DN-X`). An SDL test takes
`SDL_EVENT_DROP_*` from C-exported constants and arms
`armMainRunLoopExitCheck()`. **`DropDelegate`** (`DE-`, record §192):
`onDrop(of:delegate:)` writes the same `Handlers.dropDestination` field, so the
outermost wins and no registration site is new; every callback runs from input
through `StateDispatch.dispatching`, and `Window.retarget`/`untarget`/`deliver`
are the one place (`DE-B`). A drop wrapper silences a wrapper directly inside it
(`DropDestinationWrapping`, `DE-G`). **A new `PlatformWindow` drop feedback is
`setDropOperation(_:)`, defaultless**; a conformer owes it (`DE-H`).

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

**Focus.** A primary press focuses a `.focusable()` element (`.automatic` or `.edit` interactions, SwiftUI's click focus, `FC-A`,
divergence 94 retired), a `TextField`/`TextEditor` and a selectable `List`, not a control and not `.activate`. Focus leaves with its identity and does not return
(`IX-I`: a focused `.focusable()` that is removed clears focus where SwiftUI moves it to an existing one, divergence 217, `FC-G`); a `List` row out of window keeps it. **The first drawn frame seats the first
`.focusable()`** (`.automatic` or `.edit`, behind the disabled and hidden gates, not a control, `.activate`, text field or `List` row (`Frame.listRowDepth`), a `ScrollView`'s content included; topmost by final position, ties in tree order, and nothing when a `List` precedes the winner in tree order (a list holds the first responder, `I13`..`I13v`); `Frame.registerHandlers`
notes the candidate, `Window.seatInitialFocus` assigns it before `reconcileFocusStates()`, once, whether or not a candidate exists; divergence 186 narrowed, `FC-E`, `FC-F`) — a plain assignment, no `StateTable` write, no harness flag turns it off. `@FocusState` writes apply from
input, before the next frame. `.hidden()` removes focus/Tab/keys but not a
keyboard shortcut. Keys go Keymap → `onKeyPress` (outermost first, `KF-C`) →
focused field's editing keys → bubbling `onKey` (controls' `ControlKeys` there) → unclaimed Tab traverses
(`FocusRegistry.tabOrder`). With nothing focused `onKey` sees nothing; a new test that needs nothing focused calls `window.focus(nil)` after its first draw.

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
**Pointer extras (`PH-`, record 188).** `columnResize(directions:)`/`rowResize(directions:)` lower to the plain resize for both
directions, a one-way seam case (`columnResizeOneWay`, `rowResizeOneWay`) for one (`leading` is the left, unmirrored, as
`frameResize`) and the arrow for the empty set. **`pointerVisibility(_:)` rides `PointerAttachment`** (no `Handlers` member): `.automatic`
attaches nothing, the innermost of `.hidden`/`.visible` wins, the style and the visibility resolve independently in the one walk
(`pointerUnderPointer`, the cover eligible when opaque, hovering, or carrying a style *or* a visibility), a press holds the pressed
chain's pair, a drawn alert or menu shows the pointer, and a hidden pointer resolves to the seam's `PlatformPointerStyle.hidden`,
sent on a change and followed by one `.arrow` when the pointer leaves the window. A new pointer-region field counts in
`pointerStyleRegionCount`, or a frame with only that region resolves nothing. No new `PlatformWindow` requirement: a seam case, so an
outside exhaustive `switch` owes three arms (`docs/migration.md`).

**Key and focus scoping (`KF-`, record §88).** `onKeyPress` (SwiftUI's five spellings,
`KeyPress`, `FocusInteractions`) runs **after the Keymap and before a focused field's editing
keys, outermost handler first** (the opposite of `onKey`'s bubble); a command's ⌘-key is declined
by it and runs the command, a `Button`'s ⌘-key and every native-only menu item stay after it
(`KX`, divergence 188); a typed character on a focused field is offered once as `.down`, one
grapheme, never during composition (`KF-Q`, divergence 187). **The key chain** is the focus chain,
else the innermost `.hoverKeyRegion()`'s (the one ranking, found on demand at a key or press, never
per pointer move) and feeds the Keymap's contexts, actions and `onKeyPress` **only** — `onKey` and
every control's keys still need focus (`KF-U`). A `.focusable()` element focuses on a
primary press in the non-claiming `focusOnPress` stage (`.edit` and `.automatic`, which plain
`.focusable()` records explicitly; `nil` is a control's and stays out, `FC-A`); a press elsewhere does not resign a focused field (SwiftUI, `KF-G`). Proposal
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
element side as `AXNode.colorWellHint`/`roleHint` (internal, stripped in
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

**Segmented `Picker` selected fill (`SD-`, record §187).** The selected segment paints `PickerScope.selectedSegmentFill` (`.surface` in a light scheme, `.textPrimary` at 0.18 in a dark one), never a bare `.surface`: in the dark theme `.surface` is darker than the `.surfaceSecondary` track and the selected segment read as less selected. A control painted on a `.surfaceSecondary` track picks its raised fill by luminance order against the track in both schemes. **The selected segment also draws a 1-pixel `PickerScope.selectedSegmentEdge` border** (`SD-C`, record 260: `.textPrimary` at 0.10 light / 0.12 dark, AppKit's `separatorColor` alphas), so it keeps an outline when the page, `.surface` and the track nearly coincide; it does not reach 3:1 against an equal page.

**Identifiers on containers (`DA-`, record §166).** An `accessibilityIdentifier` on a plain container is distributed over its descendants, overwriting theirs, as SwiftUI does; to identify a container and keep the children's identifiers write `.accessibilityElement(children: .contain)`. A control that fills its own node (`TextField`, `TextEditor`) uses `AXNode.fillControl` so a declaration never costs it its role or text; a `SecureField`, if added, must pass `value: nil`.

**Hit testing under a projective effect (`PJ-E`, record §193).** `Hitbox.contains` maps the window point through the inverse homography; a point with `w <= 0` hits nothing. Geometry and accessibility frames are the bounding box of the projected quad.

**Suggestion overlay (`SOC-`, record 234).** `.suggestionOverlay(isPresented:edge:alignment:spacing:)` is a `PopoverModifier` that is **not** registered in `Frame.openPopovers`: it takes no key, no focus and is never dismissed by input (the app writes the binding from `onKeyPress` on its field); a press on it keeps the focused field focused (the press-time focus stage only clears for a key region on the cover's own layer) and never reaches what lies beneath; a new presentation that must not capture keys likewise skips `registerOpenPopover`.

**The wheel goes whole to one axis (`XS-F`, `XS-G`, record 236).** `dispatchScrollChain` takes the axis from the latch's lock (the dominant component of the scroll's first event) or, phaseless, from the event itself, and hands the wheel to the nearest scroller on the chain that declares that axis, has content past its viewport (`Hitbox.scrollTakes`) and room in the wheel's direction (`scrollRoom`, from last frame's prepaint); a scroller that cannot passes it up, the innermost one without room takes it only when nobody above can. `.onScrollWheel` handlers keep the raw event; the multi-line editor takes the vertical axis only; a custom scroller through the public `registerScrollRegion` declares both directions open. A new scroller registers through the `chrome:offset:contentSize:` overload. **A two-axis scroller declares `scrollAxes` both and room open both ways on every axis it takes, so it never chains at its edge (probe `N9c`-`N9f`) but passes a wheel on an axis its content fits (`XS-F` addendum, record 237); `Window.scroll` writes the slot the wheel's axis names and reports `didScroll` for the primary slot only.**

**Tab strip (`TBS-`, record 238).** `TabStrip` selects, closes (button, middle click) and reorders (drag, `onMoveTab(from, to)` once at the release with the index after the move) by input only and binds no key; a tab's width is `TabStripWidthLayout` (natural clamped 96...220, content proposed the clamped width, because a flexible frame lets a title overflow under an unspecified proposal); a state write from a geometry or selection change goes through `onGeometryChange`/`onChange`, never a phase. An unselected tab's ink is `textPrimary` at 0.64, the least that reaches 4.5:1 hovered (`TBS-K`, record 257).

**Keys during an IME composition (`KF-AB`, record 247).** `Window` gates nothing on a composition: AppKit offers a key to the input context first (a consumed key never arrives) and SwiftUI delivers a declined one to `onKeyPress` (probe `swiftui-onkeypress-marked-text.swift`, no real IME attached); SDL, which sends keys and `TEXT_EDITING` separately, does not forward a non-⌘/Ctrl key while marked text is non-empty (`SDLWindow.suppressesKey`). No `KeyPress.isComposing`.


**Tab strip context menu (`TBS-O`, record 323).** `TabStrip.tabContextMenu { id in ... }` (MetalUI-only, class M, no divergence) gives each tab, close slot included, a `ContextualModifier` menu built at each open for that tab's id; a secondary press selects and closes nothing, an empty menu opens nothing, show-menu is advertised only with a menu.

**Button border shape (`BY-L`, `BY-M`, `SD-E`, `TBS-M`, record 294).** `.buttonBorderShape(_:)` (`ButtonBorderShape`: `.automatic`, `.capsule`, `.roundedRectangle`, `.roundedRectangle(radius:)`, `.circle`) is an environment write read by bordered, prominent and glass `Button`s and so by `Menu` and the menu `Picker`; the radius is written at paint from the bounds (ring, wash, border follow), `.automatic` is byte-identical, `.plain`/`.borderless`/`.link`/custom styles and the segmented `Picker` ignore it. A segmented picker's shape is the MetalUI-only `.segmentedPickerShape(_:)`; a tab strip's selected tab is `TabStrip.selectedTabShape(_:)` (`.rectangle` default).

**Menu picker chevron (`BY-O`, record 306).** A menu `Picker`'s ` ⌄` is in a `flexShrink = 0` box and the title truncates first: the indicator never disappears. **Menu picker title (`BY-P`, record 307).** The selected value's title floor is capped at 24 (it truncates), so the picker's own title never wraps; SwiftUI shortens the capsule first.

**Tab strip paint (`TBS-N`, record 299).** `TabStrip.stripBackground(_:)` and `.selectedTabFill(_:)` take a `TabStripPaint` (`.automatic` byte-identical, `.clear` draws no bar rectangle, `.color`, `.material`); never name a strip modifier `background`. `ButtonBorderShape` is not a `Shape` and has no `.buttonBorder` (class R).

**`DisclosureGroup` (`OG-A`, `OG-D`, `OG-F`, `OG-H`, `OG-J`, record 311).** `DisclosureGroup` is an `ElementGroup` over a `Component` body (`DisclosureGroupBody`), so its uncontrolled state is the body's `@State` slot at the group's id (collapsed initially); the label row is a plain `Button` (focus, Space, press, disabled gate) whose `axNode.roleHint = .disclosureTriangle` (the existing optional role-hint enum, because a new `Bool` grew `AXNode` past its pinned size) publishes `.disclosureTriangle` with value `"1"`/`"0"`, and the chevron is a glyph swap with `accessibilityHidden(true)` (an unhidden symbol folds "Forward" into the row's label). Content is `@escaping` and called only while expanded; the expansion is written only from input, a click writes bare (snaps, D3c unmeasured) and `withAnimation` fades the content through the `XF-H` default unit. **Inside a content `List`** (`OG-E`, `OG-J`, record 314) the label row is the list's: a 13 wide chevron cell that toggles (an `onTapGesture`, so it is not a focus stop: the list is the single focusable, `FC-F`, and a row click focuses it), the rest of the row selects; ↑↓ move over the visible rows and reveal the lead, a hidden selection keeps the id and the next key starts from the end (`P-K7`); ← → and ⌥ are lane 5.

**An outline `List`'s disclosure keys and accessibility (`OG-E`, `OG-F`, `OG-M`, record 315, divergence 1086).** ← → and ⌥ act on the lead row through `ControlKeys.outlineDisclosure` (composed after `listMove`; ⇧, ⌘, ⌃ decline) and `LazyUnitSource.lazyDepth`/`lazyDisclosure` (input time, no realisation): → expands a collapsed group, ← collapses or selects the parent (`ListSelectionController.select(position:)`), ⌥ cascades. **A content list never writes a binding for a group it has not built**: a cascade is a request in `list/$listcascade` that the next build carries out (`OutlineCascade`: the group and everything below it built open, each write queued through `LifecycleStore.enqueue`, one drain); a data outline walks its data and writes its state slots in the key's turn. The chevron is an `onClick` (a tap gesture reads no modifiers) inside `accessibilityHidden`. **Accessibility:** a row's hint is `AXNode.outlineHint` (three bytes, stripped like the other hints; never a new `Bool` or `Int` on `AXNode`/`Handlers`); expand and collapse ride an `AccessibilityDisclosure` `Action` handler (behind the disabled gate), the builder derives `disclosedBy` from the levels of the realised rows and synthesises the cell and triangle; a content row ADOPTS the records made inside it (`Frame.withAccessibilityAdopter`). AccessKit levels are depth + 1.

**`contextMenu(forSelectionType:menu:primaryAction:)` and `ClickDispatch.clickCount` (`OG-G`, `OG-N`, record 317).** A list takes the modifier from its own `handlers.contextual?.selection` or the environment (`selectionContextMenu`) in layout, only when `I` equals its row identifier type (else inert), and gives each row a contextual attachment (menu for `row in selection ? selection : [row]`, read at each open, never selecting) and its click handler the primary action after the selection click when `ClickDispatch.clickCount == 2`; Return (no modifiers, non-empty selection) runs it from the list's `onKey`. `clickCount` rides `Window.runClick(_:on:modifiers:clickCount:)` from the mouse-up (and the arena's `.click` callback); an accessibility press reads 1.

**`onKeyPress` on any `ElementGroup` (`KF-AC`, record 316).** The five spellings exist on every `ElementGroup` (a `some ElementGroup` helper, a scope); each wraps the group once in a default-`Style` `ModifiedElement` layer and returns that `StyledElement`, so later keyboard modifiers join the layer; it hears keys as an ancestor of the focused element (outermost first, `KF-C`) and does not make the group focusable. `StyledElement`, `ProposalElementGroup` and `KeyboardModifier` keep their own, more specific overloads.

**`onKeyPress` on a proposal chain joins it (`KF-AD`, record 319).** On a proposal `ModifiedContent` chain, or a `LifecycleScope` over one, the five spellings add or join one `LayoutModifier.keyboard` layer and return `Self`: no `KeyboardModifier`, no element request per frame. A `KeyboardModifier` written over the chain (`.focusable()`) takes the layer's handlers (the focus target owns them). `onKeyPress` on the proposal-group and `ElementGroup` overloads is `@_disfavoredOverload` so a two-call chain is not ambiguous.

**`onKeyPress` in generic code folds too (`KF-AE`, record 321).** `ElementGroup.onKeyPress` returns `KeyPressed` and calls `_addingKeyPress`, a requirement: a chain, a `LifecycleScope`, an `AccessibilityModifier` and an `OverlayModifier` take the handler on their own layer (no element request), whatever the static type at the call. Only a group with no layer (`Pair`, `ForEach`, `EquatableComponent`) keeps `KF-AC`'s wrapper.

**A wrapper modifier after a lifecycle scope over a chain joins the chain (`KF-AF`, record 352).** `LifecycleScope`'s `LayerBase`/`ProposalBase` are `LifecycleScope<Content.LayerBase>`/`…ProposalBase` and its `_wrap`/`_wrapLayout` go through `ElementGroup._wrapInScope`/`ProposalElementGroup._wrapLayoutInScope`, so `….onKeyPress{}.onDisappear{}.frame(…)` is one chain over a scope, not a second chain around it (+1 request a frame before). Pinned by `HandlerChainFoldCostTests` and `ElementGroupKeyPressCostTests` A-C.

**`keyCapture` hears a key before every other stage (`TRM-U`..`TRM-Y`, record 338).** `keyCapture(except:optionAsMeta:)` marks the keyboard layer it joins on every conformer family `onKeyPress` joins; while the focus chain holds a marked layer, `Window.dispatchKeyCapture` offers the key to that layer's `onKeyPress` handlers (outermost layer first) ahead of the Keymap, the `KF-X` decline, field keys, `onKey`, the clipboard, shortcuts, commands, F10, Tab and `onInput`, and on AppKit ahead of the main menu. `.ignored` (once, never twice), an `except` match or composing marked text sends the key through the unchanged pipeline. A new key stage goes after capture, and a new `onKeyPress`-like spelling must carry the marker.

**A shifted shortcut matches the unshifted key plus Shift on every platform (`KF-AL`, record 356).** `KeyEvent.unshiftedKey` is the layout's key with no modifiers (AppKit: `UCKeyTranslate`, filled while Shift is held; SDL: its keycode), and `KeyboardShortcut.matches` takes the characters path or `.shift` + `unshiftedKey`, so `("/", .shift)` fires on ⇧/ on AppKit and SDL while "?"/"P"-spelled shortcuts keep firing; AppKit's ⇧Tab "\u{19}" is read as "\t". A new matcher over key events must go through `matches`.

**An unclaimed pointer move that changes nothing asks for no frame (`FP-T`, record 360).** `Window.pointerEventChangesNothing`: same topmost opaque hitbox, no state written by the event (`StateTable.writeCount`; `withState` raises no dirty itself), tooltip idle and no window `onInput` -> no `setNeedsRedraw()`, so the move costs 0 frames and 0 state writes (the retention writes belong to frames). A new input handler that writes state through `withState` relies on that count to keep its frame. A drag that changes nothing asks for no frame either (`FP-U`, record 386): an unclaimed `.mouseDragged`, or a secondary or other drag the button arena claims, under the same guards; gestures redraw through the state they write, and a callback that changes window-owned state (`active`, a session) calls `setNeedsRedraw()` itself (`.beginWindowDrag` does).

**A shortcut's text is one formatter (`KF-AG`, record 355).** `ShortcutText.format` serves both `KeyboardShortcut.displayText(for: KeyboardShortcut.Platform)` and the drawn menu's `MenuPanel.shortcutText`: `⌃⌥⇧⌘K` on macOS, `Ctrl+Super|Win+Alt+Shift+K` elsewhere, named keys as glyphs or names, F1...F35, other keys upper-cased only when still one character. Modifiers show as stored (`.primary` is compile-time); `Platform.primaryModifiers` builds another platform's shortcut.

**Function keys are `KeyEquivalent.f1`...`.f20` (`KF-AH`, record 367).** AppKit's `U+F704`...`U+F717`; SDL maps F13 to F20 (`0x4000_0068`...`0x4000_006F`) in `SDLKeys.named`; `Keymap.namedKeys` spells `f13`...`f20`; there is no Fn modifier.

**`.focused` on a container (`FW-`, record 365).** A `.focused($x)` / `.focused($x, equals:)` on a non-focusable container reads true / the value while focus is on it or any descendant (`Window.reconcileFocusStates` walks the focused id's parents), and writing it focuses its first focusable descendant; so a pane wrapper around a `TerminalView` needs no parameter on the view. No element request, one write per change.

**Which keys are taken is a read of the platform lists, the bar and the commands (`KF-AI`, record 363).** `KeyboardShortcut: Hashable` (class A; `"P" != "p"`); `conflicts(with:)` is equal modifiers and the same key lower-cased, ⇧Tab `\u{19}` as Tab, and with Shift a shifted key as its US base key; `KeyboardShortcut.systemReserved(on:)` is a fixed per-platform list naming `.command`/`.option` outright (never `.primary`); `App.standardMenuShortcuts()` and `commandShortcuts()` walk `evaluateMenuBar`'s `PlatformMenuItem`s in the platform's arrangement (each read evaluates the `commands` content once, and calling one inside it recurses; disabled and submenu command items are included); a drawn bar also claims F10, Shift-F10 and the Menu key; `ClaimedShortcut.isConditional`/`condition` mark a key owned only sometimes.

**`ShortcutRecorder` records the next chord as a `KeyboardShortcut` (`KF-AK`, record 366).** Recording is having focus (`@FocusState`; a press, Tab or an accessibility activate), built on `keyCapture` so ⌘Q records and no menu item or `Button` shortcut runs; any key records in one form (the unshifted base key lower-cased plus the modifiers, ⇧Tab `"\t"`), bare Escape is `onCancel`, bare ⌫/⌦ `onClear`, bare Tab and ⇧Tab move focus on (a cancel), focus loss or the window leaving `.key` is one `onCancel` and never after a record. **It is `.focusable(interactions: .activate)` plus an `onClick`, not `.edit`, because `.edit` is a first-draw seat candidate (`FC-E`) and the window would open already recording.** `Equatable` over the shortcut and label (closures not compared); an idle recorder costs 0 extra element requests by default (the public type wraps its field in `.equatable()`; MetalUI has no automatic Equatable retention).

**A code view's keys are read from its key table (`KF-AJ`, record 364).** `CodeView.builtInKeyBindings(platform:)` asks `CodeEditing.command(for:platform:)` about every key and modifier combination (never a second list) and returns source-`.codeView` claims in the base-key form, cached per platform family; Escape, find next/previous and the text-changing commands are `isConditional` with a condition string.

**`.restoresFocusOnDismiss()` returns focus to where it came from (`KF-AM`, record 374).** A transparent scope (no node, no identity level): focusables register under the innermost one through a frame-local stack; entering a scope from outside records the element focused before, leaving it another way discards the record. At `IX-I`'s drop and `resolveFocus`'s (`Frame.dropFocus`), when the dropped element's scope was not produced this frame and its record is focusable, focus moves there and one extra frame paints the ring; scope stays, record gone or no scope is today's drop (probe `F2`), nested scopes restore the innermost. No scope costs one `isEmpty` check per focusable.

**Modifier change and the pointer style (`TRM-BO`, record 384).** `Window.currentModifiers`' change is told to every pointer attachment with a `modifiersChanged` (package) and, for a flags report, key or scroll, resolves the pointer style again at `lastMousePosition` (the platform call only: no frame, no build); nothing is visited when the frame has no pointer-style region. A view whose `styleProvider` depends on the modifiers stores them from that hook rather than observing them with `onModifierKeysChanged`, which is a rebuilt frame.

**A `Table`'s selection, keys and menu are `List`'s, driven over positions (`TBL-N`..`TBL-Q`, `TBL-Y`, `TBL-Z`, record 390).** The body is focusable only when the table selects or has a `contextMenu(forSelectionType:)` of its id type; a click selects through `ListSelectionController` (a position cache of 8 verified with one read, the optional `ListRowSpace.firstSelected` so an empty selection reads nothing), ↑ ↓ move and reveal the lead by position through a `TableLeadReveal` request the body resolves before its rows, Page Up/Down/Home/End scroll only, ← → and typing (divergence 1109) do nothing, and a sortable column's header click writes `sortOrder` once. Nothing in a steady frame reads a row for input.

**A `Table` column resizes by a drag on its divider and its headers do not reorder (`TBL-R`, `TBL-S`, `TBL-AA`, record 391, divergence 1111).** The divider is a 6-point hit area over the column's trailing edge with the `.columnResize` pointer, registered by the header row AFTER every cell so its far half ranks above the next header's click; a fixed-width column has none. The drag writes the table's `@State` `columnState.widths` only when the clamped width differs from the last one written (the drag's start, key and last value live in a reference the state's `==` ignores), so a drag that changes nothing draws nothing; no new `withState` site. There is no reorder gesture: SwiftUI's `allowsColumnReordering` is false by default (probe `R1`) and there is no MetalUI switch.

**A `Table` with `tableActiveCell` is in cell mode, and an edit ends exactly once (`TCM-A`..`TCM-K`, record 394).** Class M, no divergence: a table without the binding is PRs B to E byte for byte. The active cell is the caller's binding, written once per move (never for a move to the same cell) and revealed on both axes clear of the header and the frozen columns; its ring is inside its box (2 points accent when the table or its editor is focused, 1 point secondary when not) and keyed to (row id, declared column), never to a window slot. Cell keys run before PR C's row keys and decline to them; while an edit is open the body's key handler declines everything. **The editor is one `TextField(axis: .vertical)` owned by the table body** (named `$tableEditor` under it, placed by position, so cell recycling never reaches it); it takes focus from inside the frame (`Frame.seatFocus`). An edit is a `TableEditSession` whose `isOpen` flips before any callback: Return, ⇧Return, Tab (the editor's `onKeyPress`), a click on another cell or on the empty space, focus leaving the editor (an after-frame `onChange`-style note), the table leaving the hierarchy or its window closing (an after-frame `onDisappear`-style note) each commit once, Escape and the caller's `editing = nil` cancel; `Window` has no key-resign event, so none commits. A row that no longer resolves leaves the edit open and the editor on its last frame (the position verified with one read, then `tableRowIndex`, then one scan). Every frame still realises the whole window (`TBL-M`): the cost pins are builds times the steady window, not zero.

**A `Table` publishes its logical counts, a header row first and each realised cell as its own node (`TBL-T`, `TBL-AB`, record 392, divergence 1107).** The table's fields ride the `AXEmission` (`AXTableInfo`), not `AXNode`, so `AXNode` and `Handlers` keep their pinned sizes; they are made only while `collectsAccessibility`, and a table with no client records nothing. The table node is recorded at the body's id over the VIEWPORT, after the body's own handlers; every realised row carries `logicalIndex`; a cell records before its content so the content's elements and identifiers are its children in every mode (a cell-mode cell's click stays `synthesizesAccessibility: false`); a header cell folds its title like a button and hides its sort chevron. The builder puts the header row first and orders a row's cells by column (frozen cells prepaint last). In cell mode the active cell is selected and is the published focus while the body holds the window's focus; the editor prepaints inside `withAccessibilityAdopter(<its cell>)`. AppKit is `AXTable` with `AXTableRow` rows when `columnCount` is set (a `List` stays `AXOutline`); AccessKit counts the header row in `row_count` and `row_index`.

