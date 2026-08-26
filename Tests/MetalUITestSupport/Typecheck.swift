import Foundation

// Machinery for *negative* type-system guards: properties about what must NOT
// compile. No ordinary test can observe one, because a regression makes the
// offending code compile and every existing test stays green. So these helpers
// write a fixture, shell out to `swiftc -typecheck` against the built modules,
// and report whether it was accepted.
//
// **This lives in its own target because there must be exactly one copy.**
// `modulesDirectory` below carries a fix (009768a) whose failure mode is
// *disguising itself as an unrelated regression*: it made `swift test` green on
// a branch and red on the identical merged tree, presenting as a unit-safety
// regression, because SourceKit had indexed in between. A second copy of this
// function keeps that bug, and the next person to hit it debugs the wrong
// subsystem. Ruling EP-1.
//
// `MetalUITestSupport` is a test-support target: it is in no product and is not
// one of spec §3.1's seven layering targets. It is the package's eighth
// `.target`. See the note in `Package.swift` — §3.1's seven and the package's
// seven non-test targets are two different lists that happen to have the same
// length today.

/// Locates `.build/<triple>/debug/Modules` without hardcoding the triple, which
/// differs across host architectures and SDKs.
///
/// - Parameter module: the module the caller's fixture will `import`. Only a
///   directory that actually holds it is accepted, so a partially-populated
///   build product cannot be mistaken for the real one.
public func modulesDirectory(containing module: String) -> URL? {
    // Tests/MetalUITestSupport/Typecheck.swift -> package root is three levels up.
    // The two callers of this helper both sit at Tests/<target>/<file>.swift, the
    // same depth this file does; a caller nested deeper would need its own root.
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildDirectory = packageRoot.appendingPathComponent(".build", isDirectory: true)

    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(
        at: buildDirectory,
        includingPropertiesForKeys: [.isDirectoryKey]
    ) else { return nil }

    // **Skip `index-build`.** SourceKit populates `.build/index-build/` for IDE
    // indexing, using whatever toolchain the editor runs — which need not be the
    // one running the tests. A module there compiled by Swift 6.4 makes this
    // guard's `swiftc` invocation fail with "module compiled with Swift 6.4
    // cannot be imported by the Swift 6.3.3 compiler", and the failure reads as
    // a regression in whatever the fixture was probing rather than the
    // environment artefact it is.
    // Observed for real: `swift test` was green on a branch and red on the
    // identical merged tree, purely because an editor had indexed in between.
    let buildProducts = entries.filter { $0.lastPathComponent != "index-build" }

    // Prefer a triple-qualified layout, then fall back to the unqualified one.
    let candidates = buildProducts.map {
        $0.appendingPathComponent("debug/Modules", isDirectory: true)
    } + [buildDirectory.appendingPathComponent("debug/Modules", isDirectory: true)]

    return candidates.first { candidate in
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }
        // Only accept a directory that actually holds the module we import.
        let contents = (try? fileManager.contentsOfDirectory(atPath: candidate.path)) ?? []
        return contents.contains { $0.hasPrefix("\(module).") }
    }
}

/// True when the guard can run at all. Used as a runtime skip condition so a
/// differing build layout never produces a false red.
public func canTypecheck(module: String) -> Bool { modulesDirectory(containing: module) != nil }

public struct TypecheckResult: Sendable {
    public var succeeded: Bool

    /// Everything `swiftc` wrote, verbatim. Good for a failure message; **do not
    /// assert against it** — see `messages`.
    public var output: String

    public init(succeeded: Bool, output: String) {
        self.succeeded = succeeded
        self.output = output
    }

    /// The diagnostic *messages* only, with the echoed source lines removed.
    ///
    /// **This distinction is the difference between a guard and a decoration.**
    /// `swiftc` prints the offending source line beneath each diagnostic — in
    /// every diagnostic style, `llvm` included. So a fixture whose body reads
    /// `pass.fill(box, color: .white)` yields `output` containing the substring
    /// "fill" *no matter why it was rejected*, and a test asserting
    /// `output.contains("fill")` — the assertion whose entire job is to prove the
    /// rejection is about `fill` — passes even when `LayoutPass` does not exist
    /// and the real diagnostic is `cannot find type 'LayoutPass' in scope`.
    ///
    /// Measured, not reasoned: with `output`, three of this repo's
    /// phase-separation negatives passed against a `MetalUI` that declared no
    /// pass type at all. Against `messages` they fail, as they must.
    public var messages: String {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> Substring? in
                // A diagnostic line is `file:line:col: error: message`; an echoed
                // source line has no `error: ` / `warning: ` marker.
                for marker in [" error: ", " warning: ", " note: "] {
                    if let range = line.range(of: marker) { return line[range.upperBound...] }
                }
                return nil
            }
            .joined(separator: "\n")
    }
}

/// Typechecks `body` as the contents of a function in a file that imports `module`.
///
/// Declarations are legal in `body`: Swift permits nested functions and types
/// inside a function body, so a fixture may declare `func probe(pass: inout
/// PaintPass)` and have it typechecked in full.
public func typecheck(_ body: String, importing module: String) throws -> TypecheckResult {
    guard let modules = modulesDirectory(containing: module) else {
        throw TypecheckUnavailable(module: module)
    }

    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory
        .appendingPathComponent("metalui-typecheck-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }

    let source = scratch.appendingPathComponent("fixture.swift")
    try """
    import \(module)

    func fixture() {
    \(body)
    }
    """.write(to: source, atomically: true, encoding: .utf8)

    // `-diagnostic-style=llvm` gives one `file:line:col: error: message` line per
    // diagnostic, which is what `TypecheckResult.messages` parses. Both styles
    // echo the offending source line underneath; see `messages` for why that
    // matters and why no caller should match against `output`.
    var arguments = ["swiftc", "-typecheck", "-diagnostic-style=llvm", "-I", modules.path]
    arguments += cModuleSearchPaths(besides: modules).flatMap { ["-I", $0.path] }
    arguments.append(source.path)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    return TypecheckResult(
        succeeded: process.terminationStatus == 0,
        output: String(data: data, encoding: .utf8) ?? ""
    )
}

/// Search paths for the package's **C** targets' module maps.
///
/// SwiftPM writes a Swift target's `.swiftmodule` into `debug/Modules`, but a C
/// target's generated `module.modulemap` goes to `debug/<Name>.build/` instead —
/// so `-I <Modules>` alone is not enough to import a Swift module that re-exports
/// one. Without this, importing `MetalUI` fails with
/// `error: missing required module 'MetalUIShaderTypes'`, which mentions neither
/// the fixture nor the symbol under test and would read as a false negative in
/// every guard here.
///
/// Only a `.build` directory holding a `module.modulemap` **at its top level** is
/// accepted. Swift targets also get a `<Name>.build/include/module.modulemap` for
/// their generated ObjC compatibility header; adding those would put a second
/// declaration of an already-imported module on the search path.
private func cModuleSearchPaths(besides modules: URL) -> [URL] {
    let debugDirectory = modules.deletingLastPathComponent()
    let entries = (try? FileManager.default.contentsOfDirectory(
        at: debugDirectory, includingPropertiesForKeys: nil)) ?? []
    return entries.filter { entry in
        entry.pathExtension == "build"
            && FileManager.default.fileExists(
                atPath: entry.appendingPathComponent("module.modulemap").path)
    }
}

/// Thrown when the modules directory vanished between the `.enabled(if:)` check
/// and the test body.
public struct TypecheckUnavailable: Error, CustomStringConvertible {
    public let module: String
    public var description: String {
        "built module directory holding \(module) disappeared mid-test"
    }
}
