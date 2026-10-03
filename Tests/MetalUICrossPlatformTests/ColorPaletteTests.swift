import Testing
import MetalUICore
@testable import MetalUI

// Colour and colour scheme, lane 1 — an app palette in the theme (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.1, tests
// 1.11–1.14; ruling `CR-N`). Portable: values only.

/// The palette key these tests resolve: a `Color(light:dark:)` default.
private struct Brand: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 0.1, green: 0.2, blue: 0.3),
                                    dark: Color(red: 0.7, green: 0.6, blue: 0.5))
}
private struct Second: ThemeColorKey { static let defaultValue = Color(white: 0.25) }
private struct Third: ThemeColorKey { static let defaultValue = Color(.accent) }

private let override = Color(red: 0.9, green: 0.1, blue: 0.1)

/// **1.11.** A palette colour resolves its key's default per scheme. Mutation:
/// palette resolution always takes the light half.
@Test func aPaletteKeyResolvesItsDefaultPerScheme() {
    expectResolved(Color(Brand.self).resolve(in: colourEnvironment(.light, .light)), 0.1, 0.2, 0.3, 1,
                   "light: the default's light half")
    expectResolved(Color(Brand.self).resolve(in: colourEnvironment(.dark, .dark)), 0.7, 0.6, 0.5, 1,
                   "dark: the default's dark half")
}

/// **1.12.** A theme's override wins, and only in that theme. Mutation: the
/// getter ignores `palette`.
@Test func aThemeOverrideWinsAndIsPerTheme() {
    var t = Theme.dark
    t[Brand.self] = override
    expectResolved(Color(Brand.self).resolve(in: colourEnvironment(.dark, t)), 0.9, 0.1, 0.1, 1,
                   "the override, under the theme that holds it")
    expectResolved(Color(Brand.self).resolve(in: colourEnvironment(.light, .light)), 0.1, 0.2, 0.3, 1,
                   "the default, under a theme that does not")
    #expect(t[Brand.self] == override, "the subscript reads the override back")
    #expect(Theme.light[Brand.self] == Brand.defaultValue, "an untouched theme reads the key's default")
}

/// **1.13.** An override is part of the theme's equality and hash, so a
/// palette change through `Window.theme` repaints by the existing guard. An
/// override equal to the key's default is still an entry. Mutation: a custom
/// `==` that skips `palette`.
@Test func aPaletteOverrideIsPartOfTheThemesEquality() {
    var t = Theme.dark
    t[Brand.self] = override
    #expect(t != Theme.dark, "an override makes the theme differ")
    var same = Theme.dark
    same[Brand.self] = override
    #expect(same == t && same.hashValue == t.hashValue, "two themes with the same override are equal and hash equal")
    var defaulted = Theme.dark
    defaulted[Brand.self] = Brand.defaultValue
    #expect(defaulted != Theme.dark, "an override equal to the default is still an entry")
}

/// **1.14.** The built-in tokens are untouched by a palette: a theme with
/// three overrides resolves every `ColorToken` exactly as `Theme.dark`.
/// Mutation: `subscript(token:)` consulting `palette` first.
@Test func everyBuiltInTokenIsUntouchedByAPalette() {
    var t = Theme.dark
    t[Brand.self] = override
    t[Second.self] = Color(white: 0.75)
    t[Third.self] = .red
    for token in ColorToken.allCases {
        #expect(t[token] == Theme.dark[token], "\(token) moved under a palette override")
        #expect(Color(token).resolved(theme: t, scheme: .dark) == Theme.dark[token],
                "\(token) resolves differently under a palette override")
    }
}
