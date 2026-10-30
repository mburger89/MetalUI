import Foundation
import Testing
@testable import MetalUIShaderCompile

// The environment the build-tool plugin forwards and the tool's shadercross child gets (item XP-G35, rulings
// BT-V, BT-W). Pure and portable: the `windows:` parameter stands in for the host.

private let checkout = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// **23.** The Windows list names every variable Winsock, temporary files and DLL lookup need; the other list has none of them.
/// Mutations: drop `SystemRoot` from `ForwardedEnvironment.windows` (this and the selection test redden); drop `TEMP`.
@Test func theForwardedKeysAreThoseTheToolAndShadercrossNeed() {
    let windows = ForwardedEnvironment.keys(windows: true)
    for key in ["METALUI_SHADERCROSS", "METALUI_SHADERCROSS_LIB", "PATH", "SystemRoot", "WINDIR", "TEMP", "TMP",
                "USERPROFILE", "LOCALAPPDATA", "ProgramData", "ComSpec", "PATHEXT"] {
        #expect(windows.contains(key), "windows: \(key)")
    }
    let other = ForwardedEnvironment.keys(windows: false)
    for key in ["METALUI_SHADERCROSS", "METALUI_SHADERCROSS_LIB", "PATH", "HOME", "TMPDIR", "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH"] {
        #expect(other.contains(key), "other: \(key)")
    }
    #expect(!other.contains("SystemRoot") && !windows.contains("HOME"))
}

/// **24.** Selection matches case-insensitively, forwards under the original spelling, skips absent and unlisted keys.
/// Mutation: drop `SystemRoot` from the Windows list; compare case-sensitively (`Path` is lost).
@Test func theSelectionKeepsTheOriginalSpellingAndOnlyPresentListedKeys() {
    let environment = ["Path": "C:\\bin", "SYSTEMROOT": "C:\\Windows", "temp": "C:\\Temp", "METALUI_SHADERCROSS": "C:\\sc.exe",
                       "SECRET_TOKEN": "x", "HOME": "/h"]
    let windows = ForwardedEnvironment.select(from: environment, windows: true)
    #expect(windows == ["Path": "C:\\bin", "SYSTEMROOT": "C:\\Windows", "temp": "C:\\Temp", "METALUI_SHADERCROSS": "C:\\sc.exe"])
    let other = ForwardedEnvironment.select(from: environment, windows: false)
    #expect(other == ["Path": "C:\\bin", "METALUI_SHADERCROSS": "C:\\sc.exe", "HOME": "/h"],
            "PATH still matches case-insensitively; SystemRoot and TEMP are Windows-only")
    #expect(ForwardedEnvironment.select(from: [:], windows: true).isEmpty)
}

/// **25.** On Windows the child gets SystemRoot, WINDIR, TEMP and TMP from the tool's own environment when it lacks them
/// (case-insensitively), and keeps its own values; elsewhere the environment is untouched.
/// Mutation: skip the merge (`merged` returns `environment`).
@Test func aWindowsChildGetsTheSystemVariablesItLacks() {
    let process = ["SystemRoot": "C:\\Windows", "WINDIR": "C:\\Windows", "TEMP": "C:\\T", "TMP": "C:\\T", "Other": "o"]
    let merged = ChildEnvironment.merged(["PATH": "p", "windir": "D:\\Win"], process: process, windows: true)
    #expect(merged["SystemRoot"] == "C:\\Windows")
    #expect(merged["TEMP"] == "C:\\T" && merged["TMP"] == "C:\\T")
    #expect(merged["windir"] == "D:\\Win" && merged["WINDIR"] == nil, "an existing value in any case is kept, not duplicated")
    #expect(merged["Other"] == nil, "only the four system variables are merged")
    #expect(merged["PATH"] == "p")
    #expect(ChildEnvironment.merged(["PATH": "p"], process: process, windows: false) == ["PATH": "p"])
    #expect(ChildEnvironment.merged([:], process: [:], windows: true).isEmpty, "nothing to merge from")
}

/// **26.** The plugin cannot import the tool's library, so its forwarding is the library's text: the marked region is
/// byte-identical in both files, the build command passes the selection as `environment:`, and the tool's
/// `processRunner` merges the child environment.
/// Mutations: edit the region in `Plugin.swift` only; drop `environment: forwarded`; drop the merge in `processRunner`.
@Test func theBuildPluginForwardsTheSameEnvironmentTheToolListsHere() throws {
    // A Windows checkout has CRLF line ends; the pins below spell `\n`.
    func text(_ path: String) throws -> String {
        try String(contentsOf: checkout.appendingPathComponent(path), encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
    }
    func region(_ text: String, _ path: String) throws -> String {
        let begin = try #require(text.range(of: "// BEGIN environment-forwarding"), "\(path) has no region")
        let end = try #require(text.range(of: "// END environment-forwarding"), "\(path) has no region end")
        return String(text[begin.lowerBound..<end.upperBound])
    }
    let pluginPath = "Plugins/CompileShadersOnBuild/Plugin.swift"
    let libraryPath = "Backends/SDL/Sources/MetalUIShaderCompile/ChildEnvironment.swift"
    let plugin = try text(pluginPath)
    let library = try region(try text(libraryPath), libraryPath)
    #expect(try region(plugin, pluginPath) == library)
    #expect(library.contains("enum ForwardedEnvironment"))
    #expect(plugin.contains("ForwardedEnvironment.select(from: environment, windows: isWindows)"))
    #expect(plugin.contains("environment: forwarded,"))
    let runner = try text("Backends/SDL/Sources/MetalUIShaderCompile/ShaderCompiler.swift")
    #expect(runner.contains("process.environment = ChildEnvironment.merged(environment, process: ProcessInfo.processInfo.environment, windows: runsOnWindows)"))
    let main = try text("Backends/SDL/Sources/MetalUICompileShaders/main.swift")
    let guardAt = try #require(main.range(of: "setWindowsDirectoryVariablesIfAbsent()\n#endif"))
    let usesFoundationAt = try #require(main.range(of: "let arguments = "))
    #expect(guardAt.lowerBound < usesFoundationAt.lowerBound, "SystemRoot is set before any Process use (BT-W)")
}
