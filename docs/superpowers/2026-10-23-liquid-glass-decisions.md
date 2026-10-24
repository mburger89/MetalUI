# Liquid Glass — decisions

Rulings for item LG: SwiftUI's Liquid Glass (`glassEffect`, `Glass`, `GlassEffectContainer`,
`glassEffectID`/`Union`/`Transition`, `.buttonStyle(.glass)`/`.glassProminent`) on both renderers
(user request 2026-10-23, gpui-gap priority list; **not a plan task**; MetalUI only). Builds on the
backdrop blur (`BB-`, record §94,
[`2026-10-10-backdrop-blur-decisions.md`](2026-10-10-backdrop-blur-decisions.md)). Spec:
[`specs/2026-10-23-liquid-glass-design.md`](specs/2026-10-23-liquid-glass-design.md). Record: `docs/record/153-liquid-glass.md`
(Record phase). Branch `feat/liquid-glass` from `f1c422e5`; divergence labels reserved for this
branch: **825–834** (planned below: 825–829).

**Next unused id: `LG-V`.** (Moves in the commit that appends a ruling; read the last `## LG-`
heading, not this line, if they disagree.)

Evidence: [`../probes/swiftui-liquid-glass.swift`](../probes/swiftui-liquid-glass.swift) (groups `A`, `P`, `R`, `W`;
macOS 27.0.1, Xcode SDK, Swift 6.4.2, unlocked screen, recorded output in its header; every W number below is a real
window, `screencapture -l`, 2x pixels). gpui has no glass (its `blur` is a shadow primitive); where SwiftUI is silent
MetalUI's own choice is named. **`ImageRenderer` draws no glass at all** (probe R), so every pixel claim is a window
capture and no test can compare with SwiftUI; the tests pin MetalUI's own arithmetic, and the look against a real
SwiftUI app is human check group LG.

## LG-A — The API is SwiftUI's, read from the installed SDK, not from the brief

**Ruling.** Public, class A unless noted:
`View.glassEffect(_ glass: Glass = .regular, in shape: some Shape = <capsule>)` (**no `isEnabled:` parameter: the SDK
has none**, probe A4/A5; the brief's `isEnabled:` is not built), `Glass` (`.regular`, `.clear`, `.identity`,
`.tint(_ color: Color?)`, `.interactive(_ isEnabled: Bool = true)`; `Equatable`, **not** `Hashable`, no initialiser;
A14–A17), `GlassEffectContainer(spacing: CGFloat? = nil, content:)`, `glassEffectID(_:in:)` (any `Hashable & Sendable`
id, an optional one accepted, A19), `glassEffectUnion(id:namespace:)`, `GlassEffectTransition`
(`.matchedGeometry`, `.materialize`, `.identity`) with `glassEffectTransition(_:)`, `ButtonStyle.glass` and
`.glassProminent`, `Namespace`/`@Namespace` (SwiftUI's; MetalUI has none yet, `LG-L`). Both vocabularies get the
modifier (proposal content: one `LayoutModifier` case; legacy `StyledElement`: `Decoration` extras), as `.background(material)`
did (`BB-P`). MetalUI has no availability annotations, so none are written.
The default shape is a **capsule**: `DefaultGlassEffectShape.path(in:)` agrees with a capsule on 3972 of 4000 and 9928
of 10000 grid points, the misses boundary pixels of `Path.contains` (probe P).

**Reasoning.** A9/A21 and the interface text are the authority; the brief said "probe the exact signature".
**Cost if wrong.** A later SDK adding `isEnabled:` is additive.

## LG-B — One primitive: `MUIBackdrop` grows a glass tail; no new `PrimitiveKind`

**Ruling.** A glass is a `.backdrop` record. `MUIBackdrop` goes from 96 to **256 bytes**: the six existing lanes keep
their offsets (pinned), then two **look lanes** and four **member slots** of two lanes each (a member's bounds and
four corner radii, **normalised to the record's own `bounds`**: origin as a fraction of the blob's size, radii as a
fraction of its shorter side, so every site that translates or uniformly scales `record.bounds` — `Transition.swift`
ghosts, `DragSession`, `RenderEffect.apply`, the flatten — moves the members with it and no site needs a new line).
A material's tail is all zero and **`look.flags == 0` takes today's arithmetic byte for byte** (`backdrop_fragment`
unchanged on that branch), so every existing backdrop pixel, counter and fixture frame is unchanged. A Swift
`MUIBackdrop.init(bounds:…opacity:)` extension with the tail defaulted keeps the eight existing call sites compiling.
Rejected: a new `PrimitiveKind.glass` and `Scene.glasses` (a public exhaustive-switch break, a second `Scene` array pair, a
second run kind in both renderers, a second set of fade/flatten/ghost/drag/retained arms — ten sites, each a silent
"forgot one" hazard that `BB-G`/`BB-H` already closed once for the backdrop).

**Reasoning.** Everything `BB-` built — one region function, `L + 2` pass counting, the frame target, the segment split,
the flat fallback, fades, ghosts, drag previews, the retained refusal `unlistedKind:backdrop` — applies to a glass
unchanged, which is the "build on BB" the brief asks for. The cost is 160 bytes per backdrop record, which is
irrelevant at tens of records a frame, and one stride change in the header, the HLSL read, the SDL upload and
fixture v5.
**Cost if wrong.** If members must exceed four or carry paths, a side table indexed from the tail replaces the inline
slots; the tail's flags word keeps its meaning.

## LG-C — The base look is the measured affine over the blurred backdrop, per variant and scheme

**Ruling.** A glass leaf's colour is `T + (1 − T.a) · B` over the **same blurred backdrop `B`** as a material
(sigma stays `MUIBackdropSigmaPoints`, `LG-D` item 1), with `T` fitted per (variant, scheme) from probe W2 as a
non-premultiplied `Hsla` (the record's `tint`), through the one table `GlassLook.base(_:scheme:)` (`package`, one
source for record, flat fallback and Reduce Transparency, as `Material.fill`):

| variant, scheme | black | gray 142 | white | affine fit (`out = I + s·B`) | tint colour, alpha |
|---|---|---|---|---|---|
| regular, light | 139 | 197 | 241 | I 139, s 0.40 | 0.908 grey, 0.60 |
| clear, light | 71 | 167 | 244 | I 71, s 0.68 | 0.870 grey, 0.32 |
| clear, dark | 25 | 133 | 207 | I 25, s 0.71 | 0.338 grey, 0.29 |
| regular, dark | 19 | 132 | 169 | **not affine** (chord misses gray by 24) | least-squares line over the three points, error up to 14/255 |

(values are 0–255 red-channel readings of a neutral backdrop; the lane re-fits to Oklab-free sRGB bytes and records the
table in `GlassLook`'s header.) `.identity` draws **nothing** and is the pixel-equal control (W2: identity equals no effect
to the byte, light and dark). `Glass` carries `variant`, an optional tint, `interactive` and compares by value.
**Dark regular is a divergence** (825): SwiftUI's glass is adaptive in a way one affine cannot follow; the fit is exact at
black and ~12/255 off at white and mid grey. **Cost if wrong.** Table values only; the arithmetic is unchanged.

## LG-D — Blur, lensing and rim: sigma is Material's; lens and rim are MetalUI's, bounded and named

**Ruling.** 1. **Sigma 52 pt** (the Material constant): the probe cannot separate it (a 4 pt and a 6 pt stripe
backdrop reads flat, 191–193 regular and 158–162 clear, which only says sigma ≳ 5 pt; W4, W7).
2. **The interior is flat and has no inner rim in SwiftUI's capture** (W3, W6, W7: a stripe edge 4 px inside the shape leaves
no trace, ±2 over −6…24 px). The brief asks for lensing and a specular rim, so MetalUI adds them as **its own
look, class M, divergence 825**, with amplitudes chosen small and constant (`GlassLook.lens`/`rim`, `package`, pinned by
tests as arithmetic, not as a match to SwiftUI):
   - **Lens**: inside the shape, within a band `w` device pixels of the edge (`w = min(0.5·min(bounds), 12 pt)`), the
     backdrop is read from the **sharp frame target** at `p − n · d_lens(t)`, `t = clamp(sdf_in / w, 0, 1)`,
     `d_lens = lensDepth · (1 − t)²` with `n` the outward SDF gradient, and mixed over the blurred read with weight
     `(1 − t)²`: the edge shows the backdrop bent and sharper, the interior is the base look. (A blurred-only read would show
     nothing under sigma 52; hence the second texture.)
   - **Rim**: `rim = rimStrength · (1 − t)^4 · (0.65 + 0.35 · dot(n, L))`, `L` toward the upper left, added as white at that
     alpha over the result (premultiplied), light and dark strengths from the scheme.
   - Both are **zero** for `look.flags` bit `lensRim` clear, so a test or a degraded renderer pins the base look alone.
3. The **same arithmetic** lands in `shaders.metal` and `replay.hlsl` with a CPU reference in `MetalUIPath`
   (`GlassReference`, imports nothing, `TE-AD`, `LG-O`). The record's two look lanes carry `lensDepth`, `band`, `rimStrength`,
   the scheme bit and the member count, **resolved on the CPU**, so the shaders read numbers, never a scheme.
4. **Carried, not built** (`LG-Q`): the 1 px outer hairline contact shadow measured in W6 (regular: 92 left/right, 108
top/bottom of 142; clear: left/right only).

**Reasoning.** Honesty over a pretty guess: the one measured edge feature is the carried hairline; the requested lens/rim
are labelled MetalUI's, tunable in one place after a human look in a key window.
**Cost if wrong.** A different look is a constants change; if SwiftUI's lens is real but invisible to `screencapture`, human
check LG1 re-tunes `GlassLook` with no architecture change.

## LG-E — Tint is source-over of the colour; regular's tint is unexplained

**Ruling.** `Glass.tint(c)` composites `c` (its own alpha) **source-over on the finished glass colour**: clear measured
exactly so (W2: `clear.tint(.red)` over black (233,0,0), over gray (255,0,6); W8: `clear.tint(red.opacity(0.3))` over gray
(197,124,130) against 167 untinted: G falls by 43, R rises by 30, which is 0.26–0.34 of the way to red). **`regular.tint(c)`
in SwiftUI gave a colour-independent grey** (W8: blue, white and black all (172,172,174), against 197 untinted) — unexplained
(a capture limit of an inactive borderless window is not excluded), so MetalUI applies the same source-over to both variants
and names the difference (divergence 825, human check LG2). `tint(nil)` is no tint; `Color` resolves through
`PaintPass.resolve` so a palette or token tint follows the scheme (`CR-`). **Cost if wrong.** One composite line.

## LG-F — Reduce Transparency draws an opaque grey through the `MT-` path

**Ruling.** A new `Frame.fillGlass(…)` is `fillMaterial`'s sibling: with `accessibilityReduceTransparency` it fills the shape
with `GlassLook.opaqueColor(variant:scheme:)` (the base table at alpha 1, tint source-over on it) as an ordinary rect or
path, no backdrop record, so no split, no blur pass; a change snaps (`MT-E`/`MT-F`). SwiftUI's own fallback is unmeasured
(the setting cannot be moved from a probe, `MT-F`), so the grey is a ruling. **Cost if wrong.** A table row.

## LG-G — Container merging is the polynomial smooth-min with blend radius `spacing`; the threshold is measured

**Ruling.** Shapes in a `GlassEffectContainer` whose surfaces are closer than the blend radius merge into one blob whose
signed distance is `smin(a, b, k) = min(a, b) − h²·k/4`, `h = max(k − |a − b|, 0)/k`, `k = spacing` (folded over the
members). **Measured**: two 60 pt circles with surface gap `g` merge at the gap centre iff `spacing > 2g`, exactly — `g = 10`:
spacing 17 and 19 no, 20 half-covered, 21 yes; `g = 20`: 30 no, 40 half-covered, 44 yes (W9, W10) — which is the smooth-min's
own crossing (`smin = g/2 − k/4 = 0` at `k = 2g`); the neck at spacing 24 reaches 6 pt above the row and not 12, at 40 to 12 and not
18 (W9). `spacing: nil` merges at `g = 2`, not at 6 (W15): `k ∈ (4, 12]`, **ruled 8**. A small circle merges the same way
(W11). **Cap: four members per blob** (the record's inline slots, `LG-B`); a container with more is merged in
**greedy chunks of four in tree order, never across chunks** (divergence 826, tested). Coverage of a blob is the
antialiased smooth-min SDF (half-pixel threshold, as `rect_shade`), times the clip; **a single-member glass takes the rect
shader's own SDF** so its edge equals a material's.
**Cost if wrong.** A different kernel changes `GlassReference.smin` and both shaders together; the threshold test is the
instrument.

## LG-H — `glassEffectUnion`: the documented intent, not the measured anomaly

**Ruling.** Members of one container sharing a union id (and namespace) form **one blob regardless of distance**: the fold
uses `k = max(spacing, 2 · largest surface gap + 2 pt)` for that set. **SwiftUI measured differently** (W12–W14): two 60 pt
circles with one union id render **one 60 pt circle centred between them** at gaps 10, 30 and 60, never the union of the two
shapes — against its documentation ("combines glass effects … into a single shape"). A mid-morph capture is not excluded;
the capture was taken 1 s after ordering the window in. MetalUI follows the documented intent, names the measured behaviour
and carries the question to human check LG3 (divergence 826).
**Cost if wrong.** A union becomes "first member's shape at the union centre" in one function.

## LG-I — Emission: standalone leaves at their own paint; a container emits its blobs before its content

**Ruling.** A `glassEffect` outside a container emits one record at its own paint position, **behind its content** (as
`.background(material)` does), covering its node's rect. Inside a container the members **register in prepaint** (shape,
`Glass`, rect, union id) into the open `GlassGroup` on `Frame`, emit nothing themselves, and the container emits its blobs
**at the start of its own paint, before it paints its content** (so labels sit above all glass; a non-glass element between two
members is therefore *under* the blob, divergence 826, pinned). **A container's subtree refuses retention by the taint
`glassContainer`** (the `pasteButton` way: counted, named, an `.equatable()` ancestor is evaluated every frame), because the
registration is a prepaint side effect no ledger replays; a **standalone** glass is a plain `fillGlass` at paint and the paint
record already carries a `.backdrop` (translation refuses it by name `unlistedKind:backdrop`, unchanged). **No new
`AmbientKey` field**: nothing the glass reads at paint is ambient beyond what `fillMaterial` already reads (scheme through
`resolve`, `accessibilityReduceTransparency`, opacity); a press changes a hovered/pressed element, which already excludes a
record (`SB-X`). **No new `StateTable` write site, no new `$` name**; no `noteNamed` site (nothing mints an id). A
`Frame.glassGroups` stack is per-frame scratch cleared at `render` (a pin).
**Cost if wrong.** If a profile needs retention under a container, the registrations become a ledger channel (`RK-`).

## LG-J — `.interactive()` reads the enclosing control's pressed and hovered state; no hitbox, no scale

**Ruling.** `Glass.interactive(true)` makes the leaf read `isHovered`/`isActive` of the **nearest enclosing control's id** (a
`Button` with `.buttonStyle(.glass)`, or any element the author marks) and lift the tint (`pressLift`: white at 0.12 alpha,
hover 0.05) in the record's second look lane, animated by the existing value animation. **A bare `.glassEffect(.interactive())`
on non-control content registers no hitbox** (hit testing must not move, `OM-AK`), so it is inert there (divergence 827; SwiftUI
shows a press response on its own). **No scale, bounce or shimmer** (SwiftUI's press scale is unprobed and would move a
frame): carried (`LG-Q`).
**Cost if wrong.** A press scale is a `scaleEffect` layer on the button style.

## LG-K — `glassEffectID`, `glassEffectTransition` and `Namespace`: accepted, not morphing

**Ruling.** `glassEffectID(_:in:)` is **accepted and carries the id** (a transparent tag the union reads); **no morph**: two
glass leaves with one id at different positions across a state change do not interpolate their geometry (MetalUI has no
`matchedGeometryEffect`; divergence 828). `glassEffectTransition(.materialize)` and `(.matchedGeometry)` apply the **standard
opacity transition** to the glass-bearing view's conditional (insertion needs the conditional evaluated last frame, removal
draws a ghost — `AN-` rules, and the ghost replays the record, `BB-G`), `.identity` is `.transition(.identity)`. `Namespace`
is built as SwiftUI's wrapper (a `@Namespace var ns` yielding a `Hashable Namespace.ID` stable for the element's life): the
lane builds it over a nested `State` if `StateBinder` binds one (test `aNamespaceIdIsStableAcrossFrames`), else seeds the id
from the element's `GlobalElementID` at bind (no eighth reserved slot either way, `theSevenRetentionSlotsAreMutuallyDistinct`
unmoved — the pin is run unfiltered). **Deferred with owner:** the morph, to a future `matchedGeometryEffect` milestone.
**Cost if wrong.** Spelling stays; behaviour deepens.

## LG-L — Degradations, by name (`BB-H`/`BB-I` inherited)

**Ruling.** A **`Path` shape** (a `Shape` whose `geometry(in:)` is a `Path`) draws the variant's **flat tint as that path's
ordinary fill** (not a rect: `BB-H` degraded a path fill to the bbox rect; a glass owes the path's own silhouette, which the
path fill gives for free; divergence 829, shared with `BB-H`'s 248 in spirit); a glass **inside a CPU-rasterized `.shadow`/
`.blur`/`.compositingGroup()`**, an ellipse/path **clip**'s trap (divergence 91 unchanged) and a renderer that **cannot blur**
(`BB-I`) take the record's **flat arm**: `c · o · T` per member through the new `MUIBackdrop.flatTintRects` (one rect per
member, `flatTintRect` for a one-member record unchanged; the lens, rim and merge are lost, the base tint stays). Reduce
Transparency: `LG-F`. A transition ghost and a drag preview replay the record (`BB-G`). **Cost if wrong.** A table of arms.

## LG-M — Button styles

**Ruling.** `ButtonStyle.glass` and `.glassProminent` join `.plain`/`.borderless`/`.bordered` as values (`ButtonStyle.kind`
cases; `isBordered` false for both): the label in a capsule glass (`.regular`, `.interactive()`), padded as the bordered
style, `.glassProminent` tinted with the accent (`.regular.tint(accent)`, label white); both honour `.disabled` (the label dims,
glass `identity`-free but with `Glass` tint desaturated by the existing disabled opacity), the focus ring and the keyboard
table are `ControlKeys`' unchanged. **No Button layout, hitbox or key change.** The look is MetalUI's (the SwiftUI styles' exact
metrics are unprobed: human check LG2). **Cost if wrong.** Padding constants.

## LG-N — Tests drive it headless through the scene, not pixels, except the renderer's own readbacks

**Ruling.** Three kinds, all headless: (1) **scene pins** — `MetalUITesting`'s frame yields `Scene.backdrops`, the tests read
the record (tint, flags, members, opacity) and the work counters, never a window; (2) **reference arithmetic** —
`GlassReference` over fields that vary on both axes (a vertical step let four mutations survive in §94 §6), tolerance one byte;
(3) **readbacks** — `MetalRenderTests`' offscreen drawable on macOS hardware, and `Backends/SDL`'s replay-parity harness on SDL
Metal and the Linux image's lavapipe, against `GlassReference`. A SwiftUI pixel comparison does not exist (`ImageRenderer` is
blind to glass, probe R); the real-window comparison is human check LG1. **Cost if wrong.** none.

## LG-O — Replay parity: fixture v5, the 256-byte record, three new frames

**Ruling.** `ReplayFixture` version 5 (version 4 still read: its 96-byte records are widened with a zero tail on decode,
exactly as version 3 widened to 4), `backdropStride` 256, three new parity frames (glass regular over a two-axis field with
lens and rim; a two-member blob at spacing k 24; a clear tint-source-over with a rotated transform), every existing frame
byte-identical. HLSL reads the record as sixteen `float4` lanes. Tolerance and the counters are `BB-J`'s. **Cost if wrong.**
A fixture re-record.

## LG-P — Pixels and the demo

**Ruling.** The fourteen offscreen images stay **0 px** against `f1c422e5` (no glass is drawn unless a tree asks; every
material record's tail is zero and its arithmetic untouched). The demo gains `liquidGlassSection()` in its **own function**
under `LooksDemo` (`METALUI_LOOKS_DEMO=1`), over a coloured, striped backdrop so lens, rim and merge are visible: regular,
clear, tinted, interactive buttons in `.glass` and `.glassProminent`, a container of three circles with a spacing control. If
`LooksDemo` is part of any of the fourteen images the section is gated behind its own `METALUI_GLASS_DEMO=1` instead —
**0 px wins** over placement. `DemoFrameDeterminismTests`' `Expected.swift` is not edited. **Cost if wrong.** A flag.

## LG-Q — Carried and deferred, each with a reason and an owner

1. The **1 px outer hairline** (W6) — needs the quad grown by a device pixel in both shaders and a coverage term outside the
shape; measured on one backdrop at 2x only. Owner: a follow-up after human check LG1 confirms it on a real window.
2. **Morph** between `glassEffectID` shapes — no `matchedGeometryEffect` (`LG-K`). Owner: that milestone.
3. **Press scale/bounce** and a pointer-following specular (`LG-J`). Owner: LG1's look.
4. **More than four members per blob** (`LG-G`) — a side table (`LG-B`). Owner: when an app needs it.
5. **A real blurred glass on a `Path`** — needs a path SDF (`BB-H`). Owner: `GX-` follow-up.
6. **Sigma and the lens depth against SwiftUI** — not separable headless (`LG-D`). Owner: human check LG1.
7. **Windows D3D12** parity — CI only, as `BB-J`.

## LG-R — Critic review: `spacing` is `Pixels?`; lane split stays

The design spelled `GlassEffectContainer(spacing: CGFloat?)`; MetalUI's public length type is `Pixels` (`Grid`, stacks), and an
Apple `CGFloat` has no place in a portable surface. **Ruled `Pixels?`.** Probe arms A4 (`isEnabled:` rejected) and A15 (`Glass` not
`Hashable`) were re-run and reproduce. Rejected as defects, with reason: three lanes are the cap and A's header change is the shared
dependency, so the A, then B and C order stays; lane C is large but disjoint from A and B. Every primitive lands on both renderers
(lanes A and B, parity frames 12-14), no platform requirement is added (no default or fake owed), no C enum is introduced.

## LG-S — Lane A as built: what the renderer measured against the design

**Ruling.** Seven points, each amending the text it names (the spec §3 and §5 carry a pointer here).
1. **The tail's fields are flat and named** (`LG-B`): `glassFlags`, `lensDepth`, `band`, `rimStrength`, `blendK`, `press`, `pressLift`,
`glassReserved` at 96…124, then `member0…member3` (`MUIGlassMember`: a `MUIBounds` and a `MUICorners`, 32 bytes) at 128, 160, 192, 224;
stride 256, the first six lanes' nine fields at 0, 16, 32, 48, 64, 80, 84, 88, 92 (test 1). Not `look0`/`look1` tuples: Swift would
import an array as a tuple. A nine-argument `public init` in `MetalUIScene` (`BackdropGlass.swift`) keeps every material site and the plain-import
guard 1.13 compiling; it is a public declaration owing a census row and a doc comment (it has the comment; the row is the Record phase's).
2. **The rim has no cutoff before `t = 1`** (`LG-D` 2 stands, `(1 − t)^4` over the whole band): the spec's test 6 said "zero at `t ≥ 0.25`", which
the formula does not give (`0.75^4` is 0.32). Test 6 pins the upper-left over lower-right ratio 10/3, the decay with depth and exactly zero at `t ≥ 1`
and with `lensRim` clear.
3. **The lens reads a copy of the frame region, not the frame target.** The frame target is the pass's own render target, and sampling it
inside that pass is undefined in Metal (no texture barrier), so each glass with the lens on gets a blit of its `backdropRegion` into a pool texture
(`Renderer.sharpCopy`, the `BB-D` pool, released after the draw) bound as texture 1; a record that reads none gets the blurred texture bound
(a texture must be bound), and a failed copy degrades the lens to the blur. Counted: `lastGlassRecords`, `lastGlassSharpCopies`; the copy is a
blit, not a render pass, so `lastBackdropPasses` stays `L + 2` (test 12). The lens read is bilinear at `(q − regionOrigin) / regionSize`.
4. **Press lift applies whenever `press · pressLift > 0`**, after the base and before the rim, and with `lensRim` clear (the lift is not part of the lens).
The flat arm and the Reduce Transparency grey carry no lift.
5. **Test 2's spec mutation ("run the glass branch when `flags == 0`") is an equivalent mutant on pixels, by design**: a glass with the lens, rim and lift
off is a material to the byte (test 8 pins it), so routing a material through the glass arithmetic changes nothing. Test 2 is the instrument
for the *material* arithmetic (a stored readback taken on `f1c422e5`, within one level because the bytes are a GPU's); its mutation is the material
path's premultiply, which reddens it.
6. **Two tests the spec's twelve did not hold were added**: 4b (the shader's fold against `GlassReference` over a three-member blob, which the
reference-only test 3 cannot see in the shader) and 11b (`backdropPoolFailsAllocation` with a two-member blob: one flat rect per member).
7. **`MUIBackdrop.flatTintRects` is `package` in `MetalUIScene`; `MetalUI`'s internal `flatTintRect` stays** (a same-named package member would be
ambiguous with it), and the renderer's private copy is gone (it now flat-maps `flatTintRects`). A blob whose blur cannot be had draws
`encodeRects(flatTintRects)` (one pipeline change: `encodeBackdrop` throws).
**Hazard measured.** SwiftPM's native build does not notice an edit to `MetalUIShaderTypes.h` through the `Sources/MetalUIShaderTypes/include`
symlink on every run: after editing **or restoring** it, `touch Sources/MetalUIShaderTypes/shim.c` (or `swift package clean`) or the test targets keep
the old layout and read garbage. A mutation result taken after a header restore without it is contaminated (the first batch was, and was thrown away).
**Cost if wrong.** Constants and one blit; the rim cutoff is one expression.

## LG-T — Lane B as built: SDL (`replay.hlsl`, bridge, fixture v5)

**Ruling.** 1. HLSL reads the 256-byte record as sixteen lanes (lane 6 flags/lens/band/rim, lane 7 blendK/press/lift, lanes 8-15 members); the backdrop fragment has **two sampler pairs** (t0/s0 blurred, t1/s1 the sharp copy, storage buffers at t2/t3), `stage(...)` declares 2 samplers; only `backdrop.*` blobs changed in `Shaders/compiled` (the other nine stages byte-identical, built with the pinned shadercross in the `metalcreator-linux:xp-c` image).
2. The bridge keeps **`FLAT_SLOTS = 4` flat rect slots per backdrop record** (one rect per member of a blob for the `BB-I`/`LG-L` arm, `flat_tint_rects` restating `flatTintRects`); a run's fallback draws per record. The sharp copy is an `SDL_BlitGPUTexture` of the region into a pool slot between passes; counters `out[7]` add glass records and sharp copies (`lastGlassRecords`, `lastGlassSharpCopies` on `SDLWindowRenderer`).
3. Fixture version 5; version 4 (96-byte records) widens with a **zero tail** (a material); `GlassParityFrames` (`ReplayFixture`) holds frames 12-14 for `Replay` and the tests; CI `--expect 12` became `15`.
4. **Measured:** SDL's Metal driver equals Metal at 0 px on frames 12-14; Mesa lavapipe (Vulkan) reads max Δ3 on frames 12 and 13, **at `BB-J`'s tolerance of 3 exactly, no headroom**.
5. **Carried (lane A's file):** when the sharp copy fails but the blur succeeds, Metal binds the blurred texture as `sharp` and the lens reads it at the wrong scale (SDL mirrors that); the one-line fix is clearing `glassFlags` bit 1 in `Renderer.encodeBackdrop` when `sharp == nil`.
**Cost if wrong.** Tolerance 3 is one constant; the slot count is one enum.

## LG-U — Lane C as built: the public surface, the container, the buttons

**Ruling.** Eleven points, each amending the text it names.
1. **One `LayoutModifier` case, not three** (`LG-A`): `.glassEffect(Glass, any Shape)`. `glassEffectID` and `glassEffectUnion` are **transparent
`GlassTagScope`s on `ElementGroup`** (`CoordinateSpaceScope`'s shape: no node, no identity level, conditional `ProposalElementGroup`), pushing a `GlassTag`
on `Frame.glassTags` around their content's prepaint; the `glassEffect` layer below reads the innermost union tag at registration, so a tag written **outside**
the glass reaches it and one written inside does not (SwiftUI's modifier order). `GlassEffectContainer` is the same kind of scope. `glassEffectTransition` is
`ElementGroup.transition(_:)` over `.opacity` or `.identity`. The legacy spelling is `StyledElement.glassEffect(_:in:)` (a `Decoration` field `backgroundGlass`
in `DecorationExtras`, a `Hashable` `GlassBox`; `Shape & Hashable` as `clipShape`), painted where a material is. Exhaustive-switch sites that gained an arm:
`ProposalAnimation`'s snap list and `nativeWrapperNode` (migration note added).
2. **Member registration is prepaint, in layout coordinates** (`LG-I`): a glass layer inside an open container records `shape.geometry(in: bounds)`'s rect, radii
and kind, its `Glass` and its union key; the container emits at the start of its paint through the paint position's `activeOffset`, `activeClip` and
`activeOpacity`. **Named limit:** a scroll offset, render effect or opacity written *between* the container and a member is the container's, not the member's
(the blob is placed where the container paints). A `Path` member never registers and draws its own flat tint even inside a container; `.identity` registers
nothing; a **legacy** decorated glass inside a container draws its own record and never merges (`mergesInContainer: false`).
3. **Dark regular is the minimax line, not the least-squares line** (amends `LG-C`): through the readings 19 / 132 / 169 at backdrop 0 / 142 / 255 the minimax
fit is slope 0.588, intercept 33.75/255, i.e. **grey 0.321 at alpha 0.412**, off by at most **14.8/255** at all three points (a least-squares line is off by
19.6 at grey); `LG-C`'s "exact at black" is withdrawn. The other three rows are the table as written.
4. **The merge rule** (`LG-G`, `LG-H`): two members join when their `Glass` values are equal and `2 × gap < spacing` (`gap` the distance between their
bounding rectangles; a circle's diagonal neighbour is judged by its box, the smooth-min then bridges only what its true distance allows) or when they share a
union key (glass need not be equal; the first member's glass wins); joins are transitive (union-find, tree order); each set is cut in greedy chunks of four by
`GlassReference.chunks`; a chunk whose members all share one union key blends at `max(spacing, 2 × widest gap + 2)`. The record's bounds are the union of the
chunk's members **padded by `k/4 + 1` points** (the smooth-min bulges `k/4` past the members' union), members normalised to the padded bounds.
5. **Constants** (`GlassLook`, tunable in one place, human check LG1): lens band `min(0.5 × shortest member side, 12)` pt, lens depth `0.5 × band`, rim alpha
0.45 light and 0.30 dark, press lift 0.12.
6. **`interactive` is a press lift only** (`LG-J`): `press` is 1 while the element's own pointer press is held over it (`isActive && isHovered`, paint-only),
else 0; **no hover lift** (the record has one weight, and the spec's test 30 pins 1 then 0), no animation (it snaps). A bare proposal glass has no id that is ever
pressed and is inert (divergence 827); `.buttonStyle(.glass)` reaches it through the `Button`'s own `Decoration`.
7. **Buttons** (`LG-M`): `ButtonStyle.glass` is `.regular.interactive()`, `.glassProminent` is `.regular.tint(.accent).interactive()`; both take the bordered
metrics (padding and strut), drop the chrome's fill and border where still the chrome's own, set `cornerRadius = strut height / 2` (a capsule while the label is
no taller than the strut) and a `GlassBox(…, Capsule())` unless the caller wrote a glass; a glass button neither dims nor washes when pressed. **The prominent
label is not turned white** (no foreground environment on `Text` is spelled; LG2 compares the look). Disabled: `paintControl`'s 0.5 opacity scope applies to the
record.
8. **`Namespace` rides a `State<Bool>`** the wrapper never writes (`BindableState` conformance forwarding to the box's bind, one `$state<n>` slot, no eighth
reserved name): `Namespace.ID` is the declaring slot's `GlobalElementID` (`Hashable`, `Sendable`), `ID(owner: nil)` before binding (test 33).
9. **`fillGlass` lives in `MaterialTransparency.swift`**, beside `fillMaterial`, because `noMaterialSiteBypassesFillMaterial` (`MT-I`) exempts that file; the one
glass-tailed `fillBackdrop(…, glassTail:)` call is there (test 36 scans for it), and `fillBackdrop` gained `glassTail: ((inout MUIBackdrop) -> Void)?`.
Under Reduce Transparency every member is an ordinary opaque rect of the tinted table grey (alpha 1), unmerged.
10. **The flat arm is one rect per member** (`LG-L`): `insertThroughScopes` flat-maps a degraded backdrop through `CapturedPrimitive.degradingBackdrop()` (the
`depths:` path keeps the one-for-one `degradeBackdropToFlatTint()`, which now takes `flatTintRects[0]`, equal to `flatTintRect` for a material), pinned by test
29's blob arm.
11. **Retention** (`LG-I`): a container taints `prepaintLog` and `taintRetention("glassContainer")` (the `pasteButton` pair); a standalone glass is the existing
`fillBackdrop` paint, already in the paint log (test 26); no `AmbientKey` field, no `StateTable` write site beyond `Namespace`'s slot mark, no `noteNamed` site;
`Frame.glassGroups`, `glassTags` and `glassContainerPaintDepth` are scratch reset at `render`.
**Cost if wrong.** A constants edit (5), one table row (3), the union rule is one function (4).
