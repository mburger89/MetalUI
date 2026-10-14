import Testing
// Only this import: the point of the test is that no `import CSDL` is needed.
import MetalUISDLGPU

/// GA-B: `@_exported import CSDL` crosses the package boundary, so one import
/// of the product gives the raw `SDL_` API. This target is in another package
/// than `MetalUISDLGPU`, like an app. Mutation: delete `Exports.swift`'s
/// `@_exported` → this file no longer compiles (`cannot find 'SDL_GetError'`).
@Test func oneImportOfTheProductReachesTheRawSDLSymbols() {
    #expect(SDL_GetError() != nil)
    #expect(SDL_GPU_SHADERFORMAT_SPIRV != 0)
}
