import Foundation

extension ShaderCompiler {
    /// The build-tool plugin's run (`--on-build`, ruling `BT-F`): clears `out`, decides with
    /// ``BuildDecision`` over the plugin's view of the environment, then compiles, copies the
    /// checked-in blobs or throws an error whose lines each start `error: ` once printed.
    package static func runOnBuild(_ arguments: CompileArguments, environment: [String: String],
                                   windows: Bool = runsOnWindows,
                                   fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                                   runner: ShaderRunner = ShaderCompiler.processRunner,
                                   log: (String) -> Void = { print($0) },
                                   warn: (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }) throws {
        guard arguments.mode == .onBuild, let checkedInDirectory = arguments.checkedIn else {
            throw ShaderCompileError("runOnBuild needs --on-build")
        }
        let manager = FileManager.default
        let sourceDirectory = arguments.resolvedSource, outDirectory = arguments.resolvedOut
        let display = arguments.displaySource ?? sourceDirectory
        // Both arms start from nothing: the bundle copy mirrors this directory (BT-G).
        try? manager.removeItem(atPath: outDirectory)
        try manager.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)
        guard let names = try? manager.contentsOfDirectory(atPath: sourceDirectory) else {
            throw ShaderCompileError("cannot read the source directory \(sourceDirectory)")
        }
        let shaderSources = try ShaderCompilePlan.sources(in: names, directory: sourceDirectory)
        let sources = try shaderSources.map { source in
            (name: source.fileName,
             bytes: [UInt8](try Data(contentsOf: URL(fileURLWithPath: ShaderCompilePlan.join(sourceDirectory, source.fileName)))))
        }
        let includes = try IncludeSources.read(in: sourceDirectory)
        let checkedIn = try? manager.contentsOfDirectory(atPath: checkedInDirectory)
        let includesMarker = try? String(contentsOfFile: ShaderCompilePlan.join(checkedInDirectory, IncludeSources.markerName), encoding: .utf8)
        let marker = try? String(contentsOfFile: ShaderCompilePlan.join(checkedInDirectory, "SOURCE.sha256"), encoding: .utf8)
        let seen = [ShadercrossLocator.environmentVariable: arguments.environmentShadercross ?? "", "PATH": arguments.environmentPath ?? ""]
        let located: Result<String, ShaderCompileError>?
        do {
            located = .success(try ShadercrossLocator.locate(flag: nil, environment: seen, fileExists: fileExists, windows: windows))
        } catch let error as ShaderCompileError {
            located = error.description.hasPrefix(ShadercrossLocator.notFoundMessage) ? nil : .failure(error)
        }
        switch BuildDecision.decide(located: located, sources: sources, includes: includes, includesMarker: includesMarker,
                                  checkedIn: checkedIn, marker: marker, displaySource: display) {
        case .compile(let shadercross, let stale):
            if !stale.isEmpty {
                warn("warning: \(display)/compiled is stale (\(stale.joined(separator: "; "))); this build compiled fresh blobs, "
                    + "run compile-shaders to refresh the checked-in copy")
            }
            var compile = CompileArguments(source: sourceDirectory, out: outDirectory, shadercross: shadercross,
                                           formats: Set(ShaderFormat.allCases), writesMarker: true, base: nil)
            compile.mode = .compile
            try run(compile, environment: environment, windows: windows, fileExists: fileExists, runner: runner, log: log)
        case .copy(let files):
            for file in files {
                try manager.copyItem(atPath: ShaderCompilePlan.join(checkedInDirectory, file),
                                     toPath: ShaderCompilePlan.join(outDirectory, file))
            }
            log("Verified \(sources.count) checked-in shader(s) against SOURCE.sha256"
                + (includes.isEmpty ? "" : " and \(includes.count) include(s) against \(IncludeSources.markerName)")
                + " (no shadercross): \(outDirectory)")
        case .fail(let lines):
            throw ShaderCompileError(lines.joined(separator: "\nerror: "))
        }
    }
}
