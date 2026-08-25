import MetalUI
import MetalUICore
import MetalUIRender

@MainActor
func runDemo() throws {
    let app = try App()

    try app.openWindow(title: "MetalUI — Milestone 0",
                       size: Size(width: Pixels(640), height: Pixels(400))) { scene, size in
        // One rounded rect with a border, centred, drawn entirely by an
        // analytic SDF — no rasterization, crisp at any scale factor.
        let boxSize = Size(width: ScaledPixels(320), height: ScaledPixels(180))
        let origin = Point(x: ScaledPixels((size.width.value - boxSize.width.value) / 2),
                           y: ScaledPixels((size.height.value - boxSize.height.value) / 2))

        scene.insert(MUIRect(
            bounds: Bounds(origin: origin, size: boxSize),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: size),
            background: .rgb(0x1E293B),
            borderColor: .rgb(0x38BDF8),
            cornerRadii: Corners(all: ScaledPixels(16)),
            borderWidths: Edges(all: ScaledPixels(3)),
            order: 0))
    }

    app.run()
}

try runDemo()
