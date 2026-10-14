import Testing
// Only this import: the point of the test is that no `import CSDL` is needed.
import MetalUISDLGPU

/// GA-B: `@_exported import CSDL` crosses the package boundary, so one import
/// of the product gives the raw `SDL_` API. This target is in another package
/// than `MetalUISDLGPU`, like an app, but Swift lets other files of this target
/// that import `CSDL` themselves leak it here, so **this test cannot go red on
/// its own**. The isolating instrument is a consumer package that imports only
/// `MetalUISDLGPU` (record §114: it built and ran, and with `@_exported`
/// removed from `Exports.swift` it failed with `cannot find 'SDL_GetError'`).
/// This file pins that the symbols are reachable from a test of this package.
@Test func oneImportOfTheProductReachesTheRawSDLSymbols() {
    #expect(SDL_GetError() != nil)
    #expect(SDL_GPU_SHADERFORMAT_SPIRV != 0)
}
