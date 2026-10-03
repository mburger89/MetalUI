import Testing
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUIShaderTypes
@testable import MetalUI

// Colour and colour scheme, lane 2 — the window's scheme, its theme variants,
// `.preferredColorScheme(_:)` and the platform hook (spec
// `docs/superpowers/specs/2026-10-03-colour-design.md` §6.2, tests 2.1–2.17
// and 2.22; rulings `CR-J`, `CR-K`, `CR-L`, `CR-M`, `CR-Q`, `CR-S`, `CR-T`,
// `CR-V`). Headless: a `FakePlatformWindow` reports the appearance, records
// `setPreferredColorScheme` calls, and the scene's rects carry the resolved
// colours.

private func px(_ v: Float) -> Pixels { Pixels(v) }

/// The two halves of the test's dynamic colour, chosen far apart.
private let lightHalf = Color(red: 1, green: 0, blue: 0)
private let darkHalf = Color(red: 0, green: 0, blue: 1)
private let lightHalfRGBA = Rgba(r: 1, g: 0, b: 0, a: 1)
private let darkHalfRGBA = Rgba(r: 0, g: 0, b: 1, a: 1)
private let dynamic = Color(light: lightHalf, dark: darkHalf)

private func rgba(_ c: MUIHsla) -> Rgba { Hsla(h: c.h, s: c.s, l: c.l, a: c.a).toRgba() }

private func close(_ a: Rgba, _ b: Rgba, tolerance: Float = 1.0 / 255) -> Bool {
    abs(a.r - b.r) <= tolerance && abs(a.g - b.g) <= tolerance && abs(a.b - b.b) <= tolerance
        && abs(a.a - b.a) <= tolerance
}

/// Whether some rect in `scene` has `want` as its background.
private func fills(_ scene: Scene, _ want: Rgba) -> Bool {
    scene.rects.contains { close(rgba($0.background), want) }
}

private func fills(_ scene: Scene, _ want: Hsla) -> Bool { fills(scene, want.toRgba()) }

/// The background of the rect at `width` wide (each test sizes its marker
/// boxes distinctly), or `nil`.
private func fill(_ scene: Scene, width: Float) -> Rgba? {
    scene.rects.first { $0.bounds.size.width == width }.map { rgba($0.background) }
}

private func describe(_ scene: Scene) -> String {
    scene.rects.map { "w\($0.bounds.size.width) bg\(rgba($0.background))" }.joined(separator: ", ")
}

/// A sized legacy box.
@MainActor private func box(_ width: Float) -> some StyledElement {
    Box().frame(width: px(width), height: px(10))
}

/// What a `SchemeReader`'s content read while building, in build order.
@MainActor
private final class SchemeLog {
    var reads: [ColorScheme] = []
}

/// A `Component` that reads `@Environment(\.colorScheme)` while building its
/// content — the read SwiftUI's `body` makes — and paints the test's dynamic
/// colour.
private struct SchemeReader: Component {
    let log: SchemeLog
    var width: Float = 12
    @Environment(\.colorScheme) var scheme

    var content: some ElementGroup {
        log.reads.append(scheme)
        return Box().frame(width: px(width), height: px(10)).background(dynamic)
    }
}

/// Reads `pass.environment.colorScheme` in all three phases.
@MainActor
private final class SchemePhaseLog {
    var layout: [ColorScheme] = []
    var prepaint: [ColorScheme] = []
    var paint: [ColorScheme] = []
}

private struct SchemePhaseReader: Element {
    let log: SchemePhaseLog

    func requestLayout(_ id: GlobalElementID, pass: inout LayoutPass) -> (LayoutNodeID, Void) {
        log.layout.append(pass.environment.colorScheme)
        return (pass.requestNativeLeaf { _ in LayoutMeasurement(size: SizeD(width: 10, height: 10)) }.layoutNodeID, ())
    }

    func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
                  pass: inout PrepaintPass) {
        log.prepaint.append(pass.environment.colorScheme)
    }

    func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>, layout: inout Void,
               prepaint: inout Void, pass: inout PaintPass) {
        log.paint.append(pass.environment.colorScheme)
    }
}

/// An app palette key for 2.16 and 2.17.
private enum Brand: ThemeColorKey {
    static var defaultValue: Color { Color(light: Color(red: 0, green: 1, blue: 0), dark: Color(red: 0, green: 0.5, blue: 0)) }
}

private let brandOverride = Color(red: 1, green: 0, blue: 1)
private let brandOverrideRGBA = Rgba(r: 1, g: 0, b: 1, a: 1)
private let brandSecondOverride = Color(red: 0, green: 1, blue: 1)
private let brandSecondOverrideRGBA = Rgba(r: 0, g: 1, b: 1, a: 1)

/// A theme distinguishable from both built-ins at `.surface`.
private func customTheme() -> Theme {
    var theme = Theme.dark
    theme.surface = Hsla.rgb(0x123456)
    return theme
}

/// A test-owned switch, flipped from input (the window's `onInput`).
@MainActor
private final class Flag {
    var value: ColorScheme? = nil
}

/// Delivers an input event no element claims, so it reaches `Window.onInput`
/// and the window marks itself dirty, as every input does.
@MainActor private func flip(_ platform: FakePlatformWindow) {
    platform.simulateInput(.modifiersChanged([]))
}

// MARK: - 2.1–2.4: the stamp (CR-J)

/// **2.1** (`CR-J` item 3). A `Component` reading `@Environment(\.colorScheme)`
/// while building logs the platform's appearance; `window.colorScheme` agrees.
/// Mutation: do not stamp (the root stays `.light`) — the dark arm reddens.
@MainActor
@Test func theWindowStampsItsPlatformsAppearanceAsTheColorScheme() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for appearance in [ColorScheme.dark, .light] {
        let log = SchemeLog()
        let (window, _) = try makeFakeWindow(device: device, appearance: appearance) {
            Row { SchemeReader(log: log) }
        }
        window.drawFrameIfNeeded()
        #expect(window.colorScheme == appearance)
        #expect(log.reads == [appearance], "\(appearance): the build read \(log.reads)")
    }
}

/// **2.2** (`CR-J` item 3). An appearance change dirties the window, and the
/// next build reads the new scheme and paints the dynamic colour's new half.
/// Mutation: stamp the scheme captured at `init`.
@MainActor
@Test func anAppearanceChangeRebuildsWithTheNewScheme() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemeLog()
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { SchemeReader(log: log) }
    }
    window.drawFrameIfNeeded()
    #expect(fills(window.lastScene, lightHalfRGBA), "\(describe(window.lastScene))")
    try #require(window.needsRedraw == false)

    platform.simulateAppearanceChange(to: .dark)
    #expect(window.needsRedraw, "an appearance change must repaint")
    window.drawFrameIfNeeded()
    #expect(log.reads.last == .dark)
    #expect(window.colorScheme == .dark)
    #expect(fills(window.lastScene, darkHalfRGBA), "\(describe(window.lastScene))")
}

/// **2.3** (`CR-J` item 3). A report of the scheme the window already has does
/// not wake it. Mutation: remove `colorScheme`'s equality guard.
@MainActor
@Test func aReportOfTheCurrentSchemeDoesNotWakeTheDisplay() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { box(10).background(dynamic) }
    }
    window.drawFrameIfNeeded()
    try #require(window.needsRedraw == false)
    platform.simulateAppearanceChange(to: .light)
    #expect(window.colorScheme == .light)
    #expect(window.needsRedraw == false, "a report of the current scheme must not repaint")
}

/// **2.4** (`CR-J` item 4). Reading the scheme in layout, prepaint and paint
/// writes nothing: after a draw, the next call pauses. Mutation: write the
/// stamp into `Window.environment` each draw (its `didSet` dirties).
@MainActor
@Test func readingTheColorSchemeInEveryPhaseLetsTheDisplayLinkPause() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemePhaseLog()
    let (window, _) = try makeFakeWindow(device: device, appearance: .dark) {
        Row { SchemePhaseReader(log: log) }
    }
    window.drawFrameIfNeeded()
    #expect(log.layout == [.dark] && log.prepaint == [.dark] && log.paint == [.dark],
            "every phase reads the stamped scheme: \(log.layout) \(log.prepaint) \(log.paint)")
    window.drawFrameIfNeeded()
    let frames = window.framesDrawn
    let pauses = window.pausesEntered
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == frames, "a settled window must not draw again")
    #expect(window.pausesEntered == pauses + 1, "a settled window must pause")
}

// MARK: - 2.5–2.7: scopes and variants (CR-K, CR-S)

/// **2.5** (`CR-K` item 2, `CR-S`). A scope writing `colorScheme` gives its
/// subtree the window's variant for that scheme; its sibling keeps the root's
/// (probe `V1`). Mutation: drop the variant re-stamp in `scopedValues`.
@MainActor
@Test func aColorSchemeScopeSelectsTheWindowsVariantForItsSubtree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let custom = customTheme()
    let (window, _) = try makeFakeWindow(device: device, appearance: .light) {
        Row {
            box(11).background(.surface).environment(\.colorScheme, .dark)
            box(13).background(.surface)
        }
    }
    window.darkTheme = custom
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    #expect(fill(scene, width: 11).map { close($0, custom.surface.toRgba()) } == true, "\(describe(scene))")
    #expect(fill(scene, width: 13).map { close($0, Theme.light.surface.toRgba()) } == true, "\(describe(scene))")
}

/// **2.6** (`CR-K` item 2). A `\.self` reset below a dark scope reads the bare
/// value's `.light` and the light variant. Mutation: re-stamp `colorScheme`
/// from the top after a transform.
@MainActor
@Test func aSelfResetBelowADarkScopeReadsLightAndTheLightVariant() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemePhaseLog()
    let (window, _) = try makeFakeWindow(device: device, appearance: .light) {
        Row {
            Row {
                Row {
                    SchemePhaseReader(log: log)
                    box(11).background(.surface)
                }
                .environment(\.self, EnvironmentValues())
            }
            .environment(\.colorScheme, .dark)
        }
    }
    window.drawFrameIfNeeded()
    #expect(log.paint == [.light], "\(log.paint)")
    #expect(fill(window.lastScene, width: 11).map { close($0, Theme.light.surface.toRgba()) } == true,
            "\(describe(window.lastScene))")
}

/// **2.7** (`CR-K` item 3). `.theme(.dark)` in a light window pins the tokens
/// but not the scheme: `.surface` is dark, `colorScheme` stays `.light`, and
/// `.red` resolves its light half. Mutation: `.theme(_:)` also writes
/// `colorScheme = .dark`.
@MainActor
@Test func anExplicitThemeScopePinsTokensButNotTheScheme() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemePhaseLog()
    let (window, _) = try makeFakeWindow(device: device, appearance: .light) {
        Row {
            Row {
                SchemePhaseReader(log: log)
                box(11).background(.surface)
                box(13).background(.red)
            }
            .theme(.dark)
        }
    }
    window.drawFrameIfNeeded()
    let scene = window.lastScene
    #expect(log.paint == [.light], "\(log.paint)")
    #expect(fill(scene, width: 11).map { close($0, Theme.dark.surface.toRgba()) } == true, "\(describe(scene))")
    // `Color.red`'s light half, FF383C (probe N).
    #expect(fill(scene, width: 13).map { close($0, Rgba(r: 1, g: 56.0 / 255, b: 60.0 / 255, a: 1)) } == true,
            "\(describe(scene))")
}

// MARK: - 2.8–2.10: the preference (CR-L, CR-T, CR-V)

/// **2.8** (`CR-L` item 2, probe `P1`). A child's `.preferredColorScheme(.dark)`
/// is window-wide: its **sibling** builds dark, and the platform was asked for
/// `.dark`. Mutation: implement it as a scope write
/// (`.environment(\.colorScheme, …)`) — the sibling arm reddens.
@MainActor
@Test func preferredColorSchemeIsWindowWide() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemeLog()
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row {
            box(11).preferredColorScheme(.dark)
            SchemeReader(log: log)
        }
    }
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(log.reads.last == .dark, "the sibling must build dark: \(log.reads)")
    #expect(window.colorScheme == .dark)
    #expect(platform.preferredColorSchemeRequests == [.dark])
}

/// **2.9** (`CR-L` item 3, `CR-T`; probes `P3`…`P7`). SwiftUI's reduction:
/// siblings — the first non-nil wins; nested — the outer replaces the inner,
/// `nil` included. Each arm its own window in a light fake. Arm `PR` (`CR-T`):
/// a main-tree preference beats an open popover's, even when the popover's
/// declarer comes first in the walk; with no main-tree preference, the
/// popover's counts; arm `PD`, the same for a `Deferred` presentation root.
/// Mutations: last-wins (P3, P4 redden); inner-wins (P5, P6 redden); plain
/// walk order (PR's and PD's first halves redden).
@MainActor
@Test func thePreferredColorSchemeReductionMatchesSwiftUI() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())

    func scheme<Root: Element>(_ label: String, _ content: @escaping @MainActor () -> Root) throws -> ColorScheme {
        let (window, _) = try makeFakeWindow(device: device, size: 120, appearance: .light, content: content)
        for _ in 0..<4 { window.drawFrameIfNeeded() }
        return window.colorScheme
    }

    #expect(try scheme("P3") { Row { box(10).preferredColorScheme(.dark); box(11).preferredColorScheme(.light) } } == .dark,
            "P3: the first non-nil sibling wins")
    #expect(try scheme("P4") { Row { box(10).preferredColorScheme(.light); box(11).preferredColorScheme(.dark) } } == .light,
            "P4: the first non-nil sibling wins")
    #expect(try scheme("P5") { Row { box(10).preferredColorScheme(.dark).preferredColorScheme(.light) } } == .light,
            "P5: the outer replaces the inner")
    #expect(try scheme("P6") { Row { box(10).preferredColorScheme(.dark).preferredColorScheme(nil) } } == .light,
            "P6: an outer nil replaces the inner dark: no preference, the platform's light")
    #expect(try scheme("P7") { Row { box(10).preferredColorScheme(nil); box(11).preferredColorScheme(.dark) } } == .dark,
            "P7: a nil sibling does not decide")

    #expect(try scheme("PR main") {
        Row {
            box(10).popover(isPresented: .constant(true)) { box(9).preferredColorScheme(.dark) }
            box(11).preferredColorScheme(.light)
        }
    } == .light, "PR: the main tree's preference beats the popover's")
    #expect(try scheme("PR popover") {
        Row {
            box(10).popover(isPresented: .constant(true)) { box(9).preferredColorScheme(.dark) }
            box(11)
        }
    } == .dark, "PR: with no main-tree preference the popover's counts")

    #expect(try scheme("PD main") {
        Row {
            Deferred { Box { box(9).preferredColorScheme(.dark) }.position(.absolute).inset(px(0)) }
            box(11).preferredColorScheme(.light)
        }
    } == .light, "PD: the main tree's preference beats a presentation root's")
    #expect(try scheme("PD presentation") {
        Row {
            Deferred { Box { box(9).preferredColorScheme(.dark) }.position(.absolute).inset(px(0)) }
            box(11)
        }
    } == .dark, "PD: with no main-tree preference the presentation root's counts")
    #expect(try scheme("PD in-flow") {
        Row {
            Deferred { Box { box(9).preferredColorScheme(.dark) } }
            box(11).preferredColorScheme(.light)
        }
    } == .dark, "PD: an in-flow Deferred is the main tree, first in the walk")
}

/// **2.10** (`CR-L` item 1, `CR-V` item 1). On both vocabularies a scope with a
/// following sibling records the same element ids and bounds with and without
/// `.preferredColorScheme(.dark)`. Mutations: the scope consumes a cursor slot
/// (both arms: the sibling's id shifts); record the preference only in
/// `requestGroupLayout` (the proposal arm's preference is lost — see the
/// window arm below).
@MainActor
@Test func aPreferenceOnBothVocabulariesIsTransparentToLayoutAndIdentity() throws {
    func bounds<E: Element>(_ element: E) -> (ids: [GlobalElementID: Bounds<Pixels>], preference: ColorScheme?) {
        var root = element
        let frame = Frame(contentSize: Size(width: px(200), height: px(200)), scaleFactor: 1,
                          recordsElementBounds: true)
        frame.render(&root)
        return (frame.elementBounds, frame.collectedColorSchemePreference)
    }

    let legacyWith = bounds(Row { box(10).preferredColorScheme(.dark); box(11) })
    let legacyWithout = bounds(Row { box(10); box(11) })
    #expect(legacyWith.ids == legacyWithout.ids, "legacy: the scope must be transparent")
    #expect(legacyWith.preference == .dark)

    let proposalWith = bounds(HStack(spacing: 0) {
        Rectangle().frame(width: px(10), height: px(10)).preferredColorScheme(.dark)
        Rectangle().frame(width: px(11), height: px(10))
    })
    let proposalWithout = bounds(HStack(spacing: 0) {
        Rectangle().frame(width: px(10), height: px(10))
        Rectangle().frame(width: px(11), height: px(10))
    })
    #expect(proposalWith.ids == proposalWithout.ids, "proposal: the scope must be transparent")
    #expect(proposalWith.preference == .dark, "the proposal entry must record the preference too (OM-AI)")
}

// MARK: - 2.11–2.14: when and how it applies (CR-L, CR-Q)

/// A component holding one `@State`, for 2.11's `StateTable` arm.
private struct Counter: Component {
    @State var count = 0
    var content: some ElementGroup { box(14).background(dynamic) }
}

/// **2.11** (`CR-L` item 5, `CR-Q`). A root preference is in the first
/// presented frame: one frame drawn, and its scene's `.surface` is the dark
/// theme's. The first build is adopted, not discarded: the `@State` it seeded
/// is one table entry, and the window was asked once. Mutation: drop the
/// first-frame rebuild.
@MainActor
@Test func aRootPreferenceIsInTheFirstPresentedFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row {
            Row {
                box(11).background(.surface)
                Counter()
            }
            .preferredColorScheme(.dark)
        }
    }
    window.drawFrameIfNeeded()
    #expect(window.framesDrawn == 1)
    #expect(window.colorScheme == .dark)
    #expect(fill(window.lastScene, width: 11).map { close($0, Theme.dark.surface.toRgba()) } == true,
            "\(describe(window.lastScene))")
    #expect(fill(window.lastScene, width: 14).map { close($0, darkHalfRGBA) } == true, "\(describe(window.lastScene))")
    #expect(window.stateTable.count == 1, "one @State, one entry: \(window.stateTable.count)")
    #expect(platform.preferredColorSchemeRequests == [.dark])
    #expect(window.needsRedraw == false, "the second build settled the frame")
}

/// **2.12** (`CR-L` item 5). After the first frame, a preference flipped from
/// input applies on the next frame: that frame builds light and leaves the
/// window dirty, the one after builds dark, then the window is clean.
/// Mutation: never re-dirty on a changed preference.
@MainActor
@Test func aLaterPreferenceChangeAppliesOnTheNextFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let log = SchemeLog()
    let flag = Flag()
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { Row { SchemeReader(log: log) }.preferredColorScheme(flag.value) }
    }
    window.onInput = { _ in flag.value = .dark; return true }
    window.drawFrameIfNeeded()
    try #require(window.needsRedraw == false && log.reads == [.light])

    flip(platform)
    window.drawFrameIfNeeded()
    #expect(log.reads.last == .light, "the frame that collects the preference was built light")
    #expect(window.needsRedraw, "a changed preference re-dirties")
    window.drawFrameIfNeeded()
    #expect(log.reads.last == .dark)
    #expect(fills(window.lastScene, darkHalfRGBA), "\(describe(window.lastScene))")
    #expect(window.needsRedraw == false)
}

/// **2.13** (`CR-L` item 4, probe `P8b`). Clearing the preference returns to
/// the platform's appearance, and the platform is told `nil`. Mutation: keep
/// the last non-nil.
@MainActor
@Test func clearingThePreferenceReturnsToThePlatformsAppearance() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let flag = Flag()
    flag.value = .dark
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { Row { box(10).background(dynamic) }.preferredColorScheme(flag.value) }
    }
    window.onInput = { _ in flag.value = nil; return true }
    window.drawFrameIfNeeded()
    try #require(window.colorScheme == .dark)
    flip(platform)
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(platform.preferredColorSchemeRequests == [.dark, nil])
    #expect(window.colorScheme == .light)
    #expect(fills(window.lastScene, lightHalfRGBA), "\(describe(window.lastScene))")
}

/// **2.14** (`CR-L` item 4). The tree's preference wins over the window's, and
/// the window's over the platform's. Mutation: swap tree and window precedence.
@MainActor
@Test func theTreesPreferenceWinsOverTheWindowsAndTheWindowsOverThePlatform() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let flag = Flag()
    flag.value = .dark
    let (window, platform) = try makeFakeWindow(device: device, appearance: .dark) {
        Row { Row { box(10) }.preferredColorScheme(flag.value) }
    }
    window.preferredColorScheme = .light
    window.drawFrameIfNeeded()
    #expect(window.colorScheme == .dark, "the tree's .dark beats the window's .light")

    window.onInput = { _ in flag.value = nil; return true }
    flip(platform)
    window.drawFrameIfNeeded()
    window.drawFrameIfNeeded()
    #expect(window.colorScheme == .light, "with no tree preference the window's .light beats the platform's .dark")

    window.preferredColorScheme = nil
    #expect(window.needsRedraw)
    window.drawFrameIfNeeded()
    #expect(window.colorScheme == .dark, "with neither, the platform's")
}

// MARK: - 2.15–2.17, 2.22: themes and palette (CR-K, CR-N, CR-V)

/// **2.15** (`CR-K` item 1). The window's theme follows its variants, and a
/// direct `window.theme` write lasts until the next scheme change. Mutation:
/// `theme = Theme.forAppearance(…)`, ignoring the variants.
@MainActor
@Test func theWindowsThemeFollowsItsVariantsAndADirectWriteLastsUntilTheNextChange() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let custom = customTheme()
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { box(11).background(.surface) }
    }
    window.darkTheme = custom
    #expect(window.theme == .light, "a dark variant does not touch a light window's theme")
    platform.simulateAppearanceChange(to: .dark)
    #expect(window.theme == custom)
    window.drawFrameIfNeeded()
    #expect(fill(window.lastScene, width: 11).map { close($0, custom.surface.toRgba()) } == true)

    window.theme = .light
    window.drawFrameIfNeeded()
    #expect(fill(window.lastScene, width: 11).map { close($0, Theme.light.surface.toRgba()) } == true,
            "a direct write paints until the next scheme change")
    platform.simulateAppearanceChange(to: .light)
    platform.simulateAppearanceChange(to: .dark)
    #expect(window.theme == custom, "the next scheme change re-selects the variant")
}

/// **2.16** (`CR-L` item 4, `CR-N` item 4). `App`'s scheme and themes reach a
/// window before its first frame, and a later assignment re-themes the open
/// window. Mutation: assign after `openWindow`'s first draw.
@MainActor
@Test func appSchemeAndThemesReachEveryWindowBeforeItsFirstFrame() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let platform = FakePlatform(device: device)
    let app = App(platform: platform)
    app.darkTheme[Brand.self] = brandOverride
    app.preferredColorScheme = .dark
    let window = try app.openWindow(title: "scheme", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) {
        Row { box(10).background(Color(Brand.self)) }
    }
    #expect(window.framesDrawn == 1)
    #expect(window.colorScheme == .dark)
    #expect(fills(window.lastScene, brandOverrideRGBA), "\(describe(window.lastScene))")
    #expect(platform.openedWindows.first?.preferredColorSchemeRequests == [.dark])

    app.darkTheme[Brand.self] = brandSecondOverride
    #expect(window.needsRedraw, "assigning the app's variant re-themes an open window")
    window.drawFrameIfNeeded()
    #expect(fills(window.lastScene, brandSecondOverrideRGBA), "\(describe(window.lastScene))")

    app.lightTheme = customTheme()
    #expect(window.lightTheme == customTheme())
    app.preferredColorScheme = .light
    #expect(window.preferredColorScheme == .light)
}

/// **2.17** (`CR-N` item 3). A palette override on the window's active variant
/// repaints. Mutation: drop the variant → `theme` propagation.
@MainActor
@Test func aPaletteOverrideOnTheWindowsVariantRepaints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, _) = try makeFakeWindow(device: device, appearance: .dark) {
        Row { box(10).background(Color(Brand.self)) }
    }
    window.drawFrameIfNeeded()
    try #require(window.needsRedraw == false)
    window.darkTheme[Brand.self] = brandOverride
    #expect(window.needsRedraw)
    window.drawFrameIfNeeded()
    #expect(fills(window.lastScene, brandOverrideRGBA), "\(describe(window.lastScene))")
}

/// **2.22** (`CR-V` item 2). A scheme change repaints even when both variants
/// are the same theme, so the theme does not change: the dynamic colour still
/// flips. Mutation: `colorScheme`'s `didSet` only assigns `theme` (relying on
/// `theme`'s guard to dirty).
@MainActor
@Test func aSchemeChangeRepaintsEvenWhenBothVariantsAreTheSameTheme() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (window, platform) = try makeFakeWindow(device: device, appearance: .light) {
        Row { box(10).background(dynamic) }
    }
    window.lightTheme = .dark
    window.darkTheme = .dark
    window.drawFrameIfNeeded()
    try #require(window.needsRedraw == false)
    platform.simulateAppearanceChange(to: .dark)
    #expect(window.needsRedraw, "a scheme change must repaint though the theme did not change")
    window.drawFrameIfNeeded()
    #expect(fills(window.lastScene, darkHalfRGBA), "\(describe(window.lastScene))")
}
