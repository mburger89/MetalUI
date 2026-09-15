# Environment and control state — decisions (plan task 9)

These are the rulings for plan task 9 of
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`: evolve `Theme` into
scoped environment values, add a disabled control state, and clear the keymap's
`Binding` name for task 10.

Prefixed **`EV-`** and **lettered** (`EV-A`, `EV-B`, …). **A bare `EV-3` is a
typo, not a citation.** The next unused letter is `EV-X`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-environment-design.md` — the three lanes,
  their API, tests and mutations.
- `docs/record/11-environment.md` — what was measured, and where.
- The three probes this design stands on, whose headers carry their recorded
  output (the disabled probe re-run in the second pass):
  - `docs/probes/swiftui-environment-scoping.swift` (arms A–H);
  - `docs/probes/swiftui-disabled-interaction.swift` (arms P, K);
  - `docs/probes/swiftui-environment-api-shape.swift` (compile-only).

## How to read the letters

**Written at design time, before any lane runs, and revised once.** Every
probe figure cited below was taken in this design session (2026-09-14, macOS
26.6.2, Apple Swift 6.4) and is in a probe header; nothing is carried from a
sentence. A critic review of the first pass (`bbd4d66`) found 18 defects; the
"Second pass" section at the end applies or rejects each, and the rulings below
are already amended.

- **`EV-A`…`EV-C`, `EV-L`, `EV-M`, `EV-O`, `EV-U`, `EV-V`** — the environment
  mechanism (lane 2).
- **`EV-D`…`EV-F`, `EV-T`** — the disabled control state (lane 3).
- **`EV-G`…`EV-K`** — each value's source, phase and effect (lane 2).
- **`EV-N`** — the `Binding` rename (lane 1).
- **`EV-P`** — the Space-key theme swap and the window capture (lanes 2 and 3).
- **`EV-Q`** — what the probes found that this design does not implement.
- **`EV-R`** — how the probes run, and what their harness got wrong first.
- **`EV-S`** — what a SwiftUI claim in this track may and may not rest on.
- **`EV-W`** — collisions with the two parallel tracks, and how each is kept
  loud.

**Every ruling ends with a "Mutations" line reading _owed by lane N_.** The lane
that implements a ruling replaces that line with the mutations it ran and the
tests each one reddened. A ruling whose line still says "owed" has not been
mutation-tested, and must not be cited as proven.

## Baseline this design was written against

Taken in this session in the worktree `/Users/maxburger/Developer/MetalUI-environment`
at `f64e58a`, after `swift build --build-system native`:

- `swift test --no-parallel --build-system native`: **1084 tests** passed, 0
  `error:`. The run printed ONE summary line.
- **97** goldens (`find Tests -name "*.json" | wc -l`).
- **45** typecheck guards by the per-file count: `PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `UnitSafetyTests` 3 (one is a comment, so 2),
  `AXNodeTests` 3.

---

## EV-A — one scoped environment: nearest writer wins, a transform composes with what it inherits, and nothing cascades

**What.** `Frame` holds the current **top** `EnvironmentValues`. Its first
value is the **root environment**, built once per frame from `Window` (see
`EV-H`). A writer element (`EV-B`) computes its scope's values **once, in
layout**, by applying its write to a **copy of the top** (`EV-V`), and sets them
as the top around its content's phase call, restoring the previous top when the
call returns. It pushes in **each of the three phases** — the stored values in
prepaint and paint — always in closure form (`Frame.withEnvironment`), so an
unbalanced push cannot be written. The saved tops live in `withEnvironment`'s
own locals, so the call stack is the stack. Every read is the top.

Consequences, each matching probe arm A:

- **The nearest writer wins.** `X.environment(k, 2).environment(k, 1)` reads 2
  (A2). An inner writer inside an outer one reads the inner value (A4).
- **A scope ends with its subtree.** A later sibling inside the outer scope
  reads the outer value (A5); a view after the outer scope reads the default
  (A6).
- **A transform composes with the inherited value** (A7:
  `+10` inside `+100` reads 110). **A plain write below a transform replaces
  it** (A8 reads 5).

**Not a CSS cascade, and the difference is mechanical.** There are no
selectors, no specificity, and no per-property inheritance written into every
node. A value is produced only at a writer, and handed out only to a reader
(`pass.environment`, or an element whose type declares an `@Environment`).
The framework's own reads — `Frame.theme` and the gate — read the top in place.
`EV-O` counts that work. **The first pass claimed "copied only at a writer"
while all five bind sites built `pass.frame.environment` for every element in
every phase; the critic found it and `EV-M`/`EV-O` now make the argument lazy
and count it.**

**Why.** It is SwiftUI's observed behaviour (A0–A8), and a closure-scoped stack
is how this framework already scopes clip, layer, opacity and scroll context
(`PrepaintPass.clipped`, `LayoutPass.withScrollContext`). The design adds no
new kind of mechanism.

**Probe.** `swiftui-environment-scoping.swift` arm A. The positive control is
A0: with no writer, the view reads the key's default.

**Cost if wrong.** If SwiftUI resolved writers outermost-first, A2 and A4 would
be backwards. Every scoped value in this design would then read the outer
writer. The fix would be local to `Frame.scopedValues`, which would apply the
new write beneath the enclosing ones instead of above them — exactly the
mutation E1(a) builds.

**Mutations.** _owed by lane 2._

## EV-B — writers are `EnvironmentScope<Content>`: no layout node, no index, no identity level

**What.** Every writer modifier returns
`EnvironmentScope<Content: ElementGroup>: ElementGroup`. It stores its content
and one `@MainActor (inout EnvironmentValues) -> Void` transform. In
`requestGroupLayout` it forwards the `parent` **and the `cursor`** unchanged,
exactly as `StyledComponent` does. It returns its content's nodes unchanged, and
it registers nothing. It conforms to `ProposalElementGroup` where
`Content: ProposalElementGroup`.

Consequences:

- **Layout transparency.** A scope over a two-member group still contributes two
  nodes. That matches probe E: E1 and E2 read `subviews.count` 2, like the bare
  `Group` in E0. The control E3, a scope over a `VStack`, reads 1.
- **Identity transparency.** `X()` and `X().disabled(true)` give `X` the **same**
  `GlobalElementID`. A scope is not a level in the tree.
- **A changed value keeps the state below it.** Probe D1 reads 5 → 6 → 7 with
  `onAppear` firing once. The control D2 changes an `.id`, resets to 5, and fires
  `onAppear` twice.
- **It works over any `ElementGroup`**: a legacy element, proposal content, a
  `Component`, a builder group.

**Limits, recorded rather than fixed** (each is in `EV-Q`):

- A scope is not a `StyledElement`, so `X().disabled(true).padding(4)` does not
  compile. Write the scope outermost. This was handed to task 3's composition
  foundation, but **the modifier-composition spec never mentions
  `EnvironmentScope`**, so it is unowned until the integration step assigns it
  (`EV-Q`, `EV-W`).
- A scope is not an `Element`. It therefore cannot be a window's root
  (`Window.init` takes `Root: Element`), nor the content of `Deferred` or of a
  single-`Element` slot. Root values come from `Window.environment` (`EV-H`), and
  a scope written **outside** a `Deferred` reaches into it (`EV-G`).

**Why.** SwiftUI's writers add no container (E) and keep state (D). This
framework already has one proven shape for a modifier that is neither a layout
level nor an identity level: `StyledComponent` (ruling CO-U,
`addingAModifierDoesNotResetAComponentsState`).

**Probe.** Arms D and E of `swiftui-environment-scoping.swift`.

**Cost if wrong.** A scope that consumed a cursor index would shift every later
sibling's identity. Wrapping an element in `.disabled(flag)` would then reset
the state of everything after it, which is the vanishing-`if` adoption hazard
reached by a modifier.

**Mutations.** _owed by lane 2._

## EV-C — the public shape copies SwiftUI's names; passes can read, only modifiers can write

**What.** The spec gives exact signatures. In summary:

- `public struct EnvironmentValues`. It has stored `isEnabled`,
  `layoutDirection`, `locale` and `dynamicTypeSize`, which are public and
  settable. `pixelLength` is `public internal(set)` (`EV-J`). `theme` is
  `internal` (`EV-G`). A `subscript<K: EnvironmentKey>(key: K.Type) -> K.Value`
  handles custom keys.
- `public protocol EnvironmentKey { associatedtype Value; static var defaultValue: Value { get } }`.
- `@propertyWrapper public struct Environment<Value>`, initialized with
  `init(_ keyPath: KeyPath<EnvironmentValues, Value>)` and read through a
  get-only `wrappedValue`.
- Modifiers on `ElementGroup`:
  - `.environment(_:_:)`, which takes a `WritableKeyPath`;
  - `.transformEnvironment(_:transform:)`;
  - `.disabled(_:)`;
  - `.dynamicTypeSize(_:)`;
  - `.theme(_:)`.
- `public var environment: EnvironmentValues { get }` on **all three** passes.
  It is get-only.
- `Window.environment`, a public settable property (`EV-H`).
- `public enum LayoutDirection`, **declared in `MetalUICore`** (`EV-K`), and
  `public enum DynamicTypeSize` in `MetalUI`, each with SwiftUI's cases.

**Why these names.** The plan asks for behavioural alignment with SwiftUI's
concepts. The compile-only probe confirms each SwiftUI spelling copied here.
`EnvironmentKey` needs only `static var defaultValue: Value { get }`, which a
`static let` satisfies. `.environment` takes a `WritableKeyPath`, and
`.transformEnvironment`, `.disabled` and `.dynamicTypeSize` all exist. **None of
these names is taken in the module today**: a grep for `Environment`,
`LayoutDirection` and `DynamicTypeSize` over `Sources/` and `Tests/` returned
nothing at `f64e58a`.

**Why passes are get-only.** A pass-level setter would be an unscoped push, the
cascade leak `EV-A` exists to prevent: a write in one element's `paint` would
change what every later sibling reads. Pinned by a typecheck guard (spec, lane 2,
`G2`).

**Probe.** `swiftui-environment-api-shape.swift`: two errors, both on NEGATIVE
lines, and no error on any CONTROL line.

**Cost if wrong.** A renamed API later costs a deprecation cycle. The SwiftUI
spellings are the ones least likely to need one.

**Mutations.** _owed by lane 2_ (the guards are the mutation-bearing half).

## EV-D — `isEnabled` composes as an AND under `.disabled`, a raw write overrides, and the gate reads the value

**What.** `.disabled(d)` is `transformEnvironment(\.isEnabled) { $0 = $0 && !d }`,
and `.environment(\.isEnabled, v)` is a plain write. The interaction gates in
`EV-E` and `EV-F` read `environment.isEnabled` at registration time. They do
**not** count `.disabled` modifiers.

**Why.** Probe B:

- `.disabled(false)` inside `.disabled(true)` stays disabled (B3), and so does
  `.disabled(false)` inside a raw `isEnabled = false` write (B6).
- A raw `.environment(\.isEnabled, true)` inside `.disabled(true)` re-enables
  (B5).
- Disablement reaches grandchildren (B8).

Probe P shows the gate is the value:

- A tap under a raw `true` write inside `.disabled(true)` **fires** (P8 = 1).
- A tap under a raw `false` write with no `.disabled` is blocked (P9 = 0).

**Probe.** Arm B of the scoping probe, control B0. Arm P of the disabled probe,
controls P0, P3 and P5.

**Cost if wrong.** A plain-write `.disabled` would let an inner
`.disabled(false)` re-enable a subtree its ancestor disabled. A counter-based
gate would ignore `.environment(\.isEnabled, true)`. Each is one test to flip
(`disabledComposesAsAnAndAndARawWriteOverridesIt`,
`theGateReadsTheEnvironmentValueNotTheModifier`).

**Mutations.** _owed by lane 3._

## EV-E — a disabled click target KEEPS ITS REGION AND RUNS NOTHING: one gate, in `Frame.registerHandlers`, reaches every site (MetalUI's choice, by analogy)

**What.** In `Frame.registerHandlers`, when `environment.isEnabled` is false and
`handlers.isPointerTarget` is true, an opaque hitbox is still registered, but
with an **empty** `Handlers()` and under a **derived id**
(`.child(of: id, at: 0, name: ElementID("$disabled"))`, `EV-T`). `Window`'s
click dispatch then finds that hitbox topmost, reads `handlers.onClick == nil`
and runs nothing. It already does this for any hitbox with no handler
(`Window.swift`, `hit.handlers.onClick` guard).

`.allowsHitTesting(false)` is unchanged, and remains the pass-through spelling.

**One gate, five callers.** Every handler-registering element reaches it,
because each calls `pass.registerHandlers`. `grep -rn "registerHandlers(" Sources`
finds exactly five callers at `f64e58a`: `Box`, `Stack`, `Text`,
`FrameModifier` and `NativeTappable` (`OnTapModifier`). `Column`/`Row` reach it
through `Box`, and `Component` through its members. (The first pass said "six
sites"; the grep says five.) A per-site test has one arm per **spelling** (spec,
D2), so it survives the modifier-composition track deleting `FrameModifier`
(`EV-W`). A raw `PrepaintPass.insertHitbox` call is **not** gated. It is the
low-level registration primitive, and an element that uses it reads
`pass.environment.isEnabled` itself.

**Why keep the region — stated as MetalUI's choice (`EV-S`), not as measured
alignment.** The first pass said "a disabled target swallows the click, probe
P2d–P2f". **That was not what the probe measured.** The critic's arm P2g, now in
the committed probe and re-run, shows an **enabled** clear overlay with a
`contentShape` and **no gesture** already blocks the tap (under 0), and P2h shows
the same disabled (under 0). So in SwiftUI:

- hit-testability belongs to the **shape** (P2d under 1 without one; P2e, P2f,
  P2g, P2h all block with one);
- `.disabled` changes whether the **gesture runs** (P2e over 1 → P2f over 0),
  and does **not** change whether the view is hit-testable.

A MetalUI element has no shape separate from its handler: its region exists
**because** of `onClick` (`isPointerTarget` is `onClick != nil`). The analogue of
"disable the gesture, keep the shape" is therefore "drop the handler, keep the
region", and that is what the gate does. This is an analogy, not a measurement
of MetalUI-shaped content; had the probe been able to say "a disabled target
passes through", this ruling would still be a choice.

**What this costs, knowingly.**

- It swallows the wheel inside a `ScrollView`, which is divergence 16 unchanged.
- **No longer a cost:** the first pass accepted that a disabled element would
  read `isHovered` true and could be marked `active`. The derived id (`EV-T`)
  removes both: hover and press resolve to the blocker's id, which no element
  asks about, so a `hoverBackground` does not paint on a disabled element and
  `isActive` reads false. SwiftUI's hover look under `.disabled` is still
  **unprobed**, so this is a choice, not alignment.

**Probe.** Arm P of `swiftui-disabled-interaction.swift`, P2c–P2h, read as
evidence about hit-testability only.

**Cost if wrong.** If a disabled region should pass clicks through, a disabled
button over a clickable card blocks the card. Changing that is one line: skip
the hitbox instead of registering the blocker. `aDisabledClickTargetKeepsItsRegionAndRunsNothing`
flips.

**Mutations.** _owed by lane 3._

## EV-F — keyboard: a disabled element is OUT OF THE KEYBOARD — no focus, no action handlers, no raw `onKey`, no `keyContext`; a focused element that becomes disabled loses focus (two DIVERGENCES)

**What.** When `environment.isEnabled` is false, `Frame.registerHandlers` does
not call `focusRegistry.register` at all. The element contributes nothing to
the keyboard: not `isFocusable`, not `actions`, not `onKey`, not `keyContext`.

`focusedElementProducedThisFrame` is unchanged and still ungated. **The `$focus`
retention write is gated on `isEnabled`** (second pass, critic finding 7; see
below).

Consequences:

- **A disabled element cannot acquire focus.** `Window.focus(id)` on it is
  cleared at the next prepaint/paint boundary by the existing
  produced-but-not-focusable path. This matches probe K1.
- **A keymap `Action` bound to a disabled element's `onAction` does not claim
  the keystroke.** It bubbles outward, to an enabled ancestor, or, if nothing
  claims it, to `Window.onAction` like any unclaimed action. This is MetalUI's
  routing: a `KeyBinding` belongs to the window's keymap, not to the element,
  so the window's fallback firing is not the disabled element's shortcut
  firing. The analogue of K4 (a disabled Button's `.keyboardShortcut` does not
  fire) is that the **element's** handler does not run. Pinned by D7.
- **A disabled pane contributes no `keyContext`.** A context-scoped binding
  under it does not match at all, so neither a re-enabled child's handler nor
  `Window.onAction` sees it (D9). The first pass kept the context, and the
  critic showed the consequence: the pane's context-scoped shortcut then fell
  through to `Window.onAction`, the opposite of K4.
- **DIVERGENCE 1: a disabled ancestor's raw `onKey` does not see a key** that an
  enabled, focused descendant leaves unhandled (D8). Probe K6 measured the
  opposite in SwiftUI: a disabled parent's `.onKeyPress` runs exactly as an
  enabled one's (K6 = K5, K8 = K7), and K2 shows a focused, then disabled,
  view's own `.onKeyPress` still fires.
- **DIVERGENCE 2: a focused element that becomes disabled loses focus at once**
  (D6). Probe K2 measured the opposite in SwiftUI. There, the view stays
  focused, its `.onKeyPress` keeps firing although it reads `isEnabled` 0, and
  it is still focused after re-enabling.

**Why diverge on raw keys (divergence 1).**

1. **The task brief requires it**: the disabled state "suppresses
   onClick/onTap/focus/keys".
2. Keeping raw `onKey` while stripping `actions` made a disabled pane half-live,
   and keeping `keyContext` made its shortcuts reach the window fallback. Out of
   the keyboard entirely has no half.
3. The first pass cited K5/K6 as showing the parent reads 1 "whether or not the
   parent is disabled" **while the child's control read 0**. The second pass
   fixed that harness (`EV-R` item 5): the parent runs **first** in SwiftUI, and
   a parent returning `.handled` pre-empts the child. With the parent returning
   `.ignored`, the child's control reads, and the disabled parent still runs.
   So the SwiftUI fact is now measured with a control that moved, and this is a
   divergence from it, not an alignment with it. The handler **order** (parent
   first) is a second, pre-existing difference, recorded in `EV-Q` and not
   adopted.

**Why diverge on K2 (divergence 2).**

1. The task brief requires disabled to suppress focus.
2. K2 delivers keys to a control that reports itself disabled, which contradicts
   K4 inside SwiftUI itself.
3. Retaining focus needs a new signal. `Frame` would have to know that the id was
   focused **in the previous frame** and was not merely requested since.
   `Window.focus(_:)` writes the same `focusedElement` field either way. That is
   a change to the focus contract in `Frame`/`Window`. It was handed to task 12,
   but the accessibility-bridge spec (task 12's other half) says disabled
   behaviour waits for task 9, so it is **unowned** (`EV-Q`, `EV-W`).

**The `$focus` slot write is gated on `isEnabled` (critic finding 7).**
`Frame.swift:621-651` documents a known hazard: the slot write is not gated on
`isKeyTarget`, so `Window.focus(x)` on a produced but non-focusable `x` writes a
slot that later makes a focus request on an **unproduced** `x` stick while the
table is below 256 entries. That paragraph says it is "not reachable without an
explicit `Window.focus` call on a non-focusable element". Without a gate, this
design would have made it ordinary: every `.focusable()` element under
`.disabled` is non-focusable, so D5's exact scenario writes the slot, and
removing the element and focusing it again sticks.

The general fix the paragraph describes (gate on `isKeyTarget` **and** clear the
slot in `resolveFocus`) is a focus-contract change and stays out. The gate here
is narrower and local: skip the slot write when `!isEnabled`, leaving
`focusedElementProducedThisFrame` ungated, so
`anElementThatStopsBeingFocusableLosesFocus` is untouched and the pre-existing
hazard stays exactly as reachable as it was. Lane 3 updates that paragraph to
say `.disabled` does not reach it, and D13
(`aFocusRequestWhileDisabledLeavesNoRetentionSlot`) pins the disabled arm
correct and the pre-existing arm wrong on purpose, so the instrument is shown
able to see a sticky focus.

**Probe.** Arm K of the disabled probe. Controls: K0 (enabled focus and key),
K3 (enabled shortcut), K5 (enabled parent, `.ignored`, child listed).

**Cost if wrong.** An app that disables a focused control while it works, for
example during a submit, loses focus and does not regain it on re-enable;
SwiftUI would restore it. A disabled pane's raw `onKey` shortcut stops working
while disabled; SwiftUI would still run it. The remedies are a previous-frame
focus signal and keeping `onKey` in a copy of the handlers, and the pins to flip
are `aFocusedElementThatBecomesDisabledLosesFocusAtOnce` and
`aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`.

**Mutations.** _owed by lane 3._

## EV-G — the theme becomes scoped and stays PAINT-ONLY; `Deferred` keeps its declaring scope

**What.**

- `Frame.theme` stops being a stored `let` and becomes `environment.theme`.
- `PaintPass.theme` keeps its spelling and now returns the **nearest** theme.
  Every existing reader is unchanged: `Box`, `Text` and `AnimatedColor` all read
  `pass.theme`.
- `EnvironmentValues.theme` is `internal`, so no pass exposes it and
  `@Environment(\.theme)` does not compile outside the module.
- `.theme(_:)` on `ElementGroup` is the only public writer. **Access control
  alone does not make that true**: `.environment(\.self, EnvironmentValues())`
  compiles outside the module and replaces the whole value, internal field
  included. `EV-U` re-stamps the theme after every public write.
- `Window.theme` stays the root theme's only source, and it is folded into the
  root environment at frame build.
- `PrepaintPass.deferred` and `PaintPass.deferred` do **not** touch the
  environment stack. A portal escapes clip, offset and layer, not scope.

**Why paint-only survives.** `PhaseSeparationTests`' own theme guards say to
delete them "when a layout rule acquires a use for the theme". None has. Layout
contributes `Style` and tokens, and a token resolves against a theme only in
`paint`. The scoped theme answers correctly in every phase, but exposing it
earlier would be an API with no reader. So the three existing guards stay true
without edits, and one new guard (spec, lane 2, `G1`) extends them to the new
spelling, `pass.environment.theme`.

**Why `Deferred` keeps scope.** Probe F: an overlay's content sees the scope the
overlay modifier sits in (F1 = 3). It does not see a writer applied to the base
before the overlay was attached (F2 = 0). `Deferred`, declared inside a scope,
is the F1 shape.

**Probe.** Arm F of the scoping probe.

**Cost if wrong.** A component that wants to branch on light versus dark during
`content` cannot. It paints tokens, which follow the theme anyway, so the common
case is unaffected. An `appearance` value is deferred (`EV-Q`).

**Mutations.** _owed by lane 2._

## EV-H — root values and defaults: `Window.environment`, plus the theme and the surface's scale

**What.** `Window.environment: EnvironmentValues` is public and settable, and its
`didSet` marks the window dirty. It defaults to `EnvironmentValues()`:

- `isEnabled` true;
- `layoutDirection` `.leftToRight`;
- `locale` `Locale.current`;
- `dynamicTypeSize` `.large`;
- custom keys at their defaults.

**How it reaches the frame: one statement, no init parameter.** `Frame.init`'s
signature is unchanged. It builds its root from `EnvironmentValues()` and stamps
two fields itself:

- `theme`, from the existing `theme:` parameter, which is `Window.theme`;
- `pixelLength`, as `1 / scaleFactor`, or 1 when the scale is not finite and
  positive.

`Window.drawFrameIfNeeded` then runs `frame.rootEnvironment = environment` on the
line after its `Frame(...)` expression, and the setter re-stamps the same two
fields. The first pass added an `environment:` init parameter; the
accessibility-bridge track adds `collectsAccessibility:` to the same `init`
**and** to the same call expression, so both edits would have collided
textually (`EV-W`). A test-built `Frame` gets defaults for everything.

**Two consequences, recorded rather than fixed.**

- **An in-module write to the root's theme or `pixelLength` is silently
  re-stamped.** `window.environment.theme = .dark` compiles inside `MetalUI`
  and changes nothing; `Window.theme` is the root theme's only source. Pinned
  by E13(c), and an inert row owed to the integration step.
- **Every write dirties the window, a no-op included.** `EnvironmentValues`
  holds `[ObjectIdentifier: Any]` for custom keys, so its `didSet` cannot
  compare old and new; `Window.theme` guards with `!=` (`Window.swift:104-108`)
  and this cannot. The cost is one extra frame per no-op write, and a write made
  from a phase every frame keeps the display link awake, the same rule as
  `@State`: write from input, never from a phase. Constraining `EnvironmentKey`
  values to `Equatable` would fix it and would diverge from SwiftUI's
  unconstrained `Value`, so it is rejected. Pinned by E14's no-op arm.

**`locale` has no consumer.** `Text`'s tokenizer and typesetter never receive
it; `aLocaleChangesNoTextMeasurement` (E21) pins that, as E16 does for dynamic
type, so a later change that routes it into shaping must face the pin. **Unlike
dynamic type, this is not claimed as aligned**: no probe measured SwiftUI text
under a locale. It is an inert row owed to the integration step.

**Why.** Probe C, in an NSWindow, read these defaults: `leftToRight`, `en_US`
equal to `Locale.current`, `large`, `displayScale` 2.0 equal to
`backingScaleFactor`, `pixelLength` 0.5 and `isEnabled` true. C2 is the control
that every reader moves when written.

**What C cannot tell.** This machine is LTR
(`NSApp.userInterfaceLayoutDirection` = 0). C cannot tell a constant LTR default
from one derived from the system. Nor does it test a locale change while
running. Following the system's layout direction and locale needs a
`PlatformWindow` requirement, in a shared file, and is deferred (`EV-Q`).

**Cost if wrong.** On a right-to-left system, `layoutDirection` reads
`.leftToRight` until the app sets it. Given `EV-K`, nothing built-in would
mirror anyway.

**Mutations.** _owed by lane 2._

## EV-I — `dynamicTypeSize` is carried and changes no built-in text size, as in SwiftUI on macOS

**What.** There are 12 cases, `xSmall`…`accessibility5`. The type is
`Comparable` and has `isAccessibilitySize`. The modifier `.dynamicTypeSize(_:)`
writes it. `Text` goes on measuring at its own `fontSize`.

**Why.** Probe G: a `.body` `Text` measures 120×16 at the default,
`.dynamicTypeSize(.xSmall)` and `.dynamicTypeSize(.accessibility5)`. The control
`.font(.system(size: 26))` measures 219×30. On macOS the value does not reach
text size, so carrying it without an effect **is** the aligned behaviour, not an
inert API. It is pinned so that a later "fix" has to face the probe
(`dynamicTypeSizeChangesNoTextMeasurement`).

**Cost if wrong.** On a future iOS target, text would ignore dynamic type. Task
14 owns that target.

**Mutations.** _owed by lane 2._

## EV-J — platform metrics: `pixelLength` is exposed read-only; `displayScale` is NOT (a divergence)

**What.** `EnvironmentValues.pixelLength` is `public internal(set)`, measured in
points, one device pixel wide. There is no `displayScale`.

**Why read-only.** SwiftUI's `pixelLength` is get-only. The API-shape probe
rejects both `e.pixelLength = 1` and `.environment(\.pixelLength, 1)`. A writable
one could lie about the device.

**Read-only is enforced at run time, not only by access control.**
`.environment(\.self, EnvironmentValues())` and
`.transformEnvironment(\.self) { $0 = captured }` compile outside the module and
would reset it to 1 (measured with a two-module stand-in; record 11, "Second
pass"). `EV-U` re-stamps it after every public write, and G3's positive half
records that the compiler cannot close the route.

**No internal reader.** Nothing in `MetalUI` reads `pixelLength`; it exists for
element authors. An inert row owed to the integration step.

**Why no `displayScale`, although SwiftUI's is readable and even writable.**
`PaintPass` "deliberately exposes no `scaleFactor`": `fill` takes points and
scales once, and a caller who finds a scale factor and pre-scales
double-scales. The doc of
`theFrameBehindAPassIsNotReachableFromOutsideTheModule`
(`PhaseSeparationTests.swift`) names that same hazard as a reason
`pass.frame.scaleFactor` must not compile.

`pixelLength` does reveal the scale, as `1 / pixelLength`. So this is not
secrecy; it is **which unit the value arrives in**. A hairline drawn with
`fill(… width: pixelLength)` is correct as written. The double-scaling use needs
an explicit inversion, which reads as the mistake it is.

**Probe.** `swiftui-environment-api-shape.swift` (get-only) and scoping probe C
(pixelLength 0.5 at scale 2.0).

**Cost if wrong.** An author who needs the scale computes `1 / pixelLength`.
Adding `displayScale` later is one property.

**Mutations.** _owed by lane 2._

## EV-K — `layoutDirection` is carried and readable; NO built-in container mirrors yet (a divergence, pinned wrong on purpose)

**What.** The value flows like any other. `HStack`, `Row` and every other
container ignore it. **The type is declared in `MetalUICore`**
(`Sources/MetalUICore/LayoutDirection.swift`), not in `MetalUI`: mirroring needs
the direction recorded on native nodes in `LayoutTree`, which lives in
`MetalUILayout`, and `MetalUILayout` imports only `MetalUICore`. Declaring it in
`MetalUI` now would force task 6 to move a public type across a module boundary,
the stale-incremental-build hazard CLAUDE.md names. `MetalUI` re-exports
`MetalUICore` (`App.swift:8`), so no caller sees the difference.
`aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack` pins today's LTR
placement **wrong on purpose**: a 10pt and a 20pt child in a 100pt leading frame
at x 0 and 10.

**Why diverge.** Probe H: under `.rightToLeft` SwiftUI places the first child at
x 90 and the second at 70. It mirrors, and the control H0 reads 0 and 10.
Mirroring is a placement transform inside the proposal kernel
(`LayoutTree.swift`). It would need the direction recorded on each native node
at registration. That file belongs to the kernel and container tracks (plan
tasks 6 and 7), which run in parallel with this one. The legacy CSS engine will
never gain it; it is being retired. The environment value is the input task 6
needs, and delivering it now is what lets that change stay local.

**Cost if wrong.** An app that sets `.rightToLeft` sees no mirroring, and the
pin says so rather than hiding it. Divergence text for CLAUDE.md is owed to the
integration step.

**Mutations.** None owed. It is pinned wrong on purpose, and the test flips in
the change that implements mirroring.

## EV-L — every public value is readable in all three phases and answers identically; no phase-only guard

**What.** `pass.environment` exists on `LayoutPass`, `PrepaintPass` and
`PaintPass`. Within one frame and one scope, all three return the same values.
The root is fixed before the frame starts, and a scope computes its values
once, in layout, and pushes those stored values in prepaint and paint (`EV-V`).
**So the invariance holds for any transform**, including one that reads a
counter, the time or a model; the first pass re-ran the transform per phase and
the invariance held only for pure closures (critic finding 9).

**Why no guard.** `PhaseSeparationTests`' header says a guard for an API that
would answer correctly is cargo cult. The paint-only queries are guarded because
they are **measured lies** outside paint. `isHovered` and `isFocused` resolve at
the prepaint/paint boundary; `isActive` is guarded as insurance. An environment
value has no boundary resolution, so there is nothing to lie about.

What **is** pinned instead is the invariance itself:
`anEnvironmentValueReadsIdenticallyInAllThreePhases`. A scope that skipped its
push in one phase would make it red.

**Where each value is consumed.**

- `isEnabled` is read in **prepaint**, by the framework's gate (`EV-E`, `EV-F`),
  in place, and in any phase by an element.
- `theme` is read in **paint** only (`EV-G`).
- `layoutDirection`, `locale`, `dynamicTypeSize`, `pixelLength` and custom keys
  have no built-in consumer; any phase may read them.
- A `Component` reads the environment while building `content`, which happens
  during **layout** (`EV-M`).

**Cost if wrong.** If a future value had to be resolved at a boundary, it would
need its own guard. This ruling does not cover such a value.

**Mutations.** _owed by lane 2._

## EV-M — `@Environment` is bound like `@State`: by reflection, per element, per phase, to a snapshot

**What.** `Environment<Value>` holds a key path and a class box.
`StateBinder.bind(_:table:id:)` becomes **`bind(_:in frame: Frame, id:)`**. It
seeds each `Environment` it finds with a snapshot from
`frame.environmentSnapshot()`, **taken only when the type's cached shape has
`Environment` ordinals**, once per bind. Its per-type shape cache extends to
record `Environment` ordinals alongside `State` ordinals. The five existing call
sites pass `pass.frame` (or `self` in `Frame.render`):

- `ElementGroup.swift`, three sites;
- `Component.swift`, one site;
- `Frame.swift`, one site.

Each is a one-line edit.

`wrappedValue` reads the snapshot through the key path.

**Why lazy, and why `frame:` rather than an `environment:` argument.** The first
pass passed `environment: pass.frame.environment`, which Swift evaluates before
`bind` can return early: every element in every phase built a value it never
used (critic finding 5). Passing the `Frame` costs a reference. And because the
old spelling is **removed**, not overloaded, any call site written elsewhere
against `bind(_:table:id:)` — the modifier-composition track adds two (`MC-H`) —
fails to compile at the merge instead of silently binding the root environment.
**The argument must never gain a default** (`EV-W`).

**An `@Environment` that was never bound returns the key's default, silently.**
It builds `EnvironmentValues()` on each access, which reads `Locale.current`.
There is no diagnostic: the legitimate unbound reads (a handler closure reading
an `AnyElement`-wrapped element's property, a value built outside any frame)
are indistinguishable from a forgotten bind. Documented on E8
(`anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`), and an inert
row owed to the integration step.

Consequences, all inherited from how `@State` binds:

- **An `Element`** is re-bound in `prepaintGroup` and `paintGroup`, so each phase
  reads its own occurrence's scope.
- **A `Component`** is bound once, in `requestGroupLayout`, where its `content`
  is materialized. Its handlers capture that snapshot.
- **Inside `AnyElement` it is inert** and reads defaults, for `@State`'s reason:
  `Mirror` cannot see through the box. This is a new row for the inert table,
  owed to the integration step.
- **One element VALUE placed twice under two scopes** shares one box. Reads are
  correct per phase because of the re-bind. A **handler** closure reading it after
  the frame sees the last occurrence bound. This is divergence 19's shape, one
  wrapper over.
- **The environment is re-read every frame.** A value that changed between
  frames is seen, not a stale snapshot.

**Why a snapshot and not a live reference to the stack.** A handler runs after
the frame, when the stack no longer exists. A snapshot is the value at the
element's position. SwiftUI gives no stronger promise for a value read outside
`body`, and none is claimed here.

**Cost if wrong.** A change of reflection shape can touch every `@State` user.
The existing `StateBinder` tests and `StateBinder.reflectionCount` are the guard,
and they must stay green unchanged.

**Mutations.** _owed by lane 2._

## EV-N — the keymap's `Binding` becomes `KeyBinding`, with a deprecated alias that task 10 deletes

**What.**

- `public struct Binding` in `Keymap.swift` is renamed `KeyBinding`.
- `@available(*, deprecated, renamed: "KeyBinding") public typealias Binding = KeyBinding`.
- `Keymap.bindings: [KeyBinding]` and `KeymapBuilder.buildBlock(_: KeyBinding...)`.
- The demo (`main.swift:1104-1112`, nine lines) and `KeymapTests.swift`
  (about 30 call sites) move to `KeyBinding`, so that neither emits a
  deprecation `warning:`. The suite's 0-warning bar applies.
- Doc comments that spell `Binding(` are updated, in `Keymap.swift` and in
  `KeyContext.swift:63`.

**Why rename.** Ruling `CO-Z` (component decisions) recorded the collision
and left it: `@Binding var x` fails to compile with a confusing error because
the name is taken by a non-wrapper, and a reader from SwiftUI reads
`Binding("m", ToggleModal())` as a value binding. Task 10 needs the name.

**Why an alias at all.** External callers keep compiling for one release. A
typecheck guard (spec, lane 1, `G5`) proves the old spelling still compiles
**and** is deprecated toward `KeyBinding`.

**Why the alias must die in task 10.** A module cannot declare a SwiftUI-like
`struct Binding<Value>` beside a typealias of the same name. Task 10 deletes the
alias and `G5` in the change that introduces `Binding`. Its deprecation window is
therefore exactly the time between these two tasks.

**Cost if wrong.** An external keymap written with `Binding(…)` breaks at task 10
instead of now. The warning in between is the notice.

**Mutations** (lane 1, on a `--build-system native` build in this worktree; the
guard is `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding`, and
each run below printed `passed`/`failed` for it, never `skipped`):

- **Red on arrival**, guard written, `Binding` still the struct: `messages → ""`,
  failing `contains("'Binding' is deprecated")` (`EnvironmentCompileGuards.swift:48`)
  and `contains("KeyBinding")` (`:50`); `succeeded` held.
- **(a) no alias** (the struct renamed, typealias not yet written):
  `succeeded → false`, `messages → "cannot find 'Binding' in scope"`; all three
  expectations failed (`:46`, `:48`, `:50`).
- **(b) `@available` line deleted**: `messages → ""`; `:48` and `:50` failed.
- **(c) `@available(*, deprecated)` without `renamed:`**:
  `messages → "'Binding' is deprecated [#DeprecatedDeclaration]"`; only `:50`
  failed. This is why the guard asserts both substrings: (c) is a deprecation
  that no longer tells the caller where to go.
- **Not mutated**: the respelled `KeymapTests` (the file's existing mutation
  records stand). Before the rename they failed to compile with 44 distinct
  `cannot find 'KeyBinding' in scope` errors.

The swiftc diagnostic the guard matches, taken verbatim from the fixture outside
the harness: `warning: 'Binding' is deprecated: renamed to 'KeyBinding'
[#DeprecatedDeclaration]`, plus `note: use 'KeyBinding' instead`.

## EV-O — environment work is counted, and scales with writers and readers, not with their descendants

**What.** `Frame` carries three internal, test-only counters:

- `environmentPushCount`: a tree with no writer pushes 0 in a whole frame; a tree
  with W writers pushes 3W (one per phase), whatever the size of the subtrees
  below them;
- `environmentSnapshotCount`: one per public materialization of the value —
  `pass.environment`, and each bind of a type that declares an `@Environment`.
  A tree with no reader takes **0**, however many elements and writers it has;
- `environmentTransformCount`: one per writer per frame (`EV-V`).

`Frame.theme` and the gate's `isEnabled` read the top in place and are **not**
counted. This ruling claims nothing about them beyond what the source shows.

**Why.** "Not a CSS cascade" (`EV-A`) is a performance claim as well as a
semantic one, and this repo pins performance by counting work on a **branching**
tree, never by wall clock. `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants`
is written first and is red on arrival: the counters do not exist. Its positive
control — one `@Environment` reader leaf takes the snapshot count from 0 to 3 —
proves the snapshot counter can move, and the eager-evaluation mutation (bind
snapshots before consulting the shape) reddens it, which is what the first
pass's push-only count could not see.

**Cost if wrong.** A per-element copy of `EnvironmentValues` costs
roughly one Theme (32 floats) and some retains per element per phase. It is
invisible in a small tree and linear in a 500-row list. An allocation count, as
`FreezeLoopAllocationTests` takes, would see more than the counters do and was
not designed in; it is the next instrument if a profile ever disagrees.

**Mutations.** _owed by lane 2._

## EV-P — the Space-key theme swap is proven through the fake platform, and the demo is captured without input

**What.**

- **A test drives the swap.**
  `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` puts
  `KeyBinding("space", ToggleTheme())` on a fake window and flips `window.theme`
  in `onAction`. It sends one `keyDown` through `FakePlatformWindow.simulateInput`,
  draws, and reads **rendered pixels** with `readPixels()`, gated on
  `try #require(MTLCreateSystemDefaultDevice())`: the centre pixel matches a
  light reference window before and a dark one after, and the two references
  are required to differ first. This is the demo's wiring, minus the executable
  target, which tests cannot import. The first pass read `lastScene` rect
  colours, which is not a capture; the critic pointed out `readPixels()`
  already exists.
- **The real demo is only captured.** At the end of lane 3 the release demo is
  launched at `f64e58a` and at the lane's commit, with **no input sent**, and each
  window is captured once. The captures are compared **by region**: a pixel
  script first finds the dynamic regions from two base captures seconds apart
  (and must find some, or it is not seeing the demo's changing text), then
  requires every region that differs at the lane's commit to lie inside them.
  The first pass planned a byte-for-byte `cmp`, which the demo's time- and
  scroll-dependent text would almost certainly have failed for no reason. The
  result is recorded in `docs/record/11-environment.md`.

**Why no keystrokes into the real demo.** This track's rule is that input is
sent only through the fake platform, in tests. The theme's scoping change must
be invisible when no scope is written, and a capture at launch shows exactly
that.

**Cost if wrong.** A difference that shows only after a real Space press, in
AppKit's delivery path, is not covered. `MetalHostView`'s key path is not
touched by this track.

**Mutations.** _owed by lane 2_ (the test) and _lane 3_ (the capture).

## EV-Q — found by the probes, or required by the brief, and NOT done here

Each item names its owner, or says it has none. **"Unowned" means the owner this
design first named does not, on reading that track's spec, take it**; the
integration step assigns it (`EV-W`).

| item | evidence | owner |
|---|---|---|
| RTL mirroring in any container (`EV-K`) | probe H | plan task 6 |
| Following the system's layout direction and locale, and locale changes while running (`EV-H`) | probe C cannot distinguish; needs a `PlatformWindow` requirement | platform seam, task 14 |
| A consumer for `locale` (tokenizer, typesetter, number formatting) (`EV-H`) | none measured | none named; inert row |
| `displayScale` (`EV-J`) | probe C, API shape | reopen if a reader needs it |
| An `appearance`/`colorScheme` value; the theme readable before paint (`EV-G`) | none | task 11 |
| `controlActiveState` (window key state), `controlSize` | probe C reads `inactive`, `regular` | task 12 |
| Focus retention when a focused element is disabled (`EV-F`) | probe K2 | **unowned**: named task 12, but the AX-bridge spec says disabled behaviour waits for task 9 |
| Raw key handlers on a disabled element (`EV-F` divergence 1) | probe K2, K6 | **unowned**, same reason |
| Key handler ORDER: SwiftUI runs an ancestor's `.onKeyPress` before the focused view's; MetalUI bubbles outward from the focused element | probe K5, K7 | **unowned**; a pre-existing difference, not introduced here |
| A disabled "look" (dimming) | **unprobed** | **unowned**, same reason as focus retention |
| Wheel scrolling under `.disabled` | **unmeasured**: the probe's enabled control failed (header "S") | task 10 |
| Scopes after `StyledElement` modifiers (`EV-B`) | compile-time limit | **unowned**: named task 3, but the modifier-composition spec never mentions `EnvironmentScope` |
| A scope as window root or as `Deferred`/`List` element content (`EV-B`) | compile-time limits | task 3 (same caveat) |
| `@Environment` inside `AnyElement` (`EV-M`) | inherits `@State`'s inertness | task 8 |
| Reduce Motion as an environment key | plan task 13 | task 13 |
| Removing the `Binding` alias (`EV-N`) | — | task 10 |

Hover and pressed on a disabled element were in this table and are now decided
here (`EV-T`), as MetalUI's choice.

## EV-R — how the probes run, and the harness errors this session made first

**What.**

- **Runtime probes.** Both runtime probes run under Apple's toolchain in both
  forms: `/usr/bin/swift <file>`, and compiled with `swiftc` and then run with
  `OS_ACTIVITY_DT_MODE=1`. The filtered output of the two forms was
  byte-identical, and a second compiled run of the interaction probe was
  identical too.
- **Compile-only probe.** The API-shape probe is run as
  `swiftc -typecheck -diagnostic-style=llvm`. Its errors are the observation.

**Recorded because two harness versions measured nothing:**

1. **Click order.** The first click helper queued mouse-up before mouse-down.
   Every `.onTapGesture` arm read 0, including the **enabled control**, so every
   disabled zero was void.
2. **First mouse.** Even with the order fixed, taps read 0 until the hosting
   view accepted first mouse. An unbundled script never becomes the active app,
   and an inactive window eats its first click.
3. **P2.** P2's reading was ambiguous until control P2m ran (see `EV-E`).
4. **Scroll.** Four scroll-synthesis strategies left an enabled `ScrollView`
   unscrolled, so that arm was removed rather than reported.
5. **K5/K6 (second pass).** The first version counted handler calls with the
   parent returning `.handled`; the child's control read 0 and the arm was filed
   as "unexplained" while a ruling still cited it. Scratch variants (record 11,
   "Second pass") showed the child fires when the parent is absent or returns
   `.ignored`, and an order log showed the parent runs first. The committed
   arms now log order, and K5's child entry is a control that moves.
6. **P2 again (second pass).** P2f was read as "disabled swallows". P2g, with no
   gesture at all, blocks too, so P2f measured the shape, not `.disabled`. The
   reading error was in the ruling, not in the harness; it is recorded here
   because it would have shipped a SwiftUI claim the probe does not support.

**Why record it.** Rule 11 of the practices doc's taxonomy is a run that did not
happen and reported success. Each of these would have produced a plausible
"disabled blocks it" reading.

## EV-S — scope of SwiftUI claims in this track

**What.** A sentence in this track's code, tests or docs may say "SwiftUI does X"
only when a probe arm under `docs/probes/` measured X with a positive control
that could move. Everything else is stated as MetalUI's choice:

- `keyContext` under disabled (SwiftUI has no comparable concept);
- the AX `disabled` trait;
- a disabled target keeping its region and running nothing (`EV-E`: an
  analogy to P2e–P2h, not a measurement);
- a disabled target being neither hovered nor pressed (`EV-T`);
- an unclaimed action from a disabled element reaching `Window.onAction` (`EV-F`);
- `locale` affecting no measurement (`EV-H`).

Divergences are claims too: D6 and D8 may cite K2 and K6 because those arms'
controls (K0, K5) moved.

## EV-T — a click needs its target enabled at press AND at release; a disabled target registers its blocker under a derived id

**What.** The blocker hitbox `EV-E` registers for a disabled pointer target uses
the id `.child(of: id, at: 0, name: ElementID("$disabled"))`, copying the
`$anim-content` spelling (`AnimatedStyle.swift:185`), not the element's own id.
`Window` is not edited.

Consequences, through the unchanged `Window` code:

- **Pressed disabled, released enabled → no click.** `mouseDown` makes the
  blocker's derived id `active`; the next frame re-registers the element under
  its own id with its `onClick`; `dispatchClick` requires `hit.id == pressed`
  and the ids differ.
- **Pressed enabled, released disabled → no click.** The release lands on the
  blocker, whose handlers are empty (this held in the first pass too).
- **Not hovered, not pressed.** `isHovered(id)` and `isActive(id)` resolve
  against the blocker's id, so a disabled element's `hoverBackground` does not
  paint and `isActive` reads false.
- **The accessibility bridge's `.press` refuses a disabled element** without an
  edit: it looks for a `lastHitboxes` entry with the element's id and an
  `onClick` (`EV-W`).

**Why.** The critic found that the first pass's blocker, registered under the
element's own id, let a press made while disabled click on a release after
re-enabling (`Window.swift:1197-1201`). Probe R, added in the second pass,
measured SwiftUI: R1 (pressed disabled, released enabled) reads 0 and R2 (the
reverse) reads 0, for a plain `Button` and for `.onTapGesture`, with R0 (enabled
at the same timing) reading 1. The alternatives were:

- **Record it as a divergence.** Rejected: the fix is one argument in a method
  lane 3 already edits.
- **Set `active` only for hitboxes with an `onClick`.** Rejected: scroll regions
  and raw `PrepaintPass.insertHitbox` calls register opaque hitboxes with no
  `onClick`, so it would change `isActive` for them, in `Window.swift`, a shared
  file.

The hover and pressed half is **not** probe-backed (`EV-S`); SwiftUI's hover
look under `.disabled` is unprobed. It follows from the same id and is kept
because a `hoverBackground` lighting up on a control that ignores the click
reads as a live control.

**Probe.** Arm R of `swiftui-disabled-interaction.swift`.

**Cost if wrong.** A new reserved name: `$disabled` is an id suffix beside
`$anim-content`/`$anim-viewport`, and a `List` datum whose id describes to it
collides with a disabled row's blocker (hover and press identity only; no state
lives under it). Owed to CLAUDE.md's reserved-name paragraph. If a disabled
element should show hover, register the blocker under `id` and add the R1 guard
elsewhere; `aDisabledTargetIsNeitherHoveredNorPressed` flips.

**Mutations.** _owed by lane 3._

## EV-U — `theme` and `pixelLength` are re-stamped after every public write, so `\.self` cannot reset them

**What.** `Frame.scopedValues(applying:)` handles the internal `EnvironmentWrite`:

- `.transform(t)`: copy the top, run `t`, then set `theme` and `pixelLength`
  back from the top it copied;
- `.theme(th)`: copy the top and set `theme` (only `.theme(_:)` produces this).

`Frame.rootEnvironment`'s setter re-stamps the same two fields at the root.

**Why.** `.environment(_:_:)` takes a `WritableKeyPath<EnvironmentValues, V>`,
and `\.self` is one. Measured in a two-module stand-in (record 11, "Second
pass"): `environment(\.self, EV())` from outside the module reset a
`public internal(set)` field from 0.5 to 1 and an `internal` field from 7 to 0,
while `environment(\.pixelLength, 1.0)` failed with "cannot convert … KeyPath …
to WritableKeyPath". So access control stops the field's own key path and not the
whole-value one, and a captured `@Environment(\.self)` snapshot written back
does the same. Without this ruling, any caller could reset the scoped theme to
`.light` in a dark window and `pixelLength` to 1 on a Retina display.

**Alternatives rejected.**

- **Store `theme` and `pixelLength` beside the values on `Frame`, not in them.**
  It closes the route equally, but every element that wants `pixelLength` would
  then need a second accessor, and `@Environment(\.pixelLength)` would stop
  working. Re-stamping keeps one value.
- **Reject `\.self` at compile time.** Not expressible: a `WritableKeyPath`
  parameter accepts it.

**Pins.** E19 (`aWholeValueWriteCannotResetTheThemeOrThePixelLength`) at run
time, with a control that the write did land (a custom key resets); G3's
positive half records that the route compiles.

**Cost if wrong.** A caller who genuinely wants to reset everything cannot reset
the theme through `\.self`; they write `.theme(.light)`.

**Mutations.** _owed by lane 2._

## EV-V — a scope runs its transform once per frame, in layout; prepaint and paint re-push the stored result

**What.** `EnvironmentScope.requestGroupLayout` calls
`frame.scopedValues(applying: write)` once and stores the result in its group
layout (`EnvironmentScopeLayout.values`). `prepaintGroup` and `paintGroup` push
`layout.values` and never call the transform.

**Why.** The first pass applied the transform in each phase. A
`transformEnvironment` closure that reads a counter, the clock or a changing
model would then hand layout, prepaint and paint three different values, and
`EV-L`'s "identical in all three phases" would hold only for pure closures
(critic finding 9). Storing the result makes the invariance unconditional,
keeps the push count at 3W, and costs one stored copy per writer.

**Pins.** E20 (`eachScopesTransformRunsOncePerFrame`): a counting transform runs
once per frame and the three phases read the same value; E15's transform
count.

**Cost if wrong.** If some value genuinely had to be recomputed at prepaint
(none does; `EV-L`), it would need its own boundary resolution and guard.

**Mutations.** _owed by lane 2._

## EV-W — collisions with the parallel tracks are made loud, and listed for the integration step

**What.** This track is merged with `feat/modifier-composition` (`1c6f686`) and
`feat/ax-bridge` (`2042a54`). Each known collision is designed to fail to compile
or redden a named test, and each is listed in the spec's "Owed to the integration
step":

1. **`ProposalElementGroup.requestProposalGroupLayout` (modifier composition,
   lane 3).** The empty conditional conformance of `EnvironmentScope` stops
   compiling. The resolution goes through the same private helper as
   `requestGroupLayout`; a bare forward skips the layout push, and E11's layout
   slot (`proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`) is the
   test that sees it. The first pass's E11 read paint only and could not.
2. **`StateBinder.bind` (`MC-H` adds two call sites).** The old spelling is
   removed, so they fail to compile. **No default and no compatibility
   overload** may be added: either would bind the root environment silently.
3. **`FrameModifier.swift` deleted (modifier composition, lane 2).** D2's arms
   are spelled, not typed, so `ModifiedElement` is covered on arrival.
4. **`Frame.registerHandlers` (accessibility bridge).** Both tracks edit its
   body. Synthesis reads the ungated `handlers`; the `.disabled` trait is
   inserted after synthesis. D12 gains a collecting-frame arm for an undeclared
   disabled clickable. Resolved the other way, a disabled clickable publishes
   `isEnabled = true`.
5. **`Frame.init` and `Window`'s `Frame(...)` expression.** Avoided: no init
   parameter (`EV-H`).
6. **Two deferrals whose named owners do not take them** (`EV-Q`).

**Why.** A silent merge is this repo's recurring failure: a green suite over
unreachable code (the animation milestone's lexical-only transaction). The
tracks were designed apart, so only construction can make their seams loud.

**Cost if wrong.** A collision not listed here merges silently. The integration
step re-reads both tracks' final specs, not these design-time commits.

**Mutations.** None owed: the obligations are discharged at integration.

---

## Second pass — the critic's 18 findings

A critic reviewed `bbd4d66`, re-ran the scoping probe (output identical to its
header), built a P2g arm and a two-module key-path check, and read both parallel
tracks' design commits. Every finding is **applied**; none is rejected. Where a
finding offered alternatives, the choice and the reason are given.

| # | finding | disposition |
|---|---|---|
| 1 | `EV-E`'s "a disabled target swallows" is not what P2d–P2f measured; P2g blocks with no gesture | **Applied.** P2g/P2h added to the committed probe and re-run (both 0). `EV-E` restated as MetalUI's choice by analogy; D3 no longer cites P2f as alignment; `EV-R` item 6 |
| 2 | `\.self` bypasses read-only `pixelLength` and internal `theme` | **Applied** by re-stamping (`EV-U`), not by moving storage (reason in `EV-U`). Measurement re-run in this session. E19 added; G3 gains a `\.self` premise arm |
| 3 | Collision with modifier-composition lane 3 can fail silently | **Applied.** E11 records all three phases; `bind` loses its old spelling and never gains a default; `EV-W` items 1–2; spec's owed list |
| 4 | Collision with the AX bridge in `registerHandlers`, `Frame.init`, `Window`'s `Frame(...)` | **Applied.** Trait after synthesis (`EV-W` item 4); D12 collecting arm owed; the init parameter removed altogether (`EV-H`), so items 5's conflict does not arise |
| 5 | The environment is copied per element per phase; E15 cannot see it | **Applied.** `bind(_:in:id:)` snapshots only for types with `Environment` ordinals; `theme` and the gate read in place; E15 counts snapshots with a positive control, and the eager mutation reddens it (`EV-M`, `EV-O`). Allocation counting not adopted (`EV-O` cost) |
| 6 | Disabled does not suppress keys; K5/K6's control failed; D7+D9 route a disabled pane's shortcut to the window | **Applied, first option**: strip `onKey` and `keyContext` too (`EV-F`). The K harness was **also** fixed (parent-first order found), so the divergence rests on a moved control. D8 and D9 flipped; D7's fallback routing stated and pinned |
| 7 | The `$focus` slot bug gains an ordinary trigger | **Applied by gating** the slot write on `isEnabled` (narrower than the contract change the doc paragraph rules out); paragraph update owed by lane 3; D13 pins both arms |
| 8 | Nothing covers `.disabled` reaching into `Deferred` | **Applied.** D14 |
| 9 | Each transform runs three times per frame | **Applied.** `EV-V`; E20 |
| 10 | `LayoutDirection` in the wrong module | **Applied.** `MetalUICore` (`EV-K`); clean build noted |
| 11 | Inert list incomplete | **Applied.** `locale`, `pixelLength`, in-module root writes, unbound `@Environment` added to the owed rows; E21 pins `locale` |
| 12 | Two deferrals have no owner | **Applied.** Flagged unowned in `EV-Q` and the owed list |
| 13 | `FrameModifier.swift` deleted by the other track; site count wrong | **Applied.** D2 arms by spelling; five callers by grep (`EV-E`) |
| 14 | E18 is not a window capture; `cmp` will differ | **Applied.** E18 reads pixels against two disagreeing references; the capture compares regions after a base-vs-base calibration (`EV-P`) |
| 15 | Press while disabled, release after re-enabling fires `onClick` | **Applied as a fix**, not a record: probe R measured SwiftUI refusing it; derived blocker id (`EV-T`); D15, D16 |
| 16 | E1 mutation (a) cannot be built | **Applied.** Replaced with the buildable outermost-last composition in `scopedValues` |
| 17 | A no-op `Window.environment` write dirties | **Applied as a record**: constraining keys to `Equatable` rejected (`EV-H`); E14 pins the cost |
| 18 | An unbound `@Environment` returns the default silently | **Applied as documentation** on E8 and in `EV-M`; a diagnostic rejected (legitimate unbound reads are indistinguishable) |
