# Key and focus scoping — decisions

Rulings for item C9 of the gpui-gap priority list (user request 2026-10-02;
**not a plan task**), requested by MetalCreator (gaps M4-a, M4-b, M5-b, M5-g,
M5-h and M6's `Panel`/`!Panel` keymap vetoes in its `docs/metalui-gaps.md`).
Prefix `KF-`. Spec:
[`specs/2026-10-08-key-focus-design.md`](specs/2026-10-08-key-focus-design.md).
Record: `../record/88-key-focus.md` (written in the Record phase). Branch
`feat/key-focus` from `c62d6ba`.

**Next unused id: `KF-P`.**

## The final spellings (what an app writes)

```swift
// Keys, SwiftUI's family — needs focus, outermost handler first (KF-B, KF-C)
.onKeyPress(.upArrow) { .handled }
.onKeyPress(.tab, phases: .down) { press in .handled }
.onKeyPress(keys: [.upArrow, .downArrow]) { press in .handled }
.onKeyPress(characters: .decimalDigits) { press in .ignored }
.onKeyPress(phases: .all) { press in .handled }
.onKeyPress { press in .ignored }                       // phases [.down, .repeat]

// Focus on click, SwiftUI's spelling — `.edit` opts in (KF-F)
.focusable(interactions: .edit)
.focusable(true)  /  .focusable()                       // unchanged: Tab and programmatic only

// MetalUI-only: keys follow the pointer while nothing holds focus (KF-D, KF-E)
.hoverKeyRegion()

// Size and position after layout (KF-J)
.onGeometryChange(for: Size<Pixels>.self, of: { $0.size }) { size in viewport.size = size }
.onGeometryChange(for: Bounds<Pixels>.self, of: { $0.frame(in: .global) }) { old, new in … }

// Per-frame and scheduled rebuilds (KF-K, KF-L)
TimelineView(.animation) { context in labels(at: context.date) }
TimelineView(.animation(minimumInterval: 0.1, paused: false)) { context in … }
TimelineView(.periodic(from: start, by: 1)) { context in … }
TimelineView(.everyMinute) { context in … }
TimelineView(.explicit(dates)) { context in … }

// Proposal content: every keyboard modifier merges into ONE layer (KF-H)
MetalView(redraw: .continuous) { … }
    .focusable(interactions: .edit)
    .keyContext("Viewport")
    .onKeyPress("f") { frameAll(); return .handled }    // KeyboardModifier<MetalView>
```

## Evidence

Each probe's header carries its recorded output and how to run it.

- [`../probes/swiftui-key-focus.swift`](../probes/swiftui-key-focus.swift)
  (**new**; arms K0–K12, FC1–FC7, RS0–RS5, G1–G7, T1–T5; macOS 27.0.1,
  Swift 6.4, screen unlocked; runs 10 and 11 byte-identical, 69 lines; the
  instrument's discarded runs are listed in its header).
- [`../probes/swift-builder-for-opaque.sh`](../probes/swift-builder-for-opaque.sh)
  (**new**; arms A1–A8, run twice, byte-identical) — the M4-b (1) builder
  failure reproduced with no MetalUI import.
- [`../probes/swiftui-interaction.swift`](../probes/swiftui-interaction.swift)
  (F3, F4, K0, B4 — re-read here, not re-run; FC1 repeats F3 and agrees).
- gpui: **recalled, not re-read this session** — key events dispatch along the
  focused element's dispatch path (the root's when nothing is focused), a
  capture phase root → focused then a bubble phase focused → root, with key
  contexts on that path; gpui has no hover-scoped key context. Nothing below
  rests on gpui alone: every SwiftUI-facing claim is a probe arm, and the one
  MetalUI-only API (`hoverKeyRegion`) is ruled on MetalCreator's use cases.
- The source at `c62d6ba`: `Window.swift` (the input pipeline,
  `dispatchAction`/`dispatchTextKey`/`dispatchKey`/`dispatchFocusTraversal`,
  `drawFrameIfNeeded`'s lifecycle drain), `Focus.swift` (`FocusRegistry`,
  `focusChain(from:)`), `Keymap.swift` (`matchKeymap`, `contextDepth`),
  `KeyContext.swift`, `Handlers.swift` (18 members), `Hover.swift`
  (`updateHoveredRegions`, the one ranking), `Lifecycle.swift`
  (`LifecycleScope`, `LifecycleStore`), `ProposalContentBuilder.swift`,
  `ElementBuilder.swift`, `GPUSurface.swift`/`MetalView.swift` (proposal
  leaves: no `.focusable()` today), `KeyboardShortcut.swift` (`KeyEquivalent`,
  `EventModifiers`), `SpatialGestures.swift` (`CoordinateSpace`).
- Baseline at `c62d6ba` in this worktree: native build 0 `error:`, the only
  `warning:` SwiftPM's deprecation notice; `swift test --build-system native
  --no-parallel` **2873 tests in 3 suites passed**, the
  `FR-J no-argument frame: succeeded=true` line present.

## KF-A — Scope: six asks, five built, one a toolchain limitation pinned

**Ruling.**

| # | Ask (gap) | Answer | Ruling |
|---|---|---|---|
| 1 | `onKeyPress` on focusable elements and regions (M5-b, M5-h, M6) | **Built**: SwiftUI's family, focus-scoped, outermost first, one stage after the Keymap and before a focused field's editing keys; plus the MetalUI-only `.hoverKeyRegion()` | `KF-B`, `KF-C`, `KF-D`, `KF-E`, `KF-H`, `KF-I` |
| 2 | Focus on click for a surface (M4-a focus half) | **Built**: `.focusable(interactions: .edit)`; plain `.focusable()` keeps divergence 94 (narrowed) | `KF-F` |
| 3 | A press elsewhere resigns text focus (M5-g) | **Not built as asked — SwiftUI does not** (RS1–RS5). The remedies are a click-focusable surface (RS4) and a press in a key region | `KF-G`, `KF-E` item 5 |
| 4 | `onGeometryChange(for:of:action:)` (M4-a size half) | **Built**, through the lifecycle drain: in the first presented frame and the same frame as a resize | `KF-J` |
| 5 | `for` over an opaque helper in a builder (M4-b (1)) | **A Swift 6.4 compiler defect, not fixable in the builder** (A1–A8); a guard pins it, docs give the remedies | `KF-M` |
| 6 | `TimelineView(.animation)` (M4-b (2)) | **Built**, with `.periodic`, `.everyMinute`, `.explicit` and custom schedules | `KF-K`, `KF-L` |

**Deferred, each with a reason and owner** (spec §9): `.focusEffectDisabled()`
(MetalUI draws no generic focus effect; owner: a controls-looks follow-up),
proposal `.onKey`/`.onAction` (no request; the next request that needs them),
`.focusSection()`, `GeometryReader`, named coordinate spaces (`CI-AC`'s
migration), `TimelineScheduleMode.lowFrequency` (MetalUI's windows never
enter it), default focus on show (divergence 186, kept), `onKeyPress` with an
option-modified key (unmeasured; spec §9).

**Cost if wrong.** An ask marked "not built" that SwiftUI does do would leave
MetalCreator a stopgap; each such answer cites its arm.

## KF-B — `onKeyPress`: SwiftUI's surface, SwiftUI's matching

**Ruling.**

1. **Spelling** (both vocabularies, `KF-H`): `onKeyPress(_ key: KeyEquivalent,
   action: () -> KeyPress.Result)`, `onKeyPress(_ key:phases:action:)`,
   `onKeyPress(keys: Set<KeyEquivalent>, phases: = [.down, .repeat], action:)`,
   `onKeyPress(characters: CharacterSet, phases: = [.down, .repeat], action:)`,
   `onKeyPress(phases: = [.down, .repeat], action:)`. `KeyPress` carries
   `key: KeyEquivalent`, `characters: String`, `modifiers: EventModifiers`,
   `phase: KeyPress.Phases`; `KeyPress.Result` is `.handled`/`.ignored`;
   `KeyPress.Phases` is an `OptionSet` with `.down`, `.repeat`, `.up`, `.all`.
   `KeyPress`'s initializer is internal (MetalUI makes them).
   `KeyEquivalent` gains `Hashable` (for `keys:`).
2. **Phases** (K5a, K5b, K5c, K9): default `[.down, .repeat]`; a `KeyEvent`
   with `isRepeat` is `.repeat`, without it `.down`; an `InputEvent.keyUp` is
   `.up`. Both platforms already deliver `isRepeat` and `keyUp`
   (`AppKitPlatform.keyDown`/`keyUp`, `SDLPlatform` line ~900): no platform
   change.
3. **Matching** (K6, K7, K8). `key` is the first grapheme of
   `charactersIgnoringModifiers` (MetalUI's `Keystroke` rule, the arrows and
   function keys in AppKit's private-use area as `KeyEquivalent` already
   spells them); `characters` is the event's `characters`. `onKeyPress(_ key:)`
   and `keys:` compare `key` exactly — case-sensitive, **modifiers ignored**:
   `"a"` fires for `a` and cmd-a and not for shift-A (K8). `characters:` fires
   when every scalar of `characters` is in the set (K7). An option-modified key
   (`characters` "å", `key` "a") is **unmeasured** — the probe sent identical
   strings — so MetalUI's answer (matches `"a"`) is its own until probed.
4. **Return value**: `.handled` claims the event (no later stage sees it);
   `.ignored` continues the walk (`KF-C`).
5. **Runs under `StateDispatch.dispatching(to:)` its own element** (ID-F), from
   input, never in a phase. What it captures outlives the frame (the `onKey`
   retain-cycle note applies).

**Cost if wrong.** A different matching rule would make a binding fire under
modifiers SwiftUI ignores, or not; K8 is the separating arm.

## KF-C — The pipeline: the Keymap, then `onKeyPress` outermost first, then the field

**Ruling.**

1. **SwiftUI's order, measured.** Every `onKeyPress` on the focused view and
   its ancestors runs **before** a focused `TextField`'s editor: a handled key
   is never typed (K4a), ↑ never moves the caret (K4c), Return never submits
   (K4g); an ignored one lets the field act (K4b, K4d). Ancestors too (K4e,
   K4f). A handled key never reaches a `Button`'s `keyboardShortcut` (K10); an
   ignored one does (K11).
2. **Outermost first.** An ancestor's handler runs before the focused view's
   (K2t; three levels K2v: root, mid, inner), a handled ancestor shadows the
   child (K2, K3, K2s), and on one view the later-written modifier runs first
   (K2w). **MetalUI follows it**: the walk is the key chain (`KF-D`) reversed —
   root → focused — and on one element its handlers last-written first.
   **This is the opposite of `onKey`'s bubble** (innermost first, design spec
   §4.3), which is unchanged: the two are different APIs with different
   authorities (SwiftUI for `onKeyPress`, MetalUI's own design for `onKey`).
3. **The new stage** `dispatchKeyPress` sits **after `dispatchAction` (the
   Keymap) and before `dispatchTextKey` (the field's editing keys)**:

   `Keymap → onKeyPress (root → focused) → field editing keys → onKey bubble
   (focused → root, ControlKeys there) → context-menu key → Button shortcut →
   commands → Tab traversal → onInput`.

   The Keymap stays first: it is MetalUI's window-level command layer, offered
   first as AppKit offers menu key equivalents before `keyDown` (`MN-J`'s
   reasoning); SwiftUI has no Keymap. A `keyUp` (phase `.up`) passes the
   earlier key stages unclaimed as today and reaches this stage, then
   `onInput` if unclaimed.
4. **M5-h is answered by the order**: an `onKeyPress(keys: [.upArrow,
   .downArrow])` on the palette's search field (or on the palette around it)
   claims ↑/↓ before `TextEditing.key` moves the caret; MetalCreator's keymap
   stopgap (`PaletteMove`) can go.

**Cost if wrong.** If a real keyboard on AppKit dispatched innermost first, an
app relying on a container's `.ignored` handler running before its child
would see the reverse. Human check KF-1 confirms the order with a real
keyboard; the probe's synthesized `NSEvent`s go through `NSApp.sendEvent`, the
real path.

## KF-D — The key chain: the focus chain, or with nothing focused the hovered key region's

**Ruling.**

1. **One chain feeds every keyboard stage that walks one** — the Keymap's
   contexts (`matchKeymap(contextsByLevel:)`), action dispatch, `onKeyPress`
   and the `onKey` bubble: **the focus chain when an element holds focus;
   otherwise the chain of the innermost hovered key region** (`KF-E`); empty
   when neither. The field's editing keys and Tab traversal read the focused
   element as today (no focus, no field; traversal starts from nothing).
2. **Focus wins.** A focused element anywhere — inside or outside the hovered
   region — keeps the keys: a keyboard user's Tab-focused toggle or field
   never loses Space to a canvas under a resting pointer. This is what M5-b
   asks ("Tab from a focused inspector field moves focus") and what M6's
   `Panel` veto was approximating.
3. **How Keymap contexts see it.** `matchKeymap` is unchanged: it receives the
   chain's contexts innermost first, so a region's `keyContext("Graph")` is as
   deep as its position and a `KeyBinding("+", ZoomGraph(), context: "Graph")`
   beats a context-free or `!Panel` binding by `contextDepth`'s existing rule
   (a negated predicate's depth is the outermost level). **A region nested in
   a `Panel` contributor makes `!Panel` false while hovered** — MetalCreator's
   viewport `F` (`!Panel`) is then vetoed over the graph canvas, which today
   (window-wide) it is not. Migration note: bind it to the viewport's own
   region context (`"Viewport"`) or contribute `Panel` on the fields'
   container rather than the panel (spec §8).
4. **The focus chain itself does not move**: `focusedElement`,
   `PaintPass.isFocused`, `@FocusState`, accessibility focus and Tab order are
   untouched; the hover chain never focuses anything.

**Cost if wrong.** If focus should yield to hover (gpui-style "the surface
under the pointer"), an app with a click-focused surface and a hovered
neighbour sends keys to the clicked one. Spec §8 shows MetalCreator's mapping
works without it; a `.hoverKeyRegion(priority:)` parameter is the additive
widening if a request needs it.

## KF-E — `.hoverKeyRegion()`: MetalUI-only, found by the one ranking at key time

**Ruling.**

1. **SwiftUI has none** (K1u: the pointer over an unfocused focusable view
   routes nothing; K1v: a hovered non-focusable region with `onKeyPress` hears
   nothing), and gpui has none. MetalUI-only by ruling, inventory class M.
2. **Spelling**: `.hoverKeyRegion(_ isEnabled: Bool = true)` on
   `StyledElement` (returns `Self`) and on proposal content (merges into the
   `KeyboardModifier` layer, `KF-H`). It makes the element a **key region**: a
   non-opaque pointer region (blocks no click, hover, wheel or gesture) inside
   the disabled, `.hidden()` and `allowsHitTesting` gates.
3. **Hovered** exactly by `onHover`'s rule (`SV-N` item 3): the innermost key
   region on the cover's layer whose hit region contains the pointer and from
   which the cover descends, the cover being `topmostHitbox(in:at:where:)` with
   "opaque, a hover region or a key region" — **the one ranking, never a
   second lookup**. A `Deferred` presentation above covers it; an opaque
   sibling drawn above covers it.
4. **Computed on demand** at a key event (and at a press, item 5) from
   `lastHitboxes` and the last pointer position — never per pointer move — so
   a window with key regions does no extra work while the mouse moves, and a
   window without them does none at all (counted, spec test A24).
5. **A primary press inside a key region clears focus** (the M5-g remedy),
   unless the press lands on a text field or a click-focusable element
   (`KF-F`) inside that region — those take focus in their own stage, with no
   intermediate `nil` (a `@FocusState` sees one change, not two). After the
   press nothing is focused, so the region under the pointer takes the keys
   (`KF-D`). A press outside every region changes nothing (`KF-G`).
6. **No `StateTable` entry, no reserved slot, no identity level on
   `StyledElement`** (one `Handlers` member, `KF-I`).

**Cost if wrong.** If apps want a region's keys while unrelated focus is held,
item 2 of `KF-D` is the line to revisit.

## KF-F — Focus on click: `.focusable(interactions: .edit)` opts in; divergence 94 narrows

**Ruling.**

1. **SwiftUI** (FC1–FC7): a click focuses `.focusable()` (FC1 = F3),
   `.focusable(interactions: .edit)` (FC3) and
   `.focusable().focusEffectDisabled()` (FC4); never
   `.focusable(interactions: .activate)` (FC2, FC7) or `.focusable(false)`
   (FC5); a tap gesture on a click-focusable view both focuses and taps (FC6).
2. **MetalUI**: `FocusInteractions` (`OptionSet`: `.activate`, `.edit`,
   `.automatic`) and `.focusable(_ isFocusable: Bool = true, interactions:
   FocusInteractions)` beside `.focusable(_ isFocusable: Bool = true)` (which
   replaces today's `focusable()`; `.focusable()` still compiles and means the
   same, guard G2). **An interactions set containing `.edit` focuses on a
   primary press** — SwiftUI's answer (FC3). `.activate` does not (FC2,
   aligned). `.automatic` — and so plain `.focusable()` — **does not**:
   divergence 94 stands, narrowed to `.automatic` (SwiftUI's macOS automatic
   is FC1's click focus). Moving 94 would move every existing focusable box's
   click behaviour (focus is a MUST-NOT-MOVE); the opt-in is SwiftUI's own
   spelling.
3. **Mechanism**: a click-focusable element registers a **non-opaque** press
   region (it blocks nothing, `DN-E`'s shape); at a primary `mouseDown`, after
   hover and before the text-field stage, a non-claiming stage
   `focusOnPress` focuses the innermost click-focusable element whose region
   contains the press, on the cover's layer, from which the cover descends —
   the one ranking. It claims nothing, so the press still reaches the arena
   (FC6: focus and tap). A text field inside it then focuses itself in the
   later stage (inner wins). A secondary or other-button press focuses nothing
   (`MN-B`, divergence 110). Disabled, hidden and `allowsHitTesting(false)`
   withdraw the region.
4. A click-focusable element is still a Tab stop (it is `.focusable()`); the
   focus ring remains the element's own to draw (`isFocused`).

**Cost if wrong.** If `.automatic` should click-focus, a one-line change at
item 2 plus divergence 94's retirement — and a migration note for every
`.focusable()` box that would start taking focus on click.

## KF-G — A press elsewhere does not resign a focused field (SwiftUI's answer)

**Ruling.** SwiftUI keeps a focused `TextField` focused across a press on a
plain colour (RS1), a tap target (RS2), a `Button` (RS3) and a drag target
(RS5); only a press on another click-focusable view moves focus (RS4). MetalUI
does the same today and keeps it: **no default resign**, no divergence. M5-g's
remedies are both opt-ins: make the canvas click-focusable (`KF-F`, RS4's
answer), or a key region (`KF-E` item 5, which clears focus and gives the
region the keys). `Window.focus(nil)` from a gesture stays legal. The probe's
run 1 read `focused=false` for RS1/RS2 with every earlier window still alive;
runs 2–11 read the answer above once each arm's hosting view is released —
human check KF-3 confirms it with a real mouse.

**Cost if wrong.** If a real click does resign, MetalUI diverges silently;
KF-3 is the check, and the remedy would be a non-claiming stage in
`focusOnPress`'s place.

## KF-H — Proposal content: one `KeyboardModifier` layer that every keyboard modifier merges into

**Ruling.**

1. `MetalView`/`GPUSurface` (MetalCreator's viewport and canvas) are proposal
   leaves with no keyboard modifiers today. The proposal spellings of
   `.focusable(_:)`, `.focusable(_:interactions:)`, `.onKeyPress(…)` (all five),
   `.keyContext(_:_:)`, `.focused(_:)`, `.focused(_:equals:)` and
   `.hoverKeyRegion(_:)` return **`KeyboardModifier<Self>`**: a wrapper with no
   layout node, its one child numbered from 0 under its id, one identity level
   for its caller (`HoverModifier`'s recipe), registering one `Handlers` at its
   bounds through `pass.registerHandlers` inside the gates.
2. **On a `KeyboardModifier` the same names return `Self`** (a concrete-type
   extension, preferred by overload resolution): a chain of keyboard modifiers
   is one layer and one id — so focusability, the focus binding, the context
   and the handlers all sit on the focus target, as they do on a
   `StyledElement`. Guard G3 pins it (a nested type does not typecheck).
3. **Order-free on that layer — divergence 185.** SwiftUI's `onKeyPress`
   written inside `.focusable()` never hears (K12); MetalUI's on one keyboard
   layer (and on a `StyledElement`, as before) hears in either order. A
   non-keyboard modifier between them (`.padding`) splits the layers, and the
   K12 rule then holds (the inner layer is a descendant of the focus target).
4. Proposal `.onKey`/`.onAction` are **not** offered (no request; `KF-A`).

**Cost if wrong.** A nested-layer spelling would put focus and handlers on
different ids and silently drop K12-ordered handlers; G3 is the guard.

## KF-I — `Handlers` gains one member, a class box

**Ruling.** `Handlers.keyboard: KeyboardAttachment?` — one final class holding
the `onKeyPress` handlers (written order), the focus interactions and the
key-region flag. One pointer (the 1 MB Windows stack; `Handlers` is copied per
element), nil for every element written before this item. **`Handlers` goes
from 18 to 19 members**: `HandlerShape` (`ModifierTests`) and
`HandlerFingerprint` (`OuterModifierMatrixTests`) each gain the field;
`isKeyTarget` includes `keyboard?.keyPresses` non-empty; `isPointerTarget` is
**not** widened (the press/key-region hitbox is non-opaque, registered by its
own condition as `hasDraggable`'s is). The D2 guard
(`everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`),
`everyHandlerRegisteringSiteHonoursAllowsHitTesting` and
`everyHandlerRegisteringSiteStillPublishesItsAccessibilityPayload` gain the
`KeyboardModifier` arm.

## KF-J — `onGeometryChange`: a transparent scope, noted in prepaint, run in the lifecycle drain

**Ruling.**

1. **Spelling** (every `ElementGroup`, both vocabularies, like `.onAppear`):
   `onGeometryChange<T: Equatable>(for: T.Type, of: @escaping (GeometryProxy)
   -> T, action: @escaping (T) -> Void)` and the `(_ oldValue: T, _ newValue:
   T)` form, returning `GeometryChangeScope<Self>`. `GeometryProxy` offers
   `size: Size<Pixels>` and `frame(in: CoordinateSpace) -> Bounds<Pixels>`
   (`.local`, `.global` — the window's content space, divergence 139's).
   MetalUI's geometry types, as `HoverPhase` and the spatial gestures use; no
   `safeAreaInsets`, anchors or named spaces (inventory R rows).
2. **SwiftUI's semantics, measured**: one call with the initial value
   **before** `onAppear` (G1; the two-argument form passes old == new), then
   one per changed value — per resize step (G5) — never for an unchanged one
   (G3); a group reports **once, the union** (G6: 88 = 50 + 8 + 30); a
   re-inserted view gets the initial call again (G7); `frame(in: .global)`
   includes an `.offset` written outside it (G4a).
3. **Mechanism**: `GeometryChangeScope` is `LifecycleScope`'s shape —
   identity- and layout-transparent, no node, no `StateTable` slot; in layout
   it records its position key (`$geometry<depth>`, a store key, no
   `noteNamed`) and its content's nodes; in **prepaint** it computes the
   union of those nodes' bounds, the global frame as the bounding box of that
   rect moved by the frame's scroll offset (`Frame.activeOffset`, as
   `registerHandlers` moves a hitbox) under the innermost open effect's
   composed affine (`prepaintEffects.last?.composed`, as accessibility frames
   use it, `Frame.swift` ~1952; so G4a's offset is included, a rotation gives
   the bounding box — unmeasured in SwiftUI), and `size` as the untransformed
   layout size; calls `transform` (pure — it must not write) and notes the
   value into the window's `LifecycleStore`. `endFrame` compares with the
   previous build's value and queues events; **`takeEvents` hands geometry
   events before the lifecycle's** (G1's order). No `Window.swift` change.
4. **Timing**: the events run in `Window.drainLifecycle()` — after the build,
   outside every phase and `withObservationTracking`, under `StateDispatch` —
   so a write from the action costs the drain's one settle build inside the
   same `beginFrame()`: **the first presented frame and the frame presenting
   a resize already carry what the action wrote** (M4-a: a viewport's handle
   labels on the first build and during a live resize). A write that changes
   the geometry again reports on the next frame (divergence 121's one level
   per frame). A headless `renderFrame` runs nothing (`LC-` rule).
5. **Work**: a steady frame calls each scope's `transform` once and runs no
   action (counted, spec test B11).

**Cost if wrong.** If SwiftUI distributed over a group, G6 would have read two
calls; it read one.

## KF-K — `TimelineView`: `.animation` through `noteActiveAnimation`, other schedules through one wake

**Ruling.**

1. **Spelling**: `TimelineView<Schedule: TimelineSchedule, Content>(_ schedule:
   Schedule, @ProposalContentBuilder content: @escaping
   (TimelineViewDefaultContext) -> Content)`; `TimelineViewDefaultContext`
   has `date: Date` and `cadence: Cadence` (`.live`, `.seconds`, `.minutes`).
   `TimelineSchedule` is public with SwiftUI's one requirement,
   `entries(from: Date, mode: TimelineScheduleMode) -> Entries`
   (`Entries: Sequence`, `Element == Date`). Built in:
   `AnimationTimelineSchedule` (`.animation`, `.animation(minimumInterval:
   paused:)`), `PeriodicTimelineSchedule` (`.periodic(from:by:)`),
   `EveryMinuteTimelineSchedule` (`.everyMinute`), `ExplicitTimelineSchedule`
   (`.explicit(_:)`). `mode` is always `.normal`; `cadence` always `.live`
   (T5; MetalUI windows never enter low-frequency mode — not inert, the true
   answer).
2. **`.animation`** (T1): the content is evaluated in every build with
   `context.date` the frame's date, and while present and unpaused the
   element calls **`Frame.noteActiveAnimation()`** every build — never
   `requestAnotherFrame()` — so the display link runs exactly while a live
   timeline is on screen and pauses the frame after it leaves.
   `paused: true` evaluates with the date it first appeared and asks for no
   frame (T2). `minimumInterval` steps the date in whole intervals from the
   first appearance (T3) and still runs the link (the date steps; a build per
   frame is MetalUI's model).
3. **Every other schedule** (T4): a per-position cursor in a window-owned
   `TimelineStore` (`AnimationStore`'s, keyed `$timeline<depth>`, never a
   `StateTable` slot) iterates `entries(from: firstAppearance)`: the content's
   date is **the last entry ≤ now** (the schedule's entry, not the clock —
   T4's 0.00, 0.10, …), and the store schedules **one wake** at the earliest
   next entry across the window's timelines: a main-actor `Task` that sleeps
   and then fires the window's own dirty path (`StateTable.onWrite`, the path
   a `@State` write takes) — from outside every phase. A newer earliest entry
   replaces the pending wake; a build with no timeline cancels it. The
   scheduler is injectable (tests record it; **tests never sleep**).
4. **Dates**: the frame's display-link timestamp mapped to a wall-clock `Date`
   by one offset taken at the store's first use (`Date.now − timestamp`), so
   successive dates differ exactly by tick differences; tests set the clock
   (offset 0: `date == timestamp`).
5. **Portable**: Linux and Windows run the same code; the wake relies on the
   SDL loop draining the main queue each iteration (`SV-H`). No platform
   change.

**Cost if wrong.** A periodic timeline that kept the display link running
would draw every vsync for a clock that changes once a minute; item 3 is why it
does not.

## KF-L — `TimelineView` is identity- and layout-transparent

**Ruling.** Like `LifecycleScope`, a `TimelineView` forwards its caller's
parent and cursor and adds no node: content built inside one keeps the ids it
would have outside it, so wrapping an overlay in `TimelineView(.animation)` to
follow a camera (M4-b (2)) resets no `@State`. Its content builder is
`ProposalContentBuilder`, so it is a `ProposalElementGroup` when its content
is (always, through `LegacyContent`) and an `ElementGroup` everywhere. The
content closure is called once per build in layout (the build is the
evaluation). SwiftUI's `TimelineView` identity is not observable from outside;
nothing here is claimed about it.

## KF-M — The `for`-over-an-opaque-helper failure is a toolchain defect; MetalUI pins it

**Ruling.**

1. **Reproduced** on `c62d6ba` with MetalUI (`ZStack { for t in texts {
   label(t) } }`, `label` returning `some Element` or `some
   ProposalElementGroup`, also in a legacy `Column` and with an explicit
   non-opaque outer type) and **without MetalUI** (`swift-builder-for-opaque.sh`
   A1: a twelve-line builder). A2 (a concrete-returning helper) and A3 (the
   opaque values appended to an array by hand) compile.
2. **Cause**: the result-builder transform declares the loop's accumulator with
   the body block's type; a type naming an opaque result type there reads back
   as a new `some G` nothing determines (Swift forums, "Improved Result Builder
   Implementation in Swift 5.8", post 16). It is decided **before** `buildArray`
   is consulted — a non-generic `buildArray([any G])` fails identically (A4) —
   and a wrapper that still names the type fails (A5). Only erasing **every**
   expression compiles (A6), which no typed builder can do for the loop alone:
   it would erase every statement of every block (`MC-H`'s typed copies, the
   `StackMeter` samples, every pinned type guard). **Not fixed in
   `ProposalContentBuilder` or `ElementBuilder`; the ask's "fix the buildArray
   arm" is refuted by A4.**
3. **What ships**: a `typecheckFile` guard (spec test C1) whose failing arm is
   MetalCreator's spelling — it must fail with the opaque-type diagnostic, so
   a toolchain that fixes the transform reddens it and the note can go — and
   whose separating arms compile: `ForEach(texts, id: \.self) { label($0) }`,
   a helper returning a concrete type (`-> ProposalText`, or a `struct Label:
   Element`), and the inline chain. Doc comments on both builders'
   `buildArray` and `docs/api-overview.md` name the remedies.
   SwiftUI's `ViewBuilder` has no `buildArray` at all (A7); `ForEach` is its
   spelling (A8).

**Cost if wrong.** If a library-side fix exists that A4–A6 did not reach, a
later finding supersedes this; the guard's failing arm then turns green and
says so.

## KF-N — Platforms: no new requirement, no shader, SDL source untouched

**Ruling.** Everything above is in `MetalUI` (portable) and uses what both
platforms already deliver (`keyDown` with `isRepeat`, `keyUp`, pointer
events). **No `PlatformWindow`, `Platform` or `WindowRenderer` requirement**,
no shader or renderer change, no new drawable. `Backends/SDL` sources are not
changed except the demo's opt-in root (lane C wires `METALUI_KEY_FOCUS_DEMO`
into `MetalUISDLDemo`), so that change is built and run in CI's Linux image
(`docker build -t metalui-portable …`, the `metalui-sdl-build-key-focus`
volume). The portable tests (`MetalUICrossPlatformTests`) carry the key
pipeline, geometry and timeline arms that Linux and Windows CI run.

## KF-O — Lanes, gates and acceptance

**Ruling.** Three lanes on disjoint files, run one at a time in this worktree
in the order A → B → C (spec §7): **A** keyboard and focus (owns
`Window.swift`, `Focus.swift`, `Handlers.swift`, `Box.swift`,
`FocusState.swift`, `KeyboardShortcut.swift`, `Keymap.swift`, `Frame.swift`
(one condition in `registerHandlers`); new
`KeyPress.swift`, `KeyboardModifier.swift`, `HoverKeyRegion.swift`); **B**
geometry and timeline (owns `Lifecycle.swift`, `AnimationStore.swift`; new
`GeometryChange.swift`, `TimelineView.swift`, `TimelineSchedule.swift`,
`TimelineStore.swift` — **no `Window.swift` or `Frame.swift` edit**, ruled in
`KF-J` item 3 and `KF-K` item 3); **C** the builder guard, the demo, the
docs, the census and the SDL demo wiring. Every lane: the full native suite
unfiltered (2873 at `c62d6ba` plus its own tests), 0 `error:`, only the
SwiftPM deprecation warning, `swift build --build-tests` 0 warnings, each new
typecheck guard mutated red once, every named mutation run on the full suite
with the reddened tests named. Lane C additionally: the fourteen offscreen
images at 0 px against `c62d6ba`, `DemoFrameDeterminismTests`' `Expected.swift`
unedited, both inventory scripts print nothing, the census re-recorded,
`Backends/SDL` built and tested locally and in the Linux image.
