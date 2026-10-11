/// Why a test-harness call could not do what it was asked (ruling `HT-A` item
/// 3): thrown, never trapped, so a failing query fails one test and the run
/// goes on. MetalUI-only (`HT-B`).
public enum TestHarnessError: Error, CustomStringConvertible, Equatable {
    /// No text system was given off Apple platforms, where there is no
    /// CoreText to fall back on (ruling `HT-J`).
    case textSystemRequired
    /// Nothing matched the query, described.
    case noElement(String)
    /// The query described matched `count` elements where one was asked for.
    case ambiguous(String, count: Int)
    /// The element described has no visible area to aim at.
    case notHittable(String)
    /// The window records no layout or accessibility to answer the query
    /// (`recordsLayout` or `accessibilityClientActive` was off).
    case notRecorded(String)
    /// No alert, file dialog, menu or toolbar item of the kind described is
    /// presented.
    case nothingPresented(String)
    /// No menu item lies along the path of titles.
    case noMenuItem([String])
    /// The menu item along the path is disabled.
    case disabledMenuItem([String])
    /// ``TestWindow/runUntilIdle()`` was still drawing after this many rounds.
    case notIdle(rounds: Int)

    /// A sentence naming what failed.
    public var description: String {
        switch self {
        case .textSystemRequired:
            "a text system is required off Apple platforms: there is no CoreText (ruling HT-J)"
        case .noElement(let query):
            "no element matches \(query)"
        case .ambiguous(let query, let count):
            "\(count) elements match \(query); one was expected"
        case .notHittable(let query):
            "\(query) has no visible area to aim at"
        case .notRecorded(let what):
            "the window does not record \(what)"
        case .nothingPresented(let what):
            "no \(what) is presented"
        case .noMenuItem(let path):
            "no menu item at \(path.joined(separator: " > "))"
        case .disabledMenuItem(let path):
            "the menu item at \(path.joined(separator: " > ")) is disabled"
        case .notIdle(let rounds):
            "the window was still drawing after \(rounds) rounds"
        }
    }
}
