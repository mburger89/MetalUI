import Testing
import MetalUITestSupport

// Paths, shadows and transforms, lane 3, guards G3.1–G3.3 (rulings `GX-C`,
// `GX-D`, `GX-E`, `GX-J`, `GX-Q`; spec
// `docs/superpowers/specs/2026-10-02-paths-shadows-transforms-design.md` §8).
// Whole-file Swift 6 (`typecheckFile`, ruling SA-P) against a PLAIN import —
// a `@testable` test cannot prove what an external module can write
// (practices shape 16).
//
// **A guard skips silently when `.build/<triple>/debug/Modules` is absent**
// (CLAUDE.md, "Guards"); grep the log for `GX-C spellings`, `GX-D path(in:)`
// and `GX-Q theme` to know they ran.

private let metalUISkipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **G3.1** (`GX-C`, `GX-E`, `GX-J`). The path, style and shadow spellings
/// compile under a plain `import MetalUI`: every `Path` initialiser and
/// mutator, `FillStyle`, `StrokeStyle` with each `LineCap`/`LineJoin`, the
/// styled `fill`/`stroke`/`strokeBorder` on a shape and on a `ShapeView`,
/// `.shadow` on both vocabularies, `ColorToken.shadow`, `ShapeGeometry.path`,
/// and an exhaustive `switch` over `LayoutModifier` naming `.shadow`.
/// **Negative**: `trimmedPath(from:to:)` is not offered (spec §9).
///
/// Mutation once red (**MG3.1**): `StrokeStyle.init` made `internal`.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func thePathAndShadowSpellingsCompileFromAPlainImport() throws {
    let spellings = try typecheckFile("""
        import MetalUICore
        import MetalUILayout

        let r = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(40), height: Pixels(30)))

        func build() -> Path {
            var p = Path()
            p.move(to: Point(x: Pixels(0), y: Pixels(0)))
            p.addLine(to: Point(x: Pixels(10), y: Pixels(0)))
            p.addLines([Point(x: Pixels(1), y: Pixels(1)), Point(x: Pixels(2), y: Pixels(3))])
            p.addQuadCurve(to: Point(x: Pixels(20), y: Pixels(10)), control: Point(x: Pixels(15), y: Pixels(0)))
            p.addCurve(to: Point(x: Pixels(30), y: Pixels(30)), control1: Point(x: Pixels(25), y: Pixels(10)),
                       control2: Point(x: Pixels(30), y: Pixels(20)))
            p.addArc(center: Point(x: Pixels(20), y: Pixels(20)), radius: Pixels(10), startAngle: .degrees(0),
                     endAngle: .degrees(90), clockwise: false)
            p.addArc(tangent1End: Point(x: Pixels(5), y: Pixels(5)), tangent2End: Point(x: Pixels(9), y: Pixels(1)),
                     radius: Pixels(2))
            p.addRect(r)
            p.addRects([r, r])
            p.addRoundedRect(in: r, cornerSize: Size(width: Pixels(4), height: Pixels(4)), style: .circular)
            p.addEllipse(in: r)
            p.addPath(Path(r))
            p.closeSubpath()
            _ = p.isEmpty
            _ = p.currentPoint
            _ = p.boundingRect
            _ = p.contains(Point(x: Pixels(1), y: Pixels(1)), eoFill: true)
            return p.offsetBy(dx: Pixels(1), dy: Pixels(2))
        }

        let shapes: [Path] = [Path(), Path(r), Path(roundedRect: r, cornerRadius: Pixels(4)),
                              Path(roundedRect: r, cornerSize: Size(width: Pixels(4), height: Pixels(2))),
                              Path(ellipseIn: r), Path { $0.addRect(r) }]

        let caps: [LineCap] = [.butt, .round, .square]
        let joins: [LineJoin] = [.miter, .round, .bevel]
        let style = StrokeStyle(lineWidth: Pixels(3), lineCap: .round, lineJoin: .bevel, miterLimit: 4,
                                dash: [Pixels(4), Pixels(2)], dashPhase: Pixels(1))
        let fill = FillStyle(eoFill: true, antialiased: false)
        let geometry = ShapeGeometry.path(build(), style: fill)

        @MainActor func proposal() -> some ProposalElementGroup {
            VStack {
                build().fill(style: fill)
                Circle().fill(.accent, style: fill)
                Rectangle().stroke(.accent, style: style)
                RoundedRectangle(cornerRadius: Pixels(4)).strokeBorder(.accent, style: style)
                Circle().fill(.surface).stroke(.accent, style: style).strokeBorder(.separator, style: style)
                    .fill(.accent, style: fill)
                build()
                Color(.accent).shadow(radius: Pixels(4))
                Color(.accent).shadow(color: .shadow, radius: Pixels(4), x: Pixels(1), y: Pixels(2))
            }
        }

        @MainActor func legacy() -> some StyledElement {
            Box().frame(width: Pixels(40), height: Pixels(20)).background(.accent)
                .shadow(radius: Pixels(3), y: Pixels(2))
        }

        func describe(_ m: LayoutModifier) -> String {
            switch m {
            case .shadow(let token, let radius, let x, let y): return "\\(token) \\(radius.value) \\(x.value) \\(y.value)"
            default: return ""
            }
        }
        """, importing: "MetalUI")
    let trimmed = try typecheckFile("""
        let p = Path().trimmedPath(from: 0, to: 0.5)
        """, importing: "MetalUI")

    print("""
        GX-C spellings: succeeded=\(spellings.succeeded) messages=[\(spellings.messages)]; \
        trimmedPath succeeded=\(trimmed.succeeded) messages=[\(trimmed.messages)]
        """)

    try #require(spellings.succeeded && !trimmed.succeeded,
                 """
                 the spellings must compile and trimmedPath must not, or this \
                 guard cannot fail:
                 spellings:
                 \(spellings.output)
                 trimmedPath:
                 \(trimmed.output)
                 """)
    #expect(trimmed.messages.contains("trimmedPath"), "refused FOR trimmedPath:\n\(trimmed.output)")
}

/// **G3.2** (`GX-D`). An outside shape can write SwiftUI's `path(in:)` alone
/// (no `geometry(in:)`) and sit in a stack, take `.fill`/`.stroke(style:)`,
/// and — through a generic helper — every `Shape` answers `path(in:)`, a
/// built-in included. **Negative**: `Path.applying(_:)` is not offered
/// (spec §9: `transform:` parameters are deferred).
///
/// Mutation once red (**MG3.2**): `path(in:)` removed from the protocol and
/// its default (SwiftUI's requirement absent).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func anOutsideShapeCanWritePathInAlone() throws {
    let positive = try typecheckFile("""
        import MetalUICore
        import MetalUILayout

        public struct Diamond: Shape {
            public init() {}
            public func path(in rect: Bounds<Pixels>) -> Path {
                Path { p in
                    let w = rect.size.width.value, h = rect.size.height.value
                    p.move(to: Point(x: Pixels(w / 2), y: Pixels(0)))
                    p.addLine(to: Point(x: Pixels(w), y: Pixels(h / 2)))
                    p.addLine(to: Point(x: Pixels(w / 2), y: Pixels(h)))
                    p.addLine(to: Point(x: Pixels(0), y: Pixels(h / 2)))
                    p.closeSubpath()
                }
            }
        }

        @MainActor func outline<S: Shape>(_ shape: S) -> Path {
            shape.path(in: Bounds(origin: Point(x: Pixels(0), y: Pixels(0)),
                                  size: Size(width: Pixels(10), height: Pixels(10))))
        }

        @MainActor public func use() {
            _ = HStack { Diamond(); Diamond().fill(.accent) }
            _ = Diamond().stroke(.accent, style: StrokeStyle(lineWidth: Pixels(2), lineJoin: .round))
            _ = outline(Diamond())
            _ = outline(Circle())
        }
        """, importing: "MetalUI")
    let applying = try typecheckFile("""
        let p = Path().applying(0)
        """, importing: "MetalUI")

    print("""
        GX-D path(in:): succeeded=\(positive.succeeded) messages=[\(positive.messages)]; \
        applying succeeded=\(applying.succeeded) messages=[\(applying.messages)]
        """)

    try #require(positive.succeeded && !applying.succeeded,
                 """
                 the positive must compile and applying must not, or this guard \
                 cannot fail:
                 positive:
                 \(positive.output)
                 applying:
                 \(applying.output)
                 """)
    #expect(applying.messages.contains("applying"), "refused FOR applying:\n\(applying.output)")
}

/// **G3.3** (`GX-Q`). A `Theme` written before the shadow token existed —
/// `Theme(background:…scrim:)`, no `shadow:` — still compiles from a plain
/// import, as does one passing `shadow:`. **Negative**: an exhaustive `switch`
/// over `ColorToken` without `.shadow` does not (the one public break `GX-J`
/// names, its migration note).
///
/// Mutation once red (**MG3.3**): the `shadow:` default removed.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), metalUISkipReason))
func aThemeWrittenBeforeTheShadowTokenStillCompiles() throws {
    let old = try typecheckFile("""
        import MetalUICore

        let c = Hsla(h: 0, s: 0, l: 0.5)
        let before = Theme(background: c, surface: c, surfaceSecondary: c, accent: c, separator: c,
                           textPrimary: c, scrollIndicator: c, scrim: c)
        let after = Theme(background: c, surface: c, surfaceSecondary: c, accent: c, separator: c,
                          textPrimary: c, scrollIndicator: c, scrim: c, shadow: c)
        let token = before[.shadow]
        """, importing: "MetalUI")
    let exhaustive = try typecheckFile("""
        func name(_ token: ColorToken) -> String {
            switch token {
            case .background, .surface, .surfaceSecondary, .accent, .separator, .textPrimary,
                 .scrollIndicator, .scrim: return "token"
            }
        }
        """, importing: "MetalUI")

    print("""
        GX-Q theme: succeeded=\(old.succeeded) messages=[\(old.messages)]; \
        exhaustive switch succeeded=\(exhaustive.succeeded) messages=[\(exhaustive.messages)]
        """)

    try #require(old.succeeded && !exhaustive.succeeded,
                 """
                 the themes must compile and the old exhaustive switch must not, \
                 or this guard cannot fail:
                 themes:
                 \(old.output)
                 switch:
                 \(exhaustive.output)
                 """)
    #expect(exhaustive.messages.contains("exhaustive"), "refused FOR exhaustiveness:\n\(exhaustive.output)")
}
