# Paths, shadows and transforms — design

User request 2026-10-02 (item 3 of the gpui-gap priority list; not a plan
task). Rulings `GX-A`…`GX-S` in (`GX-P`…`GX-R` from the critic round, `GX-S` lane 1's readings)
[`../2026-10-02-paths-shadows-transforms-decisions.md`](../2026-10-02-paths-shadows-transforms-decisions.md);
probe [`../../probes/swiftui-paths-shadows-transforms.swift`](../../probes/swiftui-paths-shadows-transforms.swift)
(arms P1–P6, PA1–PA9, ST1–ST11, SH0–SH13, T0–T16, H1–H7, X1–X6, N1–N10;
recorded 2026-10-02 with the screen unlocked, run twice byte-identical).
Record: `docs/record/73-paths-shadows-transforms.md` (the Record phase).

Branch `feat/paths-shadows-transforms` from `dc96395`. Baseline **2124 tests
in 3 suites, 0 goldens, 129 typecheck guards**, 70 live divergences (next
label 104).

## 1. What is built

```swift
// MetalUI — new value types
public struct Angle: Hashable, Comparable, Sendable {               // GX-C
    public var radians: Double; public var degrees: Double
    public init(radians: Double); public init(degrees: Double)
    public static func radians(_: Double) -> Angle; public static func degrees(_: Double) -> Angle
    public static let zero: Angle
    // + - unary-, * / by Double (SwiftUI's arithmetic)
}

public struct FillStyle: Hashable, Sendable {                        // GX-E
    public var isEOFilled: Bool; public var isAntialiased: Bool
    public init(eoFill: Bool = false, antialiased: Bool = true)
}
public enum LineCap: Hashable, Sendable { case butt, round, square }
public enum LineJoin: Hashable, Sendable { case miter, round, bevel }
public struct StrokeStyle: Hashable, Sendable {
    public var lineWidth: Pixels; public var lineCap: LineCap; public var lineJoin: LineJoin
    public var miterLimit: Double; public var dash: [Pixels]; public var dashPhase: Pixels
    public init(lineWidth: Pixels = 1, lineCap: LineCap = .butt, lineJoin: LineJoin = .miter,
                miterLimit: Double = 10, dash: [Pixels] = [], dashPhase: Pixels = 0)
}

public struct Path: Shape, Equatable, Sendable {                    // GX-C, GX-D
    public init()
    public init(_ rect: Bounds<Pixels>)
    public init(roundedRect: Bounds<Pixels>, cornerRadius: Pixels, style: RoundedCornerStyle = .continuous)
    public init(roundedRect: Bounds<Pixels>, cornerSize: Size<Pixels>, style: RoundedCornerStyle = .continuous)
    public init(ellipseIn rect: Bounds<Pixels>)
    public init(_ build: (inout Path) -> Void)
    public mutating func move(to: Point<Pixels>)
    public mutating func addLine(to: Point<Pixels>)
    public mutating func addLines(_ points: [Point<Pixels>])
    public mutating func addQuadCurve(to: Point<Pixels>, control: Point<Pixels>)
    public mutating func addCurve(to: Point<Pixels>, control1: Point<Pixels>, control2: Point<Pixels>)
    public mutating func addArc(center: Point<Pixels>, radius: Pixels, startAngle: Angle,
                                endAngle: Angle, clockwise: Bool)
    public mutating func addArc(tangent1End: Point<Pixels>, tangent2End: Point<Pixels>, radius: Pixels)
    public mutating func addRect(_ rect: Bounds<Pixels>)
    public mutating func addRects(_ rects: [Bounds<Pixels>])
    public mutating func addRoundedRect(in rect: Bounds<Pixels>, cornerSize: Size<Pixels>,
                                        style: RoundedCornerStyle = .continuous)
    public mutating func addEllipse(in rect: Bounds<Pixels>)
    public mutating func addPath(_ path: Path)
    public mutating func closeSubpath()
    public var isEmpty: Bool { get }
    public var currentPoint: Point<Pixels>? { get }
    public var boundingRect: Bounds<Pixels> { get }
    public func contains(_ p: Point<Pixels>, eoFill: Bool = false) -> Bool
    public func offsetBy(dx: Pixels, dy: Pixels) -> Path
}

// MetalUI — Shape gains SwiftUI's requirement (GX-D); both defaulted, implement either
public protocol Shape: ProposalElement, Sendable {
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry   // window-space rect (unchanged)
    func path(in rect: Bounds<Pixels>) -> Path                // LOCAL rect, origin (0, 0) — PA9
    nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD
}
extension ShapeGeometry { public static func path(_ path: Path, style: FillStyle = FillStyle()) -> ShapeGeometry }
extension Shape {
    public func fill(style: FillStyle) -> ShapeView<Self>
    public func fill(_ token: ColorToken, style: FillStyle) -> ShapeView<Self>
    public func stroke(_ token: ColorToken, style: StrokeStyle) -> ShapeView<Self>
    public func strokeBorder(_ token: ColorToken, style: StrokeStyle) -> ShapeView<Self>
}   // and the same three on ShapeView (layers, in declaration order — TE-AH)

// MetalUI — render effects (GX-H) and shadow (GX-J), both vocabularies
extension ProposalElementGroup {       // each one LayoutModifier layer: ModifiedContent<ProposalBase, LayoutModifier>
    func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> ...
    func scaleEffect(_ s: Double, anchor: UnitPoint = .center) -> ...
    func scaleEffect(_ s: SizeD, anchor: UnitPoint = .center) -> ...
    func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> ...
    func offset(x: Pixels = 0, y: Pixels = 0) -> ...
    func offset(_ offset: Size<Pixels>) -> ...
    func shadow(color: ColorToken = .shadow, radius: Pixels, x: Pixels = 0, y: Pixels = 0) -> ...
}
extension StyledElement { /* the same seven, each returning Self (Decoration.renderEffects) */ }

public enum LayoutModifier {           // three new cases + shadow — public break (GX-H, migration note)
    case rotationEffect(Angle, anchor: UnitPoint)
    case scaleEffect(x: Double, y: Double, anchor: UnitPoint)
    case offset(x: Pixels, y: Pixels)
    case shadow(ColorToken, radius: Pixels, x: Pixels, y: Pixels)
}
public enum ColorToken { case shadow }  // new: black at 0.33 in both themes — public break (GX-J)

// MetalUIScene / MetalUIShaderTypes (GX-F)
typedef struct { float a, b, c, d, tx, ty, pixelScale; MUIUInt _reserved;
                 MUIBounds outerMask; MUICorners outerMaskRadii; } MUITransform;   // 64 bytes
// MUIGlyph._reserved renamed `transform`; MUIRect.shape bits 8…31 and MUIImage.filter bits 8…31 carry it
public struct Scene { public private(set) var transforms: [MUITransform]
    public mutating func insert(_: MUIRect, layer: Int = 0, transform: MUITransform? = nil)   // and glyph, image, surface
}

// MetalUIPath — new portable target, imports nothing (GX-B); `package` API only
```

Not offered (spec §9): `transformEffect`, `projectionEffect`,
`rotation3DEffect`, `compositingGroup`, `drawingGroup`, `trim`,
`trimmedPath`, `strokedPath`, `applying`, `addRelativeArc`, inner shadows.

## 2. What SwiftUI does (the probe)

| subject | SwiftUI's answer | arms |
|---|---|---|
| `Path` view sizing | the proposal, nil → 10 | PA1 |
| where a `Path` draws | its own coordinates from the view origin; not scaled to, not clipped by the frame | PA1, PA1b |
| fill rules | default nonzero; even-odd empties a same-direction ring; a reversed ring is a hole under both | PA2 |
| `addArc(clockwise: false)` 0°→90° | sweeps below-right (visually clockwise in y-down) | PA3 |
| curve coverage | quad segment 3325.8 of analytic 3333.3 | PA4 |
| `addEllipse`, `addRoundedRect` default | equals `Ellipse()`; default style `.continuous` | PA5 |
| an open subpath | fills as if closed | PA6 |
| `path(in:)`'s rect | local, origin (0, 0) | PA9 |
| bare `Path` colour | the foreground style | PA8 |
| caps | butt x20…79; round x14…85; square x15…84 (w10 on 20…80) | ST1–ST3 |
| default stroke | width 1, butt, miter, limit 10 | ST4–ST6 |
| joins (V, w10) | miter tip y7, bevel y18, round y15 | ST5 |
| miter limit (ratio 8.06, w4) | limit 10 mitres (tip −4), limit 4 bevels (tip 9) | ST6 |
| dashes (w4, 0…100) | `[10,10]`: `[0…9] [20…29] …`; phase 5: `[0…4] [15…24] …`; `[10,5,2,5]`: `[0…9] [15…17] [22…31] …` | ST7 |
| closed vs open subpath corner | joined vs capped | ST8 |
| width ≤ 0 | nothing | ST10 |
| shadow default colour | black 0.33 (171 over white) | SH2 |
| shadow blur | Gaussian, sigma = radius (fit 1.02, 1.00) | SH3, SH3b |
| shadow model | per leaf (top child's shadow on the child below); `compositingGroup` composites | SH5, SH5c, SH5d, SH5e |
| text / stroke / path shadow | glyph-, ring-, triangle-shaped | SH4, SH9, SH12 |
| shadow and alpha, clip, layout | follows content alpha; cut by an outer clip, shaped by an inner one; no layout change | SH6, SH7, SH7b, SH8 |
| two shadows | the second shadows the first | SH11 |
| rotation | about `.center`, positive = clockwise; no layout change | T1, T2, T2b |
| scale | about the anchor; `x:y:` = size form; −1 flips; 0 draws nothing | T3–T5b |
| offset | moves paint only; siblings unmoved | T6, T6b, T6c |
| order | inner clip/background/shadow transform with the effect; outer ones do not; offset/rotation order matters | T7–T11, T14 |
| text under rotation | legible | T9 |
| text and paths under scale | re-rasterized (crisp) | T15b, T16 |
| hit testing | follows rotation, scale, offset; a shadow never hits | H1–H7 |
| accessibility frame | transformed frame's bounding box (offset, scale, 90°); smaller than the box at 45° | X1–X5 |
| shadow and accessibility | unchanged | X6 |
| animation | rotation angle + anchor; scale factors + anchor; offset; shadow colour, radius, offset; a `Path` view snaps; `stroke(lineWidth:)` and `trim` animate | N1–N10 |

## 3. What MetalUI has today (inventory)

- **Renderer** (`Sources/MetalUIRender/Shaders/{MetalUIShaderTypes.h,shaders.metal}`,
  `Renderer.swift`; `Backends/SDL/Shaders/replay.hlsl`, `SDLBridge.c`,
  `SDLWindowRenderer.swift`): three instanced pipelines — rect (rounded rect
  or ellipse SDF, `MUIRect.shape`), glyph (R8 atlas, `coord::pixel` linear),
  image (whole texture, linear or nearest; surfaces share it). Every vertex
  stage maps a unit quad to `bounds`; every fragment evaluates its SDF and its
  rounded-rect `contentMask` at the varying `pixelPosition`. Strides: `MUIRect`
  128 in the replay packing (8 lanes), `MUIGlyph` with a `_reserved` word,
  `MUIImage` 64. No transform anywhere.
- **Scene** (`Sources/MetalUIScene/Scene.swift`): per-kind arrays, side
  tables, `finalize()` by `(layer, order, sequence)`, texture/target tables
  never reordered.
- **Emission** (`Sources/MetalUI/Frame.swift`): `fill`, `drawImage`,
  `drawSurface`, `drawSprite`, each inserting directly unless
  `transitionScopes` is non-empty, then `insertThroughTransitions` →
  `insertIntoScene`; `activeOffset` is the **scroll** offset (no public
  `.offset` modifier exists); `clipStack`/`activeClip`/`activeClipRadii`;
  `insertHitbox` intersects with the active clip; `recordAccessibility`.
- **Transitions** (`Transition.swift`): `TransitionAtom` → `TransitionEffect`
  (alpha, uniform `scale`, `tx`, `ty`) applied to `CapturedPrimitive`
  (rect/glyph/image/surface, layer, `innerMask`); ghosts and the drag
  preview replay captured primitives.
- **Shapes** (`Shape.swift`, `Shapes.swift`, `ShapeView.swift`,
  `ClipShape.swift`): `geometry(in:)` → rounded rect or ellipse; `ShapeView`
  fill/stroke/strokeBorder layers drawn as `MUIRect`s; `clipShape` traps on an
  ellipse (divergence 91).
- **Decoration** (`Box.swift`): order-insensitive legacy paint fields;
  `paintDecoration` (`AnimatedColor.swift`) paints background/content/border
  and pushes the drag capture; `registerAndScope` registers handlers.
- **Animation** (`ProposalAnimation.swift`, `AnimationStore.swift`):
  proposal `LayoutModifier` cases animate at their phase on the store.
- **Replay** (`Backends/SDL/Sources/ReplayFixture`, `Experiments/SDLGPU`):
  fixture version 2, frames 0–6, CI `--expect 7`.

## 4. What each thing does

### 4.1 Paths (`GX-B`…`GX-E`)

A `Path` is a list of subpaths of `move`/`line`/`quad`/`cubic`/`close`
elements in local points; arcs, ellipses and rounded rects are stored as
cubics (≤ 90° each; circular corners — divergence 90 amended for
`.continuous`). As a view it answers its proposal and paints its path
offset by its layout origin with `foregroundStyle ?? .textPrimary` (a
`ShapeView` layer's token otherwise). Painting emits a
`CapturedPrimitive.path(PathPaint)` — path, fill style or stroke style,
colour, device scale — which every open paint scope transforms by composing
its affine; at `insertIntoScene` the composed affine is applied to the
control points, the path flattened (0.1 device px), stroked if a stroke, and
rasterized into the visible device rectangle; the `RasterCache` (`GX-K`)
returns the `ImageTexture`, and one `MUIImage` (filter nearest, integer device
bounds, the outer mask as its `contentMask`, inner local clips already
multiplied into the coverage) reaches the scene. Built-in shapes keep their
`MUIRect`. A plain-width stroke of a built-in shape keeps the SDF band; any
other style is stroked (§`GX-E`). `contentShape(path)` hits by winding.
`clipShape(path)` traps naming divergence 91.

### 4.2 Transforms (`GX-F`…`GX-I`)

`rotationEffect`/`scaleEffect`/`offset` push a **render-effect scope** in
prepaint and paint around their content. Its affine (points) is
`T(anchorPoint) · L · T(−anchorPoint)` composed with the offset, where
`anchorPoint = bounds.origin + activeOffset + anchor × bounds.size` (the
scroll translation primitives and hitboxes already carry, `GX-P` item 4) and `L` is
`[[cos, −sin],[sin, cos]]` (y-down; positive degrees clockwise) or
`diag(x, y)`. Scopes compose outer-to-inner in written order. In paint, each
emitted primitive is mapped (`GX-G`: flattened on the CPU when the composed
map is a translation plus a uniform positive scale, a transform record
otherwise, scaled by the device scale factor into device px). A non-flattening
scope splits the clip (outer mask / local clips). In prepaint, hitboxes store
the inverse composed affine and the outer clip; accessibility records store
the bounding box of the transformed bounds. A registration made by a proper
ancestor at the effect's own rect (a handler, gesture, draggable, drop
destination or accessibility layer written after the effect) is transformed
too; a rect-changing layer between them stops it (`GX-P` items 1–2). `Window`
maps an event point through the hit hitbox's inverse before a gesture leaf, a
value track, a text press or a drop destination reads it (`GX-P` item 3). A zero scale skips the content's
paint (nothing drawn) and registers hitboxes that contain nothing. Layout is
untouched: the layer answers its child's size.

### 4.3 Shadows (`GX-J`)

`.shadow` pushes a **shadow scope** in paint only. Each leaf emitted inside it
(one primitive; or one text draw's glyphs, bracketed by `beginLeafGroup`/
`endLeafGroup`) becomes `[CapturedPrimitive.shadow(ShadowPaint), leaf…]`
where `ShadowPaint` carries the leaf's captured primitives, colour, radius and
offset; outer scopes transform the shadow item like any primitive (composing
its affine), so the shadow's offset and sigma follow the composed transform
(T10, T14). At `insertIntoScene` the silhouette is rasterized in device space
(rects/ellipses/paths via `MetalUIPath`; glyphs from the atlas bitmap;
images from their alpha; a surface as its quad), multiplied by each
primitive's colour alpha and mask, offset, triple-box-blurred with sigma =
radius × `sqrt|det|`, tinted, cached, and inserted as one `MUIImage` before
the leaf.

## 5. Scene and renderer (`GX-F`, lane 1)

### 5.1 Packing

- `MUITransform` (64 bytes, four `float4` lanes) in `MetalUIShaderTypes.h`;
  `Scene.transforms`; `Scene.insert(…, transform:)` writes index `i + 1` into
  the packed word (`MUIRect.shape |= idx << 8`, `MUIImage.filter |= idx << 8`,
  `MUIGlyph.transform = idx`), reusing the last entry when equal;
  `precondition(idx < 1 << 24)`.
- `ShaderTypesBridge.swift`: `MUIRect.shapeKind`/`transformIndex`,
  `MUIImage.filterKind`/`transformIndex` accessors; `MUIGlyph(…, transform: 0)`
  memberwise re-spelling at every `_reserved:` glyph site
  (`git grep -n _reserved` at `dc96395`: 30 lines across sources, tests,
  `Backends/SDL` and `Experiments`; the lane lists what is left afterward —
  nothing named `_reserved` but `MUITransform`'s own pad).
- Every shader compares `(shape & 0xFF)`, `(filter & 0xFF)`; for every scene
  before this change the masked value equals the old word.

### 5.2 Shaders (both languages, the same arithmetic)

A new buffer index per pipeline (`MUIRectBufferTransforms = 4`,
`MUIGlyphBufferTransforms = 4`, `MUIImageBufferTransforms = 4`; HLSL: the
next storage-buffer register in each stage's space), bound to vertex and
fragment; an empty table binds a one-record dummy that index 0 never reads.

```
vertex:   idx == 0 → today's code
          else     → T = transforms[idx − 1]; f = 1 / T.pixelScale
                     local = bounds.origin − f + unit × (bounds.size + 2f)
                     screen = (T.a·x + T.c·y + T.tx, T.b·x + T.d·y + T.ty)
                     position ← screen; pixelPosition ← local; screenPosition ← screen
                     (glyph: atlasPosition extrapolated by the same fringe)
fragment: idx == 0 → today's code
          else     → s = T.pixelScale
                     rect:  every saturate(0.5 − sdf) becomes saturate(0.5 − sdf × s)
                     glyph: coverage = atlas.sample(clamp(atlasPosition, slotMin + 0.5, slotMax − 0.5))
                            × saturate(0.5 − rect_sdf(local, bounds) × s)
                     image: texel as today (filter kept, uv clamped to [0,1]) × the same edge term
                     all:   × mask_coverage(local, contentMask) × mask_coverage(screen, T.outerMask)
```

### 5.3 Parity frame 7

`Experiments/SDLGPU`'s `Replay` records **frame 7** through the Metal
renderer: a rounded rect with a border rotated 30°; an ellipse band rotated
45°; a rect under `scale(2, 0.5)`; a rect flipped `x: −1`; a glyph run
rotated 90° and one rotated 17°; a linear and a nearest image rotated 30°; a
rotated rect under an outer rounded mask with an inner local mask; a
nonzero and an even-odd path raster from `MetalUIPath`, and a blurred
shadow raster, both drawn as untransformed images (evidence that the CPU
rasters ride the parity-checked image pipeline) — **those rasters join frame
7 in lane 3**, through MetalUI's public `Path`/`.shadow`: a separate package
cannot call `MetalUIPath`'s `package` API (`GX-S` item 5). `ReplayFixture` version 3;
`.github/workflows/sdl-gpu-linux.yml`'s two `--expect 7` → `--expect 8`.
**Positive controls (recorded, not committed)**: the HLSL vertex stage
ignoring the transform index, and separately the HLSL outer mask dropped,
each fail frame 7's live SDL-Metal parity.

### 5.4 `MetalUIPath` (portable, imports nothing)

`package` API: `PathGeometry` (elements in `Double`), `PathMath.sinCos`
(Cody–Waite reduction by π/2 in two `Double` parts + degree-13/12 minimax
polynomials; basic operations only), `Flattener` (Wang's bound, tolerance
parameter), `Stroker` (caps, joins, miter limit, closed/open, dash walk),
`CoverageRasterizer` (exact-area accumulation, `FillRule.nonZero/.evenOdd`,
output `[UInt8]` over an integer rectangle, clip rectangle parameter, an
`antialiased: false` threshold), `BoxBlur` (three passes per axis, box widths
from sigma, integer sums, zero padding of `3σ`), `AlphaCompositor` (union,
nearest/bilinear resample of an R8 or RGBA8 source under an affine). Manifest:
the portable list; `MetalUI` depends on it; a new portable test target
`MetalUIPathTests` (Linux and Windows CI run every portable test target, so
it runs there with no workflow edit).

## 6. Frame machinery (`GX-G`, lanes 2 and 3)

- `Frame.paintScopes: [PaintScope]` (transition | effect | shadow) replaces
  `transitionScopes`; `TransitionGroup.paintGroup` pushes a transition scope
  as before. `Frame.effectScopesPushed` (work counter, reset per frame).
- `RenderEffect { alpha: Float; affine: Affine2D }`, `Affine2D` (internal,
  `a b c d tx ty` in `Double`, `concatenating`, `inverted`, `isUniformPositiveScaleTranslation`,
  `boundingBox(of:)`, `linearScale` = `sqrt|det|`).
- `CapturedPrimitive { kind: Kind; layer: Int; innerMask: Bool; transform: PrimitiveTransform? }`,
  `Kind = rect | glyph | image(ImageTexture) | surface(SurfaceTarget) | path(PathPaint) | shadow(ShadowPaint)`.
- Effect scope entry (non-flattening): `outerMask = activeClip`, the clip
  stack's top marked as a **local origin**; `activeClip` reads only clips
  pushed after the mark; exit restores. A clip pushed between two
  non-flattening marks maps through the outer scope's affine as its bounding
  box (divergence 109).
- Prepaint: `PrepaintPass.withRenderEffect(_:bounds:_:)` pushes the
  points-space affine; `insertHitbox` stores `HitboxTransform { inverse,
  outerClip }` when the stack is non-empty; `recordAccessibility` stores the
  bounding box.
- `Deferred` (presentation root and in-flow portal) pushes an empty effect
  stack around its content, as it resets clip and scroll offset.
- Text: `PaintPass.drawGlyphs(_:color:)` (internal) brackets the loop with
  `beginLeafGroup`/`endLeafGroup`; the five glyph loops (`Text`,
  `ProposalText`, `TextField`, `TextEditor` ×2) call it.

## 7. Demo, pixels, and what must not move

- **Looks demo**: `METALUI_LOOKS_DEMO=1` gains
  `looksPathsShadowsTransformsSection()` — its own function passed into the
  composing function (Windows' 1 MB stack, `everyProductionTreeBuildsOnAOneMegabyteThread`):
  a five-point star filled nonzero beside the same star even-odd; a zig-zag
  stroked width 6 with round caps and joins, and the same dashed `[12, 6]`; a
  card (surface background, rounded) with `.shadow(radius: 8, y: 4)` and a
  shadowed `Text`; a `Text("Rotated")` at 30° and an `Image` at −15°; a small
  path star under `scaleEffect(3)` (crisp) beside a `Text` under
  `scaleEffect(3)` (soft — divergence 106); a 60×60 square that rotates 45°
  more `withAnimation` on each tap (its hover and tap region follow it).
- **Human checks**: a new **group Q** in `docs/verification/human-checks.md`
  (Q1 fills, Q2 strokes and dashes, Q3 shadows light/dark, Q4 rotated text
  and image edges, Q5 crisp path vs soft text under scale, Q6 the rotating
  square's animation and that hover/taps follow the drawn diamond), each with
  what to run, what to see, the right answer and its headless pin.
- **Pixels**: no production tree uses a new API → **0 px against `dc96395`
  in all fourteen offscreen images** (`docs/probes/demo-pixels/compare.sh
  <scratch> dc96395 HEAD`), `Expected.swift` unedited.
- **Must not move**: id paths and state retention
  (`theSevenRetentionSlotsAreMutuallyDistinct`, `MC-A`/`MC-C`/`MC-P`,
  `.id()` outermost), hit testing, accessibility, animation, focus, `List`
  windowing and `TB-AH`, `Deferred`, text input — for every tree without an
  effect, a shadow or a path; `MetalUILayout` imports only `MetalUICore`,
  `MetalUIScene` only `MetalUIShaderTypes`, `MetalUIPath` nothing;
  `theLegacyEngineSymbolsAreAbsentFromTheTestProcess` green;
  `MemoryLayout<Handlers>.size` unmoved (no new member).

## 8. Lanes — three, strictly in order 1 → 2 → 3, all Opus

Every lane: red tests first (against a compiling skeleton), then the
implementation, then a mutation table — commit, mutate from a copy, run the
**whole unfiltered suite** (`swift test --build-system native --no-parallel`,
one summary line, the `FR-J` line present), `git status --short` after each
restore, name every reddened test; each new typecheck guard mutated red once.
**`swift package clean` before re-taking counts** after a public type
crossing a module boundary changes (lane 1: `MUIGlyph`, `Scene`,
`MUITransform`; lane 2: `LayoutModifier`, `Decoration`; lane 3: `ColorToken`, `Theme`, `ShapeGeometry`, `LayoutModifier`). Each
lane appends its readings as new `GX-` rulings (moving the "next unused"
line), adds its own divergence rows, `docs/api-overview.md` lines, doc
comments and inventory map rows (`zsh docs/probes/closeout-inventory-check.sh`
and `zsh docs/probes/closeout-undocumented.sh` print nothing; the census
re-recorded with `docs/probes/closeout-public-api.sh`). Tests that need a
Metal device follow their directory's existing skip convention.

### Lane 1 — the renderer transform and `MetalUIPath`

**Files**: `Sources/MetalUIRender/Shaders/{MetalUIShaderTypes.h,shaders.metal}`,
`Sources/MetalUIRender/Renderer.swift`, `Sources/MetalUIScene/Scene.swift`,
`Sources/MetalUIPrimitives/ShaderTypesBridge.swift`, new `Sources/MetalUIPath/*`,
`Package.swift`; every `_reserved:` glyph call site (§5.1);
`Backends/SDL/{Shaders/replay.hlsl,Shaders/compiled/*,scripts/compile-shaders.py,Sources/SDLBridge/*,Sources/MetalUISDL/SDLWindowRenderer.swift,Sources/ReplayFixture/ReplayFixture.swift,Sources/SDLReplay/SDLReplayer.swift}`;
`Experiments/SDLGPU/Sources/Replay/main.swift`;
`.github/workflows/sdl-gpu-linux.yml`. `shadercross`: the copy in the main
checkout's untracked `Experiments/SDLGPU/.tools/`, **copied into the
scratchpad, never run in place**.
**Notes** (`GX-R` item 4): every new C enum read from Swift is converted
explicitly (`UInt32(X.rawValue)`, the Windows `Int32` hazard); `SDLBridge.c`
raises each stage's `num_storage_buffers` for the transform table.
**Tests**: new `Tests/MetalUIRenderTests/TransformPrimitiveTests.swift`, arms in
`SceneTests.swift` and `ShaderABITests.swift`; new `Tests/MetalUIPathTests/`
(`RasterizerTests.swift`, `StrokerTests.swift`, `PathMathTests.swift`,
`BoxBlurTests.swift`); `Backends/SDL` arms (outside the root count).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `aRotatedRectCoversItsRotatedOutlineAndNotItsBounds` — 160×20 rect at the centre of 200×200, rotated 90° (record via `Scene.insert(…, transform:)`): (100, 40) covered, (40, 100) clear; the identity arm the opposite (`#require` the arms disagree) | no transform | M1a: vertex stage ignores the index |
| 1.2 | `anUntransformedSceneRendersBitIdenticallyToBefore` — a fixed scene (bordered rounded rect, ellipse band, glyph run, linear and nearest images, a rounded mask) rendered offscreen; its FNV-1a hash equals the literal recorded **on the unmodified renderer** in the lane's red commit | — (green on arrival; the pin) | M1b: the fringe applied to index-0 instances |
| 1.3 | `aTransformedEdgeIsAntialiasedAcrossTheFringe` — a rect rotated 30°: at least one pixel whose centre lies outside the rotated rect by < 0.5 px has 0 < coverage < 255 | — | M1c: no fringe expansion |
| 1.4 | `aScaledRectAntialiasesInScreenPixels` — under a uniform `scale(2)` (`GX-S` item 1: `scale(2, 0.5)` has `|det|` 1 and cannot see M1d) an edge through a pixel centre has exactly one row of partial pixels, a vertical one one column; a 2:1 arm bounds the band | — | M1d: `pixelScale` ignored |
| 1.5 | `theOuterMaskIsScreenSpaceAndTheContentMaskLocal` — a rotated 90° rect with a local `contentMask` covering its left half and an outer mask cutting the screen's top quarter: the four predicted pixels | — | M1e: outer mask unapplied; M1f: `contentMask` read at the screen position |
| 1.6 | `aRotatedGlyphSamplesItsSlotOnly` — a synthetic atlas: a 6×6 slot of coverage 0 hard against a neighbour whose touching column is 255 (`GX-S` item 10); the glyph ×4 and rotated 90°: no pixel reads the neighbour | — | M1g: no slot clamp |
| 1.7 | `aRotatedImageKeepsItsFilterAndAntialiasesItsEdges` — a 2×1 red/blue texture over 100×10 rotated 90°: top red, bottom blue; nearest → the boundary row exact; edges partial | — | M1h: image vertex ignores the index |
| 1.8 | `theFilterWordCarriesTheTransformAboveItsLowByte` — filter nearest with index 3: still nearest | — | M1i: `filter == Nearest` unmasked |
| 1.9 | `aShapeWordAboveItsLowByteKeepsItsShape` — `shape = 1 \| 2 << 8`: an ellipse | — | M1j: `shape == Ellipse` unmasked |
| 1.10 | `theTransformTableIsCarriedOnceAndIndexedFromOne` (`SceneTests`) — T, T, nil, U → table [T, U], indices 1, 1, 0, 2 in the packed words; `finalize()` twice keeps them; `clear()` empties | no table | M1k: no reuse (table of three) |
| 1.11 | `aTransformNeverBreaksARun` — two rects with different transforms → one rect run | — | M1l: finalize breaks on transform |
| 1.12 | `metalAndSwiftAgreeOnTheTransformStruct` (`ShaderABITests`) — `sizeof(MUITransform) == 64`, every field round-trips through a probe kernel; `MUIGlyph.transform` at `_reserved`'s old offset | — | M1m: the probe kernel swaps `tx`/`ty` (reddens only this) |
| 1.13 | `aFilledSquareCoversExactlyItsPixels` — 10×10 at integer coordinates: 100 pixels of 255, none else | no target | M1n: cover not accumulated (area only) |
| 1.14 | `aHalfPixelEdgeCoversHalf` — x = 0.5: the edge column 127…128 | — | M1o: coverage rounded to 0/1 |
| 1.15 | `nonZeroFillsASameDirectionRingAndEvenOddEmptiesIt` (PA2) | — | M1p: even-odd computed as nonzero |
| 1.16 | `aReversedRingIsAHoleUnderBothRules` (PA2) | — | M1q: nonzero as `|w| > 0` on the absolute area |
| 1.17 | `aQuadraticSegmentCoversItsArea` (PA4) — 3333.3 ± 0.5 % (SwiftUI 3325.8) | — | M1r: one segment per curve (5000) |
| 1.18 | `anEllipseCoversPiAB` — 100×60: 4712.4 ± 0.3 % (SwiftUI 4714.2, PA5) | — | M1s: 4-cubic constant wrong (0.5 for 0.5523) |
| 1.19 | `clockwiseFalseSweepsThroughBelowRight` (PA3) — pie (70, 70) covered, (70, 30) clear; `true` the opposite | — | M1t: sweep sign flipped |
| 1.20 | `capsEndWhereSwiftUIsDo` (ST1–ST3; ink = coverage ≥ 64 in 1.20–1.23, `GX-S` item 2) — butt x20…79, square x15…84 with its corner solid, round x14…85 (± 1) | — | M1u: square cap as butt |
| 1.21 | `joinsReachSwiftUIsTips` (ST5) — miter 7, bevel 18, round 15 (± 1) | — | M1v: miter drawn as bevel |
| 1.22 | `theMiterLimitFallsBackToABevel` (ST6) — limit 10 tip −4, limit 4 tip 9 (± 1) | — | M1w: limit ignored |
| 1.23 | `dashesWalkTheArcLengthFromThePhase` (ST7) — ST7's first two rows exactly, the third's starts and 10-unit ends exactly, its 2-unit ends ±1 (`GX-S` item 3) | — | M1x: phase ignored |
| 1.24 | `aClosedSubpathJoinsAtItsStartAndAnOpenOneCaps` (ST8) | — | M1y: closed subpaths capped |
| 1.25 | `aNonPositiveWidthStrokesNothing` (ST10) | — | M1z: `abs(width)` |
| 1.26 | `theRasterizerIsBitIdenticalEverywhere` — a fixed corpus (curves, arcs at 7 angles, the strokes above, an even-odd star, a blur) hashed to a literal recorded on macOS; runs on Linux and Windows CI | — | M1aa′: flattening tolerance 0.1 → 0.2 (`GX-R` item 2; a coefficient's last digit cannot move a byte) |
| 1.27 | `sinCosMatchesTheReferenceTable` — 24 angles (incl. ±π/2, ±π, 1e6) equal to `Double.bitPattern` literals recorded on macOS, exactly (`GX-R` item 2); odd/even symmetry exact | — | M1ab: range reduction off by a quadrant |
| 1.28 | `theBoxBlurApproximatesAGaussianOfSigmaRadius` — a 40×40 square, radius 10: the row at y 20 within ± 8 of SH3's; radius 4 within ± 6 of SH3b's | — | M1ac: sigma = radius / 2 |
| 1.29 | `onlyTheVisibleRectangleIsRasterized` — a 10 000-px path clipped to 100×100: `lastRasterizedPixels ≤ 10 000` | — | M1ad: clip ignored |
| 1.30 | `aRotatedRasterIsResampledBilinearlyByTheCompositor` — `AlphaCompositor` resampling a 2×2 checker under 90°: exact permutation; under 45° a centre value of the mean | — | M1ae: nearest in the bilinear path |
| S1.1 | (`Backends/SDL`) `aVersionThreeFixtureRoundTripsTransforms`; `thePrimitiveABIIsTheOneTheShadersRead` with the transform stride | v2 only | M1af: transforms not serialized |
| S1.2 | (`Backends/SDL`) `aTransformedFrameIsTheReplayPathsFrame` — `SDLWindowRenderer` offscreen equals the replay path on frame 7's scene | — | M1ag: transform buffer unbound in the bridge |
| P1 | **Parity** (no count): `Replay --portable --record` 8 frames pass; `PortableReplay --expect 8` and `DemoCapture` PASS on macOS; the two positive controls of §5.3 fail frame 7 (recorded) | — | the two controls |

### Lane 2 — render effects in `MetalUI`

**Files**: new `Sources/MetalUI/{Angle.swift,Affine2D.swift,RenderEffects.swift}`;
`Frame.swift` (paint-scope stack, clip split, `insertHitbox`,
`recordAccessibility`, the emitters), `Passes.swift`, `Transition.swift`,
`TransitionGroup.swift`, `TransitionStore.swift`, `Hitbox.swift`,
`NativeModifiedContent.swift` (three cases), `ModifiedContent.swift`
(per-layer prepaint/paint), `ProposalAnimation.swift`, `Box.swift`
(`Decoration.renderEffects`), `AnimatedColor.swift` (`paintDecoration`/
`registerAndScope` push the effects), `Deferred.swift`, `DragSession.swift`
(transform carried), `Window.swift` (caret bounding box; event points mapped
through the hit hitbox's inverse, `GX-P` item 3), and the handler wrappers
`NativeTappable.swift`, `GestureModifiers.swift`, `DragAndDrop.swift` and the
`AccessibilityModifier` (outward propagation, `GX-P` item 1).
**Tests**: new `Tests/MetalUITests/{RenderEffectTests,RenderEffectHitTests,RenderEffectAnimationTests}.swift`,
`RenderEffectCompileGuards.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 2.1 | `aRotationEffectChangesPaintAndNotLayout` (T1, T6b) — `HStack { a.rotationEffect(45°); b }`: `b`'s bounds unchanged; `a`'s rect carries a record rotating 45° about its centre | no API | M2a: the layer answers the rotated bounding box |
| 2.2 | `positiveDegreesRotateClockwiseAboutTheAnchor` (T2) — 90° at `.topLeading` maps local (100, 0) to (0, 100) from the anchor | — | M2b: sign flipped |
| 2.3 | `aUniformScaleAndAnOffsetAreFlattenedOnTheCPU` (T3, T6) — bounds mapped, `scene.transforms` empty | — | M2c: always a record |
| 2.4 | `aNonUniformNegativeOrRotatingEffectIsARecord` (T4, T5) | — | M2d: non-uniform flattened |
| 2.5 | `scaleEffectSizeEqualsXY` (T4b) and `offsetSizeEqualsXY` (T6c) | — | M2e: size form drops `height` |
| 2.6 | `aZeroScaleDrawsNothing` (T5b) | — | M2f: zero scale emitted |
| 2.7 | `effectsComposeInWrittenOrder` (T11) — rotation-then-offset and offset-then-rotation records differ by the predicted matrices, on both vocabularies | — | M2g: composition reversed |
| 2.8 | `aClipInsideAnEffectTurnsWithItAndOneOutsideStays` (T7, T7b) | — | M2h: the clip not split at entry |
| 2.9 | `aBackgroundAfterAProposalEffectIsNotTransformed` (T8) | — | M2i: the scope pushed around the whole chain |
| 2.10 | `aRotatedHitboxIsHitWhereItIsDrawn` (H1, H1b, H6) — a `Window` click at (100, 40) runs the tap, at (40, 100) does not | — | M2j: `insertHitbox` drops the transform |
| 2.11 | `aRotatedSquaresFrameCornerMissesAndItsTipHits` (H7) | — | M2k: hit test against the bounding box |
| 2.12 | `scaleAndOffsetMoveTheHitRegion` (H2–H4) | — | M2j |
| 2.13 | `aTransformedHitboxIsStillCutByTheOuterClip` | — | M2l: outer clip dropped from the hitbox |
| 2.14 | `hoverAndGestureArenasFollowTheTransform` — hover background and a `DragGesture` begin only inside the rotated shape | — | M2j |
| 2.15 | `theAccessibilityFrameIsTheTransformedBoundingBox` (X1, X2, X4, X5) | — | M2m: untransformed bounds published |
| 2.16 | `rotationScaleAndOffsetAnimateValueAndAnchor` (N1, N2, N3, N9) — `withAnimation`, `simulateTick` midpoint: angle, factors, offset and anchor midway | — | M2n: anchor snaps |
| 2.17 | `aLegacyEffectAnimatesOnTheStoreNotTheStateTable` — the table's reserved names unchanged, a store track keyed `$anim-effects` | — | M2o: legacy effects snap |
| 2.18 | `aGhostOfRotatedContentReplaysItsTransform` | — | M2p: `CapturedPrimitive` drops its transform |
| 2.19 | `aDragPreviewOfRotatedContentReplaysItsTransform` | — | M2p |
| 2.20 | `aDeferredInsideAnEffectIsNotTransformed` — presentation primitives index 0, hitboxes plain | — | M2q: `Deferred` keeps the stack |
| 2.21 | `aTreeWithoutEffectsPushesNoScope` — `demoContent()` through a `Window`: `effectScopesPushed == 0`, and its scene's `transforms` empty | — | M2r: a scope pushed for every element |
| 2.22 | `theLegacyVocabularyKeepsWrittenOrderAmongEffectsAndMovesNoID` — `Box().rotationEffect().offset()` vs `.offset().rotationEffect()`; ids equal to the effect-free tree's | — | M2s: the list sorted |
| 2.23 | `aLegacyEffectWrapsTheWholeElementWhateverTheOrder` (divergence 108 pin) | — | M2t: background excluded |
| 2.24 | `aClipBetweenTwoNestedRotationsIsItsScreenBoundingBox` (divergence 109 pin) | — | M2u: the middle clip dropped |
| 2.25 | `aProposalEffectIsOneIdentityLevel` — content numbered `positional(0)` under the layer (`MC-C`) | — | M2v: layer not counted |
| 2.26 | `aTransitionsCapturedBytesDoNotMove` — `.scale` and `.move` transitions' emitted primitives at activeness 0.5 equal literals recorded at `dc96395` | green (pin) | M2w′: the transition atom composes translation before scale (`GX-R` item 2; `sqrt(fl(s²)) == |s|`, so the old M2w could not redden) |
| 2.27 | `aTapWrittenAfterAnEffectHitsTheTransformedFrame` (H1b, `GX-P` item 1) — proposal `.rotationEffect(90°).onTapGesture` on the 160×20 bar: a `Window` click at (100, 40) runs it, (40, 100) does not; the same with `.gesture(TapGesture())` and `.dropDestination` | — | M2x: no outward propagation (the wrapper's hitbox stays axis-aligned) |
| 2.28 | `aHandlerOutsideAPaddingOverAnEffectHitsItsAxisAlignedFrame` (divergence 41 amended pin, `GX-P` item 2) | — | M2y: propagation through a rect-changing layer |
| 2.29 | `pointConsumersReadTheDeclarersLocalPoint` (`GX-P` item 3) — a `Slider` under `scaleEffect(x: 2, anchor: .leading)` pressed at its drawn 75 % reads 0.75; a `DragGesture` under a 90° rotation dragged +20 in window x reports translation (0, −20); a drop's action location under `offset(x: 40)` is destination-local | — | M2z: `Window` passes the raw window point |
| 2.30 | `anEffectInAScrolledScrollerTurnsAboutItsScrolledAnchor` (`GX-P` item 4) — paint record and hitbox both about the scrolled centre | — | M2aa: anchor omits `activeOffset` |
| 2.31 | `anAccessibilityRecordWrittenAfterAnEffectFollowsIt` — `.rotationEffect(90°).accessibilityLabel("x")` on the proposal path publishes the transformed bounding box | — | M2x |
| G2.1 | `theRenderEffectSpellingsCompileFromAPlainImport` (whole-file guard) | no API | MG2.1: one spelling made `internal` |

### Lane 3 — `Path`, styles, shadows, the demo, the documents

**Files**: new `Sources/MetalUI/{Path.swift,StrokeStyle.swift,Shadow.swift,RasterCache.swift}`;
`Shape.swift`, `Shapes.swift`, `ShapeView.swift`, `ClipShape.swift`,
`Theme.swift` (`.shadow`; `Theme.init`'s trailing defaulted `shadow:`, `GX-Q`), `Frame.swift` (`path`/`shadow` kinds,
rasterization at `insertIntoScene`, leaf groups), `Passes.swift`
(`drawGlyphs`), `Text.swift`, `ProposalText.swift`, `TextField.swift`,
`TextEditor.swift`, `NativeModifiedContent.swift` (`.shadow`),
`ModifiedContent.swift`, `ProposalAnimation.swift`, `Box.swift`,
`Sources/MetalUIDemoContent/LooksDemo.swift`;
`docs/verification/human-checks.md` (group Q), `docs/divergences.md`,
`docs/api-overview.md`, `docs/migration.md` (the three public breaks),
`docs/superpowers/specs/2026-09-28-shapes-and-rendering-design.md` §9,
`docs/probes/closeout-inventory-map.tsv` and the census.
**Tests**: new `Tests/MetalUITests/{PathTests,StrokeStyleTests,ShadowTests}.swift`,
`PathCompileGuards.swift`.

| # | test | red before | mutation |
|---|---|---|---|
| 3.1 | `aPathViewAnswersItsProposalAndDrawsAtItsOwnCoordinates` (PA1, PA1b) — one image at device (origin + (20, 30)), 50×40 × scale, not clipped to a 30×30 frame | no API | M3a: path scaled into the frame |
| 3.2 | `aBarePathFillsWithTheForegroundStyle` (PA8) | — | M3b: fixed colour |
| 3.3 | `pathInReceivesTheLocalRect` (PA9) — a recording shape at (17, 9) receives origin (0, 0) | — | M3c: window rect passed |
| 3.4 | `aShapeImplementingNeitherRequirementTrapsNamingGXD` (exit test, reads standard error) | — | M3d: reentrancy flag removed (recursion, no message) |
| 3.5 | `builtInShapesStillDrawOneSDFRect` — `Circle().fill`, `RoundedRectangle(8).stroke(.accent, lineWidth: 2)`: `MUIRect`s, no image | green (pin) | M3e: default `geometry(in:)` routed through the path |
| 3.6 | `aBuiltInShapesPathMatchesItsGeometry` — `path(in:).contains` = `geometry.contains` on a 1-pt grid | — | M3f: corner arcs from the wrong constant |
| 3.7 | `evenOddFillStyleEmptiesTheRing` (PA2 through `.fill(_:style:)`) | — | M3g: `FillStyle` dropped by `ShapeView` |
| 3.8 | `aJoinOrDashGoesThroughTheStrokerAndAPlainWidthKeepsTheBand` — round-joined `Rectangle().stroke` → one image; `stroke(lineWidth: 10)` → the band `MUIRect` | — | M3h: every stroke rasterized |
| 3.9 | `contentShapeOfAPathHitsByWinding` — triangle: inside hits, its bounding-box corner misses | — | M3i: path `contains` = bounding box |
| 3.10 | `clipShapeOfAPathTrapsNamingDivergence91` (exit test) | — | M3j: path clip treated as its box |
| 3.11 | `aPathUnderScaleEffectIsRasterizedAtTheScaledResolution` (T16) — a 1 pt diagonal under `scaleEffect(4)`: an untransformed image 40×40 × scale with solid pixels | — | M3k: raster at local resolution under a record |
| 3.12 | `aRotatedPathIsRasterizedInDeviceSpace` — image index 0, coverage rotated | — | M3k |
| 3.13 | `aRasterIsReusedAcrossFramesAndDroppedWhenUnused` — same `ImageTexture` identity on frame 2, `lastRasterizedPixels == 0`; gone after a frame without it | — | M3l: no cache |
| 3.14 | `theCacheKeyIncludesColourTransformAndClip` — changing each re-rasterizes or re-tints | — | M3m: each key field dropped in turn (four mutations) |
| 3.15 | `aShadowIsDrawnBelowEachLeaf` (SH5) — overlapping `ZStack`: emission order shadow(blue), blue, shadow(red), red | — | M3n: one composited shadow |
| 3.16 | `aTextCastsOneGlyphShapedShadowBelowItsGlyphs` (SH4, SH5e) — one shadow image before the run; nonzero texels < 40 % of its area | — | M3o: a shadow per glyph |
| 3.17 | `theShadowBlurMatchesSwiftUIsProfile` (SH3) — 40×40 square, radius 10: device row within ± 8 of SH3's | — | M3p: sigma = radius / 2 |
| 3.18 | `theDefaultShadowColourIsTheShadowToken` (SH2) — light theme: 171 ± 1 over white | — | M3q: default `.textPrimary` |
| 3.19 | `aShadowFollowsItsContentsAlpha` (SH6) | — | M3r: colour alpha ignored |
| 3.20 | `aShadowIsCutByAnOuterClipAndShapedByAnInnerOne` (SH7, SH7b) | — | M3s: silhouette ignores masks |
| 3.21 | `aShadowNeverHitsChangesNoLayoutAndPublishesNothing` (SH8, H5, X6) | — | M3t: shadow bounds registered as a hitbox |
| 3.22 | `aSecondShadowShadowsTheFirst` (SH11) | — | M3u: shadow images not leaves |
| 3.23 | `aShadowInsideARotationOrScaleHasItsOffsetTransformed` (T10, T14) | — | M3v: offset not mapped |
| 3.24 | `shadowColourRadiusAndOffsetAnimate` (N4–N6) | — | M3w: radius snaps |
| 3.25 | `aPathViewWhosePathChangesSnaps` (N7) | — | M3x: path interpolated |
| 3.26 | `aLegacyShadowReturnsSelfAndShadowsTheWholeElement` | — | M3y: legacy shadow ignored |
| 3.27 | `aMetalViewsShadowIsItsQuad` (divergence 104 pin) | — | M3z: surface skipped |
| 3.28 | `theLooksDemoShowsPathsShadowsAndTransforms` — `looksDemoContent()` through a fake window: ≥ 2 path images, ≥ 3 shadow images, ≥ 2 transform records, and the tap rotates the square (record angle 45° after `simulateTick` past the animation) | — | M3aa: section left out of the composer |
| G3.1 | `thePathAndShadowSpellingsCompileFromAPlainImport` (whole-file) | no API | MG3.1: `StrokeStyle.init` made `internal` |
| G3.2 | `anOutsideShapeCanWritePathInAlone` (whole-file) | no API | MG3.2: `path(in:)` removed from the protocol |
| G3.3 | `aThemeWrittenBeforeTheShadowTokenStillCompiles` (whole-file, `GX-Q`) — an outside `Theme(background:…scrim:)` with no `shadow:` | no token | MG3.3: the `shadow:` default removed |

## 9. Not built (owner none unless named)

| not built | why |
|---|---|
| `transformEffect`, `projectionEffect`, `rotation3DEffect` | `GX-A`: a public affine type and a projective primitive; the record is a full 2×3 affine, so `transformEffect` is API only |
| `Path.applying`, `transform:` parameters, `addRelativeArc`, `trimmedPath`/`Shape.trim`, `strokedPath`, SVG strings | additive later; `trim` animates in SwiftUI (N10) and needs an animatable shape protocol |
| `compositingGroup()`, `drawingGroup()` | an offscreen composite (SH5c) |
| inner shadows, `ShapeStyle` shadows, `.blur(radius:)` | not requested; `.blur` reuses `BoxBlur` later |
| an analytic GPU shadow for rect leaves | an optimization of `GX-J` |
| a shape's stroke width animating | divergence 97 amended (N8) |
| text and images re-rasterized at an effect's scale | divergence 106 (`GX-L`) |
| `clipShape` of a path or ellipse | divergence 91 |
| effects and `.shadow` on a `Component` | `GX-P` item 5: declare them on the members or a wrapping element |
| gradients, SF Symbols, colour glyphs | unchanged rows of the shapes spec §9 |

## 10. Expected counts and checks

Root suite ≈ **2124 + 30 (lane 1) + 31 + 1 guard (lane 2) + 28 + 3 guards
(lane 3) = 2213 + 4 guards → 2217 tests, 133 guards** (critic round: +5 lane-2 tests, `GX-P`; +1 lane-3 guard, `GX-Q`) (the lanes give the
exact figure), 0 goldens, `FR-J` line present, 0 `error:`, the one SwiftPM
`warning:` under native and 0 under `swift build --build-tests`. Lane 1's
`MetalUIPathTests` run on Linux and Windows CI as a fourth portable target.
Fourteen images 0 px against `dc96395`; `Expected.swift` unedited; the probe
re-run byte-identical to its header; `Backends/SDL`
(`PKG_CONFIG_PATH=$PWD/.accesskit`) builds and tests; `Replay --portable` 8
frames PASS, `PortableReplay --expect 8` and `DemoCapture` PASS; a
`swift:6.4-noble` container (OrbStack, started if stopped and stopped after)
builds and runs the portable suites; real-window capture only when the lock
probe allows. Divergences 104–109 added, 41/90/91/97 amended — live 70 → 76,
next label 110. The Record phase writes record §73, the dated sections of
records §04/§05, `CLAUDE.md`/`AGENTS.md`, `README.md` if it lists features,
and `docs/record/README.md`.
