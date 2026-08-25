import Foundation
import Metal

public enum ShaderLibraryError: Error, CustomStringConvertible {
    case resourceMissing(String)
    case compilationFailed(String)

    public var description: String {
        switch self {
        case .resourceMissing(let name):
            "MetalUI shader resource missing from bundle: \(name)"
        case .compilationFailed(let message):
            "MetalUI shader compilation failed: \(message)"
        }
    }
}

/// Builds the Metal library at run time.
///
/// SwiftPM's default build system has no Metal build rule — a `.metal` file
/// beside Swift sources produces no metallib and only an "unhandled files"
/// warning — so shaders ship as resources and compile here instead. See spec 7.2.
public enum ShaderLibrary {
    /// The shared C header concatenated ahead of the Metal source.
    ///
    /// `MTLCompileOptions` exposes no include search path, so `#include` cannot
    /// be relied on from a runtime-compiled source string. Prepending is the
    /// supported route.
    public static func combinedSource() throws -> String {
        let bundle = Bundle.module

        guard let headerURL = bundle.url(forResource: "Shaders/MetalUIShaderTypes",
                                         withExtension: "h") else {
            throw ShaderLibraryError.resourceMissing("Shaders/MetalUIShaderTypes.h")
        }
        guard let shaderURL = bundle.url(forResource: "Shaders/shaders",
                                         withExtension: "metal") else {
            throw ShaderLibraryError.resourceMissing("Shaders/shaders.metal")
        }

        let header = try String(contentsOf: headerURL, encoding: .utf8)
        let shaders = try String(contentsOf: shaderURL, encoding: .utf8)
        return header + "\n" + shaders
    }

    public static func make(device: any MTLDevice) throws -> any MTLLibrary {
        let source = try combinedSource()
        do {
            return try device.makeLibrary(source: source, options: nil)
        } catch {
            throw ShaderLibraryError.compilationFailed("\(error)")
        }
    }
}
