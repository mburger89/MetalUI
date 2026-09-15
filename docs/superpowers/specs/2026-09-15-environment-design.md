# Environment and control state design

**Milestone:** plan task 9 of `plans/2026-09-12-swiftui-alignment.md`, "Expand
the environment and control-state model", on `feat/environment`.

**Status (2026-09-15, record): implemented and verified; handed to the
integration step.** All four lanes are built, and lanes 2b, 3 and 4 were each
re-checked by an independent verifier, all ok: 1133 tests, 97 goldens unmoved,
53 guards, 0 `error:`/`warning:` under both build systems. The verifiers
refuted two statements this spec and the decisions doc carried, both now
corrected in place: D6 **can** be separated from D5 (`Window.lastFocusRegistry`
is the previous-frame signal; `EV-F`), and `.padding` after a scope does compile
over proposal content (`EV-X`). **Still owed, and not delivered by this
branch:** the release-window capture (`EV-P`), `EV-W` items 1 and 4 on the
merged tree, and the plan's "control state" (`controlActiveState`,
`controlSize`) and "scale" (`displayScale`) — so plan task 9 is **not** to be
ticked yet. Record 11, "For the integrator", is the hand-off.

**Status (2026-09-15, lane 3): lanes 1, 2, 2b and 3 implemented** (`a3c92a7`,
`a4ef92d`, recorded at `f4dcad8`; lane 2b red `d271a64`, green `de84219`;
lane 3 red `2de4eef`, green `6957464`); **lane 4 done, with its window
capture NOT taken** (the session was locked; the capture stays owed, below).
Lane 2b's corrections to this text are marked "(lane 2b)" in place, lane 3's
"(lane 3)" and lane 4's "(lane 4)". Lanes 3 and 4 found no design defect and
added no ruling; lane 4 amended `EV-W` against both tracks' moved heads.

**Third design pass (2026-09-15).** A
second critic review of `f4dcad8` found 11 defects; each is applied, with
reasons, in the decisions doc's "Third pass" table, and marked "(third pass)"
here. The largest: a disabled click target now registers **no** hitbox, because
SwiftUI lets an enabled ancestor take the click (`EV-E`, probe arm N). Lane 2's
corrections to this text, all measured, are marked "(lane 2)" in place; its
readings are in the decisions doc's `Mutations` lines and in record 11.

**Status (2026-09-14): design only, second pass.** This was written against
`f64e58a`, and no source has changed. A critic review found 18 defects in the
first pass (`bbd4d66`); each one is applied or rejected, with reasons, in the
decisions doc's "Second pass" table. Rulings are prefixed **`EV-`** and
lettered, in `docs/superpowers/2026-09-15-environment-decisions.md`. A bare
`EV-3` is a typo, not a citation. What was measured is in
`docs/record/11-environment.md`.

**Parallel-track constraint.** Three tracks run at once, in separate worktrees,
and are merged afterwards. So this design:

- **Prefers new files.** Most of it is new.
- **Keeps shared-file edits additive and local.** Each is listed per lane, with
  its size, under "Files".
- **Leaves some documents alone:** `CLAUDE.md`, `AGENTS.md`, `README.md`, the
  plan, `docs/record/README.md`, the existing record files, and the `SA-`
  decisions doc. The integration step owns those. Text owed to them is listed
  at the end, under "Owed to the integration step".
- **Makes every known merge collision loud** (`EV-W`): a collision must fail to
  compile or redden a named test, never merge quietly.

## What this design delivers

1. **Scoped environment values** with SwiftUI's nearest-writer precedence
   (`EV-A`). Writers are layout- and identity-transparent (`EV-B`), each runs
   its transform **once per frame** (`EV-V`), and the API copies SwiftUI's
   names (`EV-C`):
   - `EnvironmentValues`, `EnvironmentKey` and `@Environment`;
   - the modifiers `.environment(_:_:)`, `.transformEnvironment(_:transform:)`,
     `.disabled(_:)`, `.dynamicTypeSize(_:)` and `.theme(_:)`;
   - `pass.environment` on all three passes;
   - `Window.environment`.
2. **Values**, each with a source, a phase and an effect:
   - `theme`: scoped, paint-only, not writable through any public key path,
     `\.self` included (`EV-G`, `EV-U`);
   - `isEnabled` (`EV-D`);
   - `layoutDirection`: carried, not yet mirrored; the type lives in
     `MetalUICore` (`EV-K`);
   - `locale`: carried, no built-in consumer (`EV-H`);
   - `dynamicTypeSize`: carried, with no text effect on macOS, as in SwiftUI
     (`EV-I`);
   - `pixelLength`: read-only and tied to the device, `\.self` included — a
     **divergence**, since SwiftUI derives it from a writable `displayScale`
     (`EV-J`, `EV-U`; third pass);
   - custom keys.
3. **A disabled control state**, all of it through **one** gate in
   `Frame.registerHandlers`:
   - It suppresses clicks and taps on legacy and proposal elements by
     registering **no hitbox**, so a click over a disabled target reaches an
     enabled ancestor (aligned, probe N) or an enabled sibling under it (a
     pre-existing divergence), and the target is neither hovered nor pressed
     (`EV-E`, `EV-T`; third pass).
   - A click needs the target enabled at press **and** at release, as probe R
     measured (`EV-T`).
   - It removes the element from the keyboard entirely: no focus, no action
     handlers, no raw `onKey`, no `keyContext` (`EV-F`). That last half is a
     divergence the brief requires.
   - It adds the AX `disabled` trait.
4. **`Binding` → `KeyBinding`**, with a deprecated alias (`EV-N`).
5. **Proof that nothing else moved.**
   - The Space-key theme swap is read back **as pixels** through the fake
     platform, and the demo is captured at launch with no input, compared by
     region (`EV-P`).
   - The 97 goldens are unmoved: no lane touches `Sources/MetalUILayout/`.
     `LayoutDirection` goes to `MetalUICore`, not to the engine.

Not delivered, each with its owner or flagged as unowned: `EV-Q`.

## Evidence this design stands on

Five probes. All were run in a design session, and their recorded output is in
their headers. The disabled-interaction probe was **re-run in the second pass**
with arms P2g/P2h, a fixed K5–K8 and a new arm R; the last two were added and
run in the **third pass**:

| probe | arms | rulings |
|---|---|---|
| `docs/probes/swiftui-environment-scoping.swift` | A precedence, B `isEnabled`, C defaults, D state retention, E layout transparency, F overlay scope, G dynamic type, H RTL | `EV-A`, `EV-B`, `EV-D`, `EV-G`…`EV-K` |
| `docs/probes/swiftui-disabled-interaction.swift` | P pointer (18 arms, 8 of them controls), K focus/keys (K0–K8), R press/release across a flip | `EV-D`, `EV-E` (analogy only), `EV-F`, `EV-T` |
| `docs/probes/swiftui-environment-api-shape.swift` | compile-only: writable vs get-only members | `EV-C`, `EV-J` |
| `docs/probes/swiftui-disabled-ancestor-and-order.swift` | N a disabled child inside a tappable ancestor (N0, N3, N4 controls), O a gesture or background written inside vs after a scope (O0, O5 controls) | `EV-E`, `EV-X` |
| `docs/probes/swiftui-environment-pixel-length.swift` | V a bare `EnvironmentValues()` (V1, V2 controls), X `displayScale` and `\.self` writes in a window (X0 control) | `EV-J`, `EV-U`, `EV-Y` |

One compiler measurement stands beside them (record 11, "Second pass"): in a
two-module build, `environment(\.self, EV())` resets a `public internal(set)`
field and an `internal` field from outside the module. That is why `EV-U`
exists.

The baseline at `f64e58a` is **1084 tests, 97 goldens and 45 guards**, with 0
`error:` (decisions doc, "Baseline").

---

## Public API (all lanes)

These signatures are normative. A lane that must deviate records the reason as a
new `EV-` ruling.

```swift
// Sources/MetalUICore/LayoutDirection.swift  (new, lane 2) — in Core so plan
// task 6 can record it on native nodes in MetalUILayout without moving a public
// type across a module boundary (EV-K; CLAUDE.md's stale-build hazard)
public enum LayoutDirection: Sendable, Hashable, CaseIterable {
    case leftToRight, rightToLeft
}

// Sources/MetalUI/EnvironmentValues.swift  (new, lane 2)
import Foundation

public protocol EnvironmentKey {
    associatedtype Value
    static var defaultValue: Value { get }
}

public struct EnvironmentValues {                     // not @MainActor: a plain value with nothing
                                                      // isolated in it. NOT for key paths' sake —
                                                      // measured, Swift 6 mode forms key paths to a
                                                      // @MainActor struct's members from @MainActor
                                                      // code too (record 11, "Design session").
                                                      // Not Sendable: custom storage is [ObjectIdentifier: Any]
    public init()                                    // every field at its default
    public var isEnabled: Bool                       // true
    public var layoutDirection: LayoutDirection      // .leftToRight
    public var locale: Locale                        // Locale(identifier: ""); Window stamps
                                                     // Locale.current (EV-Y, lane 2b; lane 2 read .current)
    public var dynamicTypeSize: DynamicTypeSize      // .large
    public internal(set) var pixelLength: Double     // 1; Frame stamps 1/scaleFactor (EV-J, EV-U:
                                                     // a divergence — no scope can change it)
    var theme: Theme                                 // .light; INTERNAL — PaintPass.theme only (EV-G, EV-U)
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value { get set }
}

public enum DynamicTypeSize: Sendable, Hashable, CaseIterable, Comparable {
    case xSmall, small, medium, large, xLarge, xxLarge, xxxLarge
    case accessibility1, accessibility2, accessibility3, accessibility4, accessibility5
    public var isAccessibilitySize: Bool { get }     // accessibility1...
}

// Sources/MetalUI/EnvironmentProperty.swift  (new, lane 2)
@propertyWrapper
@MainActor
public struct Environment<Value> {
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>)
    public var wrappedValue: Value { get }           // snapshot bound per phase; if never bound,
                                                     // the key's default, silently (EV-M)
}

// Sources/MetalUI/EnvironmentScope.swift  (new, lane 2)
public struct EnvironmentScope<Content: ElementGroup>: ElementGroup {
    // stores `content` and `write: EnvironmentWrite` (internal enum, below)
    // GroupLayout = EnvironmentScopeLayout<Content.GroupLayout> { values: EnvironmentValues; content }
    // requestGroupLayout: values = pass.frame.scopedValues(applying: write)   — the ONLY transform call (EV-V)
    //                     pass.frame.withEnvironment(values) { content.requestGroupLayout(under: parent, at: &cursor, …) }
    //                     forwards parent AND cursor unchanged; returns content's nodes unchanged
    // prepaintGroup / paintGroup: pass.frame.withEnvironment(layout.values) { content.<phase>Group(…) }
}
extension EnvironmentScope: ProposalElementGroup where Content: ProposalElementGroup {}
    // after the modifier-composition merge this conformance must IMPLEMENT
    // requestProposalGroupLayout through the same private helper (EV-W)

enum EnvironmentWrite {                               // internal
    case transform(@MainActor (inout EnvironmentValues) -> Void)
    case theme(Theme)
}

extension ElementGroup {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                               _ value: V) -> EnvironmentScope<Self>
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                        transform: @escaping @MainActor (inout V) -> Void)
        -> EnvironmentScope<Self>
    public func disabled(_ disabled: Bool) -> EnvironmentScope<Self>         // lane 3: $0.isEnabled = $0.isEnabled && !disabled
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> EnvironmentScope<Self>
    public func theme(_ theme: Theme) -> EnvironmentScope<Self>              // .theme(theme): the only theme writer
}

// Sources/MetalUI/Passes.swift  (shared, lane 2 — three additive lines)
extension LayoutPass   { public var environment: EnvironmentValues { get } }   // frame.environmentSnapshot()
extension PrepaintPass { public var environment: EnvironmentValues { get } }
extension PaintPass    { public var environment: EnvironmentValues { get } }
// PaintPass.theme keeps its spelling; Frame.theme becomes an in-place read of the top.

// Sources/MetalUI/Window.swift  (shared, lane 2 — one property, one statement)
extension Window { public var environment: EnvironmentValues { get set } }   // didSet → setNeedsRedraw(), even a no-op (EV-H);
                                                                             // initial value: EnvironmentValues() with
                                                                             // locale = .current (EV-Y, lane 2b)

// Sources/MetalUI/Keymap.swift  (shared, lane 1)
public struct KeyBinding { /* was `Binding`; body unchanged */ }
@available(*, deprecated, renamed: "KeyBinding")
public typealias Binding = KeyBinding
```

**Internal (in-module) additions:**

```swift
// Frame.swift (shared, lane 2). NO new init parameter (EV-H, EV-W).
private(set) var environmentTop: EnvironmentValues     // read IN PLACE by `theme` and the gate
var rootEnvironment: EnvironmentValues { get set }       // setter re-stamps theme (from init's `theme:`)
                                                         // and pixelLength (1/scale, or 1 if the scale is
                                                         // not finite and positive) and resets the top;
                                                         // lane 2b: precondition(!isRendering) (EV-Z)
private var isRendering: Bool                            // lane 2b: set at the top of render, cleared at its end
var theme: Theme { environmentTop.theme }                // replaces `let theme`
func scopedValues(applying write: EnvironmentWrite) -> EnvironmentValues
    // .transform(t): var v = environmentTop; t(&v); v.theme = environmentTop.theme;
    //                v.pixelLength = environmentTop.pixelLength; return v        (EV-U)
    // .theme(th):    var v = environmentTop; v.theme = th; return v
    // increments environmentTransformCount
func withEnvironment<R>(_ values: EnvironmentValues, _ body: () -> R) -> R
    // saves the top in a local, sets it, restores it in a defer; increments environmentPushCount
func environmentSnapshot() -> EnvironmentValues          // returns the top; increments environmentSnapshotCount
private(set) var environmentPushCount: Int               // EV-O, test observables
private(set) var environmentSnapshotCount: Int
private(set) var environmentTransformCount: Int

// StateBinder (StateReflection.swift, shared, lane 2)
static func bind<E>(_ element: E, in frame: Frame, id: GlobalElementID)
    // replaces bind(_:table:id:). table = frame.stateTable. frame.environmentSnapshot()
    // is called ONLY when E's cached shape has Environment ordinals, once per bind.
    // No overload keeps the old spelling, so any call site written elsewhere
    // against bind(_:table:id:) fails to compile at merge (EV-W).
// the five call sites pass `pass.frame` (Frame.render: `self`)
```

**Where writers are and are not usable.** This is compile-time and deliberate
(`EV-B`).

- **Usable** over any `ElementGroup`: legacy elements, proposal content
  (conformance kept), `Component`, builder groups.
- **Not usable** as a window root, as `Deferred` content, or as a `List` row,
  because each of those requires `Element`. Write the scope outside instead.
- **Not usable** directly before `.padding` or a handler modifier:
  `.disabled(true).padding(4)` does not compile. **But `.frame(width:height:)`
  is an `ElementGroup` extension**, so `.disabled(true).frame(…)` compiles today,
  and any `StyledElement` modifier may follow it (third pass, measured). Such a
  modifier sits **outside** the scope, as in SwiftUI (`EV-X`, probe O2, O3,
  O6): `X().disabled(true).frame(width: 40, height: 40).onClick {}` fires.

---

## Lane 1 — `KeyBinding` (`EV-N`)

Small, and independent of the rest. It is first because lane 2's Space-key test
spells `KeyBinding`.

### Changes

- `Keymap.swift`:
  - rename the struct;
  - add the deprecated alias;
  - retype `Keymap.bindings`, `Keymap.init(_:)`, `KeymapBuilder.buildBlock` and
    the private `bestBinding` tuple;
  - update doc comments that spell `Binding(` (the struct doc, `Keystroke.init?`
    and `Keymap`).
- `KeyContext.swift:63`: update the doc comment.
- `Sources/MetalUIDemo/main.swift:1104-1112`: nine `Binding(` → `KeyBinding(`.
- `Tests/MetalUITests/KeymapTests.swift`: every `Binding(` → `KeyBinding(`.
- **Leave alone** the `@Binding` mentions in `ComponentTests.swift:223,479`, and
  the uses of "Binding" as an English word (`Window.swift:700`,
  `IdentityTests.swift:637`, `ShapingCacheTests.swift:340`).

### Tests

| test | file | red before | mutation that must redden it |
|---|---|---|---|
| `G5` `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding` — a plain-import `typecheck` fixture: `let k = Keymap([Binding("cmd-k", A())])`, where `A: Action`. Asserts `succeeded`, `messages.contains("'Binding' is deprecated")` **and** `messages.contains("KeyBinding")` (the deprecation warning's rename text). | new `Tests/MetalUITests/EnvironmentCompileGuards.swift` | `KeyBinding` does not exist, so `messages` has no "KeyBinding" | (a) delete the typealias → `succeeded` false; (b) drop `@available(deprecated…)` → `messages` lacks "KeyBinding"; (c) drop only `renamed:` → `messages` lacks "KeyBinding" (lane 1 ran all three; results under `EV-N`) |
| every existing `KeymapTests` test, respelled | `KeymapTests.swift` | does not compile before the rename | not a new mutation: the file's existing mutation records stand |

**Warnings.** After lane 1, `grep -c "warning:"` over the build and test log
must read 0. The demo and tests use no deprecated spelling. `G5`'s warning is
printed by the child `swiftc`, which the test captures, so it does not reach the
suite log. **Check that, don't assume it.**

Suite: 1084 → **1085**. Guards: 45 → **46**.

---

## Lane 2 — the environment (`EV-A`, `EV-B`, `EV-C`, `EV-G`…`EV-M`, `EV-O`, `EV-P`, `EV-U`, `EV-V`)

### Changes

**New files:**

- `Sources/MetalUICore/LayoutDirection.swift`: `LayoutDirection` (`EV-K`).
  `MetalUI` already re-exports `MetalUICore` (`App.swift:8`), so callers need no
  new import. This is a new public type in a module other targets import:
  **`swift package clean` before the first test run** (CLAUDE.md).
- `Sources/MetalUI/EnvironmentValues.swift`: `EnvironmentValues`,
  `EnvironmentKey` and `DynamicTypeSize`.
- `Sources/MetalUI/EnvironmentProperty.swift`: `Environment<Value>` and its
  internal `BindableEnvironment` conformance.
- `Sources/MetalUI/EnvironmentScope.swift`: `EnvironmentScope`,
  `EnvironmentWrite`, `EnvironmentScopeLayout`, and the `ElementGroup` modifiers
  except `.disabled`, which lane 3 adds.

**Shared files, each edit additive and local:**

- **`Frame.swift`.**
  - `let theme` becomes a stored `rootTheme` plus the computed `theme` above.
    Update its doc: scoped now, still paint-only, fixed per scope for the whole
    frame.
  - Add `environmentTop`, `rootEnvironment`, `scopedValues(applying:)`,
    `withEnvironment`, `environmentSnapshot()` and the three counters. **`init`'s
    signature does not change**: it builds the root from `EnvironmentValues()`
    and stamps `theme` and `pixelLength` itself.
  - `Frame.render`'s `StateBinder.bind` passes `self`.
  - About 45 lines.
- **`Passes.swift`.** Add three `environment` accessors. Amend `PaintPass.theme`'s
  doc: "the nearest `.theme(_:)`, else the window's".
- **`Window.swift`.** Add `public var environment`, and **one statement after**
  the `Frame(...)` expression in `drawFrameIfNeeded`:
  `frame.rootEnvironment = environment`. The expression itself is not edited.
- **`ElementGroup.swift`.** Three `StateBinder.bind` calls become
  `bind(self, in: pass.frame, id: …)`.
- **`Component.swift`.** One such call.
- **`StateReflection.swift`.**
  - `bind(_:in:id:)` replaces `bind(_:table:id:)`; no overload keeps the old one.
  - The shape cache records `Environment` ordinals alongside `State` ordinals.
    The miss path checks `as? BindableState` and then `as? BindableEnvironment`.
    The hit path returns before touching the environment when the `Environment`
    ordinals are empty.
  - `reflectionCount` semantics are unchanged: one per type.

### Tests

New file `Tests/MetalUITests/EnvironmentTests.swift`. Every test is `@MainActor`.
It may `import Metal` only if it declares no `Dimension`-typed fixture
(`Fakes.swift`'s note on `AnimationTests.swift`); otherwise E18's device check
moves to a helper in the same file that does.

The fixture key used below is `struct ProbeKey: EnvironmentKey { static let defaultValue = 0 }`,
exposed as `EnvironmentValues.probe`. **The recorder is a reference type**, as
`ClickLog` is (`InputDispatchTests.swift`): element values do not survive a
frame.

**Why every test below is red before lane 2.** None of the API exists, so each
file-level fixture fails to compile. For a guard, the fixture's `messages`
differ. "Red before" names the assertion that would fail if only the API shell
existed and the mechanism were a no-op (push nothing, bind nothing). That is the
stronger reading, and it is what the implementer checks by landing the shell
first.

| # | test | shell-only red reading | mutation (run after green) and what must redden |
|---|---|---|---|
| E1 | `theNearestWriterWinsAndAScopeEndsWithItsSubtree`. A legacy `Row` of recorder leaves mirrors probe A0–A6: no writer; `.environment(\.probe, 1)`; `.environment(\.probe, 2).environment(\.probe, 1)`; an outer scope 1 holding [inner-less, inner 2, sibling]; and a leaf after the scope. It expects `[0, 1, 2, 1, 2, 1, 0]`, read in **paint**. | all zeros | (a) **outer writer wins**, buildable: `Frame` keeps a stack of the writes pushed in layout, and `scopedValues(applying: w)` starts from `rootEnvironment` and applies `w` first and the enclosing writes after it, outermost last → the A2 and A4 slots read 1. (b) Remove `withEnvironment`'s restoring `defer` → values leak to later siblings: the A6 slot reads non-zero. (Applying the write to the ROOT instead of the top is invisible here, since each arm writes one key once; E2 carries that mutation) |
| E2 | `aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt`. Probe A7/A8 → `[110, 5]`. | `[0, 0]` | `scopedValues` starts from `rootEnvironment` instead of `environmentTop` → 10 and 5, so the A7 slot reddens |
| E3 | `anEnvironmentValueReadsIdenticallyInAllThreePhases`. A recorder `Element` logs `pass.environment.probe` in `requestLayout`, `prepaint` and `paint`, for a leaf in scope 2, a sibling after it in scope 1, and a leaf outside any scope. It expects `[[2,2,2],[1,1,1],[0,0,0]]`. | all zeros | `EnvironmentScope.prepaintGroup` forwards without `withEnvironment` → the middle (prepaint) element of the first two triples reads 0. The same mutation in `paintGroup` → the third (paint) element reads 0. Both are run and recorded separately |
| E4 | `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex`. (i) `Row { Pair(A, B).environment(\.probe, 1) ; C }` gives the row 3 children, and C's `GlobalElementID` equals C's id in `Row { Pair(A, B); C }`. (ii) A's id equals A's id without the scope. Ids are captured by a recorder in `prepaint`. | red only if the shell registers a node | (a) `EnvironmentScope.requestGroupLayout` wraps the nodes in `pass.requestNode(style: Style(), children:)` → child count 2; (b) `cursor += 1` before forwarding → C's id moves; (c) forward `under: GlobalElementID.child(of: parent, at: cursor, name: nil)` with a fresh cursor → A's id moves |
| E5 | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`. A real `makeFakeWindow`. A root `Row` holds a `Counter` element with `@State var n`, incremented by `onClick`, wrapped in `.environment(\.probe, model.value)`. Click twice, change `model.value`, draw; `n` reads 2. Probe D1. (Lane 3 adds a `.disabled(model.flag)` arm to this same test; see D10.) | passes on arrival for the environment arm, since there is no mechanism to lose state yet; red only in lane 3's arm, before `.disabled` exists. This is **stated and accepted**: the test exists for the mutation | implement `environment(_:_:)` as a value-keyed `EitherGroup` (`value == default ? .first(self) : .second(scope)`) → `n` resets to 0 when the value moves off the default. (lane 2: that spelling changes the modifier's return type and the file stops compiling; the run that reddened E5 keys the scope's id by its values — decisions doc, `EV-B`) |
| E6 | `anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame`. An `Element` with `@Environment(\.probe) var probe` logs `probe` in all three phases, under a scope reading `model.value`. Frame 1 at 3 gives `[3,3,3]`; frame 2 at 4 gives `[4,4,4]`. | `[0,0,0]` | (a) the binder skips binding when the box already holds a snapshot → frame 2 reads `[3,3,3]`; (b) `ElementGroup.prepaintGroup` binds `rootEnvironment` instead of the snapshot → prepaint reads 0; (c) delete the re-bind in `paintGroup` → paint reads the layout snapshot, which cannot differ within a frame, **so (c) is expected to stay green**. Record it as the instrument's limit, not as coverage, and cover (c) through E7 |
| E7 | `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint`. `let r = EnvRecorder(); Row { r.environment(\.probe, 1); r.environment(\.probe, 2) }` reads `[1, 2]` in paint. This is divergence 19's read half. | `[0, 0]` | delete the re-bind in `ElementGroup.paintGroup` → `[2, 2]` |
| E8 | `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`. It is pinned **inert on purpose** (`EV-M`). An `AnyElement` wrapping an `@Environment` reader inside `.environment(\.probe, 5)` reads 0. Its doc states the general rule this is one case of: **an `@Environment` that was never bound returns the key's default silently**, with no diagnostic, building a fresh `EnvironmentValues()` (and reading `Locale.current`) on every access. | — (describes a limit) | none. It flips when `AnyElement` binding lands |
| E9 | `aComponentReadsTheNearestEnvironmentInItsContent`. A `Component` with `@Environment(\.probe)` whose `content` is `Box().background(probe == 1 ? .accent : .surface)` of fixed size. Inside `.environment(\.probe, 1)`, the scene's rect is `.accent` resolved; bare, it is `.surface`. | both `.surface` | `Component.requestGroupLayout`'s bind snapshots `rootEnvironment` → the scoped arm reads `.surface` |
| E10 | `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState`. `Counter`-style component state survives `MyComponent()` → `MyComponent().environment(\.probe, 1)` across two frames in one `StateTable`, compared by id as in `addingAModifierDoesNotResetAComponentsState`. | — | mutation E4(b) reddens this too. Record both names |
| E11 | `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`. `HStack { Rectangle(...).environment(\.probe, 7) }` with a native recorder leaf that logs `pass.environment.probe` in **layout, prepaint and paint** → `[7,7,7]`. The same scope over `ProposalScrollView` content → `[7,7,7]`. | `[0,0,0]` | (a) E3's `paintGroup` mutation → the paint slot reads 0; (b) `EnvironmentScope.requestGroupLayout` forwards without `withEnvironment` → the layout slot reads 0. **(b) is the one the modifier-composition merge could reintroduce** (`EV-W`): a forwarding `requestProposalGroupLayout` skips the push in layout only |
| E12 | `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`. In a `Row`: a `.surface` box inside `.theme(.dark)`, a `.surface` sibling outside it, and a `Deferred { .surface box }` inside `.theme(.dark)`. The scene colours are dark, light, dark. | light, light, light | (a) `Frame.theme` returns `rootTheme` → the first arm reads light; (b) `PaintPass.deferred` sets the top to `rootEnvironment` around its body → the third arm reads light |
| E13 | `theFramesRootEnvironmentCarriesItsThemeAndScale`. (lane 2: green on the shell, because the shell already carried `Frame`'s root stamping; its three mutations are the red readings.) A `Frame(theme: .dark, scaleFactor: 2)` renders a `.surface` box dark, and `pixelLength` reads 0.5; at `scaleFactor: 1` it reads 1. Then `frame.rootEnvironment = x` where `x` is a snapshot from a light, scale-1 frame: theme still dark, `pixelLength` still 0.5 (the in-module overwrite is re-stamped; `EV-H`). | light; 1 at scale 2 | (a) the root ignores `theme:` → light; (b) `pixelLength = Double(scaleFactor)` → 2 at scale 2; (c) the `rootEnvironment` setter does not re-stamp → light and 1. The scale-2 arm is what discriminates, because the fake surface is scale 1 |
| E14 | `theWindowsEnvironmentReachesTheFrameAndASetRepaints`. A fake window: after one frame, `needsRedraw` is false; set `window.environment.locale` to a locale whose identifier differs from `Locale.current.identifier` (`de_DE`, or `fr_FR` if the machine is `de_DE`; `try #require` that they differ) → `needsRedraw` true; the next frame's recorder reads it. Draw again; `window.environment = window.environment` → `needsRedraw` **true**: a no-op write still dirties, **pinned as a stated cost** (`EV-H`). Defaults on a fresh window: `isEnabled`, `.leftToRight`, `Locale.current.identifier` and `.large`, matching probe C. | the recorder reads the default locale | (a) drop the `didSet` → `needsRedraw` false; (b) `drawFrameIfNeeded` omits the `rootEnvironment` statement → the recorder reads `Locale.current`; (c) skip dirtying when the built-in fields compare equal → the no-op arm reads false. (c) is not a defect to prevent; it is the change that must face this pin and say how it compares custom keys |
| E15 | `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants`. **Performance, counts work**, on a branching 4×5×3 tree of fixed-size `Box`es (the shape CLAUDE.md's Performance section counts cache misses on) and the same writers over a 1×1×1 tree. Counts are `try #require`d before comparison. **Pushes:** no writer → 0; one writer at the root child → 3; two nested writers → 6; the same on both trees. **Snapshots:** with no `@Environment` reader and no `pass.environment` read anywhere, **0** on both trees, writers or not. **Positive control:** add one `@Environment` reader leaf → snapshots 3 (one bind per phase) on both trees. **Transforms:** one per writer per frame. | the counters do not exist (compile) | (a) `Element.requestGroupLayout` (default) wraps `requestLayout` in `frame.withEnvironment(frame.environmentTop)` → the big tree's pushes exceed the small tree's; (b) **eager evaluation**: `bind` calls `frame.environmentSnapshot()` before consulting the shape → snapshots equal 3 × elements, so 0 fails and the trees disagree. `Frame.theme`'s and the gate's in-place reads are not counted, and the ruling claims nothing the counters cannot see (`EV-O`) |
| E16 | `dynamicTypeSizeChangesNoTextMeasurement`. A fixed-string `Text` measures the same width and height bare and under `.dynamicTypeSize(.accessibility5)`, with a positive control: `.font(size: 26)` differs. Probe G. | — (passes on arrival once it compiles: aligned behaviour) | multiply `Text`'s `fontSize` by 1.5 when `pass.environment.dynamicTypeSize.isAccessibilitySize` → red. **Revert.** The test exists so a later "fix" must face probe G |
| E17 | `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`. **Pinned wrong on purpose** (`EV-K`). `HStack(spacing: 0) { Rectangle(width: 10, height: 10); Rectangle(width: 20, height: 10) }` with `.frame(width: 100, alignment: .leading)`, inside `.environment(\.layoutDirection, .rightToLeft)`, places at x 0 and 10. The doc quotes probe H's 90 and 70. | — | none owed. It flips with task 6 |
| E18 | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` (`EV-P`). `let device = try #require(MTLCreateSystemDefaultDevice())`, then a fake window with `keymap = Keymap { KeyBinding("space", ToggleThemeFixture()) }` and `onAction` flipping `window.theme` for that action type and returning true, over a full-size `.background` box. Draw and `readPixels()`: the centre pixel is `before`. `simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: " ", characters: " ", timestamp: 0)))` returns true; draw; the centre pixel is `after`. **Oracle arms that must disagree first:** two more fake windows with `theme` set light and dark render the same tree; `try #require(lightRef != darkRef)`. Then `before == lightRef` and `after == darkRef`. | — (passes on arrival once lane 1 exists: a regression pin) | E13(a) → `after == lightRef`. Also: `Frame.theme` computed from `EnvironmentValues().theme` → `after == lightRef`. (lane 2: both redden at `try #require(lightRef != darkRef)` instead, since the dark reference turns light too — decisions doc, `EV-P`) |
| E19 | `aWholeValueWriteCannotResetTheThemeOrThePixelLength` (`EV-U`). A `Frame(scaleFactor: 2)` renders, inside `.theme(.dark)`: (i) `.environment(\.self, EnvironmentValues())` over a `.surface` box and a `pixelLength` recorder; (ii) `.transformEnvironment(\.self) { $0 = captured }` where `captured` is a snapshot taken from a light, scale-1 frame. Both arms: the box is dark, `pixelLength` 0.5. **Control:** the same `\.self` write resets `probe` from 3 to 0, so the write did land | the box is light and `pixelLength` is 1 | drop the two re-stamping assignments in `scopedValues` → light and 1 |
| E20 | `eachScopesTransformRunsOncePerFrame` (`EV-V`). A reference counter `c`; `.transformEnvironment(\.probe) { c.n += 1; $0 = c.n }` over a three-phase recorder. After frame 1: `c.n == 1`, recorder `[1,1,1]`; after frame 2: `c.n == 2`, recorder `[2,2,2]`; `environmentTransformCount` 1 per frame | the counter is 3 per frame and the recorder reads `[1,2,3]` if the shell re-runs the transform per phase | `prepaintGroup` calls `scopedValues(applying: write)` instead of pushing `layout.values` → `c.n == 2` after frame 1 and the prepaint slot differs |
| E21 | `aLocaleChangesNoTextMeasurement` (`EV-H`, inert, **pinned as inert**). `Text("กรุงเทพมหานคร อมรรัตนโกสินทร์")` measures the same min-content width, max-content width and height bare and under `.environment(\.locale, Locale(identifier: "th_TH"))`, and under `en_US`. Positive control: `.font(size: 26)` differs. | — (passes on arrival) | pass `pass.environment.locale` into `Shaper`'s tokenizer → the min-content width may move. **If it does not move, the mutation is void and that is recorded, not banked as coverage.** Revert either way |

**Typecheck guards**, in `Tests/MetalUITests/EnvironmentCompileGuards.swift`
(plain import, `canTypecheck`-gated, per the file header convention of
`PhaseSeparationTests`):

| # | guard | kind | mutation that must redden it |
|---|---|---|---|
| G1+ | `environmentValuesAreReadableInEveryPhase`. One fixture reads `pass.environment.isEnabled`, `.layoutDirection`, `.locale`, `.dynamicTypeSize`, `.pixelLength` and a custom key on all three passes, and `@Environment(\.isEnabled)` in a struct. (lane 2: the struct must be `@MainActor`; a nonisolated one is rejected in Swift 6 mode, as it would be for `@State`.) | positive | make `LayoutPass.environment` internal → fails |
| G1− | `theThemeIsNotReachableThroughTheEnvironment`. Fixtures: `pass.environment.theme` on `LayoutPass`, and `@Environment(\.theme) var t`. It asserts `!succeeded` and `messages.contains("'theme' is inaccessible")` (lane 2: the bare word also matches a nonisolated fixture's `_theme` note). | negative | make `EnvironmentValues.theme` public → `succeeded` |
| G2 | `environmentValuesCannotBeWrittenThroughAPass`. `pass.environment.isEnabled = false` on `PaintPass`. It asserts `!succeeded` and `messages.contains("'environment' is a get-only property")` (lane 2). | negative | give the pass accessor a `nonmutating set` that writes the top of the stack → `succeeded` |
| G3 | `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles`. Two fixtures inside a function returning `some ElementGroup`. **Negative:** `X().environment(\.pixelLength, 1.0)` → `!succeeded`, `messages.contains("WritableKeyPath")`. **Positive premise:** `X().environment(\.self, EnvironmentValues())` → `succeeded`. The positive half records that the compiler cannot close the `\.self` route, which is why E19 exists | negative + premise | (a) make the setter public → the negative half succeeds; (b) make `EnvironmentValues.init` internal → the positive half fails |
| G4+ | `aProposalContainerAcceptsAScopeOverProposalContent`. `typecheckFile`, Swift 6 mode: `HStack { Rectangle(width: 1, height: 1).environment(\.probe, 1) }`. | positive | delete the conditional `ProposalElementGroup` conformance → fails |
| G4− | `aProposalContainerRejectsAScopeOverLegacyContent`. `HStack { Box().environment(\.probe, 1) }`. It asserts `!succeeded` and `messages.contains("ProposalElementGroup")`. | negative | make the conformance unconditional → `succeeded` |

Each new guard is **mutated red once** in a worktree built with
`swift build --build-system native`, **to prove it runs**. The count alone
cannot say whether it ran (CLAUDE.md, "When CI lands").

Suite: 1085 → **1085 + 21 + 6 = 1112**. Guards: 46 → **52**.

---

## Lane 2b — hardening lane 2 (third pass: `EV-B`, `EV-C`, `EV-J`, `EV-U`, `EV-X`, `EV-Y`, `EV-Z`)

Everything here answers a finding against `f4dcad8` (decisions doc, "Third
pass"). It runs before lane 3 because lane 3 extends two of its files (G6, and
the doc comments lane 3 amends).

### Changes

- **`EnvironmentValues.swift`** (new file of this track).
  - `init()`: `locale = Locale(identifier: "")` (`EV-Y`).
  - `init`'s doc: these are SwiftUI's **bare** defaults (pixel-length probe V0),
    not probe C's, which a host stamps; a `Window` stamps `Locale.current` and a
    `Frame` stamps `pixelLength` and the theme.
  - `locale`'s doc: `Locale(identifier: "")` bare, `Locale.current` under a
    window.
  - `pixelLength`'s doc: delete "as SwiftUI's is". State that SwiftUI's is
    get-only but derived from a writable `displayScale` (X1) and reset by
    `\.self` (X2), so a scope can change it there and cannot here: a
    divergence (`EV-J`, `EV-U`).
  - The type doc's `EV-U` paragraph: the `pixelLength` half is a divergence;
    the `theme` half is MetalUI's own key.
- **`EnvironmentProperty.swift`**: the unbound-read doc says locale '' instead
  of "reading `Locale.current`".
- **`EnvironmentScope.swift`**: its doc's "where usable" text follows the spec
  section above (`.frame` may follow a scope; `EV-X`).
- **`Window.swift`** (shared, one expression): `environment`'s initial value
  becomes `EnvironmentValues()` with `locale = .current`, written as a closure
  or a private static helper **in `EnvironmentValues.swift`** (so the `Window`
  edit is the initializer expression only); its doc gains one `EV-Y` sentence.
  (lane 2b: the helper is `static func windowDefault()`, **internal**, not
  private — a `private` member of `EnvironmentValues.swift` is not visible from
  `Window.swift`.)
- **`Frame.swift`** (shared, four lines plus doc): `private var isRendering =
  false`; `render` sets it on its first line and clears it on its last (after
  `stateTable.sweep()`); the `rootEnvironment` setter begins with
  `precondition(!isRendering, "Frame.rootEnvironment set during render: it would replace every open scope's values (ruling EV-Z)")`.
  The setter's doc replaces "set it before `render`, never during" with the
  precondition.

### Tests

| # | test | red before lane 2b | mutation and what must redden |
|---|---|---|---|
| E12 (extended in place) | Add the `EV-X` arm to `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`: `Box().width(px(13)).height(px(10)).background(.surface).theme(.dark).frame(width: px(14), height: px(10)).background(.surface)`. The 13pt rect is dark; the 14pt frame layer's rect is **light** (O6, F2). The **disagreeing spelling** in the same test, `…background(.surface).frame(width: px(16), height: px(10)).background(.surface).theme(.dark)` (widths 15/16), reads dark and dark, so the arm is shown to see inside vs outside | — (aligned behaviour, passes on arrival: an instrument pin) | `EV-X`'s hoist overload on `EnvironmentScope.frame` → the 14pt rect paints dark. (lane 2b: **the overload as written is void** — it loses overload resolution whenever a `StyledElement` modifier follows `.frame`, so the suite stayed at 0 issues; respelled as `FrameModifier` pushing its content scope's values around its own registration and fill, it reddens only this arm at the 14pt slot — decisions doc, `EV-X`) |
| E22 | `aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex`. E4 on the proposal path: `NodeProbe(inner: HStack(spacing: 0) { Pair(NativeEnvRecorder(A), NativeEnvRecorder(B)).environment(\.probe, 1); NativeEnvRecorder(C) })` against the same tree bare. `NativeEnvRecorder` gains `log.ids[label] = id` in `prepaint`. `try #require` the **bare** `HStack` node's `tree.children` count is 3 before comparing; then the scoped count is 3 and A, B, C's ids equal the bare ones. (the explicit `Pair` inside `HStack`'s builder typechecks at `f4dcad8`, record 11, third pass) | — (passes on arrival, stated: one entry serves both paths today; it exists for the merge, `EV-W` item 1) | run here, against the shared entry, to prove the instrument sees: E4(a) with a native wrapper (`requestNativeOverlay`), E4(b), E4(c) → each reddens E22 (and E4). **Re-run at integration against the typed entry** |
| E23 | `aProposalStateCounterKeepsItsCountAcrossAChangingScope`. A real fake window (`try #require(MTLCreateSystemDefaultDevice())`), root `HStack { NativeClickCounter(log: log).environment(\.probe, model.value) }`, where `NativeClickCounter` is E11's shape (`Element` + `ProposalElementGroup` marker, `requestNativeLeaf` 20×20) with `@State var n`, an `onClick` that increments it through `pass.registerHandlers`, and a paint-time log. Click twice (`try #require` the log reads 2), set `model.value = 7`, redraw → 2 | — (passes on arrival, as E5 did) | E5's value-keyed scope id → 0. **Re-run at integration against the typed entry** |
| E24 | `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne` (`EV-Y`). (i) `try #require(Locale.current != Locale(identifier: ""))`; `EnvironmentValues().locale == Locale(identifier: "")`. (ii) A fresh fake window: `window.environment.locale == Locale.current`; a recorder with no writer reads `Locale.current.identifier`. (iii) In the same window, a recorder under `.environment(\.self, EnvironmentValues())` reads `""` while its unscoped sibling reads `Locale.current.identifier` (X2) | (i) and (iii) read `Locale.current` | `EV-Y` (a) `init` reads `Locale.current` → (i) and (iii); (b) the window's initial value unstamped → (ii), and E14's default-locale expectation |
| T1 | `aRootEnvironmentWriteDuringARenderTraps` (`EV-Z`), new file `Tests/MetalUITests/EnvironmentTrapTests.swift`. Three `#expect(processExitsWith: .failure, observing: [\.standardErrorContent])` blocks, written out at each site (non-capturing, as `ElementGroupTrapTests.swift` explains), each rendering `Row { Writer(phase:) }` inside `MainActor.run`, where `Writer` sets `pass.frame.rootEnvironment = EnvironmentValues()` in `requestLayout`, `prepaint` or `paint`. Each asserts the stderr contains `"rootEnvironment set during render"`, so an unrelated trap cannot pass it | does not trap | (a) delete the precondition → all three arms; (c) clear `isRendering` at the top of `paint` → the paint arm |
| T2 | `aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap` (`EV-Z`), `.success`: one `Frame`; set the root; render `Row { EnvRecorder(…).environment(\.probe, 1) }`; set the root again; render again. Inside the child, `precondition` that the second render's recorder reads `probe == 1` | — (passes on arrival) | (b) precondition on `environmentPushCount == 0` instead → traps on the second set |

**Typecheck guard**, in `EnvironmentCompileGuards.swift`:

| # | guard | kind | mutations |
|---|---|---|---|
| G6 | `theEnvironmentsPublicWritersCompileFromOutsideTheModule` (`EV-C`, shape 16). Plain `import MetalUI`, Swift 6 mode (`typecheckFile`, as G4 does). A file-scope custom key with a `public var probe` extension. In an `@MainActor` function returning `some ElementGroup`: `Box()` chained through `.environment(\.isEnabled, false)`, `.environment(\.layoutDirection, .rightToLeft)`, `.environment(\.locale, Locale(identifier: "de_DE"))`, `.environment(\.dynamicTypeSize, .accessibility1)`, `.environment(\.probe, 1)`, `.transformEnvironment(\.probe) { $0 += 1 }`, `.dynamicTypeSize(.xLarge)`, `.theme(.dark)`. In an `@MainActor func f(_ w: Window)`: `w.environment = EnvironmentValues()`; `w.environment.isEnabled = false`; `var e = EnvironmentValues()`, then assign each of `isEnabled`, `layoutDirection`, `locale`, `dynamicTypeSize` and `e[ProbeKey.self]`; `_ = DynamicTypeSize.accessibility2.isAccessibilitySize`. Asserts `succeeded`, printing `output` on failure | positive | each alone, each must print `failed` for G6 (and the run must show G6 ran, not skipped): (a) `.theme(_:)` internal; (b) `locale` `internal(set)`; (c) `Window.environment` `internal(set)`. (lane 2b: the fixture also needs `import Foundation` — `import MetalUI` does not re-export it, and `Locale` is otherwise not in scope) |

Each mutation in this lane is run on a `--build-system native` build in this
worktree, one at a time, restored from git, and its reddened tests named in the
ruling's Mutations line.

Suite: 1112 → **1112 + 5 + 1 = 1118** (E22, E23, E24, T1, T2 and G6; E12 is
extended in place). Guards: 52 → **53**.

---

## Lane 3 — the disabled control state (`EV-D`, `EV-E`, `EV-F`, `EV-T`, `EV-X`)

### Changes

- **`EnvironmentScope.swift`.** Add `.disabled(_:)` as the AND transform.
- **`Frame.registerHandlers`** (shared, about 20 lines, local to that method):
  ```swift
  let enabled = environmentTop.isEnabled                        // in place, not a snapshot
  if enabled { focusRegistry.register(handlers, id: id) }       // disabled: out of the keyboard entirely (EV-F)
  if let focused = focusedElement, id == focused {
      focusedElementProducedThisFrame = true                    // UNCHANGED, still ungated
      if enabled { /* the existing $focus slot write */ }       // gated (EV-F, finding 7)
  }
  if enabled, hitTestingDisabledDepth == 0, handlers.isPointerTarget {  // disabled: NO hitbox (EV-E, third pass)
      _ = insertHitbox(bounds, id: id, opaque: true, handlers: handlers)
  }
  if !handlers.axNode.isEmpty {
      var node = handlers.axNode
      if !enabled { node.traits.insert(.disabled) }             // the declared node; the bridge's record
      emitAXNode(node, at: bounds, id: id, children: [])        // takes `isEnabled: enabled` at merge (EV-W item 4)
  }
  ```
  There is **no derived id and no `$disabled` suffix** (third pass; the second
  pass's blocker is withdrawn, `EV-E`, `EV-T`).
  **Update the method's doc** to state the gate and cite `EV-E`/`EV-F`/`EV-T`,
  including that a click over a disabled target reaches an enabled ancestor or
  the sibling under it.
  **Update the `$focus` paragraph** (`Frame.swift:621-651`): the ungated-write
  hazard stays reachable through `Window.focus` on an enabled non-focusable
  element, and is **not** reachable through `.disabled`, because the slot write
  is gated on `isEnabled`. **Update `Handlers`' doc** paragraph on the two gates.
- **No other behavioural source edit.**
  - `Box`, `Stack`, `Text`, `FrameModifier` and `NativeTappable`
    (`OnTapModifier`) are **not** touched; the gate reaches them. Those are the
    **five** `registerHandlers` callers today (`grep -rn "registerHandlers(" Sources`);
    `Column`/`Row` reach it through `Box`, `List` rows through their elements,
    and `Component` through its members.
  - `Window` is **not** touched: with no hitbox for the disabled target, a
    press over it makes some other id `active` (or none), so a release on the
    re-enabled element fails `dispatchClick`'s `hit.id == pressed` (`EV-T`).
- **`EnvironmentValues.swift`**: `isEnabled`'s doc names the gate (`EV-E`,
  `EV-F`). **`EnvironmentCompileGuards.swift`**: G6's fixture gains
  `.disabled(true)` in its chain.

### Tests

New file `Tests/MetalUITests/DisabledTests.swift`.

**Why every test is red before lane 3.** `.disabled` does not exist (compile).
The "shell-only" reading below is what each test shows with `.disabled` present
but the gate absent.

The root of every window is an `Element` container (`Row`/`ZStack`), because a
scope cannot be a root (`EV-B`).

| # | test | shell-only red reading | mutation and what must redden |
|---|---|---|---|
| D1 | `disabledComposesAsAnAndAndARawWriteOverridesIt`. Probe B0–B8 as a recorder table in paint: `[true, false, true, false, false, true, false, false, false]`. | — (the value exists) | (a) `.disabled(d)` as `$0.isEnabled = !d` → the B3 and B6 slots read true; (b) `.environment(\.isEnabled, …)` special-cased to AND → the B5 slot reads false |
| D2 | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`. It mirrors `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`). **Arms are defined by their spelling, not by the type they produce**, and each is placed in a root `Row { … }` in both halves: `Box().onClick`, `Column { … }.onClick`, `Row { … }.onClick`, `Stack { … }.onClick`, `Text("x").onClick`, **a `.padding(4).frame(width: 20, height: 20)` chain with the `onClick` on the inner layer**, proposal `Rectangle(...).onTap`, a `Component` whose content is an `onClick` box with `.disabled(true)` on the component, and **two `List` arms** (third pass; a scope is not an `Element`, so it cannot be a row): **(list-row)** `List([Datum(id: 0)], rowHeight: px(40)) { _ in Box { Box().width(px(40)).height(px(40)).onClick { rec("list-row") }.disabled(true) } }`, whose control is the same with the inner `.disabled(true)` deleted — the wrapper `Box` is in both halves; **(list)** `List(...) { _ in Box() }.width(px(40)).height(px(40)).onClick { rec("list") }.disabled(true)`, control the same minus `.disabled(true)`. Each arm's **control**, identical minus `.disabled(true)`, fires once. **Plus the `EV-X` arm, which must FIRE:** `Box().width(px(20)).height(px(20)).disabled(true).frame(width: px(40), height: px(40)).onClick { rec("after") }` fires 1 (probe O2), against its **disagreeing spelling** `Box().width(px(20)).height(px(20)).frame(width: px(40), height: px(40)).onClick { rec("inside") }.disabled(true)`, which fires 0 (O1) | every disabled arm fires | always register the hitbox and focus with `handlers` (delete the `enabled` checks) → every disabled arm fires. `EV-X`'s hoist → the after arm reads 0. (lane 2b: **use the respelled hoist** — `FrameModifier` registering inside its content scope's values — because the `EnvironmentScope.frame` overload loses resolution when `.onClick` follows, and is void; decisions doc, `EV-X`) **There is no per-site mutation today:** the gate is central, so one edit reddens every arm. The arm list exists for a FUTURE site that registers a click without the gated method — including the composition track's `ModifiedElement` and, after the bridge merge, a gate placed in the 3-argument overload that `Text` and `OnTapModifier` bypass (`EV-W` item 4); record that as this test's stated purpose, not as measured per-site coverage. (lane 3: the proposal arm's root is an `HStack`, since a legacy `Row` cannot hold proposal content, and its rectangle is 100×100 so the click lands wherever the root places it; the list-row arm's `List` carries `.width(px(40))` in both halves; each control spells `.disabled(false)`, which probe B2 reads as enabled, so both halves share one structure. Measured: deleting the hitbox gate reddens all 11 disabled arms and not the after arm; the respelled hoist reddens only the after arm; the spec's overload is void again — decisions doc, `EV-E`, `EV-X`) |
| D3 | `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` (third pass, re-derived; `EV-E`). **(ancestor, aligned, probe N1/N2)** `Row { Box { Box().width(px(20)).height(px(20)).onClick { rec("child") }.disabled(true) }.width(px(40)).height(px(40)).onClick { rec("parent") } }` clicked at the child's centre → child 0, parent 1; **control** (child enabled) → child 1, parent 0 (N0/N3). **(sibling, a pre-existing divergence, P2f/P2m)** `ZStack { Rectangle(width: px(40), height: px(40)).onTap { rec("under") }; Rectangle(width: px(40), height: px(40)).onTap { rec("over") }.disabled(true) }` → under 1, over 0; **control** (over enabled) → under 0, over 1; **reference** `.allowsHitTesting(false)` instead of `.disabled(true)` → under 1, the same as the disabled arm. The doc states the sibling reading diverges from SwiftUI, whose shape blocks, and why it is not new: an enabled MetalUI `Box` with no `onClick` over a clickable sibling already passes the click | parent 0 and under 0 under the second pass's blocker; with no gate, child 1 and over 1 | `EV-E` (a) a blocker under a derived id → parent 0 and under 0; (b) the blocker under the element's own id → the same, plus D15/D16. (lane 3: the sibling rectangles are 100×100, placement-independent. (a) also reddens D16's consequence arm — the blocker is the hovered hitbox, not the parent) |
| D4 | `theGateReadsTheEnvironmentValueNotTheModifier`. Probe P8/P9: `.onClick` box under `.environment(\.isEnabled, true)` inside `.disabled(true)` → fires 1; under `.environment(\.isEnabled, false)` with no `.disabled` → 0. | P9 arm fires | gate on a `Frame.disabledDepth` counter that only `.disabled` increments → P8 reads 0 and P9 reads 1 |
| D5 | `aDisabledElementCannotAcquireFocus`. Probe K1: `window.focus(id)` on a `.focusable().onKey{…}` box inside `.disabled(true)`; draw → `window.focusedElement == nil`; a key event → `onKey` count 0. The **control** without `.disabled` → focused and count 1. | stays focused | register the ungated `handlers` → focused |
| D6 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`. **A divergence pin** (`EV-F`, probe K2 measured the opposite). Focus an enabled focusable box; draw; flip `model.disabled`; draw → `focusedElement == nil`; flip back; draw → still nil. The doc quotes K2. | stays focused | register `handlers` for a disabled element whose id is `focusedElement` → focus retained. This is exactly the SwiftUI-aligned alternative the divergence rejects. (lane 3: as spelled it also reddens D5, D11, D13 and D14 — a focus request makes the id `focusedElement` before registration, so the element acquires focus too. The alternative that keeps only a previously-held focus needs a signal `Frame` lacks, so no mutation separates D6 from D5 — decisions doc, `EV-F`) (lane 3's verifier: **refuted.** `Window.lastFocusRegistry` is that signal; handing it to `Frame` and keeping focus for an id disabled now and focusable last frame reddens D6 alone, `:499`/`:503` — decisions doc, `EV-F`) |
| D7 | `aDisabledElementsActionHandlerDoesNotClaimAKeymapAction`. A **context-free** `KeyBinding("cmd-i", Increment())`; a parent `Box` with `onAction(Increment.self)`, inside `.disabled(true)`, holding a child focusable box inside `.environment(\.isEnabled, true)`; `window.onAction` records. Focus the child; send cmd-I → the parent handler 0, `window.onAction` 1. The **control** is the parent enabled: parent 1, window 0. The doc pins the routing as MetalUI's (unprobed): an action nobody enabled claims reaches `Window.onAction`, like any unclaimed action; a **context-scoped** binding under a disabled pane does not match at all (D9) | parent 1 | register `handlers` → parent 1 |
| D8 | `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`. **A divergence pin** (`EV-F`; probe K6 shows SwiftUI's disabled parent's `.onKeyPress` runs). The parent `onKey` returns true and records, inside `.disabled(true)`; the focused child is re-enabled and its `onKey` returns false. A key → parent 0, and the event reaches `window.onInput`. The control (parent enabled) → parent 1. | parent 1 | keep `onKey` for a disabled element → parent 1 |
| D9 | `aDisabledPaneContributesNoKeyContext`. MetalUI's choice, **SwiftUI has no comparable concept** (`EV-S`). `KeyBinding("cmd-k", A(), context: "Pane")`; the pane `.keyContext("Pane")` inside `.disabled(true)` holds a re-enabled focused child with `onAction(A.self)` → the child handler 0 **and** `window.onAction` 0 (the binding does not match). The control (pane enabled) → child 1 | child 1 | keep `keyContext` for a disabled element → child 1 |
| D10 | Extends E5: the `.disabled(model.flag)` arm. The counter below `.disabled(model.flag)` keeps `n` across a flip and back, **and** a click while disabled does not increment it. | a click while disabled increments | the E5 `EitherGroup` mutation applied to `.disabled` → `n` resets. The gate-deletion mutation → it increments. Counted in E5, not as a new test. (lane 3: run as lane 2's value-keyed scope id, it reads 0 while disabled but 2 again after re-enabling — the original slot was only tombstoned — so the reset is seen only while the value differs — decisions doc, `EV-D`) |
| D11 | `reEnablingRestoresClicksButNotFocus`. Frame N disabled: click → 0. Frame N+1 enabled: click → 1, and the focus requested while disabled is not restored. | a click in frame N fires | cache the disabled state in a `$enabled` `StateTable` slot read on the next frame → the frame N+1 click reads 0 |
| D12 | `aDisabledElementsAXNodeCarriesTheDisabledTrait`. A `Box` with `handlers.axNode = AXNode(role: .button, label: "b")` set directly, as `AXEmitSiteTests.swift` does (there is no AX modifier), inside `.disabled(true)` → `frame.axNode(for:)` traits contain `.disabled`; the **control** (enabled) lacks it. **D12 cannot see the bridge merge** (third pass): it reads a frame that is not collecting, so it stays green whatever the record's `isEnabled` says. That is the joint test's job, `aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`, written at integration (`EV-W` item 4) | trait absent | delete the `traits.insert` → red |
| D13 | `aFocusRequestWhileDisabledLeavesNoRetentionSlot` (`EV-F`). Frame 1: `x` = `.focusable()` box inside `.disabled(true)`; `window.focus(x)`; draw → nil. Frame 2: `x` removed by an `if`; draw. `window.focus(x)`; draw → `focusedElement == nil`. **Instrument arm, pinned wrong on purpose:** the same sequence with `x` enabled but **not** `.focusable()` reads `x` — the known hazard in `Frame.swift`'s `$focus` paragraph, which proves the instrument can see a sticky focus. Below `StateTable.sweepThreshold` in both arms (`try #require`) | disabled arm reads `x` (lane 3: with no gate at all the disabled element is focusable, so the red reading is the arm's `try #require` that the first request is cleared) | write the `$focus` slot regardless of `enabled` → the disabled arm reads `x` (lane 3: measured, only this assertion) |
| D14 | `aDisabledScopeReachesIntoDeferredContent`. `Row { Row { Deferred { fixed-size Box().onClick(rec) } }.disabled(true) }` (the scope sits outside the `Deferred`, whose content must be an `Element`, and inside a root `Row`, since a scope cannot be a root): a click at the portal's rect → 0, and a focus request on a focusable box inside the portal → nil. **Control** without `.disabled` → 1 and focused. | 1 and focused | `PrepaintPass.deferred` sets the top to `rootEnvironment` around its body → 1 and focused |
| D15 | `aClickNeedsTheTargetEnabledAtPressAndAtRelease` (`EV-T`, probe R). A model-driven `.disabled(model.flag)` over an `onClick` box in a fake window; `mouseDown`, flip, draw, `mouseUp`. **R0 control** (no flip, enabled) → 1; **R1** pressed disabled, released enabled → 0; **R2** pressed enabled, released disabled → 0; **R3** disabled throughout → 0 | with no gate, R1, R2, R3 read 1 | `EV-T`'s mutation: a hitbox with empty `Handlers()` under the element's own id for a disabled target → R1 reads 1 |
| D16 | `aDisabledTargetIsNeitherHoveredNorPressed` (`EV-T`). A fixed-size `Box().onClick {}.hoverBackground(.accent).background(.surface)` inside `.disabled(model.flag)`; `mouseMoved` to its centre, draw → the rect is `.surface`, and a paint-phase recorder reads `isActive` false during a held press. **Control** (enabled) → `.accent` and `isActive` true. **Consequence arm** (MetalUI's, unprobed, `EV-S`): the same disabled box inside a 40×40 `Box { … }.onClick {}.hoverBackground(.accent).background(.surface)` parent → the **parent's** rect paints `.accent` with the pointer over the disabled child, as it does over any child without an `onClick`. (lane 3: the consequence arm has its own control, the child enabled, which reads the child hovered and the parent not) | `.accent` and true | `EV-T`'s mutation → the disabled arm paints `.accent` and reads `isActive` true (lane 3: measured, and the consequence arm too) |

**Divergence and inert rows, as tests.** D6 and D8 are the new divergence pins.
E8, E17 and E21 are lane 2's inert and divergence pins.

G6 gains `.disabled(true)` (no new guard); its mutation (d), `.disabled` made
internal, must print `failed` for G6.

Suite: 1118 → **1118 + 15 = 1133** (D10 extends E5 and adds no test). Guards:
53 → **53**.

---

## Lane 4 — the window capture and the merge re-measure (`EV-P`, `EV-W`)

No source or test edit; only `docs/record/11-environment.md` and the
decisions doc's `EV-P`/`EV-W` lines. Suite and guard counts stay at 1133 / 53,
re-read from an unfiltered run.

### The merge re-measure (`EV-W`)

After lane 3's commit, run `git merge-tree --write-tree --name-only` of
`feat/environment` against the **current** heads of `feat/ax-bridge` and
`feat/modifier-composition` (record both hashes). For each pair record the
conflicting files and the auto-merged ones, and for each `EV-W` item say
whether it is still loud, now loud, or still silent. In particular: does
`Frame.swift` now conflict in `registerHandlers` against the bridge (lane 3
edited the body the bridge also edits)? A clean textual merge there does
**not** make item 4 loud; say so if it happens. If either track has moved past
what `EV-W` describes (for example, the composition track's lane 2 or 3 has
landed), re-read its current spec and amend `EV-W` in the same lane.

### The window capture (`EV-P`)

**No input is sent to the real demo.** Build release at `f64e58a`
(`git worktree add`, in a scratch worktree) and at lane 3's commit. For each:

1. Run `swift run -c release MetalUIDemo`.
2. Wait 2 s.
3. Find the window id with a CoreGraphics listing script
   (`CGWindowListCopyWindowInfo`, owner `MetalUIDemo`), saved in the scratchpad.
4. Capture with `screencapture -l <id> -o <file>.png`.
5. Quit with `kill` (not Q, which would be input).

**Compare by region, not byte for byte.** The demo shows time- and
scroll-dependent text, so a whole-file `cmp` will almost certainly differ and
would say nothing. A CoreGraphics pixel script decodes both PNGs, requires equal
dimensions, and reports the bounding boxes of differing pixels. **Before
trusting it, run it on two captures of the base build taken seconds apart**:
that gives the dynamic regions, and its output must be non-empty or the script
is not seeing the text. The comparison passes when every differing box at the
lane's commit lies inside the base-vs-base dynamic boxes. Record the system
appearance, both images' sizes, the dynamic boxes, the differing boxes, and the
verdict in `docs/record/11-environment.md`. **A capture cannot see the Space
swap.** E18 is that evidence, and the record says so.

(lane 4) **Not taken.** Both release builds ran and each window was listed,
but the session was locked with the display asleep: `screencapture -l` printed
"could not create image from window", and ScreenCaptureKit returned -3811. An
offscreen stand-in, `demoContent()` through a real `Window` over the fake
platform, was byte-identical between `f64e58a` and lane 3 in light and dark,
and was checked first against two disagreeing controls. It is recorded as a
stand-in, not as the capture, which is owed to the integration step. The merge
re-measure found both tracks moved and amended `EV-W`: `Frame.swift` now
conflicts textually against the bridge, and item 4 is still silent; item 3
landed and is loud, measured on a built composition merge. Record 11, lane 4.

(lane 4 re-run, at `e709dc5`) **Capture still not taken**: the session was
still locked at 08:14–08:35 PDT, with the same `screencapture` and -3811
failures. **Both tracks had built their lane 3** (`feat/ax-bridge` `aa5d055`,
`feat/modifier-composition` `6a0169c`), so both merges were built and run in
scratch. The composition merge now conflicts in `ElementGroup.swift`. Item 1
landed: its loud half fails to compile, as predicted. Its silent half was
measured sufficient after a scratch port, 1162 passed: the push, cursor and
value-keyed mutations redden E11, E22 and E23, and the twice-delegation mutant
needs the two wrapper arms. Item 4 is still silent at `aa5d055` (1189 passed
with the literal either way), and its gate-in-the-3-argument-overload hazard is
now loud (D2 text and proposal, D3). `EV-W` and the section below were amended.
Record 11, "Lane 4, re-run".

---

## Verification common to every lane

- **Read the summary line, never the exit status.** The totals must equal the
  table above exactly: 1085 after lane 1, 1112 after lane 2, 1118 after lane 2b, 1133 after lane 3 and lane 4.
  A shortfall is a truncated run (shape 11). `grep -c "error:"` and
  `grep -c "warning:"` must both read 0. `--build-system native` prints its own
  deprecation line: tell it apart from a compiler warning, and record which it is.
- **Clean builds.** Lane 2 adds a public type to `MetalUICore` and a stored
  property to `Frame`: `swift package clean` before its first test run.
- **Goldens.** `git diff --stat f64e58a -- '*.json'` is empty, and
  `find Tests -name "*.json" | wc -l` reads 97. No lane edits
  `Sources/MetalUILayout/`. A moved golden is a stop.
- **Guards.** Count with per-file `grep -c canTypecheck`, including the new
  `EnvironmentCompileGuards.swift`, under `--build-system native`. Mutate each
  new guard red once.
- **Mutations.**
  - Run them in a scratch `git worktree`, one at a time. Restore from git, or
    from a copy if the file has uncommitted work, and confirm with
    `git status --short`.
  - Name the tests each mutation reddens, and write that into the ruling's
    "Mutations" line.
  - A mutation that reddens nothing is either a broken instrument or the
    finding. E6(c) is a predicted example of the first kind, and E21's may be;
    confirm both.
- **Timing.**
  - No test sleeps.
  - Animation-adjacent tests drive `simulateTick(timestamp:)`.
  - E15 counts pushes, snapshots and transforms, never time.
- **Exit tests.** One trap is designed, lane 2b's `EV-Z` precondition, pinned
  by T1/T2 with `#expect(processExitsWith:)` as `FontResolverTrapTests.swift`
  and `ElementGroupTrapTests.swift` do, in the same change. Any other
  precondition a lane adds is pinned the same way in the same change.
- **Device-dependent tests.** Use `try #require(MTLCreateSystemDefaultDevice())`,
  not `makeFakeWindowOnDefaultDevice`, so a displayless runner skips rather than
  hard-fails (CLAUDE.md, "When CI lands").
- **Phase rule.** No lane adds a `PaintPass`-only query. Should one become
  necessary, it gains a guard and a bullet in `PhaseSeparationTests.swift`'s
  header in the same change (CLAUDE.md).

## Files, in one place

| file | lane | new/shared | edit |
|---|---|---|---|
| `Sources/MetalUI/Keymap.swift` | 1 | shared | rename + alias + docs |
| `Sources/MetalUI/KeyContext.swift` | 1 | shared | one doc line |
| `Sources/MetalUIDemo/main.swift` | 1 | shared | nine call sites |
| `Tests/MetalUITests/KeymapTests.swift` | 1 | shared | respell |
| `Sources/MetalUICore/LayoutDirection.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentValues.swift` | 2, 2b, 3 | new | 2b: bare locale, docs; 3: `isEnabled` doc |
| `Sources/MetalUI/EnvironmentProperty.swift` | 2, 2b | new | 2b: one doc line |
| `Sources/MetalUI/EnvironmentScope.swift` | 2, 2b (doc), 3 (`.disabled`) | new | |
| `Sources/MetalUI/Frame.swift` | 2, 2b, 3 | shared | top, root, counters, `theme`; 2b: `isRendering` + setter precondition; 3: `registerHandlers` gate, `$focus` doc |
| `Sources/MetalUI/Passes.swift` | 2 | shared | three accessors, one doc |
| `Sources/MetalUI/Window.swift` | 2, 2b | shared | one property, one statement after `Frame(...)`; 2b: the property's initial value |
| `Sources/MetalUI/ElementGroup.swift` | 2 | shared | three bind calls |
| `Sources/MetalUI/Component.swift` | 2 | shared | one bind call |
| `Sources/MetalUI/StateReflection.swift` | 2 | shared | binder signature, shape cache |
| `Sources/MetalUI/Handlers.swift` | 3 | shared | doc only |
| `Tests/MetalUITests/EnvironmentTests.swift` | 2, 2b | new | 2b: E12 arm, E22–E24, E8/E11 docs |
| `Tests/MetalUITests/EnvironmentTrapTests.swift` | 2b | new | T1, T2 |
| `Tests/MetalUITests/EnvironmentCompileGuards.swift` | 1, 2, 2b, 3 | new | 2b: G6; 3: `.disabled` in G6 |
| `Tests/MetalUITests/DisabledTests.swift` | 3 | new | |
| `docs/record/11-environment.md` | all | new (track) | append per lane; lane 4: capture and merge re-measure |
| `docs/probes/swiftui-disabled-ancestor-and-order.swift`, `docs/probes/swiftui-environment-pixel-length.swift` | third design pass | new | committed with recorded output |
| `docs/superpowers/2026-09-15-environment-decisions.md` | all | new (track) | fill "Mutations" lines |

`Tests/MetalUITests/Fakes.swift` needs no edit. `simulateInput`, `readPixels`,
`makeFakeWindow` and `lastScene` suffice.

## Owed to the integration step (not written by this track)

**Merge obligations.** `EV-W` is the normative list, re-taken in the third pass
against `feat/ax-bridge` at `53d3bf6` and `feat/modifier-composition` at
`ec65da6`, re-measured by lane 4 against **`dbfa314`** and **`6d0ea97`**
(both tracks had built their lane 2), and re-measured again by lane 4's re-run
against **`aa5d055`** and **`6a0169c`** (both tracks had built their lane 3;
both merges built and run in scratch). **Not every item is loud**; the summary:

- **Precondition (`EV-W` item 0).** Do not integrate this branch before lane 3's
  commit: at `f4dcad8` `isEnabled` compiles, is documented as a gate and is read
  by nothing. Check: `grep -n "isEnabled" Sources/MetalUI/Frame.swift` is
  non-empty and `Tests/MetalUITests/DisabledTests.swift` exists. (lane 4: met
  at `6957464`.)
- **The release-window capture (`EV-P`), not taken by lane 4.** The session was
  locked, at both of lane 4's runs (04:35–04:55 and 08:14–08:35 PDT). Take it on an unlocked session by lane 4's method: base `f64e58a`
  against the merged tree, no input, compared by region after a base-vs-base
  calibration. The composition track owes the same capture (`MC-J`), so one run
  can serve both.
- **Modifier composition, lane 3 (`EV-W` item 1).** Loud: `EnvironmentScope`'s
  empty conditional conformance stops compiling. **Silent unless re-run:** the
  typed `requestProposalGroupLayout` must call
  `pass.frame.scopedValues(applying: write)` once, `pass.frame.withEnvironment(values) { … }`
  around `content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)`,
  and forward `parent` and `cursor` unchanged (the code is in `EV-W`). E11, E22
  and E23 are written in the marker shape that merge rejects: **port them to
  `ProposalElement`** (E11's layout reading inside `requestProposalLayout`), then
  **re-run** E11(b), E4(b)/(c) and E5's value-keyed id against the typed entry
  and confirm E11, E22 and E23 redden. E11 absorbs the composition track's
  `aProposalContainerReadsTheEnvironmentDuringLayout` arms; do not add a second
  test. The composition track's text "`bind` gains `environment:`" and "pass
  `pass.frame.environment`" is stale: the API is `StateBinder.bind(_:in:id:)`,
  and there is no `Frame.environment`. (lane 4: the composition spec at
  `6d0ea97` has corrected both. It also owes two `EnvironmentScope` arms in
  `everyModifierWrapperDelegatesEachPhaseExactlyOnce`, one legacy and one
  proposal, each `[1, 1, 1]`, with the mutation "the typed entry calls content
  twice". Its lane 3 is not built, so this item is unchanged.) (**lane 4
  re-run: its lane 3 LANDED at `6a0169c`.** `merge-tree` now exits 1 on
  `ElementGroup.swift`; take `enteringGroupMember` and respell
  `GroupMember.swift:39`'s bind. Measured on a scratch merge:
  `EnvironmentScope` does not conform, `EV-W`'s typed entry compiles verbatim,
  and E11's and E23's fixtures fail to compile. After the port, 1162 passed. The
  no-push mutation reddens E11's layout slot, the cursor mutations E22, and the
  value-keyed parent E22 and E23. **The content-twice mutation passes until the
  two wrapper arms exist**, and reddens the proposal arm (`[2, 1, 1]`) once
  they do. The scratch merge was discarded; do all of it on the real tree.)
- **`StateBinder.bind` (`EV-W` item 2).** Loud. `MC-H`'s helper calls
  `bind(element, in: pass.frame, id: id)`. No default, no compatibility overload.
  (lane 4 re-run: measured loud against `6a0169c`, `GroupMember.swift:39:25`
  "incorrect argument label"; the bridge's `ElementGroup.swift` hunk also spells
  `table:`.)
- **Modifier composition, lane 2 (`EV-W` item 3).** `FrameModifier.swift` is
  deleted. D2's arms (including its after-`.disabled` arm) and E12's
  after-`.theme` arm are spelled with `.frame(width:height:)`, so they run
  against `ModifiedElement` unchanged and must stay green; `EV-E`'s "five
  callers" is re-taken with the grep. (lane 4: **landed there, loud,
  measured.** On a built scratch merge, 1152 tests passed. The callers are
  still five, with `ModifiedElement` in `FrameModifier`'s place. A gate bypass
  in `ModifiedElement.prepaintLayer` reddens exactly D2's padding-frame and
  inside arms. Relabel `FrameModifier` → `ModifiedElement` in
  `Frame.registerHandlers`' doc.)
- **Accessibility bridge (`EV-W` item 4) — SILENT.** (lane 4) `Frame.swift`
  **now conflicts** against `dbfa314`, in two hunks inside `registerHandlers`.
  That does not make the item loud: the bridge's record literal
  `isEnabled: true` sits outside both hunks, auto-merges, and keeps compiling
  under every resolution that compiles.
  Write the merged 5-argument `registerHandlers` exactly as `EV-W` gives it:
  the gate in the 5-argument implementation (the 3-argument overload stays a
  bare forward), no hitbox and no focus registration when disabled, the
  declared node's `.disabled` trait, and the record's `isEnabled: enabled`,
  with presence and role read from the ungated `handlers` and actions left to
  the gated registrations. Then write the joint test under the bridge's name,
  `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`.
  It has three arms (clickable, focusable and adjustable only), each with a
  control, and four mutations as reconciled in `EV-W`. Run those mutations.
  (lane 4: this supersedes the third pass's
  `aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`.)
  Reconcile the bridge's `AB-Z` to it. Its `$disabled` blocker hitbox, and
  the blocker mutation, were withdrawn here (`EV-E`, third pass). So were the
  first version's `keyboard` copy, ungated `$focus` write and `environment:`
  init parameter. `Text` and `OnTapModifier` do not yet call the 5-argument
  method directly; the bridge's lane 3 adds those calls (`AB-F`, `AB-Y`), and
  with them D2's text and onTap arms become the check that the gate is in the
  5-argument body. (**lane 4 re-run, at `aa5d055`:** those calls exist. A gate
  in the 3-argument overload reddens D2's "text" and "proposal" arms and D3,
  measured. Hunk 2 now carries `AB-L`'s `declaration`: keep it, and insert the
  trait on a copy of `handlers.axNode` inside `if !declaration.isEmpty`, as
  `EV-W`'s method now shows; the bridge's side alone reddens D12. The four
  wholesale resolutions do not compile. The correct resolution passes 1189
  with `isEnabled: true` and with `enabled`, so the item is still silent. The
  bridge's spec at `aa5d055` still has the `$disabled` blocker and "lane 3
  designed". D12's doc comment names the superseded joint-test name; relabel
  it.)
- **`Frame.init` (`EV-W` item 5).** No parameter from this track; the bridge's
  `collectsAccessibility:` lands alone. The `Window.swift` conflict is the one
  statement after the `Frame(...)` expression. (lane 4: unchanged at
  `dbfa314`. The `ElementGroup.swift` hunk is the bind line against the bridge's
  `AB-O` block; keep both, bind first.)
- **Unowned deferrals — flag, do not assume.**
  - `.padding` and handler modifiers directly on a scope (`EV-B`, `EV-X`) were
    handed to task 3, but the modifier-composition spec never mentions
    `EnvironmentScope`. (`.frame` already follows a scope.)
  - "Hover and pressed on a disabled element; focus retention on disable" was
    handed to task 12, but the AX-bridge spec says "disabled behaviour … wait[s]
    for task 9". Hover and pressed are decided here (`EV-T`); focus retention
    and a disabled look remain **unowned**.
  - A hit shape separate from `onClick` (`EV-E`'s sibling divergence).

**Documents:**

- **CLAUDE.md.**
  - An Architecture paragraph on the environment: scoping, transparency,
    once-per-frame transforms, paint-only theme, the gate, and `@Environment`
    binding.
  - Divergences: `EV-K` (RTL not mirrored), `EV-F` (focus lost on disable;
    raw `onKey` and `keyContext` removed while SwiftUI keeps `.onKeyPress`),
    `EV-J` (no `displayScale`), `EV-U` (`pixelLength` tied to the device: no
    scope can change it and a `\.self` reset does not reset it, where SwiftUI's
    follows `displayScale`; pixel-length probe X1/X2), `EV-E`'s sibling half (a
    disabled click target passes the click to an enabled sibling under it,
    where SwiftUI's shape blocks — the same difference every non-clickable
    MetalUI overlay already has; the ancestor half is aligned, probe N), and
    the key handler order (SwiftUI runs an ancestor's `.onKeyPress` before the
    focused view's; MetalUI bubbles outward from the focused element; probe K5).
  - Inert rows: `@Environment` inside `AnyElement`; `@Environment` never bound
    returns the default silently; `layoutDirection`'s writer affects no layout;
    `locale` has no consumer (`Text`'s tokenizer and typesetter never receive
    it); `pixelLength` has no internal reader; an in-module write to
    `Frame.rootEnvironment.theme` or `.pixelLength` (or to
    `window.environment.theme`) is silently re-stamped.
  - Reserved names: **none added** by this track (third pass; the second
    pass's `$disabled` suffix was withdrawn with the blocker hitbox).
  - A paragraph on `.disabled`: no hitbox, so a click reaches an enabled
    ancestor; out of the keyboard entirely; a modifier written after the scope
    (`.disabled(true).frame(…).onClick`) sits outside it and fires (`EV-X`).
  - `Frame.rootEnvironment` traps if set during `render` (`EV-Z`).
  - `Window.environment`: every write dirties, a no-op included; write from
    input, never from a phase (a phase-time write keeps the link awake).
  - The guard-count file list gains `EnvironmentCompileGuards`.
  - Demo keys: none change.
  - Counts.
- **`docs/record/README.md`.** Index `11-environment.md`.
- **The plan.** ~~Tick task 9, with its carried items (`EV-Q`)~~ (record: **do
  not tick yet** — the plan's own text names "control state" apart from enabled
  state and "scale", and `controlActiveState`/`controlSize`/`displayScale` are
  not delivered; record 11, "For the integrator", item 3). Note in task 10
  that the `Binding` alias must be deleted in the change that adds `Binding`.
- **`PhaseSeparationTests.swift`'s theme section comment.** It stays true; add
  one sentence pointing at `G1−` for the environment spelling. This is a test
  file, which lane 2 may edit, but the sentence is listed here in case lane 2
  leaves it.
