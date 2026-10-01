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
   `METALUI_LOOKS_DEMO=1` (the looks demo, 1180×720: H1, I1, J1, K1–K3).
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

## Sign-off

Name, date, machine (macOS version, display(s)), build commit:

