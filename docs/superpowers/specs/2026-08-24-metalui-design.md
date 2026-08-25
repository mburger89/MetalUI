# MetalUI — Design

**Date:** 2026-08-24
**Status:** Approved design; implementation plan not yet written.

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) (Zed's Rust UI framework),
but written as idiomatic Swift rather than a port.

---

## 1. Goal and framing

Build a production-usable Swift UI framework capable of shipping real apps.

gpui is the **architectural reference, not the specification**. Where gpui's design solves a hard
problem well (the three-phase element pipeline, SDF-based primitives, per-primitive clipping), we
adopt it. Where Swift offers a better tool than a direct translation would (Observation, result
builders, structured concurrency, typed units), we use Swift's.

### Validating consumer

The framework's first consumer is a **node-based Metal shader authoring tool**: a visual shader
graph, a synchronized text view of the generated shader source, and a live 3D preview with
imported models.

That app is a separate project, built later. Its role here is to keep feature prioritization
honest. It exercises three subsystems simultaneously:

| App capability | Subsystem it makes load-bearing |
|---|---|
| Shader source editing | Text: shaping, metrics, caret/selection, soft wrap, virtualized scroll |
| Node graph | Paths/bezier wires, pan-zoom transforms, hit-testing, z-ordering, custom elements |
| Model import + live preview | **App-owned Metal rendering composited into the UI** |

The third is the reason a Metal-native UI framework is worth building at all, and it is a
**core primitive** in this design rather than an escape hatch. See §7.6.

### Non-goals

- Not a SwiftUI replacement or a SwiftUI-compatible API.
- Not a faithful gpui port; API fidelity to gpui is explicitly not a goal.
- Not cross-platform beyond Apple platforms in v1 (see §2).

---

## 2. Platform scope

**v1 targets macOS, iOS/iPadOS, and tvOS** on a single flat-surface backend
(`CAMetalLayer` + Metal + CoreText).

**visionOS is deferred but designed for.** It is not merely another backend: Metal content on
visionOS goes through CompositorServices `LayerRenderer`, which forks two of the deepest layers —
the render loop (stereo, per-eye projection, foveated rasterization rate maps) and the input model
(`SpatialEventCollection` rather than pointer events). Paying for stereo up front would slow every
other milestone. Instead, §3.2's seams are drawn so a CompositorServices backend is additive.

**Non-Apple platforms** (Linux/Windows) are possible later. The seams that would matter — the text
system and the render backend — are protocols, but no non-Apple implementation is planned or
budgeted.

**Dependencies: none.** Apple frameworks (Metal, CoreText, AppKit/UIKit) plus our own code. No
`unsafeFlags`, so the package remains consumable as an ordinary SwiftPM dependency.

---

## 3. Module architecture

### 3.1 Targets

Six library targets, strictly one-way dependencies. Layering buys enforced boundaries, fast
incremental builds, and headless testability — layout and text are testable with no window and no
GPU.

```
┌─────────────────────────────────────────────────────┐
│  MetalUI            umbrella: App, Window, Element,  │
│                     Component, Column/Row/Grid/      │
│                     Button, styling, focus, actions  │
└───┬──────────┬──────────┬───────────┬────────────────┘
    │          │          │           │
┌───▼────┐ ┌───▼────┐ ┌───▼─────┐ ┌───▼──────────┐
│ Layout │ │  Text  │ │ Render  │ │   Platform   │
│ flex + │ │CoreText│ │ Metal,  │ │ Window, input│
│ grid   │ │ shaping│ │ atlas   │ │ AppKit/UIKit │
└───┬────┘ └───┬────┘ └───┬─────┘ └───┬──────────┘
    └──────────┴────┬─────┴───────────┘
             ┌──────▼───────┐
             │ MetalUICore  │  geometry, color, units,
             │              │  IDs — no platform deps
             └──────────────┘
```

Plus `MetalUIShaderTypes`, a C target whose header is the single definition of every CPU/GPU
struct layout (§7.2).

Two deliberate absences hold the layering:

- **Layout does not know Text exists.** Layout leaves take a measure closure
  `(ProposedSize) -> Size`; the umbrella supplies one that calls Text. Layout stays a pure
  function of style plus closures, which is what makes the golden-file test strategy possible.
- **Render does not know fonts exist.** Text produces `GlyphRaster` (bitmap + metrics); Render
  owns the atlas and accepts bitmaps via a `GlyphRasterizing` protocol. The atlas is equally happy
  caching icons or SVG output.

### 3.2 The platform seam

The naive seam — `window.metalLayer` — silently encodes "one flat surface, orthographic
projection," which is exactly what visionOS breaks. The seam is drawn one level higher:

```swift
protocol RenderSurface: AnyObject {
    func nextFrame() throws -> SurfaceFrame
    func present(_ frame: SurfaceFrame, in commandBuffer: MTLCommandBuffer)
}

struct SurfaceFrame {
    var views: [SurfaceView]        // 1 flat, 2 stereo
    var scaleFactor: Float
}

struct SurfaceView {
    var colorTexture: MTLTexture
    var viewport: MTLViewport
    var projection: simd_float4x4                        // ortho now, perspective later
    var rasterizationRateMap: MTLRasterizationRateMap?   // nil now, foveation later
}
```

The renderer loops over `frame.views` and multiplies by a matrix it does not interpret. A
CompositorServices backend later returns two views with per-eye transform/tangents and a rate map,
**without the renderer changing**.

Input follows the same discipline: one `InputEvent` enum with spatial cases reserved rather than
retrofitted.

Windowing splits `AppKitPlatform` / `UIKitPlatform` behind a `Platform` protocol (windows,
displays, clipboard, cursor, menus, file panels). tvOS rides the UIKit backend with focus-move
events.

### 3.3 Concurrency

The package is Swift 6 language mode; strict concurrency shapes the design rather than fighting it.

- `App`, `Window`, the element tree, layout, and paint are **`@MainActor`**. UI work is
  single-threaded by construction; no locks in the hot path.
- Scene primitives are **POD structs** — trivially copyable, laid out for direct GPU upload.
- Background work (asset loading, file I/O, shader compilation, later text rasterization) uses
  structured concurrency. gpui's foreground/background executor split comes free from Swift's own;
  no custom executor machinery.

---

## 4. Core loop

### 4.1 Frame pipeline: fresh tree each frame, state keyed by ID

**Decision: rebuild the element tree every frame; no diffing, no persistent node graph.**

Each frame, `content` runs and produces a tree of lightweight `Element` values, walked three times:

1. **`requestLayout`** — each element contributes style plus a layout node; text leaves register a
   measure closure. The flex/grid engine then runs on the root.
2. **`prepaint`** — layout has resolved, so absolute bounds are known. Elements register hitboxes,
   focus handles, and scroll regions; decide they are offscreen and skip (virtualization); and
   hoist deferred/overlay content.
3. **`paint`** — emit GPU primitives into the `Scene`; push/pop clips and transforms.

```swift
@MainActor
protocol Element {
    associatedtype LayoutState
    associatedtype PrepaintState

    var elementID: ElementID? { get }

    mutating func requestLayout(_ id: GlobalElementID?, pass: inout LayoutPass)
        -> (LayoutNodeID, LayoutState)

    mutating func prepaint(_ id: GlobalElementID?, bounds: Bounds,
                           layout: inout LayoutState, pass: inout PrepaintPass) -> PrepaintState

    mutating func paint(_ id: GlobalElementID?, bounds: Bounds,
                        layout: inout LayoutState, prepaint: inout PrepaintState,
                        pass: inout PaintPass)
}
```

`LayoutPass` / `PrepaintPass` / `PaintPass` are thin structs over one `@MainActor final class
Frame`, exposing only what is legal in that phase — emitting a rect during layout is a compile
error, not a runtime rule.

**Why three phases and not two.** Hit-test registration in paint order, offscreen culling, and
overlay hoisting all require resolved positions but must happen before painting. `prepaint` is
that window.

**Rejected: diffed retained tree (React/SwiftUI model).** It buys skipping untouched subtrees and
incremental layout, at the cost of a reconciler — identity, keys, state migration on structural
change — which is where the nastiest framework bugs live. The scaling problem it purports to solve
(a 5,000-node graph, a 500k-line file) is actually solved by **virtualization**, which this design
needs regardless. With virtualization, trees stay small and full rebuilds stay cheap.

**Accepted cost:** `content` must be synchronous and cheap. Async reads are not tracked by
Observation, and expensive work re-runs on every affected frame. Documented as a hard rule: no
I/O, no heavy allocation in `content`.

**Deferred optimization:** subtree memoization (reuse last frame's layout/paint when observed
dependencies are unchanged). Not built speculatively.

### 4.2 `Component` — the user-facing surface

```swift
@MainActor
protocol Component: Element {
    associatedtype Content: Element
    @ElementBuilder var content: Content { get }
}
```

`Element` conformance comes from a protocol extension that materializes `content` once during
`requestLayout`, stashes it in `LayoutState`, and forwards all three phases. `Component` is pure
sugar; implementing `Element` directly remains available and is expected for the node graph.

**Vocabulary decision.** Names are deliberately distinct from SwiftUI's — `Component`/`content`,
not `View`/`body` — primarily to avoid symbol ambiguity when a file imports both frameworks, and
secondarily to keep visible daylight between the two. Universal UI terms (`Button`, `Column`,
`Row`, `Grid`) are kept because they belong to no single framework.

```swift
@Observable
final class ShaderDoc { var source = ""; var nodes: [Node] = [] }

struct Inspector: Component {
    let doc: ShaderDoc

    var content: some Element {
        Column(gap: 8) {
            Label("Nodes: \(doc.nodes.count)")
            Button("Compile") { compile(doc) }
        }
        .padding(12)
        .background(.gray800)
    }
}
```

### 4.3 Identity and cross-frame state

State that must survive a rebuild — scroll offset, hover, animation progress, text selection,
in-progress node drag — lives in a side table on the window keyed by `GlobalElementID`: the path
of `ElementID` components from the root.

Entries are marked on access and swept after each frame, so state for vanished elements is
collected automatically. This dictionary plus mark-sweep **is** the entire reconciliation story.

### 4.4 Redraw and scheduling

```swift
func drawFrameIfNeeded() {
    guard needsRedraw || hasActiveAnimations else { return }
    needsRedraw = false

    withObservationTracking {
        buildFrame()          // content → requestLayout → prepaint → paint
    } onChange: { [weak self] in
        Task { @MainActor in self?.needsRedraw = true }
    }
    present()
}
```

Three properties of `withObservationTracking` make it fit a full-rebuild model:

- It tracks exactly the properties **read during the closure** — precise dependencies, no
  annotations, no manual `notify()`.
- It is **one-shot**; normally an annoyance, here ideal, since we re-register every frame.
- `onChange` fires on the mutating thread just before the write lands, so we hop to `@MainActor`
  and set a flag rather than working inline.

A display link (`CVDisplayLink` / `CADisplayLink`) drives the loop, but **a frame is built only
when dirty** — set by an observation change, input event, animation tick, or resize. An idle
window costs zero CPU. Multiple mutations between vsyncs coalesce into one frame.

### 4.5 Overlays

`paint` emits into a `Scene` sorted by `(layer, order)`. A `Deferred` element hoists its subtree to
a higher layer during `prepaint`, so dropdowns, tooltips, and dragged nodes paint above siblings
without moving in the tree.

### 4.6 Allocation strategy

Rebuilding every frame allocates every frame, and `any Element` boxing brings ARC traffic.
Mitigations, in order:

1. **Result builders preserve concrete types.** `Column { Label(...); Button(...) }` builds
   `Column<Pair<Label, Button>>` — statically typed, no boxing. Only genuinely dynamic children
   need `AnyElement`.
2. **Virtualization keeps N small.**
3. If profiling still shows churn: a per-frame bump allocator for `AnyElement` (gpui's approach).
   Not built speculatively.

---

## 5. Layout

### 5.1 Decision

**Hand-written flexbox and CSS Grid in Swift.** Rejected: Yoga via C interop (opaque performance,
C++ dependency, FFI per node, limited control over incremental relayout) and porting Taffy from
Rust (~10k lines of mechanical translation plus ongoing drift).

Layout bugs must be fixable by us, and we need control over caching and incremental relayout. The
risk this incurs is mitigated by the test oracle in §5.5, which is what makes hand-writing
tractable — especially for grid.

### 5.2 Style model

```swift
struct Style {
    // Box
    var position: Position           // .relative | .absolute
    var inset: Edges<Length>
    var size, minSize, maxSize: Size<Dimension>
    var aspectRatio: Float?
    var margin, padding, border: Edges<Length>
    var overflow: Axes<Overflow>     // .visible | .hidden | .scroll

    // Container
    var display: Display             // .flex | .grid | .none
    var flexDirection: FlexDirection
    var flexWrap: FlexWrap
    var gap: Axes<Length>
    var justifyContent, alignItems, alignContent: Alignment?

    // Flex item
    var flexGrow, flexShrink: Float
    var flexBasis: Dimension
    var alignSelf: Alignment?

    // Grid container / item — see §5.4
}
```

**Out of scope for v1:** block/inline layout, floats, writing modes. **RTL is deferred but not
designed out** — `Edges` stays semantic so a start/end mapping can be added without touching
either algorithm.

### 5.3 Typed units

```swift
struct Pixels        { var value: Float }   // logical
struct DevicePixels  { var value: Int32 }   // physical
struct ScaledPixels  { var value: Float }   // logical × scaleFactor
struct Rems          { var value: Float }
enum Length { case pixels(Pixels), rems(Rems), percent(Float), auto }
```

Distinct types with arithmetic conformances, so mixing logical and device pixels is a **compile
error** rather than a Retina-only rendering bug.

### 5.4 Grid

Included in v1 (not deferred). It roughly doubles the layout module — the track-sizing algorithm
is harder than flexbox's, and auto-placement has no flexbox analogue — but it shares the `Style`
model, the SoA tree, the measure caches, and the alignment code with flex; `Display` selects the
algorithm. Retrofitting later would mean reopening sizing decisions baked around flex-only
assumptions. And the §5.5 oracle covers grid with zero changes.

**In v1:**
- `gridTemplateColumns` / `gridTemplateRows` with `px`, `%`, `fr`, `auto`, `minmax()`, `repeat()`
  including `autoFill` / `autoFit`
- `gridAutoColumns` / `gridAutoRows`, `gridAutoFlow` (row/column, sparse/dense)
- Placement: explicit line indices, spans, auto-placement
- `gap` (shared with flex); `justify`/`align` for items, content, self

**Out of v1:** subgrid (genuinely hard, rarely needed); baseline alignment across grid items
(flexbox baseline still ships); named areas (`grid-template-areas`) — deferred as an *ergonomic*
layer, since it is sugar over line indices and in Swift would be expressed with types rather than
parsed ASCII art.

```swift
Grid(columns: [.px(120), .fr(1), .auto], gap: 8) {
    Label("Roughness")
    Slider(value: $mat.roughness)
    Label("\(mat.roughness, format: .number.precision(.fractionLength(2)))")

    Label("Normal Map")
    TexturePicker(binding: $mat.normal).gridColumn(1, span: 2)
}
```

### 5.5 Caching

Flexbox calls `measure` on a leaf several times within one layout run (flex base size, then again
after flexing), and the tree is rebuilt each frame. Two caches at two lifetimes:

- **Per-frame**, in the layout tree, keyed by `(knownDimensions, availableSpace)`. Kills repeated
  calls within one run. Discarded with the tree.
- **Cross-frame**, in the text layer, keyed by
  `(textHash, fontStack, size, features, availableWidth)`, LRU. **This is the one that matters** —
  without it, scrolling a code file re-shapes every visible line every frame.

### 5.6 Test oracle

Ground truth is generated from **WebKit, already present on the machine**. A test utility loads
fixture HTML into a `WKWebView`, lets the browser lay it out, reads back every node's
`getBoundingClientRect()`, and writes a JSON golden file.

```
Tests/LayoutTests/
  Fixtures/flex_grow_basis_percent.html   ← the case, in plain CSS
  Golden/flex_grow_basis_percent.json     ← WebKit's answer, generated
  FlexEngineTests.swift                   ← asserts we match within 0.01pt
```

Fixtures are readable CSS a person can reason about; the oracle is a production browser rather
than our own opinion; and a disagreement can be opened in Safari and *seen*. Taffy's and Yoga's
fixture corpora are plain data and can be adapted as extra cases.

### 5.7 Module

```
Sources/MetalUI/Layout/
  Style.swift        Units.swift        LayoutTree.swift
  MeasureCache.swift Alignment.swift    ← shared
  FlexEngine.swift                      ← CSS Flexbox §9
  GridEngine.swift   GridPlacement.swift  GridTracks.swift
```

---

## 6. Text

CoreText does font fallback, bidi, and complex-script shaping better than we would. We use it for
shaping and rasterization and own everything above it.

| Stage | How | Owner |
|---|---|---|
| Font loading, features | `CTFontManager`; ligature/tabular-numeral controls | Us, thin over CoreText |
| Shaping | `CTLine`/`CTRun` from `CFAttributedString` → glyph IDs, advances, per-run font | CoreText |
| Line breaking / soft wrap | Our own, over shaped advances + break opportunities | **Us** |
| Rasterization | `CTFontDrawGlyphs` into our bitmap → atlas upload | Us, over CoreText |
| Atlas packing | Shelf packer; R8 monochrome, BGRA8 color | Us |

**Why own wrapping.** A code editor must re-wrap on pane resize without re-shaping, with wrap
points that are stable and identical every frame. We shape the logical line once, cache it, and
wrap by walking cached advances against break opportunities — resize becomes arithmetic over
cached data rather than a full re-shape.

### 6.1 Rasterization

- **Subpixel positioning**: rasterize each glyph at a few fractional x-offsets, pick nearest.
  Without it, text spacing visibly wobbles during horizontal scroll.
- **Atlas key**: `(fontID, glyphID, size, subpixelVariant, scaleFactor)`.
- **Grayscale AA only.** macOS retired LCD subpixel AA.
- **Color glyphs** (emoji, `COLR`/`sbix`) route to the polychrome atlas and skip tinting.

### 6.2 Text under canvas zoom

**Decision: re-rasterize per zoom bucket.** Zoom folds into the `size` component of the atlas key,
so the node canvas gets crisp text with no new machinery. This keeps text *sharper* than an SDF
approach would.

**Rejected for v1: MSDF glyphs.** At 12–14pt — the shader source editor — SDF loses thin stems,
cannot carry hinting fidelity, and cannot represent color emoji. Documented as a fallback if
bucket thrash appears in profiling; would apply to the zoomable canvas only, never globally.

Consequence: atlas eviction is mandatory (§7.5).

### 6.3 Editor API and the offset seam

```swift
struct ShapedLine {
    var runs: [ShapedRun]
    var width: Pixels
    var ascent, descent, lineHeight: Pixels

    func offset(forX x: Pixels) -> Int   // click → caret, snapped to grapheme cluster
    func x(forOffset offset: Int) -> Pixels
}
```

These two must be exact inverses at cluster boundaries; every selection, caret, and drag depends
on it.

**Offsets are UTF-8 byte offsets, not `String.Index`.** `String.Index` is grapheme-correct but its
arithmetic is O(n) — fine for a label, fatal for a 500k-line file. The framework offers a
convenience layer taking `String` for UI text and a lower-level API taking a UTF-8 buffer plus byte
ranges for editor use. The shader editor will eventually want a rope for its document; that is the
app's concern, and this seam is what lets it plug in.

---

## 7. Renderer

### 7.1 Primitive set

Verified against gpui's shipping Metal shaders (`crates/gpui_apple/src/shaders.metal`). Almost
nothing is rasterized:

```swift
enum Primitive {
    case shadow(Shadow)                     // analytic blurred rounded box
    case rect(Rect)                         // SDF rounded rect: fill, gradient, per-side borders
    case path(Path)                         // Loop-Blinn implicit quadratics
    case underline(Underline)               // analytic, incl. wavy
    case monochromeSprite(MonochromeSprite) // glyphs — tinted, R8 atlas
    case polychromeSprite(PolychromeSprite) // images, emoji, SVG — BGRA8 atlas
    case surface(Surface)                   // app-owned MTLTexture
}
```

| Primitive | Technique | Resolution-independent |
|---|---|---|
| Rect (rounded, bordered, gradient) | Analytic SDF in fragment shader | yes |
| Shadow incl. blur | Closed-form blurred-box approximation, 4 samples | yes |
| Bezier path / stroke | Loop-Blinn implicit quadratic + gradient distance | yes |
| Underline | Analytic | yes |
| **Glyph** | **CoreText → atlas sprite** | no |
| **Image / icon** | **Decode → atlas sprite** | no |
| App Metal content | Sampled texture | n/a |

Cubic béziers are subdivided into quadratics, as Loop-Blinn requires.

**Consequence for the node editor:** pan and zoom is a matrix change. Node bodies, borders,
shadows, and wires re-evaluate their SDFs at the new scale and are pixel-perfect at any zoom, with
no re-rasterization and no cache invalidation. Text is the sole exception, handled by §6.2.

**Naming.** `Rect`, not gpui's `Quad` — "quad" is GPU jargon in a UI vocabulary. It remains a
**single GPU primitive** with `cornerRadii` (all-zero = sharp), because sharp and rounded rects
interleave constantly in real UIs and separate primitive types would force a batch break at every
transition. Two API spellings, one primitive. A name-mapping table
(`Rect`↔`Quad`, `rect_fragment`↔`quad_fragment`, `rect_sdf`↔`quad_sdf`) lives in the renderer's
doc comments so gpui stays a one-hop reference for hard cases.

### 7.2 One struct definition, not two

CPU/GPU struct layouts live in a **single C header included by both**:

```
Sources/MetalUIShaderTypes/include/MetalUIShaderTypes.h   ← only definition
        ↓ imported by Swift               ↓ #included by shaders.metal
```

gpui solves this with Rust codegen; a shared header is simpler and gives compiler-enforced
agreement. Layout drift between CPU and GPU structs manifests as garbled geometry and is expensive
to debug.

### 7.3 Ordering, clipping, batching

Primitives are appended during `paint` with a monotonically increasing `order`. At submit, the
scene sorts by order and **groups consecutive runs of the same type into one instanced draw call**.
Draw-call count is the number of *type transitions* in z-order, not the number of things on screen.
A complex frame — panels, shadows, thousands of glyphs, node graph, 3D viewport — should land under
~10 draw calls.

**Clipping is per-primitive via `[[clip_distance]]`, not scissor rects.** Scissor clipping would
force a state change and therefore a batch break at every clip boundary; clip distances make
clipping free and composable with instancing, so deeply nested scroll hierarchies still batch.

### 7.4 Frame graph

```
1. App Metal passes    each MetalView encodes into its own target texture
2. Path rasterization  Loop-Blinn coverage → intermediate texture
3. Main pass           sorted batches sampling atlases + path texture + surfaces
4. Present             via RenderSurface (1 view flat, 2 later for stereo)
```

All stages share **one `MTLCommandBuffer`**. Buffers are a triple-buffered ring guarded by a
semaphore, `.storageModeShared` on Apple Silicon (no staging copy).

### 7.5 Atlas

Shelf packer; `R8Unorm` for glyph coverage, `BGRA8Unorm` for color. Growth adds textures rather
than reallocating, so live handles stay valid.

**Eviction is mandatory**, a direct consequence of §6.2: zooming mints glyph rasters at new sizes
continuously. Entries carry a last-used frame generation and evict LRU under pressure.

### 7.6 `MetalView` — app-owned rendering

```swift
struct MetalView: Element {
    var id: ElementID
    var redraw: RedrawPolicy = .onDemand   // .continuous for animated shaders
    var draw: (MetalDrawContext) -> Void
}

struct MetalDrawContext {
    let device: MTLDevice
    let commandBuffer: MTLCommandBuffer   // the SAME buffer as the UI
    let target: MTLTexture                // sized to element bounds × scale
    let depth: MTLTexture?
    let size: Size<DevicePixels>
    let frameIndex: UInt64
    let time: Double
}
```

`prepaint` learns the bounds and pulls a correctly-sized target from a texture pool; before the UI
pass, `draw` encodes app passes into that target; `paint` emits a `Surface` primitive referencing
it.

- **No synchronization tax.** Same device, queue, command buffer, and frame — none of the friction
  of hosting an `MTKView` inside AppKit or SwiftUI.
- **The viewport is a texture, so the SDF machinery applies to it.** Rounded corners, borders,
  drop shadows, translucent panels blended over live 3D, gizmos on top — ordinary rects in the same
  pass.
- **`redraw` feeds the §4.4 dirty flag.** A static preview costs zero frames when idle; an animated
  shader requests `.continuous`.

The same `Surface` path carries `IOSurface`/`CVPixelBuffer` content (video, camera) later.

### 7.7 Color

HSLA at the API boundary (theming and hover-state derivation are pleasant in HSL), converted
in-shader. Blending in **linear space** with sRGB texture formats, so gradients and translucency
are physically correct.

Because the validating consumer is a shader authoring tool on XDR displays, surface configuration
is designed for **Display P3 and EDR** from the start — `CAMetalLayer` colorspace,
`wantsExtendedDynamicRangeContent`, `rgba16Float` as an option. Retrofitting wide gamut into a
renderer that assumed 8-bit sRGB is painful, and accurate HDR shader preview is close to a
requirement for the target app.

---

## 8. Input and dispatch

### 8.1 Hit testing

Elements register hitboxes during `prepaint`:

```swift
let hitbox = pass.insertHitbox(bounds, contentMask, opaque: true)
```

Hitboxes accumulate in paint order; dispatch walks them **in reverse** so the topmost opaque hit
wins. Because registration precedes painting in the same frame, `hitbox.isHovered` is queryable
during `paint` — hover has no one-frame lag.

### 8.2 Events

```swift
enum InputEvent {
    case mouseDown(MouseDownEvent),  mouseUp(MouseUpEvent)
    case mouseMove(MouseMoveEvent),  scrollWheel(ScrollWheelEvent)
    case keyDown(KeyDownEvent),      keyUp(KeyUpEvent)
    case modifiersChanged(ModifiersChangedEvent)
    case focusMove(FocusMoveEvent)          // tvOS
    // reserved: case spatial(SpatialEvent) // visionOS
}
```

Handlers are registered during `paint` with a **capture or bubble** phase; dispatch runs against
the most recent frame's handler set. Capture lets a modal or in-progress drag swallow events
without restructuring the tree.

Scroll must honor `NSEvent`'s `phase`/`momentumPhase` rather than treating wheel events as raw
deltas — this is the difference between native trackpad feel and a web app.

### 8.3 Focus, actions, keymaps

Focus handles form a tree registered during `prepaint`; key events dispatch from the focused node
upward through ancestors. Actions are types, not strings:

```swift
struct Copy: Action {}
struct MoveCursor: Action { var direction: Direction }

Keymap {
    Binding("cmd-c",         Copy(),           context: "Editor")
    Binding("ctrl-k ctrl-f", FormatDocument(), context: "Editor && mode == code")
}
```

Dispatch builds a context stack from the focus chain, matches innermost-first, and bubbles until
handled. v1 covers single and two-stroke bindings with `&&` / `||` / `!` context predicates, and a
pending-keystroke buffer with timeout.

### 8.4 IME

Not optional and not v2: without it, `é` is untypeable and CJK input is impossible.

The focused element vends a `TextInputHandler`, bridged to `NSTextInputClient` (macOS) and
`UITextInput` (iOS), covering marked/preedit text, the candidate window, and dead keys. It must
report caret rectangles back to the system so the candidate palette positions correctly — so it
reaches into the text layer, not just the event layer. Designed in from the start; implemented in
Milestone 6.

---

## 9. Testing

Swift Testing (`import Testing`); parameterized tests carry the fixture corpora.

| Layer | Method | Catches |
|---|---|---|
| Layout | WebKit golden files, `@Test(arguments:)` over the corpus | Flex/grid algorithm errors — highest-risk hand-written code |
| Text | Golden metrics for known strings × fonts; property test that `x(forOffset:)` and `offset(forX:)` round-trip at cluster boundaries | Caret/selection drift |
| Renderer | Offscreen render → compare to reference PNGs with perceptual tolerance | Shader regressions; headless in CI |
| Interaction | Headless `TestWindow`: runs frames with no real window, synthesizes events, asserts on scene and state | "Click fires the action", "scroll updates offset", "typing updates the doc" |
| Concurrency | Swift 6 strict mode | Data races, at compile time |

`TestWindow` is a design constraint, not just a utility: it exists only because `RenderSurface` and
`Platform` are protocols and the frame loop is driven by an injectable clock rather than a display
link. Testability is a consequence of the §3.2 seams.

---

## 10. Build order

Each milestone ends in something runnable.

| # | Scope | Exit criterion |
|---|---|---|
| **0** | Core geometry/units/color, shared C header, Metal setup, `RenderSurface`, AppKit window | A window showing one rounded rect with a border |
| **1** | Flexbox + WebKit golden harness; `Element`, three phases, `Frame`, state table; `Box`/`Column`/`Row`; styling | Nested flex layout of colored rects that resizes correctly |
| **2** | CoreText shaping, glyph raster, atlas, monochrome sprites, `Text` + measure integration | Styled text in flex layout, correct on Retina and at any scale |
| **3** | Hitboxes, mouse dispatch, hover/active, focus, keymaps, actions, scroll containers | Counter demo: real buttons, hover states, scrollable list |
| **4** | `@Observable` integration, dirty tracking, display-link scheduling, `Component` + result builders, animation & easing | A real small app that **idles at 0% CPU** |
| **5** | Grid engine + fixtures, paths (Loop-Blinn), images/SVG, **`MetalView`** | **Node-graph prototype: bezier wires, grid inspector, live 3D preview with UI composited over it** |
| **6** | Soft wrap, selection, IME, virtualized list; UIKit backend | Shader source editor usable; runs on iPad |

**Milestone 5 is the target** — where the shader app's three organs exist in one window.
Milestones 0–4 are the framework earning the right to get there.

---

## 11. Known risks

| Risk | Mitigation |
|---|---|
| Hand-written flex/grid is subtly wrong | WebKit golden-file oracle (§5.6); disagreements are inspectable in Safari |
| Milestone 1 is a long stretch with little visible output | Golden corpus provides continuous objective progress signal |
| Per-frame allocation / ARC churn from `any Element` | Concrete-typed result builders, then virtualization, then bump allocator (§4.6) |
| Atlas growth during canvas zoom | LRU eviction with frame-generation marking (§7.5), mandatory not optional |
| `content` doing expensive work each frame | Documented hard rule; surfaced by frame-time instrumentation |
| IME under-scoped | Designed into the text layer from the start; Milestone 6 |
| visionOS retrofit forces redesign | `RenderSurface` returns N views with projection matrices; `InputEvent` reserves spatial cases (§3.2) |
| "Editor-grade text" is unbounded | Treated as a direction, not a finish line; Milestone 6 exit is "usable", revisited continuously |
