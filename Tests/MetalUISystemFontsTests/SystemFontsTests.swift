import Testing
import Foundation
import MetalUIFreeType
@testable import MetalUIPortableText
@testable import MetalUISystemFonts

// SF-A…SF-D. The repository's three test fonts stand in for a system font
// directory, so the answers are the same on every platform; one test reads the
// real system's fonts and asserts what that platform guarantees.

private let fontsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fonts").path

/// Counts the file reads a resolver makes.
private final class LoadLog: @unchecked Sendable {
    var paths: [String] = []
    func load(_ path: String) throws -> [UInt8] {
        paths.append((path as NSString).lastPathComponent)
        return [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    }
}

@Test func aDirectoryScanFindsEveryFaceWithItsNamesInPathOrder() {
    let faces = SystemFonts.scan([fontsDirectory, "/no/such/directory"])
    #expect(faces.map { ($0.path as NSString).lastPathComponent }
            == ["NotoSans-Regular.ttf", "NotoSansArabic-Regular.ttf", "SourceSans3-Regular.otf"])
    #expect(faces.map(\.names.postScript) == ["NotoSans-Regular", "NotoSansArabic-Regular", "SourceSans3-Regular"])
    #expect(faces.map(\.names.family) == ["Noto Sans", "Noto Sans Arabic", "Source Sans 3"])
    #expect(faces.allSatisfy { $0.names.style == "Regular" && $0.names.faceIndex == 0 })
    #expect(SystemFonts.scan(["/no/such/directory"]).isEmpty)
}

@Test func namesAreReadWithoutOpeningAFontAndMatchWhatFreeTypeFontReports() throws {
    let path = fontsDirectory + "/NotoSans-Regular.ttf"
    let names = try #require(FreeTypeFaceNames.read(path: path).first)
    let opened = try FreeTypeFont(data: [UInt8](try Data(contentsOf: URL(fileURLWithPath: path))), size: 12)
    #expect(names.postScript == opened.postScriptName && names.family == opened.familyName
            && names.full == opened.fullName)
    #expect(FreeTypeFaceNames.read(path: fontsDirectory + "/SOURCES.md").isEmpty, "not a font: nothing")
}

/// SF-B, SF-C, SF-D over the test directory: the default is the first
/// installed default family; the cascade is the installed fallback families
/// only; everything else resolves by name; and nothing is read before it is
/// needed.
@Test func theResolverDefaultsCascadesAndLoadsLazily() throws {
    let log = LoadLog()
    let resolver = try SystemFonts.resolver(directories: [fontsDirectory],
                                            defaultFamilies: ["Not Installed", "Source Sans 3"],
                                            fallbackFamilies: ["Noto Sans Arabic", "Not Installed Either"],
                                            load: log.load)
    #expect(log.paths.isEmpty, "a resolver reads no font until one is resolved")
    let base = try resolver.resolve(family: nil, size: 13)
    #expect(base.key.postScriptName == "SourceSans3-Regular")
    #expect(base.fallbacks.map(\.key.postScriptName) == ["NotoSansArabic-Regular"],
            "the cascade is the installed fallback families, not every face")
    #expect(log.paths.sorted() == ["NotoSansArabic-Regular.ttf", "SourceSans3-Regular.otf"])
    // Noto Sans is resolvable by name — read only now — but draws for nobody.
    let noto = try resolver.resolve(family: "noto sans", size: 13)
    #expect(noto.key.postScriptName == "NotoSans-Regular")
    #expect(log.paths.filter { $0 == "NotoSans-Regular.ttf" }.count == 1)
    _ = try resolver.resolve(family: "Noto Sans", size: 20)
    #expect(log.paths.filter { $0 == "NotoSans-Regular.ttf" }.count == 1, "bytes are read once, whatever the size")
    #expect(try resolver.resolve(family: "Unknown Family", size: 13).key.postScriptName == "SourceSans3-Regular")
}

@Test func withNoDefaultFamilyInstalledTheFirstRegularFaceIsTheDefault() throws {
    let resolver = try SystemFonts.resolver(directories: [fontsDirectory], defaultFamilies: ["Nope"],
                                            fallbackFamilies: [])
    #expect(try resolver.resolve(family: nil, size: 12).key.postScriptName == "NotoSans-Regular")
    #expect(throws: SystemFonts.NoFontsFound.self) {
        try SystemFonts.resolver(directories: ["/no/such/directory"])
    }
}

/// The platform's own fonts: what each CI platform guarantees is installed.
/// Linux containers may carry no fonts at all, so there the test only
/// requires that a resolver builds whenever a face was found.
@Test func thePlatformsOwnFontsResolve() throws {
    let faces = SystemFonts.scan(SystemFonts.directories)
    #if os(macOS)
    // Helvetica is a collection: every face is read, in face order, and the
    // default is its regular face, not whichever style comes first.
    let helvetica = FreeTypeFaceNames.read(path: "/System/Library/Fonts/Helvetica.ttc")
    #expect(helvetica.count > 1 && helvetica.map(\.faceIndex) == Array(0..<helvetica.count))
    #expect(helvetica.contains { $0.style == "Bold" })
    let base = try SystemFonts.resolver().resolve(family: nil, size: 13)
    #expect(base.raster.familyName == "Helvetica" && base.key.postScriptName == "Helvetica")
    #elseif os(Windows)
    #expect(try SystemFonts.resolver().resolve(family: nil, size: 13).raster.familyName == "Segoe UI")
    #else
    if !faces.isEmpty { _ = try SystemFonts.resolver().resolve(family: nil, size: 13) }
    #endif
    _ = faces
}

@Test func aFamilysRegularFaceIsRegisteredBeforeItsOtherStyles() {
    func face(_ path: String, _ style: String) -> SystemFonts.Face {
        SystemFonts.Face(path: path, names: FreeTypeFaceNames(faceIndex: 0, postScript: "F-\(style)",
                                                             family: "F", full: "F \(style)", style: style))
    }
    let scanned = [face("a", "Bold"), face("b", "Italic"), face("c", "Regular"), face("d", "Book")]
    #expect(SystemFonts.registrationOrder(scanned).map(\.path) == ["c", "d", "a", "b"])
}
