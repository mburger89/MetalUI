import Testing
import MetalUITestSupport

// Menus, popovers and tooltips, lane 2, guards G2.1–G2.2 (rulings `MN-I`,
// `MN-X`, `MN-AD`; spec §6.2). Whole-file Swift 6 (`typecheckFile`, ruling
// SA-P) against a PLAIN import — a `@testable` test cannot prove what an
// external module can write (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `MN-I` to know these ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"
private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// **G2.1** (`MN-I` item 1, `MN-X` items 2–3, `MN-AD`). The commands
/// spellings compile under `import MetalUI`: `app.commands { }` with a
/// trailing closure and spelled `commands(content:)`, `CommandMenu`, the three
/// `CommandGroup` initialisers against every placement, `if`/`else` in the
/// builder, and `Menu("…") { … }` as a view (the pull-down button). An outside
/// type conforming to `Commands` does **not** (its requirement is SPI).
///
/// Mutation **MG2.1**: the `Commands` requirement made plain `public` (the
/// negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func theCommandsSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        @MainActor func install(_ app: App, flag: Binding<Bool>, wide: Bool) {
            app.commands {
                CommandMenu("Tools") {
                    Button("Run") {}.keyboardShortcut("r")
                    Toggle("Pinned", isOn: flag)
                    Divider()
                    Menu("Sub") { Button("A") {} }
                    Button("Off") {}.disabled(true)
                }
                CommandGroup(after: .newItem) { Button("New Note") {}.keyboardShortcut("n") }
                CommandGroup(before: .appTermination) { Button("Prefs") {} }
                CommandGroup(replacing: .help) { }
                if wide { CommandMenu("Wide") { Button("W") {} } } else { CommandMenu("Narrow") { Text("N") } }
            }
            app.commands(content: {
                CommandGroup(replacing: .pasteboard) { Button("Paste") {} }
            })
            let placements: [CommandGroupPlacement] = [.appInfo, .appVisibility, .appTermination, .newItem,
                                                       .undoRedo, .pasteboard, .windowSize,
                                                       .windowArrangement, .help]
            _ = Set(placements)
        }

        @MainActor func pullDown() -> some ElementGroup {
            Row {
                Menu("Actions") { Button("A") {}; Divider(); Button("B") {} }
                Menu { Button("C") {} } label: { Text("Custom") }
            }
        }
        """, importing: "MetalUI")
    let fabricated = try typecheckFile("""
        struct Mine: Commands {
            func _commandEntries() -> _CommandEntries { CommandMenu("X") { Divider() }._commandEntries() }
        }
        """, importing: "MetalUI")
    print("""
        MN-I commands spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        fabricated succeeded=\(fabricated.succeeded) messages=[\(fabricated.messages)]
        """)
    try #require(spellings.succeeded && !fabricated.succeeded,
                 """
                 the spellings must compile and an outside conformance must not, or \
                 this guard cannot fail:
                 spellings:
                 \(spellings.output)
                 fabricated:
                 \(fabricated.output)
                 """)
}

/// A `Platform` conformer with every requirement except `setMenuBar`, which
/// the caller splices in (or not).
private func conformer(member: String) -> String {
    """
    import MetalUICore
    import MetalUIScene

    @MainActor
    final class Conformer: Platform {
        func openWindow(title: String, size: Size<Pixels>) throws -> any PlatformWindow {
            throw PlatformError.windowCreationFailed
        }
        func run() {}
        func setApplicationIcon(_: [ImageTexture]) {}
    \(member)
    }
    """
}

/// **G2.2** (`MN-I` item 3). `Platform.setMenuBar(_:)` has **no default
/// implementation** (`AB-R`/`EV-AB`/`DN-C`'s reason): a conformer that forgets
/// it fails to compile, naming it. **Positive control**: the same conformer
/// with the migration spelling, verbatim, compiles.
///
/// Mutation **MG2.2**: a protocol-extension default (the negative compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWithoutSetMenuBarDoesNotCompile() throws {
    let without = try typecheckFile(conformer(member: ""), importing: "MetalUIPlatform")
    let with = try typecheckFile(conformer(member: """
            func setMenuBar(_: PlatformMenuBar) -> Bool { false }
        """), importing: "MetalUIPlatform")
    print("""
        MN-I member required: without succeeded=\(without.succeeded) \
        messages=[\(without.messages)]; with succeeded=\(with.succeeded) \
        messages=[\(with.messages)]
        """)
    try #require(with.succeeded && !without.succeeded,
                 """
                 the control must compile and the negative must not, or this guard \
                 cannot fail:
                 with:
                 \(with.output)
                 without:
                 \(without.output)
                 """)
    #expect(without.messages.contains("setMenuBar"),
            "the negative must be refused FOR setMenuBar:\n\(without.output)")
}
