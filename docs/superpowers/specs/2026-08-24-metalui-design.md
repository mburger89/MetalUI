# MetalUI — Design

**Date:** 2026-08-24 (revised 2026-08-25 after adversarial review)
**Status:** Approved design; implementation plan not yet written.

A GPU-accelerated UI framework for Swift, architecturally modeled on
[gpui](https://github.com/zed-industries/zed/tree/main/crates/gpui) (Zed's Rust UI framework),
but written as idiomatic Swift rather than a port.

> **Revision note.** This document was reviewed by eleven agents that compiled Swift against the
> Swift 6.3.3 toolchain, built SwiftPM packages, measured CoreText and WebKit behavior on the target
> machine, and read gpui's shipping source. Claims marked **(measured)** were verified empirically;
> the measurement is quoted so it can be re-checked. Several first-draft decisions were overturned;
> §14 records them.

---

## 1. Goal and framing

Build a production-usable Swift UI framework capable of shipping real apps.

gpui is the **architectural reference, not the specification**. Where gpui's design solves a hard
problem well (the three-phase element pipeline, SDF-based primitives, per-primitive clipping), we
adopt it. Where Swift offers a better tool than a direct translation would (Observation, result
builders, structured concurrency, typed units), we use Swift's. Where gpui does not solve a problem
at all (path stroking, accessibility), we say so rather than implying inheritance.

### Validating consumer

The framework's first consumer is a **node-based Metal shader authoring tool**: a visual shader
graph, a synchronized text view of the generated shader source, and a live 3D preview with imported
models.

That app is a separate project, built later. Its role here is to keep feature prioritization honest.
It exercises three subsystems simultaneously:

| App capability | Subsystem it makes load-bearing |
|---|---|
| Shader source editing | Text: shaping, metrics, caret/selection, soft wrap, virtualized scroll |
| Node graph | Paths/bezier wires, pan-zoom transforms, hit-testing, z-ordering, custom elements |
| Model import + live preview | **App-owned Metal rendering composited into the UI** |

The third is the reason a Metal-native UI framework is worth building at all, and it is a **core
primitive** (§7.7), not an escape hatch.

### Non-goals

- Not a SwiftUI replacement or a SwiftUI-compatible API.
- Not a faithful gpui port; API fidelity to gpui is explicitly not a goal.
- Not cross-platform beyond Apple platforms (§2).

---

## 2. Platform scope

**v1 targets macOS and iOS/iPadOS** on a single flat-surface backend (`CAMetalLayer` + Metal +
CoreText).

**tvOS is deferred but designed for.** *(Revised — v1 in the first draft.)* It shares the UIKit
backend built for iOS, so it stays cheap to add, but its interaction model is pointerless: remote
swipe translated to focus movement, focus parallax, and no cursor at all — which §8.1's hitbox-based
hit testing assumes exists. Shipping it would mean designing a second input model that serves no
stated goal.

**visionOS is deferred but designed for.** It is not merely another backend: Metal content on
visionOS goes through CompositorServices `LayerRenderer`, which forks the render loop (stereo,
per-eye projection, foveated rasterization rate maps) and the input model (`SpatialEventCollection`
rather than pointer events). §3.2's seams make a CompositorServices backend additive.

**Non-Apple platforms** (Linux/Windows) are possible later. The seams that would matter — the text
system and the render backend — are protocols, but no non-Apple implementation is planned.

**Dependencies: none.** Apple frameworks (Metal, CoreText, AppKit/UIKit) plus our own code, and no
`unsafeFlags` — see §7.2, which is what makes that claim survivable.

---

## 3. Module architecture

### 3.1 Targets

Seven targets, strictly one-way dependencies. Layering buys enforced boundaries, incremental builds
that actually partition, and headless testability — layout is testable with no window and no GPU.

```
┌─────────────────────────────────────────────────────┐
│  MetalUI            umbrella: App, Window, Element,  │
│                     Component, Column/Row/Grid/      │
│                     Button, styling, focus, actions, │
│                     accessibility                    │
└───┬──────────┬──────────┬───────────┬────────────────┘
    │          │          │           │
┌───▼────┐ ┌───▼────┐ ┌───▼─────┐ ┌───▼──────────┐
│ Layout │ │  Text  │ │ Render  │ │   Platform   │
│ flex + │ │CoreText│ │ Metal,  │ │ PlatformWindow│
│ grid   │ │ shaping│ │ atlas   │ │ input, AppKit/│
│        │ │        │ │         │ │ UIKit         │
└───┬────┘ └───┬────┘ └───┬─────┘ └───┬──────────┘
    └──────────┴────┬─────┴───────────┘
             ┌──────▼───────┐      ┌──────────────────┐
             │ MetalUICore  │      │ MetalUIShaderTypes│
             │ geometry,    │      │ (C target) the    │
             │ color, units,│      │ only definition of│
             │ IDs          │      │ CPU/GPU layouts   │
             └──────────────┘      └──────────────────┘
```

`Window` in the umbrella is the public type; `PlatformWindow` in Platform is the backend protocol.
They are distinct and never aliased.

**Every module's sources live under its own target directory** (`Sources/MetalUILayout/…`, not
`Sources/MetalUI/Layout/…`). SwiftPM's `Sources/<TargetName>/` convention means the latter would
place the flex engine *inside* the umbrella target, defeating all three stated benefits.

Two deliberate absences hold the layering:

- **Layout does not know Text exists.** Layout leaves take a measure closure whose contract is §5.5.
  Layout stays a pure function of style plus closures, which is what makes §5.7's oracle possible.
- **Render does not know fonts exist.** Text produces `GlyphRaster` (bitmap + metrics); Render
  defines both `GlyphRaster` and the `GlyphRasterizing` protocol without font knowledge, and owns
  the atlas.

### 3.2 The platform seam

The naive seam — `window.metalLayer` — silently encodes "one flat surface, orthographic projection,"
which is exactly what visionOS breaks. The seam is drawn one level higher:

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

**Failure handling.** `nextFrame()` throwing and `nextDrawable()` returning nil are everyday
conditions, not errors. The frame loop skips the frame, **leaves `needsRedraw` set**, and retries on
the next tick. A skipped frame never clears dirty state. Device loss (`MTLCommandBufferError`
`.notPermitted`/`.deviceRemoved`) tears down and rebuilds all GPU resources — pipelines, atlases,
`MetalView` targets — and forces a full redraw; atlas contents are regenerable by construction, so
no user-visible state is lost.

Input follows the same discipline: one `InputEvent` enum with spatial cases reserved.

### 3.3 Concurrency

The package is Swift 6 language mode; strict concurrency shapes the design rather than fighting it.

- `App`, `Window`, the element tree, layout, and paint are **`@MainActor`**. UI work is
  single-threaded by construction; no locks in the hot path.
- Scene primitives are **POD structs** — trivially copyable, laid out for direct GPU upload.
- Background work (asset loading, file I/O, shader compilation, later text rasterization) uses
  structured concurrency. gpui's foreground/background executor split comes free from Swift's own.

---

## 4. Core loop

### 4.1 Frame pipeline: fresh tree each frame, state keyed by ID

**Decision: rebuild the element tree every frame; no diffing, no persistent node graph.**

Each frame, `content` runs and produces a tree of lightweight `Element` values, walked three times:

1. **`requestLayout`** — each element contributes style plus a layout node; text leaves register a
   measure closure (§5.5). Virtualized containers produce visible children here (§4.7). The
   flex/grid engine then runs on the root.
2. **`prepaint`** — layout has resolved, so absolute bounds are known. Elements register hitboxes,
   focus handles, scroll regions, and accessibility nodes (§9); cull offscreen content; and hoist
   deferred/overlay content.
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

`LayoutPass` / `PrepaintPass` / `PaintPass` are thin structs over one `@MainActor final class Frame`,
exposing only what is legal in that phase — emitting a rect during layout is a compile error.

**Why three phases and not two.** Hit-test registration in paint order, offscreen culling, AX node
emission, and overlay hoisting all require resolved positions but must precede painting.

**Rejected: diffed retained tree (React/SwiftUI model).** It buys skipping untouched subtrees, at the
cost of a reconciler — identity, keys, state migration — which is where the nastiest framework bugs
live. The scaling problem it purports to solve is solved instead by **virtualization** (§4.7).

**Accepted cost:** `content` must be synchronous and cheap. Async reads are not tracked by
Observation, and expensive work re-runs on every affected frame. Documented as a hard rule: no I/O,
no heavy allocation in `content`.

### 4.2 `Component` — the user-facing surface

```swift
@MainActor
protocol Component: Element {
    associatedtype Content: Element
    @ElementBuilder var content: Content { get }
}
```

`Element` conformance comes from a protocol extension that materializes `content` once during
`requestLayout`, stashes it in `LayoutState`, and forwards all three phases. `Component` is sugar;
implementing `Element` directly remains available and is expected for the node graph.

**Vocabulary decision.** Names are deliberately distinct from SwiftUI's — `Component`/`content`, not
`View`/`body` — primarily to avoid symbol ambiguity when a file imports both frameworks. Universal
UI terms (`Button`, `Column`, `Row`, `Grid`) are kept because they belong to no single framework.

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
        .background(.surfaceSecondary)
    }
}
```

### 4.3 Identity and cross-frame state

State that must survive a rebuild — scroll offset, hover, animation progress, text selection,
in-progress node drag, `MetalView` render targets (§7.7) — lives in a side table on the window keyed
by `GlobalElementID`: the path of **`PathComponent`s** from the root.

**Identity is structural and universal; `.id()` is an override, not a source.** Every element has an
identity. A component is either `.positional(Int)` — the element's index in its container's **flat**
child list — or `.named(ElementID)` when the element carries an `.id()`, and **a name replaces a
position rather than joining it**, so an item keeps its state through a reorder. What a name buys is
survival across a change of position; what position buys is that an unnamed element has state at
all. See `docs/superpowers/specs/2026-08-27-structural-identity-design.md` and
`docs/superpowers/2026-08-27-structural-identity-decisions.md` for the whole rule and its costs.

**This section originally read "the path of `ElementID` components", and identity was opt-in.** Under
that rule `GlobalElementID.child(of:_:)` returned `nil` when either the parent path or the child's
local id was `nil`, so an unnamed container poisoned its entire subtree: no descendant could hold
cross-frame state however carefully it was named. That is a DOM-ish rule — identity exists because
someone wrote an attribute — and ruling EP-5 selects SwiftUI's inverse. `nil` is now gone from the
identity a phase receives, so "every element has identity" is enforced by the compiler rather than
remembered by the reader.

`GlobalElementID` is a **persistent linked list** — one allocation per child regardless of depth,
tails shared — because universal identity makes every node build a path every frame. It is a class,
so `===` is spellable beside `==` and they differ: two structurally identical paths from different
frames are `==` and never `===`, and **only `==` may be used for lookup**.

Entries are marked on access and swept after each frame. This dictionary plus mark-sweep **is** the
entire reconciliation story.

**Two consequences the sweep forces, recorded here because both are load-bearing elsewhere:**

- **Accessibility identity rides this table.** AX clients retain element references across frames, so
  `GlobalElementID` is the only structure that can back stable AX identity (§9). A node an AX client
  still holds must survive the sweep as a tombstone that reports itself invalid, rather than
  vanishing. **Universal identity helps §9 rather than complicating it**: every element can now back
  an AX node, where under the opt-in rule an unnamed ancestor left whole subtrees unaddressable no
  matter how their elements were named. It does not make tombstones any easier — that is a change to
  the sweep, not to the key, and it is still unbuilt.
- **Exit transitions are impossible without a tombstone mechanism.** An element that stops being
  produced has its animation state swept on that very frame. **v1 does not support exit transitions**
  (§14); the sweep is why. Adding them later means deferred-sweep tombstones, which is a change to
  this section, not a feature bolted onto the animation system.

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
- `onChange` fires on the mutating thread just before the write lands, so we hop to `@MainActor` and
  set a flag rather than working inline.

**Display link. (measured)** `CVDisplayLink` is deprecated **in its entirety** as of macOS 15 —
`CVDisplayLink.h` opens `API_DEPRECATED_BEGIN(…, macos(10.4, 15.0))` at line 51 and closes at 251 —
and this package targets macOS 26. The frame loop uses **`NSView.displayLink(target:selector:)`** on
macOS (14+, returns `CADisplayLink`) and `CADisplayLink` on iOS. This is strictly better than the
first draft's plan: one type across AppKit and UIKit, and callbacks arrive on a **main-thread run
loop**, matching §3.3's `@MainActor` frame with no thread hop (a `CVDisplayLink` callback fires on a
dedicated thread and would need one).

**A frame is built only when dirty** — set by an observation change, input event, animation tick,
resize, `MetalView` invalidation (§7.7), or system appearance change (§7.8). The link is **paused**
(`link.isPaused = true`) when `needsRedraw == false && !hasActiveAnimations` and resumed at every
dirty-marking site, so an idle window permits display downclocking. Cost: one frame of latency on
the first event after idle.

**Timebase.** All animation and `MetalDrawContext.time` derive from the display link's **target
presentation timestamp**, never wall clock — required for correct 120 Hz ProMotion and
variable-refresh behavior. `hasActiveAnimations` is set when an animation is registered during
`prepaint` and cleared on the first frame where none is.

**Post-commit.** After presenting, the loop calls `NSTextInputContext.invalidateCharacterCoordinates`
when the caret rect moved (§8.4); without it the input system will not call `handleEvent:` correctly.

### 4.5 Overlays

`paint` emits into a `Scene` sorted by `(layer, order)`. A `Deferred` element hoists its subtree to a
higher layer during `prepaint`, so dropdowns, tooltips, and dragged nodes paint above siblings
without moving in the tree.

### 4.6 `AnyElement` and allocation

**`any Element` cannot drive this pipeline. (measured, swiftc 6.3.3, `-swift-version 6`,
arm64-apple-macosx26.0.)** `requestLayout` on an `inout any Element` type-checks, but `prepaint`
fails:

```
error: member 'prepaint' cannot be used on value of type 'any Element' [#ExistentialMemberAccess]
```

`LayoutState` and `PrepaintState` appear in **parameter** position, and a member is usable on an
existential only when its associated types appear in **covariant** (result) position, where the
compiler can erase them to their upper bound (SE-0309). **Making them by-value rather than `inout`
changes nothing** — measured on swiftc 6.3.3, byte-identical diagnostic. `requestLayout` opens
because its associated type is in its *return* type.

> **Corrected during M1b (ruling EP-3).** This paragraph previously said the associated types
> "appear in `inout` (invariant) position and cannot be opened", which named the wrong mechanism and
> implied that a future Swift allowing `inout` existential opening would make `AnyElement`
> redundant. It would not. Verified standalone both ways, and by construction: `-> S`, `-> [S]`,
> `-> S?`, `var prop: S { get }` and `func take(_ f: (S) -> Void)` all compile on an existential;
> `func byValue(_ s: S)` and `func byInout(_ s: inout S)` both fail identically.
`AnyElement` is therefore a **hand-written erasure**:

```swift
protocol ElementObject { /* type-erased phase methods; NOT AnyObject */ }

struct AnyElementBox<E: Element>: ElementObject {   // ← struct, not class
    var element: E
    var layoutState: E.LayoutState?
    var prepaintState: E.PrepaintState?
}

struct AnyElement { var box: any ElementObject }
```

**The box must be a struct. (measured.)** With a class box, two copies share one `LayoutState`:
`Row { sep; sep }` prints `prepaint sees layoutState=2` twice — wrong bounds, no diagnostic. The
struct box prints 1 then 2. This is a silent-corruption trap, which is why it is specified here
rather than left to implementation.

gpui's move-only `Box<dyn ElementObject>` has no Swift equivalent: `struct AnyElement: ~Copyable`
plus `[AnyElement]` gives `error: type 'AnyElement' does not conform to protocol 'Copyable'`.

**Allocation mitigations, in order:**

1. **Result builders preserve concrete types.** `Column { Label(...); Button(...) }` builds
   `Column<Pair<Label, Button>>` — statically typed, no boxing. Only genuinely dynamic children need
   `AnyElement`.
2. **Virtualization keeps N small** (§4.7).
3. If profiling still shows churn: a per-frame bump allocator. Not built speculatively.

### 4.7 Virtualization

**Culling is not virtualization**, and the first draft conflated them. Skipping offscreen elements
during `prepaint` runs *after* `content` built all N elements and after all N layout nodes were
created and sized — it removes the cheapest of three costs. Three separate arguments depend on trees
actually staying small: §4.1's rejection of a diffed retained tree, §4.6's allocation strategy, and
§13's ARC-churn row.

Real virtualization fits inside the existing phase contract without changing §4.1 — a virtualized
container produces its children during its **own** `requestLayout`, from a range closure:

```swift
VirtualList(count: doc.lineCount, extent: .uniform(lineHeight)) { range in
    range.map { LineView(doc, line: $0) }
}
```

Specified behavior:

- **Extent model**: `.uniform(Pixels)` (exact scrollbar, O(1) offset math) or
  `.estimated(Pixels, measure:)` (measured on realization, cached per index, scrollbar refines as
  content is visited). A code editor with soft wrap needs the latter.
- **Keyed state** (§4.3) for an item outside the realized range is swept normally; items must not
  hold state that outlives visibility. State that must persist (e.g. a collapsed fold) belongs in the
  app's `@Observable` model, not the element state table.
- **Hitboxes and AX nodes** exist only for realized items. AX exposes the full logical count with
  realized children, so VoiceOver reports "3 of 500" correctly.
- **Nested virtualized scrollers are supported**; the inner container's realized range is computed
  against its own clipped bounds.

Virtualization ships in **M3**, alongside scroll containers — not M6 — because the arguments above
depend on it existing.

---

## 5. Layout

### 5.1 Decision

**Hand-written flexbox and CSS Grid in Swift.** Rejected: Yoga via C interop (opaque performance, C++
dependency, FFI per node, limited control over incremental relayout) and porting Taffy from Rust
(~10k lines of mechanical translation plus ongoing drift).

Layout bugs must be fixable by us, and we need control over caching. The risk is mitigated by the
test oracle in **§5.7**, which is what makes hand-writing tractable — especially for grid.

### 5.2 Style model and box model

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

    // Grid — §5.4
}
```

**Box model: `border-box`.** `size`, `minSize`, and `maxSize` include padding and border. CSS defaults
to `content-box`, but Yoga, Taffy, and gpui all default to `border-box`, and it is what UI authors
expect. **Only `border-box` ships in v1** — no `boxSizing` property. Every §5.7 fixture must declare
`box-sizing: border-box` in its CSS, exactly as Taffy's own generator forces it.

**Automatic minimum size** (CSS flexbox's `min-width: auto`, which prevents flex items shrinking below
their min-content size) **is implemented in v1** — without it, text in a constrained row collapses to
zero and the framework looks broken on its first demo. Fixtures depending on it are in the corpus.

**Out of scope for v1:** block/inline layout, floats, writing modes. **RTL is deferred but not
designed out** — `Edges` stays semantic so a start/end mapping can be added without touching either
algorithm.

### 5.3 Units

```swift
struct Pixels        { var value: Float }   // logical
struct DevicePixels  { var value: Int32 }   // physical
struct ScaledPixels  { var value: Float }   // logical × scaleFactor
struct Rems          { var value: Float }   // relative to root font size

enum Length    { case pixels(Pixels), rems(Rems), percent(Float) }         // no auto
enum Dimension { case length(Length), auto }                               // sizing
```

`Length` is used where a value is always required (margin, padding, border, gap, inset).
`Dimension` adds `auto` and is used for `size`/`minSize`/`maxSize`/`flexBasis`. The first draft gave
`Length` an `auto` case *and* used an undefined `Dimension`; this split is the fix.

These live in **MetalUICore**, not the Layout target — §3.1's Core box owns "geometry, color, units,
IDs," and Text and Render both need them.

Distinct types with arithmetic conformances, so mixing logical and device pixels is a **compile
error** rather than a Retina-only rendering bug.

### 5.4 Grid

Included in v1. It roughly doubles the layout module — the track-sizing algorithm is harder than
flexbox's, and auto-placement has no flexbox analogue — but it shares the `Style` model, the SoA
tree, the measure caches, and the alignment code with flex; `Display` selects the algorithm. And the
§5.7 oracle covers grid with zero changes.

**In v1:** `gridTemplateColumns`/`gridTemplateRows` with `px`, `%`, `fr`, `auto`, `minmax()`,
`repeat()` including `autoFill`/`autoFit`; `gridAutoColumns`/`gridAutoRows`, `gridAutoFlow`
(row/column, sparse/dense); placement by explicit line indices, spans, and auto-placement; `gap`;
`justify`/`align` for items, content, self.

**Out of v1:** subgrid; baseline alignment across grid items; named areas (deferred as an *ergonomic*
layer over line indices).

```swift
Grid(columns: [.px(120), .fr(1), .auto], gap: 8) {
    Label("Roughness")
    Slider(value: $mat.roughness)
    Label("\(mat.roughness, format: .number.precision(.fractionLength(2)))")

    Label("Normal Map")
    TexturePicker(binding: $mat.normal).gridColumn(1, span: 2)
}
```

### 5.5 The measure contract

This is the public Layout↔Text seam, and the first draft declared two incompatible signatures. The
contract is:

```swift
enum AvailableSpace { case definite(Float), minContent, maxContent }

typealias MeasureFunction =
    (_ knownDimensions: Size<Float?>, _ availableSpace: Size<AvailableSpace>) -> Size<Float>
```

**The two parameters cannot collapse into one.** A known width of 100 obliges the leaf to *return*
100; an available width of 100 obliges it to *wrap at* 100 and return its natural width. Grid track
sizing additionally needs "known in this axis, max-content constrained in the other."

**Text's answers:** `minContent` is the longest unbreakable run; `maxContent` is the single-line
width. Both are computed from cached advances (§6), not by re-shaping.

**Fixture roots** (§5.7) are measured with max-content in both axes, matching Taffy's harness.

### 5.6 Caching

**Per-frame layout cache**, in the layout tree. The key must include state that guards
*correctness*, not merely hit rate:

```
(runMode, requestedAxis, knownDimensions, knownDimensionsAreDefinite, availableSpace, parentSize)
```

with full-layout results held in a slot distinct from measure-only results. Two failures the first
draft's shorter key allowed: a size-only result returned to a request that expected children
positioned, and percentage padding/margin (our `Length` has `.percent`) resolving against a parent
size the key ignored.

**Cross-frame text caches — two of them, not one.** The first draft used a single key including
`availableWidth`, which meant a resize drag missed every frame and re-shaped every visible line —
precisely the cost §6 exists to avoid. Shaping output does not depend on width; only wrap boundaries
do:

| Cache | Key | Invalidated by |
|---|---|---|
| Shaping | `(textHash, fontStack, resolvedFontKey, features)` | font/text change |
| Wrap & measure | `(shapedLineID, availableWidth, wrapMode)` | width change |

Only the second invalidates on resize. Lines on §6.4's re-typeset path land in the second cache with
real per-width cost.

### 5.7 Test oracle

Ground truth is generated from **WebKit**. A test utility loads fixture HTML into a `WKWebView`,
reads back every node's `getBoundingClientRect()`, and writes a JSON golden file.

**Tolerance. (measured.)** The first draft's 0.01pt is unachievable: WebKit quantizes to 1/64px
(`LayoutUnit`) and error compounds with nesting. Measured on this machine — 3× `flex:1` in 700px →
Δ0.0104; 7× `flex:1` in 100px → Δ0.0268; `repeat(7, 1fr)` in 1000px → tracks of *unequal* used size;
a 4-deep 3-way split (243 leaves) → last right edge at 1000.5625, overflowing its own parent by
0.0625pt. A 9-leaf depth-2 fixture already busts 0.01.

The generator therefore records **both** raw rects and a **cumulative-rounded** layout
(`round(cumX + w) - round(cumX)` over viewport-absolute coordinates — Taffy's `round_layout`).
MetalUI applies the identical rounding pass, and assertions compare rounded values with a **0.1pt
tolerance** (Taffy's own figure). Raw values are retained for debugging only.

```
Tests/LayoutTests/
  Fixtures/flex_grow_basis_percent.html   ← plain CSS, box-sizing: border-box
  Golden/flex_grow_basis_percent.json     ← WebKit's answer + rounded layout
  FlexEngineTests.swift                   ← @Test(arguments:) over the corpus
```

Fixtures are readable CSS; the oracle is a production browser; a disagreement can be opened in Safari
and *seen*. Taffy's and Yoga's corpora are plain data and can be adapted.

### 5.8 Module

```
Sources/MetalUILayout/
  LayoutTree.swift   MeasureCache.swift   Alignment.swift   ← shared
  FlexEngine.swift                                          ← CSS Flexbox §9
  GridEngine.swift   GridPlacement.swift  GridTracks.swift
```

`Style` lives here; `Units` lives in MetalUICore (§5.3).

---

## 6. Text

CoreText does font fallback, bidi, and complex-script shaping better than we would. We use it for
shaping and rasterization and own everything above it.

| Stage | How | Owner |
|---|---|---|
| Font loading, features | `CTFontManager`; ligature/tabular-numeral controls | Us, thin over CoreText |
| Shaping | `CTLine`/`CTRun` from `CFAttributedString` | CoreText |
| Line breaking / soft wrap | Ours, gated (§6.4, §6.5) | **Us** |
| Rasterization | `CTFontDrawGlyphs` into our bitmap → atlas | Us, over CoreText |
| Atlas packing | Shelf packer; R8 monochrome, BGRA8 color | Us |

### 6.1 Rasterization

- **Subpixel positioning**: rasterize each glyph at a few fractional x-offsets, pick nearest. Without
  it, spacing visibly wobbles during horizontal scroll.
- **Atlas key**: `(resolvedFontKey, glyphID, size, subpixelVariant, scaleFactor)`.
  **(measured)** `resolvedFontKey` identifies the *resolved* `CTFont` including variation coordinates
  and matrix — **never a family or PostScript name**. Requesting `"SFMono-Regular"` by name on this
  machine returned a font whose PostScript name is `Helvetica`; name-based keys collide across
  entirely different outlines.
- **Grayscale AA only.** macOS retired LCD subpixel AA.
- **Color glyphs** (emoji, `COLR`/`sbix`) route to the polychrome atlas and skip tinting.

### 6.2 Fonts under canvas zoom

**Zoom re-keys rasterization only — but this requires pinning the optical size axis. (measured.)**

`CTFontCreateUIFontForLanguage(.system, …)` returns a variable font whose `opsz` axis tracks point
size (13pt→17, 26pt→26, 52pt→52). Advances for a 28-character label: **13pt = 164.804, 26pt = 301.703
— −8.5% versus 13pt × 2 = 329.608.** Positioning from base-size advances scaled by §7.1's matrix while
rasterizing at the zoomed size drifts progressively (~28px accumulated at 2× on one label).
Non-variable faces are exactly linear (Menlo, Helvetica verified identical at 13 and 26pt).

**Decision, corrected 2026-08-27 by measurement: pinning `opsz` does NOT make advances linear, and
it does not belong in M2.**

The paragraph here previously read: *"pin `opsz` via a `CTFontDescriptor` variation attribute for
canvas text. Advances then scale linearly, zoom folds into the atlas key's `size` component as
originally intended, and no re-shaping is needed."* Measured on §6.2's own 28-character string, via
`CTLineGetTypographicBounds`:

| | 13pt | 26pt | ratio |
|---|---|---|---|
| unpinned | 180.2544 | 329.9257 | **1.8303** |
| **pinned** | 157.7646 | 325.8379 | **2.0653** |
| pinned + reference size carried in the font matrix | 157.7646 | 315.5293 | **2.00000000** |

**A second mechanism defeats it, independent of the axis: CoreText's advances are hinted per size.**
Not integer-ppem quantization — a 0.125pt sweep of one glyph gives 6.322266 / 6.382202 / 6.436035 /
6.495667, which would be identical under ppem rounding. What is quantized is the advance in integer
**design units** (upem 2048), varying continuously and non-monotonically with size, converging on the
unhinted `CGFont` value at **80pt** and above. Helvetica and Menlo — no hinting, no axes — are
exactly linear at every size, which isolates the cause.

**And the pin is a no-op for linearity across M2's whole surface anyway.** The unpinned axis is
`clamp(size, 17, 96)`, so at every UI-chrome and code-editor size (8–17pt) it already sits at its
minimum and is already constant. What the pin actually changes there is the optical *design*:
measured cost 11.7% at 8pt rising to 13.0% at 17pt, and **zero at 28pt and above**. That is SF's
display cut used at text size — the precise tradeoff the optical axis exists to avoid — bought on the
only surface M2 ships and paying nothing anywhere M2 goes.

**So: no pin in M2** (`FontResolver.resolve` is a plain resolve), and **linear advances are an M5
canvas requirement solved by a fixed reference size carried in the font matrix**, which measures
exactly 2.00000000. Zoom drift on §6.2's label at 2×: unpinned **30.6px**, pinned **10.3px**, matrix
**0.0px**.

**The recorded consequence of the matrix approach, which is why it is M5 work and not M2's:**
`CTFontGetSize` then reports the *reference* size, so `FontKey`'s identity moves off `size` and onto
the matrix — a type that M2's shaping cache, atlas key and renderer all key on. Changing it belongs
with the canvas that needs it.

*(Two earlier revisions of this paragraph are folded in: the first draft claimed the pin was free
with no new machinery; the second claimed it delivered linearity. Both were wrong, and both were
found by measuring rather than by reading.)*

**Two glyph pipelines, chosen by SURFACE rather than by fallback. (Revised 2026-08-27.)**

- **UI chrome and the code editor: the CoreText atlas** described above. Fixed sizes, so the atlas
  keys are stable, and CoreText's hinting and stem darkening are exactly what 12–14pt needs.
- **The node canvas: MSDF.** One rasterization per glyph, scale-free, no re-keying under continuous
  zoom.

**This paragraph previously read "Rejected for v1: MSDF glyphs … documented as a fallback if bucket
thrash appears in profiling", and the premise under it was wrong.** It assumed the fixed-size shader
source editor was the demanding surface and the zoomable canvas was secondary. **The node editor is
the product**, so the canvas is the primary surface and continuous zoom is the primary case.

The quality argument inverts with that premise. MSDF's weakness is small text — thin stems, no
hinting — and on a canvas, small text is text nobody is reading: zoomed out it is a few points tall
and wants culling or LOD, zoomed in it is large, which is where SDF is strong. The atlas's weakness
is the opposite: fine at any *fixed* size, and thrashing precisely while the user is zooming.

**What both pipelines share, and it is most of the work.** §6.2's `opsz` pinning makes advances scale
linearly, so glyph *positions* are exact under a zoom matrix in either pipeline. Shaping, metrics and
the `MeasureFunction` are common. **The choice is only about how a glyph image is produced**, not
about layout.

**Accepted cost, recorded now rather than discovered at M5:** two glyph shaders and two atlas formats
(R8 for the CoreText path, a multi-channel texture for MSDF), plus MSDF generation from
`CTFontCreatePathForGlyph` outlines. Colour emoji route to `polychromeSprite` in both cases — MSDF
cannot represent them, which is why the atlas path is permanent rather than transitional.

**Sequencing: the atlas is M2, MSDF is M5.** §12's milestone table puts the node-graph prototype at
M5, so there is no zoomable canvas before then — and MSDF quality and bucket thrash cannot be
measured against a surface that does not exist. Building MSDF earlier would ship a claim nobody could
check.

Consequence: atlas eviction is mandatory (§7.6) for the CoreText path. The MSDF atlas does not
re-key on zoom and so does not need eviction for that reason.

### 6.3 Bidirectional text and the wrap fast path

**"Shape the logical line once, then wrap by walking cached advances" is incorrect for base-RTL
paragraphs. (measured.)** For `"عربي one عربي two عربي three عربي"` (Helvetica 13pt), the whole-line
`CTLine` gives run origins 0.0 / 24.3 / 27.9 / 57.6 / 61.2 / 85.5 …, while re-typesetting per display
line at width 110 gives **−3.6** / 0.0 / 20.2 / 23.8 / 48.2 … . The negative origin is UAX #9 L1's
per-display-line trailing-whitespace level reset. Neither the positions nor the run set are
reproducible from full-line advances. LTR-base wrapping at ordinary break opportunities *does* match.

**Design: shape-once/wrap-by-advances is a fast path behind a gate.** At shape time the shaper
computes and caches a per-line boolean: no run reports `CTRunStatus.rightToLeft` and no explicit bidi
control characters are present. Lines passing the gate wrap arithmetically. Lines failing it
**re-typeset per display line** via `CTTypesetterSuggestLineBreak` + `CTTypesetterCreateLine`, and
land in §5.6's wrap cache with real per-width cost.

Character-wrap snaps to grapheme-cluster boundaries and never splits a `CTRun` mid-cluster.

### 6.4 Line breaking

**CoreText exposes no width-independent line-break-opportunity API.**
`CTTypesetterSuggestLineBreak` takes a width by construction — the opposite of what an
arithmetic re-wrap needs. `NSString.enumerateSubstrings(.byWords)` is UAX #29 word segmentation, not
UAX #14, and is wrong for hyphens, CJK, and non-breaking sequences.

v1 implements a **hand-rolled UAX #14 subset** covering the classes a code editor and Latin/CJK UI
text actually hit: `BK CR LF NL SP ZW WJ GL BA HY NS OP CL QU AL NU ID CJ IN EX SY IS PR PO`, with
everything else falling back to `AL`. Full UAX #14 (~50 classes, pair table, tailoring) is out of v1.

**Overflow policy:** word wrap by default; a run with no break opportunity wider than the line falls
back to character wrap at grapheme boundaries. **Tabs** advance to the next multiple of the
configured tab width measured from the line start, and are a break opportunity (`BA`).

### 6.5 The UTF-8 / UTF-16 seam

**Every CoreText index is a UTF-16 `CFIndex`. (measured.)** For `"aa👨‍👩‍👧‍👦bb"` (UTF-8 length 29,
UTF-16 length 15): `CTRunGetStringIndices` → `[0,1] / [2] / [13,14]`, run range `(2, 11)`,
`CTLineGetStringIndexForPosition` at x=100 → 15. The first draft declared UTF-8 byte offsets and never
mentioned UTF-16. Both sides are `Int`, so the mismatch fails **silently on the first non-ASCII line**.

Contract:

- **Public offsets are UTF-8 byte offsets.** `String.Index` is grapheme-correct but O(n) — fatal for
  a 500k-line file.
- **CoreText-interior indices are UTF-16.** Translation lives **only** at the `CTLine` boundary.
- `ShapedLine` caches a per-line UTF-16↔UTF-8 map built at shape time; `ShapedRun` carries both its
  UTF-16 range (`CTRunGetStringRange`) and its UTF-8 byte range.
- The document seam requires any backing (rope or flat buffer) to expose a **per-chunk UTF-16
  summary**, so document-level conversion is O(log n). §8.4's `NSTextInputClient` calls arrive several
  times per keystroke.
- UTF-8 → `CFAttributedString` transcode cost is paid on a §5.6 shaping-cache miss only.

### 6.6 Caret and hit-testing API

**`x(forOffset:)` is not single-valued. (measured.)** For `"abc العربية def"` (Helvetica 13pt),
`CTLineGetOffsetForStringIndex` returns primary 24.57 / secondary 54.12 at **both** UTF-16 index 4 and
index 11, and `CTLineGetStringIndexForPosition` is non-monotonic (x=25→11, 30→10, 50→5, 55→11).
Independently, soft wrap makes one offset both the end of visual row N and the start of row N+1, at
different x *and* y — and soft wrap is ours and ships in M6 regardless of §5.2's RTL deferral.

```swift
enum CaretAffinity { case upstream, downstream }

struct ShapedLine {
    var runs: [ShapedRun]
    var rows: [VisualRow]            // wrap boundaries; ascent/descent/lineHeight per row
    var maxContentWidth: Pixels

    func x(forOffset offset: Int, affinity: CaretAffinity, row: Int) -> Pixels
    func offset(forX x: Pixels, row: Int) -> (offset: Int, affinity: CaretAffinity)
}
```

**Invariant:** these round-trip for a fixed `(row, affinity)` — not unconditionally. A selection
spanning a direction change is a **set of disjoint rects**, not one rect.

---

## 7. Renderer

### 7.1 Primitive set

Verified against gpui's shipping Metal shaders (`crates/gpui_apple/src/shaders.metal`, 1,279 lines,
16 entry points). Almost nothing is rasterized:

```swift
enum Primitive {
    case shadow(Shadow)                     // analytic blurred rounded box
    case rect(Rect)                         // SDF rounded rect: fill, gradient, per-side borders
    case path(Path)                         // Loop-Blinn implicit quadratics — FILLS ONLY
    case underline(Underline)               // analytic, incl. wavy
    case monochromeSprite(MonochromeSprite) // glyphs — tinted, R8 atlas
    case polychromeSprite(PolychromeSprite) // images, emoji — BGRA8 atlas
    case surface(Surface)                   // app-owned MTLTexture
}
```

| Primitive | Technique | Scale-independent |
|---|---|---|
| Rect (rounded, bordered, gradient) | Analytic SDF in fragment shader | yes |
| Shadow incl. blur | Closed-form blurred-box approximation, 4 samples | yes |
| Bezier path **fill** | Loop-Blinn implicit quadratic + gradient distance | tessellation-dependent (§7.5) |
| Underline | Analytic | yes |
| **Glyph** | CoreText → atlas sprite | no (§6.2) |
| **Image** | Decode → atlas sprite | no |
| App Metal content | Sampled texture | n/a |

**Scope of the gpui verification.** "Verified against gpui's shipping shaders" applies to rect,
shadow, underline, sprites, and path **fills**. It does **not** cover stroking: the shader file
contains zero occurrences of `stroke`, `winding`, or `fill_rule`, and gpui's `Path` is a raw triangle
emitter with no fill rule, no self-intersection handling, and no cubic entry point. §7.5 specifies
what we must build that gpui does not have.

**Loop-Blinn correction.** Loop & Blinn (2005) render cubics *directly* — classify as
serpentine/loop/cusp/degenerate, derive (k,l,m,n), test k³−lmn. The quadratic u²−v case is the
*degenerate special case*. gpui implements only that special case (`f = st.x*st.x - st.y`;
`curve_to(to, ctrl)` takes a single control point). **We follow gpui**: subdivide cubics into
quadratics. The full cubic path buys fewer primitives at the cost of cusp/loop handling and
self-intersection artifacts we do not need.

**Consequence for the node editor:** pan and zoom is a matrix change. Rect bodies, borders, shadows,
and already-tessellated quadratic fills are exact at any zoom (gpui's `Path::scale` just scales
vertices). Cubic-flattening tolerance and stroke *offset* approximation are scale-dependent and need
re-tessellation at large zoom (§7.5). Text is handled by §6.2.

**Naming.** `Rect`, not gpui's `Quad`. It remains a **single GPU primitive** with `cornerRadii`
(all-zero = sharp), because sharp and rounded rects interleave constantly and separate types would
force a batch break at every transition. A name-mapping table (`Rect`↔`Quad`,
`rect_fragment`↔`quad_fragment`, `rect_sdf`↔`quad_sdf`) lives in the renderer's doc comments so gpui
stays a one-hop reference.

### 7.2 Shader build strategy

**SwiftPM's default build system does not compile `.metal` files. (measured, Swift 6.3.3 /
Xcode 27.0 / macOS 26.6.2.)** This is the single most load-bearing correction in the document, and it
gates Milestone 0.

| Attempt | Result |
|---|---|
| `.metal` beside Swift sources, `swift build` | `warning: found 1 file(s) which are unhandled`, then **`Build complete!`** — and **no `.metallib` anywhere**. A silent success producing a non-functional product. |
| `.metal` declared in `sources:` | hard `error: unexpected input file` |
| `swift build --build-system swiftbuild` | emits a `CompileMetalFile` task, which **fails** |
| `xcrun metal --version` | `error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain` |
| `device.makeLibrary(source:options:)` at runtime | **works with no toolchain installed** — returned `["f_main", "v_main"]` |

**Decision: compile shaders at runtime from bundled source.** `shaders.metal` and
`MetalUIShaderTypes.h` ship as SwiftPM resources, are read from `Bundle.module`, and the header is
**textually prepended to the shader source** before `makeLibrary(source:options:)`.

The prepend is not stylistic: `MTLCompileOptions` exposes only `preprocessorMacros` and **no include
search path**. `#include "…"` was observed to resolve at runtime, but the rule is undocumented and
resolved identically from two different working directories, so it cannot be relied on.

This is the only route that works under plain `swift build`, and it is what keeps §2's "consumable as
an ordinary SwiftPM dependency, no `unsafeFlags`" true.

**Consequences recorded honestly:**

- §7.2's first-draft claim of "compiler-enforced agreement" between the C header and Swift is
  **false** under runtime compilation — nothing reads the `#include`. Agreement is instead enforced by
  a **test that asserts `MemoryLayout<T>.size` / `.stride` / `.offset(of:)` against values probed from
  a GPU-side kernel**, one case per shared struct. That test is mandatory, not optional.
- An offline `.metallib` remains an **optional** build-tool-plugin path for startup cost. Its
  prerequisites are recorded so nobody rediscovers them: `--build-system swiftbuild` or Xcode,
  `xcodebuild -downloadComponent MetalToolchain`, a plugin trust prompt, and per-platform SDK variants
  (macos/ios/simulator). A single committed prebuilt `.metallib` is **not** viable.
- Startup cost: one `makeLibrary` compile per process. Measured cost and any need for an on-disk
  binary-archive cache is an M0 open item.

### 7.3 Ordering, clipping, batching

Primitives are appended during `paint` with a monotonically increasing `order`. At submit, the scene
sorts by order and **groups consecutive runs of the same type into one instanced draw call**.
Draw-call count is the number of *type transitions* in z-order.

**Clipping is per-primitive via `[[clip_distance]]`, not scissor rects.** Scissor clipping would force
a state change and therefore a batch break at every clip boundary; clip distances make clipping free
and composable with instancing.

**Draw-call expectation, stated with its constraint.** The "under ~10 draw calls" figure holds when
same-type primitives are contiguous in z-order. Paths in particular batch only in contiguous runs
(§7.4). The M5 node-graph demo is designed accordingly: all wires on one layer beneath all node
bodies, rather than interleaved per node.

### 7.4 Frame graph

```
1. App Metal passes    each MetalView encodes into its retained target texture (§7.7)
2. for each contiguous run of paths in z-order:
       path rasterization pass → intermediate texture (cleared per run)
       that run's path-sprite draw
   interleaved with the main pass's other batches, in order
3. Present             via RenderSurface
```

**Stage 2 is a loop, not a single stage.** `path_sprite_vertex` computes
`texture_coords = screen_position / viewport_size` — a **screen-space** lookup into one shared
intermediate. With a single rasterization stage, any two paths overlapping in screen space merge
their coverage and each sprite samples the union: a node body at order 20 could not sit between a
wire at order 5 and a wire at order 50, and two same-layer overlapping wires would double-composite.
The intermediate is viewport-sized, `bgra8Unorm` (§7.8), and cleared at the start of each run.

All stages share **one `MTLCommandBuffer`**. Buffers are a triple-buffered ring guarded by a
semaphore, `.storageModeShared` on Apple Silicon.

### 7.5 Path pipeline (CPU side)

gpui provides no equivalent, so this is ours to build and budget.

- **Cubic → quadratic subdivision** with a stated error bound; tolerance is a function of the current
  canvas scale, so large zoom re-tessellates.
- **Flattening tolerance** likewise scale-dependent.
- **Interior triangulation with an explicit fill rule** (nonzero for v1). gpui's fan emitter has no
  fill rule and double-blends overlapping fan triangles under `over`; we cannot inherit that for node
  graphs where wires cross.
- **Stroke-to-fill** uses `CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:transform:)` and
  `copy(dashingWithPhase:lengths:)`, which cover joins, caps, miter limits, and dashes on all target
  platforms with **no new dependency**. Interior triangulation of the resulting outline is the real
  remaining work.

### 7.6 Atlas

Shelf packer; `R8Unorm` for glyph coverage, `bgra8Unorm_srgb` for color content (§7.8). Growth adds
textures rather than reallocating, so live handles stay valid.

**Eviction is mandatory** (§6.2 mints rasters continuously under zoom), with these rules:

- Entries touched by the **current frame are pinned** and never evicted. Evicting a glyph already
  referenced by an emitted primitive corrupts the frame — exactly the pressure zoom creates.
- If one frame's live working set exceeds capacity, **allocate an additional page**; degraded
  rendering is never acceptable mid-frame.
- A sprite larger than the atlas texture dimension gets a **dedicated single-sprite texture** rather
  than failing.
- Otherwise LRU by last-used frame generation.

### 7.7 `MetalView` — app-owned rendering

```swift
struct MetalView: Element {
    var id: ElementID
    var invalidation: MetalViewInvalidation   // handle: .version(n) or .continuous
    var draw: (MetalDrawContext) -> Void
}

struct MetalDrawContext {
    let device: MTLDevice
    let commandBuffer: MTLCommandBuffer   // the SAME buffer as the UI
    let target: MTLTexture
    let depth: MTLTexture?
    let size: Size<DevicePixels>
    let frameIndex: UInt64
    let time: Double                      // target presentation timestamp (§4.4)
}
```

**Targets are retained per element in §4.3's state table, not pooled per frame.** The first draft's
pooled target is incompatible with `.onDemand`: when the window redraws for an unrelated reason —
hover elsewhere, caret blink, another pane resizing, the common case — an on-demand view's `Surface`
must reference a texture still holding **last frame's** contents. Targets are reallocated only on
size or scale change, and double-buffered against the §7.4 ring so the GPU is never reading a texture
being rewritten.

**Invalidation is explicit, because observation cannot cover it.** §4.4 wraps only `buildFrame()` in
`withObservationTracking`, while app Metal passes run in stage 1 of submit — so **reads inside `draw`
are not tracked**. The app bumps a version on its `MetalViewInvalidation` handle (or declares
`.continuous`), and that feeds §4.4's dirty flag.

**Contract with app code**, stated so violations are diagnosable: the app must **not** `commit()`,
must **not** `waitUntilCompleted()`, and must **not** present. Command-buffer errors from
app-encoded work surface through an error channel on the element rather than silently losing frames.

Three properties this buys:

- **No synchronization tax.** Same device, queue, command buffer, and frame.
- **The viewport is a texture, so §7.1's SDF machinery applies to it** — rounded corners, borders,
  shadows, translucent panels blended over live 3D, gizmos on top, all ordinary rects in the same
  pass.
- **Idle costs nothing.** A static preview requests no frames.

The same `Surface` path carries `IOSurface`/`CVPixelBuffer` content (video, camera) later.

### 7.8 Color

**Decision: composite in sRGB (gamma) space, following gpui.** *(Revised — the first draft specified
linear compositing as "physically correct".)*

**Why the reversal.** gpui sets `layer.set_pixel_format(MTLPixelFormat::BGRA8Unorm)` — **not**
`_sRGB` — and all atlas and intermediate textures are `BGRA8Unorm`; `srgb_to_linear`/`linear_to_srgb`
appear only in gradient helpers. It composites in gamma space and interpolates gradients in Oklab.
`monochrome_sprite_fragment` does `color.a *= sample.a`, using R8 coverage directly as a blend weight.
Coverage produced by a rasterizer tuned for perceptual blending, then composited linearly, makes
light-on-dark text thin and washed and dark-on-light text heavy — and §6.1 commits to grayscale AA, so
coverage is the only lever. This configuration is what ships in Zed today at exactly our workload.

Specification:

- **Working space: gamma-encoded sRGB.** Drawable format **`bgra8Unorm`** — *not* `_sRGB`. This is
  load-bearing: an `_sRGB` target makes the hardware decode to linear before blending and re-encode
  after, which is linear compositing, the opposite of this decision. `bgra8Unorm` blends on the
  stored gamma-encoded values. Layer colorspace is Display P3.
- **Colors** reach the shader as HSLA and are converted to gamma-encoded sRGB in-shader. No
  linearization anywhere in the composite path.
- **Gradients** are converted to Oklab, interpolated there, and converted back to gamma-encoded sRGB
  before output — perceptually even ramps without linear compositing.
- **Glyph coverage** (`r8Unorm`) is used as a blend weight directly, unmodified.
- **Polychrome atlas** is **`bgra8Unorm`**, no decode. sRGB-encoded image and emoji bytes are already
  in the working space; sampling through an `_sRGB` view would decode them to linear and composite
  them wrongly. (An earlier revision specified `_sRGB` here — that was correct only under linear
  compositing, which §7.8 rejects. gpui is self-consistent on this and we follow it.)
- **EDR / HDR preview** applies to the `MetalView` surface only: the app's target may be
  `rgba16Float` in `extendedLinearDisplayP3`, tone-mapped or passed through at the surface boundary.
  This gives correct HDR shader preview without hand-tuning text rendering. **(measured)** EDR is
  `API_UNAVAILABLE(tvos, watchos)`, which is moot for v1 (§2) but is why the capability is
  feature-gated rather than assumed.
- Switching SDR/EDR modes is a **pipeline-state change**, not a runtime flag.

§11 carries renderer golden cases for white-on-black and black-on-white body text at 12–14pt.

### 7.9 Theming

Colors in element code are **semantic tokens** (`.surfaceSecondary`, `.textPrimary`), never literals.
A `Theme` maps tokens to HSLA values and is supplied at the window level and propagated through the
frame context, so no element reads global state.

HSLA at the API boundary makes hover/active derivation (lighten, desaturate) trivial; conversion to
the working space happens in-shader.

System appearance and accent changes (`NSApp.effectiveAppearance` /
`traitCollectionDidChange`) swap the active theme and mark §4.4's dirty flag. Ships with **M1**,
alongside styling.

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
    case touch(TouchEvent)                  // iOS
    // reserved: case focusMove(FocusMoveEvent)  // tvOS
    // reserved: case spatial(SpatialEvent)      // visionOS
}
```

Handlers are registered during `paint` with a **capture or bubble** phase; dispatch runs against the
most recent frame's handler set. Capture lets a modal or in-progress drag swallow events without
restructuring the tree.

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

**Context contribution.** Elements contribute to the context stack during `prepaint`, alongside focus
handles:

```swift
.keyContext("Editor", ["mode": "code"])
```

Values are `String`; the predicate language is `identifier`, `key == value`, `&&`, `||`, `!`.
Dispatch builds the stack from the focus chain and matches **innermost-first**, bubbling the action
up until handled.

**Keystroke matching uses `charactersIgnoringModifiers`, not physical key codes** — physical matching
is the long-standing source of Dvorak and AZERTY breakage.

**Multi-stroke:** v1 supports one- and two-stroke sequences. The pending-prefix timeout is **1 second**;
on expiry the prefix is **dropped**, not dispatched.

### 8.4 IME

Not optional and not v2: without it, `é` is untypeable and CJK input is impossible.

**`NSTextInputClient` conformance alone does nothing.** `NSTextInputContext.handleEvent:` is what
routes an event into the input system, and its position relative to §8.3's keymap is a design
decision, not an implementation detail — keymap-first makes dead keys and CJK conversion untypeable,
the exact failure this section exists to prevent.

**Order:**

```
keyDown → NSTextInputContext.handleEvent:
        → if unhandled AND no marked text → §8.3 keymap → action dispatch
```

- `doCommandBySelector:` maps to framework actions.
- While marked text exists, keymap dispatch is **suppressed**, except for a stated escape hatch
  (Escape, which cancels composition).
- All `NSTextInputClient` ranges are **document-relative UTF-16 `NSRange`s** — see §6.5. This is why
  the document seam must provide O(log n) UTF-16↔UTF-8 conversion: these calls arrive several times
  per keystroke.
- `firstRectForCharacterRange:` and `characterIndexForPoint:` are in **screen** coordinates. The
  platform layer supplies the content→window→screen mapping.
- §4.4's post-commit step calls `invalidateCharacterCoordinates` when the caret rect moved, and the
  macOS 14+ `textInputClientWillStartScrollingOrZooming` / `…DidEndScrollingOrZooming` pair around
  scrolls.

iOS uses `UITextInput` with the same ordering.

---

## 9. Accessibility

**In v1.** A framework that renders every pixel itself gets **nothing** from the system for free:
with one `CAMetalLayer` there are no per-element views, so AX elements must be synthesized.

**Why this is in the design doc rather than deferred to implementation:** AX clients retain element
references across frames, which makes §4.3's `GlobalElementID` side table the only structure that can
back stable AX identity. That constrains §4.3 **now**, whether or not the bridge ships first.

Specification:

- **Emission.** Elements emit an AX node during `prepaint`: role, label, value, traits, actions,
  frame, and ordered children. Emission during `prepaint` (not `paint`) means bounds are resolved and
  culled content is naturally excluded.
- **Identity** derives from `GlobalElementID`. A node an AX client still holds survives §4.3's sweep
  as a **tombstone that reports itself invalid**, rather than vanishing and leaving a dangling
  reference.
- **Bridge.** A per-frame diff drives `NSAccessibilityElement` (macOS) / `UIAccessibilityElement`
  (iOS) children on the host view, posting change notifications only for what actually changed.
- **Focus.** AX focus and §8.3 focus handles are the same focus; the bridge reflects one into the
  other rather than maintaining two.
- **Virtualized content** (§4.7) exposes the full logical count with realized children, so VoiceOver
  reports "3 of 500" correctly.
- **System settings** propagate into the frame context and mark §4.4 dirty on change: Reduce Motion
  (suppresses animation), Increase Contrast (theme variant), Dynamic Type (root font size → `Rems`).

Ships incrementally: nodes and identity with **M3** (when interaction exists), the platform bridge in
**M4**.

---

## 10. Assets and images

The first draft had a `polychromeSprite` primitive and an atlas but no load API — an app could not
display an image.

```swift
Image(.bundled("icon-compile"))      // scale variants resolved from the bundle
Image(.data(bytes))
```

- **Formats:** whatever ImageIO decodes (PNG, JPEG, HEIC, TIFF, GIF first frame). No custom decoders.
- **Scale variants:** `@1x`/`@2x`/`@3x` resolved against the window's scale factor.
- **Async:** decoding happens off the main actor (§3.3); the element renders a placeholder and marks
  §4.4 dirty on completion. Decode failure renders a diagnostic placeholder and logs — never crashes,
  never silently renders nothing.
- **Cache:** decoded images live in an LRU keyed by `(source, targetScale)`, **separate from §7.6's
  glyph atlas policy** — a large image should not evict the entire glyph working set. Images above a
  threshold get dedicated textures rather than atlas pages.

**SVG is out of v1** (§14). It needs XML parsing, path-data grammar, transforms, gradients, clip
paths, `use`/`defs`, and `viewBox`, plus a rasterize-at-zoom policy that reintroduces the exact
problem §6.2 solves for text. M5 already carries Grid, paths, and `MetalView`. Icons in v1 come from
pre-rasterized assets or the path primitive directly.

---

## 11. Testing

Swift Testing (`import Testing`); parameterized tests carry the fixture corpora.

| Layer | Method | Catches |
|---|---|---|
| Layout | WebKit golden files (§5.7), `@Test(arguments:)` over the corpus, cumulative rounding, 0.1pt tolerance | Flex/grid algorithm errors |
| Shader ABI | `MemoryLayout` size/stride/offset asserted against GPU-probed values, one case per shared struct | CPU/GPU struct drift, which §7.2 can no longer catch at compile time |
| Text | Golden metrics per string × font; round-trip property test for fixed `(row, affinity)` on **wrapped** fixtures, asserted against an **independently computed** UTF-8 offset | Caret drift; a shared broken UTF-16 mapping passing trivially |
| Renderer | Offscreen render → reference PNGs, perceptual tolerance; explicit white-on-black and black-on-white 12–14pt text cases | Shader regressions; §7.8 coverage/gamma errors |
| Interaction | Headless `TestWindow`: runs frames with no real window, injectable clock, synthesized events | "Click fires the action", "scroll updates offset", "typing updates the doc" |
| Accessibility | Assert the emitted AX tree for representative screens; identity stability across frames | Missing labels, unstable identity, tombstone regressions |
| Concurrency | Swift 6 strict mode | Data races, at compile time |

**What runs under plain `swift test`:** layout, text metrics, interaction, and accessibility are fully
headless. Shader-ABI and renderer-golden tests require a Metal device; they run on macOS CI and are
skipped with an explicit `withKnownIssue`-style marker elsewhere, never silently.

`TestWindow` exists only because `RenderSurface` and `Platform` are protocols and the frame loop is
driven by an injectable clock. Testability is a consequence of §3.2's seams.

---

## 12. Build order

Each milestone ends in something runnable.

| # | Scope | Exit criterion |
|---|---|---|
| **0** | Core geometry/units/color, shared C header + **runtime shader compilation (§7.2)**, shader-ABI test, Metal setup, `RenderSurface`, AppKit window | A window showing one rounded rect with a border |
| **1** | Flexbox + WebKit golden harness; `Element`, three phases, `Frame`, state table, `AnyElement`; `Box`/`Column`/`Row`; styling; **theming (§7.9)** | Nested flex layout that resizes correctly; light/dark switch |
| **2** | CoreText shaping, UTF-8/UTF-16 seam, glyph raster, atlas, monochrome sprites, `Text` + measure integration | Styled text in flex layout, correct on Retina; non-ASCII correct |
| **3** | Hitboxes, mouse dispatch, hover/active, focus, keymaps, actions, scroll containers, **virtualization (§4.7)**, **AX nodes + identity (§9)** | Counter demo; a 100k-row virtualized list scrolling smoothly |
| **4** | `@Observable` integration, dirty tracking, display-link scheduling, `Component` + result builders, animation & easing, **AX platform bridge** | A real small app; **no frames built and display link paused while idle**; VoiceOver navigates it |
| **5** | Grid engine + fixtures, **path pipeline (§7.5)**, images (§10), **`MetalView`** | **Node-graph prototype: bezier wires, grid inspector, live 3D preview with UI composited over it** |
| **6** | Soft wrap + UAX #14 subset, bidi gate, selection, IME + `NSTextInputContext` ordering, caret affinity | Shader source editor usable; CJK and accented input work; runs on iPad |

**Milestone 5 is the target** — where the shader app's three organs exist in one window.

Two honest notes. **M1 is the longest single stretch**, because flexbox plus its harness is weeks of
work with little to show mid-way; the golden corpus is what keeps it from being a leap of faith.
**M6's text work is a direction, not a finish line** — "editor-grade text" will be revisited
continuously once you are actually editing shaders in it.

---

## 13. Known risks

| Risk | Mitigation |
|---|---|
| Hand-written flex/grid subtly wrong | WebKit oracle (§5.7) with cumulative rounding; disagreements inspectable in Safari |
| M1 is a long stretch with little visible output | Golden corpus provides continuous objective progress |
| Runtime shader compilation adds startup cost | Measured in M0; binary-archive cache if needed (§7.2) |
| CPU/GPU struct drift, no longer compiler-caught | Mandatory `MemoryLayout`-vs-GPU-probe test (§11) |
| Path pipeline is ours alone — gpui has no stroke or triangulator | Scoped in §7.5; `CGPath` covers stroke-to-fill; triangulation is the real work |
| Per-frame allocation / ARC churn | Concrete-typed builders, then virtualization, then bump allocator (§4.6) |
| Atlas growth during canvas zoom | LRU with current-frame pinning and page growth (§7.6) |
| Complex-script wrap correctness | Bidi gate with per-line detection (§6.3); re-typeset path for failures |
| UAX #14 subset misses cases | Stated class list (§6.4); expandable without design change |
| IME/keymap ordering wrong | Order specified in §8.4; M6 exit criterion tests CJK and dead keys |
| AX identity unstable across frames | Tombstones in §4.3; identity-stability test in §11 |
| `content` doing expensive work each frame | Documented hard rule; surfaced by frame-time instrumentation |
| visionOS retrofit forces redesign | `RenderSurface` returns N views with projection matrices; `InputEvent` reserves spatial cases (§3.2) |

---

## 14. Explicitly out of v1

Recorded so deferral is a decision rather than an oversight.

| Deferred | Note |
|---|---|
| tvOS | Shares the UIKit backend; needs a pointerless input model (§2) |
| visionOS | Forks render loop and input; seams designed (§2, §3.2) |
| Linux / Windows | Seams are protocols; nothing planned |
| CSS Grid subgrid, named areas, grid baseline alignment | §5.4 |
| Block/inline layout, floats, writing modes | §5.2 |
| RTL layout direction | `Edges` stays semantic (§5.2); bidi *text* is handled (§6.3) |
| `content-box` sizing | `border-box` only (§5.2) |
| Full UAX #14 | Stated subset (§6.4) |
| MSDF glyphs | Fallback if zoom-bucket thrash appears (§6.2) |
| Exit/removal transitions | Forbidden by §4.3's sweep; needs tombstones |
| SVG | §10 |
| Localization | The app's concern at this layer |
| Direct-mode `MetalView` (app drawing into the UI's own pass) | Texture mode only (§7.7) |
