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

Prefix **`MV-`**, lettered. **Next unused: `MV-L`.** (This line moves in the
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
   Two requests naming one id in one frame trap (one element, one paint).
   Counters (`package`): `createdCount`, `releasedCount`, `drawnCount`,
   `liveCount`.
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
2. **The SDL bridge** gains four C functions and no change to
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
