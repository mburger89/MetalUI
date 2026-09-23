import CFreeType
import MetalUIScene

/// A FreeType call that failed, with FreeType's own error code.
public struct FreeTypeError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let code: Int32
    public var description: String { "\(operation) failed with FreeType error \(code)" }
}

/// One face of a font file, opened with FreeType at one point size — the
/// non-Apple counterpart of `MetalUIText`'s `ResolvedFont` (ruling FT-C).
///
/// Owns its own `FT_Library`: FreeType objects are not thread-safe, and a
/// library per font keeps two fonts from ever sharing one. Not `Sendable` for
/// the same reason.
public final class FreeTypeFont {
    let library: FT_Library
    let face: FT_Face
    /// FreeType reads the face from this memory for the face's whole life.
    private let storage: UnsafeMutableRawBufferPointer

    /// The requested size, in points — one point is one device pixel at scale 1.
    public let size: Double

    /// The identity the atlas keys on (ruling FT-F).
    public let key: FontKey

    /// Opens face `faceIndex` of the font file `data` at `size` points.
    public init(data: [UInt8], faceIndex: Int = 0, size: Double) throws {
        precondition(size.isFinite && size > 0, "a font size must be positive and finite")
        var library: FT_Library?
        let initError = FT_Init_FreeType(&library)
        guard initError == 0, let library else { throw FreeTypeError(operation: "FT_Init_FreeType", code: initError) }

        let storage = UnsafeMutableRawBufferPointer.allocate(byteCount: max(data.count, 1), alignment: 16)
        data.withUnsafeBytes { storage.copyMemory(from: $0) }
        var face: FT_Face?
        let faceError = FT_New_Memory_Face(library, storage.baseAddress!.assumingMemoryBound(to: FT_Byte.self),
                                           FT_Long(data.count), FT_Long(faceIndex), &face)
        guard faceError == 0, let face else {
            FT_Done_FreeType(library)
            storage.deallocate()
            throw FreeTypeError(operation: "FT_New_Memory_Face", code: faceError)
        }
        guard face.pointee.face_flags & FT_Long(FT_FACE_FLAG_SCALABLE) != 0 else {
            FT_Done_Face(face); FT_Done_FreeType(library); storage.deallocate()
            throw FreeTypeError(operation: "a scalable outline face", code: -1)
        }
        // FT-F: a key without a PostScript name has no first component.
        guard let name = FT_Get_Postscript_Name(face).map({ String(cString: $0) }), !name.isEmpty else {
            FT_Done_Face(face); FT_Done_FreeType(library); storage.deallocate()
            throw FreeTypeError(operation: "FT_Get_Postscript_Name", code: -1)
        }

        self.library = library
        self.face = face
        self.storage = storage
        self.size = size
        // Static faces only this step (FT-F): no variation axes, and FreeType
        // applies no font matrix, so the transform is the identity — which is
        // what CoreText reports for a plain file font. Every component is read
        // off the opened face or is FreeType's fixed behaviour, never a request.
        self.key = FontKey(resolvedPostScriptName: name, size: size, variations: [],
                           matrix: FontKey.Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0))
    }

    deinit {
        FT_Done_Face(face)
        FT_Done_FreeType(library)
        storage.deallocate()
    }

    /// The face's design units per em — the unit its outlines are stored in
    /// (`FT-D` scales them to device pixels). `PortableFont` checks it against
    /// HarfBuzz's (`PT-B`).
    public var unitsPerEm: Int { Int(face.pointee.units_per_EM) }

    /// The face's `hhea` ascender, descender (negative below the baseline)
    /// and line gap, in design units — the three numbers CoreText's
    /// `CTFontGetAscent`/`Descent`/`Leading` scale (measured, `LB-F`).
    ///
    /// **Not `FT_Face.ascender`/`descender`/`height`**: FreeType fills those
    /// from OS/2's typographic metrics when the face sets `USE_TYPO_METRICS`,
    /// and CoreText does not — both Noto faces set it, with typo numbers equal
    /// to `hhea`'s, so only a patched face tells the two apart (record §31).
    /// A face with no `hhea` table falls back to FreeType's numbers.
    public var horizontalHeader: (ascender: Int, descender: Int, lineGap: Int) {
        if let table = FT_Get_Sfnt_Table(face, FT_SFNT_HHEA) {
            let hhea = table.assumingMemoryBound(to: TT_HoriHeader.self).pointee
            return (Int(hhea.Ascender), Int(hhea.Descender), Int(hhea.Line_Gap))
        }
        let face = face.pointee
        return (Int(face.ascender), Int(face.descender),
                Int(face.height) - Int(face.ascender) + Int(face.descender))
    }

    /// The face's family name (`FT_Face.family_name`, from the name table's
    /// family entry), e.g. `"Noto Sans"`.
    public var familyName: String {
        face.pointee.family_name.map { String(cString: $0) } ?? ""
    }

    /// The face's PostScript name, e.g. `"NotoSans-Regular"` — `FontKey`'s
    /// first component (FT-F).
    public var postScriptName: String { key.postScriptName }

    /// The face's full name — the name table's entry 4, e.g. `"Noto Sans
    /// Regular"` — or `""` if it has none. Read from a Windows-platform
    /// (UTF-16BE) record for US English first, then any Windows Unicode
    /// record, then a Macintosh Roman one.
    public var fullName: String { name(id: 4) }

    /// Name table entry `id`, decoded as ``fullName`` describes.
    func name(id: UInt16) -> String {
        var best: (rank: Int, value: String)?
        for index in 0..<FT_Get_Sfnt_Name_Count(face) {
            var record = FT_SfntName()
            guard FT_Get_Sfnt_Name(face, index, &record) == 0, record.name_id == id,
                  let bytes = record.string else { continue }
            let raw = Array(UnsafeBufferPointer(start: bytes, count: Int(record.string_len)))
            let rank: Int
            let value: String
            switch (record.platform_id, record.encoding_id) {
            case (3, 1), (3, 10):
                rank = record.language_id == 0x409 ? 0 : 1
                let units = stride(from: 0, to: raw.count - 1, by: 2).map { UInt16(raw[$0]) << 8 | UInt16(raw[$0 + 1]) }
                value = String(decoding: units, as: UTF16.self)
            case (1, 0):
                rank = 2
                value = String(decoding: raw, as: UTF8.self)   // ASCII in practice
            default:
                continue
            }
            if best == nil || rank < best!.rank { best = (rank, value) }
        }
        return best?.value ?? ""
    }

    /// FreeType's name for the face's outline format: `"TrueType"` for a
    /// `glyf` face, `"CFF"` for an OpenType/CFF one (`FT_Get_Font_Format`).
    public var format: String {
        FT_Get_Font_Format(face).map { String(cString: $0) } ?? ""
    }

    /// The face's glyph for a Unicode scalar, or 0 (`.notdef`) — for tests
    /// and for `PT-B`'s cross-engine check; a shaper supplies the ids that
    /// are actually drawn.
    public func glyph(for scalar: Unicode.Scalar) -> UInt16 {
        UInt16(truncatingIfNeeded: FT_Get_Char_Index(face, FT_ULong(scalar.value)))
    }
}
