# Environment and control state — decisions (plan task 9)

These are the rulings for plan task 9 of
`docs/superpowers/plans/2026-09-12-swiftui-alignment.md`: evolve `Theme` into
scoped environment values, add a disabled control state, and clear the keymap's
`Binding` name for task 10.

Prefixed **`EV-`** and **lettered** (`EV-A`, `EV-B`, …). **A bare `EV-3` is a
typo, not a citation.** The next unused letter is `EV-AA`.

Read alongside:

- `docs/superpowers/specs/2026-09-15-environment-design.md` — the three lanes,
  their API, tests and mutations.
- `docs/record/11-environment.md` — what was measured, and where.
- The five probes this design stands on, whose headers carry their recorded
  output (the disabled probe re-run in the second pass; the last two added in
  the third):
  - `docs/probes/swiftui-environment-scoping.swift` (arms A–H);
  - `docs/probes/swiftui-disabled-interaction.swift` (arms P, K, R);
  - `docs/probes/swiftui-environment-api-shape.swift` (compile-only);
  - `docs/probes/swiftui-disabled-ancestor-and-order.swift` (arms N, O);
  - `docs/probes/swiftui-environment-pixel-length.swift` (arms V, X).

## How to read the letters

**Written at design time, and revised twice.** Every probe figure cited below
was taken in a design session (2026-09-14 and 2026-09-15, macOS 26.6.2, Apple
Swift 6.4) and is in a probe header; nothing is carried from a sentence. A
critic review of the first pass (`bbd4d66`) found 18 defects; the "Second pass"
section applies or rejects each. After lanes 1 and 2 landed, a second critic
review (of `f4dcad8`) found 11 more; the "Third pass" section at the end
applies or rejects each. The rulings below are already amended.

- **`EV-A`…`EV-C`, `EV-L`, `EV-M`, `EV-O`, `EV-U`, `EV-V`** — the environment
  mechanism (lane 2; `EV-C`'s G6 and `EV-U`'s relabel land in lane 2b).
- **`EV-X`, `EV-Y`, `EV-Z`** — modifiers written after a scope, what
  `EnvironmentValues()` holds, and the sealed root (lane 2b; third pass).
- **`EV-D`…`EV-F`, `EV-T`** — the disabled control state (lane 3).
- **`EV-G`…`EV-K`** — each value's source, phase and effect (lane 2).
- **`EV-N`** — the `Binding` rename (lane 1).
- **`EV-P`** — the Space-key theme swap (lane 2) and the window capture (lane 4).
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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E1(a), outer writer wins** (`scopedValues` starts from `rootEnvironment`, applies the new write first and the enclosing writes after it, outermost last): 5 issues in 4 tests. `theNearestWriterWinsAndAScopeEndsWithItsSubtree` reads `[0, 1, 1, 1, 1, 1, 0]` (the A2 and A4 slots read 1, as predicted); `aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt` reads A8 = 105; `anEnvironmentValueReadsIdenticallyInAllThreePhases` inner `[1, 1, 1]`; `aWholeValueWriteCannotResetTheThemeOrThePixelLength` probe 3 on both arms (`:615`, `:629`).
- **E1(b), `withEnvironment` without its restoring `defer`**: 4 issues in 3 tests. E1 reads `[2, 1, 2, 1, 2, 2, 2]` (A6 non-zero); E3 sibling and outside read `[2, 2, 2]`; `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope` paints the unscoped 11pt box dark.
- **E2, `scopedValues` starts from `rootEnvironment`**: 1 issue, only `aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt`: `[10, 5]`.

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

- A scope is not a `StyledElement`, so `X().disabled(true).padding(4)` and
  `X().theme(.dark).onClick {}` do not compile. **The first two passes said no
  modifier can follow a scope, and that was already false at `f64e58a`**
  (third pass, critic finding 7, measured in record 11): `.frame(width:height:)`
  is declared on `ElementGroup` and returns a `StyledElement`, so
  `X().environment(\.probe, 1).frame(width: 20, height: 20).padding(4).onClick {}`
  and `X().theme(.dark).frame(width: 20, height: 20).background(.surface)`
  typecheck today. After the modifier-composition merge `.frame` returns
  `ModifiedElement<LayerBase>` and still compiles. What such a modifier means
  is `EV-X`: it sits **outside** the scope, as SwiftUI's does (O2, O3, O6).
  `.padding` and handler modifiers directly on a scope stay a compile-time limit
  on both branches (the composition track's `padding` is still a `StyledElement`
  extension), unowned until the integration step assigns it (`EV-Q`, `EV-W`).
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

**Proposal path (third pass, critic finding 5).** E4, E5 and E10 exercise only
legacy content. Today one `requestGroupLayout` serves both paths, so they cover
the proposal path too; after the modifier-composition merge the proposal path
has its own typed entry, hand-written at integration, and a `cursor += 1` or a
fresh child id there would redden none of them. Lane 2b adds E22 (node count
and ids through `HStack`) and E23 (a proposal `@State` counter across a value
change); their mutations are run once here against the shared entry, to prove
the instruments can see, and **re-run by the integration step against the typed
entry**, which is the coverage that matters (`EV-W` item 1).

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E4(a), the scope wraps its content's nodes in one node.** First as `requestNode(style: Style(), children:)`: E4 reddened, and then the run **died with no summary line** at `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` on SA-G's trap ("legacy layout node given a native child") — a truncated run, not a count. Re-run wrapping native content in `requestNativeOverlay` instead: 1112 tests, 1 issue, only `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex` (`:272`, the row has 2 children, not 3).
- **E4(b), `cursor += 1` before forwarding**: 4 issues in 2 tests — E4's A, B and C ids move (`:276`, three issues) and `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState` reads 1, not 3 (`:371`).
- **E4(c), forward under `.child(of: parent, at: cursor, name: nil)` with a fresh cursor**: the same 4 issues in the same 2 tests.
- **E5, a value-keyed writer.** The spec's spelling — an `Equatable` overload of `environment(_:_:)` returning `EitherGroup` — **does not compile against this test file** (`EitherGroup` has no `content`, and is not `ProposalElementGroup`), so nothing ran. Second attempt, an `EitherGroup`-shaped branch inside the scope keyed on `String(describing:)` of the scope's values against the top's: **a broken instrument** — E5 stayed green while E4 and E10 reddened, because a write that stores `probe = 0` adds a custom-key entry, so the two descriptions always differ and the branch never flips. Third, the id keyed by the scope's values (`.named("value:" + String(describing: values))`): 5 issues in 3 tests — `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` reads 0, not 2 (`:347`), plus E4's three ids and E10's count. That is the one E5 was written for.

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`). Each guard printed `failed` under its mutation, so each ran:

- **G1+, `LayoutPass.environment` made internal**: `environmentValuesAreReadableInEveryPhase` fails (`succeeded` false), and `theThemeIsNotReachableThroughTheEnvironment` fails too — its pass fixture's message became `'environment' is inaccessible`, not `'theme' is inaccessible` (`EnvironmentCompileGuards.swift:136`), which is the stronger message assertion doing its job.
- **G2, `PaintPass.environment` given a `nonmutating set` that writes the top**: `environmentValuesCannotBeWrittenThroughAPass` fails on both `!succeeded` (`:162`) and the message (`:164`).
- **G4+, the conditional `ProposalElementGroup` conformance deleted**: the test target no longer compiles, because E11 and E17 place scopes in proposal containers. Re-run with those two tests compiled out (`#if false`; 1110 tests): `aProposalContainerAcceptsAScopeOverProposalContent` fails (`:214`), nothing else.
- **G4−, the conformance made unconditional**: `aProposalContainerRejectsAScopeOverLegacyContent` fails on both `!succeeded` and the message (`:230`, `:232`).

The messages are matched on longer strings than the spec's (`'theme' is inaccessible`, `'environment' is a get-only property`) because a first draft of G1+ showed a nonisolated fixture struct is rejected with a note naming `_theme`; see record 11, lane 2.

**The writers were not pinned public (third pass, critic finding 4).** Every
test above except G1+–G4 is `@testable`; G1+ only reads, and G3/G4 spell only
`.environment(_:_:)`. So `.theme(_:)`, `.transformEnvironment`,
`.dynamicTypeSize(_:)`, `Window.environment`'s setter,
`DynamicTypeSize.isAccessibilitySize`, and the setters of `isEnabled`,
`layoutDirection`, `locale` and `dynamicTypeSize` could each be narrowed with
the suite green (shape 16). **Lane 2b adds G6,
`theEnvironmentsPublicWritersCompileFromOutsideTheModule`**: a plain-import,
Swift 6 fixture that calls each modifier, writes each settable field through
`.environment(\.field, …)` and through a `var e = EnvironmentValues()` member
assignment, sets `window.environment` and one of its fields, subscripts a custom
key, and reads `isAccessibilitySize`. Lane 3 adds `.disabled(true)` to the same
fixture. **Mutations owed by lane 2b**, each alone, each must print `failed`
for G6: (a) `.theme(_:)` made internal; (b) `locale` given `internal(set)`;
(c) `Window.environment` given `internal(set)`. Lane 3 owes (d): `.disabled`
made internal.

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

## EV-E — a disabled click target REGISTERS NO HITBOX: its click reaches an enabled ancestor, and what is under it; one gate, in `Frame.registerHandlers`, reaches every site

**Third pass: this ruling was inverted.** The first two passes kept the
disabled target's region as an opaque hitbox with empty handlers, "by analogy"
to P2f. A critic's probe, now committed as
`swiftui-disabled-ancestor-and-order.swift` arm N, measured the case this
ruling's own "Cost if wrong" named and never measured: **a disabled child does
not block its enabled ancestor's tap in SwiftUI** (N1 parent 1 for a disabled
gesture, N2 parent 1 for a disabled `.plain` Button; the controls N0 and N3 move
the other way, child 1 and parent 0). The blocker made `dispatchClick` find a
hitbox with no `onClick` topmost, so the card's `onClick` never ran. The old
text is superseded; its reasoning is kept below only where it still holds.

**What.** In `Frame.registerHandlers`, when `environment.isEnabled` is false,
**no hitbox is registered** for the element, whatever its handlers. `Window` is
not edited. At a point over a disabled target, `topmostOpaqueHitbox` answers
with whatever enabled target lies beneath it in the hitbox list: an enabled
ancestor with an `onClick`, an enabled sibling drawn under it, or nothing.

`.allowsHitTesting(false)` is unchanged, and a disabled target now behaves like
it for the pointer.

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

**Why no hitbox — aligned towards ancestors, a pre-existing difference towards
siblings.**

- **Ancestors: aligned, measured.** N1 and N2 read parent 1; N4 (a child with no
  gesture at all) reads parent 1 too. So towards its ancestors a disabled
  gesture behaves like no gesture. In MetalUI an element with no `onClick`
  registers no hitbox, and a click over it reaches the enabled ancestor's
  hitbox; registering none for a disabled element is exactly that. With the
  child enabled, the child's hitbox is topmost and the ancestor does not run
  (`dispatchClick` does not bubble), which is N0/N3.
- **Siblings underneath: a DIVERGENCE, and not a new one.** SwiftUI's
  hit-testability belongs to the **shape**: P2g (an enabled clear overlay with a
  `contentShape` and no gesture) and P2m (an enabled gesture-less `Color`)
  already block a sibling under them, and P2f/P2h block disabled or not. A
  MetalUI element has no shape apart from its `onClick`, so an enabled `Box`
  with no `onClick` over a clickable sibling **already** lets the click through
  where SwiftUI's `Color` blocks. A disabled target passing the click to the
  sibling under it is that same pre-existing difference, reached through
  `.disabled`. Emulating SwiftUI for both cases at once needs a hit shape
  separate from `onClick` (a contentShape analogue), which is a change to the
  hitbox model and out of this track (`EV-Q`).
- **The rejected alternative, the blocker, got the aligned case wrong to get the
  divergent one right**: it blocked the ancestor (against N1/N2) so that it could
  block the sibling (P2f, by analogy). Of the two, a card whose disabled button
  eats the card's click is the visible failure; a disabled overlay letting a
  click through to what it covers already happens for every non-clickable
  overlay in MetalUI.

**What else follows.**

- **Not hovered, not pressed, no derived id.** `isHovered(id)` and `isActive(id)`
  compare against the id of the hitbox under the pointer, and a disabled
  element has none, so its `hoverBackground` does not paint and `isActive` reads
  false (`EV-T`). The second pass's `$disabled` derived id, and the reserved
  suffix it would have added, are gone. An enabled ancestor under the pointer
  **is** hovered and pressed, as it would be over any non-clickable child.
- **No wheel swallowed.** A disabled `onClick` inside a `ScrollView` no longer
  swallows the wheel over its rect: divergence 16 needs a hitbox, and there is
  none. SwiftUI's wheel under `.disabled` stays unmeasured (`EV-Q`).
- **The press/release rule still holds** (`EV-T`): probe R's R1 and R2 still
  fail `dispatchClick`'s `hit.id == pressed`.

**Probe.** `swiftui-disabled-ancestor-and-order.swift` arm N (N0, N3, N4 are the
controls); `swiftui-disabled-interaction.swift` P2c–P2h and P2m, read as
evidence about the shape, which MetalUI does not have.

**Cost if wrong.** If a disabled target should block what is under it, a
disabled overlay lets a click through to the sibling it covers. Registering a
blocker restores that and breaks N1/N2 again; doing both needs a shape concept.
The pins that flip are `aDisabledClickTargetPassesTheClickToWhatIsUnderIt`'s
two arms, in opposite directions.

**Mutations.** _owed by lane 3_: (a) register a blocker hitbox with empty
`Handlers()` under a derived id (the second pass's design) → D3's ancestor arm
reads parent 0 and its sibling arm under 0; (b) the same blocker under the
element's own id → additionally D15's R1 reads 1 and D16 paints `.accent` with
`isActive` true; (c) register the hitbox with the element's own handlers when
disabled (delete the gate) → every D2 arm fires.

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E12(a), `Frame.theme` returns `rootTheme`**: 4 issues in 2 tests — `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope` paints the 10pt and 12pt boxes light (`:504`, `:506`), and `aWholeValueWriteCannotResetTheThemeOrThePixelLength` paints both arms light.
- **E12(b), `PaintPass.deferred` sets the top to `rootEnvironment` around its body**: 1 issue, only the `Deferred` arm (`:506`).
- **G1−, `EnvironmentValues.theme` made public**: `theThemeIsNotReachableThroughTheEnvironment` fails four ways — both fixtures compile (`:134`, `:145`) and neither message holds (`:136`, `:147`).

## EV-H — root values and defaults: `Window.environment`, plus the theme and the surface's scale

**What.** `Window.environment: EnvironmentValues` is public and settable, and its
`didSet` marks the window dirty. It defaults to `EnvironmentValues()` with the
locale stamped (`EV-Y`, third pass; a bare `EnvironmentValues()` holds
`Locale(identifier: "")`):

- `isEnabled` true;
- `layoutDirection` `.leftToRight`;
- `locale` `Locale.current` (stamped by `Window`, not by `init`);
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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E13(a), the root ignores `theme:`** (neither `init` nor the setter stamps it): 128 issues in 17 tests, most of them the theme and colour-animation tests that construct `Frame(theme: .dark)`. In this file: `theFramesRootEnvironmentCarriesItsThemeAndScale` (`:520`, `:533`) and `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform`, whose `try #require(lightRef != darkRef)` stopped it (`:568`, both `[247, 245, 245, 255]`) — **not** at `after == lightRef`, as the spec predicted: a dark reference window renders light too, and the require is what sees it. Also `theSevenRetentionSlotsAreMutuallyDistinct` (`AXNodeTests.swift:494`, a dark-theme colour read) and `ThemeTests`' three wiring tests.
- **E13(b), `pixelLength = Double(scaleFactor)`**: 4 issues in 2 tests — E13 reads 2.0 (`:521`, `:534`) and E19 reads 2.0 on both arms.
- **E13(c), the `rootEnvironment` setter does not re-stamp**: 17 issues in 4 tests — E13 (`:520`, `:533`), E18, `aColourFadeOnAStyleStaticElementKeepsTheDisplayLinkRunning` and `aHostAppearanceChangeSwapsTheThemeAndRepaints`: through a real `Window`, the root then takes `EnvironmentValues()`'s light theme whatever `Window.theme` says.
- **E14(a), no `didSet` on `Window.environment`**: 3 issues, only `theWindowsEnvironmentReachesTheFrameAndASetRepaints` (`:660`, `:662`, `:667`).
- **E14(b), `drawFrameIfNeeded` omits `frame.rootEnvironment = environment`**: 1 issue, the same test, the recorder reads `en_US` (`:662`).
- **E14(c), skip dirtying when the four built-in fields compare equal**: 1 issue, the same test, the no-op arm (`:667`).
- **E21, `Text` routes `pass.environment.locale` into a line-break tokenizer for its min-content width** (a fresh `CFStringTokenizer` created with that locale, bypassing the memo). The first spelling did not compile (`CFLocaleIdentifier`), so nothing ran; the corrected one ran: **`aLocaleChangesNoTextMeasurement` stayed green — the mutation is void for it**, and is recorded as such rather than banked as coverage. Under the mutation the Thai sample's widest line-break run measured the same under `th_TH`, `en_US` and the default locale on this machine (whether the runs themselves were identical was not examined). The one test that reddened was `aColdFrameCreatesAtMostOneLineBreakTokenizer` (`MeasurePerformanceTests.swift:94`, 0 counted calls against 40), because the bypass skips `Shaper.runCallCounter`. So E21 pins that no locale reaches measurement today, and cannot say whether one would move it.

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E16, `Text` measures at `fontSize * 1.5` when `pass.environment.dynamicTypeSize.isAccessibilitySize`**: 2 issues, only `dynamicTypeSizeChangesNoTextMeasurement` (max 169.38 against 119.67, `:798`; min 73.02 against 51.07, `:799`). Reverted.

## EV-J — platform metrics: `pixelLength` is exposed read-only and tied to the device; `displayScale` is NOT exposed (two divergences)

**What.** `EnvironmentValues.pixelLength` is `public internal(set)`, measured in
points, one device pixel wide. There is no `displayScale`.

**Why read-only — corrected in the third pass.** SwiftUI's `pixelLength` is
get-only: the API-shape probe rejects both `e.pixelLength = 1` and
`.environment(\.pixelLength, 1)`. The first two passes went on to say "a
writable one could lie about the device", and implied SwiftUI's cannot. **That
is false, measured** (`swiftui-environment-pixel-length.swift`): SwiftUI's
`pixelLength` is derived from `displayScale`, which **is** writable, so
`.environment(\.displayScale, 3)` on a 2x display reads `pixelLength` 1/3 (X1,
control X0 0.5), and a whole-value `\.self` write resets it to 1 (X2). In
SwiftUI a scope can make `pixelLength` disagree with the device.

MetalUI's `pixelLength` has **no writable source**, because there is no
`displayScale` (below), so it is stamped from the surface's scale factor and
re-stamped after every write (`EV-U`). Two consequences, each a **divergence**
from X1/X2, not an alignment:

- no scope can change `pixelLength` (SwiftUI: a `displayScale` write does);
- a `\.self` reset does not reset it (SwiftUI: X2 reads 1 on a 2x display).

**Read-only is enforced at run time, not only by access control.**
`.environment(\.self, EnvironmentValues())` and
`.transformEnvironment(\.self) { $0 = captured }` compile outside the module
and would reset it to 1 (measured with a two-module stand-in; record 11, "Second
pass"). `EV-U` re-stamps it after every public write, and G3's positive half
records that the compiler cannot close the route.

**No internal reader.** Nothing in `MetalUI` reads `pixelLength`; it exists for
element authors. An inert row owed to the integration step.

**Why no `displayScale`, although SwiftUI's is readable and writable (X1).**
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

**Probe.** `swiftui-environment-api-shape.swift` (get-only), scoping probe C
(pixelLength 0.5 at scale 2.0), and `swiftui-environment-pixel-length.swift`
X0–X2 (derived from a writable `displayScale`; reset by `\.self`) with control
V1 (a bare value at `displayScale` 4 reads 0.25).

**Cost if wrong.** An author who needs the scale computes `1 / pixelLength`.
An author who wants a subtree drawn as if at another scale (SwiftUI's
`displayScale` write, X1) cannot. Adding a writable `displayScale` later means
deriving `pixelLength` from it and dropping `pixelLength` from `EV-U`'s
re-stamp, which flips E19's `pixelLength` half; the double-scaling hazard above
is the argument that change must answer.

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E13(b), `pixelLength = Double(scaleFactor)`**: see `EV-H` — E13 and E19 read 2.0.
- **G3(a), `pixelLength`'s setter made public**: `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles` fails on the negative half — it compiles (`:187`) and the message is empty (`:189`).
- **G3(b), `EnvironmentValues.init` made internal**: the same test fails on the positive premise only (`:198`).

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E3, `EnvironmentScope.prepaintGroup` forwards without `withEnvironment`**: 14 issues in 5 tests. `anEnvironmentValueReadsIdenticallyInAllThreePhases` reads inner `[2, 0, 2]`, sibling `[1, 0, 1]`; also E6 (`[[3], [0], [3]]`), E11 (both arms `[7, 0, 7]`), E15 (pushes 2 and 4, not 3 and 6) and E20 (`[1, 0, 1]`, then `[2, 0, 2]`).
- **E3, the same in `paintGroup`**: 24 issues in 10 tests — every paint-read test in the file (E1, E2, E3 `[2, 2, 0]`, E6, E7, E11, E12, E19, E15, E20). Recorded separately, as the spec asks.

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
It builds `EnvironmentValues()` on each access (which, after lane 2b, reads
locale '' rather than `Locale.current`, `EV-Y`).
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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E6(a), `Environment.bind` skips when the box already holds a snapshot**: 2 issues — `anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame` frame 2 reads `[[3], [3], [3]]` (`:396`), and `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint` reads `[1, 1]` (`:410`).
- **E6(b), `Element.prepaintGroup` binds with the top set to `rootEnvironment`**: 3 issues in 2 tests — E6 reads `[[3], [0], [3]]` and `[[4], [0], [4]]`, and E15's no-writer push count reads 84 (the mutation pushes; not what E15 is for).
- **E6(c), the re-bind in `Element.paintGroup` deleted**: **E6 stayed green, as predicted** — paint reads the layout snapshot, which cannot differ within a frame; that is E6's limit, not coverage. It reddened `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint` (`[2, 2]`, `:410`) and E15's reader snapshots (2, not 3, `:728`). No `@State` test reddened.
- **E9, `Component.requestGroupLayout` binds with the top set to `rootEnvironment`**: 1 issue, only `aComponentReadsTheNearestEnvironmentInItsContent` (`:454`, the scoped arm paints `.surface`).
- **E11(b), `EnvironmentScope.requestGroupLayout` forwards without `withEnvironment`**: 18 issues in 8 tests, including `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`'s **layout slot** (`[0, 7, 7]` on both arms) — the slot a bare forwarding `requestProposalGroupLayout` would empty (`EV-W`). Also E2, E3, E6, E9, E15, E19 and E20.
- **E8** (`AnyElement`) is pinned inert and carries no mutation.

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E15(a), `Element.requestGroupLayout` wraps `requestLayout` in `withEnvironment(environmentTop)`**: 1 issue, `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants` — the 4×5×3 tree's no-writer push count reads 84 (`:709`), so the `try #require` stops before the small tree is compared.
- **E15(b), eager snapshot** (`bind` calls `frame.environmentSnapshot()` before consulting the shape): 1 issue, the same test — the no-reader snapshot count reads 253 (`:710`).
- Also reddened by: E3's two phase mutations and E11(b) (push counts), E20's (transform counts) and E6(c) (reader snapshots).

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
- **The real demo is only captured.** At the end of lane 3 (as lane 4, third pass) the release demo is
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

**Mutations** (lane 2, the test; the capture is _owed by lane 4_, third pass). `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` reddened under E13(a), E13(c) and E18's own mutation (`Frame.theme` computed from `EnvironmentValues().theme`, 132 issues in 19 tests), each time at the `try #require(lightRef != darkRef)` (`:568`), never at `after == lightRef`: every mutation that turns the post-swap frame light turns the dark reference light too, so the require is the reading. The `after` expectation has no mutation of its own that leaves the references apart; breaking the key path would be a keymap mutation, outside this track.

## EV-Q — found by the probes, or required by the brief, and NOT done here

Each item names its owner, or says it has none. **"Unowned" means the owner this
design first named does not, on reading that track's spec, take it**; the
integration step assigns it (`EV-W`).

| item | evidence | owner |
|---|---|---|
| RTL mirroring in any container (`EV-K`) | probe H | plan task 6 |
| Following the system's layout direction and locale, and locale changes while running (`EV-H`) | probe C cannot distinguish; needs a `PlatformWindow` requirement | platform seam, task 14 |
| A consumer for `locale` (tokenizer, typesetter, number formatting) (`EV-H`) | none measured | none named; inert row |
| `displayScale`, and a `pixelLength` a scope can change (`EV-J`, `EV-U`: two divergences) | probe C, API shape, pixel-length X1/X2 | reopen if a reader needs it |
| An `appearance`/`colorScheme` value; the theme readable before paint (`EV-G`) | none | task 11 |
| `controlActiveState` (window key state), `controlSize` | probe C reads `inactive`, `regular` | task 12 |
| Focus retention when a focused element is disabled (`EV-F`) | probe K2 | **unowned**: named task 12, but the AX-bridge spec says disabled behaviour waits for task 9 |
| Raw key handlers on a disabled element (`EV-F` divergence 1) | probe K2, K6 | **unowned**, same reason |
| Key handler ORDER: SwiftUI runs an ancestor's `.onKeyPress` before the focused view's; MetalUI bubbles outward from the focused element | probe K5, K7 | **unowned**; a pre-existing difference, not introduced here |
| A disabled "look" (dimming) | **unprobed** | **unowned**, same reason as focus retention |
| Wheel scrolling under `.disabled` | **unmeasured** in SwiftUI: the probe's enabled control failed (header "S"). MetalUI: a disabled target registers no hitbox, so it swallows no wheel (`EV-E`) | task 10 |
| A hit shape separate from `onClick`, so a disabled (or any non-clickable) overlay can block a sibling under it as SwiftUI's shape does (`EV-E` sibling divergence) | P2f, P2g, P2m | **unowned**; a pre-existing difference of the hitbox model |
| `.padding` and handler modifiers written directly on a scope (`EV-B`, `EV-X`). `.frame(width:height:)` already follows a scope, and any `StyledElement` modifier after it | compile-time limit; typecheck in record 11, third pass | **unowned**: named task 3, but the modifier-composition spec never mentions `EnvironmentScope` |
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

7. **A named cost never measured (third pass).** `EV-E`'s "Cost if wrong"
   named "a disabled button over a clickable card blocks the card" and no arm
   measured it; P2 measured only siblings. A critic's scratch arm did, and the
   ruling inverted (arm N). The lesson is the practices doc's shape 14: the
   case a ruling names as its own risk is the first one to probe.
8. **Hosted defaults read as the value's defaults (third pass).** Probe C read a
   hosted window's environment, and the `EnvironmentValues.init` doc said its
   defaults "match probe C". A bare `EnvironmentValues()` holds locale '' and
   `pixelLength` 1 (`swiftui-environment-pixel-length.swift` V0/V2): the host
   stamps the rest. `EV-Y`.
9. **Compiled with two toolchains (third pass).** `swiftc` on this machine's
   `PATH` is a swift.org 6.3.3 toolchain (swiftly), not Apple's. The two
   third-pass probes were run with `/usr/bin/swift`, `/usr/bin/swiftc` (Apple
   6.4) and that `swiftc`; all three filtered outputs were byte-identical. Earlier
   headers that say "`swiftc`" name whichever resolved at the time.

**Why record it.** Rule 11 of the practices doc's taxonomy is a run that did not
happen and reported success. Each of these would have produced a plausible
"disabled blocks it" reading.

## EV-S — scope of SwiftUI claims in this track

**What.** A sentence in this track's code, tests or docs may say "SwiftUI does X"
only when a probe arm under `docs/probes/` measured X with a positive control
that could move. Everything else is stated as MetalUI's choice:

- `keyContext` under disabled (SwiftUI has no comparable concept);
- the AX `disabled` trait;
- a disabled target passing a click to an enabled **sibling** under it (`EV-E`:
  a divergence from P2f/P2m, inherited from MetalUI's shape-less hitboxes; the
  **ancestor** half is measured alignment, arm N);
- a disabled target being neither hovered nor pressed (`EV-T`), and an enabled
  ancestor under the pointer being hovered and pressed;
- an unclaimed action from a disabled element reaching `Window.onAction` (`EV-F`);
- `locale` affecting no measurement (`EV-H`).

Divergences are claims too: D6 and D8 may cite K2 and K6 because those arms'
controls (K0, K5) moved.

## EV-T — a click needs its target enabled at press AND at release; a disabled target is neither hovered nor pressed

**Third pass.** The second pass reached these consequences by registering the
`EV-E` blocker under a derived id (`$disabled`). `EV-E` now registers **no
hitbox** for a disabled target, which reaches all of them with no id at all, so
the derived id and the reserved suffix it minted are withdrawn (critic findings
1 and 10). `Window` is still not edited.

**What, through the unchanged `Window` code:**

- **Pressed disabled, released enabled → no click.** `mouseDown` over the
  disabled target makes `active` whatever enabled hitbox lies under it (an
  ancestor, a sibling beneath) or `nil`. The next frame re-registers the element
  with its `onClick`; the release lands on it, and `dispatchClick` requires
  `hit.id == pressed`, which fails (or `pressed` is `nil` and it returns at
  once). With an enabled clickable ancestor, the ancestor does not fire either:
  the release's hitbox is the child's.
- **Pressed enabled, released disabled → no click for the target.** `pressed` is
  the target's id; the release's topmost hitbox is someone else's, or there is
  none. (With an enabled ancestor under the release, `hit.id` is the ancestor's
  and still differs from `pressed`: nothing fires.)
- **Not hovered, not pressed.** `isHovered(id)` and `isActive(id)` compare with
  the id of a registered hitbox, and the disabled element registered none, so a
  disabled element's `hoverBackground` does not paint and `isActive` reads
  false. An enabled ancestor under the pointer reads hovered, as it does over
  any child without an `onClick`.
- **The accessibility bridge's `.press` refuses a disabled element** without an
  edit: it looks for a `lastHitboxes` entry with the element's id and an
  `onClick`, and there is no entry (`EV-W` item 4).

**Why.** The first pass's blocker, registered under the element's own id, let a
press made while disabled click on a release after re-enabling
(`Window.swift`, `dispatchClick`'s `hit.id == pressed` guard). Probe R measured
SwiftUI: R1 (pressed disabled, released enabled) reads 0 and R2 (the reverse)
reads 0, for a plain `Button` and for `.onTapGesture`, with R0 (enabled at the
same timing) reading 1. The alternatives were:

- **Record it as a divergence.** Rejected: registering nothing is already what
  `EV-E` needs.
- **Set `active` only for hitboxes with an `onClick`.** Rejected: scroll regions
  and raw `PrepaintPass.insertHitbox` calls register opaque hitboxes with no
  `onClick`, so it would change `isActive` for them, in `Window.swift`, a shared
  file.

The hover and pressed half is **not** probe-backed (`EV-S`); SwiftUI's hover
look under `.disabled` is unprobed. It is kept because a `hoverBackground`
lighting up on a control that ignores the click reads as a live control.

**Probe.** Arm R of `swiftui-disabled-interaction.swift`.

**Cost if wrong.** If a disabled element should show hover, it needs a hitbox
that runs nothing, and then the R1 guard must move into `Window`
(`dispatchClick` or `updatePointerState`), and N1/N2's ancestor must still be
reachable through it; `aDisabledTargetIsNeitherHoveredNorPressed` flips.

**Mutations.** _owed by lane 3_: register a hitbox with empty `Handlers()` under
the element's own id for a disabled target → `aClickNeedsTheTargetEnabledAtPressAndAtRelease`
R1 reads 1, and `aDisabledTargetIsNeitherHoveredNorPressed` paints `.accent`
with `isActive` true (and D3's ancestor arm reads parent 0).

## EV-U — `theme` and `pixelLength` are re-stamped after every public write, so `\.self` cannot reset them (the `pixelLength` half is a DIVERGENCE)

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

**The two halves are not the same kind of claim (third pass, critic finding 3).**

- **`theme` is MetalUI's own key.** SwiftUI has no `theme`; `EV-G` makes
  `.theme(_:)` its only writer, and the re-stamp is what makes that true. A
  choice, not a divergence.
- **`pixelLength` is SwiftUI's key, and resetting it to 1 on a Retina display is
  exactly what SwiftUI does**: `swiftui-environment-pixel-length.swift` X2 reads
  `pixelLength` 1.0 and `displayScale` 1.0 under
  `.environment(\.self, EnvironmentValues())` on a 2x display (control X0: 0.5).
  So this half is a **divergence**, and the first two passes presented it as
  protection without saying so, against `EV-S`. It is kept, because MetalUI has
  no `displayScale` for a reset `pixelLength` to agree with (`EV-J`): after the
  reset every hairline drawn with `fill(… width: pixelLength)` would be two
  device pixels wide on a 2x surface while `PaintPass` still scales by 2. In
  SwiftUI the reset changes the scale rendering uses as well; here it would
  change only the number. The divergence text is owed to CLAUDE.md
  (spec, "Owed to the integration step").

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
the theme through `\.self`; they write `.theme(.light)`. A port of SwiftUI code
that resets the environment with `\.self` keeps the device's `pixelLength` where
SwiftUI would read 1; the pin that flips is E19's `pixelLength` half.

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E19, the two re-stamping assignments in `scopedValues` dropped**: 4 issues, only `aWholeValueWriteCannotResetTheThemeOrThePixelLength` — both arms paint light and read `pixelLength` 1.0 (`:613`, `:614`, `:627`, `:628`).
- **G3(b)**'s premise half (see `EV-J`) records that the `\.self` route compiles.

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

**Mutations** (lane 2, 2026-09-15, each run alone on a `--build-system native` build in this worktree against the full suite — 1112 tests, every run printed its summary line unless said otherwise — and restored with `git checkout` before the next; `EnvironmentTests.swift` line numbers are at `a4ef92d`):

- **E20, `prepaintGroup` pushes `scopedValues(applying: write)` instead of `layout.values`**: 10 issues in 2 tests — `eachScopesTransformRunsOncePerFrame` reads `counter.n` 2 after frame 1 and `[1, 2, 1]` (`:757`, `:758`), 4 and `[3, 4, 3]` after frame 2, transform count 2 per frame; and E15's transform counts read 2 and 4.

## EV-W — collisions with the parallel tracks: which are loud, which are SILENT, and what the integration step must do about each

**What.** This track is merged with `feat/modifier-composition` and
`feat/ax-bridge`. **Third pass (critic findings 2, 6, 9):** the second pass wrote
this list against those tracks' *design* commits (`1c6f686`, `2042a54`), and
both have moved: the accessibility bridge has built lane 1 (`53d3bf6`), and its
record path no longer looks like what item 4 described. The list below is
re-taken against `feat/ax-bridge` at `53d3bf6` and `feat/modifier-composition`
at `ec65da6`, with this track at `f4dcad8`. **A collision is "loud" only if it
fails to compile or reddens a test that exists on the merged tree without
anyone writing it.** Where the reddening test must be written at integration,
the collision is **silent** and says so.

Measured with `git merge-tree --write-tree` (record 11, third pass):
`feat/environment` × `feat/ax-bridge` conflicts textually in
`ElementGroup.swift` and `Window.swift` only; **`Frame.swift` and `Passes.swift`
auto-merge**. `feat/environment` × `feat/modifier-composition` merges with no
conflict (that track has built lane 1 only). Lane 4 re-takes both after lane 3,
because lane 3 edits `Frame.registerHandlers`, the body the bridge also edits.

0. **Integration precondition: lane 3 lands first** (critic finding 9). At
   `f4dcad8`, `.environment(\.isEnabled, false)` and
   `window.environment.isEnabled = false` compile, `isEnabled`'s doc says
   "whether controls below accept interaction", and **nothing reads it**:
   `Frame.registerHandlers` is unchanged. Integrating this branch before lane
   3's commit would ship an inert API with no row and no pin. The check before
   merging: `grep -n "isEnabled" Sources/MetalUI/Frame.swift` is non-empty and
   `DisabledTests.swift` exists. An inert pin was rejected as churn that lane 3,
   the next agent in this worktree, would delete (third-pass table).
1. **`ProposalElementGroup.requestProposalGroupLayout` (modifier composition,
   lane 3).**
   - **Loud half.** The empty conditional conformance
     `extension EnvironmentScope: ProposalElementGroup where Content: ProposalElementGroup {}`
     stops compiling.
   - **Silent half.** The typed entry the integrator writes must do what the
     untyped one does, with **today's names** (the composition spec's collision
     section still says "`bind` gains `environment:`" and "pass
     `pass.frame.environment`"; neither exists at `a4ef92d`):
     ```swift
     public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                     at cursor: inout Int,
                                                     pass: inout LayoutPass)
         -> ([ProposalNodeID], EnvironmentScopeLayout<Content.GroupLayout>) {
         let values = pass.frame.scopedValues(applying: write)      // once (EV-V)
         let (nodes, layout) = pass.frame.withEnvironment(values) {  // the push (EV-A)
             content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
         }                                                            // parent, cursor unchanged (EV-B)
         return (nodes, EnvironmentScopeLayout(values: values, content: layout))
     }
     ```
     There is no `Frame.environment`; readers use `pass.environment` (which
     calls `frame.environmentSnapshot()`), and the framework reads
     `frame.environmentTop` in place.
   - **The tests that see it stop compiling in the same merge** (critic
     finding 6). E11's `NativeEnvRecorder`, and lane 2b's E22/E23 fixtures, are
     `Element` + `extension …: ProposalElementGroup {}` + `pass.requestNativeLeaf`:
     exactly the shape the composition track's guard
     `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` rejects, and its
     registrars start returning `ProposalNodeID`. The integrator **ports** each
     to `ProposalElement` with `requestProposalLayout(_:pass:) -> (ProposalNodeID, Void)`,
     keeps E11's **layout** reading inside `requestProposalLayout`, and then
     **re-runs**, on the merged tree: E11(b) (the typed entry without
     `withEnvironment` → E11's layout slot reads 0), and E4(b)/E4(c)/E5's
     value-keyed id applied to the typed entry → E22 and E23 redden. A port
     that is not followed by these runs has not re-established coverage: the
     person porting the tests is the person writing the entry they check.
   - **One test, not two.** The composition track owes
     `aProposalContainerReadsTheEnvironmentDuringLayout` (arm 1 `HStack {
     recorder.environment(\.probe, 7) }`, arm 2 the scope outside the `HStack`,
     control no writer, mutation "typed entry without `withEnvironment`"). The
     ported E11 **is** that test: the integrator adds its arm 2 and its
     no-writer control to E11 and does not add the second name. If arm 2 as
     spelled traps (a legacy root over native content, `SA-G`), that is
     recorded, not worked around.
2. **`StateBinder.bind`.** Loud. The old `bind(_:table:id:)` is gone; the
   composition track's `GlobalElementID.enteringGroupMember` helper (`MC-H`)
   calls `StateBinder.bind(element, in: pass.frame, id: id)`. **No default and
   no compatibility overload.** (Measured: this is the `ElementGroup.swift`
   conflict against the bridge today too.)
3. **`FrameModifier.swift` deleted (modifier composition, lane 2).** D2's arms
   and `EV-X`'s after-a-scope arms are spelled, not typed, so they keep running
   against `ModifiedElement` and must stay green **unchanged**. `EV-E`'s
   "five callers" is re-taken with the grep.
4. **`Frame.registerHandlers` (accessibility bridge, `53d3bf6`) — SILENT.**
   - **What the bridge built.** The public 3-argument
     `registerHandlers(_:at:id:)` now only forwards to a 5-argument
     `registerHandlers(_:at:id:accessibleText:synthesizesAccessibility:)`, which
     `Text` and `OnTapModifier` call directly. After the declared-node
     `emitAXNode` it appends, while collecting,
     `AXEmission(id:, declared: handlers.axNode, text:, isClickable: handlers.onClick != nil, isEnabled: true, synthesizes:, portal:, geometry:)`,
     and its local `adjustable` reads `handlers.actions`. There is no
     `AXNode.synthesized(declared:handlers:text:)`: the second pass's
     instruction to insert the trait "after synthesis" names a function that
     does not exist. `AccessibilityTreeBuilder` derives `.press` from
     `hitboxes`, `.increment`/`.decrement` and `isFocusable` from the
     `FocusRegistry`, and `isEnabled = false` from a declared `.disabled` trait
     **or** `record.isEnabled == false`.
   - **Why silent.** `Frame.swift` merges textually clean today, and even a
     conflicting merge leaves the literal `isEnabled: true` compiling. Lane 3's
     D12 reads `frame.axNode(for:)` in a frame that is not collecting, so it
     stays green whichever way this goes. The test that sees it exists on
     neither branch.
   - **The merged method** (the gate lives in the **5-argument implementation**;
     the 3-argument overload stays a bare forward with no logic):
     ```swift
     func registerHandlers(_ handlers: Handlers, at bounds: Bounds<Pixels>, id: GlobalElementID,
                           accessibleText: String?, synthesizesAccessibility: Bool) {
         let enabled = environmentTop.isEnabled                        // in place (EV-O)
         if enabled { focusRegistry.register(handlers, id: id) }       // EV-F
         if let focused = focusedElement, id == focused {
             focusedElementProducedThisFrame = true                    // ungated
             if enabled { /* $focus slot write */ }                    // EV-F
         }
         if enabled, hitTestingDisabledDepth == 0, handlers.isPointerTarget {
             _ = insertHitbox(bounds, id: id, opaque: true, handlers: handlers)   // EV-E: none when disabled
         }
         if !handlers.axNode.isEmpty {
             var node = handlers.axNode
             if !enabled { node.traits.insert(.disabled) }
             emitAXNode(node, at: bounds, id: id, children: [])
         }
         if collectsAccessibility, !isAccessibilitySuppressed(for: id) {
             let adjustable = handlers.actions[ObjectIdentifier(AccessibilityAdjustment.self)] != nil
             let hasSomethingToSay = !handlers.axNode.isEmpty
                 || (synthesizesAccessibility
                     && (handlers.onClick != nil || handlers.isFocusable || adjustable || accessibleText != nil))
             if hasSomethingToSay {
                 axEmissions.append(AXEmission(id: id, declared: handlers.axNode, text: accessibleText,
                                               isClickable: handlers.onClick != nil,
                                               isEnabled: enabled,               // NOT `true`
                                               synthesizes: synthesizesAccessibility,
                                               portal: portalStack.last ?? 0,
                                               geometry: accessibilityGeometry(for: bounds)))
             }
         }
     }
     ```
   - **Ungated or stripped — decided.** **Presence and role read the UNGATED
     `handlers`**: `hasSomethingToSay`, `adjustable` and `isClickable`. So a
     disabled button, a disabled adjustable and a disabled focusable are still
     published, as disabled. **Actions read the GATED registrations**, with no
     code of their own: `.press` from `hitboxes` (a disabled element has no
     hitbox, `EV-E`), `.increment`/`.decrement` and `isFocusable` from the
     `FocusRegistry` (a disabled element is not registered, `EV-F`). The
     bridge's `AB-Z` asked for adjustability "from stripped actions" so a
     disabled adjustable advertises nothing; that outcome holds here through the
     registry, and reading a stripped copy for *presence* would instead make a
     disabled adjustable or focusable element vanish from the tree. `AB-Z` also
     assumes a `keyboard` copy with stripped `isFocusable`/`actions`, a hitbox
     with `Handlers()` under the element's id, an ungated `$focus` write and an
     `environment:` init parameter; all four were withdrawn here (`EV-E`,
     `EV-F`, `EV-H`). **This contract supersedes `AB-Z` on those points**; the
     integration step reconciles the bridge's doc to it.
   - **The joint test, one name in both tracks' docs:**
     `aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`,
     written at integration in the bridge's end-to-end test file. Fixture: an
     active fake window (`.activate` sent), `Row { Box().width(40).height(20).onClick { n += 1 }.disabled(true) }`.
     Expected: one published `.button`, `isEnabled == false`, `actions == []`;
     `.press(id)` returns `false`; `n == 0`. **Second arm:** a focusable box
     with `onAction(AccessibilityAdjustment.self)` under `.disabled(true)` →
     published, `isEnabled == false`, `isFocusable == false`, no
     `.increment`, and `.increment(id)` returns `false`. **Control:** both
     without `.disabled` → `isEnabled`, `.press` (resp. `.increment`), the
     request returns `true`, `n == 1`. **Mutations that must redden it, each
     alone:** (a) `isEnabled: true` in the record → both arms publish enabled;
     (b) register the hitbox for a disabled element → `.press` present, the
     press returns `true`, `n == 1`; (c) gate the whole record on `enabled` →
     zero published nodes; (d) register a disabled element in the focus
     registry → the second arm advertises `.increment`. **Not this test's job:**
     the gate placed in the 3-argument overload instead of the 5-argument one
     leaves `Text.onClick` and `Rectangle.onTap` ungated; D2's `text` and
     `onTap` arms redden for that, on the merged tree.
5. **`Frame.init` and `Window`'s `Frame(...)` expression.** No init parameter
   here (`EV-H`); the bridge's `collectsAccessibility:` lands alone. `AB-Z`'s
   "the merged signature takes both, `environment:` and
   `collectsAccessibility:`" is void. `Window` gains one statement after that
   expression, which is where today's `Window.swift` conflict is.
6. **Two deferrals whose named owners do not take them** (`EV-Q`).

**Why.** A silent merge is this repo's recurring failure: a green suite over
unreachable code (the animation milestone's lexical-only transaction). The
second pass called every item loud; item 4 was not, and item 1's tests were
written in a shape the same merge deletes.

**Cost if wrong.** A collision not listed here merges silently. The integration
step re-reads both tracks' **current** docs and runs `git merge-tree` itself,
not only these.

**Mutations.** None owed here: items 1 and 4 name the runs the integration step
owes on the merged tree.

## EV-X — a modifier written AFTER a scope sits outside it

**What.** In `X().disabled(true).frame(width: 40, height: 40).onClick {}` the
`onClick` belongs to the frame layer, which is **outside** the scope, so it is
registered under the enclosing environment and fires; the `.disabled` reaches
only `X`. In `X().theme(.dark).frame(width: 20, height: 20).background(.surface)`
the frame layer's background paints with the **enclosing** theme; `X`'s own
background paints dark. No code implements this: `FrameModifier` (after the
composition merge, `ModifiedElement`) registers and paints in its own phases,
outside its content's scope push.

**Why.** SwiftUI, `swiftui-disabled-ancestor-and-order.swift`: a tap gesture
written inside `.disabled` is suppressed (O1 = 0), one written after it fires
(O2 = 1), with a `.padding` between too (O3 = 1); a background written after an
`.environment` writer reads the default (O6 = 0), one written before it reads the
write (O5 = 1). Scoping probe F2 is the overlay form of O6. The control O0 = 1.

**It was spellable before anyone decided it** (critic finding 7). `EV-B`
claimed nothing could follow a scope; `.frame(width:height:)` is an
`ElementGroup` extension, and both fixtures above typecheck at `f4dcad8` (record
11, third pass). So this is pinned now, not at the composition merge: lane 2b
extends E12 with the `.theme` arm and lane 3's D2 carries the `.disabled` arm,
each with a disagreeing inside-the-scope spelling.

**Cost if wrong.** If a modifier after a scope should see it, a caller's
`.frame(…).onClick` on a disabled control would stay dead, where SwiftUI's fires.
The pins that flip are E12's after-`.theme` arm and D2's after-`.disabled` arm.

**Mutations.** _owed by lanes 2b and 3_: **hoist the scope outward**, the
plausible alternative design — an overload
`extension EnvironmentScope { func frame(width:height:) -> EnvironmentScope<FrameModifier<Content>> }`
that returns `EnvironmentScope(content: content.frame(width:height:), write: write)`,
so the frame layer lands inside the scope → E12's after-`.theme` arm paints its
outer rect dark (lane 2b), and D2's after-`.disabled` arm reads 0 (lane 3). The
overload must win overload resolution for the fixture's spelling; confirm with
the arm's reading, not by inspection.

## EV-Y — `EnvironmentValues()` holds SwiftUI's bare defaults; the WINDOW stamps the current locale

**What.** `EnvironmentValues.init()` sets `locale` to `Locale(identifier: "")`,
not `Locale.current`. `Window.environment`'s initial value is
`EnvironmentValues()` with `locale = Locale.current` stamped, so a window's
root, and everything under it with no writer, still reads `Locale.current`
(probe C). A `Frame` built without a window (every non-window test) reads ''.
An unbound `@Environment` (`EV-M`) builds `EnvironmentValues()` and so reads ''
too, and no longer reads `Locale.current` on every access.

**Why.** `swiftui-environment-pixel-length.swift` V0/V2: a bare SwiftUI
`EnvironmentValues()` holds locale '' and `== Locale(identifier: "")` is true,
`== Locale.current` false (with `Locale.current` en_US, so the comparison
discriminates); X2 shows a `\.self` reset in a hosted window reads '' too. The
lane 2 doc comment said the bare defaults "match probe C"; probe C read a
hosted window, whose host stamps the locale (and the scale) over the bare value
(`EV-R` item 8). Aligning costs one line in `init` and one in `Window`, and a
`\.self` reset then agrees with X2 for `locale` (it still disagrees for
`pixelLength`, `EV-U`).

**Rejected: record the difference instead.** Nothing reads `locale` yet
(`EV-H`), so the difference would be invisible until a consumer lands, and then
a `\.self` reset would silently keep the user's locale where SwiftUI's drops it.

**Cost if wrong.** A test-built `Frame` or an unbound `@Environment` reads the
root locale where it read the user's; with no consumer that changes no pixel.
Pinned by E24.

**Mutations.** _owed by lane 2b_: (a) `init` reads `Locale.current` → E24's bare
arm and its window `\.self` arm redden; (b) `Window.environment`'s initial value
without the stamp → E24's window arm and E14's default-locale expectation
redden.

## EV-Z — `Frame.rootEnvironment` cannot be set while the frame renders

**What.** `Frame` gains a private `isRendering` flag, set at the top of
`render` and cleared at its end (not in a `defer`, for the reason
`render`'s atlas bracket gives: a trap aborts the process). The
`rootEnvironment` setter preconditions `!isRendering`. Writes before a render
and between two renders of one frame stay legal.

**Why.** The setter assigns `environmentTop = values`. Called from inside a
phase — an element's `requestLayout` reaching `pass.frame.rootEnvironment`, which
`@testable` code and any in-module element can — it silently replaces every open
scope's values with the root for the rest of that scope's content, and
`withEnvironment`'s restoring `defer` then puts the **enclosing** values back as
the scope returns: earlier members of the scope read its write, later members
read the root, and a write at root level changes what every later sibling reads
— with no diagnostic.
The doc said "set it before `render`, never during", and nothing enforced it
(critic finding 11). `withEnvironment` is closure-only for exactly this reason;
the setter was the one unscoped write left.

**Rejected alternatives.**

- **A depth counter (`precondition(no withEnvironment is open)`).** It misses a
  write at root level during render, which changes what later siblings read.
- **Remove the setter and pass the root into `render`.** `Window`'s
  `Frame(...)` expression is the bridge's conflict site (`EV-W` item 5), and
  `render` has 60-odd call sites in tests.

**Pins.** Exit tests in a new `EnvironmentTrapTests.swift`, as
`FontResolverTrapTests.swift` and `ElementGroupTrapTests.swift` do:
`aRootEnvironmentWriteDuringARenderTraps` (`processExitsWith: .failure`: an
element whose `requestLayout` sets `pass.frame.rootEnvironment`) and
`aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap` (`.success`: set,
render a scoped tree, set again, render again — so a precondition written as
"no scope was ever pushed" or "never after the first render" reddens it).

**Cost if wrong.** An in-module caller that wanted a mid-frame root change
traps. None exists (`grep -rn "rootEnvironment =" Sources` finds `Window` only).

**Mutations.** _owed by lane 2b_: (a) delete the precondition → the failure arm
reddens; (b) precondition on `environmentPushCount == 0` instead → the success
arm reddens; (c) clear the flag at the top of `paint` instead of the end of
`render` → a variant of the failure arm that writes in `paint` reddens (the
failure test carries one arm per phase).

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

---

## Third pass — the second critic's 11 findings (against `f4dcad8`)

A critic reviewed lanes 1–2 as built and lane 3 as designed, re-ran the suite
(1112 tests, 0 `error:`, 0 `warning:`) and the scoping probe (identical to its
header), ran three scratch probes, `git merge-tree` against `feat/ax-bridge`,
and read both parallel tracks' current docs. Every finding is **applied**, one
of them by its "or" branch; none is rejected outright. The two new probes were
written and run in this pass (record 11, "Third design pass").

| # | finding | disposition |
|---|---|---|
| 1 | A disabled child blocks its enabled parent's click; SwiftUI lets the parent fire | **Applied: skip the hitbox** (`EV-E` inverted, `EV-T` re-derived). N0–N4 committed in `swiftui-disabled-ancestor-and-order.swift` and re-run (N1, N2 parent 1; controls N0, N3 child 1; N4 parent 1). The sibling half is recorded as a pre-existing divergence (shape-less hitboxes, P2m), not as a new one. D3 gains the ancestor arm and flips its sibling arm; D15 and D16 re-derived; mutations re-stated |
| 2 | The AX-bridge merge contract is stale on both sides and silent | **Applied.** `EV-W` item 4 rewritten against `53d3bf6`: the merged 5-argument method with `isEnabled: enabled`; presence and role ungated, actions from the gated registrations (decided and argued); `Frame.swift` auto-merges, stated **silent**; one joint test, the bridge's name, with four mutations and a second (adjustable) arm; `AB-Z`'s stale points listed as superseded. The bridge's own doc is not edited by this track (the integration step reconciles it) |
| 3 | `pixelLength`/`\.self`/`EnvironmentValues()` parity claims contradicted | **Applied.** `swiftui-environment-pixel-length.swift` committed with controls X0, V1, V2 and re-run under two toolchains. `EV-U`'s `pixelLength` half relabelled a divergence; `EV-J`'s "could lie about the device" reasoning corrected; `EnvironmentValues().locale` **aligned** to `Locale(identifier: "")` with the window stamping `Locale.current` (`EV-Y`); the `init` and `pixelLength` doc comments are corrected in lane 2b |
| 4 | Narrowing the public environment API breaks no test (shape 16) | **Applied.** G6 in lane 2b, plain import, every writer and settable field; three mutations owed, a fourth by lane 3 for `.disabled` (`EV-C`) |
| 5 | Identity/state transparency tested only on the legacy path | **Applied.** E22 (node count and ids through `HStack`) and E23 (a proposal `@State` counter across a changing scope) in lane 2b; mutations run here against the shared entry, **re-run at integration against the typed entry** (`EV-B`, `EV-W` item 1) |
| 6 | E11's fixture is the shape MC lane 3 stops compiling | **Applied.** `EV-W` item 1: port E11/E22/E23 to `ProposalElement`, keep the layout reading in `requestProposalLayout`, re-run E11(b) and the identity mutations after the port; E11 absorbs the composition track's `aProposalContainerReadsTheEnvironmentDuringLayout` arms (one test); current API names given (`bind(_:in:id:)`, `scopedValues(applying:)`, `withEnvironment`, no `Frame.environment`) |
| 7 | After MC lane 2, modifiers are allowed after a scope; the documented limit becomes false | **Applied, and stronger than found:** measured, the limit is **already** false at `f4dcad8` through `.frame(width:height:)`, an `ElementGroup` extension. O0–O6 committed. `EV-X` states the semantics (outside the scope, aligned with O2/O3/O6); E12 gains the after-`.theme` arm (lane 2b) and D2 the after-`.disabled` arm (lane 3), now rather than at the merge; `EV-B`'s limit text corrected (it does not "expire at the merge", it was never true for `.frame`) |
| 8 | D2's `List` arm cannot be spelled as specified | **Applied.** Two spelled arms with structurally identical controls: a per-row wrapper `Box { … .disabled(true) }` inside the row, and the scope around the `List` inside a root `Row` (spec, D2) |
| 9 | `isEnabled` is inert at the head, unpinned | **Applied by the first option**: lane 3 is an **integration precondition** (`EV-W` item 0, with the check to run). An inert pin was not added: lane 3 is the next agent in this worktree and would delete it, and no integration happens between |
| 10 | `$disabled` is a new reserved id suffix with no distinctness pin | **Applied by removal.** Finding 1's fix registers no hitbox, so no derived id is minted and no suffix is reserved; the CLAUDE.md reserved-name sentence is withdrawn from the owed list. `theSevenRetentionSlotsAreMutuallyDistinct` needs no extension from this track |
| 11 | An internal `rootEnvironment` write during render silently discards open scopes | **Applied** (`EV-Z`): an `isRendering` precondition in the setter, pinned by a `.failure` exit test with one arm per phase and a `.success` exit test that writes before and between renders of a scoped tree |

