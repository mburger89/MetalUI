import Testing
import Foundation
@testable import MetalUIAppKit

// The AppKit half of the link seam (`LI-D`). **Nothing here calls `AppKitWindow.openURL(_:)` or `NSWorkspace`**: past
// the refusal it would launch the user's browser. The part that can be tested is which strings are refused before that.

/// A string with no scheme is refused before `NSWorkspace` sees it; any scheme (custom ones, `mailto:`) passes.
/// Mutation: drop the scheme check (the bare words read non-nil).
@MainActor
@Test func appKitHandsNSWorkspaceOnlyAbsoluteURLs() {
    for refused in ["example.com", "", "just words", "/Users/me/file", "//host/path", ":x"] {
        #expect(AppKitWindow.workspaceURL(for: refused) == nil, "\"\(refused)\" is refused")
    }
    for accepted in ["https://x.org", "http://x.org/a?b=c", "mailto:a@b.org", "probe://x", "file:///tmp/a"] {
        #expect(AppKitWindow.workspaceURL(for: accepted)?.absoluteString == accepted, "\"\(accepted)\" passes as written")
    }
}
