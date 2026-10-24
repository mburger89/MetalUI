import Foundation
import Testing
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUISDL
import SDLReplay
import ReplayFixture
import SDLBridge
#if canImport(Metal)
import Metal
import simd
import MetalUI
#endif

// Liquid Glass on the SDL GPU renderer (rulings `LG-B`, `LG-D`, `LG-G`, `LG-O`, `TE-AD`;
// spec `2026-10-23-liquid-glass-design.md` §3 and §5, tests 14-16). A glass is a
// `.backdrop` record whose `glassFlags` bit 0 is set: `replay.hlsl` reads the 256-byte
// record as sixteen `float4` lanes, folds the members' signed distances, reads the blurred
// level and (with the lens on) a SHARP copy of the frame region, and adds the tint, the press
// lift and the rim. Every expected pixel is computed from the record and a Float restatement
// of `GlassReference` (`MetalUIPath`'s is `package` access of the root package; this is another
// package), over the blur reference of `SDLBackdropTests`. Every helper arms the run-loop exit
// check (record §61 §9): the offscreen renderer initialises SDL video.

private func gmb(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> MUIBounds {
    MUIBounds(origin: MUIPoint(x: x, y: y), size: MUISize(width: w, height: h))
}
private func gcorners(_ r: Float) -> MUICorners { MUICorners(topLeft: r, topRight: r, bottomRight: r, bottomLeft: r) }

/// `(r, g, b, a)` of a BGRA readback, 0...255.
private func gpx(_ pixels: [UInt8], _ x: Int, _ y: Int, width: Int) -> [Int] {
    let i = (y * width + x) * 4
    return [Int(pixels[i + 2]), Int(pixels[i + 1]), Int(pixels[i]), Int(pixels[i + 3])]
}

// MARK: - The reference (the arithmetic of `GlassReference`, re-stated)

private enum Ref {
    static func rectSDF(_ px: Float, _ py: Float, _ hw: Float, _ hh: Float, _ radius: Float) -> Float {
        let dx = abs(px) - hw + radius, dy = abs(py) - hh + radius
        let ox = max(dx, 0), oy = max(dy, 0)
        return (ox * ox + oy * oy).squareRoot() + min(max(dx, dy), 0) - radius
    }
    static func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
        guard k > 0 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * k * 0.25
    }
    static func radius(_ rx: Float, _ ry: Float, _ c: MUICorners) -> Float {
        if rx < 0 { return ry < 0 ? c.topLeft : c.bottomLeft }
        return ry < 0 ? c.topRight : c.bottomRight
    }
    static func memberSDF(_ r: MUIBackdrop, _ k: Int, _ x: Float, _ y: Float) -> Float {
        let m = [r.member0, r.member1, r.member2, r.member3][k]
        let w = r.bounds.size.width, h = r.bounds.size.height, shorter = min(w, h)
        let mw = m.bounds.size.width * w, mh = m.bounds.size.height * h
        let cx = r.bounds.origin.x + m.bounds.origin.x * w + mw / 2
        let cy = r.bounds.origin.y + m.bounds.origin.y * h + mh / 2
        let rx = x - cx, ry = y - cy
        let c = MUICorners(topLeft: m.radii.topLeft * shorter, topRight: m.radii.topRight * shorter,
                           bottomRight: m.radii.bottomRight * shorter, bottomLeft: m.radii.bottomLeft * shorter)
        return rectSDF(rx, ry, mw / 2, mh / 2, radius(rx, ry, c))
    }
    static func count(_ r: MUIBackdrop) -> Int { min(max(Int((r.glassFlags >> 3) & 7), 1), 4) }
    static func sdf(_ r: MUIBackdrop, _ x: Float, _ y: Float) -> Float {
        if count(r) <= 1 {
            let hw = r.bounds.size.width / 2, hh = r.bounds.size.height / 2
            let rx = x - (r.bounds.origin.x + hw), ry = y - (r.bounds.origin.y + hh)
            return rectSDF(rx, ry, hw, hh, radius(rx, ry, r.cornerRadii))
        }
        var d = memberSDF(r, 0, x, y)
        for k in 1..<count(r) { d = smin(d, memberSDF(r, k, x, y), r.blendK) }
        return d
    }
    static func normal(_ r: MUIBackdrop, _ x: Float, _ y: Float) -> (Float, Float) {
        let gx = sdf(r, x + 1, y) - sdf(r, x - 1, y), gy = sdf(r, x, y + 1) - sdf(r, x, y - 1)
        let l = max((gx * gx + gy * gy).squareRoot(), 1.0e-6)
        return (gx / l, gy / l)
    }
    /// Premultiplied RGBA of one pixel of an untransformed glass (`opacity` and the clip are 1).
    static func shade(_ r: MUIBackdrop, tint rgba: SIMD4<Float>, _ x: Float, _ y: Float, blurred: SIMD4<Float>,
                      sharp: (Float, Float) -> SIMD4<Float>) -> SIMD4<Float> {
        let d = sdf(r, x, y)
        let c = min(max(0.5 - d, 0), 1)
        var backdrop = blurred
        let lens = r.glassFlags & 2 != 0
        let t = r.band > 0 ? min(max(-d / r.band, 0), 1) : 1
        var n: (Float, Float) = (0, 0)
        if lens && t < 1 {
            n = normal(r, x, y)
            let u = 1 - t, weight = u * u
            let depth = r.lensDepth * weight
            backdrop = blurred + (sharp(x - n.0 * depth, y - n.1 * depth) - blurred) * weight
        }
        let tint = SIMD4(rgba.x * rgba.w, rgba.y * rgba.w, rgba.z * rgba.w, rgba.w)
        var base = tint + backdrop * (1 - tint.w)
        let lift = r.press * r.pressLift
        base = SIMD4(repeating: lift) + base * (1 - lift)
        if lens && t < 1 {
            let u = 1 - t, u2 = u * u
            let rim = r.rimStrength * (u2 * u2) * (0.65 + 0.35 * (n.0 * -0.70710678 + n.1 * -0.70710678))
            base = SIMD4(repeating: rim) + base * (1 - rim)
        }
        return base * (c * r.opacity)
    }
}

/// Bilinear read at continuous pixel coordinates (texel centres at `i + ½`), clamped to the edge.
private func bilinear(_ pixels: [Float], width: Int, height: Int, x: Float, y: Float) -> SIMD4<Float> {
    let fx = x - 0.5, fy = y - 0.5
    let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
    let tx = fx - Float(x0), ty = fy - Float(y0)
    func at(_ xi: Int, _ yi: Int) -> SIMD4<Float> {
        let i = (min(max(yi, 0), height - 1) * width + min(max(xi, 0), width - 1)) * 4
        return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }
    let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
    let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
    return top * (1 - ty) + bottom * ty
}

/// The field with the record's region replaced by what the glass leaves there, over the
/// region's own blur (the blur is clamped to it) and its sharp pixels for the lens.
private func fieldWithGlass(_ field: [Float], width w: Int, height h: Int, region: Scene.BackdropRegion,
                            record: MUIBackdrop, grayTint l: Float, alpha a: Float) -> [Float] {
    var crop = [Float](repeating: 0, count: region.width * region.height * 4)
    for y in 0..<region.height { for x in 0..<region.width { for c in 0..<4 {
        crop[(y * region.width + x) * 4 + c] = field[((region.y + y) * w + region.x + x) * 4 + c]
    } } }
    let soft = blurred(crop, width: region.width, height: region.height, sigma: record.sigma)
    var out = field
    for y in 0..<region.height { for x in 0..<region.width {
        let b = SIMD4(soft[(y * region.width + x) * 4], soft[(y * region.width + x) * 4 + 1],
                      soft[(y * region.width + x) * 4 + 2], soft[(y * region.width + x) * 4 + 3])
        let px = Float(region.x + x) + 0.5, py = Float(region.y + y) + 0.5
        let src = Ref.shade(record, tint: SIMD4(l, l, l, a), px, py, blurred: b) { sx, sy in
            bilinear(crop, width: region.width, height: region.height, x: sx - Float(region.x), y: sy - Float(region.y))
        }
        let i = ((region.y + y) * w + region.x + x) * 4
        for c in 0..<4 { out[i + c] = src[c] + (1 - src.w) * field[i + c] }
    } }
    return out
}

private func worstLevels(_ pixels: [UInt8], width: Int, expected: [Float]) -> (levels: Float, at: Int) {
    var worst: Float = 0, at = 0
    for p in 0..<(expected.count / 4) {
        let got = gpx(pixels, p % width, p / width, width: width)
        for c in 0..<4 {
            let off = abs(Float(got[c]) - expected[p * 4 + c] * 255)
            if off > worst { worst = off; at = p }
        }
    }
    return (worst, at)
}

// MARK: - Harness

@MainActor
private func offscreenRenderer(_ width: Int, _ height: Int) throws -> SDLWindowRenderer {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    return try SDLWindowRenderer(offscreenWidth: width, height: height)
}

@MainActor
private func draw(_ renderer: SDLWindowRenderer, _ scene: Scene, width: Int, height: Int) throws -> [UInt8] {
    try #require(renderer.beginFrame() != nil)
    try #require(renderer.finishFrame(scene: scene, atlas: GlyphAtlas(width: 16, height: 16), surfaces: []))
    return try renderer.readPixels(width: width, height: height)
}

private let gray = MUIHsla(h: 0, s: 0, l: 0.5, a: 0.2)

// MARK: - Tests

/// **15** (`LG-D`, `LG-G`, `TE-AD`). A single-member glass with the lens and the rim, and a
/// two-member blob folded at `blendK`, over a field with structure on both axes, equal the
/// restated reference within `tolerance` levels over every pixel of their regions: the
/// coverage (one member the rect SDF, two the smooth minimum), the blurred read, the sharp
/// copy's bilinear read at `p − n·d(1 − t)²`, the tint source-over, the press lift and the rim.
/// On Linux this is lavapipe's HLSL, on macOS SDL's Metal driver's. Mutations: `smin`'s `k/4`
/// to `k/2` in `replay.hlsl` (the blob scene), the rim's light direction flipped (the rim).
@Test @MainActor func aGlassFrameOnLavapipeMatchesTheReference() throws {
    let (w, h) = (120, 90)
    let renderer = try offscreenRenderer(w, h)
    let tolerance: Float = 4

    // One member: a rounded rect with the lens, the rim and a tint.
    var (single, field) = cellField(width: w, height: h)
    let one = GlassParityFrames.record(gmb(20, 12, 80, 56), radius: 20, tint: gray, sigma: 16,
                                       lensDepth: 8, band: 12, rim: 0.5, press: 0.5, pressLift: 0.25)
    single.insert(one)
    single.finalize()
    let region1 = try #require(single.backdropRegion(0, target: (w, h)))
    let drawn1 = try draw(renderer, single, width: w, height: h)
    let expected1 = fieldWithGlass(field, width: w, height: h, region: region1, record: one, grayTint: 0.5, alpha: 0.2)
    let off1 = worstLevels(drawn1, width: w, expected: expected1)
    #expect(off1.levels <= tolerance, "one member: worst channel \(off1.levels) levels off at pixel \(off1.at % w),\(off1.at / w)")
    #expect(renderer.lastBackdropSplits == 1 && renderer.lastBackdropBlurs == 1)

    // The same scene without the glass differs, and without the lens the edge differs from with it
    // (the instrument: a branch that did nothing would equal the reference of a bare field).
    var bare = cellField(width: w, height: h).scene
    bare.finalize()
    #expect(try draw(renderer, bare, width: w, height: h) != drawn1)

    // Two members, merged: a neck the single-member SDF cannot make.
    var (blob, field2) = cellField(width: w, height: h)
    let two = GlassParityFrames.record(gmb(10, 15, 100, 60), radius: 30, tint: gray, sigma: 16,
                                       lensDepth: 6, band: 10, rim: 0.4, blendK: 48,
                                       members: [(gmb(0, 0, 0.4, 1), gcorners(0.5)), (gmb(0.6, 0, 0.4, 1), gcorners(0.5))])
    blob.insert(two)
    blob.finalize()
    let region2 = try #require(blob.backdropRegion(0, target: (w, h)))
    let drawn2 = try draw(renderer, blob, width: w, height: h)
    let expected2 = fieldWithGlass(field2, width: w, height: h, region: region2, record: two, grayTint: 0.5, alpha: 0.2)
    let off2 = worstLevels(drawn2, width: w, expected: expected2)
    #expect(off2.levels <= tolerance, "two members: worst channel \(off2.levels) levels off at pixel \(off2.at % w),\(off2.at / w)")
    // The gap between the members (x 50, y 45) is covered through the neck: merged (k 48 > 2 × 20).
    let neck = gpx(drawn2, 60, 45, width: w)
    let bareNeck = gpx(try draw(renderer, bare, width: w, height: h), 60, 45, width: w)
    #expect(neck != bareNeck, "the neck between the members is glass: \(neck)")
}

/// **15b** (`LG-W`). A glass whose lens cannot get its sharp copy (the blur succeeded) draws its flat
/// arm, the same pixels a record whose pool fails draws, and not the lens reading the blurred texture at
/// the wrong scale; the control frame differs, and counts its sharp copy. Mutation: drop the
/// `results[k].sharp < 0` branch in `SDLBridge.c`.
@Test @MainActor func aGlassWhoseSharpCopyFailsDrawsItsFlatArm() throws {
    let (w, h) = (120, 90)
    let renderer = try offscreenRenderer(w, h)
    var (scene, _) = cellField(width: w, height: h)
    scene.insert(GlassParityFrames.record(gmb(20, 12, 80, 56), radius: 20, tint: gray, sigma: 16,
                                          lensDepth: 8, band: 12, rim: 0.5))
    scene.finalize()
    let normal = try draw(renderer, scene, width: w, height: h)
    #expect(renderer.lastGlassSharpCopies == 1)
    renderer.glassSharpCopyFailsAllocation = true
    let failed = try draw(renderer, scene, width: w, height: h)
    renderer.glassSharpCopyFailsAllocation = false
    #expect(renderer.lastGlassSharpCopies == 0, "the sharp copy failed")
    renderer.backdropPoolFailsAllocation = true
    let flat = try draw(renderer, scene, width: w, height: h)
    renderer.backdropPoolFailsAllocation = false
    #expect(failed == flat, "a record without its sharp copy draws the flat arm")
    #expect(failed != normal, "the lens is on in the control frame")
}

/// **16** (`LG-B`, `LG-O`). The bridge uploads the whole 256-byte record, at its stride:
/// record 0 has four members and member 3's bottom-left radius (the LAST lane's last
/// field) rounds that corner away; record 1, a second 256-byte slot, has two members and a
/// press lift in lane 7 (the lift whitens a blue to (128, 128, 255)); the gap between
/// record 1's members is not covered (a blend radius of 0 is a plain minimum). A 96-byte
/// upload per record would read zeros for the tail (no members: no coverage) and the second
/// record from the middle of the first. Mutation: upload 96 bytes per record.
@Test @MainActor func theSDLBridgeUploadsTheWholeRecord() throws {
    let (w, h) = (160, 100)
    let renderer = try offscreenRenderer(w, h)
    let red = MUIHsla(h: 0, s: 1, l: 0.5, a: 1), blue = MUIHsla(h: 2.0 / 3.0, s: 1, l: 0.5, a: 1)
    var scene = Scene()
    scene.insert(MUIRect(bounds: gmb(0, 0, 160, 100), contentMask: gmb(0, 0, 4096, 4096), maskCornerRadii: gcorners(0),
                         background: MUIHsla(h: 0, s: 0, l: 0, a: 1), borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
                         cornerRadii: gcorners(0), borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
                         order: 0, shape: 0))
    var last = gcorners(0)
    last.bottomLeft = 0.5
    var first = GlassParityFrames.record(
        gmb(0, 0, 160, 40), radius: 0, tint: red, sigma: 8, lensDepth: 0, band: 0, rim: 0,
        members: [(gmb(0, 0, 0.2, 1), gcorners(0)), (gmb(0.25, 0, 0.2, 1), gcorners(0)),
                  (gmb(0.5, 0, 0.2, 1), gcorners(0)), (gmb(0.75, 0, 0.25, 1), last)])
    first.glassFlags &= ~UInt32(2)           // no lens, no rim: the tint alone
    var second = GlassParityFrames.record(
        gmb(0, 55, 160, 40), radius: 0, tint: blue, sigma: 8, lensDepth: 0, band: 0, rim: 0, press: 1, pressLift: 0.5,
        members: [(gmb(0, 0, 0.3, 1), gcorners(0)), (gmb(0.5, 0, 0.5, 1), gcorners(0))])
    second.glassFlags &= ~UInt32(2)
    scene.insert(first)
    scene.insert(second)
    scene.finalize()
    let pixels = try draw(renderer, scene, width: w, height: h)
    #expect(gpx(pixels, 125, 3, width: w) == [255, 0, 0, 255], "member 3's square corner is red")
    #expect(gpx(pixels, 123, 37, width: w) == [0, 0, 0, 255], "member 3's rounded bottom-left corner is the field")
    #expect(gpx(pixels, 36, 20, width: w) == [0, 0, 0, 255], "the gap between members 0 and 1 (x 32...40) is the field")
    #expect(gpx(pixels, 5, 20, width: w) == [255, 0, 0, 255] && gpx(pixels, 56, 20, width: w) == [255, 0, 0, 255])
    #expect(gpx(pixels, 96, 20, width: w) == [255, 0, 0, 255] && gpx(pixels, 76, 20, width: w) == [0, 0, 0, 255],
            "members 1 and 2 are covered, the gap between them (72...80) is not")
    // Record 1: the second slot, two members, the lane-7 lift.
    let lifted = gpx(pixels, 100, 75, width: w)
    #expect(abs(lifted[0] - 128) <= 1 && abs(lifted[1] - 128) <= 1 && lifted[2] == 255 && lifted[3] == 255,
            "press 1 × lift 0.5 whitens blue: \(lifted)")
    #expect(gpx(pixels, 60, 75, width: w) == [0, 0, 0, 255], "the gap between record 1's members is the field")
    #expect(abs(gpx(pixels, 10, 75, width: w)[0] - 128) <= 1, "record 1's first member")
}

#if canImport(Metal)
/// The Metal renderer's pixels of `scene` (as `Replay`'s `metalPixels`).
@MainActor
private func metalPixels(_ scene: Scene, width: Int, height: Int) throws -> [UInt8] {
    guard let device = MTLCreateSystemDefaultDevice() else { throw GlassTestFailure.noDevice }
    let renderer = try Renderer(device: device)
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead]
    guard let target = renderer.device.makeTexture(descriptor: descriptor),
          let command = renderer.commandQueue.makeCommandBuffer() else { throw GlassTestFailure.noDevice }
    renderer.upload(GlyphAtlas(width: 16, height: 16))
    try renderer.encode(scene, view: SurfaceView(
        colorTexture: target, viewport: MTLViewport(originX: 0, originY: 0, width: Double(width), height: Double(height), znear: 0, zfar: 1),
        projection: matrix_identity_float4x4), in: command)
    command.commit()
    command.waitUntilCompleted()
    guard command.status == .completed else { throw GlassTestFailure.gpuFailure }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    return bytes
}
private enum GlassTestFailure: Error { case noDevice, gpuFailure }

/// **14** (`LG-O`, `BB-J`, `TE-AD`). Frames 12, 13 and 14 of `Replay --record` — a lensed,
/// rimmed glass, a merged two-member blob and a clear glass turned 25 degrees with a press lift —
/// drawn by the production Metal renderer and by SDL's renderer through its Metal driver agree
/// within `BB-J`'s backdrop tolerance (`ParityTolerance.insideBackdrops`), and every frame is
/// not the bare field (so agreement is not two renderers drawing nothing). macOS only: the
/// Metal side needs Metal; Linux's and Windows's replay of the same frames is
/// `PortableReplay` over the recorded fixtures. Mutation: change the rim exponent in
/// `replay.hlsl` only.
@Test(arguments: GlassParityFrames.indices) @MainActor
func theThreeGlassParityFramesMatchMetalWithinTheBackdropTolerance(index: Int) throws {
    #if os(macOS)
    armMainRunLoopExitCheck()
    #endif
    let (w, h) = GlassParityFrames.size
    let scene = GlassParityFrames.scene(index: index)
    let projection: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    let metal = try metalPixels(scene, width: w, height: h)
    let replayer = try SDLReplayer(shaderDirectory: SDLWindowRenderer.bundledShaderDirectory, driver: "metal")
    let sdl = try replayer.render(scene, atlas: GlyphAtlas(width: 16, height: 16), width: w, height: h, projection: projection)
    let fixture = try ReplayFixture(scene: scene, atlas: GlyphAtlas(width: 16, height: 16), width: UInt32(w), height: UInt32(h),
                                    projection: projection, reference: metal)
    let parity = fixture.parity(of: sdl)
    #expect(parity.passes, "frame \(index): \(parity)")
    print("glass frame \(index): outside Δ\(parity.outside.maxDelta), inside sprites Δ\(parity.inside.maxDelta), "
          + "glass quad \(parity.backdrop.pixels) px differ, max Δ\(parity.backdrop.maxDelta) (≤\(ParityTolerance.insideBackdrops))")
    #expect(parity.backdrop.maxDelta <= ParityTolerance.insideBackdrops, "the glass quad is judged at the backdrop tolerance")
    let field = try metalPixels(GlassParityFrames.fieldScene(), width: w, height: h)
    #expect(pixelDifference(field, metal, above: 4).pixels > 5000, "frame \(index): the glass changes the field")
}
#endif
