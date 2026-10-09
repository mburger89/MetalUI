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

Prefix **`GX-`**, lettered. **Next unused: `GX-Y`.** (This line moves in the
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
   arbitrary, and a fixture is a format, not a draw. **Pinned through `replay_render`
   only** (review round): `Backends/SDL`'s S1.3
   `aRecordNamingAMissingTransformIsRefused` renders each kind's runs of
   `transformedScene` with exactly as many records as its index names and
   expects the refusal with one fewer; removing the refusal reddens S1.3
   alone (6 issues; `Backends/SDL` 24 + 57). `mui_renderer_finish`'s call
   is defensive and unpinned: a `Scene` cannot build such a record, since
   `insert` always writes the index it assigns (item 13).
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
    **The review round's mutations** (on `8b6a2a2`, whole unfiltered suite
    each, 2158 tests, `git status` clean after every restore): the outer
    mask's factor deleted from `glyph_fragment`'s transformed branch alone →
    1.5b `aTransformedGlyphAndImageAreCutByTheScreenOuterMask` alone (its
    glyph arm), and from `image_fragment`'s alone → 1.5b alone (its image
    arm) — both green before 1.5b existed (2154 passed), so `GX-F`'s
    "every transformed instance multiplies by the outer mask" was pinned only
    for rects; `mask_coverage_scaled`'s `* s` dropped → 1.5c
    `aScaledContentMaskAntialiasesInScreenPixels` alone (1.5's pure rotation
    has `pixelScale` 1 and could not see it); `quad_edge` dropped from the
    transformed glyph → 1.5b alone (3 issues: both edge columns and the
    columns past them — 1.6's slot has coverage 0, so it could not see the
    glyph's own edge); `insert`'s `nil` path keeping a stale rect index →
    1.31 alone; the per-frame zero record restored → 1.32 alone.
12. **The zero transform record is allocated once per `Renderer`**
    (`zeroTransformBuffer`), not per frame: every scene with no transforms —
    every production frame until an effect draws — binds the same buffer,
    which no index-0 instance reads. Pinned by 1.32
    `aSceneWithoutTransformsReusesOneZeroRecord` (two frames bind the
    identical buffer).
13. **`Scene.insert(_:transform: nil)` writes index 0**, clearing
    `shape`/`filter` bits 8…31 and the glyph's `transform`: a primitive
    captured from one scene (a transition ghost, a drag preview,
    `Frame.swift`'s replay) and re-inserted into another never keeps a
    stale index into a table the new scene does not hold — the Metal
    renderer has no bounds check, only SDL's bridge does (item 7). A replay
    that must stay transformed passes its record again; lane 2's captured
    effects owe that. Pinned by 1.31 `aNilInsertClearsAStaleTransformIndex`.
    No production record carried an index before this, so no pixel moves.

**Cost if wrong.** Items 1–3 are instruments: each names the arm it
replaced and why the old one could not discriminate. Item 5 leaves frame 7
without CPU rasters until lane 3; the rasters reach the screen through the
image pipeline frame 6 already holds to parity.

---

## GX-T — Lane 2's readings: the scope stack, the share mechanism, what the tests compare

**Ruling.** Lane 2 (render effects in `MetalUI`) built `GX-G`, `GX-H`,
`GX-I` and `GX-P` as written, with these readings, each measured in the lane:

1. **One `PaintScope` class, four kinds** (`transition`, `effect`, `capture`,
   `barrier`), replacing `TransitionPaintScope` and `Frame.transitionScopes`
   (now `Frame.paintScopes`). A transition and a drag capture always flatten
   (their maps are uniform scales and translations — a `.scale` transition's
   0 included, which is not a *positive* scale but must keep its bytes); an
   effect flattens only when its device map is a translation plus a uniform
   positive scale. A degenerate composition onto a transformed primitive is
   dropped (draws nothing). `RenderEffect(atoms:…)` computes a transition's map
   in `Float` exactly as plan task 13 did and stores it in `Double` without
   rounding; the flattened map is applied in `Float` — so 2.26's literals,
   recorded on the red commit's untouched arithmetic, hold.
2. **`Deferred`'s reset is a barrier, pushed only while an effect scope is
   open**: an effect outside it is skipped for the portal's primitives, a
   transition or capture outside it still applies (as before this branch). In
   prepaint the effect stack and the share candidates are emptied around the
   portal. `clipBase` drops below the portal's root clip in both phases (the
   same values `activeClip` read before).
3. **The clip split is `Frame.clipBase`**: `activeClip`/`activeClipRadii`
   read only entries at or above it, and an effect's content sees an
   unbounded local clip (±10⁶ points) until it pushes one; `activeOffset`
   ignores it. **Prepaint always splits** (hit testing through an inverse is
   exact for every map); paint splits only for a non-flattening scope.
4. **`GX-P` item 1's mechanism is a share-candidate stack.** The five proposal
   wrappers (`OnTapModifier`, `GestureModifier`, `DraggableModifier` both
   forms, `DropDestinationModifier`, `AccessibilityModifier`) register through
   `Frame.sharingRegistrationsWithEffects`, which notes each hitbox they insert
   (its unclipped rect and the clip in force) and the range of accessibility
   records, and keeps the candidate open for their content. An effect opening
   in prepaint at a rect equal (in scrolled window points) to the innermost
   candidate's patches it — hitbox: the unclipped rect as the local rect, the
   current inverse, its own registration clip as the outer clip (an already
   transformed one keeps its outer clip; a local clip it had is dropped,
   unprobed); record: the transformed rect's bounding box — and continues
   outward, stopping at the first candidate whose rect differs (2.28's
   padding). Stack discipline makes candidates ancestors only.
5. **2.7 and 2.22 compare where the bar's corners land, not records**: an
   inner offset is flattened into the bounds before the outer rotation
   records, so the record holds `R` alone and `R · T` is in the bounds. The
   red run's failure showed it; the corrected arms (`fxLands`) still redden
   under M2g. **Amended by `GX-U` item 4**: these corrected arms landed with the
   implementation (`7568ac2`), not on the red commit; re-run since against
   `267fd8e`'s skeleton sources they redden (2.7 all four arms, 2.22 both).
6. **A focused field's caret area** is mapped in `TextField`/`TextEditor`
   (`Frame.effectBoundingBox`, including the field's own legacy effects, which
   open only inside its `registerAndScope`), not in `Window`.
7. **Legacy effects animate on two store keys**: `$anim-effects` (every
   effect's numbers, `animatedNumbers`) and `$anim-effects.kinds` (the kind
   signature; a change resets the numbers' baseline, so a structure change
   snaps). Called from `animated(_:_:for:pass:)` only when the declared list is
   non-empty, so an effect-free tree touches neither key.
8. **Mechanical test edits**: `DragPreviewTests`' 2.12a matches on
   `primitive.kind` (`CapturedPrimitive` is a struct now); two
   `GPUSurfaceTests` comments name `RenderEffect.apply`.
9. **Divergence 106 is left to lane 3** (`GX-M` allocates it; no lane-2 test
   pins text softness under scale). **107 is pinned by a new 45° arm in
   2.15** (the bounding box, 40.305 square). `docs/divergences.md` reads 73
   live, next label 110 (104–106 allocated to lane 3).
10. **Green on arrival** (filtered red run, 32 tests, 27 red): G2.1 (the
    skeleton's API exists — mutated red below), 2.13 and 2.28 (true of an
    untransformed bar; discriminated by M2l and M2y), 2.25 (a layer is a level
    already; discriminated by M2v), 2.26 (the pin).
11. **Counts**: 2190 tests in 3 suites (2158 + 32), guards 130 (+1);
    census 2031 declarations, 102 families; the smallest thread building
    every production tree **672 KB** (arm64 debug, 16 KB bisection, 656
    failing — 656 KB was recorded at drag and drop's close, not re-taken at
    `dc96395`; **re-taken at `dc96395` by `GX-U` item 5: also 672 KB**), inside the 1 MB budget. 0 px against `dc96395` in all
    fourteen offscreen images, every scene identical. `swift build --build-tests`
    0 warnings; `Backends/SDL` builds and runs 24 + 57; a `swift:6.4-noble`
    aarch64 container builds with 0 `error:`/`warning:` and runs 199 + 22 +
    21 + 31 + 18 + 6.
12. **M2v's first spelling was a broken instrument**: "the layer hands its
    content its parent's level" is a no-op at the root (a root has no parent;
    `id.parent ?? id` is the root's own id), and 2.25 built its chains as the
    root, so the mutant passed all 2190 tests. 2.25 now builds each chain
    inside a `VStack`, where the mutant reddens it alone.
13. **The mutation table** (whole unfiltered suite each, 2190 tests, the
    `FR-J` line present, `git status` clean after every restore; on
    `7568ac2`, M2v's re-run on the 2.25 fix): every spec mutation reddens its
    named test.
    M2a (the rotation layer answers a padded box) → 2.1, 2.2, 2.8, 2.16,
    2.24, 2.30, 2.31; M2b (sign flipped) → 2.2, 2.10, 2.11, 2.13, 2.14,
    2.15, 2.19, 2.24, 2.27, 2.29, 2.30, 2.31; M2c (always a record) → 2.3,
    2.16; M2d (non-uniform flattened) → 2.4, 2.16; M2e (size forms drop
    `height`) → 2.5 alone; M2f (zero scale emitted, both guards removed) →
    2.6 alone; M2g (composition reversed, prepaint and record) → 2.7, 2.19,
    2.22; M2h (no clip split in paint) → 2.8 alone; M2i (the first proposal
    effect pushed around the whole chain) → 2.7, 2.8, 2.9, 2.24; M2j
    (`insertHitbox` drops the transform) → 2.10, 2.11, 2.12, 2.14, 2.20,
    2.29; M2k (hit against the transformed bounding box) → 2.11 alone; M2l
    (outer clip dropped) → 2.13 alone; M2m (untransformed accessibility
    geometry) → 2.15 alone; M2n (rotation anchor snaps) → 2.16 alone; M2o
    (legacy effects snap) → 2.17 alone; M2p (captures drop the transform) →
    2.18, 2.19; M2q (`Deferred` keeps the stack) → 2.20 alone; M2r (an
    identity offset scope for every `StyledElement`) → 2.21 alone; M2s (the
    legacy list sorted) → 2.7, 2.22; M2t (legacy effects wrap the content
    only) → 2.3, 2.6, 2.7, 2.17, 2.18, 2.19, 2.22, 2.23; M2u (middle clip
    dropped) → 2.24 alone; M2v (re-run) → 2.25 alone; M2w′ (the scale atom's
    translation composed before its scale) → 2.26 and plan task 13's
    `aScaleTransitionScalesTheGroupsPrimitivesAboutItsAnchor`; M2x (no
    outward propagation) → 2.27, 2.31; M2y (propagation past an unequal
    rect) → 2.28 alone; M2z (`localPoint` the identity) → 2.29 alone (2.30's
    hitbox arm reads the scrolled centre, which a rotation fixes, so the
    identity passes it); M2aa (anchor without the scroll translation, both
    phases) → 2.30 alone; MG2.1 (`offset(_: Size)` made `internal`) → G2.1
    alone.

**Cost if wrong.** Item 4's rect equality is the whole share mechanism
(`GX-P`'s stated cost); a wrapper registering at a rect that differs by
rounding keeps its axis-aligned frame. Item 3's unbounded clip is a finite
±10⁶ points, beyond any window. Item 1's degenerate drop means a composed
zero scale over rotated content draws nothing, as `GX-H`'s zero scale does.

---

## GX-U — The share stops at any element but a sharing wrapper; a shared record's visible frame (review round)

**Finding.** `GX-T` item 4's share mechanism tested rect equality alone, so a
wrapper whose content is a `ZStack`, an `.overlay` or a `.background`
attachment shared an effect on **one** of their children at the same rect:
`ZStack { square; square.rotationEffect(45°) }.onTapGesture { }` (two
100 × 100 squares) lost the unrotated square's corner (53, 53) — neither
SwiftUI's answer (the union of the children's shapes) nor divergence 41's
(the wrapper's whole axis-aligned frame). `GX-P` item 1 limits the share to a
chain of effect, handler, gesture, draggable, drop, accessibility or
environment layers; the implementation did not check what lay between.
Separately, a shared accessibility record's `visibleFrame` was the old
axis-aligned visible rect cut by the new bounding box — a 90° turn of the
160 × 20 bar published `(90, 90, 20 × 20)` where the other written order (and
the direct path) published `(90, 20, 20 × 160)`; AppKit hit-tests
accessibility by `visibleFrame`. Nothing pinned `visibleFrame` under an
effect (the reviewer's V4 — the direct path's visible frame untransformed —
reddened nothing).

**Ruling.**

1. **A share floor.** `Frame.shareFloor` is the lowest index of
   `shareCandidates` an effect may patch. Every element entry —
   `Element.prepaintGroup` and its copy in `AnyElement`'s group entry — raises
   it to the stack's count for the element's prepaint
   (`Frame.enteringShareBarrier`, recording the floor it entered at as
   `shareFloorAtEntry`). A **sharing wrapper** (the five of `GX-T` item 4)
   lowers it back to its entry floor for its content
   (`passingShareFloorThrough`), so a candidate outside it stays reachable.
   An effect patches only candidates at or above the floor **its own
   element** entered at — the modifier chain carrying the effect layer (whose
   layers enter no element between them) or the legacy element (whose effects
   open before any child enters). An `EnvironmentScope`, a `TransactionScope`
   and the other identity- or layout-transparent groups are not elements and
   raise nothing. So a `ZStack`, an overlay or background attachment, a
   stack, a grid, a leaf — any other element between the wrapper and the
   effect — stops the share; rect equality (`GX-T` item 4) still stops a
   rect-changing layer inside a chain. The `ZStack`/overlay/background cases
   then answer divergence 41's axis-aligned frame, as with no rotation.
   `withoutRenderEffects` (a `Deferred`) resets both floors with the stack.
2. **A shared record's visible frame is computed as the direct path's**
   (`accessibilityGeometry` inside an effect): the bounding box of the
   record's pre-effect visible rect (the wrapper's rect cut by the clip in
   force at its registration, now stored on `ShareCandidate.clip`), cut by
   the effect's outer clip. Both written orders now publish the same frame
   and visible frame.
3. **Tests**: 2.32 `aWrapperOverAZStackOrOverlayDoesNotShareAChildsEffect`
   (new: a `ZStack`, an `.overlay` and a `.background` with a rotated child,
   the unrotated corner (53, 53) hits, control with no rotation); 2.31 asserts
   frame and visible frame on both written orders; 2.15 asserts the X2 visible
   frame on both orders; 2.27 gains a two-wrapper arm
   (`.rotationEffect(90°).accessibilityLabel("x").onTapGesture`). Red first
   (`e3dd354`: 2.32's three arms, 2.31's and 2.15's after-order visible
   frames). Mutations (whole unfiltered suite, 2191 tests, `FR-J` present,
   `git status` clean after each): **MU1** (the floor ignored in
   `shareWithEnclosingWrappers`) → 2.32 alone (three issues), on `3206ed1`
   and re-run on the final code; **MU2** (the visible frame back to the
   intersection) → 2.15, 2.31; **V4** (the direct path's visible frame
   untransformed) → 2.15, 2.31 — it reddened nothing before this ruling;
   **MU4** (a sharing wrapper does not pass the floor through) → 2.27 alone
   (its new arm). **MU3** (the modifier chain does not pass the floor through,
   as first written) stayed green: the effect reads its own element's entry
   floor, so the chain's pass-through was dead code — **deleted**, not kept
   unpinned.
4. **Red-first gap, recorded**: 2.7's and 2.22's current arms (`fxLands`,
   `GX-T` item 5) landed in the implementation commit `7568ac2`, not on the
   red commit `267fd8e`. Re-run against `267fd8e`'s sources with today's
   `RenderEffectTests.swift`, they redden: 2.7 all four arms, 2.22 both — so
   they rest on that run and on M2g, not on M2g alone.
5. **The stack budget's baseline**: the bisection (16 KB steps, an exit test
   per size, `buildEveryProductionTree(onAThreadOf:)`, arm64 debug, native
   build system) reads **672 KB at `dc96395`** (656 fails) and **672 KB at
   `3206ed1`** — lane 2 moves it by less than one step. The rise from drag and
   drop's 656 KB predates this branch.

**Cost if wrong.** An element that should be transparent to the share and is
not a sharing wrapper (a future single-child wrapper element) stops it: a
handler written outside it over an effect keeps its axis-aligned frame
(divergence 41), the conservative answer. A new sharing wrapper owes a
`sharingRegistrationsWithEffects` call, which passes the floor through.

---

## GX-V — Lane 3's readings: paths and shadows as vectors to the scene, the leaf walk, three amended tests, frame 7's rasters

**Ruling.** Lane 3 (`Path`, styles, shadows, the demo, the documents) built
`GX-C`, `GX-D`, `GX-E`, `GX-J`, `GX-K`, `GX-L` (its pin), `GX-M` and `GX-Q` as
written, with these readings, each measured in the lane:

1. **`everyTokenDiffersBetweenLightAndDark` exempts `.shadow` by name.**
   `GX-J` gives both themes SwiftUI's one default (black at 0.33, probe SH2);
   the sweep over `allCases` would redden on the first token two themes share
   by design. `noTwoTokensCollideWithinAVariant` is unchanged and still holds
   (light's `scrollIndicator` is black at 0.35, not 0.33).
   `theSubscriptReturnsEachTokensOwnProperty` gains the `shadow` arm (it
   passes `shadow:`), and `theDefaultShadowColourIsTheShadowToken` pins the
   value.
2. **`ShapeCompileGuards` G2.1's control is amended.** `GX-D` defaults both
   requirements, so the old control (a conformer without `geometry(in:)`)
   compiles — and traps at its first paint, 3.4. The control is now the same
   struct with `geometry(in:)` but no `Shape` conformance, refused at `.fill`:
   the positive's `.fill`/`.stroke`/`HStack` membership still come from
   `Shape`. Measured: `with succeeded=true`, `without succeeded=false`.
3. **`CloseoutTests` F1.3 counts the I1 bitmaps only** (the untransformed
   images sampling the 16 × 8 or a 4 × 4 texture): the Q section adds path and
   shadow rasters and a turned 4 × 4 checker, so "4 images" in the whole scene
   no longer reads I1. Its intent (fit, fill, nearest, bilinear) is unchanged.
4. **A path is a vector until `insertIntoScene`.** `CapturedPrimitive.path`
   carries `PathPaint`: the outline in points, the fill rule or stroke
   parameters, a `local` map (points → device pixels: the scale factor and the
   scroll translation at emission), the colour and the mask in force. A
   flattening scope composes its map into `local` (and maps an inner mask, as
   for a rect); a non-flattening one gives it a transform record by the
   generic path. At `insertIntoScene` the composed map is
   `transform ∘ local`, and `RasterPlacement` decides the masks: with no
   transform the image carries the path's own mask (the GPU cuts a rounded
   clip exactly); with one the image carries the **outer** mask and the local
   mask's coverage (a rounded rect rasterized under the transform) is
   multiplied into the raster. **A path's image is therefore always
   untransformed** (index 0), rotated or scaled — 3.11, 3.12.
5. **The paint-scope walk carries leaves, not primitives.** A primitive
   arriving at `insertThroughScopes` is a one-primitive leaf; a text draw's
   glyphs are buffered between `beginLeafGroup`/`endLeafGroup` (only while a
   paint scope is open — the empty-stack fast path is untouched) and arrive as
   one leaf. Each scope maps every leaf; a shadow scope emits, per leaf,
   `[shadow(leaf)]` and then the leaf, so to every scope further out the
   shadow is itself a leaf (SH11, 3.22). A shadow item's own mask is the clip
   at its scope's entry, so its `innerMask` against an outer scope is read at
   that depth (`CapturedPrimitive.maskDepth`), not at the emission depth. A
   `Deferred`'s barrier stops a shadow as it stops an effect, and is pushed
   when either is open.
6. **Frame 7 gains MetalUIPath's rasters** (`GX-S` item 5's owed item):
   `Experiments/SDLGPU`'s `pathRasters` renders a 240 × 64 tree (a star filled
   nonzero, the same star even-odd, a dashed round-joined stroke, a blurred
   shadow) through `renderFrame` and inserts its four images, moved by a whole
   pixel offset so every nearest texel stays centred on its pixel (`TE-AR`
   item 5). Measured: `Replay --portable --record` passes all 8 frames, frame
   7 at 0 differing pixels on SDL's Metal backend (6 rects, 28 glyphs, 6
   images, 9 transforms). CI's `--expect 8` is unchanged.
7. **Shadow animation keys.** Proposal: radius and offsets on
   `$anim-layer.shadow` (layout, `animatedNumbers`, the radius clamped ≥ 0),
   the colour on `$anim-layer.shadow.colour` (paint, `storedAnimatedColor`).
   Legacy: radius and offsets ride `$anim-effects` with the other effects
   (`RenderEffectSpec.shadow`, kind tag 3), the colour on
   `$anim-effects.shadow<k>` in paint. All store keys — the reserved
   `StateTable` names stay seven. A shadow opens no prepaint scope (it never
   hits and publishes nothing) and does not count in `effectScopesPushed`, so
   2.21 is unmoved.
8. **`nonisolated public` hides a declaration from the census.**
   `closeout-public-api.sh` reads declarations that begin with `public`/`open`;
   `Path`'s members (main-actor isolation comes from `Shape: ProposalElement`,
   and SwiftUI's `Path` is nonisolated) first spelled `nonisolated public`
   were invisible to the census and to `closeout-undocumented.sh` — 24
   declarations. They are spelled `public nonisolated`. No other source file
   uses the hidden order (grep of `^\s*nonisolated public`, recorded).
9. **Arms re-derived in the lane** (the red run's own readings): 3.3's
   recording shape sits at (18, 10) so the 68 × 40 root's centred origin is a
   whole point (66, 80) — at (17, 9) it is (66.5, 80.5); 3.6's ellipse allows
   8 disagreements (four cubics approximate an ellipse to 0.027 % of its
   radius, about 0.016 points at r 60; measured 4 — the rounded rectangle,
   capsule and circle read 0); 3.16 shadows "Hi, there" ("Shadowed" at 20 pt
   inks 43 % of its box, over the 40 % bound). `RasterMath.multiply` trims to
   the two masks' overlap (3.20's inner clip read the unclipped 80 × 80 box
   with zero texels outside the clip).
10. **Two pins beyond the spec's 28**, each green on arrival: 3.29
    `aTextUnderScaleEffectIsResampledNotReRasterized` (divergence 106: a glyph
    under `scaleEffect(3)` keeps its atlas slot and is drawn three times
    larger) and 3.30 `aShapesStrokeWidthSnaps` (divergence 97 amended: a
    stroke width written under `withAnimation` is the final width half-way).
    The divergences needed pins; neither had one.
11. **`strokeBorder` of a `Path` strokes the path itself** (a `Path` ignores
    its rect, so the half-width inset reaches nothing). SwiftUI offers
    `strokeBorder` only on an `InsettableShape`, which `Path` is not; MetalUI
    offers it on every `Shape` (`TE-AG` item 3). Unprobed, MetalUI's own.
12. **Red run** (`53f18ac`, the skeleton: no rasters, no shadow items, the
    defaults non-trapping, every stroke a band, the Q section uncomposed;
    filtered to the lane's files, 65 tests): 26 of the 28 spec tests red;
    green on arrival 3.5 (the built-ins' SDF pin) and 3.21 (a shadow
    registers nothing — true of no shadow), and the three guards (the API
    exists; each mutated red below).
13. **the mutation table** (whole unfiltered suite each, 2224 tests, the
    `FR-J` line present, `git status` clean after every restore; on
    `a131187`). Every spec mutation reddens its named test.
    M3a (the path scaled into its frame) → 3.1, 3.25; M3b (a fixed colour) →
    3.2, 3.14; M3c (`path(in:)` handed the window rect) → 3.3 alone; M3d (the
    reentrancy check removed: the recursion overflows the stack with no
    message) → 3.4 alone; M3e (every fill routed through the path) → a
    truncated run (`Index out of range` in an existing test reading a rect
    that is now an image) with nineteen existing shape, overlay, background,
    border and preview tests red before it, and 3.5 red in a supplementary
    filtered run (the truncation fell before it); M3f (corner control arms
    0.5 for 0.5523) → 3.6 alone; M3g (`ShapeView` drops the `FillStyle`) →
    3.7 alone; M3h (every stroke rasterized) → 3.8, 3.30, 3.5, F1.3 and eight
    `ShapeStrokeTests`/`ShapeTests` band pins; M3i (a path's `contains` its
    box) → 3.9 alone; M3j (a path clip as its box) → 3.10 alone; M3k (the
    raster made at the local resolution, the image transformed) → 3.11,
    3.12, 3.14; M3l (no cache) → 3.13, 3.14; **M3m, four**: the colour
    dropped from the tint key, the transform, the clip, the path each dropped
    from the coverage key → 3.14 each (the path's also 3.25: its frame
    reused the narrow raster); M3n (one composited shadow, after the
    content) → 3.15, 3.16, 3.22, 3.23, 3.26, 3.28; M3o (no leaf group: a
    shadow per glyph) → 3.16, 3.26; M3p (sigma = radius / 2) → 3.17, 3.24;
    M3q (the default `.textPrimary`) → 3.18 alone; M3r (the leaf's colour
    alpha ignored) → 3.19 alone; M3s (the silhouette ignores the leaf's
    masks) → 3.20 alone; M3t (the shadow's grown bounds registered as a
    hitbox) → 3.21 alone; M3u (shadow images not leaves) → 3.22 alone; M3v
    (the offset not mapped) → 3.23 alone; M3w (the radius snaps) → 3.24
    alone; **M3x is not run**: no code interpolates a path to remove — 3.25 is
    a pin of absence (red on the skeleton only because nothing drew), and it
    is discriminated by M3a and M3m-path; M3y (the legacy `.shadow` returns
    `self` unchanged) → 3.16, 3.26, 3.28 (its first spelling, the paint
    scope skipped in `withRenderEffects`, failed to compile — a closure
    capturing the non-escaping `body` — and was replaced); M3z (a surface's
    silhouette empty) → 3.27 alone; M3aa (the Q section left out of the
    composer) → 3.28 alone. Guards: **MG3.1** (`Path.addRects(_:)` made
    `internal`) → G3.1 alone — the spec's `StrokeStyle.init` made `internal`
    fails the package build before any test runs (the looks demo, another
    module, calls it), so a spelling no other module uses was chosen;
    **MG3.2** (`path(in:)` removed from the protocol, its default made
    `internal`) → G3.2, then a trap at 3.3's recording shape (its
    `path(in:)` is no longer a witness, so the default `geometry(in:)` reaches
    the default `path(in:)` and `GX-D`'s check fires); **MG3.3** (the
    `shadow:` default removed, the two in-repo pre-token themes in
    `AXNodeTests`/`AnimationTests` given `shadow:` so the suite builds) →
    G3.3 alone.

14. **Counts** (`a131187`): **2224 tests in 3 suites** (2191 + 33: the
    spec's 28, the two pins of item 10, the three guards), guards **133**
    (130 + G3.1–G3.3), 0 goldens; the `FR-J` line present; 0 `error:` on both
    build systems, the one `warning:` SwiftPM's deprecation notice under
    native, 0 under `swift build --build-tests`. Census **2086** declarations
    in **105** families (`paths`, `stroke-styles`, `shadows` added); both
    closeout checks print nothing. **0 px against `dc96395` in all fourteen
    offscreen images**, every scene identical
    (`docs/probes/demo-pixels/compare.sh`). Divergences 76 live (104–106
    added here), next label 110. The screen was locked at the lane's close
    (`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`): no
    real-window capture, no probe re-run, the demo not launched.
15. **Off the root suite** (`a131187`): `Backends/SDL`
    (`PKG_CONFIG_PATH=$PWD/.accesskit`) builds with 0 `error:` and runs
    **24 + 57**, unmoved; `Experiments/SDLGPU`'s `Replay --portable --record`
    passes all 8 frames (item 6), and on its fixtures `PortableReplay --expect
    8` (SDL Metal, every frame 0 px) and `DemoCapture` (the demo's scene
    byte-for-byte macOS's, 0 px) PASS on macOS; Linux llvmpipe and Windows
    D3D12 confirm on push. A `swift:6.4-noble` aarch64 container
    (`metalui-portable`, Swift 6.4, Ubuntu 24.04; OrbStack started and stopped
    after) builds with 0 `error:`/`warning:` and runs **199 + 22 + 21 + 31 +
    18 + 6**, as lane 2's.

16. **Review round** (lane 3's verifier: two majors, four minors; each
    finding's mutation re-run here, whole unfiltered suite, **2227 tests**,
    the `FR-J` line present, `git status` clean after every restore). Three
    tests added and four extended, red-first by mutation (each mutation was
    green on the 2224-test suite, per the review): **3.31**
    `aDeferredStopsAnEnclosingShadow` (item 5's barrier: a shadowed legacy
    column casts its in-flow bar's shadow and none for its `Deferred` box) —
    **MV1** (`insertThroughScopes` lets `.shadow` past the barrier) and
    **MV1b** (`withoutRenderEffects` pushes no barrier when only a shadow is
    open) → 3.31 alone each; **3.24b** `aLegacyShadowsColourRadiusAndOffsetAnimate`
    (item 7's legacy half; 3.24's assertions shared through one helper) —
    **MV2** (the legacy colour always `theme[token]`) and **MV3**
    (`RenderEffectSpec.with(_:)` returns `self` for a shadow) → 3.24b alone
    each; **3.32** `aFadingTransitionScalesAPathsAndAShadowsAlpha` (a
    `.transition(.opacity)` half-way: a path's solid texel and a shadow-only
    texel read 128 ± 2, 255 at rest) — **MV6** (the `.path` arm of
    `RenderEffect.apply` drops the alpha) and **MV6b** (the `.shadow` arm) →
    3.32 alone each; 3.20 now requires one cut shadow and reads its exact
    bounds (90, 90, 30 × 30) — **MV9** (no shadow under an entry clip under
    100 px wide) → 3.20 alone; 3.21 gains a window arm, a shadow on each
    vocabulary pushing **0** effect scopes (item 7's counter claim) — **MV4**
    (`PrepaintPass.withRenderEffect`'s shadow guard removed) → 3.21 alone;
    3.9 gains an even-odd ring (`ShapeGeometry.path(_, style: FillStyle(eoFill:
    true))` as a `contentShape`, the hole missing, the band hitting, and
    `Path.contains(_:eoFill:)` directly) — **MV13** (`eoFill` ignored) → 3.9
    alone; 3.7 gains `Circle().fill(_, style: FillStyle(antialiased: false))`
    drawing one image whose alphas are exactly {0, 255} — **MV8** (the
    non-antialiased branch of `paintShapeFill` disabled) → 3.7 alone. One
    reading on the way: an outside shape answering `geometry(in:)` with
    `.path` answers in the rect's own space (window points), unlike
    `path(in:)`, whose local path the default `geometry(in:)` moves to the
    rect — 3.9's ring offsets itself by `rect.origin`. Counts **2227 / 0 /
    133**.

**Cost if wrong.** Items 1–3 change existing tests' instruments, each for a
ruled reason with the old intent kept. Item 4 rasterizes a path whose clip
was pushed inside an effect with a CPU mask (exact to the rasterizer's
coverage) rather than the GPU's analytic one. Item 8 is a census blind spot:
a future declaration spelled `nonisolated public` (or with any other leading
modifier) would escape both closeout checks silently.

---

## GX-W — The Record phase's close

**Ruling.** The Record phase (2026-10-02) wrote record §73, marked the spec
BUILT, updated `CLAUDE.md`/`AGENTS.md` (the `GX-` prefix, the `MetalUIPath`
import rule, the paths/shadows/transforms paragraph, the `Shape` line, the
counts), `README.md`, records §03/§04/§05 and the record index, and re-took:

1. `git fetch`: `origin/master` still `dc96395`; §73 needed no renumbering and
   group Q no letter change.
2. `swift package clean`, the native build (0 `error:`, the one SwiftPM
   `warning:`) and the unfiltered `swift test --build-system native
   --no-parallel`: **2227 tests in 3 suites passed**, the `FR-J` line present.
   Guards **133** (129 + `PathCompileGuards` 3 + `RenderEffectCompileGuards`
   1).
3. Both closeout checks print nothing (census 2086, 105 families).
4. The fourteen-image comparison against `dc96395` (§73 §7).

**Reading.** Nothing in this phase moved a source file; every figure is read
from a run, not from a lane's report. **Cost if wrong.** None beyond the
documents.

---

## GX-X — A clip pushed inside a flattening effect is cut by the clip at the effect's entry (LF-a)

**Finding.** MetalCreator's gap LF-a, on `67a579e`: a `.clipped()` inside an
`.offset` or a uniform positive `.scaleEffect` forgot the clip outside the
effect. `GX-G` item 3 split the clip at the entry of a **non-flattening**
paint scope only, so inside a flattening one `pushClip` intersected the new
clip with the outer clip **in the content's pre-effect space**, and
`RenderEffect.apply` then moved that mask by the effect and never cut it by
the clip in force at the entry. Two symptoms of one cause, both measured red
(record §73 §12): a clipped bar moved 60 up out of a 100 × 100 clip at
(50, 50) kept the mask (80, 20) 40 × 40 and painted 30 px above it (under
`scaleEffect(4)`, (20, 20) 160 × 160); and a clipped bar laid out outside the
clip and moved **into** it got the empty mask (50, 130) 40 × 0 and drew
nothing. Prepaint was right: it always splits (`GX-G` item 3), and a hitbox
is tested against its local clip through the inverse and against the outer
clip in window space — pinned, not changed.

**Ruling.**
1. **The first clip pushed inside a flattening scope intersects nothing
   outside it**: `Frame.flatteningClipBase` (the clip depth at the innermost
   flattening scope's entry) makes `pushClip` skip the intersection when the
   stack is exactly that deep (and above `clipBase`). Unlike `clipBase` it
   leaves `activeClip` alone, so a primitive with no clip pushed inside still
   reads the entry clip — its bytes, and a removal ghost's or a drag
   preview's capture of it, are unchanged.
2. **A flattening effect scope keeps its entry clip** as `PaintScope.outer`
   (as a non-flattening one already did), and `insertThroughScopes`, after
   `apply` maps the primitive, **cuts every mask pushed inside the scope** by
   it — the primitive's own (`innerMask`) or its transform record's outer
   mask (`outerMaskInner`) — with `Frame.intersect(_:radii:_:radii:)`, radii
   included. Nested flattening scopes compose: each cuts by its own entry clip
   in its own target space. Transitions are not effect scopes and are
   untouched.
3. No scene, shader or record format change: the SDL replay parity is not
   engaged.

**Tests** (`RenderEffectTests`, `RenderEffectHitTests`, the `LF-a` sections):
`aClipInsideAnOffsetIsStillCutByTheClipOutsideIt` (both vocabularies),
`aClipInsideAUniformScaleIsStillCutByTheClipOutsideIt` (both),
`aClipInsideNestedFlatteningEffectsIsCutByTheClipOutsideBoth`,
`contentMovedIntoTheOuterClipByAnOffsetKeepsItsOwnClip`,
`aRecordsOuterMaskInsideAnOffsetIsCutByTheClipOutsideIt` — red on `67a579e`;
`aHitboxInsideAnOffsetIsCutByTheClipOutsideIt` — a pin, green on arrival.
Mutations (each a full unfiltered suite): **M-X1** (the cut skipped for a
primitive's own mask) → the offset, scale and nested tests; **M-X2** (no
split at the flattening entry) → the moved-in test alone; **M-X3** (the cut
skipped for a record's outer mask) → the record test alone; **M-X4**
(prepaint does not split at a flattening effect) → the hitbox pin's moved-in
arm alone.

**Carried.** A removal ghost replays its capture straight into the scene,
past every scope outside its transition (pre-existing): a ghost inside an
`.offset` is drawn unmoved, and since this ruling a mask pushed inside the
offset is no longer pre-cut by the clip outside it. Owner none.

**Cost if wrong.** A content clip inside a flattening effect is now local,
so a GPU surface's off-clip cull (`Frame` surface emission, which reads
`activeClip`) inside one compares against the local clip only — it can do
GPU work for a surface the outer clip hides; it never culls one the effect
brings into view, which it did before.
