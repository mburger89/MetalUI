import Testing
import Foundation
import MetalUICore
import MetalUIPlatform
@testable import MetalUI

// The window's container background (rulings `WB-A`...`WB-H`, record 285). Headless over `FakePlatform`:
// what `Window` asks the platform for, what it paints when the platform cannot, and that a window that never
// asks does nothing. The AppKit conformer is in `AppKitContainerBackgroundTests.swift`.

private func px(_ v: Float) -> Pixels { Pixels(v) }

@Observable @MainActor private final class BackdropModel {
    var mode = 0
}

@MainActor private func box() -> some Element { Box().frame(width: px(10), height: px(10)) }

@MainActor private func openBackdropWindow<E: Element>(_ model: BackdropModel, honoured: Bool = true,
                                                      _ content: @escaping @MainActor (BackdropModel) -> E)
    throws -> (Window, FakePlatformWindow) {
    let (app, platform) = try shellApp()
    platform.windowsShowBackdrops = honoured
    let window = try app.openWindow(title: "W", size: Size(width: px(64), height: px(64)),
                                    startsDisplayLink: false) { content(model) }
    let fake = try #require(platform.openedWindows.last)
    return (window, fake)
}

/// Whether the scene's first rect is a window-sized fill with lightness `l` and the given alpha.
@MainActor private func firstRectIsFill(_ window: Window, lightness l: Float, alpha: Float) -> Bool {
    guard let r = window.lastScene.rects.first else { return false }
    return r.bounds.size.width == 64 && r.bounds.size.height == 64 && abs(r.background.l - l) < 0.01
        && abs(r.background.a - alpha) < 0.01
}

/// **WB-1** (`WB-A`, `WB-G`). A window that never sets a container background never calls the platform, however
/// many frames it draws, and its scene has no window-sized rect. Mutation: send `.none` on every build (the call
/// count reddens), or paint the fallback unconditionally (the rect arm reddens).
@MainActor
@Test func aWindowWithoutAContainerBackgroundNeverTouchesThePlatformBackdrop() throws {
    let model = BackdropModel()
    let (window, fake) = try openBackdropWindow(model) { _ in Column { box() } }
    for _ in 0..<3 { window.setNeedsRedraw(); window.drawFrameIfNeeded() }
    #expect(fake.windowBackdropRequests.isEmpty, "\(fake.windowBackdropRequests)")
    #expect(!window.lastScene.rects.contains { $0.bounds.size.width == 64 && $0.bounds.size.height == 64 })
}

/// **WB-2** (`WB-A`, `WB-B`, `WB-D`). A material reaches the platform as its level, on change only; the
/// platform drawing it means `Window` paints nothing; removing it sends `.none` once; an inner report beats an
/// outer one and the first sibling beats the second, from any depth. Mutations: level not mapped (levels arm),
/// send every build (count), last report wins (siblings arm), only the root's content counts (depth arm).
@MainActor
@Test func aMaterialContainerBackgroundIsSentAsItsLevelOnChangeOnly() throws {
    let model = BackdropModel()
    let (window, fake) = try openBackdropWindow(model) { m in
        Column {
            if m.mode == 1 { box().containerBackground(.ultraThinMaterial, for: .window) }
            if m.mode == 2 { box().containerBackground(.bar, for: .window) }
            if m.mode == 3 { Column { box().containerBackground(.thickMaterial, for: .window) }
                .containerBackground(.thinMaterial, for: .window) }
            if m.mode == 4 {
                box().containerBackground(.regularMaterial, for: .window)
                box().containerBackground(.ultraThickMaterial, for: .window)
            }
            if m.mode == 5 { box() }
        }
    }
    #expect(fake.windowBackdropRequests.isEmpty)
    model.mode = 1; window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests == [.material(.ultraThin)], "\(fake.windowBackdropRequests)")
    #expect(!window.lastScene.rects.contains { $0.bounds.size.width == 64 && $0.bounds.size.height == 64 },
            "the platform draws it: Window paints no fill")
    model.mode = 2; window.drawFrameIfNeeded()
    model.mode = 3; window.drawFrameIfNeeded()
    model.mode = 4; window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests == [.material(.ultraThin), .material(.bar), .material(.thick),
                                           .material(.regular)], "\(fake.windowBackdropRequests)")
    model.mode = 5; window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests.last == WindowBackdrop.none && fake.windowBackdropRequests.count == 5)
}

/// **WB-3** (`WB-A`). A colour style is the window's background colour, resolved in the window's scheme, with
/// its alpha. Mutation: drop the alpha (the translucent arm), resolve in the light scheme always (the dark arm).
@MainActor
@Test func aColorContainerBackgroundIsTheWindowsBackgroundColor() throws {
    let model = BackdropModel()
    let (window, fake) = try openBackdropWindow(model) { m in
        Column {
            if m.mode == 0 { box().containerBackground(Color(srgb: 0.25, 0.5, 0.75, 0.5), for: .window) }
            if m.mode == 1 { box().containerBackground(Color(light: Color(srgb: 1, 1, 1, 1), dark: Color(srgb: 0, 0, 0, 1)),
                                                      for: .window) }
        }
    }
    #expect(fake.windowBackdropRequests == [.color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)],
            "\(fake.windowBackdropRequests)")
    model.mode = 1; window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests.last == .color(red: 1, green: 1, blue: 1, alpha: 1))
    fake.simulateAppearanceChange(to: .dark)
    window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests.last == .color(red: 0, green: 0, blue: 0, alpha: 1),
            "the dark variant follows the scheme: \(fake.windowBackdropRequests)")
}

/// **WB-4** (`WB-C`; the SDL arm). A platform that cannot show a backdrop answers `false`: `Window` paints the
/// material's opaque grey over the whole content first (light regular: 0.9121; dark: 0.2045), a colour as it
/// is, and the fill goes when the style does. Mutation: no fill (first arm red), the translucent tint instead of
/// the opaque grey (alpha red), fill kept after removal (last arm red).
@MainActor
@Test func aPlatformThatCannotShowTheBackdropGetsAnOpaqueFillFromTheWindow() throws {
    let model = BackdropModel()
    let (window, fake) = try openBackdropWindow(model, honoured: false) { m in
        Column {
            if m.mode == 0 { box().containerBackground(.regularMaterial, for: .window) }
            if m.mode == 1 { box().containerBackground(Color(srgb: 0.2, 0.4, 0.6, 1), for: .window) }
        }
    }
    window.setNeedsRedraw(); window.drawFrameIfNeeded()   // the answer comes after the build: the fill is the frame after
    #expect(fake.windowBackdropRequests == [.material(.regular)])
    #expect(firstRectIsFill(window, lightness: 0.9121, alpha: 1), "the material's opaque grey, light")
    fake.simulateAppearanceChange(to: .dark)
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(firstRectIsFill(window, lightness: 0.2045, alpha: 1), "dark")
    model.mode = 2; window.setNeedsRedraw(); window.drawFrameIfNeeded()
    window.setNeedsRedraw(); window.drawFrameIfNeeded()
    #expect(!window.lastScene.rects.contains { $0.bounds.size.width == 64 && $0.bounds.size.height == 64 },
            "the style left: the fill left with it")
}

/// **WB-5** (`WB-F`). Under Reduce Transparency the platform is sent the opaque grey of the material rather than
/// the blur (the one grey every material site draws), and the blur returns when the setting does; a colour style
/// is unchanged by it. Mutation: ignore the setting (the first arm reddens).
@MainActor
@Test func reduceTransparencyMakesTheWindowBackdropTheMaterialsOpaqueGrey() throws {
    let model = BackdropModel()
    let (window, fake) = try openBackdropWindow(model) { _ in
        Column { box().containerBackground(.regularMaterial, for: .window) }
    }
    #expect(fake.windowBackdropRequests == [.material(.regular)])
    fake.simulateReduceTransparencyChange(to: true)
    window.drawFrameIfNeeded()
    guard case .color(let r, let g, let b, let a)? = fake.windowBackdropRequests.last else {
        Issue.record("no opaque colour sent: \(fake.windowBackdropRequests)"); return
    }
    #expect(abs(r - 0.9121) < 0.01 && r == g && g == b && a == 1)
    fake.simulateReduceTransparencyChange(to: false)
    window.drawFrameIfNeeded()
    #expect(fake.windowBackdropRequests.last == .material(.regular) && fake.windowBackdropRequests.count == 3)
}
