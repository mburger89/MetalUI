import Foundation
import MetalUIShaderCompile

// `MetalUICompileShaders` (ruling BS-B): HLSL to SPIR-V, MSL, DXIL and reflection
// JSON through SDL_shadercross, and `SOURCE.sha256`. One implementation, shared
// with the `compile-shaders` command plugin.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    print(CompileArguments.usage)
    exit(0)
}
do {
    let parsed = try CompileArguments.parse(arguments)
    switch parsed.mode {
    case .compile: try ShaderCompiler.run(parsed, environment: ProcessInfo.processInfo.environment)
    case .onBuild: try ShaderCompiler.runOnBuild(parsed, environment: ProcessInfo.processInfo.environment)
    }
} catch let error as CompileUsageError {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(2)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
