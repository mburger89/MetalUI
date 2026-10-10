import Testing
import Foundation
import MetalUIFreeType
import MetalUITextSystem
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

// MARK: - SMK port gaps, lane 1: design families (ruling `SG-C`, spec §5 tests 1.5–1.7)

/// **1.5** (`SG-C` items 1, 3). Each design is registered as the **first
/// family in its list with an installed face**, by that face's own spelling,
/// and nothing is read until a request for the design resolves: over the test
/// directory `.monospaced` is Source Sans 3 (the first entry is not
/// installed), `.serif` Noto Sans Arabic, and `.rounded` — no list — the
/// default face. Resolving a design also reads the cascade's default face
/// (`resolve` loads the cascade, SF-C), so the log after the first resolve is
/// exactly that face and the design's. Red before: does not compile (no
/// `designFamilies:`).
/// Mutations **M1.5a** (skip the design loop), **M1.5b** (register the last
/// installed family), **M1.5c** (register the first entry whether installed
/// or not) — each reddens.
@Test func aDesignResolvesToItsFirstInstalledFamilyAndReadsNothingUntilAsked() throws {
    let log = LoadLog()
    let resolver = try SystemFonts.resolver(directories: [fontsDirectory],
                                            defaultFamilies: ["Noto Sans"],
                                            fallbackFamilies: [],
                                            designFamilies: [.monospaced: ["Not Installed", "source sans 3",
                                                                           "Noto Sans Arabic"],
                                                             .serif: ["Noto Sans Arabic"]],
                                            load: log.load)
    #expect(log.paths.isEmpty, "registering a design reads no font")
    let mono = try resolver.resolve(FontDescriptor(size: 13, design: .monospaced))
    #expect(mono.key.postScriptName == "SourceSans3-Regular", "the first installed family of the list")
    // Resolving also reads the cascade's default face (Noto Sans, the
    // default family is the cascade's first entry, SF-C) — never the serif
    // design's face.
    #expect(log.paths.sorted() == ["NotoSans-Regular.ttf", "SourceSans3-Regular.otf"],
            "the resolved face and the cascade's default face only: \(log.paths)")
    let serif = try resolver.resolve(FontDescriptor(size: 13, design: .serif))
    #expect(serif.key.postScriptName == "NotoSansArabic-Regular")
    let rounded = try resolver.resolve(FontDescriptor(size: 13, design: .rounded))
    #expect(rounded.key.postScriptName == "NotoSans-Regular", "a design with no family is the default face")
    #expect(log.paths.sorted() == ["NotoSans-Regular.ttf", "NotoSansArabic-Regular.ttf", "SourceSans3-Regular.otf"],
            "each resolved face read once, nothing else: \(log.paths)")
    // A named family still wins over the design (TE-C item 1).
    #expect(try resolver.resolve(FontDescriptor(family: "Noto Sans", size: 13, design: .monospaced))
                .key.postScriptName == "NotoSans-Regular")
}

/// **1.6** (`SG-C` item 2). The platform's own lists resolve on the fonts the
/// platform ships: macOS's three designs are the first installed names of
/// their lists, computed from the scan — Menlo and Times New Roman where
/// Apple's downloadable SF Mono and New York are absent (measured: the
/// system's own are the hidden ".SF NS Mono"/".New York" families); Windows'
/// monospaced is Cascadia Mono or Consolas (the first of the list the scan
/// finds) and serif Georgia; Linux's are DejaVu Sans Mono and DejaVu Serif
/// where DejaVu is installed (both CI images), else the test says why it
/// asserts nothing. `.rounded` off Apple is the default face. Red before: does
/// not compile. Mutation **M1.6**: `designFamilies` empty — reddens on macOS
/// and in `swift:6.4-noble`.
@Test func thePlatformsOwnDesignFamiliesResolve() throws {
    let faces = SystemFonts.scan(SystemFonts.directories)
    func installed(_ family: String) -> Bool { faces.contains { $0.isFamily(family) } }
    #if os(macOS)
    let resolver = try SystemFonts.resolver()
    // Measured 2026-10-09 (FreeType's family names over `directories`): the
    // system's own SF Mono and New York are the hidden families ".SF NS Mono"
    // and ".New York", so "SF Mono"/"New York" resolve only where Apple's
    // downloadable fonts are installed in /Library/Fonts; Menlo, Times New
    // Roman and Arial Rounded MT Bold ship with macOS. The first installed
    // name of each list is computed from the scan and asserted exactly.
    #expect(installed("Menlo") && installed("Times New Roman") && installed("Arial Rounded MT Bold"),
            "macOS ships each list's fallback")
    let monoFamily = try #require(["SF Mono", "Menlo", "Courier New"].first(where: installed))
    let serifFamily = try #require(["New York", "Times New Roman", "Times"].first(where: installed))
    let roundedFamily = try #require(["SF Pro Rounded", "Arial Rounded MT Bold"].first(where: installed))
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .monospaced)).raster.familyName == monoFamily)
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .serif)).raster.familyName == serifFamily)
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .rounded)).raster.familyName == roundedFamily)
    if !installed("SF Mono") { #expect(monoFamily == "Menlo") }
    if !installed("New York") { #expect(serifFamily == "Times New Roman") }
    #elseif os(Windows)
    let resolver = try SystemFonts.resolver()
    let mono = try #require(["Cascadia Mono", "Consolas", "Courier New"].first(where: installed))
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .monospaced)).raster.familyName == mono)
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .serif)).raster.familyName == "Georgia")
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .rounded)).raster.familyName
            == resolver.resolve(family: nil, size: 13).raster.familyName)
    #else
    guard installed("DejaVu Sans Mono") && installed("DejaVu Serif") else {
        print("SG-C 1.6: DejaVu Sans Mono/Serif not installed here; nothing asserted")
        return
    }
    let resolver = try SystemFonts.resolver(designFamilies: SystemFonts.linuxDesignFamilies(fontconfig: { _ in nil }))
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .monospaced)).raster.familyName == "DejaVu Sans Mono")
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .serif)).raster.familyName == "DejaVu Serif")
    #expect(try resolver.resolve(FontDescriptor(size: 13, design: .rounded)).raster.familyName
            == resolver.resolve(family: nil, size: 13).raster.familyName)
    // The real lists (fontconfig's answer first where `fc-match` exists) resolve too.
    let real = try SystemFonts.resolver()
    #expect(try real.resolve(FontDescriptor(size: 13, design: .monospaced)).raster.familyName
            != real.resolve(family: nil, size: 13).raster.familyName, "a monospaced face, not the default")
    #endif
}

/// **1.7** (`SG-C` item 4). fontconfig's answer for `monospace` and `serif`
/// leads each Linux list, and no answer leaves the fixed lists; `.rounded` has
/// none. The query is injected, so this runs on every platform (CI's images
/// have no `fc-match`). Red before: does not compile. Mutation **M1.7**:
/// fontconfig's answer appended last — reddens.
@Test func fontconfigsAnswerLeadsEachDesignsLinuxList() {
    let answers = ["monospace": "Hack", "serif": "Gelasio"]
    var asked: [String] = []
    let lists = SystemFonts.linuxDesignFamilies(fontconfig: { asked.append($0); return answers[$0] })
    #expect(Set(asked) == ["monospace", "serif"], "one query per generic family: \(asked)")
    #expect(lists[.monospaced]?.first == "Hack" && lists[.serif]?.first == "Gelasio")
    #expect(lists[.monospaced]?.dropFirst().first == "DejaVu Sans Mono")
    #expect(lists[.rounded] == nil)
    let fixed = SystemFonts.linuxDesignFamilies(fontconfig: { _ in nil })
    #expect(fixed[.monospaced] == ["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Ubuntu Mono", "FreeMono"])
    #expect(fixed[.serif] == ["DejaVu Serif", "Noto Serif", "Liberation Serif", "FreeSerif"])
    #expect(lists[.monospaced].map { Array($0.dropFirst()) } == fixed[.monospaced])
}
