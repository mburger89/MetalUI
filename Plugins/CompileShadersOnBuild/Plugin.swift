import Foundation
import PackagePlugin

/// Compiles or verifies an app target's `Shaders/NAME.<vert|frag|comp>.hlsl` on plain
/// `swift build` (ruling `BT-D`...`BT-G`, item `BS-D`). One command runs the
/// `MetalUICompileShaders` tool in `--on-build` mode: with shadercross (`METALUI_SHADERCROSS`,
/// else `PATH`) it compiles; without, it copies the checked-in `Shaders/compiled` blobs when
/// their `SOURCE.sha256` matches the sources, else the build fails naming the fix. The output is one
/// directory, `MetalUIAppShaders`, a resource of the target
/// (`SDLGPUShaderLibrary.locate(resourceBundle: .module)`).
@main struct CompileShadersOnBuild: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let manager = FileManager.default
        let shaders = target.directoryURL.appendingPathComponent("Shaders")
        let names = (try? manager.contentsOfDirectory(atPath: shaders.path)) ?? []
        let sources = names.filter { isSource($0) }.sorted()
        guard !sources.isEmpty else {
            Diagnostics.warning("CompileShadersOnBuild: no NAME.<vert|frag|comp>.hlsl in \(shaders.path); nothing to compile")
            return []
        }
        let compiled = shaders.appendingPathComponent("compiled")
        let blobs = ((try? manager.contentsOfDirectory(atPath: compiled.path)) ?? []).sorted().filter { name in
            var isDirectory: ObjCBool = false
            return manager.fileExists(atPath: compiled.appendingPathComponent(name).path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        let environment = ProcessInfo.processInfo.environment
        let shadercross = environment["METALUI_SHADERCROSS"] ?? ""
        // Windows spells the variable `Path`; elsewhere it is `PATH`.
        let path = environment.first { $0.key.caseInsensitiveCompare("PATH") == .orderedSame }?.value ?? ""
        let packagePath = context.package.directoryURL.path
        var display = shaders.path
        if display.hasPrefix(packagePath + "/") { display = String(display.dropFirst(packagePath.count + 1)) }
        let out = context.pluginWorkDirectoryURL.appendingPathComponent("MetalUIAppShaders")
        return [.buildCommand(
            displayName: "Compiling or verifying \(sources.count) app shader(s) for \(target.name)",
            executable: try context.tool(named: "MetalUICompileShaders").url,
            arguments: ["--on-build", "--source", shaders.path, "--checked-in", compiled.path, "--out", out.path,
                        "--environment-shadercross", shadercross, "--environment-path", path, "--display-source", display],
            inputFiles: sources.map { shaders.appendingPathComponent($0) } + blobs.map { compiled.appendingPathComponent($0) },
            outputFiles: [out])]
    }

    /// `NAME.vert.hlsl`, `NAME.frag.hlsl` or `NAME.comp.hlsl` (the tool re-checks).
    private func isSource(_ name: String) -> Bool {
        guard name.hasSuffix(".hlsl") else { return false }
        let stem = name.dropLast(".hlsl".count)
        guard let dot = stem.lastIndex(of: "."), dot != stem.startIndex else { return false }
        return ["vert", "frag", "comp"].contains(String(stem[stem.index(after: dot)...]))
    }
}
