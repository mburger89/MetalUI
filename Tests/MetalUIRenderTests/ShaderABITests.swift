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
