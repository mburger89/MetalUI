import Foundation
@testable import MetalUI
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
import Observation
import Testing

// C14-n (`TH-`): a theme reaches a retained decision through exactly one value, `EnvironmentFingerprint.theme` (`TH-A`). Eight
// `.equatable()` panels painting a surface token, a text token, a `ThemeColorKey` palette colour and a `Color(light:dark:)` dynamic colour;
// a theme change (a `.theme(_)` scope, a `Window.lightTheme` assignment at an unchanged scheme, a palette override, a scheme switch) must
// miss every panel naming `environment.theme` and the painted rect colours must be the new theme's. Colours are read from the scene's
// rects, the whole frame is compared to a retention-off twin. Counts and values, never time.
//
// **Red before the change** (mutation M1, `retainedFingerprint`'s `theme:` replaced by `Theme.light`; record 149): arms 1, 2, 5, 6.

struct THAccentKey: ThemeColorKey {
    static let defaultValue = Color(light: Color(red: 0.9, green: 0.1, blue: 0.1), dark: Color(red: 0.1, green: 0.1, blue: 0.9))
}
private let thDynamic = Color(light: Color(red: 0.31, green: 0.62, blue: 0.93), dark: Color(red: 0.93, green: 0.62, blue: 0.31))

@MainActor func thThemeB() -> Theme {
    var t = Theme.light
    t.surface = .rgb(0x102030); t.textPrimary = .rgb(0x405060); t.accent = .rgb(0x708090)
    return t
}
@MainActor func thPaletteTheme() -> Theme {
    var t = Theme.light
    t[THAccentKey.self] = Color(red: 0.2, green: 0.8, blue: 0.4)
    return t
}

@Observable @MainActor final class THThemeBox { var theme: Theme = .light }

struct THNode: Component, @MainActor Equatable {
    let index: Int
    let model: DMModel
    var content: some ElementGroup {
        let shown = model.params[index].radius
        VStack(alignment: .leading, spacing: 2) {
            Rectangle().fill(Color(.surface)).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(Color(.textPrimary)).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(Color(THAccentKey.self)).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(thDynamic).frame(width: Pixels(60), height: Pixels(8))
            Rectangle().fill(Color(red: 0.2 + shown * 0.1, green: 0.4, blue: 0.7)).frame(width: Pixels(60), height: Pixels(8))
        }
    }
    // The theme is deliberately not part of the value: it enters from outside the occurrence.
    static func == (l: THNode, r: THNode) -> Bool { l.index == r.index && l.model === r.model }
}

struct THParent: Component {
    let model: DMModel
    let box: THThemeBox
    let scoped: Bool
    var content: some ElementGroup {
        let theme = box.theme
        VStack(alignment: .leading, spacing: 4) {
            Rectangle().fill(Color(red: 0.5, green: 0.5, blue: 0.5)).frame(width: Pixels(880), height: Pixels(20))
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in model.params[2].radius = 1 + Double(value.translation.width.value) / 100 })
                .id("strip")
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(0..<8), id: \.self) { i in
                    if scoped {
                        THNode(index: i, model: model).equatable().theme(theme)
                    } else {
                        THNode(index: i, model: model).equatable()
                    }
                }
            }
        }
    }
}

@MainActor func thWindow(scoped: Bool, retain: Bool = true, preset: (TestWindow) -> Void = { _ in }) throws -> (TestWindow, THThemeBox) {
    let model = DMModel()
    let box = THThemeBox()
    let options = HeadlessPlatformWindow.Options(appearance: .light, scaleFactor: 2, accessibilityClientActive: true)
    let window = try TestWindow(size: sz(900, 160), colorScheme: .light, scaleFactor: 2, options: options, textSystem: harnessTextSystem) {
        VStack(spacing: 0) { THParent(model: model, box: box, scoped: scoped) }
    }
    window.window.testingRetainedGraft = true
    window.window.testingRetainedSubtrees = retain
    preset(window)
    for _ in 0..<4 { window.window.setNeedsRedraw(); window.tick() }
    return (window, box)
}

enum THChange: String, Sendable, CaseIterable {
    case scope, windowTheme, palette, schemeDifferent, schemeSame, equalRebuild
    var scoped: Bool { self == .scope || self == .equalRebuild }
}

@MainActor func thPreset(_ change: THChange) -> (TestWindow) -> Void {
    { w in
        if change == .schemeSame { w.window.lightTheme = thThemeB(); w.window.darkTheme = thThemeB() }
    }
}

@MainActor func thApply(_ change: THChange, _ w: TestWindow, _ box: THThemeBox) {
    switch change {
    case .scope: box.theme = thThemeB()
    case .windowTheme: w.window.lightTheme = thThemeB()
    case .palette: w.window.lightTheme = thPaletteTheme()
    case .schemeDifferent, .schemeSame: w.setAppearance(.dark)
    case .equalRebuild: box.theme = Theme.light
    }
    w.window.setNeedsRedraw(); w.tick()
}

@MainActor func thCount(_ window: TestWindow, _ c: Hsla) -> Int {
    window.scene.rects.filter { r in
        abs(r.background.h - c.h) < 1e-4 && abs(r.background.s - c.s) < 1e-4 && abs(r.background.l - c.l) < 1e-4 && abs(r.background.a - c.a) < 1e-4
    }.count
}

@MainActor func thResolved(_ color: Color, _ theme: Theme, _ scheme: ColorScheme) -> Hsla { color.resolved(theme: theme, scheme: scheme) }

struct THResult {
    var reasons: Set<String> = [], paintReasons: Set<String> = []
    var missed = 0
    var diffs: [String] = [], settledDiffs: [String] = []
    var settled = ""
    var on: TestWindow
}

/// Applies `change` to a retaining window and a retention-off twin, reading the trace of the first.
@MainActor func thRun(_ change: THChange) throws -> THResult {
    let (on, onBox) = try thWindow(scoped: change.scoped, preset: thPreset(change))
    let (off, offBox) = try thWindow(scoped: change.scoped, retain: false, preset: thPreset(change))
    var result = THResult(on: on)
    let lines = collectTrace {
        on.resetFrameWork()
        thApply(change, on, onBox)
        result.missed = on.frameWork.reduce(0) { $0 + $1.retainedMisses }
    }
    thApply(change, off, offBox)
    result.reasons = Set(lines.compactMap(traceReasons).flatMap { $0 })
    result.paintReasons = Set(lines.filter { $0.hasPrefix("retained paint miss") }.compactMap(traceReasons).flatMap { $0 })
    result.diffs = try RPSnapshot(on).differences(from: RPSnapshot(off))
    var after: [String] = []
    for _ in 0..<3 {
        on.resetFrameWork()
        on.window.setNeedsRedraw(); on.tick()
        off.window.setNeedsRedraw(); off.tick()
        after.append(on.frameWork.map { "h\($0.retainedHits) m\($0.retainedMisses)" }.joined(separator: ","))
    }
    result.settled = after.last ?? ""
    result.settledDiffs = try RPSnapshot(on).differences(from: RPSnapshot(off))
    return result
}

@MainActor func thExpectRepainted(_ r: THResult, theme: Theme, scheme: ColorScheme = .light, old: Theme = .light, _ label: String) {
    #expect(r.reasons.contains { $0.contains("environment.theme") }, "\(label): \(r.reasons.sorted())")
    #expect(r.missed >= 8, "\(label): every panel misses: \(r.missed)")
    #expect(r.diffs.isEmpty, "\(label): frame equals the twin: \(r.diffs)")
    #expect(r.settled == "h8 m0", "\(label): settles: \(r.settled)")
    #expect(r.settledDiffs.isEmpty, "\(label): \(r.settledDiffs)")
    for (color, name) in [(Color(.surface), "surface"), (Color(.textPrimary), "textPrimary"), (Color(THAccentKey.self), "palette")] {
        let want = thResolved(color, theme, scheme)
        #expect(thCount(r.on, want) >= 8, "\(label): \(name) painted in the new theme (\(thCount(r.on, want)))")
    }
    if theme[.surface] != old[.surface] {
        #expect(thCount(r.on, thResolved(Color(.surface), old, scheme)) == 0, "\(label): no stale surface")
    }
}

@Suite(.serialized) @MainActor
struct RetainedThemeTests {
    /// Arm 1: `.theme(_)` flipped between frames at a fixed scheme.
    @Test func aThemeScopeChangeMissesEveryPanelAndRepaints() throws {
        thExpectRepainted(try thRun(.scope), theme: thThemeB(), "scope")
    }

    /// Arm 2, the separating arm (`TH-B`): the scheme does not move, only the window's theme.
    @Test func aWindowThemeAssignmentAtAnUnchangedSchemeMissesAndRepaints() throws {
        thExpectRepainted(try thRun(.windowTheme), theme: thThemeB(), "windowTheme")
    }

    /// Arm 3: a scheme switch with two different themes changes both fields.
    @Test func aSchemeSwitchWithTwoDifferentThemesMissesNamingBoth() throws {
        let r = try thRun(.schemeDifferent)
        #expect(r.reasons.contains { $0.contains("colorScheme") }, "\(r.reasons.sorted())")
        thExpectRepainted(r, theme: .dark, scheme: .dark, "schemeDifferent")
    }

    /// Arm 3b: one theme in both variants, the scheme alone moves: the miss is the scheme's and the dynamic colour flips.
    @Test func aSchemeSwitchWithTheSameThemeStillMissesOnTheScheme() throws {
        let r = try thRun(.schemeSame)
        #expect(r.reasons.contains { $0.contains("colorScheme") }, "\(r.reasons.sorted())")
        #expect(!r.reasons.contains { $0.contains("environment.theme") }, "the theme is equal: \(r.reasons.sorted())")
        #expect(r.missed >= 8)
        #expect(r.diffs.isEmpty, "\(r.diffs)")
        #expect(thCount(r.on, thResolved(thDynamic, thThemeB(), .dark)) >= 8, "the dynamic colour is the dark one")
        #expect(thCount(r.on, thResolved(thDynamic, thThemeB(), .light)) == 0, "no stale light dynamic colour")
        #expect(r.settled == "h8 m0", Comment(rawValue: r.settled))
    }

    /// Arm 4: an equal theme rebuilt every frame is not a change.
    @Test func anEqualThemeRebuiltEveryFrameHits() throws {
        let (w, box) = try thWindow(scoped: true)
        var frames: [FrameWork] = []
        let lines = collectTrace {
            let strip = try! w.frame(ofID: "strip")
            let y = strip.origin.y.value + strip.size.height.value / 2
            box.theme = Theme.light
            w.resetFrameWork()
            w.drag(from: pt(strip.origin.x.value + 20, y), to: pt(strip.origin.x.value + 320, y), steps: 6)
            frames = w.frameWork
        }
        let reasons = Set(lines.compactMap(traceReasons).flatMap { $0 })
        #expect(!reasons.contains { $0.contains("environment") }, "\(reasons.sorted())")
        let drag = frames.dropLast()
        #expect(!drag.isEmpty && drag.allSatisfy { $0.retainedMisses == 1 && $0.retainedHits == 7 },
                "\(frames.map { "h\($0.retainedHits) m\($0.retainedMisses)" })")
        // Also at the change step itself: an equal assignment misses nothing.
        w.resetFrameWork()
        box.theme = Theme.light
        w.window.setNeedsRedraw(); w.tick()
        #expect(w.frameWork.allSatisfy { $0.retainedMisses == 0 }, "\(w.frameWork.map { "h\($0.retainedHits) m\($0.retainedMisses)" })")
    }

    /// Arm 5: only a palette override differs; `Theme`'s equality holds the palette, the built-in tokens are unchanged.
    @Test func aThemePaletteOverrideChangeMisses() throws {
        let r = try thRun(.palette)
        let want = thResolved(Color(THAccentKey.self), thPaletteTheme(), .light)
        #expect(r.reasons.contains { $0.contains("environment.theme") }, "\(r.reasons.sorted())")
        #expect(r.missed >= 8, "\(r.missed)")
        #expect(r.diffs.isEmpty, "\(r.diffs)")
        #expect(thCount(r.on, want) >= 8, "the palette colour is the override: \(thCount(r.on, want))")
        #expect(thCount(r.on, thResolved(Color(THAccentKey.self), .light, .light)) == 0, "no stale palette colour")
        #expect(r.settled == "h8 m0", Comment(rawValue: r.settled))
    }

    /// Arm 6 (`TH-C`): the paint decision itself names the theme; it is the paint decision, not the graft, that protects a colour.
    @Test func aThemeChangeIsNotCoveredByAnotherConjunct() throws {
        let r = try thRun(.windowTheme)
        #expect(r.paintReasons.contains { $0.contains("environment.theme") }, "paint decision: \(r.paintReasons.sorted())")
        #expect(r.diffs.isEmpty, "\(r.diffs)")
        #expect(thCount(r.on, thResolved(Color(.surface), thThemeB(), .light)) >= 8)
    }

    /// Arm 7 (`TH-C`): a graft that survives a theme change is sound, a build never reads a theme: the frame equals the twin's.
    @Test func aGraftedOccurrenceUnderAThemeChangeIsRebuiltOrEqual() throws {
        for change in [THChange.windowTheme, .scope] {
            let (on, onBox) = try thWindow(scoped: change.scoped)
            let (off, offBox) = try thWindow(scoped: change.scoped, retain: false)
            on.resetFrameWork()
            thApply(change, on, onBox)
            thApply(change, off, offBox)
            let diffs = try RPSnapshot(on).differences(from: RPSnapshot(off))
            #expect(diffs.isEmpty, "\(change): \(diffs)")
            #expect(on.frameWork.allSatisfy { $0.retainedMisses >= 8 || $0.retainedHits == 0 }, "\(change)")
        }
    }
}

/// The child's scenario: arms 1 and 2 against a twin, exiting nonzero on a stale colour (the verify trap is the other way out).
@MainActor func thVerifyScenario() -> Int32 {
    do {
        for change in [THChange.scope, .windowTheme] {
            let r = try thRun(change)
            guard r.diffs.isEmpty, r.settledDiffs.isEmpty else { return 2 }
            guard thCount(r.on, thResolved(Color(.surface), thThemeB(), .light)) >= 8 else { return 4 }
        }
        return 0
    } catch { return 3 }
}

/// Arm 8 (`TH-D`): arms 1 and 2 in a verify-mode child; with M1 applied by hand the child traps naming the paint channel.
@Test @MainActor
func theVerifySwitchSeesAThemeChange() async {
    await #expect(processExitsWith: .success) {
        setTestEnvironment("METALUI_VERIFY_RETAINED", "1")
        let code = await MainActor.run { thVerifyScenario() }
        exit(code)
    }
}
