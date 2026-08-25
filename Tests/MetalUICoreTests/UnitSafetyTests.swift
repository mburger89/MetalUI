import Foundation
import Testing

// The "typed units never implicitly convert" invariant is a *negative* property:
// it is about what must NOT compile. No ordinary test can observe it, because a
// regression (adding `Numeric`, or a cross-unit operator overload) would make the
// offending code compile and every existing test would stay green. So this guard
// shells out to `swiftc -typecheck` against the built module and asserts that each
// illegal expression is rejected — and, to keep the guard honest, that the legal
// ones are still accepted.

/// Locates `.build/<triple>/debug/Modules` without hardcoding the triple, which
/// differs across host architectures and SDKs.
private func modulesDirectory() -> URL? {
    // Tests/MetalUICoreTests/UnitSafetyTests.swift -> package root is three levels up.
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

    // Prefer a triple-qualified layout, then fall back to the unqualified one.
    let candidates = entries.map {
        $0.appendingPathComponent("debug/Modules", isDirectory: true)
    } + [buildDirectory.appendingPathComponent("debug/Modules", isDirectory: true)]

    return candidates.first { candidate in
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else { return false }
        // Only accept a directory that actually holds the module we import.
        let contents = (try? fileManager.contentsOfDirectory(atPath: candidate.path)) ?? []
        return contents.contains { $0.hasPrefix("MetalUICore.") }
    }
}

/// True when the guard can run at all. Used as a runtime skip condition so a
/// differing build layout never produces a false red.
private func canTypecheck() -> Bool { modulesDirectory() != nil }

private struct TypecheckResult {
    var succeeded: Bool
    var output: String
}

/// Typechecks `body` as the contents of a function in a file that imports MetalUICore.
private func typecheck(_ body: String) throws -> TypecheckResult {
    let modules = try #require(modulesDirectory(), "modules directory disappeared mid-test")

    let fileManager = FileManager.default
    let scratch = fileManager.temporaryDirectory
        .appendingPathComponent("metalui-unit-safety-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: scratch) }

    let source = scratch.appendingPathComponent("fixture.swift")
    try """
    import MetalUICore

    func fixture() {
    \(body)
    }
    """.write(to: source, atomically: true, encoding: .utf8)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck", "-I", modules.path, source.path]
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

@Test(
    .enabled(if: canTypecheck(),
             "built module directory .build/<triple>/debug/Modules not found — unit-mixing guard skipped")
)
func illegalUnitExpressionsDoNotCompile() throws {
    let illegal: [(description: String, code: String)] = [
        ("adding Pixels to ScaledPixels", "let v = Pixels(1) + ScaledPixels(1); _ = v"),
        ("multiplying Pixels by Pixels", "let v = Pixels(1) * Pixels(2); _ = v"),
        ("assigning ScaledPixels to Pixels", "let v: Pixels = ScaledPixels(1); _ = v"),
        ("comparing Pixels with ScaledPixels", "let v = Pixels(1) < ScaledPixels(2); _ = v"),
    ]

    for (description, code) in illegal {
        let result = try typecheck(code)
        #expect(
            !result.succeeded,
            "\(description) compiled, but must not — units are mixing implicitly.\n\(result.output)"
        )
    }
}

@Test(
    .enabled(if: canTypecheck(),
             "built module directory .build/<triple>/debug/Modules not found — unit-mixing guard skipped")
)
func legalUnitExpressionsStillCompile() throws {
    let legal: [(description: String, code: String)] = [
        ("adding Pixels to Pixels", "let v = Pixels(1) + Pixels(2); _ = v"),
        ("integer literal as Pixels", "let v: Pixels = 5; _ = v"),
        ("scaling Pixels by a Float", "let v = Pixels(1) * 2.0; _ = v"),
    ]

    for (description, code) in legal {
        let result = try typecheck(code)
        #expect(
            result.succeeded,
            "\(description) failed to compile, but must succeed — the guard itself is broken.\n\(result.output)"
        )
    }
}
