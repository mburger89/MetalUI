# Record 204: the default cross-fade, `Animatable` and glass-morph probes (round 4 item R4-3 PR A)

Branch `feat/r4-3-default-crossfade`, from master `c28d5293`. Decisions: `docs/superpowers/2026-11-03-default-transition-decisions.md` (`XF-A`..`XF-E`). Human checks: none yet (the group `XF` belongs with PR B). Divergences: **none added or retired**; rows 98, 169, 828, 898 and 947 amended in place (208 live; next label 215). **No `Sources/` change.** PRs B to E (the default fade, 897, `Animatable`, `Component & Animatable`) are separate decisions made after this record.

**Nothing in the plan survived unread.** Every `[PREDICTED]` and `[RECOLLECTION]` of the plan was an arm; where the arm disagreed, the arm won (section 3).

## 0. The machine (lock state)

`docs/probes/appkit-screen-lock-state.swift`, run first, 2026-11-03 (macOS 27.2 26B123): `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 0`, `displayActive main: 1`, `preflightScreenCaptureAccess: false`, one screen (1920x1080, scale 1.0). **The session was locked with no Screen Recording permission, and the desktop was shared.** No arm reads window-server pixels. The bitmap arms use `NSHostingView.cacheDisplay` (AppKit's own drawing) and the layer arms read `host.layer`; `ImageRenderer` was used nowhere (its `R1` did not reproduce, section 6). Every probe file was run twice (compiled with `xcrun swiftc`, Apple Swift 6.4.2); the stable lines are identical, and the `~` lines of the new files are timing (stated per file in its header).

| file | run 1 / run 2 | identical outside |
|---|---|---|
| `swiftui-transactions-animation.swift` (controls) | 227 / 227 lines | byte-identical; equal to the recorded 227 lines |
| `swiftui-default-transition.swift` (new) | 441 / 441 | the `~` lines (RGB units, 0.01 s) |
| `swiftui-animatable.swift` (new) | identical stable lines | the `~` lines (call counts, slopes) |
| `swiftui-liquid-glass.swift --no-window` | 54 / 54 | GM1c's two glass-internal `AnimatableData` lines (component ORDER differs between runs) |
| `swiftui-lifecycle.swift` | 2980 / 3083 | AV6c `slide` lines and S1/S2 row lines (as in record 201) |

## 1. Controls reproduced (stop conditions 1 and 2 did not fire)

`C0` geometry `[0, 0, 200, 0]`; `X0` insert `+1`, remove `-1`; `W10` `-1` and `+1`; `X15` `+1`; `X15b` nothing (`swiftui-transactions-animation.swift`, same session, 227 lines twice); `T1` `disappear x` only after the 1.0 s spin (`swiftui-lifecycle.swift`); `XF0` re-takes `C0`, `C1`, `X0`, `W10`, `X15`, `X15b` through the animator-counting recorder and reads the same, with one animator for one view and two for an `if`/`else`. `XF3` and `XF6` read `+1`/`-1`; `XF4` reads **two** animators for a tuple.

## 2. What the probes showed

| arm | reading | consequence |
|---|---|---|
| `XF0` | recorder valid; if/else swap is two animators | `XF-A` 1 |
| `XF1` | the bitmap sees an animated opacity (control ramp G 240..91 over white) and the default and `.opacity` ramps in and out; `.identity` is immediate | instrument valid; stop 14 did not fire |
| `XF2` | the layer tree is readable (static 0.50, animated 0.33 at 0.4 s of 1.2 s, a removal ghost layer 0.67) | instrument valid |
| `XF3` | `X0` is the same in VStack, HStack, a root Group and a ZStack | stop 2 did not fire |
| `XF4`, `XF5`, `XF5b` | a tuple under an `if` is two animators; a mixed unit's annotated member animates its own, **the unannotated one still fades** | the plan's "mixed unit gets no default" is wrong |
| `XF6`, `XF6b` | a `ForEach` element fades `+-1`, plus sibling shifts | stop 2 did not fire |
| `XF7` | a changed `.id` is `-1` and `+1`; `onDisappear` late | residue "a changed `.id`" is SwiftUI's default too |
| `XF8` | **an `AnyView` swap records nothing**, with or without `.transition(.opacity)`; `if f { AnyView }` fades; `disappear A` before `appear B`, both early | stop 3 did not fire; 212 and `$erased` stand |
| `XF9` | first render, a `LazyVStack` and a `List` row under an animated `scrollTo`: nothing | stop 8 did not fire for the scroll |
| `XF10`, `XF2zb`, `XF2zc` | **the ghost is the first sublayer of its container's run**: below a sibling it was above, below the outer sibling it was not; annotated and unannotated alike; insertion in place | neither "on top" (MetalUI) nor "in place" (plan step 8); stop 9 |
| `XF11` | Reduce Motion: default `+1`/`-1` unchanged | |
| `T1u`, `A4u`, `T4u`, `T1e`, `T1e2` | an unannotated removal delays `onDisappear`; if/else keeps appear first and delays the old branch; re-insertion fires neither; empty content delays too | stop 4 did not fire; the `LC-H` parking applies |
| `GM1a`..`GM1f` | a same-id swap in a container records opacity `+-1` only, like a plain swap; different ids reach glass-internal values | 828: the recorder does not show a morph |
| `VT` | `View & Animatable` in SwiftUI's own spelling: Swift 5 compiles, **Swift 6 errors**; `nonisolated var animatableData` compiles; `Float` is not `Animatable`; `scaled(by:)` is public | `XF-C` 7 |
| `VA1`..`VA3` | custom Shape animates, no data snaps; trim's data is `P<S.AnimatableData, P<F, F>>` with fractions scaled by 128; wrapper forwarding it animates; trim of trim nests | row 947's text corrected |
| `VA4` | a retarget on one component is a new whole-pair animator | stop 10 did not fire |
| `VA5`, `VA7` | `View & Animatable` body at interpolated values, children proposed interpolated widths; `.equatable()` does not skip in flight | PR E stands |
| `VA6`, `VA6c` | position continuous; `a`'s slope 3.58 to 3.17 across the other component's retarget | velocity projection unsupported |
| `VA8` | keyframes over a custom `Animatable` compile and interpolate; a `Float` track does not compile | row 169's `Float` is a MetalUI extra |

## 3. Plan predictions refuted or confirmed

**Refuted:** (a) "a mixed unit gets no default" (`XF5`: the unannotated member fades); (b) "removal keeps its z-position" and design step 8 "in place" (`XF10`: bottom of the container's run); (c) the recollection that `XF1`'s bitmap might see no fade (it does, with the backdrop as `.background`); (d) `XF9`'s worry that a `List`/lazy row fades (nothing animated); (e) "the perpendicular velocity component is dropped" (`VA6c`); (f) "`ImageRenderer` draws no glass" (`R1` unreproduced on 27.2). **Confirmed:** `XF8` swap instant; `T1u` delay; `XF4` two animators; a changed `.id` fades (`XF7`); `VA4` whole pair; `VA5` interpolated proposals; `VA7` no skip in flight; `Animatable`/`Shape` nonisolated and `View` `@MainActor` (the SDK interface). **Added by the probes:** trim's data scale of 128 (`VA3`); SwiftUI's own `View & Animatable` spelling fails in Swift 6 mode.

## 4. Stop conditions touched, and what they imply for PRs B to E

| # | state | implication |
|---|---|---|
| 1, 2 | did not fire | PR B's unit model "each member of an `if` fades" is right, not "the `if`" |
| 3 | `XF8` did not fire | `$erased` stays a non-unit (PR B design step "Divergence 212") |
| 4 | `T1u` did not fire | default ghosts park `onDisappear`, as `LC-H` designs; `T1e` also delays when nothing is drawn, so a slice with no primitives still parks (the plan's "no ghost, no park" is wrong) |
| 8 | `XF9` did not fire | lazy and `List` loops note nothing (design stands); `List` data insertion unmeasured |
| 9 | not as written | PR B step 8 and the new z-order row are derived from a refuted recollection; the ghost goes to the bottom of its container's run |
| 10 | `VA4`, `VA5`, `VA7` did not fire | `PaintAnimatedShape` may go; PR E stands; the `VA6c` velocity projection should not be built |
| 14 | did not fire | `XF1` and `XF2` both passed, so z-order and the fade are measured, not claimed |
| 11 | read, not spiked | SwiftUI's `Animatable` is nonisolated, `View` is `@MainActor`; SwiftUI's own conformer spelling fails in Swift 6 mode. PR D's spike still owes the MetalUI side |

Specifically for B: `XF2` (a mixed unit), `XF10` (position), `T1e` (parking) change the plan's design; `XF7` adds an `.id` change as a default transition SwiftUI performs (residue today). For D: `VA3`'s scale of 128 and `VA6c`. For E: nothing against it.

## 5. What changed

- New probes `swiftui-default-transition.swift` (`XF0`..`XF11`, with sub-arms `XF2z*`, `XF5b`, `XF6b`, `XF8a`..`XF8f`, `XF10a`..`XF10e`) and `swiftui-animatable.swift` (`VT1`..`VT16`, `VA1`..`VA8`); the recorded outputs `swiftui-default-transition-run.txt` and `swiftui-animatable-run.txt`.
- `swiftui-lifecycle.swift`: arms `T1u`, `T4u`, `A4u`, `T1e`, `T1e2` and a header block. `swiftui-liquid-glass.swift`: group `GM` (`GM1a`..`GM1f`) and a header block (the `R1` non-reproduction).
- Divergences: row 98 (SwiftUI cell: what was measured; a mixed unit, a changed `.id`, the swap, the lifecycle, the leaver position), 169 (SwiftUI cell: `Float` is not `Animatable`), 828 (verdict, `GM1`, the container), 898 (`@MainActor`, verdict), 947 (SwiftUI cell: the exact data type). No count or label moves.
- This record, its README row, the decisions document, the `decision-prefixes.md` row, `Tasks.md` (R4-3 names PR A, unticked).

## 6. Not measured, and what an instrument could not separate

How anything looks in a real window; the dip of an `if`/`else` swap; per-primitive alpha through a card (205); `List`'s own row animation; the glass morph and the liquid merge (`GM1b` shows a recorder-visible swap only); a real backing scale; a spring's internals (`VA6c` is a 30 ms window mean). **`R1` of the glass probe read `[203, 200, 214]` against `R0 [142, 142, 142]` on 27.2** (the 2026-10-23 recording read `[142, 142, 142]` for both); it is not a control of this item and was not investigated.

## 7. Counts and checks

`swift package clean`, `swift build --build-system native --build-tests`, `swift test --build-system native --no-parallel`, unfiltered, 2026-11-03 (the desktop was shared with other sessions' runs): **`Test run with 5050 tests in 14 suites passed after 280.661 seconds`** (0 failures; no test was added, so the count is master's); `FR-J no-argument frame: succeeded=true deprecations=2` (guards ran). `zsh docs/probes/record-05-check.sh`, `closeout-inventory-check.sh` and `closeout-undocumented.sh` print nothing. The counts line of `CLAUDE.md` is not replaced; `divergences.md`'s counts did not move (208 live, next 215), so `CLAUDE.md` and `AGENTS.md` are untouched.

**Not run:** `METALUI_VERIFY_*` modes and the 100k-list test (no `Sources/` change); `Backends/SDL`, Linux and Windows CI; pixels (locked session, no Screen Recording); the glass probe's group W (needs an unlocked screen).
