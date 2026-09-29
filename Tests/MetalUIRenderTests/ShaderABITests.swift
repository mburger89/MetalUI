import Testing
import Metal
import MetalUICore
import MetalUIShaderTypes
@testable import MetalUIRender

/// Asserts Metal's view of the shared structs matches Swift's.
///
/// Swift imports the same C header the shader is built from, so C-vs-Swift drift
/// cannot happen. What CAN happen is MSL applying different packing or alignment
/// rules to the same declarations. That is invisible to the Swift compiler and
/// shows up as garbled geometry, so it is checked here.
@Test func metalAndSwiftAgreeOnSharedStructLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let library = try ShaderLibrary.make(device: device)
    let function = try #require(library.makeFunction(name: "abi_probe"))
    let pipeline = try device.makeComputePipelineState(function: function)
    let queue = try #require(device.makeCommandQueue())

    // Distinct value per field, so a shifted offset produces a wrong number
    // rather than coincidentally matching.
    var rect = MUIRect(
        bounds: Bounds(origin: Point(x: ScaledPixels(11), y: ScaledPixels(12)),
                       size: Size(width: ScaledPixels(13), height: ScaledPixels(14))),
        contentMask: Bounds(origin: Point(x: ScaledPixels(21), y: ScaledPixels(22)),
                            size: Size(width: ScaledPixels(23), height: ScaledPixels(24))),
        // Distinct from `cornerRadii` below (same type, four lines apart), so a
        // transposition between the two shows up as a wrong number.
        maskCornerRadii: Corners(topLeft: ScaledPixels(51), topRight: ScaledPixels(52),
                                 bottomRight: ScaledPixels(53), bottomLeft: ScaledPixels(54)),
        background: Hsla(h: 0.5, s: 0.25, l: 0.75, a: 1),
        borderColor: Hsla(h: 0.1, s: 0.2, l: 0.3, a: 0.4),
        cornerRadii: Corners(topLeft: ScaledPixels(1), topRight: ScaledPixels(2),
                             bottomRight: ScaledPixels(3), bottomLeft: ScaledPixels(4)),
        borderWidths: Edges(top: ScaledPixels(5), right: ScaledPixels(6),
                            bottom: ScaledPixels(7), left: ScaledPixels(8)),
        order: 9)

    // The probe reads a `MUIGlyph` too, and an unbound buffer aborts the
    // process under Metal API validation rather than returning a wrong number.
    // Its fields are asserted by `metalAndSwiftAgreeOnTheGlyphStructLayout` in
    // `GlyphABITests.swift`; this one stays about `MUIRect`.
    var glyph = MUIGlyph(
        bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0)),
        atlasBounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0)),
        contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0)),
        maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
        color: MUIHsla(h: 0, s: 0, l: 0, a: 0),
        order: 0,
        _reserved: 0)

    let slots = 32
    let outBuffer = try #require(device.makeBuffer(length: slots * MemoryLayout<UInt32>.stride,
                                                   options: .storageModeShared))
    let inBuffer = try #require(device.makeBuffer(bytes: &rect,
                                                  length: MemoryLayout<MUIRect>.stride,
                                                  options: .storageModeShared))
    let glyphBuffer = try #require(device.makeBuffer(bytes: &glyph,
                                                     length: MemoryLayout<MUIGlyph>.stride,
                                                     options: .storageModeShared))

    let commandBuffer = try #require(queue.makeCommandBuffer())
    let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(outBuffer, offset: 0, index: Int(MUIProbeBufferOut.rawValue))
    encoder.setBuffer(inBuffer, offset: 0, index: Int(MUIProbeBufferRect.rawValue))
    encoder.setBuffer(glyphBuffer, offset: 0, index: Int(MUIProbeBufferGlyph.rawValue))
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.error == nil)

    let out = outBuffer.contents().bindMemory(to: UInt32.self, capacity: slots)

    // Sizes.
    #expect(Int(out[0]) == MemoryLayout<MUIRect>.size)
    #expect(Int(out[1]) == MemoryLayout<MUIBounds>.size)
    #expect(Int(out[2]) == MemoryLayout<MUIHsla>.size)
    #expect(Int(out[3]) == MemoryLayout<MUICorners>.size)
    #expect(Int(out[4]) == MemoryLayout<MUIEdges>.size)

    // Field round-trip.
    #expect(out[5] == 11)    // bounds.origin.x
    #expect(out[6] == 14)    // bounds.size.height
    #expect(out[7] == 23)    // contentMask.size.width
    #expect(out[8] == 500)   // background.h * 1000
    #expect(out[9] == 400)   // borderColor.a * 1000
    #expect(out[10] == 4)    // cornerRadii.bottomLeft
    #expect(out[11] == 8)    // borderWidths.left
    #expect(out[12] == 9)    // order
    #expect(out[29] == 51)   // maskCornerRadii.topLeft
    #expect(out[30] == 53)   // maskCornerRadii.bottomRight
}

/// 1.10 — Metal's view of `MUIImage` (64 bytes, four `float4` lanes) and of
/// `MUIRect.shape`, the word `_reserved` used to be: at offset 116, after
/// `order`, so the struct and every recorded scene's bytes are unchanged
/// (ruling TE-AD item 1). Read by `image_abi_probe`, its own kernel so the
/// two probes above keep their 32-slot buffers. Distinct values per field;
/// `order` and `shape` are adjacent `MUIUInt`s, so a probe reading one for
/// the other reports a wrong number.
@Test func metalAndSwiftAgreeOnTheImageStructAndTheShapeField() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let library = try ShaderLibrary.make(device: device)
    let function = try #require(library.makeFunction(name: "image_abi_probe"))
    let pipeline = try device.makeComputePipelineState(function: function)
    let queue = try #require(device.makeCommandQueue())

    #expect(MemoryLayout<MUIImage>.size == 64 && MemoryLayout<MUIImage>.stride == 64)
    #expect(MemoryLayout<MUIRect>.size == 120)
    #expect(MemoryLayout<MUIRect>.offset(of: \MUIRect.order) == 112)
    #expect(MemoryLayout<MUIRect>.offset(of: \MUIRect.shape) == 116)

    var rect = MUIRect(
        bounds: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0)),
        contentMask: MUIBounds(origin: MUIPoint(x: 0, y: 0), size: MUISize(width: 0, height: 0)),
        maskCornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
        background: MUIHsla(h: 0, s: 0, l: 0, a: 0), borderColor: MUIHsla(h: 0, s: 0, l: 0, a: 0),
        cornerRadii: MUICorners(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
        borderWidths: MUIEdges(top: 0, right: 0, bottom: 0, left: 0),
        order: 9, shape: 1)
    var image = MUIImage(
        bounds: MUIBounds(origin: MUIPoint(x: 11, y: 12), size: MUISize(width: 13, height: 14)),
        contentMask: MUIBounds(origin: MUIPoint(x: 21, y: 22), size: MUISize(width: 23, height: 24)),
        maskCornerRadii: MUICorners(topLeft: 31, topRight: 32, bottomRight: 33, bottomLeft: 34),
        opacity: 0.25, texture: 41, filter: 1, order: 43)

    let slots = 16
    let out = try #require(device.makeBuffer(length: slots * MemoryLayout<UInt32>.stride,
                                             options: .storageModeShared))
    let rectBuffer = try #require(device.makeBuffer(bytes: &rect, length: MemoryLayout<MUIRect>.stride,
                                                    options: .storageModeShared))
    let imageBuffer = try #require(device.makeBuffer(bytes: &image, length: MemoryLayout<MUIImage>.stride,
                                                     options: .storageModeShared))
    let commandBuffer = try #require(queue.makeCommandBuffer())
    let encoder = try #require(commandBuffer.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(out, offset: 0, index: Int(MUIProbeBufferOut.rawValue))
    encoder.setBuffer(rectBuffer, offset: 0, index: Int(MUIProbeBufferRect.rawValue))
    encoder.setBuffer(imageBuffer, offset: 0, index: Int(MUIProbeBufferImage.rawValue))
    encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
    encoder.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    #expect(commandBuffer.error == nil)

    let v = out.contents().bindMemory(to: UInt32.self, capacity: slots)
    #expect(v[0] == 64)      // sizeof(MUIImage)
    #expect(v[1] == 11)      // bounds.origin.x
    #expect(v[2] == 14)      // bounds.size.height
    #expect(v[3] == 21)      // contentMask.origin.x
    #expect(v[4] == 24)      // contentMask.size.height
    #expect(v[5] == 31)      // maskCornerRadii.topLeft
    #expect(v[6] == 34)      // maskCornerRadii.bottomLeft
    #expect(v[7] == 250)     // opacity * 1000
    #expect(v[8] == 41)      // texture
    #expect(v[9] == 1)       // filter
    #expect(v[10] == 43)     // order
    #expect(v[11] == 120)    // sizeof(MUIRect)
    #expect(v[12] == 9)      // MUIRect.order
    #expect(v[13] == 1)      // MUIRect.shape
}
