# How do I draw shapes, gradients, shadows and my own GPU content?

MetalUI draws SwiftUI's shapes, paths, gradients, shadows and materials, and lets an app encode its
own GPU work into a surface that is composited like an `Image`. This guide is about the four
places the drawing model is not SwiftUI's: a path is rasterized on the CPU, a shadow belongs to a
leaf, a material blurs its backdrop only in some positions, and a GPU surface is not a `Canvas`.
The reference is [`api-overview.md`](../api-overview.md#shapes-and-images--a) and
[GPU surfaces](../api-overview.md#gpu-surfaces--m--d). The blocks are compiled and drawn into a
headless window, whose last scene a test reads ([`testing.md`](../testing.md);
[`README.md`](README.md#how-the-code-blocks-are-checked)); a headless window draws no pixels, so
nothing here claims what a shape looks like.

## How do I draw a custom shape with a gradient and a shadow?

Conform to `Shape` and write `path(in:)`, as in SwiftUI; the points are `Point<Pixels>` in the
rect's own space. `.fill` takes a colour or a `LinearGradient`, and `.shadow(color:radius:x:y:)`
follows. A path is rasterized on the CPU, in device pixels after every effect, and reaches the
renderer as an image, so it stays crisp under `scaleEffect` and a pan reuses its raster. A gradient is
rasterized the same way and interpolates in Oklab. `clipShape` of a path traps (divergence 91);
a rounded rectangle still clips.

```swift
import MetalUI

/// A diamond: four lines and a close.
struct DrawingDiamond: Shape {
    func path(in rect: Bounds<Pixels>) -> Path {
        Path { path in
            let width = rect.size.width.value, height = rect.size.height.value
            path.move(to: Point(x: Pixels(width / 2), y: Pixels(0)))
            path.addLine(to: Point(x: Pixels(width), y: Pixels(height / 2)))
            path.addLine(to: Point(x: Pixels(width / 2), y: Pixels(height)))
            path.addLine(to: Point(x: Pixels(0), y: Pixels(height / 2)))
            path.closeSubpath()
        }
    }
}

/// A gradient-filled diamond with a shadow below it.
@MainActor
func drawingBadgeRoot() -> some Element {
    VStack {
        DrawingDiamond()
            .fill(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))
            .frame(width: Pixels(60), height: Pixels(60))
            .shadow(color: .shadow, radius: Pixels(4), x: Pixels(0), y: Pixels(2))
    }
}
```

A test builds the root and finds the path drawn as an image in the scene (pin:
`theDrawingGuideAPathShapeDrawsAsOneImage`). A shadow's blur is sigma = radius, approximated by three
box blurs (divergence 105), and **a shadow belongs to each leaf it wraps** (divergence 104): a
`Text` is one leaf, a background and a border are two. To give a container one shadow, write
SwiftUI's own `.compositingGroup()` before it, so the group is one leaf:

```swift
/// Two squares that cast one shadow between them, not two.
@MainActor
func drawingGroupedRoot() -> some Element {
    VStack {
        HStack(spacing: Pixels(0)) {
            Rectangle().fill(Color.red).frame(width: Pixels(30), height: Pixels(30))
            Rectangle().fill(Color.blue).frame(width: Pixels(30), height: Pixels(30))
        }
        .compositingGroup()
        .shadow(radius: Pixels(4), x: Pixels(2), y: Pixels(2))
    }
}
```

`.compositingGroup()` alone changes nothing, and it does not composite an opacity written outside
it (divergence 205). SwiftUI's `drawingGroup()` and inner shadows are not offered. Under a
non-uniform scale both axes blur by one radius (divergence 105), and text and images under a scale
are resampled rather than re-rasterized (divergence 106).

## How do I put a blurred material behind a panel?

`.background(.regularMaterial)` (and `.thin`, `.thick`, `.ultraThin`, `.ultraThick` and `.bar`)
is one primitive: a Gaussian-blurred copy of what is behind the panel, with a tint over it
(divergence 166). It reads what has been drawn **before** the panel, so put it over the content
you want blurred, not under it.

```swift
/// A gradient with a material panel over it.
@MainActor
func drawingMaterialRoot() -> some Element {
    VStack {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing))
            Color.clear.frame(width: Pixels(120), height: Pixels(40)).background(.regularMaterial)
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}

/// The same panel under a shadow: the material degrades to its flat tint.
@MainActor
func drawingFlatMaterialRoot() -> some Element {
    VStack {
        Color.clear.frame(width: Pixels(120), height: Pixels(40))
            .background(.regularMaterial)
            .shadow(radius: Pixels(3), x: Pixels(2), y: Pixels(2))
    }
}
```

The first root draws exactly one backdrop record; the second draws none, because a material
inside a CPU-rasterized `.shadow`, `.blur` or `.compositingGroup()` under one is drawn as its flat
tint, by name (divergence 248; pin: `theDrawingGuideAMaterialIsOneBackdropAndDegradesUnderAShadow`,
`aMaterialInsideBlurShadowOrCompositingGroupDrawsItsFlatTint`). A `Path` fill degrades the same
way. With Reduce Transparency on, a material is an opaque grey instead (divergence 315; the last section below). A GPU surface drawn under `.blur(radius:)`
stays unblurred while its siblings blur (divergence 167).

## How do I draw into my own GPU surface?

There is **no `Canvas`** in MetalUI at this checkout: draw with shapes and paths above, or hand a
surface your own GPU work. `GPUSurface` is a portable leaf sized like a `Canvas` (the proposal, 10
on a nil axis) whose closure draws into an offscreen target that MetalUI composites as an `Image`
(clip, corners, opacity and transitions all apply). The closure runs on the main actor inside the
renderer's frame, before MetalUI's own pass, and **must not commit, present or wait** on the command
buffer. `.onDemand` draws on a new or resized target or a changed `value:`; read whatever the draw
depends on as `value:`, because reads inside the closure are untracked, and a `Canvas` instead
re-runs whenever its view's body does (divergence 103). A hidden, zero-size or fully clipped surface
does no GPU work. `.continuous` draws every painted frame and keeps the display link awake.

```swift
/// A surface that redraws when `version` changes.
@MainActor
func drawingSurfaceRoot(version: Int) -> some Element {
    VStack {
        GPUSurface(redraw: .onDemand, value: version) { context in
            context.clear(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}
```

The closure's context is `any GPUSurfaceContext`, with the portable `clear`; to encode real
commands downcast it to the backend's context, `MetalDrawContext` on the Metal renderer or the SDL
backend's `SDLGPUDrawContext`. `MetalView` is the Apple-only spelling whose closure takes the Metal
context directly, and traps if the renderer is not Metal's. A macOS-only block is wrapped in
`#if os(macOS)` so it still builds on Linux and Windows:

```swift
#if os(macOS)
import Metal

/// An app-owned Metal pass: clear the target, never commit.
@MainActor
func drawingMetalViewRoot() -> some Element {
    VStack {
        MetalView(redraw: .onDemand) { context in
            let pass = context.renderPassDescriptor(loadAction: .clear,
                                                    clearColor: MTLClearColor(red: 0, green: 0.4, blue: 0.2, alpha: 1))
            guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder.endEncoding()
        }
        .frame(width: Pixels(200), height: Pixels(120))
    }
}
#endif
```

A headless window builds both roots but draws no GPU surface, because no renderer runs your closure
(`testing.md`). Both are checked by building them, not by their pixels; look at the real window
for those. Text drawn over a surface is an ordinary `Text` overlay in the same `ZStack`.

## How do I put a label over a GPU surface?

Draw the label as an ordinary `Text` in a `ZStack` above the surface; the closure of a `GPUSurface`
has no text call. To size the surface from the label, ask for its size without laying it out:
`@Environment(\.textMeasurer)` is a get-only `TextMeasurer` whose `resolve(_:)` takes a `Text` (or a
`ProposalText`) and whose `ResolvedText.measure(in:)` answers the size the text would be laid out at
under a proposal. It resolves the font, weight and rich runs from the environment **at the point you
read it**, so a measure inside a `.font(.system(size: 26))` subtree is the larger text (pin:
`theMeasureReadsTheEnvironmentAtTheReadingPoint`), and a finite width wraps and a finite height caps
the lines (pin: `aNarrowProposalWrapsAndAShortHeightCapsTheLines`). The answer is the unrounded size
layout gives the text, so the frame a `Text` gets is it rounded to whole points, within one point (pin:
`aMeasuredTextIsTheFrameALaidOutTextGets`; divergence 296). An empty string measures 0 wide and one
line tall, where SwiftUI's `Text("")` view is 0 by 0 (divergence 295; pin:
`anEmptyStringMeasuresAsItLaysOut`). MetalUI has no `Canvas` or `GraphicsContext`, which is why the
measurer is an environment value; it has no public initialiser (pin:
`theMeasurerHasNoPublicInitialiserAndNoSetter`). Label the surface for accessibility, which also lets a test find it. The test below reads the surface's
accessibility frame 16 points wider and 8 taller than the label (pin:
`theDrawingGuideASurfaceIsSizedFromTheMeasuredLabel`).

```swift
/// A label over a surface, the surface sized from the label's measured width and height.
struct DrawingLabelled: Component {
    let title: String
    @Environment(\.textMeasurer) var measurer

    var content: some ElementGroup {
        let size = measurer.resolve(Text(title)).measure(in: Size(width: .infinity, height: .infinity))
        ZStack {
            GPUSurface(redraw: .onDemand, value: title) { context in
                context.clear(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
            }
            .frame(width: Pixels(size.width.value + 16), height: Pixels(size.height.value + 8))
            .accessibilityLabel("Chart")
            Text(title).id("label")
        }
    }
}

@MainActor
func drawingLabelledRoot(_ title: String) -> some Element {
    VStack { DrawingLabelled(title: title) }
}
```

## How do I make a material respect Reduce Transparency?

Read `@Environment(\.accessibilityReduceTransparency)`, SwiftUI's key; it is get-only outside the
module (pin: `aScopeCannotWriteReduceTransparency`). The window stamps it from the platform, and no
material needs your help: with it true **every** material site draws an opaque rect instead of a
backdrop, the scheme's tint grey at alpha 1, with no blur work (pin:
`everyMaterialSiteDrawsAnOpaqueRectUnderReduceTransparency`, `reduceTransparencyCostsNoBlurWork`). A
change repaints once and a repeat of the same value does not (pin:
`reduceTransparencyRedrawsOnceAndNotOnARepeat`). SDL answers `false` and never fires. The grey is
MetalUI's ruling, not a measured copy of SwiftUI's (divergence 315), and the key is read in the
environment so your own labels can follow it, as below (pin:
`theDrawingGuideAPanelFollowsReduceTransparency`); a test turns the setting on with
`TestWindow.setReduceTransparency(_:)` or the `accessibilityReduceTransparency` window option (pin:
`theWindowStampsReduceTransparencyFromItsPlatformWindow`).

`Material.tint(in:)` (MetalUI-only; SwiftUI exposes no such read) returns the grey-and-opacity a
material composites over its blur in a scheme, for a role that must hide a given share of the
backdrop: a panel colour of opacity `t` over a material of opacity `m` hides `1 - (1 - t)(1 - m)`,
so to hide `g` take `t = 1 - (1 - g) / (1 - m)`, valid for `g >= m` (pin:
`materialTintMatchesTheFillTableForEveryKindAndScheme`, `theGlassIdentityHoldsForTheSolvedTint`).
The values are the fitted table, so a retune moves them, not the signature (pin:
`theDrawingGuideATintOpacityIsTheTable`).

```swift
/// A panel that follows the system's Reduce Transparency setting.
struct DrawingPanel: Component {
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency

    var content: some ElementGroup {
        Text(reduceTransparency ? "Opaque panel" : "Glass panel")
            .padding(Pixels(8))
            .background(.regularMaterial)
    }
}

@MainActor
func drawingPanelRoot() -> some Element {
    VStack { DrawingPanel() }
}

/// The opacity a material's tint draws at in a scheme.
func drawingTintOpacity(of material: Material, in scheme: ColorScheme) -> Float {
    material.tint(in: scheme).resolve(in: EnvironmentValues()).opacity
}
```

## Divergences you will hit

Each row is in [`divergences.md`](../divergences.md); the list is checked against it.

- divergence 91: `clipShape` of a path traps; a rounded rectangle clips.
- divergence 103: a GPU surface redraws on a new target or a changed `value:`, not on every body.
- divergence 104: a shadow is per drawn leaf.
- divergence 105: a shadow's blur is three box blurs approximating a Gaussian.
- divergence 106: text and images under a scale are resampled.
- divergence 107: an accessibility frame under a rotation off a right angle is the transformed bounding box (40.31 square at 45° for a 33 × 24 view, SwiftUI reports 35.36).
- divergence 108: a legacy element's render effects wrap the whole element.
- divergence 109: a clip between two nested rotations becomes its bounding box.
- divergence 166: a material is a blurred backdrop with a tint.
- divergence 167: a GPU surface under `.blur(radius:)` is drawn unblurred.
- divergence 205: an opacity outside `compositingGroup()` is not composited.
- divergence 248: a material inside a CPU-rasterized shadow, blur or group draws its flat tint.
- divergence 295: an empty `Text` measures one line tall.
- divergence 296: a text measurer is an environment value; MetalUI has no `Canvas`.
- divergence 315: a material under Reduce Transparency is the scheme's tint grey at alpha 1.

Next: [cross-platform](cross-platform.md), and [`api-overview.md`](../api-overview.md) for every
declaration.
