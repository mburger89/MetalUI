# Synchronous render batch for MetalCreator (XP-G22) — decisions

Rulings for item XP-G22 of the gpui-gap priority list (MetalCreator request 2026-10-22; **not a plan task**). Prefix `SY-`.
**Next unused: `SY-H`.** Spec: [`specs/2026-10-22-sync-batch-design.md`](specs/2026-10-22-sync-batch-design.md). Record: `../record/143-sync-batch.md`.
Branch `feat/sync-batch` from `d062168c`. Continues `GA-` (record 114, 125) and `GB-` (record 137). Divergence labels reserved 725–734: **none taken**.

Sources of truth. SwiftUI has no GPU API, so there is no SwiftUI-facing claim and no probe is owed; gpui exposes no command buffer to an app
(recalled, source not on this machine), context only. Facts come from this repository at `d062168c` (`SDLGPUDevice.swift`, `SDLGPUReadback.swift`,
`SDLGPUFence.swift`) and `SDL_gpu.h`. Backends/SDL is outside the census (`GA-L`); class M.

## SY-A — one recorder: `recordAndSubmit`, shared by the async and the synchronous verb

**Question.** How does the synchronous verb record and submit "exactly as `submitBatch` does" without a fork?
**Evidence.** `submitBatch`'s worker job (acquire, `record`, open-pass check, submit-and-fence, wrap, `startWaiting`) is the only place GA-E's fence rule
and the open-pass cancel live; `downloadSynchronously` already forked a smaller copy for its raw copy pass.
**Ruling.** Extract that job body into `recordAndSubmit(_:gate:) -> Result<SDLGPUFence, SDLGPUError>`, run on `submitWorker`; `submitBatch` resumes its
continuation with the result, the synchronous verb waits on a semaphore for it passing `waiterGate` like `submitBatch` (`SY-G`). Every `startWaiting` call stays at one site per verb
family, so the fence is released after its signal whether or not anyone awaits it. **Cost if wrong.** The refactor touches the async path every GPU
test uses; the S1–S6 and compute tests are the net, and Y9's mutation proves the net sees `startWaiting(gate:)`.

## SY-B — spelling: `submitBatchSynchronously(_:) throws -> SDLGPUFence`

**Ruling.** The requested spelling, kept: not `async`, so it is not an overload of `submitBatch`; it returns the fence so the caller picks `waitBlocking()`
or `downloadSynchronously`. It returns when the buffer is **submitted**, not finished (the caller blocks for the GPU only in the verb it chooses), and the
fence is normally unsignalled (pin Y2). **Cost if wrong.** A caller wanting render-and-read in one call composes two verbs; `SY-E` refuses the sugar.

## SY-C — rules are GB-F's, with the verb's own name

**Ruling.** `SDLGPUWindowGuard.assertNotInsideDraw("SDLGPUDevice.submitBatchSynchronously")` (debug trap, `GA-I`, `GA-R`) and
`preconditionNotOnOwnWorker("SDLGPUDevice.submitBatchSynchronously")` (every build, `GB-I` 2, `GB-L` 3) come first. Failures throw `SDLGPUError`
with the same three messages `submitBatch` uses (they come from the shared recorder). The `record` closure runs on the submit worker while the caller
is blocked: **a closure that hops to the main actor and waits deadlocks, and nothing detects it** (like `GA-I`'s raw SDL call, `GA-I` item on raw calls); a
blocking verb inside it is the precondition. Documented on the verb. **Cost if wrong.** A deadlock is a hang, not data loss; a timeout-guarded test
would be the instrument if a caller reports one.

## SY-D — share the hand-back box, leave `downloadSynchronously`'s body alone

**Ruling.** `Submitted` (semaphore + fence) becomes internal and carries a `Result`; both blocking verbs use it. `downloadSynchronously`'s copy-pass job is not
moved onto `recordAndSubmit`, because `SDLGPUCommandBuffer` has no texture-to-transfer copy verb and adding one is a public API nobody asked for. Carried
to the spec's "Not built". **Cost if wrong.** Two submit jobs remain; both are short, both pinned.

## SY-E — no combined render-and-read verb

**Ruling.** Refused: `submitBatchSynchronously` + `downloadSynchronously` is two calls, and a combined verb would need a result type for "pass failed" versus
"readback failed". **Cost if wrong.** Sugar added later, source compatible.

## SY-F — no divergence, no probe, no demo, no human check, no migration note

**Ruling.** Additive class-M API in `Backends/SDL`, no seam requirement (`PlatformWindow`/`Platform`/`WindowRenderer` untouched), no shader change. The
fourteen images and the root count (4248) must not move. **Cost if wrong.** A moved root number would mean the lane left `Backends/SDL`.

## SY-G — the synchronous verb passes `waiterGate`, not nil (critic's correction)

**Question.** Y2 holds `device.waiterGate` to keep the fence unsignalled; does the verb honour it?
**Evidence.** `waiterGate` is read in `submitBatch` and handed to `startWaiting(gate:)` (S2, compute tests use it); the first draft of SY-A said `gate: nil`, which would
make Y2 unable to observe an unsignalled fence and its mutation untestable. `downloadSynchronously` keeps `nil` (its fence is internal).
**Ruling.** The verb reads `waiterGate` on the caller and passes it to `recordAndSubmit`, as the async verb does; nil in production. **Cost if wrong.** Y2 would pass vacuously.
Also rejected: a trap-message check in Y5 against the guard's text beyond the verb name (the suffix is the guard's, `SDLGPUWindowGuard.swift:95`); Y5/Y6 assert the prefix only.
