import Testing
import Foundation
import MetalUI
import MetalUICore
import MetalUITesting
import MetalUIPlatform

// A steady frame's element requests with a menu-less `TabStrip` and a nested split view (rulings `TBS-O`, `HS-K`; record
// 326). The two features once added requests to every steady frame of an app that used neither feature.

@MainActor private final class StripModel {
    var selected = "a"
    var binding: Binding<String> { Binding(get: { self.selected }, set: { self.selected = $0 }) }
    let tabs = [TabStripItem(id: "a", title: "a.swift"), TabStripItem(id: "b", title: "b.swift"),
                TabStripItem(id: "c", title: "c.swift")]
}

/// Element requests of a steady frame: three redraws of the root, then the last one's count.
@MainActor private func steadyRequests<R: Element>(_ content: @escaping @MainActor () -> R) throws -> Int {
    let w = try TestWindow(size: Size(width: Pixels(600), height: Pixels(400))) { content() }
    defer { withExtendedLifetime(w) {} }
    for _ in 0..<3 { w.window.setNeedsRedraw(); w.advance(by: 0.05) }
    return w.lastFrameWork.elementRequests
}

@MainActor private func stripRequests(menu: Bool = false) throws -> Int {
    let m = StripModel()
    return try steadyRequests {
        VStack(spacing: 0) {
            if menu {
                TabStrip(selection: m.binding, tabs: m.tabs).onCloseTab { _ in }.tabContextMenu { _ in Button("Split") {} }
            } else {
                TabStrip(selection: m.binding, tabs: m.tabs).onCloseTab { _ in }
            }
            Color.red
        }
    }
}

@MainActor private func splitRequests(identifier: Bool = false) throws -> Int {
    try steadyRequests {
        if identifier {
            HSplitView {
                Color.red.frame(minWidth: 50)
                VSplitView { Color.green; Color.blue; Color.gray }.splitViewDividerIdentifier("inner")
                Color.orange
            }.splitViewDividerIdentifier("outer")
        } else {
            HSplitView {
                Color.red.frame(minWidth: 50)
                VSplitView { Color.green; Color.blue; Color.gray }
                Color.orange
            }
        }
    }
}

// Literals measured at MetalUI f9e2af33 (before #327 and #326) with this file's shapes: strip 70, split 39.

/// **1** A strip without `tabContextMenu` costs what it did before `TBS-O` (70 requests; #326 made it 73, one wrapper
/// element per tab). Mutation: `tabContextMenu(_:)` returns a `ContextualModifier` with a menu-less attachment again (73).
@MainActor @Test func aTabStripWithoutAMenuCostsNoExtraRequest() throws {
    #expect(try stripRequests() == 70)
}

/// **2** Nested split views cost no more than before `HS-K`: 35 (39 before #327, 43 after it, one wrapper per divider; the
/// one hit-area wrapper replaces the gesture and pointer wrappers, so one fewer per divider than 39 was). Mutation: add a
/// wrapper (`.accessibilityLabel("x")`) inside the hit area: 39.
@MainActor @Test func nestedSplitViewsCostNoExtraRequestPerDivider() throws {
    #expect(try splitRequests() == 35)
}

/// **3** Dividers with identifiers cost the same as without: the identifier rides the one hit-area wrapper.
@MainActor @Test func dividerIdentifiersCostNoRequest() throws {
    #expect(try splitRequests(identifier: true) == splitRequests())
}

/// **4** A strip WITH a menu costs the same as without (`TBS-Q`: the menu rides the middle-button gesture wrapper's and the
/// label's accessibility wrapper's registrations). Mutation: wrap the cell in a `ContextualModifier` when there is a menu (73).
@MainActor @Test func aTabStripWithAMenuCostsNoExtraRequest() throws {
    let without = try stripRequests(), with = try stripRequests(menu: true)
    #expect(with - without == 0, "without \(without), with \(with)")
}
