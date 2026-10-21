/// A failure of the shader compiler, the message naming the file, directory or
/// command (ruling `BS-B`).
package struct ShaderCompileError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
}

/// The stage a source's suffix names (`vert`, `frag`, `comp`); the raw value is
/// shadercross's `-t` argument.
package enum ShaderStage: String, CaseIterable, Sendable {
    case vertex, fragment, compute

    /// The file-name suffix: `vert`, `frag` or `comp`.
    package var suffix: String {
        switch self {
        case .vertex: "vert"
        case .fragment: "frag"
        case .compute: "comp"
        }
    }

    package init?(suffix: String) {
        guard let stage = ShaderStage.allCases.first(where: { $0.suffix == suffix }) else { return nil }
        self = stage
    }
}

/// An output format. `spv` is the intermediate every other format derives from.
package enum ShaderFormat: String, CaseIterable, Sendable {
    case spv, msl, dxil, json

    /// shadercross's `-d` (and `-s`) spelling.
    package var shadercrossName: String {
        switch self {
        case .spv: "SPIRV"
        case .msl: "MSL"
        case .dxil: "DXIL"
        case .json: "JSON"
        }
    }
}

/// One `NAME.<vert|frag|comp>.hlsl` source.
package struct ShaderSource: Equatable, Sendable {
    /// `tri.vert.hlsl`.
    package let fileName: String
    /// `tri.vert`: what every output is named after.
    package let stem: String
    package let stage: ShaderStage

    /// A source, or `nil` for any other file name (`x.hlsl`, `x.geom.hlsl`, `notes.txt`).
    package init?(fileName: String) {
        guard fileName.hasSuffix(".hlsl") else { return nil }
        let stem = String(fileName.dropLast(".hlsl".count))
        guard let dot = stem.lastIndex(of: "."), dot != stem.startIndex,
              let stage = ShaderStage(suffix: String(stem[stem.index(after: dot)...])) else { return nil }
        self.fileName = fileName
        self.stem = stem
        self.stage = stage
    }
}

/// What to run, as the python script ran it: HLSL to SPIR-V, then SPIR-V to
/// each other format (ruling `BS-B`).
package enum ShaderCompilePlan {
    /// The sources among `fileNames`, sorted bytewise by name; none is an error naming `directory`.
    package static func sources(in fileNames: [String], directory: String) throws -> [ShaderSource] {
        let found = fileNames.compactMap(ShaderSource.init(fileName:))
            .sorted { Array($0.fileName.utf8).lexicographicallyPrecedes(Array($1.fileName.utf8)) }
        guard !found.isEmpty else {
            throw ShaderCompileError("no NAME.vert.hlsl, NAME.frag.hlsl or NAME.comp.hlsl in \(directory)")
        }
        return found
    }

    /// `directory` and `name` joined with one slash (Windows accepts it).
    package static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// The argument vectors (without the executable) for one source, in order:
    /// SPIR-V from the HLSL always, then MSL, DXIL and JSON when requested, each
    /// from the `.spv`.
    package static func commands(for source: ShaderSource, sourceDirectory: String, outDirectory: String,
                                 formats: Set<ShaderFormat>) -> [[String]] {
        let spirv = join(outDirectory, "\(source.stem).spv")
        var commands = [[join(sourceDirectory, source.fileName), "-s", "HLSL", "-d", ShaderFormat.spv.shadercrossName,
                         "-t", source.stage.rawValue, "-o", spirv]]
        for format in [ShaderFormat.msl, .dxil, .json] where formats.contains(format) {
            commands.append([spirv, "-s", ShaderFormat.spv.shadercrossName, "-d", format.shadercrossName,
                             "-t", source.stage.rawValue, "-o", join(outDirectory, "\(source.stem).\(format.rawValue)")])
        }
        return commands
    }
}
