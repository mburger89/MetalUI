import Foundation

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

/// The include sources of an app's shader directory, with their bytes (ruling `BT-P`).
package enum IncludeSources {
    /// The marker's file name, beside `SOURCE.sha256`.
    package static let markerName = "INCLUDES.sha256"

    /// Every include source below `directory`, named by its relative path, sorted bytewise.
    package static func read(in directory: String) throws -> [(name: String, bytes: [UInt8])] {
        try IncludeSelection.relativePaths(under: directory).map { relative in
            (name: relative, bytes: [UInt8](try Data(contentsOf: URL(fileURLWithPath: ShaderCompilePlan.join(directory, relative)))))
        }
    }
}
