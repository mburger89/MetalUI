import Testing
import MetalUITestSupport

// Compile-time guards for the accessibility display settings (rulings `AD-B`, `AD-D`, `AD-J`;
// R3-10 item 7). SwiftUI's side is `docs/probes/swiftui-accessibility-display.swift` arm A:
// six keys are get-only (a `KeyPath`, not Writable), `legibilityWeight` is writable.
//
// **Every fixture uses `typecheckFile`** -- whole-file, Swift 6, a PLAIN import, as an external
// module writes it (`SA-P`). **A guard skips silently when `.build/<triple>/debug/Modules` is
// absent** (CLAUDE.md, "Guards").

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let coreSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUICore not found — guard skipped"

/// **10** (`AD-D`). The six display keys read outside the module and cannot be written by a
/// scope, as SwiftUI's key paths cannot (arm A). Mutation: `colorSchemeContrast`'s setter made
/// `public`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theAccessibilityDisplayKeysAreReadOnlyOutsideMetalUI() throws {
    let keys: [(name: String, value: String)] = [
        ("colorSchemeContrast", ".increased"), ("accessibilityDifferentiateWithoutColor", "true"),
        ("accessibilityInvertColors", "true"), ("accessibilityShowBorders", "true"),
        ("accessibilityDimFlashingLights", "true"), ("accessibilityPlayAnimatedImages", "true"),
    ]
    let read = try typecheckFile("""
        @MainActor func probe(_ values: EnvironmentValues) {
            _ = values.colorSchemeContrast
            _ = values.accessibilityDifferentiateWithoutColor
            _ = values.accessibilityInvertColors
            _ = values.accessibilityShowBorders
            _ = values.accessibilityShowButtonShapes
            _ = values.accessibilityDimFlashingLights
            _ = values.accessibilityPlayAnimatedImages
            _ = values.legibilityWeight
        }
        """, importing: "MetalUI")
    try #require(read.succeeded, "the reads must compile, or this guard cannot fail:\n\(read.output)")
    var report = "AD-D display keys: read succeeded=\(read.succeeded)"
    for (name, value) in keys {
        let write = try typecheckFile("""
            @MainActor func probe() -> some ElementGroup {
                Box().environment(\\.\(name), \(value))
            }
            """, importing: "MetalUI")
        report += "; \(name) write succeeded=\(write.succeeded)"
        try #require(!write.succeeded, "the scope write of \(name) must not compile:\n\(write.output)")
        #expect(write.messages.contains("WritableKeyPath") || write.messages.contains("get-only")
                    || write.messages.contains(name),
                "the write of \(name) must be refused FOR the key path's writability:\n\(write.output)")
    }
    print(report)
}

/// **11** (`AD-J`). `legibilityWeight` is the one writable key, as SwiftUI's is (arm A): a scope
/// outside the module writes it. Mutation: `public internal(set) var legibilityWeight`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func legibilityWeightIsWritableByAScopeOutsideMetalUI() throws {
    let write = try typecheckFile("""
        @MainActor func probe() -> some ElementGroup {
            Box().environment(\\.legibilityWeight, .bold)
        }
        """, importing: "MetalUI")
    print("AD-J legibilityWeight: write succeeded=\(write.succeeded) messages=[\(write.messages)]")
    #expect(write.succeeded, "a scope writes legibilityWeight:\n\(write.output)")
}

/// **12** (`AD-B`). `AccessibilityDisplaySettings` is constructible, every field settable, by a
/// module that imports only `MetalUICore` (a third-party `PlatformWindow` conformer builds one).
/// Mutation: `public` dropped from the initialiser.
@Test(.enabled(if: canTypecheck(module: "MetalUICore"), coreSkipReason))
func accessibilityDisplaySettingsIsConstructibleOutsideItsModule() throws {
    let result = try typecheckFile("""
        func make() -> AccessibilityDisplaySettings {
            var settings = AccessibilityDisplaySettings(colorSchemeContrast: .increased, playAnimatedImages: true)
            settings.differentiateWithoutColor = true
            settings.invertColors = true
            settings.showBorders = true
            settings.dimFlashingLights = true
            return settings
        }
        let weights: [LegibilityWeight] = [.regular, .bold]
        """, importing: "MetalUICore")
    print("AD-B settings constructible: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}
