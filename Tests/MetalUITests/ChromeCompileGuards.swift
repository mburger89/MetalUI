import Testing
import MetalUITestSupport

// SDL custom chrome, lane 1, guards `CW-1` and `CW-2` (rulings `CW-F`, `CW-K`; spec
// `docs/superpowers/specs/2026-10-13-sdl-chrome-design.md` "Tests"). The four chrome requirements have **no
// default** (`HT-X` 1's rule): a conformer that forgets one fails to compile rather than silently drawing no
// controls. The verbs and the property are reachable from a plain import.
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN import, as an external module writes
// it (`SA-P`). **A guard skips silently when `.build/<triple>/debug/Modules` is absent** (CLAUDE.md,
// "Guards"); grep the log for `CW-F window members required` and `CW-K chrome verbs` to know they ran.

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"
private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **CW-1** (`CW-F`). Each of the four new `PlatformWindow` requirements has no default: a conformer with all
/// four — the migration note's spelling, verbatim — compiles (the positive control), and each of four
/// conformers missing exactly one fails, naming it.
///
/// Mutation: a protocol-extension default `func performWindowAction(_: PlatformWindowAction) -> Bool { false }`
/// (that arm compiles).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformWindowWithoutEachChromeRequirementDoesNotCompile() throws {
    let base = windowMembers.map(\.spelling)
    let all = try typecheckFile(windowConformer(base + chromeMembers.map(\.spelling)), importing: "MetalUIPlatform")
    print("CW-F window members required: all succeeded=\(all.succeeded) messages=[\(all.messages)]")
    try #require(all.succeeded, "the control must compile, or this guard cannot fail:\n\(all.output)")
    for (index, member) in chromeMembers.enumerated() {
        var rest = chromeMembers.map(\.spelling)
        rest.remove(at: index)
        let without = try typecheckFile(windowConformer(base + rest), importing: "MetalUIPlatform")
        print("CW-F window members required: without \(member.name) succeeded=\(without.succeeded)")
        #expect(!without.succeeded, "a conformer without \(member.name) must not compile:\n\(without.output)")
        #expect(without.messages.contains(member.name),
                "the refusal must name \(member.name):\n\(without.output)")
    }
}

/// **CW-2** (`CW-K`). The chrome verbs and `PlatformWindowAction` are spellable from a plain import of
/// `MetalUI`/`MetalUIPlatform`: `Window.drawsWindowControls` (read and write), `minimize()`, `toggleZoom()`,
/// `isZoomed`, and `ChromeHitSnapshot.hit(at:)`.
///
/// Mutation: make `toggleZoom()` `internal` (the fixture fails to compile).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
@MainActor func theChromeVerbsAreReachableFromAPlainImport() throws {
    let verbs = try typecheckFile("""
        import MetalUIPlatform
        import MetalUICore

        @MainActor func drive(_ window: Window) -> Bool {
            window.drawsWindowControls = false
            window.minimize()
            window.toggleZoom()
            return window.isZoomed && window.drawsWindowControls
        }

        func hit(_ snapshot: ChromeHitSnapshot) -> ChromeHit {
            let action: PlatformWindowAction = .toggleZoom
            _ = action == .minimize
            return snapshot.hit(at: Point(x: Pixels(1), y: Pixels(1)))
        }
        """, importing: "MetalUI")
    print("CW-K chrome verbs: succeeded=\(verbs.succeeded) messages=[\(verbs.messages)]")
    #expect(verbs.succeeded, "the verbs must be public:\n\(verbs.output)")
}
