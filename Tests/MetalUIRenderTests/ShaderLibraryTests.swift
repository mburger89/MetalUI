import Testing
import Metal
@testable import MetalUIRender

@Test func combinedSourcePrependsHeaderBeforeShaders() throws {
    let src = try ShaderLibrary.combinedSource()
    let headerAt = try #require(src.range(of: "METALUI_SHADER_TYPES_H"))
    let shaderAt = try #require(src.range(of: "rect_fragment"))
    // The header must come first, or the shader cannot see the types.
    #expect(headerAt.lowerBound < shaderAt.lowerBound)
    #expect(src.contains("abi_probe"))
}

@Test func libraryCompilesAtRuntime() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(),
                              "no Metal device; run on macOS hardware")
    let lib = try ShaderLibrary.make(device: device)
    #expect(lib.functionNames.contains("rect_vertex"))
    #expect(lib.functionNames.contains("rect_fragment"))
    #expect(lib.functionNames.contains("abi_probe"))
}
