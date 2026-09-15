# Environment and control state — decisions (plan task 9)

These are the rulings for plan task 9 of
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`: evolve `Theme` into
scoped environment values, add a disabled control state, and clear the keymap's
`Binding` name for task 10.

Prefixed **`EV-`** and **lettered** (`EV-A`, `EV-B`, …). **A bare `EV-3` is a
typo, not a citation.** The next unused letter is `EV-T`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-environment-design.md` — the three lanes,
  their API, tests and mutations.
- `docs/record/11-environment.md` — what was measured, and where.
- The three probes this design stands on, whose headers carry their recorded
  output:
  - `docs/probes/swiftui-environment-scoping.swift` (arms A–H);
  - `docs/probes/swiftui-disabled-interaction.swift` (arms P, K);
  - `docs/probes/swiftui-environment-api-shape.swift` (compile-only).

## How to read the letters

**Written at design time, before any lane runs.** Every probe figure cited
below was taken in this design session (2026-09-14, macOS 26.6.2, Apple Swift
6.4) and is in a probe header; nothing is carried from a sentence.

- **`EV-A`…`EV-C`, `EV-L`, `EV-M`, `EV-O`** — the environment mechanism (lane 2).
- **`EV-D`…`EV-F`** — the disabled control state (lane 3).
- **`EV-G`…`EV-K`** — each value's source, phase and effect (lane 2).
- **`EV-N`** — the `Binding` rename (lane 1).
- **`EV-P`** — the Space-key theme swap and the window capture (lanes 2 and 3).
- **`EV-Q`** — what the probes found that this design does not implement.
- **`EV-R`** — how the probes run, and what their harness got wrong first.
- **`EV-S`** — what a SwiftUI claim in this track may and may not rest on.

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

**What.** `Frame` owns a stack of `EnvironmentValues`. Its bottom entry is the
**root environment**, built once per frame from `Window` (see `EV-H`). A writer
element (`EV-B`) applies its transform to a **copy of the top** and pushes it
around its content's phase call. It pops when the call returns. It does this in
**each of the three phases**, always in closure form (`Frame.withEnvironment`),
so an unbalanced push cannot be written. Every read is the top of the stack.

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
node. A value is copied only at a writer, never at a plain element. `EV-O`
counts that work.

**Why.** It is SwiftUI's observed behaviour (A0–A8), and a closure-scoped stack
is how this framework already scopes clip, layer, opacity and scroll context
(`PrepaintPass.clipped`, `LayoutPass.withScrollContext`). The design adds no
new kind of mechanism.

**Probe.** `swiftui-environment-scoping.swift` arm A. The positive control is
A0: with no writer, the view reads the key's default.

**Cost if wrong.** If SwiftUI resolved writers outermost-first, A2 and A4 would
be backwards. Every scoped value in this design would then read the outer
writer. The fix would be one line in `withEnvironment`, which would apply the
transform beneath the top instead of above it.

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
  compile. Write the scope outermost. Task 3's composition foundation owns
  modifier order.
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
- `public enum LayoutDirection` and `public enum DynamicTypeSize`, each with
  SwiftUI's cases.

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

## EV-E — a disabled click target SWALLOWS the click: one gate, in `Frame.registerHandlers`, reaches every site

**What.** In `Frame.registerHandlers`, when `environment.isEnabled` is false and
`handlers.isPointerTarget` is true, an opaque hitbox is still registered, but
with an **empty** `Handlers()`. `Window`'s click dispatch then finds that
hitbox topmost, reads `handlers.onClick == nil` and runs nothing. It already
does this for any hitbox with no handler (`Window.swift`, `hit.handlers.onClick`
guard).

`.allowsHitTesting(false)` is unchanged, and remains the pass-through spelling.

**One gate, six sites.** Every handler-registering element reaches it, because
all of them call `pass.registerHandlers`: `Box`, `Stack`, `Text`,
`FrameModifier` and `OnTapModifier`, with `Column`/`Row` through their inner
`Box`. `Component` reaches it through its members. A per-site test has one arm
per site (spec, lane 3). A raw `PrepaintPass.insertHitbox` call is **not** gated.
It is the low-level registration primitive, and an element that uses it reads
`pass.environment.isEnabled` itself.

**Why swallow rather than pass through.** Probe P2d–P2f:

- **Control P2d.** A clear overlay with no hit area passes the click to the view
  beneath.
- **Control P2e.** The same overlay with a `contentShape` and an enabled gesture
  takes the click.
- **Disabled P2f.** The overlay takes the click and runs nothing: over 0, under
  0.

The first P2 arm could not tell "disabled swallows" from "a `Color` blocks",
because control P2m showed an enabled gesture-less `Color` also blocks. That is
why P2d–P2f exist.

**What this costs, knowingly.** The blocker hitbox is an ordinary opaque hitbox,
so:

- `PaintPass.isHovered` answers `true` for a disabled element under the pointer.
  The `hoverBackground` chain will paint on it.
- `Window`'s press tracking can mark it `active`, although nothing built-in
  reads `isActive`.
- It swallows the wheel inside a `ScrollView`, which is divergence 16 unchanged.

SwiftUI's hover and pressed behaviour under `.disabled` is **unprobed**, so none
of this is claimed as aligned. See `EV-Q`.

**Probe.** Arm P of `swiftui-disabled-interaction.swift`.

**Cost if wrong.** If SwiftUI passed disabled clicks through, a disabled button
over a clickable card would click the card. Changing that is one line: skip the
hitbox instead of emptying it.

**Mutations.** _owed by lane 3._

## EV-F — keyboard: no focus acquisition, no action handlers; raw `onKey` and `keyContext` stay; a focused element that becomes disabled loses focus (a DIVERGENCE)

**What.** When `environment.isEnabled` is false, `Frame.registerHandlers` passes
the focus registry a copy of `handlers` with two changes:

- `isFocusable = false`;
- `actions = [:]`.

`onKey` and `keyContext` are left as they are. The `$focus` retention write and
`focusedElementProducedThisFrame` are unchanged: they stay keyed on "produced
this frame", not on focusability.

Consequences:

- **A disabled element cannot acquire focus.** `Window.focus(id)` on it is
  cleared at the next prepaint/paint boundary by the existing
  produced-but-not-focusable path. This matches probe K1.
- **A keymap `Action` bound to a disabled element's `onAction` does not claim
  the keystroke.** It bubbles outward, to an enabled ancestor or to
  `Window.onAction`. This is the analogue of K4, where a disabled Button's
  `.keyboardShortcut` does not fire.
- **A disabled ancestor's raw `onKey` still sees a key** that an enabled,
  focused descendant leaves unhandled. That descendant is reachable only through
  a raw `isEnabled = true` write. This matches K5/K6: the parent's
  `.onKeyPress` reads 1 whether or not the parent is disabled.
- **A disabled pane still contributes its `keyContext`.** This is MetalUI's
  choice, and SwiftUI has no directly comparable probe. It follows from the
  previous bullet: a context is scope, not control behaviour.
- **DIVERGENCE: a focused element that becomes disabled loses focus at once.**
  Probe K2 measured the opposite in SwiftUI. There, the view stays focused, its
  `.onKeyPress` keeps firing although it reads `isEnabled` 0, and it is still
  focused after re-enabling.

**Why diverge on K2.**

1. The task brief requires disabled to suppress focus.
2. K2 delivers keys to a control that reports itself disabled, which contradicts
   K4 inside SwiftUI itself.
3. Retaining focus needs a new signal. `Frame` would have to know that the id was
   focused **in the previous frame** and was not merely requested since.
   `Window.focus(_:)` writes the same `focusedElement` field either way. That is
   a change to the focus contract in `Frame`/`Window`, which task 12 owns
   ("disabled behaviour, keyboard focus"), not a patch this track should make in
   shared files.

**Probe.** Arm K of the disabled probe. Controls: K0 (enabled focus and key),
K3 (enabled shortcut), K5 (enabled parent). The K5/K6 child's own reading is 0
in both arms, including the control, and is recorded as unexplained. Nothing
here relies on it.

**Cost if wrong.** An app that disables a focused control while it works, for
example during a submit, loses focus and does not regain it on re-enable.
SwiftUI would restore it. The remedy is task 12's previous-frame focus signal,
plus flipping `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`.

**Mutations.** _owed by lane 3._

## EV-G — the theme becomes scoped and stays PAINT-ONLY; `Deferred` keeps its declaring scope

**What.**

- `Frame.theme` stops being a stored `let` and becomes `environment.theme`.
- `PaintPass.theme` keeps its spelling and now returns the **nearest** theme.
  Every existing reader is unchanged: `Box`, `Text` and `AnimatedColor` all read
  `pass.theme`.
- `EnvironmentValues.theme` is `internal`, so no pass exposes it and
  `@Environment(\.theme)` does not compile outside the module.
- `.theme(_:)` on `ElementGroup` is the only public writer.
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

At frame build, `Window` passes it to `Frame(…, environment:)`. `Frame` then
overwrites two fields in the root:

- `theme`, from the `theme:` parameter, which is `Window.theme`;
- `pixelLength`, as `1 / scaleFactor`, or 1 when the scale is not finite and
  positive.

A test-built `Frame` gets defaults for everything.

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
container ignore it.
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
The root is fixed before the frame starts, and a scope applies the same stored
transform in each phase.

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
  and in any phase by an element.
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
`StateBinder.bind` gains an `environment:` argument and seeds each `Environment`
it finds with a **copy** of that environment. Its per-type shape cache extends to
record `Environment` ordinals alongside `State` ordinals. The five existing call
sites pass `pass.frame.environment` (or the root environment in `Frame.render`):

- `ElementGroup.swift`, three sites;
- `Component.swift`, one site;
- `Frame.swift`, one site.

Each is a one-line edit.

`wrappedValue` reads the snapshot through the key path. It reads
`EnvironmentValues()`'s value if the box was never bound.

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

**Mutations.** _owed by lane 1._

## EV-O — environment work is counted, and scales with writers, not with their descendants

**What.** `Frame.environmentPushCount` is internal and test-only. It counts
pushes. A tree with no writer pushes 0 in a whole frame. A tree with W writers
pushes 3W (one per phase), whatever the size of the subtrees below them.
`registerHandlers`' `isEnabled` read is a stack-top read, not a push.

**Why.** "Not a CSS cascade" (`EV-A`) is a performance claim as well as a
semantic one, and this repo pins performance by counting work on a **branching**
tree, never by wall clock. `environmentWorkScalesWithWritersNotWithTheirDescendants`
is written first and is red on arrival: the counter does not exist.

**Cost if wrong.** A per-element copy of `EnvironmentValues` costs
roughly one Theme (32 floats) and some retains per element per phase. It is
invisible in a small tree and linear in a 500-row list.

**Mutations.** _owed by lane 2._

## EV-P — the Space-key theme swap is proven through the fake platform, and the demo is captured without input

**What.**

- **A test drives the swap.**
  `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` puts
  `KeyBinding("space", ToggleTheme())` on a fake window and flips `window.theme`
  in `onAction`. It sends one `keyDown` through `FakePlatformWindow.simulateInput`,
  draws, and reads the background rect's colour from `lastScene`: `Theme.light`
  before and `Theme.dark` after. This is the demo's wiring, minus the executable
  target, which tests cannot import.
- **The real demo is only captured.** At the end of lane 3 the release demo is
  launched at `f64e58a` and at the lane's commit, with **no input sent**, and each
  window is captured once. Both captures are compared and the comparison is
  recorded in `docs/record/11-environment.md`.

**Why no keystrokes into the real demo.** This track's rule is that input is
sent only through the fake platform, in tests. The theme's scoping change must
be invisible when no scope is written, and a capture at launch shows exactly
that.

**Cost if wrong.** A difference that shows only after a real Space press, in
AppKit's delivery path, is not covered. `MetalHostView`'s key path is not
touched by this track.

**Mutations.** _owed by lane 2_ (the test) and _lane 3_ (the capture).

## EV-Q — found by the probes, or required by the brief, and NOT done here

Each item names its owner.

| item | evidence | owner |
|---|---|---|
| RTL mirroring in any container (`EV-K`) | probe H | plan task 6 |
| Following the system's layout direction and locale, and locale changes while running (`EV-H`) | probe C cannot distinguish; needs a `PlatformWindow` requirement | platform seam, task 14 |
| `displayScale` (`EV-J`) | probe C, API shape | reopen if a reader needs it |
| An `appearance`/`colorScheme` value; the theme readable before paint (`EV-G`) | none | task 11 |
| `controlActiveState` (window key state), `controlSize` | probe C reads `inactive`, `regular` | task 12 |
| Focus retention when a focused element is disabled (`EV-F`) | probe K2 | task 12 |
| Hover and pressed on a disabled element; a disabled "look" (dimming) | **unprobed** | task 12 |
| Wheel scrolling under `.disabled` | **unmeasured**: the probe's enabled control failed (header "S") | task 10 |
| Scopes after `StyledElement` modifiers; a scope as window root or as `Deferred`/`List` element content (`EV-B`) | compile-time limits | task 3 |
| `@Environment` inside `AnyElement` (`EV-M`) | inherits `@State`'s inertness | task 8 |
| Reduce Motion as an environment key | plan task 13 | task 13 |
| Removing the `Binding` alias (`EV-N`) | — | task 10 |

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

**Why record it.** Rule 11 of the practices doc's taxonomy is a run that did not
happen and reported success. Each of these would have produced a plausible
"disabled blocks it" reading.

## EV-S — scope of SwiftUI claims in this track

**What.** A sentence in this track's code, tests or docs may say "SwiftUI does X"
only when a probe arm under `docs/probes/` measured X with a positive control
that could move. Everything else is stated as MetalUI's choice:

- `keyContext` under disabled;
- the AX `disabled` trait;
- the hover consequences of `EV-E`.

The unexplained K5/K6 child reading is not cited as evidence of anything.
