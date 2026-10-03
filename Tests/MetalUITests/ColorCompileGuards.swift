import Testing
import MetalUITestSupport

// Compile-time guards for colour and colour scheme, lane 1 (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.1, guards
// 1.23–1.25; rulings `CR-D`, `CR-E`, `CR-U`). Every fixture is a whole file
// with a PLAIN `import MetalUI` — what an external module can write (`SA-P`).
// A guard skips silently when `.build/<triple>/debug/Modules` is absent.

private let skipReason: Comment =
    "built module directory .build/<triple>/debug/Modules holding MetalUI not found — guard skipped"

/// **1.23** (`CR-D`). `Color`'s statics are usable off the main actor: a
/// nonisolated default argument and a `ThemeColorKey`'s nonisolated
/// `static let`. Mutation: move `Element` onto `Color`'s primary declaration
/// ("main actor-isolated default value in a nonisolated context"). **That
/// mutation fails the package build first** (`Color.swift`,
/// `TextStyleResolution.swift`), as do `@MainActor` on `static let red`
/// (`ColorValueTests`), on `opacity(_:)` (`Color.secondary`'s initialiser) and
/// on `init(_ key:)` (`ColorPaletteTests`): every member this fixture touches
/// is also used nonisolated inside the package or by the nonisolated
/// cross-platform tests, so no mutation this guard alone sees is known
/// (`CR-X` item 4). It stays as the one plain-import check of what an
/// external module can write — a second line of defence.
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func colourStaticsAreUsableOffTheMainActor() throws {
    let result = try typecheckFile("""
        nonisolated func f(_ c: Color = .red) -> Color { c.opacity(0.5) }
        struct K: ThemeColorKey {
            static let defaultValue = Color(light: .red, dark: Color(red: 0.1, green: 0.2, blue: 0.3))
        }
        nonisolated func g() -> Color { Color(K.self) }
        """, importing: "MetalUI")
    print("CR-D off the main actor: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "Color's statics must be nonisolated:\n\(result.output)")
}

/// **1.24** (`CR-E` items 1 and 3). Every `ColorToken` spelling still
/// compiles: each colour-taking site with a leading-dot token and with a
/// `ColorToken` variable (which only the disfavoured twin accepts), a write of
/// a retyped stored property, and a comparison against one. `Text`,
/// `ProposalText`, `TextField` and `TextEditor` have their result types
/// pinned: each also has an `ElementGroup` fallback returning
/// `EnvironmentScope<Self>`, which would silently accept a deleted own twin.
/// Mutations seen by this guard alone: delete `Text.foregroundColor(_ token:)`'s
/// twin (M20: "cannot convert value of type 'EnvironmentScope<Text>' to
/// specified type 'Text'"; only this guard reddens), and delete
/// `onTap(hoverColor: ColorToken)`'s twin (M26). Removing
/// `@_disfavoredOverload` from `StyledElement.background(_ token:)` (M21)
/// **fails the package build first** (`DragAndDropDemo.swift` ambiguous) —
/// this guard is the second line of defence there (`CR-X` item 2).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func everyColorTokenSpellingStillCompiles() throws {
    let result = try typecheckFile("""
        @MainActor func spellings(_ t: ColorToken) {
            let box = Box().background(.surface).background(t)
                .hoverBackground(.accent).hoverBackground(t).focusBackground(.separator).focusBackground(t)
                .border(.separator, width: Pixels(1)).border(t, width: Pixels(1))
                .border(.separator, widths: Edges(all: Pixels(1))).border(t, widths: Edges(all: Pixels(1)))
                .hoverBorder(.accent, width: Pixels(1)).hoverBorder(t, width: Pixels(1))
                .hoverBorder(.accent, widths: Edges(all: Pixels(1))).hoverBorder(t, widths: Edges(all: Pixels(1)))
                .focusBorder(.accent, width: Pixels(1)).focusBorder(t, width: Pixels(1))
                .focusBorder(.accent, widths: Edges(all: Pixels(1))).focusBorder(t, widths: Edges(all: Pixels(1)))
            _ = box.shadow(color: .shadow, radius: Pixels(2)).shadow(color: t, radius: Pixels(2))
            _ = Decoration(background: .surface, hoverBackground: .accent, focusBackground: .separator)
            _ = Decoration(background: t, hoverBackground: t, focusBackground: t)
            _ = BorderStyle(.separator, width: Pixels(1))
            _ = BorderStyle(t, width: Pixels(1))
            _ = BorderStyle(.separator, widths: Edges(all: Pixels(1)))
            _ = BorderStyle(t, widths: Edges(all: Pixels(1)))
            let leaf = Rectangle(width: Pixels(10), height: Pixels(10)).frame(width: Pixels(40), height: Pixels(40))
            _ = leaf.background(.surface).background(t).border(.separator, width: Pixels(1))
                .border(t, width: Pixels(1)).shadow(color: .shadow, radius: Pixels(2)).shadow(color: t, radius: Pixels(2))
            _ = leaf.background(.surface, in: Circle())
            _ = leaf.background(t, in: Circle())
            _ = Circle().fill(.accent).fill(t).stroke(.separator, lineWidth: Pixels(1)).stroke(t, lineWidth: Pixels(1))
                .strokeBorder(.separator, lineWidth: Pixels(1)).strokeBorder(t, lineWidth: Pixels(1))
                .fill(t, style: FillStyle()).stroke(t, style: StrokeStyle()).strokeBorder(t, style: StrokeStyle())
            _ = Circle().fill(t)
            _ = Circle().fill(t, style: FillStyle())
            _ = Circle().stroke(t, lineWidth: Pixels(1))
            _ = Circle().stroke(t, style: StrokeStyle())
            _ = Circle().strokeBorder(t, lineWidth: Pixels(1))
            _ = Circle().strokeBorder(t, style: StrokeStyle())
            _ = Text("x").foregroundColor(.textPrimary).foregroundColor(t).foregroundStyle(.accent).foregroundStyle(t)
            _ = ProposalText("x").foregroundColor(.textPrimary).foregroundColor(t).foregroundStyle(t)
            _ = TextField("", text: .constant("")).foregroundColor(.textPrimary).foregroundColor(t)
            _ = TextEditor(text: .constant("")).foregroundColor(.textPrimary).foregroundColor(t)
            // The result types are pinned: each of these four has an
            // `ElementGroup` fallback returning `EnvironmentScope<Self>`, so
            // without the annotation a deleted own twin still compiles.
            let _: Text = Text("x").foregroundColor(t)
            let _: Text = Text("x").foregroundStyle(t)
            let _: ProposalText = ProposalText("x").foregroundColor(t)
            let _: ProposalText = ProposalText("x").foregroundStyle(t)
            let _: TextField = TextField("", text: .constant("")).foregroundColor(t)
            let _: TextEditor = TextEditor(text: .constant("")).foregroundColor(t)
            _ = Box { Text("x") }.foregroundStyle(.accent).foregroundStyle(t)
            _ = Box { Text("x") }.foregroundColor(.accent).foregroundColor(t)
            _ = Background(.surface) { leaf }
            _ = Background(t) { leaf }
            _ = Rectangle(width: Pixels(1), height: Pixels(1), color: .accent)
            _ = Rectangle(width: Pixels(1), height: Pixels(1), color: t)
            _ = leaf.onTap(hoverColor: .accent) {}
            _ = leaf.onTap(hoverColor: t) {}
            _ = Color(.surface)
            _ = Color(t)
            var b = Box()
            b.decoration.background = .surface
            let rect = Rectangle(width: Pixels(1), height: Pixels(1), color: .accent)
            _ = rect.color == .accent
        }
        """, importing: "MetalUI")
    print("CR-E token spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "every ColorToken spelling must still compile:\n\(result.output)")
}

/// **1.25** (`CR-E`, `CR-U`). SwiftUI's spellings typecheck with no
/// ambiguity; `Text`'s own spellings are pinned to return `Text`. Removing
/// `@_disfavoredOverload` from `Shadow.swift`'s token twin (M22) or the legacy
/// shadow twin (M25) **fails the build first** (`ShadowTests.swift`,
/// `LooksDemo.swift` ambiguous); a mutation this guard alone sees: make
/// `Text.foregroundColor(_ color:)` take a non-optional `Color` (M27, the
/// `foregroundColor(nil)` line; `CR-X` item 4).
@Test(.enabled(if: canTypecheck(module: "MetalUI"), skipReason))
func theSwiftUISpellingsTypecheckWithoutAmbiguity() throws {
    let result = try typecheckFile("""
        @MainActor func spellings() {
            // `Text`'s own spellings return `Text`, as SwiftUI's do; pinned,
            // because the `ElementGroup` fallback would otherwise accept each
            // line as an `EnvironmentScope<Text>`.
            let _: Text = Text("x").foregroundColor(.red)
            let _: Text = Text("x").foregroundColor(nil)
            let _: Text = Text("x").foregroundStyle(.secondary)
            _ = Box { Text("x") }.foregroundStyle(.secondary)
            _ = Box().background(.surface)
            _ = Rectangle().fill(.red)
            _ = Rectangle().stroke(.blue, lineWidth: 2)
            _ = Rectangle().frame(width: Pixels(4), height: Pixels(4)).shadow(radius: Pixels(4))
            _ = Box().shadow(radius: Pixels(4))
            let c: Color = Color.red.opacity(0.5)
            _ = c
            _ = Color(.sRGB, red: 1, green: 0, blue: 0)
            _ = Color(white: 0.5)
            _ = Color(hue: 0.5, saturation: 1, brightness: 1)
        }
        """, importing: "MetalUI")
    print("CR-E SwiftUI spellings: succeeded=\(result.succeeded) messages=[\(result.messages)]")
    #expect(result.succeeded, "SwiftUI's spellings must typecheck without ambiguity:\n\(result.output)")
}
