# MetalView — the app-owned GPU surface — decisions

Rulings for the app-owned GPU surface (user request 2026-10-01; **not a plan
task** — new feature work after plan task 15, like drag and drop). The binding
design spec's §7.7 ("`MetalView` — app-owned rendering") calls it "the reason
a Metal-native UI framework is worth building at all"; it was never built —
before this branch the only mention in `Sources/` was a doc comment in
`StateTable.swift` (line 89) that this doc refutes (`MV-E` item 6). Spec:
[`specs/2026-10-01-metal-view-design.md`](specs/2026-10-01-metal-view-design.md).
Record: `../record/69-metal-view.md`. Evidence:
[`../probes/swiftui-metal-view.swift`](../probes/swiftui-metal-view.swift)
(**new**; arm ids `P…` controls, `G…` sizing, `C…`/`D…` compositing in a real
on-screen window, `R…` when `Canvas` re-runs; its header carries the recorded
output and the reading).

Prefix **`MV-`**, lettered. **Next unused: `MV-P`.** (This line moves in the
commit that appends a ruling; read the last `## MV-` heading.)

Branch `feat/metal-view` from `330f02b` (master: drag and drop merged, PR
#36). Baseline at `330f02b`: **2028 tests in 3 suites, 0 goldens**, 69 live
divergences (next label 103, `docs/divergences.md`).

**Carried items.** No decisions doc's "Carried…" section addresses an
app-owned surface, `MetalView`, a draw context or a render target:
`grep -rn -i "MetalView\|app-owned\|PaintSurface\|GPU surface" docs/superpowers docs/record Sources docs/*.md`
reads four hits outside the design spec, three in M0/M1 plans deferring it to
"M5" and one in the animation spec ("There is no `MetalView` and no draw
context yet — that is M5"), plus `StateTable.swift:89`. None is a ruling; all
are discharged here. (No carried item addresses plan task 10 in any way this
feature touches — `2026-09-25-data-and-scrolling-decisions.md:898` already
records that none names task 10.)

**How the probe reads, in one paragraph.** The screen was unlocked
(`displayAsleep main: 0`, no `CGSSessionScreenIsLocked` line, scale 2.0), so
groups C and R ran in a real window ordered front and captured by id. `G`:
`Canvas` sizes exactly like `Color` (P1) — the proposal, 10 on a nil axis,
inf at inf; an `MTKView` representable answers 0 on a nil axis. `C1`–`C3`
against `P2`: SwiftUI composites an app's Metal layer through the same clip
and opacity as any view (C2's rounded corner reads the white background,
C1's — unclipped — the surface's own red; C3's centre is the half mix).
`D1`: the drawable is the bounds × the backing scale (100×60 pt → 200×120 px
at 2.0). `R0`–`R3`: an idle `Canvas` never re-runs; a value it reads re-runs
it (R2, the positive control P3); an unrelated change re-runs a `Canvas` whose
declaring body re-ran (R1) but not one in its own child view (R3). Colours
read through the capture's colour space, so only relations are claimed.

---

## MV-A — the surface: a portable `GPUSurface` leaf with a per-backend draw context, and `MetalView` as its Apple spelling; invalidation is a `value:`, not a handle

**Ruling.**

1. **`GPUSurface`** (`Sources/MetalUI/GPUSurface.swift`, portable, every
   platform) is a `ProposalElement` leaf:
   ```swift
   public struct GPUSurface: ProposalElement {
       public init(redraw: RedrawPolicy = .onDemand,
                   draw: @escaping @MainActor (any GPUSurfaceContext) -> Void)
       public init<V: Hashable>(redraw: RedrawPolicy = .onDemand, value: V,
                                draw: @escaping @MainActor (any GPUSurfaceContext) -> Void)
   }
   ```
   `draw` receives the backend's context as the portable protocol
   `GPUSurfaceContext` (`MV-F`); app code downcasts to the backend it encodes
   for (`MetalDrawContext` on the Metal renderer, `SDLGPUDrawContext` on the
   SDL one) or uses the protocol's one portable operation, `clear(red:green:blue:alpha:)`.
2. **`MetalView`** (`Sources/MetalUI/MetalView.swift`, under
   `#if canImport(MetalUIRender)`, so macOS only, `PC-A`'s second list) is
   the spec's name with a typed context:
   `MetalView(redraw:draw: (MetalDrawContext) -> Void)` and
   `MetalView(redraw:value:draw:)`. It is a thin wrapper building a
   `GPUSurface` whose closure downcasts. **A `MetalView` handed a context that
   is not a `MetalDrawContext` traps** naming this ruling and `GPUSurface`
   (the one way to reach it is `Backends/SDL` on macOS, whose SDL GPU device
   is not the app's Metal device; drawing nothing silently would be a blank
   viewport with no error).
3. **No `id:` parameter** (the spec's sketch had one): identity is structural
   and `.id(_:)` already works on every element group (`ID-G`).
4. **No `MetalViewInvalidation` handle** (the spec's `.version(n)`): the
   spec needed it because "reads inside `draw` are not tracked" — still true
   (`draw` runs in the renderer, after the tracked build, `MV-F`) — but a
   `value:` read during the build IS tracked: a `@State` or `@Observable`
   counter passed as `value:` dirties the window when it changes, and the
   surface redraws when its value differs from the one it last drew
   (`MV-G`). To invalidate from anywhere, bump such a counter. The spelling is
   SwiftUI's own shape for "react to this value" (`.animation(_:value:)`,
   `.onChange(of:)`), and it is one type fewer.

**Evidence.** Spec §7.7's sketch. SwiftUI has no surface type to copy; its
analogues are `Canvas` (a leaf with a drawing closure), `TimelineView`
(a redraw schedule) and an `NSViewRepresentable` over `MTKView` (probe groups
G, C, R).

**Rejected.** A generic `GPUSurface<Context>` (one type per backend makes a
portable tree name its backend). Separate `MetalView`/`SDLView` elements with
no portable type (the demo tree and every portable test would fork). A handle
class (`value:` covers it, above).

**Cost if wrong.** A downcast at the top of every closure; if a later backend
wants a typed portable context, `GPUSurfaceContext` grows requirements —
additive for callers, breaking only for context conformers, which live in
this repository.

---

## MV-B — sizing is `Canvas`'s: the proposal on each finite axis, 10 on a nil axis

**Ruling.** `GPUSurface` answers its proposal on each axis, 10 where the
proposal is nil — exactly `Color`/`Rectangle`'s answer (`Shape.sizeThatFits`'
default, `TE-AC`). An infinite proposal is answered with the proposal like
every greedy leaf (`CN-F`); layout stores no infinite rect (`SA-K`), so a
surface placed at an infinite proposal is resolved by its parent exactly as a
`Color` is.

**Evidence.** Probe G1 (`Canvas`: nil×nil → 10×10, 0×0 → 0×0, 50×30 →
50×30, 300×200 → 300×200, inf → inf), G3 (`TimelineView(.animation)` around
it: the same), P1 (`Color`: the same). G2 (`MTKView` representable) answers
0×0 at nil×nil — the separating arm: the two SwiftUI analogues differ only on
a nil axis.

**Rejected.** G2's 0. `Canvas` is the SwiftUI-native drawing leaf a surface
replaces; a nil-axis 0 would make a surface vanish inside a `fixedSize()` or
an unproposed stack where every MetalUI shape shows.

**Cost if wrong.** A surface in a nil-proposed axis is 10 pt where the
author wanted 0 or something else; `.frame` fixes it either way.

---

## MV-C — the scene primitive: `PrimitiveKind.surface`, an `MUIImage` record per quad and an opaque `SurfaceTarget` (id + device-pixel size); `MetalUIScene` stays Metal-free

**Ruling.**

1. `MetalUIScene` gains `PrimitiveKind.surface`, `SurfaceID` (a window-minted
   `UInt64`), `SurfaceTarget` (`id`, `width`, `height` in device pixels, both
   > 0 or a trap), `Scene.surfaces: [MUIImage]` (the quads) and
   `Scene.surfaceTargets: [SurfaceTarget]` (one per distinct id, in first-use
   order; each quad's `texture` field indexes it), and
   `insert(_ quad: MUIImage, surface: SurfaceTarget, layer:)`. **No Metal,
   SDL or closure type enters the scene** (`PS-A`): a target is resolved to a
   GPU texture by each renderer's own table (`MV-E`).
2. **The quad is an `MUIImage`** — bounds, content mask, mask corner radii,
   opacity, filter, order: the 64-byte record both shader languages already
   read. No new shader struct and **no shader change on either renderer**: a
   surface run is drawn by the image pipeline with the target bound as its
   texture (`MV-D`). `Scene.finalize()` breaks a surface run where its target
   changes, exactly as an image run breaks where its texture changes, so the
   run count stays the draw-call count; `isEmpty`, `clear()`, `highestLayer`
   and `layer(of:at:)` read the new arrays. The side tables become **eight**
   plain `[Int]` arrays (`sceneSideTablesArePlainIntArraysThatKeepCapacityAcrossClear`'s
   literal moves 6 → 8 — a T row naming this ruling).
3. **Public break, migration note**: `PrimitiveKind` gains a case, so an
   exhaustive `switch` outside the package needs a `.surface` arm (every
   in-repo switch gains one: `Renderer.encode`, `SDLWindowRenderer`,
   `ReplayFixture`, `Scene` itself, three tests).
4. **A replay fixture cannot record a surface** (`FixtureRun.init(scene:)`
   traps on `.surface`, naming this ruling): its content is app-defined GPU
   work no fixture holds. No recorded fixture and no tree `DemoCapture`
   rebuilds contains one; parity for surfaces is a known fill drawn by a
   test callback on each backend (`MV-H` item 4).

**Rejected.** Folding surfaces into `Scene.textures` as a second
`ImageTexture` source (a scene-level enum): it would change the image cache's
key and release rule, which `TE-AF` pins, and blur two lifecycles that differ
(an image texture is immutable CPU pixels uploaded once; a target is GPU
memory rewritten in place). A new shader primitive: every field it would need
is already `MUIImage`'s.

**Cost if wrong.** A second texture-sampling kind costs one more run break
per surface — one draw call per surface, which the spec's §7.3 already
budgets.

---

## MV-D — compositing: exactly an `Image`'s — the active clip, its radii, opacity, layer, transitions and drag preview — through the existing image pipeline on both renderers

**Ruling.** `Frame.drawSurface` is `Frame.drawImage`'s arithmetic line for
line (translated by `activeOffset`, scaled, masked by `activeClip` with its
radii, `activeOpacity`, `activeLayer`), routed through
`insertThroughTransitions` with a new `CapturedPrimitive.surface` case
mirrored into every switch over it (`TransitionEffect.apply`,
`withInnerMask`, `DragSession`'s `bounds`/`replayed`, `Frame`'s insert). So a
`.clipShape(RoundedRectangle(...))`, a `.cornerRadius`, an `.opacity`, a
`.transition(...)` ghost and a drag preview all treat a surface as they treat
an image. The filter is **linear**: a quad covering exactly its target's
pixels samples texel centres exactly, and a `.scale` transition (which moves
the quad, never the target, `MV-E` item 2) resamples smoothly.

**Premultiplied, gamma space.** The image pipeline composites a texel as
premultiplied source-over in gamma-encoded sRGB (`TE-AF`, §7.8). A target is
`bgra8Unorm`, never `_sRGB`; **the app writes premultiplied colour**, which
the context's `clear` takes as given and `MetalDrawContext`'s doc states.

**Evidence.** Probe C1–C3 against P2 (SwiftUI composites an app's Metal
surface through clip and opacity like any view; C4 a `Canvas` the same).

**Rejected.** Compositing in a separate pass after the scene (the spec's
"interleaved, in order" frame graph: a surface sits at its own z-order, under
later siblings and over earlier ones).

**Cost if wrong.** None that a renderer can see: the record is the image
record and the pipeline is the image pipeline, pinned by `TE-AF`'s tests and
the parity harness.

---

## MV-E — the render target lifecycle: a portable `SurfaceTargetTable` owned per window by its `WindowRenderer`; created and resized at the element's device-pixel size, reused across frames, released when no frame references it

**Ruling.**

1. **One portable implementation of the lifecycle**,
   `SurfaceTargetTable<Handle>` (`MetalUIPlatform`), generic over the
   backend's texture handle, so the Metal and SDL renderers cannot drift
   (CLAUDE.md "A copy of a pinned implementation is unpinned"). Each frame
   it takes the scene's `surfaceTargets` and the frame's draw requests, calls
   the backend's `create`/`release` closures, and returns the requests to
   draw this frame, in request (= paint) order, each with its handle and
   whether its target is new:
   - a request whose id has **no entry** creates one (the target is new);
   - a request whose pixel size **differs** from its entry's releases the old
     handle and creates a new one (new);
   - an entry **no scene target references** is released (an element that
     left, was hidden, scrolled out of a `List`'s window, went fully clipped
     or transparent, `MV-G`);
   - an entry referenced **without a request** (a transition ghost, a drag
     preview) is **kept and not drawn**, so a ghost shows the last contents;
   - a reference with no entry and no request creates nothing, and its run
     draws nothing.
   Two requests naming one id in one frame trap (one element, one paint) —
   a table invariant `Frame` guarantees by keying `SurfaceRegistry` on
   (`GlobalElementID`, occurrence), `MV-L` item 1.
   Counters (`package`): `createdCount`, `releasedCount`, `drawnCount`,
   `liveCount` — readable by the root package only; `SDLWindowRenderer`
   counts for itself, `MV-L` item 2.
2. **The device-pixel size** is `Int((points × scale).rounded())` per axis,
   computed from the element's **laid-out** bounds before any transition
   effect (a `.scale` transition never reallocates), clamped to 8192 (the SDL
   bridge's texture limit, `mui_renderer_create_texture`; Metal's is 16384 —
   one limit for both, documented; a larger element samples its target
   stretched). A side that rounds to 0 emits nothing (`MV-G`).
3. **Per window.** Each `WindowRenderer` owns its table (`MetalWindowRenderer`,
   `SDLWindowRenderer`; both are per window), and `SurfaceID`s are minted per
   window, so two windows never evict each other's targets. **This is the
   per-window answer for surfaces that record §61 §6 item 4 asks of image
   consumers**; the image texture cache itself stays on the shared
   `Renderer`, unchanged, its note still owed to the first multi-window image
   consumer (out of this branch's scope).
4. **Format and storage.** `bgra8Unorm` (§7.8; never `_sRGB`), usage render
   target + shader read; Metal `.private` storage; SDL
   `SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM` with `COLOR_TARGET | SAMPLER` (the
   bridge's existing `texture(…, target: true)`).
5. **A new target is cleared to transparent** in the frame's command buffer
   before its first draw, so an app that draws nothing (or a partial
   viewport) composites transparent, never undefined memory. Unpinned by
   pixels on Metal (fresh private memory usually reads zero either way —
   stated in the spec's test table, not hidden).
6. **No double buffering** (spec §7.7 asked for it "against the §7.4 ring"):
   the app's pass and MetalUI's composite are GPU work in **one command
   buffer** per frame on **one queue** (Metal) / one device's submission order
   (SDL GPU, which synchronises a texture used across command buffers when
   not cycled), so frame N+1's write of a target is ordered after frame N's
   sample of it by the API, not by a second texture. The spec's ring and
   semaphore were removed long ago (CLAUDE.md "Renderer: No semaphore"). **The
   `StateTable.swift:89` doc comment and spec §4.3's list ("`MetalView`
   render targets … live in a side table on the window keyed by
   `GlobalElementID`") are refuted**: a target is GPU state the renderer owns,
   keyed by a window-minted `SurfaceID`; the window-side map from
   `GlobalElementID` to `SurfaceID` is a `SurfaceRegistry` beside
   `AnimationStore`, **not** a `StateTable` entry — the seven reserved slot
   names do not move (`theSevenRetentionSlotsAreMutuallyDistinct`). Lane 1
   corrects the comment; the Record phase adds a dated correction block to
   the design spec's §4.3 and §7.7.

**Rejected.** Targets in `StateTable` (the spec's §4.3/§7.7): the state table
is swept on identity rules a GPU resource does not follow (a `List` row out of
its window keeps `@State` for two generations, `TB-AH`, but a target there
does no work and should not hold GPU memory). A pool per frame (the spec
itself rejects it: an on-demand surface must keep last frame's contents).

**Cost if wrong.** Memory: one target per visible surface per window. A
surface that blinks in and out of a `List`'s window reallocates and redraws
on each return — the price of "offscreen does no GPU work".

---

## MV-F — the draw contract: a defaultless `WindowRenderer.finishFrame(scene:atlas:surfaces:)`; every surface draws, on the main actor, into the frame's own command buffer **before** the scene is encoded; the app must not commit, present, wait or end the buffer

**Ruling.**

1. **The seam.** `WindowRenderer`'s requirement becomes
   `func finishFrame(scene: Scene, atlas: GlyphAtlas, surfaces: [SurfaceDrawRequest]) -> Bool`,
   **with no default implementation** (`EV-AB`'s reason: a renderer that
   forgets surfaces fails to compile rather than drawing a blank viewport).
   A protocol extension keeps `finishFrame(scene:atlas:)` callable (it passes
   `[]`), so every existing **caller** compiles; an external **conformer**
   adds the parameter (migration note). `Window.drawFrameIfNeeded` passes the
   frame's `surfaceRequests`.
2. **`SurfaceDrawRequest`** (`MetalUIPlatform`): `target: SurfaceTarget`,
   `scaleFactor`, `time` (the frame's `timestamp`, the display link's target
   presentation time, §4.4), `policy: RedrawPolicy`, `value: AnyHashable?`,
   `draw`.
3. **When it runs.** Inside `finishFrame`, after `beginFrame()` acquired the
   drawable and its command buffer, after the table resolved targets
   (`MV-E`), **before** MetalUI's own render pass is begun — so no MetalUI
   encoder is open while app code runs, and the app's pass completes (in GPU
   order) before the composite samples it. Order between surfaces is paint
   order. On Metal: `MetalWindowRenderer.finishFrame` — atlas upload, clears
   of new targets, each draw, then `Renderer.encode`, present, commit. On
   SDL: between `mui_renderer_begin` and `mui_renderer_finish`, into
   `r->cmd`.
4. **What it receives** (`GPUSurfaceContext`, `@MainActor`): `pixelSize:
   Size<DevicePixels>`, `scaleFactor`, `time`, `frameIndex` (the renderer's
   count of finished frames), `isNewTarget`, and `clear(red:green:blue:alpha:)`
   (premultiplied, gamma space; one load-op-clear pass). `MetalDrawContext`
   (`MetalUIRender`) adds `device`, `commandBuffer` (the frame's own, the
   spec's "SAME buffer as the UI"), `target: any MTLTexture` and
   `renderPassDescriptor(loadAction:clearColor:)`. `SDLGPUDrawContext`
   (`MetalUISDL`) adds `device`, `commandBuffer` and `target` as
   `OpaquePointer`s (`SDL_GPUDevice *`, `SDL_GPUCommandBuffer *`,
   `SDL_GPUTexture *`) for app code that imports SDL3 itself.
5. **The app must not** commit, enqueue, present, wait on, cancel or submit
   the command buffer, and must end every encoder/pass it begins before
   returning. **On Metal a violation traps**: after each draw the renderer
   checks `commandBuffer.status == .notEnqueued` and traps naming this
   ruling (pinned by an exit test). **On SDL it is undetectable** (SDL3 has
   no command-buffer state query) and is stated on `SDLGPUDrawContext`'s doc
   as undefined behaviour.
6. **Not offered** (each a row in `docs/divergences.md`'s "Not offered"):
   a depth attachment (the spec's `depth: MTLTexture?` — the app allocates
   its own, sized from `pixelSize`); EDR / `rgba16Float` targets (§7.8's EDR
   bullet); a per-element error channel (spec §7.7 — an encoding error fails
   the frame's command buffer, which Metal's validation reports); device-loss
   rebuild (spec §3.2); hosting an arbitrary `NSView` (`NSViewRepresentable`).

**Rejected.** Running `draw` in paint (the spec's §4.4 tracked build): paint
has no command buffer, and a `Scene` must stay data. Carrying the requests in
the `Scene` (it is `Sendable` portable data compared byte for byte by
`DemoCapture`; a closure is neither). A second, separate
`drawSurfaces(_:)` requirement called between `beginFrame` and
`finishFrame` (two calls with an ordering contract the type does not state).

**Cost if wrong.** An app that commits the buffer on SDL corrupts the frame
with no message; Metal catches it.

---

## MV-G — redraw policy: `.onDemand` draws on a new target or a changed `value:`; `.continuous` draws every frame and keeps the display link awake through `noteActiveAnimation()`; a hidden, zero-size, fully clipped or transparent surface does no GPU work (divergence 103)

**Ruling.**

1. `public enum RedrawPolicy: Sendable, Hashable { case onDemand, continuous }`
   (`MetalUIPlatform`; the spec's names).
2. **`.onDemand`** draws when the target is new (first sight, a resize, a
   rescale that changes the pixel size — a rescale at an unchanged pixel size
   also redraws, the scale is part of the entry) or when the request's
   `value` differs from the value it last drew. A window redraw for any other
   reason — hover, a caret, another pane — composites the target's last
   contents with no GPU work for it (spec §7.7's "the common case").
3. **`.continuous`** draws every frame the element paints, and its paint
   calls `Frame.noteActiveAnimation()` so `hasActiveAnimations` keeps the
   display link running — **never** `requestAnotherFrame()`/`wantsAnotherFrame`
   (CLAUDE.md "Animation": never raise both). A continuous surface that stops
   painting lets the link pause on the next frame.
4. **No GPU work** when the surface emits nothing: its device-pixel size has a
   zero side, its translated bounds do not intersect `activeClip`,
   `activeOpacity` is 0, or it is not painted at all (`.hidden()` on a legacy
   wrapper — `display: none`; an `if` gone false; a `List` row out of its
   window). No quad, no request, and its target is released at that frame
   (`MV-E` item 1). Coming back is a new target, so it redraws.
5. **Divergence 103, added, kept, owner none.** SwiftUI re-runs a `Canvas`
   whenever its declaring view's body re-runs, even for a change it does not
   read (probe R1), because a closure is a new value it cannot compare; it
   does not re-run one whose own view's inputs are unchanged (R3), nor an
   idle one (R0), and re-runs on a read value (R2). MetalUI rebuilds the
   whole tree every dirty frame, so "the declaring body re-ran" is every
   frame: an `.onDemand` surface redraws only for its target or its `value:`
   — R0, R2 and R3's answers, not R1's. Remedy: pass what the drawing reads
   as `value:`.

**Evidence.** Probe R0–R3; D1 (an `MTKView`'s default, `isPaused = false`,
draws continuously — 128 draws in 2 s — the shape of `.continuous`).

**Cost if wrong.** An `.onDemand` surface whose author forgot `value:` shows
stale content until a resize; `.continuous` is always correct and costs a
frame per tick.

---

## MV-H — portability: the portable half is `MetalUIScene` + `MetalUIPlatform` + `MetalUI`; the Metal half is `MetalUIRender` (+ `MetalView` on macOS); the SDL half is `Backends/SDL`, compositing through the image pipeline and checked against the Metal renderer by a known fill

**Ruling.**

1. Layering: `SurfaceID`/`SurfaceTarget`/`PrimitiveKind.surface` in
   `MetalUIScene` (imports only `MetalUIShaderTypes`, `PS-A`);
   `RedrawPolicy`, `GPUSurfaceContext`, `SurfaceDrawRequest`,
   `SurfaceTargetTable` in `MetalUIPlatform` (imports only `MetalUICore`,
   `MetalUIScene`); `GPUSurface`, `SurfaceRegistry`, `Frame.drawSurface` in
   `MetalUI` (portable, `XP-A`); `MetalDrawContext` in `MetalUIRender`;
   `MetalView` in `MetalUI` behind `#if canImport(MetalUIRender)`;
   `SDLGPUDrawContext` in `MetalUISDL`. `MetalUILayout` is untouched.
2. **The SDL bridge** gains four C functions (five since `MV-L` item 4, which adds `mui_renderer_submission_count`) and no change to
   `mui_renderer_finish`: `mui_renderer_device`, `mui_renderer_command_buffer`
   (valid between begin and finish), `mui_renderer_create_target(r, w, h)`
   (no upload, so **no submission and no fence**, unlike
   `mui_renderer_create_texture`), `mui_gpu_clear_texture(cmd, texture, r, g,
   b, a)` (one render pass, `LOADOP_CLEAR`, ended at once). `SDLWindowRenderer`
   appends each surface quad to the image array it already uploads (texture
   index offset by `scene.textures.count`, run start offset by
   `scene.images.count`) and passes `.surface` runs as image runs — so the
   bridge's `images_valid` check, packing and draw loop, and the HLSL, are
   unchanged. Released targets go through `mui_renderer_release_texture`
   (SDL frees them once no submitted frame uses them). **The fence rule
   holds by construction**: a surface adds no submission; every surface draw
   rides `r->cmd`, submitted once by `mui_renderer_finish` (and
   `backToBackFramesNeverReleaseAnUnsignaledFence`' sibling pins it for
   surface frames).
3. **Windows C-enum hazard**: any SDL enum value reaching Swift goes through
   an explicit `UInt32(…)`/`MUIUInt(…)` conversion (CLAUDE.md CI hazards);
   the bridge returns plain `uint32_t` where it can.
4. **Parity**: the SDL test draws the same scene as lane 2's Metal test
   (a surface cleared to a known premultiplied colour under a rounded mask at
   half opacity, over a background rect) and asserts the **same literal
   pixels** within `ParityTolerance`, on macOS (SDL's Metal backend) and in
   Linux CI (llvmpipe; `Backends/SDL`'s tests run there). The replay harness
   (`ReplayFixture`/`PortableReplay`) cannot express app content (`MV-C`
   item 4) and is not extended.
5. **Headless `renderFrame` (`DC-A`)** returns the scene with the surface's
   quad and target but no request (a scene is data); a renderer handed it
   draws nothing for the run (no entry). Documented on `renderFrame`.
6. **`DemoCapture` and the cross-platform demo frame are unaffected**: no
   demo tree they build contains a surface (`Expected.swift` unedited).

**Cost if wrong.** If a later backend cannot sample a render target with the
image shader (all three SDL drivers and Metal can), it needs its own surface
pipeline.

---

## MV-I — input and accessibility: an ordinary proposal leaf, no special path

**Ruling.** `GPUSurface` registers no hitbox, focus entry or accessibility
record of its own, like `Image(decorative:)` and `Rectangle`. Pointer input
reaches it through the existing proposal modifiers (`.onTapGesture`,
`.gesture`, `.contentShape`, `.simultaneousGesture`, `.draggable`,
`.dropDestination`); accessibility through `accessibilityElement`/
`accessibilityLabel` on proposal content (`AccessibilityModifier`); focus,
`onKey`, `onClick` and `.hidden()` by wrapping it in a legacy container
(`Box { GPUSurface { … } }.focusable().onKey { … }` — proposal content inside
a legacy container is supported). A wheel over it reaches its enclosing
scroller (`DD-Y`). Nothing in hit testing, the arena, focus or the
accessibility builder changes.

**Cost if wrong.** None: no new path exists to be wrong.

---

## MV-J — the demo and the human checks

**Ruling.**

1. `METALUI_METALVIEW_DEMO=1 swift run MetalUIDemo` shows
   `metalViewDemoContent(surface:)` (`MetalUIDemoContent`, portable, its own
   function per the 1 MB-stack rule): a title, a `.continuous` surface in a
   rounded clip with a translucent label overlaid on it (UI composited over
   app GPU content — §1's point), a tap toggling `.continuous`/`.onDemand`
   (and a frame counter showing the draw rate stops), and a second, small
   `.onDemand` surface redrawn only when a `Stepper`'s value changes. The
   draw closure is the executable's: `MetalUIDemo` draws an animated
   full-screen-quad fragment shader (compiled from MSL source at runtime with
   `device.makeLibrary(source:)`, timed by `ctx.time`); `MetalUISDLDemo`
   (with the same variable) clears to a colour cycling with `ctx.time`
   through `ctx.clear`.
2. `everyProductionTreeBuildsOnAOneMegabyteThread` builds the new tree too.
3. New section in `docs/verification/human-checks.md` (O): the on-screen
   look, live resize (no stretch, no blank frame), continuous smoothness at
   the display's rate (and idle when paused — the link pauses), Retina vs
   1× scale (sharp at 2×, moving the window between displays), clip and
   overlay, and the SDL demo on Linux/Windows. **An agent cannot perform
   them.**

---

## MV-K — what must not move, the lanes, the migration notes

**Ruling.**

1. **Must not move**: state retention (`StateTable`, the seven slots, MC-A/
   MC-C/MC-P numbering, `.id()` outermost — a surface's identity is its
   element's, and `SurfaceRegistry` is a separate window table); hit testing,
   accessibility, animation, focus, the scrim, `List` windowing and `TB-AH`,
   `Deferred`, `TextField`/`TextEditor`; 0 px against `330f02b` in all
   fourteen offscreen images (no demo tree they render changes);
   `Expected.swift` unedited; `everyProductionTreeBuildsOnAOneMegabyteThread`
   green; 0 `warning:` on both build systems; `MetalUILayout` imports only
   `MetalUICore`; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green;
   `Backends/SDL` and a `swift:6.4-noble` container build.
2. **Three lanes, in order** (spec §8): 1 the portable core (scene primitive,
   platform types and table, element, frame, window, transitions, the seam
   change with minimal conformer bodies so both packages compile); 2 the
   Metal renderer, `MetalView`, the demo; 3 the SDL renderer, the SDL demo,
   human checks and the API overview.
3. **Migration notes** (`docs/migration.md`, lane 1): `PrimitiveKind.surface`
   (an exhaustive external switch adds an arm); `WindowRenderer`'s
   `finishFrame(scene:atlas:surfaces:)` (an external conformer adds the
   parameter; one with no surface support may ignore it and composites
   nothing for surface runs).

---

## MV-L — the critic round: five corrections to the design, one rejected finding

The critic round attacked the committed design (`63750dc`) before any lane
ran. **Re-run first**: the lock probe read unlocked (no
`CGSSessionScreenIsLocked` line, `displayAsleep main: 0`, one screen at
scale 2.0), and `docs/probes/swiftui-metal-view.swift` was rebuilt and re-run
whole; every G, C, D and R line (P1, G1–G3, P2, C1–C4, D1, R0–R3) printed
**byte for byte** the header's recorded block — so `MV-B`, `MV-D` and
`MV-G`/divergence 103 rest on output reproduced today, not only on the
design's run. Checked and **held**: the draw runs after
`withObservationTracking` returns (`Window.drawFrameIfNeeded`), so `MV-A`
item 4's "reads inside `draw` are not tracked" is true of the code; `beginFrame()`
runs before the frame is built, so a frame with no drawable builds no
requests to lose; `.hidden()` skips paint (`Frame.hiddenNodes`, the
`Element.paintGroup` gate), so `MV-G` item 4's "no GPU work" holds for it;
transitions apply their effect after capture (`insertThroughTransitions`),
so an `.opacity` insertion's first frame is not `activeOpacity == 0` and
still draws; `MetalUI` re-exports `MetalUIRender` on macOS, so
`MetalDrawContext` is visible from a plain `import MetalUI` (app code still
imports `Metal` itself to call `MTLCommandBuffer`'s methods — the doc says
so); `PrimitiveKind` has no raw values and `DemoFrameDeterminismTests` reads
only `rects`/`glyphs`/`drawList`, so a new case and two empty arrays move no
`Expected.swift` byte; the fake window already draws through a real
`MetalWindowRenderer` with readback, so lane 2's window pixel tests are
buildable. **Not checked here**: a Linux build of the new types — there is
no code yet; each lane builds `swift:6.4-noble` itself (`MV-K` item 1).

**Corrections.**

1. **Two siblings sharing one `.id` would trap in production.** Divergence 72
   (kept) gives two siblings with one `.id` one `GlobalElementID`; keyed by
   that alone, `SurfaceRegistry` hands both one `SurfaceID`, the frame emits
   two requests for it and `SurfaceTargetTable.update` traps — a crash from a
   tree every other element accepts. **Ruled**: the registry's key is
   (`GlobalElementID`, occurrence), the occurrence counting surfaces with
   that id already painted this frame, so each placement gets its own target
   and keeps it across frames while the order holds. The table's trap stays
   (its invariant); `Frame` now guarantees it. New test 1.13b
   (`twoSiblingSurfacesSharingOneIDGetTwoTargets`, through the spy renderer
   so the unfixed case is a wrong answer, not a process trap), mutation M1q′.
2. **`package` counters do not cross a package boundary.** The spec had
   `SDLWindowRenderer` re-expose `SurfaceTargetTable`'s `package` counters;
   `Backends/SDL` is a separate package and cannot read them (Swift's
   `package` is per package — `textureUploadCount`, the cited precedent, is
   declared and counted inside `MetalUISDL` itself). **Ruled**: the table's
   counters stay `package` for the root package's tests; `SDLWindowRenderer`
   keeps its own `package` counters, incremented in the `create`/`release`
   closures it passes and after each draw. No public API added.
3. **Test 1.15 could not see M1u.** Either `noteActiveAnimation()` or
   `requestAnotherFrame()` keeps the window drawing, so a test that asserts
   only "the window keeps drawing" stays green when one replaces the other.
   **Ruled**: 1.15 asserts `hasActiveAnimations == true` **and**
   `wantsAnotherFrame == false` while the surface paints.
4. **M3f was not a mutation 3.4 could see.** `unsignaled_fence_releases`
   counts only `r->fence`; a clear submitted in its own command buffer with a
   separately acquired fence never touches it. **Ruled**: the bridge gains
   `mui_renderer_submission_count(r)` (every `SDL_Submit…` in `SDLBridge.c`),
   test 3.4 becomes `surfaceFramesSubmitOnceAndNeverReleaseAnUnsignaledFence`
   (one submission per frame holding a new surface, no unsignalled release),
   M3f reddens its submission clause and M3f′ (`retire_fence` →
   `release_fence`) its fence clause plus the existing
   `backToBackFramesNeverReleaseAnUnsignaledFence` — both named.
5. **The no-double-buffering argument (`MV-E` item 6) needs tracked
   hazards.** Metal orders frame N+1's write of a target after frame N's
   sample of it across command buffers only for a hazard-tracked resource.
   **Ruled**: targets use the default (tracked) mode, never `.untracked`;
   stated in the spec's Metal paragraph.
6. **Test 2.6 could not see M2h as ordered.** Drawn A, A, B, B, a table
   shared on the `Renderer` releases A's target once (B's scene does not
   reference it) and every per-window count can still read 1 on the pair
   that is checked. **Ruled**: the windows draw at different sizes,
   alternately A, B, A, B, and each window's `createdCount` and draw count
   stay 1.

Also: test 1.8's name read `…AndAGhostsIsKeptUndrawn` (a typo) and is
`anUnreferencedTargetIsReleasedAndAGhostsTargetIsKeptUndrawn`. Expected root
count **2063 → 2064** (1.13b).

**Rejected finding.** *Rename `SurfaceID`/`SurfaceTarget`/`SurfaceDrawRequest`/
`SurfaceTargetTable` to `GPUSurface…`, since `MetalUIRender` already has
`RenderSurface`/`SurfaceFrame` and `MetalWindowRenderer.surface` means the
drawable.* No two names collide, the new types live in `MetalUIScene`/
`MetalUIPlatform` where `RenderSurface` is not visible, and `GPUSurfaceID`
next to `GPUSurface` would read as the element's own id rather than a
renderer handle. Kept; `finishFrame(scene:atlas:surfaces:)`'s doc says the
parameter is the frame's app surfaces, not `self.surface`. (Recorded here
rather than as an `LR-` ruling: `LR-` is task 7's engine-replacement prefix
in another decisions doc; this feature's rulings, rejections included, are
`MV-`.)

**Lane sizes.** Three lanes kept, strictly in order; lane 1 is the largest
(23 tests, the seam change) but its files are disjoint from lanes 2 and 3
except the signature-only hand-off edits spec §8 names.

## MV-M — lane 1's review round: four unpinned clauses pinned, the occurrence counted before the guards, the scene's one-id-one-size trap ruled

The reviewer of lane 1 (`2cc857f`) ran mutations against the 2051-test suite;
seven left it green. Each is now pinned or fixed, red first (`66483c2`):

1. **The layer** (mutation A, `layer: 0` for `activeLayer` in
   `Frame.drawSurface`). 1.17 compared a surface's layer to an image's in a
   tree with no portal, both 0. New 1.21,
   `aSurfaceInsideADeferredPortalIsCompositedOnThePortalsLayer`: both inside
   a `Deferred`, the image's layer `try #require`d non-zero.
2. **The scroll offset** (mutation B, `let translated = bounds`). New 1.22,
   `aScrolledSurfaceMovesWithItsScrollerAndRequestsNothingOnceScrolledOut`:
   a surface beside an image in a real `ProposalScrollView`, scrolled 30
   (moved up 30, level with the image, one request) and then to its 80
   ceiling (no quad, no request).
3. **Registry continuity** (mutation D, `endFrame()` keeps every id).
   `TransitionHarness` now holds one `SurfaceRegistry` across its frames, as
   a `Window` does. New 1.23,
   `aSurfaceReinsertedDuringItsRemovalGetsANewTarget`. The reviewer's
   scenario — the live surface and its ghost in one scene — does not arise:
   an insertion during a removal deletes that key's ghost
   (`TransitionStore`), so the re-inserted surface is alone; what the test
   pins is that it gets a new target rather than the one the ghost kept
   alive in the renderer's table (which, `.onDemand` at one size, would not
   redraw — `MV-G` item 4's "coming back is a new target").
4. **The `.surface` arm of `TransitionEffect.apply`** (mutation G, the
   inner-mask block dropped). New 1.24,
   `aSurfacesInnerMaskScalesWithItsTransitionAsAnImagesDoes`: a clip inside a
   `.transition(.scale)` group, mid-insertion, surface and image masks and
   radii equal, the mid mask `try #require`d different from the settled one.
5. **The occurrence is counted before the no-GPU-work guards** (a fix, not
   only a pin). `MV-L` item 1's occurrence counted only surfaces that passed
   `drawSurface`'s zero-size, clip and opacity guards, so among siblings
   sharing one `.id` (divergence 72) a skipped earlier sibling shifted the
   next one onto its target — at one size an `.onDemand` surface then showed
   the other's last contents undrawn. `SurfaceRegistry.occurrence(for:)` now
   runs first and `id(for:occurrence:)` after the guards (only that call
   marks a surface painted, so an unpainted one still loses its id at
   `endFrame()`). New 1.25,
   `aSkippedSiblingDoesNotShiftASharedIDsNextSurfaceOntoItsTarget` (red
   before: `after == [before[1]]` read `[before[0]]`). A `.hidden()` surface
   is not reached by paint at all and does not count — it is skipped as
   every other hidden element is.
6. **`Scene.insert(_:surface:layer:)`'s one-id-one-size precondition is
   ruled an invariant** (mutation F). A renderer binds one texture per
   target, and `Frame` never builds such a scene: a live surface's id is
   minted per frame at one size, an id that stops painting is never reused,
   and a ghost's or a drag preview's replay names its source's size or a
   retired id. Kept as a trap; pinned by the exit test 1.3b,
   `oneSurfaceIDAtTwoSizesInOneSceneTraps` (1.3's same-size repeat is the
   non-trapping control).
7. **The policy reaches the request** (mutation M, every request
   `.onDemand`). 1.15 now also asserts the `.continuous` surface's request
   carries `.continuous` (1.16 already pins `.onDemand`).

Root count **2051 → 2057** (1.21–1.25, 1.3b).

**Mutations, each on `0005509`, full unfiltered suite (2057), restored from a
copy, `git status --short` clean after each**: A (`layer: 0` in
`drawSurface`) reddens only 1.21; B (`let translated = bounds` in
`drawSurface` alone, not `drawImage`'s identical lines) only 1.22 (4
issues); D (`endFrame()` keeps every id) only 1.23; F
(`precondition(true || …)`) only 1.3b; G (the `.surface` arm's inner-mask
block dropped) only 1.24 (2 issues); M (every request `.onDemand`) only
1.15; H (the occurrence counted after the guards — this ruling's fix
reverted) only 1.25.

## MV-N — lane 2: the Metal renderer, `MetalView` and the demo as built; four mutations respelled, two exit tests strengthened

Lane 2 (`636eb7b` red, `bbaf217` green, `b22ea9d` the exit-test fix) built spec §4's
Metal paragraph, `MetalDrawContext`, `MetalView` and `MV-J`'s demo as
designed. What the lane decided that the design did not say:

1. **`MetalDrawContext.init` is `package`**: app code cannot construct one, so
   a draw is never handed a forged buffer or target. Guard G2.1's negative
   arm (`theMetalViewSpellingsCompileFromAPlainImport`) is that refusal
   ("initializer is inaccessible due to 'package' protection level").
2. **`frameIndex`** is the count of frames `finishFrame` finished before this
   one (the first frame's draws see 0). **`pixelSize`** is read off the
   created texture.
3. **`MetalView` is layout-, paint- and identity-transparent** around one
   `GPUSurface` (it forwards all three phases with its own id), so every
   `GPUSurface` rule holds for it unchanged; its downcast lives in an
   internal `MetalView.drawThunk(_:)`, the seam test 2.10 drives.
4. **The demo's draw counter** is a plain reference read during the build —
   never a `@State` write from the draw, which runs in the renderer (a phase
   write, CLAUDE.md "`@State`"). It lags the drawing by one frame and
   freezes, with the window idle, while paused. **Erratum (`MV-O` item 1):**
   as built it was "held in `@State`", and the claim that it lags by one
   frame was refuted by measurement — a never-written `@State` re-seeds from
   each build's initial value, so the header read 0 forever. The counter is
   now the caller's.
5. **The parity literal** is `SurfaceParity` in
   `Tests/MetalUIRenderTests/SurfaceCompositingTests.swift` (test 2.11): a
   black 40 × 40 rect, surface A (texel (200, 100, 40, 255), radius-6 mask,
   opacity 0.5) and surface B (opaque blue). Over opaque black every expected
   channel is an exact integer — (100, 50, 20, 255) at A's centre — so no
   GPU rounding ambiguity enters the literal lane 3 copies. Test 2.3 (another
   target) cites its RGB inline; its window has a transparent clear, so its
   alpha is checked to ±1.
6. **Exit tests 2.8 and 2.10 read the trap's message**
   (`observing: [\.standardErrorContent]`, "MV-F item 5" / "MV-A item 2").
   **Found by mutation**: M2j (the status precondition dropped) first left
   2.8 green — Metal aborts a doubly committed command buffer later in the
   same frame by itself, so a bare `.failure` cannot tell MetalUI's check
   from Metal's.
7. **Mutation spellings corrected against spec §8's table.** M2d binds the
   atlas texture where one exists (`atlasTexture ?? texture`). M2h moves the
   table onto the shared `Renderer` as a stored property (the table's
   accessor forwarding to it). M2i cannot be "never call `release`": Metal's
   `release` closure is empty by design (dropping the reference IS the
   release, `TE-AF`'s rule), so the table's counters move whatever it does —
   test 2.7 therefore also holds a **weak** reference to the `MTLTexture`
   and requires it freed once the frame that last sampled it completes, and
   M2i is the leak (`release` keeps the handle in a static array). M2m is the
   index offset by one **modulo the target count** (2.11 has two targets, so
   the plain +1 would trap out of range rather than read a wrong colour).
8. **A mutation that changes a stored property's layout needs `swift package
   clean`**: M2h, first built incrementally (both a static-backed and a
   `Renderer`-backed spelling), segfaulted the test process in 2.7 with
   impossible counter readings in 2.2 — CLAUDE.md's `direct field offset`
   hazard, not a finding. Rebuilt clean it reddens 2.6 alone.

**Mutations**, each from a copy of the committed file (`bbaf217`; M2h, M2j,
M2l and M2m re-run on the exit-test fix), full unfiltered suite (2070),
`git status --short` clean after each:

| mutation | file | reddens |
|---|---|---|
| M2a draws after `encode` | `MetalWindowRenderer.swift` | 2.1, 2.3, 2.9 |
| M2b `.surface` runs skipped in `encode` | `Renderer.swift` | 2.1, 2.2, 2.3, 2.6, 2.9, 2.11 |
| M2c a fresh table every frame | `MetalWindowRenderer.swift` | 2.2, 2.4, 2.5, 2.6, 2.7 |
| M2d the atlas bound for surface runs | `Renderer.swift` | 2.1, 2.2, 2.3, 2.6, 2.9 |
| M2e `.bgra8Unorm_srgb` targets | `MetalWindowRenderer.swift` | 2.3, 2.4 |
| M2f targets sized in points | `MetalWindowRenderer.swift` | 2.4 |
| M2g only new targets drawn | `MetalWindowRenderer.swift` | 2.4, 2.5 |
| M2h the table on the shared `Renderer` (clean build) | both | 2.6 |
| M2i `release` leaks the handle | `MetalWindowRenderer.swift` | 2.7 |
| M2j status precondition dropped | `MetalWindowRenderer.swift` | 2.8 |
| M2k `MetalView` forwards a fresh command buffer | `MetalView.swift` | 2.9 |
| M2l `MetalView` skips a non-Metal context | `MetalView.swift` | 2.10 |
| M2m target index + 1 (mod count) | `Renderer.swift` | 2.11 |
| M2n the demo's main surface `.onDemand` | `MetalViewDemo.swift` | 2.12 |
| G2.1 `renderPassDescripter` in the positive fixture | the guard | G2.1 |

(2.1 `aSurfaceFillIsCompositedOnTheFirstFrame`, 2.2
`anOnDemandSurfaceKeepsItsContentsWhenTheWindowRedrawsForAnotherReason`, 2.3
`aSurfaceIsClippedRoundedAndFadedExactlyAsAnImage`, 2.4
`aSurfaceDrawReceivesItsDevicePixelBgraTargetScaleAndTime`, 2.5
`aContinuousSurfaceDrawsOnEveryTickAndAnOnDemandOneOnce`, 2.6
`twoWindowsKeepTheirOwnTargets`, 2.7
`aSurfacesTargetIsReleasedWhenItsElementLeaves`, 2.8
`aSurfaceDrawThatCommitsTheCommandBufferTraps`, 2.9
`aMetalViewDrawsWithTheRenderersDeviceAndTheFramesCommandBuffer`, 2.10
`aMetalViewGivenANonMetalContextTraps`, 2.11
`aSurfaceRunSamplesItsTargetThroughTheImagePipeline`, 2.12
`theMetalViewDemoTreeRequestsOneContinuousAndOneOnDemandSurface`.)

**Still unpinned, stated**: a new target's clear to transparent (`MV-E` item
5; fresh private memory reads zero either way — spec §8 already says so).

Root count **2057 → 2070** (2.1–2.12, G2.1); guards +1. 0 px against
`330f02b` in all fourteen offscreen images (`compare.sh`, scenes identical);
`Expected.swift` unedited; `everyProductionTreeBuildsOnAOneMegabyteThread`
green with the new tree; 0 `error:`/`warning:` on the default build system,
SwiftPM's deprecation notice alone under native; `Backends/SDL` builds (0
`error:`); a `swift:6.4-noble` container builds the root package with 0
`error:`/`warning:`.

## MV-O — lane 2's review round: the demo's counter leaves `@State`, a draw is recorded only once its frame commits, resize pinned on the Metal path

The reviewer's findings on lane 2 (`4a8bbed`), fixed in `c5191e0`:

1. **The demo's draw counter is the caller's** (major). Measured by the
   reviewer with the screen unlocked: the shader quad animated while the
   header read "Viewport draws: 0" in both of two screenshots 1 s apart, and
   a scratch test reproduced it (`draws=5 seen=[0, 0, 0, 0, 0]`). The cause:
   `@State var draws = MetalViewDemoDraws()` is never *written* (the draw
   mutates the object, not the slot), so `StateTable.peek` finds no entry
   and `State.wrappedValue` falls back to the current struct's
   `initialValue` — a **new** object every build, because `openWindow`'s
   content closure rebuilds the tree every frame. The draw incremented an
   object the next build threw away. Now `MetalViewDemoDraws` is public
   (`count` `public internal(set)`, a doc comment on each member; the
   inventory's `MetalUIDemoContent .*` row maps it), `metalViewDemoContent`
   takes `draws:` before `surface:`, and `main.swift` creates the counter
   **and** the shader closure once, outside the content closure — the
   latter was also recompiling the pipeline every frame, since
   `shaderQuadDraw()` was called inside it. Pinned by **2.13**
   `theMetalViewDemosDrawCountAdvances`: a real `Window` with an
   accessibility client, six ticks, the header's static-text value read back
   (the string is a static text's `value`, not its `label`) — red on
   `4a8bbed`'s shape (`shown` 0 of 6 draws), green now. Mutation **M2o**
   (the counter back in `@State`) reddens 2.13 alone.

   **Carried, unprobed: a never-written `@State` of reference type is
   re-seeded every frame.** SwiftUI keeps the first initial value for the
   view's lifetime (its documented `@State` contract; not probed on this
   branch). MetalUI keeps nothing until a write, so a `@State` holding a
   class that is only mutated through the reference — never assigned —
   gets a fresh object each build. Pre-existing (the `StateTable.peek`
   absent-entry path `CX-F` already touched for optionals), not this
   branch's to change: it is an id-path/retention behaviour this branch
   must not move (`MV-K`). Owed: a probe arm and, if SwiftUI's answer is
   confirmed, a divergence row in `docs/divergences.md` or a fix — the
   Record phase files it, with no label taken here.
2. **A surface's draw is recorded only once its frame commits** (minor).
   `MetalWindowRenderer.finishFrame` called `surfaceTable.didDraw` inside
   the draw loop, before `Renderer.encode` — whose throw returns `false`
   without committing — so an `.onDemand` surface could show a target its
   uncommitted draw never wrote until its `value:` or size changed. Now
   every drawn request is recorded after `commit()`. After a failed frame
   the next one draws again (`lastDrawn` is still `nil` or the old value);
   a target **created** in the failed frame comes back with
   `isNewTarget == false` and unwritten contents, so an app that relies on
   the framework's clear of a new target sees undefined texels for one
   frame — accepted: `encode` throws only on a buffer or encoder allocation
   failure, and no test injects one.
3. **Resize is pinned on the Metal path** (minor). **2.14**
   `aResizedSurfaceGetsANewTargetAtItsNewDeviceSizeAndRedrawsOnce`: an
   `.onDemand` surface at 2× grows from 30 to 45 points wide between ticks,
   gets a new `bgra8Unorm` texture at 90 × 40 and draws once into it
   (`isNewTarget`), and an unchanged tick after draws nothing. Mutation
   **M2p** (`SurfaceTargetTable.update` ignores a size change, lane 1's V1)
   reddens 2.14 and `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating`.
4. **The record number is taken** (minor, no change here). `69` went to
   `docs/record/69-claude-md-full-2026-10-01.md` (via the master merge
   `d7a0824`) and master has since published §70 (app icon, `95234db`). The
   Record phase renumbers `69-metal-view.md` to the next free § at merge
   time (§71 if master keeps §70) and fixes every citation — this doc's
   header, the spec, the source comments — following the 24→25 and 26→27
   precedent.

Mutations from a copy of `c5191e0`, full unfiltered suite (**2072**),
`git status --short` clean after each:

| mutation | file | reddens |
|---|---|---|
| M2o the counter in `@State` again | `MetalViewDemo.swift` | 2.13 |
| M2p the table ignores a size change | `GPUSurface.swift` (`MetalUIPlatform`) | 2.14, `aResizeReplacesTheTargetAndARescaleRedrawsWithoutReallocating` |
