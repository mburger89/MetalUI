# `.task` follow-ups — decisions

Rulings for the three minor findings `PX-V` logged after `.task` landed
(user request 2026-10-02, item C4f of the gpui-gap priority list; **not a plan
task**). Prefix `TF-`. Spec:
[`specs/2026-10-08-task-followups-design.md`](specs/2026-10-08-task-followups-design.md).
Record: `../record/84-task-followups.md`. The rulings these follow up are in
[`2026-10-07-portable-app-decisions.md`](2026-10-07-portable-app-decisions.md)
(`PX-F`, `PX-L`, `PX-U`, `PX-V`) and the lifecycle's
[`2026-10-03-lifecycle-decisions.md`](2026-10-03-lifecycle-decisions.md)
(`LC-H`, `LC-P`).

**Next unused id: `TF-E`.**

Evidence (each header carries its recorded output and how to run it):

- [`../probes/swiftui-task-ghost-id.swift`](../probes/swiftui-task-ghost-id.swift)
  (**new**; arms `Y0`…`Y4`, run three times, byte-identical) — SwiftUI's
  `.task(id:)` and `.onChange(of:)` on content re-inserted from a removal
  transition with a changed id. Extends `swiftui-task.swift`'s `X17`.
- [`../probes/swiftpm-remote-dependency-warnings.sh`](../probes/swiftpm-remote-dependency-warnings.sh)
  (**new**; arms `LOCAL`, `URL`, `URL-OWN`) — what a consumer's `swift build`
  prints of a dependency's source warnings, by path and by URL.
- The source: `Sources/MetalUI/Lifecycle.swift` (`LifecycleStore.endFrame`),
  `Tests/MetalUIScaffoldTests/ScaffoldTests.swift` (test 1.7),
  `Backends/SDL/Sources/MainQueueDrainCheck/main.swift`,
  `Backends/SDL/Sources/MetalUISDL/SDLPlatform.swift`,
  `Backends/SDL/Sources/MetalUISDL/SDLWindowRenderer.swift`, and
  `Window.drawFrameIfNeeded` (`guard let … = platformWindow.renderer.beginFrame()
  else { setNeedsRedraw(); return }` — no build, no lifecycle drain, without a
  drawable).

## TF-A — A key returning from a removal ghost compares its task id and its `onChange` value against the entry it left with

**Ruling.** Supersedes `PX-V` item 1 ("left as is").

1. **SwiftUI's answer, probed** (`swiftui-task-ghost-id.swift`). Content
   re-inserted 0.15 s into a 0.6 s removal with its `task(id:)` value changed —
   in the re-insertion's own transaction (`Y1`) or written while it was a
   ghost (`Y2`) — cancels the old task, starts the new one (cancel first,
   `X5`'s order) and fires its `onChange(of:)` old→new, in the re-insertion's
   update: the same three lines, in the same order, as an id change with no
   removal (`Y3`). Re-inserted with the id unchanged (`Y0`) nothing runs
   (`X17`'s reading). With no transition there is no ghost and the
   re-insertion is a new appearance (`Y4`). SwiftUI keeps the departed view's
   task id **and** its `onChange` baseline across the ghost.
2. **MetalUI today** keeps neither. `LifecycleStore.endFrame` compares only
   inside `if let old = previous[key]`; a key returning from a parked ghost has
   no previous entry (the removal build dropped it), takes back only its
   `RunningTask` box (`ParkedGhost.running`, `PX-U` item 1) and is in
   `cancelled`, so the start branch and the appearance branch both skip it.
   The task keeps running under the old id; an `onChange` on the same content
   does not fire either — the same comparison point, which divergence 123's
   row already states ("its next `onChange` compares against nothing").
3. **The fix: the ghost parks the departed entry, not only its box.**
   `ParkedGhost.running: [Key: RunningTask]` becomes
   `ParkedGhost.departed: [Key: Entry]` — the whole last-build entry of every
   key that left under the ghost (its `task` spec with the id and `isEqual`,
   its `change` value, its `running` box). At the return, the entry is taken
   back into a per-build `returned: [Key: Entry]`, and the walk over `current`
   reads `previous[key] ?? returned[key]` as the old entry. Everything the
   `previous` branch does then applies unchanged: a different id is a change
   event that cancels then restarts (`X5`, `PX-U` item 2's bucket); an equal
   id carries the box (`X17`, unchanged); a changed `onChange` value fires
   old→new in the change bucket; a scope that stopped being a task is
   cancelled. The appearance branch is never reached for a returning key, so
   `T4`'s rule (no `onAppear`, no `initial: true` firing) holds by
   construction, as before. `runningTaskCount` reads
   `departed.values.compactMap(\.running)` where it read `running.values`;
   `closeAll` is unchanged (corrected at critique, `TF-D` item 3).
   `@State` is untouched: it is still reset at the removal (`ID-C`), which is
   the rest of divergence 123.
4. **Divergence 123 is amended, not retired**: its MetalUI column drops the
   `onChange` clause ("and its next `onChange` compares against nothing");
   `@State` stays fresh. Its pin (`reinsertingDuringTheGhostRunsNeitherCallbackAndStartsWithFreshState`,
   an `onChange(of: 5, initial: true)`) stays green: the value is constant.
   Record §04 gains a dated amendment line in the Record phase.
5. **Cost.** Zero on a steady frame and on a frame with no ghost (`LC-M`:
   `returned` is filled only inside the existing `if !parked.isEmpty` block);
   a returning key costs one dictionary move. Nothing in identity, state
   retention, transitions or animation moves.

**Evidence.** The probe's five arms (`Y0`, `Y3` the controls; `Y1`, `Y2`, `Y4`
the separating arms); the source read in item 2, confirmed red-first by the
spec's tests TF1.1–TF1.3 at `70ed000`.

**Cost if wrong.** If SwiftUI kept the old task (it does not: `Y1`), the fix
would restart a task SwiftUI keeps — visible only to code that changes an id
in the frames a removal reverses. The `onChange` half is the same mechanism;
splitting it out would leave one comparison point with two rules.

## TF-B — Test 1.7 refuses every `warning:` line in the consumer's build, and is proven able to fail

**Ruling.** Supersedes `PX-V` item 2's repair ("one substring,
`.build/checkouts/MetalUI`").

1. **The proposed repair would still not fail.** SwiftPM suppresses every
   source warning of a remote (URL) dependency — measured
   (`swiftpm-remote-dependency-warnings.sh`, macOS, Swift 6.4): `LOCAL` 6
   warnings, `URL` 0, `URL-OWN` (the consumer's own unused `let`) 2 lines. A
   consumer of MetalUI by URL — what 1.7 builds — never prints a line naming
   `.build/checkouts/MetalUI` for a warning in MetalUI's sources. That is also
   why `PX-V` saw only consumer paths under mutation V6.
2. **What a URL consumer can see is what 1.7 must refuse**: SwiftPM's own
   diagnostics about the package graph — `PX-H` item 3's hazard, "couldn't
   find pc file for accesskit" in **every consumer** once a `.systemLibrary`
   declares `pkgConfig:` — and warnings in the generated starter's own
   sources, which are MetalUI's text (`metalui new`). Neither names the
   repository path. So the filter becomes **every line containing
   `warning:`**, with no allowlist (lane 1 of `PX-` measured the printed log
   at 0 warnings, record §80 §1.3; the default build system prints no
   deprecation notice).
3. **Proof it can fail** (spec §5, run in CI's Linux image — the test is
   Linux-only): mutation **MT2.1** adds `pkgConfig: "accesskit"` to the root
   manifest's `CAccessKit` system library — the old filter stays green (the
   red-before of this item: the defect, shown), the new one reddens; mutation
   **MT2.2** adds a function holding an unused `let` to the starter's
   `mainSource` — reddens. Measurement **MT2.3** (recorded, not a pin): an
   unused `let` in `Sources/MetalUI` — the consumer prints no warning in the
   image either; the claim "MetalUI's sources build warning-free" stays pinned
   by the root package's own builds (CLAUDE.md's 0-warning rule), never by
   1.7, and 1.7's doc comment says so.
4. The test keeps its name (`aCrossPlatformPackageBuildsItsSDLAppByURL`, cited
   by record §80 and the CI workflow's filter).

**Cost if wrong.** If some future SwiftPM prints an unavoidable notice in
every consumer, 1.7 reddens in CI with the line in its message; the remedy is
an explicit, commented allowlist entry — never a return to a path filter.

## TF-C — `.task` runs under SDL in CI's Linux image through an offscreen-rendered `SDLPlatform` window

**Ruling.** Closes `PX-V`'s third open item (`PX-R` item 4: test 3.20 is gated
off SDL's offscreen driver, so no CI job runs `.task` under SDL).

1. **Why 3.20 cannot run there** (source, and `SDLLifecycleTests`' measured
   note): under `SDL_VIDEO_DRIVER=offscreen` an `SDLWindow`'s swapchain
   renderer never gets a drawable, `beginFrame()` answers `nil`, and
   `Window.drawFrameIfNeeded` returns before building — no frame, so no
   lifecycle drain, so no `.task` ever starts.
2. **The two options the item named, judged.** *A headless frame drive*
   (`Window.renderFrame`) runs no lifecycle by rule (`LC-J`: "a headless
   `renderFrame` runs nothing") — changing that rule is out of scope and would
   move `aHeadlessRenderFrameStartsNoTask`. *The main-queue drain alone* is
   already pinned there by 3.21 (`Task.immediate` from top-level code); it
   does not exercise `.task`'s start and cancel, which happen in a frame's
   drain.
3. **The way taken: the real loop with a renderer that always has a target.**
   `SDLWindowRenderer(offscreenWidth:height:)` already renders into a GPU
   target without a window, and runs ungated in the image
   (`SDLWindowRendererTests`, `SDLSurfaceTests`). `SDLPlatform` gains a
   **`package`** initialiser parameter, `init(hiddenWindows: Bool = false,
   offscreenRenderers: Bool)` (the public `init(hiddenWindows:)` unchanged and
   forwarding `false`), under which `openSDLWindow` gives each `SDLWindow` an
   offscreen renderer the window's size (in pixels, scale 1) instead of
   claiming the window. Everything else is the production path: SDL events,
   `SDLPlatform.run`'s pump, main-queue drain and display-link ticks,
   `App.openWindow`, `Window.drawFrameIfNeeded`'s builds and lifecycle drain,
   `Task.immediate`. `package` keeps it off the public surface (no census row,
   no inventory row) and out of the root package's consumers; the `#if !SDL`
   stub is not touched.
4. **The check**: `MainQueueDrainCheck task-modifier-offscreen` — the
   `task-modifier` mode's tree and line over
   `SDLPlatform(hiddenWindows: true, offscreenRenderers: true)` — and an
   **ungated** test 3.20b, `aTaskModifierProgressesAndIsCancelledUnderSDLWithoutAPresentedFrame`,
   expecting `task started=true steps=3 cancelled=true`. 3.20 keeps its gate
   (it is the swapchain path's pin on macOS and Windows).
5. **Not taken**: making the production `SDLWindow` fall back to an offscreen
   target when no drawable arrives (it would draw frames nobody sees in every
   headless deployment and change the drawable contract); widening the change
   to un-gate `SDLLifecycleTests` 10.2/10.3 (same mechanism, cheap, but not
   this item — named in the spec's deferred list, owner a follow-up).

**Cost if wrong.** The offscreen renderer could differ from the swapchain one
in pacing (no acquire wait, so the loop spins); the check is bounded by
`iterationLimit` and counts passes, never time. If the offscreen renderer ever
failed in the image, 3.20b fails loudly (renderer creation throws), never
skips.

## TF-D — Critique of the design: the departed baseline meets the reset `@State`; two corrections

**Ruling.** Amends `TF-A` (adversarial review of `9e82b81`, before any code).
Both probes were re-run first: `swiftui-task-ghost-id.swift` compiled and run
twice, 65 lines each, byte-identical to its header (screen unlocked,
`displayAsleep main: 0`); `swiftpm-remote-dependency-warnings.sh` re-run,
`LOCAL 6 / URL 0 / URL-OWN 2` as recorded. The SwiftUI claims stand.

1. **The consequence `TF-A` did not name.** MetalUI resets the departed
   content's `@State` at the removal (`ID-C`, divergence 123; pin 6.4 sees the
   fresh tile). `TF-A` restores the departed *lifecycle* entry, so a
   `task(id:)` or `onChange(of:)` whose value is read from that content's own
   `@State`, written before the removal, compares the fresh default against
   the departed value on return: a restart (or a firing) SwiftUI never makes,
   since SwiftUI keeps the state and the id is unchanged (`T4`, `Y0`'s reading).
   Before `TF-A` the same content kept the stale task running under an id the
   content no longer shows. **Taken anyway**: (a) with an id from outside the
   content — the common shape, a selection or a model key — `TF-A` is
   SwiftUI's answer and the old behaviour ran a task for the wrong id; (b) with
   an id from the reset state, the restarted task runs for the id the content
   now displays, which is coherent with what the reset already shows; (c) the
   only way to match SwiftUI in both is to keep `@State` across the ghost,
   which is divergence 123's root (`ID-C`) and out of this item. Divergence 123
   is amended to say exactly this (spec §3.1) and gains a second pin, spec test
   **TF1.4** (`aTaskIDReadFromTheContentsOwnStateRestartsOnReturnFromAGhost`,
   red before at `70ed000`, reddened by MT1.1). No new divergence label.
2. **`MT1.3`'s reading was wrong.** Each lifecycle modifier is its own key
   (scope id plus occurrence, `MV-M` item 5), so parking only boxed entries
   drops *both* `onChange` lines in TF1.3, not only the second leaf's. The
   mutation still reddens TF1.3 alone; the spec's text is corrected.
3. **`closeAll` does not change.** It never read the parked boxes: a parked
   task's cancel is its parked event (`onDisappear ?? cancelEvent(running)`),
   which `closeAll` already runs (3.14, `M3.14`). Reading the departed boxes as
   well would issue a second cancel. `TF-A` item 3 and the spec are corrected.
4. **Checked and kept.** `TF-B`: the old filter's blindness is real (the
   probe's `URL` arm), and "every `warning:` line" is the narrowest filter a URL
   consumer can fail; MT2.1/MT2.2 are the separating arms, run in the image.
   `TF-C`: the display link ticks under the offscreen driver (`linkRunning`
   reads only the tick and pause state, `SDLPlatform.swift`), so the only
   missing piece is a target for `beginFrame()` — exactly what the `package`
   option supplies; the swapchain-path arm (`offscreenRenderers: false`
   printing `started=false`) is the separating arm, taken red first in the
   image. No public declaration, no platform requirement, no shader, no pixel.
   The deferral of `SDLLifecycleTests` 10.2/10.3 stays: it is not item 3's
   question (`.task` under SDL), and it is named with an owner.

**Cost if wrong.** If an app reads a `.task(id:)` from content-local `@State`
inside a transition it reverses, its task restarts once on the return; the
divergence row says so, and TF1.4 reddens the day `@State` survives the ghost
(then TF1.4's expected log becomes `[]` and divergence 123 can retire).
