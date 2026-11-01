# Human checks — the one consolidated list (plan task 15)

**Status: NOT RUN.** Written by an agent at plan task 15's closeout (ruling
`CX-M`, `docs/superpowers/2026-09-30-closeout-decisions.md`; record §66 §4).
**An agent cannot perform any check on this page** — each needs a person at an
unlocked Mac looking at a real window, using a real pointer, trackpad, wheel
mouse or VoiceOver. Every look owed across the project's history is collected
here so none is lost; each item names the record section that owed it. **Plan
task 15's box is ticked only when every box below is ticked (or answered "no,
it looks wrong" with a note) and the Record phase has re-read this file**;
plan task 12's box waits on group L alone (the VoiceOver script).

Each item says what to run, what to look at, what the right answer is, and
where the behaviour is already pinned headless (so a "looks wrong" report can
be turned into a failing test). Report back by ticking the box and writing one
line under **Observed** — "as expected", or what you saw instead.

**How this list was built** (so a reviewer can find a gap): every dated
section of `docs/record/03-verified-on-real-hardware.md`
(`grep -n "^## " docs/record/03-verified-on-real-hardware.md`), every
"open"/"owed" row in it (`grep -n -i -E "open|owed|unobserved|nobody has" …`),
and the frozen human-verification table in `docs/record/19-claude-md-full-2026-09-21.md`
§"Human verification" — each row there that is not closed appears below.

## Before you start

1. **Check the screen is unlocked to a script**:
   `xcrun swiftc -O docs/probes/appkit-screen-lock-state.swift -o /tmp/lockstate && /tmp/lockstate`
   — expect **no** `CGSSessionScreenIsLocked` line and `displayAsleep main: 0`.
2. **Build release**: `swift build -c release`, then run the demo with
   `swift run -c release MetalUIDemo` (920×560 window). Variants:
   `METALUI_NATIVE_LAYOUT_PREVIEW=1` (the proposal preview),
   `METALUI_CONTROLS_DEMO=1` (the controls demo),
   `METALUI_TEXT_INPUT_DEMO=1` (two `TextField`s and a `TextEditor`),
   `METALUI_LOOKS_DEMO=1` (the looks demo, 1180×880: H1, I1, J1, K1–K3, Q1–Q6, S1–S3, T1–T2),
   `METALUI_DND_DEMO=1` (drag and drop: N1–N8),
   `METALUI_METALVIEW_DEMO=1` (MetalView, app-owned GPU surfaces: P1–P8).
3. **Demo keys**: **M** modal (translucent scrim), **Space** theme, **F**/**Esc**
   focus the counter, **=**/**-** count, **A** the animation look, **Q** quit.
   In the preview only **Space** and **Q** have a visible effect.
4. Dark-on-dark dimming is hard to judge by eye — measure before reporting "no
   scrim" (record §03, absolute positioning).

## A. Real-window captures (scripted, needs an unlocked screen)

- [ ] **A1. Default and preview windows, pixel for pixel.** Run
  `docs/probes/window-capture/capture.sh <scratch-dir> 1b093b8 <HEAD>`. Expect
  every a-vs-b stability pair 0, default and preview 0 differing against
  `1b093b8` (unless a later ruling names a change), the default-vs-preview
  control non-zero (958 986 at `1b093b8`). Last taken: `6c961e3` → `1b093b8`,
  0 / 0, 2026-09-30 23:41 PDT (`CX-M` item 2). *Source: record §03, stage 6b
  section onward; task 12 part 2 section.* An agent may run this one when the
  lock probe reads unlocked; the rest of this page needs a person.
  **Observed:**

## B. The demo's layout since the proposal engine became production (stage 6b)

Run `swift run -c release MetalUIDemo`. *Source: record §03, "the demo-layout
rows re-opened at engine replacement stage 6b"; record §41 §4, §12.6.* Pinned
headless by the fourteen-image offscreen comparison
(`docs/probes/demo-pixels/compare.sh`) and `theDemoFrameMatchesTheValuesRecordedOnMacOS`.

- [ ] **B1. The sidebar is 196 pt wide** (the CSS engine had shrunk it to 88 pt
  at this 920×560 window). **Observed:**
- [ ] **B2. Press A: the animation panel grows to 320 pt** and its background
  fades `.surface` → `.accent`, both in one spring (0.6 s, bounce 0.2); press A
  again and both reverse. The colour fade is not obvious at a glance — look
  twice (record §03, "Animation verified on 2026-09-10"). **Observed:**
- [ ] **B3. Press M: the modal card's height** fits its content at the lowered
  column's own width (y − 8 / h + 16 against the old engine), centred on a
  translucent scrim that dims the whole window. **Observed:**
- [ ] **B4. The list rows' labels sit vertically centred** in their 28 pt rows
  (they used to sit at the row's top). **Observed:**
- [ ] **B5. Under A, the paragraph in the main pane** wraps to four lines at
  920×560 (it drew five; `TE-Y` item 3, record §03 task-11-part-1 section).
  **Observed:**

## C. The modal, the scrim and scrolling (older open rows)

*Source: record §03, "Absolute positioning and `Deferred` — failures 3 and 4";
record §19's table.* Pinned headless by
`theDemoModalDismissesOnAScrimClickAndSwallowsTheWheel`,
`anOpaqueDeferredScrimSwallowsAWheelEventInsteadOfScrollingTheListBeneath`.

- [ ] **C1. With the modal up (M), scroll the list region**: the modal stays
  put; the wheel over the scrim does **not** scroll the list underneath
  (inverted since `IN-W`); a click on the scrim dismisses the modal.
  **Observed:**
- [ ] **C2. Wheel-mouse distance**: with a *conventional* wheel mouse (not a
  trackpad or Magic Mouse), scroll the 500-row list one detent at a time.
  About a third of a 28 pt row per click means the line→point conversion is
  live (10 pt per line); a thirtieth means it is not. Does it feel like a
  Finder list with the same mouse? Pinned only with synthesized events
  (`aNonPreciseScrollDeltaIsScaledFromLinesToPointsAndAPreciseOneIsNot`).
  **Observed:**
- [ ] **C3. Release and debug feel**: scroll to row 500 in a release and a
  debug build; report any blank row at the bottom edge, a launch hitch, or a
  stutter (record §19, measure performance in debug — "not reported either
  way"). **Observed:**
- [ ] **C4. Reactivity measurement**: run the demo, leave it idle 30 s, press
  **M** twice, quit with **Q**, and copy the printed `frames drawn` /
  `pauses entered` / `observation dirtyings` line here — a measurement, not a
  judgement (reactivity spec §8 item 7, record §19). **Observed:**

## D. The proposal preview

Run `METALUI_NATIVE_LAYOUT_PREVIEW=1 swift run -c release MetalUIDemo`.
*Source: record §19's table (preview row); record §03 2026-09-21 section
(`GR-N`).*

- [ ] **D1. Text rewraps with the window width**; the `layoutPriority(1)`
  panel keeps its width as the window narrows; the wheel scrolls the scroll
  view; the toggle flips colour on click; the dimmed tap under
  `.allowsHitTesting(false)` does nothing. **Observed:**
- [ ] **D2. The grid**: two rows and two columns of 80×24 cells at the right
  of the bottom row; the last cell changes colour on click and lights on
  hover; nothing else moves. Nobody has looked at a grid on screen (`GR-N`).
  **Observed:**

## E. Window state and display scale (task 9, task 12 part 1)

*Source: record §03, task 9 section and task 12 part 1 section.* Pinned
headless by `theAppKitMappingPutsKeyBeforeActiveBeforeInactive`,
`ControlLookTests.swift`, `WindowControlStateTests.swift`.

- [ ] **E1. Key / active / inactive**: open the controls demo, click another
  app, then back. A focused or "on" control's accent (a toggle that is on, a
  slider's fill, a segmented picker's selection) and its focus ring turn grey
  (`.separator`) while the window is not key, and return when it is. Also
  re-run `docs/probes/swiftui-environment-control-state.swift`'s C arms with
  the screen unlocked and compare SwiftUI's own key/active mapping
  (`EV-AB`). **Observed:**
- [ ] **E2. `displayScale` across displays** (needs two displays of different
  backing scale): drag the window from one to the other; text and hairlines
  stay crisp on each, and nothing jumps beyond the rescale. Pinned only
  through `FakeRenderSurface`/`simulateBackingScaleChange`. **Observed:**

## F. Disabled scrolling (task 10 part 1)

- [ ] **F1. A disabled `ScrollView` and the wheel.** MetalUI's still scrolls
  (`aDisabledScrollViewStillScrollsOnTheWheel`, `EV-E`); SwiftUI's answer is
  unmeasured. Build and run `docs/probes/swiftui-data-and-scrolling.swift`'s W
  arms with the screen unlocked: if W0 (the enabled control) scrolls and W1/W2
  (`.disabled(true)`) do not, MetalUI should move `registerScrollRegion`
  inside the disabled gate (`DD-I` item 3). *Source: record §03, task 10 part
  1 section.* **Observed:**

## G. The controls demo (task 10 part 2, task 12 part 1)

Run `METALUI_CONTROLS_DEMO=1 swift run -c release MetalUIDemo`. *Source:
record §03, task 10 part 2 and task 12 part 1 sections.* Pinned headless by
`ButtonTests.swift`, `ControlLookTests.swift`, `InputDispatchTests.swift`,
`FocusTraversalTests.swift`.

- [ ] **G1. Every control by pointer**: a slider press and drag, a stepper's
  two halves, a segmented and a radio-group picker, a toggle, a button.
  **Observed:**
- [ ] **G2. Every control by key**: Tab reaches each control in order
  (shift-Tab back); Space/Return press a button, Space flips a toggle, arrows
  move a slider, a stepper and a picker. **Observed:**
- [ ] **G3. The wheel over a button, a single-line field and a selectable row**
  inside a scroller scrolls it (`DD-Y`, `aClickTargetInsideAScrollViewPassesTheWheelToItsScroller`).
  **Observed:**
- [ ] **G4. List selection**: click selects; ⌘-click toggles; ⇧-click selects
  the range from the anchor; ↓/↑ and ⇧↓/⇧↑ move and extend; an off-screen lead
  scrolls into view. **Observed:**
- [ ] **G5. The pressed, disabled and focused looks**: a button's wash while
  held (and gone when the pointer leaves while held); a disabled control at
  half opacity; the focus ring on each of the five controls when it has focus.
  **Observed:**
- [ ] **G6. Full Keyboard Access**: with System Settings → Keyboard →
  Keyboard navigation **off**, MetalUI's controls still take Space/arrows once
  focused (divergence 80, MetalUI reads no system setting). Note whether that
  feels wrong beside a native app. **Observed:**

## H. Text (task 11 part 1)

- [ ] **H1. `controlSize`'s drawn font**: run `METALUI_LOOKS_DEMO=1 swift run
  MetalUIDemo` (the looks demo, `Sources/MetalUIDemoContent/LooksDemo.swift`);
  its "H1 · controlSize" column's three texts, under
  `.controlSize(.mini/.small/.regular)`, draw at 9/11/13 pt (`TE-Q`, `TE-F`);
  the measured layout is pinned by number, the drawn glyph never seen.
  *Source: record §03, task 11 part 1 section.* **Observed:**

## I. Shapes, strokes, clips and images (task 11 part 2)

- [ ] **I1. Through a real renderer's antialiasing**: in the looks demo
  (`METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`, section "I1 · shapes, clip,
  images"), an ellipse fill and an ellipse stroke band, a capsule, a rounded clip over overflowing content, a
  `.resizable()` image in `.fit` and `.fill`, and `.interpolation(.none)` vs
  the default (nearest vs bilinear: the third image's checker squares hard,
  the fourth's blurred). Pinned only offscreen and through the SDL
  replay-parity harness. *Source: CLAUDE.md "Human verification" task 11 part
  2; record §61.* **Observed:**

## J. Gestures (task 12 part 1)

- [ ] **J1. On a trackpad**: in the looks demo (`METALUI_LOOKS_DEMO=1 swift
  run MetalUIDemo`, section "J1 · gestures"), double-tap the first pad,
  long-press the second (0.5 s), drag on the third — the line below counts
  each. Tap slop, double-tap timing and a long press's duration feel like Finder's or a SwiftUI app's (`GestureTests.swift` pins
  the numbers). *Source: record §03, task 12 part 1 section.* **Observed:**
- [ ] **J2. A real key window's accent and ring** — the probe harness was never
  the active application (`PX23` always read "inactive"); confirm E1's flip
  happens in a real key window. **Observed:**

## K. Transitions and Reduce Motion (task 13)

*Source: record §03, task 13 section.* Pinned headless by
`aMoveTransitionOffsetsByTheElementsOwnSize`,
`aScaleTransitionScalesTheGroupsPrimitivesAboutItsAnchor`,
`underReduceMotionEveryTransitionButIdentityIsAnOpacityFade`,
`propertyAnimationsRunUnchangedUnderReduceMotion`.

Run them in the looks demo (`METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`,
section "K1–K3 · transitions"): each button toggles its tile in and out under
`withAnimation(.easeInOut(duration: 0.8))`.

- [ ] **K1. Transitions on screen**: an insertion and a removal under
  `withAnimation` for `.opacity`, `.move(edge:)`, `.scale`, `.slide`,
  `.offset`, `.push`, `.asymmetric`, `.combined` — the removed element's ghost
  draws above everything on its layer and leaves when the animation ends.
  **Observed:**
- [ ] **K2. Reduce Motion**: System Settings → Accessibility → Display →
  Reduce motion **on**; every transition but `.identity` becomes a cross-fade
  on the same animation, and property animations (the demo's **A**) are
  unchanged. Turn it off again. Measured only by swizzling the getter
  in-process. **Observed:**
- [ ] **K3. `.scale`'s mid-flight glyphs** (the looks demo's `scale` button;
  its tile carries the text "Aa scale me") look softened (a linear-filtered
  resample of the atlas, not a re-rasterization) and snap sharp when the
  transition lands. **Observed:**

## L. VoiceOver (task 12 part 2) — the script

- [ ] **L1. Run [`voiceover-script.md`](voiceover-script.md) end to end** and
  fill its **Observed (human)** cells and sign-off. That script is the whole
  check; it is linked here, not copied. It walks the demo, the controls demo,
  the preview and the text-input demo, including the five control roles
  (divergence 82's partial fold, a stepper's arrows), settable list selection
  and modal isolation. Plan task 12's box is ticked only after this and the
  Record phase's re-read (`IX-AE`). *Source: record §03, task 12 part 2
  section; task 10 part 2 section (VoiceOver on the five roles); record §19's
  bridge row.* **Observed:**

## M. Older milestone rows still open (record §19's frozen table)

- [ ] **M1. The animation look's pixel readings** were taken on the
  pre-`f1944f8` sidebar; re-take them: press A, confirm the width overshoots
  slightly and settles, the colour overshoots too, and the reverse press
  animates back (record §03, "Animation verified on 2026-09-10"). **Observed:**
- [ ] **M2. Tombstones-and-AX §7 item 9** — the regression check nobody has
  run: with VoiceOver on, scroll the demo's list far enough that rows leave
  the window and come back; the cursor and row identity survive. Folded into
  L1's list steps if that script covers it. **Observed:**

## N. Drag and drop (user request 2026-10-01, not a plan task)

*Source: record §68 (drag and drop), rulings `DN-A`…`DN-Z`
(`docs/superpowers/2026-10-01-drag-and-drop-decisions.md`), spec §8.* SwiftUI's
real pointer drags (probe group `P`) were measured at the HID tap; MetalUI's
answers are pinned headless through a fake platform window and a fake
`NSDraggingInfo` — nothing below has been seen on a real display. Run
`METALUI_DND_DEMO=1 swift run MetalUIDemo` ("MetalUI — Drag and Drop",
920×560): four chips (**Apple**, **example.com**, **Custom preview**, **Hold,
then drag**) and a
selectable list on the left, four wells (**Text**, **Links and files**,
**Anything**, **Disabled**) on the right; a well shows its last drop under its
title ("—" before one) and fills with the accent colour while targeted.

- [ ] **N1. In-window drag**: drag **Apple** onto **Text**. A translucent copy
  of the chip (about 70% opacity) follows the pointer with the press point
  under it, drawn above everything; the chip itself stays put; on release the
  copy disappears and **Text** shows "Apple". Drag **Custom preview**: a 60×60
  accent square follows instead of the chip. Pinned by
  `aDraggableBeginsOnTheFirstMoveAndDropsOnADestination`,
  `theDefaultPreviewReplaysTheSourceAboveEverythingAtSeventyPercent`,
  `aCustomPreviewReplacesTheSnapshot`,
  `theDragAndDropDemoDropsAChipOnTheTextWell`. **Observed:**
- [ ] **N2. The `isTargeted` highlight**: drag **Apple** over **Text**, out and
  back in — the well fills on entering, empties on leaving, fills again; move
  from **Text** straight to **Anything** — the first empties before the second
  fills. Press **Escape** mid-drag over **Text**: the preview vanishes, the
  well empties and shows nothing new, and the release clicks nothing. Drag
  **example.com** over **Text**: no fill (a URL is not text); over **Links and
  files**: it fills and takes the drop. Every chip over **Disabled**: no fill,
  no drop (divergence 100 — SwiftUI's disabled destination still takes it).
  Pinned by `isTargetedTurnsFalseBeforeTheNextTrueAndBeforeTheAction`,
  `escapeCancelsADragWithNoDropAndNoClick`,
  `aDisabledSourceDoesNotDragAndADisabledDestinationRefuses`. **Observed:**
- [ ] **N3. A chip dragged out of the window (AppKit)**: drag **Apple** out of
  the window onto a TextEdit document — at the window's edge the translucent
  preview is replaced by AppKit's drag image (a text badge), and the drop
  inserts "Apple"; drag **example.com** onto Finder's or Safari's address bar
  — it carries the URL. The hand-off cannot be run headless (a headless
  `NSDraggingSession`'s tracking loop never returns, `DN-X` item 1), so this
  is the only check of the real session (divergence 101). Pinned up to the
  hand-off by `leavingTheWindowHandsTheDragToThePlatformWhenItCan`,
  `anExternalDragItemCarriesEveryRepresentationAndAnImage`,
  `beginExternalDragNeedsADragEvent`. **Observed:**
- [ ] **N4. Drops from other apps (AppKit)**: drag a file from Finder onto
  **Links and files** — it fills while hovered and lists the `file://` URL;
  onto **Anything** — it shows a byte count; onto **Text** — no fill. Select
  text in TextEdit and drag it onto **Text** — it fills and shows the text.
  Pinned by `aFinderFileDropReachesAURLDestination`, `draggingExitedUnTargets`,
  `anExternalDropFindsTheSameDestinationAndLoadsOnlyWhatItImports`.
  **Observed:**
- [ ] **N5. The same drops on SDL**: `cd Backends/SDL && METALUI_DND_DEMO=1
  PKG_CONFIG_PATH=$PWD/.accesskit swift run MetalUISDLDemo` on macOS and, if
  available, Linux (X11 and Wayland) and Windows. A Finder/file-manager file
  onto **Links and files**, TextEdit/editor text onto **Text**: the drop lands
  where the pointer is (SDL's positions). **While hovering, every well but
  Disabled fills whatever is dragged** — SDL gives no types until the drop, so
  a file over **Text** fills and then refuses at the drop (divergence 102); a
  URL dragged from a browser arrives as text. A chip dragged to the window's
  edge stops there (divergence 101). Pinned by
  `sdlDropEventsBecomeOneDropSession`, `droppedTextIsUTF8PlainText`,
  `ordinaryPointerMotionEndsAnOpenDropSession` (`Backends/SDL`) and
  `anExternalDropWithUnknownTypesTargetsOptimistically`. **Observed:**
- [ ] **N6. A list row**: click a row — it selects; drag another row onto
  **Text** — the well shows "Row n" and the selection does not move. Pinned by
  `aDraggableRowsClickStillSelectsAndItsDragDoesNot`. **Observed:**
- [ ] **N7. (Optional) VoiceOver** reads the chips and wells exactly as it
  would without drag and drop — no drag or drop action, no extra attribute
  (`DN-N`, probe arms A0–A4; a VoiceOver user drags with VoiceOver's own
  mouse-down/up commands, not required here). Pinned by
  `aDraggableAndADropDestinationPublishNothingNew` and
  `accessKitPublishesADraggableAndADropDestinationUnchanged` (`Backends/SDL`).
  **Observed:**
- [ ] **N8. (Optional) A held press**: press and hold **Hold, then drag** (a
  draggable chip with a long press) past half a second without moving, then
  move — no drag begins; a quick press-and-move on it drags (MetalUI's choice,
  `DN-U` item 1; SwiftUI's answer is unmeasured). Pinned by the sixth arm of
  `aDraggableBeatsATapAClickAndALongPressOnItsElementAndItsChildren`.
  **Observed:**

## O. The application icon (user request 2026-10-01, not a plan task)

*Source: record §70 (app icon), rulings `AI-A`…`AI-M`
(`docs/superpowers/2026-10-01-app-icon-decisions.md`), spec §7.* Both demos
assign `app.icon = demoIcon()` before opening a window: six generated square
bitmaps (16 to 512 px) of a **blue (`#2F6FEB`) rounded square with a white
disc in its centre**, hard-edged (no anti-aliasing, `AI-G`). The conversions
and the calls are pinned headless; whether a shell actually shows the icon is
not observable from a test process (no test runs as a `.regular` app with a
Dock tile, and none looks at a taskbar).

- [ ] **O1. The Dock icon (AppKit)**: `swift run MetalUIDemo` (an unbundled
  executable). The Dock tile shows the blue rounded square with the white
  disc from launch — not the generic executable icon, not even briefly after
  the window appears; ⌘-Tab shows the same. Quit with **Q**: the tile goes
  away with the process and no blue icon lingers. This is the only check of
  `AppKitPlatform.run()`'s re-assignment after `setActivationPolicy(.regular)`
  (`AI-E` item 4, unpinned by design, `AI-K`). Pinned up to
  `applicationIconImage` by
  `settingTheIconOnTheAppKitPlatformSetsTheApplicationIconImage`,
  `anIconImageHoldsOneRepresentationPerTextureSmallestFirst`,
  `anIconRepresentationDrawsWithoutASecondPremultiply`,
  `theDemoIconsPixelsAreTheSpecifiedShape`. **Observed:**
- [ ] **O2. The Dock icon (SDL on macOS)**: `python3
  Backends/SDL/scripts/fetch-accesskit.py` once, then `cd Backends/SDL &&
  PKG_CONFIG_PATH=$PWD/.accesskit swift run MetalUISDLDemo`. SDL's Cocoa
  backend turns the window icon into the application's Dock icon: the tile
  shows the same blue square and white disc, not a generic icon (`AI-F` item
  6). Pinned by `sdlsCocoaBackendReceivesTheIconAsTheApplicationIcon`
  (`Backends/SDL`, macOS: SDL's Cocoa backend sets
  `NSApp.applicationIconImage` to the primary texture's size, on an open
  window and a later one) and
  `anIconSurfaceIsRGBA32HoldingTheStraightBytesRowByRow`;
  `settingTheIconAppliesItToEveryOpenWindow` and
  `aWindowOpenedAfterTheIconIsSetGetsIt` pin only that every window is
  handed the icon (their `applied` is the C wrapper's own answer). **Observed:**
- [ ] **O3. Linux (X11, then Wayland)**: the same `MetalUISDLDemo` command on
  a Linux desktop. **X11**: the window's title bar (where the window manager
  draws an icon there) and the task bar or dock show the blue square with the
  white disc (SDL writes `_NET_WM_ICON`). **Wayland**: SDL can set an icon
  only where the compositor offers `xdg-toplevel-icon-v1`; elsewhere — GNOME
  Shell among them, which takes icons from an installed `.desktop` file
  (`docs/packaging.md`) — a generic icon is the expected answer, not a
  failure. Note the desktop, compositor and version either way. The rounded
  square's edge should be clean, with no dark fringe — a fringe would mean
  the backend wanted premultiplied alpha (`AI-F`'s "cost if wrong"; the demo
  icon is hard-edged, so its only partial alpha comes from SDL's own scaling).
  Pinned by `unpremultiplyingRestoresStraightAlpha` and
  `anIconSurfaceCarriesEveryLargerTextureAsAnAlternate`. **Observed:**
- [ ] **O4. Windows**: the same `MetalUISDLDemo` command (with the flags
  `fetch-accesskit.py` prints). The title bar's small icon, the taskbar button
  and Alt-Tab show the blue square with the white disc. With the display
  scaled above 100%, the taskbar icon is sharp (an alternate, not the 16 px
  primary scaled up). Pinned by
  `anIconSurfaceCarriesEveryLargerTextureAsAnAlternate`. **Observed:**

## P. MetalView — app-owned GPU surfaces (user request 2026-10-01, not a plan task)

*Source: record §71 `71-metal-view.md` (written as §69, renumbered, `MV-O` item 4),
rulings `MV-A`…`MV-R` (`docs/superpowers/2026-10-01-metal-view-decisions.md`),
spec §7.* SwiftUI's compositing of an app's Metal layer and `Canvas`'s sizing
and re-runs were measured in a real window (probe
`docs/probes/swiftui-metal-view.swift`, arms C1–C4, D1, R0–R3); MetalUI's
answers are pinned headless — read back from an offscreen target through the
real Metal renderer (and through the SDL renderer in `Backends/SDL`) — and
nothing below has been seen on a real display. Run
`METALUI_METALVIEW_DEMO=1 swift run -c release MetalUIDemo` ("MetalUI —
MetalView", 920×560): a title, a "Viewport draws: n" counter, a large rounded
viewport (520×300) drawn by an app fragment shader with a translucent label
("App-drawn GPU content, UI composited over it") over its top-left corner,
and a **Tint** stepper beside a small rounded swatch (80×40).

- [ ] **P1. The on-screen look**: the viewport shows a smoothly moving
  colour field (sines of position and time) clipped to a 16-point rounded
  rectangle — the corners show the window background, not a square of shader
  colour; the label sits over the shader content at 80% opacity, its text
  crisp; the swatch's corners are rounded too. Nothing flickers or goes black
  on the first frame. Pinned by `aSurfaceFillIsCompositedOnTheFirstFrame`,
  `aSurfaceIsClippedRoundedAndFadedExactlyAsAnImage`,
  `aSurfaceQuadTakesTheActiveClipRadiiOpacityAndLayerAsAnImageDoes`.
  **Observed:**
- [ ] **P2. Continuous smoothness**: watch the viewport for ten seconds — it
  animates at the display's rate (60 Hz, or 120 Hz on a ProMotion display)
  with no stutter, tearing or periodic hitch; the counter climbs at about the
  display's rate. Pinned (the draw-per-tick contract only — the rate and
  smoothness are looks) by `aContinuousSurfaceDrawsOnEveryTickAndAnOnDemandOneOnce`,
  `aContinuousSurfaceKeepsTheWindowAnimatingOnlyWhilePainted`,
  `theMetalViewDemosDrawCountAdvances`. **Observed:**
- [ ] **P3. Idle when paused**: tap the viewport — the animation stops on its
  current picture, the header reads "Paused: …" and the counter stops; Activity
  Monitor's CPU (and GPU History) for the process falls to near idle — the
  display link has paused (`MV-G` item 3). Tap again: it resumes from the
  current time. Pinned by `aContinuousSurfaceKeepsTheWindowAnimatingOnlyWhilePainted`,
  `anOnDemandSurfaceKeepsItsContentsWhenTheWindowRedrawsForAnotherReason`,
  `aSurfaceRegistersNoHitboxOrAccessibilityButTakesATapThroughOnTapGesture`.
  **Observed:**
- [ ] **P4. On-demand redraw**: while paused, click the upper (+) and lower (−) halves of the
  **Tint** stepper — only the swatch changes colour (eight tints), the paused
  viewport and its counter stay unchanged; hovering or clicking elsewhere does
  not change either surface. Pinned by `aChangedValueRedrawsAndAnUnchangedOneDoesNot`,
  `theMetalViewDemoTreeRequestsOneContinuousAndOneOnDemandSurface`.
  **Observed:**
- [ ] **P5. Live resize**: drag the window's corner — larger, smaller, and
  very narrow. The viewport keeps its 520×300 point size where it fits and is
  never stretched, squashed or blurred; no blank or black frame appears while
  dragging; when the window cuts the viewport off, the hidden part is simply
  clipped. Pinned by `aResizedSurfaceGetsANewTargetAtItsNewDeviceSizeAndRedrawsOnce`,
  `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating`.
  **Observed:**
- [ ] **P6. Retina vs 1× scale**: on a Retina display the shader's edges and
  the label are sharp (the target is the bounds × 2, 1040×600 pixels); move the
  window to a non-Retina external display (or set a 1× scaled mode) — it stays
  sharp at 1× with no flash or wrong-size frame during the move, and back again.
  Pinned by `aSurfacesTargetIsItsBoundsTimesTheScaleRounded`,
  `aSurfaceDrawReceivesItsDevicePixelBgraTargetScaleAndTime`. **Observed:**
- [ ] **P7. Colour and gamma**: the shader's colours look the same saturation
  and brightness as the swatch's flat tints and the rest of the UI — no washed
  out or too-dark cast (targets are `bgra8Unorm`, composited in gamma space,
  §7.8, `MV-E` item 4). Pinned by `aSurfaceDrawReceivesItsDevicePixelBgraTargetScaleAndTime`
  (M2e, the sRGB format, reddens it). **Observed:**
- [ ] **P8. The same demo on SDL**: `cd Backends/SDL &&
  METALUI_METALVIEW_DEMO=1 PKG_CONFIG_PATH=$PWD/.accesskit swift run -c release
  MetalUISDLDemo` on macOS and, if available, Linux (X11 and Wayland) and
  Windows ("MetalUI — SDL3 MetalView"). The viewport is a flat colour cycling
  smoothly through hues (the SDL demo draws through `ctx.clear`, not a
  shader), rounded and under the same translucent label; tap pauses it and the
  counter; the stepper recolours only the swatch; resizing and moving between
  displays behave as P5/P6. Pinned by `anSDLSurfaceFillMatchesTheMetalParityLiteral`,
  `anSDLSurfaceIsDrawnBeforeTheSceneAndKeptAcrossFrames`,
  `anSDLSurfaceTargetIsReleasedWhenNoLongerReferenced`,
  `surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence`,
  `theSDLDrawContextCarriesTheFramesCommandBufferAndTarget` (`Backends/SDL`).
  **Observed:**

## Q. Paths, shadows and transforms (user request 2026-10-02, not a plan task)

*Source: record §73 `73-paths-shadows-transforms.md`, rulings `GX-A`…`GX-V`
(`docs/superpowers/2026-10-02-paths-shadows-transforms-decisions.md`), spec
§7.* SwiftUI's paths, strokes, shadows, transforms, hit testing and animation
were measured in a real window (probe `docs/probes/swiftui-paths-shadows-transforms.swift`,
arms PA1–PA9, ST1–ST11, SH0–SH13, T0–T16, H1–H7, X1–X6, N1–N10); MetalUI's
answers are pinned headless (scene bytes, CPU rasters, hitboxes), and nothing
below has been seen on a real display. Run
`METALUI_LOOKS_DEMO=1 swift run -c release MetalUIDemo` and find the section
headed **"Q1–Q6 · paths, shadows, transforms"** (left column, below I1).

- [ ] **Q1. Fills**: the two five-point stars. The left one (nonzero) is solid,
  its centre pentagon filled; the right one (even-odd) has an empty pentagon in
  the middle. Both edges smooth (antialiased), no jagged steps, no gaps where
  the edges cross. Pinned by `evenOddFillStyleEmptiesTheRing`,
  `nonZeroFillsASameDirectionRingAndEvenOddEmptiesIt` (`MetalUIPathTests`).
  **Observed:**
- [ ] **Q2. Strokes and dashes**: the left zig-zag is a 6 pt line with ROUND
  ends and rounded corners; the right one is dashed (12 on, 6 off) with flat
  ends, the dashes following the corners. Both crisp at the window's scale.
  Pinned by `capsEndWhereSwiftUIsDo`, `joinsReachSwiftUIsTips`,
  `dashesWalkTheArcLengthFromThePhase` (`MetalUIPathTests`),
  `aJoinOrDashGoesThroughTheStrokerAndAPlainWidthKeepsTheBand`. **Observed:**
- [ ] **Q3. Shadows, light and dark**: the card ("A card with a shadow") casts
  a soft grey shadow mostly below it (offset 4 down, radius 8); its text also
  casts a faint shadow (a shadow is per leaf, divergence 104). "A shadowed
  text" has a slight, glyph-shaped shadow down-right. Press **Space** to switch
  to the dark theme: the shadows stay the same black at a third alpha (barely
  visible on the dark canvas — SwiftUI's own default). No hard edges, no
  banding, no box-shaped shadow behind the text. Pinned by
  `theShadowBlurMatchesSwiftUIsProfile`, `aTextCastsOneGlyphShapedShadowBelowItsGlyphs`,
  `theDefaultShadowColourIsTheShadowToken`. **Observed:**
- [ ] **Q4. Rotated text and image edges**: "Rotated" turned 30° clockwise is
  legible, its glyphs not chopped at their boxes; the checker image turned 15°
  anticlockwise keeps hard (nearest) squares inside and antialiased outer
  edges — no staircase, no bleed of neighbouring glyphs or texels. Pinned by
  `aRotatedGlyphSamplesItsSlotOnly`, `aRotatedImageKeepsItsFilterAndAntialiasesItsEdges`
  (`MetalUIRenderTests`). **Observed:**
- [ ] **Q5. Crisp path vs soft text under scale**: the small star under
  `scaleEffect(3)` is as crisp as the big stars (re-rasterized); "Aa" under
  `scaleEffect(3)` is visibly soft (resampled from its 12 pt bitmap —
  divergence 106; SwiftUI would draw it crisp). Pinned by
  `aPathUnderScaleEffectIsRasterizedAtTheScaledResolution`,
  `aTextUnderScaleEffectIsResampledNotReRasterized`. **Observed:**
- [ ] **Q6. The rotating square**: click the blue square at the right of the
  row. It turns 45° more on each click, smoothly over about 0.6 s (ease in and
  out). Hover it: it changes colour only while the pointer is over the DRAWN
  diamond — moving into the empty corners of its old square does not hover it,
  and a click there does nothing. Pinned by `theLooksDemoShowsPathsShadowsAndTransforms`,
  `aRotatedSquaresFrameCornerMissesAndItsTipHits`, `hoverAndGestureArenasFollowTheTransform`.
  **Observed:**

## R. Menus, popovers and tooltips (user request 2026-10-02, not a plan task)

*Source: record §74 `74-menus-popovers.md`, rulings `MN-A`…`MN-AG`
(`docs/superpowers/2026-10-02-menus-popovers-decisions.md`), spec §8.* The
probes (`docs/probes/swiftui-menus-popovers.swift`, `docs/probes/swiftui-commands.swift`)
ran in a **locked** session, so a native menu's tracking, a popover's Escape
and outside click, the tooltip and the key-window order of a shortcut are
unmeasured against SwiftUI; MetalUI's answers are pinned headless and nothing
below has been seen on a real display. Run
`METALUI_MENUS_DEMO=1 swift run -c release MetalUIDemo` (AppKit) and, for R2,
`METALUI_MENUS_DEMO=1` with `Backends/SDL`'s `MetalUISDLDemo` on Linux or
Windows.

- [ ] **R1. The native context menu**: a right click and a control-click on the
  card each open a native menu — Copy, Rename, a separator, Colour ▸ (Red,
  Green, Blue), Pinned (✓ once chosen), Delete greyed, Duplicate showing ⌘D —
  looking as a SwiftUI app's does (host the probe's C1 view in a window to
  compare). Choosing an item updates the status line. Pinned by
  `aRightPressOverAContextMenuPresentsItsItemsToThePlatform`,
  `anAppKitMenuIsBuiltFromThePlatformMenu`, `aChosenNativeItemArrivesAsAMenuActionAfterThePopUpReturns`
  (`AppKitMenuTests`; the production `NSMenu.popUp` is pinned by none, `MN-AF`
  item 7). **Observed:**
- [ ] **R2. The drawn menu (SDL)**: on Linux or Windows the same right click
  draws MetalUI's menu: rows highlight under the pointer, Colour opens its
  submenu on hover, ↑ ↓ → ← move, Return chooses, Escape closes a level, an
  outside click dismisses without clicking what it lands on, Shift-F10 and the
  Menu key open the focused element's menu. Pinned by `ContextMenuTests` 1.16–1.28
  and `SDLMenuInputTests`. **Observed:**
- [ ] **R3. The menu bar (AppKit)**: the application menu has About, Hide
  (⌘H), Hide Others, Show All and Quit (⌘Q quits); File has New Note (⌘N) after
  the New item's slot and Close (⌘W); Edit ▸ Copy and Paste reach a focused
  `TextField` (the popover's field) by click and by key; a Demo menu sits
  before Window with Say Hello (⇧⌘H) and Pinned. Pinned by
  `theDefaultMenuBarHasTheStandardMenus`, `theMainMenuMapsStandardActionsToAppKitSelectors`,
  `theEditMenuReachesTheFocusedFieldAsItsKeys`. **Observed:**
- [ ] **R4. One shortcut, one action**: ⌘D (the card's Duplicate, a context
  item — inactive while the menu is closed, C12) and ⇧⌘H (Say Hello) each fire
  once per press, the status line naming them. Re-run
  `swiftui-commands.swift` unlocked with a key window to settle `MN-J` item 4's
  order, and confirm AppKit hands `performKeyEquivalent(with:)` and
  `keyDown(with:)` the same event (`MN-AF` item 8). Pinned by
  `aButtonsShortcutWinsOverACommandsAndFiresOnce`,
  `aKeyEquivalentDeclinedByTheWindowIsNotDeliveredAgainAsAKeyDown`. **Observed:**
- [ ] **R5. The popover**: Show popover presents a rounded panel above the
  button (no arrow — divergence 112), 8 pt from it; drag the window small so it
  cannot fit above: it flips below, and is kept inside the window (divergence
  111). Escape closes it; a click outside closes it **and** reaches what it
  lands on; a click on Show popover closes it (it does not re-open); clicks in
  the field and on Close work. Re-run the probe's P3/P4 unlocked to see whether
  a native transient `NSPopover`'s outside click reaches what it lands on
  (`MN-Y` passes it through on P4a's reading). Pinned by `PopoverTests` 3.1–3.8,
  3.26. **Observed:**
- [ ] **R6. Tooltips**: rest the pointer on "Hover me": after about a second a
  small panel appears below the pointer with the text; a click, a key, the
  wheel or moving off hides it, and it returns only after leaving and coming
  back. "Me too"'s text wraps. Compare the delay and look with a native AppKit
  tooltip (re-run the probe's H7 unlocked; divergence 113). Pinned by
  `TooltipTests` 3.17–3.21, 3.24. **Observed:**
- [ ] **R7. VoiceOver**: VO-Shift-M on the card opens its menu; the popover
  reads as a popover (VoiceOver does not trap focus in it); a hint's text is
  read as help. Pinned by `aShowMenuRequestOpensTheElementsMenu`,
  `thePopoverPublishesAPopoverNodeAndIsolatesNothing`,
  `helpPublishesTheSameTreeAsAccessibilityHint`. **Observed:**
- [ ] **R8. A right click presses nothing**: a right click on Show popover does
  not present the popover (divergence 110; a SwiftUI `Button` would press).
  Pinned by `aSecondaryPressNeverRunsOnClickOrATap`. **Observed:**

## S. Colour and colour scheme (user request 2026-10-02, not a plan task)

*Source: record §75 `75-colour.md`, rulings `CR-A`…`CR-Z`
(`docs/superpowers/2026-10-03-colour-decisions.md`), spec §9
(`docs/superpowers/specs/2026-10-03-colour-design.md`).* The SwiftUI probe
(`docs/probes/swiftui-colour.swift`) read every named static's resolved value
in light and dark, but every session so far ran with the screen **locked**:
no MetalUI colour, no live appearance switch and no forced appearance has been
seen on a real display. MetalUI's answers are pinned headless. Run
`METALUI_LOOKS_DEMO=1 swift run -c release MetalUIDemo` (AppKit; the colour
section is the looks window's bottom row) and, for S4, `METALUI_LOOKS_DEMO=1`
with `Backends/SDL`'s `MetalUISDLDemo` on Linux or Windows.

- [ ] **S1. Colours against a SwiftUI reference, side by side**: beside the
  demo, run a SwiftUI window of the same swatches (save as `/tmp/ref.swift`,
  `xcrun swiftc -parse-as-library /tmp/ref.swift -o /tmp/ref && /tmp/ref`):

  ```swift
  import SwiftUI
  @main struct Ref: App {
      var body: some Scene { WindowGroup { HStack(spacing: 4) {
          ForEach(Array([Color.gray, .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue,
                         .indigo, .purple, .pink, .brown, .black, .white, .clear, .primary,
                         .secondary, .accentColor, Color(red: 0.2, green: 0.4, blue: 0.6)].enumerated()),
                  id: \.offset) { $0.element.frame(width: 28, height: 28).border(.separator) }
      }.padding() } }
  }
  ```

  Expect each hue to match in hue and lightness, **slightly more saturated**
  in MetalUI (sRGB numbers on a Display P3 layer, divergence 1), the literal
  likewise; `primary`, `secondary` and `accentColor` differ by design — they
  follow MetalUI's theme, not the system's label and accent colours
  (divergence 116). Repeat with System Settings → Appearance on Dark: the dark
  halves (spec §3.2). The `light/dark` swatch is a pale gold in light and a
  blue in dark; the `LooksBrand` swatch a purple in light and a **green** in
  dark (the demo's override of the palette key, `CR-N`). Pinned by
  `everyNamedStaticResolvesToTheProbedValueInBothSchemes`,
  `theSemanticStaticsResolveThroughTheTheme`,
  `theLooksColourSectionPaintsLiteralDynamicAndPaletteColours`. **Observed:**
- [ ] **S2. Live appearance switching**: with the demo open and the toggle on
  System, switch System Settings → Appearance between Light and Dark. The
  content, the title bar and the dynamic and palette swatches flip within a
  frame; **nothing fades** (`CR-H` item 3); the `scheme:` label reads the new
  scheme. Pinned by `anAppearanceChangeRebuildsWithTheNewScheme`,
  `aSchemeChangeNeverStartsAFadeOnADynamicColour`,
  `theWindowFollowsTheApplicationsEffectiveAppearance`. **Observed:**
- [ ] **S3. The scheme toggle**: press "Appearance: System" — it cycles Light,
  Dark, System. Light and Dark force the **whole window** — content and title
  bar — regardless of the system setting (`.preferredColorScheme` is
  window-wide, `CR-L`), and the `scheme:` label follows; System returns to the system's appearance. No
  one-frame flash on a toggle. Pinned by `preferredColorSchemeIsWindowWide`,
  `aLaterPreferenceChangeAppliesOnTheNextFrame`,
  `clearingThePreferenceReturnsToThePlatformsAppearance`,
  `settingAPreferredColorSchemeSetsTheNSWindowsAppearanceAndReportsIt`.
  **Observed:**
- [ ] **S4. SDL (Linux or Windows)**: the system theme switch (GNOME/KDE dark
  style, Windows' app mode) is followed live as in S2. Under the toggle the
  content flips while the **native decorations stay with the system** — SDL3
  has no per-window appearance (`CR-M`). Pinned by
  `setPreferredColorSchemeIsRecordedAndTheSystemThemeStillReports`
  (`Backends/SDL`). **Observed:**

## T. Lifecycle modifiers — onAppear, onDisappear, onChange (user request 2026-10-02, not a plan task)

*Source: record §76 `76-lifecycle.md`, rulings `LC-A`…`LC-S`
(`docs/superpowers/2026-10-03-lifecycle-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-03-lifecycle-design.md`).* Every lifecycle
answer is pinned headless (`LifecycleTests`, `LooksLifecycleDemoTests`, and
`SDLLifecycleTests` in `Backends/SDL`), with the display link driven by
`simulateTick(timestamp:)`; nobody has watched a removal fade end on a real
display link. Run `METALUI_LOOKS_DEMO=1 swift run -c release MetalUIDemo`
(AppKit); the lifecycle section is at the top of the looks window's left
column, beside H1: "Toggle tile", "Toggle fading tile", a stepper, and four counters
(appeared, disappeared, faded, changes), each as text and as a bar 8 points per
count.

- [ ] **T1. A disappearance waits for its fade**: press "Toggle fading tile" to
  show the tile, then press it again. The tile fades out over about 0.8 s; the
  **faded** counter (and its orange bar) moves **when the fade ends**, not on
  the click (`LC-H`, probe `swiftui-lifecycle.swift` `T1`/`T3`). Pressing it
  again during the fade brings the tile back and the counter does not move
  (`T4`; divergence 123). Pinned by `anOnDisappearOutsideTheTransitionAlsoWaits`,
  `reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`,
  `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`.
  **Observed:**
- [ ] **T2. Counters stay paired**: press "Toggle tile" quickly five times on
  and five off (ten presses). At rest the **appeared** and **disappeared**
  counters are equal (5 and 5), the bars equal length, and the window goes
  idle (no busy display link). Press the stepper's + three times: **changes**
  reads 3. Pinned by `anIfThatInsertsContentRunsItsOnAppearOnce`,
  `anIfThatRemovesContentRunsItsOnDisappearOnce`, `aSettledWindowGoesIdle`,
  `theLooksLifecycleSectionCountsAppearancesDisappearancesAndChanges`.
  **Observed:**

## U. Platform services — file dialogs, alerts, window sizing, hover, `Divider`, menu picker (user request 2026-10-02, not a plan task)

*Source: record §77 `77-platform-services.md`, rulings `SV-A`…`SV-AK`
(`docs/superpowers/2026-10-04-platform-services-decisions.md`), spec §9
(`docs/superpowers/specs/2026-10-04-platform-services-design.md`).* **The
demo**: `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo` (AppKit) and the same
flag on `MetalUISDLDemo` (Linux, Windows, or macOS over SDL) open
`servicesDemoContent()` at 960 × 640 with a 900 × 600 minimum: Import…,
Export… and "Open… (async)" buttons with the last outcome as text, a
"Delete…" alert, three hover tiles (colour, an enter counter and an 8-point
bar per enter), `Divider`s in a `VStack`, an `HStack`, a `Column` and a `Row`,
and a 300-option menu picker. Every answer here is pinned headless
(`PresentationTests`, `FileDialogTests`, `AlertTests`, `AlertPanelTests`,
`HoverTests`, `WindowSizingTests`, `AppKitPresentationTests`, `DividerTests`,
`MenuPickerTests`, `MenuPanelScrollTests`, `ServicesDemoTests`, and
`SDLPresentationTests`/`SDLMainQueueDrainTests` in `Backends/SDL`); nobody has
looked at a real panel, sheet, menu or pointer.

- [ ] **U1. AppKit open panel is a sheet**: a button that sets `isPresented`
  for `.fileImporter(allowedContentTypes: [.json])`. The open panel drops as a
  sheet on the window, offering JSON files; Cancel and Open both return the
  sheet and the window is usable (`SV-F`; `appKitOpenDialogIsASheetWithTheDeclaredTypes`).
  **Observed:**
- [ ] **U2. AppKit save panel**: `.fileExporter(item: Data, contentTypes:
  [.json], defaultFilename: "keymap")`. The sheet is named "keymap" with the
  extension handled by the panel and an "Export" prompt; saving writes the
  file (`appKitSaveDialogCarriesTheNameTypesAndExportPrompt`). **Observed:**
- [ ] **U3. Linux and Windows desktop dialogs and the main-queue drain**:
  the same two buttons and an `await fileDialogs.openFiles(…)` from a `Button`
  action under SDL. The desktop's dialog (portal, zenity or the Windows one)
  opens, and the chosen path appears **without moving the pointer** — the
  main-queue drain (`SV-H`; macOS cannot see the drain, only Linux can).
  **Observed:**
- [ ] **U4. AppKit alert sheet**: an `.alert` with a destructive "Delete" and
  a cancel. A sheet; Cancel on the left, Delete on the right in red; Escape
  cancels; with the app **active** and the sheet key, an alert with plain "Save",
  "Discard" and a synthesized Cancel — does Return press Save? (`SV-X`: headless,
  SwiftUI's did not; if an active one does, the drawn alert's rule moves.)
  **Observed:**
- [ ] **U5. Hover**: tiles that change colour under `.onHover`. A tile
  highlights under the pointer and un-highlights when the pointer leaves the
  tile and when it leaves the window (both platforms); of two overlapping tiles
  only the top one highlights over the overlap (`SV-Z`). SwiftUI's own reading
  is unmeasured (probe `H` is a broken instrument). **Observed:**
- [ ] **U6. Window limits**: `openWindow(minSize: 900×600)`. Dragging the
  window edge stops at 900 × 600 on both platforms; raising `minSize` past
  `maxSize` and back leaves the larger minimum in force on SDL (`SV-AG`).
  **Observed:**
- [ ] **U7. A content-following minimum**: `windowResizability: .contentMinSize`
  with content that grows when a toggle is pressed. The window cannot be dragged
  below the content, and the minimum grows with it; `.contentSize` also stops
  the window growing past the content (`SV-L`; divergence 126). **Observed:**
- [ ] **U8. SDL drawn alert**: the demo's "Delete…" under `MetalUISDLDemo`.
  A translucent scrim over the window, a 260-wide panel 24 from the top with
  the bold title and the message; Cancel on the left, Delete on the right, and
  **no** button accented (a destructive button suppresses the default, `SV-X`);
  Return does nothing, Escape cancels; Tab and the arrows move a ring, Space
  presses the ringed button; clicks and keys beneath do nothing; an open drawn
  menu closes when the alert appears; Orca or Narrator announce an alert with
  two buttons (`SV-J` items 2–4). **Observed:**
- [ ] **U9. AppKit menu picker**: the demo's "Key" picker. The button shows
  "Key 42 ⌄", is as wide as the widest option, and opens a native menu of 300
  items with a check on the selection, below the button (`SV-P` item 4;
  SwiftUI's pop-up placement over the button is deferred); choosing writes
  "Selected: n"; VoiceOver reads a pop-up button (`SV-S`). **Observed:**
- [ ] **U10. SDL drawn menu picker scrolls**: the same picker under
  `MetalUISDLDemo`. The drawn menu is clamped to the window less 4 points
  above and below, opens with "Key 42" highlighted and in view, scrolls by the
  wheel and by ↑/↓ (the highlight stays in view), shows ▴/▾ at an edge with
  more rows, and a click chooses the row under the pointer (`SV-Q`).
  **Observed:**
- [ ] **U11. `Divider` look**: the demo's four stacks, in light and dark. A
  1-point hairline in the separator colour — horizontal in the `VStack` and
  `Column`, vertical in the `HStack` and `Row`, spanning the stack's cross
  size (`SV-O`; divergence 127: SwiftUI's is a translucent black or white).
  **Observed:**
- [ ] **U12. The demo's dialogs and hover on both platforms**: U1–U3 and U5
  through the demo's own buttons and tiles — the outcome line names the file;
  each tile's counter and bar grow by one per entry and the tile un-highlights
  when the pointer leaves the window. **Observed:**

## V. Proposal controls — controls in SwiftUI stacks (user request 2026-10-02, not a plan task)

*Source: record §78 `78-proposal-controls.md`, rulings `PE-A`…`PE-Z`
(`docs/superpowers/2026-10-06-proposal-controls-decisions.md`), spec §9
(`docs/superpowers/specs/2026-10-06-proposal-controls-design.md`).* **The
demo**: `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo` (920 × 560). The
legacy controls are on the left; on the right, "SwiftUI vocabulary": the
probe's form `FM0` — Name and a field, an Enabled toggle and Apply, Speed and
a slider, a menu picker (Mode, bound to the left's Flavor), a divider, a Qty
stepper (bound to the left's Quantity) — and under it the configurator's
status bar `ST0` (a dot, Enabled/Disabled, Qty, Speed %, the flavour, and the
name at the trailing edge). Every frame here is pinned headless
(`aSwiftUIVocabularyFormLaysOutAsTheProbeArrangesIt` 1.5,
`theConfiguratorsStatusBarLaysOutInTheSwiftUIVocabulary` 1.6,
`theControlsDemosSwiftUISectionLaysOutWithoutReports` 3.1) and every
behaviour in a proposal stack against the same tree in a `Row`/`Column`
(`ProposalControlsTests` 1.11–1.19); what nothing headless sees is the look,
the real pointer and keyboard, and VoiceOver.

- [ ] **V1. The form's rows read as `FM0`'s**: the field and the slider fill
  to the form's trailing edge (16 points in), Apply sits at the trailing
  edge, the toggle and the stepper hug their labels, the menu picker hugs
  (as wide as its label and widest option), the divider spans the form; the
  status bar is one 26-point row, its last label at the trailing edge
  (`PE-B`, `PE-D`). **Observed:**
- [ ] **V2. The controls behave as the legacy ones**: click Apply (clears the
  name), the toggle, the slider (drag and click), the stepper's arrows, the
  menu picker (a native menu; choosing a flavour moves the left's Flavor
  selection too); Tab from the left's controls reaches the form's in reading
  order (a click does not focus a control, divergence 94; it does focus the
  field); Space presses the focused button or toggle, the arrows move the
  focused slider and stepper; typing in the field updates the status bar's
  trailing label each keystroke (`PE-I`). **Observed:**
- [ ] **V3. VoiceOver** (an agent cannot): VO-→ through the form announces
  each control as the same control on the left — "Enabled, checkbox", "Apply,
  button", the slider's value, "Qty, 2, stepper", the field's placeholder and
  text, the menu picker as a pop-up button (`PE-I`; divergence 82 for the
  stepper's title). **Observed:**
- [ ] **V4. Narrower than the form**: drag the window narrower (to about 600
  points). The form gives up width from its greedy controls first — the field
  and the slider shrink (headless at a 600-point window: 165 and 161, where
  they are about 324 and 321 at 920) while Apply keeps its ~59 points and the menu
  picker its minimum (divergence 130: SwiftUI's would compress); labels wrap
  to a second line rather than overlap (`PE-D`, `PE-N`). **Observed:**
- [ ] **V5. The stack warning** — **suspended** (`PE-T`, `PE-Y`): spec §9's V5
  asked a debug scratch app with a 12-way inline `switch` to print one stack
  warning; that warning (`PE-L` item 4) is not landed, because four of the
  repository's own demos measure above its 512 KiB threshold. This item is
  re-written when `PE-L` is re-taken. Mark it N/A. **Observed:**

## W. Port gaps, medium — field chrome, `layoutPriority`, environment objects, window toolbar (user request 2026-10-02, not a plan task)

*Source: record §79 `79-port-gaps-medium.md`, rulings `MD-A`…`MD-Z`
(`docs/superpowers/2026-10-07-port-gaps-medium-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-07-port-gaps-medium-design.md`).* **The
demo**: `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo` (AppKit), and the same
tree in an SDL window for W4. Below the controls, "Port gaps": five fields
240 wide (default, `.roundedBorder`, `.squareBorder`, `.plain`, disabled), a
60-tall `TextEditor`, a 360-wide row ("Label" 80 wide, then a prioritised
grower), and "Environment object: 0" with an Increment button. The window's
toolbar holds Back (leading), a List/Grid segmented picker (centred), an
Advanced checkbox, a Share image button and a search field (trailing).
Pinned headless: the fields' heights, the row's widths, the object's text and
the toolbar's five items (`theControlsDemoShowsThePortGapsSection` 3.16), the
chrome (`TextFieldChromeTests`), the native toolbar's items and actions
(`AppKitToolbarTests`), the drawn strip's geometry, timing and controls
(`ToolbarStripTests` 3.6–3.10); what nothing headless sees is the look, the
real pointer and keyboard, the window's titlebar, and VoiceOver.

- [ ] **W1. Field chrome** (light, then dark — System Settings → Appearance):
  the five fields read as macOS text fields; the default, rounded and square
  ones identical (rounded 6-point corners, a thin border, the surface fill);
  `.plain` bare text; the disabled one's text dimmed to a third, its box
  unchanged; clicking a field draws the accent focus ring, and the ring greys
  when another app is active (`MD-B`…`MD-E`, divergence 132; AppKit's own
  glow is not drawn). **Observed:**
- [ ] **W2. `TextEditor`'s fill** reads as an editor's opaque background in
  both schemes, square-cornered, its ring square when focused (`MD-F`,
  divergence 133). **Observed:**
- [ ] **W3. Toolbar, AppKit**: a unified toolbar under the traffic lights
  holds Back (leading), the segmented picker (centred), Advanced, the Share
  image and a search field (trailing); clicking each acts once (Back and
  Share leave no visible trace; the picker and Advanced keep their state; the
  search field takes text); the window opened 20 points taller than its
  content, the content unchanged; the overflow chevron appears when the
  window is narrowed; with a MetalUI field focused, clicking the search field
  leaves one caret blinking where you type, and clicking back in the MetalUI
  field types there again (`MD-J`, `MD-U` item 3, `MD-X` item 2).
  **Observed:**
- [ ] **W4. Toolbar, SDL** (Linux or Windows; or macOS with the SDL backend):
  the same controls drawn as a 39-point strip across the window's top —
  surface-filled, a separator line under it — Back at the leading edge, the
  picker centred, Advanced, Share and a 160-wide search field at the trailing
  edge; the content sits below the strip (the window is not taller,
  divergence 136); each control works by mouse, Tab reaches the strip's
  controls after the content's, Space presses the focused button, and typing
  in the search field updates it (`MD-K`). **Observed:**
- [ ] **W5. VoiceOver** (AppKit; an agent cannot, `IX-AE`): VO-Shift-↓ into
  the toolbar announces its native items — "Back, button", the picker's
  segments, "Advanced, checkbox", "Share, button", the search field — and the
  Port gaps section's fields announce their placeholders, the disabled one as
  dimmed. **Observed:**

## X. A MetalUI app on Linux and Windows — portable images, `.task`, a consumable SDL backend (user request 2026-10-02, not a plan task)

*Source: record §80 `80-portable-app.md`, rulings `PX-A`…
(`docs/superpowers/2026-10-07-portable-app-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-07-portable-app-design.md`).* Pinned
headless: the generated cross-platform package building against a URL
checkout in the CI image (`aCrossPlatformPackageBuildsItsSDLAppByURL`, `aCrossPlatformPackageBuildsWithoutAccessKit`, `METALUI_RUN_SDL_CONSUMER_BUILD_TEST=1`),
the decoder's bytes on every platform (`ImageDecodingTests`), `.task`'s order,
cancellation and id restarts (`TaskModifierTests` 3.1–3.19), and a main-actor
task progressing and cancelled under the SDL loop (`SDLMainQueueDrainTests`
3.20 on macOS, 3.21 in the Linux container). What nothing headless sees: a
real Linux or Windows desktop, a counting task in a visible window, Orca, and
the configurator's icons.

- [ ] **X1. A generated app on Linux** (Ubuntu 25.10, or a distribution with
  SDL 3.4+): `metalui new Hello --cross-platform` (the URL default), install
  what its README says, `swift run Hello` — a window opens and draws; text is
  legible; resizing works (`PX-H`, `PX-I`, `PX-J`). Then ship it as
  `docs/packaging.md`'s Linux section 4 says — the release binary and
  `MetalUISDLShaders` copied into a new directory — rename or move the
  checkout's `.build`, and run the copy: the window still opens (`PX-P`).
  **Observed:**
- [ ] **X2. A counting `.task`** in that app: a `Text("\(n)")` with `.task {
  while !Task.isCancelled { n += 1; try? await Task.sleep(for: .seconds(1)) }
  }` counts once a second in a real SDL window on Linux and on Windows, stops
  when a toggle removes it, and restarts from 0 when it returns (`PX-F`,
  `SV-H`). **Observed:**
- [ ] **X3. Orca** reads the window's controls with the `AccessKit` trait; with
  `--no-accesskit` the app runs and Orca sees an unlabelled window (`PX-H`
  item 2). **Observed:**
- [ ] **X4. The same generated app on Windows**, built per its README
  (`PX-I`). **Observed:**
- [ ] **X5. The configurator's icons** (light and dark) on Linux look as on
  macOS (`PX-C`; divergence 138 — its icons are untagged). **Observed:**

## Y. Input APIs for viewports and canvases — scroll wheel, magnify/rotate, other buttons, tap location, pointer style (user request 2026-10-02, not a plan task)

*Source: record §81 `81-input-apis.md`, rulings `CI-A`…
(`docs/superpowers/2026-10-08-input-apis-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-08-input-apis-design.md`).* Pinned
headless: the seam on both platforms (`AppKitInputAPITests`,
`SDLInputAPITests`), the gestures and their arenas
(`InputAPIGestureArenaTests`, `InputAPIGestureWindowTests`), the wheel chain
and the pointer style (`InputAPIWindowTests`), and the demo's arithmetic
(`theCanvasDemoPansZoomsAboutThePointerPicksAndShowsACrosshair`, 3.35). What
nothing headless sees: a real trackpad's phases, momentum and pinch, a real
cursor on screen, a real mouse's middle and right buttons, and SDL on a Linux
or Windows desktop. Every check runs `METALUI_CANVAS_DEMO=1 swift run
MetalUIDemo` (AppKit) or, from `Backends/SDL`, `METALUI_CANVAS_DEMO=1 swift
run MetalUISDLDemo` (SDL); the status line under the canvas reports what each
check reads.

- [ ] **Y1. Trackpad scroll pans with momentum** (AppKit): a two-finger scroll
  on the canvas pans it and keeps gliding after the fingers lift; during the
  glide the status line's momentum phase reads `changed`, then `ended`
  (`CI-I` item 1). **Observed:**
- [ ] **Y2. Pinch zooms about the pinch centre** (AppKit): the node under the
  fingers stays under them while the zoom changes (`CI-C`, `startLocation`).
  **Observed:**
- [ ] **Y3. Rotate** (AppKit): a two-finger twist over the "Revolve" node turns
  it, and the status line's rotation is positive for a clockwise twist
  (`CI-C` item 2, probe `Q1`). **Observed:**
- [ ] **Y4. Nested magnify and rotate**: a pinch with a twist over "Revolve"
  (its `RotateGesture` inside the canvas's `MagnifyGesture`) — note whether
  both zoom and rotation change, and what happens when one ends before the
  other (`CI-D` item 3, `CI-AA` item 2: the unmeasured corner).
  **Observed:**
- [ ] **Y5. Every pointer style on AppKit**: over each swatch of the style
  strip the cursor is as named — arrow, horizontal and vertical I-beam,
  crosshair, open and closed hand, pointing hand, zoom in and out, column and
  row resize, the three frame resizes (`CI-H` item 8, probe `P1`–`P19`); the
  crosshair over empty canvas, the pointing hand over a node, the open hand
  over the strip along the canvas's top; **during a fast middle-drag pan that
  leaves the canvas the hand stays closed** (`CI-H` item 6, MetalUI's rule,
  `CI-U` item 3). **Observed:**
- [ ] **Y6. The same strip under SDL** on Linux and on Windows: both hands
  show SDL's move cursor and both zooms the arrow (`CI-H` item 8, a platform
  constraint); the rest as named. **Observed:**
- [ ] **Y7. SDL pinch on Wayland or X11** with a trackpad: the canvas zooms,
  at the speed the macOS SDL build zooms for the same pinch (`CI-K` item 1's
  cumulative-scale reading). **Observed:**
- [ ] **Y8. A real mouse** (both platforms): a middle drag pans; a right drag
  pans and opens no menu; a right-click on a node opens a menu whose first
  item is "Inspect <node>", on the release (`CI-F` item 4, `CI-R`).
  **Observed:**
- [ ] **Y9. Modifiers during a drag**: press ⌥ in the middle of a middle-drag
  pan; the status line's drag modifiers read `⌥` at the next move, not before
  (`CI-G`). **Observed:**
- [ ] **Y10. Windows precision touchpad**: a pinch arrives as ⌃-wheel and the
  demo zooms (there is no `MagnifyGesture` on Windows, `CI-K` item 1).
  **Observed:**
- [ ] **Y11. A notched wheel mouse**: the status line reads `lines` and each
  notch pans 10 points (`CI-I` item 1). **Observed:**
- [ ] **Y12. A style change under a still pointer** (AppKit; `CI-Z` item 5):
  rest the pointer over empty canvas and press **C** without moving it — the
  crosshair turns to the arrow at once, and back on a second **C**
  (`setPointerStyle`'s immediate set, which no agent can drive).
  **Observed:**
- [ ] **Y13. No wheel latching** (`CI-AD`): flick the canvas so it glides, then
  move the pointer onto the style strip mid-glide: note whether the glide
  stops (MetalUI dispatches each wheel event by the pointer), and what a
  native AppKit scroll view (Finder, a long text document) does in the same
  motion — the answer is the input of `CI-AD`'s unbuilt probe.
## RT. Rich text — Markdown, interpolation, attributed strings, decorations (user request 2026-10-02, not a plan task; provisional letter, settled at the merge)

*Source: record §83 `83-rich-text.md`, rulings `RT-A`…
(`docs/superpowers/2026-10-08-rich-text-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-08-rich-text-design.md`).* Pinned headless:
the parser against Foundation's on 2498 sources (`theParserAgreesWithFoundationOnTheCorpus`),
the runs every spelling builds (`LocalizedStringKeyTests`, `AttributedTextTests`),
styled measurement and paint on both text systems (`StyledTextSeamTests`,
`StyledTextOracleTests`, `RichTextTests`, `RichTextPaintTests`,
`RichTextPortableWindowTests`) and the demo drawn headlessly through the
portable system (`theRichTextDemoDrawsThroughThePortableSystem`). What nothing
headless sees: the look on a real display, VoiceOver, the cursor.

- [ ] **RT1. The rich-text demo on macOS**, `METALUI_RICH_TEXT_DEMO=1 swift run
  MetalUIDemo`: every Markdown form reads as styled — bold, italic, bold
  italic, struck, monospaced code, an accent-coloured link and bare URL — in
  light and dark (`RT-B`, `RT-K`). **Observed:**
- [ ] **RT2. Underlines and strikethroughs** at 1× and 2× displays look crisp
  enough beside a SwiftUI `Text(…).underline()` (divergence 152's unsnapped
  band, `RT-J`). **Observed:**
- [ ] **RT3. The mixed-size paragraph**: line spacing looks even and no glyph
  is clipped by its line; the superscript sits above the line without
  touching the line above (`RT-G`). **Observed:**
- [ ] **RT4. The same demo on Linux and Windows** (SDL,
  `METALUI_RICH_TEXT_DEMO=1`, `Backends/SDL`'s demo): matches macOS by eye,
  except code spans, which draw the default face unless the app registered a
  monospaced family (`TE-B`, `RT-O` item 12). **Observed:**
- [ ] **RT5. VoiceOver** on a styled `Text` reads the whole sentence once,
  without Markdown markers; a link is read as plain text (`RT-L` item 1,
  divergence 150). **Observed:**
- [ ] **RT6. Clicking a link** does nothing and the cursor does not change
  (divergence 150). **Observed:**

## VL. Variable-height `List` (user request 2026-10-02, not a plan task)

*Source: record §82 `82-variable-height-list.md`, rulings `VL-A`…
(`docs/superpowers/2026-10-08-variable-height-list-decisions.md`), spec §8
(`docs/superpowers/specs/2026-10-08-variable-height-list-design.md`). The
group's letter is provisional — the merge settles it beside the parallel
branches' groups.* Run `METALUI_LIST_DEMO=1 swift run MetalUIDemo` (AppKit) and,
from `Backends/SDL`, `METALUI_LIST_DEMO=1 swift run $(python3 scripts/fetch-accesskit.py
--print-flags) MetalUISDLDemo` (`PX-I`); do each check in both. Pinned
headless: row sizing at the list's width, windowing by prefix offsets, the row
on top held across measurements, width changes and insertions, `scrollTo` onto
an unmeasured row, selection and focus (`VariableHeightListTests` 2.1–2.18),
the index (`RowExtentIndexTests`), the demo windowed and settling
(`theVariableListDemoSettlesHeadless`). What nothing headless sees: real text
wrapping in a real window, the wheel, the scroll thumb, a live resize.

- [ ] **VL1. Scrolling.** Scroll the list top to bottom and back with the wheel
  and with the thumb: rows of three heights (one line, two lines, a
  paragraph), no gap at the viewport's edges, no row drawn over another
  (`VL-B`, `VL-F`). **Observed:**
- [ ] **VL2. No jump while rows above re-measure.** Resize the window narrower,
  scroll to the bottom, then scroll up quickly: the row at the top of the
  viewport stays put while rows above it are measured anew; the thumb may move
  (`VL-G`). **Observed:**
- [ ] **VL3. The jump.** Press "Jump to row 250": row 250 lands at the top of
  the viewport and stays there over the next frames (`VL-H`). **Observed:**
- [ ] **VL4. Selection.** Click, ⌘-click (ctrl-click on SDL off macOS),
  ⇧-click and ⇧↓ select as in the controls demo's list ("Selected: n"
  follows); ↓ past the viewport's bottom reveals the lead row fully (`VL-J`,
  `DD-Z`). **Observed:**
- [ ] **VL5. Live resize.** Drag the window's width continuously: the text rows
  re-wrap and the top row keeps its place (`VL-E`, `VL-G`). **Observed:**

## WS. AccessKit before the first show (item C11, user request 2026-10-02, not a plan task)

Every SDL window is now created hidden; its AccessKit adapter is made, then the
window is shown (unless `hiddenWindows`), then its renderer claims it (rulings
`WS-A`…`WS-H`, record §86). Run the SDL demo from `Backends/SDL`: `swift run
$(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo` (`PX-I`; on
Windows the CI `windows` job's flags). Pinned headless: the order on SDL's own
flag (`SDLWindowShowOrderTests` T1–T4, every platform), and on Windows CI a
launch of the demo that must survive 8 s (`WS-E`). What nothing headless sees:
the native window's appearance, focus and a screen reader.

- [ ] **WS1. Windows, interactive desktop.** `MetalUISDLDemo.exe` (AccessKit
  on) opens without a panic; the window appears at 920 × 560, focused, its
  title in the taskbar; Narrator announces the window and reads a button
  (`WS-A`, `WS-B`). **Observed:**
- [ ] **WS2. Linux, X11 and Wayland desktop.** The demo window appears focused
  at its size and draws its first frame; Orca reads the window title (`WS-B`,
  `WS-F` item 3). **Observed:**
- [ ] **WS3. macOS, the SDL demo.** The window appears key and draws its first
  frame; VoiceOver (⌘F5) reads the window through AccessKit's macOS adapter,
  now made before the show (`WS-B`). **Observed:**
- [ ] **WS4. smk_configurator, after its MetalUI pin bump.** The packaged
  Windows app's "Launch the packaged app" CI step passes (`WS-F` item 4).
  **Observed:**

## KF. Key and focus scoping — `onKeyPress`, key regions, focus on press, `onGeometryChange`, `TimelineView` (item C9, user request 2026-10-02, not a plan task)

SwiftUI's `onKeyPress` family on both vocabularies, MetalUI's hover key
regions, focus on a press for `.focusable(interactions: .edit)`, a proposal
`KeyboardModifier` layer, `onGeometryChange` and `TimelineView` (rulings
`KF-A`…`KF-Z`, record §88). Run `METALUI_KEY_FOCUS_DEMO=1 swift run MetalUIDemo`,
and the SDL demo from `Backends/SDL` with the same variable (`swift run
$(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo`). The status
line shows the last key and its walk (`root › …`). Pinned headless: the
pipeline order, the key chain, the press stage, the geometry and timeline
events (`KeyPressTests`, `HoverKeyRegionTests`, `FocusOnPressTests`,
`KeyboardModifierTests`, `GeometryChangeTests`, `TimelineViewTests`,
`KeyFocusDemoTests`). What nothing headless sees: a real keyboard, a real
pointer, an input method, the display link and the menu bar.

- [ ] **KF-1. Order and the palette.** With a real keyboard (AppKit, and SDL on
  Linux/Windows), hover the canvas with nothing focused and press Tab: the
  palette opens and the walk reads `root › canvas` — the ancestor first. In
  the palette's focused search field ↑/↓ move the highlight (the caret does
  not move) and Return picks ("picked …") without inserting anything; Escape
  closes it (`KF-B`, `KF-C`). **Observed:**
- [ ] **KF-2. Hover routing.** With nothing focused, Tab over the canvas opens
  the palette and Tab elsewhere does not; with the Name field focused, Tab
  moves focus to Depth wherever the pointer rests (`KF-D`). **Observed:**
- [ ] **KF-3. Clicks and focus.** With a field focused, a click on the header
  text leaves it focused (RS1, `KF-G`); a click on the canvas clears it
  (`KF-E` item 5); a click on the viewport focuses it and a key then reads
  `root › viewport` with the viewport's key count going up (`KF-F`, `KF-H`).
  **Observed:**
- [ ] **KF-4. The viewport's size.** On launch the status line's viewport size
  reads 240 × 200 in the first frame; resizing the window does not change it
  (the viewport has a fixed frame) and nothing lags (`KF-J`). **Observed:**
- [ ] **KF-5. The timeline.** The "orbit" label circles the viewport smoothly,
  one turn about every six seconds; closing the demo's other animations, the
  display link runs only while the label is on screen (`KF-K`). **Observed:**
- [ ] **KF-6. Native menu items.** With the viewport focused (its catch-all
  `onKeyPress` answers `.handled`), ⌘Q and ⌘H are swallowed (divergence 188);
  with the viewport not focused they quit and hide as usual. (An app
  command's ⌘-key running the command is pinned headless, A43, `KF-X`.)
  **Observed:**
- [ ] **KF-7. The digit filter.** Typing into the Depth field: letters never
  appear, digits do; an input method's composition (AppKit Japanese IME; SDL
  on Linux with IBus) is unaffected (`KF-Q`, divergence 187). **Observed:**

## AS. App shell — close veto, quit hook, title and edited marker, hidden title bar, open-document events (item C8, user request 2026-10-02, not a plan task)

*Source: record §87 `87-app-shell.md`, rulings `AS-A`…
(`docs/superpowers/2026-10-08-app-shell-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-08-app-shell-design.md`).* Run
`METALUI_APP_SHELL_DEMO=1 swift run MetalUIDemo` (AppKit; AS1–AS8) and, from
`Backends/SDL`, `METALUI_APP_SHELL_DEMO=1 swift run $(python3
scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo` (`PX-I`; AS10).
Pinned headless: the close and terminate state machines and the walk
(`AppShellTests` 2.2–2.15), the drawn alert answering later (2.5), the title,
document and edited marker reaching the platform (`WindowTitleTests`), the
insets and the band press (2.21, 2.21b), open-URL routing (`OpenURLTests`),
the AppKit delegate and window wiring (`AppKitAppShellTests` 1.3–1.11), SDL's
quit, close and window-0 drop (`SDLAppShellTests`, `SDLAppShellAppTests`
3.1–3.3), and this demo (`AppShellDemoTests` 3.4–3.4c). What nothing
headless sees: the native title bar, the sheet, the edited dot, a real drag,
logout, Finder.

- [ ] **AS1. Close with unsaved changes.** Press "Make a change", then the
  red close button: an alert sheet asks "Do you want to save the changes made
  to “Untitled.mcgraph”?". Cancel keeps the window (still edited); Save clears
  the marker and closes; Don't Save closes; with the last window gone the app
  quits (`AS-B`, `AS-C` item 5). A clean window closes at once. **Observed:**
- [ ] **AS2. ⌘Q with unsaved changes.** After "Make a change", ⌘Q shows the
  same alert; Cancel keeps the app running; Don't Save quits (`AS-C` item 2:
  no `App.onTerminateRequest`, so the window is asked). **Observed:**
- [ ] **AS3. Log out with unsaved changes.** Choose Log Out from the Apple
  menu with the document edited: the alert appears and logout waits for it
  (`.terminateLater`); the window keeps drawing meanwhile (type in the name
  field); Cancel cancels the logout (`AS-C` item 9). **Observed:**
- [ ] **AS4. The edited dot.** The close button shows its dot after "Make a
  change" and loses it after "Save"; the top bar's "— Edited" follows
  (`AS-D` item 4). **Observed:**
- [ ] **AS5. A represented document.** In a scratch app with
  `.navigationDocument(URL(fileURLWithPath: "/tmp/x.mcgraph"))` (the demo
  has none): the proxy icon appears beside the title, and ⌘-click on the title
  shows the path menu (`AS-D` item 3). **Observed:**
- [ ] **AS6. Hidden title bar.** The traffic lights sit over the top bar, its
  name starts right of them, and no title text is drawn; the window's title in
  the Window menu and Mission Control is the name field's text (`AS-E`,
  `.navigationTitle`). **Observed:**
- [ ] **AS7. The band drag.** Dragging the top bar's empty area moves the
  window; a double-click there zooms (or minimises, per System Settings →
  Desktop & Dock → "Double-click a window's title bar to"); a press on the
  name field or a button never drags (`AS-J`). **Observed:**
- [ ] **AS8. Full screen.** Enter full screen (green button): the band goes,
  the top bar sits at the very top with its name 12 points from the left
  edge; leaving full screen restores the inset (`AS-E` item 4). **Observed:**
- [ ] **AS9. Open-document events from a packaged app.** Package the demo as
  in `docs/packaging.md` with a `.mcgraph` document type: a Finder
  double-click, `open -a`, a drop on the Dock icon — with the app not running
  and with it running — each lists the file's URL once under "Opened"; `METALUI_APP_SHELL_DEMO=1
  swift run MetalUIDemo /path/to/file.mcgraph` lists it once too (the
  launch-argument recipe, `AS-G` item 6, `AS-M`). No "cannot open files in
  this format" alert appears without an `NSDocumentClass` (measured for
  `open -a` by probe `appkit-open-without-document-class.swift` `W0`/`W2`;
  confirm it for the double-click and the Dock drop).
  **Observed:**
- [ ] **AS10. SDL (Linux, Windows; macOS too).** With the document edited,
  the window manager's close button and Alt-F4 show the drawn alert; Ctrl-C
  in the terminal (SIGINT → `SDL_EVENT_QUIT`) shows it too; Don't Save ends
  the program. A file dropped on the window is a drag (nothing under
  "Opened"); the title shows no edited marker; the window keeps its system
  title bar, and the top bar's name sits 12 points from the left (insets
  zero, `AS-E` item 6). On macOS, a vetoed close of the only window does not
  quit (`AS-L`: the quit-on-last-window hint is off). **Observed:**

## CL. Controls and looks — colour picker, slider editing, progress, keyframes, gradients, blur, materials (item C10, user request 2026-10-02, not a plan task)

*Source: record §85 `85-controls-looks.md`, rulings `LK-A`…
(`docs/superpowers/2026-10-08-controls-looks-decisions.md`), spec §7
(`docs/superpowers/specs/2026-10-08-controls-looks-design.md`). The group's
letter is provisional — the merge settles it beside the parallel branches'
groups.* Run `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo` (the slider, the
two colour pickers and the progress row) and `METALUI_LOOKS_DEMO=1 swift run
MetalUIDemo` (the keyframes row and the gradients, blur and materials row),
and from `Backends/SDL` the same variables with `swift run
$(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo` (`PX-I`);
do each check in both where it says so. Pinned headless: the slider's
callback order (`SliderEditingTests`), the picker's well, panel, keys and
colour maths (`ColorPickerTests`, `ColorMathTests`), the progress view's sizes,
values and clock (`ProgressViewTests`), keyframe timelines and the animator's
records, gradient pixels against SwiftUI's probe values, blur per leaf, the
material tints over white and black, and the fourteen offscreen images at 0
differing pixels (none renders the controls or looks sections' new rows). What
nothing headless sees: the looks below, the wheel and pointer feel, a real
window's materials, VoiceOver (**an agent cannot run it**, `IX-AE`).

- [ ] **CL1. The colour well and its panel.** The "Accent" well beside an
  `NSColorWell` (e.g. a Swift playground): same 48 × 24 footprint and rounded
  look; Tab focuses it and draws the control focus ring; a disabled picker is
  dimmed; a click opens the drawn panel anchored to the well, which flips near
  a window edge and closes on Escape and on an outside press (`LK-C`, `LK-D`;
  divergence 165). **Observed:**
- [ ] **CL2. Opacity checkerboard.** With `supportsOpacity`, a selection below
  full opacity shows a checkerboard behind the well's colour and the panel's
  swatch and opacity bar; the "Opaque" picker never does (pinned by nothing:
  review mutation V7). **Observed:**
- [ ] **CL3. Dragging in the panel.** Dragging in the square and the bars feels
  continuous; the square's colours regenerate with the hue (review mutation
  V12 left this unpinned); arrow keys and the hex field commit (`LK-D`).
  **Observed:**
- [ ] **CL4. One undo step per drag.** In MetalCreator with the new
  `Slider(…onEditingChanged:)` and `ColorPicker`, one drag of a slider or the
  panel is one undo step (M5-a, M6-f together; `LK-B`). **Observed:**
- [ ] **CL5. The spinner.** At 32, 16 and 10 points against
  `NSProgressIndicator`'s spinner: size and spoke weight; the step rate looks
  like AppKit's (24 steps per 0.8 s); with Reduce Motion on it still turns
  (`LK-E`, `LK-F`). Also the indeterminate bar's sweep. **Observed:**
- [ ] **CL6. The determinate bar.** Track and fill colours in light and dark,
  in a key window and an inactive one, beside `NSProgressIndicator`
  (`LK-E`). **Observed:**
- [ ] **CL7. Gradients.** A window-background gradient during live resize stays
  smooth (the strip path), and the large diagonal one shows only a first-frame
  raster cost; no visible banding at 8 bits on a P3 display (divergence 1
  applies; `LK-J`). **Observed:**
- [ ] **CL8. Blur.** A blurred text and image at radii 2 and 6 look like
  SwiftUI's at the same radius (`LK-K`). **Observed:**
- [ ] **CL9. Materials.** The six materials over the striped backdrop in both
  schemes: the flat tint versus SwiftUI's blur (divergence 166 is visible by
  design), **and over a uniform backdrop in a real key window**, whether
  SwiftUI's tint matches the ImageRenderer fit (`LK-O` item 2). **Observed:**
- [ ] **CL10. The shake.** The keyframes row's "Shake" reads as a shake at 60 Hz
  and on a 120 Hz display (`LK-H`, `LK-I`). **Observed:**
- [ ] **CL11. VoiceOver.** The well announces its colour; the panel's sliders
  adjust; a determinate progress view announces its fraction; a spinner
  announces busy (`LK-G`; the voiceover script's controls step is unchanged).
  **Observed:**

## PF. Shadow cache — translation-free rasters, `compositingGroup()` (item C13, user request 2026-10-02, not a plan task)

Shadow, blur, path and full-gradient rasters are keyed relative to a floored
device anchor, so a whole-device-pixel move or pan reuses the cached texture;
`compositingGroup()` makes a container one leaf to an enclosing shadow or blur;
`BoxBlur` is faster with byte-identical output (rulings `PF-A`…`PF-N`, record
§90). Pinned headless: work counters (`RasterCache.lastBlurredPixels`,
`lastRasterizedPixels`, `lastTexturesMade`) and texture identity under drags
(`RasterAnchorTests`), the composite's images (`CompositingGroupTests`), the
blur against its 2155f1e copy (L2.1). What nothing headless sees: a real
pointer's sub-pixel positions and the look beside SwiftUI.

- [ ] **PF1. A trackpad drag.** In a MetalCreator-style graph, drag a node with
  `.shadow(radius: 10)` by trackpad at 2×: it moves smoothly; logging the three
  counters per frame shows how many frames hit (a sub-pixel position misses by
  design, `PF-D`). **Observed:**
- [ ] **PF2. `compositingGroup()` beside SwiftUI.** LooksDemo
  (`METALUI_LOOKS_DEMO=1`), "Gradients, blur, materials": the per-leaf pair
  shows the red square's shadow on the blue; the `compositingGroup()` pair one
  shadow under both — as SwiftUI's `P1`/`P2` (`PF-E`). **Observed:**

## OV. Overlays and coordinates — `anchoredOverlay`, point anchors, named spaces, `windowSize` (item C15, user request 2026-10-02, not a plan task)

A chrome-less overlay with its corner at a point, dismissed by any outside
press and Escape; `.popover(attachmentAnchor:)`; named coordinate spaces on
`onGeometryChange`, hover and gestures; `@Environment(\.windowSize)` (rulings
`OV-A`…`OV-T`, record §92). Pinned headless through a fake window
(`AnchoredOverlayTests` B6–B24, `PopoverTests` B1–B5, `CoordinateSpaceTests`
A1–A21). What nothing headless sees: a real pointer, a live resize, the native
context menu over the dismissal. Demo: `METALUI_OVERLAYS_DEMO=1 swift run
MetalUIDemo`. **Not run — an agent cannot.**

- [ ] **OV1. The palette at the pointer.** Click the canvas: the palette opens
  with its top-left corner exactly at the pointer; near the window's right or
  bottom edge it flips to the other side of the pointer on that axis only.
  **Observed:**
- [ ] **OV2. One right-click outside.** With the palette open, right-click the
  "Right-click me" card: the palette closes and the context menu opens on that
  same press; a middle click outside closes it too. **Observed:**
- [ ] **OV3. Keys and Escape.** Click the palette's search field and type: the
  text appears; press Escape with the field focused: the palette closes.
  **Observed:**
- [ ] **OV4. The crosshair.** Move over the canvas: the crosshair from
  `onContinuousHover(coordinateSpace: .named("canvas"))` stays under the
  pointer. **Observed:**
- [ ] **OV5. `windowSize` and a live resize.** Resize the window: the readout's
  window size follows it; an open palette near the edge re-flips in the same
  frame. **Observed:**

## SG. SMK port gaps — the drawn menu bar, the primary modifier, design families, drawn chrome (item C12, user request 2026-10-02, not a plan task; provisional letter, in the manner of `RT`, `AS` and `KF`)

Rulings `SG-A`…`SG-I`, record §89. On Linux and Windows an app declaring
`commands` draws its menu bar in every window (divergence 195); a shortcut
written without modifiers is Ctrl there; `SystemFonts.resolver()` registers
the platform's monospaced and serif families. Run the SDL demo from
`Backends/SDL`: `METALUI_MENUS_DEMO=1 METALUI_SYSTEM_FONTS=1 swift run
$(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo`. Pinned
headless: the bar's layout, titles, opening, switching, F10, Edit delivery and
the chrome height over a fake platform (`MenuBarStripTests`, 2.3–2.16), a real
SDL window's click path (`anSDLWindowDrawsTheCommandsAndAClickRunsOne`, 2.18).
What nothing headless sees: the bar's look, real pointer and keyboard on a
desktop, the monospaced face on screen, a Windows release build.

- [ ] **SG1. Linux and Windows, the menus demo.** A menu bar shows File (New
  Note), Edit and Demo; clicking a title opens its menu under it; moving the
  pointer across titles switches menus; Left/Right switch; F10 opens Edit;
  Escape closes; Demo ▸ Reset Status (no shortcut) sets the status line.
  **Observed:**
- [ ] **SG2.** Ctrl+Shift+H runs Say Hello; Super/Win+Shift+H does not; the
  Demo menu shows "Ctrl+Shift+H". **Observed:**
- [ ] **SG3.** In the popover's focused text field, Edit ▸ Copy, Paste and
  Select All work; with no field focused the Edit items are greyed out.
  **Observed:**
- [ ] **SG4.** The "Shortcut:" line draws in DejaVu Sans Mono (Linux) /
  Cascadia Mono or Consolas (Windows) — monospaced, not the UI face.
  **Observed:**
- [ ] **SG5.** The bar and a toolbar together (the services demo with
  commands, or an app with both): bar on top, strip below, content below both;
  resizing to the minimum keeps the content's minimum visible. **Observed:**
- [ ] **SG6. Windows ARM64 and x64.** `swift build -c release` of the SMK
  configurator (or the `SG-E` fixture) builds, or fails exactly as `SG-E`
  documents. **Observed:**
- [ ] **SG7.** On SDL (Linux, Windows), File ▸ Close closes the window (a
  window with an `onCloseRequest` that cancels stays open) and File ▸ Quit
  ("Exit" on Windows) ends the app; with two windows open Close closes one.
  **Observed:**

## HT. Test harness — a generated test target on Windows, the portable arm with fonts (item 8, user request 2026-10-02, not a plan task; record §91)

*Nothing here is a look: the harness paints nothing. Two measurements the
agent runs could not take (`HT-V` items 4 and 5).*

- [ ] **HT1. Windows, ARM64 and x64.** `metalui new --cross-platform Probe`
  (any source), then `swift build --build-tests` and `swift test` of the
  generated package on Windows (the UTM VM, or a CI consumer job): the test
  target imports the executable `@testable` and the generated test passes. If
  it does not, `HT-O`'s fallback applies: the manifest declares the test target
  off Windows only. **Observed:**
- [ ] **HT2. Linux with fonts installed.** The same generated cross-platform
  package, `swift test`: the Linux arm (`SystemFonts.resolver()` plus
  `PortableTextSystem`) opens its window and the generated test passes. The
  CI image installs no font package, so this needs a host that has some.
  **Observed:**

## IF. Input follow-ups — modifiers on a tap and a still hover, click count, wheel latch, cancellation (item C16, user request 2026-10-02, not a plan task; provisional letter, in the manner of `RT`, `KF` and `SG`)

Run the canvas demo (`METALUI_CANVAS_DEMO=1 swift run MetalUIDemo`): the pad under
the canvas reads `held … · tap … · drag … · scroll … · cancelled …`. **An agent
cannot post these events.** Ruling `IF-D`, record 93.

- [ ] **IF1.** `onModifierKeysChanged`: the `held` readout follows Shift, Command,
  Option and Control held with the pointer still; compare old/new and `initial`
  with a SwiftUI sample app (the probe's `M` arms did not run, `IF-D`); Command-Tab
  away with Command held and back (reads none, then the keys held on return).
  **Observed:**
- [ ] **IF2.** Shift-click the pad's box: `tap` reports Shift, also when Shift is
  released before the button. **Observed:**
- [ ] **IF3.** Double-click the box: `drag` reads `x2` at the speed set in System
  Settings > Mouse (slow it, then speed it). **Observed:**
- [ ] **IF4.** Flick the canvas to glide, move the pointer onto the style strip: the
  glide stays on the canvas. **Observed:**
- [ ] **IF5.** Hold the middle button on the box, open Mission Control or a native
  menu, release there, return: `cancelled` counts one on the first plain move.
  **Observed:**
- [ ] **IF6.** Command-Tab mid-trackpad-scroll over the box: `scroll` shows a
  cancelled phase once. **Observed:**
- [ ] **IF7.** Pinch, Command-Tab, pinch again at the same spot: the first gesture
  reads cancelled, the second starts from 1. **Observed:**

## BB. Backdrop blur behind a Material (item C21, user request 2026-10-02, not a plan task; record §94)

`.background(.ultraThinMaterial)` and the other five materials blur what is drawn
beneath them, GPU surfaces included, on Metal and SDL (rulings `BB-A`…`BB-T`). Pinned
headless: the records and their runs (`BackdropRecordTests`, `BackdropSceneTests`),
the readback against a restated reference on a real Metal device and on SDL's
offscreen renderer (`BackdropRenderTests`, `SDLBackdropTests`), the counters, and
the parity of the Metal renderer against the SDL replay on fixture frames 9–11.
What nothing headless sees: a presenting window, a moving viewport, a live resize,
Direct3D 12, and SwiftUI's own look (it blurs behind the window in a real window,
divergence 245). Run `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo` (the "Gradients, blur, materials" section ends with six materials as panels over
red/blue stripes and a disc) and, for BB1, a `.background(.regularMaterial)` panel
you place over the MetalView demo's viewport (the demo has none: the GPU-surface
case is pinned headless only, `BackdropRenderTests` 2.2, `SDLBackdropTests` 3.5). **An agent cannot.**

- [ ] **BB1. A panel over a viewport.** Over the MetalView demo's viewport
  (`METALUI_METALVIEW_DEMO=1`, with the panel added), each of
  the six materials blurs the viewport behind it (the stripes melt into one colour
  at about a 52-point radius), light and dark; outside the panel the viewport stays
  sharp. Compare with SwiftUI knowing a real window's material blurs *behind* the
  window (divergence 245), and compare the tint with a window capture
  (`docs/probes/window-capture/capture.sh`). **Observed:**
- [ ] **BB2. A panel dragged over moving content.** No tearing, no ghost of the
  previous position, no one-frame lag between panel and blur. **Observed:**
- [ ] **BB3. Nested panels.** A material over a material is blurred twice (the
  upper one sees the lower's result). **Observed:**
- [ ] **BB4. Resize with a panel up.** Resize the window, also across a Retina to
  non-Retina display: no stale or stretched blur, no flash of the unblurred
  frame. **Observed:**
- [ ] **BB5. Windows (Direct3D 12) and Linux.** The same panels on an SDL window:
  the blur matches Metal's by eye (parity frames 9–11 pass in CI; Windows was not
  run locally, `BB-T` item 9). **Observed:**
- [ ] **BB6. A fading panel.** A panel inserted or removed with a transition
  cross-fades with the live backdrop (the ghost blurs what is there now,
  `BB-G`). **Observed:**

## WD. Window drag — `WindowDragGesture` (item C22, user request 2026-10-02, not a plan task; provisional letter, in the manner of `RT`, `KF` and `IF`)

*Source: record 97 `97-window-drag.md`, rulings `WD-A`...
(`docs/superpowers/2026-10-12-window-drag-decisions.md`), spec section 6
(`docs/superpowers/specs/2026-10-12-window-drag-design.md`).* Run
`METALUI_APP_SHELL_DEMO=1 swift run MetalUIDemo` (AppKit; the hidden-title-bar
section's 40-point handle over a canvas whose `DragGesture` counts its drags and
cancellations; WD1-WD6) and, from `Backends/SDL`, `METALUI_APP_SHELL_DEMO=1 swift
run $(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo` (WD7).
Pinned headless: the arena (`WindowDragTests`), the headless seam
(`WindowDragHeadlessTests`), AppKit's held press and dispatch-only drag
(`AppKitWindowDragTests` 4.1-4.3), SDL's record-and-`false` (`SDLAppShellTests` 4.4).
**An agent cannot press and drag a real window; `NSWindow.performDrag(with:)` from a
mouse-dragged dispatch is the unproven call (`WD-D`).**

- [ ] **WD1.** Press-drag on the handle **moves the window**, the canvas count does not
  move (`cut off` does not either unless the press began a canvas drag), and the
  window follows to the release. Compare with SwiftUI's own `WindowDragGesture` in a
  scratch app for what the neighbouring gesture reports (divergence 275; the probe's
  delivery was synthetic). **Observed:**
- [ ] **WD2.** A click on a `Button` placed in the handle clicks it; a 3-point wobble
  does not drag; a 6-point move does, with no jump of the window. **Observed:**
- [ ] **WD3.** After a drag, hover, the pointer style and the next press work, also
  after the window moved under a stationary pointer. **Observed:**
- [ ] **WD4.** A secondary press on the handle opens the context menu and drags
  nothing. **Observed:**
- [ ] **WD5.** A double click on the handle: no zoom (`WD-A`); record what real
  SwiftUI does in the scratch app. **Observed:**
- [ ] **WD6.** Full screen and Stage Manager: dragging the handle does nothing
  harmful (full screen: the window does not move). **Observed:**
- [ ] **WD7.** Linux/Windows (SDL): the handle claims the press and moves nothing;
  the system title bar drags the window (divergence 276). **Observed:**

## SL. Text selection — the binding in a real window (item C25, user request 2026-10-02, MetalCreator CT-b, not a plan task; record §96)

*Run with `METALUI_SELECTION_DEMO=1 swift run MetalUIDemo` (macOS 15). An
agent cannot: these are looks, an input method and other platforms.*

- [ ] **SL1.** Double click the title: it becomes a field with the whole
  title highlighted in the accent wash; typing replaces it; Return or Escape
  ends the rename. **Observed:**
- [ ] **SL2.** "Open note": the editor takes focus with the caret at the end
  of the text and the end in view; typing appends. **Observed:**
- [ ] **SL3.** With a Japanese input method, compose in the title field and
  press "Caret to start" in the note block's neighbour (or write the binding
  from a timer): the marked text stays where it is and the commit lands where
  the composition began (`SL-H`). **Observed:**
- [ ] **SL4.** Click, arrows and Shift-arrows in either field update the
  `selection a..<b` readout. **Observed:**
- [ ] **SL5.** The same demo section on Linux (SDL) and Windows. **Observed:**
- [ ] **SL6.** Type in the note, press "Caret to start", type again, then
  undo: the undo removes the typing, not the caret move (`SL-I`).
  **Observed:**

## GT. Text over a GPU surface — measured labels (item C23, user request 2026-10-02, MetalCreator S5-c, not a plan task; record §99)

*No demo changed and the fourteen images read 0 px; the measure and the portable layout cache
are counted headless. This look is shared with MetalCreator's own check S5c-6. An agent
cannot: a camera moving over a real viewport is a look.*

- [ ] **GT1.** In a 20-label sketch (MetalCreator's viewport), labels sized with
  `@Environment(\.textMeasurer)` get chips that hug their text (no 7-points-a-character
  slack); moving the camera shows no label hitching on a Mac and on the SDL backend; labels
  placed from a `MetalView` viewport's pose stay on their anchors during a pan. **Observed:**

## GC. Continuing press cancel — a lost release (item C26, user request 2026-10-02, MetalCreator VI-b, not a plan task; record §100)

*Run `METALUI_CANVAS_DEMO=1 swift run MetalUIDemo` (a drag with `onCancelled` in the readout pad) or an app with a
reporting `DragGesture`. An agent cannot: these need a real lost release.*

- [ ] **GC1.** Start a drag, then take the release away (Mission Control, or open a native menu mid-drag), come back
  and press again on the same element: the interrupted drag reports one `onCancelled` (no `onEnded`) and the new
  press starts a drag. **Observed:**
- [ ] **GC2.** A real double-click on an element with `SpatialTapGesture(count: 2)` still fires the count-2 tap once
  and nothing spurious. **Observed:**

## RF. Resign on press — `.resignsFocusOnPress()` (item C24, user request 2026-10-02, not a plan task; record 98)

Run `METALUI_KEY_FOCUS_DEMO=1 swift run MetalUIDemo` (the root column carries the
modifier). **An agent cannot post these events.** Rulings `RF-A`…`RF-H`; pinned
headless by `ResignOnPressTests` and `ResignOnPressHarnessTests`.

- [ ] **RF-1.** With a real mouse, click the Name field, then the blank padding
  or a gap at the window's edge: the caret goes, typing goes nowhere. **Observed:**
- [ ] **RF-2.** Click Name, then the Depth field: focus moves in one step, the
  caret never flickers to nothing between. **Observed:**
- [ ] **RF-3.** Focus a field, right-click the padding: any context menu opens
  and the field stays focused (`MN-B`). Also check hovering the padding with
  nothing focused and pressing Tab opens nothing (no key routing by hover).
  **Observed:**

## MT. Material follow-ups — Reduce Transparency and the tint read (item C27, user request 2026-10-02, not a plan task; record §101; provisional letter, in the manner of `RT`, `KF` and `IF`)

*Run `METALUI_LOOKS_DEMO=1 swift run MetalUIDemo` (the material section). **An agent cannot toggle the
system's Reduce Transparency setting** (it changes the user's own settings; probe
`swiftui-material-followups.swift` `T0`/`T1` could not move SwiftUI either).* Rulings `MT-A`…`MT-K`;
pinned headless by `ReduceTransparencyTests`, `AppKitReduceTransparencyTests` and `HarnessReduceTransparencyTests`.

- [ ] **MT-1.** AppKit: with the looks demo open, turn System Settings ▸ Accessibility ▸ Display ▸ Reduce
  transparency on and off; every material goes to its flat grey and back with no relaunch and no
  flicker. Compare the grey against a SwiftUI app's `.regularMaterial` panel with the setting on
  (divergence 315, `MT-F`): note the difference per scheme. **Observed:**
- [ ] **MT-2.** AppKit: while the setting is on, Instruments (Metal System Trace) or Activity Monitor's
  GPU history shows no backdrop blur passes in the looks demo. **Observed:**
- [ ] **MT-3.** MetalCreator adoption (`Material.tint(in:)`): a glass panel at the solved tint
  `t = 1 − (1 − g)/(1 − m)` over a grey backdrop hides `g` of it (compare the panel's pixel with
  `1 − g` of the backdrop). **Observed:**

## IM. Input-method driver — what only a real input method shows (item C28, user request 2026-10-02, MetalCreator CT-d, not a plan task; record §102)

*An agent cannot: these need a real input method (Pinyin, Kana, IBus/fcitx, Windows IME) and VoiceOver.*

- [ ] **IM1.** VoiceOver on a `TextField` while a Pinyin/Kana candidate is marked: the field is not re-announced
  per keystroke; the input method announces its candidates (`IM-E`, divergence 325). **Observed:**
- [ ] **IM2.** A real input method on macOS (Pinyin, Kana) and on SDL (IBus/fcitx or Windows IME): the marked text is
  underlined at the caret, a commit writes once, Escape cancels and leaves a selected word intact (`IM-F`); the
  candidate window sits at the caret (the harness sends the platforms' own events, `IM-B`, but cannot see this).
  **Observed:**
- [ ] **IM3.** Cancel over a selection on AppKit's own `NSTextField`, for comparison with `IM-F`. **Observed:**

## GD. Developer guides — a reader's pass (item 10b, user request 2026-10-02, not a plan task; record §103)

*An agent cannot: it needs a person who does not already know the framework.*

- [ ] **GD1.** A person coming from SwiftUI reads each of the six guides in `docs/guides/` once with the demo
  running (`swift run MetalUIDemo`) and marks every step that surprises them or every sentence that did not match
  what they saw (`DG-A`, `DG-B`). The compile check proves the blocks build and the pinned claims hold in a
  headless window (`DG-C`); it cannot see whether a guide teaches. **Observed:**

## IV. Incremental invalidation — what only a real window shows (item C14, user request 2026-10-02, MetalCreator PERF-b, not a plan task; record §104)

*An agent cannot: these need a real window, two displays and VoiceOver.*

- [ ] **IV1.** Drag feel: `METALUI_INVALIDATION_DEMO=1 swift run MetalUIDemo` (and MetalCreator after adoption), bump
  cells and drag a node: no stale frame, no flicker, no node left behind; the left counter reads 1, the right 121.
  **Observed:**
- [ ] **IV2.** Type in a `TextField` placed in a memoized cell while other cells are bumped: caret, selection, focus and
  IME composition behave as in the unmemoized copy (`IV-B`, `IV-C`). **Observed:**
- [ ] **IV3.** Drag the window between a 1x and a 2x display and switch light/dark: text is crisp and correctly sized
  (the layout memo's key holds the scale factor and the text system; theme is paint-only, `IV-E`). **Observed:**
- [ ] **IV4.** VoiceOver reads a memoized subtree as the unmemoized one (the tree equality is pinned by test 2.9; the
  reading is a person's, `IX-AE`). **Observed:**

## SB. Retained subtrees — what only a real window shows (item C14b, user request 2026-10-02, not a plan task; record §109)

*An agent cannot: these need a real window, a pointer, a display of each scale, a screen reader and an eye.*

- [ ] **SB1.** A real-window drag of a retained node looks identical with replay on and off:
  `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`, drag Fillet around, tick and untick "Replay" mid-drag: no
  flicker, no node left behind, no stale wire; the strip reads 12 hits with replay on and 0 with it off
  (`SB-B`, `SB-F`). **Observed:**
- [ ] **SB2.** Hover and focus rings on a retained node appear and clear the frame the pointer or focus arrives and
  leaves (the key holds "pointer, press and focus are inside", `SB-F` item 4): move the pointer over a node's
  status badge and off again, Tab through the nodes. **Observed:**
- [ ] **SB3.** VoiceOver walks a retained subtree as a fresh one (the accessibility tree equality is pinned by the
  differential, test 1.2; the reading is a person's, `IX-AE`). **Observed:**
- [ ] **SB4.** A light/dark switch, a window resize and a move between a 1x and a 2x display repaint every retained
  subtree (the key holds the theme, the scale, the content size and the whole environment, `SB-F`, `SB-G`).
  **Observed:**
- [ ] **SB5.** An animation inside a retained region plays (an `.animation(value:)` flip, a keyframe shake): the
  occurrence is time-varying while it runs and never replays, and replays again once it settles (`SB-J`).
  **Observed:**
- [ ] **SB6.** A text field inside a retained region edits (lane 1 declares it ineligible, so it behaves as today;
  C14b-3 lifted this for an unfocused field, group RW): caret, selection and IME composition as in an unretained copy. **Observed:**

## RK. Retained build skip — what only a real window shows (item C14b-2, user request 2026-10-02, not a plan task; record §110)

*An agent cannot: these need a real window, a pointer, a screen reader and an eye. They extend group SB to prepaint replay, translated replay and the graft.*

- [ ] **RK1.** A real-window node drag looks identical with the switches off and on: `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`,
  drag a node with Prepaint and Skip build ticked and unticked mid-drag: no flicker, no stale wire, no node left behind; the readout
  shows prepaint hits, grafts and translated replays with the switches on and 0 with them off (`RK-C`, `RK-S`, `RK-X`). **Observed:**
- [ ] **RK2.** Hover, click and Tab on a replayed or grafted panel act as on a fresh one: the pointer entering a panel runs its
  prepaint that frame (hover ring, tooltip), a click reaches the right element at an overlap, Tab visits the same order (`RK-E`). **Observed:**
- [ ] **RK3.** VoiceOver walks a replayed or grafted panel as a fresh one (equality is pinned, the reading is a person's, `IX-AE`). **Observed:**
- [ ] **RK4.** A window resize, an opacity animation and a light/dark switch around the panels show no stale frame and no stutter beyond
  the single redo frame (`RK-C`, `RK-D`). **Observed:**
- [ ] **RK5.** A trackpad pan with the Prepaint switch on keeps text and shadows sharp and in place at 1x and 2x (translated replay refuses
  a fractional device translation, `RK-G`). **Observed:**

## EE. Environment epoch — an `@Environment` reader that is skipped (item C14-c, user request 2026-10-02, not a plan task; record 120; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: these need a real window, a display and an eye. The demo section is `METALUI_INVALIDATION_DEMO=1 swift run MetalUIDemo` (the "Environment" block under the two trees).*

- [ ] **EE1.** In the Environment block, "Write the key" moves the reader's getter count by 1 and its shown value; "Write an unrelated
  key" by 0; a Light/Dark switch in System Settings by 1 and the reader's text colour is right at once. Then, with the reader
  skipped and retained, drag the window across two displays of different scale and switch Light/Dark while the window is on each:
  no stale colour or size, no flicker (`EE-A`, `EE-B`, `EE-F`; the `displayScale` and `controlActiveState` readings are the
  unrehearsed ones). **Observed:**

## GA. SDL GPU for apps — compute and graphics on a real GPU (items S5 and S6, MetalCreator's SDL-port gaps 1 and 2, not a plan task; record §114)

*An agent cannot: the suites run on this Mac's Metal, on lavapipe in the Linux image and, in CI, on WARP; these need
a physical GPU, a desktop session and a console.*

- [ ] **GA1.** On a Linux or Windows desktop, a window with an instanced, depth-tested, 4x multisampled
  `GPUSurface` draw (`ctx.view`, `SDLGPUGraphicsPipelineDescription`) shows the three triangles with smooth
  edges, and resizing the window rebuilds the multisample and depth textures with no stale or stretched frame
  (the target is MetalUI's and changes size; the draw's own textures are the app's, `GA-H`). **Observed:**
- [ ] **GA2.** The append kernel (`SDLGPUComputeTests`) and the graphics tests (`SDLGPUGraphicsTests`) pass
  on **real GPU hardware** on Windows (D3D12) and on Linux (Vulkan), not only on WARP and lavapipe; run
  `swift test $(python3 scripts/fetch-accesskit.py --print-flags)` in `Backends/SDL` with `METALUI_REQUIRE_GPU=1`
  and read the one summary line (`GA-K`, `GA-N`). **Observed:**
- [ ] **GA3.** A built app that ships its compiled shaders in `MetalUIAppShaders` beside the executable finds
  them after the folder is moved, and a missing folder names every directory tried
  (`SDLGPUShaderLibrary.locate`, `docs/packaging.md` section 4a, like `X1`). **Observed:**
- [ ] **GA4.** In a debug build run in a real console, a draw that calls `SDLGPUDevice.waitForIdle()` and a draw
  that returns with a pass open each stop with a message that names the contract and reads clearly
  (`aWaitInsideADrawTrapsInDebug`, `anOpenPassAtTheEndOfADrawTrapsInDebug`; `GA-I`). **Observed:**

## IC. Image cursors and the headless SDL launch — what only a real pointer shows (items S4 and S8, user request 2026-10-02, MetalCreator SDL-port gap 8 and XP-G9, not a plan task; record §116)

*An agent cannot: a cursor is drawn by the window server and a test cannot see the pointer. The recorders (`mui_cursor_*`) pin what the bridge was asked for; these rows pin what the eye sees. The lock probe read LOCKED at design time.*

- [ ] **IC1.** SDL on Linux and on Windows: the hand and zoom recipe (`IC-H`, `docs/guides/input.md`) shows the supplied
  images, not SDL's move cursor, with the hot spot on the clicked point. `METALUI_CANVAS_DEMO=1`, the "ring" cell, on
  SDL's backend. Note the largest cursor size each platform draws (a bitmap above its limit leaves the current cursor,
  `IC-C` 3). **Observed:**
- [ ] **IC2.** macOS on a 2x display and on a 1x display: the ring cursor is crisp and the same point size on both (a 48 px
  bitmap at scale 2 is 24 pt, `IC-C`, `IC-D`). **Observed:**
- [ ] **IC3.** Every platform: the hot spot lands on the clicked pixel at the four corners of the image (hot spots
  `.zero`, top-trailing, bottom-leading, `.bottomTrailing`; a hot spot outside the unit square clamps, divergence 465).
  **Observed:**
- [ ] **IC4.** Windows (the UTM VM or CI) and Linux: an app shaped like `HeadlessLaunchCheck`
  (`SDLPlatform(options: .headless)`, a `.task`, a stop) exits 0 in CI with no display (`IC-J`, `IC-M`, `IC-Q`).
  **Observed:**

## HP. Hot paths — text and shadows look the same (item P1, user request 2026-10-02, not a plan task; record §111)

*An agent cannot: the fourteen offscreen images are 0 px against `fb9a7e42`; a real display, a scale change and an eye are a person's.*

- [ ] **HP1.** Text placement is unchanged in a real window at 1x and 2x: `swift run -c release MetalUIDemo`, compare
  against a `fb9a7e42` build side by side: paragraphs, mixed-script lines and the rich-text section sit on the same
  device pixels, no glyph a pixel off, no clipped or doubled glyph while the window resizes (the placement memo keys on
  origin, scale and font, `HP-A`, `HP-H`). **Observed:**
- [ ] **HP2.** Scrolling a list and panning a shadowed container keep text and shadows sharp and stationary relative to
  their rows: fractional scroll offsets (trackpad) never leave a stale glyph position (`HP-A` key x/y; the rich-text
  y component is pinned, record §111 s7). **Observed:**
- [ ] **HP3.** A border width, an opacity and a frame still animate smoothly and settle exactly (hover a bordered
  control, toggle a transition): the early-outs return only when nothing is in flight (`HP-C`). **Observed:**

## IB. Image decoding and orientation — what only an eye shows (item S2, user request 2026-10-02, not a plan task; record 113)

*An agent cannot: these need a real window and a person who knows which way up a photograph is.*

- [ ] **IB1.** Draw a JPEG tagged EXIF 6 two ways beside each other, in a real window: decoded through
  `DecodedImage` + `applyingOrientation()` + `ImageBitmap(_:)`, and `Image(_:scale:orientation: .right, label:)`
  over the untagged `ImageBitmap(data:)`. Both read upright and identical (`IB-F`). **Observed:**
- [ ] **IB2.** In a SwiftUI window, `Image(nsImage:)` of the same file reads upright, while MetalUI's plain
  `ImageBitmap(data:)` of it reads sideways (divergence 435, `IB-G`; the sizes are probed headless, the look is
  the eye's). **Observed:**

## CW. Window chrome on SDL — borderless looks, drag, resize and the drawn buttons (item S1, user request 2026-10-02, MetalCreator SDL-port gap 3, not a plan task; record §112; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: these need a real Windows 11 and Linux (X11 and Wayland) desktop, a pointer and an eye.* Run
`METALUI_CHROME_DEMO=1` on `MetalUISDLDemo` (and `MetalUIDemo` on macOS for the AppKit contrast).

- [ ] **CW1.** The demo's looks on Windows 11 and Linux X11 and Wayland: a borderless window, the 32-point bar
  filling its top, the three drawn buttons at the top right (flat 46 x 32 rectangles), the bar's title, button, field
  and handle left of them, nothing under the cluster. **Observed:**
- [ ] **CW2.** Dragging from the empty bar and from the handle at its end moves the window; the cursor, the window's
  position and the focus behave as a titled window's. **Observed:**
- [ ] **CW3.** The bar's button, search field and tap target still work (they are carved out of the drag region,
  `CW-E`): click the button (the count rises), type in the field, tap the target; a click on a control never starts a
  move. **Observed:**
- [ ] **CW4.** Resizing from each edge and corner (6-point border, 12-point corner squares, `CW-G`); the border over a
  scrollbar at the right edge swallows its first 6 points; a fixed-size window (equal min and max) resizes on no
  such axis. **Observed:**
- [ ] **CW5.** Divergence 425: inside the empty band the pointer style, hover and tooltips are lost on SDL (the
  platform takes the events); outside it they work. Record which platforms swallow what. **Observed:**
- [ ] **CW6.** Double-click on the empty band zooms and restores on Windows (`HTCAPTION`, `CW-I`) and does not on
  X11 or Wayland (the region consumes both presses; divergence 427 is taken only if this fails). **Observed:**
- [ ] **CW7.** macOS through SDL: the drawn buttons are three 12-point circles at the **left**, 70 points wide, in
  AppKit's order; `titleBarInsets.left` is 70. **Observed:**
- [ ] **CW8.** Entering and leaving fullscreen: the bar and buttons go, the window is bordered or not as before, the
  last requested style comes back (`CW-B`). **Observed:**
- [ ] **CW9.** A borderless Windows window's shadow and corners (DWM draws them for a borderless window or does
  not; platform, `CW-A`). **Observed:**
- [ ] **CW10.** Close goes through the close veto: with an `onCloseRequest` that answers `.cancel` or `.later` the
  drawn Close button keeps the window and the app's alert shows; minimise and zoom/restore act, and Zoom reads
  "Restore" while maximised. **Observed:**
## CB. Clipboard beyond text — pasting between applications (item S3, user request 2026-10-02, MetalCreator SDL-port gap 7, not a plan task; record 115)

*An agent cannot: these need a real clipboard shared with another application, an unlocked screen and a person.*

- [ ] **CB1.** SwiftUI's own behaviour, the arm the locked screen skipped (`R` of
  `docs/probes/swiftui-clipboard-types.swift`, unlocked screen: no `CGSSessionScreenIsLocked` line): does `copy:` reach a
  `copyable` without focus? does a `Transferable` with a proxy representation also write a string? does a
  `pasteDestination` whose `validator` rejects everything disable Edit ▸ Paste? does `copyable([a, b])` write two
  pasteboard items? **Observed:** (rewrites `CB-B`, `CB-C`, `CB-G` and divergences 455, 456 if SwiftUI disagrees).
- [ ] **CB2.** `METALUI_CLIPBOARD_DEMO=1 swift run MetalUIDemo` (then `MetalUISDLDemo` on Linux X11, Wayland and
  Windows): Tab to the source, copy, paste into TextEdit (the text fallback `graph with 3 nodes` arrives); copy text in
  another application, Tab to the destination and paste (the text import reads its length); copy in the demo and paste
  in a second demo process (the custom type arrives as `3 nodes`). **Observed:**
- [ ] **CB3.** The Edit menu's Cut, Copy and Paste enable and disable with the focus: native menu on macOS, the drawn
  bar on SDL (`METALUI_CLIPBOARD_DEMO=1`, Tab between source, destination and the text field; Cut/Copy on the source,
  Paste on the destination, all three on the field). **Observed:**
- [ ] **CB4.** A 100 MB payload (a `Data` filled in the demo's console) copies and pastes on each platform with no hang
  and the memory returning afterwards (`CB-I`: no cap; X11's incremental transfer is SDL's). **Observed:**
- [ ] **CB5.** Another application taking the clipboard while the demo owns it: the demo's next paste reads the other
  application's data, never stale bytes of its own (`CB-H`; SDL calls the cleanup when it loses the clipboard).
  **Observed:**

## SI. Single-instance launch on SDL — a second launch from a file manager (item S7, user request 2026-10-02, found answering MetalCreator SDL-port gap 5, not a plan task; record 122)

*An agent cannot: these need a real file manager, a second process started by it, and a person. Windows is compiled by CI and reviewed, never run by this item.*

- [ ] **SI1.** Linux, X11 and Wayland: install a `.desktop` file with `Exec=/path/MetalUISDLDemo %F` (a build whose
  `main.swift` calls `launchingSingleInstance`), open one document from the file manager, then a second: the first window
  shows the second document (`METALUI_APP_SHELL_DEMO=1`'s `.onOpenURL` section), no second window appears, and the window
  raises or its taskbar entry flashes. **Observed:**
- [ ] **SI2.** `kill -9` the primary, relaunch: a fresh primary starts (no "stale" refusal); launch again: it forwards.
  **Observed:**
- [ ] **SI3.** Windows 11 (x64 and ARM64), Explorer and a file association: the same as SI1; End Task on the primary, relaunch:
  a fresh primary (the semaphore is gone with its last handle, `SN-P`); also two sessions of one user (fast user switching):
  each has its own primary (`SN-D`). **Observed:**
- [ ] **SI4.** Wayland activation: does `SDL_RaiseWindow` bring the primary forward without a token, or only flash it? Record
  the compositor (`SN-H`, `SN-L`). **Observed:**
- [ ] **SI5.** Two users on one machine (`su` or fast user switching): neither sees the other's primary; a launch by the second
  user while the first runs is its own primary. **Observed:**
- [ ] **SI6.** A primary left running eight hours (screen lock, suspend, resume), then a forward: it arrives. **Observed:**

## RW. Retained read-only state — panels that replay (item C14b-3, user request 2026-10-02, not a plan task; record 121)

*An agent cannot: these need a real window and a person. Scene equality with a fresh window is pinned by the suite and by `METALUI_VERIFY_RETAINED=1`; what is owed is how it looks and feels. Switch the demo's retained subtrees off with `METALUI_RETAINED_DEMO=1`'s switch to compare.*

- [ ] **RW1.** `METALUI_RETAINED_DEMO=1`, the panel strip: scroll its `List` with a trackpad (momentum, then the indicator's fade) and
  with a wheel, retention on and off: the same pixels, no stale offset, no frozen indicator; the strip's counts read a miss while it moves
  and a hit again once it has settled (`RW-H`, `RW-I`). **Observed:**
- [ ] **RW2.** Orbit or drag a node so the panel strip replays for many frames, then click its `TextField`, type, select with the mouse and
  compose with an input method (Japanese or the emoji picker): caret, selection and marked text as in an unretained copy; click away and the
  strip returns to a hit (`RW-J`). **Observed:**
- [ ] **RW3.** Resize the window while the strip replays, then open its `Picker`: the popup opens at the declarer, not at its old
  position (`RW-K`, the anchor replay). **Observed:**
- [ ] **RW4.** Leave a retained field focused-then-blurred and the window idle for several minutes (display sleep included): its caret,
  selection and scroll offset are intact (`RW-E`, the liveness channels). **Observed:**
- [ ] **RW5.** The owner runs MetalCreator's orbit with the graph panel and inspector open: the orbit frame's window CPU against the
  `e85cb07a` reading (20.56 ms), and no panel shows stale content after a node-library scroll, a number entry or a slider drag
  (no agent touches MetalCreator). **Observed:**

## RO. Raster overscan — shadows, blurs and gradients across a clip edge (item P4, user request 2026-10-02, not a plan task; record 124)

*An agent cannot: these need a real window and a person. Pixel equality with 4d91f27f is pinned (fourteen images, 0 px; per-kind byte equality, record 124 §5); what is owed is how a panned region looks on a real display.*

- [ ] **RO1.** Scroll or drag a list whose rows carry a shadow, a blur and a radial or diagonal gradient across the edge of a `.clipped()`
  panel, on AppKit and on SDL, at 1x and 2x: no seam, flicker, popped-in glow or clipped halo as a card crosses the edge, slowly and fast
  (`OS-A`, `OS-F`). **Observed:**
- [ ] **RO2.** Drag one shadowed card's width and a card half outside the panel: the glow is whole when it re-enters, and a card larger than the
  `2^20`-pixel limit still draws (the old keys, `OS-D`). **Observed:**
- [ ] **RO3.** Rotate or scale a shadowed card under a local mask (mode 3): the shadow looks as before (`OS-E`). **Observed:**

## FS. Finer retention scopes — a List row that replays, a shifted or scrolled row that replays translated (item C14-d, user request 2026-10-02, not a plan task; record 126; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: these need a real window and a person (and, for FS1, the owner's MetalCreator). Scene, hitbox and accessibility equality with a fresh window is pinned by the suite and by `METALUI_VERIFY_RETAINED=1`; what is owed is how it looks and feels. `METALUI_RETAINED_TRANSLATION=0` turns the translation off for a comparison.*

- [ ] **FS1.** The owner runs MetalCreator's orbit and pan with the graph panel open: the window CPU per frame against the 25.8 ms reading, and no panel stale after a node drag, a
  library scroll or a number entry (no agent touches MetalCreator; `FS-K` 7). **Observed:**
- [ ] **FS2.** A long `List` of `.equatable()` rows (both `rowHeight:` and the variable-height spelling) scrolled with a wheel and a trackpad, then a row edited while the list
  scrolls: the same pixels as with retention off, no stale or duplicated row, hover and click reach the row under the pointer; VoiceOver reads the rows in order (`FS-N`). **Observed:**
- [ ] **FS3.** `METALUI_RETAINED_DEMO=1`, the shift-and-scroll strip, at scale 1, 2 and a non-dyadic scale: grow and shrink the header, scroll fast with a wheel, change a card's data
  mid-scroll: no tearing, no stale row, no cut-off card at the scroller's edge; the counters read `translated` on 1 and 2 and the refusal name on the non-dyadic one (`FS-M`, `FS-P`). **Observed:**
- [ ] **FS4.** VoiceOver on the shifted strip reads the same rows as with the translation off (accessibility refuses, so this is the unretained path, `FS-F`). **Observed:**

## RG. Retained geometry observers and per-shelf atlas uploads — a reader that follows a real window, text on distant shelves (item C14-f, user request 2026-10-02, not a plan task; record 128; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: these need a real window and a person. Delivered values equal a fresh window's over a script (resize, scroll, shift) and every atlas texel equals the atlas (Metal readback), both pinned; what is owed is how it looks on a real display and on SDL.*

- [ ] **RG1.** `METALUI_RETAINED_DEMO=1`, the geometry card: drag a node, resize the window and scroll with a wheel and a trackpad; the card's reported size follows the real window and the panel it sits in (a size that lags a frame, or
  stays at an old value after the resize ends, is the bug), and nothing is stale after a resize mid-drag (`RG-A`, `RG-C`, `RG-J`). **Observed:**
- [ ] **RG2.** On AppKit (Metal) and on SDL (Linux and Windows): change a text field's font size so first-use glyphs land on shelves far apart in one frame (a heading and a footnote, a CJK run): every glyph is drawn, none
  blank, at scale 1 and 2 (`RG-H`, `RG-O`). **Observed:**
- [ ] **RG3.** SDL on Windows D3D12 (CI cannot see a pixel): the same first-use text draws whole after the packed per-rect atlas copy (`RG-O`; CI compiles it only). **Observed:**
## AT. Accessibility under an effect-translated replay — a canvas pan with the graft on (item C14-g, user request 2026-10-02, not a plan task; record 129; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot run VoiceOver (`IX-AE`) or MetalCreator. Tree equality with a fresh window is pinned by the suite and by `METALUI_VERIFY_RETAINED=1`; what is owed is how it reads and feels.*

- [ ] **AT1.** VoiceOver on a canvas of `.equatable()` nodes under `.scaleEffect` + `.offset` (MetalCreator's graph, or `METALUI_RETAINED_DEMO=1`): pan and zoom the canvas, the VoiceOver focus rectangle follows the
  focused node and socket, stays on it after the pan settles, and reads the same labels as with retention off (`AT-A`). The owner also reads MetalCreator's warm graph pan counters: grafts above 0, redos 0, element
  requests far below 1409 (no agent touches MetalCreator). **Observed:**

## RL. Retained lifecycle and translation carries — callbacks that fire once through a graft, a reader that follows a pan (item C14-h, user request 2026-10-02, not a plan task; record 131; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot run VoiceOver (`IX-AE`), hold a real modifier key or run MetalCreator. Delivery sequences equal a retention-off window's over scripts and published trees equal a fresh window's, both pinned; what is owed is how it reads and feels on a real window. No demo strip was built: use an app with the same shape (MetalCreator's ViewportView) or any `.equatable()` panel with these scopes.*

- [ ] **RL1.** An `.equatable()` viewport with `onModifierKeysChanged` and `onAppear`/`onChange`/`.task(id:)` scopes: hold and release modifiers (Shift, Option, Command) while panning and zooming; each change is reported once, none doubled or missed, nothing re-fires `onAppear` or `initial` while the viewport pans, and the owner reads `retainedIneligibleReasons` 0 for `modifierKeys` and `lifecycle` with grafts above 0 (`RL-A`, `RL-B`). **Observed:**
- [ ] **RL2.** VoiceOver on a scrolling list of `.equatable()` rows carrying an `.onGeometryChange(.global)` observer and accessibility records: scroll and resize; the VoiceOver focus rectangle follows the focused row, the observer's value matches the real frame, and the window never flickers into a rebuild (`RL-E`, `RL-H`). **Observed:**
- [ ] **RL3.** A canvas under `.scaleEffect` + `.offset` with `.equatable()` nodes that register hitboxes inside their own effect: pan at zoom 2 and 0.8; hover and click land on the node under the pointer, and VoiceOver reads the same labels as with retention off (`RL-I`). **Observed:**

## AP. SDL application id - the desktop entry's icon and grouping (item XP-G13, user request 2026-10-21, not a plan task; record 132; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it needs a Linux desktop session. The hint is set before `SDL_Init` and an explicit option beats the single-instance id (`SDLAppIDTests`); what is owed is what the shell does with it.*

- [ ] **AP1.** On GNOME Wayland and on an X11 session, install a `.desktop` entry named after the id (`com.example.MyApp.desktop`, `Icon=` a theme name) and launch an SDL app that passes the id as `Options.applicationID` (or only to `launchingSingleInstance(id:)`): the window shows the entry's icon in the dash and
  groups under the entry, not under the executable name; on X11 `xprop WM_CLASS` names the id. With no id set the old behaviour (generic icon) holds; with `SDL_APP_ID=other.id` exported the override wins (`AP-A`, `AP-B`, `AP-C`). **Observed:**

## LZ. Lazy containers - fast scrolling, an adaptive grid's first frame, VoiceOver and resizing (item L1, user request 2026-10-02, round 2 2026-10-21, not a plan task; record 134; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot run VoiceOver (`IX-AE`), see a flash or hold a wheel. The window, the index, the anchor, the column counts and the one-frame correction are pinned by the suite (`LazyStack*Tests`, `LazyGrid*Tests`, `GridTrackSolverTests`); what is owed is how it looks and reads. Run `METALUI_LAZY_DEMO=1 swift run MetalUIDemo` (and `-c release`).*

- [ ] **LZ1.** Fast-scroll the variable-height `LazyVStack` (trackpad flick and scroll-bar drag) up and down through 10 000 rows: no row jumps, flashes or leaves a blank band, the row on top stays put while rows above it are measured, and the "on screen now" count stays near the viewport plus two rows each side (`LZ-E`, `LZ-G`, divergence 637). **Observed:**
- [ ] **LZ2.** The adaptive `LazyVGrid`'s first frame in a real window: is it visibly a single column for a frame before the real count (`LZ-L`, divergence 638)? Open the demo several times and note whether the flash is seen at all. **Observed:**
- [ ] **LZ3.** VoiceOver on the demo: it reads the realised rows and cells, reaches an off-screen row only after scrolling to it (no list position is announced, `LZ-J`), and a focused cell that scrolls out of the window does not leave a stale focus rectangle. **Observed:**
- [ ] **LZ4.** Resize the window wider and narrower while the adaptive grid is on screen: it re-flows to the new column count with no blank band and no cell drawn at a stale width longer than one frame (`LZ-L`). **Observed:**
- [ ] **LZ5.** The same demo on SDL (Linux, Windows) once `MetalUISDLDemo` carries it (carried: only `MetalUIDemo` wires it), and a wheel over a lazy stack inside a `ScrollView` on both. **Observed:**

## EX. Sample app - Jotter on macOS and SDL (item E1, user request 2026-10-21, not a plan task; record 136; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: the screen was locked and no real window was launched. The app's flows are pinned headlessly (`Examples/Jotter/Tests`); what is owed is how it looks and feels through real panels and menus.*

- [ ] **EX1.** `cd Examples/Jotter && swift run Jotter` on macOS: sidebar rows (title, date, snippet), selection, the detail's title field and editor, the stats strip, the toolbar's six items and the native File/Edit menus look right. **Observed:**
- [ ] **EX2.** The same under SDL on Linux (`swift run --traits SDL,AccessKit Jotter` or the image): the drawn menu bar and toolbar strip, the `Search notes` field, the drag preview. **Observed:**
- [ ] **EX3.** Export then Open a real JSON file through the native panels; the notes come back in order, a garbage file raises the alert and changes nothing. **Observed:**
- [ ] **EX4.** The Theme button and the system Dark mode on both platforms: sidebar fill and text follow. **Observed:**
- [ ] **EX5.** Drag a row to reorder, right-click Duplicate, Delete with the confirmation sheet (Cancel keeps it). **Observed:**
- [ ] **EX6.** New, Duplicate and Delete shortcuts with the title field focused and not (Delete's command-backspace belongs to a focused field, `EX-Q`). **Observed:**

## GB. SDL GPU gaps - anisotropy looks, Windows D3D12, the main-actor readback stall (item S11, user request 2026-10-21, not a plan task; record 137; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it needs three desktops and a real 3D viewport app. The sampler fields, viewport, scissor, write mask, `r32Float`, the blocking readback and the failure reasons are pinned headless on Metal and lavapipe; what is owed is how it looks and behaves elsewhere.*

- [ ] **GB1.** A textured ground plane at a grazing angle with `maxAnisotropy` 1 against 16 on Metal (macOS), Vulkan (Linux) and D3D12 (Windows): distant texels are visibly sharper at 16 (`GB-E`). **Observed:**
- [ ] **GB2.** On a real D3D12 device (CI compiles Windows only; the UTM VM runs the SDL GPU tests when reachable): the viewport and scissor sub-rect, a depth-only prepass (`writesColor: false`), `r32Float` sampling and `downloadSynchronously` give the same pixels and floats as Metal and lavapipe (`GB-B`...`GB-F`). **Observed:**
- [ ] **GB3.** `downloadSynchronously` for a picking readback in a real 3D viewport app: one frame hitch when it is called, no deadlock, and the pipeline-failure text (`compileGraphicsPipeline`) reads usefully for a deliberately broken shader (`GB-F`, `GB-G`). **Observed:**

## RZ. Retained zoom - a zoom that grafts, a focus reader that stays quiet (item C14-i, user request 2026-10-21, not a plan task; record 133; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot run VoiceOver (`IX-AE`), drive a real pointer or run MetalCreator. A zoom's scene, published tree, hitboxes and raster work equal a fresh frame's, pinned; what is owed is how it reads and feels on a real window. The demo's zoom strip (`METALUI_RETAINED_DEMO=1`) is the quickest subject.*

- [ ] **RZ1.** `METALUI_RETAINED_DEMO=1`: step the zoom strip's scale in and out and rotate it; nothing flickers, text and the stroked path stay sharp at each scale (no stale raster at an old scale), hover and click land on the card drawn under the pointer while the zoom moves content beneath a stationary pointer, and the strip's counters show grafts above 0 and redos 0 (`RZ-A`, `RZ-C`, `RZ-D`, `RZ-O`). **Observed:**
- [ ] **RZ2.** An app canvas under `.scaleEffect` + `.offset` with `.equatable()` nodes and VoiceOver on (MetalCreator's zoom-50-warm): zoom with the wheel; VoiceOver's focus rectangle follows the focused node at every scale and the warm frame's element requests are O(changed) (`RZ-E`). **Observed:**
- [ ] **RZ3.** A form of `.equatable()` components each declaring `@FocusState`: Tab through and click between fields; the focus ring and caret follow focus with no lag, a field focused from code takes focus on the next frame, and unfocused components are skipped (`contentRefusals` 0; `RZ-T`). **Observed:**

## GS. `@GestureState` and `phaseAnimator` (item G1, user request 2026-10-02, round 2 2026-10-21, not a plan task; record 135; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: the screen was locked for the whole item, so no real window was driven and the probe arms `G7`, `G7e` and `P5` were not re-taken. The reset paths, the stepping schedule and the work counts are pinned headlessly (`GestureStateTests`, `PhaseAnimatorTests`, `PhaseAnimatorRetainedTests`); what is owed is how it looks, how SwiftUI behaves under Reduce Motion, and the re-take. Demos: `METALUI_CANVAS_DEMO=1`'s drag chip and hold chip (the input follow-ups pad under the canvas demo) and `METALUI_LOOKS_DEMO=1`'s keyframes row (pulse and triggered bar).*

- [ ] **GS1.** Drag the chip and release: it eases home over 0.25 s (`resetTransaction`) on macOS and on SDL, with no jump at the release and none while it follows the pointer. **Observed:**
- [ ] **GS2.** Hold the press chip past 0.5 s and release early: the pressed look turns off at the maturity and again at the release, never sticks. **Observed:**
- [ ] **GS3.** Flip System Settings, Accessibility, Display, Reduce Motion, then re-run `docs/probes/swiftui-gesture-state.swift` `P1`/`P2` and watch the looks demo's pulse: record whether SwiftUI stops or snaps the cycle and what MetalUI does (it keeps stepping and animating, `GS-K`). If SwiftUI differs, the counter-ruling is one `snaps` read in `PhaseRecord` resolution. **Observed:**
- [ ] **GS4.** Start a drag on the chip and Cmd-Tab away, then return: the chip is home (key loss cancels the arena and resets the state, `GC-`, `GS-C`). **Observed:**
- [ ] **GS5.** Leave the looks demo's pulse running for a minute: one core's share while it runs, near 0 % once the window is occluded or the pulse is removed (the display link only while a step is pending, `GS-I`). **Observed:**
- [ ] **GS6.** The same drag chip and pulse on Linux with a real pointer (an SDL window). **Observed:**
- [ ] **GS7.** With an unlocked screen, re-take `swiftui-gesture-state.swift` arms `G7`, `G7e` (the claim behind divergence 645) and `P5` (the nil-animation step) byte for byte against the header's lines (`GS-O`); a line that differs re-rules 645 or the P5 pin. **Observed:**

## BS. Build-time app shaders - a real shadercross through the tool and plugin (item S12, user request 2026-10-02, not a plan task; record 138; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it needs a Windows machine and a Linux x86_64 one. The tool's plan, lookup, marker and the plugin (with a stub shadercross) are pinned headless, and the runs against a real shadercross at the pin on macOS arm64 and Linux aarch64 were byte-identical to the checked-in blobs (record 138, `BS-L`); what is owed is the other platforms.*

- [ ] **BS1.** On a machine with SDL_shadercross built at `1ff05bec573988a98ef9e0260b4da44f512b8367` (Linux x86_64 and Windows x64; macOS arm64 was run by the agent, `BS-L`; recipe in `docs/packaging.md` section 4a): `METALUI_SHADERCROSS=<path> swift package --allow-writing-to-package-directory compile-shaders --source Backends/SDL/Tests/AppShaders --out /tmp/appshaders` (a copy of the sources inside a package) writes blobs whose reflection JSON equals the checked-in one's and that open in the SDL GPU tests (`METALUI_SHADERCROSS=<path> swift test --filter anEnvGatedRunCompilesAFixture`). **Observed:**
- [ ] **BS2.** Linux aarch64 *app*: a Vulkan app on a real aarch64 Linux GPU opens the library built there, and one built without `dxil` (`--formats spv,msl,json`). The compile itself was run by the agent in the image (`BS-L`). **Observed:**
- [ ] **BS3.** A package depending on MetalUI **by URL** (not path) sees `swift package compile-shaders`; if not, `swift run --package-path .build/checkouts/MetalUI MetalUICompileShaders ...` works (`BS-B`). **Observed:**
- [ ] **BS4.** Windows: `shadercross.exe` is found on `PATH` and by `METALUI_SHADERCROSS`, its DLLs beside it load, and the tool's output matches macOS's reflection JSON. **Observed:**

## WR. Windows release build - MetalCreator's xp-2 zip (item XP-G21, 2026-10-21, not a plan task; record 139; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it needs a Windows machine with Swift 6.4.0+Asserts. The asserts snapshot on macOS is the stand-in (`WR-A`).*

- [ ] **WR1.** On Windows with the CI compiler, `swift build -c release` of the root package's `MetalUI` product and of MetalCreator's `MetalCreatorApp` finishes with no "SIL verification failed", and the xp-2 release zip's app paints a shadowed, blurred and rotated legacy element like the debug build. **Observed:**
- [ ] **WR2.** The `root-windows` job's "Release build of MetalUI" step: record its wall time from the first CI run (the lane's expectation was under 10 minutes, unmeasured). **Observed:**

## CP. Clipboard extras - PasteButton, several items, lazy export (item 6, user request 2026-10-21, not a plan task; record 142; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: these need a hosting window that becomes key (probe arm R never did from a command-line process), a person at an unlocked Mac, a second application and a clipboard manager. The behaviour is pinned headless (`PasteButtonTests`, `ClipboardItemsTests`) and on private pasteboards and SDL's C recorders; the SwiftUI side of three rulings is unprobed.*

- [ ] **CP1.** Re-take arm R of `docs/probes/swiftui-clipboard-extras.swift` where its window becomes key (unlocked screen, no `CGSSessionScreenIsLocked` line): how many pasteboard items does `copyable([a, b])` write, what does a paste destination receive from two items, does SwiftUI's `PasteButton` disable on a pasteboard holding nothing it imports, and when does an exporter run on a copy. **Observed:** (retires or rewrites divergences 456, 715's AppKit side, 716 and `CP-B`'s enablement if SwiftUI disagrees).
- [ ] **CP2.** `METALUI_CLIPBOARD_DEMO=1 swift run MetalUIDemo` beside a SwiftUI `PasteButton` on macOS, light and dark: the "Paste" look, focus ring, pressed and disabled states (divergence 717); the button is dimmed until a graph is on the clipboard and pastes both copied graphs. **Observed:**
- [ ] **CP3.** Copy the demo's two graphs and paste into a second MetalUI process (then `MetalUISDLDemo` on Linux X11, Wayland and Windows): both arrive (the pack, `CP-C`); paste into TextEdit or another application and only the first item's fallback text arrives on SDL (divergence 715). **Observed:**
- [ ] **CP4.** An external clipboard manager rewrites the clipboard while the demo window is key and idle: the button's enablement follows at the next press, becoming key or key-down (`CP-G`'s named residue); and the lazy export's closure runs at paste time on AppKit, at copy on SDL (divergence 716). **Observed:**

## DT. `drawText` in a GPU surface (round 2 item 5, 2026-10-21, not a plan task; record 141; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it needs a real window, and the screen was not unlocked for a capture. The Metal text pass reads back pixel-equal to the same `Text` at 1x and 2x (`DrawTextMetalTests`), and the SDL pass reads back equal to the same glyph records drawn directly by the scene (`SDLDrawTextTests`, macOS and the Linux image on lavapipe); what is owed is how it looks and how it behaves live. No demo section was added (the existing surface demo is not one of the fourteen images and gained nothing).*

- [ ] **DT1.** macOS: a `drawText` label beside the same `Text` overlay, at 1x and 2x: the same weight, the position within a device pixel, no halo at the glyph edges. **Observed:**
- [ ] **DT2.** Linux and Windows (SDL): the same as DT1 on a real window (Windows is compiled by CI only, check SI3). **Observed:**
- [ ] **DT3.** A label over a `.continuous` surface: no flicker and no one-frame lag against the app's own drawing while the app animates under it. **Observed:**
- [ ] **DT4.** Resize the window while a label is up: the label stays crisp (the target is recreated and redrawn at the new size) and never shows a stale or stretched frame. **Observed:**

## BG. Presentation extras - `presentationBackground`, `windowBackgroundDragBehavior`, `PointerStyle.shape` (round 2 item 7, user request 2026-10-21, not a plan task; record 144; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: the screen was locked at the design session and no window was captured. Everything here is pinned as values, work and recorded platform calls (`PresentationBackgroundTests`, `WindowBackgroundDragTests`, `ShapeCursorTests`, `AppKitWindowDragTests`, `SDLChromeTests`); the SwiftUI D arms of `swiftui-presentation-extras.swift` rest on a locked-screen recording.*

- [ ] **BG1.** `METALUI_MENUS_DEMO=1 swift run MetalUIDemo`, open the popover with the gradient fill, light and dark: the gradient fills the whole rounded panel, the 1-pt border is kept, the shadow shows under it; then a `Material` panel (divergence-free ruling `BG-P`: a real backdrop blur, **no drop shadow**) and a translucent colour. Compare with a SwiftUI `.popover` + `presentationBackground` side by side (SwiftUI's panel is glass). **Observed:**
- [ ] **BG2.** `METALUI_CHROME_DEMO=1`, Linux X11, Wayland and Windows (SDL): switch `Background drag` on; a press-drag on the empty content moves the window, a press on a button, text field or scroller does not, hover and pointer-style regions inside the background lose their pointer events (divergence 737), and the window does not move while maximised. **Observed:**
- [ ] **BG3.** The same demo on macOS: `Background drag` on moves the window by the empty background through `performDrag` (not `isMovableByWindowBackground`), a double click on the background does nothing, a press on a control does not drag, the title band keeps its own drag and double-click zoom. **Observed:**
- [ ] **BG4.** In a real SwiftUI `App` with `.windowBackgroundDragBehavior(.enabled)`: does a press-drag that starts on a `Button` or a `TextField` move the window (`BG-G`'s unprobed ruling: MetalUI never drags from an opaque target)? And what does `.disabled` do to the hidden title bar's band (`BG-J`)? **Observed:**
- [ ] **BG5.** The chrome demo's star-shaped pointer region (`PointerStyle.shape`, `eoFill`) at 1x and 2x on macOS, Linux and Windows: the black star with a 1-pt white outline is crisp (rasterized at the display scale), the hole of the even-odd star is transparent, the hot spot is its centre, and moving the window to a display of another scale re-sends one cursor at the new scale. SwiftUI has no such cursor on macOS (divergence 735): the look is ours. **Observed:**

## RC. Run-time HLSL compute shaders on SDL_GPU - Windows, packaging, a real desktop GPU (item XP-G25, user request 2026-10-02, not a plan task; record 151; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it has no Windows machine, no signed macOS `.app` run from Finder and no desktop GPU of MetalCreator's class. macOS Metal (MSL) and Linux lavapipe (SPIR-V) were compiled and dispatched by the agent (`SDLGPURuntimeCompile*`), and the pin's DXIL was compared byte for byte with the build tool's blobs.*

- [ ] **RC1.** A Windows x64 machine with `SDL3_shadercross.dll`, `dxcompiler.dll`, `dxil.dll` and the spirv-cross DLL beside the `.exe`: `SDLGPUShaderCompiler.selfTest(for:)` compiles to DXIL and dispatches on D3D12. Then remove `dxil.dll` and re-run: is it needed to sign the DXIL (`RC-U` measured it unneeded on macOS and Linux only)? **Observed:**
- [ ] **RC2.** The Linux tarball (`lib/` beside `bin/`) and an AppImage (`usr/lib`) find the library from their own layout with no `LD_LIBRARY_PATH` (`RC-C`, `RC-N`). **Observed:**
- [ ] **RC3.** An app's `--self-test` on a machine **without** the library prints the named `compilerUnavailable` error listing the paths tried and exits non-zero. **Observed:**
- [ ] **RC4.** A desktop GPU (NVIDIA, AMD, Intel; Vulkan and D3D12): the compile time of MetalCreator's real ~1000-line generated kernel, off the main actor (`RC-V` measured generated kernels only: about 0.4-0.6 s). **Observed:**
- [ ] **RC5.** A macOS `.app` with the four libraries in `Contents/Frameworks` launches from Finder and compiles: hardened runtime or library validation may refuse an unsigned dylib. **Observed:**

## SX. shadercross in `<exe>/lib`, Microsoft's DXC (items XP-G26 and the packaging note, user request 2026-10-02, not a plan task; record 152; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: it has no Windows machine and no packaged tarball from MetalCreator. The lookup order and the preload directory are pinned portably (`RuntimeLibraryLocatorTests`, `SDLGPURuntimeCompilerTests` 13b).*

- [ ] **SX1.** On Windows x64, shadercross at the pin built against Microsoft's DXC release (v1.9.2602: its `dxcompiler.dll` and `dxil.dll`): `SDLGPUShaderCompiler.selfTest(for:)` compiles to DXIL and dispatches on D3D12 (`SX-D`: compatibility is **unmeasured**). **Observed:**
- [ ] **SX2.** A Linux tarball whose libraries sit in `lib/` beside the executable (RUNPATH `$ORIGIN/lib`, no `bin/`/`../lib` layout) finds them as `<exe>/lib` with no `LD_LIBRARY_PATH` and `selfTest` passes; a missing library names `<exe>/lib/...` among the paths tried (`SX-B`, `SX-C`). **Observed:**

## LG. Liquid Glass - `glassEffect`, the container, the glass buttons (item LG, user request 2026-10-23, not a plan task; record 153; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: `ImageRenderer` draws no glass (probe `R`), so no test compares with SwiftUI; the real-window numbers of `swiftui-liquid-glass.swift` `W` are captures of an inactive borderless window. Everything here is pinned as MetalUI's own arithmetic against `GlassReference` (`GlassRenderTests`, `GlassReferenceTests`, `SDLGlassTests`), scene records and counted work (`GlassTests`, `GlassHarnessTests`). Run `METALUI_GLASS_DEMO=1 swift run MetalUIDemo`.*

- [ ] **LG1.** The demo's standalone glasses (regular, clear, tinted) over its striped, coloured backdrop, light and dark, beside a SwiftUI app on macOS 26 with the same shapes over the same photo and text: compare the edge lens depth, the specular rim (upper left), the blur radius (sigma 52 pt is the Material constant, unseparated by the probe) and the 1-pixel outer hairline `LG-Q` carries. The lens and rim are MetalUI's own look (divergence 825), tunable in `GlassLook` alone. **Observed:**
- [ ] **LG2.** `.buttonStyle(.glass)` and `.glassProminent` (padding, the capsule radius, the accent tint, a label that is **not** turned white, `LG-U` 7) and `Glass.regular.tint(_:)` against SwiftUI; SwiftUI's regular tint read a colour-independent grey in the capture (`LG-E`). **Observed:**
- [ ] **LG3.** The container's three circles with the spacing control: the merge threshold (`spacing > 2 × gap`) and the neck against SwiftUI's; `glassEffectUnion` as one blob regardless of distance, where SwiftUI's capture showed one circle between the two (`LG-H`, divergence 826); a non-glass sibling between two members sits **under** the blob. **Observed:**
- [ ] **LG4.** System Settings, Accessibility, Display, Reduce transparency on: glass shapes are an opaque grey with no blur (`LG-F`); SwiftUI's own fallback is unmeasured. **Observed:**
- [ ] **LG5.** The demo on SDL, a desktop GPU: Linux (Vulkan) and Windows (D3D12). Lens, rim and merge look as on macOS (lavapipe reads max delta 3 on parity frames 12 and 13, `BB-J`'s tolerance with no headroom; D3D12 is CI only). **Observed:**
- [ ] **LG6.** A press held on a `.glass` button: the tint lifts by a white wash (alpha 0.12) while the pointer is down over it and drops on release; SwiftUI scales and bounces (carried, `LG-J`, divergence 827); a bare `.glassEffect(.interactive())` on non-control content does nothing. **Observed:**

## TL. Hung SDL test helpers - SIGTERM, orphaned helpers, the run deadline (item HG, user request 2026-10-02 and MetalCreator's report 2026-10-24, not a plan task; record 154; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: a test cannot orphan its own runner. The watcher's decision, the deadline and the environment parse are pinned (`SDLTestProcessGuardTests` TL1-TL6); the end-to-end exit is `docs/probes/sdl-orphan-exit.sh` (`TL-J`).*

- [ ] **TL1.** macOS: in `Backends/SDL`, start `swift test` on a GPU test that blocks (a temporary test waiting on a semaphore), press Ctrl-C: the helper ends within a second and `pgrep -f swiftpm-testing-helper` shows none. **Observed:**
- [ ] **TL2.** The same in the Linux image (`docker run` as in `docs/testing.md`), then `docker stop` the container mid-run: no helper outlives it. **Observed:**

## WG. SDL test guard on Windows (item WG, user request 2026-10-02, not a plan task; record 158; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: the Windows half was written with no Windows machine (the UTM VM was unreachable, `WG-I`) and has never been compiled or run.*

- [ ] **WG1.** The first green Windows CI run of the `windows` job shows TL1, TL3-TL8, WG1-WG3 passed in `MetalUISDLTests` and no exit 70 (a false orphan, `WG-J`). **Observed:**
- [ ] **WG2.** In the UTM VM (or any Windows machine) run `powershell -File docs\probes\sdl-orphan-exit.ps1` and paste its output into the probe header (expect to fix its helper search to walk descendants first). **Observed:**
- [ ] **WG3.** A hung test under a short deadline shows exit 71 and the `METALUI_TEST_DEADLINE_SECONDS` message in the log (a `waitBlocking` with no partner under `METALUI_TEST_DEADLINE_SECONDS=30`). **Observed:**

## Sign-off

Name, date, machine (macOS version, display(s)), build commit:


## TP. SDL precise scroll - `isPrecise` and synthesized phases on a trackpad (item XP-G28, user request 2026-10-02 and MetalCreator's request 2026-10-24, not a plan task; record 155; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: no real trackpad or desktop session exists in the agent's environment, so every statement about what Wayland, X11 or Windows sends is a reading of SDL 3.4.16's source (`TP-A`). The classifier, the expiry and the `Window` rules are pinned with synthesized events (`SDLScrollClassifierTests`, `SDLInputAPITests` 1.16, `SDLShapedScrollWindowTests`). Run the demo `METALUI_CANVAS_DEMO=1` (its canvas prints the scroll's phases and `precise`/`lines`) on each desktop.*

- [ ] **TP1.** Wayland (GNOME and KDE), two-finger trackpad scroll: `isPrecise` true, one `.began`, `.changed` events, one zero-delta `.ended` about 150 ms after the last motion; **log the inter-event gaps** (they measure `quietInterval`, `TP-C`, an unmeasured ruling) and note any gesture split by a pause. **Observed:**
- [ ] **TP2.** X11 (XI2 smooth scrolling), the same as TP1. **Observed:**
- [ ] **TP3.** Windows precision touchpad: the same, including inertia after the fingers lift (expected: precise `.changed`, no momentum phase, divergence 846) and a fast flick (integral deltas must stay precise). **Observed:**
- [ ] **TP4.** A notched wheel on Wayland, X11 and Windows: `isPrecise` false, phase `.none`, no `.ended`. **Observed:**
- [ ] **TP5.** A hi-res wheel (Wayland `value120`, Windows free-spin): record what it reads (expected precise, divergence 845). **Observed:**
- [ ] **TP6.** macOS under the SDL trait (a trackpad and a wheel through `SDLPlatform`): same readings as TP1 and TP4; AppKit's own values are unchanged. **Observed:**
- [ ] **TP7.** A notch within 150 ms after a trackpad stream (expected: the `.ended` first, then the notch as a wheel), and over 50 trackpad gestures the count whose first event was integral and read as a wheel. **Observed:**
- [ ] **TP8.** `SDLPlatform.Options(scrollPrecision: .disabled)` restores `false`/`.none` for every event, trackpad included. **Observed:**


## MA. Menu anchor under render effects - `Menu`, `Picker(.menu)`, popovers (item XP-G29, MetalCreator report 2026-10-26, not a plan task; record 156; provisional letter, in the manner of `RT`, `KF` and `IF`)

*An agent cannot: a real `NSMenu` pop-up runs AppKit's tracking loop and a real window needs an unlocked desktop. The point handed to the platform is pinned (`MenuAnchorTests`, `AppKitMenuTests`); where the pop-up appears on screen is a look. Run `METALUI_MENUS_DEMO=1 swift run MetalUIDemo` (the "Anchor check" strip: a `Menu("View")` under `.offset(x: 40, y: 20)` and a `Picker(.menu)` under `.scaleEffect(1.5, anchor: .topLeading)`, in the right half of a split).*

- [ ] **MA1.** AppKit, real window: click "View" and the Mode picker. Each pop-up opens at its label's **drawn** bottom-leading corner, not at the layout position (about 40 and 20 points up-left of it for "View"). Repeat with the window resized and a different `.offset`. Compare with a real SwiftUI `Menu` under `.offset` in a scratch app (MA-E: SwiftUI's behaviour is MetalCreator's stated expectation, not probed). **Observed:**
- [ ] **MA2.** SDL (`METALUI_MENUS_DEMO=1 swift run MetalUISDLDemo`, which draws its own menu panel), the same two controls: the drawn panel's top-leading corner is the label's drawn bottom-leading corner, clamped to the window. **Observed:**
- [ ] **MA3.** MetalCreator's real app: the `View` menu of `cubeControls` (offset by the cube layout's origin, over the GPU surface in the right pane) opens under its label at about (1000, 410) on the report's window, not at (10, 100). Also drag the cube (the offset moves each frame) and open the menu again: it follows the label. **Observed:**

## EL. Layout and outer effect moved together - the growing header over a zoom (item FS-O, record 157; provisional letter)

- [ ] **EL1.** `METALUI_RETAINED_DEMO=1 swift run MetalUIDemo`, real window, the strip "Growing header over a zoom": press "+4 and zoom" repeatedly. The ten cards move down and grow with no jump or flash, `translated` and `grafted` rise by about ten a press, `redos` stays 0 and `refused` stays "none". With "Replay" off the same presses build every card and the picture is identical. **Observed:**

## HX. Run-time compile without the `SDL` trait - `MetalUIShaderRuntime` (item XP-G27, record 160; provisional letter)

*An agent cannot: a hardened-runtime signed `.app`, a Windows desktop and a Linux machine without SDL3 are not in the agent's environment. The macOS default-build arm is measured (`HX-B`, `HX-I`).*

- [ ] **HX1.** A signed `.app` with the hardened runtime and library validation, built without the `SDL` trait, shipping the five dylibs of `docs/packaging.md` 4b in `Contents/Frameworks`: `RuntimeShaderCompiler.selfTest()` loads and compiles (or note which signing step it needs). **Observed:**
- [ ] **HX2.** Windows, default build: `SDL3.dll` beside `SDL3_shadercross.dll` is loaded by `LoadLibraryW` after `SetDllDirectoryW`, `GetModuleHandleW(L"SDL3.dll")` is the module shadercross bound, and a broken kernel's diagnostics arrive. **Observed:**
- [ ] **HX3.** Linux tarball with no system libSDL3: `libSDL3.so.0` beside shadercross is preloaded `RTLD_LOCAL`, `dlsym(handle, "SDL_GetError")` finds shadercross's instance, a compile succeeds. **Observed:**

## BT. App shaders on `swift build` - `CompileShadersOnBuild` (item BS-D, record 161; provisional letter)

*An agent cannot: a Windows machine and a URL dependency are not in the agent's environment.*

- [ ] **BT1.** A Windows consumer build applying the plugin, both arms (shadercross on `PATH` spelled `Path`, and none with matching checked-in blobs): the PATH spelling, DLLs, CRLF (`eol=lf`) and the `.resources` layout.
- [ ] **BT2.** A dependency on MetalUI **by URL** applying the plugin builds and finds the bundle.
- [ ] **BT3.** A shipped macOS `.app` finds `MetalUIAppShaders` in its resource bundle through `locate(resourceBundle: .module)`.
- [ ] **BT4.** (record 162, XP-G32) On Windows and Linux, a header-only edit (a `.hlsli` under `Shaders/`) reruns the build command: with shadercross it recompiles, without it the copy path refuses naming the changed `INCLUDES.sha256` entry; and `-I` finds a nested include under the host's path spelling. **Observed:**

## VD. SDL desktop video and dialog filter names (items XP-G33, XP-G34, record 163; provisional letter)

*An agent cannot: a real Wayland compositor, a hardware-GL X server and a GTK portal are not in the agent's environment (only Xvfb was measured, `VD-C`).*

- [ ] **VD1.** A Linux tarball or AppImage bundling the image's `libSDL3.so.0` opens a window and draws on a real X11 desktop with `SDL_VIDEO_DRIVER` unset. **Observed:**
- [ ] **VD2.** The same package opens a window on a real Wayland session (libdecor decorations, resize, close) with `SDL_VIDEO_DRIVER` unset. **Observed:**
- [ ] **VD3.** An open and a save dialog on Linux (GTK portal, and zenity if that is the fallback) with a typed filter: the label reads `JSON (*.json)` or `MetalCreator graph (*.mcgraph;*.mcg)`, never a raw identifier, and a type with no description reads `*.mcgraph`. **Observed:**

## WA. Window and application activation - `Window.makeKeyAndOrderFront()`, `App.activate()` (item MF-activate, MetalFlow notification click; decisions `docs/superpowers/2026-10-30-window-activation-decisions.md`; provisional letter)

*An agent cannot: which window is in front, key, or de-miniaturised is a look at the window server; the headless platform only counts the call.*

- [ ] **WA1.** With another application frontmost, trigger a response that calls `app.activate()` then `window.makeKeyAndOrderFront()` (a notification click, or a menu item from a timer-less button that fires after you switch away, as the demo or MetalFlow does). The MetalUI window comes to the front, is key (its title bar is active, typing reaches it), and the other application goes behind. **Observed:**
- [ ] **WA2.** Minimise the window to the Dock, then trigger the same call: the window de-miniaturises and comes forward, key. **Observed:**
- [ ] **WA3.** With two MetalUI windows, call `makeKeyAndOrderFront()` on the rear one: it comes in front of the other and becomes key. **Observed:**
- [ ] **WA4.** (Linux/Windows, SDL) The same call raises the window and restores a minimised one; the window manager may only flash the taskbar entry when it denies focus stealing. **Observed:**

## FO. Folder importer - `.fileImporter(…allowedContentTypes: [.folder])` (MetalFlow "Add repo"; ruling `SV-AM`, record 170; provisional letter)

*An agent cannot: `NSOpenPanel` does not initialise under a locked screen, and SDL's folder dialog needs a desktop portal; only the configuration (`openPanelConfiguration`, `dialogMode`) and the harness flow were measured.*

*Run:* macOS `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo`; Linux/Windows the SDL demo, from `Backends/SDL`: `METALUI_SERVICES_DEMO=1 swift run $(python3 scripts/fetch-accesskit.py --print-flags) MetalUISDLDemo` (run `python3 scripts/fetch-accesskit.py` once first). The Dialogs section has **Import folder…** (`[.folder]`) and **Import folder or JSON…** (`[.folder, .json]`); the outcome line reads "Imported folder [name]" or "Imported [name]" on success.

- [ ] **FO1.** macOS (click **Import folder…** in the Services demo): a `.fileImporter` over `[.folder]` opens a sheet in which ordinary folders are enabled and files greyed out; choosing a git repository folder (and pressing Open while inside it) completes with that folder's URL. **Observed:**
- [ ] **FO2.** macOS (click **Import folder or JSON…**): over `[.folder, .json]` both a folder and a `.json` file can be chosen. **Observed:**
- [ ] **FO3.** Linux (GTK portal or zenity) and Windows (SDL demo; **Import folder…**, then **Import folder or JSON…**): over `[.folder]` the platform's folder picker opens and returns the folder; over `[.folder, .json]` the file dialog opens (files only, divergence 209). **Observed:**

## BY. Button, toggle and picker styles - custom styles, `.borderedProminent`, `.link`, `.switch`, `.button` (round 3 item R3-1; decisions `docs/superpowers/2026-10-31-styles-decisions.md`, record 174; provisional letter)

*An agent cannot: every look here is MetalUI's (SwiftUI's chrome for these styles was not probed and the offscreen capture draws no text), and a pressed look, a knob and a focus ring are looks. Run `METALUI_CONTROLS_DEMO=1 swift run MetalUIDemo` (or a scratch window) with the styles below.*

- [ ] **BY1.** `Button("Save") {}.buttonStyle(.borderedProminent)`: an accent-filled rounded rectangle at the bordered button's size, the label white; it dims under the 12 % wash while pressed and returns on release, and it greys (separator colour) when the window is not key. **Observed:**
- [ ] **BY2.** `Button("Docs") {}.buttonStyle(.link)`: the label alone in the accent colour; it fades to 60 % while pressed. Hovering shows no pointing-hand cursor (carried). **Observed:**
- [ ] **BY3.** A custom `ButtonStyle` whose body is `configuration.label.padding(10).background(configuration.isPressed ? .gray : .accent)`: it fills grey exactly while the mouse is down and over the button, goes back to accent when dragged out, grey again when dragged back in, and the action runs once on release inside only. Tab focuses it (a 2-point ring around the padded body) and Space runs the action. **Observed:**
- [ ] **BY4.** A `PrimitiveButtonStyle` using `configuration.label.onClick { configuration.trigger() }` runs the action on a click; one that never calls `trigger()` does nothing on a click. With VoiceOver, the primitive-styled button is reachable and VoiceOver's press runs the action (BY-C's documented limit: only if the body declares a clickable element). **Observed:**
- [ ] **BY5.** `.toggleStyle(.switch)`: a 38x22 capsule, accent when on and a neutral grey with a border when off, a white knob at the left (off) or right (on) that jumps rather than slides (divergence 885); the label follows. A click, Space and VoiceOver's press each flip it. **Observed:**
- [ ] **BY6.** `.toggleStyle(.button)`: a bordered button that fills with the accent colour and a white label while on, bordered grey off; no pressed look. **Observed:**
- [ ] **BY7.** `.pickerStyle(.inline)` looks like the radio-group column. **Observed:**
- [ ] **BY8.** `.buttonStyle(_:)` / `.toggleStyle(_:)` written on a `Column`/`Row` reach every control inside; a nearer style on one control wins. **Observed:**

## MG. Matched geometry and custom transitions - the looks of the morph (item R3-2; rulings `MG-A`…`MG-G`, record 175; provisional letter)

*An agent cannot: the headless suite pins the rectangles frame by frame; whether the motion reads as a morph, and how a stretched glyph or a rounded corner looks mid-flight, is a look. Run an app with the swap below.*

- [ ] **MG1.** A card `A` (a rounded accent rectangle with a label) in the top-left and a larger card `B` in the bottom-right, one `if selected { B } else { A }` with `.matchedGeometryEffect(id: "card", in: ns)` on both, toggled by a button inside `withAnimation(.easeInOut(duration: 0.4))`: the new card grows out of the old one's frame and settles, with no jump on the first or the last frame. **Observed:**
- [ ] **MG2.** The same with a label wider in `B` than in `A`: the label is stretched on the way (divergence 896) and snaps to its natural proportions when the flight lands, with no visible pop at the landing. If the stretch reads badly, record how. **Observed:**
- [ ] **MG3.** Toggle again mid-flight: the view turns round from where it was drawn, with no jump. **Observed:**
- [ ] **MG4.** Click the flying card early in the flight: the click lands on the card's final frame, not where it is drawn (divergence 895). Record whether this is noticeable. **Observed:**
- [ ] **MG5.** A custom `Transition` (scale 0.5 and fade) on an `if`: it grows in and shrinks out about its centre, reads as the built-in `.scale` combined with `.opacity`. **Observed:**
- [ ] **MG6.** With Reduce Motion on in System Settings, the custom transition is a plain fade and the matched swap still flies (Reduce Motion is not applied to the flight: unprobed). **Observed:**
## DX. Dialog extras - `.fileDialogConfirmationLabel`/`.fileDialogMessage` and non-`Text` alert buttons (round-3 item R3-6; ruling `SV-AO`, record 179; provisional letter)

*An agent cannot: `NSOpenPanel` does not initialise under a locked screen, and SDL's dialogs need a desktop portal; only the seam (`PlatformFileDialog.prompt`/`message`, `AppKitWindow.panelTexts`, `SDLWindow.dialogLabels`) and the harness flow were measured.*

*Run:* macOS `METALUI_SERVICES_DEMO=1 swift run MetalUIDemo`; Linux/Windows the SDL demo as in group FO. The **Import folder…** button now carries `.fileDialogConfirmationLabel("Use folder")` and `.fileDialogMessage("Pick the repository folder to add.")`; **Import folder or JSON…** carries neither (the control).

- [ ] **DX1.** macOS (click **Import folder…**): the sheet's confirming button reads "Use folder" (not "Open") and the line "Pick the repository folder to add." shows in the panel above the file list; **Import folder or JSON…** still reads "Open" with no message. **Observed:**
- [ ] **DX2.** macOS (click **Export…**): the exporter's confirming button still reads "Export" (no label written above it). **Observed:**
- [ ] **DX3.** Linux (GTK portal or zenity) and Windows (SDL demo, **Import folder…**): the dialog's title bar reads "Pick the repository folder to add." (divergence 935), and the accept button reads "Use folder" where the desktop's dialog honours SDL's accept label (it may not; note which). **Observed:**
## GE. Gesture composition - long press then drag, flick velocity (item R3-5, record 178; decisions `docs/superpowers/2026-10-31-gesture-composition-decisions.md`; provisional letter)

*An agent cannot: the headless suite stamps events itself; real pointer timing, the feel of a flick and a long-press-then-drag on a trackpad are looks.*

- [ ] **GE1.** An element with `LongPressGesture(minimumDuration: 0.5).sequenced(before: DragGesture())`: hold 0.6 s without moving, then drag: it follows from where the pointer was at the first move after the hold (no jump), and a release before 0.5 s does nothing. **Observed:**
- [ ] **GE2.** Drag an element and release it mid-flick: `value.predictedEndLocation` lands where a quarter second more of that motion would (a ball thrown to it looks natural); a drag that stops before release predicts about its own end. **Observed:**
- [ ] **GE3.** On Linux/Windows (SDL) the same flick predicts a comparable distance for the same hand speed (SDL event times are seconds from `mui_now`). **Observed:**
## SP. Scroll extras and `@Bindable` - pinned section headers, `scrollPosition(id:)`, an animated `scrollTo` (item R3-4, round-3 batch; decisions `docs/superpowers/2026-10-31-scroll-position-decisions.md`, record 177; provisional letter)

Run `METALUI_LAZY_DEMO=1 swift run MetalUIDemo` and use the fifth section (bottom row): 40 sections of 100 rows under a header, the title row naming the topmost row, three buttons and a header-title field.

- [ ] **SP1.** Scroll the section with the trackpad or wheel: the current section's header stays at the top of the scroller while its rows pass under it (the header is painted above them and a click on it is not taken by a row), and when the section ends its header leaves with it - the next header slides in over it, it is not pushed up. **Observed:**
- [ ] **SP2.** The title row shows `top row N` and follows the scroll: N is the first row reaching the top edge (a half-visible row counts), changing as rows pass and not flickering at rest; the demo stays smooth through a fast flick over thousands of rows. **Observed:**
- [ ] **SP3.** Press **Row 2500**, **Row 120** and **Row 0**: the list glides to the row (about 0.4 s, eased) rather than jumping, ends with the row at the top, and the title row then reads the same number; a wheel during the glide stops it where it is. **Observed:**
- [ ] **SP4.** Type in **Header title**: every visible header (and the pinned one) renames at once - the `@Bindable` text binding writes the observable and the frame redraws. **Observed:**
- [ ] **SP5.** Resize the window while a header is pinned: the header stays at the top edge with no gap or flash, and no row beneath it shows through. **Observed:**
- [ ] **SP6.** On Linux or Windows (the SDL demo with `METALUI_LAZY_DEMO=1`): SP1-SP4 look the same. **Observed:**

## PG. Path operations - `trim` animation, uneven corners, trimmed and stroked outlines (round 3 item R3-8; decisions `docs/superpowers/2026-10-31-path-ops-decisions.md`, record 181; provisional letter)

*An agent cannot: motion, the look of a growing stroke and the look of an uneven corner are looks, and the offscreen capture is blind to animation. Run a scratch window (or add the views to `METALUI_CANVAS_DEMO=1`) with the views below.*

- [ ] **PG1.** `Circle().trim(from: 0, to: progress).stroke(.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))` with a button that does `withAnimation(.linear(duration: 2)) { progress = 1 }` (and back to 0): the ring is drawn clockwise from the rightmost point (3 o'clock), growing smoothly to a full circle in two seconds with no jump at either end, and shrinking back the same way. **Observed:**
- [ ] **PG2.** The same ring with `.easeInOut` and a second tap mid-flight: it reverses from where it is, without a jump. **Observed:**
- [ ] **PG3.** `RoundedRectangle(cornerRadius: 16).trim(from: 0, to: p)` stroked, animated: the stroke starts at the midpoint of the right edge and runs down, round the bottom, up the left, along the top and back. `Rectangle().trim` starts at the top-left corner running right. **Observed:**
- [ ] **PG4.** `trim(from: s, to: s + 0.25)` animated with `s` from 0 to 0.75: a quarter-length dash chases round the ring (it does not wrap past the end; at `s` > 0.75 it shortens). **Observed:**
- [ ] **PG5.** `UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 10, bottomTrailingRadius: 20, topTrailingRadius: 0)` filled, 120x80: the top-left corner is the largest quarter circle, the top-right is square. `.strokeBorder(.red, lineWidth: 3)` hugs the same corners with no gap. As a `.clipShape(...)` over an image it clips the same. **Observed:**
- [ ] **PG6.** `UnevenRoundedRectangle(topLeadingRadius: 45)` in a 100x60 frame, filled and stroked: the top-left corner is one big arc, 45 points, not shrunk to 30 as a plain rounded rectangle would. **Observed:**
- [ ] **PG7.** `path.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)).fill(.accent)` on a zig-zag looks like `path.stroke(.accent, style: ...)` of the same style, joins and caps included; filled with a gradient it fills the band. **Observed:**
- [ ] **PG8.** A dashed `RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))`: the pattern begins at the midpoint of the right edge (not at a corner). **Observed:**
