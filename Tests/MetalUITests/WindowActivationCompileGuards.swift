import Testing
import MetalUITestSupport

// Compile-time guard for the activation API and `Color(hex:)` (rulings `WA-A`, `WA-B`). A plain `import
// MetalUI` through `typecheckFile` (`SA-P`): what an external module can spell. Skips silently when
// `.build/<triple>/debug/Modules` is absent (CLAUDE.md, "Guards").

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **WA-G1** (`WA-A`, `WA-B`). `Window.makeKeyAndOrderFront()`, `App.activate()` and `Color(hex:)` are
/// spellable with a plain import. Mutation: drop `public` from `Color.init(hex:)` (this reddens, naming
/// `hex`), or from either method.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theActivationApiAndColorHexAreSpellableFromOutside() throws {
    let result = try typecheckFile("""
        @MainActor func activate(_ window: Window, _ app: App) {
            window.makeKeyAndOrderFront()
            app.activate()
        }
        func tint() -> Color { Color(hex: 0x1E90FF) }
        """, importing: "MetalUI")
    print("WA-G1 spellable from outside: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}
