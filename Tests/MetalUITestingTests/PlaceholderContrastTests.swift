import Foundation
import MetalUI
import MetalUICore
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// Alloy contrast gaps (`VT-I`, `VT-J`, `TBS-K`, record 257): the placeholder is `Color.secondary` (SwiftUI's
// `placeholderTextColor`, probe `swiftui-vertical-text-field.swift` arm P), a `prompt:` `Text`'s style colours it, the field's
// own `foregroundColor` does not, and an unselected hovered `TabStrip` tab's ink reaches WCAG AA (4.5:1). PLAIN imports,
// headless `TestWindow`.

private func linear(_ c: Float) -> Double {
    let c = Double(c)
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}
private func luminance(_ c: Rgba) -> Double { 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b) }
/// The WCAG 2 contrast ratio of two opaque colours.
private func contrast(_ a: Rgba, _ b: Rgba) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
/// `ink` (with its own alpha) over the opaque `base`.
private func over(_ ink: Hsla, _ base: Rgba) -> Rgba {
    let i = ink.toRgba()
    return Rgba(r: i.r * i.a + base.r * (1 - i.a), g: i.g * i.a + base.g * (1 - i.a), b: i.b * i.a + base.b * (1 - i.a), a: 1)
}
private func same(_ a: Hsla, _ b: Hsla) -> Bool {
    let (x, y) = (a.toRgba(), b.toRgba())
    return abs(x.r - y.r) < 1e-4 && abs(x.g - y.g) < 1e-4 && abs(x.b - y.b) < 1e-4 && abs(x.a - y.a) < 1e-4
}

@MainActor private func firstGlyph<E: Element>(_ scheme: ColorScheme = .light, _ make: @escaping @MainActor () -> E) throws -> Hsla {
    let window = try harnessWindow(size: sz(300, 120), colorScheme: scheme) { make() }
    window.tick(); window.tick()
    let c = try #require(window.scene.glyphs.first, "the tree draws a glyph").color
    return Hsla(h: c.h, s: c.s, l: c.l, a: c.a)
}

@MainActor private func placeholder(_ scheme: ColorScheme = .light, _ field: @escaping @MainActor () -> TextField) throws -> Hsla {
    try firstGlyph(scheme) { Box { field() } }
}
@MainActor private func reference<S: ShapeStyle>(_ style: S, _ scheme: ColorScheme = .light) throws -> Hsla {
    try firstGlyph(scheme) { Box { Text("x").foregroundStyle(style) } }
}

/// 1 - the default placeholder resolves as `Color.secondary` does, in both schemes, and reaches 4.4:1 on the light surface
/// (4.479 measured). Mutation: **M1** `color.a *= 0.45` of the field's text colour (the old rule) reddens both.
@Test @MainActor func theDefaultPlaceholderIsColorSecondaryAndReadable() throws {
    for scheme in [ColorScheme.light, .dark] {
        let want = try reference(Color.secondary, scheme)
        #expect(same(try placeholder(scheme) { TextField("x", text: .constant("")) }, want), "\(scheme): horizontal field")
        #expect(same(try placeholder(scheme) { TextField("x", text: .constant(""), axis: .vertical) }, want), "\(scheme): vertical field")
    }
    let theme = Theme.light
    let ratio = contrast(over(try placeholder { TextField("x", text: .constant("")) }, theme.surface.toRgba()), theme.surface.toRgba())
    #expect(ratio >= 4.4, "light placeholder on the surface: \(ratio)")
    let dark = Theme.dark
    let darkRatio = contrast(over(try placeholder(.dark) { TextField("x", text: .constant("")) }, dark.surface.toRgba()), dark.surface.toRgba())
    #expect(darkRatio >= 4.4, "dark placeholder on the surface: \(darkRatio)")
}

/// 2 - the field's own `foregroundColor` does not reach the placeholder (probe P). Mutation: **M2** the old
/// `foregroundColor ?? textPrimary` source for the placeholder reddens it.
@Test @MainActor func aFieldsForegroundColorDoesNotChangeItsPlaceholder() throws {
    let plain = try placeholder { TextField("x", text: .constant("")) }
    let red = try placeholder { TextField("x", text: .constant("")).foregroundColor(.red) }
    let redVertical = try placeholder { TextField("x", text: .constant(""), axis: .vertical).foregroundColor(.red) }
    let scoped = try firstGlyph { Box { TextField("x", text: .constant("")).foregroundStyle(.red) } }
    #expect(same(red, plain) && same(redVertical, plain) && same(scoped, plain))
}

/// 3 - a `prompt:` `Text`'s flat colour and hierarchical level colour the placeholder, and its string is the placeholder.
/// Mutation: **M3** `applyPrompt` ignoring the prompt's colour reddens both style arms.
@Test @MainActor func aPromptsStyleColoursThePlaceholder() throws {
    let redWant = try reference(Color.red)
    let tertiaryWant = try reference(HierarchicalShapeStyle.tertiary)
    let red = try placeholder { TextField("t", text: .constant(""), prompt: Text("x").foregroundColor(.red)) }
    let tertiary = try placeholder { TextField("t", text: .constant(""), prompt: Text("x").foregroundStyle(.tertiary)) }
    let secondary = try placeholder { TextField("t", text: .constant(""), prompt: Text("x").foregroundStyle(.secondary)) }
    let axis = try placeholder { TextField("t", text: .constant(""), prompt: Text("x").foregroundColor(.red), axis: .vertical) }
    let none = try placeholder { TextField("t", text: .constant(""), prompt: Text("x")) }
    let secondaryWant = try reference(Color.secondary)
    #expect(same(red, redWant) && same(axis, redWant), "a flat colour")
    #expect(same(tertiary, tertiaryWant) && !same(tertiary, secondaryWant), "the tertiary level")
    #expect(same(secondary, secondaryWant) && same(none, secondaryWant), "secondary and no style are the default")
    let window = try harnessWindow(size: sz(300, 120)) {
        Box { TextField("ti", text: .constant(""), prompt: Text("Prompt")) }
    }
    window.tick()
    #expect(window.scene.glyphs.count == "Prompt".count, "the prompt's string is drawn, not the title")
}

/// 4 - `TextEditor`'s placeholder takes the same default and ignores its `foregroundColor`. Mutation: **M4** the old rule in
/// `TextEditor.paintContent`.
@Test @MainActor func theTextEditorPlaceholderTakesTheSameDefault() throws {
    for scheme in [ColorScheme.light, .dark] {
        let want = try reference(Color.secondary, scheme)
        let editor = try firstGlyph(scheme) { Box { TextEditor("x", text: .constant("")) } }
        let red = try firstGlyph(scheme) { Box { TextEditor("x", text: .constant("")).foregroundColor(.red) } }
        #expect(same(editor, want) && same(red, want), "\(scheme)")
    }
}

/// 5 - an unselected tab's ink reaches 4.5:1 hovered and at rest, in both schemes, over the bar (`.surfaceSecondary`) with the
/// hover wash. Mutation: **M5** the ink at 0.62 (4.40 light hovered) reddens it.
@Test @MainActor func anUnselectedHoveredTabStripTabsInkIsAA() throws {
    for scheme in [ColorScheme.light, .dark] {
        let theme = scheme == .dark ? Theme.dark : Theme.light
        let window = try harnessWindow(size: sz(500, 100), colorScheme: scheme) {
            VStack(spacing: 0) {
                TabStrip(selection: .constant("a"), tabs: [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "b.swift")])
                Spacer()
            }
        }
        window.tick(); window.tick()
        let frame = try window.element(label: "b.swift").frame
        func inkAndWash() throws -> (ink: Hsla, wash: Hsla?) {
            let glyphs = window.scene.glyphs.filter { $0.bounds.origin.x >= frame.origin.x.value
                && $0.bounds.origin.x <= frame.origin.x.value + frame.size.width.value }
            let ink = try #require(glyphs.first, "tab b's title").color
            let wash = window.scene.rects.first { r in
                r.bounds.origin.x <= frame.origin.x.value + 4 && r.bounds.size.width >= frame.size.width.value
                    && r.background.a > 0 && r.background.a < 0.2 }?.background
            func h(_ c: MUIHsla) -> Hsla { Hsla(h: c.h, s: c.s, l: c.l, a: c.a) }
            return (h(ink), wash.map(h))
        }
        let bar = theme.surfaceSecondary.toRgba()
        let rest = try inkAndWash()
        let restRatio = contrast(over(rest.ink, bar), bar)
        #expect(restRatio >= 4.5, "\(scheme) at rest: \(restRatio)")
        window.hover(at: pt(frame.origin.x.value + 30, 16)); window.tick()
        let hovered = try inkAndWash()
        let wash = try #require(hovered.wash, "\(scheme): the hover wash")
        let base = over(wash, bar)
        let ratio = contrast(over(hovered.ink, base), base)
        #expect(ratio >= 4.5, "\(scheme) hovered: \(ratio)")
    }
}

// `TBS-L` (Alloy gap G30, record 262): an unselected tab's ink is `Theme.textSecondary` when the theme sets it, else `textPrimary` at 0.64.

@MainActor private func unselectedTabInk(_ window: TestWindow) throws -> Hsla {
    let frame = try window.element(label: "b.swift").frame
    let glyphs = window.scene.glyphs.filter { $0.bounds.origin.x >= frame.origin.x.value
        && $0.bounds.origin.x <= frame.origin.x.value + frame.size.width.value }
    let c = try #require(glyphs.first, "tab b's title").color
    return Hsla(h: c.h, s: c.s, l: c.l, a: c.a)
}
@MainActor private func tabStripWindow(_ scheme: ColorScheme = .light) throws -> TestWindow {
    let window = try harnessWindow(size: sz(500, 100), colorScheme: scheme) {
        VStack(spacing: 0) {
            TabStrip(selection: .constant("a"), tabs: [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "b.swift")])
            Spacer()
        }
    }
    window.tick(); window.tick()
    return window
}
private let tabOverride = Hsla(h: 0.08, s: 0.9, l: 0.4, a: 1)

/// 6 - no `textSecondary`: the unselected ink is `textPrimary` at 0.64 exactly (`TBS-K` unchanged). Mutation: **M6** the ink back on the
/// derived `Color.secondary` (0.588 light) reddens it.
@Test @MainActor func withoutAnOverrideTheUnselectedInkIsTextPrimaryAt064() throws {
    for scheme in [ColorScheme.light, .dark] {
        var want = (scheme == .dark ? Theme.dark : Theme.light).textPrimary
        want.a *= 0.64
        #expect(same(try unselectedTabInk(try tabStripWindow(scheme)), want), "\(scheme)")
    }
}

/// 7 - a theme with `textSecondary` set paints the unselected ink as that colour (both variants). Mutation: **M7** the override ignored.
@Test @MainActor func aThemesTextSecondaryIsTheUnselectedInk() throws {
    for scheme in [ColorScheme.light, .dark] {
        let window = try harnessWindow(size: sz(500, 100), colorScheme: scheme) {
            VStack(spacing: 0) {
                TabStrip(selection: .constant("a"), tabs: [TabStripItem(id: "a", title: "main.swift"), TabStripItem(id: "b", title: "b.swift")])
                Spacer()
            }
        }
        var theme = scheme == .dark ? Theme.dark : Theme.light
        theme.textSecondary = tabOverride
        if scheme == .dark { window.window.darkTheme = theme } else { window.window.lightTheme = theme }
        window.window.setNeedsRedraw(); window.tick(); window.tick()
        #expect(same(try unselectedTabInk(window), tabOverride), "\(scheme)")
    }
}

/// 8 - assigning the theme at runtime repaints the ink, and clearing the override restores 0.64. Mutation: **M7** as above.
@Test @MainActor func switchingTheTextSecondaryRepaintsTheUnselectedInk() throws {
    let window = try tabStripWindow()
    var base = Theme.light.textPrimary
    base.a *= 0.64
    #expect(same(try unselectedTabInk(window), base), "before")
    var themed = Theme.light
    themed.textSecondary = tabOverride
    window.window.lightTheme = themed
    window.tick()
    #expect(same(try unselectedTabInk(window), tabOverride), "after the assignment")
    window.window.lightTheme = .light
    window.tick()
    #expect(same(try unselectedTabInk(window), base), "after clearing")
}
