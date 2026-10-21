import Foundation
import PackagePlugin

/// `swift package --allow-writing-to-package-directory compile-shaders --source DIR --out DIR`
/// (ruling `BS-B`): runs the `MetalUICompileShaders` tool, which SwiftPM builds and
/// finds, with the package's directory as the base of relative paths. shadercross
/// is found by `--shadercross`, `METALUI_SHADERCROSS` or `PATH`.
@main struct CompileShaders: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let tool = try context.tool(named: "MetalUICompileShaders")
        let process = Process()
        process.executableURL = tool.url
        process.arguments = arguments + ["--base", context.package.directoryURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            Diagnostics.error("MetalUICompileShaders exited with status \(process.terminationStatus)")
            throw CompileShadersFailure(status: process.terminationStatus)
        }
    }
}

struct CompileShadersFailure: Error, CustomStringConvertible {
    let status: Int32
    var description: String { "compile-shaders failed (status \(status))" }
}
