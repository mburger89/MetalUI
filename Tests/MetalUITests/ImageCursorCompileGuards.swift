import Testing
import MetalUITestSupport

// Compile-time guards for the image cursor's seam (rulings `IC-A`, `CI-AC`; spec
// `docs/superpowers/specs/2026-10-14-cursors-headless-design.md` §5, guards 9 and 10).
//
// **Every fixture uses `typecheckFile`** — whole-file, Swift 6, a PLAIN
// `import MetalUIPlatform`, as an external module writes it (`SA-P`). A guard skips silently when
// `.build/<triple>/debug/Modules` is absent (CLAUDE.md, "Guards").

private let platformSkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUIPlatform not found — guard skipped"

/// The twelve `PlatformPointerStyle` cases that existed before the image cursor, as one `case` list.
private let oldCases = """
    .arrow, .iBeam, .verticalIBeam, .crosshair, .openHand, .closedHand, .pointingHand,
             .columnResize, .rowResize, .zoomIn, .zoomOut, .frameResize
    """

/// A `switch` over `PlatformPointerStyle` naming the old cases, plus `extra`.
private func exhaustiveSwitch(extra: String) -> String {
    """
    func name(_ style: PlatformPointerStyle) -> String {
        switch style {
        case \(oldCases): return "old"
        \(extra)
        }
    }
    """
}

/// **9** (`IC-A`, `CI-AC`). `PlatformPointerStyle` has an `.image` case, so an exhaustive `switch`
/// outside the package that names only the twelve old cases **does not compile** (the migration
/// note's premise); the same `switch` with `default:` compiles, and so does one that adds
/// `.image`.
///
/// Mutation: delete the `.image` case (the negative compiles and the third arm fails).
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func anOutsideSwitchOverPlatformPointerStyleOwesTheImageCase() throws {
    let old = try typecheckFile(exhaustiveSwitch(extra: ""), importing: "MetalUIPlatform")
    let withDefault = try typecheckFile(exhaustiveSwitch(extra: "default: return \"other\""),
                                        importing: "MetalUIPlatform")
    let withImage = try typecheckFile(exhaustiveSwitch(extra: "case .image: return \"image\""),
                                      importing: "MetalUIPlatform")
    print("""
        IC-A image case: old succeeded=\(old.succeeded) messages=[\(old.messages)]; \
        default succeeded=\(withDefault.succeeded); image succeeded=\(withImage.succeeded)
        """)
    try #require(withDefault.succeeded && withImage.succeeded,
                 "the controls must compile or this guard cannot fail:\n\(withDefault.output)\n\(withImage.output)")
    #expect(!old.succeeded, "a switch that names only the old cases must not compile:\n\(old.output)")
    #expect(old.messages.contains("PlatformPointerStyle") || old.messages.contains("switch"),
            "refused FOR the missing case:\n\(old.output)")
}

/// **10** (`IC-A` 1). A `PlatformCursorImage` can be built from a plain import: its initialiser is
/// public, because the `Backends/SDL` package and an outside conformer's tests cannot reach
/// `package` API. **Positive control**: the read-backs the SDL and AppKit sides use are spellable.
///
/// Mutation: make `PlatformCursorImage.init` `package`.
@Test(.enabled(if: canTypecheck(module: "MetalUIPlatform"), platformSkipReason))
func aPlatformCursorImageCanBeBuiltFromAPlainImport() throws {
    let result = try typecheckFile("""
        import MetalUIScene
        func build() -> (Int, Float, Float) {
            let texture = ImageTexture(width: 4, height: 2, premultipliedRGBA: Array(repeating: 0, count: 32))
            let cursor = PlatformCursorImage(texture: texture, scale: 2, hotSpot: (x: 1, y: 0.5))
            let style = PlatformPointerStyle.image(cursor)
            guard case .image(let again) = style else { return (0, 0, 0) }
            return (again.pixelWidth, again.pointWidth, again.hotSpotX)
        }
        """, importing: "MetalUIPlatform")
    print("IC-A public init: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "\(result.output)")
}
