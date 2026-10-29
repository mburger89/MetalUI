import Foundation
import Testing
@testable import MetalUIShaderCompile

// Run-time shader compiler lookup (item XP-G25, rulings RC-C, RC-N, spec 5 tests 1-6 and 12b).
// Pure: no library, no GPU, no file system. A fake file system is a set of paths.

private typealias Locator = RuntimeLibraryLocator

private struct FakeFiles {
    var files: Set<String> = []
    var directories: Set<String> = []
    func attempts(explicit: String? = nil, environment: [String: String] = [:], executableDirectory: String? = nil,
                  windows: Bool = false, macOS: Bool = true) -> [Locator.Attempt] {
        Locator.attempts(explicit: explicit, environment: environment, executableDirectory: executableDirectory,
                         windows: windows, macOS: macOS, fileExists: { files.contains($0) },
                         directoryExists: { directories.contains($0) })
    }
}

private let dylib = "libSDL3_shadercross.dylib"

/// **Test 1** (`RC-C`, `SX-B`). Mutations: swap the variable and explicit candidates; drop the `<exe>/lib` arm;
/// put it after `../lib`.
@Test func theLookupOrderIsExplicitThenVariableThenBesideThenSubLibThenParentLibThenSiblingThenLoaderPath() throws {
    let all = FakeFiles(files: ["/x/\(dylib)", "/v/\(dylib)", "/app/bin/\(dylib)", "/app/bin/lib/\(dylib)", "/app/lib/\(dylib)",
                                "/sdk/lib/\(dylib)"],
                        directories: [])
    let env = ["METALUI_SHADERCROSS_LIB": "/v/\(dylib)", "METALUI_SHADERCROSS": "/sdk/bin/shadercross"]
    // explicit wins over everything
    #expect(try Locator.loadOrder(all.attempts(explicit: "/x/\(dylib)", environment: env, executableDirectory: "/app/bin")) == ["/x/\(dylib)"])
    // then the variable
    #expect(try Locator.loadOrder(all.attempts(environment: env, executableDirectory: "/app/bin")) == ["/v/\(dylib)"])
    // then beside the executable, its lib, ../lib, the tool's sibling lib, the loader name
    let rest = try Locator.loadOrder(all.attempts(environment: ["METALUI_SHADERCROSS": "/sdk/bin/shadercross"],
                                                  executableDirectory: "/app/bin"))
    #expect(rest == ["/app/bin/\(dylib)", "/app/bin/lib/\(dylib)", "/app/lib/\(dylib)", "/sdk/lib/\(dylib)", dylib])
    // the sources are ranked in that order
    let sources = all.attempts(environment: ["METALUI_SHADERCROSS": "/sdk/bin/shadercross"], executableDirectory: "/app/bin").map(\.source)
    #expect(sources == sources.sorted())
    #expect(sources.first == .besideExecutable)
    #expect(sources.contains(.besideExecutableSubLib))
    #expect(sources.last == .loaderPath)
}

/// **Test 2** (`RC-C`, `BS-C`). Mutation: `continue` past a missing explicit path.
@Test func anExplicitPathThatDoesNotExistIsAnErrorAndNotAFallThrough() {
    let fake = FakeFiles(files: ["/app/bin/\(dylib)"])
    let explicit = fake.attempts(explicit: "/nope/\(dylib)", executableDirectory: "/app/bin")
    #expect(explicit.count == 1, "no other candidate is consulted")
    #expect(throws: ComputeValidationError.self) { try Locator.loadOrder(explicit) }
    let variable = fake.attempts(environment: ["METALUI_SHADERCROSS_LIB": "/nope/\(dylib)"], executableDirectory: "/app/bin")
    #expect(variable.count == 1)
    #expect(throws: ComputeValidationError.self) { try Locator.loadOrder(variable) }
    // an empty value is unset
    #expect(fake.attempts(explicit: "", environment: ["METALUI_SHADERCROSS_LIB": ""], executableDirectory: "/app/bin").count > 1)
}

/// **Test 3** (`RC-C`). Mutation: drop the directory join.
@Test func aVariableNamingADirectoryFindsThePlatformLibraryInIt() throws {
    let mac = FakeFiles(files: ["/d/\(dylib)"], directories: ["/d"])
    #expect(try Locator.loadOrder(mac.attempts(environment: ["METALUI_SHADERCROSS_LIB": "/d"])) == ["/d/\(dylib)"])
    // Linux: .so.0 is preferred, .so accepted
    let linux = FakeFiles(files: ["/d/libSDL3_shadercross.so"], directories: ["/d"])
    #expect(try Locator.loadOrder(linux.attempts(environment: ["METALUI_SHADERCROSS_LIB": "/d"], macOS: false))
            == ["/d/libSDL3_shadercross.so"])
    let win = FakeFiles(files: ["/d/SDL3_shadercross.dll"], directories: ["/d"])
    #expect(try Locator.loadOrder(win.attempts(environment: ["METALUI_SHADERCROSS_LIB": "/d"], windows: true, macOS: false))
            == ["/d/SDL3_shadercross.dll"])
    // a directory without the library is the named error
    let empty = FakeFiles(directories: ["/e"])
    #expect(throws: ComputeValidationError.self) { try Locator.loadOrder(empty.attempts(environment: ["METALUI_SHADERCROSS_LIB": "/e"])) }
}

/// **Test 4** (`RC-C`, `BS-C`). Mutation: look in `bin` instead of `../lib`.
@Test func theShadercrossExecutableVariableOffersItsSiblingLibDirectory() throws {
    let fake = FakeFiles(files: ["/sdk/lib/\(dylib)", "/sdk/bin/\(dylib)"])
    let order = try Locator.loadOrder(fake.attempts(environment: ["METALUI_SHADERCROSS": "/sdk/bin/shadercross"]))
    #expect(order == ["/sdk/lib/\(dylib)", dylib])
    let sibling = fake.attempts(environment: ["METALUI_SHADERCROSS": "/sdk/bin/shadercross"]).first { $0.source == .executableSibling }
    #expect(sibling?.path == "/sdk/lib/\(dylib)")
}

/// **Test 5** (`RC-C`). Mutation: drop one candidate's reason.
@Test func theErrorNamesEveryPathTriedWithItsReason() {
    let fake = FakeFiles()
    let attempts = fake.attempts(environment: ["METALUI_SHADERCROSS": "/sdk/bin/shadercross"], executableDirectory: "/app/bin")
    let lines = Locator.describe(attempts, loadFailures: [dylib: "image not found"])
    #expect(lines.count == attempts.count)
    for (line, attempt) in zip(lines, attempts) {
        #expect(line.hasPrefix(attempt.path + ": "), "\(line)")
        #expect(line.count > attempt.path.count + 2, "a reason follows the path")
    }
    #expect(lines.contains("/app/bin/\(dylib): no such file (beside the executable)"))
    #expect(lines.contains("/app/bin/lib/\(dylib): no such file (in lib beside the executable)"))
    #expect(lines.contains("\(dylib): failed to load: image not found"))
    #expect(lines.contains { $0.contains("left to the loader path") } == false, "a refused loader name reports its failure instead")
    let message = ComputeValidationError.libraryMissing(lines).description
    for attempt in attempts { #expect(message.contains(attempt.path)) }
}

/// **Test 6** (`RC-C`). Mutation: return the `.so` name on macOS.
@Test func thePlatformLibraryNamesAreDylibSoAndDll() {
    #expect(Locator.libraryNames(windows: false, macOS: true) == ["libSDL3_shadercross.dylib"])
    #expect(Locator.libraryNames(windows: false, macOS: false) == ["libSDL3_shadercross.so.0", "libSDL3_shadercross.so"])
    #expect(Locator.libraryNames(windows: true, macOS: false) == ["SDL3_shadercross.dll"])
}

/// **Test 12b** (`RC-N`). Mutation: preload nothing.
@Test func thePreloadSetIsTheDependentsInTheLibrarysDirectory() throws {
    let listing = ["libSDL3_shadercross.0.0.0.dylib", "libSDL3_shadercross.dylib", "libdxcompiler.dylib", "libdxil.dylib",
                   "libspirv-cross-c-shared.0.dylib", "libspirv-cross-c-shared.dylib", "libspirv-cross-c-shared.0.68.0.dylib",
                   "libdxilconv.dylib", "README.txt", "libdxcompiler.dylib.bak"]
    let mac = try Locator.preloadSet(directory: "/lib", listing: listing, windows: false, macOS: true)
    #expect(mac == ["/lib/libdxcompiler.dylib", "/lib/libspirv-cross-c-shared.dylib", "/lib/libspirv-cross-c-shared.0.dylib",
                    "/lib/libspirv-cross-c-shared.0.68.0.dylib", "/lib/libdxil.dylib"])
    // dxil is optional
    let noDxil = try Locator.preloadSet(directory: "/lib", listing: ["libdxcompiler.so", "libspirv-cross-c-shared.so.0"],
                                        windows: false, macOS: false)
    #expect(noDxil == ["/lib/libdxcompiler.so", "/lib/libspirv-cross-c-shared.so.0"])
    // the two required ones are named when absent
    do {
        _ = try Locator.preloadSet(directory: "/lib", listing: ["libdxcompiler.so"], windows: false, macOS: false)
        Issue.record("spirv-cross missing must throw")
    } catch { #expect("\(error)".contains("spirv-cross")) }
    do {
        _ = try Locator.preloadSet(directory: "/lib", listing: ["libspirv-cross-c-shared.so"], windows: false, macOS: false)
        Issue.record("dxcompiler missing must throw")
    } catch { #expect("\(error)".contains("dxcompiler")) }
    let win = try Locator.preloadSet(directory: "C:/app", listing: ["dxcompiler.dll", "spirv-cross-c-shared.dll", "dxil.dll", "x.dll"],
                                     windows: true, macOS: false)
    #expect(win == ["C:/app/dxcompiler.dll", "C:/app/spirv-cross-c-shared.dll", "C:/app/dxil.dll"])
}

/// **Test 2** (`SX-B`). Mutation: join `"lib"` onto the parent of the executable's directory instead of the directory.
@Test func aLibraryOnlyInExecutableLibIsChosenOnEveryPlatformNaming() throws {
    let cases: [(windows: Bool, macOS: Bool, names: [String])] = [
        (false, true, ["libSDL3_shadercross.dylib"]),
        (false, false, ["libSDL3_shadercross.so.0", "libSDL3_shadercross.so"]),
        (true, false, ["SDL3_shadercross.dll"]),
    ]
    for c in cases {
        for name in c.names {
            let fake = FakeFiles(files: ["/app/bin/lib/\(name)"])
            let order = try Locator.loadOrder(fake.attempts(executableDirectory: "/app/bin", windows: c.windows, macOS: c.macOS))
            #expect(order.first == "/app/bin/lib/\(name)", "\(name): \(order)")
            #expect(order.last == c.names.last!, "the loader name stays last")
            let sub = fake.attempts(executableDirectory: "/app/bin", windows: c.windows, macOS: c.macOS)
                .filter { $0.source == .besideExecutableSubLib }
            #expect(sub.map(\.path) == c.names.map { "/app/bin/lib/\($0)" })
        }
    }
}

/// **Test 3** (`SX-B`). Mutation: swap the two sources' order.
@Test func theLibraryInTheExecutableDirectoryOutranksOneInItsLibSubdirectory() throws {
    let fake = FakeFiles(files: ["/app/bin/\(dylib)", "/app/bin/lib/\(dylib)"])
    let order = try Locator.loadOrder(fake.attempts(executableDirectory: "/app/bin"))
    #expect(order == ["/app/bin/\(dylib)", "/app/bin/lib/\(dylib)", dylib])
}

/// **Test 4** (`SX-C`, `RC-N`). Mutation: `preloadSet` joins onto a fixed directory.
@Test func thePreloadSetComesFromTheDirectoryOfTheChosenLibrary() throws {
    let fake = FakeFiles(files: ["/app/bin/lib/\(dylib)"])
    let chosen = try #require(try Locator.loadOrder(fake.attempts(executableDirectory: "/app/bin")).first)
    let directory = String(chosen.dropLast("/\(dylib)".count))
    #expect(directory == "/app/bin/lib")
    let set = try Locator.preloadSet(directory: directory,
                                     listing: [dylib, "libdxcompiler.dylib", "libspirv-cross-c-shared.dylib", "libdxil.dylib"],
                                     windows: false, macOS: true)
    #expect(set == ["/app/bin/lib/libdxcompiler.dylib", "/app/bin/lib/libspirv-cross-c-shared.dylib", "/app/bin/lib/libdxil.dylib"])
}

/// **Test 7** (`SX-F` 1). `docs/packaging.md` 4b names the `<exe>/lib` lookup and says Microsoft's DXC is unmeasured.
/// Splits on `\.isNewline`, never `"\n"` (a CRLF checkout makes `"\r\n"` one Character). Mutation: remove either sentence.
@Test func packagingNamesTheExecutableLibLookupAndMarksMicrosoftDXCUnmeasured() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let text = try String(contentsOf: root.appendingPathComponent("docs/packaging.md"), encoding: .utf8)
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    let start = try #require(lines.firstIndex { $0.hasPrefix("### 4b.") })
    let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("### ") } ?? lines.count
    let section = lines[start..<end].joined(separator: " ")
    #expect(section.contains("`<exe>/lib`"), "the lookup sentence names <exe>/lib")
    #expect(section.contains("Microsoft"), "the Microsoft DXC paragraph is in 4b")
    #expect(section.contains("unmeasured"))
    let notices = try String(contentsOf: root.appendingPathComponent("THIRD-PARTY-NOTICES.md"), encoding: .utf8)
    #expect(notices.contains("Microsoft's release"))
}

// Item XP-G27 (rulings HX-D, HX-I tests 4 and 5): the optional SDL3 group of the preload set.

/// **Test 4** (`HX-D`). Mutations: match `hasPrefix("sdl3")` (red: shadercross itself is preloaded); put the group last.
@Test func theSDLGroupIsPreloadedFirstOnlyWhenAsked() throws {
    let cases: [(listing: [String], windows: Bool, macOS: Bool, sdl: [String], dependents: [String])] = [
        (["libSDL3.0.dylib", "libSDL3.dylib", "libSDL3_shadercross.dylib", "libSDL3_test.a", "libdxcompiler.dylib",
          "libspirv-cross-c-shared.0.dylib"], false, true, ["libSDL3.dylib", "libSDL3.0.dylib"],
         ["libdxcompiler.dylib", "libspirv-cross-c-shared.0.dylib"]),
        (["libSDL3.so.0", "libSDL3.so", "libSDL3_shadercross.so.0", "libSDL3_image.so.0", "libdxcompiler.so",
          "libspirv-cross-c-shared.so.0"], false, false, ["libSDL3.so", "libSDL3.so.0"],
         ["libdxcompiler.so", "libspirv-cross-c-shared.so.0"]),
        (["SDL3.dll", "SDL3_shadercross.dll", "SDL3_image.dll", "dxcompiler.dll", "spirv-cross-c-shared.dll"], true, false,
         ["SDL3.dll"], ["dxcompiler.dll", "spirv-cross-c-shared.dll"]),
    ]
    for c in cases {
        let with = try Locator.preloadSet(directory: "/d", listing: c.listing, windows: c.windows, macOS: c.macOS, includingSDL: true)
        #expect(with == (c.sdl + c.dependents).map { "/d/" + $0 }, "\(with)")
        let without = try Locator.preloadSet(directory: "/d", listing: c.listing, windows: c.windows, macOS: c.macOS)
        #expect(without == c.dependents.map { "/d/" + $0 }, "the default set is unchanged: \(without)")
        #expect(without == (try Locator.preloadSet(directory: "/d", listing: c.listing, windows: c.windows, macOS: c.macOS, includingSDL: false)))
    }
}

/// **Test 5** (`HX-D`). Mutation: make the SDL3 group required.
@Test func aDirectoryWithoutSDLStillLoadsTheDependentsSet() throws {
    let listing = ["libdxcompiler.dylib", "libspirv-cross-c-shared.0.dylib", "libdxil.dylib"]
    let with = try Locator.preloadSet(directory: "/d", listing: listing, windows: false, macOS: true, includingSDL: true)
    #expect(with == ["/d/libdxcompiler.dylib", "/d/libspirv-cross-c-shared.0.dylib", "/d/libdxil.dylib"])
    #expect(throws: ComputeValidationError.self) {
        _ = try Locator.preloadSet(directory: "/d", listing: ["libSDL3.0.dylib"], windows: false, macOS: true, includingSDL: true)
    }
}
