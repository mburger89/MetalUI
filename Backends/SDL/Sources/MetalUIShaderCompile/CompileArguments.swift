/// A bad command line; the message is the usage text's relevant line.
package struct CompileUsageError: Error, CustomStringConvertible {
    package let description: String
    package init(_ description: String) { self.description = description }
}

/// The tool's command line (ruling `BS-B`):
/// `--source DIR --out DIR [--shadercross PATH] [--formats spv,msl,dxil,json] [--no-marker] [--base DIR]`.
package struct CompileArguments: Equatable, Sendable {
    package var source: String
    package var out: String
    package var shadercross: String?
    package var formats: Set<ShaderFormat>
    package var writesMarker: Bool
    /// A directory relative `--source` and `--out` resolve against (the plugin passes the package's).
    package var base: String?

    package static let usage = """
        usage: MetalUICompileShaders --source DIR --out DIR [--shadercross PATH] \
        [--formats spv,msl,dxil,json] [--no-marker] [--base DIR]
        """

    package var resolvedSource: String { Self.resolve(source, base: base) }
    package var resolvedOut: String { Self.resolve(out, base: base) }

    private static func resolve(_ path: String, base: String?) -> String {
        guard let base, !path.hasPrefix("/"), !(path.count > 1 && path.dropFirst().first == ":") else { return path }
        return ShaderCompilePlan.join(base, path)
    }

    /// Parses `arguments` (the program name already dropped).
    package static func parse(_ arguments: [String]) throws -> CompileArguments {
        var source: String?, out: String?, shadercross: String?, base: String?
        var formats = Set(ShaderFormat.allCases)
        var writesMarker = true
        var index = 0
        func value(for flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw CompileUsageError("\(flag) needs a value\n\(usage)") }
            return arguments[index]
        }
        while index < arguments.count {
            let flag = arguments[index]
            switch flag {
            case "--source": source = try value(for: flag)
            case "--out": out = try value(for: flag)
            case "--shadercross": shadercross = try value(for: flag)
            case "--base": base = try value(for: flag)
            case "--no-marker": writesMarker = false
            case "--formats":
                var parsed = Set<ShaderFormat>()
                for name in try value(for: flag).split(separator: ",") {
                    guard let format = ShaderFormat(rawValue: name.lowercased()) else {
                        throw CompileUsageError("unknown format \(name) (spv, msl, dxil, json)\n\(usage)")
                    }
                    parsed.insert(format)
                }
                formats = parsed
            default: throw CompileUsageError("unknown argument \(flag)\n\(usage)")
            }
            index += 1
        }
        guard let source else { throw CompileUsageError("--source is required\n\(usage)") }
        guard let out else { throw CompileUsageError("--out is required\n\(usage)") }
        return CompileArguments(source: source, out: out, shadercross: shadercross, formats: formats,
                                writesMarker: writesMarker, base: base)
    }
}
