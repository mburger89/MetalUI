/// The answer to a close or termination request (rulings `AS-B`, `AS-C`):
/// go ahead now, refuse, or decide later and reply.
///
/// `Window.onCloseRequest` and `App.onTerminateRequest` answer with it, and so
/// does the seam's ``Platform/onTerminateRequest``. After `.later` the request
/// is **pending** until the matching reply — `Window.replyToCloseRequest(_:)`,
/// `App.replyToTerminateRequest(_:)` — so an alert can be shown first and its
/// button decide. MetalUI-only: SwiftUI has no close veto or terminate hook on
/// macOS; the shape is AppKit's `windowShouldClose(_:)` and
/// `applicationShouldTerminate(_:)` with `.terminateLater`.
public enum CloseRequestReply: Sendable, Equatable {
    /// Close (or terminate) now.
    case now
    /// Refuse: the window stays open (the application keeps running) and the
    /// request is forgotten.
    case cancel
    /// Decide later: the request stays pending until a reply answers it. A
    /// pending request that is never answered leaves the window open.
    case later
}

/// A platform window's title-bar style (ruling `AS-E`): the standard bar, or
/// a transparent one with its title hidden, under which the content lays out
/// (`.fullSizeContentView`; the window buttons stay). SDL has no hidden title
/// bar and keeps its system decoration (`AS-E` item 6).
public enum PlatformTitleBarStyle: Sendable, Equatable {
    /// The system's title bar, content below it.
    case standard
    /// A transparent title bar with no title; content extends under it.
    case hidden
}
