import MetalUI
import MetalUIScene
import MetalUITesting
import Testing

// Spec §4.1 tests 1.18, 1.19, 1.22–1.24 (MG-12): a headless harness window runs
// the lifecycle drain exactly as a real window does, and opens in, follows and
// reports the colour scheme.

/// A box whose `onAppear` widens it from 10 to 30.
private struct HarnessPresenter: Component {
    @State var width: Float = 10
    var content: some ElementGroup {
        Box().frame(width: Pixels(width), height: Pixels(7)).background(.accent)
            .onAppear { width = 30 }
    }
}

/// 1.18 — an `onAppear` write is in the FIRST presented frame (`LC-E`, MG-12
/// item 2), one frame drawn. Mutation: `Window.drainLifecycle` returns at
/// once (in `Window.swift`, restored) — the harness runs the real drain.
@Test @MainActor func anOnAppearWriteIsInTheFirstFrame() throws {
    let window = try harnessWindow { VStack(spacing: 0) { HarnessPresenter() } }
    #expect(window.framesDrawn == 1)
    #expect(rects(window, height: 7).map { $0.bounds.size.width } == [30])
}

/// A box counting clicks, logging each change of the count.
private struct HarnessChangeCounter: Component {
    let log: HarnessLog
    @State var count = 0
    var content: some ElementGroup {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent)
            .onClick { count += 1 }
            .onChange(of: count) { old, new in log.add("\(old)→\(new)") }
    }
}

/// 1.19 — `onChange` runs after a click changes its value, in the click's
/// frame. Mutation: as 1.18.
@Test @MainActor func onChangeRunsAfterAClickChangesItsValue() throws {
    let log = HarnessLog()
    let window = try harnessWindow { VStack(spacing: 0) { HarnessChangeCounter(log: log) } }
    #expect(log.entries.isEmpty)
    window.click(at: pt(200, 150))
    #expect(log.entries == ["0→1"])
}

private let harnessLight = Color(red: 1, green: 0.9, blue: 0.8)
private let harnessDark = Color(red: 0.1, green: 0.1, blue: 0.4)

/// A palette key whose value differs by scheme.
private struct HarnessBrand: ThemeColorKey {
    static let defaultValue = Color(light: harnessLight, dark: harnessDark)
}

/// A presented rect's colour as (h, s, l, a).
private func hsla(_ rect: MUIRect) -> [Float] {
    [rect.background.h, rect.background.s, rect.background.l, rect.background.a]
}

/// The colours of the two 40-tall and 30-tall boxes `colors` draws.
@MainActor private func schemeColours(_ window: TestWindow) throws -> (adaptive: [Float], palette: [Float]) {
    let adaptive = try #require(rects(window, height: 40).first)
    let palette = try #require(rects(window, height: 30).first)
    return (hsla(adaptive), hsla(palette))
}

/// A `Color(light:dark:)` box 40 tall and a palette-key box 30 tall.
@MainActor private func schemeTree() -> some Element {
    VStack(spacing: 0) {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(Color(light: harnessLight, dark: harnessDark))
        Box().frame(width: Pixels(40), height: Pixels(30)).background(Color(HarnessBrand.self))
    }
}

/// The same two boxes in literal colours.
@MainActor private func literalTree(_ color: Color) -> some Element {
    VStack(spacing: 0) {
        Box().frame(width: Pixels(40), height: Pixels(40)).background(color)
        Box().frame(width: Pixels(40), height: Pixels(30)).background(color)
    }
}

/// 1.22 — a window opened `.dark` resolves its first frame dark (MG-12 item 1):
/// the adaptive colour and the palette key equal the dark literal drawn in a
/// light window, and differ from the light window's resolution. Mutation:
/// `openWindow` ignores `colorScheme`.
@Test @MainActor func aDarkWindowResolvesItsFirstFrameDark() throws {
    let dark = try harnessWindow(colorScheme: .dark) { schemeTree() }
    let light = try harnessWindow { schemeTree() }
    let darkLiteral = try harnessWindow { literalTree(harnessDark) }
    #expect(dark.framesDrawn == 1)
    let (adaptive, palette) = try schemeColours(dark)
    let expected = try schemeColours(darkLiteral)
    #expect(adaptive == expected.adaptive, "Color(light:dark:) resolved dark in frame 1")
    #expect(palette == expected.palette, "the palette key resolved dark in frame 1")
    #expect(adaptive != (try schemeColours(light)).adaptive, "the separating arm: light differs")
}

/// 1.23 — `setAppearance(.dark)` is a system switch: the next frame resolves
/// as a window opened dark does. Mutation: `simulateAppearanceChange` skips
/// the callback.
@Test @MainActor func setAppearanceSwitchesTheSchemeLikeTheSystem() throws {
    let window = try harnessWindow { schemeTree() }
    let openedDark = try harnessWindow(colorScheme: .dark) { schemeTree() }
    let before = try schemeColours(window)
    window.setAppearance(.dark)
    let after = try schemeColours(window)
    let target = try schemeColours(openedDark)
    #expect(after.adaptive == target.adaptive && after.palette == target.palette)
    #expect(before.adaptive != after.adaptive)
}

/// 1.24 — a `.preferredColorScheme(.dark)` in the tree reaches the platform's
/// record once (`CR-M`). Mutation: the record not appended.
@Test @MainActor func aPreferredColorSchemeReachesThePlatformRecord() throws {
    let window = try harnessWindow {
        VStack(spacing: 0) {
            Box().frame(width: Pixels(40), height: Pixels(40)).background(.accent).preferredColorScheme(.dark)
        }
    }
    #expect(window.platformWindow.preferredColorSchemeRequests == [ColorScheme.dark] as [ColorScheme?])
}
