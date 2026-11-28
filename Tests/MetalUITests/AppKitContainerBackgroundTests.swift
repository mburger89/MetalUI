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

/// The effect views among the content view's direct subviews, **ours** being `backdropEffectView`
/// (AppKit's own title bar carries effect views deeper down).
@MainActor private func effectViews(of window: NSWindow, _ appKit: AppKitWindow) -> [NSVisualEffectView] {
    (window.contentView?.subviews ?? []).compactMap { $0 as? NSVisualEffectView }
        .filter { $0 === appKit.backdropEffectView }
}

/// What the window's frame view holds besides effect views, by identity. (AppKit keeps an effect view of its
/// own there while the window is opaque and drops it when it is not; ours is checked separately.)
@MainActor private func frameSubviews(_ window: NSWindow) -> [ObjectIdentifier] {
    (window.contentView?.superview?.subviews ?? []).filter { !($0 is NSVisualEffectView) }.map { ObjectIdentifier($0) }
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
    let siblings = try #require(window.contentView?.subviews)
    let effectIndex = try #require(siblings.firstIndex { $0 === view })
    let hostIndex = try #require(siblings.firstIndex { $0 === appKit.hostView })
    #expect(effectIndex < hostIndex, "under the host view, inside the content view")
    #expect(try #require(appKit.hostView.layer as? CAMetalLayer).isOpaque == false, "the metal layer composites with alpha")

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

/// **WB-9** (`WB-I`). A backdrop puts nothing into AppKit's private frame view: its subviews are what a window
/// without a backdrop has (AppKit's own effect view aside), and none of them is ours, under every style.
/// Mutation: inserting into `contentView.superview`.
@MainActor
@Test func aBackdropNeverChangesTheFrameViewsSubviews() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    let before = frameSubviews(window)
    #expect(!before.isEmpty)
    for backdrop: WindowBackdrop in [.material(.regular), .material(.bar), .color(red: 0, green: 0, blue: 0, alpha: 0.5), .none] {
        #expect(appKit.setWindowBackdrop(backdrop))
        #expect(frameSubviews(window) == before, "\(backdrop)")
        let strays = (window.contentView?.superview?.subviews ?? []).filter { $0 === appKit.backdropEffectView }
        #expect(strays.isEmpty, "\(backdrop)")
    }
}

/// **WB-10** (`WB-I`). The content view is the container holding the host view and, with a material, the
/// effect view below it, both filling it; `.none` takes the effect view out and leaves the host view alone.
/// Mutations: the effect view added above the host, a host view not autoresized.
@MainActor
@Test func theEffectViewSitsInTheContainerBelowTheHostAndNoneRemovesIt() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    let container = try #require(window.contentView)
    #expect(container !== appKit.hostView && appKit.hostView.superview === container)
    #expect(container.subviews.count == 1 && appKit.hostView.frame == container.bounds)
    #expect(appKit.setWindowBackdrop(.material(.thin)))
    let effect = try #require(appKit.backdropEffectView)
    #expect(container.subviews.count == 2 && container.subviews.first === effect && container.subviews.last === appKit.hostView)
    #expect(effect.superview === container && effect.frame == container.bounds)
    container.setFrameSize(NSSize(width: 321, height: 222))
    #expect(effect.frame == container.bounds && appKit.hostView.frame == container.bounds, "both follow a resize")
    #expect(appKit.setWindowBackdrop(.none))
    #expect(effect.superview == nil && container.subviews.count == 1 && container.subviews.first === appKit.hostView)
}

/// **WB-11** (`WB-I`). The host view is the window's first responder after creation and after each backdrop
/// change, and its `initialFirstResponder`. Mutations: no `makeFirstResponder` at creation; a backdrop that
/// moves the responder.
@MainActor
@Test func theHostViewStaysTheFirstResponderThroughBackdropChanges() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    #expect(window.firstResponder === appKit.hostView && window.initialFirstResponder === appKit.hostView)
    for backdrop: WindowBackdrop in [.material(.regular), .color(red: 1, green: 1, blue: 1, alpha: 1), .none] {
        #expect(appKit.setWindowBackdrop(backdrop))
        #expect(window.firstResponder === appKit.hostView, "\(backdrop)")
    }
}

/// **WB-12** (`WB-I`). The container is transparent to accessibility: the window's accessibility children
/// (flattened through ignored views) are the same with a backdrop as without, and never include the container or
/// the effect view. Mutation: the container answering `isAccessibilityElement` true.
@MainActor
@Test func theContainerIsTransparentToAccessibility() throws {
    let (appKit, window) = try backdropWindow()
    defer { window.close() }
    func roles() -> [String] {
        (window.accessibilityChildren() ?? []).map { ($0 as? NSObject).map { "\(type(of: $0))" } ?? "?" }
    }
    let before = roles()
    #expect(window.contentView?.isAccessibilityElement() == false)
    #expect(!before.contains("HostContainerView") && !before.contains("NSVisualEffectView"), "\(before)")
    #expect(appKit.setWindowBackdrop(.material(.regular)))
    #expect(roles() == before, "the same children with a material")
    #expect(appKit.setWindowBackdrop(.none))
    #expect(roles() == before)
    #expect(before == ["MetalHostView", "_NSThemeCloseWidgetCell", "_NSThemeZoomWidgetCell", "_NSThemeWidgetCell",
                       "NSAccessibilityReparentingCellProxy"], "recorded on master before the container")
}

/// **WB-13** (`WB-I`). A window with no backdrop pays nothing per frame for the container: against a control
/// window in the same process with master's shape (the host view set directly as the content view), a steady
/// redraw costs the same element requests and no more allocations (least of eight, interleaved). One extra
/// view at creation is the whole cost. The control makes this a guard: it cannot go red by reverting the fix.
@MainActor
@Test func aWindowWithNoBackdropCostsTheSameSteadyFrameAsBefore() throws {
    let (shippedPlatform, shipped) = try backdropWindow()
    let (controlPlatform, control) = try backdropWindow()
    defer { shipped.close(); control.close() }
    control.contentView = controlPlatform.hostView   // master's shape: no container
    #expect(control.contentView === controlPlatform.hostView && shipped.contentView !== shippedPlatform.hostView)
    func make(_ platform: AppKitWindow) -> (Window, Counted) {
        let counted = Counted()
        let w = Window(platformWindow: platform, startsDisplayLink: false) { Box().frame(width: Pixels(50), height: Pixels(20)) }
        w.testingOnFrameAdopted { counted.requests = $0.elementRequests }
        for _ in 0..<6 { w.setNeedsRedraw(); w.drawFrameIfNeeded() }
        return (w, counted)
    }
    let (a, ac) = make(shippedPlatform)
    let (b, bc) = make(controlPlatform)
    var least = (shipped: Int.max, control: Int.max)
    for _ in 0..<8 {
        least.shipped = min(least.shipped, try #require(countAllocations { a.setNeedsRedraw(); a.drawFrameIfNeeded() }))
        least.control = min(least.control, try #require(countAllocations { b.setNeedsRedraw(); b.drawFrameIfNeeded() }))
    }
    #expect(ac.requests == bc.requests && ac.requests > 0, "\(ac.requests) against \(bc.requests)")
    #expect(least.shipped <= least.control, "allocations: container \(least.shipped), control \(least.control)")
}

@MainActor private final class Counted { var requests = -1 }
