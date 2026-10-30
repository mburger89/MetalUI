import Foundation

/// Runs one child: executable, arguments, environment; answers its exit status.
package typealias ShaderRunner = (_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Int32

/// The compile run itself, the python script's logic in Swift (ruling `BS-B`).
package enum ShaderCompiler {
    package static var runsOnWindows: Bool {
        #if os(Windows)
        true
        #else
        false
        #endif
    }

    /// A `Process` child inheriting standard output and error.
    package static func processRunner(_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Windows: a child missing SystemRoot/WINDIR/TEMP/TMP gets the tool's own (ruling BT-W).
        process.environment = ChildEnvironment.merged(environment, process: ProcessInfo.processInfo.environment, windows: runsOnWindows)
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Compiles every source in `arguments.source` into `arguments.out`, then writes
    /// `SOURCE.sha256` unless `--no-marker`. A failing command stops the run, naming it.
    package static func run(_ arguments: CompileArguments, environment: [String: String],
                            windows: Bool = runsOnWindows,
                            fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                            runner: ShaderRunner = ShaderCompiler.processRunner,
                            log: (String) -> Void = { print($0) }) throws {
        let located = try ShadercrossLocator.locate(flag: arguments.shadercross, environment: environment,
                                                    fileExists: fileExists, windows: windows)
        let executable = URL(fileURLWithPath: located).path
        let childEnvironment = ShadercrossLocator.loaderEnvironment(
            forExecutable: executable, environment: environment,
            directoryExists: { var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue },
            windows: windows)
        let sourceDirectory = arguments.resolvedSource, outDirectory = arguments.resolvedOut
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: sourceDirectory) else {
            throw ShaderCompileError("cannot read the source directory \(sourceDirectory)")
        }
        let sources = try ShaderCompilePlan.sources(in: names, directory: sourceDirectory)
        try FileManager.default.createDirectory(atPath: outDirectory, withIntermediateDirectories: true)
        for source in sources {
            for command in ShaderCompilePlan.commands(for: source, sourceDirectory: sourceDirectory,
                                                      outDirectory: outDirectory, formats: arguments.formats) {
                let status = try runner(executable, command, childEnvironment)
                guard status == 0 else {
                    throw ShaderCompileError("shadercross exited with status \(status) for \(source.fileName): "
                        + "\(executable) \(command.joined(separator: " "))")
                }
            }
            if arguments.formats.contains(.json),
               let json = try? String(contentsOfFile: ShaderCompilePlan.join(outDirectory, "\(source.stem).json"), encoding: .utf8) {
                log("\(source.stem) \(json.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        if arguments.writesMarker {
            let listed = try sources.map { source in
                (name: source.fileName,
                 bytes: [UInt8](try Data(contentsOf: URL(fileURLWithPath: ShaderCompilePlan.join(sourceDirectory, source.fileName)))))
            }
            try Data(SourceMarker.contents(of: listed).utf8)
                .write(to: URL(fileURLWithPath: ShaderCompilePlan.join(outDirectory, "SOURCE.sha256")))
            // `INCLUDES.sha256` only when include sources exist (BT-P); with none, a stale one is removed
            // so a package without headers is byte-identical to before.
            let includes = try IncludeSources.read(in: sourceDirectory)
            let includesPath = ShaderCompilePlan.join(outDirectory, IncludeSources.markerName)
            if includes.isEmpty {
                try? FileManager.default.removeItem(atPath: includesPath)
            } else {
                try Data(SourceMarker.contents(of: includes).utf8).write(to: URL(fileURLWithPath: includesPath))
            }
        }
        let kinds = ShaderFormat.allCases.filter { $0 == .spv || arguments.formats.contains($0) }.map(\.shadercrossName)
        log("Compiled \(sources.count) shader(s) to \(kinds.joined(separator: ", ")): \(outDirectory)")
    }
}
