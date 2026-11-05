import Foundation
import MetalUIPlatform

/// What a link click does — SwiftUI's `OpenURLAction` (round 4 item R4-4 PR D; rulings `LI-A`…, divergence 150
/// retired). `Environment(\.openURL)` holds the nearest one. A `Text` link run (a Markdown `[docs](https://…)`,
/// an `AttributedString` with `.link`) calls it on mouse-up over the run; the default asks the window's platform
/// to open the URL (`NSWorkspace.open` on AppKit, `SDL_OpenURL` on SDL).
///
/// ```swift
/// Text("see [docs](https://example.com)")
///     .environment(\.openURL, OpenURLAction { url in
///         router.show(url)
///         return .handled
///     })
/// ```
///
/// **The closure is not comparable, so a writer refuses retention at its position** (`EE-`, `LI-C`): an
/// `.equatable()` subtree below `.environment(\.openURL, …)` is evaluated again each frame, which is how a
/// changed action is never stale. The window's own default is stamped once with an identity reading and costs
/// nothing.
///
/// **`.discarded` and `.handled` do not reach the system** and do not run an outer action either (probe
/// `swiftui-text-links.swift` `LK14b`); only `.systemAction` and `.systemAction(_:)` do.
public struct OpenURLAction {
    /// What a handler did with a URL.
    public struct Result: Sendable {
        enum Kind: Sendable {
            case handled
            case discarded
            case system(URL?)
        }
        let kind: Kind

        /// The handler opened the URL itself; the system does nothing.
        public static let handled = Result(kind: .handled)
        /// The handler declined the URL; the system does nothing.
        public static let discarded = Result(kind: .discarded)
        /// The window's platform opens the URL it was given.
        public static let systemAction = Result(kind: .system(nil))
        /// The window's platform opens `url` instead of the one the handler was given.
        public static func systemAction(_ url: URL) -> Result { Result(kind: .system(url)) }
    }

    let handler: @MainActor (URL) -> Result
    /// The window's opener, put on by `EnvironmentValues.openURL`'s getter; `nil` off a window.
    var opener: URLOpener?

    /// An action that answers every URL with `handler`.
    public init(handler: @escaping @MainActor (URL) -> Result) {
        self.handler = handler
    }

    /// The environment's default: the system opens everything.
    static var system: OpenURLAction { OpenURLAction { _ in .systemAction } }

    /// Runs the handler for `url` and, if it asked for the system, opens it there. `@Environment(\.openURL) var
    /// openURL` then `openURL(url)` calls this.
    @MainActor
    public func callAsFunction(_ url: URL) {
        switch handler(url).kind {
        case .handled, .discarded: break
        case .system(let other): _ = opener?.open(other ?? url)
        }
    }
}

/// Asks one window's platform to open a URL: held weakly by the window's stamped environment, so a handler
/// that outlives the window opens nothing and creates no cycle (`LI-D`).
@MainActor
final class URLOpener {
    private weak var platformWindow: (any PlatformWindow)?

    init(platformWindow: any PlatformWindow) { self.platformWindow = platformWindow }

    func open(_ url: URL) -> Bool { platformWindow?.openURL(url.absoluteString) ?? false }
}

struct OpenURLKey: EnvironmentKey {
    static var defaultValue: OpenURLAction { .system }
}

struct URLOpenerKey: EnvironmentKey {
    static var defaultValue: URLOpener? { nil }
}

extension EnvironmentValues {
    /// The action a link click runs — SwiftUI's `\.openURL`. Written by `.environment(\.openURL, _)`; the nearest
    /// writer wins. Reads the window's opener, so a custom action's `.systemAction` reaches the platform.
    public var openURL: OpenURLAction {
        get {
            var action = self[OpenURLKey.self]
            action.opener = self[URLOpenerKey.self]
            return action
        }
        set { self[OpenURLKey.self] = newValue }
    }

    /// The window's opener, stamped at the root (`LI-D`): an identity reading, so it never makes a position
    /// uncomparable.
    mutating func stampURLOpener(_ opener: URLOpener) {
        setCustom(URLOpenerKey.self, opener, reading: .object(ObjectIdentifier(opener)))
    }
}
