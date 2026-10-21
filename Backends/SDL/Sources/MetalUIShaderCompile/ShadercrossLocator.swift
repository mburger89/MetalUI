import Foundation

/// Finds shadercross and prepares its loader path (rulings `BS-B`, `BS-C`).
package enum ShadercrossLocator {
    /// The variable `BS-C` names.
    package static let environmentVariable = "METALUI_SHADERCROSS"

    /// The executable: `flag`, else `METALUI_SHADERCROSS`, else a `PATH` search for
    /// `shadercross` (`shadercross.exe` on Windows). A flag or variable that names a
    /// missing file is an error, never a fall-through; none found names all three places.
    package static func locate(flag: String?, environment: [String: String], fileExists: (String) -> Bool,
                               windows: Bool) throws -> String {
        if let flag {
            guard fileExists(flag) else { throw ShaderCompileError("--shadercross \(flag) does not exist") }
            return flag
        }
        if let value = environment[environmentVariable], !value.isEmpty {
            guard fileExists(value) else { throw ShaderCompileError("\(environmentVariable)=\(value) does not exist") }
            return value
        }
        let name = windows ? "shadercross.exe" : "shadercross"
        let separator: Character = windows ? ";" : ":"
        for directory in (environment["PATH"] ?? "").split(separator: separator, omittingEmptySubsequences: true) {
            let candidate = ShaderCompilePlan.join(String(directory), name)
            if fileExists(candidate) { return candidate }
        }
        throw ShaderCompileError("shadercross not found: pass --shadercross PATH, set \(environmentVariable), or put it on PATH")
    }

    /// `environment` with the archive's `lib` directory (beside `bin`) first on the
    /// loader path of a non-Windows child; Windows finds DLLs beside the executable.
    package static func loaderEnvironment(forExecutable executable: String, environment: [String: String],
                                          directoryExists: (String) -> Bool, windows: Bool) -> [String: String] {
        guard !windows else { return environment }
        let library = URL(fileURLWithPath: executable).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("lib").path
        guard directoryExists(library) else { return environment }
        var result = environment
        for variable in ["DYLD_LIBRARY_PATH", "LD_LIBRARY_PATH"] {
            if let existing = environment[variable], !existing.isEmpty {
                result[variable] = library + ":" + existing
            } else {
                result[variable] = library
            }
        }
        return result
    }
}
