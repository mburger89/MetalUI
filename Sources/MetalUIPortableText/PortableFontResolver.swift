import MetalUIFreeType
import MetalUITextSystem

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
        /// The lowercased family name alone — what a weight or a slope selects
        /// among (ruling TE-W).
        let family: String
        let traits: FaceTraits
        let inCascade: Bool

        init(data: [UInt8]?, load: @escaping () throws -> [UInt8], faceIndex: Int, names: Set<String>,
             family: String, traits: FaceTraits, inCascade: Bool) {
            self.data = data
            self.load = load
            self.faceIndex = faceIndex
            self.names = names
            self.family = family
            self.traits = traits
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
    /// The family a system design resolves to (`register(design:family:)`).
    private var designFamilies: [FontDesign: String] = [:]

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
                          family: probe.family.lowercased(),
                          traits: FaceTraits(style: probe.style, weightClass: probe.weightClass,
                                             widthClass: probe.widthClass),
                          inCascade: true))
    }

    /// Makes the face `names` describes resolvable, its bytes read by `load`
    /// only when a request or a cascade first needs it (ruling SF-B). With
    /// `inCascade: false` it is never another face's fallback (SF-C).
    public func register(_ names: FreeTypeFaceNames, inCascade: Bool, load: @escaping () throws -> [UInt8]) {
        faces.append(Face(data: nil, load: load, faceIndex: names.faceIndex,
                          names: Self.matchable([names.postScript, names.family, names.full]),
                          family: names.family.lowercased(),
                          traits: FaceTraits(style: names.style, weightClass: names.weightClass,
                                             widthClass: names.widthClass),
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
        try resolve(FontDescriptor(family: family, size: size))
    }

    /// The face `descriptor` asks for (rulings TE-C item 1, TE-W), selected
    /// as CoreText selects — measured against it face for face by
    /// `FontSelectionOracleTests` over the installed multi-weight families:
    ///
    /// 1. **The name** matches as ``resolve(family:size:)`` always has
    ///    (PostScript, family or full name, case folded; `nil` or no match is
    ///    the default face; with no family, a design registered by
    ///    ``register(design:family:)`` names one). A name that is a face's
    ///    **family** name — not its PostScript or full name — means the
    ///    family's regular face: the one nearest weight 0, normal width,
    ///    upright (`CTFontCreateWithName("Futura")` is Futura-Medium,
    ///    "Sukhumvit Set" is SukhumvitSet-Text, whichever registered first).
    /// 2. **A weight** picks the upright face of that face's family whose
    ///    ``FaceTraits`` are nearest: `|Δweight| + |width|`, so a condensed
    ///    face is reached only by an exact enough weight (Helvetica Neue
    ///    black is CondensedBlack, heavy is Bold); a tie keeps the named face,
    ///    then takes the heavier.
    /// 3. **Italic** picks, among the family's italic faces of the selected
    ///    face's width, the one nearest the requested weight — the lighter on
    ///    a tie (Avenir Next light italic is UltraLightItalic where light
    ///    upright is Regular) — or, with no weight asked, nearest the selected
    ///    face's own (the heavier on a tie).
    ///
    /// Nothing is synthesised: a family without the weight or slope keeps
    /// the face it has (F2h, F4b). Reading traits needs no face's bytes, so a
    /// lazy face (SF-B) is loaded only when it is the answer. Differences
    /// from CoreText the oracle measured are named in ruling TE-W.
    public func resolve(_ descriptor: FontDescriptor) throws -> PortableFont {
        let size = descriptor.size
        precondition(size.isFinite && size > 0,
                     "PortableFontResolver.resolve(family:size:) needs a finite, positive point size; got \(size)")
        let name = descriptor.family ?? designFamilies[descriptor.design]
        let named = name.flatMap { name in
            let wanted = name.lowercased()
            return faces.firstIndex { $0.names.contains(wanted) }
        }
        var index = named ?? defaultFace
        if let named, let wanted = name?.lowercased(), faces[named].family == wanted {
            index = nearest(to: index, weight: 0, pool: familyFaces(of: index).filter { !faces[$0].traits.italic },
                            lighterOnTie: false)
        }
        if let weight = descriptor.weight {
            index = nearest(to: index, weight: weight,
                            pool: familyFaces(of: index).filter { !faces[$0].traits.italic }, lighterOnTie: false)
        }
        if descriptor.italic, !faces[index].traits.italic {
            let width = faces[index].traits.width
            let slanted = familyFaces(of: index).filter { faces[$0].traits.italic && faces[$0].traits.width == width }
            if !slanted.isEmpty {
                index = nearest(to: nil, weight: descriptor.weight ?? faces[index].traits.weight, pool: slanted,
                                lighterOnTie: descriptor.weight != nil)
            }
        }
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

    /// Makes a request with no family and `design` resolve as a request for
    /// `family` (ruling TE-C item 1) — the portable system has no SF Rounded
    /// or New York of its own. An unregistered design, or a family that
    /// matches no face, is the default face, as any unmatched name is.
    public func register(design: FontDesign, family: String) {
        designFamilies[design] = family
    }

    /// Every registered face of face `index`'s family, in registration order.
    private func familyFaces(of index: Int) -> [Int] {
        let family = faces[index].family
        return faces.indices.filter { faces[$0].family == family }
    }

    /// The face of `pool` nearest `weight` at normal width (`|Δweight| +
    /// |width|`); a tie keeps `preferred`, then takes the lighter or the
    /// heavier face. `preferred` itself when `pool` is empty.
    private func nearest(to preferred: Int?, weight: Double, pool: [Int], lighterOnTie: Bool) -> Int {
        func cost(_ index: Int) -> Double {
            let traits = faces[index].traits
            // Rounded to 1e-9 so two faces the traits place equally far are a
            // tie, not decided by the last bit of a subtraction.
            return ((abs(traits.weight - weight) + abs(traits.width)) * 1e9).rounded()
        }
        guard var best = pool.first else { return preferred ?? defaultFace }
        for candidate in pool.dropFirst() {
            let (c, b) = (cost(candidate), cost(best))
            if c < b { best = candidate; continue }
            guard c == b, best != preferred else { continue }
            if candidate == preferred { best = candidate; continue }
            let (cw, bw) = (faces[candidate].traits.weight, faces[best].traits.weight)
            if lighterOnTie ? cw < bw : cw > bw { best = candidate }
        }
        return best
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

/// A face's three matchable names and its trait inputs, read once through
/// FreeType.
struct FreeTypeFontNames {
    let postScript: String
    let family: String
    let full: String
    let style: String
    let weightClass: Int
    let widthClass: Int

    init(data: [UInt8], faceIndex: Int) throws {
        let face = try FreeTypeFont(data: data, faceIndex: faceIndex, size: 12)
        postScript = face.postScriptName
        family = face.familyName
        full = face.fullName
        style = face.styleName
        (weightClass, widthClass) = face.weightAndWidthClass
    }
}

/// A face's weight, width and slope on CoreText's trait scales (ruling TE-W),
/// derived from what FreeType reads without the face's bytes: its style name
/// and OS/2 classes.
///
/// **Not `usWeightClass` alone, measured**: over the 2 755 faces of a macOS 27
/// install, CoreText's weight trait disagrees with the OS/2 class wherever a
/// face's class and name part ways — Avenir Next UltraLight is class 275 and
/// weight −0.8, Avenir Heavy class 900 and 0.56, Avenir Black class 800 and
/// 0.62 — and follows the style name's weight word (record §59 §3). So a
/// weight word in the style name decides, and the class decides only a style
/// with none. The slope is the style name's "italic" or "oblique" (CoreText's
/// italic trait agreed with it on 2 753 of those faces, more than with
/// `fsSelection` or `macStyle`), and the width `(usWidthClass − 5) / 10`
/// (condensed, class 3, is CoreText's −0.2).
struct FaceTraits: Equatable {
    let weight: Double
    let width: Double
    let italic: Bool

    /// Weight words, longest first so "semibold" is not read as "bold", on
    /// CoreText's scale (SwiftUI's nine weights).
    private static let weightWords: [(String, Double)] = [
        ("ultralight", -0.8), ("extralight", -0.8), ("ultrathin", -0.8), ("hairline", -0.8),
        ("thin", -0.6), ("light", -0.4), ("book", 0), ("regular", 0), ("roman", 0), ("normal", 0),
        ("medium", 0.23), ("semibold", 0.3), ("demibold", 0.3), ("demi", 0.3), ("extrabold", 0.56),
        ("ultrabold", 0.62), ("heavy", 0.56), ("extrablack", 0.62), ("black", 0.62), ("bold", 0.4),
    ]
    /// `usWeightClass` 100…900 on the same scale.
    private static let classWeights: [(Int, Double)] = [
        (100, -0.8), (200, -0.6), (300, -0.4), (400, 0), (500, 0.23), (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62),
    ]

    init(style: String, weightClass: Int, widthClass: Int) {
        let words = style.lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" }
        italic = words.contains("italic") || words.contains("oblique")
        width = widthClass > 0 ? Double(widthClass - 5) / 10 : 0
        if let word = Self.weightWords.first(where: { words.contains($0.0) }) {
            weight = word.1
        } else if italic || words.isEmpty {
            // "Italic" alone is the family's regular slanted (Cochin-Italic is
            // class 500 and CoreText's 0).
            weight = 0
        } else if weightClass > 0 {
            weight = Self.classWeights.min { abs($0.0 - weightClass) < abs($1.0 - weightClass) }!.1
        } else {
            weight = 0
        }
    }
}
