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

## Sign-off

Name, date, machine (macOS version, display(s)), build commit:

