// Ruling `SG-E` (MG-27, `LK-X`): Swift's SIL type-lowering verifier
// (`verifyLexicalLowering`, "Found non-trivial lexical leaf in non-trivial
// non-lexical type?!") on a `Component` whose content holds, beside other
// content, a nested `Component` whose own content is a loop. Only compilers
// built with assertions check it — Windows CI's 6.4.0+Asserts and the Mac
// development snapshot — so no macOS or Linux job can see it. This file is the
// env-gated guard (`METALUI_RUN_ASSERTS_COMPILER_TEST=1`; counts while
// skipped). It imports no MetalUI module: it builds a scratch package against
// this checkout with the asserts toolchain.
import Foundation
import Testing

/// The repository root, from this file's own path.
private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// The verifier's own name, which every one of its crash reports carries.
private let assertionMarker = "verifyLexicalLowering"

/// `LK-X`'s minimal trigger (its table's "`Column` of the `Text` and a
/// `Component` whose content is a bare `ForEach`" row).
private let lkxFixture = """
    import MetalUI

    struct Inner: Component {
        var content: some ElementGroup { ForEach([0, 1, 2], id: \\.self) { i in Text("\\(i)") } }
    }

    struct Outer: Component {
        var content: some ElementGroup {
            Column {
                Text("a")
                Inner()
            }
        }
    }

    """

/// MG-27's shape: a `Component` whose content is a `switch` over four cases,
/// one a nested `Component` holding a loop, one an `AnyElement`.
private let mg27Fixture = """
    import MetalUI

    enum Mode { case a, b, c, d }

    struct Rows: Component {
        var items: [Int]
        var content: some ElementGroup {
            Column { ForEach(items, id: \\.self) { i in Text("row \\(i)") } }
        }
    }

    struct Shell: Component {
        var mode: Mode
        var content: some ElementGroup {
            switch mode {
            case .a: Text("a")
            case .b: Rows(items: [1, 2, 3])
            case .c: AnyElement(Box { Text("c") })
            case .d: Column { Text("d"); Text("e") }
            }
        }
    }

    """

/// The workaround both rulings name: the looping member is a `@MainActor`
/// function instead of a nested `Component`.
private let workaroundFixture = """
    import MetalUI

    enum Mode { case a, b, c, d }

    @MainActor func rows(_ items: [Int]) -> some ElementGroup {
        Column { ForEach(items, id: \\.self) { i in Text("row \\(i)") } }
    }

    @MainActor func innerRows() -> some ElementGroup {
        ForEach([0, 1, 2], id: \\.self) { i in Text("\\(i)") }
    }

    struct Shell: Component {
        var mode: Mode
        var content: some ElementGroup {
            switch mode {
            case .a: Text("a")
            case .b: rows([1, 2, 3])
            case .c: AnyElement(Box { Text("c") })
            case .d: Column { Text("d"); Text("e") }
            }
        }
    }

    struct Outer: Component {
        var content: some ElementGroup {
            Column {
                Text("a")
                innerRows()
            }
        }
    }

    """

/// The reduction with no MetalUI import (`SG-E`'s upstream report): a
/// protocol extension's witness returns `Content.Prepaint`, an outer
/// conformer's opaque content holds an inner conformer whose opaque content's
/// `Prepaint` is an eager-move standard-library type (`String`; `Array`,
/// `Set`, `Dictionary` and `Substring` too, a class or `Int` not).
private let standaloneFixture = """
    public protocol Group {
        associatedtype Prepaint
        func prepaint() -> Prepaint
    }
    public struct Text: Group {
        public func prepaint() -> String { "" }
    }
    public struct Pair<A: Group, B: Group>: Group {
        var a: A; var b: B
        public struct Prepaint { var a: A.Prepaint; var b: B.Prepaint }
        public func prepaint() -> Prepaint { Prepaint(a: a.prepaint(), b: b.prepaint()) }
    }
    public protocol Component: Group {
        associatedtype Content: Group
        var content: Content { get }
    }
    extension Component {
        public func prepaint() -> Content.Prepaint { content.prepaint() }
    }
    struct Inner: Component {
        var content: some Group { Text() }
    }
    struct Outer: Component {
        var content: some Group { Pair(a: Text(), b: Inner()) }
    }

    """

/// Runs `swift` with `arguments` in `directory` under the asserts toolchain:
/// on macOS the `.xctoolchain` at `METALUI_ASSERTS_TOOLCHAIN` (default the
/// development snapshot `LK-X` and `SG-E` measured with), selected by its
/// bundle identifier through `TOOLCHAINS`; elsewhere (Linux) the `swift` on
/// `PATH`, through `/usr/bin/env`. **Not run on Windows** — there is no
/// `/usr/bin/env`; Windows CI's 6.4.0+Asserts compiler is checked by hand
/// (human check `SG6`). Its exit status and output, interleaved.
private func swiftUnderAssertsToolchain(_ arguments: [String], in directory: URL) throws -> (Int32, String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    var environment = ProcessInfo.processInfo.environment
    #if os(macOS)
    let toolchain = environment["METALUI_ASSERTS_TOOLCHAIN"]
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a.xctoolchain").path
    let plist = try Data(contentsOf: URL(fileURLWithPath: toolchain).appendingPathComponent("Info.plist"))
    let info = try #require(try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
    environment["TOOLCHAINS"] = try #require(info["CFBundleIdentifier"] as? String, "no bundle id in \(toolchain)")
    #endif
    process.environment = environment
    process.arguments = ["swift"] + arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

/// **3.2** (`SG-E` item 4; env-gated `METALUI_RUN_ASSERTS_COMPILER_TEST=1`, a
/// debug and a release build of MetalUI under the asserts toolchain; counts
/// while skipped). A scratch package against this checkout holds `LK-X`'s
/// trigger, MG-27's shape, the function workaround and the MetalUI-free
/// reduction, one target each; in debug and in release:
///
/// - the reduction **asserts** — the positive control: a toolchain without
///   assertions (or one that fixed the bug) proves nothing about the other
///   arms, so this arm reddens first and says which;
/// - `LK-X`'s and MG-27's shapes **compile** — `Component`'s prepaint record
///   is one heap box (`ComponentPrepaint`, `SG-E` item 2 adopted), so an
///   enclosing record holds a class reference, never the inner content's
///   eager-move leaf; red before the box with the assertion;
/// - the workaround compiles.
///
/// Mutation: un-box (`Component`'s `GroupPrepaint` back to
/// `Content.GroupPrepaint`) — the two shape arms redden under the env run.
@Test(.enabled(if: ProcessInfo.processInfo.environment["METALUI_RUN_ASSERTS_COMPILER_TEST"] == "1"))
func theComponentSwitchShapeAgainstAnAssertsCompiler() throws {
    // One stable directory per checkout (a hash of its path, so two worktrees
    // running this at once never share a Package.swift), so a re-run builds
    // MetalUI incrementally.
    var hash: UInt64 = 5381
    for byte in checkout.path.utf8 { hash = hash &* 33 &+ UInt64(byte) }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("metalui-asserts-compiler-\(String(hash, radix: 16))")
    let fixtures = [("LKX", lkxFixture, true), ("MG27", mg27Fixture, true),
                    ("Workaround", workaroundFixture, true), ("Standalone", standaloneFixture, false)]
    for (name, source, _) in fixtures {
        let directory = root.appendingPathComponent("Sources/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try source.write(to: directory.appendingPathComponent("Fixture.swift"), atomically: true, encoding: .utf8)
    }
    let checkoutPath = checkout.path.replacingOccurrences(of: "\\", with: "/")
    let targets = fixtures.map { name, _, importsMetalUI in
        importsMetalUI
            ? ".target(name: \"\(name)\", dependencies: [.product(name: \"MetalUI\", package: \"MetalUI\")])"
            : ".target(name: \"\(name)\")"
    }
    try """
        // swift-tools-version: 6.4
        import PackageDescription
        let package = Package(
            name: "AssertsCompilerFixture",
            platforms: [.macOS(.v14)],
            dependencies: [.package(name: "MetalUI", path: "\(checkoutPath)")],
            targets: [
                \(targets.joined(separator: ",\n            "))
            ]
        )

        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

    for configuration in ["debug", "release"] {
        let (standaloneStatus, standalone) = try swiftUnderAssertsToolchain(
            ["build", "-c", configuration, "--target", "Standalone"], in: root)
        #expect(standaloneStatus != 0 && standalone.contains(assertionMarker),
                """
                \(configuration): the MetalUI-free reduction no longer asserts — this toolchain has no \
                assertions, or it fixed the bug (then the box may go, SG-E): \(standalone.suffix(1500))
                """)
        for name in ["LKX", "MG27", "Workaround"] {
            let (status, output) = try swiftUnderAssertsToolchain(
                ["build", "-c", configuration, "--target", name], in: root)
            print("SG-E \(configuration) \(name): status=\(status) asserted=\(output.contains(assertionMarker))")
            #expect(status == 0 && !output.contains(assertionMarker),
                    "\(configuration) \(name) did not compile: \(output.suffix(3000))")
        }
    }
}
