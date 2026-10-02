# Paths, shadows and transforms — decisions

Rulings for paths, shadows and render transforms (user request 2026-10-02,
item 3 of the gpui-gap priority list; **not a plan task** — feature work after
plan task 15, like drag and drop and MetalView). Spec:
[`specs/2026-10-02-paths-shadows-transforms-design.md`](specs/2026-10-02-paths-shadows-transforms-design.md).
Record: `../record/73-paths-shadows-transforms.md` (written at the Record
phase; renumbered there if another line publishes §73 first). Evidence:
[`../probes/swiftui-paths-shadows-transforms.swift`](../probes/swiftui-paths-shadows-transforms.swift)
(**new**; arm ids `P…` controls, `PA…` paths, `ST…` strokes, `SH…` shadows,
`T…` transforms, `H…` hit testing, `X…` accessibility frames, `N…`
animation; its header carries the recorded output, run twice byte-identical,
and the reading). Where SwiftUI has no answer (the rendering technique), the
ruling says so and names gpui's approach as the comparison, not as evidence.

Prefix **`GX-`**, lettered. **Next unused: `GX-T`.** (This line moves in the
commit that appends a ruling; read the last `## GX-` heading.)

Branch `feat/paths-shadows-transforms` from `dc96395` (master: the scaffold
review merged, PR #42). Baseline at `dc96395`: **2124 tests in 3 suites, 0
goldens, 129 typecheck guards** (the scaffold record's count line,
`38e9516`), 70 live divergences, **next label 104** (`docs/divergences.md`
line 12).

**Carried items.** The shapes-and-rendering spec's §9 table
(`specs/2026-09-28-shapes-and-rendering-design.md`) names `Path`, custom
`path(in:)` shapes and `StrokeStyle` as renderer constraints, owner none;
`TE-AG` narrows `Shape.path(in:)` to `geometry(in:)`; `Shape.swift`'s header
and `ShapeView.swift`'s header repeat it; `docs/divergences.md`'s
documented-absences table row "`Path`, gradients, `StrokeStyle`, SF Symbols,
colour glyphs". This branch discharges the `Path`/`path(in:)`/`StrokeStyle`
parts (`GX-B`…`GX-E`) and leaves gradients, SF Symbols and colour glyphs
where they are. `AN-AE`'s `.scale` transition (a post-transform of the
emitted scene range, `TransitionEffect`) is the machinery `GX-G` generalizes.
No decisions doc's "Carried…" section names a shadow, a rotation or an
`offset` render effect.

---

## GX-A — Scope: what this branch builds, what it defers

**Ruling.** Build, SwiftUI-spelled and probe-backed:

1. `Path` — a value type, a `Shape`, and a view — with `move`, `addLine`,
   `addLines`, `addQuadCurve`, `addCurve`, `addArc(center:radius:startAngle:endAngle:clockwise:)`,
   `addArc(tangent1End:tangent2End:radius:)`, `addRect`, `addRects`,
   `addRoundedRect(in:cornerSize:style:)`, `addEllipse(in:)`, `addPath`,
   `closeSubpath`, plus `boundingRect`, `isEmpty`, `currentPoint`,
   `contains(_:eoFill:)` and `offsetBy(dx:dy:)` (`GX-C`); filled under
   nonzero and even-odd (`FillStyle`), stroked under the whole `StrokeStyle`
   — width, cap, join, miter limit **and dashes** (`GX-E`); `Shape` gains
   SwiftUI's `path(in:)` (`GX-D`).
2. `.shadow(color:radius:x:y:)` on both vocabularies (`GX-J`).
3. `.rotationEffect(_:anchor:)`, `.scaleEffect(_:anchor:)` (scalar and
   `SizeD`), `.scaleEffect(x:y:anchor:)` and `.offset(x:y:)`/`.offset(_:)` on
   both vocabularies, changing paint, hit testing and accessibility frames
   but not layout (`GX-F`…`GX-I`).
4. A looks-demo section and a human-checks group.

**Deferred, each named in spec §9 with owner none**: `transformEffect`,
`projectionEffect`, `rotation3DEffect`; `Path.applying(_:)` and every
`transform:` parameter, `addRelativeArc`, `trimmedPath`/`Shape.trim`,
`strokedPath`, SVG strings; `compositingGroup()`/`drawingGroup()`; inner
shadows and `ShapeStyle` shadows; `.blur(radius:)`; gradients; a shape's
stroke width animating (divergence 97 amended); text and images
re-rasterized at an effect's scale (divergence 106); `clipShape` of a path
(divergence 91 amended).

**Reasoning.** The request asks to "prefer landing Path + shadow +
rotation/scale/offset solid over half of everything". Dashes are in because
on a flattened polyline they are an arc-length walk the stroker already does
(no new technique), and SwiftUI's probe gives three exact rows to pin (ST7).
The deferred transforms need a projective (3D) primitive or an arbitrary
public affine type MetalUI does not yet expose; nothing the request names
depends on them.

**Cost if wrong.** A deferred item a user needs is one more branch; none of
them is foreclosed by a choice here (`GX-F`'s transform record is a full
2×3 affine, so `transformEffect` is an API addition, not a renderer change).

---

## GX-B — Paths are rasterized on the CPU, in a portable target, and drawn as images

**Ruling.** A path's coverage (fill or stroke) is computed on the CPU by an
exact-area scanline rasterizer (signed area and cover accumulated per pixel,
the font-rasterizer technique), in a **new portable target `MetalUIPath`**
that imports nothing (pure Swift standard library — no Foundation, no
`MetalUICore`), and reaches the screen as an ordinary `MUIImage` over an
`ImageTexture` (premultiplied RGBA8, the fill colour times coverage),
pixel-aligned in device space. **No new primitive kind, no shader change and
no stride change for paths.**

- The rasterizer works in **device pixels after the composed transform**
  (`GX-G`): a path is flattened, stroked and rasterized under the full affine
  that maps it to the target, so it is crisp under any `rotationEffect`/
  `scaleEffect` — SwiftUI's own answer (probe T16: a 1 pt diagonal under
  `scaleEffect(4)` has 118 solid pixels, impossible for a resampled line).
- **Fill rules** read the accumulated winding: nonzero is `min(|w|, 1)`,
  even-odd is the triangle wave of `|w|` (PA2's four answers).
- **Flattening** is adaptive by a fixed tolerance (0.1 device px) with
  segment counts from the control polygon (Wang's bound — `sqrt`, `*`, `+`,
  `/` only); **arcs become cubic Béziers of at most 90°**.
- **Trigonometry is `MetalUIPath`'s own** (`PathMath.sinCos`, Cody–Waite
  range reduction and a fixed minimax polynomial in `Double`, basic
  operations only): the Swift standard library has no `sin`, and libm's
  differs by platform, so a path's coverage is **bit-identical on macOS,
  Linux and Windows** (pinned by a hashed corpus, spec test 1.26, run by
  Linux and Windows CI). `rotationEffect` uses the same function (`GX-H`).
- Only the **visible part** is rasterized: the raster rectangle is the
  path's device bounding box ∩ the clip in effect ∩ the target, so no image
  exceeds the window.
- Rasters are **cached by value** (`GX-K`), so a path that does not change
  keeps one `ImageTexture` identity and the renderers' texture caches
  (`TE-AF`) upload it once.

**Alternatives rejected.**

- *GPU tessellation with MSAA or analytic edge AA* (gpui's current path
  pipeline rasterizes path triangles into an intermediate texture): sample
  patterns and triangle rasterization rules are backend-defined; the parity
  harness judges outside sprites at ≤ 1 per channel on llvmpipe and D3D12,
  which MSAA resolves do not guarantee. It also needs a new pipeline and
  vertex format in both shader languages.
- *Stencil-then-cover*: needs a stencil attachment and two passes in both
  renderers and in `SDLBridge.c`; even-odd is natural, but antialiasing
  needs MSAA again.
- *An SDF per segment*: cost grows with the segment count per pixel, and
  even-odd/nonzero winding is not a distance.

The CPU route renders identically on Metal and SDL **by construction** — both
draw the same `MUIImage` through the image pipeline, which already passes the
replay-parity harness (frame 6, `TE-AF`) — and is deterministic for
`DemoFrameDeterminismTests`' kind of pin. **gpui's answer is GPU paths; this
ruling departs from it deliberately**, for parity and determinism.

**Cost if wrong.** CPU time per changed path (flatten + rasterize is linear
in the raster's area and the edge count) and one texture upload per changed
raster. An animated path (a `Path` view snaps, N7, so only a path under an
animated effect re-rasterizes) or a very large stroked path costs a frame's
budget. `CapturedPrimitive.path` (`GX-G`) keeps the vector form to the end, so
a GPU rasterizer can later replace the CPU one behind the same seam without
touching the public API. Performance tests count rasterized pixels
(`RasterCache.lastRasterizedPixels`), never time.

---

## GX-C — The `Path` surface: SwiftUI's spelling over MetalUI's geometry

**Ruling.** `public struct Path: Shape, Equatable, Sendable` in `MetalUI`
(`Path.swift`), storing its elements as `Point<Pixels>` values (MetalUI's
geometry — no `CGPoint`/`CGRect` crosses the portable seam, `TE-AL`'s
precedent), with SwiftUI's initialisers (`init()`, `init(_ rect:)`,
`init(roundedRect:cornerRadius:style:)`, `init(roundedRect:cornerSize:style:)`,
`init(ellipseIn:)`, `init(_ build: (inout Path) -> Void)`) and the mutators
of `GX-A` item 1. A new `public struct Angle` (`.degrees(_:)`,
`.radians(_:)`, `degrees`/`radians`, `zero`, `Hashable`, `Comparable`,
`Sendable`, arithmetic) carries arc and rotation angles, as SwiftUI's does.

- **Coordinates are local**: a `Path` view draws its path from its own
  layout origin, neither scaled to nor clipped by its frame (PA1, PA1b), and
  answers its proposal like every shape (nil → 10, PA1 sizes).
- **`clockwise` is SwiftUI's flag**: in y-down screen space `clockwise:
  false` from 0° to 90° sweeps through the below-right quadrant (PA3) — the
  flag reads in y-up terms, so MetalUI's arc sweeps the **positive** angle
  direction (visually clockwise) when `clockwise` is `false`. Pinned by
  1.19 and 3.x on both sides of the flag.
- **An open subpath fills as if closed** (PA6); `addEllipse` equals
  `Ellipse()` (PA5); `addRoundedRect`'s default style is `.continuous`
  (PA5), drawn circular (divergence 90, amended: the path's corners are the
  same circular arcs `RoundedRectangle` draws).
- A bare `Path` fills with `foregroundStyle ?? .textPrimary` (PA8, `TE-AH`).
- `Path.contains(_:eoFill:)` tests winding at a point (the rasterizer's
  flattening, unantialiased) — `contentShape(Path)` uses it (`GX-D`).

**Reasoning.** SwiftUI code ports by renaming `CGPoint(x:y:)` →
`Point(x:y:)` (both take literals: `Pixels` is `ExpressibleByIntegerLiteral`)
and `CGRect` → `Bounds`, the same port every MetalUI geometry already asks for.

**Cost if wrong.** Caller-visible spelling; the deferred members
(`applying`, `transform:`, `trimmedPath`, `strokedPath`, `addRelativeArc`)
are additive later.

---

## GX-D — `Shape.path(in:)` joins the protocol beside `geometry(in:)`

**Ruling.** `Shape` gains SwiftUI's requirement `func path(in rect:
Bounds<Pixels>) -> Path`, and **both** requirements get defaults:
`geometry(in:)`'s default is `.path(path(in: localRect).offsetBy(origin))`,
`path(in:)`'s default converts `geometry(in:)` (a rounded rectangle or an
ellipse) to a `Path`. A conformer implements **either**; one that implements
**neither** would recurse forever, so the defaults set a per-thread
reentrancy flag and **trap naming `GX-D`** on re-entry — pinned by an exit
test reading the trap's message (3.4). `ShapeGeometry` gains a third kind,
`.path(Path, FillStyle)` (`public static func path(_:style:)`).

- **`path(in:)` receives the shape's LOCAL rect**, origin (0, 0) (PA9 —
  SwiftUI's answer); the framework offsets the result by the layout origin.
  **`geometry(in:)` keeps receiving the window-space rect it always has** —
  source compatibility for every existing conformer, at the price of two
  conventions, each documented on its requirement.
- **The built-ins keep their analytic primitive**: `Rectangle`,
  `RoundedRectangle`, `Circle`, `Capsule`, `Ellipse` still implement
  `geometry(in:)` and still draw one `MUIRect` (SDF) per fill — no image, no
  rasterization, unchanged bytes (3.5) — and gain a working `path(in:)` by
  the default conversion (3.6).
- `Path` itself implements `geometry(in:)` as `.path(self.offsetBy(rect
  origin), .init())`.
- **A `.path` geometry's hit test is its winding** (`contentShape(_:)`,
  `IX-L`'s `ShapeGeometry.contains`): nonzero unless its style says even-odd.
- **A `.path` geometry in a clip traps** exactly as an ellipse does
  (divergence 91, amended: "`clipShape` of an ellipse or a path"): every
  primitive's mask is a rounded rectangle (`GX-F` does not change that).

**Alternatives rejected.** *`geometry(in:)` alone, with a `.path` case*: no
recursion hazard, but SwiftUI shapes would need rewriting into a MetalUI-only
requirement — rejected for SwiftUI alignment, since the trap makes the hazard
loud. *Replace `geometry(in:)` by `path(in:)`*: breaks every outside
conformer and drops the built-ins' exact SDF primitives.

**Cost if wrong.** A conformer implementing neither requirement traps at its
first paint rather than failing to compile. Guard
`anOutsideShapeCanWritePathInAlone` pins that the SwiftUI spelling compiles.

---

## GX-E — Fill and stroke styles

**Ruling.**

- `public struct FillStyle { isEOFilled, isAntialiased; init(eoFill:antialiased:) }`;
  `Shape.fill(_ token:style:)` and `.fill(style:)`. `antialiased: false`
  thresholds coverage at 0.5.
- `public struct StrokeStyle { lineWidth, lineCap, lineJoin, miterLimit, dash,
  dashPhase }` with SwiftUI's defaults (width 1, `.butt`, `.miter`, limit 10,
  no dash — ST4, ST5, ST6) and `public enum LineCap { butt, round, square }`,
  `public enum LineJoin { miter, round, bevel }` (SwiftUI's `CGLineCap`/
  `CGLineJoin` case names). `Shape.stroke(_:style:)`, `.strokeBorder(_:style:)`.
- **The stroker works on the flattened polyline in device space**: offset
  segments, caps at open ends (butt at the endpoint, round/square w/2 past it,
  ST1–ST3), joins (miter falling back to bevel past the limit, ST6; round;
  bevel), a closed subpath joined at its start and an open one capped there
  (ST8), dashes walked by arc length from the phase **before** stroking
  (ST7's three rows exactly); the result is filled nonzero. A width ≤ 0
  strokes nothing (ST10).
- **Routing keeps every existing stroke on its primitive**: a `ShapeView`
  stroke layer over a built-in shape whose style is SwiftUI's default apart
  from `lineWidth` (any cap — a closed outline has no ends — `.miter` join,
  limit ≥ the corner's ratio, no dash) still draws the SDF band `TE-AE`
  measured, unchanged (3.8's second arm). Anything else — a round or bevel
  join on a corner, a dash, any `Path` — goes through the stroker and draws an
  image. `strokeBorder(style:)` strokes the shape inset by `lineWidth / 2`,
  `TE-AE`'s rule.

**Reasoning.** The probe's numbers are exact (bounding boxes and runs), so
every rule above has a discriminating arm; the SDF band already equals a
miter-joined stroke of a rounded rectangle, which is why the default stays
there.

**Cost if wrong.** A stroke routed to the image path costs a raster; a
rounding difference at a join is a pixel at an antialiased edge, judged by
the tests' ±1 tolerance.

---

## GX-F — Transforms on the GPU: a 64-byte side table indexed from words the primitives already have

**Ruling.** Rotated, non-uniformly scaled, flipped or sheared rects,
ellipses, glyphs, images and surfaces are drawn by the **existing three
pipelines with an affine per instance**, read from a new per-scene table:

```c
typedef struct {            // 64 bytes: four float4 lanes
    float a, b, c, d;       // x' = a x + c y + tx,  y' = b x + d y + ty (device px)
    float tx, ty;
    float pixelScale;       // sqrt|ad − bc|: screen px per local px, for AA
    MUIUInt _reserved;
    MUIBounds  outerMask;   // the clip at the effect's entry, SCREEN space
    MUICorners outerMaskRadii;
} MUITransform;
```

- **No stride moves** (`MUIRect` 128 in the replay packing, `MUIImage` 64,
  `MUIGlyph` unchanged): the index rides in words that already exist —
  `MUIRect.shape`'s bits 8…31 (bits 0…7 stay the shape kind), `MUIImage.filter`'s
  bits 8…31 (bits 0…7 stay the filter; surfaces share the record), and
  `MUIGlyph._reserved`, **renamed `transform`** (the precedent is `TE-AQ`
  item 7's `_reserved` → `shape`). **Index 0 means identity and is never
  stored**, so every scene written before this change — every word was 0 or
  a shape/filter below 256 — keeps its bytes, `Expected.swift` is unedited,
  and the fourteen images read 0 px.
- `Scene.transforms: [MUITransform]`, `Scene.insert(_:layer:transform:)`
  (default `nil`) assigning the index, reusing the previous entry when equal
  (one effect's primitives share one record). `finalize()` never reorders the
  table; `clear()` empties it; it never breaks a run.
- **Shaders** (`shaders.metal` and `replay.hlsl`, identically): an instance
  with index 0 runs **today's code unchanged** (a branch, not an identity
  multiply). An instance with index `i > 0`: the vertex stage expands the
  local quad by `1 / pixelScale` local px on every side (an antialiasing
  fringe), maps its corners through the affine for the clip position and
  passes the **local** position as the existing `pixelPosition` varying —
  so the rect/ellipse SDF, the primitive's own `contentMask` (now **local**:
  clips pushed inside the effect) and every corner pick run on unchanged
  code; the fragment multiplies the SDF by `pixelScale` before the half-pixel
  threshold and multiplies coverage by the outer mask evaluated at the
  **screen** position. Glyphs sample the atlas bilinearly at the
  interpolated atlas position **clamped to their slot** (no bleed), images
  keep their filter; both gain an edge coverage
  `saturate(0.5 − rect_sdf(local) × pixelScale)` so their rotated edges are
  antialiased like a rect's. Basic operations only (no transcendental), the
  same discipline as `TE-AQ` item 6.
- **Replay**: `ReplayFixture` version **3** carries the transform table after
  the textures; the stride check gains the transform stride; `Experiments/SDLGPU`
  records a **frame 7** (spec §5.3) and both CI jobs' `--expect 7` become
  `--expect 8`. Frame 7's reference is the Metal renderer; SDL's Metal backend
  must read 0 px, llvmpipe and D3D12 within `ParityTolerance` (sprites ≤ 8
  inside glyph and image quads, ≤ 1 elsewhere).

**Alternatives rejected.**

- *Grow the strides* (a transform per primitive): re-records
  `Expected.swift`, which this branch must not edit, changes the replay
  packing, and pays 24+ bytes on every primitive of every frame for a rare
  effect.
- *Expand on the CPU into paths*: exact for rects, impossible for glyphs and
  images (their pixels are not vectors), and rasterizes every rotated rect.
- *Render the subtree to an offscreen texture and draw it rotated*: needs
  render-to-texture passes in both renderers and the SDL bridge, and resamples
  vectors SwiftUI keeps crisp.

**Cost if wrong.** Shader complexity on the transformed branch only; a
parity miss there is caught by frame 7 on push, with a named positive
control (spec P1). `pixelScale` is isotropic, so a strongly non-uniform
scale antialiases one axis slightly wider than a pixel — the tests pin
uniform and 2:1 cases.

---

## GX-G — One paint-scope stack: `TransitionEffect` generalizes into `RenderEffect`

**Ruling.** `Frame.transitionScopes` becomes `Frame.paintScopes`: transition
groups (`AN-AE`), render-effect scopes (`GX-H`) and shadow scopes (`GX-J`) in
one stack, innermost last, each processing every primitive emitted inside it
in order (innermost first) before it reaches the scene. **An empty stack is
today's fast path, unchanged**: the four emitters insert directly, and a tree
with no transition, effect or shadow pushes nothing (pinned by a work
counter, 2.21).

- `TransitionEffect` (alpha, uniform scale, translation) becomes
  `RenderEffect` (alpha, `Affine2D`), and `AnyTransition`'s atoms produce one
  exactly as before (same arithmetic: a `.scale` transition's map is a
  uniform scale about its anchor) — transitions' captured and emitted bytes
  do not move.
- `CapturedPrimitive` becomes a struct carrying its kind (rect, glyph, image,
  surface — and, lane 3, path and shadow), its layer, `innerMask`, and an
  optional **`PrimitiveTransform`** (an affine plus an outer mask) **by
  value**, so ghosts and drag previews replay transformed content in a later
  frame without reading a stale scene index.
- **Applying an effect**: the effect's affine `M` composes onto the
  primitive's transform `T` (`M ∘ T`). When the result is a translation plus
  a **uniform positive** scale and the primitive had no transform, it is
  **flattened on the CPU** as a transition is today (bounds, radii, border
  widths, an inner mask mapped; the mask in effect at the scope's entry kept);
  otherwise it becomes a transform record. So `offset` and `scaleEffect(2)`
  never touch the GPU transform branch; rotation, flips and non-uniform
  scales do.
- **The clip splits at an effect's entry**: entering a non-flattening effect
  scope saves the active clip as the scope's **outer mask** (screen space)
  and resets the active clip, so clips pushed inside intersect among
  themselves in **local** space (T7: an inner clip rotates with the content;
  T7b: an outer one stays). A clip pushed **between two nested non-flattening
  effects** cannot be expressed in either space; it becomes **its screen
  bounding box** intersected with the outer mask (divergence 109, kept,
  owner none — a second mask per primitive is the only exact answer).
- **A `Deferred` presentation resets the effect stack** as it already resets
  clip and scroll offset (`AP-I`): a sheet declared inside a rotated view is
  not rotated, and its hitboxes are untransformed (2.20).
- The same composed affine (in points) is pushed in **prepaint** around the
  element's registration, for hitboxes and accessibility (`GX-I`).

**Reasoning.** The request asks to "reuse/generalize that machinery rather
than adding a second"; ghosts, drag previews and effects all need the same
"primitive through a stack of maps" walk, and carrying the transform by value
is what lets a ghost outlive its frame's table.

**Cost if wrong.** `CapturedPrimitive` grows (an optional 64-byte record);
only frames with an open scope pay it. A mutation that flattens a rotation
reddens 2.4/2.1.

---

## GX-H — The transform API, both vocabularies, and how it animates

**Ruling.**

- **Spelling**: `rotationEffect(_ angle: Angle, anchor: UnitPoint = .center)`;
  `scaleEffect(_ s: Double, anchor: UnitPoint = .center)`,
  `scaleEffect(_ s: SizeD, anchor:)`, `scaleEffect(x: Double = 1, y: Double = 1, anchor:)`
  (T4b: the size form equals `x:y:`); `offset(x: Pixels = 0, y: Pixels = 0)`,
  `offset(_ offset: Size<Pixels>)` (T6c). Positive degrees rotate visually
  clockwise about the anchor in the element's own bounds (T1, T2, T2b); a
  negative factor flips (T5); a zero factor draws nothing (T5b).
- **Proposal vocabulary**: three new `LayoutModifier` cases —
  `.rotationEffect(Angle, anchor:)`, `.scaleEffect(x:y:anchor:)`,
  `.offset(x:y:)` — each **one layer, one node, one identity level**
  (`MC-A`/`MC-C`, unchanged rules), layout-transparent (the node answers its
  child's size, T1/T3/T6 sizes), composing in written order (T10, T11, T14).
  **Public break**: an exhaustive `switch` over `LayoutModifier` outside the
  package adds arms (migration note, as `MV-C` item 3 for `PrimitiveKind`).
- **Legacy vocabulary**: the same three on `StyledElement` **return `Self`**
  (no id moves, `DN-P`'s precedent) and append to a new ordered
  `Decoration.renderEffects: [RenderEffectSpec]` — **written order is kept
  among effects** (and shadows, `GX-J`), and the list always wraps the whole
  element (background, content, border): a background written *after*
  an effect is still transformed, where SwiftUI's is not (T8) — divergence
  108, kept, owner none (the legacy `Decoration` is order-insensitive by
  design, divergence 47's reason).
- **Animation** (N1, N2, N2b, N3, N9): the angle and its anchor, both
  factors and their anchor, and both offset components animate, at the
  **layout phase** exactly as `.opacity` does (`AN-AB`): the layer rewrites
  its own case from the window's `AnimationStore`, prepaint and paint read
  it. Legacy effects animate on an `AnimationStore` track keyed
  `$anim-effects` (a store key, **not** a `StateTable` slot — the reserved
  names stay seven, `theSevenRetentionSlotsAreMutuallyDistinct` untouched).
  An effect appearing or vanishing snaps its structure (`LR-AS`).
- `rotationEffect` reads `PathMath.sinCos` (`GX-B`), so the same angle gives
  the same affine on every platform.

**Cost if wrong.** The public break above; a legacy order mismatch is the
named divergence.

---

## GX-I — Hit testing and accessibility follow the transform; nothing else moves

**Ruling.**

- **Hit testing follows every effect** (H1–H4, H6, H7): a `Hitbox`
  registered inside an effect stores its local rect (clipped by local clips),
  the **inverse** composed affine and the scope's outer clip;
  `Hitbox.contains(p)` is `outerClip.contains(p) && localRect.contains(inv(p))`
  (then the `contentShape` geometry at `inv(p)`, `IX-L`). The one ranking
  (`topmostHitbox(in:at:where:)`) is unchanged; hover, click, gesture arenas,
  wheel routing, drag sources and drop destinations all read `contains` and
  therefore follow. **A hitbox registered outside every effect takes today's
  code path** (no transform stored).
- **A shadow never hits** (H5): it registers nothing.
- **Accessibility frames are the transformed frame's axis-aligned bounding
  box** (X1, X2, X4, X5 — exact). At a non-right-angle rotation SwiftUI
  reports a smaller square (X3: 35.36 where the bounding box is 40.31,
  unexplained) — divergence 107, kept, owner none.
- A focused `TextField`'s caret rectangle handed to the platform
  (`setTextInputArea`) is the bounding box of the transformed caret.
- **Unprobed, MetalUI's own choice**: a wheel over a rotated scroller scrolls
  its own axis by the window-space delta (no rotation of the delta).

**Must not move** (and how it is checked): every id path (`MC-A`/`MC-C`/
`MC-P`), `theSevenRetentionSlotsAreMutuallyDistinct`, the ranking, focus,
`List` windowing and `TB-AH`, `Deferred`, text input — a tree without an
effect registers byte-identical hitboxes and accessibility records (the full
suite unchanged), and the fourteen images read 0 px against `dc96395`.
`Handlers` gains **no** member (`MemoryLayout<Handlers>.size` unmoved).

---

## GX-J — Shadows: per leaf, silhouette on the CPU, Gaussian with sigma = radius

**Ruling.**

- **Spelling**: `shadow(color: ColorToken = .shadow, radius: Pixels, x:
  Pixels = 0, y: Pixels = 0)` on `ProposalElementGroup` (a `LayoutModifier`
  case `.shadow(…)`, one layer) and on `StyledElement` (an entry in
  `Decoration.renderEffects`, returns `Self`). A **new `ColorToken.shadow`**,
  black at 0.33 alpha in both themes (SH2: SwiftUI's default reads 171 over
  white). **Public break**: `ColorToken` is `CaseIterable` and switched over
  exhaustively by themes and tests; an outside exhaustive `switch` adds an arm
  (migration note).
- **Per leaf, not composited** (SH5: in an overlapping stack the top child's
  shadow falls on the child below it; `compositingGroup()` composites, SH5c —
  not offered, spec §9). Every primitive emitted inside a shadow scope is a
  leaf and gets its own shadow drawn **immediately below it**, with one
  grouping: **the glyphs of one text draw are one leaf** (a `Text` is one
  SwiftUI leaf, SH4/SH5e) — `Frame` brackets each text draw
  (`beginLeafGroup`/`endLeafGroup`) and the scope holds the group's glyphs
  until its end, then emits one shadow and the glyphs. A nested shadow's
  image is itself a leaf (SH11: the second shadow shadows the first).
  **A primitive that SwiftUI draws as two leaves is one here** — a `Box`'s
  background and border are one `MUIRect`, so the border's shadow never
  falls on the element's own background — divergence 104, kept, owner none.
- **The silhouette is computed on the CPU** from the leaf's captured
  primitives in device space (after the composed transform): rects, ellipses
  and paths through `MetalUIPath`'s rasterizer, glyphs from the atlas bitmap
  and images from their texture's alpha (bilinear under a transform), each
  times its colour's alpha (the shadow follows the content's alpha, SH6) and
  its own mask; a **`MetalView` surface's silhouette is its quad** (its pixels
  live on the GPU) — divergence 104 again. Overlapping coverage unions as
  alpha compositing does (`a + b − ab`).
- **The blur is a triple box blur approximating a Gaussian with sigma equal
  to the radius** (SH3/SH3b fitted: sigma/radius 1.02 and 1.00), integer
  arithmetic on the alpha channel, box widths from sigma by the standard
  formula (`sqrt` only) — deterministic everywhere, O(1) per pixel whatever
  the radius. Its profile is pinned against SwiftUI's measured rows within ±8
  grey levels (1.28, 3.17); the three-box shape and SwiftUI's own truncation
  at about 2.4 sigma are the difference — divergence 105, kept, owner none.
- **Offsets and radius follow the composed transform**: the offset is mapped
  by the composed linear part (T10: rotated; T14: scaled) and sigma by
  `sqrt|det|` (isotropic — a non-uniform scale blurs both axes alike,
  divergence 105 again).
- The result is one `ImageTexture` (the shadow colour times the blurred
  alpha), pixel-aligned in device space, inserted just before the leaf;
  rasterized only inside the clip in effect (SH7: a clip outside cuts it;
  SH7b: a clip inside shapes the silhouette); cached by value (`GX-K`).
- A shadow **changes no layout** (SH8), **registers no hitbox** (H5) and
  **publishes nothing** (X6).
- **Animation** (N4–N6): colour, radius and both offsets animate, at the
  **paint** phase on the `AnimationStore` (`AN-AB`'s colour precedent); the
  legacy one on the `$anim-effects` track.

**Alternatives rejected.** *gpui's analytic Gaussian-blurred rounded rect in
the shader*: exact and cheap for boxes, but SwiftUI shadows text, strokes,
paths and images (SH4, SH9, SH12), and `erf`/`exp` in two shader languages
at the ≤ 1 parity tolerance is the precision risk `TE-AQ` item 6 avoided. It
remains a possible optimization for a rect leaf (owner none).

**Cost if wrong.** One raster and one image per shadowed leaf, and an image
run per shadow (a shadowed list of N rows draws about 2N runs). Static
shadows are cached; an animated radius re-blurs every frame.

---

## GX-K — The raster cache

**Ruling.** A window-owned `RasterCache` maps a **value key** (the path or
leaf primitives, the style, the colour, the composed affine, the device
scale, the clip rectangle) to the `ImageTexture` it produced. A hit returns
the same identity (so `TE-AF`'s per-renderer texture caches never re-upload
it); entries a frame did not touch are dropped at `endFrame` (the
`AnimationStore` precedent), so an animated path's old rasters do not
accumulate. Coverage is cached separately from colour, so a colour animation
re-tints without re-rasterizing. Work counters
(`lastRasterizedPixels`, `lastBlurredPixels`) are what performance tests read.

**Cost if wrong.** Memory held for one frame of rasters; a key that misses a
field draws a stale raster — every key field has a mutation in spec lane 3.

---

## GX-L — Text and images under an effect are resampled, not re-rasterized

**Ruling.** A glyph under a scale or rotation effect samples its device-scale
atlas bitmap through the GPU transform (bilinear, slot-clamped, `GX-F`); an
image samples its texture under its own filter. **SwiftUI re-rasterizes text
at the effective scale** (T15b: 326 partial pixels against 298 for real 40 pt
text and 1237 for a bilinear upscale), so MetalUI's text is soft above 1× —
divergence 106, kept, owner none. Paths and shadows are re-rasterized
(`GX-B`, `GX-J`), matching SwiftUI.

**Reasoning.** The glyph atlas is grow-only (`evictUnusedSince` has no caller,
CLAUDE.md "Text"); re-rasterizing at every intermediate scale of an animated
`scaleEffect` or `.scale` transition would grow it without bound. A quantized
scale ladder with an evicting atlas is the remedy, and is its own design.

---

## GX-M — Divergences and documents

**Ruling.** Added (next label **104** → **110**):

| # | subject | ruling |
|---|---|---|
| 104 | a shadow's leaves | `GX-J` |
| 105 | a shadow's blur profile | `GX-J` |
| 106 | text and images under a scale or rotation effect | `GX-L` |
| 107 | an accessibility frame under a non-right-angle rotation | `GX-I` |
| 108 | legacy effects against a legacy background or border | `GX-H` |
| 109 | a clip between two nested rotations | `GX-G` |

Amended: **90** (a `Path`'s `.continuous` rounded rect is drawn circular,
`GX-C`), **91** (`clipShape` of a path traps too, `GX-D`), **97** (a shape's
stroke width and `StrokeStyle` snap where SwiftUI animates them, N8), and
**41** (a handler outside a rect-changing layer over an effect hits its
axis-aligned frame, `GX-P` item 2 — added by the critic round). The
shapes spec's §9 table loses its `Path`/`path(in:)` and `StrokeStyle` rows
(lifted, pointing here) and `docs/divergences.md`'s absences row drops `Path`
and `StrokeStyle`. `docs/api-overview.md` gains the surface; every new public
declaration a doc comment and an inventory map row (`CX-A`, `CX-K`).

---

## GX-N — Pixels, determinism and what must not move

**Ruling.** No production tree (`demoContent()`, `nativeLayoutPreviewContent()`)
uses a new API, so **the fourteen offscreen images read 0 px against
`dc96395`**, `DemoFrameDeterminismTests`' `Expected.swift` is **unedited**
(`GX-F`'s identity index keeps every primitive byte), and the CPU rasterizer's
own determinism is pinned separately (spec 1.26). `MetalUILayout` still imports
only `MetalUICore`, `MetalUIScene` only `MetalUIShaderTypes` (`MUITransform` is
in the header), and the new `MetalUIPath` imports nothing.
`theLegacyEngineSymbolsAreAbsentFromTheTestProcess` stays green.
`Decoration` grows by one array (8 bytes); the smallest thread building every
production tree (`everyProductionTreeBuildsOnAOneMegabyteThread`) is
re-measured by lane 2 and must stay under 1 MB. The new looks-demo section is
its own function (Windows' 1 MB stack). `Backends/SDL` and a `swift:6.4-noble`
container build; the real-window capture follows the lock probe.

---

## GX-O — Lanes

**Ruling.** Three lanes, run strictly in order **1, 2, 3** (2 needs 1's GPU
transform; 3 needs 1's rasterizer and 2's composed transforms), all Opus.
Lane 1: the renderer transform and `MetalUIPath` (no `MetalUI` public API).
Lane 2: render effects in `MetalUI` (effects, scope stack, hit testing,
accessibility, animation). Lane 3: `Path`, `Shape.path(in:)`, fill and stroke
styles, shadows, the looks demo, human checks and the documents. Shared
files (`Frame.swift`, `Transition.swift`, `NativeModifiedContent.swift`,
`ModifiedContent.swift`, `ProposalAnimation.swift`, `Box.swift`) are safe only
because the lanes run one at a time; spec §8 lists each lane's files.

---

## GX-P — A handler written after an effect follows it; point consumers read local points; the anchor is in scrolled space (critic round)

**Finding.** `GX-I` transforms only the hitboxes and accessibility records
registered **inside** an effect scope. On the proposal path every
handler-registering wrapper (`OnTapModifier`, `GestureModifier`,
`DraggableModifier`, `DropDestinationModifier`, `AccessibilityModifier`)
calls `registerHandlers` over its **own** bounds before prepainting its
content, so `Rectangle().frame(width: 160, height: 20).rotationEffect(.degrees(90)).onTapGesture { }`
— the order probe arm **H1b** measured — would register an axis-aligned
160×20 hitbox outside the rotation scope and hit where nothing is drawn,
the opposite of SwiftUI's `(100,40) 1 (40,100) 0`. The spec's test 2.10 cited
H1b but its mechanism could not produce it. Separately, every consumer that
turns the event point into a local one — `Gesture.swift`'s `leaf.local(point)`
(window point minus the declarer's unclipped origin), `Slider`'s
`ValueTrackTarget.minX`, a `TextField`/`TextEditor` press, a drop
destination's action location (`DN-H` item 2) — reads the **window** point,
so under a rotation or scale a slider would set the wrong value and a
`DragGesture` would report rotated translations. And `GX-H`'s anchor
(`bounds.origin + anchor × size`) omitted `Frame.activeOffset`, the scroll
translation `PaintPass.fill` and `insertHitbox` already add, so an effect
inside a scrolled `ScrollView` would turn about a point the content has
scrolled away from.

**Ruling.**

1. **A registration whose rect IS the effect's rect shares the effect.** A
   hitbox or accessibility record registered by a **proper ancestor** of an
   effect layer, at a rect equal to the effect layer's own rect (no layer
   between them changed the rect — only other effects, handlers, gestures,
   draggables, drop destinations, accessibility or environment layers), is
   registered through the effect's composed affine exactly as one inside it
   is (`GX-I`'s inverse, outer clip and bounding box). The mechanism —
   retroactive patching of the matching registrations when the effect's
   prepaint scope opens, or a look-ahead in the unified layer recursion — is
   lane 2's choice, recorded as a ruling. So `.rotationEffect(…).onTapGesture`
   and `.onTapGesture.rotationEffect(…)` hit the same diamond (H1, H1b).
2. **A rect-changing layer stops it.** `.rotationEffect(…).padding(10).onTapGesture`
   registers the padded, axis-aligned frame: MetalUI's hit region is the
   registering element's frame (divergence 41), and that frame is not
   transformed. SwiftUI hits only the rotated content (its hit region is the
   content's shape) — **divergence 41, amended** (no new label: it is the
   frame-versus-content rule, now also under an effect), remedy: write the
   handler inside the padding or before the effect. A legacy `StyledElement`
   needs no rule: its own `Decoration.renderEffects` wrap its own handlers
   (`GX-H`).
3. **Point consumers read the declarer's local point.** `Window` maps the
   event point through the hit hitbox's stored inverse (into the
   pre-effect, window-space frame the declarer was laid out in) **before**
   handing it to a gesture leaf, a value track, a text press or a drop
   destination; their existing `point − origin` conversions are unchanged.
   A `DragGesture`'s `location`/`startLocation`/`translation` are therefore in
   the declarer's untransformed space, and a drag's `translation` under a 90°
   rotation is the window delta rotated back. **No SwiftUI claim**: the probe
   does not record gesture values under an effect; this is MetalUI's own
   reading of a gesture's local space, consistent with hit testing following
   the transform. The drag preview's translation stays window-space (it is
   drawn above everything, untransformed — `DN-J`).
4. **The anchor is in the space primitives are emitted in**:
   `anchorPoint = bounds.origin + activeOffset + anchor × bounds.size`, then
   the device scale for paint; prepaint uses the same expression, so the
   hitbox inverse and the drawn content agree inside a scrolled scroller.
5. **Not offered on a `Component`** (`StyledComponent` or a bare
   `Component`), as `background(_ token:)`/`onClick` are not (CLAUDE.md
   "Component"): declare the effect on the members, or on a proposal or
   legacy element that wraps the body. Owner none; a row in spec §9.

**Tests** (lane 2, spec §8): 2.27–2.31.

**Cost if wrong.** Rule 1's rect-equality test is the whole mechanism; a
wrapper that registers at a rect differing only by rounding would fall back to
the axis-aligned frame — 2.27 pins the common chain on both orders.

---

## GX-Q — `ColorToken.shadow` keeps `Theme`'s public initialiser source-compatible (critic round)

**Finding.** `GX-J` adds a `ColorToken` case, but `Theme` is a public struct
with one stored `Hsla` per token, a public memberwise
`init(background:surface:…:scrim:)` and an exhaustive `subscript(token:)`
(`Theme.swift`, the "adding a case to `ColorToken` is a compile error here"
note). Adding `shadow` as a required stored property and initialiser
parameter would break every outside custom theme — a second, unruled public
break.

**Ruling.** `Theme` gains `public var shadow: Hsla` and its initialiser a
**trailing defaulted** parameter `shadow: Hsla = <black at 0.33>`, so every
existing `Theme(background:…scrim:)` call compiles unchanged; `.light` and
`.dark` pass the same value (SH2). The subscript gains the arm. Pinned by a
plain-import whole-file guard, **G3.3** `aThemeWrittenBeforeTheShadowTokenStillCompiles`
(mutation MG3.3: the default removed). `ColorToken`'s own exhaustive-`switch`
break stays the one migration note `GX-J` names. `swift package clean`
before lane 3 re-takes counts (`Theme` is a public type crossing into
`MetalUIDemoContent`).

---

## GX-R — Critic round: instruments replaced, cross-references fixed, what was rejected

**Ruling.**

1. **Probe re-run.** The whole probe was re-run compiled on 2026-10-02 with
   the screen unlocked (lock probe: no `CGSSessionScreenIsLocked` line,
   `displayAsleep main: 0`): **120 lines, byte-identical to its header**,
   exit 0 — every arm the rulings cite, not only two.
2. **Two mutations could not redden; replaced.**
   - *M2w* ("`RenderEffect` maps a corner radius by `sqrt|det|` for a
     flattened map — a 1-ulp drift"): for a uniform scale `s`,
     `sqrt(fl(s²)) == |s|` exactly in IEEE round-to-nearest, so the mutant
     emits the same bytes and 2.26 stays green — a broken instrument.
     **Replaced** by *M2w′*: the transition atom's affine composes its
     translation before its scale (`S·T` for `T·S`), which moves every
     `.scale` transition primitive whose anchor is not the origin.
   - *M1aa* ("one `sinCos` coefficient's last digit changed"): a change of
     about 1e-17 relative cannot move an 8-bit coverage byte, so 1.26's
     hash stays green. **Replaced** by *M1aa′*: the flattening tolerance
     0.1 → 0.2 device px (segment counts change, so curve coverage bytes do).
     `sinCos`'s own determinism is pinned by 1.27, now **exact bit
     patterns** (`Double.bitPattern` literals recorded on macOS, compared
     on Linux and Windows CI), not "within 2 ulp" — a tolerance cannot see
     the platform drift the function exists to prevent. `PathMath` uses no
     `addingProduct`/`fma`, so no platform's fused multiply-add enters.
3. **Cross-references corrected**: `GX-C`'s arc pin is 1.19 (not 1.18);
   `GX-F`'s frame 7 is spec §5.3 (not §6.3); `GX-G`'s `Deferred` pin is 2.20
   (not 2.18); `GX-J`'s blur pins are 1.28 and 3.17 (not 1.25).
4. **Lane 1 notes added**: every new C enum (the three
   `MUI…BufferTransforms` indices) is converted explicitly where Swift reads
   it (`UInt32(X.rawValue)`/`Int(X.rawValue)`, the Windows `Int32` hazard),
   and `SDLBridge.c`'s shader create infos raise `num_storage_buffers` for
   each stage that reads the table.
5. **Rejected, with reasons.**
   - *Split lane 1* (the GPU transform from `MetalUIPath`): the two are
     disjoint in files, but frame 7 needs both (a CPU raster drawn through
     the parity-checked image pipeline is its evidence), and agents run one
     at a time here, so a split buys no parallelism and costs one more
     agent loading the same rules. Kept.
   - *An `Hsla` overload for `.shadow(color:)`*: MetalUI colours are theme
     tokens everywhere (`fill`, `foregroundStyle`, `background`); a shadow is
     not the place to break that convention. Kept token-only.
   - *A translation-free raster cache key*: a shadowed or path view inside a
     scrolling `ScrollView` re-rasterizes while it scrolls (the key holds the
     composed affine and the clip). Correct, only slower; recorded as `GX-K`'s
     cost, owner none.
   - *Gesture values under an effect probed*: the click harness sends single
     clicks; a recorded `DragGesture` value needs a drag harness the probe
     does not have. `GX-P` item 3 is stated as MetalUI's own reading instead.

---

## GX-S — Lane 1's readings: instruments re-derived, the stroker's space, frame 7's rasters, where an index is checked

**Ruling.** Lane 1 (the renderer transform and `MetalUIPath`) built `GX-B`
and `GX-F` as written, with these readings, each measured in the lane:

1. **Test 1.4's arm is a uniform scale of 2, not `scale(2, 0.5)`.** The
   spec's `scale(2, 0.5)` has `|ad − bc| = 1`, so `pixelScale` is 1 and its
   mutation M1d ("`pixelScale` ignored") cannot change a byte — a broken
   instrument. Under `scale(2, 2)` an edge a quarter pixel from a pixel
   centre leaves exactly one partial row and column (M1d makes it two). **The
   lane's first arm put the edge through a pixel centre, and M1d stayed
   green** (both bands then end exactly on the neighbours' centres) — found by
   the mutation run, the arm moved to 20.25. A 2:1 arm (`scale(2, 1)`,
   `pixelScale` √2) only bounds the isotropic band (≤ 4 partial pixels across
   a row), which is `GX-F`'s stated cost.
2. **"Ink" in the stroke tests is coverage ≥ 64 (a quarter pixel).**
   SwiftUI's bitmaps come from CoreGraphics' sample-based antialiasing,
   which leaves no ink for a sliver under about a quarter pixel (a miter's
   last rows, a round cap's tangent). At ≥ 128 the sharp miter of ST6 —
   split down the middle between two pixel columns — reads −2 against
   SwiftUI's −4; at > 0 it reads −7. At ≥ 64 every arm of ST1–ST8 is within
   the spec's ±1 (measured: miter tip 8 vs 7, limit-10 −4, limit-4 9/10).
3. **ST7's third row differs at the 2-unit dashes' ends.** SwiftUI reads
   `[15…17]` for the dash [15, 17) and `[0…9]` for [0, 10): CoreGraphics
   inks a sliver past the short dashes only. MetalUI's exact-area answer is
   `[15…16]`. Test 1.23 pins the first two rows exactly, and in the third
   every start and every 10-unit end exactly, the four 2-unit ends ±1.
4. **A stroke is stroked in the path's own space, then mapped**
   (`PathRaster.stroke`): flattening and the stroker's round pieces use the
   device tolerance divided by the transform's `sqrt|det|`, the outline is
   mapped by the affine and filled nonzero in device pixels. For a uniform
   scale this is `GX-E`'s "device space"; for a non-uniform one it widens a
   stroke as SwiftUI's does (a `scaleEffect(x: 2)` doubles a vertical line's
   width), which stroking an already-mapped polyline would not.
5. **Frame 7 carries the GPU transform on every pipeline; MetalUIPath's
   rasters join it in lane 3.** `MetalUIPath`'s API is `package` (spec
   §5.4), and `Experiments/SDLGPU` is a separate SwiftPM package, which
   `package` access cannot reach (`GX-R` item 5's "frame 7 needs both" did
   not see this). Lane 3 adds the nonzero and even-odd path rasters and the
   blurred shadow to frame 7 through MetalUI's public `Path` and `.shadow`
   (`renderFrame` of a small tree) — the production path, better evidence
   than calling the rasterizer directly. Owner: lane 3. CI's `--expect 8`
   does not move: frame 7 exists now. Measured on this branch: `Replay
   --portable --record` passes all 8 frames, frame 7 at 0 differing pixels
   on SDL's Metal backend (6 rects, 28 glyphs, 2 images, 9 transforms).
   **Positive controls** (recorded, not committed, each restored with
   `SOURCE.sha256` matching): the HLSL vertex stage ignoring the index fails
   frame 7 with 40 402 differing pixels (max Δ 220); the HLSL outer mask
   dropped (all three kinds) fails it with 1 823 (max Δ 220, all outside the
   sprites — the cut lands on the masked rect).
6. **Index 0 is today's arithmetic by construction, and measured.** The
   fragment's transformed rect path shares `rect_shade(r, p, s)` with the
   untransformed one, called with the literal `1.0`, which the compiler
   folds (`x × 1.0 == x`); glyph and image fragments branch on the index
   before any new arithmetic. `anUntransformedSceneRendersBitIdenticallyToBefore`
   (1.2) hashes a fixed untransformed scene to `0xc1c0b5e350b217a8`,
   recorded on `dc96395`'s shaders in the lane's red commit, and is green
   on the transformed ones.
7. **A record's transform index is checked in the SDL bridge, not the
   fixture.** `SDLBridge.c`'s `transforms_valid` refuses a run whose record
   names an entry past the table (beside `images_valid`), in both
   `replay_render` and `mui_renderer_finish`. `ReplayFixture.validate()`
   checks only that the table is whole records: the format tests build
   fixtures from distinct-valued byte ramps whose `shape` words are
   arbitrary, and a fixture is a format, not a draw.
8. **Only consecutive equal records share a table entry** (byte-equal,
   `_reserved` zeroed): one effect's primitives name one record; a later
   return to an earlier transform is a new entry. Test 1.10 reads it so
   (the glyph and the image under U, not T).
9. **`PathMath.sinCos` is odd by construction**: it works on `|x|` and
   restores the sine's sign, so `sin(−0) = −0` and every symmetry in 1.27
   is exact (the reduction alone gave `sin(−0) = +0`).
10. **Test 1.6's atlas is a coverage-0 slot hard against a neighbour whose
    touching column is 255, drawn ×4 and turned a quarter**: any lit pixel
    is a bleed. The spec's two 255 slots cannot show one (a bleed of 255
    into 255 is invisible).

11. **The mutation table** (whole unfiltered suite each, `git status`
    clean after every restore; M1a–M1c on `3169cb3`, the rest on `2026d98`):
    every spec mutation reddens its named test. M1a → 1.1, 1.3, 1.4, 1.5;
    M1b → 1.2 alone (the pin is the only test that sees index 0's fringe);
    M1c → 1.3, 1.4; M1d → 1.4 (after item 1's fix; green before it); M1e,
    M1f → 1.5; M1g → 1.6; M1h → 1.7; M1i → 1.7, 1.8; M1j → 1.9; M1k → 1.10;
    M1l → 1.11; M1m → 1.12 alone; M1n → twelve `MetalUIPathTests`; M1o →
    1.14, 1.22, 1.26; M1p → 1.15, 1.26; M1q → eight; M1r → 1.17, 1.18, 1.19,
    1.26; M1s → 1.18, 1.26; M1t → 1.19, 1.26; M1u → 1.20, 1.26; M1v → 1.21,
    1.22, 1.24, 1.26; M1w → 1.22, 1.26; M1x → 1.23, 1.26; M1y → 1.24; M1z →
    1.25; M1aa′ → 1.18, 1.26; M1ab → 1.19, 1.26, 1.27; M1ac → 1.26, 1.28;
    M1ad → 1.29; M1ae → 1.30; in `Backends/SDL`, M1af → S1.1 and M1ag (the
    window renderer binding the dummy record) → S1.2. The bit-identity pins
    1.26 and 1.27 pass unchanged in a `swift:6.4-noble` aarch64 container.

**Cost if wrong.** Items 1–3 are instruments: each names the arm it
replaced and why the old one could not discriminate. Item 5 leaves frame 7
without CPU rasters until lane 3; the rasters reach the screen through the
image pipeline frame 6 already holds to parity.

