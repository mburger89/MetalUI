# Milestone 0 — decisions made during execution

Every ruling taken on the user's behalf while executing
`docs/superpowers/plans/2026-08-25-metalui-m0-foundation.md`, in the order made.
Each says what was decided, why, and what it costs if wrong. Reworking any of
these is a normal edit — nothing here is load-bearing on anything else except
where noted.

**Summary: 26 rulings. Every defect found during execution was in the plan or
the spec, not in the implementations.**

## Pre-flight (from scanning the plan before any code)

| # | Ruling | Cost if wrong |
|---|---|---|
| R1 | Task 1's `Package.swift` declares a `MetalUICore` product, not `MetalUI`. A product naming a target the same task deletes is a hard SwiftPM error — the plan could not build at Task 1. | None; the state was unbuildable. |
| R2 | Keep `setVertexBytes` for M0 but comment the 4KB cap (~39 `MUIRect`s). | Silent truncation past ~39 rects if M1 inherits it unnoticed. |
| R3 | Drop the `!` on `colorAttachments[0]` only if the compiler rejects it. It didn't — imports as IUO. | None, compile-time only. |
| R4 | Drop the `Sendable` extension if the compiler reports redundancy. **Superseded — see B-1'.** | None. |
| R5 | The unit-mixing check is a sanity check, not a gate; locate the real Modules dir. | None. |

## Dispatch A — MetalUICore

| # | Ruling | Cost if wrong |
|---|---|---|
| A-1 | The "units never implicitly convert" invariant gets a real regression guard. It is a spec pillar with nothing defending it — a future refactor adding `Numeric` would compile green. | A test that may need skipping on an unusual CI host. |
| A-2 | `DevicePixels` stays narrow — **the brief was wrong, not the code.** It wraps `Int32`, so float literals and `* Float` are meaningless and should not compile. Declined to add arithmetic (nothing in M0 needs it). | A later task wanting it adds it then. |
| A-3 | The `Edges`/`Corners` equality test enters the fix round despite being filed Minor: uniform values on both sides mean it passes against a transposing init. Test invalidity, not style. | Negligible. |

## Dispatch B — shared shader types

| # | Ruling | Cost if wrong |
|---|---|---|
| B-1' | **Delete** the `Sendable` extension rather than annotate it. Swift 6 already imports an all-trivial C struct as `Sendable` (verified cross-module), so it was redundant and `@unchecked` opted the type out of real checking. My prepared `swift_attr` fix was unnecessary. | If a toolchain stops inferring this, the build breaks loudly at the use site; `swift_attr` is recorded in the plan as the fix. |
| B-2 | The converter test enters the fix round. Same defect family as A-3 and systematic in the briefs. Audited the rest: confined to Tasks 1 and 4. | Negligible. |
| B-3 | Incremental builds do not refresh Swift's view of the shared header. Task 7 gains a **required** `rm -rf .build` on both sides of its drift injection. Declined the `shim.c` `#include` defusal — tested, Swift's value stayed stale. | None; a clean build is slower, never incorrect. |

## Dispatch C — shader, loader, ABI probe

| # | Ruling | Cost if wrong |
|---|---|---|
| C-c | **Resolved, no action.** Probe coverage is structurally sound: each nested aggregate is pinned by its own `sizeof` *and* a scalar at a known offset, so MSL padding cannot hide. | — |
| C-a | The staleness footgun stays documentation, not code. | Someone misreads an incremental result; mitigated by warnings at both the constraint and the step. |
| C-b | The ABI probe **skipping** without a Metal device is accepted for M0. A guarantee that silently lapses on headless CI is the exact failure mode this batch prevents, but no CI exists yet. | **If CI is added before this is revisited, the ABI guarantee is silently absent there. Gate it on an env var before the first CI job.** |

## Dispatch D — Scene and Renderer

| # | Ruling | Cost if wrong |
|---|---|---|
| D-1 | **Wire the seam.** `SurfaceView.projection` was never read, so a stereo backend would have rendered identical output for both eyes — the very change the seam exists to avoid. Spec §3.2 already said the renderer multiplies by the matrix; the code didn't. Chose wiring over deleting under YAGNI. | A buffer slot and a matrix multiply per vertex, both trivial. |
| D-2 | The fill test enters the fix round: both probes sat far from any edge, so a 20px placement error shipped green. | Negligible. |
| D-3 | An asymmetric-colour assertion is required — every renderer test used white and black, symmetric under red↔blue. | Negligible. |
| D-4 | The Scene stability test is **kept despite being a non-discriminator** (green at every n tried, up to 5000). Swift's `sorted` is stable in practice but undocumented, so the tiebreaker is right and the test is a tripwire. | A test that reads stronger than it is; comment corrected. |

## Dispatch F — App, frame loop, demo

| # | Ruling | Cost if wrong |
|---|---|---|
| F-1 | **The Retina defect is in the demo, not `Window`** — and this overturned my own instinct. Making the demo proportional would have redefined corner radius and border width as *fractions*, destroying the crispness check. Thread the scale factor instead. | `FrameContent`'s signature churns again in M1; cheap versus inheriting the units confusion. |
| F-2 | Draw once eagerly at the end of `App.openWindow`. `setNeedsRedraw` only unpauses, and the init-time `onResize` fires before `Window` installs its handler — a window starting occluded stayed blank forever. | One wasted frame at startup. |
| F-3 | Wire `onClose` to terminate. **The plan's "close the window to exit" could not work** — no wiring, no delegate, no menu — and a human was about to follow it. | None. |
| F-4 | `@_exported import` in the umbrella. Dropping the `MetalUICore` product left the `MetalUI` library unusable externally: `openWindow` takes a `Size<Pixels>` nothing outside could name. | `@_exported` is underscored; fallback is declaring the inner libraries as products. |

## Final review

| # | Ruling | Cost if wrong |
|---|---|---|
| G-1 | One fix wave, seven items, no second wave. Instructed the implementer to report BLOCKED rather than change production code to make `Window` testable — it wasn't needed; `Window.init` was already injectable. | Test-only surface added. |
| G-2 | Plan header said "seven targets"; M0 ships six non-test targets. Corrected. | None. |

## Carried into M1

- **Gate the ABI probe on an env var before the first CI job** (C-b) — otherwise the guarantee is silently absent in CI.
- **Make the shared header a tracked build input** rather than a symlink. `abi_probe` structurally cannot catch a CPU side that was never rebuilt, and the symptom is a vanished rect that looks exactly like a shader bug. Run `swift package clean` after header edits until then.
- **Replace the pixel-format constant pin with a real blend-readback guard** — 50%-alpha white over opaque black is ≈128 under gamma compositing, ≈188 under linear.
- 12 further deferred minors triaged fix-in-M1; see the final review section of the plan.
