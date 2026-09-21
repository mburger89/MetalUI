// Typecheck probe: every NSAccessibility override and notification spelling
// the accessibility-bridge spec's lane 2 names, on an NSView subclass
// extension and an NSAccessibilityElement subclass, plus the NSWorkspace
// VoiceOver observation AB-B uses. Nothing here runs; it is compiled only.
// Committed because the design session's first typecheck was a scratch file
// (critic finding 14): this is that check, re-runnable.
//
// HOW TO RUN:
//
//   xcrun swiftc -typecheck -swift-version 6 -warnings-as-errors \
//     docs/probes/appkit-accessibility-overrides-typecheck.swift; echo "exit=$?"
//
// POSITIVE CONTROL. Uncomment the `NEGATIVE CONTROL` method below: it spells
// `accessibilityFocusedUIElement` as a method, the first spelling the design
// session guessed, and must fail with "method does not override any method
// from its superclass". A typecheck that accepts it is not checking overrides.
//
// RECORDED 2026-09-15, macOS 26.6.2 (25G83), Apple Swift 6.4
// (swiftlang-6.4.0.33.1):
//
//   as committed:              exit=0, no output
//   with NEGATIVE CONTROL on:  :41:19: error: method does not override any method from its superclass
//                              :41:19: error: invalid redeclaration of 'accessibilityFocusedUIElement()'

import AppKit

final class HostView: NSView {
    override var isFlipped: Bool { true }
    // The one stored property lane 2 adds lives in the class body; overrides
    // compile in an extension.
    var bridgeToken: AnyObject?
}

extension HostView {
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? { self }
    override var accessibilityFocusedUIElement: Any? { self }
    // NEGATIVE CONTROL:
    // override func accessibilityFocusedUIElement() -> Any? { self }
}

final class Element: NSAccessibilityElement {
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { nil }
    override func accessibilityValue() -> Any? { nil }
    override func accessibilityParent() -> Any? { nil }
    override func accessibilityChildren() -> [Any]? { [] }
    override func accessibilityFrame() -> NSRect { .zero }
    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { true }
    override func isAccessibilitySelected() -> Bool { false }
    override func accessibilityRowCount() -> Int { 0 }
    override func accessibilityRows() -> [Any]? { [] }
    override func accessibilityVisibleRows() -> [Any]? { [] }
    override func accessibilityIndex() -> Int { 0 }
    override func isAccessibilityFocused() -> Bool { false }
    override func setAccessibilityFocused(_ focused: Bool) {}
    override func accessibilityPerformPress() -> Bool { false }
    override func accessibilityPerformIncrement() -> Bool { false }
    override func accessibilityPerformDecrement() -> Bool { false }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool { false }
}

@MainActor func notificationSpellings(_ element: Any) {
    for name: NSAccessibility.Notification in [.uiElementDestroyed, .layoutChanged, .titleChanged,
                                               .valueChanged, .rowCountChanged,
                                               .focusedUIElementChanged] {
        NSAccessibility.post(element: element, notification: name)
    }
}

@MainActor func voiceOverObservation() -> NSKeyValueObservation {
    NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.initial, .new]) { workspace, _ in
        _ = workspace.isVoiceOverEnabled
    }
}
