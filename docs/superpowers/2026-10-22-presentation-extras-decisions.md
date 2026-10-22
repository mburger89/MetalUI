# Presentation extras — decisions

Rulings for item BG (round 2 item 7, user request 2026-10-21; carried gaps `OV-C`, `WD-A`, `IC-G`; not a plan task). Spec:
[`specs/2026-10-22-presentation-extras-design.md`](specs/2026-10-22-presentation-extras-design.md). Record: `../record/144-presentation-extras.md`. Branch `feat/presentation-extras` from `dd9a072f`. Evidence: `docs/probes/swiftui-presentation-extras.swift` (compiled form, screen
**locked**, output in its header; arms `B0`–`B9`, `D` arms), `docs/probes/swiftui-presentation-extras-typecheck.sh` (`T0`–`T4`, the interface census),
the earlier `swiftui-overlays-coords.swift` `B0`–`B2` (`OV-C`'s evidence), `swiftui-window-drag.swift`, `swiftui-image-cursor.swift`.
**gpui** has `anchored` (no panel, so nothing to colour: it models `anchoredOverlay`, `OV-A`) and `window.start_window_move()` on a mouse-down
(the app decides per element; no scene-level switch): nothing is claimed from gpui for the three items.
Divergence labels **735–744 reserved**; 735–737 are planned (rows written in the lane that builds them), 738–744 unused.

Prefix **`BG-`**, lettered. **Next unused: `BG-T`.** (Moves in the commit that appends a ruling.)

**Carried.** `OV-C` (the deferral this closes: "a fill only, the border and shadow kept"), `CR-T`/`Frame.beginPresentationPreferences` (a presentation
collects its own reports), `AS-D` (first report in post-order wins), `MN-M` item 5 (the panel), `MT-` (every material site draws through
`Frame.fillMaterial`), `WD-A`/`WD-E`, `AS-J` (the band press), `CW-E`/`CW-J`/`CW-V` (hit-test regions, carved by blockers, never a second lookup),
`IC-A`/`IC-F` (a cursor compares by identity; a rebuilt value is one cursor), `IC-G`, `IX-` (one ranking), `RW-` (an open popover is retention-ineligible).

## BG-A — `presentationBackground` is built for the popover only

**Question.** `OV-C` deferred it with no owner. Which of MetalUI's presentations can carry it?

**Evidence.** SwiftUI's modifier is declared for sheets, popovers, confirmation dialogs' hosts (interface census: `View`, macOS 13.3). On a macOS
popover it recolours the whole panel (`B2`: left = right = top ring pixel, content pixel changed), and `.clear` keeps the frame (`OV-C` B1). MetalUI's
presentations: `.popover` (a `Box` panel, `MN-M` item 5), `anchoredOverlay` (no panel by design, `OV-A` item 1), `.alert`/`.confirmationDialog`/
`.fileImporter` (a closed set of `Text` and buttons, not views, so no content exists to carry the modifier; AppKit shows native sheets), context
menus (`MenuContent`, a closed set). No `.sheet`.

**Ruling.** Only `.popover` (both vocabularies) reads it. An `anchoredOverlay` ignores it (no panel; the modifier is accepted and paints nothing, pinned);
the drawn alert and menu panels are not views and never see it. A future `.sheet` reads the same channel (`BG-B`).

**Rejected.** (a) Painting a fill for an `anchoredOverlay` from it: SwiftUI's own answer keeps chrome (`OV-A`'s rejection of a chrome-less spelling
stands), so the modifier would mean something SwiftUI does not give it. (b) A per-alert background: the alert's body is not a view.

**Cost if wrong.** Small and additive: another site reading the channel.

## BG-B — The channel: a reported preference, innermost wins, collected per presentation

**Evidence.** `B7` (inner `.red`, outer `.blue`): red, the **innermost** (first reported in post-order) wins; `B4` (the modifier on the declarer, outside the
popover's content): every pixel equals `B0`'s, no effect.

**Ruling.** A new `EnvironmentWrite.presentationBackground(PresentationBackgroundSpec)`: changes no value, reports to the frame **after** its content builds,
exactly `navigationTitle`'s shape (`AS-D` item 6), into a slot opened by `Frame.beginPresentationPreferences` and closed by `endPresentationPreferences`
(the `CR-T` bracket `AnchoredPresentation.requestLayout` already runs): the first report inside the bracket is kept, the slot is read by the chrome in
paint (stored in `LayoutState`), and a scope **outside any presentation bracket reports nothing** (`B4`). The main tree's slot is never written, so no window
state, no `Window` read and no graft/audit counter moves (`BG-F`).

**Rejected.** (a) A new `Handlers` member or a `Decoration` field: it is not a per-element paint, and `Handlers` stays nineteen. (b) A last-wins slot:
`B7`. (c) Reading through `@Environment`: SwiftUI's is a preference, and an environment value would reach siblings.

**Cost if wrong.** The innermost-wins arm is one `if slot == nil`; an inversion is one line and one test.

## BG-C — Paint: the fill only; border and shadow stay; a material goes through `Frame.fillMaterial`

**Ruling.** `AnchoredPresentation.paint` fills the panel rect with the spec instead of `theme[.surface]`; the 1-pt `.separator` border, the radius-10 corners
and the shadow are unchanged (`OV-C`, `B2` kept the frame; MetalUI's border is the frame). Colour and `ColorToken` resolve through `PaintPass.resolve` (a
token follows the scheme, `CR-`); a `Material` draws through `Frame.fillMaterial` (`MT-`: with Reduce Transparency its opaque grey and no backdrop record, a
change snaps) with the panel's corner radii, then the border is drawn as its own stroke-only rect so a backdrop fill and the border do not need one primitive;
a gradient draws through the existing gradient-image path clipped to the rounded panel (`LK-J`). **The shadow is under the fill in every case**; a translucent
fill shows the shadow through it, as `B9`'s glass shows what is behind (SwiftUI's panel is glass, MetalUI's is the window's content: pinned as values, looks in
check `BG1`).

**Cost if wrong.** A look; one function.

## BG-D — Spellings: the concrete-colour set, plus `alignment:content:`

**Ruling.** On `ElementGroup` (one extension, as `navigationTitle`): `presentationBackground(_ color: Color)`, `(_ token: ColorToken)` (the `CR-D` twin, a guard),
`(_ material: Material)`, `(_ gradient: LinearGradient)`, `(_ gradient: RadialGradient)` and
`presentationBackground(alignment: ProposalAlignment = .center, @ProposalContentBuilder content: () -> some ElementGroup)`. There is no generic
`<S: ShapeStyle>` because MetalUI has no `ShapeStyle` (divergence 119, `CR-A`; the overload set is the existing spelling of every colour-taking site).
`B3`: the content spelling also fills the whole panel (a flexible `Color` fills); `B8`: the content is **proposed the panel's size and placed by the alignment**,
not stretched (a fixed-width `HStack` sits at the leading edge, the rest of the panel shows the chrome fill).
**Not offered:** a `ShapeStyle`-generic overload, `.foregroundStyle`-style hierarchical styles, `.tint`.

## BG-E — The content spelling's identity and layout

**Ruling.** The reported content is built by `AnchoredPresentation` as a **sibling layout node** under its own id, `GlobalElementID.child(of: owner, at: 0, name:
"$presentationbackground")` — a name, never `-1` (`MC-P` reserves it) and never a `StateTable` slot (the seven stay) — requested after the content's node in
the same presentation run, with a `ProposalLayout` that proposes the chrome node's measured size, places it at `alignment`, and answers the chrome's size
(the background never changes the panel's size: `B8`, same panel size as `B3`). **A site that mints a named id owes `StateTable.noteNamed` and an arm in
`everyNamingSiteStartsAReturningNameFresh`** (pinned, `theContentBackgroundNameIsReturnedFresh`); its `@State` is reset when the popover closes (`ID-C`'s
rule for removed content). It paints **before** the panel's content and after the fill, inside the rounded clip of the panel (`clipShape` of the panel rect).
**If `noteNamed` cannot hold it (a state read of the background content survives a close) the lane stops and reports**: the content spelling is then carried
with the measured reason and the colour spellings ship alone (`BG-A`…`BG-D` do not depend on it).

## BG-F — Retention: nothing in `Retained*.swift` moves

**Ruling.** An open popover is retention-ineligible by name (`RW-`'s list), so a graft or replay never skips the popover's build and the report always
runs. A scope outside a presentation reports nothing, so an `.equatable()` occurrence containing a stray `.presentationBackground` builds, replays and grafts as it
did (pinned: `aStrayPresentationBackgroundDoesNotChangeARetainedOccurrence`, work counters equal to the same tree without it). No `BuildAudit` channel, no
`BuildJournal` event, no `ReplayKey` field. Sibling item C14-j (`Retained*.swift`) is untouched.

## BG-G — `windowBackgroundDragBehavior`: SwiftUI's three values; only `.enabled` drags

**Evidence.** The D arms (a real SwiftUI `App`): with `.enabled` a press-drag on the content background makes AppKit log "Window move completed without
beginning" (a window move was requested), also with `.hiddenTitleBar` and on a `Text`; with no modifier, `.automatic`, `.disabled`, and a hidden title bar alone,
it never does. `isMovableByWindowBackground` is `false` in every arm: SwiftUI does not use AppKit's flag. The modifier is `Scene`-only (`T2` refused on a View, `T3`
compiles); `WindowInteractionBehavior` is `automatic`/`enabled`/`disabled` (census).

**Ruling.** `public struct WindowInteractionBehavior: Sendable, Hashable` with the three statics (class A, macOS 15 spelling) and
`Window.backgroundDragBehavior: WindowInteractionBehavior` (default `.automatic`; class M — MetalUI has no `Scene` type, its scene analogue is `Window`'s
options beside `windowStyle`/`drawsWindowControls`, divergence 736). `.automatic` and `.disabled` are the same: no background drag. `.enabled`: a primary press
that **no stage claimed** (the end of `onInput`'s path, the one rule of `AS-J`: no opaque hitbox under it from the one ranking, `active == nil`, no gesture
arena) asks the platform to drag the window. A change dirties nothing visible and republishes regions once (`BG-I`).

**Not probed, ruled and labelled (check `BG4`):** whether a press on a control under `.enabled` moves the window in SwiftUI (the `enabledButton` arm cannot
separate a button that fired from one that did not). MetalUI's answer follows the one ranking: **an opaque target (a control, a text field, a scroller, a
draggable, a destination) never drags**; the instrument for this is the existing `WindowDragGesture` rule set, unchanged (a handle's arena wins).

**Cost if wrong.** A press on a control that SwiftUI would drag from does not drag: additive to loosen.

## BG-H — AppKit: the `AS-J` call, not `isMovableByWindowBackground`

**Ruling.** On AppKit the background press calls `platformWindow.performTitleBarPress(clickCount: 1)` (`AS-J` item 2: acts only while the host view is
dispatching a primary mouse-down, `performDrag(with:)` with that event; `clickCount` 2 on the background does **nothing**, the double-click action belongs to the
title bar). **Rejected:** `NSWindow.isMovableByWindowBackground = true` (SwiftUI does not use it, the D arms; it would move the window from every pixel of the
one host view and ignore the one ranking and every blocker, so a click on a button would drag). No new platform requirement: `performTitleBarPress` exists and
every conformer answers it (`HT-X` 1 stands; the headless platform already records `titleBarPresses`).

## BG-I — SDL: one more region candidate, carved by every blocker, no backdrop exemption

**Ruling.** With `.enabled`, `ChromeRegions.compute` gets a second candidate, the whole content rect, carved by **every** blocker (`blocks(_:)`), **without** the
band's backdrop exemption: a window-wide opaque backdrop (an `onClick` on the root) blocks the whole candidate, as a press there needs the pointer (the band's
exemption exists because the bar floats over content, `CW-V`; the background has no such reading). `WindowDragGesture` handles are candidates as today (carved
only by blockers above them). The list is published through the same `setWindowDragRegions` on change only (`CW-E`), is `[]` while a popover, drawn alert
or menu is up (existing rule), while the window is zoomed (`PlatformWindow.isZoomed`: no move by a maximised window's background; the band keeps its rule) and when
the platform said it does not use regions. The 64-rect cap (`ChromeHitSnapshot.maximumRegions`) is the existing `ChromeHitMap.carve(limit:)` behaviour; a
carve that would exceed it drops the **background** candidate whole before any handle or the band (a region that is too fragmented to publish is no region: an
over-cap background is never a partial one), counted by a test. Hover, wheel and pointer-style regions are not blockers, so they lose their pointer events inside
the region (divergence 425's rule, divergence 737 for this extension); a text selection is an opaque target and blocks.

**Rejected.** Hit-testing the background by an `SDL` event hook after the fact: SDL's callback runs on its thread before `Window` sees the press (`CW-E`).
**Cost if wrong.** Pointer events inside an enabled window's background never reach hover handlers on SDL: documented (`737`), human check `BG2`.

## BG-J — The title band is untouched

**Ruling.** `AS-J`'s band press (a primary press in the hidden title bar's band, double click action) and `CW`'s band region are unchanged by the behavior, `.disabled`
included. SwiftUI's own band behaviour under `.disabled` is **unprobed** (the D arm `hidden` reads only that a hidden title bar alone gives no *background* drag; the arm presses the
content, not the bar), so this is a ruling, not a measurement: `.disabled` means "no background drag", not "no drag". Pinned: `theTitleBandKeepsItsDragWhateverTheBehavior`.

## BG-K — `PointerStyle.shape(_:eoFill:size:)` exists on visionOS only; MetalUI offers the spelling as a MetalUI-only extension

**Question.** `IC-G` carried it: SwiftUI's `size:` default, colour and hot spot were "unprobed".

**Evidence.** The interface census and `T1`: `public static func shape(_ shape: some Shape, eoFill: Swift.Bool = false, size: CoreFoundation.CGSize) -> PointerStyle`
is `@available(visionOS 2.0, *) @available(macOS, unavailable)`; `T1` on macOS is `error: 'shape(_:eoFill:size:)' is unavailable in macOS`, the control `T0` (`.image`) compiles.
**There is no SwiftUI-on-macOS behaviour to probe** — no default size (it has none: `size` is required), no colour parameter, no hot-spot parameter; visionOS's pointer is a
system effect over the gaze/pointer and cannot be run on this machine (colour, outline and hot spot are unmeasurable here, `IC-G`'s three questions have no macOS answer).

**Ruling.** Build it as **MetalUI's own extension of the visionOS spelling** (class M, divergence 735: SwiftUI-on-macOS has none; the look is ours):
`PointerStyle.shape(_ shape: some Shape, eoFill: Bool = false, size: Size<Pixels>, hotSpot: UnitPoint = .center, fill: Color = .black, outline: Color = .white)`.
`size` is in points (MetalUI's `Pixels` are points, as `windowSize`), required as SwiftUI's. The three extra parameters have defaults, so a visionOS-shaped call
`shape(s, eoFill: x, size: z)` compiles unchanged. Defaults are an ordinary arrow-cursor look: **black fill, a 1-pt white outline around it** (visible on every
background); `.center` hot spot (a shape pointer is centred on the pointer, as visionOS's is under its gaze).

**Rejected.** (a) Carry it again: the cost the carry feared (a probe half-day) is gone because the probe answer is "does not exist on macOS". (b) Not offering the
spelling and an `.image`-only recipe: `IC-G`'s stated additive route is cheap now. (c) A `Color`-less shape: a cursor needs an opaque, contrasting look.

**Cost if wrong.** Class M additions are additive; the defaults are changeable (they are values in one place and pinned in a test).

## BG-L — Rasterization: `MetalUIPath`, CPU, at the window's display scale

**Ruling.** The shape's `path(in: Bounds(0, 0, size))` becomes a `Path` (a clamp: size components non-finite or `<= 0` make the style `.default`; each clamps at **128 pt**,
the SDL/AppKit practical cursor limit). Fill by `PathRaster.fill(rule: eoFill ? .evenOdd : .nonZero, antialiased: true)`, the outline by `PathRaster.stroke` of the same
geometry with width `2` pt (centred, so 1 pt shows outside the fill) drawn first, then the fill over it; both through a `RasterScratch` borrowed from a throwaway cache (**not**
the window's `RasterCache`: a cursor is not a frame leaf and must not touch `lastTexturesMade`/`touchedImages` counters). The bitmap is `(size × scale) + 2 × ceil(1 × scale)` pixels
each way (the outline's margin), `scale` = the window's display scale rounded **up** to an integer (`displayScale` of the frame the window last built, 1 before the first), the
image's `scale` is that integer so `pointWidth` is `size + 2` pt and the hot spot is `(1 + hotSpot.x × size.width, 1 + hotSpot.y × size.height)` points: the shape's own
point at the pointer. Pixel format: premultiplied RGBA8 sRGB (`AI-E`), built through `ImageBitmap(width:height:rgba:)` (straight alpha, which `ImageTexture` premultiplies once).

## BG-M — Resolution at send time; one cursor per value; no seam requirement

**Ruling.** `PointerStyle.Kind` gains an internal `.shape(ShapeCursorSpec)` (Hashable by the path's geometry value, `eoFill`, size, hot spot, fill and outline bit patterns):
`PointerStyle` equality and `Hashable` stay derived, so a shape rebuilt every frame is **the same style** and `updatePointerStyle` sends once (`IC-A`/`IC-F`). `Window.sendPointerStyle`
resolves a `.shape` into `PlatformPointerStyle.image(PlatformCursorImage)` through a window-owned **`ShapeCursorCache`** keyed by `(spec, integer scale)`, an LRU of **8** (SDL's table is 8, the
AppKit window's 16), holding the `PlatformCursorImage` so the same texture identity reaches the platform cache (`IC-A` 2). `PlatformPointerStyle` is unchanged: **no new
requirement, no migration note**, AppKit and SDL need no code (the image cursor already serves both, `IC-`), the headless platform records the resolved `.image` (`IC-I`). A scale change
(a window moved between displays) is a new key, resolved and sent on the next send (the existing re-send on re-entry, `CI-S`).

**Rejected.** A `PlatformPointerStyle.shape` case with per-platform rasterizers: two rasterizers and a seam case for a pure function of its key (`TE-AD`'s reason in the other direction).

## BG-N — What is not built

`presentationBackground` on `anchoredOverlay`, alerts, menus (`BG-A`); the `<S: ShapeStyle>` generic (divergence 119); animated shape cursors; a shape stroke style
beyond the outline; `windowBackgroundDragBehavior` per scene/`Scene` modifier (MetalUI has no scene type); background drag while zoomed on SDL and in fullscreen (`BG-I`;
AppKit's `performDrag` does nothing in fullscreen); `isMovableByWindowBackground` (`BG-H`); a drag from a control (`BG-G`, check `BG4`). Owners: none, each additive.

## BG-O — Critic pass: what was attacked and what stands

**Re-run.** `swiftui-presentation-extras-typecheck.sh` re-taken on 2026-10-22 (T0 compiles, T1 unavailable in macOS, T2 no member, T3/T4 compile): the header matches. The D arms need
an unlocked screen and are not re-taken (the screen is locked); `BG-G` rests on the recorded output, and check `BG4` stays owed.
**Checked, no defect:** no Apple type in a portable surface (`Size<Pixels>`, `UnitPoint`, `Color` are MetalUI's); no new `PlatformWindow`/`Platform`/`WindowRenderer` requirement, so no default or
fake owed; no shader; no C enum; each spelling difference from SwiftUI (`Window` property for a `Scene` modifier, the extra `shape` parameters, no `ShapeStyle` generic) has a ruling (`BG-D`, `BG-G`, `BG-K`).
**Pinned in the lane, not a design change:** on SDL the platform moves the window before `Window` sees the press (`CW-E`), so the `.enabled` background press must not also call
`performTitleBarPress` there (it answers `false`; test 25 and the SDL region test read it). Test 33's mutation is read by the raster counter, not memory. Lanes stay two, disjoint by file.

## BG-P — Lane 1 build: a material panel has no drop shadow; the gradient and the border

**Question.** `BG-C` said "the shadow is under the fill in every case" and a `Material` goes through `Frame.fillMaterial`. A backdrop record inside a shadow scope is
drawn as its flat tint (`BB-H`, divergence 248), which would silently turn a `Material` panel into a flat translucent rect.

**Evidence.** `Frame.fillBackdrop` -> `insertThroughScopes` degrades inside a `.shadow` scope; the shadow of a translucent fill shows through it. Test 5.

**Ruling.** A `Material` panel is `fillMaterial` over the panel rect with its radii **outside** any shadow scope (a real backdrop blur), then the 1-pt `.separator` border as its own
stroke-only rect; **no drop shadow** (border, radius kept). Under Reduce Transparency `fillMaterial` is the opaque grey rect, so the shadow scope is kept around it (what
`BG-C` said). A gradient fill is `paintGradientFill` over the rounded panel **inside** the shadow scope (the image path, `LK-J`) with the border stroked over it; a colour fill is
the one bordered rect inside the shadow scope as before. The content spelling keeps the `.surface` panel (one bordered rect, shadow) and draws its content over it, cut to the
panel's rounded rect (`pushClip` at the panel bounds with radius 10), before the popover's own content. Amends `BG-C`'s "every case" for a non-reduced material only.

**Not built / carried.** A material panel's shadow (a shadow-only primitive does not exist; adding one is a renderer change, `TE-AD`). Cost if wrong: a look, one function
(`AnchoredPresentation.paintPanel`), check `BG1`.

**Lane 1 build notes.** The slot is `Frame.presentationBackgroundSlot`, opened by `beginPresentationPreferences` (saves the enclosing value, depth +1) and restored by
`endPresentationPreferences`; `AnchoredPresentation.requestLayout` reads it between the content's build and the end. The content spelling is an overlay attachment
(`requestNativeOverlayAttachment`: SwiftUI's `.background(alignment:content:)` kernel node: measured at the primary's size, never part of it) of the chrome node and the
background element (`AnyElement(Box(content:))`) under `child(of: id, at: 0, name: "$presentationbackground")`, `noteNamed` called, its own preference bracket kept out of the
main tree, its bounds recorded as the group default does.

## BG-Q — Lane 1 measured: the `noteNamed` call is unobservable; the token twin needs an explicit token

**Evidence (mutations, filtered family set of 21: the 13 `PresentationBackgroundTests`, the 2 guards, `everyFrameChannelIsClassified`, the Menus tests, the 1 MB stack test; applied over the
committed tree, restored with `git checkout`, `git status --short` empty after each).**
`M1` paint ignores the slot -> tests 1, 2, 5, 6, 7 (`aPopoverPanelTakes…`, `theInnermost…`, `aMaterial…`, `aGradient…`, `aColourToken…`). `M2` overwrite instead of keep-first -> 2.
`M3` report before the body, the bracket not resetting, no depth guard -> 2, 3. `M4` border width 0 under a colour -> 4. `M5` `fillBackdrop` called directly -> 5 (both arms; the `MT-` scan guard
also scans for it, not re-run in the family set). `M6` the token twin resolves against `Theme.light` -> 7 (both scheme arms of the twin spelling). `M7` alignment ignored -> 8.
`M7b` a ZStack in place of the overlay attachment (the background answers the layout) -> 8. `M9` the report taints the graft journal -> 11. `M10` an opaque hitbox for the background node -> 12.
`M11` an overlay reads the slot and paints a panel -> 10. `M12` the scope also reports a colour-scheme preference -> 13. Guards: the twin without `@_disfavoredOverload` -> BG1.1 (`ambiguous use of
'surface'`), the radial overload deleted -> BG1.2, each with the other green (the module rebuilt, the test binary not). **`M8` (the `noteNamed` call dropped) reddens nothing**: the name is a constant at its
position, so `noteNamed` can neither find a departed name nor change a produced set; the call is kept for `ID-R`'s rule and is an instrument with nothing to see (as `SG-I`), not a pin.

**Rulings.** (1) The popover test 7 reaches the `ColorToken` twin with an explicit `ColorToken` value: `.presentationBackground(.accent)` resolves to the `Color.accent` overload (the twin is
`@_disfavoredOverload`), so the implicit spelling never exercises it; both are tested. (2) Test 3's absence is structural: a scope reports **after** its body, so a declarer-level report happens after
the presentation's bracket closed; only a pre-order report (`M3`) reaches the chrome, and that is what the test pins. (3) `Frame.presentationBackgroundSlot` and `presentationBracketDepth` are `buildOnly`
rows of `frameChannels` (the one edit to `RetainedSubtreeInternalTests.swift`, a table row, not a retained path). (4) The demo: the existing menus-demo popover gains a gradient fill
(`menusPopoverBackground()`, its own function); the popover is closed in the default frame.

## BG-R — Lane 2 build notes: where the rulings landed and what the build settled

**Background press.** `Window.answerUnclaimedTitleBarPress` keeps the band branch byte for byte and adds the background one behind it: `.enabled`, `clickCount == 1`
and `platformUsesDragRegions != true` (an SDL-like platform moves the window by its region before `Window` sees the press, so it is **not** also asked; `BG-O`). The behavior
lives in `WindowChromeState.backgroundDragBehavior`; a change dirties the window once (the regions are republished after the build) and an equal write does nothing.
**Regions.** `ChromeRegions.compute(…, background:)` carves the content rect last by **every** blocker; `ChromeHitMap.carve` already cuts at the cap and reports
`truncated`, so the over-cap rule is: if the carve with the background truncated anything, carve again without it (the band and the handles keep exactly what they had; no
`ChromeHitMap` change). The window passes the background only for `.enabled` and not while `platformWindow.isZoomed`; the popover/alert/menu rule is the old
early `[]`.
**Shape cursor.** `ShapeCursorSpec` is `Hashable` by the path geometry value and the clamped numbers; `Kind.shape` resolves in `Window.resolvedPlatformStyle` (the one
`sendPointerStyle` argument); `PointerStyle.platformStyle` answers `.arrow` for a shape to a caller outside the window. `Window.noteDisplayScale` runs at the start of every build
and forgets the sent style when the **integer** scale (rounded up) changes while a shape is sent, so the post-frame resolution re-sends once; a fractional change within one
integer sends nothing. **A `Color` fill or outline resolves in the light theme and scheme** (`Color.resolved(theme: .light, scheme: .light)`): a literal is exact, a token or dynamic
colour takes its light value, because a cursor is not part of any scheme-scoped tree; documented on `shape`. The spelling is `@MainActor` (`Shape.path(in:)` is).
**Tests.** The background-drag and shape tests are in `Tests/MetalUITestingTests` (portable, plain imports, real `Window` over the headless platform, runs on Linux and Windows),
not `MetalUITests`; the AppKit arm (`appKitBackgroundPressDragsOnlyDuringAMouseDown`) is in `AppKitWindowDragTests`; the SDL arm is in `SDLChromeTests`
(`aBackgroundRegionReachesTheSDLHitTestSnapshot`, gated on a window-manager driver like its neighbours). Guards `BackgroundDragCompileGuards.swift` (3).
**Demo.** `chromeDemoContent` gains `ChromeDemoBackground` (its own `Component` and the star path in its own function): a `Background drag` switch applied through
`ChromeDemoModel.applyBackgroundDrag` (set by `openChromeDemoWindow`; **a public `ChromeDemoModel.backgroundDrag` field, class M**) and a star-shaped pointer region (`eoFill`).
The default demo is untouched, so the fourteen images do not move.

## BG-S — Lane 2 measured: mutations, the two pins strengthened, and a trap the 1 MB harness found

**Evidence (mutations, filtered family set of 62 tests: the lane's 23, `WindowChromeTests`, `ImageCursorTests`; each applied over the committed tree, built, run, restored with `git checkout`, `git status --short` empty after each; the full unfiltered suite ran on the unmutated tree before and after).**
`M1` the behavior check dropped -> `automaticAndDisabledNeverDragFromTheBackground` and `appKitBackgroundPressDragsOnlyDuringAMouseDown`. `M1b` `.automatic` treated as `.enabled` -> 16 plus 23 existing/new region tests (the chrome tests hold a window with
default `.automatic`). `M2a` `active == nil` dropped -> `aPressOnAnOpaqueTargetANestedGestureOrAHandleNeverDragsFromTheBackground`. **`M2b` the arena check dropped reddened nothing** at first: `DragGesture` and `onClick` both make an opaque target, so `active` already
blocks them; the case only the arena check catches is a **draggable** (non-opaque arena member, `DN-`), so the test gained that arm and `M2b` now reddens it. `M3` `clickCount` passed through -> `aSecondaryPressAndADoubleClickOnTheBackgroundDoNotDrag` and the AppKit arm. `M3b` a region platform also asked
-> `aChangeOfBehaviorRepublishesTheRegionsOnceAndNeverOnAnEqualFrame` (its last arm). `M4` the band gated on `.enabled` -> `theTitleBandKeepsItsDragWhateverTheBehavior`. `M5` background carved by nothing -> `theBackgroundRegionIsTheWindowCarvedByEveryBlocker`,
`aWindowWideOpaqueBackdropLeavesNoBackgroundRegion`, `aTooFragmentedBackgroundIsDroppedWholeNotCutShort`. `M6` the band's backdrop exemption reused for the background -> `aWindowWideOpaqueBackdropLeavesNoBackgroundRegion` (its first arm). `M7` zoomed arm dropped ->
`theBackgroundRegionIsEmptyWhileAPopoverADrawnAlertOrAMenuIsOpenAndWhileZoomed`. `M8` the cut list kept -> `aTooFragmentedBackgroundIsDroppedWholeNotCutShort`. `M9` the setter does not dirty -> `aChangeOfBehaviorRepublishes…`, the region tests that set the behavior after open.
Shape: `S1` raster at scale 1 -> `aShapeCursorIsAnImageCursorOfTheShapeRasterizedAtTheDisplayScale` (by an out-of-range pixel read: the run ends without a summary line, the test reddens by trap). `S2` always nonzero -> `eoFillLeavesTheHoleOfAnOverlappingPathTransparent`. `S3` a cache that never hits ->
`theShapeCursorCacheKeepsTheEightMostRecentlyUsed` (and the raster count of 29 reads it). `S4` the outline ignored by the style -> `aDifferentSizeScaleHotSpotOrColourIsAnotherCursor`. `S5` the hot spot from the bitmap origin -> `theShapeCursorHotSpotIsTheCentreByDefaultAndClampsOutsideTheUnitSquare`. `S6` no 128 clamp ->
`aNonFiniteOrEmptySizeFallsBackToTheArrowAndAnOversizedOneClampsTo128`. `S7` no eviction -> `theShapeCursorCacheKeepsTheEightMostRecentlyUsed`. **`S8` (a note of rasterized pixels at send time) reddened nothing**: the frame zeroes its counters at its start, so work done outside a frame is
invisible to `lastRasterizedPixels`; test 34 now also reads `RasterCache.keyProbes` (never reset), and `S8` as a coverage lookup at send time reddens `aShapeCursorCostsNoFrameRasterWork`. `S9` a scale change leaving the sent style -> `aShapeCursorUnderAScaleChangeIsReSentOnceAtTheNewScale`.
Guards (each mutated red once, the other arms green): `G1` a fourth `WindowInteractionBehavior` value -> `windowInteractionBehaviorOffersExactlyThreeValues`; `G2` the setter `internal` -> `theBackgroundDragBehaviorIsSettableFromOutsideTheModule` (read with `--target MetalUI`, the demo
module refusing the assignment too); `G3` `size:` defaulted -> `theShapeCursorSpellingTypechecksWithTheVisionOSCall`. **`aBackgroundRegionReachesTheSDLHitTestSnapshot` is a characterization** of a platform answer no lane-2 source changes: no mutation of this lane reddens it.

**A closure inside the star path trapped the stack-budget test.** `chromeDemoStar()` first built its points with `.map { … }`: a main-actor closure handed to a stdlib generic checks its isolation per call, and the 1 MB harness builds on a secondary thread (`HP-C`):
`everyProductionTreeBuildsOnAOneMegabyteThread` read `.signal(SIGTRAP)` (not an overflow: an 8 MB thread trapped too). Plain calls fix it; the new section stays in the test. **Rulings.** (1) A demo section takes no closure over a main-actor value in a stdlib generic. (2) An SDL-like platform's bordered
window with a whole-window region answers `.draggable` at its edge (no resize edge of its own, `CW-G`), pinned in the SDL test.

