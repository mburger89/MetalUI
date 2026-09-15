## Environment and control state (plan task 9) — `feat/environment`

The record for plan task 9. Rulings: `docs/superpowers/2026-09-15-environment-decisions.md`
(`EV-`). Spec: `docs/superpowers/specs/2026-09-15-environment-design.md`.
Lanes append their own sections below this one. This file is not yet indexed by
`docs/record/README.md`; the integration step owns that index.

### Design session (2026-09-14), at `f64e58a`

**Where.** Everything here was measured in the worktree
`/Users/maxburger/Developer/MetalUI-environment` on branch `feat/environment`.
**No other agent was live in the worktree.** No source file was edited; the only
new files are docs and probes.

#### Baseline counts

The suite was run once, after `swift build --build-system native`, with
`swift test --no-parallel --build-system native`.

- **1084 tests** passed, on **one summary line**.
- **0 `error:`** lines.
- **97 goldens**.
- **45 typecheck guards**, counted per file with `grep -c canTypecheck`:

  | file | hits | guards |
  |---|---|---|
  | `PhaseSeparationTests` | 19 | 19 |
  | `ErasureCompileGuards` | 10 | 10 |
  | `ProposalLayoutCompileGuards` | 6 | 6 |
  | `ElementGroupTrapTests` | 5 | 5 |
  | `UnitSafetyTests` | 3 | 2 (one hit is a comment) |
  | `AXNodeTests` | 3 | 3 |

- **Warnings: not established.** The command redirected stderr to the
  background task's output rather than to the log file. That output held only
  build progress and no `warning:` line, but a warning printed during the test
  run could have gone either way. The implementer re-takes this with both
  streams sent to one file.

These counts agree with the plan's task 2 entry: 1084 tests, 97 goldens and 45
guards at `553b980`.

#### Probes run, and what each showed

The full recorded output is in each probe's header. Every figure below is copied
from those headers.

**`docs/probes/swiftui-environment-scoping.swift`** was run in both forms. The
filtered output of the two forms is byte-identical (`diff` empty), and both
exited 0.

- **A: precedence.** Arms A0–A6 read `[0, 1, 2, 1, 2, 1, 0]`.
  - A7, a transform of +10 inside one of +100, reads 110.
  - A8, a plain write of 5 inside a transform of +100, reads 5.
- **B: isEnabled.** Arms B0–B8 read
  `[true, false, true, false, false, true, false, false, false]`.
- **C: defaults**, read in an `NSWindow`.
  - `leftToRight`.
  - `en_US`, which equals `Locale.current`.
  - `dynamicTypeSize` `large`.
  - `displayScale` 2.0, which equals the window's `backingScaleFactor`.
  - `pixelLength` 0.5.
  - `colorScheme` dark, `controlActiveState` inactive, `controlSize` regular.
  - C2 is the control: every reader moves when written.
- **D: state across a value change.**
  - D1, where only the value changes, reads n = 5 → 6 → 7, and `onAppear` runs
    once.
  - D2 is the control, where `.id` changes: n reads 5 → 6 → 5, and `onAppear`
    runs twice.
- **E: subview counts** read 2, 2, 2 and 1. The 1 is the control, a writer on a
  `VStack`.
- **F: overlays.** F1, the overlay inside the writer, reads 3. F2, a writer on
  the base before the overlay, reads 0.
- **G: dynamic type.** A `.body` text measures 120×16 at the default, at
  `xSmall` and at `accessibility5`. The control, a 26pt font, measures 219×30.
- **H: layout direction.** In a 100pt frame:
  - LTR (the control) places the children at x 0 and 10.
  - RTL places them at x 90 and 70.

**`docs/probes/swiftui-disabled-interaction.swift`** was run compiled twice and
as a script once. All three filtered outputs are identical, and each exited 0.
Arm results:

- **Enabled controls fire:**
  - P0, `.onTapGesture`: 1.
  - P2c, a tap under an `.allowsHitTesting(false)` view: under = 1.
  - P2d, a tap under a clear view with no shape: under = 1.
  - P2e, an enabled overlay: over = 1, under = 0.
  - P3, a plain `Button`: 1.
  - P5, a default-style `Button`: 1.
- **Disabled arms:**
  - These fire nothing (0): P1, P4, P6 and P7.
  - P2f, the disabled overlay: over = 0, under = 0.
  - P9, a raw `isEnabled = false`: 0.
  - P8, a raw `isEnabled = true` inside `.disabled(true)`: 1.
- **P2m/P2n.** A `Color` over a tappable blocks the tap whether enabled or
  disabled. That is why P2 alone could not be read.
- **Focus and keys (arm K):**
  - K0 is the control: the view takes focus and its key handler fires.
  - K1, disabled from the start: focus is never acquired and no key arrives.
  - K2, disabled after focusing: focus stays, the key handler still fires, and
    the view reads `isEnabled` 0. Focus is still held after re-enabling.
  - K5/K6: the parent's key handler fires (1) whether or not the parent is
    disabled. The child's handler reads 0 in both arms, including the control;
    **this is unexplained**. _(Superseded in the second pass, below: the parent
    runs first and a `.handled` parent pre-empts the child.)_
  - K3, an enabled keyboard shortcut: 1. K4, the same shortcut disabled: 0.
  - _(Second pass: P2f's reading below is superseded too; P2g shows an enabled
    gesture-less shape blocks, so P2f measured the shape, not `.disabled`.)_

**`docs/probes/swiftui-environment-api-shape.swift`** was typechecked with
`swiftc -typecheck`, which exited 1. That is expected: the file must fail.

- There are two `error:` lines, both on NEGATIVE lines: assigning
  `pixelLength`, and `.environment(\.pixelLength, 1)`.
- No CONTROL line errored. So `displayScale`, `isEnabled`, `layoutDirection`,
  `locale` and `dynamicTypeSize` are all writable.

#### Harness failures, recorded because each would have produced a plausible reading

1. **Mouse-up queued before mouse-down.** Every `.onTapGesture` arm read 0,
   **including the enabled control P0**, and so did the default-style Button
   control. Sending down, waiting 50 ms, then sending up, both through
   `sendEvent`, fixed the gesture arms.
2. **Taps still read 0** until the hosting view overrode
   `acceptsFirstMouse(for:)` to return true. The script is unbundled, so
   `NSApp.isActive` reads false even after
   `setActivationPolicy(.regular)`, `finishLaunching()` and
   `activate(ignoringOtherApps:)`.
3. **P2 read 0/0 ambiguously**, because control P2m showed an enabled `Color`
   also blocks the tap. Arms P2d–P2f were added to separate the two.
4. **Scroll: not measured.** One pixel-unit wheel event through `sendEvent`,
   plus four strategies in a scratch file, all left an **enabled**
   `ScrollView` at minY 0:
   - `NSWindow.sendEvent`;
   - a direct `scrollWheel(with:)` on the hit view;
   - each of those with continuous began/changed/ended phases.

   The arm was removed. Whether `.disabled` stops scrolling is unknown.

#### One compiler measurement behind a spec comment

The spec's `EnvironmentValues` declaration has a comment on its isolation. A
first draft said the struct must not be `@MainActor` "so key paths to its
members form in Swift 6 mode". **That claim was checked and refuted.**

- **The check.** A scratch file declared a `@MainActor` struct and a plain
  struct, a `@MainActor` property wrapper over a `KeyPath` to each, and a
  `@MainActor` function taking a `WritableKeyPath`. It typechecked under
  `swiftc -swift-version 6 -typecheck` with no error and no warning (exit 0).
- **What changed.** The spec comment now says the choice is about not isolating
  a plain value type, not about key paths.

#### What this session did NOT establish

- **Hover and pressed appearance on a disabled view in SwiftUI.** No arm
  measured either.
- **Scrolling under `.disabled`.** See harness failure 4.
- **Whether SwiftUI's default `layoutDirection` follows the system.** The
  machine is LTR (`NSApp.userInterfaceLayoutDirection` = 0), so a constant
  default and a derived one read the same.
- **`keyContext`, the AX `disabled` trait, and `@Environment` inside
  `AnyElement`.** These are MetalUI design choices, not SwiftUI observations.
- **Any MetalUI behaviour.** Nothing was implemented, so every EV ruling's
  "Mutations" line is still owed.

### Design session, second pass (2026-09-14 into 2026-09-15), at `bbd4d66`

**Why.** A critic review of the first design commit (`bbd4d66`) reported 18
defects. This pass applied all 18; the dispositions are in the decisions doc's
"Second pass" table. **No source file was edited.** The changed files are the
spec, the decisions doc, this record and one probe. **No other agent was live
in this worktree.** The two other tracks' design commits were read with
`git show` from the shared object store (`1c6f686` modifier composition,
`2042a54` accessibility bridge); their worktrees were not touched.

#### Probe re-run: `docs/probes/swiftui-disabled-interaction.swift`

Three arms were changed or added, and the whole file was re-run.

- **P2g/P2h** (the critic's arm, now committed): a clear overlay with a
  `contentShape` and **no gesture** over a tappable, enabled (P2g) and
  `.disabled(true)` (P2h). Both read **under 0**. P2d (no shape) still reads
  under 1, so the instrument can pass a click through.
- **K5–K8** replace the old K5/K6. Each handler appends its name to an ordered
  log. K5 (parent enabled, parent returns `.ignored`, control) reads
  `["parent", "child"]`; K6 (parent disabled, child re-enabled) reads the same;
  K7/K8 (parent returns `.handled`) read `["parent"]`.
- **R0–R3** (new): press, flip `.disabled` through an `@ObservedObject`, 0.2 s,
  release, for a plain `Button` and for `.onTapGesture`. R0 (enabled
  throughout, same timing) reads 1; R1 (pressed disabled, released enabled),
  R2 (the reverse) and R3 (disabled throughout) read 0. Identical for both
  controls.

**How it ran.** Compiled with `swiftc` and run with `OS_ACTIVITY_DT_MODE=1`
twice, and as `/usr/bin/swift <file>` once, on the final file (the header was
rewritten after the first compiled run and the file re-compiled and re-run).
All filtered outputs were `diff`-identical to the recorded block now in the
header, every run exited 0, and the script run printed 0 `warning:` lines.
Every arm the first pass recorded reads the same as before.

#### Scratch exploration behind K5–K8 (not committed; files in the session scratchpad `ev2/`)

The committed arms were designed from three scratch runs, recorded here so the
path is checkable:

- **Six child variants under a `.handled` parent** (`kbprobe.swift`): the
  original shape, no `.environment` write, a child returning `.handled`,
  `.onKeyPress` before `.focusable()`, `onKeyPress(phases: .down)` and
  `onKeyPress(characters:)`. **All six read child 0, parent 1**, with the child
  focused. So the child's zero was not about the modifier order or the overload.
- **Parent presence** (`kbprobe2.swift`): no parent handler → child 1; a parent
  returning `.ignored` → child 1, parent 1; a parent returning `.handled` →
  child 0, parent 1 (twice, once with the child returning `.handled`).
- **Order** (`kbprobe3.swift`): an ordered log read `["parent", "child"]` with the
  parent enabled or disabled and returning `.ignored`, and `["parent"]` when it
  returned `.handled`. That is the shape committed as K5–K8.

#### Key-path measurement behind `EV-U`

The critic's two-module stand-in was rebuilt and re-run in this session
(scratchpad `ev2/kp/`). Module `A` declares
`public struct EV { public init() {}; public internal(set) var pixelLength: Double = 1; var theme: Int = 0 }`
and `public func environment<V>(_ kp: WritableKeyPath<EV, V>, _ v: V) -> EV`,
which starts from a value with `pixelLength = 0.5` and `theme = 7`.

- From module `B`, `environment(\.self, EV())` compiled, ran (exit 0), and
  printed `pixelLength 1.0 theme 0`: both the `internal(set)` field and the
  internal field were reset from outside the module.
- From module `C`, `environment(\.pixelLength, 1.0)` failed to typecheck with
  `cannot convert value of type 'KeyPath<EV, Double>' to expected argument type 'WritableKeyPath<EV, Double>'`.

#### Source facts re-checked for the second pass, at `f64e58a`

- `grep -rn "registerHandlers(" Sources` finds **five** callers: `Box.swift:99`,
  `Stack.swift:123`, `Text.swift:304`, `FrameModifier.swift:48` and
  `NativeTappable.swift:35` (plus `Passes.swift:426`, the forwarding pass
  method). The first pass said six.
- `StateBinder.bind(` has five call sites, all in `Sources/`
  (`ElementGroup.swift:112,129,139`, `Component.swift:130`, `Frame.swift:1349`),
  and **none in `Tests/`**, so removing `bind(_:table:id:)` breaks no test.
- `PrepaintPass.deferred` and `PaintPass.deferred` (`Passes.swift:494`, `:642`)
  run their body in place, inside the caller's closure, so a scope around a
  `Deferred` is still on the stack when its content runs.
- `Window.dispatchClick` requires `hit.id == pressed` and a non-nil `onClick`
  (`Window.swift:1195-1201`); `updatePointerState` sets `active` to the topmost
  hitbox's owner on `mouseDown` whatever its handlers (`:1128`). Scroll regions
  register opaque hitboxes with no `onClick` (`Frame.swift:502`).
- The `$anim-content` named-child spelling is
  `.child(of: id, at: 0, name: ElementID("$anim-content"))`
  (`AnimatedStyle.swift:185`).
- `MetalUI` re-exports `MetalUICore` (`App.swift:8`).
- The accessibility-bridge spec (`2042a54`) synthesizes nodes inside
  `registerHandlers` from `handlers.onClick != nil`, adds
  `collectsAccessibility:` to `Frame.init` and to `Window`'s `Frame(...)` call,
  derives `.press` from a `lastHitboxes` entry with the element's id and an
  `onClick`, and says disabled behaviour waits for task 9.
- The modifier-composition spec (`1c6f686`) adds
  `ProposalElementGroup.requestProposalGroupLayout`, two `StateBinder.bind` call
  sites (`MC-H`), deletes `FrameModifier.swift`, and does not mention
  `EnvironmentScope`.

#### What the second pass did NOT establish

- **SwiftUI's hover look on a disabled view.** `EV-T`'s hover half is a choice.
- **Whether SwiftUI text measurement moves with `locale`.** E21 pins MetalUI's
  inertness, not alignment.
- **The suite, goldens and guards were not re-run**: nothing in `Sources/` or
  `Tests/` changed since the first pass's baseline.

### Lane 1 — `KeyBinding` (`EV-N`), 2026-09-15

**Where.** Worktree `/Users/maxburger/Developer/MetalUI-environment`, branch
`feat/environment`, on `e9afded`. No other agent was live in the worktree.

**What changed.** `public struct Binding` → `KeyBinding` in `Keymap.swift`, with
`@available(*, deprecated, renamed: "KeyBinding") public typealias Binding`.
`Keymap.bindings`, both `Keymap` inits, `KeymapBuilder.buildBlock` and the private
`bestBinding` tuple are retyped. Doc comments spelling `Binding` are respelled in
`Keymap.swift` and `KeyContext.swift:63`. The demo's nine keymap lines
(`main.swift:1104-1112`) and all 45 hits in `KeymapTests.swift` (44 calls, one
doc comment) spell `KeyBinding`. The English-word and `@Binding` mentions the
spec lists were left alone.

**Red first** (commit `14c1fbb`):

- G5 alone, before the rename: `Expectation failed: (result.messages → "").contains("'Binding' is deprecated")`
  at `EnvironmentCompileGuards.swift:48`, and the same for `"KeyBinding"` at `:50`.
  `succeeded` held: the old struct compiles.
- `KeymapTests` respelled: 44 distinct `error: cannot find 'KeyBinding' in scope`.

**Mutations of G5.** All four runs (red, a, b, c) are recorded under `EV-N`. Each
reddened a different subset of the three expectations; (c), a deprecation with
no `renamed:`, reddens only the `"KeyBinding"` expectation.

**Suite**, after `swift package clean`, build and test output in one file:

- `swift build --build-system native --build-tests` then
  `swift test --no-parallel --build-system native`:
  `Test run with 1085 tests in 1 suite passed`, **0 `warning:`**, **0 `error:`**.
  Two tests skipped, both the documented gated ones (`regenerateAllGoldens`,
  `aListsWorkIsTheSameFor100kRowsAsFor500`). G5 printed `passed`.
- `swift test --no-parallel` (default build system), the same checkout
  afterwards: `1085 tests`, **0 `warning:`**, **0 `error:`**, G5 `passed` —
  against the native build's leftover `Modules`, which were current (CLAUDE.md,
  "When CI lands").
- **The deprecation warning does not reach the suite log**: the child `swiftc`
  writes it into the helper's pipe. Checked by the 0 above, not assumed.
- Goldens: **97**; `git diff --name-only f64e58a -- Tests` lists no `.json`.
- Guards: **46** (`EnvironmentCompileGuards` 1 over the design baseline's 45).

### Lane 2 — scoped environment (`EV-A`…`EV-C`, `EV-G`…`EV-M`, `EV-O`, `EV-P`, `EV-U`, `EV-V`), 2026-09-15

**Where.** Worktree `/Users/maxburger/Developer/MetalUI-environment`, branch
`feat/environment`, from `a3c92a7`. No other agent was live **in this worktree**.
`swift package clean` ran before the first build (a new public type in
`MetalUICore`, a stored property on `Frame`).

**One contention, recorded because it touched the instrument.** The session
scratchpad is shared with the parallel tracks' agents, and another agent's
mutation harness wrote into the same `mut/summary.txt` while this lane's batch
ran (its lines read "1094 tests" and name overlay and modifier tests). Only that
summary file was shared: every mutation here wrote its own full log, those logs
are internally consistent, and every figure below and in the decisions doc was
re-read from the per-mutation logs after the batch, not from the summary. The
other agent's runs used their own worktree; this worktree's `git status` was
clean after every run.

#### What changed

- New: `Sources/MetalUICore/LayoutDirection.swift`,
  `Sources/MetalUI/EnvironmentValues.swift` (`EnvironmentValues`,
  `EnvironmentKey`, `DynamicTypeSize`), `EnvironmentProperty.swift`
  (`@Environment`, `BindableEnvironment`), `EnvironmentScope.swift`
  (`EnvironmentScope`, `EnvironmentWrite`, `EnvironmentScopeLayout`,
  `.environment`/`.transformEnvironment`/`.dynamicTypeSize`/`.theme`).
- Shared, additive: `Frame.swift` (`theme` read in place from
  `environmentTop`; `rootTheme`; `rootEnvironment` whose setter re-stamps
  `theme` and `pixelLength`; `scopedValues(applying:)`; `withEnvironment`;
  `environmentSnapshot()`; three counters; **no init parameter**);
  `Passes.swift` (three get-only `environment` accessors, `PaintPass.theme`
  doc); `Window.swift` (`public var environment` with a `didSet` that always
  dirties; one statement `frame.rootEnvironment = environment` after the
  `Frame(...)` expression, which is unedited); `StateReflection.swift`
  (`bind(_:in:id:)` replaces `bind(_:table:id:)`, no overload, no default);
  `ElementGroup.swift` ×3 and `Component.swift` ×1 call sites; `Frame.render`'s
  root bind.
- **The shape cache stores one merged ordinal list and a `hasEnvironment`
  flag**, not separate `State` and `Environment` lists as the spec sketched:
  nothing reads the two lists apart, and the hit path's question is only "does
  this type need a snapshot". Behaviour is the spec's.
- Tests: `EnvironmentTests.swift` (E1–E21), six guards appended to
  `EnvironmentCompileGuards.swift`, and one doc sentence in
  `PhaseSeparationTests.swift`'s theme section pointing at G1−.

#### Red first (commit `e9bafb0`)

The API landed as a **shell** so the tests compiled and failed on mechanism:
the scope applied no write and pushed nothing, the binder bound no
`@Environment`, and `Window` did not hand its environment to the frame. `Frame`'s
root stamping was **not** shelled. Filtered run of the 28 environment tests,
native build: **15 failed with 36 issues**. Each failure line, at `e9bafb0`:

- E1 `:206` readings all 0; E2 `:224` `[0, 0]`; E3 `:241`, `:242` inner and
  sibling `[0, 0, 0]`.
- E6 `:391`, `:396` `[[0], [0], [0]]`; E7 `:410` `[0, 0]`.
- E9 `:454` the scoped arm paints `Theme.light.surface`.
- E11 `:475`, `:481` `[0, 0, 0]` on both arms.
- E12 `:504`, `:506` the scoped and `Deferred` arms light.
- E19 `:613`, `:627` both arms light; `:616` the control reads 0, not 3.
- E14 `:662` the recorder reads `en_US`, not `de_DE`.
- E15, on both trees: `:714` push 0 ≠ 3, `:716` transform 0 ≠ 1, `:720` push
  0 ≠ 6, `:722` transform 0 ≠ 2, `:727` push 0 ≠ 3, `:728` snapshot 0 ≠ 3,
  `:729` the reader reads `[0]`.
- E20 `:757`–`:759`, `:764`–`:766` `counter.n` 0, `[0, 0, 0]`, transform count 0.

**Green on the shell**, as the spec predicted or for a stated reason: E4 (red
only if a shell registers a node), E5 (no mechanism to lose state), E8 (inert
pin), E10, E16, E17, E21 (aligned or inert pins), E18 (a regression pin), and
**E13** — against the spec's predicted "light; 1 at scale 2", because the shell
kept `Frame`'s root stamping. E13's three mutations are its red readings. The
six new guards passed on the shell; each is reddened by its mutation instead
(decisions doc, `EV-C`, `EV-G`, `EV-J`).

**A first-draft guard failed for a real reason.** G1+'s fixture declared
`public struct Reader { @Environment(\.isEnabled) var isEnabled }` and failed in
the Swift 6 language mode: "memberwise initializer for 'Reader' cannot be both
nonisolated and main actor-isolated" (and "default initializer…"), with a note
that the initializer for `_isEnabled` is main-actor-isolated. `Environment` is
`@MainActor` like `State`, so a type declaring either must be main-actor
isolated — every `Element` and `Component` already is, through its protocol.
The fixture gained `@MainActor`. G1−'s wrapper fixture got the same fix, and its
message assertion was tightened from `theme` to `'theme' is inaccessible`,
because a nonisolated fixture's note names `_theme` and would have satisfied the
bare word for the wrong reason. The exact diagnostics, from the fixtures typechecked
outside the harness:

- `'theme' is inaccessible due to 'internal' protection level` (both G1− fixtures);
- `cannot assign to property: 'environment' is a get-only property` (G2);
- `cannot convert value of type 'any KeyPath<EnvironmentValues, Double> & Sendable' to expected argument type 'WritableKeyPath<EnvironmentValues, Double>'` (G3);
- `generic struct 'HStack' requires that 'Box<EmptyGroup>' conform to 'ProposalElementGroup'` (G4−).

#### Suite (implementation commit `a4ef92d`)

- `swift build --build-system native --build-tests` then
  `swift test --no-parallel --build-system native`, both streams to one file:
  **`Test run with 1112 tests in 1 suite passed`**, **0 `warning:`**, **0
  `error:`**. The two documented gated tests skipped. This native run printed no
  deprecation line matching `warning:` (grep for "deprecat" found only G5's
  test name).
- `swift test --no-parallel` (default build system), afterwards: **1112 tests
  passed**, 0 `warning:`, 0 `error:`.
- Goldens: **97**; `git diff --name-only f64e58a -- '*.json'` empty. No file
  under `Sources/MetalUILayout/` changed.
- Guards: **52** by the per-file count (`PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `UnitSafetyTests` 3 hits = 2, `AXNodeTests` 3,
  `EnvironmentCompileGuards` 7). All seven environment guards printed `passed`,
  not `skipped`, on the native build.
- A full native suite run takes about 27 s on this machine, so every mutation
  below ran the whole suite, not a filter.

#### Mutations

Forty-one runs (36 planned, 5 re-spelled after a failed instrument), one at a time, full suite, restored with `git checkout` and
`git status --short` checked empty after each. **The readings and the tests each
one reddened are under the ruling each mutation serves, in the decisions doc**;
this is what the batch taught beyond them:

- **Three instruments failed first, and each is recorded, not smoothed over.**
  E4(a) as a legacy wrapper node killed the run at SA-G's trap (no summary line:
  a truncated run, shape 11), so it was re-run with a native wrapper for native
  content. E5's spec spelling does not compile against the test file. E5's second
  spelling compared `String(describing:)` of two `EnvironmentValues` and never
  flipped, because writing a custom key's default value still adds an entry;
  E5 stayed green and E4/E10 reddened for the wrong reason. The third
  spelling — the scope's id keyed by its values — reddens E5.
- **E6(c) stayed green on E6, as the spec predicted**, and reddened E7 and
  E15's reader-snapshot count. E6's limit, not coverage.
- **E21's mutation is void.** Routing the locale into a line-break tokenizer did
  not move the Thai sample's min-content width. E21 pins that no locale reaches
  measurement today; it does not show that one would move it.
- **E18 reddens at its reference require, never at `after == lightRef`**: any
  mutation that makes the swapped frame light makes the dark reference light too.
- **G4+ could not be run as written**: deleting the conformance stops the test
  target compiling (E11 and E17 use it). It was run with those two tests under
  `#if false` (1110 tests) and reddened only its guard.
- **E13(a) and E18's own mutation redden 17 and 19 tests**, most outside this
  file (colour animation, `ThemeTests`, and `theSevenRetentionSlotsAreMutuallyDistinct`),
  because every test that builds `Frame(theme: .dark)` depends on the root stamp.

#### Deferred, or not done by this lane

- `.disabled(_:)`, the gate in `Frame.registerHandlers`, D1–D16 and the window
  capture: lane 3.
- `@Environment` inside `AnyElement` stays inert (E8), for task 8.
- RTL mirroring stays unimplemented (E17), for task 6.
- The inert and divergence rows, the reserved-name and `Window.environment`
  paragraphs, and the counts are owed to the integration step (spec, "Owed to
  the integration step"); CLAUDE.md was not edited.
