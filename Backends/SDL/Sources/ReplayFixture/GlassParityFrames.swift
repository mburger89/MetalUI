// The three Liquid Glass parity scenes (ruling `LG-O`): frames 12-14 of
// `swift run Replay --portable --record`, shared by that tool and the SDL tests
// so the recorded frames and the tests' frames cannot drift apart. Imports only
// MetalUIScene and the shader types, like the rest of this library.
//
//   12: one glass, regular-style tint, lens and rim over a two-axis field
//   13: a two-member blob (blend radius 96 over a 41.6-pixel gap: merged)
//   14: a clear glass with a press lift, turned 25 degrees about its centre
//
// Every pixel under a glass reads the scene's field, which varies on both axes
// at every scale, so a lens that reads the wrong axis, a rim with the wrong
// light direction or a fold of the wrong members shows.

import MetalUIScene
import MetalUIShaderTypes

public enum GlassParityFrames {
    /// The frames' size: all three are 320 x 200.
    public static let size = (width: 320, height: 200)
    /// The frame indices of `Replay --record`.
    public static let indices = 12...14

    private static func bounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
        MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
    }
    private static func corners(_ r: Float) -> MUICorners {
        MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r)
    }

    /// 16-pixel cells in a hue ramp at alternating lightness (`Replay`'s backdrop field).
    private static func field(_ scene: inout Scene) {
        let full = bounds(0, 0, Float(size.width), Float(size.height))
        let cell = 16
        for gy in 0..<((size.height + cell - 1) / cell) {
            for gx in 0..<((size.width + cell - 1) / cell) {
                scene.insert(MUIRect(
                    bounds: bounds(Float(gx * cell), Float(gy * cell), Float(cell), Float(cell)),
                    contentMask: full, maskCornerRadii: corners(0),
                    background: MUIHsla(h: Float((gx * 7 + gy * 3) % 12) / 12, s: 0.8, l: (gx + gy) % 2 == 0 ? 0.35 : 0.65, a: 1),
                    borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0), cornerRadii: corners(0),
                    borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0))
            }
        }
    }

    /// A glass record: the six material lanes and the tail (`LG-B`). `members` empty is one
    /// member (the record itself).
    public static func record(_ box: MUIBounds, radius: Float, tint: MUIHsla, sigma: Float = 52, opacity: Float = 1,
                              lensDepth: Float, band: Float, rim: Float, dark: Bool = false,
                              blendK: Float = 0, press: Float = 0, pressLift: Float = 0,
                              members: [(MUIBounds, MUICorners)] = []) -> MUIBackdrop {
        var r = MUIBackdrop(bounds: box, contentMask: bounds(0, 0, 4096, 4096), maskCornerRadii: corners(0),
                            cornerRadii: corners(radius), tint: tint, order: 0, shape: 0, sigma: sigma, opacity: opacity)
        var flags: UInt32 = 1 | 2
        if dark { flags |= 4 }
        flags |= UInt32(min(max(members.count, 1), 7)) << 3
        r.glassFlags = flags
        r.lensDepth = lensDepth; r.band = band; r.rimStrength = rim
        r.blendK = blendK; r.press = press; r.pressLift = pressLift
        let slots = members.map { MUIGlassMember(bounds: $0.0, radii: $0.1) }
        if slots.count > 0 { r.member0 = slots[0] }
        if slots.count > 1 { r.member1 = slots[1] }
        if slots.count > 2 { r.member2 = slots[2] }
        if slots.count > 3 { r.member3 = slots[3] }
        return r
    }

    /// The field alone, finalized: the frames without their glass.
    public static func fieldScene() -> Scene {
        var scene = Scene()
        field(&scene)
        scene.finalize()
        return scene
    }

    /// Frame `index` (12...14), finalized.
    public static func scene(index: Int) -> Scene {
        var scene = Scene()
        field(&scene)
        switch index {
        case 12:
            scene.insert(record(bounds(40, 30, 240, 120), radius: 40, tint: MUIHsla(h: 0, s: 0, l: 0.9, a: 0.18),
                                lensDepth: 10, band: 18, rim: 0.45))
        case 13:
            scene.insert(record(bounds(30, 40, 260, 100), radius: 50, tint: MUIHsla(h: 0.6, s: 0.5, l: 0.5, a: 0.15),
                                lensDepth: 8, band: 16, rim: 0.4, dark: true, blendK: 96,
                                members: [(bounds(0, 0, 0.42, 1), corners(0.5)), (bounds(0.58, 0, 0.42, 1), corners(0.5))]))
        default:
            // cos 25, sin 25; a turn about (160, 100), outer mask the whole frame.
            let c: Float = 0.9063078, s: Float = 0.4226183
            let turn = MUITransform(a: c, b: s, c: -s, d: c, tx: 160 - c * 160 + s * 100, ty: 100 - s * 160 - c * 100,
                                    pixelScale: 1, _reserved: 0,
                                    outerMask: bounds(0, 0, Float(size.width), Float(size.height)), outerMaskRadii: corners(0))
            scene.insert(record(bounds(60, 55, 200, 90), radius: 30, tint: MUIHsla(h: 0, s: 0, l: 1, a: 0.1),
                                lensDepth: 12, band: 20, rim: 0.5, press: 0.5, pressLift: 0.2), transform: turn)
        }
        scene.finalize()
        return scene
    }
}
