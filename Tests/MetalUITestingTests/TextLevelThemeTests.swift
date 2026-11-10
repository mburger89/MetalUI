import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Testing

// `CR-AD` (Alloy gaps G21 and G27, record 259): `Theme.textSecondary` / `textTertiary` override the derived text levels, and a runtime
// assignment through `Window.lightTheme` / `darkTheme` only repaints. One `.equatable()` panel paints the hierarchical `.secondary` and
// `.tertiary` as rects and as glyphs, and `Color.secondary` as a rect; its build is counted. Colours are read from the scene.

@MainActor final class TLCounter { var builds = 0 }

struct TLPanel: Component, @MainActor Equatable {
    let counter: TLCounter
    var content: some ElementGroup {
        let _ = counter.builds += 1
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(.secondary).frame(width: Pixels(40), height: Pixels(8))
            Rectangle().fill(.tertiary).frame(width: Pixels(40), height: Pixels(8))
            Rectangle().fill(Color.secondary).frame(width: Pixels(40), height: Pixels(9))
            Text("W").foregroundStyle(.secondary)
            Text("W").foregroundStyle(.tertiary)
        }
    }
    static func == (l: TLPanel, r: TLPanel) -> Bool { l.counter === r.counter }
}

private func same(_ a: (h: Float, s: Float, l: Float, a: Float), _ b: Hsla) -> Bool {
    abs(a.h - b.h) < 1e-4 && abs(a.s - b.s) < 1e-4 && abs(a.l - b.l) < 1e-4 && abs(a.a - b.a) < 1e-4
}

private let tlSecondary = Hsla.rgb(0x6272A4)
private let tlTertiary = Hsla.rgb(0x586E75, alpha: 0.9)

private func derived(_ theme: Theme, _ scheme: ColorScheme, _ level: HierarchicalShapeStyle.Level) -> Hsla {
    var c = theme.textPrimary
    c.a *= level.factor(overParent: false, scheme: scheme)
    return c
}

@MainActor private func rects(_ w: TestWindow, _ c: Hsla) -> Int { w.scene.rects.filter { same(($0.background.h, $0.background.s, $0.background.l, $0.background.a), c) }.count }
@MainActor private func glyphs(_ w: TestWindow, _ c: Hsla) -> Int { w.scene.glyphs.filter { same(($0.color.h, $0.color.s, $0.color.l, $0.color.a), c) }.count }

@MainActor private func tlWindow(retain: Bool, scheme: ColorScheme = .light) throws -> (TestWindow, TLCounter) {
    let counter = TLCounter()
    let options = HeadlessPlatformWindow.Options(appearance: scheme == .dark ? .dark : .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(200, 160), colorScheme: scheme, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { TLPanel(counter: counter).equatable() }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, counter)
}

@Suite(.serialized) @MainActor
struct TextLevelThemeTests {
    /// Unset overrides: today's derived colours, in both schemes (`.secondary` 0.588 / 0.648, `.tertiary` 0.306 / 0.292 of the text colour).
    @Test(arguments: [ColorScheme.light, .dark])
    func anUnsetOverrideDrawsTheDerivedLevels(scheme: ColorScheme) throws {
        let (w, _) = try tlWindow(retain: true, scheme: scheme)
        let theme = scheme == .dark ? Theme.dark : .light
        #expect(theme.textSecondary == nil && theme.textTertiary == nil)
        #expect(rects(w, derived(theme, scheme, .secondary)) == 2, "hierarchical + Color.secondary")
        #expect(rects(w, derived(theme, scheme, .tertiary)) == 1)
        #expect(glyphs(w, derived(theme, scheme, .secondary)) == 1)
        #expect(glyphs(w, derived(theme, scheme, .tertiary)) == 1)
    }

    /// A set override is used directly (its own alpha, not multiplied) for the hierarchical levels, `Color.secondary` and glyphs, in
    /// light and dark, given at construction.
    @Test(arguments: [ColorScheme.light, .dark])
    func aSetOverrideIsUsedDirectly(scheme: ColorScheme) throws {
        let counter = TLCounter()
        var light = Theme.light, dark = Theme.dark
        light.textSecondary = tlSecondary; light.textTertiary = tlTertiary
        dark.textSecondary = tlSecondary; dark.textTertiary = tlTertiary
        let options = HeadlessPlatformWindow.Options(appearance: scheme == .dark ? .dark : .light, scaleFactor: 2, accessibilityClientActive: true)
        let w = try TestWindow(size: sz(200, 160), colorScheme: scheme, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
            VStack(spacing: 0) { TLPanel(counter: counter).equatable() }
        }
        w.window.lightTheme = light; w.window.darkTheme = dark
        for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
        #expect(rects(w, tlSecondary) == 2)
        #expect(rects(w, tlTertiary) == 1)
        #expect(glyphs(w, tlSecondary) == 1)
        #expect(glyphs(w, tlTertiary) == 1)
    }

    /// The runtime switch (`window.lightTheme = …`) at an unchanged scheme: only a repaint. The panel is `.equatable()`, so it is a retained
    /// subtree; its content closure is **not** re-run (measured: 0 builds, retention on and off), because colours resolve at paint against the
    /// frame's theme; the new colours are drawn in the same frame, no stale derived colour survives, and later frames add no build.
    @Test(arguments: [true, false])
    func aRuntimeThemeAssignmentRepaintsAReplayedSubtreeWithoutAnotherBuild(retain: Bool) throws {
        let (w, counter) = try tlWindow(retain: retain)
        let before = Theme.light
        #expect(rects(w, derived(before, .light, .secondary)) == 2)
        let buildsBefore = counter.builds
        var themed = Theme.light
        themed.textSecondary = tlSecondary; themed.textTertiary = tlTertiary
        w.window.lightTheme = themed
        w.tick()
        #expect(rects(w, tlSecondary) == 2, "Color.secondary and the hierarchical level follow the assignment")
        #expect(rects(w, tlTertiary) == 1)
        #expect(glyphs(w, tlSecondary) == 1 && glyphs(w, tlTertiary) == 1)
        #expect(rects(w, derived(before, .light, .secondary)) == 0, "no stale derived colour")
        #expect(rects(w, derived(before, .light, .tertiary)) == 0)
        let afterSwitch = counter.builds
        #expect(afterSwitch == buildsBefore, "a theme assignment re-runs no build of the equatable panel: \(afterSwitch - buildsBefore) builds")
        for _ in 0..<3 { w.window.setNeedsRedraw(); w.tick() }
        #expect(counter.builds == afterSwitch, "later frames add no builds")
        #expect(rects(w, tlSecondary) == 2, "still the override after replay")
        // Back to nil: the derived colours return.
        w.window.lightTheme = .light
        w.tick()
        #expect(rects(w, tlSecondary) == 0)
        #expect(rects(w, derived(before, .light, .secondary)) == 2)
    }

    /// Flipping the scheme re-selects the other variant: the dark theme's override shows, the light one's is gone.
    @Test func aSchemeFlipSelectsTheOtherVariantsOverride() throws {
        let (w, _) = try tlWindow(retain: true)
        var dark = Theme.dark
        dark.textSecondary = tlSecondary
        w.window.darkTheme = dark
        w.tick()
        #expect(rects(w, tlSecondary) == 0, "the dark override is not drawn in the light scheme")
        w.setAppearance(.dark)
        w.window.setNeedsRedraw(); w.tick()
        #expect(rects(w, tlSecondary) == 2)
        #expect(rects(w, derived(dark, .dark, .tertiary)) == 1, "an unset tertiary stays derived")
    }
}
