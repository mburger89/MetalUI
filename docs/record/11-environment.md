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
