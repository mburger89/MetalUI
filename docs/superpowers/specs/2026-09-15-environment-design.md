# Environment and control state design

**Milestone:** plan task 9 of `plans/2026-09-12-swiftui-alignment.md`, "Expand
the environment and control-state model", on `feat/environment`.

**Status (2026-09-14): design only.** This was written against `f64e58a`, and no
source has changed. Rulings are prefixed **`EV-`** and lettered, in
`docs/superpowers/2026-09-15-environment-decisions.md`. A bare `EV-3` is a
typo, not a citation. What was measured is in `docs/record/11-environment.md`.

**Parallel-track constraint.** Three tracks run at once, in separate worktrees,
and are merged afterwards. So this design:

- **Prefers new files.** Most of it is new.
- **Keeps shared-file edits additive and local.** Each is listed per lane, with
  its size, under "Files".
- **Leaves some documents alone:** `CLAUDE.md`, `AGENTS.md`, `README.md`, the
  plan, `docs/record/README.md`, the existing record files, and the `SA-`
  decisions doc. The integration step owns those. Text owed to them is listed
  at the end, under "Owed to the integration step".

## What this design delivers

1. **Scoped environment values** with SwiftUI's nearest-writer precedence
   (`EV-A`). Writers are layout- and identity-transparent (`EV-B`), and the API
   copies SwiftUI's names (`EV-C`):
   - `EnvironmentValues`, `EnvironmentKey` and `@Environment`;
   - the modifiers `.environment(_:_:)`, `.transformEnvironment(_:transform:)`,
     `.disabled(_:)`, `.dynamicTypeSize(_:)` and `.theme(_:)`;
   - `pass.environment` on all three passes;
   - `Window.environment`.
2. **Values**, each with a source, a phase and an effect:
   - `theme`: scoped, paint-only (`EV-G`);
   - `isEnabled` (`EV-D`);
   - `layoutDirection`: carried, not yet mirrored (`EV-K`);
   - `locale` (`EV-H`);
   - `dynamicTypeSize`: carried, with no text effect on macOS, as in SwiftUI
     (`EV-I`);
   - `pixelLength`: read-only (`EV-J`);
   - custom keys.
3. **A disabled control state.**
   - It suppresses clicks and taps on legacy and proposal elements, swallowing
     rather than passing through (`EV-E`).
   - It suppresses focus acquisition and keymap action handlers (`EV-F`).
   - It adds the AX `disabled` trait.
   - All of it happens through **one** gate in `Frame.registerHandlers`.
4. **`Binding` → `KeyBinding`**, with a deprecated alias (`EV-N`).
5. **Proof that nothing else moved.**
   - The Space-key theme swap works through the fake platform, and the demo is
     captured at launch with no input (`EV-P`).
   - The 97 goldens are unmoved: no lane touches `Sources/MetalUILayout/`.

Not delivered, each with its owner: `EV-Q`.

## Evidence this design stands on

Three probes. All were run in this session, and their recorded output is in
their headers:

| probe | arms | rulings |
|---|---|---|
| `docs/probes/swiftui-environment-scoping.swift` | A precedence, B `isEnabled`, C defaults, D state retention, E layout transparency, F overlay scope, G dynamic type, H RTL | `EV-A`, `EV-B`, `EV-D`, `EV-G`…`EV-K` |
| `docs/probes/swiftui-disabled-interaction.swift` | P pointer (13 arms incl. 6 controls), K focus/keys | `EV-D`, `EV-E`, `EV-F` |
| `docs/probes/swiftui-environment-api-shape.swift` | compile-only: writable vs get-only members | `EV-C`, `EV-J` |

The baseline at `f64e58a` is **1084 tests, 97 goldens and 45 guards**, with 0
`error:` (decisions doc, "Baseline").

---

## Public API (all lanes)

These signatures are normative. A lane that must deviate records the reason as a
new `EV-` ruling.

```swift
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
    public var locale: Locale                        // Locale.current, read in init()
    public var dynamicTypeSize: DynamicTypeSize      // .large
    public internal(set) var pixelLength: Double     // 1; Frame sets 1/scaleFactor (EV-J)
    var theme: Theme                                 // .light; INTERNAL — PaintPass.theme only (EV-G)
    public subscript<K: EnvironmentKey>(key: K.Type) -> K.Value { get set }
}

public enum LayoutDirection: Sendable, Hashable, CaseIterable {
    case leftToRight, rightToLeft
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
    public var wrappedValue: Value { get }           // snapshot bound per phase; default if unbound (EV-M)
}

// Sources/MetalUI/EnvironmentScope.swift  (new, lane 2)
public struct EnvironmentScope<Content: ElementGroup>: ElementGroup {
    // stores `content` and `transform: @MainActor (inout EnvironmentValues) -> Void`
    // requestGroupLayout: forwards parent AND cursor unchanged; returns content's nodes unchanged
    // each phase: pass.frame.withEnvironment(transform) { content.<phase>Group(...) }
}
extension EnvironmentScope: ProposalElementGroup where Content: ProposalElementGroup {}

extension ElementGroup {
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                               _ value: V) -> EnvironmentScope<Self>
    public func transformEnvironment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>,
                                        transform: @escaping @MainActor (inout V) -> Void)
        -> EnvironmentScope<Self>
    public func disabled(_ disabled: Bool) -> EnvironmentScope<Self>         // lane 3: $0.isEnabled = $0.isEnabled && !disabled
    public func dynamicTypeSize(_ size: DynamicTypeSize) -> EnvironmentScope<Self>
    public func theme(_ theme: Theme) -> EnvironmentScope<Self>              // writes the internal field
}

// Sources/MetalUI/Passes.swift  (shared, lane 2 — three additive lines)
extension LayoutPass   { public var environment: EnvironmentValues { get } }
extension PrepaintPass { public var environment: EnvironmentValues { get } }
extension PaintPass    { public var environment: EnvironmentValues { get } }
// PaintPass.theme keeps its spelling; Frame.theme becomes `environment.theme`.

// Sources/MetalUI/Window.swift  (shared, lane 2 — one property, one argument)
extension Window { public var environment: EnvironmentValues { get set } }   // didSet → setNeedsRedraw()

// Sources/MetalUI/Keymap.swift  (shared, lane 1)
public struct KeyBinding { /* was `Binding`; body unchanged */ }
@available(*, deprecated, renamed: "KeyBinding")
public typealias Binding = KeyBinding
```

**Internal (in-module) additions:**

```swift
// Frame.swift (shared, lane 2)
init(..., transaction: Animation? = nil, environment: EnvironmentValues = EnvironmentValues())
    // root = environment; root.theme = theme; root.pixelLength = scale > 0 && finite ? 1/scale : 1
var environment: EnvironmentValues { get }              // top of stack
var theme: Theme { environment.theme }                  // replaces `let theme`
func withEnvironment<R>(_ transform: (inout EnvironmentValues) -> Void, _ body: () -> R) -> R
private(set) var environmentPushCount: Int              // EV-O, test observable

// StateBinder (StateReflection.swift, shared, lane 2)
static func bind<E>(_ element: E, table: StateTable, environment: EnvironmentValues,
                    id: GlobalElementID)
// the five call sites pass `pass.frame.environment` (Frame.render: `environment`)
```

**Where writers are and are not usable.** This is compile-time and deliberate
(`EV-B`).

- **Usable** over any `ElementGroup`: legacy elements, proposal content
  (conformance kept), `Component`, builder groups.
- **Not usable** as a window root, as `Deferred` content, or as a `List` row,
  because each of those requires `Element`. Write the scope outside instead.
- **Not usable** before a `StyledElement` modifier: write `.padding(4).disabled(true)`,
  not `.disabled(true).padding(4)`.

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
| `G5` `theDeprecatedBindingSpellingStillCompilesAndPointsAtKeyBinding` — a plain-import `typecheck` fixture: `let k = Keymap([Binding("cmd-k", A())])`, where `A: Action`. Asserts `succeeded` **and** `messages.contains("KeyBinding")` (the deprecation warning's rename text). | new `Tests/MetalUITests/EnvironmentCompileGuards.swift` | `KeyBinding` does not exist, so `messages` has no "KeyBinding" | (a) delete the typealias → `succeeded` false; (b) drop `@available(deprecated…)` → `messages` lacks "KeyBinding" |
| every existing `KeymapTests` test, respelled | `KeymapTests.swift` | does not compile before the rename | not a new mutation: the file's existing mutation records stand |

**Warnings.** After lane 1, `grep -c "warning:"` over the build and test log
must read 0. The demo and tests use no deprecated spelling. `G5`'s warning is
printed by the child `swiftc`, which the test captures, so it does not reach the
suite log. **Check that, don't assume it.**

Suite: 1084 → **1085**. Guards: 45 → **46**.

---

## Lane 2 — the environment (`EV-A`, `EV-B`, `EV-C`, `EV-G`…`EV-M`, `EV-O`, `EV-P`)

### Changes

**New files:**

- `Sources/MetalUI/EnvironmentValues.swift`: `EnvironmentValues`,
  `EnvironmentKey`, `LayoutDirection` and `DynamicTypeSize`.
- `Sources/MetalUI/EnvironmentProperty.swift`: `Environment<Value>` and its
  internal `BindableEnvironment` conformance.
- `Sources/MetalUI/EnvironmentScope.swift`: `EnvironmentScope`, and the
  `ElementGroup` modifiers except `.disabled`, which lane 3 adds.

**Shared files, each edit additive and local:**

- **`Frame.swift`.**
  - `let theme` becomes a computed property over the environment stack. Update
    its doc: it is scoped now, still paint-only, and still fixed per scope for
    the whole frame.
  - Add the stack, `withEnvironment`, `environmentPushCount`, and the `init`
    parameter `environment:` with the root rules.
  - `Frame.render`'s `StateBinder.bind` passes `environment`.
  - About 40 lines.
- **`Passes.swift`.** Add three `environment` accessors. Amend `PaintPass.theme`'s
  doc: "the nearest `.theme(_:)`, else the window's".
- **`Window.swift`.** Add `public var environment`, and pass
  `environment: environment` to `Frame(...)` in `drawFrameIfNeeded`.
- **`ElementGroup.swift`.** Three `StateBinder.bind` calls gain
  `environment: pass.frame.environment`.
- **`Component.swift`.** One such call.
- **`StateReflection.swift`.**
  - The shape cache records `Environment` ordinals alongside `State` ordinals.
    The miss path checks `as? BindableState` and then `as? BindableEnvironment`.
  - `reflectionCount` semantics are unchanged: one per type.

### Tests

New file `Tests/MetalUITests/EnvironmentTests.swift`. Every test is `@MainActor`.

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
| E1 | `theNearestWriterWinsAndAScopeEndsWithItsSubtree`. A legacy `Row` of recorder leaves mirrors probe A0–A6: no writer; `.environment(\.probe, 1)`; `.environment(\.probe, 2).environment(\.probe, 1)`; an outer scope 1 holding [inner-less, inner 2, sibling]; and a leaf after the scope. It expects `[0, 1, 2, 1, 2, 1, 0]`, read in **paint**. | all zeros | (a) outer writer wins: `withEnvironment` pushes the transformed copy only when the key still holds the root's value, else re-pushes the top unchanged → A2 and A4 read 1. (b) Skip the pop (remove its `defer`) → values leak to later siblings: A6 reads non-zero, and every slot after the first writer reads a leaked value. (Applying the transform to the ROOT instead of the top is invisible here, since each arm writes one key once; E2 carries that mutation) |
| E2 | `aTransformComposesWithTheInheritedValueAndAWriteBelowItReplacesIt`. Probe A7/A8 → `[110, 5]`. | `[0, 0]` | `transformEnvironment` starts from `EnvironmentValues()` instead of the inherited copy → 10 and 5, so the A7 slot reddens |
| E3 | `anEnvironmentValueReadsIdenticallyInAllThreePhases`. A recorder `Element` logs `pass.environment.probe` in `requestLayout`, `prepaint` and `paint`, for a leaf in scope 2, a sibling after it in scope 1, and a leaf outside any scope. It expects `[[2,2,2],[1,1,1],[0,0,0]]`. | all zeros | `EnvironmentScope.prepaintGroup` forwards without `withEnvironment` → the middle (prepaint) element of the first two triples reads 0, because neither scope pushes in prepaint. The same mutation in `paintGroup` → the third (paint) element reads 0. Both are run and recorded separately |
| E4 | `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex`. (i) `Row { Pair(A, B).environment(\.probe, 1) ; C }` gives the row 3 children, and C's `GlobalElementID` equals C's id in `Row { Pair(A, B); C }`. (ii) A's id equals A's id without the scope. Ids are captured by a recorder in `prepaint`. | red only if the shell registers a node | (a) `EnvironmentScope.requestGroupLayout` wraps the nodes in `pass.requestNode(style: Style(), children:)` → child count 2; (b) `cursor += 1` before forwarding → C's id moves; (c) forward `under: GlobalElementID.child(of: parent, at: cursor, name: nil)` with a fresh cursor → A's id moves |
| E5 | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`. A real `makeFakeWindow`. A root `Row` holds a `Counter` element with `@State var n`, incremented by `onClick`, wrapped in `.environment(\.probe, model.value)`. Click twice, change `model.value`, draw; `n` reads 2. Probe D1. (Lane 3 adds a `.disabled(model.flag)` arm to this same test; see L3-D10.) | passes on arrival for the environment arm, since there is no mechanism to lose state yet; red only in lane 3's arm, before `.disabled` exists. This is **stated and accepted**: the test exists for the mutation | implement `environment(_:_:)` as a value-keyed `EitherGroup` (`value == default ? .first(self) : .second(scope)`) → `n` resets to 0 when the value moves off the default |
| E6 | `anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame`. An `Element` with `@Environment(\.probe) var probe` logs `probe` in all three phases, under a scope reading `model.value`. Frame 1 at 3 gives `[3,3,3]`; frame 2 at 4 gives `[4,4,4]`. | `[0,0,0]` | (a) the binder skips binding when the box already holds a snapshot → frame 2 reads `[3,3,3]`; (b) `ElementGroup.prepaintGroup` passes `Frame`'s root environment → prepaint reads 0; (c) delete the re-bind in `paintGroup` → paint reads the layout snapshot, which cannot differ within a frame, **so (c) is expected to stay green**. Record it as the instrument's limit, not as coverage, and cover (c) through E7 |
| E7 | `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint`. `let r = EnvRecorder(); Row { r.environment(\.probe, 1); r.environment(\.probe, 2) }` reads `[1, 2]` in paint. This is divergence 19's read half. | `[0, 0]` | delete the re-bind in `ElementGroup.paintGroup` → `[2, 2]` |
| E8 | `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`. It is pinned **inert on purpose** (`EV-M`). An `AnyElement` wrapping an `@Environment` reader inside `.environment(\.probe, 5)` reads 0. | — (describes a limit) | none. It flips when `AnyElement` binding lands |
| E9 | `aComponentReadsTheNearestEnvironmentInItsContent`. A `Component` with `@Environment(\.probe)` whose `content` is `Box().background(probe == 1 ? .accent : .surface)` of fixed size. Inside `.environment(\.probe, 1)`, the scene's rect is `.accent` resolved; bare, it is `.surface`. | both `.surface` | `Component.requestGroupLayout`'s bind passes `EnvironmentValues()` → the scoped arm reads `.surface` |
| E10 | `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState`. `Counter`-style component state survives `MyComponent()` → `MyComponent().environment(\.probe, 1)` across two frames in one `StateTable`, compared by id as in `addingAModifierDoesNotResetAComponentsState`. | — | mutation E4(b) reddens this too. Record both names |
| E11 | `proposalContentReadsTheEnvironmentThroughAScope`. `HStack { Rectangle(...).environment(\.probe, 7) }` plus a native recorder leaf read in paint → 7. The same scope over `ProposalScrollView` content → 7. | 0 | E3's `paintGroup` mutation reddens it. It exists because the composition (proposal kernel, scope) is otherwise absent from the corpus (taxonomy shape 9), not for a mutation of its own |
| E12 | `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`. In a `Row`: a `.surface` box inside `.theme(.dark)`, a `.surface` sibling outside it, and a `Deferred { .surface box }` inside `.theme(.dark)`. The scene colours are dark, light, dark. | light, light, light | (a) `PaintPass.theme` returns the root theme → the first arm reads light; (b) `PaintPass.deferred` pushes the root environment → the third arm reads light |
| E13 | `theFramesThemeParameterIsTheRootTheme`. `Frame(theme: .dark, environment: EnvironmentValues())` renders a `.surface` box dark, and `pixelLength` reads 0.5 at `scaleFactor: 2` and 1 at `scaleFactor: 1`. | light; 1 at scale 2 | (a) the root ignores `theme:` → light; (b) `pixelLength = Double(scaleFactor)` → 2 at scale 2. The scale-2 arm is what discriminates, because the fake surface is scale 1 |
| E14 | `theWindowsEnvironmentReachesTheFrameAndASetRepaints`. A fake window: after one frame, `needsRedraw` is false; set `window.environment.locale` to a locale whose identifier differs from `Locale.current.identifier` (`de_DE`, or `fr_FR` if the machine is `de_DE`; `try #require` that they differ) → `needsRedraw` true; the next frame's recorder reads it. Defaults on a fresh window: `isEnabled`, `.leftToRight`, `Locale.current.identifier` and `.large`, matching probe C. | the recorder reads the default locale | (a) drop the `didSet` → `needsRedraw` false; (b) `drawFrameIfNeeded` omits `environment:` → the recorder reads `Locale.current` |
| E15 | `environmentWorkScalesWithWritersNotWithTheirDescendants`. **Performance, counts work**, on a branching 4×5×3 tree of fixed-size `Box`es (the shape CLAUDE.md's Performance section counts cache misses on): no writer gives `environmentPushCount == 0`; one writer at the root child gives 3; two nested writers give 6; and the same writers over a 1×1×1 tree give the same counts. Counts are `try #require`d before comparison. | the counter does not exist (compile) | `Element.requestGroupLayout` (default) wraps `requestLayout` in `frame.withEnvironment({ _ in })` → one extra push per element in layout, so the big tree's count exceeds the small tree's and the equality fails |
| E16 | `dynamicTypeSizeChangesNoTextMeasurement`. A fixed-string `Text` measures the same width and height bare and under `.dynamicTypeSize(.accessibility5)`, with a positive control: `.font(size: 26)` differs. Probe G. | — (passes on arrival once it compiles: aligned behaviour) | multiply `Text`'s `fontSize` by 1.5 when `pass.environment.dynamicTypeSize.isAccessibilitySize` → red. **Revert.** The test exists so a later "fix" must face probe G |
| E17 | `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`. **Pinned wrong on purpose** (`EV-K`). `HStack(spacing: 0) { Rectangle(width: 10, height: 10); Rectangle(width: 20, height: 10) }` with `.frame(width: 100, alignment: .leading)`, inside `.environment(\.layoutDirection, .rightToLeft)`, places at x 0 and 10. The doc quotes probe H's 90 and 70. | — | none owed. It flips with task 6 |
| E18 | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` (`EV-P`). A fake window with `keymap = Keymap { KeyBinding("space", ToggleThemeFixture()) }`, and `onAction` flipping `window.theme` for that action type and returning true. Draw; the background rect of a full-size `.background` box is `Theme.light.background`. `simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: " ", characters: " ", timestamp: 0)))` returns true; draw; the rect is `Theme.dark.background`. | — (passes on arrival once lane 1 exists: a regression pin) | E13(a) → the second read stays light. Also: `Frame.theme` computed from `EnvironmentValues().theme` → light |

**Typecheck guards**, in `Tests/MetalUITests/EnvironmentCompileGuards.swift`
(plain import, `canTypecheck`-gated, per the file header convention of
`PhaseSeparationTests`):

| # | guard | kind | mutation that must redden it |
|---|---|---|---|
| G1+ | `environmentValuesAreReadableInEveryPhase`. One fixture reads `pass.environment.isEnabled`, `.layoutDirection`, `.locale`, `.dynamicTypeSize`, `.pixelLength` and a custom key on all three passes, and `@Environment(\.isEnabled)` in a struct. | positive | make `LayoutPass.environment` internal → fails |
| G1− | `theThemeIsNotReachableThroughTheEnvironment`. Fixtures: `pass.environment.theme` on `LayoutPass`, and `@Environment(\.theme) var t`. It asserts `!succeeded` and `messages.contains("theme")`. | negative | make `EnvironmentValues.theme` public → `succeeded` |
| G2 | `environmentValuesCannotBeWrittenThroughAPass`. `pass.environment.isEnabled = false` on `PaintPass`. It asserts `!succeeded` and `messages.contains("environment")`. | negative | give the pass accessor a `nonmutating set` that writes the top of the stack → `succeeded` |
| G3 | `pixelLengthIsNotWritableFromOutside`. `X().environment(\.pixelLength, 1.0)` inside a function returning `some ElementGroup`. It asserts `!succeeded` and `messages.contains("WritableKeyPath")`. | negative | make the setter public → `succeeded` |
| G4+ | `aProposalContainerAcceptsAScopeOverProposalContent`. `typecheckFile`, Swift 6 mode: `HStack { Rectangle(width: 1, height: 1).environment(\.probe, 1) }`. | positive | delete the conditional `ProposalElementGroup` conformance → fails |
| G4− | `aProposalContainerRejectsAScopeOverLegacyContent`. `HStack { Box().environment(\.probe, 1) }`. It asserts `!succeeded` and `messages.contains("ProposalElementGroup")`. | negative | make the conformance unconditional → `succeeded` |

Each new guard is **mutated red once** in a worktree built with
`swift build --build-system native`, **to prove it runs**. The count alone
cannot say whether it ran (CLAUDE.md, "When CI lands").

Suite: 1085 → **1085 + 18 + 6 = 1109**. Guards: 46 → **52**.

---

## Lane 3 — the disabled control state (`EV-D`, `EV-E`, `EV-F`, `EV-P` capture)

### Changes

- **`EnvironmentScope.swift`.** Add `.disabled(_:)` as the AND transform.
- **`Frame.registerHandlers`** (shared, about 15 lines, local to that method):
  ```swift
  let enabled = environment.isEnabled
  var keyboard = handlers
  if !enabled { keyboard.isFocusable = false; keyboard.actions = [:] }  // onKey, keyContext kept (EV-F)
  focusRegistry.register(keyboard, id: id)
  // focusedElementProducedThisFrame / $focus write: UNCHANGED, still ungated
  if hitTestingDisabledDepth == 0, handlers.isPointerTarget {
      _ = insertHitbox(bounds, id: id, opaque: true,
                       handlers: enabled ? handlers : Handlers())      // swallow (EV-E)
  }
  if !handlers.axNode.isEmpty {
      var node = handlers.axNode
      if !enabled { node.traits.insert(.disabled) }
      emitAXNode(node, at: bounds, id: id, children: [])
  }
  ```
  **Update the method's doc** to state the gate and cite `EV-E`/`EV-F`, and
  update `Handlers`' doc paragraph on the two gates.
- **No other source edit.**
  - `Box`, `Stack`, `Text`, `FrameModifier`, `OnTapModifier` and `List` are
    **not** touched; the gate reaches them.
  - `Window` is **not** touched: its click dispatch already runs nothing for a
    hitbox with no `onClick`.

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
| D2 | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`. It mirrors `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`) with arms box, column, row, stack, text, list, frame (`.frame(width:height:)`'s `FrameModifier`), proposal `Rectangle(...).onTap`, and a `Component` whose content is an `onClick` box with `.disabled(true)` on the component. Each arm has a **control**, identical minus `.disabled(true)`, that fires once. | every disabled arm fires | delete the `enabled ? handlers : Handlers()` choice (always `handlers`) → every disabled arm fires. **There is no per-site mutation today:** the gate is central, so one edit reddens every arm. The arm list exists for a FUTURE site that registers a click without `registerHandlers`; record that as this test's stated purpose, not as measured per-site coverage |
| D3 | `aDisabledClickTargetSwallowsTheClickRatherThanPassingItThrough`. `ZStack { Rectangle().onTap(under); Rectangle().onTap(over).disabled(true) }` clicked at the centre gives under 0, over 0. The **control** is the same with `.allowsHitTesting(false)` instead of `.disabled(true)`: under 1. Probe P2f and P2c. | over 1 | skip the hitbox when disabled (no blocker) → under 1 |
| D4 | `theGateReadsTheEnvironmentValueNotTheModifier`. Probe P8/P9: `.onClick` box under `.environment(\.isEnabled, true)` inside `.disabled(true)` → fires 1; under `.environment(\.isEnabled, false)` with no `.disabled` → 0. | P9 arm fires | gate on a `Frame.disabledDepth` counter that only `.disabled` increments → P8 reads 0 and P9 reads 1 |
| D5 | `aDisabledElementCannotAcquireFocus`. Probe K1: `window.focus(id)` on a `.focusable().onKey{…}` box inside `.disabled(true)`; draw → `window.focusedElement == nil`; a key event → `onKey` count 0. The **control** without `.disabled` → focused and count 1. | stays focused | keep `isFocusable` in the keyboard copy → focused |
| D6 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`. **A divergence pin** (`EV-F`, probe K2 measured the opposite). Focus an enabled focusable box; draw; flip `model.disabled`; draw → `focusedElement == nil`; flip back; draw → still nil. The doc quotes K2. | stays focused | (a) register `isFocusable` for a disabled element whose id is `focusedElement` → focus retained. This is exactly the SwiftUI-aligned alternative the divergence rejects |
| D7 | `aDisabledElementsActionHandlerDoesNotClaimAKeymapAction`. A keymap `KeyBinding("cmd-i", Increment())`; a parent `Box` with `onAction(Increment.self)`, inside `.disabled(true)`, holding a child focusable box inside `.environment(\.isEnabled, true)`; `window.onAction` records. Focus the child; send cmd-I → the parent handler 0, `window.onAction` 1. The **control** is the parent enabled: parent 1, window 0. | parent 1 | keep `actions` in the keyboard copy → parent 1 |
| D8 | `aDisabledAncestorStillReceivesAKeyItsEnabledFocusedDescendantLeavesUnhandled`. Probe K6 shape: the parent `onKey` returns true and records, inside `.disabled(true)`; the focused child is re-enabled and has `onKey` returning false. A key → parent 1. The control (parent enabled) → parent 1. | — (passes on arrival once `.disabled` exists) | strip `onKey` in the keyboard copy → parent 0 |
| D9 | `aDisabledPaneStillContributesItsKeyContext`. MetalUI's choice, **SwiftUI unprobed** (`EV-S`). `KeyBinding("cmd-k", A(), context: "Pane")`; the pane `.keyContext("Pane")` inside `.disabled(true)` holds a re-enabled focused child with `onAction(A.self)` → the child handler 1. | — (passes on arrival) | strip `keyContext` in the keyboard copy → child 0 |
| D10 | Extends E5: the `.disabled(model.flag)` arm. The counter below `.disabled(model.flag)` keeps `n` across a flip and back, **and** a click while disabled does not increment it. | a click while disabled increments | the E5 `EitherGroup` mutation applied to `.disabled` → `n` resets. The gate-deletion mutation → it increments. Counted in E5, not as a new test |
| D11 | `reEnablingRestoresClicksButNotFocus`. Frame N disabled: click → 0. Frame N+1 enabled: click → 1, and the focus requested while disabled is not restored. | a click in frame N fires | cache the disabled state in a `$enabled` `StateTable` slot read on the next frame → the frame N+1 click reads 0 |
| D12 | `aDisabledElementsAXNodeCarriesTheDisabledTrait`. A `Box` with `handlers.axNode = AXNode(role: .button, label: "b")` set directly, as `AXEmitSiteTests.swift` does (there is no AX modifier), inside `.disabled(true)` → `frame.axNode(for:)` traits contain `.disabled`; the **control** (enabled) lacks it. | trait absent | delete the `traits.insert` → red |

**Divergence and inert rows, as tests.** D6 is the new divergence pin. E8 and
E17 are lane 2's inert and divergence pins.

Suite: 1109 → **1109 + 11 = 1120** (D10 extends E5 and adds no test). Guards:
52 → **52**.

### Human verification: the window capture (`EV-P`)

**No input is sent to the real demo.** Build release at `f64e58a`
(`git worktree add` or `git stash`, in a scratch worktree) and at lane 3's
commit. For each:

1. Run `swift run -c release MetalUIDemo`.
2. Wait 2 s.
3. Find the window id with a CoreGraphics listing script
   (`CGWindowListCopyWindowInfo`, owner `MetalUIDemo`), saved in the scratchpad.
4. Capture with `screencapture -l <id> -o <file>.png`.
5. Quit with `kill` (not Q, which would be input).

Compare the two PNGs byte for byte (`cmp`). If they differ, diff them with a
CoreGraphics pixel script, then locate and explain the region; the demo has time-
and scroll-dependent text. Record the system appearance, both hashes, and the
result in `docs/record/11-environment.md`. **A capture cannot see the Space
swap.** E18 is that evidence, and the record says so.

---

## Verification common to every lane

- **Read the summary line, never the exit status.** The totals must equal the
  table above exactly: 1085 after lane 1, 1109 after lane 2, 1120 after lane 3.
  A shortfall is a truncated run (shape 11). `grep -c "error:"` and
  `grep -c "warning:"` must both read 0. `--build-system native` prints its own
  deprecation line: tell it apart from a compiler warning, and record which it is.
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
    finding. E6(c) is a predicted example of the first kind; confirm it.
- **Timing.**
  - No test sleeps.
  - Animation-adjacent tests drive `simulateTick(timestamp:)`.
  - E15 counts pushes, never time.
- **Exit tests.** No new trap is designed. If a lane adds a precondition (for
  example, "the environment stack is back to one entry after paint"), pin it with
  `#expect(processExitsWith:)`, as `FontResolverTrapTests.swift` does, in the same
  change.
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
| `Sources/MetalUI/EnvironmentValues.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentProperty.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentScope.swift` | 2 (+3 for `.disabled`) | new | |
| `Sources/MetalUI/Frame.swift` | 2, 3 | shared | stack, init param, `theme`; `registerHandlers` gate |
| `Sources/MetalUI/Passes.swift` | 2 | shared | three accessors, one doc |
| `Sources/MetalUI/Window.swift` | 2 | shared | one property, one argument |
| `Sources/MetalUI/ElementGroup.swift` | 2 | shared | three bind calls |
| `Sources/MetalUI/Component.swift` | 2 | shared | one bind call |
| `Sources/MetalUI/StateReflection.swift` | 2 | shared | binder signature, shape cache |
| `Sources/MetalUI/Handlers.swift` | 3 | shared | doc only |
| `Tests/MetalUITests/EnvironmentTests.swift` | 2 | new | |
| `Tests/MetalUITests/EnvironmentCompileGuards.swift` | 1, 2 | new | |
| `Tests/MetalUITests/DisabledTests.swift` | 3 | new | |
| `docs/record/11-environment.md` | all | new (track) | append per lane |
| `docs/superpowers/2026-09-15-environment-decisions.md` | all | new (track) | fill "Mutations" lines |

`Tests/MetalUITests/Fakes.swift` needs no edit. `simulateInput`, `readPixels`,
`makeFakeWindow` and `lastScene` suffice.

## Owed to the integration step (not written by this track)

- **CLAUDE.md.**
  - An Architecture paragraph on the environment: scoping, transparency,
    paint-only theme, the gate, and `@Environment` binding.
  - Divergences: `EV-K` (RTL not mirrored), `EV-F` (focus lost on disable),
    `EV-J` (no `displayScale`).
  - Inert rows: `@Environment` inside `AnyElement`; `layoutDirection`'s writer
    affects no layout.
  - The guard-count file list gains `EnvironmentCompileGuards`.
  - Demo keys: none change.
  - Counts.
- **`docs/record/README.md`.** Index `11-environment.md`.
- **The plan.** Tick task 9, with its carried items (`EV-Q`), and note in task 10
  that the `Binding` alias must be deleted in the change that adds `Binding`.
- **`PhaseSeparationTests.swift`'s theme section comment.** It stays true; add
  one sentence pointing at `G1−` for the environment spelling. This is a test
  file, which lane 2 may edit, but the sentence is listed here in case lane 2
  leaves it.
