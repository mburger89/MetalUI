import Foundation

// BEGIN environment-forwarding
// Identical, byte for byte, in Plugins/CompileShadersOnBuild/Plugin.swift (a plugin cannot import a package
// target); pinned by `theBuildPluginForwardsTheSameEnvironmentTheToolListsHere` (ruling BT-V).

/// The environment variables the build-tool plugin forwards to `MetalUICompileShaders`: the build system may run a
/// build command with an (almost) empty environment, and on Windows Foundation's `Process` cannot start Winsock
/// without `SystemRoot` (the tool crashed in `CFSocket`), nor find a temporary directory without `TEMP` (ruling `BT-V`).
enum ForwardedEnvironment {
    /// What the tool and shadercross need everywhere: the shadercross lookup, its libraries, and `PATH` (`Path` on Windows).
    static let common = ["METALUI_SHADERCROSS", "METALUI_SHADERCROSS_LIB", "PATH"]
    /// Windows' system variables (Winsock, temporary files, shadercross's DLL and `.exe` resolution).
    static let windows = ["SystemRoot", "WINDIR", "TEMP", "TMP", "USERPROFILE", "LOCALAPPDATA", "ProgramData", "ComSpec", "PATHEXT"]
    /// Elsewhere: a home, a temporary directory and the loader paths.
    static let other = ["HOME", "TMPDIR", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"]

    /// The names to forward on this platform, in order.
    static func keys(windows isWindows: Bool) -> [String] { common + (isWindows ? windows : other) }

    /// The entries of `environment` whose name equals a forwarded key, matched case-insensitively and kept under their own
    /// spelling (Windows has `Path`, `SystemRoot`), each only when present. A key never matches twice.
    static func select(from environment: [String: String], windows isWindows: Bool) -> [String: String] {
        var result: [String: String] = [:]
        for key in keys(windows: isWindows) {
            for (name, value) in environment where name.caseInsensitiveCompare(key) == .orderedSame {
                result[name] = value
            }
        }
        return result
    }
}
// END environment-forwarding

/// The environment a shadercross child gets on Windows (ruling `BT-W`): `environment` plus, for each of `SystemRoot`,
/// `WINDIR`, `TEMP`, `TMP` it lacks (case-insensitively), the tool's own `process` value when it has one. A child that
/// is itself a Winsock or temporary-file user fails without them; elsewhere `environment` is returned unchanged.
enum ChildEnvironment {
    static let windowsRequired = ["SystemRoot", "WINDIR", "TEMP", "TMP"]

    static func merged(_ environment: [String: String], process: [String: String], windows: Bool) -> [String: String] {
        guard windows else { return environment }
        var result = environment
        for key in windowsRequired where !result.keys.contains(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) {
            if let entry = process.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                result[entry.key] = entry.value
            }
        }
        return result
    }
}
