/// What the build-tool plugin's `--on-build` run does (rulings `BT-F`, `BT-L`): a pure
/// function of the locator's answer, the source bytes and the checked-in directory.
package enum BuildDecision: Equatable {
    /// shadercross was found: compile fresh; `staleCheckedIn` names a stale checked-in marker's problems (empty when none or no marker).
    case compile(shadercross: String, staleCheckedIn: [String])
    /// No shadercross, a matching marker: copy these names from the checked-in directory (marker included, sorted bytewise).
    case copy(files: [String])
    /// Refuse; each line is printed as `error: <line>`.
    case fail(lines: [String])

    /// - Parameters:
    ///   - located: the locator's answer: `nil` when nothing was found anywhere, a failure when a variable names a missing file.
    ///   - sources: every `NAME.<vert|frag|comp>.hlsl` with its bytes.
    ///   - checkedIn: the file names in `compiled/`, `nil` when there is no such directory.
    ///   - marker: `compiled/SOURCE.sha256`, `nil` when absent.
    ///   - displaySource: the sources directory as the user spells it, for the fix text.
    package static func decide(located: Result<String, ShaderCompileError>?,
                               sources: [(name: String, bytes: [UInt8])],
                               checkedIn: [String]?, marker: String?, displaySource: String) -> BuildDecision {
        let markerProblems: [String]
        if let marker { markerProblems = SourceMarker.problems(marker: marker, sources: sources) } else { markerProblems = [] }
        switch located {
        case .success(let path):
            return .compile(shadercross: path, staleCheckedIn: markerProblems)
        case .failure(let error):
            return .fail(lines: ["\(error)"])
        case nil:
            break
        }
        var problems: [String] = []
        if checkedIn == nil {
            problems.append("\(displaySource)/compiled does not exist")
        } else if marker == nil {
            problems.append("\(displaySource)/compiled/SOURCE.sha256 does not exist")
        } else {
            problems.append(contentsOf: markerProblems)
            let names = Set(checkedIn ?? [])
            for source in sources.compactMap({ ShaderSource(fileName: $0.name) }) {
                for ext in ["json", "spv"] where !names.contains("\(source.stem).\(ext)") {
                    problems.append("\(source.stem).\(ext) is missing in compiled/")
                }
            }
        }
        guard problems.isEmpty, let checkedIn else {
            var lines = ["the app shaders in \(displaySource) do not match \(displaySource)/compiled: " + problems.joined(separator: "; ")]
            lines.append("no shadercross was found (\(ShadercrossLocator.environmentVariable) is unset and none is on PATH), "
                + "so the build cannot compile them and will not use stale blobs. Either:")
            lines.append("  1. install SDL_shadercross at \(ShadercrossPin.commit) (docs/packaging.md 4a) "
                + "and set \(ShadercrossLocator.environmentVariable) or put it on PATH, or")
            lines.append("  2. where shadercross is installed, run: swift package --allow-writing-to-package-directory "
                + "compile-shaders --source \(displaySource) --out \(displaySource)/compiled")
            lines.append("     and commit \(displaySource)/compiled. A CRLF checkout changes the hashes: mark *.hlsl eol=lf (docs/packaging.md 4a).")
            return .fail(lines: lines)
        }
        let names = Set(checkedIn)
        var files = ["SOURCE.sha256"]
        for source in sources.compactMap({ ShaderSource(fileName: $0.name) }) {
            for format in ShaderFormat.allCases where names.contains("\(source.stem).\(format.rawValue)") {
                files.append("\(source.stem).\(format.rawValue)")
            }
        }
        files.sort { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        return .copy(files: files)
    }
}
