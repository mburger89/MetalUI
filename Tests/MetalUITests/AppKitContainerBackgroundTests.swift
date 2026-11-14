import MetalUITestSupport
import Testing
import Foundation
import Metal
import AppKit
import MetalUICore
@testable import MetalUI
import MetalUIRender
@testable import MetalUIPlatform
@testable import MetalUIAppKit

// The AppKit side of the window's container background (rulings `WB-A`, `WB-B`; record 285). A real
// `AppKitPlatform` window, never ordered on screen: the effect view and the window's flags are read back.
// What the compositor then draws is human check WB1.

@MainActor private final class QuietSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) { handler(false) }
}

@MainActor private func backdropWindow() throws -> (AppKitWindow, NSWindow) {
    let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device; run on macOS hardware")
    installAppKitEventSignal()
    let platform = AppKitPlatform(device: device, accessibilitySignal: { QuietSignal() })
    let platformWindow = try platform.openWindow(title: "Backdrop \(UUID().uuidString)",
                                                 size: Size(width: Pixels(200), height: Pixels(100)))
    let appKit = try #require(platformWindow as? AppKitWindow)
    return (appKit, try #require(appKit.hostView.window))
}

/// The effect views among the window's frame view's direct subviews, **ours** being `backdropEffectView`
/// (AppKit's own title bar carries effect views deeper down).
@MainActor private func effectViews(of window: NSWindow, _ appKit: AppKitWindow) -> [NSVisualEffectView] {
    (window.contentView?.superview?.subviews ?? []).compactMap { $0 as? NSVisualEffectView }
        .filter { $0 === appKit.backdropEffectView }
}

/// **WB-6** (`WB-A`, `WB-B`). A material backdrop puts one behind-window effect view, following the window's
/// active state, in the mapped material, **under** the content view; the window turns non-opaque with a clear
/// background; the metal layer stays non-opaque; the answer is `true`. Mutations: `.withinWindow` blending (the
/// blending arm), no `isOpaque = false` (the window arm), the view added above the content (the order arm), the
/// level mapping collapsed (the table test).
@MainActor
@Test func aMaterialBackdropPutsABehindWindowEffectViewUnderTheContent() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    #expect(window.isOpaque && effectViews(of: window, appKit).isEmpty, "untouched: opaque, no effect view")
    #expect(appKit.setWindowBackdrop(.material(.regular)))
    let view = try #require(effectViews(of: window, appKit).first)
    #expect(effectViews(of: window, appKit).count == 1)
    #expect(view.material == .popover && view.blendingMode == .behindWindow && view.state == .followsWindowActiveState)
    #expect(!window.isOpaque && window.backgroundColor.alphaComponent == 0)
    let siblings = try #require(window.contentView?.superview?.subviews)
    let effectIndex = try #require(siblings.firstIndex { $0 === view })
    let contentIndex = try #require(siblings.firstIndex { $0 === window.contentView })
    #expect(effectIndex < contentIndex, "under the content view")
    #expect(try #require(appKit.hostView.layer as? CAMetalLayer).isOpaque == false, "the metal layer composites with alpha")
    #expect(window.contentView === appKit.hostView, "the content view is untouched")

    #expect(appKit.setWindowBackdrop(.material(.bar)))
    #expect(effectViews(of: window, appKit).count == 1 && effectViews(of: window, appKit).first === view && view.material == .titlebar,
            "a level change updates the one view")
}

/// **WB-7** (`WB-A`). A colour backdrop sets the window's background colour (no effect view), translucent below
/// alpha 1 (non-opaque), opaque at 1; `.none` puts the window's own opaque background back and removes the view.
/// Mutations: `isOpaque` left false at alpha 1, `.none` not restoring the saved colour.
@MainActor
@Test func aColorBackdropSetsTheWindowBackgroundAndNoneRestoresIt() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    let original = window.backgroundColor
    #expect(appKit.setWindowBackdrop(.material(.thin)))
    #expect(appKit.setWindowBackdrop(.color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)))
    #expect(effectViews(of: window, appKit).isEmpty, "a colour is not a material: the view goes")
    #expect(!window.isOpaque)
    let c = try #require(window.backgroundColor.usingColorSpace(.sRGB))
    #expect(abs(c.redComponent - 0.25) < 0.001 && abs(c.greenComponent - 0.5) < 0.001
            && abs(c.blueComponent - 0.75) < 0.001 && abs(c.alphaComponent - 0.5) < 0.001)
    #expect(appKit.setWindowBackdrop(.color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)))
    #expect(window.isOpaque, "alpha 1 is an opaque window")
    #expect(appKit.setWindowBackdrop(.material(.thick)))
    #expect(appKit.setWindowBackdrop(.none))
    #expect(effectViews(of: window, appKit).isEmpty && window.isOpaque && window.backgroundColor == original,
            "the opaque configuration is back")
    #expect(appKit.setWindowBackdrop(.none), "removing twice is harmless")
}

/// **WB-8** (`WB-B`). Each level maps to its own `NSVisualEffectView.Material`, ordered from the most to the least
/// see-through system material. Mutation: two levels sharing a material reddens the distinct count.
@MainActor
@Test func everyBackdropLevelHasItsOwnEffectMaterial() {
    let levels: [WindowBackdropMaterial] = [.ultraThin, .thin, .regular, .thick, .ultraThick, .bar]
    let mapped = levels.map { AppKitWindow.effectMaterial(for: $0) }
    #expect(mapped == [.underWindowBackground, .sidebar, .popover, .sheet, .windowBackground, .titlebar])
    #expect(Set(mapped.map(\.rawValue)).count == 6)
}
