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
    **this is unexplained**.
  - K3, an enabled keyboard shortcut: 1. K4, the same shortcut disabled: 0.

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
