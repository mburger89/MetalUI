import Metal
import MetalUICore
import MetalUIPath
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUIRender

// Shared fixtures of the Liquid Glass lane-A tests (`GlassSceneTests`, `GlassRenderTests`).

func glassBounds(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
let glassSquare = MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0)
let glassWide = glassBounds(0, 0, 4096, 4096)
let glassNoColor = MUIHsla(h: 0, s: 0, l: 0, a: 0)

func glassGray(_ l: Float, alpha: Float = 1) -> MUIHsla { MUIHsla(h: 0, s: 0, l: l, a: alpha) }
let glassRedHSLA = MUIHsla(h: 0, s: 1, l: 0.5, a: 1)

/// An HSLA of the straight-alpha sRGB colour `(r, g, b, a)`.
func glassHSLA(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) -> MUIHsla {
    let hi = max(r, g, b), lo = min(r, g, b)
    let l = (hi + lo) / 2
    guard hi != lo else { return MUIHsla(h: 0, s: 0, l: l, a: a) }
    let d = hi - lo
    let s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo)
    var h: Float
    if hi == r { h = (g - b) / d + (g < b ? 6 : 0) } else if hi == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
    h /= 6
    return MUIHsla(h: h, s: s, l: l, a: a)
}

func glassSolid(_ b: MUIBounds, _ color: MUIHsla) -> MUIRect {
    MUIRect(bounds: b, contentMask: glassWide, maskCornerRadii: glassSquare, background: color,
            borderColor: glassNoColor, cornerRadii: glassSquare,
            borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0), order: 0, shape: 0)
}

/// A glass record: the six material lanes plus the glass tail. One member reads the record itself.
func glassRecord(_ b: MUIBounds, tint: MUIHsla = glassNoColor, radius: Float = 0, sigma: Float = 8, opacity: Float = 1,
                 ellipse: Bool = false, lensRim: Bool = false, dark: Bool = false,
                 lensDepth: Float = 0, band: Float = 0, rim: Float = 0,
                 blendK: Float = 0, press: Float = 0, pressLift: Float = 0,
                 members: [(MUIBounds, MUICorners)] = [], ellipses: [Bool] = []) -> MUIBackdrop {
    var r = MUIBackdrop(bounds: b, contentMask: glassWide, maskCornerRadii: glassSquare,
                        cornerRadii: MUICorners(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius),
                        tint: tint, order: 0, shape: ellipse ? 1 : 0, sigma: sigma, opacity: opacity)
    var flags: UInt32 = 1
    if lensRim { flags |= 2 }
    if dark { flags |= 4 }
    flags |= UInt32(min(max(members.count, 1), 7)) << 3
    for (k, e) in ellipses.prefix(4).enumerated() where e { flags |= 1 << UInt32(6 + k) }
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

/// The reference record of a glass `MUIBackdrop` (straight tint from `rgba`).
func referenceRecord(_ r: MUIBackdrop, tint rgba: SIMD4<Float>) -> GlassReference.Record {
    var out = GlassReference.Record(originX: r.bounds.origin.x, originY: r.bounds.origin.y,
                                    width: r.bounds.size.width, height: r.bounds.size.height)
    out.topLeft = r.cornerRadii.topLeft; out.topRight = r.cornerRadii.topRight
    out.bottomRight = r.cornerRadii.bottomRight; out.bottomLeft = r.cornerRadii.bottomLeft
    out.isEllipse = r.shape & 0xFF == 1
    out.tint = rgba
    out.opacity = r.opacity
    out.flags = r.glassFlags
    out.lensDepth = r.lensDepth; out.band = r.band; out.rimStrength = r.rimStrength
    out.blendK = r.blendK; out.press = r.press; out.pressLift = r.pressLift
    out.members = [r.member0, r.member1, r.member2, r.member3].map {
        GlassReference.Member(x: $0.bounds.origin.x, y: $0.bounds.origin.y,
                              width: $0.bounds.size.width, height: $0.bounds.size.height,
                              topLeft: $0.radii.topLeft, topRight: $0.radii.topRight,
                              bottomRight: $0.radii.bottomRight, bottomLeft: $0.radii.bottomLeft)
    }
    return out
}

func glassTargetSize(_ w: Int, _ h: Int) -> Size<DevicePixels> {
    Size(width: DevicePixels(Int32(w)), height: DevicePixels(Int32(h)))
}

/// `(r, g, b, a)` of a BGRA readback, as 0...255 floats.
func glassPixel(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [Float] {
    let i = (y * width + x) * 4
    return [Float(pixels[i + 2]), Float(pixels[i + 1]), Float(pixels[i]), Float(pixels[i + 3])]
}

@MainActor func glassRenderer() throws -> Renderer {
    guard let device = MTLCreateSystemDefaultDevice() else { throw GlassTestError.noDevice }
    return try Renderer(device: device)
}
enum GlassTestError: Error { case noDevice }

/// A field varying on both axes: `block`-pixel squares coloured by both indices, premultiplied
/// opaque floats, row-major, plus the rects that draw it.
func glassField(width: Int, height: Int, block: Int = 6) -> (pixels: [Float], rects: [MUIRect]) {
    var pixels = [Float](repeating: 0, count: width * height * 4)
    var rects: [MUIRect] = []
    for by in 0..<((height + block - 1) / block) { for bx in 0..<((width + block - 1) / block) {
        let r = Float((bx * 37) % 8) / 7, g = Float((by * 61) % 8) / 7, b = Float(((bx + by) * 3) % 5) / 4
        rects.append(glassSolid(glassBounds(Float(bx * block), Float(by * block), Float(block), Float(block)), glassHSLA(r, g, b)))
        for y in (by * block)..<min((by + 1) * block, height) { for x in (bx * block)..<min((bx + 1) * block, width) {
            let i = (y * width + x) * 4
            pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 1
        } }
    } }
    return (pixels, rects)
}

/// Bilinear read at continuous pixel coordinates (texel centres at `i + ½`), clamped to the edge.
func glassBilinear(_ pixels: [Float], width: Int, height: Int, x: Float, y: Float) -> SIMD4<Float> {
    let fx = x - 0.5, fy = y - 0.5
    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
    let tx = fx - Float(x0), ty = fy - Float(y0)
    func at(_ xi: Int, _ yi: Int) -> SIMD4<Float> {
        let cx = min(max(xi, 0), width - 1), cy = min(max(yi, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }
    let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
    let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
    return top * (1 - ty) + bottom * ty
}
