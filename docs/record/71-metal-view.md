# 71 — MetalView, the app-owned GPU surface

Branch `feat/metal-view` from `330f02b` (master: drag and drop merged, PR #36).
**Not a plan task**: new feature work requested by the user on 2026-10-01 — the
binding design spec's §7.7 ("`MetalView` — app-owned rendering"), which calls
it "the reason a Metal-native UI framework is worth building at all" and which
was never built. Spec `docs/superpowers/specs/2026-10-01-metal-view-design.md`;
rulings `MV-A`…`MV-R` in the new decisions doc
`docs/superpowers/2026-10-01-metal-view-decisions.md` (next unused `MV-S`);
probe `docs/probes/swiftui-metal-view.swift` (groups `P`, `G`, `C`/`D`, `R`).

**Numbering.** This record was written as `§69` and renumbered at the Record
phase: `69` went to `69-claude-md-full-2026-10-01.md` (PR #37, merged into this
branch as `d7a0824`) and master has since published §70 (app icon, PR #38,
`95234db`) — the 24→25 / 26→27 precedent (`MV-O` item 4). Master published no
further record number before the merge, so §71 stands. **The human-checks
group letter collided too**: master's app icon (§70) had already added its own
group O (O1–O4), so at the merge this branch's group O became **P** (P1–P8) and
every "group O"/"groups A–O" citation here, in `CLAUDE.md`/`AGENTS.md`, the
decisions doc, the spec, record §03, `README.md` and `docs/api-overview.md`
moved with it (found by the branch checker, 2026-10-02; done at the merge,
§11).

**Status: LANDED — every agent-doable clause is built; the looks are owed to a
human** (`docs/verification/human-checks.md` group P, §7). Three lanes, each red
first, each with a review round, all verified `ok: true`; the Record phase's
close (§9) re-took the suite, the counts, the inventory check and the
fourteen-image comparison.

## §0 Baseline, design session and critic round (2026-10-01)

- **Baseline** at `330f02b`: **2028 tests in 3 suites**, 0 goldens, 125
  typecheck guards, 69 live divergences (next label 103), public census 1940
  declarations in 99 inventory families, `Backends/SDL` 22 + 41.
- **Carried items.** No decisions doc's "Carried…" section addresses an
  app-owned surface; `grep -i "MetalView\|app-owned\|PaintSurface\|GPU surface"`
  finds three M0/M1 plan lines deferring it to "M5", one animation-spec line
  ("There is no `MetalView` and no draw context yet — that is M5") and the
  `StateTable.swift` doc comment this branch refutes (`MV-E` item 6). None is a
  ruling; all are discharged here.
- **Probe** `swiftui-metal-view.swift`: `P1`–`P3` positive controls, `G1`–`G3`
  sizing (`Canvas`, an `MTKView` representable, `TimelineView{Canvas}`),
  `C1`–`C4` compositing under a clip and an opacity in a real on-screen window,
  `D1` the drawable's size, `R0`–`R3` when `Canvas` re-runs. The design session
  ran it with the screen unlocked; the critic round re-ran it whole, **every G,
  C, D and R line byte for byte** (`MV-L`).
- **Critic round** (`MV-L`): six corrections — two siblings sharing one `.id`
  would have crashed `SurfaceTargetTable` (the registry is keyed by
  (`GlobalElementID`, occurrence)); `package` counters do not cross a package
  boundary (`SDLWindowRenderer` counts for itself); test 1.15 could not see
  `requestAnotherFrame()` replacing `noteActiveAnimation()`; mutation M3f was
  not one test 3.4 could see (`mui_renderer_submission_count` added); targets
  must use Metal's default, tracked hazard mode; test 2.6 could not see a
  shared table (windows now draw alternately, at different sizes). One finding
  rejected (renaming `SurfaceID`/`SurfaceTarget` to `GPUSurface…`).

## §1 What landed

- **`GPUSurface`** (`Sources/MetalUI/GPUSurface.swift`, portable, `MV-A`): a
  `ProposalElement` leaf, `GPUSurface(redraw:draw:)` and
  `GPUSurface(redraw:value:draw:)`, whose `@MainActor` closure gets an
  `any GPUSurfaceContext`. It sizes like `Canvas`/`Color` — the proposal on each
  axis, 10 on a nil axis (`MV-B`, probe `G1`; an `MTKView` representable
  answers 0 there, `G2`, the separating arm). It registers no hitbox, focus
  entry or accessibility record: input and accessibility come through the
  ordinary modifiers (`MV-I`).
- **`MetalView`** (`Sources/MetalUI/MetalView.swift`, `#if
  canImport(MetalUIRender)`, macOS only): the spec's name with a typed
  `MetalDrawContext`, a layout-, paint- and identity-transparent wrapper around
  one `GPUSurface`; **a `MetalView` handed a non-Metal context traps** naming
  `MV-A` item 2. No `id:` parameter and no invalidation handle: identity is
  structural and a `value:` read during the tracked build invalidates (`MV-A`
  items 3–4).
- **The scene primitive** (`MetalUIScene`, `MV-C`): `PrimitiveKind.surface`,
  `SurfaceID`, `SurfaceTarget` (id + device-pixel size), `Scene.surfaces`
  (`MUIImage` quads) and `Scene.surfaceTargets`; the scene's side tables become
  eight plain `[Int]` arrays. **No Metal, SDL or closure type enters the scene**
  (`PS-A`) and **no shader changed on either renderer**: a surface run is
  drawn by the image pipeline with its target bound as the texture. A
  `FixtureRun` cannot record a surface (it traps naming `MV-C` item 4).
- **The lifecycle and the seam** (`MetalUIPlatform`, `MV-E`, `MV-F`, `MV-G`):
  `RedrawPolicy` (`.onDemand`/`.continuous`), `GPUSurfaceContext`,
  `SurfaceDrawRequest`, and **`SurfaceTargetTable<Handle>`** — the one portable
  implementation of "created and resized at the element's device-pixel size
  (`(points × scale).rounded()`, clamped to 8192), reused across frames,
  released when no scene references it, a ghost's target kept and not drawn",
  owned **per window** by each `WindowRenderer` (the per-window answer record
  §61 §6 item 4 asked for, for surfaces). `WindowRenderer.finishFrame(scene:atlas:surfaces:)`
  is the new **defaultless** requirement; a forwarding extension keeps
  `finishFrame(scene:atlas:)` callable.
- **The frame side** (`Frame.drawSurface`, `SurfaceRegistry`, `Transition.swift`,
  `DragSession.swift`, `MV-D`): `drawImage`'s arithmetic line for line (active
  offset, clip and radii, opacity, layer), through `insertThroughTransitions`
  with a new `CapturedPrimitive.surface`, mirrored into every switch over it,
  so `.clipShape`, `.cornerRadius`, `.opacity`, `.transition` ghosts and a drag
  preview treat a surface as an image. A zero-size, fully clipped or
  transparent surface emits nothing and its target is released; `.continuous`
  paints `noteActiveAnimation()`, never `requestAnotherFrame()` (divergence 103
  is `.onDemand`'s answer, `MV-G` item 5). The registry (`SurfaceID` per
  (`GlobalElementID`, occurrence), minted per window) is **not** a `StateTable`
  entry: the seven reserved slots did not move.
- **Metal** (`MetalUIRender`, `MV-F`): `MetalWindowRenderer` owns a
  `SurfaceTargetTable<MTLTexture>` (`bgra8Unorm`, render target + shader read,
  private, default hazard tracking); `finishFrame` uploads the atlas, resolves
  the table, clears new targets to transparent, runs each surface's draw on the
  main actor **into the frame's own command buffer before** `Renderer.encode`,
  and traps (naming `MV-F` item 5) if a draw left the buffer committed or
  enqueued; draws are recorded only after `commit()` (`MV-O` item 2).
  `MetalDrawContext` adds `device`, `commandBuffer`, `target` and
  `renderPassDescriptor(loadAction:clearColor:)`; its initialiser is `package`.
- **SDL** (`Backends/SDL`, `MV-H`, `MV-P`): `SDLWindowRenderer` owns the same
  table (`mui_renderer_create_target`, no upload, no submission, no fence),
  draws between `mui_renderer_begin` and `mui_renderer_finish` into the frame's
  buffer, appends the surface quads to the image array it already uploads
  (texture index offset by `scene.textures.count`) and passes `.surface` runs as
  image runs — `images_valid`, the packing, `mui_renderer_finish` and the HLSL
  unchanged; **the fence rule holds by construction**, pinned by
  `surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence` and the existing
  `backToBackFramesNeverReleaseAnUnsignaledFence`. Five new bridge functions
  (`mui_renderer_device`, `_command_buffer`, `_create_target`,
  `mui_gpu_clear_texture`, `mui_renderer_submission_count`; a sixth,
  `mui_gpu_blit_texture`, is test plumbing, `MV-Q` item 2) and
  `SDLGPUDrawContext` (`device`, `commandBuffer`, `target` as SDL3 pointers;
  `package` init). A draw that commits on SDL is undefined behaviour,
  undetectable (SDL3 has no command-buffer state query), stated on the type.
- **The demos** (`MV-J`): `METALUI_METALVIEW_DEMO=1` on `MetalUIDemo` (a
  fragment shader compiled from MSL at runtime, `device.makeLibrary(source:)`)
  and `MetalUISDLDemo` (a hue cycled through `ctx.clear`);
  `metalViewDemoContent(draws:surface:)` in `MetalUIDemoContent`, its own
  function per the 1 MB-stack rule — a `.continuous` rounded viewport with a
  translucent label over it, a tap toggling `.continuous`/`.onDemand`, a draw
  counter, and a small `.onDemand` swatch recoloured by a `Stepper`'s `value:`.
- **Public documents**: divergence 103 and two "Not offered" rows
  (`docs/divergences.md`), two migration rows (`PrimitiveKind.surface`,
  `finishFrame(scene:atlas:surfaces:)`), the API overview's "GPU surfaces"
  section, human checks group P (P1–P8), inventory family `gpu-surface`.

## §2 Tests and guards, per file

Root **2028 → 2072 (+44)**: lane 1 +23 and its review round +6, lane 2 +13 and
its review round +2, lane 3 +0 (its tests are in `Backends/SDL`). No test
retired; `sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear`'s literal
moved 6 → 8 (a T row, `MV-C` item 2). Guards **125 → 128** (+3, all whole-file
`typecheckFile`). Goldens 0.

| file | tests | spec id |
|---|---|---|
| `Tests/MetalUIRenderTests/SurfaceSceneTests.swift` | `surfaceRunsBreakWhereTheTargetChanges`, `aSceneHoldingOnlyASurfaceIsNotEmpty`, `aSurfaceTargetIsCarriedOncePerID`, `oneSurfaceIDAtTwoSizesInOneSceneTraps` | 1.1–1.3, 1.3b |
| `Tests/MetalUICrossPlatformTests/SurfaceTargetTableTests.swift` | `aRequestedTargetIsCreatedAndDrawnOnceThenReused`, `aChangedValueRedrawsAndAnUnchangedOneDoesNot`, `aContinuousRequestDrawsEveryFrame`, `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating`, `anUnreferencedTargetIsReleasedAndAGhostsTargetIsKeptUndrawn`, `aReferenceWithoutARequestOrEntryCreatesNothing`, `twoRequestsForOneSurfaceTrap` | 1.4–1.10 (portable: Linux and Windows CI run them) |
| `Tests/MetalUITests/GPUSurfaceTests.swift` | 16: sizing (1.11), target size (1.12), id continuity and two placements (1.13, 1.13b), the no-GPU-work arms (1.14), `.continuous` and the window (1.15), the renderer hand-off (1.16), clip/radii/opacity/layer (1.17), ghost (1.18), drag preview (1.19), no hitbox but a tap (1.20), and the review round's 1.21–1.25 | 1.11–1.25 |
| `Tests/MetalUITests/GPUSurfaceCompileGuards.swift` | `theGPUSurfaceSpellingsCompileFromAPlainImport`, `aWindowRendererWithoutTheSurfacesFinishFrameDoesNotCompile` | G1.1, G1.2 |
| `Tests/MetalUITests/MetalViewTests.swift` | 13: first-frame fill (2.1), on-demand keeps contents (2.2), clip/round/fade pixel-equal to an `Image` (2.3), device-pixel bgra target (2.4), continuous vs on-demand draws (2.5), two windows (2.6), release (2.7), a committing draw traps (2.8), `MetalView` on the frame's buffer (2.9), a non-Metal context traps (2.10), the demo tree (2.12), the demo's counter (2.13), resize (2.14) | 2.1–2.10, 2.12–2.14 |
| `Tests/MetalUIRenderTests/SurfaceCompositingTests.swift` | `aSurfaceRunSamplesItsTargetThroughTheImagePipeline` (carries `SurfaceParity`, the shared literal) | 2.11 |
| `Tests/MetalUITests/MetalViewCompileGuards.swift` | `theMetalViewSpellingsCompileFromAPlainImport` (its negative arm is `MetalDrawContext.init`'s `package` refusal) | G2.1 |
| `Backends/SDL/Tests/MetalUISDLTests/SDLSurfaceTests.swift` | `anSDLSurfaceFillMatchesTheMetalParityLiteral`, `anSDLSurfaceIsDrawnBeforeTheSceneAndKeptAcrossFrames`, `anSDLSurfaceTargetIsReleasedWhenNoLongerReferenced`, `surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence`, `theSDLDrawContextCarriesTheFramesCommandBufferAndTarget`, `anSDLSurfaceTargetIsMadeAtItsDevicePixelSizeAndRemadeOnResize`, `aNewSDLSurfaceTargetArrivesClearedToTransparent` | 3.1–3.5, 3.7, 3.8 |
| `Backends/SDL/Tests/ReplayFixtureTests/ReplayFixtureTests.swift` | `aSceneWithASurfaceIsNotRecordable` (exit test) | 3.6 |

Existing tests that gained a `.surface` arm, no answer changed:
`DecorationPaintTests`, `DragPreviewTests`, `SceneFinalizeIdentityTests`,
`TransitionTests` (its harness shares one `SurfaceRegistry` across frames, as a
`Window` does), `DemoStackBudgetTests` (the new tree on a 1 MB thread).
`Backends/SDL` **22 + 41 → 23 + 48** (`ReplayFixtureTests` +1, `MetalUISDLTests`
+7).

## §3 Probes

`swiftui-metal-view.swift` (new). **Read**: `Canvas` sizes exactly like `Color`
(`G1`: nil×nil 10×10, 0×0, the proposal, infinity answered with infinity); an
`MTKView` representable answers 0 on a nil axis (`G2`, the separating arm);
`TimelineView(.animation){Canvas}` the same as `Canvas` (`G3`). SwiftUI
composites an app's Metal layer through the same clip and opacity as any view
(`C1` unclipped reads the surface's red, `C2`'s rounded corner reads the white
background, `C3`'s centre the half mix, against `P2`'s control and `C4`'s
`Canvas`). The drawable is bounds × backing scale (`D1`, 100×60 pt → 200×120 px
at 2.0) and an `MTKView`'s default draws continuously. An idle `Canvas` never
re-runs (`R0`); a value it reads re-runs it (`R2`, control `P3`); an unrelated
change re-runs a `Canvas` whose declaring body re-ran (`R1`) but not one in its
own child view (`R3`) — divergence 103. Colours read through the capture's
colour space, so only relations are claimed. Re-run whole at the critic round,
byte for byte (`MV-L`). **No new SwiftUI behaviour is claimed at the Record
phase**; the one carried, unprobed claim is §10's.

## §4 Red runs

Each lane committed its tests red first against a stub, with the failing
lines recorded in the commit message:

- **Lane 1** (`a0c82bd`): compile errors, the surface types absent
  (`SurfaceSceneTests`, `SurfaceTargetTableTests`, `GPUSurfaceTests`, the spy
  renderer in `Fakes.swift`, the three `PrimitiveKind` switches).
- **Lane 1's review round** (`66483c2`): 1.25 red at
  `GPUSurfaceTests.swift:562` (`after == [before[1]]` read `[before[0]]`); the
  other five tests and 1.15's policy clause pin existing behaviour.
- **Lane 2** (`636eb7b`): compile errors against lane 2's API, plus runtime red
  against lane 1's stub — 2.1 (`draws.value == 1`), 2.2, 2.3 (the unclipped arm
  must separate), 2.5, 2.6.
- **Lane 2's review round** (`c5191e0`): 2.13 red on `4a8bbed`'s shape
  (`shown` 0 of 6 draws); 2.14 green on arrival (pins what was built).
- **Lane 3** (`f222db0`): 3.1 (the parity literal at (10, 10) and (30, 30)),
  3.2, 3.3, 3.4, 3.5 red; 3.6 green on arrival (lane 1's trap, mutated).
- **Lane 3's review round** (`4d53473`): 3.7 and 3.8 are new pins on existing
  behaviour; the reddening is §5's V-rows.

## §5 Mutation tables

Every mutation from a copy of the committed file, the full unfiltered suite
(`swift test --build-system native --no-parallel`, or `Backends/SDL`'s own),
`git status --short` clean after each, reddened tests named.

**Lane 1's review round** (`MV-M`, each on `0005509`, suite 2057): A (`layer:
0` in `drawSurface`) → 1.21 only; B (`let translated = bounds` in `drawSurface`
alone) → 1.22 only (4 issues); D (`endFrame()` keeps every id) → 1.23 only; F
(`precondition(true || …)` in `Scene.insert`) → 1.3b only; G (the `.surface`
arm's inner-mask block dropped) → 1.24 only (2 issues); M (every request
`.onDemand`) → 1.15 only; H (the occurrence counted after the no-GPU-work
guards, `MV-M` item 5 reverted) → 1.25 only. The lane's own table (spec §8's
M1a–M1z against tests 1.1–1.20) was run by the lane and is not tabled in the
decisions doc; the reviewer's seven are the ones that were found green and are
the recorded ones.

**Lane 2** (`MV-N`, suite 2070; M2h, M2j, M2l, M2m re-run on the exit-test fix):

| mutation | reddens |
|---|---|
| M2a draws after `encode` | 2.1, 2.3, 2.9 |
| M2b `.surface` runs skipped in `encode` | 2.1, 2.2, 2.3, 2.6, 2.9, 2.11 |
| M2c a fresh table every frame | 2.2, 2.4, 2.5, 2.6, 2.7 |
| M2d the atlas bound for surface runs | 2.1, 2.2, 2.3, 2.6, 2.9 |
| M2e `.bgra8Unorm_srgb` targets | 2.3, 2.4 |
| M2f targets sized in points | 2.4 |
| M2g only new targets drawn | 2.4, 2.5 |
| M2h the table on the shared `Renderer` (clean build) | 2.6 |
| M2i `release` leaks the handle | 2.7 |
| M2j status precondition dropped | 2.8 |
| M2k `MetalView` forwards a fresh command buffer | 2.9 |
| M2l `MetalView` skips a non-Metal context | 2.10 |
| M2m target index + 1 (mod count) | 2.11 |
| M2n the demo's main surface `.onDemand` | 2.12 |
| G2.1 `renderPassDescripter` in the positive fixture | G2.1 |

**Lane 2's review round** (`MV-O`, suite 2072): M2o (the counter back in
`@State`) → 2.13 at its set-up `require draws.count >= 5`; M2o-b (the passed
counter incremented but the header reading a separate never-written
`@State`, the `4a8bbed` shape) → 2.13 at `shown >= 4 && shown <= draws.count`;
M2p (`SurfaceTargetTable.update`'s size-change branch disabled) → 2.14 (1
issue) and `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating` (5);
`MV-O` item 2 reverted (`didDraw` back inside the draw loop, before commit) →
**nothing** (§6).

**Lane 3** (`MV-P`, `Backends/SDL`, 23 + 46):

| mutation | reddens |
|---|---|
| M3a surface quads not appended | 3.1–3.5 (the bridge's `images_valid` refuses the frame) |
| M3b texture-index offset forgotten | 3.1 |
| M3c draws after the composite (next frame's buffer) | 3.1–3.5 |
| M3c as spec §8 spelled it (into the submitted buffer) | **hangs the process** — respelled, `MV-P` item 3 |
| M3d a fresh table every frame | 3.2–3.5 |
| M3e `release` does nothing | 3.3, 3.4 |
| M3f a new target cleared in its own submitted buffer | 3.4 (the submission clause alone) |
| M3f′ `retire_fence` → `release_fence` | 3.4 (fence clause), `backToBackFramesNeverReleaseAnUnsignaledFence`, `imageTexturesPersistAndAreReleasedWhenAbsent` |
| M3g a fresh command buffer for the context | 3.1–3.5 |
| M3h `.surface` mapped to `.image` in `ReplayFixture` | 3.6 (exit status and message) |

**Lane 3's review round** (`MV-Q`, from `4d53473`/`c8518bc`, 23 + 48): V2b
(every quad's `bounds`/`contentMask` x += 10) → 3.1 ((20, 10), (10, 19),
(20, 30)) and 3.7; V2c (y += 5) → 3.1 and 3.7; the verifier's extra x += 1 and
y += 1 → 3.1 and 3.7 each (a one-device-pixel shift is caught); V7
(`create_target(renderer, 1, 1)`) → 3.7 (12 issues); V7′ (width and height
swapped) → 3.7 (10 issues); V5 (the new-target clear removed) → 3.8 on macOS,
32 issues, every sample (255, 0, 255, 255) — Metal API Validation's fill for an
uninitialised texture (§6).

**Typecheck guards, mutated red once** (spec §8): G1.1 (a misspelt
`RedrawPolicy.continuous` in the fixture), G1.2 (a default `finishFrame` in a
scratch copy), G2.1 (`renderPassDescripter`).

## §6 Green mutations and pins that prove less than they look

- **`MV-O` item 2 reverted reddens nothing.** `didDraw` after `commit()` rather
  than before it is the fix for a failed frame (`Renderer.encode` throws only on
  a buffer or encoder allocation failure and no test injects one), so no test
  can see which order was built; it is pinned by reading, not by a test. A
  target created in a failed frame comes back `isNewTarget == false` with
  unwritten contents for one frame — accepted, stated in `MV-O` item 2.
- **A new target's clear to transparent on Metal is unpinned by pixels.** Fresh
  private memory reads zero either way (spec §8 says so). On SDL, **V5 is
  caught only on macOS under Metal API Validation** (`swift test` enables it);
  without validation Metal may hand back zeros, and **V5 is equivalent on Mesa
  lavapipe** (`MV-Q` item 4: 3.8 stays green with the clear removed). The clear
  stays: SDL3 documents a new texture's contents as undefined. The
  re-verification did not re-run V5 on Linux; the lavapipe reading is lane 3's
  own container run.
- **Test 2.8 and 2.10 read the trap's own message.** M2j (the status
  precondition dropped) first left 2.8 green: Metal aborts a doubly committed
  command buffer by itself later in the same frame, so a bare `.failure`
  cannot tell MetalUI's check from Metal's (`MV-N` item 6).
- **A mutation that changes a stored property's layout needs `swift package
  clean`** (M2h): built incrementally it segfaulted 2.7 with impossible counter
  readings — CLAUDE.md's `direct field offset` hazard, not a finding.
- **The `SurfaceParity` literal is exact on purpose**: over opaque black every
  expected channel is an integer (`(100, 50, 20, 255)` at A's centre), so no GPU
  rounding ambiguity enters the literal lane 3 copies into another package.
- **Test 1.23's scenario is not the reviewer's** (the live surface and its ghost
  in one scene does not arise — an insertion during a removal deletes that
  key's ghost); it pins that the re-inserted surface gets a new target rather
  than the one the ghost kept alive.

## §7 Demo comparison and looks

- **Fourteen offscreen images, `docs/probes/demo-pixels/compare.sh` from
  `330f02b` to this record's head: 0 differing pixels and `scene identical` in
  all fourteen**, controls non-zero (re-taken at the Record phase; lanes 2 and
  3 each took it too). The new demo is its own tree and is in none of the
  fourteen; `Expected.swift` is unedited.
- **The real-window capture was not taken.** The lock probe read
  `CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1` at lane 3's close and
  at the Record phase, so `capture.sh` was not run; the last unlocked reading
  remains 2026-09-30. The SDL demo ran five seconds under
  `METALUI_METALVIEW_DEMO=1` without a crash (screen locked — not a look).
- **Owed, new here — `docs/verification/human-checks.md` group P, none
  performed (an agent cannot)**: P1 the on-screen look (a rounded, moving
  shader field, the label over it, no flicker or black first frame); P2
  continuous smoothness at the display's rate; P3 idle when paused (the display
  link stops — Activity Monitor); P4 on-demand redraw (only the swatch changes
  with the stepper); P5 live resize (no stretch, no blank frame); P6 Retina vs
  1× scale and moving between displays; P7 colour and gamma against the flat
  tints; P8 the same demo on SDL (macOS and, if available, Linux and Windows).
  Nothing in the suite sees the display link's rate, tearing, a real window's
  resize or a second display.

## §8 Hazards

- **Counters do not cross a package boundary** (`MV-L` item 2): `package` is per
  package, so `SurfaceTargetTable`'s counters serve the root package's tests
  and `SDLWindowRenderer` keeps its own.
- **Never release an SDL fence the GPU has not signalled** holds by
  construction here: a surface adds no submission and every draw rides the
  frame's one command buffer (`MV-H` item 2). A new bridge helper that submits
  its own buffer breaks it — test 3.4 counts submissions.
- **The SDL test process on macOS can hang if a draw is recorded into a command
  buffer `mui_renderer_finish` has already submitted** (M3c as first spelled,
  `MV-P` item 3): no summary line after ~20 minutes. A new SDL surface test
  still arms `armMainRunLoopExitCheck()`.
- **A C enum's `rawValue` is `Int32` on Windows**: the bridge returns plain
  `uint32_t` where it can, and tests convert explicitly; only Windows CI can see
  a miss (it confirms on push).
- **A never-written `@State` of reference type is re-seeded every build** — the
  demo's draw counter was lost to it (`MV-O` item 1). A draw closure must never
  hold state in `@State` it only mutates through a reference; pass the object in
  from outside the content closure (the demo's `MetalViewDemoDraws`).
- **`finishFrame` runs after `withObservationTracking` returns**, so a read
  inside `draw` is untracked (`MV-A` item 4, held at the critic round): what the
  drawing depends on must be passed as `value:`.
- **A renderer ignoring `surfaces`** (an external `WindowRenderer` conformer)
  composites nothing for surface runs and draws no GPU work — a blank viewport
  with no error; the requirement is defaultless so the conformer must say so
  (`MV-F` item 1, guard G1.2).

## §9 The Record phase's own close (2026-10-02, `MV-R`)

1. **Suite, clean.** After `swift package clean`, `swift build --build-system
   native --build-tests`: 0 `error:`, one `warning:` (SwiftPM's deprecation
   notice). The unfiltered `swift test --build-system native --no-parallel`
   printed **`Test run with 2072 tests in 3 suites passed after 109.875
   seconds`**, the `FR-J no-argument frame: succeeded=true` line present (the
   guards ran). Goldens 0 (`find Tests/MetalUILayoutTests -name "*.json" | wc -l`
   reads 0). Guards 125 → 128, counted by file: 2 in
   `GPUSurfaceCompileGuards` and 1 in `MetalViewCompileGuards`.
2. **The inventory check failed on arrival** — twelve `UNMAPPED` rows, every
   `GPUSurface`/`MetalView` declaration in `Sources/MetalUI` (the lanes' other
   new declarations are claimed by the existing `MetalUIScene`, `MetalUIPlatform`,
   `MetalUIRender` and `MetalUIDemoContent` rules). A new family `gpu-surface`
   (class A: probe `swiftui-metal-view.swift` arm `G1`, test
   `aSurfaceAnswersItsProposalAndTenOnANilAxis`, divergence 103, rulings `MV-A`
   `MV-B` `MV-G` `MV-I`) and two `M` rows close it; `zsh
   docs/probes/closeout-inventory-check.sh` and `closeout-undocumented.sh` now
   print nothing, and `closeout-public-api.tsv` is re-recorded: **1940 → 1997**
   public declarations in **100** families (99 + 1).
3. **Docs**: `CLAUDE.md` (a "GPU surfaces" rules paragraph, the `MV-` prefix, the
   counts, the divergence count) with `AGENTS.md` byte-identical;
   `docs/divergences.md` (70 live, 103 added, next label 104 — written by lane
   1, verified here), `docs/migration.md`, `docs/api-overview.md`,
   `docs/verification/human-checks.md` group P; the design spec's status and a
   dated note on §4.3 and §7.7 (§10); `docs/record/README.md`, `03`, `04`, `05`;
   the top-level `README.md`.
4. **Pixels**: §7.

## §10 Deferrals, with owners

- **A never-written `@State` of reference type is re-seeded every build**
  (`MV-O` item 1). SwiftUI keeps the first initial value for a view's lifetime
  (its documented `@State` contract; **not probed here**). Pre-existing, an
  id-path/retention behaviour this branch must not move. **Owed: a probe arm,
  and, if SwiftUI's answer is confirmed, a divergence row or a fix. No label
  was taken** — filing a row without a probe would be an unprobed SwiftUI
  claim. Owner: none yet.
- **Not built** (`MV-F` item 6, `docs/divergences.md` "Not offered", owner
  none): a depth attachment, EDR / `rgba16Float` targets, a per-element error
  channel, device-loss rebuild, `NSViewRepresentable`, direct-mode drawing into
  MetalUI's own pass, `IOSurface`/`CVPixelBuffer` content (spec §7.7's "later"),
  an SDL replay fixture holding a surface (a fixture cannot hold app GPU work).
- **The image texture cache is still per `Renderer`, shared across windows**
  (record §61 §6 item 4): unchanged, its note still owed to the first
  multi-window **image** consumer. Surfaces have their own per-window answer.
- **One limit, 8192**, for both renderers (the SDL bridge's texture limit;
  Metal's is 16384): a larger element samples its target stretched.
- **Linux/Windows CI** confirm on push: the new portable
  `SurfaceTargetTableTests` (the Linux/Windows `MetalUICrossPlatformTests` count
  moved 14 → 21 (seven tests): the branch checker measured **199 + 22 + 21** in
  `swift:6.4-noble` at `554243a`, 0 `error:`/`warning:`), the `Backends/SDL` surface tests on Vulkan and D3D12 (lane 3
  measured Linux/lavapipe 23 + 46 at `20ce04f`/`4d53473`; `c8518bc` did not
  change `Sources/`), and the C-enum conversions.
- **The human looks**: group P (§7). An agent cannot perform them.

## §11 Merge with master (2026-10-02, `95234db`, the app icon)

`origin/master` at `95234db` (PR #38, the application icon, record §70,
rulings `AI-A`…`AI-N`) merged into `feat/metal-view` at `5f5dfea`.

1. **What conflicted.** No Swift source, test fake, manifest or demo file
   conflicted: `Platform.swift`, `Tests/MetalUITests/Fakes.swift`, both demos'
   `main.swift` and `SDLBridge.c`/`.h` auto-merged, so every fake carries both
   new requirements (`Platform.setApplicationIcon(_:)`, `AI-B`, and
   `WindowRenderer.finishFrame(scene:atlas:surfaces:)`, `MV-F` item 1) and the
   build proved it. Nine documents conflicted, each resolved as a union:
   `CLAUDE.md`/`AGENTS.md` (both prefixes — `AI-` next `AI-O`, `MV-` next
   `MV-S`; the counts bullet re-taken; the defaultless-requirement bullet now
   names `finishFrame(scene:atlas:surfaces:)` beside `setApplicationIcon(_:)`),
   `docs/api-overview.md` (both sections), `docs/migration.md` (both rows),
   `docs/record/README.md` (§70 then §71), record §03 (both dated sections),
   `docs/verification/human-checks.md`, `closeout-inventory-map.tsv` (both
   families, `gpu-surface` and `app-icon`) and `closeout-public-api.tsv`
   (re-recorded by `closeout-public-api.sh`: **2000** declarations — 1997 + the
   app icon's three — in **101** families; `closeout-inventory-check.sh` and
   `closeout-undocumented.sh` print nothing).
2. **Group O → P.** Master's app icon keeps human-checks group **O** (O1–O4);
   this branch's MetalView group is now **P** (P1–P8). Moved: the group
   heading and items, the "Before you start" variant line, record §03's
   MetalView section, this record, the spec's status line, the decisions
   doc's two citations, `docs/record/README.md`'s §71 row, the top-level
   `README.md`, and `CLAUDE.md`'s "groups A–P". The demo sources cite no
   MetalView group letter; every surviving `O1`…`O4` in `Sources/` is the app
   icon's (or an unrelated probe arm's).
3. **Counts after the merge**, after `swift package clean`:
   `swift build --build-system native --build-tests` 0 `error:`, one
   `warning:` (SwiftPM's deprecation notice); `swift build --build-tests` 0
   `warning:`, 0 `error:`; unfiltered `swift test --build-system native
   --no-parallel` printed **`Test run with 2093 tests in 3 suites passed after
   110.170 seconds`** (2072 + master's 21), the `FR-J no-argument frame:
   succeeded=true` line present. Guards **129** (128 + `AppIconCompileGuards`'
   one). `Backends/SDL` (`PKG_CONFIG_PATH=$PWD/.accesskit`): `swift build --build-tests` 0 `error:`, `swift test --no-parallel` **23 + 55** (the branch's 23 + 48 plus the app icon's seven `SDLIconTests`; master read 22 + 48). Pixels: `docs/probes/demo-pixels/compare.sh <scratch> 95234db 4157f76` (the merge commit) reads **0 differing pixels and identical scenes in all fourteen** images, the controls non-zero where they must be (light vs dark 1 048 576, default vs modal 1 031 003, prod default vs modal 491 221).
