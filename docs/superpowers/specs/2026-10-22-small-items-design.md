# Small items (IH-K, SN-L, P3c) — design

Round 2 item 9, requested 2026-10-21. Branch `feat/small-items` from `1c53976d`. Rulings `SM-A`…`SM-D`
([decisions](../2026-10-22-small-items-decisions.md)); record §147.

## Outcome

Three independent carried items were inventoried, probed and measured. **All three are ruled carried, each with a measured reason**; no
`Sources/` or `Backends/` line changes, so there are **no lanes, no public declaration (no census or inventory row), no divergence label
(765-774 untouched), no shader or renderer change, no new test or typecheck guard, no demo section and no human check**. Counts stay 4307 tests
in 3 suites at `1c53976d`; pixels are untouched by construction.

| item | carried id | built? | measured reason | evidence |
|---|---|---|---|---|
| Image decode cancellation | `IH-K` / `SM-A` | no | a read callback is 1-3 % of an in-memory decode; JPEG returns a zero-filled full image on early EOF | `docs/probes/stb-callback-eof.c`, `stb-phase-split.c` |
| Activation-token forwarding | `SN-L` / `SM-B` | no | `SDL_RaiseWindow` on Wayland never reads `XDG_ACTIVATION_TOKEN` (SDL 3.4.16); X11 ignores it | `docs/probes/sdl-activation-token.sh` |
| D-Bus activation | `SN-L` / `SM-C` | no | needs a new client dependency, a desktop-file contract and a second election; same result as the socket path | reasoning, no probe |
| R8 coverage with a shader tint | `P3c`, `PN-D` / `SM-D` | no | tint is 6 % of raster work (record §118); shaders not regenerable here (no shadercross/dxc) | record §118 §7, `which` |

## What would be built, if an owner appears

1. **Cancellation** (`SM-A`): a Swift-side `async` wrapper over the existing decode — not stb's callback — reading the file in 1 MiB chunks
   with `Task.isCancelled` between chunks, checking again before stb and discarding after; throws `CancellationError`. Class `M`, additive.
   Tests: a cancelled-before-start decode throws and performs 0 reads (counted through the chunk reader); an uncancelled one is byte-identical
   to `DecodedImage(data:)`; red-before is the missing symbol; the mutation is dropping the between-chunks check (the count pin reddens).
2. **Token forwarding** (`SM-B`): after an SDL release whose raise consumes the environment token (or our own Wayland binding): optional
   token string appended to the message; primary sets `XDG_ACTIVATION_TOKEN` before the raise. Testable in the Linux image for the wire format
   only; the effect is human check SI4 on a Wayland session.
3. **D-Bus** (`SM-C`) and **R8** (`SM-D`): see the rulings for owners and first steps.

## Verification run for this commit

Docs and probes only: `git status --short` lists only `docs/`; the probes were compiled and run (outputs in their headers). The full
suite, census, the fourteen images and the Linux image are **not re-taken** (nothing they read changed); the Record phase need only re-run
the inventory scripts if the merge moves them.

## Deferred (named, with owner)

Everything above is the deferral list; owners are in `SM-A`…`SM-D`.
