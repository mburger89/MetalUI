import CoreText
import Foundation
import Testing
@testable import MetalUIPortableText
@testable import MetalUIText

// FN-B: `PortableFontResolver` resolves a family request to the same face as
// `FontResolver.resolve(family:size:)` (`CTFontCreateWithName`) does, with the
// bundled fonts registered in both. CoreText's substitute (Helvetica on
// macOS) and the portable default face are the same answer: "not a
// registered name".
//
// Measured before the resolver was written (2026-09-23, macOS 27.0), with the
// three bundled faces registered for the process: a name matches a face's
// PostScript, family or full name, ignoring case; `"NotoSans"`, `"Noto  Sans"`,
// `" Noto Sans"`, `"Noto Sans "`, `"Noto"`, `"Source Sans"`, `"Source Sans 3
// Regular"`, `""` and style-qualified names match nothing.

let resolverQueries = [
    "Noto Sans", "NotoSans-Regular", "Noto Sans Regular", "noto sans", "NOTO SANS", "notosans-regular",
    "NotoSans", "Noto  Sans", " Noto Sans", "Noto Sans ", "Noto", "Noto Sans Arabic", "NotoSansArabic-Regular",
    "noto sans arabic regular", "Source Sans 3", "SourceSans3-Regular", "Source Sans 3 Regular", "source sans 3",
    "SOURCESANS3-REGULAR", "Source Sans", "Nope", "", "Noto Sans Bold", "Noto Sans-Bold", "Noto Sans Italic",
    "Noto Sans\u{0}", "Nöto Sans", "Helvetica",
]

let bundledFaces = ["NotoSans-Regular.ttf", "SourceSans3-Regular.otf", "NotoSansArabic-Regular.ttf"]

/// The bundled faces registered with CoreText for the duration of `body`.
func withBundledFacesRegistered<T>(_ body: () throws -> T) throws -> T {
    let urls = bundledFaces.map {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts").appendingPathComponent($0) as CFURL
    }
    for url in urls { CTFontManagerRegisterFontsForURL(url, .process, nil) }
    defer { for url in urls { CTFontManagerUnregisterFontsForURL(url, .process, nil) } }
    return try body()
}

/// A resolver over the three bundled faces whose default is `defaultFace`,
/// the other two registered after it.
func bundledResolver(default defaultFace: String = "NotoSans-Regular.ttf") throws -> PortableFontResolver {
    let resolver = try PortableFontResolver(defaultFont: fontBytes(defaultFace))
    for face in bundledFaces where face != defaultFace { try resolver.register(fontBytes(face)) }
    return resolver
}

/// A face CoreText resolved to, as the portable answer names it: a bundled
/// face's PostScript name, or `nil` for "not a bundled face" (the substitute).
func coreTextFace(_ family: String) -> String? {
    let name = FontResolver.resolve(family: family, size: 13).key.postScriptName
    return ["NotoSans-Regular", "SourceSans3-Regular", "NotoSansArabic-Regular"].contains(name) ? name : nil
}

/// Run once per default face: a query that should substitute and wrongly
/// matched the default's own name would look right in the run where that face
/// is the default, and is caught in the other two.
@Test func everyQueryResolvesToTheFaceCoreTextResolvesTo() throws {
    try withBundledFacesRegistered {
        for defaultFace in bundledFaces {
            let resolver = try bundledResolver(default: defaultFace)
            let defaultName = try resolver.resolve(family: nil, size: 13).key.postScriptName
            var substitutes = 0
            for query in resolverQueries {
                let portable = try resolver.resolve(family: query, size: 13).key.postScriptName
                if let apple = coreTextFace(query) {
                    #expect(portable == apple, "\(query.debugDescription), default \(defaultFace)")
                } else {
                    substitutes += 1
                    // CoreText substituted: the portable resolver gives its default.
                    #expect(portable == defaultName, "\(query.debugDescription), default \(defaultFace)")
                }
            }
            // Both halves are exercised: 13 names match a bundled face, 15 do not.
            #expect(substitutes == 15)
        }
    }
}

@Test func nilIsTheDefaultFace() throws {
    #expect(try bundledResolver().resolve(family: nil, size: 13).key.postScriptName == "NotoSans-Regular")
    let sourceDefault = try PortableFontResolver(defaultFont: fontBytes("SourceSans3-Regular.otf"))
    #expect(try sourceDefault.resolve(family: nil, size: 13).key.postScriptName == "SourceSans3-Regular")
    #expect(try sourceDefault.resolve(family: "Nope", size: 13).key.postScriptName == "SourceSans3-Regular")
}

@Test func aResolvedFontIsMemoizedPerFaceAndSize() throws {
    let resolver = try bundledResolver()
    let a = try resolver.resolve(family: "Noto Sans", size: 13)
    #expect(try resolver.resolve(family: "NotoSans-Regular", size: 13) === a)
    #expect(try resolver.resolve(family: nil, size: 13) === a)
    #expect(try resolver.resolve(family: "Noto Sans", size: 14) !== a)
    #expect(try resolver.resolve(family: "Noto Sans", size: 14).size == 14)
}

/// The earlier registration wins a name two faces share. Seen through the
/// memo: the default face is registration 0, so a name resolving to it is the
/// very instance `nil` resolves to; a later copy of the same file would be a
/// different face, and a different instance.
@Test func theFirstRegisteredFaceWinsASharedName() throws {
    let resolver = try PortableFontResolver(defaultFont: fontBytes("NotoSans-Regular.ttf"))
    try resolver.register(fontBytes("NotoSans-Regular.ttf"))
    #expect(try resolver.resolve(family: "Noto Sans", size: 13) === resolver.resolve(family: nil, size: 13))
}

@Test func theFaceNamesAreReadFromTheFont() throws {
    let names = try FreeTypeFontNames(data: fontBytes("NotoSansArabic-Regular.ttf"), faceIndex: 0)
    #expect(names.postScript == "NotoSansArabic-Regular")
    #expect(names.family == "Noto Sans Arabic")
    #expect(names.full == "Noto Sans Arabic Regular")
    let source = try FreeTypeFontNames(data: fontBytes("SourceSans3-Regular.otf"), faceIndex: 0)
    #expect(source.full == "Source Sans 3")
}

@Test func aNonPositiveSizeTraps() async {
    await #expect(processExitsWith: .failure) {
        _ = try? PortableFontResolver(defaultFont: fontBytes("NotoSans-Regular.ttf")).resolve(family: nil, size: 0)
    }
}
