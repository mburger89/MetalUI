import MetalUI

@MainActor
func runDemo() throws {
    let app = try App()

    try app.openWindow(title: "MetalUI — Milestone 0",
                       size: Size(width: Pixels(640), height: Pixels(400))) { scene, size, scale in
        // One rounded rect with a border, centred, drawn entirely by an
        // analytic SDF — no rasterization, crisp at any scale factor.
        //
        // Every constant is in logical points and converted with `scaled(by:)`,
        // so the border stays 3pt and the corners 16pt physically on a Retina
        // display rather than shrinking to half their intended size.
        let boxSize = Size(width: Pixels(320).scaled(by: scale),
                           height: Pixels(180).scaled(by: scale))
        let origin = Point(x: ScaledPixels((size.width.value - boxSize.width.value) / 2),
                           y: ScaledPixels((size.height.value - boxSize.height.value) / 2))

        scene.insert(MUIRect(
            bounds: Bounds(origin: origin, size: boxSize),
            contentMask: Bounds(origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                                size: size),
            background: .rgb(0x1E293B),
            borderColor: .rgb(0x38BDF8),
            cornerRadii: Corners(all: Pixels(16).scaled(by: scale)),
            borderWidths: Edges(all: Pixels(3).scaled(by: scale)),
            order: 0))
    }

    app.run()
}

try runDemo()
