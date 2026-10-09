# Controls and looks — decisions

Rulings for `ColorPicker`, `Slider(onEditingChanged:)`, `ProgressView`,
keyframe animation, gradients, `.blur(radius:)` and materials (user request
2026-10-02, item C10 of the gpui-gap priority list; **not a plan task**).
Requested by MetalCreator (`docs/metalui-gaps.md` gaps M6-f, M5-a, M5-c, M5-d,
M5-i, M5-j) and by the SMK configurator port (MG-7 colour picker, MG-9
materials). Spec: [`specs/2026-10-08-controls-looks-design.md`](specs/2026-10-08-controls-looks-design.md).
Record: `../record/85-controls-looks.md`.

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-controls-looks.swift`](../probes/swiftui-controls-looks.swift)
  (**new**; groups `P` (controls), `S` slider, `V` progress view, `C` colour
  picker, `K` keyframes, `G`/`R` gradients, `B` blur, `M` materials; compiled
  form run twice, 160 lines byte-identical, screen locked) — SwiftUI's answers.
- [`../probes/gradient-raster-cost.swift`](../probes/gradient-raster-cost.swift)
  (**new**; a measurement, not a SwiftUI probe) — what a CPU gradient raster
  costs at window size, and that a premultiplied-Oklab table reproduces
  SwiftUI's midpoint.
- Earlier probes cited by arm: `swiftui-controls-and-selection.swift` (`KY7`:
  SwiftUI's slider takes no arrow key), `swiftui-paths-shadows-transforms.swift`
  (`SH3`, `SH5`: the shadow blur and its per-leaf rule),
  `swiftui-transactions-animation.swift` (the in-process Reduce Motion swizzle
  reused by `V10`), `swiftui-accessibility-bridge.swift` (the
  `AXEnhancedUserInterface` activation reused by every AX arm here).

Where SwiftUI has no answer (a hex field, how a drawn panel takes keys, what a
GPU surface under a blur shows) the ruling says so; gpui is named as a
comparison where it has one, never as evidence.

Prefix **`LK-`**, lettered. **Next unused: `LK-X`.** (This line moves in the
commit that appends a ruling; read the last `## LK-` heading.)

Branch `feat/controls-looks` from `cd84b0c` (master: variable-height `List`,
PR #53). Baseline at `cd84b0c` per the brief: **2723 tests in 3 suites**; not
re-taken by the design session (other workflows share the machine; lane 1
takes it before its first change, spec §0).

**Final spellings (what MetalCreator and the configurator swap their stopgaps
to)** — each lands in the lane named in the spec, and the lane's ruling or the
record names any change:

| Gap | Spelling |
|---|---|
| M5-a | `Slider(value: $v, in: 0...1, onEditingChanged: { editing in … })` (and `step:`) |
| M6-f, MG-7 | `ColorPicker("Tint", selection: $color, supportsOpacity: true)` over MetalUI's `Color` (also `ColorPicker(selection:supportsOpacity:label:)`, `LK-P`) |
| M5-j | `ProgressView()`, `ProgressView(value: x, total: 1)`, `ProgressView("Label", value: x)`, `.controlSize(.small)`, `.progressViewStyle(.linear / .circular)` |
| M5-i | `.keyframeAnimator(initialValue: 0.0, trigger: refusals) { content, x in content.offset(x: Pixels(Float(x))) } keyframes: { _ in KeyframeTrack { LinearKeyframe(6, duration: 0.05); LinearKeyframe(-6, duration: 0.1); LinearKeyframe(0, duration: 0.05) } }` |
| M5-d | `LinearGradient(colors: [a, b], startPoint: .top, endPoint: .bottom)` as `.background(_:)` (both vocabularies) and `Shape.fill(_:)`; `RadialGradient(colors:center:startRadius:endRadius:)` |
| M5-c (blur) | `.blur(radius: Pixels(6))` |
| M5-c, MG-9 (materials) | `.background(.ultraThinMaterial)` … `.ultraThickMaterial`, `.bar` — **a fitted flat tint with no backdrop blur** (`LK-L`, divergence 166); the backdrop blur is deferred |

---

## LK-A — Scope: what this branch builds, what it defers, and the lanes

**Ruling.** The branch builds, in three sequential lanes on disjoint files
(agents run one at a time in this worktree):

1. **Lane 1 — controls**: `Slider(onEditingChanged:)` (`LK-B`), `ColorPicker`
   and its drawn panel (`LK-C`, `LK-D`), and the three accessibility roles the
   branch needs (`LK-G`) on both bridges.
2. **Lane 2 — progress and keyframes**: `ProgressView` (`LK-E`, `LK-F`) and
   `keyframeAnimator`/`KeyframeAnimator`/`KeyframeTimeline` (`LK-H`, `LK-I`).
3. **Lane 3 — looks**: `Gradient`, `LinearGradient`, `RadialGradient`
   (`LK-J`), `.blur(radius:)` (`LK-K`), `Material` (`LK-L`).

Deferred, each by name, with its owner:

| Deferred | Reason | Owner |
|---|---|---|
| The native `NSColorPanel` route for `ColorPicker` on AppKit | every file it needs (`Platform.swift`, `InputEvent.swift`, `AppKitPlatform.swift`, `SDLPlatform.swift`, `Tests/MetalUITests/Fakes.swift`) is edited by `feat/input-apis`, which the brief puts off-limits; the seam is designed (`LK-C` item 6) | a follow-up after `feat/input-apis` merges (C10-b, unscheduled) |
| Backdrop blur for materials | `LK-L`: a CPU backdrop cannot see a GPU surface (MetalCreator's case), a GPU backdrop needs a pass split on both renderers and an intermediate target on SDL | a renderer follow-up (C10-c, unscheduled) |
| `phaseAnimator`/`PhaseAnimator` | `LK-H`: needs a logical-completion rule for springs that is unmeasured and new transaction plumbing | none (additive later) |
| `SpringKeyframe` without `duration:`, `Spring.settlingDuration` | `LK-I` item 5: SwiftUI's default length is unfitted (`K4b`, `K4d`) | none |
| `AngularGradient`, `EllipticalGradient`, `Gradient.colorSpace(_:)`, `.foregroundStyle(gradient)` on text, gradient animation | `LK-J` items 7–8 | none |
| `.blur(radius:opaque:)`'s `opaque: true` | `LK-K` item 6 | none |
| `ProgressView(timerInterval:)`, `ProgressView(_: Progress)`, a custom `ProgressViewStyle` | no requester; `Progress` is Foundation-only | none |
| `CGColor` bindings (label views are built: `LK-P` item 2) | MetalUI's `Color` is the one colour type (`CR-`) | none |

**Reasoning.** Six features in one branch is only honest if each lands whole
or is deferred by name. The split follows the files: lane 1 owns `Slider.swift`,
the one `Window.swift` hunk and the accessibility enum and bridges; lane 2 owns
`AnimationStore.swift` and the new progress/keyframe files; lane 3 owns the
paint path (`RasterCache.swift`, `Shadow.swift`'s neighbours, `ShapeView.swift`,
`Box.swift`'s `Decoration`, `NativeModifiedContent.swift`). ProgressView rides
with keyframes because both are frame-clock animations driven through
`noteActiveAnimation()`; the roles it needs land in lane 1 first.

**Cost if wrong.** A lane that finds its piece cannot land honestly defers it by
a lettered ruling; the table above grows, the spellings table shrinks.

## LK-B — `Slider(onEditingChanged:)`: SwiftUI's order, one pair per gesture

**Ruling.**

1. **Spelling**: SwiftUI's — `init<V>(value: Binding<V>, in bounds:
   ClosedRange<V> = 0...1, onEditingChanged: @escaping (Bool) -> Void = { _ in })`
   and `init<V>(value:in:step:onEditingChanged:)`. The existing two inits
   gain the defaulted parameter (source-compatible; their census rows change).
2. **A press** calls `onEditingChanged(true)` **before** the press's write;
   each drag writes; **the release** calls `onEditingChanged(false)` **after**
   the last write (probe `S1`: `editing true | set 0.222 | set 0.333 | set
   0.444 | editing false`). A press with no drag is `true, write, false`
   (`S2`); a drag that does not move writes nothing more (`S3`).
3. **An accessibility increment or decrement** is a whole edit: `true`, the
   write, `false` (`S4`). **An arrow key** (MetalUI's `DD-T`; SwiftUI's slider
   takes none, `KY7`) is the same pair — a MetalUI rule by analogy with `S4`,
   not a SwiftUI claim.
4. **Nothing else** calls it: a binding write from outside (`S5`), a disabled
   slider's press (`S7`, the hitbox is gated), a hover, a scroll.
5. **The pairing invariant** (MetalUI's, unprobed edges): every `true` is
   followed by exactly one `false`. The window keeps the pressed slider's
   callback from the press (beside `active`) and calls it at the release
   wherever the release lands, **even if the slider left the tree, was
   disabled or the window closed mid-drag** (a close counts as the release).
   Both calls run under `StateDispatch` to the pressed slider's id (`ID-F`).
6. **Where** (**amended by `LK-Q`**: the release end moved to the top of the
   input hook; no `pressedBefore:`): `ValueTrackTarget` gains `onEditingChanged`; `dispatchValueTrack`
   (`Window.swift`) gains the release case and a `pressedBefore:` argument.
   `Handlers` keeps seventeen members (the callback rides `valueTrack`). The
   hunk is inside `dispatchValueTrack` and the window's close path (the
   caller of `runDisappearancesForClose`) only;
   `feat/input-apis`' `Window.swift` hunks (diff stat read 2026-10-08: lines
   875–2440 of the old file, the pinch/button arenas and the gesture press) do
   not reach it, and `ControlKeys.swift` and `valueTrack` are untouched there.

**Reasoning.** M5-a's use is undo coalescing: one undo step per drag. SwiftUI's
order (open before the first write, close after the last) is what makes a
coalescing key correct — a key opened after the first write would split it.

**Cost if wrong.** A missed `false` leaves an undo group open forever; the
invariant is pinned on its three edges (spec §3.1).

## LK-C — `ColorPicker`: a drawn well and a drawn panel on every platform

**Ruling.**

1. **Spelling** (**amended by `LK-P`**: `ColorPicker<Label>`, `Element,
   StyledElement`, one `Box`, plus the label-view initialiser): `ColorPicker(_ titleKey: String, selection: Binding<Color>,
   supportsOpacity: Bool = true)`. One public type, an `Element`, usable in both
   vocabularies (in a SwiftUI stack through `LegacyContent`, `PE-C`).
2. **Geometry** (probe `C0`, `V12`): the label `Text`, **8 points**, then a
   **48×24** well (`79 = 23 + 8 + 48` for "Tint"; `170 = 114 + 8 + 48`). An
   empty title draws the well alone (48×24, `labelsHidden()`'s answer). The
   well hugs; the whole is `HStack(spacing: 8)`-shaped and baseline-free.
3. **The well** draws a rounded bezel (`.separator` 1-point border, radius 5,
   `.surface` fill) with the selection inset 4 points (radius 3); a colour with
   opacity < 1 shows a 4-point checkerboard behind it in its right half (the
   NSColorWell convention, a look — human check). It is focusable and takes the
   control focus ring; Space/Return or a press **opens the panel**; a press
   does not focus (divergence 94's rule).
4. **The panel** is a `.popover` from the well (MetalUI's anchored presentation
   root, `MN-`), drawn on **every** platform (SDL has no colour panel). Its
   parts and keys are `LK-D`.
5. **Colour**: every write is `Color(.sRGB, red:green:blue:opacity:)` — gamma
   sRGB, MetalUI's literal (`CR-`; divergence 1 applies as to every literal).
   The panel seeds from `selection.wrappedValue.resolve(in:)` with the
   environment at open, so a token, dynamic or palette selection opens at its
   current resolved value and the first edit replaces it with a literal (what
   AppKit's panel does to a dynamic system colour, `C5`/`C6`: the binding
   receives the panel's colour as a plain colour). **`supportsOpacity: false`**
   hides the opacity bar and the hex field's alpha, and **every write carries
   opacity 1** (`C8`: SwiftUI writes alpha 1 even when the panel's colour has
   0.5). The panel never writes outside 0…1 (it edits in sRGB HSB); P3 input
   is not possible from it.
6. **The native route is deferred, with its seam designed**: a defaultless
   `PlatformWindow.presentColorPanel(_ request: ColorPanelRequest) -> Bool`
   (AppKit: `NSColorPanel.shared` with `showsAlpha = supportsOpacity`,
   changes returned as queued `InputEvent.colorPanelChanged(token:, rgba:)`;
   SDL and fakes `false`), with `dismissColorPanel(token:)`; `false` falls back
   to this ruling's drawn panel (the `presentMenu` precedent, `MN-C`). Owner:
   C10-b, after `feat/input-apis` merges (`LK-A`). Until then **divergence 165**:
   on macOS SwiftUI's well opens `NSColorPanel` (`C3`: `active=true
   panelVisible=true showsAlpha=true`), MetalUI's opens a drawn popover.
7. **Accessibility** (probe `C1`): the label is its own static text; the well is
   a new role **`.colorWell`** (`LK-G`), no label, value `"rgb R G B A"` with
   components printed like AppKit's (`rgb 1 0 0 1`: shortest decimal, at most 3
   places), press action opens the panel.

**Reasoning.** A drawn picker is needed on SDL anyway; drawing it everywhere
gives one implementation the suite can drive headless, and the native route
slots in later behind a `Bool`-returning seam without an API change (the swap
is by spelling, so MetalCreator's call site does not move). The colour rule
follows SwiftUI's observable behaviour on the binding (`C4`–`C8`) rather than
its panel's colour spaces, which MetalUI's `Color` cannot hold (`CR-C` item 6).

**Cost if wrong.** A user who expects the system panel on macOS sees a drawn
one (divergence 165, human check). The colour arithmetic is pinned by value.

## LK-D — The drawn colour panel: parts, input, keys, accessibility

SwiftUI has no drawn panel to measure; every item here is MetalUI's rule
(macOS's own NSColorPanel "wheel/square" pages are the look reference — a
human check, not evidence).

**Ruling.**

1. **Parts**, top to bottom, 12-point padding, 8-point gaps, 200 points wide:
   a **saturation–brightness square** (200×150; x = saturation 0…1, y =
   brightness 1…0) with a 10-point ring marker; a **hue bar** (200×14, hue
   0…360°, wrapping colours) with a thumb; an **opacity bar** (200×14, the
   current colour from clear to opaque over a checkerboard) only when
   `supportsOpacity`; a row of a **swatch** (24×24, the current colour) and a
   **hex field** (`TextField`, the rest of the row).
2. **The square and bars are images**, made on the CPU per value (an
   `ImageBitmap` the panel caches by hue for the square, by colour for the
   opacity bar; the hue bar once) and drawn with `Image` — no dependency on
   lane 3's gradients, no shader change.
3. **Pointer**: a press or drag on the square sets saturation and brightness
   from the local point (clamped to the square); on a bar, hue or opacity from
   the local x. Every move **writes the binding** (continuous, as SwiftUI's
   panel does, `C4`). Built on `DragGesture(minimumDistance: 0)` (public API;
   no change to `Gesture.swift`).
4. **The panel keeps its own HSB(A) state** (`@State` in the panel's
   `Component`), seeded at open; a binding change from outside while open
   re-seeds it only when the new value differs from the panel's last write
   (so hue survives saturation 0 and brightness 0 while dragging).
5. **Keys**: the square, each bar and the field are focusable (Tab order:
   square, hue, opacity, field). On the square ←/→ change saturation and ↑/↓
   brightness by 0.01; on a bar ←/→ by 1° of hue or 0.01 of opacity; with ⇧,
   ten times that. Escape closes the panel (the popover rule). Each key is a
   write.
6. **The hex field** accepts `#RRGGBB`, `RRGGBB`, `#RGB`, and with
   `supportsOpacity` also `#RRGGBBAA`; case-insensitive; on submit (Return) a
   valid string writes, an invalid one reverts the field to the current colour
   and writes nothing. It shows `#RRGGBB` (`#RRGGBBAA` when opacity < 1 and
   `supportsOpacity`), uppercase.
7. **Accessibility**: the square is a group labelled "Saturation and
   brightness" whose two children are adjustable `.slider` nodes
   ("Saturation", "Brightness", values in percent); the bars are `.slider`
   nodes ("Hue" in degrees, "Opacity" in percent); increment/decrement step as
   item 5. The field is the existing `.textField`.

**Cost if wrong.** A look reviewers dislike is a human-check finding and a
re-draw, no API change.

## LK-E — `ProgressView`: spellings, sizes, values, labels

**Ruling.**

1. **Spellings** (**amended by `LK-P`**: `ProgressView<Label,
   CurrentValueLabel>`, `Element, StyledElement`, one `Box`): `ProgressView()`; `ProgressView(_ title: String)`;
   `ProgressView<V: BinaryFloatingPoint>(value: V?, total: V = 1.0)`;
   `ProgressView(_ title: String, value: V?, total: V = 1.0)`;
   `ProgressView(value:total:label:currentValueLabel:)` with element-builder
   labels; `.progressViewStyle(_:)` over `ProgressViewStyle` with `.automatic`,
   `.linear`, `.circular` (written on the view or a container, innermost wins —
   `MD-B`'s `textFieldStyle` precedent).
2. **What draws** (probe `V7`, `V8`): `.automatic` with no value is the
   **spinner**; with a value it is the **linear bar**. `.linear` with no value
   is an indeterminate bar; `.circular` with a value is a determinate ring.
   **A value below 0, or a total ≤ 0, is indeterminate** (`V8`: `value: -1` and
   `total: 0` both read `indeterminate=true`, `AXBusyIndicator`); a value above
   the total is drawn full (`V8`: 1.5/1 → 1.0). A non-finite value or total is
   indeterminate (MetalUI's rule; never a trap, nothing non-finite reaches a
   node).
3. **Sizes** (`V0`–`V6`, `V12`): spinner **32×32**, `.small` 16×16, `.mini`
   10×10, `.large` 32×32 (`.extraLarge` as `.large`); linear bar **greedy on
   the width** — the proposed width taken whole, infinity at an infinite offer
   (`PE-D`'s rule, as `Slider`), **0 at `nil`** (`V3` fitting `0x20`) — and
   **20 tall** (12 at `.small` and `.mini`, 20 at `.large`); circular as the
   spinner. With a title, a linear bar stacks the title **above** the bar with
   no gap (`V4`: 36 = 16 + 20) and a current-value label **below** in the
   caption font, secondary colour, no gap (`V4`: 50 = 16 + 20 + 14); a spinner
   stacks its title **below**, centred, 4 points apart (`V1`: 48×52 = 32 + 4 +
   16 under a 48-wide label). Leading-aligned for the bar.
4. **The bar** draws an 8-point track (`.separator`, radius 4) centred in its
   20-point box and the fraction filled in the control accent from
   `controlActiveState` (`ControlLook.swift`), as `Slider` (`V14` read an
   8-point bar in its 20-point frame; the colours are a look — human check).
5. **Accessibility** (`V7`, `V8`): a determinate view is
   **`.progressIndicator`** with the **fraction 0…1** as its value (`5/10` reads
   `0.5`) and the title as its label; an indeterminate one is
   **`.busyIndicator`** with no value. Both new roles are `LK-G`.

**Cost if wrong.** Sizes are pinned literals from `V0`–`V12`; a later probe
that disagrees reddens a named test.

## LK-F — `ProgressView` animation: the frame clock, 24 steps per 0.8 s, Reduce Motion keeps it

**Ruling.**

1. The spinner draws 12 spokes and advances in **24 discrete steps per 0.8 s**
   (`V13`: AppKit's spinner is a `CAKeyframeAnimation` of `contentsRect`, 24
   values, `discrete`, duration 0.8, repeating). The step index is
   `floor((t mod 0.8) / 0.8 × 24)` of the frame timestamp; the spoke look is a
   human check.
2. The indeterminate bar moves a 30%-wide segment across the track and back
   every 1.6 s (unmeasured period: `V8`'s `overallIndeterminateAnimation` was
   not timed — a look, human check).
3. Both call **`Frame.noteActiveAnimation()`** while painted (never
   `requestAnotherFrame()`, never both — `AN-`); a hidden, zero-size, clipped
   or fully transparent view requests nothing (the `GPUSurface` precedent). A
   determinate view never animates (a value change snaps; SwiftUI's
   `NSProgressIndicator` animates its own fill change — unmeasured, a human
   check, not a divergence).
4. **Reduce Motion does not stop it** (`V10`: with NSWorkspace's Reduce Motion
   getter swizzled to `true` and the change notification posted, the spinner
   still runs `CUIIndeterminateProgressAnimation`; the control after the
   swizzle is undone reads the same). Consistent with `AN-`'s "Reduce Motion
   changes only transitions".
5. Tests drive `simulateTick(timestamp:)` and read the painted spoke phase and
   `hasActiveAnimations`; nothing sleeps.

## LK-G — Three accessibility roles, on both bridges

**Ruling.** `AccessibilityRole` gains **`.progressIndicator`** (AppKit
`.progressIndicator`, AccessKit `PROGRESS_INDICATOR` with a numeric value
0…1), **`.busyIndicator`** (AppKit `.busyIndicator`, AccessKit
`PROGRESS_INDICATOR` with no numeric value — `accesskit.h` 0.23 has no busy
role), and **`.colorWell`** (AppKit `.colorWell`, AccessKit `COLOR_WELL`).
Each gets a row on both bridges (the `Mirror` count is unchanged: roles are
cases, not fields). This **names the accessibility area** of the brief's
must-not-move list: additive, no existing node changes role. A new case on a
public enum crossing a module boundary: `swift package clean` before the next
measured run (CLAUDE.md). Migration note: an exhaustive `switch` over
`AccessibilityRole` outside the package gains three cases.

## LK-H — `keyframeAnimator`, not `phaseAnimator`

**Ruling.** Build `keyframeAnimator`/`KeyframeAnimator`/`KeyframeTimeline`;
defer `phaseAnimator` (`LK-A`).

**Reasoning.** The smaller *honest* surface is the keyframe one, though it has
more types:

- A keyframe timeline is a **pure function of time** (`KeyframeTimeline.value(
  time:)`), measurable to three places without a window (`K1`–`K9`), so every
  rule is pinned by SwiftUI's own numbers and every test is arithmetic plus
  `simulateTick`. It needs from the animation system only the frame clock and
  `noteActiveAnimation()` — nothing in the must-not-move animation area moves.
- A phase animator advances "when the phase's animation completes": for a
  spring that is SwiftUI's logical-completion rule, which no probe has
  measured, and it would need a completion signal from MetalUI's transaction
  machinery (none exists) for whatever modifiers the content animates — new
  plumbing in the area the brief freezes.

MetalCreator's refused-wire shake is a keyframe sequence (`M5-i`); the
configurator asks for neither.

**Cost if wrong.** A phase animator added later is additive.

## LK-I — Keyframe semantics (timeline and animator)

**Ruling.** The timeline (probe `K`):

1. **Tracks**: `KeyframeTrack(_ keyPath: WritableKeyPath<Root, Value> = \.self)
   { … }`; several tracks in one `KeyframesBuilder`; the timeline's duration
   is the longest track's; a shorter track holds its last value (`K6`); a field
   no track names keeps the initial value (`K7`).
2. **Before 0** a track reads the initial value; **after its end** its last
   value (`K1`); `value(progress:)` is `value(time: clamp(progress, 0, 1) ×
   duration)` (`K9`).
3. **`LinearKeyframe(_ to:, duration:, timingCurve: UnitCurve = .linear)`**:
   from the previous value along the curve (`K2`: `.easeInOut` at 0.125 of the
   way reads 0.311 of 10). `UnitCurve` offers `.linear`, `.easeIn`, `.easeOut`,
   `.easeInOut`, `.bezier(startControlPoint:endControlPoint:)`, mapped onto
   MetalUI's existing `Animation` curves (the lane pins `K2`'s values).
4. **`CubicKeyframe(_ to:, duration:, startVelocity: Value? = nil, endVelocity:
   Value? = nil)`**: a cubic Hermite over the segment with tangents = velocity
   (per second) × segment duration. An explicit velocity wins (`K3e`: 50/s over
   0.4 s). Otherwise at a keyframe **between two cubic segments** the velocity
   is the finite difference `(next − previous) / (t_next − t_previous)` (`K3f`
   equal: 15 per 0.2 s; `K3g` unequal: 75/s over 0.1 s and 0.3 s); **at a
   boundary with a non-cubic segment** it is that segment's velocity at the
   boundary (`K3d`: 10 from the linear before, 5 from the linear after; `K3h`:
   0 from a hold); **at the track's start or end** 0 (`K3`, `K3b`
   smoothstep).
5. **`SpringKeyframe(_ to:, duration: TimeInterval, spring: Spring = Spring(),
   startVelocity: Value? = nil)`** — **`duration:` required** (divergence 168:
   SwiftUI's optional `duration` defaults to a settling length this design
   could not fit — `K4b` timeline 1.273 s for `Spring(duration: 0.4, bounce:
   0.3)` while its `settlingDuration` reads 0.854, `K4d`). The spring runs from
   the previous value **with the incoming velocity** (`K4e`: a linear at 50/s
   into a spring reads 9.280 at 0.05 s) and **stops at the keyframe's
   duration, holding the value reached** (`K4`: 9.864 from 0.4 s on, never
   10); a following keyframe starts from that value (`K4c`). `Spring` is
   SwiftUI's `Spring(duration: 0.5, bounce: 0)` initialiser and nothing else;
   its values are MetalUI's `Animation.springValue` (the lane pins `K4`, `K4d`
   at t = 0.1 within 0.005).
6. **`MoveKeyframe(_ to:)`** jumps at its time; the next keyframe starts from
   it (`K5`).
7. **A zero-duration keyframe** reads its target at its own time (divergence
   171: SwiftUI's timeline reads `nan` there, `K8`; MetalUI stores nothing
   non-finite).
8. **Values**: a track's `Value` conforms to **`VectorArithmetic`** (declared
   by MetalUI with SwiftUI's requirements: `AdditiveArithmetic`, `scale(by:)`,
   `magnitudeSquared`; `Double`, `Float`, `CGFloat` where available, and
   `Angle` conform). SwiftUI constrains `Value: Animatable`; every `Double`/
   `CGFloat`/`Float` track compiles the same (divergence 169 records the
   constraint and that the content closure receives the element itself, not a
   `PlaceholderContentView`).

The animator (probe `K10`–`K14`):

9. `.keyframeAnimator(initialValue:trigger:content:keyframes:)` and
   `.keyframeAnimator(initialValue:repeating:content:keyframes:)` on every
   `ElementGroup` (proposal content stays proposal), and `KeyframeAnimator(
   initialValue:trigger:content:keyframes:)`. One **transparent scope**
   (no node, no id level), its state in the window's `AnimationStore` keyed
   `$keyframes<depth>` by position — **never a `StateTable` slot** (the seven
   slots unmoved, `LC-`'s precedent).
10. **Appear**: `content` receives `initialValue`; `keyframes` is not called
    (`K10`). **A trigger change from rest** calls `keyframes(initialValue)` and
    runs from `initialValue` — even after a completed run left the content at
    its end value (`K11`, `K12`: start 0, the content jumps 20 → 0). **A
    trigger change mid-run** calls `keyframes(current value)` and runs from
    there (`K13`: start ≈ 5). **At the end** the content holds the timeline's
    end value until the next trigger.
11. **Repeating** calls `keyframes(initialValue)` once and loops the timeline
    from 0 (`K14`).
12. While running the scope calls `noteActiveAnimation()`; at rest nothing.
    The trigger is compared with `==` from input-time state, read during the
    build; the store write is the `AnimationStore`'s, never a phase-time
    `@State` write.

**Cost if wrong.** Each rule is a literal from `K`; a future SwiftUI that
changes one reddens a named test.

## LK-J — Gradients: rasterized on the CPU through the image path, Oklab, with a strip fast path

**Ruling.**

1. **Types**: `Gradient` (`Stop(color:location:)`, `init(colors:)`,
   `init(stops:)`), `LinearGradient(gradient:/colors:/stops:, startPoint:,
   endPoint:)`, `RadialGradient(gradient:/colors:/stops:, center:,
   startRadius:, endRadius:)`. Both gradients are **views** — greedy leaves,
   ideal 10×10 like a shape (`G10`: own 300×120, fitting 10×10) — and fills:
   `Shape.fill(_:)`, `Shape.stroke(_:lineWidth:)`, `Shape.stroke(_:style:)`,
   `.background(_:)` on both vocabularies and `.background(_:in:)` on the
   proposal one.
2. **Geometry** (probe `G`): unit points map to the filled rectangle; the
   linear parameter is the projection onto start→end **in points** (isolines
   perpendicular in point space — `G3`: t(100,0) reads 0.40's grey, t(0,50)
   0.10's); radial distance is **circular in points** (`R2`); sampled at
   **pixel centres** (`G1`: y0 reads t = 0.5/101); **padded** beyond the ends
   (`G7`, `R1`); stops **sorted by location** (`G4b`), equal locations a hard
   edge (`G4c`); **start == end draws the last colour** (`G6`).
3. **Colour**: interpolated in **premultiplied Oklab** (`G11`: red→blue midpoint
   (140, 83, 162), neither the gamma mix (128, 0, 128) nor the linear-light one;
   `G2`: black→white midpoint 99 = Oklab L 0.5; `G5`: clear-red→blue is blue at
   half alpha). A 1024-entry table per gradient value (0.05 ms;
   `gradient-raster-cost.swift` reproduces (140, 83, 162)).
4. **How it draws — CPU, through the image path, no new primitive**: a gradient
   fill travels the paint scopes as a vector (a new `CapturedPrimitive` kind,
   the `.path` precedent, `GX-B`) and rasterizes at `insertIntoScene` into an
   `ImageTexture` cached by value in the window's `RasterCache` (a key missing
   a field draws a stale raster: the key carries the stops, points, geometry,
   transform and placement). **No shader changes on either renderer**, so
   `TE-AD`'s identical-landing rule holds by construction; the SDL
   replay-parity harness sees images, which it already compares.
5. **The strip fast path**: an axis-aligned linear gradient on an untransformed
   (or translation-only) **rectangle or rounded rectangle wholly inside its
   clip** draws a **1-pixel-thick strip** texture (length = the device extent
   along the axis) stretched by the image pipeline with its linear filter,
   corner radii as the image's mask radii. Everything else (diagonal, radial,
   ellipse, path, stroke, rotated, partly clipped) rasterizes in full:
   coverage × colour.
6. **Measured** (`gradient-raster-cost.swift`, M1 Max, `-O`): a full 3200×2000
   linear raster is **8.8 ms** of colour plus **8.9 ms** of coverage and a 25.6
   MB upload per miss; the strip is **0.005 ms**. A cached raster costs nothing
   per frame, so static gradients of any shape are fine; a window-size
   background resized every frame would blow the frame budget without the
   strip, and MetalCreator's window background (M5-d) is exactly the strip's
   case. gpui draws gradients in its quad shader (two stops, sRGB or Oklab) — a
   comparison: MetalUI could add a shader primitive later if a measured
   animated large non-axis gradient needs it (owner none).
7. **Gradients do not animate**: a change snaps (SwiftUI's answer under a
   transaction is unmeasured — recorded in the record's inert list, not as a
   divergence). `AngularGradient`, `EllipticalGradient`,
   `Gradient.colorSpace(_:)` and `.foregroundStyle(gradient)` on text are not
   offered (`LK-A`).
8. **Legacy `.background(gradient)`** stores the fill on `Decoration` beside
   `background: Color?` (an internal stored property on a public struct:
   `swift package clean` before the next measured run); it paints through
   `paintDecoration` (`DN-X`), under the corner radius and border, and is not
   animated (`animatedBackground` keeps the colour path only).

**Cost if wrong.** If the CPU route proves too slow somewhere the strip does
not reach, the shader primitive is the follow-up; the API does not move.

## LK-K — `.blur(radius:)`: per leaf, sigma = radius, the shadow pipeline in colour

**Ruling.**

1. **Spelling**: `blur(radius: Pixels)` on `ProposalElementGroup` (one
   `LayoutModifier` layer, `.blur(radius:)`, one identity level, `MC-C`) and on
   `StyledElement` (returning `Self`, joining `Decoration.renderEffects` in
   written order, around the whole element — divergence 108's rule, as
   `.shadow`).
2. **Per leaf** (probe `B2`/`B2c`: a blue square over an equal red one, blurred
   together, reads **identically** to each blurred alone — red bleeds at the
   edge, so SwiftUI does not composite first). Each leaf inside (a text draw
   is one leaf, `beginLeafGroup`/`endLeafGroup`) is replaced by its blurred
   image. This is `GX-J`'s shadow pipeline with colour: the leaf rasterized in
   device pixels under the composed transform as **four premultiplied channels**
   (each an `AlphaMask`), each blurred by the existing `BoxBlur` (three box
   passes, divergence 105's approximation), recombined into one `ImageTexture`,
   cached in `RasterCache` by the leaf's key plus the radius.
3. **Sigma = radius** (`B1`: the profile fits a Gaussian of sigma 4.0 at
   radius 4 from four points; blurred in gamma space, as the shadow), the image
   grows by the blur's reach; a clip **outside** cuts it (`B5`), one inside
   shapes the leaf.
4. **Render only**: no layout change (`B4`: 50×20 stays 50×20), no hit-region
   change, nothing published.
5. **A GPU surface leaf** (`GPUSurface`/`MetalView`) cannot be read on the CPU:
   it is **drawn unblurred** (divergence 167; the shadow's quad rule,
   divergence 104, is the precedent for "a surface's pixels are on the GPU").
6. The radius animates (the shadow-radius precedent, `GX-J`). A radius ≤ 0
   draws the leaf unchanged; a non-finite one traps naming the modifier (the
   shadow's validation). `opaque:` is not offered (`LK-A`; `B3` recorded:
   SwiftUI's opaque blur clamps the edge and drops the fade).

## LK-L — Materials: a fitted flat tint now, backdrop blur deferred

**Ruling.**

1. **Spelling**: `Material` with `.ultraThinMaterial`, `.thinMaterial`,
   `.regularMaterial`, `.thickMaterial`, `.ultraThickMaterial`, `.bar`;
   `.background(_ material:)` on both vocabularies, `.background(_:in:)` on the
   proposal one, `Shape.fill(_ material:)`.
2. **What SwiftUI draws** (probe `M1`, `M5`): a **blurred backdrop** with a
   tint (over 10-point red/blue stripes every material reads nearly one
   colour, with green the stripes lack — a blur and a vibrancy lift), and over
   a **uniform** backdrop a flat tint per material and scheme.
3. **What MetalUI draws**: the flat tint only — a colour at an alpha, per
   material and scheme, **fitted from `M5`** (an ImageRenderer fit; a real
   window is unmeasured, `LK-O` item 2) so that over uniform white and
   black it reproduces SwiftUI's material within ±1 (alpha = 1 − (W − K)/255,
   grey = K / (alpha × 255)):

   | material | light: grey, alpha | dark: grey, alpha |
   |---|---|---|
   | ultraThin | 0.9250, 0.4706 | 0.2248, 0.5059 |
   | thin | 0.9145, 0.5961 | 0.2105, 0.5961 |
   | regular | 0.9121, 0.7137 | 0.2045, 0.6902 |
   | thick | 0.9052, 0.8275 | 0.2010, 0.7804 |
   | ultraThick | 0.8996, 0.9373 | 0.2000, 0.8627 |
   | bar | 1.0000, 0.8000 | 0.1779, 0.8157 |

   Over mid-grey it differs by up to 7 levels (light thick/ultraThick: SwiftUI
   lifts), over colour by much more (the blur). **Divergence 166**, a
   **renderer constraint** in the `TE-AD` sense — documented, never silent.
4. **Why the backdrop blur is deferred**: a backdrop is everything drawn
   beneath, in scene order. On the CPU (the `LK-K` compositor over every
   earlier primitive under the material) it cannot see a GPU surface — and
   MetalCreator's glass panels sit over its Metal viewport, the very case. On
   the GPU it needs the frame's pass split at each material (copy the target
   region, blur, resume), identically in `shaders.metal` and `replay.hlsl`, a
   non-`framebufferOnly` drawable on Metal and an intermediate render target on
   SDL (whose frames draw straight into the swapchain texture today) — a
   renderer milestone of its own. AppKit's `NSVisualEffectView` cannot sit
   inside the Metal layer's content. Owner: C10-c (`LK-A`).

**Cost if wrong.** Panels look flat (human check); the call sites do not move
when the backdrop lands.

## LK-M — Demos, pixels, human checks

**Ruling.** Lane 1 adds a `controlsLooksSection()` to `ControlsDemo.swift`
(slider editing log, two `ColorPicker`s, `supportsOpacity` on and off); lane 2 a
`progressSection()` there and a `keyframesSection()` to `LooksDemo.swift`; lane
3 a `gradientsBlurMaterialsSection()` to `LooksDemo.swift` — each in its own
function passed to the generic composer (Windows' 1 MB stack,
`everyProductionTreeBuildsOnAOneMegabyteThread`). None is in `demoContent()`,
`nativeLayoutPreviewContent()` or the chrome pair, so **the fourteen offscreen
images read 0 px** against `cd84b0c` (`compare.sh`), and
`DemoFrameDeterminismTests`' `Expected.swift` is unedited. The human checks the
spec lists (§7) are added to `docs/verification/human-checks.md` in the Record
phase.

## LK-N — Parallel branches: files this branch does not touch

**Ruling.** Off-limits (edited by `feat/input-apis`, record §81, or
`feat/rich-text`, record §83): `Gesture.swift`, `GestureModifiers.swift`,
`SpatialGestures.swift`, `ContextMenu.swift`, `MenuSession.swift`,
`Popover.swift`, `Tooltip.swift`, `InputEvent.swift`, `Platform.swift`,
`PointerStyle.swift`, `AppKitPlatform.swift`, `AppKitCursor.swift`,
`SDLPlatform.swift`, `SDLInputMapping.swift`, `SDLBridge.c/h`, `Fakes.swift`;
`Text.swift`, `TextModifiers.swift`, `TextStyleResolution.swift`,
`ProposalText.swift`, `Font.swift`, every `MetalUIText`/`MetalUIPortableText`/
`MetalUITextSystem`/`MetalUIHarfBuzz`/`MetalUIFreeType` file,
`AnimationTests.swift`, `DecorationPaintTests.swift`, `MenuPickerTests.swift`,
`TextCompileGuards.swift`. **One exception, named**: `Window.swift`, lines right after
`updatePointerState(event)` in the input hook, inside `dispatchValueTrack`, and
the close path (`LK-Q` item 3), away from every input-apis hunk. Merge hazards
in this branch's own test files: `LK-T`. Both branches append to `closeout-inventory-map.tsv` and
re-record `closeout-public-api.tsv`: the later merge re-records the census.
Divergence labels come from this branch's range **165–174**; the header's
next-label line is left to the merge.

## LK-O — Critic: the probe re-run, and what the material fit rests on

**Ruling.** The critic re-ran `swiftui-controls-looks.swift` (compiled form,
same screen state: `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`)
twice. **Run 2 is byte-identical to the recorded 160 lines** (after the
header's two-space indent); **run 1 differs on one line**, `M1 ImageRenderer
light regular`, by one level in two samples (blue stripe `(222, 136, 170)`
for the recorded `(223, …)`, edge `(224, …)` for `(225, …)`). Every other arm,
including `S`, `V`, `C`, `K`, `G` and `B`, reproduced both times;
`gradient-raster-cost.swift` reproduced its check line `(140, 83, 162)` and its
timings within 0.12 ms. Consequences:

1. **`M1` is not byte-stable** (SwiftUI's material blur over ImageRenderer
   varies by ±1); the header's "byte-identical" claim holds for the `M5` arms
   the fit uses, not for every line. Nothing pins `M1`; `M5`'s ±1 tolerance
   (`everyMaterialMatchesSwiftUIOverWhiteAndBlackM5`) already covers the
   instrument's spread.
2. **`M4` is a discarded instrument, not an answer.** `cacheDisplay` of a
   hosted window read the regular light material over the stripes as `(128,
   37, 34)` / `(28, 28, 127)` — the stripes stay apart (no blur) and the tint
   is dark — so `cacheDisplay` does not composite the material's backdrop (as
   `V14` read an inactive dark window). **The `LK-L` table is an
   ImageRenderer fit; whether SwiftUI in a real, key window draws the same
   tint over a uniform backdrop is unmeasured** — the Record phase adds it to
   human check 8, and a window capture (`docs/probes/window-capture/`) when
   the lock probe allows may replace the table. `LK-L` and divergence 166 say
   "fitted from ImageRenderer", not "SwiftUI's material".
3. `V1`'s fitting height reads 53 against an own 52: unexplained one point of
   SwiftUI's fitting answer; MetalUI pins the **own** size (48×52), as the spec
   does.

**Reasoning.** A ruling that cites a probe must survive a re-run; the one line
that did not is named rather than smoothed over, and the window arm the design
did not cite contradicts the instrument the fit came from — that is recorded,
not hidden.

## LK-P — Critic: `ColorPicker` and `ProgressView` take `Toggle`'s shape, one node each

**Ruling (amends `LK-C` item 1, `LK-E` item 1, `LK-A`'s deferral table, spec
§1 and §3.1–§3.2).**

1. **The defect.** The spec declared `public struct ColorPicker: Element` and
   `public struct ProgressView: Element` but built both as a `Component` whose
   body is a label and a control side by side. A `Component` is
   layout-transparent (`OM-D`): two top-level nodes become **two children of
   the caller's container**, so `VStack { ColorPicker("Tint", …) }` would stack
   the label above the well and `HStack(spacing: 20)` would space them 20, not
   8 — and a `Component` takes no `StyledElement` modifier (`.background`,
   `.padding` per member). A struct also cannot be a leaf in one initialiser
   and a `Component` in another.
2. **Final shapes** (the `Toggle<Label>` precedent, `Toggle.swift`: one
   `Element, StyledElement` over one `Box` holding the label and the control;
   SwiftUI's own types are generic over their labels):
   - `public struct ColorPicker<Label: ElementGroup>: Element, StyledElement` —
     `init(selection: Binding<Color>, supportsOpacity: Bool = true,
     @ElementBuilder label: () -> Label)` and, `where Label == Text`,
     `init(_ titleKey: String, selection: Binding<Color>, supportsOpacity:
     Bool = true)`. One `Box` (row, gap 8, cross-axis centred) over the label
     and the internal well leaf; an empty title drops the label **and** the gap.
     The label-view initialiser is **no longer deferred** (it was deferred for
     a reason that applies only to `CGColor` bindings, which stay deferred).
   - `public struct ProgressView<Label: ElementGroup, CurrentValueLabel:
     ElementGroup>: Element, StyledElement` — `init()` and `init(value:total:)`
     `where Label == EmptyGroup, CurrentValueLabel == EmptyGroup`;
     `init(_ title: String)` and `init(_ title: String, value:total:)` `where
     Label == Text, CurrentValueLabel == EmptyGroup`;
     `init(value:total:label:currentValueLabel:)` generic. One `Box` (column:
     title above with gap 0 and the caption current-value label below for the
     bar; the title below with gap 4 for the spinner) over an internal
     indicator leaf. No label: the leaf's box alone.
3. **The colour panel** stays an internal `Component`, but its body is **one**
   container (a `Column`/`VStack`), because a popover's content is a
   presentation root that takes exactly one node (`Deferred`'s one child).
4. **New tests** (lane 1 / lane 2): `aColorPickerInAVStackKeepsItsLabelBesideTheWell`
   and `aColorPickerInAnHStackKeepsItsOwnEightPointGap` (mutation: make the
   body a `Component` of two top-level nodes); `aTitledProgressViewInAnHStackStacksItsTitleAbove`
   (same mutation); `aColorPickerTakesABackgroundAndPadding` (a compile guard,
   plain import: `ColorPicker("A", selection: $c).padding(4).background(.surface)`;
   mutation: drop the `StyledElement` conformance).

**Reasoning.** Every existing control (`Toggle`, `Picker`, `Stepper`,
`TextField`, `Slider`) is one `Element, StyledElement`; a composite control
that dissolves into its parent is a layout bug, not a style.

## LK-Q — Critic: a slider's edit ends at the top of the input hook, never in its own stage

**Ruling (amends `LK-B` items 5–6 and spec §3.1).**

1. **The defect.** The spec ended the edit in a new `.mouseUp` case of
   `dispatchValueTrack`. That stage runs after the drawn alert
   (`dispatchDrawnAlert`, modal: it takes every pointer event while up), the
   drag session, the menu session and the popovers' stage — each can claim
   the release first. An `.alert` presented by a value change mid-drag (an
   SDL window draws it, `SV-AK`) would swallow the release and **leave the
   edit open forever**, breaking `LK-B` item 5's invariant.
2. **Where it ends**: `Window` keeps `editingTrack: (id, end)` (set by
   `dispatchValueTrack`'s `.mouseDown` after `onEditingChanged(true)` and
   before the write). The `.mouseUp` end runs **immediately after
   `updatePointerState(event)` at the top of the `onInput` hook**, before the
   services switch and every claiming stage, under `StateDispatch` to the
   stored id, and **claims nothing** (the release continues to the stages
   exactly as today: click dispatch and the gesture arena are unchanged). A
   `.mouseDown` that finds an `editingTrack` still open (a lost release) ends
   it first. The close path ends it as before. **No `pressedBefore:`
   argument**; `dispatchValueTrack`'s signature and call site do not change.
3. **Merge footing.** The new lines sit right after `self.updatePointerState(event)`
   (`Window.swift` line 856 at `cd84b0c`) and inside `dispatchValueTrack`
   (line 2500); `feat/input-apis`' nearest hunks start at old line 875 (the
   hover case list) and 926 (its pinch/button stage). The edit does **not**
   touch `updatePointerState` (input-apis' hunk at 1960 is adjacent to its
   `.mouseUp` case) nor the stage list.
4. **New tests** (lane 1): `aReleaseClaimedByTheDrawnAlertStillEndsTheEdit`
   (a fake window answering `presentAlert` `false`, an `.alert` raised by the
   first write; mutation: move the end into `dispatchValueTrack`'s
   `.mouseUp` case — **the spec's own spelling**, which this test must redden);
   `aSecondPressWithoutAReleaseEndsTheFirstEdit` (two `.mouseDown`s; mutation:
   overwrite `editingTrack` without ending it); `theReleaseIsNotClaimedByTheSlider`
   (an `onTapGesture` ancestor's arena still sees the release exactly as at
   `cd84b0c`; mutation: return `true` from the end).

## LK-R — Critic: where the gradient and material overloads live, and what they return

**Ruling (amends `LK-J` item 1, `LK-L` item 1, spec §1 lane 3).**

1. **The defect.** The spec declared `ProposalElementGroup.background(_:
   LinearGradient)` returning `ModifiedContent<ProposalBase, LayoutModifier>`
   while listing only one new `LayoutModifier` case (`blur`) — there is no
   case for it to wrap; and it put `background(_:in:)` on the proposal
   vocabulary only, where the existing colour spelling is on **`ElementGroup`**
   (`ClipShape.swift`, both vocabularies, `BackgroundModifier<Self,
   ShapeView<S>>`, probe O2). It also omitted `fill(_:style:)`, which
   `ShapeView.swift` offers for every colour (`fill(_ color:, style:
   FillStyle)`), so `Circle().fill(gradient, style: FillStyle(eoFill: true))`
   would not compile.
2. **Final spellings and types**:
   - `ElementGroup.background<S: Shape>(_: LinearGradient | RadialGradient |
     Material, in: S) -> BackgroundModifier<Self, ShapeView<S>>` — the same
     as `background { shape.fill(style) }`, beside the colour pair.
   - `ProposalElementGroup.background(_: LinearGradient | RadialGradient) ->
     BackgroundModifier<Self, LinearGradient | RadialGradient>` — the gradient
     **view** as the background attachment (`MC-P`'s `.child(of:at: -1)`), a
     greedy view proposed the primary's size, so it fills the bounds (`G9`).
     **No `LayoutModifier` case for gradients.**
   - `ProposalElementGroup.background(_: Material) -> ModifiedContent<ProposalBase,
     LayoutModifier>` — the existing `.background(Color)` case with the
     material's `Color(light:dark:)` (`LK-L` item 3's table).
   - `StyledElement.background(_: LinearGradient | RadialGradient | Material) -> Self`
     as specified.
   - `Shape.fill(_:style:)` and `ShapeView.fill(_:)`/`fill(_:style:)` for both
     gradients and `Material`, beside the colour overloads; `stroke` as
     specified.
3. **`LayoutModifier.blur(radius:)`** is the one new public case; **migration
   note** (Record phase, `docs/migration.md`): an exhaustive `switch` over
   `LayoutModifier` outside the package gains a case, as `LK-G`'s roles do.
4. **Guard 3.T1 grows two lines**: `Circle().fill(LinearGradient(…), style:
   FillStyle(eoFill: true))` and `Text("x").background(.thinMaterial, in:
   Capsule())` in the legacy vocabulary (mutation: declare the `in:` overload
   on `ProposalElementGroup` only).

## LK-S — Critic: replay parity for CPU-made images, and a mutation that can redden

**Ruling (amends spec §3.3 "Replay parity", §4.3's last row, §5).**

1. **The defect.** The spec's parity mutation — "change the gradient table on
   one side only" — cannot redden: the table, the raster and the blur run once,
   on the CPU, in `MetalUI`, before the scene exists, so the recorded Metal
   reference and the SDL replay receive **the same texels**. `TE-AD` holds by
   construction (no shader line moves), and the parity arm proves only what the
   image path does with those texels.
2. **What the new fixture is for**: the **strip** (`LK-J` item 5) — a 1-texel
   texture stretched over a rect at **quarter-pixel device bounds** (as frame
   6's images are), with mask radii — is the one new way this branch uses the
   image pipeline. The recorder (`Experiments/SDLGPU/Sources/Replay/main.swift`,
   `--portable --record`) gains **frame 9** through `renderFrame`: a vertical
   strip-path rounded rect at fractional bounds, a horizontal one, a diagonal
   (full raster) rect, a radial circle and a blurred text leaf.
   `.github/workflows/sdl-gpu-linux.yml`'s two `--expect 8` become `--expect
   9` (the `PT-G` rule: a frame that stops being recorded fails). Both files
   join lane 3.
3. **Separating mutation**: `SDLBridge.c`'s image sampler `address_mode_v`
   set to `SDL_GPU_SAMPLERADDRESSMODE_REPEAT` — the strip's end rows sample
   across the wrap — must fail `PortableReplay` on frame 9 (and frames 0–8
   must not be what fails, or the fixture adds nothing). The lane records the
   failing frame and Δ; if the mutant passes, the instrument is broken — the
   lane moves the strip's bounds until it reddens or rules the frame
   redundant by name. (`SDLBridge.c` is `feat/input-apis`' file: the
   mutation is applied in an isolated copy and never committed.)
4. **Where it runs**: `PortableReplay` needs a GPU. Locally on macOS
   (`--driver metal`, SDL GPU over Metal, record §28's method); CI replays on
   Mesa llvmpipe and Windows D3D12 on push. **The Linux image of the brief
   (`SDL_VIDEO_DRIVER=offscreen`) builds and tests `Backends/SDL`; it does not
   replay** — the spec's "replayed on SDL in the Linux image" is corrected.

## LK-T — Critic: merge hazards and a modifier-order limit the design left unsaid

**Ruling (amends `LK-N`, `LK-I` item 9).**

1. **No new `PlatformWindow` conformer in this branch's test files.**
   `feat/input-apis` adds a defaultless `setPointerStyle(_:)` to
   `PlatformWindow` and edits every compile-guard file that declares a
   conformer (`ToolbarCompileGuards.swift` and six others, one line each). A
   new guard file here (`ColorPickerCompileGuards`, `ProgressViewCompileGuards`,
   `KeyframeCompileGuards`, `LooksCompileGuards`) uses the shared fakes or
   none; if one must declare a conformer, the record names it so the merge adds
   the line.
2. **`.keyframeAnimator` returns a transparent scope**, so — like
   `LifecycleScope` and `PresentationScope` — a legacy decoration written
   after it does not compile (divergence 120's rule, extended by name in the
   Record phase; no new label). MetalCreator's shake writes its `.offset`
   inside the content closure, which is SwiftUI's spelling anyway; the guard
   `keyframeAnimatorTypechecksWithSwiftUIsCallShape` adds a negative arm
   (`.keyframeAnimator(…).padding(4)` on a legacy `Box` does not compile;
   mutation: return `Self`).
3. **`ControlsDemo.swift` and `LooksDemo.swift` are shared by append**: lanes 1
   and 2 each append a function to the first, lanes 2 and 3 to the second; no
   lane edits another lane's function. Sequential lanes make this safe; it is
   named because the spec's table called the lanes disjoint.
4. **`KeyframeAnimator`'s initialisers are SwiftUI's**: `init(initialValue:
   trigger:content: @escaping (Value) -> Content, keyframes:)` and
   `init(initialValue:repeating:content:keyframes:)` (`repeating: Bool =
   true`) — the view form's content takes the value only; the modifier form's
   takes `(Self, Value)` (divergence 169).

## LK-U — Lane 1: what landing the controls changed in the design

**Final spellings (lane 1, landed)** — MetalCreator and the configurator swap
their stopgaps to exactly these:

- **M5-a**: `Slider(value: $v, in: 0...1, onEditingChanged: { editing in … })`
  and `Slider(value: $v, in: 0...10, step: 1, onEditingChanged: { … })`; the
  trailing closure `Slider(value: $v) { editing in … }` compiles too (guard
  `theSliderInitialisersKeepTheirSwiftUISpellings`).
- **M6-f, MG-7**: `ColorPicker("Tint", selection: $color, supportsOpacity: true)`
  and `ColorPicker(selection: $color, supportsOpacity: false) { Text("Tint") }`,
  over MetalUI's `Color`; it takes `.padding`/`.background` like any control
  (guard `aColorPickerTakesABackgroundAndPadding`).

**Ruling (amends `LK-Q` item 2, `LK-D` item 7, `LK-G`, spec §2's file table
and §4.1).**

1. **The edit ends at the top of the input hook on a press too.** The end
   (`Window.endSliderEdit()`, right after `updatePointerState(event)`) runs for
   `.mouseUp` **and** `.mouseDown`, so a lost release is ended by the next
   press whatever stage claims that press — not only a press that reaches
   `dispatchValueTrack`. The close path calls the same method first thing in
   `runDisappearancesForClose()` (the caller `App.onClose` is unchanged).
   `dispatchValueTrack`'s signature and call site are unchanged.
2. **One closure, so `Handlers` keeps its size.** `ValueTrackTarget`'s `write`
   became `edit: (Event) -> Void` with `.begin`, `.write(Double)` and `.end`;
   a second stored closure grew `MemoryLayout<Handlers>` by 16 bytes and
   reddened `theNewDeclarationsCostHandlersAtMostOnePointer` and
   `handlersGainsOneReferenceMember` (measured on the first green suite).
   `Handlers` keeps seventeen members and its size.
3. **The release observer.** `LK-Q` item 4's `theReleaseIsNotClaimedByTheSlider`
   named an `onTapGesture` ancestor as the observer; it cannot see the release
   on either side — the slider's own stage claims the press, so no arena forms
   at `cd84b0c` either. The test observes the window's own `onInput` (which an
   unclaimed release reaches) and the hook's answer (`false`).
4. **The well's role is a hint** (`AXNode.colorWellHint`, internal, stripped
   in `Frame.registerHandlers` as `popUpButtonHint` is, mapped in
   `AccessibilityTreeBuilder.publishedRole` from `.button`), the `SV-S`
   precedent — no public `AXRole` case. The progress view's two roles reach
   the element side in lane 2 by the same means.
5. **The square's two accessibility children** (`LK-D` item 7) are
   registrations under positional child ids of the square
   (`GlobalElementID.child(of: square, at: 0/1)`), its top and bottom halves,
   through `registerAndScope` inside the square's own scope: each an
   adjustable `.slider` with no hitbox and no focus stop, so Tab stops once at
   the square and a client adjusts each. No named id is minted (no
   `noteNamed`).
6. **Files beyond the spec's table**, each a one- or few-line edit:
   `AXNode.swift`, `Frame.swift`, `AccessibilityTreeBuilder.swift` (item 4),
   `LayoutAuthority.swift` (a `LoweringSite.colorPicker` for the well and the
   panel's planes, lowered as `slider` is), and
   `Backends/SDL/Sources/MetalUISDL/AccessKitAdapter.swift` (the two
   snapshot roles' C codes, explicit `UInt8` conversion; `Node.numericRange`
   sending `min_numeric_value` 0 and `max_numeric_value` 1). None is on
   `LK-N`'s off-limits list.
7. **Tests the spec named differently**: `escapeClosesThePanel`'s mutation
   ("swallow Escape in the panel") cannot redden — the popovers' stage
   precedes every key handler — so its separating mutation is the well's
   popover binding ignoring `false`. The D2 rule ("a new handler-registering
   site gains an arm") is met by `aDisabledColorPickerOpensNothing`: the D2
   guard's helper counts logged click handlers, and the well's open logs
   nothing a fixture can count. `aTokenSelectionOpensAtItsResolvedValueAndTheFirstEditWritesALiteral`
   holds two arms, a dynamic colour in a dark window (the scheme's separating
   arm) and `.accent` in a dark window.
8. **The demo's slider starts at 0.65** so it never publishes a value the
   controls slider's VoiceOver steps read (`theVoiceOverScriptQuotesThePublishedTree`
   matched two `0.5` sliders on the first green suite).

## LK-V — Lane 2: what landing the progress view and keyframes changed in the design

**Final spellings (lane 2, landed)** — MetalCreator swaps its stopgaps to
exactly these:

- **M5-j** (`StatusBadge.text(for:)`'s `◌`): `ProgressView()` (the spinner),
  `ProgressView().controlSize(.small)` (16 points), `ProgressView(value: x,
  total: 1)` (the bar), `ProgressView("Exporting", value: x)`,
  `ProgressView("Loading")`, `ProgressView(value: x) { Text("Export") }
  currentValueLabel: { Text("30%") }`, `.progressViewStyle(.linear /
  .circular / .automatic)` on the view or a container; it takes `.padding`/
  `.background` like any control (guard `progressViewSpellingsTypecheckFromAnExternalModule`).
- **M5-i** (the refused-wire spring-back): `.keyframeAnimator(initialValue:
  0.0, trigger: refusals) { content, x in content.offset(x: Pixels(Float(x)))
  } keyframes: { _ in KeyframeTrack { LinearKeyframe(6, duration: 0.05);
  LinearKeyframe(-6, duration: 0.1); LinearKeyframe(0, duration: 0.05) } }`;
  also `.keyframeAnimator(initialValue:repeating:content:keyframes:)`,
  `KeyframeAnimator(initialValue:trigger:content:keyframes:)` (content takes the
  value only) and `KeyframeTimeline(initialValue:content:)` with
  `value(time:)`/`value(progress:)`/`duration` (guard
  `keyframeAnimatorTypechecksWithSwiftUIsCallShape`).

**Ruling (amends `LK-E` items 1–2, `LK-I` items 1, 9, `LK-T` item 2, spec §1,
§2's file table, §3.2 and §6).**

1. **A value initialiser always draws a bar.** `.automatic` draws the spinner
   for `ProgressView()` and `ProgressView(_:)` only; every value initialiser
   draws a bar, an **indeterminate** one when the value is `nil`, negative,
   non-finite or the total is not positive (probe `V6`: `ProgressView(value:
   nil)` is `own 300x20 fitting 0x20`, a bar — `LK-E` item 2 read "with no
   value is the spinner"). Its node is the busy indicator either way (`V8`).
2. **The carriers have no public initialiser** (`MC-G`'s shape, as `LK-I`
   item 8's "internal requirements" cannot be spelled: a public protocol's
   requirement is public). `KeyframeTrackContent`'s one requirement returns a
   `KeyframeTrackContentGroup<Value>`, `Keyframes`' a `KeyframesGroup<Value>`;
   both are public structs with internal initialisers and storage, and are what
   the two result builders build. A conformance that **forwards** to MetalUI's
   keyframes compiles (it is composition, the guard's positive control); one
   that builds its own does not. The guard's mutation is the initialisers'
   access, not "make `_segments` public".
3. **`KeyframeTrack<Root, TrackValue, Content>`**: its second generic parameter
   is `TrackValue`, not SwiftUI's `Value`. `Keyframes`' associated type is named
   `Value` (the root, so `KeyframesBuilder<Value>` relates tracks to the
   timeline) and a generic parameter of the same name would bind it to the
   track's value. No call site spells the parameter; recorded, not a
   divergence.
4. **The negative arm of the call-shape guard is `.onClick {}`** after the
   animator — divergence 120's own guards' spelling — not `.padding(4)`
   (`LK-T` item 2): `.padding` is spelled on `ElementGroup` too and is not the
   rule's separating decoration. The animator returns the concrete public type
   `KeyframeAnimator<Value, Content, K>` (the view type), conditionally a
   `ProposalElementGroup`, so proposal content stays proposal content with one
   overload pair instead of the spec's `some ElementGroup` plus a proposal twin.
5. **The keyframe depth counter lives in `AnimationStore`** (`keyframeDepth`,
   `withKeyframeScope`), not `Frame` (lane 3's file): the records are that
   store's, keyed `$keyframes<depth>` under `.child(of: parent, at: cursor)`.
6. **The progress roles reach the element side by a hint**, `LK-U` item 4's
   means: `AXNode.progressHint` (`.determinate` / `.busy`, internal), stripped
   in `Frame.registerHandlers` as `popoverHint` is and, like it, enough for a
   record; `AccessibilityTreeBuilder.publishedRole` maps a `.group` with the
   hint. The indicator leaf carries the view's one node: the fraction as its
   value (`ValueStepping.accessibilityText`: `5/10` → `0.5`), the **string
   title as its label** with the title `Text` itself `accessibilityHidden` — a
   label *view* (`init(value:total:label:currentValueLabel:)`) publishes as its
   own content (SwiftUI's fold of a label view is unprobed).
7. **Unmeasured choices, each a look or a literal no probe contradicts**: a
   `.small`/`.mini` bar's track is 6 points (8 at 20 tall); the spinner's spokes
   are 2 points at 32 (side / 16), `.textPrimary` at 0.7 × an opacity falling 1
   → 0.25 behind the head, drawn as twelve stroked `Path`s per step through
   `pass.drawPath`; the ring is a `side / 8` stroke, the arc a 64-segment
   polyline; a cubic keyframe before a spring with no start velocity arrives at
   velocity 0 (the spring then starts at 0 — the cycle the rule otherwise has).
8. **Files beyond the spec's table**, each a one- or few-line edit:
   `AXNode.swift`, `Frame.swift` (two lines in `registerHandlers`),
   `AccessibilityTreeBuilder.swift` (item 6), `LayoutAuthority.swift`
   (`LoweringSite.progressView`, the indicator leaf's site — its style is never
   a caller's, so no diagnostics arm can reach it, as `colorPicker`'s cannot),
   and `LooksDemo.swift`'s `looksDemoContent()` call line (item 9).
9. **Demos.** `progressSection()` is appended to `ControlsDemo.swift` and
   called from `controlsDemoContent()`; `keyframesSection()` is appended to
   `LooksDemo.swift` and reached through a new `looksColourAndKeyframes()`
   composer above the colour section. Passed to `looksRoot` as three
   temporaries (the two sections and a stacking helper) the looks tree
   overflowed the 1 MB thread (`everyProductionTreeBuildsOnAOneMegabyteThread`,
   `.signal(SIGBUS)`, measured; with the composer in its own frame it passes).
   The shake is triggered by an `.onTapGesture` on a text, not a `Button`:
   `theLooksDemoDrawsEverySurfaceItsHumanChecksName` pins the demo's click
   targets at fourteen and `theLooksColourSectionPaintsLiteralDynamicAndPaletteColours`
   presses the bottom-most as the scheme toggle (a `Button` reddened both,
   measured), and the row sits above the colour section for the same reason.


## LK-W — Lane 3: what landing gradients, blur and materials changed in the design

**Final spellings (lane 3, landed)** — MetalCreator and the configurator swap
their stopgaps to exactly these:

- **M5-d** (the solid window background): `LinearGradient(colors: [a, b],
  startPoint: .top, endPoint: .bottom)` as `.background(_:)` on a proposal view
  (the gradient view as the background attachment) or a legacy `StyledElement`
  (a `Decoration` fill), `Shape.fill(_:)` / `fill(_:style:)` /
  `stroke(_:lineWidth:)` / `stroke(_:style:)`, and `.background(gradient, in:
  shape)`; also `LinearGradient(stops:startPoint:endPoint:)`,
  `LinearGradient(gradient:startPoint:endPoint:)`, `Gradient(colors:)`,
  `Gradient(stops: [.init(color:location:)])` and
  `RadialGradient(colors:center:startRadius:endRadius:)` (and `gradient:`/`stops:`).
  A gradient is a view too: `LinearGradient(…).frame(…)`.
- **M5-c** (blur): `.blur(radius: Pixels(6))` on both vocabularies.
- **M5-c, MG-9** (materials): `.background(.ultraThinMaterial)` …
  `.ultraThickMaterial`, `.bar`; `.background(.regularMaterial, in: Capsule())`;
  `Rectangle().fill(.thinMaterial)` — **a fitted flat tint with no backdrop
  blur** (divergence 166).

Guard 3.T1 (`materialSpellingsResolveWithoutAmbiguity`) typechecks them all
beside `.background(.surface)` and `.fill(.red)` from a plain import.

**Ruling (amends `LK-J` items 4–5 and 8, `LK-K` item 2, `LK-S` item 2, spec
§2's file table, §3.3, §4.3 and §6).**

1. **"Frame 9" is the ninth frame, index 8.** The recorder's frames are
   numbered from 0 (frame 7 is the transforms frame), so `LK-S`'s frame 9 is
   `looksFrame` at index 8; `--expect 9` counts it. `Experiments/SDLGPU/README.md`
   says so.
2. **G1's red end takes ±3, measured.** The probe's own premultiplied-Oklab
   arithmetic (`gradient-raster-cost.swift`), evaluated exactly, reads G1's
   y 0 as (254, **6**, 8) and y 1 as (252, 16, 21) where SwiftUI reads
   (254, 9, 8) and (251, 19, 21): the steep red end of red → blue, where
   SwiftUI's renderer sits up to 3 levels off the formula. Every other G1, G2,
   G4, G7 and G11 point the arithmetic reproduces within 1. The table is not
   bent to the two points; `aVerticalGradientSamplesAtPixelCentresG1` holds
   y 0 to ±3 (its `t = y/H` mutation still separates: green 0). Recorded, not
   a divergence.
3. **G4c's probe pixel 50 is the edge itself** (t = 0.5 exactly at its centre)
   and is not pinned; its neighbours 48, 49, 51, 52 are. MetalUI's table puts
   `t = 0.5` in the later stop's colour after the 1024-entry rounding.
4. **A blurred leaf is keyed by its colours.** The shadow's leaf key
   (`keyShadow`) carries alpha only — a silhouette needs no more — and the
   blur first reused it: `blurIsPerLeafB2`'s blue square drew the red square's
   cached texture (measured, `(255, 166, 166)` at x 26). The one leaf switch
   is now `Frame.keyLeaf(_:into:retained:colours:)` (`Shadow.swift`), the
   shadow passing `colours: false` (its keys unchanged) and the blur `true`.
5. **Where the strip applies** (`LK-J` item 5, exactly): a linear gradient
   along exactly one axis, a **fill** with antialiasing, a built-in rounded
   rectangle (not an ellipse or path), no transform record, the composed map a
   uniform positive scale plus translation (so translation and uniform-scale
   effects, which flatten, keep it), and the device rect inside the clip inset
   by the clip's largest corner radius. Its texel count is the device length
   rounded up; texel `i` is the colour at its centre. Its image carries
   `contentMask` = the rect and `maskCornerRadii` = the rect's radii, filter
   linear, the gradient's opacity as the image's. A full raster carries the
   opacity the same way (so a fade re-tints nothing).
6. **A legacy gradient background and a colour one: the last written wins**
   (`background(_:)` with a colour clears the gradient, a gradient clears the
   colour); a gradient is the **plain fill slot** for the opacity-escape rule
   (`LR-FW`); a hover or focus colour paints over it; it paints through
   `paintDecorationBody`, under the corner radius, before the border.
7. **Materials draw the colour site's primitive**: a proposal
   `.background(material)` is the existing `.background(Color)` layer (it fades
   on that layer's colour track like any colour), a legacy one is
   `background(material.color)`, `fill(material)` is `fill(material.color)` —
   a `Color(light:dark:)` of two gamma greys at an alpha (`LK-L` item 3's
   table). `aGradientChangeSnaps` compares half-way with a fresh window's
   pixels rather than a literal, since the new gradient's first pixel is not
   pure green (t = 0.5/100).
8. **Files beyond the spec's table**, each a few lines: `Transition.swift`
   (the two `CapturedPrimitive` kinds and their arms), `TransitionStore.swift`
   (`PaintScope.Kind.blur`, `PaintScope.Blur`), `DragSession.swift` (a replayed
   preview's masks), `AnimatedColor.swift` (`paintDecorationBody`'s gradient,
   item 6), `ModifiedContent.swift` and `ProposalAnimation.swift` (the
   `LayoutModifier.blur` layer's paint and radius track),
   `Tests/MetalUITests/DragPreviewTests.swift` (an exhaustive switch over
   `CapturedPrimitive.Kind` gains an arm) and `Experiments/SDLGPU/README.md`.
   None is on `LK-N`'s off-limits list.
9. **The demo's blur row has fixed radii (0, 2, 6), not a slider**: a slider
   is a click target, and `theLooksDemoDrawsEverySurfaceItsHumanChecksName`
   pins the looks demo's at fourteen (`LK-V` item 9). The section is composed
   with the transitions section in its own frame (`looksTransitionsAndLooks`),
   its rows `Component`s.
10. **The 1 MB thread, measured twice.** With `backgroundGradient` stored
    inline `MemoryLayout<Decoration>.size` read 272 and
    `everyProductionTreeBuildsOnAOneMegabyteThread` failed (`.signal(SIGBUS)`)
    on the first full suite (2850, that one failure) — **even with the new demo
    section removed**. `Decoration`'s two rarely-set paint fields, `clipShape`
    and `backgroundGradient`, now live in one heap box (`DecorationExtras`, an
    `indirect` case; both stay computed properties with their old spelling, `nil`
    when neither is set): the size reads 224 and the production trees build
    again. The section itself, composed inline beside the transitions, still
    overflowed; as a `Component` (`LooksGradientsBlurMaterials`, `PE-K`) it
    passes. A new stored property on `Decoration` (or any per-element value)
    is a stack cost on Windows: box it.
11. **`LayoutModifier.blur(radius:)` owes its migration note** in the Record
    phase (`docs/migration.md`, `LK-R` item 3).
12. **Frame 8 is a second witness, not the first** (`LK-S` item 3, measured).
    The sampler mutation (`address_mode_v` → `REPEAT` on `SDLBridge.c`'s one
    image sampler) fails `PortableReplay` on **frame 6** first (12223 px,
    Δ99), whose stretched images already sample the edge rows; frame 8 alone
    fails too (101 px, Δ40) and passes unmutated. The frame stays: it is the
    only fixture holding a 1-texel strip, a full gradient raster and a blurred
    leaf, and it reddens by itself; it is not ruled redundant. Record §85 §3.3.
