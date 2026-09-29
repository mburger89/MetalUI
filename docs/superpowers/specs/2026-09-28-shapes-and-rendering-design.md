# Shapes and rendering — design (plan task 11, part 2)

Branch `feat/shapes-and-rendering` from `ff2ae92` (part 1's tip, record §59).
Rulings `TE-AC`…`TE-AQ`, appended to part 1's decisions doc,
[`../2026-09-28-text-semantics-decisions.md`](../2026-09-28-text-semantics-decisions.md)
(next unused **`TE-AV`**; lane 1's `TE-AR` amends §4, §6, §8 and §9 as landed, lane 2's `TE-AS` §4, §5 and §8, lane 3's `TE-AU` §4, §5, §8 and §10). Evidence: `docs/probes/swiftui-shapes-and-rendering.swift`
(**new**, revision 3; arm ids `S1`, `K8`, `I8`, `A3`, `O6` …; its header carries the
recorded output and the reading), and `docs/probes/swiftui-grid.swift` arm
`GL14` (grids track, **re-run** by the critic round 2026-09-29, compiled,
byte-identical to its header line). Record: `docs/record/60-shapes-and-rendering.md`.

**Status: DESIGNED, critic round applied (`TE-AQ`); lane 1 landed (`TE-AR`, record §60 §3); lane 2 landed (`TE-AS`, fix round `TE-AT`, record §60 §4); lane 3 landed (`TE-AU`, fix round, record §60 §5); Record phase close applied (record §60 §6) — LANDED, task 11 ticked.** Parts 1 and 2 together are plan task 11; this part is
the task's second and third sentences — "cover shapes, images, fills/strokes,
overlays and clipping where MetalUI exposes them. Keep renderer constraints
explicit when an exact effect is not supportable yet."

## 1. Baseline

`ff2ae92`, this worktree with its own `.build`: `swift build --build-system
native --build-tests` (0 `error:`, the one `warning:` SwiftPM's deprecation
notice), then unfiltered `swift test --build-system native --no-parallel` →
**`Test run with 1706 tests in 3 suites passed`**; the log carries `FR-J
no-argument frame: succeeded=`. 0 goldens, **105** typecheck guards, **65**
live divergences, next label **90**. Re-taken by this design session.

The probe needs no window (`ImageRenderer` at scale 1 and a recording
`Layout`); it ran with the screen **locked** (lock probe:
`CGSSessionScreenIsLocked = 1`, `displayAsleep main: 1`), compiled twice and
interpreted once, byte-identical, 77 lines. The critic round re-ran
revision 2 unchanged (byte-identical), added **O6** (revision 3: `O4`'s
white-on-white read re-taken over a red canvas, with a blue positive control)
and re-ran the whole the same three ways, byte-identical, 78 lines.

## 2. What the renderer draws today (`TE-AD`)

| primitive | fields | draws exactly |
|---|---|---|
| `MUIRect` (`rect_fragment`, `replay.hlsl` rect stage) | bounds; per-corner **circular** radii; per-edge border **inside** the bounds; background and border colour; a rounded-rect content mask; `order`; `_reserved` (unused, always 0) | rectangles, rounded rectangles with circular corners, capsules and circles (radius = half the shorter side), their fills, and a border inside the edge |
| `MUIGlyph` (`glyph_fragment`) | bounds, atlas bounds (R8), mask, tint | a tinted coverage sprite, 1:1 |

**Not drawable today**: an ellipse; SwiftUI's continuous corners; elliptical
corners (`cornerSize:`); an arbitrary `Path`; gradients; dashes and line
caps/joins other than what a rounded rect implies; any texture but the R8
glyph atlas; an ellipse-shaped clip; the intersection of two rounded clips
that cross (`Frame.intersect`'s documented square-box fallback, `CL-A`).

**This part adds two capabilities, on both renderers** (lane 1): an **ellipse
shape kind** on `MUIRect` (the unused `_reserved` word becomes `shape`, so the
struct's 128-byte stride, the replay packing and every existing scene's bytes
are unchanged), and an **image primitive**, `MUIImage`, sampling an RGBA8
texture carried by the `Scene`. Everything else in the list stays a
**documented renderer constraint** (§9).

## 3. Scope — the collection (`TE-AC`)

| item | source | disposition |
|---|---|---|
| shapes (`Shape`, `Rectangle`'s relation, `RoundedRectangle`, `Circle`, `Capsule`, `Ellipse`) | plan text | **built**, `TE-AG`, `TE-AH`; divergence **90** added (continuous corners drawn circular) |
| fills and strokes (`.fill`, `.stroke(_:lineWidth:)`, `.strokeBorder`) | plan text | **built**, `TE-AI` |
| `foregroundStyle` reaching a shape's fill (C9) | `TE-O` | **built**, `TE-AH` (F1, F2) |
| clipping (`.clipShape`, `.clipped()`, `.cornerRadius`) | plan text | **built** on the proposal path and legacy `.clipShape`, `TE-AJ`; divergences **91** (an ellipse clip traps) and **92** (crossing rounded clips) added |
| `.cornerRadius` clipping, divergence 47 (`OM-G`) | `TE-O` | **kept** on the legacy `StyledElement.cornerRadius`, owner none, `TE-AJ`; the proposal path's new `.cornerRadius` clips (C1, C4) |
| overlays/backgrounds with shapes | plan text | **audited** (`.overlay`/`.background(alignment:content:)` unchanged), `.background(_:in:)`/`.background(in:)` added, `TE-AK` |
| images | plan text | **built**: `Image(decorative:scale:)`, `.resizable()`, `.interpolation(_:)`, fit/fill, a texture path on Metal and SDL, `TE-AF`, `TE-AL`; divergence **93** added (`.high` drawn bilinear) |
| `aspectRatio(contentMode:)` with no ratio, `scaledToFit`/`scaledToFill` | images (I3–I7) | **built** in the kernel, `TE-AM` |
| `UnitPoint` in `gridCellAnchor` (`GR-O` 4, divergence 64) | `TE-O` | **built**; divergence **64 retires**, `TE-AN` |
| `appearance`/`colorScheme`, a pre-paint theme (`EV-G`) | `TE-O` | **not built**, a documented absence, owner none, `TE-AO` |
| colour glyphs (record §05) | `TE-O` | **kept**, record §05's row stays a renderer constraint, owner none, `TE-AO` |
| SF Symbols, `Path`, gradients, `StrokeStyle`, a labelled `Image` | task text / SwiftUI surface | constraints and owners, §9 |

Live divergence count **65 → 68** (four added, one retired).

## 4. Public API (`MetalUI` unless named)

Every spelling is SwiftUI's; each departure is named. Colours are `ColorToken`s
(spec §7.9, as part 1's `foregroundStyle`); there is no `ShapeStyle`.

```swift
// Shapes (lane 2)
public protocol Shape: ProposalElement, Sendable {       // TE-AQ item 1
    /// SwiftUI's `path(in:)`, narrowed to what the renderer draws (TE-AG).
    func geometry(in rect: Bounds<Pixels>) -> ShapeGeometry
    /// SwiftUI's `sizeThatFits(_:)`. Default: the proposal, nil → 10 (S1).
    /// `nonisolated`: the kernel's leaf measure is a @Sendable closure (TE-AS item 1).
    nonisolated func sizeThatFits(_ proposal: ProposedSize) -> SizeD
}
// `extension Shape` supplies requestProposalLayout / prepaint / paint (the
// bare fill, TE-AH) with concrete LayoutState (`ShapeLayout`, public;
// `Rectangle.Layout` is a typealias of it, TE-AS item 2) and PrepaintState, so an outside
// conformer writes geometry(in:) alone and sits in an HStack (G2.1).
// Every built-in below is also Hashable (TE-AQ item 3).
public struct ShapeGeometry: Sendable, Equatable {
    public static func roundedRectangle(_ rect: Bounds<Pixels>, cornerRadii: Corners<Pixels>,
                                        style: RoundedCornerStyle = .continuous) -> ShapeGeometry
    public static func ellipse(_ rect: Bounds<Pixels>) -> ShapeGeometry
}
public enum RoundedCornerStyle: Sendable, Hashable { case circular, continuous }
public struct Rectangle: Shape, Hashable   // existing type, now a Shape (TE-AH)
    // public var color: ColorToken  →  ColorToken?  (nil = the foreground
    // style; a public break, ruled with its migration, TE-AQ item 2)
public struct RoundedRectangle: Shape { public init(cornerRadius: Pixels, style: RoundedCornerStyle = .continuous) }
public struct Circle: Shape { public init() }
public struct Capsule: Shape { public init(style: RoundedCornerStyle = .continuous) }
public struct Ellipse: Shape { public init() }
extension Shape {
    public func fill() -> ShapeView<Self>                       // the foreground style
    public func fill(_ token: ColorToken) -> ShapeView<Self>
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self>
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<Self>
}
public struct ShapeView<S: Shape>: Element {                   // SwiftUI's `_ShapeView`
    public func fill(_ token: ColorToken) -> ShapeView<S>       // layers paint in order (F4)
    public func stroke(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S>
    public func strokeBorder(_ token: ColorToken, lineWidth: Pixels = Pixels(1)) -> ShapeView<S>
}
extension Rectangle {
    @available(*, deprecated, message: "use Rectangle().fill(_:)")
    public init(color: ColorToken)                              // TE-AH
    // init(width:height:color:) unchanged, undeprecated
}

// Clipping and backgrounds (lane 2)
extension ProposalElementGroup {
    public func clipShape<S: Shape>(_ shape: S) -> ModifiedContent<ProposalBase, LayoutModifier>
    public func clipped() -> ModifiedContent<ProposalBase, LayoutModifier>          // = clip()
    public func cornerRadius(_ radius: Pixels) -> ModifiedContent<ProposalBase, LayoutModifier>
        // = clipShape(RoundedRectangle(cornerRadius: radius)), C4
}
extension StyledElement {
    public func clipShape<S: Shape & Hashable>(_ shape: S) -> Self      // a Decoration clip, like clipped();
        // `& Hashable` because `Decoration` is Hashable (TE-AQ item 3)
}
extension ElementGroup {
    public func background<S: Shape>(_ token: ColorToken, in shape: S) -> …  // = background { shape.fill(token) }, O2
    public func background<S: Shape>(in shape: S) -> …                        // token .background, O4
}

// Images (lane 3)
public struct ImageBitmap: Sendable {                           // not SwiftUI's; CGImage's stand-in
    public init(width: Int, height: Int, rgba: [UInt8])         // straight alpha, sRGB; premultiplied here
    #if canImport(ImageIO)
    public init?(contentsOfFile path: String)                   // macOS only (TE-AL)
    #endif
    public var width: Int { get }
    public var height: Int { get }
}
public struct Image: ProposalElement {                      // TE-AU item 1
    public init(decorative bitmap: ImageBitmap, scale: Float)   // SwiftUI's Image(decorative:scale:orientation:);
        // Float is Frame.scaleFactor's type; no orientation: (TE-AQ item 9);
        // a scale that is not finite and positive traps (SA-J, TE-AU item 2)
    public func resizable() -> Image
    public func interpolation(_ interpolation: Interpolation) -> Image
    public enum Interpolation: Sendable, Hashable { case none, low, medium, high }
}
extension ProposalElementGroup {
    public func aspectRatio(_ ratio: Double? = nil,
                            contentMode: AspectRatioContentMode = .fit) -> ModifiedContent<ProposalBase, LayoutModifier>
    public func scaledToFit() -> ModifiedContent<ProposalBase, LayoutModifier>
    public func scaledToFill() -> ModifiedContent<ProposalBase, LayoutModifier>
}
public typealias ContentMode = AspectRatioContentMode           // SwiftUI's name
extension ProposalElementGroup {   // on GridCellModifier's receivers, as gridCellAnchor is today
    @_disfavoredOverload
    public func gridCellAnchor(_ anchor: UnitPoint) -> GridCellModifier<Self>   // TE-AN
}
// MetalUILayout (TE-AU item 4): the kernel's anchor is a factor pair —
public struct ProposalAnchor: Sendable, Hashable {
    public var horizontalFactor: Double; public var verticalFactor: Double
    public init(horizontalFactor: Double, verticalFactor: Double)
    public init(_ alignment: ProposalAlignment)
}
// LayoutTree/LayoutPass.markNativeGridCell(_:columns:anchor:anchorPoint:columnAlignment:unsizedAxes:)
// gains `anchorPoint: ProposalAnchor? = nil` (a non-finite factor traps, SA-J);
// GridCellAttribute gains `case anchorPoint(UnitPoint)`.

// Paint API (lane 1), for custom elements
extension PaintPass {
    public func fill(_ bounds: Bounds<Pixels>, color: Hsla, cornerRadii: …, borderColor: …,
                     borderWidths: …, shape: PrimitiveShape = .roundedRectangle)
    public func drawImage(_ texture: ImageTexture, in bounds: Bounds<Pixels>,
                          filter: ImageFilter = .linear)
}
```

**Vocabulary.** A `Shape`, a `ShapeView` and `Image` are proposal leaves:
each conforms to `ProposalElement` exactly as `Rectangle` does today
(`ProposalElementGroup.swift`'s `extension Rectangle: ProposalElement {}`), so
they sit in `HStack`/`Grid` and, like `Rectangle`, in legacy containers. A
legacy `Box` is not a `ProposalElementGroup`, so `Box().clipShape(_:)` reaches
only the `StyledElement` overload; 2.16 and 2.18 each assert which overload
their receiver reaches.

`MetalUIScene` (lane 1): `PrimitiveKind.image`; `Scene.images: [MUIImage]`,
`Scene.textures: [ImageTexture]`, `Scene.insert(_ image: MUIImage, texture:
ImageTexture, layer:)`; `public final class ImageTexture: Sendable` (width,
height, premultiplied RGBA8 pixels; immutable). `MetalUIShaderTypes.h`:
`MUIRect.shape` (was `_reserved`), `MUIShapeRoundedRect = 0`,
`MUIShapeEllipse = 1`; `MUIImage { bounds; contentMask; maskCornerRadii;
float opacity; MUIUInt texture; MUIUInt filter; MUIUInt order; }` (64 bytes,
four `float4` lanes — **no `_reserved`**: with it the list summed to 68,
`TE-AR` item 1). `ImageTexture` has `init(width:height:premultipliedRGBA:)`
and `init(width:height:straightRGBA:)`, which premultiplies (`TE-AR` item 2).

## 5. What each thing does

**Shape sizing and placement** (S1, S2, S4–S6): every built-in answers its
proposal, a nil axis 10; **`Circle` answers the square of the smaller proposed
side** (a nil axis takes the other's value; nil×nil → 10×10; ∞×∞ → ∞×∞) and
draws **centred** in its frame. `RoundedRectangle`'s radius clamps to half the
shorter side and a negative one is 0 — clamped in
`ShapeGeometry.roundedRectangle`, so an outside shape's radii are too (`TE-AS`
item 3); `Capsule`'s radius is half the shorter side. A shape registers no hitbox, no focus entry and no accessibility record
(as `Rectangle` today), and snaps under animation (proposal path).

**Geometry → primitive** (one function, `Shape.swift`): a rounded rectangle
is one `MUIRect` (shape 0) with its radii; an ellipse is one `MUIRect`
(shape 1). `.continuous` is drawn as `.circular` (**divergence 90**, S3: 196 px
at r = 20 in 100×60).

**Fill and stroke** (F1–F5, K1–K12): a bare shape fills with
`foregroundStyle ?? .textPrimary`, part 1's resolution; `.fill` wins.
`Rectangle.color` becomes `ColorToken?`: `Rectangle()` stores `nil` (the
foreground style), `Rectangle(width:height:color:)` keeps its `.surface`
default and stores it, and a `ShapeView`'s layers paint their own colours,
never the shape's stored one (`TE-AQ` item 2). A
`ShapeView`'s layers paint in declaration order, so `.fill(a).stroke(b)`
strokes over the fill. **`strokeBorder(w)`** is one `MUIRect` over the shape's
own bounds with border `w`, transparent background, outer radius `r` when
`r ≥ w/2` else **0** (K11: square outer corner), inner radius `max(r − w, 0)`
(the shader's existing rule). **`stroke(w)`** is `strokeBorder(w)` over the
bounds outset by `w/2` with radius `r > 0 ? r + w/2 : 0` (K1, K6, K7, K12).
A width ≤ 0 draws nothing (K9); a border wider than half fills (K10, a
rectangle's pinned by pixels in 2.13b, `TE-AT` item 1); strokes
change no layout (K5); the default width is 1 (K3). **An ellipse's
`strokeBorder(w)`** is SwiftUI's inset-ellipse stroke — the band of half-width
`w/2` around the ellipse inset by `w/2` (K8: **not** a concentric ellipse,
518 px apart) — so the ellipse kind takes one width (`borderWidths.top`) and
the fragment computes an **exact** ellipse distance (§6).

**Clipping** (C0–C8): `.clipShape(s)` pushes the clip `s.geometry(in: bounds)`
names — a rounded-rect geometry's rect and radii — in prepaint and paint, as
`.clip(cornerRadius:)` does (so a hitbox inside is clipped to the geometry's
**bounding rect**, square — `insertHitbox` intersects with `activeClip` alone
— as today's `.clipped()` and `.clip(cornerRadius:)` do; this is MetalUI's
existing rule, `OM-AJ`/divergence 43's family, not a SwiftUI claim: SwiftUI's
hit behaviour under `clipShape` is unmeasured here, owner **plan task 12**,
`TE-AQ` item 4); an **ellipse geometry traps** naming divergence 91.
`.clipped()` is `.clip()`; the proposal `.cornerRadius(r)` is
`.clipShape(RoundedRectangle(cornerRadius: r))` (C4). `clipShape` changes no
layout (C8). The legacy `StyledElement.clipShape(s)` stores the shape on the
`Decoration` (a package `Hashable` box over `any Shape & Hashable`, `TE-AQ`
item 3; the field **snaps** under animation, joining the paint-only
`Decoration` fields; it wins over `clipsContent` when both are set, `TE-AS`
item 4) and clips through `registerAndScope`/`paintDecoration`'s
existing clip halves; **the legacy `.cornerRadius(r)` stays paint-only** (divergence 47
kept, `TE-AJ`). `Frame.intersect(_:radii:_:radii:)` gains one exact case
before its square fallback: **an inner rounded rect contained in the outer
rounded rect keeps its own radii** (a 1e-4 pt tolerance at tangency,
`TE-AS` item 5 — defensive and unpinned, `TE-AT` item 2) — tested exactly as "each inner corner disc
lies inside the outer shape" (`rect_sdf(outer, cᵢ) ≤ −rᵢ` for the four inner
corner centres; both shapes are convex hulls of their corner discs), and the
mirror case; it runs **after** the two existing cases, whose answers do not
move — including case 2's documented inexactness (containment tested against
`outer`'s bounding box, `Frame.swift`'s own doc comment), which is kept, not
replaced by the exact test (`TE-AQ` item 12). C6 then reads SwiftUI's answer.
Two rounded clips that **cross** still intersect as the square box
(**divergence 92**).

**Overlays and backgrounds** (O1–O5): unchanged; `.background { shape }` and
`.overlay { shape }` already offer the shape the content's size and change no
layout. `.background(t, in: s)` is `.background { s.fill(t) }` (O2, 0 px);
`.background(in: s)` fills token `.background` (O6: SwiftUI's default style
**paints** — white over a red canvas under `ImageRenderer`'s light appearance —
so MetalUI fills its own canvas token, the analogue under §7.9's tokens; O4's
"ink none" was white on white, `TE-AQ` item 5).

**Images** (I1–I12): `Image(decorative:scale:)` answers `pixels ÷ scale` at
every proposal until `.resizable()`, which answers the proposal (nil → its
point size). It paints one `MUIImage` over its bounds, filter `.nearest` for
`.none`, `.linear` for `.low`/`.medium`/`.high` and the default (I8, I11;
`.high` is **divergence 93**, 880 px). A `.fill` image overflows its frame
unless `.clipped()` (I10). `ImageBitmap(width:height:rgba:)` takes straight
alpha and premultiplies (I12: half-alpha red over white reads (255,127,127));
a byte count other than `width × height × 4`, or a zero side, traps.
`contentsOfFile:` decodes through ImageIO on macOS; off Apple it does not
exist (§9). The image publishes no accessibility record (decorative, as its
name says).

**`aspectRatio(nil)`** (A1–A4, I3–I7): the kernel measures the child at
nil×nil and uses `width / height` as the ratio; a zero or non-finite ideal
ratio passes the proposal through (the AR2 branch). A fixed child keeps its
size. `scaledToFit()`/`scaledToFill()` are `aspectRatio(nil, contentMode:)`.

**`gridCellAnchor(UnitPoint)`** (GL14): the kernel's cell anchor becomes a
factor pair (`ProposalAnchor`, `TE-AU` item 4); the nine `ProposalAlignment`
spellings map to their factors and still resolve by leading dot (the new
overload is `@_disfavoredOverload`, `DD-P` item 4's ambiguity). A non-finite
component traps (`SA-J`, `TE-AU` item 2); one outside `0…1` is accepted.

## 6. The renderer (lane 1)

- **Ellipse kind.** `rect_fragment`/`replay.hlsl`: `shape == 1` computes the
  exact signed distance to the ellipse with semi-axes `h` (fill) and the band
  `|d(p, h − w/2)| − w/2` (border `w`), a circle branch when the axes are
  equal within 1e-4, the same algorithm and constants in MSL and HLSL: the
  **trig-free fixed-iteration** closest-point method (Chatfield's "simple
  method": three iterations over a unit direction, `sqrt`, `*`, `+`, `/`
  only) — **not** Quílez's analytic cubic nor a Newton on the angle, whose
  `acos`/`cbrt`/`pow`/`sin`/`cos` Vulkan and D3D leave at loose precision, a
  parity risk at the ≤ 1 tolerance outside images (`TE-AQ` item 6). Coverage on the same
  half-pixel threshold as the rect edge; background inside the band's inner
  edge, border in the band, then the mask. `cornerRadii` is ignored.
- **Image primitive.** Metal: `image_vertex`/`image_fragment`, sampler
  `coord::pixel`-free normalised UVs over the whole texture, `clamp_to_edge`,
  `filter::linear`; `filter == 1` reads the texel under the pixel
  (`texture.read`), the HLSL twin `Texture2D.Load` — no second sampler
  binding. Premultiplied output × `opacity` × mask, `(one,
  oneMinusSourceAlpha)`, pixel format `bgra8Unorm` (never `_sRGB`).
- **Textures ride in the `Scene`**: `WindowRenderer.finishFrame(scene:atlas:)`
  keeps its signature (`RS-A`). Each renderer caches one GPU texture per
  `ImageTexture` **identity** (`ObjectIdentifier`, the cache holding the object
  strongly so the identifier cannot be reused), uploads on first sight, and
  **releases every cached texture the frame's scene does not reference**.
- **Runs**: `Scene.finalize()` merges three arrays by `(layer, order,
  sequence)`; an image run also breaks where the texture changes, so **the
  number of runs is still the draw-call count**. `isEmpty` reads all three.
- **SDL**: `replay.hlsl` gains `IMAGE_STAGE`; `compile-shaders.py` compiles
  three kinds (six stages) and rewrites `SOURCE.sha256`; `SDLBridge.c`/`.h`
  gain the image pipeline and texture create/destroy/bind; `SDLWindowRenderer`
  maps `.image` (the current `kind == .glyph ? 1 : 0` would draw an image run
  as rects — replaced by an exhaustive switch) and keeps the cache.
  `shadercross` is the one the existing script names (SDL3_shadercross 3.0.0;
  a copy is in the main checkout's untracked `Experiments/SDLGPU/.tools/`,
  **copy it into the scratchpad, never run it in place**).
- **Parity**: `ReplayFixture` version **2** carries image records and their
  textures (width, height, bytes) after the glyph bytes; `Experiments/SDLGPU`'s
  `Replay` records a **frame 6** — an ellipse fill, an ellipse band, a stroked
  circle, a capsule, a linear and a nearest image, a half-alpha image, and an
  image under a rounded mask — through the Metal renderer and checks SDL Metal
  parity live; `.github/workflows/sdl-gpu-linux.yml`'s two `--expect 6` become
  `--expect 7`. Frame 6's reference is the Metal renderer; Linux (llvmpipe)
  and Windows (D3D12) re-confirm on push within `ParityTolerance` — **images
  are judged at the glyph tolerance (≤ 8)** inside image quads for the same
  sub-texel-precision reason, a mask built like `glyphMask()`
  (`ReplayFixture.spriteMask()`, glyph and image quads); outside them ≤ 1.
  The live comparison keeps frames 0–5 at one step everywhere and judges frame
  6 by that parity (`TE-AR` item 8).

## 7. Demo, pixels, and what must not move

No demo tree uses a new API (the preview's `Rectangle(width:height:color:)`
keeps its explicit colour; no demo code calls `Rectangle()` or
`Rectangle(color:)`), so the **fourteen offscreen images read 0 px against
`ff2ae92`**, `DemoFrameDeterminismTests`' `Expected.swift` is **unedited** (the
`MUIRect` rename keeps every byte: `shape` is 0 where `_reserved` was), and
`everyProductionTreeBuildsOnAOneMegabyteThread` stays green. Must not move:
state retention (no id path changes — a `Shape`, `ShapeView` and `Image` are
leaves like `Rectangle`; `clipShape` is one `LayoutModifier` layer exactly as
`.clip` is, and one `Decoration` field on the legacy path, returning `Self`),
hit testing (a clip clips hitboxes exactly as `.clipped()` does today; no new
hitbox), accessibility, animation, focus, the scrim, `List`, `Deferred`,
`TextField`/`TextEditor`. `MetalUILayout` still imports only `MetalUICore`;
`MetalUIScene` only `MetalUIShaderTypes`; `theLegacyEngineSymbolsAreAbsentFromTheTestProcess`
green. The real-window capture follows the lock probe; locked at design time,
so it is owed, as for tasks 8–11 part 1.

## 8. Lanes

Three lanes, run in order **1, 2, 3**. Shared source files, safe only because
the lanes run one at a time: `Frame.swift` (lane 1's emission, lane 2's
`intersect`, lane 3's aspect-ratio registrar), `Passes.swift` (lanes 1, 3),
`NativeModifiedContent.swift` and `ModifiedContent.swift` (lanes 2, 3).
Every other file is one lane's. Each lane commits its red tests first (against a
compiling skeleton where a new API is needed), then the implementation, then a
mutation table: commit, mutate from a copy, run the **whole unfiltered suite**,
`git status --short` after each restore, name every reddened test. Each new
typecheck guard is mutated red once. **`swift package clean` before re-taking
counts** after a lane changes a public type crossing a module boundary — lane
1's `MUIRect` field rename, `MUIImage`, `Scene`'s stored arrays and
`PrimitiveKind`'s case; lane 2's `Decoration` field and `LayoutModifier` case;
lane 3's `NativeNode.aspectRatio` payload and the grid anchor storage. Each lane
appends its readings to `TE-` as a new lettered ruling (moving the "next
unused" line) and its section to record §60.

### Lane 1 — the renderer: an ellipse kind and an image primitive, on Metal and SDL

**Files**: `Sources/MetalUIRender/Shaders/{MetalUIShaderTypes.h,shaders.metal}`,
`Sources/MetalUIRender/Renderer.swift`, `Sources/MetalUIScene/Scene.swift`,
new `Sources/MetalUIScene/ImageTexture.swift`,
`Sources/MetalUIPrimitives/ShaderTypesBridge.swift`, `Frame.swift`'s `fill`
and new `drawImage`, `Passes.swift`'s `PaintPass.fill`/`drawImage`;
`Backends/SDL/{Shaders/replay.hlsl,Shaders/compiled/*,scripts/compile-shaders.py,Sources/SDLBridge/*,Sources/MetalUISDL/SDLWindowRenderer.swift,Sources/ReplayFixture/ReplayFixture.swift,Sources/SDLReplay/SDLReplayer.swift}`;
`Experiments/SDLGPU/Sources/Replay/main.swift`;
`.github/workflows/sdl-gpu-linux.yml` (`--expect 7`).
**The rename re-spells every `MUIRect(…, _reserved: 0)` memberwise call**
(`TE-AQ` item 7; `git grep -n _reserved` at `ff2ae92`, rect sites only — the
glyph's `_reserved` stays): `ShaderTypesBridge.swift`, `Tests/MetalUIRenderTests/{ClipTests,DrawListTests,RendererTests,SceneFinalizeIdentityTests,ShaderABITests,ShaderTypesTests}.swift`,
`Backends/SDL/Tests/MetalUISDLTests/SDLWindowRendererTests.swift`,
`Experiments/SDLGPU/Sources/Replay/main.swift` — and, found at the build,
`Tests/MetalUIPortableTextTests/{EmitLinesTests,EmitParameterTests}.swift`
(`TE-AR` item 9) — a spelling, no test's answer moves, no T row; the lane greps
`_reserved` after and lists what is left (glyph fields only).
**Tests**: new `Tests/MetalUIRenderTests/{EllipsePrimitiveTests,ImagePrimitiveTests}.swift`,
arms in `SceneTests.swift`, `DrawListTests.swift`, `ShaderABITests.swift`;
new `Tests/MetalUITests/PaintPrimitiveTests.swift`; in `Backends/SDL`
(outside the root count) `ReplayFixtureTests` and `SDLWindowRendererTests` arms.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 1.1 | `anEllipseFillsItsInscribedEllipseAndNotTheCapsule` — 100×60, shape 1: centre filled, (1,1) empty, and pixel (10,10) — inside the radius-30 capsule of the same bounds, outside the ellipse — empty; the capsule arm (shape 0, radii 30) fills (10,10) (`#require` the arms disagree) | `shape` read by nothing | M1a: `rect_fragment` ignores `shape` |
| 1.2 | `anEllipseBorderIsTheStrokeOfTheInsetEllipse` — **120×40, border 16** (at K8's 100×60, border 10 the two models' pixel-centre classifications are at most 0.11 px apart, `TE-AR` item 3): the test computes, on the CPU, a pixel where the inset-band model and the concentric-hole model (K8) disagree by more than 0.9 px (`#require` one exists) and asserts the rendered pixel follows the inset band; the centre is background | — | M1b: band computed as the concentric ellipse `h − w` |
| 1.3 | `aSceneHoldingOnlyAnImageIsNotEmpty` | `isEmpty` reads two arrays | M1c: `images` dropped from `isEmpty` |
| 1.4 | `imageRunsBreakWhereTheTextureChanges` — images A, A, B then a rect, one layer → runs `[image 2, image 1, rect 1]`; `finalize()` twice gives the same list | no image kind | M1d: runs merged across textures |
| 1.5 | `anImageSamplesBilinearlyWithClampedEdges` — a 2×1 red/blue texture over 100×10: the twelve x's of I8's default row within ±2 per channel ((0…24) red, 25 ≈ (252,0,3), 49 ≈ (130,0,125), (75…99) blue) | no image pipeline | M1e: `filter::nearest` in `image_fragment` |
| 1.6 | `aNearestImageReadsTheTexelUnderEachPixel` — same texture, filter 1: I8 `.none`'s row exactly (49 red, 50 blue) | — | M1f: `filter` ignored |
| 1.7 | `aTranslucentImageCompositesPremultipliedSourceOver` — straight (200,100,50,128) over white → (227,177,152) ±1, derived before the run; `ImageTexture` stores (100,50,25,128) | — | M1g: no premultiply in `ImageTexture` (reads (255,227,177)) |
| 1.8 | `anImageUnderARoundedMaskIsClippedByIt` — mask radius 20: corner pixel is the clear colour, centre is the image | — | M1h: `image_fragment` skips the mask |
| 1.9 | `aTextureTheSceneNoLongerReferencesIsReleased` — frame A then frame B: the renderer's cache (internal count and identities) holds only B; frame A again uploads once more | — | M1i: never evict |
| 1.10 | `metalAndSwiftAgreeOnTheImageStructAndTheShapeField` — `image_abi_probe` (its own kernel, `TE-AR` item 4) reports `sizeof(MUIImage) == 64`, every field round-trips, and `MUIRect.shape` at `_reserved`'s old offset | — | M1j: `abi_probe` reads `order` for `shape` (the field swap reddens only this test) |
| 1.11 | `drawImageEmitsOneImageAtTheActiveOffsetClipOpacityAndLayer` — `PaintPass.drawImage` inside a scrolled clip at opacity 0.5 → one `MUIImage` with those fields, its texture in `scene.textures` once for two draws | no API | M1k: `activeOpacity` not applied |
| 1.12 | `fillCarriesTheEllipseShapeKind` — `PaintPass.fill(…, shape: .ellipse)` → `MUIRect.shape == 1`; the default is 0 | — | M1l: `Frame.fill` drops `shape` |
| S1.1 | (`Backends/SDL`) `aVersionTwoFixtureRoundTripsImagesAndTextures` and `thePrimitiveABIIsTheOneTheShadersRead` extended with the image stride | v1 only | M1m: textures not serialized |
| S1.2 | (`Backends/SDL`) `anImageFrameIsTheReplayPathsFrame` — `SDLWindowRenderer` offscreen equals the replay path on a scene with an ellipse, two images and a mask; `imageTexturesPersistAndAreReleasedWhenAbsent` | — | M1n: `.image` runs mapped to rects (the old ternary) |
| P1 | **Parity** (not a test count): `swift run Replay --portable --record <dir>` in `Experiments/SDLGPU` passes with 7 frames; `PortableReplay <dir> --expect 7` and `DemoCapture` PASS on macOS; positive control: the HLSL image stage forced to nearest, and separately the HLSL ellipse branch dropped, each fail frame 6's parity (recorded) | — | the two controls |

### Lane 2 — `Shape`, the built-ins, fill and stroke, clipping, backgrounds in a shape

**Files**: new `Sources/MetalUI/{Shape,Shapes,ShapeView,ClipShape}.swift`;
`NativeElements.swift` (`Rectangle`); `NativeModifiedContent.swift`
(`LayoutModifier.clipShape`); `ModifiedContent.swift` (its prepaint/paint
arms); `Box.swift`, `DecorationScope.swift`, `AnimatedColor.swift` (the legacy
`Decoration` clip shape; and `Box.swift:1339`'s doc comment, which still
says the bare `cornerRadius` gap "is task 11's" — re-pointed to divergence 47
kept, `TE-AJ`); `Frame.swift`'s `intersect`. **Tests**: new
`Tests/MetalUITests/{ShapeTests,ShapeStrokeTests,ClipShapeTests,ShapeCompileGuards}.swift`.
Before the red commit, a **census** of every test that paints a bare
`Rectangle()` (79 `Rectangle()` spellings in `Sources`/`Tests` at `ff2ae92`,
most in guards and layout-only tests): each one whose asserted colour moves
from `.surface` to `.textPrimary` is a T row with its literal re-derived
(`TE-AH`), listed in record §60.

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 2.1 | `everyBuiltInShapeAnswersItsProposalAndACircleTheSmallerSquare` — S1's 5 × 5 table through the kernel | no types | M2a: `Circle` keeps the default answer |
| 2.2 | `aCircleDrawsCentredInItsFrame` — 100×60 → rect (20,0,60,60) radii 30; 40×90 → (0,25,40,40) | — | M2b: circle at the frame's origin |
| 2.3 | `aCornerRadiusClampsToHalfTheShorterSideAndANegativeOneIsZero` — RR(50) on 100×60 → 30; RR(−5) → 0; `Capsule` 40×90 → 20 (S4–S6) | — | M2c: no clamp |
| 2.4 | `anEllipseEmitsTheEllipseKind` | — | M2d: `Ellipse` as a rounded rectangle |
| 2.5 | `aBareShapeFillsWithTheForegroundStyle` — `Rectangle()` → `.textPrimary`; under `.foregroundStyle(.accent)` → `.accent`; `Circle()` likewise (F1, F2, F5); `Rectangle(width: 10, height: 10)` still `.surface` under `.foregroundStyle(.accent)` (the fixed form's stored default, `TE-AQ` item 2) | `Rectangle()` fills `.surface` | M2e: default `.surface` |
| 2.6 | `aFillWinsOverTheForegroundStyle` (F3) | — | M2f: environment read first |
| 2.7 | `aStrokeDrawsOverTheFill` — `.fill(a).stroke(b, lineWidth: 10)` on 100×60: two rects, the fill first, the stroke's bounds (−5,−5,110,70), border 10, clear background (F4, K1) | — | M2g: layers painted reversed |
| 2.8 | `aStrokeBorderIsInsideTheEdge` — bounds (0,0,100,60), border 10 (K2) | — | M2h: `strokeBorder` outset |
| 2.9 | `aStrokeRoundsItsOuterEdgeByHalfTheWidthOnlyOverACurve` — RR(20) → 25; `Circle` 60 → (−5,−5,70,70) radii 35; RR(3) → 8; `Rectangle` → 0 (K1, K6, K7, K12) | — | M2i: `r + w/2` even at r = 0 |
| 2.10 | `aStrokeBorderWiderThanTwiceTheRadiusHasASquareOuterCorner` — RR(3).strokeBorder(10) → 0; RR(20) → 20 (K11) | — | M2j: radius kept |
| 2.11 | `aStrokeOfZeroOrNegativeWidthDrawsNothing` (K9) | — | M2k: guard dropped |
| 2.12 | `aStrokeChangesNoLayoutAndDefaultsToOnePoint` (K3, K5) | — | M2l: default width 0 |
| 2.13 | `anEllipseStrokeIsTheEllipseBandOverTheOutsetBounds` — `strokeBorder(10)`: bounds 100×60, border 10, kind 1; `stroke(10)`: bounds (−5,−5,110,70) | — | M2m: ellipse stroke not outset |
| 2.14 | `theContinuousStyleIsTheDefaultAndIsDrawnCircular` — **divergence 90's pin**: `RoundedRectangle(cornerRadius: 20)` and `Capsule()` default `.continuous`, and their primitives equal `.circular`'s | — | M2n: default `.circular` |
| 2.15 | `clipShapeClipsToTheShapesGeometry` — proposal overflow content (C0's) under `.clipShape(Circle())`: the child's mask (20,0,60,60) radii 30; `Capsule` → full bounds radii 30 (C2, C7) | — | M2o: clip to the bounds, not the geometry |
| 2.16 | `clippedAndCornerRadiusClipOnTheProposalPath` — `.clipped()` mask = bounds, radii 0; `.cornerRadius(12)` mask radii 12, equal to `.clipShape(RoundedRectangle(cornerRadius: 12))` (C1, C3, C4) | — | M2p: proposal `cornerRadius` not clipping |
| 2.17 | `clipShapeChangesNoLayout` (C8) | — | M2q: `clipShape` wraps a frame |
| 2.18 | `aLegacyClipShapeClipsItsChildrenAndItsHitboxes` — `Box { … onClick }.clipShape(Capsule())`: child mask radii, hitbox clipped as `clippedAlsoClipsTheHitboxesInsideIt` | — | M2r: the prepaint half omitted (only the hitbox arm reddens) |
| 2.19 | `clipShapeOfAnEllipseTrapsNamingDivergence91` (exit test) | — | M2s: trap removed |
| 2.20 | `aRoundedClipContainedInARoundedClipKeepsItsRadii` (one `@Test`) — C6: capsule (0,0,100,60) r 30 then circle (20,0,60,60) r 30 → radii 30 (the fallback gave 0); the mirror case; one `Frame.intersect` unit arm per case | square box | M2t: containment case removed |
| 2.21 | `twoCrossingRoundedClipsIntersectAsTheSquareBox` — **divergence 92's pin** | — | M2u: return the inner radii unconditionally |
| 2.22 | `aShapeBackgroundOrOverlayTakesTheContentsSize` — O1, O3, O5 through the existing `.background { }`/`.overlay { }`, both vocabularies, plus a `.topLeading` overlay arm (band at (−2, −2), `TE-AS` item 6) | no shapes | M2v: `Circle` answers the proposal (the `.topLeading` band moves to (18, −2); the centred O3 cannot see it, `TE-AS` item 6) |
| 2.23 | `backgroundInAShapeIsTheFilledShapeAndDefaultsToTheBackgroundToken` (O2, O4) | — | M2w: default token `.surface` |
| 2.13b | `aBorderWiderThanHalfTheShapeFillsIt` — K10: `Rectangle().strokeBorder(40)` on 100×60 renders byte-identical to its `fill` through a real window; control `strokeBorder(10)` differs (fix round, `TE-AT` item 1) | — | K10a: `rect_fragment`'s inner half-size `abs(halfSize − border)` |
| 2.15b | `aProposalClipShapeCutsTheHitboxesInsideIt` — a `ProposalScrollView`'s scroll-region hitbox (0,0,100,60) cut to (20,0,60,60) under `.clipShape(Circle())` (fix round, `TE-AT` item 1) | — | X7: the proposal `.clipShape` prepaint returns `inside()` |
| 2.18b | `aLegacyClipShapeWinsOverClipped` — `.clipped()` alone radius 0; with `.clipShape(Circle())` in either order radius 20 (`TE-AS` item 4; fix round) | — | X1: `clipRegion(in:)` reads `clipsContent` first |
| 2.18c | `aLegacyClipShapeComparesByItsConcreteShape` — `ClipShapeBox.==` by type and value (fix round) | — | X3: `==` returns `true` |
| 2.20 (arm) | the per-quadrant container radius: a radius-5 inner rect in a 100×100 outer's bottom-right corner is contained when that corner is square, not when it is 40 (fix round) | — | X9: always `containerRadii.topLeft` |
| G2.1 | `anOutsideShapeNeedsOnlyItsGeometry` — plain `import MetalUI`, whole-file: a struct conforming to `Shape` with only `geometry(in:)` compiles, `.fill(.accent)`s, **and sits bare in an `HStack`** (so it is a `ProposalElement`); control: one without it fails naming `geometry` | — | MG2a: `sizeThatFits`'s default removed; MG2a′: `Shape` refines `Element` instead of `ProposalElement` (the `HStack` arm fails) |
| G2.2 | `theRectangleColorInitialiserIsDeprecatedTowardFill` — `Rectangle(color: .accent)` warns naming `fill`; control `Rectangle().fill(.accent)` warns nothing | — | MG2b: deprecation dropped |

### Lane 3 — `Image`, `aspectRatio(nil)`, the `UnitPoint` grid anchor

**Files**: new `Sources/MetalUI/{Image,ImageBitmap}.swift`;
`NativeModifiedContent.swift` (`aspectRatio(_:contentMode:)` optional ratio,
`scaledToFit`/`scaledToFill`, `ContentMode`); `Sources/MetalUILayout/{LayoutTree,NativeGrid}.swift`
(the nil-ratio node, the anchor factor pair); `Frame.swift`/`Passes.swift`'s
aspect-ratio registrars; `Sources/MetalUI/{Grid,UnitPoint}.swift` (including
`UnitPoint.swift:11`'s and `Grid.swift:338`'s doc comments, which still name
the nine-point gap as plan task 11's — re-pointed to divergence 64 retired).
**Tests**: new `Tests/MetalUITests/{ImageTests,ImageCompileGuards}.swift`,
new `Tests/MetalUILayoutTests/AspectRatioIdealTests.swift` (portable),
an arm in `Tests/MetalUITests/GridElementTests.swift`, `GridCompileGuards.swift`
(G4 inverted, below).

| # | test | red before | mutation that must redden it |
|---|---|---|---|
| 3.1 | `anImageAnswersItsPointSizeAtEveryProposal` — 40×20 px at scale 1, and 80×40 px at scale 2, both 40×20 at I1's five proposals (I1, I9) | no type | M3a: `scale` ignored |
| 3.2 | `aResizableImageAnswersItsProposal` (I2) | — | M3b: `resizable()` a no-op |
| 3.3 | `anImagePaintsOneTexturedQuadOverItsBoundsAtTheScale` — at scale factor 2, the `MUIImage` bounds are the element rect × 2, its texture the bitmap's | — | M3c: bounds not scaled |
| 3.4 | `aspectRatioWithNoRatioTakesTheChildsIdealRatio` (`MetalUILayoutTests`, kernel) — a leaf ideal 40×20 → 100×60 fit 100×50, nil×nil 40×20 (A3); a `Color`-like leaf → 60×60 fit, 100×100 fill (A1, A2) | ratio required | M3d: nil ratio treated as 1 |
| 3.5 | `aFixedChildKeepsItsSizeUnderAspectRatioNil` (A4, I7) | — | M3e: child proposed the ratio's size and clamped |
| 3.6 | `scaledToFitAndScaledToFillAreAspectRatioNil` — a resizable image in 100×60: fit (0,5,100,50), fill (−10,0,120,60) (I3–I5) | — | M3f: `scaledToFill` mapped to `.fit` |
| 3.7 | `aFillImageOverflowsItsFrameUnlessClipped` — I10: unclipped mask is the surface; `.clipped()` mask (0,0,100,60) | — | M3g: image clips itself to its frame |
| 3.8 | `interpolationNoneIsNearestAndEveryOtherLinear` — **divergence 93's pin**: `.none` → filter 1; default, `.low`, `.medium`, `.high` → 0 (I8, I11) | — | M3h: `.none` → 0 |
| 3.9 | `anImageBitmapPremultipliesStraightAlpha` — (200,100,50,128) → (100,50,25,128) | — | M3i: bytes copied as given |
| 3.10 | `anImageBitmapOfTheWrongByteCountOrAZeroSideTraps` — **one** `@Test` holding two `#expect(processExitsWith:)` arms, each asserting `ImageBitmap` in its stderr (so `ImageTexture`'s own trap cannot stand in) | — | M3j: precondition removed |
| 3.10b | `anImageOfANonPositiveOrNonFiniteScaleTraps` — scale 0 and ∞, each naming `scale` (`SA-J`, `TE-AU` item 2) | — | M3m: precondition removed |
| 3.11 | `anImageBitmapDecodesAPNGThroughImageIO` (macOS) — a **2×2** PNG (`TE-AU` item 3: one row cannot see M3k) written by ImageIO in the test, decoded to the same straight bytes, premultiplied; a missing file is `nil` | — | M3k: rows read bottom-up |
| 3.12 | `aGridCellAnchorTakesAUnitPoint` — GL14: `a` at (10,20), `b` (58,0), `c` (0,38) | nine-case only | M3l: anchor factors rounded to the nearest nine-point |
| 3.12b | `aNonFiniteGridCellAnchorTraps` — `UnitPoint(x: .nan, y: 0)` traps naming `gridCellAnchor`; control (1.5, −1) lays out (`SA-J`, `TE-AU` item 2) | — | M3n: precondition removed |
| G3.1 | **G4 inverted and renamed**: `aGridCellAnchorIsNinePoint` → `aGridCellAnchorTakesAUnitPointAndTheNinePointSpellingsStillResolve` — `UnitPoint(x: 0.25, y: 1)` compiles; `.topLeading` still resolves to the `ProposalAlignment` overload (the control) | the old guard's answer | MG3a: `@_disfavoredOverload` removed (the leading-dot control stops compiling) — does not build alone; MG3a′ also spells the package's 27 leading-dot sites `ProposalAlignment.…` (`TE-AU` item 7) |
| G3.2 | `anImageHasNoSystemNameOrAssetInitialiser` — `Image(systemName:)` and `Image("name")` fail naming `Image`; control `Image(decorative:scale:)` compiles | — | MG3b: a `init(systemName:)` stub added |

## 9. Renderer constraints and what is not built (owner none unless named)

| not supportable yet / not built | why | owner |
|---|---|---|
| continuous corners (`RoundedCornerStyle.continuous`) drawn exactly | the rect SDF is circular; Apple's continuous curve has no closed form this renderer carries | none — divergence 90 |
| elliptical corners (`RoundedRectangle(cornerSize:)`), `UnevenRoundedRectangle` | not offered; the primitive has per-corner circular radii, so `UnevenRoundedRectangle` is drawable, but the task names neither | none (plan task 15's inventory) |
| `Path`, custom `path(in:)` shapes | no path-coverage or tessellation primitive | none |
| gradients and any `ShapeStyle` but a colour token | §7.9 (tokens), and no gradient primitive | none |
| `StrokeStyle` (dash, cap, join, miter limit) | no stroke primitive; a rect's corner is its join | none |
| an ellipse clip, `clipShape(Ellipse())` | the mask is a rounded rect on every primitive | none — divergence 91 (a trap) |
| two crossing rounded clips | one mask per primitive | none — divergence 92 |
| `.interpolation(.high)` | bilinear only | none — divergence 93 |
| `Image(_:bundle:)`, `Image(nsImage:)`, `Image(systemName:)` (SF Symbols), `resizable(capInsets:resizingMode:)`, `renderingMode`, `symbolRenderingMode`, `Image(decorative:scale:orientation:)`'s `orientation:` | no asset catalog, no AppKit image type crosses the seam, SF Symbols are out of the task's scope | none |
| a labelled `Image(_:scale:label:)` and an image's accessibility | accessibility | **plan task 12** |
| image decoding off Apple (`ImageBitmap(contentsOfFile:)`) | no decoder is vendored | none |
| `colorScheme`/`appearance` environment value; the theme before paint | `EV-G`'s paint-only rule stands; a second appearance source needs a coupling rule to tokens no probe here measures | none (`TE-AO`) |
| colour glyphs | a polychrome rasterizer and atlas; the image pipeline is what would draw one, rasterization is the missing half | none (record §05's row) |
| shapes' and `clipShape`'s hit regions (`contentShape`) | interaction | **plan task 12** |
| a nearest-sampled texel boundary exactly on a pixel centre | which texel is read there is the backend's interpolation rounding (Metal and llvmpipe pick opposite sides: 55 px, Δ97 measured) — every renderer, SwiftUI's included; parity frames keep boundaries off pixel centres (`TE-AR` item 5) | none |

## 10. Verification (each lane, and the Record phase)

Full unfiltered suite, summary line read (≈ **1756** = 1706 + 12 (lane 1)
+ 23 + 2 guards (lane 2) + 12 + 1 guard (lane 3); G3.1 renames a guard,
adding none; the `Backends/SDL` rows are outside this count; the lanes give
the exact figure — **as landed 1762** = 1706 + 12 + (25 + 4, `TE-AT`) + (14 +
1, `TE-AU` item 2)), guards **108**, `FR-J` line present, 0 `error:`, one
`warning:`; fourteen images 0 px; the probe re-run byte-identical to its
header; `Backends/SDL` (`PKG_CONFIG_PATH=.accesskit`) builds and tests;
`Replay --portable` 7 frames PASS, `PortableReplay --expect 7` and
`DemoCapture` PASS; a `swift:6.4-noble` container builds the root package
(and runs its portable suites: `MetalUILayoutTests` + 1); `goldensUnchanged`:
every T row (lane 2's `Rectangle()` census, G3.1) has its retirement row and
no other retained test changes its answer. The Record phase writes record
§60's close, records §03/§04/§05 dated sections (64 retired; 90–93 added; 47
re-read and kept; §05's colour-glyph row re-read), CLAUDE.md/AGENTS.md, the
plan's progress note — **ticking task 11 if and only if every clause above
landed** (`TE-AP`) — and `docs/record/README.md`.
