## Environment and control state (plan task 9) — `feat/environment`

The record for plan task 9. Rulings: `docs/superpowers/2026-09-15-environment-decisions.md`
(`EV-`, lettered, `EV-A`…`EV-Z`; the next is `EV-AA`). Spec:
`docs/superpowers/specs/2026-09-15-environment-design.md`. This file is not yet
indexed by `docs/record/README.md`; the integration step owns that index.

**What this track built, on `feat/environment` from `f64e58a`:** scoped
environment values with SwiftUI's nearest-writer precedence (`EnvironmentValues`,
`EnvironmentKey`, `@Environment`, `.environment(_:_:)`,
`.transformEnvironment(_:transform:)`, `.dynamicTypeSize(_:)`, `.theme(_:)`,
`pass.environment` on all three passes, `Window.environment`); a disabled
control state (`.disabled(_:)`, one gate in `Frame.registerHandlers`); and the
keymap's `Binding` renamed `KeyBinding` behind a deprecated alias. **The design
was reviewed by two critics (18 and 11 findings, all dispositioned), then built
in four lanes, each verified by an independent agent that re-ran the suite,
re-took the red run and ran mutations of its own.** All four verdicts were ok.
**A second verification round then re-checked lanes 2b, 3 and 4 at `e709dc5`
and `d18f2ce`, and all three verdicts were ok again.** It found no defect in
the code. It did find four new minor issues: two claims under `EV-Y` that no
test pins; a disabled `ScrollView` that still scrolls; merge-tree tree ids that
cannot be reproduced; and line numbers in `DisabledTests.swift` that have
shifted. The window capture the brief asked for was **not taken** (the session
was locked). An offscreen stand-in and E18 stand in for it, and the capture is
still owed.

The per-lane entries below are the log, in the order they were written. The
summary sections at the end are the part to read first: "Verification of lanes
2b, 3 and 4", "Second verification round", "Hazards in one place", "What
remains open" and "For the integrator".

### Commits, in order

| commit | lane | what |
|---|---|---|
| `bbd4d66` | design | spec, decisions doc, first three probes |
| `e9afded` | design, second pass | the first critic's 18 findings applied |
| `14c1fbb` | 1, red | G5 and the respelled `KeymapTests` |
| `a3c92a7` | 1, green | `Binding` → `KeyBinding`, deprecated alias (`EV-N`) |
| `e9bafb0` | 2, red | E1–E21 and G1–G4 over an API shell |
| `a4ef92d` | 2, green | scoped environment, `@Environment`, `Window.environment` |
| `f4dcad8` | 2, docs | lane 2's red run and 41 mutation runs |
| `8d0d3fe` | design, third pass | the second critic's 11 findings; two new probes |
| `d271a64` | 2b, red | E12's after-scope arm, E22–E24, T1/T2, G6 |
| `de84219` | 2b, green | bare root locale, window-stamped locale, sealed root during render (`EV-Y`, `EV-Z`) |
| `087c405` | 2b, docs | lane 2b's red run and 14 mutation runs |
| `2de4eef` | 3, red | D1–D16, E5's D10 arm, G6's `.disabled` |
| `6957464` | 3, green | the disabled gate in `Frame.registerHandlers` |
| `ba9f4cb` | 3, docs | lane 3's red run and 19 mutation runs |
| `cbe5fc0`, `19749c7` | 4, docs | capture not taken; offscreen stand-in; `EV-W` re-measured |
| `e709dc5` | record | verifier readings folded in, refuted claims corrected, "For the integrator" |
| `d18f2ce` | 4, re-run, docs | capture still not taken; `EV-W` measured on built merges at `aa5d055` and `6a0169c` |
| this commit | record, second round | second verification round folded in; `EV-Y` narrowed; the unpinned wheel scroll added to `EV-E`/`EV-Q`; spec Status |

The record commit also corrects three doc comments and two decision texts the
verifiers refuted (below): `EnvironmentScope.swift`'s "does not compile",
`DisabledTests.swift`'s D6 comment, and `EV-F`/`EV-X`/`EV-Y`/`EV-W` in the
decisions doc. Comments only: after them, `swift build --build-system native
--build-tests` then `swift test --no-parallel --build-system native` printed
**`Test run with 1133 tests in 1 suite passed after 26.933 seconds`**, 0
`error:` and 0 `warning:` across both logs, the two gated tests skipped.

### Counts

| | `f64e58a` | lane 1 | lane 2 | lane 2b | lane 3 = lane 4 = HEAD |
|---|---|---|---|---|---|
| tests | 1084 | 1085 | 1112 | 1118 | **1133** |
| goldens | 97 | 97 | 97 | 97 | **97** |
| typecheck guards | 45 | 46 | 52 | 53 | **53** |
| `error:` / `warning:` | 0 / not established | 0 / 0 | 0 / 0 | 0 / 0 | **0 / 0** |

Guards at HEAD, per-file `grep -c canTypecheck`: `PhaseSeparationTests` 19,
`ErasureCompileGuards` 10, `ProposalLayoutCompileGuards` 6,
`ElementGroupTrapTests` 5, `UnitSafetyTests` 3 hits = 2, `AXNodeTests` 3,
**`EnvironmentCompileGuards` 8**. `git diff --stat f64e58a -- '*.json'
Sources/MetalUILayout` is empty: **no golden moved and the engine was not
touched.** Every figure was re-taken under both `--build-system native` and the
default build system by the implementers, and by the verifiers of lanes 2b, 3 and 4.

**+49 tests, all additions.**

| file | new | lane | contents |
|---|---|---|---|
| `Tests/MetalUITests/EnvironmentCompileGuards.swift` (new) | 8, all guards | 1, 2, 2b | G5 the deprecated `Binding` alias; G1+/G1− readable in every phase, theme unreachable; G2 no write through a pass; G3 `pixelLength` not writable; G4+/G4− proposal container over a scope; G6 every public writer compiles from outside the module |
| `Tests/MetalUITests/EnvironmentTests.swift` (new) | 24 | 2, 2b | E1–E21 (precedence, transparency, three-phase reads, `@Environment` binding, `Component`, proposal content, scoped theme and `Deferred`, root theme and scale, E18 the Space swap as pixels, whole-value writes, `Window.environment`, counted work, once-per-frame transforms, the three inert pins); E22–E24 (lane 2b) |
| `Tests/MetalUITests/EnvironmentTrapTests.swift` (new) | 2 | 2b | T1 `aRootEnvironmentWriteDuringARenderTraps` (exit test, three phases), T2 its `.success` control |
| `Tests/MetalUITests/DisabledTests.swift` (new) | 15 | 3 | D1–D9, D11–D16 (D10 is an arm of E5) |
| `Tests/MetalUITests/KeymapTests.swift` | 0 | 1 | 45 `Binding` spellings respelled `KeyBinding` |
| `Tests/MetalUITests/PhaseSeparationTests.swift` | 0 | 2 | one doc sentence pointing at G1− |

1084 + 1 + 27 + 6 + 15 = 1133.

### Probes (all under `docs/probes/`, output in each header, each with a control)

| probe | arms | run |
|---|---|---|
| `swiftui-environment-scoping.swift` | A precedence, B `isEnabled`, C defaults, D state across a value change, E subview counts, F overlays, G dynamic type, H RTL | design session, twice |
| `swiftui-disabled-interaction.swift` | P pointer, K focus and keys (K0–K8), R press/release across a flip | design; re-run in the second pass |
| `swiftui-environment-api-shape.swift` | compile-only, writable vs get-only | design |
| `swiftui-disabled-ancestor-and-order.swift` | N disabled child in a tappable ancestor, O a modifier inside vs after a scope | third pass; **re-run by lane 2b's verifier, N0–N4 and O0–O6 reproduced** |
| `swiftui-environment-pixel-length.swift` | V bare `EnvironmentValues()`, X `displayScale` and `\.self` writes in a window | third pass; **re-run by lane 2b's verifier, V0–V2 and X0–X3 reproduced** |

(`swiftui-layout-input-validation.swift` and `swiftui-layout-protocol-contract.swift`
in the same directory are task 2's, not this track's.)

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

### Design session, third pass (2026-09-15), at `f4dcad8`

A second critic reviewed lanes 1–2 as built and lane 3 as designed, and reported
11 findings (decisions doc, "Third pass"). This session changed **no source and
no test**: `git diff --stat f4dcad8 -- Sources Tests` is empty at this pass's
commit, so the critic's suite reading at `f4dcad8` stands (1112 tests, 0
`error:`, 0 `warning:`, `--build-system native`; log in the critic's session
scratchpad) and was not re-taken. Goldens: no file under `Tests` changed, 97.

#### Probes written and run (both committed under `docs/probes/`, output in their headers)

- **`swiftui-disabled-ancestor-and-order.swift`**, from the critic's scratch
  `order-probe.swift` (whose first version, with the O arms, the critic had
  overwritten; the O arms were rebuilt from the finding's text and re-run, not
  copied). Arms and readings:
  - N0 control (enabled child gesture in a tappable `ZStack`): child 1, parent 0.
  - N3 control (enabled `.plain` Button in a tappable card): button 1, parent 0.
  - N4 control (a gesture-less child in a tappable card): parent 1.
  - **N1 disabled child gesture: child 0, parent 1.**
  - **N2 disabled `.plain` Button: button 0, parent 1.**
  - O0 control 1; O1 gesture inside `.disabled` 0; **O2 gesture after
    `.disabled` 1; O3 after `.disabled` and `.padding(4)` 1**; O4 enabled
    `VStack` gesture over a disabled gesture-less child 1.
  - O5 control (background before the writer) probe=1; **O6 background after
    the writer probe=0**.
- **`swiftui-environment-pixel-length.swift`**, from the critic's scratch
  `px-probe.swift` and `ev-default.swift`, with a V2 comparison added:
  - V0 bare `EnvironmentValues()`: pixelLength 1.0, displayScale 1.0, locale '',
    isEnabled true, large, leftToRight. V1 control (`displayScale = 4`):
    pixelLength 0.25. **V2: bare locale `== Locale(identifier: "")` true,
    `== Locale.current` false**, `Locale.current` en_US.
  - X0 control in a 2x window: pixelLength 0.5, displayScale 2.0, en_US.
    **X1 `.environment(\.displayScale, 3)`: pixelLength 0.333…** **X2
    `.environment(\.self, EnvironmentValues())`: pixelLength 1.0, displayScale
    1.0, locale ''.** X3 (`\.self` inside an outer locale write): locale ''.
- **Run three ways each**, filtered with the committed `grep -v`, and the three
  outputs of each probe were byte-identical (`diff` empty): `/usr/bin/swift
  <file>` (Apple Swift 6.4, swiftlang-6.4.0.33.1), `/usr/bin/swiftc` then the
  binary with `OS_ACTIVITY_DT_MODE=1`, and `swiftc` from `PATH` — which on this
  machine is **swiftly's swift.org 6.3.3**, not Apple's (`EV-R` item 9). macOS
  26.6.2 (25G83), system appearance Dark. Exit status 0 each time.
- One label was renamed after the first run (`O0 control, Color.onTapGesture: 1
  expected` → `O0 control, Color.onTapGesture`), and the probe was re-run in all
  three forms after the rename; the header holds the post-rename output.

#### Compiler measurement: modifiers after a scope already compile (finding 7)

Against this worktree's `--build-system native` modules at `f4dcad8`
(`swiftc -typecheck -diagnostic-style=llvm -I .build/arm64-apple-macosx/debug/Modules`
plus the C module map directories, the `Typecheck.swift` helper's arguments),
a plain-import fixture:

```swift
Box().environment(\.probe, 1).frame(width: Pixels(20), height: Pixels(20)).padding(Pixels(4)).onClick {}
Box().theme(.dark).frame(width: Pixels(20), height: Pixels(20)).background(.surface).hoverBackground(.accent)
```

**typechecked with exit status 0 and no diagnostic.** A second fixture,
`Box().theme(.dark).padding(Pixels(4))` and `Box().theme(.dark).onClick {}`,
failed as `EV-B` said: "referencing instance method 'padding' on
'EnvironmentScope' requires that 'Box<EmptyGroup>' conform to
'ProposalElementGroup'" and "value of type 'EnvironmentScope<Box<EmptyGroup>>'
has no member 'onClick'". Cause: `FrameModifier.swift:62-67` declares
`frame(width:height:)` in `extension ElementGroup`, and `FrameModifier` is a
`StyledElement`. So `EV-B`'s "does not compile" limit was never true for
`.frame`; the critic's "becomes false at the composition merge" understated it.
`FrameModifier.prepaint` (`:45-50`) calls `pass.registerHandlers` before
`content.prepaintGroup`, and `paint` fills before `content.paintGroup`: both
outside any scope in its content, which is `EV-X`'s mechanism.

#### Merge measurement (finding 2)

`git merge-tree --write-tree --name-only feat/environment feat/ax-bridge`
(`f4dcad8` × `53d3bf6`, merge base `f64e58a`): **CONFLICT in
`Sources/MetalUI/ElementGroup.swift` and `Sources/MetalUI/Window.swift`**;
`Frame.swift` and `Passes.swift` **auto-merge**. The same against
`feat/modifier-composition` (`ec65da6`): no conflict.

Read at `53d3bf6` (`git show`, read-only): `Frame.registerHandlers(_:at:id:)` is
a bare forward to `registerHandlers(_:at:id:accessibleText:synthesizesAccessibility:)`
(`Frame.swift:610-618`); the record is
`AXEmission(id:, declared: handlers.axNode, text:, isClickable: handlers.onClick != nil, isEnabled: true, …)`
(`:735-741`) behind `hasSomethingToSay`, with `adjustable` read from
`handlers.actions` (`:729`). The bridge's spec derives `.press` from `hitboxes`,
`.increment`/`.decrement` and `isFocusable` from the `FocusRegistry`, and
`isEnabled = false` from a declared trait or `record.isEnabled == false`. Its
`AB-Z` merge contract still assumes an `environment:` init parameter, a
`keyboard` copy with stripped actions, and a hitbox with `Handlers()`.
Read at `ec65da6`: the composition spec's environment-collision section still
says "`bind` gains `environment:`" and "E11 reads only in paint"; its lane 3
guard `aMarkerConformerThatRegistersALegacyNodeDoesNotCompile` rejects E11's
fixture shape.

#### Source facts re-checked for finding 1, at `f4dcad8`

- `Window.dispatchClick` (`Window.swift:1215-1224`): the topmost opaque hitbox
  under the release, `hit.id == pressed`, and its own `onClick`; no bubbling
  (its doc: "a container's `onClick` never sees a click that landed on a child
  with its own").
- `updatePointerState`: `mouseDown` sets `active = topmostHitboxOwner(at:)`, so
  a press over no hitbox leaves `active` nil and `dispatchClick` returns at its
  first guard.
- `PaintPass.isHovered(_: GlobalElementID)` is `frame.hoveredElement == id` and
  `isActive` is `frame.activeElement == id` (`Passes.swift:725-738`): exact id
  equality, so an element with no hitbox is never hovered or active.
- `Frame.rootEnvironment`'s setter (`Frame.swift:189-198`) assigns
  `environmentTop = values` unconditionally (finding 11), and
  `grep -rn "rootEnvironment" Sources Tests` finds one production writer
  (`Window.swift:860`) and one test writer (`EnvironmentTests.swift:530`,
  between two renders).

#### What the third pass did NOT establish

- **No MetalUI code ran for finding 1.** "A disabled target with no hitbox lets
  an enabled ancestor's `onClick` fire" is read from `dispatchClick` and
  `topmostOpaqueHitbox`, not measured; lane 3's D3 ancestor arm is the
  measurement, with its control.
- **SwiftUI's hover under `.disabled`**, and whether an enabled ancestor's hover
  look shows over a disabled child, stay unprobed (`EV-T`, D16's consequence
  arm is MetalUI's choice).
- **The accessibility joint test** exists on neither branch; its expected
  readings are design, not measurement.

E22's spelling **was** typechecked, the same way as the after-scope fixture:
`HStack(spacing: Pixels(0)) { Pair(Rectangle(…), Rectangle(…)).environment(\.probe, 1); Rectangle(…) }`
returned as `some Element` compiles with no diagnostic at `f4dcad8`.

### Lane 2b — hardening lane 2 (`EV-B`, `EV-C`, `EV-J`, `EV-U`, `EV-X`, `EV-Y`, `EV-Z`), 2026-09-15

**Where.** Worktree `/Users/maxburger/Developer/MetalUI-environment`, branch
`feat/environment`, from `8d0d3fe`. No other agent was live in this worktree.
Every run below used `--build-system native`; logs in the session scratchpad
under `ev2b/` (this session's own directory, not shared with the lane 2
harness's `mut/summary.txt`). macOS 26.6.2, Apple Swift 6.4, `Locale.current`
`en_US`.

#### What changed

- `EnvironmentValues.swift`: `init()` sets `locale = Locale(identifier: "")`;
  new internal `static func windowDefault()` (the bare value with
  `Locale.current` stamped). Doc comments on the type (the `EV-U` paragraph now
  says the `theme` half is MetalUI's own key and the `pixelLength` half a
  divergence), `init` (bare defaults, V0/V2, not probe C's), `locale` and
  `pixelLength` (no "as SwiftUI's is"; X1/X2 named).
- `EnvironmentProperty.swift`: the unbound-read doc names the root locale.
- `EnvironmentScope.swift`: the "where it can go" doc says `.frame` may follow
  a scope and sits outside it (`EV-X`).
- `Window.swift`: the initial value expression only
  (`EnvironmentValues.windowDefault()`), plus doc sentences.
- `Frame.swift`: `private var isRendering`, set on `render`'s first line and
  cleared on its last (after `stateTable.sweep()`); the `rootEnvironment`
  setter begins with the `EV-Z` precondition; its doc replaces "set it before
  `render`, never during".
- **One deviation from the spec's wording**: the helper is `internal`, not
  "private static" — a `private` member of `EnvironmentValues.swift` cannot be
  called from `Window.swift`.
- Tests: E12 extended in place (13/14pt after-`.theme` arm, 15/16pt disagreeing
  spelling); E22, E23, E24 in `EnvironmentTests.swift`; `NativeEnvRecorder`
  records its id in `prepaint`; E8's doc names the root locale; E11's doc names
  the marker-shape port owed at integration. New `EnvironmentTrapTests.swift`
  (T1, T2). G6 appended to `EnvironmentCompileGuards.swift`.

#### Red first (commit `d271a64`)

Full suite, native build: **`Test run with 1118 tests in 1 suite failed with 9
issues`**, 0 `error:`, 0 `warning:`. Each failure line, at `d271a64`:

- E24 `EnvironmentTests.swift:834` `(EnvironmentValues().locale → en_US) ==
  (Locale(identifier: "") → )`; `:835` `"en_US" == ""`; `:848`
  `(log.paint["reset"]?.locale.identifier → "en_US") == ""`.
- T1 `EnvironmentTrapTests.swift:69`, `:77`, `:85` `.failure → .exitCode(0)`
  (layout, prepaint, paint); `:74`, `:82`, `:90` the stderr is empty.

**Passed on arrival, as the spec states**: E12's new arm (instrument pin),
E22, E23 (transparency on the shared entry), T2 (positive control), G6 (the
writers are public), and E24's window arm (ii) (lane 2's `init` already read
`Locale.current`).

**A first-run failure that was the fixture's, not the source's.** The very
first red run read 10 issues: G6 also failed, with `cannot find 'Locale' in
scope` at both of its `Locale(identifier:)` spellings. `import MetalUI` does
not re-export Foundation. The fixture gained `import Foundation` before the
commit; G6 then passed, as a positive guard over public API must.

#### Suite (implementation commit `de84219`)

- `swift test --no-parallel --build-system native`: **`Test run with 1118
  tests in 1 suite passed`**, 0 `error:`, 0 `warning:` (this run printed no
  deprecation line matching `warning:`).
- `swift test --no-parallel` (default build system), afterwards: **1118 tests
  passed**, 0 `error:`, 0 `warning:`.
- Goldens: **97**; `git diff --stat f64e58a -- '*.json'` empty. No file under
  `Sources/MetalUILayout/` changed.
- Guards: **53** by the per-file count (`PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `UnitSafetyTests` 3 hits = 2, `AXNodeTests` 3,
  `EnvironmentCompileGuards` 8). G6 printed `passed` on the native build, and
  `failed` under each of its three mutations, so it runs.

#### Mutations

Fourteen runs, one at a time, full suite, `git checkout -- Sources Tests` and
`git status --short` empty after each (all fourteen read 0 lines). Readings and
reddened tests are under each ruling's Mutations line in the decisions doc
(`EV-B` proposal path, `EV-C` G6, `EV-X` lane 2b half, `EV-Y`, `EV-Z`). What
the batch taught beyond them:

- **The spec's `EV-X` hoist overload is a void instrument for every
  after-scope arm.** The suite read 1118 passed, 0 issues. A separate
  `swiftc -typecheck` against the mutated native modules showed why: the
  overload wins an unconstrained `Box().theme(.dark).frame(…)` (it converts to
  `EnvironmentScope<FrameModifier<…>>`), but when `.background` follows, the
  solver picks `ElementGroup.frame` instead, since only a `StyledElement` has
  `.background`. Against unmutated modules the same conversion fails (the
  positive control). Respelled as `FrameModifier` pushing its content scope's
  stored values around its own registration and fill, it reddens exactly E12's
  14pt slot. Lane 3's D2 after-`.disabled` arm has the same shape; the spec's
  D2 row now says to use the respelling.
- **`EV-Z` (b), the push-counter precondition, reddened T1 as well as T2** —
  not predicted. `RootWriter` sits under no scope, so the counter is 0 when it
  writes. That is the ruling's rejected alternative failing where the ruling
  said: a root-level write during render.
- **`EV-Y` (b) reddened both of E14's default-locale expectations** (`:797`
  window, `:802` recorder), not one.
- **E4(a) needed no second spelling this time**: the native/legacy split by
  `Content.self is any ProposalElementGroup.Type` was used from the start, so
  no run was truncated by SA-G's trap.
- **E22 and E23 see the shared entry only.** Their mutations prove the
  instruments; the typed proposal entry does not exist on this branch, and the
  re-run against it is the integration step's (`EV-W` item 1).

#### Deferred, or not done by this lane

- `.disabled(_:)`, the gate, D1–D16, G6's `.disabled` arm and `EV-X`'s lane 3
  half (D2's after arm under the respelled hoist): lane 3.
- The window capture and merge re-measure: lane 4.
- E11, E22 and E23 are in the marker shape the modifier-composition merge
  rejects; porting them and re-running their mutations is owed to the
  integration step (`EV-W` item 1).
- CLAUDE.md's divergence text for `pixelLength` (`EV-U`) and the counts are
  owed to the integration step; CLAUDE.md was not edited.

### Lane 3 — the disabled control state (`EV-D`, `EV-E`, `EV-F`, `EV-T`, `EV-X`), 2026-09-15

**Where.** Worktree `/Users/maxburger/Developer/MetalUI-environment`, branch
`feat/environment`, from `087c405`. No other agent was live in this worktree.
Every run below used `--build-system native` unless it says otherwise; logs in
this session's scratchpad under `ev3/`. macOS 26.6.2; `swift --version` printed
`Apple Swift version 6.3.3 (swift-6.3.3-RELEASE)`; `Locale.current` `en_US`.

#### What changed

- `EnvironmentScope.swift`: `.disabled(_:)` as
  `transformEnvironment(\.isEnabled) { $0 = $0 && !disabled }`, with its doc
  (`EV-D`, `EV-E`, `EV-F`, `EV-T`, `EV-X`).
- `Frame.registerHandlers` (shared): one `let enabled = environmentTop.isEnabled`;
  `focusRegistry.register` only when enabled; the `$focus` slot write only when
  enabled, with `focusedElementProducedThisFrame` still ungated; `insertHitbox`
  only when enabled (no blocker, no derived id); the declared AX node gains
  `.disabled` when not enabled. The method's doc states the gate; the `$focus`
  hazard paragraph now says the hazard is reachable through `Window.focus` on an
  ENABLED, produced, non-focusable element and not through `.disabled`, and
  names D13 as the pin both ways.
- Doc only: `Handlers`' type doc (both gates sit behind `isEnabled`),
  `EnvironmentValues.isEnabled`, and `PrepaintPass.registerHandlers` (one
  paragraph, `Passes.swift`, shared). `Box`, `Stack`, `Text`, `FrameModifier`,
  `OnTapModifier` and `Window` are untouched; `Box.swift` and `Text.swift`'s
  "holds all three gates" stay true (the disabled gate is in the same method)
  and were left alone.
- Tests: new `DisabledTests.swift` (D1–D9, D11–D16, 15 tests); E5 gains the D10
  arm in place (`EnvModel.flag`); G6's chain gains `.disabled(true)`.
- **Test-shape deviations from the spec's wording**, none a design change: the
  D2 proposal arm's root is an `HStack` (a legacy `Row` cannot hold proposal
  content) and its rectangle, like D3's sibling rectangles, is 100×100 so the
  click lands wherever the proposal root places it; D2's list-row `List`
  carries `.width(px(40))` in both halves; every Bool-parameterised control
  spells `.disabled(false)` (probe B2: enabled) rather than deleting the
  modifier; D16's consequence arm has its own control (child enabled). Ids,
  bounds and `isActive` are read through a forwarding `TargetProbe` wrapper that
  hands its own id to the wrapped element (the name `Probe` is taken elsewhere
  in the test module).

#### Red first (commit `2de4eef`)

The red commit carries `.disabled(_:)` (the API shell) and no gate. Full suite:
**`Test run with 1133 tests in 1 suite failed after 30.313 seconds with 41
issues`**, 0 `error:`, 0 `warning:`. Every control passed; each failure line, at
`2de4eef`:

- D4 `DisabledTests.swift:245` `(log.count("P9") → 1) == 0`.
- D2 `:298` `(disabled → 1) == 0` **×11** — box, column, row, stack, text,
  padding-frame, proposal, component, list-row, list, inside. The after arm
  (`:367`) passed, as it must.
- D3 `:417` `clicks(at: pt(10, 40)) { ancestor(true) } == ["parent"]`; `:429`
  `clicks(at: pt(50, 50)) { sibling(true) } == ["under"]`.
- D5 `:471` `!(disabled.focused → true)`; `:472` `(disabled.keys → 1) == 0`.
- D6 `:499`, `:503` `(window.focusedElement → GlobalElementID) == nil`.
- D7 `:556` `(disabled.parent → 1) == 0`; `:557` `(disabled.window → 0) == 1`.
- D8 `:608` `(disabled.parent → 1) == 0`; `:609` `(disabled.window → 0) == 1`.
- D9 `:653` `(disabled.child → 1) == 0`.
- D11 `:680` focus not cleared; `:682` `(log.count("x") → 1) == 0`; `:687`
  `(log.count("x") → 2) == 1`; `:688` focus not nil.
- D13 `:717` — the arm's `try #require` that the first request is cleared: with
  no gate the disabled element is focusable, so the arm stops before its final
  assertion. The instrument arm (`:730`) passed.
- D14 `:776` `(disabled.clicks → 1) == 0`; `:777` `!(disabled.focused → true)`.
- D15 `:814`, `:815`, `:816` — R1, R2, R3 each read 1 (R0 passed).
- D16 `:863` the disabled box hovered; `:864` `(disabled.active → true) == false`;
  `:892` `parentHovered → false`; `:893` `childHovered → true`.
- D12 `:925` `traits(true).contains(.disabled)`.
- E5's D10 arm `EnvironmentTests.swift:378` `(readings.last → 3) == 2`; `:383`
  `3 == 2`; `:387` `4 == 3`.

**Passed on arrival, as the spec states**: D1 (the value exists once
`.disabled` does) and G6 (`.disabled` is public).

#### Suite (implementation commit `6957464`)

- `swift test --no-parallel --build-system native`: **`Test run with 1133
  tests in 1 suite passed after 29.002 seconds`**, 0 `error:`, 0 `warning:`.
  Green on the first implementation run.
- `swift test --no-parallel` (default build system), afterwards: **1133 tests
  passed**, 0 `error:`, 0 `warning:`.
- Goldens: **97**; `git diff --stat f64e58a -- '*.json'` empty; nothing under
  `Sources/MetalUILayout/` changed.
- Guards: **53** by the per-file count (`PhaseSeparationTests` 19,
  `ErasureCompileGuards` 10, `ProposalLayoutCompileGuards` 6,
  `ElementGroupTrapTests` 5, `UnitSafetyTests` 3 hits = 2, `AXNodeTests` 3,
  `EnvironmentCompileGuards` 8). No new guard; G6 printed `passed` on the native
  build and `failed` under its mutation (d), so it runs.

#### Mutations

Nineteen runs after the green commit, one at a time, full suite, each restored
with `git checkout -- Sources Tests` and `git status --short` empty after each
(all nineteen read empty). Readings and reddened tests are under each ruling's
Mutations line in the decisions doc (`EV-C` G6 (d), `EV-D` (a), (b), D4's
counter and D10, `EV-E` (a)–(c), D12, D14, `EV-F` six runs and D11, `EV-T`
(= `EV-E` (b)), `EV-X` lane 3 half). What the batch taught beyond them:

- **The central gate is one edit away from every D2 arm**: deleting the hitbox
  gate reddened all 11 disabled arms at once and left the after arm green. The
  arm list is a pin for future sites, not per-site coverage, as the spec says.
- **The spec's `EV-X` overload is void for D2's `.onClick` spelling too** (1133
  passed); the respelled hoist reddens only the after arm (`:367`).
- **Three unpredicted readings.** `EV-E` (a)'s derived-id blocker also reddens
  D16's consequence arm (the blocker, not the parent, is the hovered hitbox).
  The value-keyed scope id reads 0 in E5's disabled arm while disabled but 2
  again after re-enabling, because the original slot was only tombstoned; it
  also reddens D6 (the focused id moves with the values). D11's `$enabled` slot
  reddens 14 `table.count` assertions across `IdentityTests`,
  `ElementGroupTrapTests` and `MeasurePerformanceTests`, besides D11 itself.
- **D6's mutation as the spec spells it does not separate D6 from D5**:
  registering for `id == focusedElement` also lets a disabled element acquire
  focus, since a request sets `focusedElement` before registration. _(This
  bullet went on to say the SwiftUI-aligned retention "needs a previous-frame
  focus signal", so no mutation could separate them. That "cannot" was not
  measured, and lane 3's verifier refuted it: `Window.lastFocusRegistry` is the
  signal, and a five-line retention reddens D6 alone. See "Verification of
  lanes 2b, 3 and 4" below and `EV-F`'s Mutations.)_
- **`EV-D` (b) and D4's counter stop D7–D9 at their instruments**: each
  re-enables a child with a raw `.environment(\.isEnabled, true)`, so their
  `try #require` that the child holds focus is where they redden.
- G6 (d)'s run printed `error:` twice; both are the typecheck fixture's
  diagnostic quoted in the failure message, not a build error.

#### Deferred, or not done by this lane

- The window capture and the merge re-measure (`EV-P`, `EV-W`): lane 4. With
  this lane `Frame.registerHandlers`' body changed, so lane 4's question whether
  it now conflicts textually with `feat/ax-bridge` is live.
- The joint AX-bridge test and the merged 5-argument gate (`EV-W` item 4), and
  porting E11/E22/E23 (`EV-W` item 1): the integration step.
- Unowned, as before: focus retention across a disable (D6's divergence), a
  disabled look, a hit shape separate from `onClick` (D3's sibling divergence),
  and `.padding`/handler modifiers directly on a scope.
- CLAUDE.md's `.disabled` paragraph, divergences and counts (1133 tests, 53
  guards): owed to the integration step; CLAUDE.md was not edited.

### Lane 4 — the window capture and the merge re-measure (`EV-P`, `EV-W`), 2026-09-15

**Where.** Worktree `/Users/maxburger/Developer/MetalUI-environment`, branch
`feat/environment`, at `ba9f4cb` (lane 3's docs commit; `git diff 6957464
ba9f4cb -- Sources Tests` is empty, so its source is lane 3's implementation
commit). No `Sources/` or `Tests/` file changed in this lane. Scratch worktrees,
all under this session's scratchpad `ev4/` and all detached (no ref moved): `base`
at `f64e58a`, `lane3` at `ba9f4cb`, `merge-mc` at a scratch commit (below). No
other agent was live in this worktree. macOS 26.6.2 (Darwin 25.6.0), `Apple
Swift version 6.3.3`.

#### The window capture (`EV-P`): NOT TAKEN — the session was locked

**System state**, read by a compiled CoreGraphics/AppKit script at 04:35 and
again at 04:44 and 04:47 PDT, unchanged each time:
`CGSSessionScreenIsLocked` 1, `kCGSSessionOnConsoleKey` 1,
`CGDisplayIsAsleep(CGMainDisplayID())` 1, `CGPreflightScreenCaptureAccess()`
true. **System appearance: Dark** (`defaults read -g AppleInterfaceStyle` →
`Dark`; `NSAppearance.currentDrawing()` → `NSAppearanceNameDarkAqua`). One
screen, 2056×1329 pt at scale 2 ("Color LCD"). This is the state the
modifier-composition track's lane 2 met (`feat/modifier-composition:docs/record/10-modifier-composition.md`,
"the window capture was NOT taken").

**What was run.** Both builds succeeded: `swift build -c release --product
MetalUIDemo` at `f64e58a` ("complete! (34.37s)") and at `ba9f4cb` ("complete!
(34.52s)"). A script (`ev4/capture.sh`) ran `swift run -c release MetalUIDemo`
in the package directory, polled a `CGWindowListCopyWindowInfo` listing
(`ev4/winlist`, owner `MetalUIDemo`) until a window appeared, waited 2 s, tried
the capture, and ended the process with `kill` (`pgrep -x MetalUIDemo` empty
afterwards every time). **No input was sent, the pointer was not moved, and
nothing was done to wake or unlock the session.**

| build | window (id, bounds, flags) | `screencapture -l <id> -o -x` | ScreenCaptureKit fallback |
|---|---|---|---|
| `f64e58a`, run 1 | 77700, (614, 259) 828×533, onscreen, layer 0, "MetalUI — Milestones 1 to 3" | `could not create image from window`, exit 1 | not tried |
| `f64e58a`, run 2 | 77735, same bounds | same | trapped: `Assertion failed: (did_initialize), function CGS_REQUIRE_INIT` (the script did not touch `NSApplication.shared` first; a harness error) |
| `f64e58a`, run 3 | 77739, same bounds | same | `SCScreenshotManager.captureImage` on `SCContentFilter(desktopIndependentWindow:)`: the window IS in `SCShareableContent` (`onScreen: true`, `active: true`), and the capture fails with `SCStreamErrorDomain` -3811, "Failed to start stream due to audio/video capture failure" |
| `ba9f4cb` | 78394, same bounds | same | same -3811 |

So there are **no images, no image sizes, no base-vs-base dynamic boxes, no
differing boxes and no capture verdict.** The calibration the spec requires
(two base captures seconds apart, non-empty diff) could not start. **The
capture stays owed** (spec, "Owed to the integration step"), by the same method,
on an unlocked session; the scripts are described above and rebuilt in minutes.
Harness note: `swift <file>` could not JIT a script importing AppKit here
("Symbols not found: `_OBJC_CLASS_$_NSAppearance`, `_OBJC_CLASS_$_NSScreen`"),
so each script was compiled with `swiftc -O` and run as a binary.

**A capture was never the evidence for the Space swap.** E18,
`theSpaceKeyBindingSwapsTheThemeThroughTheFakePlatform`, reads the swap as
pixels through the fake platform (`EV-P`, lane 2's mutations); it passed in this
lane's unfiltered run below.

#### A stand-in, and what it is not

What a locked session still allows is rendering offscreen. In the `base` and
`lane3` scratch worktrees only (never committed), a generated test file
`EV4DemoStandIn.swift` holds the demo's `main.swift` up to `runDemo()` —
`Increment`/`Decrement` renamed `EV4Demo…` (they collide with test fixtures) and
the top-level globals marked `nonisolated(unsafe)` (Swift 6 mode in the test
target) — plus one test that renders `demoContent()` through a real `Window`
over `FakePlatformWindow` (`makeFakeWindow`, 1024×1024, scale 1,
`startsDisplayLink: true`), under `Appearance.light` and `.dark`: one draw,
PNG from `fakeSurface.readPixels()`; then three `simulateTick` + draw, PNG
again. The two generated files were `cmp`-identical (the demo differs between
the builds only in `runDemo()`'s nine `KeyBinding` spellings, `EV-N`, which the
cut excludes). Both runs printed `theme=light` / `theme=dark` and
`framesDrawn=1` (the ticks drew nothing: nothing was dirty).

The comparison tool (`ev4/regiondiff`, compiled Swift) decodes two PNGs into
RGBA8 sRGB, requires equal dimensions, bins differing pixels into 8×8 cells,
merges 8-connected cells and prints each component's pixel bounds; given a box
file it reports whether every differing box lies inside one.

| comparison | sizes | differing pixels | boxes |
|---|---|---|---|
| **control, must differ everywhere:** base light-f0 vs base dark-f0 | 1024×1024 both | 1 048 576 | `0 0 1024 1024` |
| base dark-f0 vs base dark-f3 (the offscreen "dynamic regions") | 1024×1024 | **0** | none |
| **control, must differ locally:** `lane3` vs `lane3` with ONE demo sidebar `Box` (`EV4DemoStandIn.swift:459`) given `.theme(.light)`, dark-f0 | 1024×1024 | 1 748 | **`30 189 68 26`** — exactly that 68×26 box (the verifier's re-take, scoping one of the identical sibling `surfaceSecondary` boxes, read the same 1 748 pixels and 68×26 at y 261) |
| the same control, light-f0 (a light scope under a light theme) | 1024×1024 | 0 | none |
| **base vs lane 3**, light-f0, light-f3, dark-f0, dark-f3 | 1024×1024 each | **0, 0, 0, 0** | none; `cmp` byte-identical, all four |

**Reading.** With no scope written, lane 3's demo renders the same bytes as
`f64e58a`'s under both themes, and the instrument that says so reports a single
scoped box as a single 68×26 box. **What it does not cover:** the drawable,
`MetalLayerSurface`, the display's colour space (divergence 1), the real
920×560 window's layout, AppKit's appearance delivery, and anything time- or
scroll-dependent (the offscreen base-vs-base diff is empty because the fake
clock is deterministic, so the spec's "non-empty dynamic regions" calibration
has no offscreen counterpart; the two disagreeing controls stand in for it).
It is recorded as a stand-in, not as `EV-P`'s capture.

#### The merge re-measure (`EV-W`)

Heads: `feat/environment` `ba9f4cb`, `feat/ax-bridge` **`dbfa314`**,
`feat/modifier-composition` **`6d0ea97`**; merge base `f64e58a` for both pairs.
**Both tracks have moved past what `EV-W` described** (it was re-taken at
`53d3bf6` / `ec65da6`): the bridge has built its lane 2 (`b7474f9`, `7dfdc6d`,
`dbfa314`: the AppKit bridge; its spec header still reads "lane 1
implemented"), and the composition track has built its lane 2 (`e9248c3`,
`5fe5a30`, `49270c7`, recorded `c52f782`/`6d0ea97`: `ModifiedElement`,
`FrameModifier.swift` deleted; its lane 3 "not started"). Both specs were
re-read at those heads (`git show`, read-only), and `EV-W` was amended.

**`git merge-tree --write-tree --name-only feat/environment feat/ax-bridge`**:
tree `198b02197df0af59f23ccbae896a5c29fe90f6e4`, exit 1.

- **Conflicting:** `Sources/MetalUI/ElementGroup.swift` (one hunk: lane 2's
  `StateBinder.bind(self, in: pass.frame, id:)` against the bridge's old-spelling
  bind plus its `AB-O` `display: none` block), **`Sources/MetalUI/Frame.swift`
  (two hunks, both inside `registerHandlers`: NEW since the third pass)**, and
  `Sources/MetalUI/Window.swift` (one hunk: `frame.rootEnvironment =
  environment` against `collectsAccessibility: accessibility.isActive`).
- **`Frame.swift`'s hunks.** (1) Lane 3's `let enabled = environmentTop.isEnabled`
  and gated `focusRegistry.register`, against the bridge's 3-argument body
  becoming a forward, the 5-argument signature, and an ungated
  `focusRegistry.register`. (2) Lane 3's doc paragraph on the declared node's
  `.disabled` trait, against the bridge's `AB-C` doc paragraph, both just
  above `if !handlers.axNode.isEmpty`.
- **Auto-merged** (touched by both, no conflict): `Sources/MetalUI/Passes.swift`;
  and in `Frame.swift` everything outside the two hunks — including lane 3's
  gated `$focus` write, its `if enabled, hitTestingDisabledDepth == 0, …`
  hitbox gate, its `if !enabled { node.traits.insert(.disabled) }`, **and the
  bridge's `isEnabled: true` record literal**, which lands unconflicted in the
  merged 5-argument body. `Frame.render`'s root edits (lane 2b's bind and
  `isRendering`, the bridge's `AB-AD` hidden-root `prepaint`) also auto-merge.

**Is item 4 loud now? No — a textual conflict there does not make it loud.**
By reading the merged file (none of these resolutions was built): resolving
hunk 1 by taking the bridge's side wholesale leaves `enabled` undeclared for the
three auto-merged uses (a compile error, loud); taking the environment's side
wholesale deletes the 5-argument signature, so the auto-merged record code's
`accessibleText` and `synthesizesAccessibility` are undeclared and
`PrepaintPass.registerHandlers(_:at:id:accessibleText:synthesizesAccessibility:)`
(`dbfa314:Sources/MetalUI/Passes.swift:439-443`) calls a method that is gone (a
compile error, loud); a resolution that declares `enabled` but leaves
`focusRegistry.register` ungated is lane 3's measured "focus registration
ungated" mutation, 13 issues in 8 tests, D5 among them (`EV-F`'s Mutations
line; loud). **Every resolution that compiles still keeps
`isEnabled: true`**, and no test on either branch reads a collecting frame's
record of a disabled element. Item 4 stays SILENT.

Two facts corrected by this reading: at `53d3bf6` and at `dbfa314`, **no
element calls the 5-argument overload directly** — `Text.swift:304` and
`NativeTappable.swift:35` call the 3-argument one; only `PrepaintPass`'s
internal overload forwards to it, with no `Sources/` caller. `EV-W` said `Text`
and `OnTapModifier` "call directly"; that is the bridge's lane 3 design (`AB-F`,
`AB-Y`), not built. And the bridge's `AB-Z` merge contract
(`dbfa314:docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md:967-1066`,
rewritten against this track's `e9afded`) still registers **a blocker hitbox
under the derived id `$disabled`** — withdrawn by this track's third pass
(`EV-E`) and absent from lane 3's code — and names its joint test
`aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`
with **three** arms (clickable only, focusable only, adjustable only) and a
mutation "register the blocker under `id` with the enabled `handlers`". `EV-W`
named `aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`
with two. `EV-W` item 4 now adopts the bridge's name and three arms, with the
mutation list reconciled to lane 3's no-hitbox gate.

**`git merge-tree --write-tree --name-only feat/environment feat/modifier-composition`**:
tree `b970fff7ff25ca7bad706e0b629c37f65ea35f06`, exit 0, **no conflict**.
Touched by both and auto-merged: `Sources/MetalUI/ElementGroup.swift` (the
composition track's two `LayerBase` requirements; lane 2's three bind calls) and
`Sources/MetalUIDemo/main.swift` (`EV-N`'s nine `KeyBinding` spellings; the
composition track's doc/type lines).

**The clean composition merge was built and run**, because only a build can
say whether item 3 is loud. `git commit-tree b970fff -p ba9f4cb -p 6d0ea97`
made the scratch commit `481c0e9` (no ref points at it), checked out detached
in `ev4/merge-mc`:

- `swift build --build-system native --build-tests`: "Build complete!", 0
  `error:`.
- `swift test --no-parallel --build-system native`: **`Test run with 1152 tests
  in 1 suite passed after 29.410 seconds`**, 0 `error:`, 0 `warning:`. 1152 =
  1084 + 49 (this track) + 19 (composition, 1103 − 1084): nothing lost.
- Guards by per-file `grep -c canTypecheck`: 19 + 10 + 6 + 5 + 2 (`UnitSafetyTests`
  3 hits, one a comment) + 3 + 8 + 2 (`ModifiedElementCompileGuards`) = **55**.
- **`registerHandlers` callers** (`grep -rn "registerHandlers(" Sources`, code
  lines): `Box.swift:99`, `Stack.swift:123`, `Text.swift:304`,
  `ModifiedElement.swift:211`, `NativeTappable.swift:35` — still five, with
  `ModifiedElement` in `FrameModifier`'s place. `Frame.swift:733`'s lane 3 doc
  still names `FrameModifier` on the merged tree (stale at merge; integration
  relabels).
- **Mutation, one run, full suite:** `ModifiedElement.prepaintLayer` registers
  each layer under a pushed copy of the environment with `isEnabled = true`
  (a per-site bypass of the central gate). **`Test run with 1152 tests in 1
  suite failed after 29.233 seconds with 2 issues`**, both
  `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`
  `DisabledTests.swift:298` `(disabled → 1) == 0`, arms **"padding-frame"** and
  **"inside"**; the after arm and every other test passed. Restored with
  `git checkout -- Sources`; `git status --short` empty.

So on the merged tree D2's two `.frame`-spelled disabled arms run through
`ModifiedElement`, unchanged, and a site there that skipped the gate is caught
by a test that exists without anyone writing it: **item 3 is loud, measured.**
This is also the first measured per-site reading of D2's arm list (lane 3 could
only move the central gate).

Also read at `6d0ea97`: the composition spec's environment collisions were
re-written against `f4dcad8` (`MC-Q` finding 5) and agree with `EV-W` items 1
and 2 (`bind(_:in:id:)`; E11 is the layout-slot test; its invented test
withdrawn). It adds one owed item `EV-W` lacked: **`EnvironmentScope` arms in
`everyModifierWrapperDelegatesEachPhaseExactlyOnce`**, legacy and proposal,
each `[1, 1, 1]`, mutation "the typed entry calls
`content.requestProposalGroupLayout` twice". It also names this record's
lines 258-259 ("two `StateBinder.bind` call sites (`MC-H`)") as stale:
`8cdb25e`'s shared helper superseded them, and the composition track now adds
**no** bind call site. That correction is recorded here rather than by
rewriting the second-pass entry.

**`feat/ax-bridge` moved during this lane**, to `b9e258e` ("docs(ax-bridge):
record lane 2 …"): docs only (`git diff --stat dbfa314 b9e258e` touches its
record, decisions doc and spec, no `Sources/` or `Tests/`), its spec header now
reads "lanes 1 and 2 implemented", and no merge-contract or disabled-gate line
changed. _(Narrowed after verification: this said no line mentioning
`isEnabled` changed, which is false taken literally. `git diff dbfa314 b9e258e`
adds the row `| L05 | ignore isEnabled | rolesLabelsValuesAndTraitsMapOneToOne |`
to the bridge's record, `docs/record/12-accessibility-bridge.md:147`: the
bridge's own translator mutation, unrelated to `EV-W`.)_ `git merge-tree` against it:
tree `df6a60c…`, exit 1, the same three conflicting files and `Passes.swift`
auto-merged. The reading above holds at `b9e258e`.

#### Counts, re-read

- `swift build --build-system native --build-tests`, then
  `swift test --no-parallel --build-system native` in this worktree, unfiltered:
  **`Test run with 1133 tests in 1 suite passed after 28.035 seconds`**, 0
  `error:`, 0 `warning:`. No SwiftPM deprecation line was printed in this run's
  log.
- Guards **53** (`PhaseSeparationTests` 19, `ErasureCompileGuards` 10,
  `ProposalLayoutCompileGuards` 6, `ElementGroupTrapTests` 5, `UnitSafetyTests`
  3 hits = 2, `AXNodeTests` 3, `EnvironmentCompileGuards` 8);
  `.build/arm64-apple-macosx/debug/Modules` exists. No guard added.
- Goldens **97**; `git diff --stat f64e58a -- '*.json'` and
  `-- Sources/MetalUILayout` both empty.

#### Deferred, or not done by this lane

- **The release-window capture (`EV-P`)**, on an unlocked session: owed to the
  integration step, with the composition track's identical owed capture
  (`MC-J`). The offscreen stand-in above does not discharge it.
- The joint AX test, the merged 5-argument gate and the E11/E22/E23 ports
  (`EV-W` items 1 and 4): the integration step, as before.
- CLAUDE.md, counts and divergences: the integration step; CLAUDE.md was not
  edited.

---

### Verification of lanes 2b, 3 and 4 (2026-09-15)

Each lane after lane 2 was checked by an independent verifier agent working in
this worktree after the implementer had finished. Every verifier re-ran the
unfiltered suite under both build systems, re-took the red run by restoring the
red commit's sources, re-counted goldens and guards, and ran mutations of its
own choosing, including some the implementer had not run. **All three verdicts:
ok, goldens unchanged.** Each left the worktree clean (`git status --short`
empty), with scratch files only in its session scratchpad.

#### Lane 2b, verified at `087c405`

- **Suite.** 1118 passed under `--build-system native` and under the default
  system, 0 `error:`, 0 `warning:`; only the two gated tests skipped; G6
  printed `passed`. 97 goldens, `git diff f64e58a HEAD -- '*.json'` empty. 53
  guards.
- **Red re-take.** Sources of `d271a64` with HEAD's tests (identical between
  the two): **1118 tests, 9 issues**, at `EnvironmentTests.swift:834`, `:835`,
  `:848` and `EnvironmentTrapTests.swift:69`, `:74`, `:77`, `:82`, `:85`, `:90`
  — the implementer's list exactly. (Those `EnvironmentTests` lines are at
  `d271a64`; lane 3's in-place E5 arm has since moved E24 to `:870`.)
- **Probes re-run:** `swiftui-environment-pixel-length.swift` reproduced V0–V2
  and X0–X3 (bare locale '', the X2 reset gives ''), and
  `swiftui-disabled-ancestor-and-order.swift` reproduced N0–N4 and O0–O6
  (O6 probe=0).
- **Compile claims re-checked** with `swiftc -typecheck` against the native
  modules: `Box().theme(.dark).padding(4)` and `.theme(.dark).onClick {}` are
  rejected; `Box().padding(4).theme(.dark)` and
  `Box().theme(.dark).frame(...).background(.surface)` compile; `Box()` is the
  positive control.

| mutation | reddened |
|---|---|
| `EV-Z` (a): `Frame.rootEnvironment`'s precondition neutralised (`true \|\| !isRendering`) | T1 `aRootEnvironmentWriteDuringARenderTraps`, `:69`, `:74`, `:77`, `:82`, `:85`, `:90` (6) |
| `EV-Z` (c): `isRendering = false` just before `element.paint` | T1's paint arm only, `:85`, `:90` |
| `EV-Z`, the verifier's variant: the closing `isRendering = false` deleted | T2 `aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap` `:139` |
| `EV-Y` (a): `init` sets `locale = Locale.current` | E24 `:834`, `:835`, `:848` |
| `EV-Y` (b): `windowDefault()` does not stamp `Locale.current` | E24 `:845`, `:847`; E14 `theWindowsEnvironmentReachesTheFrameAndASetRepaints` `:797`, `:802` |
| G6, the verifier's: `transformEnvironment` made internal | G6 `EnvironmentCompileGuards.swift:285` ("'transformEnvironment' is inaccessible"), so the guard runs |
| G6: `dynamicTypeSize` given `internal(set)` | G6 `:285` (key-path conversion error and setter-inaccessible error in the fixture) |
| `EV-B` / E4(b): `cursor += 1` before forwarding | E4 `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex` `:278` ×3; `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState` `:373`; E22 `aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex` `:422` ×3 (7) |
| `EV-B` / E5: forward under an id keyed by `String(describing: values)` | E5 `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` `:349`; E23 `aProposalStateCounterKeepsItsCountAcrossAChangingScope` `:493`; E4 `:278` ×2; E22 `:422` ×2; `:373` (7) |
| `EV-X`, respelled hoist: `FrameModifier.paint` fills inside its content scope's values | E12 `:650`, the 14pt slot only |
| `EV-X` hoist as the spec wrote it (an `EnvironmentScope.frame` overload) | **nothing**, as the lane recorded: the solver's fallback, not a blind arm |

**Two minor issues**, both applied by this record commit:

1. **E24 hard-fails, rather than skipping, on a machine whose current locale is
   the root locale**: its `try #require(Locale.current != Locale(identifier: ""))`
   is a failure when it does not hold. That is a CI hazard, recorded under
   `EV-Y` and in "For the integrator" below. The test was not changed.
2. **`EnvironmentScope`'s doc said `.theme(.dark).padding(4)` does not
   compile.** That holds only over legacy content. The rejection names the
   proposal `.padding(_ insets:)` (`NativeModifiedContent.swift:181`, which
   requires `Content: ProposalElementGroup`), so over proposal content the
   spelling compiles, and nothing says whether that padding sits inside or
   outside the scope. The doc now says "over legacy content"; `EV-X` gains the
   proposal-path padding and flexible frame as unmeasured and unpinned.

#### Lane 3, verified at `ba9f4cb`

- **Suite.** 1133 passed under `--build-system native` after touching every
  `Sources/MetalUI` file and the three lane-3 test files so they recompiled,
  and 1133 under the default system; 0 `error:`, 0 `warning:`; only the two
  gated tests skipped. 53 guards (lane 3 extended G6 and added none). 97
  goldens, unchanged.
- **Red re-take.** `Frame.swift` restored from `2de4eef`: **1133 tests, 41
  issues**, the implementer's list line for line (D2 `:298` ×11, E5 `:378`,
  `:383`, `:387`, D4 `:245`, …). D1 and G6 stayed green.

| mutation | reddened |
|---|---|
| `EV-E` (c): `enabled` deleted from the hitbox gate | D2 `:298` ×11 (after arm `:367` green); D3 `:417`, `:429`; D15 `:814`, `:815`, `:816`; D16 `:863`, `:864`, `:892`, `:893`; D4 `:245`; D11 `:682`, `:687`; D14 `:776`; E5 `:378`, `:383`, `:387` |
| `EV-F`: focus registered for every element | D5 `:471`, `:472`; D6 `:499`, `:503`; D7 `:556`, `:557`; D8 `:608`, `:609`; D9 `:653`; D11 `:680`, `:688`; D13 `:717`; D14 `:777` |
| `EV-F`: the `$focus` slot written for every element | D13 `:739` only |
| `EV-E` / D12: the `.disabled` trait insert deleted | D12 `:925` only |
| `EV-D` (a): `.disabled` as a plain write | D1 `:213` only |
| `EV-F`: a disabled element keeps only its `onKey` | D8 `:608`, `:609` only |
| `EV-F`: keeps only its `actions` | D7 `:556`, `:557` only |
| `EV-F`: keeps only its `keyContext` | D9 `:653` only |
| `EV-E` (b) / `EV-T`: a blocker with empty `Handlers()` under the element's own id | D15 `:814`; D3 `:417`, `:429`; D16 `:863`, `:864`, `:892`, `:893` |
| `EV-E` (a): a blocker under `child(of: id, name: "$disabled")` | D3 `:417`, `:429`; D16 `:892` |
| D14: `PrepaintPass.deferred` runs its body under the root environment | D14 `:776`, `:777` only |
| `EV-X`, respelled hoist: `FrameModifier.prepaint` registers inside its content scope's values | D2 `:367`, the after arm only |
| `EV-X` as the spec wrote it (the overload), checked with `swiftc -typecheck` against the mutated modules | nothing; **cause now measured** (below) |
| G6: `disabled(_:)` made internal | G6 `:287` ("'disabled' is inaccessible"), so the guard runs |
| **the verifier's own D6-separating mutation** (below) | **D6 `:499`, `:503` only** — D5, D11, D13, D14 green |

**The refuted "cannot".** Lane 3's record and `EV-F` said no mutation could
separate D6 from D5, because keeping focus the SwiftUI way (probe K2) "needs a
previous-frame focus signal `Frame` does not have". Nobody had measured that
(practices shape 14). **`Window.lastFocusRegistry` already holds the previous
frame's registry.** The verifier handed it to `Frame` before `renderRoot`, had
`registerHandlers` record the ids of disabled elements, and had `resolveFocus`
keep focus for an id that is disabled now and was focusable in that registry —
five lines across `Frame.swift` and `Window.swift`. The suite read **1133
tests, 2 issues, both in `aFocusedElementThatBecomesDisabledLosesFocusAtOnce`**.
So D6 has D6-specific coverage, and removing the divergence is a small change.
It stays rejected because the brief requires `.disabled` to suppress focus, not
for lack of a signal. Corrected in `EV-F` (why, cost, Mutations), in D6's doc
comment, in the spec's D6 row, and in lane 3's bullet above.

**The void overload's cause, measured.** Against the mutated native modules,
`Box().disabled(true).frame(width:height:).onClick {}` has type
`FrameModifier<EnvironmentScope<Box<EmptyGroup>>>`, while the same chain without
`.onClick` has type `EnvironmentScope<FrameModifier<Box<EmptyGroup>>>`. The
unmutated control gives `FrameModifier<EnvironmentScope<…>>` for both. The
solver falls back to `ElementGroup.frame` because `.onClick` exists only on
`StyledElement`. This replaces `EV-X`'s "not re-measured with `swiftc`".

#### Lane 4, verified at `19749c7`

- **Suite.** After `swift build --build-system native --build-tests`, the
  unfiltered native run printed `Test run with 1133 tests in 1 suite passed
  after 26.685 seconds`, and so did the default system; 0 `error:`, 0
  `warning:`. `git diff --stat ba9f4cb HEAD -- Sources Tests` is empty: lane 4
  was docs only. 97 goldens; `git diff --stat f64e58a -- '*.json'
  Sources/MetalUILayout` empty. 53 guards.
- **The composition merge**, re-made (merge-tree against `6d0ea97` exits 0;
  scratch commit `da8734c`): built, **1152 tests passed**, 55 guards — the
  lane's reading.
- **The bridge merge** against `b9e258e` exits 1, with conflicts in
  `ElementGroup.swift`, `Frame.swift` and `Window.swift`, and `Passes.swift`
  auto-merged. A diff3 of `Frame.swift` shows exactly two hunks inside
  `registerHandlers`, with `isEnabled: true` outside both.
- **Source claims at `dbfa314`/`b9e258e`** hold: `Text.swift:304` and
  `NativeTappable.swift:35` call the 3-argument overload; `Passes.swift:439-443`
  is the only 5-argument forward; the bridge spec still has the `$disabled`
  blocker hitbox (`:997` at `dbfa314`) and the three-arm joint test name.
  `Frame.swift` at `6957464` has `isEnabled` at `:711`, `:736`, `:741`.
- **The session was still locked** at 04:55 PDT (`CGSSessionScreenIsLocked` 1,
  `CGDisplayIsAsleep` 1), so "not taken" is the machine's state. No input was
  sent and no `MetalUIDemo` process was left running.

| mutation | reddened |
|---|---|
| `EV-W` item 3, on a scratch composition merge (tree `c375647`): `ModifiedElement.prepaintLayer` registers under a copy of the environment with `isEnabled = true` | D2 `:298`, arms padding-frame and inside — the lane's reading |
| `EV-W` item 4's silence, **measured, not read**: scratch bridge merge (parents `19749c7`, `b9e258e`) resolved as `EV-W` prescribes (3-argument forward, gated 5-argument body, bind before `AB-O`, both `Window` statements) | **nothing, twice**: 1172 passed with the bridge's `isEnabled: true`, and 1172 with the correct `isEnabled: enabled` |
| instrument control for that run: `isEnabled: !enabled` | `declaredRolesLabelsValuesAndTraitsReachThePublishedNode` (`AccessibilityTreeTests.swift:295`, `text.isEnabled → false`) — so a test reads the field, and the silence is real |
| `EV-P` stand-in, re-taken at `f64e58a` and `19749c7` | base vs lane, light and dark: `cmp` identical; control base light vs base dark: 3 145 547 differing bytes |
| stand-in local control: one sidebar `surfaceSecondary` `Box` given `.theme(.light)` | dark: 1 748 differing pixels in a 68×26 box at (30, 261) (the lane recorded y 189, another of the identical sibling boxes); light: 0 |

**Three minor issues**, recorded here and in `EV-W`:

1. The capture is still undelivered (the machine's state, not the lane's work).
2. Lane 4's note on `b9e258e` said no line mentioning `isEnabled` changed; the
   bridge's docs diff adds its own L05 translator mutation row, which does.
   Narrowed in place above.
3. Heads moved after lane 4: `feat/modifier-composition` is at **`40566de`**
   (one commit, tests and docs), and merge-tree against it still exits 0 (tree
   `7153201`). Item 4's measured silence above is now in `EV-W`.

### Lane 4, re-run at `e709dc5` (2026-09-15, 08:14–08:40 PDT)

**Why a second run.** The first run could not take the capture, and both
parallel tracks built their lane 3 afterwards: `feat/ax-bridge` is at
**`aa5d055`** (`AB-F`, `AB-G`, `AB-T`, `AB-X`, `AB-Y`: `Text` and `OnTapModifier`
defaults, the accessibility modifiers, `List`), and `feat/modifier-composition`
is at **`6a0169c`** (`f9e2c62`: `ProposalNodeID` and the typed
`requestProposalGroupLayout` requirement, `MC-G`/`MC-H`; its spec header reads
"lanes 1, 2 and 3 done"). So `EV-W`'s two future items are no longer future, and
both were measured on built merges rather than read.

**Where.** This worktree at `e709dc5`; `git diff ba9f4cb e709dc5 -- Sources Tests`
touches two doc comments only (the verifiers' `EnvironmentScope` and D6
comments), so the source is lane 3's. No `Sources/` or `Tests/` file in this
worktree changed. Scratch worktrees, all detached, under this session's
scratchpad `ev4r/`: `mc` and `ab` (merges started from `e709dc5`, never
committed), `mchead` at `6a0169c` and `abhead` at `aa5d055` (test lists only).
All four were removed at the end of the run. No other agent was live in this
worktree.

#### The window capture (`EV-P`): NOT TAKEN, again

At 08:14 and again at 08:35 PDT the session script (`ev4/session`) read
`CGSSessionScreenIsLocked` 1, `CGDisplayIsAsleep(main)` 1,
`CGPreflightScreenCaptureAccess` true, **appearance Dark**, one 2056×1329 pt
screen at scale 2. `swift build -c release --product MetalUIDemo` at `e709dc5`
completed ("complete! (4.98s)", incremental). `ev4/capture.sh` launched
`swift run -c release MetalUIDemo`, found window **86152** (614, 259) 828×533,
onscreen, "MetalUI — Milestones 1 to 3", and got `could not create image from
window` (exit 1) and ScreenCaptureKit `-3811` ("Failed to start stream due to
audio/video capture failure"). `pgrep -x MetalUIDemo` was empty afterwards. No
input was sent and nothing was done to wake the session. The base build was
not rebuilt, because a capture of the lane's build was already impossible.
**Still no images, sizes, dynamic boxes, differing boxes or verdict.** The
offscreen stand-in above is unchanged in what it covers: no rendered source has
changed since it was taken. E18 passed in this run's unfiltered suite (below)
and remains the evidence for the Space-key swap.

#### Merge re-measure (`EV-W`) at `aa5d055` and `6a0169c`

Merge base `f64e58a` for both pairs.

| pair | `git merge-tree --write-tree --name-only` | conflicting | auto-merged (touched by both) |
|---|---|---|---|
| × `feat/ax-bridge` `aa5d055` | `df46e83…`*, exit 1 | `ElementGroup.swift` (1 hunk), `Frame.swift` (2 hunks in `registerHandlers`), `Window.swift` (1 hunk) | `Passes.swift`, `Sources/MetalUIDemo/main.swift` |
| × `feat/modifier-composition` `6a0169c` | `90ddf94…`*, exit 1 (**was exit 0**) | **`ElementGroup.swift` (1 hunk, new)** | `Passes.swift`, `Sources/MetalUIDemo/main.swift` |

\* _(Second verification round.)_ **These tree ids cannot be reproduced from
the commit ids alone.** With conflicts, the written tree contains the conflict
markers, and those markers carry the ref labels the command was given.
`git merge-tree --write-tree e709dc5 aa5d055` gives `ea59709…`, and the same
against `6a0169c` gives `0225719…`. The exit status, conflicting files and hunk
counts are identical to those above. The refs spelled in this run were not
recorded. The same applies to every exit-1 tree id in this file (`198b021…`,
`df6a60c…`, `6147237…`, `65dacb3…`). Only the exit status and the file and hunk
lists carry meaning. An exit-0 tree has no markers, so its id is reproducible,
and `b970fff…` was used as such by `commit-tree`.

**The composition merge, built.** The one hunk is `Element.requestGroupLayout`:
lane 2's `child(of:)` + `StateBinder.bind(self, in: pass.frame, id:)` +
`cursor += 1` against the composition track's
`GlobalElementID.enteringGroupMember(...)` call. Resolved to the helper side,
then built with `swift build --build-system native --build-tests`:

- **Loud, measured (items 1 and 2).** Three errors:
  `EnvironmentScope.swift:108:1: type 'EnvironmentScope<Content>' does not conform to protocol 'ProposalElementGroup'`;
  `GroupMember.swift:39:25: incorrect argument label in call (have '_:table:id:', expected '_:in:id:')`;
  `GroupMember.swift:39:53: cannot convert value of type 'StateTable' to expected argument type 'Frame'`.
- **`EV-W` item 1's typed entry, pasted verbatim, compiles.** With
  `GroupMember.swift:39` respelled `bind(element, in: pass.frame, id: id)`, the
  sources build, and the test target fails with exactly the fixtures `EV-W`
  predicted: `EnvironmentTests.swift:95:16` and `:480:16` "cannot convert
  return expression of type '(ProposalNodeID, ())' to return type
  '(LayoutNodeID, Void)'", and `:110:1` / `:498:1` "type 'NativeEnvRecorder'
  / 'NativeClickCounter' does not conform to protocol 'ProposalElementGroup'"
  — E11's recorder (also E22's) and E23's counter. **Loud.**
- **The port, in scratch only.** Both fixtures made `ProposalElement` with
  `requestProposalLayout(_:pass:) -> (ProposalNodeID, Void)`, the two empty
  marker extensions deleted, bodies unchanged: "Build complete!", then
  `swift test --no-parallel --build-system native`: **`Test run with 1162 tests
  in 1 suite passed after 31.467 seconds`**, 0 `error:`, 0 `warning:`. 1162 =
  1133 + 1113 − 1084, and the merged `swift test list` equals the union of this
  branch's list (1133) and `6a0169c`'s (1113), so nothing was lost. (`6a0169c`
  run alone: `Test run with 1113 tests … passed`; its record's "1116" at lane 3
  counts uncommitted files.) Guards: 19 + 10 + 6 + 5 + 2 (`UnitSafetyTests` 3
  hits) + 3 + 8 + 2 (`ModifiedElementCompileGuards`) + 6
  (`ProposalNodeIDCompileGuards`) = **61**. Goldens 97. `registerHandlers`
  callers: `Box`, `Stack`, `Text`, `ModifiedElement` `:211`, `NativeTappable`
  `:35` — five. `ModifiedElement.swift` is unchanged since `6d0ea97`, so item
  3's per-site measurement stands and was not re-run.
- **The silent half, measured on the ported merge.** Each mutation replaced the
  typed entry's body alone, full unfiltered suite, restored from a copy. Line
  numbers are the ported scratch file's (HEAD's minus 1 before `:110`, minus 2
  after `:498`).

| mutation of the typed `requestProposalGroupLayout` | result |
|---|---|
| M1: no `withEnvironment` (the bare forward `EV-W` warns of) | 1162, 2 issues: E11 `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` `:639` (`hstack` → `[0, 7, 7]`) and `:645` (`scroll` → `[0, 7, 7]`) — the layout slot only |
| M2: `cursor += 1` before forwarding (E4(b)) | 1162, 3 issues: E22 `aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex` `:459` ×3 (A, B, C ids moved) |
| M3: forward under `.child(of: parent, at: cursor, name: nil)` with a fresh cursor (E4(c)) | the same 3 issues, E22 `:459` ×3 |
| M4: content's parent keyed by `ElementID("value:" + String(describing: values))` (E5) | 1162, 3 issues: E22 `:459` ×2 (A, B; C is outside the scope) and E23 `aProposalStateCounterKeepsItsCountAcrossAChangingScope` `:529` ("a changed environment value reset the proposal state below it") |
| M5: the typed entry calls `content.requestProposalGroupLayout` twice (once on a copy with a scratch cursor) | **1162 passed — silent** |
| M5 again, after adding the two owed arms (`Row { CountingLeaf("x", log: log).environment(\.layoutDirection, .rightToLeft) }` and the `HStack`/`CountingProposalLeaf` twin) to `everyModifierWrapperDelegatesEachPhaseExactlyOnce` | unmutated: 1162 passed (the arms are green); mutated: 1162, 1 issue, `ModifierCompositionProofTests.swift:831`, "EnvironmentScope, proposal: [layout, prepaint, paint] = [2, 1, 1]" |

So on this merge **E11, E22 and E23, ported, see the typed entry**: M1 reddens
only E11's layout slot, M2/M3 only E22, M4 E22 and E23. **None of the legacy
E4/E5/E10 tests redden under these mutations**, as expected, since only the
typed entry was mutated. The twice-delegation bug is invisible until the
wrapper arms exist, and they catch it once they do. These mutations were run
by the person who pasted the entry, in scratch. **The integrator still owes
the port and these runs on the real merged tree.** What this run establishes
is that `EV-W`'s code and port instructions are sufficient at `6a0169c`.

**The bridge merge, built.** Resolved as `EV-W` item 4 prescribes:
`ElementGroup.swift` takes the bridge's hunk with the bind respelled
`StateBinder.bind(self, in: pass.frame, id: layout.id)` before its `AB-O`
block; `Window.swift` keeps `collectsAccessibility: accessibility.isActive` and
then `frame.rootEnvironment = environment`; `Frame.swift` hunk 1 is the
bridge's 3-argument forward and 5-argument signature followed by lane 3's
`let enabled` and gated `focusRegistry.register`. **Hunk 2 has changed since
`b9e258e`:** the bridge's side is now `AB-L`'s `var declaration =
handlers.axNode; declaration.logicalIndex = nil; if !declaration.isEmpty {
emitAXNode(handlers.axNode, …) }`, and the auto-merged record code reads
`declaration` (`hasSomethingToSay = !declaration.isEmpty ||
handlers.axNode.logicalIndex != nil || …`). Resolved as `if
!declaration.isEmpty { var node = handlers.axNode; if !enabled {
node.traits.insert(.disabled) }; emitAXNode(node, …) }`.

- **The four wholesale resolutions of the two `Frame.swift` hunks, each
  built (`swift build --build-system native`):** bridge/bridge: `cannot find
  'enabled' in scope` (`:840`, `:850`); environment/environment: `cannot find
  'declaration'`, `'synthesizesAccessibility'`, `'accessibleText'`;
  bridge/environment: `enabled` and `declaration`; environment/bridge:
  `synthesizesAccessibility`, `accessibleText`. **All loud.**
- **Correct resolution, record literal left as the bridge's `isEnabled: true`:**
  `Test run with 1189 tests in 1 suite passed after 30.680 seconds`, 0
  `error:`. **With `isEnabled: enabled`:** `Test run with 1189 tests in 1 suite
  passed after 32.723 seconds`, 0 `error:`, 0 `warning:`. **Instrument
  control, `isEnabled: !enabled`** (`[3/7] Compiling MetalUI Frame.swift`, so
  the edits were built): 1189, 1 issue,
  `declaredRolesLabelsValuesAndTraitsReachThePublishedNode`
  `AccessibilityTreeTests.swift:300`. **Item 4 is still SILENT at `aa5d055`**,
  measured. 1189 = 1133 + 1140 − 1084; the merged test list is the union of
  this branch's and `aa5d055`'s (1140). Guards 53, goldens 97.
- **Hunk 2 resolved to the bridge's side, with `enabled` declared** (so the
  trait insert is lost): 1189, 1 issue, `aDisabledElementsAXNodeCarriesTheDisabledTrait`
  (D12) `DisabledTests.swift:927`. Loud.
- **The gate placed in the 3-argument overload instead of the 5-argument body**
  (the 3-argument forward stores `environmentTop.isEnabled` in a scratch
  `mutantGate` and resets it to `true`; the 5-argument body reads
  `let enabled = mutantGate`): 1189, 3 issues —
  `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled`
  `DisabledTests.swift:298` ×2, arms **"text"** and **"proposal"** (the
  `Rectangle.onTap` arm), and `aDisabledClickTargetPassesTheClickToWhatIsUnderIt`
  `:429` (the `ZStack` of two `onTap` rectangles). **This hazard is now loud,
  measured**: at `aa5d055`, `Text.swift:311` and `NativeTappable.swift:38` call
  `PrepaintPass`'s internal 5-argument overload (`Passes.swift:439-442`), which
  calls `Frame`'s 5-argument method. Callers on the bridge merge are `Box`,
  `Stack` and `FrameModifier` (3-argument), plus `Text` and `NativeTappable`
  (5-argument).
- **The bridge's docs at `aa5d055`** are unchanged where this track cares.
  `git diff b9e258e aa5d055 -- docs/superpowers/specs/` is empty: the header
  still reads "lanes 1 and 2 implemented; lane 3 designed", and `AB-Z`'s merge
  contract still registers the `$disabled` blocker hitbox (`:1029`) with the
  three-arm joint test. The decisions-doc diff adds only the lane-2 verifier
  round's V-rows.

**Per item, now:**

- **0** met.
- **1 landed.** Its loud half is loud, measured: `EnvironmentScope` and the three
  fixtures do not compile. Its silent half is measured sufficient in scratch,
  and the integrator still owes it: M1–M4 redden the ported E11/E22/E23, and M5
  needs the two wrapper arms.
- **2** loud, measured: `GroupMember.swift:39` does not compile against the
  composition track, and `ElementGroup.swift` conflicts against both tracks.
- **3** loud; unchanged since `6d0ea97` and not re-run.
- **4** still SILENT, measured at `aa5d055`. Hunk 2 now carries `AB-L`'s
  `declaration`. The gate-in-the-3-argument-overload hazard is loud now that
  the direct 5-argument calls exist.
- **5** loud, unchanged (the same `Window.swift` hunk).
- **6** unchanged.

**Heads moved during this re-run** (read at 08:40): `feat/ax-bridge` to
**`15f0dd2`** (one commit, `AccessibilityDefaultsTests.swift` only) and
`feat/modifier-composition` to **`dbc2bc9`** (a doc comment in
`ProposalElementGroup.swift`, the new `ProposalGroupEntryTests.swift`, docs).
Neither touches a file this track edits or any line read above. `merge-tree`
at the new heads gives `6147237…` (exit 1: the same three files) and
`65dacb3…` (exit 1: `ElementGroup.swift`). The merged test totals above
(1162, 1189) will rise by those commits' tests; the merges were not rebuilt at
the new heads.

**Not measured:** the three-way merge of all three branches (`ModifiedElement`
on the bridge merge, `FrameModifier` on neither), and the two merges' own
`AB-O`/`ModifiedElement` interaction (the composition spec's item, not this
track's).

#### Counts, re-read (this worktree, `e709dc5`)

`swift build --build-system native --build-tests` ("Build complete!"), then
`swift test --no-parallel --build-system native`, unfiltered: **`Test run with
1133 tests in 1 suite passed after 28.048 seconds`**, 0 `error:`, 0 `warning:`,
no deprecation line in the log. Guards **53** (19, 10, 6, 5, 3 hits = 2, 3, 8);
`.build/arm64-apple-macosx/debug/Modules` exists. Goldens **97**; `git diff
--stat f64e58a -- '*.json' Sources/MetalUILayout` empty.

#### Deferred, or not done by this re-run

- **The release-window capture (`EV-P`)**: the session is still locked. It is
  owed to the integration step, by the same method.
- Items 1 and 4 on the real merged tree: the port, the typed entry, the two
  wrapper arms, the M1–M5 re-runs, the merged 5-argument gate, the joint AX
  test and its four mutations. This run's scratch merges were discarded.
- **A stale test doc comment, not edited (no `Tests/` edits in this lane):**
  D12's doc (`DisabledTests.swift:907`) still names the joint test
  `aDisabledClickableElementPublishesDisabledWithNoPressAndRefusesAPress`, which
  the first lane-4 run superseded with the bridge's
  `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`.
  The integrator relabels it when writing the joint test.

### Second verification round (2026-09-15), at `e709dc5` and `d18f2ce`

Three more independent verifiers took lanes 2b, 3 and 4 again after the first
round's record commit and lane 4's re-run. Each left the worktree clean.
Mutations were reverted with `git checkout`, and scratch tests and scratch
clones were deleted. **All three verdicts: ok, goldens unchanged.** Every
line number in this section is at the commit it names.

**Suite, all three.** First `swift build --build-system native`, then the
unfiltered `swift test --no-parallel --build-system native`. The three runs
printed `Test run with 1133 tests in 1 suite passed after 32.092 seconds`
(2b), `27.113 seconds` (3) and `26.997 seconds` (4, at `d18f2ce`), each with 0
`error:` and 0 `warning:`. The lane 2b and lane 3 verifiers also ran the
default build system, which printed 1133 passed with 0 `error:` and 0
`warning:`; its guards ran against the leftover native modules. The lane 4
verifier confirmed that `.build/…/debug/Modules` exists. Only `regenerateAllGoldens` and
`aListsWorkIsTheSameFor100kRowsAsFor500` were skipped; every lane 2b test
(G6, E12, E22, E23, E24, T1, T2) printed `passed`. Goldens: 97.
`git diff --stat f64e58a -- '*.json' Sources/MetalUILayout` is empty.
Guards by the per-file grep: 19 + 10 + 6 + 5 + (3 − 1) + 3 + 8 = **53**.

#### Lane 2b, at `e709dc5`

- **Red-first holds.** `git diff 8d0d3fe d271a64 -- Sources` is empty, and the
  green commit `de84219` touches no file under `Tests`. `EV-Y` (a) and `EV-Z`
  (a) together put the source back in its state before the implementation.
  They read 3 + 6 = 9 issues at the recorded lines (shifted by lane 3), which
  matches the red run of 1118 tests with 9 issues.
- **Probes re-run**, both exited 0, and the output matched the recorded
  headers line for line: `swiftui-environment-pixel-length.swift` (V0–V2,
  X0–X3) and `swiftui-disabled-ancestor-and-order.swift` (N, O).

| mutation | reddened |
|---|---|
| `EV-Y` (a): `init` sets `locale = Locale.current` | E24 `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne` `EnvironmentTests.swift:872`, `:873`, `:886` |
| `EV-Y` (b): `Window.environment` starts as `EnvironmentValues()`, unstamped | E24 `:883`, `:885`; E14 `theWindowsEnvironmentReachesTheFrameAndASetRepaints` `:835`, `:840` |
| `EV-Z` (a): the `rootEnvironment` precondition deleted | T1 `aRootEnvironmentWriteDuringARenderTraps` `EnvironmentTrapTests.swift:69`, `:74`, `:77`, `:82`, `:85`, `:90` |
| `EV-Z` (b): `precondition(environmentPushCount == 0)` instead of `!isRendering` | T2 `aRootEnvironmentWriteBeforeAndBetweenRendersDoesNotTrap` `:139`; T1, all six lines |
| `EV-Z` (c): `isRendering = false` just before `element.paint` | T1's paint arm only, `:85`, `:90` |
| `EV-Z`, verifier's: the precondition message changed to "root write while busy" | T1's stderr assertions only, `:74`, `:82`, `:90`. So the stderr check reads the message |
| `EV-Z`, verifier's: `isRendering` never cleared at the end of `render` | T2 `:139` |
| G6 (a): `.theme(_:)` internal | G6 `theEnvironmentsPublicWritersCompileFromOutsideTheModule` `EnvironmentCompileGuards.swift:287` ("'theme' is inaccessible") |
| G6 (b): `locale` `internal(set)` | G6 `:287`, with key-path and member-setter messages |
| G6 (c): `Window.environment` `internal(set)` | G6 `:287`, with three setter-inaccessible messages |
| G6, verifier's, seven runs filtered to G6, each alone: `transformEnvironment` internal; `dynamicTypeSize(_:)` internal; `isAccessibilitySize` internal; `layoutDirection`, `dynamicTypeSize` and `isEnabled` `internal(set)`; the custom-key subscript `internal(set)` | G6, in each of the seven, with the matching fixture diagnostic |
| E4(a): the scope wraps its content in `requestNativeOverlay` (proposal) or `requestNode` (legacy) | E4 `anEnvironmentScopeContributesNoLayoutNodeAndConsumesNoIndex` `:275`; E22 `aScopeOverProposalContentContributesNoNodeAndConsumesNoIndex` `:456` |
| E4(b): `cursor += 1` before forwarding | E4 `:279` ×3; `anEnvironmentScopeOverAComponentKeepsItsIdentityAndState` `:411`; E22 `:460` ×3 |
| E5: content forwarded under a child id named `"value:" + String(describing: values)` | E23 `aProposalStateCounterKeepsItsCountAcrossAChangingScope` `:531`; E5 `changingADisabledOrEnvironmentValueKeepsTheStateBelowTheWriter` `:357`, `:374`, `:378`; E4 `:279` ×2; E22 `:460` ×2; `:411`; D6 `aFocusedElementThatBecomesDisabledLosesFocusAtOnce` `DisabledTests.swift:501`, `:505` |
| `EV-X`, respelled hoist: `FrameModifier` registers and fills inside its content scope's stored values | E12 `aScopedThemeRepaintsOnlyItsSubtreeAndDeferredKeepsItsDeclaringScope` `:688` (the 14pt frame layer only); D2 `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` `DisabledTests.swift:367` (the after arm) |
| **`EV-Y` m1, verifier's: `Frame.init` roots at `EnvironmentValues.windowDefault()`** | **nothing, 1133 passed** |
| **`EV-Y` m2, verifier's: an unbound `@Environment` falls back to `EnvironmentValues.windowDefault()`** (`EnvironmentProperty.swift:48`) | **nothing, 1133 passed** |

**m1 and m2 are gaps in coverage, not void instruments, measured.** A
temporary test, since removed, rendered `EnvRecorder` in `frame()` and read
`Environment(\.locale).wrappedValue` unbound. It passed unmutated. Under m1 it
failed at `(log.paint["w"]?.locale.identifier → "en_US") == ""`, and under m2
at `(unbound.wrappedValue.identifier → "en_US") == ""`. `EV-Y` makes four
claims, and E24 pins only two of them: the bare value and the window's root.
The two it does not pin are that a windowless `Frame` reads '' and that an
unbound `@Environment` reads ''. Those two also appear in doc comments at
`Frame.swift:186-187` and `EnvironmentProperty.swift:21-22`. **Applied by this
commit:** `EV-Y`'s "Pinned by E24" is narrowed, and m1 and m2 are recorded
under it. No test or source was changed.

Two issues were already recorded: E24 hard-fails on a runner whose locale is
the root locale (`EV-Y`, CI), and E11, E22 and E23 exercise only the shared
entry (`EV-W` item 1).

#### Lane 3, at `e709dc5`

- **Red-first equivalent.** `let enabled = true` in `Frame.registerHandlers`
  keeps the `.disabled` shell and turns the gate off, which is the red
  commit's state. It read **1133 tests, 41 issues**, the implementer's red
  list line for line. D1 and G6 stayed green.
- **Probes re-run**, both exited 0 with no diff:
  `swiftui-disabled-ancestor-and-order.swift` (N, O) and
  `swiftui-disabled-interaction.swift` (P, K, R; 43 recorded output lines).

| mutation | reddened |
|---|---|
| `EV-D` (a): `.disabled` as a plain write (`$0 = !disabled`) | D1 `disabledComposesAsAnAndAndARawWriteOverridesIt` `:213` |
| `EV-D` (b): `.environment(\.isEnabled, v)` special-cased to an AND | D1 `:213`; D4 `theGateReadsTheEnvironmentValueNotTheModifier` `:235`; D7 `:549`, D8 `:600`, D9 `:646`, each at its `try #require` instrument |
| D4, counter gate (a `disabledDepth` raised only by `.disabled`; the gate reads `disabledDepth == 0`) | D4 `:235`, `:245`; D1 `:213`; D7 `:549`; D8 `:600`; D9 `:646` |
| `EV-E` (c): `enabled` deleted from the hitbox gate (27 issues) | D2 `:298` ×11 (box, column, row, stack, text, padding-frame, proposal, component, list-row, list, inside; after arm `:367` green); D3 `:417`, `:429`; D15 `:816`, `:817`, `:818`; D16 `:865`, `:866`, `:894`, `:895`; D4 `:245`; D11 `:684`, `:689`; D14 `:778`; E5 `EnvironmentTests.swift:378`, `:383`, `:387` |
| `EV-E` (b) / `EV-T`: a blocker with empty `Handlers()` under the element's own id (7 issues) | D15 `:816` (R1); D3 `:417`, `:429`; D16 `:865`, `:866`, `:894`, `:895` |
| `EV-E` (a): a blocker under `.child(of: id, at: 0, name: "$disabled")` | D3 `:417`, `:429`; D16 `:894` |
| `EV-F`: `focusRegistry.register` ungated (13 issues) | D5 `:471`, `:472`; D6 `:501`, `:505`; D7 `:558`, `:559`; D8 `:610`, `:611`; D9 `:655`; D11 `:682`, `:690`; D13 `:719`; D14 `:779` |
| `EV-F`: a disabled element keeps only `onKey` | D8 `:610`, `:611` |
| `EV-F`: keeps only `actions` | D7 `:558`, `:559` |
| `EV-F`: keeps only `keyContext` | D9 `:655` |
| `EV-F`: the `$focus` slot write ungated | D13 `:741` |
| `EV-F` / D6: the SwiftUI-aligned retention (five lines, `Window.lastFocusRegistry`) | D6 `:501`, `:505` only; D5, D11, D13 and D14 green |
| D12: the `.disabled` trait insert deleted | D12 `aDisabledElementsAXNodeCarriesTheDisabledTrait` `:927` |
| D12, control: the trait inserted unconditionally | D12 `:926`, the control arm |
| D14: `PrepaintPass.deferred` runs its body under `frame.rootEnvironment` | D14 `:778`, `:779` |
| `EV-X`, respelled hoist in `FrameModifier.prepaint` | D2 `:367`, the after arm only |
| G6: `disabled(_:)` internal | G6 `EnvironmentCompileGuards.swift:287` ("'disabled' is inaccessible") |

**New, and applied by this commit: a `.disabled(true)` `ScrollView` still
scrolls on the wheel.** `Frame.registerScrollRegion` calls `insertHitbox`
directly, outside `registerHandlers` and its gate. The verifier measured this
with a scratch test, since deleted:
`Row { Box { ScrollView(.vertical, elementID: "list") { Box 40×400 }.disabled(d) }.width(120).height(120) }`,
with one −37 wheel event at (20, 60). The stored `ScrollState` offset read
**37.0 for `d = false` and 37.0 for `d = true`**. Three other scratch arms fired
0 while their controls fired 1: a disabled ancestor of a `List` row's
`onClick`, a clickable child of a `ScrollView`, and a nested proposal `onTap`.
No test pins the scroll either way, and SwiftUI's answer is unmeasured. It is
now in `EV-E`'s "No wheel swallowed" bullet and `EV-Q`'s wheel row. No code was
changed.

**Line numbers moved.** `e709dc5` lengthened D6's doc comment, so every
`DisabledTests.swift` line after `:478` sits 2 lines lower at `e709dc5` than at
`2de4eef`/`6957464`/`ba9f4cb`. Lane 3's entry above, its first-round table and
`EV-D`/`EV-E`/`EV-F`/`EV-T`/`EV-X`'s Mutations lines cite the older lines, and
they are correct at the commits they name. For example, D6 `:499`/`:503` is
now `:501`/`:505`, D13 `:739` is now `:741`, and D12 `:925` is now `:927`.

#### Lane 4, at `d18f2ce`

This lane changed docs only, so it had no new guard to mutate and no red
commit to judge. The verifier rebuilt both merges in scratch clones (not git
worktrees) under its scratchpad, and removed them afterwards:

- **`e709dc5` × `aa5d055`**, resolved as `EV-W` item 4 says: **1189 passed**,
  0 `warning:`, 53 guards.
- **`e709dc5` × `6a0169c`**: `GroupMember` respelled, `EV-W` item 1's typed
  entry pasted verbatim, and the E11 and E23 fixtures ported. **1162 passed**,
  0 `warning:`, 61 guards.
- `git merge-tree` against all four heads (`aa5d055`, `15f0dd2`, `6a0169c`,
  `dbc2bc9`) reported exactly the recorded conflicts: bridge `ElementGroup` (1
  hunk), `Frame` (2) and `Window` (1); composition `ElementGroup` (1).
  `Passes.swift` and the demo auto-merged. Between the old and moved heads,
  only tests, docs and one comment differ. `git diff ba9f4cb e709dc5 --
  Sources Tests` is two doc comments.

| mutation | reddened |
|---|---|
| bridge merge: the record literal `isEnabled: true` → `isEnabled: enabled` | nothing, **as `EV-W` item 4 says: silent** |
| bridge merge, control: `isEnabled: !enabled` | `declaredRolesLabelsValuesAndTraitsReachThePublishedNode` `AccessibilityTreeTests.swift:300` |
| bridge merge: `Frame.swift` hunk 2 taken from the bridge (no `.disabled` insert), `enabled` still declared | D12 `DisabledTests.swift:927` |
| bridge merge: the gate moved to the 3-argument overload (via a `mutantGate`) | D2 `:298`, arms "text" and "proposal"; D3 `aDisabledClickTargetPassesTheClickToWhatIsUnderIt` `:429` |
| composition merge, typed entry: no `withEnvironment` push (M1) | E11 `proposalContentReadsTheEnvironmentThroughAScopeInEveryPhase` `EnvironmentTests.swift:639` (hstack `[0, 7, 7]`), `:645` (scroll `[0, 7, 7]`) |
| composition merge, verifier's M2 variant: `cursor += 1` **after** forwarding | E22 `:459` ×1 (C only). The recorded before-forwarding spelling gives ×3 |
| composition merge, verifier's M4 variant: value-keyed parent **with** a cursor bump | E22 `:459` ×3 (the recorded no-bump version gives ×2); E23 `:529` (`readings.last` 0 ≠ 2) |
| composition merge: typed entry forwards twice, no wrapper arms (M5) | nothing, as recorded |
| M5 after adding the two owed `EnvironmentScope` arms to `everyModifierWrapperDelegatesEachPhaseExactlyOnce` | `ModifierCompositionProofTests.swift:831`, read `[2, 1, 1]` |
| the two wrapper arms, no mutation (control) | nothing |
| composition merge, loud half: typed entry absent and `GroupMember.swift:39` still spelled `table:` | build: `EnvironmentScope.swift:108:1` does not conform to `ProposalElementGroup`; `GroupMember.swift:39:25` argument label, `:39:53` `StateTable` to `Frame`; with the entry pasted, the test build fails at `EnvironmentTests.swift:95:16`, `:480:16`, `:110:1` (`NativeEnvRecorder`), `:498:1` (`NativeClickCounter`) |

Line numbers on the composition merge are the ported scratch file's.

**Three minor issues.** First, the capture is still not taken (`EV-P`); the
spec already records that obligation. Second, the recorded exit-1 tree ids
cannot be reproduced; they now carry a footnote in the table above. Third,
D12's doc comment (`DisabledTests.swift:907`) still names the superseded joint
test. That comment is in `Tests/`, so it is left for the integrator.

### What stayed green

- **All 97 goldens, byte-identical to `f64e58a`**, and nothing under
  `Sources/MetalUILayout/`. `LayoutDirection` went to `MetalUICore`, not the
  engine.
- **The theme, as pixels.** `Frame(theme:)`, `PaintPass.theme`,
  `Window.theme` and the demo's Space key (`window.theme = …`, `main.swift:1128`)
  are unchanged in behaviour: E18 reads the swap as pixels through the fake
  platform, and the offscreen stand-in renders `demoContent()` byte-identical
  to `f64e58a` in light and dark.
- **Every pre-existing test.** 1084 at base, 1133 at HEAD, and no test was
  deleted. `KeymapTests` changed spelling only; the demo's nine `KeyBinding`
  lines compile, and the deprecated `Binding` alias still compiles with a
  deprecation that names `KeyBinding` (G5).
- **Identity.** A scope mints no id and consumes no index (E4, E22), so `@State`
  below a scope whose value changes is kept (E5, E23, the `Component` arm) —
  the `EV-B` mutations above redden exactly those.
- **The existing `$focus` hazard is exactly as reachable as before** (D13 pins
  it both ways), and `anElementThatStopsBeingFocusableLosesFocus` is untouched.

### Hazards in one place

Each is described above or in its ruling. **Measured** unless marked.

1. **A modifier written after a scope sits outside it** (`EV-X`, aligned with
   probe O2/O3/O6): `X().disabled(true).frame(…).onClick {}` **fires**. Over
   proposal content, `.padding`/flexible frame after a scope compile and their
   side of the scope is **unmeasured**.
2. **The obvious "hoist" instrument is void.** An `EnvironmentScope.frame`
   overload loses overload resolution whenever a `StyledElement` modifier
   follows; a test of the after-scope arm must use the respelled hoist.
3. **A disabled click target registers no hitbox**, so its click reaches an
   enabled ancestor (aligned, probe N) **and an enabled sibling under it**
   (divergence: SwiftUI's shape blocks, P2f/P2g).
4. **A focused element that becomes disabled loses focus and does not regain
   it on re-enable** (divergence, D6, probe K2). About five lines to remove.
5. **A disabled element is out of the keyboard entirely**, raw `onKey` and
   `keyContext` included (divergence, D8/D9, probe K6).
6. **`Window.environment` dirties on every write, a no-op included** —
   `EnvironmentValues` stores custom keys as `Any`, so there is no equality
   guard. A phase-time write every frame keeps the display link awake (by
   reading; the dirtying itself is pinned by E14).
7. **In-module writes to `theme` or `pixelLength` through `rootEnvironment` or
   `window.environment` are silently re-stamped** (`EV-U`); from outside the
   module they do not compile (G1−, G3), but `environment(\.self, …)` does and
   still cannot reset them (E19).
8. **`Frame.rootEnvironment` traps if set during `render`** (`EV-Z`, T1/T2).
9. **An `@Environment` never bound reads `EnvironmentValues()`'s defaults
   silently**: its locale is '' (`EV-Y`), not the user's. Inside `AnyElement`
   it is inert (E8). **Neither the unbound '' nor a windowless `Frame`'s '' is
   pinned.** The second round's mutations m1 and m2 each left 1133 tests
   passing, although both change behaviour.
10. **Two merge collisions are silent** (`EV-W` items 1 and 4): the typed
    proposal entry must push the scope (E11/E22/E23 stop compiling and must be
    ported and their mutations re-run), and the bridge's `isEnabled: true`
    compiles under every resolution — measured green both ways (1172 at
    `b9e258e`, 1189 at `aa5d055`). Item 1's twice-delegation mutant is green
    until the two `EnvironmentScope` wrapper arms are written (lane 4 re-run).
11. **E24 hard-fails on a root-locale runner** (its precondition is a
    `#require`, not a skip; by reading, not run on such a runner).
12. **Carried values with no consumer**: `layoutDirection` mirrors nothing
    (E17, pinned wrong on purpose), `locale` reaches no tokenizer or typesetter
    (E21; its mutation was void, so E21 shows inertness, not that a locale
    would move measurement), `dynamicTypeSize` changes no text (aligned on
    macOS, E16), `pixelLength` has no internal reader.
13. **The `Binding` alias must be deleted in the same change that adds a
    SwiftUI `Binding`** (task 10), or the two collide.
14. **A `.disabled` `ScrollView` still scrolls on the wheel.** Its scroll
    region is registered by `Frame.registerScrollRegion`, outside the gate.
    Measured (offset 37.0 disabled and enabled alike), unpinned, and SwiftUI's
    answer is unmeasured.
15. **`DisabledTests.swift` line numbers after `:478` are +2 at `e709dc5`**
    against every lane 3 citation, which was taken at `2de4eef`–`ba9f4cb`.
16. **Exit-1 `git merge-tree` tree ids in this file cannot be reproduced**:
    they depend on the ref labels in the conflict markers. Compare exit status
    and conflicting files instead.

### What remains open

- **The release-window capture** (`EV-P`), before/after, no input: not taken,
  session locked (04:35–04:55 and again 08:14–08:35 PDT). Owed with the
  composition track's `MC-J`.
- **`EV-W` items 1 and 4** on the merged tree: the typed-entry port with its
  re-run mutations and the two `EnvironmentScope` wrapper arms; the merged
  5-argument gate and the three-arm joint AX test with its four mutations.
- **Not delivered, from `EV-Q`:** `controlActiveState` and `controlSize` (probe
  C reads them; task 12); `displayScale` and a scope-writable `pixelLength`
  (two divergences); RTL mirroring (task 6); a `locale` consumer (none named);
  following the system's direction and locale while running (task 14); an
  appearance/colour-scheme value and a pre-paint theme (task 11); Reduce Motion
  (task 13); `@Environment` in `AnyElement` (task 8).
- **Unowned**: focus retention on disable, raw keys on a disabled ancestor, a
  disabled look, a hit shape separate from `onClick`, the key-handler order
  (SwiftUI runs the ancestor first, K5), `.padding` and handler modifiers
  directly on a legacy scope, and wheel scrolling under `.disabled` in SwiftUI
  (unmeasured: the probe's enabled control failed).
- **Unprobed in SwiftUI**: hover and pressed appearance under `.disabled`
  (`EV-T`'s hover half is MetalUI's choice).
- **Unpinned, measured**: `EV-Y`'s windowless-`Frame` locale '' and unbound
  `@Environment` locale '' (m1, m2 green), and a `.disabled` `ScrollView`
  scrolling on the wheel.

### For the integrator

Everything below is owed by the integration step; this track edited none of
the files named. Re-take every count on the merged tree — the figures here are
this branch's.

**1. Merge, and check what does not fail by itself.**

- **Precondition** (`EV-W` item 0): met at `6957464`.
- **Re-run `git merge-tree` at your own heads, and compare exit status and
  conflicting files, not tree ids.** An exit-1 tree id depends on the ref
  labels in the conflict markers, so the ids in this record cannot be
  reproduced (second round). Last read (lane 4 re-run, confirmed by the second
  round at all four heads):
  `feat/ax-bridge` `aa5d055`, then `15f0dd2` (exit 1: `ElementGroup.swift`, `Frame.swift` ×2
  hunks in `registerHandlers`, `Window.swift`; `Passes.swift` and the demo
  auto-merge); `feat/modifier-composition` `6a0169c`, then `dbc2bc9` (**exit 1**:
  `ElementGroup.swift`, `Element.requestGroupLayout`'s bind against
  `enteringGroupMember`; take the helper and respell `GroupMember.swift:39` as
  `StateBinder.bind(element, in: pass.frame, id: id)`).
- **`ElementGroup.swift`** (bridge): keep both — `StateBinder.bind(self, in:
  pass.frame, id: layout.id)` first, then the bridge's `AB-O` block (the
  bridge's hunk spells the bind `table:`; respell it). **`Window.swift`**:
  keep both statements (`collectsAccessibility:` in the `Frame(...)` expression;
  `frame.rootEnvironment = environment` after it). No `Frame.init` parameter
  from this track (`EV-W` item 5). `StateBinder.bind(_:in:id:)` has no default
  and no compatibility overload (`EV-W` item 2, loud).
- **`Frame.registerHandlers`** (`EV-W` item 4, **silent**): write the merged
  5-argument body exactly as `EV-W` gives it — the gate in the 5-argument
  implementation, the 3-argument overload a bare forward, no hitbox and no focus
  registration when disabled, the `$focus` write gated,
  `focusedElementProducedThisFrame` ungated, the declared node's `.disabled`
  trait, and **`isEnabled: enabled`** in the record, not the bridge's `true`.
  Measured: 1172 tests pass with either value at `b9e258e`, and 1189 at
  `aa5d055`, so nothing will tell you. Then
  write `aDisabledElementPublishesDisabledWithTheGatedActionsAndRefusesEveryRequest`
  (three arms: clickable only, focusable only, adjustable only; each with a
  control) and run its four mutations as `EV-W` lists them. Reconcile the
  bridge's `AB-Z`: its `$disabled` blocker hitbox, blocker mutation, `keyboard`
  copy, ungated `$focus` and `environment:` init parameter were all withdrawn
  here. **The bridge's lane 3 has landed (`aa5d055`)**: `Text` and
  `OnTapModifier` now reach the 5-argument method directly, and a gate placed
  in the 3-argument overload reddens D2's "text" and "proposal" arms and D3
  (measured, lane 4 re-run). Hunk 2 now carries `AB-L`'s `declaration`; keep
  it, and insert the trait on a copy of `handlers.axNode` inside
  `if !declaration.isEmpty` (dropping the insert reddens D12). Relabel D12's
  doc comment (`DisabledTests.swift:907`) to the bridge's joint-test name. The
  second round rebuilt this resolution at `aa5d055`: 1189 passed, 53 guards,
  `isEnabled: enabled` silent, `!enabled` reddens
  `AccessibilityTreeTests.swift:300`.
- **Modifier composition lane 3, LANDED at `6a0169c`** (`EV-W` item 1; the
  loud half and the sufficiency of what follows were measured on a scratch merge
  in the lane 4 re-run: 1162 passed after the port, M1–M4 redden E11/E22/E23,
  M5 needs the wrapper arms). The silent half:
  the typed `requestProposalGroupLayout` on `EnvironmentScope` calls
  `scopedValues(applying:)` once, pushes with `withEnvironment` around
  `content.requestProposalGroupLayout`, and forwards `parent` and `cursor`
  unchanged. Port E11, E22 and E23 to `ProposalElement` (E11 absorbs
  `aProposalContainerReadsTheEnvironmentDuringLayout`; do not add that name),
  then **re-run** E11(b), E4(b)/(c) and E5's value-keyed id against the typed
  entry and confirm they redden. Add the two `EnvironmentScope` arms to
  `everyModifierWrapperDelegatesEachPhaseExactlyOnce`, each `[1, 1, 1]`, with
  the mutation "the typed entry calls content twice". Measure, and pin, which
  side of a scope a proposal `.padding`/flexible frame written after it sits on
  (`EV-X`). The second round rebuilt this merge at `6a0169c` (1162 passed, 61
  guards). Its variants add two readings: `cursor += 1` **after** forwarding
  reddens E22 ×1, not ×3, and a value-keyed parent **with** a cursor bump
  reddens E22 ×3 and E23. Either spelling is an acceptable instrument.
- **Pin, or narrow, what `EV-Y` claims (second round).** Mutations m1
  (`Frame.init` roots at `windowDefault()`) and m2 (an unbound `@Environment`
  falls back to `windowDefault()`) each left the suite green, although both
  change behaviour. Choose one:
  - extend E24 with a windowless-`Frame` arm and an unbound-`@Environment`
    arm, both behind its existing `Locale.current != ''` `#require`, and re-run
    m1 and m2 red; or
  - keep `EV-Y`'s narrowed text (applied on this branch) and the two doc
    comments (`Frame.swift:186-187`, `EnvironmentProperty.swift:21-22`) as
    unpinned claims.
- **Decide the disabled `ScrollView` (second round).** `.disabled(true)` does
  not stop wheel scrolling, because `Frame.registerScrollRegion` inserts its
  hitbox outside the gate. This was measured and is unpinned, and SwiftUI's
  answer is unmeasured. Either pin it as it stands, with an enabled control,
  or gate the scroll region and pin that. Carry it into the inert table either
  way (below).
- **`FrameModifier` → `ModifiedElement`** (`EV-W` item 3, loud, measured):
  relabel `Frame.registerHandlers`' doc; `grep -rn "registerHandlers(" Sources`
  should still find five callers. D2's padding-frame and inside arms are the
  per-site check.
- **Take the release-window capture** (`EV-P`, with `MC-J`) on an unlocked
  session by lane 4's method: base `f64e58a` against the merged tree, no input,
  region comparison after a base-vs-base calibration.

**2. CLAUDE.md — rules only.**

- **"Where things are", the ruling-prefix table:** add `EV-` | environment
  (plan task 9) | lettered, `EV-A`…`EV-Z`, next is `EV-AA`. Name the spec,
  decisions doc and `docs/record/11-environment.md`.
- **A new Architecture paragraph, "Environment":**
  - `EnvironmentScope` is layout- and identity-transparent: no node, no cursor
    index, no id, so a changing value keeps the `@State` below it. Nearest
    writer wins; `.transformEnvironment` composes with the inherited value;
    nothing cascades.
  - A scope's transform runs **once per frame, in layout**; prepaint and paint
    re-push the stored result, so all three phases read identical values.
  - Every value is readable in every phase through `pass.environment`, so
    there is **no phase-only query and no new `PhaseSeparationTests` guard**.
    The exception is `theme`: `PaintPass.theme` only, unreachable through any
    public key path, `\.self` included (G1−).
  - `@Environment` is bound like `@State`, by reflection, per element per
    phase, to a snapshot; unbound it reads `EnvironmentValues()`'s defaults
    silently (locale ''); inside `AnyElement` it is inert. A type declaring it
    must be main-actor isolated (every `Element` and `Component` is).
  - `Window.environment` is the root. **Every write dirties, a no-op
    included** — write from input, never from a phase. `theme` and
    `pixelLength` are re-stamped from `Window.theme` and the surface scale, so
    a write to either through `window.environment` or `rootEnvironment` does
    nothing. `Frame.rootEnvironment` traps if set during `render` (`EV-Z`).
  - A `Frame` built without a window roots at `EnvironmentValues()` (locale
    ''); `Window` stamps `Locale.current`. Unpinned unless E24 is extended
    (above).
  - **A modifier written after a scope sits outside it** (`EV-X`):
    `.disabled(true).frame(…).onClick {}` fires. Over legacy content,
    `.padding` and handler modifiers do not compile directly on a scope; over
    proposal content `.padding` does, and its side is unmeasured.
  - A `Deferred` inside a scope keeps its declaring scope's values.
- **A paragraph on `.disabled`:**
  - `.disabled(d)` is `transformEnvironment(\.isEnabled) { $0 = $0 && !d }`;
    a raw `.environment(\.isEnabled, true)` overrides it, and the gate reads the
    value, not the modifier.
  - **One gate, in `Frame.registerHandlers`**: a disabled element registers
    **no hitbox** (so it is neither hovered nor pressed, and its click reaches
    an enabled ancestor or an enabled sibling under it), **nothing in the focus
    registry** (no `isFocusable`, `actions`, raw `onKey` or `keyContext`), no
    `$focus` slot, and its declared AX node gains `.disabled`. A click needs the
    target enabled at press and at release.
  - **Scroll regions are outside the gate**: a `.disabled` `ScrollView` still
    scrolls on the wheel (`Frame.registerScrollRegion`; measured, unpinned
    unless pinned at integration).
  - A site that registers handlers without that method is ungated with no
    diagnostic; `everyHandlerRegisteringSiteSuppressesItsClickWhenDisabled` is
    the per-site guard, and a new site gains an arm in the same change.
  - Focus is lost on disable and not restored on re-enable (divergence below).
- **Keymap:** `KeyBinding` is the keymap's type; `Binding` is a deprecated
  alias that plan task 10 deletes **in the change that introduces a SwiftUI
  `Binding`**.
- **Reserved names:** none added (the `$disabled` suffix was withdrawn).
- **Known divergences — add rows** (labels are the integrator's to assign; 20
  is the first never used):
  - `EV-F` (a): a focused element that becomes disabled loses focus at once and
    re-enabling does not restore it; SwiftUI keeps it (probe K2). Pinned by D6.
    Kept because disabled must suppress focus; `Window.lastFocusRegistry`
    would make retention about five lines.
  - `EV-F` (b): a disabled ancestor's raw `onKey` and `keyContext` are removed;
    SwiftUI runs a disabled parent's `.onKeyPress` (K6). Pinned by D8/D9.
  - `EV-E` sibling half: a disabled click target passes the click to an enabled
    sibling under it, where SwiftUI's shape blocks (P2f/P2g) — the same
    difference every non-clickable MetalUI overlay already has. Pinned by D3.
  - `EV-J`/`EV-U`: no `displayScale`; `pixelLength` is tied to the device, so no
    scope changes it and a `\.self` reset does not reset it (pixel-length X1/X2).
  - `EV-K`: `layoutDirection` is carried and no container mirrors (probe H).
    Pinned wrong on purpose by E17.
  - Key-handler order: SwiftUI runs an ancestor's `.onKeyPress` before the
    focused view's; MetalUI bubbles outward (K5). Pre-existing, now measured.
- **Declared but inert — add rows:** `layoutDirection` (no layout reads it);
  `locale` (no tokenizer, typesetter or formatter receives it);
  `dynamicTypeSize` (no text size moves; aligned with SwiftUI on macOS);
  `pixelLength` (no internal reader); `@Environment` inside `AnyElement`; an
  unbound `@Environment` (reads defaults silently); an in-module write to
  `theme`/`pixelLength` through `window.environment` or `rootEnvironment`
  (re-stamped); `.disabled` on a `ScrollView` (the wheel still scrolls; its
  scroll region bypasses the gate).
- **Build and test — guards:** the per-file guard list gains
  `MetalUITests/EnvironmentCompileGuards` (8 guards). **Counts on this branch:
  1133 tests, 97 goldens, 53 guards, 0 `error:`, 0 `warning:`** (both build
  systems); the composition merge measured 1152 / 55 at `6d0ea97` and 1162 / 61
  at `6a0169c` (after the scratch port), the bridge merge 1172 at `b9e258e` and
  1189 / 53 at `aa5d055`. The second verification round reproduced 1133 / 97 /
  53 at `e709dc5` and `d18f2ce`, and 1162 / 61 and 1189 / 53 on its own
  rebuilds of the two merges. Re-take on the merged tree.
- **When CI lands — add:** `aBareEnvironmentValuesHoldsTheRootLocaleAndAWindowStampsTheCurrentOne`
  (E24) **hard-fails on a runner whose current locale is the root locale**
  (unset `LANG`): its discriminating precondition is a `try #require`, not a
  skip. Make it an `.enabled(if:)` trait with a skip reason, or give the runner
  a locale. The track's device-dependent tests follow the surrounding
  convention, `try #require(MTLCreateSystemDefaultDevice())`, and none uses
  `makeFakeWindowOnDefaultDevice`; how either behaves on a displayless runner
  was not measured here.
- **Human verification table:** add a row — the release-window capture before
  and after this track, no input, **open** (session locked 2026-09-15). The
  Space-key swap itself is covered by E18 and needs no look.
- **Demo keys:** unchanged.

**3. The plan, task 9 — do NOT tick it.** Its own text asks for scoped values
covering "enabled state, layout direction, locale, dynamic type/scale, control
state and platform metrics", read/write modifiers with nearest-ancestor
precedence and no CSS cascade, and the `Binding` collision resolved.
Delivered: enabled state, layout direction (carried, unmirrored), locale
(carried, no consumer), dynamic type (`dynamicTypeSize`), platform metrics
(`pixelLength`), the modifiers and their precedence, no cascade, and
`KeyBinding`. **Not delivered: "control state" as a value apart from enabled
state** (the plan lists the two separately; `controlActiveState` and
`controlSize` are `EV-Q` items for task 12), **and "scale"** (`displayScale` is
not exposed, `EV-J`, a divergence). The brief's before/after window capture is
also untaken. Record task 9 as implemented with carried items (`EV-Q`, the
capture), and tick it only when control state and scale land or the plan's text
is amended to drop them. Under task 10, note that the `Binding` alias is
deleted in the change that adds `Binding`, and that wheel scrolling under
`.disabled` (SwiftUI unmeasured; MetalUI's `ScrollView` still scrolls) is
`EV-Q`'s task 10 item. Under task 12, note that focus
retention on disable, raw keys on a disabled ancestor and a disabled look are
unowned.

**4. README.md.** Line 82's demo keys stay true. If README lists the public
API or the keymap, spell `KeyBinding` (the `Binding` alias is deprecated), and
add one sentence: environment values are scoped with `.environment(_:_:)`,
`.transformEnvironment`, `.disabled`, `.dynamicTypeSize` and `.theme`, read with
`@Environment` or `pass.environment`, and rooted at `Window.environment`.

**5. `docs/record/README.md`.** Index `11-environment.md` as "plan task 9:
scoped environment, the disabled gate, `KeyBinding`; four lanes, two verifier
rounds, and the merge obligations".

---

## Integration (2026-09-15)

Merged on `integrate/tasks-3-9-12` with the other two tracks. What the merge
needed, the interaction it exposed (a hidden inner `ModifiedElement` layer no
longer suppressing accessibility, `AB-O`), the cross-track tests and their
mutations, and the offscreen pixel stand-in for the demo capture are in
record §13 (`13-integration-tasks-3-9-12.md`). Counts after integration:
1226 tests, 97 goldens, 61 guards.
