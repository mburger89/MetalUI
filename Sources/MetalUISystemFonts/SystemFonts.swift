import Foundation
import MetalUIFreeType
import MetalUIPortableText
import MetalUITextSystem

/// The platform's installed fonts as a ``PortableFontResolver`` (roadmap item
/// 8b, rulings SF-A…SF-D).
///
/// ```swift
/// let resolver = try SystemFonts.resolver()
/// let app = App(platform: try SDLPlatform(),
///               textSystem: { PortableTextSystem(resolver: resolver) })
/// ```
///
/// - **Discovery (SF-A):** every `.ttf`, `.otf`, `.ttc` and `.otc` under the
///   platform's font directories, in path order, each face's names read by
///   FreeType from the file without loading it.
/// - **Laziness (SF-B):** a face's bytes are read the first time a request or
///   a cascade needs it, so an install with hundreds of faces costs one name
///   read each at startup, not hundreds of opened fonts.
/// - **The default face (SF-D)** is the first of the platform's default
///   families that is installed — asked of fontconfig first on Linux — in its
///   regular style.
/// - **The cascade (SF-C)** is the platform's fallback families that are
///   installed, in order; every other face resolves by name only.
/// - **Designs (SG-C):** `.monospaced` and `.serif` resolve to the first
///   installed family of ``designFamilies`` — registered by name, read only
///   when a request for the design resolves.
public enum SystemFonts {
    /// No scalable font file was found in the searched directories.
    public struct NoFontsFound: Error, CustomStringConvertible {
        /// The directories searched.
        public let directories: [String]
        public var description: String { "no scalable font under \(directories)" }
    }

    /// One face of one installed file.
    public struct Face: Equatable, Sendable {
        /// The font file's path.
        public let path: String
        /// The face's names, read without loading it.
        public let names: FreeTypeFaceNames
    }

    // MARK: Platform defaults

    /// Where the platform keeps fonts, system-wide and per user.
    public static var directories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environment = ProcessInfo.processInfo.environment
        #if os(macOS)
        return ["/System/Library/Fonts", "/Library/Fonts", home + "/Library/Fonts"]
        #elseif os(Windows)
        let windows = environment["WINDIR"] ?? environment["SystemRoot"] ?? "C:\\Windows"
        var directories = [windows + "\\Fonts"]
        if let local = environment["LOCALAPPDATA"] { directories.append(local + "\\Microsoft\\Windows\\Fonts") }
        return directories
        #else
        let data = environment["XDG_DATA_HOME"] ?? home + "/.local/share"
        return ["/usr/share/fonts", "/usr/local/share/fonts", data + "/fonts", home + "/.fonts"]
        #endif
    }

    /// The families `family: nil` resolves to, first installed wins. On Linux
    /// fontconfig's own answer for `sans-serif` comes first when `fc-match`
    /// is installed.
    public static var defaultFamilies: [String] {
        #if os(macOS)
        return ["Helvetica", "Arial"]
        #elseif os(Windows)
        return ["Segoe UI", "Arial", "Tahoma"]
        #else
        return (fontconfigFamily("sans-serif").map { [$0] } ?? [])
            + ["DejaVu Sans", "Noto Sans", "Liberation Sans", "Ubuntu", "Cantarell", "FreeSans"]
        #endif
    }

    /// The faces that draw what the resolved face lacks, in order: broad
    /// Latin/Greek/Cyrillic coverage, then the major scripts and symbols.
    public static var fallbackFamilies: [String] {
        #if os(macOS)
        return ["Helvetica", "Arial Unicode MS", "Apple Symbols", "PingFang SC", "Hiragino Sans",
                "Apple SD Gothic Neo", "Geeza Pro", "Arial Hebrew", "Kohinoor Devanagari", "Thonburi"]
        #elseif os(Windows)
        return ["Segoe UI", "Segoe UI Symbol", "Microsoft YaHei", "Yu Gothic UI", "Malgun Gothic",
                "Nirmala UI", "Segoe UI Historic", "Leelawadee UI", "Ebrima", "Gadugi"]
        #else
        return ["DejaVu Sans", "Noto Sans", "Noto Sans CJK SC", "Noto Sans CJK JP", "Noto Sans Arabic",
                "Noto Sans Hebrew", "Noto Sans Devanagari", "Noto Sans Thai", "Noto Sans Symbols",
                "Noto Sans Symbols2", "FreeSans", "Liberation Sans"]
        #endif
    }

    /// The families each system-font design resolves to, first installed wins
    /// (ruling `SG-C`): what `Font.system(size:design:)` draws with on the
    /// portable text system. A design with no installed family — and
    /// `.rounded` off Apple, which no Linux or Windows install ships —
    /// resolves to the default face, never a trap; an app with a rounded face
    /// calls `PortableFontResolver.register(design:family:)` itself.
    ///
    /// - **macOS** (the portable system there is tests and tools; production
    ///   uses CoreText): `.monospaced` SF Mono, Menlo, Courier New; `.serif`
    ///   New York, Times New Roman, Times; `.rounded` SF Pro Rounded, Arial
    ///   Rounded MT Bold.
    /// - **Windows**: `.monospaced` Cascadia Mono, Consolas, Courier New;
    ///   `.serif` Georgia, Times New Roman.
    /// - **Linux**: fontconfig's own `monospace` and `serif` answers first when
    ///   `fc-match` is installed, then `.monospaced` DejaVu Sans Mono, Noto
    ///   Sans Mono, Liberation Mono, Ubuntu Mono, FreeMono; `.serif` DejaVu
    ///   Serif, Noto Serif, Liberation Serif, FreeSerif.
    public static var designFamilies: [FontDesign: [String]] {
        #if os(macOS)
        return [.monospaced: ["SF Mono", "Menlo", "Courier New"],
                .serif: ["New York", "Times New Roman", "Times"],
                .rounded: ["SF Pro Rounded", "Arial Rounded MT Bold"]]
        #elseif os(Windows)
        return [.monospaced: ["Cascadia Mono", "Consolas", "Courier New"],
                .serif: ["Georgia", "Times New Roman"]]
        #else
        return linuxDesignFamilies(fontconfig: fontconfigFamily)
        #endif
    }

    /// Linux's design lists with `fontconfig`'s answer for each generic
    /// family (`monospace`, `serif`) leading its fixed list — compiled on
    /// every platform so the ordering is tested everywhere (`SG-C` item 4).
    static func linuxDesignFamilies(fontconfig: (String) -> String?) -> [FontDesign: [String]] {
        func list(_ generic: String, _ fixed: [String]) -> [String] {
            (fontconfig(generic).map { [$0] } ?? []) + fixed
        }
        return [.monospaced: list("monospace", ["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono",
                                                "Ubuntu Mono", "FreeMono"]),
                .serif: list("serif", ["DejaVu Serif", "Noto Serif", "Liberation Serif", "FreeSerif"])]
    }

    // MARK: Discovery

    /// Every face under `directories`, files in path order, faces in file
    /// order. Missing directories contribute nothing.
    public static func scan(_ directories: [String]) -> [Face] {
        let extensions: Set<String> = ["ttf", "otf", "ttc", "otc"]
        var paths: [String] = []
        let files = FileManager.default
        for directory in directories {
            guard let walker = files.enumerator(atPath: directory) else { continue }
            while let relative = walker.nextObject() as? String {
                let ext = (relative as NSString).pathExtension.lowercased()
                if extensions.contains(ext) { paths.append((directory as NSString).appendingPathComponent(relative)) }
            }
        }
        return paths.sorted().flatMap { path in
            FreeTypeFaceNames.read(path: path).map { Face(path: path, names: $0) }
        }
    }

    // MARK: The resolver

    /// A resolver over the faces under `directories` (SF-A…SF-D), each design
    /// of `designFamilies` registered as its first installed family (SG-C).
    /// `load` reads a file's bytes — injectable so a test can count the reads.
    public static func resolver(directories: [String] = directories,
                                defaultFamilies: [String] = defaultFamilies,
                                fallbackFamilies: [String] = fallbackFamilies,
                                designFamilies: [FontDesign: [String]] = designFamilies,
                                load: @escaping (String) throws -> [UInt8] = { [UInt8](try Data(contentsOf: URL(fileURLWithPath: $0))) })
        throws -> PortableFontResolver {
        let faces = scan(directories)
        guard !faces.isEmpty else { throw NoFontsFound(directories: directories) }
        let ordered = registrationOrder(faces)
        let defaultFace = defaultFamilies.lazy.compactMap { family in ordered.first { $0.isFamily(family) } }.first
            ?? ordered[0]
        let resolver = PortableFontResolver(defaultFont: defaultFace.names) { try load(defaultFace.path) }
        var registered: Set<Face> = [defaultFace]
        for family in fallbackFamilies {
            guard let face = ordered.first(where: { $0.isFamily(family) }), !registered.contains(face) else { continue }
            registered.insert(face)
            resolver.register(face.names, inCascade: true) { try load(face.path) }
        }
        for face in ordered where !registered.contains(face) {
            resolver.register(face.names, inCascade: false) { try load(face.path) }
        }
        // A name, not a face: nothing is read until the design resolves (SG-C
        // item 1, SF-B). The face's own spelling, so the resolver's name match
        // finds exactly it.
        for (design, families) in designFamilies {
            guard let face = families.lazy.compactMap({ family in ordered.first { $0.isFamily(family) } }).first
            else { continue }
            resolver.register(design: design, family: face.names.family)
        }
        return resolver
    }

    /// Regular faces first, each group in scan order, so a family name two
    /// faces share resolves to the regular one (a face registered earlier
    /// wins a name, FN-A).
    static func registrationOrder(_ faces: [Face]) -> [Face] {
        faces.filter(\.isRegular) + faces.filter { !$0.isRegular }
    }

    /// fontconfig's family for the generic family `generic` (`sans-serif`,
    /// `monospace`, `serif`), if `fc-match` is installed.
    static func fontconfigFamily(_ generic: String) -> String? {
        #if os(Linux)
        for candidate in ["/usr/bin/fc-match", "/usr/local/bin/fc-match"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: candidate)
            process.arguments = ["-f", "%{family[0]}", generic]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            process.waitUntilExit()
            let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return process.terminationStatus == 0 && !output.isEmpty ? output : nil
        }
        #endif
        return nil
    }
}

extension SystemFonts.Face: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
        hasher.combine(names.faceIndex)
    }

    /// The face a family name means when nothing else is said: its regular
    /// (or book, or medium-less plain) style.
    var isRegular: Bool {
        ["regular", "book", "normal", "roman", ""].contains(names.style.lowercased())
    }

    func isFamily(_ family: String) -> Bool {
        names.family.lowercased() == family.lowercased()
    }
}
