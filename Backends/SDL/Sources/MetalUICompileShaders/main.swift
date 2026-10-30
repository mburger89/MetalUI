#if os(Windows)
import WinSDK
#endif
import Foundation
import MetalUIShaderCompile

// BT-W: under swift-build on Windows the tool may start with no SystemRoot, and Foundation's Process (CFSocket,
// Winsock) then traps. Set SystemRoot and WINDIR from the Windows directory before any Process or socket use.
#if os(Windows)
func setWindowsDirectoryVariablesIfAbsent() {
    var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
    let length = GetWindowsDirectoryW(&buffer, DWORD(buffer.count))
    guard length > 0, Int(length) < buffer.count else { return }
    for name in ["SystemRoot", "WINDIR"] {
        let probe = GetEnvironmentVariableW(Array(name.utf16) + [0], nil, 0)
        if probe == 0 { _ = SetEnvironmentVariableW(Array(name.utf16) + [0], buffer) }
    }
}
setWindowsDirectoryVariablesIfAbsent()
#endif

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
