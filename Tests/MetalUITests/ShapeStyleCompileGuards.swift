import Testing
import MetalUITestSupport

// Round 3 item R3-9 (`SS-A`…): whole-file Swift 6 against a PLAIN `import MetalUI` (`typecheckFile`, ruling
// SA-P) — what an external module may write against `ShapeStyle`. **A guard skips silently when
// `.build/<triple>/debug/Modules` is absent** (CLAUDE.md, "Guards"); grep the log for `SHAPE STYLE GUARD`.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G-SS1 — a third-party module uses every style generically and conforms by composition.** `func f(_ s: some
/// ShapeStyle)` feeds `fill`, `stroke`, `strokeBorder`, `foregroundStyle`, `background`, `border` and `tint`;
/// `AnyShapeStyle` erases a colour, gradient, material and the tint style; a custom `ShapeStyle` returns an existing
/// style from `resolve(in:)`. **Negative arms**, each its own fixture: a `Resolved` that is no style, and a
/// `ResolvedShapeStyle` built outside the module (it has no public initialiser, so a third party cannot forge a
/// primitive).
///
/// Mutation that must redden it: `ShapeStyle` made `internal`, or `Color` not conforming, or `resolve(in:)` made
/// `package`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func aThirdPartyModuleCanUseAndComposeShapeStyles() throws {
    let positive = try typecheckFile("""
        public struct Brand: ShapeStyle {
            public init() {}
            public func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
                environment.colorScheme == .dark ? Color.white : Color.black
            }
        }
        public struct Wrapped: ShapeStyle {
            public init() {}
            public func resolve(in environment: EnvironmentValues) -> some ShapeStyle { Brand() }
        }
        @MainActor public func paint(_ style: some ShapeStyle) -> ShapeView<Rectangle> {
            Rectangle().fill(style)
        }
        @MainActor public func everySite(_ style: some ShapeStyle) {
            _ = Rectangle().fill(style).stroke(style, lineWidth: Pixels(2)).strokeBorder(style, lineWidth: Pixels(1))
            _ = Circle().stroke(style, style: StrokeStyle(lineWidth: Pixels(2)))
            _ = Column { Text("a") }.foregroundStyle(style).tint(style)
            _ = Text("a").foregroundStyle(style)
            _ = Column { Text("a") }.background(style, in: Rectangle())
            _ = Box(decoration: Decoration(), content: EmptyGroup()).background(style).border(style, width: Pixels(1))
        }
        @MainActor public func erased() -> [AnyShapeStyle] {
            let gradient = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
            _ = Rectangle().fill(AnyShapeStyle(gradient))
            _ = Rectangle().fill(.tint)
            _ = Column { Text("a") }.tint(Color.red).tint(nil as Color?)
            return [AnyShapeStyle(Color.red), AnyShapeStyle(gradient), AnyShapeStyle(Material.thinMaterial),
                    AnyShapeStyle(TintShapeStyle()), AnyShapeStyle(Brand()), AnyShapeStyle(Wrapped())]
        }
        public func resolved(_ environment: EnvironmentValues) {
            let _: Color.Resolved = Color.red.resolve(in: environment)
            let _: ResolvedShapeStyle = LinearGradient(colors: [.red], startPoint: .top, endPoint: .bottom)
                .resolve(in: environment)
            let _: ResolvedShapeStyle = AnyShapeStyle(Brand()).resolve(in: environment)
        }
        """, importing: "MetalUI")
    print("SHAPE STYLE GUARD G-SS1 positive: succeeded=\(positive.succeeded)\n\(positive.messages)")
    let badResolved = try typecheckFile("""
        public struct Bad: ShapeStyle {
            public init() {}
            public func resolve(in environment: EnvironmentValues) -> Int { 0 }
        }
        """, importing: "MetalUI")
    let forged = try typecheckFile("""
        public func forged() { _ = ResolvedShapeStyle(.color(Color.red)) }
        """, importing: "MetalUI")
    let notAStyle = try typecheckFile("""
        @MainActor public func notAStyle() { _ = Rectangle().fill(42) }
        """, importing: "MetalUI")
    print("SHAPE STYLE GUARD G-SS1 negatives: badResolved=\(badResolved.succeeded) forged=\(forged.succeeded) "
          + "notAStyle=\(notAStyle.succeeded)")
    try #require(positive.succeeded != badResolved.succeeded && positive.succeeded != forged.succeeded
                    && positive.succeeded != notAStyle.succeeded,
                 """
                 the arms must disagree, or the guard measures nothing:
                 \(positive.output)
                 \(badResolved.output)
                 \(forged.output)
                 \(notAStyle.output)
                 """)
    #expect(positive.succeeded, "every style spelling must compile from a plain import:\n\(positive.output)")
    #expect(!badResolved.succeeded, "a Resolved that is no ShapeStyle must not compile")
    #expect(!forged.succeeded, "a third party cannot build a ResolvedShapeStyle")
    #expect(!notAStyle.succeeded, "an Int is no ShapeStyle")
}
