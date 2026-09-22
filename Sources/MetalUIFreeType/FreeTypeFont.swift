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

    /// The face's glyph for a Unicode scalar, or 0 (`.notdef`) — for tests,
    /// until a shaper supplies glyph ids.
    public func glyph(for scalar: Unicode.Scalar) -> UInt16 {
        UInt16(truncatingIfNeeded: FT_Get_Char_Index(face, FT_ULong(scalar.value)))
    }
}
