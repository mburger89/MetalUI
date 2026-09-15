# Environment and control state design

**Milestone:** plan task 9 of `plans/2026-09-12-swiftui-alignment.md`, "Expand
the environment and control-state model", on `feat/environment`.

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
   - `pixelLength`: read-only, `\.self` included (`EV-J`, `EV-U`);
   - custom keys.
3. **A disabled control state**, all of it through **one** gate in
   `Frame.registerHandlers`:
   - It suppresses clicks and taps on legacy and proposal elements. The
     element's hit region stays and runs nothing, registered under a derived
     id, so it is neither hovered nor pressed (`EV-E`, `EV-T`).
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

Three probes. All were run in this session, and their recorded output is in
their headers. The disabled-interaction probe was **re-run in the second pass**
with arms P2g/P2h, a fixed K5–K8 and a new arm R:

| probe | arms | rulings |
|---|---|---|
| `docs/probes/swiftui-environment-scoping.swift` | A precedence, B `isEnabled`, C defaults, D state retention, E layout transparency, F overlay scope, G dynamic type, H RTL | `EV-A`, `EV-B`, `EV-D`, `EV-G`…`EV-K` |
| `docs/probes/swiftui-disabled-interaction.swift` | P pointer (18 arms, 8 of them controls), K focus/keys (K0–K8), R press/release across a flip | `EV-D`, `EV-E` (analogy only), `EV-F`, `EV-T` |
| `docs/probes/swiftui-environment-api-shape.swift` | compile-only: writable vs get-only members | `EV-C`, `EV-J` |

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
    public var locale: Locale                        // Locale.current, read in init()
    public var dynamicTypeSize: DynamicTypeSize      // .large
    public internal(set) var pixelLength: Double     // 1; Frame stamps 1/scaleFactor (EV-J, EV-U)
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
extension Window { public var environment: EnvironmentValues { get set } }   // didSet → setNeedsRedraw(), even a no-op (EV-H)

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
                                                         // not finite and positive) and resets the top
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
| E5 | `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter`. A real `makeFakeWindow`. A root `Row` holds a `Counter` element with `@State var n`, incremented by `onClick`, wrapped in `.environment(\.probe, model.value)`. Click twice, change `model.value`, draw; `n` reads 2. Probe D1. (Lane 3 adds a `.disabled(model.flag)` arm to this same test; see D10.) | passes on arrival for the environment arm, since there is no mechanism to lose state yet; red only in lane 3's arm, before `.disabled` exists. This is **stated and accepted**: the test exists for the mutation | implement `environment(_:_:)` as a value-keyed `EitherGroup` (`value == default ? .first(self) : .second(scope)`) → `n` resets to 0 when the value moves off the default |
| E6 | `anEnvironmentPropertyIsBoundToTheNearestScopeInEveryPhaseAndRereadEachFrame`. An `Element` with `@Environment(\.probe) var probe` logs `probe` in all three phases, under a scope reading `model.value`. Frame 1 at 3 gives `[3,3,3]`; frame 2 at 4 gives `[4,4,4]`. | `[0,0,0]` | (a) the binder skips binding when the box already holds a snapshot → frame 2 reads `[3,3,3]`; (b) `ElementGroup.prepaintGroup` binds `rootEnvironment` instead of the snapshot → prepaint reads 0; (c) delete the re-bind in `paintGroup` → paint reads the layout snapshot, which cannot differ within a frame, **so (c) is expected to stay green**. Record it as the instrument's limit, not as coverage, and cover (c) through E7 |
| E7 | `oneElementValuePlacedTwiceUnderTwoScopesReadsEachScopeInPaint`. `let r = EnvRecorder(); Row { r.environment(\.probe, 1); r.environment(\.probe, 2) }` reads `[1, 2]` in paint. This is divergence 19's read half. | `[0, 0]` | delete the re-bind in `ElementGroup.paintGroup` → `[2, 2]` |
| E8 | `anEnvironmentPropertyInsideAnyElementIsInertAndReadsTheDefault`. It is pinned **inert on purpose** (`EV-M`). An `AnyElement` wrapping an `@Environment` reader inside `.environment(\.probe, 5)` reads 0. Its doc states the general rule this is one case of: **an `@Environment` that was never bound returns the key's default silently**, with no diagnostic, building a fresh `EnvironmentValues()` (and reading `Locale.current`) on every access. | — (describes a limit) | none. It flips when `AnyElement` binding lands |
| E9 | `aComponentReadsTheNearestEnvironmentInItsContent`. A `Component` with `@Environment(\.probe)` whose `content` is `Box().background(probe == 1 ? .accent : .surface)` of fixed size. Inside `.environment(\.probe, 1)`, the scene's rect is `.accent` resolved; bare, it is `.surface`. | both `.surface` | `Component.requestGroupLayout`'s bind snapshots `rootEnvironment` → the scoped arm reads `.surface` |
| E10 | `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState`. `Counter`-style component state survives `MyComponent()` → `MyComponent().environment(\.probe, 1)` across two frames in one `StateTable`, compared by id as in `addingAModifierDoesNotResetAComponentsState`. | — | mutation E4(b) reddens this too. Record both names |
| E11 | `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase`. `HStack { Rectangle(...).environment(\.probe, 7) }` with a native recorder leaf that logs `pass.environment.probe` in **layout, prepaint and paint** → `[7,7,7]`. The same scope over `ProposalScrollView` content → `[7,7,7]`. | `[0,0,0]` | (a) E3's `paintGroup` mutation → the paint slot reads 0; (b) `EnvironmentScope.requestGroupLayout` forwards without `withEnvironment` → the layout slot reads 0. **(b) is the one the modifier-composition merge could reintroduce** (`EV-W`): a forwarding `requestProposalGroupLayout` skips the push in layout only |
| E12 | `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope`. In a `Row`: a `.surface` box inside `.theme(.dark)`, a `.surface` sibling outside it, and a `Deferred { .surface box }` inside `.theme(.dark)`. The scene colours are dark, light, dark. | light, light, light | (a) `Frame.theme` returns `rootTheme` → the first arm reads light; (b) `PaintPass.deferred` sets the top to `rootEnvironment` around its body → the third arm reads light |
| E13 | `theFramesRootEnvironmentCarriesItsThemeAndScale`. A `Frame(theme: .dark, scaleFactor: 2)` renders a `.surface` box dark, and `pixelLength` reads 0.5; at `scaleFactor: 1` it reads 1. Then `frame.rootEnvironment = x` where `x` is a snapshot from a light, scale-1 frame: theme still dark, `pixelLength` still 0.5 (the in-module overwrite is re-stamped; `EV-H`). | light; 1 at scale 2 | (a) the root ignores `theme:` → light; (b) `pixelLength = Double(scaleFactor)` → 2 at scale 2; (c) the `rootEnvironment` setter does not re-stamp → light and 1. The scale-2 arm is what discriminates, because the fake surface is scale 1 |
| E14 | `theWindowsEnvironmentReachesTheFrameAndASetRepaints`. A fake window: after one frame, `needsRedraw` is false; set `window.environment.locale` to a locale whose identifier differs from `Locale.current.identifier` (`de_DE`, or `fr_FR` if the machine is `de_DE`; `try #require` that they differ) → `needsRedraw` true; the next frame's recorder reads it. Draw again; `window.environment = window.environment` → `needsRedraw` **true**: a no-op write still dirties, **pinned as a stated cost** (`EV-H`). Defaults on a fresh window: `isEnabled`, `.leftToRight`, `Locale.current.identifier` and `.large`, matching probe C. | the recorder reads the default locale | (a) drop the `didSet` → `needsRedraw` false; (b) `drawFrameIfNeeded` omits the `rootEnvironment` statement → the recorder reads `Locale.current`; (c) skip dirtying when the built-in fields compare equal → the no-op arm reads false. (c) is not a defect to prevent; it is the change that must face this pin and say how it compares custom keys |
| E15 | `environmentWorkScalesWithWritersAndReadersNotWithTheirDescendants`. **Performance, counts work**, on a branching 4×5×3 tree of fixed-size `Box`es (the shape CLAUDE.md's Performance section counts cache misses on) and the same writers over a 1×1×1 tree. Counts are `try #require`d before comparison. **Pushes:** no writer → 0; one writer at the root child → 3; two nested writers → 6; the same on both trees. **Snapshots:** with no `@Environment` reader and no `pass.environment` read anywhere, **0** on both trees, writers or not. **Positive control:** add one `@Environment` reader leaf → snapshots 3 (one bind per phase) on both trees. **Transforms:** one per writer per frame. | the counters do not exist (compile) | (a) `Element.requestGroupLayout` (default) wraps `requestLayout` in `frame.withEnvironment(frame.environmentTop)` → the big tree's pushes exceed the small tree's; (b) **eager evaluation**: `bind` calls `frame.environmentSnapshot()` before consulting the shape → snapshots equal 3 × elements, so 0 fails and the trees disagree. `Frame.theme`'s and the gate's in-place reads are not counted, and the ruling claims nothing the counters cannot see (`EV-O`) |
| E16 | `dynamicTypeSizeChangesNoTextMeasurement`. A fixed-string `Text` measures the same width and height bare and under `.dynamicTypeSize(.accessibility5)`, with a positive control: `.font(size: 26)` differs. Probe G. | — (passes on arrival once it compiles: aligned behaviour) | multiply `Text`'s `fontSize` by 1.5 when `pass.environment.dynamicTypeSize.isAccessibilitySize` → red. **Revert.** The test exists so a later "fix" must face probe G |
| E17 | `aRightToLeftLayoutDirectionDoesNotYetMirrorAnHStack`. **Pinned wrong on purpose** (`EV-K`). `HStack(spacing: 0) { Rectangle(width: 10, height: 10); Rectangle(width: 20, height: 10) }` with `.frame(width: 100, alignment: .leading)`, inside `.environment(\.layoutDirection, .rightToLeft)`, places at x 0 and 10. The doc quotes probe H's 90 and 70. | — | none owed. It flips with task 6 |
| E18 | `theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform` (`EV-P`). `let device = try #require(MTLCreateSystemDefaultDevice())`, then a fake window with `keymap = Keymap { KeyBinding("space", ToggleThemeFixture()) }` and `onAction` flipping `window.theme` for that action type and returning true, over a full-size `.background` box. Draw and `readPixels()`: the centre pixel is `before`. `simulateInput(.keyDown(KeyEvent(charactersIgnoringModifiers: " ", characters: " ", timestamp: 0)))` returns true; draw; the centre pixel is `after`. **Oracle arms that must disagree first:** two more fake windows with `theme` set light and dark render the same tree; `try #require(lightRef != darkRef)`. Then `before == lightRef` and `after == darkRef`. | — (passes on arrival once lane 1 exists: a regression pin) | E13(a) → `after == lightRef`. Also: `Frame.theme` computed from `EnvironmentValues().theme` → `after == lightRef` |
| E19 | `aWholeValueWriteCannotResetTheThemeOrThePixelLength` (`EV-U`). A `Frame(scaleFactor: 2)` renders, inside `.theme(.dark)`: (i) `.environment(\.self, EnvironmentValues())` over a `.surface` box and a `pixelLength` recorder; (ii) `.transformEnvironment(\.self) { $0 = captured }` where `captured` is a snapshot taken from a light, scale-1 frame. Both arms: the box is dark, `pixelLength` 0.5. **Control:** the same `\.self` write resets `probe` from 3 to 0, so the write did land | the box is light and `pixelLength` is 1 | drop the two re-stamping assignments in `scopedValues` → light and 1 |
| E20 | `eachScopesTransformRunsOncePerFrame` (`EV-V`). A reference counter `c`; `.transformEnvironment(\.probe) { c.n += 1; $0 = c.n }` over a three-phase recorder. After frame 1: `c.n == 1`, recorder `[1,1,1]`; after frame 2: `c.n == 2`, recorder `[2,2,2]`; `environmentTransformCount` 1 per frame | the counter is 3 per frame and the recorder reads `[1,2,3]` if the shell re-runs the transform per phase | `prepaintGroup` calls `scopedValues(applying: write)` instead of pushing `layout.values` → `c.n == 2` after frame 1 and the prepaint slot differs |
| E21 | `aLocaleChangesNoTextMeasurement` (`EV-H`, inert, **pinned as inert**). `Text("กรุงเทพมหานคร อมรรัตนโกสินทร์")` measures the same min-content width, max-content width and height bare and under `.environment(\.locale, Locale(identifier: "th_TH"))`, and under `en_US`. Positive control: `.font(size: 26)` differs. | — (passes on arrival) | pass `pass.environment.locale` into `Shaper`'s tokenizer → the min-content width may move. **If it does not move, the mutation is void and that is recorded, not banked as coverage.** Revert either way |

**Typecheck guards**, in `Tests/MetalUITests/EnvironmentCompileGuards.swift`
(plain import, `canTypecheck`-gated, per the file header convention of
`PhaseSeparationTests`):

| # | guard | kind | mutation that must redden it |
|---|---|---|---|
| G1+ | `environmentValuesAreReadableInEveryPhase`. One fixture reads `pass.environment.isEnabled`, `.layoutDirection`, `.locale`, `.dynamicTypeSize`, `.pixelLength` and a custom key on all three passes, and `@Environment(\.isEnabled)` in a struct. | positive | make `LayoutPass.environment` internal → fails |
| G1− | `theThemeIsNotReachableThroughTheEnvironment`. Fixtures: `pass.environment.theme` on `LayoutPass`, and `@Environment(\.theme) var t`. It asserts `!succeeded` and `messages.contains("theme")`. | negative | make `EnvironmentValues.theme` public → `succeeded` |
| G2 | `environmentValuesCannotBeWrittenThroughAPass`. `pass.environment.isEnabled = false` on `PaintPass`. It asserts `!succeeded` and `messages.contains("environment")`. | negative | give the pass accessor a `nonmutating set` that writes the top of the stack → `succeeded` |
| G3 | `pixelLengthIsNotWritableFromOutsideButAWholeValueWriteCompiles`. Two fixtures inside a function returning `some ElementGroup`. **Negative:** `X().environment(\.pixelLength, 1.0)` → `!succeeded`, `messages.contains("WritableKeyPath")`. **Positive premise:** `X().environment(\.self, EnvironmentValues())` → `succeeded`. The positive half records that the compiler cannot close the `\.self` route, which is why E19 exists | negative + premise | (a) make the setter public → the negative half succeeds; (b) make `EnvironmentValues.init` internal → the positive half fails |
| G4+ | `aProposalContainerAcceptsAScopeOverProposalContent`. `typecheckFile`, Swift 6 mode: `HStack { Rectangle(width: 1, height: 1).environment(\.probe, 1) }`. | positive | delete the conditional `ProposalElementGroup` conformance → fails |
| G4− | `aProposalContainerRejectsAScopeOverLegacyContent`. `HStack { Box().environment(\.probe, 1) }`. It asserts `!succeeded` and `messages.contains("ProposalElementGroup")`. | negative | make the conformance unconditional → `succeeded` |

Each new guard is **mutated red once** in a worktree built with
`swift build --build-system native`, **to prove it runs**. The count alone
cannot say whether it ran (CLAUDE.md, "When CI lands").

Suite: 1085 → **1085 + 21 + 6 = 1112**. Guards: 46 → **52**.

---

## Lane 3 — the disabled control state (`EV-D`, `EV-E`, `EV-F`, `EV-T`, `EV-P` capture)

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
  if hitTestingDisabledDepth == 0, handlers.isPointerTarget {
      if enabled {
          _ = insertHitbox(bounds, id: id, opaque: true, handlers: handlers)
      } else {                                                  // keep the region, run nothing, under a
          _ = insertHitbox(bounds, id: .child(of: id, at: 0, name: ElementID("$disabled")),  // DERIVED (EV-T)
                           opaque: true, handlers: Handlers())
      }
  }
  if !handlers.axNode.isEmpty {
      var node = handlers.axNode                                // after the AX-bridge merge: the SYNTHESIZED
      if !enabled { node.traits.insert(.disabled) }             // node, from the UNGATED handlers; the trait
      emitAXNode(node, at: bounds, id: id, children: [])        // is inserted after synthesis (EV-W)
  }
  ```
  The derived id copies the `$anim-content` precedent's spelling exactly
  (`AnimatedStyle.swift:185`: `.child(of: id, at: 0, name: ElementID("$anim-content"))`).
  **Update the method's doc** to state the gate and cite `EV-E`/`EV-F`/`EV-T`.
  **Update the `$focus` paragraph** (`Frame.swift:621-651`): the ungated-write
  hazard stays reachable through `Window.focus` on an enabled non-focusable
  element, and is **not** reachable through `.disabled`, because the slot write
  is gated on `isEnabled`. **Update `Handlers`' doc** paragraph on the two gates.
- **No other source edit.**
  - `Box`, `Stack`, `Text`, `FrameModifier` and `NativeTappable`
    (`OnTapModifier`) are **not** touched; the gate reaches them. Those are the
    **five** `registerHandlers` callers today (`grep -rn "registerHandlers(" Sources`);
    `Column`/`Row` reach it through `Box`, `List` rows through their elements,
    and `Component` through its members.
  - `Window` is **not** touched: its click dispatch already runs nothing for a
    hitbox with no `onClick`, and the derived id makes a press on a disabled
    target never match a later release on the re-enabled element.

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
| D2 | `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`. It mirrors `onClickIsLiveOnEveryConformerThatCanRegisterOne` (`InputDispatchTests.swift`). **Arms are defined by their spelling, not by the type they produce**: `Box().onClick`, `Column { … }.onClick`, `Row { … }.onClick`, `Stack { … }.onClick`, `Text("x").onClick`, a `List` row's `onClick` box, **a `.padding(4).frame(width: 20, height: 20)` chain with the `onClick` on the inner layer**, proposal `Rectangle(...).onTap`, and a `Component` whose content is an `onClick` box with `.disabled(true)` on the component. Each arm has a **control**, identical minus `.disabled(true)`, that fires once. | every disabled arm fires | always pass `handlers` (delete the `enabled` branch) → every disabled arm fires. **There is no per-site mutation today:** the gate is central, so one edit reddens every arm. The arm list exists for a FUTURE site that registers a click without `registerHandlers` — including the modifier-composition track's `ModifiedElement`, which replaces `FrameModifier` (`EV-W`); record that as this test's stated purpose, not as measured per-site coverage |
| D3 | `aDisabledClickTargetKeepsItsRegionAndRunsNothing`. `ZStack { Rectangle().onTap(under); Rectangle().onTap(over).disabled(true) }` clicked at the centre gives under 0, over 0. The **control** is the same with `.allowsHitTesting(false)` instead of `.disabled(true)`: under 1. The doc states this is **MetalUI's choice by analogy** (`EV-E`): probe P2e–P2h shows SwiftUI's `.disabled` leaves hit-testability alone, and a MetalUI region comes from its `onClick`. It does **not** cite P2f as alignment | over 1 | skip the hitbox when disabled → under 1 |
| D4 | `theGateReadsTheEnvironmentValueNotTheModifier`. Probe P8/P9: `.onClick` box under `.environment(\.isEnabled, true)` inside `.disabled(true)` → fires 1; under `.environment(\.isEnabled, false)` with no `.disabled` → 0. | P9 arm fires | gate on a `Frame.disabledDepth` counter that only `.disabled` increments → P8 reads 0 and P9 reads 1 |
| D5 | `aDisabledElementCannotAcquireFocus`. Probe K1: `window.focus(id)` on a `.focusable().onKey{…}` box inside `.disabled(true)`; draw → `window.focusedElement == nil`; a key event → `onKey` count 0. The **control** without `.disabled` → focused and count 1. | stays focused | register the ungated `handlers` → focused |
| D6 | `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`. **A divergence pin** (`EV-F`, probe K2 measured the opposite). Focus an enabled focusable box; draw; flip `model.disabled`; draw → `focusedElement == nil`; flip back; draw → still nil. The doc quotes K2. | stays focused | register `handlers` for a disabled element whose id is `focusedElement` → focus retained. This is exactly the SwiftUI-aligned alternative the divergence rejects |
| D7 | `aDisabledElementsActionHandlerDoesNotClaimAKeymapAction`. A **context-free** `KeyBinding("cmd-i", Increment())`; a parent `Box` with `onAction(Increment.self)`, inside `.disabled(true)`, holding a child focusable box inside `.environment(\.isEnabled, true)`; `window.onAction` records. Focus the child; send cmd-I → the parent handler 0, `window.onAction` 1. The **control** is the parent enabled: parent 1, window 0. The doc pins the routing as MetalUI's (unprobed): an action nobody enabled claims reaches `Window.onAction`, like any unclaimed action; a **context-scoped** binding under a disabled pane does not match at all (D9) | parent 1 | register `handlers` → parent 1 |
| D8 | `aDisabledAncestorsRawKeyHandlerDoesNotSeeAKey`. **A divergence pin** (`EV-F`; probe K6 shows SwiftUI's disabled parent's `.onKeyPress` runs). The parent `onKey` returns true and records, inside `.disabled(true)`; the focused child is re-enabled and its `onKey` returns false. A key → parent 0, and the event reaches `window.onInput`. The control (parent enabled) → parent 1. | parent 1 | keep `onKey` for a disabled element → parent 1 |
| D9 | `aDisabledPaneContributesNoKeyContext`. MetalUI's choice, **SwiftUI has no comparable concept** (`EV-S`). `KeyBinding("cmd-k", A(), context: "Pane")`; the pane `.keyContext("Pane")` inside `.disabled(true)` holds a re-enabled focused child with `onAction(A.self)` → the child handler 0 **and** `window.onAction` 0 (the binding does not match). The control (pane enabled) → child 1 | child 1 | keep `keyContext` for a disabled element → child 1 |
| D10 | Extends E5: the `.disabled(model.flag)` arm. The counter below `.disabled(model.flag)` keeps `n` across a flip and back, **and** a click while disabled does not increment it. | a click while disabled increments | the E5 `EitherGroup` mutation applied to `.disabled` → `n` resets. The gate-deletion mutation → it increments. Counted in E5, not as a new test |
| D11 | `reEnablingRestoresClicksButNotFocus`. Frame N disabled: click → 0. Frame N+1 enabled: click → 1, and the focus requested while disabled is not restored. | a click in frame N fires | cache the disabled state in a `$enabled` `StateTable` slot read on the next frame → the frame N+1 click reads 0 |
| D12 | `aDisabledElementsAXNodeCarriesTheDisabledTrait`. A `Box` with `handlers.axNode = AXNode(role: .button, label: "b")` set directly, as `AXEmitSiteTests.swift` does (there is no AX modifier), inside `.disabled(true)` → `frame.axNode(for:)` traits contain `.disabled`; the **control** (enabled) lacks it. **An arm is owed to the integration step** (`EV-W`): an undeclared, disabled `Box().onClick {}` in a *collecting* frame publishes a synthesized `.button` with `isEnabled == false`, and has no `.press` action | trait absent | delete the `traits.insert` → red |
| D13 | `aFocusRequestWhileDisabledLeavesNoRetentionSlot` (`EV-F`). Frame 1: `x` = `.focusable()` box inside `.disabled(true)`; `window.focus(x)`; draw → nil. Frame 2: `x` removed by an `if`; draw. `window.focus(x)`; draw → `focusedElement == nil`. **Instrument arm, pinned wrong on purpose:** the same sequence with `x` enabled but **not** `.focusable()` reads `x` — the known hazard in `Frame.swift`'s `$focus` paragraph, which proves the instrument can see a sticky focus. Below `StateTable.sweepThreshold` in both arms (`try #require`) | disabled arm reads `x` | write the `$focus` slot regardless of `enabled` → the disabled arm reads `x` |
| D14 | `aDisabledScopeReachesIntoDeferredContent`. `Row { Row { Deferred { fixed-size Box().onClick(rec) } }.disabled(true) }` (the scope sits outside the `Deferred`, whose content must be an `Element`, and inside a root `Row`, since a scope cannot be a root): a click at the portal's rect → 0, and a focus request on a focusable box inside the portal → nil. **Control** without `.disabled` → 1 and focused. | 1 and focused | `PrepaintPass.deferred` sets the top to `rootEnvironment` around its body → 1 and focused |
| D15 | `aClickNeedsTheTargetEnabledAtPressAndAtRelease` (`EV-T`, probe R). A model-driven `.disabled(model.flag)` over an `onClick` box in a fake window; `mouseDown`, flip, draw, `mouseUp`. **R0 control** (no flip, enabled) → 1; **R1** pressed disabled, released enabled → 0; **R2** pressed enabled, released disabled → 0; **R3** disabled throughout → 0 | R1 reads 1 | register the blocker under the element's own `id` → R1 reads 1 |
| D16 | `aDisabledTargetIsNeitherHoveredNorPressed` (`EV-T`). A fixed-size `Box().onClick {}.hoverBackground(.accent).background(.surface)` inside `.disabled(model.flag)`; `mouseMoved` to its centre, draw → the rect is `.surface`, and a paint-phase recorder reads `isActive` false during a held press. **Control** (enabled) → `.accent` and `isActive` true | `.accent` and true | register the blocker under the element's own `id` → `.accent` and true |

**Divergence and inert rows, as tests.** D6 and D8 are the new divergence pins.
E8, E17 and E21 are lane 2's inert and divergence pins.

Suite: 1112 → **1112 + 15 = 1127** (D10 extends E5 and adds no test). Guards:
52 → **52**.

### Human verification: the window capture (`EV-P`)

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

---

## Verification common to every lane

- **Read the summary line, never the exit status.** The totals must equal the
  table above exactly: 1085 after lane 1, 1112 after lane 2, 1127 after lane 3.
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
- **Exit tests.** No new trap is designed. If a lane adds a precondition (for
  example, "the environment top is the root again after paint"), pin it with
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
| `Sources/MetalUICore/LayoutDirection.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentValues.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentProperty.swift` | 2 | new | |
| `Sources/MetalUI/EnvironmentScope.swift` | 2 (+3 for `.disabled`) | new | |
| `Sources/MetalUI/Frame.swift` | 2, 3 | shared | top, root, counters, `theme`; `registerHandlers` gate, `$focus` doc |
| `Sources/MetalUI/Passes.swift` | 2 | shared | three accessors, one doc |
| `Sources/MetalUI/Window.swift` | 2 | shared | one property, one statement after `Frame(...)` |
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

**Merge obligations** (`EV-W`; each is loud by construction, and this list says
where):

- **Modifier composition, lane 3 (`feat/modifier-composition`, `1c6f686`).**
  - `ProposalElementGroup` gains `requestProposalGroupLayout`. The empty
    conditional conformance of `EnvironmentScope` then fails to compile (loud).
    The fix must go **through the same private helper** as
    `requestGroupLayout` — resolve the write once, push, forward — not a bare
    forward, which would skip the push in layout. E11's layout slot is the test
    that sees a bare forward.
  - `MC-H` adds two `StateBinder.bind` call sites (the `ProposalElement` typed
    default and `Component where Content: ProposalElementGroup`). They are
    written against `bind(_:table:id:)`, which this design removes, so they fail
    to compile (loud). They move to `bind(_:in:id:)`. **No default and no
    compatibility overload may be added** to make them compile.
- **Modifier composition, lane 2.** `FrameModifier.swift` is deleted and
  `ModifiedElement` registers one layer per id. D2's `.padding(4).frame(…)` arm
  is defined by spelling, so it keeps running and must stay green; `EV-E`'s site
  list and the "five callers" count are re-taken with the grep above.
- **Accessibility bridge (`feat/ax-bridge`, `2042a54`).**
  - **Textual conflict in `Frame.registerHandlers`**: both tracks edit its body.
    Resolution: synthesis (`AXNode.synthesized(declared:handlers:text:)`) reads
    the **ungated** `handlers`, so a disabled clickable still synthesizes a
    `.button`; the `.disabled` trait is inserted into the node synthesis
    returned, **after** synthesis, before `emitAXNode`. Resolving it the other
    way (trait on `handlers.axNode` before synthesis) publishes a disabled
    clickable as `isEnabled = true`.
  - D12 gains its collecting-frame arm (above).
  - **No conflict in `Frame.init` or in `Window`'s `Frame(...)` expression**:
    this design adds neither an init parameter nor an argument (`EV-H`); the
    bridge's `collectsAccessibility:` lands alone. `Window` gains one statement
    after that expression, which may conflict as adjacent lines only.
  - The bridge's `.press` derivation ("`lastHitboxes` holds an entry for the id
    with `onClick`") refuses a disabled element for free, because the blocker
    sits under the derived id with empty handlers; its `.focus` request refuses
    because a disabled element is not in the focus registry. Neither needs an
    edit; both deserve an arm in the bridge's own tests.
- **Unowned deferrals — flag, do not assume.**
  - "Scopes after `StyledElement` modifiers" was handed to task 3, but the
    modifier-composition spec never mentions `EnvironmentScope`.
  - "Hover and pressed on a disabled element; focus retention on disable" was
    handed to task 12, but the AX-bridge spec says "disabled behaviour … wait[s]
    for task 9". Hover and pressed are now decided here (`EV-T`); focus
    retention and a disabled look remain **unowned**.

**Documents:**

- **CLAUDE.md.**
  - An Architecture paragraph on the environment: scoping, transparency,
    once-per-frame transforms, paint-only theme, the gate, and `@Environment`
    binding.
  - Divergences: `EV-K` (RTL not mirrored), `EV-F` (focus lost on disable;
    raw `onKey` and `keyContext` removed while SwiftUI keeps `.onKeyPress`),
    `EV-J` (no `displayScale`), and the key handler order (SwiftUI runs an
    ancestor's `.onKeyPress` before the focused view's; MetalUI bubbles
    outward from the focused element; probe K5).
  - Inert rows: `@Environment` inside `AnyElement`; `@Environment` never bound
    returns the default silently; `layoutDirection`'s writer affects no layout;
    `locale` has no consumer (`Text`'s tokenizer and typesetter never receive
    it); `pixelLength` has no internal reader; an in-module write to
    `Frame.rootEnvironment.theme` or `.pixelLength` (or to
    `window.environment.theme`) is silently re-stamped.
  - Reserved names: `$disabled` is an **id suffix** (the blocker hitbox's
    derived id), not a slot, beside `$anim-content`/`$anim-viewport`. A `List`
    datum whose id describes to it collides with a disabled row's blocker.
  - `Window.environment`: every write dirties, a no-op included; write from
    input, never from a phase (a phase-time write keeps the link awake).
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
