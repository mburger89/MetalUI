import MetalUIFreeType

/// A request — an optional family name and a point size — turned into a
/// ``PortableFont``, over font files the caller registers (rulings `FN-A`…`FN-C`). The portable counterpart of `MetalUIText`'s
/// `FontResolver`, with CoreText's matching rules (measured):
///
/// - a name matches a face's **PostScript name, family name or full name**,
///   ignoring case and nothing else — no whitespace folding, no family plus
///   style synthesis (`"Source Sans 3 Regular"` is not a name of Source Sans
///   3, whose full name is `"Source Sans 3"`);
/// - a resolved font falls back to every other registered face, in the order
///   registered (ruling FB-B), for characters it has no glyph for;
/// - `nil` is the default face, and a name that matches nothing — `""`
///   included — **substitutes** the default face rather than failing, as
///   `CTFontCreateWithName` substitutes Helvetica. Callers key caches on the
///   resolved ``PortableFont/key``, never on the requested name.
///
/// Discovering a platform's installed fonts is not here: this target has no
/// file system. A platform layer reads font files and registers them —
/// `MetalUISystemFonts` does (ruling SF-A), lazily: a face registered with a
/// loader is matched by names read without its bytes, and loaded the first
/// time a request or a cascade needs it (SF-B). A face registered with
/// `inCascade: false` resolves by name but never draws another face's missing
/// characters (SF-C), so hundreds of installed faces do not all open when the
/// first font resolves.
public final class PortableFontResolver {
    private final class Face {
        private var data: [UInt8]?
        private let load: () throws -> [UInt8]
        let faceIndex: Int
        /// Lowercased PostScript, family and full names.
        let names: Set<String>
        let inCascade: Bool

        init(data: [UInt8]?, load: @escaping () throws -> [UInt8], faceIndex: Int, names: Set<String>,
             inCascade: Bool) {
            self.data = data
            self.load = load
            self.faceIndex = faceIndex
            self.names = names
            self.inCascade = inCascade
        }

        /// The bytes, loaded on first use and kept.
        func bytes() throws -> [UInt8] {
            if let data { return data }
            let loaded = try load()
            data = loaded
            return loaded
        }
    }

    private var faces: [Face] = []
    private let defaultFace: Int
    private var cache: [FontRequest: PortableFont] = [:]

    private struct FontRequest: Hashable {
        let face: Int
        let size: Double
    }

    /// A resolver whose default face — `family: nil`, and the substitute for
    /// a name that matches nothing — is face `faceIndex` of `data`.
    public init(defaultFont data: [UInt8], faceIndex: Int = 0) throws {
        defaultFace = 0
        try register(data, faceIndex: faceIndex)
    }

    /// A resolver whose default face is known by `names` and loaded by `load`
    /// the first time it is needed (ruling SF-B).
    public init(defaultFont names: FreeTypeFaceNames, load: @escaping () throws -> [UInt8]) {
        defaultFace = 0
        register(names, inCascade: true, load: load)
    }

    /// Makes face `faceIndex` of `data` resolvable by its names. A face
    /// registered earlier wins a name two faces share.
    public func register(_ data: [UInt8], faceIndex: Int = 0) throws {
        // Any size reads the names; the face is opened again per resolved size.
        let probe = try FreeTypeFontNames(data: data, faceIndex: faceIndex)
        faces.append(Face(data: data, load: { data }, faceIndex: faceIndex,
                          names: Self.matchable([probe.postScript, probe.family, probe.full]),
                          inCascade: true))
    }

    /// Makes the face `names` describes resolvable, its bytes read by `load`
    /// only when a request or a cascade first needs it (ruling SF-B). With
    /// `inCascade: false` it is never another face's fallback (SF-C).
    public func register(_ names: FreeTypeFaceNames, inCascade: Bool, load: @escaping () throws -> [UInt8]) {
        faces.append(Face(data: nil, load: load, faceIndex: names.faceIndex,
                          names: Self.matchable([names.postScript, names.family, names.full]),
                          inCascade: inCascade))
    }

    private static func matchable(_ names: [String]) -> Set<String> {
        Set(names.filter { !$0.isEmpty }.map { $0.lowercased() })
    }

    /// The registered face `family` names, or the default face, at `size`.
    ///
    /// Traps on a size that is not finite and positive, as
    /// `FontResolver.resolve(family:size:)` does. Memoized per face and size:
    /// the same request returns the same ``PortableFont`` instance.
    public func resolve(family: String?, size: Double) throws -> PortableFont {
        precondition(size.isFinite && size > 0,
                     "PortableFontResolver.resolve(family:size:) needs a finite, positive point size; got \(size)")
        let index = family.flatMap { name in
            let wanted = name.lowercased()
            return faces.firstIndex { $0.names.contains(wanted) }
        } ?? defaultFace
        let font = try font(face: index, size: size)
        // The cascade (ruling FB-B): every other registered face in the
        // cascade (SF-C), in the order registered, at this size — what draws a
        // character this face lacks.
        if font.fallbacks.isEmpty, faces.count > 1 {
            font.fallbacks = try faces.indices.filter { $0 != index && faces[$0].inCascade }
                .map { try self.font(face: $0, size: size) }
        }
        return font
    }

    /// Face `index` at `size`, memoized.
    private func font(face index: Int, size: Double) throws -> PortableFont {
        let request = FontRequest(face: index, size: size)
        if let cached = cache[request] { return cached }
        let face = faces[index]
        let font = try PortableFont(data: try face.bytes(), faceIndex: face.faceIndex, size: size)
        cache[request] = font
        return font
    }
}

/// A face's three matchable names, read once through FreeType.
struct FreeTypeFontNames {
    let postScript: String
    let family: String
    let full: String

    init(data: [UInt8], faceIndex: Int) throws {
        let face = try FreeTypeFont(data: data, faceIndex: faceIndex, size: 12)
        postScript = face.postScriptName
        family = face.familyName
        full = face.fullName
    }
}
