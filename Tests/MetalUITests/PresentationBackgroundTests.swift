import Testing
import Foundation
import Metal
import MetalUICore
import MetalUILayout
import MetalUIPlatform
import MetalUIScene
import MetalUITesting
@testable import MetalUI

// Presentation extras, lane 1 (`BG-A`…`BG-F`, record 144; spec
// `docs/superpowers/specs/2026-10-22-presentation-extras-design.md`, tests 1-14):
// `.presentationBackground` on a popover's panel. SwiftUI's answers are arms of
// `docs/probes/swiftui-presentation-extras.swift` (`B1`-`B9`); the rest is ruled.
//
// A popover is a real `Window` over a 400 x 400 `FakePlatformWindow`, drawn until
// clean (nothing sleeps). The 100 x 50 content gives a 124 x 74 panel at (138, 108),
// as in `PopoverTests`.

// MARK: - Fixtures

@MainActor
private final class BGLog {
    var shown = true
    var entries: [String] = []
}

private func px(_ v: Float) -> Pixels { Pixels(v) }

@MainActor private func shownBinding(_ log: BGLog) -> Binding<Bool> {
    Binding(get: { log.shown }, set: { log.shown = $0; log.entries.append("shown=\($0)") })
}

/// A 100 x 50 popover content: the panel around it is 124 x 74.
@MainActor private func content100x50() -> ModifiedElement<Box<EmptyGroup>> {
    Box().frame(width: px(100), height: px(50))
}

/// `anchor` at (180, 190) in a 400 x 400 root.
@MainActor private func at<A: Element>(_ anchor: A) -> some Element {
    Column {
        Box().frame(width: px(1), height: px(190))
        Row {
            Box().frame(width: px(180), height: px(1))
            anchor
            Box().frame(width: px(180), height: px(1))
        }
        Box().frame(width: px(1), height: px(190))
    }
}

/// The 40 x 20 anchor with a popover over `content`.
@MainActor private func declarer<P: ElementGroup>(_ log: BGLog, @ElementBuilder _ content: @escaping @MainActor () -> P) -> some Element {
    at(Box().frame(width: px(40), height: px(20)).popover(isPresented: shownBinding(log)) { content() })
}

@MainActor
private func bgWindow<Root: Element>(_ content: @escaping @MainActor () -> Root) throws -> (Window, FakePlatformWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    let (window, platform) = try makeFakeWindow(device: device, size: 400, content: content)
    window.recordsElementBounds = true
    window.drawFrameIfNeeded()
    drawUntilClean(window)
    return (window, platform)
}

@MainActor private func drawUntilClean(_ window: Window) {
    for _ in 0..<6 where window.needsRedraw { window.drawFrameIfNeeded() }
}

@MainActor private func redraw(_ window: Window) {
    window.setNeedsRedraw()
    drawUntilClean(window)
}

private let panelBounds: [Float] = [138, 108, 124, 74]

private func xywh(_ b: MUIBounds) -> [Float] { [b.origin.x, b.origin.y, b.size.width, b.size.height] }

/// The rects of the popover's layer (the highest), in draw order.
@MainActor private func popoverRects(_ window: Window) throws -> [MUIRect] {
    let scene = window.lastScene
    let layer = try #require(scene.highestLayer)
    try #require(layer > 0, "the popover is on a higher layer")
    return scene.rects.indices.filter { scene.layer(of: .rect, at: $0) == layer }.map { scene.rects[$0] }
}

/// The popover's panel rect: the one at the chrome's bounds.
@MainActor private func panel(_ window: Window) throws -> MUIRect {
    try #require(try popoverRects(window).first { xywh($0.bounds) == panelBounds }, "the panel rect")
}

@MainActor private func popoverImages(_ window: Window) throws -> [MUIImage] {
    let scene = window.lastScene
    let layer = try #require(scene.highestLayer)
    return scene.images.indices.filter { scene.layer(of: .image, at: $0) == layer }.map { scene.images[$0] }
}

private func same(_ a: MUIHsla, _ b: Hsla) -> Bool { a.h == b.h && a.s == b.s && a.l == b.l && a.a == b.a }

private let blue = Color(red: 0.2, green: 0.4, blue: 0.8)
private let orange = Color(red: 0.9, green: 0.5, blue: 0.1)

@MainActor private func resolved(_ color: Color, _ window: Window, _ scheme: ColorScheme = .light) -> Hsla {
    color.resolved(theme: scheme == .dark ? window.darkTheme : window.lightTheme, scheme: scheme)
}

// MARK: - 1-4: the fill, the winner, the declarer, the chrome

/// **1** (`BG-C`, probe `B2`). A popover whose content reports a colour fills its panel with it and not with
/// `.surface`. Mutation: paint ignores the slot (fills `theme[.surface]`).
@MainActor
@Test func aPopoverPanelTakesThePresentationBackgroundColourAsItsFill() throws {
    let log = BGLog()
    let (window, _) = try bgWindow { declarer(log) { content100x50().presentationBackground(blue) } }
    let rect = try panel(window)
    #expect(same(rect.background, resolved(blue, window)), "the colour: \(rect.background)")
    #expect(!same(rect.background, window.theme[.surface]), "and not the surface")
    withExtendedLifetime(window) {}
}

/// **2** (`BG-B`, probe `B7`). Two reports: the innermost wins. Mutation: the slot is overwritten instead of kept.
@MainActor
@Test func theInnermostPresentationBackgroundWins() throws {
    let log = BGLog()
    let (window, _) = try bgWindow {
        declarer(log) { content100x50().presentationBackground(blue).presentationBackground(orange) }
    }
    let rect = try panel(window)
    #expect(same(rect.background, resolved(blue, window)), "the inner: \(rect.background)")
    withExtendedLifetime(window) {}
}

/// **3** (`BG-B`, probe `B4`). The modifier written on the declarer, outside the popover's content, changes nothing.
/// Mutation: a scope outside a presentation bracket reports into the slot the chrome reads.
@MainActor
@Test func aPresentationBackgroundOutsideThePopoverContentChangesNothing() throws {
    let log = BGLog()
    let (window, _) = try bgWindow {
        Row { declarer(log) { content100x50() }.presentationBackground(blue) }
    }
    let rect = try panel(window)
    #expect(same(rect.background, window.theme[.surface]), "the surface: \(rect.background)")
    withExtendedLifetime(window) {}
}

/// **4** (`BG-C`, `OV-C`, probe `B1`/`B2`). The border, the radius and the shadow stay under a colour fill.
/// Mutation: the border is skipped when a spec is present.
@MainActor
@Test func thePanelKeepsItsBorderRadiusAndShadowUnderAPresentationBackground() throws {
    let log = BGLog()
    let (window, _) = try bgWindow { declarer(log) { content100x50().presentationBackground(blue) } }
    let rect = try panel(window)
    #expect(rect.borderWidths.top == 1 && rect.borderWidths.left == 1, "the 1-pt border")
    #expect(same(rect.borderColor, window.theme[.separator]), "the separator border")
    #expect([rect.cornerRadii.topLeft, rect.cornerRadii.bottomRight] == [10, 10], "radius 10")
    #expect(try popoverImages(window).count == 1, "the shadow image")
    withExtendedLifetime(window) {}
}

// MARK: - 5-7: material, gradient, token

/// **5** (`BG-C`, `MT-`). A material panel goes through `Frame.fillMaterial`: one backdrop record at the panel with its
/// radii, the border its own stroke-only rect; under Reduce Transparency an opaque rect and no backdrop record.
/// Mutation: call `fillBackdrop` directly.
@MainActor
@Test func aMaterialPresentationBackgroundGoesThroughFillMaterial() throws {
    for reduce in [false, true] {
        let log = BGLog()
        let (window, _) = try bgWindow {
            Row {
                declarer(log) { content100x50().presentationBackground(Material.regularMaterial) }
                    .environment(\.accessibilityReduceTransparency, reduce)
            }
        }
        let scene = window.lastScene
        let rects = try popoverRects(window)
        let border = try #require(rects.first { xywh($0.bounds) == panelBounds && $0.borderWidths.top == 1 }, "the border rect, reduce \(reduce)")
        #expect(border.background.a == 0, "the border rect is stroke-only: \(border.background)")
        if reduce {
            #expect(scene.backdrops.isEmpty, "no backdrop record under Reduce Transparency")
            #expect(rects.contains { xywh($0.bounds) == panelBounds && $0.background.a == 1 }, "an opaque panel rect")
        } else {
            let backdrop = try #require(scene.backdrops.first, "one backdrop record")
            #expect(scene.backdrops.count == 1)
            #expect(xywh(backdrop.bounds) == panelBounds, "at the panel")
            #expect([backdrop.cornerRadii.topLeft, backdrop.cornerRadii.bottomRight] == [10, 10], "with its radii")
        }
        withExtendedLifetime(window) {}
    }
}

/// **6** (`BG-C`, `LK-J`). A gradient panel is one gradient image over the panel under the content (a strip, so the
/// image is the panel's rect), rastered once and then served from the cache. Mutation: the gradient is not painted.
@MainActor
@Test func aGradientPresentationBackgroundPaintsAGradientImageUnderTheContent() throws {
    let log = BGLog()
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)
    let (window, _) = try bgWindow { declarer(log) { content100x50().presentationBackground(gradient) } }
    let images = try popoverImages(window)
    #expect(images.count == 2, "the shadow and the gradient: \(images.count)")
    #expect(images.contains { xywh($0.bounds) == panelBounds }, "the gradient over the panel")
    redraw(window)
    #expect(window.animationStore.rasters.lastTexturesMade == 0, "an equal frame rasters nothing")
    withExtendedLifetime(window) {}
}

/// **7** (`CR-`, `BG-C`). A token follows the scheme: resolved at paint, not at build. Two spellings, because
/// `.accent` alone picks `Color.accent` (the `ColorToken` twin is disfavoured): the explicit `ColorToken` value
/// reaches the twin. Mutation: the twin resolves its token once against the light theme.
@MainActor
@Test func aColourTokenPresentationBackgroundFollowsTheColourScheme() throws {
    let token: ColorToken = .accent
    for scheme in [ColorScheme.light, .dark] {
        for twin in [false, true] {
            let log = BGLog()
            let (window, _) = try bgWindow {
                Row {
                    declarer(log) {
                        if twin {
                            content100x50().presentationBackground(token)
                        } else {
                            content100x50().presentationBackground(.accent)
                        }
                    }
                    .environment(\.colorScheme, scheme)
                }
            }
            let rect = try panel(window)
            let want = (scheme == .dark ? window.darkTheme : window.lightTheme)[.accent]
            #expect(same(rect.background, want), "\(scheme), twin \(twin): \(rect.background)")
            withExtendedLifetime(window) {}
        }
    }
    #expect(Theme.light[.accent] != Theme.dark[.accent], "the instrument: the two schemes differ")
}

// MARK: - 8-9: the content spelling

/// **8** (`BG-D`, `BG-E`, probes `B3`, `B8`). The content spelling is proposed the panel's size and placed by its
/// alignment: a flexible colour fills the panel, a 30-pt-wide one sits at the leading edge and the panel is the same size
/// with and without. A 300-pt one is cut to the panel and does not grow it. Mutations: ignore `alignment`; let the
/// background's size answer the layout.
@MainActor
@Test func aContentPresentationBackgroundIsProposedThePanelAndPlacedByItsAlignment() throws {
    func rects<P: ElementGroup>(_ content: @escaping @MainActor () -> P) throws -> ([MUIRect], Window) {
        let log = BGLog()
        let (window, _) = try bgWindow { declarer(log, content) }
        return (try popoverRects(window), window)
    }
    let (plain, w0) = try rects { content100x50() }
    #expect(plain.contains { xywh($0.bounds) == panelBounds }, "the plain panel")
    let (fill, w1) = try rects { content100x50().presentationBackground { Color.red } }
    #expect(fill.contains { xywh($0.bounds) == panelBounds && $0.background.a == 1 && $0.borderWidths.top == 0 },
            "B3: a flexible colour fills the panel: \(fill.map { xywh($0.bounds) })")
    let (narrow, w2) = try rects {
        content100x50().presentationBackground(alignment: .leading) { Color.red.frame(width: px(30)) }
    }
    #expect(narrow.contains { xywh($0.bounds) == [138, 108, 30, 74] }, "B8: leading, 30 wide: \(narrow.map { xywh($0.bounds) })")
    #expect(narrow.contains { xywh($0.bounds) == panelBounds && $0.borderWidths.top == 1 }, "the panel is the same size")
    let (wide, w3) = try rects {
        content100x50().presentationBackground { Color.red.frame(width: px(300), height: px(300)) }
    }
    #expect(wide.contains { xywh($0.bounds) == panelBounds && $0.borderWidths.top == 1 }, "an oversized background grows nothing")
    let cut = try #require(wide.first { $0.background.a == 1 && $0.borderWidths.top == 0 }, "the oversized colour")
    #expect(xywh(cut.contentMask) == panelBounds, "cut to the panel: \(xywh(cut.contentMask))")
    withExtendedLifetime((w0, w1, w2, w3)) {}
}

/// **9** (`BG-E`, `ID-R`, `ID-C`). The content spelling's node is the named child `$presentationbackground`; its
/// `@State` is reset when the popover closes and the name is noted. Mutation: drop the `noteNamed` call.
@MainActor
@Test func theContentBackgroundNameIsReturnedFresh() throws {
    let log0 = BGLog()
    let (window0, _) = try bgWindow { declarer(log0) { content100x50() } }
    let withoutBackground = window0.stateTable.count
    log0.shown = false
    redraw(window0)
    let closed = window0.stateTable.count

    let log = BGLog()
    let (window, _) = try bgWindow { declarer(log) { content100x50().presentationBackground { BGStateful() } } }
    let named = window.lastElementBounds.keys.filter { id in
        if case .named(let name) = id.component { return name == ElementID("$presentationbackground") }
        return false
    }
    #expect(named.count == 1, "one named background node: \(named)")
    #expect(window.stateTable.count > withoutBackground, "the background's state exists while open")
    for shown in [false, true, false] {
        log.shown = shown
        redraw(window)
    }
    #expect(window.stateTable.count == closed, "dismissed: the background's state is gone")
    withExtendedLifetime((window0, window)) {}
}

private struct BGStateful: Component {
    @State private var count = 0
    var content: some ElementGroup {
        Color.red.frame(width: px(10), height: px(10)).onClick { count += 1 }
    }
}

// MARK: - 10-13: overlays, retention, hit testing, window preferences

/// **10** (`BG-A`). An `anchoredOverlay` has no panel: the modifier is accepted and paints nothing, the scene equal to
/// the same overlay without it.
@MainActor
@Test func aPresentationBackgroundInAnAnchoredOverlayPaintsNothing() throws {
    func scene(_ background: Bool) throws -> [[Float]] {
        let log = BGLog()
        let (window, _) = try bgWindow {
            Box().frame(width: px(400), height: px(400))
                .anchoredOverlay(isPresented: shownBinding(log), at: Point(x: px(120), y: px(80))) {
                    if background {
                        content100x50().background(.accent).presentationBackground(blue)
                    } else {
                        content100x50().background(.accent)
                    }
                }
        }
        defer { withExtendedLifetime(window) {} }
        return try popoverRects(window).map { xywh($0.bounds) + [$0.background.h, $0.background.l, $0.background.a] }
    }
    #expect(try scene(true) == scene(false))
}

/// **11** (`BG-F`). A stray `.presentationBackground` in an `.equatable()` occurrence does not change its retained work.
/// Mutation: report into the main slot with a build-audit count.
@MainActor
@Test func aStrayPresentationBackgroundDoesNotChangeARetainedOccurrence() throws {
    func work(_ stray: Bool) throws -> [Int] {
        let w = try TestWindow(size: Size(width: px(200), height: px(100))) {
            VStack(spacing: 0) { BGOccurrence(stray: stray).equatable() }
        }
        for _ in 0..<8 { w.window.setNeedsRedraw(); w.tick() }
        let f = w.lastFrameWork
        return [f.retainedGrafts, f.retainedPrepaintHits, f.elementRequests, f.retainedGraftIneligible, f.retainedPrepaintIneligible]
    }
    let with = try work(true), without = try work(false)
    #expect(with == without, "work with \(with), without \(without)")
    #expect(with[0] == 1, "the occurrence still grafts: \(with)")
}

private struct BGOccurrence: Component, @MainActor Equatable {
    let stray: Bool
    static func == (l: BGOccurrence, r: BGOccurrence) -> Bool { l.stray == r.stray }
    var content: some ElementGroup {
        if stray {
            Box().frame(width: px(40), height: px(20)).background(.accent).presentationBackground(blue)
        } else {
            Box().frame(width: px(40), height: px(20)).background(.accent)
        }
    }
}

/// **12** (`BG-F`). A popover with a background hits and dismisses as before: the same hitboxes, an outside press
/// dismisses, a press on the panel does not. Mutation: an extra hitbox for the background node.
@MainActor
@Test func aPopoverWithAPresentationBackgroundHitsAndDismissesAsBefore() throws {
    func hitboxes(_ background: Bool) throws -> ([[Float]], BGLog, FakePlatformWindow, Window) {
        let log = BGLog()
        let (window, platform) = try bgWindow {
            declarer(log) {
                if background {
                    content100x50().presentationBackground { Color.red }
                } else {
                    content100x50()
                }
            }
        }
        let boxes = window.lastHitboxes.map { [$0.bounds.origin.x.value, $0.bounds.origin.y.value,
                                              $0.bounds.size.width.value, $0.bounds.size.height.value] }
        return (boxes, log, platform, window)
    }
    let (plain, _, _, w0) = try hitboxes(false)
    let (with, log, platform, window) = try hitboxes(true)
    #expect(with == plain, "hitboxes equal: \(with) vs \(plain)")
    platform.simulateInput(.mouseDown(MouseEvent(position: Point(x: px(200), y: px(145)))))
    platform.simulateInput(.mouseUp(MouseEvent(position: Point(x: px(200), y: px(145)))))
    #expect(log.entries.isEmpty, "a press on the panel does not dismiss: \(log.entries)")
    platform.simulateInput(.mouseDown(MouseEvent(position: Point(x: px(20), y: px(20)))))
    #expect(log.entries == ["shown=false"], "an outside press dismisses: \(log.entries)")
    withExtendedLifetime((w0, window)) {}
}

/// **13** (`BG-B`). A background reaches none of the window's preferences: the colour scheme request, the title and the
/// toolbar are those of the same tree without it.
@MainActor
@Test func aPresentationBackgroundDoesNotReachTheWindowsPreferences() throws {
    let log = BGLog()
    let (window, platform) = try bgWindow {
        Row { declarer(log) { content100x50().presentationBackground(blue) } }
    }
    let log0 = BGLog()
    let (plain, platform0) = try bgWindow { Row { declarer(log0) { content100x50() } } }
    #expect(platform.preferredColorSchemeRequests == platform0.preferredColorSchemeRequests)
    #expect(platform.titleWrites == platform0.titleWrites)
    withExtendedLifetime((window, plain)) {}
}
