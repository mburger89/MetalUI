/// Finds the run-time shader compiler library and its dependents (rulings `RC-C`, `RC-N`).
///
/// Pure: every file-system question is a closure, so the order is pinned on every
/// platform's CI with no library and no GPU. `package`, never public.
package enum RuntimeLibraryLocator {
    /// The variable that names the library (a file) or a directory holding it.
    package static let libraryVariable = "METALUI_SHADERCROSS_LIB"
    /// The build tool's executable variable (`BS-C`); its sibling `lib` is a candidate.
    package static let executableVariable = "METALUI_SHADERCROSS"

    /// Where a candidate came from, in lookup order.
    package enum Source: Int, Comparable, Sendable {
        case explicit, variable, besideExecutable, besideExecutableLib, executableSibling, loaderPath
        package static func < (a: Source, b: Source) -> Bool { a.rawValue < b.rawValue }
    }

    /// One place the library may be, with what is known about it before loading.
    package struct Attempt: Equatable, Sendable {
        package var path: String
        package var source: Source
        /// `true`/`false` for a file the lookup could test; `nil` for a bare loader name.
        package var exists: Bool?
        /// The words after the path in an error line.
        package var reason: String

        package init(path: String, source: Source, exists: Bool?, reason: String) {
            self.path = path
            self.source = source
            self.exists = exists
            self.reason = reason
        }
    }

    /// The loader-path names of the library: `.dylib`, then `.so.0` and `.so`, or `.dll`.
    package static func libraryNames(windows: Bool, macOS: Bool) -> [String] {
        if windows { return ["SDL3_shadercross.dll"] }
        if macOS { return ["libSDL3_shadercross.dylib"] }
        return ["libSDL3_shadercross.so.0", "libSDL3_shadercross.so"]
    }

    /// Every candidate in order. A non-empty `explicit` path or `METALUI_SHADERCROSS_LIB` is
    /// **the only candidate** of its rank: one that names a missing file is an error, never a
    /// fall-through (`BS-C`'s rule).
    package static func attempts(explicit: String?, environment: [String: String], executableDirectory: String?,
                                 windows: Bool, macOS: Bool, fileExists: (String) -> Bool,
                                 directoryExists: (String) -> Bool) -> [Attempt] {
        let names = libraryNames(windows: windows, macOS: macOS)
        if let explicit, !explicit.isEmpty {
            return [fileAttempt(explicit, .explicit, "the explicit library path", fileExists)]
        }
        if let value = environment[libraryVariable], !value.isEmpty {
            let label = "\(libraryVariable)=\(value)"
            if directoryExists(value) {
                let inside = names.map { ShaderCompilePlan.join(value, $0) }
                if let found = inside.first(where: fileExists) {
                    return [Attempt(path: found, source: .variable, exists: true, reason: label)]
                }
                return [Attempt(path: inside[0], source: .variable, exists: false,
                                reason: "\(label) is a directory without \(names.joined(separator: " or "))")]
            }
            return [fileAttempt(value, .variable, label, fileExists)]
        }
        var result: [Attempt] = []
        if let directory = executableDirectory, !directory.isEmpty {
            for (source, base) in [(Source.besideExecutable, directory),
                                   (Source.besideExecutableLib, ShaderCompilePlan.join(parent(of: directory), "lib"))] {
                let place = source == .besideExecutable ? "beside the executable" : "in ../lib of the executable"
                for name in names {
                    result.append(fileAttempt(ShaderCompilePlan.join(base, name), source, place, fileExists))
                }
            }
        }
        if let tool = environment[executableVariable], !tool.isEmpty {
            let lib = ShaderCompilePlan.join(parent(of: parent(of: tool)), "lib")
            for name in names {
                result.append(fileAttempt(ShaderCompilePlan.join(lib, name), .executableSibling,
                                          "lib beside bin of \(executableVariable)=\(tool)", fileExists))
            }
        }
        for name in names {
            result.append(Attempt(path: name, source: .loaderPath, exists: nil,
                                  reason: "left to the loader path (not checked)"))
        }
        return result
    }

    /// The paths to try loading, in order. Throws only for an explicit path or variable that
    /// names a missing file; otherwise the existing files in lookup order, then the loader names.
    package static func loadOrder(_ attempts: [Attempt]) throws -> [String] {
        if let first = attempts.first, first.source <= .variable {
            guard first.exists == true else {
                throw ComputeValidationError.libraryMissing(describe(attempts))
            }
            return [first.path]
        }
        return attempts.filter { $0.exists != false }.map(\.path)
    }

    /// Every attempt as `path: reason` lines, plus one `loadFailures` line per path the loader
    /// refused (`path` to its text), so the error names everything tried and why it failed.
    package static func describe(_ attempts: [Attempt], loadFailures: [String: String] = [:]) -> [String] {
        attempts.map { attempt in
            let state: String
            if let failure = loadFailures[attempt.path] { state = "failed to load: \(failure)" }
            else if attempt.exists == false { state = "no such file (\(attempt.reason))" }
            else { state = attempt.reason }
            return "\(attempt.path): \(state)"
        }
    }

    /// The dependents to load by full path before the library itself (`RC-N`): the pin's
    /// install has no rpath, so a full-path load alone fails. `listing` is the directory's
    /// file names. `dxcompiler` and `spirv-cross` are required (a missing one throws naming
    /// it), `dxil` is optional; unrelated files are ignored.
    package static func preloadSet(directory: String, listing: [String], windows: Bool, macOS: Bool) throws -> [String] {
        var result: [String] = []
        for (group, required) in [("dxcompiler", true), ("spirv-cross", true), ("dxil", false)] {
            let matches = listing.filter { name in
                guard isLibraryFile(name, windows: windows, macOS: macOS) else { return false }
                let found = stem(name, windows: windows)
                return group == "spirv-cross" ? found.hasPrefix("spirv-cross") : found == group
            }
            if matches.isEmpty, required {
                throw ComputeValidationError.libraryMissing(["\(directory): the \(group) library is missing (expected beside the shader compiler)"])
            }
            result += matches.sorted { ($0.count, $0) < ($1.count, $1) }.map { ShaderCompilePlan.join(directory, $0) }
        }
        return result
    }

    private static func fileAttempt(_ path: String, _ source: Source, _ reason: String, _ fileExists: (String) -> Bool) -> Attempt {
        Attempt(path: path, source: source, exists: fileExists(path), reason: reason)
    }

    private static func parent(of path: String) -> String {
        var trimmed = Substring(path)
        while trimmed.count > 1, trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        guard let slash = trimmed.lastIndex(of: "/") else { return "." }
        return slash == trimmed.startIndex ? "/" : String(trimmed[..<slash])
    }

    private static func isLibraryFile(_ name: String, windows: Bool, macOS: Bool) -> Bool {
        let lower = name.lowercased()
        if windows { return lower.hasSuffix(".dll") }
        if macOS { return lower.hasSuffix(".dylib") }
        return lower.hasSuffix(".so") || lower.contains(".so.")
    }

    /// `libdxcompiler.so.3` to `dxcompiler`; `dxil.dll` to `dxil`.
    private static func stem(_ name: String, windows: Bool) -> String {
        var base = Substring(name.lowercased())
        if !windows, base.hasPrefix("lib") { base = base.dropFirst(3) }
        if let dot = base.firstIndex(of: ".") { base = base[..<dot] }
        return String(base)
    }
}
