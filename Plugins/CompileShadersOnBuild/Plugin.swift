import Foundation
import PackagePlugin

/// Compiles or verifies an app target's `Shaders/NAME.<vert|frag|comp>.hlsl` on plain
/// `swift build` (ruling `BT-D`...`BT-G`, item `BS-D`). One command runs the
/// `MetalUICompileShaders` tool in `--on-build` mode: with shadercross (`METALUI_SHADERCROSS`,
/// else `PATH`) it compiles; without, it copies the checked-in `Shaders/compiled` blobs when
/// their `SOURCE.sha256` (and, with include files, `INCLUDES.sha256`) match the sources, else the build fails naming the fix. The output is one
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
        // Every `.hlsli` and non-stage `.hlsl` below Shaders/ (not compiled/) is an input too (BT-O).
        let includes = IncludeSelection.relativePaths(under: shaders.path)
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
            inputFiles: sources.map { shaders.appendingPathComponent($0) } + includes.map { shaders.appendingPathComponent($0) } + blobs.map { compiled.appendingPathComponent($0) },
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

// BEGIN include-selection
// Identical, byte for byte, in Plugins/CompileShadersOnBuild/Plugin.swift (a plugin cannot import a package
// target); pinned by `theBuildPluginSelectsIncludeSourcesExactlyAsTheToolDoes` (ruling BT-O).

/// Which files under an app's `Shaders/` are include sources: every regular file ending `.hlsli`, or ending
/// `.hlsl` but not a top-level `NAME.<vert|frag|comp>.hlsl` stage source, anywhere below `Shaders/` except
/// the top-level `compiled/` subtree (ruling `BT-O`).
enum IncludeSelection {
    /// Whether `relativePath` (`/`-separated, below `Shaders/`) names an include source by its spelling.
    static func isIncludeSource(relativePath: String) -> Bool {
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        if name.hasSuffix(".hlsli") { return name.count > ".hlsli".count }
        guard name.hasSuffix(".hlsl"), name.count > ".hlsl".count else { return false }
        guard !relativePath.contains("/") else { return true }
        let stem = name.dropLast(".hlsl".count)
        guard let dot = stem.lastIndex(of: "."), dot != stem.startIndex else { return true }
        return !["vert", "frag", "comp"].contains(String(stem[stem.index(after: dot)...]))
    }

    /// The include sources below `directory`, as `/`-separated paths relative to it, sorted bytewise. A
    /// symlink to a regular file counts; a symlink to a directory, a broken link and the top-level
    /// `compiled` directory are not entered or listed (no cycles, no blobs).
    static func relativePaths(under directory: String, fileManager: FileManager = .default) -> [String] {
        var found: [String] = []
        func walk(_ relative: String) {
            let path = relative.isEmpty ? directory : (directory.hasSuffix("/") ? directory : directory + "/") + relative
            guard let names = try? fileManager.contentsOfDirectory(atPath: path) else { return }
            for name in names {
                let child = relative.isEmpty ? name : relative + "/" + name
                let full = (path.hasSuffix("/") ? path : path + "/") + name
                let type = (try? fileManager.attributesOfItem(atPath: full))?[.type] as? FileAttributeType
                if type == .typeDirectory {
                    if !(relative.isEmpty && name == "compiled") { walk(child) }
                } else if type == .typeSymbolicLink {
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: full, isDirectory: &isDirectory), !isDirectory.boolValue,
                       isIncludeSource(relativePath: child) { found.append(child) }
                } else if type == .typeRegular, isIncludeSource(relativePath: child) {
                    found.append(child)
                }
            }
        }
        walk("")
        return found.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
    }
}
// END include-selection
